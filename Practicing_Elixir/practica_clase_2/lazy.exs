Enum.to_list(1..100)|> Enum.map(&-/1)


Stream.map(1..1000000000, (&-1))
