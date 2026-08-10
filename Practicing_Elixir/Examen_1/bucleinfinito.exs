defmodule Bucleinfito do

  def infinito(x) do
    IO.puts(x)
    infinito(x+1)

  end
end


Bucleinfito.infinito(0)
