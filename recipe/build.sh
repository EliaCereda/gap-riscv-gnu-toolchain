#!/usr/bin/env bash
set -euxo pipefail

# The conda compiler activation injects -std=c++17 into CXXFLAGS, which
# overrides GCC 7's own -std=gnu++98 and breaks its (pre-C++17) sources.
export CXXFLAGS="${CXXFLAGS/-std=c++17/}"

# Keep gdb curses/termcap-free (stub termcap, no TUI). Conda build tools drag
# ncurses into the build environment transitively, but any conda .so in the
# host binaries' NEEDED entries could not be resolved at runtime (binary
# prefix relocation is off, so baked rpaths are dead). Preset the configure
# caches so gdb behaves as on a system without curses.
export ac_cv_search_tgetent=no ac_cv_search_waddstr=no \
       ac_cv_header_curses_h=no ac_cv_header_ncurses_h=no \
       ac_cv_header_ncurses_ncurses_h=no ac_cv_header_ncurses_curses_h=no

# Build gmp/mpfr/mpc in-tree and statically instead of linking shared
# libraries, so the host tools only depend on the system C/C++ runtime. The
# top-level configure picks the in-tree path automatically because those
# libraries are absent from the build environment.
( cd riscv-gcc && ./contrib/download_prerequisites )

# Link the C++ runtime statically on Linux. macOS has no static libc and its
# libc++ is a stable system library, so there the dynamic default is correct
# (and clang has no equivalent flags). Append to the conda activation's
# LDFLAGS rather than replacing them.
if [[ "$(uname -s)" == "Linux" ]]; then
  export LDFLAGS="${LDFLAGS:-} -static-libstdc++ -static-libgcc"
fi

# Mirrors Makefile.gap's `build` target, but installs into the conda build
# prefix so rattler-build records relocatable prefix placeholders.
# --without-system-zlib makes GCC build its bundled zlib statically (the
# top-level configure defaults to --with-system-zlib), avoiding an
# undeclared runtime dependency on the system libz.
./configure --prefix="$PREFIX" --with-arch=rv32imcxgap9 --with-cmodel=medlow \
  --enable-multilib --without-system-zlib
make -j"${CPU_COUNT}" all install
cp riscv.ld "$PREFIX"/riscv32-unknown-elf/lib

# Strip host binaries before packaging (mirrors Makefile.gap's `strip` target).
# Target libraries (newlib .a) must keep their symbols — only bin/ and libexec/.
# STRIP is the conda binutils' host strip from the compiler activation.
find "$PREFIX"/bin "$PREFIX"/libexec -type f | xargs -r "${STRIP:-strip}" -- 2>/dev/null || true
find "$PREFIX" -name '*.la' -delete
