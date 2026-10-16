//! Witness and handler equations use an invocation-local store.
//! Only recorded principal closing decisions can close an otherwise open tail.
const std = @import("std");
const T = @import("../check/types.zig");
const E = @import("type_evidence.zig");
const graph = @import("../reuse/principal_type_graph.zig");

pub fn reconstruct(evidence: *E.Store, source: anytype, clauses: anytype, certificates: []const u32, variables: []const T.Id, mappings: *std.ArrayList(E.Mapping), rows: *std.ArrayList(E.RowMapping), resolver: E.ProjectionResolver) E.Error!void {
    var needed = false;
    for (clauses) |clause| {
        if (resolver.remaining.* == 0) return error.EvidenceLimit;
        resolver.remaining.* -= 1;
        if (clause.kind == .effect_handler or clause.kind == .type_head) {
            needed = true;
            break;
        }
    }
    if (!needed) return;
    const allocator = evidence.allocator;
    var scratch = T.Store.init(allocator) catch |err| return convert(err);
    defer scratch.deinit();
    scratch.resolution_depth_limit = 256;
    scratch.projection_limit = resolver.remaining.*;
    scratch.has_projections = true;
    var observed: usize = 0;
    defer {
        const spent = scratch.projection_steps - observed;
        if (spent > resolver.remaining.*) {
            resolver.remaining.* = 0;
        } else resolver.remaining.* -= spent;
    }
    const Copier = if (@TypeOf(source) == *const T.Store) graph.NormalizedCopy else graph.FrozenCopy;
    var copy: Copier = .{ .allocator = allocator, .source = source, .destination = &scratch, .max_depth = 256, .max_nodes = 1_000_000, .remaining = resolver.remaining, .projection_observed = &observed };
    defer copy.deinit();
    var closed: @import("closed_evidence_import.zig").Importer = .{ .allocator = allocator, .source = evidence.view(), .destination = &scratch };
    defer closed.deinit();
    for (mappings.items) |mapping| {
        scratch.chargeProjection() catch |err| return convert(err);
        const actual = closed.ty(mapping.evidence, 0) catch |err| return convert(err);
        try copy.types.put(allocator, mapping.variable, actual);
    }
    for (rows.items) |mapping| {
        scratch.chargeProjection() catch |err| return convert(err);
        const actual = closed.row(mapping.evidence, 0) catch |err| return convert(err);
        try copy.row_variables.put(allocator, mapping.variable, actual);
    }
    // Only known witness inputs determine these ordinary principal variables.
    // No associated output or implementation head participates in this solve.
    for (clauses) |clause| {
        if (clause.kind != .type_head) continue;
        var root = copy.ty(clause.ty, 0) catch |err| return convert(err);
        var depth: usize = 0;
        while (true) {
            root = scratch.resolve(root, 0) catch |err| return convert(err);
            const node = scratch.node(root);
            if (node.tag != .function) break;
            if (depth >= 256) return error.EvidenceLimit;
            scratch.chargeProjection() catch |err| return convert(err);
            depth += 1;
            root = node.b;
        }
        if (!(scratch.equalClosed(root, root) catch |err| return convert(err))) continue;
        const result = copy.ty(clause.result, 0) catch |err| return convert(err);
        scratch.unify(result, root) catch |err| return convert(err);
    }
    for (variables) |variable| {
        scratch.chargeProjection() catch |err| return convert(err);
        var known = false;
        for (mappings.items) |mapping| {
            scratch.chargeProjection() catch |err| return convert(err);
            if (mapping.variable == variable) {
                known = true;
                break;
            }
        }
        if (known) continue;
        const copied = copy.ty(variable, 0) catch |err| return convert(err);
        const resolved = scratch.resolve(copied, 0) catch |err| return convert(err);
        if (!(scratch.equalClosed(resolved, resolved) catch |err| return convert(err))) continue;
        try syncBudget(&scratch, &observed, resolver.remaining);
        const actual = try evidence.projectWithBudget(&scratch, resolved, &.{}, &.{}, resolver.remaining);
        try mappings.append(allocator, .{ .variable = variable, .evidence = actual });
    }
    for (clauses) |clause| {
        if (resolver.remaining.* == 0) return error.EvidenceLimit;
        resolver.remaining.* -= 1;
        if (clause.kind != .effect_handler) continue;
        try syncBudget(&scratch, &observed, resolver.remaining);
        const token_id = try evidence.projectSelected(source, clause.ty, mappings.items, rows.items, resolver);
        const token = evidence.node(token_id);
        if (token.tag != .nominal) return error.TypeMismatch;
        closed.source = evidence.view();
        const imported = closed.ty(token_id, 0) catch |err| return convert(err);
        const nominal = scratch.node(imported);
        const label = scratch.internOperation(.{ .unit = token.a, .decl = token.b }, scratch.nominalArguments(nominal)) catch |err| return convert(err);
        const extended = source.node(source.head(clause.signature, 0));
        const residual = source.node(source.head(clause.other, 0));
        if (extended.tag != .function or residual.tag != .function) return error.TypeMismatch;
        const left = copy.row(extended.c, 0) catch |err| return convert(err);
        const right = copy.row(residual.c, 0) catch |err| return convert(err);
        const tail = scratch.resolveEffects(right, 0) catch |err| return convert(err);
        var labels: std.ArrayList(T.Effects.Label) = .empty;
        defer labels.deinit(allocator);
        try labels.append(allocator, label);
        try labels.appendSlice(allocator, scratch.rowLabels(tail));
        const row = scratch.effects.rowAt(labels.items, scratch.row(tail).tail, scratch.row(tail).cursor) catch |err| return convert(T.effectError(err));
        try unifyRows(&scratch, left, row);
    }
    // All supplied rows are already closed. Unmapped rows are fresh in this
    // invocation, so certificate propagation cannot close a caller's row.
    for (certificates) |variable| {
        scratch.chargeProjection() catch |err| return convert(err);
        const copied = copy.row_variables.get(variable) orelse continue;
        const resolved = scratch.resolveEffects(copied, 0) catch |err| return convert(err);
        const tail = scratch.row(resolved).tail;
        if (tail != .variable) continue;
        const established = scratch.effects.row(scratch.rowLabels(resolved), .closed) catch |err| return convert(T.effectError(err));
        try unifyRows(&scratch, resolved, established);
    }
    // Synchronize solver work before projecting its closed rows back to owned
    // evidence; that projection uses the same project-operation budget.
    try syncBudget(&scratch, &observed, resolver.remaining);
    var row_variables = copy.row_variables.iterator();
    while (row_variables.next()) |entry| {
        scratch.chargeProjection() catch |err| return convert(err);
        var known = false;
        for (rows.items) |mapping| {
            scratch.chargeProjection() catch |err| return convert(err);
            if (mapping.variable == entry.key_ptr.*) {
                known = true;
                break;
            }
        }
        if (known) continue;
        const resolved = scratch.resolveEffects(entry.value_ptr.*, 0) catch |err| return convert(err);
        if (scratch.row(resolved).tail != .closed) continue;
        const carrier = scratch.functionWithEffects(T.unit, T.unit, resolved) catch |err| return convert(err);
        try syncBudget(&scratch, &observed, resolver.remaining);
        const actual = try evidence.projectWithBudget(&scratch, carrier, &.{}, &.{}, resolver.remaining);
        try rows.append(allocator, .{ .variable = entry.key_ptr.*, .evidence = evidence.node(actual).c });
    }
    try syncBudget(&scratch, &observed, resolver.remaining);
}
fn syncBudget(store: *T.Store, observed: *usize, remaining: *usize) E.Error!void {
    const spent = store.projection_steps - observed.*;
    if (spent > remaining.*) return error.EvidenceLimit;
    remaining.* -= spent;
    observed.* = store.projection_steps;
    store.projection_limit = store.projection_steps + remaining.*;
}
fn unifyRows(store: *T.Store, left: T.Effects.Id, right: T.Effects.Id) E.Error!void {
    store.chargeProjection() catch |err| return convert(err);
    for (store.rowLabels(left)) |_| store.chargeProjection() catch |err| return convert(err);
    for (store.rowLabels(right)) |_| store.chargeProjection() catch |err| return convert(err);
    store.unifyEffects(left, right) catch |err| return convert(err);
}
fn convert(err: T.Error) E.Error {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    if (err == error.TypeLimit) return error.EvidenceLimit;
    return error.TypeMismatch;
}

