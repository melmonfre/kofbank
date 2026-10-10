/* lockhelper - test-only driver for the KFLOCK native helper (build/KFLOCK.so).
 * Independent OS processes use this to create real, controllable lock
 * contention. Mirrors the COBOL call ABI (all args by reference, fixed-width).
 *
 *   acquire <ms> <base> <name> : KOF_LOCK_TIMEOUT_MS=<ms>; dlopen KFLOCK;
 *                                mode 'W'; prints status=NN; exits.
 *   acquire <ms> <base> <name> <waitsec> : same, then holds the lock for
 *                                <waitsec> seconds before releasing.
 *   selftest                   : dlopen with no KFLOCK symbols => expect EF
 *                                (proves fail-closed with no silent fallback).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dlfcn.h>

typedef void (*kflock_t)(char *, char *, char *, char *);

static void pad(char *dst, const char *src, int width)
{
    int i, n = (int)strlen(src);
    for (i = 0; i < width; i++)
        dst[i] = i < n ? src[i] : ' ';
}

int main(int argc, char **argv)
{
    void *h;
    kflock_t f;
    char mode[1], base[80], name[64], status[2];
    char *so;

    if (argc >= 2 && strcmp(argv[1], "selftest") == 0) {
        h = dlopen("./build/NO_SUCH_LIB_KFLOCK.so", RTLD_NOW);
        if (!h) {
            printf("status=EF\n");
            return 0;
        }
        printf("status=LOADED\n");
        return 2;
    }

    if (argc < 5) {
        fprintf(stderr, "usage: lockhelper acquire <ms|-> <base> <name> [waitsec]\n");
        return 1;
    }
    if (strcmp(argv[2], "-") != 0)
        setenv("KOF_LOCK_TIMEOUT_MS", argv[2], 1);

    so = getenv("KFLOCK_SO");
    h = dlopen(so ? so : "./build/KFLOCK.so", RTLD_NOW);
    if (!h) {
        fprintf(stderr, "dlopen: %s\n", dlerror());
        return 1;
    }
    f = (kflock_t)dlsym(h, "KFLOCK");
    if (!f) {
        fprintf(stderr, "dlsym: %s\n", dlerror());
        printf("status=EF\n");
        return 3;
    }

    mode[0] = 'W';
    pad(base, argv[3], 80);
    pad(name, argv[4], 64);
    status[0] = '0';
    status[1] = '0';
    f(mode, base, name, status);
    printf("status=%c%c\n", status[0], status[1]);
    fflush(stdout);
    if (status[0] == '0' && status[1] == '0' && argc >= 6) {
        sleep(atoi(argv[5]));
        mode[0] = 'R';
        f(mode, base, name, status);
    }
    return 0;
}
