//! Optional coarse optimization jobs over immutable functions and completed
//! lifetime facts. Only the backing allocator is synchronized. Workers use
//! private arenas, and publication/assembly happens after every worker joins.
//! A job may also plan reference counts over its final body (optimized or
//! reused). The caller reads those verdicts in function order, so the first
//! unproven function is the serial one whatever finished first.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const pipeline = @import("runtime_pipeline.zig");
const retained = @import("optimized_bodies.zig");
const lifetimes = @import("wasm_lifetimes.zig");
const A = std.mem.Allocator;

const LockedAllocator = @import("../eval/parallel_allocator.zig").LockedAllocator;

const Slot = struct { needed: bool, rc: bool = false, output: ?ir.Body = null, failed: bool = false, unproven: bool = false };
const Job = struct { id: usize, instructions: usize };
fn heavier(_: void, left: Job, right: Job) bool {
    return if (left.instructions == right.instructions) left.id < right.id else left.instructions > right.instructions;
}
const Work = struct {
    session: *const pipeline.Session,
    matcher: ?*const retained.Matcher,
    allocator: A,
    slots: []Slot,
    jobs: []const Job,
    clock: ?std.Io,
    started: ?std.Io.Timestamp,
    timings: ?*[16]retained.WorkerTiming,
    next: std.atomic.Value(usize) = .init(0),
    fn elapsed(self: *const Work) u64 {
        const io = self.clock orelse return 0;
        return @intCast(@max(0, self.started.?.durationTo(std.Io.Clock.awake.now(io)).toMicroseconds()));
    }
    fn execute(self: *Work, worker: usize) void {
        // Count in private stack storage and publish once. Profile collection
        // does not add per-job shared counters or cache-line contention.
        var timing: retained.WorkerTiming = .{ .started_us = self.elapsed() };
        const cpu_started = if (@import("builtin").os.tag == .linux) if (self.clock) |io| std.Io.Clock.cpu_thread.now(io) else null else null;
        defer if (self.timings) |times| {
            timing.finished_us = self.elapsed();
            if (cpu_started) |started| timing.cpu_us = @intCast(@max(0, started.durationTo(std.Io.Clock.cpu_thread.now(self.clock.?)).toMicroseconds()));
            times[worker] = timing;
        };
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        // Summaries are already complete. This shallow copy borrows their
        // immutable arrays; it neither rebuilds nor releases them.
        var local = self.session.*;
        local.allocator = arena.allocator();
        while (true) {
            const next = self.next.fetchAdd(1, .monotonic);
            if (next >= self.jobs.len) return;
            const id = self.jobs[next].id;
            if (self.timings != null) {
                timing.jobs += 1;
                timing.instructions += self.jobs[next].instructions;
            }
            const slot = &self.slots[id];
            defer _ = arena.reset(.{ .retain_with_limit = 512 * 1024 });
            const function = &local.module.functions.items[id];
            const body = if (slot.needed) (local.optimize(function) catch {
                slot.failed = true;
                continue;
            }) else self.matcher.?.output(id);
            if (slot.needed) if (body) |output| {
                slot.output = clone(self.allocator, output) catch {
                    slot.failed = true;
                    continue;
                };
            };
            if (slot.rc) {
                var view = function.*;
                if (body) |final| {
                    view.locals = final.locals;
                    view.instructions = final.instructions;
                }
                var proof = lifetimes.rcPlan(arena.allocator(), local.module, &view, &local.summaries, null) catch {
                    slot.failed = true;
                    continue;
                };
                defer proof.deinit(arena.allocator());
                slot.unproven = !proof.admitted or proof.allocations.items.len != 0;
            }
        }
    }
};
fn clone(a: A, body: ir.Body) A.Error!ir.Body {
    const locals = try a.dupe(ir.ValueType, body.locals.items);
    errdefer a.free(locals);
    const instructions = try a.dupe(ir.Instruction, body.instructions.items);
    return .{ .locals = .fromOwnedSlice(locals), .instructions = .fromOwnedSlice(instructions) };
}
pub const Batch = struct {
    allocator: A,
    slots: []Slot,
    workers: usize = 1,
    jobs: usize,
    rc: bool = false,
    timings: ?[16]retained.WorkerTiming = null,

    /// With `rc`, every function that is not a runtime helper also gets its
    /// final body's reference-count verdict, read through `unproven`.
    pub fn run(a: A, optional_io: ?std.Io, session: *const pipeline.Session, matcher: ?*const retained.Matcher, requested: u8, rc: bool, profile: bool) A.Error!?Batch {
        if (requested <= 1) return null;
        const io = optional_io orelse return null;
        std.debug.assert(session.summaries.prepared);
        var jobs: usize = 0;
        var instructions: usize = 0;
        for (session.module.functions.items, 0..) |function, id| {
            if (if (matcher) |matches| matches.matches(id) else false) continue;
            jobs += 1;
            instructions +|= function.instructions.items.len;
        }
        // Small edits and tiny modules do not pay scheduling/copying costs.
        if (jobs < 4 or instructions < 4096) return null;
        var batch: Batch = .{ .allocator = a, .slots = try a.alloc(Slot, session.module.functions.items.len), .jobs = jobs };
        errdefer batch.deinit();
        for (batch.slots, session.module.functions.items, 0..) |*slot, *function, id| slot.* = .{
            .needed = !(if (matcher) |matches| matches.matches(id) else false),
            .rc = rc and !session.runtimeHelper(function) and (if (matcher) |matches| matches.rcUnproven(id) == null else true),
        };
        batch.rc = rc;
        var queue: std.ArrayList(Job) = .empty;
        defer queue.deinit(a);
        for (batch.slots, session.module.functions.items, 0..) |slot, function, id| if (slot.needed or slot.rc) {
            const body = if (!slot.needed) matcher.?.output(id) else null;
            try queue.append(a, .{ .id = id, .instructions = if (body) |output| output.instructions.items.len else function.instructions.items.len });
        };
        std.mem.sort(Job, queue.items, {}, heavier);
        var locked: LockedAllocator = .{ .backing = a, .io = io };
        if (profile) batch.timings = @splat(.{});
        var work: Work = .{ .allocator = locked.allocator(), .session = session, .matcher = matcher, .slots = batch.slots, .jobs = queue.items, .clock = if (profile) io else null, .started = if (profile) std.Io.Clock.awake.now(io) else null, .timings = if (batch.timings) |*timings| timings else null };
        var group: std.Io.Group = .init;
        // The compiler's CPU phases have no cancellation points. Keep this
        // bounded join in the same regime; pending cancellation resumes at the
        // next ordinary IO boundary after every borrowed owner is safe again.
        const protection = io.swapCancelProtection(.blocked);
        defer _ = io.swapCancelProtection(protection);
        defer group.cancel(io);
        const count = @min(@as(usize, requested), @min(jobs, 16));
        for (1..count) |_| {
            group.concurrent(io, Work.execute, .{ &work, batch.workers }) catch break;
            batch.workers += 1;
        }
        work.execute(0);
        group.await(io) catch unreachable;
        for (batch.slots) |slot| if (slot.failed) return error.OutOfMemory;
        return batch;
    }
    /// Moves an owned result out only after all workers have joined.
    pub fn take(self: *Batch, id: usize) ?ir.Body {
        std.debug.assert(self.slots[id].needed);
        const body = self.slots[id].output;
        self.slots[id].output = null;
        return body;
    }
    /// Whether function `id`'s final body leaves an allocation uncounted, or
    /// null when this batch did not plan it.
    pub fn unproven(self: *const Batch, id: usize) ?bool {
        if (!self.slots[id].rc) return null;
        return self.slots[id].unproven;
    }
    pub fn deinit(self: *Batch) void {
        for (self.slots) |*slot| if (slot.output) |*body| body.deinit(self.allocator);
        self.allocator.free(self.slots);
        self.* = undefined;
    }
};
