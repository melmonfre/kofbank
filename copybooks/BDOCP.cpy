      *> Document canonicalization and validation boundary.
      *> Prepares the core for alphanumeric CNPJ without guessing official
      *> check-digit algorithms.
       01 BK-DOC-PARMS.
          05 BD-OP            PIC X(12).
          05 BD-TYPE          PIC X(08).
          05 BD-IN            PIC X(60).
          05 BD-CANON         PIC X(60).
          05 BD-STATE         PIC X(12).
          05 BD-CLASS         PIC X(12).
          05 BD-RC            PIC X(02).
          05 BD-MSG           PIC X(80).
