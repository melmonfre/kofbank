IDENTIFICATION DIVISION.
PROGRAM-ID. BPXRVS.

*> Durable split-reversal header store.  Indexed by reversal id;
*> lookup by (orig-pix, request) is a bounded sequential scan of the
*> small per-institution header file (same convention as other list
*> scans in this domain).  No money is ever computed here: this is
*> identity and state only.

ENVIRONMENT DIVISION.
INPUT-OUTPUT SECTION.
FILE-CONTROL.
    SELECT RV-FILE ASSIGN TO WS-RV-PATH
        ORGANIZATION IS INDEXED
        ACCESS MODE IS DYNAMIC
        RECORD KEY IS RV-REV-ID OF RV-REC
        FILE STATUS IS WS-RV-ST.

DATA DIVISION.
FILE SECTION.
FD RV-FILE.
01 RV-REC.
   COPY "BPXRV".

WORKING-STORAGE SECTION.
01 WS-RV-PATH PIC X(200).
01 WS-HOME PIC X(80).
01 WS-RV-ST PIC X(02).
01 WS-EOF PIC X(01).

LINKAGE SECTION.
COPY "BPXRVP".
01 BK-PX-RV-PARMS.
   COPY "BPXRV".

PROCEDURE DIVISION USING BK-PX-RV-STO-REQ BK-PX-RV-PARMS
    BK-PX-RV-LIST.
    MOVE "00" TO RVQ-RC
    MOVE SPACES TO RVQ-MSG
    ACCEPT WS-HOME FROM ENVIRONMENT "BANK_HOME"
    MOVE SPACES TO WS-RV-PATH
    STRING FUNCTION TRIM(WS-HOME) "/var/data/pxrev.idx"
        DELIMITED SIZE INTO WS-RV-PATH
    EVALUATE FUNCTION TRIM(RVQ-OP)
        WHEN "WRITE" PERFORM DO-WRITE
        WHEN "REWRITE" PERFORM DO-REWRITE
        WHEN "GET" PERFORM DO-GET
        WHEN "GET-REQ" PERFORM DO-GET-REQ
        WHEN "LIST-BY-PIX" PERFORM DO-LIST-BY-PIX
        WHEN OTHER
            MOVE "99" TO RVQ-RC
            MOVE "UNKNOWN REVERSAL STO OP" TO RVQ-MSG
    END-EVALUATE
    GOBACK.

DO-WRITE.
    PERFORM OPEN-I-O
    IF RVQ-RC NOT = "00"
        GOBACK
    END-IF
    MOVE BK-PX-RV-PARMS TO RV-REC
    WRITE RV-REC
        INVALID KEY
            MOVE "22" TO RVQ-RC
            MOVE "REVERSAL ALREADY EXISTS" TO RVQ-MSG
        NOT INVALID KEY
            CONTINUE
    END-WRITE
    CLOSE RV-FILE.

DO-REWRITE.
    PERFORM OPEN-I-O
    IF RVQ-RC NOT = "00"
        GOBACK
    END-IF
    MOVE RV-REV-ID OF BK-PX-RV-PARMS TO RV-REV-ID OF RV-REC
    READ RV-FILE
        INVALID KEY
            MOVE "23" TO RVQ-RC
            MOVE "REVERSAL NOT FOUND" TO RVQ-MSG
    END-READ
    IF RVQ-RC NOT = "00"
        CLOSE RV-FILE
        GOBACK
    END-IF
    MOVE BK-PX-RV-PARMS TO RV-REC
    REWRITE RV-REC
        INVALID KEY
            MOVE "23" TO RVQ-RC
            MOVE "REVERSAL NOT FOUND" TO RVQ-MSG
        NOT INVALID KEY
            CONTINUE
    END-REWRITE
    CLOSE RV-FILE.

DO-GET.
    PERFORM OPEN-INPUT
    IF RVQ-RC NOT = "00"
        GOBACK
    END-IF
    MOVE RVQ-REV-ID TO RV-REV-ID OF RV-REC
    READ RV-FILE
        INVALID KEY
            MOVE "23" TO RVQ-RC
            MOVE "REVERSAL NOT FOUND" TO RVQ-MSG
        NOT INVALID KEY
            MOVE RV-REC TO BK-PX-RV-PARMS
    END-READ
    CLOSE RV-FILE.

