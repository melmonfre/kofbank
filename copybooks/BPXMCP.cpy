       01 BK-MC-PARMS.
          05 MP-OP             PIC X(16).
          05 MP-REQ-CASE-ID    PIC X(12).
          05 MP-REQ-ID         PIC X(24).
          05 MP-ORIG-PIX-ID    PIC X(12).
          05 MP-E2E-ID         PIC X(32).
          05 MP-CLAIMANT       PIC X(12).
          05 MP-CLAIMANT-TYPE  PIC X(06).
          05 MP-REASON         PIC X(40).
          05 MP-CHANNEL        PIC X(08).
          05 MP-CLAIMED-AMT    PIC S9(15)V99 COMP-3.
          05 MP-CURRENCY       PIC X(03).
          05 MP-FRAUD-FLAG     PIC X(01).
          05 MP-FRAUD-SOURCE   PIC X(12).
          05 MP-FRAUD-REF      PIC X(32).
          05 MP-ORIG-AMOUNT    PIC S9(15)V99 COMP-3.
          05 MP-AVAILABLE      PIC S9(15)V99 COMP-3.
          05 MP-BLOCKED-AMT    PIC S9(15)V99 COMP-3.
          05 MP-ELIGIBLE-AMT   PIC S9(15)V99 COMP-3.
          05 MP-DECISION-AMT   PIC S9(15)V99 COMP-3.
          05 MP-RETURNED-AMT   PIC S9(15)V99 COMP-3.
          05 MP-REMAIN-AMT     PIC S9(15)V99 COMP-3.
          05 MP-DECISION       PIC X(14).
          05 MP-DEC-REASON     PIC X(40).
          05 MP-STATUS         PIC X(12).
          05 MP-CASE-STATUS    PIC X(12).
          05 MP-DEVOL-PIX-ID   PIC X(12).
          05 MP-DEVOL-TXN-ID   PIC X(12).
          05 MP-DEVOL-JRN-ID   PIC X(20).
          05 MP-STL-REF        PIC X(32).
          05 MP-HOLD-ID        PIC X(16).
          05 MP-RECON-STATUS   PIC X(12).
          05 MP-DATE           PIC 9(08).
          05 MP-DEADLINE       PIC 9(08).
          05 MP-COUNT          PIC 9(07).
          05 MP-SIM            PIC X(12).
          05 MP-REPLAY         PIC X(01).
          05 MP-OPERATOR       PIC X(12).
          05 MP-CORR           PIC X(24).
          05 MP-RC             PIC X(02).
          05 MP-MSG            PIC X(80).
