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
    rm -rf var/data var/journal var/audit
    mkdir -p var/data var/journal var/audit
}

reset

bank "ledger.init" >/dev/null
out=$(bank "customer.create|P|MARIA SOUZA|CPF|98765432100|19900202|OP01|R1")
check "customer.create" "C00000000001" "$(value "$out" id=)"

out=$(bank "account.open|C00000000001|DMND|BRL|500000|OP01|R2|O1")
check "account.open" "A00000000001" "$(value "$out" id=)"

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
cp /tmp/kofbank.postings.bak var/journal/postings.log

out=$(bank "batch.eod|OP01|R15|EOD1")
check "payment.eod" "00" "$(value "$out" rc=)"
check "recon.eod.report" "1" "$(grep -c 'RECON-LEDGER' var/out/eod_20261002.txt || true)"

printf 'GLP|2000|D|          99.00|A00000000007|BRL|GHOSTEOD|20261002\n' >> var/journal/postings.log
printf 'GLP|2000|C|          99.00|A00000000007|BRL|GHOSTEOD|20261002\n' >> var/journal/postings.log
cp etc/bank.cfg "$CFG_BAK"
sed -i 's/business-date=.*/business-date=2026-10-03/' etc/bank.cfg
out=$(bank "batch.eod|OP01|R99|EOD9")
check "recon.eod.fails.open" "20" "$(value "$out" rc=)"

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
check "pix.stl.finalize.incomplete.msg" "CYCLE NOT READY" "$(value "$out" msg=)"
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
out=$(bank "pix.stl.adjust|S00000000003|10.00|tarifa de liquidez|OP01|COR|SAJ1")
check "pix.stl.adjust.rc" "00" "$(value "$out" rc=)"
check "pix.stl.adjust.amount" "10.00" "$(value "$out" adjust=)"
check "pix.stl.adjust.net" "190.00" "$(value "$out" net=)"
out=$(bank "pix.stl.adjust|S00000000003|10.00|duplicado|OP01|COR|SAJ1")
check "pix.stl.adjust.idempotent" "22" "$(value "$out" rc=)"
out=$(bank "pix.cycle.close|$cycb|||||OP01|COR|SC3")
check "pix.stl.b.close" "CLOSED" "$(value "$out" status=)"
out=$(bank "pix.cycle.calc|$cycb|||||OP01|COR|SC4")
check "pix.stl.b.calc.net" "130.00" "$(value "$out" net=)"
check "pix.stl.b.calc.grosspay" "190.00" "$(value "$out" grosspay=)"
out=$(bank "pix.cycle.submit|$cycb||||||OP01|COR|SS2")
check "pix.stl.b.submit" "SUBMITTED" "$(value "$out" status=)"
out=$(bank "pix.stl.result|S00000000003||SETTLED|SPIRES-3|valor menor|180.00|OP01|COR|SR3")
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
out=$(bank "pix.stl.get|S00000000003")
check "pix.stl.b.obligation.recon" "EXCEPTION" "$(value "$out" recon=)"
out=$(bank "pix.cycle.finalize|$cycb|||||OP01|COR|SF2")
check "pix.stl.b.finalize.blocked" "20" "$(value "$out" rc=)"
out=$(bank "pix.stl.get|S00000000004")
check "pix.stl.b.stale.status" "SUBMITTED" "$(value "$out" status=)"
out=$(bank "ledger.balance|$stlpayer")
check "pix.stl.b.balance.unchanged" "$stlpaybal0" "$(value "$out" available=)"
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
check "pix.stl.eod.finalized" "SETTLED" "$(value "$out" status=)"
check "pix.stl.eod.recon" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.stl.list|$cycd")
check "pix.stl.eod.obligations" "0000002" "$(value "$out" settlements=)"
check "pix.stl.eod.reconciled" "2" "$(grep -c "status=RECONCILED" <<<"$out")"
check "pix.stl.eod.posted" "2" "$(grep -c "post=POSTED" <<<"$out")"
out=$(bank "pix.stl.get|S00000000005")
check "pix.stl.eod.journal" "Y" "$(test -n "$(value "$out" journal=)" && echo Y || echo N)"
out=$(bank "ledger.balance|$stlpayer")
check "pix.stl.eod.customer.untouched" "$eodpay0" "$(value "$out" available=)"
out=$(bank "ledger.trial")
check "pix.stl.eod.trial" "BALANCED" "$(value "$out" msg=)"
out=$(bank "batch.eod")
check "pix.stl.eod.rerun.rc" "00" "$(value "$out" rc=)"
glstl2=$(grep -c "|STLS" var/journal/postings.log)
check "pix.stl.eod.rerun.no.double" "12" "$glstl2"
out=$(bank "ledger.trial")
check "pix.stl.eod.rerun.trial" "BALANCED" "$(value "$out" msg=)"
out=$(bank "pix.pos.list")
check "pix.stl.pos.settledpay.total" "420.00" "$(value "$out" settledpay=)"
check "pix.stl.pos.settledrcv.total" "270.00" "$(value "$out" settledrcv=)"
check "pix.stl.pos.pending" "0000001" "$(value "$out" pending=)"

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

sed -i 's/business-date=.*/business-date=2026-10-02/' etc/bank.cfg
reset
bank "ledger.init" >/dev/null
out=$(bank "pix.rt.create|12345678|KOF SELF|DEBITS|DPI|Y||OP01|COR|SRT1")
check "pix.stl.rt.self" "ACTIVE" "$(value "$out" status=)"
out=$(bank "pix.rt.create|87654321|BANCO OUTRO|DEBITS|DPI|N||OP01|COR|SRT2")
stlrt=$(value "$out" id=)
out=$(bank "customer.create|P|STL PAGADOR|CPF|123.456.789-09|19900101|OP01|SC1")
out=$(bank "account.open|$(value "$out" id=)|DMND|BRL|500000|OP01|SC2|O1")
stlpayer=$(value "$out" id=)
out=$(bank "customer.create|P|STL RECEBEDOR|CPF|234.567.890-92|19900101|OP01|SC3")
stlrecvc=$(value "$out" id=)
out=$(bank "account.open|$stlrecvc|DMND|BRL|500000|OP01|SC4|O2")
stlpayee=$(value "$out" id=)
out=$(bank "pix.key.register|CPF|234.567.890-92|$stlpayee|$stlrecvc|OP01|COR|SK1")
stlkey=$(value "$out" id=)
out=$(bank "pix.key.seed|CPF|13579111140|$stlrt|FX000000001|FXC0000001|OUT CLIENTE|OP01|COR|SK2")
check "pix.stl.seed" "00" "$(value "$out" rc=)"
stlforeign=$(value "$out" keyid=)

out=$(bank "pix.out.key|$stlkey|100.00|$stlpayer|||pix local|OP01|COR|SK3||Y")
check "pix.stl.local.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|150.00|$stlpayer|||pix externo|OP01|COR|SK4||Y")
stlout=$(value "$out" id=)
check "pix.stl.out.posted" "POSTED" "$(value "$out" status=)"
check "pix.stl.out.settle.pending" "PENDING" "$(value "$out" settle=)"
out=$(bank "pix.in|50.00|$stlpayee|$stlrt|E2ESTL000000000000000000001|EXT-STL-1|PAGADOR EXTERNO|OP01|COR|SK5")
stlin=$(value "$out" id=)
check "pix.stl.in.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|70.00|$stlpayer|||a devolver|OP01|COR|SK6||Y")
stldvl=$(value "$out" id=)
out=$(bank "pix.devol|$stldvl|70.00|estorno integral|OP01|COR|SK7")
check "pix.stl.devol.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.get|$stldvl")
check "pix.stl.devol.status" "DEVOLVED" "$(value "$out" status=)"

out=$(bank "pix.cycle.open|20261002|BRL|OP01|COR|SK8")
check "pix.stl.cycle.open" "00" "$(value "$out" rc=)"
check "pix.stl.cycle.status" "OPEN" "$(value "$out" status=)"
cyc=$(value "$out" cycle=)
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|SK9")
check "pix.stl.accrue.rc" "00" "$(value "$out" rc=)"
check "pix.stl.accrue.cycle" "$cyc" "$(value "$out" cycle=)"
out=$(bank "pix.get|$stlout")
check "pix.stl.out.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.get|$stlin")
check "pix.stl.in.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.get|$stldvl")
check "pix.stl.devol.excluded" "NOT-APPLICABLE" "$(value "$out" settle=)"
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|SK9")
check "pix.stl.accrue.replay" "00" "$(value "$out" rc=)"

out=$(bank "pix.cycle.close|$cyc|OP01|COR|SKA")
check "pix.stl.close" "CLOSED" "$(value "$out" status=)"
out=$(bank "pix.cycle.calc|$cyc|OP01|COR|SKB")
check "pix.stl.calc" "CALCULATED" "$(value "$out" status=)"
check "pix.stl.calc.txns" "0000003" "$(value "$out" txns=)"
check "pix.stl.calc.grosspay" "150.00" "$(value "$out" grosspay=)"
check "pix.stl.calc.grossrcv" "120.00" "$(value "$out" grossrcv=)"
check "pix.stl.calc.net" "30.00" "$(value "$out" net=)"
check "pix.stl.calc.side" "PAYABLE" "$(value "$out" side=)"
check "pix.stl.calc.parties" "0000001" "$(value "$out" parties=)"

out=$(bank "pix.cycle.submit|$cyc||OP01|COR|SKC")
check "pix.stl.cycle.submit" "SUBMITTED" "$(value "$out" status=)"
out=$(bank "pix.stl.list|$cyc")
check "pix.stl.submit.count" "0000002" "$(value "$out" settlements=)"
check "pix.stl.submit.status" "SUBMITTED" "$(grep -c 'status=SUBMITTED' <<<"$out" | tr -d ' ')"
stl1=$(grep -F "side=PAYABLE" -B2 <<<"$out" | grep -F "settlement=" | head -1 | sed 's/^settlement=//;s/[[:space:]]*$//')
stl2=$(bank "pix.stl.list|$cyc" | grep -F "settlement=" | tail -1 | sed 's/^settlement=//;s/[[:space:]]*$//')
out=$(bank "pix.stl.get|$stl1")
check "pix.stl.get.participant" "$stlrt" "$(value "$out" participant=)"
check "pix.stl.get.extref" "SPIS-00000000001" "$(value "$out" extref=)"
out=$(bank "pix.cycle.submit|$cyc||OP01|COR|SKC")
check "pix.stl.submit.replay.attempts" "0001" "$(bank "pix.stl.get|$stl1" | grep -F "attempts=" | sed 's/^attempts=//;s/[[:space:]]*$//')"

out=$(bank "pix.stl.result|$stl1||SETTLED|SPIRES-1|valor divergente|140.00|OP01|COR|SKD")
check "pix.stl.result.mismatch.rc" "00" "$(value "$out" rc=)"
check "pix.stl.result.mismatch.settled" "140.00" "$(value "$out" settledamt=)"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-BAD||OP01|COR|SKE")
check "pix.stl.recon.bad.rc" "00" "$(value "$out" rc=)"
check "pix.stl.recon.bad.status" "EXCEPTIONS" "$(value "$out" msg=)"
check "pix.stl.recon.bad.open" "000000002" "$(value "$out" openexc=)"
out=$(bank "reconciliation.exceptions|REC-STL-BAD")
case "$out" in
    *AMT_MISMATCH*) stm=yes ;;
    *) stm=no ;;
esac
check "pix.stl.recon.amount.mismatch.code" "yes" "$stm"
case "$out" in
    *STALE_SETTLE*) sts=yes ;;
    *) sts=no ;;
esac
check "pix.stl.recon.stale.code" "yes" "$sts"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|SKF")
check "pix.stl.recon.cycle.exc" "RECON-EXCEPTION" "$(value "$out" status=)"

out=$(bank "pix.stl.result|$stl1||SETTLED|SPIRES-1B|valor correto|150.00|OP01|COR|SKG")
check "pix.stl.result.fixed" "SETTLED" "$(value "$out" status=)"
check "pix.stl.result.fixed.amount" "150.00" "$(value "$out" settledamt=)"
out=$(bank "pix.stl.result|$stl2||SETTLED|SPIRES-2|ok|50.00|OP01|COR|SKH")
check "pix.stl.result.in" "SETTLED" "$(value "$out" status=)"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|SKI")
check "pix.stl.finalize" "SETTLED" "$(value "$out" status=)"
check "pix.stl.finalize.post" "BALANCED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|$stl1|OP01|COR|SKJ")
check "pix.stl.post.pay.rc" "00" "$(value "$out" rc=)"
check "pix.stl.post.pay.status" "POSTED" "$(value "$out" post=)"
stl1jrnl=$(value "$out" journal=)
case "$stl1jrnl" in
    STL*) jok=yes ;;
    *) jok=no ;;
