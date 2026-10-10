#!/usr/bin/env bash
set -uo pipefail

BANK="build/bank"
PASS=0
FAIL=0
CFG=etc/bank.cfg
CFG_BAK=$(mktemp)
sed -i 's/^business-date=.*/business-date=2026-10-02/' "$CFG"
cp "$CFG" "$CFG_BAK"
trap 'cp "$CFG_BAK" "$CFG"; rm -f "$CFG_BAK"' EXIT

bank() { printf '%s\n' "$1" | "$BANK"; }

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

value() {
    grep -F "$2" <<<"$1" | head -1 | sed 's/^[^=]*=//' | tr -d ' '
}

reset() {
    rm -rf var/data var/journal var/audit var/run var/bkp
    rm -rf var/data.precall.*
    mkdir -p var/data var/journal var/audit var/run
}

if [ "${1:-}" = "--reset-only" ]; then
    export COB_LIBRARY_PATH="${COB_LIBRARY_PATH:-$PWD/build}"
    reset
    bank "ledger.init" >/dev/null
    exit 0
fi

reset

bank "ledger.init" >/dev/null
out=$(bank "customer.create|P|MARIA SOUZA|CPF|98765432100|19900202|OP01|R1")
check "customer.create" "C00000000001" "$(value "$out" id=)"

out=$(bank "account.open|C00000000001|DMND|BRL|500000|OP01|R2|O1")
check "account.open" "A00000000001" "$(value "$out" id=)"
out=$(bank "account.find|C00000000001")
check "account.find.rc" "00" "$(value "$out" rc=)"
check "account.find.count" "000001" "$(value "$out" count=)"
check "account.find.id" "A00000000001" "$(printf '%s' "$out" | grep '^id=' | head -1 | cut -d' ' -f1 | sed 's/^id=//')"
out=$(bank "account.find|C99999999999")
check "account.find.none" "000000" "$(value "$out" count=)"

mkdir -p tests/fixtures
printf 'JRNA00000000001|500000.00|BRL|20261002\n' > tests/fixtures/ext_ok.dat
out=$(bank "reconciliation.run|EXTERNAL|REC-EXT-OK|tests/fixtures/ext_ok.dat|OP1|C0")
check "recon.external.balanced.rc" "00" "$(value "$out" rc=)"
check "recon.external.balanced.status" "BALANCED" "$(value "$out" msg=)"

out=$(bank "txn.create|DEPOSIT||A00000000001|250000|BRL|SALARIO|OP01|R3|D11")
check "txn.create.deposit" "T00000000001" "$(value "$out" id=)"
check "txn.create.deposit.status" "VA" "$(value "$out" status=)"
out=$(bank "txn.authorize|T00000000001|OP01|R3|D2")
check "txn.authorize" "AU" "$(value "$out" status=)"
out=$(bank "txn.post|T00000000001|OP01|R3|D3")
check "txn.post" "PO" "$(value "$out" status=)"
out=$(bank "txn.settle|T00000000001|OP01|R3|D4")
check "txn.settle" "ST" "$(value "$out" status=)"
out=$(bank "ledger.balance|A00000000001")
check "txn.deposit.posted" "750000.00" "$(value "$out" ledger=)"
out=$(bank "txn.complete|T00000000001|OP01|R3|D5")
check "txn.complete" "CP" "$(value "$out" status=)"
out=$(bank "txn.list")
check "txn.list.dst" "yes" "$(printf '%s' "$out" | grep -q 'dst=A00000000001' && echo yes || echo no)"
check "txn.list.created" "yes" "$(printf '%s' "$out" | grep -q ' created=[0-9]' && echo yes || echo no)"
out=$(bank "txn.get|T00000000001")
check "txn.get.status" "CP" "$(value "$out" status=)"
check "txn.get.type" "DEPOSIT" "$(value "$out" type=)"
check "txn.get.amount" "250000.00" "$(value "$out" amount=)"

out=$(bank "txn.create|WITHDRAW|A00000000001||100000|BRL|SAQUE|OP01|R4|W11")
check "txn.create.withdraw" "T00000000002" "$(value "$out" id=)"
out=$(bank "txn.authorize|T00000000002|OP01|R4|W2")
out=$(bank "txn.post|T00000000002|OP01|R4|W3")
out=$(bank "txn.settle|T00000000002|OP01|R4|W4")
check "txn.withdraw" "ST" "$(value "$out" status=)"

out=$(bank "ledger.balance|A00000000001")
check "balance.ledger" "650000.00" "$(value "$out" ledger=)"
check "balance.available" "650000.00" "$(value "$out" available=)"

out=$(bank "txn.create|WITHDRAW|A00000000001||9999999|BRL|SAQUE|OP01|R5|W15")
check "txn.withdraw.insufficient" "20" "$(value "$out" rc=)"

out=$(bank "txn.create|DEPOSIT||A00000000001|250000|BRL|SALARIO|OP01|R3|D11")
check "txn.replay.id" "T00000000001" "$(value "$out" id=)"
out=$(bank "ledger.balance|A00000000001")
check "replay.no.double.post" "650000.00" "$(value "$out" ledger=)"

out=$(bank "ledger.trial")
td=$(value "$out" total-debit=)
tc=$(value "$out" total-credit=)
check "invariant.debit.equals.credit" "$td" "$tc"
check "trial.balanced" "00" "$(value "$out" rc=)"

posted=$(bank "ledger.postings|" | grep -c '^gl=' || true)
check "postings.count" "6" "$posted"

out=$(bank "account.open|C00000000001|DMND|BRL|100000|OP01|R6|O2")
check "payment.account.open" "A00000000002" "$(value "$out" id=)"

out=$(bank "account.open|C00000000001|DMND|BRL|100000|OP01|R21|O21")
check "lifecycle.account.open" "A00000000003" "$(value "$out" id=)"
out=$(bank "txn.create|FEE|A00000000001||1000|BRL|TARIFA|OP01|R22|FEE11")
check "txn.create.fee" "T00000000003" "$(value "$out" id=)"
out=$(bank "txn.authorize|T00000000003|OP01|R22|FEE2")
out=$(bank "txn.post|T00000000003|OP01|R22|FEE3")
out=$(bank "txn.settle|T00000000003|OP01|R22|FEE4")
check "txn.fee.settled" "ST" "$(value "$out" status=)"
out=$(bank "ledger.balance|A00000000001")
check "txn.fee.balance" "649000.00" "$(value "$out" ledger=)"

out=$(bank "txn.create|TRANSFER|A00000000001|A00000000003|50000|BRL|TRANSF|OP01|R23|TRF11")
check "txn.create.transfer" "T00000000004" "$(value "$out" id=)"
out=$(bank "txn.authorize|T00000000004|OP01|R23|TRF2")
out=$(bank "txn.post|T00000000004|OP01|R23|TRF3")
out=$(bank "txn.settle|T00000000004|OP01|R23|TRF4")
out=$(bank "txn.complete|T00000000004|OP01|R23|TRF5")
check "txn.transfer.completed" "CP" "$(value "$out" status=)"
out=$(bank "ledger.balance|A00000000001")
check "txn.transfer.src" "599000.00" "$(value "$out" ledger=)"
out=$(bank "ledger.balance|A00000000003")
check "txn.transfer.dst" "150000.00" "$(value "$out" ledger=)"

out=$(bank "txn.create|WITHDRAW|A00000000003||5000|BRL|CANCEL|OP01|R24|CAN11")
check "txn.create.cancel" "T00000000005" "$(value "$out" id=)"
out=$(bank "txn.cancel|T00000000005|DESISTI|OP01|R24|CAN2")
check "txn.cancel" "CN" "$(value "$out" status=)"
out=$(bank "ledger.balance|A00000000003")
check "txn.cancel.no.effect" "150000.00" "$(value "$out" ledger=)"

out=$(bank "txn.return|T00000000004|DEVOLVE|OP02|R25|RTN11")
check "txn.return" "RT" "$(value "$out" status=)"
out=$(bank "ledger.balance|A00000000001")
check "txn.return.src" "649000.00" "$(value "$out" ledger=)"
out=$(bank "ledger.balance|A00000000003")
check "txn.return.dst" "100000.00" "$(value "$out" ledger=)"

out=$(bank "txn.reverse|T00000000001|ESTORNO|OP02|R26|REV11")
check "txn.reverse" "RV" "$(value "$out" status=)"
out=$(bank "ledger.balance|A00000000001")
check "txn.reverse.balance" "399000.00" "$(value "$out" ledger=)"

out=$(bank "txn.post|T00000000004|OP01|R27|BAD11")
check "txn.invalid.transition" "20" "$(value "$out" rc=)"
out=$(bank "txn.return|T00000000005|X|OP01|R28|BAD12")
check "txn.return.not.settled" "20" "$(value "$out" rc=)"

out=$(bank "reconciliation.run|TXN")
check "recon.txn.balanced" "BALANCED" "$(value "$out" msg=)"

out=$(bank "ledger.trial")
td=$(value "$out" total-debit=)
tc=$(value "$out" total-credit=)
check "txn.invariant.debit.equals.credit" "$td" "$tc"

out=$(bank "payment.create|INTERNAL|INTERNAL|A00000000001|A00000000002|150000|BRL|PAGAMENTO|OP01|R7|PAYREQ1|IDEM1")
check "payment.create" "P00000000001" "$(value "$out" id=)"
check "payment.create.status" "ST" "$(value "$out" status=)"

out=$(bank "limits.check|CHANNEL|PAY|DAILY|0|BRL")
check "payment.limit.consumed" "150000.00" "$(value "$out" used=)"

out=$(bank "payment.get|P00000000001")
check "payment.get.status" "ST" "$(value "$out" status=)"
check "payment.get.amount" "150000.00" "$(value "$out" amount=)"

out=$(bank "payment.create|INTERNAL|INTERNAL|A00000000001|A00000000002|150000|BRL|PAGAMENTO|OP01|R7|PAYREQ1|IDEM1")
check "payment.replay.id" "P00000000001" "$(value "$out" id=)"
check "payment.replay.status" "ST" "$(value "$out" status=)"

out=$(bank "payment.create|INTERNAL|INTERNAL|A00000000001|A00000000002|999999|BRL|X|OP01|R8|PAYREQ2|IDEM1")
check "payment.idem.conflict" "20" "$(value "$out" rc=)"

out=$(bank "payment.create|INTERNAL|INTERNAL|A00000000001|A00000000002|999999|BRL|X|OP01|R9|PAYREQ3|IDEM3")
check "payment.insufficient" "20" "$(value "$out" rc=)"

out=$(bank "payment.create|INTERNAL|INTERNAL|A00000000009|A00000000002|100|BRL|X|OP01|R10|PAYREQ4|IDEM4")
check "payment.bad.account" "20" "$(value "$out" rc=)"

out=$(bank "payment.return|P00000000001|DEFEITO|OP02|R11|RTN1")
check "payment.return" "RT" "$(value "$out" status=)"

out=$(bank "payment.return|P00000000001|DEFEITO|OP02|R11|RTN1")
check "payment.return.replay" "RT" "$(value "$out" status=)"

out=$(bank "limits.check|CHANNEL|PAY|DAILY|0|BRL")
check "payment.limit.released" "0.00" "$(value "$out" used=)"

out=$(bank "payment.reverse|P00000000001|ESTORNO|OP02|R12|REV1")
check "payment.reverse.invalid" "20" "$(value "$out" rc=)"

out=$(bank "payment.create|INTERNAL|INTERNAL|A00000000002|A00000000001|50000|BRL|OUTRO|OP01|R13|PAYREQ5|IDEM5")
check "payment.create2" "P00000000002" "$(value "$out" id=)"

out=$(bank "payment.reverse|P00000000002|ESTORNO|OP02|R14|REV2")
check "payment.reverse" "RV" "$(value "$out" status=)"

out=$(bank "ledger.balance|A00000000001")
check "payment.balance.src" "399000.00" "$(value "$out" ledger=)"
out=$(bank "ledger.balance|A00000000002")
check "payment.balance.dst" "100000.00" "$(value "$out" ledger=)"

out=$(bank "ledger.trial")
td=$(value "$out" total-debit=)
tc=$(value "$out" total-credit=)
check "payment.invariant.debit.equals.credit" "$td" "$tc"

out=$(bank "product.init")
check "product.init" "00010" "$(value "$out" products=)"
check "product.init.rc" "00" "$(value "$out" rc=)"

out=$(bank "product.get|DMND")
check "product.effective.version" "00002" "$(value "$out" version=)"
check "product.effective.daily" "2000000.00" "$(value "$out" daily-limit=)"
check "product.effective.type" "DEMAND" "$(value "$out" type=)"

out=$(bank "product.get|ZZZZ")
check "product.missing" "23" "$(value "$out" rc=)"

out=$(bank "interest.accrue|100000|1200|30|365")
check "interest.accrue.rc" "00" "$(value "$out" rc=)"
check "interest.accrue.amount" "986.30" "$(value "$out" interest=)"

out=$(bank "interest.accrue|100000|1200|0|365")
check "interest.accrue.bad-days" "20" "$(value "$out" rc=)"

out=$(bank "limits.check|ACCOUNT|A00000000001|DAILY|5000001|BRL")
check "limits.exceeded" "20" "$(value "$out" rc=)"

out=$(bank "limits.check|ACCOUNT|A00000000001|DAILY|100000|BRL")
check "limits.within" "00" "$(value "$out" rc=)"

out=$(bank "account.open|C00000000001|BUSN|BRL|0|OP01|R16|O3")
check "product.minimum.balance" "20" "$(value "$out" rc=)"

out=$(bank "reconciliation.run|LEDGER")
check "recon.ledger.rc" "00" "$(value "$out" rc=)"
check "recon.ledger.balanced" "BALANCED" "$(value "$out" msg=)"

out=$(bank "reconciliation.run|LEDGER")
check "recon.ledger.idempotent" "24" "$(value "$out" rc=)"

out=$(bank "reconciliation.run|PAYMENT")
check "recon.payment.balanced" "BALANCED" "$(value "$out" msg=)"

out=$(bank "reconciliation.get|REC-LEDGER-20261002")
check "recon.get.rc" "00" "$(value "$out" rc=)"
check "recon.get.type" "LEDGER" "$(value "$out" type=)"

out=$(bank "reconciliation.list")
check "recon.list.rc" "00" "$(value "$out" rc=)"

printf 'GLP|2000|D|          77.00|A00000000009|BRL|JRNORPH1|20261002\n' >> var/journal/postings.log
printf 'GLP|2000|C|          77.00|A00000000009|BRL|JRNORPH1|20261002\n' >> var/journal/postings.log
out=$(bank "reconciliation.run|LEDGER|REC-RECON-LEDGER")
check "recon.ledger.exceptions" "EXCEPTIONS" "$(value "$out" msg=)"

out=$(bank "reconciliation.exceptions|REC-RECON-LEDGER")
check "recon.exception.orphan" "1" "$(printf '%s' "$out" | grep -c 'code=ORPHAN')"

exc=$(printf '%s' "$out" | grep -o 'exc=[A-Z0-9]*' | head -1 | cut -d= -f2)
out=$(bank "reconciliation.resolve|$exc|ACCEPT||OP02|manual")
check "recon.resolve.accept" "00" "$(value "$out" rc=)"
out=$(bank "reconciliation.get|REC-RECON-LEDGER")
check "recon.resolve.open" "000000000" "$(value "$out" open=)"
check "recon.resolve.balanced" "BALANCED" "$(value "$out" status=)"

grep -v '|JRNORPH1|' var/journal/postings.log > /tmp/kofbank.postings.jclean
mv /tmp/kofbank.postings.jclean var/journal/postings.log

out=$(bank "reconciliation.resolve|E99999999999|ACCEPT||OP02|x")
check "recon.resolve.missing" "23" "$(value "$out" rc=)"
out=$(bank "reconciliation.resolve|$exc|ADJUST||OP02|")
check "recon.resolve.adjust.noref" "20" "$(value "$out" rc=)"
out=$(bank "reconciliation.resolve|$exc|ADJUST|ADJTXN1|OP02|approved")
check "recon.resolve.adjust" "00" "$(value "$out" rc=)"
out=$(bank "reconciliation.get|REC-RECON-LEDGER")
check "recon.resolve.adjustments" "000000001" "$(value "$out" adjustments=)"

printf 'JRNA00000000001|999999.00|BRL|20261002\n' > tests/fixtures/ext_bad.dat
out=$(bank "reconciliation.run|EXTERNAL|REC-EXT-BAD|tests/fixtures/ext_bad.dat|OP1|C9")
check "recon.external.amount" "EXCEPTIONS" "$(value "$out" msg=)"
out=$(bank "reconciliation.exceptions|REC-EXT-BAD")
check "recon.external.amount.code" "1" "$(printf '%s' "$out" | grep -c 'code=AMOUNT')"

printf 'JRNA00000000001|500000.00|BRL|20261002\nJRNA00000000001|500000.00|BRL|20261002\n' > tests/fixtures/ext_dup.dat
out=$(bank "reconciliation.run|EXTERNAL|REC-EXT-DUP|tests/fixtures/ext_dup.dat|OP1|C10")
out=$(bank "reconciliation.exceptions|REC-EXT-DUP")
check "recon.external.duplicate.code" "1" "$(printf '%s' "$out" | grep -c 'code=DUPLICATE')"

printf 'JRNA00000000001|500000.00|BRL|20261003\n' > tests/fixtures/ext_dt.dat
out=$(bank "reconciliation.run|EXTERNAL|REC-EXT-DATE|tests/fixtures/ext_dt.dat|OP1|C11")
check "recon.external.date.status" "EXCEPTIONS" "$(value "$out" msg=)"
out=$(bank "reconciliation.exceptions|REC-EXT-DATE")
check "recon.external.date.code" "1" "$(printf '%s' "$out" | grep -c 'code=DATE')"

printf 'GLP|2000|D|          8765.43|A00000000001|BRL|JRNFB10000000001|20261002\n' >> var/journal/postings.log
printf 'GLP|2000|C|          8765.43|A00000000002|BRL|JRNFB10000000001|20261002\n' >> var/journal/postings.log
printf '|8765.43|BRL|20261002\n' > tests/fixtures/ext_fb.dat
out=$(bank "reconciliation.run|EXTERNAL|REC-EXT-FB|tests/fixtures/ext_fb.dat|OP1|C12")
out=$(bank "reconciliation.exceptions|REC-EXT-FB")
check "recon.external.fallback.matched" "0" "$(printf '%s' "$out" | grep -c 'key=8765.43')"
out=$(bank "reconciliation.get|REC-EXT-FB")
check "recon.external.fallback.count" "000000001" "$(value "$out" matched=)"

printf 'GLP|2000|D|          4321.09|A00000000001|BRL|JRNFB20000000001|20261002\n' >> var/journal/postings.log
printf 'GLP|2000|C|          4321.09|A00000000002|BRL|JRNFB20000000001|20261002\n' >> var/journal/postings.log
printf 'GLP|2000|D|          4321.09|A00000000001|BRL|JRNFB20000000002|20261002\n' >> var/journal/postings.log
printf 'GLP|2000|C|          4321.09|A00000000002|BRL|JRNFB20000000002|20261002\n' >> var/journal/postings.log
printf '|4321.09|BRL|20261002\n' > tests/fixtures/ext_amb.dat
out=$(bank "reconciliation.run|EXTERNAL|REC-EXT-AMB|tests/fixtures/ext_amb.dat|OP1|C13")
check "recon.external.ambiguous.status" "EXCEPTIONS" "$(value "$out" msg=)"
out=$(bank "reconciliation.exceptions|REC-EXT-AMB")
check "recon.external.ambiguous.code" "1" "$(printf '%s' "$out" | grep -c 'code=AMBIGUOUS')"

out=$(bank "reconciliation.run|EXTERNAL|REC-EXT-MISS|tests/fixtures/nope.dat|OP1|C14")
check "recon.external.missing.rc" "35" "$(value "$out" rc=)"
check "recon.external.missing.msg" "EXTERNALFILEMISSING" "$(value "$out" msg=)"
out=$(bank "reconciliation.get|REC-EXT-MISS")
check "recon.external.missing.status" "FAILED" "$(value "$out" status=)"
out=$(bank "reconciliation.run|EXTERNAL|REC-EXT-MISS|tests/fixtures/ext_ok.dat|OP1|C15")
check "recon.failed.resume.rc" "00" "$(value "$out" rc=)"
out=$(bank "reconciliation.get|REC-EXT-MISS")
check "recon.failed.resume.matched" "000000001" "$(value "$out" matched=)"
check "recon.failed.resume.cleared" "00" "$(value "$out" rc=)"

grep -v '|JRNFB' var/journal/postings.log > /tmp/kofbank.postings.fbclean
mv /tmp/kofbank.postings.fbclean var/journal/postings.log

printf 'GLP|2000|D|          55.00|A00000000001|BRL|PAYGHOST1|20261002\n' >> var/journal/postings.log
printf 'GLP|2000|C|          55.00|A00000000002|BRL|PAYGHOST1|20261002\n' >> var/journal/postings.log
out=$(bank "reconciliation.run|PAYMENT|REC-PAY-GHOST")
check "recon.payment.orphan" "EXCEPTIONS" "$(value "$out" msg=)"
out=$(bank "reconciliation.exceptions|REC-PAY-GHOST")
check "recon.payment.orphan.code" "1" "$(printf '%s' "$out" | grep -c 'code=ORPHAN')"

aud=$(grep -c 'REC.RESOLVE' var/audit/audit.log || true)
check "recon.audit.trail" "2" "$aud"

out=$(bank "ledger.trial")
td=$(value "$out" total-debit=)
tc=$(value "$out" total-credit=)
check "recon.invariant.debit.equals.credit" "$td" "$tc"

cp var/journal/postings.log /tmp/kofbank.postings.bak
grep -v '|PAY00000000001|' /tmp/kofbank.postings.bak > /tmp/kofbank.postings.tmp
mv /tmp/kofbank.postings.tmp var/journal/postings.log
out=$(bank "reconciliation.run|LEDGER|REC-BAL-MISMATCH")
check "recon.balance.mismatch" "EXCEPTIONS" "$(value "$out" msg=)"
out=$(bank "reconciliation.exceptions|REC-BAL-MISMATCH")
check "recon.balance.mismatch.code" "2" "$(printf '%s' "$out" | grep -c 'code=MISMATCH')"
grep -v '|PAYGHOST1|' /tmp/kofbank.postings.bak > var/journal/postings.log

out=$(bank "batch.eod|OP01|R15|EOD1")
check "payment.eod" "00" "$(value "$out" rc=)"
check "recon.eod.report" "1" "$(grep -c 'RECON-LEDGER' var/out/eod_20261002.txt || true)"

printf 'GLP|2000|D|          99.00|A00000000007|BRL|GHOSTEOD|20261002\n' >> var/journal/postings.log
printf 'GLP|2000|C|          99.00|A00000000007|BRL|GHOSTEOD|20261002\n' >> var/journal/postings.log
cp etc/bank.cfg "$CFG_BAK"
sed -i 's/business-date=.*/business-date=2026-10-03/' etc/bank.cfg
out=$(bank "batch.eod|OP01|R99|EOD9")
check "recon.eod.fails.open" "20" "$(value "$out" rc=)"

cp "$CFG_BAK" etc/bank.cfg

reset
bank "ledger.init" >/dev/null
bank "customer.create|P|JOAO|CPF|11122233344|19850101|OP01|C1" >/dev/null
bank "account.open|C00000000001|DMND|BRL|0|OP01|C2|CO1" >/dev/null

out=$(bank "credit.application.create|C00000000001|LNPR|A00000000001|100000|12|OP01|C3|CAP1")
check "credit.application.create" "L00000000001" "$(value "$out" application=)"
check "credit.application.create.rc" "00" "$(value "$out" rc=)"
out=$(bank "credit.application.get|L00000000001")
check "credit.application.get.status" "UND" "$(value "$out" status=)"
out=$(bank "credit.application.create|C00000000001|LNPR|A00000000001|0|12|OP01|C4|CAP2")
check "credit.application.zero.amount" "20" "$(value "$out" rc=)"
out=$(bank "credit.application.create|C00000000001|DMND|A00000000001|1000|12|OP01|C5|CAP3")
check "credit.application.not.credit" "20" "$(value "$out" rc=)"
out=$(bank "credit.application.create|C00000000001|LNPR|A00000000001|999999999|12|OP01|C6|CAP4")
check "credit.application.over.max" "20" "$(value "$out" rc=)"
out=$(bank "credit.application.create|C00000000001|LNPR|A00000000001|100000|99|OP01|C7|CAP5")
check "credit.application.over.term" "20" "$(value "$out" rc=)"
out=$(bank "credit.application.approve|L00000000001|100000||OP01|C8|CAP6")
check "credit.application.approve" "00" "$(value "$out" rc=)"
out=$(bank "credit.application.approve|L00000000001|100000||OP01|C8|CAP6")
check "credit.application.approve.replay" "00" "$(value "$out" rc=)"
out=$(bank "credit.application.get|L00000000001")
check "credit.application.approved" "APV" "$(value "$out" status=)"
check "credit.application.approved.amount" "100000.00" "$(value "$out" approved=)"

out=$(bank "credit.facility.originate|L00000000001|A00000000001|20271002|COLL1|OP01|C9|CF1")
check "credit.facility.originate" "F00000000001" "$(value "$out" facility=)"
out=$(bank "credit.facility.contract|F00000000001||||OP01|C10|CF2")
check "credit.facility.contract.before.approve" "20" "$(value "$out" rc=)"
out=$(bank "credit.facility.approve|F00000000001||OP01|C11|CF3")
check "credit.facility.approve" "00" "$(value "$out" rc=)"
out=$(bank "credit.facility.contract|F00000000001||||OP01|C12|CF4")
check "credit.facility.contract" "00" "$(value "$out" rc=)"
out=$(bank "credit.facility.get|F00000000001")
check "credit.facility.contracted.status" "CON" "$(value "$out" status=)"
check "credit.facility.contracted.amount" "100000.00" "$(value "$out" contracted=)"
out=$(bank "credit.facility.activate|F00000000001||OP01|C13|CF5")
check "credit.facility.activate" "00" "$(value "$out" rc=)"
out=$(bank "credit.facility.get|F00000000001")
check "credit.facility.active" "ACT" "$(value "$out" status=)"

out=$(bank "credit.facility.schedule|F00000000001|100000|2400|360|12|20261002")
check "credit.schedule.count" "0012" "$(value "$out" installments=)"
out=$(bank "credit.installment.get|F00000000001|1")
check "credit.installment.1.principal" "8333.33" "$(value "$out" principal=)"
check "credit.installment.1.interest" "2066.66" "$(value "$out" interest=)"
out=$(bank "credit.installment.get|F00000000001|12")
check "credit.installment.12.principal" "8333.37" "$(value "$out" principal=)"

out=$(bank "credit.disbursement.create|F00000000001|100000|0|OP01|C14|CD1")
check "credit.disbursement" "00" "$(value "$out" rc=)"
check "credit.disbursement.txn" "T00000000001" "$(value "$out" txn=)"
out=$(bank "credit.disbursement.create|F00000000001|100000|0|OP01|C14|CD1")
check "credit.disbursement.replay" "T00000000001" "$(value "$out" txn=)"
out=$(bank "ledger.balance|A00000000001")
check "credit.disbursement.balance" "100000.00" "$(value "$out" ledger=)"
out=$(bank "credit.facility.exposure|F00000000001")
check "credit.exposure.principal" "100000.00" "$(value "$out" principal=)"
check "credit.exposure.utilized" "100000.00" "$(value "$out" utilized=)"
check "credit.exposure.available" "0.00" "$(value "$out" available=)"
out=$(bank "credit.disbursement.create|F00000000001|1|0|OP01|C15|CD2")
check "credit.disbursement.overlimit" "20" "$(value "$out" rc=)"

out=$(bank "credit.repayment.create|F00000000001|10000|OP01|C16|CR1")
check "credit.repayment" "00" "$(value "$out" rc=)"
check "credit.repayment.principal" "+000000000007933.34" "$(value "$out" principal=)"
check "credit.repayment.interest" "+000000000002066.66" "$(value "$out" interest=)"
out=$(bank "ledger.balance|A00000000001")
check "credit.repayment.balance" "90000.00" "$(value "$out" ledger=)"
out=$(bank "credit.installment.get|F00000000001|1")
check "credit.installment.partial" "PT" "$(value "$out" status=)"
out=$(bank "credit.facility.exposure|F00000000001")
check "credit.exposure.after.repay" "92066.66" "$(value "$out" principal=)"

out=$(bank "credit.writeoff.create|F00000000001|5000|FRAUDE|OP01|C17|CW1")
check "credit.writeoff" "00" "$(value "$out" rc=)"
out=$(bank "credit.facility.exposure|F00000000001")
check "credit.exposure.after.writeoff" "87066.66" "$(value "$out" principal=)"
out=$(bank "credit.facility.mature|F00000000001|X|OP01|C18|CF6")
check "credit.facility.mature.outstanding" "20" "$(value "$out" rc=)"

out=$(bank "reconciliation.run|CREDIT|REC-CRD")
check "credit.recon.balanced" "BALANCED" "$(value "$out" msg=)"
out=$(bank "batch.eod|OP01|C19|CEOD")
check "credit.eod" "00" "$(value "$out" rc=)"

reset
bank "ledger.init" >/dev/null
bank "customer.create|P|ANA|CPF|22233344455|19900303|OP01|D1" >/dev/null
bank "account.open|C00000000001|DMND|BRL|0|OP01|D2|DO1" >/dev/null
bank "credit.application.create|C00000000001|LNPR|A00000000001|100000|12|OP01|D3|DAP1" >/dev/null
bank "credit.application.approve|L00000000001|100000||OP01|D4|DAP2" >/dev/null
bank "credit.facility.originate|L00000000001|A00000000001|20271002|COLL1|OP01|D5|DF1" >/dev/null
bank "credit.facility.approve|F00000000001||OP01|D6|DF2" >/dev/null
bank "credit.facility.contract|F00000000001||||OP01|D7|DF3" >/dev/null
bank "credit.facility.activate|F00000000001||OP01|D8|DF4" >/dev/null
bank "credit.facility.schedule|F00000000001|100000|2400|360|12|20261002" >/dev/null
bank "credit.disbursement.create|F00000000001|100000|0|OP01|D9|DD1" >/dev/null
cp etc/bank.cfg "$CFG_BAK"
sed -i 's/business-date=.*/business-date=2027-01-15/' etc/bank.cfg
out=$(bank "batch.eod|OP01|D10|DEOD")
check "credit.eod.overdue.rc" "00" "$(value "$out" rc=)"
out=$(bank "credit.facility.exposure|F00000000001")
check "credit.eod.overdue.amount" "30622.20" "$(value "$out" overdue=)"
out=$(bank "reconciliation.run|CREDIT|REC-CRD2")
check "credit.recon.after.eod" "BALANCED" "$(value "$out" msg=)"

cp "$CFG_BAK" etc/bank.cfg

setup_credit_facility() {
    bank "ledger.init" >/dev/null
    bank "customer.create|P|ANA|CPF|22233344455|19900303|OP01|S1" >/dev/null
    bank "account.open|C00000000001|DMND|BRL|0|OP01|S2|SO1" >/dev/null
    bank "credit.application.create|C00000000001|LNPR|A00000000001|100000|12|OP01|S3|SAP1" >/dev/null
    bank "credit.application.approve|L00000000001|100000||OP01|S4|SAP2" >/dev/null
    bank "credit.facility.originate|L00000000001|A00000000001|20271002|COLL1|OP01|S5|SF1" >/dev/null
    bank "credit.facility.approve|F00000000001||OP01|S6|SF2" >/dev/null
    bank "credit.facility.contract|F00000000001||||OP01|S7|SF3" >/dev/null
    bank "credit.facility.activate|F00000000001||OP01|S8|SF4" >/dev/null
}

setup_active_loan() {
    setup_credit_facility
    bank "loan.create|F00000000001|100000|12|CSPR|1|OP01|N1|NL1" >/dev/null
    bank "loan.approve|N00000000001||OP01|N2|NL2" >/dev/null
    bank "loan.contract|N00000000001||OP01|N3|NL3" >/dev/null
    bank "loan.activate|N00000000001||OP01|N4|NL4" >/dev/null
    bank "loan.schedule|N00000000001" >/dev/null
}

reset
setup_credit_facility

out=$(bank "loan.create|F00000000001|100000|12|CSPR|1|OP01|LA1|LC1")
check "loan.create" "N00000000001" "$(value "$out" loan=)"
check "loan.create.status" "REQ" "$(value "$out" status=)"
check "loan.create.rc" "00" "$(value "$out" rc=)"
out=$(bank "loan.create|F00000000001|100000|12|XXXX|1|OP01|LA2|LC2")
check "loan.create.bad.amort" "20" "$(value "$out" rc=)"
out=$(bank "loan.create|F00000000001|100000|12|CSPR|2|OP01|LA3|LC3")
check "loan.create.bad.freq" "20" "$(value "$out" rc=)"
out=$(bank "loan.contract|N00000000001||OP01|LA4|LC4")
check "loan.contract.before.approve" "20" "$(value "$out" rc=)"
out=$(bank "loan.approve|N00000000001||OP01|LA5|LC5")
check "loan.approve" "APV" "$(value "$out" status=)"
out=$(bank "loan.contract|N00000000001||OP01|LA6|LC6")
check "loan.contract" "CON" "$(value "$out" status=)"
out=$(bank "loan.get|N00000000001")
check "loan.contract.first-due" "20261102" "$(value "$out" first-due=)"
check "loan.contract.maturity" "20271002" "$(value "$out" maturity=)"
out=$(bank "loan.activate|N00000000001||OP01|LA7|LC7")
check "loan.activate" "ACT" "$(value "$out" status=)"
out=$(bank "loan.schedule|N00000000001")
check "loan.schedule" "0012" "$(value "$out" installments=)"
out=$(bank "loan.installment.get|N00000000001|1")
check "loan.installment.1.principal" "8333.33" "$(value "$out" principal=)"
check "loan.installment.1.interest" "2066.66" "$(value "$out" interest=)"
out=$(bank "loan.installment.get|N00000000001|12")
check "loan.installment.12.principal" "8333.37" "$(value "$out" principal=)"
out=$(bank "loan.contract|N00000000001||OP01|LA8|LC8")
check "loan.invalid.transition" "20" "$(value "$out" rc=)"
out=$(bank "loan.activate|N00000000009||OP01|LA9|LC9")
check "loan.not.found" "23" "$(value "$out" rc=)"

reset
setup_active_loan

out=$(bank "loan.disburse|N00000000001|100000|0|OP01|LB1|LD1")
check "loan.disbursement" "00" "$(value "$out" rc=)"
check "loan.disbursement.txn" "T00000000001" "$(value "$out" txn=)"
out=$(bank "loan.disburse|N00000000001|100000|0|OP01|LB1|LD1")
check "loan.disbursement.replay" "T00000000001" "$(value "$out" txn=)"
out=$(bank "ledger.balance|A00000000001")
check "loan.disbursement.balance" "100000.00" "$(value "$out" ledger=)"
out=$(bank "loan.disburse|N00000000001|1|0|OP01|LB2|LD2")
check "loan.disbursement.already" "20" "$(value "$out" rc=)"
out=$(bank "loan.exposure|N00000000001")
check "loan.exposure.outstanding" "100000.00" "$(value "$out" outstanding=)"
out=$(bank "loan.repay|N00000000001|10000|OP01|LB3|LR1")
check "loan.repayment" "00" "$(value "$out" rc=)"
check "loan.repayment.principal" "+000000000007933.34" "$(value "$out" principal=)"
check "loan.repayment.interest" "+000000000002066.66" "$(value "$out" interest=)"
out=$(bank "loan.installment.get|N00000000001|1")
check "loan.installment.partial" "PT" "$(value "$out" status=)"
out=$(bank "loan.exposure|N00000000001")
check "loan.exposure.after.repay" "92066.66" "$(value "$out" outstanding=)"
out=$(bank "loan.repay|N00000000009|100|OP01|LB4|LR2")
check "loan.repay.not.found" "23" "$(value "$out" rc=)"
out=$(bank "loan.writeoff|N00000000001|5000|FRAUDE|OP01|LB5|LW1")
check "loan.writeoff" "00" "$(value "$out" rc=)"
out=$(bank "loan.get|N00000000001")
check "loan.writeoff.outstanding" "87066.66" "$(value "$out" outstanding=)"
check "loan.writeoff.written-off" "5000.00" "$(value "$out" written-off=)"
out=$(bank "loan.writeoff|N00000000001|9999999|X|OP01|LB6|LW2")
check "loan.writeoff.exceeds" "20" "$(value "$out" rc=)"
out=$(bank "loan.default|N00000000001|INADIMPLENCIA|OP01|LB7|LDEF")
check "loan.default" "DEF" "$(value "$out" status=)"
out=$(bank "reconciliation.run|LOAN|REC-LN-B")
check "loan.recon.balanced" "BALANCED" "$(value "$out" msg=)"

reset
setup_active_loan
bank "loan.disburse|N00000000001|100000|0|OP01|LC1|LCD1" >/dev/null
out=$(bank "reconciliation.run|LOAN|REC-LN-C")
check "loan.recon.pre-eod" "BALANCED" "$(value "$out" msg=)"
cp etc/bank.cfg "$CFG_BAK"
sed -i 's/business-date=.*/business-date=2027-01-15/' etc/bank.cfg
out=$(bank "batch.eod|OP01|LC2|LCEOD")
check "loan.eod.rc" "00" "$(value "$out" rc=)"
out=$(bank "loan.get|N00000000001")
check "loan.eod.overdue" "30622.20" "$(value "$out" overdue-principal=)"
out=$(bank "loan.installment.get|N00000000001|1")
check "loan.eod.installment.overdue" "OD" "$(value "$out" status=)"
out=$(bank "loan.exposure|N00000000001")
check "loan.eod.exposure.overdue" "30622.20" "$(value "$out" overdue=)"
out=$(bank "reconciliation.run|LOAN|REC-LN-C2")
check "loan.recon.after.eod" "BALANCED" "$(value "$out" msg=)"

cp "$CFG_BAK" etc/bank.cfg

