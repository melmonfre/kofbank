# ADR 0002 local persistence

decision: GnuCOBOL indexed datasets as VSAM-like local storage
reason: matches KSDS and portable to z/OS
evidence: indexed file handler BDB, alternate keys, status codes
consequences:
  - one dataset per entity under var/data
  - dynamic ASSIGN from BANK_HOME
  - no DB2 dependency in local mode
status: accepted
