#Procesos ligeros que viven dentro de procesos.W

IO.puts("Proceso principal: #{inspect(self())}")

spawn(fn ->
  IO.puts("Proceso nuevo: #{inspect(self())}")
end)
