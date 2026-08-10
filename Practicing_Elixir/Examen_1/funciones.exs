### Hay 3 tipos de funciones

### Funciones un poco mas cortas y otras mas largas, la notacion corta no tiene el end

### y las funciones anonimas este la notacion cambia

## En todos los tipos de funciones yo puedo hacer patrones


mul = fn a, b -> a*b end

mul.(2,3) |>IO.puts()

mul = &(&1 * &2)

mul.(4,5) |>IO.puts()


defmodule Operaciones do
  def sum(a,b) do
    a+b
  end
  def res(a,b) do
    a-b
  end
end

Operaciones.sum(2,3) |>IO.puts()
Operaciones.res(2,3) |>IO.puts()

defmodule OperacionesCortas do
  def sum(a,b), do: a+b
  def res(a,b), do: a-b

end

OperacionesCortas.sum(2,3) |>IO.puts()
OperacionesCortas.res(2,3) |>IO.puts()
