      *> Startup safety classification parameters (GATE 4).
      *> 01 group name: BK-OPS-PARMS.
      *> Classes: CLEAN RECOVERABLE OPERATOR_REQUIRED CORRUPT
      *>          UNINITIALIZED
      *> The classifier inspects durable state only.  It never mutates
      *> financial truth and never guesses unknown states.
       01 BK-OPS-PARMS.
          05 OP-OP             PIC X(10).
          05 OP-CLASS          PIC X(18).
          05 OP-STATE          PIC X(18).
          05 OP-TXN-PEND       PIC 9(05).
          05 OP-JRN-STAGE      PIC 9(05).
          05 OP-OUTB-OPEN      PIC 9(05).
          05 OP-OUTB-UNK       PIC 9(05).
          05 OP-MSG-UNFIN      PIC 9(05).
          05 OP-IDM-STUCK      PIC 9(05).
          05 OP-LOCK-STALE     PIC 9(05).
          05 OP-REC-OPEN       PIC 9(05).
          05 OP-EOD-INTERRUPT  PIC 9(05).
          05 OP-CORRUPT-LINES  PIC 9(05).
          05 OP-CORRUPT        PIC X(01).
          05 OP-OPERATOR       PIC X(01).
          05 OP-RECOVER        PIC X(01).
          05 OP-RC             PIC X(02).
          05 OP-MSG            PIC X(80).
