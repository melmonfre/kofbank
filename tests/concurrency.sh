#!/usr/bin/env bash
# KofBank cross-process concurrency adversarial suite.
# Real OS-level serialization: BLCK registry flock + BSEQ per-key flock +
# BWR leaf store locks (WR-TXN/ACCT/CUST/LEDGER/RC). See ADR 0022.
# Barrier = flag file all workers spin on, then release -> tight simultaneous
# multi-process contention. KOF_CRASH seams give deterministic crash points;
# SIGKILL used only to prove kernel auto-release of flocks on process death.
set -u
cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
export BANK_HOME="$ROOT"
export COB_LIBRARY_PATH="$ROOT/build"
BANK="$ROOT/build/bank"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }
chk() { if [ "$2" = "$3" ]; then ok "$1 ($2)"; else bad "$1: expected [$3] got [$2]"; fi; }
bank() { printf '%s\n' "$1" | timeout 90 "$BANK" 2>/dev/null | tr -d '\r'; }

BARRIER=""
mkbar() { BARRIER="/tmp/kfbar.$$.$RANDOM"; rm -rf "$BARRIER"; mkdir -p "$BARRIER"; }
go()    { : > "$BARRIER/go"; }
rmbbar() { rm -rf "$BARRIER"; }
# worker: spin until released, then run one one-shot CLI request
worker() { local line=$1 out=$2; while [ ! -f "$BARRIER/go" ]; do :; done;
           printf '%s\n' "$line" > "$out"; timeout 90 "$BANK" < "$out" 2>&1 | tr -d '\r' > "${out}.res"; }

new_home() {
  rm -rf var/data var/journal var/run; mkdir -p var/data var/journal var/run
  bank 'ledger.init' >/dev/null
  bank 'customer.create|J|HA|CNPJ|61010101000101|20261007|S|c1' >/dev/null
  bank 'customer.create|J|HB|CNPJ|61010101000290|20261007|S|c2' >/dev/null
  bank 'account.open|C00000000001|DMND|BRL|10000000|S|o1|OA1' >/dev/null
  bank 'account.open|C00000000002|DMND|BRL|0|S|o2|OA2' >/dev/null
}

echo "== 1) distinct requestId create (id uniqueness + no lost write) =="
new_home; mkbar
for i in $(seq 1 12); do worker "txn.create|TRANSFER|A00000000001|A00000000002|500|BRL|m|S|c|ID$i" "/tmp/kf1_$i" & done
sleep 0.1; go; wait; rmbbar
ids=$(cat /tmp/kf1_*.res 2>/dev/null | grep '^id=' | awk -F= '{print $2}')
chk "unique ids = 12" "$(printf '%s\n' "$ids" | grep . | sort -u | wc -l)" "12"
chk "all accepted = 12" "$(printf '%s\n' "$ids" | grep -c .)" "12"
chk "store holds 12 (no silent ISAM loss)" "$(bank 'txn.list|' | grep -c '^id=')" "12"
rm -f /tmp/kf1_*

echo "== 2) concurrent SAME requestId (idempotent, one effect) =="
new_home; mkbar
for i in $(seq 1 6); do worker 'txn.create|TRANSFER|A00000000001|A00000000002|777|BRL|m|S|cc|REQ-SAME' "/tmp/kf2_$i" & done
sleep 0.1; go; wait; rmbbar
sid=$(cat /tmp/kf2_*.res 2>/dev/null | grep '^id=' | awk -F= '{print $2}' | sort -u)
chk "same requestId -> single distinct id" "$(printf '%s\n' "$sid" | grep -c .)" "1"
chk "store holds exactly 1 record" "$(bank 'txn.list|' | grep -c '^id=')" "1"
rm -f /tmp/kf2_*

echo "== 3) same requestId + different payload (must reject) =="
new_home
bank 'txn.create|TRANSFER|A00000000001|A00000000002|1000|BRL|m|S|cc|REQ-CF' >/dev/null
b=$(bank 'txn.create|TRANSFER|A00000000001|A00000000002|2000|BRL|m|S|cc|REQ-CF')
chk "conflict rejected rc=26" "$(printf '%s\n' "$b" | grep '^rc=' | awk -F= '{print $2}')" "26"

