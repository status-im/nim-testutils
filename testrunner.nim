import std/strtabs
import std/os
import std/osproc
import std/strutils
import std/terminal
import std/times
import std/pegs

import testutils/spec
import testutils/config
import testutils/helpers

##[

The runner will look recursively for all *.test files at given path. A
test file should have at minimum a program name. This is the name of the
nim source minus the .nim extension)

]##


# Code is here and there influenced by nim testament tester and unittest
# module.

const
  # defaultOptions = "--verbosity:1 --warnings:off --hint[Processing]:off " &
  #                  "--hint[Conf]:off --hint[XDeclaredButNotUsed]:off " &
  #                  "--hint[Link]:off --hint[Pattern]:off"
  defaultOptions = "--verbosity:1 --warnings:on "
  🎉 = -1

type
  TestStatus* = enum
    OK
    FAILED
    SKIPPED
    INVALID

  #[
   If needed, pass more info to the logresult via a TestResult object
   TestResult = object
     status: TestStatus
     compileTime: float
     fileSize: uint
  ]#

  ThreadPayload = object
    core: int
    spec: TestSpec
    recurse: bool

  TestThread = Thread[ThreadPayload]
  TestError* = enum
    SourceFileNotFound
    ExeFileNotFound
    OutputFileNotFound
    CompileError
    RuntimeError
    OutputsDiffer
    FileSizeTooLarge
    CompileErrorDiffers

proc logFailure(test: TestSpec; error: TestError;
                data: varargs[string] = [""]) =
  case error
  of SourceFileNotFound:
    styledEcho(fgYellow, styleBright, "source file not found: ",
               resetStyle, test.program.addFileExt(".nim"))
  of ExeFileNotFound:
    styledEcho(fgYellow, styleBright, "file not found: ",
               resetStyle, test.binary)
  of OutputFileNotFound:
    styledEcho(fgYellow, styleBright, "file not found: ",
               resetStyle, data[0])
  of CompileError:
    styledEcho(fgYellow, styleBright, "compile error:\p",
               resetStyle, data[0])
  of RuntimeError:
    styledEcho(fgYellow, styleBright, "runtime error:\p",
               resetStyle, data[0])
  of OutputsDiffer:
    styledEcho(fgYellow, styleBright, "outputs are different:\p",
               resetStyle,"Expected output to $#:\p$#" % [data[0], data[1]],
                          "Resulted output to $#:\p$#" % [data[0], data[2]])
  of FileSizeTooLarge:
    styledEcho(fgYellow, styleBright, "file size is too large: ",
               resetStyle, data[0] & " > " & $test.maxSize)
  of CompileErrorDiffers:
    styledEcho(fgYellow, styleBright, "compile error is different:\p",
               resetStyle, data[0])

  styledEcho(fgCyan, styleBright, "command: ", resetStyle,
             "nim c $#$#$#" % [defaultOptions, test.flags,
                                 test.program.addFileExt(".nim")])

template withinDir(dir: string; body: untyped): untyped =
  let
    cwd = getCurrentDir()
  setCurrentDir(dir)
  try:
    body
  finally:
    setCurrentDir(cwd)

proc logResult(testName: string, status: TestStatus, time: float) =
  var color = case status
              of OK: fgGreen
              of FAILED: fgRed
              of SKIPPED: fgYellow
              of INVALID: fgRed
  styledEcho(styleBright, color, "[", $status, "] ",
             resetStyle, testName,
             fgYellow, " ", time.formatFloat(ffDecimal, 3), " s")

template time(duration, body): untyped =
  let t0 = epochTime()
  block:
    body
  duration =  epochTime() - t0

proc composeOutputs(test: TestSpec, stdout: string): TestOutputs =
  result = newTestOutputs()
  for name, expected in test.outputs.pairs:
    if name == "stdout":
      result[name] = stdout
    else:
      if not existsFile(name):
        continue
      result[name] = readFile(name)
      removeFile(name)

proc cmpOutputs(test: TestSpec, outputs: TestOutputs): TestStatus =
  result = OK
  for name, expected in test.outputs.pairs:
    if name notin outputs:
      logFailure(test, OutputFileNotFound, name)
      result = FAILED
      continue

    let
      testOutput = outputs[name]

    # Would be nice to do a real diff here instead of simple compare
    if test.timestampPeg.len > 0:
      if not cmpIgnorePegs(testOutput, expected,
                           peg(test.timestampPeg), pegXid):
        logFailure(test, OutputsDiffer, name, expected, testOutput)
        result = FAILED
    else:
      if not cmpIgnoreDefaultTimestamps(testOutput, expected):
        logFailure(test, OutputsDiffer, name, expected, testOutput)
        result = FAILED

