       *> DICT double service parameters.
       *> Boundary note: this models the participant-facing DICT API
       *> (claim lifecycle states, actor/reason matrices, resolution /
       *> completion periods, per-key versioning) as described in the
       *> current BCB "DICT API 2.X" specification.  It is a LOCAL
       *> deterministic double: no mTLS, no signatures, no RSFN
       *> connectivity.  Adapter=FIXTURE in etc/pix.cfg selects this
       *> program, never a Banco Central integration.
       01 BK-PX-DICT-PARMS.
          05 DT-OP             PIC X(16).
          05 DT-ADAPTER        PIC X(12).
          05 DT-KEY-TYPE       PIC X(10).
          05 DT-KEY-VALUE      PIC X(60).
          05 DT-KEY-HASH       PIC X(16).
          05 DT-KEY-MASK       PIC X(30).
          05 DT-KEY-ID         PIC X(12).
          05 DT-PART           PIC X(12).
          05 DT-ACCT           PIC X(12).
          05 DT-CUST           PIC X(12).
          05 DT-NAME           PIC X(60).
          05 DT-KEY-STATUS     PIC X(12).
          05 DT-CLAIM-STATUS   PIC X(18).
          05 DT-CLAIM-ID       PIC X(24).
          05 DT-CLAIM-TYPE     PIC X(12).
          05 DT-DONOR-PART     PIC X(12).
          05 DT-CLAIMER-CUST   PIC X(12).
          05 DT-CLAIMER-ACCT   PIC X(12).
          05 DT-CLAIMER-PART   PIC X(12).
          05 DT-CLAIM-REQ-ID   PIC X(24).
          05 DT-CONFIRM-REASON PIC X(20).
          05 DT-CANCEL-REASON  PIC X(20).
          05 DT-CANCELLED-BY   PIC X(12).
          05 DT-RESOL-END      PIC 9(08).
          05 DT-COMPL-END      PIC 9(08).
          05 DT-VERSION        PIC 9(05).
          05 DT-MIN-VERSION    PIC 9(05).
          05 DT-MATCH          PIC X(01).
          05 DT-FRAUD-FLAG     PIC X(01).
          05 DT-SELF-FLAG      PIC X(01).
          05 DT-SIM            PIC X(12).
          05 DT-COUNT          PIC 9(04).
          05 DT-DATE           PIC 9(08).
          05 DT-REASON         PIC X(40).
          05 DT-OPERATOR       PIC X(12).
          05 DT-CORR           PIC X(24).
          05 DT-REQUEST        PIC X(24).
          05 DT-REPLAY         PIC X(01).
          05 DT-RC             PIC X(02).
          05 DT-MSG            PIC X(80).
          05 DT-VERIFIED       PIC X(12).
