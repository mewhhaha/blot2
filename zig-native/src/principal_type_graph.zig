//! Copy an open type graph between owners, preserving sharing inside one
//! import while freshening every type and row binder. Published templates have
//! no substitution history and are immutable throughout import.
const std = @import("std");
const T = @import("types.zig");

/// True only when every data endpoint is an unconstrained binder and no
/// operation or rigid row is already selected. A callee relationship with any
/// concrete or partially structured endpoint still needs ordinary inference.
pub fn allUnknown(source: *const T.Store, root: T.Id, max_depth: usize) bool {
    var cursor = root;
    for (0..max_depth) |_| {
        const node = source.node(cursor);
        if (node.tag != .function) return node.tag == .variable;
        if (source.node(node.a).tag != .variable) return false;
        const row = source.row(node.c);
        if (row.labels.len != 0 or row.tail == .parameter) return false;
        cursor = node.b;
    }
    return false;
}

/// Match an unselected caller against a source-owned data/callback skeleton.
/// Constructors belong to the source; every quantified leaf must still be an
/// unknown caller binder. Repeated source binders retain their alias class.
/// This describes a residual relationship and proves no selected judgment.
pub fn matchesOpen(allocator: std.mem.Allocator, source: *const T.Store, principal: T.Id, caller: *const T.Store, actual: T.Id, max_depth: usize, max_nodes: usize) std.mem.Allocator.Error!bool {
    return matches(allocator, source, principal, caller, actual, max_depth, max_nodes, false);
}

/// Equality within one immutable owner retains exact binder identities.
/// Separately allocated structural nodes may be equal; separate binders cannot.
pub fn sameOpen(allocator: std.mem.Allocator, source: *const T.Store, left: T.Id, right: T.Id, max_depth: usize, max_nodes: usize) std.mem.Allocator.Error!bool {
    return matches(allocator, source, left, source, right, max_depth, max_nodes, true);
}

