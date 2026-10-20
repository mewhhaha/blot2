//! Own the public binding
//! correspondence before any retained Core reference can be rewritten.
const std = @import("std");
const PI = @import("principal_interface.zig");
const T = @import("../check/types.zig");
const D = @import("frozen_dependency.zig");
const graphs = @import("frontend_graph_correspondence.zig");
const A = std.mem.Allocator;
const Error = A.Error || error{Declined};

pub const Map = struct {
    bindings: []u32,
    nominals: []u32 = &.{},
    constructors: []u32 = &.{},
    pub fn deinit(self: *Map, a: A) void {
        a.free(self.bindings);
        a.free(self.nominals);
        a.free(self.constructors);
        self.* = .{ .bindings = &.{} };
    }
    pub fn binding(self: Map, old: u32) ?u32 {
        if (old == 0 or old >= self.bindings.len or self.bindings[old] == 0) return null;
        return self.bindings[old];
    }
    pub fn changes(self: Map) bool {
        for (self.bindings, 0..) |current, old| if (current != 0 and current != old) return true;
        for (self.nominals, 0..) |current, old| if (current != 0 and current != old) return true;
        for (self.constructors, 0..) |current, old| if (current != 0 and current != old) return true;
        return false;
    }
    pub fn catalog(self: Map, kind: @FieldType(D.Export, "kind"), old: u32) ?u32 {
        const entries = switch (kind) {
            .nominal => self.nominals,
            .constructor => self.constructors,
            else => return old,
        };
        if (old == 0 or old >= entries.len or entries[old] == 0) return null;
        return entries[old];
    }
};

pub const Targets = struct {
    units: []const ?Map = &.{},
    pub fn changes(self: Targets) bool {
        for (self.units) |map| if (map) |value| if (value.changes()) return true;
        return false;
    }
    pub fn target(self: Targets, old: PI.ExternalTarget) ?PI.ExternalTarget {
        if (old.binding == 0 or old.unit == 0 or old.unit > self.units.len) return old;
        const map = self.units[old.unit - 1] orelse return old;
        return .{ .unit = old.unit, .binding = map.binding(old.binding) orelse return null };
    }
    pub fn exported(self: Targets, old: D.Export) ?D.Export {
        var result = old;
        result.target = self.target(old.target) orelse return null;
        if (old.target.unit == 0) return null;
        if (old.target.unit > self.units.len) return result;
        const map = self.units[old.target.unit - 1] orelse return result;
        result.catalog = map.catalog(old.kind, old.catalog) orelse return null;
        return result;
    }
};

fn visible(value: PI.Binding) bool {
    return !value.private and (value.kind == .global or value.kind == .external);
}

