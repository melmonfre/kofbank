       01 BK-COL-LOANLIST.
          05 LL-OP            PIC X(08).
          05 LL-RC            PIC X(02).
          05 LL-MSG           PIC X(80).
          05 LL-COUNT         PIC 9(05).
          05 LL-ROW OCCURS 200 TIMES.
             10 LL-ID         PIC X(12).
             10 LL-STATUS     PIC X(04).