esac
check "pix.stl.post.journal" "yes" "$jok"
out=$(bank "pix.stl.post|$stl2|OP01|COR|SKK")
check "pix.stl.post.rcv" "POSTED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|$stl1|OP01|COR|SKJ")
check "pix.stl.post.replay" "Y" "$(value "$out" replay=)"
out=$(bank "ledger.balance|$stlpayer")
check "pix.stl.customer.untouched.payer" "489950.00" "$(value "$out" available=)"
out=$(bank "ledger.balance|$stlpayee")
check "pix.stl.customer.untouched.payee" "500230.00" "$(value "$out" available=)"
grep -aq "|D|             150.00|${stlrt}|BRL|STL" var/journal/postings.log && paygl=yes || paygl=no
check "pix.stl.gl.payable.debit" "yes" "$paygl"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-OK||OP01|COR|SKL")
check "pix.stl.recon.ok" "BALANCED" "$(value "$out" msg=)"
check "pix.stl.recon.ok.matched" "000000002" "$(value "$out" matched=)"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|SKM")
check "pix.stl.cycle.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.cycle.recon" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.stl.get|$stl1")
check "pix.stl.obligation.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.obligation.matched" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.pos.list")
check "pix.stl.position.count" "0000001" "$(value "$out" positions=)"
check "pix.stl.position.settledpay" "150.00" "$(value "$out" settledpay=)"
check "pix.stl.position.settledrcv" "50.00" "$(value "$out" settledrcv=)"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|SKN")
check "pix.stl.finalize.replay" "Y" "$(value "$out" replay=)"

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

sed -i 's/business-date=.*/business-date=2026-10-02/' etc/bank.cfg
reset
bank "ledger.init" >/dev/null
out=$(bank "pix.rt.create|12345678|KOF SELF|DEBITS|DPI|Y||OP01|COR|SRT1")
check "pix.stl.rt.self" "ACTIVE" "$(value "$out" status=)"
out=$(bank "pix.rt.create|87654321|BANCO OUTRO|DEBITS|DPI|N||OP01|COR|SRT2")
stlrt=$(value "$out" id=)
out=$(bank "customer.create|P|STL PAGADOR|CPF|123.456.789-09|19900101|OP01|SC1")
out=$(bank "account.open|$(value "$out" id=)|DMND|BRL|500000|OP01|SC2|O1")
stlpayer=$(value "$out" id=)
out=$(bank "customer.create|P|STL RECEBEDOR|CPF|234.567.890-92|19900101|OP01|SC3")
stlrecvc=$(value "$out" id=)
out=$(bank "account.open|$stlrecvc|DMND|BRL|500000|OP01|SC4|O2")
stlpayee=$(value "$out" id=)
out=$(bank "pix.key.register|CPF|234.567.890-92|$stlpayee|$stlrecvc|OP01|COR|SK1")
stlkey=$(value "$out" id=)
out=$(bank "pix.key.seed|CPF|13579111140|$stlrt|FX000000001|FXC0000001|OUT CLIENTE|OP01|COR|SK2")
check "pix.stl.seed" "00" "$(value "$out" rc=)"
stlforeign=$(value "$out" keyid=)

out=$(bank "pix.out.key|$stlkey|100.00|$stlpayer|||pix local|OP01|COR|SK3||Y")
check "pix.stl.local.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|150.00|$stlpayer|||pix externo|OP01|COR|SK4||Y")
stlout=$(value "$out" id=)
check "pix.stl.out.posted" "POSTED" "$(value "$out" status=)"
check "pix.stl.out.settle.pending" "PENDING" "$(value "$out" settle=)"
out=$(bank "pix.in|50.00|$stlpayee|$stlrt|E2ESTL000000000000000000001|EXT-STL-1|PAGADOR EXTERNO|OP01|COR|SK5")
stlin=$(value "$out" id=)
check "pix.stl.in.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|70.00|$stlpayer|||a devolver|OP01|COR|SK6||Y")
stldvl=$(value "$out" id=)
out=$(bank "pix.devol|$stldvl|70.00|estorno integral|OP01|COR|SK7")
check "pix.stl.devol.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.get|$stldvl")
check "pix.stl.devol.status" "DEVOLVED" "$(value "$out" status=)"

out=$(bank "pix.cycle.open|20261002|BRL|OP01|COR|SK8")
check "pix.stl.cycle.open" "00" "$(value "$out" rc=)"
check "pix.stl.cycle.status" "OPEN" "$(value "$out" status=)"
cyc=$(value "$out" cycle=)
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|SK9")
check "pix.stl.accrue.rc" "00" "$(value "$out" rc=)"
check "pix.stl.accrue.cycle" "$cyc" "$(value "$out" cycle=)"
out=$(bank "pix.get|$stlout")
check "pix.stl.out.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.get|$stlin")
check "pix.stl.in.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.get|$stldvl")
check "pix.stl.devol.excluded" "NOT-APPLICABLE" "$(value "$out" settle=)"
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|SK9")
check "pix.stl.accrue.replay" "00" "$(value "$out" rc=)"

out=$(bank "pix.cycle.close|$cyc|OP01|COR|SKA")
check "pix.stl.close" "CLOSED" "$(value "$out" status=)"
out=$(bank "pix.cycle.calc|$cyc|OP01|COR|SKB")
check "pix.stl.calc" "CALCULATED" "$(value "$out" status=)"
check "pix.stl.calc.txns" "0000003" "$(value "$out" txns=)"
check "pix.stl.calc.grosspay" "150.00" "$(value "$out" grosspay=)"
check "pix.stl.calc.grossrcv" "120.00" "$(value "$out" grossrcv=)"
check "pix.stl.calc.net" "30.00" "$(value "$out" net=)"
check "pix.stl.calc.side" "PAYABLE" "$(value "$out" side=)"
check "pix.stl.calc.parties" "0000001" "$(value "$out" parties=)"

out=$(bank "pix.cycle.submit|$cyc||OP01|COR|SKC")
check "pix.stl.cycle.submit" "SUBMITTED" "$(value "$out" status=)"
out=$(bank "pix.stl.list|$cyc")
check "pix.stl.submit.count" "0000002" "$(value "$out" settlements=)"
check "pix.stl.submit.status" "SUBMITTED" "$(grep -c 'status=SUBMITTED' <<<"$out" | tr -d ' ')"
stl1=$(grep -F "side=PAYABLE" -B2 <<<"$out" | grep -F "settlement=" | head -1 | sed 's/^settlement=//;s/[[:space:]]*$//')
stl2=$(bank "pix.stl.list|$cyc" | grep -F "settlement=" | tail -1 | sed 's/^settlement=//;s/[[:space:]]*$//')
out=$(bank "pix.stl.get|$stl1")
check "pix.stl.get.participant" "$stlrt" "$(value "$out" participant=)"
check "pix.stl.get.extref" "SPIS-00000000001" "$(value "$out" extref=)"
out=$(bank "pix.cycle.submit|$cyc||OP01|COR|SKC")
check "pix.stl.submit.replay.attempts" "0001" "$(bank "pix.stl.get|$stl1" | grep -F "attempts=" | sed 's/^attempts=//;s/[[:space:]]*$//')"

out=$(bank "pix.stl.result|$stl1||SETTLED|SPIRES-1|valor divergente|140.00|OP01|COR|SKD")
check "pix.stl.result.mismatch.rc" "00" "$(value "$out" rc=)"
check "pix.stl.result.mismatch.settled" "140.00" "$(value "$out" settledamt=)"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-BAD||OP01|COR|SKE")
check "pix.stl.recon.bad.rc" "00" "$(value "$out" rc=)"
check "pix.stl.recon.bad.status" "EXCEPTIONS" "$(value "$out" msg=)"
check "pix.stl.recon.bad.open" "000000002" "$(value "$out" openexc=)"
out=$(bank "reconciliation.exceptions|REC-STL-BAD")
case "$out" in
    *AMT_MISMATCH*) stm=yes ;;
    *) stm=no ;;
esac
check "pix.stl.recon.amount.mismatch.code" "yes" "$stm"
case "$out" in
    *STALE_SETTLE*) sts=yes ;;
    *) sts=no ;;
esac
check "pix.stl.recon.stale.code" "yes" "$sts"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|SKF")
check "pix.stl.recon.cycle.exc" "RECON-EXCEPTION" "$(value "$out" status=)"

out=$(bank "pix.stl.result|$stl1||SETTLED|SPIRES-1B|valor correto|150.00|OP01|COR|SKG")
check "pix.stl.result.fixed" "SETTLED" "$(value "$out" status=)"
check "pix.stl.result.fixed.amount" "150.00" "$(value "$out" settledamt=)"
out=$(bank "pix.stl.result|$stl2||SETTLED|SPIRES-2|ok|50.00|OP01|COR|SKH")
check "pix.stl.result.in" "SETTLED" "$(value "$out" status=)"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|SKI")
check "pix.stl.finalize" "SETTLED" "$(value "$out" status=)"
check "pix.stl.finalize.post" "BALANCED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|$stl1|OP01|COR|SKJ")
check "pix.stl.post.pay.rc" "00" "$(value "$out" rc=)"
check "pix.stl.post.pay.status" "POSTED" "$(value "$out" post=)"
stl1jrnl=$(value "$out" journal=)
case "$stl1jrnl" in
    STL*) jok=yes ;;
    *) jok=no ;;
esac
check "pix.stl.post.journal" "yes" "$jok"
out=$(bank "pix.stl.post|$stl2|OP01|COR|SKK")
check "pix.stl.post.rcv" "POSTED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|$stl1|OP01|COR|SKJ")
check "pix.stl.post.replay" "Y" "$(value "$out" replay=)"
out=$(bank "ledger.balance|$stlpayer")
check "pix.stl.customer.untouched.payer" "489950.00" "$(value "$out" available=)"
out=$(bank "ledger.balance|$stlpayee")
check "pix.stl.customer.untouched.payee" "500230.00" "$(value "$out" available=)"
grep -aq "|D|             150.00|${stlrt}|BRL|STL" var/journal/postings.log && paygl=yes || paygl=no
check "pix.stl.gl.payable.debit" "yes" "$paygl"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-OK||OP01|COR|SKL")
check "pix.stl.recon.ok" "BALANCED" "$(value "$out" msg=)"
check "pix.stl.recon.ok.matched" "000000002" "$(value "$out" matched=)"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|SKM")
check "pix.stl.cycle.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.cycle.recon" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.stl.get|$stl1")
check "pix.stl.obligation.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.obligation.matched" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.pos.list")
check "pix.stl.position.count" "0000001" "$(value "$out" positions=)"
check "pix.stl.position.settledpay" "150.00" "$(value "$out" settledpay=)"
check "pix.stl.position.settledrcv" "50.00" "$(value "$out" settledrcv=)"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|SKN")
check "pix.stl.finalize.replay" "Y" "$(value "$out" replay=)"

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


sed -i 's/business-date=.*/business-date=2026-10-02/' etc/bank.cfg
reset
bank "ledger.init" >/dev/null
out=$(bank "pix.rt.create|12345678|KOF SELF|DEBITS|DPI|Y||OP01|COR|SRT1")
check "pix.stl.rt.self" "ACTIVE" "$(value "$out" status=)"
out=$(bank "pix.rt.create|87654321|BANCO OUTRO|DEBITS|DPI|N||OP01|COR|SRT2")
stlrt=$(value "$out" id=)
out=$(bank "customer.create|P|STL PAGADOR|CPF|123.456.789-09|19900101|OP01|SC1")
out=$(bank "account.open|$(value "$out" id=)|DMND|BRL|500000|OP01|SC2|O1")
stlpayer=$(value "$out" id=)
out=$(bank "customer.create|P|STL RECEBEDOR|CPF|234.567.890-92|19900101|OP01|SC3")
stlrecvc=$(value "$out" id=)
out=$(bank "account.open|$stlrecvc|DMND|BRL|500000|OP01|SC4|O2")
stlpayee=$(value "$out" id=)
out=$(bank "pix.key.register|CPF|234.567.890-92|$stlpayee|$stlrecvc|OP01|COR|SK1")
stlkey=$(value "$out" id=)
out=$(bank "pix.key.seed|CPF|13579111140|$stlrt|FX000000001|FXC0000001|OUT CLIENTE|OP01|COR|SK2")
check "pix.stl.seed" "00" "$(value "$out" rc=)"
stlforeign=$(value "$out" keyid=)