/// Inputs must already be admitted immutable principal interfaces in the same
/// exact symbol/unit namespace. Failure publishes neither a partial map nor a
/// semantic equality claim. Unsupported authority-bearing catalogs decline.
pub fn compare(a: A, left: *const PI.Interface, right: *const PI.Interface, targets: Targets) A.Error!?Map {
    if (left.unit != right.unit or left.bindings.len > 65_536 or right.bindings.len > 65_536) return null;
    if (left.has_rank_contracts or right.has_rank_contracts or left.has_usage_contracts or right.has_usage_contracts or left.has_numeric_proofs or right.has_numeric_proofs) return null;
    inline for (.{ "proof_contracts", "associated", "implementations", "implementation_predicates", "implementation_members", "member_templates", "selected_proofs", "selected_members", "selected_edges" }) |field| {
        if (@field(left, field).len != 0 or @field(right, field).len != 0) return null;
    }
    if (!privateContractsOnly(left) or !privateContractsOnly(right)) return null;
    // Moving effects changes their generative AST identity. They do not take
    // the opaque-name exception and remain on ordinary checking here.
    if (!privateEffectsOnly(left) or !privateEffectsOnly(right)) {
        if (left.effect_families.len != right.effect_families.len or left.effect_templates.len != right.effect_templates.len) return null;
    }

    var map: Map = .{ .bindings = try a.alloc(u32, left.bindings.len) };
    var published = false;
    defer if (!published) map.deinit(a);
    @memset(map.bindings, 0);
    const used = try a.alloc(bool, right.bindings.len);
    defer a.free(used);
    @memset(used, false);
    var comparisons: usize = 65_536;
    for (left.bindings, 0..) |old, index| {
        if (index == 0) continue;
        if (!visible(old)) continue;
        if (old.name == 0) return null;
        var matched: ?u32 = null;
        for (right.bindings, 0..) |current, next| {
            if (comparisons == 0) return null;
            comparisons -= 1;
            if (next == 0 or !visible(current) or old.name != current.name or old.kind != current.kind) continue;
            if (matched != null or used[next]) return null;
            matched = @intCast(next);
        }
        const next = matched orelse return null;
        used[next] = true;
        map.bindings[index] = next;
    }
    for (right.bindings, used, 0..) |value, matched, index| if (index != 0 and visible(value) and !matched) return null;

    map.nominals = try a.alloc(u32, left.nominals.len);
    @memset(map.nominals, 0);
    const nominal_used = try a.alloc(bool, right.nominals.len);
    defer a.free(nominal_used);
    @memset(nominal_used, false);
    for (left.nominals, 0..) |old, index| {
        if (index == 0 or old.private) continue;
        var matched: ?u32 = null;
        for (right.nominals, 0..) |current, next| {
            if (comparisons == 0) return null;
            comparisons -= 1;
            if (next == 0 or current.private or old.name != current.name or !std.meta.eql(old.identity, current.identity)) continue;
            if (matched != null or nominal_used[next]) return null;
            matched = @intCast(next);
        }
        const next = matched orelse return null;
        nominal_used[next] = true;
        map.nominals[index] = next;
    }
    for (right.nominals, nominal_used, 0..) |value, matched, index| if (index != 0 and !value.private and !matched) return null;
    map.constructors = try a.alloc(u32, left.constructors.len);
    @memset(map.constructors, 0);
    const constructor_used = try a.alloc(bool, right.constructors.len);
    defer a.free(constructor_used);
    @memset(constructor_used, false);
    for (left.constructors, 0..) |old, index| {
        if (index == 0 or old.nominal == 0 or old.nominal >= map.nominals.len or left.nominals[old.nominal].private) continue;
        const parent = map.nominals[old.nominal];
        if (parent == 0) return null;
        var matched: ?u32 = null;
        for (right.constructors, 0..) |current, next| {
            if (comparisons == 0) return null;
            comparisons -= 1;
            if (next == 0 or current.nominal != parent or current.tag != old.tag) continue;
            if (matched != null or constructor_used[next]) return null;
            matched = @intCast(next);
        }
        const next = matched orelse return null;
        constructor_used[next] = true;
        map.constructors[index] = next;
    }
    for (right.constructors, constructor_used, 0..) |value, matched, index| {
        if (index != 0 and value.nominal != 0 and !right.nominals[value.nominal].private and !matched) return null;
    }

    var graph = (try graphs.Match.init(a, &left.graph, &right.graph)) orelse return null;
    defer graph.deinit();
    var checker: Checker = .{ .left = left, .right = right, .graph = &graph, .map = map, .targets = targets };
    checker.check() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Declined => return null,
    };
    published = true;
    return map;
}

