#!/bin/bash
# Run a prebuilt GCC1 test ELF on the GAP9 EVK (FT4232H probe): the same binary
# that ran on GVSOC. From the gap-sdk pixi env on the board host:
#   bash run_board.sh <test> <ELF>
set -euo pipefail
: "${GAP_SDK_HOME:?run inside the gap-sdk pixi env}"
t=$1
elf=$(realpath "$2")
cd "$(dirname "${BASH_SOURCE[0]}")"
b=build-board-$t

if pgrep -x openocd >/dev/null; then echo "FATAL: openocd already running (probe busy)"; exit 1; fi

cmake -B "$b" -DKCONFIG_CONFIG=sdk-board.config -DGCC1_TEST="$t" -G"Unix Makefiles" > "$b.cmake.log" 2>&1 ||
  { tail -20 "$b.cmake.log"; exit 1; }
grep -q "CONFIG_PLATFORM_BOARD YES" "$b/__vars.cmake" || { echo "FATAL: board platform not selected"; exit 1; }
# Build the SDK side and the flash image inputs, then swap in the given ELF.
cmake --build "$b" --target "gcc1_$t" -j 14 > "$b.build.log" 2>&1 || { tail -30 "$b.build.log"; exit 1; }
sleep 1
cp "$elf" "$b/gcc1_$t" && touch "$b/gcc1_$t"
sha256sum "$b/gcc1_$t"

# Poll for the last line; board runs can hang after printing it.
log=$b.run.log
: > "$log"
set +e
timeout 300 stdbuf -oL cmake --build "$b" --target run > "$log" 2>&1 &
pid=$!
for _ in $(seq 140); do
  grep -q "^GCC1 DONE" "$log" && break
  kill -0 "$pid" 2>/dev/null || break
  sleep 2
done
sleep 2
pkill -x openocd 2>/dev/null
wait "$pid" 2>/dev/null
set -e
sha256sum "$b/gcc1_$t"
grep -cE "Linking|Building C" "$log" || true
grep "^GCC1" "$log"
