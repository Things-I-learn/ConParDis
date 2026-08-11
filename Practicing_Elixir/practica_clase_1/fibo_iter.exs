defmodule Fiboiter do
  def fibo(0,a, _b) do
    a
  end

  def fibo(n,a,b) do
    fibo(n-1, b,a+b)
  end
end

Fiboiter.fibo(100, 0, 1) |> IO.puts()
