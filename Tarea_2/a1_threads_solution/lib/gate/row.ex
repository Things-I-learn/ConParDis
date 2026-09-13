defmodule Gate.Row do
  @moduledoc """
  One row of seats. Pure data, no processes.

  Contiguous seating is a question about one row, so a row is a useful thing to have a
  name for, and a sector then becomes a collection of rows. Nothing in the grader looks
  at this module, so if you would rather represent a sector some other way, do that
  instead and change this file.

  A seat is `:free`, `:held` or `:sold`, and never two of those at once.

  """

  @enforce_keys [:size, :status, :free]
  defstruct [:size, :status, :free]

  @type seat_no :: pos_integer
  @type status :: :free | :held | :sold
  @type t :: %__MODULE__{
          size: pos_integer,
          status: %{seat_no => status},
          free: non_neg_integer
        }

  @doc "A row of `size` free seats."
  @spec new(pos_integer) :: t
  def new(size) do
    status = Map.new(1..size, fn seat_no -> {seat_no, :free} end)
    %__MODULE__{
      size: size,
      status: status,
      free: size
    }
  end

  @doc "How many seats of the row are free."
  @spec free_count(t) :: non_neg_integer
  def free_count(row) do
    row.free
  end

  @doc """
  Hold up to `qty` free seats and say which ones.

  Up to, so the caller gets between 0 and `qty`. That is what lets a reserve in `:any`
  mode walk several rows and collect what it needs.
  """
  @spec alloc_upto(t, pos_integer) :: {t, [seat_no]}
  def alloc_upto(row, qty) do
    seats = 1..row.size
    |> Enum.filter(fn seat_no -> row.status[seat_no] == :free end)
    |> Enum.take(qty)

    new_status = Enum.reduce(seats, row.status, fn seat_no, status -> Map.put(status, seat_no, :held) end)

    new_row = %{row | status: new_status, free: row.free - length(seats)}

    {new_row, seats}
  end

  @doc "Hold `qty` seats with consecutive numbers, or nothing at all."
  @spec alloc_contiguous(t, pos_integer) :: {:ok, t, [seat_no]} | :none
  def alloc_contiguous(row, qty) do
    seats = 1..row.size
    |> Enum.chunk_every(qty, 1, :discard)
    |> Enum.find(fn seats -> Enum.all?(seats, fn seat_no -> row.status[seat_no] == :free end) end)

  case seats do
    nil ->
      :none
    seats ->
      new_status = Enum.reduce(seats, row.status, fn seat_no, status -> Map.put(status, seat_no, :held) end)
      new_row = %{ row | status: new_status, free: row.free - qty}

      {:ok, new_row, seats}
  end

  end

  @doc "Put held seats back to free."
  @spec release(t, [seat_no]) :: t
  def release(row, seats) do
    new_status =Enum.reduce(seats, row.status, fn seat_no, status -> Map.put(status, seat_no, :free) end)
    new_row = %{row | status: new_status, free: row.free + length(seats)}
    new_row
  end

  @doc "Turn held seats into sold seats."
  def sell(row, seats) do
    new_status = Enum.reduce(seats, row.status, fn seat_no, status -> Map.put(status, seat_no, :sold) end)
    new_row = %{ row | status: new_status}
    new_row
  end

  @doc "Seat numbers of the row grouped by status."
  @spec by_status(t) :: %{free: [seat_no], held: [seat_no], sold: [seat_no]}
  def by_status(row) do
    row.status
    |> Enum.reduce(%{free: [], held: [], sold: []},
    fn {seat_no, status}, acc -> Map.update!(acc, status, fn seats -> [seat_no | seats] end) end)
    |> Map.new(fn {status, seats} -> {status, Enum.sort(seats)} end)
  end
end
