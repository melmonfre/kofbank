      *> MED batch run record (one per execution request id).  Keyed by a
      *> deterministic idempotency key.  Holds the restart checkpoint (last
      *> fully processed case id) and control totals.  Operational metadata
      *> only: no financial truth lives here; it can be purged without
      *> affecting accounting (runs would then simply re-execute replay-safe
      *> operations against persisted MED state).
          05 MBR-KEY.
             10 MBR-REQ-ID      PIC X(24).
          05 MBR-BIZDATE        PIC 9(08).
          05 MBR-STATUS         PIC X(12).
          05 MBR-OPERATOR       PIC X(12).
          05 MBR-CORR           PIC X(24).
          05 MBR-SCANNED        PIC 9(07).
          05 MBR-ELIGIBLE       PIC 9(07).
          05 MBR-EXPIRE-ELIG    PIC 9(07).
          05 MBR-RECOVER-ELIG   PIC 9(07).
          05 MBR-RECON-ELIG     PIC 9(07).
          05 MBR-PROCESSED      PIC 9(07).
          05 MBR-EXPIRED        PIC 9(07).
          05 MBR-RETRIED        PIC 9(07).
          05 MBR-REFRESHED      PIC 9(07).
          05 MBR-SKIPPED        PIC 9(07).
          05 MBR-RETRY-REQ      PIC 9(07).
          05 MBR-INCONSISTENT   PIC 9(07).
          05 MBR-EXCEPTIONS     PIC 9(07).
          05 MBR-FAILED         PIC 9(07).
          05 MBR-LAST-CASE      PIC X(12).
          05 MBR-STARTED        PIC 9(14).
          05 MBR-UPDATED        PIC 9(14).
          05 MBR-COMPLETED      PIC 9(14).
          05 MBR-SIM            PIC X(12).
