defmodule Mooncore.Dev.Page do
  @moduledoc false

  @external_resource Path.join(__DIR__, "page.html")
  @html File.read!(Path.join(__DIR__, "page.html"))

  def render, do: @html
end
