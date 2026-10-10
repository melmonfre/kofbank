# operations-catalog

## run

```
make build
make test
make bank ARGS="account open ..."
make eod
```

## environment

- BANK_HOME: dataset root, set by Makefile
- COB_LIBRARY_PATH: build
- KOF_LOCK_TIMEOUT_MS: optional bounded wait (ms) for cross-process lock
  acquisition (BLCK/BSEQ/BWR via KFLOCK). Unset = wait until granted, relying
  on kernel release if the holder dies. Set = on expiry the acquisition fails
  with status 62 and the operation fails closed (rc 24 / non-"00"); there is no
  silent fallback to unsynchronised access. Keep >= 5000 in production so the
  short critical sections never surface a timeout to clients (ADR 0022).
- KOF_CRASH: QA-only crash-seam injection (ADR 0022); never set in production.

## observability

| signal | location |
|---|---|
| audit | var/audit/audit.log |
| events | var/journal/events.log |
| journal | var/journal/journal.log |
| postings | var/journal/postings.log |
| eod report | var/out/eod_<date>.txt |
| transactions | var/data/txn.idx |
| reconciliation runs | var/data/rec.idx |
| reconciliation exceptions | var/data/recexc.idx |
| credit applications | var/data/crapp.idx |
| credit facilities | var/data/crfac.idx |
| credit exposure | var/data/crexp.idx |
| credit obligations | var/data/crobl.idx |

## transaction operations

```
txn.create|<type>|<src>|<dst>|<amount>|<currency>|<descr>|<operator>|<corr>|<request>
txn.authorize|<id>|<operator>|<corr>|<request>
txn.post|<id>|<operator>|<corr>|<request>
txn.settle|<id>|<operator>|<corr>|<request>
txn.complete|<id>|<operator>|<corr>|<request>
txn.cancel|<id>|<reason>|<operator>|<corr>|<request>
txn.reverse|<id>|<reason>|<operator>|<corr>|<request>
txn.return|<id>|<reason>|<operator>|<corr>|<request>
txn.get|<id>
txn.list
```

types: DEPOSIT WITHDRAW TRANSFER FEE
states: CR VA AU PO ST CP | RJ CN RT RV

## credit operations

```
credit.application.create|<cust>|<product>|<account>|<amount>|<term>|<op>|<corr>|<req>
credit.application.approve|<app>|<approved>||<op>|<corr>|<req>
credit.application.get|<app>
credit.facility.originate|<app>|<account>|<expires>|<collateral>|<op>|<corr>|<req>
credit.facility.approve|<fac>||<op>|<corr>|<req>
credit.facility.contract|<fac>||||<op>|<corr>|<req>
credit.facility.activate|<fac>||<op>|<corr>|<req>
credit.facility.schedule|<fac>|<principal>|<rate-bps>|<basis>|<term>|<eff>
credit.facility.exposure|<fac>
credit.disbursement.create|<fac>|<amount>|<fee>|<op>|<corr>|<req>
credit.repayment.create|<fac>|<amount>|<op>|<corr>|<req>
credit.writeoff.create|<fac>|<amount>|<reason>|<op>|<corr>|<req>
credit.installment.get|<fac>|<installment>
credit.installment.list|<fac>
```

application states: RCV UND APV CND REJ CAN EXP CON
facility states: REQ APV CON ACT SUS BLK MAT CLO CAN DEF EXP
obligation states: SC PT PA

## loan operations

```
loan.create|<fac>|<principal>|<term>|<amort>|<freq>|<op>|<corr>|<req>
loan.approve|<loan>||<op>|<corr>|<req>
loan.contract|<loan>||<op>|<corr>|<req>
loan.activate|<loan>||<op>|<corr>|<req>
loan.suspend|<loan>||<op>|<corr>|<req>
loan.resume|<loan>||<op>|<corr>|<req>
loan.delinquent|<loan>||<op>|<corr>|<req>
loan.default|<loan>|<reason>|<op>|<corr>|<req>
loan.mature|<loan>||<op>|<corr>|<req>
loan.settle|<loan>||<op>|<corr>|<req>
loan.close|<loan>||<op>|<corr>|<req>
loan.cancel|<loan>|<reason>|<op>|<corr>|<req>
loan.restructure|<loan>|<reason>|<op>|<corr>|<req>
loan.schedule|<loan>
loan.disburse|<loan>|<amount>|<fee>|<op>|<corr>|<req>
loan.repay|<loan>|<amount>|<op>|<corr>|<req>
loan.writeoff|<loan>|<amount>|<reason>|<op>|<corr>|<req>
loan.get|<loan>
loan.list
loan.installment.get|<loan>|<installment>
loan.installment.list|<loan>
loan.exposure|<loan>
```