fn matches(allocator: std.mem.Allocator, source: *const T.Store, principal: T.Id, caller: *const T.Store, actual: T.Id, max_depth: usize, max_nodes: usize, exact_binders: bool) std.mem.Allocator.Error!bool {
    const Pair = struct { principal: T.Id, actual: T.Id, ambient: bool };
    const Item = struct { pair: Pair, depth: usize };
    const Row = struct { variable: ?u32, cursor: T.Cursor };
    var pending: std.ArrayList(Item) = .empty;
    defer pending.deinit(allocator);
    var seen: std.AutoHashMapUnmanaged(Pair, void) = .empty;
    defer seen.deinit(allocator);
    var variables: std.AutoHashMapUnmanaged(u32, T.Id) = .empty;
    defer variables.deinit(allocator);
    var rows: std.AutoHashMapUnmanaged(u32, Row) = .empty;
    defer rows.deinit(allocator);
    try pending.append(allocator, .{ .pair = .{ .principal = principal, .actual = actual, .ambient = true }, .depth = 0 });
    while (pending.pop()) |item| {
        if (item.depth >= max_depth) return false;
        const original = source.head(item.pair.principal, 0);
        const live = caller.head(item.pair.actual, 0);
        const key: Pair = .{ .principal = original, .actual = live, .ambient = item.pair.ambient };
        if (seen.contains(key)) continue;
        if (seen.count() >= max_nodes) return false;
        try seen.put(allocator, key, {});
        const from = source.node(original);
        const to = caller.node(live);
        if (from.tag == .variable) {
            if (to.tag != .variable) return false;
            if (exact_binders and original != live) return false;
            const slot = try variables.getOrPut(allocator, from.a);
            if (slot.found_existing) {
                if (slot.value_ptr.* != live) return false;
            } else slot.value_ptr.* = live;
            continue;
        }
        if (from.tag != to.tag) return false;
        const depth = item.depth + 1;
        switch (from.tag) {
            .function => {
                const before = source.row(from.c);
                const after = caller.row(to.c);
                if (before.labels.len > max_nodes) return false;
                if (exact_binders and (!std.meta.eql(before.tail, after.tail) or before.cursor != after.cursor)) return false;
                if (before.labels.len != after.labels.len or before.tail == .parameter or after.tail == .parameter) return false;
                for (source.rowLabels(from.c), caller.rowLabels(to.c)) |left, right| {
                    if (!std.meta.eql(source.operation(left).identity, caller.operation(right).identity)) return false;
                    const arguments = source.operationArguments(left);
                    const actuals = caller.operationArguments(right);
                    if (arguments.len != actuals.len or arguments.len > max_nodes -| pending.items.len) return false;
                    for (arguments, actuals) |a_, b_| try pending.append(allocator, .{ .pair = .{ .principal = a_, .actual = b_, .ambient = false }, .depth = depth });
                }
                // A pure source may have an unselected covariant ambient view.
                // Supplied callbacks retain exact closed rows, including purity.
                // This retains a residual edge, never a closed row judgment.
                if (before.tail == .closed and (before.labels.len != 0 or !item.pair.ambient) and after.tail != .closed) return false;
                if (before.tail == .variable) {
                    const value: Row = .{ .variable = if (after.tail == .variable) after.tail.variable else null, .cursor = after.cursor };
                    const slot = try rows.getOrPut(allocator, before.tail.variable);
                    if (slot.found_existing) {
                        if (!std.meta.eql(slot.value_ptr.*, value)) return false;
                    } else slot.value_ptr.* = value;
                }
                try pending.append(allocator, .{ .pair = .{ .principal = from.a, .actual = to.a, .ambient = false }, .depth = depth });
                try pending.append(allocator, .{ .pair = .{ .principal = from.b, .actual = to.b, .ambient = item.pair.ambient }, .depth = depth });
            },
            .array, .list, .cursor => try pending.append(allocator, .{ .pair = .{ .principal = from.a, .actual = to.a, .ambient = false }, .depth = depth }),
            .product, .nominal => {
                if (from.tag == .nominal and (from.a != to.a or from.b != to.b)) return false;
                const left = if (from.tag == .nominal) source.nominalArguments(from) else source.list(.{ .start = from.a, .len = from.b });
                const right = if (to.tag == .nominal) caller.nominalArguments(to) else caller.list(.{ .start = to.a, .len = to.b });
                if (left.len != right.len) return false;
                if (left.len > max_nodes -| pending.items.len) return false;
                for (left, right) |a_, b_| try pending.append(allocator, .{ .pair = .{ .principal = a_, .actual = b_, .ambient = false }, .depth = depth });
            },
            .record => {
                if (from.b != to.b or from.b > max_nodes -| pending.items.len) return false;
                for (0..from.b) |i| {
                    const left = source.recordField(from, i);
                    const right = caller.recordField(to, i);
                    if (left.name != right.name) return false;
                    try pending.append(allocator, .{ .pair = .{ .principal = left.ty, .actual = right.ty, .ambient = false }, .depth = depth });
                }
            },
            .unit, .boolean, .u32, .f32, .never => {},
            else => return false,
        }
    }
    return true;
}

fn callbackSkeletonScenario(allocator: std.mem.Allocator) !void {
    var source = try T.Store.init(allocator);
    defer source.deinit();
    const variable = try source.fresh();
    const pure_callback = try source.function(variable, variable);
    const pure = try source.function(pure_callback, pure_callback);
    var caller = try T.Store.init(allocator);
    defer caller.deinit();
    var copy: Copy = .{ .allocator = allocator, .source = &source, .destination = &caller, .max_depth = 64, .max_nodes = 1024 };
    defer copy.deinit();
    const actual = try copy.ty(pure, 0);
    try std.testing.expect(try matchesOpen(allocator, &source, pure, &caller, actual, 64, 1024));
    const root = caller.node(actual);
    const input = caller.node(root.a);
    const open_callback = try caller.functionWithEffects(input.a, input.b, try caller.freshEffects());
    const wrong_input = try caller.function(open_callback, root.b);
    try std.testing.expect(!try matchesOpen(allocator, &source, pure, &caller, wrong_input, 64, 1024));
    const row = try source.freshEffects();
    const callback = try source.functionWithEffects(variable, variable, row);
    const returned = try source.functionWithEffects(variable, callback, row);
    const relationship = try source.function(callback, returned);
    const instantiated = try copy.ty(relationship, 0);
    try std.testing.expect(try matchesOpen(allocator, &source, relationship, &caller, instantiated, 64, 1024));
    const outer = caller.node(instantiated);
    const result = caller.node(outer.b);
    const separated = try caller.functionWithEffects(result.a, result.b, try caller.freshEffects());
    const wrong_alias = try caller.function(outer.a, separated);
    try std.testing.expect(!try matchesOpen(allocator, &source, relationship, &caller, wrong_alias, 64, 1024));
    try std.testing.expectEqual(@as(usize, 0), source.versions.items.len);
    try std.testing.expectEqual(@as(usize, 0), source.effects.versions.items.len);
}

