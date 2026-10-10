IDENTIFICATION DIVISION.
PROGRAM-ID. BWR.

*> Store-write serialiser.  Wraps the KFLOCK native helper so a COBOL caller can
*> bracket a single durable-store write (OPEN..WRITE..CLOSE) with a real
*> cross-process leaf lock without knowing about BANK_HOME path building.
*>
*>   CALL "BWR" USING WS-LOCK-MODE WS-LOCK-NAME WS-LOCK-STATUS
*>     mode 'W'  bounded-wait acquire (see KOF_LOCK_TIMEOUT_MS in KFLOCK;
*>               unset = kernel wait with release-at-death guarantee)
*>     mode 'R'  release
*>     status "00" success; "61" busy, "62" timeout, "EF" infra error -
*>     callers fail closed with the code, never fall back to unsynchronised.
*>
*> Leaf discipline: a WR-* lock is a short critical section acquired and
*> released within one program; it is NEVER held while acquiring another WR-*
*> lock.  Long-lived logical holds (transaction/request/PIX/card) stay in BLCK.
*> Ordering is therefore always logical-lock-then-store-leaf, never leaf-then-
*> leaf, so no store leaf can participate in a deadlock cycle.  See ADR 0022.

ENVIRONMENT DIVISION.
INPUT-OUTPUT SECTION.

DATA DIVISION.
WORKING-STORAGE SECTION.
01 WS-DATA-DIR PIC X(80).
01 WS-HOME PIC X(80).
01 WS-KF-MODE PIC X(01).

LINKAGE SECTION.
01 LS-MODE PIC X(01).
01 LS-NAME PIC X(64).
01 LS-STATUS PIC X(02).

PROCEDURE DIVISION USING LS-MODE LS-NAME LS-STATUS.
    ACCEPT WS-HOME FROM ENVIRONMENT "BANK_HOME"
    MOVE SPACES TO WS-DATA-DIR
    STRING FUNCTION TRIM(WS-HOME) "/var/data"
        DELIMITED SIZE INTO WS-DATA-DIR
    END-STRING
    MOVE LS-MODE TO WS-KF-MODE
    MOVE SPACES TO LS-STATUS
    CALL "KFLOCK" USING WS-KF-MODE WS-DATA-DIR LS-NAME LS-STATUS
    GOBACK.
