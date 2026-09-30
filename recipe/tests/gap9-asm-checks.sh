#!/usr/bin/env bash
# Checks for the GAP9 silicon fixes (patches riscv-gcc 0005-0008 and
# riscv-binutils-gdb 0004-0005): compile the gap9-*.c tests to assembly and grep it,
# and assemble .d immediates at both ends of their ranges. Run from the
# directory holding the tests, with the package's riscv32-unknown-elf-* on PATH.
set -euo pipefail

flags=(-march=rv32imcxgap9 -mPE=8 -mFC=1 -mint64)
fail=0
bad() { echo "FAIL: $*" >&2; fail=1; }

# Body of function $2 in assembly file $1 (from its label to the next .size).
body() { awk -v f="$2" '$0 == f":" {p=1; next} p && /^\t\.size/ {exit} p' "$1"; }
# Function $2's body must match the extended regex $3.
has() { body "$1" "$2" | grep -Eq "$3" || bad "$2: no match for /$3/"; }
# Function $2's body must not match $3.
hasnt() { if body "$1" "$2" | grep -Eq "$3"; then bad "$2: unexpected /$3/"; fi; }
# Instructions in each hardware-loop body of the assembly on stdin: from the
# lp.setup up to the instruction at its end label, labels and directives left out.
hwbodies() {
  awk '/^\tlp\.setup/ { l = $0; sub(/.*\(/, "", l); sub(/\).*/, "", l); n = 0; in_loop = 1; at_end = 0; next }
       in_loop && $0 == l ":" { at_end = 1; next }
       in_loop && /^\t[a-z]/ { n++; if (at_end) { print n; in_loop = 0 } }'
}

# (a) .d immediates: xori/ori/andi/sltiu.d take 0..31, addi.d/slti.d -16..15.
riscv32-unknown-elf-gcc "${flags[@]}" -O2 -S -o d-imm.s gap9-d-imm.c
if grep -Eq '(xori|ori|andi|sltiu)\.d[[:space:]]+[^,]+,[^,]+,-' d-imm.s; then
  bad "negative xori/ori/andi/sltiu.d immediate:"
  grep -E '(xori|ori|andi|sltiu)\.d[[:space:]]+[^,]+,[^,]+,-' d-imm.s >&2
fi
has d-imm.s ltu_16 'sltiu\.d[[:space:]]+a0,a0,16$'
has d-imm.s ltu_31 'sltiu\.d[[:space:]]+a0,a0,31$'
has d-imm.s leu_30 'sltiu\.d[[:space:]]+a0,a0,31$'
has d-imm.s br_geu_20 'sltiu\.d[[:space:]]+[a-z0-9]+,a0,20$'
has d-imm.s lt_m16 'slti\.d[[:space:]]+a0,a0,-16$'
has d-imm.s le_m17 'slti\.d[[:space:]]+a0,a0,-16$'
has d-imm.s add_m16 'addi\.d[[:space:]]+a0,a0,-16$'

# (b) gas and objdump: 0..31 unsigned; negative values are rejected.
printf '%s\n' 'sltiu.d a0,a0,31' 'xori.d a0,a2,16' 'ori.d a0,a2,0' 'andi.d a0,a2,17' \
  'addi.d a0,a2,-16' 'slti.d a0,a2,-16' > d-imm-ok.s
riscv32-unknown-elf-as -march=rv32imcxgap9 -o d-imm-ok.o d-imm-ok.s
riscv32-unknown-elf-objdump -d d-imm-ok.o > d-imm-ok.dis
for want in '31f5351b[[:space:]]+sltiu\.d[[:space:]]+a0,a0,31' '2106451b[[:space:]]+xori\.d[[:space:]]+a0,a2,16' \
            '2116751b[[:space:]]+andi\.d[[:space:]]+a0,a2,17' '23061513[[:space:]]+addi\.d[[:space:]]+a0,a2,-16' \
            '3106251b[[:space:]]+slti\.d[[:space:]]+a0,a2,-16'; do
  grep -Eq "$want" d-imm-ok.dis || bad "objdump: no /$want/"
done
for insn in 'sltiu.d a0,a0,-1' 'andi.d a0,a2,-16' 'xori.d a0,a2,32' 'ori.d a0,a2,-5'; do
  echo "$insn" > d-imm-bad.s
  if riscv32-unknown-elf-as -march=rv32imcxgap9 -o d-imm-bad.o d-imm-bad.s 2> d-imm-bad.err; then
    bad "gas accepted '$insn'"
  elif ! grep -q 'immediate out of range, expected 0..31' d-imm-bad.err; then
    bad "gas error for '$insn': $(cat d-imm-bad.err)"
  fi
done

