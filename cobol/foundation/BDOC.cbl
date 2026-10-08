IDENTIFICATION DIVISION.
PROGRAM-ID. BDOC.

*> Document identifier boundary.
*>
*> A CNPJ is an identifier, never a monetary or arithmetic quantity.
*> The Receita Federal started issuing alphanumeric CNPJ on 2026-07-31
*> and BCB information systems must treat CNPJ as a canonical string.
*> This module is the single place that decides how document strings
*> are canonicalized and validated:
*>
*>   - legacy all-numeric 14-position CNPJ: canonical digits, official
*>     mod-11 check digits verified;
*>   - alphanumeric CNPJ (positions 1-12 may contain A-Z; positions
*>     13-14 remain numeric verification digits): verified with the
*>     official Receita Federal alphanumeric procedure (character
*>     value = ASCII code minus 48, so A=17 ... Z=42 while digits
*>     keep their face value; standard right-to-left 2..9 cycling
*>     weights, remainder < 2 -> 0 else 11 - remainder).  Both DV
*>     passes run over the same unified routine: NUMVAL for a digit
*>     and ASCII-minus-48 coincide, so legacy numeric verification
*>     is bit-for-bit unchanged.
*>
*> This is mathematical validation only: it proves the identifier
*> conforms to the official structure and its verification digits are
*> correct.  It does NOT prove the CNPJ is registered at the Receita
*> Federal (no RFB/Serpro lookup exists here, by design).
*>
*> Validation outcomes (BD-STATE after VALIDATE, rc "00"):
*>   numeric + valid DV          -> VERIFIED
*>   alphanumeric + valid DV     -> VERIFIED
*>   DV mismatch                 -> rc 20 INVALID CNPJ CHECK DIGIT
*>   invalid structure/chars     -> rc 20 INVALID ...
*>   (the historical "UNVERIFIED" state is retired: letters are no
*>   longer a reason to skip verification)
*>
*> Canonical form: upper case, separators . , / - (and spaces)
*> removed; input is rejected if any other character survives
*> canonicalization; CNPJ length is exactly 14 positions and the two
*> DV positions must be digits.  The identifier is never truncated,
*> never numerically converted as a whole, and the same 14-character
*> canonical string is what every consumer persists, hashes and
*> compares.  Rejected outright: repeated-character identifiers,
*> symbols, accented or non-ASCII characters.

ENVIRONMENT DIVISION.
DATA DIVISION.
WORKING-STORAGE SECTION.
01 WS-RAW          PIC X(60).
01 WS-C            PIC X(01).
01 WS-I            PIC 9(03).
01 WS-N            PIC 9(03).
01 WS-HAS-ALPHA    PIC X(01).
01 WS-HAS-NUM      PIC X(01).
01 WS-LEN          PIC 9(03).
01 WS-INLEN        PIC 9(03).
01 WS-ALL-SAME     PIC X(01).
01 WS-DIGITS       PIC 9(03).
01 WS-I2           PIC 9(03).
01 WS-W            PIC 9(02).
01 WS-ACCUM        PIC 9(07).
01 WS-PROD         PIC 9(06).
01 WS-REM          PIC 9(02).
01 WS-DV           PIC 9(02).
01 WS-CHAR-VAL     PIC 9(02).

LINKAGE SECTION.
COPY "BDOCP".

PROCEDURE DIVISION USING BK-DOC-PARMS.
    MOVE "00" TO BD-RC
    MOVE SPACES TO BD-MSG BD-CANON
    MOVE "NUMERIC" TO BD-CLASS
    MOVE SPACES TO BD-STATE
    EVALUATE FUNCTION TRIM(BD-OP)
        WHEN "VALIDATE" PERFORM DO-VALIDATE
        WHEN "CANON" PERFORM DO-CANON
        WHEN OTHER
            MOVE "99" TO BD-RC
            MOVE "UNKNOWN DOC OP" TO BD-MSG
    END-EVALUATE
    GOBACK.

DO-CANON.
    PERFORM CANONICALIZE
    IF BD-RC NOT = "00"
        GOBACK
    END-IF
    PERFORM CLASSIFY
    MOVE "CANONICAL" TO BD-STATE.

DO-VALIDATE.
    PERFORM CANONICALIZE
    IF BD-RC NOT = "00"
        GOBACK
    END-IF
    PERFORM CLASSIFY
    EVALUATE FUNCTION TRIM(BD-TYPE)
        WHEN "CNPJ" PERFORM CHECK-CNPJ
        WHEN OTHER
            MOVE "99" TO BD-RC
            MOVE "UNKNOWN DOC TYPE" TO BD-MSG
    END-EVALUATE.

