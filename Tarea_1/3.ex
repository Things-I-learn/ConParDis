defmodule Task3 do

def count(nil), do: %{}

def count(texto) do
  texto
  |> String.downcase()
  |> Regex.scan(~r/[A-Za-z]+(?:'[A-Za-z]+)?|\d+/)
  |> List.flatten()
  |> Enum.reduce(%{}, fn palabra, conteo ->
    Map.update(conteo, palabra, 1, fn valor ->
      valor + 1
    end)
  end)
end

end
