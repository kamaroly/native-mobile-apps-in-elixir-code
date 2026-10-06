defmodule RisitiApp.Screens.PhotoFlowTest do
  use Mob.ScreenCase

  import RisitiApp.ScreenHelpers

  alias RisitiApp.Receipts.Photos
  alias RisitiApp.Screens.{ReceiptFormScreen, ReceiptsScreen}
  alias RisitiApp.Transactions

  setup :checkout_repo

  @receipt_text """
  JAVA HOUSE
  Junction Mall, Ngong Rd
  GRAND TOTAL KES  1,650.00
  Served on 5 Sep 2026  13:05
  """

  # Stands in for the temporary file the camera writes.
  defp camera_file(context) do
    path = Path.join(context.tmp_dir, "camera.jpg")
    File.write!(path, "not really a jpeg")
    path
  end

  # Does what MobOcr does on the phone: writes the kept photo to `dest`,
  # then answers with what it read.
  defp read_by_phone(view, text) do
    assert_received {:native, :process_photo, [_tmp, dest]}
    File.mkdir_p!(Path.dirname(dest))
    File.write!(dest, "the upright copy")

    json = IO.iodata_to_binary(:json.encode(%{"text" => text, "qr" => :null, "path" => dest}))
    render_info(view, {:ocr, :result, json})
  end

  test "Scan receipt asks for the camera, then opens it" do
    view = ReceiptsScreen |> mount_screen() |> render_info({:tap, :take_photo})
    assert_received {:native, :request_camera, []}

    render_info(view, {:permission, :camera, :granted})
    assert_received {:native, :take_photo, []}
  end

  @tag :tmp_dir
  test "a photo opens the form, which asks the phone to read it", context do
    tmp = camera_file(context)

    view =
      ReceiptsScreen
      |> mount_screen()
      |> render_info({:camera, :photo, %{path: tmp, width: 1600, height: 1200}})

    assert {:push, ReceiptFormScreen, %{photo: ^tmp}} = view.socket.__mob__.nav_action

    form = mount_screen(ReceiptFormScreen, %{photo: tmp})

    assert_received {:native, :process_photo, [^tmp, dest]}
    assert Path.dirname(dest) == Photos.dir()
    assert assigns(form).reading
    assert text(rendered(form)) =~ "Reading receipt…"
  end

  @tag :tmp_dir
  test "what's read fills the form, and says what it found", context do
    form =
      ReceiptFormScreen
      |> mount_screen(%{photo: camera_file(context)})
      |> read_by_phone(@receipt_text)

    assert %{vendor: "Java House", date: "2026-09-05", amount: "1650.00", reading: false} =
             assigns(form)

    assert Photos.exists?(assigns(form).receipt.photo_path)
    assert text(rendered(form)) =~ "Read the vendor, date, total from the photo."
  end

  @tag :tmp_dir
  test "a reading never overwrites what was typed", context do
    form =
      ReceiptFormScreen
      |> mount_screen(%{photo: camera_file(context)})
      |> render_info({:change, :vendor, "Java House Junction"})
      |> read_by_phone(@receipt_text)

    assert %{vendor: "Java House Junction", amount: "1650.00"} = assigns(form)
  end

  @tag :tmp_dir
  test "Save waits for the reading to finish", context do
    form =
      ReceiptFormScreen
      |> mount_screen(%{photo: camera_file(context)})
      |> render_info({:tap, :save})

    assert navigated_to(form) == nil
    assert text(rendered(form)) =~ "Reading receipt…"
  end

  @tag :tmp_dir
  test "saving keeps the photo and the text read off it", context do
    view =
      ReceiptFormScreen
      |> mount_screen(%{photo: camera_file(context)})
      |> read_by_phone(@receipt_text)
      |> render_info({:tap, :save})

    assert navigated_to(view) == ReceiptsScreen

    assert [%{vendor: "Java House", source: "ocr", photo_path: name, ocr_text: @receipt_text}] =
             Transactions.list_transactions()

    assert Photos.exists?(name)
  end

  test "a failed reading says so, and keeps the photo it saved" do
    dest = Photos.new_path()
    File.mkdir_p!(Path.dirname(dest))
    File.write!(dest, "saved before the reading failed")
    json = IO.iodata_to_binary(:json.encode(%{"message" => "boom", "path" => dest}))

    form =
      ReceiptFormScreen
      |> mount_screen(%{photo: "/tmp/camera.jpg"})
      |> render_info({:ocr, :error, json})

    assert assigns(form).receipt.photo_path == Photos.name(dest)
    assert assigns(form).receipt.source == "photo"
    assert text(rendered(form)) =~ "Couldn't read the text in this photo."
  end

  @tag :tmp_dir
  test "backing out of a new receipt deletes its photo", context do
    form =
      ReceiptFormScreen
      |> mount_screen(%{photo: camera_file(context)})
      |> read_by_phone(@receipt_text)

    name = assigns(form).receipt.photo_path
    render_info(form, {:tap, :back})

    refute Photos.exists?(name)
  end

  @tag :tmp_dir
  test "a retaken photo replaces the old one only when saved", context do
    old = Photos.keep(camera_file(context))
    receipt = insert_transaction(vendor: "Java House", photo_path: old)

    form =
      ReceiptFormScreen
      |> mount_screen(%{id: receipt.id})
      |> render_info({:tap, :take_photo})
      |> render_info({:permission, :camera, :granted})
      |> render_info({:camera, :photo, %{path: camera_file(context)}})
      |> read_by_phone(@receipt_text)

    new = assigns(form).receipt.photo_path
    assert new != old
    assert Photos.exists?(old), "the saved photo stays until the edit is saved"

    render_info(form, {:tap, :save})

    refute Photos.exists?(old)
    assert Transactions.get_transaction!(receipt.id).photo_path == new
  end

  @tag :tmp_dir
  test "removing the photo from a saved receipt", context do
    old = Photos.keep(camera_file(context))
    receipt = insert_transaction(vendor: "Java House", photo_path: old, source: "photo")

    ReceiptFormScreen
    |> mount_screen(%{id: receipt.id})
    |> render_info({:tap, :remove_photo})
    |> render_info({:tap, :save})

    assert %{photo_path: nil, source: "manual"} = Transactions.get_transaction!(receipt.id)
    refute Photos.exists?(old)
  end

  @tag :tmp_dir
  test "deleting a transaction deletes its photo", context do
    name = Photos.keep(camera_file(context))
    receipt = insert_transaction(photo_path: name)

    {:ok, _} = Transactions.delete_transaction(receipt)

    refute Photos.exists?(name)
  end
end
