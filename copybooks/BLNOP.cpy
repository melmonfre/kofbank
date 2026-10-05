       01 BK-LN-PARMS.
          05 CL-OP            PIC X(12).
          05 CL-LOAN-ID       PIC X(12).
          05 CL-FAC-ID        PIC X(12).
          05 CL-CUST-ID       PIC X(12).
          05 CL-PRODUCT       PIC X(04).
          05 CL-ACCOUNT       PIC X(12).
          05 CL-PRINCIPAL     PIC S9(15)V99 COMP-3.
          05 CL-TERM          PIC 9(04).
          05 CL-AMORT         PIC X(12).
          05 CL-FREQ          PIC 9(02).
          05 CL-FIRST-DUE     PIC 9(08).
          05 CL-EFF           PIC 9(08).
          05 CL-AMOUNT        PIC S9(15)V99 COMP-3.
          05 CL-FEE           PIC S9(15)V99 COMP-3.
          05 CL-INTEREST      PIC S9(15)V99 COMP-3.
          05 CL-FEES          PIC S9(15)V99 COMP-3.
          05 CL-DATE          PIC 9(08).
          05 CL-TXN-ID        PIC X(12).
          05 CL-EXCESS        PIC S9(15)V99 COMP-3.
          05 CL-REASON        PIC X(80).
          05 CL-OPERATOR      PIC X(12).
          05 CL-CORR          PIC X(24).
          05 CL-REQUEST       PIC X(24).
          05 CL-STATUS        PIC X(04).
          05 CL-PLAN-N        PIC 9(04).
          05 CL-PLAN OCCURS 40 TIMES.
             10 CL-P-INST     PIC 9(04).
             10 CL-P-FEE      PIC S9(15)V99 COMP-3.
             10 CL-P-INT      PIC S9(15)V99 COMP-3.
             10 CL-P-PRIN     PIC S9(15)V99 COMP-3.
          05 CL-RC            PIC X(02).
          05 CL-MSG           PIC X(80).
