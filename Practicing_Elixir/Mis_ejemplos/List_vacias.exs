defmodule PrintsList do
  def list([]) do
  end

  def list(l) do
    [head|tail] = l
    IO.puts(head)
    list(tail)
  end
end

IO.puts(PrintsList.list([1,2,3]))
