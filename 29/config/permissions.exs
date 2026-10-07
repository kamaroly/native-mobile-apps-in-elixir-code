import Config

# What a team's groups can grant, as "area:what" (e.g.
# "transactions:approve_transactions"). Owners hold every one. Without
# transactions:list_all_transactions, people see only their own.
config :risiti,
  permissions: [
    transactions: [
      :list_all_transactions,
      :approve_transactions,
      :mark_transactions_paid,
      :export_transactions
    ]
  ]
