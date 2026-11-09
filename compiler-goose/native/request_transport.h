#ifndef BLOT_REQUEST_TRANSPORT_H
#define BLOT_REQUEST_TRANSPORT_H
#include <stdint.h>
/* Public project protocol 1: two little-endian u32 lengths, JSON + opaque payload.
 * Hello is emitted once by Goose before request_start; this loop emits no Hello.
 * Call only in the supervisor role, with 64 MiB request/reply limits. Returns zero
 * at clean EOF/accepted close, otherwise negative errno and closes the session.
 * Full request schema checking and all compiler operations remain Goose code.
 */
int32_t blot_request_transport_run(int32_t reader_fd, int32_t writer_fd);
/* Candidate-only output spool, kernel-capped at 64 MiB; write sequentially.
 * Cleanup parsed request owners before finish.
 * finish returns only after adoption; no stdout is used by the candidate. */
int32_t blot_request_transport_reply_open(void);
int32_t blot_request_transport_finish(uint64_t token);
#endif
