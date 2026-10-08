      *> Split payment allocation record (one durable leg of one Pix
      *> gross payment).  The record is the auditable decomposition of a
      *> split Pix: payment id, ordered sequence, destination, amount,
      *> type, reference, tax metadata, status and posting identity.
      *> Position alone never identifies a leg: AL-ALLOC-ID is durable.
       05 AL-ALLOC-ID        PIC X(12).
       05 AL-PIX-ID          PIC X(12).
       05 AL-SEQ             PIC 9(02).
       05 AL-DEST-ROLE       PIC X(12).
       05 AL-DEST-ACCT       PIC X(12).
       05 AL-DEST-PART       PIC X(12).
       05 AL-DEST-CUST       PIC X(12).
       05 AL-DEST-DOC-TYPE   PIC X(04).
       05 AL-DEST-DOC        PIC X(20).
       05 AL-DEST-NAME       PIC X(60).
       05 AL-AMOUNT          PIC S9(15)V99 COMP-3.
       05 AL-CURRENCY        PIC X(03).
       05 AL-TYPE            PIC X(10).
       05 AL-REF             PIC X(32).
       05 AL-DOC-REF         PIC X(50).
       05 AL-TAX-TYPE        PIC X(10).
       05 AL-TAX-CAT         PIC X(08).
       05 AL-STATUS          PIC X(12).
       05 AL-ORIG-ALLOC-ID   PIC X(12).
       05 AL-REV-ID          PIC X(12).
       05 AL-TXN-ID          PIC X(12).
       05 AL-JRN-ID          PIC X(20).
       05 AL-BIZDATE         PIC 9(08).
       05 AL-CREATED         PIC 9(14).
       05 AL-UPDATED         PIC 9(14).
       05 AL-VERSION         PIC 9(05).
       05 AL-HASH            PIC X(16).
       05 AL-OPERATOR        PIC X(12).
       05 AL-CORR            PIC X(24).
       05 AL-REQUEST         PIC X(24).
