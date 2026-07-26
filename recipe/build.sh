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

# The zlib bundled with the binutils and gcc trees #defines fdopen to NULL
# on macOS (a pre-OS-X workaround, removed in later upstream zlib), which
# breaks the fdopen declaration in modern macOS SDK headers. Drop it.
find . -path '*/zlib/zutil.h' -exec sed -i '/define fdopen(fd,mode) NULL/d' {} +

# gcc 7 predates Apple Silicon: add the aarch64-darwin host support that
# upstream gained in gcc 12 (config.host gates it, so this is inert
# elsewhere), and graphite.h's missing isl includes.
patch -p1 -N -d riscv-gcc < "$RECIPE_DIR/patches/0002-gcc-add-aarch64-darwin-host-support.patch"
patch -p1 -N -d riscv-gcc < "$RECIPE_DIR/patches/0003-gcc-graphite-isl-includes.patch"

# ld shares one file offset between the LTO plugin's (dup'd) fd and the
# bfd's buffered stdio stream, and only restores it when the plugin does
# NOT claim the file. Darwin's stdio seeks inside its buffer without
# re-syncing the descriptor, so after a claimed archive member the next
# buffer refill reads from the wrong offset and linking any -flto archive
# fails with "Malformed archive". Restore the offset unconditionally.
patch -p1 -N -d riscv-binutils-gdb < "$RECIPE_DIR/patches/0004-macos-binutils-lto-plugin-restore-file-offset.patch"

# The GAP fork's SMALLF mode iterator can expand to V1SF, which is missing
# from riscv.md's declared "mode" attribute values. gcc hosts constant-fold
# the (false) TARGET_HARD_FLOAT insn conditions and prune those variants
# before genattrtab's check; clang does not fold them, and genattrtab then
# rejects the file. Declare the missing value — the insns stay disabled by
# their run-time conditions either way.
sed -i 's/"unknown,none,QI,HI,SI,DI,TI,HF,OHF,SF,DF,TF,V2HI,V4QI,V2HF,V2OHF"/"unknown,none,QI,HI,SI,DI,TI,HF,OHF,SF,DF,TF,V1SF,V2HI,V4QI,V2HF,V2OHF"/' \
  riscv-gcc/gcc/config/riscv/riscv.md

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

# The generated Makefile re-runs download_prerequisites during the build
# (when gmp/mpfr/mpc are not host libraries), and GCC 7's script re-extracts
# the tarballs unconditionally — clobbering the config.sub/zutil.h fixups
# above. The prerequisites are already in place, so neutralize the re-run.
sed -i 's|&& \./contrib/download_prerequisites|\&\& true|' Makefile.in

# libcc1 is gdb's compile-anything plugin — useless for an embedded cross
# toolchain, and its host plugin libraries fail to link on aarch64-darwin
# (they resolve symbols against the running cc1, which gcc 7's libtool
# setup never handled for that host). Disable it uniformly.
sed -i 's|--disable-libmudflap|--disable-libcc1 --disable-libmudflap|' Makefile.in

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
