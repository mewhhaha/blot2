//! Validate the public semantic frontier separately from private executable
//! metadata. No ABI recipe can authorize semantic payload access.
const std = @import("std");
const PI = @import("principal_interface.zig");
const F = @import("frozen_types.zig");
const core = @import("core.zig");
const T = @import("types.zig");
const visibility = @import("module_visibility.zig");
const storage = @import("opaque_storage.zig");
const Error = std.mem.Allocator.Error || error{InvalidArtifact};
fn require(condition: bool) Error!void {
    if (!condition) return error.InvalidArtifact;
}
pub fn publicView(allocator: std.mem.Allocator, owner: *const PI.Interface) Error!void {
    var abstraction = false;
    for (owner.nominals) |nominal| abstraction = abstraction or nominal.private or nominal.is_opaque;
    for (owner.bindings) |binding| abstraction = abstraction or binding.private;
    for (owner.effect_families) |family| abstraction = abstraction or family.private;
    for (owner.contracts) |contract| abstraction = abstraction or contract.private;
    if (!abstraction) return;
    var scan = visibility.Scan.init(allocator, .{ .frozen = &owner.graph }, owner.nominals, owner.effect_families, owner.effect_templates) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.TypeLimit => return error.InvalidArtifact,
    };
    defer scan.deinit();
    for (owner.contracts) |contract| if (contract.private) try scan.blocked.put(allocator, contract.identity, {});
    for (owner.bindings) |binding| {
        if (binding.private) {
            try require(binding.name == 0 and binding.ty == 0 and binding.scheme.root == 0 and binding.external == null);
            continue;
        }
        try allowed(&scan, binding.scheme.root);
        for (owner.obligations[binding.scheme.obligations.start..][0..binding.scheme.obligations.len]) |predicate| try requirement(&scan, owner, predicate);
    }
    var identities: std.AutoHashMapUnmanaged(T.NominalIdentity, void) = .empty;
    defer identities.deinit(allocator);
    for (owner.nominals) |nominal| {
        if (nominal.identity.unit != 0) {
            const found = try identities.getOrPut(allocator, nominal.identity);
            try require(!found.found_existing);
        }
        if (nominal.private) {
            try require(nominal.name == 0 and nominal.alias == 0 and nominal.parameters.len == 0 and nominal.constructors.len == 0);
            continue;
        }
        if (nominal.is_opaque) try require(nominal.name == (nominal.identity.decl & ~T.opaque_name_bit));
        try allowed(&scan, nominal.alias);
        for (owner.graph.extra[nominal.parameters.start..][0..nominal.parameters.len]) |parameter| try allowed(&scan, parameter);
        for (owner.graph.extra[nominal.constructors.start..][0..nominal.constructors.len]) |index| try allowed(&scan, owner.constructors[index].payload);
    }
    for (owner.constructors) |constructor| {
        if (constructor.private) {
            try require(constructor.name == 0 and constructor.payload == 0 and constructor.scheme.root == 0);
            continue;
        }
        try require(!owner.nominals[constructor.nominal].is_opaque and !owner.nominals[constructor.nominal].private);
        try allowed(&scan, constructor.payload);
        try allowed(&scan, constructor.scheme.root);
    }
    for (owner.effect_families) |family| {
        if (family.private) {
            try require(family.name == 0 and family.parameters.len == 0 and family.operations.len == 0);
            continue;
        }
        for (owner.graph.extra[family.parameters.start..][0..family.parameters.len]) |parameter| try allowed(&scan, parameter);
        for (owner.graph.extra[family.operations.start..][0..family.operations.len]) |index| {
            try allowed(&scan, owner.effect_templates[index].parameter);
            try allowed(&scan, owner.effect_templates[index].result);
        }
    }
    for (owner.contracts) |contract| {
        if (contract.private) {
            try require(contract.name == 0 and contract.parameters.len == 0 and contract.predicates.len == 0);
            continue;
        }
        for (owner.graph.extra[contract.parameters.start..][0..contract.parameters.len]) |parameter| try allowed(&scan, parameter);
        for (owner.contract_members[contract.members.start..][0..contract.members.len]) |member| try allowed(&scan, member.root);
        for (owner.contract_predicates[contract.predicates.start..][0..contract.predicates.len]) |predicate| try requirement(&scan, owner, predicate);
    }
    for (owner.associated) |member| try require(member.binding < owner.bindings.len and !owner.bindings[member.binding].private);
}
fn allowed(scan: *visibility.Scan, ty: T.Id) Error!void {
    const result = scan.allowed(ty) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.TypeLimit => return error.InvalidArtifact,
    };
    try require(result);
}
fn requirement(scan: *visibility.Scan, owner: *const PI.Interface, predicate: T.Obligation) Error!void {
    if (predicate.kind == .callee_use and predicate.identity.unit == owner.unit) {
        try require(predicate.identity.decl < owner.bindings.len and !owner.bindings[predicate.identity.decl].private);
    }
    if (predicate.kind == .contract) try require(!scan.blocked.contains(predicate.identity));
    inline for (.{ "ty", "result", "other", "signature" }) |field| try allowed(scan, @field(predicate, field));
}

