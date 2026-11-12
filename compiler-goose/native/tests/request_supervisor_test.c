#define _GNU_SOURCE
#include "../request_supervisor.h"
#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

/* Exercises the production module with a retained native heap value, rather
 * than modelling rollback in a separate implementation. */
enum { SET, GET, MARKED_OOM, ABORT, EXIT, KILL, SHORT_REPLY, WRONG_TOKEN, TIMEOUT, SLOW };
struct request { int op, value; };
extern void blot_platform_entry_init(int argc, char **argv);
extern int64_t blot_worker_spawn(uint32_t slot);
extern int32_t blot_worker_descriptor(uint32_t slot, _Bool writing);
extern int32_t blot_worker_stop(uint32_t slot);
extern void blot_worker_detach(void);
static int stage_pid, stage_handle = -1, events, interrupt_fork, publication;
static pid_t expected_supervisor;
static void publish_after_adoption(void) {
    assert(getppid() == expected_supervisor);
    uint64_t token = blot_request_token();
    assert(pwrite(publication, &token, sizeof token, 0) == sizeof token);
}
static void detach_stage(void) {
    blot_worker_detach();
    stage_handle = -1; stage_pid = 0;
    if (interrupt_fork) {
        pid_t pid = getpid(); assert(write(events, &pid, sizeof pid) == sizeof pid);
        for (;;) pause();
    }
}
static int spool_bytes(const void *data, size_t length) {
    int fd = memfd_create("supervisor-test", MFD_CLOEXEC);
    assert(fd >= 0 && write(fd, data, length) == (ssize_t)length);
    return fd;
}
static void report_pid(pid_t pid) { assert(write(events, &pid, sizeof pid) == sizeof pid); }
static pid_t receive_pid(int fd) { pid_t pid; assert(read(fd, &pid, sizeof pid) == sizeof pid); return pid; }
static void worker_loop(void) {
    int *counter = malloc(sizeof *counter); assert(counter); *counter = 0;
    for (;;) {
        /* Baseline-owned stage workers must survive a rejected candidate. */
        if (!stage_pid) {
            stage_pid = (int)blot_worker_spawn(0); assert(stage_pid > 0);
            stage_handle = blot_worker_descriptor(0, 1); assert(stage_handle >= 0);
            char sent = 'a', received = 0;
            assert(write(stage_handle, &sent, 1) == 1);
            assert(read(blot_worker_descriptor(0, 0), &received, 1) == 1 && received == sent);
            report_pid(stage_pid);
        }
        if (blot_request_begin()) _exit(0);
        assert(!stage_pid && stage_handle == -1); /* child hook detached handles */
        assert(blot_worker_descriptor(0, 0) == -EBADF && blot_worker_stop(0) == 0);
        struct request request;
        assert(blot_request_input_length() == sizeof request);
        assert(read(blot_request_input_fd(), &request, sizeof request) == sizeof request);
        assert(fcntl(blot_request_input_fd(), F_GET_SEALS) & F_SEAL_WRITE);
        assert(write(blot_request_input_fd(), "x", 1) < 0 && errno == EPERM);
        uint64_t token = blot_request_token();
        if (request.op != GET) *counter = request.value;
        /* An accidental compiler write cannot leak a partial protocol reply. */
        assert(write(STDOUT_FILENO, "PARTIAL", 7) == 7);
        if (request.op == MARKED_OOM) {
            pid_t child = fork(); assert(child >= 0);
            if (!child) { for (;;) pause(); }
            report_pid(child);
            blot_request_fail_oom(token);
        }
        if (request.op == ABORT) abort();
        if (request.op == EXIT) _exit(0);
        if (request.op == KILL) raise(SIGKILL);
        if (request.op == WRONG_TOKEN) blot_request_fail_oom(token + 1);
        if (request.op == TIMEOUT) { for (;;) pause(); }
        if (request.op == SLOW) { struct timespec pause_for = { 0, 600000000 }; while (nanosleep(&pause_for, &pause_for)) {} }
        int fd = spool_bytes(counter, sizeof *counter);
        uint64_t length = sizeof *counter;
        if (request.op == SHORT_REPLY) length++;
        /* This point represents completed request cleanup. */
        assert(blot_request_finish(fd, length, token) == 0);
        assert(blot_request_token() == 0);
        close(fd);
    }
}
static int fd_count(void) {
    DIR *dir = opendir("/proc/self/fd"); assert(dir);
    int count = 0; while (readdir(dir)) count++;
    closedir(dir); return count;
}
static uint64_t token, accepted_token;
static int32_t reject_reply(int32_t fd, uint64_t length, uint64_t request_token) {
    (void)fd; (void)length; (void)request_token; return -EPROTO;
}
static int submit(int op, int value) {
    struct request request = { op, value };
    int fd = spool_bytes(&request, sizeof request);
    int result = blot_request_submit(fd, sizeof request, ++token);
    close(fd); assert(blot_request_token() == 0);
    if (result == BLOT_REQUEST_ACCEPTED) accepted_token = token; return result;
}
static void expect_value(int value) {
    assert(blot_request_reply_length() == sizeof value);
    int actual = -1;
    assert(pread(blot_request_reply_fd(), &actual, sizeof actual, 0) == sizeof actual);
    assert(actual == value);
    uint64_t published = 0;
    assert(pread(publication, &published, sizeof published, 0) == sizeof published && published == accepted_token);
    assert(write(blot_request_reply_fd(), "x", 1) < 0 && errno == EPERM);
}
static void absent(pid_t pid) { assert(kill(pid, 0) < 0 && errno == ESRCH); }
int main(int argc, char **argv) {
    blot_platform_entry_init(argc, argv);
    if (argc > 1) {
        char byte;
        while (read(STDIN_FILENO, &byte, 1) == 1) assert(write(STDOUT_FILENO, &byte, 1) == 1);
        return 0;
    }
    struct rlimit core = {0}; assert(!setrlimit(RLIMIT_CORE, &core));
    int capture[2], event_pipe[2]; assert(!pipe2(capture, O_CLOEXEC | O_NONBLOCK));
    assert(!pipe2(event_pipe, O_CLOEXEC)); events = event_pipe[1];
    int stdout_copy = dup(STDOUT_FILENO); assert(stdout_copy >= 0);
    assert(dup2(capture[1], STDOUT_FILENO) >= 0); close(capture[1]);
    uint64_t unpublished = 0; publication = spool_bytes(&unpublished, sizeof unpublished);
    int initial_fds = fd_count(); expected_supervisor = getpid();
    blot_request_fork_hook(detach_stage);
    blot_request_adopt_hook(publish_after_adoption);
    int role = blot_request_start(1024, 1024, 250); assert(role >= 0);
    if (role == BLOT_REQUEST_WORKER) worker_loop();
    pid_t initial_stage = receive_pid(event_pipe[0]);
    assert(submit(SET, 7) == BLOT_REQUEST_ACCEPTED); expect_value(7);
    pid_t retained_stage = receive_pid(event_pipe[0]); absent(initial_stage);
    int stable_fds = fd_count();
    uint64_t committed_token = token;
    assert(submit(MARKED_OOM, 999) == BLOT_REQUEST_OOM);
    uint64_t published = 0;
    assert(pread(publication, &published, sizeof published, 0) == sizeof published && published == committed_token);
    pid_t rejected_child = receive_pid(event_pipe[0]); absent(rejected_child);
    assert(kill(retained_stage, 0) == 0);
    assert(blot_request_reply_fd() == -1); /* no partial reply */
    assert(submit(GET, 0) == BLOT_REQUEST_ACCEPTED); expect_value(7);
    absent(retained_stage); retained_stage = receive_pid(event_pipe[0]);
    blot_request_reply_validator(reject_reply);
    assert(submit(SET, 999) == BLOT_REQUEST_FAILED && kill(retained_stage, 0) == 0);
    blot_request_reply_validator(NULL);
    assert(submit(GET, 0) == BLOT_REQUEST_ACCEPTED); expect_value(7);
    absent(retained_stage); retained_stage = receive_pid(event_pipe[0]);
    int failures[] = { SHORT_REPLY, ABORT, EXIT, KILL, WRONG_TOKEN, TIMEOUT };
    for (unsigned i = 0; i < sizeof failures / sizeof failures[0]; i++) {
        int expected = BLOT_REQUEST_FAILED;
        if (failures[i] == TIMEOUT) expected = BLOT_REQUEST_TIMEOUT;
        assert(submit(failures[i], 999) == expected);
        assert(blot_request_reply_fd() == -1 && kill(retained_stage, 0) == 0);
        assert(submit(GET, 0) == BLOT_REQUEST_ACCEPTED); expect_value(7);
        absent(retained_stage); retained_stage = receive_pid(event_pipe[0]);
        assert(fd_count() == stable_fds);
    }
    for (int i = 0; i < 100; i++) {
        assert(submit(SET, i) == BLOT_REQUEST_ACCEPTED); expect_value(i);
        absent(retained_stage); retained_stage = receive_pid(event_pipe[0]);
        assert(fd_count() == stable_fds);
    }
    int fd = spool_bytes("x", 1);
    assert(blot_request_submit(fd, 1025, ++token) == -EFBIG);
    close(fd); expect_value(99); /* invalid input never starts a transaction */
    blot_request_stop(); absent(retained_stage);
    assert(fd_count() == initial_fds);
    int status; assert(waitpid(-1, &status, WNOHANG) == -1 && errno == ECHILD);
    /* Cancellation between fork and GO must not leave a candidate behind. */
    pid_t supervisor = fork(); assert(supervisor >= 0);
    if (!supervisor) {
        interrupt_fork = 1;
        int nested_role = blot_request_start(1024, 1024, 250); assert(nested_role >= 0);
        if (nested_role == BLOT_REQUEST_WORKER) {
            report_pid(getpid()); blot_request_begin(); _exit(123);
        }
        submit(GET, 0); _exit(123);
    }
    pid_t baseline = receive_pid(event_pipe[0]);
    pid_t candidate = receive_pid(event_pipe[0]);
    assert(kill(supervisor, SIGKILL) == 0);
    assert(waitpid(supervisor, &status, 0) == supervisor && WIFSIGNALED(status));
    assert(waitpid(baseline, &status, 0) == baseline && WIFSIGNALED(status));
    assert(waitpid(candidate, &status, 0) == candidate && WIFSIGNALED(status));
    assert(waitpid(-1, &status, WNOHANG) == -1 && errno == ECHILD);
    assert(fd_count() == initial_fds);
    /* A zero limit leaves computation unbounded: a request slower than the
     * 250 ms limit above is still adopted. */
    pid_t unbounded = fork(); assert(unbounded >= 0);
    if (!unbounded) {
        expected_supervisor = getpid();
        int unbounded_role = blot_request_start(1024, 1024, 0); assert(unbounded_role >= 0);
        if (unbounded_role == BLOT_REQUEST_WORKER) worker_loop();
        receive_pid(event_pipe[0]);
        assert(submit(SLOW, 5) == BLOT_REQUEST_ACCEPTED); expect_value(5);
        blot_request_stop(); _exit(0);
    }
    assert(waitpid(unbounded, &status, 0) == unbounded && WIFEXITED(status) && !WEXITSTATUS(status));
    char byte; assert(read(capture[0], &byte, 1) == -1 && errno == EAGAIN);
    assert(dup2(stdout_copy, STDOUT_FILENO) >= 0);
    close(stdout_copy); close(capture[0]); close(event_pipe[0]); close(event_pipe[1]); close(publication);
    puts("request supervisor: retained heap, classified failures, unbounded computation, immutable spools, stdout/FD/child cleanup pass");
}
