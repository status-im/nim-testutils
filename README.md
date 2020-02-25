# Testrunner [![Build Status](https://travis-ci.org/disruptek/testutils.svg?branch=master)](https://travis-ci.org/disruptek/testutils)

## Usage

Command syntax:

```sh
testrunner [options] path
Run the test(s) specified at path. Will search recursively for test files
provided path is a directory.
Options:
--targets:"c c++ js objc" [Not implemented] Run tests for specified targets
--include:"test1 test2"   Run only listed tests (space/comma seperated)
--exclude:"test1 test2"   Skip listed tests (space/comma seperated)
--update                  Rewrite failed tests with new output
--help                    Display this help and exit
```

The runner will look recursively for all `*.test` files at given path.

## Test file options

The test files follow the configuration file syntax (similar as `.ini`), see
also [nim parsecfg module](https://nim-lang.org/docs/parsecfg.html).

### Required

- **program**: A test file should have at minimum a program name. This is the name
of the nim source minus the `.nim` extension.

### Optional

- **max_size**: To check the maximum size of the binary, in bytes.
- **timestamp_peg**: If you don't want to use the default timestamps, you can define
your own timestamp peg here.
- **compile_error**: When expecting a compilation failure, the error message that
should be expected.
- **error_file**: When expecting a compilation failure, the source file where the
error should occur.
- **os**: Space and/or comma separated list of operating systems for which the
test should be run. Defaults to `"linux, macosx, windows"`. Tests meant for a
different OS than the host will be marked as `SKIPPED`.
- **--skip**: This will simply skip the test (will not be marked as failure).

### Forwarded Options
Any other options or key-value pairs will be forwarded to the nim compiler.

A **key-value** pair will become a conditional symbol + value (`-d:SYMBOL(:VAL)`)
for the nim compiler, e.g. for `-d:chronicles_timestamps="UnixTime"` the test
file requires:
```ini
chronicles_timestamps="UnixTime"
```
If only a key is given, an empty value will be forwarded.

An **option** will be forwarded as is to the nim compiler, e.g. this can be
added in a test file:
```ini
--opt:size
```

### Verifying Expected Output

For outputs to be compared, the output string should be set to the output name
(`stdout` or _filename_) from within an _Output_ section:

```ini
[Output]
stdout="""expected stdout output"""
file.log="""expected file output"""
```

Triple quotes can be used for multiple lines.

### Supplying Command-line Arguments

Optionally specify command-line arguments as an escaped string in the following
syntax inside any _Output_ section:

```ini
[Output]
args = "--title \"useful title\""
```

### Multiple Invocations

Multiple _Output_ sections denote multiple test program invocations. Any
failure of the test program to match its expected outputs will short-circuit
and fail the test.

```ini
[Output]
stdout = ""
args = "--no-output"

[Output_newlines]
stdout = "\n\n"
args = "--newlines"
```

### Updating Expected Outputs

Pass the `--update` argument to `testrunner` to rewrite any failing test with
the new outputs of the test.

### Concurrent Test Execution

Unless you pass `--nothreads` to `testrunner`, it will run multiple test
invocations defined in each test file simultaneously. You can also specify
`nothreads` or `threads` in the _preamble_.

```ini
nothreads = true

[Output_1st_serial]
args = "--first"

[Output_2nd_serial]
args = "--second"
```

### CPU Affinity

Specify `affinity` to clamp the first _N_ concurrent test threads to the first
_N_ CPU cores.

```ini
affinity = true

[Output_1st_core]
args = "--first"

[Output_2nd_core]
args = "--second"
```

### More Examples

See `chonicles`, where `testutils` was born:
- https://github.com/status-im/nim-chronicles/tree/master/tests


## License
Apache2 or MIT
