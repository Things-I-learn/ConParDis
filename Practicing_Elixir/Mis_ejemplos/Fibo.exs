defmodule Fibonacci do
  def fibo(1) do
    1
  end
  def fibo(0) do
    0
  end
  def fibo(x) do
    fibo(x-1) + fibo(x-2)
  end
end

# def fibo(1), do: 1
# def fibo(0), do: 0
# def fibo(x), do: fibo(x-1) + fibo(x-2)

IO.puts(Fibonacci.fibo(1))
IO.puts(Fibonacci.fibo(0))
IO.puts(Fibonacci.fibo(2))
IO.puts(Fibonacci.fibo(3))
IO.puts(Fibonacci.fibo(30))
