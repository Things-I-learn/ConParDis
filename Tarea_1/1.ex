defmodule Task1 do

  def lados_numericos?(a, b, c) do
    is_number(a) and is_number(b) and is_number(c)
  end
  def lados_positivos?(a,b,c) do
    a>0 and b >0 and c> 0
  end

  def condicion_triangulo?(a,b,c) do
    a+b >= c and a+c >= b and b+c >= a
  end

  def equilatero?(a,b,c) do
    a == b and b == c
  end

  def isosceles?(a,b,c) do
    a == b or b == c or a == c
  end

  def triangulo_valido?(a,b,c) do
    lados_positivos?(a,b,c) and condicion_triangulo?(a,b,c)
  end

  def kind(a,b,c) do
    cond do
      not lados_numericos?(a, b, c) -> {:error, "Invalid triangle"}

      not triangulo_valido?(a,b,c) -> {:error, "Invalid triangle"}

      equilatero?(a,b,c) -> {:ok, :equilateral}

      isosceles?(a,b,c) -> {:ok, :isosceles}

      true ->{:ok, :scalene}
    end
  end


end
