# ADR 0003 journal first

decision: persist the journal before mutating balances
reason: indexed writes are not multi-record atomic
consequences:
  - journal.log and postings.log are the source of truth
  - balances are derivable and explainable
  - recovery can replay the journal
status: accepted
