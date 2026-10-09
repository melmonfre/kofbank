# ADR 0009 effective-dated product catalog

decision: products are versioned records resolved by effective date, not a flat config
reason: historical transactions must stay interpretable under the rules in force at their time
consequences:
  - prod.idx is the runtime catalog, product.def is the seed
  - BPRODQ returns the latest version whose effective date is on or before the business date
  - BPRDVAL falls back to the seed when the catalog is absent, keeping bootstrap simple
  - rules carry limits, minimum opening balance, interest basis points and fees
status: accepted
