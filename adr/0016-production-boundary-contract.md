# ADR 0016 the production boundary is a contract, not a second core

decision: external connectivity (SPI/DICT-like rails, certificates, signing,
outbound intents, inbound message processing and external reconciliation) is
implemented as an explicit boundary layer whose durable state describes
EXTERNAL attempts and identities only; all financial truth stays inside the
already verified core (journal, balances, transaction lifecycle)
reason: a mainframe replacement must be able to swap protocol adapters,
transports and security material without touching accounting rules; if the
boundary owned ledgers or invented regulatory values, the replacement would
fork the financial truth instead of isolating it
consequences:
  - BXTP is the single transport contract (SEND/QUERY over channel+adapter);
    the local deterministic double is the only implementation, and a real
    network/MQ adapter must implement the same copybook contract (BKBNDP)
  - BXOUTB is a durable outbound intent store (PENDING/SENT/ACKED/REJECTED/
    UNKNOWN) that reuses the same external identity on every retry and never
    posts to the GL; unknown outcomes require query or operator correlation,
    never blind retry
  - BXMSGID keeps external message identity (MsgId/EndToEndId/version/family)
    distinct from internal transaction identity and makes inbound replay and
    payload-mismatch detection durable
  - BXPIPE orders the inbound stages schema -> security -> identity ->
    normalization -> core -> outcome persistence; it maps messages onto the
    existing BPXSTX contract instead of duplicating it
  - BSEC manages certificate lifecycle states and a HASH-DOUBLE signing
    seam only; no private keys, credentials or real certificate material
    exist in COBOL or fixtures, and production must replace the double with
    an HSM/PKCS#11 adapter behind the same BKCFTP contract
  - BRECBND reconciles intent, external response, message identity and the
    journal and raises durable exceptions; it never repairs silently
  - environment, transport, security and clock are explicit configuration
    (etc/pix.cfg); the active value is LOCAL_DOUBLE, so nothing may claim
    real Banco Central connectivity or regulatory compliance from this gate
status: accepted
