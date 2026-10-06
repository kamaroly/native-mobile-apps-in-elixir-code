defmodule RisitiApp.Components.KraBadge do
  @moduledoc """
  A small green "KRA" tag for a receipt with a KRA QR code. Renders nothing
  for any other transaction.

      <Row>
        {KraBadge.badge(transaction)}
        <Text text="..." />
      </Row>

  The gap after the tag is part of the badge, so it can sit right in front
  of text.
  """

  import Mob.Sigil

  alias RisitiApp.Transactions

  def badge(transaction) do
    if Transactions.kra?(transaction), do: tag(Transactions.verified?(transaction)), else: []
  end

  defp tag(verified?) do
    label = if verified?, do: "KRA receipt, verified", else: "KRA receipt, not verified yet"

    ~MOB"""
    <Row align={:center} accessibility_label={label}>
      <Row background={:secondary} corner_radius={4} padding_left={3} padding_right={3}>
        <Text
          text="KRA"
          text_size={8}
          font_weight="bold"
          letter_spacing={0.3}
          text_color={:on_secondary}
        />
      </Row>
      <Spacer size={5} />
    </Row>
    """
  end
end
