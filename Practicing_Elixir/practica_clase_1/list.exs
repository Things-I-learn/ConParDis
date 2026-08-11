#head -> tail tiene apuntadores a la cola


x = [1,2,3]

defmodule All do
  def sumall([],c) do
    c
  end

  def sumall([head|tail],c) do
    sumall(tail, head+c)
  end

end

All.sumall(x, 0) |> IO.puts()
