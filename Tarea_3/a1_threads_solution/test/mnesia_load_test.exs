defmodule Gate.MnesiaLoadTest do
  use ExUnit.Case, async: false

  alias Gate.Venue
  alias Gate.VenueSpec

  @price 100_000
  @workers 48
  @timeout_ms 180_000
  @large_timeout_ms 600_000

  defp shape(rows, seats_per_row, price_cop \\ @price) do
    %{rows: rows, seats_per_row: seats_per_row, price_cop: price_cop}
  end

  defp new_venue(sectors, ttl_ms \\ 120_000) do
    spec = %{sectors: sectors, ttl_ms: ttl_ms}
    {:ok, venue} = Venue.start_venue(spec)
    on_exit(fn -> Venue.stop_venue(venue) end)
    {venue, spec}
  end

  # Cada cliente ejecuta una reserva seguida de una confirmacion, cancelacion
  # o abandono. Una reserva fallida no hace una segunda solicitud implicitamente.
  defp operation(venue, {sector, qty, mode, action}) do
    case Venue.reserve(venue, sector, qty, mode) do
      {:ok, hold_id, seats} ->
        case action do
          :buy ->
            case Venue.confirm(venue, hold_id) do
              {:ok, tickets} -> {:bought, tickets}
              other -> {:unexpected, {:confirm, other}}
            end

          :cancel ->
            case Venue.cancel(venue, hold_id) do
              :ok -> {:cancelled, []}
              other -> {:unexpected, {:cancel, other}}
            end

          :abandon ->
            {:held, seats}
        end

      {:error, reason} when reason in [:sold_out, :no_contiguous_block] ->
        {:rejected, reason}

      other ->
        {:unexpected, {:reserve, other}}
    end
  end

  defp empty_stats do
    %{
      attempts: 0,
      bought: 0,
      cancelled: 0,
      held: 0,
      rejected: %{},
      tickets: [],
      unexpected: [],
      latencies_us: []
    }
  end

  defp record(stats, result, elapsed_us) do
    stats = %{stats | attempts: stats.attempts + 1, latencies_us: [elapsed_us | stats.latencies_us]}

    case result do
      {:bought, tickets} ->
        %{stats | bought: stats.bought + 1, tickets: Enum.reverse(tickets, stats.tickets)}

      {:cancelled, _} ->
        %{stats | cancelled: stats.cancelled + 1}

      {:held, _} ->
        %{stats | held: stats.held + 1}

      {:rejected, reason} ->
        %{stats | rejected: Map.update(stats.rejected, reason, 1, &(&1 + 1))}

      {:unexpected, reason} ->
        %{stats | unexpected: [reason | stats.unexpected]}
    end
  end

  defp run_chunk(venue, requests) do
    Enum.reduce(requests, empty_stats(), fn request, stats ->
      started_us = System.monotonic_time(:microsecond)
      result = operation(venue, request)
      elapsed_us = System.monotonic_time(:microsecond) - started_us
      record(stats, result, elapsed_us)
    end)
  end

  # Usamos un numero acotado de procesos: 40 000 solicitudes NO significan
  # 40 000 procesos vivos al mismo tiempo. Cada proceso ejecuta su lote.
  defp run_parallel(venue, requests, workers \\ @workers, timeout_ms \\ @timeout_ms) do
    parent = self()
    run_ref = make_ref()
    chunk_size = max(div(length(requests) + workers - 1, workers), 1)

    monitored =
      for chunk <- Enum.chunk_every(requests, chunk_size) do
        spawn_monitor(fn ->
          send(parent, {:finished, run_ref, self(), run_chunk(venue, chunk)})
        end)
      end

    pending = MapSet.new(Enum.map(monitored, fn {pid, _monitor} -> pid end))
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    started_us = System.monotonic_time(:microsecond)

    try do
      summaries = collect(run_ref, pending, [], deadline)
      elapsed_us = System.monotonic_time(:microsecond) - started_us
      {elapsed_us, merge_stats(summaries)}
    after
      Enum.each(monitored, fn {pid, monitor} ->
        if Process.alive?(pid), do: Process.exit(pid, :kill)
        Process.demonitor(monitor, [:flush])
      end)
    end
  end

  defp collect(run_ref, pending, summaries, deadline) do
    if MapSet.size(pending) == 0 do
      summaries
    else
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:finished, ^run_ref, pid, stats} ->
          if MapSet.member?(pending, pid) do
            collect(run_ref, MapSet.delete(pending, pid), [stats | summaries], deadline)
          else
            collect(run_ref, pending, summaries, deadline)
          end

        {:DOWN, _monitor, :process, pid, reason} when reason != :normal ->
          flunk("El cliente #{inspect(pid)} termino inesperadamente: #{inspect(reason)}")
      after
        remaining -> flunk("No terminaron todos los clientes dentro del plazo global de prueba")
      end
    end
  end

  defp merge_stats(summaries) do
    Enum.reduce(summaries, empty_stats(), fn summary, acc ->
      rejected = Map.merge(acc.rejected, summary.rejected, fn _reason, a, b -> a + b end)

      %{
        attempts: acc.attempts + summary.attempts,
        bought: acc.bought + summary.bought,
        cancelled: acc.cancelled + summary.cancelled,
        held: acc.held + summary.held,
        rejected: rejected,
        tickets: summary.tickets ++ acc.tickets,
        unexpected: summary.unexpected ++ acc.unexpected,
        latencies_us: summary.latencies_us ++ acc.latencies_us
      }
    end)
  end

  defp rejected_total(stats), do: stats.rejected |> Map.values() |> Enum.sum()

  defp check_accounting(stats, expected_attempts) do
    assert stats.attempts == expected_attempts
    assert stats.unexpected == []
    assert stats.bought + stats.cancelled + stats.held + rejected_total(stats) == expected_attempts
  end

  # Compara el estado FINAL contra los tickets entregados, la capacidad real
  # del spec, la particion libre/reservado/vendido y los ingresos registrados.
  defp check_snapshot(venue, spec, tickets, expected_held \\ 0) do
    snapshot = Venue.snapshot(venue)
    sold_ids = Enum.map(tickets, & &1.seat_id)
    sold = MapSet.new(snapshot.sold)
    held = MapSet.new(snapshot.held)
    free = MapSet.new(snapshot.free)
    # all_seat_ids/1 solo recorre los sectores del concierto oficial.
    # Las pruebas adversariales usan sectores inventados; los generamos
    # directamente desde cada spec para no omitir ninguno.
    all_ids =
      for {sector, shape} <- spec.sectors,
          row <- 1..shape.rows,
          seat <- 1..shape.seats_per_row do
        VenueSpec.seat_id(sector, row, seat)
      end

    all = MapSet.new(all_ids)

    assert length(sold_ids) == MapSet.size(MapSet.new(sold_ids)), "Se emitieron tickets duplicados"
    assert length(snapshot.sold) == MapSet.size(sold), "Snapshot contiene vendidos duplicados"
    assert length(snapshot.held) == MapSet.size(held), "Snapshot contiene reservas duplicadas"
    assert length(snapshot.free) == MapSet.size(free), "Snapshot contiene libres duplicados"
    assert sold == MapSet.new(sold_ids), "Las ventas en Mnesia no coinciden con los tickets entregados"
    assert MapSet.disjoint?(sold, held)
    assert MapSet.disjoint?(sold, free)
    assert MapSet.disjoint?(held, free)
    assert MapSet.union(sold, MapSet.union(held, free)) == all
    assert MapSet.size(held) == expected_held
    assert snapshot.revenue == Enum.sum(Enum.map(tickets, & &1.price_cop))
    snapshot
  end

  defp print_metrics(label, elapsed_us, stats) do
    sorted = Enum.sort(stats.latencies_us)
    count = length(sorted)
    p95_us = Enum.at(sorted, max(ceil(count * 0.95) - 1, 0), 0)
    p99_us = Enum.at(sorted, max(ceil(count * 0.99) - 1, 0), 0)
    ms = Float.round(elapsed_us / 1_000, 1)
    throughput = Float.round(stats.attempts * 1_000_000 / max(elapsed_us, 1), 1)

    IO.puts("\n#{label}: #{stats.attempts} intentos; #{ms} ms; #{throughput} intentos/s")
    IO.puts("Compras=#{stats.bought}, cancelaciones=#{stats.cancelled}, abandonos=#{stats.held}, rechazos=#{inspect(stats.rejected)}")
    IO.puts("Latencia por intento: p95=#{Float.round(p95_us / 1_000, 2)} ms; p99=#{Float.round(p99_us / 1_000, 2)} ms")
  end

  @tag :carga_grande
  @tag timeout: 900_000
  test "40 000 solicitudes demandan exactamente 72 000 asientos en El Campin" do
    # TTL amplio para aislar la carga de compra; la expiracion se prueba aparte.
    spec = VenueSpec.el_campin(ttl_ms: 600_000)
    assert VenueSpec.capacity(spec) == 36_016
    {:ok, venue} = Venue.start_venue(spec)
    on_exit(fn -> Venue.stop_venue(venue) end)

    sectors = VenueSpec.sectors()
    cheap = [:norte_baja, :sur_baja, :oriental_norte_baja]

    requests =
      for i <- 1..40_000 do
        qty = if rem(i, 5) == 0, do: 1, else: 2
        mode = if rem(i, 7) == 0, do: :contiguous, else: :any

        sector =
          if rem(i, 4) == 0 do
            Enum.at(sectors, rem(div(i, 4), length(sectors)))
          else
            Enum.at(cheap, rem(i, length(cheap)))
          end

        {sector, qty, mode, :buy}
      end

    assert length(requests) == 40_000
    assert Enum.sum(Enum.map(requests, fn {_sector, qty, _mode, _action} -> qty end)) == 72_000

    {elapsed_us, stats} = run_parallel(venue, requests, 64, @large_timeout_ms)
    print_metrics("Carga completa de El Campin", elapsed_us, stats)
    check_accounting(stats, 40_000)
    assert stats.bought > 0
    assert rejected_total(stats) > 0
    assert length(stats.tickets) <= 36_016
    check_snapshot(venue, spec, stats.tickets)
  end

  test "adversarial: todos compiten por el sector mas pequeno" do
    {venue, spec} = new_venue(%{soundcheck_vip: shape(32, 40)}, 120_000)
    requests = for _ <- 1..2_000, do: {:soundcheck_vip, 2, :any, :buy}
    {elapsed_us, stats} = run_parallel(venue, requests)
    print_metrics("Contencion en el sector mas pequeno", elapsed_us, stats)
    check_accounting(stats, 2_000)
    assert stats.bought == 640
    assert stats.rejected == %{sold_out: 1_360}
    snapshot = check_snapshot(venue, spec, stats.tickets)
    assert length(snapshot.sold) == 1_280
    assert snapshot.free == []
  end

  test "adversarial: grupos disputan los ultimos asientos" do
    {venue, spec} = new_venue(%{ultimo: shape(1, 5)})
    assert {:ok, hold_id, _} = Venue.reserve(venue, :ultimo, 2, :contiguous)
    assert {:ok, initial_tickets} = Venue.confirm(venue, hold_id)

    requests = for _ <- 1..40, do: {:ultimo, 2, :contiguous, :buy}
    {_elapsed_us, stats} = run_parallel(venue, requests, 20)
    check_accounting(stats, 40)
    assert stats.bought == 1
    assert stats.rejected == %{sold_out: 39}
    snapshot = check_snapshot(venue, spec, initial_tickets ++ stats.tickets)
    assert length(snapshot.sold) == 4
    assert length(snapshot.free) == 1
  end

  test "adversarial: cancelar inmediatamente devuelve todos los asientos" do
    {venue, spec} = new_venue(%{rotacion: shape(2, 20)})
    requests = for _ <- 1..2_000, do: {:rotacion, 1, :any, :cancel}
    {elapsed_us, stats} = run_parallel(venue, requests)
    print_metrics("Reservar y cancelar sin pausas", elapsed_us, stats)
    check_accounting(stats, 2_000)
    assert stats.cancelled > 0
    snapshot = check_snapshot(venue, spec, [])
    assert length(snapshot.free) == 40
  end

  test "adversarial: todos abandonan reservas y despues de 3 TTL no hay held" do
    ttl_ms = 80
    {venue, spec} = new_venue(%{abandono: shape(2, 20)}, ttl_ms)
    requests = for _ <- 1..300, do: {:abandono, 1, :any, :abandon}
    {_elapsed_us, stats} = run_parallel(venue, requests, 24)
    check_accounting(stats, 300)
    assert stats.held > 0

    # No se utiliza Process.sleep. Solo se verifica despues del plazo de 3 TTL
    # contado a partir de la ultima solicitud completada.
    receive do
    after
      3 * ttl_ms -> :ok
    end

    snapshot = check_snapshot(venue, spec, [])
    assert length(snapshot.free) == 40
    assert Venue.availability(venue, :abandono) == 40
  end

  test "adversarial: se vende el sector hasta el ultimo asiento" do
    {venue, spec} = new_venue(%{agotado: shape(3, 10)})
    requests = for _ <- 1..80, do: {:agotado, 1, :any, :buy}
    {_elapsed_us, stats} = run_parallel(venue, requests, 24)
    check_accounting(stats, 80)
    assert stats.bought == 30
    assert stats.rejected == %{sold_out: 50}
    snapshot = check_snapshot(venue, spec, stats.tickets)
    assert snapshot.free == []
    assert Venue.availability(venue, :agotado) == 0
  end

  test "snapshot durante la carga no muestra asientos en dos estados" do
    {venue, spec} = new_venue(%{simultaneo: shape(3, 20)})
    requests = for _ <- 1..1_000, do: {:simultaneo, 1, :any, :buy}
    parent = self()
    ref = make_ref()

    {pid, monitor} = spawn_monitor(fn ->
      {elapsed_us, stats} = run_parallel(venue, requests, 24)
      send(parent, {ref, :finished, elapsed_us, stats})
    end)

    all =
      for row <- 1..3, seat <- 1..20, into: MapSet.new() do
        VenueSpec.seat_id(:simultaneo, row, seat)
      end

    # Cada snapshot debe ser una particion valida, aun si las ventas avanzan.
    for _ <- 1..20 do
      snapshot = Venue.snapshot(venue)
      sold = MapSet.new(snapshot.sold)
      held = MapSet.new(snapshot.held)
      free = MapSet.new(snapshot.free)

      assert length(snapshot.sold) == MapSet.size(sold)
      assert length(snapshot.held) == MapSet.size(held)
      assert length(snapshot.free) == MapSet.size(free)
      assert MapSet.disjoint?(sold, held)
      assert MapSet.disjoint?(sold, free)
      assert MapSet.disjoint?(held, free)
      assert MapSet.union(sold, MapSet.union(held, free)) == all
      assert snapshot.revenue == length(snapshot.sold) * @price
    end

    receive do
      {^ref, :finished, _elapsed_us, stats} ->
        check_accounting(stats, 1_000)
        assert stats.bought == 60
        assert stats.rejected == %{sold_out: 940}
        check_snapshot(venue, spec, stats.tickets)

      {:DOWN, ^monitor, :process, ^pid, reason} when reason != :normal ->
        flunk("La prueba de snapshots fallo: #{inspect(reason)}")
    after
      @timeout_ms -> flunk("El cliente de snapshots no termino")
    end

    Process.demonitor(monitor, [:flush])
  end

  test "sin bloque contiguo: hay asientos libres, pero no son consecutivos" do
    {venue, spec} = new_venue(%{fragmentado: shape(1, 5)})

    holds =
      for _ <- 1..5 do
        assert {:ok, hold_id, [_seat]} = Venue.reserve(venue, :fragmentado, 1, :any)
        hold_id
      end

    assert :ok == Venue.cancel(venue, Enum.at(holds, 1))
    assert :ok == Venue.cancel(venue, Enum.at(holds, 3))
    assert Venue.availability(venue, :fragmentado) == 2
    assert {:error, :no_contiguous_block} == Venue.reserve(venue, :fragmentado, 2, :contiguous)
    assert {:ok, extra_hold, seats} = Venue.reserve(venue, :fragmentado, 2, :any)
    assert length(seats) == 2
    assert {:ok, extra_tickets} = Venue.confirm(venue, extra_hold)

    original_tickets =
      Enum.flat_map([Enum.at(holds, 0), Enum.at(holds, 2), Enum.at(holds, 4)], fn hold_id ->
        assert {:ok, tickets} = Venue.confirm(venue, hold_id)
        tickets
      end)

    snapshot = check_snapshot(venue, spec, original_tickets ++ extra_tickets)
    assert snapshot.free == []
  end
end
