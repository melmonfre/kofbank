#!/usr/bin/env bash
set -uo pipefail

BANK="build/bank"
PASS=0
FAIL=0

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
check "product.init" "00008" "$(value "$out" products=)"
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
cp etc/bank.cfg /tmp/kofbank.cfg.bak
sed -i 's/business-date=.*/business-date=2026-10-03/' etc/bank.cfg
out=$(bank "batch.eod|OP01|R99|EOD9")
check "recon.eod.fails.open" "20" "$(value "$out" rc=)"
cp /tmp/kofbank.cfg.bak etc/bank.cfg

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
cp etc/bank.cfg /tmp/kofbank.cfg.bak
sed -i 's/business-date=.*/business-date=2027-01-15/' etc/bank.cfg
out=$(bank "batch.eod|OP01|D10|DEOD")
check "credit.eod.overdue.rc" "00" "$(value "$out" rc=)"
out=$(bank "credit.facility.exposure|F00000000001")
check "credit.eod.overdue.amount" "30622.20" "$(value "$out" overdue=)"
out=$(bank "reconciliation.run|CREDIT|REC-CRD2")
check "credit.recon.after.eod" "BALANCED" "$(value "$out" msg=)"
cp /tmp/kofbank.cfg.bak etc/bank.cfg

echo "tests: $((PASS + FAIL)) passed: $PASS failed: $FAIL"
[ "$FAIL" -eq 0 ]
