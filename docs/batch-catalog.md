# batch-catalog

| job | schedule | dependencies | input | output | checkpoint | restart | failure |
|---|---|---|---|---|---|---|---|
| BATCH.EOD | daily after cut | none | cust.idx acct.idx acctbal.idx txn.idx pay.idx postings.log | var/out/eod_<date>.txt | date in filename | rerun idempotent | stops if trial unbalanced or reconciliation has open exceptions |
| BGLCHT | on demand | chart.cfg | chart.cfg | gl.idx | none | idempotent upsert | rc 35 missing config |

## eod sequence

1. trial balance check
2. customer count
3. account count
4. balance count and total liability
5. payment lifecycle reconciliation against postings.log
6. ledger reconciliation (balances vs postings) as run REC-LEDGER-<date>
7. payment reconciliation (payments vs postings) as run REC-PAYMENT-<date>
8. transaction reconciliation (settled txns vs postings) as run REC-TXN-<date>
9. credit end-of-day: mark overdue installments on exposure, mature facilities
   with zero outstanding principal (BCRCRDEOD)
10. credit reconciliation (exposure principal vs settled credit txns) as run
    REC-CREDIT-<date>
11. loan end-of-day: mark overdue installments and accumulate facility overdue
    exposure (BLNCEOD)
12. loan reconciliation (loan outstanding vs settled loan txns) as run
    REC-LOAN-<date>
13. report
14. audit
15. BATCH.EOD.v1 event

## eod reconciliation behavior

- balanced runs allow EOD to continue
- open exceptions stop EOD with rc 20 after the report is written
- a run that already exists for the date is accepted (idempotent rerun)
- the trial balance remains the hard gate; reconciliation adds a second gate

## invariants

- eod never mutates balances
- eod is safe to rerun for the same date