test "callback skeleton imports retain pure input rows and curried returned row aliases under allocation failure" {
    try callbackSkeletonScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, callbackSkeletonScenario, .{});
}

pub const Copy = Copier(*const T.Store, true);
pub const FrozenCopy = Copier(*const @import("core.zig").Types, true);
/// A source-only solver may have inferred equations before publication. Every
/// supplied root must be resolved first; the destination retains no history.
pub const NormalizedCopy = Copier(*const T.Store, false);

fn normalizedEqualityScenario(allocator: std.mem.Allocator) !void {
    var source = try T.Store.init(allocator);
    defer source.deinit();
    const shared = try source.fresh();
    const separate = try source.fresh();
    const row = try source.freshEffects();
    const distinct_row = try source.freshEffects();
    const identity = try source.functionWithEffects(shared, shared, row);
    const equalities = [_]bool{
        try sameOpen(allocator, &source, identity, try source.functionWithEffects(shared, shared, row), 64, 1024),
        try sameOpen(allocator, &source, identity, try source.functionWithEffects(separate, separate, row), 64, 1024),
        try sameOpen(allocator, &source, identity, try source.functionWithEffects(shared, separate, row), 64, 1024),
        try sameOpen(allocator, &source, identity, try source.functionWithEffects(shared, shared, distinct_row), 64, 1024),
    };
    try std.testing.expectEqualSlices(bool, &.{ true, false, false, false }, &equalities);
    // Operation instances admit complete arguments only. The equation being
    // normalized lives in the surrounding function graph and row tail.
    const label = try source.internOperation(.{ .unit = 4, .decl = 8 }, &.{T.u32_type});
    const concrete = source.effects.row(&.{label}, .closed) catch |err| return T.effectError(err);
    try source.unify(shared, T.u32_type);
    try source.unifyEffects(row, concrete);
    const nested = try source.functionWithEffects(identity, identity, row);
    const resolved = try source.resolve(nested, 0);
    var frozen = try T.Store.init(allocator);
    defer frozen.deinit();
    var copy: NormalizedCopy = .{ .allocator = allocator, .source = &source, .destination = &frozen, .max_depth = 64, .max_nodes = 1024 };
    defer copy.deinit();
    const copied = try copy.ty(resolved, 0);
    const root = frozen.node(copied);
    const callback = frozen.node(root.a);
    // Resolution may rebuild equivalent structural nodes separately. Exact
    // binder equality and the copied graph must still preserve their relation.
    try std.testing.expect(try sameOpen(allocator, &frozen, root.a, root.b, 64, 1024));
    try std.testing.expectEqual(copied, try copy.ty(resolved, 0));
    try std.testing.expectEqual(T.u32_type, callback.a);
    try std.testing.expectEqual(T.u32_type, callback.b);
    for ([_]T.Effects.Id{ root.c, callback.c }) |effect| {
        const labels = frozen.rowLabels(effect);
        try std.testing.expect(frozen.row(effect).tail == .closed);
        try std.testing.expectEqual(@as(usize, 1), labels.len);
        try std.testing.expectEqualDeep(T.NominalIdentity{ .unit = 4, .decl = 8 }, frozen.operation(labels[0]).identity);
        try std.testing.expectEqualSlices(T.Id, &.{T.u32_type}, frozen.operationArguments(labels[0]));
    }
    try std.testing.expectEqual(@as(usize, 0), frozen.versions.items.len);
    try std.testing.expectEqual(@as(usize, 0), frozen.effects.versions.items.len);
}

