RisitiApp.Components.register_all()

defmodule RisitiApp.ScreenHelpers do
  @moduledoc "Expands a screen's tree the way Mob does on the device."

  import Mob.ScreenCase, only: [tree: 1]

  def rendered(view) do
    renderers = view.socket.__mob__[:list_renderers] || %{}

    view
    |> tree()
    |> Mob.Composite.expand(self())
    |> Mob.List.expand(renderers, self())
  end
end

ExUnit.start()
