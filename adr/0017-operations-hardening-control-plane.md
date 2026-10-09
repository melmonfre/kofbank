# ADR 0017 operations hardening is control state, never financial truth

decision: system lifecycle, startup safety classification, EOD batch
checkpointing, backup/restore, stale-lock inspection, incidents, correlation
and configuration verification are implemented as operational control state
that observes, gates and records the already-verified financial core; no
operational component may create, mutate or repair ledger, balance,
settlement or journal truth
reason: an institution must survive crashes, operator error, media failure
and partial batches without ever doubting its books; the fastest way to
lose that trust is operational tooling that "helpfully" fixes financial
state; mainframe practice (CICS region state, JCL restart, DFSMSdss
consistency quiesce, RACF-audited operator actions) treats these as a
distinct control plane with its own datasets and audit trail
consequences:
  - BLIFE (var/run/life.dat) stores only STOPPED/RUNNING/DRAINING/MAINTENANCE/
    RECOVERY_REQUIRED/RECOVERING with generation, timestamp, operator and
    reason; BANKCLI enforces the domain gate for every request; when the file
    does not exist the system runs unchanged in legacy mode so pre-GATE-4
    deployments and the full 1510-test regression are untouched
  - BOPSCK (ops.inspect / ops.health) is strictly read-only: it scans txn
    status AU, journal stage markers, outbox pending/unknown, inbound
    RECEIVED identities, open reconciliation exceptions, EOD checkpoints and
    the structural integrity of journal/postings/events/audit chains, then
    returns CLEAN / RECOVERABLE / OPERATOR_REQUIRED / CORRUPT; ops.start is
    fail-closed (CORRUPT refuses start; non-CLEAN starts into
    RECOVERY_REQUIRED instead of RUNNING); nothing is ever auto-repaired
  - BEODCHK (var/data/eodchk.idx) marks EOD stages (25 of them) durably
    before advancing; batch.eod|RESUME skips completed stages and repeats
    none; stage effects remain idempotent from GATE 2, so a wrong mask can
    only cost a replayed idempotent step, never a duplicated financial
    effect; the checkpoint is purgable operational metadata
  - BOPSBK packages var/data + var/journal + var/audit + etc with a sorted
    manifest; CREATE is permitted only while STOPPED/DRAINING/MAINTENANCE
    (application-consistent copy, DFSMSdss-style quiesce); APPLY demands the
    explicit CONFIRM-RESTORE token, refuses while RUNNING, verifies the
    package first and moves the live tree to var/data.precall.<tag> instead
    of deleting it; restore.verify reports LIVE-DIVERGED without touching
    anything; no secrets exist in the tree to leak (GATE 3 rule inherited)
  - BOPSSTALE lists BLCK entries as FRESH/STALE from their expiry instant
    and releases only expired locks, requiring an audited reason; detection
    never implies deletion (stale locks must be understood, not swept)
  - BOPSINC (var/data/opsinc.idx) keeps OPEN -> ACK -> RESOLVED as a strict
    operator narrative with evidence, severity and resolution note; resolved
    incidents are immutable; operational tooling does not open or resolve
    incidents on its own
  - BOPSCO correlates one id across txn, journal stage, outbox, message
    identity, exception, incident stores and the four chain logs; read-only
    evidence gathering for the recovery runbook
  - BOPSCFG fails closed on dangerous configuration combinations (PRODUCTION
    with LOCALDOUBLE transport, LOCAL_DOUBLE security, empty signing cert
    reference or trusted issuer); it reports effective config and changes
    nothing
  - every privileged operator action carries explicit operator + correlation
    and lands in the existing BAUD chain (LIFE.CHANGE, LOCK.RELEASE,
    BK.CREATE, BK.APPLY, INC.*); this is an authorization boundary under an
    institution's identity rules, not an invented IAM
  - production replacements are named, not faked: region state from
    CICS/MVS console, backup from DFSMSdss with the same quiesce invariant,
    batch restart from JCL/checkpoint utilities, operator identity from
    RACF/EACF, alerting from enterprise monitoring; the COBOL control plane
    here is the contract those adapters must satisfy
  - capacity, RPO/RTO and multi-site DR remain institutional open items;
    nothing in this gate claims them
