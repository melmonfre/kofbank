# ADR 0006 request line contract

decision: one request line on stdin, key=value lines on stdout
reason: KISS, Unix, testable from shell
consequences:
  - BANKCLI routes by domain prefix
  - domain CLI calls core programs with LINKAGE groups
  - rc is always returned
status: accepted
