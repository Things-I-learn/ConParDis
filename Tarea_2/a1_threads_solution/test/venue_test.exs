defmodule Gate.VenueTest do
  use ExUnit.Case

  alias Gate.Venue

  setup do
    spec = %{
      sectors: %{
        vip: %{
          rows: 2,
          seats_per_row: 5,
          price_cop: 100_000
        }
      },
      ttl_ms: 5_000
    }

    {:ok, venue} = Venue.start_venue(spec)

    on_exit(fn ->
      Venue.stop_venue(venue)
    end)

    %{venue: venue}
  end

  test "el venue inicia con todos los asientos disponibles",
       %{venue: venue} do
    assert Venue.availability(venue, :vip) == 10
  end

  test "reserve crea un hold y reduce la disponibilidad",
       %{venue: venue} do
    assert {:ok, hold_id, seat_ids} =
             Venue.reserve(
               venue,
               :vip,
               2,
               :contiguous
             )

    assert is_tuple(hold_id)
    assert length(seat_ids) == 2

    assert Venue.availability(venue, :vip) == 8
  end

  test "confirm convierte los asientos held en sold",
       %{venue: venue} do
    {:ok, hold_id, _seat_ids} =
      Venue.reserve(
        venue,
        :vip,
        2,
        :contiguous
      )

    assert {:ok, tickets} =
             Venue.confirm(
               venue,
               hold_id
             )

    assert length(tickets) == 2

    assert Enum.all?(tickets, fn ticket ->
             ticket.hold_id == hold_id and
               ticket.sector == :vip and
               ticket.price_cop == 100_000
           end)

    # Confirmar no devuelve los asientos a free.
    assert Venue.availability(venue, :vip) == 8
  end

  test "confirmar dos veces produce already_confirmed",
       %{venue: venue} do
    {:ok, hold_id, _seat_ids} =
      Venue.reserve(
        venue,
        :vip,
        1,
        :any
      )

    assert {:ok, _tickets} =
             Venue.confirm(
               venue,
               hold_id
             )

    assert {:error, :already_confirmed} =
             Venue.confirm(
               venue,
               hold_id
             )
  end

  test "cancel devuelve los asientos held a free",
       %{venue: venue} do
    {:ok, hold_id, _seat_ids} =
      Venue.reserve(
        venue,
        :vip,
        3,
        :any
      )

    assert Venue.availability(venue, :vip) == 7

    assert :ok =
             Venue.cancel(
               venue,
               hold_id
             )

    assert Venue.availability(venue, :vip) == 10
  end

  test "cancelar dos veces es idempotente",
       %{venue: venue} do
    {:ok, hold_id, _seat_ids} =
      Venue.reserve(
        venue,
        :vip,
        1,
        :any
      )

    assert :ok =
             Venue.cancel(
               venue,
               hold_id
             )

    assert :ok =
             Venue.cancel(
               venue,
               hold_id
             )
  end

  test "reserve devuelve bad_sector para un sector inexistente",
       %{venue: venue} do
    assert {:error, :bad_sector} =
             Venue.reserve(
               venue,
               :sector_inventado,
               1,
               :any
             )
  end

  test "confirm y cancel rechazan un hold con forma invalida",
       %{venue: venue} do
    assert {:error, :unknown_hold} =
             Venue.confirm(
               venue,
               "hold_inventado"
             )

    assert {:error, :unknown_hold} =
             Venue.cancel(
               venue,
               "hold_inventado"
             )
  end

  test "snapshot refleja free held sold y revenue",
       %{venue: venue} do
    # 2 vendidos
    {:ok, hold1, _} =
      Venue.reserve(
        venue,
        :vip,
        2,
        :contiguous
      )

    {:ok, _tickets} =
      Venue.confirm(
        venue,
        hold1
      )

    # 1 queda held
    {:ok, _hold2, _} =
      Venue.reserve(
        venue,
        :vip,
        1,
        :any
      )

    snapshot =
      Venue.snapshot(venue)

    assert length(snapshot.sold) == 2
    assert length(snapshot.held) == 1
    assert length(snapshot.free) == 7

    assert snapshot.revenue == 200_000

    assert length(snapshot.sold) +
             length(snapshot.held) +
             length(snapshot.free) == 10
  end
end
