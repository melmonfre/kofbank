       01 BK-PST-TABLE.
          05 BK-PST OCCURS 50 TIMES.
             10 BK-PST-GL        PIC X(10).
             10 BK-PST-DC        PIC X(01).
             10 BK-PST-AMOUNT    PIC S9(15)V99 COMP-3.
             10 BK-PST-CURRENCY  PIC X(03).
             10 BK-PST-ENTITY    PIC X(20).
             10 BK-PST-DESCR     PIC X(40).
             10 BK-PST-VALUEDATE PIC 9(08).
