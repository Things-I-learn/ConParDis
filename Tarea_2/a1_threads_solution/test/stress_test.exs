defmodule Gate.StressTest do
  use ExUnit.Case

  alias Gate.Venue

  # ============================================================
  # TEST 1
  # Muchos procesos compiten por los mismos asientos.
  #
  # Queremos comprobar:
  # - no hay doble reserva
  # - exactamente 1000 procesos ganan
  # - exactamente 500 reciben :sold_out
  # ============================================================

  test "muchos procesos concurrentes no reservan el mismo asiento dos veces" do
    spec = %{
      sectors: %{
        vip: %{
          rows: 20,
          seats_per_row: 50,
          price_cop: 100_000
        }
      },

      # TTL largo para evitar expiraciones durante el test
      ttl_ms: 60_000
    }

    {:ok, venue} =
      Venue.start_venue(spec)

    on_exit(fn ->
      Venue.stop_venue(venue)
    end)

    parent = self()

    # Tenemos 20 * 50 = 1000 asientos,
    # pero lanzamos 1500 procesos.
    number_of_clients = 1_500

    procesos =
      for _ <- 1..number_of_clients do
        spawn(fn ->
          # Todos esperan la señal :go.
          receive do
            :go ->
              result =
                Venue.reserve(
                  venue,
                  :vip,
                  1,
                  :any
                )

              send(
                parent,
                {:reservation_result, result}
              )
          end
        end)
      end

    # Liberamos todos los procesos.
    Enum.each(procesos, fn pid ->
      send(pid, :go)
    end)

    # Recogemos las 1500 respuestas.
    resultados =
      for _ <- 1..number_of_clients do
        receive do
          {:reservation_result, result} ->
            result
        after
          10_000 ->
            flunk(
              "un proceso no respondió durante el stress test"
            )
        end
      end

    exitos =
      Enum.filter(
        resultados,
        fn result ->
          match?(
            {:ok, _hold_id, _seat_ids},
            result
          )
        end
      )

    sold_out =
      Enum.filter(
        resultados,
        fn result ->
          match?(
            {:error, :sold_out},
            result
          )
        end
      )

    # Exactamente 1000 consiguen asiento.
    assert length(exitos) == 1_000

    # Los otros 500 encuentran el sector lleno.
    assert length(sold_out) == 500

    # Extraemos todos los seat_id reservados.
    seat_ids =
      exitos
      |> Enum.flat_map(fn
        {:ok, _hold_id, seat_ids} ->
          seat_ids
      end)

    assert length(seat_ids) == 1_000

    # Ningún asiento puede aparecer dos veces.
    unique_seat_ids =
      Enum.uniq(seat_ids)

    assert length(unique_seat_ids) == 1_000

    # Estado final.
    snapshot =
      Venue.snapshot(venue)

    assert length(snapshot.held) == 1_000
    assert snapshot.sold == []
    assert snapshot.free == []

    # Invariante: siguen existiendo los 1000 asientos.
    assert length(snapshot.held) +
             length(snapshot.sold) +
             length(snapshot.free) ==
             1_000

    assert Venue.availability(
             venue,
             :vip
           ) == 0
  end

  # ============================================================
  # TEST 2
  # Muchos procesos reservan y luego unos confirman
  # mientras otros cancelan.
  #
  # Queremos comprobar:
  # - 50 vendidos
  # - 50 vuelven a estar libres
  # - 0 quedan held
  # - revenue correcto
  # ============================================================

  test "reservas confirmaciones y cancelaciones concurrentes mantienen un estado consistente" do
    number_of_clients = 100

    spec = %{
      sectors: %{
        vip: %{
          rows: 10,
          seats_per_row: 10,
          price_cop: 100_000
        }
      },

      # Evitamos expiraciones durante el test.
      ttl_ms: 60_000
    }

    {:ok, venue} =
      Venue.start_venue(spec)

    on_exit(fn ->
      Venue.stop_venue(venue)
    end)

    parent = self()

    procesos =
      for client_id <- 1..number_of_clients do
        spawn(fn ->
          receive do
            :go ->
              reserve_result =
                Venue.reserve(
                  venue,
                  :vip,
                  1,
                  :any
                )

              final_result =
                case reserve_result do
                  {:ok, hold_id, seat_ids} ->
                    # Pares confirman.
                    # Impares cancelan.
                    if rem(client_id, 2) == 0 do
                      {
                        :confirmed,
                        seat_ids,
                        Venue.confirm(
                          venue,
                          hold_id
                        )
                      }
                    else
                      {
                        :cancelled,
                        seat_ids,
                        Venue.cancel(
                          venue,
                          hold_id
                        )
                      }
                    end

                  error ->
                    {
                      :reservation_error,
                      error
                    }
                end

              send(
                parent,
                {
                  :client_result,
                  client_id,
                  final_result
                }
              )
          end
        end)
      end

    # Lanzamos los 100 clientes.
    Enum.each(procesos, fn pid ->
      send(pid, :go)
    end)

    # Recogemos todas las respuestas.
    resultados =
      for _ <- 1..number_of_clients do
        receive do
          {:client_result, client_id, result} ->
            {client_id, result}
        after
          5_000 ->
            flunk(
              "un proceso no respondió durante la prueba concurrente"
            )
        end
      end

    # Ninguna reserva debería fallar:
    # hay exactamente 100 asientos.
    errores_reserva =
      Enum.filter(
        resultados,
        fn
          {_id, {:reservation_error, _reason}} ->
            true

          _ ->
            false
        end
      )

    assert errores_reserva == []

    # 50 clientes pares confirmaron.
    confirmados =
      Enum.filter(
        resultados,
        fn
          {_id, {:confirmed, _seat_ids, {:ok, _tickets}}} ->
            true

          _ ->
            false
        end
      )

    assert length(confirmados) == 50

    # 50 clientes impares cancelaron.
    cancelados =
      Enum.filter(
        resultados,
        fn
          {_id, {:cancelled, _seat_ids, :ok}} ->
            true

          _ ->
            false
        end
      )

    assert length(cancelados) == 50

    # Estado final.
    snapshot =
      Venue.snapshot(venue)

    assert length(snapshot.sold) == 50
    assert length(snapshot.held) == 0
    assert length(snapshot.free) == 50

    # 50 ventas * 100.000
    assert snapshot.revenue == 5_000_000

    # Invariante:
    # free + held + sold = total de asientos.
    assert length(snapshot.sold) +
             length(snapshot.held) +
             length(snapshot.free) ==
             100

    assert Venue.availability(
             venue,
             :vip
           ) == 50

    # Un asiento vendido no puede aparecer también como libre.
    sold_set =
      MapSet.new(snapshot.sold)

    free_set =
      MapSet.new(snapshot.free)

    assert MapSet.disjoint?(
             sold_set,
             free_set
           )
  end
  test "muchos holds abandonados expiran y liberan todos los asientos" do
  # Trabajamos directamente con Sector para controlar el tiempo
  # de forma determinista y no depender del reloj real.

  sector =
    Gate.Sector.new(
      :vip,
      %{
        rows: 20,
        seats_per_row: 50,
        price_cop: 100_000
      },
      1_000
    )

  # 20 * 50 = 1000 asientos.
  #
  # Creamos 1000 holds en el mismo instante lógico.
  sector =
    Enum.reduce(
      1..1_000,
      sector,
      fn _, current_sector ->
        {:ok, new_sector, _hold_id, [_seat_id]} =
          Gate.Sector.reserve(
            current_sector,
            1,
            :any,
            1_000
          )

        new_sector
      end
    )

  # Todos están held.
  assert sector.free == 0

  {sector, snapshot_before} =
    Gate.Sector.snapshot(
      sector,
      1_500
    )

  assert length(snapshot_before.held) == 1_000
  assert snapshot_before.free == []
  assert snapshot_before.sold == []

  # TTL = 1000
  #
  # Los holds vencían en 2000.
  # Consultamos mucho después, en 5000.
  #
  # Aquí la expiración debe hacer todo el trabajo.
  {sector, snapshot_after} =
    Gate.Sector.snapshot(
      sector,
      5_000
    )

  assert snapshot_after.held == []
  assert snapshot_after.sold == []
  assert length(snapshot_after.free) == 1_000

  assert sector.free == 1_000

  # Verificamos que todos los holds quedaron expirados.
  assert Enum.all?(
           sector.holds,
           fn {_hold_id, hold} ->
             hold.state == :expired
           end
         )

  # Y la cola de expiraciones debe quedar vacía.
  assert :queue.is_empty(
           sector.expiry_queue
         )
