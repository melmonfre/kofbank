# capability-map

status legend: implemented | partial | stub | designed | missing | not-applicable
only executable, tested behavior counts as implemented

status: foundation | customer | account | ledger | txn | batch | payments | product | interest | limits | reconciliation | credit | loans | collections

| capability | status | location | tests | dependencies | production-dependency |
|---|---|---|---|---|---|
| foundation-runtime | implemented | cobol/foundation | core | - | - |
| idempotency | implemented | cobol/foundation/BIDM | yes | - | - |
| audit | implemented | cobol/foundation/BAUD | yes | - | - |
| events | implemented | cobol/foundation/BEVT | yes | - | MQ boundary |
| locks | partial | cobol/foundation/BLCK | no | - | - |
| sequences | implemented | cobol/foundation/BSEQ | yes | - | - |
| config | implemented | cobol/foundation/BCFG | yes | - | - |
| party-customer | implemented | cobol/customers | yes | - | - |
| customer-relationships | missing | - | no | customer | - |
| beneficial-owner | missing | - | no | customer | KYC |
| address-contact | partial | cobol/customers | yes | customer | - |
| customer-segmentation | missing | - | no | customer | - |
| customer-risk | partial | cobol/customers | yes | customer | - |
| kyc | partial | cobol/customers | yes | customer | KYC |
| account | implemented | cobol/accounts | yes | customer, ledger | - |
| account-products | partial | cobol/accounts | yes | - | - |
| joint-accounts | missing | - | no | account, customer | - |
| account-ownership | missing | - | no | account | - |
| account-restrictions | missing | - | no | account | - |
| account-limits | missing | - | no | account, limits | - |
| product-catalog | implemented | cobol/products | yes | foundation | - |
| product-effective-dating | implemented | cobol/products/BPRODQ | yes | product-catalog | - |
| ledger | implemented | cobol/ledger | yes | foundation | - |
| chart-of-accounts | implemented | etc/chart.cfg | yes | ledger | - |
| journal | implemented | cobol/ledger | yes | ledger | - |
| posting | implemented | cobol/ledger/BGLPST | yes | ledger | - |
| trial-balance | implemented | cobol/ledger/BGLTB | yes | ledger | - |
| accounting-period | missing | - | no | ledger | - |
| financial-close | missing | - | no | ledger, batch | - |
| accruals | missing | - | no | ledger, interest | - |
| suspense-accounts | missing | - | no | ledger | - |
| txn-lifecycle | implemented | cobol/transactions/BTXNLFC | yes | account, ledger, limits | - |
| deposits | implemented | cobol/transactions/BTXNPOST | yes | account, ledger | - |
| withdrawals | implemented | cobol/transactions/BTXNPOST | yes | account, ledger | - |
| transfers-internal | implemented | cobol/transactions/BTXNPOST | yes | account, ledger | - |
| txn-authorization | implemented | cobol/transactions/BTXNLFC | yes | transactions, limits | - |
| txn-posting | implemented | cobol/transactions/BTXNPOST | yes | transactions, ledger | - |
| txn-reversal | implemented | cobol/transactions/BTXNREV | yes | transactions, ledger | - |
| txn-correction | missing | - | no | transactions, ledger | - |
| payments | implemented | cobol/payments | yes | account, ledger | - |
| payment-return | implemented | cobol/payments/BPAYRTN | yes | payments | - |
| payment-reversal | implemented | cobol/payments/BPAYRTN | yes | payments | - |
| payment-rails | implemented | etc/rails.cfg | yes | payments | rail adapters |
| payment-scheduling | missing | - | no | payments, batch | - |
| payment-batches | missing | - | no | payments, batch | - |
| payment-limits | missing | - | no | payments, limits | - |
| payment-fees | missing | - | no | payments, fees | - |
| payment-reconciliation | implemented | cobol/payments/BPAYEOD | yes | payments, ledger | - |
| pix | missing | - | no | payments | Pix spec (external) |
| credit | implemented | cobol/credit | yes | customer, account, ledger, product, interest, limits, txn | - |
| credit-application | implemented | cobol/credit/BCRA | yes | credit, customer | - |
| credit-facility | implemented | cobol/credit/BCRF | yes | credit-application | - |
| credit-exposure | implemented | cobol/credit/BCRUPD | yes | credit-facility, ledger | - |
| credit-schedule | implemented | cobol/credit/BCRSCH | yes | credit-facility, interest | - |
| credit-disbursement | implemented | cobol/credit/BCRDIS | yes | credit-facility, txn-lifecycle | - |
| credit-repayment | implemented | cobol/credit/BCRPAY | yes | credit-facility, txn-lifecycle | - |
| credit-writeoff | implemented | cobol/credit/BCRWOF | yes | credit-facility, ledger | - |
| loans | implemented | cobol/loans | yes | credit, interest, ledger, txn | - |
| loan-agreement | implemented | cobol/loans/BLN | yes | credit-facility, product | - |
| loan-amortization | implemented | cobol/loans/BLNSCH | yes | loan-agreement, interest | - |
| loan-disbursement | implemented | cobol/loans/BLNDIS | yes | loan-agreement, txn-lifecycle | - |
| loan-repayment | implemented | cobol/loans/BLRPAY | yes | loan-amortization, txn-lifecycle | - |
| loan-writeoff | implemented | cobol/loans/BLNWOF | yes | loan-agreement, ledger | - |
| loan-lifecycle | implemented | cobol/loans/BLNST | yes | loan-agreement | - |
| loan-eod | implemented | cobol/batch/BLNCEOD | yes | loans, batch-eod | - |
| recon-loan | implemented | cobol/reconciliation/BRECLON | yes | loans, ledger | - |
| loan-restructuring | partial | cobol/loans/BLN | yes | loan-agreement | jurisdiction |
| collateral | missing | - | no | credit | - |
| interest | implemented | cobol/interest/BINT | yes | - | - |
| fees | partial | cobol/interest/BINT | yes | ledger | - |
| tax | missing | - | no | ledger | jurisdiction |
| collections | missing | - | no | credit, payments | - |
| cards | missing | - | no | account, payments | card network |
| merchant-acquiring | missing | - | no | cards, payments | card network |
| treasury | missing | - | no | ledger, fx | - |
| fx | missing | - | no | ledger | rate source |
| international-banking | missing | - | no | payments, fx | SWIFT |
| investments | missing | - | no | ledger | exchange |
| trade-finance | missing | - | no | credit, international | - |
| corporate-banking | missing | - | no | customer, payments | - |
| limits | implemented | cobol/limits | yes | foundation | - |
| risk | missing | - | no | credit, ledger | - |
| fraud | missing | - | no | limits, txn | rules only |
| aml | missing | - | no | customer, txn | regulation |
| reconciliation | implemented | cobol/reconciliation | yes | ledger, payments | - |
| recon-ledger | implemented | cobol/reconciliation/BRECLGR | yes | ledger | - |
| recon-payment | implemented | cobol/reconciliation/BRECPAY | yes | payments | - |
| recon-transaction | implemented | cobol/reconciliation/BRECTXN | yes | transactions | - |
| recon-external | implemented | cobol/reconciliation/BRECEXT | yes | external files | external statements |
| recon-exceptions | implemented | cobol/reconciliation/BRECESO | yes | - | - |
| recon-resolution | implemented | cobol/reconciliation/BRECRES | yes | ledger, txn | - |
| recon-credit | implemented | cobol/reconciliation/BRECCRD | yes | credit, ledger | - |
| batch-eod | implemented | cobol/batch | yes | all | JCL/JES |
| credit-eod | implemented | cobol/batch/BCRCRDEOD | yes | credit, batch-eod | - |
| batch-eom-eoy | missing | - | no | batch, accounting | - |
| statements | missing | - | no | account, ledger | - |
| reporting | partial | cobol/batch | yes | ledger | - |
| mainframe-execution | designed | jcl/ | no | - | z/OS, CICS, DB2, MQ |
| persistence-vsam | implemented | var/data | yes | - | VSAM/IDCAMS |
| persistence-db2 | designed | docs/data-catalog | no | - | DB2 |
| messaging | partial | var/journal/events.log | yes | - | IBM MQ |
| security-rbac | designed | docs/security-catalog | no | - | RACF |
| operational-controls | partial | cobol/core, etc/bank.cfg | yes | - | - |
| data-integrity | partial | tests/run.sh | yes | all | - |
| failure-recovery | partial | tests/run.sh | yes | all | - |

## priority-unknowns

- kyc-thresholds: unknown
- regulatory-jurisdiction: unknown
- pix-spec: external authoritative source required
- card-network: external
- swift: external
- fx-rate-source: external

## rule

unknown requirements are explicit, never guessed.
