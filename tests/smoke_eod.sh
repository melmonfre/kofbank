#!/usr/bin/env bash
set -uo pipefail
cd /home/mel/kofbank
export BANK_HOME=$PWD COB_LIBRARY_PATH=$PWD/build
BANK="build/bank"
bank() { printf '%s\n' "$1" | "$BANK"; }
value() { grep -F "$2" <<<"$1" | head -1 | sed 's/^[^=]*=//' | tr -d ' '; }
show() { echo "--- $1"; echo "$2"; }

rm -rf var/data var/journal var/audit var/out; mkdir -p var/data var/journal var/audit var/out
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

bank "pix.out.key|$seckey|150.00|$pixa1|||eod payable|OP01|COR|EK1||Y" >/dev/null
bank "pix.in|50.00|$pixa2|$rtid|E2EEOD0000000000000000000001|EXT-EOD-1|EXT PAYER|OP01|COR|EI1" >/dev/null

out=$(bank "batch.eod|BATCH|EODPX1|EODP1"); show eod "$out"
echo "--- report"
grep -E "PIX-EOD|RECON-PIXSTL" var/out/eod_20261002.txt
out=$(bank "pix.stl.list|CYC20261002BRL123456"); show stl.list "$out"
out=$(bank "pix.cycle.get|CYC20261002BRL123456"); show cycle "$out"
out=$(bank "pix.pos.list"); show pos "$out"
out=$(bank "ledger.trial"); show trial "$out"
out=$(bank "batch.eod|BATCH|EODPX1|EODP2"); show eod.rerun "$out"
out=$(bank "reconciliation.run|PIXSTL|REC-PIX-EOD2||OP01|CORX|RNE2"); show recon.rerun "$out"
