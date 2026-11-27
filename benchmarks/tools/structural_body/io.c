#include <errno.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static void packet_path(char *path, size_t size, uint32_t version,
                        uint32_t unit) {
  const char *dir = getenv(version == 0 ? "SQUID_BASE" : "SQUID_EDIT");
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
  if (snprintf(path, sizeof path, "%s/%u.wasm", getenv("SQUID_SAVE"), kind) >=
      (int)sizeof path)
    abort();
  FILE *f = fopen(path, "wb");
  if (!f || fwrite(data, 1, n, f) != (size_t)n || fclose(f))
    abort();
}
bool body_reference_first(void) {
  return getenv("SQUID_REFERENCE_FIRST") != NULL;
}
uint32_t edit_unit(void) { return strtoul(getenv("SQUID_EDIT_UNIT"), NULL, 10); }
uint32_t edit_point(void) {
  return strtoul(getenv("SQUID_EDIT_POINT"), NULL, 10);
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
static bool inferred[limit], replay, mismatch, enabled;
static uint32_t active = UINT32_MAX, named_count;
static size_t event_count, event_bytes, staged_bytes;
struct staged_bindings {
  uint8_t *bits;
  size_t size;
};
static struct staged_bindings stages[294];

bool body_recording(void) { return getenv("SQUID_CONTROL") == NULL; }
void body_enable(bool value) { enabled = value; }

void body_stage_read(uint32_t unit, uint32_t binding) {
  if (!enabled || replay)
    return;
  if (unit >= sizeof stages / sizeof stages[0])
    abort();
  struct staged_bindings *stage = &stages[unit];
  size_t index = binding / 8;
  if (index >= stage->size) {
    size_t next = 2 * (index + 1);
    stage->bits = realloc(stage->bits, next);
    if (!stage->bits)
      abort();
    memset(stage->bits + stage->size, 0, next - stage->size);
    staged_bytes += next - stage->size;
    stage->size = next;
  }
  stage->bits[index] |= 1u << (binding % 8);
}
bool body_staged(uint32_t unit, uint32_t binding) {
  if (unit >= sizeof stages / sizeof stages[0])
    abort();
  struct staged_bindings *stage = &stages[unit];
  return binding / 8 < stage->size &&
         (stage->bits[binding / 8] & (1u << (binding % 8)));
}
uint32_t body_enter(uint32_t id, bool track, bool inferring,
                    uint32_t existing) {
  uint32_t prior = active;
  if (id >= limit)
    abort();
  active = UINT32_MAX;
  if (enabled && track)
    active = id;
  if (active != UINT32_MAX && !replay) {
    traces[id].existing = existing;
    named_count++;
  }
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
    size_t old = trace->capacity;
    trace->capacity = 4;
    if (old)
      trace->capacity = 2 * old;
    event_bytes += (trace->capacity - old) * sizeof key;
    trace->calls = realloc(trace->calls, trace->capacity * sizeof key);
    if (!trace->calls)
      abort();
  }
  trace->calls[trace->count++] = key;
  event_count++;
}
bool body_trace_match(uint32_t id) {
  return id < limit && !mismatch && traces[id].count == traces[id].replayed;
}

// Each edit runs in a child of the same completed checkpoint. The parent
// cannot observe mutations in an accepted, declined or failing trial.
static bool job_line(char **line, size_t *cap) {
  ssize_t size = getline(line, cap, stdin);
  if (size < 0 && feof(stdin))
    return false;
  if (size <= 0 || (*line)[size - 1] != '\n')
    abort();
  (*line)[size - 1] = 0;
  return true;
}

extern uint64_t squid_clock_ns(void);
static uint64_t job_start;
uint64_t body_job_elapsed(void) { return squid_clock_ns() - job_start; }

bool body_next_edit(void) {
  body_stat(23, named_count);
  body_stat(24, event_count);
  body_stat(25, event_bytes + staged_bytes + sizeof traces + sizeof inferred +
                    sizeof stages);
  fflush(stdout);
  int ready_fd = atoi(getenv("SQUID_READY_FD"));
  if (write(ready_fd, "!", 1) != 1 || close(ready_fd)) abort();
  char *fields[5] = {0};
  size_t caps[5] = {0};
  unsigned int job = 0;
  while (job_line(&fields[0], &caps[0])) {
    for (int i = 1; i < 5; i++)
      if (!job_line(&fields[i], &caps[i]))
        abort();
    printf("JOB %u\n", job++);
    fflush(stdout);
    job_start = squid_clock_ns();
    pid_t child = fork();
    if (child < 0)
      abort();
    if (!child) {
      if (setenv("SQUID_EDIT", fields[0], 1) ||
          setenv("SQUID_SAVE", fields[1], 1) ||
          setenv("SQUID_EDIT_UNIT", fields[2], 1) ||
          setenv("SQUID_EDIT_POINT", fields[3], 1))
        abort();
      if (strcmp(fields[4], "1") == 0 && setenv("SQUID_REFERENCE_FIRST", "1", 1))
        abort();
      return true;
    }
    int status = 0;
    while (waitpid(child, &status, 0) < 0)
      if (errno != EINTR)
        abort();
    if (!WIFEXITED(status) || WEXITSTATUS(status))
      exit(1);
  }
  for (int i = 0; i < 5; i++)
    free(fields[i]);
  return false;
}
