import strformat
import os except dirExists

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
    var curDir = getCurrentDir()
    try:
      setCurrentDir(dir)
      body
    finally:
      setCurrentDir(curDir)

template q(x: string): string =
  quoteShell x

proc aflCompile*(target: string, c: AflCompiler) =
  let aflOptions = &"-d:afl -d:noSignalHandler {$c}"
  let compileCmd = &"nim c {defaultFlags} {aflOptions} {q target}"
  exec compileCmd

proc aflExec*(target: string,
              inputDir: string,
              resultsDir: string,
              cleanStart = false) =
  let exe = target.addFileExt(ExeExt)
  if not dirExists(inputDir):
    # create a input dir with one 0 file for afl
    mkDir(inputDir)
    # TODO: improve
    withDir inputDir: exec "echo '0' > test"

  var fuzzCmd: string
  # if there is an output dir already, continue fuzzing from previous run
  if (not dirExists(resultsDir)) or cleanStart:
    fuzzCmd = &"afl-fuzz -i {q inputDir} -o {q resultsDir} -M fuzzer01 -- {q exe}"
  else:
    fuzzCmd = &"afl-fuzz -i - -o {q resultsDir} -M fuzzer01 -- {q exe}"
  exec fuzzCmd

proc libFuzzerCompile*(target: string) =
  let libFuzzerOptions = &"-d:llvmFuzzer --noMain {libFuzzerClang}"
  let compileCmd = &"nim c {defaultFlags} {libFuzzerOptions} {q target}"
  exec compileCmd

proc libFuzzerExec*(target: string, corpusDir: string) =
  if not dirExists(corpusDir):
    # libFuzzer is OK when starting with empty corpus dir
    mkDir(corpusDir)

  exec &"{q target} {q corpusDir}"

proc honggfuzzCompile*(target: string) =
  let honggfuzzOptions = &"-d:llvmFuzzer --noMain {honggfuzzClang}"
  let compileCmd = &"nim c {defaultFlags} {honggfuzzOptions} {q target}"
  exec compileCmd

proc honggfuzzExec*(target: string, corpusDir: string, outputDir: string) =
  #if not dirExists(corpusDir):
  #  # libFuzzer is OK when starting with empty corpus dir
  #  mkDir(corpusDir)

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
  exec &"honggfuzz --persistent --input {q corpusDir} --output {q outputDir} -- {q target}"

proc runFuzzer*(targetPath: string, fuzzer: FuzzingEngine, corpusDir: string) =
  let
    (path, target, ext) = splitFile(targetPath)
    compiledExe = addFileExt(path / target, ExeExt)
    corpusDir = if corpusDir.len > 0: corpusDir
                else: path / "corpus"

  case fuzzer
  of afl:
    aflCompile(targetPath, clang)
    aflExec(compiledExe, corpusDir, path / "results")

  of libFuzzer:
    libFuzzerCompile(targetPath)
    libFuzzerExec(compiledExe, corpusDir)

  of honggfuzz:
    honggfuzzCompile(targetPath)
    honggfuzzExec(compiledExe, corpusDir, path / "results")

