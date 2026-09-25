# GAP9 silicon tests for the GCC/gas fixes

Self-checking GAP SDK programs for riscv-gcc patches 0005–0007 and
riscv-binutils-gdb patch 0004. They run on GVSOC and, as the same ELF, on a
GAP9 EVK. `recipe/tests/gap9-asm-checks.sh` covers the same fixes at the
assembly level in the package tests. These programs need an SDK and a
simulator or board, so the package tests don't run them.

Each test is split in two:
- `<test>_fns.c` holds the code under test, compiled by the
  `riscv32-unknown-elf-gcc` on PATH, or passed prebuilt as `GCC1_FNS_OBJ`.
- `<test>_main.c` is the harness, compiled by the SDK's GCC.

| Test | Checks | What it covers |
|---|---|---|
| `dimm` | 54740 | 64-bit `<`, `<=`, `>`, `>=` (signed and unsigned), `==`, `!=`, `&`, `\|`, `^` against constants -40..40 and edge values. Compares are checked both as values and as branches, on 28 inputs, against the same operation with the constant in a register (`gen_dimm.py` generates both files). |
| `unpack` | 73 | `pv.unpack1.{lo,hi}` lanes, including through GCC's lane extraction and constant folding, and `pv.unpack2` with a value live in rd+1 |
| `trunc` | 166 | bf16 → `int`/`unsigned`/`short` (scalar and in a loop at -O3) under every frm; frm left unchanged; `__builtin_pulp_v2ohftov2hi` rounding by frm |
| `frm` | none | Probe only: how soon an FP instruction sees a write to frm |

## Running

From a gap-sdk checkout's pixi environment:

```sh
# GVSOC: build <test> as variant <tag> (board platform) and run that ELF on GVSOC
pixi run bash <this dir>/run_gvsoc.sh trunc new
pixi run bash <this dir>/run_gvsoc.sh trunc old-obj /path/to/trunc_fns.o
# EVK: the board host rebuilds the project with the board platform, swaps in the ELF, runs it
pixi run bash <this dir>/run_board.sh trunc /path/to/gcc1_trunc
```

To use another compiler, put its `bin/` first on PATH and its prefix first on
`CMAKE_PREFIX_PATH` inside the pixi command, or pass the prebuilt object:
`pixi run bash -c 'export PATH=/pkg/bin:$PATH CMAKE_PREFIX_PATH=/pkg:$CMAKE_PREFIX_PATH; bash …'`.
Output lines start with `GCC1`, and each run ends with `GCC1 <test>: N checks, M
errors` and `GCC1 DONE`.

## Results

GWT GCC 7.1 as packaged before these patches (build 5), against the patched
package (build 6). Each ELF ran unchanged on GVSOC and on a GAP9 EVK (fabric
controller):

| Test | Build 5: errors on GVSOC / EVK | Build 6: errors on GVSOC / EVK |
|---|---|---|
| `dimm` (54740 checks) | 1760 / 1760: unsigned compares whose constant became a negative `sltiu.d` immediate | 0 / 0 |
| `unpack` (73 checks) | 29 / 29: lanes through extraction and folding, the rd+1 clobber | 0 / 0 |
| `trunc` (166 checks) | 64 / 72: scalar and vectorised conversions round | 0 / 0 |

For build 5, only `<test>_fns.c` came from that compiler; the harness and SDK
runtime came from the SDK's GCC. For build 6, the whole ELF, SDK runtime
included, was built by the package, with its `bin` first on PATH and its
prefix first on `CMAKE_PREFIX_PATH`. The SDK's CMake searches
`CMAKE_PREFIX_PATH` before PATH, so setting only PATH isn't enough. Build 6
ELFs, sha256: `dimm` 3eb7aa29…, `unpack` 5dd8340e…, `trunc` b1b490de….

## Silicon facts these tests established

- **frm hazard.** An FP instruction right after a write to frm (`fsrm`,
  `fscsr` or `csrrwi` on CSR 2) still rounds by the *old* frm. One
  instruction in between is enough. This was measured on the fabric
  controller with `fadd.s`, `fcvt.w.ah` and `vfcvt.x.ah`, in both
  directions (`frm` test). GVSOC doesn't model it.
- **`fcvt.w.ah` follows frm on silicon.** GVSOC instead hands the
  instruction's rm field (5) to its conversion routine, which behaves as
  RNE. Neither can truncate, so C conversions go through `fcvt.s.ah` and
  `fcvt.w.s …,rtz`.
- **`vfcvt.x.ah` with frm = RMM aborts GVSOC** ("Unimplemented rounding
  mode"). The `trunc` test skips that one raw-instruction probe.
