cmake_minimum_required(VERSION 3.19)

# GAP9 silicon tests for the riscv-gcc 0005-0007 / riscv-binutils-gdb 0004
# fixes (README.md). <test>_fns.c holds the code under test, compiled by the
# riscv32-unknown-elf-gcc on PATH or given prebuilt as GCC1_FNS_OBJ (another
# compiler); <test>_main.c is the harness. dimm's two files are generated.
set(GCC1_TEST "dimm" CACHE STRING "dimm, unpack, trunc or frm")
set(GCC1_FNS_OBJ "" CACHE FILEPATH "prebuilt object for <test>_fns.c")
set(TARGET_NAME "gcc1_${GCC1_TEST}")
set(SRC ${CMAKE_CURRENT_SOURCE_DIR})
if(GCC1_TEST STREQUAL "dimm")
  execute_process(COMMAND python3 ${SRC}/gen_dimm.py WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
                  COMMAND_ERROR_IS_FATAL ANY)
  set(SRC ${CMAKE_CURRENT_BINARY_DIR})
endif()
if(GCC1_FNS_OBJ)
  set(FNS ${GCC1_FNS_OBJ})
else()
  set(FNS ${SRC}/${GCC1_TEST}_fns.c)
endif()
set(TARGET_SRCS ${SRC}/${GCC1_TEST}_main.c ${FNS})

include($ENV{GAP_SDK_HOME}/utils/cmake/setup.cmake)

project(${TARGET_NAME} C ASM)
add_executable(${TARGET_NAME} ${TARGET_SRCS})
if(NOT GCC1_FNS_OBJ)
  # -Wno-error: dimm has always-true compares (x >= 0u) on purpose.
  if(GCC1_TEST STREQUAL "trunc")
    set_source_files_properties(${FNS} PROPERTIES COMPILE_OPTIONS "-O3;-Wno-error")
  else()
    set_source_files_properties(${FNS} PROPERTIES COMPILE_OPTIONS "-O2;-Wno-error")
  endif()
endif()

setupos(${TARGET_NAME})
