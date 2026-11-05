#include <stdint.h>
#if !defined(_WIN32)
#include <sys/resource.h>
#endif

/* Build the Goose source as a C-host library (--header). The generated header
 * exports this fixed scalar entry; no compiler algorithm crosses this shim. */
extern void goose_init(int argc, char **argv);
extern int32_t blot_goose_main(void);
extern void blot_platform_entry_init(int argc, char **argv);

int main(int argc, char **argv) {
    /* Native inference uses deep ordinary C recursion. Raising the main
     * thread limit preserves demand-committed stack pages without introducing
     * a Goose thread entry that reaches non-flat compiler metadata. */
#if !defined(_WIN32)
    struct rlimit stack;
    if (getrlimit(RLIMIT_STACK, &stack) == 0) {
        rlim_t wanted = (rlim_t)1 << 30;
        if (stack.rlim_max != RLIM_INFINITY && wanted > stack.rlim_max)
            wanted = stack.rlim_max;
        if (stack.rlim_cur != RLIM_INFINITY && wanted > stack.rlim_cur) {
            stack.rlim_cur = wanted;
            (void)setrlimit(RLIMIT_STACK, &stack);
        }
    }
#endif
    blot_platform_entry_init(argc, argv);
    goose_init(argc, argv);
    return blot_goose_main();
}
