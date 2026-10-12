#!/usr/bin/env bash
set -uo pipefail

COBC=${COBC:-cobc}
CFLAGS="-free -I copybooks"
BUILD_DIR="build/test_bpxspi"
DATA_DIR="var/data"

mkdir -p "$BUILD_DIR"
mkdir -p "$DATA_DIR"

# Clean SPI settlement index for clean repeatable run
rm -f "$DATA_DIR/pxspis.idx" "$DATA_DIR/pxspis.idx"*

echo "Compiling BPXSPI regression test suite..."
$COBC $CFLAGS -x -o "$BUILD_DIR/test_bpxspi" \
    tests/test_bpxspi_driver.cbl \
    cobol/pix/BPXSPI.cbl || exit 1

echo "Running BPXSPI regression tests..."
export BANK_HOME="${BANK_HOME:-$PWD}"

out=$("$BUILD_DIR/test_bpxspi")

PASS=0
FAIL=0

check() {
    local test_name="$1"
    local pattern="$2"
    if echo "$out" | grep -q "$pattern"; then
        echo "PASS: $test_name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $test_name (expected pattern: '$pattern')"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Output ==="
echo "$out"
echo "=============="

check "Initial in-flight submission marked UNKNOWN" "test=submit_unknown rc=24 result=UNKNOWN"
check "First query returns UNKNOWN (RC=24)" "test=query_unknown_1 rc=24 result=UNKNOWN"
check "Second query stays UNKNOWN (RC=24, no fake auto-settlement)" "test=query_unknown_2 rc=24 result=UNKNOWN"
check "Third query stays UNKNOWN (RC=24, idempotent)" "test=query_unknown_3 rc=24 result=UNKNOWN"
check "Explicit SETTLED query confirms SETTLED" "test=query_settled rc=00 result=SETTLED"

echo ""
echo "Summary: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

exit 0
