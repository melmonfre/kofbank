# Collections Catalog

domain: collections  
engine: cobol/collections  
status: implemented  
proof: make test (collections.* cases, 320 tests green)

## Scope

Collections consumes authoritative financial state. It never writes balances,
ledger postings, or payment records directly. Money effects flow through:

```
recovery.post -> loans.repay (BLRPAY) -> transaction -> ledger -> account
collections case/promise/arrangement/action/handoff = state + obligations only
```

Reconciliation (`reconciliation.run|COLLECT`) matches case recovered totals
against recovery postings (`RV-APPLIED`, status POSTED).

## Records

| file | copybook | key | fields |
|---|---|---|---|
| colcase.idx | COLC | CC-ID | loan, cust, status, stage, strategy, overdue, recovered, delinq-date, promise, arrangement |
| colpromise.idx | COLP | PM-ID | case, status, amount, paid, txn-ref, promise-date |
| colarrange.idx | COLAG | AG-ID | case, status, total, paid, installments |
| colaction.idx | COLA | AL-ID | case, type, status, due |
| colhandoff.idx | COLH | HD-ID | case, kind, status, provider, ref, amount |
| colrec.idx | COLRC | RV-ID | case, loan, txn, amount, applied, excess, status, plan |

## Case lifecycle

```
OPEN -> INCO (activate)
INCO -> PREC (recovery posted) -> PREC (more recoveries)
INCO/PREC -> ESC (escalate / promise broken / handoff)
OPEN/INCO/PREC/ESC -> REC (fully recovered) -> CLOS (close)
OPEN/INCO -> CANC (cancel), FAIL (fail)
CLOS/FAIL/CANC -> INCO (reopen)
```

Stage/strategy/priority from `CLOVER` (BK-COL-DELINQ): aging buckets by
`OV-AGE` from earliest past-due installment (`first-due` fallback); policy
thresholds via `COLCFG` / facility config. No regulatory scoring invented:
strategy is operational routing, documented as configurable thresholds.

## Money semantics

- `recovery.post` calls `BLRPAY`; `RV-AMOUNT` = cash posted, `RV-APPLIED` =
  portion charged against delinquency, `RV-EXCESS` = amount beyond delinquency
  that the loan engine applied as prepayment/overpay.
- Case `CC-RECOVERED-AMT` and promise/arrangement `PAID` accumulate
  `RV-APPLIED` only. `recon COLLECT` compares against `RV-APPLIED` sums.
- `promise.fulfill` never closes money: it is rejected (rc 20, REQUIRES
  RECOVERY POSTING); fulfillment happens via `recovery.post` linking the
  promise through `CC-PROMISE-ID` and stamping `PM-TXN-REF`.
- `recovery.reverse` rewinds promise/arrangement by `RV-APPLIED`, reopens the
  case to active, restores loan exposure through reversal transaction.

## EOD

`COLCEOD` (batch): auto-create cases for loans in ACT/OD/DEF with due
obligations (`COLLNQ`),
snapshot open/active/inco cases (re-derives overdue), expire promises past
`promise-date + KF-EXP-DAYS`, escalate broken promises, then
`BBATEOD` runs `reconciliation COLLECT` and prints
`COLLECTION-EOD SNAPSHOT= EXPIRED= CREATED=`.

## Operations (CLI)

```
case.create|get|list|eligible|snapshot|activate|escalate|close|cancel|fail|reopen|stage
action.create|execute|cancel|expire|fail|list
promise.create|accept|break|cancel|expire|list
arrange.create|activate|cancel|break|expire|list
recovery.post|reverse|list
handoff.create|ack|return|close|cancel
```

Guards: one active case per loan (`ACTIVE CASE EXISTS`), one active promise
(`ACTIVE PROMISE EXISTS`), one active arrangement (`ACTIVE ARRANGEMENT EXISTS`),
one active handoff per kind (`EXTERNAL/LEGAL HANDOFF EXISTS`), idempotent recovery via
`CO-REQUEST` correlation (BIDM).

## Open (not fabricated)

- collection-charge-off: delegated to loans written-off; no independent
  regulatory write-off decision in collections.
- provision linkage: depends on unresolved `provisioning` open item.
- scoring-driven priority: depends on unresolved `credit-scoring` open item.