// Admitted private catalogs contain redacted tombstones. They confer no public
// authority and no external catalog position. Actual public authority graphs
// remain on ordinary checking until their full correspondence is implemented.
fn privateContractsOnly(owner: *const PI.Interface) bool {
    for (owner.contracts) |contract| if (!contract.private) return false;
    if (owner.implementations.len != 0 or owner.implementation_members.len != 0 or owner.implementation_predicates.len != 0) return false;
    for (owner.contract_members) |member| if (member.name != 0 or member.root != 0) return false;
    const inert: T.Obligation = .{ .ty = 0, .kind = .type_rep, .source = 0, .explicit = true };
    for (owner.contract_predicates) |predicate| if (!std.meta.eql(predicate, inert)) return false;
    return true;
}
fn privateEffectsOnly(owner: *const PI.Interface) bool {
    for (owner.effect_families, 0..) |family, index| {
        if (index == 0 and family.identity.unit == 0 and family.identity.decl == 0) continue;
        if (!family.private) return false;
    }
    for (owner.effect_templates, 0..) |operation, index| {
        if (index == 0 and operation.identity.unit == 0 and operation.identity.decl == 0) continue;
        if (operation.family >= owner.effect_families.len or !owner.effect_families[operation.family].private) return false;
    }
    return true;
}

