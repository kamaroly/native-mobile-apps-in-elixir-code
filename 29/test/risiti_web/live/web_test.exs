defmodule RisitiWeb.WebTest do
  use RisitiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Risiti.Fixtures

  alias Risiti.Expenses
  alias Risiti.Expenses.Transaction

  setup do
    business_team()
  end

  describe "signing in with a phone number" do
    test "a known number gets a session", %{conn: conn, member: otieno} do
      {:ok, view, _html} = live(conn, ~p"/sign-in/phone")

      view |> form("#phone-form", %{phone: otieno.phone}) |> render_submit()
      Oban.drain_queue(queue: :sms)
      assert_received {:sms, _phone, text}
      [code] = Regex.run(~r/\d{6}/, text)

      view |> form("#code-form", %{code: code}) |> render_submit()

      # The page posts a short-lived token to /auth/phone, which signs in.
      form = view |> element("#session-form") |> render()
      [_, token] = Regex.run(~r/name="token" value="([^"]+)"/, form)
      conn = post(conn, ~p"/auth/phone", %{token: token})
      assert redirected_to(conn) == ~p"/transactions"

      assert conn |> recycle() |> get(~p"/transactions") |> html_response(200) =~ "Transactions"
    end

    test "an unknown number is sent to the app", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in/phone")
      view |> form("#phone-form", %{phone: "0799000111"}) |> render_submit()
      Oban.drain_queue(queue: :sms)
      assert_received {:sms, _phone, text}
      [code] = Regex.run(~r/\d{6}/, text)

      assert view |> form("#code-form", %{code: code}) |> render_submit() =~
               "Sign up on the Risiti app"
    end

    test "a made-up token is refused", %{conn: conn} do
      assert conn |> post(~p"/auth/phone", %{token: "nope"}) |> redirected_to() ==
               ~p"/sign-in/phone"
    end
  end

  test "signing up on the web makes a personal book" do
    {:ok, user} =
      Ash.create(
        Risiti.Accounts.User,
        %{
          email: "njeri@example.com",
          password: "a long password",
          password_confirmation: "a long password"
        },
        action: :register_with_password,
        authorize?: false
      )

    assert user.current_team =~ ~r/^p_/
    assert user.__metadata__.token
  end

  test "signed out, the pages send you to sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/transactions")
  end

  describe "approvals" do
    test "an approver approves and rejects, and the list follows", %{
      conn: conn,
      member: otieno,
      approver: achieng
    } do
      fuel = Expenses.sync_transaction!(phone_transaction(vendor: "Rubis"), actor: otieno)
      lunch = Expenses.sync_transaction!(phone_transaction(vendor: "Java House"), actor: otieno)

      {:ok, view, html} = conn |> log_in(achieng) |> live(~p"/approvals")
      assert html =~ "Rubis" and html =~ "Java House"

      # A rejection needs a note.
      view |> element("#transaction-#{lunch.id} button", "Reject") |> render_click()
      assert render(view) =~ "Say why, so they know what to fix"

      view
      |> element("#note-#{lunch.id}")
      |> render_change(%{transaction_id: lunch.id, note: "Personal lunch"})

      view |> element("#transaction-#{lunch.id} button", "Reject") |> render_click()
      view |> element("#transaction-#{fuel.id} button", "Approve") |> render_click()

      assert render(view) =~ "Nothing waiting"
      assert Ash.reload!(lunch, authorize?: false).decision_note == "Personal lunch"
      assert Ash.reload!(fuel, authorize?: false).status == :approved
    end

    test "a phone's new transaction appears without a reload", %{
      conn: conn,
      member: otieno,
      approver: achieng
    } do
      {:ok, view, _html} = conn |> log_in(achieng) |> live(~p"/approvals")

      Expenses.sync_transaction!(phone_transaction(vendor: "Naivas"), actor: otieno)
      assert render(view) =~ "Naivas"
    end

    test "someone who can't approve is sent away", %{conn: conn, member: otieno} do
      assert {:error, {:redirect, %{to: "/transactions"}}} =
               conn |> log_in(otieno) |> live(~p"/approvals")
    end
  end

  test "the transactions page shows what each person may see", %{
    conn: conn,
    member: otieno,
    owner: wanjiku
  } do
    Expenses.sync_transaction!(phone_transaction(vendor: "Otieno's fuel"), actor: otieno)
    Expenses.sync_transaction!(phone_transaction(vendor: "Wanjiku's rent"), actor: wanjiku)

    {:ok, _view, html} = conn |> log_in(otieno) |> live(~p"/transactions")
    assert html =~ "Otieno&#39;s fuel"
    refute html =~ "Wanjiku&#39;s rent"
    refute html =~ "Export for accounting"

    {:ok, _view, html} = build_conn() |> log_in(wanjiku) |> live(~p"/transactions")
    assert html =~ "Otieno&#39;s fuel" and html =~ "Wanjiku&#39;s rent"
    assert html =~ "Export for accounting"
  end

  @tag :pdftotext
  test "an uploaded receipt is read, and fills the form", %{conn: conn, member: otieno} do
    {:ok, view, _html} = conn |> log_in(otieno) |> live(~p"/transactions/new")

    receipt =
      file_input(view, "#new-transaction", :receipt, [
        %{
          name: "kamau.pdf",
          content: File.read!("test/fixtures/uploads/kamau_hardware.pdf"),
          type: "application/pdf"
        }
      ])

    render_upload(receipt, "kamau.pdf")
    html = render(view)
    assert html =~ "Kamau Hardware Limited"
    assert html =~ "Ksh 12,500.00"

    view
    |> form("#new-transaction", transaction: %{category: "Office Supplies"})
    |> render_submit()

    assert [t] = Transaction.mine!(actor: otieno)
    assert %{vendor: "Kamau Hardware Limited", amount_cents: 1_250_000, status: :pending} = t
    assert t.source == "ocr"
    assert t.photo_file
    assert t.client_id =~ ~r/^web-/
  end

  test "a form with mistakes says what's wrong", %{conn: conn, member: otieno} do
    {:ok, view, _html} = conn |> log_in(otieno) |> live(~p"/transactions/new")

    html =
      view
      |> form("#new-transaction", transaction: %{vendor: "", amount: "abc", category: "Fuel"})
      |> render_submit()

    assert html =~ "is required"
    assert Transaction.mine!(actor: otieno) == []
  end

  describe "exports" do
    setup %{member: otieno, owner: wanjiku} do
      fuel =
        Expenses.sync_transaction!(
          phone_transaction(
            vendor: "Rubis",
            category: "Fuel",
            amount_cents: 500_000,
            tax_cents: 68_966,
            method: "till",
            till_number: "832909",
            date: "2026-10-03"
          ),
          actor: otieno
        )

      Transaction.approve!(fuel, nil, actor: wanjiku)

      refund =
        Expenses.sync_transaction!(
          phone_transaction(
            type: "refund",
            vendor: "Java House",
            category: "Meals & Entertainment",
            amount_cents: 165_000,
            method: "cash",
            date: "2026-10-04"
          ),
          actor: otieno
        )

      Transaction.approve!(refund, nil, actor: wanjiku)
      :ok
    end

    test "QuickBooks journal entries balance, and are marked exported", %{
      conn: conn,
      owner: wanjiku
    } do
      params = %{from: "2026-10-01", to: "2026-10-31", format: "quickbooks"}
      csv = conn |> log_in(wanjiku) |> get(~p"/transactions/export", params) |> response(200)

      [header | lines] = csv |> String.trim() |> String.split("\r\n")
      assert header == "Journal No.,Journal Date,Account Name,Debits,Credits,Description,Name"

      assert [
               [_, "03/10/2026", "Fuel", "4310.34", "", "Rubis", "Rubis"],
               [_, "03/10/2026", "VAT Input", "689.66", "", "Rubis", "Rubis"],
               [_, "03/10/2026", "M-Pesa", "", "5000.00", "Rubis", "Rubis"],
               [
                 _,
                 "04/10/2026",
                 "Meals & Entertainment",
                 "1650.00",
                 "",
                 "Java House",
                 "Java House"
               ],
               [
                 _,
                 "04/10/2026",
                 "Staff Claims Payable",
                 "",
                 "1650.00",
                 "Java House",
                 "Java House"
               ]
             ] = Enum.map(lines, &String.split(&1, ","))

      unexported = Map.put(params, :unexported_only, "true")

      again =
        build_conn()
        |> log_in(wanjiku)
        |> get(~p"/transactions/export", unexported)
        |> response(200)

      assert again |> String.trim() |> String.split("\r\n") |> length() == 1
    end

    test "only those who may export can", %{conn: conn, member: otieno} do
      conn =
        conn
        |> log_in(otieno)
        |> get(~p"/transactions/export", %{
          from: "2026-10-01",
          to: "2026-10-31",
          format: "transactions"
        })

      assert redirected_to(conn) == ~p"/transactions"
    end
  end
end
