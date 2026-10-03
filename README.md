# kofbank

Banking institution modeled as software. COBOL core first; Kof is the modern
integration layer later. Local development runs on GnuCOBOL with VSAM-like
indexed datasets; the design targets z/OS, CICS, VSAM, DB2, MQ and JCL.

## Run

```
make build
make test
make bank ARGS="account open ACC000000001 C000000001 1000 500000"
make eod
```

## Layout

```
cobol/foundation   runtime: config, status, keys, hash, journal, lock, audit, idempotency
cobol/customers    party and customer lifecycle
cobol/accounts     account opening and status
cobol/ledger       double-entry chart, journal, postings, trial balance
cobol/transactions transaction lifecycle: create, authorize, post, settle, complete, cancel, reverse, return
cobol/payments     payment lifecycle, rails, return, reversal, reconciliation
cobol/products     effective-dated product catalog and rules
cobol/interest     deterministic interest, compounding and fee calculation
cobol/limits       centralized limit rules and period usage
cobol/reconciliation runs, matching, exceptions, resolution
cobol/batch        end-of-day orchestration
copybooks          shared record layouts
jcl                mainframe job skeletons
operations         operator scripts and runbooks
tests              golden datasets and invariant checks
```

## Rules

- COBOL is the core. No business logic outside it.
- No comments in code. The code expresses itself.
- Small files, Unix and KISS.
- Every financial effect is persisted, balanced and auditable.
- Unknown requirements are explicit, never guessed.


## License

KofBank is free and open-source software licensed under the **GNU General Public License v3.0 (GPLv3)**.

See the `LICENSE` file for the complete license terms.
