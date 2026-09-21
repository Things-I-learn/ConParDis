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
  def new(_size) do
    raise "not implemented"
  end

  @doc "How many seats of the row are free."
  @spec free_count(t) :: non_neg_integer
  def free_count(_row) do
    raise "not implemented"
  end

  @doc """
  Hold up to `qty` free seats and say which ones.

  Up to, so the caller gets between 0 and `qty`. That is what lets a reserve in `:any`
  mode walk several rows and collect what it needs.
  """
  @spec alloc_upto(t, pos_integer) :: {t, [seat_no]}
  def alloc_upto(_row, _qty) do
    raise "not implemented"
  end

  @doc "Hold `qty` seats with consecutive numbers, or nothing at all."
  @spec alloc_contiguous(t, pos_integer) :: {:ok, t, [seat_no]} | :none
  def alloc_contiguous(_row, _qty) do
    raise "not implemented"
  end

  @doc "Put held seats back to free."
  @spec release(t, [seat_no]) :: t
  def release(_row, _seats) do
    raise "not implemented"
  end

  @doc "Turn held seats into sold seats."
  @spec sell(t, [seat_no]) :: t
  def sell(_row, _seats) do
    raise "not implemented"
  end

  @doc "Seat numbers of the row grouped by status."
  @spec by_status(t) :: %{free: [seat_no], held: [seat_no], sold: [seat_no]}
  def by_status(_row) do
    raise "not implemented"
  end
end