reset
setup_active_loan
bank "loan.disburse|N00000000001|100000|0|OP01|LD1|LDD1" >/dev/null
out=$(bank "loan.repay|N00000000001|200000|OP01|LD2|LDR1")
check "loan.repay.insufficient" "20" "$(value "$out" rc=)"
out=$(bank "loan.repay|N00000000001|200000|OP01|LD2|LDR1")
check "loan.repay.retry.after.failure" "20" "$(value "$out" rc=)"
bank "txn.create|DEPOSIT||A00000000001|300000|BRL|FUND|OP01|LD3|LDT1" >/dev/null
bank "txn.authorize|T00000000002|OP01|LD4|LDT2" >/dev/null
bank "txn.post|T00000000002|OP01|LD5|LDT3" >/dev/null
bank "txn.settle|T00000000002|OP01|LD6|LDT4" >/dev/null
out=$(bank "loan.repay|N00000000001|200000|OP01|LD2|LDR1")
check "loan.repay.recovery" "00" "$(value "$out" rc=)"
check "loan.repay.full.principal" "+000000000100000.00" "$(value "$out" principal=)"
out=$(bank "loan.get|N00000000001")
check "loan.repay.full.outstanding" "0.00" "$(value "$out" outstanding=)"
out=$(bank "loan.settle|N00000000001||OP01|LD7|LDS1")
check "loan.settle" "SET" "$(value "$out" status=)"
out=$(bank "loan.close|N00000000001||OP01|LD8|LDC1")
check "loan.close" "CLO" "$(value "$out" status=)"
out=$(bank "loan.activate|N00000000001||OP01|LD9|LDA1")
check "loan.closed.invalid.reopen" "20" "$(value "$out" rc=)"
out=$(bank "loan.disburse|N00000000001|1|0|OP01|LD10|LDD2")
check "loan.closed.disburse" "20" "$(value "$out" rc=)"

setup_collectible_loan() {
    setup_active_loan
    bank "loan.disburse|N00000000001|100000|0|OP01|MC1|MCD1" >/dev/null
    cp etc/bank.cfg "$CFG_BAK"
    sed -i 's/business-date=.*/business-date=2027-01-15/' etc/bank.cfg
    bank "batch.eod|OP01|MC2|MCEOD" >/dev/null
}

reset
setup_collectible_loan

out=$(bank "collections.case.eligible|N00000000001")
check "collections.eligible.rc" "00" "$(value "$out" rc=)"
check "collections.eligible.flag" "Y" "$(value "$out" eligible=)"
check "collections.eligible.overdue" "+000000000030622.20" "$(value "$out" overdue=)"

out=$(bank "collections.case.create|N00000000001|DELINQ|OP01|CC1|CR1")
check "collections.case.auto.duplicate" "22" "$(value "$out" rc=)"
out=$(bank "collections.case.list")
check "collections.autocreate.exists" "00001" "$(value "$out" count=)"
out=$(bank "collections.case.get|K00000000001")
check "collections.case.create.status" "OPEN" "$(value "$out" status=)"
check "collections.case.create.stage" "STANDARD" "$(value "$out" stage=)"
check "collections.case.create.priority" "120" "$(value "$out" priority=)"

out=$(bank "collections.case.create|N00000000001|DELINQ|OP01|CC2|CR2")
check "collections.case.duplicate" "22" "$(value "$out" rc=)"

out=$(bank "collections.case.get|K00000000001")
check "collections.case.get" "K00000000001" "$(value "$out" case=)"
check "collections.case.get.overdue" "+000000000030622.20" "$(value "$out" overdue=)"

out=$(bank "collections.case.activate|K00000000001|ATIVAR|OP01|CC3|CR3")
check "collections.case.activate" "INCO" "$(value "$out" status=)"

out=$(bank "collections.case.activate|K00000000001|ATIVAR|OP01|CC4|CR4")
check "collections.case.invalid.transition" "20" "$(value "$out" rc=)"

out=$(bank "collections.case.stage|K00000000001|OP01|CC5|CR5")
check "collections.case.stage" "STANDARD" "$(value "$out" stage=)"
check "collections.case.stage.priority" "120" "$(value "$out" priority=)"

out=$(bank "collections.case.get|K00000000009")
check "collections.case.not.found" "23" "$(value "$out" rc=)"

out=$(bank "collections.action.create|K00000000001|CALL|LIGAR|OP01|CC6|CR6")
check "collections.action.create" "X00000000001" "$(value "$out" action=)"
check "collections.action.create.status" "PLANNED" "$(value "$out" status=)"

out=$(bank "collections.action.execute|X00000000001|ATENDEU|OP01|CC7|CR7")
check "collections.action.execute" "EXECUTED" "$(value "$out" status=)"

out=$(bank "collections.action.list|K00000000001")
check "collections.action.list.count" "00001" "$(value "$out" count=)"

out=$(bank "collections.promise.create|K00000000001|10000|20270120|PROM|OP01|CC8|CR8")
check "collections.promise.create" "M00000000001" "$(value "$out" promise=)"
check "collections.promise.create.status" "PROPOSED" "$(value "$out" status=)"

out=$(bank "collections.promise.accept|M00000000001||OP01|CC9|CR9")
check "collections.promise.accept" "ACCEPTED" "$(value "$out" status=)"

out=$(bank "collections.case.get|K00000000001")
check "collections.case.promise.status" "PPEN" "$(value "$out" status=)"

out=$(bank "collections.promise.fulfill|M00000000001||OP01|CC10|CR10")
check "collections.promise.fulfill.rejected" "20" "$(value "$out" rc=)"

out=$(bank "collections.promise.break|M00000000001|NAO PAGO|OP01|CC10B|CR10B")
check "collections.promise.broken" "BROKEN" "$(value "$out" status=)"

out=$(bank "collections.case.get|K00000000001")
check "collections.case.promise.broken" "ESC" "$(value "$out" status=)"

out=$(bank "collections.arrange.create|K00000000001|20000|3|ACORDO|OP01|CC11|CR11")
check "collections.arrange.create" "G00000000001" "$(value "$out" arrangement=)"
check "collections.arrange.create.status" "PROPOSED" "$(value "$out" status=)"

out=$(bank "collections.arrange.activate|G00000000001||OP01|CC12|CR12")
check "collections.arrange.activate" "ACTIVE" "$(value "$out" status=)"

out=$(bank "collections.arrange.list|K00000000001")
check "collections.arrange.list.count" "00001" "$(value "$out" count=)"

out=$(bank "collections.recovery.post|K00000000001|5000|PAGOU|OP01|CC13|CR13")
check "collections.recovery.post" "00" "$(value "$out" rc=)"
check "collections.recovery.post.id" "R00000000001" "$(value "$out" recovery=)"
check "collections.recovery.post.principal" "+000000000002933.34" "$(value "$out" principal=)"
check "collections.recovery.post.interest" "+000000000002066.66" "$(value "$out" interest=)"
check "collections.recovery.post.status" "PREC" "$(value "$out" status=)"
check "collections.recovery.post.recovered" "+000000000005000.00" "$(value "$out" recovered=)"
check "collections.recovery.post.remaining" "+000000000025622.20" "$(value "$out" remaining=)"

out=$(bank "collections.recovery.post|K00000000001|5000|PAGOU|OP01|CC13|CR13")
check "collections.recovery.replay" "R00000000001" "$(value "$out" recovery=)"

out=$(bank "collections.recovery.list|K00000000001")
check "collections.recovery.list.count" "00001" "$(value "$out" count=)"

out=$(bank "loan.get|N00000000001")
check "collections.loan.after.recovery" "97066.66" "$(value "$out" outstanding=)"

out=$(bank "collections.recovery.reverse|R00000000001|OP01|CC14|CR14")
check "collections.recovery.reverse" "00" "$(value "$out" rc=)"

out=$(bank "loan.get|N00000000001")
check "collections.loan.after.reverse" "100000.00" "$(value "$out" outstanding=)"

out=$(bank "collections.case.get|K00000000001")
check "collections.case.after.reverse.overdue" "+000000000030622.20" "$(value "$out" overdue=)"
check "collections.case.after.reverse.recovered" "+000000000000000.00" "$(value "$out" recovered=)"

out=$(bank "collections.handoff.create|K00000000001|EXTERNAL|AGENCIA|TERCEIRIZACAO|OP01|CC15|CR15")
check "collections.handoff.create" "H00000000001" "$(value "$out" handoff=)"
check "collections.handoff.create.status" "REQUESTED" "$(value "$out" status=)"
out=$(bank "collections.handoff.create|K00000000001|EXTERNAL|AGENCIA|TERCEIRIZACAO|OP01|CC15B|CR15B")
check "collections.handoff.dup" "22" "$(value "$out" rc=)"
out=$(bank "collections.handoff.ack|H00000000001|AGENCIA|EXTREF77|OP01|CC15C|CR15C")
check "collections.handoff.ack" "ASSIGNED" "$(value "$out" status=)"
out=$(bank "collections.handoff.create|K00000000001|LEGAL|ESCRITORIO|COBRANCA JUDICIAL|OP01|CC15D|CR15D")
check "collections.handoff.legal" "00" "$(value "$out" rc=)"

out=$(bank "collections.case.get|K00000000001")
check "collections.case.handoff.escalated" "ESC" "$(value "$out" status=)"

out=$(bank "collections.handoff.return|H00000000001|||CONTATO|OP01|CC16|CR16")
check "collections.handoff.return" "RETURNED" "$(value "$out" status=)"

out=$(bank "collections.recovery.post|K00000000001|30622.20|QUITAR|OP01|CC17|CR17")
check "collections.recovery.full" "REC" "$(value "$out" status=)"

out=$(bank "collections.case.get|K00000000001")
check "collections.case.full.overdue" "+000000000000000.00" "$(value "$out" overdue=)"

out=$(bank "collections.case.close|K00000000001|QUITADO|OP01|CC18|CR18")
check "collections.case.close" "CLOS" "$(value "$out" status=)"

out=$(bank "collections.case.close|K00000000001|QUITADO|OP01|CC19|CR19")
check "collections.case.close.invalid" "20" "$(value "$out" rc=)"

out=$(bank "reconciliation.run|COLLECT|REC-COL-1")
check "collections.recon" "BALANCED" "$(value "$out" msg=)"


cp "$CFG_BAK" etc/bank.cfg

reset
setup_collectible_loan

out=$(bank "collections.case.cancel|K00000000001|ENGANO|OP01|CD2|CDR2")
check "collections.case.cancel" "CANC" "$(value "$out" status=)"
out=$(bank "collections.case.create|N00000000001|D|OP01|CD3|CDR3")
check "collections.case.recreate.after.cancel" "K00000000002" "$(value "$out" case=)"
out=$(bank "collections.case.reopen|K00000000001|VOLTA|OP01|CD4|CDR4")
check "collections.case.reopen.cancelled" "INCO" "$(value "$out" status=)"

out=$(bank "collections.recovery.post|K00000000002|1000|P|OP01|CD5|CDR5")
check "collections.recovery.on.active" "00" "$(value "$out" rc=)"
out=$(bank "collections.case.fail|K00000000002|ERRO|OP01|CD6|CDR6")
check "collections.case.fail" "FAIL" "$(value "$out" status=)"
out=$(bank "collections.recovery.post|K00000000002|100|P|OP01|CD7|CDR7")
check "collections.recovery.on.failed" "20" "$(value "$out" rc=)"

out=$(bank "collections.recovery.post|K00000000009|100|P|OP01|CD8|CDR8")
check "collections.recovery.not.found" "23" "$(value "$out" rc=)"

out=$(bank "collections.case.eligible|N00000000009")
check "collections.eligible.not.found" "23" "$(value "$out" rc=)"


cp "$CFG_BAK" etc/bank.cfg

reset
setup_collectible_loan
out=$(bank "collections.case.activate|K00000000001|A|OP01|CF2|CFR2")
bank "collections.recovery.post|K00000000001|5000|P|OP01|CF3|CFR3" >/dev/null
out=$(bank "ledger.trial")
td=$(value "$out" total-debit=)
tc=$(value "$out" total-credit=)
check "collections.invariant.debit.equals.credit" "$td" "$tc"
out=$(bank "ledger.trial")
check "collections.trial.balanced" "00" "$(value "$out" rc=)"
out=$(bank "reconciliation.run|COLLECT|REC-COL-2")
check "collections.recon.after.recovery" "BALANCED" "$(value "$out" msg=)"

cp "$CFG_BAK" etc/bank.cfg

reset
setup_collectible_loan

out=$(bank "collections.case.activate|K00000000001|A|OP01|PE2|PER2")
out=$(bank "collections.promise.create|K00000000001|10000|20270120|PROM|OP01|PE3|PER3")
out=$(bank "collections.promise.accept|M00000000001||OP01|PE4|PER4")
out=$(bank "collections.recovery.post|K00000000001|10000|PROM-PAGO|OP01|PE5|PER5")
check "collections.promise.financial.rc" "00" "$(value "$out" rc=)"
check "collections.promise.financial.status" "PREC" "$(value "$out" status=)"
out=$(bank "collections.promise.list|K00000000001")
check "collections.promise.fulfilled" "FULFILLED" "$(value "$out" status=)"
check "collections.promise.txnref" "T" "$(value "$out" txn= | cut -c1-1)"
out=$(bank "collections.case.get|K00000000001")
check "collections.case.after.promise.money" "PREC" "$(value "$out" status=)"

out=$(bank "collections.recovery.post|K00000000001|30000|PARCIAL-MAIOR|OP01|PE6|PER6")
check "collections.payoff.rc" "00" "$(value "$out" rc=)"
check "collections.excess.remaining" "+000000000000000.00" "$(value "$out" remaining=)"
check "collections.excess.case" "REC" "$(value "$out" status=)"
ex=$(value "$out" excess=)
check "collections.excess.value" "+000000000009377.80" "$ex"
out=$(bank "loan.get|N00000000001")
check "collections.payoff.outstanding" "67172.21" "$(value "$out" outstanding=)"
out=$(bank "reconciliation.run|COLLECT|REC-COL-PE")
check "collections.recon.promise" "BALANCED" "$(value "$out" msg=)"


cp "$CFG_BAK" etc/bank.cfg

reset
setup_collectible_loan
bank "collections.case.activate|K00000000001|A|OP01|PX2|PXR2" >/dev/null
bank "collections.promise.create|K00000000001|5000|20270110|PROM|OP01|PX3|PXR3" >/dev/null
sed -i 's/business-date=.*/business-date=2027-03-01/' etc/bank.cfg
out=$(bank "batch.eod|OP01|PX4|PXR4")
check "collections.eod.expired.rc" "00" "$(value "$out" rc=)"
check "collections.eod.expired.count" "00001" "$(printf '%s' "$out" | grep -o 'EXPIRED=[0-9]*' | tail -1 | sed 's/EXPIRED=//')"
out=$(bank "collections.promise.list|K00000000001")
check "collections.promise.expired" "EXPIRED" "$(value "$out" status=)"
out=$(bank "collections.case.get|K00000000001")
check "collections.case.after.expire" "INCO" "$(value "$out" status=)"
out=$(bank "collections.promise.create|K00000000001|5000|20270310|PROM|OP01|PX5|PXR5")
check "collections.promise.new.after.expire" "00" "$(value "$out" rc=)"


cp "$CFG_BAK" etc/bank.cfg

reset
setup_active_loan
bank "loan.disburse|N00000000001|100000|0|OP01|PA0|PAR0" >/dev/null
sed -i 's/business-date=.*/business-date=2027-01-15/' etc/bank.cfg
out=$(bank "batch.eod|OP01|PA1|PAR1")
check "collections.autocreate.eod" "00" "$(value "$out" rc=)"
check "collections.autocreate.count" "00001" "$(printf '%s' "$out" | grep -o 'CREATED=[0-9]*' | tail -1 | sed 's/CREATED=//')"
out=$(bank "collections.case.list")
check "collections.autocreate.list" "00001" "$(value "$out" count=)"
out=$(bank "collections.case.get|K00000000001")
check "collections.autocreate.status" "OPEN" "$(value "$out" status=)"
check "collections.autocreate.stage" "STANDARD" "$(value "$out" stage=)"
out=$(bank "batch.eod|OP01|PA2|PAR2")
check "collections.autocreate.rc2" "00" "$(value "$out" rc=)"
check "collections.autocreate.created2" "00000" "$(printf '%s' "$out" | grep -o 'CREATED=[0-9]*' | tail -1 | sed 's/CREATED=//')"
out=$(bank "collections.case.list")
check "collections.autocreate.list2" "00001" "$(value "$out" count=)"

cp "$CFG_BAK" etc/bank.cfg

reset
setup_collectible_loan

bank "collections.case.activate|K00000000001|A|OP01|AG2|AGR2" >/dev/null
out=$(bank "collections.arrange.create|K00000000001|6000|2|AC|OP01|AG3|AGR3")
out=$(bank "collections.arrange.create|K00000000001|3000|2|AC|OP01|AG4|AGR4")
check "collections.arrange.dup" "22" "$(value "$out" rc=)"
out=$(bank "collections.arrange.activate|G00000000001||OP01|AG5|AGR5")
out=$(bank "collections.recovery.post|K00000000001|3000|PARCELA|OP01|AG6|AGR6")
check "collections.arrange.paid1" "PREC" "$(value "$out" status=)"
out=$(bank "collections.arrange.list|K00000000001")
check "collections.arrange.partial" "PARTIALLY" "$(value "$out" status=)"
out=$(bank "collections.recovery.post|K00000000001|3000|PARCELB|OP01|AG7|AGR7")
out=$(bank "collections.arrange.list|K00000000001")
check "collections.arrange.fulfilled" "FULFILLED" "$(value "$out" status=)"
out=$(bank "collections.recovery.reverse|R00000000002|OP01|AG8|AGR8")
check "collections.arrange.rewind" "00" "$(value "$out" rc=)"
out=$(bank "collections.arrange.list|K00000000001")
check "collections.arrange.rewind.status" "PARTIALLY" "$(value "$out" status=)"
out=$(bank "collections.promise.fulfill|M00000000009||OP01|AG9|AGR9")
check "collections.promise.notfound" "23" "$(value "$out" rc=)"


cp "$CFG_BAK" etc/bank.cfg

reset
setup_collectible_loan

out=$(bank "collections.action.create|K00000000001|REVIEW|REV|OP01|AC2|ACR2")
check "collections.action.dup.block" "22" "$(bank "collections.action.create|K00000000001|REVIEW|REV|OP01|AC3|ACR3" | grep '^rc=' | sed 's/^rc=//')"
out=$(bank "collections.action.fail|X00000000001|FALHA|OP01|AC4|ACR4")
check "collections.action.failed" "FAILED" "$(value "$out" status=)"
out=$(bank "collections.action.create|K00000000001|REMINDER|NOVO|OP01|AC5|ACR5")
check "collections.action.recreate" "00" "$(value "$out" rc=)"
out=$(bank "collections.action.execute|X00000000002|CONTATO|OP01|AC6|ACR6")
check "collections.action.exec2" "EXECUTED" "$(value "$out" status=)"
out=$(bank "collections.action.execute|X00000000002|REPETIDO|OP01|AC7|ACR7")
check "collections.action.exec.idempotent" "20" "$(value "$out" rc=)"
out=$(bank "collections.action.cancel|X00000000002|X|OP01|AC8|ACR8")
check "collections.action.cancel.done" "20" "$(value "$out" rc=)"

bank "collections.recovery.post|K00000000001|1000|AMOSTRAGEM|OP01|AC9|ACR9" >/dev/null
aud=$(grep -ac '|COL.CREATE|K00000000001|' var/audit/audit.log || true)
check "collections.audit.create" "1" "$aud"
aud=$(grep -ac '|COL.EXECUTE|X00000000002|' var/audit/audit.log || true)
check "collections.audit.execute" "1" "$aud"
aud=$(grep -ac '|COL.RECOVER|R00000000001|' var/audit/audit.log || true)
check "collections.audit.recover" "1" "$aud"

out=$(bank "reconciliation.run|COLLECT|REC-COL-AUD")
check "collections.recon.audit" "BALANCED" "$(value "$out" msg=)"


# ---------- collateral domain ----------
sed -i 's/business-date=.*/business-date=2026-10-02/' etc/bank.cfg
POL=etc/collateral.cfg
POL_BAK=$(mktemp)
cp "$POL" "$POL_BAK"
reset
bank "ledger.init" >/dev/null
setup_active_loan
bank "loan.disburse|N00000000001|100000|0|OP01|CB1|CBD1" >/dev/null

sed -i 's/^VEHICLE|.*/VEHICLE|1000|Y|N|0|0/' "$POL"
out=$(bank "collateral.create|VEHICLE|C00000000001|C00000000001|CUSTOMER|BRL||||||Car 1|20260101|20261231||OP01")
check "collateral.create" "S00000000001" "$(value "$out" collateral=)"
check "collateral.create.status" "REGISTER" "$(value "$out" status=)"
out=$(bank "collateral.create|WIDGET|C00000000001|C00000000001|CUSTOMER|BRL||||||Bad|20260101||||OP01")
check "collateral.create.bad.type" "20" "$(value "$out" rc=)"
out=$(bank "collateral.create|VEHICLE|C00000000001|C00000000001|CUSTOMER|XXX||||||Bad|20260101||||OP01")
check "collateral.create.bad.currency" "20" "$(value "$out" rc=)"
out=$(bank "collateral.validate|S00000000001|OP01")
check "collateral.validate" "VALID" "$(value "$out" status=)"
out=$(bank "collateral.allocate|S00000000001|LOAN|N00000000001|10000||OBL0|OP01|CBA0|CBAR0")
check "collateral.allocate.before.value" "20" "$(value "$out" rc=)"
out=$(bank "collateral.value|S00000000001|100000|MARKET|APPRAISAL|REF-V|20261002||OP01|CBV1|CBVR1")
check "collateral.value" "V00000000001" "$(value "$out" valuation=)"
check "collateral.value.haircut" "+000000000090000.00" "$(value "$out" adjusted=)"
out=$(bank "collateral.value|S00000000001|100000|MARKET|APPRAISAL|REF-V|20261002||OP01|CBV1|CBVR1")
check "collateral.value.replay" "V00000000001" "$(value "$out" valuation=)"
out=$(bank "collateral.eligible|S00000000001")
check "collateral.eligible" "Y" "$(value "$out" eligible=)"
out=$(bank "collateral.allocate|S00000000001|LOAN|N00000000001|95000||OBL1|OP01|CBA1|CBAR1")
check "collateral.allocate.over" "20" "$(value "$out" rc=)"
out=$(bank "collateral.allocate|S00000000001|LOAN|N00000000001|60000||OBL1|OP01|CBA1|CBAR1")
check "collateral.allocate" "J00000000001" "$(value "$out" allocation=)"
check "collateral.allocate.available" "+000000000030000.00" "$(value "$out" available=)"
out=$(bank "collateral.allocate|S00000000001|LOAN|N00000000001|60000||OBL1|OP01|CBA1|CBAR1")
check "collateral.allocate.replay" "J00000000001" "$(value "$out" allocation=)"
out=$(bank "collateral.get|S00000000001")
check "collateral.get.status" "PARTPLED" "$(value "$out" status=)"
out=$(bank "collateral.cover|LOAN|N00000000001|80000")
check "collateral.cover.secured" "+000000000060000.00" "$(value "$out" secured=)"
check "collateral.cover.shortfall" "+000000000020000.00" "$(value "$out" shortfall=)"

out=$(bank "collateral.create|EQUIPMENT|C00000000001|C00000000001|CUSTOMER|BRL||||||Machine|20260101|20261231||OP01")
check "collateral.sub.dst.create" "S00000000002" "$(value "$out" collateral=)"
bank "collateral.validate|S00000000002|OP01" >/dev/null
bank "collateral.value|S00000000002|50000|BOOK|LEDGER|REF-E|20261002||OP01|CBV2|CBVR2" >/dev/null
out=$(bank "collateral.substitute|S00000000001|S00000000002|J00000000001||SWAP|OP01|CBS1|CBSR1")
check "collateral.sub.capacity" "20" "$(value "$out" rc=)"
bank "collateral.value|S00000000002|70000|BOOK|LEDGER|REF-E2|20261002||OP01|CBV3|CBVR3" >/dev/null
out=$(bank "collateral.substitute|S00000000001|S00000000002|J00000000001||SWAP|OP01|CBS1|CBSR1")
check "collateral.substitute" "B00000000001" "$(value "$out" substitution=)"
out=$(bank "collateral.get|S00000000001")
check "collateral.sub.pending.status" "SUBSTPT" "$(value "$out" status=)"
out=$(bank "collateral.subst-cancel|B00000000001|NOPE|OP01")
check "collateral.subst-cancel" "CANCELLED" "$(value "$out" status=)"
out=$(bank "collateral.get|S00000000001")
check "collateral.sub.cancel.restores" "PARTPLED" "$(value "$out" status=)"
out=$(bank "collateral.substitute|S00000000001|S00000000002|J00000000001||SWAP|OP01|CBS2|CBSR2")
check "collateral.substitute.2" "B00000000002" "$(value "$out" substitution=)"
out=$(bank "collateral.subst-complete|B00000000002")
check "collateral.subst-complete" "DONE" "$(value "$out" status=)"
DST=$(value "$out" dst-allocation=)
out=$(bank "collateral.get|S00000000001")
check "collateral.sub.done.src" "SUBSTITD" "$(value "$out" status=)"
out=$(bank "collateral.get|S00000000002")
check "collateral.sub.done.dst" "PARTPLED" "$(value "$out" status=)"
out=$(bank "collateral.obl-allocs|LOAN|N00000000001" | grep -c '^row')
check "collateral.sub.rows" "1" "$out"

out=$(bank "collateral.release|$DST|PAYOFF|OP01|CBR1|CBRR1")
check "collateral.release" "RELEASED" "$(value "$out" status=)"
out=$(bank "collateral.get|S00000000002")
check "collateral.release.status" "VALID" "$(value "$out" status=)"
out=$(bank "collateral.recompute|S00000000002")
check "collateral.recompute.available" "+000000000070000.00" "$(value "$out" available=)"

sed -i 's/^REAL-ESTATE|.*/REAL-ESTATE|0|N|Y|0|0/' "$POL"
out=$(bank "collateral.create|REAL-ESTATE|C00000000001|C00000000001|CUSTOMER|BRL||||||House|20260101||||OP01")
check "collateral.doc.create" "S00000000003" "$(value "$out" collateral=)"
out=$(bank "collateral.get|S00000000003")
check "collateral.doc.state" "MISSING" "$(value "$out" docstate=)"
bank "collateral.validate|S00000000003|OP01" >/dev/null
bank "collateral.value|S00000000003|200000|MARKET|APPRAISAL|REF-R|20261002||OP01|CBV4|CBVR4" >/dev/null
out=$(bank "collateral.allocate|S00000000003|LOAN|N00000000001|10000||OBL2|OP01|CBA2|CBAR2")
check "collateral.allocate.doc.missing" "20" "$(value "$out" rc=)"
out=$(bank "collateral.doc.create|S00000000003|DEED|REG-DEED-1|20260101|20270101|House deed|OP01")
check "collateral.doc.register" "W00000000001" "$(value "$out" document=)"
out=$(bank "collateral.doc.verify|W00000000001|BANKER|OP01")
check "collateral.doc.verify" "VERIFIED" "$(value "$out" state=)"
out=$(bank "collateral.allocate|S00000000003|LOAN|N00000000001|10000||OBL2|OP01|CBA2|CBAR2")
check "collateral.allocate.doc.ok" "J00000000004" "$(value "$out" allocation=)"
ALLOC3=$(value "$out" allocation=)
out=$(bank "collateral.allocate|S00000000003|FACIL|F00000000001|5000||OBL3|OP01|CBA3|CBAR3")
check "collateral.multi.blocked" "20" "$(value "$out" rc=)"
out=$(bank "collateral.cover|FACIL|F00000000001|80000")
check "collateral.cover.none" "NONE" "$(value "$out" status=)"

out=$(bank "collateral.create|PERSONAL-GUARANTEE|C00000000001|C00000000001|CUSTOMER|BRL|OP01")
check "collateral.guar.no.guarantor" "20" "$(value "$out" rc=)"
out=$(bank "collateral.create|PERSONAL-GUARANTEE|C00000000001|C00000000001|CUSTOMER|BRL|G00000000001|100000||||PG|20260101|20261231||||OP01")
check "collateral.guar.create" "S00000000004" "$(value "$out" collateral=)"
bank "collateral.validate|S00000000004|OP01" >/dev/null
out=$(bank "collateral.value|S00000000004|500000|CONTRACT|PG-DOC|REF-G|20261002||OP01|CBV5|CBVR5")
check "collateral.guar.cap" "+000000000100000.00" "$(value "$out" eligible=)"

out=$(bank "collateral.enforce|S00000000003|$ALLOC3|10000||DEFAULT|OP01|CBE1|CBER1")
check "collateral.enforce" "E00000000001" "$(value "$out" enforcement=)"
ENF=$(value "$out" enforcement=)
out=$(bank "collateral.get|S00000000003")
check "collateral.enforce.status" "ENFORCEP" "$(value "$out" status=)"
out=$(bank "collateral.enforce|S00000000003|$ALLOC3|10000||AGAIN|OP01|CBE2|CBER2")
check "collateral.enforce.dup" "20" "$(value "$out" rc=)"
out=$(bank "collateral.enforce-complete|$ENF|OP01")
check "collateral.enforce-complete" "ENFORCED" "$(value "$out" status=)"
ENFST=$(value "$out" enforcement=)
out=$(bank "collateral.dispose|$ENF||LIQUIDATION|OP01|CBD1|CBDR1")
check "collateral.dispose" "D00000000001" "$(value "$out" disposition=)"
DISPX=$(value "$out" disposition=)
bank "txn.create|DEPOSIT||A00000000001|100000|BRL|LIQUID|OP01|STX1|STXR1" >/dev/null
out=$(bank "collateral.disp-settle|$DISPX|ZZZZ|OP01")
check "collateral.disp.settle.bad.txn" "23" "$(value "$out" rc=)"
bank "txn.authorize|T00000000001|OP01|STX2|STXR2" >/dev/null
bank "txn.post|T00000000001|OP01|STX3|STXR3" >/dev/null
bank "txn.settle|T00000000001|OP01|STX4|STXR4" >/dev/null
out=$(bank "collateral.disp-settle|$DISPX|T00000000001|OP01")
check "collateral.disp-settle" "SETTLED" "$(value "$out" status=)"
check "collateral.disp.applied" "+000000000010000.00" "$(value "$out" applied=)"
check "collateral.disp.surplus" "+000000000090000.00" "$(value "$out" surplus=)"
out=$(bank "collateral.get|S00000000003")
check "collateral.disp.collateral" "RECOVERED" "$(value "$out" status=)"

out=$(bank "collateral.create|INVENTORY|C00000000001|C00000000001|CUSTOMER|BRL||||||Stock|20260101|20260930||OP01")
check "collateral.expiring.create" "S00000000005" "$(value "$out" collateral=)"
bank "collateral.validate|S00000000005|OP01" >/dev/null
bank "batch.eod|OP01|CBW1|CBWR1" >/dev/null
out=$(grep -c 'COLLATERAL-EOD' var/out/eod_20261002.txt || true)
check "collateral.eod.report" "1" "$out"
out=$(bank "collateral.get|S00000000005")
check "collateral.eod.expired" "EXPIRED" "$(value "$out" status=)"
out=$(bank "collateral.eligible|S00000000005")
check "collateral.expired.ineligible" "N" "$(value "$out" eligible=)"
out=$(bank "reconciliation.run|CLTREG|REC-CLT1")
check "collateral.recon.balanced" "BALANCED" "$(value "$out" msg=)"

aud=$(grep -ac '|CLT.CREAT|S00000000001|' var/audit/audit.log || true)
check "collateral.audit.create" "1" "$aud"
aud=$(grep -ac '|CLT.VAL|V00000000001|' var/audit/audit.log || true)
check "collateral.audit.value" "1" "$aud"
aud=$(grep -ac '|CLT.ALLOC|J00000000001|' var/audit/audit.log || true)
check "collateral.audit.allocate" "1" "$aud"
aud=$(grep -ac '|CLT.CHG|S00000000003|' var/audit/audit.log || true)
aud2=$(test "$aud" -gt 0 && echo yes || echo no)
check "collateral.audit.change" "yes" "$aud2"
ev=$(grep -ac 'COLLATERAL.VAL.v1' var/journal/events.log || true)
ev2=$(test "$ev" -gt 0 && echo yes || echo no)
check "collateral.event.valuation" "yes" "$ev2"

cp "$POL_BAK" "$POL"; rm -f "$POL_BAK"

# ---------- cards domain ----------
sed -i 's/business-date=.*/business-date=2026-10-02/' etc/bank.cfg
reset
bank "ledger.init" >/dev/null
bank "product.init" >/dev/null
bank "customer.create|P|CARL CARD|CPF|12345678901|19900101|OP01" >/dev/null
out=$(bank "account.open|C00000000001|DMND|BRL|1000000|OP01")
check "cards.setup.account" "A00000000001" "$(value "$out" id=)"
out=$(bank "cards.create|CDEB|C00000000001|A00000000001||BRL")
check "cards.create" "U00000000001" "$(value "$out" card=)"
check "cards.create.status" "REQUESTED" "$(value "$out" status=)"
check "cards.create.masked" "MASKU00000000001" "$(value "$out" masked=)"
out=$(bank "cards.approve|U00000000001|CREDIT OK|OP01")
check "cards.approve" "APPROVED" "$(value "$out" status=)"
out=$(bank "cards.activate|U00000000001||OP01")
check "cards.activate.before.issue" "20" "$(value "$out" rc=)"
out=$(bank "cards.issue|U00000000001|S|OP01")
check "cards.issue" "ISSUED" "$(value "$out" status=)"
out=$(bank "cards.activate|U00000000001||OP01")
check "cards.activate" "ACTIVE" "$(value "$out" status=)"
out=$(bank "cards.block|U00000000001|LOST|OP01")
check "cards.block" "BLOCKED" "$(value "$out" status=)"
out=$(bank "cards.unblock|U00000000001||OP01")
check "cards.unblock" "ACTIVE" "$(value "$out" status=)"
out=$(bank "cards.replace|U00000000001|DAMAGED|OP01")
check "cards.replace" "REPLACED" "$(value "$out" status=)"
check "cards.replace.next" "U00000000002" "$(value "$out" next=)"
out=$(bank "cards.get|U00000000002")
check "cards.replaced.new" "ISSUED" "$(value "$out" status=)"
check "cards.replaced.prev" "U00000000001" "$(value "$out" prev=)"
out=$(bank "cards.list|C00000000001")
check "cards.list" "00002" "$(value "$out" count=)"

out=$(bank "cards.issue|U00000000002|S|OP01")
out=$(bank "cards.activate|U00000000002||OP01")
check "cards.replaced.active" "ACTIVE" "$(value "$out" status=)"
out=$(bank "cards.auth|U00000000002|400000|BRL|M01|5999|POS|PURCHASE||OP01|CORP|A1")
check "cards.auth" "Q00000000001" "$(value "$out" auth=)"
check "cards.auth.status" "APPROVED" "$(value "$out" status=)"
out=$(bank "cards.auth|U00000000002|650000|BRL|M02|5999|POS|PURCHASE||OP01|CORP|A2")
check "cards.auth.insufficient" "DECLINED" "$(value "$out" status=)"
check "cards.auth.insufficient.reason" "INSUFFICIENTFUNDS" "$(value "$out" reason=)"
out=$(bank "cards.auth|U00000000002|400000|BRL|M01|5999|POS|PURCHASE||OP01|CORP|A1")
check "cards.auth.replay" "Q00000000001" "$(value "$out" auth=)"
check "cards.auth.replay.msg" "AUTHORIZATIONREPLAY" "$(value "$out" msg=)"
out=$(bank "cards.capture|Q00000000001|150000|OP01|CORP|C1")
check "cards.capture.status" "PARTCAP" "$(value "$out" status=)"
check "cards.capture.amount" "+000000000150000.00" "$(value "$out" captured=)"
check "cards.capture.remain" "+000000000250000.00" "$(value "$out" remaining=)"
out=$(bank "cards.capture|Q00000000001|150000|OP01|CORP|C1")
check "cards.capture.replay" "PARTCAP" "$(value "$out" status=)"
check "cards.capture.replay.amount" "+000000000150000.00" "$(value "$out" captured=)"
out=$(bank "cards.capture|Q00000000001|250000|OP01|CORP|C2")
check "cards.capture.full" "CAPTURED" "$(value "$out" status=)"
check "cards.capture.full.remain" "+000000000000000.00" "$(value "$out" remaining=)"
out=$(bank "cards.capture|Q00000000001|1|OP01|CORP|C3")
check "cards.capture.exceeds" "20" "$(value "$out" rc=)"
out=$(bank "cards.release|Q00000000002||OP01|CORP|R1")
check "cards.release.declined" "20" "$(value "$out" rc=)"
out=$(bank "cards.auth|U00000000002|700000|BRL|M03|5999|POS|PURCHASE||OP01|CORP|A3")
check "cards.auth.after.capture" "APPROVED" "$(value "$out" status=)"
check "cards.auth.after.capture.id" "Q00000000003" "$(value "$out" auth=)"
out=$(bank "cards.auth-reverse|Q00000000003|OP01|CORP|RV1")
check "cards.reverse" "REVERSED" "$(value "$out" status=)"
out=$(bank "cards.auth|U00000000002|800000|BRL|M04|5999|POS|PURCHASE||OP01|CORP|A4")
check "cards.auth.hold.released" "APPROVED" "$(value "$out" status=)"
check "cards.auth.hold.released.id" "Q00000000004" "$(value "$out" auth=)"
out=$(bank "cards.auth-get|Q00000000001")
check "cards.auth-get" "CAPTURED" "$(value "$out" status=)"
out=$(bank "cards.auth-get|Q00000009999")
check "cards.auth-get.missing" "23" "$(value "$out" rc=)"
out=$(bank "cards.capture|Q00000000002|1000|OP01|CORP|C4")
check "cards.capture.declined" "20" "$(value "$out" rc=)"
out=$(bank "cards.block|U00000000002|FRAUD|OP01")
out=$(bank "cards.auth|U00000000002|1000|BRL|M05|5999|POS|PURCHASE||OP01|CORP|A5")
check "cards.auth.blocked" "DECLINED" "$(value "$out" status=)"
check "cards.auth.blocked.reason" "CARDNOTACTIVE" "$(value "$out" reason=)"
out=$(bank "cards.unblock|U00000000002||OP01")

aud=$(grep -ac '|CRD.CREAT|U00000000001|' var/audit/audit.log || true)
check "cards.audit.create" "1" "$aud"
ev=$(grep -ac 'CARD_AUTHORIZATION_EVENT' var/journal/events.log || true)
test "$ev" -gt 0 && yes1=yes || yes1=no
check "cards.event.authorization" "yes" "$yes1"
ev2=$(grep -ac 'CARD.ACTIVATE' var/journal/events.log || true)
test "$ev2" -gt 0 && yes2=yes || yes2=no
check "cards.event.lifecycle" "yes" "$yes2"
grep -aqE "4111[0-9]{12}" var/data/crdcard.idx && leak=yes || leak=no
check "cards.security.no.pan" "no" "$leak"

