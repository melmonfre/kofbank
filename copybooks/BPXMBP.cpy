      *> Pix MED batch service parameters.  The batch driver (BPXMEOD)
      *> orchestrates the existing MED engine; it owns no financial state.
01 BK-MED-BATCH.
   05 MB-OP              PIC X(08).
   05 MB-SCOPE           PIC X(12).
   05 MB-REQ-ID          PIC X(24).
   05 MB-FAULT-AFTER     PIC 9(04).
   05 MB-BIZDATE         PIC 9(08).
   05 MB-SCANNED         PIC 9(07).
   05 MB-ELIGIBLE        PIC 9(07).
   05 MB-EXPIRE-ELIG     PIC 9(07).
   05 MB-RECOVER-ELIG    PIC 9(07).
   05 MB-RECON-ELIG      PIC 9(07).
   05 MB-PROCESSED       PIC 9(07).
   05 MB-EXPIRED         PIC 9(07).
   05 MB-RETRIED         PIC 9(07).
   05 MB-REFRESHED       PIC 9(07).
   05 MB-SKIPPED         PIC 9(07).
    05 MB-RETRY-REQ      PIC 9(07).
    05 MB-INCONSISTENT    PIC 9(07).
    05 MB-EXCEPTIONS     PIC 9(07).
   05 MB-FAILED          PIC 9(07).
   05 MB-LAST-CASE       PIC X(12).
   05 MB-CASE-ID         PIC X(12).
   05 MB-RUN-STATUS      PIC X(12).
   05 MB-ELIG-CLASS      PIC X(08).
   05 MB-CLASS           PIC X(14).
   05 MB-SIM             PIC X(12).
   05 MB-REPLAY          PIC X(01).
   05 MB-OPERATOR        PIC X(12).
   05 MB-CORR            PIC X(24).
   05 MB-RC              PIC X(02).
   05 MB-MSG             PIC X(80).
