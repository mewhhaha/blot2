//! Owned complete query records and ordered position indexes. Claim adapters
//! still prove equality, validate dependencies and prepare replay; a bucket
//! match is never a successful semantic answer. No active solver ID is stored.
const std = @import("std");
const A = std.mem.Allocator;
pub const Kind = enum { refinement, specialization, principal, source_validation, executable };
pub const Order = enum { oldest_first, newest_first };
pub const Limits = struct {
    records: usize = 4096,
    owned_bytes: usize = 16 * 1024 * 1024,
    retained_capacity: usize = 2 * 1024 * 1024,
    lookup_work: usize = 4096,
};
/// Operation-local adapter: arrays/maps retain only their buffers, never this
/// pointer. Capacity failures decline caching; backing failures still report
/// OOM. Growth must fit while the previous buffer is live during preparation.
const CapacityAllocator = struct {
    backing: A,
    live: *usize,
    limit: usize,
    denied: bool = false,
    fn allocator(self: *CapacityAllocator) A {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn admits(self: *CapacityAllocator, old: usize, new: usize) bool {
        if (new -| old > self.limit -| self.live.*) {
            self.denied = true;
            return false;
        }
        return true;
    }
    fn alloc(raw: *anyopaque, len: usize, alignment: std.mem.Alignment, ret: usize) ?[*]u8 {
        const self: *CapacityAllocator = @ptrCast(@alignCast(raw));
        if (!self.admits(0, len)) return null;
        const buffer = self.backing.rawAlloc(len, alignment, ret) orelse return null;
        self.live.* += len;
        return buffer;
    }
    fn resize(raw: *anyopaque, old: []u8, alignment: std.mem.Alignment, len: usize, ret: usize) bool {
        const self: *CapacityAllocator = @ptrCast(@alignCast(raw));
        if (!self.admits(old.len, len) or !self.backing.rawResize(old, alignment, len, ret)) return false;
        self.live.* = self.live.* - old.len + len;
        return true;
    }
    fn remap(raw: *anyopaque, old: []u8, alignment: std.mem.Alignment, len: usize, ret: usize) ?[*]u8 {
        const self: *CapacityAllocator = @ptrCast(@alignCast(raw));
        if (!self.admits(old.len, len)) return null;
        const buffer = self.backing.rawRemap(old, alignment, len, ret) orelse return null;
        self.live.* = self.live.* - old.len + len;
        return buffer;
    }
    fn free(raw: *anyopaque, old: []u8, alignment: std.mem.Alignment, ret: usize) void {
        const self: *CapacityAllocator = @ptrCast(@alignCast(raw));
        self.backing.rawFree(old, alignment, ret);
        self.live.* -= old.len;
    }
};
pub fn Handle(comptime kind_: Kind) type {
    return struct {
        pub const kind = kind_;
        position: u32,
        owner: usize,
    };
}

pub const Storage = struct {
    inspected_positions: usize = 0,
    inspected_dependencies: usize = 0,
    lookup_declines: usize = 0,
    records: usize = 0,
    payload_bytes: usize = 0,
    capacity_bytes: usize = 0,
    saturated: usize = 0,
};

/// Both traversal directions share one bounded index. Links are positions,
/// never pointers into a growing record array. Duplicate keys retain their
/// own observations and explicit insertion order.
pub const PositionIndex = struct {
    const Ends = struct { oldest: u32, newest: u32 };
    const Link = struct { older: ?u32, newer: ?u32 = null };
    buckets: std.AutoHashMapUnmanaged(u64, Ends) = .empty,
    links: std.ArrayList(Link) = .empty,
    pub fn deinit(self: *PositionIndex, a: A) void {
        self.buckets.deinit(a);
        self.links.deinit(a);
    }
    pub fn prepare(self: *PositionIndex, a: A, bound: usize) A.Error!void {
        const needed = self.links.items.len + 1;
        std.debug.assert(needed <= bound);
        if (needed > self.links.capacity) try self.links.ensureTotalCapacityPrecise(a, @min(bound, @max(16, self.links.capacity * 2)));
        try self.buckets.ensureUnusedCapacity(a, 1);
    }
    pub fn publish(self: *PositionIndex, fingerprint: u64) void {
        const position: u32 = @intCast(self.links.items.len);
        const bucket = self.buckets.getOrPutAssumeCapacity(fingerprint);
        const previous: ?u32 = if (bucket.found_existing) bucket.value_ptr.newest else null;
        self.links.appendAssumeCapacity(.{ .older = previous });
        if (previous) |older| {
            self.links.items[older].newer = position;
            bucket.value_ptr.newest = position;
        } else bucket.value_ptr.* = .{ .oldest = position, .newest = position };
    }
    pub const Cursor = struct {
        index: *const PositionIndex,
        position: ?u32,
        order: Order,
        remaining: usize,
        inspected: usize = 0,
        pub fn next(self: *Cursor) ?u32 {
            if (self.remaining == 0) return null;
            const position = self.position orelse return null;
            self.remaining -= 1;
            self.inspected += 1;
            const link = self.index.links.items[position];
            self.position = if (self.order == .oldest_first) link.newer else link.older;
            return position;
        }
    };
    pub fn candidates(self: *const PositionIndex, fingerprint: u64, order: Order, budget: usize) Cursor {
        const ends = self.buckets.get(fingerprint);
        return .{ .index = self, .position = if (ends) |entry| (if (order == .oldest_first) entry.oldest else entry.newest) else null, .order = order, .remaining = budget };
    }
};

pub fn OwnedRecord(comptime kind_: Kind, comptime Key: type, comptime Dependencies: type, comptime Result: type) type {
    return struct {
        pub const kind = kind_;
        pub const schema: u32 = 1;
        key: Key,
        dependencies: Dependencies,
        value: Result,
        pub fn deinit(self: *@This(), a: A) void {
            self.key.deinit(a);
            self.dependencies.deinit(a);
            self.value.deinit(a);
            self.* = undefined;
        }
    };
}

/// Adapter defines Key/Dependencies/Result and the complete/fingerprint/bytes
/// judgments. Dependencies own their ordered replay publications. Builders own
/// every transferred part; preparation can change capacity, never record order
/// or visible facts. The adapter reserves evaluator replay destinations too.
pub fn Table(comptime Adapter: type) type {
    return struct {
        const Self = @This();
        pub const Record = OwnedRecord(Adapter.kind, Adapter.Key, Adapter.Dependencies, Adapter.Result);
        pub const QueryHandle = Handle(Adapter.kind);
        records: std.ArrayList(Record) = .empty,
        index: PositionIndex = .{},
        limits: Limits = .{},
        owned_bytes: usize = 0,
        capacity_bytes: usize = 0,
        saturated: usize = 0,
        pub fn storage(self: *const Self) Storage {
            return .{ .records = self.records.items.len, .payload_bytes = self.owned_bytes, .capacity_bytes = self.capacity_bytes, .saturated = self.saturated };
        }
        pub fn deinit(self: *Self, a: A) void {
            for (self.records.items) |*record| record.deinit(a);
            self.records.deinit(a);
            self.index.deinit(a);
        }
        pub const Builder = struct {
            allocator: A,
            key: ?Adapter.Key,
            dependencies: ?Adapter.Dependencies = null,
            value: ?Adapter.Result = null,
            pub fn read(self: *Builder, dependencies: Adapter.Dependencies) void {
                std.debug.assert(self.dependencies == null);
                self.dependencies = dependencies;
            }
            pub fn stage(self: *Builder, value: Adapter.Result) void {
                std.debug.assert(self.value == null);
                self.value = value;
            }
            pub fn abort(self: *Builder) void {
                if (self.key) |*key| key.deinit(self.allocator);
                if (self.dependencies) |*dependencies| dependencies.deinit(self.allocator);
                if (self.value) |*value| value.deinit(self.allocator);
                self.key = null;
                self.dependencies = null;
                self.value = null;
            }
            pub fn complete(self: *Builder) ?Candidate {
                const key = self.key orelse return null;
                const dependencies = self.dependencies orelse return null;
                const value = self.value orelse return null;
                const record: Record = .{ .key = key, .dependencies = dependencies, .value = value };
                if (!Adapter.complete(record)) return null;
                self.key = null;
                self.dependencies = null;
                self.value = null;
                return .{ .allocator = self.allocator, .record = record };
            }
        };
        pub fn begin(a: A, owned_key: Adapter.Key) Builder {
            return .{ .allocator = a, .key = owned_key };
        }
        pub const Candidate = struct {
            allocator: A,
            record: ?Record,
            pub fn abort(self: *Candidate) void {
                if (self.record) |*record| record.deinit(self.allocator);
                self.record = null;
            }
        };
        pub const Prepared = struct {
            owner: usize,
            candidate: usize,
            position: usize,
            fingerprint: u64,
            bytes: usize,
        };
        pub fn prepare(self: *Self, a: A, candidate: *const Candidate) A.Error!?Prepared {
            const record = candidate.record orelse return null;
            if (!Adapter.complete(record)) return null;
            const bytes = Adapter.bytes(record);
            if (self.records.items.len >= @min(self.limits.records, std.math.maxInt(u32)) or bytes > self.limits.owned_bytes -| self.owned_bytes) {
                self.saturated +|= 1;
                return null;
            }
            var capacity: CapacityAllocator = .{ .backing = a, .live = &self.capacity_bytes, .limit = self.limits.retained_capacity };
            self.reserve(capacity.allocator()) catch {
                if (!capacity.denied) return error.OutOfMemory;
                self.saturated +|= 1;
                return null;
            };
            return .{ .owner = @intFromPtr(self), .candidate = @intFromPtr(candidate), .position = self.records.items.len, .fingerprint = Adapter.fingerprint(record.key), .bytes = bytes };
        }
        fn reserve(self: *Self, a: A) A.Error!void {
            const needed = self.records.items.len + 1;
            if (needed > self.records.capacity) try self.records.ensureTotalCapacityPrecise(a, @min(self.limits.records, @max(16, self.records.capacity * 2)));
            try self.index.prepare(a, self.limits.records);
        }
        /// Caller revalidates its typed read set and revision context before
        /// installation. An intervening publication invalidates this token.
        pub fn validPrepared(self: *const Self, prepared: Prepared, candidate: *const Candidate) bool {
            const record = candidate.record orelse return false;
            return prepared.owner == @intFromPtr(self) and prepared.candidate == @intFromPtr(candidate) and prepared.position == self.records.items.len and prepared.fingerprint == Adapter.fingerprint(record.key) and prepared.bytes == Adapter.bytes(record);
        }
        pub fn publish(self: *Self, prepared: Prepared, candidate: *Candidate) QueryHandle {
            std.debug.assert(self.validPrepared(prepared, candidate));
            std.debug.assert(self.records.items.len == self.index.links.items.len);
            self.records.appendAssumeCapacity(candidate.record.?);
            candidate.record = null;
            self.index.publish(prepared.fingerprint);
            self.owned_bytes += prepared.bytes;
            return .{ .position = @intCast(prepared.position), .owner = prepared.owner };
        }
        pub fn get(self: *const Self, handle: QueryHandle) ?*const Record {
            if (handle.owner != @intFromPtr(self) or handle.position >= self.records.items.len) return null;
            return &self.records.items[handle.position];
        }
        pub fn candidates(self: *const Self, fingerprint: u64, order: Order) PositionIndex.Cursor {
            return self.index.candidates(fingerprint, order, self.limits.lookup_work);
        }
    };
}

const TestBytes = struct {
    data: []u8,
    pub fn deinit(self: *TestBytes, a: A) void {
        a.free(self.data);
    }
};
const TestDependencies = struct {
    data: []u8,
    known: bool = true,
    pub fn deinit(self: *TestDependencies, a: A) void {
        a.free(self.data);
    }
};
const TestAdapter = struct {
    pub const kind: Kind = .refinement;
    pub const Key = TestBytes;
    pub const Dependencies = TestDependencies;
    pub const Result = TestBytes;
    pub fn fingerprint(_: Key) u64 {
        return 0; // Deliberately collide every unequal key.
    }
    pub fn complete(record: TestTable.Record) bool {
        return record.dependencies.known;
    }
    pub fn bytes(record: TestTable.Record) usize {
        return record.key.data.len + record.dependencies.data.len + record.value.data.len;
    }
};
const TestTable = Table(TestAdapter);
fn testBuilder(a: A, key: []const u8, value: []const u8, known: bool) A.Error!TestTable.Builder {
    var builder = TestTable.begin(a, .{ .data = try a.dupe(u8, key) });
    errdefer builder.abort();
    builder.read(.{ .data = try a.dupe(u8, "ordered reads and publications"), .known = known });
    builder.stage(.{ .data = try a.dupe(u8, value) });
    return builder;
}
fn testInsert(a: A, table: *TestTable, key: []const u8, value: []const u8) !TestTable.QueryHandle {
    var builder = try testBuilder(a, key, value, true);
    defer builder.abort();
    var candidate = builder.complete() orelse return error.TestUnexpectedResult;
    defer candidate.abort();
    const count = table.records.items.len;
    const prepared = table.prepare(a, &candidate) catch {
        std.debug.assert(table.records.items.len == count and table.index.links.items.len == count);
        return error.OutOfMemory;
    } orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(count, table.records.items.len);
    return table.publish(prepared, &candidate);
}
fn testLookup(table: *const TestTable, key: []const u8, order: Order) ?[]const u8 {
    var cursor = table.candidates(0, order);
    while (cursor.next()) |position| {
        const record = table.records.items[position];
        if (std.mem.eql(u8, record.key.data, key)) return record.value.data;
    }
    return null;
}
fn orderedScenario(a: A) !void {
    var table: TestTable = .{};
    defer table.deinit(a);
    const first = try testInsert(a, &table, "same", "old complete result");
    _ = try testInsert(a, &table, "different", "collision must miss");
    _ = try testInsert(a, &table, "same", "new complete result");
    try std.testing.expectEqualStrings("old complete result", table.get(first).?.value.data);
    try std.testing.expectEqualStrings("old complete result", testLookup(&table, "same", .oldest_first).?);
    try std.testing.expectEqualStrings("new complete result", testLookup(&table, "same", .newest_first).?);
    try std.testing.expect(testLookup(&table, "missing", .oldest_first) == null);
    var foreign: TestTable = .{};
    defer foreign.deinit(a);
    try std.testing.expect(foreign.get(first) == null);
    table.limits.lookup_work = 2;
    try std.testing.expect(testLookup(&table, "different", .oldest_first) != null);
    table.limits.lookup_work = 1;
    try std.testing.expect(testLookup(&table, "different", .oldest_first) == null);
}
test "owned query table preserves first valid order across forced collisions and allocation failures" {
    try orderedScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, orderedScenario, .{});
}
test "owned query builder cannot publish unknown observations and saturation remains bounded" {
    const a = std.testing.allocator;
    var table: TestTable = .{ .limits = .{ .records = 1, .owned_bytes = 1024, .lookup_work = 1 } };
    defer table.deinit(a);
    var incomplete = try testBuilder(a, "unknown", "private", false);
    defer incomplete.abort();
    try std.testing.expect(incomplete.complete() == null);
    try std.testing.expectEqual(@as(usize, 0), table.records.items.len);
    _ = try testInsert(a, &table, "complete", "published");
    var builder = try testBuilder(a, "second", "must decline", true);
    defer builder.abort();
    var candidate = builder.complete().?;
    defer candidate.abort();
    try std.testing.expect((try table.prepare(a, &candidate)) == null);
    try std.testing.expectEqual(@as(usize, 1), table.records.items.len);
    try std.testing.expectEqual(@as(usize, 1), table.records.capacity);
    try std.testing.expectEqual(@as(usize, 1), table.index.links.capacity);
    try std.testing.expectEqualStrings("published", testLookup(&table, "complete", .oldest_first).?);
    table.limits.records = 2;
    table.limits.owned_bytes = table.owned_bytes;
    try std.testing.expect((try table.prepare(a, &candidate)) == null);
    try std.testing.expectEqual(@as(usize, 1), table.records.items.len);
}

