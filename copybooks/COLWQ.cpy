       01 BK-COL-RECLIST.
          05 RL-OP            PIC X(08).
          05 RL-RC            PIC X(02).
          05 RL-MSG           PIC X(80).
          05 RL-CASE          PIC X(12).
          05 RL-COUNT         PIC 9(05).
          05 RL-ROW OCCURS 100 TIMES.
             10 RL-ID         PIC X(12).
             10 RL-TXN        PIC X(12).
             10 RL-STATUS     PIC X(12).
             10 RL-AMOUNT     PIC S9(15)V99 COMP-3.
             10 RL-DATE       PIC 9(08).