end
test "grupos concurrentes peleando por los ultimos asientos respetan todo o nada" do
  spec = %{
    sectors: %{
      vip: %{
        rows: 1,
        seats_per_row: 5,
        price_cop: 100_000
      }
    },
    ttl_ms: 60_000
  }

  {:ok, venue} =
    Venue.start_venue(spec)

  on_exit(fn ->
    Venue.stop_venue(venue)
  end)

  parent = self()

  # Tres clientes piden grupos de 3.
  #
  # Solo uno puede ganar:
  #
  # 5 asientos totales
  # primer grupo toma 3
  # quedan 2
  #
  # los demás deben recibir :sold_out,
  # no una reserva parcial de 2.
  procesos =
    for client_id <- 1..3 do
      spawn(fn ->
        receive do
          :go ->
            result =
              Venue.reserve(
                venue,
                :vip,
                3,
                :any
              )

            send(
              parent,
              {:group_result, client_id, result}
            )
        end
      end)
    end

  Enum.each(procesos, fn pid ->
    send(pid, :go)
  end)

  resultados =
    for _ <- 1..3 do
      receive do
        {:group_result, client_id, result} ->
          {client_id, result}
      after
        2_000 ->
          flunk("un grupo no respondió")
      end
    end

  exitos =
    Enum.filter(
      resultados,
      fn
        {_id, {:ok, _hold_id, seat_ids}} ->
          length(seat_ids) == 3

        _ ->
          false
      end
    )

  errores =
    Enum.filter(
      resultados,
      fn
        {_id, {:error, :sold_out}} ->
          true

        _ ->
          false
      end
    )

  # Exactamente un grupo obtiene 3 asientos.
  assert length(exitos) == 1

  # Los otros dos fallan limpiamente.
  assert length(errores) == 2

  snapshot =
    Venue.snapshot(venue)

  # Hay 3 held y 2 libres.
  assert length(snapshot.held) == 3
  assert length(snapshot.free) == 2
  assert snapshot.sold == []

  # Invariante total.
  assert length(snapshot.held) +
           length(snapshot.free) +
           length(snapshot.sold) ==
           5
