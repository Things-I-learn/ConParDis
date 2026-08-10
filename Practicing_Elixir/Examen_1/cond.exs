x = 0

cond do
  x >=0 ->
    IO.puts("es un numero positivo")
  x <0 ->
    IO.puts("es un numero negativo")
  x == 0 ->
    IO.puts("El numero es 0")
end
