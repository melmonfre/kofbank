      *> Deterministic UTC clock parameters.
      *> Single temporal primitive shared by the domains that need an
      *> exact instant.  It carries ONLY wall-clock mechanics; every
      *> business rule (QR TTL, MED deadline, claim resolution period,
      *> loan due date, batch business date) stays in its own module and
      *> only ever consumes these primitives.  They must not share
      *> business semantics.
      *>
      *> Instants are PIC 9(14) UTC, YYYYMMDDHHMMSS, the same
      *> representation the persistent records already use (QR-CREATED,
      *> QR-UPDATED).  Granularity is one second, which is the smallest
      *> unit that keeps the "one second before / exactly at / one second
      *> after" boundaries explicit.
       01 BK-CLK-PARMS.
          05 CLK-OP            PIC X(12).
          05 CLK-BASE          PIC 9(14).
          05 CLK-BASE2         PIC 9(14).
          05 CLK-SECONDS       PIC S9(15).
          05 CLK-OUT           PIC 9(14).
          05 CLK-DIFF          PIC S9(15).
          05 CLK-SRC           PIC X(04).
          05 CLK-RC            PIC X(02).
          05 CLK-MSG           PIC X(60).
