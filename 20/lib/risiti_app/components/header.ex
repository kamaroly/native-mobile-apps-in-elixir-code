defmodule RisitiApp.Components.Header do
  @moduledoc """
  Screen header: a small muted kicker over a large title, with optional square
  icon buttons for going back and for actions on the right.

      <Header title="Settings" show_back={true} />
      <Header kicker="Monday, 05 Oct" title="Your expenses" actions={[{"settings", "Settings", :open_settings}]} />

  Each action is `{icon, accessibility_label, tag}`. Taps arrive as
  `{:tap, :back}` and `{:tap, tag}`.
  """

  import Mob.Sigil

  def expand(props, _children, _ctx) do
    title = Map.fetch!(props, :title)
    kicker = Map.get(props, :kicker)
    show_back = Map.get(props, :show_back, false)

    actions =
      props
      |> Map.get(:actions, [])
      |> Enum.map(fn {icon, label, tag} -> icon_button(icon, label, {self(), tag}) end)

    ~MOB"""
    <Row
      fill_width={true}
      padding_top={12}
      padding_left={22}
      padding_right={22}
      padding_bottom={14}
      gap={8}
    >
      {if show_back, do: icon_button("back", "Back", {self(), :back})}
      <Column weight={1}>
        <Text :if={kicker} text={kicker} text_size={13} text_color={:muted} font_weight="medium" />
        <Text
          text={title}
          text_size={26}
          font_weight="bold"
          letter_spacing={-1}
          text_color={:on_background}
          max_lines={2}
        />
      </Column>
      {actions}
    </Row>
    """
  end

  @doc "A 40×40 bordered square holding one icon."
  def icon_button(icon, label, on_tap) do
    ~MOB"""
    <Box
      width={40}
      height={40}
      corner_radius={14}
      background={:surface}
      border_color={:border}
      border_width={1}
      align={:center}
      on_tap={on_tap}
      accessibility_label={label}
    >
      <Icon name={icon} text_size={18} text_color={:on_surface} />
    </Box>
    """
  end
end
