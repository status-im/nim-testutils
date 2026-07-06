import std/[oids, strformat]
import results
import stew/[byteutils, io2]
export results

const
  aflGcc = "--cc=gcc " &
           "--gcc.exe=afl-gcc " &
           "--gcc.linkerexe=afl-gcc"

  aflClang = "--cc=clang " &
             "--clang.exe=afl-clang " &
             "--clang.linkerexe=afl-clang"

  aflClangFast = "--cc=clang " &
                 "--clang.exe=afl-clang-fast " &
                 "--clang.linkerexe=afl-clang-fast " &
                 "-d:clangfast"

  libFuzzerClang = "--cc=clang " &
                   "--passC='-fsanitize=fuzzer,address' " &
                   "--passL='-fsanitize=fuzzer,address'"

  honggfuzzClang = "--cc=clang " &
                   "--clang.exe=hfuzz-clang " &
                   "--clang.linkerexe=hfuzz-clang "

  # Can also test in debug mode obviously, but might be slower
  # Can turn on more logging, in case of libFuzzer it will get very verbose though
  defaultFlags = "-d:release -d:chronicles_log_level=fatal " &
                 "--hints:off --warnings:off --verbosity:0"

type
  FuzzingEngine* = enum
    libFuzzer
    honggfuzz
    afl

  AflCompiler* = enum
    gcc = aflGcc,
    clang = aflClang,
    clangFast = aflClangFast

const
  defaultFuzzingEngine* = libFuzzer

when not defined(nimscript):
  import os, osproc

  template exec(cmd: string) =
    discard execCmd(cmd)

  template mkDir(dir: string) =
    createDir dir

  template withDir*(dir: string; body: untyped): untyped =
    ## Changes the current directory temporarily.
    ##
    ## If you need a permanent change, use the `cd() <#cd,string>`_ proc.
    ## Usage example:
    ##
    ## .. code-block:: nim
    ##   withDir "foo":
    ##     # inside foo
    ##   #back to last dir
    var curDir = os.getCurrentDir()
    try:
      setCurrentDir(dir)
      body
    finally:
      setCurrentDir(curDir)
else:
  import os except dirExists

template q(x: string): string =
  quoteShell x

proc aflCompile*(target: string, c: AflCompiler) =
  let aflOptions = &"-d:afl -d:noSignalHandler {$c}"
  let compileCmd = &"nim c {defaultFlags} {aflOptions} {q target}"
  exec compileCmd

proc aflExec*(target: string,
              inputDir: string,
              outputDir: string,
              duration = 0,
              cleanStart = false): Opt[void] =
  let exe = target.addFileExt(ExeExt)
  if not dirExists(inputDir):
    # create a input dir with one 0 file for afl
    mkDir(inputDir)
    # TODO: improve
    withDir inputDir: exec "echo '0' > test"

  let durArg = if duration > 0: " -V " & $duration else: ""
  var fuzzCmd: string
  # if there is an output dir already, continue fuzzing from previous run
  if (not dirExists(outputDir)) or cleanStart:
    fuzzCmd =
      &"AFL_BENCH_UNTIL_CRASH=1 afl-fuzz -i {q inputDir} " &
      &"-o {q outputDir}{durArg} -M fuzzer01 -- {q exe}"
  else:
    fuzzCmd =
      &"AFL_BENCH_UNTIL_CRASH=1 afl-fuzz -i - " &
      &"-o {q outputDir}{durArg} -M fuzzer01 -- {q exe}"
  if execCmd(fuzzCmd) != 0:
    return err()
  ok()

proc libFuzzerCompile*(target: string) =
  let libFuzzerOptions = &"-d:llvmFuzzer --noMain {libFuzzerClang}"
  let compileCmd = &"nim c {defaultFlags} {libFuzzerOptions} {q target}"
  exec compileCmd

