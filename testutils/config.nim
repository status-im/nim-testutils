import std/parseopt
import std/strutils

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
  TestConfig* = object
    path*: string
    update*: bool
    includedTests*: seq[string]
    excludedTests*: seq[string]
    releaseBuild*: bool
    noThreads*: bool

proc processArguments*(): TestConfig =
  ## consume the arguments supplied to testrunner and yield a computed
  ## configuration object
  var
    opt = initOptParser()

  for kind, key, value in opt.getOpt:
    case kind
    of cmdArgument:
      if result.path == "":
        result.path = key
    of cmdLongOption, cmdShortOption:
      case key.toLowerAscii
      of "help", "h":
        quit(Usage, QuitSuccess)
      of "release":
        result.releaseBuild = true
      of "nothreads":
        result.noThreads = true
      of "targets", "t":
        discard # not implemented
      of "update":
        result.update = true
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
