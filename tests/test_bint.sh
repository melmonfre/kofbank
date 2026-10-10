#!/usr/bin/env bash
set -uo pipefail

COBC=${COBC:-cobc}
CFLAGS="-free -I copybooks"
BUILD_DIR="build/test_bint"

mkdir -p "$BUILD_DIR"
echo "Compiling BINT regression suite..."
$COBC $CFLAGS -x -o "$BUILD_DIR/test_bint" tests/test_bint_driver.cbl cobol/interest/BINT.cbl || exit 1

echo "Running BINT regression tests..."
out=$("$BUILD_DIR/test_bint")

PASS=0
FAIL=0

check() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        echo "ok   $name"
    else
        FAIL=$((FAIL + 1))
        echo "FAIL $name expected=[$expected] actual=[$actual]"
    fi
}

# 1. Accrue Baseline: 10000 * 0.10 * 30 / 360 = 83.33
check "accrue_baseline" "83.33" "$(grep 'test=accrue_baseline' <<<"$out" | sed 's/.*interest=//')"

# 2. Compound Daily: 10000 * ((1 + 0.10/360)^30 - 1) = 83.68
check "compound_daily" "83.68" "$(grep 'test=compound_daily' <<<"$out" | sed 's/.*interest=//')"

# 3. Compound 365 Days: 10000 * ((1 + 0.12/365)^365 - 1) = 1274.75
check "compound_365" "1274.75" "$(grep 'test=compound_365' <<<"$out" | sed 's/.*interest=//')"

# 4. Bad Basis Rejection
check "compound_bad_basis_rc" "20" "$(grep 'test=compound_bad_basis' <<<"$out" | sed -n 's/.*rc=\([0-9]*\).*/\1/p')"

# 5. Fee Propagation: Fee 45.50 must be assigned to INT-INTEREST
check "fee_propagation" "45.50" "$(grep 'test=fee_propagation' <<<"$out" | sed 's/.*interest=//')"

echo "----------------------------------------"
echo "BINT tests finished: $PASS passed, $FAIL failed."
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
