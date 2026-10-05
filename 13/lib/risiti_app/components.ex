defmodule RisitiApp.Components do
  @moduledoc "Registers the app's own tags, so screens can write <Header /> and <TransactionItem />."

  @composites [
    header: RisitiApp.Components.Header,
    transaction_item: RisitiApp.Components.TransactionItem
  ]

  def register_all do
    Enum.each(@composites, fn {tag, module} ->
      Mob.Composite.register(tag, {module, :expand})
    end)
  end
end
