# ADR 0019 — Kof consumes KofBank through the KBCLI-1 request-line contract

Date: 2026-10-08
Status: accepted (kof-ecosystem-integration-design)

## Context

Kof must integrate with the frozen COBOL financial core without
becoming a second core. Inspection showed an already-documented, tested
contract (ADR 0006: one request line, key=value response, rc always) and a
complete Kof primitive set (`shell.pipeline`, `process.spawn`, `config.env`,
typed records, deterministic JSON) — no protocol or Kof change was missing.

## Decision

1. First integration contract = KBCLI-1: formalization (not invention) of the
   existing CLI surface, plus one new read-only verb `system.contract` for
   version handshake. rc semantics are carried unchanged; rc=24/26 and the
   unknown-outcome protocol are contract-level, client-visible.
2. Transport v1: synchronous child process via `shell.pipeline` (printf |
   build/bank). No HTTP/MQ/socket listener is introduced; a future facade
   must re-use the same request/response grammar and identity rules.
3. Kof side stays thin: `tools/kof/src/KofBank.kf` (~50 lines of parsing and
   identity passing) and `src/Main.kf` (executable QA integration). No Kof
   framework, SDK, or Kof4j repository change.
4. QA determinism: `make kof-test` runs against a fresh reset instance
   (`tests/run.sh --reset-only`), mirroring Gate 5 LOCAL_DOUBLE defaults.
   Kof checks are additive (1610 COBOL checks + 17 Kof checks); production
   activation remains fail-closed exactly as before.
5. Financial truth remains where it is: idempotency (BIDM), lifecycle
   (BTXNLFC VA->AU->PO->ST->CP), ledger math, journal and audit are exercised
   through the core, never reimplemented in Kof. The integration proves this
   by asserting exact core-returned balances and rc codes.

## Consequences

- Kof applications can compose banking flows (create->authorize->post->...
  and replay/tamper handling) in ~100 lines.
- Future transports inherit the same versioning rule (additive = compatible;
  grammar/rc-semantics change = new contract id).
- Nothing in Gates 1-5 changed behaviorally; the only COBOL delta is the
  read-only `system.contract` verb.
