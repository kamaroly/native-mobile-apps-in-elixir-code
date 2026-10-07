defmodule RisitiWeb.Api.DevicesTest do
  use RisitiWeb.ConnCase, async: false

  import Risiti.Fixtures

  alias Risiti.Accounts.PushDevice

  defp api(person),
    do:
      build_conn()
      |> put_req_header("authorization", "Bearer " <> Risiti.Accounts.SignUp.api_token(person))

  test "a phone registers its token, and it moves with whoever signs in" do
    otieno = user(name: "Otieno")
    achieng = user(name: "Achieng")

    assert %{"ok" => true} =
             api(otieno)
             |> put(~p"/api/devices", %{platform: "android", token: "fcm-1"})
             |> json_response(200)

    api(achieng) |> put(~p"/api/devices", %{platform: "android", token: "fcm-1"})

    assert [%{user_id: user_id}] = Ash.read!(PushDevice, authorize?: false)
    assert user_id == achieng.id
  end

  test "only its own person can forget a token" do
    otieno = user(name: "Otieno")
    PushDevice.register!(:android, "fcm-1", actor: otieno)

    api(user()) |> delete(~p"/api/devices/fcm-1")
    assert [_still_there] = Ash.read!(PushDevice, authorize?: false)

    api(otieno) |> delete(~p"/api/devices/fcm-1")
    assert [] = Ash.read!(PushDevice, authorize?: false)
  end

  test "a platform it doesn't know is refused" do
    assert %{"error" => _} =
             api(user())
             |> put(~p"/api/devices", %{platform: "windows", token: "x"})
             |> json_response(422)
  end
end
