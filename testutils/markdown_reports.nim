import algorithm, sequtils, strutils, strformat, tables

type
  Status* {.pure.} = enum OK, Fail, Skip

proc generateReport*(title: string; data: OrderedTable[string, OrderedTable[string, Status]];
                     width = 63) =
  ## Generate a markdown report from test data and write it to a file with the given title.
  ## The table keys are sections, and the nested tables map tests to statuses.
  let symbol: array[Status, string] = ["+", "-", " "]
  var raw = ""
  var okCountTotal = 0
  var failCountTotal = 0
  var skipCountTotal = 0
  raw.add(title & "\n")
  raw.add("===\n")
  for section, statuses in data:
    raw.add("## " & section & "\n")
    raw.add("```diff\n")
    var sortedStatuses = statuses
    sortedStatuses.sort do (a: (string, Status), b: (string, Status)) -> int:
      cmp(a[0], b[0])
    var okCount = 0
    var failCount = 0
    var skipCount = 0
    for name, final in sortedStatuses:
      let padded = alignLeft(name, width)
      raw.add(&"{symbol[final]} {padded[0 ..< width]} {$final}\n")
      case final
      of Status.OK: okCount += 1
      of Status.Fail: failCount += 1
      of Status.Skip: skipCount += 1
    raw.add("```\n")
    let sum = okCount + failCount + skipCount
    okCountTotal += okCount
    failCountTotal += failCount
    skipCountTotal += skipCount
    raw.add("OK: $1/$4 Fail: $2/$4 Skip: $3/$4\n" % [$okCount, $failCount, $skipCount, $sum])

  let sumTotal = okCountTotal + failCountTotal + skipCountTotal
  raw.add("\n---TOTAL---\n")
  raw.add("OK: $1/$4 Fail: $2/$4 Skip: $3/$4\n" % [$okCountTotal, $failCountTotal,
                                                   $skipCountTotal, $sumTotal])
  writeFile(title & ".md", raw)
