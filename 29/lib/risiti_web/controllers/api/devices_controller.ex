defmodule RisitiWeb.Api.DevicesController do
  @moduledoc """
  The phone's push token (see `Risiti.Push`): registered after signing in,
  forgotten when the phone disconnects.
  """

  use RisitiWeb, :controller

  require Ash.Query

  alias Risiti.Accounts.PushDevice
  alias RisitiWeb.Api.JSON

  def register(conn, %{"platform" => platform, "token" => token})
      when platform in ~w(ios android) and is_binary(token) do
    user = conn.assigns.current_user

    case PushDevice.register(platform, token, actor: user, authorize?: false) do
      {:ok, _device} -> json(conn, %{ok: true})
      {:error, error} -> conn |> put_status(422) |> json(%{errors: JSON.errors(error)})
    end
  end

  def register(conn, _params),
    do: conn |> put_status(422) |> json(%{error: "Send a platform (ios or android) and a token"})

  @doc "Forgets the token, if it's this person's."
  def forget(conn, %{"token" => token}) do
    user_id = conn.assigns.current_user.id

    PushDevice
    |> Ash.Query.filter(token == ^token and user_id == ^user_id)
    |> Ash.bulk_destroy!(:destroy, %{}, authorize?: false)

    json(conn, %{ok: true})
  end
end
