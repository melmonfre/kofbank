IDENTIFICATION DIVISION.
PROGRAM-ID. BLCK.

*> Advisory cross-process lock.  The lock itself is a persistent claim record in
*> lock.idx (owner + TTL), so a hold taken in one CLI process is still visible
*> to a later, different process until it is released or expires - this is what
*> PIX mediation holds, card holds and the transaction/post locks rely on.
*>
*> The historical defect was purely atomicity: the check-and-set
*> (WRITE, INVALID KEY, READ, REWRITE) had no OS-level guard, so two processes
*> could both observe the key absent and both claim it (observed as a
*> same-requestId double create).  The fix is a real cross-process mutex around
*> that check-and-set: the KFLOCK helper (flock(2)) is held ONLY for the
*> microseconds of the claim/release on lock.idx and released before returning,
*> so it never becomes the long-lived hold itself and cannot strand on process
*> death.  Because every lock.idx mutation is now serialised, the GnuCOBOL ISAM
*> lost-update/corruption on concurrent writes is also eliminated for this file.
*>
*> Contract preserved for callers: "00" = acquired, non-"00" = busy or infra
*> error (mapped by callers to a safe refusal such as rc 24). 'A' = try-acquire,
*> 'R' = release. See ADR 0022 for ordering and crash semantics.

ENVIRONMENT DIVISION.
INPUT-OUTPUT SECTION.
FILE-CONTROL.
    SELECT LOCK-FILE ASSIGN TO WS-LOCK-PATH
        ORGANIZATION IS INDEXED
        ACCESS MODE IS DYNAMIC
        RECORD KEY IS LK-NAME
        FILE STATUS IS WS-LK-ST.

DATA DIVISION.
FILE SECTION.
FD LOCK-FILE.
01 LOCK-REC.
   05 LK-NAME PIC X(24).
   05 LK-OWNER PIC X(16).
   05 LK-DATE PIC 9(08).
   05 LK-SECS PIC 9(05).

WORKING-STORAGE SECTION.
01 WS-LOCK-PATH PIC X(200).
01 WS-HOME PIC X(80).
01 WS-LK-ST PIC X(02).
01 WS-NOW PIC X(14).
01 WS-TODAY PIC 9(08).
01 WS-NOWSEC PIC 9(05).
01 WS-TTL PIC 9(05) VALUE 300.
01 WS-EXPIRE PIC 9(05).
01 WS-DATA-DIR PIC X(80).
01 WS-REG-NAME PIC X(64) VALUE "REGISTRY-LOCKIDX".
01 WS-KF-MODE PIC X(01).
01 WS-KF-STATUS PIC X(02).

LINKAGE SECTION.
01 LS-NAME PIC X(24).
01 LS-OWNER PIC X(16).
01 LS-MODE PIC X(01).
01 LS-STATUS PIC X(02).

PROCEDURE DIVISION USING LS-NAME LS-OWNER LS-MODE LS-STATUS.
    MOVE "00" TO LS-STATUS
    ACCEPT WS-HOME FROM ENVIRONMENT "BANK_HOME"
    MOVE SPACES TO WS-DATA-DIR
    STRING FUNCTION TRIM(WS-HOME) "/var/data"
        DELIMITED SIZE INTO WS-DATA-DIR
    END-STRING
    MOVE SPACES TO WS-LOCK-PATH
    STRING FUNCTION TRIM(WS-HOME) "/var/data/lock.idx"
        DELIMITED SIZE INTO WS-LOCK-PATH
    END-STRING
    PERFORM REG-ACQUIRE
    IF WS-KF-STATUS NOT = "00"
        MOVE WS-KF-STATUS TO LS-STATUS
        GOBACK
    END-IF
    EVALUATE LS-MODE
        WHEN "A" PERFORM ACQUIRE-LOCK
        WHEN "R" PERFORM RELEASE-LOCK
        WHEN OTHER MOVE "99" TO LS-STATUS
    END-EVALUATE
    PERFORM REG-RELEASE
    GOBACK.

ACQUIRE-LOCK.
    OPEN I-O LOCK-FILE
    IF WS-LK-ST = "35"
        OPEN OUTPUT LOCK-FILE
        CLOSE LOCK-FILE
        OPEN I-O LOCK-FILE
    END-IF
    IF WS-LK-ST NOT = "00"
        MOVE WS-LK-ST TO LS-STATUS
        GOBACK
    END-IF
    MOVE FUNCTION CURRENT-DATE TO WS-NOW
    MOVE WS-NOW(1:8) TO WS-TODAY
    COMPUTE WS-NOWSEC = FUNCTION NUMVAL(WS-NOW(9:2)) * 3600
        + FUNCTION NUMVAL(WS-NOW(11:2)) * 60
        + FUNCTION NUMVAL(WS-NOW(13:2))
    COMPUTE WS-EXPIRE = WS-NOWSEC + WS-TTL
    IF WS-EXPIRE > 86399
        MOVE 86399 TO WS-EXPIRE
    END-IF
    MOVE LS-NAME TO LK-NAME
    MOVE LS-OWNER TO LK-OWNER
    MOVE WS-TODAY TO LK-DATE
    MOVE WS-EXPIRE TO LK-SECS
    WRITE LOCK-REC
        INVALID KEY PERFORM RECLAIM-OR-FAIL
    END-WRITE
    CLOSE LOCK-FILE.

RECLAIM-OR-FAIL.
    READ LOCK-FILE
    EVALUATE WS-LK-ST
        WHEN "23"
            MOVE "00" TO LS-STATUS
            MOVE LS-OWNER TO LK-OWNER
            MOVE WS-TODAY TO LK-DATE
            MOVE WS-EXPIRE TO LK-SECS
            WRITE LOCK-REC
                INVALID KEY MOVE "61" TO LS-STATUS
        WHEN "00"
            IF LK-DATE < WS-TODAY OR LK-SECS < WS-NOWSEC
                MOVE LS-OWNER TO LK-OWNER
                MOVE WS-TODAY TO LK-DATE
                MOVE WS-EXPIRE TO LK-SECS
                REWRITE LOCK-REC
            ELSE
                MOVE "61" TO LS-STATUS
            END-IF
        WHEN OTHER
            MOVE "61" TO LS-STATUS
    END-EVALUATE.

RELEASE-LOCK.
    MOVE LS-NAME TO LK-NAME
    OPEN I-O LOCK-FILE
    IF WS-LK-ST = "00"
        READ LOCK-FILE
            INVALID KEY CONTINUE
            NOT INVALID KEY
                IF LK-OWNER = LS-OWNER
                    DELETE LOCK-FILE RECORD
                END-IF
        END-READ
    END-IF
    CLOSE LOCK-FILE.

REG-ACQUIRE.
    MOVE "W" TO WS-KF-MODE
    CALL "KFLOCK" USING WS-KF-MODE WS-DATA-DIR WS-REG-NAME
        WS-KF-STATUS.

REG-RELEASE.
    MOVE "R" TO WS-KF-MODE
    CALL "KFLOCK" USING WS-KF-MODE WS-DATA-DIR WS-REG-NAME
        WS-KF-STATUS.
