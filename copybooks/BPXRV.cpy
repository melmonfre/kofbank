      *> Split reversal header.  One durable record per split Pix
      *> devolution request.  The header never carries money itself:
      *> it references the reversal legs (by original allocation id),
      *> the reversal transaction/journal produced on success, and the
      *> request identity used for idempotency.  Statuses: RESERVED
      *> (legs consumed, no financial effect yet), POSTED (balanced
      *> reversal journal durable), FAILED (explicitly abandoned).
      *> A RESERVED header whose posting outcome is unknown stays
      *> RESERVED until reconciliation resolves it; it is never
      *> blindly re-posted.
       05 RV-REV-ID          PIC X(12).
       05 RV-ORIG-PIX-ID     PIC X(12).
       05 RV-ORIG-TXN-ID     PIC X(12).
       05 RV-ORIG-JRN-ID     PIC X(20).
       05 RV-ORIG-GROSS      PIC S9(15)V99 COMP-3.
       05 RV-REQUEST         PIC X(24).
       05 RV-CURRENCY        PIC X(03).
       05 RV-GROSS           PIC S9(15)V99 COMP-3.
       05 RV-CNT             PIC 9(02).
       05 RV-STATUS          PIC X(12).
       05 RV-TXN-ID          PIC X(12).
       05 RV-JRN-ID          PIC X(20).
       05 RV-BIZDATE         PIC 9(08).
       05 RV-CREATED         PIC 9(14).
       05 RV-UPDATED         PIC 9(14).
       05 RV-VERSION         PIC 9(05).
       05 RV-HASH            PIC X(16).
       05 RV-OPERATOR        PIC X(12).
       05 RV-CORR            PIC X(24).
       05 RV-REASON          PIC X(40).
       05 RV-S-ROW OCCURS 20 TIMES.
          10 RV-PS-SEQ         PIC 9(02).
          10 RV-PS-ORIG        PIC X(12).
          10 RV-PS-ROLE        PIC X(12).
          10 RV-PS-ACCT        PIC X(12).
          10 RV-PS-PART        PIC X(12).
          10 RV-PS-CUST        PIC X(12).
          10 RV-PS-AMT         PIC S9(15)V99 COMP-3.
          10 RV-PS-TYPE        PIC X(10).
          10 RV-PS-REF         PIC X(32).
          10 RV-PS-DOCREF      PIC X(50).
          10 RV-PS-TAXTYPE     PIC X(10).
          10 RV-PS-TAXCAT      PIC X(08).
          10 RV-PS-ALLOC-ID    PIC X(12).
          10 RV-PS-STATUS      PIC X(12).
          10 RV-PS-TXN-ID      PIC X(12).
          10 RV-PS-JRN-ID      PIC X(20).
