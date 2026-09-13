defmodule TopSecret do

  def to_ast(nil), do: nil

  def to_ast(code) do
    Code.string_to_quoted!(code)
  end


  def decode_secret_message_part(ast_node, nil) do
    decode_secret_message_part(ast_node, [])
  end

  def decode_secret_message_part(
        {operation, _, [{:when, _, [{name, _, args} | _]} | _]} = ast_node,
        acc
      )
      when operation in [:def, :defp] do

    arity = length(args || [])

    secret_part =
      name
      |> Atom.to_string()
      |> String.slice(0, arity)

    {ast_node, [secret_part | acc]}
  end


  def decode_secret_message_part(
        {operation, _, [{name, _, args} | _]} = ast_node,
        acc
      )
      when operation in [:def, :defp] do

    arity = length(args || [])

    secret_part =
      name
      |> Atom.to_string()
      |> String.slice(0, arity)

    {ast_node, [secret_part | acc]}
  end

  def decode_secret_message_part(ast_node, acc) do
    {ast_node, acc}
  end


  def decode_secret_message(nil), do: ""

  def decode_secret_message(code) do
    {_ast, secret_parts} =
      code
      |> to_ast()
      |> Macro.prewalk([], &decode_secret_message_part/2)

    secret_parts
    |> Enum.reverse()
    |> Enum.join()
  end
end
