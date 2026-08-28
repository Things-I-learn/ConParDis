defmodule Ejercicio3 do
  def count() do

  end

end




texto = " Hola mundo it's Hola 2 024"



# palabras_minusculas = Enum.map(palabras, &String.downcase/1)

 conteo = Enum.reduce(palabras, %{}, fn palabra, conteo -> Map.update(conteo, palabra, 1, fn valor -> valor + 1 end) end
         )


~r/[A-Za-z]+(?:'[A-Za-z]+)?|\d|\d+/


[\d \d+]
