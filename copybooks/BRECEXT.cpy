       05 XL-RC              PIC X(02).
       05 XL-MSG             PIC X(80).
       05 XL-N-EXT           PIC 9(05).
       05 XL-N-JRN           PIC 9(05).
       05 XL-EXTT.
          10 XL-E-ROW OCCURS 200 TIMES.
             15 XL-E-REF     PIC X(24).
             15 XL-E-KEY     PIC X(24).
             15 XL-E-AMT     PIC S9(15)V99 COMP-3.
             15 XL-E-CUR     PIC X(03).
             15 XL-E-DATE    PIC X(08).
             15 XL-E-STATE   PIC X(01).
       05 XL-JRNT.
          10 XL-J-ROW OCCURS 400 TIMES.
             15 XL-J-ID      PIC X(20).
             15 XL-J-AMT     PIC S9(15)V99 COMP-3.
             15 XL-J-CUR     PIC X(03).
             15 XL-J-DATE    PIC X(08).
             15 XL-J-MATCH   PIC X(01).
