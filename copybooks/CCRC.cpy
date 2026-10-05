       05 CC-ID             PIC X(12).
       05 CC-CARD-ID        PIC X(12).
       05 CC-ACCOUNT        PIC X(12).
       05 CC-FACILITY       PIC X(12).
       05 CC-AUTH-ID        PIC X(12).
       05 CC-ORIG-CLR-ID    PIC X(12).
       05 CC-TXN-ID         PIC X(12).
       05 CC-EXT-REF        PIC X(32).
       05 CC-EXT-BATCH      PIC X(16).
       05 CC-SOURCE         PIC X(08).
       05 CC-MERCHANT-ID    PIC X(16).
       05 CC-MERCHANT-NAME  PIC X(40).
       05 CC-MCC            PIC X(04).
       05 CC-CHANNEL        PIC X(04).
       05 CC-TXN-TYPE       PIC X(08).
       05 CC-AMOUNT         PIC S9(15)V99 COMP-3.
       05 CC-CURRENCY       PIC X(03).
       05 CC-AUTH-AMOUNT    PIC S9(15)V99 COMP-3.
       05 CC-DIFF-AMOUNT    PIC S9(15)V99 COMP-3.
       05 CC-FEE-AMT        PIC S9(15)V99 COMP-3.
       05 CC-SETTLE-CURR    PIC X(03).
       05 CC-SETTLE-AMT     PIC S9(15)V99 COMP-3.
       05 CC-SETTLE-BATCH   PIC X(12).
       05 CC-STATUS         PIC X(12).
       05 CC-MATCH-STATUS   PIC X(12).
       05 CC-POST-STATUS    PIC X(12).
       05 CC-SETTLE-STATUS  PIC X(12).
       05 CC-RECON-STATUS   PIC X(12).
       05 CC-TXN-DATE       PIC 9(08).
       05 CC-CLEAR-DATE     PIC 9(08).
       05 CC-PROC-DATE      PIC 9(08).
       05 CC-BIZDATE        PIC 9(08).
       05 CC-OPERATOR       PIC X(12).
       05 CC-CORR           PIC X(24).
       05 CC-REQUEST        PIC X(24).
       05 CC-REASON         PIC X(40).
       05 CC-CREATED        PIC 9(14).
       05 CC-UPDATED        PIC 9(14).
       05 CC-VERSION        PIC 9(05).
       05 CC-HASH           PIC X(16).
