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
    }
};
/// Charges time until the matching `exit` to `phase`, pausing the active one.
pub fn enter(phase: Phase) Scope {
    const profile = installed orelse return .{ .profile = null, .previous = .other };
    profile.account();
    const previous = profile.active;
    profile.activate(phase);
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
    const detail = try std.json.Stringify.valueAlloc(allocator, result, .{});
    defer allocator.free(detail);
    try std.testing.expect(std.mem.find(u8, detail, "\"total_us\":") != null);
    try std.testing.expect(std.mem.find(u8, detail, "\"validation\":{\"us\":") != null);
    try std.testing.expect(std.mem.find(u8, detail, "\"requested_bytes\":") != null);
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
