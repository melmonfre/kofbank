# integration-catalog

| system | direction | status | contract |
|---|---|---|---|
| cli | inbound | done | request-line stdin, fields stdout |
| kof | inbound | planned | calls core programs, no business logic |
| cics | inbound | planned | jcl/cics skeletons |
| mq | both | planned | event contracts in schemas/ |
| db2 | storage | planned | portable DDL in db2/ |
| jcl | batch | skeleton | jcl/ |
| events | outbound | done | var/journal/events.log |
| external-rails | outbound | done | etc/rails.cfg, cobol/payments/BPAYRAIL |
| external-reconciliation | inbound | done | line file ref\|amount\|currency\|date, cobol/reconciliation/BRECEXT |
| recon-mq | inbound | planned | MQ adapter to external reconciliation format |
| regulators | outbound | planned | reporting adapter |

## event-contracts

- CUSTOMER.CREATED.v1
- CUSTOMER.UPDATED.v1
- CUSTOMER.STATUS.v1
- ACCOUNT.CREATED.v1
- ACCOUNT.BLOCKED.v1
- ACCOUNT.CLOSED.v1
- TRANSACTION.POSTED.v1
- TRANSACTION.CANCELLED.v1
- TRANSACTION.REVERSED.v1
- TRANSACTION.RETURNED.v1
- PAYMENT.SETTLED.v1
- PAYMENT.RETURNED.v1
- PAYMENT.REVERSED.v1
- BATCH.EOD.v1

envelope: EVT|type|key|business-date|timestamp|payload
