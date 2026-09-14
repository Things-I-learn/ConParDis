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

  defstruct [:name, :price_cop, :ttl_ms, :rows, :holds, :free, :next_hold_id]

  @doc "An empty sector, built from one entry of a venue spec."
  @spec new(Gate.API.sector(), map, pos_integer) :: t
  def new(name, shape, ttl_ms) do
    rows = Map.new(1..shape.rows, fn row_no -> {row_no, Gate.Row.new(shape.seats_per_row)} end)

    %__MODULE__{
      name: name,
      price_cop: shape.price_cop,
      ttl_ms: ttl_ms,
      rows: rows,
      holds: %{},
      free: shape.rows * shape.seats_per_row,
      next_hold_id: 1
    }
  end

  @doc """
  Hold `qty` seats and say which ones, or say why not.

  All of the seats or none of them. A request that cannot be served leaves the sector
  exactly as it was.
  """
  @spec reserve(t, pos_integer, :any | :contiguous, integer) ::
          {:ok, t, Gate.API.hold_id(), [Gate.API.seat_id()]}
          | {:error, :sold_out | :no_contiguous_block}
    def reserve(sector, qty, :contiguous, now) do
      sector = expire_holds(sector, now)

      if sector.free < qty do
        {:error, :sold_out}
      else
        result = 1..map_size(sector.rows) |> Enum.find_value(fn row_no -> row = sector.rows[row_no]
            case Gate.Row.alloc_contiguous(row, qty) do
              :none -> nil
              {:ok, new_row, seat_nos} -> {row_no, new_row, seat_nos}
            end
          end)

        case result do
          nil -> {:error, :no_contiguous_block}
          {row_no, new_row, seat_nos} -> hold_id = {sector.name, sector.next_hold_id}

            hold = %{
              state: :held,
              seats: Enum.map(seat_nos, fn seat_no -> {row_no, seat_no} end),
              expires_at: now + sector.ttl_ms
            }

            new_rows = Map.put(sector.rows, row_no, new_row)
            new_holds = Map.put(sector.holds, hold_id, hold)
            seat_ids = Enum.map(seat_nos, fn seat_no -> Gate.VenueSpec.seat_id(sector.name, row_no, seat_no) end)

            new_sector = %{
              sector
              | rows: new_rows,
                holds: new_holds,
                free: sector.free - qty,
                next_hold_id: sector.next_hold_id + 1
            }

            {:ok, new_sector, hold_id, seat_ids}
        end
      end
    end

    def reserve(sector, qty, :any, now) do
      sector = expire_holds(sector, now)

      if sector.free < qty do
        {:error, :sold_out}
      else
        {new_rows, seats, remaining} =
          Enum.reduce_while(1..map_size(sector.rows), {sector.rows, [], qty}, fn row_no, {rows, seats, remaining} ->
            row = rows[row_no]
            {new_row, seat_nos} = Gate.Row.alloc_upto(row, remaining)
            new_seats = Enum.map(seat_nos, fn seat_no -> {row_no, seat_no} end)
            new_rows = Map.put(rows, row_no, new_row)
            remaining = remaining - length(seat_nos)
            result = {new_rows, seats ++ new_seats, remaining}

            if remaining == 0 do
              {:halt, result}
            else
              {:cont, result}
            end
          end)

        if remaining > 0 do
          {:error, :sold_out}
        else
          hold_id = {sector.name, sector.next_hold_id}

          hold = %{
            state: :held,
            seats: seats,
            expires_at: now + sector.ttl_ms
          }

          new_holds = Map.put(sector.holds, hold_id, hold)

          new_sector = %{
            sector
            | rows: new_rows,
              holds: new_holds,
              free: sector.free - qty,
              next_hold_id: sector.next_hold_id + 1
          }

          seat_ids = Enum.map(seats, fn {row_no, seat_no} -> Gate.VenueSpec.seat_id(sector.name, row_no, seat_no) end)

          {:ok, new_sector, hold_id, seat_ids}
        end
      end
    end



  @doc "Sell the seats of a live hold, all of them together."
  @spec confirm(t, Gate.API.hold_id(), integer) ::
          {:ok, t, [Gate.API.ticket()]}
          | {:error, :expired | :unknown_hold | :already_confirmed}
  def confirm(sector, hold_id, now) do
    case Map.get(sector.holds, hold_id) do
      nil ->
        {:error, :unknown_hold}

      %{state: :confirmed} ->
        {:error, :already_confirmed}

      %{state: :cancelled} ->
        {:error, :unknown_hold}

      %{state: :expired} ->
        {:error, :expired}

      hold = %{state: :held} ->
        if now >= hold.expires_at do
          {:error, :expired}
        else
          new_rows =
            sell_hold_seats(sector.rows, hold.seats)

          new_holds =
            Map.put(
              sector.holds,
              hold_id,
              %{hold | state: :confirmed}
            )

          new_sector = %{
            sector
            | rows: new_rows,
              holds: new_holds
          }

          tickets =
            Enum.map(hold.seats, fn {row_no, seat_no} ->
              %{
                seat_id:
                  Gate.VenueSpec.seat_id(
                    sector.name,
                    row_no,
                    seat_no
                  ),
                sector: sector.name,
                price_cop: sector.price_cop,
                hold_id: hold_id
              }
            end)

          {:ok, new_sector, tickets}
        end
    end
  end

  @doc "Give up a hold and free its seats."
  @spec cancel(t, Gate.API.hold_id(), integer) ::
          {:ok, t} | {:error, :unknown_hold | :already_confirmed}
  def cancel(sector, hold_id, now) do
    sector = expire_holds(sector, now)

    case Map.get(sector.holds, hold_id) do
      nil -> {:error, :unknown_hold}
      %{state: :confirmed} -> {:error, :already_confirmed}
      %{state: :cancelled} -> {:ok, sector}
      %{state: :expired} -> {:ok, sector}

      hold = %{state: :held} ->
        new_rows = release_hold_seats(sector.rows, hold.seats)
        new_holds = Map.put(sector.holds, hold_id, %{hold | state: :cancelled})
        new_sector = %{sector | rows: new_rows, holds: new_holds, free: sector.free + length(hold.seats)}

        {:ok, new_sector}
    end
  end

  @doc "Free seats of the sector, after dropping whatever has expired."
  @spec availability(t, integer) :: {t, non_neg_integer}
  def availability(sector, now) do
    sector = expire_holds(sector, now)
    {sector, sector.free}
  end

  @doc "A consistent cut of this sector, and the money made in it so far."
  @spec snapshot(t, integer) :: {t, Gate.API.snapshot()}
  def snapshot(sector, now) do
    sector = expire_holds(sector, now)

    snapshot =
      Enum.reduce(1..map_size(sector.rows), %{sold: [], held: [], free: [], revenue: 0}, fn row_no, acc ->
        row = sector.rows[row_no]
        statuses = Gate.Row.by_status(row)

        sold_ids = Enum.map(statuses.sold, fn seat_no -> Gate.VenueSpec.seat_id(sector.name, row_no, seat_no) end)
        held_ids = Enum.map(statuses.held, fn seat_no -> Gate.VenueSpec.seat_id(sector.name, row_no, seat_no) end)
        free_ids = Enum.map(statuses.free, fn seat_no -> Gate.VenueSpec.seat_id(sector.name, row_no, seat_no) end)

        %{sold: acc.sold ++ sold_ids, held: acc.held ++ held_ids, free: acc.free ++ free_ids, revenue: acc.revenue + length(sold_ids) * sector.price_cop}
      end)

    {sector, snapshot}
  end

  defp sell_hold_seats(rows, seats) do
    Enum.reduce(seats, rows, fn {row_no, seat_no}, current_rows ->
      row = current_rows[row_no]

      new_row =
        Gate.Row.sell(row, [seat_no])

      Map.put(current_rows, row_no, new_row)
    end)
  end
  defp release_hold_seats(rows, seats) do
    Enum.reduce(seats, rows, fn {row_no, seat_no}, current_rows ->
      row = current_rows[row_no]
      new_row = Gate.Row.release(row, [seat_no])
      Map.put(current_rows, row_no, new_row)
    end)
  end
  defp expire_holds(sector, now) do
    expired_ids =
      sector.holds
      |> Enum.filter(fn {_hold_id, hold} -> hold.state == :held and now >= hold.expires_at end)
      |> Enum.map(fn {hold_id, _hold} -> hold_id end)

    Enum.reduce(expired_ids, sector, fn hold_id, current_sector ->
      hold = current_sector.holds[hold_id]
      new_rows = release_hold_seats(current_sector.rows, hold.seats)
      new_holds = Map.put(current_sector.holds, hold_id, %{hold | state: :expired})

      %{current_sector | rows: new_rows, holds: new_holds, free: current_sector.free + length(hold.seats)}
    end)
  end
end
