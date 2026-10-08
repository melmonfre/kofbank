      *> EOD batch checkpoint record (GATE 4).  One row per business
      *> date in var/data/eodchk.idx.  STG marks completed stages so an
      *> interrupted EOD can resume without double-applying effects.
       05 EC-BD             PIC 9(08).
       05 EC-ST             PIC X(07).
       05 EC-CUR            PIC X(20).
       05 EC-LAST           PIC X(20).
       05 EC-RUN-RC         PIC X(02).
       05 EC-STARTED        PIC 9(14).
       05 EC-UPDATED        PIC 9(14).
       05 EC-OPER           PIC X(12).
       05 EC-REQ            PIC X(24).
       05 EC-STG OCCURS 30 TIMES PIC X(01).
