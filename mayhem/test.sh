#!/usr/bin/env bash
#
# mayhem/test.sh — RUN quirc's functional suite (already built by mayhem/build.sh): upstream's
# tests/overflow_test plus a known-answer decode of committed QR images. exit 0 = pass.
# PATCH-grade oracle: the grader rebuilds (build.sh) then runs this.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# RUN the suite build.sh produced (never compile here).
T="$SRC/mayhem/out/test"
for b in overflow_test quirc_selftest; do
  [ -x "$T/$b" ] || { echo "missing $T/$b — mayhem/build.sh did not build the suite" >&2; emit_ctrf quirc-known-answer 0 1; exit 1; }
done

passed=0 failed=0

# Upstream's unit test: quirc_image_size() must not overflow (asserts abort on failure).
if "$T/overflow_test"; then passed=$((passed+1)); echo "PASS overflow_test"
else failed=$((failed+1)); echo "FAIL overflow_test"; fi

# Known-answer decode: every image in mayhem/selftest/images is a QR code made by an independent
# encoder (segno); quirc must find it and decode the exact version/ECC/mask/type/ECI/payload in
# mayhem/selftest/expected.txt (one line per image; mirrored.pgm only decodes through quirc_flip).
actual=$("$T/quirc_selftest" "$SRC"/mayhem/selftest/images/*.pgm 2>&1) || true
while IFS= read -r want; do
  img=${want%% *}
  got=$(printf '%s\n' "$actual" | awk -v p="$img " 'index($0, p) == 1')
  if [ "$got" = "$want" ]; then passed=$((passed+1)); echo "PASS $img"
  else failed=$((failed+1)); echo "FAIL $img"; echo "  want: $want"; echo "  got:  ${got:-<nothing>}"; fi
done < "$SRC/mayhem/selftest/expected.txt"

emit_ctrf quirc-known-answer "$passed" "$failed"