end

test "snapshot contiene conjuntos disjuntos y todos los asientos" do
  spec = %{
    sectors: %{
      vip: %{
        rows: 2,
        seats_per_row: 3,
        price_cop: 100_000
      }
    },
    ttl_ms: 60_000
  }

  {:ok, venue} =
    Venue.start_venue(spec)

  on_exit(fn ->
    Venue.stop_venue(venue)
  end)

  # Vendemos 2.
  {:ok, hold1, _} =
    Venue.reserve(
      venue,
      :vip,
      2,
      :contiguous
    )

  assert {:ok, _tickets} =
           Venue.confirm(
             venue,
             hold1
           )

  # Dejamos 1 en held.
  {:ok, _hold2, _} =
    Venue.reserve(
      venue,
      :vip,
      1,
      :any
    )

  snapshot =
    Venue.snapshot(venue)

  sold =
    MapSet.new(snapshot.sold)

  held =
    MapSet.new(snapshot.held)

  free =
    MapSet.new(snapshot.free)

  # ------------------------------------------------------------
  # Ningún asiento puede pertenecer a dos estados.
  # ------------------------------------------------------------

  assert MapSet.disjoint?(sold, held)
  assert MapSet.disjoint?(sold, free)
  assert MapSet.disjoint?(held, free)

  # ------------------------------------------------------------
  # Construimos los 6 seat_id que deberían existir.
  # ------------------------------------------------------------

  expected =
    for row <- 1..2,
        seat <- 1..3,
        into: MapSet.new() do
      Gate.VenueSpec.seat_id(
        :vip,
        row,
        seat
      )
    end

  actual =
    sold
    |> MapSet.union(held)
    |> MapSet.union(free)

  # Deben aparecer exactamente todos los asientos.
  assert actual == expected

  assert MapSet.size(actual) == 6

  # Estado esperado:
  # 2 vendidos
  # 1 held
  # 3 libres
  assert MapSet.size(sold) == 2
  assert MapSet.size(held) == 1
  assert MapSet.size(free) == 3

  assert snapshot.revenue == 200_000
end
end
