# ADR 0008 payments delegate to the ledger

decision: payments own instruction lifecycle, rails and reconciliation, never balances
reason: one ledger is the single source of financial truth
consequences:
  - BPAYOPR and BPAYRTN call BPAYPOST, which calls BGLPST
  - settlement is Dr 2000 source / Cr 2000 destination
  - return and reversal post a new linked effect, never mutate history
  - a settled payment record is never deleted
  - BPAYEOD reconciles settled payments against postings.log
status: accepted
