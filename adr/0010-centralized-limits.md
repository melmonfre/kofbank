# ADR 0010 centralized limits

decision: limits are evaluated by one primitive for every scope
reason: consistent enforcement across transactions, payments, cards and credit
consequences:
  - limits.cfg defines rules by scope, key and period, with * wildcard keys
  - limuse.idx persists consumed usage per scope, key and period
  - the tightest matching rule wins
  - payments consume on settlement and release on return or reversal
  - missing rule means no limit, never a silent block
status: accepted
