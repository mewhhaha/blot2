//! Interned semantic types for specialization and pure evaluation. This table
//! preserves nominal arguments and has no dependency on a machine layout or
//! runtime value representation. Published IDs remain stable through growth.
const std = @import("std");
const types = @import("types.zig");
const projections = @import("projection_cache.zig");
pub const Effects = @import("effect_evidence.zig");
const Allocator = std.mem.Allocator;
pub const Id = u32;
pub const Tag = enum(u8) { absent, unit, boolean, u32, f32, never, function, product, record, nominal, array, list, cursor, demand, type_constructor, resolver, provider, state_provider };
pub const Node = struct { tag: Tag, a: u32 = 0, b: u32 = 0, c: u32 = 0 };
pub const Mapping = struct { variable: types.Id, evidence: Id };
pub const RowMapping = struct { variable: u32, evidence: Effects.Id };
pub const Error = Allocator.Error || error{ UnresolvedType, EvidenceLimit, TypeMismatch };
pub const View = struct {
    nodes: []const Node,
    extra: []const Id,
    effects: Effects.View = .{},
    pub fn node(self: View, id: Id) Node {
        return self.nodes[id];
    }
    pub fn children(self: View, id: Id) []const Id {
        const n = self.node(id);
        return switch (n.tag) {
            .product => self.extra[n.a..][0..n.b],
            .record => self.extra[n.a..][0 .. @as(usize, n.b) * 2],
            .nominal => self.extra[n.c + 1 ..][0..self.extra[n.c]],
            else => &.{},
        };
    }
};
pub const Snapshot = struct {
    nodes: []Node,
    extra: []Id,
    effects: Effects.Snapshot,
    pub fn view(self: *const Snapshot) View {
        return .{ .nodes = self.nodes, .extra = self.extra, .effects = self.effects.view() };
    }
    pub fn deinit(self: *Snapshot, allocator: Allocator) void {
        allocator.free(self.nodes);
        allocator.free(self.extra);
        self.effects.deinit(allocator);
        self.* = undefined;
    }
};
pub const Store = struct {
    allocator: Allocator,
    effects: Effects.Store,
    nodes: std.ArrayList(Node) = .empty,
    extra: std.ArrayList(Id) = .empty,
    next: std.ArrayList(Id) = .empty,
    buckets: std.AutoHashMapUnmanaged(u64, Id) = .empty,
    pub fn init(allocator: Allocator) Error!Store {
        var self: Store = .{ .allocator = allocator, .effects = .{ .allocator = allocator } };
        errdefer self.deinit();
        self.effects = try Effects.Store.init(allocator);
        try self.nodes.appendSlice(allocator, &.{ .{ .tag = .absent }, .{ .tag = .unit }, .{ .tag = .boolean }, .{ .tag = .u32 }, .{ .tag = .f32 }, .{ .tag = .never } });
        try self.next.appendNTimes(allocator, 0, self.nodes.items.len);
        return self;
    }
    pub fn deinit(self: *Store) void {
        self.effects.deinit();
        self.nodes.deinit(self.allocator);
        self.extra.deinit(self.allocator);
        self.next.deinit(self.allocator);
        self.buckets.deinit(self.allocator);
        self.* = undefined;
    }
    pub fn view(self: *const Store) View {
        return .{ .nodes = self.nodes.items, .extra = self.extra.items, .effects = self.effects.view() };
    }
    pub fn node(self: *const Store, id: Id) Node {
        return self.view().node(id);
    }
    pub fn children(self: *const Store, id: Id) []const Id {
        return self.view().children(id);
    }
    pub fn copyOwned(self: *const Store, allocator: Allocator) Allocator.Error!Snapshot {
        const nodes = try allocator.dupe(Node, self.nodes.items);
        errdefer allocator.free(nodes);
        const extra = try allocator.dupe(Id, self.extra.items);
        errdefer allocator.free(extra);
        return .{ .nodes = nodes, .extra = extra, .effects = try self.effects.copyOwned(allocator) };
    }
    /// Record fields are canonicalized by name: semantic equality is independent
    /// of payload slots, which remain in the separate core/layout catalogs.
    pub fn intern(self: *Store, tag: Tag, a: u32, b: u32, values: []const Id) Error!Id {
        return self.internWithEffects(tag, a, b, 0, values);
    }
    pub fn internWithEffects(self: *Store, tag: Tag, a: u32, b: u32, row: Effects.Id, values: []const Id) Error!Id {
        return self.internFields(tag, a, b, row, values);
    }
    pub fn internStateProvider(self: *Store, read: Id, write: Id, state: Id) Error!Id {
        return self.internFields(.state_provider, read, write, state, &.{});
    }
    fn internFields(self: *Store, tag: Tag, a: u32, b: u32, row: u32, values: []const Id) Error!Id {
        var scratch_buffer: [256]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const allocator = scratch.allocator();
        const owned = try allocator.dupe(Id, values);
        defer allocator.free(owned);
        if (tag == .record) {
            if (owned.len % 2 != 0) return error.TypeMismatch;
            const FieldWords = extern struct {
                name: Id,
                evidence: Id,
                fn less(_: void, left: @This(), right: @This()) bool {
                    return left.name < right.name;
                }
            };
            const fields = @as([*]FieldWords, @ptrCast(owned.ptr))[0 .. owned.len / 2];
            std.mem.sortUnstable(FieldWords, fields, {}, FieldWords.less);
            if (fields.len > 1) for (fields[1..], fields[0 .. fields.len - 1]) |field, prior| if (field.name == prior.name) return error.TypeMismatch;
        }
        var hash = std.hash.Wyhash.init(0);
        hash.update(std.mem.asBytes(&tag));
        hash.update(std.mem.asBytes(&a));
        hash.update(std.mem.asBytes(&b));
        hash.update(std.mem.asBytes(&row));
        hash.update(std.mem.sliceAsBytes(owned));
        return self.internWithEffectsHashed(tag, a, b, row, owned, hash.final());
    }
    fn internHashed(self: *Store, tag: Tag, a: u32, b: u32, values: []const Id, fingerprint: u64) Error!Id {
        return self.internWithEffectsHashed(tag, a, b, 0, values, fingerprint);
    }
    fn internWithEffectsHashed(self: *Store, tag: Tag, a: u32, b: u32, row: Effects.Id, values: []const Id, fingerprint: u64) Error!Id {
        if (tag != .state_provider and (row >= self.effects.rows.items.len or (row != 0 and tag != .function and tag != .demand and tag != .provider))) return error.TypeMismatch;
        switch (tag) {
            .absent => return error.UnresolvedType,
            .unit, .boolean, .u32, .f32, .never => {
                if (a != 0 or b != 0 or values.len != 0) return error.TypeMismatch;
                return switch (tag) {
                    .unit => types.unit,
                    .boolean => types.boolean,
                    .u32 => types.u32_type,
                    .f32 => types.f32_type,
                    .never => types.never,
                    else => unreachable,
                };
            },
            .function => if (values.len != 0 or a == 0 or b == 0 or a >= self.nodes.items.len or b >= self.nodes.items.len) return error.TypeMismatch,
            .array, .list, .cursor, .demand, .resolver, .provider => if (values.len != 0 or a == 0 or a >= self.nodes.items.len or b != 0) return error.TypeMismatch,
            .state_provider => if (values.len != 0 or a == 0 or b == 0 or row == 0 or a >= self.nodes.items.len or b >= self.nodes.items.len or row >= self.nodes.items.len) return error.TypeMismatch,
            .product, .record => if (a != 0 or b != 0) return error.TypeMismatch,
            .nominal => if (a == 0) return error.TypeMismatch,
            .type_constructor => if (a == 0 or b == 0 or values.len != 0) return error.TypeMismatch,
        }
        if (tag == .provider and self.node(a).tag != .nominal) return error.TypeMismatch;
        if (tag == .state_provider and (self.node(a).tag != .nominal or self.node(b).tag != .nominal)) return error.TypeMismatch;
        for (values, 0..) |value, i| {
            if (tag == .record and i % 2 == 0) {
                if (value == 0) return error.TypeMismatch;
            } else if (value == 0 or value >= self.nodes.items.len) return error.TypeMismatch;
        }
        var candidate = self.buckets.get(fingerprint) orelse 0;
        while (candidate != 0) : (candidate = self.next.items[candidate]) {
            const n = self.node(candidate);
            const same = n.tag == tag and switch (tag) {
                .product, .record => std.mem.eql(Id, self.children(candidate), values),
                .nominal => n.a == a and n.b == b and std.mem.eql(Id, self.children(candidate), values),
                else => n.a == a and n.b == b and n.c == row,
            };
            if (same) return candidate;
        }
        if (self.nodes.items.len >= std.math.maxInt(Id) or values.len >= std.math.maxInt(Id) or self.extra.items.len > std.math.maxInt(Id) - values.len - 1) return error.EvidenceLimit;
        const bucket = try self.buckets.getOrPut(self.allocator, fingerprint);
        if (!bucket.found_existing) bucket.value_ptr.* = 0;
        // Reserve every buffer before exposing an ID. Failure leaves every
        // previously published ID, node and child span unchanged.
        try self.nodes.ensureUnusedCapacity(self.allocator, 1);
        try self.next.ensureUnusedCapacity(self.allocator, 1);
        try self.extra.ensureUnusedCapacity(self.allocator, values.len + 1);
        var n: Node = .{ .tag = tag, .a = a, .b = b, .c = row };
        switch (tag) {
            .product, .record => {
                n.a = @intCast(self.extra.items.len);
                n.b = @intCast(if (tag == .record) values.len / 2 else values.len);
                self.extra.appendSliceAssumeCapacity(values);
            },
            .nominal => {
                n.c = @intCast(self.extra.items.len);
                self.extra.appendAssumeCapacity(@intCast(values.len));
                self.extra.appendSliceAssumeCapacity(values);
            },
            else => {},
        }
        const id: Id = @intCast(self.nodes.items.len);
        self.nodes.appendAssumeCapacity(n);
        self.next.appendAssumeCapacity(bucket.value_ptr.*);
        bucket.value_ptr.* = id;
        return id;
    }
    /// Source is an immutable, normalized core.Types-compatible table. Mapping
    /// variables are local to that source module; evidence IDs are session-wide.
    pub fn project(self: *Store, source: anytype, ty: types.Id, mappings: []const Mapping) Error!Id {
        return self.projectWithRows(source, ty, mappings, &.{});
    }
    pub fn projectWithRows(self: *Store, source: anytype, ty: types.Id, mappings: []const Mapping, rows: []const RowMapping) Error!Id {
        var budget: usize = 1_000_000;
        return self.projectDepth(source, ty, mappings, rows, 0, &budget, false, null, null);
    }
    pub fn projectEffects(self: *Store, source: anytype, row: types.Effects.Id, mappings: []const Mapping, rows: []const RowMapping) Error!Effects.Id {
        var budget: usize = 1_000_000;
        return self.projectRowDepth(source, row, mappings, rows, 0, &budget, false, null, null);
    }
    /// Owned inference has no caller mappings. Successful normalized subgraphs
    /// are immutable until rollback or physical mutation changes their clocks.
    /// Share the ordinary projector, including its exact depth and work limits.
    pub fn projectOwned(self: *Store, source: *const types.Store, ty: types.Id, memo: *projections.Cache) Error!Id {
        if (!memo.activate(source, self, source.closed_generation, source.effects.physical_epoch)) return self.project(source, ty, &.{});
        var budget: usize = 1_000_000;
        return self.projectDepth(source, ty, &.{}, &.{}, 0, &budget, true, memo, null);
    }
    fn projectDepth(self: *Store, source: anytype, ty: types.Id, mappings: []const Mapping, rows: []const RowMapping, depth: usize, budget: *usize, comptime retained: bool, memo: ?*projections.Cache, parent_height: ?*u16) Error!Id {
        if (depth >= 1024 or budget.* == 0) return error.EvidenceLimit;
        if (retained and ty > types.never) if (memo.?.answers.get(ty)) |answer| {
            if (depth + answer.height > 1024 or budget.* < answer.visits) return error.EvidenceLimit;
            budget.* -= answer.visits;
            if (parent_height) |parent| parent.* = @max(parent.*, answer.height + 1);
            return answer.value;
        };
        const before = budget.*;
        budget.* -= 1;
        var height: u16 = 1;
        const result = try self.projectNodeDepth(source, ty, mappings, rows, depth, budget, retained, memo, &height);
        if (retained) {
            if (parent_height) |parent| parent.* = @max(parent.*, height + 1);
            if (ty > types.never) try memo.?.answers.put(memo.?.allocator orelse self.allocator, ty, .{ .value = result, .visits = @intCast(before - budget.*), .height = height });
        }
        return result;
    }
    fn projectRowDepth(self: *Store, source: anytype, row: types.Effects.Id, mappings: []const Mapping, rows: []const RowMapping, depth: usize, budget: *usize, comptime retained: bool, memo: ?*projections.Cache, parent_height: ?*u16) Error!Effects.Id {
        if (depth >= 1024 or budget.* == 0) return error.EvidenceLimit;
        budget.* -= 1;
        var height: u16 = 1;
        const result = try self.projectRowBody(source, row, mappings, rows, depth, budget, retained, memo, &height);
        if (retained) if (parent_height) |parent| {
            parent.* = @max(parent.*, height + 1);
        };
        return result;
    }
    fn projectNodeDepth(self: *Store, source: anytype, ty: types.Id, mappings: []const Mapping, rows: []const RowMapping, depth: usize, budget: *usize, comptime retained: bool, memo: ?*projections.Cache, height: *u16) Error!Id {
        for (mappings) |mapping| if (mapping.variable == ty) {
            if (mapping.evidence == 0 or mapping.evidence >= self.nodes.items.len) return error.TypeMismatch;
            return mapping.evidence;
        };
        const n = source.node(ty);
        switch (n.tag) {
            .unit => return types.unit,
            .boolean => return types.boolean,
            .u32 => return types.u32_type,
            .f32 => return types.f32_type,
            .never => return types.never,
            .variable, .absent => return error.UnresolvedType,
            .array => return self.intern(.array, try self.projectDepth(source, n.a, mappings, rows, depth + 1, budget, retained, memo, height), 0, &.{}),
            .list => return self.intern(.list, try self.projectDepth(source, n.a, mappings, rows, depth + 1, budget, retained, memo, height), 0, &.{}),
            .cursor => return self.intern(.cursor, try self.projectDepth(source, n.a, mappings, rows, depth + 1, budget, retained, memo, height), 0, &.{}),
            .demand => return self.internWithEffects(.demand, try self.projectDepth(source, n.a, mappings, rows, depth + 1, budget, retained, memo, height), 0, try self.projectRowDepth(source, n.c, mappings, rows, depth + 1, budget, retained, memo, height), &.{}),
            .resolver => return self.intern(.resolver, try self.projectDepth(source, n.a, mappings, rows, depth + 1, budget, retained, memo, height), 0, &.{}),
            .provider => return self.internWithEffects(.provider, try self.projectDepth(source, n.a, mappings, rows, depth + 1, budget, retained, memo, height), 0, try self.projectRowDepth(source, n.c, mappings, rows, depth + 1, budget, retained, memo, height), &.{}),
            .state_provider => return self.internStateProvider(try self.projectDepth(source, n.a, mappings, rows, depth + 1, budget, retained, memo, height), try self.projectDepth(source, n.b, mappings, rows, depth + 1, budget, retained, memo, height), try self.projectDepth(source, n.c, mappings, rows, depth + 1, budget, retained, memo, height)),
            .type_constructor => return self.intern(.type_constructor, n.a, n.b, &.{}),
            .function => return self.internWithEffects(.function, try self.projectDepth(source, n.a, mappings, rows, depth + 1, budget, retained, memo, height), try self.projectDepth(source, n.b, mappings, rows, depth + 1, budget, retained, memo, height), try self.projectRowDepth(source, n.c, mappings, rows, depth + 1, budget, retained, memo, height), &.{}),
            .product, .record, .nominal => {
                var scratch_buffer: [256]u8 align(@alignOf(usize)) = undefined;
                var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
                const allocator = scratch.allocator();
                var values: std.ArrayList(Id) = .empty;
                defer values.deinit(allocator);
                if (n.tag == .record) {
                    for (0..n.b) |index| {
                        const field = source.recordField(n, index);
                        try values.append(allocator, field.name);
                        try values.append(allocator, try self.projectDepth(source, field.ty, mappings, rows, depth + 1, budget, retained, memo, height));
                    }
                } else {
                    const children_ = if (n.tag == .nominal) source.nominalArguments(n) else source.list(.{ .start = n.a, .len = n.b });
                    for (children_) |child| try values.append(allocator, try self.projectDepth(source, child, mappings, rows, depth + 1, budget, retained, memo, height));
                }
                return self.intern(switch (n.tag) {
                    .product => .product,
                    .record => .record,
                    .nominal => .nominal,
                    else => unreachable,
                }, if (n.tag == .nominal) n.a else 0, if (n.tag == .nominal) n.b else 0, values.items);
            },
        }
    }
    fn projectRowBody(self: *Store, source: anytype, row: types.Effects.Id, mappings: []const Mapping, rows: []const RowMapping, depth: usize, budget: *usize, comptime retained: bool, memo: ?*projections.Cache, height: *u16) Error!Effects.Id {
        const tail = source.row(row).tail;
        var suffix: Effects.Id = 0;
        switch (tail) {
            .closed => {},
            .parameter => return error.UnresolvedType,
            .variable => |variable| {
                var found = false;
                for (rows) |mapping| if (mapping.variable == variable) {
                    if (mapping.evidence >= self.effects.rows.items.len) return error.TypeMismatch;
                    suffix = mapping.evidence;
                    found = true;
                    break;
                };
                if (!found) return error.UnresolvedType;
            },
        }
        var scratch_buffer: [256]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const allocator = scratch.allocator();
        var labels: std.ArrayList(Effects.Label) = .empty;
        defer labels.deinit(allocator);
        var arguments: std.ArrayList(Id) = .empty;
        defer arguments.deinit(allocator);
        for (source.rowLabels(row)) |label| {
            arguments.clearRetainingCapacity();
            for (source.operationArguments(label)) |argument| try arguments.append(allocator, try self.projectDepth(source, argument, mappings, rows, depth + 1, budget, retained, memo, height));
            try labels.append(allocator, try self.effects.internOperation(source.operation(label).identity, arguments.items));
        }
        try labels.appendSlice(allocator, self.effects.view().rowLabels(suffix));
        return self.effects.internRow(labels.items);
    }
    /// Matching only appends variable substitutions; a failed candidate restores
    /// the entire mapping frontier, without changing any previously bound ID.
    pub fn match(self: *Store, source: anytype, pattern: types.Id, actual: Id, mappings: *std.ArrayList(Mapping)) Error!bool {
        return self.matchWithRowsOptional(source, pattern, actual, mappings, null);
    }
    pub fn matchWithRows(self: *Store, source: anytype, pattern: types.Id, actual: Id, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping)) Error!bool {
        return self.matchWithRowsOptional(source, pattern, actual, mappings, rows);
    }
    fn matchWithRowsOptional(self: *Store, source: anytype, pattern: types.Id, actual: Id, mappings: *std.ArrayList(Mapping), rows: ?*std.ArrayList(RowMapping)) Error!bool {
        const row_start = if (rows) |values| values.items.len else 0;
        errdefer if (rows) |values| values.shrinkRetainingCapacity(row_start);
        const start = mappings.items.len;
        errdefer mappings.shrinkRetainingCapacity(start);
        var budget: usize = 1_000_000;
        const accepted = try self.matchDepth(source, pattern, actual, mappings, rows, 0, &budget);
        if (!accepted) {
            mappings.shrinkRetainingCapacity(start);
            if (rows) |values| values.shrinkRetainingCapacity(row_start);
        }
        return accepted;
    }
    fn matchDepth(self: *Store, source: anytype, pattern: types.Id, actual: Id, mappings: *std.ArrayList(Mapping), rows: ?*std.ArrayList(RowMapping), depth: usize, budget: *usize) Error!bool {
        if (depth >= 1024 or budget.* == 0) return error.EvidenceLimit;
        budget.* -= 1;
        if (actual == 0 or actual >= self.nodes.items.len) return error.UnresolvedType;
        const n = source.node(pattern);
        const concrete = self.node(actual);
        if (n.tag == .never or concrete.tag == .never) return true;
        if (n.tag == .variable) {
            for (mappings.items) |mapping| if (mapping.variable == pattern) return mapping.evidence == actual;
            try mappings.append(self.allocator, .{ .variable = pattern, .evidence = actual });
            return true;
        }
        const same = switch (n.tag) {
            .absent => false,
            .unit => concrete.tag == .unit,
            .boolean => concrete.tag == .boolean,
            .u32 => concrete.tag == .u32,
            .f32 => concrete.tag == .f32,
            .array => concrete.tag == .array,
            .list => concrete.tag == .list,
            .cursor => concrete.tag == .cursor,
            .demand => concrete.tag == .demand,
            .resolver => concrete.tag == .resolver,
            .provider => concrete.tag == .provider,
            .state_provider => concrete.tag == .state_provider,
            .type_constructor => concrete.tag == .type_constructor and n.a == concrete.a and n.b == concrete.b,
            .function => concrete.tag == .function,
            .product => concrete.tag == .product,
            .record => concrete.tag == .record,
            .nominal => concrete.tag == .nominal and n.a == concrete.a and n.b == concrete.b,
            .variable, .never => unreachable,
        };
        if (!same) return false;
        if ((n.tag == .function or n.tag == .demand or n.tag == .provider) and !try self.matchRowDepth(source, n.c, concrete.c, mappings, rows, depth + 1, budget)) return false;
        switch (n.tag) {
            .array, .list, .cursor, .demand, .resolver, .provider => return self.matchDepth(source, n.a, concrete.a, mappings, rows, depth + 1, budget),
            .state_provider => return try self.matchDepth(source, n.a, concrete.a, mappings, rows, depth + 1, budget) and try self.matchDepth(source, n.b, concrete.b, mappings, rows, depth + 1, budget) and try self.matchDepth(source, n.c, concrete.c, mappings, rows, depth + 1, budget),
            .function => return try self.matchDepth(source, n.a, concrete.a, mappings, rows, depth + 1, budget) and try self.matchDepth(source, n.b, concrete.b, mappings, rows, depth + 1, budget),
            .product, .nominal => {
                const expected = if (n.tag == .nominal) source.nominalArguments(n) else source.list(.{ .start = n.a, .len = n.b });
                const actuals = self.children(actual);
                if (expected.len != actuals.len) return false;
                for (expected, actuals) |child, child_actual| if (!try self.matchDepth(source, child, child_actual, mappings, rows, depth + 1, budget)) return false;
            },
            .record => {
                const fields = self.children(actual);
                if (fields.len != @as(usize, n.b) * 2) return false;
                for (0..n.b) |index| {
                    const field = source.recordField(n, index);
                    var found = false;
                    var i: usize = 0;
                    while (i < fields.len) : (i += 2) if (fields[i] == field.name) {
                        if (!try self.matchDepth(source, field.ty, fields[i + 1], mappings, rows, depth + 1, budget)) return false;
                        found = true;
                        break;
                    };
                    if (!found) return false;
                }
            },
            else => {},
        }
        return true;
    }
    fn matchRowDepth(self: *Store, source: anytype, pattern: types.Effects.Id, actual: Effects.Id, mappings: *std.ArrayList(Mapping), rows: ?*std.ArrayList(RowMapping), depth: usize, budget: *usize) Error!bool {
        const tail = source.row(pattern).tail;
        if (tail == .parameter or (tail == .variable and rows == null)) return error.UnresolvedType;
        const expected = source.rowLabels(pattern);
        const actuals = try self.allocator.dupe(Effects.Label, self.effects.view().rowLabels(actual));
        defer self.allocator.free(actuals);
        if (expected.len > actuals.len or (tail == .closed and expected.len != actuals.len)) return false;
        const used = try self.allocator.alloc(bool, actuals.len);
        defer self.allocator.free(used);
        @memset(used, false);
        return self.matchOperations(source, expected, actuals, used, tail, 0, mappings, rows, depth, budget);
    }
    fn matchOperations(self: *Store, source: anytype, expected: []const types.Effects.Label, actuals: []const Effects.Label, used: []bool, tail: types.Effects.Tail, index: usize, mappings: *std.ArrayList(Mapping), rows: ?*std.ArrayList(RowMapping), depth: usize, budget: *usize) Error!bool {
        if (depth >= 1024 or budget.* == 0) return error.EvidenceLimit;
        budget.* -= 1;
        if (index == expected.len) {
            if (tail == .closed) return true;
            var remaining: std.ArrayList(Effects.Label) = .empty;
            defer remaining.deinit(self.allocator);
            for (actuals, used) |label, consumed| if (!consumed) try remaining.append(self.allocator, label);
            const suffix = try self.effects.internRow(remaining.items);
            for (rows.?.items) |mapping| if (mapping.variable == tail.variable) return mapping.evidence == suffix;
            try rows.?.append(self.allocator, .{ .variable = tail.variable, .evidence = suffix });
            return true;
        }
        const operation = source.operation(expected[index]);
        const arguments = source.operationArguments(expected[index]);
        for (actuals, 0..) |label, i| {
            if (used[i]) continue;
            const concrete = self.effects.view().operation(label);
            if (operation.identity.unit != concrete.identity.unit or operation.identity.decl != concrete.identity.decl) continue;
            const actual_arguments = self.effects.view().operationArguments(label);
            if (arguments.len != actual_arguments.len) continue;
            const frontier = mappings.items.len;
            const row_frontier = if (rows) |values| values.items.len else 0;
            var same = true;
            for (arguments, actual_arguments) |argument, concrete_argument| {
                if (!try self.matchDepth(source, argument, concrete_argument, mappings, rows, depth + 1, budget)) {
                    same = false;
                    break;
                }
            }
            if (same) {
                used[i] = true;
                if (try self.matchOperations(source, expected, actuals, used, tail, index + 1, mappings, rows, depth + 1, budget)) return true;
                used[i] = false;
            }
            mappings.shrinkRetainingCapacity(frontier);
            if (rows) |values| values.shrinkRetainingCapacity(row_frontier);
        }
        return false;
    }
};

