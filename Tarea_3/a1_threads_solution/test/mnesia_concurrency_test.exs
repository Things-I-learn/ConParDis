defmodule Gate.MnesiaConcurrencyTest do
  use ExUnit.Case, async: false

  alias Gate.Sync
  alias Gate.Venue

  @client_timeout_ms 30_000

  defp sector(rows, seats_per_row) do
    %{rows: rows, seats_per_row: seats_per_row, price_cop: 100_000}
  end

  defp crear_estadio(sectors) do
    {:ok, venue} = Venue.start_venue(%{sectors: sectors, ttl_ms: 120_000})
    on_exit(fn -> Venue.stop_venue(venue) end)
    venue
  end

  defp comprar(venue, sector_name) do
    case Venue.reserve(venue, sector_name, 1, :any) do
      {:ok, hold_id, _seat_ids} -> Venue.confirm(venue, hold_id)
      error -> error
    end
  end

  # Lanza clientes a la vez; detecta caidas y usa un plazo total, no uno por cliente.
  defp ejecutar_clientes(operaciones) do
    parent = self()
    ref = make_ref()

    clientes = Enum.map(operaciones, fn operacion ->
      spawn_monitor(fn ->
        receive do
          {:iniciar, ^ref} -> send(parent, {ref, self(), operacion.()})
        end
      end)
    end)

    Enum.each(clientes, fn {pid, _monitor_ref} -> send(pid, {:iniciar, ref}) end)
    limite = System.monotonic_time(:millisecond) + @client_timeout_ms

    resultados = for _ <- clientes do
      restante = max(limite - System.monotonic_time(:millisecond), 0)

      receive do
        {^ref, _pid, resultado} -> resultado
        {:DOWN, _monitor_ref, :process, pid, reason} when reason != :normal ->
          flunk("El cliente #{inspect(pid)} termino inesperadamente: #{inspect(reason)}")
      after
        restante -> flunk("No respondieron todos los clientes en #{@client_timeout_ms} ms")
      end
    end

    Enum.each(clientes, fn {_pid, monitor_ref} -> Process.demonitor(monitor_ref, [:flush]) end)
    resultados
  end

  defp comprobar_ventas(resultados, venue, total_asientos) do
    compras = for {:ok, tickets} <- resultados, ticket <- tickets, do: ticket
    rechazos = Enum.count(resultados, &(&1 == {:error, :sold_out}))
    ids = Enum.map(compras, & &1.seat_id)
    snapshot = Venue.snapshot(venue)

    assert length(compras) == total_asientos
    assert rechazos == length(resultados) - total_asientos
    assert length(compras) + rechazos == length(resultados)
    assert length(ids) == length(Enum.uniq(ids))
    assert Enum.sort(snapshot.sold) == Enum.sort(ids)
    assert snapshot.held == []
    assert snapshot.free == []
    assert snapshot.revenue == total_asientos * 100_000
  end

  test "contencion: 120 clientes compiten por los 60 asientos de un sector" do
    venue = crear_estadio(%{prueba: sector(3, 20)})
    operaciones = for _ <- 1..120, do: fn -> comprar(venue, :prueba) end

    {microsegundos, resultados} = :timer.tc(fn -> ejecutar_clientes(operaciones) end)
    IO.puts("\nMismo sector: #{Float.round(microsegundos / 1_000, 1)} ms para 120 compras intentadas")

    comprobar_ventas(resultados, venue, 60)
    assert Venue.availability(venue, :prueba) == 0
  end

  test "sectores distintos: 120 clientes compiten por 60 asientos distribuidos" do
    venue = crear_estadio(%{norte: sector(1, 20), sur: sector(1, 20), vip: sector(1, 20)})

    operaciones = Enum.flat_map([:norte, :sur, :vip], fn sector_name ->
      for _ <- 1..40, do: fn -> comprar(venue, sector_name) end
    end)

    {microsegundos, resultados} = :timer.tc(fn -> ejecutar_clientes(operaciones) end)
    IO.puts("\nTres sectores: #{Float.round(microsegundos / 1_000, 1)} ms para 120 compras intentadas")

    comprobar_ventas(resultados, venue, 60)

    for sector_name <- [:norte, :sur, :vip] do
      assert Venue.availability(venue, sector_name) == 0
    end
  end

  test "un sector puede avanzar mientras otro conserva un bloqueo de escritura" do
    venue = crear_estadio(%{a: sector(1, 1), b: sector(1, 1)})
    parent = self()
    ref = make_ref()

    {pid_a, monitor_a} = spawn_monitor(fn ->
      resultado = Sync.update(venue, :a, fn current_sector, _now ->
        send(parent, {ref, :a_dentro})

        receive do
          {:liberar, ^ref} -> :ok
        after
          20_000 -> raise "No se libero el sector a durante la prueba"
        end

        {:a_termino, current_sector}
      end)

      send(parent, {ref, :a_resultado, resultado})
    end)

    assert_receive {^ref, :a_dentro}, 5_000

    {_pid_b, monitor_b} = spawn_monitor(fn ->
      send(parent, {ref, :b_resultado, Venue.reserve(venue, :b, 1, :any)})
    end)

    try do
      # B debe completar su reserva ANTES de que liberemos el bloqueo de A.
      assert_receive {^ref, :b_resultado, {:ok, _, ["b:R001:S001"]}}, 10_000
    after
      send(pid_a, {:liberar, ref})
    end

    assert_receive {^ref, :a_resultado, :a_termino}, 5_000
    assert Venue.availability(venue, :a) == 1
    assert Venue.availability(venue, :b) == 0

    Process.demonitor(monitor_a, [:flush])
    Process.demonitor(monitor_b, [:flush])
  end

  test "si una transaccion falla, otro cliente puede comprar en el mismo sector" do
    venue = crear_estadio(%{prueba: sector(1, 1)})
    parent = self()
    ref = make_ref()

    {pid_a, monitor_a} = spawn_monitor(fn ->
      Sync.update(venue, :prueba, fn _current_sector, _now ->
        send(parent, {ref, :a_dentro})

        receive do
          {:abortar, ^ref} -> :mnesia.abort(:fallo_simulado)
        after
          20_000 -> raise "No se libero la transaccion fallida"
        end
      end)
    end)

    assert_receive {^ref, :a_dentro}, 5_000

    {_pid_b, monitor_b} = spawn_monitor(fn ->
      send(parent, {ref, :b_listo})
      send(parent, {ref, :b_resultado, comprar(venue, :prueba)})
    end)

    try do
      assert_receive {^ref, :b_listo}, 5_000
    after
      send(pid_a, {:abortar, ref})
    end

    # Sync.update/3 convierte el aborto en RuntimeError: la caida es intencional.
    assert_receive {:DOWN, ^monitor_a, :process, ^pid_a, {%RuntimeError{}, _stacktrace}}, 10_000
    assert_receive {^ref, :b_resultado, {:ok, [%{seat_id: "prueba:R001:S001"}]}}, 10_000

    snapshot = Venue.snapshot(venue)
    assert snapshot.sold == ["prueba:R001:S001"]
    assert snapshot.held == []
    assert snapshot.free == []
    assert snapshot.revenue == 100_000

    Process.demonitor(monitor_b, [:flush])
  end
end
