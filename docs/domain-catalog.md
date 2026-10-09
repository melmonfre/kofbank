# domain-catalog

## foundation
owns: config, status codes, keys, hash, journal, audit, events, idempotency, locks, sequences
data: bank.cfg, journal.log, postings.log, events.log, audit.log, idm.idx, lock.idx, seq_*.dat
transactions: none (runtime)
events: none
batch: none
accounting: none
invariants:
  - journal header debit equals credit
  - idempotent request never posts twice
failure-modes: missing-dataset, corrupt-counter, lock-contention

## customer
owns: customer master, document uniqueness, lifecycle status
data: cust.idx, custdoc.idx
transactions: CUST.CREATE, CUST.UPDATE, CUST.STATUS
events: CUSTOMER.CREATED.v1, CUSTOMER.UPDATED.v1, CUSTOMER.STATUS.v1
accounting: none
invariants:
  - document is unique
  - closed customer cannot be updated
failure-modes: duplicate-document, invalid-transition

## account
owns: account master, product validation, lifecycle
data: acct.idx, prod.idx
transactions: ACCT.OPEN, ACCT.STATUS
events: ACCOUNT.CREATED.v1, ACCOUNT.BLOCKED.v1, ACCOUNT.CLOSED.v1
accounting: opening posts cash vs deposits
invariants:
  - account belongs to an active customer
  - product must exist
failure-modes: unknown-product, inactive-customer

## ledger
owns: chart of accounts, journal, postings, balances, trial balance
data: gl.idx, acctbal.idx, journal.log, postings.log
transactions: posting, reversal
events: none
accounting: double-entry
invariants:
  - debit equals credit
  - balance is explainable by postings
failure-modes: unbalanced-entry, unknown-gl, missing-chart

## transactions
owns: transaction lifecycle: deposit, withdrawal, transfer, fee, reversal, return
data: txn.idx, postings.log, acctbal.idx
transactions: TXN.CREATE, TXN.AUTHORIZE, TXN.POST, TXN.SETTLE, TXN.COMPLETE, TXN.CANCEL, TXN.REVERSE, TXN.RETURN, TXN.GET, TXN.LIST
events: TRANSACTION.POSTED.v1, TRANSACTION.CANCELLED.v1, TRANSACTION.REVERSED.v1, TRANSACTION.RETURNED.v1
accounting: cash vs deposits, deposits between accounts, fee income
states: CR VA AU PO ST CP | RJ CN RT RV
invariants:
  - amount positive
  - active accounts and matching currency
  - available balance covers withdrawal, fee and transfer
  - ledger effect only on POST, once
failure-modes: insufficient-funds, inactive-account, invalid-transition

## products
owns: effective-dated product definitions and rules
data: prod.idx, product.def
transactions: PRODUCT.INIT, PRODUCT.GET
events: none
accounting: none
invariants:
  - a product version is immutable once effective
  - rules resolve by effective date, not current date
failure-modes: missing-config, unknown-product, future-effective-date

## interest
owns: deterministic interest, compounding and fee calculation
data: none (pure function)
transactions: INTEREST.ACCRUE, INTEREST.COMPOUND, INTEREST.FEE
events: none
accounting: consumed by accrual postings when wired
invariants:
  - monetary results are rounded deterministically
  - basis is 360 or 365
failure-modes: rate-out-of-range, invalid-basis, non-positive-days

## limits
owns: centralized limit rules and period usage
data: limuse.idx, limits.cfg
transactions: LIMIT.CHECK, LIMIT.CONSUME, LIMIT.RELEASE
events: none
accounting: none
invariants:
  - consumption is per scope, key and period
  - release never drives usage below zero
failure-modes: limit-exceeded, missing-config

## payments
owns: payment instruction lifecycle, rails, currencies, return, reversal, reconciliation
data: pay.idx, rails.cfg, currencies.cfg
transactions: PAYMENT.CREATE, PAYMENT.RETURN, PAYMENT.REVERSE
events: PAYMENT.SETTLED.v1, PAYMENT.RETURNED.v1, PAYMENT.REVERSED.v1
accounting: delegates to ledger via BPAYPOST, Dr 2000 source / Cr 2000 destination
invariants:
  - payment is not a second ledger
  - settled payment is never deleted
  - return or reversal creates a new linked effect
failure-modes: unknown-rail, currency-mismatch, insufficient-funds, invalid-transition

