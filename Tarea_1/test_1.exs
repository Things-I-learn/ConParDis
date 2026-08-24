ExUnit.start()

Code.require_file("1.ex")

defmodule Ejercicio1Test do
  use ExUnit.Case

  test "triángulo equilátero" do
    assert Ejercicio1.kind(3, 3, 3) == {:ok, :equilateral}
  end

  test "triángulo isósceles" do
    assert Ejercicio1.kind(3, 3, 4) == {:ok, :isosceles}
    assert Ejercicio1.kind(3, 4, 3) == {:ok, :isosceles}
    assert Ejercicio1.kind(4, 3, 3) == {:ok, :isosceles}
  end

  test "triángulo escaleno" do
    assert Ejercicio1.kind(3, 4, 5) == {:ok, :scalene}
  end

  test "lados no positivos" do
    assert Ejercicio1.kind(0, 3, 3) == {:error, "Invalid triangle"}
    assert Ejercicio1.kind(-1, 3, 3) == {:error, "Invalid triangle"}
  end

  test "no cumple la desigualdad triangular" do
    assert Ejercicio1.kind(2, 3, 10) == {:error, "Invalid triangle"}
  end

  test "acepta números decimales" do
    assert Ejercicio1.kind(3.5, 3.5, 3.5) == {:ok, :equilateral}
  end

  test "valores no numéricos" do
    assert Ejercicio1.kind(nil, 3, 3) == {:error, "Invalid triangle"}
    assert Ejercicio1.kind("3", 3, 3) == {:error, "Invalid triangle"}
  end
end
