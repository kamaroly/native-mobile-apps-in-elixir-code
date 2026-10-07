defmodule RisitiApp.ApiTest do
  use ExUnit.Case, async: true

  alias RisitiApp.{Api, FakeServer}

  doctest Api

  test "every answer becomes one of a few results" do
    for {reply, expected} <- [
          {{200, %{"sent" => true}}, {:ok, %{"sent" => true}}},
          {{401, %{"error" => "Sign in again"}}, {:error, :unauthorized}},
          {{422, %{"errors" => %{"vendor" => "is required"}}},
           {:error, {:invalid, %{"vendor" => "is required"}}}},
          {{429, %{"error" => "Too many codes."}},
           {:error, {:invalid, %{"error" => "Too many codes."}}}},
          {{502, %{"error" => "Couldn't send the SMS."}},
           {:error, {:http, 502, %{"error" => "Couldn't send the SMS."}}}},
          {{:error, :timeout}, {:error, :offline}}
        ] do
      FakeServer.stub(fn _request -> reply end)
      assert Api.request_code("+254712345678") == expected
    end
  end

  test "signed-in calls carry the token" do
    FakeServer.stub(fn {:get, "/api/me", _} -> {200, %{"user" => %{}}} end)
    Api.me(%RisitiApp.Accounts.Profile{api_token: "tok-1"})

    assert_received {:http, :get, "/api/me", %{headers: headers}}
    assert {"authorization", "Bearer tok-1"} in headers
  end
end
