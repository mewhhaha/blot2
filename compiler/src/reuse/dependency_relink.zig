//! Relink only decoded, unpublished owners. Declaration slots stay positional;
//! owned field spellings keep physical ordering stable across dictionaries.
const std = @import("std");
const symbols = @import("../parse/symbols.zig");
const D = @import("frozen_dependency.zig");
const PI = @import("principal_interface.zig");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const Allocator = std.mem.Allocator;
const slots = @import("dependency_symbol_slots.zig");
pub const Error = Allocator.Error || error{ InvalidArtifact, NoncanonicalSymbols, SymbolLimit };

/// Decoded-artifact relocation. Callers validate every ID before rewriting.
const Dictionary = struct {
    names: []const u32,
    units: []const u32,
    fn symbol(self: Dictionary, id: u32) u32 {
        return self.names[id];
    }
    fn unit(self: Dictionary, id: u32) u32 {
        return if (id == 0 or id == std.math.maxInt(u32)) id else self.units[id - 1];
    }
};
/// Fresh-freeze renumbering. Symbol IDs are unchanged; each unit must name a
/// retained producer, so the excluded entry (mapped to zero) and out-of-range
/// IDs record a rejection instead of becoming the current-unit context.
const Retained = struct {
    units: []const u32,
    rejected: *bool,
    fn symbol(_: Retained, id: u32) u32 {
        return id;
    }
    fn unit(self: Retained, id: u32) u32 {
        if (id == 0 or id == std.math.maxInt(u32)) return id;
        if (id <= self.units.len and self.units[id - 1] != 0) return self.units[id - 1];
        self.rejected.* = true;
        return id;
    }
};
fn identity(map: anytype, value: *T.NominalIdentity) void {
    value.unit = map.unit(value.unit);
    if (value.unit != 0 and value.unit != std.math.maxInt(u32) and value.decl & T.opaque_name_bit != 0) value.decl = T.opaque_name_bit | map.symbol(value.decl & ~T.opaque_name_bit);
}
fn target(map: anytype, value: anytype) void {
    value.unit = map.unit(value.unit);
}
fn typeUnits(nodes: []T.Node, map: anytype) void {
    for (nodes) |*node| switch (node.tag) {
        .scoped => node.b = map.unit(node.b),
        .instance_selection, .instance_version => node.a = map.unit(node.a),
        .nominal, .projection, .type_constructor => {
            node.a = map.unit(node.a);
            if (node.a != 0 and node.a != std.math.maxInt(u32) and node.b & T.opaque_name_bit != 0) node.b = T.opaque_name_bit | map.symbol(node.b & ~T.opaque_name_bit);
        },
        else => {},
    };
}

fn implementations(owner: anytype, map: anytype) void {
    for (owner.implementations) |*value| {
        identity(map, &value.identity);
        identity(map, &value.contract);
        value.name = map.symbol(value.name);
    }
    for (owner.implementation_members) |*value| {
        value.name = map.symbol(value.name);
        target(map, &value.target);
    }
    for (owner.member_templates) |*value| {
        identity(map, &value.contract);
        value.name = map.symbol(value.name);
    }
    for (owner.selected_members) |*value| {
        value.name = map.symbol(value.name);
        target(map, &value.target);
    }
    for (owner.selected_proofs) |*value| {
        target(map, &value.predicate_target);
        value.context = map.unit(value.context);
        identity(map, &value.implementation);
        identity(map, &value.contract);
        identity(map, &value.predicate.identity);
        value.predicate.name = map.symbol(value.predicate.name);
        value.predicate.qualification_unit = map.unit(value.predicate.qualification_unit);
    }
}
/// Renumber a freshly frozen principal interface like moduleUnits.
pub fn interfaceUnits(owner: *PI.Interface, units: []const u32) error{InvalidArtifact}!void {
    var rejected = false;
    interfaceWith(owner, Retained{ .units = units, .rejected = &rejected });
    if (rejected) return error.InvalidArtifact;
}
fn interfaceWith(owner: *PI.Interface, map: anytype) void {
    capabilityNodes(owner.capability_contracts.nodes, map);
    implementations(owner, map);
    owner.unit = map.unit(owner.unit);
    typeUnits(owner.graph.nodes, map);
    for (owner.graph.quantifier_obligations) |*goal| {
        goal.name = map.symbol(goal.name);
        identity(map, &goal.identity);
        goal.qualification_unit = map.unit(goal.qualification_unit);
    }
    for (owner.graph.operations) |*operation| {
        identity(map, &operation.identity);
        operation.instance.unit = map.unit(operation.instance.unit);
    }
    for (owner.bindings) |*binding| {
        binding.name = map.symbol(binding.name);
        if (binding.external) |*external| target(map, external);
    }
    for (owner.obligations) |*obligation| {
        obligation.name = map.symbol(obligation.name);
        identity(map, &obligation.identity);
        obligation.qualification_unit = map.unit(obligation.qualification_unit);
    }
    for (owner.nominals) |*nominal| {
        identity(map, &nominal.identity);
        nominal.name = map.symbol(nominal.name);
    }
    for (owner.contracts) |*contract| {
        identity(map, &contract.identity);
        contract.name = map.symbol(contract.name);
    }
    for (owner.contract_members) |*member| {
        identity(map, &member.contract);
        member.name = map.symbol(member.name);
    }
    for (owner.contract_predicates) |*predicate| {
        predicate.name = map.symbol(predicate.name);
        identity(map, &predicate.identity);
        predicate.qualification_unit = map.unit(predicate.qualification_unit);
    }
    for (owner.implementation_predicates) |*predicate| {
        predicate.name = map.symbol(predicate.name);
        identity(map, &predicate.identity);
        predicate.qualification_unit = map.unit(predicate.qualification_unit);
    }
    for (owner.constructors) |*constructor| {
        identity(map, &constructor.identity);
        constructor.name = map.symbol(constructor.name);
    }
    for (owner.effect_families) |*family| {
        identity(map, &family.identity);
        family.name = map.symbol(family.name);
    }
    for (owner.effect_templates) |*operation| {
        identity(map, &operation.identity);
        operation.name = map.symbol(operation.name);
    }
    for (owner.associated) |*method| {
        identity(map, &method.identity);
        method.member = map.symbol(method.member);
    }
}

