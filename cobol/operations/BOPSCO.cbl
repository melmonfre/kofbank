IDENTIFICATION DIVISION.
PROGRAM-ID. BOPSCO.

*> Cross-store correlation (GATE 4).  Given one id (transaction, journal,
*> message, intent, exception, incident, operator, external ref) scan
*> every durable operational store and chain log that can reference it.
*> Read-only.  This is the evidence trail, not a financial operation.

ENVIRONMENT DIVISION.
INPUT-OUTPUT SECTION.
FILE-CONTROL.
    SELECT TXN-FILE ASSIGN TO WS-TXN-PATH
        ORGANIZATION IS INDEXED
        ACCESS MODE IS SEQUENTIAL
        RECORD KEY IS TXN-ID OF TXN-REC
        FILE STATUS IS WS-TXN-ST.
    SELECT JST-FILE ASSIGN TO WS-JST-PATH
        ORGANIZATION IS INDEXED
        ACCESS MODE IS SEQUENTIAL
        RECORD KEY IS JST-ID OF JST-REC
        FILE STATUS IS WS-JST-ST.
    SELECT OB-FILE ASSIGN TO WS-OB-PATH
        ORGANIZATION IS INDEXED
        ACCESS MODE IS SEQUENTIAL
        RECORD KEY IS OB-OPID OF OB-REC
        FILE STATUS IS WS-OB-ST.
    SELECT MI-FILE ASSIGN TO WS-MI-PATH
        ORGANIZATION IS INDEXED
        ACCESS MODE IS SEQUENTIAL
        RECORD KEY IS MI-MSGID OF MI-REC
        FILE STATUS IS WS-MI-ST.
    SELECT EXC-FILE ASSIGN TO WS-EXC-PATH
        ORGANIZATION IS INDEXED
        ACCESS MODE IS SEQUENTIAL
        RECORD KEY IS EXC-ID OF EXC-REC
        FILE STATUS IS WS-EXC-ST.
    SELECT INC-FILE ASSIGN TO WS-INC-PATH
        ORGANIZATION IS INDEXED
        ACCESS MODE IS SEQUENTIAL
        RECORD KEY IS INC-KEY OF INC-REC
        FILE STATUS IS WS-INC-ST.

DATA DIVISION.
FILE SECTION.
FD TXN-FILE.
01 TXN-REC.
   COPY "BTXREC".
FD JST-FILE.
01 JST-REC.
   05 JST-ID PIC X(20).
   05 JST-STATE PIC X(01).
   05 JST-UPDATED PIC 9(14).
FD OB-FILE.
01 OB-REC.
   05 OB-OPID          PIC X(16).
   05 OB-OPKIND        PIC X(12).
   05 OB-OP            PIC X(14).
   05 OB-CHANNEL       PIC X(12).
   05 OB-E2E           PIC X(32).
   05 OB-MSGID         PIC X(32).
   05 OB-AMT           PIC S9(15)V99 COMP-3.
   05 OB-CUR           PIC X(03).
   05 OB-INTERNAL      PIC X(32).
   05 OB-STATE         PIC X(16).
   05 OB-RETRIES       PIC 9(03).
   05 OB-CERTID        PIC X(24).
   05 OB-SIG           PIC X(64).
   05 OB-SIM           PIC X(12).
   05 OB-OUTCOME       PIC X(12).
   05 OB-EXTREF        PIC X(32).
   05 OB-FP            PIC X(16).
   05 OB-ENV           PIC X(16).
   05 OB-REASON        PIC X(60).
   05 OB-OPER          PIC X(12).
   05 OB-CORR          PIC X(24).
   05 OB-CREATED       PIC 9(14).
   05 OB-SENT          PIC 9(14).
   05 OB-RESP          PIC 9(14).
FD MI-FILE.
01 MI-REC.
   05 MI-MSGID         PIC X(32).
   05 MI-VER           PIC X(05).
   05 MI-MSGNM         PIC X(20).
   05 MI-E2E           PIC X(32).
   05 MI-FP            PIC X(16).
   05 MI-ENV           PIC X(16).
   05 MI-CHANNEL       PIC X(12).
   05 MI-STATE         PIC X(12).
   05 MI-PIXID         PIC X(12).
   05 MI-TXNID         PIC X(12).
   05 MI-JRNID         PIC X(20).
   05 MI-AMT           PIC S9(15)V99 COMP-3.
   05 MI-CUR           PIC X(03).
   05 MI-CREATED       PIC 9(14).
   05 MI-UPDATED       PIC 9(14).
   05 MI-COUNT         PIC 9(03).
FD EXC-FILE.
01 EXC-REC.
   COPY "BRECE".
FD INC-FILE.
01 INC-REC.
   05 INC-KEY          PIC X(24).
   05 INC-SUMMARY      PIC X(60).
   05 INC-SEV          PIC X(06).
   05 INC-STATE        PIC X(08).

