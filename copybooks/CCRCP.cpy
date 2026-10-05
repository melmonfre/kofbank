       01 BK-CCRD-CLR-PARMS.
          05 CP-OP             PIC X(17).
          05 CP-CLR-ID         PIC X(12).
          05 CP-CARD-ID        PIC X(12).
          05 CP-ACCOUNT        PIC X(12).
          05 CP-FACILITY       PIC X(12).
          05 CP-AUTH-ID        PIC X(12).
          05 CP-ORIG-CLR-ID    PIC X(12).
          05 CP-TXN-ID         PIC X(12).
          05 CP-EXT-REF        PIC X(32).
          05 CP-EXT-BATCH      PIC X(16).
          05 CP-SOURCE         PIC X(08).
          05 CP-MERCHANT-ID    PIC X(16).
          05 CP-MERCHANT-NAME  PIC X(40).
          05 CP-MCC            PIC X(04).
          05 CP-CHANNEL        PIC X(04).
          05 CP-TXN-TYPE       PIC X(08).
          05 CP-AMOUNT         PIC S9(15)V99 COMP-3.
          05 CP-CURRENCY       PIC X(03).
          05 CP-AUTH-AMOUNT    PIC S9(15)V99 COMP-3.
          05 CP-DIFF-AMOUNT    PIC S9(15)V99 COMP-3.
          05 CP-FEE-AMT        PIC S9(15)V99 COMP-3.
          05 CP-SETTLE-CURR    PIC X(03).
          05 CP-SETTLE-AMT     PIC S9(15)V99 COMP-3.
          05 CP-SETTLE-BATCH   PIC X(12).
          05 CP-STATUS         PIC X(12).
          05 CP-MATCH-STATUS   PIC X(12).
          05 CP-POST-STATUS    PIC X(12).
          05 CP-SETTLE-STATUS  PIC X(12).
          05 CP-RECON-STATUS   PIC X(12).
          05 CP-TXN-DATE       PIC 9(08).
          05 CP-CLEAR-DATE     PIC 9(08).
          05 CP-EXC-ID         PIC X(12).
          05 CP-FORCE          PIC X(01).
          05 CP-OPERATOR       PIC X(12).
          05 CP-CORR           PIC X(24).
          05 CP-REQUEST        PIC X(24).
          05 CP-REASON         PIC X(40).
          05 CP-REPLAY         PIC X(01).
          05 CP-COUNT          PIC 9(05).
          05 CP-RC             PIC X(02).
          05 CP-MSG            PIC X(80).
