//! Implementation recipes are admitted before their owned catalogs become
//! observable. Matching inspects heads only; prerequisites grant no overlap.
const std = @import("std");
const T = @import("../check/types.zig");
const F = @import("../check/frozen_types.zig");
const C = @import("../check/core.zig");
const PI = @import("../reuse/principal_interface.zig");
const associated = @import("../check/associated_admission.zig");
const Copier = @import("../reuse/principal_type_graph.zig").FrozenCopy;
const A = std.mem.Allocator;
pub const Error = A.Error || error{InvalidArtifact};
fn require(value: bool) Error!void {
    if (!value) return error.InvalidArtifact;
}
fn graph(source: *const C.Types) F.Graph {
    return .{ .nodes = source.nodes, .extra = source.extra, .rows = source.effects.rows, .labels = source.effects.labels, .operations = source.operations, .quantifier_goals = source.quantifier_goals, .quantifier_obligations = source.quantifier_obligations, .row_variable_count = source.effects.variable_count };
}
fn convert(err: T.Error) Error {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    return error.InvalidArtifact;
}
fn list(a: A, copy: *Copier, span: T.List) Error!T.List {
    var roots: std.ArrayList(T.Id) = .empty;
    defer roots.deinit(a);
    for (copy.source.list(span)) |root| try roots.append(a, copy.ty(root, 0) catch |err| return convert(err));
    return copy.destination.saveList(roots.items) catch |err| return convert(err);
}
fn imported(a: A, copy: *Copier, source: PI.Implementation) Error!PI.Implementation {
    var value = source;
    value.variables = try list(a, copy, source.variables);
    var rows: std.ArrayList(u32) = .empty;
    defer rows.deinit(a);
    for (copy.source.list(source.row_variables)) |row| try rows.append(a, copy.rowVariable(row) catch |err| return convert(err));
    value.row_variables = copy.destination.saveList(rows.items) catch |err| return convert(err);
    value.head = try list(a, copy, source.head);
    return value;
}
fn charge(remaining: *usize) Error!void {
    try require(remaining.* != 0);
    remaining.* -= 1;
}
fn sameRoot(copy: *Copier, first: T.Id, second: T.Id, remaining: *usize) Error!void {
    const left = copy.ty(first, 0) catch |err| return convert(err);
    const right = copy.ty(second, 0) catch |err| return convert(err);
    const store = copy.destination;
    store.has_projections = true;
    store.projection_limit = store.projection_steps + remaining.*;
    const before = store.projection_steps;
    defer remaining.* -= @min(remaining.*, store.projection_steps - before);
    try require(store.equalSymbolic(left, right) catch |err| return convert(err));
}
fn canonicalCarrier(store: *T.Store, id: T.Id, head_rows: []const u32) Error!T.Id {
    if (id == 0) return 0;
    const node = store.node(store.head(id, 0));
    if (node.tag != .function or node.a != T.unit or node.b != T.unit) return id;
    const row = store.row(store.resolveEffects(node.c, 0) catch |err| return convert(err));
    if (row.labels.len == 0 and row.tail == .variable and std.mem.findScalar(u32, head_rows, row.tail.variable) == null) return 0;
    return id;
}
const ProjectionWork = struct {
    store: *T.Store,
    remaining: *usize,
    observed: usize = 0,
    fn sync(self: *@This()) Error!void {
        const spent = self.store.projection_steps - self.observed;
        try require(spent <= self.remaining.*);
        self.remaining.* -= spent;
        self.observed = self.store.projection_steps;
        self.store.projection_limit = self.store.projection_steps + self.remaining.*;
    }
    fn step(self: *@This()) Error!void {
        try self.sync();
        try charge(self.remaining);
        self.store.projection_limit = self.store.projection_steps + self.remaining.*;
    }
    fn failed(self: *@This()) void {
        self.remaining.* -= @min(self.remaining.*, self.store.projection_steps - self.observed);
    }
};
fn declarationRecipe(a: A, source: *const C.Types, owner: anytype, implementation: PI.Implementation, predicates: anytype, contract_predicates: anytype, remaining: *usize) Error!void {
    var destination = T.Store.init(a) catch |err| return convert(err);
    defer destination.deinit();
    destination.has_projections = true;
    destination.resolution_depth_limit = 256;
    var work: ProjectionWork = .{ .store = &destination, .remaining = remaining };
    try work.sync();
    errdefer work.failed();
    var copy: Copier = .{ .allocator = a, .source = source, .destination = &destination, .max_depth = 256, .max_nodes = 1_000_000, .remaining = remaining, .projection_observed = &work.observed };
    defer copy.deinit();
    const contract = for (owner.contracts) |candidate| {
        if (std.meta.eql(candidate.identity, implementation.contract)) break candidate;
    } else return error.InvalidArtifact;
    const head = try list(a, &copy, implementation.head);
    const arguments = try a.dupe(T.Id, destination.list(head));
    defer a.free(arguments);
    for (source.list(contract.parameters), arguments) |pattern, actual| {
        destination.unify(copy.ty(pattern, 0) catch |err| return convert(err), actual) catch |err| return convert(err);
    }
    const pack = destination.product(arguments) catch |err| return convert(err);
    const head_rows = destination.freeRowVariables(pack) catch |err| return convert(err);
    defer a.free(head_rows);
    // Only equations for this declaration's exact symbolic head authorize
    // substitution. No wanted result can select or specialize another head.
    const recipe_members = owner.implementation_members[implementation.members.start..][0..implementation.members.len];
    for (recipe_members) |member| _ = copy.ty(member.root, 0) catch |err| return convert(err);
    for (owner.contract_members[contract.members.start..][0..contract.members.len]) |member| _ = copy.ty(member.root, 0) catch |err| return convert(err);
    for (predicates[implementation.predicates.start..][0..implementation.predicates.len]) |predicate| {
        inline for (.{ "ty", "other", "result", "signature" }) |field| _ = copy.ty(@field(predicate, field), 0) catch |err| return convert(err);
    }
    for (contract_predicates[contract.predicates.start..][0..contract.predicates.len]) |predicate| {
        inline for (.{ "ty", "other", "result", "signature" }) |field| _ = copy.ty(@field(predicate, field), 0) catch |err| return convert(err);
    }
    try work.sync();
    var index: usize = 0;
    while (index < destination.nodes.items.len) : (index += 1) {
        try work.step();
        const node = destination.nodes.items[index];
        if (node.tag != .projection or node.a != contract.identity.unit or node.b != contract.identity.decl) continue;
        const inputs = try a.dupe(T.Id, destination.nominalArguments(node));
        defer a.free(inputs);
        if (inputs.len != arguments.len) return error.InvalidArtifact;
        var same = true;
        for (inputs, arguments) |actual, expected| {
            const resolved_input = destination.resolve(actual, 0) catch |err| return convert(err);
            const resolved_head = destination.resolve(expected, 0) catch |err| return convert(err);
            if (!(destination.equalSymbolic(resolved_input, resolved_head) catch |err| return convert(err))) {
                same = false;
                break;
            }
        }
        if (!same) continue;
        const name = destination.projectionMember(node);
        var equation: T.Id = 0;
        for (recipe_members) |member| {
            if (member.kind == .type_ and member.name == name) {
                equation = copy.ty(member.root, 0) catch |err| return convert(err);
                break;
            }
        }
        if (equation == 0) {
            for (owner.contract_members[contract.members.start..][0..contract.members.len]) |member| {
                if (member.kind == .defined_type and member.name == name) {
                    equation = copy.ty(member.root, 0) catch |err| return convert(err);
                    break;
                }
            }
        }
        if (equation != 0) destination.bindAssociated(@intCast(index), equation) catch |err| return convert(err);
    }
    const Given = @import("given_equations.zig");
    var equations: std.ArrayList(Given.Equation) = .empty;
    defer equations.deinit(a);
    for (predicates[implementation.predicates.start..][0..implementation.predicates.len]) |predicate| {
        if (predicate.kind != .type_eq) continue;
        try work.step();
        try equations.append(a, .{ .left = copy.ty(predicate.ty, 0) catch |err| return convert(err), .right = copy.ty(predicate.result, 0) catch |err| return convert(err) });
    }
    var given: Given.Rewrite = .{ .store = &destination, .equations = equations.items };
    for (recipe_members) |member| {
        try work.sync();
        _ = destination.resolve(copy.ty(member.root, 0) catch |err| return convert(err), 0) catch |err| return convert(err);
        if (member.kind != .value) continue;
        const descriptor = for (owner.contract_members[contract.members.start..][0..contract.members.len]) |candidate| {
            if (candidate.name == member.name) break candidate;
        } else return error.InvalidArtifact;
        const expected = given.normalize(copy.ty(descriptor.root, 0) catch |err| return convert(err)) catch |err| return convert(err);
        const actual = given.normalize(copy.ty(member.root, 0) catch |err| return convert(err)) catch |err| return convert(err);
        try require(destination.equalSymbolic(expected, actual) catch |err| return convert(err));
        if (member.target.unit == owner.unit) {
            const binding = owner.bindings[member.target.binding];
            try require(binding.private);
            if (binding.scheme.root == 0) {
                if (comptime @hasField(@TypeOf(owner.*), "bodies")) return error.InvalidArtifact;
                // Principal-only exports tombstone private executable bindings;
                // the corresponding owned Core validates their signatures.
                try require(binding.name == 0 and binding.ty == 0);
            } else {
                const signature = given.normalize(copy.ty(binding.scheme.root, 0) catch |err| return convert(err)) catch |err| return convert(err);
                try require(destination.equalSymbolic(actual, signature) catch |err| return convert(err));
            }
        }
    }
    for (contract_predicates[contract.predicates.start..][0..contract.predicates.len]) |expected| {
        var found = false;
        for (predicates[implementation.predicates.start..][0..implementation.predicates.len]) |actual| {
            try work.step();
            if (actual.kind != expected.kind or actual.name != expected.name or actual.operator != expected.operator or !std.meta.eql(actual.identity, expected.identity)) continue;
            var same = true;
            inline for (.{ "ty", "other", "result", "signature" }) |field| {
                var first = copy.ty(@field(expected, field), 0) catch |err| return convert(err);
                var second = copy.ty(@field(actual, field), 0) catch |err| return convert(err);
                if (comptime std.mem.eql(u8, field, "signature")) {
                    if (actual.kind == .dispatch or actual.kind == .receiver or actual.kind == .update) {
                        first = try canonicalCarrier(&destination, first, head_rows);
                        second = try canonicalCarrier(&destination, second, head_rows);
                    }
                }
                first = destination.resolve(first, 0) catch |err| return convert(err);
                second = destination.resolve(second, 0) catch |err| return convert(err);
                if (!(destination.equalSymbolic(first, second) catch |err| return convert(err))) same = false;
            }
            if (same) {
                found = true;
                break;
            }
        }
        try require(found);
    }
    try work.sync();
}
fn templateRecipes(a: A, source: *const C.Types, owner: anytype, contract_predicates: anytype, remaining: *usize) Error!void {
    if (owner.member_templates.len == 0) return;
    var destination = T.Store.init(a) catch |err| return convert(err);
    defer destination.deinit();
    var copy: Copier = .{ .allocator = a, .source = source, .destination = &destination, .max_depth = 256, .max_nodes = 1_000_000, .remaining = remaining };
    defer copy.deinit();
    const claimed = try a.alloc(bool, owner.bindings.len);
    defer a.free(claimed);
    @memset(claimed, false);
    for (owner.member_templates, 0..) |template, ordinal| {
        try charge(remaining);
        try require(!claimed[template.binding]);
        claimed[template.binding] = true;
        const binding = owner.bindings[template.binding];
        const contract = for (owner.contracts) |candidate| {
            if (std.meta.eql(candidate.identity, template.contract)) break candidate;
        } else return error.InvalidArtifact;
        const descriptor = for (owner.contract_members[contract.members.start..][0..contract.members.len]) |candidate| {
            if (candidate.name == template.name) break candidate;
        } else return error.InvalidArtifact;
        try require(descriptor.kind == .value and binding.private == contract.private and binding.kind == .global);
        try require(source.node(descriptor.root).tag == .function);
        try sameRoot(&copy, binding.ty, descriptor.root, remaining);
        try sameRoot(&copy, binding.scheme.root, descriptor.root, remaining);
        try require(std.mem.eql(T.Id, source.list(binding.scheme.variables), source.list(contract.variables)));
        try require(std.mem.eql(u32, source.list(binding.scheme.row_variables), source.list(contract.row_variables)));
        try require(template.arguments.len == contract.parameters.len);
        for (source.list(template.arguments), source.list(contract.parameters)) |argument, expected| try sameRoot(&copy, argument, expected, remaining);
        const clauses = owner.obligations[binding.scheme.obligations.start..][0..binding.scheme.obligations.len];
        const prerequisites = contract_predicates[contract.predicates.start..][0..contract.predicates.len];
        try require(clauses.len == prerequisites.len + 1);
        for (clauses[0..prerequisites.len], prerequisites) |actual, expected| {
            try charge(remaining);
            try require(actual.kind == expected.kind and actual.name == expected.name and actual.operator == expected.operator and std.meta.eql(actual.identity, expected.identity) and actual.explicit == expected.explicit);
            inline for (.{ "ty", "other", "result", "signature" }) |field| try sameRoot(&copy, @field(actual, field), @field(expected, field), remaining);
        }
        const self = clauses[prerequisites.len];
        try require(self.kind == .contract and std.meta.eql(self.identity, contract.identity) and self.explicit and self.other == 0 and self.result == 0 and self.signature == 0);
        const pack = source.node(self.ty);
        try require(pack.tag == .product and pack.b == contract.parameters.len);
        for (source.list(.{ .start = pack.a, .len = pack.b }), source.list(contract.parameters)) |argument, expected| try sameRoot(&copy, argument, expected, remaining);
        if (comptime @hasField(@TypeOf(owner.*), "bodies")) {
            try require(binding.body_id != 0);
            const body = owner.bodies[binding.body_id];
            try require(body.binding == template.binding and body.is_function and std.meta.eql(body.scheme, binding.scheme));
            const root = owner.node(body.root);
            try require(root.tag == .contract_method and root.a == ordinal and root.c == body.parameters.len);
            var expected = descriptor.root;
            for (owner.parameters[body.parameters.start..][0..body.parameters.len], owner.children(body.root)) |parameter, argument| {
                try charge(remaining);
                const arrow = source.node(expected);
                try require(arrow.tag == .function);
                try sameRoot(&copy, parameter.ty, arrow.a, remaining);
                const reference = owner.node(argument);
                try require(reference.tag == .reference and owner.references[reference.a].binding == parameter.binding and (owner.references[reference.a].unit == 0 or owner.references[reference.a].unit == owner.unit));
                try sameRoot(&copy, reference.ty, arrow.a, remaining);
                expected = arrow.b;
            }
            try require(source.node(expected).tag != .function);
            try sameRoot(&copy, root.ty, expected, remaining);
        }
    }
    if (comptime @hasField(@TypeOf(owner.*), "nodes")) {
        for (owner.nodes, 0..) |node, index| if (node.tag == .contract_method) {
            try charge(remaining);
            const template = owner.member_templates[node.a];
            try require(owner.bodies[owner.bindings[template.binding].body_id].root == index);
        };
    }
}
/// Called only after ordinary bounds and structural graph cycles are checked.
fn unrestrictedAssociatedType(source: *const C.Types, nominals: anytype, root: T.Id, remaining: *usize) Error!void {
    var work: @import("../check/usage_check.zig").Work = .{ .remaining = remaining.* };
    defer remaining.* = work.remaining;
    try require(!(@import("../check/usage_check.zig").containsNominalWork(source, nominals, root, &work) catch |err| return convert(err)));
}
pub fn scopes(a: A, source: *const C.Types, owner: anytype, predicates: anytype, remaining: *usize) Error!void {
    if (comptime @hasField(@TypeOf(owner.*), "contract_predicates")) {
        try templateRecipes(a, source, owner, owner.contract_predicates, remaining);
    } else {
        try templateRecipes(a, source, owner, owner.obligations, remaining);
    }
    for (owner.contract_members) |member| if (member.kind == .defined_type) try unrestrictedAssociatedType(source, owner.nominals, member.root, remaining);
    if (owner.implementations.len == 0) return;
    const frozen = graph(source);
    const view: F.Source = .{ .frozen = &frozen };
    const claimed = try a.alloc(bool, owner.implementation_members.len);
    defer a.free(claimed);
    @memset(claimed, false);
    const claimed_predicates = try a.alloc(bool, predicates.len);
    defer a.free(claimed_predicates);
    @memset(claimed_predicates, false);
    var destination = T.Store.init(a) catch |err| return convert(err);
    defer destination.deinit();
    var heads: std.ArrayList(PI.Implementation) = .empty;
    defer heads.deinit(a);
    for (owner.implementations, 0..) |implementation, ordinal| {
        try charge(remaining);
        for (owner.implementations[0..ordinal]) |prior| try require(!std.meta.eql(prior.identity, implementation.identity));
        if (implementation.private and implementation.name == 0) continue;
        if (comptime @hasField(@TypeOf(owner.*), "contract_predicates")) {
            try declarationRecipe(a, source, owner, implementation, predicates, owner.contract_predicates, remaining);
        } else {
            try declarationRecipe(a, source, owner, implementation, predicates, owner.obligations, remaining);
        }
        const contract = for (owner.contracts) |candidate| {
            if (std.meta.eql(candidate.identity, implementation.contract)) break candidate;
        } else return error.InvalidArtifact;
        try require(contract.requires_implementation and implementation.head.len == contract.parameters.len);
        for (source.list(implementation.head)) |root| try associated.scope(a, view, implementation, root, false, remaining);
        for (source.list(implementation.row_parameters), source.list(implementation.row_variables)) |row, variable| {
            try require(source.row(row).labels.len == 0 and source.row(row).tail == .variable and source.row(row).tail.variable == variable);
        }
        for (source.list(implementation.variables), 0..) |variable, index| {
            for (source.list(implementation.variables)[0..index]) |prior| try require(prior != variable);
        }
        for (source.list(implementation.row_variables), 0..) |variable, index| {
            for (source.list(implementation.row_variables)[0..index]) |prior| try require(prior != variable);
        }
        for (owner.implementation_members[implementation.members.start..][0..implementation.members.len], implementation.members.start..) |member, index| {
            try require(!claimed[index]);
            claimed[index] = true;
            const descriptor = for (owner.contract_members[contract.members.start..][0..contract.members.len]) |candidate| {
                if (candidate.name == member.name) break candidate;
            } else return error.InvalidArtifact;
            try require(descriptor.kind != .defined_type and (descriptor.kind == .abstract_type) == (member.kind == .type_));
            for (owner.implementation_members[implementation.members.start..index]) |prior| try require(prior.name != member.name);
            try associated.scope(a, view, implementation, member.root, true, remaining);
            if (member.kind == .type_) try unrestrictedAssociatedType(source, owner.nominals, member.root, remaining);
        }
        for (owner.contract_members[contract.members.start..][0..contract.members.len]) |descriptor| {
            if (descriptor.kind == .defined_type) continue;
            var present = false;
            for (owner.implementation_members[implementation.members.start..][0..implementation.members.len]) |member| if (member.name == descriptor.name) {
                present = true;
                break;
            };
            try require(present);
        }
        for (predicates[implementation.predicates.start..][0..implementation.predicates.len], implementation.predicates.start..) |predicate, index| {
            if (comptime @TypeOf(predicates) == []const T.Obligation) try require(!claimed_predicates[index]);
            claimed_predicates[index] = true;
            inline for (.{ "ty", "other", "result", "signature" }) |field| try associated.scope(a, view, implementation, @field(predicate, field), false, remaining);
        }
        var copy: Copier = .{ .allocator = a, .source = source, .destination = &destination, .max_depth = 256, .max_nodes = 1_000_000, .remaining = remaining };
        defer copy.deinit();
        const declaration = try imported(a, &copy, implementation);
        for (destination.list(declaration.head)) |root| try require(!(destination.containsProjection(root) catch |err| return convert(err)));
        const roots = try a.dupe(T.Id, destination.list(declaration.head));
        defer a.free(roots);
        const pack = destination.product(roots) catch |err| return convert(err);
        const variables = destination.freeVariables(pack) catch |err| return convert(err);
        defer a.free(variables);
        try require(variables.len == declaration.variables.len);
        const rows = destination.freeRowVariables(pack) catch |err| return convert(err);
        defer a.free(rows);
        try require(rows.len == declaration.row_variables.len);
        for (heads.items) |prior| {
            destination.projection_limit = destination.projection_steps + remaining.*;
            const before = destination.projection_steps;
            const overlap = @import("implementation_patterns.zig").overlap(&destination, prior, declaration) catch |err| return convert(err);
            remaining.* -= @min(remaining.*, destination.projection_steps - before);
            try require(!overlap);
        }
        try heads.append(a, declaration);
        {
            const point = destination.mark();
            defer destination.rollback(point);
            var contract_copy: Copier = .{ .allocator = a, .source = source, .destination = &destination, .max_depth = 256, .max_nodes = 1_000_000, .remaining = remaining };
            defer contract_copy.deinit();
            var anchor: T.Id = 0;
            if (contract.variables.len != 0) anchor = contract_copy.ty(source.list(contract.variables)[0], 0) catch |err| return convert(err);
            for (source.list(contract.parameters), roots) |pattern, actual| {
                const expected = contract_copy.ty(pattern, 0) catch |err| return convert(err);
                destination.unify(expected, actual) catch |err| return convert(err);
            }
            if (implementation.identity.unit != contract.identity.unit) {
                try require(anchor != 0);
                const head = destination.node(destination.head(anchor, 0));
                try require(head.tag == .nominal and head.a == implementation.identity.unit);
            }
        }
    }
    for (owner.implementation_members, claimed) |member, used| if (!used) try require(member.name == 0 and member.root == 0 and member.target.unit == 0 and member.target.binding == 0);
}