out=$(bank "pix.out.key|$stlkey|100.00|$stlpayer|||pix local|OP01|COR|SK3||Y")
check "pix.stl.local.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|150.00|$stlpayer|||pix externo|OP01|COR|SK4||Y")
stlout=$(value "$out" id=)
check "pix.stl.out.posted" "POSTED" "$(value "$out" status=)"
check "pix.stl.out.settle.pending" "PENDING" "$(value "$out" settle=)"
out=$(bank "pix.in|50.00|$stlpayee|$stlrt|E2ESTL000000000000000000001|EXT-STL-1|PAGADOR EXTERNO|OP01|COR|SK5")
stlin=$(value "$out" id=)
check "pix.stl.in.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|70.00|$stlpayer|||a devolver|OP01|COR|SK6||Y")
stldvl=$(value "$out" id=)
out=$(bank "pix.devol|$stldvl|70.00|estorno integral|OP01|COR|SK7")
check "pix.stl.devol.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.get|$stldvl")
check "pix.stl.devol.status" "DEVOLVED" "$(value "$out" status=)"

out=$(bank "pix.cycle.open|20261002|BRL|OP01|COR|SK8")
check "pix.stl.cycle.open" "00" "$(value "$out" rc=)"
check "pix.stl.cycle.status" "OPEN" "$(value "$out" status=)"
cyc=$(value "$out" cycle=)
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|SK9")
check "pix.stl.accrue.rc" "00" "$(value "$out" rc=)"
check "pix.stl.accrue.cycle" "$cyc" "$(value "$out" cycle=)"
out=$(bank "pix.get|$stlout")
check "pix.stl.out.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.get|$stlin")
check "pix.stl.in.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.get|$stldvl")
check "pix.stl.devol.excluded" "NOT-APPLICABLE" "$(value "$out" settle=)"
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|SK9")
check "pix.stl.accrue.replay" "00" "$(value "$out" rc=)"

out=$(bank "pix.cycle.close|$cyc|OP01|COR|SKA")
check "pix.stl.close" "CLOSED" "$(value "$out" status=)"
out=$(bank "pix.cycle.calc|$cyc|OP01|COR|SKB")
check "pix.stl.calc" "CALCULATED" "$(value "$out" status=)"
check "pix.stl.calc.txns" "0000003" "$(value "$out" txns=)"
check "pix.stl.calc.grosspay" "150.00" "$(value "$out" grosspay=)"
check "pix.stl.calc.grossrcv" "120.00" "$(value "$out" grossrcv=)"
check "pix.stl.calc.net" "30.00" "$(value "$out" net=)"
check "pix.stl.calc.side" "PAYABLE" "$(value "$out" side=)"
check "pix.stl.calc.parties" "0000001" "$(value "$out" parties=)"

out=$(bank "pix.cycle.submit|$cyc||OP01|COR|SKC")
check "pix.stl.cycle.submit" "SUBMITTED" "$(value "$out" status=)"
out=$(bank "pix.stl.list|$cyc")
check "pix.stl.submit.count" "0000002" "$(value "$out" settlements=)"
check "pix.stl.submit.status" "SUBMITTED" "$(grep -c 'status=SUBMITTED' <<<"$out" | tr -d ' ')"
stl1=$(grep -F "side=PAYABLE" -B2 <<<"$out" | grep -F "settlement=" | head -1 | sed 's/^settlement=//;s/[[:space:]]*$//')
stl2=$(bank "pix.stl.list|$cyc" | grep -F "settlement=" | tail -1 | sed 's/^settlement=//;s/[[:space:]]*$//')
out=$(bank "pix.stl.get|$stl1")
check "pix.stl.get.participant" "$stlrt" "$(value "$out" participant=)"
check "pix.stl.get.extref" "SPIS-00000000001" "$(value "$out" extref=)"
out=$(bank "pix.cycle.submit|$cyc||OP01|COR|SKC")
check "pix.stl.submit.replay.attempts" "0001" "$(bank "pix.stl.get|$stl1" | grep -F "attempts=" | sed 's/^attempts=//;s/[[:space:]]*$//')"

out=$(bank "pix.stl.result|$stl1||SETTLED|SPIRES-1|valor divergente|140.00|OP01|COR|SKD")
check "pix.stl.result.mismatch.rc" "00" "$(value "$out" rc=)"
check "pix.stl.result.mismatch.settled" "140.00" "$(value "$out" settledamt=)"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-BAD||OP01|COR|SKE")
check "pix.stl.recon.bad.rc" "00" "$(value "$out" rc=)"
check "pix.stl.recon.bad.status" "EXCEPTIONS" "$(value "$out" msg=)"
check "pix.stl.recon.bad.open" "000000002" "$(value "$out" openexc=)"
out=$(bank "reconciliation.exceptions|REC-STL-BAD")
case "$out" in
    *AMT_MISMATCH*) stm=yes ;;
    *) stm=no ;;
esac
check "pix.stl.recon.amount.mismatch.code" "yes" "$stm"
case "$out" in
    *STALE_SETTLE*) sts=yes ;;
    *) sts=no ;;
esac
check "pix.stl.recon.stale.code" "yes" "$sts"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|SKF")
check "pix.stl.recon.cycle.exc" "RECON-EXCEPTION" "$(value "$out" status=)"

out=$(bank "pix.stl.result|$stl1||SETTLED|SPIRES-1B|valor correto|150.00|OP01|COR|SKG")
check "pix.stl.result.fixed" "SETTLED" "$(value "$out" status=)"
check "pix.stl.result.fixed.amount" "150.00" "$(value "$out" settledamt=)"
out=$(bank "pix.stl.result|$stl2||SETTLED|SPIRES-2|ok|50.00|OP01|COR|SKH")
check "pix.stl.result.in" "SETTLED" "$(value "$out" status=)"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|SKI")
check "pix.stl.finalize" "SETTLED" "$(value "$out" status=)"
check "pix.stl.finalize.post" "BALANCED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|$stl1|OP01|COR|SKJ")
check "pix.stl.post.pay.rc" "00" "$(value "$out" rc=)"
check "pix.stl.post.pay.status" "POSTED" "$(value "$out" post=)"
stl1jrnl=$(value "$out" journal=)
case "$stl1jrnl" in
    STL*) jok=yes ;;
    *) jok=no ;;
esac
check "pix.stl.post.journal" "yes" "$jok"
out=$(bank "pix.stl.post|$stl2|OP01|COR|SKK")
check "pix.stl.post.rcv" "POSTED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|$stl1|OP01|COR|SKJ")
check "pix.stl.post.replay" "Y" "$(value "$out" replay=)"
out=$(bank "ledger.balance|$stlpayer")
check "pix.stl.customer.untouched.payer" "489950.00" "$(value "$out" available=)"
out=$(bank "ledger.balance|$stlpayee")
check "pix.stl.customer.untouched.payee" "500230.00" "$(value "$out" available=)"
grep -aq "|D|             150.00|${stlrt}|BRL|STL" var/journal/postings.log && paygl=yes || paygl=no
check "pix.stl.gl.payable.debit" "yes" "$paygl"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-OK||OP01|COR|SKL")
check "pix.stl.recon.ok" "BALANCED" "$(value "$out" msg=)"
check "pix.stl.recon.ok.matched" "000000002" "$(value "$out" matched=)"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|SKM")
check "pix.stl.cycle.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.cycle.recon" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.stl.get|$stl1")
check "pix.stl.obligation.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.obligation.matched" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.pos.list")
check "pix.stl.position.count" "0000001" "$(value "$out" positions=)"
check "pix.stl.position.settledpay" "150.00" "$(value "$out" settledpay=)"
check "pix.stl.position.settledrcv" "50.00" "$(value "$out" settledrcv=)"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|SKN")
check "pix.stl.finalize.replay" "Y" "$(value "$out" replay=)"

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


sed -i 's/business-date=.*/business-date=2026-10-02/' etc/bank.cfg
reset
bank "ledger.init" >/dev/null
out=$(bank "pix.rt.create|12345678|KOF SELF|DEBITS|DPI|Y||OP01|COR|SRT1")
check "pix.stl.rt.self" "ACTIVE" "$(value "$out" status=)"
out=$(bank "pix.rt.create|87654321|BANCO OUTRO|DEBITS|DPI|N||OP01|COR|SRT2")
stlrt=$(value "$out" id=)
out=$(bank "customer.create|P|STL PAGADOR|CPF|123.456.789-09|19900101|OP01|SC1")
out=$(bank "account.open|$(value "$out" id=)|DMND|BRL|500000|OP01|SC2|O1")
stlpayer=$(value "$out" id=)
out=$(bank "customer.create|P|STL RECEBEDOR|CPF|234.567.890-92|19900101|OP01|SC3")
stlrecvc=$(value "$out" id=)
out=$(bank "account.open|$stlrecvc|DMND|BRL|500000|OP01|SC4|O2")
stlpayee=$(value "$out" id=)
out=$(bank "pix.key.register|CPF|234.567.890-92|$stlpayee|$stlrecvc|OP01|COR|SK1")
stlkey=$(value "$out" id=)
out=$(bank "pix.key.seed|CPF|13579111140|$stlrt|FX000000001|FXC0000001|OUT CLIENTE|OP01|COR|SK2")
check "pix.stl.seed" "00" "$(value "$out" rc=)"
stlforeign=$(value "$out" keyid=)

out=$(bank "pix.out.key|$stlkey|100.00|$stlpayer|||pix local|OP01|COR|SK3||Y")
check "pix.stl.local.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|150.00|$stlpayer|||pix externo|OP01|COR|SK4||Y")
stlout=$(value "$out" id=)
check "pix.stl.out.posted" "POSTED" "$(value "$out" status=)"
check "pix.stl.out.settle.pending" "PENDING" "$(value "$out" settle=)"
out=$(bank "pix.in|50.00|$stlpayee|$stlrt|E2ESTL000000000000000000001|EXT-STL-1|PAGADOR EXTERNO|OP01|COR|SK5")
stlin=$(value "$out" id=)
check "pix.stl.in.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|70.00|$stlpayer|||a devolver|OP01|COR|SK6||Y")
stldvl=$(value "$out" id=)
out=$(bank "pix.devol|$stldvl|70.00|estorno integral|OP01|COR|SK7")
check "pix.stl.devol.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.get|$stldvl")
check "pix.stl.devol.status" "DEVOLVED" "$(value "$out" status=)"

out=$(bank "pix.cycle.open|20261002|BRL|OP01|COR|SK8")
check "pix.stl.cycle.open" "00" "$(value "$out" rc=)"
check "pix.stl.cycle.status" "OPEN" "$(value "$out" status=)"
cyc=$(value "$out" cycle=)
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|SK9")
check "pix.stl.accrue.rc" "00" "$(value "$out" rc=)"
check "pix.stl.accrue.cycle" "$cyc" "$(value "$out" cycle=)"
out=$(bank "pix.get|$stlout")
check "pix.stl.out.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.get|$stlin")
check "pix.stl.in.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.get|$stldvl")
check "pix.stl.devol.excluded" "NOT-APPLICABLE" "$(value "$out" settle=)"
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|SK9")
check "pix.stl.accrue.replay" "00" "$(value "$out" rc=)"

out=$(bank "pix.cycle.close|$cyc|OP01|COR|SKA")
check "pix.stl.close" "CLOSED" "$(value "$out" status=)"
out=$(bank "pix.cycle.calc|$cyc|OP01|COR|SKB")
check "pix.stl.calc" "CALCULATED" "$(value "$out" status=)"
check "pix.stl.calc.txns" "0000003" "$(value "$out" txns=)"
check "pix.stl.calc.grosspay" "150.00" "$(value "$out" grosspay=)"
check "pix.stl.calc.grossrcv" "120.00" "$(value "$out" grossrcv=)"
check "pix.stl.calc.net" "30.00" "$(value "$out" net=)"
check "pix.stl.calc.side" "PAYABLE" "$(value "$out" side=)"
check "pix.stl.calc.parties" "0000001" "$(value "$out" parties=)"

