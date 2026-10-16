//! Reconstruct complete closed selected proofs from admitted declaration
//! recipes. Serialized edges and member targets never authorize themselves.
const std = @import("std");
const C = @import("../check/core.zig");
const T = @import("../check/types.zig");
const E = @import("type_evidence.zig");
const P = @import("implementation_evidence.zig");
const PI = @import("../reuse/principal_interface.zig");
const A = std.mem.Allocator;
pub const Error = A.Error || error{InvalidArtifact};
fn require(value: bool) Error!void {
    if (!value) return error.InvalidArtifact;
}
fn convert(err: anyerror) Error {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    return error.InvalidArtifact;
}
const Host = struct {
    units: []const C.Module,
    evidence: E.Store,
    associated_remaining: usize,
    pub fn evidenceStore(self: *@This()) *E.Store {
        return &self.evidence;
    }
    pub fn implementationRead(_: *@This(), _: u32, _: T.NominalIdentity) A.Error!void {}
    pub fn implementationLegacyPredicate(self: *@This(), context: u32, value: C.Obligation, operands: [4]E.Id, resolver: E.ProjectionResolver) E.Error!?P.LegacyChoice {
        const module = for (self.units) |*candidate| {
            if (candidate.unit == context) break candidate;
        } else return null;
        if (value.kind == .field or value.kind == .writable_field) {
            if (self.evidence.node(operands[0]).tag == .record) {
                const fields = self.evidence.children(operands[0]);
                var at: usize = 0;
                while (at < fields.len) : (at += 2) {
                    if (fields[at] == value.name) {
                        if (operands[2] == 0 or operands[2] == fields[at + 1]) return .{ .target = .{ .unit = 0, .binding = 0 }, .carrier = operands[3] };
                        return null;
                    }
                }
            }
        }
        if (value.kind != .field and value.kind != .dispatch and value.kind != .receiver and value.kind != .result_dispatch and value.kind != .resolver_dispatch) return null;
        var selection_operands = [_]E.Id{ operands[0], operands[1] };
        if (value.kind == .result_dispatch) selection_operands[0] = operands[2];
        if (value.kind == .resolver_dispatch) {
            const resolver_type = self.evidence.node(operands[0]);
            if (resolver_type.tag != .resolver) return null;
            selection_operands[0] = resolver_type.a;
        }
        for (selection_operands, 0..) |operand, side| {
            if (side == 1 and value.kind != .dispatch) break;
            if (side == 1 and value.name == 0) {
                if (@import("implementation_predicates.zig").primitiveResult(&self.evidence, value.operator, operands[0], operands[1])) |result| {
                    if (result != operands[2]) return null;
                    var carrier = operands[3];
                    if (carrier == 0) carrier = try self.evidence.intern(.function, T.unit, T.unit, &.{});
                    return .{ .target = .{ .unit = 0, .binding = 0 }, .carrier = carrier };
                }
            }
            const node = self.evidence.node(operand);
            if (node.tag != .nominal and node.tag != .type_constructor and node.tag != .u32 and node.tag != .f32 and node.tag != .boolean and node.tag != .array and node.tag != .list and node.tag != .cursor) continue;
            var identity: T.NominalIdentity = .{ .unit = node.a, .decl = node.b };
            switch (node.tag) {
                .u32 => identity = .{ .unit = 0, .decl = T.u32_type },
                .f32 => identity = .{ .unit = 0, .decl = T.f32_type },
                .boolean => identity = .{ .unit = 0, .decl = T.boolean },
                .array => identity = .{ .unit = 0, .decl = std.math.maxInt(u32) },
                .list => identity = .{ .unit = 0, .decl = std.math.maxInt(u32) - 1 },
                .cursor => identity = .{ .unit = 0, .decl = std.math.maxInt(u32) - 2 },
                else => {},
            }
            for (module.associated) |method| {
                if (!std.meta.eql(identity, method.identity)) continue;
                if (value.name != 0) {
                    if (method.member != value.name) continue;
                } else if (method.operator != value.operator) continue;
                // Imported signatures have an admitted local external binding.
                // Read that copy rather than unvalidated foreign body graphs.
                const binding = for (module.bindings, 0..) |candidate, ordinal| {
                    if ((method.target.unit == context or method.target.unit == 0) and method.target.binding == ordinal) break candidate;
                    if (candidate.kind == .external and std.meta.eql(candidate.target, method.target)) break candidate;
                } else continue;
                var mappings: std.ArrayList(E.Mapping) = .empty;
                defer mappings.deinit(self.evidence.allocator);
                var rows: std.ArrayList(E.RowMapping) = .empty;
                defer rows.deinit(self.evidence.allocator);
                var arity: usize = 2;
                if (value.kind == .field or value.kind == .result_dispatch) arity = 1;
                var carrier: E.Id = 0;
                if (value.kind == .resolver_dispatch) {
                    if (!try self.evidence.matchLegacySignature(&module.types, binding.scheme.root, operands[1], &mappings, &rows, resolver)) continue;
                } else carrier = try self.evidence.matchPrerequisite(&module.types, binding.scheme.root, operands, arity, &mappings, &rows, resolver) orelse continue;
                for (mappings.items) |mapping| if (std.mem.findScalar(T.Id, module.types.list(binding.scheme.variables), mapping.variable) == null) return null;
                for (rows.items) |mapping| if (std.mem.findScalar(u32, module.types.list(binding.scheme.row_variables), mapping.variable) == null) return null;
                var original = method.target;
                if (original.unit == 0) original.unit = context;
                return .{ .target = original, .carrier = carrier };
            }
        }
        return null;
    }
};
const Validator = struct {
    allocator: A,
    module: *const C.Module,
    host: *Host,
    derived: *P.Store,
    matched: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    fn root(self: *@This(), value: T.Id) Error!E.Id {
        if (value == 0) return 0;
        return self.host.evidence.projectWithBudget(&self.module.types, value, &.{}, &.{}, &self.host.associated_remaining) catch |err| return convert(err);
    }
    fn compare(self: *@This(), supplied: u32, inferred: u32, depth: usize) Error!void {
        try require(depth < 256);
        try require(self.host.associated_remaining != 0);
        self.host.associated_remaining -= 1;
        const memo = try self.matched.getOrPut(self.allocator, supplied);
        if (memo.found_existing) return require(memo.value_ptr.* == inferred);
        memo.value_ptr.* = inferred;
        const before = self.module.selected_proofs[supplied];
        const after = self.derived.proofs.items[inferred];
        var context = before.context;
        if (context == 0) context = self.module.unit;
        try require(context == after.context and std.meta.eql(before.implementation, after.implementation) and std.meta.eql(before.contract, after.contract));
        try require(@backingInt(before.kind) == @backingInt(after.kind));
        try require(before.arguments.len == after.arguments.len and before.members.len == after.members.len and before.prerequisites.len == after.prerequisites.len);
        for (self.module.types.list(before.arguments), self.derived.arguments.items[after.arguments.start..][0..after.arguments.len]) |argument, expected| try require(try self.root(argument) == expected);
        if (before.kind == .predicate) {
            const fact = before.predicate;
            try require(std.meta.eql(before.predicate_target, PI.ExternalTarget{ .unit = after.predicate.target.unit, .binding = after.predicate.target.binding }));
            try require(fact.kind == after.predicate.kind and fact.operator == after.predicate.operator and fact.name == after.predicate.name and std.meta.eql(fact.identity, after.predicate.identity));
            for ([_]T.Id{ fact.ty, fact.other, fact.result, fact.signature }, after.predicate.operands) |operand, expected| try require(try self.root(operand) == expected);
        }
        for (self.module.selected_members[before.members.start..][0..before.members.len], self.derived.members.items[after.members.start..][0..after.members.len]) |member, expected| {
            try require(member.name == expected.name and member.kind == expected.kind and std.meta.eql(C.BindingRef{ .unit = member.target.unit, .binding = member.target.binding }, expected.target));
            try require(try self.root(member.root) == expected.root);
        }
        for (self.module.selected_edges[before.prerequisites.start..][0..before.prerequisites.len], self.derived.edges.items[after.prerequisites.start..][0..after.prerequisites.len]) |child, expected| try self.compare(child, expected, depth + 1);
    }
};
pub fn core(a: A, module: *const C.Module, remaining: *usize) Error!void {
    if (module.selected_proofs.len == 0) {
        try require(module.selected_members.len == 0 and module.selected_edges.len == 0 and module.selected_uses.len == 0);
        return;
    }
    var host: Host = .{ .units = &.{module.*}, .evidence = E.Store.init(a) catch |err| return convert(err), .associated_remaining = remaining.* };
    defer remaining.* = host.associated_remaining;
    defer host.evidence.deinit();
    var derived: P.Store = .{ .allocator = a };
    defer derived.deinit();
    var validator: Validator = .{ .allocator = a, .module = module, .host = &host, .derived = &derived };
    defer validator.matched.deinit(a);
    var members_count: usize = 0;
    var edges_count: usize = 0;
    for (module.selected_proofs, 0..) |proof, ordinal| {
        try require(proof.context == 0 or proof.context == module.unit);
        if (proof.members.len != 0) try require(proof.members.start == members_count);
        if (proof.prerequisites.len != 0) try require(proof.prerequisites.start == edges_count);
        members_count += proof.members.len;
        edges_count += proof.prerequisites.len;
        if (proof.kind == .predicate) continue;
        var arguments: std.ArrayList(E.Id) = .empty;
        defer arguments.deinit(a);
        for (module.types.list(proof.arguments)) |argument| try arguments.append(a, try validator.root(argument));
        const selected = derived.resolve(&host, module.unit, proof.contract, arguments.items) catch |err| return convert(err);
        try validator.compare(@intCast(ordinal), selected, 0);
    }
    // A predicate certificate is meaningful only beneath a complete root.
    try require(validator.matched.count() == module.selected_proofs.len and members_count == module.selected_members.len and edges_count == module.selected_edges.len);
}

