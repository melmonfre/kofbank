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
bank "pix.rt.create|12345678|KOF SELF|DEBITS|DPI|Y||OP01|CORP|PRT1" >/dev/null
out=$(bank "pix.rt.create|87654321|BANCO OUTRO|DEBITS|DPI|N||OP01|CORP|PRT2")
rtid=$(value "$out" id=)
out=$(bank "customer.create|P|PIX PAGADOR|CPF|123.456.789-09|19900101|OP01|PX1")
pixc1=$(value "$out" id=)
out=$(bank "account.open|$pixc1|DMND|BRL|500000|OP01|PX2|O1")
pixa1=$(value "$out" id=)
out=$(bank "customer.create|P|PIX RECEBEDOR|CPF|234.567.890-92|19900101|OP01|PX3")
pixc2=$(value "$out" id=)
out=$(bank "account.open|$pixc2|DMND|BRL|500000|OP01|PX4|O2")
pixa2=$(value "$out" id=)
out=$(bank "pix.key.seed|CPF|13579111140|$rtid|FX000000001|FXCUST0001|OUT CLIENT|OP01|COR|KS1")
seckey=$(value "$out" keyid=)

bank "pix.out.key|$seckey|150.00|$pixa1|||payable|OP01|COR|PK1||Y" >/dev/null
bank "pix.in|50.00|$pixa2|$rtid|E2ESET000000000000000000002|EXT-IN-2|EXT PAYER|OP01|COR|PIN1" >/dev/null
out=$(bank "pix.cycle.accrue|20261002|BRL||OP01|COR|CO1"); cyc=$(value "$out" cycle=)
bank "pix.cycle.close|$cyc|OP01|COR|CO2" >/dev/null
bank "pix.cycle.calc|$cyc|OP01|COR|CO3" >/dev/null
out=$(bank "pix.cycle.submit|$cyc||OP01|COR|CO4"); show submit "$out"
s1=$(bank "pix.stl.list|$cyc" | grep -F "settlement=" | sed -n "1p" | sed "s/^settlement=//;s/ *$//")
s2=$(bank "pix.stl.list|$cyc" | grep -F "settlement=" | sed -n "2p" | sed "s/^settlement=//;s/ *$//")
echo "obligations: $s1 $s2"

out=$(bank "pix.stl.result|$s1||SETTLED|SPIRES-BAD|wrong amount|140.00|OP01|COR|RS1")
show result.mismatch "$out"
out=$(bank "reconciliation.run|PIXSTL|REC-PIX-BAD||OP01|CORX|RNB1"); show recon.bad "$out"
out=$(bank "pix.cycle.get|$cyc|OP01|COR|CO5"); show cycle.bad "$out"
out=$(bank "pix.stl.list|$cyc"); show stl.bad "$out"
