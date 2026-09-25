#!/bin/bash
# Build GCC1 test <test> as variant <tag> with the board platform (the same ELF
# runs on the EVK) and run it on GVSOC. Run inside the gap-sdk pixi env.
#   run_gvsoc.sh <test> <tag> [<fns object>]
# With no object, <test>_fns.c is compiled by the riscv32-unknown-elf-gcc on PATH.
set -euo pipefail
: "${GAP_SDK_HOME:?run inside the gap-sdk pixi env}"
t=$1 tag=$2 obj=${3:-}
cd "$(dirname "${BASH_SOURCE[0]}")"
b=build-$t-$tag g=gvsoc-$t-$tag
cmake -B "$b" -DKCONFIG_CONFIG=sdk-board.config -DGCC1_TEST="$t" -DGCC1_FNS_OBJ="$obj" \
  -G"Unix Makefiles" > "$b.cmake.log" 2>&1 || { tail -20 "$b.cmake.log"; exit 1; }
cmake --build "$b" --target "gcc1_$t" -j "${CMAKE_BUILD_PARALLEL_LEVEL:-14}" > "$b.build.log" 2>&1 ||
  { tail -30 "$b.build.log"; exit 1; }
elf=$b/gcc1_$t
# GVSOC: an up-to-date gvsoc-platform build dir, then the board ELF swapped in.
cmake -B "$g" -DKCONFIG_CONFIG=sdk.config -DGCC1_TEST="$t" -DGCC1_FNS_OBJ="$obj" \
  -G"Unix Makefiles" > "$g.cmake.log" 2>&1 || { tail -20 "$g.cmake.log"; exit 1; }
cmake --build "$g" --target "gcc1_$t" -j "${CMAKE_BUILD_PARALLEL_LEVEL:-14}" > "$g.build.log" 2>&1 ||
  { tail -30 "$g.build.log"; exit 1; }
sleep 1
cp "$elf" "$g/gcc1_$t" && touch "$g/gcc1_$t"
timeout 600 cmake --build "$g" --target run > "$g.run.log" 2>&1 || true
sha256sum "$elf" "$g/gcc1_$t" | awk '{print $1}' | uniq -c
grep -E '^GCC1' "$g.run.log" || { tail -20 "$g.run.log"; exit 1; }
