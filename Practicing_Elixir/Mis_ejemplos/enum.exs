numbers = [1, 2, 3, 4, 5, 6]

result =
  numbers
  |> Enum.filter(fn x -> rem(x, 2) == 0 end)
  |> Enum.map(fn x -> x * 2 end)
  |> Enum.sum()

IO.puts(result)