out=$(bank "pix.cycle.submit|$cyc||OP01|COR|SKC")
check "pix.stl.cycle.submit" "SUBMITTED" "$(value "$out" status=)"
out=$(bank "pix.stl.list|$cyc")
check "pix.stl.submit.count" "0000002" "$(value "$out" settlements=)"
check "pix.stl.submit.status" "SUBMITTED" "$(grep -c 'status=SUBMITTED' <<<"$out" | tr -d ' ')"
stl1=$(grep -F "side=PAYABLE" -B2 <<<"$out" | grep -F "settlement=" | head -1 | sed 's/^settlement=//;s/[[:space:]]*$//')
stl2=$(bank "pix.stl.list|$cyc" | grep -F "settlement=" | tail -1 | sed 's/^settlement=//;s/[[:space:]]*$//')
out=$(bank "pix.stl.get|$stl1")
check "pix.stl.get.participant" "$stlrt" "$(value "$out" participant=)"
check "pix.stl.get.extref" "SPIS-00000000001" "$(value "$out" extref=)"
out=$(bank "pix.cycle.submit|$cyc||OP01|COR|SKC")
check "pix.stl.submit.replay.attempts" "0001" "$(bank "pix.stl.get|$stl1" | grep -F "attempts=" | sed 's/^attempts=//;s/[[:space:]]*$//')"

out=$(bank "pix.stl.result|$stl1||SETTLED|SPIRES-1|valor divergente|140.00|OP01|COR|SKD")
check "pix.stl.result.mismatch.rc" "00" "$(value "$out" rc=)"
check "pix.stl.result.mismatch.settled" "140.00" "$(value "$out" settledamt=)"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-BAD||OP01|COR|SKE")
check "pix.stl.recon.bad.rc" "00" "$(value "$out" rc=)"
check "pix.stl.recon.bad.status" "EXCEPTIONS" "$(value "$out" msg=)"
check "pix.stl.recon.bad.open" "000000002" "$(value "$out" openexc=)"
out=$(bank "reconciliation.exceptions|REC-STL-BAD")
case "$out" in
    *AMT_MISMATCH*) stm=yes ;;
    *) stm=no ;;
esac
check "pix.stl.recon.amount.mismatch.code" "yes" "$stm"
case "$out" in
    *STALE_SETTLE*) sts=yes ;;
    *) sts=no ;;
esac
check "pix.stl.recon.stale.code" "yes" "$sts"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|SKF")
check "pix.stl.recon.cycle.exc" "RECON-EXCEPTION" "$(value "$out" status=)"

out=$(bank "pix.stl.result|$stl1||SETTLED|SPIRES-1B|valor correto|150.00|OP01|COR|SKG")
check "pix.stl.result.fixed" "SETTLED" "$(value "$out" status=)"
check "pix.stl.result.fixed.amount" "150.00" "$(value "$out" settledamt=)"
out=$(bank "pix.stl.result|$stl2||SETTLED|SPIRES-2|ok|50.00|OP01|COR|SKH")
check "pix.stl.result.in" "SETTLED" "$(value "$out" status=)"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|SKI")
check "pix.stl.finalize" "SETTLED" "$(value "$out" status=)"
check "pix.stl.finalize.post" "BALANCED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|$stl1|OP01|COR|SKJ")
check "pix.stl.post.pay.rc" "00" "$(value "$out" rc=)"
check "pix.stl.post.pay.status" "POSTED" "$(value "$out" post=)"
stl1jrnl=$(value "$out" journal=)
case "$stl1jrnl" in
    STL*) jok=yes ;;
    *) jok=no ;;
esac
check "pix.stl.post.journal" "yes" "$jok"
out=$(bank "pix.stl.post|$stl2|OP01|COR|SKK")
check "pix.stl.post.rcv" "POSTED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|$stl1|OP01|COR|SKJ")
check "pix.stl.post.replay" "Y" "$(value "$out" replay=)"
out=$(bank "ledger.balance|$stlpayer")
check "pix.stl.customer.untouched.payer" "489950.00" "$(value "$out" available=)"
out=$(bank "ledger.balance|$stlpayee")
check "pix.stl.customer.untouched.payee" "500230.00" "$(value "$out" available=)"
grep -aq "|D|             150.00|${stlrt}|BRL|STL" var/journal/postings.log && paygl=yes || paygl=no
check "pix.stl.gl.payable.debit" "yes" "$paygl"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-OK||OP01|COR|SKL")
check "pix.stl.recon.ok" "BALANCED" "$(value "$out" msg=)"
check "pix.stl.recon.ok.matched" "000000002" "$(value "$out" matched=)"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|SKM")
check "pix.stl.cycle.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.cycle.recon" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.stl.get|$stl1")
check "pix.stl.obligation.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.obligation.matched" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.pos.list")
check "pix.stl.position.count" "0000001" "$(value "$out" positions=)"
check "pix.stl.position.settledpay" "150.00" "$(value "$out" settledpay=)"
check "pix.stl.position.settledrcv" "50.00" "$(value "$out" settledrcv=)"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|SKN")
check "pix.stl.finalize.replay" "Y" "$(value "$out" replay=)"

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

sed -i 's/business-date=.*/business-date=2026-10-02/' etc/bank.cfg
reset
bank "ledger.init" >/dev/null
out=$(bank "pix.rt.create|12345678|KOF SELF|DEBITS|DPI|Y||OP01|COR|SRT1")
check "pix.stl.rt.self" "ACTIVE" "$(value "$out" status=)"
out=$(bank "pix.rt.create|87654321|BANCO OUTRO|DEBITS|DPI|N||OP01|COR|SRT2")
stlrt=$(value "$out" id=)
out=$(bank "customer.create|P|STL PAGADOR|CPF|123.456.789-09|19900101|OP01|SC1")
out=$(bank "account.open|$(value "$out" id=)|DMND|BRL|500000|OP01|SC2|O1")
stlpayer=$(value "$out" id=)
out=$(bank "customer.create|P|STL RECEBEDOR|CPF|234.567.890-92|19900101|OP01|SC3")
stlrecvc=$(value "$out" id=)
out=$(bank "account.open|$stlrecvc|DMND|BRL|500000|OP01|SC4|O2")
stlpayee=$(value "$out" id=)
out=$(bank "pix.key.register|CPF|234.567.890-92|$stlpayee|$stlrecvc|OP01|COR|SK1")
stlkey=$(value "$out" id=)
out=$(bank "pix.key.seed|CPF|13579111140|$stlrt|FX000000001|FXC0000001|OUT CLIENTE|OP01|COR|SK2")
check "pix.stl.seed" "00" "$(value "$out" rc=)"
stlforeign=$(value "$out" keyid=)

out=$(bank "pix.out.key|$stlkey|100.00|$stlpayer|||pix local|OP01|COR|SK3||Y")
check "pix.stl.local.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|150.00|$stlpayer|||pix externo|OP01|COR|SK4||Y")
stlout=$(value "$out" id=)
check "pix.stl.out.posted" "POSTED" "$(value "$out" status=)"
check "pix.stl.out.settle.pending" "PENDING" "$(value "$out" settle=)"
out=$(bank "pix.in|50.00|$stlpayee|$stlrt|E2ESTL000000000000000000001|EXT-STL-1|PAGADOR EXTERNO|OP01|COR|SK5")
stlin=$(value "$out" id=)
check "pix.stl.in.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|70.00|$stlpayer|||a devolver|OP01|COR|SK6||Y")
stldvl=$(value "$out" id=)
out=$(bank "pix.devol|$stldvl|70.00|estorno integral|OP01|COR|SK7")
check "pix.stl.devol.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.get|$stldvl")
check "pix.stl.devol.status" "DEVOLVED" "$(value "$out" status=)"

out=$(bank "pix.cycle.open|20261002|BRL|OP01|COR|SK8")
check "pix.stl.cycle.open" "00" "$(value "$out" rc=)"
check "pix.stl.cycle.status" "OPEN" "$(value "$out" status=)"
cyc=$(value "$out" cycle=)
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|SK9")
check "pix.stl.accrue.rc" "00" "$(value "$out" rc=)"
check "pix.stl.accrue.cycle" "$cyc" "$(value "$out" cycle=)"
out=$(bank "pix.get|$stlout")
check "pix.stl.out.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.get|$stlin")
check "pix.stl.in.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.get|$stldvl")
check "pix.stl.devol.excluded" "NOT-APPLICABLE" "$(value "$out" settle=)"
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|SK9")
check "pix.stl.accrue.replay" "00" "$(value "$out" rc=)"

out=$(bank "pix.cycle.close|$cyc|OP01|COR|SKA")
check "pix.stl.close" "CLOSED" "$(value "$out" status=)"
out=$(bank "pix.cycle.calc|$cyc|OP01|COR|SKB")
check "pix.stl.calc" "CALCULATED" "$(value "$out" status=)"
check "pix.stl.calc.txns" "0000003" "$(value "$out" txns=)"
check "pix.stl.calc.grosspay" "150.00" "$(value "$out" grosspay=)"
check "pix.stl.calc.grossrcv" "120.00" "$(value "$out" grossrcv=)"
check "pix.stl.calc.net" "30.00" "$(value "$out" net=)"
check "pix.stl.calc.side" "PAYABLE" "$(value "$out" side=)"
check "pix.stl.calc.parties" "0000001" "$(value "$out" parties=)"

out=$(bank "pix.cycle.submit|$cyc||OP01|COR|SKC")
check "pix.stl.cycle.submit" "SUBMITTED" "$(value "$out" status=)"
out=$(bank "pix.stl.list|$cyc")
check "pix.stl.submit.count" "0000002" "$(value "$out" settlements=)"
check "pix.stl.submit.status" "SUBMITTED" "$(grep -c 'status=SUBMITTED' <<<"$out" | tr -d ' ')"
stl1=$(grep -F "side=PAYABLE" -B2 <<<"$out" | grep -F "settlement=" | head -1 | sed 's/^settlement=//;s/[[:space:]]*$//')
stl2=$(bank "pix.stl.list|$cyc" | grep -F "settlement=" | tail -1 | sed 's/^settlement=//;s/[[:space:]]*$//')
out=$(bank "pix.stl.get|$stl1")
check "pix.stl.get.participant" "$stlrt" "$(value "$out" participant=)"
check "pix.stl.get.extref" "SPIS-00000000001" "$(value "$out" extref=)"
out=$(bank "pix.cycle.submit|$cyc||OP01|COR|SKC")
check "pix.stl.submit.replay.attempts" "0001" "$(bank "pix.stl.get|$stl1" | grep -F "attempts=" | sed 's/^attempts=//;s/[[:space:]]*$//')"

out=$(bank "pix.stl.result|$stl1||SETTLED|SPIRES-1|valor divergente|140.00|OP01|COR|SKD")
check "pix.stl.result.mismatch.rc" "00" "$(value "$out" rc=)"
check "pix.stl.result.mismatch.settled" "140.00" "$(value "$out" settledamt=)"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-BAD||OP01|COR|SKE")
check "pix.stl.recon.bad.rc" "00" "$(value "$out" rc=)"
check "pix.stl.recon.bad.status" "EXCEPTIONS" "$(value "$out" msg=)"
check "pix.stl.recon.bad.open" "000000002" "$(value "$out" openexc=)"
out=$(bank "reconciliation.exceptions|REC-STL-BAD")
case "$out" in
    *AMT_MISMATCH*) stm=yes ;;
    *) stm=no ;;
esac
check "pix.stl.recon.amount.mismatch.code" "yes" "$stm"
case "$out" in
    *STALE_SETTLE*) sts=yes ;;
    *) sts=no ;;
esac
check "pix.stl.recon.stale.code" "yes" "$sts"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|SKF")
check "pix.stl.recon.cycle.exc" "RECON-EXCEPTION" "$(value "$out" status=)"

