defmodule Recursion do
  def factorial(0) do
    1
  end
  def factorial x do
    factorial(x-1) *x
  end
end
IO.puts(Recursion.factorial(100))
