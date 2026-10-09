# Kof <-> KofBank Integration Contract — KBCLI-1 (Expanded)

Status: QA-verified (48 integration checks via `make kof-test`, executable payroll example via `make kof-example`).
The COBOL core remains authoritative for all financial truth. Kof provides integration, orchestration, and ergonomics without duplicating financial logic.

## 1. Architecture and Protocol

```text
external callers / applications (e.g. Payroll, Portal, CLI)
            |
            v
   Kof Integration Layer (KofBank.kf)
            |
            v  [KBCLI-1 request-line over shell.pipeline]
       BANKCLI (COBOL dispatcher)
            |
            v
   COBOL Domain Modules (BTXN, BGL, BOPS, BCUST, BACCT, etc.)
            |
            v
   Financial Stores (acct.idx, txn.idx, jrst.idx, journal.log, audit.log)
```

- **Transport**: Synchronous process execution (`build/bank`). Kof invokes via `shell.pipeline([["printf", req], [bank]])` with `BANK_HOME` and `COB_LIBRARY_PATH`. No network listener or daemon is introduced.
- **Request format**: One line `domain.verb|arg1|arg2|...` on stdin (ADR 0006).
- **Response format**: Multi-line `key=value` on stdout. `rc=` is always present.
- **Version handshake**: `system.contract` returns `contract=KBCLI-1`, `core=BANKCLI`, `transport=request-line/keyvalue`. Callers must verify the contract version before processing.
- **Versioning policy**: Additive fields and verbs are backward-compatible. Changes to existing field names, parsing grammar, or RC semantics require bumping to a new contract identifier (e.g., `KBCLI-2`).

## 2. Structured Error and Result Model

Kof clients must never collapse financial results into a generic boolean or exception. The classifier `outcome(reply)` in `KofBank.kf` distinguishes:

| Outcome | Criteria | Meaning | Client Handling |
|---|---|---|---|
| `OK` | `exit == 0` and `rc == "00"` | Operation accepted or completed | Proceed with returned data |
| `PENDING` | `exit == 0` and `rc == "24"` | In-progress or lock held | Do NOT blind-retry; query by request ID |
| `CONFLICT` | `exit == 0` and `rc == "26"` | Idempotency payload mismatch | Terminal; request ID reused with different payload |
| `REJECT` | `exit == 0` and `rc in {"20","22","23"}` | Business or validation rejection | Check `msg=` and `rc=`; fix input or notify caller |
| `INTEGRITY`| `exit == 0` and `rc in {"35","36"}` | Store or chain integrity issue | Operational incident; do NOT retry through |
| `INFRA_FAIL`| `exit != 0` | Process crash, missing binary, SIGSEGV | Operational failure; inspect `err` and retry safely |
| `NO_REPLY` | `exit == 0` and no `rc=` line | Malformed/incomplete response | Presumed uncertain; inspect or reconcile |

### Unknown Outcome Protocol

If an operation encounters `INFRA_FAIL` or `NO_REPLY` during a financial write:
1. The outcome is **unknown** (in-doubt).
2. The client must re-issue the operation with the **SAME request ID** (idempotency token). The COBOL `BIDM` store will return the original completed result if it was processed, or `rc=24` if still in progress.
3. If still unresolved, the client must query `txnGet(id)` or `correlate(reqId)` rather than submitting a new transaction with a new ID.
4. Under no circumstances may an application invent a balance or assume success/failure independently.

## 3. Expanded Capability Surface

All capabilities delegate directly to existing, operationally hardened COBOL modules:

### Account & Ledger Inquiry
- `balance(accountId)`: Returns `rc`, `ledger`, `available`, `blocked`, `currency`. Read-only.
- `postings(accountId)`: Scans journal postings for the entity. Returns `rc`, `matches`.
- `trial()`: Full general ledger trial balance. Returns `rc`, `total-debit`, `total-credit`, `accounts`. Used to verify mathematical conservation.
- `journal(ref)`: Queries durable journal entries by reference (`TXN...-P`, `JRN...`). Returns `rc`, `found`, `debit`, `credit`.

### Transaction Lifecycle & Inspection
- `deposit(acct, amt, desc, op, corr, reqId)`: Submits `txn.create|DEPOSIT`. Returns `rc`, `id`, `status=VA`, `msg`.
- `withdraw(acct, amt, desc, op, corr, reqId)`: Submits `txn.create|WITHDRAW`. Returns `rc`, `id`, `status=VA`, `msg`. Overdraft returns `rc=20`, `msg=INSUFFICIENT FUNDS`.
- `txnRequest(op, id, op, corr, reqId)`: Drives lifecycle transitions: `authorize` (`AU`), `post` (`PO`), `settle` (`ST`), `complete` (`CP`).
- `txnGet(id)`: Full record retrieval via `BTXNQRY`. Returns `id`, `type`, `status`, `amount`, `source`, `destination`, `journal`, etc.
- `txnList()`: Returns summary listing of transactions in the store.
- `reverse(id, reason, op, corr, reqId)`: Initiates reversal via `BTXNLFC`. Automatically posts offsetting journal entries and updates account balances. Returns `status=RV`.
- `recover(id)`: Invokes restart recovery on a transaction in-doubt via `BTXNRCV`.

### Operations, Batch & Audit
- `health()`: Operational status via `BLIFE`. Returns `rc`, `state`, `generation`.
- `opsInspect()`: Startup safety classification via `BOPSCK`. Returns `rc`, `class` (`CLEAN`, `RECOVERABLE`, `OPERATOR_REQUIRED`, `CORRUPT`), `rec-open`, `eod-interrupted`, `outb-unknown`.
- `batchStatus(bizDate)`: EOD checkpoint status via `BEODCHK`. Returns `rc`, `state` (`RUNNING`, `DONE`, `FAILED`).
- `correlate(ref)`: Cross-store correlation via `BOPSCO`. Traces across `bndout`, `bndmsgid`, `txn`, `jrst`, and log files. Returns `rc`, `hits`, and matching records.

