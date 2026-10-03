       01 BK-TXN-POST-REQ.
          05 TPO-TXN-ID        PIC X(12).
          05 TPO-TYPE          PIC X(08).
          05 TPO-STATUS        PIC X(02).
          05 TPO-SRC           PIC X(12).
          05 TPO-DST           PIC X(12).
          05 TPO-AMOUNT        PIC S9(15)V99 COMP-3.
          05 TPO-CURRENCY      PIC X(03).
          05 TPO-DESCR         PIC X(40).
          05 TPO-OPERATOR      PIC X(12).
          05 TPO-CORR          PIC X(24).
          05 TPO-REQUEST       PIC X(24).
          05 TPO-REASON        PIC X(40).
          05 TPO-ORIGIN        PIC X(12).
          05 TPO-BIZDATE       PIC 9(08).
          05 TPO-JRN-ID        PIC X(20).
          05 TPO-REF           PIC X(24).
          05 TPO-FACILITY      PIC X(12).
          05 TPO-PRINCIPAL     PIC S9(15)V99 COMP-3.
          05 TPO-INTEREST      PIC S9(15)V99 COMP-3.
          05 TPO-FEE-AMT       PIC S9(15)V99 COMP-3.
          05 TPO-DUE-DATE      PIC 9(08).
          05 TPO-INSTALLMENT   PIC 9(04).
          05 TPO-RC            PIC X(02).
          05 TPO-MSG           PIC X(80).