# --- cards clearing ---
reset
bank "ledger.init" >/dev/null
bank "product.init" >/dev/null
bank "customer.create|P|CLEARING CUST|CPF|12345678901|19900101|OP01" >/dev/null
bank "account.open|C00000000001|DMND|BRL|1000000|OP01|CO|A0" >/dev/null
bank "cards.create|CDEB|C00000000001|A00000000001||BRL" >/dev/null
bank "cards.approve|U00000000001||OP01" >/dev/null
bank "cards.issue|U00000000001|S|OP01" >/dev/null
bank "cards.activate|U00000000001||OP01" >/dev/null
out=$(bank "cards.auth|U00000000001|5000|BRL|M01|5999|POS|PURCHASE|EXT-CL1|OP01|CO|A1")
check "clearing.seed.auth" "Q00000000001" "$(value "$out" auth=)"

out=$(bank "clearing.ingest|VISA|EXT-CL1|U00000000001|4000|BRL|PURCHASE|Q00000000001|M01|5999|POS||20261002||B01||||OP01|CORC|CI1")
check "clearing.ingest" "Y00000000001" "$(value "$out" clr=)"
check "clearing.ingest.status" "RECEIVED" "$(value "$out" status=)"
out=$(bank "clearing.ingest|VISA|EXT-CL1|U00000000001|4000|BRL|PURCHASE|Q00000000001|M01|5999|POS||20261002||B01||||OP01|CORC|CI1")
check "clearing.ingest.replay.id" "Y00000000001" "$(value "$out" clr=)"
check "clearing.ingest.replay" "Y" "$(value "$out" replay=)"
out=$(bank "clearing.ingest|VISA|EXT-CL1|U00000000001|999|BRL|PURCHASE||M01|5999|POS||20261002||B01||||OP01|CORC|CI2")
check "clearing.ingest.diff.req" "Y00000000001" "$(value "$out" clr=)"
out=$(bank "clearing.post|Y00000000001||OP01|CORC|CP0")
check "clearing.post.before.match" "20" "$(value "$out" rc=)"
out=$(bank "clearing.match|Y00000000001|OP01|CORC|CM1")
check "clearing.match" "MATCHED" "$(value "$out" match=)"
check "clearing.match.auth" "Q00000000001" "$(value "$out" auth=)"
check "clearing.match.diff" "-000000000001000.00" "$(printf '%s' "$out" | grep '^diff=' | sed 's/^diff=//')"
out=$(bank "clearing.match|Y00000000001|OP01|CORC|CM1")
check "clearing.match.replay.msg" "MATCHALREADYDONE" "$(printf '%s' "$out" | grep '^msg=' | sed 's/^msg=//' | tr -d ' ')"
out=$(bank "cards.auth-get|Q00000000001")
check "clearing.match.auth.consumed" "RELEASED" "$(value "$out" status=)"
check "clearing.match.auth.captured" "+000000000004000.00" "$(printf '%s' "$out" | grep '^captured=' | sed 's/^captured=//')"
out=$(bank "clearing.post|Y00000000001||OP01|CORC|CP1")
check "clearing.post" "POSTED" "$(value "$out" post=)"
check "clearing.post.txn" "T00000000001" "$(value "$out" txn=)"
out=$(bank "clearing.post|Y00000000001||OP01|CORC|CP1")
check "clearing.post.replay" "Y" "$(value "$out" replay=)"
out=$(bank "txn.get|T00000000001")
check "clearing.post.txn.status" "ST" "$(value "$out" status=)"
out=$(bank "clearing.get|Y00000000001")
check "clearing.get" "POSTED" "$(value "$out" status=)"
out=$(bank "ledger.balance|A00000000001")
check "clearing.balance.after.post" "996000.00" "$(value "$out" available=)"

out=$(bank "clearing.ingest|MSTR|EXT-CL1|U00000000001|4000|BRL|PURCHASE|Q00000000001|M01|5999|POS||20261002||B01||||OP01|CORC|CI3")
check "clearing.dup.ingest" "Y00000000002" "$(value "$out" clr=)"
out=$(bank "clearing.match|Y00000000002|OP01|CORC|CM2")
check "clearing.duplicate" "20" "$(value "$out" rc=)"
check "clearing.duplicate.match" "DUPLICATE" "$(value "$out" match=)"
out=$(bank "clearing.exc-get|O00000000001")
check "clearing.exc.get" "Y00000000002" "$(value "$out" clr=)"

out=$(bank "cards.auth|U00000000001|4000|BRL|M02|5999|POS|PURCHASE|EXT-CL2|OP01|CORC|AA2")
check "clearing.other.source.auth" "Q00000000002" "$(value "$out" auth=)"
out=$(bank "clearing.ingest|VISA|EXT-CL2|U00000000001|4000|BRL|PURCHASE||M02|5999|POS||20261002||B01||||OP01|CORC|CI4")
check "clearing.other.source.ingest" "Y00000000003" "$(value "$out" clr=)"
out=$(bank "clearing.match|Y00000000003|OP01|CORC|CM3")
check "clearing.other.source.match" "MATCHED" "$(value "$out" match=)"
check "clearing.other.source.matchauth" "Q00000000002" "$(value "$out" auth=)"
out=$(bank "clearing.post|Y00000000003||OP01|CORC|CP3")
check "clearing.other.source.post" "POSTED" "$(value "$out" post=)"

out=$(bank "clearing.ingest|VISA|EXT-RV1|U00000000001|4000|BRL|REVERSAL|Y00000000003|M02|5999|POS||20261002||B01||||OP01|CORC|RV1")
check "clearing.reversal.ingest" "Y00000000004" "$(value "$out" clr=)"
out=$(bank "clearing.match|Y00000000004|OP01|CORC|RM1")
check "clearing.reversal.match" "NO-AUTH" "$(value "$out" match=)"
out=$(bank "clearing.post|Y00000000004||OP01|CORC|RP1")
check "clearing.reversal.post" "REVERSED" "$(value "$out" post=)"
out=$(bank "clearing.get|Y00000000003")
check "clearing.reversed.origin" "REVERSED" "$(value "$out" post=)"
out=$(bank "clearing.post|Y00000000004||OP01|CORC|RP2")
check "clearing.reversal.replay" "Y" "$(value "$out" replay=)"
out=$(bank "ledger.balance|A00000000001")
check "clearing.balance.after.reversal" "996000.00" "$(value "$out" available=)"

out=$(bank "clearing.ingest|VISA|EXT-CL9|U0000000999|4000|BRL|PURCHASE||M01|5999|POS||20261002||B01||||OP01|CORC|CI5")
check "clearing.ingest.unknown.card" "20" "$(value "$out" rc=)"
out=$(bank "clearing.ingest|VISA|EXT-CL8|U00000000001|0|BRL|PURCHASE||M01|5999|POS||20261002||B01||||OP01|CORC|CI6")
check "clearing.ingest.zero.amount" "20" "$(value "$out" rc=)"
out=$(bank "clearing.ingest|VISA|EXT-CL7|U00000000001|4000|USD|PURCHASE||M01|5999|POS||20261002||B01||||OP01|CORC|CI7")
check "clearing.ingest.currency.mismatch" "20" "$(value "$out" rc=)"
out=$(bank "clearing.ingest|VISA|EXT-CL6|U00000000001|4000|BRL|BOGUS||M01|5999|POS||20261002||B01||||OP01|CORC|CI8")
check "clearing.ingest.bad.type" "20" "$(value "$out" rc=)"
out=$(bank "clearing.ingest|VISA|EXT-XX1|U00000000001|100|BRL|PURCHASE|Q00000009999|M01|5999|POS||20261002||B06||||OP01|CORC|CI9")
check "clearing.bad.auth.ref" "20" "$(value "$out" rc=)"

out=$(bank "clearing.ingest|VISA|EXT-RF1|U00000000001|300|BRL|REFUND|||5999|POS||20261002||B01||||OP01|CORC|R3")
check "clearing.refund.ingest" "Y00000000005" "$(value "$out" clr=)"
out=$(bank "clearing.match|Y00000000005|OP01|CORC|RM4")
check "clearing.refund.match" "NO-AUTH" "$(value "$out" match=)"
out=$(bank "clearing.post|Y00000000005||OP01|CORC|RP4")
check "clearing.refund.post" "POSTED" "$(value "$out" post=)"
out=$(bank "ledger.balance|A00000000001")
check "clearing.refund.balance" "996300.00" "$(value "$out" available=)"

out=$(bank "clearing.ingest|VISA|EXT-CL4|U00000000001|2000|BRL|PURCHASE||M04|5999|POS||20261002||B04||||OP01|CORC|IA0")
check "clearing.unmatched.ingest" "Y00000000006" "$(value "$out" clr=)"
out=$(bank "clearing.match|Y00000000006|OP01|CORC|CM5")
check "clearing.unmatched" "UNMATCHED" "$(value "$out" match=)"
out=$(bank "clearing.post|Y00000000006||OP01|CORC|CP5")
check "clearing.post.unmatched" "20" "$(value "$out" rc=)"
out=$(bank "clearing.exc-list|OPEN")
check "clearing.exceptions.open" "00002" "$(value "$out" count=)"
out=$(bank "clearing.post|Y00000000006|Y|OP01|CORC|CP6")
check "clearing.post.forced" "POSTED" "$(value "$out" post=)"

out=$(bank "cards.auth|U00000000001|700|BRL|M05|5999|POS|PURCHASE|EXT-CL5|OP01|CORC|AA5")
check "clearing.settle.auth" "Q00000000003" "$(value "$out" auth=)"
out=$(bank "clearing.ingest|VISA|EXT-CL5|U00000000001|700|BRL|PURCHASE||M05|5999|POS||20261002||B02||||OP01|CORC|IA2")
check "clearing.settle.ingest" "Y00000000007" "$(value "$out" clr=)"
out=$(bank "clearing.match|Y00000000007|OP01|CORC|CM6")
check "clearing.settle.match" "MATCHED" "$(value "$out" match=)"
out=$(bank "clearing.post|Y00000000007||OP01|CORC|CP7")
check "clearing.settle.post" "POSTED" "$(value "$out" post=)"

out=$(bank "clearing.settle-build|VISA|BRL|||OP01|CORC|Z1")
check "clearing.settle.build" "Z00000000001" "$(value "$out" batch=)"
out=$(bank "clearing.settle-get|Z00000000001")
check "clearing.settle.build.count" "00004" "$(value "$out" count=)"
check "clearing.settle.build.amount" "+000000000007000.00" "$(printf '%s' "$out" | grep '^amount=' | sed 's/^amount=//')"
out=$(bank "clearing.settle-build|VISA|BRL|||OP01|CORC|Z1")
check "clearing.settle.build.replay" "Z00000000001" "$(value "$out" batch=)"
out=$(bank "clearing.settle-check|Z00000000001|OP01")
check "clearing.settle.check" "00" "$(value "$out" rc=)"
out=$(bank "clearing.settle-mark|Z00000000001|OP01|CORC|Z2")
check "clearing.settle.mark" "00" "$(value "$out" rc=)"
out=$(bank "clearing.settle-mark|Z00000000001|OP01|CORC|Z3")
check "clearing.settle.mark.replay" "Y" "$(value "$out" replay=)"
out=$(bank "clearing.get|Y00000000001")
check "clearing.settled.status" "SETTLED" "$(value "$out" status=)"
check "clearing.settled.batch" "Z00000000001" "$(value "$out" batch=)"
out=$(bank "txn.get|T00000000001")
check "clearing.settled.txn" "ST" "$(value "$out" status=)"
out=$(bank "clearing.ingest|VISA|EXT-RV2|U00000000001|4000|BRL|REVERSAL|Y00000000001|M01|5999|POS||20261002||B01||||OP01|CORC|RV3")
check "clearing.settled.reversal.ingest" "Y00000000008" "$(value "$out" clr=)"
out=$(bank "clearing.match|Y00000000008|OP01|CORC|RM8")
check "clearing.settled.reversal.match" "NO-AUTH" "$(value "$out" match=)"
out=$(bank "clearing.post|Y00000000008||OP01|CORC|RP5")
check "clearing.reversal.after.settle" "20" "$(value "$out" rc=)"
check "clearing.reversal.after.settle.msg" "USEREFUNDAFTERSETTLEMENT" "$(printf '%s' "$out" | grep '^msg=' | sed 's/^msg=//' | tr -d ' ')"

out=$(bank "reconciliation.run|CARDCLR")
check "clearing.recon.run" "00" "$(value "$out" rc=)"
rid=$(value "$out" run=)
out=$(bank "reconciliation.get|$rid")
check "clearing.recon.matched" "000000001" "$(value "$out" matched=)"
out=$(bank "clearing.get|Y00000000001")
check "clearing.recon.status" "RECONCILED" "$(value "$out" recon=)"

out=$(bank "cards.auth|U00000000001|3000|BRL|M06|5999|POS|PURCHASE|EXT-AM1|OP01|CORC|AM5")
check "clearing.ambig.auth1" "Q00000000004" "$(value "$out" auth=)"
out=$(bank "cards.auth|U00000000001|3000|BRL|M07|5999|POS|PURCHASE|EXT-AM2|OP01|CORC|AM6")
check "clearing.ambig.auth2" "Q00000000005" "$(value "$out" auth=)"
out=$(bank "clearing.ingest|VISA|EXT-AMB0|U00000000001|3000|BRL|PURCHASE||M08|5999|POS||20261002||B03||||OP01|CORC|AM1")
check "clearing.ambig.ingest" "Y00000000009" "$(value "$out" clr=)"
out=$(bank "clearing.match|Y00000000009|OP01|CORC|AM3")
check "clearing.ambiguous" "20" "$(value "$out" rc=)"
check "clearing.ambiguous.match" "AMBIGUOUS" "$(value "$out" match=)"
out=$(bank "clearing.match|Y00000000009|OP01|CORC|AM3")
check "clearing.ambiguous.replay" "20" "$(value "$out" rc=)"
out=$(bank "cards.release|Q00000000004||OP01|CORC|XR1") >/dev/null
out=$(bank "cards.release|Q00000000005||OP01|CORC|XR2") >/dev/null

out=$(bank "clearing.exc-resolve|O00000000001|MANUAL REVIEW COMPLETE|OP01|CORC")
check "clearing.exc.resolve" "00" "$(value "$out" rc=)"
out=$(bank "clearing.exc-retry|O00000000001|OP01|CORC")
check "clearing.exc.retry.resolved" "20" "$(value "$out" rc=)"
out=$(bank "clearing.exc-list|OPEN")
check "clearing.exceptions.after.resolve" "00002" "$(value "$out" count=)"

sed -i 's/business-date=.*/business-date=2026-10-03/' "$CFG"
out=$(bank "cards.auth|U00000000001|700|BRL|M08|5999|POS|PURCHASE|EXT-CL10|OP01|CORC|AA8")
check "clearing.expiry.auth" "Q00000000006" "$(value "$out" auth=)"
sed -i 's/business-date=.*/business-date=2026-10-05/' "$CFG"
out=$(bank "clearing.ingest|VISA|EXT-EXP1|U00000000001|700|BRL|PURCHASE|Q00000000006|M08|5999|POS||20261005||B05||||OP01|CORC|EX1")
check "clearing.expired.ingest" "Y00000000010" "$(value "$out" clr=)"
out=$(bank "clearing.match|Y00000000010|OP01|CORC|EX2")
check "clearing.expired.match" "20" "$(value "$out" rc=)"
check "clearing.expired.match.status" "EXPIRED" "$(value "$out" match=)"
out=$(bank "clearing.post|Y00000000010|Y|OP01|CORC|EX3")
check "clearing.expired.post.blocked" "20" "$(value "$out" rc=)"
out=$(bank "batch.eod|OP01|CE1|CEOD1")
check "clearing.eod" "00" "$(value "$out" rc=)"
check "clearing.eod.report" "1" "$(grep -c 'RECON-CARDCLR' var/out/eod_20261005.txt || true)"
grep -q 'CARD EOD: EXPIRED=00001' var/out/eod_20261005.txt && ex=yes || ex=no
check "clearing.eod.expired.count" "yes" "$ex"
out=$(bank "cards.auth-get|Q00000000006")
check "clearing.eod.auth.released" "RELEASED" "$(value "$out" status=)"
grep -aqE "4111[0-9]{12}" var/data/crdclr.idx var/data/crdclrx.idx var/data/crdclrm.idx var/data/crdstl.idx && cleak=yes || cleak=no
check "clearing.security.no.pan" "no" "$cleak"
aud=$(grep -ac '|CLR.INGEST|' var/audit/audit.log || true)
test "$aud" -ge 1 && ca=yes || ca=no
check "clearing.audit.ingest" "yes" "$ca"
ev3=$(grep -ac 'CARD.CLR.INGEST' var/journal/events.log || true)
test "$ev3" -ge 1 && ce=yes || ce=no
check "clearing.event.ingest" "yes" "$ce"

# --- cards clearing: credit card and fee flows ---
reset
bank "ledger.init" >/dev/null
bank "product.init" >/dev/null
bank "customer.create|P|CREDIT CUST|CPF|33344455566|19800101|OP01" >/dev/null
bank "account.open|C00000000001|DMND|BRL|100000|OP01|CO|OA1" >/dev/null
out=$(bank "credit.application.create|C00000000001|CRCR|A00000000001|100000|12|OP01|C|AP1")
check "clearing.credit.application" "L00000000001" "$(value "$out" application=)"
bank "credit.application.approve|L00000000001|100000||OP01|C|CAP" >/dev/null
bank "credit.facility.originate|L00000000001|A00000000001|20271002||OP01|C|OR1" >/dev/null
bank "credit.facility.approve|F00000000001||OP01|C|APV" >/dev/null
bank "credit.facility.contract|F00000000001||||OP01|C|CT1" >/dev/null
bank "credit.facility.activate|F00000000001||OP01|C|AC1" >/dev/null
out=$(bank "cards.create|CRCR|C00000000001|A00000000001|F00000000001|BRL")
check "clearing.credit.card" "U00000000001" "$(value "$out" card=)"
check "clearing.credit.kind" "CREDIT" "$(value "$out" kind=)"
bank "cards.approve|U00000000001||OP01" >/dev/null
bank "cards.issue|U00000000001|S|OP01" >/dev/null
bank "cards.activate|U00000000001||OP01" >/dev/null
out=$(bank "cards.auth|U00000000001|20000|BRL|M09|5999|POS|PURCHASE|EXT-CC1|OP01|CO|ACR")
check "clearing.credit.auth" "Q00000000001" "$(value "$out" auth=)"
out=$(bank "clearing.ingest|VISA|EXT-CC1|U00000000001|18000|BRL|PURCHASE||M09|5999|POS||20261005||B01||||OP01|CORC|CC1")
check "clearing.credit.ingest" "Y00000000001" "$(value "$out" clr=)"
out=$(bank "clearing.match|Y00000000001|OP01|CORC|CCM")
check "clearing.credit.match" "MATCHED" "$(value "$out" match=)"
out=$(bank "clearing.post|Y00000000001||OP01|CORC|CCP")
check "clearing.credit.post" "POSTED" "$(value "$out" post=)"
out=$(bank "credit.facility.exposure|F00000000001")
check "clearing.credit.exposure" "18000.00" "$(value "$out" principal=)"
out=$(bank "ledger.balance|A00000000001")
check "clearing.credit.no.debit" "100000.00" "$(value "$out" available=)"
out=$(bank "clearing.ingest|VISA|EXT-CC2|U00000000001|3000|BRL|REFUND|||5999|POS||20261005||B01||||OP01|CORC|CC2")
check "clearing.credit.refund.ingest" "Y00000000002" "$(value "$out" clr=)"
out=$(bank "clearing.match|Y00000000002|OP01|CORC|CCM2")
check "clearing.credit.refund.match" "NO-AUTH" "$(value "$out" match=)"
out=$(bank "clearing.post|Y00000000002||OP01|CORC|CCP2")
check "clearing.credit.refund.post" "POSTED" "$(value "$out" post=)"
out=$(bank "credit.facility.exposure|F00000000001")
check "clearing.credit.exposure.after.refund" "15000.00" "$(value "$out" principal=)"
out=$(bank "clearing.settle-build|VISA|BRL|||OP01|CORC|Z9")
check "clearing.credit.settle.build" "Z00000000001" "$(value "$out" batch=)"
out=$(bank "clearing.settle-check|Z00000000001|OP01")
check "clearing.credit.settle.check" "00" "$(value "$out" rc=)"
out=$(bank "clearing.settle-mark|Z00000000001|OP01|CORC|Z10")
check "clearing.credit.settle.mark" "00" "$(value "$out" rc=)"
out=$(bank "reconciliation.run|CARDCLR")
check "clearing.credit.recon" "00" "$(value "$out" rc=)"

out=$(bank "customer.create|P|FEE CUST|CPF|44455566677|19750101|OP01")
check "clearing.fee.customer" "C00000000002" "$(value "$out" id=)"
out=$(bank "account.open|C00000000002|DMND|BRL|500000|OP01|CO|OA2")
check "clearing.fee.account" "A00000000002" "$(value "$out" id=)"
out=$(bank "cards.create|CDEB|C00000000002|A00000000002||BRL")
check "clearing.fee.card" "U00000000002" "$(value "$out" card=)"
bank "cards.approve|U00000000002||OP01" >/dev/null
bank "cards.issue|U00000000002|S|OP01" >/dev/null
bank "cards.activate|U00000000002||OP01" >/dev/null
out=$(bank "clearing.ingest|VISA|EXT-FEE1|U00000000002|1200|BRL|FEE|||5999|POS||20261005||B02||||OP01|CORC|FE1")
check "clearing.fee.ingest" "Y00000000003" "$(value "$out" clr=)"
out=$(bank "clearing.match|Y00000000003|OP01|CORC|FEM")
check "clearing.fee.match" "NO-AUTH" "$(value "$out" match=)"
out=$(bank "clearing.post|Y00000000003||OP01|CORC|FEP")
check "clearing.fee.post" "POSTED" "$(value "$out" post=)"
out=$(bank "ledger.balance|A00000000002")
check "clearing.fee.debit" "498800.00" "$(value "$out" available=)"
out=$(bank "clearing.ingest|VISA|EXT-FEE1|U00000000002|1200|BRL|FEE|||5999|POS||20261005||B02||||OP01|CORC|FE2")
check "clearing.fee.replay" "Y00000000003" "$(value "$out" clr=)"
grep -aqE "4111[0-9]{12}" var/data/crdclr.idx && leak=yes || leak=no
check "clearing.credit.security.no.pan" "no" "$leak"

# --- pix keys / DICT / QR / payments / devolution ---
out=$(bank "pix.rt.create|12345678|KOF PIX SERVICOS|DEBITS|DPI|Y||OP01|CORP|PRT1")
check "pix.rt.self" "ACTIVE" "$(value "$out" status=)"
out=$(bank "pix.rt.create|87654321|BANCO OUTRO PIX|DEBITS|DPI|N||OP01|CORP|PRT2")
check "pix.rt.other" "ACTIVE" "$(value "$out" status=)"
rtid=$(value "$out" id=)
out=$(bank "pix.rt.get|$rtid")
check "pix.rt.get.ispb" "87654321" "$(value "$out" ispb=)"
out=$(bank "pix.rt.get|P00000000001")
check "pix.rt.get.self" "12345678" "$(value "$out" ispb=)"

out=$(bank "customer.create|P|PIX PAGADOR|CPF|123.456.789-09|19900101|OP01|PX1")
pixpc1=$(value "$out" id=)
out=$(bank "account.open|$pixpc1|DMND|BRL|500000|OP01|PX2|O1")
pixa1=$(value "$out" id=)
out=$(bank "customer.create|P|PIX RECEBEDOR|CPF|234.567.890-92|19900101|OP01|PX3")
pixpc2=$(value "$out" id=)
out=$(bank "account.open|$pixpc2|DMND|BRL|500000|OP01|PX4|O2")
pixa2=$(value "$out" id=)
out=$(bank "customer.create|P|PIX POBRE|CPF|345.678.901-75|19900101|OP01|PX5")
pixpc3=$(value "$out" id=)
out=$(bank "account.open|$pixpc3|DMND|BRL|100|OP01|PX6|O3")
pixa3=$(value "$out" id=)
out=$(bank "account.open|$pixpc1|DMND|BRL|3000000|OP01|PX7|O4")
pixrich=$(value "$out" id=)

out=$(bank "pix.key.register|CPF|234.567.890-92|$pixa2|$pixpc2|OP01|COR|KR1")
check "pix.key.register.rc" "00" "$(value "$out" rc=)"
check "pix.key.register.status" "ACTIVE" "$(value "$out" status=)"
pixkey=$(value "$out" id=)
mask=$(value "$out" mask=)
case "$mask" in
    *"*"*) masked=yes ;;
    *) masked=no ;;
esac
check "pix.key.register.masked" "yes" "$masked"
grep -aq "23456789092" var/data/pxkey.idx && keyleak=yes || keyleak=no
check "pix.key.store.no.clear.value" "no" "$keyleak"
out=$(bank "pix.key.register|CPF|23456789092|$pixa2|$pixpc2|OP01|COR|KR2")
check "pix.key.duplicate.normalized" "22" "$(value "$out" rc=)"
out=$(bank "pix.key.register|CPF|111.111.111-11|$pixa2|$pixpc2|OP01|COR|KR3")
check "pix.key.invalid.cpf" "20" "$(value "$out" rc=)"
out=$(bank "pix.key.lookup|CPF|23456789092")
check "pix.key.lookup.id" "$pixkey" "$(value "$out" id=)"
out=$(bank "pix.key.lookup|CPF|99988877766")
check "pix.key.lookup.missing" "20" "$(value "$out" rc=)"
out=$(bank "pix.key.list|$pixa2")
check "pix.key.list.count" "0001" "$(value "$out" count=)"
out=$(bank "pix.key.register|EMAIL|joao.lima@KofBank.com|$pixa2|$pixpc2|OP01|COR|KR4")
check "pix.key.email.register" "00" "$(value "$out" rc=)"
pixemail=$(value "$out" id=)
out=$(bank "pix.key.lookup|EMAIL|JOAO.LIMA@KOFBANK.COM")
check "pix.key.email.canonical" "$pixemail" "$(value "$out" id=)"
out=$(bank "pix.key.change|$pixemail|$pixa1|OP01|COR|KR5")
check "pix.key.change.acct" "$pixa1" "$(value "$out" acct=)"
out=$(bank "pix.key.delete|$pixemail|OP01|COR|KR6")
check "pix.key.delete.status" "REVOKED" "$(value "$out" status=)"
out=$(bank "pix.key.lookup|EMAIL|joao.lima@kofbank.com")
check "pix.key.lookup.deleted" "23" "$(value "$out" rc=)"

out=$(bank "pix.qr.create|STATIC|$pixa2|$pixkey|CPF|23456789092|25.00|PIX MERCHANT|SAO PAULO|0000|OP01|COR|QC1")
check "pix.qr.static.rc" "00" "$(value "$out" rc=)"
staticpayload=$(grep -F "payload=" <<<"$out" | head -1 | sed "s/^payload=//; s/[[:space:]]*$//")
staticqr=$(value "$out" id=)
check "pix.qr.static.status" "PUBLISHED" "$(value "$out" status=)"
case "$staticpayload" in
    "000201"*) emvok=yes ;;
    *) emvok=no ;;
esac
check "pix.qr.static.payload.prefix" "yes" "$emvok"
out=$(bank "pix.qr.parse|$staticpayload")
check "pix.qr.parse.ok" "00" "$(value "$out" rc=)"
check "pix.qr.parse.amount" "25.00" "$(value "$out" amount=)"
tampered="$(printf '%s' "$staticpayload" | sed 's/PIX MERCHANT/PIX MERCHANTX/')"
out=$(bank "pix.qr.parse|$tampered")
check "pix.qr.parse.tamper.crc" "20" "$(value "$out" rc=)"
out=$(bank "pix.qr.parse|00020126580014br.gov.bcb.pix0136123e4567e89b12d3a45642661417400005204000053039865802BR5913NOMEGA6009BRASILIA62070503***63041234")
check "pix.qr.parse.bad.crc" "20" "$(value "$out" rc=)"

out=$(bank "pix.qr.create|DYNAMIC|$pixa2|$pixkey|CPF|23456789092|30.00|PIX MERCHANT|SAO PAULO|0000|OP01|COR|QC2")
check "pix.qr.dynamic.rc" "00" "$(value "$out" rc=)"
dynqr=$(value "$out" id=)
check "pix.qr.dynamic.published" "PUBLISHED" "$(value "$out" status=)"
out=$(bank "pix.qr.read|$dynqr|OP01|COR|QR1")
check "pix.qr.read.status" "READ" "$(value "$out" status=)"
check "pix.qr.read.count" "00001" "$(value "$out" reads=)"
out=$(bank "pix.out.qr|$dynqr|30.00|$pixa1||pix via qr|OP01|COR|PQ1")
check "pix.qr.pay.posted" "POSTED" "$(value "$out" status=)"
check "pix.qr.pay.qrid" "$dynqr" "$(value "$out" qrid=)"
qrpix=$(value "$out" id=)
out=$(bank "pix.qr.get|$dynqr")
check "pix.qr.paid.status" "PAID" "$(value "$out" status=)"
check "pix.qr.paid.link" "$qrpix" "$(value "$out" pix=)"
out=$(bank "pix.out.qr|$dynqr|30.00|$pixa1||pix via qr twice|OP01|COR|PQ2")
check "pix.qr.double.pay.blocked" "20" "$(value "$out" rc=)"

out=$(bank "pix.out.key|$pixkey|100.00|$pixa1|||transferencia pix|OP01|COR|PK1||Y")
pixout=$(value "$out" id=)
check "pix.out.key.posted" "POSTED" "$(value "$out" status=)"
check "pix.out.key.payer" "$pixa1" "$(value "$out" payer=)"
check "pix.out.key.payee" "$pixa2" "$(value "$out" payee=)"
check "pix.out.key.linked.txn" "Y" "$(test -n "$(value "$out" txn=)" -a -n "$(value "$out" journal=)" && echo Y || echo N)"
out=$(bank "ledger.balance|$pixa1")
check "pix.out.key.debit" "499870.00" "$(value "$out" available=)"
out=$(bank "ledger.balance|$pixa2")
check "pix.out.key.credit" "500130.00" "$(value "$out" available=)"
out=$(bank "pix.out.key|$pixkey|100.00|$pixa1|||transferencia pix|OP01|COR|PK1||Y")
check "pix.idempotent.replay" "Y" "$(value "$out" replay=)"
check "pix.idempotent.same.id" "$pixout" "$(value "$out" id=)"
out=$(bank "ledger.balance|$pixa1")
check "pix.idempotent.no.double.debit" "499870.00" "$(value "$out" available=)"
out=$(bank "pix.out.key|$pixkey|1200000.00|$pixrich|||acima do limite de canal|OP01|COR|PK2||Y")
check "pix.limit.channel" "20" "$(value "$out" rc=)"
out=$(bank "ledger.balance|$pixrich")
check "pix.limit.channel.no.debit" "3000000.00" "$(value "$out" available=)"
out=$(bank "pix.out.key|$pixkey|5000.00|$pixa3|||sem fundo|OP01|COR|PK3||Y")
check "pix.insufficient" "20" "$(value "$out" rc=)"
out=$(bank "ledger.balance|$pixa3")
check "pix.insufficient.no.change" "100.00" "$(value "$out" available=)"
out=$(bank "pix.out.key|$pixkey|10.00|$pixa1|||spi timeout|OP01|COR|PK4|TIMEOUT|Y")
check "pix.spi.timeout.status" "TIMEOUT" "$(value "$out" status=)"
check "pix.spi.timeout.rc" "24" "$(value "$out" rc=)"
out=$(bank "pix.out.key|$pixkey|7.77|$pixa1|||spi reject|OP01|COR|PK5|REJECT|Y")
check "pix.spi.reject.status" "REJECTED" "$(value "$out" status=)"
out=$(bank "ledger.balance|$pixa1")
check "pix.spi.failures.no.debit" "499870.00" "$(value "$out" available=)"

out=$(bank "pix.out.key|$pixkey|10.00|$pixrich|||timeout then retry|OP01|COR|PK6|TIMEOUT|Y")
check "pix.timeout.retry.setup" "24" "$(value "$out" rc=)"
pixtt=$(value "$out" id=)
out=$(bank "pix.get|$pixtt")
check "pix.timeout.status.persisted" "TIMEOUT" "$(value "$out" status=)"
out=$(bank "pix.retry|$pixtt||OP01|COR|PK7")
check "pix.timeout.retry.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "ledger.balance|$pixrich")
check "pix.timeout.retry.debit" "2999990.00" "$(value "$out" available=)"

out=$(bank "pix.in|50.00|$pixa1|$rtid|E2EPIXTST0000000000000000001|EXT-PXIN-1|PIX PAGADOR|OP01|COR|PIN1")
check "pix.in.posted" "POSTED" "$(value "$out" status=)"
inid=$(value "$out" id=)
out=$(bank "ledger.balance|$pixa1")
check "pix.in.credit" "499920.00" "$(value "$out" available=)"
out=$(bank "pix.in|50.00|$pixa1|$rtid|E2EPIXTST0000000000000000001|EXT-PXIN-2|PIX PAGADOR|OP01|COR|PIN2")
check "pix.in.duplicate.e2e" "22" "$(value "$out" rc=)"
out=$(bank "pix.get.e2e|E2EPIXTST0000000000000000001")
check "pix.get.e2e.id" "$inid" "$(value "$out" id=)"

out=$(bank "pix.devol|$pixout|40.00|estorno parcial|OP01|COR|DV1")
check "pix.devol.partial.rc" "00" "$(value "$out" rc=)"
devol1=$(value "$out" id=)
out=$(bank "pix.get|$pixout")
check "pix.devol.partial.status" "PARTIAL" "$(value "$out" dev=)"
check "pix.devol.partial.amount" "40.00" "$(value "$out" blocked=)"
check "pix.devol.partial.link" "$devol1" "$(value "$out" devol=)"
out=$(bank "ledger.balance|$pixa1")
check "pix.devol.partial.refund" "499960.00" "$(value "$out" available=)"
out=$(bank "pix.devol|$pixout|60.00|estorno total|OP01|COR|DV2")
check "pix.devol.full.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.devol|$pixout|1.00|excesso|OP01|COR|DV3")
check "pix.devol.over.blocked" "20" "$(value "$out" rc=)"
out=$(bank "pix.get|$pixout")
check "pix.devol.full.status" "FULL" "$(value "$out" dev=)"
check "pix.devol.orig.pix.status" "DEVOLVED" "$(value "$out" status=)"
out=$(bank "ledger.balance|$pixa1")
check "pix.devol.restores.balance" "500020.00" "$(value "$out" available=)"
out=$(bank "pix.devol|$inid|50.00|devolucao de entrada|OP01|COR|DV4")
check "pix.devol.inbound.rc" "00" "$(value "$out" rc=)"
out=$(bank "ledger.balance|$pixa1")
check "pix.devol.inbound.debit" "499970.00" "$(value "$out" available=)"


sed -i 's/business-date=.*/business-date=2026-10-02/' etc/bank.cfg
reset
bank "ledger.init" >/dev/null
out=$(bank "pix.rt.create|12345678|KOF SELF|DEBITS|DPI|Y||OP01|COR|SRT1")
check "pix.stl.self.rt" "00" "$(value "$out" rc=)"
out=$(bank "pix.rt.create|87654321|BANCO OUTRO|DEBITS|DPI|N||OP01|COR|SRT2")
stlrt=$(value "$out" id=)
out=$(bank "customer.create|P|STL PAGADOR|CPF|123.456.789-09|19900101|OP01|SC1")
stlc1=$(value "$out" id=)
out=$(bank "account.open|$stlc1|DMND|BRL|500000|OP01|SC2|O1")
stlpayer=$(value "$out" id=)
out=$(bank "customer.create|P|STL RECEBEDOR|CPF|234.567.890-92|19900101|OP01|SC3")
stlc2=$(value "$out" id=)
out=$(bank "account.open|$stlc2|DMND|BRL|500000|OP01|SC4|O2")
stlpayee=$(value "$out" id=)
out=$(bank "pix.key.register|CPF|234.567.890-92|$stlpayee|$stlc2|OP01|COR|SK1")
stlkey=$(value "$out" id=)
out=$(bank "pix.key.seed|CPF|13579111140|$stlrt|FX000000001|FXC0000001|OUT CLIENTE|OP01|COR|SK2")
check "pix.stl.key.seeded" "00" "$(value "$out" rc=)"
stlforeign=$(value "$out" keyid=)
out=$(bank "pix.out.key|$stlkey|100.00|$stlpayer|||pix local|OP01|COR|SK3||Y")
check "pix.stl.local.posted" "POSTED" "$(value "$out" status=)"
check "pix.stl.local.not.settleable" "PENDING" "$(value "$out" settle=)"
out=$(bank "pix.out.key|$stlforeign|150.00|$stlpayer|||pix externo|OP01|COR|SK4||Y")
check "pix.stl.out.posted" "POSTED" "$(value "$out" status=)"
check "pix.stl.out.pending" "PENDING" "$(value "$out" settle=)"
check "pix.stl.out.payeepart" "$stlrt" "$(value "$out" payeepart=)"
out=$(bank "pix.in|50.00|$stlpayee|$stlrt|E2ESETL0000000000000000001|EXT-STL-1|PAGADOR EXTERNO|OP01|COR|SK5")
check "pix.stl.in.posted" "POSTED" "$(value "$out" status=)"
stlin=$(value "$out" id=)
out=$(bank "pix.out.key|$stlforeign|70.00|$stlpayer|||a devolver|OP01|COR|SK6||Y")
stldvl=$(value "$out" id=)
out=$(bank "pix.devol|$stldvl|70.00|estorno integral|OP01|COR|SK7")
check "pix.stl.devol.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.get|$stlin")
check "pix.stl.in.self.settle" "PENDING" "$(value "$out" settle=)"

