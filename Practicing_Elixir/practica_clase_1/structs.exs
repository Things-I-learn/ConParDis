defmodule Person do
  defstruct name: "", age: 0
end

p= struct(Person)

p|>IO.inspect()

p.age |> IO.inspect()


# la estructura no esta definida aún
# Construirse en tiempo de compilacion
# Algo pasa en la compilación
