      *> Split reversal store parameters and header list table.
      *> Headers are ordered deterministically by REV-ID (creation
      *> sequence), never by file position assumptions in callers.
       01 BK-PX-RV-LIST.
          05 RVL-CNT               PIC 9(02).
          05 RVL-ROW OCCURS 20 TIMES.
             10 RVL-REV-ID         PIC X(12).
             10 RVL-REQUEST        PIC X(24).
             10 RVL-GROSS          PIC S9(15)V99 COMP-3.
             10 RVL-LGCNT          PIC 9(02).
             10 RVL-STATUS         PIC X(12).
             10 RVL-TXN-ID         PIC X(12).
             10 RVL-JRN-ID         PIC X(20).
             10 RVL-BIZDATE        PIC 9(08).
       01 BK-PX-RV-STO-REQ.
          05 RVQ-OP               PIC X(14).
          05 RVQ-REV-ID           PIC X(12).
          05 RVQ-ORIG-PIX-ID      PIC X(12).
          05 RVQ-REQUEST          PIC X(24).
          05 RVQ-DEVOLVED         PIC S9(15)V99 COMP-3.
          05 RVQ-RC               PIC X(02).
          05 RVQ-MSG              PIC X(80).
