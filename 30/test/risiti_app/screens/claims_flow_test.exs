defmodule RisitiApp.Screens.ClaimsFlowTest do
  use Mob.ScreenCase

  import RisitiApp.ScreenHelpers

  alias RisitiApp.Screens.{ReceiptsScreen, RequestFormScreen}
  alias RisitiApp.Transactions
  alias RisitiApp.Transactions.Attachments

  setup :checkout_repo

  defp fill_in(view, fields) do
    Enum.reduce(fields, view, fn {field, value}, view ->
      render_info(view, {:change, field, value})
    end)
  end

  # A file in the test's temporary folder, as the picker would hand it over.
  defp picked(context, name, mime) do
    path = Path.join(context.tmp_dir, name)
    File.write!(path, "contents of #{name}")
    %{path: path, name: name, mime: mime, size: 20}
  end

  describe "payment requests" do
    test "Add offers an expense by hand or a payment request" do
      view = ReceiptsScreen |> mount_screen() |> render_info({:tap, :add_menu})

      assert_received {:native, :action_sheet, [opts]}
      assert Enum.map(opts[:buttons], & &1[:action]) == [:add_manual, :new_payment, nil]

      view = render_info(view, {:alert, :new_payment})
      assert {:push, RequestFormScreen, %{notify: pid}} = view.socket.__mob__.nav_action
      assert pid == self()
    end

    test "a request to pay a supplier's till is saved, pending, and reported back" do
      view =
        RequestFormScreen
        |> mount_screen(%{notify: self()})
        |> fill_in(amount: "12,500", vendor: "Kamau Hardware", description: "Cement for the site")
        |> render_info({:tap, {:method, "till"}})
        |> fill_in(till_number: "832909")
        |> render_info({:tap, :submit})

      assert view.socket.__mob__.nav_action == {:pop}
      assert_received {:request_saved, %{type: "payment_request"}}
      assert_received {:native, :toast, ["Request sent for approval"]}

      assert [request] = Transactions.list_transactions()

      assert %{
               type: "payment_request",
               pay_to: "supplier",
               status: "pending",
               amount_cents: 1_250_000,
               method: "till",
               till_number: "832909"
             } = request
    end

    test "only the chosen way of paying is kept" do
      RequestFormScreen
      |> mount_screen()
      |> fill_in(amount: "500", vendor: "Otieno", phone: "0712 345 678")
      |> render_info({:tap, {:method, "paybill"}})
      |> fill_in(paybill_number: "888880", account_number: "1234567")
      |> render_info({:tap, :submit})

      assert [%{method: "paybill", phone: nil, account_number: "1234567"}] =
               Transactions.list_transactions()
    end

    test "each way of paying says what it's missing, in words" do
      view =
        RequestFormScreen
        |> mount_screen()
        |> fill_in(amount: "500", vendor: "Otieno")
        |> render_info({:tap, {:method, "till"}})
        |> fill_in(till_number: "12")
        |> render_info({:tap, :submit})

      assert assigns(view).errors == %{till_number: "Till number is 5 to 7 digits"}

      view =
        view
        |> render_info({:tap, {:method, "paybill"}})
        |> fill_in(paybill_number: "888880")
        |> render_info({:tap, :submit})

      assert assigns(view).errors == %{account_number: "Enter the account number"}
      assert Transactions.list_transactions() == []
    end

    test "an advance pays the person" do
      RequestFormScreen
      |> mount_screen()
      |> fill_in(amount: "3000", vendor: "Me", phone: "0712345678")
      |> render_info({:tap, {:pay_to, "self"}})
      |> render_info({:tap, :submit})

      assert [%{pay_to: "self", phone: "+254712345678"}] = Transactions.list_transactions()
    end

    test "editing an approved request sends it back for approval" do
      {:ok, request} =
        Transactions.create_transaction(%{
          type: "payment_request",
          date: Transactions.today(),
          vendor: "Kamau Hardware",
          amount_cents: 1_250_000,
          category: "Office Supplies",
          method: "till",
          till_number: "832909"
        })

      {:ok, _} = Transactions.decide(request, "approved")

      view =
        ReceiptsScreen
        |> mount_screen()
        |> render_info({:select, :receipts, 0})
        |> render_info({:tap, :edit_transaction})

      assert {:push, RequestFormScreen, %{id: id}} = view.socket.__mob__.nav_action
      assert id == request.id

      RequestFormScreen
      |> mount_screen(%{id: id})
      |> fill_in(amount: "13,000")
      |> render_info({:tap, :submit})

      assert %{status: "pending", amount_cents: 1_300_000} = Transactions.get_transaction!(id)
    end
  end

  describe "refunds" do
    test "an expense asked back becomes a refund, paid to the number given" do
      expense = insert_transaction(vendor: "Java House", description: "Client lunch")

      view =
        ReceiptsScreen
        |> mount_screen()
        |> render_info({:select, :receipts, 0})

      assert text(rendered(view)) =~ "Request refund"

      view = render_info(view, {:tap, :request_refund})
      assert {:push, RequestFormScreen, %{refund_of: id}} = view.socket.__mob__.nav_action
      assert id == expense.id

      RequestFormScreen
      |> mount_screen(%{refund_of: id, notify: self()})
      |> fill_in(phone: "0712 345 678", description: "Paid with my own M-Pesa")
      |> render_info({:tap, :submit})

      assert %{
               type: "refund",
               pay_to: "self",
               phone: "+254712345678",
               description: "Client lunch — Paid with my own M-Pesa",
               client_id: client_id
             } = Transactions.get_transaction!(id)

      assert client_id == expense.client_id, "a refund is the same transaction"
    end

    test "a pending refund can be taken back from its sheet" do
      {:ok, refund} =
        Transactions.request_refund(insert_transaction(), %{
          method: "send_money",
          phone: "0712345678"
        })

      view =
        ReceiptsScreen
        |> mount_screen()
        |> render_info({:select, :receipts, 0})
        |> render_info({:tap, :cancel_refund})

      assert_received {:native, :alert, [opts]}
      assert opts[:title] == "Take back the refund request?"

      view = render_info(view, {:alert, :confirm_cancel_refund})

      assert Transactions.get_transaction!(refund.id).type == "expense"
      assert text(rendered(view)) =~ "Request refund"
    end

    test "the Refunds & payments pill shows only claims" do
      insert_transaction(vendor: "Naivas")

      {:ok, _} =
        Transactions.request_refund(insert_transaction(vendor: "Java House"), %{
          method: "cash"
        })

      view = ReceiptsScreen |> mount_screen() |> render_info({:tap, {:group, :claims}})

      assert view |> assigns() |> Map.fetch!(:items) |> Enum.map(& &1.vendor) == ["Java House"]
    end
  end

  describe "attachments" do
    @tag :tmp_dir
    test "picked files are copied in and saved with the request", context do
      view =
        RequestFormScreen
        |> mount_screen()
        |> fill_in(amount: "12,500", vendor: "Kamau Hardware", phone: "0712345678")
        |> render_info({:tap, :attach_file})

      assert_received {:native, :pick_files, []}

      view =
        render_info(
          view,
          {:files, :picked,
           [
             picked(context, "Quotation.pdf", "application/pdf"),
             picked(context, "notes.txt", "text/plain")
           ]}
        )

      assert [%{name: "Quotation.pdf", file_name: file_name}] = assigns(view).attachments
      assert File.read!(Attachments.path(file_name)) == "contents of Quotation.pdf"
      assert_received {:native, :toast, ["notes.txt isn't an image or PDF"]}

      render_info(view, {:tap, :submit})

      assert [%{attachments: [%{name: "Quotation.pdf", content_type: "application/pdf"}]}] =
               Transactions.list_transactions()
    end

    @tag :tmp_dir
    test "a request never sent leaves no files behind", context do
      view =
        RequestFormScreen
        |> mount_screen()
        |> render_info({:files, :picked, [picked(context, "Invoice.pdf", "application/pdf")]})

      [%{file_name: file_name}] = assigns(view).attachments
      render_info(view, {:tap, :back})

      refute File.exists?(Attachments.path(file_name))
    end

    @tag :tmp_dir
    test "no more than five fit", context do
      files = for i <- 1..6, do: picked(context, "Page #{i}.jpg", "image/jpeg")

      view = RequestFormScreen |> mount_screen() |> render_info({:files, :picked, files})

      assert length(assigns(view).attachments) == 5
      assert_received {:native, :toast, ["Only 5 attachments fit"]}
    end

    @tag :tmp_dir
    test "the sheet lists them, opens one, and deleting removes the files", context do
      {:ok, stored} =
        Attachments.store(
          picked(context, "Invoice.pdf", nil).path,
          "Invoice.pdf",
          "application/pdf"
        )

      {:ok, request} =
        Transactions.create_transaction(
          %{
            type: "payment_request",
            date: Transactions.today(),
            vendor: "Kamau Hardware",
            amount_cents: 1_250_000,
            category: "Office Supplies",
            method: "cash"
          },
          [stored]
        )

      [attachment] = request.attachments

      view =
        ReceiptsScreen
        |> mount_screen()
        |> render_info({:select, :receipts, 0})

      assert text(rendered(view)) =~ "Invoice.pdf"

      render_info(view, {:tap, {:open_attachment, attachment.id}})
      path = Attachments.path(attachment.file_name)
      assert_received {:native, :open_file, [^path]}

      {:ok, _} = Transactions.delete_transaction(request)
      refute File.exists?(path)
    end
  end
end
