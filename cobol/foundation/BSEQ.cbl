IDENTIFICATION DIVISION.
PROGRAM-ID. BSEQ.

*> Monotonic identifier allocation.  The read-increment-write of the sequence
*> file is a classic lost-update critical section.  It is now held under a
*> cross-process flock ("<data>/lk_SEQ-<name>.lck") via the KFLOCK helper, so
*> concurrent allocators cannot receive the same identifier and cannot
*> overwrite each other's counter.  The wait is bounded when
*> KOF_LOCK_TIMEOUT_MS is set (timeout surfaces as status "62"); when unset it
*> waits in-kernel and relies on kernel release at holder death.  Allocation
*> callers (BTXNLFC, BACOPN, BCUSTC) hard-fail on any non-"00" status rather
*> than minting an id from a failed allocation.  Sequence gaps after a crash
*> remain possible (an allocated id may not be committed), which the existing
*> contract permits; duplicate/reused ids are not.

ENVIRONMENT DIVISION.
INPUT-OUTPUT SECTION.
FILE-CONTROL.
    SELECT SEQ-FILE ASSIGN TO WS-SEQ-PATH
        ORGANIZATION IS LINE SEQUENTIAL
        ACCESS MODE IS SEQUENTIAL
        FILE STATUS IS WS-SEQ-ST.

DATA DIVISION.
FILE SECTION.
FD SEQ-FILE.
01 SEQ-NUM PIC 9(12).

WORKING-STORAGE SECTION.
01 WS-SEQ-PATH PIC X(200).
01 WS-HOME PIC X(80).
01 WS-SEQ-ST PIC X(02).
01 WS-CUR PIC 9(12) VALUE 0.
01 WS-DATA-DIR PIC X(80).
01 WS-SEQ-LOCK PIC X(64).
01 WS-KF-MODE PIC X(01).
01 WS-KF-STATUS PIC X(02).

LINKAGE SECTION.
01 LS-SEQ-NAME PIC X(20).
01 LS-SEQ-NEXT PIC 9(12).
01 LS-STATUS PIC X(02).

PROCEDURE DIVISION USING LS-SEQ-NAME LS-SEQ-NEXT LS-STATUS.
    MOVE "00" TO LS-STATUS
    MOVE 0 TO LS-SEQ-NEXT
    MOVE 0 TO WS-CUR
    ACCEPT WS-HOME FROM ENVIRONMENT "BANK_HOME"
    MOVE SPACES TO WS-DATA-DIR
    STRING FUNCTION TRIM(WS-HOME) "/var/data"
        DELIMITED SIZE INTO WS-DATA-DIR
    END-STRING
    MOVE SPACES TO WS-SEQ-PATH
    STRING FUNCTION TRIM(WS-HOME) "/var/data/seq_"
        DELIMITED SIZE FUNCTION TRIM(LS-SEQ-NAME) DELIMITED SIZE
        ".dat" DELIMITED SIZE INTO WS-SEQ-PATH
    END-STRING
    MOVE SPACES TO WS-SEQ-LOCK
    STRING "SEQ-" DELIMITED SIZE FUNCTION TRIM(LS-SEQ-NAME)
        DELIMITED SIZE INTO WS-SEQ-LOCK
    END-STRING
    MOVE "W" TO WS-KF-MODE
    CALL "KFLOCK" USING WS-KF-MODE WS-DATA-DIR WS-SEQ-LOCK
        WS-KF-STATUS
    IF WS-KF-STATUS NOT = "00"
        MOVE WS-KF-STATUS TO LS-STATUS
        GOBACK
    END-IF
    OPEN INPUT SEQ-FILE
    IF WS-SEQ-ST = "00"
        READ SEQ-FILE
            NOT AT END MOVE SEQ-NUM TO WS-CUR
        END-READ
        CLOSE SEQ-FILE
    END-IF
    ADD 1 TO WS-CUR
    OPEN OUTPUT SEQ-FILE
    MOVE WS-CUR TO SEQ-NUM
    WRITE SEQ-NUM
    CLOSE SEQ-FILE
    MOVE "R" TO WS-KF-MODE
    CALL "KFLOCK" USING WS-KF-MODE WS-DATA-DIR WS-SEQ-LOCK
        WS-KF-STATUS
    MOVE WS-CUR TO LS-SEQ-NEXT
    MOVE "00" TO LS-STATUS
    GOBACK.
