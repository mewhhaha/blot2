//! Optional whole-build phase clocks and allocation counts. A caller that
//! requested profiling installs a Profile on its compiling thread for one
//! build; `enter` then charges elapsed time to the active phase. Phases are
//! exclusive: a nested phase pauses its parent, so the recorded clocks
//! partition the profiled interval and `other` is the unattributed remainder.
//! Without an installed profile a scope is one thread-local load and branch:
//! no clock is read. Like backend_timing, this never participates in compiler
//! identities, semantic decisions or retained artifact validity. Worker
//! threads see no installed profile; their time overlaps the coordinating
//! thread's phase, and their allocations are charged to that phase.
const std = @import("std");
const builtin = @import("builtin");

pub const Phase = enum(u8) {
    other,
    /// Native asset capture and generated asset modules.
    assets,
    /// Revision input capture and comparison against the previous revision.
    inputs,
    /// File reading, import resolution and project assembly.
    load,
    lex,
    parse,
    check,
    lower,
    /// Copying checked Core and interfaces into a frozen dependency.
    freeze,
    /// Structural validation of frozen Core, interfaces and closures.
    validation,
    backend,
};
const phase_count = @typeInfo(Phase).@"enum".field_names.len;

pub const Profile = struct {
    io: std.Io,
    started: std.Io.Timestamp,
    previous: std.Io.Timestamp,
    /// Written by the installing thread; CountingAllocator reads it anywhere.
    active: Phase = .other,
    checking: @import("work_counters.zig").Frontend = .{},
    nanos: [phase_count]u64 = @splat(0),
    /// Updated atomically by CountingAllocator from any thread.
    requested_bytes: [phase_count]u64 = @splat(0),
    allocations: [phase_count]u64 = @splat(0),
    /// Growth of the process's peak RSS charged to the phase that ended when
    /// it was sampled. Samples are taken at phase changes at most every
    /// `rss_interval_ns`, so short phases cost no file read.
    rss_growth_kib: [phase_count]u64 = @splat(0),
    peak_rss_kib: u64,
    rss_sampled: std.Io.Timestamp,

    const rss_interval_ns = 2 * std.time.ns_per_ms;

    pub fn init(io: std.Io) Profile {
        const now = std.Io.Clock.awake.now(io);
        return .{ .io = io, .started = now, .previous = now, .peak_rss_kib = peakRssKib(io), .rss_sampled = now };
    }
    fn account(self: *Profile) void {
        const now = std.Io.Clock.awake.now(self.io);
        const phase = @backingInt(self.active);
        self.nanos[phase] += @intCast(@max(0, self.previous.durationTo(now).toNanoseconds()));
        self.previous = now;
        if (self.rss_sampled.durationTo(now).toNanoseconds() >= rss_interval_ns) self.sampleRss(phase);
    }
    fn sampleRss(self: *Profile, phase: usize) void {
        const peak = peakRssKib(self.io);
        self.rss_growth_kib[phase] += peak -| self.peak_rss_kib;
        self.peak_rss_kib = @max(self.peak_rss_kib, peak);
        self.rss_sampled = std.Io.Clock.awake.now(self.io);
    }
    fn activate(self: *Profile, phase: Phase) void {
        @atomicStore(Phase, &self.active, phase, .monotonic);
    }
    /// Charges the open interval to the active phase and reports every clock.
    pub fn record(self: *Profile) Record {
        self.account();
        self.sampleRss(@backingInt(self.active));
        if (trace) |owner| owner.flushPasses();
        var result: Record = .{ .profiled = true, .total_us = @intCast(@max(0, self.started.durationTo(self.previous).toMicroseconds())), .peak_rss_kib = self.peak_rss_kib };
        result.checking = self.checking;
        for (&result.phases, 0..) |*phase, index| phase.* = .{
            .us = self.nanos[index] / std.time.ns_per_us,
            .requested_bytes = @atomicLoad(u64, &self.requested_bytes[index], .monotonic),
            .allocations = @atomicLoad(u64, &self.allocations[index], .monotonic),
            .rss_growth_kib = self.rss_growth_kib[index],
        };
        return result;
    }
};

