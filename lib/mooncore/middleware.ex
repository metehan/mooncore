defmodule Mooncore.Middleware do
  @moduledoc """
  Behaviour for action middleware.

  Middlewares are called before and after action execution,
  allowing you to modify the request map or response.

  ## Before Middleware

  Receives the request map, must return a (possibly modified) request map.

      defmodule MyApp.Middleware.DBLink do
        @behaviour Mooncore.Middleware

        @impl true
        def call(req) do
          db = MyApp.DB.link(req[:auth]["dkey"])
          Map.put(req, :db, db)
        end
      end

  ## After Middleware

  Receives the response from the action handler, must return a (possibly modified) response.

      defmodule MyApp.Middleware.StripPassword do
        @behaviour Mooncore.Middleware

        @impl true
        def call(response) when is_map(response) do
          Map.delete(response, "password")
        end
        def call(response), do: response
      end

  Configure in:

      config :mooncore,
        before_action: [MyApp.Middleware.DBLink],
        after_action: [MyApp.Middleware.StripPassword]
  """

  @callback call(map() | any()) :: map() | any()
end
