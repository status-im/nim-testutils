import std/os
import std/parsecfg
import std/strutils
import std/streams

const
  DefaultOses = @["linux", "macosx", "windows"]

type
  TestSpec* = object
    name*: string
    skip*: bool
    program*: string
    flags*: string
    outputs*: seq[tuple[name: string, expectedOutput: string]]
    timestampPeg*: string
    errorMsg*: string
    maxSize*: int64
    compileError*: string
    errorFile*: string
    errorLine*: int
    errorColumn*: int
    os*: seq[string]

proc defaults(spec: var TestSpec) =
  ## assert some default values for a given spec
  spec.os = DefaultOses

proc consumeConfigEvent(spec: var TestSpec; event: CfgEvent) =
  ## parse a specification supplied prior to any sections
  case event.key
  of "program":
    spec.program = event.value
  of "timestamp_peg":
    spec.timestampPeg = event.value
  of "max_size":
    if event.value[0].isDigit:
      spec.maxSize = parseInt(event.value)
    else:
      # XXX crash?
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

proc parseTestFile*(filePath: string): TestSpec =
  ## parse a test input file into a spec
  result.defaults
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
          if e.section.cmpIgnoreCase("Output") == 0:
            outputSection = true
        of cfgKeyValuePair:
          if outputSection:
            result.outputs.add((e.key, e.value))
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
      # XXX crash?
      echo "Parsing error: no program value"