fn providerEvidenceScenario(allocator: Allocator) !void {
    var source = try types.Store.init(allocator);
    defer source.deinit();
    const variable = try source.fresh();
    const phantom = try source.nominal(.{ .unit = 2, .decl = 9 }, &.{variable});
    const read = try source.nominal(.{ .unit = 2, .decl = 10 }, &.{phantom});
    const write = try source.nominal(.{ .unit = 2, .decl = 11 }, &.{phantom});
    const row = try source.freshEffects();
    const provider = try source.provider(read, row);
    const state = try source.stateProvider(read, write, phantom);
    var semantic = try Store.init(allocator);
    defer semantic.deinit();
    const type_maps = [_]Mapping{.{ .variable = variable, .evidence = types.u32_type }};
    const row_maps = [_]RowMapping{.{ .variable = source.row(row).tail.variable, .evidence = 0 }};
    if (semantic.projectWithRows(&source, provider, &type_maps, &.{})) |_| {
        return error.TestExpectedError;
    } else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.UnresolvedType, err);
    }
    const concrete = try semantic.projectWithRows(&source, provider, &type_maps, &row_maps);
    const state_type = try semantic.project(&source, state, &type_maps);
    try std.testing.expectEqual(Tag.provider, semantic.node(concrete).tag);
    try std.testing.expectEqual(Tag.nominal, semantic.node(semantic.node(state_type).c).tag);
    const operation = try semantic.effects.internOperation(.{ .unit = 2, .decl = 12 }, &.{});
    const effect_row = try semantic.effects.internRow(&.{operation});
    const effectful = try semantic.internWithEffects(.provider, semantic.node(concrete).a, 0, effect_row, &.{});
    try std.testing.expect(concrete != effectful);
    try std.testing.expectError(error.TypeMismatch, semantic.internWithEffects(.provider, types.u32_type, 0, 0, &.{}));
    var maps: std.ArrayList(Mapping) = .empty;
    defer maps.deinit(allocator);
    var rows: std.ArrayList(RowMapping) = .empty;
    defer rows.deinit(allocator);
    try std.testing.expect(try semantic.matchWithRows(&source, provider, effectful, &maps, &rows));
    try std.testing.expectEqual(types.u32_type, maps.items[0].evidence);
    try std.testing.expectEqual(effect_row, rows.items[0].evidence);
    maps.clearRetainingCapacity();
    rows.clearRetainingCapacity();
    const float_phantom = try semantic.intern(.nominal, 2, 9, &.{types.f32_type});
    const float_write = try semantic.intern(.nominal, 2, 11, &.{float_phantom});
    const contradictory = try semantic.internStateProvider(semantic.node(state_type).a, float_write, semantic.node(state_type).c);
    try std.testing.expect(!try semantic.matchWithRows(&source, state, contradictory, &maps, &rows));
    try std.testing.expectEqual(@as(usize, 0), maps.items.len);
    try std.testing.expectEqual(@as(usize, 0), rows.items.len);
    var snapshot = try semantic.copyOwned(allocator);
    defer snapshot.deinit(allocator);
    try std.testing.expectEqualDeep(semantic.node(state_type), snapshot.view().node(state_type));
}
test "provider evidence preserves operation arguments, implementation effects and state types" {
    try providerEvidenceScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, providerEvidenceScenario, .{});
}