echo "== 4) concurrent create + list (no crash, no torn read) =="
new_home; mkbar
for i in $(seq 1 6); do worker "txn.create|DEPOSIT||A00000000001|300|BRL|m|S|d|D$i" "/tmp/kf4_$i" & done
for i in 7 8 9 10; do worker 'txn.list|' "/tmp/kf4_$i" & done
sleep 0.1; go; wait; rmbbar
chk "6 deposits present" "$(bank 'txn.list|' | grep -c '^id=')" "6"
rm -f /tmp/kf4_*

echo "== 5) concurrent full transfer lifecycle (money conservation) =="
new_home
b0=$(bank 'ledger.balance|A00000000001' | awk -F= '/^ledger=/{print $2}' | tr -d ' ')
mkbar
xfer() { local n=$1 T
  T=$(bank "txn.create|TRANSFER|A00000000001|A00000000002|100000|BRL|m|S|tcr|TX$n" | awk -F= '/^id=/{print $2}' | tr -d ' ')
  bank "txn.authorize|$T|S|tcr|A$n" >/dev/null; bank "txn.post|$T|S|tcr|P$n" >/dev/null; bank "txn.settle|$T|S|tcr|S$n" >/dev/null; }
for i in $(seq 1 8); do ( while [ ! -f "$BARRIER/go" ]; do :; done; xfer $i ) & done
sleep 0.1; go; wait; rmbbar
b1=$(bank 'ledger.balance|A00000000001' | awk -F= '/^ledger=/{print $2}' | tr -d ' ')
b2=$(bank 'ledger.balance|A00000000002' | awk -F= '/^ledger=/{print $2}' | tr -d ' ')
chk "A1 net -800000 (no lost update)" "$b1" "9200000.00"
chk "A2 net +800000 (no lost update)" "$b2" "800000.00"
chk "conservation (A1+A2 == opening)" "$(python3 -c "print(float('$b1')+float('$b2')==float('$b0'))")" "True"
imb=$(bank 'ledger.trial' | grep 'imbalance=' | awk -F= '{print $2}' | tr -d ' ')
chk "trial imbalance 0.00" "${imb:-0.00}" "0.00"

echo "== 6) crash after balance then recover (exactly-once) =="
new_home
T=$(bank 'txn.create|TRANSFER|A00000000001|A00000000002|654321|BRL|m|S|cr|SEAM1' | awk -F= '/^id=/{print $2}' | tr -d ' ')
bank "txn.authorize|$T|S|cr|AU" >/dev/null
printf '%s\n' "txn.post|$T|S|cr|PO" | KOF_CRASH=AFTER-BAL timeout 20 "$BANK" >/dev/null 2>&1
bank "txn.recover|$T|S|cr|RC" >/dev/null
chk "balance after recover == 654321.00 (once)" "$(bank 'ledger.balance|A00000000002' | awk -F= '/^ledger=/{print $2}' | tr -d ' ')" "654321.00"
chk "txn committed after recover" "$(bank "txn.get|$T" | grep '^status=' | awk -F= '{print $2}')" "PO"

echo "== 7) SIGKILL during lifecycle -> kernel auto-releases flock (no stall) =="
new_home; mkbar
for i in $(seq 1 6); do worker "txn.create|TRANSFER|A00000000001|A00000000002|1000|BRL|m|S|k|KILL$i" "/tmp/kf7_$i" & done
sleep 0.05; go; ( sleep 0.04; pkill -9 -f 'build/bank' 2>/dev/null ) &
wait 2>/dev/null; rmbbar
fresh=$(bank 'txn.create|TRANSFER|A00000000001|A00000000002|111|BRL|m|S|z|POSTKILL')
chk "new create succeeds after SIGKILL (rc=00)" "$(printf '%s\n' "$fresh" | grep '^rc=' | awk -F= '{print $2}')" "00"
rm -f /tmp/kf7_*

echo "== 8) concurrent recovery + creation (exactly-once, CLEAN) =="
new_home; ids=()
for i in 1 2 3; do
  T=$(bank "txn.create|TRANSFER|A00000000001|A00000000002|5000|BRL|m|S|cr|R$i" | awk -F= '/^id=/{print $2}' | tr -d ' ')
  bank "txn.authorize|$T|S|cr|A$i" >/dev/null
  printf '%s\n' "txn.post|$T|S|cr|P$i" | KOF_CRASH=AFTER-JRN timeout 20 "$BANK" >/dev/null 2>&1
  ids+=("$T")
