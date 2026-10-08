IDENTIFICATION DIVISION.
PROGRAM-ID. BCLK.

*> Deterministic UTC clock.
*>
*> Single temporal primitive for domains that need an exact instant.
*> It carries only wall-clock mechanics: NOW (with a test-override),
*> ADD-SECONDS and DIFF-SECONDS over full UTC timestamps.  No business
*> rule lives here: QR TTL, MED deadlines, claim resolution periods,
*> loan due dates and batch business dates each keep their own semantics
*> and merely consume these primitives.  They must not share business
*> rules accidentally; only this low-level clock is shared.
*>
*> Source priority for NOW:
*>   1. PIX_CLOCK_NOW  YYYYMMDDHHMMSS (deterministic test override)
*>   2. system clock   FUNCTION CURRENT-DATE (already UTC)
*>
*> Calendar arithmetic is pure proleptic-Gregorian integer math
*> (civil_from_days / days_from_civil), so second, minute, hour, day,
*> month, year and leap-year rollovers are exact and portable to
*> Enterprise COBOL.  Instants are PIC 9(14) UTC, YYYYMMDDHHMMSS, the
*> representation the persistent records already use; one second is the
*> smallest unit the platform timestamps carry.

ENVIRONMENT DIVISION.
DATA DIVISION.
WORKING-STORAGE SECTION.
01 WS-ENV-NOW      PIC X(20).
01 WS-STAGE        PIC X(14).
01 WS-EPOCH        PIC S9(18) VALUE 719468.
01 WS-Z            PIC S9(18).
01 WS-ERA          PIC S9(18).
01 WS-DOE          PIC S9(18).
01 WS-YOE          PIC S9(18).
01 WS-DOY          PIC S9(18).
01 WS-MP           PIC S9(18).
01 WS-DAY          PIC S9(18).
01 WS-MON          PIC S9(18).
01 WS-AA           PIC S9(18).
01 WS-MMD          PIC S9(18).
01 WS-D1           PIC S9(18).
01 WS-T1           PIC S9(15).
01 WS-D2           PIC S9(18).
01 WS-T2           PIC S9(15).
01 WS-HH           PIC S9(15).
01 WS-MIN          PIC S9(15).
01 WS-SS           PIC S9(15).
01 WS-SUM          PIC S9(15).
01 WS-Q1           PIC S9(18).
01 WS-Q2           PIC S9(18).
01 WS-Q3           PIC S9(18).
01 WS-QX           PIC S9(18).
01 WS-OY           PIC 9(04).
01 WS-OM           PIC 9(02).
01 WS-OD           PIC 9(02).
01 WS-OH           PIC 9(02).
01 WS-OI           PIC 9(02).
01 WS-OS           PIC 9(02).

LINKAGE SECTION.
COPY "BCLKP".

PROCEDURE DIVISION USING BK-CLK-PARMS.
    MOVE "00" TO CLK-RC
    MOVE SPACES TO CLK-MSG
    MOVE "SYS" TO CLK-SRC
    MOVE 0 TO CLK-DIFF
    EVALUATE FUNCTION TRIM(CLK-OP)
        WHEN "NOW" PERFORM DO-NOW
        WHEN "ADD-SECONDS" PERFORM DO-ADD-SECONDS
        WHEN "DIFF-SECONDS" PERFORM DO-DIFF-SECONDS
        WHEN OTHER
            MOVE "99" TO CLK-RC
            MOVE "UNKNOWN CLOCK OP" TO CLK-MSG
    END-EVALUATE
    GOBACK.

DO-NOW.
    MOVE SPACES TO WS-ENV-NOW
    ACCEPT WS-ENV-NOW FROM ENVIRONMENT "PIX_CLOCK_NOW"
    MOVE FUNCTION TRIM(WS-ENV-NOW) TO WS-STAGE
    IF WS-STAGE NOT = SPACES
        IF WS-STAGE IS NUMERIC
            MOVE WS-STAGE TO CLK-OUT
            MOVE "ENV" TO CLK-SRC
        ELSE
            MOVE "91" TO CLK-RC
            MOVE "BAD PIX_CLOCK_NOW VALUE" TO CLK-MSG
        END-IF
    ELSE
        MOVE FUNCTION CURRENT-DATE TO CLK-OUT
    END-IF.

DO-ADD-SECONDS.
    MOVE CLK-BASE TO WS-STAGE
    PERFORM VALIDATE-STAGE
    IF CLK-RC NOT = "00"
        GOBACK
    END-IF
    PERFORM STAGE-TO-ABSOLUTE
    ADD CLK-SECONDS TO WS-T1
    PERFORM NORMALIZE-ABSOLUTE
    PERFORM ABSOLUTE-TO-STAGE
    MOVE WS-STAGE TO CLK-OUT.

DO-DIFF-SECONDS.
    MOVE CLK-BASE TO WS-STAGE
    PERFORM VALIDATE-STAGE
    IF CLK-RC NOT = "00"
        GOBACK
    END-IF
    PERFORM STAGE-TO-ABSOLUTE
    MOVE WS-D1 TO WS-D2
    MOVE WS-T1 TO WS-T2
    MOVE CLK-BASE2 TO WS-STAGE
    PERFORM VALIDATE-STAGE
    IF CLK-RC NOT = "00"
        GOBACK
    END-IF
    PERFORM STAGE-TO-ABSOLUTE
    COMPUTE CLK-DIFF = (WS-D1 - WS-D2) * 86400 +
        (WS-T1 - WS-T2).