out=$(bank "pix.stl.result|$stl1||SETTLED|SPIRES-1B|valor correto|150.00|OP01|COR|SKG")
check "pix.stl.result.fixed" "SETTLED" "$(value "$out" status=)"
check "pix.stl.result.fixed.amount" "150.00" "$(value "$out" settledamt=)"
out=$(bank "pix.stl.result|$stl2||SETTLED|SPIRES-2|ok|50.00|OP01|COR|SKH")
check "pix.stl.result.in" "SETTLED" "$(value "$out" status=)"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|SKI")
check "pix.stl.finalize" "SETTLED" "$(value "$out" status=)"
check "pix.stl.finalize.post" "BALANCED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|$stl1|OP01|COR|SKJ")
check "pix.stl.post.pay.rc" "00" "$(value "$out" rc=)"
check "pix.stl.post.pay.status" "POSTED" "$(value "$out" post=)"
stl1jrnl=$(value "$out" journal=)
case "$stl1jrnl" in
    STL*) jok=yes ;;
    *) jok=no ;;
esac
check "pix.stl.post.journal" "yes" "$jok"
out=$(bank "pix.stl.post|$stl2|OP01|COR|SKK")
check "pix.stl.post.rcv" "POSTED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|$stl1|OP01|COR|SKJ")
check "pix.stl.post.replay" "Y" "$(value "$out" replay=)"
out=$(bank "ledger.balance|$stlpayer")
check "pix.stl.customer.untouched.payer" "489950.00" "$(value "$out" available=)"
out=$(bank "ledger.balance|$stlpayee")
check "pix.stl.customer.untouched.payee" "500230.00" "$(value "$out" available=)"
grep -aq "|D|             150.00|${stlrt}|BRL|STL" var/journal/postings.log && paygl=yes || paygl=no
check "pix.stl.gl.payable.debit" "yes" "$paygl"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-OK||OP01|COR|SKL")
check "pix.stl.recon.ok" "BALANCED" "$(value "$out" msg=)"
check "pix.stl.recon.ok.matched" "000000002" "$(value "$out" matched=)"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|SKM")
check "pix.stl.cycle.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.cycle.recon" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.stl.get|$stl1")
check "pix.stl.obligation.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.obligation.matched" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.pos.list")
check "pix.stl.position.count" "0000001" "$(value "$out" positions=)"
check "pix.stl.position.settledpay" "150.00" "$(value "$out" settledpay=)"
check "pix.stl.position.settledrcv" "50.00" "$(value "$out" settledrcv=)"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|SKN")
check "pix.stl.finalize.replay" "Y" "$(value "$out" replay=)"

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


sed -i 's/business-date=.*/business-date=2026-10-02/' etc/bank.cfg
reset
bank "ledger.init" >/dev/null
out=$(bank "pix.rt.create|12345678|KOF SELF|DEBITS|DPI|Y||OP01|COR|SRT1")
check "pix.stl.rt.self" "ACTIVE" "$(value "$out" status=)"
out=$(bank "pix.rt.create|87654321|BANCO OUTRO|DEBITS|DPI|N||OP01|COR|SRT2")
stlrt=$(value "$out" id=)
out=$(bank "customer.create|P|STL PAGADOR|CPF|123.456.789-09|19900101|OP01|SC1")
out=$(bank "account.open|$(value "$out" id=)|DMND|BRL|500000|OP01|SC2|O1")
stlpayer=$(value "$out" id=)
out=$(bank "customer.create|P|STL RECEBEDOR|CPF|234.567.890-92|19900101|OP01|SC3")
stlrecvc=$(value "$out" id=)
out=$(bank "account.open|$stlrecvc|DMND|BRL|500000|OP01|SC4|O2")
stlpayee=$(value "$out" id=)
out=$(bank "pix.key.register|CPF|234.567.890-92|$stlpayee|$stlrecvc|OP01|COR|SK1")
stlkey=$(value "$out" id=)
out=$(bank "pix.key.seed|CPF|13579111140|$stlrt|FX000000001|FXC0000001|OUT CLIENTE|OP01|COR|SK2")
check "pix.stl.seed" "00" "$(value "$out" rc=)"
stlforeign=$(value "$out" keyid=)

out=$(bank "pix.out.key|$stlkey|100.00|$stlpayer|||pix local|OP01|COR|SK3||Y")
check "pix.stl.local.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|150.00|$stlpayer|||pix externo|OP01|COR|SK4||Y")
stlout=$(value "$out" id=)
check "pix.stl.out.posted" "POSTED" "$(value "$out" status=)"
check "pix.stl.out.settle.pending" "PENDING" "$(value "$out" settle=)"
out=$(bank "pix.in|50.00|$stlpayee|$stlrt|E2ESTL000000000000000000001|EXT-STL-1|PAGADOR EXTERNO|OP01|COR|SK5")
stlin=$(value "$out" id=)
check "pix.stl.in.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|70.00|$stlpayer|||a devolver|OP01|COR|SK6||Y")
stldvl=$(value "$out" id=)
out=$(bank "pix.devol|$stldvl|70.00|estorno integral|OP01|COR|SK7")
check "pix.stl.devol.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.get|$stldvl")
check "pix.stl.devol.status" "DEVOLVED" "$(value "$out" status=)"

out=$(bank "pix.cycle.open|20261002|BRL|OP01|COR|SK8")
check "pix.stl.cycle.open" "00" "$(value "$out" rc=)"
check "pix.stl.cycle.status" "OPEN" "$(value "$out" status=)"
cyc=$(value "$out" cycle=)
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|SK9")
check "pix.stl.accrue.rc" "00" "$(value "$out" rc=)"
check "pix.stl.accrue.cycle" "$cyc" "$(value "$out" cycle=)"
out=$(bank "pix.get|$stlout")
check "pix.stl.out.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.get|$stlin")
check "pix.stl.in.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.get|$stldvl")
check "pix.stl.devol.excluded" "NOT-APPLICABLE" "$(value "$out" settle=)"
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|SK9")
check "pix.stl.accrue.replay" "00" "$(value "$out" rc=)"

out=$(bank "pix.cycle.close|$cyc|OP01|COR|SKA")
check "pix.stl.close" "CLOSED" "$(value "$out" status=)"
out=$(bank "pix.cycle.calc|$cyc|OP01|COR|SKB")
check "pix.stl.calc" "CALCULATED" "$(value "$out" status=)"
check "pix.stl.calc.txns" "0000003" "$(value "$out" txns=)"
check "pix.stl.calc.grosspay" "150.00" "$(value "$out" grosspay=)"
check "pix.stl.calc.grossrcv" "120.00" "$(value "$out" grossrcv=)"
check "pix.stl.calc.net" "30.00" "$(value "$out" net=)"
check "pix.stl.calc.side" "PAYABLE" "$(value "$out" side=)"
check "pix.stl.calc.parties" "0000001" "$(value "$out" parties=)"

out=$(bank "pix.cycle.submit|$cyc||OP01|COR|SKC")
check "pix.stl.cycle.submit" "SUBMITTED" "$(value "$out" status=)"
out=$(bank "pix.stl.list|$cyc")
check "pix.stl.submit.count" "0000002" "$(value "$out" settlements=)"
check "pix.stl.submit.status" "SUBMITTED" "$(grep -c 'status=SUBMITTED' <<<"$out" | tr -d ' ')"
stl1=$(grep -F "side=PAYABLE" -B2 <<<"$out" | grep -F "settlement=" | head -1 | sed 's/^settlement=//;s/[[:space:]]*$//')
stl2=$(bank "pix.stl.list|$cyc" | grep -F "settlement=" | tail -1 | sed 's/^settlement=//;s/[[:space:]]*$//')
out=$(bank "pix.stl.get|$stl1")
check "pix.stl.get.participant" "$stlrt" "$(value "$out" participant=)"
check "pix.stl.get.extref" "SPIS-00000000001" "$(value "$out" extref=)"
out=$(bank "pix.cycle.submit|$cyc||OP01|COR|SKC")
check "pix.stl.submit.replay.attempts" "0001" "$(bank "pix.stl.get|$stl1" | grep -F "attempts=" | sed 's/^attempts=//;s/[[:space:]]*$//')"

out=$(bank "pix.stl.result|$stl1||SETTLED|SPIRES-1|valor divergente|140.00|OP01|COR|SKD")
check "pix.stl.result.mismatch.rc" "00" "$(value "$out" rc=)"
check "pix.stl.result.mismatch.settled" "140.00" "$(value "$out" settledamt=)"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-BAD||OP01|COR|SKE")
check "pix.stl.recon.bad.rc" "00" "$(value "$out" rc=)"
check "pix.stl.recon.bad.status" "EXCEPTIONS" "$(value "$out" msg=)"
check "pix.stl.recon.bad.open" "000000002" "$(value "$out" openexc=)"
out=$(bank "reconciliation.exceptions|REC-STL-BAD")
case "$out" in
    *AMT_MISMATCH*) stm=yes ;;
    *) stm=no ;;
esac
check "pix.stl.recon.amount.mismatch.code" "yes" "$stm"
case "$out" in
    *STALE_SETTLE*) sts=yes ;;
    *) sts=no ;;
esac
check "pix.stl.recon.stale.code" "yes" "$sts"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|SKF")
check "pix.stl.recon.cycle.exc" "RECON-EXCEPTION" "$(value "$out" status=)"

out=$(bank "pix.stl.result|$stl1||SETTLED|SPIRES-1B|valor correto|150.00|OP01|COR|SKG")
check "pix.stl.result.fixed" "SETTLED" "$(value "$out" status=)"
check "pix.stl.result.fixed.amount" "150.00" "$(value "$out" settledamt=)"
out=$(bank "pix.stl.result|$stl2||SETTLED|SPIRES-2|ok|50.00|OP01|COR|SKH")
check "pix.stl.result.in" "SETTLED" "$(value "$out" status=)"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|SKI")
check "pix.stl.finalize" "SETTLED" "$(value "$out" status=)"
check "pix.stl.finalize.post" "BALANCED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|$stl1|OP01|COR|SKJ")
check "pix.stl.post.pay.rc" "00" "$(value "$out" rc=)"
check "pix.stl.post.pay.status" "POSTED" "$(value "$out" post=)"
stl1jrnl=$(value "$out" journal=)
case "$stl1jrnl" in
    STL*) jok=yes ;;
    *) jok=no ;;
esac
check "pix.stl.post.journal" "yes" "$jok"
out=$(bank "pix.stl.post|$stl2|OP01|COR|SKK")
check "pix.stl.post.rcv" "POSTED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|$stl1|OP01|COR|SKJ")
check "pix.stl.post.replay" "Y" "$(value "$out" replay=)"
out=$(bank "ledger.balance|$stlpayer")
check "pix.stl.customer.untouched.payer" "489950.00" "$(value "$out" available=)"
out=$(bank "ledger.balance|$stlpayee")
check "pix.stl.customer.untouched.payee" "500230.00" "$(value "$out" available=)"
grep -aq "|D|             150.00|${stlrt}|BRL|STL" var/journal/postings.log && paygl=yes || paygl=no
check "pix.stl.gl.payable.debit" "yes" "$paygl"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-OK||OP01|COR|SKL")
check "pix.stl.recon.ok" "BALANCED" "$(value "$out" msg=)"
check "pix.stl.recon.ok.matched" "000000002" "$(value "$out" matched=)"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|SKM")
check "pix.stl.cycle.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.cycle.recon" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.stl.get|$stl1")
check "pix.stl.obligation.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.obligation.matched" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.pos.list")
check "pix.stl.position.count" "0000001" "$(value "$out" positions=)"
check "pix.stl.position.settledpay" "150.00" "$(value "$out" settledpay=)"
check "pix.stl.position.settledrcv" "50.00" "$(value "$out" settledrcv=)"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|SKN")
check "pix.stl.finalize.replay" "Y" "$(value "$out" replay=)"

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


