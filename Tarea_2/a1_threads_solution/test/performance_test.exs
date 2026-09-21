defmodule Gate.PerformanceTest do
  use ExUnit.Case

  alias Gate.Venue

  @tag timeout: 60_000
  test "muchas reservas secuenciales" do
    number_of_seats = 5_000

    spec = %{
      sectors: %{
        vip: %{
          rows: 100,
          seats_per_row: 50,
          price_cop: 100_000
        }
      },

      # No queremos expiraciones durante la medición.
      ttl_ms: 60_000
    }

    {:ok, venue} =
      Venue.start_venue(spec)

    on_exit(fn ->
      Venue.stop_venue(venue)
    end)

    start_time =
      System.monotonic_time(:millisecond)

    for _ <- 1..number_of_seats do
      assert {:ok, _hold_id, [_seat_id]} =
               Venue.reserve(
                 venue,
                 :vip,
                 1,
                 :any
               )
    end

    end_time =
      System.monotonic_time(:millisecond)

    elapsed_ms =
      end_time - start_time

    IO.puts(
      "\nTiempo para #{number_of_seats} reservas: #{elapsed_ms} ms"
    )

    assert Venue.availability(
             venue,
             :vip
           ) == 0

    snapshot =
      Venue.snapshot(venue)

    assert length(snapshot.held) == 5_000
    assert snapshot.free == []
  end
end