test "semantic evidence distinguishes phantom arguments while interning exact repeated types" {
    const a = std.testing.allocator;
    var source = try types.Store.init(a);
    defer source.deinit();
    const variable = try source.fresh();
    const phantom = try source.nominal(.{ .unit = 7, .decl = 3 }, &.{variable});
    var evidence = try Store.init(a);
    defer evidence.deinit();
    try std.testing.expectError(error.UnresolvedType, evidence.project(&source, phantom, &.{}));
    const integer = try evidence.project(&source, phantom, &.{.{ .variable = variable, .evidence = types.u32_type }});
    const floating = try evidence.project(&source, phantom, &.{.{ .variable = variable, .evidence = types.f32_type }});
    try std.testing.expect(integer != floating);
    try std.testing.expectEqual(types.u32_type, evidence.children(integer)[0]);
    try std.testing.expectEqual(types.f32_type, evidence.children(floating)[0]);
    try std.testing.expectEqual(integer, try evidence.project(&source, phantom, &.{.{ .variable = variable, .evidence = types.u32_type }}));
    const different_owner = try evidence.intern(.nominal, 8, 3, &.{types.u32_type});
    try std.testing.expect(different_owner != integer);
    // A builtin U32 and a nominal at the same declaration slot remain distinct.
    try std.testing.expectEqual(Tag.nominal, evidence.node(integer).tag);
    try std.testing.expectEqual(Tag.u32, evidence.node(types.u32_type).tag);
}
test "candidate matching checks phantom substitutions and rolls back failed parameter probes" {
    const a = std.testing.allocator;
    var source = try types.Store.init(a);
    defer source.deinit();
    const variable = try source.fresh();
    const phantom = try source.nominal(.{ .unit = 1, .decl = 42 }, &.{variable});
    const pattern = try source.function(phantom, try source.function(variable, types.u32_type));
    var evidence = try Store.init(a);
    defer evidence.deinit();
    const integer = try evidence.intern(.nominal, 1, 42, &.{types.u32_type});
    const accepted = try evidence.intern(.function, integer, try evidence.intern(.function, types.u32_type, types.u32_type, &.{}), &.{});
    const rejected = try evidence.intern(.function, integer, try evidence.intern(.function, types.f32_type, types.u32_type, &.{}), &.{});
    var mappings: std.ArrayList(Mapping) = .empty;
    defer mappings.deinit(a);
    try std.testing.expect(!try evidence.match(&source, pattern, rejected, &mappings));
    try std.testing.expectEqual(@as(usize, 0), mappings.items.len);
    try std.testing.expect(try evidence.match(&source, pattern, accepted, &mappings));
    try std.testing.expectEqual(@as(usize, 1), mappings.items.len);
    try std.testing.expectEqual(types.u32_type, mappings.items[0].evidence);
    try std.testing.expect(!try evidence.match(&source, pattern, rejected, &mappings));
    try std.testing.expectEqual(@as(usize, 1), mappings.items.len);
    try std.testing.expectEqual(types.u32_type, mappings.items[0].evidence);
}
test "semantic record equality is independent of field order and hash collisions are exact" {
    const a = std.testing.allocator;
    var evidence = try Store.init(a);
    defer evidence.deinit();
    const first = try evidence.intern(.record, 0, 0, &.{ 10, types.u32_type, 2, types.f32_type });
    const reordered = try evidence.intern(.record, 0, 0, &.{ 2, types.f32_type, 10, types.u32_type });
    try std.testing.expectEqual(first, reordered);
    try std.testing.expectEqualSlices(Id, &.{ 2, types.f32_type, 10, types.u32_type }, evidence.children(first));
    try std.testing.expectError(error.TypeMismatch, evidence.intern(.record, 0, 0, &.{ 1, types.u32_type, 1, types.f32_type }));
    const left = try evidence.internHashed(.nominal, 1, 20, &.{types.u32_type}, 0);
    const right = try evidence.internHashed(.nominal, 1, 20, &.{types.f32_type}, 0);
    try std.testing.expect(left != right);
    try std.testing.expectEqual(left, try evidence.internHashed(.nominal, 1, 20, &.{types.u32_type}, 0));
    // Both empty products and empty records are valid but distinct semantic types.
    try std.testing.expect(try evidence.intern(.product, 0, 0, &.{}) != try evidence.intern(.record, 0, 0, &.{}));
}
test "evidence IDs and owned snapshots survive growth and producer teardown" {
    const a = std.testing.allocator;
    var snapshot: Snapshot = undefined;
    var integer: Id = 0;
    {
        var evidence = try Store.init(a);
        defer evidence.deinit();
        integer = try evidence.intern(.nominal, 1, 7, &.{types.u32_type});
        for (0..512) |i| _ = try evidence.intern(.nominal, 1, @intCast(100 + i), &.{types.f32_type});
        // Borrowed children may alias the growing side table; intern copies
        // before reserving any buffer, preserving published spans.
        const borrowed = evidence.children(integer);
        _ = try evidence.intern(.product, 0, 0, borrowed);
        try std.testing.expectEqualSlices(Id, &.{types.u32_type}, evidence.children(integer));
        snapshot = try evidence.copyOwned(a);
    }
    defer snapshot.deinit(a);
    try std.testing.expectEqual(Tag.nominal, snapshot.view().node(integer).tag);
    try std.testing.expectEqualSlices(Id, &.{types.u32_type}, snapshot.view().children(integer));
}
fn allocationScenario(allocator: Allocator) !void {
    var source = try types.Store.init(allocator);
    defer source.deinit();
    const variable = try source.fresh();
    const record_ = try source.record(&.{ .{ .name = 2, .ty = variable }, .{ .name = 1, .ty = types.boolean } });
    const nominal = try source.nominal(.{ .unit = 2, .decl = 7 }, &.{try source.array(record_)});
    const function = try source.function(nominal, nominal);
    var evidence = try Store.init(allocator);
    defer evidence.deinit();
    const concrete = try evidence.project(&source, function, &.{.{ .variable = variable, .evidence = types.f32_type }});
    var mappings: std.ArrayList(Mapping) = .empty;
    defer mappings.deinit(allocator);
    try std.testing.expect(try evidence.match(&source, function, concrete, &mappings));
    var snapshot = try evidence.copyOwned(allocator);
    defer snapshot.deinit(allocator);
    try std.testing.expectEqual(Tag.function, snapshot.view().node(concrete).tag);
}
test "every evidence and snapshot allocation failure releases all owned buffers" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}

