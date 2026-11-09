/* Included after the selected, unmodified Goose runtime in one test TU. This
 * fake compiler entry exercises the production native main/worker/supervisor,
 * real registry allocation, and cache queue; no compiler algorithm lives here. */
#include "../request_supervisor.h"
#include "../request_cache.h"
#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>
extern int blot_native_main(int, char **);
extern int64_t blot_worker_spawn(uint32_t);
extern int32_t blot_worker_descriptor(uint32_t, _Bool);
extern int32_t blot_worker_stop(uint32_t);
static int stage_mode, stage_argc, events;
static char directory[PATH_MAX], target[PATH_MAX], lock_path[PATH_MAX], temporary[PATH_MAX];
struct response { uint64_t token; int pid, descendant; };
struct request { int mode, value; };
static void write_exact(int fd, const void *bytes, size_t length) {
    assert(write(fd, bytes, length) == (ssize_t)length);
}
static void actual_refusal(void) {
    struct rlimit limit = {1, 1}; assert(!setrlimit(RLIMIT_AS, &limit));
    /* Actual patched registry calloc -> observer -> production allocation_failed.
     * This models allocator resource refusal, not physical RAM exhaustion. */
    gs_regions_begin(INT64_C(1) << 30);
    abort();
}
void goose_init(int argc, char **argv) {
    stage_argc = argc;
    if (argc > 1 && !strcmp(argv[1], "--worker")) {
        assert(argc == 2 && argv[2] == NULL);
        unsigned char mode;
        assert(read(STDIN_FILENO, &mode, 1) == 1);
        stage_mode = mode;
        if (mode == 'i') actual_refusal(); /* before Goose runtime initialization */
    }
    gs_rt_start(argc, argv, GS_STACK_RESERVE, GS_STACK_GAP, GS_STACK_BUDGET, 4, 0);
}
static int stage_capability(void) {
    DIR *dir = opendir("/proc/self/fd"); assert(dir);
    int found = -1;
    struct dirent *entry;
    while ((entry = readdir(dir))) {
        int fd = atoi(entry->d_name), type = 0; socklen_t size = sizeof type;
        if (fd <= 2 || getsockopt(fd, SOL_SOCKET, SO_TYPE, &type, &size)) continue;
        if (type == SOCK_SEQPACKET) { assert(found < 0); found = fd; }
    }
    closedir(dir); return found;
}
static int stage_loop(void) {
    assert(stage_argc == 2);
    uint64_t token = blot_request_token();
    if (stage_mode == 'o') actual_refusal();
    if (stage_mode == 'p') gs_panic("ordinary worker panic");
    if (stage_mode == 'e') _exit(125);
    if (stage_mode == 'k') raise(SIGKILL);
    if (stage_mode == 's') blot_request_fail_oom(token + 1);
    int cap = stage_capability();
    if (token) assert(cap >= 0 && (fcntl(cap, F_GETFD) & FD_CLOEXEC));
    else assert(cap == -1);
    if (stage_mode == 'f') { write_exact(cap, "x", 1); return 0; }
    if (stage_mode == 'z') {
        assert(send(cap, "", 0, MSG_NOSIGNAL) == 0);
        for (;;) pause(); /* live capability: empty packet must fail immediately */
    }
    struct response response = {token, getpid(), 0};
    if (stage_mode == 'h') {
        pid_t pid = fork(); assert(pid >= 0);
        if (!pid) { for (;;) pause(); } /* holds capability: adoption must wait */
        response.descendant = pid;
    }
    if (stage_mode == 'x') {
        pid_t pid = fork(); assert(pid >= 0);
        if (!pid) {
            char fd[32]; snprintf(fd, sizeof fd, "%d", cap);
            execl("/proc/self/exe", "worker-oom-test", "--cap-probe", fd, NULL);
            _exit(123);
        }
        int status; assert(waitpid(pid, &status, 0) == pid);
        assert(WIFEXITED(status) && !WEXITSTATUS(status));
    }
    if (stage_mode == 't') { write_exact(STDOUT_FILENO, &response, 1); return 0; }
    write_exact(STDOUT_FILENO, &response, sizeof response);
    if (stage_mode == 'v') { assert(send(cap, "", 0, MSG_NOSIGNAL) == 0); return 0; }
    if (stage_mode == 'h') return 0;
    unsigned char byte;
    assert(read(STDIN_FILENO, &byte, 1) == 0);
    if (stage_mode == 'a') _exit(125);
    if (stage_mode == 'r') actual_refusal(); /* response-before-cleanup race */
    return 0;
}
static int spool(const void *bytes, size_t length) {
    int fd = memfd_create("worker-oom-test", MFD_CLOEXEC); assert(fd >= 0);
    write_exact(fd, bytes, length); return fd;
}
static void stage_cache(int value) {
    char bytes[32]; int length = snprintf(bytes, sizeof bytes, "%d", value);
    assert(!blot_request_cache_stage_write(0,
        (uint8_t *)directory, strlen(directory), (uint8_t *)lock_path, strlen(lock_path),
        (uint8_t *)target, strlen(target), (uint8_t *)temporary, strlen(temporary),
        (uint8_t *)bytes, (uint64_t)length));
}
static struct response read_response(int fd) {
    struct response result = {0}; size_t at = 0;
    while (at < sizeof result) {
        ssize_t count = read(fd, (char *)&result + at, sizeof result - at);
        if (count <= 0) blot_request_fail(blot_request_token());
        at += (size_t)count;
    }
    return result;
}
static pid_t idle_stage(void) {
    int64_t pid = blot_worker_spawn(0); assert(pid > 0);
    unsigned char mode = 'g'; write_exact(blot_worker_descriptor(0, 1), &mode, 1);
    struct response reply = read_response(blot_worker_descriptor(0, 0));
    assert(!reply.token && reply.pid == pid);
    write_exact(events, &reply, sizeof reply);
    return (pid_t)pid;
}
static void committed_loop(void) {
    int *counter = malloc(sizeof *counter); assert(counter); *counter = 0;
    for (;;) {
        idle_stage(); /* baseline capability must never carry a later token */
        if (blot_request_begin()) _exit(0);
        assert(blot_worker_descriptor(0, 0) == -EBADF);
        struct request request;
        assert(read(blot_request_input_fd(), &request, sizeof request) == sizeof request);
        uint64_t token = blot_request_token(); assert(token);
        if (request.value >= 0) *counter = request.value;
        stage_cache(*counter);
        int64_t pid = blot_worker_spawn(0); assert(pid > 0);
        unsigned char mode = (unsigned char)request.mode;
        write_exact(blot_worker_descriptor(0, 1), &mode, 1);
        struct response response = read_response(blot_worker_descriptor(0, 0));
        assert(response.token == token && response.pid == pid);
        write_exact(events, &response, sizeof response);
        int fd = spool(counter, sizeof *counter);
        assert(!blot_request_finish(fd, sizeof *counter, token));
        close(fd); assert(!blot_request_token() && !blot_request_cache_pending());
    }
}
static int fd_count(void) {
    DIR *dir = opendir("/proc/self/fd"); assert(dir); int count = 0;
    while (readdir(dir)) count++;
    closedir(dir); return count;
}
static uint64_t token;
static int submit(int mode, int value) {
    struct request request = {mode, value}; int fd = spool(&request, sizeof request);
    int result = blot_request_submit(fd, sizeof request, ++token); close(fd); return result;
}
static struct response event(int fd) {
    struct response value; assert(read(fd, &value, sizeof value) == sizeof value); return value;
}
static void absent(pid_t pid) { assert(kill(pid, 0) < 0 && errno == ESRCH); }
static void value_is(int value) {
    int actual = -1;
    assert(pread(blot_request_reply_fd(), &actual, sizeof actual, 0) == sizeof actual && actual == value);
    char actual_cache[32] = {0}, expected[32];
    int length = snprintf(expected, sizeof expected, "%d", value);
    int fd = open(target, O_RDONLY); assert(fd >= 0);
    assert(read(fd, actual_cache, sizeof actual_cache) == length && !memcmp(expected, actual_cache, (size_t)length));
    close(fd);
}
int32_t blot_goose_main(void) {
    if (stage_mode) return stage_loop();
    char name[] = "/tmp/blot-worker-oom-XXXXXX"; assert(mkdtemp(name));
    snprintf(directory, sizeof directory, "%s", name);
    snprintf(target, sizeof target, "%s/value", name);
    snprintf(lock_path, sizeof lock_path, "%s/key.lock", name);
    snprintf(temporary, sizeof temporary, "%s/value.partial", name);
    struct rlimit core = {0}; assert(!setrlimit(RLIMIT_CORE, &core));
    int pipefd[2], capture[2]; assert(!pipe2(pipefd, O_CLOEXEC)); events = pipefd[1];
    assert(!pipe2(capture, O_CLOEXEC | O_NONBLOCK));
    int saved_stdout = dup(STDOUT_FILENO); assert(saved_stdout >= 0);
    assert(dup2(capture[1], STDOUT_FILENO) >= 0); close(capture[1]);
    int before = fd_count();
    int role = blot_request_start(1024, 1024, 500); assert(role >= 0);
    if (role == BLOT_REQUEST_WORKER) committed_loop();
    pid_t baseline = event(pipefd[0]).pid;
    assert(submit('g', 7) == BLOT_REQUEST_ACCEPTED); value_is(7); absent(baseline);
    struct response response = event(pipefd[0]); absent(response.pid);
    baseline = event(pipefd[0]).pid;
    int stable = fd_count();
    const char modes[] = {'i', 'o', 'r', 'e', 'p', 'k', 't', 's', 'f', 'z', 'v', 'a', 'h'};
    for (size_t n = 0; n < sizeof modes; ++n) {
        int expected = BLOT_REQUEST_FAILED;
        if (n < 3) expected = BLOT_REQUEST_OOM;
        if (modes[n] == 'h') expected = BLOT_REQUEST_TIMEOUT;
        int actual = submit(modes[n], 999);
        if (actual != expected) {
            dprintf(STDERR_FILENO, "mode %c: got %d, expected %d\n", modes[n], actual, expected);
            blot_request_stop(); abort();
        }
        assert(blot_request_reply_fd() == -1 && kill(baseline, 0) == 0);
        int fd = open(target, O_RDONLY); assert(fd >= 0); char byte;
        assert(read(fd, &byte, 1) == 1 && byte == '7'); close(fd);
        assert(access(temporary, F_OK) < 0); /* staged candidate cache never published */
        if (modes[n] == 'r' || modes[n] == 'h' || modes[n] == 'v' || modes[n] == 'a') {
            response = event(pipefd[0]); absent(response.pid);
            if (response.descendant) absent(response.descendant);
        }
        assert(submit('x', -1) == BLOT_REQUEST_ACCEPTED); value_is(7); absent(baseline);
        response = event(pipefd[0]); absent(response.pid);
        baseline = event(pipefd[0]).pid;
        assert(fd_count() == stable);
    }
    assert(submit('g', 8) == BLOT_REQUEST_ACCEPTED); value_is(8); absent(baseline);
    response = event(pipefd[0]); absent(response.pid); baseline = event(pipefd[0]).pid;
    blot_request_stop(); absent(baseline);
    assert(fd_count() == before);
    int status; assert(waitpid(-1, &status, WNOHANG) == -1 && errno == ECHILD);
    char byte; assert(read(capture[0], &byte, 1) < 0 && errno == EAGAIN);
    assert(dup2(saved_stdout, STDOUT_FILENO) >= 0);
    close(saved_stdout); close(capture[0]); close(pipefd[0]); close(pipefd[1]);
    unlink(target); unlink(lock_path); assert(!rmdir(directory));
    puts("worker OOM: real allocator refusal before/init/after reply, retained heap/cache, generic failures, token/capability closure, FD/stdout/zombie cleanup pass");
    return 0;
}
int main(int argc, char **argv) {
    if (argc == 3 && !strcmp(argv[1], "--cap-probe")) {
        assert(fcntl(atoi(argv[2]), F_GETFD) < 0 && errno == EBADF); return 0;
    }
    return blot_native_main(argc, argv);
}