out=$(bank "pix.cycle.open|20261002|BRL|||||OP01|COR|SO1")
check "pix.stl.cycle.open.rc" "00" "$(value "$out" rc=)"
check "pix.stl.cycle.open.status" "OPEN" "$(value "$out" status=)"
cyc=$(value "$out" cycle=)
check "pix.stl.cycle.id" "CYC20261002BRL123456" "$cyc"
out=$(bank "pix.cycle.open|20261002|BRL|||||OP01|COR|SO2")
check "pix.stl.cycle.replay" "Y" "$(value "$out" replay=)"
out=$(bank "pix.cycle.accrue|20261002|BRL|||||OP01|COR|SA1")
check "pix.stl.accrue.rc" "00" "$(value "$out" rc=)"
check "pix.stl.accrue.cycle" "$cyc" "$(value "$out" cycle=)"
check "pix.stl.accrue.status" "ACCUMULATING" "$(value "$out" status=)"
check "pix.stl.accrue.grosspay" "150.00" "$(value "$out" grosspay=)"
check "pix.stl.accrue.grossrcv" "120.00" "$(value "$out" grossrcv=)"
out=$(bank "pix.get|$stlin")
check "pix.stl.in.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.cycle.accrue|20261002|BRL|||||OP01|COR|SA1")
check "pix.stl.accrue.idempotent" "22" "$(value "$out" rc=)"
out=$(bank "pix.cycle.close|$cyc|||||OP01|COR|SC1")
check "pix.stl.close" "CLOSED" "$(value "$out" status=)"
out=$(bank "pix.cycle.calc|$cyc|||||OP01|COR|SC2")
check "pix.stl.calc.status" "CALCULATED" "$(value "$out" status=)"
check "pix.stl.calc.txns" "0000003" "$(value "$out" txns=)"
check "pix.stl.calc.obligations" "0000002" "$(value "$out" obligations=)"
check "pix.stl.calc.parties" "0000001" "$(value "$out" parties=)"
check "pix.stl.calc.grosspay" "150.00" "$(value "$out" grosspay=)"
check "pix.stl.calc.grossrcv" "120.00" "$(value "$out" grossrcv=)"
check "pix.stl.calc.net" "30.00" "$(value "$out" net=)"
check "pix.stl.calc.side" "PAYABLE" "$(value "$out" side=)"
out=$(bank "pix.cycle.submit|$cyc||||||OP01|COR|SS1")
check "pix.stl.submit.status" "SUBMITTED" "$(value "$out" status=)"
out=$(bank "pix.stl.list|$cyc")
check "pix.stl.list.count" "0000002" "$(value "$out" settlements=)"
check "pix.stl.list.submitted" "2" "$(grep -c "status=SUBMITTED" <<<"$out")"
check "pix.stl.list.extref" "2" "$(grep -c "extref=SPIS-" <<<"$out")"
out=$(bank "pix.stl.get|S00000000001")
check "pix.stl.payable.side" "PAYABLE" "$(value "$out" side=)"
check "pix.stl.payable.gross" "150.00" "$(value "$out" gross=)"
check "pix.stl.payable.part" "$stlrt" "$(value "$out" participant=)"
out=$(bank "pix.stl.get|S00000000002")
check "pix.stl.receivable.side" "RECEIVABLE" "$(value "$out" side=)"
check "pix.stl.receivable.net" "120.00" "$(value "$out" net=)"
out=$(bank "pix.cycle.submit|$cyc||||||OP01|COR|SS1")
check "pix.stl.submit.idempotent" "22" "$(value "$out" rc=)"
out=$(bank "pix.stl.get|S00000000001")
check "pix.stl.attempts.once" "0001" "$(value "$out" attempts=)"
out=$(bank "ledger.balance|$stlpayer")
stlpaybal0=$(value "$out" available=)
out=$(bank "ledger.balance|$stlpayee")
stlrecvbal0=$(value "$out" available=)
out=$(bank "pix.stl.result|S00000000001||SETTLED|SPIRES-1|liquidado||OP01|COR|SR1")
check "pix.stl.result.rc" "00" "$(value "$out" rc=)"
check "pix.stl.result.status" "SETTLED" "$(value "$out" status=)"
check "pix.stl.result.amount" "150.00" "$(value "$out" settledamt=)"
check "pix.stl.result.ref" "SPIRES-1" "$(value "$out" resultref=)"
out=$(bank "pix.cycle.finalize|$cyc|||||OP01|COR|SF1")
check "pix.stl.finalize.incomplete" "21" "$(value "$out" rc=)"
case "$out" in
    *"CYCLE NOT READY"*) stlnr=yes ;;
    *) stlnr=no ;;
esac
check "pix.stl.finalize.incomplete.msg" "yes" "$stlnr"
out=$(bank "pix.stl.result|S00000000002||SETTLED|SPIRES-2|liquidado||OP01|COR|SR2")
check "pix.stl.result.in" "SETTLED" "$(value "$out" status=)"
check "pix.stl.result.in.amount" "120.00" "$(value "$out" settledamt=)"
out=$(bank "pix.cycle.finalize|$cyc|||||OP01|COR|SF1")
check "pix.stl.finalize.status" "SETTLED" "$(value "$out" status=)"
out=$(bank "pix.cycle.finalize|$cyc|||||OP01|COR|SF1")
check "pix.stl.finalize.idempotent" "22" "$(value "$out" rc=)"
out=$(bank "pix.stl.post|S00000000001||||OP01|COR|SP1")
check "pix.stl.post.pay.rc" "00" "$(value "$out" rc=)"
check "pix.stl.post.pay.status" "POSTED" "$(value "$out" post=)"
stl1jrnl=$(value "$out" journal=)
case "$stl1jrnl" in
    STL*) check "pix.stl.post.journal" "Y" "Y" ;;
    *) check "pix.stl.post.journal" "Y" "N" ;;
esac
out=$(bank "pix.stl.post|S00000000002||||OP01|COR|SP2")
check "pix.stl.post.rcv" "POSTED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|S00000000001||||OP01|COR|SP1")
check "pix.stl.post.replay" "Y" "$(value "$out" replay=)"
check "pix.stl.post.replay.journal" "$stl1jrnl" "$(value "$out" journal=)"
out=$(bank "ledger.balance|$stlpayer")
check "pix.stl.customer.untouched.payer" "$stlpaybal0" "$(value "$out" available=)"
out=$(bank "ledger.balance|$stlpayee")
check "pix.stl.customer.untouched.payee" "$stlrecvbal0" "$(value "$out" available=)"
glstl=$(grep -c "|STLS" var/journal/postings.log)
check "pix.stl.gl.lines" "4" "$glstl"
out=$(bank "pix.pos.rebuild|P00000000002|BRL|||||OP01|COR|SPR1")
check "pix.stl.pos.rebuild.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.pos.list")
check "pix.stl.pos.count" "0000001" "$(value "$out" positions=)"
check "pix.stl.pos.part" "$stlrt" "$(value "$out" participant=)"
check "pix.stl.pos.settledpay" "150.00" "$(value "$out" settledpay=)"
check "pix.stl.pos.settledrcv" "120.00" "$(value "$out" settledrcv=)"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-1||OP01|COR")
check "pix.stl.recon.balanced" "BALANCED" "$(value "$out" msg=)"
check "pix.stl.recon.matched" "000000002" "$(value "$out" matched=)"
check "pix.stl.recon.unmatched" "000000000" "$(value "$out" unmatched=)"
check "pix.stl.recon.openexc" "000000000" "$(value "$out" openexc=)"
out=$(bank "pix.cycle.get|$cyc|||||OP01|COR|SG1")
check "pix.stl.cycle.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.cycle.recon" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.stl.get|S00000000001")
check "pix.stl.obligation.recon" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.obligation.match" "MATCHED" "$(value "$out" recon=)"
out=$(bank "reconciliation.exceptions|REC-STL-1")
check "pix.stl.recon.no.exc" "000000000" "$(value "$out" exceptions=)"
out=$(bank "ledger.trial")
check "pix.stl.trial.balanced" "BALANCED" "$(value "$out" msg=)"

sed -i 's/business-date=.*/business-date=2026-10-03/' etc/bank.cfg
out=$(bank "pix.out.key|$stlforeign|200.00|$stlpayer|||pix ciclo b|OP01|COR|SK8||Y")
stlbout=$(value "$out" id=)
out=$(bank "ledger.balance|$stlpayer")
stlbpay0=$(value "$out" available=)
out=$(bank "pix.in|60.00|$stlpayee|$stlrt|E2ESETL0000000000000000002|EXT-STL-2|PAGADOR B|OP01|COR|SK9")
check "pix.stl.b.in.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.cycle.accrue|20261003|BRL|||||OP01|COR|SA2")
check "pix.stl.b.accrue.rc" "00" "$(value "$out" rc=)"
cycb=$(value "$out" cycle=)
check "pix.stl.b.cycle" "CYC20261003BRL123456" "$cycb"
check "pix.stl.b.grosspay" "200.00" "$(value "$out" grosspay=)"
check "pix.stl.b.grossrcv" "60.00" "$(value "$out" grossrcv=)"
out=$(bank "pix.get|$stlbout")
check "pix.stl.b.out.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.stl.list|$cycb")
stlbpay=$(awk '/^settlement=/{id=substr($0,12)}
    /^side=PAYABLE/{print id; exit}' <<<"$out")
stlbcv=$(awk '/^settlement=/{id=substr($0,12)}
    /^side=RECEIVABLE/{print id; exit}' <<<"$out")
out=$(bank "pix.stl.adjust|$stlbpay|10.00|tarifa de liquidez||||OP01|COR|SAJ1")
check "pix.stl.adjust.rc" "00" "$(value "$out" rc=)"
check "pix.stl.adjust.amount" "10.00" "$(value "$out" adjust=)"
check "pix.stl.adjust.net" "190.00" "$(value "$out" net=)"
out=$(bank "pix.stl.adjust|$stlbpay|10.00|duplicado||||OP01|COR|SAJ1")
check "pix.stl.adjust.idempotent" "22" "$(value "$out" rc=)"
out=$(bank "pix.stl.get|$stlbpay")
check "pix.stl.adjust.replay.amount" "10.00" "$(value "$out" adjust=)"
out=$(bank "pix.cycle.close|$cycb|||||OP01|COR|SC3")
check "pix.stl.b.close" "CLOSED" "$(value "$out" status=)"
out=$(bank "pix.cycle.calc|$cycb|||||OP01|COR|SC4")
check "pix.stl.b.calc.status" "CALCULATED" "$(value "$out" status=)"
check "pix.stl.b.calc.net" "130.00" "$(value "$out" net=)"
check "pix.stl.b.calc.grosspay" "190.00" "$(value "$out" grosspay=)"
check "pix.stl.b.calc.obligations" "0000002" "$(value "$out" obligations=)"
out=$(bank "pix.cycle.submit|$cycb||||||OP01|COR|SS2")
check "pix.stl.b.submit" "SUBMITTED" "$(value "$out" status=)"
out=$(bank "pix.stl.result|$stlbpay||SETTLED|SPIRES-3|valor menor|180.00|OP01|COR|SR3")
check "pix.stl.b.result.amount" "180.00" "$(value "$out" settledamt=)"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-2||OP01|COR")
check "pix.stl.b.recon.exc" "EXCEPTIONS" "$(value "$out" msg=)"
check "pix.stl.b.recon.open" "000000002" "$(value "$out" openexc=)"
out=$(bank "reconciliation.exceptions|REC-STL-2")
check "pix.stl.b.exc.count" "000000002" "$(value "$out" exceptions=)"
case "$out" in
    *AMT_MISMATCH*) stlamt=yes ;;
    *) stlamt=no ;;
esac
check "pix.stl.b.exc.amount.code" "yes" "$stlamt"
case "$out" in
    *STALE_SETTLE*) stlstale=yes ;;
    *) stlstale=no ;;
esac
check "pix.stl.b.exc.stale.code" "yes" "$stlstale"
out=$(bank "pix.cycle.get|$cycb|||||OP01|COR|SG2")
check "pix.stl.b.cycle.exc" "RECON-EXCEPTION" "$(value "$out" status=)"
check "pix.stl.b.cycle.recon" "EXCEPTION" "$(value "$out" recon=)"
out=$(bank "pix.stl.get|$stlbpay")
check "pix.stl.b.obligation.recon" "EXCEPTION" "$(value "$out" recon=)"
out=$(bank "pix.cycle.finalize|$cycb|||||OP01|COR|SF2")
check "pix.stl.b.finalize.blocked" "21" "$(value "$out" rc=)"
out=$(bank "pix.stl.get|$stlbcv")
check "pix.stl.b.stale.status" "SUBMITTED" "$(value "$out" status=)"
out=$(bank "ledger.balance|$stlpayer")
check "pix.stl.b.balance.unchanged" "$stlbpay0" "$(value "$out" available=)"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-3||OP01|COR")
check "pix.stl.b.recon.repeat" "EXCEPTIONS" "$(value "$out" msg=)"

sed -i 's/business-date=.*/business-date=2026-10-04/' etc/bank.cfg
out=$(bank "pix.cycle.open|20261004|BRL|||||OP01|COR|SO3")
check "pix.stl.eod.cycle" "CYC20261004BRL123456" "$(value "$out" cycle=)"
cycd=$(value "$out" cycle=)
out=$(bank "pix.cycle.accrue|20261004|BRL|||||OP01|COR|SA3")
check "pix.stl.eod.empty" "00" "$(value "$out" rc=)"
out=$(bank "pix.cycle.get|$cycd|||||OP01|COR|SG3")
check "pix.stl.eod.empty.status" "OPEN" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|90.00|$stlpayer|||pix eod|OP01|COR|SEA||Y")
check "pix.stl.eod.out.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.in|30.00|$stlpayee|$stlrt|E2ESETL0000000000000000003|EXT-STL-3|PAGADOR C|OP01|COR|SEB")
check "pix.stl.eod.in.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "ledger.balance|$stlpayer")
eodpay0=$(value "$out" available=)
out=$(bank "batch.eod")
check "pix.stl.eod.batch.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.cycle.get|$cycd|||||OP01|COR|SG4")
check "pix.stl.eod.finalized" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.eod.recon" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.stl.list|$cycd")
check "pix.stl.eod.obligations" "0000002" "$(value "$out" settlements=)"
check "pix.stl.eod.reconciled" "2" "$(grep -c "status=RECONCILED" <<<"$out")"
check "pix.stl.eod.posted" "2" "$(grep -c "post=POSTED" <<<"$out")"
outeod=$(bank "pix.stl.list|$cycd")
stleodpay=$(awk '/^settlement=/{id=substr($0,12)}
    /^side=PAYABLE/{print id; exit}' <<<"$outeod")
out=$(bank "pix.stl.get|$stleodpay")
check "pix.stl.eod.journal" "Y" "$(test -n "$(value "$out" journal=)" && echo Y || echo N)"
out=$(bank "ledger.balance|$stlpayer")
check "pix.stl.eod.customer.untouched" "$eodpay0" "$(value "$out" available=)"
out=$(bank "ledger.trial")
check "pix.stl.eod.trial" "BALANCED" "$(value "$out" msg=)"
out=$(bank "batch.eod")
check "pix.stl.eod.rerun.rc" "00" "$(value "$out" rc=)"
glstl2=$(grep -c "|STLS" var/journal/postings.log)
check "pix.stl.eod.rerun.no.double" "8" "$glstl2"
out=$(bank "ledger.trial")
check "pix.stl.eod.rerun.trial" "BALANCED" "$(value "$out" msg=)"
out=$(bank "pix.pos.list")
check "pix.stl.pos.settledpay.total" "420.00" "$(value "$out" settledpay=)"
check "pix.stl.pos.settledrcv.total" "150.00" "$(value "$out" settledrcv=)"
check "pix.stl.pos.pending.total" "0000001" "$(value "$out" pending=)"
check "pix.stl.pos.settledrcv.eod" "150.00" "$(value "$out" settledrcv=)"

# ---------- pix MED (Mecanismo Especial de Devolucao) domain ----------
sed -i 's/business-date=.*/business-date=2026-10-02/' etc/bank.cfg
reset
bank "ledger.init" >/dev/null
out=$(bank "pix.rt.create|12345678|KOF MED SELF|DEBITS|DPI|Y||OP01|COR|MRT1")
check "pix.med.self.rt" "00" "$(value "$out" rc=)"
out=$(bank "pix.rt.create|87654321|BANCO OUTRO MED|DEBITS|DPI|N||OP01|COR|MRT2")
med_foreign=$(value "$out" id=)

MEDN=0
med_case() {
    MEDN=$((MEDN + 1))
    local cpayer cpayee key
    cpayer=$(printf '1%010d' "$MEDN")
    cpayee=$(printf '2%010d' "$MEDN")
    out=$(bank "customer.create|P|MEDP$MEDN|CPF|$cpayer|19900101|OP01|M${MEDN}p")
    MED_PAYER_CUST=$(value "$out" id=)
    out=$(bank "account.open|$MED_PAYER_CUST|DMND|BRL|500000|OP01|M${MEDN}pa|MQ${MEDN}a")
    MED_PAYER=$(value "$out" id=)
    out=$(bank "customer.create|P|MEDR$MEDN|CPF|$cpayee|19900101|OP01|M${MEDN}r")
    MED_PAYEE_CUST=$(value "$out" id=)
    out=$(bank "account.open|$MED_PAYEE_CUST|DMND|BRL|500000|OP01|M${MEDN}ra|MQ${MEDN}b")
    MED_PAYEE=$(value "$out" id=)
    out=$(bank "pix.key.register|EMAIL|medpayee${MEDN}@example.com|$MED_PAYEE|$MED_PAYEE_CUST|OP01|COR|M${MEDN}k")
    key=$(value "$out" id=)
    out=$(bank "pix.out.key|$key|1000.00|$MED_PAYER|||pix fraudado|OP01|COR|M${MEDN}x||Y")
    MED_PIX=$(value "$out" id=)
    MED_PIX_STATUS=$(value "$out" status=)
}

# --- scenario A: full lifecycle, funds reserved then devoluted exactly once ---
med_case
check "pix.med.A.posted" "POSTED" "$MED_PIX_STATUS"
out=$(bank "pix.med.open|$MED_PIX|1000.00|BRL|$MED_PAYEE_CUST|PAYEE|FRAUDE|Y|OP01|MA1|MRQ1")
medA=$(value "$out" medcase=); medAfraud=$(value "$out" fraud=)
check "pix.med.A.open.rc" "00" "$(value "$out" rc=)"
check "pix.med.A.open.status" "OPEN" "$(value "$out" status=)"
check "pix.med.A.open.fraud" "Y" "$medAfraud"
check "pix.med.A.open.origamount" "1000.00" "$(value "$out" origamount=)"
out=$(bank "pix.get|$MED_PIX")
check "pix.med.A.link" "$medA" "$(value "$out" medcase=)"
check "pix.med.A.orig.immutable" "1000.00" "$(value "$out" amount=)"
out=$(bank "pix.med.validate|$medA|OP01|MA2")
check "pix.med.A.validate.rc" "00" "$(value "$out" rc=)"
check "pix.med.A.validate.status" "BLOCK-PEND" "$(value "$out" status=)"
check "pix.med.A.validate.eligible" "1000.00" "$(value "$out" eligible=)"
out=$(bank "pix.med.block|$medA|OP01|MA3")
check "pix.med.A.block.rc" "00" "$(value "$out" rc=)"
check "pix.med.A.block.status" "BLOCKED" "$(value "$out" status=)"
check "pix.med.A.block.amount" "1000.00" "$(value "$out" blocked=)"
medAhold=$(value "$out" hold=)
check "pix.med.A.block.holdid" "Y" "$(test -n "$medAhold" && echo Y || echo N)"
out=$(bank "ledger.balance|$MED_PAYEE")
check "pix.med.A.block.avail" "500000.00" "$(value "$out" available=)"
check "pix.med.A.block.ledger" "501000.00" "$(value "$out" ledger=)"
out=$(bank "pix.med.block|$medA|OP01|MA3b")
check "pix.med.A.block.replay" "00" "$(value "$out" rc=)"
out=$(bank "pix.med.decide|$medA|APPROVE||fundamentado|OP01|MA4")
check "pix.med.A.decide.rc" "00" "$(value "$out" rc=)"
check "pix.med.A.decide.status" "APPROVED" "$(value "$out" status=)"
check "pix.med.A.decide.amount" "1000.00" "$(value "$out" decamount=)"
out=$(bank "pix.med.execute|$medA||OP01|MA5")
medAdevol=$(value "$out" devol=)
check "pix.med.A.exec.rc" "00" "$(value "$out" rc=)"
check "pix.med.A.exec.status" "DEVOLVED" "$(value "$out" status=)"
check "pix.med.A.exec.returned" "1000.00" "$(value "$out" returned=)"
check "pix.med.A.exec.devol" "Y" "$(test -n "$medAdevol" && echo Y || echo N)"
out=$(bank "pix.med.execute|$medA||OP01|MA6")
check "pix.med.A.exec.replay" "DEVOLVED" "$(value "$out" status=)"
check "pix.med.A.exec.replayflag" "Y" "$(value "$out" replay=)"
out=$(bank "ledger.balance|$MED_PAYEE")
check "pix.med.A.final.payee.ledger" "500000.00" "$(value "$out" ledger=)"
check "pix.med.A.final.payee.blocked" "0.00" "$(value "$out" blocked=)"
out=$(bank "ledger.balance|$MED_PAYER")
check "pix.med.A.final.payer.avail" "500000.00" "$(value "$out" available=)"
out=$(bank "pix.get|$MED_PIX")
check "pix.med.A.orig.dev" "FULL" "$(value "$out" dev=)"
check "pix.med.A.orig.status" "DEVOLVED" "$(value "$out" status=)"
check "pix.med.A.orig.devol" "$medAdevol" "$(value "$out" devol=)"
out=$(bank "pix.get|$medAdevol")
check "pix.med.A.devol.amount" "1000.00" "$(value "$out" amount=)"
out=$(bank "pix.med.close|$medA|OP01|MA7")
check "pix.med.A.close.rc" "00" "$(value "$out" rc=)"
check "pix.med.A.close.status" "CLOSED" "$(value "$out" status=)"
out=$(bank "ledger.trial")
check "pix.med.A.trial" "BALANCED" "$(value "$out" msg=)"

# --- scenario B: rejected after block -> hold released, NO financial effect ---
med_case
out=$(bank "pix.med.open|$MED_PIX|1000.00|BRL|$MED_PAYEE_CUST|PAYEE|FRAUDE|Y|OP01|MB1|MRQ2")
medB=$(value "$out" medcase=)
bank "pix.med.validate|$medB|OP01|MB2" >/dev/null
bank "pix.med.block|$medB|OP01|MB3" >/dev/null
out=$(bank "ledger.balance|$MED_PAYEE")
check "pix.med.B.blocked.avail" "500000.00" "$(value "$out" available=)"
out=$(bank "pix.med.decide|$medB|REJECT||improcedente|OP01|MB4")
check "pix.med.B.reject.rc" "00" "$(value "$out" rc=)"
check "pix.med.B.reject.status" "REJECTED" "$(value "$out" status=)"
out=$(bank "pix.med.release|$medB|OP01|MB5")
check "pix.med.B.release.rc" "00" "$(value "$out" rc=)"
out=$(bank "ledger.balance|$MED_PAYEE")
check "pix.med.B.released.blocked" "0.00" "$(value "$out" blocked=)"
check "pix.med.B.released.avail" "501000.00" "$(value "$out" available=)"
out=$(bank "pix.med.execute|$medB||OP01|MB6")
check "pix.med.B.exec.after.reject" "20" "$(value "$out" rc=)"
check "pix.med.B.no.devol" "NONE" "$(value "$(bank "pix.get|$MED_PIX")" dev=)"
out=$(bank "ledger.trial")
check "pix.med.B.trial" "BALANCED" "$(value "$out" msg=)"

# --- scenario C: ineligible (no fraud indication) ---
med_case
out=$(bank "pix.med.open|$MED_PIX|1000.00|BRL|$MED_PAYEE_CUST|PAYEE|DUVIDA|N|OP01|MC1|MRQ3")
medC=$(value "$out" medcase=)
out=$(bank "pix.med.validate|$medC|OP01|MC2")
check "pix.med.C.inelig.rc" "00" "$(value "$out" rc=)"
check "pix.med.C.inelig.status" "INELIGIBLE" "$(value "$out" status=)"
out=$(bank "pix.med.block|$medC|OP01|MC3")
check "pix.med.C.block.blocked" "20" "$(value "$out" rc=)"

# --- scenario D: partial approval + partial devolution ---
med_case
out=$(bank "pix.med.open|$MED_PIX|1000.00|BRL|$MED_PAYEE_CUST|PAYEE|FRAUDE|Y|OP01|MD1|MRQ4")
medD=$(value "$out" medcase=)
bank "pix.med.validate|$medD|OP01|MD2" >/dev/null
bank "pix.med.block|$medD|OP01|MD3" >/dev/null
out=$(bank "pix.med.decide|$medD|PARTIAL|400.00|parcial|OP01|MD4")
check "pix.med.D.part.decide" "00" "$(value "$out" rc=)"
check "pix.med.D.part.status" "PART-APPROV" "$(value "$out" status=)"
check "pix.med.D.part.amount" "400.00" "$(value "$out" decamount=)"
out=$(bank "pix.med.execute|$medD||OP01|MD5")
medDdevol=$(value "$out" devol=)
check "pix.med.D.part.exec.rc" "00" "$(value "$out" rc=)"
check "pix.med.D.part.exec.status" "DEVOLVED" "$(value "$out" status=)"
check "pix.med.D.part.exec.returned" "400.00" "$(value "$out" returned=)"
check "pix.med.D.part.remain" "600.00" "$(value "$out" remain=)"
out=$(bank "pix.get|$MED_PIX")
check "pix.med.D.orig.dev" "PARTIAL" "$(value "$out" dev=)"
out=$(bank "pix.med.close|$medD|OP01|MD6")
check "pix.med.D.close.status" "CLOSED" "$(value "$out" status=)"
out=$(bank "ledger.trial")
check "pix.med.D.trial" "BALANCED" "$(value "$out" msg=)"

# --- scenario E: partial reservation when receiver has insufficient funds ---
MEDN=$((MEDN + 1))
eR=$(printf '2%010d' "$MEDN"); eT=$(printf '3%010d' "$MEDN")
out=$(bank "customer.create|P|MEDR$MEDN|CPF|$eR|19900101|OP01|ME${MEDN}r"); erc=$(value "$out" id=)
out=$(bank "account.open|$erc|DMND|BRL|0|OP01|ME${MEDN}ra|ME${MEDN}qa"); epayee=$(value "$out" id=)
out=$(bank "customer.create|P|MEDT$MEDN|CPF|$eT|19900101|OP01|ME${MEDN}t"); etc=$(value "$out" id=)
out=$(bank "account.open|$etc|DMND|BRL|500000|OP01|ME${MEDN}ta|ME${MEDN}qb"); etarget=$(value "$out" id=)
out=$(bank "pix.key.register|EMAIL|medtgt${MEDN}@example.com|$etarget|$etc|OP01|COR|ME${MEDN}k2"); tkey=$(value "$out" id=)
out=$(bank "pix.in|1000.00|$epayee|$med_foreign|E2EMEDL0000000000000000001|EXT-MED-E|PAG EXT|OP01|COR|ME${MEDN}in"); epix=$(value "$out" id=)
check "pix.med.E.in.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "ledger.balance|$epayee"); check "pix.med.E.in.avail" "1000.00" "$(value "$out" available=)"
out=$(bank "pix.out.key|$tkey|700.00|$epayee|||saque|OP01|COR|ME${MEDN}ot||Y")
check "pix.med.E.out.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "ledger.balance|$epayee"); check "pix.med.E.avail.after" "300.00" "$(value "$out" available=)"
out=$(bank "pix.med.open|$epix|1000.00|BRL|$erc|PAYEE|FRAUDE|Y|OP01|ME1|MRQ5"); medE=$(value "$out" medcase=)
bank "pix.med.validate|$medE|OP01|ME2" >/dev/null
out=$(bank "pix.med.block|$medE|OP01|ME3")
check "pix.med.E.block.rc" "00" "$(value "$out" rc=)"
check "pix.med.E.block.status" "BLOCKED" "$(value "$out" status=)"
check "pix.med.E.block.eligible" "300.00" "$(value "$out" eligible=)"
check "pix.med.E.block.blocked" "300.00" "$(value "$out" blocked=)"
out=$(bank "pix.med.decide|$medE|APPROVE||fund|OP01|ME4")
check "pix.med.E.decide.amount" "300.00" "$(value "$out" decamount=)"
out=$(bank "pix.med.execute|$medE||OP01|ME5"); medEdevol=$(value "$out" devol=)
check "pix.med.E.exec.rc" "00" "$(value "$out" rc=)"
check "pix.med.E.exec.status" "DEVOLVED" "$(value "$out" status=)"
check "pix.med.E.exec.returned" "300.00" "$(value "$out" returned=)"
out=$(bank "pix.get|$epix"); check "pix.med.E.orig.dev" "PARTIAL" "$(value "$out" dev=)"
out=$(bank "pix.get|$medEdevol"); check "pix.med.E.devol.amount" "300.00" "$(value "$out" amount=)"
out=$(bank "ledger.trial"); check "pix.med.E.trial" "BALANCED" "$(value "$out" msg=)"

# --- scenario F: timeout -> unknown -> recovery via existing devol id (no duplicate) ---
med_case
out=$(bank "pix.med.open|$MED_PIX|1000.00|BRL|$MED_PAYEE_CUST|PAYEE|FRAUDE|Y|OP01|MF1|MRQ6")
medF=$(value "$out" medcase=)
bank "pix.med.validate|$medF|OP01|MF2" >/dev/null
bank "pix.med.block|$medF|OP01|MF3" >/dev/null
bank "pix.med.decide|$medF|APPROVE||fund|OP01|MF4" >/dev/null
out=$(bank "pix.med.execute|$medF|TIMEOUT|OP01|MF5")
medFdevol=$(value "$out" devol=)
check "pix.med.F.timeout.rc" "24" "$(value "$out" rc=)"
check "pix.med.F.timeout.status" "DEVOLV-UNK" "$(value "$out" status=)"
check "pix.med.F.timeout.devol" "Y" "$(test -n "$medFdevol" && echo Y || echo N)"
out=$(bank "pix.get|$MED_PIX")
check "pix.med.F.orig.still.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.med.execute|$medF||OP01|MF6")
medFdevol2=$(value "$out" devol=)
check "pix.med.F.recover.rc" "00" "$(value "$out" rc=)"
check "pix.med.F.recover.status" "DEVOLVED" "$(value "$out" status=)"
check "pix.med.F.recover.devol" "1000.00" "$(value "$out" returned=)"
check "pix.med.F.recover.sameid" "Y" "$(test "$medFdevol" = "$medFdevol2" && echo Y || echo N)"
out=$(bank "pix.med.execute|$medF||OP01|MF7")
check "pix.med.F.recover.idempotent" "DEVOLVED" "$(value "$out" status=)"
out=$(bank "ledger.balance|$MED_PAYEE")
check "pix.med.F.final.payee.ledger" "500000.00" "$(value "$out" ledger=)"
check "pix.med.F.final.payee.blocked" "0.00" "$(value "$out" blocked=)"
out=$(bank "pix.get|$MED_PIX")
check "pix.med.F.orig.dev" "FULL" "$(value "$out" dev=)"
out=$(bank "ledger.trial")
check "pix.med.F.trial" "BALANCED" "$(value "$out" msg=)"

# --- scenario G: invalid input / bad transitions ---
med_case
out=$(bank "pix.med.open|X00000000999|1000.00|BRL|$MED_PAYEE_CUST|PAYEE|FRAUDE|Y|OP01|MG1|MRQ7")
check "pix.med.G.unknownpix" "20" "$(value "$out" rc=)"
out=$(bank "pix.med.open|$MED_PIX|2000.00|BRL|$MED_PAYEE_CUST|PAYEE|FRAUDE|Y|OP01|MG2|MRQ8")
check "pix.med.G.overclaim" "20" "$(value "$out" rc=)"
out=$(bank "pix.med.open|$MED_PIX|1000.00|USD|$MED_PAYEE_CUST|PAYEE|FRAUDE|Y|OP01|MG3|MRQ9")
check "pix.med.G.badcur" "20" "$(value "$out" rc=)"
out=$(bank "pix.med.open|$MED_PIX|1000.00|BRL|$MED_PAYEE_CUST|PAYEE||Y|OP01|MG4|MRQ10")
check "pix.med.G.badreason" "20" "$(value "$out" rc=)"
out=$(bank "pix.med.open|$MED_PIX|1000.00|BRL|$MED_PAYEE_CUST|PAYEE|FRAUDE|Y|OP01|MG5|MRQ11")
medG=$(value "$out" medcase=)
check "pix.med.G.open.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.med.open|$MED_PIX|1000.00|BRL|$MED_PAYEE_CUST|PAYEE|FRAUDE|Y|OP01|MG6|MRQ12")
check "pix.med.G.dupconflict" "22" "$(value "$out" rc=)"
out=$(bank "pix.med.execute|$medG||OP01|MG7")
check "pix.med.G.exec.tooearly" "20" "$(value "$out" rc=)"
out=$(bank "pix.med.validate|$medG|OP01|MG8")
check "pix.med.G.validate.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.med.decide|$medG|APPROVE||fund|OP01|MG9")
check "pix.med.G.decide.preblock" "20" "$(value "$out" rc=)"
out=$(bank "pix.med.validate|$medG|OP01|MGA")
check "pix.med.G.validate.revalidate" "20" "$(value "$out" rc=)"
out=$(bank "pix.med.close|$medG|OP01|MGB")
check "pix.med.G.close.approved" "20" "$(value "$out" rc=)"

# --- scenario H: request-id idempotent replay returns same case ---
out=$(bank "pix.med.open|$MED_PIX|1000.00|BRL|$MED_PAYEE_CUST|PAYEE|FRAUDE|Y|OP01|MHC|MRQ11")
check "pix.med.H.replay.case" "$medG" "$(value "$out" medcase=)"
check "pix.med.H.replay.flag" "Y" "$(value "$out" replay=)"

# --- scenario I: expiry releases hold; window guard ---
med_case
out=$(bank "pix.med.open|$MED_PIX|1000.00|BRL|$MED_PAYEE_CUST|PAYEE|FRAUDE|Y|OP01|MI1|MRQ13")
medI=$(value "$out" medcase=)
check "pix.med.I.deadline" "20261013" "$(value "$out" deadline=)"
bank "pix.med.validate|$medI|OP01|MI2" >/dev/null
bank "pix.med.block|$medI|OP01|MI3" >/dev/null
out=$(bank "pix.med.expire|$medI|OP01|MI4")
check "pix.med.I.notexpired.rc" "00" "$(value "$out" rc=)"
check "pix.med.I.notexpired.status" "BLOCKED" "$(value "$out" status=)"
sed -i 's/business-date=.*/business-date=2026-10-14/' etc/bank.cfg
out=$(bank "pix.med.expire|$medI|OP01|MI5")
check "pix.med.I.expired" "EXPIRED" "$(value "$out" status=)"
out=$(bank "ledger.balance|$MED_PAYEE")
check "pix.med.I.expired.blocked" "0.00" "$(value "$out" blocked=)"
check "pix.med.I.expired.avail" "501000.00" "$(value "$out" available=)"
sed -i 's/business-date=.*/business-date=2026-10-02/' etc/bank.cfg
out=$(bank "ledger.trial")
check "pix.med.I.trial" "BALANCED" "$(value "$out" msg=)"

# --- scenario J: list / get / recon / restart safety (data is on-disk) ---
out=$(bank "pix.med.get|$medA")
check "pix.med.J.get.closed" "CLOSED" "$(value "$out" status=)"
out=$(bank "pix.med.recon|$medF|MATCHED|OP01")
check "pix.med.J.recon.rc" "00" "$(value "$out" rc=)"
check "pix.med.J.recon.status" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.med.list||$MED_PIX|")
check "pix.med.J.list.count" "0000001" "$(value "$out" count=)"
out=$(bank "pix.med.list|CLOSED||")
check "pix.med.J.list.closed" "0000002" "$(value "$out" count=)"
out=$(bank "pix.med.get|$medA")
check "pix.med.J.restart.persist" "CLOSED" "$(value "$out" status=)"
out=$(bank "ledger.trial")
check "pix.med.J.final.trial" "BALANCED" "$(value "$out" msg=)"

# --- scenario K: batch dry run is read-only (zero writes, no run record) ---
med_case
out=$(bank "pix.med.open|$MED_PIX|1000.00|BRL|$MED_PAYEE_CUST|PAYEE|FRAUDE|Y|OP01|MK1|MRQ20")
medK1=$(value "$out" medcase=)
bank "pix.med.validate|$medK1|OP01|MK2" >/dev/null
bank "pix.med.block|$medK1|OP01|MK3" >/dev/null
med_case
out=$(bank "pix.med.open|$MED_PIX|1000.00|BRL|$MED_PAYEE_CUST|PAYEE|FRAUDE|Y|OP01|MK4|MRQ21")
medK2=$(value "$out" medcase=)
bank "pix.med.validate|$medK2|OP01|MK5" >/dev/null
bank "pix.med.block|$medK2|OP01|MK6" >/dev/null
out=$(bank "pix.med.batch.dry|")
check "pix.med.K.dry.rc" "00" "$(value "$out" rc=)"
check "pix.med.K.dry.status" "DRY" "$(value "$out" status=)"
check "pix.med.K.dry.noexception" "0000000" "$(value "$out" inconsistent=)"
dryScanned=$(value "$out" scanned=)
out=$(bank "pix.med.batch.get|MED-BATCH-20261002")
check "pix.med.K.dry.nowriterec" "23" "$(value "$out" rc=)"
out=$(bank "pix.med.get|$medK1")
check "pix.med.K.dry.untouched" "BLOCKED" "$(value "$out" status=)"
out=$(bank "ledger.trial")
check "pix.med.K.dry.trial" "BALANCED" "$(value "$out" msg=)"

# --- scenario L: overdue expiry via batch, hold released exactly once ---
sed -i 's/business-date=.*/business-date=2026-10-14/' etc/bank.cfg
out=$(bank "pix.med.batch.dry|")
check "pix.med.L.dry.expireelig" "Y" "$(test "$(value "$out" expireelig=)" -ge 3 && echo Y || echo N)"
out=$(bank "pix.med.batch.run|MEDB-L|||OP01|MLC1")
check "pix.med.L.run.rc" "00" "$(value "$out" rc=)"
check "pix.med.L.run.completed" "COMPLETED" "$(value "$out" status=)"
check "pix.med.L.run.scanned" "$dryScanned" "$(value "$out" scanned=)"
check "pix.med.L.run.nofailed" "0000000" "$(value "$out" failed=)"
check "pix.med.L.run.noretryreq" "0000000" "$(value "$out" retryreq=)"
medLexpired=$(value "$out" expired=)
medLprocessed=$(value "$out" processed=)
for c in "$medK1" "$medK2" "$medG"; do
    out=$(bank "pix.med.get|$c")
    check "pix.med.L.expired.$c" "EXPIRED" "$(value "$out" status=)"
    check "pix.med.L.holdgone.$c" "" "$(value "$out" hold=)"
done
out=$(bank "pix.med.get|$medK1")
check "pix.med.L.deadlinekept" "20261013" "$(value "$out" deadline=)"
out=$(bank "ledger.trial")
check "pix.med.L.trial" "BALANCED" "$(value "$out" msg=)"

