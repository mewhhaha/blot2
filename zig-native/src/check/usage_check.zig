//! Affine moves are checked against resolved binding versions, never spelling.
//! This pass runs only for feature-bearing modules. Its state is private until
//! all exits and captures have been checked; ordinary modules allocate nothing.
const std = @import("std");
const ast = @import("../parse/ast.zig");
const T = @import("types.zig");
const State = struct { binding: u32, first: ast.Id = 0, loan: ast.Id = 0 };
const Outcome = enum { live, exit };
const ExitFrame = struct { joined: []State, seen: bool = false };

pub fn affine(store: anytype, root: T.Id) T.Error!bool {
    return inspect(store, root, .affine);
}
pub fn borrowed(store: anytype, root: T.Id) T.Error!bool {
    return inspect(store, root, .borrow);
}
pub fn contains(store: anytype, root: T.Id) T.Error!bool {
    return inspect(store, root, .any);
}
pub const Work = struct {
    remaining: usize = 65_536,
    pub fn charge(self: *Work, amount: usize) T.Error!void {
        if (amount > self.remaining) return error.TypeLimit;
        self.remaining -= amount;
    }
};
/// Completed negative results belong to one query with a fixed nominal catalog.
/// Solver writes invalidate them; no memo is retained in checked artifacts.
pub const Memo = struct {
    allocator: std.mem.Allocator,
    safe: std.AutoHashMapUnmanaged(T.Id, void) = .empty,
    epoch: ?u64 = null,
    row_epoch: ?u64 = null,
    nominals: std.ArrayList(struct { identity: T.NominalIdentity, has_usage: bool }) = .empty,
    pub fn deinit(self: *Memo) void {
        self.safe.deinit(self.allocator);
        self.nominals.deinit(self.allocator);
    }
};
pub fn containsNominalMemoWork(store: *const T.Store, nominals: anytype, root: T.Id, work: *Work, memo: *Memo) T.Error!bool {
    const epoch = store.mutation_epoch;
    var same_catalog = memo.nominals.items.len == nominals.len;
    if (same_catalog) for (memo.nominals.items, nominals) |prior, nominal| {
        try work.charge(1);
        if (!std.meta.eql(prior.identity, nominal.identity) or prior.has_usage != nominal.has_usage) {
            same_catalog = false;
            break;
        }
    };
    if (memo.epoch != epoch or memo.row_epoch != store.effects.mutation_epoch or !same_catalog or epoch == std.math.maxInt(u64)) memo.safe.clearRetainingCapacity();
    memo.epoch = epoch;
    memo.row_epoch = store.effects.mutation_epoch;
    if (!same_catalog) {
        memo.nominals.clearRetainingCapacity();
        for (nominals) |nominal| {
            try work.charge(1);
            try memo.nominals.append(memo.allocator, .{ .identity = nominal.identity, .has_usage = nominal.has_usage });
        }
    }
    const context: NominalStore(@TypeOf(store), @TypeOf(nominals)) = .{ .store = store, .nominals = nominals, .work = work };
    if (epoch == std.math.maxInt(u64) or store.effects.mutation_epoch == std.math.maxInt(u64)) return inspectWithWork(&context, root, .any, work);
    return inspectWithMemo(&context, root, .any, work, memo);
}
fn NominalStore(comptime Store: type, comptime Nominals: type) type {
    return struct {
        store: Store,
        nominals: Nominals,
        work: *Work,
        pub fn head(self: *const @This(), id: T.Id, cursor: T.Cursor) T.Id {
            return self.store.head(id, cursor);
        }
        pub fn node(self: *const @This(), id: T.Id) T.Node {
            return self.store.node(id);
        }
        pub fn list(self: *const @This(), values: T.List) []const T.Id {
            return self.store.list(values);
        }
        pub fn recordField(self: *const @This(), value: T.Node, index: usize) T.Field {
            return self.store.recordField(value, index);
        }
        pub fn nominalArguments(self: *const @This(), value: T.Node) []const T.Id {
            return self.store.nominalArguments(value);
        }
        pub fn valid(self: *const @This(), id: T.Id) bool {
            const nodes = self.store.nodes;
            if (comptime @hasField(@TypeOf(nodes), "items")) return id < nodes.items.len;
            return id < nodes.len;
        }
        pub fn shape(self: *const @This(), value: T.Node) T.Error!void {
            const storage = self.store.extra;
            const values = if (comptime @hasField(@TypeOf(storage), "items")) storage.items else storage;
            switch (value.tag) {
                .usage, .array, .list, .cursor, .demand, .forall, .existential, .resolver, .provider, .scoped => if (!self.valid(value.a)) return error.TypeLimit,
                .function => if (!self.valid(value.a) or !self.valid(value.b)) return error.TypeLimit,
                else => {},
            }
            switch (value.tag) {
                .product => if (value.a > values.len or value.b > values.len - value.a) return error.TypeLimit,
                .record => if (value.a > values.len or value.b > (values.len - value.a) / 2) return error.TypeLimit,
                .nominal, .projection => if (value.c >= values.len or values[value.c] > values.len - value.c - 1) return error.TypeLimit,
                .usage => if (value.b > @backingInt(T.UsageKind.concurrent)) return error.TypeLimit,
                else => {},
            }
            if (value.tag == .projection and values[value.c] >= values.len - value.c - 1) return error.TypeLimit;
            var first: usize = value.a;
            var count: usize = 0;
            var stride: usize = 1;
            switch (value.tag) {
                .product => count = value.b,
                .record => {
                    count = value.b;
                    first += 1;
                    stride = 2;
                },
                .nominal, .projection => {
                    count = values[value.c];
                    first = value.c + 1;
                },
                else => {},
            }
            for (0..count) |index| {
                try self.work.charge(1);
                if (!self.valid(values[first + index * stride])) return error.TypeLimit;
            }
        }
        pub fn nominalProperty(self: *const @This(), value: T.Node, comptime mode: Mode) T.Error!bool {
            for (self.nominals) |nominal| {
                try self.work.charge(1);
                if (nominal.identity.unit == value.a and nominal.identity.decl == value.b) {
                    if (mode == .any) return nominal.has_usage;
                    return nominal.affine;
                }
            }
            return false;
        }
    };
}
pub fn nominalShape(store: anytype, nominals: anytype, node: T.Node, work: *Work) T.Error!void {
    const context: NominalStore(@TypeOf(store), @TypeOf(nominals)) = .{ .store = store, .nominals = nominals, .work = work };
    try work.charge(1);
    try context.shape(node);
}
pub fn affineNominal(store: anytype, nominals: anytype, root: T.Id) T.Error!bool {
    var work: Work = .{};
    return affineNominalWork(store, nominals, root, &work);
}
pub fn affineNominalWork(store: anytype, nominals: anytype, root: T.Id, work: *Work) T.Error!bool {
    const context: NominalStore(@TypeOf(store), @TypeOf(nominals)) = .{ .store = store, .nominals = nominals, .work = work };
    return inspectWithWork(&context, root, .affine, work);
}
pub fn containsNominal(store: anytype, nominals: anytype, root: T.Id) T.Error!bool {
    var work: Work = .{};
    return containsNominalWork(store, nominals, root, &work);
}
pub fn containsNominalWork(store: anytype, nominals: anytype, root: T.Id, work: *Work) T.Error!bool {
    const context: NominalStore(@TypeOf(store), @TypeOf(nominals)) = .{ .store = store, .nominals = nominals, .work = work };
    return inspectWithWork(&context, root, .any, work);
}
const Mode = enum { affine, any, borrow };
fn inspect(store: anytype, root: T.Id, comptime mode: Mode) T.Error!bool {
    var work: Work = .{};
    return inspectWithWork(store, root, mode, &work);
}
fn inspectWithWork(store: anytype, root: T.Id, comptime mode: Mode, work: *Work) T.Error!bool {
    return inspectWithMemo(store, root, mode, work, null);
}
fn inspectWithMemo(store: anytype, root: T.Id, comptime mode: Mode, work: *Work, memo: ?*Memo) T.Error!bool {
    const Pending = struct {
        ids: [4096]T.Id = undefined,
        slots: [8192]u16 = @splat(0),
        count: usize = 0,
        fn add(self: *@This(), source: anytype, raw: T.Id, budget: *Work, known: ?*Memo) T.Error!void {
            if (comptime @hasDecl(@TypeOf(source.*), "valid")) {
                if (!source.valid(raw)) return error.TypeLimit;
            }
            const id = source.head(raw, 0);
            if (comptime @hasDecl(@TypeOf(source.*), "valid")) {
                if (!source.valid(id)) return error.TypeLimit;
            }
            if (known) |cache| {
                try budget.charge(1);
                if (cache.safe.contains(id)) return;
            }
            var slot: usize = (@as(usize, id) *% 0x9e3779b1) & (self.slots.len - 1);
            while (true) {
                try budget.charge(1);
                const prior = self.slots[slot];
                if (prior == 0) break;
                if (self.ids[prior - 1] == id) return;
                slot = (slot + 1) & (self.slots.len - 1);
            }
            if (self.count == self.ids.len) return error.TypeLimit;
            self.ids[self.count] = id;
            self.count += 1;
            self.slots[slot] = @intCast(self.count);
        }
    };
    var pending: Pending = .{};
    try pending.add(store, root, work, memo);
    var next: usize = 0;
    while (next != pending.count) : (next += 1) {
        try work.charge(1);
        const id = pending.ids[next];
        const node = store.node(id);
        if (comptime @hasDecl(@TypeOf(store.*), "shape")) try store.shape(node);
        if (comptime @hasDecl(@TypeOf(store.*), "nominalProperty")) {
            if (mode != .borrow and node.tag == .nominal and try store.nominalProperty(node, mode)) return true;
        }
        // Lexical scope/version evidence is authority, not a data witness.
        if (mode == .any and (node.tag == .scoped or node.tag == .instance_version)) return true;
        if (node.tag == .usage) {
            if (mode == .any) return true;
            const kind: T.UsageKind = @fromBackingInt(@intCast(node.b));
            if (mode == .borrow) {
                if (kind == .borrow or kind == .borrow_mut) return true;
            } else if (kind == .unique or kind == .borrow_mut or kind == .once) return true;
            // Shared ownership must not hide an affine obligation. Construction
            // separately checks it, and the walker preserves it conservatively.
        }
        var children: [1]T.Id = .{node.a};
        const edges: []const T.Id = switch (node.tag) {
            .usage, .array, .list, .cursor, .demand, .forall, .existential => &children,
            .product => store.list(.{ .start = node.a, .len = node.b }),
            .nominal, .projection => store.nominalArguments(node),
            .function => blk: {
                if (mode == .any) {
                    try pending.add(store, node.a, work, memo);
                    try pending.add(store, node.b, work, memo);
                }
                break :blk &.{};
            },
            .record => blk: {
                for (0..node.b) |index| {
                    try work.charge(1);
                    try pending.add(store, store.recordField(node, index).ty, work, memo);
                }
                break :blk &.{};
            },
            else => &.{},
        };
        try work.charge(edges.len);
        for (edges) |edge| try pending.add(store, edge, work, memo);
    }
    if (memo) |cache| for (pending.ids[0..pending.count]) |id| {
        try work.charge(1);
        try cache.safe.put(cache.allocator, id, {});
    };
    return false;
}
fn Walker(comptime Engine: type) type {
    return struct {
        const Self = @This();
        engine: Engine,
        task_views: bool = false,
        states: std.ArrayList(State) = .empty,
        remaining: usize = 65_536,
        regions: [128]T.Id = undefined,
        region_count: usize = 0,
        returns: ?*ExitFrame = null,
        breaks: ?*ExitFrame = null,
        fn record(self: *Self, frame: *ExitFrame) void {
            frame.seen = true;
            for (frame.joined, self.states.items[0..frame.joined.len]) |*entry, after| if (entry.first == 0) {
                entry.first = after.first;
            };
        }
        fn suite(self: *Self, source: ast.Id, depth: usize) T.Error!Outcome {
            if (source == 0) return .live;
            try self.charge(depth);
            for (self.engine.tree.children(source)) |child| if (try self.expression(child, depth + 1) == .exit) return .exit;
            return .live;
        }
        fn block(self: *Self, source: ast.Id, depth: usize) T.Error!Outcome {
            const joined = try self.snapshot();
            defer self.engine.allocator.free(joined);
            var frame: ExitFrame = .{ .joined = joined };
            const outer = self.returns;
            self.returns = &frame;
            defer self.returns = outer;
            const flow = try self.suite(source, depth + 1);
            self.states.shrinkRetainingCapacity(joined.len);
            if (frame.seen) {
                if (flow == .exit) {
                    @memcpy(self.states.items, joined);
                } else {
                    for (self.states.items, joined) |*entry, after| if (entry.first == 0) {
                        entry.first = after.first;
                    };
                }
                return .live;
            }
            return flow;
        }
        fn integer(self: *Self, source: ast.Id) ?u32 {
            if (source == 0) return null;
            var id = source;
            var depth: usize = 0;
            while (self.engine.tree.node(id).tag == .group) : (depth += 1) {
                if (depth == 128) return null;
                id = self.engine.tree.node(id).a;
            }
            const node = self.engine.tree.node(id);
            if (node.tag != .integer) return null;
            return node.a;
        }
        fn singleIteration(self: *Self, first: ast.Id, end: ast.Id) bool {
            const low = self.integer(first) orelse return false;
            const high = self.integer(end) orelse return false;
            return low < high and high - low == 1;
        }
        fn charge(self: *Self, depth: usize) T.Error!void {
            if (depth >= 128 or self.remaining == 0) return error.TypeLimit;
            self.remaining -= 1;
        }
        fn snapshot(self: *Self) T.Error![]State {
            if (self.states.items.len > self.remaining) return error.TypeLimit;
            self.remaining -= self.states.items.len;
            return self.engine.allocator.dupe(State, self.states.items);
        }
        fn state(self: *Self, binding: u32) ?*State {
            for (self.states.items) |*entry| if (entry.binding == binding) return entry;
            return null;
        }
        fn introduce(self: *Self, binding: u32) T.Error!void {
            if (binding == 0 or self.state(binding) != null) return;
            if (!try affineNominal(&self.engine.types, self.engine.nominals.items, self.engine.bindings.items[binding].ty)) return;
            if (self.states.items.len == 4096) return error.TypeLimit;
            try self.states.append(self.engine.allocator, .{ .binding = binding });
        }
        fn use(self: *Self, binding: u32, source: ast.Id) T.Error!void {
            if (binding == 0 or !try affineNominal(&self.engine.types, self.engine.nominals.items, self.engine.bindings.items[binding].ty)) return;
            if (self.state(binding)) |entry| {
                if (entry.loan != 0) {
                    try self.engine.usageConflict(.borrow_conflict, source, entry.loan, self.engine.bindings.items[binding].declaration);
                    return;
                }
                if (entry.first != 0) {
                    var code: @TypeOf(self.engine.diagnostics.items[0].code) = .use_after_move;
                    const ty = self.engine.types.node(self.engine.types.head(self.engine.bindings.items[binding].ty, 0));
                    if (ty.tag == .usage and ty.b == @backingInt(T.UsageKind.once)) code = .once_reused;
                    if (@import("task_types.zig").isHandle(&self.engine.types, self.engine.bindings.items[binding].ty)) code = .task_handle_consumed;
                    try self.engine.usageConflict(code, source, entry.first, self.engine.bindings.items[binding].declaration);
                    return;
                }
                entry.first = source;
            } else try self.engine.usageDiagnostic(.duplicate_owner, source);
        }
        fn pattern(self: *Self, source: ast.Id, depth: usize) T.Error!void {
            try self.charge(depth);
            const node = self.engine.tree.node(source);

            if (node.tag == .pattern_name) return self.introduce(self.engine.resolved[source]);
            if (node.tag == .pattern_constructor or node.tag == .pattern_field) {
                if (node.b != 0) try self.pattern(node.b, depth + 1) else if (node.tag == .pattern_field) try self.introduce(self.engine.resolved[source]);
            } else if (node.tag == .pattern_product or node.tag == .pattern_record) {
                for (self.engine.tree.children(source)) |child| try self.pattern(child, depth + 1);
            }
        }
        fn captures(self: *Self, source: ast.Id, owner: ast.Id, once: bool, found: *std.ArrayList(u32), depth: usize) T.Error!void {
            try self.charge(depth);
            const node = self.engine.tree.node(source);
            if (node.tag == .name) {
                const binding = self.engine.resolved[source];
                if (binding == 0 or self.engine.bindings.items[binding].owner == owner or self.state(binding) == null) return;
                for (found.items) |prior| if (prior == binding) return;
                try found.append(self.engine.allocator, binding);
                if (!once) try self.engine.usageDiagnostic(.duplicate_owner, source) else try self.use(binding, source);
                return;
            }
            // Capture discovery visits syntax without executing it. Only live
            // outer owners matter, so nested lexical parameters cannot alias it.
            switch (node.tag) {
                .lambda => try self.captures(node.b, owner, once, found, depth + 1),
                .group, .field_access, .return_stmt, .function_return_stmt, .yield_stmt, .type_witness => try self.captures(node.a, owner, once, found, depth + 1),
                .field, .unary, .operator_tail => if (node.b != 0) {
                    try self.captures(node.b, owner, once, found, depth + 1);
                },
                .apply, .index_access, .rebind_stmt => {
                    try self.captures(node.a, owner, once, found, depth + 1);
                    try self.captures(node.b, owner, once, found, depth + 1);
                },
                .binary => {
                    try self.captures(node.b, owner, once, found, depth + 1);
                    try self.captures(node.c, owner, once, found, depth + 1);
                },
                .if_expr, .if_stmt => {
                    try self.captures(node.a, owner, once, found, depth + 1);
                    try self.captures(node.b, owner, once, found, depth + 1);
                    if (node.c != 0) try self.captures(node.c, owner, once, found, depth + 1);
                },
                .product, .record, .array, .block => for (self.engine.tree.children(source)) |child| {
                    try self.captures(child, owner, once, found, depth + 1);
                },
                .let_stmt => {
                    const binding = self.engine.tree.binding(source);
                    try self.captures(binding.value, owner, once, found, depth + 1);
                    if (binding.fallback != 0) try self.captures(binding.fallback, owner, once, found, depth + 1);
                },
                .use_stmt, .iterator_bind => try self.captures(node.b, owner, once, found, depth + 1),
                .infix_chain => {
                    try self.captures(node.a, owner, once, found, depth + 1);
                    for (self.engine.tree.list(.{ .start = node.b, .len = node.c })) |tail| try self.captures(tail, owner, once, found, depth + 1);
                },
                .case_expr => {
                    const inputs = self.engine.tree.extra.items[node.a..][0..2];
                    for (self.engine.tree.list(.{ .start = inputs[0], .len = inputs[1] })) |input| try self.captures(input, owner, once, found, depth + 1);
                    for (self.engine.tree.list(.{ .start = node.b, .len = node.c })) |arm| {
                        const details = self.engine.tree.extra.items[self.engine.tree.node(arm).c..][0..2];
                        if (details[0] != 0) try self.captures(details[0], owner, once, found, depth + 1);
                        try self.captures(details[1], owner, once, found, depth + 1);
                    }
                },
                .if_let_stmt => {
                    try self.captures(node.b, owner, once, found, depth + 1);
                    const bodies = self.engine.tree.extra.items[node.c..][0..2];
                    for (bodies) |body| if (body != 0) {
                        try self.captures(body, owner, once, found, depth + 1);
                    };
                },
                .for_stmt => {
                    try self.captures(node.b, owner, once, found, depth + 1);
                    const end = self.engine.tree.extra.items[node.c];
                    if (end != 0) try self.captures(end, owner, once, found, depth + 1);
                    try self.captures(self.engine.tree.extra.items[node.c + 1], owner, once, found, depth + 1);
                },
                .range_stmt => {
                    try self.captures(node.a, owner, once, found, depth + 1);
                    try self.captures(node.b, owner, once, found, depth + 1);
                    try self.captures(node.c, owner, once, found, depth + 1);
                },
                .forever_stmt => try self.captures(node.a, owner, once, found, depth + 1),
                .package_pack => try self.captures(self.engine.tree.extra.items[node.c], owner, once, found, depth + 1),
                .package_unpack => {
                    try self.captures(node.a, owner, once, found, depth + 1);
                    try self.captures(self.engine.tree.extra.items[node.c + 2], owner, once, found, depth + 1);
                },
                else => {},
            }
        }
        fn lambda(self: *Self, source: ast.Id, depth: usize) T.Error!void {
            const node = self.engine.tree.node(source);
            const ty = self.engine.types.node(self.engine.types.head(self.engine.expr_types[source], 0));
            if (ty.tag == .usage and ty.b == @backingInt(T.UsageKind.cleanup)) {
                if (!@import("cleanup_contracts.zig").source(self.engine, source)) try self.engine.usageDiagnostic(.cleanup_not_safe, source);
            }
            // Pure incoming arrows have no caller-owned finite executable
            // receipt here. Their spelling cannot license unknown adapters.
            if (@import("cleanup_contracts.zig").pureNominal(&self.engine.types, self.engine.nominals.items, self.engine.expr_types[node.a])) try self.engine.usageDiagnostic(.cleanup_not_safe, node.a);
            const once = ty.tag == .usage and ty.b == @backingInt(T.UsageKind.once);
            var captured: std.ArrayList(u32) = .empty;
            defer captured.deinit(self.engine.allocator);
            try self.captures(node.b, source, once, &captured, depth + 1);
            const previous = try self.snapshot();
            defer self.engine.allocator.free(previous);
            defer {
                self.states.shrinkRetainingCapacity(previous.len);
                @memcpy(self.states.items, previous);
            }
            // A moved capture has a new owning path inside the closure body.
            for (captured.items) |binding| if (self.state(binding)) |entry| {
                entry.first = 0;
            };
            const outer_returns = self.returns;
            const outer_breaks = self.breaks;
            self.returns = null;
            self.breaks = null;
            defer {
                self.returns = outer_returns;
                self.breaks = outer_breaks;
            }
            try self.introduce(self.engine.resolved[node.a]);
            _ = try self.expression(node.b, depth + 1);
        }
        fn branches(self: *Self, left: ast.Id, right: ast.Id, suites: bool, depth: usize) T.Error!Outcome {
            const prior = try self.snapshot();
            defer self.engine.allocator.free(prior);
            var left_flow: Outcome = .live;
            if (suites) left_flow = try self.suite(left, depth + 1) else left_flow = try self.expression(left, depth + 1);
            self.states.shrinkRetainingCapacity(prior.len);
            const after = try self.snapshot();
            defer self.engine.allocator.free(after);
            @memcpy(self.states.items, prior);
            var right_flow: Outcome = .live;
            if (right != 0) {
                if (suites) right_flow = try self.suite(right, depth + 1) else right_flow = try self.expression(right, depth + 1);
            }
            self.states.shrinkRetainingCapacity(prior.len);
            for (self.states.items, after) |*entry, first| {
                if (right_flow == .exit) entry.* = first else if (left_flow != .exit and entry.first == 0) entry.first = first.first;
            }
            if (left_flow == .exit and right_flow == .exit) return .exit;
            return .live;
        }
        fn cases(self: *Self, node: ast.Node, depth: usize) T.Error!Outcome {
            const inputs = self.engine.tree.extra.items[node.a..][0..2];
            for (self.engine.tree.list(.{ .start = inputs[0], .len = inputs[1] })) |input| if (try self.expression(input, depth + 1) == .exit) return .exit;
            const before = try self.snapshot();
            defer self.engine.allocator.free(before);
            const joined = try self.snapshot();
            defer self.engine.allocator.free(joined);
            var live = false;
            for (self.engine.tree.list(.{ .start = node.b, .len = node.c })) |arm_id| {
                @memcpy(self.states.items, before);
                const arm = self.engine.tree.node(arm_id);
                for (self.engine.tree.list(.{ .start = arm.a, .len = arm.b })) |row| for (self.engine.tree.children(row)) |pattern_| try self.pattern(pattern_, depth + 1);
                const details = self.engine.tree.extra.items[arm.c..][0..2];
                if (details[0] != 0) {
                    if (try self.expression(details[0], depth + 1) == .exit) {
                        self.states.shrinkRetainingCapacity(before.len);
                        continue;
                    }
                    // A failed guard continues to the next arm. Its owner
                    // moves survive even when this arm's body never runs.
                    for (before, self.states.items[0..before.len]) |*entry, after| if (entry.first == 0) {
                        entry.first = after.first;
                    };
                    // Pattern payloads must remain available on fallthrough;
                    // an owning use in a guard would duplicate the scrutinee.
                    for (self.states.items[before.len..]) |entry| if (entry.first != 0) {
                        try self.engine.usageDiagnostic(.duplicate_owner, details[0]);
                    };
                }
                const flow = try self.expression(details[1], depth + 1);
                self.states.shrinkRetainingCapacity(before.len);
                if (flow == .live) {
                    live = true;
                    for (joined, self.states.items) |*entry, after| if (entry.first == 0) {
                        entry.first = after.first;
                    };
                }
            }
            @memcpy(self.states.items, joined);
            if (!live) return .exit;
            return .live;
        }
        fn admitsAffine(self: *Self, callee_source: ast.Id) T.Error!bool {
            var task_head = callee_source;
            for (0..128) |_| {
                const candidate = self.engine.tree.node(task_head);
                if (candidate.tag == .apply or candidate.tag == .group) {
                    task_head = candidate.a;
                    continue;
                }
                if (candidate.tag == .intrinsic and @import("task_types.zig").lookup(self.engine.pool.get(candidate.a)) != null) return true;
                break;
            }
            var source = callee_source;
            while (self.engine.tree.node(source).tag == .group) source = self.engine.tree.node(source).a;
            const node = self.engine.tree.node(source);
            if (node.tag == .lambda or node.tag == .constructor_ref) return true;
            const binding = self.engine.resolved[source];
            if (binding == 0) return false;
            const declaration = self.engine.bindings.items[binding];
            if (declaration.kind == .parameter) {
                const parameter = self.engine.tree.parameter(declaration.declaration);
                var annotation = parameter.annotation;
                if (annotation == 0) return false;
                while (self.engine.tree.node(annotation).tag == .group or self.engine.tree.node(annotation).tag == .type_usage or self.engine.tree.node(annotation).tag == .type_forall) {
                    const wrapper = self.engine.tree.node(annotation);
                    if (wrapper.tag == .group) {
                        annotation = wrapper.a;
                    } else if (wrapper.tag == .type_forall) {
                        annotation = self.engine.tree.extra.items[wrapper.c];
                    } else annotation = wrapper.b;
                }
                const arrow = self.engine.tree.node(annotation);
                if (arrow.tag != .type_function) return false;
                var input = arrow.a;
                while (self.engine.tree.node(input).tag == .group) input = self.engine.tree.node(input).a;
                return self.engine.tree.node(input).tag == .type_usage;
            }
            var header = self.engine.types.node(self.engine.types.head(declaration.ty, 0));
            while (header.tag == .usage or header.tag == .forall) header = self.engine.types.node(self.engine.types.head(header.a, 0));
            return header.tag == .function and (self.engine.types.node(header.a).tag == .usage or try affineNominal(&self.engine.types, self.engine.nominals.items, header.a));
        }
        fn expression(self: *Self, source: ast.Id, depth: usize) T.Error!Outcome {
            if (source == 0) return .live;
            try self.charge(depth);
            const node = self.engine.tree.node(source);
            if (self.task_views and node.tag == .apply) {
                var head = source;
                var arguments: [3]ast.Id = undefined;
                var count: usize = 0;
                while (self.engine.tree.node(head).tag == .apply and count < arguments.len) {
                    arguments[count] = self.engine.tree.node(head).b;
                    count += 1;
                    head = self.engine.tree.node(head).a;
                }
                if (self.engine.tree.node(head).tag == .intrinsic) if (@import("task_types.zig").lookup(self.engine.pool.get(self.engine.tree.node(head).a))) |operation| {
                    if ((operation == .read or operation == .write) and count == @import("task_types.zig").arity(operation)) {
                        var owner = arguments[count - 1];
                        while (self.engine.tree.node(owner).tag == .group) owner = self.engine.tree.node(owner).a;
                        if (self.engine.tree.node(owner).tag == .name) {
                            if (self.state(self.engine.resolved[owner])) |entry| {
                                if (entry.first != 0) try self.engine.usageDiagnostic(.use_after_move, owner);
                                if (entry.loan != 0) try self.engine.usageDiagnostic(.borrow_conflict, owner);
                            }
                        } else if (try self.expression(owner, depth + 1) == .exit) return .exit;
                        var index = count - 1;
                        while (index != 0) {
                            index -= 1;
                            if (try self.expression(arguments[index], depth + 1) == .exit) return .exit;
                        }
                        return .live;
                    }
                };
            }
            if (node.tag == .apply) for (self.engine.usage_loans.items) |loan| {
                if (loan.source != source) continue;
                if (loan.acquire != 0) {
                    _ = try self.expression(loan.acquire, depth + 1);
                    _ = try self.expression(loan.release, depth + 1);
                    if (loan.callback == 0) return .live;
                    if (self.region_count == self.regions.len) return error.TypeLimit;
                    self.regions[self.region_count] = loan.region;
                    self.region_count += 1;
                    defer self.region_count -= 1;
                    _ = try self.expression(loan.callback, depth + 1);
                    return .live;
                }
                var first = node.a;
                while (self.engine.tree.node(first).tag == .group) first = self.engine.tree.node(first).a;
                var owner = self.engine.tree.node(first).b;
                while (self.engine.tree.node(owner).tag == .group) owner = self.engine.tree.node(owner).a;
                var binding: u32 = 0;
                if (self.engine.tree.node(owner).tag == .name) binding = self.engine.resolved[owner];
                if (self.state(binding)) |entry| {
                    if (entry.first != 0 or entry.loan != 0) try self.engine.usageDiagnostic(.borrow_conflict, owner);
                    entry.loan = source;
                } else if (try self.expression(owner, depth + 1) == .exit) return .exit;
                defer if (self.state(binding)) |entry| {
                    entry.loan = 0;
                };
                if (self.region_count == self.regions.len) return error.TypeLimit;
                self.regions[self.region_count] = loan.region;
                self.region_count += 1;
                defer self.region_count -= 1;
                _ = try self.expression(node.b, depth + 1);
                return .live;
            };
            if (node.tag == .apply and self.engine.demand_types[source] != 0) {
                if (try self.expression(node.a, depth + 1) == .exit) return .exit;
                var captured: std.ArrayList(u32) = .empty;
                defer captured.deinit(self.engine.allocator);
                try self.captures(node.b, source, self.engine.demand_once[source], &captured, depth + 1);
                const prior = try self.snapshot();
                defer self.engine.allocator.free(prior);
                // The delayed body owns moved captures in its new environment.
                // Restore the consumed outer state after checking that body.
                for (captured.items) |binding| if (self.state(binding)) |entry| {
                    entry.first = 0;
                };
                const outer_returns = self.returns;
                const outer_breaks = self.breaks;
                self.returns = null;
                self.breaks = null;
                defer {
                    self.states.shrinkRetainingCapacity(prior.len);
                    @memcpy(self.states.items, prior);
                    self.returns = outer_returns;
                    self.breaks = outer_breaks;
                }
                _ = try self.expression(node.b, depth + 1);
                return .live;
            }
            switch (node.tag) {
                .name => try self.use(self.engine.resolved[source], source),
                .lambda => try self.lambda(source, depth + 1),
                .group, .field_access, .type_witness => return self.expression(node.a, depth + 1),
                .return_stmt => {
                    if (try self.expression(node.a, depth + 1) == .exit) return .exit;
                    if (self.returns) |frame| self.record(frame);
                    return .exit;
                },
                .function_return_stmt => {
                    if (try self.expression(node.a, depth + 1) == .exit) return .exit;
                    return .exit;
                },
                .break_stmt, .continue_stmt => {
                    if (self.breaks) |frame| self.record(frame);
                    return .exit;
                },
                .yield_stmt => {
                    if (try self.expression(node.a, depth + 1) == .exit) return .exit;
                },
                .field, .unary, .operator_tail => {
                    if (node.b != 0 and try self.expression(node.b, depth + 1) == .exit) return .exit;
                },
                .binary => {
                    if (try self.expression(node.b, depth + 1) == .exit) return .exit;
                    if (try self.expression(node.c, depth + 1) == .exit) return .exit;
                },
                .apply, .index_access => {
                    var callee_source = node.a;
                    while (self.engine.tree.node(callee_source).tag == .group) callee_source = self.engine.tree.node(callee_source).a;
                    const callee_node = self.engine.tree.node(callee_source);
                    if (node.tag == .apply and callee_node.tag == .intrinsic and (std.mem.eql(u8, self.engine.pool.get(callee_node.a), "@usage.share") or std.mem.eql(u8, self.engine.pool.get(callee_node.a), "@resource.release") or std.mem.eql(u8, self.engine.pool.get(callee_node.a), "@demand") or std.mem.eql(u8, self.engine.pool.get(callee_node.a), "@force"))) return self.expression(node.b, depth + 1);
                    if (node.tag == .apply and callee_node.tag == .intrinsic and (std.mem.eql(u8, self.engine.pool.get(callee_node.a), "@usage.read") or std.mem.eql(u8, self.engine.pool.get(callee_node.a), "@usage.length"))) {
                        var operand = node.b;
                        while (self.engine.tree.node(operand).tag == .group) operand = self.engine.tree.node(operand).a;
                        if (self.engine.tree.node(operand).tag == .name) {
                            if (self.state(self.engine.resolved[operand])) |entry| {
                                if (entry.loan != 0) try self.engine.usageDiagnostic(.borrow_conflict, operand);
                                if (entry.first != 0) try self.engine.usageDiagnostic(.use_after_move, operand);
                            }
                        } else if (try self.expression(node.b, depth + 1) == .exit) return .exit;
                        return .live;
                    }
                    if (node.tag == .apply) for (self.regions[0..self.region_count]) |region| {
                        if (try self.engine.usageLoanFootprint(node.b, region) and !try self.admitsAffine(node.a)) try self.engine.usageDiagnostic(.borrow_escape, node.b);
                    };

                    if (try self.expression(node.a, depth + 1) == .exit) return .exit;
                    if (try self.expression(node.b, depth + 1) == .exit) return .exit;
                    if (node.tag == .apply and (try affineNominal(&self.engine.types, self.engine.nominals.items, self.engine.expr_types[node.b]) or try borrowed(&self.engine.types, self.engine.expr_types[node.b]))) {
                        var callee = self.engine.types.node(self.engine.types.head(self.engine.expr_types[node.a], 0));
                        if (callee.tag == .usage) callee = self.engine.types.node(self.engine.types.head(callee.a, 0));
                        if (callee.tag != .function or !try self.admitsAffine(node.a)) try self.engine.usageDiagnostic(.multiplicity_unknown, source);
                    }
                },
                .case_expr => return self.cases(node, depth + 1),
                .infix_chain => {
                    if (try self.expression(node.a, depth + 1) == .exit) return .exit;
                    for (self.engine.tree.list(.{ .start = node.b, .len = node.c })) |tail| if (try self.expression(tail, depth + 1) == .exit) return .exit;
                },
                .if_let_stmt => {
                    if (try self.expression(node.b, depth + 1) == .exit) return .exit;
                    const before = self.states.items.len;
                    try self.pattern(node.a, depth + 1);
                    const bodies = self.engine.tree.extra.items[node.c..][0..2];
                    const result = try self.branches(bodies[0], bodies[1], true, depth + 1);
                    self.states.shrinkRetainingCapacity(before);
                    return result;
                },
                .request_case => {
                    const prior = try self.snapshot();
                    defer self.engine.allocator.free(prior);
                    for (self.engine.tree.list(.{ .start = node.b, .len = node.c })) |arm_id| {
                        @memcpy(self.states.items, prior);
                        const arm = self.engine.tree.node(arm_id);
                        if (arm.b != 0) try self.pattern(arm.b, depth + 1);
                        _ = try self.suite(arm.c, depth + 1);
                        self.states.shrinkRetainingCapacity(prior.len);
                        // A request may repeat a handler. Outer affine state
                        // must survive every reply; fresh handler owners retire
                        // with its invocation. Unknown protocol transfer rejects.
                        for (self.states.items, prior) |after, before| if (after.first != before.first or after.loan != before.loan) {
                            try self.engine.usageDiagnostic(.multiplicity_unknown, arm_id);
                        };
                    }
                    @memcpy(self.states.items, prior);
                },
                .if_expr, .if_stmt => {
                    if (try self.expression(node.a, depth + 1) == .exit) return .exit;
                    return self.branches(node.b, node.c, node.tag == .if_stmt, depth + 1);
                },
                .let_stmt => {
                    const binding = self.engine.tree.binding(source);
                    const target = self.engine.resolved[binding.pattern];
                    if (target != 0 and @import("cleanup_contracts.zig").pureNominal(&self.engine.types, self.engine.nominals.items, self.engine.bindings.items[target].ty) and !@import("cleanup_contracts.zig").source(self.engine, binding.value)) try self.engine.usageDiagnostic(.cleanup_not_safe, binding.value);
                    if (try self.expression(binding.value, depth + 1) == .exit) return .exit;
                    if (binding.fallback != 0) {
                        const prior = try self.snapshot();
                        defer self.engine.allocator.free(prior);
                        _ = try self.suite(binding.fallback, depth + 1);
                        self.states.shrinkRetainingCapacity(prior.len);
                        @memcpy(self.states.items, prior);
                    }
                    try self.pattern(binding.pattern, depth + 1);
                },
                .use_stmt, .iterator_bind => {
                    if (try self.expression(node.b, depth + 1) == .exit) return .exit;
                    try self.introduce(self.engine.resolved[source]);
                },
                .rebind_stmt => {
                    if (try self.expression(node.b, depth + 1) == .exit) return .exit;
                    try self.introduce(self.engine.resolved[source]);
                },
                .block => {
                    if (node.c != 0 and self.states.items.len != 0) try self.engine.usageDiagnostic(.multiplicity_unknown, source);
                    return self.block(source, depth + 1);
                },
                .product, .array, .record => {
                    for (self.engine.tree.children(source)) |child| if (try self.expression(child, depth + 1) == .exit) return .exit;
                },
                .for_stmt, .range_stmt, .forever_stmt => {
                    // Bounds execute once, in source order, before any body
                    // backedge. Named ranges store their end outside node.b.
                    if (node.tag == .range_stmt) if (try self.expression(node.a, depth + 1) == .exit) return .exit;
                    if (node.tag != .forever_stmt) if (try self.expression(node.b, depth + 1) == .exit) return .exit;
                    if (node.tag == .for_stmt) {
                        const end = self.engine.tree.extra.items[node.c];
                        if (end != 0 and try self.expression(end, depth + 1) == .exit) return .exit;
                    }
                    var single = false;
                    if (node.tag == .range_stmt) single = self.singleIteration(node.a, node.b);
                    if (node.tag == .for_stmt) single = self.singleIteration(node.b, self.engine.tree.extra.items[node.c]);
                    const prior = try self.snapshot();
                    defer self.engine.allocator.free(prior);
                    const exits = try self.snapshot();
                    defer self.engine.allocator.free(exits);
                    var frame: ExitFrame = .{ .joined = exits };
                    const outer_breaks = self.breaks;
                    self.breaks = &frame;
                    defer self.breaks = outer_breaks;
                    if (node.tag == .for_stmt) try self.pattern(node.a, depth + 1);
                    var body = node.a;
                    if (node.tag == .range_stmt) body = node.c;
                    if (node.tag == .for_stmt) body = self.engine.tree.extra.items[node.c + 1];
                    const flow = try self.suite(body, depth + 1);
                    self.states.shrinkRetainingCapacity(prior.len);
                    if (flow == .live and !single) for (self.states.items, prior) |entry, before| if (entry.first != before.first) {
                        try self.engine.usageDiagnostic(.once_reused, source);
                        break;
                    };
                    // Return edges belong to the enclosing do. Only breaks
                    // and a finite loop's zero-iteration edge reach its suffix.
                    if (flow == .live and single) self.record(&frame);
                    @memcpy(self.states.items, exits);
                    if ((node.tag == .forever_stmt or single) and !frame.seen) return .exit;
                },
                .package_pack => {
                    if (try self.expression(self.engine.tree.extra.items[node.c], depth + 1) == .exit) return .exit;
                },
                .package_unpack => {
                    if (try self.expression(node.a, depth + 1) == .exit) return .exit;
                    try self.introduce(self.engine.resolved[source]);
                    return self.expression(self.engine.tree.extra.items[node.c + 2], depth + 1);
                },
                else => {},
            }
            return .live;
        }
    };
}
pub fn validate(engine: anytype) T.Error!void {
    var walker: Walker(@TypeOf(engine)) = .{ .engine = engine, .task_views = engine.pool.lookup("@task.read") != null or engine.pool.lookup("@task.write") != null };
    defer walker.states.deinit(engine.allocator);
    for (engine.tree.roots.items) |root| if (engine.tree.node(root).tag == .value_decl) {
        walker.states.clearRetainingCapacity();
        walker.remaining = 65_536;
        const binding = engine.resolved[root];
        const body = engine.tree.valueDecl(root).body;
        if (binding != 0 and @import("cleanup_contracts.zig").pureNominal(&engine.types, engine.nominals.items, engine.bindings.items[binding].ty) and !@import("cleanup_contracts.zig").source(engine, body)) try engine.usageDiagnostic(.cleanup_not_safe, body);
        _ = walker.expression(body, 0) catch |err| {
            if (err == error.TypeLimit) {
                try engine.usageDiagnostic(.usage_analysis_limit, root);
                continue;
            }
            return err;
        };
    };
}
