       01 BK-PX-SS-STO-REQ.
          05 SS-OP             PIC X(16).
          05 SS-CYCLE-ID       PIC X(20).
          05 SS-STL-ID         PIC X(12).
          05 SS-XREF.
             10 SS-XREF-CYCLE  PIC X(20).
             10 SS-XREF-PART   PIC X(12).
             10 SS-XREF-SIDE   PIC X(10).
          05 SS-POS-KEY.
             10 SS-POS-PART    PIC X(12).
             10 SS-POS-SEP     PIC X(01).
             10 SS-POS-CUR     PIC X(03).
          05 SS-GROSS-PAY      PIC S9(15)V99 COMP-3.
          05 SS-GROSS-RCV      PIC S9(15)V99 COMP-3.
          05 SS-ADJ-AMT        PIC S9(15)V99 COMP-3.
          05 SS-NET-AMT        PIC S9(15)V99 COMP-3.
          05 SS-PARTY-COUNT    PIC 9(07).
          05 SS-OBL-PAY        PIC 9(07).
          05 SS-OBL-RCV        PIC 9(07).
          05 SS-ITEM-COUNT     PIC 9(07).
          05 SS-ANY            PIC X(01).
          05 SS-C-PENDING      PIC 9(07).
          05 SS-C-SUBMITTED    PIC 9(07).
          05 SS-C-UNKNOWN      PIC 9(07).
          05 SS-C-SETTLED      PIC 9(07).
          05 SS-C-REJECTED     PIC 9(07).
          05 SS-C-RECON        PIC 9(07).
          05 SS-SETTLED-AMT    PIC S9(15)V99 COMP-3.
          05 SS-EXTERNAL-REF   PIC X(32).
          05 SS-RC             PIC X(02).
          05 SS-MSG            PIC X(80).
