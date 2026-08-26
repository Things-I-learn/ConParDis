sum = fn a, b -> a+b end


describe = fn
  0 -> "Zero"
  1 -> "One"
  2 -> "Two"
  _ -> "Other"
end
sum = &(&1 + &2 * &2)