## reconciliation
owns: reconciliation runs, matching, differences, exceptions, resolution
data: rec.idx, recexc.idx, postings.log, acctbal.idx, pay.idx, external files
transactions: RECON.RUN, RECON.RESOLVE
events: none (audited)
accounting: none; reconciliation never posts, it requests corrections through txn and ledger
invariants:
  - a run is identified deterministically by type and business date
  - a balanced run has zero open exceptions
  - exceptions are never deleted
  - resolution that changes financial state carries a financial reference
failure-modes: external-file-missing, run-exists, balance-mismatch, orphan-posting, unmatched-record

## credit
owns: credit applications, facilities, exposure, obligations, disbursement, repayment, writeoff
data: crapp.idx, crfac.idx, crexp.idx, crobl.idx, txn.idx, postings.log, acctbal.idx
transactions: CREDIT.APPLICATION.CREATE/APPROVE/CONDITION/SATISFY/REJECT/CANCEL,
  CREDIT.FACILITY.ORIGINATE/APPROVE/CONTRACT/ACTIVATE/SUSPEND/RESUME/BLOCK/UNBLOCK/EXPIRE/MATURE/CLOSE/CANCEL/DEFAULT,
  CREDIT.DISBURSEMENT.CREATE, CREDIT.REPAYMENT.CREATE, CREDIT.WRITEOFF.CREATE, CREDIT.SCHEDULE.GENERATE
events: CREDIT.APPLICATION.v1, CREDIT.FACILITY.v1, CREDIT.DISBURSEMENT.v1, CREDIT.REPAYMENT.v1, CREDIT.WRITEOFF.v1
accounting: disbursement Dr 3000 / Cr 2000, fee Dr 4000 / Cr 2000;
  repayment Dr 2000 / Cr 4100 interest, Dr 2000 / Cr 3000 principal;
  writeoff Dr 5100 / Cr 3000
invariants:
  - approval is not disbursement
  - exposure is derived from canonical transactions, never an independent source
  - closed or cancelled facility never reactivates
  - writeoff reduces outstanding but never deletes debt history
  - disbursement over contracted exposure is rejected
  - repayment allocates fees, then interest, then principal
failure-modes: over-limit, invalid-transition, exposure-missing, not-active

## loans
owns: loan agreements, amortization installments, disbursement, repayment, writeoff
data: loans.idx, loaninst.idx, txn.idx, postings.log, acctbal.idx
transactions: LOAN.CREATE, LOAN.APPROVE/CONTRACT/ACTIVATE/SUSPEND/RESUME/DELINQUENT/DEFAULT/MATURE/SETTLE/CLOSE/CANCEL/RESTRUCTURE,
  LOAN.SCHEDULE, LOAN.DISBURSEMENT, LOAN.REPAYMENT, LOAN.WRITEOFF
events: LOAN.CREATED.v1, LOAN.APPROVED.v1, LOAN.CONTRACTED.v1, LOAN.ACTIVATED.v1,
  LOAN.DEFAULTED.v1, LOAN.MATURED.v1, LOAN.SETTLED.v1, LOAN.CLOSED.v1, LOAN.CANCELLED.v1,
  LOAN.DISBURSEMENT.v1, LOAN.REPAYMENT.v1, LOAN.WRITEOFF.v1
accounting: reuses canonical credit txn types CREDDISB, CREDREPY, CREDWOFF with the
  same posting rules as credit; the loan is the source entity, not a second ledger
invariants:
  - a loan is originated under an active credit facility and never exceeds available credit
  - loan state and transaction state are distinct dimensions
  - installment schedule is built without duplicating ledger balances
  - outstanding = disbursed - principal paid - principal written off, never negative
  - repayment allocates by the product allocation order, capped by outstanding principal
  - every financial effect flows through the canonical transaction lifecycle
  - closed, cancelled or settled loans never disburse or reactivate
failure-modes: facility-not-active, over-limit, invalid-transition, nothing-to-allocate,
  amount-exceeds-outstanding, not-repayable

## batch
owns: end-of-day
data: var/out/eod_<date>.txt
transactions: BATCH.EOD
events: BATCH.EOD.v1
invariants:
  - eod fails if trial balance is not balanced
  - eod fails if any reconciliation run has open exceptions
failure-modes: out-of-balance, missing-dataset
