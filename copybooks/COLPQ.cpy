       01 BK-COL-PROMLIST.
          05 PL-OP            PIC X(08).
          05 PL-RC            PIC X(02).
          05 PL-MSG           PIC X(80).
          05 PL-CASE          PIC X(12).
          05 PL-COUNT         PIC 9(05).
          05 PL-ROW OCCURS 100 TIMES.
             10 PL-ID         PIC X(12).
             10 PL-STATUS     PIC X(12).
             10 PL-AMOUNT     PIC S9(15)V99 COMP-3.
             10 PL-PAID       PIC S9(15)V99 COMP-3.
             10 PL-DATE       PIC 9(08).
             10 PL-TXN        PIC X(12).
