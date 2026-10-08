defmodule RisitiApp.Screens.AllScreensTest do
  use Mob.ScreenCase, async: false

  import RisitiApp.ScreenHelpers

  alias RisitiApp.Screens.{
    DateRangeScreen,
    ReceiptFormScreen,
    ReceiptsScreen,
    RequestFormScreen,
    SettingsScreen
  }

  setup :checkout_repo

  setup do
    [id: insert_transaction().id]
  end

  # Every screen, with the params it needs to mount. Add new screens here.
  # `:id` is filled in from the transaction saved above.
  @screens [
    {ReceiptsScreen, %{}},
    {ReceiptFormScreen, %{}},
    {ReceiptFormScreen, %{id: :id}},
    {ReceiptFormScreen,
     %{
       qr:
         "https://etims.kra.go.ke/common/link/etims/receipt/indexEtimsReceiptData?Data=P051234567X00ABC123"
     }},
    {RequestFormScreen, %{}},
    {RequestFormScreen, %{refund_of: :id}},
    {SettingsScreen, %{}},
    {DateRangeScreen, %{}}
  ]

  for {screen, params} <- @screens do
    test "#{inspect(screen)} #{inspect(params)} renders a tree the phone can draw", context do
      view = mount_screen(unquote(screen), params(unquote(Macro.escape(params)), context))
      assert_renderable(rendered(view))
    end

    test "#{inspect(screen)} #{inspect(params)} ignores unexpected messages", context do
      view = mount_screen(unquote(screen), params(unquote(Macro.escape(params)), context))
      view = render_info(view, {:something, :unexpected})
      assert_renderable(rendered(view))
    end
  end

  defp params(params, context) do
    Map.new(params, fn
      {key, :id} -> {key, context.id}
      pair -> pair
    end)
  end
end
