mode = ScriptMode.Verbose

packageName   = "testutils"
version       = "0.8.2"
author        = "Status Research & Development GmbH"
description   = "A unittest framework"
license       = "Apache License 2.0"
skipDirs      = @["tests"]
bin           = @["ntu"]
#srcDir        = "testutils"

requires "nim >= 1.6.0",
         "stew",
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

let
  fuzzSeconds = getEnv("FUZZ_SECONDS", "10")
  fuzzTime =
    if fuzzSeconds == "": ""
    else: " --duration=" & fuzzSeconds & " "

proc execFuzz(test: string, fuzzer: string) =
  execCmd "nim c -d:release -r ntu fuzz --fuzzer=" & fuzzer & fuzzTime & test

task fuzz, "run fuzzing tests":
  execCmd "nim c -d:release -r tests/tfuzzing.nim"

  for fuzzer in ["libFuzzer", "honggfuzz", "afl"]:
    when defined(macos) or defined(macosx):
      if fuzzer == "honggfuzz":
        continue

    var didFail = false
    try:
      execFuzz("tests/fuzzing/fuzz_bug.nim", fuzzer)
    except OSError:
      didFail = true
    doAssert didFail

    execFuzz("tests/fuzzing/fuzz_ok.nim", fuzzer)
