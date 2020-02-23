import std/os
import std/parsecfg
import std/strutils
import std/streams
import std/strtabs

import testutils/config

const
  DefaultOses = @["linux", "macosx", "windows"]

type
  TestOutputs* = StringTableRef
  TestSpec* = ref object
    section*: string
    args*: string
    config*: TestConfig
    path*: string
    name*: string
    skip*: bool
    program*: string
    flags*: string
    preamble*: seq[tuple[key: string; value: string]]
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

proc newTestOutputs*(): StringTableRef =
  result = newStringTable(mode = modeStyleInsensitive)

proc clone*(spec: TestSpec): TestSpec =
  result = new(TestSpec)
  result[] = spec[]
  result.outputs = newTestOutputs()
  result.args = ""
  result.child = spec

proc binary*(spec: TestSpec): string =
  ## the output binary (execution input) of the test
  result = spec.path.changeFileExt("").addFileExt(ExeExt)

proc defaults(spec: var TestSpec) =
  ## assert some default values for a given spec
  spec.os = DefaultOses
  spec.outputs = newTestOutputs()

proc consumeConfigEvent(spec: var TestSpec; event: CfgEvent) =
  ## parse a specification supplied prior to any sections

  # save the key/value pair in case we need to write out the test file
  spec.preamble.add (key: event.key, value: event.value)
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
  else:
    let
      flag = "--define:$#:$#" % [event.key, event.value]
    spec.flags.add flag.quoteShell & " "

proc rewriteTestFile*(spec: TestSpec) =
  ## rewrite a test file with updated outputs after having run the tests
  var
    test = loadConfig(spec.path)
  if spec.args != "":
    test.setSectionKey(spec.section, "args", spec.args)
  for name, expected in spec.outputs.pairs:
    test.setSectionKey(spec.section, name, expected)
  test.writeConfig(spec.path)

proc parseTestFile*(filePath: string; config: TestConfig): TestSpec =
  ## parse a test input file into a spec
  result = new(TestSpec)
  result.defaults
  result.path = absolutePath(filePath)
  result.config = config
  result.name = splitFile(filePath).name
  block:
    var
      f = newFileStream(filePath, fmRead)
    if f == nil:
      # XXX crash?
      echo "Parsing error: cannot open " & filePath
      break

    var
      outputSection = false
      p: CfgParser
    p.open(f, filePath)
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
          if e.section.cmpIgnoreCase("Output") == 0:
            outputSection = true
            result.section = e.section
        of cfgKeyValuePair:
          if outputSection:
            if e.key.cmpIgnoreStyle("args") == 0:
              # if this is the first args statement in the test,
              # then we'll just use it.  otherwise, we'll clone
              # ourselves and link to the test behind us, first.
              if result.args.len != 0:
                # create our parent; the eternal chain
                result = result.clone
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
            result.flags &= ("--$#:$#" % [e.key, e.value]).quoteShell & " "
    finally:
      close p
    if result.program == "":
      # we catch this in testrunner and crash there if needed
      echo "Parsing error: no program value"
