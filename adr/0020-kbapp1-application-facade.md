# ADR 0020 - KBAPP-1 application facade (BFF) vertical slice

Date: 2026-10-08
Status: accepted (local QA scope)

## Context
The product needs an application-facing surface (JSON HTTP) over KofBank without
leaking COBOL contracts into the frontend and without moving financial authority
out of the core.

## Decision
1. Introduce `KBAPP-1`: Kof `web.app()` BFF (`tools/kof/facade/Bff.kf`) that only
   composes responses, maps identity/errors and calls the unchanged KBCLI-1 client
   (`tools/kof/src/KofBank.kf`). All financial state stays COBOL-authoritative.
2. Session model is explicitly a dev/QA boundary (`SES.<user>.<customer>`), using
   `X-Session-Token` to avoid the Kof web built-in `Authorization` pipeline.
3. Core return codes map deterministically to HTTP (20/22/23/24/26/35-36 ->
   400/422/404/504/409/500) and unknown outcome is never marked retryable.
4. The frontend slice is the view-state machine in `Portal.kf` plus the HTTP-only
   portal flow; no balances or financial logic exist in the view layer.
5. QA runs as `make kof-facade-test` (38 checks, 3 JVM packages) on the fail-closed
   LOCAL_DOUBLE profile; `make kof-portal` is the runnable demo.

## Consequences
- Frontends never see `domain.verb|args`, `rc=`, or padded fields.
- BFF crash/absence is a UX outage, never a ledger outage or double-post.
- Production auth/TLS/deploy hardening remain open gates; this slice claims none.

## Known upstream toolchain bugs hit (workarounds, Kof4j untouched)
- KOF-002: record methods containing real empty-string `""` literals and helper
  calls emit zero-length constant-pool entries / `String.""` methodrefs
  (ClassFormatError). Workaround: suites are plain global functions per directory
  (`SuiteA/B/C.kf`), never records, and each `kof run` dir holds exactly one .kf
  (sibling sources silently join the package).
- `val` is a reserved word (local was renamed `vtext`).
