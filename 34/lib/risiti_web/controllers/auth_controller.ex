defmodule RisitiWeb.AuthController do
  use RisitiWeb, :controller
  use AshAuthentication.Phoenix.Controller

  def success(conn, activity, user, _token) do
    return_to = get_session(conn, :return_to) || ~p"/transactions"

    message =
      case activity do
        {:confirm_new_user, :confirm} -> "Your email address has now been confirmed"
        {:password, :reset} -> "Your password has successfully been reset"
        _ -> "You are now signed in"
      end

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    # If your resource has a different name, update the assign name here (i.e :current_admin)
    |> assign(:current_user, user)
    |> put_flash(:info, message)
    |> redirect(to: return_to)
  end

  @doc "The end of signing in with a code on the web (`RisitiWeb.PhoneSignInLive`)."
  def phone(conn, params) do
    case Risiti.Accounts.PhoneSignIn.web_user(params["token"]) do
      {:ok, user} ->
        {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
        success(conn, {:phone, :sign_in}, Ash.Resource.put_metadata(user, :token, token), token)

      {:error, :expired} ->
        conn
        |> put_flash(:error, "That took too long. Please sign in again.")
        |> redirect(to: ~p"/sign-in/phone")
    end
  end

  def failure(conn, activity, reason) do
    message =
      case {activity, reason} do
        {_,
         %AshAuthentication.Errors.AuthenticationFailed{
           caused_by: %Ash.Error.Forbidden{
             errors: [%AshAuthentication.Errors.CannotConfirmUnconfirmedUser{}]
           }
         }} ->
          """
          You have already signed in another way, but have not confirmed your account.
          You can confirm your account using the link we sent to you, or by resetting your password.
          """

        {_,
         %AshAuthentication.Errors.AuthenticationFailed{
           caused_by: %AshAuthentication.Errors.ConfirmationRequired{}
         }} ->
          """
          An account with this email already exists. We've sent a link to that
          address - confirm it to finish linking this provider to your account.
          """

        _ ->
          "Incorrect email or password"
      end

    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/sign-in")
  end

  def sign_out(conn, _params) do
    return_to = get_session(conn, :return_to) || ~p"/"

    conn
    |> clear_session(:risiti)
    |> put_flash(:info, "You are now signed out")
    |> redirect(to: return_to)
  end
end
