# reconciliation-catalog

reconciliation detects and explains differences. it is not a second ledger and
never writes balances or postings. corrections flow through transactions and BGLPST.

## lifecycle

```
CREATED -> MATCHING -> BALANCED | EXCEPTIONS
                    \-> FAILED
```

- CREATED: run record written
- MATCHING: a matcher is executing
- BALANCED: zero open exceptions
- EXCEPTIONS: one or more open exceptions
- FAILED: a matcher returned a hard error

## types

| type | source | internal | key | difference codes |
|---|---|---|---|---|
| LEDGER | postings.log | acctbal.idx | account | MISMATCH, ORPHAN |
| PAYMENT | pay.idx | postings.log | journal id | NO_POSTING, ORPHAN |
| TXN | txn.idx | postings.log | journal id | NO_POSTING, ORPHAN |
| CREDIT | txn.idx (credit types) | crexp.idx | facility | NO_EXPOSURE, MISMATCH |
| LOAN | txn.idx (loan refs) | loans.idx | loan | NO_LOAN, MISMATCH, CLOSED_OUTSTANDING |
| EXTERNAL | external file | postings.log | journal id, or (amt, cur, date) | UNMATCHED, AMOUNT, CURRENCY, DATE, DUPLICATE, AMBIGUOUS |

## matching

deterministic, in priority order:

1. exact key (account or journal id)
2. exact reference (external ref = journal id) with amount, currency, and value-date verification
3. keyless fallback by amount, currency, and date (unique candidate only)

ambiguous candidates (multiple postings matching keyless amount/currency/date) raise AMBIGUOUS; they are never automatically marked matched.

## exception lifecycle

```
OPEN -> UNDER_REVIEW -> RESOLVED | ACCEPTED | REJECTED | REPROCESSED | CLOSED
```

resolutions:

| action | status | financial effect |
|---|---|---|
| ACCEPT | ACCEPTED | none, operator accepts the difference |
| REJECT | REJECTED | none |
| REPROCESS | REPROCESSED | none, source is reprocessed |
| EXTERNAL | RESOLVED | external correction |
| INTERNAL | RESOLVED | internal correction |
| ADJUST | RESOLVED | requires financial reference |
| REVERSE | RESOLVED | requires financial reference |
| CLOSE | CLOSED | none |

ADJUST and REVERSE require a financial reference. the reference points to the
transaction and ledger effect created through the normal financial path.

## invariants

- a run id is deterministic: REC-<type>-<business-date>
- rerunning the same run returns 24 and creates nothing
- exceptions are never deleted
- a balanced run has zero open exceptions
- reconciliation never changes acctbal.idx or postings.log
- source invariant: sum(source records) = sum(matched) + sum(exceptions) (no record hidden)
- source table overflow fails the run loudly (rc=37) rather than dropping records
- missing or unreadable authoritative files fail the run loudly (rc=35/36) instead of vacuously balancing

## external boundary

external records are imported as line-sequential `ref|amount|currency|date`.
the boundary is intentionally file-shaped so VSAM, sequential, JCL or MQ sources
can feed it through an adapter without changing the engine.

## mainframe model

- record oriented, streaming scan of postings and balances
- indexed datasets for runs and exceptions, VSAM-like
- deterministic run ids support restart without duplication
- bounded in-memory tables; a production build would externalize the sort

## restart and recovery

- an interrupted run is left in CREATED or MATCHING
- rerunning with the same id returns 24 until the run is FINALIZED
- a FAILED run is resettable and rerunnable
- full checkpointing is a documented limitation, not faked

## limitations

- in-memory matcher tables are bounded (200-400 rows)
- external format is local sequential, adapters are future work
- no automatic rollback of a partially written run
