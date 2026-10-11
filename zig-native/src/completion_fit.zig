//! Bounded, request-local fitting. Neither substitutions nor proof IDs escape.
const std = @import("std");
const T = @import("types.zig");
const graph = @import("principal_type_graph.zig");
const Allocator = std.mem.Allocator;

pub const Match = enum { exact, compatible, unknown, incompatible };
pub const Budget = struct {
    remaining: usize = 1_000_000,
    exhausted: bool = false,

    pub fn spend(self: *Budget, amount: usize) bool {
        if (amount > self.remaining) {
            self.exhausted = true;
            self.remaining = 0;
            return false;
        }
        self.remaining -= amount;
        return true;
    }
};

const Measure = struct {
    source: *const T.Store,
    quantified: T.List,
    closed_rows: T.List,
    budget: *Budget,
    visits: usize = 0,
    known: bool = true,

    fn ty(self: *Measure, original: T.Id, depth: usize) error{TypeLimit}!void {
        // Charge an upper bound for chronological head resolution before
        // reading it. Count expanded edges, not just unique graph nodes: a
        // tiny shared DAG must not conceal exponential fitting work.
        if (depth >= 32 or self.visits == 1024 or
            !self.budget.spend(1 + self.source.versions.items.len + self.source.effects.versions.items.len))
            return error.TypeLimit;
        self.visits += 1;
        const root = self.source.head(original, 0);
        const node = self.source.node(root);
        switch (node.tag) {
            .absent => self.known = false,
            .variable => if (!contains(self.source.list(self.quantified), root)) {
                self.known = false;
            },
            .function => {
                try self.ty(node.a, depth + 1);
                try self.ty(node.b, depth + 1);
                try self.row(node.c, depth + 1);
            },
            .array, .list, .cursor, .resolver => try self.ty(node.a, depth + 1),
            .demand, .provider => {
                try self.ty(node.a, depth + 1);
                try self.row(node.c, depth + 1);
            },
            .state_provider => {
                try self.ty(node.a, depth + 1);
                try self.ty(node.b, depth + 1);
                try self.ty(node.c, depth + 1);
            },
            .product => for (self.source.list(.{ .start = node.a, .len = node.b })) |child| try self.ty(child, depth + 1),
            .nominal => for (self.source.nominalArguments(node)) |child| try self.ty(child, depth + 1),
            .record => for (0..node.b) |index| try self.ty(self.source.recordField(node, index).ty, depth + 1),
            else => {},
        }
    }

    fn row(self: *Measure, id: T.Effects.Id, depth: usize) error{TypeLimit}!void {
        const row_ = self.source.row(id);
        if (row_.tail != .closed) {
            if (row_.tail != .variable or !contains(self.source.list(self.closed_rows), row_.tail.variable))
                self.known = false;
        }
        for (self.source.rowLabels(id)) |label| {
            if (self.visits == 1024) return error.TypeLimit;
            self.visits += 1;
            if (!self.budget.spend(1)) return error.TypeLimit;
            for (self.source.operationArguments(label)) |part| try self.ty(part, depth + 1);
        }
    }
};

fn contains(items: []const u32, value: u32) bool {
    return std.mem.findScalar(u32, items, value) != null;
}

fn seedClosed(copy: *graph.NormalizedCopy, scheme: T.Scheme) T.Error!void {
    for (copy.source.list(scheme.closed_rows)) |variable|
        try copy.row_variables.put(copy.allocator, variable, 0);
}

fn requirementHead(left: T.Obligation, right: T.Obligation) bool {
    return left.kind == right.kind and left.name == right.name and
        left.operator == right.operator and std.meta.eql(left.identity, right.identity);
}

