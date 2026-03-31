defmodule Mooncore.App do
  @moduledoc """
  Behaviour for the app registry.

  Users implement this to register their apps with their roles and action modules.
  Configure via `config :mooncore, app_module: MyApp.App`.

  ## Example

      defmodule MyApp.App do
        @behaviour Mooncore.App

        @impl true
        def list do
          %{
            "myapp" => %{
              key: "myapp",
              name: "My Application",
              roles: MyApp.Roles.list(),
              action_module: MyApp.Action
            }
          }
        end

        @impl true
        def info(app_name), do: Map.get(list(), app_name)
      end
  """

  @callback list() :: map()
  @callback info(String.t()) :: map() | nil

  @doc "Get app info using the configured app_module."
  def info(app_name) do
    case Mooncore.config(:app_module) do
      nil -> nil
      mod -> mod.info(app_name)
    end
  end

  @doc "List all apps using the configured app_module."
  def list do
    case Mooncore.config(:app_module) do
      nil -> %{}
      mod -> mod.list()
    end
  end
end