# --- scenario M: replay and checkpoint restart after interruption ---
out=$(bank "pix.med.batch.run|MEDB-L|||OP01|MLC2")
check "pix.med.M.replay.flag" "Y" "$(value "$out" replay=)"
check "pix.med.M.replay.rc" "00" "$(value "$out" rc=)"
check "pix.med.M.replay.counts" "$medLexpired" "$(value "$out" expired=)"
check "pix.med.M.replay.nostatechg" "$medLprocessed" "$(value "$out" processed=)"
out=$(bank "pix.med.batch.get|MEDB-L")
check "pix.med.M.get.rc" "00" "$(value "$out" rc=)"
check "pix.med.M.get.status" "COMPLETED" "$(value "$out" status=)"
med_case
out=$(bank "pix.med.open|$MED_PIX|1000.00|BRL|$MED_PAYEE_CUST|PAYEE|FRAUDE|Y|OP01|MM1|MRQ22")
medM1=$(value "$out" medcase=)
bank "pix.med.validate|$medM1|OP01|MM2" >/dev/null
bank "pix.med.block|$medM1|OP01|MM3" >/dev/null
med_case
out=$(bank "pix.med.open|$MED_PIX|1000.00|BRL|$MED_PAYEE_CUST|PAYEE|FRAUDE|Y|OP01|MM5|MRQ21B")
medM2=$(value "$out" medcase=)
bank "pix.med.validate|$medM2|OP01|MM6" >/dev/null
bank "pix.med.block|$medM2|OP01|MM7" >/dev/null
sed -i 's/business-date=.*/business-date=2026-10-26/' etc/bank.cfg
out=$(bank "pix.med.batch.run|MEDB-M||1|OP01|MMC1")
check "pix.med.M.fault.rc" "24" "$(value "$out" rc=)"
check "pix.med.M.fault.running" "RUNNING" "$(value "$out" status=)"
check "pix.med.M.fault.processed" "0000001" "$(value "$out" processed=)"
out=$(bank "pix.med.batch.get|MEDB-M")
check "pix.med.M.ckpt.running" "RUNNING" "$(value "$out" status=)"
ckptLast=$(value "$out" lastcase=)
out=$(bank "pix.med.get|$medM1")
check "pix.med.M.ckpt.done" "EXPIRED" "$(value "$out" status=)"
out=$(bank "pix.med.get|$medM2")
check "pix.med.M.ckpt.pending" "BLOCKED" "$(value "$out" status=)"
out=$(bank "pix.med.batch.run|MEDB-M|||OP01|MMC2")
check "pix.med.M.resume.rc" "00" "$(value "$out" rc=)"
check "pix.med.M.resume.completed" "COMPLETED" "$(value "$out" status=)"
check "pix.med.M.resume.processed" "0000001" "$(value "$out" processed=)"
check "pix.med.M.resume.lastcasegt" "Y" "$(test "$(value "$out" lastcase=)" > "$ckptLast" && echo Y || echo N)"
out=$(bank "pix.med.get|$medM2")
check "pix.med.M.resumed.expired" "EXPIRED" "$(value "$out" status=)"
out=$(bank "pix.med.batch.run|MEDB-M|||OP01|MMC3")
check "pix.med.M.double.replay" "Y" "$(value "$out" replay=)"
out=$(bank "ledger.trial")
check "pix.med.M.trial" "BALANCED" "$(value "$out" msg=)"

# --- scenario N: claimant scope + batch run lock mutual exclusion ---
med_case
out=$(bank "pix.med.open|$MED_PIX|1000.00|BRL|$MED_PAYEE_CUST|PAYEE|FRAUDE|Y|OP01|MP1|MRQ25")
medP1=$(value "$out" medcase=); medP1claim=$(value "$out" claimant=)
bank "pix.med.validate|$medP1|OP01|MP2" >/dev/null
bank "pix.med.block|$medP1|OP01|MP3" >/dev/null
med_case
out=$(bank "pix.med.open|$MED_PIX|1000.00|BRL|$MED_PAYEE_CUST|PAYEE|FRAUDE|Y|OP01|MP4|MRQ26")
medP2=$(value "$out" medcase=)
bank "pix.med.validate|$medP2|OP01|MP5" >/dev/null
bank "pix.med.block|$medP2|OP01|MP6" >/dev/null
sed -i 's/business-date=.*/business-date=2026-11-07/' etc/bank.cfg
out=$(bank "pix.med.lock|A|MEDB-MEDB-PLOCK|OTHEROP")
check "pix.med.N.acquire" "00" "$(value "$out" rc=)"
out=$(bank "pix.med.batch.run|MEDB-PLOCK|||OP01|MPC1")
check "pix.med.N.contend.rc" "24" "$(value "$out" rc=)"
check "pix.med.N.contend.msg" "Y" "$(printf '%s' "$out" | grep -q "ALREADY RUNNING" && echo Y || echo N)"
out=$(bank "pix.med.get|$medP1")
check "pix.med.N.contend.untouched" "BLOCKED" "$(value "$out" status=)"
out=$(bank "pix.med.lock|R|MEDB-MEDB-PLOCK|OTHEROP")
check "pix.med.N.release" "00" "$(value "$out" rc=)"
out=$(bank "pix.med.batch.run|MEDB-P|$medP1claim||OP01|MPC2")
check "pix.med.N.scope.rc" "00" "$(value "$out" rc=)"
check "pix.med.N.scope.scanned" "0000001" "$(value "$out" scanned=)"
check "pix.med.N.scope.expired" "0000001" "$(value "$out" expired=)"
out=$(bank "pix.med.get|$medP1")
check "pix.med.N.scope.done" "EXPIRED" "$(value "$out" status=)"
out=$(bank "pix.med.get|$medP2")
check "pix.med.N.scope.other" "BLOCKED" "$(value "$out" status=)"

# --- scenario O: batch recovers unknown devolutions, never double-pays ---
med_case
out=$(bank "pix.med.open|$MED_PIX|1000.00|BRL|$MED_PAYEE_CUST|PAYEE|FRAUDE|Y|OP01|MN1|MRQ23")
medN=$(value "$out" medcase=)
bank "pix.med.validate|$medN|OP01|MN2" >/dev/null
bank "pix.med.block|$medN|OP01|MN3" >/dev/null
bank "pix.med.decide|$medN|APPROVE||fund|OP01|MN4" >/dev/null
out=$(bank "pix.med.execute|$medN|TIMEOUT|OP01|MN5")
medNdevol=$(value "$out" devol=)
check "pix.med.O.timeout" "DEVOLV-UNK" "$(value "$out" status=)"
out=$(bank "pix.med.batch.run|MEDB-N|||OP01|MNC1|TIMEOUT")
check "pix.med.O.stuck.rc" "00" "$(value "$out" rc=)"
check "pix.med.O.stuck.retryreq" "0000001" "$(value "$out" retryreq=)"
check "pix.med.O.stuck.exceptions" "0000001" "$(value "$out" exceptions=)"
check "pix.med.O.stuck.completed" "COMPLETED" "$(value "$out" status=)"
out=$(bank "reconciliation.exceptions|MEDB-N")
check "pix.med.O.exc.count" "000000001" "$(value "$out" exceptions=)"
check "pix.med.O.exc.code" "1" "$(printf '%s' "$out" | grep -c 'code=MEDRETRY')"
out=$(bank "pix.med.batch.run|MEDB-N2|||OP01|MNC2")
check "pix.med.O.rec.retried" "0000001" "$(value "$out" retried=)"
check "pix.med.O.rec.exceptions" "0000000" "$(value "$out" exceptions=)"
out=$(bank "pix.med.get|$medN")
check "pix.med.O.rec.status" "DEVOLVED" "$(value "$out" status=)"
check "pix.med.O.rec.returned" "1000.00" "$(value "$out" returned=)"
check "pix.med.O.rec.sameid" "$medNdevol" "$(value "$out" devol=)"
out=$(bank "pix.get|$MED_PIX")
check "pix.med.O.orig.full" "FULL" "$(value "$out" dev=)"
out=$(bank "ledger.balance|$MED_PAYEE")
check "pix.med.O.payee.once" "500000.00" "$(value "$out" ledger=)"
out=$(bank "ledger.trial")
check "pix.med.O.trial" "BALANCED" "$(value "$out" msg=)"

# --- scenario P: reconciliation refresh + manual verdict guard ---
med_case
out=$(bank "pix.med.open|$MED_PIX|1000.00|BRL|$MED_PAYEE_CUST|PAYEE|FRAUDE|Y|OP01|MO1|MRQ24")
medO=$(value "$out" medcase=)
bank "pix.med.validate|$medO|OP01|MO2" >/dev/null
bank "pix.med.block|$medO|OP01|MO3" >/dev/null
bank "pix.med.decide|$medO|APPROVE||fund|OP01|MO4" >/dev/null
out=$(bank "pix.med.execute|$medO||OP01|MO5")
medOdevol=$(value "$out" devol=)
check "pix.med.P.exec" "DEVOLVED" "$(value "$out" status=)"
out=$(bank "pix.med.batch.dry|")
reconBefore=$(value "$out" reconelig=)
out=$(bank "pix.med.batch.run|MEDB-O|||OP01|MOC1")
check "pix.med.P.run.rc" "00" "$(value "$out" rc=)"
refreshed=$(value "$out" refreshed=)
check "pix.med.P.refreshed.ge1" "Y" "$(test "$refreshed" -ge 1 && echo Y || echo N)"
out=$(bank "pix.med.get|$medO")
medOrecon=$(value "$out" recon=)
check "pix.med.P.recon.set" "Y" "$(test -n "$medOrecon" && echo Y || echo N)"
out=$(bank "pix.get|$medOdevol")
devolState=$(value "$out" status=)
wantRecon="POSTED"
if [ "$devolState" = "RECONCILED" ]; then wantRecon="RECONCILED"; fi
if [ "$devolState" = "SETTLED" ]; then wantRecon="SETTLED"; fi
check "pix.med.P.recon.value" "$wantRecon" "$medOrecon"
out=$(bank "pix.med.batch.dry|")
reconAfter=$(value "$out" reconelig=)
check "pix.med.P.recon.dropped" "Y" "$(test "$reconBefore" -gt "$reconAfter" && echo Y || echo N)"
out=$(bank "pix.med.recon|$medO|MATCHED|OP01")
check "pix.med.P.manual" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.med.batch.dry|")
check "pix.med.P.guard" "Y" "$(test "$(value "$out" reconelig=)" = "$reconAfter" && echo Y || echo N)"

# --- scenario Q: full EOD integration (auto run id per business date) ---
out=$(bank "batch.eod|OP01|MQ1|EODMED")
check "pix.med.Q.eod.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.med.batch.get|MED-BATCH-20261107")
check "pix.med.Q.eod.autoid" "00" "$(value "$out" rc=)"
check "pix.med.Q.eod.completed" "COMPLETED" "$(value "$out" status=)"
check "pix.med.Q.eod.report" "Y" "$(grep -rq 'MEDBATCH-EOD' var/out/ 2>/dev/null && echo Y || echo N)"
out=$(bank "pix.med.get|$medP2")
check "pix.med.Q.eod.p2expired" "EXPIRED" "$(value "$out" status=)"
sed -i 's/business-date=.*/business-date=2026-11-08/' etc/bank.cfg
out=$(bank "batch.eod|OP01|MQ2|EODMED2")
check "pix.med.Q.eod2.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.med.batch.get|MED-BATCH-20261108")
check "pix.med.Q.eod2.autoid" "00" "$(value "$out" rc=)"
check "pix.med.Q.eod2.replay" "Y" "$(printf '%s' "$(bank 'pix.med.batch.run|MED-BATCH-20261107|||OP01|MQ3')" | grep -q 'replay=Y' && echo Y || echo N)"
out=$(bank "pix.med.get|$medP2")
check "pix.med.Q.eod2.p2expired" "EXPIRED" "$(value "$out" status=)"
out=$(bank "pix.med.batch.get|MED-BATCH-20261107")
check "pix.med.Q.eod.noclobber" "COMPLETED" "$(value "$out" status=)"
out=$(bank "ledger.trial")
check "pix.med.Q.eod.trial" "BALANCED" "$(value "$out" msg=)"

# --- pix-claim: portability + possession + DICT sync regressions ---
sed -i 's/business-date=.*/business-date=2026-10-02/' etc/bank.cfg
pix_self="P00000000001"
pix_other="P00000000002"
pixc=$(value "$(bank "customer.create|P|CLM OWNER|CPF|22233344405|19900101|OP01|CC1")" id=)
pixa=$(value "$(bank "account.open|$pixc|DMND|BRL|500000|OP01|CC2|OC1")" id=)
pixb=$(value "$(bank "account.open|$pixc|DMND|BRL|500000|OP01|CC3|OC2")" id=)
pixd=$(value "$(bank "customer.create|P|CLM OUTSIDER|CPF|33344455566|19900101|OP01|CC4")" id=)
pixe=$(value "$(bank "account.open|$pixd|DMND|BRL|500000|OP01|CC5|OC3")" id=)
pk_e=$(value "$(bank "pix.key.register|EMAIL|claim.me@KofBank.com|$pixa|$pixc|OP01|CR|CK1")" id=)
pk_p=$(value "$(bank "pix.key.register|PHONE|+5511999990001|$pixa|$pixc|OP01|CR|CK2")" id=)
pk_t=$(value "$(bank "pix.key.register|CPF|222.333.444-05|$pixa|$pixc|OP01|CR|CK3")" id=)
pk_f=$(value "$(bank "pix.key.seed|PHONE|+5511999990009|$pix_other|ZZ99999999|ZZ88888888|FOREIGN OWNER|OP01")" keyid=)
pk_f2=$(value "$(bank "pix.key.seed|PHONE|+5511999990010|$pix_other|ZZ99999998|ZZ88888887|FOREIGN OWNER2|OP01")" keyid=)
pk_bad=$(value "$(bank "pix.key.seed|RANDOM|123e4567e89b12d3a456426614174000|$pix_other|ZZ99999997|ZZ88888886|EVPFOREIGN|OP01")" keyid=)
pk_f3=$(value "$(bank "pix.key.seed|PHONE|+5511999990003|$pix_other|ZZ99999996|ZZ88888885|FOREIGN OWNER3|OP01")" keyid=)

# A: portability happy path (EMAIL, same customer, other account)
out=$(bank "pix.key.claim.create|$pk_e|PORTABILITY|$pixb|$pixc||CLMP-E1|OP01|CP1")
check "pix.claim.A.create.rc" "00" "$(value "$out" rc=)"
check "pix.claim.A.create.status" "OPEN" "$(value "$out" claim=)"
check "pix.claim.A.resol" "20261004" "$(value "$out" resolend=)"
check "pix.claim.A.compl" "20261005" "$(value "$out" complend=)"
pc1=$(value "$out" claimid=)
out=$(bank "pix.key.get|$pk_e")
check "pix.claim.A.localmirror" "OPEN" "$(value "$out" claim=)"
out=$(bank "pix.key.claim.ack|$pk_e|$pc1||OP01")
check "pix.claim.A.ack.rc" "00" "$(value "$out" rc=)"
check "pix.claim.A.ack.status" "WAITING_RESOLUTION" "$(value "$out" claim=)"
out=$(bank "pix.key.claim.ack|$pk_e|$pc1||OP01")
check "pix.claim.A.ack.idem" "WAITING_RESOLUTION" "$(value "$out" claim=)"
out=$(bank "pix.key.claim.confirm|$pk_e|$pc1|ACCOUNT_CLOSURE|$pix_other|OP01")
check "pix.claim.A.cfm.badactor" "20" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.confirm|$pk_e|$pc1|USER_REQUESTED|$pixd|OP01")
check "pix.claim.A.cfm.badactor2" "20" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.confirm|$pk_e|$pc1|USER_REQUESTED||OP01")
check "pix.claim.A.cfm.rc" "00" "$(value "$out" rc=)"
check "pix.claim.A.cfm.status" "CONFIRMED" "$(value "$out" claim=)"
check "pix.claim.A.cfm.acct" "$pixb" "$(value "$out" acct=)"
out=$(bank "pix.key.claim.complete|$pk_e|$pc1||OP01")
check "pix.claim.A.cmp.rc" "00" "$(value "$out" rc=)"
check "pix.claim.A.cmp.status" "COMPLETED" "$(value "$out" claim=)"
out=$(bank "pix.key.claim.complete|$pk_e|$pc1||OP01")
check "pix.claim.A.cmp.idem" "COMPLETED" "$(value "$out" claim=)"
out=$(bank "pix.key.lookup|EMAIL|claim.me@kofbank.com")
check "pix.claim.A.owner.acct" "$pixb" "$(value "$out" acct=)"
check "pix.claim.A.owner.cust" "$pixc" "$(value "$out" cust=)"
check "pix.claim.A.owner.noclaim" "" "$(value "$out" claim=)"
out=$(bank "pix.key.lookup|EMAIL|claim.me@KofBank.com")
check "pix.claim.A.owner.self" "Y" "$(value "$out" self=)"

# B: possession cross-PSP to completion (PHONE foreign -> self)
out=$(bank "pix.key.claim.create|$pk_f|OWNERSHIP|$pixa|$pixc||CLMP-P1|OP01|CP2")
check "pix.claim.B.create.rc" "00" "$(value "$out" rc=)"
pos1=$(value "$out" claimid=)
out=$(bank "pix.key.claim.ack|$pk_f|$pos1|$pix_other|OP01")
check "pix.claim.B.ack.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.confirm|$pk_f|$pos1|DEFAULT_OPERATION|$pix_other|OP01")
check "pix.claim.B.cfm.early" "20" "$(value "$out" rc=)"
sed -i 's/business-date=.*/business-date=2026-10-05/' etc/bank.cfg
out=$(bank "pix.key.claim.confirm|$pk_f|$pos1|DEFAULT_OPERATION|$pix_other|OP01")
check "pix.claim.B.cfm.default" "00" "$(value "$out" rc=)"
check "pix.claim.B.cfm.status" "CONFIRMED" "$(value "$out" claim=)"
out=$(bank "pix.key.claim.complete|$pk_f|$pos1||OP01")
check "pix.claim.B.cmp.blocked" "20" "$(value "$out" rc=)"
sed -i 's/business-date=.*/business-date=2026-10-06/' etc/bank.cfg
out=$(bank "pix.key.claim.complete|$pk_f|$pos1||OP01")
check "pix.claim.B.cmp.rc" "00" "$(value "$out" rc=)"
check "pix.claim.B.cmp.status" "COMPLETED" "$(value "$out" claim=)"
sed -i 's/business-date=.*/business-date=2026-10-02/' etc/bank.cfg
out=$(bank "pix.key.lookup|PHONE|+5511999990009")
check "pix.claim.B.new.part" "$pix_self" "$(value "$out" part=)"
check "pix.claim.B.new.acct" "$pixa" "$(value "$out" acct=)"
check "pix.claim.B.new.cust" "$pixc" "$(value "$out" cust=)"
check "pix.claim.B.new.self" "Y" "$(value "$out" self=)"

# C: possession cancel matrix + donor restore
out=$(bank "pix.key.claim.create|$pk_f2|OWNERSHIP|$pixa|$pixc||CLMP-P2|OP01|CP3")
pos2=$(value "$out" claimid=)
out=$(bank "pix.key.claim.confirm|$pk_f2|$pos2|USER_REQUESTED|$pix_other|OP01")
check "pix.claim.C.cfm.before.ack" "20" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.ack|$pk_f2|$pos2|$pix_other|OP01")
check "pix.claim.C.ack" "00" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.cancel|$pk_f2|$pos2|USER_REQUESTED|$pix_other|OP01")
check "pix.claim.C.cancel.donor.user" "20" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.cancel|$pk_f2|$pos2|FRAUD|$pix_other|OP01")
check "pix.claim.C.cancel.donor.fraud" "00" "$(value "$out" rc=)"
check "pix.claim.C.cancelledby" "DONOR" "$(value "$out" cancelledby=)"
out=$(bank "pix.key.claim.create|$pk_f2|OWNERSHIP|$pixa|$pixc||CLMP-P3|OP01|CP4")
pos3=$(value "$out" claimid=)
out=$(bank "pix.key.claim.cancel|$pk_f2|$pos3|USER_REQUESTED||OP01")
check "pix.claim.C.cancel.claimer" "00" "$(value "$out" rc=)"
check "pix.claim.C.cancel.claimer.status" "CANCELLED" "$(value "$out" claim=)"
check "pix.claim.C.cancel.claimer.by" "CLAIMER" "$(value "$out" cancelledby=)"
out=$(bank "pix.key.claim.create|$pk_f2|OWNERSHIP|$pixa|$pixc||CLMP-P4|OP01|CP5")
pos4=$(value "$out" claimid=)
out=$(bank "pix.key.claim.ack|$pk_f2|$pos4|$pix_other|OP01")
check "pix.claim.C.ack4" "00" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.confirm|$pk_f2|$pos4|USER_REQUESTED|$pix_other|OP01")
check "pix.claim.C.confirm4" "00" "$(value "$out" rc=)"
check "pix.claim.C.confirm4.compl0" "00000000" "$(value "$out" complend=)"
out=$(bank "pix.key.claim.cancel|$pk_f2|$pos4|FRAUD|$pix_other|OP01")
check "pix.claim.C.cancel.confirmed" "00" "$(value "$out" rc=)"
out=$(bank "pix.key.lookup|PHONE|+5511999990010")
check "pix.claim.C.revert.part" "$pix_other" "$(value "$out" part=)"
check "pix.claim.C.revert.acct" "ZZ99999998" "$(value "$out" acct=)"

# D: create validation matrix
out=$(bank "pix.key.claim.create|$pk_t|OWNERSHIP|$pixe|$pixd||CLMP-D1|OP01|CD1")
check "pix.claim.D.phone.ownership.cust" "20" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.create|$pk_e|PORTABILITY|$pixe|$pixd||CLMP-D2|OP01|CD2")
check "pix.claim.D.port.cust.mismatch" "20" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.create|$pk_bad|PORTABILITY|$pixb|$pixc||CLMP-D3|OP01|CD3")
check "pix.claim.D.port.random" "20" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.create|$pk_e|PORTABILITY|$pixb|$pixc||CLMP-D4|OP01|CD4")
check "pix.claim.D.port.same.acct" "22" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.create|$pk_t|PORTABILITY|$pixb|$pixc||CLMP-D5|OP01|CD5")
check "pix.claim.D.cpf.port.ok" "00" "$(value "$out" rc=)"
dk1=$(value "$out" claimid=)
out=$(bank "pix.key.claim.cancel|$pk_t|$dk1|RECONCILIATION||OP01")
check "pix.claim.D.cancel.recon.open" "00" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.create|$pk_e|OWNERSHIP|$pixe|$pixd||CLMP-D6|OP01|CD6")
check "pix.claim.D.email.ownership" "20" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.cancel|$pk_t|$dk1|USER_REQUESTED||OP01")
check "pix.claim.D.cancel.twice" "00" "$(value "$out" rc=)"
check "pix.claim.D.cancel.twice.idem" "CANCELLED" "$(value "$out" claim=)"

# E: idempotent create + conflicting body same request-id
out=$(bank "pix.key.claim.create|$pk_f3|OWNERSHIP|$pixa|$pixc||CLMP-EX1|OP01|CE1")
pe1=$(value "$out" claimid=)
out=$(bank "pix.key.claim.create|$pk_f3|OWNERSHIP|$pixa|$pixc||CLMP-EX1|OP01|CE1R")
check "pix.claim.E.replay.rc" "00" "$(value "$out" rc=)"
check "pix.claim.E.replay.flag" "Y" "$(value "$out" replay=)"
check "pix.claim.E.replay.id" "$pe1" "$(value "$out" claimid=)"
out=$(bank "pix.key.claim.create|$pk_f3|OWNERSHIP|$pixb|$pixc||CLMP-EX1|OP01|CE2")
check "pix.claim.E.conflict" "20" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.create|$pk_f3|OWNERSHIP|$pixb|$pixc||CLMP-E3|OP01|CE3")
check "pix.claim.E.locked" "20" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.cancel|$pk_f3|$pe1|USER_REQUESTED||OP01")
check "pix.claim.E.cancel.claimer" "00" "$(value "$out" rc=)"

# F: key locked by claim + concurrency lock + portability cancel rules
out=$(bank "pix.key.claim.create|$pk_t|PORTABILITY|$pixb|$pixc||CLMP-F1|OP01|CF1")
pf1=$(value "$out" claimid=)
out=$(bank "pix.key.change|$pk_t|$pixe|OP01|CF2|CFC")
check "pix.claim.F.change.locked" "20" "$(value "$out" rc=)"
out=$(bank "pix.key.delete|$pk_t|OP01|CF3|CFD")
check "pix.claim.F.delete.locked" "20" "$(value "$out" rc=)"
out=$(bank "pix.med.lock|A|DICTK-$pk_t|INTRUDER")
check "pix.claim.F.grablock" "00" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.ack|$pk_t|$pf1||OP01")
check "pix.claim.F.busy" "24" "$(value "$out" rc=)"
out=$(bank "pix.med.lock|R|DICTK-$pk_t|INTRUDER")
check "pix.claim.F.relock" "00" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.ack|$pk_t|$pf1||OP01")
check "pix.claim.F.ack.after" "00" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.cancel|$pk_t|$pf1|RECONCILIATION||OP01")
check "pix.claim.F.recon.waiting" "20" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.cancel|$pk_t|$pf1|ACCOUNT_CLOSURE||OP01")
check "pix.claim.F.cancel.closer" "00" "$(value "$out" rc=)"
check "pix.claim.F.cancel.closer.status" "CANCELLED" "$(value "$out" claim=)"
out=$(bank "pix.key.delete|$pk_t|OP01|CF4|CFE")
check "pix.claim.F.delete.after" "00" "$(value "$out" rc=)"

# G: sync: other-participant notice, consistent, stale-base version guard
out=$(bank "pix.key.sync|$pk_bad")
check "pix.claim.G.sync.held.other" "yes" "$(grep -qa 'HELD BY OTHER' <<<"$out" && echo yes || echo no)"
out=$(bank "pix.key.sync|$pk_e")
check "pix.claim.G.sync.consistent" "00" "$(value "$out" rc=)"
check "pix.claim.G.sync.claim.blank" "" "$(value "$out" claim=)"
out=$(bank "pix.key.sync|$pk_f2|1")
check "pix.claim.G.ver.stale" "22" "$(value "$out" rc=)"
out=$(bank "pix.key.sync|$pk_f|0")
check "pix.claim.G.ver.now" "00" "$(value "$out" rc=)"

# H: lazy expiry at completion-period end
out=$(bank "pix.key.claim.create|$pk_f2|OWNERSHIP|$pixa|$pixc||CLMP-H1|OP01|CH1")
ph=$(value "$out" claimid=)
check "pix.claim.H.create" "00" "$(value "$out" rc=)"
sed -i 's/business-date=.*/business-date=2026-10-07/' etc/bank.cfg
out=$(bank "pix.key.claim.ack|$pk_f2|$ph|$pix_other|OP01")
check "pix.claim.H.expiry.ack" "20" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.get|$ph")
check "pix.claim.H.expiry.status" "CANCELLED" "$(value "$out" claim=)"
check "pix.claim.H.expiry.by" "EXPIRED" "$(value "$out" cancelledby=)"
out=$(bank "pix.key.claim.get|$ph")
check "pix.claim.H.expiry.reason" "DEFAULT_OPERATION" "$(value "$out" cancelr=)"
out=$(bank "pix.key.lookup|PHONE|+5511999990010")
check "pix.claim.H.expiry.entryclear" "" "$(value "$out" claim=)"
check "pix.claim.H.expiry.donor" "$pix_other" "$(value "$out" part=)"
out=$(bank "pix.key.claim.list|OPEN")
check "pix.claim.H.list.open.zero" "0000" "$(value "$out" count=)"
out=$(bank "pix.key.sync|$pk_f2")
check "pix.claim.H.sync.after.expiry" "00" "$(value "$out" rc=)"
sed -i 's/business-date=.*/business-date=2026-10-02/' etc/bank.cfg

# I: stale claim pointer self-heal (ghost DICT entry)
gk=$(value "$(bank "pix.key.seed|PHONE|+5599999999999|$pix_other|ZZ00000001|ZZ00000002|GHOST OWNER|OP01")" keyid=)
python3 - <<'GEP'
data=open('var/data/pxdict.idx','rb').read()
pos=data.find(b'ZZ00000001')
rs=pos-106
buf=bytearray(data)
buf[rs+202:rs+220]=b'OPEN              '
buf[rs+220:rs+244]=b'CGHOST0001'.ljust(24)
open('var/data/pxdict.idx','wb').write(bytes(buf))
GEP
out=$(bank "pix.key.lookup|PHONE|+5599999999999")
check "pix.claim.I.ghost.lookup.rc" "00" "$(value "$out" rc=)"
check "pix.claim.I.ghost.healed" "" "$(value "$out" claim=)"
out=$(bank "pix.key.delete|$gk|OP01|CI1|CID")
check "pix.claim.I.ghost.delete" "00" "$(value "$out" rc=)"
out=$(bank "pix.key.claim.list|OPEN")
check "pix.claim.I.list.open.zero" "0000" "$(value "$out" count=)"
out=$(bank "pix.key.sync|$gk")
check "pix.claim.I.sync.released" "23" "$(value "$out" rc=)"
# J: audit + events
check "pix.claim.J.audit.create" "yes" "$(grep -aq 'KEY-CLM-CRT' var/audit/audit.log && echo yes || echo no)"
check "pix.claim.J.audit.confirm" "yes" "$(grep -aq 'KEY-CLM-CFM' var/audit/audit.log && echo yes || echo no)"
check "pix.claim.J.event.claim" "yes" "$(grep -aq 'PIX.KEY.CLAIM.v1' var/journal/events.log && echo yes || echo no)"
check "pix.claim.J.event.portability" "yes" "$(grep -aq 'PIX.KEY.PORTABILITY.v1' var/journal/events.log && echo yes || echo no)"
check "pix.claim.J.event.sync" "yes" "$(grep -aq 'PIX.KEY.DICT-SYNC.v1' var/journal/events.log && echo yes || echo no)"
check "pix.claim.J.no.keyleak" "no" "$(grep -aq '22233344405' var/data/pxdict.idx && echo yes || echo no)"


# --- pix-qr-expiry: seconds-level UTC expiration regressions ---
reset
bank "ledger.init" >/dev/null
bank "pix.rt.create|12345678|KOF|DEBITS|DPI|Y||OP01|CORP|QXE1" >/dev/null
out=$(bank "customer.create|P|QR EXPIRY PAYER|CPF|123.456.789-09|19900101|OP01|QXE2")
qxpc1=$(value "$out" id=)
out=$(bank "account.open|$qxpc1|DMND|BRL|500000|OP01|QXE3|A")
qxa1=$(value "$out" id=)
out=$(bank "customer.create|P|QR EXPIRY PAYEE|CPF|234.567.890-92|19900101|OP01|QXE4")
qxpc2=$(value "$out" id=)
out=$(bank "account.open|$qxpc2|DMND|BRL|500000|OP01|QXE5|B")
qxa2=$(value "$out" id=)
out=$(bank "pix.key.register|CPF|23456789092|$qxa2|$qxpc2|OP01|QXE6|K")
qxkey=$(value "$out" id=)

export PIX_CLOCK_NOW=20261006100000
# default expiration when omitted: 86400 seconds from the spec default
out=$(bank "pix.qr.create|DYNAMIC|$qxa2|$qxkey|CPF|23456789092|30.00|PIX MERCHANT|SAO PAULO|0000|OP01|COR|QXD0")
check "qr.expire.default.ttl" "0086400" "$(value "$out" ttlsec=)"
check "qr.expire.default.expiresat" "20261007100000" "$(value "$out" expiresat=)"
qrd=$(value "$out" id=)
out=$(bank "pix.qr.check|$qrd|OP01")
check "qr.expire.default.active.1s-before" "00" "$(value "$out" rc=)"
out=$(PIX_CLOCK_NOW=20261007095959 bank "pix.qr.check|$qrd|OP01")
check "qr.expire.default.active.lastsec" "00" "$(value "$out" rc=)"
out=$(PIX_CLOCK_NOW=20261007100000 bank "pix.qr.check|$qrd|OP01")
check "qr.expire.default.exact-boundary" "20" "$(value "$out" rc=)"
check "qr.expire.default.exact-msg" "yes" "$(grep -aq '^msg=PIX QR EXPIRED' <<<"$out" && echo yes || echo no)"

# explicit expiration in seconds
out=$(bank "pix.qr.create|DYNAMIC|$qxa2|$qxkey|CPF|23456789092|30.00|PIX MERCHANT|SAO PAULO|0000|OP01|COR|QXD1|3600")
qra=$(value "$out" id=)
check "qr.expire.explicit.ttl" "0003600" "$(value "$out" ttlsec=)"
check "qr.expire.explicit.expiresat" "20261006110000" "$(value "$out" expiresat=)"
out=$(PIX_CLOCK_NOW=20261006105959 bank "pix.qr.check|$qra|OP01")
check "qr.expire.boundary.before" "00" "$(value "$out" rc=)"
check "qr.expire.boundary.before.status" "PUBLISHED" "$(value "$out" status=)"
out=$(PIX_CLOCK_NOW=20261006110000 bank "pix.qr.check|$qra|OP01")
check "qr.expire.boundary.exact" "20" "$(value "$out" rc=)"
out=$(PIX_CLOCK_NOW=20261006110001 bank "pix.qr.check|$qra|OP01")
check "qr.expire.boundary.after" "20" "$(value "$out" rc=)"

# checking expiration is pure and deterministic (no mutation, replay-safe)
c1=$(PIX_CLOCK_NOW=20261006110000 bank "pix.qr.check|$qra|OP01")
c2=$(PIX_CLOCK_NOW=20261006110000 bank "pix.qr.check|$qra|OP01")
check "qr.expire.check.idempotent" "yes" "$([ "$(value "$c1" crc=)" = "$(value "$c2" crc=)" ] && echo yes || echo no)"
check "qr.expire.check.keeps-status" "PUBLISHED" "$(value "$c1" status=)"
out=$(bank "pix.qr.get|$qra")
check "qr.expire.check.no-transition" "PUBLISHED" "$(value "$out" status=)"

# reading (presentation) does not reset the expiration
out=$(PIX_CLOCK_NOW=20261006103000 bank "pix.qr.read|$qra|OP01|COR|QXR1")
check "qr.expire.read.active" "00" "$(value "$out" rc=)"
check "qr.expire.read.count" "00001" "$(value "$out" reads=)"
check "qr.expire.read.no-reset" "20261006110000" "$(value "$out" expiresat=)"
out=$(PIX_CLOCK_NOW=20261006110000 bank "pix.qr.check|$qra|OP01")
check "qr.expire.after.read.expired" "20" "$(value "$out" rc=)"

# payment exactly one second before the boundary succeeds
out=$(bank "pix.out.qr|$qra|30.00|$qxa1||qr pay valid|OP01|COR|QXP0")
check "qr.expire.pay.valid.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.qr.get|$qra")
check "qr.expire.pay.valid.linked" "PAID" "$(value "$out" status=)"

# expired QR produces zero financial effect
out=$(bank "pix.qr.create|DYNAMIC|$qxa2|$qxkey|CPF|23456789092|60.00|PIX MERCHANT|SAO PAULO|0000|OP01|COR|QXD9|60")
qrx=$(value "$out" id=)
bal=$(value "$(bank "account.get|$qxa1")" balance=)
out=$(PIX_CLOCK_NOW=20261006100100 bank "pix.out.qr|$qrx|60.00|$qxa1||qr pay expired|OP01|COR|QXP1")
check "qr.expire.pay.expired.rc" "20" "$(value "$out" rc=)"
check "qr.expire.pay.expired.msg" "yes" "$(grep -aq '^msg=PIX QR EXPIRED' <<<"$out" && echo yes || echo no)"
check "qr.expire.pay.expired.noid" "" "$(value "$out" id=)"
check "qr.expire.pay.expired.balance" "$bal" "$(value "$(bank "account.get|$qxa1")" balance=)"
grep -aq "QXP1" var/journal/journal.log && qj=yes || qj=no
check "qr.expire.pay.expired.no-journal" "no" "$qj"
grep -aq "QXP1" var/data/px.idx && qt=yes || qt=no
check "qr.expire.pay.expired.no-txn" "no" "$qt"

# lazy transition on read, then terminal for the state machine
out=$(bank "pix.qr.create|DYNAMIC|$qxa2|$qxkey|CPF|23456789092|40.00|PIX MERCHANT|SAO PAULO|0000|OP01|COR|QXD2|60")
qrl=$(value "$out" id=)
out=$(PIX_CLOCK_NOW=20261006100200 bank "pix.qr.read|$qrl|OP01|COR|QXR2")
check "qr.expire.lazy.read.rc" "20" "$(value "$out" rc=)"
check "qr.expire.lazy.read.msg" "yes" "$(grep -aq '^msg=PIX QR EXPIRED' <<<"$out" && echo yes || echo no)"
out=$(bank "pix.qr.get|$qrl")
check "qr.expire.lazy.status" "EXPIRED" "$(value "$out" status=)"
out=$(bank "pix.qr.status|$qrl|PAID|OP01|COR|QXS1")
check "qr.expire.lazy.paid-blocked" "20" "$(value "$out" rc=)"
out=$(bank "pix.qr.status|$qrl|CANCELLED|OP01|COR|QXS2")
check "qr.expire.lazy.cancel-blocked" "20" "$(value "$out" rc=)"

# PAID directly after expiry (no prior read) is refused and transitions lazily
out=$(bank "pix.qr.create|DYNAMIC|$qxa2|$qxkey|CPF|23456789092|15.00|PIX MERCHANT|SAO PAULO|0000|OP01|COR|QXD3|30")
qrp=$(value "$out" id=)
out=$(PIX_CLOCK_NOW=20261006100031 bank "pix.qr.status|$qrp|PAID|OP01|COR|QXS3")
check "qr.expire.paid-direct.rc" "20" "$(value "$out" rc=)"
check "qr.expire.paid-direct.msg" "yes" "$(grep -aq '^msg=PIX QR EXPIRED' <<<"$out" && echo yes || echo no)"
out=$(bank "pix.qr.get|$qrp")
check "qr.expire.paid-direct.status" "EXPIRED" "$(value "$out" status=)"

# static QR never expires
out=$(bank "pix.qr.create|STATIC|$qxa2|$qxkey|CPF|23456789092|25.00|PIX MERCHANT|SAO PAULO|0000|OP01|COR|QXS4")
qrs=$(value "$out" id=)
check "qr.expire.static.no-ttl" "0000000" "$(value "$out" ttlsec=)"
out=$(PIX_CLOCK_NOW=20990101000000 bank "pix.qr.check|$qrs|OP01")
check "qr.expire.static.active" "00" "$(value "$out" rc=)"