proc libFuzzerExec*(
    target: string, corpusDir: string,
    outputDir: string, duration = 0): Opt[void] =
  if not dirExists(corpusDir):
    # libFuzzer is OK when starting with empty corpus dir
    mkDir(corpusDir)
  if not dirExists(outputDir):
    mkDir(outputDir)

  let durArg = if duration > 0: " -max_total_time=" & $duration else: ""
  echo &"{q target}{durArg} -artifact_prefix={q outputDir} {q corpusDir}"
  if execCmd(
      &"{q target}{durArg} -artifact_prefix={q outputDir} {q corpusDir}") != 0:
    return err()
  ok()

proc honggfuzzCompile*(target: string) =
  let honggfuzzOptions = &"-d:llvmFuzzer -d:honggfuzz --noMain {honggfuzzClang}"
  let compileCmd = &"nim c {defaultFlags} {honggfuzzOptions} {q target}"
  exec compileCmd

proc honggfuzzExec*(
    target: string, corpusDir: string,
    outputDir: string, duration = 0): Opt[void] =
  if not dirExists(corpusDir):
    mkDir(corpusDir)

  # TODO:
  # Other useful parameters:
  # --threads|-n VALUE
  #   Number of concurrent fuzzing threads (default: number of CPUs / 2)
  # --workspace|-W VALUE
  #   Workspace directory to save crashes & runtime files (default: '.')
  # --crashdir VALUE
  #   Directory where crashes are saved to (default: workspace directory)
  # --covdir_new VALUE
  #   New coverage (beyond the dry-run fuzzing phase) is written to this separate directory
  # --dict|-w VALUE
  #   Dictionary file. Format:http://llvm.org/docs/LibFuzzer.html#dictionaries
  let durArg = if duration > 0: " --run_time " & $duration else: ""
  echo &"honggfuzz --persistent --exit_upon_crash{durArg} " &
      &"--input {q corpusDir} --crashdir {q outputDir} -- {q target}"
  if execCmd(
      &"honggfuzz --persistent --exit_upon_crash{durArg} " &
      &"--input {q corpusDir} --crashdir {q outputDir} -- {q target}") != 0:
    return err()
  ok()

proc compileFuzzer*(targetPath: string, fuzzer: FuzzingEngine) =
  case fuzzer
  of afl:
    aflCompile(targetPath, clangFast)
  of libFuzzer:
    libFuzzerCompile(targetPath)
  of honggfuzz:
    honggfuzzCompile(targetPath)

proc runFuzzer*(
    targetPath: string, fuzzer: FuzzingEngine,
    corpusDir = "", duration = 0): Opt[void] =
  let
    oid = genOid()
    compiledExe = changeFileExt(targetPath, ExeExt)
    corpusDir = if corpusDir.len > 0: corpusDir
                else: compiledExe & "-" & $fuzzer & "-corpus-" & $oid & "/"

  compileFuzzer(targetPath, fuzzer)

  let
    outputDir = compiledExe & "-" & $fuzzer & "-results-" & $oid & "/"
    res =
      case fuzzer
      of afl:
        aflExec(compiledExe, corpusDir, outputDir, duration)
      of libFuzzer:
        libFuzzerExec(compiledExe, corpusDir, outputDir, duration)
      of honggfuzz:
        honggfuzzExec(compiledExe, corpusDir, outputDir, duration)

  let crashesDir =
    if fuzzer == afl:
      outputDir / "fuzzer01" / "crashes"
    else:
      outputDir
  for path in walkDirRec(crashesDir):
    echo "================================================================================"
    echo "Fuzzer '" & $fuzzer & "' detected crash during " & targetPath & ":"
    echo "- " & path
    echo "--------------------------------------------------------------------------------"
    echo readAllBytes(path).get(@[]).toHex()
    echo "================================================================================"
    return err()

  if res.isErr:
    echo "================================================================================"
    echo "Fuzzer '" & $fuzzer & "' detected problem during " & targetPath &
      " but did not produce any test vectors in " & outputDir
    echo "================================================================================"
  res
