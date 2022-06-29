mode = ScriptMode.Verbose

packageName   = "testutils"
version       = "0.5.0"
author        = "Status Research & Development GmbH"
description   = "A unittest framework"
license       = "Apache License 2.0"
skipDirs      = @["tests"]
bin           = @["ntu"]
#srcDir        = "testutils"

requires "nim >= 1.2.0",
         "unittest2"

proc execCmd(cmd: string) =
  echo "execCmd: " & cmd
  exec cmd

proc execTest(test: string) =
  let
    test = "ntu test " & test
  when true:
    execCmd "nim c           -f -r " & test
    execCmd "nim c   -d:release -r " & test
    execCmd "nim c   -d:danger  -r " & test
    execCmd "nim cpp            -r " & test
    execCmd "nim cpp -d:danger  -r " & test
    #when NimMajor >= 1 and NimMinor >= 1 and not defined(macosx):
    when false:
      # we disable gc:arc test here because Nim cgen
      # generate something not acceptable for clang
      # and failed on windows 64 bit too
      execCmd "nim c   --gc:arc --exceptions:goto -r " & test
      execCmd "nim cpp --gc:arc --exceptions:goto -r " & test
  else:
    execCmd "nim c           -f -r " & test

task test, "run tests for travis":
  execTest("tests")
