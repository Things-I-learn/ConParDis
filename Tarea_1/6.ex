# debe recibir codigo elixir en un string y pasar datos.

defmodule TopSecret do
  def to_ast(code) do
    Code.string_to_quoted(code)
  end

end

TopSecret.to_ast("div(4,3)") |> IO.puts()
