defmodule Gate.Sector do
  @moduledoc """
  All the ticketing rules for one sector. Pure data and pure functions. No processes, no
  messages, no locks, not one of them anywhere in this file.

  Take into account:

  - Write it in assignment 1 and copy it into the next three without touching a line.
  - This is the part of the project that does not change between the four assignments, so
    it is worth getting right once!
  - If you find yourself editing it in assignment 2, the boundary between the rules and
    the model is in the wrong place!

  """

  @type hold_state :: :held | :confirmed | :cancelled | :expired

  @typedoc "Your representation of one sector. The fields below are a suggestion."
  @type t :: %__MODULE__{}

  defstruct [:name, :price_cop, :ttl_ms, :rows, :holds, :free]

  @doc "An empty sector, built from one entry of a venue spec."
  @spec new(Gate.API.sector(), map, pos_integer) :: t
  def new(_name, _shape, _ttl_ms) do
    raise "not implemented"
  end

  @doc """
  Hold `qty` seats and say which ones, or say why not.

  All of the seats or none of them. A request that cannot be served leaves the sector
  exactly as it was.
  """
  @spec reserve(t, pos_integer, :any | :contiguous, integer) ::
          {:ok, t, Gate.API.hold_id(), [Gate.API.seat_id()]}
          | {:error, :sold_out | :no_contiguous_block}
  def reserve(_sector, _qty, _mode, _now) do
    raise "not implemented"
  end

  @doc "Sell the seats of a live hold, all of them together."
  @spec confirm(t, Gate.API.hold_id(), integer) ::
          {:ok, t, [Gate.API.ticket()]}
          | {:error, :expired | :unknown_hold | :already_confirmed}
  def confirm(_sector, _hold_id, _now) do
    raise "not implemented"
  end

  @doc "Give up a hold and free its seats."
  @spec cancel(t, Gate.API.hold_id(), integer) ::
          {:ok, t} | {:error, :unknown_hold | :already_confirmed}
  def cancel(_sector, _hold_id, _now) do
    raise "not implemented"
  end

  @doc "Free seats of the sector, after dropping whatever has expired."
  @spec availability(t, integer) :: {t, non_neg_integer}
  def availability(_sector, _now) do
    raise "not implemented"
  end

  @doc "A consistent cut of this sector, and the money made in it so far."
  @spec snapshot(t, integer) :: {t, Gate.API.snapshot()}
  def snapshot(_sector, _now) do
    raise "not implemented"
  end
end
