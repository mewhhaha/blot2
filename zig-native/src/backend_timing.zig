//! Optional caller-owned wall-clock instrumentation. It does not participate
//! in compiler identities, semantic decisions or retained artifact validity.
const std = @import("std");
pub const Stats = struct {
    prepare_us: u64 = 0,
    generate_us: u64 = 0,
    initialize_us: u64 = 0,
    assemble_us: u64 = 0,
    capture_us: u64 = 0,
    work: WorkStats = .{},
};
pub const Region = struct {
    file_utf8: [160]u8 = @splat(0),
    file_truncated: bool = false,
    offset: u32 = 0,
    unit: u32 = 0,
    binding: u32 = 0,
    body: u32 = 0,
    scopes: usize = 0,
    nodes: usize = 0,
    us: u64 = 0,
    principal: bool = false,
    rejected: u16 = 0,
    input_calls: usize = 0,
    recorded_inputs: bool = false,
    output_types: usize = 0,
    output_rows: usize = 0,
    pub fn jsonStringify(self: *const Region, stream: *std.json.Stringify) std.Io.Writer.Error!void {
        try stream.write(.{ .file = std.mem.sliceTo(&self.file_utf8, 0), .file_truncated = self.file_truncated, .offset = self.offset, .unit = self.unit, .binding = self.binding, .body = self.body, .scopes = self.scopes, .nodes = self.nodes, .us = self.us, .principal = self.principal, .rejected = self.rejected, .input_calls = self.input_calls, .recorded_inputs = self.recorded_inputs, .output_types = self.output_types, .output_rows = self.output_rows });
    }
};
pub const WorkStats = struct { regions: [8]Region = @splat(.{}), lookup_us: u64 = 0, replay_us: u64 = 0, specialization_us: u64 = 0, constants_us: u64 = 0, principals_us: u64 = 0, interfaces_us: u64 = 0, startup_us: u64 = 0, layouts_us: u64 = 0, evaluation_us: u64 = 0, inference_us: u64 = 0 };
pub const Work = struct {
    pub const Phase = enum { other, lookup, replay, specialization, constants, principals, interfaces, startup, layouts, evaluation, inference };
    clock: Clock = .{ .io = null, .previous = null },
    active: Phase = .other,
    regions: [8]Region = @splat(.{}),
    nanos: [@typeInfo(Phase).@"enum".field_names.len]u64 = @splat(0),
    pub const Scope = struct {
        owner: *Work,
        previous: Phase,
        started: ?std.Io.Timestamp,
        pub fn elapsedUs(self: Scope) u64 {
            const io = self.owner.clock.io orelse return 0;
            const now = std.Io.Clock.awake.now(io);
            return @intCast(@max(0, self.started.?.durationTo(now).toMicroseconds()));
        }
        pub fn deinit(self: Scope) void {
            self.owner.account();
            self.owner.active = self.previous;
        }
    };
    fn account(self: *Work) void {
        self.nanos[@backingInt(self.active)] += self.clock.lapNanos();
    }
    pub fn snapshot(self: *const Work) WorkStats {
        var result: WorkStats = .{ .regions = self.regions };
        inline for (@typeInfo(Phase).@"enum".field_names) |field| {
            if (comptime !std.mem.eql(u8, field, "other")) {
                const phase = @field(Phase, field);
                @field(result, field ++ "_us") = self.nanos[@backingInt(phase)] / std.time.ns_per_us;
            }
        }
        return result;
    }
    pub fn region(self: *Work, input: Region, name: []const u8) void {
        var smallest: usize = 0;
        for (self.regions, 0..) |record, i| if (record.us < self.regions[smallest].us) {
            smallest = i;
        };
        if (input.us <= self.regions[smallest].us) return;
        const record = &self.regions[smallest];
        record.* = input;
        var len = @min(name.len, record.file_utf8.len);
        while (len != 0 and len < name.len and name[len] & 0xc0 == 0x80) len -= 1;
        @memcpy(record.file_utf8[0..len], name[0..len]);
        record.file_truncated = len != name.len;
    }
    pub fn enter(self: *Work, phase: Phase) Scope {
        self.account();
        const scope: Scope = .{ .owner = self, .previous = self.active, .started = self.clock.previous };
        self.active = phase;
        return scope;
    }
};
pub const Clock = struct {
    io: ?std.Io,
    previous: ?std.Io.Timestamp,
    pub fn init(io: ?std.Io) Clock {
        return .{ .io = io, .previous = if (io) |value| std.Io.Clock.awake.now(value) else null };
    }
    pub fn lap(self: *Clock) u64 {
        return self.lapNanos() / std.time.ns_per_us;
    }
    pub fn lapNanos(self: *Clock) u64 {
        const io = self.io orelse return 0;
        const current = std.Io.Clock.awake.now(io);
        const elapsed = self.previous.?.durationTo(current).toNanoseconds();
        self.previous = current;
        return @intCast(@max(0, elapsed));
    }
};
