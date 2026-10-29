#!/usr/bin/env bash
#
# mayhem/build.sh — build xz's liblzma fuzz harnesses (sanitized) and the project's own test suite (normal flags).
# Runs in the commit image as `mayhem` in /mayhem. Nothing is fetched: xz's CMake build needs only the toolchain.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

HARNESSES="fuzz_decode_alone fuzz_decode_index fuzz_decode_stream fuzz_decode_stream_mt fuzz_encode_stream"

# 1) Sanitized + SanCov-instrumented static liblzma, in a gitignored build dir (mayhem/.gitignore).
#    fuzz-no-link instruments the library itself; without it the harnesses record no coverage.
FUZZ_DIR="$SRC/mayhem/build-fuzz"
env -u CFLAGS -u CXXFLAGS -u LDFLAGS cmake -S "$SRC" -B "$FUZZ_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link" \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF -DXZ_SANDBOX=no \
    -DXZ_NLS=OFF -DXZ_DOC=OFF \
    -DXZ_TOOL_XZ=OFF -DXZ_TOOL_XZDEC=OFF -DXZ_TOOL_LZMADEC=OFF -DXZ_TOOL_LZMAINFO=OFF \
    -DXZ_TOOL_SCRIPTS=OFF -DXZ_TOOL_SYMLINKS=OFF
cmake --build "$FUZZ_DIR" -j"$MAYHEM_JOBS" --target liblzma

# 2) Each harness twice: libFuzzer binary and run-once standalone reproducer. Leak detection is off at
#    build time via lsan_off.cc (ASan/UBSan stay on). The standalone driver is a C file, compiled once.
OBJ_DIR="$FUZZ_DIR/harness-obj"
mkdir -p "$OBJ_DIR"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$OBJ_DIR/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OBJ_DIR/standalone_main.o"
for h in $HARNESSES; do
    $CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
        -I"$SRC/src/liblzma/api" "$SRC/tests/ossfuzz/$h.c" "$OBJ_DIR/lsan_off.o" \
        "$FUZZ_DIR/liblzma.a" -lpthread -o "$SRC/$h"
    $CC $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link \
        -I"$SRC/src/liblzma/api" "$SRC/tests/ossfuzz/$h.c" "$OBJ_DIR/standalone_main.o" \
        "$OBJ_DIR/lsan_off.o" "$FUZZ_DIR/liblzma.a" -lpthread -o "$SRC/$h-standalone"
done

# 3) The project's own test suite with NORMAL flags (no sanitizers, no -gdwarf-3); test.sh only runs it.
TEST_DIR="$SRC/mayhem/build-tests"
env -u CFLAGS -u CXXFLAGS -u LDFLAGS cmake -S "$SRC" -B "$TEST_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=ON \
    -DXZ_NLS=OFF -DXZ_DOC=OFF
cmake --build "$TEST_DIR" -j"$MAYHEM_JOBS"
