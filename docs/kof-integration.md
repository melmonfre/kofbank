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
| **COBOL Core Suite** | **1627** | **`make test` (1627 passed, 0 failed)** |
| **Facade Slice** | **183** | **`make kof-facade-test` (suites A-I, 0 failed)** |

## Application facade (KBAPP-1) — transfer vertical slice

### Controlled transfer flow
`POST /api/accounts/:id/transfers` (body: amount cents, to, description?,
requestId, correlationId?) drives the existing COBOL lifecycle only:
`txn.create|TRANSFER|...` then authorize->post->settle->complete through KBCLI-1.
No second ledger, no application-side state machine: the core decides.
Guarantees asserted end-to-end (suite D):
- exact replay of the same request id + same payload returns the same durable
  transaction reference with zero additional financial effect;
- same request id + changed payload -> 409 IDEMPOTENCY_CONFLICT (core rc 26);
- insufficient funds / unknown or inactive destination / self-transfer / currency
  mismatch are core business rejections (422) with no effect;
- concurrent duplicate submissions (twin test) resolve to one effect; every
  response reports a reconciled `verdict` (COMMITTED / VISIBLE / NON_COMMITTED_SAFE /
  RECONCILIATION_REQUIRED / CONFIRMED_NOT_EFFECTIVE) as a normal body; only a
  committed, evidenced transaction is ever shown as done, and undetermined outcomes
  are never marked retryable;
- crash seam (KOF_CRASH=AFTER-POST, QA env injection through raw client, never
  through production config) leaves a FAIL-marked idempotency record; `txn.recover`
  finishes the posting exactly once (journal found=1 lines=2);
- GET /api/operations/:requestId reconciles by request identity against the
  core idempotency store (new read-only KBCLI-1 verb `txn.lookup`, modes
  R=in progress / undetermined -> RECONCILIATION_REQUIRED (200, never
  retryable=true, account-ownership enforced), C=committed+evidence -> COMMITTED
  with durable txn ref, failed create with no txn -> NON_COMMITTED_SAFE
  (retryable), absent -> NOT_FOUND);
- restart durability (suite F): a second BFF process over the same store shows
  the identical balance, history, detail and lookup result; replay after
  restart still never double-posts; journal trial stays balanced and store
  CLEAN at slice end.

### Security boundary (suite E, all against the real core)
- session token must be exactly `SES.<user>.<customer>` (dot-count enforced);
  forged suffixes, swapped pairs and unknown users are rejected;
- account/transaction ids are shape-validated at the boundary; KBCLI-1 fields
  are fixed-width PIC X and silently truncate, so a wider id (for example
  `A00000000001X`) would alias to a real account without the guard. The guard
  closes aliasing for every :id route;
- pipe/newline injection and over-width request ids are rejected before the
  CLI contract is touched (core fields: request/correlation 24, description 40);
- error bodies carry only app-level categories, coreRc and correlation — no
  paths, no file layout, no credentials, no stack details;
- every data route fails closed with 401 without a valid token; deposits and
  transfers enforce source ownership before any core mutation; transaction
  detail is visible only to owners on either side.

### Core fix found during this slice
`BTXNVAL.cbl` V-TRANSFER checked funds against the destination account
(stale `WS-ACCT-ID-WS`) — rich-source transfers were wrongly rejected and
poor-source overdrafts could pass validation. Fixed to check the source;
11 new COBOL regression checks cover direction, self-transfer, currency and
lookup states (COBOL suite now 1627).

### Resilience & concurrency hardening (slice 3, suites G/H/I)
Suite G proves the crash boundaries through the facade path (not just the raw
client): for each `KOF_CRASH` seam (ledger AFTER-JRN / AFTER-BAL / AFTER-PST, txn
AFTER-POST) it asserts balances/journal durability, that `txn.recover` resumes the
staged write and completes it exactly once (journal `found=1 lines=2`), and that the
operation reconciles to the right verdict - a lifecycle attempt that crashed after
post reads as `RECONCILIATION_REQUIRED` (never auto-reposted), a repost is a core
duplicate with zero added effect.

