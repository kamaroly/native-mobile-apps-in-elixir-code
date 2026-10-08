defmodule RisitiWeb.PhoneSignInLive do
  @moduledoc """
  Signing in on the web with a phone number and an SMS code, the same as
  on the phone (`Risiti.Accounts.PhoneSignIn`). Someone the server doesn't
  know yet signs up on the app first.

  A LiveView can't set the session cookie, so once the code is right the
  page posts a short-lived token to `RisitiWeb.AuthController.phone/2`
  (`phx-trigger-action`), which can.
  """

  use RisitiWeb, :live_view

  alias Risiti.Accounts.PhoneSignIn

  on_mount {RisitiWeb.LiveUserAuth, :live_no_user}

  def mount(_params, _session, socket) do
    # Only a connected socket knows the address; the page can't send a code before then.
    ip = if connected?(socket), do: RisitiWeb.ClientAddress.of_socket(socket)

    socket
    |> assign(step: :phone, phone: "", error: nil, web_token: nil, trigger_action: false)
    |> assign(ip: ip)
    |> ok()
  end

  def handle_event("send_code", %{"phone" => phone}, socket) do
    case PhoneSignIn.request_code(phone, socket.assigns.ip) do
      :ok -> socket |> assign(step: :code, phone: phone, error: nil) |> noreply()
      {:error, reason} -> socket |> assign(error: message(reason)) |> noreply()
    end
  end

  def handle_event("verify", %{"code" => code}, socket) do
    case PhoneSignIn.verify(socket.assigns.phone, String.trim(code)) do
      {:ok, :new, _signup_token} ->
        socket
        |> assign(
          step: :phone,
          error: "We don't know that number yet. Sign up on the Risiti app."
        )
        |> noreply()

      {:ok, user, _api_token} ->
        socket
        |> assign(web_token: PhoneSignIn.web_token(user), trigger_action: true)
        |> noreply()

      {:error, reason} ->
        socket |> assign(error: message(reason)) |> noreply()
    end
  end

  defp message(:invalid_phone), do: "Enter a valid Kenyan mobile number"
  defp message(:too_many_requests), do: "Too many codes. Try again in an hour."
  defp message(:invalid_code), do: "That code is wrong or has expired"
  defp message(_reason), do: "Couldn't send the SMS. Try again."

  defp ok(socket), do: {:ok, socket}
  defp noreply(socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>Sign in with your phone</.header>

      <p :if={@error} id="phone-error" class="text-error">{@error}</p>

      <form :if={@step == :phone} id="phone-form" phx-submit="send_code" class="space-y-4">
        <.input name="phone" value={@phone} label="Mobile number" placeholder="0712 345 678" />
        <.button>Send me a code</.button>
      </form>

      <form :if={@step == :code} id="code-form" phx-submit="verify" class="space-y-4">
        <p>We sent a code to {@phone}.</p>
        <.input name="code" value="" label="Code" inputmode="numeric" autocomplete="one-time-code" />
        <.button>Sign in</.button>
      </form>

      <form
        id="session-form"
        action={~p"/auth/phone"}
        method="post"
        phx-trigger-action={@trigger_action}
      >
        <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
        <input type="hidden" name="token" value={@web_token} />
      </form>
    </Layouts.app>
    """
  end
end
