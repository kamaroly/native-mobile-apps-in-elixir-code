defmodule RisitiApp.App do
  @moduledoc "Application entry point for RisitiApp."

  use Mob.App, theme: RisitiApp.Theme.Light

  require Logger

  @impl Mob.App
  def navigation(_platform) do
    stack(:main, root: RisitiApp.Screens.ReceiptsScreen)
  end

  @impl Mob.App
  def on_start do
    RisitiApp.Components.register_all()

    # Configure BEAM's DNS path so Req / Finch / Mint / `gen_tcp:connect/3`
    # with a hostname work on iOS without per-host setup. Flips the lookup
    # chain from the iOS-broken `:native` (inet_gethost port program) path
    # to `[:file, :dns]` and seeds Google + Cloudflare as fallback
    # nameservers. Override with `nameservers:` if you need to (corporate
    # resolver, Quad9, etc.) — see `Mob.DNS.configure_pure_beam/1`.
    #
    # For hosts that need Apple's resolver (VPN-pushed DNS, mDNS,
    # captive portals, search-domain expansion) call `Mob.DNS.resolve/1`
    # for those specific hostnames here too. Both paths compose.
    Mob.DNS.configure_pure_beam()

    # Android has no CA store the BEAM can read, so HTTPS (the KRA receipt
    # lookup) verifies against this bundled copy of the Mozilla trust store.
    # The app works offline without it, so a failure only costs the lookup.
    with {:error, reason} <- Mob.Certs.load_cacerts(priv_path("cacerts.pem")) do
      Logger.warning("CA certificates not loaded, KRA lookups will fail: #{inspect(reason)}")
    end

    {:ok, _} = Application.ensure_all_started(:ecto_sqlite3)
    {:ok, _} = RisitiApp.Repo.start_link()

    Ecto.Migrator.with_repo(RisitiApp.Repo, fn repo ->
      Ecto.Migrator.run(repo, priv_path("repo/migrations"), :up, all: true)
    end)

    # After Repo and Mob.State are up and before the first screen renders, so
    # the user's Light/Dark/System choice is in place from the first frame.
    RisitiApp.Appearance.apply_saved()

    Mob.Screen.start_root(RisitiApp.Screens.ReceiptsScreen)
    Mob.Dist.ensure_started(node: :"risiti_app_android@127.0.0.1", cookie: :mob_secret)
  end

  # A file or folder under priv/, wherever this platform keeps it.
  #
  # On Android and iOS, Mob deploys the .beam files to one flat directory with
  # no versioned lib/ layout, so Application.app_dir/2 can't find priv/. The
  # native launcher sets MOB_BEAMS_DIR, and the deployer copies priv/ there.
  # (Chapter 12 explains what goes wrong when migrations can't be found.)
  defp priv_path(relative) do
    case System.get_env("MOB_BEAMS_DIR") do
      nil -> Application.app_dir(:risiti_app, Path.join("priv", relative))
      beams_dir -> Path.join([beams_dir, "priv", relative])
    end
  end
end
