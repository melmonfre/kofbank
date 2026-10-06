       01 BK-EOD-RPT.
          05 ER-BIZDATE     PIC 9(08).
          05 ER-N-CUST      PIC 9(09).
          05 ER-N-ACCT      PIC 9(09).
          05 ER-N-BAL       PIC 9(09).
          05 ER-TOT-LEDGER  PIC S9(15)V99 COMP-3.
          05 ER-PAY-EOD.
            10 ER-PE-TOTAL     PIC 9(09).
            10 ER-PE-SETTLED   PIC 9(09).
            10 ER-PE-PENDING   PIC 9(09).
            10 ER-PE-FAILED    PIC 9(09).
            10 ER-PE-RETURNED  PIC 9(09).
            10 ER-PE-REVERSED  PIC 9(09).
            10 ER-PE-BROKEN    PIC 9(09).
            10 ER-PE-SETTLED-AMT PIC S9(15)V99 COMP-3.
          05 ER-REC-LED-ID  PIC X(20).
          05 ER-REC-PAY-ID  PIC X(20).
          05 ER-REC-TXN-ID  PIC X(20).
          05 ER-REC-CRD-ID  PIC X(20).
          05 ER-CRD-EOD     PIC X(80).
          05 ER-REC-LN-ID   PIC X(20).
          05 ER-LN-EOD      PIC X(80).
          05 ER-REC-COL-ID  PIC X(20).
          05 ER-COL-EOD     PIC X(80).
          05 ER-REC-CLT-ID  PIC X(20).
          05 ER-CLT-EOD     PIC X(80).
          05 ER-REC-CCR-ID  PIC X(20).
          05 ER-CRC-EOD     PIC X(80).
          05 ER-REC-PIX-ID  PIC X(20).
          05 ER-PX-EOD      PIC X(80).
          05 ER-MED-BATCH   PIC X(80).
          05 ER-TB-MSG      PIC X(80).
          05 ER-RC          PIC X(02).
