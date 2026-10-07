defmodule RisitiApp.Components.ActionButton do
  @moduledoc """
  A compact icon-and-label button, in place of Material's roomy `Button`.

      ActionButton.button(nil, "Scan receipt", :take_photo, weight: 1)
      ActionButton.button("trash", "Delete", :delete, style: :danger)

  `icon` is one of Mob's built-in icon names, or nil for a label alone.

  Styles: `:primary` (ink, the default), `:secondary` (bordered surface) and
  `:danger`. Taps arrive as `{:tap, tag}`.
  """

  import Mob.Sigil

  def button(icon, label, tag, opts \\ []) do
    {background, content, border} = colors(Keyword.get(opts, :style, :primary))

    node = ~MOB"""
    <Box
      height={44}
      background={background}
      border_color={border}
      border_width={1}
      corner_radius={14}
      padding_left={14}
      padding_right={14}
      align={:center}
      on_tap={{self(), tag}}
      accessibility_label={label}
    >
      <Row align={:center} gap={6}>
        <Icon :if={icon} name={icon} text_size={18} text_color={content} />
        <Text text={label} text_size={14} font_weight="semibold" text_color={content} max_lines={1} />
      </Row>
    </Box>
    """

    # A Box fills its row on Android unless it is given a width or a weight.
    sizing = opts |> Keyword.take([:weight, :width]) |> Map.new()
    %{node | props: Map.merge(node.props, sizing)}
  end

  defp colors(:primary), do: {:primary, :on_primary, :primary}
  defp colors(:secondary), do: {:surface, :on_surface, :border}
  defp colors(:danger), do: {:error, :on_error, :error}
end
