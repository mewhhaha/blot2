#include <stdint.h>
#include <unistd.h>
#include <stdlib.h>
#include "allocation_observer.h"
#include "request_supervisor.h"
#include "request_cache.h"
#if !defined(_WIN32)
#include <sys/resource.h>
#endif

/* Build the Goose source as a C-host library (--header). The generated header
 * exports this fixed scalar entry; no compiler algorithm crosses this shim. */
extern void goose_init(int argc, char **argv);
extern int32_t blot_goose_main(void);
extern void blot_platform_entry_init(int argc, char **argv);

extern void blot_worker_detach(void);
static uint64_t failure_request, failure_at;
static int failure_kind;

static uint64_t unsigned_environment(const char *name) {
    const char *value = getenv(name);
    if (!value || !*value) return 0;
    uint64_t result = 0;
    for (; *value; ++value) {
        if (*value < '0' || *value > '9') return 0;
        unsigned digit = (unsigned)(*value - '0');
        if (result > (UINT64_MAX - digit) / 10) return 0;
        result = result * 10 + digit;
    }
    return result;
}

static void request_forked(void) {
    blot_worker_detach();
    uint64_t token = blot_request_token();
    uint64_t selected = 0;
    if (token == failure_request) selected = failure_at;
    blot_allocation_observer_begin(token, selected, failure_kind);
}

static void allocation_failed(int kind, uint64_t bytes) {
    (void)kind;
    (void)bytes;
    uint64_t token = blot_request_token();
    if (token) blot_request_fail_oom(token);
    static const char message[] = "blotc: out_of_memory\n";
    (void)write(STDERR_FILENO, message, sizeof message - 1);
    _exit(125);
}

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
    failure_request = unsigned_environment("BLOT_GOOSE_FAIL_REQUEST");
    failure_at = unsigned_environment("BLOT_GOOSE_FAIL_AT");
    uint64_t kind = unsigned_environment("BLOT_GOOSE_FAIL_KIND");
    if (kind <= BLOT_OBS_POOL_REUSE) failure_kind = (int)kind;
    blot_request_fork_hook(request_forked);
    blot_request_adopt_hook(blot_request_cache_publish);
    blot_allocation_observer_install(allocation_failed);
    goose_init(argc, argv);
    return blot_goose_main();
}
