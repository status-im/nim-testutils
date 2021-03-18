{.used.}

template tests*(body: untyped) =
  template payload =
    when not declared(unittest2):
      import unittest2

    body

  when defined(testutils_test_build):
    payload()
  else:
    when not compiles(payload()):
      payload()

template programMain*(body: untyped) =
  proc main =
    body

  when not defined(testutils_test_build):
    main()

