import unittest2

suite "goats":
  test "pigs":
    echo "oink"
    check true

  test "horses":
    expect ValueError:
      echo "ney"
      raise newException(ValueError, "you made an error")
