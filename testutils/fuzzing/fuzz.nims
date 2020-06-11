import ./fuzz_helpers

# TODO: get this some nice cmd line options when confutils works for nimscript
# or if we want to put this in a nim application instead of script

if paramCount() < 3:
  echo "Usage: nim fuzz.nims FUZZER TARGET [CORPUS_DIR]"
  echo "Fuzzer options are afl or libFuzzer"
  quit 1

let
  fuzzer = paramStr(2)
  targetPath = paramStr(3)

let corpusDir = if paramCount() == 4: paramStr(4)
                else: ""

if corpusDir != "" and not dirExists(corpusDir):
  echo "Corpus dir does not exist"
  quit 1

if not fileExists(targetPath):
  echo "Target file does not exist"
  quit 1

case fuzzer
of "afl":
  runFuzzer(targetPath, afl, corpusDir)
of "libFuzzer":
  runFuzzer(targetPath, libFuzzer, corpusDir)
of "honggfuzz":
  runFuzzer(targetPath, honggfuzz, corpusDir)

else:
  echo "Invalid fuzzer option: ", fuzzer
  echo "Fuzzer options are afl or libFuzzer"
  quit 1
