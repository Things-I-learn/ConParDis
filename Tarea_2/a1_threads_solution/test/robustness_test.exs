defmodule Gate.RobustnessTest do
  use ExUnit.Case

  alias Gate.Venue

  setup do
    spec = %{
      sectors: %{
        vip: %{
          rows: 1,
          seats_per_row: 6,
          price_cop: 100_000
        },
        sur: %{
          rows: 1,
          seats_per_row: 4,
          price_cop: 80_000
        }
      },
      ttl_ms: 30
    }

    {:ok, venue} =
      Venue.start_venue(spec)

    on_exit(fn ->
      Venue.stop_venue(venue)
    end)

    %{venue: venue}
  end

  # ============================================================
  # 1. stop_venue debe poder llamarse más de una vez
  # ============================================================

  test "stop_venue es idempotente", %{venue: venue} do
    assert :ok =
             Venue.stop_venue(venue)

    assert :ok =
             Venue.stop_venue(venue)
  end

  # ============================================================
  # 2. Hold con sector que no existe
  # ============================================================

  test "confirm traduce un sector inexistente a unknown_hold",
       %{venue: venue} do
    fake_hold =
      {:sector_inventado, 123}

    assert {:error, :unknown_hold} =
             Venue.confirm(
               venue,
               fake_hold
             )
  end

  # ============================================================
  # 3. Formas inválidas de hold_id
  # ============================================================

  test "holds con forma invalida son rechazados",
       %{venue: venue} do
    assert {:error, :unknown_hold} =
             Venue.confirm(
               venue,
               "hola"
             )

    assert {:error, :unknown_hold} =
             Venue.confirm(
               venue,
               123
             )

    assert {:error, :unknown_hold} =
             Venue.confirm(
               venue,
               {:vip, :no_es_entero}
             )

    assert {:error, :unknown_hold} =
             Venue.cancel(
               venue,
               nil
             )
  end

  # ============================================================
  # 4. No se puede cancelar una compra confirmada
  # ============================================================

  test "un hold confirmado no puede cancelarse",
       %{venue: venue} do
    {:ok, hold_id, _seat_ids} =
      Venue.reserve(
        venue,
        :vip,
        2,
        :any
      )

    assert {:ok, _tickets} =
             Venue.confirm(
               venue,
               hold_id
             )

    assert {:error, :already_confirmed} =
             Venue.cancel(
               venue,
               hold_id
             )

    # Siguen vendidos, no regresan a free.
    assert Venue.availability(
             venue,
             :vip
           ) == 4
  end

  # ============================================================
  # 5. Un hold expirado libera sus asientos
  # ============================================================

  test "un hold expirado no puede confirmarse y libera asientos",
       %{venue: venue} do
    {:ok, hold_id, _seat_ids} =
      Venue.reserve(
        venue,
        :vip,
        2,
        :any
      )

    assert Venue.availability(
             venue,
             :vip
           ) == 4

    # Esperamos un poco más que el TTL de 30 ms.
    #
    # Esto está en los tests; no estamos usando Process.sleep
    # dentro de la implementación.
    receive do
    after
      50 ->
        :ok
    end

    assert {:error, :expired} =
             Venue.confirm(
               venue,
               hold_id
             )

    assert Venue.availability(
             venue,
             :vip
           ) == 6
  end

  # ============================================================
  # 6. Los hold_id nunca deben reutilizarse
  # ============================================================

  test "los hold_id no se reutilizan después de cancelar",
       %{venue: venue} do
    {:ok, hold1, _} =
      Venue.reserve(
        venue,
        :vip,
        1,
        :any
      )

    assert :ok =
             Venue.cancel(
               venue,
               hold1
             )

    {:ok, hold2, _} =
      Venue.reserve(
        venue,
        :vip,
        1,
        :any
      )

    refute hold1 == hold2
  end

  # ============================================================
  # 7. Snapshot global con dos sectores
  # ============================================================

  test "snapshot combina correctamente varios sectores",
       %{venue: venue} do
    # VIP: vendemos 2
    {:ok, vip_hold, _} =
      Venue.reserve(
        venue,
        :vip,
        2,
        :any
      )

    {:ok, _tickets} =
      Venue.confirm(
        venue,
        vip_hold
      )

    # SUR: dejamos 1 held
    {:ok, _sur_hold, _} =
      Venue.reserve(
        venue,
        :sur,
        1,
        :any
      )

    snapshot =
      Venue.snapshot(venue)

    assert length(snapshot.sold) == 2
    assert length(snapshot.held) == 1
    assert length(snapshot.free) == 7

    assert snapshot.revenue ==
             200_000

    assert length(snapshot.sold) +
             length(snapshot.held) +
             length(snapshot.free) ==
             10
  end
  test "expiry_queue distingue holds confirmados cancelados y expirados" do
  sector =
    Gate.Sector.new(
      :vip,
      %{
        rows: 1,
        seats_per_row: 5,
        price_cop: 100_000
      },
      500
    )

  # Hold 1:
  # se crea y posteriormente se confirma.
  {:ok, sector, hold1, _} =
    Gate.Sector.reserve(
      sector,
      1,
      :any,
      1_000
    )

  # Hold 2:
  # se crea y posteriormente se cancela.
  {:ok, sector, hold2, _} =
    Gate.Sector.reserve(
      sector,
      1,
      :any,
      1_100
    )

  # Hold 3:
  # se crea y lo dejamos expirar.
  {:ok, sector, hold3, _} =
    Gate.Sector.reserve(
      sector,
      1,
      :any,
      1_200
    )

  # En este momento hay:
  #
  # free = 2
  # held = 3

  {:ok, sector, _tickets} =
    Gate.Sector.confirm(
      sector,
      hold1,
      1_300
    )

  # Confirmar:
  # held -> sold
  #
  # free sigue siendo 2.

  {:ok, sector} =
    Gate.Sector.cancel(
      sector,
      hold2,
      1_300
    )

  # Cancelar:
  # held -> free
  #
  # free pasa a 3.

  # En 2000 todos los expires_at ya pasaron.
  #
  # La cola contiene entradas para los tres holds,
  # pero:
  #
  # hold1 está :confirmed  -> NO debe liberarse
  # hold2 está :cancelled  -> NO debe liberarse otra vez
  # hold3 está :held       -> debe expirar y liberarse

  {sector, snapshot} =
    Gate.Sector.snapshot(
      sector,
      2_000
    )

  assert sector.holds[hold1].state == :confirmed
  assert sector.holds[hold2].state == :cancelled
  assert sector.holds[hold3].state == :expired

  assert length(snapshot.sold) == 1
  assert length(snapshot.held) == 0
  assert length(snapshot.free) == 4

  assert snapshot.revenue == 100_000

  assert sector.free == 4
end
end
