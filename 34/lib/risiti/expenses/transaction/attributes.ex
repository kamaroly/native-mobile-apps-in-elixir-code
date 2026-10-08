defmodule Risiti.Expenses.Transaction.Attributes do
  @moduledoc false
  use Spark.Dsl.Fragment, of: Ash.Resource

  attributes do
    uuid_v7_primary_key :id

    attribute :client_id, :string do
      description "The phone's id for this transaction, so a resend updates it"
      allow_nil? false
      public? true
    end

    # ── The figures: the phone owns these ───────────────────────────────────

    attribute :type, :string do
      description "expense, refund or payment_request"
      allow_nil? false
      public? true
      default "expense"
      constraints match: ~r/^(expense|refund|payment_request)$/
    end

    attribute :pay_to, :atom do
      description "Who a claim pays: the person themselves or a supplier; nil for an expense"
      constraints one_of: [:self, :supplier]
      public? true
    end

    attribute :date, :date, allow_nil?: false, public?: true

    attribute :vendor, :string do
      description "Who was paid, or is to be paid"
      allow_nil? false
      public? true
    end

    attribute :description, :string, public?: true
    attribute :amount_cents, :integer, allow_nil?: false, public?: true, constraints: [min: 1]

    attribute :tax_cents, :integer do
      description "VAT included in the amount, when the receipt shows it"
      public? true
      constraints min: 0
    end

    attribute :category, :string, allow_nil?: false, public?: true

    attribute :method, :string do
      description "How it was, or is to be, paid (Risiti.Expenses.PaymentMethod)"
      public? true
    end

    attribute :phone, :string, public?: true
    attribute :till_number, :string, public?: true
    attribute :paybill_number, :string, public?: true
    attribute :account_number, :string, public?: true

    # ── What was read off the receipt ───────────────────────────────────────

    attribute :source, :string, public?: true, default: "manual"
    attribute :qr_content, :string, public?: true
    attribute :seller_pin, :string, public?: true
    attribute :branch_id, :string, public?: true
    attribute :invoice_number, :string, public?: true
    attribute :verify_url, :string, public?: true
    attribute :verified_at, :utc_datetime, public?: true
    attribute :ocr_text, :string, public?: true

    attribute :photo_file, :string do
      description "The stored receipt photo's file name"
      public? true
    end

    # ── The decision: the server owns these ─────────────────────────────────

    attribute :status, :atom do
      constraints one_of: [:pending, :approved, :rejected, :paid]
      default :pending
      allow_nil? false
      public? true
    end

    attribute :decision_note, :string, public?: true
    attribute :decided_at, :utc_datetime, public?: true
    attribute :paid_at, :utc_datetime, public?: true

    attribute :exported_at, :utc_datetime do
      description "When it was last exported for accounting software"
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_client_id, [:user_id, :client_id]
  end
end
