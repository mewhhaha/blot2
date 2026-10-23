//! Interned semantic types for specialization and pure evaluation. This table
//! preserves nominal arguments and has no dependency on a machine layout or
//! runtime value representation. Published IDs remain stable through growth.
const std = @import("std");
const types = @import("../check/types.zig");
const projections = @import("../reuse/projection_cache.zig");
pub const Effects = @import("../check/effect_evidence.zig");
const Allocator = std.mem.Allocator;
pub const Id = u32;
// Tags 19/22 belonged to body-plus-arity quantifiers. Explicit ownership uses
// fresh wire tags: older reflected archive schemas reject this representation.
pub const Tag = enum(u8) { absent, unit, boolean, u32, f32, never, function, product, record, nominal, array, list, cursor, demand, type_constructor, resolver, provider, state_provider, erased_proof, bound = 20, usage = 21, scoped = 23, forall = 24, existential = 25, projection = 26 };
pub const Node = struct { tag: Tag, a: u32 = 0, b: u32 = 0, c: u32 = 0 };
pub const Mapping = struct { variable: types.Id, evidence: Id };
/// Semantic predicates belong to their exact canonical quantifier owner.
/// No source span, inference nonce, or physical slot confers goal authority.
pub const Goal = struct { ty: Id, kind: types.ObligationKind, name: u32 = 0, result: Id = 0, other: Id = 0, signature: Id = 0, operator: types.Operator = .none, identity: types.NominalIdentity = .{ .unit = 0, .decl = 0 }, explicit: bool = false };
pub const QuantifierGoals = struct { owner: Id, goals: types.List };
pub const Projection = struct { member: u32, scope: u32, goal: u32 };
const ScopeFrame = struct { binders: []const Id, goals: []const Goal = &.{} };
pub const RowMapping = struct { variable: u32, evidence: Effects.Id };
pub const Error = Allocator.Error || error{ UnresolvedType, EvidenceLimit, TypeMismatch };
pub const ProjectionResolver = struct { context: *anyopaque, remaining: *usize, resolve: *const fn (*anyopaque, types.NominalIdentity, u32, []const Id) Error!Id };
pub const View = struct {
    nodes: []const Node,
    extra: []const Id,
    effects: Effects.View = .{},
    quantifier_goals: []const QuantifierGoals = &.{},
    quantifier_obligations: []const Goal = &.{},
    pub fn quantifierGoals(self: View, owner: Id) []const Goal {
        var lo: usize = 0;
        var hi = self.quantifier_goals.len;
        while (lo < hi) {
            const middle = lo + (hi - lo) / 2;
            const entry = self.quantifier_goals[middle];
            if (entry.owner < owner) lo = middle + 1 else hi = middle;
        }
        if (lo < self.quantifier_goals.len) {
            const entry = self.quantifier_goals[lo];
            if (entry.owner == owner) return self.quantifier_obligations[entry.goals.start..][0..entry.goals.len];
        }
        return &.{};
    }
    pub fn validateGoalTables(self: View) Error!void {
        var remaining: usize = 65_536;
        return self.validateGoalTablesWithBudget(&remaining);
    }
    pub fn validateGoalTablesWithBudget(self: View, remaining: *usize) Error!void {
        if (self.quantifier_goals.len > self.nodes.len or self.quantifier_obligations.len > 65_536) return error.EvidenceLimit;
        var previous: Id = 0;
        var cursor: usize = 0;
        for (self.quantifier_goals) |entry| {
            if (remaining.* == 0) return error.EvidenceLimit;
            remaining.* -= 1;
            if (entry.owner <= previous or entry.owner >= self.nodes.len or entry.goals.len == 0 or entry.goals.start != cursor or cursor > self.quantifier_obligations.len or entry.goals.len > self.quantifier_obligations.len - cursor) return error.TypeMismatch;
            const tag = self.node(entry.owner).tag;
            if (tag != .forall and tag != .existential) return error.TypeMismatch;
            for (self.quantifier_obligations[entry.goals.start..][0..entry.goals.len]) |goal| {
                if (remaining.* == 0) return error.EvidenceLimit;
                remaining.* -= 1;
                if (@backingInt(goal.kind) > @backingInt(types.ObligationKind.task_receive) or @backingInt(goal.operator) > @backingInt(types.Operator.shift_right) or goal.ty == 0) return error.TypeMismatch;
                inline for (.{ "ty", "other", "result", "signature" }) |field| if (@field(goal, field) >= entry.owner) return error.TypeMismatch;
            }
            previous = entry.owner;
            cursor += entry.goals.len;
        }
        if (cursor != self.quantifier_obligations.len) return error.TypeMismatch;
    }
    pub fn openQuantifier(self: View, id: Id, remaining: *usize, seen: ?[]bool) Error!void {
        try self.validateGoalTablesWithBudget(remaining);
        return self.openQuantifierValidated(id, remaining, seen);
    }
    /// The enclosing graph reader validates goal tables once for all roots.
    pub fn openQuantifierValidated(self: View, id: Id, remaining: *usize, seen: ?[]bool) Error!void {
        var frames: [128]ScopeFrame = undefined;
        try self.walk(id, 0, remaining, &frames, 0, false, seen, true);
    }
    pub fn node(self: View, id: Id) Node {
        return self.nodes[id];
    }
    pub fn children(self: View, id: Id) []const Id {
        const n = self.node(id);
        return switch (n.tag) {
            .product => self.extra[n.a..][0..n.b],
            .record => self.extra[n.a..][0 .. @as(usize, n.b) * 2],
            .nominal, .projection => self.extra[n.c + 1 ..][0..self.extra[n.c]],
            .forall, .existential => self.extra[n.c..][0..n.b],
            else => &.{},
        };
    }
    pub fn projection(self: View, id: Id) Projection {
        const n = self.node(id);
        const tail = self.extra[n.c + 1 + self.extra[n.c] ..];
        return .{ .member = tail[0], .scope = tail[1], .goal = tail[2] };
    }
    /// Canonical quantifiers own an explicit list, preserving unused binder
    /// sorts. Bound leaves use lexical depth, never a solver or producer ID.
    pub fn body(self: View, id: Id, binders: []const Id, depth: usize, remaining: *usize, seen: ?[]bool) Error!void {
        try self.validateGoalTablesWithBudget(remaining);
        var frames: [128]ScopeFrame = undefined;
        try self.binderList(binders, seen, remaining);
        frames[0] = .{ .binders = binders };
        try self.walk(id, depth, remaining, &frames, 1, false, seen, false);
    }
    pub fn openBody(self: View, id: Id, binders: []const Id, remaining: *usize, seen: ?[]bool) Error!void {
        return self.openBodyWithGoals(id, binders, &.{}, remaining, seen);
    }
    pub fn openBodyWithGoals(self: View, id: Id, binders: []const Id, goals: []const Goal, remaining: *usize, seen: ?[]bool) Error!void {
        try self.validateGoalTablesWithBudget(remaining);
        return self.bodyWithGoalsValidated(id, binders, goals, remaining, seen);
    }
    fn bodyWithGoalsValidated(self: View, id: Id, binders: []const Id, goals: []const Goal, remaining: *usize, seen: ?[]bool) Error!void {
        var frames: [128]ScopeFrame = undefined;
        try self.binderList(binders, seen, remaining);
        frames[0] = .{ .binders = binders, .goals = goals };
        try self.walk(id, 0, remaining, &frames, 1, false, seen, true);
    }
    pub fn closed(self: View, id: Id, depth: usize, remaining: *usize) Error!void {
        try self.validateGoalTablesWithBudget(remaining);
        var frames: [128]ScopeFrame = undefined;
        try self.walk(id, depth, remaining, &frames, 0, false, null, false);
    }
    fn binderList(self: View, binders: []const Id, seen: ?[]bool, remaining: *usize) Error!void {
        if (binders.len == 0 or binders.len > 128) return error.TypeMismatch;
        for (binders, 0..) |id, ordinal| {
            if (remaining.* == 0) return error.EvidenceLimit;
            remaining.* -= 1;
            if (id == 0 or id >= self.nodes.len) return error.TypeMismatch;
            const leaf = self.node(id);
            if (leaf.tag != .bound or leaf.a != ordinal or leaf.b > 2 or leaf.c != 0) return error.TypeMismatch;
            if (seen) |slots| {
                if (id >= slots.len) return error.EvidenceLimit;
                slots[id] = true;
            }
        }
    }
    fn walk(self: View, id: Id, depth: usize, remaining: *usize, frames: *[128]ScopeFrame, scope_count: usize, region: bool, seen: ?[]bool, open: bool) Error!void {
        if (depth >= 128 or remaining.* == 0) return error.EvidenceLimit;
        remaining.* -= 1;
        if (id == 0 or id >= self.nodes.len) return error.TypeMismatch;
        const n = self.node(id);
        if (region and (n.tag != .bound or n.b != 2)) return error.TypeMismatch;
        switch (n.tag) {
            .bound => {
                if (n.c >= scope_count) {
                    if (!open or n.a >= 128 or n.b > 2 or (region and n.b != 2) or (!region and n.b != 0)) return error.TypeMismatch;
                    return;
                }
                const owner = frames[scope_count - 1 - n.c].binders;
                if (n.a >= owner.len) return error.TypeMismatch;
                const formal = self.node(owner[n.a]);
                if (formal.b != n.b or (region and n.b != 2) or (!region and n.b != 0)) return error.TypeMismatch;
                if (seen) |slots| {
                    if (id >= slots.len) return error.EvidenceLimit;
                    slots[id] = true;
                }
            },
            .forall, .existential => {
                if (scope_count == frames.len or n.c > self.extra.len or n.b > self.extra.len - n.c) return error.TypeMismatch;
                const binders = self.children(id);
                try self.binderList(binders, seen, remaining);
                if (n.tag == .existential) for (binders) |binder| if (self.node(binder).b != 0) return error.TypeMismatch;
                frames[scope_count] = .{ .binders = binders, .goals = self.quantifierGoals(id) };
                try self.walk(n.a, depth + 1, remaining, frames, scope_count + 1, false, seen, open);
                for (self.quantifierGoals(id)) |goal| {
                    if (remaining.* == 0) return error.EvidenceLimit;
                    remaining.* -= 1;
                    inline for (.{ "ty", "other", "result", "signature" }) |field| {
                        const endpoint = @field(goal, field);
                        if (endpoint != 0) try self.walk(endpoint, depth + 1, remaining, frames, scope_count + 1, false, seen, open);
                    }
                }
            },
            .projection => {
                if (n.c >= self.extra.len or self.extra[n.c] > self.extra.len - n.c - 1) return error.TypeMismatch;
                const count = self.extra[n.c];
                if (self.extra.len - n.c - 1 - count < 3) return error.TypeMismatch;
                const descriptor = self.projection(id);
                if (descriptor.member == 0 or descriptor.scope >= 128 or descriptor.goal >= 4096) return error.TypeMismatch;
                for (self.children(id)) |argument| try self.walk(argument, depth + 1, remaining, frames, scope_count, false, seen, open);
                if (descriptor.scope >= scope_count) {
                    if (!open) return error.TypeMismatch;
                    return;
                }
                const goals = frames[scope_count - 1 - descriptor.scope].goals;
                if (descriptor.goal >= goals.len) return error.TypeMismatch;
                try @import("evidence_projection.zig").validate(self, id, goals[descriptor.goal], remaining);
                if (seen) |slots| {
                    if (id >= slots.len) return error.EvidenceLimit;
                    slots[id] = true;
                }
            },
            .usage => {
                if (n.b > @backingInt(types.UsageKind.concurrent)) return error.TypeMismatch;
                const loan = n.b == @backingInt(types.UsageKind.borrow) or n.b == @backingInt(types.UsageKind.borrow_mut);
                if (loan != (n.c != 0)) return error.TypeMismatch;
                try self.walk(n.a, depth + 1, remaining, frames, scope_count, false, seen, open);
                if (loan) try self.walk(n.c, depth + 1, remaining, frames, scope_count, true, seen, open);
            },
            .function, .state_provider => {
                try self.walk(n.a, depth + 1, remaining, frames, scope_count, false, seen, open);
                try self.walk(n.b, depth + 1, remaining, frames, scope_count, false, seen, open);
                if (n.tag == .function) try self.walkRow(n.c, depth + 1, remaining, frames, scope_count, seen, open) else try self.walk(n.c, depth + 1, remaining, frames, scope_count, false, seen, open);
            },
            .demand, .provider => {
                try self.walk(n.a, depth + 1, remaining, frames, scope_count, false, seen, open);
                try self.walkRow(n.c, depth + 1, remaining, frames, scope_count, seen, open);
            },
            .array, .list, .cursor, .resolver => try self.walk(n.a, depth + 1, remaining, frames, scope_count, false, seen, open),
            .product, .record, .nominal => {
                var start = n.a;
                var count = n.b;
                if (n.tag == .record) count = std.math.mul(u32, count, 2) catch return error.EvidenceLimit;
                if (n.tag == .nominal) {
                    if (n.c >= self.extra.len) return error.TypeMismatch;
                    start = n.c + 1;
                    count = self.extra[n.c];
                }
                if (start > self.extra.len or count > self.extra.len - start) return error.TypeMismatch;
                for (self.extra[start..][0..count], 0..) |child, index| {
                    if (n.tag == .record and index % 2 == 0) continue;
                    try self.walk(child, depth + 1, remaining, frames, scope_count, false, seen, open);
                }
            },
            .scoped, .absent, .erased_proof => return error.UnresolvedType,
            .type_constructor, .unit, .boolean, .u32, .f32, .never => {},
        }
    }
    fn walkRow(self: View, row: Effects.Id, depth: usize, remaining: *usize, frames: *[128]ScopeFrame, scope_count: usize, seen: ?[]bool, open: bool) Error!void {
        if (row == 0) return;
        if (depth >= 128 or remaining.* == 0 or row >= self.effects.rows.len) return error.EvidenceLimit;
        remaining.* -= 1;
        const formal = self.effects.rows[row].formal;
        if (formal != 0) {
            if (formal >= self.nodes.len or remaining.* == 0) return error.TypeMismatch;
            remaining.* -= 1;
            const leaf = self.node(formal);
            if (leaf.tag != .bound or leaf.b != 1 or leaf.a >= 128 or leaf.c >= 128) return error.TypeMismatch;
            if (leaf.c >= scope_count) {
                if (!open) return error.TypeMismatch;
            } else {
                const owner = frames[scope_count - 1 - leaf.c].binders;
                if (leaf.a >= owner.len or self.node(owner[leaf.a]).b != 1) return error.TypeMismatch;
            }
            if (seen) |slots| {
                if (formal >= slots.len) return error.EvidenceLimit;
                slots[formal] = true;
            }
        }
        for (self.effects.rowLabels(row)) |label| {
            if (label == 0 or label >= self.effects.operations.len or remaining.* == 0) return error.TypeMismatch;
            remaining.* -= 1;
            for (self.effects.operationArguments(label)) |argument| try self.walk(argument, depth + 1, remaining, frames, scope_count, false, seen, open);
        }
    }
};
pub const Snapshot = struct {
    nodes: []Node,
    extra: []Id,
    effects: Effects.Snapshot,
    quantifier_goals: []QuantifierGoals = &.{},
    quantifier_obligations: []Goal = &.{},
    pub fn view(self: *const Snapshot) View {
        return .{ .nodes = self.nodes, .extra = self.extra, .effects = self.effects.view(), .quantifier_goals = self.quantifier_goals, .quantifier_obligations = self.quantifier_obligations };
    }
    pub fn deinit(self: *Snapshot, allocator: Allocator) void {
        allocator.free(self.nodes);
        allocator.free(self.extra);
        allocator.free(self.quantifier_goals);
        allocator.free(self.quantifier_obligations);
        self.effects.deinit(allocator);
        self.* = undefined;
    }
};
fn goalEqual(left: []const Goal, right: []const Goal) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!std.meta.eql(a, b)) return false;
    return true;
}
pub const Store = struct {
    allocator: Allocator,
    effects: Effects.Store,
    nodes: std.ArrayList(Node) = .empty,
    extra: std.ArrayList(Id) = .empty,
    next: std.ArrayList(Id) = .empty,
    buckets: std.AutoHashMapUnmanaged(u64, Id) = .empty,
    projection_owners: std.ArrayList([]const types.Id) = .empty,
    projection_quantifiers: std.ArrayList(types.Id) = .empty,
    quantifier_goals: std.ArrayList(QuantifierGoals) = .empty,
    quantifier_obligations: std.ArrayList(Goal) = .empty,
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
        self.projection_owners.deinit(self.allocator);
        self.projection_quantifiers.deinit(self.allocator);
        self.quantifier_goals.deinit(self.allocator);
        self.quantifier_obligations.deinit(self.allocator);
        self.* = undefined;
    }
    pub fn view(self: *const Store) View {
        return .{ .nodes = self.nodes.items, .extra = self.extra.items, .effects = self.effects.view(), .quantifier_goals = self.quantifier_goals.items, .quantifier_obligations = self.quantifier_obligations.items };
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
        const goals = try allocator.dupe(QuantifierGoals, self.quantifier_goals.items);
        errdefer allocator.free(goals);
        const obligations = try allocator.dupe(Goal, self.quantifier_obligations.items);
        errdefer allocator.free(obligations);
        return .{ .nodes = nodes, .extra = extra, .effects = try self.effects.copyOwned(allocator), .quantifier_goals = goals, .quantifier_obligations = obligations };
    }
    /// An independent mutable owner with exactly the same published IDs.
    pub fn clone(self: *const Store, allocator: Allocator) Allocator.Error!Store {
        var result: Store = .{ .allocator = allocator, .effects = .{ .allocator = allocator } };
        errdefer result.deinit();
        inline for (.{ "nodes", "extra", "next", "buckets", "quantifier_goals", "quantifier_obligations" }) |field| @field(result, field) = try @field(self, field).clone(allocator);
        result.effects = try self.effects.clone(allocator);
        return result;
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
        if ((tag == .forall or tag == .existential) and values.len == 0) {
            if (b == 0 or b > 128) return error.TypeMismatch;
            var binders: [128]Id = undefined;
            for (binders[0..b], 0..) |*binder, ordinal| binder.* = try self.intern(.bound, @intCast(ordinal), 0, &.{});
            return self.internFields(tag, a, b, row, binders[0..b]);
        }
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
        // One header update streams the same bytes as one update per word.
        const header = std.mem.toBytes(tag) ++ std.mem.toBytes(a) ++ std.mem.toBytes(b) ++ std.mem.toBytes(row);
        var hash = std.hash.Wyhash.init(0);
        hash.update(&header);
        hash.update(std.mem.sliceAsBytes(owned));
        return self.internWithEffectsHashed(tag, a, b, row, owned, hash.final());
    }
    fn internHashed(self: *Store, tag: Tag, a: u32, b: u32, values: []const Id, fingerprint: u64) Error!Id {
        return self.internWithEffectsHashed(tag, a, b, 0, values, fingerprint);
    }
    pub fn internProjection(self: *Store, identity: types.NominalIdentity, member: u32, arguments: []const Id, scope: u32, goal: u32) Error!Id {
        var words: std.ArrayList(Id) = .empty;
        defer words.deinit(self.allocator);
        try words.appendSlice(self.allocator, arguments);
        try words.appendSlice(self.allocator, &.{ member, scope, goal });
        return self.intern(.projection, identity.unit, identity.decl, words.items);
    }
    pub fn internQuantifiedWithGoals(self: *Store, tag: Tag, body_: Id, binders: []const Id, goals: []const Goal) Error!Id {
        if (tag != .forall and tag != .existential) return error.TypeMismatch;
        if (goals.len == 0) return self.intern(tag, body_, @intCast(binders.len), binders);
        var hash = std.hash.Wyhash.init(0);
        hash.update(std.mem.asBytes(&tag));
        hash.update(std.mem.asBytes(&body_));
        const arity: u32 = @intCast(binders.len);
        hash.update(std.mem.asBytes(&arity));
        hash.update(std.mem.sliceAsBytes(binders));
        for (goals) |goal| inline for (@typeInfo(Goal).@"struct".field_names) |field| hash.update(std.mem.asBytes(&@field(goal, field)));
        return self.internGoalFields(tag, body_, arity, 0, binders, goals, hash.final());
    }
    fn internWithEffectsHashed(self: *Store, tag: Tag, a: u32, b: u32, row: Effects.Id, values: []const Id, fingerprint: u64) Error!Id {
        return self.internGoalFields(tag, a, b, row, values, &.{}, fingerprint);
    }
    fn internGoalFields(self: *Store, tag: Tag, a: u32, b: u32, row: Effects.Id, values: []const Id, goals: []const Goal, fingerprint: u64) Error!Id {
        if (tag != .state_provider and tag != .scoped and tag != .usage and tag != .bound and (row >= self.effects.rows.items.len or (row != 0 and tag != .function and tag != .demand and tag != .provider))) return error.TypeMismatch;
        switch (tag) {
            .absent => return error.UnresolvedType,
            .usage => {
                if (a == 0 or a >= self.nodes.items.len or b > @backingInt(types.UsageKind.concurrent) or values.len != 0) return error.TypeMismatch;
                const loan = b == @backingInt(types.UsageKind.borrow) or b == @backingInt(types.UsageKind.borrow_mut);
                if (loan != (row != 0)) return error.TypeMismatch;
                if (loan and (row >= self.nodes.items.len or self.node(row).tag != .bound or self.node(row).b != 2)) return error.TypeMismatch;
            },
            .erased_proof => if (a != 0 or b != 0 or values.len != 0) return error.TypeMismatch,
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
            .forall, .existential => {
                if (a == 0 or a >= self.nodes.items.len or b == 0 or b > 128 or row != 0 or values.len != b) return error.TypeMismatch;
                var remaining: usize = 4096;
                try self.view().bodyWithGoalsValidated(a, values, goals, &remaining, null);
                if (tag == .existential) for (values) |binder| if (self.node(binder).b != 0) return error.TypeMismatch;
                for (goals) |goal| {
                    if (goal.ty == 0 or @backingInt(goal.kind) > @backingInt(types.ObligationKind.task_receive) or @backingInt(goal.operator) > @backingInt(types.Operator.shift_right)) return error.TypeMismatch;
                    inline for (.{ "ty", "other", "result", "signature" }) |field| {
                        const endpoint = @field(goal, field);
                        if (endpoint != 0) try self.view().bodyWithGoalsValidated(endpoint, values, goals, &remaining, null);
                    }
                }
            },
            .scoped => if (a == 0 or a >= self.nodes.items.len or self.node(a).tag != .nominal or b == 0 or row == 0 or values.len != 0) return error.TypeMismatch,
            .bound => if (a >= 128 or b > 2 or row >= 128 or values.len != 0) return error.TypeMismatch,
            .function => if (values.len != 0 or a == 0 or b == 0 or a >= self.nodes.items.len or b >= self.nodes.items.len) return error.TypeMismatch,
            .array, .list, .cursor, .demand, .resolver, .provider => if (values.len != 0 or a == 0 or a >= self.nodes.items.len or b != 0) return error.TypeMismatch,
            .state_provider => if (values.len != 0 or a == 0 or b == 0 or row == 0 or a >= self.nodes.items.len or b >= self.nodes.items.len or row >= self.nodes.items.len) return error.TypeMismatch,
            .product, .record => if (a != 0 or b != 0) return error.TypeMismatch,
            .projection => {
                if (a == 0 or b == 0 or values.len < 3 or values[values.len - 3] == 0 or values[values.len - 2] >= 128 or values[values.len - 1] >= 4096) return error.TypeMismatch;
            },
            .nominal => if (a == 0) return error.TypeMismatch,
            .type_constructor => if (a == 0 or b == 0 or values.len != 0) return error.TypeMismatch,
        }
        if (tag == .provider and self.node(a).tag != .nominal and self.node(a).tag != .scoped) return error.TypeMismatch;
        switch (tag) {
            .array, .list, .cursor, .demand, .resolver, .provider => if (self.node(a).tag == .erased_proof) return error.TypeMismatch,
            else => {},
        }
        if (tag == .state_provider and ((self.node(a).tag != .nominal and self.node(a).tag != .scoped) or (self.node(b).tag != .nominal and self.node(b).tag != .scoped))) return error.TypeMismatch;
        for (values, 0..) |value, i| {
            if (tag == .projection and i >= values.len - 3) continue;
            if (tag == .record and i % 2 == 0) {
                if (value == 0) return error.TypeMismatch;
            } else {
                if (value == 0 or value >= self.nodes.items.len) return error.TypeMismatch;
                if (self.node(value).tag == .erased_proof) return error.TypeMismatch;
            }
        }
        var candidate = self.buckets.get(fingerprint) orelse 0;
        while (candidate != 0) : (candidate = self.next.items[candidate]) {
            const n = self.node(candidate);
            const same = n.tag == tag and switch (tag) {
                .product, .record => std.mem.eql(Id, self.children(candidate), values),
                .nominal, .forall, .existential => n.a == a and n.b == b and std.mem.eql(Id, self.children(candidate), values),
                .projection => n.a == a and n.b == b and std.mem.eql(Id, self.extra.items[n.c + 1 ..][0 .. self.extra.items[n.c] + 3], values),
                else => n.a == a and n.b == b and n.c == row,
            };
            if (same and goalEqual(self.view().quantifierGoals(candidate), goals)) return candidate;
        }
        if (self.nodes.items.len >= std.math.maxInt(Id) or values.len >= std.math.maxInt(Id) or self.extra.items.len > std.math.maxInt(Id) - values.len - 1) return error.EvidenceLimit;
        const bucket = try self.buckets.getOrPut(self.allocator, fingerprint);
        if (!bucket.found_existing) bucket.value_ptr.* = 0;
        // Reserve every buffer before exposing an ID. Failure leaves every
        // previously published ID, node and child span unchanged.
        try self.nodes.ensureUnusedCapacity(self.allocator, 1);
        try self.next.ensureUnusedCapacity(self.allocator, 1);
        try self.extra.ensureUnusedCapacity(self.allocator, values.len + 1);
        if (goals.len != 0) {
            if (goals.len > std.math.maxInt(u32) - self.quantifier_obligations.items.len) return error.EvidenceLimit;
            try self.quantifier_goals.ensureUnusedCapacity(self.allocator, 1);
            try self.quantifier_obligations.ensureUnusedCapacity(self.allocator, goals.len);
        }
        var n: Node = .{ .tag = tag, .a = a, .b = b, .c = row };
        switch (tag) {
            .product, .record => {
                n.a = @intCast(self.extra.items.len);
                n.b = @intCast(if (tag == .record) values.len / 2 else values.len);
                self.extra.appendSliceAssumeCapacity(values);
            },
            .forall, .existential => {
                n.c = @intCast(self.extra.items.len);
                self.extra.appendSliceAssumeCapacity(values);
            },
            .nominal, .projection => {
                n.c = @intCast(self.extra.items.len);
                var count = values.len;
                if (tag == .projection) count -= 3;
                self.extra.appendAssumeCapacity(@intCast(count));
                self.extra.appendSliceAssumeCapacity(values);
            },
            else => {},
        }
        const id: Id = @intCast(self.nodes.items.len);
        if (goals.len != 0) {
            self.quantifier_goals.appendAssumeCapacity(.{ .owner = id, .goals = .{ .start = @intCast(self.quantifier_obligations.items.len), .len = @intCast(goals.len) } });
            self.quantifier_obligations.appendSliceAssumeCapacity(goals);
        }
        self.nodes.appendAssumeCapacity(n);
        self.next.appendAssumeCapacity(bucket.value_ptr.*);
        bucket.value_ptr.* = id;
        return id;
    }
    /// Reflection may observe a sealed package type, but cannot inspect a free
    /// abstract leaf reached through an opened payload or callable result.
    pub fn containsAbstract(self: *const Store, id: Id) Error!bool {
        var remaining: usize = 4096;
        return self.abstractDepth(id, 0, &remaining);
    }
    fn abstractDepth(self: *const Store, id: Id, depth: usize, remaining: *usize) Error!bool {
        if (depth >= 128 or remaining.* == 0) return error.EvidenceLimit;
        remaining.* -= 1;
        const node_ = self.node(id);
        switch (node_.tag) {
            .bound, .projection => return true,
            .forall, .existential => return false,
            .function => return try self.abstractDepth(node_.a, depth + 1, remaining) or try self.abstractDepth(node_.b, depth + 1, remaining),
            .scoped, .usage, .array, .list, .cursor, .demand, .resolver, .provider => return self.abstractDepth(node_.a, depth + 1, remaining),
            .state_provider => return try self.abstractDepth(node_.a, depth + 1, remaining) or try self.abstractDepth(node_.b, depth + 1, remaining) or try self.abstractDepth(node_.c, depth + 1, remaining),
            .product, .record, .nominal => for (self.children(id), 0..) |child, index| {
                if (node_.tag == .record and index % 2 == 0) continue;
                if (try self.abstractDepth(child, depth + 1, remaining)) return true;
            },
            else => {},
        }
        return false;
    }
    /// Source is an immutable, normalized core.Types-compatible table. Mapping
    /// variables are local to that source module; evidence IDs are session-wide.
    pub fn project(self: *Store, source: anytype, ty: types.Id, mappings: []const Mapping) Error!Id {
        return self.projectWithRows(source, ty, mappings, &.{});
    }
    pub fn projectWithRows(self: *Store, source: anytype, ty: types.Id, mappings: []const Mapping, rows: []const RowMapping) Error!Id {
        var budget: usize = 1_000_000;
        return self.projectDepth(source, ty, mappings, rows, 0, &budget, false, null, null, null);
    }
    pub fn projectWithBudget(self: *Store, source: anytype, ty: types.Id, mappings: []const Mapping, rows: []const RowMapping, budget: *usize) Error!Id {
        return self.projectDepth(source, ty, mappings, rows, 0, budget, false, null, null, null);
    }
    pub fn projectSelected(self: *Store, source: anytype, ty: types.Id, mappings: []const Mapping, rows: []const RowMapping, resolver: ProjectionResolver) Error!Id {
        var budget: usize = 1_000_000;
        var memo: projections.Cache = .{};
        defer memo.deinit(self.allocator);
        return self.projectDepth(source, ty, mappings, rows, 0, &budget, false, &memo, null, resolver);
    }
    pub fn projectEffects(self: *Store, source: anytype, row: types.Effects.Id, mappings: []const Mapping, rows: []const RowMapping) Error!Effects.Id {
        var budget: usize = 1_000_000;
        return self.projectRowDepth(source, row, mappings, rows, 0, &budget, false, null, null, null);
    }
    /// Owned inference has no caller mappings. Successful normalized subgraphs
    /// are immutable until rollback or physical mutation changes their clocks.
    /// Share the ordinary projector, including its exact depth and work limits.
    pub fn projectOwned(self: *Store, source: *const types.Store, ty: types.Id, memo: *projections.Cache) Error!Id {
        if (!memo.activate(source, self, source.closed_generation, source.effects.physical_epoch)) return self.project(source, ty, &.{});
        var budget: usize = 1_000_000;
        return self.projectDepth(source, ty, &.{}, &.{}, 0, &budget, true, memo, null, null);
    }
    pub fn projectAssociatedOwned(self: *Store, source: *const types.Store, ty: types.Id, memo: *projections.Cache, remaining: *usize) Error!Id {
        const Closed = struct {
            fn resolve(_: *anyopaque, _: types.NominalIdentity, _: u32, _: []const Id) Error!Id {
                return error.UnresolvedType;
            }
        };
        const resolver: ProjectionResolver = .{ .context = self, .remaining = remaining, .resolve = Closed.resolve };
        if (!memo.activate(source, self, source.closed_generation, source.effects.physical_epoch)) return self.projectSelected(source, ty, &.{}, &.{}, resolver);
        var budget: usize = 1_000_000;
        return self.projectDepth(source, ty, &.{}, &.{}, 0, &budget, false, memo, null, resolver);
    }
    fn projectDepth(self: *Store, source: anytype, ty: types.Id, mappings: []const Mapping, rows: []const RowMapping, depth: usize, budget: *usize, comptime retained: bool, memo: ?*projections.Cache, parent_height: ?*u16, resolver: ?ProjectionResolver) Error!Id {
        if (depth >= 1024 or budget.* == 0) return error.EvidenceLimit;
        if (resolver) |selection| {
            if (depth >= 256 or selection.remaining.* == 0) return error.EvidenceLimit;
            selection.remaining.* -= 1;
            if (ty > types.never) if (memo) |cache| if (cache.answers.get(ty)) |answer| {
                if (depth + answer.height > 256) return error.EvidenceLimit;
                budget.* -= 1;
                if (parent_height) |parent| parent.* = @max(parent.*, answer.height + 1);
                return answer.value;
            };
        }
        if (retained and ty > types.never) if (memo.?.answers.get(ty)) |answer| {
            if (depth + answer.height > 1024 or budget.* < answer.visits) return error.EvidenceLimit;
            budget.* -= answer.visits;
            if (parent_height) |parent| parent.* = @max(parent.*, answer.height + 1);
            return answer.value;
        };
        const before = budget.*;
        budget.* -= 1;
        var height: u16 = 1;
        const result = try self.projectNodeDepth(source, ty, mappings, rows, depth, budget, retained, memo, &height, resolver);
        if (retained) {
            if (parent_height) |parent| parent.* = @max(parent.*, height + 1);
            if (ty > types.never) try memo.?.answers.put(memo.?.allocator orelse self.allocator, ty, .{ .value = result, .visits = @intCast(before - budget.*), .height = height });
        }
        if (!retained and memo != null) {
            if (parent_height) |parent| parent.* = @max(parent.*, height + 1);
            if (ty > types.never) try memo.?.answers.put(memo.?.allocator orelse self.allocator, ty, .{ .value = result, .visits = 1, .height = height });
        }
        return result;
    }
    fn projectRowDepth(self: *Store, source: anytype, row: types.Effects.Id, mappings: []const Mapping, rows: []const RowMapping, depth: usize, budget: *usize, comptime retained: bool, memo: ?*projections.Cache, parent_height: ?*u16, resolver: ?ProjectionResolver) Error!Effects.Id {
        if (depth >= 1024 or budget.* == 0) return error.EvidenceLimit;
        budget.* -= 1;
        if (resolver) |selection| {
            if (depth >= 256 or selection.remaining.* == 0) return error.EvidenceLimit;
            selection.remaining.* -= 1;
        }
        var height: u16 = 1;
        const result = try self.projectRowBody(source, row, mappings, rows, depth, budget, retained, memo, &height, resolver);
        if (memo != null) if (parent_height) |parent| {
            parent.* = @max(parent.*, height + 1);
        };
        return result;
    }
    fn projectNodeDepth(self: *Store, source: anytype, ty: types.Id, mappings: []const Mapping, rows: []const RowMapping, depth: usize, budget: *usize, comptime retained: bool, memo: ?*projections.Cache, height: *u16, resolver: ?ProjectionResolver) Error!Id {
        for (mappings) |mapping| if (mapping.variable == ty) {
            if (mapping.evidence == 0 or mapping.evidence >= self.nodes.items.len) return error.TypeMismatch;
            const leaf = self.node(mapping.evidence);
            if (leaf.tag == .erased_proof and source.node(ty).tag != .erased_proof) return error.TypeMismatch;
            if (leaf.tag == .bound) {
                var scope = self.projection_owners.items.len;
                while (scope != 0) {
                    scope -= 1;
                    for (self.projection_owners.items[scope]) |binder| if (binder == ty) {
                        const levels = self.projection_owners.items.len - 1 - scope;
                        if (levels >= 128 or leaf.c > 127 - levels) return error.EvidenceLimit;
                        return self.internWithEffects(.bound, leaf.a, leaf.b, leaf.c + @as(u32, @intCast(levels)), &.{});
                    };
                }
            }
            return mapping.evidence;
        };
        const n = source.node(ty);
        switch (n.tag) {
            .usage => {
                var region: Id = 0;
                if (n.c != 0) region = try self.projectDepth(source, n.c, mappings, rows, depth + 1, budget, retained, memo, height, resolver);
                return self.internWithEffects(.usage, try self.projectDepth(source, n.a, mappings, rows, depth + 1, budget, retained, memo, height, resolver), n.b, region, &.{});
            },
            .forall, .existential => {
                if (n.tag == .forall) {
                    var complete = true;
                    for (source.list(.{ .start = n.b, .len = n.c })) |binder| {
                        var found = false;
                        for (mappings) |mapping| if (mapping.variable == binder) {
                            found = true;
                            break;
                        };
                        complete = complete and found;
                    }
                    if (complete and source.quantifierGoals(ty).len == 0) return self.projectDepth(source, n.a, mappings, rows, depth + 1, budget, retained, memo, height, resolver);
                }
                if (depth >= 128 or n.c == 0 or n.c > 128) return error.EvidenceLimit;
                var owned: std.ArrayList(Mapping) = .empty;
                defer owned.deinit(self.allocator);
                // Local binder mappings precede inherited mappings: lexical
                // quantified slots never inherit a caller's concrete witness.
                for (source.list(.{ .start = n.b, .len = n.c }), 0..) |binder, ordinal| {
                    const leaf = source.node(binder);
                    if (leaf.tag != .bound or leaf.a != ordinal or leaf.b > 2 or leaf.c != 0) return error.UnresolvedType;
                    try owned.append(self.allocator, .{ .variable = binder, .evidence = try self.intern(.bound, @intCast(ordinal), leaf.b, &.{}) });
                }
                try owned.appendSlice(self.allocator, mappings);
                try self.projection_owners.append(self.allocator, source.list(.{ .start = n.b, .len = n.c }));
                defer _ = self.projection_owners.pop();
                try self.projection_quantifiers.append(self.allocator, ty);
                defer _ = self.projection_quantifiers.pop();
                var body_budget: usize = @min(budget.*, 4096);
                const available = body_budget;
                defer budget.* -= available - body_budget;
                const body = try self.projectDepth(source, n.a, owned.items, rows, depth + 1, &body_budget, false, null, height, resolver);
                var tag: Tag = .existential;
                if (n.tag == .forall) tag = .forall;
                var binders: [128]Id = undefined;
                for (owned.items[0..n.c], binders[0..n.c]) |mapping, *binder| binder.* = mapping.evidence;
                var goals: std.ArrayList(Goal) = .empty;
                defer goals.deinit(self.allocator);
                for (source.quantifierGoals(ty)) |goal| {
                    if (body_budget == 0) return error.EvidenceLimit;
                    body_budget -= 1;
                    var value: Goal = .{ .ty = 0, .kind = goal.kind, .name = goal.name, .operator = goal.operator, .identity = goal.identity, .explicit = goal.explicit };
                    inline for (.{ "ty", "other", "result", "signature" }) |field| {
                        const endpoint = @field(goal, field);
                        if (endpoint != 0) @field(value, field) = try self.projectDepth(source, endpoint, owned.items, rows, depth + 1, &body_budget, false, null, height, resolver);
                    }
                    try goals.append(self.allocator, value);
                }
                return self.internQuantifiedWithGoals(tag, body, binders[0..n.c], goals.items);
            },
            .scoped => {
                const descriptor = try self.projectDepth(source, n.a, mappings, rows, depth + 1, budget, retained, memo, height, resolver);
                var instance = types.selectionAtom(source, .{ .unit = n.b, .decl = n.c });
                if (instance.unit == 0) {
                    const owner = self.node(try self.projectDepth(source, n.c, mappings, rows, depth + 1, budget, retained, memo, height, resolver));
                    if (owner.tag != .scoped) return error.UnresolvedType;
                    instance = .{ .unit = owner.b, .decl = owner.c };
                }
                if (instance.unit == 0 or instance.decl == 0) return error.UnresolvedType;
                return self.internWithEffects(.scoped, descriptor, instance.unit, instance.decl, &.{});
            },
            .instance_version, .bound, .rigid, .instance_selection => return error.UnresolvedType,
            .erased_proof => return self.intern(.erased_proof, 0, 0, &.{}),
            .unit => return types.unit,
            .boolean => return types.boolean,
            .u32 => return types.u32_type,
            .f32 => return types.f32_type,
            .never => return types.never,
            .variable, .absent => return error.UnresolvedType,
            .projection => {
                const input = source.nominalArguments(n);
                const arguments = try self.allocator.alloc(Id, input.len);
                defer self.allocator.free(arguments);
                for (input, arguments) |root, *argument| argument.* = try self.projectDepth(source, root, mappings, rows, depth + 1, budget, retained, memo, height, resolver);
                var owner_index = self.projection_quantifiers.items.len;
                while (owner_index != 0) {
                    owner_index -= 1;
                    const owner = self.projection_quantifiers.items[owner_index];
                    for (source.quantifierGoals(owner), 0..) |goal, ordinal| {
                        if (budget.* == 0) return error.EvidenceLimit;
                        budget.* -= 1;
                        if (goal.kind != .contract or goal.identity.unit != n.a or goal.identity.decl != n.b) continue;
                        const tuple = source.node(goal.ty);
                        if (tuple.tag != .product or tuple.b != input.len) continue;
                        var matches = true;
                        for (source.list(.{ .start = tuple.a, .len = tuple.b }), arguments) |expected, actual| {
                            const projected = try self.projectDepth(source, expected, mappings, rows, depth + 1, budget, retained, memo, height, resolver);
                            if (projected != actual) matches = false;
                        }
                        if (matches) return self.internProjection(.{ .unit = n.a, .decl = n.b }, source.projectionMember(n), arguments, @intCast(self.projection_quantifiers.items.len - 1 - owner_index), @intCast(ordinal));
                    }
                }
                const selection = resolver orelse return error.UnresolvedType;
                return selection.resolve(selection.context, .{ .unit = n.a, .decl = n.b }, source.projectionMember(n), arguments);
            },
            .array => return self.intern(.array, try self.projectDepth(source, n.a, mappings, rows, depth + 1, budget, retained, memo, height, resolver), 0, &.{}),
            .list => return self.intern(.list, try self.projectDepth(source, n.a, mappings, rows, depth + 1, budget, retained, memo, height, resolver), 0, &.{}),
            .cursor => return self.intern(.cursor, try self.projectDepth(source, n.a, mappings, rows, depth + 1, budget, retained, memo, height, resolver), 0, &.{}),
            .demand => return self.internWithEffects(.demand, try self.projectDepth(source, n.a, mappings, rows, depth + 1, budget, retained, memo, height, resolver), 0, try self.projectRowDepth(source, n.c, mappings, rows, depth + 1, budget, retained, memo, height, resolver), &.{}),
            .resolver => return self.intern(.resolver, try self.projectDepth(source, n.a, mappings, rows, depth + 1, budget, retained, memo, height, resolver), 0, &.{}),
            .provider => return self.internWithEffects(.provider, try self.projectDepth(source, n.a, mappings, rows, depth + 1, budget, retained, memo, height, resolver), 0, try self.projectRowDepth(source, n.c, mappings, rows, depth + 1, budget, retained, memo, height, resolver), &.{}),
            .state_provider => return self.internStateProvider(try self.projectDepth(source, n.a, mappings, rows, depth + 1, budget, retained, memo, height, resolver), try self.projectDepth(source, n.b, mappings, rows, depth + 1, budget, retained, memo, height, resolver), try self.projectDepth(source, n.c, mappings, rows, depth + 1, budget, retained, memo, height, resolver)),
            .type_constructor => return self.intern(.type_constructor, n.a, n.b, &.{}),
            .function => return self.internWithEffects(.function, try self.projectDepth(source, n.a, mappings, rows, depth + 1, budget, retained, memo, height, resolver), try self.projectDepth(source, n.b, mappings, rows, depth + 1, budget, retained, memo, height, resolver), try self.projectRowDepth(source, n.c, mappings, rows, depth + 1, budget, retained, memo, height, resolver), &.{}),
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
                        try values.append(allocator, try self.projectDepth(source, field.ty, mappings, rows, depth + 1, budget, retained, memo, height, resolver));
                    }
                } else {
                    const children_ = if (n.tag == .nominal) source.nominalArguments(n) else source.list(.{ .start = n.a, .len = n.b });
                    for (children_) |child| try values.append(allocator, try self.projectDepth(source, child, mappings, rows, depth + 1, budget, retained, memo, height, resolver));
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
    fn projectRowBody(self: *Store, source: anytype, row: types.Effects.Id, mappings: []const Mapping, rows: []const RowMapping, depth: usize, budget: *usize, comptime retained: bool, memo: ?*projections.Cache, height: *u16, resolver: ?ProjectionResolver) Error!Effects.Id {
        const tail = source.row(row).tail;
        var suffix: Effects.Id = 0;
        var formal: Id = 0;
        switch (tail) {
            .closed => {},
            .formal => |leaf| {
                const key = types.formalRowKey(leaf) catch return error.UnresolvedType;
                var replaced = false;
                for (rows) |mapping| if (mapping.variable == key) {
                    if (mapping.evidence >= self.effects.rows.items.len) return error.TypeMismatch;
                    suffix = mapping.evidence;
                    replaced = true;
                    break;
                };
                if (!replaced) {
                    formal = try self.projectDepth(source, leaf, mappings, rows, depth + 1, budget, retained, memo, height, resolver);
                    const projected = self.node(formal);
                    if (projected.tag != .bound or projected.b != 1) return error.TypeMismatch;
                }
            },
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
            if (resolver) |selection| {
                if (selection.remaining.* == 0) return error.EvidenceLimit;
                selection.remaining.* -= 1;
            }
            // Owned projection memoizes each solver label like a subtree: a
            // label and its argument nodes are immutable until the cache's
            // clocks move. A hit charges the arguments' exact visits and
            // fails at the depth where re-projecting them would.
            if (retained) if (memo.?.labels.get(label)) |answer| {
                if (depth + answer.height > 1024 or budget.* < answer.visits) return error.EvidenceLimit;
                budget.* -= answer.visits;
                height.* = @max(height.*, answer.height);
                try labels.append(allocator, answer.value);
                continue;
            };
            const instance = types.selectionAtom(source, source.operation(label).instance);
            if (instance.unit == 0 and instance.decl != 0) return error.UnresolvedType;
            arguments.clearRetainingCapacity();
            const before = budget.*;
            var label_height: u16 = 0;
            for (source.operationArguments(label)) |argument| try arguments.append(allocator, try self.projectDepth(source, argument, mappings, rows, depth + 1, budget, retained, memo, if (retained) &label_height else height, resolver));
            const projected = try self.effects.internOperationInstance(source.operation(label).identity, arguments.items, instance);
            if (retained) {
                height.* = @max(height.*, label_height);
                try memo.?.labels.put(memo.?.allocator orelse self.allocator, label, .{ .value = projected, .visits = @intCast(before - budget.*), .height = label_height });
            }
            try labels.append(allocator, projected);
        }
        try labels.appendSlice(allocator, self.effects.view().rowLabels(suffix));
        if (suffix != 0) formal = self.effects.rows.items[suffix].formal;
        return self.effects.internRowWithFormal(labels.items, formal);
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
        const accepted = try self.matchDepth(source, pattern, actual, mappings, rows, 0, &budget, null, null);
        if (!accepted) {
            mappings.shrinkRetainingCapacity(start);
            if (rows) |values| values.shrinkRetainingCapacity(row_start);
        }
        return accepted;
    }
    const MatchMemo = std.AutoHashMapUnmanaged(u64, void);
    pub fn matchWithRowsBudget(self: *Store, source: anytype, pattern: types.Id, actual: Id, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), budget: *usize) Error!bool {
        var memo: MatchMemo = .empty;
        defer memo.deinit(self.allocator);
        const frontier = mappings.items.len;
        const row_frontier = rows.items.len;
        errdefer {
            mappings.shrinkRetainingCapacity(frontier);
            rows.shrinkRetainingCapacity(row_frontier);
        }
        const accepted = try self.matchDepth(source, pattern, actual, mappings, rows, 0, budget, null, &memo);
        if (!accepted) {
            mappings.shrinkRetainingCapacity(frontier);
            rows.shrinkRetainingCapacity(row_frontier);
        }
        return accepted;
    }
    /// A method reference may carry its caller's larger ambient row. Its
    /// ordinary argument types remain exact implementation-head evidence.
    pub fn matchTemplate(self: *Store, source: anytype, pattern: types.Id, actual: Id, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), resolver: ProjectionResolver) Error!bool {
        return self.matchSignature(source, pattern, actual, mappings, rows, resolver, false);
    }
    pub fn matchLegacySignature(self: *Store, source: anytype, pattern: types.Id, actual: Id, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), resolver: ProjectionResolver) Error!bool {
        return self.matchSignature(source, pattern, actual, mappings, rows, resolver, true);
    }
    fn matchSignature(self: *Store, source: anytype, pattern: types.Id, actual: Id, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), resolver: ProjectionResolver, infer_rows: bool) Error!bool {
        var memo: MatchMemo = .empty;
        defer memo.deinit(self.allocator);
        const frontier = mappings.items.len;
        const row_frontier = rows.items.len;
        var accepted = false;
        defer if (!accepted) {
            mappings.shrinkRetainingCapacity(frontier);
            rows.shrinkRetainingCapacity(row_frontier);
        };
        var expected = pattern;
        var supplied = actual;
        var depth: usize = 0;
        while (source.node(expected).tag == .forall) {
            if (depth >= 128) return error.EvidenceLimit;
            depth += 1;
            expected = source.node(expected).a;
        }
        while (source.node(expected).tag == .function) {
            if (depth >= 256 or resolver.remaining.* == 0) return error.EvidenceLimit;
            resolver.remaining.* -= 1;
            const arrow = source.node(expected);
            const concrete = self.node(supplied);
            if (concrete.tag != .function) return false;
            if (!try self.matchDepth(source, arrow.a, concrete.a, mappings, rows, depth + 1, resolver.remaining, resolver, &memo)) return false;
            const required_row = self.projectRowDepth(source, arrow.c, mappings.items, rows.items, depth + 1, resolver.remaining, false, null, null, resolver) catch |err| switch (err) {
                error.UnresolvedType => fallback: {
                    if (!infer_rows) return false;
                    if (!try self.matchRowDepth(source, arrow.c, concrete.c, mappings, rows, depth + 1, resolver.remaining, resolver, &memo)) return false;
                    break :fallback try self.projectRowDepth(source, arrow.c, mappings.items, rows.items, depth + 1, resolver.remaining, false, null, null, resolver);
                },
                else => return err,
            };
            const required = try self.allocator.dupe(Effects.Label, self.effects.view().rowLabels(required_row));
            defer self.allocator.free(required);
            for (required) |label| {
                if (resolver.remaining.* == 0) return error.EvidenceLimit;
                resolver.remaining.* -= 1;
                if (std.mem.findScalar(Effects.Label, self.effects.view().rowLabels(concrete.c), label) == null) return false;
            }
            expected = arrow.b;
            supplied = concrete.b;
            depth += 1;
        }
        accepted = try self.matchDepth(source, expected, supplied, mappings, rows, depth + 1, resolver.remaining, resolver, &memo);
        return accepted;
    }
    /// Legacy invocation facts infer only their own invocation rows. The
    /// selected signature is never opened against an executable ambient.
    pub fn matchPrerequisite(self: *Store, source: anytype, pattern: types.Id, operands: [4]Id, arity: usize, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), resolver: ProjectionResolver) Error!?Id {
        var memo: MatchMemo = .empty;
        defer memo.deinit(self.allocator);
        var labels: std.ArrayList(Effects.Label) = .empty;
        defer labels.deinit(self.allocator);
        const frontier = mappings.items.len;
        const row_frontier = rows.items.len;
        var accepted = false;
        defer if (!accepted) {
            mappings.shrinkRetainingCapacity(frontier);
            rows.shrinkRetainingCapacity(row_frontier);
        };
        var required = pattern;
        var requested: Effects.Id = 0;
        if (operands[3] != 0) {
            const carrier = self.node(operands[3]);
            if (carrier.tag != .function) return null;
            requested = carrier.c;
        }
        for (0..arity) |stage| {
            if (resolver.remaining.* == 0) return error.EvidenceLimit;
            resolver.remaining.* -= 1;
            const arrow = source.node(required);
            if (arrow.tag != .function) return null;
            if (!try self.matchDepth(source, arrow.a, operands[stage], mappings, rows, 0, resolver.remaining, resolver, &memo)) return null;
            const own_row = self.projectRowDepth(source, arrow.c, mappings.items, rows.items, 0, resolver.remaining, false, null, null, resolver) catch |err| switch (err) {
                error.UnresolvedType => fallback: {
                    if (operands[3] == 0) return null;
                    if (!try self.matchRowDepth(source, arrow.c, requested, mappings, rows, 0, resolver.remaining, resolver, &memo)) return null;
                    break :fallback try self.projectRowDepth(source, arrow.c, mappings.items, rows.items, 0, resolver.remaining, false, null, null, resolver);
                },
                else => return err,
            };
            const own_labels = self.effects.view().rowLabels(own_row);
            for (own_labels, 0..) |label, index| {
                if (resolver.remaining.* == 0) return error.EvidenceLimit;
                resolver.remaining.* -= 1;
                var count: usize = 0;
                for (own_labels[0 .. index + 1]) |earlier| {
                    if (resolver.remaining.* == 0) return error.EvidenceLimit;
                    resolver.remaining.* -= 1;
                    if (earlier == label) count += 1;
                }
                if (operands[3] != 0) {
                    var available: usize = 0;
                    for (self.effects.view().rowLabels(requested)) |actual| {
                        if (resolver.remaining.* == 0) return error.EvidenceLimit;
                        resolver.remaining.* -= 1;
                        if (actual == label) available += 1;
                    }
                    if (count > available) return error.TypeMismatch;
                }
                var present: usize = 0;
                for (labels.items) |actual| {
                    if (resolver.remaining.* == 0) return error.EvidenceLimit;
                    resolver.remaining.* -= 1;
                    if (actual == label) present += 1;
                }
                if (count > present) try labels.append(self.allocator, label);
            }
            required = arrow.b;
        }
        if (!try self.matchDepth(source, required, operands[2], mappings, rows, 0, resolver.remaining, resolver, &memo)) return error.TypeMismatch;
        accepted = true;
        if (operands[3] != 0) return operands[3];
        const own = try self.effects.internRow(labels.items);
        return try self.internWithEffects(.function, types.unit, types.unit, own, &.{});
    }
    pub fn matchSelected(self: *Store, source: anytype, pattern: types.Id, actual: Id, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), resolver: ProjectionResolver) Error!bool {
        var memo: MatchMemo = .empty;
        defer memo.deinit(self.allocator);
        const frontier = mappings.items.len;
        const row_frontier = rows.items.len;
        errdefer {
            mappings.shrinkRetainingCapacity(frontier);
            rows.shrinkRetainingCapacity(row_frontier);
        }
        const accepted = try self.matchDepth(source, pattern, actual, mappings, rows, 0, resolver.remaining, resolver, &memo);
        if (!accepted) {
            mappings.shrinkRetainingCapacity(frontier);
            rows.shrinkRetainingCapacity(row_frontier);
        }
        return accepted;
    }
    fn matchDepth(self: *Store, source: anytype, pattern: types.Id, actual: Id, mappings: *std.ArrayList(Mapping), rows: ?*std.ArrayList(RowMapping), depth: usize, budget: *usize, resolver: ?ProjectionResolver, memo: ?*MatchMemo) Error!bool {
        if (depth >= 1024 or (memo != null and depth >= 256) or budget.* == 0) return error.EvidenceLimit;
        budget.* -= 1;
        if (actual == 0 or actual >= self.nodes.items.len) return error.UnresolvedType;
        const pair = (@as(u64, pattern) << 32) | actual;
        if (memo) |seen| if (seen.contains(pair)) return true;
        const n = source.node(pattern);
        if (n.tag == .projection) {
            const selected = resolver orelse return false;
            var mapped_rows: []const RowMapping = &.{};
            if (rows) |values| mapped_rows = values.items;
            const normalized = self.projectSelected(source, pattern, mappings.items, mapped_rows, selected) catch |err| switch (err) {
                error.UnresolvedType => return false,
                else => return err,
            };
            if (normalized != actual) return false;
            if (memo) |seen| try seen.put(self.allocator, pair, {});
            return true;
        }
        const concrete = self.node(actual);
        if (n.tag == .existential or (n.tag == .forall and concrete.tag == .forall)) {
            var tag: Tag = .existential;
            if (n.tag == .forall) tag = .forall;
            if (concrete.tag != tag or n.c != concrete.b) return false;
            var row_values: []const RowMapping = &.{};
            if (rows) |values| row_values = values.items;
            const expected = self.projectWithRows(source, pattern, mappings.items, row_values) catch |err| switch (err) {
                error.UnresolvedType => return false,
                else => return err,
            };
            return expected == actual;
        }
        if (n.tag == .never or concrete.tag == .never) return true;
        if (n.tag == .forall) return self.matchDepth(source, n.a, actual, mappings, rows, depth + 1, budget, resolver, memo);
        if (n.tag == .variable or (n.tag == .bound and n.b == 0)) {
            if (concrete.tag == .erased_proof) return false;
            for (mappings.items) |mapping| if (mapping.variable == pattern) return mapping.evidence == actual;
            try mappings.append(self.allocator, .{ .variable = pattern, .evidence = actual });
            return true;
        }
        const same = switch (n.tag) {
            .scoped => concrete.tag == .scoped and (n.b == 0 or (n.b == concrete.b and n.c == concrete.c)),
            .forall, .existential, .instance_version, .bound, .rigid, .instance_selection => false,
            .usage => concrete.tag == .usage and n.b == concrete.b,
            .erased_proof => concrete.tag == .erased_proof,
            .absent, .projection => false,
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
        if ((n.tag == .demand or n.tag == .provider) and !try self.matchRowDepth(source, n.c, concrete.c, mappings, rows, depth + 1, budget, resolver, memo)) return false;
        switch (n.tag) {
            .scoped => {
                if (!try self.matchDepth(source, n.a, concrete.a, mappings, rows, depth + 1, budget, resolver, memo)) return false;
                if (n.b == 0) {
                    const owner = source.head(n.c, 0);
                    if (source.node(owner).tag == .variable) {
                        var known = false;
                        for (mappings.items) |mapping| if (mapping.variable == owner) {
                            const prior = self.node(mapping.evidence);
                            if (prior.tag != .scoped or prior.b != concrete.b or prior.c != concrete.c) return false;
                            known = true;
                            break;
                        };
                        if (!known) try mappings.append(self.allocator, .{ .variable = owner, .evidence = actual });
                    } else {
                        const atom = types.selectionAtom(source, .{ .unit = 0, .decl = owner });
                        if (atom.unit != concrete.b or atom.decl != concrete.c) return false;
                    }
                }
            },
            .usage, .array, .list, .cursor, .demand, .resolver, .provider => {
                if (!try self.matchDepth(source, n.a, concrete.a, mappings, rows, depth + 1, budget, resolver, memo)) return false;
            },
            .state_provider => {
                if (!try self.matchDepth(source, n.a, concrete.a, mappings, rows, depth + 1, budget, resolver, memo)) return false;
                if (!try self.matchDepth(source, n.b, concrete.b, mappings, rows, depth + 1, budget, resolver, memo)) return false;
                if (!try self.matchDepth(source, n.c, concrete.c, mappings, rows, depth + 1, budget, resolver, memo)) return false;
            },
            .function => {
                if (!try self.matchDepth(source, n.a, concrete.a, mappings, rows, depth + 1, budget, resolver, memo)) return false;
                if (!try self.matchRowDepth(source, n.c, concrete.c, mappings, rows, depth + 1, budget, resolver, memo)) return false;
                if (!try self.matchDepth(source, n.b, concrete.b, mappings, rows, depth + 1, budget, resolver, memo)) return false;
            },
            .product, .nominal => {
                const expected = if (n.tag == .nominal) source.nominalArguments(n) else source.list(.{ .start = n.a, .len = n.b });
                var actuals = self.children(actual);
                if (resolver != null) actuals = try self.allocator.dupe(Id, actuals);
                defer if (resolver != null) self.allocator.free(actuals);
                if (expected.len != actuals.len) return false;
                for (expected, actuals) |child, child_actual| if (!try self.matchDepth(source, child, child_actual, mappings, rows, depth + 1, budget, resolver, memo)) return false;
            },
            .record => {
                var fields = self.children(actual);
                if (resolver != null) fields = try self.allocator.dupe(Id, fields);
                defer if (resolver != null) self.allocator.free(fields);
                if (fields.len != @as(usize, n.b) * 2) return false;
                for (0..n.b) |index| {
                    const field = source.recordField(n, index);
                    var found = false;
                    var i: usize = 0;
                    while (i < fields.len) : (i += 2) if (fields[i] == field.name) {
                        if (!try self.matchDepth(source, field.ty, fields[i + 1], mappings, rows, depth + 1, budget, resolver, memo)) return false;
                        found = true;
                        break;
                    };
                    if (!found) return false;
                }
            },
            else => {},
        }
        if (memo) |seen| try seen.put(self.allocator, pair, {});
        return true;
    }
    fn matchRowDepth(self: *Store, source: anytype, pattern: types.Effects.Id, actual: Effects.Id, mappings: *std.ArrayList(Mapping), rows: ?*std.ArrayList(RowMapping), depth: usize, budget: *usize, resolver: ?ProjectionResolver, memo: ?*MatchMemo) Error!bool {
        const tail = source.row(pattern).tail;
        if (tail == .parameter or (tail == .variable and rows == null)) return error.UnresolvedType;
        if (tail == .formal) return actual == try self.projectRowDepth(source, pattern, mappings.items, if (rows) |values| values.items else &.{}, depth + 1, budget, false, null, null, resolver);
        const actual_formal = self.effects.rows.items[actual].formal;
        if (tail == .closed and actual_formal != 0) return false;
        const expected = source.rowLabels(pattern);
        const actuals = try self.allocator.dupe(Effects.Label, self.effects.view().rowLabels(actual));
        defer self.allocator.free(actuals);
        if (expected.len > actuals.len or (tail == .closed and expected.len != actuals.len)) return false;
        const used = try self.allocator.alloc(bool, actuals.len);
        defer self.allocator.free(used);
        @memset(used, false);
        return self.matchOperations(source, expected, actuals, used, tail, actual_formal, 0, mappings, rows, depth, budget, resolver, memo);
    }
    fn matchOperations(self: *Store, source: anytype, expected: []const types.Effects.Label, actuals: []const Effects.Label, used: []bool, tail: types.Effects.Tail, actual_formal: Id, index: usize, mappings: *std.ArrayList(Mapping), rows: ?*std.ArrayList(RowMapping), depth: usize, budget: *usize, resolver: ?ProjectionResolver, memo: ?*MatchMemo) Error!bool {
        if (depth >= 1024 or (memo != null and depth >= 256) or budget.* == 0) return error.EvidenceLimit;
        budget.* -= 1;
        if (index == expected.len) {
            if (tail == .closed) return true;
            var remaining: std.ArrayList(Effects.Label) = .empty;
            defer remaining.deinit(self.allocator);
            for (actuals, used) |label, consumed| if (!consumed) try remaining.append(self.allocator, label);
            const suffix = try self.effects.internRowWithFormal(remaining.items, actual_formal);
            for (rows.?.items) |mapping| if (mapping.variable == tail.variable) return mapping.evidence == suffix;
            try rows.?.append(self.allocator, .{ .variable = tail.variable, .evidence = suffix });
            return true;
        }
        const operation = source.operation(expected[index]);
        const arguments = source.operationArguments(expected[index]);
        for (actuals, 0..) |label, i| {
            if (memo != null) {
                if (budget.* == 0) return error.EvidenceLimit;
                budget.* -= 1;
            }
            if (used[i]) continue;
            const concrete = self.effects.view().operation(label);
            if (!std.meta.eql(types.selectionAtom(source, operation.instance), concrete.instance) or operation.identity.unit != concrete.identity.unit or operation.identity.decl != concrete.identity.decl) continue;
            var actual_arguments = self.effects.view().operationArguments(label);
            if (resolver != null) actual_arguments = try self.allocator.dupe(Id, actual_arguments);
            defer if (resolver != null) self.allocator.free(actual_arguments);
            if (arguments.len != actual_arguments.len) continue;
            const frontier = mappings.items.len;
            const row_frontier = if (rows) |values| values.items.len else 0;
            var same = true;
            for (arguments, actual_arguments) |argument, concrete_argument| {
                if (!try self.matchDepth(source, argument, concrete_argument, mappings, rows, depth + 1, budget, resolver, memo)) {
                    same = false;
                    break;
                }
            }
            if (same) {
                used[i] = true;
                if (try self.matchOperations(source, expected, actuals, used, tail, actual_formal, index + 1, mappings, rows, depth + 1, budget, resolver, memo)) return true;
                used[i] = false;
            }
            if (memo) |seen| seen.clearRetainingCapacity();
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, providerEvidenceScenario, .{});
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
test "interning fingerprints do not depend on how their stream is split into updates" {
    var words: [70]u32 = undefined;
    for (&words, 0..) |*word, index| word.* = @truncate(index *% 2654435761);
    const tag: Tag = .record;
    var split = std.hash.Wyhash.init(0);
    split.update(std.mem.asBytes(&tag));
    for (&words) |*word| split.update(std.mem.asBytes(word));
    const header = std.mem.toBytes(tag) ++ std.mem.toBytes(words[0]) ++ std.mem.toBytes(words[1]);
    var joined = std.hash.Wyhash.init(0);
    joined.update(&header);
    joined.update(std.mem.sliceAsBytes(words[2..]));
    try std.testing.expectEqual(split.final(), joined.final());
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, effectOwnershipScenario, .{});
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, rowSubstitutionScenario, .{});
}

