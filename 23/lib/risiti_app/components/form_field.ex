defmodule RisitiApp.Components.FormField do
  @moduledoc """
  A text input with a visible label above it, an example in the placeholder,
  and a hint or the validation error below.

      FormField.field(
        label: "Amount paid (Ksh)",
        key: :amount,
        value: @amount,
        placeholder: "e.g. 1,250.50",
        keyboard: :decimal,
        error: @errors[:amount]
      )

  Typing arrives in the screen as `{:change, key, value}`.
  """

  import Mob.Sigil

  def field(opts) do
    label = Keyword.fetch!(opts, :label)
    key = Keyword.fetch!(opts, :key)
    value = Keyword.get(opts, :value) || ""
    placeholder = Keyword.get(opts, :placeholder, "")
    keyboard = Keyword.get(opts, :keyboard, :default)
    hint = Keyword.get(opts, :hint)
    error = Keyword.get(opts, :error)

    ~MOB"""
    <Column fill_width={true} padding_bottom={12}>
      <Text text={label} text_size={13} font_weight="medium" text_color={:on_background} />
      <Spacer size={6} />
      <Box
        background={:surface}
        border_color={if(error, do: :error, else: :border)}
        border_width={1}
        corner_radius={16}
        padding_left={2}
        padding_right={2}
        fill_width={true}
      >
        <TextField
          value={value}
          placeholder={placeholder}
          variant={:bare}
          background={:transparent}
          padding={0}
          keyboard={keyboard}
          on_change={{self(), key}}
          fill_width={true}
        />
      </Box>
      <Spacer :if={hint || error} size={4} />
      <Text :if={hint && !error} text={hint} text_size={12} text_color={:muted} />
      <Text :if={error} text={error} text_size={12} text_color={:error} />
    </Column>
    """
  end
end
