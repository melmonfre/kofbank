       05 TXN-ID            PIC X(12).
       05 TXN-TYPE          PIC X(08).
       05 TXN-STATUS        PIC X(02).
       05 TXN-SRC           PIC X(12).
       05 TXN-DST           PIC X(12).
       05 TXN-AMOUNT        PIC S9(15)V99 COMP-3.
       05 TXN-CURRENCY      PIC X(03).
       05 TXN-DESCR         PIC X(40).
       05 TXN-OPERATOR      PIC X(12).
       05 TXN-CORR          PIC X(24).
       05 TXN-REQUEST       PIC X(24).
       05 TXN-ORIGIN        PIC X(12).
       05 TXN-REASON        PIC X(40).
       05 TXN-REF           PIC X(24).
       05 TXN-FACILITY      PIC X(12).
       05 TXN-PRINCIPAL     PIC S9(15)V99 COMP-3.
       05 TXN-INTEREST      PIC S9(15)V99 COMP-3.
       05 TXN-FEE-AMT       PIC S9(15)V99 COMP-3.
       05 TXN-DUE-DATE      PIC 9(08).
       05 TXN-INSTALLMENT   PIC 9(04).
      *> Split legs (type SPLITPIX): persisted with the transaction so
      *> posting is restartable and the journal is reproducible.
       05 TXN-SPLIT-CNT     PIC 9(02).
       05 TXN-S-ROW OCCURS 20 TIMES.
          10 TXN-PS-SEQ     PIC 9(02).
          10 TXN-PS-ROLE    PIC X(12).
          10 TXN-PS-DEST    PIC X(12).
          10 TXN-PS-AMT     PIC S9(15)V99 COMP-3.
          10 TXN-PS-TYPE    PIC X(10).
       05 TXN-JRN-ID        PIC X(20).
       05 TXN-CREATED       PIC 9(08).
       05 TXN-POSTED        PIC 9(08).
       05 TXN-SETTLED       PIC 9(08).
       05 TXN-VERSION       PIC 9(05).
       05 TXN-HASH          PIC X(16).
