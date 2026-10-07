defmodule RisitiApp.Transactions.Attachment do
  @moduledoc """
  A file supporting a transaction: an invoice, a quotation, a photo of the
  goods. Images and PDFs only. (The receipt photo itself is the
  transaction's `photo_path`.)

  The file lives in the app's data folder (see `Attachments`); this row
  records its stored name, the name the person knows it by, its type and
  its size.
  """

  use Ecto.Schema

  schema "transaction_attachments" do
    field :file_name, :string
    field :name, :string
    field :content_type, :string
    field :size, :integer

    belongs_to :transaction, RisitiApp.Transactions.Transaction

    timestamps()
  end

  def image?(%{content_type: "image/" <> _}), do: true
  def image?(_attachment), do: false
end
