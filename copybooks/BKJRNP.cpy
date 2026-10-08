       01 BK-JRN-PARMS.
          05 BK-JRN-ID         PIC X(20).
          05 BK-JRN-TXN-ID     PIC X(24).
          05 BK-JRN-TYPE       PIC X(08).
          05 BK-JRN-BIZDATE    PIC 9(08).
          05 BK-JRN-CHANNEL    PIC X(08).
          05 BK-JRN-OPERATOR   PIC X(12).
          05 BK-JRN-CORR       PIC X(24).
          05 BK-JRN-REQUEST    PIC X(24).
          05 BK-JRN-COUNT      PIC 9(04).
          05 BK-JRN-HASH       PIC X(16).
          05 BK-JRN-RC         PIC X(02).
          05 BK-JRN-MSG        PIC X(80).
          05 BK-JRN-MODE       PIC X(01).
          05 BK-JRN-F-FOUND    PIC 9(04).
          05 BK-JRN-F-DECLARED PIC 9(04).
          05 BK-JRN-F-NCOL     PIC 9(04).
          05 BK-JRN-F-BIZDATE  PIC 9(08).
          05 BK-JRN-F-DR       PIC S9(15)V99 COMP-3.
          05 BK-JRN-F-CR       PIC S9(15)V99 COMP-3.
          05 BK-JRN-F-HASH     PIC X(16).
          05 BK-JRN-L OCCURS 50 TIMES.
             10 BK-JRN-L-SEQ       PIC 9(02).
             10 BK-JRN-L-GL        PIC X(10).
             10 BK-JRN-L-DC        PIC X(01).
             10 BK-JRN-L-AMT       PIC S9(15)V99 COMP-3.
             10 BK-JRN-L-CUR       PIC X(03).
             10 BK-JRN-L-ENTITY    PIC X(20).
             10 BK-JRN-L-DESCR     PIC X(40).