test "demand evidence retains parameter mode through projection matching and owned publication" {
    const allocator = std.testing.allocator;
    var source = try types.Store.init(allocator);
    defer source.deinit();
    const variable = try source.fresh();
    const demanded = try source.function(try source.demand(variable), variable);
    const ordinary = try source.function(variable, variable);
    var evidence = try Store.init(allocator);
    defer evidence.deinit();
    const demand_u32 = try evidence.intern(.demand, types.u32_type, 0, &.{});
    const lazy_u32 = try evidence.intern(.function, demand_u32, types.u32_type, &.{});
    const eager_u32 = try evidence.intern(.function, types.u32_type, types.u32_type, &.{});
    try std.testing.expect(lazy_u32 != eager_u32);
    var mappings: std.ArrayList(Mapping) = .empty;
    defer mappings.deinit(allocator);
    try std.testing.expect(try evidence.match(&source, demanded, lazy_u32, &mappings));
    try std.testing.expectEqual(@as(usize, 1), mappings.items.len);
    try std.testing.expectEqual(lazy_u32, try evidence.project(&source, demanded, mappings.items));
    try std.testing.expect(!try evidence.match(&source, ordinary, lazy_u32, &mappings));
    try std.testing.expectEqual(@as(usize, 1), mappings.items.len);
    var snapshot = try evidence.copyOwned(allocator);
    defer snapshot.deinit(allocator);
    try std.testing.expectEqual(Tag.demand, snapshot.view().node(snapshot.view().node(lazy_u32).a).tag);
}

