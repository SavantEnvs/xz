#!/usr/bin/env bash
#
# mayhem/test.sh — RUN xz's own test suite (built by mayhem/build.sh) plus a known-answer check.
# Counts come from ctest's own summary line and the known-answer assertions, so a neutered binary
# (empty output) fails loudly instead of "passing" on exit status.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

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

TEST_DIR="$SRC/mayhem/build-tests"
[ -f "$TEST_DIR/CTestTestfile.cmake" ] || { echo "test.sh: $TEST_DIR missing — build.sh must build the suite" >&2; emit_ctrf "cmake-ctest" 0 1; exit 1; }

# 1) Upstream's ctest suite: liblzma unit tests (tuktest) + tests that run the xz tool over tests/files
#    (good-* must decode, bad-* must be rejected) — all assert behavior.
out=$(cd "$TEST_DIR" && ctest -j"${MAYHEM_JOBS:-$(nproc)}" 2>&1)
echo "$out"
summary=$(printf '%s\n' "$out" | sed -n 's/.*[0-9]*% tests passed, \([0-9]*\) tests failed out of \([0-9]*\).*/\1 \2/p' | tail -1)
if [ -z "$summary" ]; then
  echo "test.sh: no ctest summary — the suite did not run" >&2
  emit_ctrf "cmake-ctest" 0 1; exit 1
fi
set -- $summary
failed=$1; total=$2
passed=$(( total - failed ))
[ "$total" -gt 0 ] || { failed=1; }

# 2) Known-answer checks with the built xz tool: decoding fixtures must reproduce exact bytes.
XZ="$TEST_DIR/xz"
ka_total=0; ka_failed=0
known() { # <description> <expected> <actual>
  ka_total=$((ka_total+1))
  if [ "$2" = "$3" ]; then echo "known-answer ok: $1"; else echo "known-answer FAIL: $1 (expected '$2', got '$3')" >&2; ka_failed=$((ka_failed+1)); fi
}
known "xz --version prefix" "xz (XZ Utils)" "$("$XZ" --version 2>/dev/null | head -1 | sed 's/ [0-9][0-9.a-z]*$//')"
payload="mayhem known-answer payload: the quick brown fox jumps over the lazy dog"
rt=$(printf '%s' "$payload" | "$XZ" -c -6 -C crc64 2>/dev/null | "$XZ" -dc 2>/dev/null)
known "xz round trip" "$payload" "$rt"
tmpf=$(mktemp "${TMPDIR:-/tmp}/xzka.XXXXXX"); trap 'rm -f "$tmpf"' EXIT
printf '%s' "$payload" | "$XZ" -c 2>/dev/null > "$tmpf"
known "xz --robot -l reports one stream and the payload size" "1 ${#payload}" "$("$XZ" --robot -l "$tmpf" 2>/dev/null | awk '$1=="totals"{print $2, $5}')"
good="$SRC/tests/files/good-1-check-crc32.xz"
known "good-1-check-crc32.xz decodes to 'Hello\nWorld!\n' hash" "$(printf 'Hello\nWorld!\n' | sha256sum | cut -d' ' -f1)" "$("$XZ" -dc "$good" 2>/dev/null | sha256sum | cut -d' ' -f1)"
bad="$SRC/tests/files/bad-1-check-crc32.xz"
"$XZ" -dc "$bad" >/dev/null 2>&1; rc=$?
known "bad-1-check-crc32.xz is rejected (exit 1)" "1" "$rc"

passed=$(( passed + ka_total - ka_failed )); failed=$(( failed + ka_failed ))
emit_ctrf "cmake-ctest+known-answer" "$passed" "$failed"
