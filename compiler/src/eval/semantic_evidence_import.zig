//! Closed evidence transfer between independent owners of the same immutable
//! source catalogs. Numeric semantic/effect IDs are always explicitly remapped.
const std = @import("std");
const evidence = @import("type_evidence.zig");
const A = std.mem.Allocator;
pub const Importer = struct {
    allocator: A,
    source: evidence.View,
    destination: *evidence.Store,
    max_depth: usize,
    allow_scoped: bool = true,
    remaining: ?*usize = null,
    nodes: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    rows: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    labels: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    fn charge(self: *Importer) evidence.Error!void {
        if (self.remaining) |remaining| {
            if (remaining.* == 0) return error.EvidenceLimit;
            remaining.* -= 1;
        }
    }
    pub fn deinit(self: *Importer) void {
        self.nodes.deinit(self.allocator);
        self.rows.deinit(self.allocator);
        self.labels.deinit(self.allocator);
    }
    pub fn ty(self: *Importer, id: u32, depth: usize) evidence.Error!u32 {
        if (id == 0) return 0;
        if (depth >= self.max_depth or id >= self.source.nodes.len) return error.EvidenceLimit;
        if (id <= 5) return id;
        if (self.nodes.get(id)) |known| return known;
        try self.charge();
        const node = self.source.node(id);
        if (!self.allow_scoped and (node.tag == .scoped or (node.tag == .usage and node.c != 0))) return error.TypeMismatch;
        const children = self.source.children(id);
        var scratch_bytes: [128]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_bytes, self.allocator);
        const temporary = scratch.allocator();
        const copied = try temporary.dupe(u32, children);
        defer temporary.free(copied);
        for (copied, 0..) |*child, index| {
            if (node.tag != .record or index % 2 != 0) child.* = try self.ty(child.*, depth + 1);
        }
        const a = switch (node.tag) {
            .usage, .scoped, .forall, .existential, .function, .array, .list, .cursor, .demand, .resolver, .provider, .state_provider => try self.ty(node.a, depth + 1),
            .bound, .nominal, .type_constructor => node.a,
            else => 0,
        };
        const b = switch (node.tag) {
            .function, .state_provider => try self.ty(node.b, depth + 1),
            .bound, .usage, .scoped, .forall, .existential, .nominal, .type_constructor => node.b,
            else => 0,
        };
        const c = switch (node.tag) {
            .function, .demand, .provider => try self.row(node.c, depth + 1),
            .state_provider => try self.ty(node.c, depth + 1),
            .usage => if (node.c == 0) 0 else try self.ty(node.c, depth + 1),
            .bound, .scoped => node.c,
            else => 0,
        };
        var result: u32 = undefined;
        if (node.tag == .projection) {
            const descriptor = self.source.projection(id);
            result = try self.destination.internProjection(.{ .unit = node.a, .decl = node.b }, descriptor.member, copied, descriptor.scope, descriptor.goal);
        } else if (node.tag == .forall or node.tag == .existential) {
            var goals: std.ArrayList(evidence.Goal) = .empty;
            defer goals.deinit(self.allocator);
            for (self.source.quantifierGoals(id)) |goal| {
                try self.charge();
                var value = goal;
                inline for (.{ "ty", "other", "result", "signature" }) |field| @field(value, field) = try self.ty(@field(goal, field), depth + 1);
                try goals.append(self.allocator, value);
            }
            result = try self.destination.internQuantifiedWithGoals(node.tag, a, copied, goals.items);
        } else if (node.tag == .state_provider) result = try self.destination.internStateProvider(a, b, c) else result = try self.destination.internWithEffects(node.tag, a, b, c, copied);
        try self.nodes.put(self.allocator, id, result);
        return result;
    }
    pub fn row(self: *Importer, id: u32, depth: usize) evidence.Error!u32 {
        if (id == 0) return 0;
        if (depth >= self.max_depth or id >= self.source.effects.rows.len) return error.EvidenceLimit;
        if (self.rows.get(id)) |known| return known;
        try self.charge();
        const original = self.source.effects.rowLabels(id);
        var scratch_bytes: [128]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_bytes, self.allocator);
        const temporary = scratch.allocator();
        const copied = try temporary.alloc(u32, original.len);
        defer temporary.free(copied);
        for (original, copied) |old, *new| new.* = try self.label(old, depth + 1);
        const old_formal = self.source.effects.rows[id].formal;
        const formal = if (old_formal == 0) 0 else try self.ty(old_formal, depth + 1);
        const result = try self.destination.effects.internRowWithFormal(copied, formal);
        try self.rows.put(self.allocator, id, result);
        return result;
    }
    fn label(self: *Importer, id: u32, depth: usize) evidence.Error!u32 {
        if (depth >= self.max_depth or id == 0 or id >= self.source.effects.operations.len) return error.EvidenceLimit;
        if (self.labels.get(id)) |known| return known;
        try self.charge();
        const operation = self.source.effects.operation(id);
        if (!self.allow_scoped and (operation.instance.unit != 0 or operation.instance.decl != 0)) return error.TypeMismatch;
        const original = self.source.effects.operationArguments(id);
        var scratch_bytes: [128]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_bytes, self.allocator);
        const temporary = scratch.allocator();
        const copied = try temporary.alloc(u32, original.len);
        defer temporary.free(copied);
        for (original, copied) |old, *new| new.* = try self.ty(old, depth + 1);
        const result = try self.destination.effects.internOperationInstance(operation.identity, copied, operation.instance);
        try self.labels.put(self.allocator, id, result);
        return result;
    }
};

