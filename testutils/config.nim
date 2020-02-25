import std/hashes
import std/os
import std/parseopt
import std/strutils
import std/algorithm

const
  Usage = """

  Usage:
  testrunner [options] path
  Run the test(s) specified at path. Will search recursively for test files
  provided path is a directory.
Options:
  --targets:"c c++ js objc" [Not implemented] Run tests for specified targets
  --include:"test1 test2"   Run only listed tests (space/comma seperated)
  --exclude:"test1 test2"   Skip listed tests (space/comma seperated)
  --update                  Rewrite failed tests with new output
  --help                    Display this help and exit

  """.unindent.strip

type
  FlagKind* = enum
    UpdateOutputs = "--update"
    UseThreads = "--threads:on"
    DebugBuild = "--define:debug"
    ReleaseBuild = "--define:release"
    DangerBuild = "--define:danger"
    CpuAffinity = "--affinity"

  TestConfig* = object
    path*: string
    includedTests*: seq[string]
    excludedTests*: seq[string]

    flags*: set[FlagKind]
    # options
    backendNames*: seq[string]

const
  defaultFlags = {UseThreads}
  compilerFlags* = {DebugBuild, ReleaseBuild, DangerBuild, UseThreads}
  # --define:testutilsBackends="cpp js"
  testutilsBackends {.strdefine.} = "c"

proc `backends=`*(config: var TestConfig; inputs: seq[string]) =
  config.backendNames = inputs.sorted

proc `backends=`*(config: var TestConfig; input: string) =
  config.backends = input.split(" ")

proc newTestConfig*(options = defaultFlags): TestConfig =
  result.flags = options
  result.backends = testutilsBackends

proc backends*(config: TestConfig): seq[string] =
  result = config.backendNames

proc hash*(config: TestConfig): Hash =
  var h: Hash = 0
  h = h !& config.backends.hash
  h = h !& hash(ReleaseBuild in config.flags)
  h = h !& hash(DangerBuild in config.flags)
  h = h !& hash(UseThreads notin config.flags)
  result = !$h

proc cache*(config: TestConfig; backend: string): string =
  ## return the path to the nimcache for the given backend and
  ## compile-time flags
  result = getTempDir()
  result = result / "testutils-nimcache-$#-$#" % [ backend,
                                                   $getCurrentProcessId() ]

proc processArguments*(): TestConfig =
  ## consume the arguments supplied to testrunner and yield a computed
  ## configuration object
  var
    opt = initOptParser()

  result = newTestConfig()
  for kind, key, value in opt.getOpt:
    case kind
    of cmdArgument:
      if result.path == "":
        result.path = absolutePath(key)
    of cmdLongOption, cmdShortOption:
      case key.toLowerAscii
      of "help", "h":
        quit(Usage, QuitSuccess)
      of "backend", "backends":
        result.backends = value
      of "release", "danger":
        result.flags.incl ReleaseBuild
        result.flags.incl DangerBuild
      of "nothreads":
        result.flags.excl UseThreads
      of "targets", "t":
        discard # not implemented
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

  if result.path == "":
    quit(Usage)

func shouldSkip*(config: TestConfig, name: string): bool =
  ## true if the named test should be skipped
  if name in config.excludedTests:
    result = true
  elif config.includedTests.len > 0:
    if name notin config.includedTests:
      result = true
