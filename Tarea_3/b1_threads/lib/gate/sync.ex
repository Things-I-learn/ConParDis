defmodule Gate.Sync do
  @moduledoc """
  The concurrency layer. This is the file that changes between the four assignments, and
  in assignments 2, 3 and 4 it is the only one.

  It has one job. `Gate.Venue` hands it a pure transition and the name of a sector, and it
  has to run that transition somewhere safe and give the answer back. Safe, meaning:  two
  clients touching the same sector cannot see or lose each other's work.

  Everything about processes lives here and only here. `spawn`, `send`, `receive`,`Task`,
  `Process`, and whatever you build out of them.

  ## The contract

      update(venue, sector, fun)

  where `fun` takes the current sector value and the current time in milliseconds and
  returns `{result, new_sector_value}`. `update/3` returns the `result`, or
  `{:error, :bad_sector}` if there is no such sector.

  The whole of `fun` has to happen as one indivisible step. Reading the sector, working
  out the answer, and writing the sector back cannot be three steps that another client
  can slip between. How you arrange that is the assignment.

  """

  @typedoc "Whatever `Gate.Venue.start_venue/1` needs to hand back. Yours to define."
  @type venue :: term

  @doc "Set up whatever owns the state, and return the handle for it."
  @spec start(Gate.API.venue_spec()) :: {:ok, venue} | {:error, term}
  def start(_spec) do
    raise "not implemented"
  end

  @doc "Take it all down. Calling this twice must still work."
  @spec stop(venue) :: :ok
  def stop(_venue) do
    raise "not implemented"
  end

  @doc "Sector names of a running venue."
  @spec sectors(venue) :: [Gate.API.sector()]
  def sectors(_venue) do
    raise "not implemented"
  end

  @doc """
  Run a pure transition against one sector, as one indivisible step.

  See the module documentation. This function is the whole assignment.
  """
  @spec update(venue, Gate.API.sector(), (Gate.Sector.t(), integer -> {result, Gate.Sector.t()})) ::
          result | {:error, :bad_sector}
        when result: term
  def update(_venue, _sector, _fun) do
    raise "not implemented"
  end
end
