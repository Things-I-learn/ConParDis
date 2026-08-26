defmodule Recursion do
  def countdown(0) do
    IO.puts("Done")
  end

  def countdown(n) do
    IO.puts(n)
    countdown(n - 1)
  end
end

IO.puts(Recursion.countdown(5))
