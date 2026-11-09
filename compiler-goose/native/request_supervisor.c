#define _GNU_SOURCE
#include "request_supervisor.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stddef.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

/* SOCK_SEQPACKET makes each control record atomic; ancillary FDs never carry
 * compiler data. Only immutable, size-checked memfds cross this boundary. */
enum { BEGIN = 1, FORKED, GO, FINISH, OOM, FAILED, ADOPT, READY, COMMIT, QUIESCENT, KEEP, IDLE };
struct record {
    uint64_t magic, token, length;
    int32_t kind, pid;
};
_Static_assert(sizeof(struct record) == 32, "fixed control record");
static const uint64_t magic = UINT64_C(0x424c4f5452583031);
static int channel = -1, input = -1, reply = -1, worker = -1, role = -1;
static uint64_t request_bound, reply_bound, active_token, input_length, reply_length;
static uint32_t limit_ms;
static pid_t supervisor_pid;
static void (*fork_hook)(void);
static void (*adopt_hook)(void);
static int32_t (*reply_validator)(int32_t, uint64_t, uint64_t);

void blot_request_fork_hook(void (*hook)(void)) { fork_hook = hook; }
void blot_request_adopt_hook(void (*hook)(void)) { adopt_hook = hook; }
void blot_request_reply_validator(int32_t (*validate)(int32_t, uint64_t, uint64_t)) {
    reply_validator = validate;
}
static void close_fd(int *fd) { if (*fd >= 0) close(*fd); *fd = -1; }
static int64_t milliseconds(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now)) return 0;
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}
static int send_record(int fd, int kind, uint64_t token, uint64_t length, int pid, int pass) {
    struct record r = { magic, token, length, kind, pid };
    struct iovec io = { &r, sizeof r };
    char ancillary[CMSG_SPACE(sizeof(int))] = {0};
    struct msghdr msg = { .msg_iov = &io, .msg_iovlen = 1 };
    if (pass >= 0) {
        msg.msg_control = ancillary; msg.msg_controllen = sizeof ancillary;
        struct cmsghdr *c = CMSG_FIRSTHDR(&msg);
        c->cmsg_level = SOL_SOCKET; c->cmsg_type = SCM_RIGHTS;
        c->cmsg_len = CMSG_LEN(sizeof(int));
        memcpy(CMSG_DATA(c), &pass, sizeof pass);
    }
    ssize_t n;
    do { n = sendmsg(fd, &msg, MSG_NOSIGNAL); } while (n < 0 && errno == EINTR);
    if (n < 0) return -errno;
    if (n != sizeof r) return -EPROTO;
    return 0;
}
static int receive(int fd, struct record *r, int *received, int64_t deadline) {
    *received = -1;
    for (;;) {
        int timeout = -1;
        if (deadline) {
            int64_t remaining = deadline - milliseconds();
            if (remaining <= 0) return -ETIMEDOUT;
            timeout = INT_MAX;
            if (remaining < INT_MAX) timeout = (int)remaining;
        }
        struct pollfd p = { .fd = fd, .events = POLLIN };
        int ready = poll(&p, 1, timeout);
        if (ready < 0 && errno == EINTR) continue;
        if (ready < 0) return -errno;
        if (!ready) return -ETIMEDOUT;
        char ancillary[CMSG_SPACE(sizeof(int) * 8)] = {0};
        struct iovec io = { r, sizeof *r };
        struct msghdr msg = { .msg_iov = &io, .msg_iovlen = 1,
                              .msg_control = ancillary, .msg_controllen = sizeof ancillary };
        ssize_t n = recvmsg(fd, &msg, MSG_CMSG_CLOEXEC);
        if (n < 0 && errno == EINTR) continue;
        int count = 0;
        for (struct cmsghdr *c = CMSG_FIRSTHDR(&msg); c; c = CMSG_NXTHDR(&msg, c)) {
            if (c->cmsg_level != SOL_SOCKET || c->cmsg_type != SCM_RIGHTS) continue;
            size_t bytes = c->cmsg_len - CMSG_LEN(0);
            for (size_t i = 0; i + sizeof(int) <= bytes; i += sizeof(int)) {
                int value; memcpy(&value, (char *)CMSG_DATA(c) + i, sizeof value);
                if (count++ == 0) *received = value;
                else close(value);
            }
        }
        if (n != sizeof *r || (msg.msg_flags & (MSG_TRUNC | MSG_CTRUNC)) ||
            count > 1 || r->magic != magic) {
            close_fd(received); return -EPROTO;
        }
        return 0;
    }
}
static int immutable(int fd, uint64_t length, uint64_t bound) {
    struct stat st;
    if (length > bound || length > INT64_MAX) return -EFBIG;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_size < 0 ||
        (uint64_t)st.st_size != length) return -EINVAL;
    int seals = fcntl(fd, F_GET_SEALS);
    int required = F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL;
    if (seals < 0 || (seals & required) != required) return -EINVAL;
    return 0;
}
static int spool(int source, uint64_t length, uint64_t bound) {
    struct stat st;
    if (length > bound || length > INT64_MAX) return -EFBIG;
    if (fstat(source, &st) || !S_ISREG(st.st_mode) || st.st_size < 0 ||
        (uint64_t)st.st_size != length) return -EINVAL;
    int fd = memfd_create("blot-request", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (fd < 0) return -errno;
    uint8_t buffer[16384];
    uint64_t offset = 0;
    while (offset < length) {
        size_t count = sizeof buffer;
        if (length - offset < count) count = (size_t)(length - offset);
        ssize_t n = pread(source, buffer, count, (off_t)offset);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { close(fd); return -EIO; }
        ssize_t written = 0;
        while (written < n) {
            ssize_t amount = write(fd, buffer + written, (size_t)(n - written));
            if (amount < 0 && errno == EINTR) continue;
            if (amount <= 0) { close(fd); return -EIO; }
            written += amount;
        }
        offset += (uint64_t)n;
    }
    if (fcntl(fd, F_ADD_SEALS, F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL) ||
        lseek(fd, 0, SEEK_SET) < 0) { int error = errno; close(fd); return -error; }
    return fd;
}
static void reap(int pid) {
    int status;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
}
static void kill_group(int pid) { if (pid > 0) { kill(-pid, SIGKILL); kill(pid, SIGKILL); } }
static void reap_group(int pid) {
    int status;
    for (;;) {
        pid_t reaped = waitpid(-pid, &status, WNOHANG);
        if (reaped > 0 || (reaped < 0 && errno == EINTR)) continue;
        if (reaped < 0) return;
        /* A child forked during the first group kill may have survived that
         * snapshot. Its group remains pinned by our unreaped child. */
        kill(-pid, SIGKILL);
        do { reaped = waitpid(-pid, &status, 0); } while (reaped < 0 && errno == EINTR);
        if (reaped < 0) return;
    }
}
int32_t blot_request_start(uint64_t max_request, uint64_t max_reply, uint32_t timeout_ms) {
    if (role >= 0 || !max_request || !max_reply || !timeout_ms ||
        max_request > INT64_MAX || max_reply > INT64_MAX) return -EINVAL;
    if (prctl(PR_SET_CHILD_SUBREAPER, 1)) return -errno;
    int pair[2];
    if (socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, pair)) return -errno;
    request_bound = max_request; reply_bound = max_reply; limit_ms = timeout_ms;
    supervisor_pid = getpid(); active_token = 0; input_length = 0; reply_length = 0;
    pid_t pid = fork();
    if (pid < 0) { int error = errno; close(pair[0]); close(pair[1]); return -error; }
    if (!pid) {
        close(pair[0]); channel = pair[1]; role = BLOT_REQUEST_WORKER;
        if (setpgid(0, 0) || prctl(PR_SET_PDEATHSIG, SIGKILL) ||
            getppid() != supervisor_pid) _exit(120);
        int null = open("/dev/null", O_WRONLY | O_CLOEXEC);
        if (null < 0 || dup2(null, STDOUT_FILENO) < 0) _exit(120);
        if (null != STDOUT_FILENO) close(null);
        return role;
    }
    close(pair[1]); setpgid(pid, pid); channel = pair[0]; worker = pid;
    role = BLOT_REQUEST_SUPERVISOR; return role;
}
int32_t blot_request_reply_fd(void) { return reply; }
uint64_t blot_request_reply_length(void) { return reply_length; }
int32_t blot_request_input_fd(void) { return input; }
uint64_t blot_request_input_length(void) { return input_length; }
uint64_t blot_request_token(void) {
    if (role != BLOT_REQUEST_WORKER) return 0;
    return active_token;
}
void blot_request_stop(void) {
    if (role == BLOT_REQUEST_SUPERVISOR) { kill_group(worker); reap(worker); reap_group(worker); }
    close_fd(&channel); close_fd(&input); close_fd(&reply);
    worker = -1; role = -1;
}
int32_t blot_request_begin(void) {
    if (role != BLOT_REQUEST_WORKER || input >= 0) return -EINVAL;
    for (;;) {
        struct record r; int fd;
        int error = receive(channel, &r, &fd, 0);
        if (error) return error;
        if (r.kind != BEGIN || fd >= 0 || !r.token) { close_fd(&fd); return -EPROTO; }
        int pair[2];
        if (socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, pair)) {
            if (send_record(channel, FAILED, r.token, 0, 0, -1)) return -EPIPE;
            continue;
        }
        pid_t baseline = getpid();
        pid_t pid = fork();
        if (pid < 0) {
            close(pair[0]); close(pair[1]);
            if (send_record(channel, FAILED, r.token, 0, 0, -1)) return -EPIPE;
            continue;
        }
        if (!pid) {
            close(pair[0]); close_fd(&channel); channel = pair[1];
            if (setpgid(0, 0) || prctl(PR_SET_PDEATHSIG, SIGKILL) ||
                getppid() != baseline) _exit(120);
            active_token = r.token;
            if (fork_hook) fork_hook();
            error = receive(channel, &r, &fd, 0);
            if (error || r.kind != GO || r.token != active_token ||
                fd < 0 || immutable(fd, r.length, request_bound)) _exit(120);
            input = fd; input_length = r.length;
            return 0;
        }
        close(pair[1]); setpgid(pid, pid);
        error = send_record(channel, FORKED, r.token, 0, pid, pair[0]);
        close(pair[0]);
        if (!error) error = receive(channel, &r, &fd, 0);
        close_fd(&fd);
        if (error || r.kind != KEEP) { kill_group(pid); reap(pid); return -EPROTO; }
        kill_group(pid); reap(pid);
        if (send_record(channel, IDLE, r.token, 0, 0, -1)) return -EPIPE;
    }
}
_Noreturn void blot_request_fail_oom(uint64_t token) {
    send_record(channel, OOM, token, 0, 0, -1); _exit(121);
}
_Noreturn void blot_request_fail(uint64_t token) {
    send_record(channel, FAILED, token, 0, 0, -1); _exit(122);
}
int32_t blot_request_finish(int32_t reply_fd, uint64_t length, uint64_t token) {
    if (role != BLOT_REQUEST_WORKER || input < 0 || token != active_token)
        blot_request_fail(token);
    int staged = spool(reply_fd, length, reply_bound);
    close_fd(&input); input_length = 0;
    if (staged < 0) blot_request_fail(token);
    int error = send_record(channel, FINISH, token, length, 0, staged);
    close(staged);
    struct record r; int fd = -1;
    if (!error) error = receive(channel, &r, &fd, 0);
    close_fd(&fd);
    if (error || r.kind != ADOPT || r.token != token) _exit(122);
    /* Baseline retirement reparents us to the supervisor. Clear the old
     * parent-death binding only while blocked on that supervisor's socket. */
    if (prctl(PR_SET_PDEATHSIG, 0) || send_record(channel, READY, token, 0, 0, -1))
        { kill_group(getpid()); _exit(122); }
    error = receive(channel, &r, &fd, 0);
    close_fd(&fd);
    if (error || r.kind != COMMIT || r.token != token ||
        prctl(PR_SET_PDEATHSIG, SIGKILL) || getppid() != supervisor_pid)
        { kill_group(getpid()); _exit(122); }
    if (adopt_hook) adopt_hook();
    if (send_record(channel, QUIESCENT, token, 0, 0, -1)) { kill_group(getpid()); _exit(122); }
    active_token = 0;
    return 0;
}
int32_t blot_request_submit(int32_t request_fd, uint64_t length, uint64_t token) {
    if (role != BLOT_REQUEST_SUPERVISOR || !token || token <= active_token || worker <= 0)
        return -EINVAL;
    int request = spool(request_fd, length, request_bound);
    if (request < 0) return request;
    close_fd(&reply); reply_length = 0; active_token = token;
    int64_t deadline = milliseconds() + limit_ms;
    int error = send_record(channel, BEGIN, token, 0, 0, -1);
    struct record r; int candidate_channel = -1, candidate = -1;
    if (!error) error = receive(channel, &r, &candidate_channel, deadline);
    if (!error && r.kind == FAILED && r.token == token && candidate_channel < 0) {
        close(request); return BLOT_REQUEST_FAILED;
    }
    if (!error && (r.kind != FORKED || r.token != token || r.pid <= 0 || candidate_channel < 0))
        error = -EPROTO;
    if (error) {
        close(request); close_fd(&candidate_channel);
        /* A lost baseline transport is terminal; it cannot promise rollback. */
        blot_request_stop(); return -EPIPE;
    }
    candidate = r.pid;
    error = send_record(candidate_channel, GO, token, length, 0, request);
    close(request);
    int result = BLOT_REQUEST_FAILED, returned = -1;
    if (!error) error = receive(candidate_channel, &r, &returned, deadline);
    if (error == -ETIMEDOUT) result = BLOT_REQUEST_TIMEOUT;
    if (!error && r.token == token && r.kind == OOM && returned < 0 && !r.length)
        result = BLOT_REQUEST_OOM;
    if (!error && r.token == token && r.kind == FINISH && returned >= 0 &&
        !immutable(returned, r.length, reply_bound) &&
        (!reply_validator || !reply_validator(returned, r.length, token))) {
        uint64_t complete_length = r.length;
        error = send_record(candidate_channel, ADOPT, token, 0, 0, -1);
        int extra = -1;
        if (!error) error = receive(candidate_channel, &r, &extra, deadline);
        if (!error && r.kind == READY && r.token == token && extra < 0) {
            kill_group(worker); reap(worker); reap_group(worker);
            close_fd(&channel); channel = candidate_channel; worker = candidate;
            reply = returned; reply_length = complete_length;
            error = send_record(channel, COMMIT, token, 0, 0, -1);
            if (!error) error = receive(channel, &r, &extra, milliseconds() + limit_ms);
            int invalid_fd = extra >= 0;
            close_fd(&extra);
            if (error || r.kind != QUIESCENT || r.token != token || invalid_fd) {
                blot_request_stop(); return -EPIPE;
            }
            return BLOT_REQUEST_ACCEPTED;
        }
        close_fd(&extra);
        if (error == -ETIMEDOUT) result = BLOT_REQUEST_TIMEOUT;
    }
    close_fd(&returned); close_fd(&candidate_channel);
    kill_group(candidate);
    error = send_record(channel, KEEP, token, 0, 0, -1);
    int extra = -1;
    if (!error) error = receive(channel, &r, &extra, milliseconds() + limit_ms);
    close_fd(&extra); reap_group(candidate);
    if (error || r.kind != IDLE || r.token != token) { blot_request_stop(); return -EPIPE; }
    return result;
}