loan states: REQ APV CON ACT SUS DFL DEF MAT SET CLO CAN
installment states: SC PT PA OD
allocation order: product field PR-ALLOC-ORDER, default FIP (fees, interest, principal)

## reconciliation operations

```
reconciliation.run|LEDGER
reconciliation.run|PAYMENT
reconciliation.run|TXN
reconciliation.run|CREDIT
reconciliation.run|LOAN
reconciliation.run|EXTERNAL|<run-id>|<file>|<operator>|<corr>
reconciliation.get|<run-id>
reconciliation.list
reconciliation.exceptions|<run-id>
reconciliation.resolve|<exc-id>|<action>|<fin-ref>|<operator>|<reason>
```

actions: ACCEPT REJECT REPROCESS EXTERNAL INTERNAL ADJUST REVERSE CLOSE
ADJUST and REVERSE require a financial reference.

## recovery

- journal-first: business effect is journalled before balances
- idempotency store prevents double posting on replay
- lock table with stale expiry prevents deadlock
- rerun eod is safe for the same business date

## incidents

severity: S1 data loss, S2 financial mismatch, S3 degraded
first action: stop writes, preserve var/journal and var/audit, run ledger.trial

## system lifecycle (GATE 4)

```
system.status
system.start|<reason>|<operator>|<corr>
system.drain|<reason>|<operator>|<corr>
system.stop|IMMEDIATE|<operator>|<corr>
system.stop|GRACEFUL|<operator>|<corr>
system.recover.begin|<reason>|<operator>
system.recover.resume|<operator>|<corr>
system.maintain|<reason>|<operator>
```

States: STOPPED RUNNING DRAINING MAINTENANCE
RECOVERY_REQUIRED RECOVERING. STARTING is transient inside ops.start.

Durable state: var/run/life.dat (one line: state|timestamp|operator|
reason|generation).  The lifecycle record only gates permission to
accept work; it never stores or implies financial truth.

Backward compatibility: if var/run/life.dat does not exist the system
runs in legacy mode and every domain is accepted (existing deployments
and the full pre-GATE-4 regression suite are unaffected).  Creating the
file activates the gate immediately.

Gate matrix while lifecycle is enforced:

| state | business txn/ledger writes | batch.eod | boundary drain ops (bnd.*) | ops.* / system.* |
|---|---|---|---|---|
| RUNNING | yes | yes | yes | yes |
| DRAINING | no | no | yes (outbox/inbound resolve) | yes |
| STOPPED | no | no | no | yes |
| RECOVERY_REQUIRED / RECOVERING | recovery only (txn.recover, ledger, recon, batch, bnd) | yes | yes | yes |
| MAINTENANCE | no | no | no | yes |

ops.start classifies durable state first: CLEAN starts RUNNING;
RECOVERABLE/OPERATOR_REQUIRED starts RECOVERY_REQUIRED (fail-closed,
resume required); CORRUPT refuses the start entirely (rc=20).

## startup safety inspection

```
ops.inspect            full findings + counters
ops.health             live/ready/integrity summary lines
```

Findings (read-only, never mutate): TXN_UNRESOLVED (status AU),
JRN_STAGED (jrst marker J/B/P without completion), OUTB_PENDING,
OUTB_UNKNOWN, MSG_RECEIVED_UNFIN (inbound identity stuck RECEIVED),
LOCK_STALE, REC_OPEN (open reconciliation exceptions), EOD_INTERRUPTED
(checkpoint RUNNING/FAILED), CHAIN_MALFORMED / CHAIN_TRUNCATED /
CHAIN_UNREADABLE on journal.log, postings.log, events.log, audit.log.

Classes: CLEAN, RECOVERABLE (durable recovery exists: txn.recover,
outbox processing, checkpoint resume), OPERATOR_REQUIRED (unknown or
open items that recovery must not guess: UNKNOWN intents, RECEIVED
inbound, open exceptions), CORRUPT (structural chain damage).  The
class never changes any data; it only decides whether start is safe.

## batch checkpoint (EOD)

var/data/eodchk.idx: one record per business date with a 30-bit stage
mask (25 stages: trial ledger, counts, all reconciliations, domain EOD
steps, report, audit).  batch.eod marks each stage complete durably
before the next one starts and closes DONE/FAILED at the end.

```
batch.eod
batch.eod|RESUME            skips completed stages, replays none twice
ops.batch.status|<yyyymmdd>
ops.batch.list
```

