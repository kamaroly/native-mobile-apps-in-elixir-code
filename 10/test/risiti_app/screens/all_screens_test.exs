defmodule RisitiApp.Screens.AllScreensTest do
  use Mob.ScreenCase, async: false

  import RisitiApp.ScreenHelpers

  alias RisitiApp.Screens.{ReceiptFormScreen, ReceiptsScreen, SettingsScreen}

  # Every screen, with the params it needs to mount. Add new screens here.
  @screens [
    {ReceiptsScreen, %{}},
    {ReceiptFormScreen, %{}},
    {ReceiptFormScreen, %{id: 1}},
    {SettingsScreen, %{}}
  ]

  for {screen, params} <- @screens do
    test "#{inspect(screen)} #{inspect(params)} renders a tree the phone can draw" do
      view = mount_screen(unquote(screen), unquote(Macro.escape(params)))
      assert_renderable(rendered(view))
    end

    test "#{inspect(screen)} #{inspect(params)} ignores unexpected messages" do
      view = mount_screen(unquote(screen), unquote(Macro.escape(params)))
      view = render_info(view, {:something, :unexpected})
      assert_renderable(rendered(view))
    end
  end
end
