       05 CA-ID             PIC X(12).
       05 CA-CARD-ID        PIC X(12).
       05 CA-CUST-ID        PIC X(12).
       05 CA-KIND           PIC X(08).
       05 CA-AMOUNT         PIC S9(15)V99 COMP-3.
       05 CA-CURRENCY       PIC X(03).
       05 CA-CAPTURED       PIC S9(15)V99 COMP-3.
       05 CA-MERCHANT       PIC X(12).
       05 CA-MCC            PIC X(04).
       05 CA-CHANNEL        PIC X(08).
       05 CA-STATUS         PIC X(12).
       05 CA-REASON         PIC X(40).
       05 CA-DATE           PIC 9(08).
       05 CA-EXPIRY         PIC 9(08).
       05 CA-CLEAR-ID       PIC X(12).
       05 CA-TXN-ID         PIC X(12).
       05 CA-EXT-REF        PIC X(24).
       05 CA-OPERATOR       PIC X(12).
       05 CA-CORR           PIC X(24).
       05 CA-CREATED        PIC 9(08).
       05 CA-UPDATED        PIC 9(08).
       05 CA-VERSION        PIC 9(05).
       05 CA-HASH           PIC X(16).
