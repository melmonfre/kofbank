# ADR 0013 credit is a domain over the canonical transaction lifecycle

decision: model credit as product, application, facility, exposure, obligation and
credit transactions; every financial effect flows through the canonical transaction
lifecycle and ledger
reason: credit must not create a parallel financial model or a second source of truth
consequences:
  - hierarchy is Credit Product -> Facility/Agreement -> Exposure -> Transactions
  - approval is never disbursement; the facility has its own state machine
  - BCRFST is the only authority on facility transitions; closed/cancelled never reactivate
  - exposure in crexp.idx is derived from settled credit transactions, not authoritative
  - BCRUPD is the only writer of exposure; BCRXSTO owns persistence
  - BCRSCH builds installments in crobl.idx without duplicating ledger balances
  - BCRDIS, BCRPAY and BCRWOF emit canonical txns (CREDDISB, CREDREPY, CREDFEE, CREDWOFF)
  - BCRENV provides idempotency, audit and events for credit operations
  - posting rules: disbursement Dr3000/Cr2000, fee Dr4000/Cr2000,
    repayment Dr2000/Cr4100 interest and Dr2000/Cr3000 principal,
    writeoff Dr5100/Cr3000
  - disbursement is rejected when amount plus fee exceeds contracted exposure
  - BCRCRDEOD marks overdue exposure and matures facilities with zero outstanding
  - BRECCRD reconciles exposure principal against settled credit transactions
  - allocation order is fee, interest, principal and is a product field
status: accepted
