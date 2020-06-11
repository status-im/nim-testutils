import std/hashes
import std/os
import std/parsecfg
import std/strutils
import std/streams
import std/strtabs

import testutils/config

type
  TestOutputs* = StringTableRef
  TestSpec* = ref object
    section*: string
    args*: string
    config*: TestConfig
    path*: string
    pathComponents*: tuple[dir, name, ext: string]
    skip*: bool
    program*: string
    flags*: string
    outputs*: TestOutputs
    timestampPeg*: string
    errorMsg*: string
    maxSize*: int64
    compileError*: string
    errorFile*: string
    errorLine*: int
    errorColumn*: int
    os*: seq[string]
    child*: TestSpec

const
  DefaultOses = @["linux", "macosx", "windows"]

proc hash*(spec: TestSpec): Hash =
  var h: Hash = 0
  h = h !& spec.config.hash
  h = h !& spec.flags.hash
  h = h !& spec.os.hash
  result = !$h

proc binaryHash*(spec: TestSpec; backend: string): Hash =
  ## hash the backend, any compilation flags, and defines, etc.
  var h: Hash = 0
  h = h !& backend.hash
  h = h !& spec.os.hash
  h = h !& hash(spec.config.flags * compilerFlags)
  h = h !& hash(spec.flags)
  h = h !& spec.program.hash
  h = h !& spec.pathComponents.name.hash
  result = !$h

template name*(spec: TestSpec): string =
  spec.pathComponents.name

proc newTestOutputs*(): StringTableRef =
  result = newStringTable(mode = modeStyleInsensitive)

proc clone*(spec: TestSpec): TestSpec =
  ## create the parent of this test and set the child reference appropriately
  result = new(TestSpec)
  result[] = spec[]
  result.outputs = newTestOutputs()
  result.args = ""
  result.child = spec

func stage*(spec: TestSpec): string =
  ## the name of the output section for the test
  ## Output_test_section_name
  let
    # @["", "test_section_name"]
    names = spec.section.split("Output")
  result = names[^1].replace("_", " ").strip

proc source*(spec: TestSpec): string =
  result = absolutePath(spec.pathComponents.dir / spec.program.addFileExt(".nim"))

proc binary*(spec: TestSpec; backend: string): string =
  ## some day this will make more sense
  result = (spec.pathComponents.dir / spec.pathComponents.name).addFileExt(ExeExt)
  if dirExists(result):
    result = result.addFileExt("out")

proc binary*(spec: TestSpec): string {.deprecated.} =
  ## the output binary (execution input) of the test
  result = spec.binary("c")

iterator binaries*(spec: TestSpec): string =
  ## enumerate binary targets for each backend specified by the test
  for backend in spec.config.backends.items:
    yield spec.binary(backend)

proc defaults(spec: var TestSpec) =
  ## assert some default values for a given spec
  spec.os = DefaultOses
  spec.outputs = newTestOutputs()

proc consumeConfigEvent(spec: var TestSpec; event: CfgEvent) =
  ## parse a specification supplied prior to any sections
  case event.key
  of "program":
    spec.program = event.value
  of "timestamp_peg":
    spec.timestampPeg = event.value
  of "max_size":
    try:
      spec.maxSize = parseInt(event.value)
    except ValueError:
      echo "Parsing warning: value of " & event.key &
           " is not a number (value = " & event.value & ")."
  of "compile_error":
    spec.compileError = event.value
  of "error_file":
    spec.errorFile = event.value
  of "os":
    spec.os = event.value.normalize.split({','} + Whitespace)
  of "affinity":
    spec.config.flags.incl CpuAffinity
  of "threads":
    spec.config.flags.incl UseThreads
  of "nothreads":
    spec.config.flags.excl UseThreads
  of "release", "danger", "debug":
    spec.config.flags.incl parseEnum[FlagKind]("--define:" & event.key)
  else:
    let
      flag = "--define:$#:$#" % [event.key, event.value]
    spec.flags.add flag.quoteShell & " "

proc rewriteTestFile*(spec: TestSpec; outputs: TestOutputs) =
  ## rewrite a test file with updated outputs after having run the tests
  var
    test = loadConfig(spec.path)
  # take the opportunity to update an args statement if necessary
  if spec.args != "":
    test.setSectionKey(spec.section, "args", spec.args)
  else:
    test.delSectionKey(spec.section, "args")
  # delete the old test outputs for completeness
  for name, expected in spec.outputs.pairs:
    test.delSectionKey(spec.section, name)
  # add the new test outputs
  for name, expected in outputs.pairs:
    test.setSectionKey(spec.section, name, expected)
  test.writeConfig(spec.path)

proc parseTestFile*(config: TestConfig; filePath: string): TestSpec =
  ## parse a test input file into a spec
  result = new(TestSpec)
  result.defaults
  result.path = absolutePath(filePath)
  result.pathComponents = splitFile result.path
  result.config = config
  block:
    var
      f = newFileStream(result.path, fmRead)
    if f == nil:
      # XXX crash?
      echo "Parsing error: cannot open " & result.path
      break

    var
      outputSection = false
      p: CfgParser
    p.open(f, result.path)
    try:
      while true:
        var e = next(p)
        case e.kind
        of cfgEof:
          break
        of cfgError:
          # XXX crash?
          echo "Parsing warning:" & e.msg
        of cfgSectionStart:
          # starts with Output
          if e.section[0..len"Output"-1].cmpIgnoreCase("Output") == 0:
            if outputSection:
              # create our parent; the eternal chain
              result = result.clone
            outputSection = true
            result.section = e.section
        of cfgKeyValuePair:
          if outputSection:
            if e.key.cmpIgnoreStyle("args") == 0:
              result.args = e.value
            else:
              result.outputs[e.key] = e.value
          else:
            result.consumeConfigEvent(e)
        of cfgOption:
          case e.key
          of "skip":
            result.skip = true
          else:
            # this for for, eg. --opt:size
            result.flags &= ("--$#:$#" % [e.key, e.value]).quoteShell & " "
    finally:
      close p

    # we catch this in ntu and crash there if needed
    if result.program == "":
      echo "Parsing error: no program value"
