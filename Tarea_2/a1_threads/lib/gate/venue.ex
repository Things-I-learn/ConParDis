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
  def start_venue(_spec) do
    raise "not implemented"
  end

  @impl Gate.API
  def stop_venue(_venue) do
    raise "not implemented"
  end

  @impl Gate.API
  def reserve(_venue, _sector, _qty, _mode) do
    raise "not implemented"
  end

  @impl Gate.API
  def confirm(_venue, _hold_id) do
    raise "not implemented"
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
