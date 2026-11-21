#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void packet_path(char *path, size_t size, uint32_t version,
                        uint32_t unit) {
  const char *dir = getenv(version == 0 ? "BLOT_BASE" : "BLOT_EDIT");
  if (!dir || snprintf(path, size, "%s/%u-2.bin", dir, unit) >= (int)size)
    abort();
}
int64_t body_packet_size(uint32_t version, uint32_t unit) {
  char path[4096];
  struct stat st;
  packet_path(path, sizeof path, version, unit);
  if (stat(path, &st))
    abort();
  return st.st_size;
}
void body_packet_read(uint32_t version, uint32_t unit, uint8_t *data,
                      int64_t n) {
  char path[4096];
  packet_path(path, sizeof path, version, unit);
  FILE *f = fopen(path, "rb");
  if (!f || fread(data, 1, n, f) != (size_t)n || fclose(f))
    abort();
}
void body_stat(uint32_t key, uint64_t value) {
  printf("%u %" PRIu64 "\n", key, value);
}
void body_save(uint32_t kind, const uint8_t *data, int64_t n) {
  char path[4096];
  if (snprintf(path, sizeof path, "%s/%u.wasm", getenv("BLOT_SAVE"), kind) >=
      (int)sizeof path)
    abort();
  FILE *f = fopen(path, "wb");
  if (!f || fwrite(data, 1, n, f) != (size_t)n || fclose(f))
    abort();
}
bool body_reference_first(void) {
  return getenv("BLOT_REFERENCE_FIRST") != NULL;
}
uint32_t edit_unit(void) { return strtoul(getenv("BLOT_EDIT_UNIT"), NULL, 10); }
uint32_t edit_point(void) {
  return strtoul(getenv("BLOT_EDIT_POINT"), NULL, 10);
}
void body_diag(const uint8_t *text, int64_t n) {
  fprintf(stderr, "%.*s\n", (int)n, text);
}

// This fixed bound belongs to the pinned benchmark. An overflow aborts the
// experiment.
enum { limit = 16384 };
struct key {
  uint32_t kind, unit, id, type, parent, evidence;
};
struct trace {
  struct key *calls;
  size_t count, capacity, replayed;
  uint32_t existing;
};
static struct trace traces[limit];
static bool inferred[limit], replay, stage_reader, mismatch, enabled;
static uint32_t unit, binding, active = UINT32_MAX;

void body_enable(bool value) { enabled = value; }
void body_target(uint32_t u, uint32_t b) {
  unit = u;
  binding = b;
}
bool body_is_target(uint32_t u, uint32_t b) {
  return unit == u && binding == b;
}
void body_stage_read(uint32_t u, uint32_t b) {
  if (enabled && body_is_target(u, b))
    stage_reader = true;
}
bool body_staged(void) { return stage_reader; }
uint32_t body_enter(uint32_t id, bool track, bool inferring,
                    uint32_t existing) {
  uint32_t prior = active;
  if (id >= limit)
    abort();
  active = (enabled && track) ? id : UINT32_MAX;
  if (active != UINT32_MAX && !replay)
    traces[id].existing = existing;
  if (enabled && !replay && inferring)
    inferred[id] = true;
  return prior;
}
void body_leave(uint32_t saved) { active = saved; }
bool body_inferred(uint32_t id) {
  if (id >= limit)
    abort();
  return inferred[id];
}
void body_begin_replay(void) { replay = true; }
void body_lookup(uint32_t kind, uint32_t u, uint32_t id, uint32_t type,
                 uint32_t parent, uint32_t evidence, uint32_t found) {
  if (active == UINT32_MAX)
    return;
  struct trace *trace = &traces[active];
  if (found < trace->existing)
    return;
  struct key key = {kind, u, id, type, parent, evidence};
  if (replay) {
    if (trace->replayed >= trace->count ||
        memcmp(&trace->calls[trace->replayed], &key, sizeof key))
      mismatch = true;
    trace->replayed++;
    return;
  }
  if (trace->count == trace->capacity) {
    trace->capacity = trace->capacity ? 2 * trace->capacity : 16;
    trace->calls = realloc(trace->calls, trace->capacity * sizeof key);
    if (!trace->calls)
      abort();
  }
  trace->calls[trace->count++] = key;
}
bool body_trace_match(uint32_t id) {
  return id < limit && !mismatch && traces[id].count == traces[id].replayed;
}
