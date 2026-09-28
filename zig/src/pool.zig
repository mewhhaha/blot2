//! A bounded, persistent fork/join pool. Waiters execute queued work so nested
//! joins cannot consume every worker while their children wait in the queue.
//! Jobs borrow caller storage; wait() is the lifetime boundary for that storage.
const std = @import("std");

pub const Job = struct {
    run: *const fn (*anyopaque) void,
    data: *anyopaque,
    next: ?*Job = null,
    // Protected by Pool.mutex, including the completion publication.
    done: bool = false,
};

pub const Pool = struct {
    mutex: std.c.pthread_mutex_t = std.c.PTHREAD_MUTEX_INITIALIZER,
    changed: std.c.pthread_cond_t = std.c.PTHREAD_COND_INITIALIZER,
    head: ?*Job = null,
    stopping: bool = false,
    workers: [63]std.Thread = undefined,
    worker_count: usize = 0,
    worker_jobs: std.atomic.Value(u64) = .init(0),

    /// The calling thread is included in `threads`. Keep this Pool at a stable
    /// address from start() until deinit(); workers retain its address.
    pub fn start(self: *Pool, threads: usize) !void {
        if (threads == 0 or threads > self.workers.len + 1) return error.InvalidThreadCount;
        errdefer self.deinit();
        while (self.worker_count < threads - 1) {
            self.workers[self.worker_count] = try std.Thread.spawn(
                .{ .stack_size = 64 * 1024 * 1024 },
                worker,
                .{self},
            );
            self.worker_count += 1;
        }
    }

    pub fn deinit(self: *Pool) void {
        self.lock();
        std.debug.assert(self.head == null);
        self.stopping = true;
        check(std.c.pthread_cond_broadcast(&self.changed));
        self.unlock();
        for (self.workers[0..self.worker_count]) |thread| thread.join();
        self.worker_count = 0;
        check(std.c.pthread_cond_destroy(&self.changed));
        check(std.c.pthread_mutex_destroy(&self.mutex));
    }

    pub fn submit(self: *Pool, job: *Job) void {
        self.lock();
        defer self.unlock();
        std.debug.assert(!self.stopping and self.worker_count > 0);
        job.done = false;
        job.next = self.head;
        self.head = job;
        check(std.c.pthread_cond_signal(&self.changed));
    }

    pub fn wait(self: *Pool, target: *Job) void {
        self.lock();
        defer self.unlock();
        while (!target.done) {
            if (self.pop()) |job| {
                self.unlock();
                self.execute(job);
                self.lock();
            } else {
                check(std.c.pthread_cond_wait(&self.changed, &self.mutex));
            }
        }
    }

    fn pop(self: *Pool) ?*Job {
        const job = self.head orelse return null;
        self.head = job.next;
        return job;
    }

    fn execute(self: *Pool, job: *Job) void {
        job.run(job.data);
        self.lock();
        job.done = true;
        // Do not access job after unlocking: wait() may return and end its life.
        check(std.c.pthread_cond_broadcast(&self.changed));
        self.unlock();
    }

    fn worker(self: *Pool) void {
        self.lock();
        defer self.unlock();
        while (true) {
            if (self.pop()) |job| {
                self.unlock();
                _ = self.worker_jobs.fetchAdd(1, .monotonic);
                self.execute(job);
                self.lock();
            } else if (self.stopping) {
                return;
            } else {
                check(std.c.pthread_cond_wait(&self.changed, &self.mutex));
            }
        }
    }

    fn lock(self: *Pool) void {
        check(std.c.pthread_mutex_lock(&self.mutex));
    }

    fn unlock(self: *Pool) void {
        check(std.c.pthread_mutex_unlock(&self.mutex));
    }

    fn check(result: std.c.E) void {
        if (result != .SUCCESS) @panic("native compiler worker synchronization failed");
    }
};

test "persistent workers complete nested fork/join work and publish results" {
    const Task = struct {
        pool: *Pool,
        depth: u8,
        result: u64 = 0,
        fn run(raw: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            if (self.depth == 0) {
                self.result = 1;
                return;
            }
            var left: @This() = .{ .pool = self.pool, .depth = self.depth - 1 };
            var right: @This() = .{ .pool = self.pool, .depth = self.depth - 1 };
            var job: Job = .{ .run = run, .data = &left };
            self.pool.submit(&job);
            run(&right);
            self.pool.wait(&job);
            self.result = left.result + right.result;
        }
    };
    for ([_]usize{ 2, 4 }) |count| {
        var pool: Pool = .{};
        try pool.start(count);
        defer pool.deinit();
        var task: Task = .{ .pool = &pool, .depth = 9 };
        var root: Job = .{ .run = Task.run, .data = &task };
        pool.submit(&root);
        // Intentionally do not help here: prove a real worker runs the root.
        pool.lock();
        while (!root.done) Pool.check(std.c.pthread_cond_wait(&pool.changed, &pool.mutex));
        pool.unlock();
        try std.testing.expectEqual(@as(u64, 512), task.result);
        try std.testing.expect(pool.worker_jobs.load(.monotonic) > 0);
    }
}

test "worker limits include the calling thread" {
    var serial: Pool = .{};
    try serial.start(1);
    defer serial.deinit();
    try std.testing.expectEqual(@as(usize, 0), serial.worker_count);
    var invalid: Pool = .{};
    try std.testing.expectError(error.InvalidThreadCount, invalid.start(0));
    try std.testing.expectError(error.InvalidThreadCount, invalid.start(65));
}