/// The process's peak resident set so far (VmHWM), or zero where the kernel
/// does not publish it. getrusage's maxrss is unusable: after exec it keeps
/// the spawning process's resident set.
fn peakRssKib(io: std.Io) u64 {
    if (comptime builtin.os.tag != .linux) return 0;
    var buffer: [4096]u8 = undefined;
    const status = std.Io.Dir.cwd().readFile(io, "/proc/self/status", &buffer) catch return 0;
    const at = std.mem.find(u8, status, "\nVmHWM:") orelse return 0;
    var digits = std.mem.tokenizeAny(u8, status[at + "\nVmHWM:".len ..], " \t");
    return std.fmt.parseInt(u64, digits.next() orelse return 0, 10) catch 0;
}

/// One phase's share of a profiled build. Allocation counts are those of the
/// CountingAllocator attached to the profile; requested bytes exclude
/// allocator overhead and are not reduced by frees.
pub const PhaseRecord = struct { us: u64 = 0, requested_bytes: u64 = 0, allocations: u64 = 0, rss_growth_kib: u64 = 0 };

/// An unprofiled record publishes an empty object rather than zero clocks.
pub const Record = struct {
    profiled: bool = false,
    total_us: u64 = 0,
    peak_rss_kib: u64 = 0,
    phases: [phase_count]PhaseRecord = @splat(.{}),
    checking: @import("work_counters.zig").Frontend = .{},
    pub fn jsonStringify(self: *const Record, stream: *std.json.Stringify) std.Io.Writer.Error!void {
        try stream.beginObject();
        if (self.profiled) {
            try stream.objectField("total_us");
            try stream.write(self.total_us);
            try stream.objectField("peak_rss_kib");
            try stream.write(self.peak_rss_kib);
            try stream.objectField("phases");
            try stream.beginObject();
            inline for (@typeInfo(Phase).@"enum".field_names, 0..) |name, index| {
                try stream.objectField(name);
                try stream.write(self.phases[index]);
            }
            try stream.endObject();
            try stream.objectField("checking");
            try stream.write(self.checking);
        }
        try stream.endObject();
    }
};

threadlocal var installed: ?*Profile = null;
threadlocal var checking_capture: ?*@import("work_counters.zig").Frontend = null;

/// Independent diagnostic stream. Records own no compiler data and never
/// participate in artifact identity. The client retains a bounded tail plus
/// the latest phase totals/module names, even when the process is killed.
pub const OptimizationPass = enum { @"inline", scalar, vector, row_products, lifetime, reduce, rc };
const PassTotals = struct { us: u64 = 0, cpu_us: u64 = 0, input: u64 = 0, output: u64 = 0, calls: u64 = 0 };

