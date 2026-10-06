       05 MC-CASE-ID        PIC X(12).
       05 MC-ORIG-PIX-ID    PIC X(12).
       05 MC-E2E-ID         PIC X(32).
       05 MC-ORIG-TXN-ID    PIC X(12).
       05 MC-ORIG-JRN-ID    PIC X(20).
       05 MC-ORIG-DIR       PIC X(08).
       05 MC-PAYER-ACCT     PIC X(12).
       05 MC-PAYER-CUST     PIC X(12).
       05 MC-PAYER-PART     PIC X(12).
       05 MC-PAYEE-ACCT     PIC X(12).
       05 MC-PAYEE-CUST     PIC X(12).
       05 MC-PAYEE-PART     PIC X(12).
       05 MC-CLAIMANT       PIC X(12).
       05 MC-CLAIMANT-TYPE  PIC X(06).
       05 MC-ORIG-AMOUNT    PIC S9(15)V99 COMP-3.
       05 MC-CLAIMED-AMT    PIC S9(15)V99 COMP-3.
       05 MC-CURRENCY       PIC X(03).
       05 MC-AVAILABLE      PIC S9(15)V99 COMP-3.
       05 MC-BLOCKED-AMT    PIC S9(15)V99 COMP-3.
       05 MC-ELIGIBLE-AMT   PIC S9(15)V99 COMP-3.
       05 MC-DECISION-AMT   PIC S9(15)V99 COMP-3.
       05 MC-RETURNED-AMT   PIC S9(15)V99 COMP-3.
       05 MC-REMAIN-AMT     PIC S9(15)V99 COMP-3.
       05 MC-REASON         PIC X(40).
       05 MC-FRAUD-FLAG     PIC X(01).
       05 MC-FRAUD-SOURCE   PIC X(12).
       05 MC-FRAUD-REF      PIC X(32).
       05 MC-STATUS         PIC X(12).
       05 MC-DECISION       PIC X(14).
       05 MC-DEC-REASON     PIC X(40).
       05 MC-DEC-BY         PIC X(12).
       05 MC-DEVOL-PIX-ID   PIC X(12).
       05 MC-DEVOL-TXN-ID   PIC X(12).
       05 MC-DEVOL-JRN-ID   PIC X(20).
       05 MC-STL-REF        PIC X(32).
       05 MC-HOLD-ID        PIC X(16).
       05 MC-RECON-STATUS   PIC X(12).
       05 MC-CHANNEL        PIC X(08).
       05 MC-MODALITY       PIC X(12).
       05 MC-BIZDATE        PIC 9(08).
       05 MC-DEADLINE       PIC 9(08).
       05 MC-DEC-DATE       PIC 9(08).
       05 MC-DEVOL-DATE     PIC 9(08).
       05 MC-CREATED        PIC 9(14).
       05 MC-UPDATED        PIC 9(14).
       05 MC-VERSION        PIC 9(05).
       05 MC-OPERATOR       PIC X(12).
       05 MC-CORR           PIC X(24).
       05 MC-REQUEST        PIC X(24).
       05 MC-IDEM-KEY       PIC X(64).
       05 MC-HASH           PIC X(16).
