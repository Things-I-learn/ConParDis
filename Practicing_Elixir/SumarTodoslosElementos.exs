a = [1,2]

defmodule Allsum do
  def allsum([],c) do
    c
  end
  def allsum([head|tail],c) do
    allsum(tail,c+head)
  end
end

defmodule Allsum do
  def allsum([],c), do: c
  def allsum([head|tail],c), do: allsum(tail,c+head)
end


a = [1,2,3]

Allsum.allsum(a, 0) |>IO.puts()


sum = fn
  _, [], c -> c
  f, [head|tail], c -> f.(f,tail,c+head)
end


sum.(sum,a,0) |>IO.puts()