pub const Trace = struct {
    io: std.Io,
    started: std.Io.Timestamp,
    build: u32,
    mutex: std.Io.Mutex = .init,
    next: std.atomic.Value(u64) = .init(1),
    passes: [7]PassTotals = @splat(.{}),

    pub fn init(io: std.Io, build: u32) Trace {
        return .{ .io = io, .build = build, .started = std.Io.Clock.awake.now(io) };
    }
    /// Pass clocks are accumulated across functions and workers, rather than
    /// serializing every small pass. These sums overlap coordinator wall time.
    pub fn flushPasses(self: *Trace) void {
        inline for (@typeInfo(OptimizationPass).@"enum".field_names, 0..) |name, index| {
            const totals = &self.passes[index];
            const calls = @atomicLoad(u64, &totals.calls, .monotonic);
            if (calls != 0) self.write(.{ .kind = "end", .id = 0, .thread = 0, .stage = "runtime-ir.total." ++ name, .unit = 0, .start = 0, .end = 0, .at_us = self.elapsed(), .us = @atomicLoad(u64, &totals.us, .monotonic), .cpu_us = @atomicLoad(u64, &totals.cpu_us, .monotonic), .input_items = @atomicLoad(u64, &totals.input, .monotonic), .output_items = @atomicLoad(u64, &totals.output, .monotonic), .calls = calls });
        }
    }
    fn elapsed(self: *const Trace) u64 {
        return @intCast(@max(0, self.started.durationTo(std.Io.Clock.awake.now(self.io)).toMicroseconds()));
    }
    fn write(self: *Trace, value: anytype) void {
        var bytes: [4096]u8 = undefined;
        var writer = std.Io.Writer.fixed(&bytes);
        writer.writeAll("BLOT_PROFILE ") catch return;
        const Envelope = struct {
            build: u32,
            event: @TypeOf(value),
            pub fn jsonStringify(envelope: @This(), stream: *std.json.Stringify) std.Io.Writer.Error!void {
                try stream.beginObject();
                try stream.objectField("build");
                try stream.write(envelope.build);
                inline for (@typeInfo(@TypeOf(value)).@"struct".field_names) |field| {
                    try stream.objectField(field);
                    try stream.write(@field(envelope.event, field));
                }
                try stream.endObject();
            }
        };
        std.json.Stringify.value(Envelope{ .build = self.build, .event = value }, .{}, &writer) catch return;
        writer.writeByte('\n') catch return;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        std.Io.File.stderr().writeStreamingAll(self.io, writer.buffered()) catch {};
    }
};

threadlocal var trace: ?*Trace = null;
pub const TraceInstallation = struct {
    previous: ?*Trace,
    pub fn restore(self: TraceInstallation) void {
        trace = self.previous;
    }
};
pub fn currentTrace() ?*Trace {
    return trace;
}
pub fn installTrace(value: ?*Trace) TraceInstallation {
    const previous = trace;
    trace = value;
    return .{ .previous = previous };
}

fn cpuNanos() ?u64 {
    if (comptime builtin.os.tag != .linux) return null;
    var stamp: std.os.linux.timespec = undefined;
    if (std.os.linux.clock_gettime(.THREAD_CPUTIME_ID, &stamp) != 0) return null;
    return @as(u64, @intCast(stamp.sec)) * std.time.ns_per_s + @as(u64, @intCast(stamp.nsec));
}
fn threadId() u32 {
    if (comptime builtin.os.tag == .linux) return @intCast(std.os.linux.gettid());
    return 0;
}