test "principal exact binder equality and normalized publication retain nested type and row equations under allocation failure" {
    try normalizedEqualityScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, normalizedEqualityScenario, .{});
}

fn seededRowScenario(allocator: std.mem.Allocator) !void {
    var source = try T.Store.init(allocator);
    defer source.deinit();
    const variable = try source.freshEffects();
    const label = try source.internOperation(.{ .unit = 4, .decl = 8 }, &.{T.u32_type});
    const prefix = source.effects.row(&.{label}, source.row(variable).tail) catch |err| return T.effectError(err);
    for ([_]bool{ false, true }) |closed| {
        var destination = try T.Store.init(allocator);
        defer destination.deinit();
        const actual_label = try destination.internOperation(.{ .unit = 4, .decl = 8 }, &.{T.u32_type});
        const actual_tail = if (closed) 0 else try destination.freshEffects();
        const actual = destination.effects.row(&.{actual_label}, destination.row(actual_tail).tail) catch |err| return T.effectError(err);
        var copy: Copy = .{ .allocator = allocator, .source = &source, .destination = &destination, .max_depth = 64, .max_nodes = 1024 };
        defer copy.deinit();
        try copy.row_variables.put(allocator, source.row(variable).tail.variable, actual);
        const plain = try copy.row(variable, 0);
        const repeated = try copy.row(prefix, 0);
        try std.testing.expectEqualDeep(destination.row(actual), destination.row(plain));
        try std.testing.expectEqualSlices(T.Effects.Label, &.{ actual_label, actual_label }, destination.rowLabels(repeated));
        try std.testing.expectEqualDeep(destination.row(actual).tail, destination.row(repeated).tail);
        if (!closed) {
            try destination.unifyEffects(actual_tail, 0);
            const resolved = try destination.resolveEffects(repeated, 0);
            try std.testing.expect(destination.row(resolved).tail == .closed);
            try std.testing.expectEqualSlices(T.Effects.Label, &.{ actual_label, actual_label }, destination.rowLabels(resolved));
        }
    }
    try std.testing.expectEqual(@as(usize, 0), source.effects.versions.items.len);
}

test "seeded principal row copies preserve prefixes multiplicity and future tail writes under allocation failure" {
    try seededRowScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, seededRowScenario, .{});
}