fn transferScenario(a: A) !void {
    var source = try evidence.Store.init(a);
    defer source.deinit();
    const nominal = try source.intern(.nominal, 17, 23, &.{3});
    const write = try source.intern(.nominal, 17, 24, &.{4});
    const label_ = try source.effects.internOperation(.{ .unit = 17, .decl = 31 }, &.{nominal});
    const row_ = try source.effects.internRow(&.{ label_, label_ });
    const function = try source.internWithEffects(.function, nominal, write, row_, &.{});
    const provider = try source.internWithEffects(.provider, nominal, 0, row_, &.{});
    const state = try source.internStateProvider(nominal, write, 3);
    const record = try source.intern(.record, 0, 0, &.{ 41, function, 42, function });
    const root = try source.intern(.product, 0, 0, &.{ record, provider, state });
    var destination = try evidence.Store.init(a);
    defer destination.deinit();
    _ = try destination.intern(.array, 4, 0, &.{});
    var before = try destination.copyOwned(a);
    defer before.deinit(a);
    var staged = try destination.clone(a);
    defer staged.deinit();
    var copy: Importer = .{ .allocator = a, .source = source.view(), .destination = &staged, .max_depth = 256 };
    defer copy.deinit();
    const copied = try copy.ty(root, 0);
    try std.testing.expectEqualDeep(before.nodes, destination.nodes.items);
    try std.testing.expectEqualDeep(before.extra, destination.extra.items);
    std.mem.swap(evidence.Store, &staged, &destination);
    const children = destination.children(copied);
    const fields = destination.children(children[0]);
    try std.testing.expectEqual(@as(u32, 41), fields[0]);
    try std.testing.expectEqual(fields[1], fields[3]);
    const arrow = destination.node(fields[1]);
    const nominal_copy = destination.node(arrow.a);
    try std.testing.expectEqual(@as(u32, 17), nominal_copy.a);
    try std.testing.expectEqual(@as(u32, 23), nominal_copy.b);
    const labels = destination.effects.view().rowLabels(arrow.c);
    try std.testing.expectEqual(@as(usize, 2), labels.len);
    try std.testing.expectEqual(labels[0], labels[1]);
    try std.testing.expectEqual(arrow.a, destination.effects.view().operationArguments(labels[0])[0]);
    try std.testing.expectEqual(arrow.c, destination.node(children[1]).c);
    const state_copy = destination.node(children[2]);
    try std.testing.expectEqual(arrow.a, state_copy.a);
    try std.testing.expectEqual(arrow.b, state_copy.b);
    try std.testing.expectEqual(@as(u32, 3), state_copy.c);
}
test "private semantic evidence remaps nominal records aliases and repeated effect labels with atomic owner staging" {
    try transferScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, transferScenario, .{});
}

fn scopedSemanticImportLaw(allocator: A) !void {
    var source = try evidence.Store.init(allocator);
    defer source.deinit();
    var destination = try evidence.Store.init(allocator);
    defer destination.deinit();
    const operation: @import("../check/types.zig").NominalIdentity = .{ .unit = 2, .decl = 30 };
    const left: @import("../check/types.zig").NominalIdentity = .{ .unit = 2, .decl = 31 };
    const right: @import("../check/types.zig").NominalIdentity = .{ .unit = 2, .decl = 32 };
    const a_ = try source.effects.internOperationInstance(operation, &.{3}, left);
    const b_ = try source.effects.internOperationInstance(operation, &.{3}, right);
    const row_ = try source.effects.internRow(&.{ a_, a_, b_ });
    var copy: Importer = .{ .allocator = allocator, .source = source.view(), .destination = &destination, .max_depth = 128 };
    defer copy.deinit();
    const copied = try copy.row(row_, 0);
    const labels = destination.effects.view().rowLabels(copied);
    try std.testing.expectEqual(@as(usize, 3), labels.len);
    try std.testing.expectEqual(labels[0], labels[1]);
    try std.testing.expect(labels[0] != labels[2]);
    try std.testing.expectEqual(left, destination.effects.view().operation(labels[0]).instance);
    try std.testing.expectEqual(right, destination.effects.view().operation(labels[2]).instance);
    var solver = try @import("../check/types.zig").Store.init(allocator);
    defer solver.deinit();
    var closed: @import("closed_evidence_import.zig").Importer = .{ .allocator = allocator, .source = destination.view(), .destination = &solver };
    defer closed.deinit();
    const solver_row = try closed.row(copied, 0);
    const solver_labels = solver.rowLabels(solver_row);
    try std.testing.expectEqual(left, solver.operation(solver_labels[0]).instance);
    try std.testing.expectEqual(right, solver.operation(solver_labels[2]).instance);
}
test "scoped effect semantic imports preserve owner and repeated occurrences" {
    try scopedSemanticImportLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, scopedSemanticImportLaw, .{});
}

