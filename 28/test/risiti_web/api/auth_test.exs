defmodule RisitiWeb.Api.AuthTest do
  use RisitiWeb.ConnCase, async: false

  @client_id "risiti-web.apps.googleusercontent.com"

  defp code_for(phone) do
    # The SMS is a job now: run it here, and the Log adapter "sends" to us.
    Oban.drain_queue(queue: :sms)
    assert_received {:sms, ^phone, text}
    [code] = Regex.run(~r/\d{6}/, text)
    code
  end

  describe "by SMS" do
    test "a new number signs up, then is known", %{conn: conn} do
      assert %{"sent" => true} =
               conn |> post(~p"/api/auth/code", %{phone: "0712345678"}) |> json_response(200)

      code = code_for("+254712345678")

      assert %{"needs_registration" => true, "signup_token" => signup} =
               build_conn()
               |> post(~p"/api/auth/verify", %{phone: "0712345678", code: code})
               |> json_response(200)

      assert %{"token" => token, "user" => user} =
               build_conn()
               |> post(~p"/api/auth/register", %{
                 signup_token: signup,
                 name: "Wanjiku",
                 team_name: "Duka Ltd"
               })
               |> json_response(201)

      assert %{"name" => "Wanjiku", "phone" => "+254712345678", "team_kind" => "business"} = user

      assert user["permissions"] == %{
               "approve" => true,
               "mark_paid" => true,
               "list_all" => true,
               "export" => true
             }

      assert %{"user" => %{"team_name" => "Duka Ltd"}} =
               build_conn()
               |> put_req_header("authorization", "Bearer " <> token)
               |> get(~p"/api/me")
               |> json_response(200)
    end

    test "a wrong code is a 401", %{conn: conn} do
      post(conn, ~p"/api/auth/code", %{phone: "0712345678"})

      assert %{"error" => "That code is wrong or has expired"} =
               build_conn()
               |> post(~p"/api/auth/verify", %{phone: "0712345678", code: "000000"})
               |> json_response(401)
    end

    test "a sixth code in an hour is a 429" do
      for _ <- 1..5, do: build_conn() |> post(~p"/api/auth/code", %{phone: "0712345678"})

      assert %{"error" => _} =
               build_conn()
               |> post(~p"/api/auth/code", %{phone: "0712345678"})
               |> json_response(429)
    end

    test "the limit per address uses the proxy's last X-Forwarded-For entry" do
      for n <- 1..10 do
        build_conn()
        |> put_req_header("x-forwarded-for", "1.2.3.#{n}, 10.0.0.9")
        |> post(~p"/api/auth/code", %{phone: "07000000#{String.pad_leading("#{n}", 2, "0")}"})
      end

      assert build_conn()
             |> put_req_header("x-forwarded-for", "5.6.7.8, 10.0.0.9")
             |> post(~p"/api/auth/code", %{phone: "0722000000"})
             |> json_response(429)
    end
  end

  test "no token, no /api/me" do
    assert %{"error" => "Sign in again"} = build_conn() |> get(~p"/api/me") |> json_response(401)
  end

  describe "with Google" do
    setup do
      Cachex.clear(:risiti)
      google = JOSE.JWK.generate_key({:rsa, 2048})
      {_, public} = google |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()

      Req.Test.stub(Risiti.Accounts.GoogleIdToken, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("cache-control", "public, max-age=600")
        |> Req.Test.json(%{
          "keys" => [Map.merge(public, %{"kid" => "google-1", "alg" => "RS256"})]
        })
      end)

      %{google: google}
    end

    defp id_token(key, overrides \\ %{}) do
      claims =
        Map.merge(
          %{
            "iss" => "https://accounts.google.com",
            "aud" => @client_id,
            "sub" => "google-sub-1",
            "email" => "Achieng@Gmail.com",
            "email_verified" => true,
            "name" => "Achieng Otieno",
            "exp" => System.os_time(:second) + 600
          },
          overrides
        )

      {_, token} =
        key
        |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => "google-1"}, claims)
        |> JOSE.JWS.compact()

      token
    end

    defp google_sign_in(token), do: build_conn() |> post(~p"/api/auth/google", %{id_token: token})

    test "someone new signs up with the name Google has, then signs straight in", %{
      google: google
    } do
      assert %{"needs_registration" => true, "signup_token" => signup, "name" => "Achieng Otieno"} =
               google |> id_token() |> google_sign_in() |> json_response(200)

      assert %{"user" => %{"id" => id, "email" => "achieng@gmail.com", "team_kind" => "personal"}} =
               build_conn()
               |> post(~p"/api/auth/register", %{signup_token: signup, name: "Achieng Otieno"})
               |> json_response(201)

      assert %{"user" => %{"id" => ^id}} =
               google |> id_token() |> google_sign_in() |> json_response(200)
    end

    test "an account with that email is signed into, and linked", %{google: google} do
      user = Ash.Seed.seed!(Risiti.Accounts.User, %{email: "achieng@gmail.com", name: "Achieng"})
      id = user.id

      assert %{"user" => %{"id" => ^id}} =
               google |> id_token() |> google_sign_in() |> json_response(200)

      # Linked: a new email at Google still finds her.
      assert %{"user" => %{"id" => ^id}} =
               google
               |> id_token(%{"email" => "new@gmail.com"})
               |> google_sign_in()
               |> json_response(200)
    end

    test "tokens that aren't good enough are refused", %{google: google} do
      other_key = JOSE.JWK.generate_key({:rsa, 2048})

      for token <- [
            id_token(other_key),
            id_token(google, %{"aud" => "someone-else.apps.googleusercontent.com"}),
            id_token(google, %{"iss" => "https://evil.example.com"}),
            id_token(google, %{"exp" => System.os_time(:second) - 1}),
            id_token(google, %{"email_verified" => false}),
            "not.a.token"
          ] do
        assert %{"error" => _} = token |> google_sign_in() |> json_response(401)
      end
    end
  end
end
