defmodule Risiti.Expenses.Transaction.Actions do
  @moduledoc false
  use Spark.Dsl.Fragment, of: Ash.Resource

  alias Risiti.Expenses.Transaction.{Changes, Validations}

  # What the person types: change one of these on a decided transaction and
  # it goes back for approval.
  @figures [
    :type,
    :pay_to,
    :date,
    :vendor,
    :description,
    :amount_cents,
    :tax_cents,
    :category,
    :method,
    :phone,
    :till_number,
    :paybill_number,
    :account_number
  ]

  # What was read off the receipt: kept, but not something to approve.
  @details [
    :qr_content,
    :source,
    :seller_pin,
    :branch_id,
    :invoice_number,
    :verify_url,
    :verified_at,
    :ocr_text,
    :photo_file
  ]

  code_interface do
    define :submit
    define :update_from_phone
    define :withdraw
    define :approve, args: [{:optional, :note}]
    define :reject, args: [:note]
    define :mark_paid
    define :to_decide
    define :mine
    define :list
    define :for_export, args: [:from, :to, :unexported_only?]
    define :mark_exported
  end

  actions do
    defaults [:read]

    create :submit do
      description "A transaction sent from a phone for the first time"
      accept [:client_id] ++ @figures ++ @details
      change relate_actor(:user)
      change Changes.SetPayTo
      validate Validations.PaymentDetails
      validate present(:method), where: [attribute_equals(:type, "payment_request")]
      change Changes.ApproveInPersonalTeam
    end

    update :update_from_phone do
      description "A transaction the phone had already sent, sent again with changes"
      require_atomic? false
      accept @figures ++ @details
      validate attribute_does_not_equal(:status, :paid), message: "has already been paid"
      change Changes.SetPayTo
      validate Validations.PaymentDetails
      validate present(:method), where: [attribute_equals(:type, "payment_request")]
      change Changes.ReopenIfFiguresChanged
      change Changes.ApproveInPersonalTeam
    end

    action :sync, :struct do
      description """
      Saves a transaction sent from a phone: submits it the first time its
      `client_id` is seen, updates it (`update_from_phone`) after that.
      """

      constraints instance_of: Risiti.Expenses.Transaction
      argument :attrs, :map, allow_nil?: false
      run Risiti.Expenses.Transaction.Actions.Sync
    end

    destroy :withdraw do
      description "Deleted on the phone before anyone decided on it"
      require_atomic? false
      validate attribute_equals(:status, :pending), message: "has already been decided"
    end

    update :approve do
      require_atomic? false
      argument :note, :string
      validate attribute_equals(:status, :pending), message: "is no longer waiting for approval"
      change set_attribute(:status, :approved)
      change set_attribute(:decision_note, arg(:note))
      change set_attribute(:decided_at, &DateTime.utc_now/0)
      change relate_actor(:decided_by)
    end

    update :reject do
      require_atomic? false
      argument :note, :string, allow_nil?: false
      validate attribute_equals(:status, :pending), message: "is no longer waiting for approval"
      change set_attribute(:status, :rejected)
      change set_attribute(:decision_note, arg(:note))
      change set_attribute(:decided_at, &DateTime.utc_now/0)
      change relate_actor(:decided_by)
    end

    update :mark_paid do
      require_atomic? false
      validate attribute_equals(:status, :approved), message: "must be approved before it is paid"

      validate attribute_in(:type, ["refund", "payment_request"]),
        message: "is an expense, already paid"

      change set_attribute(:status, :paid)
      change set_attribute(:paid_at, &DateTime.utc_now/0)
    end

    update :mark_exported do
      description "Exported to accounting software, so it isn't imported twice"
      require_atomic? false
      accept []
      change set_attribute(:exported_at, &DateTime.utc_now/0)
    end

    read :own do
      description "The actor's own transaction with the phone's `client_id`"
      get? true
      argument :client_id, :string, allow_nil?: false
      filter expr(user_id == ^actor(:id) and client_id == ^arg(:client_id))
    end

    read :mine do
      description "The actor's own transactions, newest first"
      filter expr(user_id == ^actor(:id))
      prepare build(sort: [date: :desc, inserted_at: :desc])
    end

    read :to_decide do
      description "Waiting for a decision, or approved claims waiting to be paid"

      filter expr(
               status == :pending or
                 (status == :approved and type in ["refund", "payment_request"])
             )

      prepare build(sort: [inserted_at: :asc])
    end

    read :list do
      description "What the actor may see, newest first, optionally one status or type"

      argument :status, :atom do
        constraints one_of: [:pending, :approved, :rejected, :paid]
      end

      argument :type, :string do
        constraints match: ~r/^(expense|refund|payment_request)$/
      end

      filter expr(
               (is_nil(^arg(:status)) or status == ^arg(:status)) and
                 (is_nil(^arg(:type)) or type == ^arg(:type))
             )

      prepare build(sort: [date: :desc, inserted_at: :desc])
    end

    read :for_export do
      description "Approved and paid transactions dated within a period, oldest first"
      argument :from, :date, allow_nil?: false
      argument :to, :date, allow_nil?: false
      argument :unexported_only?, :boolean, default: false

      filter expr(
               status in [:approved, :paid] and date >= ^arg(:from) and date <= ^arg(:to) and
                 (not (^arg(:unexported_only?)) or is_nil(exported_at))
             )

      prepare build(sort: [date: :asc, inserted_at: :asc], load: [:user])
    end
  end

  @doc "The fields whose change sends a decided transaction back for approval."
  def figures, do: @figures
end
