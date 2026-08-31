defmodule Tarea4 do
  def search(tuple, val), do: search(tuple, 0, tuple_size(tuple)-1, val)


  defp search(_tuple, left, right, _val) when left>right  do
      :not_found
  end

  defp search(tuple, left, right, val) do
    mitad = div(right-left, 2) +left
    element = elem(tuple,mitad)

    case element do
      n when n == val -> {:ok, mitad}
      n when n <val -> search(tuple, mitad+1,right , val)
      n when n > val -> search(tuple, left, mitad-1, val)
    end

  end
end




Tarea4.search({2, 5, 8, 12, 16, 23, 38}, 12) |>IO.inspect()
Tarea4.search({2, 5, 8, 12, 16, 23, 38}, 2) |>IO.inspect()
Tarea4.search({2, 5, 8, 12, 16, 23, 38}, 38) |>IO.inspect()
Tarea4.search({2, 5, 8, 12, 16, 23, 38}, 100) |>IO.inspect()
Tarea4.search({2, 5, 8, 12, 16, 23, 38}, -100) |>IO.inspect()
