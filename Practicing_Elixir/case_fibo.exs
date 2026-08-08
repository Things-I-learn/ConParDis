x = 10
a = 0
b = 1

defmodule IterationFibo do
  def fibo(0,a, _b) do
    a
  end

  def fibo(x,a,b) do
    c = b
    b = a+b
    a = c
    fibo(x-1, a,b )
  end
end


IterationFibo.fibo(x,a,b)|>IO.puts()