const SnapshotValidator = struct {
    allocator: A,
    source: P.View,
    host: *Host,
    derived: *P.Store,
    imports: *@import("semantic_evidence_import.zig").Importer,
    matched: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    fn root(self: *@This(), value: E.Id) Error!E.Id {
        return self.imports.ty(value, 0) catch |err| return convert(err);
    }
    fn compare(self: *@This(), supplied: u32, inferred: u32, depth: usize) Error!void {
        try require(depth < 256 and self.host.associated_remaining != 0);
        self.host.associated_remaining -= 1;
        const memo = try self.matched.getOrPut(self.allocator, supplied);
        if (memo.found_existing) return require(memo.value_ptr.* == inferred);
        memo.value_ptr.* = inferred;
        const before = self.source.proofs[supplied];
        const after = self.derived.proofs.items[inferred];
        try require(before.context == after.context and before.kind == after.kind and std.meta.eql(before.implementation, after.implementation) and std.meta.eql(before.contract, after.contract));
        try require(before.arguments.len == after.arguments.len and before.members.len == after.members.len and before.prerequisites.len == after.prerequisites.len);
        for (self.source.arguments[before.arguments.start..][0..before.arguments.len], self.derived.arguments.items[after.arguments.start..][0..after.arguments.len]) |argument, expected| try require(try self.root(argument) == expected);
        if (before.kind == .predicate) {
            const fact = before.predicate;
            try require(fact.kind == after.predicate.kind and fact.operator == after.predicate.operator and fact.name == after.predicate.name and std.meta.eql(fact.identity, after.predicate.identity) and std.meta.eql(fact.target, after.predicate.target));
            for (fact.operands, after.predicate.operands) |operand, expected| try require(try self.root(operand) == expected);
        }
        for (self.source.members[before.members.start..][0..before.members.len], self.derived.members.items[after.members.start..][0..after.members.len]) |member, expected| {
            try require(member.name == expected.name and member.kind == expected.kind and std.meta.eql(member.target, expected.target));
            try require(try self.root(member.root) == expected.root);
        }
        for (self.source.edges[before.prerequisites.start..][0..before.prerequisites.len], self.derived.edges.items[after.prerequisites.start..][0..after.prerequisites.len]) |child, expected| try self.compare(child, expected, depth + 1);
    }
};
/// Bounds and evidence graph validity precede reconstruction. No archived
/// method target, member kind or prerequisite edge authorizes itself.
pub fn snapshot(a: A, units: []const C.Module, evidence: E.View, supplied: P.View, remaining: *usize) Error!void {
    if (supplied.proofs.len == 0) {
        try require(supplied.members.len == 0 and supplied.arguments.len == 0 and supplied.edges.len == 0);
        return;
    }
    var host: Host = .{ .units = units, .evidence = E.Store.init(a) catch |err| return convert(err), .associated_remaining = remaining.* };
    defer remaining.* = host.associated_remaining;
    defer host.evidence.deinit();
    var imports: @import("semantic_evidence_import.zig").Importer = .{ .allocator = a, .source = evidence, .destination = &host.evidence, .max_depth = 256, .remaining = &host.associated_remaining };
    defer imports.deinit();
    var derived: P.Store = .{ .allocator = a };
    defer derived.deinit();
    var validator: SnapshotValidator = .{ .allocator = a, .source = supplied, .host = &host, .derived = &derived, .imports = &imports };
    defer validator.matched.deinit(a);
    var arguments_count: usize = 0;
    var members_count: usize = 0;
    var edges_count: usize = 0;
    for (supplied.proofs, 0..) |proof, ordinal| {
        if (proof.arguments.len != 0) try require(proof.arguments.start == arguments_count);
        if (proof.members.len != 0) try require(proof.members.start == members_count);
        if (proof.prerequisites.len != 0) try require(proof.prerequisites.start == edges_count);
        arguments_count += proof.arguments.len;
        members_count += proof.members.len;
        edges_count += proof.prerequisites.len;
        if (proof.kind == .predicate) {
            try require(proof.arguments.len == 0 and proof.members.len == 0);
            continue;
        }
        var arguments: std.ArrayList(E.Id) = .empty;
        defer arguments.deinit(a);
        for (supplied.arguments[proof.arguments.start..][0..proof.arguments.len]) |argument| try arguments.append(a, try validator.root(argument));
        const selected = derived.resolve(&host, proof.context, proof.contract, arguments.items) catch |err| return convert(err);
        try validator.compare(@intCast(ordinal), selected, 0);
    }
    try require(arguments_count == supplied.arguments.len and members_count == supplied.members.len and edges_count == supplied.edges.len and validator.matched.count() == supplied.proofs.len);
}
