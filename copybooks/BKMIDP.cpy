      *> Inbound message identity registry parameters (BXMSGID, GATE 3).
      *> 01 group name: BK-MSGID-PARMS.
       01 BK-MSGID-PARMS.
          05 MD-OP             PIC X(14).
          05 MD-MSG-ID         PIC X(32).
          05 MD-VER            PIC X(05).
          05 MD-FAMILY         PIC X(20).
          05 MD-E2E            PIC X(32).
          05 MD-FP             PIC X(16).
          05 MD-ENV            PIC X(16).
          05 MD-CHANNEL        PIC X(12).
          05 MD-AMOUNT         PIC S9(15)V99 COMP-3.
          05 MD-CURRENCY       PIC X(03).
          05 MD-STATE          PIC X(16).
          05 MD-PIX            PIC X(12).
          05 MD-TXN            PIC X(12).
          05 MD-JRN            PIC X(20).
          05 MD-CNT            PIC 9(04).
          05 MD-RC             PIC X(02).
          05 MD-MSG            PIC X(80).
