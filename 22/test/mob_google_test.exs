defmodule MobGoogleTest do
  use ExUnit.Case, async: true

  # Under mix test the NIF isn't loaded (it's built for the phone), so the
  # plugin answers the way it does on any platform without one.
  test "with no native side, sign_in answers with not_available" do
    assert MobGoogle.sign_in(:socket, server_client_id: "123-abc.apps.googleusercontent.com") ==
             :socket

    assert_received {:google, :error, json}
    assert MobGoogle.decode(json) == %{"message" => "not_available"}
  end

  test "decode turns JSON null into nil" do
    assert MobGoogle.decode(~s({"id_token":"x","email":"a@b.c","name":null})) ==
             %{"id_token" => "x", "email" => "a@b.c", "name" => nil}
  end

  test "the server client id is required" do
    assert_raise KeyError, fn -> MobGoogle.sign_in(:socket, []) end
  end
end
