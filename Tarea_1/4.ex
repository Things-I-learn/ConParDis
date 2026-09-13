defmodule Task4 do

  def search(nil, _val), do: :not_found

  def search(tuple, val) do
    search(tuple, 0, tuple_size(tuple) - 1, val)
  end

  defp search(_tuple, left, right, _val) when left > right do
    :not_found
  end

  defp search(tuple, left, right, val) do
    mitad = div(right - left, 2) + left
    element = elem(tuple, mitad)

    case element do
      n when n == val ->
        {:ok, mitad}

      n when n < val ->
        search(tuple, mitad + 1, right, val)

      n when n > val ->
        search(tuple, left, mitad - 1, val)
    end
  end
end