sed -i 's/business-date=.*/business-date=2026-10-02/' etc/bank.cfg
reset
bank "ledger.init" >/dev/null
out=$(bank "pix.rt.create|12345678|KOF SELF|DEBITS|DPI|Y||OP01|COR|SRT1")
check "pix.stl.rt.self" "ACTIVE" "$(value "$out" status=)"
out=$(bank "pix.rt.create|87654321|BANCO OUTRO|DEBITS|DPI|N||OP01|COR|SRT2")
stlrt=$(value "$out" id=)
out=$(bank "customer.create|P|STL PAGADOR|CPF|123.456.789-09|19900101|OP01|SC1")
out=$(bank "account.open|$(value "$out" id=)|DMND|BRL|500000|OP01|SC2|O1")
stlpayer=$(value "$out" id=)
out=$(bank "customer.create|P|STL RECEBEDOR|CPF|234.567.890-92|19900101|OP01|SC3")
stlrecvc=$(value "$out" id=)
out=$(bank "account.open|$stlrecvc|DMND|BRL|500000|OP01|SC4|O2")
stlpayee=$(value "$out" id=)
out=$(bank "pix.key.register|CPF|234.567.890-92|$stlpayee|$stlrecvc|OP01|COR|SK1")
stlkey=$(value "$out" id=)
out=$(bank "pix.key.seed|CPF|13579111140|$stlrt|FX000000001|FXC0000001|OUT CLIENTE|OP01|COR|SK2")
check "pix.stl.seed" "00" "$(value "$out" rc=)"
stlforeign=$(value "$out" keyid=)

out=$(bank "pix.out.key|$stlkey|100.00|$stlpayer|||pix local|OP01|COR|SK3||Y")
check "pix.stl.local.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|150.00|$stlpayer|||pix externo|OP01|COR|SK4||Y")
stlout=$(value "$out" id=)
check "pix.stl.out.posted" "POSTED" "$(value "$out" status=)"
check "pix.stl.out.settle.pending" "PENDING" "$(value "$out" settle=)"
out=$(bank "pix.in|50.00|$stlpayee|$stlrt|E2ESTL000000000000000000001|EXT-STL-1|PAGADOR EXTERNO|OP01|COR|SK5")
stlin=$(value "$out" id=)
check "pix.stl.in.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|70.00|$stlpayer|||a devolver|OP01|COR|SK6||Y")
stldvl=$(value "$out" id=)
out=$(bank "pix.devol|$stldvl|70.00|estorno integral|OP01|COR|SK7")
check "pix.stl.devol.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.get|$stldvl")
check "pix.stl.devol.status" "DEVOLVED" "$(value "$out" status=)"

out=$(bank "pix.cycle.open|20261002|BRL|OP01|COR|SK8")
check "pix.stl.cycle.open" "00" "$(value "$out" rc=)"
check "pix.stl.cycle.status" "OPEN" "$(value "$out" status=)"
cyc=$(value "$out" cycle=)
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|SK9")
check "pix.stl.accrue.rc" "00" "$(value "$out" rc=)"
check "pix.stl.accrue.cycle" "$cyc" "$(value "$out" cycle=)"
out=$(bank "pix.get|$stlout")
check "pix.stl.out.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.get|$stlin")
check "pix.stl.in.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.get|$stldvl")
check "pix.stl.devol.excluded" "NOT-APPLICABLE" "$(value "$out" settle=)"
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|SK9")
check "pix.stl.accrue.replay" "00" "$(value "$out" rc=)"

out=$(bank "pix.cycle.close|$cyc|OP01|COR|SKA")
check "pix.stl.close" "CLOSED" "$(value "$out" status=)"
out=$(bank "pix.cycle.calc|$cyc|OP01|COR|SKB")
check "pix.stl.calc" "CALCULATED" "$(value "$out" status=)"
check "pix.stl.calc.txns" "0000003" "$(value "$out" txns=)"
check "pix.stl.calc.grosspay" "150.00" "$(value "$out" grosspay=)"
check "pix.stl.calc.grossrcv" "120.00" "$(value "$out" grossrcv=)"
check "pix.stl.calc.net" "30.00" "$(value "$out" net=)"
check "pix.stl.calc.side" "PAYABLE" "$(value "$out" side=)"
check "pix.stl.calc.parties" "0000001" "$(value "$out" parties=)"

out=$(bank "pix.cycle.submit|$cyc||OP01|COR|SKC")
check "pix.stl.cycle.submit" "SUBMITTED" "$(value "$out" status=)"
out=$(bank "pix.stl.list|$cyc")
check "pix.stl.submit.count" "0000002" "$(value "$out" settlements=)"
check "pix.stl.submit.status" "SUBMITTED" "$(grep -c 'status=SUBMITTED' <<<"$out" | tr -d ' ')"
stl1=$(grep -F "side=PAYABLE" -B2 <<<"$out" | grep -F "settlement=" | head -1 | sed 's/^settlement=//;s/[[:space:]]*$//')
stl2=$(bank "pix.stl.list|$cyc" | grep -F "settlement=" | tail -1 | sed 's/^settlement=//;s/[[:space:]]*$//')
out=$(bank "pix.stl.get|$stl1")
check "pix.stl.get.participant" "$stlrt" "$(value "$out" participant=)"
check "pix.stl.get.extref" "SPIS-00000000001" "$(value "$out" extref=)"
out=$(bank "pix.cycle.submit|$cyc||OP01|COR|SKC")
check "pix.stl.submit.replay.attempts" "0001" "$(bank "pix.stl.get|$stl1" | grep -F "attempts=" | sed 's/^attempts=//;s/[[:space:]]*$//')"

out=$(bank "pix.stl.result|$stl1||SETTLED|SPIRES-1|valor divergente|140.00|OP01|COR|SKD")
check "pix.stl.result.mismatch.rc" "00" "$(value "$out" rc=)"
check "pix.stl.result.mismatch.settled" "140.00" "$(value "$out" settledamt=)"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-BAD||OP01|COR|SKE")
check "pix.stl.recon.bad.rc" "00" "$(value "$out" rc=)"
check "pix.stl.recon.bad.status" "EXCEPTIONS" "$(value "$out" msg=)"
check "pix.stl.recon.bad.open" "000000002" "$(value "$out" openexc=)"
out=$(bank "reconciliation.exceptions|REC-STL-BAD")
case "$out" in
    *AMT_MISMATCH*) stm=yes ;;
    *) stm=no ;;
esac
check "pix.stl.recon.amount.mismatch.code" "yes" "$stm"
case "$out" in
    *STALE_SETTLE*) sts=yes ;;
    *) sts=no ;;
esac
check "pix.stl.recon.stale.code" "yes" "$sts"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|SKF")
check "pix.stl.recon.cycle.exc" "RECON-EXCEPTION" "$(value "$out" status=)"

out=$(bank "pix.stl.result|$stl1||SETTLED|SPIRES-1B|valor correto|150.00|OP01|COR|SKG")
check "pix.stl.result.fixed" "SETTLED" "$(value "$out" status=)"
check "pix.stl.result.fixed.amount" "150.00" "$(value "$out" settledamt=)"
out=$(bank "pix.stl.result|$stl2||SETTLED|SPIRES-2|ok|50.00|OP01|COR|SKH")
check "pix.stl.result.in" "SETTLED" "$(value "$out" status=)"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|SKI")
check "pix.stl.finalize" "SETTLED" "$(value "$out" status=)"
check "pix.stl.finalize.post" "BALANCED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|$stl1|OP01|COR|SKJ")
check "pix.stl.post.pay.rc" "00" "$(value "$out" rc=)"
check "pix.stl.post.pay.status" "POSTED" "$(value "$out" post=)"
stl1jrnl=$(value "$out" journal=)
case "$stl1jrnl" in
    STL*) jok=yes ;;
    *) jok=no ;;
esac
check "pix.stl.post.journal" "yes" "$jok"
out=$(bank "pix.stl.post|$stl2|OP01|COR|SKK")
check "pix.stl.post.rcv" "POSTED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|$stl1|OP01|COR|SKJ")
check "pix.stl.post.replay" "Y" "$(value "$out" replay=)"
out=$(bank "ledger.balance|$stlpayer")
check "pix.stl.customer.untouched.payer" "489950.00" "$(value "$out" available=)"
out=$(bank "ledger.balance|$stlpayee")
check "pix.stl.customer.untouched.payee" "500230.00" "$(value "$out" available=)"
grep -aq "|D|             150.00|${stlrt}|BRL|STL" var/journal/postings.log && paygl=yes || paygl=no
check "pix.stl.gl.payable.debit" "yes" "$paygl"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-OK||OP01|COR|SKL")
check "pix.stl.recon.ok" "BALANCED" "$(value "$out" msg=)"
check "pix.stl.recon.ok.matched" "000000002" "$(value "$out" matched=)"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|SKM")
check "pix.stl.cycle.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.cycle.recon" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.stl.get|$stl1")
check "pix.stl.obligation.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.obligation.matched" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.pos.list")
check "pix.stl.position.count" "0000001" "$(value "$out" positions=)"
check "pix.stl.position.settledpay" "150.00" "$(value "$out" settledpay=)"
check "pix.stl.position.settledrcv" "50.00" "$(value "$out" settledrcv=)"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|SKN")
check "pix.stl.finalize.replay" "Y" "$(value "$out" replay=)"

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

sed -i 's/business-date=.*/business-date=2026-10-02/' etc/bank.cfg
reset
bank "ledger.init" >/dev/null
out=$(bank "pix.rt.create|12345678|KOF SELF|DEBITS|DPI|Y||OP01|COR|SRT1")
check "pix.stl.rt.self" "ACTIVE" "$(value "$out" status=)"
out=$(bank "pix.rt.create|87654321|BANCO OUTRO|DEBITS|DPI|N||OP01|COR|SRT2")
stlrt=$(value "$out" id=)
out=$(bank "customer.create|P|STL PAGADOR|CPF|123.456.789-09|19900101|OP01|SC1")
out=$(bank "account.open|$(value "$out" id=)|DMND|BRL|500000|OP01|SC2|O1")
stlpayer=$(value "$out" id=)
out=$(bank "customer.create|P|STL RECEBEDOR|CPF|234.567.890-92|19900101|OP01|SC3")
stlrecvc=$(value "$out" id=)
out=$(bank "account.open|$stlrecvc|DMND|BRL|500000|OP01|SC4|O2")
stlpayee=$(value "$out" id=)
out=$(bank "pix.key.register|CPF|234.567.890-92|$stlpayee|$stlrecvc|OP01|COR|SK1")
stlkey=$(value "$out" id=)
out=$(bank "pix.key.seed|CPF|13579111140|$stlrt|FX000000001|FXC0000001|OUT CLIENTE|OP01|COR|SK2")
check "pix.stl.seed" "00" "$(value "$out" rc=)"
stlforeign=$(value "$out" keyid=)

out=$(bank "pix.out.key|$stlkey|100.00|$stlpayer|||pix local|OP01|COR|SK3||Y")
check "pix.stl.local.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|150.00|$stlpayer|||pix externo|OP01|COR|SK4||Y")
stlout=$(value "$out" id=)
check "pix.stl.out.posted" "POSTED" "$(value "$out" status=)"
check "pix.stl.out.settle.pending" "PENDING" "$(value "$out" settle=)"
out=$(bank "pix.in|50.00|$stlpayee|$stlrt|E2ESTL000000000000000000001|EXT-STL-1|PAGADOR EXTERNO|OP01|COR|SK5")
stlin=$(value "$out" id=)
check "pix.stl.in.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|70.00|$stlpayer|||a devolver|OP01|COR|SK6||Y")
stldvl=$(value "$out" id=)
out=$(bank "pix.devol|$stldvl|70.00|estorno integral|OP01|COR|SK7")
check "pix.stl.devol.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.get|$stldvl")
check "pix.stl.devol.status" "DEVOLVED" "$(value "$out" status=)"

out=$(bank "pix.cycle.open|20261002|BRL|OP01|COR|SK8")
check "pix.stl.cycle.open" "00" "$(value "$out" rc=)"
check "pix.stl.cycle.status" "OPEN" "$(value "$out" status=)"
cyc=$(value "$out" cycle=)
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|SK9")
check "pix.stl.accrue.rc" "00" "$(value "$out" rc=)"
check "pix.stl.accrue.cycle" "$cyc" "$(value "$out" cycle=)"
out=$(bank "pix.get|$stlout")
check "pix.stl.out.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.get|$stlin")
check "pix.stl.in.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.get|$stldvl")
check "pix.stl.devol.excluded" "NOT-APPLICABLE" "$(value "$out" settle=)"
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|SK9")
check "pix.stl.accrue.replay" "00" "$(value "$out" rc=)"

