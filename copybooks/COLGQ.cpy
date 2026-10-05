       01 BK-COL-ARRLIST.
          05 GL-OP            PIC X(08).
          05 GL-RC            PIC X(02).
          05 GL-MSG           PIC X(80).
          05 GL-CASE          PIC X(12).
          05 GL-COUNT         PIC 9(05).
          05 GL-ROW OCCURS 100 TIMES.
             10 GL-ID         PIC X(12).
             10 GL-STATUS     PIC X(12).
             10 GL-TOTAL      PIC S9(15)V99 COMP-3.
             10 GL-PAID       PIC S9(15)V99 COMP-3.
             10 GL-INSTS      PIC 9(04).
             10 GL-INPAID     PIC 9(04).