CANONICALIZE.
    MOVE BD-IN TO WS-RAW
    MOVE FUNCTION LENGTH(FUNCTION TRIM(WS-RAW)) TO WS-INLEN
    IF WS-RAW = SPACES
        MOVE "20" TO BD-RC
        MOVE "DOCUMENT EMPTY" TO BD-MSG
        GOBACK
    END-IF
    MOVE 0 TO WS-N
    PERFORM VARYING WS-I FROM 1 BY 1
        UNTIL WS-I > WS-INLEN
        MOVE WS-RAW(WS-I:1) TO WS-C
        EVALUATE TRUE
            WHEN WS-C = " " OR WS-C = "." OR WS-C = ","
            WHEN WS-C = "/" OR WS-C = "-"
                CONTINUE
            WHEN WS-C >= "a" AND WS-C <= "z"
                MOVE FUNCTION UPPER-CASE(WS-C) TO WS-C
                ADD 1 TO WS-N
                MOVE WS-C TO BD-CANON(WS-N:1)
            WHEN WS-C >= "0" AND WS-C <= "9"
                ADD 1 TO WS-N
                MOVE WS-C TO BD-CANON(WS-N:1)
            WHEN WS-C >= "A" AND WS-C <= "Z"
                ADD 1 TO WS-N
                MOVE WS-C TO BD-CANON(WS-N:1)
            WHEN OTHER
                MOVE "20" TO BD-RC
                MOVE "INVALID DOCUMENT CHARACTERS" TO BD-MSG
                GOBACK
        END-EVALUATE
    END-PERFORM
    IF WS-N = 0
        MOVE "20" TO BD-RC
        MOVE "DOCUMENT EMPTY" TO BD-MSG
        GOBACK
    END-IF
    IF WS-N > 60
        MOVE "20" TO BD-RC
        MOVE "DOCUMENT TOO LONG" TO BD-MSG
        GOBACK
    END-IF.

CLASSIFY.
    MOVE "N" TO WS-HAS-ALPHA WS-HAS-NUM
    MOVE FUNCTION LENGTH(FUNCTION TRIM(BD-CANON)) TO WS-LEN
    PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > WS-LEN
        IF BD-CANON(WS-I:1) >= "A" AND BD-CANON(WS-I:1) <= "Z"
            MOVE "Y" TO WS-HAS-ALPHA
        ELSE
            MOVE "Y" TO WS-HAS-NUM
        END-IF
    END-PERFORM
    IF WS-HAS-ALPHA = "Y"
        MOVE "ALPHANUMERIC" TO BD-CLASS
    ELSE
        MOVE "NUMERIC" TO BD-CLASS
    END-IF.

CHECK-CNPJ.
    IF WS-LEN NOT = 14
        MOVE "20" TO BD-RC
        MOVE "INVALID CNPJ LENGTH" TO BD-MSG
        GOBACK
    END-IF
    PERFORM CHECK-REPEATED
    IF BD-RC NOT = "00"
        GOBACK
    END-IF
    IF BD-CANON(13:1) < "0" OR BD-CANON(13:1) > "9"
        MOVE "20" TO BD-RC
        MOVE "CNPJ DV POSITIONS MUST BE NUMERIC" TO BD-MSG
        GOBACK
    END-IF
    IF BD-CANON(14:1) < "0" OR BD-CANON(14:1) > "9"
        MOVE "20" TO BD-RC
        MOVE "CNPJ DV POSITIONS MUST BE NUMERIC" TO BD-MSG
        GOBACK
    END-IF
    MOVE 12 TO WS-DIGITS
    PERFORM CNPJ-DIGIT
    IF WS-DV NOT = FUNCTION NUMVAL(BD-CANON(13:1))
        MOVE "20" TO BD-RC
        MOVE "INVALID CNPJ CHECK DIGIT" TO BD-MSG
        GOBACK
    END-IF
    MOVE 13 TO WS-DIGITS
    PERFORM CNPJ-DIGIT
    IF WS-DV NOT = FUNCTION NUMVAL(BD-CANON(14:1))
        MOVE "20" TO BD-RC
        MOVE "INVALID CNPJ CHECK DIGIT" TO BD-MSG
        GOBACK
    END-IF
    MOVE "VERIFIED" TO BD-STATE.

