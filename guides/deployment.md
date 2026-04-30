# Deployment

Mooncore runs on Bandit (a pure-Elixir HTTP server) and follows standard Elixir deployment practices. There's no special deployment tooling — if you can deploy an Elixir application, you can deploy Mooncore.

## Release Configuration

### Environment-Specific Config

```elixir
# config/config.exs — shared
import Config

config :mooncore,
  router: MyApp.Router,
  app_module: MyApp.App,
  pools: [:default],
  before_action: [MyApp.Middleware.DB],
  after_action: []

# config/dev.exs
import Config

config :mooncore,
  port: 4000,
  mooncore_dev_tools: true,
  jwt: [
    key: File.read!("priv/dev_key.pem"),
    issuer: "myapp-dev"
  ]

# config/prod.exs
import Config

config :mooncore,
  mooncore_dev_tools: false  # always false in production

# config/runtime.exs — runtime secrets
import Config

if config_env() == :prod do
  config :mooncore,
    port: String.to_integer(System.get_env("PORT") || "4000"),
    jwt: [
      key: System.get_env("JWT_PRIVATE_KEY") || raise("JWT_PRIVATE_KEY not set"),
      issuer: System.get_env("JWT_ISSUER") || "myapp"
    ]
end
```

### Building a Release

```bash
MIX_ENV=prod mix release
```

### Running

```bash
_build/prod/rel/my_app/bin/my_app start
```

## Docker

```dockerfile
FROM elixir:1.17-alpine AS build

WORKDIR /app

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

COPY lib lib/
COPY config config/
RUN mix compile
RUN mix release

# Runtime
FROM alpine:3.19

RUN apk add --no-cache libstdc++ ncurses-libs openssl

WORKDIR /app
COPY --from=build /app/_build/prod/rel/my_app ./

ENV PORT=4000
EXPOSE 4000

CMD ["bin/my_app", "start"]
```

## Environment Variables

| Variable              | Description                                                                                    |
| --------------------- | ---------------------------------------------------------------------------------------------- |
| `PORT`                | HTTP listening port                                                                            |
| `JWT_PRIVATE_KEY`     | RSA private key PEM for JWT signing                                                            |
| `JWT_ISSUER`          | JWT issuer claim                                                                               |
| `SECRET_KEY_BASE`     | For cookie signing if you use Plug sessions                                                    |
| `MOONCORE_DEV_SECRET` | Password for dev dashboard login. Also accepted as `x-dev-secret` query param for MCP clients. |

### Why Two Gates?

Dev tools require both `config :mooncore, mooncore_dev_tools: true` AND `MOONCORE_DEV_SECRET` set to a non-empty value. This prevents accidental exposure in production — even if a config file is misconfigured or copied from dev, the environment variable acts as a second safety gate. The config says "this environment is allowed to have dev tools" and the secret says "this specific deployment instance has dev tools turned on."

## Health Checks

Add a health endpoint in your router:

```elixir
get "/health" do
  send_resp(conn, 200, "ok")
end
```

For a deeper health check:

```elixir
get "/health" do
  checks = %{
    database: MyApp.DB.healthy?(),
    pools: Mooncore.config(:pools, []) |> length()
  }

  status = if checks.database, do: 200, else: 503

  conn
  |> put_resp_content_type("application/json")
  |> send_resp(status, Jason.encode!(checks))
end
```

## Production Checklist

- [ ] `mooncore_dev_tools: false` — never expose dev tools in production
- [ ] `dev_tools_allowed_ips` restricts dev tools to known IPs (if dev tools are enabled)
- [ ] JWT private key loaded from environment variable, not committed to repo
- [ ] CORS origins restricted to your domains (not `["*"]`)
- [ ] Plug.Logger or custom logging configured
- [ ] Health check endpoint available for load balancers
- [ ] `start_permanent: Mix.env() == :prod` in mix.exs (crashes restart the app)

## Scaling

Mooncore is a single-node framework. Each instance runs independently with its own client registry and watcher state.

For horizontal scaling:

- **Stateless actions** work across instances behind a load balancer with no changes
- **WebSocket connections** are pinned to a single instance — use sticky sessions or connection-aware routing
- **Pub/sub** is local to each instance — for cross-node broadcasting, integrate an external pub/sub system (Redis, NATS, etc.) in a middleware or custom broadcaster
- **Client registry** is local — for global client awareness, sync state through an external store

Mooncore doesn't impose a clustering solution. Use what fits your infrastructure.