const Checker = struct {
    left: *const PI.Interface,
    right: *const PI.Interface,
    graph: *graphs.Match,
    map: Map,
    targets: Targets,
    remaining: usize = 65_536,
    fn work(self: *Checker, depth: usize) Error!void {
        if (depth >= 128 or self.remaining == 0) return error.Declined;
        self.remaining -= 1;
    }
    fn check(self: *Checker) Error!void {
        for (self.left.bindings, 0..) |old, index| {
            if (!visible(old)) continue;
            try self.work(0);
            const current = self.right.bindings[self.map.binding(@intCast(index)) orelse return error.Declined];
            if (old.private != current.private or old.named_function != current.named_function or old.capability_flow != current.capability_flow or !std.meta.eql(old.capability_parameters, current.capability_parameters)) return error.Declined;
            if (old.external) |target| {
                const mapped = self.targets.target(target) orelse return error.Declined;
                if (current.external == null or !std.meta.eql(mapped, current.external.?)) return error.Declined;
            } else if (current.external != null) return error.Declined;
            try self.graph.ty(old.ty, current.ty);
            try self.scheme(old.scheme, current.scheme);
        }
        // The public capability graph is already canonical in declaration
        // order. Private binding insertion must preserve the complete recipe;
        // only its sparse public binding roots need slot relocation.
        const old_capabilities = self.left.capability_contracts;
        const new_capabilities = self.right.capability_contracts;
        if (old_capabilities.nodes.len != new_capabilities.nodes.len or !std.mem.eql(u32, old_capabilities.words, new_capabilities.words) or old_capabilities.bindings.len != new_capabilities.bindings.len) return error.Declined;
        for (old_capabilities.nodes, new_capabilities.nodes) |old, current| if (!std.meta.eql(old, current)) return error.Declined;
        for (old_capabilities.bindings, new_capabilities.bindings) |old, current| {
            try self.work(0);
            if ((self.map.binding(old.binding) orelse return error.Declined) != current.binding or old.root != current.root) return error.Declined;
        }
        for (self.left.nominals, 0..) |old, index| {
            if (index == 0 or old.private) continue;
            const mapped = self.map.catalog(.nominal, @intCast(index)) orelse return error.Declined;
            const current = self.right.nominals[mapped];
            try self.work(0);
            if (old.affine != current.affine or old.has_usage != current.has_usage or old.closed_storage != current.closed_storage or old.private != current.private or old.is_opaque != current.is_opaque or old.declaration != current.declaration or !std.meta.eql(old.identity, current.identity) or old.name != current.name) return error.Declined;
            if ((!old.is_opaque or old.storage.kind == .unknown or current.storage.kind == .unknown) and !std.meta.eql(old.storage, current.storage)) return error.Declined;
            try self.graph.typeList(old.parameters, current.parameters);
            try self.graph.typeList(old.variables, current.variables);
            try self.graph.ty(old.alias, current.alias);
            try self.graph.rowVariables(old.alias_rows, current.alias_rows);
            // These are declaration-local binder spellings. Public argument
            // shapes, record labels and repeated-variable relationships are
            // compared through the complete type and pattern graphs instead.
            if (old.parameter_names.len != current.parameter_names.len) return error.Declined;
            try self.patternList(old.patterns, current.patterns, 0);
            if (old.constructors.len != current.constructors.len) return error.Declined;
            for (self.left.graph.extra[old.constructors.start..][0..old.constructors.len], self.right.graph.extra[current.constructors.start..][0..current.constructors.len]) |before, after| {
                try self.work(0);
                if ((self.map.catalog(.constructor, before) orelse return error.Declined) != after) return error.Declined;
            }
        }
        for (self.left.constructors, 0..) |old, index| {
            if (index == 0 or old.nominal == 0 or self.left.nominals[old.nominal].private) continue;
            const mapped = self.map.catalog(.constructor, @intCast(index)) orelse return error.Declined;
            const current = self.right.constructors[mapped];
            try self.work(0);
            if (old.private != current.private or (self.map.catalog(.nominal, old.nominal) orelse return error.Declined) != current.nominal or old.tag != current.tag or old.name != current.name or old.declared_record != current.declared_record or old.identity.unit != current.identity.unit) return error.Declined;
            if (old.identity.decl != current.identity.decl) {
                if (!old.private or old.nominal >= self.left.nominals.len) return error.Declined;
                const parent = self.left.nominals[old.nominal];
                if (!parent.is_opaque or parent.storage.kind == .unknown or self.right.nominals[current.nominal].storage.kind == .unknown or old.identity.unit != parent.identity.unit) return error.Declined;
            }
            try self.graph.ty(old.payload, current.payload);
            try self.scheme(old.scheme, current.scheme);
        }
        try self.effects();
    }
    fn effects(self: *Checker) Error!void {
        if (privateEffectsOnly(self.left) and privateEffectsOnly(self.right)) return;
        if (self.left.effect_families.len != self.right.effect_families.len or self.left.effect_templates.len != self.right.effect_templates.len) return error.Declined;
        for (self.left.effect_families, self.right.effect_families) |old, current| {
            try self.work(0);
            if (old.private != current.private) return error.Declined;
            if (old.private) continue;
            if (!std.meta.eql(old.identity, current.identity) or old.name != current.name or old.callable != current.callable or old.parameter_names.len != current.parameter_names.len) return error.Declined;
            try self.graph.typeList(old.parameters, current.parameters);
            try self.graph.typeList(old.variables, current.variables);
            try self.patternList(old.patterns, current.patterns, 0);
            // Catalog positions are retained here; only private-only catalogs
            // may grow without a public effect catalog correspondence.
            if (!std.mem.eql(u32, self.left.graph.extra[old.operations.start..][0..old.operations.len], self.right.graph.extra[current.operations.start..][0..current.operations.len])) return error.Declined;
        }
        for (self.left.effect_templates, self.right.effect_templates) |old, current| {
            try self.work(0);
            const before = self.left.effect_families[old.family];
            const after = self.right.effect_families[current.family];
            if (before.private and after.private) continue;
            if (old.family != current.family or old.name != current.name or !std.meta.eql(old.identity, current.identity)) return error.Declined;
            try self.graph.ty(old.parameter, current.parameter);
            try self.graph.ty(old.result, current.result);
        }
    }
    fn scheme(self: *Checker, old: T.Scheme, current: T.Scheme) Error!void {
        try self.work(0);
        if (old.generative.len != 0 or current.generative.len != 0) return error.Declined;
        try self.graph.ty(old.root, current.root);
        try self.graph.typeList(old.variables, current.variables);
        try self.graph.rowVariables(old.row_variables, current.row_variables);
        try self.graph.rowVariables(old.closed_rows, current.closed_rows);
        if (old.obligations.len != current.obligations.len) return error.Declined;
        const old_goals = self.left.obligations[old.obligations.start..][0..old.obligations.len];
        const new_goals = self.right.obligations[current.obligations.start..][0..current.obligations.len];
        for (old_goals, new_goals) |from, to| {
            try self.work(0);
            // Formal value binders need a separate lexical correspondence;
            // numeric coincidence after movement cannot prove one.
            if (from.kind == .callee_use or to.kind == .callee_use) return error.Declined;
            if (from.kind != to.kind or from.name != to.name or from.operator != to.operator or !std.meta.eql(from.identity, to.identity) or from.explicit != to.explicit or from.qualification_unit != to.qualification_unit or !std.meta.eql(from.qualification_span, to.qualification_span) or from.source != 0 or to.source != 0) return error.Declined;
            inline for (.{ "ty", "result", "other", "signature" }) |field| try self.graph.ty(@field(from, field), @field(to, field));
        }
    }
    fn patternList(self: *Checker, old: T.List, current: T.List, depth: usize) Error!void {
        try self.work(depth);
        if (old.len != current.len) return error.Declined;
        const before = self.left.patterns.extra[old.start..][0..old.len];
        const after = self.right.patterns.extra[current.start..][0..current.len];
        for (before, after) |from, to| try self.pattern(from, to, depth + 1);
    }
    fn pattern(self: *Checker, old: u32, current: u32, depth: usize) Error!void {
        try self.work(depth);
        const from = self.left.patterns.nodes[old];
        const to = self.right.patterns.nodes[current];
        if (from.kind != to.kind or from.b != to.b) return error.Declined;
        if (from.kind == .binding) return self.graph.ty(from.a, to.a);
        if (from.kind == .record) {
            for (0..from.b) |field| {
                const before = self.left.patterns.extra[from.a + field * 2 ..][0..2];
                const after = self.right.patterns.extra[to.a + field * 2 ..][0..2];
                if (before[0] != after[0]) return error.Declined;
                try self.pattern(before[1], after[1], depth + 1);
            }
        } else try self.patternList(.{ .start = from.a, .len = from.b }, .{ .start = to.a, .len = to.b }, depth + 1);
    }
};

