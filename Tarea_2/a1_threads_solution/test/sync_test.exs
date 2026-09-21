defmodule Gate.SyncTest do
  use ExUnit.Case

  alias Gate.Sync
  alias Gate.Venue

  setup do
    spec = %{
      sectors: %{
        vip: %{
          rows: 1,
          seats_per_row: 5,
          price_cop: 100_000
        },
        sur: %{
          rows: 1,
          seats_per_row: 5,
          price_cop: 80_000
        }
      },
      ttl_ms: 5_000
    }

    {:ok, venue} = Sync.start(spec)

    on_exit(fn ->
      Sync.stop(venue)
    end)

    %{venue: venue}
  end

  # ============================================================
  # 1. Dos procesos sobre el MISMO sector deben serializarse
  # ============================================================

  test "dos procesos no ejecutan fun al mismo tiempo en el mismo sector",
       %{venue: venue} do
    parent = self()

    pid_a =
      spawn(fn ->
        result =
          Sync.update(
            venue,
            :vip,
            fn sector, _now ->
              # Avisamos al proceso del test que A entró
              send(parent, {:entered, :a, self()})

              # A se queda dentro de la sección crítica
              # hasta que el test le permita continuar.
              receive do
                :continue ->
                  {:a_done, sector}
              end
            end
          )

        send(parent, {:finished, :a, result})
      end)

    # Confirmamos que A entró al sector :vip
    assert_receive {:entered, :a, ^pid_a}, 1_000

    pid_b =
      spawn(fn ->
        result =
          Sync.update(
            venue,
            :vip,
            fn sector, _now ->
              send(parent, {:entered, :b, self()})

              receive do
                :continue ->
                  {:b_done, sector}
              end
            end
          )

        send(parent, {:finished, :b, result})
      end)

    # B NO debe entrar mientras A tenga el mutex de :vip
    refute_receive {:entered, :b, ^pid_b}, 100

    # Permitimos que A termine y libere el mutex
    send(pid_a, :continue)

    # Ahora B sí debe poder entrar
    assert_receive {:entered, :b, ^pid_b}, 1_000

    # A también debe haber terminado correctamente
    assert_receive {:finished, :a, :a_done}, 1_000

    # Permitimos que B termine
    send(pid_b, :continue)

    assert_receive {:finished, :b, :b_done}, 1_000
  end

  # ============================================================
  # 2. Dos procesos sobre sectores DIFERENTES pueden avanzar
  #    al mismo tiempo
  # ============================================================

  test "dos procesos pueden trabajar al mismo tiempo en sectores diferentes",
       %{venue: venue} do
    parent = self()

    pid_a =
      spawn(fn ->
        result =
          Sync.update(
            venue,
            :vip,
            fn sector, _now ->
              send(parent, {:entered, :a, self()})

              receive do
                :continue ->
                  {:a_done, sector}
              end
            end
          )

        send(parent, {:finished, :a, result})
      end)

    # A entra a :vip y se queda allí
    assert_receive {:entered, :a, ^pid_a}, 1_000

    pid_b =
      spawn(fn ->
        result =
          Sync.update(
            venue,
            :sur,
            fn sector, _now ->
              send(parent, {:entered, :b, self()})

              receive do
                :continue ->
                  {:b_done, sector}
              end
            end
          )

        send(parent, {:finished, :b, result})
      end)

    # Aunque A todavía tenga :vip,
    # B debe poder entrar a :sur.
    assert_receive {:entered, :b, ^pid_b}, 1_000

    # Liberamos ambos procesos
    send(pid_a, :continue)
    send(pid_b, :continue)

    assert_receive {:finished, :a, :a_done}, 1_000
    assert_receive {:finished, :b, :b_done}, 1_000
  end

  # ============================================================
  # 3. Muchos procesos compiten por UN SOLO asiento
  # ============================================================

  test "solo un proceso puede reservar el ultimo asiento disponible" do
    spec = %{
      sectors: %{
        vip: %{
          rows: 1,
          seats_per_row: 1,
          price_cop: 100_000
        }
      },
      ttl_ms: 5_000
    }

    {:ok, venue} =
      Venue.start_venue(spec)

    on_exit(fn ->
      Venue.stop_venue(venue)
    end)

    parent = self()

    procesos =
      for _ <- 1..10 do
        spawn(fn ->
          # Todos esperan la señal :go
          receive do
            :go ->
              result =
                Venue.reserve(
                  venue,
                  :vip,
                  1,
                  :contiguous
                )

              send(
                parent,
                {:result, result}
              )
          end
        end)
      end

    # Mandamos a los 10 procesos a competir
    # por el asiento.
    Enum.each(procesos, fn pid ->
      send(pid, :go)
    end)

    resultados =
      for _ <- 1..10 do
        receive do
          {:result, result} ->
            result
        after
          2_000 ->
            flunk("un proceso no respondió a tiempo")
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

    errores =
      Enum.filter(
        resultados,
        fn result ->
          match?(
            {:error, :sold_out},
            result
          )
        end
      )

    # Solo uno puede haber obtenido el asiento.
    assert length(exitos) == 1

    # Los otros nueve deben encontrarlo ocupado.
    assert length(errores) == 9

    # Como el asiento está held,
    # ya no cuenta como disponible.
    assert Venue.availability(
             venue,
             :vip
           ) == 0
  end
  test "otro proceso puede continuar si el dueño del mutex muere",
     %{venue: venue} do
  parent = self()

  # A nace ya monitorizado.
  {pid_a, monitor_ref} =
    spawn_monitor(fn ->
      Sync.update(
        venue,
        :vip,
        fn _sector, _now ->
          send(parent, :a_entered)

          exit(:boom)
        end
      )
    end)

  # A consiguió entrar a la sección crítica.
  assert_receive :a_entered, 1_000

  # Como estaba monitorizado desde el principio,
  # debemos recibir la causa real de su muerte.
  assert_receive {
                   :DOWN,
                   ^monitor_ref,
                   :process,
                   ^pid_a,
                   :boom
                 },
                 1_000

  # Ahora B intenta utilizar el mismo sector.
  pid_b =
    spawn(fn ->
      result =
        Sync.update(
          venue,
          :vip,
          fn sector, _now ->
            {:b_done, sector}
          end
        )

      send(parent, {:b_result, result})
    end)

  assert_receive {:b_result, :b_done}, 1_000

  refute Process.alive?(pid_b)
end
end
