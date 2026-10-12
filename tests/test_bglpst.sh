#!/usr/bin/env bash
set -uo pipefail

COBC=${COBC:-cobc}
CC=${CC:-cc}
CFLAGS="-free -I copybooks"
BUILD_DIR="build/test_bglpst"
DATA_DIR="var/data"
JRN_DIR="var/journal"

mkdir -p "$BUILD_DIR"
mkdir -p "$DATA_DIR"
mkdir -p "$JRN_DIR"

# Clean state for isolated run
rm -f "$DATA_DIR"/gl.idx* "$DATA_DIR"/acctbal.idx* "$DATA_DIR"/jrst.idx*
rm -f "$DATA_DIR"/lk_*.lck "$JRN_DIR"/postings.log* "$JRN_DIR"/journal.idx*

echo "Building native KFLOCK helper..."
$CC -O2 -fPIC -shared -o "$BUILD_DIR/KFLOCK.so" cobol/foundation/KFLOCK.c || exit 1

echo "Compiling BGLPST regression test suite..."
$COBC $CFLAGS -x -o "$BUILD_DIR/test_bglpst" \
    tests/test_bglpst_driver.cbl \
    cobol/ledger/BGLPST.cbl \
    cobol/ledger/BJRN.cbl \
    cobol/ledger/BGLCHT.cbl \
    cobol/foundation/BWR.cbl || exit 1

echo "Running BGLPST regression tests..."
export BANK_HOME="${BANK_HOME:-$PWD}"
export COB_LIBRARY_PATH="$BUILD_DIR:${COB_LIBRARY_PATH:-}"

out=$("$BUILD_DIR/test_bglpst")

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

check "Chart of accounts initialization" "test=chart_init rc=00"
check "Initial journal posting success" "test=post_1 rc=00"
check "Lock released after post 1 (no leak in APPEND-POSTINGS)" "test=lock_released_1 status=00"
check "Second sequential posting success" "test=post_2 rc=00"
check "Lock released after post 2" "test=lock_released_2 status=00"

echo ""
echo "Summary: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

exit 0
