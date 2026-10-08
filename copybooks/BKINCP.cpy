      *> Incident parameters (GATE 4).  01 group: BK-INC-PARMS.
      *> Incidents are durable operational evidence: detection, severity,
      *> safe action taken, and an explicit resolution condition.  They
      *> never carry financial truth; they record what the operator saw
      *> and did.  Severity: SEV1 SEV2 SEV3.  State: OPEN ACK RESOLVED.
       01 BK-INC-PARMS.
          05 IN-OP             PIC X(08).
          05 IN-KEY            PIC X(24).
          05 IN-SUMMARY        PIC X(60).
          05 IN-SEV            PIC X(06).
          05 IN-STATE          PIC X(08).
          05 IN-EVIDENCE       PIC X(240).
          05 IN-ACTION         PIC X(80).
          05 IN-RESOLVE        PIC X(80).
          05 IN-OPERATOR       PIC X(12).
          05 IN-CORR           PIC X(24).
          05 IN-RC             PIC X(02).
          05 IN-MSG            PIC X(80).
