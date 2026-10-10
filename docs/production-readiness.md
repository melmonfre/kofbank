# KofBank — Production Readiness Review (GATE 5)

Revision reviewed: `b391fdb` + working tree (GATE 4/5 hardening, uncommitted).
Proof: `make clean && make build && make test` -> 1627 checks, 0 failed, stable
across 3 consecutive full runs after a clean rebuild.

This document is an audit of claims against executable code and tests. It does
not connect to Banco Central and does not certify production operation.

## 1. Readiness classification (honest, separated)

| Class | Status | Meaning |
|---|---|---|
| Code readiness | VERIFIED_IN_QA | Contracts, adapters seam, tests complete for defined scope. |
| QA readiness | VERIFIED | Deterministic local doubles, fail-closed profile, reproducible suite. |
| BCB integration readiness | READY_FOR_INSTITUTIONAL_INTEGRATION | Internal contracts stable; every external prerequisite listed in §7 is OPEN/BLOCKED. |
| Production deployment readiness | OPEN | No real transport, PKI, IAM, capacity, DR, certification. Guard refuses PRODUCTION at runtime by design. |

There is deliberately no single `production-ready` flag.

## 2. Core freeze boundary

Authoritative, frozen for feature expansion (may change only for a justified
defect fix + regression test):

- Financial rules: `cobol/transactions/`, `cobol/ledger/` (BTXN*, BGL*),
  settlement `BPXSTL/BPXCYC/BPXEOD`, reconciliation `cobol/reconciliation/`.
- Journal-first ordering: `BGLPST.cbl:99-115` (seams AFTER-JRN/AFTER-BAL/AFTER-PST).
- Idempotency: `BIDM.cbl` fingerprint store; changed-payload conflict
  `payment.idem.conflict`, replay `pix.idempotent.replay`.
- Lifecycle: `BTXNLFC` (state machine, duplicate guard `BGLPST.cbl:122-126`).

Operational/control-plane modules (`cobol/operations/`, boundary, batch
checkpoint) inspect, gate, checkpoint, restore, correlate, and record operator
evidence. They never create, mutate, or repair financial truth (ADR 0017).
No second ledger, shadow balances, or hidden repair exists anywhere.

## 3. Gate-by-gate evidence matrix

Format: claim -> implementation -> test/proof -> failure scenario covered ->
durable evidence -> remaining limitation.

### GATE 1 — Domain complete
- Claim: core banking domains implemented end-to-end.
- Impl: `cobol/{customers,accounts,transactions,ledger,pix,credit,loan,cards,
  collections,clearing,foundation}`, catalogs in `docs/*-catalog.md`.
- Proof: 1510+ checks incl. `pix.med.*` (192), `pix.claim.*` (96),
  `collateral.*`, `clearing.*`; `docs/capability-map.tsv`.
- Failure scenarios: invalid inputs, product gating, limit breach rules.
- Durable: indexed stores under `var/data/`, audit chain `var/audit/audit.log`.
- Limitation: behavior validated against local accounting rules; institutional
  accounting/regulatory decisions remain §7 OPEN.

### GATE 2 — Financial integrity
- Ledger conservation: postings always balance (`BGLPST`), recon `BRECLGR`
  (`recon.ledger.idempotent`, `fin.cons.*` family, `ledger.balance` checks).
- Journal-first: crash seams prove ordering; recovery `BTXNRCV`
  (`txn.recover`, GATE 2 crash-window families `bnd.ob.crash*`, `bnd.in.crash*`
  built on the same mechanism).
- Idempotency + replay/changed-payload rejection: `BIDM`,
  `payment.idem.conflict`, `pix.idempotent.replay`.
- Concurrency: lock store `BGLBLK` (`lock.idx`), txn lock tests.
- EOD interruption: GATE 4 checkpoint makes stage resume durable.
- Limitation: none within scope; multi-node concurrency is a deployment topic.

### GATE 3 — Production boundary
- Outbox durability: `BXOUTB.cbl` + `var/data/bndout.idx`; unknown outcomes
  stay UNKNOWN (`bnd.ob.process.*`, `bnd.ob.crash*`); reap guard
  (`bnd.ob.refinal.*`, `bnd.ob.reap.guard`).
- Message identity: `BXMSGID.cbl` + `bndmsgid.idx`; duplicate msgid reuse
  refused (`bnd.in.reuse.*`).
- Transport contract: `BXTP.cbl` single choke point; TPERR never fakes success.
- Security: `BSEC.cbl` sign/verify, cert register/check/rotate/revoke
  (`bnd.cert.*`, `bnd.in.badsig.*`, `bnd.in.expiredcert.rc`).
- Inbound validation before domain posting: `BXPIPE.cbl` stage separation
  (`bnd.in.malformed.rc`, `bnd.in.security.noeffect`).
- External reconciliation: `BRECEXT/BRECBND` + exception store
  (`bnd.rec.*`, `recon.resolve.*`); detection, not correction (ADR 0011).
