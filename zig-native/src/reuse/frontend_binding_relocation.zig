//! Own the public binding
//! correspondence before any retained Core reference can be rewritten.
const std = @import("std");
const PI = @import("principal_interface.zig");
const T = @import("../check/types.zig");
const D = @import("frozen_dependency.zig");
const graphs = @import("frontend_graph_correspondence.zig");
const ast = @import("../parse/ast.zig");
const methods = @import("frontend_method_sources.zig");
const capabilities = @import("../check/capability_contracts.zig");
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
    implementations: []u32 = &.{},
    qualifications: []Qualification = &.{},
    pub fn deinit(self: *Map, a: A) void {
        a.free(self.bindings);
        a.free(self.nominals);
        a.free(self.constructors);
        a.free(self.contracts);
        a.free(self.implementations);
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
        for (self.implementations, 0..) |current, old| if (current != unmapped and current != old) return true;
        return false;
    }
    pub fn catalog(self: Map, kind: @FieldType(D.Export, "kind"), old: u32) ?u32 {
        // Contract catalog zero is a valid declaration, unlike the nominal
        // and constructor sentinel entries.
        if (kind == .contract) return if (old < self.contracts.len and self.contracts[old] != unmapped) self.contracts[old] else null;
        if (kind == .implementation) return if (old < self.implementations.len and self.implementations[old] != unmapped) self.implementations[old] else null;
        const entries = switch (kind) {
            .nominal => self.nominals,
            .constructor => self.constructors,
            else => return old,
        };
        if (old == 0 or old >= entries.len or entries[old] == 0) return null;
        return entries[old];
    }
};

