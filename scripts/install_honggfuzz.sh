#!/usr/bin/env bash

set -eu

sudo apt-get update
sudo apt-get install binutils-dev
sudo apt-get install libunwind8-dev

git clone https://github.com/google/honggfuzz.git /tmp/honggfuzz

pushd /tmp/honggfuzz
  make
  sudo make install DESTDIR=/opt/honggfuzz
popd

rm -rf /tmp/honggfuzz

