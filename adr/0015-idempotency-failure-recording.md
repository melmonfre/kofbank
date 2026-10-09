# ADR 0015 failed requests are recorded as failed

decision: an operation that begins under a request id and then fails must record
the request as failed, so a later retry with the same request id re-executes
instead of returning a stale success
reason: ADR 0004 states a failed request is recorded as F, but BCRENV reset its
result code at entry and callers returned before the end call, so failed requests
stayed in progress or were recorded as completed with an empty result
consequences:
  - BCRENV resets the result code only on BEGIN, never on END
  - loan operations run their work in a paragraph and always invoke the end step,
    so success records C and failure records F
  - a retry of a failed request with the same request id re-executes and returns
    the real failure again
  - a successful retry after the cause is removed completes normally
  - replay of a completed request still returns the stored result without
    re-executing, preserving ADR 0004
status: accepted