DO-GET-REQ.
    MOVE SPACES TO BK-PX-RV-PARMS
    PERFORM OPEN-INPUT
    IF RVQ-RC NOT = "00"
        GOBACK
    END-IF
    MOVE "N" TO WS-EOF
    MOVE "23" TO RVQ-RC
    PERFORM UNTIL WS-EOF = "Y"
        READ RV-FILE
            AT END MOVE "Y" TO WS-EOF
            NOT AT END
                IF RV-ORIG-PIX-ID OF RV-REC = RVQ-ORIG-PIX-ID AND
                   RV-REQUEST OF RV-REC = RVQ-REQUEST
                    MOVE RV-REC TO BK-PX-RV-PARMS
                    MOVE RV-REV-ID OF RV-REC TO RVQ-REV-ID
                    MOVE "00" TO RVQ-RC
                    MOVE "Y" TO WS-EOF
                END-IF
        END-READ
    END-PERFORM
    CLOSE RV-FILE
    IF RVQ-RC = "23"
        MOVE "PIX SPLIT REVERSAL NOT FOUND" TO RVQ-MSG
    END-IF.

DO-LIST-BY-PIX.
    MOVE 0 TO RVL-CNT
    MOVE 0 TO RVQ-DEVOLVED
    PERFORM OPEN-INPUT
    IF RVQ-RC NOT = "00"
        GOBACK
    END-IF
    MOVE "N" TO WS-EOF
    PERFORM UNTIL WS-EOF = "Y"
        READ RV-FILE
            AT END MOVE "Y" TO WS-EOF
            NOT AT END
                IF RV-ORIG-PIX-ID OF RV-REC = RVQ-ORIG-PIX-ID
                    IF RV-STATUS OF RV-REC NOT = "FAILED"
                        ADD RV-GROSS OF RV-REC TO RVQ-DEVOLVED
                    END-IF
                    ADD 1 TO RVL-CNT
                    IF RVL-CNT <= 20
                        MOVE RV-REV-ID OF RV-REC TO
                            RVL-REV-ID(RVL-CNT)
                        MOVE RV-REQUEST OF RV-REC TO
                            RVL-REQUEST(RVL-CNT)
                        MOVE RV-GROSS OF RV-REC TO
                            RVL-GROSS(RVL-CNT)
                        MOVE RV-CNT OF RV-REC TO RVL-LGCNT(RVL-CNT)
                        MOVE RV-STATUS OF RV-REC TO
                            RVL-STATUS(RVL-CNT)
                        MOVE RV-TXN-ID OF RV-REC TO
                            RVL-TXN-ID(RVL-CNT)
                        MOVE RV-JRN-ID OF RV-REC TO
                            RVL-JRN-ID(RVL-CNT)
                        MOVE RV-BIZDATE OF RV-REC TO
                            RVL-BIZDATE(RVL-CNT)
                    END-IF
                END-IF
        END-READ
    END-PERFORM
    CLOSE RV-FILE.

OPEN-I-O.
    OPEN I-O RV-FILE
    IF WS-RV-ST = "35" OR WS-RV-ST = "05" OR WS-RV-ST = "46"
        OPEN OUTPUT RV-FILE
        CLOSE RV-FILE
        OPEN I-O RV-FILE
    END-IF
    IF WS-RV-ST NOT = "00"
        MOVE "30" TO RVQ-RC
        MOVE "REVERSAL STORE UNAVAILABLE" TO RVQ-MSG
    END-IF.

OPEN-INPUT.
    OPEN INPUT RV-FILE
    IF WS-RV-ST = "35" OR WS-RV-ST = "05" OR WS-RV-ST = "46"
        MOVE "23" TO RVQ-RC
        MOVE "REVERSAL STORE EMPTY" TO RVQ-MSG
        EXIT PARAGRAPH
    END-IF
    IF WS-RV-ST NOT = "00"
        MOVE "30" TO RVQ-RC
        MOVE "REVERSAL STORE UNAVAILABLE" TO RVQ-MSG
    END-IF.
