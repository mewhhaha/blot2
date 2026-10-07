//! Relink only decoded, unpublished owners. Declaration slots stay positional;
//! owned field spellings keep physical ordering stable across dictionaries.
const std = @import("std");
const symbols = @import("symbols.zig");
const D = @import("frozen_dependency.zig");
const PI = @import("principal_interface.zig");
const core = @import("core.zig");
const T = @import("types.zig");
const Allocator = std.mem.Allocator;
const slots = @import("dependency_symbol_slots.zig");
pub const Error = Allocator.Error || error{ InvalidArtifact, NoncanonicalSymbols, SymbolLimit };

fn symbol(map: []const u32, id: u32) u32 {
    return map[id];
}
fn unit(map: []const u32, id: u32) u32 {
    return if (id == 0 or id == std.math.maxInt(u32)) id else map[id - 1];
}
fn identity(map: []const u32, value: *T.NominalIdentity) void {
    value.unit = unit(map, value.unit);
}
fn target(map: []const u32, value: anytype) void {
    value.unit = unit(map, value.unit);
}
fn typeUnits(nodes: []T.Node, units: []const u32) void {
    for (nodes) |*node| switch (node.tag) {
        .nominal, .type_constructor => node.a = unit(units, node.a),
        else => {},
    };
}

pub fn interface(owner: *PI.Interface, names: []const u32, units: []const u32) void {
    owner.unit = unit(units, owner.unit);
    typeUnits(owner.graph.nodes, units);
    for (owner.graph.operations) |*operation| identity(units, &operation.identity);
    for (owner.bindings) |*binding| {
        binding.name = symbol(names, binding.name);
        if (binding.external) |*external| target(units, external);
    }
    for (owner.obligations) |*obligation| {
        obligation.name = symbol(names, obligation.name);
        identity(units, &obligation.identity);
        obligation.qualification_unit = unit(units, obligation.qualification_unit);
    }
    for (owner.nominals) |*nominal| {
        identity(units, &nominal.identity);
        nominal.name = symbol(names, nominal.name);
    }
    for (owner.contracts) |*contract| {
        identity(units, &contract.identity);
        contract.name = symbol(names, contract.name);
    }
    for (owner.contract_predicates) |*predicate| {
        predicate.name = symbol(names, predicate.name);
        identity(units, &predicate.identity);
        predicate.qualification_unit = unit(units, predicate.qualification_unit);
    }
    for (owner.constructors) |*constructor| {
        identity(units, &constructor.identity);
        constructor.name = symbol(names, constructor.name);
    }
    for (owner.effect_families) |*family| {
        identity(units, &family.identity);
        family.name = symbol(names, family.name);
    }
    for (owner.effect_templates) |*operation| {
        identity(units, &operation.identity);
        operation.name = symbol(names, operation.name);
    }
    for (owner.associated) |*method| {
        identity(units, &method.identity);
        method.member = symbol(names, method.member);
    }
}

pub fn module(owner: *core.Module, names: []const u32, units: []const u32) void {
    for (owner.field_names) |*field| field.symbol = symbol(names, field.symbol);
    std.mem.sortUnstable(core.FieldName, owner.field_names, {}, struct {
        fn less(_: void, left: core.FieldName, right: core.FieldName) bool {
            return left.symbol < right.symbol;
        }
    }.less);
    owner.unit = unit(units, owner.unit);
    typeUnits(owner.types.nodes, units);
    for (owner.types.operations) |*operation| identity(units, &operation.identity);
    for (owner.nodes) |*node| switch (node.tag) {
        .associated => node.c = symbol(names, node.c),
        .result_associated => node.b = symbol(names, node.b),
        else => {},
    };
    for (owner.bindings) |*binding| target(units, &binding.target);
    for (owner.references) |*reference| target(units, reference);
    for (owner.dependency_references) |*reference| target(units, reference);
    for (owner.erased_declaration_references) |*reference| target(units, &reference.target);
    for (owner.dependency_members) |*member| member.name = symbol(names, member.name);
    for (owner.calls) |*call| target(units, &call.target);
    for (owner.obligations) |*obligation| {
        obligation.name = symbol(names, obligation.name);
        identity(units, &obligation.identity);
        obligation.qualification_unit = unit(units, obligation.qualification_unit);
    }
    for (owner.nominals) |*nominal| identity(units, &nominal.identity);
    for (owner.operation_names) |*operation| identity(units, &operation.identity);
    for (owner.constructors) |*constructor| identity(units, &constructor.identity);
    for (owner.projections) |*projection| {
        identity(units, &projection.nominal);
        projection.field = symbol(names, projection.field);
    }
    for (owner.associated) |*method| {
        identity(units, &method.identity);
        method.member = symbol(names, method.member);
        target(units, &method.target);
    }
    for (owner.resolver_ops) |*operation| {
        operation.member = symbol(names, operation.member);
        target(units, &operation.method);
    }
    for (owner.operation_values) |*operation| identity(units, &operation.identity);
}

/// The caller validates all payload IDs before this transaction. Failure to
/// admit an injective dictionary leaves the decoded artifact untouched.
pub fn relink(allocator: Allocator, value: *D.FrozenDependency, pool: *symbols.Pool, units: []const u32) Error!void {
    if (units.len != value.modules.len or value.symbols.len == 0 or value.symbols.len > std.math.maxInt(u32)) return error.InvalidArtifact;
    for (units, 0..) |id, index| {
        if (id == 0 or id == std.math.maxInt(u32)) return error.InvalidArtifact;
        if (std.mem.indexOfScalar(u32, units[0..index], id) != null) return error.InvalidArtifact;
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
    }
    // Everything below is infallible on the previously validated owner.
    std.mem.swap(symbols.Pool, pool, &candidate);
    for (value.modules, word_slots) |*owner, roles| {
        slots.rewrite(owner.interface.graph.extra, roles.interface_types, names);
        slots.rewrite(owner.interface.patterns.extra, roles.patterns, names);
        slots.rewrite(owner.core.types.extra, roles.core_types, names);
        interface(&owner.interface, names, units);
        module(&owner.core, names, units);
        for (owner.imports) |*dependency| dependency.* = unit(units, dependency.*);
        for (owner.source_imports) |*request| request.target = unit(units, request.target);
        for (owner.exports) |*exported| {
            exported.name = symbol(names, exported.name);
            target(units, &exported.target);
        }
        for (owner.fixities) |*fixity| {
            fixity.operator = symbol(names, fixity.operator);
            fixity.target = symbol(names, fixity.target);
            target(units, &fixity.producer);
        }
    }
}