pub const Region = struct {
    owner: ?*Trace = null,
    id: u64 = 0,
    stage: []const u8 = "",
    unit: u32 = 0,
    start: u32 = 0,
    end: u32 = 0,
    started: u64 = 0,
    cpu: ?u64 = null,
    pass: ?OptimizationPass = null,
    pub fn exit(self: Region) void {
        self.exitWithItems(0, 0);
    }
    pub fn exitWithItems(self: Region, input_items: usize, output_items: usize) void {
        const owner = self.owner orelse return;
        const now = owner.elapsed();
        const cpu = cpuNanos();
        if (self.pass) |pass| {
            const totals = &owner.passes[@backingInt(pass)];
            _ = @atomicRmw(u64, &totals.us, .Add, now -| self.started, .monotonic);
            if (cpu != null and self.cpu != null) _ = @atomicRmw(u64, &totals.cpu_us, .Add, (cpu.? -| self.cpu.?) / std.time.ns_per_us, .monotonic);
            _ = @atomicRmw(u64, &totals.input, .Add, input_items, .monotonic);
            _ = @atomicRmw(u64, &totals.output, .Add, output_items, .monotonic);
            _ = @atomicRmw(u64, &totals.calls, .Add, 1, .monotonic);
            return;
        }
        owner.write(.{ .kind = "end", .id = self.id, .thread = threadId(), .stage = self.stage, .unit = self.unit, .start = self.start, .end = self.end, .at_us = now, .us = now -| self.started, .input_items = input_items, .output_items = output_items, .cpu_us = if (cpu != null and self.cpu != null) (cpu.? -| self.cpu.?) / std.time.ns_per_us else null });
    }
};
/// Region wall/CPU clocks are inclusive and may overlap other regions. They
/// must not be summed with exclusive phase clocks or across nested regions.
pub fn region(stage: []const u8, unit: u32, start: u32, end: u32) Region {
    const owner = trace orelse return .{};
    const value: Region = .{ .owner = owner, .id = owner.next.fetchAdd(1, .monotonic), .stage = stage, .unit = unit, .start = start, .end = end, .started = owner.elapsed(), .cpu = cpuNanos() };
    owner.write(.{ .kind = "begin", .id = value.id, .thread = threadId(), .stage = stage, .unit = unit, .start = start, .end = end, .at_us = value.started });
    return value;
}
pub fn optimizationPass(pass: OptimizationPass) Region {
    const owner = trace orelse return .{};
    return .{ .owner = owner, .pass = pass, .started = owner.elapsed(), .cpu = cpuNanos() };
}
pub fn detail(stage: []const u8, unit: u32, start: u32, end: u32, items: u64) void {
    const owner = trace orelse return;
    owner.write(.{ .kind = "detail", .thread = threadId(), .stage = stage, .unit = unit, .start = start, .end = end, .items = items, .at_us = owner.elapsed() });
}
pub fn traceModule(unit: u32, filename: []const u8, bytes: usize) void {
    const owner = trace orelse return;
    owner.write(.{ .kind = "module", .unit = unit, .filename = filename, .bytes = bytes });
}
fn tracePhases(profile: *Profile) void {
    const owner = trace orelse return;
    var micros: [phase_count]u64 = undefined;
    for (profile.nanos, &micros) |ns, *us| us.* = ns / std.time.ns_per_us;
    owner.write(.{ .kind = "phases", .active = @tagName(profile.active), .phase_us = micros, .at_us = owner.elapsed() });
}

pub const CheckingCapture = struct {
    previous: ?*@import("work_counters.zig").Frontend,
    pub fn restore(self: CheckingCapture) void {
        checking_capture = self.previous;
    }
};
pub fn captureChecking(output: *@import("work_counters.zig").Frontend) CheckingCapture {
    const previous = checking_capture;
    checking_capture = output;
    return .{ .previous = previous };
}

pub fn recordChecking(work: @import("work_counters.zig").Frontend) void {
    if (checking_capture) |output| {
        output.merge(work);
        return;
    }
    const profile = installed orelse return;
    if (profile.active == .check) profile.checking.merge(work);
}

/// Restores the profile that was installed before `install`.
pub const Installation = struct {
    previous: ?*Profile,
    pub fn restore(self: Installation) void {
        installed = self.previous;
    }
};
pub fn install(profile: *Profile) Installation {
    const previous = installed;
    installed = profile;
    return .{ .previous = previous };
}

pub const Scope = struct {
    profile: ?*Profile,
    previous: Phase,
    pub fn exit(self: Scope) void {
        const profile = self.profile orelse return;
        profile.account();
        profile.activate(self.previous);
        tracePhases(profile);
    }
};
/// Charges time until the matching `exit` to `phase`, pausing the active one.
pub fn enter(phase: Phase) Scope {
    const profile = installed orelse return .{ .profile = null, .previous = .other };
    profile.account();
    const previous = profile.active;
    profile.activate(phase);
    tracePhases(profile);
    return .{ .profile = profile, .previous = previous };
}

