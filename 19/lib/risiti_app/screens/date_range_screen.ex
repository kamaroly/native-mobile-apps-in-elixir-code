defmodule RisitiApp.Screens.DateRangeScreen do
  @moduledoc """
  Pick the dates the list shows: from one day to another. Either can be
  left empty, for no limit that way.

  Mount params: `from` and `to` (dates or nil) to start with, and `notify`,
  the screen that opened it. That screen gets `{:dates_chosen, from, to}`
  just before this one goes back to it.
  """

  use Mob.Screen

  alias RisitiApp.Components.{ActionButton, FormField}
  alias RisitiApp.Transactions

  @impl Mob.Screen
  def mount(params, _session, socket) do
    socket =
      Mob.Socket.assign(socket,
        notify: params[:notify],
        from: input(params[:from]),
        to: input(params[:to]),
        errors: %{}
      )

    {:ok, socket}
  end

  defp input(%Date{} = date), do: Date.to_iso8601(date)
  defp input(nil), do: ""

  @impl Mob.Screen
  def render(assigns) do
    ~MOB"""
    <Column background={:background} fill_width={true} fill_height={true}>
      <Header title="Choose dates" show_back={true} />
      <Column padding_left={18} padding_right={18} fill_width={true}>
        {FormField.field(
          label: "From",
          key: :from,
          value: @from,
          placeholder: "e.g. #{Date.to_iso8601(Date.beginning_of_month(Transactions.today()))}",
          hint: "Leave empty to start from the first transaction",
          error: @errors[:from]
        )}
        {FormField.field(
          label: "To",
          key: :to,
          value: @to,
          placeholder: "e.g. #{Date.to_iso8601(Transactions.today())}",
          hint: "Leave empty to go up to today",
          error: @errors[:to]
        )}
      </Column>
      <Spacer weight={1} />
      <Column fill_width={true} padding={18}>
        {ActionButton.button("check", "Show these dates", :apply)}
      </Column>
    </Column>
    """
  end

  @impl Mob.Screen
  def handle_info({:change, key, value}, socket) when key in [:from, :to] do
    {:noreply, Mob.Socket.assign(socket, key, value)}
  end

  def handle_info({:tap, :apply}, socket) do
    case parse(socket.assigns) do
      {:ok, from, to} ->
        if pid = socket.assigns.notify, do: send(pid, {:dates_chosen, from, to})
        {:noreply, Mob.Socket.pop_screen(socket)}

      {:error, errors} ->
        {:noreply, Mob.Socket.assign(socket, :errors, errors)}
    end
  end

  def handle_info({:tap, :back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  @doc """
  The two dates typed in, checked.

      iex> RisitiApp.Screens.DateRangeScreen.parse(%{from: "2026-09-01", to: " "})
      {:ok, ~D[2026-09-01], nil}

      iex> RisitiApp.Screens.DateRangeScreen.parse(%{from: "2026-09-10", to: "2026-09-01"})
      {:error, %{to: "must be on or after the From date"}}
  """
  def parse(%{from: from, to: to}) do
    case {date(from), date(to)} do
      {{:ok, from}, {:ok, to}} when is_nil(from) or is_nil(to) ->
        {:ok, from, to}

      {{:ok, from}, {:ok, to}} ->
        if Date.compare(from, to) == :gt,
          do: {:error, %{to: "must be on or after the From date"}},
          else: {:ok, from, to}

      {from, to} ->
        {:error,
         for(
           {key, :error} <- [from: from, to: to],
           into: %{},
           do: {key, "use the format 2026-09-23"}
         )}
    end
  end

  defp date(text) do
    case String.trim(text) do
      "" ->
        {:ok, nil}

      trimmed ->
        case Date.from_iso8601(trimmed) do
          {:ok, date} -> {:ok, date}
          {:error, _} -> :error
        end
    end
  end
end