out=$(bank "pix.cycle.close|$cyc|OP01|COR|SKA")
check "pix.stl.close" "CLOSED" "$(value "$out" status=)"
out=$(bank "pix.cycle.calc|$cyc|OP01|COR|SKB")
check "pix.stl.calc" "CALCULATED" "$(value "$out" status=)"
check "pix.stl.calc.txns" "0000003" "$(value "$out" txns=)"
check "pix.stl.calc.grosspay" "150.00" "$(value "$out" grosspay=)"
check "pix.stl.calc.grossrcv" "120.00" "$(value "$out" grossrcv=)"
check "pix.stl.calc.net" "30.00" "$(value "$out" net=)"
check "pix.stl.calc.side" "PAYABLE" "$(value "$out" side=)"
check "pix.stl.calc.parties" "0000001" "$(value "$out" parties=)"

out=$(bank "pix.cycle.submit|$cyc||OP01|COR|SKC")
check "pix.stl.cycle.submit" "SUBMITTED" "$(value "$out" status=)"
out=$(bank "pix.stl.list|$cyc")
check "pix.stl.submit.count" "0000002" "$(value "$out" settlements=)"
check "pix.stl.submit.status" "SUBMITTED" "$(grep -c 'status=SUBMITTED' <<<"$out" | tr -d ' ')"
stl1=$(grep -F "side=PAYABLE" -B2 <<<"$out" | grep -F "settlement=" | head -1 | sed 's/^settlement=//;s/[[:space:]]*$//')
stl2=$(bank "pix.stl.list|$cyc" | grep -F "settlement=" | tail -1 | sed 's/^settlement=//;s/[[:space:]]*$//')
out=$(bank "pix.stl.get|$stl1")
check "pix.stl.get.participant" "$stlrt" "$(value "$out" participant=)"
check "pix.stl.get.extref" "SPIS-00000000001" "$(value "$out" extref=)"
out=$(bank "pix.cycle.submit|$cyc||OP01|COR|SKC")
check "pix.stl.submit.replay.attempts" "0001" "$(bank "pix.stl.get|$stl1" | grep -F "attempts=" | sed 's/^attempts=//;s/[[:space:]]*$//')"

out=$(bank "pix.stl.result|$stl1||SETTLED|SPIRES-1|valor divergente|140.00|OP01|COR|SKD")
check "pix.stl.result.mismatch.rc" "00" "$(value "$out" rc=)"
check "pix.stl.result.mismatch.settled" "140.00" "$(value "$out" settledamt=)"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-BAD||OP01|COR|SKE")
check "pix.stl.recon.bad.rc" "00" "$(value "$out" rc=)"
check "pix.stl.recon.bad.status" "EXCEPTIONS" "$(value "$out" msg=)"
check "pix.stl.recon.bad.open" "000000002" "$(value "$out" openexc=)"
out=$(bank "reconciliation.exceptions|REC-STL-BAD")
case "$out" in
    *AMT_MISMATCH*) stm=yes ;;
    *) stm=no ;;
esac
check "pix.stl.recon.amount.mismatch.code" "yes" "$stm"
case "$out" in
    *STALE_SETTLE*) sts=yes ;;
    *) sts=no ;;
esac
check "pix.stl.recon.stale.code" "yes" "$sts"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|SKF")
check "pix.stl.recon.cycle.exc" "RECON-EXCEPTION" "$(value "$out" status=)"

out=$(bank "pix.stl.result|$stl1||SETTLED|SPIRES-1B|valor correto|150.00|OP01|COR|SKG")
check "pix.stl.result.fixed" "SETTLED" "$(value "$out" status=)"
check "pix.stl.result.fixed.amount" "150.00" "$(value "$out" settledamt=)"
out=$(bank "pix.stl.result|$stl2||SETTLED|SPIRES-2|ok|50.00|OP01|COR|SKH")
check "pix.stl.result.in" "SETTLED" "$(value "$out" status=)"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|SKI")
check "pix.stl.finalize" "SETTLED" "$(value "$out" status=)"
check "pix.stl.finalize.post" "BALANCED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|$stl1|OP01|COR|SKJ")
check "pix.stl.post.pay.rc" "00" "$(value "$out" rc=)"
check "pix.stl.post.pay.status" "POSTED" "$(value "$out" post=)"
stl1jrnl=$(value "$out" journal=)
case "$stl1jrnl" in
    STL*) jok=yes ;;
    *) jok=no ;;
esac
check "pix.stl.post.journal" "yes" "$jok"
out=$(bank "pix.stl.post|$stl2|OP01|COR|SKK")
check "pix.stl.post.rcv" "POSTED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|$stl1|OP01|COR|SKJ")
check "pix.stl.post.replay" "Y" "$(value "$out" replay=)"
out=$(bank "ledger.balance|$stlpayer")
check "pix.stl.customer.untouched.payer" "489950.00" "$(value "$out" available=)"
out=$(bank "ledger.balance|$stlpayee")
check "pix.stl.customer.untouched.payee" "500230.00" "$(value "$out" available=)"
grep -aq "|D|             150.00|${stlrt}|BRL|STL" var/journal/postings.log && paygl=yes || paygl=no
check "pix.stl.gl.payable.debit" "yes" "$paygl"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-OK||OP01|COR|SKL")
check "pix.stl.recon.ok" "BALANCED" "$(value "$out" msg=)"
check "pix.stl.recon.ok.matched" "000000002" "$(value "$out" matched=)"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|SKM")
check "pix.stl.cycle.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.cycle.recon" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.stl.get|$stl1")
check "pix.stl.obligation.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.obligation.matched" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.pos.list")
check "pix.stl.position.count" "0000001" "$(value "$out" positions=)"
check "pix.stl.position.settledpay" "150.00" "$(value "$out" settledpay=)"
check "pix.stl.position.settledrcv" "50.00" "$(value "$out" settledrcv=)"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|SKN")
check "pix.stl.finalize.replay" "Y" "$(value "$out" replay=)"

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


sed -i 's/business-date=.*/business-date=2026-10-02/' etc/bank.cfg
reset
bank "ledger.init" >/dev/null
out=$(bank "pix.rt.create|12345678|KOF SELF|DEBITS|DPI|Y||OP01|COR|SRT1")
check "pix.stl.rt.self" "ACTIVE" "$(value "$out" status=)"
out=$(bank "pix.rt.create|87654321|BANCO OUTRO|DEBITS|DPI|N||OP01|COR|SRT2")
stlrt=$(value "$out" id=)
out=$(bank "customer.create|P|STL PAGADOR|CPF|123.456.789-09|19900101|OP01|SC1")
out=$(bank "account.open|$(value "$out" id=)|DMND|BRL|500000|OP01|SC2|O1")
stlpayer=$(value "$out" id=)
out=$(bank "customer.create|P|STL RECEBEDOR|CPF|234.567.890-92|19900101|OP01|SC3")
stlrecvc=$(value "$out" id=)
out=$(bank "account.open|$stlrecvc|DMND|BRL|500000|OP01|SC4|O2")
stlpayee=$(value "$out" id=)
out=$(bank "pix.key.register|CPF|234.567.890-92|$stlpayee|$stlrecvc|OP01|COR|SK1")
stlkey=$(value "$out" id=)
out=$(bank "pix.key.seed|CPF|13579111140|$stlrt|FX000000001|FXC0000001|OUT CLIENTE|OP01|COR|SK2")
check "pix.stl.seed" "00" "$(value "$out" rc=)"
stlforeign=$(value "$out" keyid=)

out=$(bank "pix.out.key|$stlkey|100.00|$stlpayer|||pix local|OP01|COR|SK3||Y")
check "pix.stl.local.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|150.00|$stlpayer|||pix externo|OP01|COR|SK4||Y")
stlout=$(value "$out" id=)
check "pix.stl.out.posted" "POSTED" "$(value "$out" status=)"
check "pix.stl.out.settle.pending" "PENDING" "$(value "$out" settle=)"
out=$(bank "pix.in|50.00|$stlpayee|$stlrt|E2ESTL000000000000000000001|EXT-STL-1|PAGADOR EXTERNO|OP01|COR|SK5")
stlin=$(value "$out" id=)
check "pix.stl.in.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|70.00|$stlpayer|||a devolver|OP01|COR|SK6||Y")
stldvl=$(value "$out" id=)
out=$(bank "pix.devol|$stldvl|70.00|estorno integral|OP01|COR|SK7")
check "pix.stl.devol.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.get|$stldvl")
check "pix.stl.devol.status" "DEVOLVED" "$(value "$out" status=)"

out=$(bank "pix.cycle.open|20261002|BRL|OP01|COR|SK8")
check "pix.stl.cycle.open" "00" "$(value "$out" rc=)"
check "pix.stl.cycle.status" "OPEN" "$(value "$out" status=)"
cyc=$(value "$out" cycle=)
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|SK9")
check "pix.stl.accrue.rc" "00" "$(value "$out" rc=)"
check "pix.stl.accrue.cycle" "$cyc" "$(value "$out" cycle=)"
out=$(bank "pix.get|$stlout")
check "pix.stl.out.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.get|$stlin")
check "pix.stl.in.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.get|$stldvl")
check "pix.stl.devol.excluded" "NOT-APPLICABLE" "$(value "$out" settle=)"
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|SK9")
check "pix.stl.accrue.replay" "00" "$(value "$out" rc=)"

out=$(bank "pix.cycle.close|$cyc|OP01|COR|SKA")
check "pix.stl.close" "CLOSED" "$(value "$out" status=)"
out=$(bank "pix.cycle.calc|$cyc|OP01|COR|SKB")
check "pix.stl.calc" "CALCULATED" "$(value "$out" status=)"
check "pix.stl.calc.txns" "0000003" "$(value "$out" txns=)"
check "pix.stl.calc.grosspay" "150.00" "$(value "$out" grosspay=)"
check "pix.stl.calc.grossrcv" "120.00" "$(value "$out" grossrcv=)"
check "pix.stl.calc.net" "30.00" "$(value "$out" net=)"
check "pix.stl.calc.side" "PAYABLE" "$(value "$out" side=)"
check "pix.stl.calc.parties" "0000001" "$(value "$out" parties=)"

out=$(bank "pix.cycle.submit|$cyc||OP01|COR|SKC")
check "pix.stl.cycle.submit" "SUBMITTED" "$(value "$out" status=)"
out=$(bank "pix.stl.list|$cyc")
check "pix.stl.submit.count" "0000002" "$(value "$out" settlements=)"
check "pix.stl.submit.status" "SUBMITTED" "$(grep -c 'status=SUBMITTED' <<<"$out" | tr -d ' ')"
stl1=$(grep -F "side=PAYABLE" -B2 <<<"$out" | grep -F "settlement=" | head -1 | sed 's/^settlement=//;s/[[:space:]]*$//')
stl2=$(bank "pix.stl.list|$cyc" | grep -F "settlement=" | tail -1 | sed 's/^settlement=//;s/[[:space:]]*$//')
out=$(bank "pix.stl.get|$stl1")
check "pix.stl.get.participant" "$stlrt" "$(value "$out" participant=)"
check "pix.stl.get.extref" "SPIS-00000000001" "$(value "$out" extref=)"
out=$(bank "pix.cycle.submit|$cyc||OP01|COR|SKC")
check "pix.stl.submit.replay.attempts" "0001" "$(bank "pix.stl.get|$stl1" | grep -F "attempts=" | sed 's/^attempts=//;s/[[:space:]]*$//')"

out=$(bank "pix.stl.result|$stl1||SETTLED|SPIRES-1|valor divergente|140.00|OP01|COR|SKD")
check "pix.stl.result.mismatch.rc" "00" "$(value "$out" rc=)"
check "pix.stl.result.mismatch.settled" "140.00" "$(value "$out" settledamt=)"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-BAD||OP01|COR|SKE")
check "pix.stl.recon.bad.rc" "00" "$(value "$out" rc=)"
check "pix.stl.recon.bad.status" "EXCEPTIONS" "$(value "$out" msg=)"
check "pix.stl.recon.bad.open" "000000002" "$(value "$out" openexc=)"
out=$(bank "reconciliation.exceptions|REC-STL-BAD")
case "$out" in
    *AMT_MISMATCH*) stm=yes ;;
    *) stm=no ;;
esac
check "pix.stl.recon.amount.mismatch.code" "yes" "$stm"
case "$out" in
    *STALE_SETTLE*) sts=yes ;;
    *) sts=no ;;
esac
check "pix.stl.recon.stale.code" "yes" "$sts"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|SKF")
check "pix.stl.recon.cycle.exc" "RECON-EXCEPTION" "$(value "$out" status=)"

