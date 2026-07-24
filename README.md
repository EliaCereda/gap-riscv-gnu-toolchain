# gap-riscv-gnu-toolchain (conda package)

Builds the [GAP RISC-V GNU toolchain](https://github.com/GreenWaves-Technologies/gap-riscv-gnu-toolchain)
(riscv32-unknown-elf GCC, binutils, GDB and newlib for GreenWaves GAP processors)
as a relocatable conda package with [rattler-build](https://rattler.build), for
`linux-64`, `linux-aarch64`, `osx-arm64` and `osx-64`.

## Using the toolchain with Pixi

```toml
[workspace]
channels = ["https://prefix.dev/eliacereda", "conda-forge"]
platforms = ["linux-64", "linux-aarch64", "osx-arm64", "osx-64"]

[dependencies]
gap-riscv-gnu-toolchain = "24.02.*"
```

Then `pixi install` and `riscv32-unknown-elf-gcc` is on the environment path.
For ad-hoc use: `pixi global install -c https://prefix.dev/eliacereda gap-riscv-gnu-toolchain`.

Note: the channel's sharded repodata currently 404s on prefix.dev's side,
which makes `pixi add`/`pixi install` fail with an error like
`HTTP status client error (404 Not Found) for url (https://shards.prefix.dev/…)`.
Until that is fixed, disable sharded repodata for prefix.dev in
`.pixi/config.toml` (per workspace) or `~/.pixi/config.toml` (global):

```toml
[repodata-config."https://prefix.dev"]
disable-sharded = true
```

Pixi then falls back to the plain `repodata.json`, which is regenerated about
hourly — a freshly uploaded package can take up to an hour to become
installable even though it is already visible on the website.

Note: conda normalizes numeric version segments, so `24.02.0` may be displayed as
`24.2.0` in lockfiles; `24.02.*` and `24.2.*` match the same package.

## Building locally

```sh
pixi run build
```

This runs `rattler-build build --recipe recipe/recipe.yaml`. The build compiles
GCC + binutils + newlib from source (upstream commit pinned in
[recipe/recipe.yaml](recipe/recipe.yaml)) and takes on the order of 10 minutes
to 2 hours depending on core count. The build is fully conda-native: the
compilers and all build tools come from conda-forge, so it works on any
supported host with no container and no system packages. The compatibility
floor comes from the pinned standard library rather than the build machine —
on Linux gcc 13 with the glibc 2.28 sysroot (giving `__glibc >=2.28`), on
macOS clang with deployment target 11.0; see
[recipe/variants.yaml](recipe/variants.yaml). gmp/mpfr/mpc and zlib are built
in-tree, statically, so the host binaries link only system libraries (CI
verifies this with `readelf`/`otool`).

## CI and publishing

GitHub Actions ([.github/workflows/conda.yml](.github/workflows/conda.yml)) builds
all four platforms natively on hosted runners (`ubuntu-24.04`,
`ubuntu-24.04-arm`, `macos-15`, `macos-15-intel`)
on every push/PR. Pushing a `v*` tag additionally uploads the packages to the
`eliacereda` channel on prefix.dev, authenticating via OIDC trusted publishing
(the repository is registered as a Trusted Publisher on prefix.dev; no stored
API key).

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
