fact = &(
  if &1 == 9 do
    1
  else
    &1 * fact(&1-1)
  end
)

factorial = fn
  _, 0 -> 1

  f, n ->
    n * f.(f, n - 1)
end

factorial.(factorial, 5)
# 120