fn openSkeletonScenario(allocator: std.mem.Allocator) !void {
    var source = try T.Store.init(allocator);
    defer source.deinit();
    const variable = try source.fresh();
    const row = try source.freshEffects();
    const array = try source.sequence(.array, variable);
    const record = try source.record(&.{.{ .name = 9, .ty = variable }});
    const nominal = try source.nominal(.{ .unit = 3, .decl = 7 }, &.{variable});
    const product = try source.product(&.{ array, record, nominal });
    const inner = try source.functionWithEffects(variable, product, row);
    const root = try source.functionWithEffects(variable, inner, row);
    var caller = try T.Store.init(allocator);
    defer caller.deinit();
    var copy: Copy = .{ .allocator = allocator, .source = &source, .destination = &caller, .max_depth = 64, .max_nodes = 1024 };
    defer copy.deinit();
    const actual = try copy.ty(root, 0);
    try std.testing.expect(try matchesOpen(allocator, &source, root, &caller, actual, 64, 1024));
    try std.testing.expect(!try matchesOpen(allocator, &source, root, &caller, actual, 2, 1024));
    try std.testing.expect(!try matchesOpen(allocator, &source, root, &caller, actual, 64, 2));
    const pure = try source.function(T.u32_type, T.u32_type);
    const unknown_effects = try caller.functionWithEffects(T.u32_type, T.u32_type, try caller.freshEffects());
    try std.testing.expect(try matchesOpen(allocator, &source, pure, &caller, unknown_effects, 64, 1024));
    const declared = try source.internOperation(.{ .unit = 14, .decl = 6 }, &.{T.u32_type});
    const declared_row = source.effects.row(&.{declared}, source.row(row).tail) catch |err| return T.effectError(err);
    const operation_root = try source.functionWithEffects(variable, product, declared_row);
    const operation_actual = try copy.ty(operation_root, 0);
    try std.testing.expect(try matchesOpen(allocator, &source, operation_root, &caller, operation_actual, 64, 1024));
    const operation_arrow = caller.node(operation_actual);
    const closed_operation_row = source.effects.row(&.{declared}, .closed) catch |err| return T.effectError(err);
    const closed_operation = try source.functionWithEffects(variable, product, closed_operation_row);
    try std.testing.expect(!try matchesOpen(allocator, &source, closed_operation, &caller, operation_actual, 64, 1024));
    const closed_operation_actual = try copy.ty(closed_operation, 0);
    try std.testing.expect(try matchesOpen(allocator, &source, closed_operation, &caller, closed_operation_actual, 64, 1024));
    const split_label = try caller.internOperation(.{ .unit = 14, .decl = 6 }, &.{T.f32_type});
    const split_row = caller.effects.row(&.{split_label}, caller.row(operation_arrow.c).tail) catch |err| return T.effectError(err);
    const split_operation = try caller.functionWithEffects(operation_arrow.a, operation_arrow.b, split_row);
    try std.testing.expect(!try matchesOpen(allocator, &source, operation_root, &caller, split_operation, 64, 1024));
    const outer = caller.node(actual);
    const inside = caller.node(outer.b);
    const separated = try caller.functionWithEffects(try caller.fresh(), outer.b, outer.c);
    try std.testing.expect(!try matchesOpen(allocator, &source, root, &caller, separated, 64, 1024));
    const structured_input = try caller.functionWithEffects(try caller.sequence(.array, outer.a), outer.b, outer.c);
    try std.testing.expect(!try matchesOpen(allocator, &source, root, &caller, structured_input, 64, 1024));
    const separate_row = try caller.functionWithEffects(inside.a, inside.b, try caller.freshEffects());
    const changed_row = try caller.functionWithEffects(outer.a, separate_row, outer.c);
    try std.testing.expect(!try matchesOpen(allocator, &source, root, &caller, changed_row, 64, 1024));
    const operation = try caller.internOperation(.{ .unit = 14, .decl = 6 }, &.{T.u32_type});
    const selected_row = caller.effects.row(&.{operation}, caller.row(outer.c).tail) catch |err| return T.effectError(err);
    const effectful = try caller.functionWithEffects(outer.a, outer.b, selected_row);
    try std.testing.expect(!try matchesOpen(allocator, &source, root, &caller, effectful, 64, 1024));
    const result = caller.node(inside.b);
    const parts = caller.list(.{ .start = result.a, .len = result.b })[0..3].*;
    const other_nominal = try caller.nominal(.{ .unit = 3, .decl = 8 }, &.{outer.a});
    const other_product = try caller.product(&.{ parts[0], parts[1], other_nominal });
    const other_inner = try caller.functionWithEffects(inside.a, other_product, inside.c);
    const other_identity = try caller.functionWithEffects(outer.a, other_inner, outer.c);
    try std.testing.expect(!try matchesOpen(allocator, &source, root, &caller, other_identity, 64, 1024));
    try caller.unify(outer.a, T.u32_type);
    const concrete = try caller.resolve(actual, 0);
    try std.testing.expect(!try matchesOpen(allocator, &source, root, &caller, concrete, 64, 1024));
    try std.testing.expectEqual(@as(usize, 0), source.versions.items.len);
    try std.testing.expectEqual(@as(usize, 0), source.effects.versions.items.len);
}

test "open skeleton matching preserves source constructors aliases rows and owner selection under allocation failure" {
    try openSkeletonScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, openSkeletonScenario, .{});
}