- Split Tax version routing: `spi-message-version` config (`spi.ingest.*`).
- Limitation: doubles are deterministic stand-ins; they cannot masquerade as
  SPI because the runtime guard refuses PRODUCTION operation (§5).

### GATE 4 — Operations hardening
- Lifecycle gate: `BLIFE.cbl`, `BANKCLI` matrix; legacy compatibility
  (`g4.legacy.*`, `g4.drain.*`).
- Startup classification: `BOPSCK.cbl` CLEAN/RECOVERABLE/OPERATOR_REQUIRED/
  CORRUPT; start refuses/correctly routes (`g4.start.*`); crash-seam findings
  and `txn.recover` clearing (recovery-findings block).
- EOD checkpoint/resume: `BEODCHK.cbl` + `BBATEOD.cbl` 25 stages;
  `g4.eod.*` proves FAIL -> detect (EOD_INTERRUPTED) -> repair -> RESUME -> DONE.
- Backup/restore: `BOPSBK.cbl`, manifest packages, confirm token, pre-call
  snapshot (`g4.restore.*`, `g4.bkp.*`, `g4.audit.restore`).
- Stale locks (`g4.lock.*`), incidents (`g4.inc.*`), correlation (`g4.corr.*`),
  cert expiry (`g4.cert.expired.*`), config fail-closed (`g4.config.rc`).
- Limitation: operational state is single-host; real quiesce/DR are §7 items.

## 4. QA environment

Default profile (already the repository default, now formally named):

```
environment=LOCAL_DOUBLE   # or alias QA — identical double-mode behavior
adapter=FIXTURE            # SPI/DICT deterministic double
transport-adapter=LOCALDOUBLE
security-adapter=LOCAL_DOUBLE
sign-algorithm=HASH-DOUBLE
signing-cert-ref=<empty>   # test material only; never production secrets
```

`etc/pix.cfg` remains the single source; `BPXCFG.cbl` loads it; unknown or
blank environment values are refused by `BOPSCFG` and by runtime guards.

Deterministic scenario coverage (all in `tests/run.sh`, executed against the
doubles):

| Scenario | Evidence |
|---|---|
| accepted payment | `bnd.ob.process.*` outcome SUBMITTED/ACKED |
| rejected payment | `bnd.ob.reject.*` |
| duplicate inbound message | `bnd.in.reuse.*`, `bnd.in.replay.*` |
| duplicate outbound response | `bnd.ob.refinal.*`, `bnd.ob.reap.guard` |
| identical replay | `pix.idempotent.replay` |
| changed payload, existing id | `payment.idem.conflict` |
| timeout before remote acceptance | `KOF_BND_SEAM` TP-BEFORE-SEND, `bnd.ob.crasha.*` |
| timeout after possible acceptance | TP-AFTER-SEND, `bnd.ob.crashb.*` -> UNKNOWN |
| unknown external outcome | `bnd.ob.get.state`, OUTB_UNCORR (`bnd.rec.*`) |
| malformed external message | `bnd.in.malformed.rc` (rc 21, no side effect) |
| invalid signature | `bnd.in.badsig.*` (SECURITY state, no post) |
| unavailable external dependency | TPERR class tests `bnd.ob.tperr.*` |
| certificate expiration | `bnd.cert.check.expired.*`, `g4.cert.expired.*` |
| crash at every existing seam | `bnd.ob.crash*`, `bnd.in.crash*`, GATE 2 txn crash families |
| restart and recovery | `g4.start.*`, `txn.recover`, `g4.eod.resume.*` |
| reconciliation after uncertainty | `recon.resolve.*`, `bnd.rec.*` |

QA never needs BCB credentials; no real endpoint is configured anywhere in the
repository.

## 5. Adapter selection is explicit and fail-closed

Layering: domain behavior -> `BKBNDP` contract -> adapter (`BXTP` transport,
`BSEC` security, `BXOUTB`/`BXPIPE` orchestration) -> external system (none).
Retry policy, correlation, and timeouts are config (`transport-timeout-secs`,
`outbound-max-retry`) not code paths in the core.

Enforcement (new in this review, tested by `g5.*`):

- `BXTP` (single transport choke point): environment PRODUCTION -> refuses with
  `PRODUCTION TRANSPORT ADAPTER NOT INSTALLED` (rc 20, class TPERR) before any
  seam or side effect; unknown/blank environment -> refuses.
- `BXPIPE` inbound: refuses PRODUCTION/unknown environment before registry or
  domain effect.
- `BSEC` SIGN/VERIFY: refuse PRODUCTION/unknown environment; EXPSCAN stays
  read-only. `ops.config.verify` already refused PRODUCTION+double combos.
- `BOPSCFG`: environment whitelist {LOCAL_DOUBLE, QA, PRODUCTION}; double-mode
  environments must keep `adapter=FIXTURE`, `transport-adapter=LOCALDOUBLE`,
  `security-adapter=LOCAL_DOUBLE`, `sign-algorithm=HASH-DOUBLE`; PRODUCTION
  keeps prior rules (no doubles, explicit signing cert, trusted issuer).
- A refused transport send leaves the intent PENDING (never sent) — no success
  is faked (`g5.prod.ob.durable`).