fn recipe(value: PI.Implementation) PI.Contract {
    return .{ .private = value.private, .identity = value.identity, .name = value.name, .parameters = value.head, .variables = value.variables, .parameter_names = value.parameter_names, .row_variables = value.row_variables, .row_parameter_names = value.row_parameter_names, .row_parameters = value.row_parameters, .requires_implementation = true };
}
fn members(a: A, contract: T.NominalIdentity, values: []const PI.ImplementationMember) A.Error![]PI.ContractMember {
    const result = try a.alloc(PI.ContractMember, values.len);
    for (values, result) |value, *member| {
        var kind: @FieldType(PI.ContractMember, "kind") = .defined_type;
        if (value.kind == .value) kind = .value;
        member.* = .{ .contract = contract, .name = value.name, .kind = kind, .root = value.root };
    }
    return result;
}
fn equivalent(a: A, first: *const C.Types, second: *const C.Types, left: PI.Implementation, right: PI.Implementation, left_members: []const PI.ImplementationMember, right_members: []const PI.ImplementationMember, left_predicates: anytype, right_predicates: anytype, remaining: *usize) Error!void {
    try require(std.meta.eql(left.contract, right.contract) and std.meta.eql(left.origin_span, right.origin_span));
    try require(std.mem.eql(u32, first.list(left.parameter_names), second.list(right.parameter_names)));
    try require(left_members.len == right_members.len);
    for (left_members, right_members) |before, after| try require(std.meta.eql(before.target, after.target));
    const before = try members(a, left.contract, left_members);
    defer a.free(before);
    const after = try members(a, right.contract, right_members);
    defer a.free(after);
    try associated.equivalent(a, first, second, recipe(left), recipe(right), before, after, left_predicates, right_predicates, remaining);
}
pub fn publicCore(a: A, principal: *const PI.Interface, executable: *const C.Module, remaining: *usize) Error!void {
    try selectedPrincipal(a, principal, executable, remaining);
    const first = associated.typesView(&principal.graph);
    for (principal.implementations) |implementation| {
        if (implementation.private) continue;
        const original = for (executable.implementations) |candidate| {
            if (std.meta.eql(candidate.identity, implementation.identity)) break candidate;
        } else return error.InvalidArtifact;
        try equivalent(a, &first, &executable.types, implementation, original, principal.implementation_members[implementation.members.start..][0..implementation.members.len], executable.implementation_members[original.members.start..][0..original.members.len], principal.implementation_predicates[implementation.predicates.start..][0..implementation.predicates.len], executable.obligations[original.predicates.start..][0..original.predicates.len], remaining);
    }
    for (executable.implementations) |implementation| {
        if (implementation.private) continue;
        var present = false;
        for (principal.implementations) |candidate| if (!candidate.private and std.meta.eql(candidate.identity, implementation.identity)) {
            present = true;
            break;
        };
        try require(present);
    }
}
fn selectedPrincipal(a: A, principal: *const PI.Interface, executable: *const C.Module, remaining: *usize) Error!void {
    if (principal.selected_proofs.len == 0) {
        try require(principal.selected_members.len == 0 and principal.selected_edges.len == 0);
        return;
    }
    // Public-only principal exports omit concrete certificates. Full retained
    // principals must preserve the corresponding independently proved Core DAG.
    try require(principal.selected_proofs.len == executable.selected_proofs.len and principal.selected_members.len == executable.selected_members.len);
    try require(std.mem.eql(u32, principal.selected_edges, executable.selected_edges));
    var destination = T.Store.init(a) catch |err| return convert(err);
    defer destination.deinit();
    const first = associated.typesView(&principal.graph);
    var before: Copier = .{ .allocator = a, .source = &first, .destination = &destination, .max_depth = 256, .max_nodes = 1_000_000, .remaining = remaining };
    defer before.deinit();
    var after: Copier = .{ .allocator = a, .source = &executable.types, .destination = &destination, .max_depth = 256, .max_nodes = 1_000_000, .remaining = remaining };
    defer after.deinit();
    const Compare = struct {
        fn root(left: *Copier, right: *Copier, first_: T.Id, second: T.Id, budget: *usize) Error!void {
            const original = left.ty(first_, 0) catch |err| return convert(err);
            const current = right.ty(second, 0) catch |err| return convert(err);
            const store = left.destination;
            store.has_projections = true;
            store.projection_limit = store.projection_steps + budget.*;
            const spent = store.projection_steps;
            defer budget.* -= @min(budget.*, store.projection_steps - spent);
            try require(store.equalSymbolic(original, current) catch |err| return convert(err));
        }
    };
    for (principal.selected_proofs, executable.selected_proofs) |original, current| {
        try charge(remaining);
        try require(original.context == current.context and original.kind == current.kind and std.meta.eql(original.implementation, current.implementation) and std.meta.eql(original.contract, current.contract));
        try require(std.meta.eql(original.predicate_target, current.predicate_target) and std.meta.eql(original.members, current.members) and std.meta.eql(original.prerequisites, current.prerequisites));
        try require(original.arguments.len == current.arguments.len);
        for (first.list(original.arguments), executable.types.list(current.arguments)) |left, right| try Compare.root(&before, &after, left, right, remaining);
        if (original.kind == .predicate) {
            try require(original.predicate.kind == current.predicate.kind and original.predicate.operator == current.predicate.operator and original.predicate.name == current.predicate.name and std.meta.eql(original.predicate.identity, current.predicate.identity));
            inline for (.{ "ty", "other", "result", "signature" }) |field| try Compare.root(&before, &after, @field(original.predicate, field), @field(current.predicate, field), remaining);
        }
    }
    for (principal.selected_members, executable.selected_members) |original, current| {
        try charge(remaining);
        try require(original.name == current.name and original.kind == current.kind and std.meta.eql(original.target, current.target));
        try Compare.root(&before, &after, original.root, current.root, remaining);
    }
}
pub fn originalProducers(a: A, owners: []const @import("../reuse/frozen_dependency.zig").Module, remaining: *usize) Error!void {
    for (owners) |owner| for (owner.interface.implementations) |implementation| {
        if (implementation.private) continue;
        try require(implementation.identity.unit != 0 and implementation.identity.unit <= owners.len);
        const producer = &owners[implementation.identity.unit - 1].interface;
        const original = for (producer.implementations) |candidate| {
            if (!candidate.private and std.meta.eql(candidate.identity, implementation.identity)) break candidate;
        } else return error.InvalidArtifact;
        const first = associated.typesView(&owner.interface.graph);
        const second = associated.typesView(&producer.graph);
        try equivalent(a, &first, &second, implementation, original, owner.interface.implementation_members[implementation.members.start..][0..implementation.members.len], producer.implementation_members[original.members.start..][0..original.members.len], owner.interface.implementation_predicates[implementation.predicates.start..][0..implementation.predicates.len], producer.implementation_predicates[original.predicates.start..][0..original.predicates.len], remaining);
    };
}