fn Copier(comptime Source: type, comptime frozen: bool) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        source: Source,
        destination: *T.Store,
        max_depth: usize,
        max_nodes: usize,
        types: std.AutoHashMapUnmanaged(T.Id, T.Id) = .empty,
        variables: std.AutoHashMapUnmanaged(u32, T.Id) = .empty,
        rows: std.AutoHashMapUnmanaged(T.Effects.Id, T.Effects.Id) = .empty,
        row_variables: std.AutoHashMapUnmanaged(u32, T.Effects.Id) = .empty,
        labels: std.AutoHashMapUnmanaged(T.Effects.Label, T.Effects.Label) = .empty,

        pub fn deinit(self: *Self) void {
            self.types.deinit(self.allocator);
            self.variables.deinit(self.allocator);
            self.rows.deinit(self.allocator);
            self.row_variables.deinit(self.allocator);
            self.labels.deinit(self.allocator);
            self.* = undefined;
        }

        pub fn ty(self: *Self, original: T.Id, depth: usize) T.Error!T.Id {
            if (comptime Source == *const T.Store and frozen) std.debug.assert(self.source.versions.items.len == 0 and self.source.effects.versions.items.len == 0);
            if (original <= T.never) return original;
            if (depth >= self.max_depth or self.types.count() >= self.max_nodes) return error.TypeLimit;
            if (self.types.get(original)) |known| return known;
            const root = self.source.head(original, 0);
            if (root != original) {
                const result = try self.ty(root, depth + 1);
                try self.types.put(self.allocator, original, result);
                return result;
            }
            const node = self.source.node(root);
            const result = switch (node.tag) {
                .variable => blk: {
                    if (self.variables.get(node.a)) |known| break :blk known;
                    const fresh = try self.destination.fresh();
                    try self.variables.put(self.allocator, node.a, fresh);
                    break :blk fresh;
                },
                .function => try self.destination.functionWithEffects(try self.ty(node.a, depth + 1), try self.ty(node.b, depth + 1), try self.row(node.c, depth + 1)),
                .array, .list, .cursor => try self.destination.sequence(node.tag, try self.ty(node.a, depth + 1)),
                .demand => try self.destination.demandWithEffects(try self.ty(node.a, depth + 1), try self.row(node.c, depth + 1)),
                .provider => try self.destination.provider(try self.ty(node.a, depth + 1), try self.row(node.c, depth + 1)),
                .resolver => try self.destination.resolver(try self.ty(node.a, depth + 1)),
                .state_provider => try self.destination.stateProvider(try self.ty(node.a, depth + 1), try self.ty(node.b, depth + 1), try self.ty(node.c, depth + 1)),
                .type_constructor => try self.destination.typeConstructor(.{ .unit = node.a, .decl = node.b }),
                .record => blk: {
                    const fields = try self.allocator.alloc(T.Field, node.b);
                    defer self.allocator.free(fields);
                    for (fields, 0..) |*field, index| {
                        const old = self.source.recordField(node, index);
                        field.* = .{ .name = old.name, .ty = try self.ty(old.ty, depth + 1) };
                    }
                    break :blk try self.destination.record(fields);
                },
                .product, .nominal => blk: {
                    const children = if (node.tag == .nominal) self.source.nominalArguments(node) else self.source.list(.{ .start = node.a, .len = node.b });
                    const copied = try self.allocator.alloc(T.Id, children.len);
                    defer self.allocator.free(copied);
                    for (children, copied) |child, *value| value.* = try self.ty(child, depth + 1);
                    break :blk if (node.tag == .nominal) try self.destination.nominal(.{ .unit = node.a, .decl = node.b }, copied) else try self.destination.product(copied);
                },
                .absent, .unit, .boolean, .u32, .f32, .never => unreachable,
            };
            try self.types.put(self.allocator, original, result);
            return result;
        }

        pub fn rowVariable(self: *Self, variable: u32) T.Error!T.Effects.Id {
            if (self.row_variables.get(variable)) |known| return known;
            if (self.row_variables.count() >= self.max_nodes) return error.TypeLimit;
            const fresh = try self.destination.freshEffects();
            try self.row_variables.put(self.allocator, variable, fresh);
            return fresh;
        }

        pub fn row(self: *Self, original: T.Effects.Id, depth: usize) T.Error!T.Effects.Id {
            if (original == 0) return 0;
            if (depth >= self.max_depth or self.rows.count() >= self.max_nodes) return error.TypeLimit;
            if (self.rows.get(original)) |known| return known;
            const root = original;
            const source = self.source.row(root);
            const old_labels = self.source.rowLabels(root);
            const copied = try self.allocator.alloc(T.Effects.Label, old_labels.len);
            defer self.allocator.free(copied);
            for (old_labels, copied) |operation_label, *value| value.* = try self.label(operation_label, depth + 1);
            const result = switch (source.tail) {
                .closed => self.destination.effects.row(copied, .closed) catch |err| return T.effectError(err),
                .variable => |variable| blk: {
                    const replacement = try self.rowVariable(variable);
                    if (copied.len == 0) break :blk replacement;
                    const resolved = try self.destination.resolveEffects(replacement, 0);
                    const row_ = self.destination.row(resolved);
                    var labels: std.ArrayList(T.Effects.Label) = .empty;
                    defer labels.deinit(self.allocator);
                    try labels.appendSlice(self.allocator, copied);
                    try labels.appendSlice(self.allocator, self.destination.rowLabels(resolved));
                    break :blk self.destination.effects.rowAt(labels.items, row_.tail, row_.cursor) catch |err| return T.effectError(err);
                },
                // Rigid row parameters require their source-owner identity. They
                // remain on ordinary collection until that boundary is represented.
                .parameter => return error.TypeLimit,
            };
            try self.rows.put(self.allocator, original, result);
            return result;
        }

        fn label(self: *Self, original: T.Effects.Label, depth: usize) T.Error!T.Effects.Label {
            if (depth >= self.max_depth or self.labels.count() >= self.max_nodes) return error.TypeLimit;
            if (self.labels.get(original)) |known| return known;
            const operation = self.source.operation(original);
            const old = self.source.operationArguments(original);
            const arguments = try self.allocator.alloc(T.Id, old.len);
            defer self.allocator.free(arguments);
            for (old, arguments) |argument, *value| value.* = try self.ty(argument, depth + 1);
            const result = try self.destination.internOperation(operation.identity, arguments);
            try self.labels.put(self.allocator, original, result);
            return result;
        }
    };
}

