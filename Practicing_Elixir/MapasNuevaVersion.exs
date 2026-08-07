persona = %{nombre: "Juan", edad: 30, ciudad: "Madrid"}

# y escribe código para obtener la edad y luego crear una nueva versión donde la edad sea 26.



IO.puts(persona.edad)

persona = Map.put(persona, :edad, 26)

IO.inspect(persona)
