defmodule Gate.SectorTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------
  # Helper: sector pequeño para las pruebas
  # ---------------------------------------------------------

  defp new_sector(rows \\ 2, seats_per_row \\ 5, ttl_ms \\ 5_000) do
    Gate.Sector.new(
      :prueba,
      %{
        rows: rows,
        seats_per_row: seats_per_row,
        price_cop: 100_000
      },
      ttl_ms
    )
  end

  # ---------------------------------------------------------
  # new/3
  # ---------------------------------------------------------

  test "new crea todos los asientos libres" do
    sector = new_sector()

    assert sector.free == 10
    assert sector.next_hold_id == 1
    assert sector.holds == %{}

    assert Gate.Row.free_count(sector.rows[1]) == 5
    assert Gate.Row.free_count(sector.rows[2]) == 5
  end

  # ---------------------------------------------------------
  # reserve/4 :contiguous
  # ---------------------------------------------------------

  test "reserve contiguous reserva asientos consecutivos" do
    sector = new_sector()

    assert {:ok, sector2, {:prueba, 1}, seat_ids} =
             Gate.Sector.reserve(
               sector,
               3,
               :contiguous,
               1_000
             )

    assert seat_ids == [
             "prueba:R001:S001",
             "prueba:R001:S002",
             "prueba:R001:S003"
           ]

    assert sector2.free == 7
    assert sector2.next_hold_id == 2

    assert sector2.rows[1].status[1] == :held
    assert sector2.rows[1].status[2] == :held
    assert sector2.rows[1].status[3] == :held
  end

  # ---------------------------------------------------------
  # reserve/4 :any
  # ---------------------------------------------------------

  test "reserve any puede usar varias filas" do
    sector = new_sector(2, 3)

    assert {:ok, sector2, {:prueba, 1}, seat_ids} =
             Gate.Sector.reserve(
               sector,
               4,
               :any,
               1_000
             )

    assert seat_ids == [
             "prueba:R001:S001",
             "prueba:R001:S002",
             "prueba:R001:S003",
             "prueba:R002:S001"
           ]

    assert sector2.free == 2
  end

  # ---------------------------------------------------------
  # sold_out
  # ---------------------------------------------------------

  test "reserve devuelve sold_out cuando no hay suficientes libres" do
    sector = new_sector(1, 3)

    {:ok, sector2, _hold_id, _seats} =
      Gate.Sector.reserve(
        sector,
        3,
        :contiguous,
        1_000
      )

    assert {:error, :sold_out} =
             Gate.Sector.reserve(
               sector2,
               1,
               :contiguous,
               2_000
             )
  end

  # ---------------------------------------------------------
  # no_contiguous_block
  # ---------------------------------------------------------

  test "reserve contiguous devuelve no_contiguous_block si hay libres pero separados" do
    sector = new_sector(1, 5)

    fragmented_row = %Gate.Row{
      size: 5,
      status: %{
        1 => :free,
        2 => :sold,
        3 => :free,
        4 => :sold,
        5 => :free
      },
      free: 3
    }

    sector = %{
      sector
      | rows: %{1 => fragmented_row},
        free: 3
    }

    assert {:error, :no_contiguous_block} =
             Gate.Sector.reserve(
               sector,
               2,
               :contiguous,
               1_000
             )
  end

  # ---------------------------------------------------------
  # confirm/3
  # ---------------------------------------------------------

  test "confirm convierte held en sold y crea tickets" do
    sector = new_sector(1, 5)

    {:ok, sector2, hold_id, _seat_ids} =
      Gate.Sector.reserve(
        sector,
        3,
        :contiguous,
        1_000
      )

    assert {:ok, sector3, tickets} =
             Gate.Sector.confirm(
               sector2,
               hold_id,
               2_000
             )

    assert length(tickets) == 3

    assert Enum.all?(tickets, fn ticket ->
             ticket.hold_id == hold_id and
               ticket.price_cop == 100_000 and
               ticket.sector == :prueba
           end)

    assert sector3.rows[1].status[1] == :sold
    assert sector3.rows[1].status[2] == :sold
    assert sector3.rows[1].status[3] == :sold

    # Confirmar no cambia free:
    # los asientos ya estaban ocupados como :held.
    assert sector3.free == 2
  end

  test "confirmar dos veces devuelve already_confirmed" do
    sector = new_sector(1, 5)

    {:ok, sector2, hold_id, _} =
      Gate.Sector.reserve(
        sector,
        2,
        :contiguous,
        1_000
      )

    {:ok, sector3, _tickets} =
      Gate.Sector.confirm(
        sector2,
        hold_id,
        2_000
      )

    assert {:error, :already_confirmed} =
             Gate.Sector.confirm(
               sector3,
               hold_id,
               3_000
             )
  end

  # ---------------------------------------------------------
  # Expiración
  # ---------------------------------------------------------

  test "confirm de un hold vencido devuelve expired" do
    sector = new_sector(1, 5, 5_000)

    {:ok, sector2, hold_id, _} =
      Gate.Sector.reserve(
        sector,
        3,
        :contiguous,
        1_000
      )

    # Expira en:
    # 1_000 + 5_000 = 6_000

    assert {:error, :expired} =
             Gate.Sector.confirm(
               sector2,
               hold_id,
               7_000
             )
  end

  # ---------------------------------------------------------
  # cancel/3
  # ---------------------------------------------------------

  test "cancel libera los asientos" do
    sector = new_sector(1, 5)

    {:ok, sector2, hold_id, _} =
      Gate.Sector.reserve(
        sector,
        3,
        :contiguous,
        1_000
      )

    assert sector2.free == 2

    assert {:ok, sector3} =
             Gate.Sector.cancel(
               sector2,
               hold_id,
               2_000
             )

    assert sector3.free == 5

    assert Enum.all?(1..5, fn seat_no ->
             sector3.rows[1].status[seat_no] == :free
           end)

    assert sector3.holds[hold_id].state == :cancelled
  end

  test "cancelar dos veces sigue devolviendo ok" do
    sector = new_sector(1, 5)

    {:ok, sector2, hold_id, _} =
      Gate.Sector.reserve(
        sector,
        2,
        :contiguous,
        1_000
      )

    {:ok, sector3} =
      Gate.Sector.cancel(
        sector2,
        hold_id,
        2_000
      )

    assert {:ok, sector4} =
             Gate.Sector.cancel(
               sector3,
               hold_id,
               3_000
             )

    assert sector4.free == 5
  end

  test "cancelar un hold confirmado devuelve already_confirmed" do
    sector = new_sector(1, 5)

    {:ok, sector2, hold_id, _} =
      Gate.Sector.reserve(
        sector,
        2,
        :contiguous,
        1_000
      )

    {:ok, sector3, _tickets} =
      Gate.Sector.confirm(
        sector2,
        hold_id,
        2_000
      )

    assert {:error, :already_confirmed} =
             Gate.Sector.cancel(
               sector3,
               hold_id,
               3_000
             )
  end

  # ---------------------------------------------------------
  # hold_id
  # ---------------------------------------------------------

  test "los hold_id no se reutilizan" do
    sector = new_sector(1, 5)

    {:ok, sector2, hold1, _} =
      Gate.Sector.reserve(
        sector,
        2,
        :contiguous,
        1_000
      )

    {:ok, sector3} =
      Gate.Sector.cancel(
        sector2,
        hold1,
        2_000
      )

    {:ok, _sector4, hold2, _} =
      Gate.Sector.reserve(
        sector3,
        2,
        :contiguous,
        3_000
      )

    assert hold1 == {:prueba, 1}
    assert hold2 == {:prueba, 2}
    assert hold1 != hold2
  end

  # ---------------------------------------------------------
  # availability/2
  # ---------------------------------------------------------

  test "availability libera holds expirados" do
    sector = new_sector(1, 5, 5_000)

    {:ok, sector2, hold_id, _} =
      Gate.Sector.reserve(
        sector,
        3,
        :contiguous,
        1_000
      )

    assert sector2.free == 2

    {sector3, available} =
      Gate.Sector.availability(
        sector2,
        7_000
      )

    assert available == 5
    assert sector3.free == 5
    assert sector3.holds[hold_id].state == :expired
  end

  # ---------------------------------------------------------
  # snapshot/2
  # ---------------------------------------------------------

  test "snapshot separa free held sold y calcula revenue" do
    sector = new_sector(1, 5)

    {:ok, sector2, hold1, _} =
      Gate.Sector.reserve(
        sector,
        2,
        :contiguous,
        1_000
      )

    {:ok, sector3, _tickets} =
      Gate.Sector.confirm(
        sector2,
        hold1,
        2_000
      )

    {:ok, sector4, _hold2, _} =
      Gate.Sector.reserve(
        sector3,
        1,
        :contiguous,
        3_000
      )

    {_sector5, snapshot} =
      Gate.Sector.snapshot(
        sector4,
        4_000
      )

    assert length(snapshot.sold) == 2
    assert length(snapshot.held) == 1
    assert length(snapshot.free) == 2

    assert snapshot.revenue == 200_000

    assert length(snapshot.sold) +
             length(snapshot.held) +
             length(snapshot.free) == 5
  end

  # ---------------------------------------------------------
  # Unknown hold
  # ---------------------------------------------------------

  test "un hold desconocido falla sin romper el programa" do
    sector = new_sector()

    assert {:error, :unknown_hold} =
             Gate.Sector.confirm(
               sector,
               {:inventado, 999},
               1_000
             )

    assert {:error, :unknown_hold} =
             Gate.Sector.cancel(
               sector,
               {:inventado, 999},
               1_000
             )
  end
end
