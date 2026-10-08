IDENTIFICATION DIVISION.
PROGRAM-ID. BPXSTX.

*> SPI Split Tax contract boundary (BPXSTX).
*>
*> This module is the only place in KofBank that knows the official SPI
*> Split Tax message structure.  Direction of every operation:
*>
*>   external SPI message  ->  this boundary  ->  Pix Split domain
*>
*> It never calculates tax.  Tax block values (RefNb docFiscal, the
*> CBSSPLIT/IBSSPLIT records and their TtlAmt amounts) are taken from
*> the authorized upstream exactly as declared; the boundary validates
*> the official contract and maps the block onto the pre-existing
*> allocation tax metadata (TAXTYPE/TAXCAT/DOCREF) of the split engine.
*> Financial effects remain exclusively in BPXVAL/BPXPASTO/BTXNVAL/
*> BTXNPOST: this module posts nothing on its own and drives pacs.008
*> ingestion through the existing payment processor (BPXPR), reusing
*> the whole transaction lifecycle, idempotency and replay machinery.
*>
*> Contract source of truth (inspected 2026-10, production cycle SPI
*> 5.13): BCB "Definições detalhadas das mensagens do Catálogo de
*> Mensagens do SPI" spi.5.13.2.zip (published 2026-10-02 per the
*> change log of Catálogo de Serviços do SFN Volume VI v5.13; 5.13.1
*> was superseded and no longer published), plus spi.5.12.1.zip as the
*> 5.12 baseline for the version boundary.
*>
*> Official Tax structure (byte-identical between 5.12.1 and 5.13.2):
*>   pacs.008 (spi.1.15/1.16) CdtTrfTxInf/Tax TaxInformation8:
*>       RefNb [1..1] DocFiscalType [a-zA-Z0-9]{1,50}
*>       Rcrd  [2..2] { Tp=CBSSPLIT|IBSSPLIT, Ctgy=INF,
*>                      TaxAmt/TtlAmt ActiveOrHistoricCurrencyAndAmount }
*>   camt.054 (spi.1.15/1.16) TxDtls/Tax TaxInformation8, RefNb [0..1]:
*>       notification repeating the declared Tax block of the
*>       referenced transaction; no new semantics, no second record.
*>   pain.013 (spi.2.2, unchanged 5.12.1 -> 5.13.2)
*>       CdtTrfTx/Tax TaxInformation10: RefNb [0..1]; Rcrd [2..4];
*>       per tax type INF mandatory, COR optional; Ctgy {INF, COR}.
*>   Amounts: Ccy required "BRL", max 18 numeric characters, exactly
*>   two decimals separated by a point, values >= 0.
*>
*> Official Brazil fill rules (XLSX v5.13.2):
*>   pacs.008: block only when payer AND receiver are Pessoa Juridica
*>     (14 CNPJ positions) and formaDeIniciacao is QRES/APES/MANU/DICT.
*>     QRDN/APDN/AUTO belong to the receiver-side pain.013 flow; INIC
*>     is out of Split scope.  Exactly one CBSSPLIT and one IBSSPLIT
*>     record, both Ctgy=INF.  Sum of TtlAmt >= 0 and must not exceed
*>     IntrBkSttlmAmt.
*>   pain.013: block allowed when cpfCnpjDevedor (if present) or else
*>     cpfCnpjUsuarioPagador is PJ.  Sum rule per tax type uses COR
*>     when present, otherwise INF; total must not exceed InstdAmt.
*>     No posting happens for pain.013 at this boundary.
*>
*> Official error separation (Volume VI + message XSDs):
*>   XML/XSD syntax failures     -> ADMI.002 class (XT-CODESRC=ADMI)
*>   tax info invalid/incomplete -> pacs.002 RR06 TaxInformationInvalid
*>   tax sum above transaction   -> pacs.002 AM23 (official SPI BR
*>                                   description of tax-sum overflow)
*>   allocation/gross mismatch   -> existing domain rejection
*>   financial rejection         -> BTXNVAL/BTXNPOST through BPXPR
*>   pain.014 5.13.x (v2.4) has NO tax-specific code (AM23/RR06/AG12/
*>   DS27 were removed in 5.13.1 "aderência ao modelo de validação da
*>   ICOM/SPI"); TX-RESPONSE validates against the version-specific
*>   official enumeration, so 5.12 and 5.13 differ exactly where the
*>   specification differs and are otherwise one mapping.
*>
*> Versioning: XT-VER (5.12/5.13) selects the official message-version
*> mapping and the version-specific pain.014 error domain.  Deployed
*> catalog version is configuration (etc/pix.cfg spi-message-version),
*> never a CURRENT-DATE comparison inside financial logic.

DATA DIVISION.
WORKING-STORAGE SECTION.
COPY "BDOCP".
COPY "BKEVTP".
COPY "BPXPP".
COPY "BPXCFG".
01 WS-LEN          PIC 9(03).
01 WS-I            PIC 9(03).
01 WS-CH           PIC X(01).
01 WS-K            PIC 9(03).
01 WS-MSG-KEEP     PIC X(80).
01 WS-J            PIC 9(03).
01 WS-DOTPOS       PIC 9(03).
01 WS-DECPOS       PIC 9(03).
01 WS-CENTS        PIC S9(18) COMP-3.
01 WS-INT-PART     PIC 9(16).
01 WS-DEC-PART     PIC 9(02).
01 WS-AMT-SRC      PIC X(18).
01 WS-AMT-OUT      PIC S9(15)V99 COMP-3.
01 WS-BAD          PIC X(01).
01 WS-CHKSTR       PIC X(64).
01 WS-CHKLEN       PIC 9(02).
01 WS-REASON       PIC X(60).
01 WS-DOCIN        PIC X(20).
01 WS-CANON-PJ     PIC X(14).
01 WS-EFF-CBS      PIC S9(15)V99 COMP-3.
01 WS-EFF-IBS      PIC S9(15)V99 COMP-3.
01 WS-CBS-FOUND    PIC X(01).
01 WS-IBS-FOUND    PIC X(01).
01 WS-MAIN-AMT     PIC S9(15)V99 COMP-3.
01 WS-ENV-TXT      PIC X(2000).
01 WS-TMP          PIC X(20).

LINKAGE SECTION.
COPY "BPTXP".

PROCEDURE DIVISION USING BK-SPITAX-PARMS.
    MOVE "00" TO XT-RC
    MOVE SPACES TO XT-CODESRC
    MOVE "N" TO XT-SYNTAX
    MOVE 0 TO XT-GROSS XT-TAXSUM
    EVALUATE FUNCTION TRIM(XT-OP)
        WHEN "TX-VALIDATE" PERFORM DO-VALIDATE
        WHEN "TX-BUILD" PERFORM DO-BUILD
        WHEN "TX-INGEST" PERFORM DO-INGEST
        WHEN "TX-RESPONSE" PERFORM DO-RESPONSE
        WHEN "TX-GET" PERFORM DO-TXGET
        WHEN "TX-GETE2E" PERFORM DO-TXGETE2E
        WHEN "TX-LIST" PERFORM DO-TXLIST
        WHEN OTHER
            MOVE "99" TO XT-RC
            MOVE "UNKNOWN SPITAX OP" TO XT-MSG
    END-EVALUATE
    GOBACK.

*>  ================================================================== *
*> Contract validation of one parsed message object.
*>  ================================================================== *
DO-VALIDATE.
    MOVE SPACES TO XT-MSG XT-STATUS XT-CODE
    PERFORM CHECK-SYNTAX
    IF XT-RC NOT = "00"
        EXIT PARAGRAPH
    END-IF
    IF XT-HAS-TAX = "Y"
        PERFORM CHECK-TAX-CARDINALITY
        IF XT-RC NOT = "00"
            EXIT PARAGRAPH
        END-IF
        PERFORM CHECK-TAX-RECORDS
        IF XT-RC NOT = "00"
            EXIT PARAGRAPH
        END-IF
        PERFORM CHECK-TAX-GATE
        IF XT-RC NOT = "00"
            EXIT PARAGRAPH
        END-IF
        PERFORM CHECK-TAX-SUM
        IF XT-RC NOT = "00"
            EXIT PARAGRAPH
        END-IF
    END-IF
    MOVE "ACCEPTED" TO XT-STATUS
    MOVE "00" TO XT-RC
    MOVE "SPI TAX CONTRACT VALID" TO XT-MSG.
    EXIT PARAGRAPH.

*> ------------------------------------------------------------------ *
*> Syntax layer (XSD level, ADMI.002 class when reported upstream).
*> ------------------------------------------------------------------ *
CHECK-SYNTAX.
    IF XT-VER = SPACES
        PERFORM LOAD-DEFAULT-VERSION
    END-IF
    EVALUATE FUNCTION TRIM(XT-MSGNM)
        WHEN "pacs.008" WHEN "pain.013" WHEN "camt.054"
            CONTINUE
        WHEN OTHER
            MOVE "UNKNOWN SPI MESSAGE NAME" TO WS-REASON
            PERFORM SYNTAX-FAIL
            EXIT PARAGRAPH
    END-EVALUATE
    PERFORM SET-MESSAGE-VERSION
    IF XT-RC NOT = "00"
        EXIT PARAGRAPH
    END-IF
    MOVE FUNCTION TRIM(XT-MSGR-ID) TO WS-CHKSTR
    MOVE FUNCTION LENGTH(FUNCTION TRIM(XT-MSGR-ID)) TO WS-CHKLEN
    IF WS-CHKLEN < 9 OR WS-CHKLEN > 32
        MOVE "MESSAGE ID LENGTH INVALID" TO WS-REASON
        PERFORM SYNTAX-FAIL
        EXIT PARAGRAPH
    END-IF
    PERFORM CHECK-ALNUM
    IF WS-BAD = "Y"
        MOVE "MESSAGE ID CHARACTER INVALID" TO WS-REASON
        PERFORM SYNTAX-FAIL
        EXIT PARAGRAPH
    END-IF
    PERFORM CHECK-CREATTM
    IF XT-RC NOT = "00"
        EXIT PARAGRAPH
    END-IF
    IF FUNCTION TRIM(XT-MSGNM) = "pacs.008.spi.1.15" OR
       FUNCTION TRIM(XT-MSGNM) = "pacs.008.spi.1.16"
        PERFORM CHECK-E2E
        IF XT-RC NOT = "00"
            EXIT PARAGRAPH
        END-IF
    END-IF
    IF FUNCTION TRIM(XT-CURRENCY) NOT = "BRL"
        MOVE "CURRENCY MUST BE BRL" TO WS-REASON
        PERFORM SYNTAX-FAIL
        EXIT PARAGRAPH
    END-IF
    MOVE XT-GROSS-STR TO WS-AMT-SRC
    PERFORM AMOUNT-PARSE
    IF XT-RC NOT = "00"
        EXIT PARAGRAPH
    END-IF
    MOVE WS-AMT-OUT TO XT-GROSS
    IF XT-GROSS <= 0
        MOVE "GROSS AMOUNT MUST BE POSITIVE" TO WS-REASON
        PERFORM SYNTAX-FAIL
        EXIT PARAGRAPH
    END-IF
    IF XT-HAS-TAX = "Y"
        PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > XT-RCNT
            IF FUNCTION TRIM(XT-R-CCY(WS-I)) NOT = "BRL"
                MOVE "TAX CURRENCY MUST BE BRL" TO WS-REASON
                PERFORM SYNTAX-FAIL
                EXIT PERFORM
            END-IF
            MOVE XT-R-VSTR(WS-I) TO WS-AMT-SRC
            PERFORM AMOUNT-PARSE
            IF XT-RC NOT = "00"
                EXIT PERFORM
            END-IF
            MOVE WS-AMT-OUT TO XT-R-AMT(WS-I)
            IF XT-R-AMT(WS-I) < 0
                MOVE "TAX AMOUNT MUST NOT BE NEGATIVE"
                    TO WS-REASON
                PERFORM SYNTAX-FAIL
                EXIT PERFORM
            END-IF
        END-PERFORM
    END-IF.
    EXIT PARAGRAPH.

SET-MESSAGE-VERSION.
    EVALUATE FUNCTION TRIM(XT-VER)
        WHEN "5.12"
            MOVE "5.12" TO XT-VER
            EVALUATE FUNCTION TRIM(XT-MSGNM)
                WHEN "pacs.008"
                    MOVE "pacs.008.spi.1.15" TO XT-MSGNM
                WHEN "pain.013"
                    MOVE "pain.013.spi.2.2" TO XT-MSGNM
                WHEN "camt.054"
                    MOVE "camt.054.spi.1.15" TO XT-MSGNM
            END-EVALUATE
        WHEN "5.13"
            MOVE "5.13" TO XT-VER
            EVALUATE FUNCTION TRIM(XT-MSGNM)
                WHEN "pacs.008"
                    MOVE "pacs.008.spi.1.16" TO XT-MSGNM
                WHEN "pain.013"
                    MOVE "pain.013.spi.2.2" TO XT-MSGNM
                WHEN "camt.054"
                    MOVE "camt.054.spi.1.16" TO XT-MSGNM
            END-EVALUATE
        WHEN OTHER
            MOVE "UNSUPPORTED SPI CATALOG VERSION" TO WS-REASON
            PERFORM SYNTAX-FAIL
    END-EVALUATE.
    EXIT PARAGRAPH.

CHECK-CREATTM.
    MOVE FUNCTION TRIM(XT-CREATTM) TO WS-CHKSTR
    MOVE FUNCTION LENGTH(FUNCTION TRIM(XT-CREATTM)) TO WS-CHKLEN
    IF WS-CHKLEN < 20 OR WS-CHKLEN > 24
        MOVE "CREATION TIME INVALID" TO WS-REASON
        PERFORM SYNTAX-FAIL
        EXIT PARAGRAPH
    END-IF
    IF WS-CHKSTR(5:1) NOT = "-" OR WS-CHKSTR(8:1) NOT = "-" OR
       WS-CHKSTR(11:1) NOT = "T"
        MOVE "CREATION TIME INVALID" TO WS-REASON
        PERFORM SYNTAX-FAIL
        EXIT PARAGRAPH
    END-IF
    PERFORM CHECK-YEAR
    IF WS-BAD = "Y"
        MOVE "CREATION TIME INVALID" TO WS-REASON
        PERFORM SYNTAX-FAIL
        EXIT PARAGRAPH
    END-IF
    PERFORM CHECK-MONTH
    IF WS-BAD = "Y"
        MOVE "CREATION TIME INVALID" TO WS-REASON
        PERFORM SYNTAX-FAIL
        EXIT PARAGRAPH
    END-IF
    PERFORM CHECK-DAY
    IF WS-BAD = "Y"
        MOVE "CREATION TIME INVALID" TO WS-REASON
        PERFORM SYNTAX-FAIL
        EXIT PARAGRAPH
    END-IF
    PERFORM CHECK-HOUR
    IF WS-BAD = "Y"
        MOVE "CREATION TIME INVALID" TO WS-REASON
        PERFORM SYNTAX-FAIL
        EXIT PARAGRAPH
    END-IF
    PERFORM CHECK-MINUTE
    IF WS-BAD = "Y"
        MOVE "CREATION TIME INVALID" TO WS-REASON
        PERFORM SYNTAX-FAIL
        EXIT PARAGRAPH
    END-IF
    PERFORM VARYING WS-I FROM 18 BY 1 UNTIL WS-I > WS-CHKLEN
        MOVE WS-CHKSTR(WS-I:1) TO WS-CH
        IF WS-CH NOT = ":" AND WS-CH NOT = "." AND
           WS-CH NOT = "Z" AND WS-CH < "0" AND WS-CH > "9"
            MOVE "CREATION TIME INVALID" TO WS-REASON
            PERFORM SYNTAX-FAIL
            EXIT PARAGRAPH
        END-IF
    END-PERFORM
    MOVE "00" TO XT-RC.
    EXIT PARAGRAPH.

CHECK-YEAR.
    MOVE "N" TO WS-BAD
    IF WS-CHKSTR(1:1) < "1" OR WS-CHKSTR(1:1) > "9"
        MOVE "Y" TO WS-BAD
    END-IF.
    EXIT PARAGRAPH.
CHECK-MONTH.
    MOVE "N" TO WS-BAD
    IF WS-CHKSTR(6:1) NOT = "0" OR WS-CHKSTR(7:1) < "1" OR
       WS-CHKSTR(7:1) > "9"
        IF WS-CHKSTR(6:2) NOT = "10" AND
           WS-CHKSTR(6:2) NOT = "11" AND
           WS-CHKSTR(6:2) NOT = "12"
            MOVE "Y" TO WS-BAD
        END-IF
    END-IF.
    EXIT PARAGRAPH.
CHECK-DAY.
    MOVE "N" TO WS-BAD
    IF WS-CHKSTR(9:1) > "3"
        MOVE "Y" TO WS-BAD
    END-IF
    IF WS-CHKSTR(9:1) = "3" AND WS-CHKSTR(10:1) > "1"
        MOVE "Y" TO WS-BAD
    END-IF
    IF WS-CHKSTR(9:2) = "00"
        MOVE "Y" TO WS-BAD
    END-IF.
    EXIT PARAGRAPH.
CHECK-HOUR.
    MOVE "N" TO WS-BAD
    IF WS-CHKSTR(12:1) > "2"
        MOVE "Y" TO WS-BAD
    END-IF
    IF WS-CHKSTR(12:1) = "2" AND WS-CHKSTR(13:1) > "3"
        MOVE "Y" TO WS-BAD
    END-IF.
    EXIT PARAGRAPH.
CHECK-MINUTE.
    MOVE "N" TO WS-BAD
    IF WS-CHKSTR(15:1) > "5"
        MOVE "Y" TO WS-BAD
    END-IF.
    EXIT PARAGRAPH.

CHECK-E2E.
    MOVE FUNCTION TRIM(XT-E2E-ID) TO WS-CHKSTR
    MOVE FUNCTION LENGTH(FUNCTION TRIM(XT-E2E-ID)) TO WS-CHKLEN
    IF WS-CHKLEN NOT = 32
        MOVE "END TO END ID LENGTH INVALID" TO WS-REASON
        PERFORM SYNTAX-FAIL
        EXIT PARAGRAPH
    END-IF
    IF WS-CHKSTR(1:1) NOT = "E"
        MOVE "END TO END ID MUST START WITH E" TO WS-REASON
        PERFORM SYNTAX-FAIL
        EXIT PARAGRAPH
    END-IF
    PERFORM CHECK-ALNUM
    IF WS-BAD = "Y"
        MOVE "END TO END ID CHARACTER INVALID" TO WS-REASON
        PERFORM SYNTAX-FAIL
        EXIT PARAGRAPH
    END-IF
    MOVE "00" TO XT-RC.
    EXIT PARAGRAPH.

CHECK-ALNUM.
    MOVE "N" TO WS-BAD
    PERFORM VARYING WS-K FROM 1 BY 1 UNTIL WS-K > WS-CHKLEN
        MOVE WS-CHKSTR(WS-K:1) TO WS-CH
        IF NOT ((WS-CH >= "0" AND WS-CH <= "9") OR
                (WS-CH >= "A" AND WS-CH <= "Z") OR
                (WS-CH >= "a" AND WS-CH <= "z"))
            MOVE "Y" TO WS-BAD
            EXIT PERFORM
        END-IF
    END-PERFORM.
    EXIT PARAGRAPH.

AMOUNT-PARSE.
    MOVE "00" TO XT-RC
    MOVE 0 TO WS-CENTS WS-AMT-OUT WS-DOTPOS
    MOVE FUNCTION TRIM(WS-AMT-SRC) TO WS-CHKSTR
    MOVE FUNCTION LENGTH(FUNCTION TRIM(WS-AMT-SRC)) TO WS-CHKLEN
    MOVE "N" TO WS-BAD
    IF WS-CHKLEN < 4 OR WS-CHKLEN > 18
        MOVE "AMOUNT LENGTH INVALID" TO WS-REASON
        PERFORM SYNTAX-FAIL
        EXIT PARAGRAPH
    END-IF
    PERFORM VARYING WS-K FROM 1 BY 1 UNTIL WS-K > WS-CHKLEN
        MOVE WS-CHKSTR(WS-K:1) TO WS-CH
        IF WS-CH = "."
            IF WS-DOTPOS > 0
                MOVE "Y" TO WS-BAD
            ELSE
                MOVE WS-K TO WS-DOTPOS
            END-IF
        ELSE
            IF WS-CH < "0" OR WS-CH > "9"
                MOVE "Y" TO WS-BAD
            END-IF
        END-IF
    END-PERFORM
    IF WS-BAD = "Y"
        MOVE "AMOUNT CHARACTER INVALID" TO WS-REASON
        PERFORM SYNTAX-FAIL
        EXIT PARAGRAPH
    END-IF
    IF WS-DOTPOS = 0
        MOVE "AMOUNT DECIMAL REQUIRED" TO WS-REASON
        PERFORM SYNTAX-FAIL
        EXIT PARAGRAPH
    END-IF
    COMPUTE WS-DECPOS = WS-CHKLEN - WS-DOTPOS
    IF WS-DECPOS NOT = 2
        MOVE "AMOUNT MUST HAVE TWO DECIMALS" TO WS-REASON
        PERFORM SYNTAX-FAIL
        EXIT PARAGRAPH
    END-IF
    IF WS-DOTPOS > 16
        MOVE "AMOUNT DIGITS EXCEED CONTRACT" TO WS-REASON
        PERFORM SYNTAX-FAIL
        EXIT PARAGRAPH
    END-IF
    COMPUTE WS-K = WS-DOTPOS - 1
    MOVE WS-CHKSTR(1:WS-K) TO WS-INT-PART
    COMPUTE WS-K = WS-DOTPOS + 1
    MOVE WS-CHKSTR(WS-K:2) TO WS-DEC-PART
    COMPUTE WS-AMT-OUT = WS-INT-PART * 100 + WS-DEC-PART
    DIVIDE 100 INTO WS-AMT-OUT
    MOVE "00" TO XT-RC.
    EXIT PARAGRAPH.

SYNTAX-FAIL.
    MOVE "Y" TO XT-SYNTAX
    MOVE "RJCT" TO XT-STATUS
    MOVE SPACES TO XT-CODE
    MOVE "ADMI" TO XT-CODESRC
    MOVE "20" TO XT-RC
    STRING "SPI TAX MESSAGE SYNTAX INVALID: " DELIMITED SIZE
        WS-REASON DELIMITED SIZE INTO XT-MSG
    END-STRING.
    EXIT PARAGRAPH.

TAX-FAIL-RR06.
    MOVE "N" TO XT-SYNTAX
    MOVE "REJECTED" TO XT-STATUS
    MOVE "RR06" TO XT-CODE
    MOVE "SPI" TO XT-CODESRC
    MOVE "20" TO XT-RC
    STRING "SPI TAX INFORMATION INVALID: " DELIMITED SIZE
        WS-REASON DELIMITED SIZE INTO XT-MSG
    END-STRING.
    EXIT PARAGRAPH.

*> ------------------------------------------------------------------ *
*> Tax data layer (official domain RR06 for missing/incomplete/
*> invalid tax information).
*> ------------------------------------------------------------------ *
CHECK-TAX-CARDINALITY.
    IF FUNCTION TRIM(XT-MSGNM) = "pacs.008.spi.1.15" OR
       FUNCTION TRIM(XT-MSGNM) = "pacs.008.spi.1.16"
        IF XT-REFNB = SPACES
            MOVE "REFNB DOCFISCAL REQUIRED IN PACS.008"
                TO WS-REASON
            PERFORM TAX-FAIL-RR06
            EXIT PARAGRAPH
        END-IF
    END-IF
    IF XT-REFNB NOT = SPACES
        MOVE FUNCTION TRIM(XT-REFNB) TO WS-CHKSTR
        MOVE FUNCTION LENGTH(FUNCTION TRIM(XT-REFNB))
            TO WS-CHKLEN
        IF WS-CHKLEN > 50
            MOVE "DOC FISCAL LENGTH EXCEEDS 50" TO WS-REASON
            PERFORM TAX-FAIL-RR06
            EXIT PARAGRAPH
        END-IF
        PERFORM CHECK-ALNUM
        IF WS-BAD = "Y"
            MOVE "DOC FISCAL SPECIAL CHARACTER FORBIDDEN"
                TO WS-REASON
            PERFORM TAX-FAIL-RR06
            EXIT PARAGRAPH
        END-IF
    END-IF
    MOVE "N" TO WS-BAD
    PERFORM VARYING WS-I FROM 2 BY 1 UNTIL WS-I > XT-RCNT
        PERFORM VARYING WS-J FROM 1 BY 1 UNTIL WS-J >= WS-I
            IF XT-R-TY(WS-J) = XT-R-TY(WS-I) AND
               XT-R-CT(WS-J) = XT-R-CT(WS-I)
                MOVE "Y" TO WS-BAD
                EXIT PERFORM
            END-IF
        END-PERFORM
        IF WS-BAD = "Y"
            EXIT PERFORM
        END-IF
    END-PERFORM
    IF WS-BAD = "Y"
        MOVE "DUPLICATE TAX RECORDS FOR SAME TYPE" TO WS-REASON
        PERFORM TAX-FAIL-RR06
        EXIT PARAGRAPH
    END-IF
    IF FUNCTION TRIM(XT-MSGNM) NOT = "pain.013.spi.2.2"
        MOVE "N" TO WS-CBS-FOUND WS-IBS-FOUND
        PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > XT-RCNT
            IF XT-R-TY(WS-I) = "CBSSPLIT"
                IF WS-CBS-FOUND = "Y"
                    MOVE "Y" TO WS-BAD
                END-IF
                MOVE "Y" TO WS-CBS-FOUND
            END-IF
            IF XT-R-TY(WS-I) = "IBSSPLIT"
                IF WS-IBS-FOUND = "Y"
                    MOVE "Y" TO WS-BAD
                END-IF
                MOVE "Y" TO WS-IBS-FOUND
            END-IF
        END-PERFORM
        IF WS-BAD = "Y"
            MOVE "DUPLICATE TAX TYPE RECORDS" TO WS-REASON
            PERFORM TAX-FAIL-RR06
            EXIT PARAGRAPH
        END-IF
    END-IF
    EVALUATE FUNCTION TRIM(XT-MSGNM)
        WHEN "pain.013.spi.2.2"
            IF XT-RCNT < 2 OR XT-RCNT > 4
                MOVE "PAIN.013 TAX RECORDS MUST BE 2 TO 4"
                    TO WS-REASON
                PERFORM TAX-FAIL-RR06
                EXIT PARAGRAPH
            END-IF
        WHEN OTHER
            IF XT-RCNT NOT = 2
                MOVE "PACS/CAMT TAX RECORDS MUST BE EXACTLY 2"
                    TO WS-REASON
                PERFORM TAX-FAIL-RR06
                EXIT PARAGRAPH
            END-IF
    END-EVALUATE
    MOVE "00" TO XT-RC.
    EXIT PARAGRAPH.

CHECK-TAX-RECORDS.
    MOVE "N" TO WS-CBS-FOUND WS-IBS-FOUND
    PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > XT-RCNT
        IF XT-R-TY(WS-I) NOT = "CBSSPLIT" AND
           XT-R-TY(WS-I) NOT = "IBSSPLIT"
            MOVE "TAX TYPE NOT IN OFFICIAL DOMAIN"
                TO WS-REASON
            PERFORM TAX-FAIL-RR06
            EXIT PERFORM
        END-IF
        IF XT-R-CT(WS-I) = "INF"
            CONTINUE
        ELSE
            IF XT-R-CT(WS-I) = "COR" AND
               FUNCTION TRIM(XT-MSGNM) = "pain.013.spi.2.2"
                CONTINUE
            ELSE
                MOVE "TAX CATEGORY NOT IN OFFICIAL DOMAIN"
                    TO WS-REASON
                PERFORM TAX-FAIL-RR06
                EXIT PERFORM
            END-IF
        END-IF
        IF XT-R-TY(WS-I) = "CBSSPLIT"
            MOVE "Y" TO WS-CBS-FOUND
        END-IF
        IF XT-R-TY(WS-I) = "IBSSPLIT"
            MOVE "Y" TO WS-IBS-FOUND
        END-IF
        IF FUNCTION TRIM(XT-MSGNM) NOT = "pain.013.spi.2.2"
            IF XT-R-CT(WS-I) NOT = "INF"
                MOVE "PACS/CAMT TAX RECORDS MUST BE CATEGORY INF"
                    TO WS-REASON
                PERFORM TAX-FAIL-RR06
                EXIT PERFORM
            END-IF
        END-IF
    END-PERFORM
    IF XT-RC NOT = "00"
        EXIT PARAGRAPH
    END-IF
    IF WS-CBS-FOUND NOT = "Y" OR WS-IBS-FOUND NOT = "Y"
        MOVE "CBSSPLIT AND IBSSPLIT RECORDS BOTH REQUIRED"
            TO WS-REASON
        PERFORM TAX-FAIL-RR06
        EXIT PARAGRAPH
    END-IF
    IF FUNCTION TRIM(XT-MSGNM) = "pain.013.spi.2.2"
        PERFORM CHECK-PAIN-CATEGORY-PAIRS
        IF XT-RC NOT = "00"
            EXIT PARAGRAPH
        END-IF
    END-IF
    MOVE "00" TO XT-RC.
    EXIT PARAGRAPH.

CHECK-PAIN-CATEGORY-PAIRS.
    PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > XT-RCNT
        IF XT-R-CT(WS-I) = "COR"
            MOVE "N" TO WS-BAD
            PERFORM VARYING WS-J FROM 1 BY 1
                UNTIL WS-J > XT-RCNT
                IF XT-R-TY(WS-J) = XT-R-TY(WS-I) AND
                   XT-R-CT(WS-J) = "INF"
                    MOVE "Y" TO WS-BAD
                END-IF
            END-PERFORM
            IF WS-BAD = "N"
                MOVE "COR RECORD REQUIRES INF RECORD OF SAME TYPE"
                    TO WS-REASON
                PERFORM TAX-FAIL-RR06
                EXIT PARAGRAPH
            END-IF
        END-IF
    END-PERFORM.
    EXIT PARAGRAPH.

CHECK-TAX-GATE.
    IF FUNCTION TRIM(XT-MSGNM) = "pacs.008.spi.1.15" OR
       FUNCTION TRIM(XT-MSGNM) = "pacs.008.spi.1.16"
        IF XT-PAYER-DOC = SPACES OR XT-RECV-DOC = SPACES
            MOVE "PJ DOCUMENTS REQUIRED FOR PAYER-SIDE SPLIT"
                TO WS-REASON
            PERFORM TAX-FAIL-RR06
            EXIT PARAGRAPH
        END-IF
        MOVE XT-PAYER-DOC TO WS-DOCIN
        PERFORM CHECK-PJ-VALID
        IF XT-RC NOT = "00"
            EXIT PARAGRAPH
        END-IF
        MOVE XT-RECV-DOC TO WS-DOCIN
        PERFORM CHECK-PJ-VALID
        IF XT-RC NOT = "00"
            EXIT PARAGRAPH
        END-IF
        MOVE XT-PAYER-DOC TO WS-CANON-PJ
        EVALUATE FUNCTION TRIM(XT-INITFORM)
            WHEN "QRES" WHEN "APES" WHEN "MANU" WHEN "DICT"
                CONTINUE
            WHEN "INIC"
                MOVE "SPLIT TAX OUT OF SCOPE FOR INIC"
                    TO WS-REASON
                PERFORM TAX-FAIL-RR06
                EXIT PARAGRAPH
            WHEN OTHER
                MOVE "RECEIVER-SIDE FORM FORBIDDEN IN PACS.008"
                    TO WS-REASON
                PERFORM TAX-FAIL-RR06
                EXIT PARAGRAPH
        END-EVALUATE
        MOVE "00" TO XT-RC
        EXIT PARAGRAPH
    END-IF
    IF FUNCTION TRIM(XT-MSGNM) = "pain.013.spi.2.2"
        IF XT-DEBTOR-DOC NOT = SPACES
            MOVE XT-DEBTOR-DOC TO WS-DOCIN
        ELSE
            MOVE XT-PAYER-DOC TO WS-DOCIN
        END-IF
        PERFORM CHECK-PJ-VALID
        IF XT-RC NOT = "00"
            EXIT PARAGRAPH
        END-IF
    END-IF.
    EXIT PARAGRAPH.

CHECK-PJ-VALID.
    MOVE SPACES TO BK-DOC-PARMS
    MOVE "CNPJ" TO BD-TYPE OF BK-DOC-PARMS
    MOVE "VALIDATE" TO BD-OP OF BK-DOC-PARMS
    MOVE WS-DOCIN TO BD-IN OF BK-DOC-PARMS
    CALL "BDOC" USING BK-DOC-PARMS
    IF BD-RC NOT = "00"
        STRING "CNPJ REJECTED BY DOCUMENT BOUNDARY: "
            DELIMITED SIZE FUNCTION TRIM(BD-MSG)
            DELIMITED SIZE INTO WS-REASON
        END-STRING
        PERFORM TAX-FAIL-RR06
        MOVE SPACES TO WS-REASON
        EXIT PARAGRAPH
    END-IF
    MOVE BD-CANON(1:14) TO WS-DOCIN
    MOVE "00" TO XT-RC.
    EXIT PARAGRAPH.

CHECK-TAX-SUM.
    MOVE 0 TO WS-EFF-CBS WS-EFF-IBS XT-TAXSUM
    IF FUNCTION TRIM(XT-MSGNM) = "pain.013.spi.2.2"
        PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > XT-RCNT
            IF XT-R-TY(WS-I) = "CBSSPLIT"
                IF XT-R-CT(WS-I) = "COR"
                    MOVE XT-R-AMT(WS-I) TO WS-EFF-CBS
                ELSE
                    IF WS-EFF-CBS = 0
                        MOVE XT-R-AMT(WS-I) TO WS-EFF-CBS
                    END-IF
                END-IF
            END-IF
            IF XT-R-TY(WS-I) = "IBSSPLIT"
                IF XT-R-CT(WS-I) = "COR"
                    MOVE XT-R-AMT(WS-I) TO WS-EFF-IBS
                ELSE
                    IF WS-EFF-IBS = 0
                        MOVE XT-R-AMT(WS-I) TO WS-EFF-IBS
                    END-IF
                END-IF
            END-IF
        END-PERFORM
        ADD WS-EFF-CBS TO XT-TAXSUM
        ADD WS-EFF-IBS TO XT-TAXSUM
    ELSE
        PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > XT-RCNT
            ADD XT-R-AMT(WS-I) TO XT-TAXSUM
        END-PERFORM
    END-IF
    IF XT-TAXSUM > XT-GROSS
        MOVE "REJECTED" TO XT-STATUS
        MOVE "AM23" TO XT-CODE
        MOVE "SPI" TO XT-CODESRC
        MOVE "20" TO XT-RC
        MOVE "TAX SUM EXCEEDS TRANSACTION AMOUNT" TO XT-MSG
        EXIT PARAGRAPH
    END-IF
    MOVE "00" TO XT-RC.
    EXIT PARAGRAPH.

*>  ================================================================== *
*> Internal-to-external: serialize the contract object into the
*> official deterministic envelope.  Same durable state, same bytes.
*>  ================================================================== *
DO-BUILD.
    MOVE SPACES TO XT-MSG XT-STATUS XT-CODE
    MOVE SPACES TO XT-ENV
    PERFORM DO-VALIDATE
    IF XT-RC NOT = "00"
        GOBACK
    END-IF
    PERFORM SERIALIZE-ENVELOPE
    MOVE "00" TO XT-RC
    MOVE "SPI TAX CONTRACT BUILT" TO XT-MSG.
    EXIT PARAGRAPH.

SERIALIZE-ENVELOPE.
    MOVE SPACES TO WS-ENV-TXT
    STRING "msg=" DELIMITED SIZE FUNCTION TRIM(XT-MSGNM)
        DELIMITED SIZE " v=" DELIMITED SIZE
        FUNCTION TRIM(XT-VER) DELIMITED SIZE " m=" DELIMITED
        SIZE FUNCTION TRIM(XT-MSGR-ID) DELIMITED SIZE
        " t=" DELIMITED SIZE FUNCTION TRIM(XT-CREATTM)
        DELIMITED SIZE INTO WS-ENV-TXT
    END-STRING
    IF XT-E2E-ID NOT = SPACES
        STRING FUNCTION TRIM(WS-ENV-TXT)
            " e=" DELIMITED SIZE FUNCTION TRIM(XT-E2E-ID)
            DELIMITED SIZE INTO WS-ENV-TXT
        END-STRING
    END-IF
    STRING FUNCTION TRIM(WS-ENV-TXT)
        " amt=" DELIMITED SIZE
        FUNCTION TRIM(XT-GROSS-STR) DELIMITED SIZE
        INTO WS-ENV-TXT
    END-STRING
    IF XT-HAS-TAX = "Y"
        IF XT-REFNB NOT = SPACES
            STRING FUNCTION TRIM(WS-ENV-TXT)
                " ref=" DELIMITED SIZE
                FUNCTION TRIM(XT-REFNB) DELIMITED SIZE
                INTO WS-ENV-TXT
            END-STRING
        END-IF
        PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > XT-RCNT
            STRING FUNCTION TRIM(WS-ENV-TXT)
                " rec{" DELIMITED SIZE
                FUNCTION TRIM(XT-R-TY(WS-I)) DELIMITED SIZE
                "," FUNCTION TRIM(XT-R-CT(WS-I)) DELIMITED SIZE
                "," FUNCTION TRIM(XT-R-CCY(WS-I)) DELIMITED SIZE
                "," FUNCTION TRIM(XT-R-VSTR(WS-I)) DELIMITED SIZE
                "};" DELIMITED SIZE INTO WS-ENV-TXT
            END-STRING
        END-PERFORM
    END-IF
    MOVE WS-ENV-TXT TO XT-ENV.
    EXIT PARAGRAPH.

*>  ================================================================== *
*> External-to-internal ingestion.  Validation precedes any financial
*> state; pacs.008 money moves ONLY through BPXPR (and therefore
*> BPXVAL/BPXSLV/BTXNVAL/BTXNPOST/BPXPASTO).  Nothing is persisted by
*> this module unless the lifecycle accepted it; envelopes in the
*> local store are transport/audit artifacts, never ledger inputs.
*>  ================================================================== *
DO-INGEST.
    MOVE SPACES TO XT-MSG XT-STATUS XT-CODE
    MOVE "N" TO XT-REPLAY
    PERFORM DO-VALIDATE
    IF XT-RC NOT = "00"
        PERFORM STORE-ENVELOPE
        IF XT-STORE-RC NOT = "00"
            MOVE XT-STORE-RC TO XT-RC
            MOVE "SPI TAX ENVELOPE STORE FAILED" TO XT-MSG
        END-IF
        GOBACK
    END-IF
    IF FUNCTION TRIM(XT-MSGNM) = "pacs.008.spi.1.15" OR
       FUNCTION TRIM(XT-MSGNM) = "pacs.008.spi.1.16"
        IF XT-RECV-ACCT = SPACES OR XT-RECV-CUST = SPACES
            MOVE "REJECTED" TO XT-STATUS
            MOVE "20" TO XT-RC
            MOVE "RECEIVER LEG REQUIRED FOR SPLIT POSTING"
                TO XT-MSG
            PERFORM STORE-ENVELOPE
            IF XT-STORE-RC NOT = "00"
                MOVE XT-STORE-RC TO XT-RC
                MOVE "SPI TAX ENVELOPE STORE FAILED" TO XT-MSG
            END-IF
            GOBACK
        END-IF
    END-IF
    IF FUNCTION TRIM(XT-MSGNM) = "pain.013.spi.2.2" OR
       FUNCTION TRIM(XT-MSGNM) = "camt.054.spi.1.15" OR
       FUNCTION TRIM(XT-MSGNM) = "camt.054.spi.1.16"
        PERFORM STORE-ENVELOPE
        IF XT-STORE-RC = "00"
            MOVE "NOTIF" TO XT-STATUS
            MOVE "00" TO XT-RC
            MOVE "SPI TAX MESSAGE RECORDED NO POSTING"
                TO XT-MSG
        ELSE
            MOVE XT-STORE-RC TO XT-RC
            MOVE "SPI TAX ENVELOPE STORE FAILED" TO XT-MSG
        END-IF
        GOBACK
    END-IF
    IF XT-TAXSUM >= XT-GROSS
        MOVE "REJECTED" TO XT-STATUS
        MOVE "20" TO XT-RC
        MOVE "SPLIT REQUIRES POSITIVE RECEIVER LEG" TO XT-MSG
        PERFORM STORE-ENVELOPE
        IF XT-STORE-RC NOT = "00"
            MOVE XT-STORE-RC TO XT-RC
            MOVE "SPI TAX ENVELOPE STORE FAILED" TO XT-MSG
        END-IF
        GOBACK
    END-IF
    PERFORM BUILD-DOMAIN-ROWS
    IF XT-RC NOT = "00"
        PERFORM STORE-ENVELOPE
        IF XT-STORE-RC NOT = "00"
            MOVE XT-STORE-RC TO XT-RC
            MOVE "SPI TAX ENVELOPE STORE FAILED" TO XT-MSG
        END-IF
        GOBACK
    END-IF
    CALL "BPXPR" USING BK-PX-PARMS
    MOVE XP-RC TO XT-RC
    MOVE XP-MSG TO XT-MSG
    MOVE XP-REPLAY TO XT-REPLAY
    IF XP-RC = "00"
        MOVE XP-PIX-ID TO XT-PIX-ID
        MOVE XP-TXN-ID TO XT-TXN-ID
        MOVE XP-JRN-ID TO XT-JRN-ID
        MOVE XP-STATUS TO XT-STATUS
    END-IF
    IF XT-RC NOT = "00"
        MOVE "REJECTED" TO XT-STATUS
        PERFORM STORE-ENVELOPE
        IF XT-STORE-RC NOT = "00"
            MOVE XT-STORE-RC TO XT-RC
            MOVE "SPI TAX ENVELOPE STORE FAILED" TO XT-MSG
        END-IF
        GOBACK
    END-IF
    PERFORM STORE-ENVELOPE
    IF XT-STORE-RC = "00"
        PERFORM AUDIT-ENVELOPE
    ELSE
        MOVE XT-STORE-RC TO XT-RC
        MOVE "SPI TAX POSTED BUT ENVELOPE STORE FAILED"
            TO XT-MSG
    END-IF
    EXIT PARAGRAPH.

BUILD-DOMAIN-ROWS.
    MOVE SPACES TO BK-PX-PARMS
    MOVE "PIX-REQUEST" TO XP-OP
    MOVE "OUT" TO XP-DIRECTION
    MOVE "PROD" TO XP-ENV
    MOVE "MANUAL" TO XP-MODALITY
    MOVE "Y" TO XP-SPLIT
    MOVE XT-GROSS TO XP-AMOUNT
    MOVE "BRL" TO XP-CURRENCY
    MOVE XT-PAYER-ACCT TO XP-PAYER-ACCT
    MOVE XT-PAYER-CUST TO XP-PAYER-CUST
    MOVE XT-PAYER-PART TO XP-PAYER-PART
    MOVE XT-RECV-ACCT TO XP-PAYEE-ACCT
    MOVE XT-RECV-CUST TO XP-PAYEE-CUST
    MOVE XT-RECV-PART TO XP-PAYEE-PART
    MOVE XT-DESCR TO XP-DESCR
    MOVE XT-OPERATOR TO XP-OPERATOR
    MOVE XT-E2E-ID TO XP-E2E-ID
    MOVE XT-MSGR-ID(1:24) TO XP-CORR
    MOVE XT-REQ TO XP-REQUEST
    IF XT-RECV-ACCT = SPACES OR XT-RECV-CUST = SPACES
        MOVE "RECEIVER LEG REQUIRED FOR SPLIT POSTING" TO XT-MSG
        MOVE "20" TO XT-RC
        GOBACK
    END-IF
    MOVE 0 TO XP-SPLIT-CNT
    COMPUTE WS-MAIN-AMT = XT-GROSS - XT-TAXSUM
    IF WS-MAIN-AMT <= 0
        MOVE "SPLIT POSTING REQUIRES POSITIVE RECEIVER LEG"
            TO XT-MSG
        MOVE "20" TO XT-RC
        GOBACK
    END-IF
    ADD 1 TO XP-SPLIT-CNT
    MOVE XP-SPLIT-CNT TO XP-PS-SEQ(1)
    MOVE "CUSTOMER" TO XP-PS-ROLE(1)
    MOVE XT-RECV-ACCT TO XP-PS-ID(1)
    MOVE XT-RECV-CUST TO XP-PS-CUST(1)
    MOVE WS-MAIN-AMT TO XP-PS-AMT(1)
    MOVE "MAIN" TO XP-PS-TYPE(1)
    PERFORM VARYING WS-I FROM 1 BY 1 UNTIL WS-I > XT-RCNT
        ADD 1 TO XP-SPLIT-CNT
        MOVE XP-SPLIT-CNT TO XP-PS-SEQ(XP-SPLIT-CNT)
        MOVE "TAX" TO XP-PS-ROLE(XP-SPLIT-CNT)
        IF XT-R-TY(WS-I) = "CBSSPLIT"
            MOVE XT-TAX-CBS-ACCT TO XP-PS-ID(XP-SPLIT-CNT)
            MOVE XT-TAX-CBS-CUST TO XP-PS-CUST(XP-SPLIT-CNT)
        ELSE
            MOVE XT-TAX-IBS-ACCT TO XP-PS-ID(XP-SPLIT-CNT)
            MOVE XT-TAX-IBS-CUST TO XP-PS-CUST(XP-SPLIT-CNT)
        END-IF
        MOVE "TAX" TO XP-PS-TYPE(XP-SPLIT-CNT)
        MOVE XT-R-TY(WS-I) TO XP-PS-TAXTYPE(XP-SPLIT-CNT)
        MOVE XT-R-CT(WS-I) TO XP-PS-TAXCAT(XP-SPLIT-CNT)
        MOVE XT-REFNB(1:50) TO XP-PS-DOCREF(XP-SPLIT-CNT)
        MOVE XT-R-AMT(WS-I) TO XP-PS-AMT(XP-SPLIT-CNT)
        IF XT-R-TY(WS-I) = "CBSSPLIT"
            MOVE "SPI-SPLIT-CBS" TO XP-PS-REF(XP-SPLIT-CNT)
        ELSE
            MOVE "SPI-SPLIT-IBS" TO XP-PS-REF(XP-SPLIT-CNT)
        END-IF
    END-PERFORM.
    EXIT PARAGRAPH.

STORE-ENVELOPE.
    MOVE XT-RC TO WS-TMP
    MOVE XT-MSG TO WS-MSG-KEEP
    PERFORM SERIALIZE-ENVELOPE
    MOVE SPACES TO XT-KEY
    IF XT-E2E-ID NOT = SPACES
        STRING "T" DELIMITED SIZE FUNCTION TRIM(XT-E2E-ID)
            DELIMITED SIZE INTO XT-KEY
        END-STRING
    ELSE
        STRING "M" DELIMITED SIZE FUNCTION TRIM(XT-MSGR-ID)
            DELIMITED SIZE INTO XT-KEY
        END-STRING
    END-IF
    MOVE "STX-PUT" TO XT-OP
    CALL "BPXSTXTO" USING BK-SPITAX-PARMS
    MOVE XT-RC TO XT-STORE-RC
    IF XT-STORE-RC = "22"
        MOVE "Y" TO XT-REPLAY
        MOVE "00" TO XT-STORE-RC
    END-IF
    MOVE WS-TMP TO XT-RC
    IF XT-STORE-RC = "00"
        MOVE WS-MSG-KEEP TO XT-MSG
    ELSE
        MOVE "SPI TAX ENVELOPE STORE FAILED" TO XT-MSG
    END-IF
    MOVE XT-ENV TO WS-ENV-TXT.
    EXIT PARAGRAPH.

AUDIT-ENVELOPE.
    MOVE SPACES TO BK-EVT-PARMS
    MOVE "SPI-TAX-INGEST" TO BK-EVT-TYPE
    MOVE XT-E2E-ID TO BK-EVT-KEY
    STRING "pix=" DELIMITED SIZE FUNCTION TRIM(XT-PIX-ID)
        DELIMITED SIZE " txn=" DELIMITED SIZE
        FUNCTION TRIM(XT-TXN-ID) DELIMITED SIZE
        " jrn=" DELIMITED SIZE FUNCTION TRIM(XT-JRN-ID)
        DELIMITED SIZE " msgnm=" DELIMITED SIZE
        FUNCTION TRIM(XT-MSGNM) DELIMITED SIZE
        " ref=" DELIMITED SIZE FUNCTION TRIM(XT-REFNB)
        DELIMITED SIZE INTO BK-EVT-PAYLOAD
    END-STRING
    MOVE "00" TO BK-EVT-STATUS
    CALL "BEVT" USING BK-EVT-PARMS.
    EXIT PARAGRAPH.

*>  ================================================================== *
*> Response modeling: the official enumerations of pacs.002 v1.16/1.18
*> (identical tax codes) and pain.014 v2.3 (5.12) vs v2.4 (5.13),
*> where the tax codes were removed.  Codes validated one by one
*> against the published domains; nothing invented.
*>  ================================================================== *
DO-RESPONSE.
    MOVE SPACES TO XT-CODESRC
    MOVE "N" TO XT-SYNTAX
    IF XT-STATUS NOT = "ACSC" AND XT-STATUS NOT = "RJCT"
        MOVE "20" TO XT-RC
        MOVE "RESPONSE STATUS NOT IN OFFICIAL DOMAIN" TO XT-MSG
        GOBACK
    END-IF
    IF FUNCTION TRIM(XT-MSGNM) NOT = "pacs.002" AND
       FUNCTION TRIM(XT-MSGNM) NOT = "pain.014"
        MOVE "20" TO XT-RC
        MOVE "UNKNOWN SPI RESPONSE MESSAGE" TO XT-MSG
        GOBACK
    END-IF
    IF XT-STATUS = "ACSC"
        MOVE SPACES TO XT-CODE
        MOVE "00" TO XT-RC
    ELSE
        PERFORM CHECK-RESPONSE-CODE
    END-IF
    IF XT-RC NOT = "00"
        GOBACK
    END-IF
    MOVE SPACES TO WS-ENV-TXT
    STRING "msg=" DELIMITED SIZE FUNCTION TRIM(XT-MSGNM)
        DELIMITED SIZE " v=" DELIMITED SIZE
        FUNCTION TRIM(XT-VER) DELIMITED SIZE " m=" DELIMITED
        SIZE FUNCTION TRIM(XT-MSGR-ID) DELIMITED SIZE
        " orgnl=" DELIMITED SIZE FUNCTION TRIM(XT-E2E-ID)
        DELIMITED SIZE " sts=" DELIMITED SIZE
        FUNCTION TRIM(XT-STATUS) DELIMITED SIZE
        INTO WS-ENV-TXT
    END-STRING
    IF XT-CODE NOT = SPACES
        STRING FUNCTION TRIM(WS-ENV-TXT)
            " code=" DELIMITED SIZE FUNCTION TRIM(XT-CODE)
            DELIMITED SIZE INTO WS-ENV-TXT
        END-STRING
    END-IF
    MOVE WS-ENV-TXT TO XT-ENV
    PERFORM STORE-ENVELOPE
    IF XT-RC = "00" AND XT-STORE-RC = "00"
        MOVE "00" TO XT-RC
        MOVE "SPI RESPONSE BUILT" TO XT-MSG
    ELSE
        IF XT-STORE-RC NOT = "00"
            MOVE XT-STORE-RC TO XT-RC
            MOVE "SPI TAX ENVELOPE STORE FAILED" TO XT-MSG
        END-IF
    END-IF.
    EXIT PARAGRAPH.

CHECK-RESPONSE-CODE.
    IF XT-CODE = SPACES
        MOVE "20" TO XT-RC
        MOVE "REJECTION REASON CODE REQUIRED" TO XT-MSG
        GOBACK
    END-IF
    IF FUNCTION TRIM(XT-MSGNM) = "pacs.002"
        PERFORM CHECK-PACS002-CODE
    ELSE
        PERFORM CHECK-PAIN014-CODE
    END-IF.
    EXIT PARAGRAPH.

CHECK-PACS002-CODE.
    MOVE "Y" TO WS-BAD
    EVALUATE XT-CODE
        WHEN "AB03" WHEN "AB09" WHEN "AB11" WHEN "AC03"
            WHEN "AC06" WHEN "AC07" WHEN "AC14" WHEN "AG01"
            WHEN "AG03" WHEN "AG12" WHEN "AG13" WHEN "AGNT"
            WHEN "AM01" WHEN "AM02" WHEN "AM04" WHEN "AM09"
            WHEN "AM12" WHEN "AM18" WHEN "AM23" WHEN "BE01"
            WHEN "BE05" WHEN "BE15" WHEN "BE17" WHEN "CH11"
            WHEN "CH16" WHEN "CN01" WHEN "DS02" WHEN "DS04"
            WHEN "DS0G" WHEN "DS27" WHEN "DT02" WHEN "DT05"
            WHEN "DU03" WHEN "DUPL" WHEN "ED05" WHEN "FF07"
            WHEN "FF08" WHEN "FRAD" WHEN "INDT" WHEN "MD01"
            WHEN "RC09" WHEN "RC10" WHEN "RR04" WHEN "RR06"
            MOVE "N" TO WS-BAD
    END-EVALUATE
    IF WS-BAD = "Y"
        MOVE "20" TO XT-RC
        MOVE "PACS.002 CODE NOT IN OFFICIAL DOMAIN" TO XT-MSG
    END-IF.
    EXIT PARAGRAPH.

CHECK-PAIN014-CODE.
    MOVE "Y" TO WS-BAD
    EVALUATE TRUE
        WHEN XT-CODE = "AB10" WHEN XT-CODE = "AC05"
            WHEN XT-CODE = "AC06" WHEN XT-CODE = "AM02"
            WHEN XT-CODE = "AM09" WHEN XT-CODE = "CRNC"
            WHEN XT-CODE = "DENC" WHEN XT-CODE = "DTED"
            WHEN XT-CODE = "DTNT" WHEN XT-CODE = "FCD1"
            WHEN XT-CODE = "FCD2" WHEN XT-CODE = "GRER"
            WHEN XT-CODE = "IRNT" WHEN XT-CODE = "MIDI"
            WHEN XT-CODE = "MSUC" WHEN XT-CODE = "NIEC"
            WHEN XT-CODE = "NIPA" WHEN XT-CODE = "NITX"
            WHEN XT-CODE = "QUNT" WHEN XT-CODE = "UDEI"
            MOVE "N" TO WS-BAD
    END-EVALUATE
    IF WS-BAD = "Y"
        IF FUNCTION TRIM(XT-VER) = "5.12"
            EVALUATE TRUE
                WHEN XT-CODE = "AG12" WHEN XT-CODE = "AM23"
                    WHEN XT-CODE = "DS27" WHEN XT-CODE = "RC09"
                    WHEN XT-CODE = "RR06"
                    MOVE "N" TO WS-BAD
            END-EVALUATE
        END-IF
    END-IF
    IF WS-BAD = "Y"
        MOVE "20" TO XT-RC
        MOVE "PAIN.014 CODE NOT IN OFFICIAL DOMAIN" TO XT-MSG
        IF FUNCTION TRIM(XT-VER) = "5.13"
            MOVE "PAIN.014 5.13 HAS NO TAX ERROR CODE"
                TO XT-MSG
        END-IF
    END-IF.
    EXIT PARAGRAPH.

*>  ================================================================== *
*> Diagnostics passthroughs to the envelope store.
*>  ================================================================== *
DO-TXGET.
    MOVE "STX-GET" TO XT-OP
    CALL "BPXSTXTO" USING BK-SPITAX-PARMS.
    EXIT PARAGRAPH.

DO-TXGETE2E.
    MOVE "STX-GETE2E" TO XT-OP
    CALL "BPXSTXTO" USING BK-SPITAX-PARMS.
    EXIT PARAGRAPH.

DO-TXLIST.
    MOVE "STX-LIST" TO XT-OP
    CALL "BPXSTXTO" USING BK-SPITAX-PARMS.
    EXIT PARAGRAPH.
LOAD-DEFAULT-VERSION.
    MOVE SPACES TO BK-PX-CFG
    CALL "BPXCFG" USING BK-PX-CFG
    MOVE "5.13" TO XT-VER
    IF PC-SPI-VER = "5.12" OR PC-SPI-VER = "5.13"
        MOVE PC-SPI-VER TO XT-VER
    END-IF.
