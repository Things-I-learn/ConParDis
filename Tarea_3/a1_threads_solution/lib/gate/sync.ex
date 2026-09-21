defmodule Gate.Sync do
  @moduledoc """
  The concurrency layer. This is the file that changes between the four assignments, and
  in assignments 2, 3 and 4 it is the only one.

  It has one job. `Gate.Venue` hands it a pure transition and the name of a sector, and it
  has to run that transition somewhere safe and give the answer back. Safe, meaning: two
  clients touching the same sector cannot see or lose each other's work.

  Everything about processes lives here and only here. `spawn`, `send`, `receive`, `Task`,
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

  alias Gate.Sector
  @table :gate_sectors

  @typedoc "Whatever `Gate.Venue.start_venue/1` needs to hand back. Yours to define."
  @type venue :: term

  @doc "Set up whatever owns the state, and return the handle for it."
  @spec start(Gate.API.venue_spec()) :: {:ok, venue} | {:error, term}

  def start(%{sectors: sector_specs, ttl_ms: ttl_ms}) do
    with :ok <- iniciar_mnesia(), :ok <- crear_tabla() do
      venue = make_ref()

      resultado = :mnesia.transaction(fn ->
        Enum.each(sector_specs, fn {sector_name, shape} ->
          sector = Sector.new(sector_name, shape, ttl_ms)
          :mnesia.write({@table, {venue, sector_name}, sector})
        end)
      end)

      case resultado do
        {:atomic, :ok} -> {:ok, venue}
        {:aborted, reason} -> {:error, reason}
      end
    end
  end

  @doc "Take it all down. Calling this twice must still work."
  @spec stop(venue) :: :ok

  def stop(venue) do
    sector_names = sectors(venue)

    transaction = fn ->
      Enum.each(sector_names, fn sector_name ->
        key = {venue, sector_name}
        :mnesia.delete({@table, key})
      end)
    end

    case :mnesia.transaction(transaction) do
      {:atomic, :ok} -> :ok
      {:aborted, reason} -> raise "Mnesia transaction failed: #{inspect(reason)}"
    end
  end

  @doc "Sector names of a running venue."
  @spec sectors(venue) :: [Gate.API.sector()]

  def sectors(venue) do
    transaction = fn ->
      pattern = {@table, {venue, :_}, :_}

      :mnesia.match_object(@table, pattern, :read)
      |> Enum.map(fn {@table, {_venue, sector_name}, _sector} -> sector_name end)
    end

    case :mnesia.transaction(transaction) do
      {:atomic, sector_names} -> sector_names
      {:aborted, reason} -> raise "Mnesia transaction failed: #{inspect(reason)}"
    end
  end
  @doc """
  Run a pure transition against one sector, as one indivisible step.

  See the module documentation. This function is the whole assignment.
  """
  @spec update(
          venue,
          Gate.API.sector(),
          (Gate.Sector.t(), integer -> {result, Gate.Sector.t()})
        ) :: result | {:error, :bad_sector}
        when result: term

  def update(venue, sector_name, fun) do
    key = {venue, sector_name}

    transaction = fn ->
      case :mnesia.read(@table, key, :write) do
        [{@table, ^key, current_sector}] ->
          now = System.monotonic_time(:millisecond)
          {result, new_sector} = fun.(current_sector, now)
          :mnesia.write({@table, key, new_sector})
          result

        [] -> {:error, :bad_sector}
      end
    end

    case :mnesia.transaction(transaction) do
      {:atomic, result} -> result
      {:aborted, reason} -> raise "Mnesia transaction failed: #{inspect(reason)}"
    end
  end


  defp iniciar_mnesia do
    case :mnesia.start() do
      :ok -> :ok
      {:error, {:already_started, :mnesia}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp crear_tabla do
    case :mnesia.create_table(@table, attributes: [:key, :sector], type: :set, ram_copies: [node()]) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, @table}} -> :ok
      {:aborted, reason} -> {:error, reason}
    end
  end


end
