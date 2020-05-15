# Fuzzing on Windows

This is a supplemental guide to fuzzing on windows platform.

## Windows Subsystem for Linux(WSL) Ubuntu 20.04

Grab Ubuntu from Windows Store and install libFuzzer and afl.
But don't forget to update or upgrade the database if you start with a 'blank' Ubuntu.

```sh
sudo apt update
sudo apt upgrade
```

### Install clang and libFuzzer

Pick your clang version: 9, 10, or 11. In this example I'll use clang-10.

```sh
sudo apt install build-essential
sudo apt-get install clang-10 lldb-10 lld-10
sudo apt-get install libfuzzer-10-dev
```

Now copy the symlink in `/usr/bin` or whatever location of clang-10.

```sh
$> which clang-10
/usr/bin/clang-10 # this is the result of 'which clang-10'
$> sudo cp -P /usr/bin/clang-10 /usr/bin/clang
```

### Install afl

```sh
git clone https://github.com/google/AFL
cd AFL
make
sudo make install
```

Now go back to [Fuzzing instructions for Linux](readme.md)

## Real Windows instructions

There are a lot of things you need to install on Windows.

### Compiling with libFuzzer

* Download and install Clang 11 for Windows [here](https://llvm.org/builds/)
* Download and install Visual Studio 2019 [here](https://visualstudio.microsoft.com/downloads/)

You don't need to install all of the Visual Studio components, you only need to
choose “Desktop development with C++”. That will be enough and only download less than 2GB instead of 4GB+.
Perhaps you wonder why need to install two compiler? The answer is: libFuzzer does not work with MingW-GCC.

If you already prepare your test case, the instruction to build the binary is exactly the same with Linux version.

```Nim
nim c -d:libFuzzer -d:release -d:chronicles_log_level=fatal --noMain --cc=clang --passC="-fsanitize=fuzzer" --passL="-fsanitize=fuzzer" testcase
```

Now go back to [Starting the Fuzzer using libFuzzer](readme.md#Starting-the-Fuzzer)


### Compiling with winafl

We will use the same Visual Studio compiler like libFuzzer.

* Download and install Visual Studio 2019 [here](https://visualstudio.microsoft.com/downloads/)

Now open one of this terminal from VS 2019:

* Developer PowerShell for VS 2019
* x64 Native Tools Command Prompt for VS 2019
* x86 Native Tools Command Prompt for VS 2019

### Download and build winafl

No need to install cmake, VS 2019 already included cmake in it's installation package.

```sh
git clone https://github.com/googleprojectzero/winafl
cd winafl
git submodule update --init --recursive
```

#### 32/64 bit build using VS 2017

```sh
mkdir build32
cd build32
cmake -G"Visual Studio 15 2017" .. -DINTELPT=1
cmake --build . --config Release

mkdir build64
cd build64
cmake -G"Visual Studio 15 2017 Win64" .. -DINTELPT=1
cmake --build . --config Release
```

#### 32/64 bit build using VS 2019

```
mkdir build32
cd build32
cmake -G"Visual Studio 16 2019" .. -DINTELPT=1 -Ax86
cmake --build . --config Release

mkdir build64
cd build64
cmake -G"Visual Studio 16 2019" .. -DINTELPT=1 -Ax64
cmake --build . --config Release
```

Either you use VS 2017 or VS 2019, you'll get the binary in:

`winafl/build64/bin/Release` or `winafl/build32/bin/Release`

If you only need to use it occasionally, you can use this command to add the winafl binary path to
you env `PATH` instead of polluting it system wide.

* PowerShell: ```$env:path = ($pwd).path + "\bin\Release;" + $env:path```
* CMD Command Prompt: ```set PATH=%CD%\bin\Release;%PATH%```

#### Compiling testcase

Compiling the testcase is simpler than Linux version, you don't need to use afl-gcc or afl-clang,
you can use clang, vcc, or mingw-gcc as you like.

```Nim
nim c -d:afl -d:noSignalHandler -d:release -d:chronicles_log_level=fatal testcase
```

#### Starting the Fuzzer

Now run the command from Command Prompt terminal, the `@@` will not work with PowerShell.
Winafl needs the input data to be read from a file, not from stdin, that's why the presence of `@@`.

```sh
afl-fuzz.exe -i inDir -o outDir -P -t 20000 -- -coverage_module testcase.exe -fuzz_iterations 20 -target_module testcase.exe -target_method AFLmain -nargs 2 -- testcase.exe @@
```

* `inDir` is a directory containing a small but valid input file that makes sense to the program.
* `outDir` will be the location of generated testcase corpus.
* replace both `testcase.exe` with your executable binary.
* `-P` is Intel PT selector
* `-t` timeout in msec