fn bindingMapScenario(a: A) !void {
    var nodes = [_]T.Node{ .{ .tag = .absent }, .{ .tag = .u32 }, .{ .tag = .f32 } };
    const inert: PI.Binding = .{ .private = true, .name = 0, .kind = .global, .named_function = false, .ty = 0, .scheme = .{}, .external = null };
    const public: PI.Binding = .{ .name = 7, .kind = .global, .named_function = false, .ty = 1, .scheme = .{ .root = 1 }, .external = null };
    var old_bindings = [_]PI.Binding{ inert, inert, public };
    var current_bindings = [_]PI.Binding{ inert, inert, inert, public };
    const old: PI.Interface = .{
        .unit = 1,
        .graph = .{ .nodes = &nodes, .extra = &.{}, .rows = &.{}, .labels = &.{}, .operations = &.{}, .row_variable_count = 0 },
        .patterns = .{ .nodes = &.{}, .extra = &.{} },
        .bindings = &old_bindings,
        .obligations = &.{},
        .obligation_spans = &.{},
        .nominals = &.{},
        .constructors = &.{},
        .effect_families = &.{},
        .effect_templates = &.{},
        .associated = &.{},
    };
    var current = old;
    current.bindings = &current_bindings;
    var map = (try compare(a, &old, &current, .{})) orelse return error.MissingBindingMap;
    defer map.deinit(a);
    try std.testing.expectEqual(@as(?u32, 3), map.binding(2));
    try std.testing.expectEqual(@as(?u32, null), map.binding(1));
    current_bindings[3].ty = 2;
    var rejected = try compare(a, &old, &current, .{});
    defer if (rejected) |*unexpected| unexpected.deinit(a);
    try std.testing.expect(rejected == null);
}

test "frontend relocation public slot maps own private insertion and reject changed contracts through OOM" {
    try bindingMapScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, bindingMapScenario, .{});
}