fn covered(candidate: *graph.NormalizedCopy, context: *graph.NormalizedCopy, wanted: T.Obligation, declared: T.Obligation) T.Error!bool {
    if (!requirementHead(wanted, declared)) return false;
    for ([_][2]T.Id{
        .{ wanted.ty, declared.ty }, .{ wanted.other, declared.other }, .{ wanted.result, declared.result },
    }) |pair| {
        if (pair[0] == 0 and pair[1] == 0) continue;
        if (pair[0] == 0 or pair[1] == 0) return false;
        const left = try candidate.ty(pair[0], 0);
        const right = try context.ty(pair[1], 0);
        if (!try candidate.destination.equalClosed(try candidate.destination.resolve(left, 0), try candidate.destination.resolve(right, 0))) return false;
    }
    // Dispatch signatures include the surrounding ambient row. Ordinary
    // qualification coverage compares their source operands and results;
    // effect-operation signatures additionally require the exact latent row.
    if (wanted.kind != .dispatch and (wanted.signature != 0 or declared.signature != 0)) {
        if (wanted.signature == 0 or declared.signature == 0) return false;
        if (!try candidate.destination.equalClosed(try candidate.destination.resolve(try candidate.ty(wanted.signature, 0), 0), try candidate.destination.resolve(try context.ty(declared.signature, 0), 0))) return false;
    }
    return true;
}

pub fn fit(a: Allocator, source: *const T.Store, expected: T.Id, candidate_scheme: T.Scheme, enclosing: T.Scheme, obligations: []const T.Obligation, budget: *Budget) Allocator.Error!Match {
    return fitPrivate(a, source, expected, candidate_scheme, enclosing, obligations, budget) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.TypeMismatch, error.EffectMismatch, error.InfiniteType, error.InfiniteEffect => .incompatible,
        error.TypeLimit => blk: {
            budget.exhausted = true;
            break :blk .unknown;
        },
    };
}

fn fitPrivate(a: Allocator, source: *const T.Store, expected: T.Id, scheme: T.Scheme, enclosing: T.Scheme, obligations: []const T.Obligation, budget: *Budget) T.Error!Match {
    if (expected == 0 or scheme.root == 0) return .unknown;
    if (scheme.obligations.len > 32 or enclosing.obligations.len > 32 or
        scheme.variables.len > 1024 or enclosing.variables.len > 1024 or
        scheme.closed_rows.len > 1024 or enclosing.closed_rows.len > 1024)
    {
        budget.exhausted = true;
        return .unknown;
    }
    var expected_measure: Measure = .{ .source = source, .quantified = enclosing.variables, .closed_rows = enclosing.closed_rows, .budget = budget };
    try expected_measure.ty(expected, 0);
    var candidate_measure: Measure = .{ .source = source, .quantified = scheme.variables, .closed_rows = scheme.closed_rows, .budget = budget };
    try candidate_measure.ty(scheme.root, 0);
    for (obligations[scheme.obligations.start..][0..scheme.obligations.len]) |obligation|
        for ([_]T.Id{ obligation.ty, obligation.other, obligation.result }) |part| {
            if (part != 0) try candidate_measure.ty(part, 0);
        };
    for (obligations[enclosing.obligations.start..][0..enclosing.obligations.len]) |obligation|
        for ([_]T.Id{ obligation.ty, obligation.other, obligation.result }) |part| {
            if (part != 0) try expected_measure.ty(part, 0);
        };
    for (obligations[scheme.obligations.start..][0..scheme.obligations.len]) |obligation|
        if (obligation.kind != .dispatch and obligation.signature != 0) try candidate_measure.ty(obligation.signature, 0);
    for (obligations[enclosing.obligations.start..][0..enclosing.obligations.len]) |obligation|
        if (obligation.kind != .dispatch and obligation.signature != 0) try expected_measure.ty(obligation.signature, 0);
    const visits = expected_measure.visits + candidate_measure.visits;
    // Structural equality, occurs checks and row/field matching can be
    // quadratic. Reserve that bound before any solver operation.
    if (!budget.spend(visits * visits)) return .unknown;
    var private = try T.Store.init(a);
    defer private.deinit();
    var context: graph.NormalizedCopy = .{ .allocator = a, .source = source, .destination = &private, .max_depth = 32, .max_nodes = 1024 };
    defer context.deinit();
    var candidate: graph.NormalizedCopy = .{ .allocator = a, .source = source, .destination = &private, .max_depth = 32, .max_nodes = 1024 };
    defer candidate.deinit();
    try seedClosed(&context, enclosing);
    try seedClosed(&candidate, scheme);
    // Source nominal units are nonzero. Unit zero is used only here for
    // rigid enclosing binders; these private identities never reach a reply.
    for (source.list(enclosing.variables), 0..) |variable, index| {
        const node = source.node(source.head(variable, 0));
        if (node.tag != .variable) continue;
        const rigid = try private.typeConstructor(.{ .unit = 0, .decl = @intCast(index + 1) });
        try context.variables.put(a, node.a, rigid);
    }
    const expected_copy = try context.ty(expected, 0);
    const candidate_copy = try candidate.ty(scheme.root, 0);
    const exact = scheme.variables.len == 0 and scheme.row_variables.len == 0 and try private.equalClosed(candidate_copy, expected_copy);
    try private.unify(candidate_copy, expected_copy);
    if (!expected_measure.known or !candidate_measure.known) return .unknown;
    for (obligations[scheme.obligations.start..][0..scheme.obligations.len]) |wanted| {
        if (wanted.kind == .callee_use) return .unknown;
        var entailed = false;
        for (obligations[enclosing.obligations.start..][0..enclosing.obligations.len]) |declared| {
            if (!budget.spend(visits * visits)) return .unknown;
            if (try covered(&candidate, &context, wanted, declared)) {
                entailed = true;
                break;
            }
        }
        if (!entailed) return .unknown;
    }
    if (exact) return .exact;
    return .compatible;
}

