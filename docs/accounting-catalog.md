# accounting-catalog

## chart of accounts

| code | name | type |
|---|---|---|
| 1000 | CASH | asset |
| 1100 | DUE FROM BANKS | asset |
| 2000 | CUSTOMER DEPOSITS | liability |
| 3000 | LOAN PORTFOLIO | asset |
| 4000 | FEE INCOME | revenue |
| 4100 | INTEREST INCOME | revenue |
| 5000 | INTEREST EXPENSE | expense |
| 5100 | CREDIT LOSS | expense |
| 6000 | FX POSITION | asset |
| 7000 | SETTLEMENT CLEARING | asset |
| 8000 | EQUITY | liability |

## entries

| operation | debit | credit | subledger |
|---|---|---|---|
| account-opening | 1000 initial | 2000 initial | acctbal |
| deposit | 1000 amount | 2000 amount | acctbal |
| withdrawal | 2000 amount | 1000 amount | acctbal |
| transfer | 2000 from | 2000 to | acctbal |
| fee | 2000 account | 4000 amount | acctbal |
| txn-reversal | opposite of origin | opposite of origin | acctbal |
| txn-return | opposite of origin | opposite of origin | acctbal |
| payment-settle | 2000 source | 2000 destination | acctbal |
| payment-return | 2000 destination | 2000 source | acctbal |
| payment-reversal | 2000 destination | 2000 source | acctbal |
| credit-disbursement | 3000 facility | 2000 account | acctbal |
| credit-disbursement-fee | 4000 facility | 2000 account | acctbal |
| credit-repayment-principal | 2000 account | 3000 facility | acctbal |
| credit-repayment-interest | 2000 account | 4100 facility | acctbal |
| credit-writeoff | 5100 facility | 3000 facility | acctbal |
| loan-disbursement | 3000 facility | 2000 account | acctbal |
| loan-disbursement-fee | 4000 facility | 2000 account | acctbal |
| loan-repayment-principal | 2000 account | 3000 facility | acctbal |
| loan-repayment-interest | 2000 account | 4100 facility | acctbal |
| loan-writeoff | 5100 facility | 3000 facility | acctbal |

loan operations reuse the canonical credit transaction types and posting rules;
the loan agreement is the source entity and the credit facility remains the
exposure and ledger owner.

## calculation-primitives

| primitive | program | input | output | posting |
|---|---|---|---|---|
| simple-interest | BINT ACCRUE | amount, bps, days, basis | interest | not wired yet |
| compound-interest | BINT COMPOUND | amount, bps, days | interest | not wired yet |
| fee | BINT FEE | fee | validated fee | not wired yet |

interest and fees are deterministic calculations. they become ledger effects only
when an accrual or fee posting explicitly calls BGLPST.

## reconciliation

- reconciliation reads postings and balances, it never writes them
- a difference is recorded as an exception, not corrected in place
- corrections must flow through transactions and BGLPST
- a run balances only when it has zero open exceptions
- approved adjustments carry the financial reference that created the effect

## rules

- every journal has equal total debit and total credit
- balance sign: asset debits positive, liability credits positive
- reversal mirrors debit and credit
- trial balance total debit equals total credit

## evidence

- var/journal/journal.log header + posting lines
- var/journal/postings.log flattened postings
- var/data/acctbal.idx explainable by postings
