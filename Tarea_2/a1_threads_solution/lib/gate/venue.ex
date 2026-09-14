defmodule Gate.Venue do
  @moduledoc """
  The module the grader calls. Write it once, in assignment 1, and then leave
  it alone.

  This is the glue and nothing else. Each callback turns a request into a pure state
  transition of `Gate.Sector` and hands that transition to `Gate.Sync.update/3`, which
  is the only code in the project that knows how the state is shared.

  Keeping this file free of processes is what makes the next three assignments a change
  of model instead of a rewrite. `mix gate.check` enforces it: `spawn`, `send`,
  `receive` and `Process` here are a hard failure.
  """

  @behaviour Gate.API

  # alias Gate.Sector
  # alias Gate.Sync

  @impl Gate.API
  def start_venue(spec) do
    Sync.start(spec)
  end

  @impl Gate.API
  def stop_venue(venue) do
    Sync.stop(venue)
  end

  @impl Gate.API
  def reserve(venue, sector, qty, mode) do
    Sync.update(venue, sector, fn current_sector, now ->
      {current_sector, _available} = Sector.availability(current_sector, now)

      case Sector.reserve(current_sector, qty, mode, now) do
        {:ok, new_sector, hold_id, seat_ids} -> {{:ok, hold_id, seat_ids}, new_sector}
        {:error, reason} -> {{:error, reason}, current_sector}
      end
    end)
  end

@impl Gate.API
  def confirm(venue, {sector_name, id} = hold_id) when is_atom(sector_name) and is_integer(id) do
    result =
      Sync.update(venue, sector_name, fn current_sector, now ->
        {current_sector, _available} = Sector.availability(current_sector, now)

        case Sector.confirm(current_sector, hold_id, now) do
          {:ok, new_sector, tickets} -> {{:ok, tickets}, new_sector}
          {:error, reason} -> {{:error, reason}, current_sector}
        end
      end)

    case result do
      {:error, :bad_sector} -> {:error, :unknown_hold}
      other -> other
    end
  end

  def confirm(_venue, _hold_id) do
    {:error, :unknown_hold}
  end

  @impl Gate.API
  def cancel(_venue, _hold_id) do
    raise "not implemented"
  end

  @impl Gate.API
  def availability(_venue, _sector) do
    raise "not implemented"
  end

  @impl Gate.API
  def snapshot(_venue) do
    raise "not implemented"
  end
end
