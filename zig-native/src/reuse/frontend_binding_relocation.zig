//! Own the public binding
//! correspondence before any retained Core reference can be rewritten.
const std = @import("std");
const PI = @import("principal_interface.zig");
const T = @import("../check/types.zig");
const D = @import("frozen_dependency.zig");
const graphs = @import("frontend_graph_correspondence.zig");
const ast = @import("../parse/ast.zig");
const A = std.mem.Allocator;
const Error = A.Error || error{Declined};
const unmapped = std.math.maxInt(u32);

pub const Qualification = struct {
    before: ast.Span,
    after: ast.Span,
    fn less(_: void, left: Qualification, right: Qualification) bool {
        return left.before.start < right.before.start or (left.before.start == right.before.start and left.before.end < right.before.end);
    }
};

pub const Map = struct {
    bindings: []u32,
    nominals: []u32 = &.{},
    constructors: []u32 = &.{},
    contracts: []u32 = &.{},
    qualifications: []Qualification = &.{},
    pub fn deinit(self: *Map, a: A) void {
        a.free(self.bindings);
        a.free(self.nominals);
        a.free(self.constructors);
        a.free(self.contracts);
        a.free(self.qualifications);
        self.* = .{ .bindings = &.{} };
    }
    pub fn binding(self: Map, old: u32) ?u32 {
        if (old == 0 or old >= self.bindings.len or self.bindings[old] == 0) return null;
        return self.bindings[old];
    }
    pub fn qualification(self: Map, old: ast.Span) ast.Span {
        var low: usize = 0;
        var high = self.qualifications.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            const value = self.qualifications[middle];
            if (std.meta.eql(value.before, old)) return value.after;
            if (Qualification.less({}, value, .{ .before = old, .after = old })) low = middle + 1 else high = middle;
        }
        return old;
    }
    pub fn changes(self: Map) bool {
        for (self.qualifications) |value| if (!std.meta.eql(value.before, value.after)) return true;
        for (self.bindings, 0..) |current, old| if (current != 0 and current != old) return true;
        for (self.nominals, 0..) |current, old| if (current != 0 and current != old) return true;
        for (self.constructors, 0..) |current, old| if (current != 0 and current != old) return true;
        for (self.contracts, 0..) |current, old| if (current != unmapped and current != old) return true;
        return false;
    }
    pub fn catalog(self: Map, kind: @FieldType(D.Export, "kind"), old: u32) ?u32 {
        // Contract catalog zero is a valid declaration, unlike the nominal
        // and constructor sentinel entries.
        if (kind == .contract) return if (old < self.contracts.len and self.contracts[old] != unmapped) self.contracts[old] else null;
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
    pub fn qualification(self: Targets, unit: u32, span: ast.Span) ast.Span {
        if (unit == 0 or unit > self.units.len) return span;
        const map = self.units[unit - 1] orelse return span;
        return map.qualification(span);
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
        if (old.name == 0 and (old.kind != .external or old.external == null)) return null;
        var matched: ?u32 = null;
        for (right.bindings, 0..) |current, next| {
            if (comparisons == 0) return null;
            comparisons -= 1;
            if (next == 0 or !visible(current) or old.name != current.name or old.kind != current.kind) continue;
            // Shared imported schemes have no exposed spelling. Their exact
            // original public producer target, not an ordinal, identifies them.
            if (old.name == 0) {
                const target = targets.target(old.external.?) orelse return null;
                if (current.external == null or !std.meta.eql(target, current.external.?)) continue;
            }
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

    if (!privateContractsOnly(left) or !privateContractsOnly(right)) {
        map.contracts = try a.alloc(u32, left.contracts.len);
        @memset(map.contracts, unmapped);
        const contract_used = try a.alloc(bool, right.contracts.len);
        defer a.free(contract_used);
        @memset(contract_used, false);
        for (left.contracts, 0..) |old, index| {
            if (old.private) continue;
            var matched: ?u32 = null;
            for (right.contracts, 0..) |current, next| {
                if (comparisons == 0) return null;
                comparisons -= 1;
                if (current.private or old.name != current.name or !std.meta.eql(old.identity, current.identity)) continue;
                if (matched != null or contract_used[next]) return null;
                matched = @intCast(next);
            }
            const next = matched orelse return null;
            contract_used[next] = true;
            map.contracts[index] = next;
        }
        for (right.contracts, contract_used) |value, matched| if (!value.private and !matched) return null;
    }

    var graph = (try graphs.Match.init(a, &left.graph, &right.graph)) orelse return null;
    defer graph.deinit();
    var checker: Checker = .{ .left = left, .right = right, .graph = &graph, .map = map, .targets = targets };
    defer checker.qualifications.deinit(a);
    checker.check() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Declined => return null,
    };
    map.qualifications = try checker.qualifications.toOwnedSlice(a);
    std.mem.sort(Qualification, map.qualifications, {}, Qualification.less);
    published = true;
    return map;
}

// Admitted private catalogs contain redacted tombstones. They confer no public
// authority and no external catalog position. Public recipes are compared
// separately; selected implementations still require ordinary checking.
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
    qualifications: std.ArrayList(Qualification) = .empty,
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
        try self.contracts();
    }
    fn contracts(self: *Checker) Error!void {
        if (privateContractsOnly(self.left) and privateContractsOnly(self.right)) return;
        try self.privateContractSlots(self.left);
        try self.privateContractSlots(self.right);
        for (self.left.contracts, 0..) |old, index| {
            if (old.private) continue;
            try self.work(0);
            const current = self.right.contracts[self.map.catalog(.contract, @intCast(index)) orelse return error.Declined];
            if (old.private != current.private or old.name != current.name or old.declaration != current.declaration or !std.meta.eql(old.identity, current.identity) or old.requires_implementation != current.requires_implementation or old.parameter_names.len != current.parameter_names.len or old.row_parameter_names.len != current.row_parameter_names.len) return error.Declined;
            try self.graph.typeList(old.parameters, current.parameters);
            try self.graph.typeList(old.variables, current.variables);
            try self.patternList(old.patterns, current.patterns, 0);
            try self.graph.rowVariables(old.row_variables, current.row_variables);
            try self.graph.rowList(old.row_parameters, current.row_parameters);
            if (old.predicates.len != current.predicates.len or old.members.len != current.members.len) return error.Declined;
            for (self.left.contract_predicates[old.predicates.start..][0..old.predicates.len], self.right.contract_predicates[current.predicates.start..][0..current.predicates.len]) |from, to| try self.obligation(from, to);
            for (self.left.contract_members[old.members.start..][0..old.members.len], self.right.contract_members[current.members.start..][0..current.members.len]) |from, to| {
                try self.work(0);
                if (from.name != to.name or from.kind != to.kind or !std.meta.eql(from.contract, to.contract)) return error.Declined;
                try self.graph.ty(from.root, to.root);
            }
        }
    }
    fn privateContractSlots(self: *Checker, owner: *const PI.Interface) Error!void {
        // Redacted private headers have empty spans. Any substantive flat slot
        // must therefore belong to a public recipe that is compared above.
        for (owner.contract_members, 0..) |member, index| {
            if (member.name == 0 and member.root == 0) continue;
            var public = false;
            for (owner.contracts) |header| {
                try self.work(0);
                if (!header.private and std.meta.eql(header.identity, member.contract) and index >= header.members.start and index - header.members.start < header.members.len) public = true;
            }
            if (!public) return error.Declined;
        }
        const inert: T.Obligation = .{ .ty = 0, .kind = .type_rep, .source = 0, .explicit = true };
        for (owner.contract_predicates, 0..) |predicate, index| {
            if (std.meta.eql(predicate, inert)) continue;
            var public = false;
            for (owner.contracts) |header| {
                try self.work(0);
                if (!header.private and index >= header.predicates.start and index - header.predicates.start < header.predicates.len) public = true;
            }
            if (!public) return error.Declined;
        }
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
            try self.obligation(from, to);
        }
    }
    fn obligation(self: *Checker, from: T.Obligation, to: T.Obligation) Error!void {
        try self.work(0);
        if (from.kind != to.kind or from.name != to.name or from.operator != to.operator or from.explicit != to.explicit or from.qualification_unit != to.qualification_unit or from.source != 0 or to.source != 0) return error.Declined;
        if (from.kind == .callee_use) {
            // Only an owned public binding map establishes this relation.
            // Formal, private and missing callees have no admitted target.
            if (from.identity.unit == 0 or from.identity.unit != self.left.unit or to.identity.unit != self.right.unit) return error.Declined;
            if ((self.map.binding(from.identity.decl) orelse return error.Declined) != to.identity.decl) return error.Declined;
        } else if (!std.meta.eql(from.identity, to.identity)) return error.Declined;
        inline for (.{ "ty", "result", "other", "signature" }) |field| try self.graph.ty(@field(from, field), @field(to, field));
        if ((from.qualification_span == null) != (to.qualification_span == null)) return error.Declined;
        const before = from.qualification_span orelse return;
        const after = to.qualification_span.?;
        if (before.start > before.end or after.start > after.end) return error.Declined;
        if (from.explicit and from.qualification_unit == self.left.unit) {
            // This span belongs to the matched public scheme or contract. Its
            // complete predicate graph has passed; retain the correspondence
            // so owned caller copies keep current evidence provenance too.
            for (self.qualifications.items) |prior| {
                try self.work(0);
                if (std.meta.eql(prior.before, before)) {
                    if (!std.meta.eql(prior.after, after)) return error.Declined;
                    return;
                }
                if (std.meta.eql(prior.after, after)) return error.Declined;
            }
            try self.qualifications.append(self.graph.allocator, .{ .before = before, .after = after });
        } else if (!std.meta.eql(self.targets.qualification(from.qualification_unit, before), after)) return error.Declined;
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

fn publicContractMapScenario(a: A) !void {
    var old_nodes = [_]T.Node{ .{ .tag = .absent }, .{ .tag = .u32 }, .{ .tag = .array, .a = 1 } };
    var new_nodes = old_nodes;
    const inert: PI.Binding = .{ .private = true, .name = 0, .kind = .global, .named_function = false, .ty = 0, .scheme = .{}, .external = null };
    const public: PI.Binding = .{ .name = 7, .kind = .global, .named_function = false, .ty = 1, .scheme = .{ .root = 1, .obligations = .{ .start = 0, .len = 1 } }, .external = null };
    var old_bindings = [_]PI.Binding{ inert, inert, public };
    var new_bindings = [_]PI.Binding{ inert, inert, inert, public };
    const contract: PI.Contract = .{ .identity = .{ .unit = 1, .decl = T.opaque_name_bit | 9 }, .name = 9, .predicates = .{ .start = 0, .len = 2 } };
    var old_contracts = [_]PI.Contract{contract};
    var new_contracts = [_]PI.Contract{ .{ .private = true, .identity = .{ .unit = 1, .decl = T.opaque_name_bit | 10 }, .name = 0 }, contract };
    const before: ast.Span = .{ .start = 10, .end = 20 };
    const after: ast.Span = .{ .start = 40, .end = 50 };
    const predicate: T.Obligation = .{ .ty = 2, .kind = .type_rep, .source = 0, .explicit = true, .qualification_unit = 1, .qualification_span = before };
    var predicates = [_]T.Obligation{ predicate, predicate };
    var moved = predicates;
    for (&moved) |*value| value.qualification_span = after;
    const clause_before: ast.Span = .{ .start = 60, .end = 70 };
    const clause_after: ast.Span = .{ .start = 90, .end = 100 };
    var old_goals = [_]T.Obligation{.{ .ty = 1, .kind = .type_rep, .source = 0, .explicit = true, .qualification_unit = 1, .qualification_span = clause_before }};
    var new_goals = old_goals;
    new_goals[0].qualification_span = clause_after;
    const old: PI.Interface = .{
        .unit = 1,
        .graph = .{ .nodes = &old_nodes, .extra = &.{}, .rows = &.{}, .labels = &.{}, .operations = &.{}, .row_variable_count = 0 },
        .patterns = .{ .nodes = &.{}, .extra = &.{} },
        .bindings = &old_bindings,
        .obligations = &old_goals,
        .obligation_spans = &.{},
        .nominals = &.{},
        .constructors = &.{},
        .effect_families = &.{},
        .effect_templates = &.{},
        .associated = &.{},
        .contracts = &old_contracts,
        .contract_predicates = &predicates,
    };
    var current = old;
    current.bindings = &new_bindings;
    current.graph.nodes = &new_nodes;
    current.contracts = &new_contracts;
    current.contract_predicates = &moved;
    current.obligations = &new_goals;
    var map = (try compare(a, &old, &current, .{})) orelse return error.MissingContractMap;
    defer map.deinit(a);
    try std.testing.expectEqual(@as(?u32, 1), map.catalog(.contract, 0));
    try std.testing.expect(map.changes());
    try std.testing.expectEqual(@as(usize, 2), map.qualifications.len);
    try std.testing.expectEqual(after, map.qualification(before));
    try std.testing.expectEqual(clause_after, map.qualification(clause_before));
    // One authored clause may supply several predicates, but its old/new
    // provenance relation must be unambiguous and keep the original unit.
    moved[1].qualification_span = .{ .start = 41, .end = 51 };
    var ambiguous = try compare(a, &old, &current, .{});
    defer if (ambiguous) |*value| value.deinit(a);
    try std.testing.expect(ambiguous == null);
    moved[1].qualification_span = after;
    moved[1].qualification_unit = 2;
    var foreign = try compare(a, &old, &current, .{});
    defer if (foreign) |*value| value.deinit(a);
    try std.testing.expect(foreign == null);
    moved[1].qualification_unit = 1;
    moved[1].qualification_span = null;
    var omitted = try compare(a, &old, &current, .{});
    defer if (omitted) |*value| value.deinit(a);
    try std.testing.expect(omitted == null);
    moved[1].qualification_span = after;
    // Equal raw predicate root IDs cannot conceal a changed public graph.
    new_nodes[2].tag = .list;
    var rejected = try compare(a, &old, &current, .{});
    defer if (rejected) |*value| value.deinit(a);
    try std.testing.expect(rejected == null);
}

test "frontend relocation public contracts preserve zero catalog slots and reject changed graph recipes through OOM" {
    try publicContractMapScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, publicContractMapScenario, .{});
}

