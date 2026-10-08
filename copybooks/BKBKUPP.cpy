      *> Backup/restore parameters (GATE 4).  01 group: BK-BKU-PARMS.
      *> Packages live under var/bkp/<tag>.  Creation is only allowed on
      *> a drained or stopped system so the copy is application-consistent.
      *> Restore APPLY requires the explicit CONFIRM-RESTORE token and is
      *> only allowed while the system is not RUNNING.
       01 BK-BKU-PARMS.
          05 KU-OP             PIC X(16).
          05 KU-TAG            PIC X(24).
          05 KU-OPERATOR       PIC X(12).
          05 KU-CONFIRM        PIC X(20).
          05 KU-CORR           PIC X(24).
          05 KU-COUNT          PIC 9(05).
          05 KU-RC             PIC X(02).
          05 KU-MSG            PIC X(80).
