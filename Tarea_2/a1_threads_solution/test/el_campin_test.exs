defmodule Gate.ElCampinTest do
  use ExUnit.Case

  alias Gate.Venue
  alias Gate.VenueSpec

  setup do
    spec = VenueSpec.el_campin()

    {:ok, venue} =
      Venue.start_venue(spec)

    on_exit(fn ->
      Venue.stop_venue(venue)
    end)

    %{
      venue: venue,
      spec: spec
    }
  end

  test "El Campin inicia con todos los asientos libres",
       %{venue: venue, spec: spec} do
    snapshot =
      Venue.snapshot(venue)

    total_esperado =
      spec.sectors
      |> Enum.reduce(0, fn {_sector_name, shape}, acc ->
        acc +
          shape.rows *
            shape.seats_per_row
      end)

    assert total_esperado == 36_016

    assert length(snapshot.free) ==
             total_esperado

    assert snapshot.held == []
    assert snapshot.sold == []
    assert snapshot.revenue == 0
  end
  test "se puede reservar y confirmar en un sector real de El Campin",
     %{venue: venue, spec: spec} do

  # Tomamos uno de los sectores reales del recinto.
  {sector_name, shape} =
    Enum.at(spec.sectors, 0)

  total_sector =
    shape.rows * shape.seats_per_row

  # Antes de reservar, todo el sector está disponible.
  assert Venue.availability(
           venue,
           sector_name
         ) == total_sector

  # Reservamos dos asientos contiguos.
  assert {:ok, hold_id, seat_ids} =
           Venue.reserve(
             venue,
             sector_name,
             2,
             :contiguous
           )

  assert length(seat_ids) == 2

  # Los asientos held ya no cuentan como disponibles.
  assert Venue.availability(
           venue,
           sector_name
         ) == total_sector - 2

  # Confirmamos la compra.
  assert {:ok, tickets} =
           Venue.confirm(
             venue,
             hold_id
           )

  assert length(tickets) == 2

  # Confirmar cambia held -> sold.
  # Por eso la disponibilidad continúa siendo total - 2.
  assert Venue.availability(
           venue,
           sector_name
         ) == total_sector - 2

  # Revisamos los tickets.
  assert Enum.all?(tickets, fn ticket ->
           ticket.sector == sector_name and
             ticket.price_cop == shape.price_cop and
             ticket.hold_id == hold_id
         end)

  # Revisamos el estado global.
  snapshot =
    Venue.snapshot(venue)

  assert length(snapshot.sold) == 2
  assert snapshot.held == []

  assert snapshot.revenue ==
           2 * shape.price_cop

  # Siempre deben seguir existiendo exactamente
  # los 36.016 asientos.
  assert length(snapshot.free) +
           length(snapshot.held) +
           length(snapshot.sold) ==
           36_016
end
end
