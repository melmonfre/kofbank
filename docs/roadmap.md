# roadmap

order derived from actual dependencies in the repository, not from a wish list.
each domain ships executable behavior, tests, documentation and state before the next.

## done

foundation, customer, account, ledger, txn, batch-eod, payments,
product-catalog, interest-fees, limits, reconciliation, txn-lifecycle,
credit, loans

## next

1. collections          aging, delinquency, recovery on top of credit and loans
2. accounting-close     periods, accruals, financial close
3. statements           account, transaction, payment, loan statements
4. treasury             cash and liquidity positions
5. fx                   rates, trades, positions
6. cards                authorization separate from posting
7. merchant-acquiring   capture and settlement
8. corporate-banking    hierarchy, signatories, bulk payments
9. risk                 positions and limits on authoritative state
10. fraud               deterministic rules and decisions
11. aml                 monitoring, alerts, cases
12. investments         instruments, orders, positions
13. international       correspondents, cross-border
14. trade-finance       letters of credit, guarantees
15. advanced-batch      intraday, EOM, EOY, accrual, statements, archive
16. hardening           operational controls, security, recovery

## after the core

kof integration boundary