# expiration is seconds + UTC instant, independent of business-date
# (bank.cfg business-date is 2026-10-02 while the QR clock runs 2026-10-06/07)
out=$(bank "pix.qr.create|DYNAMIC|$qxa2|$qxkey|CPF|23456789092|30.00|PIX MERCHANT|SAO PAULO|0000|OP01|COR|QXDA|3600")
qrb=$(value "$out" id=)
out=$(PIX_CLOCK_NOW=20261006105959 bank "pix.qr.check|$qrb|OP01")
check "qr.expire.bizdate.independent.active" "00" "$(value "$out" rc=)"
out=$(PIX_CLOCK_NOW=20261006110000 bank "pix.qr.check|$qrb|OP01")
check "qr.expire.bizdate.independent.expired" "20" "$(value "$out" rc=)"

# day, month, year and leap rollovers
out=$(PIX_CLOCK_NOW=20261231235900 bank "pix.qr.create|DYNAMIC|$qxa2|$qxkey|CPF|23456789092|10.00|PIX MERCHANT|SAO PAULO|0000|OP01|COR|QXD4|86399")
check "qr.expire.year.rollover" "20270101235859" "$(value "$out" expiresat=)"
qry=$(value "$out" id=)
out=$(PIX_CLOCK_NOW=20270101235858 bank "pix.qr.check|$qry|OP01")
check "qr.expire.year.last-second" "00" "$(value "$out" rc=)"
out=$(PIX_CLOCK_NOW=20270101235859 bank "pix.qr.check|$qry|OP01")
check "qr.expire.year.expired" "20" "$(value "$out" rc=)"
out=$(PIX_CLOCK_NOW=20280228235900 bank "pix.qr.create|DYNAMIC|$qxa2|$qxkey|CPF|23456789092|10.00|PIX MERCHANT|SAO PAULO|0000|OP01|COR|QXD5|86400")
check "qr.expire.leap-day" "20280229235900" "$(value "$out" expiresat=)"
out=$(PIX_CLOCK_NOW=21000228000000 bank "pix.qr.create|DYNAMIC|$qxa2|$qxkey|CPF|23456789092|10.00|PIX MERCHANT|SAO PAULO|0000|OP01|COR|QXD6|86400")
check "qr.expire.century.no-leap" "21000301000000" "$(value "$out" expiresat=)"

# institution default is one boundary knob; explicit expiration still wins
sed -i 's/^qr-expiration-default-seconds=.*/qr-expiration-default-seconds=120/' etc/pix.cfg
out=$(PIX_CLOCK_NOW=20261006100000 bank "pix.qr.create|DYNAMIC|$qxa2|$qxkey|CPF|23456789092|20.00|PIX MERCHANT|SAO PAULO|0000|OP01|COR|QXD7")
check "qr.expire.cfg.default.ttl" "0000120" "$(value "$out" ttlsec=)"
check "qr.expire.cfg.default.expiresat" "20261006100200" "$(value "$out" expiresat=)"
out=$(bank "pix.qr.create|DYNAMIC|$qxa2|$qxkey|CPF|23456789092|20.00|PIX MERCHANT|SAO PAULO|0000|OP01|COR|QXD8|3600")
check "qr.expire.cfg.explicit-wins" "20261006110000" "$(value "$out" expiresat=)"
sed -i 's/^qr-expiration-default-seconds=.*/qr-expiration-default-seconds=86400/' etc/pix.cfg

# unknown QR is refused for check and pay with zero side effects
out=$(PIX_CLOCK_NOW=20261006101500 bank "pix.qr.check|R99999999999|OP01")
check "qr.expire.check.unknown.rc" "23" "$(value "$out" rc=)"
out=$(bank "pix.out.qr|R99999999999|30.00|$qxa1||unknown qr|OP01|COR|QXP2")
check "qr.expire.pay.unknown.rc" "23" "$(value "$out" rc=)"
unset PIX_CLOCK_NOW

# --- pix-split-prep: multi-destination extension-point guard ---
reset
bank "ledger.init" >/dev/null
bank "pix.rt.create|12345678|KOF|DEBITS|DPI|Y||OP01|CORP|SPE1" >/dev/null
out=$(bank "customer.create|P|SPLIT PAYER|CPF|123.456.789-09|19900101|OP01|SPE2")
spc1=$(value "$out" id=)
out=$(bank "account.open|$spc1|DMND|BRL|500000|OP01|SPE3|A")
spa1=$(value "$out" id=)
out=$(bank "customer.create|P|SPLIT PAYEE|CPF|234.567.890-92|19900101|OP01|SPE4")
spc2=$(value "$out" id=)
out=$(bank "account.open|$spc2|DMND|BRL|500000|OP01|SPE5|B")
spa2=$(value "$out" id=)
out=$(bank "pix.key.register|CPF|234.567.890-92|$spa2|$spc2|OP01|SPE6|K")
spkey=$(value "$out" id=)
out=$(bank "pix.out.key|$spkey|100.00|$spa1|||split intent|OP01|COR|SPR1||Y|Y")
check "split.guard.key.rc" "20" "$(value "$out" rc=)"
check "split.guard.key.msg" "yes" "$(grep -aq '^msg=SPLIT REQUIRES 1 TO 20 ALLOCATIONS' <<<"$out" && echo yes || echo no)"
out=$(bank "pix.qr.create|DYNAMIC|$spa2|$spkey|CPF|23456789092|80.00|SPLIT MERCHANT|SAO PAULO|0000|OP01|COR|SPR2")
spqr=$(value "$out" id=)
out=$(bank "pix.out.qr|$spqr|80.00|$spa1|||qr split intent|OP01|COR|SPR3||Y|Y")
check "split.guard.qr.rc" "20" "$(value "$out" rc=)"
check "split.guard.qr.msg" "yes" "$(grep -aq '^msg=SPLIT REQUIRES 1 TO 20 ALLOCATIONS' <<<"$out" && echo yes || echo no)"
out=$(bank "ledger.balance|$spa1")
check "split.guard.no-debit" "500000.00" "$(value "$out" available=)"
out=$(bank "pix.out.key|$spkey|100.00|$spa1|||single dest|OP01|COR|SPR4||Y")
check "split.single.ok" "POSTED" "$(value "$out" status=)"

# --- pix-split: multi-destination allocation engine ---
reset
bank "ledger.init" >/dev/null
bank "pix.rt.create|12345678|KOF|DEBITS|DPI|Y||OP01|CORP|SPA0" >/dev/null
out=$(bank "customer.create|P|SPLIT PAYER|CPF|123.456.789-09|19900101|OP01|SPA1")
spc1=$(value "$out" id=)
out=$(bank "account.open|$spc1|DMND|BRL|500000|OP01|SPA2|A")
spa1=$(value "$out" id=)
out=$(bank "customer.create|P|SPLIT PAYEE1|CPF|234.567.890-92|19900101|OP01|SPA3")
spc2=$(value "$out" id=)
out=$(bank "account.open|$spc2|DMND|BRL|0|OP01|SPA4|B")
spa2=$(value "$out" id=)
out=$(bank "customer.create|P|SPLIT PAYEE2|CPF|345.678.901-91|19900101|OP01|SPA5")
spc3=$(value "$out" id=)
out=$(bank "account.open|$spc3|DMND|BRL|0|OP01|SPA6|C")
spa3=$(value "$out" id=)

# structural validation at the payment boundary
out=$(bank "pix.split.validate|CUSTOMER:$spa2:60.00:MAIN;CUSTOMER:$spa3:40.00:MAIN|100.00|$spa1")
check "split.valid.rc" "00" "$(value "$out" rc=)"
check "split.valid.total" "yes" "$(grep -aq '^total=+000000000000100.00' <<<"$out" && echo yes || echo no)"
out=$(bank "pix.split.validate|CUSTOMER:$spa2:60.00:MAIN;CUSTOMER:$spa3:30.00:MAIN|100.00|$spa1")
check "split.sum.rc" "20" "$(value "$out" rc=)"
check "split.sum.msg" "yes" "$(grep -aq '^msg=PIX SPLIT ALLOCATION SUM != GROSS' <<<"$out" && echo yes || echo no)"
out=$(bank "pix.split.validate|CUSTOMER:$spa2:0.00:MAIN;CUSTOMER:$spa3:100.00:MAIN|100.00|$spa1")
check "split.zero.rc" "20" "$(value "$out" rc=)"
check "split.zero.msg" "yes" "$(grep -aq '^msg=ALLOCATION AMOUNT MUST BE POSITIVE' <<<"$out" && echo yes || echo no)"
out=$(bank "pix.split.validate|CUSTOMER:$spa2:60.00:MAIN;BOGUS:$spa3:40.00:MAIN|100.00|$spa1")
check "split.role.rc" "20" "$(value "$out" rc=)"
out=$(bank "pix.split.validate|CUSTOMER:$spa2:60.00:MAIN;CUSTOMER:ZZZZ00000000:40.00:MAIN|100.00|$spa1")
check "split.dest.rc" "20" "$(value "$out" rc=)"
out=$(bank "pix.split.validate|CUSTOMER:$spa2:60.00:MAIN;TAX:$spa3:40.00:TAX|100.00|$spa1")
check "split.taxmeta.rc" "20" "$(value "$out" rc=)"
check "split.taxmeta.msg" "yes" "$(grep -aq '^msg=TAX ALLOCATION METADATA INCOMPLETE' <<<"$out" && echo yes || echo no)"
out=$(bank "pix.split.validate|CUSTOMER:$spa2:60.00:MAIN:X:Y:Z;CUSTOMER:$spa3:40.00:MAIN|100.00|$spa1")
check "split.taxbleed.rc" "20" "$(value "$out" rc=)"
out=$(bank "pix.split.validate|CUSTOMER:$spa2:60.00:MAIN;PARTICIPANT:P00000000001:40.00:MAIN|100.00|$spa1")
check "split.participant.rc" "00" "$(value "$out" rc=)"

# full posted split: gross debit once, credits per allocation
out=$(bank "pix.split.request|CUSTOMER:$spa2:60.00:MAIN;CUSTOMER:$spa3:40.00:MAIN|100.00|$spa1|||posted split|OP01|COR|SPS1||Y")
check "split.post.rc" "00" "$(value "$out" rc=)"
check "split.post.status" "POSTED" "$(value "$out" status=)"
check "split.post.cnt" "02" "$(value "$out" splitcnt=)"
spid=$(value "$out" id=)
check "split.post.allocids" "yes" "$(grep -aq 'L000000000' <<<"$out" && echo yes || echo no)"
out=$(bank "ledger.balance|$spa1")
check "split.gross.debit" "499900.00" "$(value "$out" available=)"
out=$(bank "ledger.balance|$spa2")
check "split.leg1.credit" "60.00" "$(value "$out" available=)"
out=$(bank "ledger.balance|$spa3")
check "split.leg2.credit" "40.00" "$(value "$out" available=)"
out=$(bank "ledger.trial")
sptd=$(value "$out" total-debit=)
sptc=$(value "$out" total-credit=)
check "split.trial.rc" "00" "$(value "$out" rc=)"
check "split.trial.balanced" "yes" "$([ "$sptd" = "$sptc" ] && echo yes || echo no)"

# allocations durable and marked POSTED (fresh process = restart-safe read)
out=$(bank "pix.split.show|$spid")
check "split.show.rc" "00" "$(value "$out" rc=)"
check "split.show.total" "yes" "$(grep -aq '^total=+000000000000100.00' <<<"$out" && echo yes || echo no)"
check "split.show.posted1" "yes" "$(grep -aq '^leg 01.*st=POSTED' <<<"$out" && echo yes || echo no)"
check "split.show.posted2" "yes" "$(grep -aq '^leg 02.*st=POSTED' <<<"$out" && echo yes || echo no)"
check "split.show.seq" "yes" "$(grep -aq '^leg 01.*seq=01' <<<"$out" && grep -aq '^leg 02.*seq=02' <<<"$out" && echo yes || echo no)"

# idempotency: identical replay re-posts nothing
out=$(bank "pix.split.request|CUSTOMER:$spa2:60.00:MAIN;CUSTOMER:$spa3:40.00:MAIN|100.00|$spa1|||posted split|OP01|COR|SPS1||Y")
check "split.replay.rc" "00" "$(value "$out" rc=)"
check "split.replay.flag" "Y" "$(value "$out" replay=)"
sptxn=$(value "$out" txn=)
out=$(bank "ledger.balance|$spa1")
check "split.replay.noextra" "499900.00" "$(value "$out" available=)"

# same request key, different decomposition: first intent wins (no new posting)
out=$(bank "pix.split.request|CUSTOMER:$spa2:70.00:MAIN;CUSTOMER:$spa3:30.00:MAIN|100.00|$spa1|||posted split alt|OP01|COR|SPS1||Y")
check "split.samekey.rc" "00" "$(value "$out" rc=)"
check "split.samekey.replay" "Y" "$(value "$out" replay=)"
check "split.samekey.txn-stable" "$sptxn" "$(value "$out" txn=)"
out=$(bank "pix.split.show|$spid")
check "split.samekey.legs-intact" "yes" "$(grep -aq '^leg 01.*amt=+000000000000060.00' <<<"$out" && echo yes || echo no)"

# tax allocation leg: explicit metadata, no tax calculation by engine
out=$(bank "pix.split.request|CUSTOMER:$spa2:55.00:MAIN;TAX:$spa3:45.00:TAX:ISS:GRL:NF-9|100.00|$spa1|||tax split|OP01|COR|SPS3||Y")
check "split.tax.rc" "00" "$(value "$out" rc=)"
sptid=$(value "$out" id=)
out=$(bank "pix.split.show|$sptid")
check "split.tax.total45" "yes" "$(grep -aq '^taxtotal=+000000000000045.00' <<<"$out" && echo yes || echo no)"
check "split.tax.posted" "yes" "$(grep -aq '^leg 02.*type=TAX.*st=POSTED' <<<"$out" && echo yes || echo no)"

# participant destination: external leg keeps gross settlement identity
out=$(bank "pix.rt.create|87654321|EXTB|DEBITS|DPI|N||OP01|CORP|SPS0")
sppart=$(value "$out" id=)
out=$(bank "pix.split.request|CUSTOMER:$spa2:60.00:MAIN;PARTICIPANT:$sppart:40.00:MAIN|100.00|$spa1|||ext split|OP01|COR|SPS4||Y")
check "split.ext.rc" "00" "$(value "$out" rc=)"
speid=$(value "$out" id=)
out=$(bank "pix.split.show|$speid")
check "split.ext.total" "yes" "$(grep -aq '^exttotal=+000000000000040.00' <<<"$out" && echo yes || echo no)"

# single-destination behavior unchanged
out=$(bank "pix.key.register|CPF|234.567.890-92|$spa2|$spc2|OP01|SPS6|K")
spkey2=$(value "$out" id=)
out=$(bank "pix.out.key|$spkey2|100.00|$spa1|||plain|OP01|COR|SPS5||Y")
check "split.single.unaffected" "no" "$(grep -aq '^msg=PIX SPLIT' <<<"$out" && echo yes || echo no)"

# --- pix-split-reversal: allocation-level devolution ---
reset
bank "ledger.init" >/dev/null
bank "pix.rt.create|12345678|KOF|DEBITS|DPI|Y||OP01|CORP|RVA0" >/dev/null
out=$(bank "customer.create|P|SPLIT PAYER|CPF|123.456.789-09|19900101|OP01|RVA1")
rvc1=$(value "$out" id=)
out=$(bank "account.open|$rvc1|DMND|BRL|500000|OP01|RVA2|A")
rva1=$(value "$out" id=)
out=$(bank "customer.create|P|SPLIT PAYEE1|CPF|234.567.890-92|19900101|OP01|RVA3")
rvc2=$(value "$out" id=)
out=$(bank "account.open|$rvc2|DMND|BRL|0|OP01|RVA4|B")
rva2=$(value "$out" id=)
out=$(bank "customer.create|P|SPLIT PAYEE2|CPF|345.678.901-91|19900101|OP01|RVA5")
rvc3=$(value "$out" id=)
out=$(bank "account.open|$rvc3|DMND|BRL|0|OP01|RVA6|C")
rva3=$(value "$out" id=)

out=$(bank "pix.split.request|CUSTOMER:$rva2:60.00:MAIN;CUSTOMER:$rva3:40.00:MAIN|100.00|$rva1|||posted split|OP01|COR|RVB1||Y")
check "revsetup.rc" "00" "$(value "$out" rc=)"
rvid=$(value "$out" id=)
out=$(bank "pix.split.show|$rvid")
rvl1=$(grep -a '^leg 01' <<<"$out" | grep -ao 'aid=[A-Z0-9]*' | cut -d= -f2)
rvl2=$(grep -a '^leg 02' <<<"$out" | grep -ao 'aid=[A-Z0-9]*' | cut -d= -f2)
check "revsetup.legids" "yes" "$([ -n "$rvl1" ] && [ -n "$rvl2" ] && echo yes || echo no)"

# gross devolution of a split pix is rejected (no implicit full reversal)
out=$(bank "pix.devol|$rvid|10.00|GROSS ATTEMPT|OP01|COR|RVC1")
check "rev.gross.rc" "20" "$(value "$out" rc=)"
check "rev.gross.msg" "yes" "$(grep -aq 'SPLIT PIX REQUIRES EXPLICIT LEG REVERSAL' <<<"$out" && echo yes || echo no)"

# partial leg reversal: 25.00 of leg1 (60.00)
out=$(bank "pix.split.reverse|$rvid|$rvl1:25.00|RVREQ1")
check "rev.partial.rc" "00" "$(value "$out" rc=)"
check "rev.partial.devoid" "yes" "$(grep -a '^devoid=' <<<"$out" | grep -aq 'W' && echo yes || echo no)"
check "rev.partial.devstatus" "PARTIAL" "$(value "$out" devstatus=)"
out=$(bank "ledger.balance|$rva1")
check "rev.partial.payer" "499925.00" "$(value "$out" available=)"
out=$(bank "ledger.balance|$rva2")
check "rev.partial.payee1" "35.00" "$(value "$out" available=)"
out=$(bank "ledger.balance|$rva3")
check "rev.partial.payee2" "40.00" "$(value "$out" available=)"
out=$(bank "ledger.trial")
check "rev.partial.trial" "yes" "$([ "$(value "$out" total-debit=)" = "$(value "$out" total-credit=)" ] && echo yes || echo no)"

# idempotent replay of same request id: no second posting
out=$(bank "pix.split.reverse|$rvid|$rvl1:25.00|RVREQ1")
check "rev.replay.rc" "00" "$(value "$out" rc=)"
check "rev.replay.flag" "Y" "$(value "$out" replay=)"
out=$(bank "ledger.balance|$rva1")
check "rev.replay.noeffect" "499925.00" "$(value "$out" available=)"

# over-reversal on remaining is refused (remain=35)
out=$(bank "pix.split.reverse|$rvid|$rvl1:36.00|RVREQ2")
check "rev.over.rc" "20" "$(value "$out" rc=)"
check "rev.over.msg" "yes" "$(grep -aq 'EXCEEDS REMAINING LEG AMOUNT' <<<"$out" && echo yes || echo no)"
out=$(bank "ledger.balance|$rva1")
check "rev.over.noeffect" "499925.00" "$(value "$out" available=)"

# remaining legs reversed fully via auto build (full keyword)
out=$(bank "pix.split.reverse|$rvid|full|RVREQ3")
check "rev.auto.rc" "00" "$(value "$out" rc=)"
check "rev.auto.amount" "yes" "$(grep -aq '^amount=+000000000000075.00' <<<"$out" && echo yes || echo no)"
check "rev.auto.devstatus" "FULL" "$(value "$out" devstatus=)"
out=$(bank "ledger.balance|$rva1")
check "rev.auto.payer" "500000.00" "$(value "$out" available=)"
out=$(bank "ledger.balance|$rva2")
check "rev.auto.payee1" "0.00" "$(value "$out" available=)"
out=$(bank "ledger.balance|$rva3")
check "rev.auto.payee2" "0.00" "$(value "$out" available=)"

# original pix reaches DEVOLVED and remains immutable afterwards
out=$(bank "pix.get|$rvid")
check "rev.pix.devolved" "DEVOLVED" "$(value "$out" status=)"
out=$(bank "pix.split.show|$rvid")
check "rev.show.remain0" "yes" "$(grep -aq '^remain=+000000000000000.00' <<<"$out" && echo yes || echo no)"
check "rev.show.devolved100" "yes" "$(grep -aq '^devolved=+000000000000100.00' <<<"$out" && echo yes || echo no)"
check "rev.show.origintact" "yes" "$(grep -aq '^leg 01.*amt=+000000000000060.00' <<<"$out" && grep -aq '^leg 02.*amt=+000000000000040.00' <<<"$out" && echo yes || echo no)"
check "rev.show.remainleg" "yes" "$(grep -aq '^leg 01.*remain=+000000000000000.00' <<<"$out" && echo yes || echo no)"

# further reversal attempts refused on a fully devolved pix
out=$(bank "pix.split.reverse|$rvid|$rvl2:10.00|RVREQ4")
check "rev.afterfull.rc" "20" "$(value "$out" rc=)"

# reversal headers are durable and listable in a fresh process
out=$(bank "pix.split.reversals|$rvid")
check "rev.list.rc" "00" "$(value "$out" rc=)"
check "rev.list.cnt" "02" "$(value "$out" cnt=)"
check "rev.list.posted" "yes" "$(grep -ac 'st=POSTED' <<<"$out" | grep -aq '^2$' && echo yes || echo no)"
out=$(bank "ledger.trial")
check "rev.final.trial" "yes" "$([ "$(value "$out" total-debit=)" = "$(value "$out" total-credit=)" ] && echo yes || echo no)"

# tax split reversal: metadata is preserved on reversal legs
out=$(bank "pix.split.request|CUSTOMER:$rva2:55.00:MAIN;TAX:$rva3:45.00:TAX:ISS:GRL:NF-9|100.00|$rva1|||tax split|OP01|COR|RVB2||Y")
check "rev.taxsetup.rc" "00" "$(value "$out" rc=)"
rvtid=$(value "$out" id=)
out=$(bank "pix.split.show|$rvtid")
rvtax=$(grep -a '^leg 02' <<<"$out" | grep -ao 'aid=[A-Z0-9]*' | cut -d= -f2)
out=$(bank "pix.split.reverse|$rvtid|$rvtax:45.00|RVREQ5")
check "rev.tax.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.split.show|$rvtid")
check "rev.tax.taxtotal" "yes" "$(grep -aq '^taxtotal=+000000000000045.00' <<<"$out" && echo yes || echo no)"
check "rev.tax.remain" "yes" "$(grep -aq '^remain=+000000000000055.00' <<<"$out" && echo yes || echo no)"
out=$(bank "ledger.balance|$rva3")
check "rev.tax.payeebalance" "0.00" "$(value "$out" available=)"
out=$(bank "ledger.trial")
check "rev.tax.trial" "yes" "$([ "$(value "$out" total-debit=)" = "$(value "$out" total-credit=)" ] && echo yes || echo no)"

# participant split + settlement netting after leg reversal
out=$(bank "pix.rt.create|87654321|EXTC|DEBITS|DPI|N||OP01|CORP|RVC0")
rvpart=$(value "$out" id=)
out=$(bank "pix.split.request|CUSTOMER:$rva2:60.00:MAIN;PARTICIPANT:$rvpart:40.00:MAIN|100.00|$rva1|||ext split rv|OP01|COR|RVC1||Y")
check "rev.ext.rc" "00" "$(value "$out" rc=)"
rvxid=$(value "$out" id=)
out=$(bank "pix.split.show|$rvxid")
rvx2=$(grep -a '^leg 02' <<<"$out" | grep -ao 'aid=[A-Z0-9]*' | cut -d= -f2)
out=$(bank "pix.split.reverse|$rvxid|$rvx2:30.00|RVCREQ1")
check "rev.ext.rev.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.cycle.open|20261002|BRL|||||OP01|COR|RVC2")
check "rev.cycle.open" "00" "$(value "$out" rc=)"
rvcyc=$(value "$out" cycle=)
out=$(bank "pix.cycle.accrue|20261002|BRL|||||OP01|COR|RVC3")
check "rev.cycle.accrue.rc" "00" "$(value "$out" rc=)"
check "rev.cycle.netpay" "yes" "$(grep -aq '^grosspay=' <<<"$out" && echo yes || echo no)"
out=$(bank "pix.cycle.close|$rvcyc|||||OP01|COR|RVC4")
check "rev.cycle.close" "CLOSED" "$(value "$out" status=)"
out=$(bank "pix.cycle.calc|$rvcyc|||||OP01|COR|RVC5")
check "rev.cycle.calc.rc" "00" "$(value "$out" rc=)"
# participant obligation nets the reversed 30.00 (and the earlier internal
# splits' participant legs): payable reduced vs gross accrued
check "rev.cycle.nettable" "yes" "$([ -n "$(value "$out" grosspay=)" ] && echo yes || echo no)"

# MED full lifecycle on a split payment: hold, decide, leg-level devolution
out=$(bank "pix.split.request|CUSTOMER:$rva2:60.00:MAIN;CUSTOMER:$rva3:40.00:MAIN|100.00|$rva1|||med split|OP01|COR|RVM1||Y")
check "rev.med.setup" "00" "$(value "$out" rc=)"
rvmed=$(value "$out" id=)
out=$(bank "pix.med.open|$rvmed|100.00|BRL|$rvc2|PAYEE|FRAUDE|Y|OP01|OPM|RVM2")
check "rev.med.open" "00" "$(value "$out" rc=)"
rvcase=$(value "$out" medcase=)
out=$(bank "pix.med.block|$rvcase|OPM|RVM3")
check "rev.med.block.rc" "00" "$(value "$out" rc=)"
check "rev.med.block.hold" "60.00" "$(value "$out" blocked=)"
out=$(bank "pix.med.decide|$rvcase|APPROVE||fundamentado|OPM|RVM4")
check "rev.med.decide" "00" "$(value "$out" rc=)"
out=$(bank "pix.med.execute|$rvcase||OPM|RVM5")
check "rev.med.exec.rc" "00" "$(value "$out" rc=)"
rvmdev=$(value "$out" devol=)
check "rev.med.devoid" "yes" "$(grep -aq '^devol=W' <<<"$out" && echo yes || echo no)"
out=$(bank "pix.med.execute|$rvcase||OPM|RVM6")
check "rev.med.replay" "DEVOLVED" "$(value "$out" status=)"
check "rev.med.replayflag" "Y" "$(value "$out" replay=)"
out=$(bank "pix.split.show|$rvmed")
check "rev.med.remain" "yes" "$(grep -aq '^devolved=+000000000000060.00' <<<"$out" && echo yes || echo no)"
out=$(bank "pix.get|$rvmed")
check "rev.med.devstatus" "PARTIAL" "$(value "$out" dev=)"
out=$(bank "pix.devol.get|$rvmdev")
check "rev.med.devolget" "00" "$(value "$out" rc=)"
out=$(bank "pix.split.show|$rvmed")
rvm2=$(grep -a '^leg 02' <<<"$out" | grep -ao 'aid=[A-Z0-9]*' | cut -d= -f2)
out=$(bank "pix.split.reverse|$rvmed|$rvm2:40.00|RVM7")
check "rev.med.rest.rc" "00" "$(value "$out" rc=)"
check "rev.med.rest.dev" "FULL" "$(value "$out" devstatus=)"
out=$(bank "pix.get|$rvmed")
check "rev.med.rest.status" "DEVOLVED" "$(value "$out" status=)"
out=$(bank "ledger.trial")
check "rev.med.trial" "yes" "$([ "$(value "$out" total-debit=)" = "$(value "$out" total-credit=)" ] && echo yes || echo no)"

# --- pix-doc-cnpj: alphanumeric CNPJ identity regressions ---
reset
bank "ledger.init" >/dev/null
bank "pix.rt.create|12345678|KOF|DEBITS|DPI|Y||OP01|CORP|DCE1" >/dev/null
out=$(bank "customer.create|J|LEGACY ACME|CNPJ|33.000.167/0001-01|20000101|OP01|DCE2")
check "cnpj.legacy.customer" "00" "$(value "$out" rc=)"
dcc1=$(value "$out" id=)
out=$(bank "customer.create|J|LEGACY ACME ALT|CNPJ|33000167000101|20000101|OP01|DCE3")
check "cnpj.legacy.canon-dedup" "22" "$(value "$out" rc=)"
out=$(bank "customer.create|P|FORMATTED CPF|CPF|123.456.789-09|19900101|OP01|DCE4")
check "cnpj.cpf.formatted" "00" "$(value "$out" rc=)"
dcpc=$(value "$out" id=)
out=$(bank "customer.create|P|RAW CPF|CPF|12345678909|19900101|OP01|DCE5")
check "cnpj.cpf.canon-dedup" "22" "$(value "$out" rc=)"
out=$(bank "account.open|$dcc1|DMND|BRL|500000|OP01|DCE6|A")
dca1=$(value "$out" id=)
out=$(bank "pix.key.register|CNPJ|33000167000101|$dca1|$dcc1|OP01|DCE7|K")
check "cnpj.key.legacy.rc" "00" "$(value "$out" rc=)"
check "cnpj.key.legacy.verified" "VERIFIED" "$(value "$out" verified=)"
out=$(bank "pix.key.lookup|CNPJ|33.000.167/0001-01")
check "cnpj.key.lookup-cross-format" "00" "$(value "$out" rc=)"
out=$(bank "pix.key.register|CNPJ|33000167000100|$dca1|$dcc1|OP01|DCE8|K")
check "cnpj.key.bad-dv" "20" "$(value "$out" rc=)"
check "cnpj.key.bad-dv.msg" "yes" "$(grep -aq '^msg=INVALID CNPJ CHECK DIGIT' <<<"$out" && echo yes || echo no)"
out=$(bank "pix.key.register|CNPJ|11111111111111|$dca1|$dcc1|OP01|DCE9|K")
check "cnpj.key.repeated" "20" "$(value "$out" rc=)"
out=$(bank "customer.create|J|ALPHA CORP|CNPJ|AB1C2D3E4F5G13|20260801|OP01|DCF1")
check "cnpj.alnum.customer" "00" "$(value "$out" rc=)"
dcc2=$(value "$out" id=)
out=$(bank "customer.create|J|ALPHA CORP DUP|CNPJ|ab1c2d3e4f5g13|20260801|OP01|DCF2")
check "cnpj.alnum.canon-dedup" "22" "$(value "$out" rc=)"
out=$(bank "account.open|$dcc2|DMND|BRL|500000|OP01|DCF3|B")
dca2=$(value "$out" id=)
out=$(bank "pix.key.register|CNPJ|ab.1c2d3e4f5g13|$dca2|$dcc2|OP01|DCF4|K")
check "cnpj.alnum.key.rc" "00" "$(value "$out" rc=)"
check "cnpj.alnum.key.verified" "VERIFIED" "$(value "$out" verified=)"
alnumkey=$(value "$out" id=)
mask=$(grep '^mask=' <<<"$out" | head -1 | sed 's/^mask= *//')
case "$mask" in
    *AB1C*|*ab1c**) leak=yes ;;
    *) leak=no ;;
esac
check "cnpj.alnum.key.masked" "no" "$leak"
out=$(bank "pix.key.lookup|CNPJ|AB1C2D3E4F5G13")
check "cnpj.alnum.lookup" "00" "$(value "$out" rc=)"
out=$(bank "pix.key.lookup|CNPJ|AB1C2D3E4F5G13I")
check "cnpj.alnum.lookup.wrong-len" "20" "$(value "$out" rc=)"
out=$(bank "pix.key.register|CNPJ|AB1C2D3E4F5G1_|$dca2|$dcc2|OP01|DCF5|K")
check "cnpj.badchar" "20" "$(value "$out" rc=)"
check "cnpj.badchar.msg" "yes" "$(grep -aq '^msg=INVALID DOCUMENT CHARACTERS' <<<"$out" && echo yes || echo no)"
out=$(bank "pix.qr.create|DYNAMIC|$dca2|$alnumkey|CNPJ|AB1C2D3E4F5G13|10.00|ALPHA CORP|SAO PAULO|0000|OP01|DCF6|Q")
check "cnpj.qr.rc" "00" "$(value "$out" rc=)"
check "cnpj.qr.payload-key" "yes" "$(grep -F "AB1C2D3E4F5G13" <<<"$out" >/dev/null && echo yes || echo no)"
out=$(bank "pix.key.delete|$alnumkey|OP01|DCF7|K")
check "cnpj.alnum.delete" "REVOKED" "$(value "$out" status=)"

# --- pix-doc-cnpj-alphanumeric: official RFB alphanumeric DV ---
reset
bank "ledger.init" >/dev/null
bank "pix.rt.create|12345678|KOF|DEBITS|DPI|Y||OP01|CORP|ALA0" >/dev/null
out=$(bank "customer.create|J|OFFICIAL ORG|CNPJ|12ABC34501DE35|20260801|OP01|ALA1")
c1=$(value "$out" id=)
out=$(bank "account.open|$c1|DMND|BRL|500000|OP01|ALA2|A")
a1=$(value "$out" id=)
out=$(bank "customer.create|J|MIXED CORP|CNPJ|1A2B3C4D5E6F34|20260801|OP01|ALA3")
c2=$(value "$out" id=)
out=$(bank "account.open|$c2|DMND|BRL|0|OP01|ALA4|B")
a2=$(value "$out" id=)
out=$(bank "customer.create|J|TAX CORP|CNPJ|ABCDEFGHIJKL80|20260801|OP01|ALA5")
c3=$(value "$out" id=)
out=$(bank "account.open|$c3|DMND|BRL|0|OP01|ALA6|C")
a3=$(value "$out" id=)
out=$(bank "customer.create|J|LOWER CORP|CNPJ|11ABCDEF234590|20260801|OP01|ALA7")
c4=$(value "$out" id=)
out=$(bank "account.open|$c4|DMND|BRL|0|OP01|ALA8|D")
a4=$(value "$out" id=)
out=$(bank "customer.create|J|FIFTH CORP|CNPJ|0A1B2C3D4E5F23|20260801|OP01|ALA9")
c5=$(value "$out" id=)
out=$(bank "account.open|$c5|DMND|BRL|0|OP01|ALB0|E")
a5=$(value "$out" id=)

# official example from the RFB technical note, formatted input
out=$(bank "pix.key.register|CNPJ|12.ABC.345/01DE-35|$a1|$c1|OP01|ALB1|K")
check "alnum.official.register" "00" "$(value "$out" rc=)"
check "alnum.official.verified" "VERIFIED" "$(value "$out" verified=)"
alcan=$(value "$out" id=)
out=$(bank "pix.key.lookup|CNPJ|12ABC34501DE35")
check "alnum.canon.cross" "00" "$(value "$out" rc=)"
check "alnum.canon.cross.id" "$alcan" "$(value "$out" id=)"
out=$(bank "pix.key.delete|$alcan")
check "alnum.official.delete" "00" "$(value "$out" rc=)"
out=$(bank "pix.key.lookup|CNPJ|12ABC34501DE35")
check "alnum.absence.rc" "23" "$(value "$out" rc=)"

# DV failures refused even for structurally-valid alphanumeric strings
out=$(bank "pix.key.register|CNPJ|12ABC34501DE34|$a1|$c1|OP01|ALB2|K")
check "alnum.dv2.bad" "20" "$(value "$out" rc=)"
check "alnum.dv2.msg" "yes" "$(grep -aq '^msg=INVALID CNPJ CHECK DIGIT' <<<"$out" && echo yes || echo no)"
out=$(bank "pix.key.register|CNPJ|12ABC34501DE95|$a1|$c1|OP01|ALB3|K")
check "alnum.dv1.bad" "20" "$(value "$out" rc=)"
out=$(bank "pix.key.register|CNPJ|12BBC34501DE35|$a1|$c1|OP01|ALB4|K")
check "alnum.base-mutate.rejected" "20" "$(value "$out" rc=)"

# lowercase + separators canonicalize before DV
out=$(bank "pix.key.register|CNPJ|11.abc.def/2345-90|$a4|$c4|OP01|ALB5|K")
check "alnum.lowercase" "00" "$(value "$out" rc=)"
check "alnum.lowercase.verified" "VERIFIED" "$(value "$out" verified=)"

# mixed and all-letter bases verify; customer dedup across formats
out=$(bank "pix.key.register|CNPJ|ab.1c2d3e4f5g13|$a2|$c2|OP01|ALB6|K")
check "alnum.mixed.register" "00" "$(value "$out" rc=)"
check "alnum.mixed.verified" "VERIFIED" "$(value "$out" verified=)"
out=$(bank "pix.key.lookup|CNPJ|1A2B3C4D5E6F34")
check "alnum.mixed.lookup" "20" "$(value "$out" rc=)"
check "alnum.mixed.lookup.msg" "yes" "$(grep -aq 'PIX KEY NOT REGISTERED IN DICT' <<<"$out" && echo yes || echo no)"
out=$(bank "customer.create|J|ALL LETTERS DUP|CNPJ|abcdefghijk l80|20260801|OP01|ALB7")
check "alnum.allalpha.customer-dedup" "22" "$(value "$out" rc=)"
out=$(bank "customer.create|J|ALL SAME|CNPJ|AAAAAAAAAAAAAA|20260801|OP01|ALB8")
check "alnum.all-same.customer" "00" "$(value "$out" rc=)"
out=$(bank "pix.key.register|CNPJ|AAAAAAAAAAAAAA|$a3|$c3|OP01|ALB9|K")
check "alnum.all-same.rejected" "20" "$(value "$out" rc=)"
check "alnum.all-same.msg" "yes" "$(grep -aq 'INVALID REPEATED' <<<"$out" && echo yes || echo no)"

# structure boundary
out=$(bank "pix.key.register|CNPJ|12ABC34501DE3|$a1|$c1|OP01|ALC0|K")
check "alnum.short" "20" "$(value "$out" rc=)"
out=$(bank "pix.key.register|CNPJ|12ABC34501DE355|$a1|$c1|OP01|ALC1|K")
check "alnum.long" "20" "$(value "$out" rc=)"
out=$(bank "pix.key.register|CNPJ|12ABC34501DEAB|$a1|$c1|OP01|ALC2|K")
check "alnum.letter-dv" "20" "$(value "$out" rc=)"
check "alnum.letter-dv.msg" "yes" "$(grep -aq 'DV POSITIONS MUST BE NUMERIC' <<<"$out" && echo yes || echo no)"
out=$(bank "pix.key.register|CNPJ|12ABC!4501DE35|$a1|$c1|OP01|ALC3|K")
check "alnum.punct" "20" "$(value "$out" rc=)"

