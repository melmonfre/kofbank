#!/usr/bin/env bash
set -uo pipefail

COBC=${COBC:-cobc}
CC=${CC:-cc}
CFLAGS="-free -I copybooks"
BUILD_DIR="build/test_bacopn"
DATA_DIR="var/data"
JRN_DIR="var/journal"

mkdir -p "$BUILD_DIR"
mkdir -p "$DATA_DIR"
mkdir -p "$JRN_DIR"

# Clean state
rm -f "$DATA_DIR"/acct.idx* "$DATA_DIR"/gl.idx* "$DATA_DIR"/acctbal.idx*
rm -f "$DATA_DIR"/cust.idx* "$DATA_DIR"/lk_*.lck "$DATA_DIR"/jrst.idx*

# Create customer record for C00000000001
export BANK_HOME="${BANK_HOME:-$PWD}"

echo "Building native KFLOCK helper..."
$CC -O2 -fPIC -shared -o "$BUILD_DIR/KFLOCK.so" cobol/foundation/KFLOCK.c || exit 1

echo "Compiling BACOPN regression test suite..."
$COBC $CFLAGS -x -o "$BUILD_DIR/test_bacopn" \
    tests/test_bacopn_driver.cbl \
    cobol/accounts/BACOPN.cbl \
    cobol/customer/BCUSGET.cbl \
    cobol/products/BPRDVAL.cbl \
    cobol/foundation/BCFG.cbl \
    cobol/foundation/BWR.cbl \
    cobol/foundation/BHSH.cbl \
    cobol/foundation/BAUD.cbl \
    cobol/foundation/BEVT.cbl \
    cobol/foundation/BIDM.cbl \
    cobol/ledger/BGLPST.cbl \
    cobol/ledger/BJRN.cbl || exit 1

echo "Seeding test customer..."
$COBC $CFLAGS -x -o "$BUILD_DIR/seed_cust" cobol/customer/BCUSADD.cbl cobol/foundation/BCFG.cbl cobol/foundation/BWR.cbl cobol/foundation/BHSH.cbl cobol/foundation/BAUD.cbl cobol/foundation/BEVT.cbl cobol/foundation/BIDM.cbl || true

export COB_LIBRARY_PATH="$BUILD_DIR:${COB_LIBRARY_PATH:-}"

echo "Running BACOPN regression tests..."
out=$("$BUILD_DIR/test_bacopn")

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

check "Zero-deposit account creation succeeds" "test=open_zero_deposit rc=00"
check "Deposit failure returns error RC" "test=open_failed_deposit rc="
check "Ghost account is rolled back from disk (status=23)" "test=ghost_account_deleted status=ROLLED_BACK"

echo ""
echo "Summary: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

exit 0
