//! Validate normalized principal payloads before exposing any imported scheme.
const std = @import("std");
const PI = @import("principal_interface.zig");
const T = @import("../check/types.zig");
pub const Error = error{InvalidArtifact};

fn require(condition: bool) Error!void {
    if (!condition) return error.InvalidArtifact;
}
fn range(start: u32, count: u32, length: usize) Error!void {
    try require(start <= length and count <= length - start);
}
fn list(owner: *const PI.Interface, value: T.List) Error![]const u32 {
    try range(value.start, value.len, owner.graph.extra.len);
    return owner.graph.extra[value.start..][0..value.len];
}
fn ty(owner: *const PI.Interface, id: T.Id) Error!void {
    try require(id < owner.graph.nodes.len);
}
fn names(values: []const u32, count: usize) Error!void {
    for (values) |id| try require(id < count);
}
fn units(id: u32, count: usize) Error!void {
    try require(id == 0 or id == std.math.maxInt(u32) or id <= count);
}
fn target(owner: *const PI.Interface, value: PI.ExternalTarget, unit_count: usize) Error!void {
    try units(value.unit, unit_count);
    if (value.unit == 0 or value.unit == owner.unit) try require(value.binding < owner.bindings.len);
}
fn callee(owner: *const PI.Interface, value: T.Obligation, local: bool, unit_count: usize) Error!void {
    if (value.kind != .callee_use) return;
    if (local or value.identity.unit == 0 or value.identity.unit == owner.unit) {
        try require(value.identity.decl != 0 and value.identity.decl < owner.bindings.len);
        return;
    }
    try require(value.identity.unit <= unit_count and value.identity.decl != 0);
    for (owner.bindings) |binding| {
        if (binding.kind != .external) continue;
        const external = binding.external orelse continue;
        if (external.unit == value.identity.unit and external.binding == value.identity.decl) return;
    }
    return error.InvalidArtifact;
}
fn identity(value: T.NominalIdentity, symbol_count: usize, unit_count: usize) Error!void {
    try units(value.unit, unit_count);
    if (value.unit != 0 and value.unit != std.math.maxInt(u32) and value.decl & T.opaque_name_bit != 0) try require((value.decl & ~T.opaque_name_bit) < symbol_count);
}
fn scheme(owner: *const PI.Interface, value: T.Scheme) Error!void {
    try ty(owner, value.root);
    for (try list(owner, value.variables)) |id| {
        try ty(owner, id);
        try require(owner.graph.nodes[id].tag == .variable);
    }
    for (try list(owner, value.row_variables)) |id| try require(id < owner.graph.row_variable_count);
    for (try list(owner, value.closed_rows)) |id| try require(id < owner.graph.row_variable_count);
    try range(value.obligations.start, value.obligations.len, owner.obligations.len);
    try require(value.generative.len <= 32 and value.generative.len % 2 == 0);
    const binders = try list(owner, value.generative);
    for (0..binders.len / 2) |index| {
        try ty(owner, binders[index * 2]);
        try ty(owner, binders[index * 2 + 1]);
        const selected = owner.graph.nodes[binders[index * 2 + 1]];
        try require(owner.graph.nodes[binders[index * 2]].tag == .function and selected.tag == .scoped and selected.b == 0 and owner.graph.nodes[selected.c].tag == .instance_selection);
    }
}