test "unresolved capability instance terms cannot become closed row evidence" {
    const allocator = std.testing.allocator;
    var solver = try types.Store.init(allocator);
    defer solver.deinit();
    var evidence = try Store.init(allocator);
    defer evidence.deinit();
    const capability = try solver.capabilityParameter(try solver.nominal(.{ .unit = 2, .decl = 7 }, &.{types.u32_type}));
    const label = try solver.internScopedOperation(.{ .unit = 2, .decl = 8 }, .{ .unit = 0, .decl = solver.node(capability).c }, &.{types.u32_type});
    const row = try solver.effects.row(&.{ label, label }, .closed);
    try std.testing.expectError(error.UnresolvedType, evidence.projectEffects(&solver, row, &.{}, &.{}));
    try solver.unify(capability, try solver.scoped(solver.node(capability).a, .{ .unit = 2, .decl = 40 }));
    const resolved = try solver.resolveEffects(row, 0);
    const closed = try evidence.projectEffects(&solver, resolved, &.{}, &.{});
    try std.testing.expectEqual(2, evidence.effects.view().rowLabels(closed).len);
    try std.testing.expectEqual(types.NominalIdentity{ .unit = 2, .decl = 40 }, evidence.effects.view().operation(evidence.effects.view().rowLabels(closed)[0]).instance);
}