pub const Progress = struct {
    stage: enum { eligibility, public_index, public_match, nominals, constructors, contracts, implementations, graph, checked } = .eligibility,
    binding: u32 = 0,
    other: u32 = 0,
    unnamed: bool = false,
    kind: PI.Kind = .global,
};
pub const Targets = struct {
    progress: ?*Progress = null,
    units: []const ?Map = &.{},
    methods: ?methods.Sources = null,
    comparisons_left: ?*usize = null,
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

const BindingKey = struct {
    name: u32,
    kind: PI.Kind,
    target: PI.ExternalTarget = .{ .unit = 0, .binding = 0 },
    fn current(binding: PI.Binding) ?BindingKey {
        if (binding.name != 0) return .{ .name = binding.name, .kind = binding.kind, .target = if (binding.kind == .external) binding.external orelse .{ .unit = 0, .binding = 0 } else .{ .unit = 0, .binding = 0 } };
        if (binding.kind != .external) return null;
        return .{ .name = 0, .kind = binding.kind, .target = binding.external orelse return null };
    }
};

const CatalogKey = struct { name: u32, identity: PI.Identity };
const CatalogIndex = std.AutoHashMapUnmanaged(CatalogKey, u32);
const ConstructorKey = struct { parent: u32, tag: u32 };
fn namedCatalogIndex(a: A, entries: anytype, sentinel: bool, remaining: *usize) A.Error!?CatalogIndex {
    var result: CatalogIndex = .empty;
    var published = false;
    defer if (!published) result.deinit(a);
    for (entries, 0..) |entry, index| {
        if ((sentinel and index == 0) or entry.private) continue;
        if (remaining.* == 0) return null;
        remaining.* -= 1;
        const slot = try result.getOrPut(a, .{ .name = entry.name, .identity = entry.identity });
        if (slot.found_existing) return null;
        slot.value_ptr.* = @intCast(index);
    }
    published = true;
    return result;
}

/// Inputs must already be admitted immutable principal interfaces in the same
/// exact symbol/unit namespace. Failure publishes neither a partial map nor a
/// semantic equality claim. Unsupported authority-bearing catalogs decline.
pub fn compare(a: A, left: *const PI.Interface, right: *const PI.Interface, targets: Targets) A.Error!?Map {
    if (targets.progress) |value| value.* = .{};
    if (targets.comparisons_left) |remaining| remaining.* = 65_536;
    if (left.unit != right.unit or left.bindings.len > 65_536 or right.bindings.len > 65_536) return null;
    if (left.has_rank_contracts or right.has_rank_contracts or left.has_usage_contracts or right.has_usage_contracts or left.has_numeric_proofs or right.has_numeric_proofs) return null;
    inline for (.{ "proof_contracts", "selected_proofs", "selected_members", "selected_edges" }) |field| {
        if (@field(left, field).len != 0 or @field(right, field).len != 0) return null;
    }
    // Keep the already-qualified ordinary implementation-catalog bounds.
    if (left.implementations.len != 0 or right.implementations.len != 0) {
        if (left.contracts.len > 64 or right.contracts.len > 64 or left.implementations.len > 64 or right.implementations.len > 64) return null;
        for (left.implementations) |value| if (!value.private and (value.row_variables.len != 0 or value.row_parameters.len != 0)) return null;
        for (right.implementations) |value| if (!value.private and (value.row_variables.len != 0 or value.row_parameters.len != 0)) return null;
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
    defer if (targets.comparisons_left) |remaining| {
        remaining.* = comparisons;
    };
    // Index exact public identities once. Duplicate identities still decline;
    // the graph and contract checks below remain the semantic admission gate.
    var public: std.AutoHashMapUnmanaged(BindingKey, u32) = .empty;
    defer public.deinit(a);
    if (targets.progress) |value| value.stage = .public_index;
    for (right.bindings, 0..) |current, index| {
        if (index == 0 or !visible(current)) continue;
        if (comparisons == 0) return null;
        comparisons -= 1;
        const key = BindingKey.current(current) orelse return null;
        const entry = try public.getOrPut(a, key);
        if (entry.found_existing) {
            if (targets.progress) |value| {
                value.binding = @intCast(index);
                value.other = entry.value_ptr.*;
                value.unnamed = key.name == 0;
                value.kind = key.kind;
            }
            // Several imported scheme slots can name the same original
            // producer. Preserve their exact local slots only when both
            // immutable catalogs already agree on those producer identities.
            // Named ambiguity and moved duplicate slots still decline.
            if (key.name != 0 or left.bindings.len != right.bindings.len or !std.meta.eql(key, BindingKey.current(left.bindings[index]) orelse return null)) return null;
            const prior = entry.value_ptr.*;
            if (prior != unmapped and !std.meta.eql(key, BindingKey.current(left.bindings[prior]) orelse return null)) return null;
            entry.value_ptr.* = unmapped;
            continue;
        }
        entry.value_ptr.* = @intCast(index);
    }
    if (targets.progress) |value| value.stage = .public_match;
    for (left.bindings, 0..) |old, index| {
        if (index == 0 or !visible(old)) continue;
        if (comparisons == 0) return null;
        comparisons -= 1;
        if (targets.progress) |value| value.binding = @intCast(index);
        var key = BindingKey.current(old) orelse return null;
        // Imported schemes retain their original producer, translated through
        // an admitted relocation. Several producers can expose one spelling.
        if (old.kind == .external and old.external != null) key.target = targets.target(key.target) orelse return null;
        const found = public.get(key) orelse return null;
        const next: u32 = if (found == unmapped) next: {
            if (index >= right.bindings.len or !std.meta.eql(key, BindingKey.current(right.bindings[index]) orelse return null)) return null;
            break :next @intCast(index);
        } else found;
        if (used[next]) return null;
        used[next] = true;
        map.bindings[index] = next;
    }
    for (right.bindings, used, 0..) |value, matched, index| if (index != 0 and visible(value) and !matched) return null;

    if (targets.progress) |value| value.stage = .nominals;
    map.nominals = try a.alloc(u32, left.nominals.len);
    @memset(map.nominals, 0);
    const nominal_used = try a.alloc(bool, right.nominals.len);
    defer a.free(nominal_used);
    @memset(nominal_used, false);
    var nominals_index = (try namedCatalogIndex(a, right.nominals, true, &comparisons)) orelse return null;
    defer nominals_index.deinit(a);
    for (left.nominals, 0..) |old, index| {
        if (index == 0 or old.private) continue;
        if (comparisons == 0) return null;
        comparisons -= 1;
        const next = nominals_index.get(.{ .name = old.name, .identity = old.identity }) orelse return null;
        if (nominal_used[next]) return null;
        nominal_used[next] = true;
        map.nominals[index] = next;
    }
    for (right.nominals, nominal_used, 0..) |value, matched, index| if (index != 0 and !value.private and !matched) return null;
    if (targets.progress) |value| value.stage = .constructors;
    map.constructors = try a.alloc(u32, left.constructors.len);
    @memset(map.constructors, 0);
    const constructor_used = try a.alloc(bool, right.constructors.len);
    defer a.free(constructor_used);
    @memset(constructor_used, false);
    var constructor_index: std.AutoHashMapUnmanaged(ConstructorKey, u32) = .empty;
    defer constructor_index.deinit(a);
    for (right.constructors, 0..) |current, index| {
        if (index == 0 or current.nominal == 0 or right.nominals[current.nominal].private) continue;
        if (comparisons == 0) return null;
        comparisons -= 1;
        const slot = try constructor_index.getOrPut(a, .{ .parent = current.nominal, .tag = current.tag });
        if (slot.found_existing) return null;
        slot.value_ptr.* = @intCast(index);
    }
    for (left.constructors, 0..) |old, index| {
        if (index == 0 or old.nominal == 0 or old.nominal >= map.nominals.len or left.nominals[old.nominal].private) continue;
        const parent = map.nominals[old.nominal];
        if (parent == 0) return null;
        if (comparisons == 0) return null;
        comparisons -= 1;
        const next = constructor_index.get(.{ .parent = parent, .tag = old.tag }) orelse return null;
        if (constructor_used[next]) return null;
        constructor_used[next] = true;
        map.constructors[index] = next;
    }
    for (right.constructors, constructor_used, 0..) |value, matched, index| {
        if (index != 0 and value.nominal != 0 and !right.nominals[value.nominal].private and !matched) return null;
    }

    if (!privateContractsOnly(left) or !privateContractsOnly(right)) {
        if (targets.progress) |value| value.stage = .contracts;
        map.contracts = try a.alloc(u32, left.contracts.len);
        @memset(map.contracts, unmapped);
        const contract_used = try a.alloc(bool, right.contracts.len);
        defer a.free(contract_used);
        @memset(contract_used, false);
        var contracts_index = (try namedCatalogIndex(a, right.contracts, false, &comparisons)) orelse return null;
        defer contracts_index.deinit(a);
        for (left.contracts, 0..) |old, index| {
            if (old.private) continue;
            if (comparisons == 0) return null;
            comparisons -= 1;
            const next = contracts_index.get(.{ .name = old.name, .identity = old.identity }) orelse return null;
            if (contract_used[next]) return null;
            contract_used[next] = true;
            map.contracts[index] = next;
        }
        for (right.contracts, contract_used) |value, matched| if (!value.private and !matched) return null;
    }

    if (targets.progress) |value| value.stage = .implementations;
    map.implementations = try a.alloc(u32, left.implementations.len);
    @memset(map.implementations, unmapped);
    const implementation_used = try a.alloc(bool, right.implementations.len);
    defer a.free(implementation_used);
    @memset(implementation_used, false);
    var implementations_index = (try namedCatalogIndex(a, right.implementations, false, &comparisons)) orelse return null;
    defer implementations_index.deinit(a);
    for (left.implementations, 0..) |old, index| {
        if (old.private) continue;
        if (comparisons == 0) return null;
        comparisons -= 1;
        const next = implementations_index.get(.{ .name = old.name, .identity = old.identity }) orelse return null;
        if (implementation_used[next]) return null;
        implementation_used[next] = true;
        map.implementations[index] = next;
        const current = right.implementations[next];
        if (old.members.len != current.members.len) return null;
        for (left.implementation_members[old.members.start..][0..old.members.len], right.implementation_members[current.members.start..][0..current.members.len]) |from, to| {
            if (comparisons == 0) return null;
            comparisons -= 1;
            if (from.name != to.name or from.kind != to.kind) return null;
            if (from.kind != .value) continue;
            if (from.target.unit == 0 or from.target.binding == 0 or to.target.unit != from.target.unit or to.target.binding == 0) return null;
            if (from.target.unit != left.unit) {
                if (!std.meta.eql(targets.target(from.target) orelse return null, to.target)) return null;
                continue;
            }
            if (from.target.binding >= map.bindings.len or to.target.binding >= right.bindings.len) return null;
            const before = left.bindings[from.target.binding];
            const after = right.bindings[to.target.binding];
            // A public member's exact original implementation/member identity
            // owns this hidden method slot, just as an opaque parent owns its
            // private constructor. Never match arbitrary private functions by
            // their type or ordinal. The whole public recipe is checked below
            // before this unpublished map can be returned.
            if (before.private != after.private or before.kind != .global or after.kind != .global) return null;
            if (before.private) {
                const sources = targets.methods orelse return null;
                const role: methods.Role = .{ .implementation = old.identity, .member = from.name };
                const old_method = sources.before(sources.context, role, from.target.binding) orelse return null;
                const new_method = sources.after(sources.context, role, to.target.binding) orelse return null;
                if (old_method.flow != new_method.flow or !std.meta.eql(old_method.parameters, new_method.parameters) or (old_method.recipe == null) != (new_method.recipe == null)) return null;
                if (old_method.recipe) |recipe| {
                    if (recipe.arity != new_method.recipe.?.arity) return null;
                    const same = capabilities.equivalent(recipe.view(), recipe.root, new_method.recipe.?.view(), new_method.recipe.?.root) catch |err| switch (err) {
                        error.OutOfMemory => return error.OutOfMemory,
                        else => return null,
                    };
                    if (!same) return null;
                }
            }
            if (map.binding(from.target.binding)) |prior| {
                if (prior != to.target.binding) return null;
            } else {
                if (!before.private or before.name != 0 or after.name != 0 or used[to.target.binding]) return null;
                map.bindings[from.target.binding] = to.target.binding;
                used[to.target.binding] = true;
            }
        }
    }
    for (right.implementations, implementation_used) |value, matched| if (!value.private and !matched) return null;

    if (targets.progress) |value| value.stage = .graph;
    var graph = (try graphs.Match.init(a, &left.graph, &right.graph)) orelse return null;
    defer graph.deinit();
    var checker: Checker = .{ .left = left, .right = right, .graph = &graph, .map = map, .targets = targets };
    if (left.implementations.len != 0 or right.implementations.len != 0) {
        checker.remaining = 4096;
        graph.remaining = 4096;
    }
    defer checker.qualifications.deinit(a);
    checker.check() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Declined => return null,
    };
    map.qualifications = try checker.qualifications.toOwnedSlice(a);
    std.mem.sort(Qualification, map.qualifications, {}, Qualification.less);
    if (targets.progress) |value| value.stage = .checked;
    published = true;
    return map;
}

// Admitted private catalogs contain redacted tombstones. They confer no public
// authority and no external catalog position. Public recipes are compared
// separately; selected proof payloads retain ordinary checking.
fn privateContractsOnly(owner: *const PI.Interface) bool {
    for (owner.contracts) |contract| if (!contract.private) return false;
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
        try self.associated();
        try self.implementations();
        try self.memberTemplates();
    }
    fn implementations(self: *Checker) Error!void {
        // Every non-redacted flat slot must belong to a checked public recipe.
        inline for (.{ .{ "implementation_members", "members" }, .{ "implementation_predicates", "predicates" } }) |fields| {
            for (@field(self.left, fields[0]), 0..) |value, index| {
                try self.implementationSlot(self.left, fields[0], fields[1], value, index);
            }
            for (@field(self.right, fields[0]), 0..) |value, index| {
                try self.implementationSlot(self.right, fields[0], fields[1], value, index);
            }
        }
        for (self.left.implementations, 0..) |old, index| {
            if (old.private) continue;
            try self.work(0);
            const current = self.right.implementations[self.map.catalog(.implementation, @intCast(index)) orelse return error.Declined];
            if (old.private != current.private or old.name != current.name or old.declaration != current.declaration or !std.meta.eql(old.identity, current.identity) or !std.meta.eql(old.contract, current.contract) or old.parameter_names.len != current.parameter_names.len or old.row_parameter_names.len != current.row_parameter_names.len) return error.Declined;
            try self.graph.typeList(old.head, current.head);
            try self.graph.typeList(old.variables, current.variables);
            try self.graph.rowVariables(old.row_variables, current.row_variables);
            try self.graph.rowList(old.row_parameters, current.row_parameters);
            if (old.predicates.len != current.predicates.len or old.members.len != current.members.len) return error.Declined;
            for (self.left.implementation_predicates[old.predicates.start..][0..old.predicates.len], self.right.implementation_predicates[current.predicates.start..][0..current.predicates.len]) |from, to| try self.obligation(from, to);
            for (self.left.implementation_members[old.members.start..][0..old.members.len], self.right.implementation_members[current.members.start..][0..current.members.len]) |from, to| {
                try self.work(0);
                if (from.name != to.name or from.kind != to.kind) return error.Declined;
                try self.graph.ty(from.root, to.root);
                if (from.kind == .type_) {
                    if (!std.meta.eql(from.target, to.target)) return error.Declined;
                } else if (from.target.unit == self.left.unit) {
                    if (to.target.unit != self.right.unit or (self.map.binding(from.target.binding) orelse return error.Declined) != to.target.binding) return error.Declined;
                } else if (!std.meta.eql(self.targets.target(from.target) orelse return error.Declined, to.target)) return error.Declined;
            }
            if ((old.origin_span == null) != (current.origin_span == null)) return error.Declined;
            if (old.origin_span) |before| try self.provenance(old.identity.unit, before, current.origin_span.?);
        }
    }
    fn implementationSlot(self: *Checker, owner: *const PI.Interface, comptime table: []const u8, comptime field: []const u8, value: anytype, index: usize) Error!void {
        if (comptime std.mem.eql(u8, table, "implementation_members")) {
            if (value.name == 0 and value.root == 0 and value.target.unit == 0 and value.target.binding == 0) return;
        } else {
            const inert: T.Obligation = .{ .ty = 0, .kind = .type_rep, .source = 0, .explicit = true };
            if (std.meta.eql(value, inert)) return;
        }
        var claims: usize = 0;
        for (owner.implementations) |header| {
            try self.work(0);
            const span = @field(header, field);
            if (!header.private and index >= span.start and index - span.start < span.len) claims += 1;
        }
        if (claims != 1) return error.Declined;
    }
    fn memberTemplates(self: *Checker) Error!void {
        if (self.left.member_templates.len != self.right.member_templates.len) return error.Declined;
        const used = try self.graph.allocator.alloc(bool, self.right.member_templates.len);
        defer self.graph.allocator.free(used);
        @memset(used, false);
        for (self.left.member_templates) |old| {
            const binding = self.map.binding(old.binding) orelse return error.Declined;
            var matched: ?usize = null;
            for (self.right.member_templates, 0..) |current, index| {
                try self.work(0);
                if (current.binding != binding or old.name != current.name or !std.meta.eql(old.contract, current.contract)) continue;
                if (matched != null or used[index]) return error.Declined;
                matched = index;
            }
            const index = matched orelse return error.Declined;
            used[index] = true;
            try self.graph.typeList(old.arguments, self.right.member_templates[index].arguments);
        }
        for (used) |matched| if (!matched) return error.Declined;
    }
    fn associated(self: *Checker) Error!void {
        if (self.left.associated.len != self.right.associated.len) return error.Declined;
        if (self.left.associated.len == 0) return;
        const used = try self.graph.allocator.alloc(bool, self.right.associated.len);
        defer self.graph.allocator.free(used);
        @memset(used, false);
        for (self.left.associated) |old| {
            const binding = self.map.binding(old.binding) orelse return error.Declined;
            var matched: ?usize = null;
            for (self.right.associated, 0..) |current, index| {
                try self.work(0);
                if (binding != current.binding or old.member != current.member or old.operator != current.operator or !std.meta.eql(old.identity, current.identity)) continue;
                if (matched != null or used[index]) return error.Declined;
                matched = index;
            }
            used[matched orelse return error.Declined] = true;
        }
        for (used) |matched| if (!matched) return error.Declined;
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
            // Only a public binding or a complete public-member relationship
            // establishes this target. Lexical formals and private slots
            // without that source-owned relationship remain unadmitted.
            if (from.identity.unit == 0 or from.identity.unit != self.left.unit or to.identity.unit != self.right.unit) return error.Declined;
            if ((self.map.binding(from.identity.decl) orelse return error.Declined) != to.identity.decl) return error.Declined;
        } else if (!std.meta.eql(from.identity, to.identity)) return error.Declined;
        inline for (.{ "ty", "result", "other", "signature" }) |field| try self.graph.ty(@field(from, field), @field(to, field));
        if ((from.qualification_span == null) != (to.qualification_span == null)) return error.Declined;
        const before = from.qualification_span orelse return;
        const after = to.qualification_span.?;
        if (before.start > before.end or after.start > after.end) return error.Declined;
        if (from.explicit) {
            try self.provenance(from.qualification_unit, before, after);
        } else if (!std.meta.eql(self.targets.qualification(from.qualification_unit, before), after)) return error.Declined;
    }
    fn provenance(self: *Checker, unit: u32, before: ast.Span, after: ast.Span) Error!void {
        if (before.start > before.end or after.start > after.end) return error.Declined;
        if (unit != self.left.unit) {
            if (!std.meta.eql(self.targets.qualification(unit, before), after)) return error.Declined;
            return;
        }
        for (self.qualifications.items) |prior| {
            try self.work(0);
            if (std.meta.eql(prior.before, before)) {
                if (!std.meta.eql(prior.after, after)) return error.Declined;
                return;
            }
            if (std.meta.eql(prior.after, after)) return error.Declined;
        }
        try self.qualifications.append(self.graph.allocator, .{ .before = before, .after = after });
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

fn wideBindingMapScenario(a: A) !void {
    var nodes = [_]T.Node{ .{ .tag = .absent }, .{ .tag = .u32 }, .{ .tag = .f32 } };
    const inert: PI.Binding = .{ .private = true, .name = 0, .kind = .global, .named_function = false, .ty = 0, .scheme = .{}, .external = null };
    var before: [301]PI.Binding = @splat(inert);
    var after: [302]PI.Binding = @splat(inert);
    for (1..before.len) |i| {
        before[i] = .{ .name = @intCast(i), .kind = .global, .named_function = false, .ty = 1, .scheme = .{ .root = 1 }, .external = null };
        after[after.len - i] = before[i];
    }
    const inert_nominal: PI.Nominal = .{ .private = true, .identity = .{ .unit = 0, .decl = 0 }, .name = 0, .parameters = .{}, .variables = .{} };
    var old_nominals: [301]PI.Nominal = @splat(inert_nominal);
    var new_nominals = old_nominals;
    for (1..old_nominals.len) |i| {
        old_nominals[i] = .{ .identity = .{ .unit = 1, .decl = @intCast(i) }, .name = @intCast(i), .parameters = .{}, .variables = .{}, .alias = 1 };
        new_nominals[old_nominals.len - i] = old_nominals[i];
    }
    const old: PI.Interface = .{
        .unit = 1,
        .graph = .{ .nodes = &nodes, .extra = &.{}, .rows = &.{}, .labels = &.{}, .operations = &.{}, .row_variable_count = 0 },
        .patterns = .{ .nodes = &.{}, .extra = &.{} },
        .bindings = &before,
        .obligations = &.{},
        .obligation_spans = &.{},
        .nominals = &old_nominals,
        .constructors = &.{},
        .effect_families = &.{},
        .effect_templates = &.{},
        .associated = &.{},
    };
    var current = old;
    current.bindings = &after;
    current.nominals = &new_nominals;
    var remaining: usize = 0;
    var map = (try compare(a, &old, &current, .{ .comparisons_left = &remaining })) orelse return error.MissingBindingMap;
    defer map.deinit(a);
    try std.testing.expect(remaining > 60_000);
    for (1..before.len) |i| try std.testing.expectEqual(@as(?u32, @intCast(after.len - i)), map.binding(@intCast(i)));
    for (1..old_nominals.len) |i| try std.testing.expectEqual(@as(?u32, @intCast(old_nominals.len - i)), map.catalog(.nominal, @intCast(i)));
    // The former quadratic walk exhausted its budget before reaching the last
    // entries. All of them must now be checked, including negative cases.
    new_nominals[1].alias = 2;
    var changed_alias = try compare(a, &old, &current, .{});
    defer if (changed_alias) |*value| value.deinit(a);
    try std.testing.expect(changed_alias == null);
    new_nominals[1].alias = 1;
    after[2].ty = 2;
    var changed = try compare(a, &old, &current, .{});
    defer if (changed) |*value| value.deinit(a);
    try std.testing.expect(changed == null);
    after[2].ty = 1;
    after[2].name = after[3].name;
    var duplicate = try compare(a, &old, &current, .{});
    defer if (duplicate) |*value| value.deinit(a);
    try std.testing.expect(duplicate == null);
    after[2].name = 999;
    var missing = try compare(a, &old, &current, .{});
    defer if (missing) |*value| value.deinit(a);
    try std.testing.expect(missing == null);
}

test "frontend relocation indexes wide reordered catalogs and rejects late changes duplicates and missing names through OOM" {
    try wideBindingMapScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, wideBindingMapScenario, .{});
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
    old_goals[0].identity.unit = 1;
    before[1] = callee;
    var stable = before;
    current = old;
    current.bindings = &stable;
    var duplicates = (try compare(a, &old, &current, .{})) orelse return error.MissingStableImportedSlots;
    defer duplicates.deinit(a);
    try std.testing.expectEqual(@as(?u32, 1), duplicates.binding(1));
    try std.testing.expectEqual(@as(?u32, 2), duplicates.binding(2));
    stable[1].ty = 1;
    var changed_duplicate = try compare(a, &old, &current, .{});
    defer if (changed_duplicate) |*value| value.deinit(a);
    try std.testing.expect(changed_duplicate == null);
    stable[1] = callee;
    stable[1].external.?.binding = 3;
    var changed_producer = try compare(a, &old, &current, .{});
    defer if (changed_producer) |*value| value.deinit(a);
    try std.testing.expect(changed_producer == null);
    // The same imported spelling may identify different original producers.
    // Those targets, and the caller's relocated callee edge, remain exact.
    before[1].name = 8;
    before[1].external.?.binding = 4;
    before[2].name = 8;
    stable = before;
    stable[1] = before[2];
    stable[2] = before[1];
    new_goals = old_goals;
    new_goals[0].identity.decl = 1;
    current.obligations = &new_goals;
    var named_imports = (try compare(a, &old, &current, .{})) orelse return error.MissingNamedProducerMap;
    defer named_imports.deinit(a);
    try std.testing.expectEqual(@as(?u32, 2), named_imports.binding(1));
    try std.testing.expectEqual(@as(?u32, 1), named_imports.binding(2));
    stable[1].external.?.binding = 4;
    var ambiguous = try compare(a, &old, &current, .{});
    defer if (ambiguous) |*value| value.deinit(a);
    try std.testing.expect(ambiguous == null);
}

