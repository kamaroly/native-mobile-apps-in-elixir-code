defmodule RisitiWeb.Api.AuthController do
  @moduledoc """
  Signing in and up on the phone: by SMS code (`Risiti.Accounts.PhoneSignIn`)
  or with Google (`Risiti.Accounts.GoogleSignIn`), then a name and a team
  for someone new (`Risiti.Accounts.SignUp`).
  """

  use RisitiWeb, :controller

  alias Risiti.Accounts.{GoogleSignIn, PhoneSignIn, SignUp}
  alias RisitiWeb.Api.JSON

  def request_code(conn, %{"phone" => phone}) do
    case PhoneSignIn.request_code(phone, RisitiWeb.ClientAddress.of_conn(conn)) do
      :ok -> json(conn, %{sent: true})
      {:error, :invalid_phone} -> error(conn, 422, "Enter a valid Kenyan mobile number")
      {:error, :too_many_requests} -> error(conn, 429, "Too many codes. Try again in an hour.")
      {:error, _reason} -> error(conn, 502, "Couldn't send the SMS. Try again.")
    end
  end

  def verify(conn, %{"phone" => phone, "code" => code}) do
    case PhoneSignIn.verify(phone, code) do
      # A new number: the phone asks for a name and a team, then registers.
      {:ok, :new, signup_token} ->
        json(conn, %{needs_registration: true, signup_token: signup_token})

      {:ok, user, token} ->
        json(conn, %{token: token, user: JSON.user(user)})

      {:error, :invalid_phone} ->
        error(conn, 422, "Enter a valid Kenyan mobile number")

      {:error, :invalid_code} ->
        error(conn, 401, "That code is wrong or has expired")
    end
  end

  def google(conn, %{"id_token" => id_token}) do
    case GoogleSignIn.verify(id_token) do
      {:ok, :new, signup_token, name} ->
        json(conn, %{needs_registration: true, signup_token: signup_token, name: name})

      {:ok, user, token} ->
        json(conn, %{token: token, user: JSON.user(user)})

      {:error, :google_unreachable} ->
        error(conn, 502, "Couldn't reach Google. Try again.")

      {:error, _refused} ->
        error(conn, 401, "That Google sign-in didn't work. Try again.")
    end
  end

  @doc "Someone new: `name`, and `team_name` for a business (blank for a personal book)."
  def register(conn, %{"signup_token" => signup_token} = params) do
    case SignUp.register(signup_token, Map.take(params, ["name", "team_name"])) do
      {:ok, user, token} ->
        conn |> put_status(:created) |> json(%{token: token, user: JSON.user(user)})

      {:error, :expired} ->
        error(conn, 401, "That took too long. Ask for a new code.")

      {:error, error} ->
        conn |> put_status(422) |> json(%{errors: JSON.errors(error)})
    end
  end

  def me(conn, _params), do: json(conn, %{user: JSON.user(conn.assigns.current_user)})

  defp error(conn, status, message), do: conn |> put_status(status) |> json(%{error: message})
end