WORKING-STORAGE SECTION.
01 WS-TXN-PATH PIC X(200).
01 WS-JST-PATH PIC X(200).
01 WS-OB-PATH PIC X(200).
01 WS-MI-PATH PIC X(200).
01 WS-EXC-PATH PIC X(200).
01 WS-INC-PATH PIC X(200).
01 WS-CHAIN-PATH PIC X(200).
01 WS-CMD PIC X(600).
01 WS-ARG PIC X(200).
01 WS-HOME PIC X(80).
01 WS-TXN-ST PIC X(02).
01 WS-JST-ST PIC X(02).
01 WS-OB-ST PIC X(02).
01 WS-MI-ST PIC X(02).
01 WS-EXC-ST PIC X(02).
01 WS-INC-ST PIC X(02).
01 WS-EOF PIC X(01).
01 WS-HITS PIC 9(05).

LINKAGE SECTION.
COPY "BKCOP".

PROCEDURE DIVISION USING BK-CO-PARMS.
    MOVE "00" TO CO-RC
    MOVE 0 TO WS-HITS
    ACCEPT WS-HOME FROM ENVIRONMENT "BANK_HOME"
    MOVE CO-ID TO WS-ARG
    PERFORM BUILD-PATHS
    PERFORM SCAN-TXN
    PERFORM SCAN-JST
    PERFORM SCAN-OB
    PERFORM SCAN-MI
    PERFORM SCAN-EXC
    PERFORM SCAN-INC
    MOVE "/var/journal/journal.log" TO WS-CHAIN-PATH
    PERFORM GREP-CHAIN
    MOVE "/var/journal/postings.log" TO WS-CHAIN-PATH
    PERFORM GREP-CHAIN
    MOVE "/var/audit/audit.log" TO WS-CHAIN-PATH
    PERFORM GREP-CHAIN
    MOVE "/var/journal/events.log" TO WS-CHAIN-PATH
    PERFORM GREP-CHAIN
    MOVE WS-HITS TO CO-COUNT
    MOVE "CORRELATION COMPLETE" TO CO-MSG
    GOBACK.

BUILD-PATHS.
    STRING FUNCTION TRIM(WS-HOME) "/var/data/txn.idx"
        DELIMITED SIZE INTO WS-TXN-PATH
    END-STRING
    STRING FUNCTION TRIM(WS-HOME) "/var/data/jrst.idx"
        DELIMITED SIZE INTO WS-JST-PATH
    END-STRING
    STRING FUNCTION TRIM(WS-HOME) "/var/data/bndout.idx"
        DELIMITED SIZE INTO WS-OB-PATH
    END-STRING
    STRING FUNCTION TRIM(WS-HOME) "/var/data/bndmsgid.idx"
        DELIMITED SIZE INTO WS-MI-PATH
    END-STRING
    STRING FUNCTION TRIM(WS-HOME) "/var/data/recexc.idx"
        DELIMITED SIZE INTO WS-EXC-PATH
    END-STRING
    STRING FUNCTION TRIM(WS-HOME) "/var/data/opsinc.idx"
        DELIMITED SIZE INTO WS-INC-PATH
    END-STRING.

SCAN-TXN.
    MOVE "N" TO WS-EOF
    OPEN INPUT TXN-FILE
    IF WS-TXN-ST = "00"
        PERFORM UNTIL WS-EOF = "Y"
            READ TXN-FILE
                AT END MOVE "Y" TO WS-EOF
                NOT AT END
                    IF FUNCTION TRIM(TXN-ID OF TXN-REC) =
                         FUNCTION TRIM(WS-ARG) OR
                       FUNCTION TRIM(TXN-JRN-ID OF TXN-REC) =
                         FUNCTION TRIM(WS-ARG) OR
                       FUNCTION TRIM(TXN-CORR OF TXN-REC) =
                         FUNCTION TRIM(WS-ARG) OR
                       FUNCTION TRIM(TXN-REQUEST OF TXN-REC) =
                         FUNCTION TRIM(WS-ARG) OR
                       FUNCTION TRIM(TXN-REF OF TXN-REC) =
                         FUNCTION TRIM(WS-ARG)
                        ADD 1 TO WS-HITS
                        DISPLAY "CO|TXN|"
                            FUNCTION TRIM(TXN-ID OF TXN-REC) "|"
                            TXN-STATUS OF TXN-REC "|"
                            FUNCTION TRIM(TXN-JRN-ID OF TXN-REC)
                    END-IF
            END-READ
        END-PERFORM
    END-IF
    CLOSE TXN-FILE.

SCAN-JST.
    MOVE "N" TO WS-EOF
    OPEN INPUT JST-FILE
    IF WS-JST-ST = "00"
        PERFORM UNTIL WS-EOF = "Y"
            READ JST-FILE
                AT END MOVE "Y" TO WS-EOF
                NOT AT END
                    IF FUNCTION TRIM(JST-ID OF JST-REC) =
                         FUNCTION TRIM(WS-ARG)
                        ADD 1 TO WS-HITS
                        DISPLAY "CO|JST|"
                            FUNCTION TRIM(JST-ID OF JST-REC) "|"
                            JST-STATE OF JST-REC
                    END-IF
            END-READ
        END-PERFORM
    END-IF
    CLOSE JST-FILE.

