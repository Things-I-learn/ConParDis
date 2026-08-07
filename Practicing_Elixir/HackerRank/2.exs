defmodule Solution do
    def n_hello(0) do
    end

    def n_hello(n) do
        IO.puts("Hello World")
        n_hello(n-1)
    end
end

n = IO.gets("") |>String.to_integer()
Solution.n_hello(n)