test "principal type graph imports fresh binders and preserves nested aliases and effect identities" {
    const a = std.testing.allocator;
    var source = try T.Store.init(a);
    defer source.deinit();
    const shared = try source.fresh();
    const row = try source.freshEffects();
    const label = try source.internOperation(.{ .unit = 12, .decl = 9 }, &.{T.f32_type});
    const effect = source.effects.row(&.{label}, source.row(row).tail) catch |err| return T.effectError(err);
    const payload = try source.product(&.{ shared, shared });
    const root = try source.functionWithEffects(payload, shared, effect);
    var template = try T.Store.init(a);
    defer template.deinit();
    var describe: Copy = .{ .allocator = a, .source = &source, .destination = &template, .max_depth = 64, .max_nodes = 1024 };
    defer describe.deinit();
    const principal = try describe.ty(root, 0);
    var caller = try T.Store.init(a);
    defer caller.deinit();
    var first: Copy = .{ .allocator = a, .source = &template, .destination = &caller, .max_depth = 64, .max_nodes = 1024 };
    defer first.deinit();
    var second: Copy = .{ .allocator = a, .source = &template, .destination = &caller, .max_depth = 64, .max_nodes = 1024 };
    defer second.deinit();
    const integer = caller.node(try first.ty(principal, 0));
    const floating = caller.node(try second.ty(principal, 0));
    const integer_fields = caller.node(integer.a);
    const values = caller.list(.{ .start = integer_fields.a, .len = integer_fields.b });
    try std.testing.expectEqual(integer.b, values[0]);
    try std.testing.expectEqual(integer.b, values[1]);
    try std.testing.expect(integer.b != floating.b);
    try caller.unify(integer.b, T.u32_type);
    try caller.unify(floating.b, T.f32_type);
    try std.testing.expectEqual(T.u32_type, try caller.resolve(integer.b, 0));
    try std.testing.expectEqual(T.f32_type, try caller.resolve(floating.b, 0));
    try std.testing.expect(caller.row(integer.c).tail.variable != caller.row(floating.c).tail.variable);
    try std.testing.expectEqualDeep(caller.rowLabels(integer.c), caller.rowLabels(floating.c));
    try std.testing.expectEqualDeep(T.NominalIdentity{ .unit = 12, .decl = 9 }, caller.operation(caller.rowLabels(integer.c)[0]).identity);
    try std.testing.expectEqual(@as(usize, 0), template.versions.items.len);
    try std.testing.expectEqual(@as(usize, 0), template.effects.versions.items.len);
}