/// Charges requested bytes and allocation counts to the active phase of the
/// attached profile. Insert it only for profiled compilations: each request
/// then pays two relaxed atomic additions. Detached, it only forwards. It is
/// independent of TrackedAllocator, whose counters may be compiled out.
pub const CountingAllocator = struct {
    backing: std.mem.Allocator,
    profile: ?*Profile = null,

    pub fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }
    const vtable: std.mem.Allocator.VTable = .{ .alloc = alloc, .resize = resize, .remap = remap, .free = free };
    /// This wrapper's counters are atomic. Its backing allocator still decides
    /// whether concurrent jobs may call through it without an outer lock.
    pub fn backingOf(a: std.mem.Allocator) ?std.mem.Allocator {
        if (a.vtable != &vtable) return null;
        return @as(*CountingAllocator, @ptrCast(@alignCast(a.ptr))).backing;
    }
    /// The profile must outlive the attachment; detach before releasing it.
    pub fn attach(self: *CountingAllocator, profile: *Profile) void {
        @atomicStore(?*Profile, &self.profile, profile, .release);
    }
    pub fn detach(self: *CountingAllocator) void {
        @atomicStore(?*Profile, &self.profile, null, .release);
    }
    fn charge(self: *CountingAllocator, bytes: usize, allocations: u64) void {
        const profile = @atomicLoad(?*Profile, &self.profile, .acquire) orelse return;
        const phase = @backingInt(@atomicLoad(Phase, &profile.active, .monotonic));
        _ = @atomicRmw(u64, &profile.requested_bytes[phase], .Add, bytes, .monotonic);
        if (allocations != 0) _ = @atomicRmw(u64, &profile.allocations[phase], .Add, allocations, .monotonic);
    }
    fn alloc(raw: *anyopaque, len: usize, alignment: std.mem.Alignment, ret: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(raw));
        const result = self.backing.rawAlloc(len, alignment, ret) orelse return null;
        self.charge(len, 1);
        return result;
    }
    fn resize(raw: *anyopaque, old: []u8, alignment: std.mem.Alignment, len: usize, ret: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(raw));
        if (!self.backing.rawResize(old, alignment, len, ret)) return false;
        self.charge(len -| old.len, 0);
        return true;
    }
    fn remap(raw: *anyopaque, old: []u8, alignment: std.mem.Alignment, len: usize, ret: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(raw));
        const result = self.backing.rawRemap(old, alignment, len, ret) orelse return null;
        self.charge(len -| old.len, 0);
        return result;
    }
    fn free(raw: *anyopaque, old: []u8, alignment: std.mem.Alignment, ret: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(raw));
        self.backing.rawFree(old, alignment, ret);
    }
};

test "unprofiled scopes read no clock and publish an empty record" {
    const allocator = std.testing.allocator;
    const scope = enter(.check);
    try std.testing.expect(scope.profile == null);
    scope.exit();
    const plain = try std.json.Stringify.valueAlloc(allocator, Record{}, .{});
    defer allocator.free(plain);
    try std.testing.expectEqualStrings("{}", plain);
}

test "nested phases are exclusive and partition the profiled interval" {
    const allocator = std.testing.allocator;
    var profile: Profile = .init(std.testing.io);
    const installation = install(&profile);
    {
        const load = enter(.load);
        defer load.exit();
        const lex = enter(.lex);
        try std.testing.expectEqual(Phase.lex, profile.active);
        lex.exit();
        try std.testing.expectEqual(Phase.load, profile.active);
    }
    try std.testing.expectEqual(Phase.other, profile.active);
    installation.restore();
    // A scope opened without an installed profile does not touch this one.
    const outside = enter(.backend);
    outside.exit();
    try std.testing.expectEqual(Phase.other, profile.active);
    const result = profile.record();
    var sum: u64 = 0;
    for (profile.nanos) |nanos| sum += nanos;
    // Every nanosecond since init belongs to exactly one phase.
    try std.testing.expectEqual(@as(i96, @intCast(sum)), profile.started.durationTo(profile.previous).toNanoseconds());
    var growth: u64 = 0;
    for (result.phases) |phase| growth += phase.rss_growth_kib;
    try std.testing.expect(growth <= result.peak_rss_kib);
    const encoded = try std.json.Stringify.valueAlloc(allocator, result, .{});
    defer allocator.free(encoded);
    try std.testing.expect(std.mem.find(u8, encoded, "\"total_us\":") != null);
    try std.testing.expect(std.mem.find(u8, encoded, "\"validation\":{\"us\":") != null);
    try std.testing.expect(std.mem.find(u8, encoded, "\"requested_bytes\":") != null);
}

