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

  @typedoc "Whatever `Gate.Venue.start_venue/1` needs to hand back. Yours to define."
  @type venue :: term

  @doc "Set up whatever owns the state, and return the handle for it."
  @spec start(Gate.API.venue_spec()) :: {:ok, venue} | {:error, term}

  def start(%{sectors: sector_specs, ttl_ms: ttl_ms}) do
    sectors = Map.new(sector_specs, fn {sector_name, shape} -> {sector_name, Sector.new(sector_name, shape, ttl_ms)} end)

    venue = spawn(fn ->
      loop(%{
        sectors: sectors,
        locks: %{},
        waiters: %{},
        lock_monitors: %{}
      })
    end)

    {:ok, venue}
  end

  @doc "Take it all down. Calling this twice must still work."
  @spec stop(venue) :: :ok

  def stop(venue) do
    monitor_ref = Process.monitor(venue)
    send(venue, :stop)

    receive do
      {:DOWN, ^monitor_ref, :process, ^venue, _reason} -> :ok
    end
  end

  @doc "Sector names of a running venue."
  @spec sectors(venue) :: [Gate.API.sector()]

  def sectors(venue) do
    ref = make_ref()
    send(venue, {:sectors, self(), ref})

    receive do
      {^ref, sector_names} -> sector_names
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

  def update(venue, sector, fun) do
    caller = self()
    acquire_ref = make_ref()

    send(venue, {:acquire, caller, acquire_ref, sector})

    receive do
      {^acquire_ref, {:error, :bad_sector}} ->
        {:error, :bad_sector}

      {^acquire_ref, {:ok, current_sector}} ->
        now = System.monotonic_time(:millisecond)
        {result, new_sector} = fun.(current_sector, now)
        release_ref = make_ref()

        send(
          venue,
          {:release, caller, release_ref, sector, new_sector}
        )

        receive do
          {^release_ref, :ok} -> result
        end
    end
  end

  # ============================================================
  # Entregar el mutex al siguiente proceso
  # ============================================================

  defp give_lock_to_next(state, sector_name) do
    queue = Map.get(state.waiters, sector_name, :queue.new())

    case :queue.out(queue) do
      {:empty, _queue} ->
        %{
          state
          | locks: Map.delete(state.locks, sector_name),
            waiters: Map.delete(state.waiters, sector_name),
            lock_monitors: Map.delete(state.lock_monitors, sector_name)
        }

      {{:value, {next_caller, next_ref}}, remaining_queue} ->
        current_sector = Map.fetch!(state.sectors, sector_name)

        # Monitoreamos al nuevo dueño del mutex.
        monitor_ref = Process.monitor(next_caller)

        send(
          next_caller,
          {next_ref, {:ok, current_sector}}
        )

        new_waiters =
          if :queue.is_empty(remaining_queue) do
            Map.delete(state.waiters, sector_name)
          else
            Map.put(
              state.waiters,
              sector_name,
              remaining_queue
            )
          end

        %{
          state
          | locks: Map.put(state.locks, sector_name, next_caller),
            waiters: new_waiters,
            lock_monitors: Map.put(state.lock_monitors, sector_name, monitor_ref)
        }
    end
  end

  # ============================================================
  # Loop principal
  # ============================================================

  defp loop(state) do
    receive do
      # --------------------------------------------------------
      # Solicitar el mutex de un sector
      # --------------------------------------------------------

      {:acquire, caller, ref, sector_name} ->
        cond do
          # El sector no existe.
          not Map.has_key?(state.sectors, sector_name) ->
            send(
              caller,
              {ref, {:error, :bad_sector}}
            )

            loop(state)

          # El mutex ya está ocupado.
          # El proceso entra en la cola.
          Map.has_key?(state.locks, sector_name) ->
            queue = Map.get(state.waiters, sector_name, :queue.new())
            new_queue = :queue.in({caller, ref}, queue)
            new_waiters = Map.put(state.waiters, sector_name, new_queue)

            loop(%{
              state
              | waiters: new_waiters
            })

          # El mutex está libre.
          true ->
            current_sector = Map.fetch!(state.sectors, sector_name)

            # Monitoreamos al proceso que será dueño del mutex.
            monitor_ref = Process.monitor(caller)

            send(
              caller,
              {ref, {:ok, current_sector}}
            )

            new_locks = Map.put(state.locks, sector_name, caller)
            new_lock_monitors = Map.put(state.lock_monitors, sector_name, monitor_ref)

            loop(%{
              state
              | locks: new_locks,
                lock_monitors: new_lock_monitors
            })
        end

      # --------------------------------------------------------
      # Liberar el mutex y guardar el nuevo estado
      # --------------------------------------------------------

      {:release, caller, ref, sector_name, new_sector} ->
        case Map.get(state.locks, sector_name) do
          ^caller ->
            # El proceso terminó normalmente.
            #
            # Ya no necesitamos vigilarlo como dueño del mutex.
            monitor_ref = Map.get(state.lock_monitors, sector_name)

            if monitor_ref != nil do
              Process.demonitor(
                monitor_ref,
                [:flush]
              )
            end

            new_sectors = Map.put(state.sectors, sector_name, new_sector)

            state_without_monitor = %{
              state
              | sectors: new_sectors,
                lock_monitors: Map.delete(state.lock_monitors, sector_name)
            }

            new_state = give_lock_to_next(state_without_monitor, sector_name)

            send(
              caller,
              {ref, :ok}
            )

            loop(new_state)

          _other ->
            send(
              caller,
              {ref, {:error, :not_owner}}
            )

            loop(state)
        end

      # --------------------------------------------------------
      # El dueño de un mutex murió
      # --------------------------------------------------------

      {:DOWN, monitor_ref, :process, caller, _reason} ->
        owner =
          Enum.find(
            state.lock_monitors,
            fn {_sector_name, stored_monitor_ref} ->
              stored_monitor_ref == monitor_ref
            end
          )

        case owner do
          nil ->
            # Este DOWN no corresponde a un mutex actual.
            loop(state)

          {sector_name, ^monitor_ref} ->
            case Map.get(state.locks, sector_name) do
              ^caller ->
                # El proceso murió antes de hacer release.
                #
                # IMPORTANTE:
                # NO modificamos state.sectors porque la transición
                # del proceso muerto nunca terminó.
                state_without_monitor = %{
                  state
                  | lock_monitors: Map.delete(state.lock_monitors, sector_name)
                }

                new_state = give_lock_to_next(state_without_monitor, sector_name)

                loop(new_state)

              _other ->
                loop(state)
            end
        end

      # --------------------------------------------------------
      # Consultar nombres de sectores
      # --------------------------------------------------------

      {:sectors, caller, ref} ->
        sector_names = Map.keys(state.sectors)

        send(
          caller,
          {ref, sector_names}
        )

        loop(state)

      # --------------------------------------------------------
      # Terminar el venue
      # --------------------------------------------------------

      :stop ->
        :ok
    end
  end
end
