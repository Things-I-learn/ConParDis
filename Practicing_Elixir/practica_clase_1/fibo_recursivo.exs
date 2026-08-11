defmodule Fibore do
  def fibo(0) do
    0
  end
  def fibo(1) do
    1
  end

  def fibo(a) do
    fibo(a-1) + fibo(a-2)
  end
end

Fibore.fibo(100) |> IO.puts()