VALIDATE-STAGE.
    IF WS-STAGE IS NOT NUMERIC OR WS-STAGE = 0
        MOVE "93" TO CLK-RC
        MOVE "CLOCK INSTANT INVALID" TO CLK-MSG
    END-IF.

STAGE-TO-ABSOLUTE.
    MOVE WS-STAGE(1:4) TO WS-AA
    MOVE WS-STAGE(5:2) TO WS-MON
    MOVE WS-STAGE(7:2) TO WS-DAY
    MOVE WS-STAGE(9:2) TO WS-HH
    MOVE WS-STAGE(11:2) TO WS-MIN
    MOVE WS-STAGE(13:2) TO WS-SS
    IF WS-MON <= 2
        SUBTRACT 1 FROM WS-AA
        ADD 9 TO WS-MON
    ELSE
        SUBTRACT 3 FROM WS-MON
    END-IF
    IF WS-AA >= 0
        COMPUTE WS-ERA = WS-AA / 400
    ELSE
        COMPUTE WS-ERA = WS-AA / 400 - 1
    END-IF
    COMPUTE WS-YOE = WS-AA - WS-ERA * 400
    COMPUTE WS-MMD = WS-MON
    COMPUTE WS-QX = 153 * WS-MMD + 2
    COMPUTE WS-Q1 = WS-QX / 5
    COMPUTE WS-DOY = WS-Q1 + WS-DAY - 1
    COMPUTE WS-Q1 = WS-YOE / 4
    COMPUTE WS-Q2 = WS-YOE / 100
    COMPUTE WS-DOE = WS-YOE * 365 + WS-Q1 - WS-Q2 + WS-DOY
    COMPUTE WS-D1 = WS-ERA * 146097 + WS-DOE - WS-EPOCH
    COMPUTE WS-T1 = WS-HH * 3600 + WS-MIN * 60 + WS-SS.

NORMALIZE-ABSOLUTE.
    PERFORM UNTIL WS-T1 >= 0 AND WS-T1 < 86400
        IF WS-T1 < 0
            ADD 86400 TO WS-T1
            SUBTRACT 1 FROM WS-D1
        ELSE
            SUBTRACT 86400 FROM WS-T1
            ADD 1 TO WS-D1
        END-IF
    END-PERFORM.

ABSOLUTE-TO-STAGE.
    COMPUTE WS-Z = WS-D1 + WS-EPOCH
    IF WS-Z >= 0
        COMPUTE WS-ERA = WS-Z / 146097
    ELSE
        COMPUTE WS-ERA = WS-Z / 146097 - 1
    END-IF
    COMPUTE WS-DOE = WS-Z - WS-ERA * 146097
    COMPUTE WS-Q1 = WS-DOE / 1460
    COMPUTE WS-Q2 = WS-DOE / 36524
    COMPUTE WS-Q3 = WS-DOE / 146096
    COMPUTE WS-QX = WS-DOE - WS-Q1 + WS-Q2 - WS-Q3
    COMPUTE WS-YOE = WS-QX / 365
    COMPUTE WS-AA = WS-YOE + WS-ERA * 400
    COMPUTE WS-Q1 = 365 * WS-YOE
    COMPUTE WS-Q2 = WS-YOE / 4
    COMPUTE WS-Q3 = WS-YOE / 100
    COMPUTE WS-DOY = WS-DOE - (WS-Q1 + WS-Q2 - WS-Q3)
    COMPUTE WS-MP = (5 * WS-DOY + 2) / 153
    COMPUTE WS-QX = (153 * WS-MP + 2) / 5
    COMPUTE WS-DAY = WS-DOY - WS-QX + 1
    IF WS-MP < 10
        COMPUTE WS-MON = WS-MP + 3
    ELSE
        COMPUTE WS-MON = WS-MP - 9
        ADD 1 TO WS-AA
    END-IF
    COMPUTE WS-HH = WS-T1 / 3600
    COMPUTE WS-SUM = WS-HH * 3600
    COMPUTE WS-MIN = (WS-T1 - WS-SUM) / 60
    COMPUTE WS-SS = WS-T1 - WS-SUM - WS-MIN * 60

    MOVE WS-AA TO WS-OY
    MOVE WS-MON TO WS-OM
    MOVE WS-DAY TO WS-OD
    MOVE WS-HH TO WS-OH
    MOVE WS-MIN TO WS-OI
    MOVE WS-SS TO WS-OS
    MOVE WS-OY TO WS-STAGE(1:4)
    MOVE WS-OM TO WS-STAGE(5:2)
    MOVE WS-OD TO WS-STAGE(7:2)
    MOVE WS-OH TO WS-STAGE(9:2)
    MOVE WS-OI TO WS-STAGE(11:2)
    MOVE WS-OS TO WS-STAGE(13:2).
