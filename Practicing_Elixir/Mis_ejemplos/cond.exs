x = 7

cond do
  x > 10 ->
    IO.puts("Greater than 10")

  x > 5 ->
    IO.puts("Greater than 5")

  true ->
    IO.puts("5 or less")
end
