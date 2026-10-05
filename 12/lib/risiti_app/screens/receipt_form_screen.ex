defmodule RisitiApp.Screens.ReceiptFormScreen do
  use Mob.Screen

  @impl Mob.Screen
  def mount(params, _session, socket) do
    # Opened with %{id: id} to edit a receipt, or with no params for a new one.
    receipt = if id = params[:id], do: RisitiApp.Transactions.get_transaction!(id)
    {:ok, Mob.Socket.assign(socket, :receipt, receipt)}
  end

  @impl Mob.Screen
  def render(assigns) do
    ~MOB"""
    <Column background={:background} fill_height={true}>
      <Header title={title(@receipt)} show_back={true} />
    </Column>
    """
  end

  defp title(nil), do: "New receipt"
  defp title(receipt), do: receipt.vendor

  @impl Mob.Screen
  def handle_info({:tap, :back}, socket) do
    {:noreply, Mob.Socket.pop_screen(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}
end