fn quantifierOwnershipScenario(allocator: Allocator) !void {
    var semantic = try Store.init(allocator);
    defer semantic.deinit();
    var root: Id = 0;
    {
        var source = try types.Store.init(allocator);
        defer source.deinit();
        const outer = try source.boundType(0, 0);
        const region = try source.boundType(1, 2);
        const phantom_row = try source.boundType(2, 1);
        const inner = try source.boundType(0, 0);
        const loan = try source.usage(outer, .borrow, region);
        const result = try source.product(&.{ outer, loan });
        const nested = try source.quantified(.forall, try source.function(inner, result), &.{inner});
        const signature = try source.quantified(.forall, try source.function(outer, nested), &.{ outer, region, phantom_row });
        root = try semantic.project(&source, signature, &.{});
    }
    const owner = semantic.node(root);
    try std.testing.expectEqual(@as(u32, 3), owner.b);
    const binders = semantic.children(root);
    try std.testing.expectEqual(@as(u32, 0), semantic.node(binders[0]).b);
    try std.testing.expectEqual(@as(u32, 2), semantic.node(binders[1]).b);
    try std.testing.expectEqual(@as(u32, 1), semantic.node(binders[2]).b);
    const nested = semantic.node(semantic.node(owner.a).b);
    try std.testing.expectEqual(Tag.forall, nested.tag);
    const fields = semantic.children(semantic.node(nested.a).b);
    try std.testing.expectEqual(@as(u32, 1), semantic.node(fields[0]).c);
    const loan = semantic.node(fields[1]);
    try std.testing.expectEqual(@as(u32, 1), semantic.node(loan.c).c);
    try std.testing.expectEqual(@as(u32, 2), semantic.node(loan.c).b);
    try std.testing.expect(@import("../reuse/portable_query.zig").validEvidence(semantic.view()));
    try std.testing.expect(@import("../reuse/portable_query.zig").closedEvidence(semantic.view(), root));
    try std.testing.expect(!@import("../reuse/portable_query.zig").closedEvidence(semantic.view(), semantic.node(owner.a).b));
    var snapshot = try semantic.copyOwned(allocator);
    defer snapshot.deinit(allocator);
    var destination = try Store.init(allocator);
    defer destination.deinit();
    _ = try destination.intern(.array, types.f32_type, 0, &.{});
    var transfer: @import("semantic_evidence_import.zig").Importer = .{ .allocator = allocator, .source = snapshot.view(), .destination = &destination, .max_depth = 128 };
    defer transfer.deinit();
    const copied = try transfer.ty(root, 0);
    try std.testing.expect(@import("../reuse/portable_query.zig").validEvidence(destination.view()));
    var solver = try types.Store.init(allocator);
    defer solver.deinit();
    var importer: @import("closed_evidence_import.zig").Importer = .{ .allocator = allocator, .source = destination.view(), .destination = &solver };
    defer importer.deinit();
    const imported = try importer.ty(copied, 0);
    try std.testing.expectEqual(root, try semantic.project(&solver, imported, &.{}));
    const saved = snapshot.nodes[loan.c];
    snapshot.nodes[loan.c].c += 1;
    try std.testing.expect(!@import("../reuse/portable_query.zig").validEvidence(snapshot.view()));
    try std.testing.expect(!@import("../reuse/portable_query.zig").closedEvidence(snapshot.view(), root));
    snapshot.nodes[loan.c] = saved;
    snapshot.nodes[binders[1]].b = 0;
    try std.testing.expect(!@import("../reuse/portable_query.zig").validEvidence(snapshot.view()));
}

