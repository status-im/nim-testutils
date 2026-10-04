mode = ScriptMode.Verbose

packageName   = "testutils"
version       = "0.8.5"
author        = "Status Research & Development GmbH"
description   = "A unittest framework"
license       = "Apache License 2.0"
skipDirs      = @["tests"]
bin           = @["ntu"]
installFiles  = @["scripts/install_honggfuzz.sh"]
#srcDir        = "testutils"

requires "nim >= 1.6.18",
         "results >= 0.5.0",
         "stew >= 0.5.0",
         "unittest2 >= 0.2.0"

let nimc = getEnv("NIMC", "nim") # Which nim compiler to use
let lang = getEnv("NIMLANG", "c") # Which backend (c/cpp/js)
let flags = getEnv("NIMFLAGS", "") # Extra flags for the compiler
let verbose = getEnv("V", "") notin ["", "0"]
let platform = getEnv("PLATFORM", "")
let testArguments = [
  "-d:debug",
  "-d:release",
  "-d:danger",
]

from std/os import quoteShell

let cfg =
  " --styleCheck:usages --styleCheck:error" &
  (if verbose: "" else: " --verbosity:0") &
  " --skipParentCfg --skipUserCfg --outdir:build -f " &
  quoteShell("--nimcache:build/nimcache/$projectName")

proc build(args, path: string, cmdArgs = "") =
  exec nimc & " " & lang & " " & cfg & " " & flags & " " & args & " " & path & " " & cmdArgs

proc run(args, path: string, cmdArgs = "") =
  try:
    putEnv("NIMFLAGS", flags & " " & args)  # Apply to programs compiled by ntu
    build args & " -r", path, cmdArgs
  finally:
    putEnv("NIMFLAGS", flags)

task test, "Run all tests":
  for args in testArguments:
    run args & " --mm:refc", "ntu", "test tests"
    if (NimMajor, NimMinor) > (1, 6):
      run args & " --mm:orc", "ntu", "test tests"

  # Nim cgen generates something not acceptable for clang in C++ mode
  # TODO https://github.com/nim-lang/Nim/issues/22101
  if lang == "c" or (NimMajor, NimMinor) >= (2, 2):
    run "--mm:arc --exceptions:goto", "ntu", "test tests"

task test_asan, "Run all tests with ASAN":
  if platform != "x86" and (NimMajor, NimMinor) >= (2, 2):
    try:
      exec "echo '#if __clang_major__ < 20\n#error\n#endif' | clang -E - >/dev/null"
    except OSError:
      return

    # https://clang.llvm.org/docs/AddressSanitizer.html
    putEnv("ASAN_OPTIONS", "detect_leaks=0:detect_stack_use_after_return=1")
    # https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html
    putEnv("UBSAN_OPTIONS", "print_stacktrace=1")
    let asanArgs =
      " --mm:orc -d:useMalloc --cc:clang --debugger:native" &
      " --passC:-fsanitize=address,undefined" &
      " --passL:-fsanitize=address,undefined" &
      " --passC:-fno-sanitize-recover=undefined" &
      " --passC:-fno-sanitize-merge" &
      " --passC:-fno-omit-frame-pointer"
    for args in testArguments:
      run args & asanArgs, "ntu", "test --exclude:hello_size tests"

let
  fuzzSeconds = getEnv("FUZZ_SECONDS", "10")
  fuzzTime =
    if fuzzSeconds == "": ""
    else: " --duration=" & fuzzSeconds & " "

proc execFuzz(test: string, fuzzer: string) =
  run "-d:release", "ntu", "fuzz --fuzzer=" & fuzzer & fuzzTime & test

task fuzz, "Run fuzzing tests":
  run "-d:release", "tests/tfuzzing"

  for fuzzer in ["libFuzzer", "honggfuzz", "afl"]:
    when defined(macosx):
      if fuzzer == "honggfuzz":
        continue

    var didFail = false
    try:
      execFuzz("tests/fuzzing/fuzz_bug.nim", fuzzer)
    except OSError:
      didFail = true
    doAssert didFail

    execFuzz("tests/fuzzing/fuzz_ok.nim", fuzzer)
