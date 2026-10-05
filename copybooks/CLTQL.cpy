       01 BK-CLT-LIST.
          05 QL-OP            PIC X(08).
          05 QL-RC            PIC X(02).
          05 QL-MSG           PIC X(80).
          05 QL-FILTER         PIC X(12).
          05 QL-OBL-TYPE      PIC X(08).
          05 QL-OBL-ID        PIC X(12).
          05 QL-CUST          PIC X(12).
          05 QL-CASE          PIC X(12).
          05 QL-COUNT         PIC 9(05).
          05 QL-ROW OCCURS 300 TIMES.
             10 QL-ID         PIC X(12).
             10 QL-COLL       PIC X(12).
             10 QL-STATUS     PIC X(12).
             10 QL-AMOUNT     PIC S9(15)V99 COMP-3.
             10 QL-AMT2       PIC S9(15)V99 COMP-3.
             10 QL-CURRENCY   PIC X(03).
             10 QL-DATE       PIC 9(08).
             10 QL-TEXT       PIC X(20).
