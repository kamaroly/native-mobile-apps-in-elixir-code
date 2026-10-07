defmodule RisitiApp.Transactions.Attachment do
  @moduledoc """
  A file supporting a transaction: an invoice, a quotation, a photo of the
  goods. Images and PDFs only. (The receipt photo itself is the
  transaction's `photo_path`.)

  The file lives in the app's data folder (see `Attachments`); this row
  records its stored name, the name the person knows it by, its type and
  its size. `remote_id` is its id on the server, once the server has it;
  one that came from the server downloads the first time it's opened.
  """

  use Ecto.Schema

  schema "transaction_attachments" do
    field :file_name, :string
    field :name, :string
    field :content_type, :string
    field :size, :integer
    field :remote_id, :string

    belongs_to :transaction, RisitiApp.Transactions.Transaction

    timestamps()
  end

  def image?(%{content_type: "image/" <> _}), do: true
  def image?(_attachment), do: false
end
