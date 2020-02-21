mode = ScriptMode.Verbose

packageName   = "testutils"
version       = "0.0.1"
author        = "Status Research & Development GmbH"
description   = "A unittest framework"
license       = "Apache License 2.0"
skipDirs      = @["tests"]

requires "nim >= 1.0.2"
#requires "json_serialization"

task test, "run CPU tests":
  cd "tests"
  exec "nim c -r testrunner ."