fn certifiedRows(allocator: std.mem.Allocator) !void {
    var source = try T.Store.init(allocator);
    defer source.deinit();
    const residual = try source.freshEffects();
    const extended = try source.freshEffects();
    const token = try source.nominal(.{ .unit = 1, .decl = 2 }, &.{T.u32_type});
    const clause: @import("../check/core.zig").Obligation = .{ .kind = .effect_handler, .ty = token, .span = .{ .start = 0, .end = 0 }, .signature = try source.functionWithEffects(T.unit, T.unit, extended), .other = try source.functionWithEffects(T.unit, T.unit, residual) };
    var evidence = try E.Store.init(allocator);
    defer evidence.deinit();
    var rows: std.ArrayList(E.RowMapping) = .empty;
    defer rows.deinit(allocator);
    var mappings: std.ArrayList(E.Mapping) = .empty;
    defer mappings.deinit(allocator);
    var remaining: usize = 1_000_000;
    const NoProjection = struct {
        fn resolve(_: *anyopaque, _: T.NominalIdentity, _: u32, _: []const E.Id) E.Error!E.Id {
            return error.UnresolvedType;
        }
    };
    var context: u8 = 0;
    const resolver: E.ProjectionResolver = .{ .context = &context, .remaining = &remaining, .resolve = NoProjection.resolve };
    const clauses = [_]@import("../check/core.zig").Obligation{clause};
    try reconstruct(&evidence, @as(*const T.Store, &source), &clauses, &.{}, &.{}, &mappings, &rows, resolver);
    try std.testing.expectEqual(@as(usize, 0), rows.items.len);
    const certified = source.row(residual).tail.variable;
    try reconstruct(&evidence, @as(*const T.Store, &source), &clauses, &.{certified}, &.{}, &mappings, &rows, resolver);
    try std.testing.expectEqual(@as(usize, 2), rows.items.len);
    var empty = false;
    var removed = false;
    for (rows.items) |mapping| {
        if (mapping.variable == certified) {
            empty = mapping.evidence == 0;
        } else {
            const labels = evidence.effects.view().rowLabels(mapping.evidence);
            removed = labels.len == 1;
            if (removed) try std.testing.expect(std.meta.eql(evidence.effects.view().operation(labels[0]).identity, T.NominalIdentity{ .unit = 1, .decl = 2 }));
        }
    }
    try std.testing.expect(empty and removed);
    try std.testing.expectEqual(@as(usize, 0), source.versions.items.len);
    try std.testing.expectEqual(@as(usize, 0), source.effects.versions.items.len);
}
test "implementation internal row equations preserve absent certificates and release every failed allocation" {
    try certifiedRows(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, certifiedRows, .{});
}

