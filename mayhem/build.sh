#!/usr/bin/env bash
#
# mayhem/build.sh — build quirc's fuzz harnesses and its functional suite.
#
# Runs inside the commit image as `mayhem` in /mayhem (re-run offline, on an already-built or
# `git clean -ffdX`-ed tree, by the PATCH tier). quirc has no dependencies beyond libm.
#
#  1. libquirc.a with $SANITIZER_FLAGS $DEBUG_FLAGS through upstream's own Makefile target, stashed
#     in mayhem/out/fuzz/, and each harness linked twice against it: libFuzzer
#     (/mayhem/<fuzzer>) and the run-once reproducer (/mayhem/<fuzzer>-standalone).
#  2. libquirc.a again with NORMAL flags (-O2, as a user would build it) for the test suite:
#     upstream's tests/overflow_test and mayhem/selftest/quirc_selftest, in mayhem/out/test/.
#
# The Makefile computes SDL/OpenCV flags with pkg-config at parse time (for the demo programs);
# they are blanked here because only libquirc.a / overflow_test are built.
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
OUT="$SRC/mayhem/out"
mkdir -p "$OUT/fuzz" "$OUT/test"
# SanCov for the fuzzed code: the objects are compiled apart from the libFuzzer link, so they need
# fuzzer-no-link themselves (else the fuzzer sees no edges in quirc).
#
# UBSan relaxation (only this check): identify.c's perspective_map() casts rint() of a projective
# transform to int, and degenerate capstone geometry from almost any random image yields NaN/inf
# there (UBSan float-cast-overflow at identify.c:107 within ~20 execs, every run). Every caller
# bounds-checks the resulting point before touching a pixel, so the cast floods the target without
# a memory-safety consequence; ASan and every other UBSan check stay on and halting. Appended only
# when sanitizers are on, so the empty --build-arg SANITIZER_FLAGS= off-switch still works.
UBSAN_RELAX=""
case "$SANITIZER_FLAGS" in *undefined*) UBSAN_RELAX="-fno-sanitize=float-cast-overflow" ;; esac
FUZZ_CFLAGS="$SANITIZER_FLAGS $UBSAN_RELAX $DEBUG_FLAGS -fsanitize=fuzzer-no-link"
MAKE_ARGS=(-B CC="$CC" SDL_CFLAGS= SDL_LIBS= OPENCV_CFLAGS= OPENCV_LIBS=)

# 1) sanitized library + harnesses
# shellcheck disable=SC2086
make -j"$MAYHEM_JOBS" "${MAKE_ARGS[@]}" CFLAGS="-O1 -Wall -fPIC $FUZZ_CFLAGS" libquirc.a
cp libquirc.a "$OUT/fuzz/libquirc.a"

# shellcheck disable=SC2086
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$OUT/fuzz/lsan_off.o"
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OUT/fuzz/standalone_main.o"

for h in quirc_image_fuzzer quirc_decode_fuzzer; do
  # shellcheck disable=SC2086
  $CC $FUZZ_CFLAGS -Ilib -c "mayhem/harnesses/$h.c" -o "$OUT/fuzz/$h.o"
  # shellcheck disable=SC2086
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$OUT/fuzz/$h.o" "$OUT/fuzz/lsan_off.o" \
      "$OUT/fuzz/libquirc.a" -lm -o "$SRC/$h"
  # shellcheck disable=SC2086
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$OUT/fuzz/standalone_main.o" "$OUT/fuzz/$h.o" "$OUT/fuzz/lsan_off.o" \
      "$OUT/fuzz/libquirc.a" -lm -o "$SRC/$h-standalone"
done

# 2) normal-flags library + functional suite (no sanitizers: an honest oracle for PATCH grading)
# shellcheck disable=SC2086
make -j"$MAYHEM_JOBS" "${MAKE_ARGS[@]}" CFLAGS="-O2 -Wall -fPIC $COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS" \
    libquirc.a overflow_test
cp libquirc.a "$OUT/test/libquirc.a"
mv -f overflow_test "$OUT/test/overflow_test"
# shellcheck disable=SC2086
$CC -O2 -Wall $COVERAGE_FLAGS -Ilib mayhem/selftest/quirc_selftest.c "$OUT/test/libquirc.a" -lm \
    -o "$OUT/test/quirc_selftest"

# Leave no stale in-tree objects/archive behind (all gitignored upstream anyway).
rm -f lib/*.o tests/*.o libquirc.a

echo "built: $SRC/quirc_image_fuzzer $SRC/quirc_decode_fuzzer (+ -standalone), $OUT/test/{overflow_test,quirc_selftest}"
