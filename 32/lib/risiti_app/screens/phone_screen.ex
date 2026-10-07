defmodule RisitiApp.Screens.PhoneScreen do
  @moduledoc """
  Signing in to the Risiti server, which connects this phone's book to the
  person's team.

  The server texts a 6-digit code to the number. A number the server
  already knows goes straight in. A new one is asked for a name and
  whether it's "Just me", a free personal book, or a business they own.

  "Continue with Google" (once `config :risiti_app, :google_client_id` is
  set) signs in with a Google account instead. The book is still kept
  under a phone number, so someone new with Google gives their M-Pesa
  number too; it stays on the phone. The server only trusts numbers it
  has texted.
  """

  use Mob.Screen

  alias RisitiApp.{Accounts, Api, Native, Phone}
  alias RisitiApp.Components.{ActionButton, FormField}

  @impl Mob.Screen
  def mount(_params, _session, socket) do
    {:ok,
     Mob.Socket.assign(socket,
       # :phone (ask the number) → :code (ask the code) → :register (someone
       # new: a name, and just me or a business). Google skips to :register
       # for someone new, or goes straight in (via :google_phone if the
       # server has no number for them).
       step: :phone,
       via: :sms,
       phone: "",
       code: "",
       signup_token: nil,
       # Someone Google signed in, waiting for their M-Pesa number.
       signed_in: nil,
       name: "",
       business?: false,
       team_name: "",
       busy: false,
       error: nil
     )}
  end

  @impl Mob.Screen
  def render(%{step: :phone} = assigns) do
    ~MOB"""
    <Column padding_left={22} padding_right={22} background={:background} fill_height={true}>
      <Spacer size={56} />
      <Text text="Sign in to Risiti" text_size={26} font_weight="bold" text_color={:on_background} />
      <Spacer size={8} />
      <Text
        text="We'll text you a code. Your receipts stay on this phone either way; signing in sends them to your team."
        text_size={15}
        text_color={:muted}
      />
      <Spacer size={24} />
      {FormField.field(
        label: "Phone number",
        key: :phone,
        value: @phone,
        placeholder: "e.g. 0712 345 678",
        keyboard: :phone,
        error: @error
      )}
      {ActionButton.button("forward", if(@busy, do: "Sending code…", else: "Send code"), :send_code)}
      {google_button()}
    </Column>
    """
  end

  def render(%{step: :code} = assigns) do
    ~MOB"""
    <Column padding_left={22} padding_right={22} background={:background} fill_height={true}>
      <Spacer size={56} />
      <Text text="Enter the code" text_size={26} font_weight="bold" text_color={:on_background} />
      <Spacer size={8} />
      <Text text={"We texted a 6-digit code to #{@phone}."} text_size={15} text_color={:muted} />
      <Spacer size={24} />
      {FormField.field(
        label: "Code",
        key: :code,
        value: @code,
        placeholder: "e.g. 482913",
        keyboard: :number,
        error: @error
      )}
      {ActionButton.button("check", if(@busy, do: "Checking…", else: "Sign in"), :verify)}
      <Spacer size={12} />
      <Row fill_width={true}>
        {ActionButton.button("back", "Change number", :change_number, style: :secondary, weight: 1)}
        <Spacer size={8} />
        {ActionButton.button("refresh", "Resend", :send_code, style: :secondary, weight: 1)}
      </Row>
    </Column>
    """
  end

  # Someone Google signed in whom the server knows, without a number yet.
  def render(%{step: :google_phone} = assigns) do
    ~MOB"""
    <Column padding_left={22} padding_right={22} background={:background} fill_height={true}>
      <Spacer size={56} />
      <Text text="Your M-Pesa number" text_size={26} font_weight="bold" text_color={:on_background} />
      <Spacer size={8} />
      <Text
        text="Refunds are paid to it. It stays on this phone."
        text_size={15}
        text_color={:muted}
      />
      <Spacer size={24} />
      {FormField.field(
        label: "Phone number",
        key: :phone,
        value: @phone,
        placeholder: "e.g. 0712 345 678",
        keyboard: :phone,
        error: @error
      )}
      {ActionButton.button("check", "Continue", :finish_google)}
    </Column>
    """
  end

  def render(%{step: :register} = assigns) do
    ~MOB"""
    <Column padding_left={22} padding_right={22} background={:background} fill_height={true}>
      <Spacer size={56} />
      <Text text="Welcome to Risiti" text_size={26} font_weight="bold" text_color={:on_background} />
      <Spacer size={8} />
      <Text text="A couple of things and you're in." text_size={15} text_color={:muted} />
      <Spacer size={24} />
      {FormField.field(
        label: "Your name",
        key: :name,
        value: @name,
        placeholder: "e.g. Achieng Otieno",
        error: @error
      )}
      {if @via == :google,
        do:
          FormField.field(
            label: "Your M-Pesa number",
            key: :phone,
            value: @phone,
            placeholder: "e.g. 0712 345 678",
            keyboard: :phone,
            hint: "Refunds are paid to it. It stays on this phone."
          )}
      <Text text="Who's it for?" text_size={13} font_weight="medium" text_color={:on_background} />
      <Spacer size={6} />
      <Row fill_width={true}>
        {choice("Just me", "Free", :just_me, not @business?)}
        <Spacer size={8} />
        {choice("My business", "Free trial", :business, @business?)}
      </Row>
      <Spacer size={16} />
      {if @business?,
        do:
          FormField.field(
            label: "Business name",
            key: :team_name,
            value: @team_name,
            placeholder: "e.g. Achieng Traders"
          )}
      {ActionButton.button("check", if(@busy, do: "Setting up…", else: "Start"), :register)}
    </Column>
    """
  end

  defp google_button do
    if Application.get_env(:risiti_app, :google_client_id) do
      ~MOB"""
      <Column fill_width={true} padding_top={12}>
        {ActionButton.button("user", "Continue with Google", :google, style: :secondary)}
      </Column>
      """
    else
      []
    end
  end

  defp choice(title, subtitle, tag, selected?) do
    {background, text_color, border} =
      if selected?,
        do: {:primary, :on_primary, :primary},
        else: {:surface, :on_surface, :border}

    ~MOB"""
    <Box
      weight={1}
      background={background}
      border_color={border}
      border_width={1}
      corner_radius={16}
      padding={14}
      on_tap={{self(), {:for, tag}}}
      accessibility_label={title}
    >
      <Column>
        <Text text={title} text_size={15} font_weight="semibold" text_color={text_color} />
        <Text text={subtitle} text_size={12} text_color={text_color} />
      </Column>
    </Box>
    """
  end

  # ── Events ──────────────────────────────────────────────────────────────────

  @impl Mob.Screen
  def handle_info({:change, field, value}, socket)
      when field in [:phone, :code, :name, :team_name] do
    {:noreply, Mob.Socket.assign(socket, [{field, value}, {:error, nil}])}
  end

  # While a request is out, taps wait: `busy` is the guard.
  def handle_info({:tap, _}, %{assigns: %{busy: true}} = socket), do: {:noreply, socket}

  def handle_info({:tap, :send_code}, socket) do
    case Phone.normalize(socket.assigns.phone) do
      {:ok, phone} ->
        {:noreply,
         socket
         |> Mob.Socket.assign(phone: phone, busy: true, error: nil)
         |> Native.background(:code_sent, fn -> Api.request_code(phone) end)}

      :error ->
        {:noreply,
         Mob.Socket.assign(socket, :error, "Enter a Kenyan mobile number, e.g. 0712 345 678.")}
    end
  end

  def handle_info({:code_sent, {:ok, _}}, socket) do
    {:noreply,
     socket
     |> Mob.Socket.assign(step: :code, busy: false, code: "", error: nil)
     |> Native.toast("Code sent")}
  end

  def handle_info({:tap, :verify}, socket) do
    %{phone: phone, code: code} = socket.assigns

    {:noreply,
     socket
     |> Mob.Socket.assign(busy: true, error: nil)
     |> Native.background(:verified, fn -> Api.verify(phone, String.trim(code)) end)}
  end

  # Someone new: ask who they are before signing them up.
  def handle_info({result, {:ok, %{"needs_registration" => true} = body}}, socket)
      when result in [:verified, :google_verified] do
    {:noreply,
     Mob.Socket.assign(socket,
       step: :register,
       signup_token: body["signup_token"],
       name: body["name"] || socket.assigns.name,
       busy: false,
       error: nil
     )}
  end

  def handle_info({result, {:ok, body}}, socket)
      when result in [:verified, :google_verified, :registered] do
    finish(socket, body)
  end

  def handle_info({result, {:error, error}}, socket)
      when result in [:code_sent, :verified, :google_verified, :registered] do
    {:noreply, Mob.Socket.assign(socket, busy: false, error: Api.error_message(error))}
  end

  def handle_info({:tap, :google}, socket) do
    {:noreply,
     socket
     |> Mob.Socket.assign(busy: true, error: nil, via: :google)
     |> Native.google_sign_in(Application.fetch_env!(:risiti_app, :google_client_id))}
  end

  def handle_info({:google, :result, json}, socket) do
    %{"id_token" => id_token} = MobGoogle.decode(json)
    {:noreply, Native.background(socket, :google_verified, fn -> Api.google(id_token) end)}
  end

  def handle_info({:google, :error, json}, socket) do
    socket = Mob.Socket.assign(socket, busy: false, via: :sms)

    error =
      case MobGoogle.decode(json) do
        %{"message" => "cancelled"} -> nil
        %{"message" => "no_accounts"} -> "Add a Google account to this phone first."
        _other -> "Google sign-in didn't work. Try the SMS code."
      end

    {:noreply, Mob.Socket.assign(socket, :error, error)}
  end

  def handle_info({:tap, {:for, choice}}, socket),
    do: {:noreply, Mob.Socket.assign(socket, :business?, choice == :business)}

  def handle_info({:tap, :register}, socket) do
    %{signup_token: token, name: name, business?: business?, team_name: team_name} =
      socket.assigns

    cond do
      String.trim(name) == "" ->
        {:noreply, Mob.Socket.assign(socket, :error, "Tell us your name")}

      business? and String.trim(team_name) == "" ->
        {:noreply, Mob.Socket.assign(socket, :error, "Give your business a name")}

      socket.assigns.via == :google and Phone.normalize(socket.assigns.phone) == :error ->
        {:noreply, Mob.Socket.assign(socket, :error, "Enter your M-Pesa number")}

      true ->
        team_name = if business?, do: String.trim(team_name), else: ""

        {:noreply,
         socket
         |> Mob.Socket.assign(busy: true, error: nil)
         |> Native.background(:registered, fn ->
           Api.register(token, String.trim(name), team_name)
         end)}
    end
  end

  def handle_info({:tap, :finish_google}, %{assigns: %{signed_in: body}} = socket) do
    case Phone.normalize(socket.assigns.phone) do
      {:ok, phone} -> connect(socket, phone, body)
      :error -> {:noreply, Mob.Socket.assign(socket, :error, "Enter a Kenyan mobile number.")}
    end
  end

  def handle_info({:tap, :change_number}, socket),
    do: {:noreply, Mob.Socket.assign(socket, step: :phone, code: "", error: nil)}

  def handle_info(_message, socket), do: {:noreply, socket}

  # The book is kept under a phone number: the one the server has for them
  # (it texted that one), or else the one they typed. Someone Google signed
  # in whom the server knows without a number is asked for theirs.
  defp finish(socket, %{"user" => user} = body) do
    case phone_for(user, socket.assigns.phone) do
      {:ok, phone} ->
        connect(socket, phone, body)

      :error ->
        {:noreply, Mob.Socket.assign(socket, step: :google_phone, signed_in: body, busy: false)}
    end
  end

  defp phone_for(%{"phone" => phone}, _typed) when is_binary(phone), do: {:ok, phone}
  defp phone_for(_user, typed), do: Phone.normalize(typed)

  # Connects the book on this phone and opens it.
  defp connect(socket, phone, body) do
    case Accounts.connect(phone, body) do
      {:ok, _profile} ->
        {:noreply, Mob.Socket.reset_to(socket, RisitiApp.Screens.ReceiptsScreen)}

      {:error, :another_book} ->
        {:noreply,
         Mob.Socket.assign(socket,
           busy: false,
           step: :phone,
           error: "This phone's receipts belong to another account. Sign in with that one."
         )}

      {:error, _changeset} ->
        {:noreply,
         Mob.Socket.assign(socket, busy: false, error: "Couldn't save the sign-in. Try again.")}
    end
  end
end