fn witnessDirection(allocator: std.mem.Allocator) !void {
    var source = try T.Store.init(allocator);
    defer source.deinit();
    const witness = try source.fresh();
    const result = try source.fresh();
    const clause: @import("../check/core.zig").Obligation = .{ .kind = .type_head, .ty = witness, .result = result, .span = .{ .start = 0, .end = 0 } };
    const clauses = [_]@import("../check/core.zig").Obligation{clause};
    var evidence = try E.Store.init(allocator);
    defer evidence.deinit();
    var rows: std.ArrayList(E.RowMapping) = .empty;
    defer rows.deinit(allocator);
    var mappings: std.ArrayList(E.Mapping) = .empty;
    defer mappings.deinit(allocator);
    var remaining: usize = 1_000_000;
    const NoProjection = struct {
        fn resolve(_: *anyopaque, _: T.NominalIdentity, _: u32, _: []const E.Id) E.Error!E.Id {
            return error.UnresolvedType;
        }
    };
    var context: u8 = 0;
    const resolver: E.ProjectionResolver = .{ .context = &context, .remaining = &remaining, .resolve = NoProjection.resolve };
    try mappings.append(allocator, .{ .variable = result, .evidence = T.u32_type });
    try reconstruct(&evidence, @as(*const T.Store, &source), &clauses, &.{}, &.{ witness, result }, &mappings, &rows, resolver);
    try std.testing.expectEqual(@as(usize, 1), mappings.items.len);
    try std.testing.expectEqual(result, mappings.items[0].variable);
    mappings.clearRetainingCapacity();
    const arrow = try evidence.intern(.function, T.unit, T.f32_type, &.{});
    try mappings.append(allocator, .{ .variable = witness, .evidence = arrow });
    try reconstruct(&evidence, @as(*const T.Store, &source), &clauses, &.{}, &.{ witness, result }, &mappings, &rows, resolver);
    try std.testing.expectEqual(@as(usize, 2), mappings.items.len);
    try std.testing.expectEqual(result, mappings.items[1].variable);
    try std.testing.expectEqual(T.f32_type, mappings.items[1].evidence);
    try std.testing.expectEqual(@as(usize, 0), source.versions.items.len);
}
test "implementation witness result equations never infer an unknown input from a known output" {
    try witnessDirection(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, witnessDirection, .{});
}
