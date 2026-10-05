       05 RV-ID             PIC X(12).
       05 RV-CASE-ID        PIC X(12).
       05 RV-LOAN-ID        PIC X(12).
       05 RV-TXN-ID         PIC X(12).
       05 RV-STATUS         PIC X(12).
       05 RV-CURRENCY       PIC X(03).
       05 RV-AMOUNT         PIC S9(15)V99 COMP-3.
       05 RV-PRINCIPAL      PIC S9(15)V99 COMP-3.
       05 RV-INTEREST       PIC S9(15)V99 COMP-3.
       05 RV-FEES           PIC S9(15)V99 COMP-3.
       05 RV-DATE           PIC 9(08).
       05 RV-APPLIED       PIC S9(15)V99 COMP-3.
       05 RV-EXCESS         PIC S9(15)V99 COMP-3.
       05 RV-REASON         PIC X(80).
       05 RV-OPERATOR       PIC X(12).
       05 RV-CREATED        PIC 9(08).
       05 RV-UPDATED        PIC 9(08).
       05 RV-VERSION        PIC 9(05).
       05 RV-PLAN-N         PIC 9(04).
       05 RV-PLAN OCCURS 40 TIMES.
          10 RV-P-INST      PIC 9(04).
          10 RV-P-FEE       PIC S9(15)V99 COMP-3.
          10 RV-P-INT       PIC S9(15)V99 COMP-3.
          10 RV-P-PRIN      PIC S9(15)V99 COMP-3.