# (b) gas's GAP9 rounding-mode warnings (riscv-binutils-gdb 0005): the lines of
# gap9-frm-warn.s tagged "# WARN" warn, no other line does, and -mno-frm-warn
# turns them off.
riscv32-unknown-elf-as -march=rv32imcxgap9 -o frm-warn.o gap9-frm-warn.s 2> frm-warn.err
want=$(grep -nE '#[[:space:]]*WARN' gap9-frm-warn.s | cut -d: -f1 | tr '\n' ' ')
got=$(grep -oE 'gap9-frm-warn\.s:[0-9]+: Warning' frm-warn.err | cut -d: -f2 | tr '\n' ' ')
if [ "$want" != "$got" ]; then
  bad "frm warnings on lines [$got], expected [$want]"
  cat frm-warn.err >&2
fi
riscv32-unknown-elf-as -march=rv32imcxgap9 -mno-frm-warn -o frm-warn.o gap9-frm-warn.s 2> frm-warn-off.err
if [ -s frm-warn-off.err ]; then bad "-mno-frm-warn still warns"; cat frm-warn-off.err >&2; fi

# (c) pv.unpack: lane 0 is the even byte; unpack2 writes a pair, rs2 unused.
riscv32-unknown-elf-gcc "${flags[@]}" -O2 -S -o unpack.s gap9-unpack.c
has unpack.s lo_lane0 'pv\.extract\.b[[:space:]]+a0,a0,0'
has unpack.s lo_lane1 'pv\.extract\.b[[:space:]]+a0,a0,1'
has unpack.s hi_lane0 'pv\.extract\.b[[:space:]]+a0,a0,2'
has unpack.s lo_const_lane0 'li[[:space:]]+a0,1$'
has unpack.s pair_s 'pv\.unpack2\.h\.b\.s[[:space:]]+[a-z0-9]+,a0,zero'
has unpack.s pair_u 'pv\.unpack2\.h\.b\.u[[:space:]]+[a-z0-9]+,a0,zero'

# (c) bf16 <-> int: C conversions to integer widen to float (exact) and use
# rtz, scalar and vectorised alike; nothing writes fcsr or frm (a frm write
# isn't seen by the next FP instruction on GAP9 silicon); the builtin stays a
# single vfcvt.x.ah.
riscv32-unknown-elf-gcc "${flags[@]}" -O3 -S -o bf16-trunc.s gap9-bf16-trunc.c
if grep -Eq 'fscsr|fsrm|csrrwi|csrw' bf16-trunc.s; then bad "fcsr/frm write in bf16-trunc.s"; fi
if grep -Eq 'fcvt\.wu?\.ah' bf16-trunc.s; then bad "fcvt.w[u].ah in bf16-trunc.s (rounds, can't truncate)"; fi
has bf16-trunc.s to_int 'fcvt\.s\.ah[[:space:]]+a0,a0'
has bf16-trunc.s to_int 'fcvt\.w\.s[[:space:]]+a0,a0,rtz'
has bf16-trunc.s to_uint 'fcvt\.wu\.s[[:space:]]+a0,a0,rtz'
has bf16-trunc.s to_short_array 'fcvt\.s\.ah'
has bf16-trunc.s to_short_array 'fcvt\.w\.s[[:space:]]+[a-z0-9]+,[a-z0-9]+,rtz'
hasnt bf16-trunc.s to_short_array 'vfcvt'
has bf16-trunc.s from_short_array 'vfcvt\.ah\.x'
has bf16-trunc.s builtin_round 'vfcvt\.x\.ah'

# (d) hardware loops: GAP9 runs a one-instruction body once, so GCC pads it
# with a nop. A loop of one OffsetedWritePtr store or event_unit_read_fenced
# load (a code-less barrier and the access) gets the nop too (riscv-gcc 0008).
# -Os makes no hardware loop of the run-time counts (incn, sum).
for o in O2 O3 Os; do
  riscv32-unknown-elf-gcc "${flags[@]}" -$o -S -o hwloop-$o.s gap9-hwloop.c
  for f in inc100 incn poll100 sum; do
    n=$(body hwloop-$o.s $f | hwbodies | tr '\n' ' ')
    if [ -z "$n" ] && { [ "$o" != Os ] || [ "$f" = inc100 ] || [ "$f" = poll100 ]; }; then
      bad "-$o $f: no hardware loop"
    fi
    case " $n" in
      *" 0 "* | *" 1 "*) bad "-$o $f: a hardware-loop body of one instruction (bodies: $n)" ;;
    esac
  done
done
has hwloop-O2.s inc100 '^[[:space:]]nop$'
hasnt hwloop-O2.s sum '^[[:space:]]nop$'

exit "$fail"
