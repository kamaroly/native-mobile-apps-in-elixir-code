defmodule RisitiApp.Screens.PushFlowTest do
  use Mob.ScreenCase, async: false

  import RisitiApp.ScreenHelpers

  alias RisitiApp.{Accounts, FakeServer, Push}
  alias RisitiApp.Screens.{ApprovalsScreen, ReceiptsScreen}

  doctest Push

  setup :checkout_repo

  setup do
    # Mob.State outlives each test; start every test without a token.
    Mob.State.put(:push_token, nil)
    Mob.State.put(:push_token_sent, nil)
    :ok
  end

  @approver %{
    "id" => "u-achieng",
    "name" => "Achieng",
    "phone" => "+254700000003",
    "team" => "t_duka",
    "team_name" => "Duka Ltd",
    "team_kind" => "business",
    "permissions" => %{
      "approve" => true,
      "mark_paid" => true,
      "list_all" => false,
      "export" => false
    }
  }

  defp connect(user \\ @approver),
    do: {:ok, _} = Accounts.connect(user["phone"], %{"token" => "tok-a", "user" => user})

  defp deliver(view, tag) do
    assert_received {^tag, result}
    render_info(view, {tag, result})
  end

  defp waiting(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => "t-1",
        "client_id" => "c-1",
        "type" => "refund",
        "pay_to" => "self",
        "status" => "pending",
        "date" => "2026-10-04",
        "vendor" => "Java House",
        "amount_cents" => 165_000,
        "category" => "Meals & Entertainment",
        "method" => "send_money",
        "phone" => "+254700000002",
        "has_photo" => true,
        "attachments" => [],
        "submitted_by" => %{"name" => "Otieno", "phone" => "+254700000002"}
      },
      overrides
    )
  end

  describe "registering for pushes" do
    test "a business book asks, registers, and sends the token once" do
      connect()
      FakeServer.stub(fn {:put, "/api/devices", _} -> {200, %{"ok" => true}} end)

      view = mount_screen(ReceiptsScreen)
      assert_received {:native, :request_notifications, []}

      view = render_info(view, {:permission, :notifications, :granted})
      assert_received {:native, :register_push, []}

      view =
        view |> render_info({:push_token, :android, "fcm-token-1"}) |> deliver(:push_registered)

      assert_received {:http, :put, "/api/devices",
                       %{body: {:json, %{platform: :android, token: "fcm-token-1"}}}}

      # The same token again (Firebase repeats itself): nothing to send.
      render_info(view, {:push_token, :android, "fcm-token-1"})
      refute_received {:push_registered, _}
    end

    test "a personal book, or one that isn't connected, never asks" do
      mount_screen(ReceiptsScreen)
      refute_received {:native, :request_notifications, []}

      connect(%{@approver | "team_kind" => "personal"})
      mount_screen(ReceiptsScreen)
      refute_received {:native, :request_notifications, []}
    end
  end

  describe "a push arriving" do
    setup do
      connect()
      %{view: mount_screen(ReceiptsScreen)}
    end

    test "while the app is open: a sync, and a toast", %{view: view} do
      # The sync the screen started as it opened has finished.
      view = render_info(view, {:sync, {:ok, %{pushed: 0, failed: 0, pulled: 0}}})
      flush()

      render_info(view, {:notification, push("approvals", :foreground)})

      assert_received {:native, :sync, []}

      assert_received {:native, :toast,
                       ["New refund to approve: Otieno · Java House · Ksh 1,650"]}
    end

    test "tapped: opens Approvals for an approver", %{view: view} do
      view = render_info(view, {:notification, push("approvals", :tap)})
      assert navigated_to(view) == ApprovalsScreen
    end

    test "tapped, about the person's own: stays on the list", %{view: view} do
      view = render_info(view, {:notification, push("transactions", :tap)})
      assert navigated_to(view) == nil
    end
  end

  describe "the Approvals screen" do
    setup do
      connect()
      :ok
    end

    test "decides, with a note needed to reject" do
      FakeServer.stub(fn
        {:get, "/api/approvals", _} ->
          {200, %{"transactions" => [waiting()]}}

        {:post, "/api/approvals/t-1/" <> _, _} ->
          {200, %{"transaction" => waiting(%{"status" => "rejected"})}}
      end)

      view = ApprovalsScreen |> mount_screen() |> deliver(:loaded)
      assert text(rendered(view)) =~ "From Otieno"

      view = render_info(view, {:select, :approvals, 0})
      assert text(rendered(view)) =~ "Note (needed to reject)"

      view = render_info(view, {:tap, :reject})
      assert assigns(view).note_error == "Say why, so they know what to fix"
      refute_received {:http, :post, _, _}

      view =
        view
        |> render_info({:change, :note, "This was a team lunch"})
        |> render_info({:tap, :reject})

      assert_received {:http, :post, "/api/approvals/t-1/reject",
                       %{body: {:json, %{note: "This was a team lunch"}}}}

      view = deliver(view, {:decided, "Rejected"})
      assert_received {:native, :toast, ["Rejected"]}
      assert assigns(view).selected == nil
    end

    test "an approved claim can be marked paid" do
      FakeServer.stub(fn
        {:get, "/api/approvals", _} ->
          {200, %{"transactions" => [waiting(%{"status" => "approved"})]}}

        {:post, "/api/approvals/t-1/pay", _} ->
          {200, %{"transaction" => waiting(%{"status" => "paid"})}}
      end)

      view =
        ApprovalsScreen
        |> mount_screen()
        |> deliver(:loaded)
        |> render_info({:select, :approvals, 0})

      assert text(rendered(view)) =~ "Mark as paid"

      view |> render_info({:tap, :pay}) |> deliver({:decided, "Marked as paid"})
      assert_received {:http, :post, "/api/approvals/t-1/pay", _}
    end

    test "the photo downloads, then opens" do
      FakeServer.stub(fn
        {:get, "/api/approvals", _} -> {200, %{"transactions" => [waiting()]}}
        {:get, "/api/transactions/t-1/photo", _} -> {200, "jpeg bytes"}
      end)

      view =
        ApprovalsScreen
        |> mount_screen()
        |> deliver(:loaded)
        |> render_info({:select, :approvals, 0})
        |> render_info({:tap, :open_photo})
        |> deliver(:downloaded)

      assert_received {:native, :open_file, [path]}
      assert File.read!(path) == "jpeg bytes"
      assert view
    end

    test "a push while it's open reloads it" do
      FakeServer.stub(fn {:get, "/api/approvals", _} -> {200, %{"transactions" => []}} end)
      view = ApprovalsScreen |> mount_screen() |> deliver(:loaded)

      render_info(view, :server_changed)
      assert_received {:loaded, _}
    end
  end

  defp push(screen, presentation) do
    %{
      source: :push,
      presentation: presentation,
      title: "New refund to approve",
      body: "Otieno · Java House · Ksh 1,650",
      data: %{screen: screen, kind: "transaction", id: "t-1"}
    }
  end

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end
end
