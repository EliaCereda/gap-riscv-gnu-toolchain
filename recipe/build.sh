#!/usr/bin/env bash
set -euxo pipefail

# The conda compiler activation injects -std=c++17 into CXXFLAGS, which
# overrides GCC 7's own -std=gnu++98 and breaks its pre-C++17 sources
# ('register' storage class in gcc/cp, etc.). gdb picks its own standard and
# is handled by the -Wno-error below.
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

# The 2017-era config.sub/config.guess in the subprojects (and in the gmp/
# mpfr/mpc trees extracted above) predate Apple Silicon and reject the
# arm64-apple-darwin host triple. Refresh them everywhere from gnuconfig,
# after download_prerequisites so the extracted trees are covered too.
# (cp -f: the mpc tarball extracts these files read-only, and a plain cp
# fails on them silently inside find -exec)
find . -name config.sub -exec cp -f "$BUILD_PREFIX"/share/gnuconfig/config.sub {} \;
find . -name config.guess -exec cp -f "$BUILD_PREFIX"/share/gnuconfig/config.guess {} \;

# Fresh git checkouts have arbitrary mtimes, which can make the pregenerated
# bison/flex outputs (e.g. intl/plural.c) look stale; modern bison then
# mangles the 2003-era grammars and the build fails. Backdate all grammar
# sources so the shipped generated files always win.
find . \( -name '*.y' -o -name '*.yy' -o -name '*.l' -o -name '*.ll' \) -exec touch -t 200001010000 {} +

# bison generates gdb's parsers (c-exp.y etc.) during the build and needs
# GNU m4 — point it at the build env's explicitly so a BSD m4 from the host
# (Xcode's gm4) can never be picked up.
export M4="$BUILD_PREFIX/bin/m4"

# All source modifications go through the patch series below, one directory
# per tree they target; every patch carries its rationale in its own header
# and the series apply in filename order.
for p in "$RECIPE_DIR"/patches/toolchain/*.patch; do
  patch -p1 -N < "$p"
done
for p in "$RECIPE_DIR"/patches/riscv-gcc/*.patch; do
  patch -p1 -N -d riscv-gcc < "$p"
done
for p in "$RECIPE_DIR"/patches/riscv-binutils-gdb/*.patch; do
  patch -p1 -N -d riscv-binutils-gdb < "$p"
done

# Link the C++ runtime statically on Linux. macOS has no static libc and its
# libc++ is a stable system library, so there the dynamic default is correct
# (and clang has no equivalent flags). Append to the conda activation's
# LDFLAGS rather than replacing them.
if [[ "$(uname -s)" == "Linux" ]]; then
  export LDFLAGS="${LDFLAGS:-} -static-libstdc++ -static-libgcc"
fi

# The 2017-era K&R C throughout binutils/readline/gdb trips diagnostics that
# clang >= 16 promoted to hard errors (readline's undeclared ioctl() being
# the first); downgrade them back to the warnings they were when this code
# was current.
if [[ "$(uname -s)" == "Darwin" ]]; then
  export CFLAGS="${CFLAGS:-} -Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=int-conversion -Wno-error=incompatible-function-pointer-types -Wno-error=incompatible-pointer-types"
  # gdb's enum-flags template casts -1 into unscoped enums; clang 18 makes
  # that an error by default (-Wenum-constexpr-conversion) but still allows
  # downgrading it — clang >= 19 does not, hence the version pin in
  # variants.yaml. 'register' (gcc/cp via cfns.gperf) and dynamic exception
  # specs are C++17 removals that gcc 13 reports as warnings but clang
  # promotes to errors under its gnu++17 default.
  export CXXFLAGS="${CXXFLAGS:-} -Wno-error=enum-constexpr-conversion -Wno-register -Wno-dynamic-exception-spec"
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

# The bfd/opcodes dev files (consumed by the SDK's gen-debug-info build)
# stay where cross binutils installs them:
# $PREFIX/<host-triple>/riscv32-unknown-elf/{lib,include}. That is binutils'
# own convention for host libraries serving a target toolchain, and it is
# inherently non-clobbering — folding them into plain lib/ and include/
# collides with conda-forge's binutils_impl, which ships its own (2.46-API)
# bfd.h/libbfd.a/libopcodes.a at those paths in every Linux environment.
# Consumers locate the directory with a glob such as
#   "$CONDA_PREFIX"/*/riscv32-unknown-elf/lib
# which also absorbs the platform-to-platform host-triple differences.

# libiberty installs into $(libdir)/$(CC -print-multi-os-directory), which is
# lib64 with conda's Linux gcc; fold it into lib/, where conda packages
# belong (lib/libiberty.a does not collide with binutils_impl).
if [ -f "$PREFIX/lib64/libiberty.a" ]; then
  mv "$PREFIX/lib64/libiberty.a" "$PREFIX/lib/"
  rmdir "$PREFIX/lib64" 2>/dev/null || true
fi

# Strip host binaries before packaging (mirrors Makefile.gap's `strip` target).
# Target libraries (newlib .a) must keep their symbols — only bin/ and libexec/.
# STRIP is the conda binutils' host strip from the compiler activation.
find "$PREFIX"/bin "$PREFIX"/libexec -type f | xargs -r "${STRIP:-strip}" -- 2>/dev/null || true
find "$PREFIX" -name '*.la' -delete
