# transaction-catalog

request-line: domain.op|args
result: rc=NN and fields

| id | purpose | input | validation | accounting | persistence | events | idempotency |
|---|---|---|---|---|---|---|---|
| CUST.CREATE | register customer | type name doctype doc birth addr op corr | name, doc, type P/J, unique doc | none | cust.idx, custdoc.idx | CUSTOMER.CREATED.v1 | doc unique |
| CUST.UPDATE | update customer | id name addr op corr | exists, not closed | none | cust.idx | CUSTOMER.UPDATED.v1 | none |
| CUST.STATUS | change status | id status op corr | allowed transition | none | cust.idx | CUSTOMER.STATUS.v1 | none |
| ACCT.OPEN | open account | cust product currency initial op corr req | active customer, known product, product minimum balance | Dr 1000 / Cr 2000 | acct.idx, journal, postings, acctbal | ACCOUNT.CREATED.v1 | request |
| ACCT.STATUS | change status | id status op corr | allowed transition | none | acct.idx | ACCOUNT.BLOCKED/CLOSED.v1 | none |
| TXN.CREATE | create transaction | type src dst amount currency descr op corr req | type known, amount>0, active accounts, currency, funds (WITHDRAW/FEE/TRANSFER) | none | txn.idx | TRANSACTION.POSTED.v1 | request |
| TXN.AUTHORIZE | authorize transaction | id op corr req | state VA, channel limit | none | txn.idx, limuse.idx | TRANSACTION.POSTED.v1 | request |
| TXN.POST | post ledger effect | id op corr req | state AU | type dependent: DEPOSIT Dr1000/Cr2000, WITHDRAW Dr2000/Cr1000, TRANSFER Dr2000/Cr2000, FEE Dr2000/Cr4000 | txn.idx, journal, postings, acctbal | TRANSACTION.POSTED.v1 | request |
| TXN.SETTLE | settle transaction | id op corr req | state PO | none | txn.idx, limuse.idx | TRANSACTION.POSTED.v1 | request |
| TXN.COMPLETE | complete transaction | id op corr req | state ST | none | txn.idx | TRANSACTION.POSTED.v1 | request |
| TXN.CANCEL | cancel before posting | id reason op corr req | state CR/VA/AU | none | txn.idx | TRANSACTION.CANCELLED.v1 | request |
| TXN.REVERSE | reverse settled txn | id reason op corr req | origin ST/CP | opposite of origin posting | txn.idx, journal, postings, acctbal | TRANSACTION.REVERSED.v1 | request |
| TXN.RETURN | return settled txn | id reason op corr req | origin ST/CP | opposite of origin posting | txn.idx, journal, postings, acctbal | TRANSACTION.RETURNED.v1 | request |
| TXN.GET | read transaction | id | exists | none | txn.idx | none | none |
| TXN.LIST | list transactions | none | none | none | txn.idx | none | none |
| PAYMENT.CREATE | create payment | type rail src dst amount currency descr op corr req idem | rail active, currency known, accounts active, funds | Dr 2000 src / Cr 2000 dst | pay.idx, journal, postings, acctbal | PAYMENT.SETTLED.v1 | idem or request, hash |
| PAYMENT.GET | read payment | id | exists | none | pay.idx | none | none |
| PAYMENT.RETURN | return settled payment | id reason op corr req idem | state ST or PR | Dr 2000 dst / Cr 2000 src | pay.idx, journal, postings, acctbal | PAYMENT.RETURNED.v1 | idem or request |
| PAYMENT.REVERSE | reverse settled payment | id reason op corr req idem | state ST | Dr 2000 dst / Cr 2000 src | pay.idx, journal, postings, acctbal | PAYMENT.REVERSED.v1 | idem or request |
| PRODUCT.INIT | load product definitions | none | product.def present | none | prod.idx | none | idempotent upsert |
| PRODUCT.GET | resolve effective product | id | effective version exists | none | prod.idx | none | none |
| INTEREST.ACCRUE | simple interest | amount bps days basis | amount>=0, rate<=99999, days>0, basis 360/365 | none | none | none | pure |
| INTEREST.COMPOUND | compound interest | amount bps days | same | none | none | none | pure |
| INTEREST.FEE | fee validation | fee | fee>=0 | none | none | none | pure |
| LIMIT.CHECK | evaluate limit | scope key period amount currency | within limit | none | limuse.idx | none | per period |
| LIMIT.CONSUME | consume limit | scope key period amount currency | within limit | none | limuse.idx | none | per period |
| LIMIT.RELEASE | release limit | scope key period amount currency | none | none | limuse.idx | none | per period |
| RECON.RUN | run reconciliation | type run-id file operator corr | known type, balanced if no exceptions | none | rec.idx, recexc.idx | none | run-id deterministic |
| RECON.GET | read run | run-id | exists | none | rec.idx | none | none |
| RECON.LIST | list runs | none | none | none | rec.idx | none | none |
| RECON.EXCEPTIONS | list run exceptions | run-id | none | none | recexc.idx | none | none |
| RECON.RESOLVE | resolve exception | exc-id action fin-ref operator reason | terminal check, adjustment needs financial ref | via existing txn only | recexc.idx, rec.idx, audit | none | per exception |
| BATCH.EOD | end of day | date | trial balanced, payments reconciled, recon runs have no open exceptions | none | var/out | BATCH.EOD.v1 | per date |
| CREDIT.APPLICATION.CREATE | create credit application | cust product account amount term op corr req | active customer, credit product, amount within min/max, term within max | none | crapp.idx | CREDIT.APPLICATION.v1 | request |
| CREDIT.APPLICATION.APPROVE | approve application | app approved conditions op corr req | state RCV/UND, decision amount <= requested | none | crapp.idx | CREDIT.APPLICATION.v1 | request |
| CREDIT.APPLICATION.CONDITION | require conditions | app conditions op corr req | state RCV | none | crapp.idx | CREDIT.APPLICATION.v1 | request |
| CREDIT.APPLICATION.SATISFY | satisfy conditions | app op corr req | state CND | none | crapp.idx | CREDIT.APPLICATION.v1 | request |
| CREDIT.APPLICATION.REJECT | reject application | app reason op corr req | state RCV/UND/CND | none | crapp.idx | CREDIT.APPLICATION.v1 | request |
| CREDIT.APPLICATION.CANCEL | cancel application | app reason op corr req | not terminal | none | crapp.idx | CREDIT.APPLICATION.v1 | request |
| CREDIT.FACILITY.ORIGINATE | originate facility | app account expires collateral op corr req | approved application | none | crfac.idx, crexp.idx | CREDIT.FACILITY.v1 | request |
| CREDIT.FACILITY.APPROVE | approve facility | fac op corr req | state REQ | none | crfac.idx | CREDIT.FACILITY.v1 | request |
| CREDIT.FACILITY.CONTRACT | contract facility | fac amount collateral conditions op corr req | state APV | none | crfac.idx | CREDIT.FACILITY.v1 | request |
| CREDIT.FACILITY.ACTIVATE | activate facility | fac op corr req | state CON | none | crfac.idx, crexp.idx | CREDIT.FACILITY.v1 | request |
| CREDIT.FACILITY.SUSPEND/RESUME/BLOCK/UNBLOCK | lifecycle controls | fac op corr req | state machine | none | crfac.idx | CREDIT.FACILITY.v1 | request |
| CREDIT.FACILITY.EXPIRE/MATURE/CLOSE/CANCEL/DEFAULT | terminal transitions | fac reason op corr req | state machine; mature only when outstanding principal is zero | none | crfac.idx | CREDIT.FACILITY.v1 | request |
| CREDIT.FACILITY.SCHEDULE.GENERATE | build installment schedule | fac principal rate basis term eff | active facility, term>0 | none | crobl.idx | none | request |
| CREDIT.DISBURSEMENT.CREATE | disburse principal | fac amount fee op corr req | active facility, amount+fee within available exposure | Dr 3000 / Cr 2000, fee Dr 4000 / Cr 2000 | txn.idx, crobl.idx, crexp.idx, journal, postings, acctbal | CREDIT.DISBURSEMENT.v1 | request |
| CREDIT.REPAYMENT.CREATE | repay facility | fac amount op corr req | facility not terminal | Dr 2000 / Cr 4100 interest, Dr 2000 / Cr 3000 principal, fee Dr 2000 / Cr 4000 | txn.idx, crobl.idx, crexp.idx, journal, postings, acctbal | CREDIT.REPAYMENT.v1 | request |
| CREDIT.WRITEOFF.CREATE | write off principal | fac amount reason op corr req | amount <= outstanding principal | Dr 5100 / Cr 3000 | txn.idx, crexp.idx, journal, postings, acctbal | CREDIT.WRITEOFF.v1 | request |
| CREDIT.INSTALLMENT.GET | read installment | fac installment | exists | none | crobl.idx | none | none |
| CREDIT.INSTALLMENT.LIST | list installments | fac | exists | none | crobl.idx | none | none |
| CREDIT.FACILITY.EXPOSURE | read exposure | fac | exists | none | crexp.idx | none | none |
| LOAN.CREATE | originate loan agreement | fac principal term amort freq op corr req | active facility, amort CSPR/CSPY, freq 1, principal within available credit | none | loans.idx | LOAN.CREATED.v1 | request |
| LOAN.APPROVE | approve loan | loan op corr req | state REQ | none | loans.idx | LOAN.APPROVED.v1 | request |
| LOAN.CONTRACT | contract loan | loan op corr req | state APV; sets first due and maturity | none | loans.idx | LOAN.CONTRACTED.v1 | request |
| LOAN.ACTIVATE | activate loan | loan op corr req | state CON, terms complete | none | loans.idx | LOAN.ACTIVATED.v1 | request |
| LOAN.SUSPEND/RESUME/DELINQUENT | lifecycle controls | loan op corr req | state machine | none | loans.idx | LOAN.SUSPENDED/ACTIVATED/DEFAULTED.v1 | request |
| LOAN.DEFAULT | default loan | loan reason op corr req | state ACT/SUS/DFL | none | loans.idx | LOAN.DEFAULTED.v1 | request |
| LOAN.MATURE/SETTLE/CLOSE/CANCEL | terminal transitions | loan reason op corr req | state machine; mature/settle/close only when outstanding is zero | none | loans.idx | LOAN.MATURED/SETTLED/CLOSED/CANCELLED.v1 | request |
| LOAN.RESTRUCTURE | restructure loan | loan reason op corr req | state ACT/DFL/DEF | none | loans.idx | LOAN.CONTRACTED.v1 | request |
| LOAN.SCHEDULE | build installment schedule | loan | state CON/ACT, principal>0, term>0 | none | loaninst.idx | none | request |
| LOAN.DISBURSEMENT | disburse principal | loan amount fee op corr req | active loan, not already disbursed, amount <= principal | CREDDISB Dr 3000 / Cr 2000, fee Dr 4000 / Cr 2000 | txn.idx, loaninst.idx, loans.idx, crexp.idx, journal, postings, acctbal | LOAN.DISBURSEMENT.v1 | request |
| LOAN.REPAYMENT | repay loan | loan amount op corr req | loan repayable, amount>0 | CREDREPY Dr 2000 / Cr 4100 interest, Dr 2000 / Cr 3000 principal, fee Dr 2000 / Cr 4000 | txn.idx, loaninst.idx, loans.idx, crexp.idx, journal, postings, acctbal | LOAN.REPAYMENT.v1 | request |
| LOAN.WRITEOFF | write off principal | loan amount reason op corr req | amount <= outstanding | CREDWOFF Dr 5100 / Cr 3000 | txn.idx, loans.idx, crexp.idx, journal, postings, acctbal | LOAN.WRITEOFF.v1 | request |
| LOAN.GET/LIST | read loans | loan or none | exists | none | loans.idx | none | none |
| LOAN.INSTALLMENT.GET/LIST | read installments | loan installment | exists | none | loaninst.idx | none | none |
| LOAN.EXPOSURE | read loan and facility exposure | loan | exists | none | loans.idx, crexp.idx | none | none |

