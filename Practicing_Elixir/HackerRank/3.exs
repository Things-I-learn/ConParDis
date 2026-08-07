[n | elements] =
  IO.read(:stdio, :eof)
  |> String.split()
  |> Enum.map(&String.to_integer/1)