# legacy numeric regression through the unified routine
out=$(bank "customer.create|J|LEGACY REG|CNPJ|33000167000101|20260801|OP01|ALC3B")
cleg=$(value "$out" id=)
out=$(bank "account.open|$cleg|DMND|BRL|0|OP01|ALC3C|L")
aleg=$(value "$out" id=)
out=$(bank "pix.key.register|CNPJ|33.000.167/0001-01|$aleg|$cleg|OP01|ALC4|K")
check "alnum.legacy-key" "00" "$(value "$out" rc=)"
check "alnum.legacy.verified" "VERIFIED" "$(value "$out" verified=)"
out=$(bank "pix.key.register|CNPJ|33000167000100|$a5|$c2|OP01|ALC5|K")
check "alnum.legacy.bad-dv" "20" "$(value "$out" rc=)"

# split allocation + tax metadata carry the verified alphanumeric CNPJ
out=$(bank "pix.split.request|CUSTOMER:$a2:50.00:MAIN;TAX:$a3:50.00:TAX:ISS:GRL:12ABC34501DE35|100.00|$a1|||alnum tax split|OP01|COR|ALC6||Y")
check "alnum.split.rc" "00" "$(value "$out" rc=)"
alnsx=$(value "$out" id=)
out=$(bank "pix.split.show|$alnsx")
check "alnum.split.taxtype" "yes" "$(grep -aq '^leg 02: .*type=TAX' <<<"$out" && echo yes || echo no)"
check "alnum.split.taxtotal" "yes" "$(grep -aq '^taxtotal=+000000000000050.00' <<<"$out" && echo yes || echo no)"
alnl2=$(grep -a '^leg 02' <<<"$out" | grep -ao 'aid=[A-Z0-9]*' | cut -d= -f2)
out=$(bank "pix.split.reverse|$alnsx|$alnl2:50.00|ALREQ1")
check "alnum.reverse.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.split.show|$alnsx")
check "alnum.reverse.remain" "yes" "$(grep -aq '^leg 02.*remain=+000000000000000.00' <<<"$out" && echo yes || echo no)"
check "alnum.reverse.paid" "+000000000000050.00" "$(value "$out" devolved=)"
out=$(bank "ledger.trial")
check "alnum.reverse.trial" "yes" "$([ "$(value "$out" total-debit=)" = "$(value "$out" total-credit=)" ] && echo yes || echo no)"

# masking convention: canonical CNPJ not leaked in key mask
out=$(bank "pix.key.lookup|CNPJ|ab1c2d3e4f5g13")
leak=$(grep -a "mask=" <<<"$out" | grep -ac "AB1C2D3E4F5G13" || true)
check "alnum.mask.no-leak" "0" "$leak"


sed -i 's/business-date=.*/business-date=2026-10-02/' etc/bank.cfg


cp "$CFG_BAK" etc/bank.cfg


# ====================================================================
# pix-split-tax-spi: official SPI Split Tax contract boundary
# (pacs.008 / pain.013 / camt.054 / pacs.002 / pain.014 semantics)
# ====================================================================
reset
bank "ledger.init" >/dev/null
out=$(bank "customer.create|J|SPI PAYER|CNPJ|33000167000101|20261007|OP01|STXA")
sxc1=$(value "$out" id=)
out=$(bank "account.open|$sxc1|DMND|BRL|500.00|OP01|STXB|SRV1")
sxa1=$(value "$out" id=)
out=$(bank "customer.create|J|SPI RECEIVER|CNPJ|12.ABC.345/01DE-35|20261007|OP01|STXC")
sxc2=$(value "$out" id=)
out=$(bank "account.open|$sxc2|DMND|BRL|0|OP01|STXD|SRV2")
sxa2=$(value "$out" id=)
out=$(bank "customer.create|J|SPI TREASURY|CNPJ|11222333000181|20261007|OP01|STXE")
sxc3=$(value "$out" id=)
out=$(bank "account.open|$sxc3|DMND|BRL|0|OP01|STXF|SRV3")
sxa3=$(value "$out" id=)
out=$(bank "account.open|$sxc3|DMND|BRL|0|OP01|STXG|SRV4")
sxa4=$(value "$out" id=)
out=$(bank "pix.rt.create|12345678|KOF PIX SERVICOS|DEBITS|DPI|Y||OP01|STXH|PRT1")
check "spi.participant" "ACTIVE" "$(value "$out" status=)"

out=$(bank "pix.spi.tax.validate|5.13|pacs.008|E12345678202610071500abcdefghijk|100.00|MANU|33000167000101|12ABC34501DE35|||1234567890|CBSSPLIT:INF:50.00:BRL;IBSSPLIT:INF:30.00:BRL")
check "spi.validate.rc" "00" "$(value "$out" rc=)"
check "spi.validate.status" "ACCEPTED" "$(value "$out" status=)"
check "spi.validate.msgnm" "pacs.008.spi.1.16" "$(value "$out" msgnm=)"
check "spi.validate.sum" "+000000000000080.00" "$(value "$out" taxsum=)"

out=$(bank "pix.spi.tax.validate|5.12|pacs.008|E12345678202610071500abcdefghik0|100.00|MANU|33000167000101|12ABC34501DE35|||1234567890|CBSSPLIT:INF:50.00:BRL;IBSSPLIT:INF:30.00:BRL")
check "spi.validate.512" "pacs.008.spi.1.15" "$(value "$out" msgnm=)"

out=$(bank "pix.spi.tax.validate|5.13|pacs.008|E12345678202610071500abcdefghik1|100.0|MANU|33000167000101|12ABC34501DE35|||1234567890|CBSSPLIT:INF:50.00:BRL;IBSSPLIT:INF:30.00:BRL")
check "spi.syntax.rc" "20" "$(value "$out" rc=)"
check "spi.syntax.flag" "Y" "$(value "$out" syntax=)"
check "spi.syntax.status" "RJCT" "$(value "$out" status=)"

out=$(bank "pix.spi.tax.validate|5.13|pacs.008|E12345678202610071500abcdefghik2|100.00|MANU|33000167000101|12ABC34501DE35|||1234567890|CBSSPLIT:INF:50.00:BRL;OTHERTAX:INF:30.00:BRL")
check "spi.tp.enum" "RR06" "$(value "$out" code=)"
out=$(bank "pix.spi.tax.validate|5.13|pacs.008|E12345678202610071500abcdefghik3|100.00|MANU|33000167000101|12ABC34501DE35|||1234567890|CBSSPLIT:INF:50.00:BRL")
check "spi.pair.required" "RR06" "$(value "$out" code=)"
out=$(bank "pix.spi.tax.validate|5.13|pacs.008|E12345678202610071500abcdefghik4|100.00|MANU|33000167000101|12ABC34501DE35|||1234567890|CBSSPLIT:COR:50.00:BRL;IBSSPLIT:INF:30.00:BRL")
check "spi.camt.cats.inf" "RR06" "$(value "$out" code=)"

out=$(bank "pix.spi.tax.validate|5.13|pacs.008|E12345678202610071500abcdefghik5|100.00|MANU|12345678901|12ABC34501DE35|||1234567890|CBSSPLIT:INF:50.00:BRL;IBSSPLIT:INF:30.00:BRL")
check "spi.pj.gate" "RR06" "$(value "$out" code=)"
out=$(bank "pix.spi.tax.validate|5.13|pacs.008|E12345678202610071500abcdefghik6|100.00|QRDN|33000167000101|12ABC34501DE35|||1234567890|CBSSPLIT:INF:50.00:BRL;IBSSPLIT:INF:30.00:BRL")
check "spi.initform.forbidden" "RR06" "$(value "$out" code=)"

out=$(bank "pix.spi.tax.validate|5.13|pacs.008|E12345678202610071500abcdefghik7|100.00|MANU|33000167000101|12ABC34501DE35|||1234567890|CBSSPLIT:INF:80.00:BRL;IBSSPLIT:INF:30.00:BRL")
check "spi.am23" "AM23" "$(value "$out" code=)"
check "spi.am23.codesrc" "SPI" "$(value "$out" codesrc=)"

IN="pix.spi.tax.ingest|5.13|pacs.008|E12345678202610071500abcdefghik8|100.00|MANU|33000167000101|12ABC34501DE35|||1234567890|CBSSPLIT:INF:50.00:BRL;IBSSPLIT:INF:30.00:BRL|$sxa1|$sxc1|$sxa2,$sxc2,,,$sxa3,$sxc3,$sxa4,$sxc3,OP01,STXREQ1"
out=$(bank "$IN")
check "spi.ingest.rc" "00" "$(value "$out" rc=)"
check "spi.ingest.status" "POSTED" "$(value "$out" status=)"
check "spi.ingest.msgnm" "pacs.008.spi.1.16" "$(value "$out" msgnm=)"
spix=$(value "$out" pix=)
check "spi.ingest.haspix" "yes" "$([ -n "$spix" ] && echo yes || echo no)"
out=$(bank "ledger.balance|$sxa1")
check "spi.ingest.payer" "400.00" "$(value "$out" ledger=)"
out=$(bank "ledger.balance|$sxa2")
check "spi.ingest.receiver" "20.00" "$(value "$out" ledger=)"
out=$(bank "ledger.balance|$sxa3")
check "spi.ingest.cbs" "50.00" "$(value "$out" ledger=)"
out=$(bank "ledger.balance|$sxa4")
check "spi.ingest.ibs" "30.00" "$(value "$out" ledger=)"
out=$(bank "pix.split.show|$spix")
check "spi.ingest.taxtotal" "yes" "$(grep -aq '^taxtotal=+000000000000080.00' <<<"$out" && echo yes || echo no)"
check "spi.ingest.role" "yes" "$(grep -aq '^leg 02: seq=02 role=TAX' <<<"$out" && echo yes || echo no)"

out=$(bank "$IN")
check "spi.replay.rc" "00" "$(value "$out" rc=)"
check "spi.replay.flag" "Y" "$(value "$out" replay=)"
check "spi.replay.pix" "$spix" "$(value "$out" pix=)"

out=$(bank "pix.spi.tax.get|E12345678202610071500abcdefghik8")
check "spi.get.rc" "00" "$(value "$out" rc=)"
check "spi.get.status" "POSTED" "$(value "$out" status=)"
check "spi.get.envtax" "yes" "$(grep -aq 'rec{CBSSPLIT,INF,BRL,50.00}; rec{IBSSPLIT,INF,BRL,30.00};' <<<"$out" && echo yes || echo no)"
check "spi.get.envref" "yes" "$(grep -aq 'ref=1234567890' <<<"$out" && echo yes || echo no)"
check "spi.get.pix" "$spix" "$(value "$out" pix=)"
out=$(bank "pix.spi.tax.list")
check "spi.list.rc" "00" "$(value "$out" rc=)"
check "spi.list.count" "001" "$(value "$out" count=)"

out=$(bank "pix.spi.tax.map|5.13|$spix|E12345678202610071500abcdefghik8|33000167000101|12ABC34501DE35")
check "spi.map.rc" "00" "$(value "$out" rc=)"
check "spi.map.sum" "+000000000000080.00" "$(value "$out" taxsum=)"
check "spi.map.env" "yes" "$(grep -aq 'amt=100.00' <<<"$out" && echo yes || echo no)"

out=$(bank "pix.spi.tax.ingest|5.13|pacs.008|E12345678202610071500abcdefghik9|100.00|MANU|33000167000101|12ABC34501DE35|||1234567890|CBSSPLIT:INF:80.00:BRL;IBSSPLIT:INF:30.00:BRL|$sxa1|$sxc1|$sxa2,$sxc2,,,$sxa3,$sxc3,$sxa4,$sxc3,OP01,STXREQ2")
check "spi.reject.rc" "20" "$(value "$out" rc=)"
check "spi.reject.code" "AM23" "$(value "$out" code=)"
check "spi.reject.status" "REJECTED" "$(value "$out" status=)"
out=$(bank "pix.spi.tax.get|E12345678202610071500abcdefghik9")
check "spi.reject.persist" "REJECTED" "$(value "$out" status=)"

out=$(bank "pix.spi.tax.ingest|5.13|pain.013|E12345678202610071500abcdefghka0|80.00||||33000167000101|||CBSSPLIT:COR:20.00:BRL;CBSSPLIT:INF:50.00:BRL;IBSSPLIT:INF:30.00:BRL")
check "spi.pain.rc" "00" "$(value "$out" rc=)"
check "spi.pain.status" "NOTIF" "$(value "$out" status=)"
check "spi.pain.sum" "+000000000000050.00" "$(value "$out" taxsum=)"
out=$(bank "pix.spi.tax.validate|5.13|pain.013|E12345678202610071500abcdefghka1|80.00||||33000167000101|||CBSSPLIT:COR:20.00:BRL;IBSSPLIT:INF:30.00:BRL")
check "spi.pain.pair" "RR06" "$(value "$out" code=)"
out=$(bank "pix.spi.tax.validate|5.13|pain.013|E12345678202610071500abcdefghka2|30.00||||33000167000101|||CBSSPLIT:COR:20.00:BRL;CBSSPLIT:INF:50.00:BRL;IBSSPLIT:INF:30.00:BRL")
check "spi.pain.am23" "AM23" "$(value "$out" code=)"

out=$(bank "pix.spi.tax.ingest|5.13|camt.054|E12345678202610071500abcdefghka3|100.00||||||REFX|CBSSPLIT:INF:50.00:BRL;IBSSPLIT:INF:30.00:BRL")
check "spi.camt.rc" "00" "$(value "$out" rc=)"
check "spi.camt.status" "NOTIF" "$(value "$out" status=)"
check "spi.camt.pix" "yes" "$([ -z "$(value "$out" pix=)" ] && echo yes || echo no)"
out=$(bank "ledger.balance|$sxa1")
check "spi.camt.nopost" "400.00" "$(value "$out" ledger=)"

out=$(bank "pix.spi.tax.response|pacs.002|5.13|E12345678202610071500abcdefghik8|ACSC")
check "spi.resp.acsc" "00" "$(value "$out" rc=)"
out=$(bank "pix.spi.tax.response|pacs.002|5.13|E12345678202610071500abcdefghik8|RJCT|RR06")
check "spi.resp.rr06" "00" "$(value "$out" rc=)"
out=$(bank "pix.spi.tax.response|pacs.002|5.13|E12345678202610071500abcdefghik8|RJCT|AM23")
check "spi.resp.am23" "00" "$(value "$out" rc=)"
out=$(bank "pix.spi.tax.response|pacs.002|5.13|E12345678202610071500abcdefghik8|RJCT|ZZ99")
check "spi.resp.domain" "20" "$(value "$out" rc=)"

out=$(bank "pix.spi.tax.response|pain.014|5.12|E12345678202610071500abcdefghik8|RJCT|RR06")
check "spi.pain014.512" "00" "$(value "$out" rc=)"
out=$(bank "pix.spi.tax.response|pain.014|5.13|E12345678202610071500abcdefghik8|RJCT|RR06")
check "spi.pain014.513" "20" "$(value "$out" rc=)"
check "spi.pain014.513.msg" "yes" "$(grep -aq 'HAS NO TAX ERROR CODE' <<<"$out" && echo yes || echo no)"

l2=$(grep -a '^leg 02' <<<"$(bank "pix.split.show|$spix")" | grep -ao 'aid=[A-Z0-9]*' | cut -d= -f2)
out=$(bank "pix.split.reverse|$spix|$l2:50.00|STXREV1")
check "spi.reverse.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.split.show|$spix")
check "spi.reverse.remain" "yes" "$(grep -aq '^leg 02.*remain=+000000000000000.00' <<<"$out" && echo yes || echo no)"
out=$(bank "ledger.trial")
check "spi.reverse.trial" "yes" "$([ "$(value "$out" total-debit=)" = "$(value "$out" total-credit=)" ] && echo yes || echo no)"

out=$(bank "pix.spi.tax.validate||pacs.008|E12345678202610071500abcdefghka4|100.00|MANU|33000167000101|12ABC34501DE35|||1234567890|CBSSPLIT:INF:50.00:BRL;IBSSPLIT:INF:30.00:BRL")
check "spi.cfg.default" "5.13" "$(value "$out" ver=)"
check "spi.cfg.msgnm" "pacs.008.spi.1.16" "$(value "$out" msgnm=)"



# ===== GATE 2: FINANCIAL INTEGRITY =====

reset
bank "ledger.init" >/dev/null
bank "customer.create|P|FIN A|CPF|11111111111|19900101|OP01|FC1" >/dev/null
bank "customer.create|P|FIN B|CPF|22222222222|19900102|OP01|FC2" >/dev/null
bank "account.open|C00000000001|DMND|BRL|100000|OP01|FC3|FA1" >/dev/null
bank "account.open|C00000000002|DMND|BRL|1000|OP01|FC4|FA2" >/dev/null
A1=A00000000001
A2=A00000000002

# ---- FINANCIAL-CONSERVATION ----
t1=$(bank "txn.create|TRANSFER|$A1|$A2|500|BRL|ftr|OP01|C1|FREQ1" | awk -F= '/^id/{print $2}')
check "fin.cons.create" "T00000000001" "$t1"
check "fin.cons.auth" "00" "$(value "$(bank "txn.authorize|$t1|OP01|C2|FREQ2")" rc=)"
out=$(bank "txn.post|$t1|OP01|C3|FREQ3")
check "fin.cons.post.rc" "00" "$(value "$out" rc=)"
out=$(bank "ledger.trial")
check "fin.cons.trial" "$(value "$out" total-debit=)" "$(value "$out" total-credit=)"
out=$(bank "ledger.journal|TXN$t1-P")
check "fin.cons.jrn.found" "0001" "$(value "$out" found=)"
check "fin.cons.jrn.decl" "0002" "$(value "$out" declared=)"
check "fin.cons.jrn.lines" "0002" "$(value "$out" lines=)"
check "fin.cons.jrn.dr" "500.00" "$(value "$out" debit=)"
check "fin.cons.jrn.cr" "500.00" "$(value "$out" credit=)"
check "fin.cons.jrn.hash" "yes" "$([ -n "$(value "$out" hash=)" ] && echo yes || echo no)"
check "fin.cons.glp" "2" "$(grep -c "|TXN$t1-P|" var/journal/postings.log)"
check "fin.cons.bal.dst" "1500.00" "$(value "$(bank "ledger.balance|$A2")" ledger=)"

# ---- FINANCIAL-IDEMPOTENCY ----
out=$(bank "txn.post|$t1|OP01|C3|FREQ3")
check "fin.idem.replay.rc" "00" "$(value "$out" rc=)"
check "fin.idem.replay.status" "PO" "$(value "$out" status=)"
check "fin.idem.jrn.once" "1" "$(grep -c "^JRN|TXN$t1-P|" var/journal/journal.log)"
check "fin.idem.glp.once" "2" "$(grep -c "|TXN$t1-P|" var/journal/postings.log)"
out=$(bank "txn.authorize|$t1|OP01|C4|FREQ1")
check "fin.idem.mismatch.rc" "26" "$(value "$out" rc=)"
check "fin.idem.mismatch.msg" "yes" "$(grep -aq 'PAYLOAD MISMATCH' <<<"$out" && echo yes || echo no)"
out=$(bank "txn.create|TRANSFER|$A1|$A2|500|BRL|ftr|OP01|C1|FREQ1")
check "fin.idem.create.replay" "$t1" "$(value "$out" id=)"

# ---- FINANCIAL-STATE-MACHINE ----
t2=$(bank "txn.create|FEE|$A1||10|BRL|st|OP01|C5|FRQ4" | awk -F= '/^id/{print $2}')
check "fin.sm.post.unauth" "20" "$(value "$(bank "txn.post|$t2|OP01|C6|FRQ5")" rc=)"
bank "txn.authorize|$t2|OP01|C7|FRQ6" >/dev/null
check "fin.sm.post" "00" "$(value "$(bank "txn.post|$t2|OP01|C8|FRQ7")" rc=)"
check "fin.sm.post.again" "20" "$(value "$(bank "txn.post|$t2|OP01|C9|FRQ8")" rc=)"
check "fin.sm.settle" "00" "$(value "$(bank "txn.settle|$t2|OP01|C10|FRQ9")" rc=)"
check "fin.sm.settle.again" "20" "$(value "$(bank "txn.settle|$t2|OP01|C11|FRQ10")" rc=)"
check "fin.sm.complete" "00" "$(value "$(bank "txn.complete|$t2|OP01|C12|FRQ11")" rc=)"
check "fin.sm.cancel.cp" "20" "$(value "$(bank "txn.cancel|$t2|OP01|C13|FRQ12")" rc=)"
t3=$(bank "txn.create|FEE|$A1||10|BRL|cn|OP01|C14|FRQ13" | awk -F= '/^id/{print $2}')
check "fin.sm.reverse.cr" "20" "$(value "$(bank "txn.reverse|$t3|OP01|C15|FRQ14")" rc=)"
check "fin.sm.cancel.cr" "00" "$(value "$(bank "txn.cancel|$t3|OP01|C16|FRQ15")" rc=)"
check "fin.sm.post.cancelled" "20" "$(value "$(bank "txn.post|$t3|OP01|C17|FRQ16")" rc=)"
check "fin.sm.settle.cancelled" "20" "$(value "$(bank "txn.settle|$t3|OP01|C18|FRQ17")" rc=)"

# ---- FINANCIAL-RESTART (crash seams + recovery) ----
t4=$(bank "txn.create|TRANSFER|$A1|$A2|700|BRL|c1|OP01|C19|FRQ18" | awk -F= '/^id/{print $2}')
bank "txn.authorize|$t4|OP01|C20|FRQ19" >/dev/null
KOF_CRASH=AFTER-JRN bank "txn.post|$t4|OP01|C21|FRQ20" >/dev/null
check "fin.rcv.status.au" "AU" "$(value "$(bank "txn.get|$t4")" status=)"
check "fin.rcv.recover" "00" "$(value "$(bank "txn.recover|$t4")" rc=)"
check "fin.rcv.status.po" "PO" "$(value "$(bank "txn.get|$t4")" status=)"
check "fin.rcv.jrn.once" "1" "$(grep -c "^JRN|TXN$t4-P|" var/journal/journal.log)"
check "fin.rcv.glp.once" "2" "$(grep -c "|TXN$t4-P|" var/journal/postings.log)"
check "fin.rcv.recover.idem" "00" "$(value "$(bank "txn.recover|$t4")" rc=)"
check "fin.rcv.trial" "$(value "$(bank "ledger.trial")" total-debit=)" "$(value "$(bank "ledger.trial")" total-credit=)"
t5=$(bank "txn.create|TRANSFER|$A1|$A2|900|BRL|c2|OP01|C22|FRQ21" | awk -F= '/^id/{print $2}')
bank "txn.authorize|$t5|OP01|C23|FRQ22" >/dev/null
KOF_CRASH=AFTER-BAL bank "txn.post|$t5|OP01|C24|FRQ23" >/dev/null
check "fin.rcv2.recover" "00" "$(value "$(bank "txn.recover|$t5")" rc=)"
check "fin.rcv2.glp" "2" "$(grep -c "|TXN$t5-P|" var/journal/postings.log)"
t6=$(bank "txn.create|TRANSFER|$A1|$A2|1100|BRL|c3|OP01|C25|FRQ24" | awk -F= '/^id/{print $2}')
bank "txn.authorize|$t6|OP01|C26|FRQ25" >/dev/null
KOF_CRASH=AFTER-PST bank "txn.post|$t6|OP01|C27|FRQ26" >/dev/null
check "fin.rcv3.recover" "00" "$(value "$(bank "txn.recover|$t6")" rc=)"
check "fin.rcv3.glp" "2" "$(grep -c "|TXN$t6-P|" var/journal/postings.log)"
t7=$(bank "txn.create|TRANSFER|$A1|$A2|1300|BRL|c4|OP01|C28|FRQ27" | awk -F= '/^id/{print $2}')
bank "txn.authorize|$t7|OP01|C29|FRQ28" >/dev/null
KOF_CRASH=AFTER-POST bank "txn.post|$t7|OP01|C30|FRQ29" >/dev/null
check "fin.rcv4.recover" "00" "$(value "$(bank "txn.recover|$t7")" rc=)"
check "fin.rcv4.status" "PO" "$(value "$(bank "txn.get|$t7")" status=)"
check "fin.rcv4.jrn.once" "1" "$(grep -c "^JRN|TXN$t7-P|" var/journal/journal.log)"
t8=$(bank "txn.create|TRANSFER|$A1|$A2|100|BRL|n1|OP01|C31|FRQ30" | awk -F= '/^id/{print $2}')
check "fin.rcv5.nodurable" "20" "$(value "$(bank "txn.recover|$t8")" rc=)"
bank "txn.authorize|$t8|OP01|C32|FRQ31" >/dev/null
check "fin.rcv5.safe.retry.post" "00" "$(value "$(bank "txn.post|$t8|OP01|C33|FRQ32")" rc=)"

# ---- FINANCIAL-CONCURRENCY ----
t9=$(bank "txn.create|TRANSFER|$A1|$A2|55|BRL|cc|OP01|C34|FRQ33" | awk -F= '/^id/{print $2}')
bank "txn.authorize|$t9|OP01|C35|FRQ34" >/dev/null
bank "txn.lock|A|TXN-$t9|MANUAL" >/dev/null
out=$(bank "txn.post|$t9|OP01|C36|FRQ35")
check "fin.con.lock.held" "24" "$(value "$out" rc=)"
check "fin.con.lock.status" "AU" "$(value "$(bank "txn.get|$t9")" status=)"
bank "txn.unlock|X|TXN-$t9|MANUAL" >/dev/null
out=$(bank "txn.post|$t9|OP01|C37|FRQ36")
check "fin.con.after.unlock" "00" "$(value "$out" rc=)"
( bank "txn.post|$t9|OP01|C38|FRQ37" > /tmp/kof.cw1 2>/dev/null & bank "txn.post|$t9|OP01|C39|FRQ37" > /tmp/kof.cw2 2>/dev/null & wait )
check "fin.con.race.jrn" "1" "$(grep -c "^JRN|TXN$t9-P|" var/journal/journal.log)"
check "fin.con.race.glp" "2" "$(grep -c "|TXN$t9-P|" var/journal/postings.log)"
check "fin.con.race.trial" "$(value "$(bank "ledger.trial")" total-debit=)" "$(value "$(bank "ledger.trial")" total-credit=)"

# ---- FINANCIAL-RECON ----
out=$(bank "reconciliation.run|JOURNAL|REC-FIN-J1")
check "fin.rec.clean.rc" "00" "$(value "$out" rc=)"
check "fin.rec.clean.balanced" "BALANCED" "$(value "$out" msg=)"
check "fin.rec.matched.pos" "yes" "$([ "$(value "$out" matched=)" -gt 0 ] && echo yes || echo no)"
cp var/journal/postings.log /tmp/kof.fin.pbak
printf 'GLP|2000|D|          12.34|A00000000009|BRL|FIN_ORPH_X|20261002\n' >> var/journal/postings.log
printf 'GLP|2000|C|          12.34|A00000000009|BRL|FIN_ORPH_X|20261002\n' >> var/journal/postings.log
out=$(bank "reconciliation.run|JOURNAL|REC-FIN-J2")
check "fin.rec.orphan.status" "EXCEPTIONS" "$(value "$out" msg=)"
out=$(bank "reconciliation.exceptions|REC-FIN-J2")
check "fin.rec.orphan.code" "1" "$(printf '%s' "$out" | grep -c 'code=LGR_ORPHAN')"
check "fin.rec.orphan.key" "1" "$(printf '%s' "$out" | grep -c 'key=FIN_ORPH_X')"
check "fin.rec.no.repair" "2" "$(grep -c '|FIN_ORPH_X|' var/journal/postings.log)"
fe=$(printf '%s' "$out" | awk '/^exc=/{id=$0} /^code=LGR_ORPHAN/{sub("exc=","",id); print id}' | head -1)
check "fin.rec.exc.id" "yes" "$([ -n "$fe" ] && echo yes || echo no)"
check "fin.rec.resolve" "00" "$(value "$(bank "reconciliation.resolve|$fe|ACCEPT||OP01|closed")" rc=)"
out=$(bank "reconciliation.exceptions|REC-FIN-J2")
check "fin.rec.resolved" "ACCEPTED" "$(value "$out" status=)"
cp /tmp/kof.fin.pbak var/journal/postings.log

# ---- FINANCIAL-EOD ----
out=$(bank "batch.eod|OP01|C40|EODF1")
check "fin.eod.report" "1" "$(grep -c 'RECON-JOURNAL' var/out/eod_20261002.txt || true)"
printf 'GLP|2000|D|          33.33|A00000000009|BRL|FIN_GHOST|20261003\n' >> var/journal/postings.log
printf 'GLP|2000|C|          33.33|A00000000009|BRL|FIN_GHOST|20261003\n' >> var/journal/postings.log
cp etc/bank.cfg /tmp/kof.fin.cfgbak
sed -i 's/business-date=.*/business-date=2026-10-03/' etc/bank.cfg
out=$(bank "batch.eod|OP01|C41|EODF2")
check "fin.eod.stop.rc" "20" "$(value "$out" rc=)"
check "fin.eod.stop.msg" "yes" "$(grep -aq 'RECONCILIATION EXCEPTIONS' <<<"$out" && echo yes || echo no)"
out=$(bank "reconciliation.exceptions|REC-JOURNAL-20261003")
for xid in $(printf '%s' "$out" | awk '/^exc=/{id=$0} /^code=LGR_ORPHAN/{sub("exc=","",id); print id}'); do
    bank "reconciliation.resolve|$xid|ACCEPT||OP01|cleared" >/dev/null
done
out=$(bank "batch.eod|OP01|C42|EODF3")
check "fin.eod.after.resolve" "00" "$(value "$out" rc=)"
grep -v '|FIN_GHOST|' var/journal/postings.log > /tmp/kof.fin.gclean
mv /tmp/kof.fin.gclean var/journal/postings.log
cp /tmp/kof.fin.cfgbak etc/bank.cfg
out=$(bank "batch.eod|OP01|C43|EODF4")
check "fin.eod.restart.idem" "00" "$(value "$out" rc=)"

# ---- FINANCIAL-AUDIT ----
check "fin.aud.header.chain" "1" "$(grep -c "^JRN|TXN$t4-P|$t4|" var/journal/journal.log)"
check "fin.aud.glp.chain" "2" "$(grep -c "|TXN$t4-P|" var/journal/postings.log)"
check "fin.aud.recover.trail" "yes" "$(grep -ac 'TXN.RECOVER' var/audit/audit.log | awk '{print ($1>0)?"yes":"no"}')"
check "fin.aud.event.posted" "yes" "$(grep -ac 'TRANSACTION.POSTED' var/journal/events.log | awk '{print ($1>0)?"yes":"no"}')"
check "fin.aud.lock.audit" "yes" "$(grep -ac 'TXN.POST' var/audit/audit.log | awk '{print ($1>0)?"yes":"no"}')"

# ---- FINANCIAL-CROSS-DOMAIN ----
out=$(bank "pix.split.show|$spix" 2>/dev/null || true)
out=$(bank "ledger.balance|$A1")
check "fin.xd.balance.projection" "yes" "$([ -n "$(value "$out" ledger=)" ] && echo yes || echo no)"
sumj=$(LC_ALL=C awk -F'|' '$1=="JRN"{s+=$11} END{printf "%.2f", s}' var/journal/journal.log)
out=$(bank "ledger.trial")
check "fin.xd.jrn.eq.trial" "$sumj" "$(value "$out" total-debit=)"
check "fin.xd.trial.bal" "$(value "$out" total-debit=)" "$(value "$out" total-credit=)"
out=$(bank "reconciliation.run|JOURNAL|REC-FIN-XD")
check "fin.xd.journal.balanced" "BALANCED" "$(value "$out" msg=)"
out=$(bank "reconciliation.run|TXN|REC-FIN-XTX")
check "fin.xd.txn.run.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.stl.recon 2>/dev/null" 2>/dev/null || true)

# ====================================================================
# gate3-production-boundary: external contracts, outbox, identity,
# certificates, signing, inbound pipeline, external reconciliation
# ====================================================================
reset
bank "ledger.init" >/dev/null
out=$(bank "customer.create|J|BND PAYER|CNPJ|33000167000101|20261007|OP01|BDNA")
bc1=$(value "$out" id=)
out=$(bank "account.open|$bc1|DMND|BRL|500.00|OP01|BDNB|BRV1")
ba1=$(value "$out" id=)
out=$(bank "customer.create|J|BND RECEIVER|CNPJ|12.ABC.345/01DE-35|20261007|OP01|BDNC")
bc2=$(value "$out" id=)
out=$(bank "account.open|$bc2|DMND|BRL|0|OP01|BDND|BRV2")
ba2=$(value "$out" id=)
out=$(bank "customer.create|J|BND TREASURY|CNPJ|11222333000181|20261007|OP01|BDNE")
bc3=$(value "$out" id=)
out=$(bank "account.open|$bc3|DMND|BRL|0|OP01|BDNF|BRV3")
ba3=$(value "$out" id=)
out=$(bank "account.open|$bc3|DMND|BRL|0|OP01|BDNG|BRV4")
ba4=$(value "$out" id=)
bank "pix.rt.create|12345678|KOF PIX SERVICOS|DEBITS|DPI|Y||OP01|BDNH|PRT1" >/dev/null

bnow=$(date +%Y%m%d%H%M%S)
bdfrom=$(date +%Y%m%d)000000
bduntil=$(date -d '+30 days' +%Y%m%d)235959
bdyesterday=$(date -d '+1 day' +%Y%m%d)000000
bdyday=$(date -d '+2 days' +%Y%m%d)235959

# ---- CERTIFICATE LIFECYCLE ----
out=$(bank "bnd.cert.register|CBAD|BND KOF|ICP-BR|SIGN|LOCAL_DOUBLE|ACTIVE|20200101000000|20200102000000")
check "bnd.cert.register.expired" "00" "$(value "$out" rc=)"
out=$(bank "bnd.cert.register|CFUT|BND KOF|ICP-BR|SIGN|LOCAL_DOUBLE|ACTIVE|$bduntil|20991231235959")
check "bnd.cert.register.future" "00" "$(value "$out" rc=)"
out=$(bank "bnd.cert.register|CACT|BND KOF|ICP-BR|SIGN|LOCAL_DOUBLE|ACTIVE|$bdfrom|$bduntil")
check "bnd.cert.register.valid" "00" "$(value "$out" rc=)"
out=$(bank "bnd.cert.register|CROT|BND KOF|ICP-BR|SIGN|LOCAL_DOUBLE|ACTIVE|$bdfrom|$bdyday")
check "bnd.cert.register.rotate-src" "00" "$(value "$out" rc=)"
out=$(bank "bnd.cert.register|CREV|BND KOF|ICP-BR|SIGN|LOCAL_DOUBLE|ACTIVE|$bdfrom|$bdyday")
check "bnd.cert.register.revoke-src" "00" "$(value "$out" rc=)"
out=$(bank "bnd.cert.register|CACT|BND KOF|ICP-BR|SIGN|LOCAL_DOUBLE|ACTIVE|$bdfrom|$bduntil")
check "bnd.cert.register.dup" "22" "$(value "$out" rc=)"
out=$(bank "bnd.cert.check|CACT")
check "bnd.cert.check.valid" "00" "$(value "$out" rc=)"
check "bnd.cert.check.valid.msg" "CERTIFICATEVALID" "$(value "$out" msg=)"
out=$(bank "bnd.cert.check|CBAD")
check "bnd.cert.check.expired" "20" "$(value "$out" rc=)"
check "bnd.cert.check.expired.msg" "CERTIFICATEEXPIRED" "$(value "$out" msg=)"
out=$(bank "bnd.cert.check|CFUT")
check "bnd.cert.check.future" "20" "$(value "$out" rc=)"
check "bnd.cert.check.future.msg" "CERTIFICATENOTYETVALID" "$(value "$out" msg=)"
out=$(bank "bnd.cert.check|CMISSING")
check "bnd.cert.check.missing" "23" "$(value "$out" rc=)"
out=$(bank "bnd.cert.rotate|CROT|CACT")
check "bnd.cert.rotate" "00" "$(value "$out" rc=)"
out=$(bank "bnd.cert.check|CROT")
check "bnd.cert.rotated.out" "20" "$(value "$out" rc=)"
out=$(bank "bnd.cert.revoke|CREV")
check "bnd.cert.revoke" "00" "$(value "$out" rc=)"
out=$(bank "bnd.cert.check|CREV")
check "bnd.cert.revoked" "20" "$(value "$out" rc=)"
check "bnd.cert.revoked.msg" "CERTIFICATEREVOKED" "$(value "$out" msg=)"

# ---- SIGNING AND VERIFICATION ----
out=$(bank "bnd.cert.sign|CACT|hello-boundary")
check "bnd.sign.rc" "00" "$(value "$out" rc=)"
bsig=$(value "$out" sig=)
check "bnd.sign.format" "SIG-CACT-" "$(printf '%.9s' "$bsig")"
out=$(bank "bnd.cert.verify|CACT|hello-boundary|$bsig")
check "bnd.verify.ok" "00" "$(value "$out" rc=)"
out=$(bank "bnd.cert.verify|CACT|hello-tampered|$bsig")
check "bnd.verify.tampered" "20" "$(value "$out" rc=)"
out=$(bank "bnd.cert.sign|CBAD|hello-boundary")
check "bnd.sign.expired" "20" "$(value "$out" rc=)"
out=$(bank "bnd.cert.sign|CREV|hello-boundary")
check "bnd.sign.revoked" "20" "$(value "$out" rc=)"
out=$(bank "bnd.cert.sign|CFUT|hello-boundary")
check "bnd.sign.notyetyvalid" "20" "$(value "$out" rc=)"

# ---- OUTBOUND INTENT LIFECYCLE ----
out=$(bank "bnd.outbox.add|OB0001|STL|SPI|STL-SUBMIT|MSGIDOB0001|E2EOB0000000000000000000000001|250.00|BRL|STLOBL0001|NONE|CACT|settlement cycle|OP01")
check "bnd.ob.add.rc" "00" "$(value "$out" rc=)"
check "bnd.ob.add.fp" "yes" "$([ -n "$(value "$out" fp=)" ] && echo yes || echo no)"
out=$(bank "bnd.outbox.add|OB0001|STL|SPI|STL-SUBMIT|MSGIDOB0001|E2EOB0000000000000000000000001|250.00|BRL|STLOBL0001|NONE|CACT|settlement cycle|OP01")
check "bnd.ob.add.dup" "22" "$(value "$out" rc=)"
out=$(bank "bnd.outbox.process|OB0001")
check "bnd.ob.process.rc" "00" "$(value "$out" rc=)"
check "bnd.ob.process.state" "ACKED" "$(value "$out" state=)"
check "bnd.ob.process.outcome" "SUBMITTED" "$(value "$out" outcome=)"
check "bnd.ob.process.class" "OK" "$(value "$out" class=)"
check "bnd.ob.process.retry" "N" "$(value "$out" retryable=)"
check "bnd.ob.process.extref" "yes" "$([ -n "$(value "$out" extref=)" ] && echo yes || echo no)"
out=$(bank "bnd.outbox.process|OB0001")
check "bnd.ob.refinal.rc" "00" "$(value "$out" rc=)"
check "bnd.ob.refinal.state" "ACKED" "$(value "$out" state=)"
out=$(bank "bnd.outbox.get|OB0001")
check "bnd.ob.get.state" "ACKED" "$(value "$out" state=)"
check "bnd.ob.audit" "yes" "$(grep -ac 'BND-PROCESS' var/audit/audit.log | awk '{print ($1>0)?"yes":"no"}')"
check "bnd.ob.event" "yes" "$(grep -ac 'BOUNDARY.OUTBOUND.ACKED.v1' var/journal/events.log | awk '{print ($1>0)?"yes":"no"}')"

