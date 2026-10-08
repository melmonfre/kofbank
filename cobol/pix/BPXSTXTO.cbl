IDENTIFICATION DIVISION.
PROGRAM-ID. BPXSTXTO.

*> Durable SPI Split Tax message envelope store (local double).  Keeps
*> the exact contract representation that crossed the boundary so
*> ingestion can be replayed after restart and audit can answer "which
*> external message carried this Tax information" from structured
*> records, not log text.  Envelopes are transport artifacts: this
*> store never participates in financial posting.

ENVIRONMENT DIVISION.
INPUT-OUTPUT SECTION.
FILE-CONTROL.
    SELECT SPITX-FILE ASSIGN TO WS-SPITX-PATH
        ORGANIZATION IS INDEXED
        ACCESS MODE IS DYNAMIC
        RECORD KEY IS SPITX-KEY OF SPITX-REC
        FILE STATUS IS WS-SPITX-ST.

DATA DIVISION.
FILE SECTION.
FD SPITX-FILE.
01 SPITX-REC.
   05 SPITX-KEY              PIC X(70).
   05 SPITX-MSGNM            PIC X(20).
   05 SPITX-VER              PIC X(05).
   05 SPITX-MSGR-ID          PIC X(32).
   05 SPITX-E2E-ID           PIC X(32).
   05 SPITX-STATUS           PIC X(10).
   05 SPITX-CODE             PIC X(04).
   05 SPITX-CODESRC          PIC X(04).
   05 SPITX-PIX-ID           PIC X(12).
   05 SPITX-TXN-ID           PIC X(12).
   05 SPITX-JRN-ID           PIC X(20).
   05 SPITX-ENVELOPE         PIC X(2000).

WORKING-STORAGE SECTION.
01 WS-SPITX-PATH  PIC X(200).
01 WS-SPITX-ST    PIC X(02).
01 WS-HOME        PIC X(80).
01 WS-EOF         PIC X(01).

LINKAGE SECTION.
COPY "BPTXP".

PROCEDURE DIVISION USING BK-SPITAX-PARMS.
    MOVE "00" TO XT-RC
    MOVE SPACES TO XT-MSG
    EVALUATE FUNCTION TRIM(XT-OP)
        WHEN "STX-PUT" PERFORM DO-PUT
        WHEN "STX-GET" PERFORM DO-GET
        WHEN "STX-GETE2E" PERFORM DO-GETE2E
        WHEN "STX-LIST" PERFORM DO-LIST
        WHEN OTHER
            MOVE "99" TO XT-RC
            MOVE "UNKNOWN SPITAX STO OP" TO XT-MSG
    END-EVALUATE
    GOBACK.

OPEN-STORE.
    ACCEPT WS-HOME FROM ENVIRONMENT "BANK_HOME"
    MOVE SPACES TO WS-SPITX-PATH
    STRING FUNCTION TRIM(WS-HOME) "/var/data/pxspitx.idx"
        DELIMITED SIZE INTO WS-SPITX-PATH
    END-STRING
    OPEN I-O SPITX-FILE
    IF WS-SPITX-ST = "35"
        OPEN OUTPUT SPITX-FILE
        CLOSE SPITX-FILE
        OPEN I-O SPITX-FILE
    END-IF
    IF WS-SPITX-ST NOT = "00"
        MOVE "20" TO XT-RC
        MOVE "SPI TAX STORE UNAVAILABLE" TO XT-MSG
    END-IF.
    EXIT PARAGRAPH.