## 4. Consumer Application Example: Payroll (`Payroll.kf`)

Located at `tools/kof/examples/Payroll.kf`. Run with:
```bash
make kof-example
```

The example implements a salary disbursement batch:
1. **Handshake check**: Verifies `system.contract == "KBCLI-1"`.
2. **Safety guard**: Calls `opsInspect()` and aborts if system is not `CLEAN`.
3. **Onboarding**: Creates customers and demand accounts for employees.
4. **Disbursement**: Iterates over staff records, creating deposits with unique, deterministic request IDs (`PAY-<seed>-<emp>-DEP`).
5. **Conflict detection**: Explicitly checks `rc == "26"` (payload mismatch) and marks as unresolved.
6. **Lifecycle completion**: Walks each deposit through `authorize -> post -> settle -> complete`.
7. **Verification**: Queries `balance()`, `txnGet()` (journal ref), and `correlate()` to confirm postings.
8. **Idempotent replay**: Re-submits the first salary deposit with identical payload and request ID, asserting `rc == "00"` and identical transaction ID.
9. **Conservation check**: Invokes `trial()` and verifies `total-debit == total-credit`. Aborts if ledger does not balance.
10. **Audit output**: Prints summary of paid, failed, and unresolved transactions, and exits non-zero if any state is uncertain.

## 5. Verification Matrix

| Area | Checks | Executable Proof |
|---|---|---|
| Contract & Handshake | 3 | `contract.handshake`, `contract.transport`, `health.rc` |
| Customer & Account | 2 | `customer.created`, `account.opened` |
| Deposit Lifecycle | 7 | `txn.accepted`, `txn.pending`, `txn.authorized`, `txn.posted`, `txn.settled`, `txn.completed`, `txn.get.completed` |
| Idempotency & Tamper | 4 | `replay.same.id`, `conflict.rejected` (`rc=26`), `reissue.same.id`, `reverse.idempotent` |
| Ledger Balance Math | 3 | `balance.before.value`, `balance.increased`, `reverse.restores.balance` |
| Journal & Postings | 4 | `txn.journal.ref`, `journal.inquiry.rc`, `journal.balanced`, `postings.rc`, `postings.count` |
| General Ledger Trial | 2 | `trial.rc`, `trial.conservation`, `trial.conservation.after.reverse` |
| Transaction Listing | 2 | `txn.list.rc`, `txn.list.contains` |
| Operations & EOD | 4 | `correlate.rc`, `correlate.hit`, `ops.inspect.rc`, `ops.inspect.class`, `batch.absent.rc` |
| Reversal Delegation | 3 | `reverse.accepted` (`RV`), `reverse.idempotent`, `reverse.restores.balance` |
| Business Rejection | 4 | `business.reject.rc` (`20`), `business.reject.reason` (`INSUFFICIENT`), `business.reject.clean.exit` (`exit=0`), `business.reject.classified` (`REJECT`) |
| Process & Infra Safety | 5 | `infra.fail.exit` (`exit!=0`), `infra.fail.classified` (`INFRA_FAIL`), `infra.fail.operational`, `infra.stderr.separated`, `unknown.reply.safe` |
| **Total Automated** | **48** | **`make kof-test` (48 passed, 0 failed)** |
| **Consumer Example** | **1** | **`make kof-example` (3 salaries paid, ledger conserved, exit 0)** |
| **COBOL Core Suite** | **1616** | **`make test` (1616 passed, 0 failed)** |
| **Facade Slice** | **38** | **`make kof-facade-test` (suiteA+B+C, 0 failed)** |

## Application facade (KBAPP-1) — first vertical slice

The Kof application layer (`tools/kof/facade/`) is a thin BFF between a UI and the
KBCLI-1 COBOL boundary. Contract: frontend -> BFF HTTP JSON -> KBCLI-1 -> COBOL core.

Files:
- `BffTypes.kf` - DTOs, dev identity, tolerant `key=value` parsing, core-rc -> HTTP mapping.
- `Bff.kf` - `web.app()` routes under `/api/*` (KBAPP-1), default port 8977 (`server.port`).
- `Portal.kf` - frontend view-state machine (`LOADING/READY/EMPTY/ERROR/UNKNOWN_OPERATION/INFRA_ERROR`).
- `Tools.kf`, `SuiteA/B/C.kf` - end-to-end QA suites driving the real BFF against the real core.

Core rc mapping: exit!=0 -> 503, empty rc -> 502, 20 -> 400, 22 -> 422, 23 -> 404,
24 -> 504 (unknown outcome, explicitly not blind-retryable), 26 -> 409, 35/36 -> 500.
Every error body carries `category`, `coreRc`, `correlationId`, `retryable`.

Commands:
- `make kof-facade-test` - resets QA state, seeds two funded customers + one empty,
  runs 38 end-to-end checks (auth, ownership isolation, authoritative balance,
  history/detail, idempotent replay, tamper conflict, malformed bodies, view states,
  CLEAN store and balanced ledger at the end).
- `make kof-portal` - starts the BFF and exercises the portal flow (login, accounts,
  balance, history, detail) through the HTTP contract only.

Identity boundary: `ana/kof-demo-ana` -> `C00000000001`, `bob/kof-demo-bob` ->
`C00000000002`, session token `SES.<user>.<customer>`. This is a LOCAL QA identity
model. There is no real credential store, TLS or token expiry yet; production auth
is a known gap, not a claim.

No financial computation happens in Kof: balances, transactions, posting and
idempotency are read/decided exclusively by COBOL through KBCLI-1.