done
mkbar
for j in 0 1 2; do worker "txn.recover|${ids[$j]}|S|cr|RC$j" "/tmp/kf8r_$j" & done
for j in 1 2; do worker "txn.create|DEPOSIT||A00000000001|700|BRL|m|S|n|NEWC$j" "/tmp/kf8c_$j" & done
sleep 0.1; go; wait; rmbbar
chk "recovered total = 15000.00 (three exactly-once)" "$(bank 'ledger.balance|A00000000002' | awk -F= '/^ledger=/{print $2}' | tr -d ' ')" "15000.00"
imbb=$(bank 'ledger.trial' | grep 'imbalance=' | awk -F= '{print $2}' | tr -d ' ')
chk "trial imbalance 0.00" "${imbb:-0.00}" "0.00"
rm -f /tmp/kf8*

echo "== 9) interrupted identifier allocation (crash between reserve and record) =="
new_home
before=$(bank 'txn.list|' | grep -c '^id=')
c1=$(KOF_CRASH=AFTER-SEQ bank 'txn.create|TRANSFER|A00000000001|A00000000002|500|BRL|m|S|c|SEAMA' | grep '^rc=' | awk -F= '{print $2}')
[ "$c1" = "90" ] && ok "AFTER-SEQ seam aborts create (rc=90)" || bad "expected rc=90 got [$c1]"
chk "no record written by aborted create" "$(bank 'txn.list|' | grep -c '^id=')" "$before"
d1=$(bank 'txn.create|TRANSFER|A00000000001|A00000000002|500|BRL|m|S|c|SEAMB' | grep '^id=' | awk -F= '{print $2}')
d2=$(bank 'txn.create|TRANSFER|A00000000001|A00000000002|500|BRL|m|S|c|SEAMC' | grep '^id=' | awk -F= '{print $2}')
[ "$d1" != "$d2" ] && [ -n "$d1" ] && ok "restart allocation resumes uniquely ($d1,$d2)" || bad "post-seam ids collided"
cnt=$(bank 'txn.list|' | grep -c '^id=')
chk "durable count = 2 after seam restart" "$cnt" "2"
seqv=$(tr -dc '0-9' < var/data/seq_TRANSACTION.dat 2>/dev/null); seqv=${seqv:-0}
maxid=$(bank 'txn.list|' | grep -oE 'id=T[0-9]+' | sed 's/id=T//' | sort -n | tail -1); maxid=${maxid:-0}
[ $((10#$seqv)) -ge $((10#$maxid)) ] && ok "seq counter >= max minted id (gap tolerated, no reuse)" || bad "seq < max id (seqv=$seqv maxid=$maxid)"

echo "== 10) contention bounded timeout, later success, fail-closed without fallback =="
new_home
LF="$ROOT/build/lockhelper"; ABS="$ROOT/var/data"
rm -f /tmp/lhhold.out
"$LF" acquire - "$ABS" REGISTRY-LOCKIDX 2 > /tmp/lhhold.out 2>&1 &
HP=$!
i=0; while [ $i -lt 100 ] && ! grep -q status=00 /tmp/lhhold.out; do sleep 0.1; i=$((i+1)); done
grep -q status=00 /tmp/lhhold.out && ok "independent holder acquired registry lock" || bad "holder never acquired"
t=$(KOF_LOCK_TIMEOUT_MS=150 "$LF" acquire 150 "$ABS" REGISTRY-LOCKIDX)
chk "waiting process times out with distinct status 62" "$t" "status=62"
rcx=$(KOF_LOCK_TIMEOUT_MS=150 bank 'txn.create|TRANSFER|A00000000001|A00000000002|400|BRL|m|S|c|TO1' | grep '^rc=' | awk -F= '{print $2}')
[ "$rcx" != "00" ] && ok "bank create fails closed under contention (rc=$rcx)" || bad "create succeeded while lock held"
wait $HP
t2=$("$LF" acquire 2000 "$ABS" REGISTRY-LOCKIDX)
chk "acquisition succeeds after holder exits (kernel release)" "$t2" "status=00"
rco=$(bank 'txn.create|TRANSFER|A00000000001|A00000000002|400|BRL|m|S|c|TO2' | grep '^rc=' | awk -F= '{print $2}')
chk "create succeeds after contention clears" "$rco" "00"
self=$(KOF_LOCK_TIMEOUT_MS=150 "$LF" selftest)
chk "no KFLOCK module => explicit EF (no silent fallback)" "$self" "status=EF"

echo "== 11) stale/override protection for live holds (cross-process) =="
new_home
lc=$(bank 'txn.lock|A|HOLD-TEST-01|opA|x' | grep '^rc=' | awk -F= '{print $2}')
chk "owner process acquires hold" "$lc" "00"
listed=$(bank 'ops.locks.list|x' | grep -c 'HOLD-TEST-01')
chk "hold visible to independent processes" "$listed" "1"
bank 'txn.unlock|X|HOLD-TEST-01|opB|x' >/dev/null
still=$(bank 'ops.locks.list|x' | grep -c 'HOLD-TEST-01')
chk "wrong owner cannot remove live hold" "$still" "1"
rel=$(bank 'ops.locks.release|HOLD-TEST-01|auto-sweep|op|c1')
rrc=$(printf '%s\n' "$rel" | grep '^rc=' | awk -F= '{print $2}')
chk "sweeper refuses unexpired lock (rc=20)" "$rrc" "20"
gone=$(bank 'ops.locks.list|x' | grep -c 'HOLD-TEST-01')
chk "refused sweep left lock intact" "$gone" "1"
bank 'txn.unlock|X|HOLD-TEST-01|opA|x' >/dev/null
fin=$(bank 'ops.locks.list|x' | grep -c 'HOLD-TEST-01')
chk "owner release removes hold" "$fin" "0"

echo "== 12) high-contention burst with authoritative durable inspection =="
new_home; mkbar
jd0=$(wc -l < var/journal/journal.log 2>/dev/null || echo 0)
jp0=$(wc -l < var/journal/postings.log 2>/dev/null || echo 0)
for i in $(seq 1 12); do worker "txn.create|TRANSFER|A00000000001|A00000000002|600|BRL|m|S|c|HI$i" "/tmp/kf12a_$i" & done
for i in $(seq 1 6); do  worker 'txn.create|DEPOSIT||A00000000001|900|BRL|m|S|d|REPLAY' "/tmp/kf12b_$i" & done
sleep 0.1; go; wait; rmbbar
aids=$(cat /tmp/kf12a_*.res | grep '^id=' | awk -F= '{print $2}')
chk "12 distinct-request ids unique" "$(printf '%s\n' "$aids" | grep . | sort -u | wc -l)" "12"
rids=$(cat /tmp/kf12b_*.res | grep '^id=' | awk -F= '{print $2}' | sort -u)
chk "6 replays same requestId -> one id" "$(printf '%s\n' "$rids" | grep -c .)" "1"
cnt=$(bank 'txn.list|' | grep -oE 'id=T[0-9]+' | wc -l)
chk "durable txn store holds exactly 13 records" "$cnt" "13"
dupids=$(bank 'txn.list|' | grep -oE 'id=T[0-9]+' | sort | uniq -d | wc -l)
chk "no duplicate ids in durable store" "$dupids" "0"
seqv=$(tr -dc '0-9' < var/data/seq_TRANSACTION.dat 2>/dev/null); seqv=${seqv:-0}
maxid=$(bank 'txn.list|' | grep -oE 'id=T[0-9]+' | sed 's/id=T//' | sort -n | tail -1); maxid=${maxid:-0}
chk "seq counter equals highest minted id" "$((10#$seqv))" "$((10#$maxid))"
jd=$(wc -l < var/journal/journal.log 2>/dev/null || echo 0)
jp=$(wc -l < var/journal/postings.log 2>/dev/null || echo 0)
chk "no new journal lines from creates" "$jd" "$jd0"
chk "no new posting lines from creates" "$jp" "$jp0"
imbb2=$(bank 'ledger.trial' | grep 'imbalance=' | awk -F= '{print $2}' | tr -d ' ')
chk "trial imbalance 0.00 after burst" "${imbb2:-0.00}" "0.00"
lok=$(bank 'ops.locks.list|x' | grep -c 'LOCK ')
chk "no locks left after burst" "$lok" "0"

echo "== 13) global invariants =="
insp=$(bank 'ops.inspect' | grep '^class=' | awk -F= '{print $2}')
ok "ops.inspect class=[$insp]"
[ "$insp" = "CORRUPT" ] && bad "store classified CORRUPT" || ok "store not CORRUPT"

echo
echo "concurrency: passed=$pass failed=$fail"
[ "$fail" -eq 0 ] || exit 1