test "canonical quantifiers preserve phantom sorts nested owners and formal loans through every allocation failure" {
    try quantifierOwnershipScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, quantifierOwnershipScenario, .{});
}

fn formalRowRecipe(allocator: Allocator) !void {
    var source = try types.Store.init(allocator);
    defer source.deinit();
    const binder = try source.boundType(0, 1);
    const callback = try source.functionWithEffects(types.u32_type, types.u32_type, try source.rowType(binder));
    const root = try source.quantified(.forall, try source.function(callback, callback), &.{binder});
    var evidence = try Store.init(allocator);
    defer evidence.deinit();
    const recipe = try evidence.project(&source, root, &.{});
    try std.testing.expect(@import("../reuse/portable_query.zig").closedEvidence(evidence.view(), recipe));
    try @import("../check/package_evidence.zig").validate(evidence.view());
    const body = evidence.node(recipe).a;
    const row = evidence.node(evidence.node(body).a).c;
    const formal = evidence.effects.rows.items[row].formal;
    try std.testing.expectEqual(Tag.bound, evidence.node(formal).tag);
    try std.testing.expectEqual(@as(u32, 1), evidence.node(formal).b);
    var mappings: std.ArrayList(Mapping) = .empty;
    defer mappings.deinit(allocator);
    try std.testing.expect(!try evidence.match(&source, try source.function(types.u32_type, types.u32_type), evidence.node(body).a, &mappings));
    try std.testing.expect(row != try evidence.effects.internRow(&.{}));
    var work: usize = 65_536;
    try std.testing.expectError(error.TypeMismatch, evidence.view().closed(body, 0, &work));
    var snapshot = try evidence.copyOwned(allocator);
    defer snapshot.deinit(allocator);
    var destination = try Store.init(allocator);
    defer destination.deinit();
    _ = try destination.intern(.product, 0, 0, &.{ types.u32_type, types.f32_type });
    var copy: @import("semantic_evidence_import.zig").Importer = .{ .allocator = allocator, .source = snapshot.view(), .destination = &destination, .max_depth = 128 };
    defer copy.deinit();
    const transferred = try copy.ty(recipe, 0);
    var solver = try types.Store.init(allocator);
    defer solver.deinit();
    var imported: @import("closed_evidence_import.zig").Importer = .{ .allocator = allocator, .source = destination.view(), .destination = &solver };
    defer imported.deinit();
    const cloned = try imported.ty(transferred, 0);
    const owned = solver.node(cloned);
    const owned_binder = solver.list(.{ .start = owned.b, .len = owned.c })[0];
    const cloned_row = solver.node(solver.node(owned.a).a).c;
    try std.testing.expectEqual(owned_binder, solver.row(cloned_row).tail.formal);
    try std.testing.expectEqual(transferred, try destination.project(&solver, cloned, &.{}));
    // The same row descriptor interpreted under a different sorted owner
    // cannot borrow a type binder or a forged outer scope.
    snapshot.nodes[formal].b = 0;
    try std.testing.expect(!@import("../reuse/portable_query.zig").closedEvidence(snapshot.view(), recipe));
    snapshot.nodes[formal].b = 1;
    snapshot.nodes[formal].c = 1;
    try std.testing.expect(!@import("../reuse/portable_query.zig").closedEvidence(snapshot.view(), recipe));
}

