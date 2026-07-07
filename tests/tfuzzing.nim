import std/[oids, os, osproc], unittest2, ../testutils/fuzzing_engines

const BugSrc = """
import testutils/fuzzing

test:
  doAssert payload.len < 4

  if payload.len > 2:
    raise (ref ValueError)(msg: "Too long")

  if payload.len > 1:
    echo (cast[ptr int](1))[]
"""

suite "fuzzing engines":
  for fuzzer in FuzzingEngine:
    let path = getTempDir() / "tfuzzing-" & $genOid()
    doAssert not existsOrCreateDir(path)
    defer: removeDir(path)

    (path / "nim.cfg").writeFile(
      "--nimcache:\"" & (path / "nimcache") & "\"\n" &
      "--path:\"" & currentSourcePath.parentDir.parentDir & "\"\n")

    let targetPath = path / "src.nim"
    targetPath.writeFile(BugSrc)
    targetPath.compileFuzzer(fuzzer)
    let compiledExe = targetPath.changeFileExt(ExeExt)
    doAssert compiledExe.fileExists

    test "Success reporting [" & $fuzzer & "]":
      let inputPath = path / "good.txt"
      inputPath.writeFile "A"
      check execCmd("\"" & compiledExe & "\" \"" & inputPath & "\"") == 0

    test "Sigal reporting [" & $fuzzer & "]":
      let inputPath = path / "bad_signal.txt"
      inputPath.writeFile "AB"
      check execCmd("\"" & compiledExe & "\" \"" & inputPath & "\"") != 0

    test "Error reporting [" & $fuzzer & "]":
      let inputPath = path / "bad_error.txt"
      inputPath.writeFile "ABC"
      check execCmd("\"" & compiledExe & "\" \"" & inputPath & "\"") != 0

    test "Defect reporting [" & $fuzzer & "]":
      let inputPath = path / "bad_defect.txt"
      inputPath.writeFile "ABCD"
      check execCmd("\"" & compiledExe & "\" \"" & inputPath & "\"") != 0
