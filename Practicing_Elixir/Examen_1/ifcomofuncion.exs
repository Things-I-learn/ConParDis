defmodule Condicion do
  def if(x) when x<=0 do
    "x es negativo"
  end
  def if(x) when x>0 do
    "x es positivo"
  end

  def if(x) when x==0 do
    "x es cero"
  end
end

x = 10
y= -1
w = 0
x |> Condicion.if() |>IO.puts()
y |> Condicion.if() |>IO.puts()
w |> Condicion.if() |>IO.puts()
