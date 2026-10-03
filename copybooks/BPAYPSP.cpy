       01 BK-PAY-POST-REQ.
          05 PPO-SRC           PIC X(12).
          05 PPO-DST           PIC X(12).
          05 PPO-AMOUNT        PIC S9(15)V99 COMP-3.
          05 PPO-CURRENCY      PIC X(03).
          05 PPO-JRN-ID        PIC X(20).
          05 PPO-TXN-ID        PIC X(24).
          05 PPO-REQUEST       PIC X(24).
          05 PPO-DESCR         PIC X(40).
          05 PPO-OPERATOR      PIC X(12).
          05 PPO-CORR          PIC X(24).
          05 PPO-BIZDATE       PIC 9(08).
          05 PPO-RC            PIC X(02).
          05 PPO-MSG           PIC X(80).