Stage effects themselves remain idempotent (GATE 2 design), so RESUME
is safe even against partially recorded stages; the mask prevents
re-running the non-idempotent report/audit appends.

## backup and restore

```
ops.backup.create|<tag>|<operator>|<corr>      STOPPED/DRAINING only
ops.backup.verify|<tag>
ops.restore.verify|<tag>                        also reports LIVE-DIVERGED
ops.restore.apply|<tag>|CONFIRM-RESTORE|<operator>|<corr>   refuses RUNNING
ops.backup.list
```

Package layout: var/bkp/<tag>/{data,journal,audit,etc} plus
manifest.txt (sorted relative paths).  CREATE is only allowed when the
system is not accepting work, so the copy is application-consistent;
on failure it removes the partial package.  APPLY verifies the package
first, moves the live data tree to var/data.precall.<tag>, and requires
the literal CONFIRM-RESTORE token.  restore.verify diffs live files
against the package and reports divergence without touching anything.
Secrets: nothing beyond etc/ is copied; the tree holds no key material
(GATE 3 rule).

## stale locks and operator authorization

```
ops.locks.list
ops.locks.release|<name>|<reason>|<operator>|<corr>
```

BLCK entries carry an expiry instant.  ops.locks.list labels FRESH or
STALE; release refuses to delete a FRESH lock (rc=20) and requires an
explicit reason, audited as LOCK.RELEASE.  Detection never auto-deletes.

Every privileged action takes operator and correlation fields and is
written to the existing audit chain: LIFE.CHANGE, LOCK.RELEASE,
BK.CREATE/BK.APPLY, INC.OPEN/INC.ACK/INC.RESOLVE.  This is an
authorization boundary (explicit operator, auditable, fail-closed),
not IAM; production maps operators to RACF/EACF identities.

## incidents

```
ops.incident.open|<key>|<summary>|SEV1|SEV2|SEV3|<operator>|<evidence>
ops.incident.ack|<key>|<operator>
ops.incident.resolve|<key>|<resolution-note>|<operator>|<corr>
ops.incident.show|<key>
ops.incident.list
```

Durable store var/data/opsinc.idx.  OPEN -> ACK -> RESOLVED enforced in
order; resolve requires a note; resolved incidents are immutable (open
a new key).  Evidence is free text referencing finding ids.

## correlation

```
ops.correlate|<id>
```

Scans txn, journal-stage, outbox, message-identity, exceptions,
incidents and all four chain logs for the id (transaction id, journal
id, msgid, e2e, intent id, correlation id, request id).  Read-only.

## configuration and certificate operations

```
ops.config.verify        fails closed on dangerous combinations
ops.cert.expiring|<days>  CERT-EXPIRED / CERT-EXPIRING scan
```

PRODUCTION environment refuses LOCALDOUBLE transport, LOCAL_DOUBLE
security, an empty signing-cert-ref or an empty trusted-issuer-subject
(rc=20 CONFIG VERIFIED never printed on refusal).

## mainframe boundary

The lifecycle, checkpoint, incident and audit primitives are plain
indexed/line-sequential files that map 1:1 to VSAM KSDS and dataset
patterns (see jcl/EOD.jcl DD list: EODCHK added).  Production
replacements:

- var/run/life.dat -> operator-controlled CICS region status or a
  z/OS console-monitored dataset; the COBOL gate logic is unchanged.
- ops.backup.* -> DFSMSdss dumps + console-driven quiesce (drain the
  region first, same invariant).
- batch.eod|RESUME -> checkpointed JCL with restart stages; the
  eodchk mask is the stage truth.
- ops.* CLI -> CICS TRANIDs or batch operator jobs guarded by RACF.
- INCIDENTS/locks -> CA-Sched/MQ/Db2 equivalents may wrap, but the
  file-based stores remain authoritative in this build.

Capacity and RPO/RTO are institution decisions; the suite proves the
mechanisms, not the sizing.  No fake multi-site DR is claimed.

## GATE 5 — QA profile and fail-closed adapters

Runtime environments: `LOCAL_DOUBLE` (default) and alias `QA` behave
identically as deterministic doubles; `PRODUCTION` is accepted in config only
with strict coherence rules, and the boundary refuses every send/query,
inbound, and sign/verify operation under PRODUCTION (or any unknown/blank
environment) with explicit "NOT INSTALLED" / "UNKNOWN OR MISSING" messages
before any side effect. `ops.config.verify` additionally rejects a
double-mode environment pointing at non-double adapters and vice-versa.
QA runbook: `docs/production-readiness.md` §4/§9; ADR 0018.
