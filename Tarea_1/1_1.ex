defmodule Tarea1 do
  def number?(a,b,c) do
    is_number(a) and is_number(b) and is_number(c)
  end

  def triangulo?(a, b, c) do
    a >0 and b >0 and c>0
  end

  def equilateral?(a,b,c)  do
    a == b and b== c
  end
  def isosceles?(a, b, c) do
    a == b or b== c or c == a
  end


  def kind(a, b, c) do

    cond do
      not number?(a,b,c) -> {:error, "no es un numero"}

      not triangulo?(a,b,c) -> {:error, "no es un triangulo"}

      equilateral?(a,b,c) -> {:ok, :equilateral}

      isosceles?(a,b,c) -> {:ok, :isosceles}

      true -> {:ok, :scalene}

    end


  end



end



IO.inspect(Tarea1.kind(3, 3, 3), label: "Equilateral")
IO.inspect(Tarea1.kind(3, 3, 5), label: "Isosceles")
IO.inspect(Tarea1.kind(3, 4, 5), label: "Scalene")
IO.inspect(Tarea1.kind(0, 3, 3), label: "Cero")
IO.inspect(Tarea1.kind(-1, 3, 3), label: "Negativo")
IO.inspect(Tarea1.kind("3", 3, 3), label: "No numerico")
IO.inspect(Tarea1.kind(2.5, 2.5, 2.5), label: "Decimales")
IO.inspect(Tarea1.kind(1, 2, 10), label: "Triangulo imposible")
