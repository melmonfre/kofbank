# Production Boundary (GATE 3)

KofBank keeps the COBOL core as the single financial truth. This document
defines the boundary layer that replaces the mainframe edge: protocol,
transport, security references, external identity and external
reconciliation. The boundary is implemented and verified against
deterministic local doubles ONLY. Nothing here connects to, or claims
compliance with, real SPI/DICT/Banco Central infrastructure.

## Ownership split

| Concern | Owner |
|---|---|
| Ledger, journal, balances, settlement, transaction state, financial idempotency | core |
| Protocol/serialization, transport, certificate metadata, signing seam, external correlation, response mapping, outbox intent | boundary |
| Real network/MQ, real certificates, HSM, key custody | NOT AVAILABLE (production integration) |

The boundary may never: post to the GL, mutate balances, create financial
effects, invent regulatory values, silently repair divergences, or retry an
unknown external outcome without correlating it first.

## Components

- `BXTP` (transport contract). `SEND`/`QUERY` over `BD-CHANNEL` (SPI/DICT)
  routing to the existing `BPXSPI`/`BPXDICT` doubles. Classifies outcomes:
  `OK` / `RJCT` / `UNK` (needs correlation) / `TPERR` (retryable transport
  error). Copybook: `BKBNDP`.
- `BXOUTB` (durable outbound intent / outbox). One record per internal
  operation (`var/data/bndout.idx`): what/why/internal ref/external
  identity (E2E, MsgId), fingerprint, retries, cert ref, signature, state
  `PENDING/SENT/ACKED/REJECTED/UNKNOWN`. Retry reuses the same external
  identity. `QUERY` resolves unknowns through the double; `CORRELATE`
  records an explicit operator result with reason; `REAP` ages unresolved
  intents into `UNKNOWN`. Audit + event per state change. Never GL.
- `BXMSGID` (external message identity registry, `var/data/bndmsgid.idx`).
  MsgId -> version/family/E2E/fingerprint/state/internal ids. Replay-safe
  BEGIN/GET/COMPLETE/FAIL: reuse with a different fingerprint is rejected
  (rc 26); completed messages replay without new effects.
- `BSEC` (certificate + security seam, `var/data/bndcrt.idx`). Lifecycle
  `ACTIVE/NOT_VALID_YET/EXPIRED/REVOKED/ROTATED` with validity windows;
  register/check/rotate/revoke/sign/verify. Signing is a deterministic
  `HASH-DOUBLE` over `SIG|certid|env|canonical`. Only cert references and
  metadata exist; no keys or secret material anywhere.
- `BXPIPE` (inbound processing). Fixed stage order: receive/schema ->
  security (cert valid + signature over `msgid|e2e|gross|msgnm`) ->
  message identity/idempotency -> normalization to the existing `BPXSTX`
  contract -> core operation -> outcome persistence. A failed stage stops
  the pipeline; effects appear only after all validation passes.
- `BRECBND` (external reconciliation, `reconciliation.run|BOUNDARY`).
  Compares intent vs external settlement record vs message registry vs
  journal. Durable exception codes: `OUTB_STALE`, `OUTB_UNCORR`,
  `OUTB_NOEXT`, `OUTB_CONF`, `OUTB_AMT`, `MSG_UNFIN`, `MSG_NOLEDG`.
  Runs inside EOD (`RECON-BOUNDARY` report line).
- `BBNDCLI` (`bank bnd.*`). Thin CLI over the above contracts.

## Configuration (etc/pix.cfg)

`environment=LOCAL_DOUBLE`, `transport-adapter=LOCALDOUBLE`,
`security-adapter=LOCAL_DOUBLE`, `sign-algorithm=HASH-DOUBLE`,
`transport-timeout-secs`, `outbound-max-retry`, `signing-cert-ref`
(reference only), `boundary-clock-ref=SYSTEM`. These are explicit choices,
not hardcoded assumptions; HOMOLOGATION/PRODUCTION values must be selected
operationally before any real integration.

## Failure seams (`KOF_BND_SEAM`)

`TP-BEFORE-SEND`, `TP-AFTER-SEND`, `CRASH_BEFORE_SEND`,
`CRASH_AFTER_SEND`, `CRASH_BEFORE_RESPERSIST`, `CRASH_AFTER_RESPERSIST`,
`SECURITY_FAILURE`, `MALFORMED_RESPONSE`. All verified in the suite: no
crash seam produces a double financial effect; every unresolved send
converges through query/correlate/reap.

## Mainframe replacement boundary

A production transport or security adapter replaces exactly: the `BXTP`
routing target, the `BSEC` sign/verify backend (HSM/PKCS#11), and the
config values. No core program changes. Message-level regulatory formats
beyond the already modeled SPI Split Tax contract (`BPXSTX`) are
boundary-defined only; this gate does not claim full ISO 20022 validation,
real certificate PKI, or Bacen connectivity.