test "formal row evidence retains sorted lexical ownership across snapshots and independent imports through OOM" {
    try formalRowRecipe(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, formalRowRecipe, .{});
}

fn canonicalGoalsScenario(allocator: Allocator) !void {
    var source = try types.Store.init(allocator);
    defer source.deinit();
    const binder = try source.boundType(0, 0);
    const body_ = try source.sequence(.array, binder);
    const contract: types.NominalIdentity = .{ .unit = 17, .decl = 31 };
    const goal_ty = try source.nominal(contract, &.{body_});
    const goal: types.Obligation = .{ .ty = goal_ty, .kind = .contract, .source = 111, .identity = contract, .explicit = true };
    const row_binder = try source.boundType(1, 1);
    const callback = try source.functionWithEffects(binder, binder, try source.rowType(row_binder));
    const row_goal_ty = try source.product(&.{callback});
    const row_goal: types.Obligation = .{ .ty = row_goal_ty, .kind = .contract, .source = 222, .identity = contract, .explicit = true };
    const row_root = try source.quantifiedWithGoals(.forall, try source.function(types.unit, types.unit), &.{ binder, row_binder }, &.{row_goal});
    const root = try source.quantifiedWithGoals(.existential, body_, &.{binder}, &.{goal});
    var evidence = try Store.init(allocator);
    defer evidence.deinit();
    const row_actual = try evidence.project(&source, row_root, &.{});
    var row_budget: usize = 65_536;
    try evidence.view().closed(row_actual, 0, &row_budget);
    const actual = try evidence.project(&source, root, &.{});
    const bare = try evidence.intern(.existential, evidence.node(actual).a, 1, evidence.children(actual));
    try std.testing.expect(actual != bare);
    const values = evidence.view().quantifierGoals(actual);
    try std.testing.expectEqual(@as(usize, 1), values.len);
    try std.testing.expectEqual(contract, values[0].identity);
    const identity_copy = values[0];
    try std.testing.expectEqual(actual, try evidence.internQuantifiedWithGoals(.existential, evidence.node(actual).a, evidence.children(actual), &.{identity_copy}));
    var changed = identity_copy;
    changed.identity.decl += 1;
    try std.testing.expect(actual != try evidence.internQuantifiedWithGoals(.existential, evidence.node(actual).a, evidence.children(actual), &.{changed}));
    try std.testing.expect(@import("../reuse/portable_query.zig").validEvidence(evidence.view()));
    var snapshot = try evidence.copyOwned(allocator);
    defer snapshot.deinit(allocator);
    try std.testing.expect(@import("../reuse/portable_query.zig").validEvidence(snapshot.view()));
    var clone = try evidence.clone(allocator);
    defer clone.deinit();
    try std.testing.expectEqualDeep(snapshot.quantifier_goals, clone.quantifier_goals.items);
    try std.testing.expectEqualDeep(snapshot.quantifier_obligations, clone.quantifier_obligations.items);
    var target = try Store.init(allocator);
    defer target.deinit();
    _ = try target.intern(.array, types.f32_type, 0, &.{});
    var importer: @import("semantic_evidence_import.zig").Importer = .{ .allocator = allocator, .source = snapshot.view(), .destination = &target, .max_depth = 128 };
    defer importer.deinit();
    const copied = try importer.ty(actual, 0);
    try std.testing.expectEqual(contract, target.view().quantifierGoals(copied)[0].identity);
    try std.testing.expect(@import("../reuse/portable_query.zig").validEvidence(target.view()));
    var solver = try types.Store.init(allocator);
    defer solver.deinit();
    var closed: @import("closed_evidence_import.zig").Importer = .{ .allocator = allocator, .source = target.view(), .destination = &solver };
    defer closed.deinit();
    var row_closed: @import("closed_evidence_import.zig").Importer = .{ .allocator = allocator, .source = snapshot.view(), .destination = &solver };
    defer row_closed.deinit();
    const row_imported = try row_closed.ty(row_actual, 0);
    try std.testing.expectEqual(row_actual, try evidence.project(&solver, row_imported, &.{}));
    const imported = try closed.ty(copied, 0);
    try std.testing.expectEqual(@as(usize, 1), solver.quantifierGoals(imported).len);
    try std.testing.expectEqual(actual, try evidence.project(&solver, imported, &.{}));
    const ordinal = snapshot.quantifier_goals.len - 2;
    const stored = snapshot.quantifier_goals[ordinal];
    snapshot.quantifier_goals[ordinal].owner = types.unit;
    try std.testing.expect(!@import("../reuse/portable_query.zig").validEvidence(snapshot.view()));
    snapshot.quantifier_goals[ordinal] = stored;
    snapshot.quantifier_goals[ordinal].goals.start += 1;
    try std.testing.expect(!@import("../reuse/portable_query.zig").validEvidence(snapshot.view()));
    snapshot.quantifier_goals[ordinal] = stored;
    const original = snapshot.quantifier_obligations[0];
    snapshot.quantifier_obligations[0].ty = actual;
    try std.testing.expect(!@import("../reuse/portable_query.zig").validEvidence(snapshot.view()));
    snapshot.quantifier_obligations[0] = original;
    var tiny: usize = 1;
    try std.testing.expectError(error.EvidenceLimit, snapshot.view().closed(actual, 0, &tiny));
    try std.testing.expectEqual(@as(usize, 0), tiny);
}
test "canonical quantifier predicates retain exact goals across independent interning snapshot clone and solver imports" {
    try canonicalGoalsScenario(std.testing.allocator);
}
test "canonical quantifier predicates preserve every published owner through all allocation failures" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, canonicalGoalsScenario, .{});
}

