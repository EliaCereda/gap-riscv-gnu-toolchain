#!/usr/bin/env bash
set -euxo pipefail

# Build gmp/mpfr/mpc in-tree and statically instead of linking the distro's
# shared libraries, so the host tools only depend on glibc.
( cd riscv-gcc && ./contrib/download_prerequisites )
export LDFLAGS="-static-libstdc++ -static-libgcc"

# Mirrors Makefile.gap's `build` target, but installs into the conda build
# prefix so rattler-build records relocatable prefix placeholders.
./configure --prefix="$PREFIX" --with-arch=rv32imcxgap9 --with-cmodel=medlow --enable-multilib
make -j"${CPU_COUNT}" all install
cp riscv.ld "$PREFIX"/riscv32-unknown-elf/lib

# Strip host binaries before packaging (mirrors Makefile.gap's `strip` target).
# Target libraries (newlib .a) must keep their symbols — only bin/ and libexec/.
find "$PREFIX"/bin "$PREFIX"/libexec -type f | xargs -r strip -- 2>/dev/null || true
find "$PREFIX" -name '*.la' -delete
