      *> EOD batch checkpoint parameters (GATE 4).  Operational control
      *> data only; no financial truth.  01 group: BK-EODCHK-PARM.
       01 BK-EODCHK-PARM.
          05 EC-OP             PIC X(08).
          05 EC-BIZDATE        PIC 9(08).
          05 EC-STATE          PIC X(07).
          05 EC-CUR-STAGE      PIC X(20).
          05 EC-LAST-STAGE     PIC X(20).
          05 EC-RC             PIC X(02).
          05 EC-MSG            PIC X(80).
          05 EC-OPERATOR       PIC X(12).
          05 EC-REQ            PIC X(24).
          05 EC-STAGE-NO       PIC 9(02).