out=$(bank "pix.stl.result|$stl1||SETTLED|SPIRES-1B|valor correto|150.00|OP01|COR|SKG")
check "pix.stl.result.fixed" "SETTLED" "$(value "$out" status=)"
check "pix.stl.result.fixed.amount" "150.00" "$(value "$out" settledamt=)"
out=$(bank "pix.stl.result|$stl2||SETTLED|SPIRES-2|ok|50.00|OP01|COR|SKH")
check "pix.stl.result.in" "SETTLED" "$(value "$out" status=)"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|SKI")
check "pix.stl.finalize" "SETTLED" "$(value "$out" status=)"
check "pix.stl.finalize.post" "BALANCED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|$stl1|OP01|COR|SKJ")
check "pix.stl.post.pay.rc" "00" "$(value "$out" rc=)"
check "pix.stl.post.pay.status" "POSTED" "$(value "$out" post=)"
stl1jrnl=$(value "$out" journal=)
case "$stl1jrnl" in
    STL*) jok=yes ;;
    *) jok=no ;;
esac
check "pix.stl.post.journal" "yes" "$jok"
out=$(bank "pix.stl.post|$stl2|OP01|COR|SKK")
check "pix.stl.post.rcv" "POSTED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|$stl1|OP01|COR|SKJ")
check "pix.stl.post.replay" "Y" "$(value "$out" replay=)"
out=$(bank "ledger.balance|$stlpayer")
check "pix.stl.customer.untouched.payer" "489950.00" "$(value "$out" available=)"
out=$(bank "ledger.balance|$stlpayee")
check "pix.stl.customer.untouched.payee" "500230.00" "$(value "$out" available=)"
grep -aq "|D|             150.00|${stlrt}|BRL|STL" var/journal/postings.log && paygl=yes || paygl=no
check "pix.stl.gl.payable.debit" "yes" "$paygl"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-OK||OP01|COR|SKL")
check "pix.stl.recon.ok" "BALANCED" "$(value "$out" msg=)"
check "pix.stl.recon.ok.matched" "000000002" "$(value "$out" matched=)"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|SKM")
check "pix.stl.cycle.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.cycle.recon" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.stl.get|$stl1")
check "pix.stl.obligation.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.obligation.matched" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.pos.list")
check "pix.stl.position.count" "0000001" "$(value "$out" positions=)"
check "pix.stl.position.settledpay" "150.00" "$(value "$out" settledpay=)"
check "pix.stl.position.settledrcv" "50.00" "$(value "$out" settledrcv=)"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|SKN")
check "pix.stl.finalize.replay" "Y" "$(value "$out" replay=)"

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
check "pix.stl.rt.self" "ACTIVE" "$(value "$out" status=)"
out=$(bank "pix.rt.create|87654321|BANCO OUTRO|DEBITS|DPI|N||OP01|COR|SRT2")
stlrt=$(value "$out" id=)
out=$(bank "customer.create|P|STL PAGADOR|CPF|123.456.789-09|19900101|OP01|SC1")
out=$(bank "account.open|$(value "$out" id=)|DMND|BRL|500000|OP01|SC2|O1")
stlpayer=$(value "$out" id=)
out=$(bank "customer.create|P|STL RECEBEDOR|CPF|234.567.890-92|19900101|OP01|SC3")
stlrecvc=$(value "$out" id=)
out=$(bank "account.open|$stlrecvc|DMND|BRL|500000|OP01|SC4|O2")
stlpayee=$(value "$out" id=)
out=$(bank "pix.key.register|CPF|234.567.890-92|$stlpayee|$stlrecvc|OP01|COR|SK1")
stlkey=$(value "$out" id=)
out=$(bank "pix.key.seed|CPF|13579111140|$stlrt|FX000000001|FXC0000001|OUT CLIENTE|OP01|COR|SK2")
check "pix.stl.seed" "00" "$(value "$out" rc=)"
stlforeign=$(value "$out" keyid=)

out=$(bank "pix.out.key|$stlkey|100.00|$stlpayer|||pix local|OP01|COR|SK3||Y")
check "pix.stl.local.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|150.00|$stlpayer|||pix externo|OP01|COR|SK4||Y")
stlout=$(value "$out" id=)
check "pix.stl.out.posted" "POSTED" "$(value "$out" status=)"
check "pix.stl.out.settle.pending" "PENDING" "$(value "$out" settle=)"
out=$(bank "pix.in|50.00|$stlpayee|$stlrt|E2ESTL000000000000000000001|EXT-STL-1|PAGADOR EXTERNO|OP01|COR|SK5")
stlin=$(value "$out" id=)
check "pix.stl.in.posted" "POSTED" "$(value "$out" status=)"
out=$(bank "pix.out.key|$stlforeign|70.00|$stlpayer|||a devolver|OP01|COR|SK6||Y")
stldvl=$(value "$out" id=)
out=$(bank "pix.devol|$stldvl|70.00|estorno integral|OP01|COR|SK7")
check "pix.stl.devol.rc" "00" "$(value "$out" rc=)"
out=$(bank "pix.get|$stldvl")
check "pix.stl.devol.status" "DEVOLVED" "$(value "$out" status=)"

out=$(bank "pix.cycle.open|20261002|BRL|OP01|COR|SK8")
check "pix.stl.cycle.open" "00" "$(value "$out" rc=)"
check "pix.stl.cycle.status" "OPEN" "$(value "$out" status=)"
cyc=$(value "$out" cycle=)
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|SK9")
check "pix.stl.accrue.rc" "00" "$(value "$out" rc=)"
check "pix.stl.accrue.cycle" "$cyc" "$(value "$out" cycle=)"
out=$(bank "pix.get|$stlout")
check "pix.stl.out.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.get|$stlin")
check "pix.stl.in.accumulated" "ACCUMULATED" "$(value "$out" settle=)"
out=$(bank "pix.get|$stldvl")
check "pix.stl.devol.excluded" "NOT-APPLICABLE" "$(value "$out" settle=)"
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|SK9")
check "pix.stl.accrue.replay" "00" "$(value "$out" rc=)"

out=$(bank "pix.cycle.close|$cyc|OP01|COR|SKA")
check "pix.stl.close" "CLOSED" "$(value "$out" status=)"
out=$(bank "pix.cycle.calc|$cyc|OP01|COR|SKB")
check "pix.stl.calc" "CALCULATED" "$(value "$out" status=)"
check "pix.stl.calc.txns" "0000003" "$(value "$out" txns=)"
check "pix.stl.calc.grosspay" "150.00" "$(value "$out" grosspay=)"
check "pix.stl.calc.grossrcv" "120.00" "$(value "$out" grossrcv=)"
check "pix.stl.calc.net" "30.00" "$(value "$out" net=)"
check "pix.stl.calc.side" "PAYABLE" "$(value "$out" side=)"
check "pix.stl.calc.parties" "0000001" "$(value "$out" parties=)"

out=$(bank "pix.cycle.submit|$cyc||OP01|COR|SKC")
check "pix.stl.cycle.submit" "SUBMITTED" "$(value "$out" status=)"
out=$(bank "pix.stl.list|$cyc")
check "pix.stl.submit.count" "0000002" "$(value "$out" settlements=)"
check "pix.stl.submit.status" "SUBMITTED" "$(grep -c 'status=SUBMITTED' <<<"$out" | tr -d ' ')"
stl1=$(grep -F "side=PAYABLE" -B2 <<<"$out" | grep -F "settlement=" | head -1 | sed 's/^settlement=//;s/[[:space:]]*$//')
stl2=$(bank "pix.stl.list|$cyc" | grep -F "settlement=" | tail -1 | sed 's/^settlement=//;s/[[:space:]]*$//')
out=$(bank "pix.stl.get|$stl1")
check "pix.stl.get.participant" "$stlrt" "$(value "$out" participant=)"
check "pix.stl.get.extref" "SPIS-00000000001" "$(value "$out" extref=)"
out=$(bank "pix.cycle.submit|$cyc||OP01|COR|SKC")
check "pix.stl.submit.replay.attempts" "0001" "$(bank "pix.stl.get|$stl1" | grep -F "attempts=" | sed 's/^attempts=//;s/[[:space:]]*$//')"

out=$(bank "pix.stl.result|$stl1||SETTLED|SPIRES-1|valor divergente|140.00|OP01|COR|SKD")
check "pix.stl.result.mismatch.rc" "00" "$(value "$out" rc=)"
check "pix.stl.result.mismatch.settled" "140.00" "$(value "$out" settledamt=)"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-BAD||OP01|COR|SKE")
check "pix.stl.recon.bad.rc" "00" "$(value "$out" rc=)"
check "pix.stl.recon.bad.status" "EXCEPTIONS" "$(value "$out" msg=)"
check "pix.stl.recon.bad.open" "000000002" "$(value "$out" openexc=)"
out=$(bank "reconciliation.exceptions|REC-STL-BAD")
case "$out" in
    *AMT_MISMATCH*) stm=yes ;;
    *) stm=no ;;
esac
check "pix.stl.recon.amount.mismatch.code" "yes" "$stm"
case "$out" in
    *STALE_SETTLE*) sts=yes ;;
    *) sts=no ;;
esac
check "pix.stl.recon.stale.code" "yes" "$sts"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|SKF")
check "pix.stl.recon.cycle.exc" "RECON-EXCEPTION" "$(value "$out" status=)"

out=$(bank "pix.stl.result|$stl1||SETTLED|SPIRES-1B|valor correto|150.00|OP01|COR|SKG")
check "pix.stl.result.fixed" "SETTLED" "$(value "$out" status=)"
check "pix.stl.result.fixed.amount" "150.00" "$(value "$out" settledamt=)"
out=$(bank "pix.stl.result|$stl2||SETTLED|SPIRES-2|ok|50.00|OP01|COR|SKH")
check "pix.stl.result.in" "SETTLED" "$(value "$out" status=)"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|SKI")
check "pix.stl.finalize" "SETTLED" "$(value "$out" status=)"
check "pix.stl.finalize.post" "BALANCED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|$stl1|OP01|COR|SKJ")
check "pix.stl.post.pay.rc" "00" "$(value "$out" rc=)"
check "pix.stl.post.pay.status" "POSTED" "$(value "$out" post=)"
stl1jrnl=$(value "$out" journal=)
case "$stl1jrnl" in
    STL*) jok=yes ;;
    *) jok=no ;;
esac
check "pix.stl.post.journal" "yes" "$jok"
out=$(bank "pix.stl.post|$stl2|OP01|COR|SKK")
check "pix.stl.post.rcv" "POSTED" "$(value "$out" post=)"
out=$(bank "pix.stl.post|$stl1|OP01|COR|SKJ")
check "pix.stl.post.replay" "Y" "$(value "$out" replay=)"
out=$(bank "ledger.balance|$stlpayer")
check "pix.stl.customer.untouched.payer" "489950.00" "$(value "$out" available=)"
out=$(bank "ledger.balance|$stlpayee")
check "pix.stl.customer.untouched.payee" "500230.00" "$(value "$out" available=)"
grep -aq "|D|             150.00|${stlrt}|BRL|STL" var/journal/postings.log && paygl=yes || paygl=no
check "pix.stl.gl.payable.debit" "yes" "$paygl"
out=$(bank "reconciliation.run|PIXSTL|REC-STL-OK||OP01|COR|SKL")
check "pix.stl.recon.ok" "BALANCED" "$(value "$out" msg=)"
check "pix.stl.recon.ok.matched" "000000002" "$(value "$out" matched=)"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|SKM")
check "pix.stl.cycle.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.cycle.recon" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.stl.get|$stl1")
check "pix.stl.obligation.reconciled" "RECONCILED" "$(value "$out" status=)"
check "pix.stl.obligation.matched" "MATCHED" "$(value "$out" recon=)"
out=$(bank "pix.pos.list")
check "pix.stl.position.count" "0000001" "$(value "$out" positions=)"
check "pix.stl.position.settledpay" "150.00" "$(value "$out" settledpay=)"
check "pix.stl.position.settledrcv" "50.00" "$(value "$out" settledrcv=)"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|SKN")
check "pix.stl.finalize.replay" "Y" "$(value "$out" replay=)"

cp "$CFG_BAK" etc/bank.cfg

echo "tests: $((PASS + FAIL)) passed: $PASS failed: $FAIL"
[ "$FAIL" -eq 0 ]
