defmodule RisitiApp.Theme do
  @moduledoc """
  The app's look: warm paper background, near-black ink and a deep green
  accent.

  `Light` and `Dark` are ordinary Mob themes; `Adaptive` picks between them
  from the phone's own setting. Colours the theme has no token for (the dark
  spend card and the three spending groups) come from `color/1`, which
  answers for whichever of the two is active.
  """

  defmodule Light do
    @moduledoc "Paper-and-ink light theme."

    def theme do
      Mob.Theme.build(
        primary: 0xFF1C1916,
        on_primary: 0xFFFFFFFF,
        secondary: 0xFF1F6B4A,
        on_secondary: 0xFFFFFFFF,
        background: 0xFFF4F1EC,
        on_background: 0xFF1C1916,
        surface: 0xFFFFFCF7,
        surface_raised: 0xFFFFFFFF,
        on_surface: 0xFF1C1916,
        muted: 0xFF6F6A63,
        error: 0xFFB42318,
        on_error: 0xFFFFFFFF,
        border: 0xFFE6E0D6,
        radius_sm: 14,
        radius_md: 16,
        radius_lg: 24
      )
    end
  end

  defmodule Dark do
    @moduledoc "The same palette, turned down for night use."

    def theme do
      Mob.Theme.build(
        primary: 0xFFF4F1EC,
        on_primary: 0xFF1C1916,
        secondary: 0xFF5BBF8F,
        on_secondary: 0xFF10201A,
        background: 0xFF141210,
        on_background: 0xFFF4F1EC,
        surface: 0xFF1E1B18,
        surface_raised: 0xFF28241F,
        on_surface: 0xFFF4F1EC,
        muted: 0xFFA39D94,
        error: 0xFFF97066,
        on_error: 0xFF1C1916,
        border: 0xFF34302A,
        radius_sm: 14,
        radius_md: 16,
        radius_lg: 24
      )
    end
  end

  defmodule Adaptive do
    @moduledoc "Follows the phone's light / dark setting."

    def theme do
      case Mob.Theme.color_scheme() do
        :dark -> Dark.theme()
        _ -> Light.theme()
      end
    end
  end

  @light %{
    spend_card: 0xFF1B2A24,
    spend_chip: 0xFF2A3833,
    spend_text: 0xFFF7F4EE,
    spend_muted: 0xFFB7C3BC,
    food: 0xFFC45C26,
    food_tint: 0xFFF3E3D8,
    fuel: 0xFF2B6CB0,
    fuel_tint: 0xFFDCE8F6,
    other: 0xFF7A5AF8,
    other_tint: 0xFFE8E3FB
  }

  @dark %{
    spend_card: 0xFF1B2A24,
    spend_chip: 0xFF2A3833,
    spend_text: 0xFFF7F4EE,
    spend_muted: 0xFFB7C3BC,
    food: 0xFFF0A477,
    food_tint: 0xFF3A2519,
    fuel: 0xFF7FB2E8,
    fuel_tint: 0xFF1A2A3D,
    other: 0xFFB3A1FF,
    other_tint: 0xFF2A2342
  }

  @doc "An ARGB colour the theme has no token for, for the active theme."
  def color(name), do: Map.fetch!(if(dark?(), do: @dark, else: @light), name)

  def dark?, do: Mob.Theme.current() == Dark.theme()
end