DO-PUT.
    PERFORM OPEN-STORE
    IF XT-RC = "00"
        MOVE XT-KEY TO SPITX-KEY OF SPITX-REC
        MOVE XT-MSGNM TO SPITX-MSGNM OF SPITX-REC
        MOVE XT-VER TO SPITX-VER OF SPITX-REC
        MOVE XT-MSGR-ID TO SPITX-MSGR-ID OF SPITX-REC
        MOVE XT-E2E-ID TO SPITX-E2E-ID OF SPITX-REC
        MOVE XT-STATUS TO SPITX-STATUS OF SPITX-REC
        MOVE XT-CODE TO SPITX-CODE OF SPITX-REC
        MOVE XT-CODESRC TO SPITX-CODESRC OF SPITX-REC
        MOVE XT-PIX-ID TO SPITX-PIX-ID OF SPITX-REC
        MOVE XT-TXN-ID TO SPITX-TXN-ID OF SPITX-REC
        MOVE XT-JRN-ID TO SPITX-JRN-ID OF SPITX-REC
        MOVE XT-ENV TO SPITX-ENVELOPE OF SPITX-REC
        READ SPITX-FILE
            INVALID KEY
                WRITE SPITX-REC
                    INVALID KEY
                        MOVE "22" TO XT-RC
                        MOVE "SPI TAX MESSAGE ALREADY STORED"
                            TO XT-MSG
                    NOT INVALID KEY
                        MOVE "00" TO XT-RC
                        MOVE "SPI TAX MESSAGE STORED" TO XT-MSG
                END-WRITE
            NOT INVALID KEY
                IF XT-ENV = SPITX-ENVELOPE OF SPITX-REC AND
                   XT-STATUS = SPITX-STATUS OF SPITX-REC
                    MOVE "22" TO XT-RC
                    MOVE "SPI TAX MESSAGE ALREADY STORED"
                        TO XT-MSG
                ELSE
                    REWRITE SPITX-REC
                        INVALID KEY
                            MOVE "20" TO XT-RC
                            MOVE "SPI TAX STORE REWRITE FAILED"
                                TO XT-MSG
                        NOT INVALID KEY
                            MOVE "00" TO XT-RC
                            MOVE "SPI TAX MESSAGE RESTORED"
                                TO XT-MSG
                        END-REWRITE
                END-IF
        END-READ
        CLOSE SPITX-FILE
    END-IF.
    EXIT PARAGRAPH.

DO-GET.
    PERFORM OPEN-STORE
    IF XT-RC = "00"
        MOVE XT-KEY TO SPITX-KEY OF SPITX-REC
        READ SPITX-FILE
            INVALID KEY
                MOVE "23" TO XT-RC
                MOVE "SPI TAX MESSAGE NOT FOUND" TO XT-MSG
            NOT INVALID KEY
                MOVE SPACES TO XT-KEY XT-MSGNM XT-VER XT-MSGR-ID
                    XT-E2E-ID XT-STATUS XT-CODE XT-CODESRC
                    XT-PIX-ID XT-TXN-ID XT-JRN-ID XT-ENV
                MOVE SPITX-KEY OF SPITX-REC TO XT-KEY
                MOVE SPITX-MSGNM OF SPITX-REC TO XT-MSGNM
                MOVE SPITX-VER OF SPITX-REC TO XT-VER
                MOVE SPITX-MSGR-ID OF SPITX-REC TO XT-MSGR-ID
                MOVE SPITX-E2E-ID OF SPITX-REC TO XT-E2E-ID
                MOVE SPITX-STATUS OF SPITX-REC TO XT-STATUS
                MOVE SPITX-CODE OF SPITX-REC TO XT-CODE
                MOVE SPITX-CODESRC OF SPITX-REC TO XT-CODESRC
                MOVE SPITX-PIX-ID OF SPITX-REC TO XT-PIX-ID
                MOVE SPITX-TXN-ID OF SPITX-REC TO XT-TXN-ID
                MOVE SPITX-JRN-ID OF SPITX-REC TO XT-JRN-ID
                MOVE SPITX-ENVELOPE OF SPITX-REC TO XT-ENV
        END-READ
        CLOSE SPITX-FILE
    END-IF.
    EXIT PARAGRAPH.

DO-GETE2E.
    MOVE SPACES TO XT-KEY
    STRING "T" DELIMITED SIZE FUNCTION TRIM(XT-E2E-ID)
        DELIMITED SIZE INTO XT-KEY
    END-STRING
    PERFORM DO-GET.
    EXIT PARAGRAPH.

DO-LIST.
    MOVE 0 TO XT-CNT
    MOVE "N" TO WS-EOF
    PERFORM OPEN-STORE
    IF XT-RC = "00"
        MOVE SPACES TO XT-ENV
        PERFORM UNTIL WS-EOF = "Y"
            READ SPITX-FILE
                AT END
                    MOVE "Y" TO WS-EOF
                NOT AT END
                    IF XT-CNT < 20
                        ADD 1 TO XT-CNT
                        STRING FUNCTION TRIM(XT-ENV)
                            " [" DELIMITED SIZE
                            FUNCTION TRIM(SPITX-KEY OF SPITX-REC)
                            DELIMITED SIZE "] " DELIMITED SIZE
                            FUNCTION TRIM(SPITX-STATUS OF SPITX-REC)
                            DELIMITED SIZE
                            INTO XT-ENV
                        END-STRING
                    END-IF
            END-READ
        END-PERFORM
        CLOSE SPITX-FILE
    END-IF.
    EXIT PARAGRAPH.