proc compile(test: TestSpec): TestStatus =
  let
    source = test.config.path / test.program.addFileExt(".nim")

  if not existsFile(source):
    logFailure(test, SourceFileNotFound)
    result = FAILED
    return

  for backend in test.config.backends.items:
    let
      binary = test.binary(backend)
    var
      cmd = findExe("nim")
    cmd &= " " & backend
    cmd &= " --nimcache:" & test.config.cache(backend)
    cmd &= " --out:" & binary
    cmd &= " " & defaultOptions
    cmd &= " " & test.flags
    cmd &= " " & source.quoteShell
    var
      c = parseCmdLine(cmd)
      p = startProcess(command=c[0], args=c[1.. ^1],
                       options={poStdErrToStdOut, poUsePath})

    try:
      let
        compileInfo = parseCompileStream(p, p.outputStream)

      if compileInfo.exitCode != 0:
        if test.compileError.len == 0:
          logFailure(test, CompileError, compileInfo.fullMsg)
          result = FAILED
          break
        else:
          if test.compileError == compileInfo.msg and
             (test.errorFile.len == 0 or test.errorFile == compileInfo.errorFile) and
             (test.errorLine == 0 or test.errorLine == compileInfo.errorLine) and
             (test.errorColumn == 0 or test.errorColumn == compileInfo.errorColumn):
            result = OK
          else:
            logFailure(test, CompileErrorDiffers, compileInfo.fullMsg)
            result = FAILED
            break

      # Lets also check file size here as it kinda belongs to the compilation result
      if test.maxSize != 0:
        var size = getFileSize(binary)
        if size > test.maxSize:
          logFailure(test, FileSizeTooLarge, $size)
          result = FAILED
          break

      result = OK
    finally:
      close(p)

proc threadedExecute(payload: ThreadPayload) {.thread.}

proc spawnTest(child: var Thread[ThreadPayload]; test: TestSpec;
               core: int): bool =
  assert core >= 0
  child.createThread(threadedExecute,
                     ThreadPayload(core: core, spec: test))
  if CpuAffinity in test.config.flags:
    if core < countProcessors():
      child.pinToCpu core
      result = true

proc execute(test: TestSpec): TestStatus =
  var
    cmd = test.binary
  # output the test stage if necessary
  if test.stage.len > 0:
    echo 20.spaces & test.stage

  if not existsFile(cmd):
    result = FAILED
    logFailure(test, ExeFileNotFound)
  else:
    withinDir parentDir(cmd):
      cmd = cmd.quoteShell & " " & test.args
      let
        (output, exitCode) = execCmdEx(cmd)
      if exitCode != 0:
        # parseExecuteOutput() # Need to parse the run time failures?
        logFailure(test, RuntimeError, output)
        result = FAILED
      else:
        let
          outputs = test.composeOutputs(output)
        result = test.cmpOutputs(outputs)
        # perform an update of the testfile if requested and required
        if UpdateOutputs in test.config.flags and result == FAILED:
          test.rewriteTestFile(outputs)
          # we'll call this a `skip` because it's not strictly a failure
          # and we want any dependent testing to proceed as usual.
          result = SKIPPED

proc executeTestChain(test: TestSpec; core: int): TestStatus =
  # don't try this in python
  when compileOption("threads"):
    try:
      var
        thread: TestThread
      assert core == 🎉
      discard thread.spawnTest(test, core + 1)
      thread.joinThreads
    except:
      # any thread(?) exception is a failure
      result = FAILED
  else:
    # unthreaded serial test execution
    result = test.execute
    if test.child != nil and result in {OK, SKIPPED}:
      result = test.child.execute

proc threadedExecute(payload: ThreadPayload) {.thread.} =
  var
    result = FAILED
  if payload.spec.child == nil:
    {.gcsafe.}:
      result = payload.spec.execute
  else:
    try:
      var
        child: TestThread
      discard child.spawnTest(payload.spec.child, payload.core + 1)
      {.gcsafe.}:
        result = payload.spec.execute
      child.joinThreads
    except:
      result = FAILED
  if result == FAILED:
    raise newException(Exception, "i'm a terrible person")

proc scanTestPath(path: string): seq[string] =
  if fileExists(path):
    result.add path
  else:
    for file in walkDirRec path:
      if file.endsWith ".test":
        result.add file

proc test(config: TestConfig, testPath: string): TestStatus =
  var
    test: TestSpec
    duration: float

  time duration:
    test = parseTestFile(testPath, config)
    for flag in config.flags * compilerFlags:
      test.flags &= " " & $flag

    if test.program.len == 0: # a program name is bare minimum of a test file
      result = INVALID
      break

    if test.skip or hostOS notin test.os or config.shouldSkip(test.name):
      result = SKIPPED
      break

    result = test.compile()
    if result != OK or test.compileError.len > 0:
      break

    result = test.executeTestChain(🎉)  # get this party started
    try:
      # this may fail in 64-bit AppVeyor images with "The process cannot
      # access the file because it is being used by another process.
      # [OSError]"
      removeFile(test.binary)
    except CatchableError as e:
      echo e.msg

  logResult(test.name, result, duration)

proc main() =
  let
    config = processArguments()
    testFiles = scanTestPath(config.path)
  var
    successful, skipped = 0

  if testFiles.len == 0:
    styledEcho(styleBright, "No test files found")
    program_result = 1
  else:
    for testFile in testFiles:
      # Here we could do multithread or multiprocess but we will have to
      # work with different nim caches per test and also the executables
      # have to be in a unique location as several tests can use the same
      # source.
      var result = test(config, testFile)
      if result == OK:
        successful += 1
      elif result == SKIPPED:
        skipped += 1

    styledEcho(styleBright, "Finished run: $#/$# tests successful" %
                            [$successful, $(testFiles.len - skipped)])
    program_result = testFiles.len - successful - skipped

when isMainModule:
  main()
