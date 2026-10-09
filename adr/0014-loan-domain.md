# ADR 0014 loan is a domain over credit and the canonical transaction lifecycle

decision: model loans as agreements originated under an active credit facility,
with their own state machine and amortization schedule; every financial effect
flows through the canonical transaction lifecycle and the existing credit ledger
accounts
reason: a loan is a distinct legal agreement but must not create a parallel
financial model, a second exposure register or a second ledger
consequences:
  - hierarchy is Customer -> Credit Facility -> Loan Agreement -> Installments -> Txn -> Ledger
  - loan state (BLNST) is independent from transaction state and credit facility state
  - loan states are REQ APV CON ACT SUS DFL DEF MAT SET CLO CAN; closed, cancelled
    and settled loans never reactivate or disburse
  - creation requires an active facility and principal within available credit
  - principal, term, basis and rate default from the credit facility; amortization
    is CSPR or CSPY and frequency is 1
  - BLNSCH builds installments in loaninst.idx using BINT and BDAT without
    duplicating ledger balances
  - BLNDIS, BLRPAY and BLNWOF emit canonical CREDDISB, CREDREPY and CREDWOFF
    transactions with the loan id as TXN-REF, so the existing BTXNPOST rules and
    the credit exposure update apply unchanged
  - outstanding = disbursed - principal paid - principal written off, never negative
  - BLRPAY plans allocation before posting; installments are only mutated after the
    transaction settles; allocation order is the product field PR-ALLOC-ORDER,
    default FIP, capped by outstanding principal
  - BLNCEOD marks overdue installments and accumulates facility overdue exposure;
    BRECLON reconciles loan outstanding against settled loan transactions
  - credit scoring, regulatory allocation order and provisioning remain explicit
    open dependencies and are not guessed
status: accepted
