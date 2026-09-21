defmodule Gate.MnesiaRobustnessTest do
  use ExUnit.Case, async: false

  alias Gate.Sync
  alias Gate.Venue

  @timeout_ms 20_000
  @price 100_000

  defp sector(rows, seats_per_row) do
    %{rows: rows, seats_per_row: seats_per_row, price_cop: @price}
  end

  defp crear_estadio(sectors, ttl_ms \\ 120_000) do
    {:ok, venue} = Venue.start_venue(%{sectors: sectors, ttl_ms: ttl_ms})
    on_exit(fn -> Venue.stop_venue(venue) end)
    venue
  end

  test "si un cliente muere despues de reservar, su hold expira y los asientos se recuperan" do
    ttl_ms = 150
    venue = crear_estadio(%{prueba: sector(1, 2)}, ttl_ms)
    parent = self()
    ref = make_ref()

    {pid, monitor_ref} = spawn_monitor(fn ->
      result = Venue.reserve(venue, :prueba, 2, :contiguous)
      send(parent, {ref, :reserva, result})
      exit(:cliente_simulado_caido)
    end)

    assert_receive {^ref, :reserva, {:ok, hold_id, seats}}, @timeout_ms
    assert length(seats) == 2
    assert_receive {:DOWN, ^monitor_ref, :process, ^pid, :cliente_simulado_caido}, @timeout_ms

    # El plazo se cuenta DESPUES de recibir la respuesta del cliente.
    # No dependemos de que el proceso siga vivo para liberar el hold.
    receive do
    after
      3 * ttl_ms -> :ok
    end

    assert Venue.confirm(venue, hold_id) == {:error, :expired}
    assert Venue.availability(venue, :prueba) == 2

    assert {:ok, nuevo_hold, nuevos_asientos} = Venue.reserve(venue, :prueba, 2, :contiguous)
    assert Enum.sort(nuevos_asientos) == Enum.sort(seats)
    assert nuevo_hold != hold_id
    assert {:ok, tickets} = Venue.confirm(venue, nuevo_hold)
    assert length(tickets) == 2

    snapshot = Venue.snapshot(venue)
    assert Enum.sort(snapshot.sold) == Enum.sort(seats)
    assert snapshot.held == []
    assert snapshot.free == []
    assert snapshot.revenue == 2 * @price
  end

  test "stop termina sin resucitar registros cuando se solapa con una transaccion en curso" do
    venue = crear_estadio(%{a: sector(1, 1), b: sector(1, 1)})
    parent = self()
    ref = make_ref()

    {update_pid, update_monitor} = spawn_monitor(fn ->
      result = Sync.update(venue, :a, fn current_sector, _now ->
        send(parent, {ref, :update_dentro})

        receive do
          {:continuar, ^ref} -> :ok
        after
          @timeout_ms -> raise "No se libero la transaccion en curso"
        end

        {:ok, current_sector}
      end)

      send(parent, {ref, :update_result, result})
    end)

    try do
      assert_receive {^ref, :update_dentro}, @timeout_ms

      {stop_pid, stop_monitor} = spawn_monitor(fn ->
        send(parent, {ref, :stop_iniciado})
        send(parent, {ref, :stop_result, Venue.stop_venue(venue)})
      end)

      assert_receive {^ref, :stop_iniciado}, @timeout_ms
      send(update_pid, {:continuar, ref})

      assert_receive {^ref, :update_result, :ok}, @timeout_ms
      assert_receive {:DOWN, ^update_monitor, :process, ^update_pid, :normal}, @timeout_ms
      assert_receive {^ref, :stop_result, :ok}, @timeout_ms
      assert_receive {:DOWN, ^stop_monitor, :process, ^stop_pid, :normal}, @timeout_ms

      assert Sync.sectors(venue) == []
      assert :mnesia.dirty_read(:gate_sectors, {venue, :a}) == []
      assert :mnesia.dirty_read(:gate_sectors, {venue, :b}) == []
      assert Venue.availability(venue, :a) == {:error, :bad_sector}
      assert Venue.reserve(venue, :a, 1, :any) == {:error, :bad_sector}
    after
      # Evita que el cliente bloqueado quede vivo si una asercion falla antes de liberarlo.
      send(update_pid, {:continuar, ref})
    end
  end

  test "dos cierres concurrentes son idempotentes y no afectan a otro estadio" do
    venue_a = crear_estadio(%{a: sector(1, 2), b: sector(1, 2)})
    venue_b = crear_estadio(%{a: sector(1, 2)})
    parent = self()
    ref = make_ref()

    cierres = for _ <- 1..2 do
      spawn_monitor(fn ->
        receive do
          {:cerrar, ^ref} -> send(parent, {ref, :cierre, Venue.stop_venue(venue_a)})
        end
      end)
    end

    Enum.each(cierres, fn {pid, _monitor} -> send(pid, {:cerrar, ref}) end)

    for _ <- 1..2 do
      assert_receive {^ref, :cierre, :ok}, @timeout_ms
    end

    Enum.each(cierres, fn {pid, monitor} ->
      assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, @timeout_ms
    end)

    assert Sync.sectors(venue_a) == []
    assert Enum.sort(Sync.sectors(venue_b)) == [:a]
    assert {:ok, hold_id, [seat_id]} = Venue.reserve(venue_b, :a, 1, :any)
    assert {:ok, [%{seat_id: ^seat_id}]} = Venue.confirm(venue_b, hold_id)
    assert Venue.availability(venue_b, :a) == 1
  end
end
