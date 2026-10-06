defmodule RisitiApp.Screens.KraFlowTest do
  use Mob.ScreenCase

  import RisitiApp.ScreenHelpers

  alias RisitiApp.Screens.{ReceiptFormScreen, ReceiptsScreen}
  alias RisitiApp.Transactions

  setup :checkout_repo

  @etims "https://etims.kra.go.ke/common/link/etims/receipt/indexEtimsReceiptData?Data=P051234567X00ABCDEF0123456789"

  # What KraReceipt.parse/1 makes of KRA's page for this receipt.
  @details %{
    vendor: "Stabex International Limited",
    date: ~D[2026-09-24],
    amount_cents: 199_845,
    description: "Unleaded",
    invoice_number: "KRACU0300010612/58385"
  }

  defp insert_kra_receipt(attrs \\ %{}) do
    insert_transaction(
      Map.merge(
        %{vendor: "Stabex", source: "etims", qr_content: @etims, verify_url: @etims},
        Map.new(attrs)
      )
    )
  end

  describe "scanning from the home screen" do
    test "QR opens the scanner, and a new code opens the form" do
      view = ReceiptsScreen |> mount_screen() |> render_info({:tap, :scan_qr})
      assert_received {:native, :scan_qr, []}

      view = render_info(view, {:scan, :result, %{type: :qr, value: @etims}})
      assert {:push, ReceiptFormScreen, %{qr: @etims}} = view.socket.__mob__.nav_action
    end

    test "a code that's already saved opens that receipt instead" do
      saved = insert_kra_receipt(verified_at: ~U[2026-09-24 10:00:00Z])

      view =
        ReceiptsScreen
        |> mount_screen()
        |> render_info({:scan, :result, %{type: :qr, value: @etims}})

      assert navigated_to(view) == nil
      assert assigns(view).selected.id == saved.id
      assert_received {:native, :toast, ["You already saved this receipt"]}
    end
  end

  describe "the form, from a scanned code" do
    test "asks KRA for the receipt, and the camera for a photo of it" do
      form = mount_screen(ReceiptFormScreen, %{qr: @etims})

      assert_received {:native, :lookup_kra, [@etims]}
      assert_received {:native, :request_camera, []}
      assert assigns(form).receipt.seller_pin == "P051234567X"
      assert text(rendered(form)) =~ "Getting this receipt's details from KRA…"
      assert text(rendered(form)) =~ "KRA eTIMS receipt"
    end

    test "KRA's record fills the form and verifies the receipt" do
      form =
        ReceiptFormScreen
        |> mount_screen(%{qr: @etims})
        |> render_info({:change, :description, "Fuel for the site visit"})
        |> render_info({:kra, :result, @details})

      assert %{
               vendor: "Stabex International Limited",
               date: "2026-09-24",
               amount: "1998.45",
               description: "Fuel for the site visit"
             } = assigns(form)

      assert assigns(form).receipt.verified_at
      assert text(rendered(form)) =~ "Verified with KRA"
    end

    test "a photo read afterwards doesn't overwrite what KRA said" do
      form =
        ReceiptFormScreen
        |> mount_screen(%{qr: @etims})
        |> render_info({:kra, :result, @details})
        |> render_info({:camera, :photo, %{path: "/tmp/camera.jpg"}})

      assert_received {:native, :process_photo, [_tmp, dest]}

      json =
        IO.iodata_to_binary(
          :json.encode(%{
            "text" => "STABEX\nTOTAL  1,000.00\nDate: 01/09/2026",
            "qr" => :null,
            "path" => dest
          })
        )

      form = render_info(form, {:ocr, :result, json})

      assert %{vendor: "Stabex International Limited", amount: "1998.45"} = assigns(form)
      assert text(rendered(form)) =~ "Verified with KRA"
    end

    test "if KRA can't be reached, the form says so and can still be saved" do
      view =
        ReceiptFormScreen
        |> mount_screen(%{qr: @etims})
        |> render_info({:kra, :error, :timeout})

      assert text(rendered(view)) =~ "Couldn't get this receipt from KRA"

      view =
        view
        |> render_info({:change, :vendor, "Stabex"})
        |> render_info({:change, :amount, "1998.45"})
        |> render_info({:tap, :save})

      assert navigated_to(view) == ReceiptsScreen

      assert [%{source: "etims", qr_content: @etims, seller_pin: "P051234567X", verified_at: nil}] =
               Transactions.list_transactions()
    end

    test "KRA having no record isn't blamed on the connection" do
      form =
        ReceiptFormScreen
        |> mount_screen(%{qr: @etims})
        |> render_info({:kra, :error, :unrecognised})

      assert text(rendered(form)) =~ "KRA has no record of this receipt yet."
      refute text(rendered(form)) =~ "connection"
    end

    test "a QR code found in the photo is looked up too" do
      form = mount_screen(ReceiptFormScreen, %{photo: "/tmp/camera.jpg"})
      assert_received {:native, :process_photo, [_tmp, dest]}

      json =
        IO.iodata_to_binary(:json.encode(%{"text" => "STABEX", "qr" => @etims, "path" => dest}))

      form = render_info(form, {:ocr, :result, json})

      assert assigns(form).receipt.source == "etims"
      assert_received {:native, :lookup_kra, [@etims]}
    end

    test "scanning a code that's already saved warns straight away" do
      insert_kra_receipt()

      form = mount_screen(ReceiptFormScreen, %{qr: @etims})

      assert text(rendered(form)) =~ "You already saved this receipt (Stabex"
    end
  end

  describe "checking saved receipts with KRA" do
    test "the home screen quietly checks an unverified receipt" do
      receipt = insert_kra_receipt()

      view = mount_screen(ReceiptsScreen)
      id = receipt.id
      assert_received {:native, :lookup_kra, [@etims, {:verify, ^id}]}

      render_info(view, {:kra, :result, @details, {:verify, id}})

      assert Transactions.get_transaction!(id).verified_at
      refute_received {:native, :toast, _}
    end

    test "a receipt KRA couldn't answer for isn't retried on the same visit" do
      receipt = insert_kra_receipt()
      id = receipt.id

      view = mount_screen(ReceiptsScreen)
      assert_received {:native, :lookup_kra, [_, {:verify, ^id}]}

      render_info(view, {:kra, :error, :timeout, {:verify, id}})

      refute_received {:native, :lookup_kra, _}
      assert assigns(view).tried == MapSet.new([id])
    end

    test "Verify with KRA in the sheet says how it went, and the total if KRA's differs" do
      receipt = insert_kra_receipt(amount_cents: 199_800)
      id = receipt.id

      view = mount_screen(ReceiptsScreen)
      assert_received {:native, :lookup_kra, _}
      view = render_info(view, {:kra, :error, :timeout, {:verify, id}})

      view = render_info(view, {:select, :receipts, 0})
      assert text(rendered(view)) =~ "Not verified yet"

      view = render_info(view, {:tap, :verify_receipt})
      assert_received {:native, :lookup_kra, [_, {:verify, ^id}]}

      view = render_info(view, {:kra, :result, @details, {:verify, id}})

      assert_received {:native, :toast, ["Verified with KRA, but KRA's total is Ksh 1,998.45"]}

      assert text(rendered(view)) =~ "Verified with KRA ·"
    end
  end
end
