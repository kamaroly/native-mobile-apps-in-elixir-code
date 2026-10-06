defmodule RisitiApp.AppLock do
  @moduledoc """
  Whether the receipts open only after a fingerprint or face check. A phone
  setting, kept in `Mob.State`.
  """

  def enabled?, do: Mob.State.get(:app_lock, false) == true

  def set(enabled) when is_boolean(enabled), do: Mob.State.put(:app_lock, enabled)
end
