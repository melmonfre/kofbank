      *> Split allocation service parameters.  The row table is the
      *> payment decomposition: input for validate/create, output for
      *> list/get.  Rows carry durable identities, never positional
      *> meaning.
       01 BK-PX-SPL-PARMS.
          05 SP-OP             PIC X(16).
          05 SP-PIX-ID         PIC X(12).
          05 SP-GROSS          PIC S9(15)V99 COMP-3.
          05 SP-CURRENCY       PIC X(03).
          05 SP-CNT            PIC 9(02).
          05 SP-SEQ            PIC 9(02).
          05 SP-ROW OCCURS 20 TIMES.
             10 SP-PS-SEQ      PIC 9(02).
             10 SP-PS-ROLE     PIC X(12).
             10 SP-PS-ID       PIC X(12).
             10 SP-PS-CUST     PIC X(12).
             10 SP-PS-DOC-TYPE PIC X(04).
             10 SP-PS-DOC      PIC X(20).
             10 SP-PS-NAME     PIC X(60).
             10 SP-PS-AMT      PIC S9(15)V99 COMP-3.
             10 SP-PS-TYPE     PIC X(10).
             10 SP-PS-REF      PIC X(32).
             10 SP-PS-DOCREF   PIC X(50).
             10 SP-PS-TAXTYPE  PIC X(10).
             10 SP-PS-TAXCAT   PIC X(08).
             10 SP-PS-ALLOC-ID PIC X(12).
             10 SP-PS-STATUS   PIC X(12).
             10 SP-PS-ORIG     PIC X(12).
             10 SP-PS-TXN-ID   PIC X(12).
             10 SP-PS-JRN-ID   PIC X(20).
             10 SP-PS-REMAIN   PIC S9(15)V99 COMP-3.
          05 SP-ALLOC-TOTAL    PIC S9(15)V99 COMP-3.
          05 SP-TAX-TOTAL      PIC S9(15)V99 COMP-3.
          05 SP-EXT-TOTAL      PIC S9(15)V99 COMP-3.
          05 SP-TXN-ID         PIC X(12).
          05 SP-JRN-ID         PIC X(20).
          05 SP-STATUS         PIC X(12).
          05 SP-BIZDATE        PIC 9(08).
          05 SP-OPERATOR       PIC X(12).
          05 SP-CORR           PIC X(24).
          05 SP-REQUEST        PIC X(24).
          05 SP-REV-ID         PIC X(12).
          05 SP-REQ-ID         PIC X(24).
          05 SP-ORIG-TXN-ID    PIC X(12).
          05 SP-ORIG-JRN-ID    PIC X(20).
          05 SP-REVERSED-TOTAL PIC S9(15)V99 COMP-3.
          05 SP-REMAIN         PIC S9(15)V99 COMP-3.
          05 SP-FULL           PIC X(01).
          05 SP-DEVOLVED       PIC S9(15)V99 COMP-3.
          05 SP-DEVID          PIC X(12).
          05 SP-R-CNT          PIC 9(02).
          05 SP-R-ROW OCCURS 20 TIMES.
             10 SP-RS-SEQ      PIC 9(02).
             10 SP-RS-ORIG     PIC X(12).
             10 SP-RS-ROLE     PIC X(12).
             10 SP-RS-ACCT     PIC X(12).
             10 SP-RS-AMT      PIC S9(15)V99 COMP-3.
             10 SP-RS-TYPE     PIC X(10).
             10 SP-RS-ALLOC-ID PIC X(12).
             10 SP-RS-STATUS   PIC X(12).
             10 SP-RS-TXN-ID   PIC X(12).
             10 SP-RS-JRN-ID   PIC X(20).
          05 SP-REPLAY         PIC X(01).
          05 SP-RC             PIC X(02).
          05 SP-MSG            PIC X(80).
