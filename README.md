# gap-riscv-gnu-toolchain (conda package)

Builds the [GAP RISC-V GNU toolchain](https://github.com/GreenWaves-Technologies/gap-riscv-gnu-toolchain)
(riscv32-unknown-elf GCC, binutils, GDB and newlib for GreenWaves GAP processors)
as a relocatable conda package with [rattler-build](https://rattler.build), for
`linux-64` and `linux-aarch64`.

## Using the toolchain with Pixi

```toml
[workspace]
channels = ["https://prefix.dev/eliacereda", "conda-forge"]
platforms = ["linux-64", "linux-aarch64"]

[dependencies]
gap-riscv-gnu-toolchain = "24.02.*"
```

Then `pixi install` and `riscv32-unknown-elf-gcc` is on the environment path.
For ad-hoc use: `pixi global install -c https://prefix.dev/eliacereda gap-riscv-gnu-toolchain`.

Note: conda normalizes numeric version segments, so `24.02.0` may be displayed as
`24.2.0` in lockfiles; `24.02.*` and `24.2.*` match the same package.

## Building locally

```sh
pixi run build
```

This runs `rattler-build build --recipe recipe/recipe.yaml`. The build compiles
GCC + binutils + newlib from source (upstream commit pinned in
[recipe/recipe.yaml](recipe/recipe.yaml)) and takes on the order of 10 minutes
to 2 hours depending on core count. Host build dependencies (autotools, bison,
flex, texinfo, gperf, gawk, bc, zlib headers, a C/C++ compiler) must be
installed system-side, matching the Ubuntu 24.04 CI environment; gmp/mpfr/mpc
are downloaded and built in-tree, statically.

## CI and publishing

GitHub Actions ([.github/workflows/conda.yml](.github/workflows/conda.yml)) builds
both architectures natively on hosted runners (`ubuntu-24.04`, `ubuntu-24.04-arm`)
on every push/PR. Pushing a `v*` tag additionally uploads the packages to the
`eliacereda` channel on prefix.dev (requires the `PREFIX_API_KEY` repository secret).

Release flow: bump `context.version` / `context.rev` in the recipe, tag `v<version>`
(e.g. `v24.02.0`), push the tag.

## Patches

Patches in `patches/toolchain/` are applied to the upstream checkout via the
`source.patches` list in [recipe/recipe.yaml](recipe/recipe.yaml). Currently:

- `0001-disable-gdb-python.patch` — GDB 8.0-era Python bindings do not compile
  against modern Python, so Python scripting support is disabled explicitly
  (otherwise the build fails on any host with python3 development headers).

## Notes on relocatability

The package ships the toolchain with its build-time installation prefix left
untouched inside the ELF binaries (`prefix_detection: ignore_binary_files`):
that path never exists at install time, so GCC's own `argv[0]`-relative
self-relocation resolves every internal path. Rewriting the embedded prefix
instead would corrupt the driver, because GCC 7 constant-folds `strlen` of the
compiled-in prefix into fixed offsets at build time.

Linking a standalone program requires providing `__global_pointer$` (e.g.
`-Wl,--defsym,__global_pointer$=...`); in normal use the GAP SDK's
chip-specific linker scripts define it.
