       01 BK-COL-ACTLIST.
          05 AL-OP            PIC X(08).
          05 AL-RC            PIC X(02).
          05 AL-MSG           PIC X(80).
          05 AL-CASE          PIC X(12).
          05 AL-COUNT         PIC 9(05).
          05 AL-ROW OCCURS 300 TIMES.
             10 AL-ID         PIC X(12).
             10 AL-TYPE       PIC X(16).
             10 AL-STAT       PIC X(12).
