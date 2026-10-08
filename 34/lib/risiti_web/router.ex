defmodule RisitiWeb.Router do
  use RisitiWeb, :router

  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RisitiWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  scope "/", RisitiWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes,
      on_mount: [{RisitiWeb.LiveUserAuth, :live_user_required}, {RisitiWeb.LiveUserAuth, :menu}] do
      live "/transactions", TransactionsLive
      live "/transactions/new", NewTransactionLive
      live "/approvals", ApprovalsLive
    end

    ash_authentication_live_session :phone_sign_in do
      live "/sign-in/phone", PhoneSignInLive
    end
  end

  scope "/", RisitiWeb do
    pipe_through :browser

    get "/", PageController, :home
    post "/auth/phone", AuthController, :phone
    auth_routes AuthController, Risiti.Accounts.User, path: "/auth"

    sign_out_route AuthController, "/sign-out",
      overrides: [RisitiWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove these if you'd like to use your own authentication views
    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{RisitiWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    RisitiWeb.AuthOverrides,
                    AshAuthentication.Phoenix.Overrides.Default
                  ]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [RisitiWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove this if you do not use the confirmation strategy
    confirm_route Risiti.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [RisitiWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(Risiti.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [RisitiWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]
    )
  end

  pipeline :require_web_user do
    plug RisitiWeb.Plugs.RequireWebUser
  end

  # Files and exports for the web pages, signed in with the browser's session.
  scope "/", RisitiWeb do
    pipe_through [:browser, :require_web_user]

    get "/transactions/export", ExportController, :download
    get "/transactions/:id/photo", Api.TransactionsController, :photo
    get "/attachments/:id", Api.TransactionsController, :attachment
  end

  pipeline :require_api_user do
    plug RisitiWeb.Plugs.RequireApiUser
  end

  # The phone's API. Signing in needs no token; everything else does.
  scope "/api", RisitiWeb.Api do
    pipe_through :api

    post "/auth/code", AuthController, :request_code
    post "/auth/verify", AuthController, :verify
    post "/auth/google", AuthController, :google
    post "/auth/register", AuthController, :register
  end

  scope "/api", RisitiWeb.Api do
    pipe_through [:api, :require_api_user]

    get "/me", AuthController, :me
    get "/catalog", TransactionsController, :catalog

    put "/devices", DevicesController, :register
    delete "/devices/:token", DevicesController, :forget

    get "/transactions", TransactionsController, :index
    put "/transactions/:client_id", TransactionsController, :put
    delete "/transactions/:client_id", TransactionsController, :delete
    get "/transactions/:id/photo", TransactionsController, :photo
    get "/attachments/:id", TransactionsController, :attachment

    get "/approvals", ApprovalsController, :index
    post "/approvals/:id/:decision", ApprovalsController, :decide
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:risiti, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: RisitiWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
