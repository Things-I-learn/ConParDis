defmodule Factorial do
    defp fact_iter(0, acc)  do
    acc
  end

  defp fact_iter(n, acc) when n>0  do
    fact_iter(n - 1, n * acc)
  end

  def fact(n) do
    fact_iter(n, 1)
  end


end

IO.inspect(Factorial.fact(5))

defmodule Fibo do
  defp fibo_iter(0,a, _b) do
    a
  end

  defp fibo_iter(n, a, b) do
    fibo_iter(n-1, b,a+b)
  end

  def fibo(n) when n >= 0 do
    fibo_iter(n, 0, 1)
  end
end
