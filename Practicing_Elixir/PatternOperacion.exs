#Crea dos variables a = 15 y b = 7 y muestra su suma, resta, multiplicación y división.
a = 15
b = 7
defmodule CuatroOperaciones do
  def operacion("suma", a,b), do: a+b
  def operacion("resta", a,b), do: a-b
  def operacion("multiplicacion", a,b), do: a*b
  def operacion("division", a,b), do: a/b
  def operacion(_,_,_), do: "No es una operación válida"
end





IO.puts(CuatroOperaciones.operacion("suma", a, b))
