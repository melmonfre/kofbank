# ADR 0018 — QA environment profile and fail-closed adapter selection

Date: 2026-10-08
Status: accepted (GATE 5, production-readiness-review)

## Context

Until this gate, environment selection was validated only by the static
`ops.config.verify` check and by `adapter != FIXTURE` guards inside `BXOUTB`.
A misconfigured `environment=PRODUCTION` still executed the local doubles,
which could masquerade as SPI/DICT. QA needs an explicit, reproducible profile
and production activation needs an honest refusal, not an implicit fallback.

## Decision

1. Enforce the environment at the executable choke points, before any side
   effect and before the crash-seam handling: `BXTP` (transport), `BXPIPE`
   (inbound), `BSEC` (sign/verify). Allowed runtime environments:
   `LOCAL_DOUBLE`, `QA` (alias, same double semantics), `PRODUCTION`. Unknown
   or blank values fail closed.
2. `PRODUCTION` has no installed adapter by design; the guards refuse with
   explicit messages (`... NOT INSTALLED`). Activation of a real adapter is
   future institutional work behind the unchanged `BKBNDP` contract.
3. `BOPSCFG` gains an environment whitelist and double-coherence rules:
   double-mode environments must keep `adapter=FIXTURE`,
   `transport-adapter=LOCALDOUBLE`, `security-adapter=LOCAL_DOUBLE`,
   `sign-algorithm=HASH-DOUBLE`. Production keeps its existing stricter rules.
4. A transport refusal never fabricates success: the outbound intent remains
   PENDING (nothing left the bank), and unknown-after-send stays UNKNOWN.
5. The QA profile is the repository default; no production endpoint,
   credential, or key exists in the codebase to be activated accidentally.

## Consequences

- Readiness classifications are separated: code/QA verified,
  BCB-integration READY (contracts) while production-deployment remains OPEN.
- `KOF_BND_SEAM` test hooks are meaningless in PRODUCTION because the guard
  runs first; QA determinism is unchanged for all pre-existing suites.
- Regression families: `g5.qa.*`, `g5.prod.*`, `g5.bad.env.*`,
  `g5.blank.env.*`, `g5.restored.*`.
