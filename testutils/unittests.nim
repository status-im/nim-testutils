import
  unittest

export
  unittest

template procSuite*(name: string, body: untyped) =
  proc suitePayload =
    suite name, body

  suitePayload()

template asyncTest*(name, body: untyped) =
  test name:
    proc scenario {.async.} = body
    waitFor scenario()