test "frontend relocation shared public callee schemes retain original targets and reject formal or private substitutions through OOM" {
    try sharedCalleeMapScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, sharedCalleeMapScenario, .{});
}

fn associatedMapScenario(a: A) !void {
    var nodes = [_]T.Node{ .{ .tag = .absent }, .{ .tag = .u32 }, .{ .tag = .function, .a = 1, .b = 1 } };
    var rows = [_]T.Effects.Row{.{ .labels = .{}, .tail = .closed }};
    const inert: PI.Binding = .{ .private = true, .name = 0, .kind = .global, .named_function = false, .ty = 0, .scheme = .{}, .external = null };
    const method: PI.Binding = .{ .name = 7, .kind = .global, .named_function = true, .ty = 2, .scheme = .{ .root = 2 }, .external = null };
    var helper = method;
    helper.name = 9;
    var old_bindings = [_]PI.Binding{ inert, inert, method, helper };
    var new_bindings = [_]PI.Binding{ inert, inert, inert, method, helper };
    var before = [_]PI.Associated{.{ .identity = .{ .unit = 0, .decl = T.u32_type }, .member = 8, .operator = .none, .binding = 2 }};
    var after = before;
    after[0].binding = 3;
    const old: PI.Interface = .{
        .unit = 1,
        .graph = .{ .nodes = &nodes, .extra = &.{}, .rows = &rows, .labels = &.{}, .operations = &.{}, .row_variable_count = 0 },
        .patterns = .{ .nodes = &.{}, .extra = &.{} },
        .bindings = &old_bindings,
        .obligations = &.{},
        .obligation_spans = &.{},
        .nominals = &.{},
        .constructors = &.{},
        .effect_families = &.{},
        .effect_templates = &.{},
        .associated = &before,
    };
    var current = old;
    current.bindings = &new_bindings;
    current.associated = &after;
    var map = (try compare(a, &old, &current, .{})) orelse return error.MissingAssociatedMap;
    defer map.deinit(a);
    try std.testing.expectEqual(@as(?u32, 3), map.binding(2));
    // Equal function types cannot authorize a different public relationship.
    after[0].binding = 4;
    var retargeted = try compare(a, &old, &current, .{});
    defer if (retargeted) |*value| value.deinit(a);
    try std.testing.expect(retargeted == null);
    after[0].binding = 3;
    after[0].operator = .add;
    var changed_operator = try compare(a, &old, &current, .{});
    defer if (changed_operator) |*value| value.deinit(a);
    try std.testing.expect(changed_operator == null);
    after[0].operator = .none;
    after[0].identity.decl = T.f32_type;
    var changed_owner = try compare(a, &old, &current, .{});
    defer if (changed_owner) |*value| value.deinit(a);
    try std.testing.expect(changed_owner == null);
    after[0].identity.decl = T.u32_type;
    var duplicate = [_]PI.Associated{ after[0], after[0] };
    current.associated = &duplicate;
    var duplicated = try compare(a, &old, &current, .{});
    defer if (duplicated) |*value| value.deinit(a);
    try std.testing.expect(duplicated == null);
}

