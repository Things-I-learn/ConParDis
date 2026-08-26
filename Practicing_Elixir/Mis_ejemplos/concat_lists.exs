defmodule Concat do
  def concat([],b) do
    b
  end

  def concat([head|tail], b) do
     [head |concat(tail, b)   ]
  end
end


l1 = [1,2,3]
l2 = [4,5,6]

Concat.concat(l1,l2) |> IO.inspect()

#1, [2,3]

# [1 | [2 | [3 | [4| [] ]]]]

#[],[5,6,7]