SCAN-OB.
    MOVE "N" TO WS-EOF
    OPEN INPUT OB-FILE
    IF WS-OB-ST = "00"
        PERFORM UNTIL WS-EOF = "Y"
            READ OB-FILE
                AT END MOVE "Y" TO WS-EOF
                NOT AT END
                    IF FUNCTION TRIM(OB-OPID OF OB-REC) =
                         FUNCTION TRIM(WS-ARG) OR
                       FUNCTION TRIM(OB-E2E OF OB-REC) =
                         FUNCTION TRIM(WS-ARG) OR
                       FUNCTION TRIM(OB-MSGID OF OB-REC) =
                         FUNCTION TRIM(WS-ARG) OR
                       FUNCTION TRIM(OB-INTERNAL OF OB-REC) =
                         FUNCTION TRIM(WS-ARG)
                        ADD 1 TO WS-HITS
                        DISPLAY "CO|OUTB|"
                            FUNCTION TRIM(OB-OPID OF OB-REC) "|"
                            FUNCTION TRIM(OB-STATE OF OB-REC)
                    END-IF
            END-READ
        END-PERFORM
    END-IF
    CLOSE OB-FILE.

SCAN-MI.
    MOVE "N" TO WS-EOF
    OPEN INPUT MI-FILE
    IF WS-MI-ST = "00"
        PERFORM UNTIL WS-EOF = "Y"
            READ MI-FILE
                AT END MOVE "Y" TO WS-EOF
                NOT AT END
                    IF FUNCTION TRIM(MI-MSGID OF MI-REC) =
                         FUNCTION TRIM(WS-ARG) OR
                       FUNCTION TRIM(MI-E2E OF MI-REC) =
                         FUNCTION TRIM(WS-ARG) OR
                       FUNCTION TRIM(MI-TXNID OF MI-REC) =
                         FUNCTION TRIM(WS-ARG) OR
                       FUNCTION TRIM(MI-JRNID OF MI-REC) =
                         FUNCTION TRIM(WS-ARG)
                        ADD 1 TO WS-HITS
                        DISPLAY "CO|MSGID|"
                            FUNCTION TRIM(MI-MSGID OF MI-REC) "|"
                            FUNCTION TRIM(MI-STATE OF MI-REC)
                    END-IF
            END-READ
        END-PERFORM
    END-IF
    CLOSE MI-FILE.

SCAN-EXC.
    MOVE "N" TO WS-EOF
    OPEN INPUT EXC-FILE
    IF WS-EXC-ST = "00"
        PERFORM UNTIL WS-EOF = "Y"
            READ EXC-FILE
                AT END MOVE "Y" TO WS-EOF
                NOT AT END
                    IF FUNCTION TRIM(EXC-KEY OF EXC-REC) =
                         FUNCTION TRIM(WS-ARG) OR
                       FUNCTION TRIM(EXC-SRC-REF OF EXC-REC) =
                         FUNCTION TRIM(WS-ARG) OR
                       FUNCTION TRIM(EXC-INT-REF OF EXC-REC) =
                         FUNCTION TRIM(WS-ARG) OR
                       FUNCTION TRIM(EXC-TXN-REF OF EXC-REC) =
                         FUNCTION TRIM(WS-ARG)
                        ADD 1 TO WS-HITS
                        DISPLAY "CO|EXC|" FUNCTION TRIM(EXC-ID
                            OF EXC-REC) "|" FUNCTION TRIM(EXC-CODE
                            OF EXC-REC) "|"
                            FUNCTION TRIM(EXC-STATUS OF EXC-REC)
                    END-IF
            END-READ
        END-PERFORM
    END-IF
    CLOSE EXC-FILE.

SCAN-INC.
    MOVE "N" TO WS-EOF
    OPEN INPUT INC-FILE
    IF WS-INC-ST = "00"
        PERFORM UNTIL WS-EOF = "Y"
            READ INC-FILE
                AT END MOVE "Y" TO WS-EOF
                NOT AT END
                    IF FUNCTION TRIM(INC-KEY OF INC-REC) =
                         FUNCTION TRIM(WS-ARG)
                        ADD 1 TO WS-HITS
                        DISPLAY "CO|INC|" FUNCTION TRIM(INC-KEY
                            OF INC-REC) "|"
                            FUNCTION TRIM(INC-STATE OF INC-REC)
                    END-IF
            END-READ
        END-PERFORM
    END-IF
    CLOSE INC-FILE.

GREP-CHAIN.
    MOVE SPACES TO WS-CMD
    STRING "grep -h " DELIMITED SIZE "'" DELIMITED SIZE
        WS-ARG DELIMITED SIZE "' " DELIMITED SIZE
        FUNCTION TRIM(WS-HOME) DELIMITED SIZE
        WS-CHAIN-PATH DELIMITED SIZE " 2>/dev/null"
        DELIMITED SIZE INTO WS-CMD
    END-STRING
    CALL "SYSTEM" USING WS-CMD
    IF RETURN-CODE = 0
        ADD 1 TO WS-HITS
    END-IF.
