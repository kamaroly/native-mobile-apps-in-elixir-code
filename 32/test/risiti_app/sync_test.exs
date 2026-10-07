defmodule RisitiApp.SyncTest do
  # Sync against a scripted server (RisitiApp.FakeServer).
  use Mob.ScreenCase, async: false

  import RisitiApp.ScreenHelpers

  alias RisitiApp.{Accounts, FakeServer, Repo, Sync, Transactions}
  alias RisitiApp.Receipts.Photos
  alias RisitiApp.Screens.ReceiptsScreen
  alias RisitiApp.Sync.Deletion
  alias RisitiApp.Transactions.{Attachment, Attachments, Transaction}

  setup :checkout_repo

  setup do
    {:ok, profile} =
      Accounts.connect("+254712345678", %{
        "token" => "tok-1",
        "user" => %{
          "id" => "u-1",
          "team" => "t_duka",
          "team_kind" => "business",
          "permissions" => %{}
        }
      })

    File.write!(Photos.path("receipt-sync.jpg"), "jpeg")

    expense =
      insert_transaction(vendor: "Naivas", amount_cents: 245_000, photo_path: "receipt-sync.jpg")

    %{profile: profile, expense: expense}
  end

  # A server that takes everything and answers with what it got, an id, and
  # ids for the attachments it was sent.
  defp accepting_server(opts \\ %{}) do
    FakeServer.stub(fn
      {:put, "/api/transactions/" <> client_id, %{body: body}} ->
        attachments =
          body
          |> FakeServer.multipart_all("attachments[]")
          |> Enum.with_index(fn {:file, path, name, _type}, i ->
            %{"id" => "a-#{client_id}-#{i}", "name" => name, "size" => File.stat!(path).size}
          end)

        fields = body |> FakeServer.multipart_fields() |> Map.drop(["attachments[]", "photo"])

        {200,
         %{
           "transaction" =>
             Map.merge(fields, %{
               "id" => "t-" <> client_id,
               "client_id" => client_id,
               "status" => Map.get(opts, :status, "pending"),
               "attachments" => attachments
             })
         }}

      {:get, "/api/transactions", _} ->
        {200, %{"transactions" => Map.get(opts, :transactions, [])}}

      {:get, "/api/me", _} ->
        {200,
         %{"user" => %{"id" => "u-1", "team" => "t_duka", "permissions" => %{"approve" => true}}}}

      {:delete, _path, _} ->
        Map.get(opts, :delete, {204, ""})

      {:get, "/api/transactions/" <> _photo, _} ->
        {200, "server-jpeg"}

      {:get, "/api/attachments/" <> _id, _} ->
        {200, "server-pdf"}
    end)
  end

  # Something the server has from another phone, or from before a reinstall.
  defp server_transaction(overrides) do
    Map.merge(
      %{
        "id" => "t-remote",
        "client_id" => "other-phone-1",
        "type" => "refund",
        "pay_to" => "self",
        "status" => "paid",
        "date" => "2026-09-18",
        "vendor" => "Quickmart",
        "amount_cents" => 99_000,
        "category" => "Office Supplies",
        "method" => "send_money",
        "phone" => "+254712345678",
        "has_photo" => true,
        "decision_note" => "OK",
        "decided_at" => "2026-09-19T08:00:00Z",
        "paid_at" => "2026-09-20T08:00:00Z",
        "attachments" => [
          %{
            "id" => "a-1",
            "name" => "invoice.pdf",
            "content_type" => "application/pdf",
            "size" => 10
          }
        ]
      },
      overrides
    )
  end

  defp stored_attachment(name) do
    source = Path.join(System.tmp_dir!(), "sync-#{System.unique_integer([:positive])}-#{name}")
    File.write!(source, "%PDF-1.4 #{name}")
    {:ok, attachment} = Attachments.store(source, name, "application/pdf")
    attachment
  end

  test "a new expense goes up once, with its photo", %{profile: profile, expense: expense} do
    accepting_server()

    assert {:ok, %{pushed: 1, failed: 0, pulled: 0}} = Sync.run(profile)

    client_id = expense.client_id
    path = "/api/transactions/" <> client_id
    assert_received {:http, :put, ^path, %{body: body}}

    assert %{
             "vendor" => "Naivas",
             "amount_cents" => "245000",
             "photo" => {:file, "receipt-sync.jpg"}
           } =
             FakeServer.multipart_fields(body)

    assert %Transaction{needs_push: false, photo_pushed: true, remote_id: "t-" <> ^client_id} =
             Repo.get!(Transaction, expense.id)

    # Nothing changed, so the next sync sends nothing.
    assert {:ok, %{pushed: 0}} = Sync.run(profile)
    refute_received {:http, :put, _, _}
  end

  test "an edit made while it was uploading is kept for the next sync", %{
    profile: profile,
    expense: expense
  } do
    FakeServer.stub(fn
      {:put, _, _} ->
        # The person edits the expense while the upload is on its way.
        Transaction
        |> Repo.get!(expense.id)
        |> Ecto.Changeset.change(vendor: "Naivas Karen", updated_at: ~N[2030-01-01 00:00:00])
        |> Repo.update!()

        {200, %{"transaction" => %{"id" => "t-1", "client_id" => expense.client_id}}}

      {:get, "/api/transactions", _} ->
        {200, %{"transactions" => []}}

      {:get, "/api/me", _} ->
        {200, %{"user" => %{}}}
    end)

    Sync.run(profile)

    assert %Transaction{needs_push: true, vendor: "Naivas Karen"} =
             Repo.get!(Transaction, expense.id)
  end

  test "an edit from a form opened before the sync still goes up", %{
    profile: profile,
    expense: expense
  } do
    accepting_server()
    # The form loaded the expense while it was still waiting to be sent...
    stale = Repo.get!(Transaction, expense.id)
    Sync.run(profile)

    # ...and the person saves after the sync: a new photo, a new vendor.
    File.write!(Photos.path("receipt-new.jpg"), "new jpeg")

    {:ok, _} =
      Transactions.update_transaction(stale, %{
        vendor: "Naivas Karen",
        photo_path: "receipt-new.jpg"
      })

    assert %Transaction{needs_push: true, photo_pushed: false} =
             Repo.get!(Transaction, expense.id)

    collect()
    Sync.run(profile)
    assert_received {:http, :put, _, %{body: body}}

    assert %{"vendor" => "Naivas Karen", "photo" => {:file, "receipt-new.jpg"}} =
             FakeServer.multipart_fields(body)
  end

  test "attachments go up once each", %{profile: profile} do
    accepting_server()

    {:ok, payment} =
      Transactions.create_transaction(
        %{
          type: "payment_request",
          pay_to: "supplier",
          date: ~D[2026-10-06],
          vendor: "Kamau Hardware",
          amount_cents: 1_250_000,
          category: "Office Supplies",
          method: "till",
          till_number: "832909"
        },
        [stored_attachment("quotation.pdf")]
      )

    Sync.run(profile)

    sent =
      for {:http, :put, _, %{body: body}} <- collect(),
          do: FakeServer.multipart_all(body, "attachments[]")

    assert [[], [{:file, _, "quotation.pdf", "application/pdf"}]] = Enum.sort(sent)

    # Edited and sent again: the server already has the quotation.
    {:ok, _} =
      Transactions.update_transaction(Repo.preload(payment, :attachments, force: true), %{
        description: "Cement"
      })

    Sync.run(profile)

    assert [{:http, :put, _, %{body: body}}] =
             collect() |> Enum.filter(&match?({:http, :put, _, _}, &1))

    assert FakeServer.multipart_all(body, "attachments[]") == []
    assert [%Attachment{remote_id: "a-" <> _}] = Repo.all(Attachment)
  end

  test "decisions come back, except onto edits the server hasn't seen", %{
    profile: profile,
    expense: expense
  } do
    accepting_server()
    Sync.run(profile)

    decided = %{
      "id" => "t-1",
      "client_id" => expense.client_id,
      "status" => "rejected",
      "decision_note" => "Duplicate",
      "decided_at" => "2026-10-07T07:00:00Z"
    }

    FakeServer.stub(fn
      {:get, "/api/transactions", _} -> {200, %{"transactions" => [decided]}}
      {:get, "/api/me", _} -> {200, %{"user" => %{}}}
    end)

    Sync.run(profile)

    assert %Transaction{status: "rejected", decision_note: "Duplicate"} =
             Repo.get!(Transaction, expense.id)

    # The person fixes it, and before it goes up, a pull says "rejected"
    # again. The fix wins: it goes up next, and the server decides again.
    {:ok, fixed} =
      Transactions.update_transaction(Repo.get!(Transaction, expense.id), %{amount_cents: 200_000})

    assert fixed.status == "pending"

    FakeServer.stub(fn
      {:put, _, _} -> {:error, :timeout}
      {:get, "/api/transactions", _} -> {200, %{"transactions" => [decided]}}
    end)

    assert {:error, :offline} = Sync.run(profile)
    assert %Transaction{status: "pending", needs_push: true} = Repo.get!(Transaction, expense.id)
  end

  describe "what the server has and the phone doesn't" do
    test "is added, with its photo and attachments left on the server", %{profile: profile} do
      accepting_server(%{transactions: [server_transaction(%{})]})

      assert {:ok, %{pulled: 1}} = Sync.run(profile)

      pulled =
        Transactions.get_transaction!(Repo.get_by!(Transaction, client_id: "other-phone-1").id)

      assert %Transaction{
               vendor: "Quickmart",
               status: "paid",
               needs_push: false,
               photo_pushed: true,
               photo_path: "remote-t-remote.jpg"
             } = pulled

      refute Photos.exists?(pulled.photo_path)
      assert [%Attachment{remote_id: "a-1", name: "invoice.pdf"} = invoice] = pulled.attachments

      # Downloaded when first opened.
      assert :ok = Sync.fetch_photo(profile, pulled)
      assert File.read!(Photos.path(pulled.photo_path)) == "server-jpeg"
      assert :ok = Sync.fetch_attachment(profile, invoice)
      assert File.read!(Attachments.path(invoice.file_name)) == "server-pdf"

      # And never goes back up.
      collect()
      assert {:ok, %{pushed: 0}} = Sync.run(profile)
      refute_received {:http, :put, _, _}
    end
  end

  describe "a transaction deleted here" do
    test "is deleted on the server at the next sync", %{profile: profile, expense: expense} do
      accepting_server()
      {:ok, _} = Transactions.delete_transaction(expense)
      assert [%Deletion{}] = Repo.all(Deletion)

      Sync.run(profile)

      path = "/api/transactions/" <> expense.client_id
      assert_received {:http, :delete, ^path, _}
      assert Repo.all(Deletion) == []
    end

    test "isn't brought back by a pull before the server hears of it", %{
      profile: profile,
      expense: expense
    } do
      on_server = server_transaction(%{"client_id" => expense.client_id, "status" => "pending"})
      accepting_server(%{transactions: [on_server], delete: {:error, :timeout}})
      {:ok, _} = Transactions.delete_transaction(expense)

      assert {:error, :offline} = Sync.run(profile)
      refute Repo.get_by(Transaction, client_id: expense.client_id)
    end

    test "comes back if it was decided meanwhile", %{profile: profile, expense: expense} do
      decided = server_transaction(%{"client_id" => expense.client_id, "status" => "approved"})

      accepting_server(%{
        transactions: [decided],
        delete: {422, %{"errors" => %{"status" => "has already been decided"}}}
      })

      {:ok, _} = Transactions.delete_transaction(expense)
      Sync.run(profile)

      assert %Transaction{status: "approved"} =
               Repo.get_by!(Transaction, client_id: expense.client_id)
    end
  end

  test "a book that isn't connected doesn't try", %{profile: profile} do
    {:ok, _} = Accounts.disconnect(profile)
    assert {:error, :not_connected} = Sync.run()
    refute_received {:http, _, _, _}
  end

  test "the home screen syncs when it opens, and a refused token disconnects" do
    view = mount_screen(ReceiptsScreen)
    assert_received {:native, :sync, []}
    assert assigns(view).syncing

    FakeServer.stub(fn _ -> {401, %{"error" => "Sign in again"}} end)
    view = render_info(view, {:sync, Sync.run()})

    refute RisitiApp.Accounts.Profile.connected?(assigns(view).profile)
    assert_received {:native, :toast, ["Please sign in again."]}
  end

  test "coming back online syncs" do
    view = mount_screen(ReceiptsScreen)
    view = render_info(view, {:sync, {:error, :offline}})
    assert_received {:native, :sync, []}

    render_info(view, {:mob_device, :connectivity_changed, %{online: true}})
    assert_received {:native, :sync, []}
  end

  test "only one sync runs at a time" do
    Process.register(self(), Sync)
    on_exit(fn -> :ok end)

    # Taken: a second run doesn't start, and sends nothing back.
    assert :ok = Sync.start(self())
    refute_receive {:sync, _}, 100
  end

  defp collect(acc \\ []) do
    receive do
      message -> collect([message | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
