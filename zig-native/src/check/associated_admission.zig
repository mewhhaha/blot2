//! Associated declaration scope checks after ordinary graph bounds validation.
//! All traversal state belongs to the unpublished artifact candidate.
const std = @import("std");
const T = @import("types.zig");
const F = @import("frozen_types.zig");
const PI = @import("../reuse/principal_interface.zig");
const core = @import("core.zig");
const A = std.mem.Allocator;
pub const Error = A.Error || error{InvalidArtifact};
const ScopeKey = struct { id: u32, row: bool };
const Work = struct { id: u32, row: bool = false, depth: u32 = 0 };
fn require(value: bool) Error!void {
    if (!value) return error.InvalidArtifact;
}
fn charge(remaining: *usize) Error!void {
    if (remaining.* == 0) return error.InvalidArtifact;
    remaining.* -= 1;
}
fn boundType(source: F.Source, ids: T.List, variable: u32) bool {
    for (source.list(ids)) |id| if (source.node(id).tag == .variable and source.node(id).a == variable) return true;
    return false;
}
fn boundRow(source: F.Source, contract: anytype, variable: u32, member: bool) bool {
    if (comptime @hasField(@TypeOf(contract), "row_parameters")) {
        if (member) {
            for (source.list(contract.row_parameters)) |id| {
                const row = source.row(id);
                if (row.tail == .variable and row.tail.variable == variable) return true;
            }
            return false;
        }
    }
    for (source.list(contract.row_variables)) |id| if (id == variable) return true;
    return false;
}
pub fn scope(a: A, source: F.Source, contract: anytype, root: T.Id, member: bool, remaining: *usize) Error!void {
    var work: std.ArrayList(Work) = .empty;
    defer work.deinit(a);
    var seen: std.AutoHashMapUnmanaged(ScopeKey, void) = .empty;
    defer seen.deinit(a);
    try work.append(a, .{ .id = root });
    while (work.pop()) |item| {
        try charge(remaining);
        try require(item.depth < 256);
        const key: ScopeKey = .{ .id = item.id, .row = item.row };
        const entry = try seen.getOrPut(a, key);
        if (entry.found_existing) continue;
        if (item.row) {
            const row = source.row(item.id);
            if (row.tail == .variable) try require(boundRow(source, contract, row.tail.variable, member));
            try require(row.tail != .parameter);
            for (source.rowLabels(row.labels)) |label| {
                try charge(remaining);
                for (source.list(source.operation(label).arguments)) |argument| try work.append(a, .{ .id = argument, .depth = item.depth + 1 });
            }
            continue;
        }
        const n = source.node(item.id);
        switch (n.tag) {
            .variable => try require(boundType(source, contract.variables, n.a)),
            .function => {
                try work.appendSlice(a, &.{ .{ .id = n.a, .depth = item.depth + 1 }, .{ .id = n.b, .depth = item.depth + 1 }, .{ .id = n.c, .row = true, .depth = item.depth + 1 } });
            },
            .demand, .provider => try work.appendSlice(a, &.{ .{ .id = n.a, .depth = item.depth + 1 }, .{ .id = n.c, .row = true, .depth = item.depth + 1 } }),
            .usage, .array, .list, .cursor, .resolver => try work.append(a, .{ .id = n.a, .depth = item.depth + 1 }),
            .state_provider => for ([_]u32{ n.a, n.b, n.c }) |id| try work.append(a, .{ .id = id, .depth = item.depth + 1 }),
            .product => for (source.list(.{ .start = n.a, .len = n.b })) |id| try work.append(a, .{ .id = id, .depth = item.depth + 1 }),
            .record => for (0..n.b) |index| try work.append(a, .{ .id = source.recordField(n, index).ty, .depth = item.depth + 1 }),
            .nominal, .projection => for (source.nominalArguments(n)) |id| try work.append(a, .{ .id = id, .depth = item.depth + 1 }),
            else => {},
        }
    }
}
pub fn interface(a: A, owner: *const PI.Interface) Error!void {
    var remaining: usize = 1_000_000;
    return interfaceWithBudget(a, owner, &remaining);
}
pub fn interfaceWithBudget(a: A, owner: *const PI.Interface, remaining: *usize) Error!void {
    if (owner.contract_members.len == 0) return;
    const source: F.Source = .{ .frozen = &owner.graph };
    const claimed = try a.alloc(bool, owner.contract_members.len);
    defer a.free(claimed);
    @memset(claimed, false);
    var identities: std.AutoHashMapUnmanaged(T.NominalIdentity, void) = .empty;
    defer identities.deinit(a);
    for (owner.contracts) |contract| {
        try charge(remaining);
        const unique = try identities.getOrPut(a, contract.identity);
        try require(!unique.found_existing);
        if (contract.private and contract.name == 0) continue;
        try require(contract.identity.unit != 0 and contract.identity.decl == T.opaque_name_bit | contract.name);
        for (owner.contract_members[contract.members.start..][0..contract.members.len], contract.members.start..) |member, index| {
            try require(!claimed[index]);
            claimed[index] = true;
            try scope(a, source, contract, member.root, true, remaining);
        }
        for (owner.contract_predicates[contract.predicates.start..][0..contract.predicates.len]) |predicate| inline for (.{ "ty", "other", "result", "signature" }) |field| try scope(a, source, contract, @field(predicate, field), false, remaining);
    }
    for (owner.contract_members, claimed) |member, used| if (!used) try require(member.name == 0 and member.root == 0);
}
pub fn typesView(graph: *const F.Graph) core.Types {
    return .{ .nodes = graph.nodes, .extra = graph.extra, .effects = .{ .rows = graph.rows, .labels = graph.labels, .variable_count = graph.row_variable_count }, .operations = graph.operations, .quantifier_goals = graph.quantifier_goals, .quantifier_obligations = graph.quantifier_obligations };
}
const Copier = @import("../reuse/principal_type_graph.zig").FrozenCopy;
fn sameRoot(a: A, left: *Copier, right: *Copier, l: T.Id, r: T.Id, remaining: *usize) Error!void {
    const first = left.ty(l, 0) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidArtifact,
    };
    const second = right.ty(r, 0) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidArtifact,
    };
    _ = a;
    left.destination.has_projections = true;
    left.destination.projection_limit = left.destination.projection_steps + remaining.*;
    const before = left.destination.projection_steps;
    defer remaining.* -= @min(remaining.*, left.destination.projection_steps - before);
    try require(left.destination.equalSymbolic(first, second) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidArtifact,
    });
}
pub fn equivalent(a: A, first: *const core.Types, second: *const core.Types, left_contract: anytype, right_contract: anytype, left_members: []const PI.ContractMember, right_members: []const PI.ContractMember, left_predicates: anytype, right_predicates: anytype, remaining: *usize) Error!void {
    try require(std.meta.eql(left_contract.identity, right_contract.identity) and left_contract.name == right_contract.name and left_contract.private == right_contract.private and left_contract.requires_implementation == right_contract.requires_implementation);
    try require(left_contract.row_parameters.len == right_contract.row_parameters.len and std.mem.eql(u32, first.list(left_contract.row_parameter_names), second.list(right_contract.row_parameter_names)));
    try require(left_contract.parameters.len == right_contract.parameters.len and left_contract.variables.len == right_contract.variables.len and left_contract.row_variables.len == right_contract.row_variables.len and left_members.len == right_members.len and left_predicates.len == right_predicates.len);
    var destination = T.Store.init(a) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidArtifact,
    };
    defer destination.deinit();
    var left: Copier = .{ .allocator = a, .source = first, .destination = &destination, .max_depth = 256, .max_nodes = 1_000_000, .remaining = remaining };
    defer left.deinit();
    var right: Copier = .{ .allocator = a, .source = second, .destination = &destination, .max_depth = 256, .max_nodes = 1_000_000, .remaining = remaining };
    defer right.deinit();
    for (first.list(left_contract.variables), second.list(right_contract.variables)) |l, r| {
        const fresh = left.ty(l, 0) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidArtifact,
        };
        try right.variables.put(a, second.node(r).a, fresh);
    }
    for (first.list(left_contract.row_variables), second.list(right_contract.row_variables)) |l, r| {
        const fresh = left.rowVariable(l) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidArtifact,
        };
        try right.row_variables.put(a, r, fresh);
    }
    for (first.list(left_contract.row_parameters), second.list(right_contract.row_parameters)) |l, r| {
        const first_row = left.row(l, 0) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidArtifact,
        };
        const second_row = right.row(r, 0) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidArtifact,
        };
        const first_type = destination.functionWithEffects(T.unit, T.unit, first_row) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidArtifact,
        };
        const second_type = destination.functionWithEffects(T.unit, T.unit, second_row) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidArtifact,
        };
        destination.has_projections = true;
        destination.projection_limit = destination.projection_steps + remaining.*;
        const before = destination.projection_steps;
        defer remaining.* -= @min(remaining.*, destination.projection_steps - before);
        try require(destination.equalSymbolic(first_type, second_type) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidArtifact,
        });
    }
    for (first.list(left_contract.parameters), second.list(right_contract.parameters)) |l, r| try sameRoot(a, &left, &right, l, r, remaining);
    for (left_members, right_members) |l, r| {
        try require(std.meta.eql(l.contract, r.contract) and l.name == r.name and l.kind == r.kind);
        try sameRoot(a, &left, &right, l.root, r.root, remaining);
    }
    for (left_predicates, right_predicates) |l, r| {
        try require(l.kind == r.kind and l.name == r.name and l.operator == r.operator and std.meta.eql(l.identity, r.identity) and l.explicit == r.explicit);
        inline for (.{ "ty", "other", "result", "signature" }) |field| try sameRoot(a, &left, &right, @field(l, field), @field(r, field), remaining);
    }
}
/// Public declarations agree with the private executable owner's immutable
/// recipes. Numeric nodes are views; quantifiers compare in declaration order.
pub fn publicCore(a: A, principal: *const PI.Interface, executable: *const core.Module) Error!void {
    var remaining: usize = 1_000_000;
    return publicCoreWithBudget(a, principal, executable, &remaining);
}
pub fn publicCoreWithBudget(a: A, principal: *const PI.Interface, executable: *const core.Module, remaining: *usize) Error!void {
    try @import("rank_portable.zig").publicCore(principal, executable);
    for (principal.bindings, 0..) |binding, index| {
        const private = executable.bindings[index].scheme;
        if (binding.ty == 0 or (binding.scheme.generative.len == 0 and private.generative.len == 0)) continue;
        const public = binding.scheme;
        try require(public.generative.len == private.generative.len and public.variables.len == private.variables.len and public.row_variables.len == private.row_variables.len);
        const source = typesView(&principal.graph);
        var destination = T.Store.init(a) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidArtifact,
        };
        defer destination.deinit();
        var left: Copier = .{ .allocator = a, .source = &source, .destination = &destination, .max_depth = 256, .max_nodes = 1_000_000, .remaining = remaining };
        defer left.deinit();
        var right: Copier = .{ .allocator = a, .source = &executable.types, .destination = &destination, .max_depth = 256, .max_nodes = 1_000_000, .remaining = remaining };
        defer right.deinit();
        for (source.list(public.variables), executable.types.list(private.variables)) |l, r| {
            const fresh = left.ty(l, 0) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return error.InvalidArtifact,
            };
            try right.variables.put(a, executable.types.node(r).a, fresh);
        }
        for (source.list(public.row_variables), executable.types.list(private.row_variables)) |l, r| {
            const fresh = left.rowVariable(l) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return error.InvalidArtifact,
            };
            try right.row_variables.put(a, r, fresh);
        }
        try sameRoot(a, &left, &right, public.root, private.root, remaining);
        for (source.list(public.generative), executable.types.list(private.generative)) |l, r| try sameRoot(a, &left, &right, l, r, remaining);
    }
    for (principal.proof_contracts) |value| {
        if (remaining.* == 0) return error.InvalidArtifact;
        remaining.* -= 1;
        const original = @import("numeric_proof_headers.zig").find(executable.proof_contracts, value.binding) orelse return error.InvalidArtifact;
        try require(@import("numeric_proof_headers.zig").equal(value.header, original.*));
    }
    for (principal.bindings, 0..) |binding, id| {
        if (binding.ty == 0) continue;
        if (@import("numeric_proof_headers.zig").find(executable.proof_contracts, @intCast(id)) != null) {
            try require(@import("numeric_proof_headers.zig").find(principal.proof_contracts, @intCast(id)) != null);
        }
    }
    if (principal.contract_members.len == 0 and executable.contract_members.len == 0) return;
    const first = typesView(&principal.graph);
    for (principal.contracts) |contract| {
        if (contract.private or contract.members.len == 0) continue;
        const original = for (executable.contracts) |candidate| {
            if (std.meta.eql(contract.identity, candidate.identity)) break candidate;
        } else return error.InvalidArtifact;
        try equivalent(a, &first, &executable.types, contract, original, principal.contract_members[contract.members.start..][0..contract.members.len], executable.contract_members[original.members.start..][0..original.members.len], principal.contract_predicates[contract.predicates.start..][0..contract.predicates.len], executable.obligations[original.predicates.start..][0..original.predicates.len], remaining);
    }
}
/// An imported recipe cannot claim a portable identity with a different body.
pub fn originalProducers(a: A, owners: []const @import("../reuse/frozen_dependency.zig").Module) Error!void {
    var remaining: usize = 1_000_000;
    return originalProducersWithBudget(a, owners, &remaining);
}
pub fn originalProducersWithBudget(a: A, owners: []const @import("../reuse/frozen_dependency.zig").Module, remaining: *usize) Error!void {
    for (owners) |owner| for (owner.interface.contracts) |contract| {
        if (contract.private or contract.members.len == 0) continue;
        try require(contract.identity.unit != 0 and contract.identity.unit <= owners.len);
        const producer = &owners[contract.identity.unit - 1].interface;
        const original = for (producer.contracts) |candidate| {
            if (std.meta.eql(candidate.identity, contract.identity) and !candidate.private) break candidate;
        } else return error.InvalidArtifact;
        const first = typesView(&owner.interface.graph);
        const second = typesView(&producer.graph);
        try equivalent(a, &first, &second, contract, original, owner.interface.contract_members[contract.members.start..][0..contract.members.len], producer.contract_members[original.members.start..][0..original.members.len], owner.interface.contract_predicates[contract.predicates.start..][0..contract.predicates.len], producer.contract_predicates[original.predicates.start..][0..original.predicates.len], remaining);
    };
}