pub fn validate(owner: *const PI.Interface, symbol_count: usize, unit_count: usize) Error!void {
    for (owner.obligations) |value| try callee(owner, value, true, unit_count);
    for ([_][]const T.Obligation{ owner.contract_predicates, owner.implementation_predicates, owner.graph.quantifier_obligations }) |predicates| {
        for (predicates) |value| try callee(owner, value, false, unit_count);
    }
    for (owner.selected_proofs) |proof| try callee(owner, proof.predicate, false, unit_count);
    try require(owner.has_numeric_proofs or owner.proof_contracts.len == 0);
    for (owner.proof_contracts) |value| try require(value.binding != 0 and value.binding < owner.bindings.len);
    owner.capability_contracts.validate(owner.bindings.len, symbol_count) catch return error.InvalidArtifact;
    for (owner.capability_contracts.bindings) |entry| {
        const binding = owner.bindings[entry.binding];
        try require(binding.capability_parameters.present() and binding.kind == .global);
        const header = owner.capability_contracts.header(entry.binding, binding.capability_parameters.arity()).?;
        header.view().validate(header.root, header.arity, true) catch return error.InvalidArtifact;
    }
    try require(owner.unit != 0 and owner.unit <= unit_count);
    try require(owner.graph.nodes.len >= 6 and owner.graph.rows.len != 0 and owner.graph.operations.len >= 2);
    try @import("../check/quantifier_goals.zig").validate(owner.graph.nodes, owner.graph.quantifier_goals, owner.graph.quantifier_obligations);
    for ([_]T.Tag{ .absent, .unit, .boolean, .u32, .f32, .never }, owner.graph.nodes[0..6]) |tag, node| try require(node.tag == tag and node.a == 0 and node.b == 0 and node.c == 0);
    for (owner.graph.nodes) |node| switch (node.tag) {
        .bound => {
            if (node.b == 0) {
                try require(owner.has_rank_contracts and node.a < 128 and node.c == 0);
            } else if (node.c == 0) {
                try require(owner.has_rank_contracts and node.a < 128 and (node.b == 1 or (owner.has_usage_contracts and node.b == 2)));
            } else try require(owner.has_usage_contracts and node.a == 0 and node.b == 2 and node.c < owner.bindings.len);
        },
        .forall, .existential => {
            try require(owner.has_rank_contracts);
            try ty(owner, node.a);
            for (try list(owner, .{ .start = node.b, .len = node.c })) |binder| try ty(owner, binder);
        },
        .rigid => return error.InvalidArtifact,
        .instance_version => {
            try units(node.a, unit_count);
            try require(node.a != 0 and node.b != 0 and node.b < 0x04000000 and node.c < 16);
        },
        .instance_selection => {
            try units(node.a, unit_count);
            try require(node.a != 0 and node.b != 0 and node.c < owner.graph.extra.len and owner.graph.extra[node.c] == 3);
            const children = try list(owner, .{ .start = node.c + 1, .len = 3 });
            for (children) |child| try ty(owner, child);
            try require(owner.graph.nodes[children[0]].tag == .scoped and owner.graph.nodes[children[1]].tag == .scoped and owner.graph.nodes[children[2]].tag == .instance_version);
        },
        .usage => {
            try ty(owner, node.a);
            try require(owner.has_usage_contracts and node.b <= @backingInt(T.UsageKind.cleanup));
            if (node.c != 0) try ty(owner, node.c);
        },
        .erased_proof => try require(owner.has_numeric_proofs and node.a == 0 and node.b == 0 and node.c == 0),
        .scoped => {
            try ty(owner, node.a);
            try ty(owner, node.c);
            try require(node.b == 0 and (owner.graph.nodes[node.c].tag == .variable or owner.graph.nodes[node.c].tag == .instance_selection) and owner.graph.nodes[node.a].tag == .nominal);
        },
        .absent, .unit, .boolean, .u32, .f32, .never => {},
        .variable => try require(node.b == 0 and node.c == 0),
        .function => {
            try ty(owner, node.a);
            try ty(owner, node.b);
            try require(node.c < owner.graph.rows.len);
        },
        .product => for (try list(owner, .{ .start = node.a, .len = node.b })) |child| try ty(owner, child),
        .record => {
            const count = std.math.mul(u32, node.b, 2) catch return error.InvalidArtifact;
            const fields = try list(owner, .{ .start = node.a, .len = count });
            for (0..node.b) |index| {
                try require(fields[index * 2] != 0 and fields[index * 2] < symbol_count);
                try ty(owner, fields[index * 2 + 1]);
                // Record payloads retain source declaration order. Layouts
                // canonicalize separately; validateGraph checks uniqueness.
            }
        },
        .nominal, .projection => {
            try identity(.{ .unit = node.a, .decl = node.b }, symbol_count, unit_count);
            try require(node.c < owner.graph.extra.len);
            const start = std.math.add(u32, node.c, 1) catch return error.InvalidArtifact;
            for (try list(owner, .{ .start = start, .len = owner.graph.extra[node.c] })) |child| try ty(owner, child);
            if (node.tag == .projection) {
                const slot = std.math.add(u32, start, owner.graph.extra[node.c]) catch return error.InvalidArtifact;
                try require(slot < owner.graph.extra.len);
                try require(owner.graph.extra[slot] != 0 and owner.graph.extra[slot] < symbol_count);
                const member_name = owner.graph.extra[slot];
                var declared = false;
                for (owner.contract_members) |member| if (member.contract.unit == node.a and member.contract.decl == node.b and member.name == member_name and member.kind != .value) {
                    declared = true;
                };
                try require(declared);
                const contract = for (owner.contracts) |candidate| {
                    if (candidate.identity.unit == node.a and candidate.identity.decl == node.b) break candidate;
                } else return error.InvalidArtifact;
                try require(owner.graph.extra[node.c] == contract.parameters.len);
            }
        },
        .type_constructor => try identity(.{ .unit = node.a, .decl = node.b }, symbol_count, unit_count),
        .array, .list, .cursor, .resolver => try ty(owner, node.a),
        .demand, .provider => {
            try ty(owner, node.a);
            try require(node.c < owner.graph.rows.len);
        },
        .state_provider => {
            try ty(owner, node.a);
            try ty(owner, node.b);
            try ty(owner, node.c);
        },
    };
    try require(owner.graph.row_variable_count <= T.Effects.formal_key_bit);
    for (owner.graph.rows) |row| {
        try require(row.cursor == 0);
        try range(row.labels.start, row.labels.len, owner.graph.labels.len);
        for (owner.graph.labels[row.labels.start..][0..row.labels.len]) |label| try require(label != 0 and label < owner.graph.operations.len);
        if (row.tail == .variable) try require(row.tail.variable < owner.graph.row_variable_count);
        if (row.tail == .formal) {
            try ty(owner, row.tail.formal);
            const leaf = owner.graph.nodes[row.tail.formal];
            try require(leaf.tag == .bound and leaf.b == 1 and leaf.c == 0);
        }
    }
    try require(owner.graph.rows[0].labels.len == 0 and owner.graph.rows[0].tail == .closed);
    for (owner.graph.operations) |operation| {
        try require(operation.instance.unit == 0);
        if (operation.instance.decl != 0) {
            try ty(owner, operation.instance.decl);
            try require(owner.graph.nodes[operation.instance.decl].tag == .variable or owner.graph.nodes[operation.instance.decl].tag == .instance_selection);
        }
        try identity(operation.identity, symbol_count, unit_count);
        for (try list(owner, operation.arguments)) |argument| try ty(owner, argument);
    }
    try require(owner.graph.operations[0].identity.unit == 0 and owner.graph.operations[0].identity.decl == 0);
    try require(owner.graph.operations[1].identity.unit == 0 and owner.graph.operations[1].identity.decl == 1);
    for (owner.patterns.nodes) |node| switch (node.kind) {
        .binding => try ty(owner, node.a),
        .tuple, .array => {
            try range(node.a, node.b, owner.patterns.extra.len);
            for (owner.patterns.extra[node.a..][0..node.b]) |id| try require(id < owner.patterns.nodes.len);
        },
        .record => {
            const count = std.math.mul(u32, node.b, 2) catch return error.InvalidArtifact;
            try range(node.a, count, owner.patterns.extra.len);
            for (0..node.b) |index| {
                try require(owner.patterns.extra[node.a + index * 2] < symbol_count);
                try require(owner.patterns.extra[node.a + index * 2 + 1] < owner.patterns.nodes.len);
            }
        },
    };
    for (owner.bindings) |binding| {
        try require(binding.name < symbol_count);
        try require(@backingInt(binding.capability_flow) <= @backingInt(@import("../check/capability_flow.zig").Contract.consume_task));
        try ty(owner, binding.ty);
        try scheme(owner, binding.scheme);
        try require(binding.capability_parameters.valid());
        if (binding.capability_flow == .input_shape) try require(binding.capability_parameters.kind == .product and binding.capability_parameters.arity() != 0 and binding.scheme.generative.len == 0);
        if (binding.capability_flow != .unknown or binding.capability_parameters.present()) {
            try require(binding.external == null and binding.named_function);
            try require(binding.scheme.root != 0);
            var root = binding.scheme.root;
            if (owner.graph.nodes[root].tag == .forall) {
                try require(owner.has_rank_contracts);
                root = owner.graph.nodes[root].a;
            }
            try require(owner.graph.nodes[root].tag == .function);
        }
        if (binding.external) |external| {
            try target(owner, external, unit_count);
            try require(external.binding != 0);
        }
    }
    try require(owner.obligations.len == owner.obligation_spans.len);
    for (owner.obligations) |obligation| {
        try ty(owner, obligation.ty);
        try ty(owner, obligation.result);
        try ty(owner, obligation.other);
        try ty(owner, obligation.signature);
        try require(obligation.source == 0 and obligation.name < symbol_count);
        try identity(obligation.identity, symbol_count, unit_count);
        try units(obligation.qualification_unit, unit_count);
    }
    for (owner.nominals) |nominal| {
        try require(!nominal.affine or nominal.has_usage);
        try require(!nominal.closed_storage or !nominal.has_usage);
        if (nominal.has_usage) try require(owner.has_usage_contracts);
        if (nominal.identity.unit != 0 and nominal.identity.unit != std.math.maxInt(u32)) try require(nominal.is_opaque == (nominal.identity.decl & T.opaque_name_bit != 0));
        if (nominal.is_opaque) {
            try require(nominal.alias == 0 and nominal.constructors.len == 0);
            try require(nominal.storage.kind != .parameter or nominal.storage.parameter < nominal.parameters.len);
            try require(nominal.identity.decl & T.opaque_name_bit != 0);
            try require((nominal.identity.decl & ~T.opaque_name_bit) < symbol_count);
        }
        try ty(owner, nominal.alias);
        for (try list(owner, nominal.alias_rows)) |row| try require(row < owner.graph.row_variable_count);
        if (nominal.alias != 0) try require(nominal.constructors.len == 0);
        try identity(nominal.identity, symbol_count, unit_count);
        try require(nominal.name < symbol_count);
        for (try list(owner, nominal.parameters)) |id| try ty(owner, id);
        for (try list(owner, nominal.variables)) |id| try ty(owner, id);
        try range(nominal.patterns.start, nominal.patterns.len, owner.patterns.extra.len);
        for (owner.patterns.extra[nominal.patterns.start..][0..nominal.patterns.len]) |id| try require(id < owner.patterns.nodes.len);
        try names(try list(owner, nominal.parameter_names), symbol_count);
        for (try list(owner, nominal.constructors)) |id| try require(id < owner.constructors.len);
    }
    for (owner.contracts) |contract| {
        try identity(contract.identity, symbol_count, unit_count);
        try require(contract.name < symbol_count);
        for (try list(owner, contract.parameters)) |id| try ty(owner, id);
        for (try list(owner, contract.variables)) |id| {
            try ty(owner, id);
            try require(owner.graph.nodes[id].tag == .variable);
        }
        for (try list(owner, contract.row_variables)) |row| try require(row < owner.graph.row_variable_count);
        try names(try list(owner, contract.parameter_names), symbol_count);
        try names(try list(owner, contract.row_parameter_names), symbol_count);
        try require(contract.row_parameters.len == contract.row_parameter_names.len and contract.declaration == 0);
        for (try list(owner, contract.row_parameters)) |row| {
            try require(row < owner.graph.rows.len);
            const value = owner.graph.rows[row];
            try require(value.tail == .variable and value.labels.len == 0);
            const bound = for (try list(owner, contract.row_variables)) |variable| {
                if (variable == value.tail.variable) break true;
            } else false;
            try require(bound);
        }
        for (try list(owner, contract.row_parameter_names), 0..) |name, ordinal| {
            try require(name != 0);
            for ((try list(owner, contract.row_parameter_names))[0..ordinal]) |previous| try require(name != previous);
        }
        try require(contract.parameter_names.len == contract.variables.len and contract.patterns.len == contract.parameters.len);
        try range(contract.patterns.start, contract.patterns.len, owner.patterns.extra.len);
        for (owner.patterns.extra[contract.patterns.start..][0..contract.patterns.len]) |id| try require(id < owner.patterns.nodes.len);
        try range(contract.predicates.start, contract.predicates.len, owner.contract_predicates.len);
        try range(contract.members.start, contract.members.len, owner.contract_members.len);
        var requires_implementation = false;
        for (owner.contract_members[contract.members.start..][0..contract.members.len], 0..) |member, index| {
            try require(std.meta.eql(member.contract, contract.identity));
            try require(member.name != 0 and member.name < symbol_count);
            try ty(owner, member.root);
            try require((member.kind == .abstract_type) == (member.root == 0));
            if (member.kind == .value) try require(owner.graph.nodes[member.root].tag == .function);
            for (owner.contract_members[contract.members.start..][0..index]) |previous| try require(previous.name != member.name);
            requires_implementation = requires_implementation or member.kind != .defined_type;
        }
        try require(contract.requires_implementation == requires_implementation);
    }
    for (owner.contract_predicates) |predicate| {
        inline for (.{ "ty", "other", "result", "signature" }) |field| try ty(owner, @field(predicate, field));
        try require(predicate.source == 0 and predicate.name < symbol_count and predicate.explicit);
        try identity(predicate.identity, symbol_count, unit_count);
        try units(predicate.qualification_unit, unit_count);
    }
    try require(owner.implementations.len <= 4096);
    for (owner.implementations) |implementation| {
        try identity(implementation.identity, symbol_count, unit_count);
        try identity(implementation.contract, symbol_count, unit_count);
        try require(implementation.name < symbol_count and implementation.declaration == 0);
        if (implementation.private and implementation.name == 0) {
            try require(implementation.head.len == 0 and implementation.variables.len == 0 and implementation.row_variables.len == 0 and implementation.predicates.len == 0 and implementation.members.len == 0);
            continue;
        }
        try require(implementation.name != 0 and implementation.identity.decl == T.opaque_name_bit | implementation.name);
        for (try list(owner, implementation.head)) |id| try ty(owner, id);
        for (try list(owner, implementation.variables)) |id| {
            try ty(owner, id);
            try require(owner.graph.nodes[id].tag == .variable);
        }
        try names(try list(owner, implementation.parameter_names), symbol_count);
        try names(try list(owner, implementation.row_parameter_names), symbol_count);
        try require(implementation.parameter_names.len == implementation.variables.len and implementation.row_parameter_names.len == implementation.row_variables.len and implementation.row_parameters.len == implementation.row_variables.len);
        for (try list(owner, implementation.row_variables)) |id| try require(id < owner.graph.row_variable_count);
        for (try list(owner, implementation.row_parameters)) |id| try require(id < owner.graph.rows.len);
        try range(implementation.predicates.start, implementation.predicates.len, owner.implementation_predicates.len);
        try range(implementation.members.start, implementation.members.len, owner.implementation_members.len);
    }
    for (owner.implementation_members) |member| {
        try require(member.name < symbol_count);
        try ty(owner, member.root);
        try target(owner, member.target, unit_count);
        if (member.kind == .type_) try require(member.target.unit == 0 and member.target.binding == 0);
        if (member.name != 0 and member.kind == .value) try require(member.target.binding != 0 and owner.graph.nodes[member.root].tag == .function);
    }
    for (owner.implementation_predicates) |predicate| {
        inline for (.{ "ty", "other", "result", "signature" }) |field| try ty(owner, @field(predicate, field));
        try require(predicate.source == 0 and predicate.name < symbol_count);
        try identity(predicate.identity, symbol_count, unit_count);
    }
    for (owner.member_templates) |template| {
        try require(template.binding != 0 and template.binding < owner.bindings.len and template.name != 0 and template.name < symbol_count);
        try identity(template.contract, symbol_count, unit_count);
        for (try list(owner, template.arguments)) |root| try ty(owner, root);
    }
    for (owner.selected_members) |member| {
        try require(member.name != 0 and member.name < symbol_count);
        try ty(owner, member.root);
        try require(member.root != 0);
        try target(owner, member.target, unit_count);
    }
    for (owner.selected_proofs, 0..) |proof, ordinal| {
        try target(owner, proof.predicate_target, unit_count);
        if (proof.predicate_target.binding == 0) try require(proof.predicate_target.unit == 0);
        try units(proof.context, unit_count);
        try identity(proof.implementation, symbol_count, unit_count);
        try identity(proof.contract, symbol_count, unit_count);
        for (try list(owner, proof.arguments)) |root| try ty(owner, root);
        inline for (.{ "ty", "other", "result", "signature" }) |field| try ty(owner, @field(proof.predicate, field));
        try range(proof.members.start, proof.members.len, owner.selected_members.len);
        try range(proof.prerequisites.start, proof.prerequisites.len, owner.selected_edges.len);
        for (owner.selected_edges[proof.prerequisites.start..][0..proof.prerequisites.len]) |child| try require(child < ordinal);
    }
    for (owner.constructors) |constructor| {
        try identity(constructor.identity, symbol_count, unit_count);
        try require(constructor.name < symbol_count and constructor.nominal < owner.nominals.len);
        try scheme(owner, constructor.scheme);
        try ty(owner, constructor.payload);
    }
    for (owner.effect_families) |family| {
        try identity(family.identity, symbol_count, unit_count);
        try require(family.name < symbol_count);
        for (try list(owner, family.parameters)) |id| try ty(owner, id);
        for (try list(owner, family.variables)) |id| try ty(owner, id);
        try range(family.patterns.start, family.patterns.len, owner.patterns.extra.len);
        for (owner.patterns.extra[family.patterns.start..][0..family.patterns.len]) |id| try require(id < owner.patterns.nodes.len);
        try names(try list(owner, family.parameter_names), symbol_count);
        for (try list(owner, family.operations)) |id| try require(id < owner.effect_templates.len);
    }
    for (owner.effect_templates) |operation| {
        try identity(operation.identity, symbol_count, unit_count);
        try require(operation.name < symbol_count and operation.family < owner.effect_families.len);
        try ty(owner, operation.parameter);
        try ty(owner, operation.result);
    }
    for (owner.associated) |method| {
        try identity(method.identity, symbol_count, unit_count);
        try require(method.member < symbol_count and method.binding < owner.bindings.len);
    }
}

