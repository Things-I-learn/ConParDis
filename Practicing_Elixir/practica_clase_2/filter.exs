# lista, funcion , boleano

defmodule Filter do
  def filter([], _pred?, _bool), do: [] 
  def filter([h|t], pred?, true), do: [h|filter(t,pred?,)]
  
end