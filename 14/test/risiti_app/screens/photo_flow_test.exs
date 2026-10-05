defmodule RisitiApp.Screens.PhotoFlowTest do
  use Mob.ScreenCase

  import RisitiApp.ScreenHelpers

  alias RisitiApp.Receipts.Photos
  alias RisitiApp.Screens.{ReceiptFormScreen, ReceiptsScreen}
  alias RisitiApp.Transactions

  setup :checkout_repo

  # Stands in for the temporary file the camera writes.
  defp camera_file(context) do
    path = Path.join(context.tmp_dir, "camera.jpg")
    File.write!(path, "not really a jpeg")
    path
  end

  test "Scan receipt asks for the camera, then opens it" do
    view = ReceiptsScreen |> mount_screen() |> render_info({:tap, :take_photo})
    assert_received {:native, :request_camera, []}

    render_info(view, {:permission, :camera, :granted})
    assert_received {:native, :take_photo, []}
  end

  @tag :tmp_dir
  test "a photo opens the form, which keeps a copy of it", context do
    tmp = camera_file(context)

    view =
      ReceiptsScreen
      |> mount_screen()
      |> render_info({:camera, :photo, %{path: tmp, width: 1600, height: 1200}})

    assert {:push, ReceiptFormScreen, %{photo: ^tmp}} = view.socket.__mob__.nav_action

    form = mount_screen(ReceiptFormScreen, %{photo: tmp})
    name = assigns(form).receipt.photo_path

    assert name =~ ~r/^receipt-\d+-\d+\.jpg$/
    assert File.read!(Photos.path(name)) == "not really a jpeg"
    assert find(rendered(form), :image, src: Photos.path(name))
  end

  @tag :tmp_dir
  test "saving stores the photo's name on the transaction", context do
    view =
      ReceiptFormScreen
      |> mount_screen(%{photo: camera_file(context)})
      |> render_info({:change, :vendor, "Naivas"})
      |> render_info({:change, :amount, "1,250"})
      |> render_info({:tap, :save})

    assert navigated_to(view) == ReceiptsScreen
    assert [%{photo_path: name, source: "photo"}] = Transactions.list_transactions()
    assert Photos.exists?(name)
  end

  @tag :tmp_dir
  test "backing out of a new receipt deletes its photo", context do
    form = mount_screen(ReceiptFormScreen, %{photo: camera_file(context)})
    name = assigns(form).receipt.photo_path

    render_info(form, {:tap, :back})

    refute Photos.exists?(name)
  end

  @tag :tmp_dir
  test "deleting a transaction deletes its photo", context do
    name = Photos.keep(camera_file(context))
    receipt = insert_transaction(photo_path: name)

    {:ok, _} = Transactions.delete_transaction(receipt)

    refute Photos.exists?(name)
  end
end