/// Structural type, operation and pattern edges must be acyclic. Nominal
/// declaration identities are leaves; recursive source data is represented by
/// those identities rather than a pointer back into this graph. Bounds must be
/// checked first, so this traversal never speculates about malformed indices.
pub fn validateGraph(allocator: std.mem.Allocator, owner: *const PI.Interface) (Error || std.mem.Allocator.Error)!void {
    var remaining: usize = 1_000_000;
    return validateGraphWithBudget(allocator, owner, &remaining);
}
pub fn validateGraphWithBudget(allocator: std.mem.Allocator, owner: *const PI.Interface, remaining: *usize) (Error || std.mem.Allocator.Error)!void {
    if (owner.has_numeric_proofs) try @import("../check/numeric_proof_core.zig").dataTypes(@import("../check/frozen_types.zig").Source{ .frozen = &owner.graph }, owner.graph.nodes);
    try require(owner.has_numeric_proofs or owner.proof_contracts.len == 0);
    var proof_budget: @import("../check/numeric_proof_terms.zig").Store = .{};
    defer proof_budget.deinit(allocator);
    proof_budget.limits.visits = @min(remaining.*, proof_budget.limits.visits);
    var proof_bindings: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer proof_bindings.deinit(allocator);
    for (owner.proof_contracts) |value| {
        try require(value.binding != 0 and value.binding < owner.bindings.len);
        const slot = try proof_bindings.getOrPut(allocator, value.binding);
        try require(!slot.found_existing);
        value.header.signature().validateInto(allocator, &proof_budget) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return error.InvalidArtifact;
        };
        try @import("../check/numeric_proof_core.zig").signatureTypes(@import("../check/frozen_types.zig").Source{ .frozen = &owner.graph }, owner.bindings[value.binding].ty, value.header);
    }
    remaining.* -= @min(remaining.*, proof_budget.visits);
    try @import("../check/associated_admission.zig").interfaceWithBudget(allocator, owner, remaining);
    const source = @import("../check/associated_admission.zig").typesView(&owner.graph);
    try @import("../eval/implementation_admission.zig").scopes(allocator, &source, owner, owner.implementation_predicates, remaining);
    // Reuse one symbol-stamp lane across every source record. Arbitrary
    // declaration order is legal; duplicate fields reject in linear work.
    var symbol_limit: usize = 0;
    for (owner.graph.nodes) |n| if (n.tag == .record) {
        for (0..n.b) |index| symbol_limit = @max(symbol_limit, @as(usize, owner.graph.extra[n.a + index * 2]) + 1);
    };
    const stamps = try allocator.alloc(u32, symbol_limit);
    defer allocator.free(stamps);
    @memset(stamps, 0);
    var generation: u32 = 0;
    for (owner.graph.nodes) |n| if (n.tag == .record) {
        generation = std.math.add(u32, generation, 1) catch return error.InvalidArtifact;
        for (0..n.b) |index| {
            const name = owner.graph.extra[n.a + index * 2];
            if (stamps[name] == generation) return error.InvalidArtifact;
            stamps[name] = generation;
        }
    };
    const graph = GraphEdges{ .owner = owner };
    const total = graph.total();
    const colors = try allocator.alloc(u2, total);
    defer allocator.free(colors);
    @memset(colors, 0);
    const Frame = struct { key: usize, next: usize = 0 };
    const frames = try allocator.alloc(Frame, total);
    defer allocator.free(frames);
    for (0..total) |root| {
        if (colors[root] != 0) continue;
        var depth: usize = 1;
        frames[0] = .{ .key = root };
        colors[root] = 1;
        while (depth != 0) {
            const current = &frames[depth - 1];
            const child = graph.child(current.key, current.next) orelse {
                colors[current.key] = 2;
                depth -= 1;
                continue;
            };
            current.next += 1;
            if (colors[child] == 1) return error.InvalidArtifact;
            if (colors[child] == 2) continue;
            colors[child] = 1;
            frames[depth] = .{ .key = child };
            depth += 1;
        }
    }
    try @import("../check/rank_portable.zig").interface(owner);
}

