defmodule Risiti.Accounts.User.Changes.NormalizePhone do
  @moduledoc "Stores a Kenyan mobile number as +254XXXXXXXXX, or refuses it."

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :phone) do
      nil ->
        changeset

      raw ->
        case Risiti.Accounts.Phone.normalize(raw) do
          {:ok, phone} ->
            Ash.Changeset.force_change_attribute(changeset, :phone, phone)

          :error ->
            Ash.Changeset.add_error(changeset,
              field: :phone,
              message: "is not a valid Kenyan mobile number"
            )
        end
    end
  end
end
