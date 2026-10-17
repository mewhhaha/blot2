//! Optional whole-build phase clocks. A caller that requested profiling
//! installs a Profile on its compiling thread for one build; `enter` then
//! charges elapsed time to the active phase. Phases are exclusive: a nested
//! phase pauses its parent, so the recorded clocks partition the profiled
//! interval and `other` is the unattributed remainder. Without an installed
//! profile a scope is one thread-local load and branch: no clock is read.
//! Like backend_timing, this never participates in compiler identities,
//! semantic decisions or retained artifact validity. Worker threads see no
//! installed profile; their time overlaps the coordinating thread's phase.
const std = @import("std");

pub const Phase = enum {
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
    active: Phase = .other,
    nanos: [phase_count]u64 = @splat(0),

    pub fn init(io: std.Io) Profile {
        const now = std.Io.Clock.awake.now(io);
        return .{ .io = io, .started = now, .previous = now };
    }
    fn account(self: *Profile) void {
        const now = std.Io.Clock.awake.now(self.io);
        self.nanos[@backingInt(self.active)] += @intCast(@max(0, self.previous.durationTo(now).toNanoseconds()));
        self.previous = now;
    }
    /// Charges the open interval to the active phase and reports every clock.
    pub fn record(self: *Profile) Record {
        self.account();
        var result: Record = .{ .profiled = true, .total_us = @intCast(@max(0, self.started.durationTo(self.previous).toMicroseconds())) };
        for (&result.phases, self.nanos) |*phase, nanos| phase.us = nanos / std.time.ns_per_us;
        return result;
    }
};

/// One phase's share of a profiled build.
pub const PhaseRecord = struct { us: u64 = 0 };

/// An unprofiled record publishes an empty object rather than zero clocks.
pub const Record = struct {
    profiled: bool = false,
    total_us: u64 = 0,
    phases: [phase_count]PhaseRecord = @splat(.{}),
    pub fn jsonStringify(self: *const Record, stream: *std.json.Stringify) std.Io.Writer.Error!void {
        try stream.beginObject();
        if (self.profiled) {
            try stream.objectField("total_us");
            try stream.write(self.total_us);
            try stream.objectField("phases");
            try stream.beginObject();
            inline for (@typeInfo(Phase).@"enum".field_names, 0..) |name, index| {
                try stream.objectField(name);
                try stream.write(self.phases[index]);
            }
            try stream.endObject();
        }
        try stream.endObject();
    }
};

threadlocal var installed: ?*Profile = null;

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
        profile.active = self.previous;
    }
};
/// Charges time until the matching `exit` to `phase`, pausing the active one.
pub fn enter(phase: Phase) Scope {
    const profile = installed orelse return .{ .profile = null, .previous = .other };
    profile.account();
    const previous = profile.active;
    profile.active = phase;
    return .{ .profile = profile, .previous = previous };
}

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
    const detail = try std.json.Stringify.valueAlloc(allocator, result, .{});
    defer allocator.free(detail);
    try std.testing.expect(std.mem.find(u8, detail, "\"total_us\":") != null);
    try std.testing.expect(std.mem.find(u8, detail, "\"validation\":{\"us\":") != null);
}