test "resolver evidence retains exact nominal owner tokens through generic aliases and publication" {
    const allocator = std.testing.allocator;
    var source = try types.Store.init(allocator);
    defer source.deinit();
    const generic = try source.fresh();
    const factory = try source.function(generic, try source.resolver(generic));
    const first = try source.typeConstructor(.{ .unit = 1, .decl = 42 });
    const foreign = try source.typeConstructor(.{ .unit = 2, .decl = 42 });
    var evidence = try Store.init(allocator);
    defer evidence.deinit();
    const token = try evidence.project(&source, first, &.{});
    const other = try evidence.project(&source, foreign, &.{});
    try std.testing.expect(token != other);
    const resolver = try evidence.intern(.resolver, token, 0, &.{});
    const instance = try evidence.intern(.function, token, resolver, &.{});
    var mappings: std.ArrayList(Mapping) = .empty;
    defer mappings.deinit(allocator);
    try std.testing.expect(try evidence.match(&source, factory, instance, &mappings));
    try std.testing.expectEqual(instance, try evidence.project(&source, factory, mappings.items));
    const wrong = try evidence.intern(.function, other, resolver, &.{});
    try std.testing.expect(!try evidence.match(&source, factory, wrong, &mappings));
    try std.testing.expectEqual(@as(usize, 1), mappings.items.len);
    var snapshot = try evidence.copyOwned(allocator);
    defer snapshot.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 1), snapshot.view().node(snapshot.view().node(resolver).a).a);
    try std.testing.expectEqual(@as(u32, 42), snapshot.view().node(snapshot.view().node(resolver).a).b);
}

