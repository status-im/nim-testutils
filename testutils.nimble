mode = ScriptMode.Verbose

packageName   = "testutils"
version       = "0.6.0"
author        = "Status Research & Development GmbH"
description   = "A unittest framework"
license       = "Apache License 2.0"
skipDirs      = @["tests"]
bin           = @["ntu"]
#srcDir        = "testutils"

requires "nim >= 1.6.0",
         "unittest2"

proc execCmd(cmd: string) =
  echo "execCmd: " & cmd
  exec cmd

proc execTest(test: string) =
  let test = "ntu test " & test
  execCmd "nim c   --mm:refc         -f -r " & test
  execCmd "nim c   --mm:refc -d:release -r " & test
  execCmd "nim c   --mm:refc -d:danger  -r " & test
  execCmd "nim cpp --mm:refc            -r " & test
  execCmd "nim cpp --mm:refc -d:danger  -r " & test
  if (NimMajor, NimMinor) > (1, 6):
    execCmd "nim c   --mm:orc         -f -r " & test
    execCmd "nim c   --mm:orc -d:release -r " & test
    execCmd "nim c   --mm:orc -d:danger  -r " & test
    execCmd "nim cpp --mm:orc            -r " & test
    execCmd "nim cpp --mm:orc -d:danger  -r " & test

  execCmd "nim c   --gc:arc --exceptions:goto -r " & test
  when false:
    # we disable gc:arc test here because Nim cgen
    # generate something not acceptable for clang
    # and failed on windows 64 bit too
    # TODO https://github.com/nim-lang/Nim/issues/22101
    execCmd "nim cpp --gc:arc --exceptions:goto -r " & test

task test, "run tests for travis":
  execTest("tests")
