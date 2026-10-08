      *> System lifecycle parameters (BLIFE, GATE 4).
      *> 01 group name: BK-LIFE-PARMS.
      *> States: STOPPED STARTING RUNNING DRAINING MAINTENANCE
      *>         RECOVERY_REQUIRED RECOVERING
      *> Transitions are validated here; financial state is never derived
      *> from the lifecycle record, only the permission to act.
       01 BK-LIFE-PARMS.
          05 LF-OP             PIC X(10).
          05 LF-DOMAIN         PIC X(14).
          05 LF-CMD            PIC X(14).
          05 LF-STATE          PIC X(18).
          05 LF-REASON         PIC X(60).
          05 LF-OPERATOR       PIC X(12).
          05 LF-CORR           PIC X(24).
          05 LF-RC             PIC X(02).
          05 LF-MSG            PIC X(80).