fn module(owner: *core.Module, names: []const u32, units: []const u32) void {
    for (owner.field_names) |*field| field.symbol = names[field.symbol];
    std.mem.sortUnstable(core.FieldName, owner.field_names, {}, struct {
        fn less(_: void, left: core.FieldName, right: core.FieldName) bool {
            return left.symbol < right.symbol;
        }
    }.less);
    moduleWith(owner, Dictionary{ .names = names, .units = units });
}
/// Renumber a freshly frozen source module to dense artifact units in place.
/// Symbols, field order and every non-unit word stay untouched, so complete
/// Core validation of the result decides exactly what validating the source
/// numbering would. A unit naming the excluded entry or no source module
/// rejects; the owner is then partially renumbered and must be discarded.
pub fn moduleUnits(owner: *core.Module, units: []const u32) error{InvalidArtifact}!void {
    var rejected = false;
    moduleWith(owner, Retained{ .units = units, .rejected = &rejected });
    if (rejected) return error.InvalidArtifact;
}
fn moduleWith(owner: *core.Module, map: anytype) void {
    capabilityNodes(owner.capability_contracts.nodes, map);
    implementations(owner, map);
    owner.unit = map.unit(owner.unit);
    typeUnits(owner.types.nodes, map);
    for (owner.types.quantifier_obligations) |*goal| {
        goal.name = map.symbol(goal.name);
        identity(map, &goal.identity);
        goal.qualification_unit = map.unit(goal.qualification_unit);
    }
    for (owner.types.operations) |*operation| {
        identity(map, &operation.identity);
        operation.instance.unit = map.unit(operation.instance.unit);
    }
    for (owner.nodes) |*node| switch (node.tag) {
        .associated => node.c = map.symbol(node.c),
        .result_associated => node.b = map.symbol(node.b),
        else => {},
    };
    for (owner.bindings) |*binding| target(map, &binding.target);
    for (owner.references) |*reference| target(map, reference);
    for (owner.dependency_references) |*reference| target(map, reference);
    for (owner.erased_declaration_references) |*reference| target(map, &reference.target);
    for (owner.dependency_members) |*member| member.name = map.symbol(member.name);
    for (owner.calls) |*call| target(map, &call.target);
    for (owner.obligations) |*obligation| {
        obligation.name = map.symbol(obligation.name);
        identity(map, &obligation.identity);
        obligation.qualification_unit = map.unit(obligation.qualification_unit);
    }
    for (owner.contracts) |*contract| {
        identity(map, &contract.identity);
        contract.name = map.symbol(contract.name);
    }
    for (owner.contract_members) |*member| {
        identity(map, &member.contract);
        member.name = map.symbol(member.name);
    }
    for (owner.nominals) |*nominal| identity(map, &nominal.identity);
    for (owner.operation_names) |*operation| identity(map, &operation.identity);
    for (owner.constructors) |*constructor| identity(map, &constructor.identity);
    for (owner.projections) |*projection| {
        identity(map, &projection.nominal);
        projection.field = map.symbol(projection.field);
    }
    for (owner.associated) |*method| {
        identity(map, &method.identity);
        method.member = map.symbol(method.member);
        target(map, &method.target);
    }
    for (owner.resolver_ops) |*operation| {
        operation.member = map.symbol(operation.member);
        target(map, &operation.method);
    }
    for (owner.operation_values) |*operation| {
        identity(map, &operation.identity);
        operation.instance.unit = map.unit(operation.instance.unit);
    }
}

