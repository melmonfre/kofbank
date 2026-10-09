# ADR 0012 transactions have an explicit lifecycle

decision: every transaction is a persistent state machine and posts once
reason: authorization must be separable from posting and reversals must not mutate history
consequences:
  - BTXNSTT is the only authority on allowed state transitions
  - txn.idx is the transaction record; BTXNSTO owns persistence
  - states are CR VA AU PO ST CP with RJ CN RT RV terminal
  - the ledger effect is produced only by POST, through BTXNPOST and BGLPST
  - BTXNPOST maps type to double entry and never touches balances directly
  - BTXNLFC enforces idempotency per operation and replays the stored result
  - reverse and return write a new transaction with TXN-ORIGIN and opposite postings
  - limits are checked at authorize, consumed at settle, released on reverse and return
  - reconciliation TXN matches settled transactions against postings.log
status: accepted