test "frontend relocation associated relationships keep exact receiver member operator and original targets through OOM" {
    try associatedMapScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, associatedMapScenario, .{});
}

fn implementationMapScenario(a: A) !void {
    var nodes = [_]T.Node{ .{ .tag = .absent }, .{ .tag = .u32 }, .{ .tag = .f32 }, .{ .tag = .function, .a = 1, .b = 1 }, .{ .tag = .variable, .a = 0 }, .{ .tag = .function, .a = 4, .b = 1 } };
    var rows = [_]T.Effects.Row{.{ .labels = .{}, .tail = .closed }};
    var extra = [_]u32{ 1, 4, 11 };
    var new_extra = extra;
    const inert: PI.Binding = .{ .private = true, .name = 0, .kind = .global, .named_function = false, .ty = 0, .scheme = .{}, .external = null };
    const member: PI.Binding = .{ .name = 7, .kind = .global, .named_function = true, .ty = 5, .scheme = .{ .root = 5, .variables = .{ .start = 1, .len = 1 } }, .external = null };
    var old_bindings = [_]PI.Binding{ inert, inert, member };
    var new_bindings = [_]PI.Binding{ inert, inert, inert, member };
    const contract: PI.Contract = .{ .identity = .{ .unit = 1, .decl = T.opaque_name_bit | 8 }, .name = 8, .parameters = .{ .start = 1, .len = 1 }, .variables = .{ .start = 1, .len = 1 }, .parameter_names = .{ .start = 2, .len = 1 }, .members = .{ .start = 0, .len = 1 }, .requires_implementation = true };
    var contracts = [_]PI.Contract{contract};
    var contract_members = [_]PI.ContractMember{.{ .contract = contract.identity, .name = 15, .kind = .value, .root = 5 }};
    const before: ast.Span = .{ .start = 10, .end = 20 };
    const after: ast.Span = .{ .start = 40, .end = 50 };
    const implementation: PI.Implementation = .{ .origin_span = before, .identity = .{ .unit = 1, .decl = T.opaque_name_bit | 9 }, .name = 9, .contract = contract.identity, .head = .{ .start = 0, .len = 1 }, .members = .{ .start = 0, .len = 1 } };
    var old_implementations = [_]PI.Implementation{implementation};
    var new_implementations = [_]PI.Implementation{ .{ .private = true, .identity = .{ .unit = 1, .decl = T.opaque_name_bit | 10 }, .name = 0, .contract = contract.identity }, implementation };
    new_implementations[1].origin_span = after;
    var old_members = [_]PI.ImplementationMember{.{ .name = 15, .kind = .value, .root = 3, .target = .{ .unit = 1, .binding = 1 } }};
    var new_members = old_members;
    new_members[0].target.binding = 2;
    var old_templates = [_]PI.MemberTemplate{.{ .binding = 2, .contract = contract.identity, .name = 15, .arguments = .{ .start = 1, .len = 1 } }};
    var new_templates = old_templates;
    new_templates[0].binding = 3;
    const old: PI.Interface = .{
        .unit = 1,
        .graph = .{ .nodes = &nodes, .extra = &extra, .rows = &rows, .labels = &.{}, .operations = &.{}, .row_variable_count = 0 },
        .patterns = .{ .nodes = &.{}, .extra = &.{} },
        .bindings = &old_bindings,
        .obligations = &.{},
        .obligation_spans = &.{},
        .nominals = &.{},
        .constructors = &.{},
        .effect_families = &.{},
        .effect_templates = &.{},
        .associated = &.{},
        .contracts = &contracts,
        .contract_members = &contract_members,
        .implementations = &old_implementations,
        .implementation_members = &old_members,
        .member_templates = &old_templates,
    };
    var current = old;
    current.graph.extra = &new_extra;
    current.bindings = &new_bindings;
    current.implementations = &new_implementations;
    current.implementation_members = &new_members;
    current.member_templates = &new_templates;
    const Source = struct {
        before: methods.Header = .{ .flow = .unknown, .parameters = .{}, .recipe = null },
        after: methods.Header = .{ .flow = .unknown, .parameters = .{}, .recipe = null },
        authorized: bool = true,
        fn readBefore(raw: *anyopaque, role: methods.Role, binding: u32) ?methods.Header {
            const self: *@This() = @ptrCast(@alignCast(raw));
            if (binding != 1 or role.implementation.unit != 1 or role.implementation.decl != T.opaque_name_bit | 9 or role.member != 15) return null;
            return self.before;
        }
        fn readAfter(raw: *anyopaque, role: methods.Role, binding: u32) ?methods.Header {
            const self: *@This() = @ptrCast(@alignCast(raw));
            if (!self.authorized or binding != 2 or role.implementation.unit != 1 or role.implementation.decl != T.opaque_name_bit | 9 or role.member != 15) return null;
            return self.after;
        }
        fn view(self: *@This()) methods.Sources {
            return .{ .context = self, .before = readBefore, .after = readAfter };
        }
    };
    var source: Source = .{};
    const targets: Targets = .{ .methods = source.view() };
    var map = (try compare(a, &old, &current, targets)) orelse return error.MissingImplementationMap;
    defer map.deinit(a);
    try std.testing.expectEqual(@as(?u32, 1), map.catalog(.implementation, 0));
    try std.testing.expectEqual(@as(?u32, 2), map.binding(1));
    try std.testing.expectEqual(@as(?u32, 3), map.binding(2));
    try std.testing.expectEqual(after, map.qualification(before));
    var no_sources = try compare(a, &old, &current, .{});
    defer if (no_sources) |*value| value.deinit(a);
    try std.testing.expect(no_sources == null);
    source.after.flow = .identity;
    var changed_flow = try compare(a, &old, &current, targets);
    defer if (changed_flow) |*value| value.deinit(a);
    try std.testing.expect(changed_flow == null);
    source.after.flow = .unknown;
    source.after.parameters = .init(1, 0);
    var changed_parameters = try compare(a, &old, &current, targets);
    defer if (changed_parameters) |*value| value.deinit(a);
    try std.testing.expect(changed_parameters == null);
    source.after.parameters = .{};
    var capability_nodes = [_]capabilities.Term{ .{ .tag = .empty }, .{ .tag = .parameter, .a = 0 } };
    source.before.recipe = .{ .arity = 1, .root = 1, .nodes = &capability_nodes, .words = &.{} };
    source.after.recipe = .{ .arity = 1, .root = 0, .nodes = &capability_nodes, .words = &.{} };
    var changed_capability = try compare(a, &old, &current, targets);
    defer if (changed_capability) |*value| value.deinit(a);
    try std.testing.expect(changed_capability == null);
    source.before.recipe = null;
    source.after.recipe = null;
    source.authorized = false;
    var wrong_method = try compare(a, &old, &current, targets);
    defer if (wrong_method) |*value| value.deinit(a);
    try std.testing.expect(wrong_method == null);
    source.authorized = true;
    // Same-layout scalar heads, another original producer, changed public
    // member names and missing method slots cannot confer this relationship.
    new_extra[0] = 2;
    var changed_head = try compare(a, &old, &current, targets);
    defer if (changed_head) |*value| value.deinit(a);
    try std.testing.expect(changed_head == null);
    new_extra[0] = 1;
    new_members[0].target.unit = 2;
    var changed_producer = try compare(a, &old, &current, targets);
    defer if (changed_producer) |*value| value.deinit(a);
    try std.testing.expect(changed_producer == null);
    new_members[0].target.unit = 1;
    new_members[0].name = 16;
    var changed_member = try compare(a, &old, &current, targets);
    defer if (changed_member) |*value| value.deinit(a);
    try std.testing.expect(changed_member == null);
    new_members[0].name = 15;
    new_members[0].target.binding = 0;
    var missing = try compare(a, &old, &current, targets);
    defer if (missing) |*value| value.deinit(a);
    try std.testing.expect(missing == null);
    new_members[0].target.binding = 2;
    new_implementations[0] = new_implementations[1];
    var duplicated = try compare(a, &old, &current, targets);
    defer if (duplicated) |*value| value.deinit(a);
    try std.testing.expect(duplicated == null);
}

test "frontend relocation bounded implementation catalogs preserve original member relationships and provenance through OOM" {
    try implementationMapScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, implementationMapScenario, .{});
}
