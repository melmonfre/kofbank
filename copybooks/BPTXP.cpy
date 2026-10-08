      *> SPI Split Tax contract boundary parameters (BPXSTX).
      *> Official field mnemonics (RefNb, Rcrd, Tp, Ctgy, TaxAmt, TtlAmt)
      *> are external-contract identifiers and appear ONLY here and in
      *> BPXSTX/BPXSTXTO; they never enter the financial domain copybooks.
      *> The domain counterpart of this block is the existing allocation
      *> tax metadata (SP-PS-TAXTYPE / SP-PS-TAXCAT / SP-PS-DOCREF) which
      *> stays authoritative for financial effects.
      *> Contract source: BCB "Definições detalhadas das mensagens do
      *> Catálogo de Mensagens do SPI" spi.5.13.2.zip (2026-10-02,
      *> current production cycle SPI 5.13) and Catálogo de Serviços do
      *> SFN Volume VI v5.13.  spi.5.12.1.zip was diffed for versioning:
      *> the Tax structure is identical between 5.12.1 and 5.13.2
      *> (pacs.008 1.15->1.16, camt.054 1.15->1.16 bump message version
      *> only; pain.013 2.2 unchanged).
       01 BK-SPITAX-PARMS.
          05 XT-OP             PIC X(14).
          05 XT-MSGNM          PIC X(20).
          05 XT-VER            PIC X(05).
          05 XT-MSGR-ID        PIC X(32).
          05 XT-E2E-ID         PIC X(32).
          05 XT-CREATTM        PIC X(24).
          05 XT-GROSS-STR      PIC X(18).
          05 XT-CURRENCY       PIC X(03).
          05 XT-INITFORM       PIC X(04).
          05 XT-PAYER-ACCT     PIC X(12).
          05 XT-PAYER-CUST     PIC X(12).
          05 XT-PAYER-PART     PIC X(12).
          05 XT-RECV-ACCT      PIC X(12).
          05 XT-RECV-CUST      PIC X(12).
          05 XT-RECV-PART      PIC X(12).
          05 XT-DEBTOR-CUST    PIC X(12).
          05 XT-TAX-CBS-ACCT    PIC X(12).
          05 XT-TAX-CBS-CUST   PIC X(12).
          05 XT-TAX-IBS-ACCT    PIC X(12).
          05 XT-TAX-IBS-CUST   PIC X(12).
          05 XT-PAYER-DOC      PIC X(20).
          05 XT-RECV-DOC       PIC X(20).
          05 XT-DEBTOR-DOC     PIC X(20).
          05 XT-DESCR          PIC X(40).
          05 XT-OPERATOR       PIC X(12).
          05 XT-REQ            PIC X(24).
          05 XT-GROSS          PIC S9(15)V99 COMP-3.
          05 XT-HAS-TAX        PIC X(01).
          05 XT-REFNB          PIC X(50).
          05 XT-RCNT           PIC 9(02).
          05 XT-R OCCURS 4 TIMES.
             10 XT-R-TY        PIC X(08).
             10 XT-R-CT        PIC X(03).
             10 XT-R-VSTR      PIC X(18).
             10 XT-R-CCY       PIC X(03).
             10 XT-R-AMT       PIC S9(15)V99 COMP-3.
          05 XT-TAXSUM         PIC S9(15)V99 COMP-3.
          05 XT-STATUS         PIC X(10).
          05 XT-CODE           PIC X(04).
          05 XT-CODESRC        PIC X(04).
          05 XT-SYNTAX         PIC X(01).
          05 XT-RC             PIC X(02).
          05 XT-MSG            PIC X(80).
          05 XT-PIX-ID         PIC X(12).
          05 XT-TXN-ID         PIC X(12).
          05 XT-JRN-ID         PIC X(20).
          05 XT-REPLAY         PIC X(01).
          05 XT-STORE-RC       PIC X(02).
          05 XT-ENV            PIC X(2000).
          05 XT-KEY            PIC X(70).
          05 XT-CNT            PIC 9(03).
