defmodule RisitiApp.Screens.LockAndGalleryTest do
  use Mob.ScreenCase, async: false

  import RisitiApp.ScreenHelpers

  alias RisitiApp.AppLock
  alias RisitiApp.Receipts.Photos
  alias RisitiApp.Screens.{ReceiptFormScreen, ReceiptsScreen, SettingsScreen}

  setup :checkout_repo

  describe "the app lock" do
    test "is off until switched on in Settings" do
      refute AppLock.enabled?()

      SettingsScreen |> mount_screen() |> render_info({:change, :app_lock, true})

      assert AppLock.enabled?()
    end

    test "a locked book asks for a fingerprint and shows nothing else" do
      AppLock.set(true)
      insert_transaction(vendor: "Naivas")

      view = mount_screen(ReceiptsScreen)

      assert_received {:native, :authenticate, ["Unlock your receipts"]}
      assert text(rendered(view)) =~ "Receipts are locked"
      refute text(rendered(view)) =~ "Naivas"
    end

    test "a recognised fingerprint unlocks it" do
      AppLock.set(true)
      insert_transaction(vendor: "Naivas")

      view = ReceiptsScreen |> mount_screen() |> render_info({:biometric, :success})

      assert text(rendered(view)) =~ "Naivas"
    end

    test "a failed check stays locked; a phone without biometrics doesn't lock you out" do
      AppLock.set(true)

      failed = ReceiptsScreen |> mount_screen() |> render_info({:biometric, :failure})
      assert assigns(failed).locked

      no_sensor = ReceiptsScreen |> mount_screen() |> render_info({:biometric, :not_available})
      refute assigns(no_sensor).locked
    end
  end

  describe "the photo viewer" do
    @tag :tmp_dir
    test "opens full screen and saves to the gallery", context do
      tmp = Path.join(context.tmp_dir, "camera.jpg")
      File.write!(tmp, "not really a jpeg")
      receipt = insert_transaction(photo_path: Photos.keep(tmp))
      path = Photos.path(receipt.photo_path)

      view =
        ReceiptFormScreen
        |> mount_screen(%{id: receipt.id})
        |> render_info({:tap, :view_photo})

      assert find(rendered(view), :image, src: path)
      refute text(rendered(view)) =~ "Date on receipt"

      render_info(view, {:tap, :save_photo})
      assert_received {:native, :save_to_gallery, [^path]}

      render_info(view, {:storage, :saved_to_library, path})
      assert_received {:native, :toast, ["Saved to your phone's gallery"]}
    end
  end
end
