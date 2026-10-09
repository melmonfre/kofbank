# security-catalog

## principles

- least privilege
- segregation of duties
- maker-checker for sensitive operations
- every change audited
- no secrets in code or datasets

## implemented

| control | status | location |
|---|---|---|
| audit-trail | done | var/audit/audit.log |
| correlation-id | done | every request field |
| idempotency | done | BIDM |
| document-uniqueness | done | custdoc.idx |

## planned

| control | status |
|---|---|
| authentication | planned |
| authorization-rbac | planned |
| encryption-at-rest | planned |
| masking | planned |
| key-management | planned |
| pin-handling | planned |

## pii

- customer name, document, address are pii
- never logged in clear outside audit datasets
- masking required for non-production reads
