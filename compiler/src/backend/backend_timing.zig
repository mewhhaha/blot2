//! Optional caller-owned wall-clock instrumentation. It does not participate
//! in compiler identities, semantic decisions or retained artifact validity.
const std = @import("std");
pub const Stats = struct {
    prepare_us: u64 = 0,
    generate_us: u64 = 0,
    initialize_us: u64 = 0,
    assemble_us: u64 = 0,
    capture_us: u64 = 0,
    /// Detailed work clocks exist only when the caller requested profiling.
    /// An unprofiled record has no `work` object rather than zero placeholders.
    profiled: bool = false,
    work: WorkStats = .{},
    pub fn jsonStringify(self: *const Stats, stream: *std.json.Stringify) std.Io.Writer.Error!void {
        try stream.beginObject();
        inline for (@typeInfo(Stats).@"struct".field_names) |name| {
            if (comptime !std.mem.eql(u8, name, "profiled") and !std.mem.eql(u8, name, "work")) {
                try stream.objectField(name);
                try stream.write(@field(self, name));
            }
        }
        if (self.profiled) {
            try stream.objectField("work");
            try stream.write(self.work);
        }
        try stream.endObject();
    }
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
/// User plus kernel CPU of the coordinating thread, exclusive by work phase.
/// Worker CPU is reported separately. Availability is explicit on other hosts.
pub const ThreadCpu = struct {
    values: [@typeInfo(Work.Phase).@"enum".field_names.len]u64 = @splat(0),
    pub fn jsonStringify(self: *const ThreadCpu, stream: *std.json.Stringify) std.Io.Writer.Error!void {
        try stream.beginObject();
        inline for (@typeInfo(Work.Phase).@"enum".field_names, 0..) |name, index| {
            try stream.objectField(name);
            try stream.write(self.values[index]);
        }
        try stream.endObject();
    }
};
/// Whole fresh refinement requests, grouped by exact diagnostic flag sets.
/// Flags are observational only; they never admit a semantic query.
pub const RefinementCost = struct {
    admission: u8 = 0,
    publication: u16 = 0,
    rejected_candidates: u16 = 0,
    record_rejections: u8 = 0,
    requests: u64 = 0,
    nodes: u64 = 0,
};
pub const RefinementRequest = struct {
    cost: RefinementCost = .{},
    unit: u32 = 0,
    source: u32 = 0,
    closure: bool = false,
    expected: u32 = 0,
    seeds: usize = 0,
    rows: usize = 0,
};
pub const RefinementCensus = struct {
    groups: [32]RefinementCost = @splat(.{}),
    overflow: RefinementCost = .{},
    heaviest: [8]RefinementRequest = @splat(.{}),
    pub fn add(self: *RefinementCensus, request: RefinementRequest) void {
        const cost = request.cost;
        const slot = for (&self.groups) |*group| {
            if (group.requests == 0 or (group.admission == cost.admission and group.publication == cost.publication and group.rejected_candidates == cost.rejected_candidates and group.record_rejections == cost.record_rejections)) break group;
        } else &self.overflow;
        if (slot.requests == 0 and slot != &self.overflow) slot.* = cost else {
            slot.requests +|= cost.requests;
            slot.nodes +|= cost.nodes;
        }
        var smallest: usize = 0;
        for (self.heaviest, 0..) |prior, index| if (prior.cost.nodes < self.heaviest[smallest].cost.nodes) {
            smallest = index;
        };
        if (cost.nodes > self.heaviest[smallest].cost.nodes) self.heaviest[smallest] = request;
    }
    pub fn jsonStringify(self: *const RefinementCensus, stream: *std.json.Stringify) std.Io.Writer.Error!void {
        try stream.beginObject();
        try stream.objectField("groups");
        try stream.beginArray();
        for (self.groups) |group| if (group.requests != 0) try stream.write(group);
        try stream.endArray();
        try stream.objectField("overflow");
        try stream.write(self.overflow);
        try stream.objectField("heaviest");
        try stream.beginArray();
        for (self.heaviest) |request| if (request.cost.requests != 0) try stream.write(request);
        try stream.endArray();
        try stream.endObject();
    }
};
pub const WorkStats = struct {
    regions: [8]Region = @splat(.{}),
    region_callers: RegionCensus = .{},
    refinements: RefinementCensus = .{},
    thread_cpu_us: ?ThreadCpu = null,
    lookup_us: u64 = 0,
    query_prepare_us: u64 = 0,
    query_scan_us: u64 = 0,
    query_source_us: u64 = 0,
    query_import_us: u64 = 0,
    query_match_us: u64 = 0,
    query_validate_us: u64 = 0,
    query_publish_us: u64 = 0,
    replay_us: u64 = 0,
    specialization_us: u64 = 0,
    constants_us: u64 = 0,
    principals_us: u64 = 0,
    interfaces_us: u64 = 0,
    startup_us: u64 = 0,
    layouts_us: u64 = 0,
    evaluation_us: u64 = 0,
    inference_us: u64 = 0,
    semantic_coordination_us: u64 = 0,
    semantic_dispatch_us: u64 = 0,
    semantic_publication_us: u64 = 0,
    /// Sum of private job wall time; overlaps dispatch and is not additive.
    semantic_job_sum_us: u64 = 0,
    /// Only the slowest recorded regions are published; empty slots are not.
    pub fn jsonStringify(self: *const WorkStats, stream: *std.json.Stringify) std.Io.Writer.Error!void {
        try stream.beginObject();
        try stream.objectField("regions");
        try stream.beginArray();
        for (self.regions) |record| if (record.us != 0) try stream.write(record);
        try stream.endArray();
        inline for (@typeInfo(WorkStats).@"struct".field_names) |name| {
            if (comptime !std.mem.eql(u8, name, "regions")) {
                try stream.objectField(name);
                try stream.write(@field(self, name));
            }
        }
        try stream.endObject();
    }
};
pub const RegionCaller = struct { function: []const u8 = "", line: u32 = 0 };
pub const RegionCost = struct {
    /// Descriptors are comptime constants with compiler-process lifetime,
    /// including when this census is copied into a result snapshot.
    caller: *const RegionCaller = &.{},
    stage: ?@import("../work_counters.zig").InferenceStage = .general,
    regions: u64 = 0,
    /// Inclusive region wall time: nested regions overlap and cannot be added
    /// to the exclusive inference clock. Allocation totals have distinct owners.
    inclusive_us: u64 = 0,
    scopes: u64 = 0,
    nodes: u64 = 0,
    solver_bytes: u64 = 0,
    scratch_bytes: u64 = 0,
    solver_allocations: u64 = 0,
    scratch_allocations: u64 = 0,
};
pub const RegionCensus = struct {
    entries: [32]RegionCost = @splat(.{}),
    overflow: RegionCost = .{ .caller = &.{ .function = "overflow" }, .stage = null },
    pub fn add(self: *RegionCensus, cost: RegionCost) void {
        const slot = for (&self.entries) |*entry| {
            if (entry.regions == 0 or (entry.stage == cost.stage and entry.caller.line == cost.caller.line and std.mem.eql(u8, entry.caller.function, cost.caller.function))) break entry;
        } else &self.overflow;
        if (slot.regions == 0 and slot != &self.overflow) {
            slot.caller = cost.caller;
            slot.stage = cost.stage;
        }
        inline for (@typeInfo(RegionCost).@"struct".field_names) |field| {
            if (comptime !std.mem.eql(u8, field, "caller") and !std.mem.eql(u8, field, "stage")) @field(slot, field) +|= @field(cost, field);
        }
    }
    pub fn jsonStringify(self: *const RegionCensus, stream: *std.json.Stringify) std.Io.Writer.Error!void {
        try stream.beginArray();
        for (self.entries) |entry| if (entry.regions != 0) try stream.write(entry);
        if (self.overflow.regions != 0) try stream.write(self.overflow);
        try stream.endArray();
    }
};
pub const Work = struct {
    pub const Phase = enum { other, lookup, query_prepare, query_scan, query_source, query_import, query_match, query_validate, query_publish, replay, specialization, constants, principals, interfaces, startup, layouts, evaluation, inference, semantic_coordination, semantic_dispatch, semantic_publication };
    clock: Clock = .{ .io = null, .previous = null },
    cpu_clock: Clock = .{ .io = null, .previous = null, .kind = .cpu_thread },
    cpu_nanos: [@typeInfo(Phase).@"enum".field_names.len]u64 = @splat(0),
    active: Phase = .other,
    regions: [8]Region = @splat(.{}),
    region_callers: RegionCensus = .{},
    refinements: RefinementCensus = .{},
    nanos: [@typeInfo(Phase).@"enum".field_names.len]u64 = @splat(0),
    semantic_job_nanos: u64 = 0,
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
        /// Move an existing scope between exclusive work stages while keeping
        /// its original parent. Nested scopes still restore this stage.
        pub fn change(self: Scope, phase: Phase) void {
            self.owner.account();
            self.owner.active = phase;
        }
    };
    fn account(self: *Work) void {
        self.nanos[@backingInt(self.active)] += self.clock.lapNanos();
        self.cpu_nanos[@backingInt(self.active)] += self.cpu_clock.lapNanos();
    }
    pub fn snapshot(self: *const Work) WorkStats {
        var result: WorkStats = .{ .regions = self.regions, .region_callers = self.region_callers, .refinements = self.refinements, .semantic_job_sum_us = self.semantic_job_nanos / std.time.ns_per_us };
        if (self.cpu_clock.io != null) {
            result.thread_cpu_us = .{};
            for (self.cpu_nanos, &result.thread_cpu_us.?.values) |nanos, *us| us.* = nanos / std.time.ns_per_us;
        }
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
        record.file_truncated = copyUtf8Prefix(&record.file_utf8, name);
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
    kind: std.Io.Clock = .awake,
    pub fn init(io: ?std.Io) Clock {
        return initKind(io, .awake);
    }
    pub fn initKind(io: ?std.Io, kind: std.Io.Clock) Clock {
        return .{ .io = io, .kind = kind, .previous = if (io) |value| kind.now(value) else null };
    }
    pub fn lap(self: *Clock) u64 {
        return self.lapNanos() / std.time.ns_per_us;
    }
    pub fn lapNanos(self: *Clock) u64 {
        const io = self.io orelse return 0;
        const current = self.kind.now(io);
        const elapsed = self.previous.?.durationTo(current).toNanoseconds();
        self.previous = current;
        return @intCast(@max(0, elapsed));
    }
};
/// Copies the longest whole-code-point prefix of `name` that fits `buffer` and
/// reports whether `name` was cut short.
fn copyUtf8Prefix(buffer: []u8, name: []const u8) bool {
    var len = @min(name.len, buffer.len);
    while (len != 0 and len < name.len and name[len] & 0xc0 == 0x80) len -= 1;
    @memcpy(buffer[0..len], name[0..len]);
    return len != name.len;
}

test "unprofiled timing publishes no work object or placeholder regions" {
    const allocator = std.testing.allocator;
    const plain = try std.json.Stringify.valueAlloc(allocator, Stats{}, .{});
    defer allocator.free(plain);
    try std.testing.expect(std.mem.find(u8, plain, "prepare_us") != null);
    try std.testing.expect(std.mem.find(u8, plain, "work") == null);
    try std.testing.expect(std.mem.find(u8, plain, "regions") == null);
    var profiled: Stats = .{ .profiled = true };
    profiled.work.inference_us = 7;
    profiled.work.regions[3] = .{ .us = 1500, .scopes = 2 };
    const detail = try std.json.Stringify.valueAlloc(allocator, profiled, .{});
    defer allocator.free(detail);
    try std.testing.expect(std.mem.find(u8, detail, "\"inference_us\":7") != null);
    // Seven empty slots are not published; only the recorded region is.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, detail, "\"scopes\""));
    var census: RegionCensus = .{};
    const caller: *const RegionCaller = &.{ .function = "same", .line = 1 };
    census.add(.{ .caller = caller, .stage = .general, .regions = 1 });
    census.add(.{ .caller = caller, .stage = .lowering, .regions = 2 });
    census.add(.{ .caller = caller, .stage = .general, .regions = 3 });
    try std.testing.expectEqual(@as(u64, 4), census.entries[0].regions);
    try std.testing.expectEqual(@as(u64, 2), census.entries[1].regions);
    const stages = try std.json.Stringify.valueAlloc(allocator, census, .{});
    defer allocator.free(stages);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, stages, "\"stage\""));
    try std.testing.expect(std.mem.find(u8, stages, "\"stage\":\"general\"") != null);
    try std.testing.expect(std.mem.find(u8, stages, "\"stage\":\"lowering\"") != null);
}

test "refinement census preserves all request work through bounded overflow" {
    var census: RefinementCensus = .{};
    for (0..40) |index| census.add(.{ .cost = .{ .admission = @intCast(index), .requests = 1, .nodes = index + 1 } });
    var requests = census.overflow.requests;
    var nodes = census.overflow.nodes;
    for (census.groups) |group| {
        requests += group.requests;
        nodes += group.nodes;
    }
    try std.testing.expectEqual(@as(u64, 40), requests);
    try std.testing.expectEqual(@as(u64, 820), nodes);
    for (census.heaviest) |request| try std.testing.expect(request.cost.nodes >= 33);
}
