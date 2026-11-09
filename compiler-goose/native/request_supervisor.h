#ifndef BLOT_REQUEST_SUPERVISOR_H
#define BLOT_REQUEST_SUPERVISOR_H
#include <stdint.h>

/* Linux, single-threaded and quiescent at begin. Request/reply bytes are opaque.
 * Worker descendants must remain in their inherited process group. The fork hook
 * closes inherited stage-worker handles without signalling those baseline workers.
 * No request parsing, compiler state, or cache publication belongs in this module.
 */
enum { BLOT_REQUEST_SUPERVISOR = 0, BLOT_REQUEST_WORKER = 1 };
enum {
    BLOT_REQUEST_ACCEPTED = 0,
    BLOT_REQUEST_OOM = 1,
    BLOT_REQUEST_FAILED = 2,
    BLOT_REQUEST_TIMEOUT = 3,
};
void blot_request_fork_hook(void (*hook)(void));
/* Allocation-free post-adoption publication. Drain optional cache effects here;
 * the supervisor waits for this hook before exposing the accepted reply. */
void blot_request_adopt_hook(void (*hook)(void));
/* Optional parent-only validation of immutable complete reply before adoption. */
void blot_request_reply_validator(int32_t (*validate)(int32_t fd, uint64_t length, uint64_t token));
/* Call once before compiler state is created; returns role or negative errno.
 * The supervisor owns the external input/output. Worker stdout is discarded. */
int32_t blot_request_start(uint64_t max_request, uint64_t max_reply, uint32_t timeout_ms);
/* Supervisor: borrowed regular/spool FD, exact length, increasing nonzero token.
 * The caller writes reply bytes externally only after ACCEPTED. Input errors
 * return negative errno before begin. -EPIPE means the baseline control channel
 * failed and the supervisor stopped; all other results retain committed state.
 */
int32_t blot_request_submit(int32_t request_fd, uint64_t length, uint64_t token);
/* Supervisor: accepted immutable reply; valid until next submit/stop. */
int32_t blot_request_reply_fd(void);
uint64_t blot_request_reply_length(void);
void blot_request_stop(void);
/* Worker: blocks between requests, forks before exposing bytes to the candidate.
 * Returns 0 only in a candidate, or negative errno on shutdown/transport failure.
 */
int32_t blot_request_begin(void);
int32_t blot_request_input_fd(void);
uint64_t blot_request_input_length(void);
/* Internal exec-worker bootstrap: consumes only the private native argv suffix,
 * restores public --worker arguments, and marks the capability close-on-exec.
 * Call before goose_init. Returns 1 for a bound stage child, 0 normally, <0 invalid. */
int32_t blot_request_stage_init(int *argc, char **argv);
/* Borrowed OOM-only capability for a candidate's copied stage workers, or -1.
 * It never carries request/reply or adoption messages. */
int32_t blot_request_stage_capability(void);
/* Zero in the supervisor and outside candidate/adoption processing. Exec stage
 * children retain their original token until exit, never a later request token. */
uint64_t blot_request_token(void);
/* Worker: call after all request cleanup. Borrows reply FD, stages and seals an
 * exact bounded copy. Returns 0 after adoption; failed candidates never return.
 */
int32_t blot_request_finish(int32_t reply_fd, uint64_t length, uint64_t token);
/* Terminal, allocation-free failure path. Only this marker classifies an OOM;
 * exit codes, signals, missing/truncated replies, and timeouts never do. */
_Noreturn void blot_request_fail_oom(uint64_t token);
_Noreturn void blot_request_fail(uint64_t token);
#endif
