// Minimal POSIX timer + exact per-child CPU time and peak RSS helper
// (avoids Python's fork() inheriting Python's ~19 MiB hiwater_rss on Linux,
// and records both wall_ms and single-process user+sys cpu_ms from wait4).
// Usage: measure_proc <metrics_file> <cmd> [args...]
#define _GNU_SOURCE
#include <errno.h>
#include <spawn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <metrics_file> <cmd> [args...]\n", argv[0]);
        return 2;
    }
    const char *metrics_path = argv[1];
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    pid_t pid = 0;
    int rc = posix_spawnp(&pid, argv[2], NULL, NULL, &argv[2], environ);
    if (rc != 0) {
        fprintf(stderr, "posix_spawnp(%s) failed: %d\n", argv[2], rc);
        return 127;
    }
    int status = 0;
    struct rusage ru;
    while (wait4(pid, &status, 0, &ru) < 0) {
        if (errno != EINTR) {
            perror("wait4");
            return 126;
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double wall_ms = (double)(t1.tv_sec - t0.tv_sec) * 1000.0 + (double)(t1.tv_nsec - t0.tv_nsec) / 1e6;
    double cpu_ms =
        (double)ru.ru_utime.tv_sec * 1000.0 + (double)ru.ru_utime.tv_usec / 1000.0 +
        (double)ru.ru_stime.tv_sec * 1000.0 + (double)ru.ru_stime.tv_usec / 1000.0;
    uint64_t peak_bytes = (uint64_t)ru.ru_maxrss * 1024ull;

    FILE *f = fopen(metrics_path, "w");
    if (f) {
        fprintf(f, "%.6f %.6f %llu\n", wall_ms, cpu_ms, (unsigned long long)peak_bytes);
        fclose(f);
    }
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return 1;
}
