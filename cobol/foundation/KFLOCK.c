/* KFLOCK - narrow native cross-process advisory lock helper for KofBank.
 *
 * Provides true cross-process mutual exclusion via flock(2) on a per-key lock
 * file. The lock fd is kept in a process-static table keyed by the resolved
 * path so a lock acquired in one COBOL CALL is still held for later CALLs in
 * the same process (COBOL holds no fd across CALL boundaries otherwise) and is
 * released by the kernel automatically if the process dies. This is the only
 * primitive here; it carries no financial logic and no payload data.
 *
 * Build:  cc -O2 -fPIC -shared -o build/KFLOCK.so cobol/foundation/KFLOCK.c
 * Load:   COB_LIBRARY_PATH must contain the directory holding KFLOCK.so so the
 *         GnuCOBOL runtime dlopen()s it on CALL "KFLOCK".
 *
 * Interface (all arguments passed BY REFERENCE by COBOL, fixed-width fields):
 *   MODE   PIC X(1)   'A' = acquire non-blocking (busy => status "61")
 *                     'W' = acquire with bounded wait: if the environment
 *                           KOF_LOCK_TIMEOUT_MS is set to N > 0, poll for the
 *                           grant every 2ms up to N ms and give up with "62"
 *                           (timeout, distinct from contention); if unset or
 *                           0, wait in-kernel (relying on kernel release at
 *                           holder death) with no application deadline.
 *                     'R' = release (unlock + close the held fd)
 *   BASE   PIC X(80)  data directory, e.g. BANK_HOME + "/var/data"
 *   NAME   PIC X(64)  logical lock name (sanitised; never raw payload)
 *   STATUS PIC X(2)   out: "00" acquired/released, "61" busy (non-blocking),
 *                     "62" timed out waiting, "EF" file/env error,
 *                     "NS" unsupported/invalid mode.
 *                     Contention (61/62), infrastructure failure (EF) and bad
 *                     usage (NS) stay distinguishable to callers.
 *
 * The resolved object is "<BASE>/lk_<sanitised NAME>.lck". The file is created
 * with O_CREAT and NEVER unlinked (removing it would let different processes
 * lock different inodes for the same logical key). Kernel locks are per-inode,
 * so this is correct across processes. Contention granularity is one file per
 * logical key: distinct keys never contend.
 *
 * Supported environments: POSIX with flock(2) (Linux, *BSD) on a local
 * filesystem. It is deliberately NOT used for cross-host or network-filesystem
 * deployment (see ADR 0022); on a platform without flock the 'W'/'A' path
 * returns "EF" and callers fail closed.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <sys/file.h>

#define MAXLOCKS 256

static long lk_deadline_ms(void)
{
    const char *s = getenv("KOF_LOCK_TIMEOUT_MS");
    long v;
    if (s == NULL || *s == '\0')
        return 0;
    v = strtol(s, NULL, 10);
    return v > 0 ? v : 0;
}

static long lk_now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

static int   lk_fd[MAXLOCKS];
static char  lk_path[MAXLOCKS][700];
static int   lk_n = 0;

static int lk_find(const char *path)
{
    int i;
    for (i = 0; i < lk_n; i++)
        if (strcmp(lk_path[i], path) == 0)
            return i;
    return -1;
}

/* trim leading/trailing spaces from a fixed-width COBOL field into dst */
static void lk_trim(const char *src, int len, char *dst)
{
    int s = 0, e = len - 1, j = 0;
    while (s < len && src[s] == ' ') s++;
    while (e >= s && src[e] == ' ') e--;
    for (; s <= e && j < len; s++, j++)
        dst[j] = src[s];
    dst[j] = '\0';
}

/* keep only filesystem-safe characters; collapse the rest to '_' */
static void lk_sanitize(const char *src, char *dst)
{
    int j = 0;
    for (; *src && j < 300; src++)
        dst[j++] = (isalnum((unsigned char)*src) || *src == '-' ||
                    *src == '_' || *src == '.') ? *src : '_';
    dst[j] = '\0';
}

static void lk_status(char *out, const char *code)
{
    out[0] = code[0];
    out[1] = code[1];
}

void KFLOCK(char *mode, char *base, char *name, char *status)
{
    char b[96], nm[80], clean[80], path[700];
    char m;
    long deadline, start, waited;
    int  i, fd, e;

    lk_trim(base, 80, b);
    lk_trim(name, 64, nm);
    lk_sanitize(nm, clean);
    lk_status(status, "00");

    if (b[0] == '\0' || clean[0] == '\0') {
        lk_status(status, "EF");
        return;
    }
    snprintf(path, sizeof path, "%s/lk_%.80s.lck", b, clean);

    m = mode[0];
    i = lk_find(path);

    if (m == 'A' || m == 'W') {
        /* already held by this process: do not silently re-grant nesting */
        if (i >= 0) {
            lk_status(status, "61");
            return;
        }
        fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0644);
        if (fd < 0) {
            lk_status(status, "EF");
            return;
        }
        if (m == 'A') {
            if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
                e = errno;
                close(fd);
                lk_status(status, (e == EWOULDBLOCK || e == EACCES) ? "61" : "EF");
                return;
            }
        } else {
            /* bounded wait: poll until deadline, else wait in-kernel */
            deadline = lk_deadline_ms();
            start = lk_now_ms();
            for (;;) {
                if (flock(fd, LOCK_EX | LOCK_NB) == 0)
                    break;
                e = errno;
                if (e != EWOULDBLOCK && e != EACCES) {
                    close(fd);
                    lk_status(status, "EF");
                    return;
                }
                if (deadline == 0) {
                    if (flock(fd, LOCK_EX) != 0) {
                        close(fd);
                        lk_status(status, "EF");
                        return;
                    }
                    break;
                }
                waited = lk_now_ms() - start;
                if (waited >= deadline) {
                    close(fd);
                    lk_status(status, "62");
                    return;
                }
                {
                    struct timespec nap;
                    nap.tv_sec = 0;
                    nap.tv_nsec = 2000000; /* 2ms poll interval */
                    nanosleep(&nap, NULL);
                }
            }
        }
        lk_fd[lk_n] = fd;
        strncpy(lk_path[lk_n], path, sizeof lk_path[0] - 1);
        lk_path[lk_n][sizeof lk_path[0] - 1] = '\0';
        lk_n++;
        lk_status(status, "00");
        return;
    }

    if (m == 'R') {
        if (i < 0) {
            /* release of an unheld key is a no-op success */
            lk_status(status, "00");
            return;
        }
        flock(lk_fd[i], LOCK_UN);
        close(lk_fd[i]);
        for (; i < lk_n - 1; i++) {
            lk_fd[i] = lk_fd[i + 1];
            strcpy(lk_path[i], lk_path[i + 1]);
        }
        lk_n--;
        lk_status(status, "00");
        return;
    }

    lk_status(status, "NS");
}