out=$(bank "bnd.outbox.add|OB0002|STL|SPI|STL-SUBMIT|MSGIDOB0002|E2EOB0000000000000000000000002|50.00|BRL|STLOBL0002|REJECT||settlement cycle|OP01") >/dev/null
out=$(bank "bnd.outbox.process|OB0002")
check "bnd.ob.reject.rc" "20" "$(value "$out" rc=)"
check "bnd.ob.reject.state" "REJECTED" "$(value "$out" state=)"
check "bnd.ob.reject.class" "RJCT" "$(value "$out" class=)"

# ---- UNKNOWN OUTCOME -> QUERY CORRELATION (no blind retry) ----
out=$(bank "bnd.outbox.add|OB0003|STL|SPI|STL-SUBMIT|MSGIDOB0003|E2EOB0000000000000000000000003|100.00|BRL|STLOBL0003|UNKNOWN||settlement cycle|OP01") >/dev/null
out=$(bank "bnd.outbox.process|OB0003")
check "bnd.ob.unk.rc" "24" "$(value "$out" rc=)"
check "bnd.ob.unk.state" "UNKNOWN" "$(value "$out" state=)"
check "bnd.ob.unk.correlate" "Y" "$(value "$out" correlate=)"
check "bnd.ob.unk.retry" "N" "$(value "$out" retryable=)"
out=$(bank "bnd.outbox.query|OB0003")
check "bnd.ob.query1.rc" "24" "$(value "$out" rc=)"
check "bnd.ob.query1.state" "UNKNOWN" "$(value "$out" state=)"
out=$(bank "bnd.outbox.query|OB0003")
check "bnd.ob.query2.rc" "00" "$(value "$out" rc=)"
check "bnd.ob.query2.state" "ACKED" "$(value "$out" state=)"
check "bnd.ob.query2.outcome" "SETTLED" "$(value "$out" outcome=)"

# ---- TRANSPORT FAILURE IS RETRYABLE; CRASH SEAMS RECOVER SAFE ----
out=$(bank "bnd.outbox.add|OB0004|PAY|SPI|PAY-SUBMIT|MSGIDOB0004|E2EOB0000000000000000000000004|10.00|BRL|TXNBND0004|NONE||payment submit|OP01") >/dev/null
KOF_BND_SEAM=TP-BEFORE-SEND out=$(KOF_BND_SEAM=TP-BEFORE-SEND bank "bnd.outbox.process|OB0004")
check "bnd.ob.tperr.rc" "09" "$(value "$out" rc=)"
out=$(bank "bnd.outbox.process|OB0004")
check "bnd.ob.tperr.retry.rc" "00" "$(value "$out" rc=)"
check "bnd.ob.tperr.retry.state" "ACKED" "$(value "$out" state=)"

out=$(bank "bnd.outbox.add|OB0005|PAY|SPI|PAY-SUBMIT|MSGIDOB0005|E2EOB0000000000000000000000005|20.00|BRL|TXNBND0005|NONE||payment submit|OP01") >/dev/null
KOF_BND_SEAM=CRASH_BEFORE_SEND out=$(KOF_BND_SEAM=CRASH_BEFORE_SEND bank "bnd.outbox.process|OB0005")
check "bnd.ob.crashb.rc" "90" "$(value "$out" rc=)"
out=$(bank "bnd.outbox.get|OB0005")
check "bnd.ob.crashb.state" "PENDING" "$(value "$out" state=)"
out=$(bank "bnd.outbox.process|OB0005")
check "bnd.ob.crashb.recover" "ACKED" "$(value "$out" state=)"

out=$(bank "bnd.outbox.add|OB0006|STL|SPI|STL-SUBMIT|MSGIDOB0006|E2EOB0000000000000000000000006|30.00|BRL|STLOBL0006|NONE||settlement cycle|OP01") >/dev/null
KOF_BND_SEAM=CRASH_AFTER_SEND out=$(KOF_BND_SEAM=CRASH_AFTER_SEND bank "bnd.outbox.process|OB0006")
check "bnd.ob.crasha.rc" "90" "$(value "$out" rc=)"
check "bnd.ob.crasha.state" "SENT" "$(value "$out" state=)"
out=$(bank "bnd.outbox.process|OB0006")
check "bnd.ob.crasha.resolve" "ACKED" "$(value "$out" state=)"
check "bnd.ob.crasha.retries" "002" "$(value "$out" retries=)"

# ---- OPERATOR CORRELATION REQUIRES EXPLICIT REASON ----
out=$(bank "bnd.outbox.add|OB0007|STL|SPI|STL-SUBMIT|MSGIDOB0007|E2EOB0000000000000000000000007|40.00|BRL|STLOBL0007|UNKNOWN||settlement cycle|OP01") >/dev/null
out=$(bank "bnd.outbox.process|OB0007") >/dev/null
out=$(bank "bnd.outbox.correlate|OB0007|ACKED||OP09")
check "bnd.ob.corrr.noason.rc" "20" "$(value "$out" rc=)"
out=$(bank "bnd.outbox.correlate|OB0007|ACKED|confirmed via SPI portal|OP09")
check "bnd.ob.correlate.rc" "00" "$(value "$out" rc=)"
check "bnd.ob.correlate.state" "ACKED" "$(value "$out" state=)"

out=$(bank "bnd.outbox.reap|0")
check "bnd.ob.reap.guard" "20" "$(value "$out" rc=)"

# ---- DICT CHANNEL THROUGH TRANSPORT CONTRACT ----
out=$(bank "bnd.tp.send|DICT|KEY-REGISTER|kof.bnd.test@pix.com|E2EDICT00000000000000000000001|0|BRL|NONE")
check "bnd.dict.send.rc" "00" "$(value "$out" rc=)"
check "bnd.dict.send.outcome" "ACTIVE" "$(value "$out" outcome=)"
check "bnd.dict.send.class" "OK" "$(value "$out" class=)"
out=$(bank "bnd.tp.send|DICT|KEY-REGISTER|kof.bnd.test@pix.com|E2EDICT00000000000000000000001|0|BRL|NONE")
check "bnd.dict.dup" "22" "$(value "$out" rc=)"

# ---- INBOUND PIPELINE: SCHEMA / SECURITY / IDENTITY / CORE ----
be1="E12345678202610071500abcdefghf10"
BIN="spi.tax.ingest|5.13|pacs.008|$be1|100.00|MANU|33000167000101|12ABC34501DE35|||1234567901|CBSSPLIT:INF:50.00:BRL;IBSSPLIT:INF:30.00:BRL|$ba1|$bc1|$ba2,$bc2,,,$ba3,$bc3,$ba4,$bc3,OP01,BNDREQ1"
out=$(bank "bnd.inbound|BNDMSGID00100|||$BIN")
check "bnd.in.rc" "00" "$(value "$out" rc=)"
check "bnd.in.state" "POSTED" "$(value "$out" state=)"
check "bnd.in.outcome" "ACKED" "$(value "$out" outcome=)"
bpix=$(value "$out" pix=)
check "bnd.in.haspix" "yes" "$([ -n "$bpix" ] && echo yes || echo no)"
check "bnd.in.jrn" "yes" "$([ -n "$(value "$out" jrn=)" ] && echo yes || echo no)"
out=$(bank "ledger.balance|$ba1")
check "bnd.in.payer.ledger" "400.00" "$(value "$out" ledger=)"
out=$(bank "bnd.inbound|BNDMSGID00100|||$BIN")
check "bnd.in.replay.rc" "00" "$(value "$out" rc=)"
check "bnd.in.replay.outcome" "REPLAY" "$(value "$out" outcome=)"
check "bnd.in.replay.pix" "$bpix" "$(value "$out" pix=)"
out=$(bank "ledger.balance|$ba1")
check "bnd.in.replay.noeffect" "400.00" "$(value "$out" ledger=)"
check "bnd.in.jrncount" "2" "$(grep -c "^JRN|" var/journal/journal.log)"

be2="E12345678202610071500abcdefghf20"
BIN2="spi.tax.ingest|5.13|pacs.008|$be2|100.00|MANU|33000167000101|12ABC34501DE35|||1234567902|CBSSPLIT:INF:50.00:BRL;IBSSPLIT:INF:30.00:BRL|$ba1|$bc1|$ba2,$bc2,,,$ba3,$bc3,$ba4,$bc3,OP01,BNDREQ2"
out=$(bank "bnd.inbound|BNDMSGID00100|||$BIN2")
check "bnd.in.reuse.rc" "26" "$(value "$out" rc=)"
check "bnd.in.reuse.msg" "MESSAGEREUSEWITHDIFFERENTPAYLOAD" "$(value "$out" msg=)"

out=$(bank "bnd.inbound|BNDMSGID00101|||spi.tax.ingest|5.11|pacs.008|$be2|100.00|MANU|33000167000101|12ABC34501DE35|||1234567903|CBSSPLIT:INF:50.00:BRL;IBSSPLIT:INF:30.00:BRL|$ba1|$bc1|$ba2,$bc2,,,$ba3,$bc3,$ba4,$bc3,OP01,BNDREQ3")
check "bnd.in.ver.rc" "21" "$(value "$out" rc=)"
check "bnd.in.ver.state" "REJECTED" "$(value "$out" state=)"
out=$(bank "bnd.inbound|BNDMSGID00102|||spi.tax.ingest|5.13|pacs.999|$be2|100.00|MANU|33000167000101|12ABC34501DE35|||1234567904|CBSSPLIT:INF:50.00:BRL;IBSSPLIT:INF:30.00:BRL|$ba1|$bc1|$ba2,$bc2,,,$ba3,$bc3,$ba4,$bc3,OP01,BNDREQ4")
check "bnd.in.msgnm.rc" "21" "$(value "$out" rc=)"
KOF_BND_SEAM=MALFORMED_RESPONSE out=$(KOF_BND_SEAM=MALFORMED_RESPONSE bank "bnd.inbound|BNDMSGID00103|||$BIN2")
check "bnd.in.malformed.rc" "21" "$(value "$out" rc=)"
out=$(bank "bnd.inbound|||$BIN")
check "bnd.in.empty.msgid" "21" "$(value "$out" rc=)"

# signed inbound (canonical: msgid|e2e|gross|msgnm)
out=$(bank "bnd.cert.sign|CACT|BNDMSGID00104|$be1|100.00|pacs.008")
check "bnd.in.sign.rc" "00" "$(value "$out" rc=)"
bsig=$(value "$out" sig=)
out=$(bank "bnd.inbound|BNDMSGID00104|CACT|$bsig|$BIN")
check "bnd.in.signed.rc" "00" "$(value "$out" rc=)"
check "bnd.in.signed.state" "POSTED" "$(value "$out" state=)"
out=$(bank "bnd.inbound|BNDMSGID00105|CACT|BADSIGVALUE|$BIN2")
check "bnd.in.badsig.rc" "21" "$(value "$out" rc=)"
check "bnd.in.badsig.state" "SECURITY" "$(value "$out" state=)"
KOF_BND_SEAM=SECURITY_FAILURE out=$(KOF_BND_SEAM=SECURITY_FAILURE bank "bnd.inbound|BNDMSGID00106|CACT|$bsig|$BIN")
check "bnd.in.seamfail.rc" "21" "$(value "$out" rc=)"
out=$(bank "bnd.inbound|BNDMSGID00107|CBAD|$bsig|$BIN")
check "bnd.in.expiredcert.rc" "21" "$(value "$out" rc=)"
out=$(bank "ledger.balance|$ba1")
check "bnd.in.security.noeffect" "400.00" "$(value "$out" ledger=)"

# crash seams around response persistence
be3="E12345678202610071500abcdefghf30"
BIN3="spi.tax.ingest|5.13|pacs.008|$be3|100.00|MANU|33000167000101|12ABC34501DE35|||1234567905|CBSSPLIT:INF:50.00:BRL;IBSSPLIT:INF:30.00:BRL|$ba1|$bc1|$ba2,$bc2,,,$ba3,$bc3,$ba4,$bc3,OP01,BNDREQ5"
KOF_BND_SEAM=CRASH_BEFORE_RESPERSIST out=$(KOF_BND_SEAM=CRASH_BEFORE_RESPERSIST bank "bnd.inbound|BNDMSGID00110|||$BIN3")
check "bnd.in.crashb.rc" "90" "$(value "$out" rc=)"
out=$(bank "ledger.balance|$ba1")
check "bnd.in.crashb.noeffect" "400.00" "$(value "$out" ledger=)"
out=$(bank "bnd.inbound|BNDMSGID00110|||$BIN3")
check "bnd.in.crashb.recover" "00" "$(value "$out" rc=)"
check "bnd.in.crashb.posted" "POSTED" "$(value "$out" state=)"

be4="E12345678202610071500abcdefghf40"
BIN4="spi.tax.ingest|5.13|pacs.008|$be4|100.00|MANU|33000167000101|12ABC34501DE35|||1234567906|CBSSPLIT:INF:50.00:BRL;IBSSPLIT:INF:30.00:BRL|$ba1|$bc1|$ba2,$bc2,,,$ba3,$bc3,$ba4,$bc3,OP01,BNDREQ6"
KOF_BND_SEAM=CRASH_AFTER_RESPERSIST out=$(KOF_BND_SEAM=CRASH_AFTER_RESPERSIST bank "bnd.inbound|BNDMSGID00111|||$BIN4")
check "bnd.in.crasha.rc" "90" "$(value "$out" rc=)"
out=$(bank "bnd.inbound|BNDMSGID00111|||$BIN4")
check "bnd.in.crasha.replay" "REPLAY" "$(value "$out" outcome=)"
out=$(bank "ledger.balance|$ba1")
check "bnd.in.crasha.single.effect" "200.00" "$(value "$out" ledger=)"
check "bnd.in.registry.audit" "yes" "$(grep -ac 'BND-INBOUND' var/audit/audit.log | awk '{print ($1>0)?"yes":"no"}')"
out=$(bank "bnd.msgid.get|BNDMSGID00110")
check "bnd.in.registry.state" "POSTED" "$(value "$out" state=)"
check "bnd.in.registry.trace" "yes" "$([ -n "$(value "$out" jrn=)" ] && echo yes || echo no)"

# ---- EOD STAGE INCLUDES BOUNDARY RECONCILIATION ----
out=$(bank "batch.eod|OP01|BEOD|BREQ")
check "bnd.eod.rc" "00" "$(value "$out" rc=)"
check "bnd.eod.reconline" "1" "$(grep -c 'RECON-BOUNDARY' var/out/eod_20261002.txt || true)"

# ---- EXTERNAL RECONCILIATION ----
out=$(bank "reconciliation.run|BOUNDARY|REC-BND-OK")
check "bnd.rec.ok.rc" "00" "$(value "$out" rc=)"
check "bnd.rec.ok.status" "BALANCED" "$(value "$out" msg=)"
out=$(bank "bnd.outbox.add|OB0009|STL|SPI|STL-SUBMIT|MSGIDOB0009|E2EOB0000000000000000000000009|45.00|BRL|STLOBL0009|UNKNOWN||||OP01") >/dev/null
out=$(bank "bnd.outbox.process|OB0009") >/dev/null
out=$(bank "reconciliation.run|BOUNDARY|REC-BND-UNC")
check "bnd.rec.uncorr.rc" "00" "$(value "$out" rc=)"
check "bnd.rec.uncorr.status" "EXCEPTIONS" "$(value "$out" msg=)"
out=$(bank "reconciliation.exceptions|REC-BND-UNC")
check "bnd.rec.uncorr.code" "1" "$(printf '%s' "$out" | grep -c 'code=OUTB_UNCORR')"
out=$(bank "bnd.outbox.correlate|OB0009|REJECTED|external confirmed rejection|OP09")
check "bnd.rec.correlate.rc" "00" "$(value "$out" rc=)"
out=$(bank "reconciliation.run|BOUNDARY|REC-BND-OK2")
check "bnd.rec.ok2.status" "BALANCED" "$(value "$out" msg=)"
rm -f var/data/pxspis.idx
out=$(bank "reconciliation.run|BOUNDARY|REC-BND-NOEXT")
check "bnd.rec.noext.status" "EXCEPTIONS" "$(value "$out" msg=)"
out=$(bank "reconciliation.exceptions|REC-BND-NOEXT")
check "bnd.rec.noext.found" "yes" "$(printf '%s' "$out" | grep -aq 'code=OUTB_NOEXT' && echo yes || echo no)"
rm -f var/journal/journal.log
out=$(bank "reconciliation.run|BOUNDARY|REC-BND-NOLDG")
check "bnd.rec.noledg.status" "EXCEPTIONS" "$(value "$out" msg=)"
out=$(bank "reconciliation.exceptions|REC-BND-NOLDG")
check "bnd.rec.noledg.found" "yes" "$(printf '%s' "$out" | grep -aq 'code=MSG_NOLEDG' && echo yes || echo no)"

# ---- CONFIG DEFAULTS: EXPLICIT ENVIRONMENT ----
grep -q '^environment=LOCAL_DOUBLE' etc/pix.cfg
check "bnd.cfg.environment" "yes" "$([ $? -eq 0 ] && echo yes || echo no)"
grep -q '^security-adapter=LOCAL_DOUBLE' etc/pix.cfg
check "bnd.cfg.security" "yes" "$([ $? -eq 0 ] && echo yes || echo no)"
grep -q '^transport-adapter=LOCALDOUBLE' etc/pix.cfg
check "bnd.cfg.transport" "yes" "$([ $? -eq 0 ] && echo yes || echo no)"


# ==================================================================
# GATE 4 - OPERATIONS HARDENING
# ==================================================================

# ---- LEGACY MODE: NO LIFECYCLE FILE, BUSINESS STILL ALLOWED ----
out=$(bank "ops.inspect")
check "g4.legacy.state" "STOPPED" "$(value "$out" state=)"
check "g4.legacy.corrupt" "00000" "$(value "$out" corrupt-lines=)"
check "g4.legacy.txnp" "00000" "$(value "$out" txn-pend=)"
check "g4.legacy.jrn" "00000" "$(value "$out" jrn-stage=)"
check "g4.legacy.eodint" "00000" "$(value "$out" eod-interrupted=)"
out=$(bank "txn.create|DEPOSIT||$ba1|1000.00|BRL|G4DEP|OP99|G4LGC|G4DP1")
check "g4.legacy.business" "00" "$(value "$out" rc=)"
bank "txn.authorize|$(value "$out" id=)|OP99|G4LGC2|G4DP2" >/dev/null
bank "txn.post|$(value "$out" id=)|OP99|G4LGC3|G4DP3" >/dev/null
out=$(bank "batch.eod|OP99|G4CHK|R9")
check "g4.eodchk.rc" "00" "$(value "$out" rc=)"
out=$(bank "ops.batch.status|20261002")
check "g4.eodchk.done" "DONE" "$(value "$out" state=)"
out=$(bank "ops.inspect")
check "g4.legacy.class" "OPERATOR_REQUIRED" "$(value "$out" class=)"

# ---- LIFECYCLE: START ROUTES THROUGH RECOVERY (OPERATOR FINDINGS) ----
out=$(bank "system.status")
check "g4.status.stopped" "STOPPED" "$(value "$out" state=)"
out=$(bank "system.stop|GRACEFUL|OPS01|S1")
check "g4.stop.notrunning" "22" "$(value "$out" rc=)"
out=$(bank "ops.health")
check "g4.health.stale" "stale-state" "$(value "$out" live=)"
out=$(bank "system.start|boot-g4|OPS01|R1")
check "g4.start.rc" "00" "$(value "$out" rc=)"
check "g4.start.state" "RECOVERY_REQUIRED" "$(value "$out" state=)"
out=$(bank "system.start|again|OPS01|R2")
check "g4.start.recovery-blocked" "20" "$(value "$out" rc=)"
out=$(bank "system.recover.resume|OPS01|R12")
check "g4.resume.rc" "00" "$(value "$out" rc=)"
check "g4.resume.state" "RUNNING" "$(value "$out" state=)"
out=$(bank "system.start|dup|OPS01|R2B")
check "g4.start.dup" "22" "$(value "$out" rc=)"
out=$(bank "ops.health")
check "g4.health.live" "ok" "$(value "$out" live=)"

# ---- DRAIN: NEW WORK BLOCKED, BOUNDARY OPS CONTINUE ----
out=$(bank "system.drain|window|OPS01|R3")
check "g4.drain.rc" "00" "$(value "$out" rc=)"
check "g4.drain.state" "DRAINING" "$(value "$out" state=)"
out=$(bank "txn.create|DEPOSIT||$ba1|1.00|BRL|g4drain|OPS01|C1|FRQD")
check "g4.gate.drain.block" "20" "$(value "$out" rc=)"
out=$(bank "bnd.outbox.add|OBG4DRN|STL|SPI|STL-SUBMIT|MSGG4DRN|E2EG4DRN000000000000000000000001|45.00|BRL|STLG4DRN|UNKNOWN||||OP01")
check "g4.gate.drain.bnd" "00" "$(value "$out" rc=)"
out=$(bank "ops.config.verify")
check "g4.config.rc" "00" "$(value "$out" rc=)"

# ---- BACKUP ON DRAINED SYSTEM ----
out=$(bank "ops.backup.create|g4bk|OPS01|R5")
check "g4.backup.rc" "00" "$(value "$out" rc=)"
check "g4.backup.manifest" "yes" "$([ -f var/bkp/g4bk/manifest.txt ] && echo yes || echo no)"
out=$(bank "ops.backup.verify|g4bk")
check "g4.backup.verify" "00" "$(value "$out" rc=)"
out=$(bank "system.stop|IMMEDIATE|OPS01|R6")
check "g4.stop.rc" "00" "$(value "$out" rc=)"
check "g4.stop.state" "STOPPED" "$(value "$out" state=)"

# ---- GATING: BUSINESS BLOCKED WHILE STOPPED ----
out=$(bank "txn.create|DEPOSIT||$ba1|1.00|BRL|g4off|OPS01|C2|FRQO")
check "g4.gate.stopped.block" "20" "$(value "$out" rc=)"

# ---- CORRUPTION DETECTION BLOCKS START ----
printf 'ZZ|GARBAGE-CORRUPTION\n' >> var/journal/journal.log
out=$(bank "ops.inspect")
check "g4.inspect.corrupt" "CORRUPT" "$(value "$out" class=)"
check "g4.inspect.corruptlines" "yes" "$(grep -ac '^FINDING|CHAIN_TRUNCATED|journal' <<<"$out" | awk '{print ($1>=1)?"yes":"no"}')"
out=$(bank "system.start|boot-bad|OPS01|R7")
check "g4.start.corrupt.block" "20" "$(value "$out" rc=)"

# ---- RESTORE DRILL ----
out=$(bank "ops.restore.verify|g4bk")
check "g4.restore.verify" "00" "$(value "$out" rc=)"
out=$(bank "ops.restore.apply|g4bk|WRONG|OPS01|R8")
check "g4.restore.confirm.fail" "20" "$(value "$out" rc=)"
out=$(bank "ops.restore.apply|g4bk|CONFIRM-RESTORE|OPS01|R9")
check "g4.restore.apply" "00" "$(value "$out" rc=)"
out=$(bank "ops.inspect")
check "g4.inspect.after.restore" "OPERATOR_REQUIRED" "$(value "$out" class=)"
check "g4.inspect.after.restore.corrupt" "00000" "$(value "$out" corrupt-lines=)"
out=$(bank "system.start|restored|OPS01|R10")
check "g4.start.after.restore" "00" "$(value "$out" rc=)"
check "g4.start.after.restore.state" "RECOVERY_REQUIRED" "$(value "$out" state=)"
out=$(bank "system.recover.resume|OPS01|R13")
check "g4.resume2.rc" "00" "$(value "$out" rc=)"
check "g4.resume2.state" "RUNNING" "$(value "$out" state=)"

# ---- INTERRUPTED BATCH: FAIL, DETECT, REPAIR, RESUME ----
out=$(bank "bnd.outbox.add|OBG4UNK|STL|SPI|STL-SUBMIT|MSGG4UNK|E2EG4GHOST0000000000000000000099|11.00|BRL|STLG4UNK|UNKNOWN||||OP01")
check "g4.eod.unk.add" "00" "$(value "$out" rc=)"
out=$(bank "bnd.outbox.process|OBG4UNK")
check "g4.eod.unk.state" "UNKNOWN" "$(value "$out" state=)"
sed -i 's/^business-date=.*/business-date=2026-12-31/' etc/bank.cfg
out=$(bank "batch.eod|OP01|G4FAIL|R30")
check "g4.eod.fail.rc" "20" "$(value "$out" rc=)"
out=$(bank "ops.batch.status|20261231")
check "g4.eod.fail.state" "FAILED" "$(value "$out" state=)"
out=$(bank "ops.inspect")
check "g4.eod.interrupted" "yes" "$(grep -aq '^FINDING|EOD_INTERRUPTED|' <<<"$out" && echo yes || echo no)"
check "g4.eod.interrupted.count" "00001" "$(value "$out" eod-interrupted=)"
out=$(bank "bnd.outbox.correlate|OBG4UNK|REJECTED|external confirmed rejection|OP01")
check "g4.eod.unk.correlate" "00" "$(value "$out" rc=)"
out=$(bank "batch.eod|RESUME")
check "g4.eod.resume.rc" "00" "$(value "$out" rc=)"
out=$(bank "ops.inspect")
check "g4.eod.interrupted.gone" "00000" "$(value "$out" eod-interrupted=)"
out=$(bank "ops.batch.status|20261231")
check "g4.eod.resume.state" "DONE" "$(value "$out" state=)"
sed -i 's/^business-date=.*/business-date=2026-10-02/' etc/bank.cfg

# ---- RECOVERY FINDINGS FROM CRASH SEAM ----
out=$(bank "txn.create|DEPOSIT||$ba1|500.00|BRL|G4RD|OPS01|C2R|G4RD2")
tR1=$(value "$out" id=)
bank "txn.authorize|$tR1|OPS01|C4|FRQR2" >/dev/null
KOF_CRASH=AFTER-JRN bank "txn.post|$tR1|OPS01|C5|FRQR3" >/dev/null
out=$(bank "ops.inspect")
check "g4.inspect.txnp" "00001" "$(value "$out" txn-pend=)"
check "g4.inspect.jrnp" "00001" "$(value "$out" jrn-stage=)"
check "g4.finding.stage" "yes" "$(grep -aq "FINDING|JRN_STAGED|TXN$tR1-P" <<<"$out" && echo yes || echo no)"
out=$(bank "txn.recover|$tR1")
check "g4.recover.rc" "00" "$(value "$out" rc=)"
out=$(bank "ops.inspect")
check "g4.inspect.txnp.gone" "00000" "$(value "$out" txn-pend=)"
check "g4.inspect.jrnp.gone" "00000" "$(value "$out" jrn-stage=)"

# ---- STALE LOCKS ----
bank "txn.lock|A|TXN-$tR1|G4MAN" >/dev/null
out=$(bank "ops.locks.list")
check "g4.lock.fresh.list" "yes" "$(grep -aq 'FRESH' <<<"$out" && echo yes || echo no)"
out=$(bank "ops.locks.release|TXN-$tR1|manual override|OPS01|R13")
check "g4.lock.fresh.block" "20" "$(value "$out" rc=)"
out=$(bank "ops.locks.release|TXN-NOSUCH|ghost|OPS01|R13B")
check "g4.lock.missing" "22" "$(value "$out" rc=)"

# ---- INCIDENTS ----
out=$(bank "ops.incident.open|G4INC1|uncorrelated outbound intent|SEV2|OPS01|evidence line for gate4 incident test")
check "g4.inc.open" "00" "$(value "$out" rc=)"
out=$(bank "ops.incident.open|G4INC1|dup attempt|SEV2|OPS01|dup evidence for the very same incident key")
check "g4.inc.open.dup" "22" "$(value "$out" rc=)"
out=$(bank "ops.incident.resolve|G4INC1|skip ack|OPS01|R14")
check "g4.inc.resolve.early" "20" "$(value "$out" rc=)"
out=$(bank "ops.incident.ack|G4INC1|OPS01|R15")
check "g4.inc.ack" "00" "$(value "$out" rc=)"
check "g4.inc.ack.state" "ACK" "$(value "$out" state=)"
out=$(bank "ops.incident.resolve|G4INC1|correlated with SPI portal export|OPS01|R16")
check "g4.inc.resolve" "00" "$(value "$out" rc=)"
out=$(bank "ops.incident.resolve|G4INC1|again|OPS01|R17")
check "g4.inc.resolve.dup" "22" "$(value "$out" rc=)"

# ---- CORRELATION ----
out=$(bank "ops.correlate|$tR1")
check "g4.correlate.rc" "00" "$(value "$out" rc=)"
check "g4.correlate.txn" "yes" "$(grep -aq 'CO|TXN|' <<<"$out" && echo yes || echo no)"
out=$(bank "ops.correlate|BNDMSGID00104")
check "g4.correlate.msgid" "yes" "$(grep -aq 'CO|MSGID|' <<<"$out" && echo yes || echo no)"

# ---- CERTIFICATE EXPIRY SCAN ----
out=$(bank "bnd.cert.register|CG4OLD|KOF OPS|ICP-BR|SIGN|LOCAL_DOUBLE|ACTIVE|20200101000000|20200102000000")
check "g4.cert.exp.register" "00" "$(value "$out" rc=)"
out=$(bank "ops.cert.expiring|0")
check "g4.cert.expired.detected" "yes" "$(grep -aq 'CERT-EXPIRED CG4OLD' <<<"$out" && echo yes || echo no)"
check "g4.cert.active.clean" "yes" "$(grep -q 'CERT-EXPIRING CACT' <<<"$out" && echo no || echo yes)"

# ---- AUDIT TRAIL FOR OPERATOR ACTIONS ----
check "g4.audit.lifecycle" "yes" "$(grep -aq 'LIFE.CHANGE' var/audit/audit.log && echo yes || echo no)"
check "g4.audit.restore" "yes" "$(grep -aq 'BK.APPLY' var/audit/audit.log && echo yes || echo no)"
check "g4.audit.restore" "yes" "$(grep -aq 'BK.APPLY' var/audit/audit.log && echo yes || echo no)"
check "g4.audit.incident" "yes" "$(grep -aq 'INC.OPEN' var/audit/audit.log && echo yes || echo no)"

# ---- GATE 5: QA PROFILE AND FAIL-CLOSED ADAPTER SELECTION ----
PIX_BAK=$(mktemp)
cp etc/pix.cfg "$PIX_BAK"

# QA alias is an accepted, double-only environment.
sed -i 's/^environment=.*/environment=QA/' etc/pix.cfg
out=$(bank "ops.config.verify")
check "g5.qa.env.ok" "00" "$(value "$out" rc=)"
out=$(bank "bnd.tp.send|SPI|STL-SUBMIT|MSGG5A|E2EG5AGHOST00000000000000000000|10.00|BRL")
check "g5.qa.send.rc" "00" "$(value "$out" rc=)"
check "g5.qa.send.class" "OK" "$(value "$out" class=)"
out=$(bank "bnd.cert.sign|CACT|MSGG5A|E2EG5AGHOST00000000000000000000|10.00|pacs.008")
check "g5.qa.sign.rc" "00" "$(value "$out" rc=)"
# QA may not point at a production/uninstalled adapter.
sed -i 's/^transport-adapter=.*/transport-adapter=SPI-MQ/' etc/pix.cfg
out=$(bank "ops.config.verify")
check "g5.qa.prodtp.fail" "20" "$(value "$out" rc=)"
sed -i 's/^transport-adapter=.*/transport-adapter=LOCALDOUBLE/' etc/pix.cfg
sed -i 's/^adapter=.*/adapter=NONE/' etc/pix.cfg
out=$(bank "ops.config.verify")
check "g5.qa.adapternone.fail" "20" "$(value "$out" rc=)"
sed -i 's/^adapter=.*/adapter=FIXTURE/' etc/pix.cfg

# PRODUCTION fails closed: nothing is installed to talk to BCB.
sed -i 's/^environment=.*/environment=PRODUCTION/' etc/pix.cfg
out=$(bank "ops.config.verify")
check "g5.prod.cfg.fail" "20" "$(value "$out" rc=)"
out=$(bank "bnd.tp.send|SPI|STL-SUBMIT|MSGG5B|E2EG5BGHOST00000000000000000000|10.00|BRL")
check "g5.prod.send.blocked" "20" "$(value "$out" rc=)"
check "g5.prod.send.class" "TPERR" "$(value "$out" class=)"
out=$(bank "bnd.cert.sign|CACT|MSGG5B|E2EG5BGHOST00000000000000000000|10.00|pacs.008")
check "g5.prod.sign.blocked" "20" "$(value "$out" rc=)"
out=$(bank "bnd.cert.verify|CACT|$bsig|$be1|100.00|pacs.008")
check "g5.prod.verify.blocked" "20" "$(value "$out" rc=)"
out=$(bank "bnd.inbound|BNDG5PROD|CACT|$bsig|$BIN")
check "g5.prod.inbound.blocked" "20" "$(value "$out" rc=)"
# outbound durability: transport refusal never fakes success.
out=$(bank "bnd.outbox.add|OBG5B|STL|SPI|STL-SUBMIT|MSGG5B|E2EG5BGHOST00000000000000000000|21.00|BRL|STLG5B|PENDING||||OP01")
check "g5.prod.ob.add" "00" "$(value "$out" rc=)"
out=$(bank "bnd.outbox.process|OBG5B")
check "g5.prod.ob.state" "PENDING" "$(value "$out" state=)"
out=$(bank "bnd.outbox.get|OBG5B")
check "g5.prod.ob.durable" "PENDING" "$(value "$out" state=)"

# Unknown and blank environments fail closed everywhere.
sed -i 's/^environment=.*/environment=MYSTERY/' etc/pix.cfg
out=$(bank "ops.config.verify")
check "g5.bad.env.cfg" "20" "$(value "$out" rc=)"
out=$(bank "bnd.tp.send|SPI|STL-SUBMIT|MSGG5C|E2EG5CGHOST00000000000000000000|10.00|BRL")
check "g5.bad.env.send" "20" "$(value "$out" rc=)"
sed -i 's/^environment=.*/environment=/' etc/pix.cfg
out=$(bank "ops.config.verify")
check "g5.blank.env.cfg" "20" "$(value "$out" rc=)"
out=$(bank "bnd.tp.send|SPI|STL-SUBMIT|MSGG5D|E2EG5DGHOST00000000000000000000|10.00|BRL")
check "g5.blank.env.send" "20" "$(value "$out" rc=)"

# Restore the default QA (LOCAL_DOUBLE) profile; boundary works again.
cp "$PIX_BAK" etc/pix.cfg
out=$(bank "bnd.tp.send|SPI|STL-SUBMIT|MSGG5E|E2EG5EGHOST00000000000000000000|10.00|BRL")
check "g5.restored.send" "00" "$(value "$out" rc=)"
grep -q "^environment=LOCAL_DOUBLE" etc/pix.cfg
check "g5.restored.env" "yes" "$([ $? -eq 0 ] && echo yes || echo no)"
check "g5.pix.cfg.intact" "yes" "$(cmp -s etc/pix.cfg "$PIX_BAK" && echo yes || echo no)"
rm -f "$PIX_BAK"


# ---- TRANSFER-FUND-DIRECTION (V-TRANSFER must debit-check SOURCE) ----
reset
bank "ledger.init" >/dev/null
bank "customer.create|P|TD RICH|CPF|33333333331|19900101|OP01|TD1" >/dev/null
bank "customer.create|P|TD POOR|CPF|33333333332|19900102|OP01|TD2" >/dev/null
bank "account.open|C00000000001|DMND|BRL|100000|OP01|TD3|TDA1" >/dev/null
bank "account.open|C00000000002|DMND|BRL|100|OP01|TD4|TDA2" >/dev/null
out=$(bank "txn.create|TRANSFER|A00000000001|A00000000002|50000|BRL|TDUP|OP01|TD5|TDQ1")
check "txn.xfer.richsrc.rc" "00" "$(value "$out" rc=)"
tid=$(value "$out" id=)
check "txn.xfer.richsrc.ok" "00" "$(value "$(bank "txn.authorize|$tid|OP01|TD6|TDQ2")" rc=)"
out=$(bank "txn.create|TRANSFER|A00000000002|A00000000001|50000|BRL|TDDN|OP01|TD7|TDQ3")
check "txn.xfer.poorsrc.reject" "20" "$(value "$out" rc=)"
check "txn.xfer.poorsrc.msg" "INSUFFICIENT FUNDS" "$(sed -n "s/^msg=//p" <<<"$out" | head -1 | sed "s/ *$//")"
out=$(bank "txn.create|TRANSFER|A00000000001|A00000000001|10|BRL|TDSF|OP01|TD8|TDQ4")
check "txn.xfer.self.reject" "20" "$(value "$out" rc=)"
check "txn.xfer.self.msg" "SOURCE AND DESTINATION MUST DIFFER" "$(sed -n "s/^msg=//p" <<<"$out" | head -1 | sed "s/ *$//")"
out=$(bank "txn.create|TRANSFER|A00000000001|A00000000099|10|BRL|TDBD|OP01|TD9|TDQ5")
check "txn.xfer.baddst.reject" "20" "$(value "$out" rc=)"
out=$(bank "txn.lookup|TDQ1")
check "txn.lookup.done.rc" "C" "$(value "$out" rc=)"
check "txn.lookup.done.id" "$tid" "$(sed -n 's/^result=//p' <<<"$out" | head -1 | cut -c1-12 | tr -d ' ')"
check "txn.lookup.fail.rc" "F" "$(value "$(bank "txn.lookup|TDQ3")" rc=)"
check "txn.lookup.missing.rc" "23" "$(value "$(bank "txn.lookup|TDQ99")" rc=)"

echo "tests: $((PASS + FAIL)) passed: $PASS failed: $FAIL"
[ "$FAIL" -eq 0 ]