CNPJ-DIGIT.
    MOVE 0 TO WS-ACCUM WS-W
    PERFORM VARYING WS-I FROM WS-DIGITS BY -1 UNTIL WS-I < 1
        IF WS-W = 0 OR WS-W = 9
            MOVE 2 TO WS-W
        ELSE
            ADD 1 TO WS-W
        END-IF
        MOVE BD-CANON(WS-I:1) TO WS-C
        PERFORM CNPJ-CHAR-VALUE
        MULTIPLY WS-CHAR-VAL BY WS-W GIVING WS-PROD
        ADD WS-PROD TO WS-ACCUM
    END-PERFORM
    COMPUTE WS-REM = FUNCTION MOD(WS-ACCUM 11)
    IF WS-REM < 2
        MOVE 0 TO WS-DV
    ELSE
        COMPUTE WS-DV = 11 - WS-REM
    END-IF.

CNPJ-CHAR-VALUE.
    *> Official alphanumeric CNPJ character values: ASCII code minus
    *> 48.  Digits keep their face value (NUMVAL coincides with
    *> ASCII-48); A-Z map to 17-42.  Table-based so EBCDIC hosts
    *> compute the identical official values.
    IF WS-C >= "0" AND WS-C <= "9"
        MOVE FUNCTION NUMVAL(WS-C) TO WS-CHAR-VAL
    ELSE
        EVALUATE WS-C
            WHEN "A" MOVE 17 TO WS-CHAR-VAL
            WHEN "B" MOVE 18 TO WS-CHAR-VAL
            WHEN "C" MOVE 19 TO WS-CHAR-VAL
            WHEN "D" MOVE 20 TO WS-CHAR-VAL
            WHEN "E" MOVE 21 TO WS-CHAR-VAL
            WHEN "F" MOVE 22 TO WS-CHAR-VAL
            WHEN "G" MOVE 23 TO WS-CHAR-VAL
            WHEN "H" MOVE 24 TO WS-CHAR-VAL
            WHEN "I" MOVE 25 TO WS-CHAR-VAL
            WHEN "J" MOVE 26 TO WS-CHAR-VAL
            WHEN "K" MOVE 27 TO WS-CHAR-VAL
            WHEN "L" MOVE 28 TO WS-CHAR-VAL
            WHEN "M" MOVE 29 TO WS-CHAR-VAL
            WHEN "N" MOVE 30 TO WS-CHAR-VAL
            WHEN "O" MOVE 31 TO WS-CHAR-VAL
            WHEN "P" MOVE 32 TO WS-CHAR-VAL
            WHEN "Q" MOVE 33 TO WS-CHAR-VAL
            WHEN "R" MOVE 34 TO WS-CHAR-VAL
            WHEN "S" MOVE 35 TO WS-CHAR-VAL
            WHEN "T" MOVE 36 TO WS-CHAR-VAL
            WHEN "U" MOVE 37 TO WS-CHAR-VAL
            WHEN "V" MOVE 38 TO WS-CHAR-VAL
            WHEN "W" MOVE 39 TO WS-CHAR-VAL
            WHEN "X" MOVE 40 TO WS-CHAR-VAL
            WHEN "Y" MOVE 41 TO WS-CHAR-VAL
            WHEN "Z" MOVE 42 TO WS-CHAR-VAL
            WHEN OTHER MOVE 0 TO WS-CHAR-VAL
        END-EVALUATE
    END-IF.

CHECK-REPEATED.
    IF BD-CLASS = "ALPHANUMERIC"
        PERFORM CHECK-REPEATED-ALNUM
        EXIT PARAGRAPH
    END-IF
    MOVE "Y" TO WS-ALL-SAME
    PERFORM VARYING WS-I FROM 2 BY 1 UNTIL WS-I > WS-LEN
        IF BD-CANON(WS-I:1) NOT = BD-CANON(1:1)
            MOVE "N" TO WS-ALL-SAME
        END-IF
    END-PERFORM
    IF WS-ALL-SAME = "Y"
        MOVE "20" TO BD-RC
        MOVE "INVALID REPEATED DIGITS" TO BD-MSG
    END-IF.

CHECK-REPEATED-ALNUM.
    MOVE "Y" TO WS-ALL-SAME
    PERFORM VARYING WS-I FROM 2 BY 1 UNTIL WS-I > WS-LEN
        IF BD-CANON(WS-I:1) NOT = BD-CANON(1:1)
            MOVE "N" TO WS-ALL-SAME
        END-IF
    END-PERFORM
    IF WS-ALL-SAME = "Y"
        MOVE "20" TO BD-RC
        MOVE "INVALID REPEATED CHARACTERS" TO BD-MSG
    END-IF.