const GraphEdges = struct {
    owner: *const PI.Interface,
    fn rowStart(self: GraphEdges) usize {
        return self.owner.graph.nodes.len;
    }
    fn operationStart(self: GraphEdges) usize {
        return self.rowStart() + self.owner.graph.rows.len;
    }
    fn patternStart(self: GraphEdges) usize {
        return self.operationStart() + self.owner.graph.operations.len;
    }
    fn total(self: GraphEdges) usize {
        return self.patternStart() + self.owner.patterns.nodes.len;
    }
    fn child(self: GraphEdges, key: usize, index: usize) ?usize {
        const g = self.owner.graph;
        if (key < self.rowStart()) {
            const n = g.nodes[key];
            return switch (n.tag) {
                .usage => switch (index) {
                    0 => n.a,
                    1 => if (n.c != 0) n.c else null,
                    else => null,
                },
                .function => switch (index) {
                    0 => n.a,
                    1 => n.b,
                    2 => self.rowStart() + n.c,
                    else => null,
                },
                .forall, .existential => blk: {
                    if (index == 0) break :blk n.a;
                    if (index - 1 < n.c) break :blk g.extra[n.b + index - 1];
                    const goals = @import("../check/quantifier_goals.zig").get(g.quantifier_goals, g.quantifier_obligations, @intCast(key));
                    const goal_slot = index - 1 - n.c;
                    if (goal_slot / 4 >= goals.len) break :blk null;
                    const goal = goals[goal_slot / 4];
                    const children = [_]T.Id{ goal.ty, goal.other, goal.result, goal.signature };
                    break :blk children[goal_slot % 4];
                },
                .product => if (index < n.b) g.extra[n.a + index] else null,
                .record => if (index < n.b) g.extra[n.a + index * 2 + 1] else null,
                .nominal => if (index < g.extra[n.c]) g.extra[n.c + 1 + index] else null,
                .projection => blk: {
                    const count = g.extra[n.c];
                    if (index < count) break :blk g.extra[n.c + 1 + index];
                    if (index != count) break :blk null;
                    const member_name = g.extra[n.c + 1 + count];
                    for (self.owner.contract_members) |member| {
                        if (member.contract.unit == n.a and member.contract.decl == n.b and member.name == member_name and member.kind == .defined_type) break :blk member.root;
                    }
                    break :blk null;
                },
                .array, .list, .cursor, .resolver => if (index == 0) n.a else null,
                .demand, .provider => switch (index) {
                    0 => n.a,
                    1 => self.rowStart() + n.c,
                    else => null,
                },
                .state_provider => switch (index) {
                    0 => n.a,
                    1 => n.b,
                    2 => n.c,
                    else => null,
                },
                else => null,
            };
        }
        if (key < self.operationStart()) {
            const row = g.rows[key - self.rowStart()];
            return if (index < row.labels.len) self.operationStart() + g.labels[row.labels.start + index] else null;
        }
        if (key < self.patternStart()) {
            const operation = g.operations[key - self.operationStart()];
            return if (index < operation.arguments.len) g.extra[operation.arguments.start + index] else null;
        }
        const p = self.owner.patterns;
        const n = p.nodes[key - self.patternStart()];
        return switch (n.kind) {
            .binding => if (index == 0) n.a else null,
            .tuple, .array => if (index < n.b) self.patternStart() + p.extra[n.a + index] else null,
            .record => if (index < n.b) self.patternStart() + p.extra[n.a + index * 2 + 1] else null,
        };
    }
};
