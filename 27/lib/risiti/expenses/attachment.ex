defmodule Risiti.Expenses.Attachment do
  @moduledoc """
  A file supporting a transaction: an invoice, a quotation, a delivery
  note. Images and PDFs; the file itself is kept by
  `Risiti.Expenses.Storage`. (The receipt photo is the transaction's own
  `photo_file`.)
  """

  use Ash.Resource,
    domain: Risiti.Expenses,
    data_layer: AshPostgres.DataLayer,
    fragments: [Risiti.Accounts.Fragments.Multitenancies]

  postgres do
    table "transaction_attachments"
    repo Risiti.Repo

    references do
      reference :transaction, on_delete: :delete
    end
  end

  code_interface do
    define :attach
  end

  actions do
    defaults [:read, :destroy]

    create :attach do
      accept [:transaction_id, :file, :name, :content_type, :size]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :file, :string do
      description "The stored file's name (see Risiti.Expenses.Storage)"
      allow_nil? false
      public? true
    end

    attribute :name, :string, allow_nil?: false, public?: true

    attribute :content_type, :string do
      allow_nil? false
      public? true
      constraints match: ~r/^(image\/.+|application\/pdf)$/
    end

    attribute :size, :integer, allow_nil?: false, public?: true, constraints: [min: 0]

    timestamps()
  end

  relationships do
    belongs_to :transaction, Risiti.Expenses.Transaction, allow_nil?: false
  end
end
