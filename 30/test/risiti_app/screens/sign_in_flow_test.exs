defmodule RisitiApp.Screens.SignInFlowTest do
  use Mob.ScreenCase, async: false

  import RisitiApp.ScreenHelpers

  alias RisitiApp.{Accounts, FakeServer}
  alias RisitiApp.Accounts.Profile
  alias RisitiApp.Screens.{PhoneScreen, ReceiptsScreen, SettingsScreen}

  setup :checkout_repo

  @user %{
    "id" => "2e191203-7832-4a12-b52c-8fb57aa32fc3",
    "name" => "Wanjiku",
    "phone" => "+254712345678",
    "team" => "t_alr553sdvv2cc",
    "team_name" => "Duka Ltd",
    "team_kind" => "business",
    "permissions" => %{
      "approve" => true,
      "mark_paid" => true,
      "list_all" => true,
      "export" => true
    }
  }

  # What a background call sent the screen, handed to it as the phone would.
  defp deliver(view, tag) do
    assert_received {^tag, result}
    render_info(view, {tag, result})
  end

  defp type(view, field, value), do: render_info(view, {:change, field, value})

  test "a known number signs straight in, and the book is connected" do
    FakeServer.stub(fn
      {:post, "/api/auth/code", _} -> {200, %{"sent" => true}}
      {:post, "/api/auth/verify", _} -> {200, %{"token" => "tok-1", "user" => @user}}
    end)

    view =
      PhoneScreen
      |> mount_screen()
      |> type(:phone, "0712 345 678")
      |> render_info({:tap, :send_code})

    assert_received {:http, :post, "/api/auth/code", %{body: {:json, %{phone: "+254712345678"}}}}

    view = deliver(view, :code_sent)
    assert assigns(view).step == :code

    view = view |> type(:code, " 482913 ") |> render_info({:tap, :verify})
    assert_received {:http, :post, "/api/auth/verify", %{body: {:json, %{code: "482913"}}}}

    view = deliver(view, :verified)
    assert navigated_to(view) == ReceiptsScreen

    assert %Profile{api_token: "tok-1", team_name: "Duka Ltd", can_approve: true} =
             profile = Accounts.current_profile()

    assert Profile.connected?(profile) and Profile.manager?(profile)
  end

  test "someone new chooses a business and is signed up" do
    FakeServer.stub(fn
      {:post, "/api/auth/code", _} ->
        {200, %{"sent" => true}}

      {:post, "/api/auth/verify", _} ->
        {200, %{"needs_registration" => true, "signup_token" => "s-1"}}

      {:post, "/api/auth/register", _} ->
        {201, %{"token" => "tok-2", "user" => @user}}
    end)

    view =
      PhoneScreen
      |> mount_screen()
      |> type(:phone, "0712345678")
      |> render_info({:tap, :send_code})
      |> deliver(:code_sent)
      |> type(:code, "482913")
      |> render_info({:tap, :verify})
      |> deliver(:verified)

    assert assigns(view).step == :register
    assert text(rendered(view)) =~ "Who's it for?"

    # A business needs a name.
    view =
      view
      |> type(:name, "Wanjiku")
      |> render_info({:tap, {:for, :business}})
      |> render_info({:tap, :register})

    assert assigns(view).error == "Give your business a name"

    view = view |> type(:team_name, "Duka Ltd") |> render_info({:tap, :register})

    assert_received {:http, :post, "/api/auth/register",
                     %{
                       body:
                         {:json, %{signup_token: "s-1", name: "Wanjiku", team_name: "Duka Ltd"}}
                     }}

    assert navigated_to(deliver(view, :registered)) == ReceiptsScreen
  end

  test "a wrong code, and no connection, each say what happened" do
    FakeServer.stub(fn
      {:post, "/api/auth/code", _} -> {:error, :nxdomain}
      {:post, "/api/auth/verify", _} -> {401, %{"error" => "That code is wrong or has expired"}}
    end)

    view =
      PhoneScreen
      |> mount_screen()
      |> type(:phone, "0712345678")
      |> render_info({:tap, :send_code})
      |> deliver(:code_sent)

    assert assigns(view).error == "Can't reach the server. Check your internet connection."

    view = view |> render_info({:tap, :verify}) |> deliver(:verified)
    assert assigns(view).error == "That code is wrong or has expired"
  end

  test "a number that isn't Kenyan never reaches the server" do
    view =
      PhoneScreen |> mount_screen() |> type(:phone, "12345") |> render_info({:tap, :send_code})

    assert assigns(view).error =~ "Kenyan mobile number"
    refute_received {:http, _, _, _}
  end

  test "someone new with Google gives their M-Pesa number, which stays on the phone" do
    FakeServer.stub(fn
      {:post, "/api/auth/google", _} ->
        {200,
         %{"needs_registration" => true, "signup_token" => "s-g", "name" => "Achieng Otieno"}}

      {:post, "/api/auth/register", _} ->
        {201,
         %{"token" => "tok-g", "user" => %{@user | "phone" => nil, "name" => "Achieng Otieno"}}}
    end)

    view = PhoneScreen |> mount_screen() |> render_info({:tap, :google})
    assert_received {:native, :google_sign_in, ["risiti-web.apps.googleusercontent.com"]}

    view =
      view
      |> render_info({:google, :result, ~s({"id_token": "google-id-token"})})
      |> deliver(:google_verified)

    assert assigns(view).step == :register
    assert assigns(view).name == "Achieng Otieno"

    view = view |> render_info({:tap, :register})
    assert assigns(view).error == "Enter your M-Pesa number"

    view =
      view
      |> type(:phone, "0722 000 111")
      |> render_info({:tap, :register})
      |> deliver(:registered)

    assert navigated_to(view) == ReceiptsScreen
    assert Accounts.current_profile().phone == "+254722000111"
  end

  test "a book with receipts isn't handed to someone else's account" do
    {:ok, _} = Accounts.connect("+254712345678", %{"token" => "tok-1", "user" => @user})
    insert_transaction()

    other = %{@user | "id" => "another-person", "phone" => "+254799000111"}

    assert {:error, :another_book} =
             Accounts.connect("+254799000111", %{"token" => "t", "user" => other})
  end

  describe "Settings" do
    test "offers to sign in when the book isn't connected" do
      view = mount_screen(SettingsScreen)
      assert text(rendered(view)) =~ "Not signed in"
      assert navigated_to(render_info(view, {:tap, :sign_in})) == PhoneScreen
    end

    test "disconnecting keeps the book and forgets the token" do
      {:ok, _} = Accounts.connect("+254712345678", %{"token" => "tok-1", "user" => @user})
      view = mount_screen(SettingsScreen)
      assert text(rendered(view)) =~ "Duka Ltd · Business"

      view =
        view |> render_info({:tap, :disconnect}) |> render_info({:alert, :confirm_disconnect})

      assert_received {:native, :alert, _}

      refute Profile.connected?(Accounts.current_profile())
      assert text(rendered(view)) =~ "Not signed in"
    end
  end

  test "a personal book has no Refunds & payments pill" do
    personal = %{@user | "team_kind" => "personal", "team_name" => "Personal"}
    {:ok, _} = Accounts.connect("+254712345678", %{"token" => "tok-1", "user" => personal})

    refute text(rendered(mount_screen(ReceiptsScreen))) =~ "Refunds & payments"
  end
end