fn effectOwnershipScenario(allocator: Allocator) !void {
    var snapshot: ?Snapshot = null;
    defer if (snapshot) |*owned| owned.deinit(allocator);
    var concrete: Id = 0;
    {
        var source = try types.Store.init(allocator);
        defer source.deinit();
        const integer = try source.nominal(.{ .unit = 7, .decl = 4 }, &.{types.u32_type});
        const floating = try source.nominal(.{ .unit = 7, .decl = 4 }, &.{types.f32_type});
        const read_integer = try source.internOperation(.{ .unit = 8, .decl = 10 }, &.{integer});
        const read_float = try source.internOperation(.{ .unit = 8, .decl = 10 }, &.{floating});
        const row = try source.effects.row(&.{ read_float, read_integer, read_integer }, .closed);
        const demanded = try source.demandWithEffects(types.u32_type, row);
        const function = try source.functionWithEffects(demanded, types.u32_type, row);
        var evidence = try Store.init(allocator);
        defer evidence.deinit();
        // Different parent IDs must be remapped, even when the same raw numbers
        // happen to denote unrelated nodes in the two owners.
        _ = try evidence.intern(.product, 0, 0, &.{types.boolean});
        concrete = try evidence.project(&source, function, &.{});
        const published = evidence.node(concrete);
        try std.testing.expectEqual(published.c, evidence.node(published.a).c);
        try std.testing.expectEqual(@as(usize, 3), evidence.effects.view().rowLabels(published.c).len);
        const pure = try evidence.intern(.function, published.a, published.b, &.{});
        try std.testing.expect(pure != concrete);
        var mappings: std.ArrayList(Mapping) = .empty;
        defer mappings.deinit(allocator);
        try std.testing.expect(try evidence.match(&source, function, concrete, &mappings));
        try std.testing.expect(!try evidence.match(&source, function, pure, &mappings));
        const open = try source.functionWithEffects(types.unit, types.u32_type, try source.freshEffects());
        try std.testing.expectError(error.UnresolvedType, evidence.project(&source, open, &.{}));
        snapshot = try evidence.copyOwned(allocator);
    }
    const view = snapshot.?.view();
    const labels = view.effects.rowLabels(view.node(concrete).c);
    const first_arguments = view.effects.operationArguments(labels[0]);
    try std.testing.expectEqual(@as(u32, 7), view.node(first_arguments[0]).a);
    try std.testing.expectEqual(@as(u32, 4), view.node(first_arguments[0]).b);
    try std.testing.expectEqual(@as(usize, 1), view.children(first_arguments[0]).len);
}
test "effect evidence survives owner teardown with exact latent rows and operation argument types" {
    try effectOwnershipScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, effectOwnershipScenario, .{});
}

