import ../../testutils/fuzzing

var initialized = false
initialized = true  # Ensure NimMain was called

test:
  doAssert initialized

  var x = 0'u8
  for v in payload:
    x = x xor v
  for v in payload:
    x = x xor v
  doAssert x == 0