fn associatedProjectionScenario(allocator: Allocator) !void {
    var source = try types.Store.init(allocator);
    defer source.deinit();
    const identity: types.NominalIdentity = .{ .unit = 1, .decl = 37 };
    const binder = try source.boundType(0, 0);
    const argument = try source.sequence(.array, binder);
    const projection_ = try source.projection(identity, 41, &.{argument});
    const goal: types.Obligation = .{ .kind = .contract, .identity = identity, .ty = try source.product(&.{argument}), .source = 0 };
    const inner_binder = try source.boundType(0, 0);
    const inner = try source.quantified(.forall, try source.function(inner_binder, projection_), &.{inner_binder});
    const root = try source.quantifiedWithGoals(.forall, try source.function(argument, inner), &.{binder}, &.{goal});
    var semantic = try Store.init(allocator);
    defer semantic.deinit();
    const actual = try semantic.project(&source, root, &.{});
    try std.testing.expect(@import("../reuse/portable_query.zig").validEvidence(semantic.view()));
    try std.testing.expect(@import("../reuse/portable_query.zig").closedEvidence(semantic.view(), actual));
    const inner_actual = semantic.node(semantic.node(actual).a).b;
    const associated = semantic.node(semantic.node(inner_actual).a).b;
    try std.testing.expectEqual(Tag.projection, semantic.node(associated).tag);
    try std.testing.expectEqualDeep(Projection{ .member = 41, .scope = 1, .goal = 0 }, semantic.view().projection(associated));
    var snapshot = try semantic.copyOwned(allocator);
    defer snapshot.deinit(allocator);
    var destination = try Store.init(allocator);
    defer destination.deinit();
    _ = try destination.intern(.array, types.f32_type, 0, &.{});
    var transfer: @import("semantic_evidence_import.zig").Importer = .{ .allocator = allocator, .source = snapshot.view(), .destination = &destination, .max_depth = 128 };
    defer transfer.deinit();
    const copied = try transfer.ty(actual, 0);
    try std.testing.expect(@import("../reuse/portable_query.zig").closedEvidence(destination.view(), copied));
    var solver = try types.Store.init(allocator);
    defer solver.deinit();
    var importer: @import("closed_evidence_import.zig").Importer = .{ .allocator = allocator, .source = destination.view(), .destination = &solver };
    defer importer.deinit();
    const imported = try importer.ty(copied, 0);
    try std.testing.expectEqual(copied, try destination.project(&solver, imported, &.{}));
    const node = snapshot.nodes[associated];
    const tail = node.c + 1 + snapshot.extra[node.c];
    snapshot.extra[tail + 1] = 0;
    try std.testing.expect(!@import("../reuse/portable_query.zig").closedEvidence(snapshot.view(), actual));
    snapshot.extra[tail + 1] = 1;
    snapshot.extra[tail + 2] = 1;
    try std.testing.expect(!@import("../reuse/portable_query.zig").closedEvidence(snapshot.view(), actual));
    snapshot.extra[tail + 2] = 0;
    snapshot.nodes[associated].b += 1;
    try std.testing.expect(!@import("../reuse/portable_query.zig").closedEvidence(snapshot.view(), actual));
    snapshot.nodes[associated] = node;
    try std.testing.expect(@import("../reuse/portable_query.zig").closedEvidence(snapshot.view(), actual));
    var exhausted: usize = 1;
    try std.testing.expectError(error.EvidenceLimit, snapshot.view().closed(actual, 0, &exhausted));
}
test "associated projection evidence preserves exact lexical goals through nested owners snapshots solver imports and complete OOM" {
    try associatedProjectionScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, associatedProjectionScenario, .{});
}