test "project checking counters merge modules and exclude backend checker invocations" {
    var profile: Profile = .init(std.testing.io);
    const installation = install(&profile);
    defer installation.restore();
    const checking = enter(.check);
    recordChecking(.{ .modules = 1, .imported_schemes = 3, .normalization = .{ .free_type_visits = 7 } });
    recordChecking(.{ .modules = 1, .imported_schemes = 5, .normalization = .{ .free_type_visits = 11 } });
    const backend = enter(.backend);
    recordChecking(.{ .modules = 99, .imported_schemes = 99 });
    backend.exit();
    checking.exit();
    const record = profile.record();
    try std.testing.expectEqual(@as(u64, 2), record.checking.modules);
    try std.testing.expectEqual(@as(u64, 8), record.checking.imported_schemes);
    try std.testing.expectEqual(@as(u64, 18), record.checking.normalization.free_type_visits);
}

test "counting allocator charges requests to the active phase and only while attached" {
    var profile: Profile = .init(std.testing.io);
    var counting: CountingAllocator = .{ .backing = std.testing.allocator };
    const a = counting.allocator();
    // Detached requests are forwarded and not charged.
    const early = try a.alloc(u8, 64);
    defer a.free(early);
    counting.attach(&profile);
    const installation = install(&profile);
    {
        const lex = enter(.lex);
        defer lex.exit();
        var bytes: std.ArrayList(u8) = .empty;
        defer bytes.deinit(a);
        for (0..1000) |i| try bytes.append(a, @truncate(i));
        // Growth by resize or remap is requested storage; the list owns at
        // least its capacity, and frees never reduce the requested total.
        try std.testing.expect(profile.requested_bytes[@backingInt(Phase.lex)] >= bytes.capacity);
        try std.testing.expect(profile.allocations[@backingInt(Phase.lex)] >= 1);
    }
    const checked = try a.create(u64);
    a.destroy(checked);
    installation.restore();
    counting.detach();
    const late = try a.alloc(u8, 32);
    a.free(late);
    const result = profile.record();
    try std.testing.expectEqual(@as(u64, @sizeOf(u64)), result.phases[@backingInt(Phase.other)].requested_bytes);
    try std.testing.expectEqual(@as(u64, 1), result.phases[@backingInt(Phase.other)].allocations);
    try std.testing.expectEqual(@as(u64, 0), result.phases[@backingInt(Phase.check)].allocations);
}

test "counting allocator charges nothing for a failed request" {
    var profile: Profile = .init(std.testing.io);
    var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{ .fail_index = 0 });
    var counting: CountingAllocator = .{ .backing = failing.allocator() };
    counting.attach(&profile);
    try std.testing.expectError(error.OutOfMemory, counting.allocator().alloc(u8, 16));
    for (profile.requested_bytes, profile.allocations) |bytes, count| {
        try std.testing.expectEqual(@as(u64, 0), bytes);
        try std.testing.expectEqual(@as(u64, 0), count);
    }
}

test "optimizer trace aggregates instruction counts and restores thread installation" {
    var owner: Trace = .init(std.testing.io, 17);
    const installation = installTrace(&owner);
    defer installation.restore();
    const first = optimizationPass(.scalar);
    first.exitWithItems(20, 12);
    {
        const hidden = installTrace(null);
        defer hidden.restore();
        const ignored = optimizationPass(.scalar);
        ignored.exitWithItems(100, 90);
    }
    try std.testing.expect(currentTrace() == &owner);
    const second = optimizationPass(.scalar);
    second.exitWithItems(30, 11);
    const totals = owner.passes[@backingInt(OptimizationPass.scalar)];
    try std.testing.expectEqual(@as(u64, 2), totals.calls);
    try std.testing.expectEqual(@as(u64, 50), totals.input);
    try std.testing.expectEqual(@as(u64, 23), totals.output);
    try std.testing.expectEqual(@as(u64, 0), owner.passes[@backingInt(OptimizationPass.vector)].calls);
}
