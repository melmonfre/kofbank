# ADR 0011 reconciliation is detection, not correction

decision: reconciliation records differences and never writes financial state
reason: the ledger is the single accounting source of truth
consequences:
  - matchers read postings, balances, payments and external files only
  - every difference becomes a persistent exception with a code and reason
  - corrections require a financial reference and flow through txn and BGLPST
  - a run balances only with zero open exceptions
  - EOD runs ledger and payment reconciliation and stops on open exceptions
  - run ids are deterministic so reruns are idempotent
status: accepted