## states

transaction: CR VA AU PO ST CP
  CR created, VA validated, AU authorized, PO posted, ST settled, CP completed
transaction-terminal: RJ rejected, CN cancelled, RT returned, RV reversed
reversal: post a new transaction linked to the origin via TXN-ORIGIN; never
  delete or mutate the origin effect

payment: CR VA AU PR ST RT RJ RV CN
  CR created, VA validated, AU authorized, PR processing, ST settled
  RT returned, RJ rejected, RV reversed, CN cancelled

reconciliation-run: CREATED MATCHING BALANCED EXCEPTIONS FINALIZED FAILED
reconciliation-exception: OPEN UNDER_REVIEW RESOLVED ACCEPTED REJECTED REPROCESSED CLOSED
difference-code: MISMATCH ORPHAN UNMATCHED DUPLICATE AMOUNT CURRENCY DATE INVALID

credit-application: RCV UND APV CND REJ CAN EXP CON
  RCV received, UND under review, APV approved, CND conditional,
  REJ rejected, CAN cancelled, EXP expired, CON converted
credit-facility: REQ APV CON ACT SUS BLK MAT CLO CAN DEF EXP
  REQ requested, APV approved, CON contracted, ACT active, SUS suspended,
  BLK blocked, MAT matured, CLO closed, CAN cancelled, DEF defaulted, EXP expired
credit-obligation: SC PT PA
  SC scheduled, PT partially paid, PA paid
credit-txn-type: CREDDISB CREDREPY CREDFEE CREDWOFF

loan: REQ APV CON ACT SUS DFL DEF MAT SET CLO CAN
  REQ requested, APV approved, CON contracted, ACT active, SUS suspended,
  DFL delinquent, DEF defaulted, MAT matured, SET settled, CLO closed, CAN cancelled
loan-installment: SC PT PA OD
  SC scheduled, PT partially paid, PA paid, OD overdue
loan-transition: APPROVE CONTRACT ACTIVATE SUSPEND RESUME DELINQUENT DEFAULT
  MATURE SETTLE CLOSE CANCEL RESTRUCTURE
loan-txn-type: CREDDISB CREDREPY CREDWOFF (canonical credit types; loan is source entity)

## rc

00 ok, 20 validation, 22 duplicate, 23 not-found, 24 in-progress, 35 missing-dataset, 61 locked, 99 bad-request
