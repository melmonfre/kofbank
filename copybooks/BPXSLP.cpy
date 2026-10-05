       01 BK-PX-STL-PARMS.
          05 SL-OP             PIC X(20).
          05 SL-CYCLE-ID       PIC X(20).
          05 SL-BIZDATE        PIC 9(08).
          05 SL-SETTLE-DATE    PIC 9(08).
          05 SL-CYCLE-STATUS   PIC X(16).
          05 SL-STL-ID         PIC X(12).
          05 SL-BATCH          PIC X(12).
          05 SL-PARTICIPANT    PIC X(12).
          05 SL-CURRENCY       PIC X(03).
          05 SL-SIDE           PIC X(10).
          05 SL-DIRECTION      PIC X(08).
          05 SL-GROSS-AMT      PIC S9(15)V99 COMP-3.
          05 SL-GROSS-RCV      PIC S9(15)V99 COMP-3.
          05 SL-ADJ-AMT        PIC S9(15)V99 COMP-3.
          05 SL-FEE-AMT        PIC S9(15)V99 COMP-3.
          05 SL-NET-AMT        PIC S9(15)V99 COMP-3.
          05 SL-SETTLED-AMT    PIC S9(15)V99 COMP-3.
          05 SL-STL-STATUS     PIC X(16).
          05 SL-EXTERNAL-REF   PIC X(32).
          05 SL-RESULT-REF     PIC X(32).
          05 SL-POST-STATUS    PIC X(12).
          05 SL-RECON-STATUS   PIC X(12).
          05 SL-JRN-ID         PIC X(20).
          05 SL-PIX-ID         PIC X(12).
          05 SL-RUN-ID         PIC X(20).
          05 SL-FILE           PIC X(120).
          05 SL-SIM            PIC X(12).
          05 SL-REASON         PIC X(40).
          05 SL-OPERATOR       PIC X(12).
          05 SL-CORR           PIC X(24).
          05 SL-REQUEST        PIC X(24).
          05 SL-TXN-COUNT      PIC 9(07).
          05 SL-PAY-COUNT      PIC 9(07).
          05 SL-RCV-COUNT      PIC 9(07).
          05 SL-PARTY-COUNT    PIC 9(07).
          05 SL-ITEM-COUNT     PIC 9(07).
          05 SL-ATTEMPTS       PIC 9(04).
          05 SL-POS-PAYABLE    PIC S9(15)V99 COMP-3.
          05 SL-POS-RECEIVABLE PIC S9(15)V99 COMP-3.
          05 SL-POS-SPENT      PIC S9(15)V99 COMP-3.
          05 SL-POS-RECEIVED   PIC S9(15)V99 COMP-3.
          05 SL-POS-PENDING    PIC S9(15)V99 COMP-3.
          05 SL-POS-NET        PIC S9(15)V99 COMP-3.
          05 SL-REPLAY         PIC X(01).
          05 SL-RC             PIC X(02).
          05 SL-MSG            PIC X(80).
