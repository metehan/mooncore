defmodule Mooncore.MixProject do
  use Mix.Project

  @version "0.2.3"
  @source_url "https://github.com/metehan/mooncore"

  def project do
    [
      app: :mooncore,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "A lightweight, action-based api framework for Elixir.",
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Mooncore.Application, []}
    ]
  end

  defp deps do
    [
      {:bandit, "~> 1.1"},
      {:plug, "~> 1.15"},
      {:jason, "~> 1.4"},
      {:cors_plug, "~> 3.0"},
      {:websock_adapter, "~> 0.5"},
      {:joken, "~> 2.6"},
      {:manifold, "~> 1.6"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "guides/introduction.md",
        "guides/philosophy.md",
        "guides/getting-started.md",
        "guides/actions.md",
        "guides/authentication.md",
        "guides/websockets.md",
        "guides/middleware.md",
        "guides/devtools.md",
        "guides/mcp.md",
        "guides/skills.md",
        "guides/deployment.md"
      ],
      groups_for_extras: [
        Guides: Path.wildcard("guides/*.md")
      ]
    ]
  end
end
