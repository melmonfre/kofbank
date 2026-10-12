IDENTIFICATION DIVISION.
PROGRAM-ID. TESTBGLPST.

ENVIRONMENT DIVISION.
INPUT-OUTPUT SECTION.

DATA DIVISION.
WORKING-STORAGE SECTION.
01 WS-COUNT PIC 9(04).
01 WS-STATUS PIC X(02).
01 WS-LK-MODE PIC X(01).
01 WS-LK-NAME PIC X(64) VALUE "WR-LEDGER".
01 WS-LK-STATUS PIC X(02).

COPY "BKJRNP".
COPY "BKPSTT".

PROCEDURE DIVISION.
    *> Step 1: Initialize chart of accounts via BGLCHT
    CALL "BGLCHT" USING WS-COUNT WS-STATUS
    DISPLAY "test=chart_init rc=" WS-STATUS " count=" WS-COUNT

    *> Step 2: Prepare first balanced posting (1000.00 BRL)
    MOVE SPACES TO BK-JRN-PARMS
    MOVE SPACES TO BK-PST-TABLE
    MOVE "JRN-TEST-001" TO BK-JRN-ID
    MOVE "TX-TEST-001"  TO BK-JRN-TX-ID
    MOVE "20261012"     TO BK-JRN-BIZDATE
    MOVE "W"            TO BK-JRN-MODE
    MOVE 2              TO BK-JRN-COUNT

    *> Leg 1: Debit 1010 (Asset) entity A00000000001
    MOVE "1010"         TO BK-PST-GL(1)
    MOVE "D"            TO BK-PST-DC(1)
    MOVE 1000.00        TO BK-PST-AMOUNT(1)
    MOVE "A00000000001" TO BK-PST-ENTITY(1)
    MOVE "BRL"          TO BK-PST-CURRENCY(1)

    *> Leg 2: Credit 2010 (Liability) entity A00000000002
    MOVE "2010"         TO BK-PST-GL(2)
    MOVE "C"            TO BK-PST-DC(2)
    MOVE 1000.00        TO BK-PST-AMOUNT(2)
    MOVE "A00000000002" TO BK-PST-ENTITY(2)
    MOVE "BRL"          TO BK-PST-CURRENCY(2)

    *> Execute posting
    CALL "BGLPST" USING BK-JRN-PARMS BK-PST-TABLE
    DISPLAY "test=post_1 rc=" BK-JRN-RC " msg=" FUNCTION TRIM(BK-JRN-MSG)

    *> Step 3: Verify WR-LEDGER lock was NOT leaked by BGLPST
    *> In the unfixed code, APPEND-POSTINGS leaked the lock, so non-nested acquire in same process returned 61
    MOVE "W" TO WS-LK-MODE
    CALL "BWR" USING WS-LK-MODE WS-LK-NAME WS-LK-STATUS
    DISPLAY "test=lock_released_1 status=" WS-LK-STATUS
    IF WS-LK-STATUS = "00"
        MOVE "R" TO WS-LK-MODE
        CALL "BWR" USING WS-LK-MODE WS-LK-NAME WS-LK-STATUS
    END-IF

    *> Step 4: Prepare second sequential posting (500.00 BRL)
    MOVE SPACES TO BK-JRN-PARMS
    MOVE SPACES TO BK-PST-TABLE
    MOVE "JRN-TEST-002" TO BK-JRN-ID
    MOVE "TX-TEST-002"  TO BK-JRN-TX-ID
    MOVE "20261012"     TO BK-JRN-BIZDATE
    MOVE "W"            TO BK-JRN-MODE
    MOVE 2              TO BK-JRN-COUNT

    MOVE "1010"         TO BK-PST-GL(1)
    MOVE "D"            TO BK-PST-DC(1)
    MOVE 500.00         TO BK-PST-AMOUNT(1)
    MOVE "A00000000001" TO BK-PST-ENTITY(1)
    MOVE "BRL"          TO BK-PST-CURRENCY(1)

    MOVE "2010"         TO BK-PST-GL(2)
    MOVE "C"            TO BK-PST-DC(2)
    MOVE 500.00         TO BK-PST-AMOUNT(2)
    MOVE "A00000000002" TO BK-PST-ENTITY(2)
    MOVE "BRL"          TO BK-PST-CURRENCY(2)

    CALL "BGLPST" USING BK-JRN-PARMS BK-PST-TABLE
    DISPLAY "test=post_2 rc=" BK-JRN-RC " msg=" FUNCTION TRIM(BK-JRN-MSG)

    *> Step 5: Verify lock released after second posting as well
    MOVE "W" TO WS-LK-MODE
    CALL "BWR" USING WS-LK-MODE WS-LK-NAME WS-LK-STATUS
    DISPLAY "test=lock_released_2 status=" WS-LK-STATUS
    IF WS-LK-STATUS = "00"
        MOVE "R" TO WS-LK-MODE
        CALL "BWR" USING WS-LK-MODE WS-LK-NAME WS-LK-STATUS
    END-IF

    GOBACK.
