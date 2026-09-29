#define _GNU_SOURCE
#include <caml/mlvalues.h>

#ifdef __linux__
#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <sched.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <unistd.h>

static void normal_priority(pid_t tid) {
  if (sched_getscheduler(tid) == SCHED_IDLE) {
    struct sched_param parameter = { .sched_priority = 0 };
    (void)sched_setscheduler(tid, SCHED_OTHER, &parameter);
  }
  errno = 0;
  int nice_value = getpriority(PRIO_PROCESS, (id_t)tid);
  if (errno == 0 && nice_value > 0)
    (void)setpriority(PRIO_PROCESS, (id_t)tid, 0);
#if defined(SYS_ioprio_get) && defined(SYS_ioprio_set)
  long priority = syscall(SYS_ioprio_get, 1, tid);
  if (priority >= 0 && (priority >> 13) == 3)
    (void)syscall(SYS_ioprio_set, 1, tid, (2 << 13) | 4);
#endif
}
#endif

CAMLprim value caml_blot_configure(value inherit) {
#ifdef __linux__
  if (!Bool_val(inherit)) {
    /* Configure the caller first so subsequently created runtime threads
       inherit it; then cover helper threads already started by the runtime. */
    normal_priority(0);
    DIR *directory = opendir("/proc/self/task");
    if (directory != NULL) {
      struct dirent *entry;
      while ((entry = readdir(directory)) != NULL) {
        char *end;
        long tid = strtol(entry->d_name, &end, 10);
        if (*entry->d_name != '\0' && *end == '\0' && tid > 0 && tid <= INT_MAX)
          normal_priority((pid_t)tid);
      }
      closedir(directory);
    }
  }
#else
  (void)inherit;
#endif
  return Val_unit;
}