Suite H proves cross-process behaviour with real OS subprocesses (`spawn` = fork):
- H1: concurrent **same-requestId** creates resolve to exactly one transaction. This
  required a core fix - `BTXNLFC` now serializes the `BEGIN -> create -> COMPLETE`
  idempotency window under a `BLCK` lock keyed by `"CR"+BHSH(requestId)` and
  releases it on every exit path (before the fix two racing creates each minted a
  transaction for one key).
- H4/H5: concurrent posts on one transaction are serialized (one effect, journal
  once, trial balanced, store CLEAN, locks released).

Suite I covers bounded load (a 10-request burst with a full replay pass asserting
idempotent replay adds nothing and the trial stays balanced) and observability: a
committed transfer is traced across the core stores via `ops.correlate` (txn id,
journal ref, requestId) and the portal detail/operation views agree; a rejected
transfer leaves `NON_COMMITTED_SAFE` (retryable) with no committed effect.

**Cross-process locking (ADR 0022, resolved in slice 4).** `BLCK`, `BSEQ` and the
durable store writers are now serialized by real OS locks via a native `flock(2)`
helper (`KFLOCK`), not by optimistic ISAM claims. `BSEQ` allocates ids under a
per-key lock (`SEQ-<name>`), `BLCK` performs its `lock.idx` check-and-set under a
registry lock, and each store write (`txn/acct/cust` + the ledger post/recover)
takes a leaf lock (`WR-TXN/ACCT/CUST/LEDGER/RC`) that is never nested with
another leaf lock. A hard process kill is self-healing because the kernel frees
the `flock` on death. So a *same-instant* burst of creates with **distinct**
requestIds now yields unique ids with no lost create, and concurrent transfers
conserve money (no lost balance update). Suite H asserts this positively
(`H3.concurrent.allDistinctCommit`); `tests/concurrency.sh` (`make concurrency-test`,
part of `make test`) drives deterministic multi-process bursts (44 checks): id
uniqueness and no-lost-create, same-request idempotency and payload-mismatch
rejection, transfer conservation, interrupted allocation (`KOF_CRASH=AFTER-SEQ`,
gaps tolerated, no id reuse), bounded lock waiting with `KOF_LOCK_TIMEOUT_MS`
(timeout surfaces as status `62` and fail-closed - there is no silent fallback;
missing `KFLOCK.so` returns `EF`), stale-sweeper protection of live holds, and
final durable inspection of the sequence store. Financial authority is
unchanged - COBOL still owns every balance/ledger decision. Validated on local
ext4 single host; `flock` semantics on NFS/distributed FS are not claimed.

### Development-only auth (unchanged scope statement)
### Development-only authentication boundary (unchanged)
`ana`/`bob` dev identities and `X-Session-Token` remain a LOCAL QA model: no
credential store, no expiry, no TLS. Production identity is an open gate, not
delivered here.

### Legacy slice notes (read-oriented portal)

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
  runs suites A-I (183 end-to-end checks): auth, ownership isolation, authoritative
  balance/history/detail, idempotent replay, tamper conflict, malformed bodies, view
  states, crash-seam recovery (G), cross-process idempotency/concurrency (H), bounded
  load + correlation/observability + failure semantics (I), CLEAN store and balanced
  ledger at the end.
- `make kof-portal` - starts the BFF and exercises the portal flow (login, accounts,
  balance, history, detail) through the HTTP contract only.

Identity boundary: `ana/kof-demo-ana` -> `C00000000001`, `bob/kof-demo-bob` ->
`C00000000002`, session token `SES.<user>.<customer>`. This is a LOCAL QA identity
model. There is no real credential store, TLS or token expiry yet; production auth
is a known gap, not a claim.

No financial computation happens in Kof: balances, transactions, posting and
idempotency are read/decided exclusively by COBOL through KBCLI-1.
