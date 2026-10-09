# ADR 0004 idempotency

decision: request id stored in idm.idx with state R C F
reason: online retries must not double post
consequences:
  - replay returns stored result, rc 00
  - concurrent duplicate returns rc 24
  - failed request is recorded as F
status: accepted
