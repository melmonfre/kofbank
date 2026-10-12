#!/usr/bin/env bash
set -uo pipefail

COBC=${COBC:-cobc}
CFLAGS="-free -I copybooks"
BUILD_DIR="build/test_btxnval"
DATA_DIR="var/data"

mkdir -p "$BUILD_DIR"
mkdir -p "$DATA_DIR"

# Clean credit storage index
rm -f "$DATA_DIR"/crexp.idx*

echo "Compiling BTXNVAL regression test suite..."
$COBC $CFLAGS -x -o "$BUILD_DIR/test_btxnval" \
    tests/test_btxnval_driver.cbl \
    cobol/transactions/BTXNVAL.cbl \
    cobol/credit/BCRUPD.cbl \
    cobol/credit/BCRXSTO.cbl \
    cobol/foundation/BWR.cbl \
    cobol/foundation/BHSH.cbl || exit 1

echo "Running BTXNVAL regression tests..."
export BANK_HOME="${BANK_HOME:-$PWD}"

out=$("$BUILD_DIR/test_btxnval")

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

check "Valid charge within credit headroom accepted" "test=charge_valid rc=00"
check "Over-limit charge rejected with EXCEEDS CREDIT FACILITY LIMIT" "test=charge_overlimit rc=20 msg=EXCEEDS CREDIT FACILITY LIMIT"
check "Charge on closed facility rejected" "test=charge_closed rc=20 msg=FACILITY CLOSED"
check "Charge on inactive facility rejected" "test=charge_inactive rc=20 msg=FACILITY NOT ACTIVE"

echo ""
echo "Summary: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

exit 0