fn rowSubstitutionScenario(allocator: Allocator) !void {
    var source = try types.Store.init(allocator);
    defer source.deinit();
    const variable = try source.fresh();
    const tail = try source.freshEffects();
    const callback = try source.functionWithEffects(types.u32_type, variable, tail);
    const pattern = try source.functionWithEffects(callback, variable, tail);
    var evidence = try Store.init(allocator);
    defer evidence.deinit();
    const foreign = try evidence.effects.internOperation(.{ .unit = 0, .decl = 1 }, &.{});
    const foreign_row = try evidence.effects.internRow(&.{foreign});
    const concrete_callback = try evidence.internWithEffects(.function, types.u32_type, types.f32_type, foreign_row, &.{});
    const actual = try evidence.internWithEffects(.function, concrete_callback, types.f32_type, foreign_row, &.{});
    const rejected = try evidence.intern(.function, concrete_callback, types.f32_type, &.{});
    var mappings: std.ArrayList(Mapping) = .empty;
    defer mappings.deinit(allocator);
    var rows: std.ArrayList(RowMapping) = .empty;
    defer rows.deinit(allocator);
    try std.testing.expect(!try evidence.matchWithRows(&source, pattern, rejected, &mappings, &rows));
    try std.testing.expectEqual(@as(usize, 0), mappings.items.len);
    try std.testing.expectEqual(@as(usize, 0), rows.items.len);
    try std.testing.expect(try evidence.matchWithRows(&source, pattern, actual, &mappings, &rows));
    try std.testing.expectEqual(types.f32_type, mappings.items[0].evidence);
    try std.testing.expectEqual(foreign_row, rows.items[0].evidence);
    try std.testing.expectEqual(source.node(variable).a, rows.items[0].variable);
    try std.testing.expectEqual(actual, try evidence.projectWithRows(&source, pattern, mappings.items, rows.items));
    try std.testing.expect(!try evidence.matchWithRows(&source, pattern, rejected, &mappings, &rows));
    try std.testing.expectEqual(@as(usize, 1), mappings.items.len);
    try std.testing.expectEqual(@as(usize, 1), rows.items.len);
    const state = try source.internOperation(.{ .unit = 9, .decl = 4 }, &.{types.u32_type});
    const prefixed = try source.effects.row(&.{ state, types.foreign_operation }, source.row(tail).tail);
    const open = try source.functionWithEffects(types.unit, types.u32_type, prefixed);
    const closed = try source.effects.row(&.{ types.foreign_operation, state, state, types.foreign_operation }, .closed);
    const closed_function = try source.functionWithEffects(types.unit, types.u32_type, closed);
    const supplied = try evidence.project(&source, closed_function, &.{});
    mappings.clearRetainingCapacity();
    rows.clearRetainingCapacity();
    try std.testing.expect(try evidence.matchWithRows(&source, open, supplied, &mappings, &rows));
    try std.testing.expectEqual(@as(usize, 2), evidence.effects.view().rowLabels(rows.items[0].evidence).len);
    try std.testing.expectEqual(supplied, try evidence.projectWithRows(&source, open, mappings.items, rows.items));
}
test "type and row substitutions have separate namespaces and transactional matching" {
    try rowSubstitutionScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, rowSubstitutionScenario, .{});
}
