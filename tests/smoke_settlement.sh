#!/usr/bin/env bash
set -uo pipefail
cd /home/mel/kofbank
export BANK_HOME=$PWD COB_LIBRARY_PATH=$PWD/build
BANK="build/bank"
bank() { printf '%s\n' "$1" | "$BANK"; }
value() { grep -F "$2" <<<"$1" | head -1 | sed 's/^[^=]*=//' | tr -d ' '; }
show() { echo "--- $1"; echo "$2"; }

rm -rf var/data var/journal var/audit; mkdir -p var/data var/journal var/audit
sed -i 's/^business-date=.*/business-date=2026-10-02/' etc/bank.cfg

bank "ledger.init" >/dev/null
out=$(bank "pix.rt.create|12345678|KOF SELF|DEBITS|DPI|Y||OP01|CORP|PRT1"); show rt.self "$out"
out=$(bank "pix.rt.create|87654321|BANCO OUTRO|DEBITS|DPI|N||OP01|CORP|PRT2"); show rt.other "$out"
rtid=$(value "$out" id=)
out=$(bank "customer.create|P|PIX PAGADOR|CPF|123.456.789-09|19900101|OP01|PX1")
pixa1=$(value "$out" id=)
out=$(bank "account.open|$pixa1|DMND|BRL|500000|OP01|PX2|O1")
pixa1=$(value "$out" id=)
out=$(bank "customer.create|P|PIX RECEBEDOR|CPF|234.567.890-92|19900101|OP01|PX3")
pixc2=$(value "$out" id=)
out=$(bank "account.open|$pixc2|DMND|BRL|500000|OP01|PX4|O2")
pixa2=$(value "$out" id=)
out=$(bank "pix.key.register|CPF|234.567.890-92|$pixa2|$pixc2|OP01|COR|KR1")
pixkey=$(value "$out" id=)
out=$(bank "pix.key.seed|CPF|13579111140|$rtid|FX000000001|FXCUST0001|OUT CLIENT|OP01|COR|KS1")
show seed "$out"
seckey=$(value "$out" keyid=)
out=$(bank "pix.out.key|$pixkey|100.00|$pixa1|||local pay|OP01|COR|PK1||Y")
show out.local "$out"
out=$(bank "pix.out.key|$seckey|150.00|$pixa1|||external pay|OP01|COR|PK2||Y")
show out.ext "$out"
out=$(bank "pix.in|50.00|$pixa2|$rtid|E2ESET000000000000000000001|EXT-IN-1|EXT PAYER|OP01|COR|PIN1")
show in "$out"
out=$(bank "pix.cycle.open|20261002|BRL|OP01|COR|CO1"); show cycle.open "$out"
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|CO2"); show cycle.accrue "$out"
cyc=$(value "$out" cycle=)
out=$(bank "pix.cycle.close|$cyc|OP01|COR|CO3"); show cycle.close "$out"
out=$(bank "pix.cycle.calc|$cyc|OP01|COR|CO4"); show cycle.calc "$out"
out=$(bank "pix.cycle.submit|$cyc||OP01|COR|CO5"); show cycle.submit "$out"
out=$(bank "pix.stl.list|$cyc"); show stl.list "$out"
out=$(bank "pix.stl.get|S00000000001"); show stl.get "$out"
out=$(bank "pix.stl.result|S00000000001||SETTLED|SPIRES-1|ok|OP01|COR|RS1"); show stl.result "$out"
out=$(bank "pix.stl.result|S00000000002||SETTLED|SPIRES-2|ok|OP01|COR|RS2"); show stl.result2 "$out"
out=$(bank "pix.cycle.finalize|$cyc|OP01|COR|CO6"); show cycle.finalize2 "$out"
out=$(bank "pix.stl.post|S00000000001|OP01|COR|CP1"); show stl.post1 "$out"
out=$(bank "pix.stl.post|S00000000002|OP01|COR|CP2"); show stl.post2 "$out"
out=$(bank "pix.pos.rebuild||BRL|OP01|COR|PR1"); show pos.rebuild "$out"
out=$(bank "pix.pos.list"); show pos.list "$out"
out=$(bank "reconciliation.run|PIXSTL|REC-PIXSTL||OP01|CORX|RNX1"); show recon "$out"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|CO7"); show cycle.after "$out"
out=$(bank "pix.stl.get|S00000000001|OP01|COR|SG2"); show stl.after "$out"
out=$(bank "ledger.balance|7000"); show gl.7000 "$out"
out=$(bank "ledger.balance|1000"); show gl.1000 "$out"
out=$(bank "ledger.balance|$pixa1"); show cust.payer "$out"
out=$(bank "ledger.balance|$pixa2"); show cust.payee "$out"
out=$(bank "ledger.trial|20261002"); show gl.trial "$out"
