#!/usr/bin/env bash

set -eu

SRC="${HONGGFUZZ_SRC:-/tmp/honggfuzz}"
DESTDIR="${DESTDIR:-/opt/honggfuzz}"
SUDO="${SUDO-sudo}"

rm -rf "$SRC"
git clone --depth 1 https://github.com/google/honggfuzz.git "$SRC"

case "$(uname -s)" in
  Linux)
    $SUDO apt-get update
    $SUDO apt-get install -y binutils-dev libunwind8-dev
    make -C "$SRC"
    $SUDO make -C "$SRC" install DESTDIR="$DESTDIR"
    ;;
  Darwin)
    # On macOS only the compiler wrappers (hfuzz-clang, ...) and libhfuzz works.
    # Coverage-guided fuzzing links no longer existing private macOS frameworks.
    sed -i '' 's/\$(error Unsupported MAC OS X version)/CRASH_REPORT := unsupported/' "$SRC/Makefile"
    sed -i '' 's/-Wall -Wextra -Werror /-Wall -Wextra -Werror -Wno-error=strict-prototypes -Wno-error=c23-extensions -Wno-error=unused-command-line-argument /' "$SRC/Makefile"
    printf '\n.PHONY: wrappers\nwrappers: $(HFUZZ_CC_BIN)\n' >> "$SRC/Makefile"
    make -C "$SRC" wrappers LDFLAGS=
    BIN_PATH="$DESTDIR/usr/local/bin"
    $SUDO mkdir -p -m 755 "$BIN_PATH"
    for w in hfuzz-cc hfuzz-clang hfuzz-clang++ hfuzz-gcc hfuzz-g++; do
      $SUDO install -m 755 "$SRC/hfuzz_cc/$w" "$BIN_PATH"
    done
    echo "honggfuzz compiler wrappers installed to $BIN_PATH"
    echo "Add to PATH:  export PATH=\"$BIN_PATH:\$PATH\""
    ;;
  *)
    echo "$0: unsupported OS '$(uname -s)'" >&2
    exit 1
    ;;
esac

rm -rf "$SRC"
