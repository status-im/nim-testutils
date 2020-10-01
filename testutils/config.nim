import
  std/[sequtils, hashes, os, parseopt, strutils, algorithm],
  fuzzing_engines

const
  Usage = """

  Usage:
    ntu COMMAND [options] <path>

  Available commands:

  $ ntu test [options] <path>

  Run the test(s) specified at path. Will search recursively for test files
  provided path is a directory.

  Options:
  --backends:"c cpp js objc"  Run tests for specified targets
  --include:"test1 test2"     Run only listed tests (space/comma separated)
  --exclude:"test1 test2"     Skip listed tests (space/comma separated)
  --update                    Rewrite failed tests with new output
  --sort:"source,test"        Sort the tests by program and/or test mtime
  --reverse                   Reverse the order of tests
  --random                    Shuffle the order of tests
  --help                      Display this help and exit

  $ ntu fuzz [options] <module>

  Start a fuzzing test with a Nim module based on testutils/fuzzing.

  Options:
  --fuzzer:libFuzzer         The fuzzing engine to use.
                             Possible values: libFuzzer, honggfuzz, afl
  --corpus:<path>            A directory with initial input cases

  """.unindent.strip

type
  FlagKind* = enum
    UpdateOutputs = "--update"
    UseThreads = "--threads:on"
    DebugBuild = "--define:debug"
    ReleaseBuild = "--define:release"
    DangerBuild = "--define:danger"
    CpuAffinity = "--affinity"

  SortBy* {.pure.} = enum
    Random   = "random"
    Source   = "source"
    Test     = "test"
    Reverse  = "reverse"

  Command* = enum
    noCommand
    test
    fuzz

  TestConfig* = object
    case cmd*: Command
    of test:
      path*: string
      includedTests*: seq[string]
      excludedTests*: seq[string]

      flags*: set[FlagKind]
      # options
      backendNames*: seq[string]
      orderBy*: set[SortBy]
    of fuzz:
      fuzzer*: FuzzingEngine
      corpusDir*: string
      target*: string
    of noCommand:
      discard

const
  defaultFlags = {UseThreads}
  compilerFlags* = {DebugBuild, ReleaseBuild, DangerBuild, UseThreads}
  # --define:testutilsBackends="cpp js"
  testutilsBackends* {.strdefine.} = "c"
  defaultSort = {Source, Reverse}

proc `backends=`*(config: var TestConfig; inputs: seq[string]) =
  config.backendNames = inputs.sorted

proc `backends=`*(config: var TestConfig; input: string) =
  config.backends = input.split(" ")

proc backends*(config: TestConfig): seq[string] =
  result = config.backendNames

proc hash*(config: TestConfig): Hash =
  var h: Hash = 0
  h = h !& config.backends.hash
  h = h !& hash(ReleaseBuild in config.flags)
  h = h !& hash(DangerBuild in config.flags)
  h = h !& hash(UseThreads notin config.flags)
  result = !$h

proc compilationFlags*(config: TestConfig): string =
  for flag in compilerFlags * config.flags:
    result &= " " & $flag

proc cache*(config: TestConfig; backend: string): string =
  ## return the path to the nimcache for the given backend and
  ## compile-time flags
  result = getTempDir()
  result = result / "testutils-nimcache-$#-$#" % [ backend,
                                                   $getCurrentProcessId() ]

proc processArguments*(): TestConfig =
  ## consume the arguments supplied to ntu and yield a computed
  ## configuration object
  var
    opt = initOptParser()

  func toSet[SortBy](list: seq[SortBy]): set[SortBy] =
    for element in list.items:
      result.incl element

  for kind, key, value in opt.getOpt:
    if result.cmd == noCommand:
      doAssert kind == cmdArgument
      result.cmd = parseEnum[Command](key)
      if result.cmd == test:
        result.flags = defaultFlags
        result.backends = testutilsBackends
        result.orderBy = defaultSort
      continue

    case result.cmd
    of test:
      case kind
      of cmdArgument:
        if result.path == "":
          result.path = absolutePath(key)
      of cmdLongOption, cmdShortOption:
        case key.toLowerAscii
        of "help", "h":
          quit(Usage, QuitSuccess)
        of "reverse", "random":
          let
            flag = parseEnum[SortBy](value)
          if flag in result.orderBy:
            result.orderBy.excl flag
          else:
            result.orderBy.incl flag
        of "sort":
          result.orderBy = toSet value.split(",").mapIt parseEnum[SortBy](it)
        of "backend", "backends", "targets", "t":
          result.backends = value
        of "release", "danger":
          result.flags.incl ReleaseBuild
          result.flags.incl DangerBuild
        of "nothreads":
          result.flags.excl UseThreads
        of "update":
          result.flags.incl UpdateOutputs
        of "include":
          result.includedTests.add value.split(Whitespace + {','})
        of "exclude":
          result.excludedTests.add value.split(Whitespace + {','})
        else:
          quit(Usage)
      of cmdEnd:
        quit(Usage)

    of fuzz:
      case kind
      of cmdArgument:
        result.target = key
      of cmdLongOption, cmdShortOption:
        case key.toLowerAscii:
        of "f", "fuzzer":
          result.fuzzer = parseEnum[FuzzingEngine](value)
        of "c", "corpus":
          result.corpusDir = absolutePath(value)
        else:
          quit(Usage)
      else:
        echo "got kind ", kind
        quit(Usage)

    of noCommand:
      discard

  case result.cmd
  of test:
    if result.path == "":
      quit(Usage)
  of fuzz:
    if result.target == "":
      quit(Usage)
  else:
    quit(Usage)

func shouldSkip*(config: TestConfig, name: string): bool =
  ## true if the named test should be skipped
  if name in config.excludedTests:
    result = true
  elif config.includedTests.len > 0:
    if name notin config.includedTests:
      result = true