fn packageRecipeTransferLaw(allocator: A) !void {
    var source = try evidence.Store.init(allocator);
    defer source.deinit();
    var destination = try evidence.Store.init(allocator);
    defer destination.deinit();
    // Occupy different numeric IDs before the lexical recipe is transferred.
    _ = try destination.intern(.product, 0, 0, &.{ 3, 4 });
    const bound = try source.intern(.bound, 0, 0, &.{});
    const callback = try source.intern(.function, bound, 3, &.{});
    const body = try source.intern(.product, 0, 0, &.{ bound, callback });
    const package = try source.intern(.existential, body, 1, &.{});
    try std.testing.expect(try source.containsAbstract(body));
    try std.testing.expect(!try source.containsAbstract(package));
    const foreign = try source.intern(.bound, 1, 0, &.{});
    try std.testing.expectError(error.TypeMismatch, source.intern(.existential, foreign, 1, &.{}));
    const nested = try source.intern(.existential, package, 1, &.{});
    try std.testing.expect(@import("../reuse/portable_query.zig").closedEvidence(source.view(), nested));
    var copy: Importer = .{ .allocator = allocator, .source = source.view(), .destination = &destination, .max_depth = 128 };
    defer copy.deinit();
    const transported = try copy.ty(package, 0);
    try std.testing.expect(transported != package);
    var solver = try @import("../check/types.zig").Store.init(allocator);
    defer solver.deinit();
    var closed: @import("closed_evidence_import.zig").Importer = .{ .allocator = allocator, .source = destination.view(), .destination = &solver };
    defer closed.deinit();
    const imported = try closed.ty(transported, 0);
    const owner = solver.node(imported);
    try std.testing.expectEqual(@import("../check/types.zig").Tag.existential, owner.tag);
    const binder = solver.list(.{ .start = owner.b, .len = owner.c })[0];
    const fields = solver.list(.{ .start = solver.node(owner.a).a, .len = 2 });
    try std.testing.expectEqual(binder, fields[0]);
    try std.testing.expectEqual(binder, solver.node(fields[1]).a);
    // Reprojection proves alpha identity without borrowing the old stores.
    const normalized = try destination.project(&solver, imported, &.{});
    try std.testing.expectEqual(transported, normalized);
    try std.testing.expectError(error.TypeMismatch, closed.ty(destination.children(destination.node(transported).a)[0], 0));
}
test "private existential recipes preserve owned lexical binders through transfer and every allocation failure" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, packageRecipeTransferLaw, .{});
}

fn contextFreeTransferLaw(allocator: A) !void {
    var source = try evidence.Store.init(allocator);
    defer source.deinit();
    const family = try source.intern(.nominal, 1, 7, &.{});
    const scoped = try source.internWithEffects(.scoped, family, 7, 9, &.{});
    const hidden = try source.intern(.product, 0, 0, &.{ 3, scoped });
    const operation = try source.effects.internOperationInstance(.{ .unit = 1, .decl = 17 }, &.{3}, .{ .unit = 7, .decl = 9 });
    const row_ = try source.effects.internRow(&.{operation});
    const callback = try source.internWithEffects(.function, 3, 3, row_, &.{});
    const plain = try source.intern(.product, 0, 0, &.{ 3, 4 });
    var destination = try evidence.Store.init(allocator);
    defer destination.deinit();
    var copy: Importer = .{ .allocator = allocator, .source = source.view(), .destination = &destination, .max_depth = 128, .allow_scoped = false };
    defer copy.deinit();
    for ([_]u32{ hidden, callback }) |id| {
        _ = copy.ty(id, 0) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            try std.testing.expectEqual(error.TypeMismatch, err);
            continue;
        };
        return error.TestUnexpectedResult;
    }
    // A failed live-scope transport cannot poison later closed data transfer.
    const transported = try copy.ty(plain, 0);
    try std.testing.expectEqualSlices(u32, &.{ 3, 4 }, destination.children(transported));
}
test "constant semantic graph transport rejects hidden scope identities and instanced rows through OOM" {
    try contextFreeTransferLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, contextFreeTransferLaw, .{});
}