fn sharedCalleeMapScenario(a: A) !void {
    var nodes = [_]T.Node{ .{ .tag = .absent }, .{ .tag = .u32 }, .{ .tag = .function, .a = 1, .b = 1 }, .{ .tag = .product } };
    var rows = [_]T.Effects.Row{.{ .labels = .{}, .tail = .closed }};
    const inert: PI.Binding = .{ .private = true, .name = 0, .kind = .global, .named_function = false, .ty = 0, .scheme = .{}, .external = null };
    const callee: PI.Binding = .{ .name = 0, .kind = .external, .named_function = true, .ty = 2, .scheme = .{ .root = 2 }, .external = .{ .unit = 2, .binding = 2 } };
    const caller: PI.Binding = .{ .name = 7, .kind = .external, .named_function = true, .ty = 2, .scheme = .{ .root = 2, .obligations = .{ .start = 0, .len = 1 } }, .external = .{ .unit = 2, .binding = 3 } };
    var before = [_]PI.Binding{ inert, inert, callee, caller };
    var after = [_]PI.Binding{ inert, inert, inert, callee, caller };
    after[3].external.?.binding = 4;
    after[4].external.?.binding = 5;
    var old_goals = [_]T.Obligation{.{ .kind = .callee_use, .ty = 3, .source = 0, .identity = .{ .unit = 1, .decl = 2 } }};
    var new_goals = old_goals;
    new_goals[0].identity.decl = 3;
    const old: PI.Interface = .{
        .unit = 1,
        .graph = .{ .nodes = &nodes, .extra = &.{}, .rows = &rows, .labels = &.{}, .operations = &.{}, .row_variable_count = 0 },
        .patterns = .{ .nodes = &.{}, .extra = &.{} },
        .bindings = &before,
        .obligations = &old_goals,
        .obligation_spans = &.{},
        .nominals = &.{},
        .constructors = &.{},
        .effect_families = &.{},
        .effect_templates = &.{},
        .associated = &.{},
    };
    var current = old;
    current.bindings = &after;
    current.obligations = &new_goals;
    var producer_slots = [_]u32{ 0, 0, 4, 5 };
    const producers = [_]?Map{ null, .{ .bindings = &producer_slots } };
    const targets: Targets = .{ .units = &producers };
    var map = (try compare(a, &old, &current, targets)) orelse return error.MissingSharedCalleeMap;
    defer map.deinit(a);
    try std.testing.expectEqual(@as(?u32, 3), map.binding(2));
    try std.testing.expectEqual(@as(?u32, 4), map.binding(3));
    after[3].external.?.binding = 5;
    var retargeted = try compare(a, &old, &current, targets);
    defer if (retargeted) |*value| value.deinit(a);
    try std.testing.expect(retargeted == null);
    after[3].external.?.binding = 4;
    new_goals[0].identity.decl = 1;
    var private = try compare(a, &old, &current, targets);
    defer if (private) |*value| value.deinit(a);
    try std.testing.expect(private == null);
    new_goals[0].identity.decl = 3;
    old_goals[0].identity.unit = 0;
    new_goals[0].identity.unit = 0;
    var formal = try compare(a, &old, &current, targets);
    defer if (formal) |*value| value.deinit(a);
    try std.testing.expect(formal == null);
}

test "frontend relocation shared public callee schemes retain original targets and reject formal or private substitutions through OOM" {
    try sharedCalleeMapScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, sharedCalleeMapScenario, .{});
}