/// The caller validates all payload IDs before this transaction. Failure to
/// admit an injective dictionary leaves the decoded artifact untouched.
pub fn relink(allocator: Allocator, value: *D.FrozenDependency, pool: *symbols.Pool, units: []const u32) Error!void {
    if (units.len != value.modules.len or value.symbols.len == 0 or value.symbols.len > std.math.maxInt(u32)) return error.InvalidArtifact;
    for (units, 0..) |id, index| {
        if (id == 0 or id == std.math.maxInt(u32)) return error.InvalidArtifact;
        if (std.mem.findScalar(u32, units[0..index], id) != null) return error.InvalidArtifact;
    }
    // All new names are private until admission. A declined dictionary or an
    // allocation failure cannot alter any published caller symbol identity.
    var candidate: symbols.Pool = .{};
    defer candidate.deinit(allocator);
    for (0..pool.entries.items.len) |index| _ = try candidate.intern(allocator, pool.get(@intCast(index + 1)));
    const names = try allocator.alloc(u32, value.symbols.len);
    defer allocator.free(names);
    if (value.symbols[0].text.len != 0) return error.InvalidArtifact;
    names[0] = 0;
    for (value.symbols[1..], names[1..]) |old, *name| {
        name.* = try candidate.intern(allocator, old.text);
    }
    // The current principal/Core format stores source field positions, not
    // canonical semantic evidence or emitted layouts. Rewriting names must
    // therefore keep every list in place, while retaining exact name identity.
    var increasing = true;
    for (names[1..], 1..) |name, index| if (name <= names[index - 1]) {
        increasing = false;
        break;
    };
    if (!increasing) {
        const seen = try allocator.alloc(bool, candidate.entries.items.len + 1);
        defer allocator.free(seen);
        @memset(seen, false);
        for (names[1..]) |name| {
            if (name == 0 or seen[name]) return error.InvalidArtifact;
            seen[name] = true;
        }
    }
    const word_slots = try allocator.alloc(slots.Slots, value.modules.len);
    defer allocator.free(word_slots);
    var initialized: usize = 0;
    defer for (word_slots[0..initialized]) |*entry| entry.deinit(allocator);
    for (value.modules, word_slots) |*owner, *entry| {
        entry.* = try slots.collect(allocator, owner);
        initialized += 1;
        inline for (.{ .{ "interface_types", "graph" }, .{ "patterns", "patterns" } }) |pair| {
            const words = @field(owner.interface, pair[1]).extra;
            for (words, @field(entry, pair[0])) |word, role| if (role == 1 and word >= names.len) return error.InvalidArtifact;
        }
        for (owner.core.types.extra, entry.core_types) |word, role| if (role == 1 and word >= names.len) return error.InvalidArtifact;
        for (owner.interface.capability_contracts.words, entry.interface_capabilities) |word, role| if (role == 1 and word >= names.len) return error.InvalidArtifact;
        for (owner.core.capability_contracts.words, entry.core_capabilities) |word, role| if (role == 1 and word >= names.len) return error.InvalidArtifact;
        for ([_]@import("../check/capability_contracts.zig").Collection{ owner.interface.capability_contracts, owner.core.capability_contracts }) |collection| {
            for (collection.nodes) |node| if (node.tag == .project and node.c == @backingInt(@import("../check/capability_contracts.zig").Projection.field) and node.b >= names.len) return error.InvalidArtifact;
        }
    }
    // Everything below is infallible on the previously validated owner.
    std.mem.swap(symbols.Pool, pool, &candidate);
    const map: Dictionary = .{ .names = names, .units = units };
    for (value.modules, word_slots) |*owner, roles| {
        slots.rewrite(owner.interface.graph.extra, roles.interface_types, names);
        slots.rewrite(owner.interface.patterns.extra, roles.patterns, names);
        slots.rewrite(owner.core.types.extra, roles.core_types, names);
        slots.rewrite(owner.interface.capability_contracts.words, roles.interface_capabilities, names);
        slots.rewrite(owner.core.capability_contracts.words, roles.core_capabilities, names);
        interfaceWith(&owner.interface, map);
        module(&owner.core, names, units);
        for (owner.imports) |*dependency| dependency.* = map.unit(dependency.*);
        for (owner.source_imports) |*request| request.target = map.unit(request.target);
        for (owner.exports) |*exported| {
            exported.name = map.symbol(exported.name);
            target(map, &exported.target);
        }
        for (owner.fixities) |*fixity| {
            fixity.operator = map.symbol(fixity.operator);
            fixity.target = map.symbol(fixity.target);
            target(map, &fixity.producer);
        }
    }
}

fn capabilityNodes(nodes: []@import("../check/capability_contracts.zig").Term, map: anytype) void {
    for (nodes) |*node| if (node.tag == .project and node.c == @backingInt(@import("../check/capability_contracts.zig").Projection.field)) {
        node.b = map.symbol(node.b);
    };
}
