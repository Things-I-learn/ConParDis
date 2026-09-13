defmodule Task2 do

  def create(direction, position) do
    {direction, position}
  end

  def direction(nil), do: nil
  def direction({direction, _position}), do: direction

  def position(nil), do: nil
  def position({_direction, position}), do: position

  def simulate(nil, _instructions), do: nil

  def simulate(robot, nil), do: robot

  def simulate(robot, instructions) do
    movimientos = String.graphemes(instructions)
    ejecutar(robot, movimientos)
  end

  defp girar_derecha(:north), do: :east
  defp girar_derecha(:east), do: :south
  defp girar_derecha(:south), do: :west
  defp girar_derecha(:west), do: :north
  defp girar_derecha(direction), do: direction

  defp girar_izquierda(:north), do: :west
  defp girar_izquierda(:west), do: :south
  defp girar_izquierda(:south), do: :east
  defp girar_izquierda(:east), do: :north
  defp girar_izquierda(direction), do: direction

  defp avanzar(:north, {x, y}), do: {:north, {x, y + 1}}
  defp avanzar(:south, {x, y}), do: {:south, {x, y - 1}}
  defp avanzar(:east, {x, y}), do: {:east, {x + 1, y}}
  defp avanzar(:west, {x, y}), do: {:west, {x - 1, y}}

  defp avanzar(direction, position) do
    {direction, position}
  end

  defp ejecutar(robot, []) do
    robot
  end

  defp ejecutar({direction, position}, [movimiento | tail]) do
    nuevo_robot =
      case movimiento do
        "R" -> {girar_derecha(direction), position}
        "L" -> {girar_izquierda(direction), position}
        "A" -> avanzar(direction, position)
         _ -> {direction, position}
      end

    ejecutar(nuevo_robot, tail)
  end
end