fn isolatedFitLaw(a: Allocator) !void {
    var source = try T.Store.init(a);
    defer source.deinit();
    const variable = try source.fresh();
    const identity = try source.function(variable, variable);
    const generic: T.Scheme = .{ .root = identity, .variables = try source.saveList(&.{variable}) };
    const expected = try source.function(T.f32_type, T.f32_type);
    const mark = source.mark();
    var budget: Budget = .{};
    try std.testing.expectEqual(Match.compatible, try fit(a, &source, expected, generic, .{}, &.{}, &budget));
    try std.testing.expectEqual(Match.incompatible, try fit(a, &source, T.u32_type, .{ .root = T.f32_type }, .{}, &.{}, &budget));
    try std.testing.expectEqual(Match.exact, try fit(a, &source, T.f32_type, .{ .root = T.f32_type }, .{}, &.{}, &budget));
    try std.testing.expectEqual(Match.unknown, try fit(a, &source, variable, .{ .root = T.f32_type }, .{}, &.{}, &budget));
    try std.testing.expectEqualDeep(mark, source.mark());
}

test "completion isolated fitting preserves live substitutions through allocation failure" {
    try isolatedFitLaw(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, isolatedFitLaw, .{});
}

test "completion fitting preserves rigid aliases and requires enclosing evidence" {
    const a = std.testing.allocator;
    var source = try T.Store.init(a);
    defer source.deinit();
    const rigid = try source.fresh();
    const fresh = try source.fresh();
    const expected = try source.function(rigid, rigid);
    const generic = try source.function(fresh, fresh);
    const requirements = [_]T.Obligation{
        .{ .kind = .dispatch, .name = 7, .ty = fresh, .other = fresh, .result = fresh, .source = 0 },
        .{ .kind = .dispatch, .name = 7, .ty = rigid, .other = rigid, .result = rigid, .source = 0 },
    };
    const enclosing: T.Scheme = .{ .root = expected, .variables = try source.saveList(&.{rigid}), .obligations = .{ .start = 1, .len = 1 } };
    const scheme: T.Scheme = .{ .root = generic, .variables = try source.saveList(&.{fresh}), .obligations = .{ .len = 1 } };
    var budget: Budget = .{};
    try std.testing.expectEqual(Match.compatible, try fit(a, &source, expected, scheme, enclosing, &requirements, &budget));
    try std.testing.expectEqual(Match.incompatible, try fit(a, &source, rigid, scheme, enclosing, &requirements, &budget));
    try std.testing.expectEqual(Match.unknown, try fit(a, &source, expected, scheme, .{ .variables = enclosing.variables }, &requirements, &budget));
    const distinct = try source.fresh();
    const unequal = try source.function(rigid, distinct);
    const unequal_context: T.Scheme = .{ .variables = try source.saveList(&.{ rigid, distinct }) };
    try std.testing.expectEqual(Match.incompatible, try fit(a, &source, unequal, .{ .root = generic, .variables = scheme.variables }, unequal_context, &.{}, &budget));
    var empty: Budget = .{ .remaining = 0 };
    try std.testing.expectEqual(Match.unknown, try fit(a, &source, expected, scheme, enclosing, &requirements, &empty));
    try std.testing.expect(empty.exhausted);
}