test "owned query capacity is measured and bounded and preparation binds one candidate" {
    var tracked: @import("memory.zig").TrackedAllocator = .{ .backing = std.testing.allocator };
    const a = tracked.allocator();
    {
        var table: TestTable = .{ .limits = .{ .retained_capacity = 1 } };
        defer table.deinit(a);
        var first = try testBuilder(a, "first", "first result", true);
        defer first.abort();
        var left = first.complete().?;
        defer left.abort();
        const private_bytes = tracked.counts.live_bytes;
        try std.testing.expect((try table.prepare(a, &left)) == null);
        try std.testing.expectEqual(@as(usize, 0), table.capacity_bytes);
        table.limits.retained_capacity = 64 * 1024;
        const prepared = (try table.prepare(a, &left)).?;
        try std.testing.expect(table.capacity_bytes <= table.limits.retained_capacity);
        try std.testing.expectEqual(tracked.counts.live_bytes - private_bytes, table.capacity_bytes);
        var second = try testBuilder(a, "second", "second result", true);
        defer second.abort();
        var right = second.complete().?;
        defer right.abort();
        const other = (try table.prepare(a, &right)).?;
        try std.testing.expect(table.validPrepared(prepared, &left));
        try std.testing.expect(!table.validPrepared(prepared, &right));
        try std.testing.expect(!table.validPrepared(other, &left));
        _ = table.publish(prepared, &left);
        try std.testing.expect(!table.validPrepared(other, &right));
        const retry = (try table.prepare(a, &right)).?;
        _ = table.publish(retry, &right);
        try std.testing.expectEqual(table.capacity_bytes + table.owned_bytes, tracked.counts.live_bytes);
    }
    try std.testing.expectEqual(@as(usize, 0), tracked.counts.live_bytes);
}
