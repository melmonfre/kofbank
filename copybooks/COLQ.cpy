       01 BK-COL-LIST.
          05 OL-OP            PIC X(08).
          05 OL-RC            PIC X(02).
          05 OL-MSG           PIC X(80).
          05 OL-COUNT         PIC 9(05).
          05 OL-ROW OCCURS 300 TIMES.
             10 OL-CASE       PIC X(12).
             10 OL-LOAN       PIC X(12).
             10 OL-STATUS     PIC X(04).
