       01 BK-CCRD-LIST.
          05 QL-OP            PIC X(08).
          05 QL-RC            PIC X(02).
          05 QL-MSG           PIC X(80).
          05 QL-CUST          PIC X(12).
          05 QL-FSTAT       PIC X(12).
          05 QL-FACILITY      PIC X(12).
          05 QL-ACCOUNT       PIC X(12).
          05 QL-COUNT         PIC 9(05).
          05 QL-ROW OCCURS 300 TIMES.
             10 QL-ID         PIC X(12).
             10 QL-STATUS     PIC X(12).
             10 QL-KIND       PIC X(08).
             10 QL-PRODUCT    PIC X(04).
             10 QL-MASKED     PIC X(16).
             10 QL-CURRENCY   PIC X(03).
             10 QL-DATE       PIC 9(08).
             10 QL-TEXT       PIC X(20).
