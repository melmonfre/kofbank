       05 PO-KEY.
          10 PO-PARTICIPANT  PIC X(12).
          10 PO-SEP          PIC X(01).
          10 PO-CURRENCY     PIC X(03).
       05 PO-PAYABLE         PIC S9(15)V99 COMP-3.
       05 PO-RECEIVABLE      PIC S9(15)V99 COMP-3.
       05 PO-SETTLED-PAY     PIC S9(15)V99 COMP-3.
       05 PO-SETTLED-RCV     PIC S9(15)V99 COMP-3.
       05 PO-ADJ-AMT         PIC S9(15)V99 COMP-3.
       05 PO-PENDING-COUNT   PIC 9(07).
       05 PO-SETTLED-COUNT   PIC 9(07).
       05 PO-LAST-DATE       PIC 9(08).
       05 PO-UPDATED         PIC 9(14).
       05 PO-VERSION         PIC 9(05).
