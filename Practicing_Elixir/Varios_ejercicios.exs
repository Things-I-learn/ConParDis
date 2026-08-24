defmodule Numero do
  def paridad(x) when rem(x,2) ==0 do
    IO.puts("El numero es par")
  end
  def paridad(x) when rem(x,2) !=0 do
    IO.puts("El numero es impar")
  end
end

Numero.paridad(5)
|>IO.puts()


defmodule Numero do
  defp es_par(n) do
    rem(n, 2) == 0 # puede devolver un valor de verdad
  end

  def tipo(n) do
    if es_par(n) do
      "par"
    else
      "impar"
    end
  end
end

IO.inspect(Numero.tipo(7))
# "impar"

defmodule Notas do
  defp nota_valida?(nota) do
    nota >= 0 and nota <= 5
  end

  def clasificar(nota) do
    cond do
      not nota_valida?(nota) -> "Nota inválida"
      nota >= 4.5 -> "Excelente"
      nota >= 4.0 -> "Muy bien"
      nota >= 3.0 -> "Aprobado"
      true -> "Reprobado"
    end
  end
end

IO.inspect(Notas.clasificar(4.2))
# "Muy bien"

defmodule Calculadora do
  defp dividir(_a, 0) do
    {:error, "No se puede dividir por cero"}
  end

  defp dividir(a, b) do
    a / b
  end

  def operar(operacion, a, b) do
    case operacion do
      :suma -> a + b
      :resta -> a - b
      :multiplicacion -> a * b
      :division -> dividir(a, b)
      _ -> {:error, "Operación desconocida"}
    end
  end
end

IO.inspect(Calculadora.operar(:suma, 4, 2))
IO.inspect(Calculadora.operar(:division, 4, 2))

defmodule Persona do
  defp edad_valida?(edad) do
    edad >= 0
  end

  def etapa(edad) do
    cond do
      not edad_valida?(edad) -> "Edad inválida"
      edad <= 12 -> "Niño"
      edad <= 17 -> "Adolescente"
      edad <= 64 -> "Adulto"
      true -> "Adulto mayor"
    end
  end
end

IO.inspect(Persona.etapa(24))
# "Adulto"

defmodule Login do
  defp longitud_valida?(password) do
    String.length(password) >= 8
  end

  def validar(password) do
    if longitud_valida?(password) do
      "Contraseña válida"
    else
      "Contraseña inválida"
    end
  end
end

IO.inspect(Login.validar("elixir123"))
# "Contraseña válida"


defmodule Semaforo do
  def accion(color) do
    case color do
      :rojo -> "Detenerse"
      :amarillo -> "Precaución"
      :verde -> "Avanzar"
      _ -> "Color desconocido"
    end
  end
end

IO.inspect(Semaforo.accion(:rojo))
IO.inspect(Semaforo.accion(:verde))
IO.inspect(Semaforo.accion(:azul))