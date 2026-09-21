defmodule Gate.MnesiaTest do
  use ExUnit.Case, async: false

  alias Gate.Venue
  alias Gate.Sync

  defp crear_estadio(sectors, ttl_ms \\ 120_000) do
    spec = %{sectors: sectors, ttl_ms: ttl_ms}
    {:ok, venue} = Venue.start_venue(spec)
    on_exit(fn -> Venue.stop_venue(venue) end)
    venue
  end

  defp sector(rows, seats_per_row, price_cop \\ 100_000) do
    %{rows: rows, seats_per_row: seats_per_row, price_cop: price_cop}
  end

  # Los procesos esperan la misma señal antes de comenzar.
  # La referencia identifica los mensajes de esta ejecución.
  defp clientes_concurrentes(n, operacion) do
    parent = self()
    ref = make_ref()

    clients = for _ <- 1..n do
      spawn(fn ->
        receive do
          {:go, ^ref} -> send(parent, {ref, operacion.()})
        end
      end)
    end

    Enum.each(clients, fn pid -> send(pid, {:go, ref}) end)

    for _ <- 1..n do
      receive do
        {^ref, resultado} -> resultado
      after
        20_000 -> flunk("Un cliente no respondió en 20 segundos")
      end
    end
  end

  test "reserva, confirma y mantiene el estado del sector" do
    venue = crear_estadio(%{prueba: sector(1, 2)})

    assert Sync.sectors(venue) == [:prueba]
    assert Venue.availability(venue, :prueba) == 2
    assert Venue.reserve(venue, :inexistente, 1, :any) == {:error, :bad_sector}

    assert {:ok, hold_id, [seat_id]} = Venue.reserve(venue, :prueba, 1, :any)
    assert {:ok, [%{seat_id: ^seat_id, hold_id: ^hold_id}]} = Venue.confirm(venue, hold_id)
    assert Venue.confirm(venue, hold_id) == {:error, :already_confirmed}
    assert Venue.availability(venue, :prueba) == 1

    snapshot = Venue.snapshot(venue)
    assert snapshot.sold == [seat_id]
    assert snapshot.held == []
    assert length(snapshot.free) == 1
    assert snapshot.revenue == 100_000
  end

  test "dos clientes compiten por los mismos dos asientos" do
    venue = crear_estadio(%{prueba: sector(1, 2)})

    resultados = clientes_concurrentes(2, fn ->
      Venue.reserve(venue, :prueba, 2, :contiguous)
    end)

    exitos = Enum.filter(resultados, fn resultado -> match?({:ok, _, _}, resultado) end)
    assert length(exitos) == 1
    assert Enum.count(resultados, &(&1 == {:error, :sold_out})) == 1

    assert [{:ok, _hold_id, asientos}] = exitos
    assert length(asientos) == 2
    assert length(Enum.uniq(asientos)) == 2

    snapshot = Venue.snapshot(venue)
    assert Enum.sort(snapshot.held) == Enum.sort(asientos)
    assert snapshot.sold == []
    assert snapshot.free == []
  end

  test "50 clientes compran como máximo los 30 asientos disponibles" do
    venue = crear_estadio(%{prueba: sector(3, 10)})

    resultados = clientes_concurrentes(50, fn ->
      case Venue.reserve(venue, :prueba, 1, :any) do
        {:ok, hold_id, _asientos} -> Venue.confirm(venue, hold_id)
        error -> error
      end
    end)

    compras = for {:ok, tickets} <- resultados, do: tickets
    rechazos = Enum.count(resultados, &(&1 == {:error, :sold_out}))
    assert length(compras) == 30
    assert rechazos == 20
    assert length(compras) + rechazos == length(resultados)

    asientos_vendidos = for tickets <- compras, ticket <- tickets, do: ticket.seat_id
    assert length(asientos_vendidos) == 30
    assert length(Enum.uniq(asientos_vendidos)) == 30

    snapshot = Venue.snapshot(venue)
    assert Enum.sort(snapshot.sold) == Enum.sort(asientos_vendidos)
    assert snapshot.held == []
    assert snapshot.free == []
    assert snapshot.revenue == 3_000_000
  end

  test "sectores distintos conservan estados independientes" do
    venue = crear_estadio(%{vip: sector(1, 1), general: sector(1, 1)})

    parent = self()
    ref = make_ref()

    clients = Enum.map([:vip, :general], fn sector_name ->
      spawn(fn ->
        receive do
          {:go, ^ref} ->
            resultado = Venue.reserve(venue, sector_name, 1, :any)
            send(parent, {ref, sector_name, resultado})
        end
      end)
    end)

    Enum.each(clients, fn pid -> send(pid, {:go, ref}) end)

    assert_receive {^ref, :vip, {:ok, _, [vip_seat]}}, 20_000
    assert_receive {^ref, :general, {:ok, _, [general_seat]}}, 20_000
    refute vip_seat == general_seat
    assert Venue.availability(venue, :vip) == 0
    assert Venue.availability(venue, :general) == 0
  end

  test "detener un estadio no elimina otro y stop es idempotente" do
    venue_a = crear_estadio(%{prueba: sector(1, 1)})
    venue_b = crear_estadio(%{prueba: sector(1, 1)})

    assert {:ok, hold_id, _} = Venue.reserve(venue_a, :prueba, 1, :any)
    assert {:ok, [_ticket]} = Venue.confirm(venue_a, hold_id)
    assert Venue.availability(venue_b, :prueba) == 1

    assert Venue.stop_venue(venue_a) == :ok
    assert Sync.sectors(venue_a) == []
    assert Venue.stop_venue(venue_a) == :ok
    assert Venue.availability(venue_b, :prueba) == 1
  end

  test "un cliente puede continuar despues del fallo de otro" do
    spec = %{
      sectors: %{
        prueba: %{
          rows: 1,
          seats_per_row: 2,
          price_cop: 100_000
        }
      },
      ttl_ms: 60_000
    }

    {:ok, venue} = Gate.Venue.start_venue(spec)

    parent = self()

    {pid, monitor_ref} =
      spawn_monitor(fn ->
        Gate.Sync.update(venue, :prueba, fn sector, now ->
          {:ok, modified_sector, _hold_id, _seats} =
            Gate.Sector.reserve(sector, 2, :contiguous, now)

          send(parent, :transition_started)

          raise "boom"

          {:ok, modified_sector}
        end)
      end)

    assert_receive :transition_started, 5_000

    assert_receive {:DOWN, ^monitor_ref, :process, ^pid, reason}, 5_000

    assert {%RuntimeError{}, _stacktrace} = reason

    assert Gate.Venue.availability(venue, :prueba) == 2

    assert {:ok, hold_id, seats} =
      Gate.Venue.reserve(venue, :prueba, 2, :contiguous)

    assert length(seats) == 2

    assert {:ok, tickets} = Gate.Venue.confirm(venue, hold_id)

    assert length(tickets) == 2

    snapshot = Gate.Venue.snapshot(venue)

    assert length(snapshot.sold) == 2
    assert snapshot.free == []
    assert snapshot.held == []
  end
end
