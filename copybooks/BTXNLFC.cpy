       01 BK-TXN-LFC-REQ.
          05 LFC-OP            PIC X(12).
          05 LFC-TXN-ID        PIC X(12).
          05 LFC-TYPE          PIC X(08).
          05 LFC-SRC           PIC X(12).
          05 LFC-DST           PIC X(12).
          05 LFC-AMOUNT        PIC S9(15)V99 COMP-3.
          05 LFC-CURRENCY      PIC X(03).
          05 LFC-DESCR         PIC X(40).
          05 LFC-OPERATOR      PIC X(12).
          05 LFC-CORR          PIC X(24).
          05 LFC-REQUEST       PIC X(24).
          05 LFC-ORIGIN        PIC X(12).
          05 LFC-REASON        PIC X(40).
          05 LFC-REF           PIC X(24).
          05 LFC-FACILITY      PIC X(12).
          05 LFC-PRINCIPAL     PIC S9(15)V99 COMP-3.
          05 LFC-INTEREST      PIC S9(15)V99 COMP-3.
          05 LFC-FEE-AMT       PIC S9(15)V99 COMP-3.
          05 LFC-DUE-DATE      PIC 9(08).
          05 LFC-INSTALLMENT   PIC 9(04).
