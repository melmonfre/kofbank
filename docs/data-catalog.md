# data-catalog

storage: indexed datasets (VSAM-like), sequential journal, line-sequential config
root: BANK_HOME

| entity | dataset | key | fields | sensitivity | retention |
|---|---|---|---|---|---|
| customer | var/data/cust.idx | cust-id | type status name doctype doc birth risk kyc addr created updated version hash | pii | life+ |
| customer-document | var/data/custdoc.idx | doctype+doc | cust-id | pii | life+ |
| account | var/data/acct.idx | acct-id | cust-id product currency status opened closed version hash | internal | life+ |
| balance | var/data/acctbal.idx | acct-id | ledger available blocked currency updated seq | internal | life+ |
| gl-account | var/data/gl.idx | gl-code | name type status | internal | life+ |
| transaction | var/data/txn.idx | txn-id | id type status src dst amount currency descr operator corr request origin reason ref jrn-id created posted settled version hash | internal | permanent |
| payment | var/data/pay.idx | pay-id | id type rail src dst amount currency status ref request corr operator descr txn-id jrn-id origin reason created valuedate settled version hash | internal | permanent |
| product | var/data/prod.idx | product-id+version | id version status name type currency effective min-balance daily-limit monthly-limit interest-bps fee hash | internal | life+ |
| limit-usage | var/data/limuse.idx | scope+key+period | scope key period date used | internal | period |
| reconciliation-run | var/data/rec.idx | run-id | id type status bizdate operator started finished src-count int-count matched unmatched-i unmatched-e exceptions open-exc adjustments amounts hash | internal | permanent |
| reconciliation-exception | var/data/recexc.idx | exc-id | id run-id type code status key src-ref int-ref amount currency bizdate reason resolution txn-ref operator created updated | internal | permanent |
| credit-application | var/data/crapp.idx | app-id | id cust-id product account requested approved term status conditions reason operator created updated version hash | internal | permanent |
| credit-facility | var/data/crfac.idx | fac-id | id cust-id product account app-id status approved contracted currency term basis rate-bps eff expires maturity collateral conditions reason created updated version hash | internal | permanent |
| credit-exposure | var/data/crexp.idx | fac-id | fac-id product currency approved contracted principal pending overdue interest-accr fees-accr paid-prin status updated version hash | internal | permanent |
| credit-obligation | var/data/crobl.idx | fac-id+installment | key due-date principal interest fees paid-prin paid-int paid-fee total-due status eff-date updated version | internal | permanent |
| loan | var/data/loans.idx | loan-id | id cust-id fac-id product account status currency principal disbursed principal-paid principal-wo outstanding overdue-prin term basis rate-bps amort freq contract-date eff-date first-due maturity disb-date disb-txn installments reason created updated version hash | internal | permanent |
| loan-installment | var/data/loaninst.idx | loan-id+installment | key number due-date opening-bal principal interest fees total-due paid-prin paid-int paid-fee close-bal status eff-date updated version | internal | permanent |
| journal | var/journal/journal.log | line | header and posting lines | internal | permanent |
| postings | var/journal/postings.log | line | gl dc amount entity currency journal date | internal | permanent |
| events | var/journal/events.log | line | type key bizdate time payload | internal | permanent |
| audit | var/audit/audit.log | seq | seq time bizdate operator action entity corr before after result | internal | permanent |
| idempotency | var/data/idm.idx | txn-id | operation status result created | internal | life+ |
| lock | var/data/lock.idx | name | owner date secs | internal | transient |
| sequence | var/data/seq_*.dat | file | counter | internal | life+ |

## record-sizes

- journal line 500
- posting line 300
- event line 400
- audit line 400

## integrity

- customer id format C + 11 digits
- account id format A + 11 digits
- payment id format P + 11 digits
- transaction id format T + 11 digits
- credit application id format L + 11 digits
- credit facility id format F + 11 digits
- credit obligation key is facility id + 4-digit installment
- loan id format N + 11 digits
- loan installment key is loan id + 4-digit installment
- amounts S9(15)V99 COMP-3
