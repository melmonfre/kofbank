      *> Split allocation request table and store parameters.
      *> The table is a fixed OCCURS structure (mainframe-native,
      *> deterministic ordering by AL-SEQ); it is never JSON.
       01 BK-PX-ALLOC-TBL.
          05 PXA-CNT              PIC 9(02).
          05 PXA-ROW OCCURS 20 TIMES.
             10 PXA-SEQ           PIC 9(02).
             10 PXA-ALLOC-ID      PIC X(12).
             10 PXA-DEST-ROLE     PIC X(12).
             10 PXA-DEST-ID       PIC X(12).
             10 PXA-DEST-DOC-TYPE PIC X(04).
             10 PXA-DEST-DOC      PIC X(20).
             10 PXA-DEST-NAME     PIC X(60).
             10 PXA-DEST-CUST     PIC X(12).
             10 PXA-AMOUNT        PIC S9(15)V99 COMP-3.
             10 PXA-TYPE          PIC X(10).
             10 PXA-REF           PIC X(32).
             10 PXA-DOC-REF       PIC X(50).
             10 PXA-TAX-TYPE      PIC X(10).
             10 PXA-TAX-CAT       PIC X(08).
             10 PXA-STATUS        PIC X(12).
             10 PXA-ORIG-ALLOC-ID PIC X(12).
             10 PXA-TXN-ID        PIC X(12).
             10 PXA-JRN-ID        PIC X(20).

       01 BK-PX-ALLOC-STO-REQ.
          05 WA-OP             PIC X(14).
          05 WA-PIX-ID         PIC X(12).
          05 WA-ALLOC-ID       PIC X(12).
          05 WA-SEQ            PIC 9(02).
          05 WA-RC             PIC X(02).
          05 WA-MSG            PIC X(80).