Thus: QA cannot activate production (config fails + runtime guard), the local
double cannot masquerade as SPI under a production label, and a configured
"production adapter" is explicitly NOT considered operational — instantiation
of a real adapter is future institutional work.

## 6. Certificates and signing review

- No private keys, credentials, or production secrets in COBOL source, etc/,
  or var/ (audited: `BSEC` uses a deterministic hash double over test refs).
- Test certificate material lives only in `var/data/bndcrt.idx` fixtures with
  explicit purpose/validity windows; expiry/not-yet-valid/missing/revoked all
  fail safely (`bnd.cert.check.*`, `bnd.cert.revoked.*`).
- Signing failure can never be read as transmission success: sign happens in
  the boundary stage before transport; transport refusal keeps PENDING (§5).
- Rotation has an operational contract (`bnd.cert.rotate*`); logs and CLI
  output never print key material.
- No fake CA is built and no claim of institutional acceptance is made.

## 7. SPI / DICT production prerequisites register

Per future production adapter (all fields required; none may be invented):

- Internal contract: `BKBNDP` params + `BXTP` send/query, `BSEC` sign/verify —
  IMPLEMENTED, frozen.
- External contract/version: Split Tax message schema `spi-message-version`
  (5.13 cycle) traceable to published spec; other SPI message schemas OPEN.
- Transport (MQ/network, addressing, TLS/mTLS): BLOCKED_BY_EXTERNAL_DEPENDENCY.
- Authentication (participant credentials): OPEN.
- Message signing (institution HSM/PKCS#11 approved provider): OPEN.
- Certificates (BCB-approved issuing, rotation ops): OPEN.
- Correlation (msgid/e2e/ext-ref preservation across retries): implemented in
  doubles — VERIFIED_IN_QA; production semantics OPEN.
- Timeout/retry semantics: config-driven, limits enforced — VERIFIED_IN_QA.
- Unknown-outcome semantics: durable UNKNOWN + operator reconciliation —
  VERIFIED_IN_QA; SPI query production semantics OPEN.
- Reconciliation: exception detection (OUTB_UNCORR/NOEXT/STALE) —
  VERIFIED_IN_QA; BCB file/report exchange OPEN.
- Institutional prerequisites (participant registration, settlement account
  at BCB, ISPB, homologation certification): BLOCKED_BY_EXTERNAL_DEPENDENCY.

DICT: key/claim domain isolated from transport (`BPXKEY/BPXDICT` vs double);
claim state machine cannot be fabricated by the adapter (adapter only answers);
local deterministic DICT clearly marked; real DICT auth/connectivity not
implemented (OPEN). MED: institution-side workflow only; explicitly NOT BCB
MED integration (OPEN).

## 8. Defects found and fixed during this review

1. Runtime boundary trusted config only. A misconfigured `environment=
   PRODUCTION` still routed through the local double — the double could
   masquerade as SPI. Fix: guards in `BXTP`/`BXPIPE`/`BSEC` (smallest seam:
   one paragraph each, before side effects). Tests `g5.prod.*`.
2. Arbitrary environment strings were accepted by `BPXCFG` and ignored. Fix:
   explicit whitelist + double-coherence rules in `BOPSCFG`. Tests
   `g5.bad.env.cfg`, `g5.blank.env.cfg`, `g5.qa.*`.
3. (Late GATE 4, caught by regression) `FAIL-CHECKPOINT` in `BBATEOD` wrote
   without `EC-OP=FINISH`, re-initializing the record instead of marking
   FAILED. Fix `BBATEOD.cbl` (`MOVE "FINISH" TO EC-OP` in FAIL-CHECKPOINT).
   Test `g4.eod.fail.state`.

No financial rule changed anywhere; diffs touch boundary/operations/config
validation only.

## 9. QA execution procedure (reproducible)

```
git rev-parse HEAD                    # source revision
make clean && make build && make test # must end: tests: 1627 ... failed: 0
make test && make test                # repeatability (no order/seed dependence)
```

Environment profile: default `etc/pix.cfg` (LOCAL_DOUBLE/QA). Adapters:
FIXTURE doubles only. Entry gate items from §9 of the review request are each
held by named families in `tests/run.sh` (§3–§5). Record build rc, counts,
stability in `status.md` (single source of truth per session).

Release candidate claim allowed: reproducible build+test at the revision above
— a QA candidate, not a production release.

## 10. Kof

`/home/mel/Kof4j` untouched (verified by this review's git state — no Kof
commits were made). No Kof runtime dependency exists in the COBOL core. The
intended future relationship (Kof ecosystem -> explicit integration contracts
-> KofBank production boundary -> COBOL core) is a target, not a present fact.
A separate evolution must design it against `BKBNDP`/CLI contracts, after this
review is approved.

## 11. Next recommended evolution

`kof-ecosystem-integration-design`: define the Kof-facing application contract
over the frozen CLI/`BKBNDP` boundary, with contract tests as the seam — still
no financial rules outside COBOL, still no real BCB connectivity.