pub fn storageContracts(owner: *const PI.Interface, implementation: *const core.Module) Error!void {
    try require(owner.bindings.len <= implementation.bindings.len);
    for (owner.bindings, 0..) |binding, index| try require(binding.private == implementation.bindings[index].private);
    try require(owner.nominals.len == implementation.nominals.len);
    for (owner.nominals, implementation.nominals) |public, private| {
        try require(std.meta.eql(public.identity, private.identity) and public.private == private.private and public.is_opaque == private.is_opaque);
    }
    for (owner.constructors) |constructor| {
        const nominal = implementation.nominals[constructor.nominal];
        try require(constructor.private == (nominal.private or nominal.is_opaque));
    }
    for (implementation.nodes) |node| {
        if (node.tag != .construct and node.tag != .constructor_function) continue;
        const nominal = implementation.nominals[implementation.constructors[node.a].nominal];
        if (nominal.is_opaque) try require(nominal.identity.unit == implementation.unit);
    }
    for (implementation.patterns) |pattern| {
        if (pattern.tag != .constructor) continue;
        const nominal = implementation.nominals[implementation.constructors[pattern.a].nominal];
        if (nominal.is_opaque) try require(nominal.identity.unit == implementation.unit);
    }
    for (implementation.projections) |projection| {
        if (projection.nominal.unit != 0 and projection.nominal.decl & T.opaque_name_bit != 0) try require(projection.nominal.unit == implementation.unit);
    }
    var graph: F.Graph = .{ .nodes = implementation.types.nodes, .extra = implementation.types.extra, .rows = implementation.types.effects.rows, .labels = implementation.types.effects.labels, .operations = implementation.types.operations, .row_variable_count = implementation.types.effects.variable_count };
    var remaining: usize = 1_000_000;
    for (implementation.nominals) |nominal| {
        if (!nominal.is_opaque or nominal.identity.unit != implementation.unit) continue;
        try require(nominal.constructors.len == 1);
        const constructor = implementation.constructors[implementation.extra[nominal.constructors.start]];
        const inferred = storage.inferPayload(.{ .frozen = &graph }, implementation.nominals, implementation.constructors, constructor.payload, nominal.parameters, &remaining);
        try require(std.meta.eql(nominal.storage, inferred));
    }
    for (owner.nominals) |nominal| {
        if (!nominal.is_opaque or nominal.private or nominal.identity.unit != implementation.unit) continue;
        var found = false;
        for (implementation.nominals) |private| {
            if (!std.meta.eql(private.identity, nominal.identity)) continue;
            try require(private.is_opaque and private.private == nominal.private and std.meta.eql(private.storage, nominal.storage));
            found = true;
            break;
        }
        try require(found);
    }
}
