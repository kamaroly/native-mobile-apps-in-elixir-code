defmodule RisitiApp.Components do
  @moduledoc "Registers the app's own tags, so screens can write <Header />, <TransactionItem /> and the rest."

  @composites [
    header: RisitiApp.Components.Header,
    transaction_item: RisitiApp.Components.TransactionItem,
    search_field: RisitiApp.Components.SearchField,
    transaction_sheet: RisitiApp.Components.TransactionSheet
  ]

  def register_all do
    Enum.each(@composites, fn {tag, module} ->
      Mob.Composite.register(tag, {module, :expand})
    end)
  end
end
