defmodule Ejercicio2 do
  def create(direction, position) do
    {direction, position}
  end
  def direction({direction, _position}) do
    direction
  end
  def position({_direction, position}) do
    position
  end

  defp girar_derecha(:north), do: :east
  defp girar_derecha(:east), do: :south
  defp girar_derecha(:south), do: :west
  defp girar_derecha(:west), do: :north

  defp girar_izquierda(:north), do: :west
  defp girar_izquierda(:east), do: :north
  defp girar_izquierda(:south), do: :east
  defp girar_izquierda(:west), do: :south

  defp avanzar({:north, {x, y}}), do: {:north, {x, y+1}}
  defp avanzar({:south, {x, y}}), do: {:south, {x, y-1}}
  defp avanzar({:east, {x, y}}), do: {:east, {x+1, y}}
  defp avanzar({:west, {x, y}}), do: {:west, {x-1, y}}

  defp ejecutar_instruccion({directio, position}, "R") do
    {girar_derecha(direction), position}
  end


end
