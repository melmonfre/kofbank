# ADR 0005 status based file io

decision: use FILE STATUS and EVALUATE for keyed reads, not INVALID KEY clauses
reason: GnuCOBOL 3.1.2 executed both INVALID KEY and NOT INVALID KEY branches and doubled balances
evidence: make test before and after, balance 1000000 to 500000
consequences:
  - all keyed reads test status 00 or 23
  - duplicate detection still uses INVALID KEY on WRITE
status: accepted
