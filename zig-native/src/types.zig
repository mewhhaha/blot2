//! Owned dense types and ordered substitution history. Resolution follows the
//! first replacement at or after its cursor, then advances past that write.
//! It deliberately does not collapse history into union-find representatives.
const std = @import("std");
const resolution_cache = @import("resolution_cache.zig");
const epoch_cache = @import("epoch_resolution_cache.zig");
pub const Effects = @import("effects.zig");
pub const Id = u32;
pub const Cursor = u32;
pub const absent: Id = 0;
pub const unit: Id = 1;
pub const boolean: Id = 2;
pub const u32_type: Id = 3;
pub const f32_type: Id = 4;
pub const never: Id = 5;
pub const Tag = enum(u8) { absent, unit, boolean, u32, f32, never, variable, function, product, record, nominal, array, list, demand, type_constructor, resolver, provider, state_provider };
pub const Node = struct {
    tag: Tag,
    // Owned structural certificate, kept in the existing three padding bytes.
    // Zero height declines the shortcut; generation never reuses rollback IDs.
    closed_height: u8 = 0,
    closed_generation: u16 = 0,
    a: u32 = 0,
    b: u32 = 0,
    c: u32 = 0,
};
comptime {
    std.debug.assert(@sizeOf(Node) == 16);
}
pub const NominalIdentity = struct { unit: u32, decl: u32 };
pub const Operation = struct { identity: NominalIdentity, arguments: List = .{} };
pub const foreign_operation: Effects.Label = 1;
// Builtin operations occupy a compiler-owned unit outside source module IDs.
pub const builtin_state_read: NominalIdentity = .{ .unit = std.math.maxInt(u32), .decl = 1 };
pub fn isReflectionIdentity(unit_: u32, decl: u32) bool {
    return unit_ == std.math.maxInt(u32) and (decl == 3 or decl == 4);
}
pub const effect_set_identity: NominalIdentity = .{ .unit = std.math.maxInt(u32), .decl = 3 };
pub const effect_descriptor_identity: NominalIdentity = .{ .unit = std.math.maxInt(u32), .decl = 4 };
pub const builtin_state_write: NominalIdentity = .{ .unit = std.math.maxInt(u32), .decl = 2 };
pub const Field = struct { name: u32, ty: Id };
pub const List = struct { start: u32 = 0, len: u32 = 0 };
pub const Scheme = struct { root: Id = absent, variables: List = .{}, row_variables: List = .{}, closed_rows: List = .{}, obligations: List = .{} };
pub const ClosedCovariant = struct { root: Id, closed_rows: List };
pub const Operator = enum { none, add, sub, mul, div, rem, equal, not_equal, less, less_equal, greater, greater_equal, bit_and, bit_or, bit_xor, shift_left, shift_right };
pub const ObligationKind = enum { arithmetic, ordered, equality, integer, field, writable_field, dispatch, result_dispatch, monad_factory, resolver_dispatch, resolver_shape, effect_operation, effect_handler, receiver, update, type_rep, effect_rep, type_head, collection };
pub const Obligation = struct { ty: Id, kind: ObligationKind, source: u32, name: u32 = 0, result: Id = 0, other: Id = 0, signature: Id = 0, operator: Operator = .none, identity: NominalIdentity = .{ .unit = 0, .decl = 0 }, explicit: bool = false, qualification_span: ?@import("ast.zig").Span = null, qualification_unit: u32 = 0 };
pub const Version = struct { variable: u32, replacement: Id, position: Cursor, previous: u32, next: u32 = none };
const none = std.math.maxInt(u32);
const Variable = struct { first: u32 = none, last: u32 = none };
pub const Mark = struct { nodes: usize, extra: usize, variables: usize, versions: usize, operations: usize, effects: Effects.Mark };
pub const Error = std.mem.Allocator.Error || error{ TypeMismatch, InfiniteType, EffectMismatch, InfiniteEffect, TypeLimit };
pub fn effectError(err: Effects.Error) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.EffectMismatch => error.EffectMismatch,
        error.InfiniteEffect => error.InfiniteEffect,
        error.EffectLimit => error.TypeLimit,
    };
}

pub const Store = struct {
    use_closed_graphs: bool = false,
    closed_generation: u16 = 1,
    closed_effect_physical_epoch: u64 = 0,
    // Writes and rollback advance this clock; recycled numeric IDs never make
    // an entry from a discarded history valid again. It is not rolled back.
    mutation_epoch: u64 = 0,
    use_resolution_cache: bool = true,
    resolved: epoch_cache.Cache = .{},
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(Node) = .empty,
    extra: std.ArrayList(Id) = .empty,
    variables: std.ArrayList(Variable) = .empty,
    versions: std.ArrayList(Version) = .empty,
    variable_views: std.AutoHashMapUnmanaged(u64, Id) = .empty,
    /// Both substitution kinds use effects.next_position as their one global
    /// history clock. A type write advances child row visibility too.
    effects: Effects.Store,
    operations: std.ArrayList(Operation) = .empty,

    /// Owned per-store policy; uncached instances preserve the same chronology.
    pub const Options = struct { resolution_cache: bool = true, closed_graphs: bool = false };

    pub fn init(allocator: std.mem.Allocator) Error!Store {
        return initWithOptions(allocator, .{});
    }
    pub fn initWithOptions(allocator: std.mem.Allocator, options: Options) Error!Store {
        var self: Store = .{ .allocator = allocator, .use_closed_graphs = options.closed_graphs, .use_resolution_cache = options.resolution_cache, .effects = Effects.Store.initWithOptions(allocator, .{ .resolution_cache = options.resolution_cache }) catch |err| return effectError(err) };
        errdefer self.deinit();
        try self.nodes.appendSlice(allocator, &.{ .{ .tag = .absent }, .{ .tag = .unit }, .{ .tag = .boolean }, .{ .tag = .u32 }, .{ .tag = .f32 }, .{ .tag = .never } });
        try self.operations.appendSlice(allocator, &.{ .{ .identity = .{ .unit = 0, .decl = 0 } }, .{ .identity = .{ .unit = 0, .decl = 1 } } });
        return self;
    }
    pub fn deinit(self: *Store) void {
        self.nodes.deinit(self.allocator);
        self.extra.deinit(self.allocator);
        self.variables.deinit(self.allocator);
        self.versions.deinit(self.allocator);
        self.variable_views.deinit(self.allocator);
        self.resolved.deinit(self.allocator);
        self.effects.deinit();
        self.operations.deinit(self.allocator);
        self.* = undefined;
    }
    pub fn node(self: *const Store, id: Id) Node {
        return self.nodes.items[id];
    }
    pub fn list(self: *const Store, span: List) []const Id {
        return self.extra.items[span.start..][0..span.len];
    }
    pub fn saveList(self: *Store, values: []const Id) Error!List {
        if (values.len > std.math.maxInt(u32) - self.extra.items.len) return error.TypeLimit;
        const start: u32 = @intCast(self.extra.items.len);
        try self.extra.appendSlice(self.allocator, values);
        return .{ .start = start, .len = @intCast(values.len) };
    }
    /// Publication may normalize owned argument lists in place. Its physical
    /// write invalidates prior projections even when no substitution was added.
    pub fn replaceListItem(self: *Store, span: List, index: usize, value: Id) void {
        std.debug.assert(index < span.len and value < self.nodes.items.len);
        const slot = @as(usize, span.start) + index;
        if (self.extra.items[slot] == value) return;
        self.extra.items[slot] = value;
        self.invalidateClosedGraphs();
        resolution_cache.tick(&self.mutation_epoch);
    }
    fn add(self: *Store, value: Node) Error!Id {
        if (self.nodes.items.len == std.math.maxInt(u32)) return error.TypeLimit;
        const id: Id = @intCast(self.nodes.items.len);
        var owned = value;
        if (self.use_closed_graphs) {
            self.synchronizeClosedGraphs();
            owned.closed_height = self.closedNodeHeight(value);
            owned.closed_generation = self.closed_generation;
        }
        try self.nodes.append(self.allocator, owned);
        return id;
    }
    fn invalidateClosedGraphs(self: *Store) void {
        // Saturation permanently declines; it never wraps to an old proof.
        if (self.closed_generation != std.math.maxInt(u16)) self.closed_generation += 1;
    }
    fn synchronizeClosedGraphs(self: *Store) void {
        if (self.closed_effect_physical_epoch == self.effects.physical_epoch) return;
        self.invalidateClosedGraphs();
        self.closed_effect_physical_epoch = self.effects.physical_epoch;
    }
    fn closedHeight(self: *const Store, id: Id) u8 {
        if (!self.use_closed_graphs or self.closed_generation == std.math.maxInt(u16) or
            self.effects.physical_epoch == std.math.maxInt(u64) or
            self.closed_effect_physical_epoch != self.effects.physical_epoch) return 0;
        if (id <= never) return if (id == absent) 0 else 1;
        const n = self.node(id);
        return if (n.closed_generation == self.closed_generation) n.closed_height else 0;
    }
    fn closedRow(self: *const Store, id: Effects.Id) bool {
        const r = self.effects.node(id);
        if (r.tail != .closed) return false;
        for (self.effects.list(r.labels)) |label| {
            if (label >= self.operations.items.len) return false;
            for (self.list(self.operations.items[label].arguments)) |arg| if (self.closedHeight(arg) == 0) return false;
        }
        return true;
    }
    fn closedNodeHeight(self: *const Store, n: Node) u8 {
        var height: u8 = 0;
        switch (n.tag) {
            .absent, .variable => return 0,
            .function, .demand, .provider => {
                if (!self.closedRow(n.c)) return 0;
                height = self.closedHeight(n.a);
                if (height == 0) return 0;
                if (n.tag == .function) {
                    const result = self.closedHeight(n.b);
                    if (result == 0) return 0;
                    height = @max(height, result);
                }
            },
            .array, .list, .resolver => {
                height = self.closedHeight(n.a);
                if (height == 0) return 0;
            },
            .state_provider => for ([_]Id{ n.a, n.b, n.c }) |child| {
                const child_height = self.closedHeight(child);
                if (child_height == 0) return 0;
                height = @max(height, child_height);
            },
            .product => for (self.list(.{ .start = n.a, .len = n.b })) |child| {
                const child_height = self.closedHeight(child);
                if (child_height == 0) return 0;
                height = @max(height, child_height);
            },
            .record => for (0..n.b) |index| {
                const child_height = self.closedHeight(self.recordField(n, index).ty);
                if (child_height == 0) return 0;
                height = @max(height, child_height);
            },
            .nominal => for (self.nominalArguments(n)) |child| {
                const child_height = self.closedHeight(child);
                if (child_height == 0) return 0;
                height = @max(height, child_height);
            },
            else => {},
        }
        return if (height == std.math.maxInt(u8)) 0 else height + 1;
    }
    pub fn fresh(self: *Store) Error!Id {
        const index: u32 = @intCast(self.variables.items.len);
        try self.variables.append(self.allocator, .{});
        errdefer _ = self.variables.pop();
        return self.variableView(index, 0);
    }
    fn variableView(self: *Store, index: u32, at: Cursor) Error!Id {
        // If this variable has no writes, all future writes occur at or beyond
        // the current history end. Advancing within that history cannot change
        // its meaning; keep its principal identity canonical.
        const position = if (self.variables.items[index].first == none and at <= self.cursor()) 0 else at;
        const key = (@as(u64, index) << 32) | position;
        if (self.variable_views.get(key)) |id| return id;
        const id = try self.add(.{ .tag = .variable, .a = index, .b = position });
        errdefer _ = self.nodes.pop();
        try self.variable_views.put(self.allocator, key, id);
        return id;
    }
    pub fn function(self: *Store, parameter: Id, result: Id) Error!Id {
        return self.functionWithEffects(parameter, result, 0);
    }
    pub fn functionWithEffects(self: *Store, parameter: Id, result: Id, effect_row: Effects.Id) Error!Id {
        return self.add(.{ .tag = .function, .a = parameter, .b = result, .c = effect_row });
    }
    pub fn product(self: *Store, fields: []const Id) Error!Id {
        const span = try self.saveList(fields);
        return self.add(.{ .tag = .product, .a = span.start, .b = span.len });
    }
    pub fn array(self: *Store, element: Id) Error!Id {
        return self.add(.{ .tag = .array, .a = element });
    }
    pub fn sequence(self: *Store, tag: Tag, element: Id) Error!Id {
        std.debug.assert(tag == .array or tag == .list);
        return self.add(.{ .tag = tag, .a = element });
    }
    pub fn demand(self: *Store, element: Id) Error!Id {
        return self.demandWithEffects(element, 0);
    }
    pub fn demandWithEffects(self: *Store, element: Id, effect_row: Effects.Id) Error!Id {
        return self.add(.{ .tag = .demand, .a = element, .c = effect_row });
    }
    pub fn typeConstructor(self: *Store, identity: NominalIdentity) Error!Id {
        return self.add(.{ .tag = .type_constructor, .a = identity.unit, .b = identity.decl });
    }
    pub fn resolver(self: *Store, token: Id) Error!Id {
        return self.add(.{ .tag = .resolver, .a = token });
    }
    /// The nominal child identifies an operation and its shaped arguments,
    /// without borrowing a local effect catalog label. Implementation effects
    /// remain latent until the provider is installed.
    pub fn provider(self: *Store, operation_type: Id, implementation_effects: Effects.Id) Error!Id {
        return self.add(.{ .tag = .provider, .a = operation_type, .c = implementation_effects });
    }
    pub fn stateProvider(self: *Store, read: Id, write: Id, state_type: Id) Error!Id {
        return self.add(.{ .tag = .state_provider, .a = read, .b = write, .c = state_type });
    }
    pub fn record(self: *Store, fields: []const Field) Error!Id {
        var words: std.ArrayList(Id) = .empty;
        defer words.deinit(self.allocator);
        for (fields) |field| try words.appendSlice(self.allocator, &.{ field.name, field.ty });
        const span = try self.saveList(words.items);
        return self.add(.{ .tag = .record, .a = span.start, .b = @intCast(fields.len) });
    }
    pub fn nominal(self: *Store, identity: NominalIdentity, arguments: []const Id) Error!Id {
        if (arguments.len >= std.math.maxInt(u32) or self.extra.items.len > std.math.maxInt(u32) - arguments.len - 1) return error.TypeLimit;
        const owned = try self.allocator.dupe(Id, arguments);
        defer self.allocator.free(owned);
        const start: u32 = @intCast(self.extra.items.len);
        try self.extra.ensureUnusedCapacity(self.allocator, owned.len + 1);
        self.extra.appendAssumeCapacity(@intCast(owned.len));
        self.extra.appendSliceAssumeCapacity(owned);
        return self.add(.{ .tag = .nominal, .a = identity.unit, .b = identity.decl, .c = start });
    }
    pub fn nominalArguments(self: *const Store, value: Node) []const Id {
        std.debug.assert(value.tag == .nominal);
        return self.extra.items[value.c + 1 ..][0..self.extra.items[value.c]];
    }
    pub fn recordField(self: *const Store, value: Node, index: usize) Field {
        std.debug.assert(value.tag == .record and index < value.b);
        return .{ .name = self.extra.items[value.a + index * 2], .ty = self.extra.items[value.a + index * 2 + 1] };
    }
    pub fn cursor(self: *const Store) Cursor {
        return self.effects.next_position;
    }
    pub fn mark(self: *const Store) Mark {
        return .{ .nodes = self.nodes.items.len, .extra = self.extra.items.len, .variables = self.variables.items.len, .versions = self.versions.items.len, .operations = self.operations.items.len, .effects = self.effects.mark() };
    }
    pub fn rollback(self: *Store, point: Mark) void {
        self.invalidateClosedGraphs();
        resolution_cache.tick(&self.mutation_epoch);
        while (self.versions.items.len > point.versions) {
            const write = self.versions.pop().?;
            self.variables.items[write.variable].last = write.previous;
            if (write.previous == none) self.variables.items[write.variable].first = none else self.versions.items[write.previous].next = none;
        }
        for (self.nodes.items[point.nodes..]) |value| if (value.tag == .variable) {
            _ = self.variable_views.remove((@as(u64, value.a) << 32) | value.b);
        };
        self.nodes.shrinkRetainingCapacity(point.nodes);
        self.extra.shrinkRetainingCapacity(point.extra);
        self.variables.shrinkRetainingCapacity(point.variables);
        self.operations.shrinkRetainingCapacity(point.operations);
        self.effects.rollback(point.effects);
    }
    /// Raw writes preserve arbitrary histories for the reference oracle. Normal
    /// checker writes go through unify, including an occurs check.
    pub fn appendVersion(self: *Store, variable: Id, replacement_id: Id) Error!void {
        const value = self.node(variable);
        std.debug.assert(value.tag == .variable);
        const old = self.variables.items[value.a];
        const index: u32 = @intCast(self.versions.items.len);
        if (index == none or self.cursor() == none) return error.TypeLimit;
        try self.versions.append(self.allocator, .{ .variable = value.a, .replacement = replacement_id, .position = self.cursor(), .previous = old.last });
        if (old.last == none) self.variables.items[value.a].first = index else self.versions.items[old.last].next = index;
        self.variables.items[value.a].last = index;
        self.effects.next_position += 1;
        resolution_cache.tick(&self.mutation_epoch);
    }
    fn replacement(self: *const Store, index: u32, at: Cursor) ?Version {
        var version = self.variables.items[index].first;
        while (version != none) : (version = self.versions.items[version].next) {
            const value = self.versions.items[version];
            if (value.position >= at) return value;
        }
        return null;
    }
    pub fn head(self: *const Store, root: Id, at: Cursor) Id {
        var id = root;
        var position = at;
        while (self.node(id).tag == .variable) {
            const variable = self.node(id);
            position = @max(position, variable.b);
            const write = self.replacement(variable.a, position) orelse break;
            id = write.replacement;
            position = write.position + 1;
        }
        const value = self.node(id);
        return if (value.tag == .variable) self.variable_views.get((@as(u64, value.a) << 32) | position) orelse id else id;
    }
    pub fn resolve(self: *Store, root: Id, at: Cursor) Error!Id {
        if (self.use_closed_graphs) {
            self.synchronizeClosedGraphs();
            // A certified raw graph has no cursor-dependent children or tails.
            if (self.closedHeight(root) != 0) return root;
        }
        // Historical windows retain the original chronological traversal.
        if (!self.use_resolution_cache or at != 0 or root <= never) return self.resolveDepth(root, at, 0);
        const mutation = resolution_cache.stamp(self.mutation_epoch) orelse return self.resolveDepth(root, at, 0);
        const effects = resolution_cache.stamp(self.effects.mutation_epoch) orelse return self.resolveDepth(root, at, 0);
        if (!self.resolved.activate(mutation, effects)) return self.resolveDepth(root, at, 0);
        if (self.resolved.get(root)) |result| return result;
        const result = try self.resolveDepth(root, at, 0);
        // An unchanged query must not acquire fresh retained storage.
        if (result == root and root >= self.resolved.high_water) return result;
        try self.resolved.put(self.allocator, root, result);
        return result;
    }
    fn resolveDepth(self: *Store, root: Id, at: Cursor, depth: usize) Error!Id {
        if (depth >= 1024) return error.TypeLimit;
        const height = self.closedHeight(root);
        if (height != 0) {
            if (depth + height > 1024) return error.TypeLimit;
            return root;
        }
        var id = root;
        var position = at;
        while (self.node(id).tag == .variable) {
            const variable = self.node(id);
            position = @max(position, variable.b);
            const write = self.replacement(variable.a, position) orelse break;
            id = write.replacement;
            position = write.position + 1;
        }
        if (id != root) {
            const selected_height = self.closedHeight(id);
            if (selected_height != 0) {
                if (depth + selected_height > 1024) return error.TypeLimit;
                return id;
            }
        }
        const value = self.node(id);
        switch (value.tag) {
            .variable => return self.variableView(value.a, position),
            .function => {
                const parameter = try self.resolveDepth(value.a, position, depth + 1);
                const result = try self.resolveDepth(value.b, position, depth + 1);
                const effect_row = self.effects.resolve(value.c, position) catch |err| return effectError(err);
                if (parameter == value.a and result == value.b and effect_row == value.c) return id;
                return self.functionWithEffects(parameter, result, effect_row);
            },
            .product => {
                var fields: std.ArrayList(Id) = .empty;
                defer fields.deinit(self.allocator);
                var changed = false;
                for (0..value.b) |i| {
                    const old = self.extra.items[value.a + i];
                    const child = try self.resolveDepth(old, position, depth + 1);
                    if (!changed and child != old) {
                        try fields.ensureTotalCapacity(self.allocator, value.b);
                        // Recursive resolution may move extra, so reread the
                        // unchanged prefix through its stable numeric range.
                        fields.appendSliceAssumeCapacity(self.extra.items[value.a..][0..i]);
                        changed = true;
                    }
                    if (changed) fields.appendAssumeCapacity(child);
                }
                return if (changed) self.product(fields.items) else id;
            },
            .array, .list, .resolver => {
                const child = try self.resolveDepth(value.a, position, depth + 1);
                return if (child == value.a) id else if (value.tag == .resolver) self.resolver(child) else self.sequence(value.tag, child);
            },
            .demand, .provider => {
                const child = try self.resolveDepth(value.a, position, depth + 1);
                const effect_row = self.effects.resolve(value.c, position) catch |err| return effectError(err);
                return if (child == value.a and effect_row == value.c) id else if (value.tag == .provider) self.provider(child, effect_row) else self.demandWithEffects(child, effect_row);
            },
            .state_provider => {
                const read = try self.resolveDepth(value.a, position, depth + 1);
                const write = try self.resolveDepth(value.b, position, depth + 1);
                const state_type = try self.resolveDepth(value.c, position, depth + 1);
                return if (read == value.a and write == value.b and state_type == value.c) id else self.stateProvider(read, write, state_type);
            },
            .record => {
                var fields: std.ArrayList(Field) = .empty;
                defer fields.deinit(self.allocator);
                var changed = false;
                for (0..value.b) |i| {
                    const field = self.recordField(value, i);
                    const child = try self.resolveDepth(field.ty, position, depth + 1);
                    if (!changed and child != field.ty) {
                        try fields.ensureTotalCapacity(self.allocator, value.b);
                        for (0..i) |prefix| fields.appendAssumeCapacity(self.recordField(value, prefix));
                        changed = true;
                    }
                    if (changed) fields.appendAssumeCapacity(.{ .name = field.name, .ty = child });
                }
                return if (changed) self.record(fields.items) else id;
            },
            .nominal => {
                var args: std.ArrayList(Id) = .empty;
                defer args.deinit(self.allocator);
                var changed = false;
                const count = self.extra.items[value.c];
                for (0..count) |i| {
                    const child = self.extra.items[value.c + 1 + i];
                    const next = try self.resolveDepth(child, position, depth + 1);
                    if (!changed and child != next) {
                        try args.ensureTotalCapacity(self.allocator, count);
                        args.appendSliceAssumeCapacity(self.extra.items[value.c + 1 ..][0..i]);
                        changed = true;
                    }
                    if (changed) args.appendAssumeCapacity(next);
                }
                return if (changed) self.nominal(.{ .unit = value.a, .decl = value.b }, args.items) else id;
            },
            else => return id,
        }
    }
    fn occurs(self: *Store, variable: u32, root: Id) Error!bool {
        var scratch_buffer: [512]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const scratch_allocator = scratch.allocator();
        var pending: std.ArrayList(Id) = .empty;
        defer pending.deinit(scratch_allocator);
        try pending.append(scratch_allocator, try self.resolve(root, 0));
        var budget: usize = 1_000_000;
        while (pending.pop()) |id| {
            if (budget == 0) return error.TypeLimit;
            budget -= 1;
            const value = self.node(id);
            switch (value.tag) {
                .variable => if (value.a == variable) return true,
                .function => try pending.appendSlice(scratch_allocator, &.{ value.a, value.b }),
                .product => try pending.appendSlice(scratch_allocator, self.list(.{ .start = value.a, .len = value.b })),
                .array, .list, .demand, .resolver, .provider => try pending.append(scratch_allocator, value.a),
                .state_provider => try pending.appendSlice(scratch_allocator, &.{ value.a, value.b, value.c }),
                .record => for (0..value.b) |i| {
                    try pending.append(scratch_allocator, self.recordField(value, i).ty);
                },
                .nominal => try pending.appendSlice(scratch_allocator, self.nominalArguments(value)),
                else => {},
            }
        }
        return false;
    }
    pub fn unifyEffects(self: *Store, left: Effects.Id, right: Effects.Id) Error!void {
        self.effects.unify(left, right) catch |err| return effectError(err);
    }
    pub fn freshEffects(self: *Store) Error!Effects.Id {
        return self.effects.fresh() catch |err| return effectError(err);
    }
    pub fn resolveEffects(self: *Store, effect_row: Effects.Id, at: Cursor) Error!Effects.Id {
        return self.effects.resolve(effect_row, at) catch |err| return effectError(err);
    }
    pub fn row(self: *const Store, id: Effects.Id) Effects.Row {
        return self.effects.node(id);
    }
    pub fn rowLabels(self: *const Store, id: Effects.Id) []const Effects.Label {
        return self.effects.list(self.row(id).labels);
    }
    pub fn operation(self: *const Store, label: Effects.Label) Operation {
        return self.operations.items[label];
    }
    pub fn operationArguments(self: *const Store, label: Effects.Label) []const Id {
        return self.list(self.operation(label).arguments);
    }
    /// Exact closed operation identity. These IDs are owned by this store;
    /// import/publication must copy identities and arguments, then remap labels.
    pub fn internOperation(self: *Store, identity: NominalIdentity, arguments: []const Id) Error!Effects.Label {
        var scratch_buffer: [512]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const scratch_allocator = scratch.allocator();
        const point = self.mark();
        errdefer self.rollback(point);
        const borrowed = try scratch_allocator.dupe(Id, arguments);
        defer scratch_allocator.free(borrowed);
        var resolved: std.ArrayList(Id) = .empty;
        defer resolved.deinit(scratch_allocator);
        for (borrowed) |argument| {
            const ty = try self.resolve(argument, 0);
            if (!try self.equalClosed(ty, ty)) return error.TypeMismatch;
            try resolved.append(scratch_allocator, ty);
        }
        for (self.operations.items[1..], 1..) |candidate, index| {
            if (!std.meta.eql(identity, candidate.identity)) continue;
            const old = self.list(candidate.arguments);
            if (old.len != resolved.items.len) continue;
            var same = true;
            for (old, resolved.items) |a, b| same = same and try self.equalClosed(a, b);
            if (same) return @intCast(index);
        }
        if (self.operations.items.len == none) return error.TypeLimit;
        const span = try self.saveList(resolved.items);
        const id: Effects.Label = @intCast(self.operations.items.len);
        try self.operations.append(self.allocator, .{ .identity = identity, .arguments = span });
        return id;
    }
    /// Read-only exact comparison. A variable or open latent row is not closed,
    /// even when the two source IDs happen to be identical.
    pub fn equalClosed(self: *const Store, left: Id, right: Id) Error!bool {
        var scratch_buffer: [512]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const scratch_allocator = scratch.allocator();
        const Pair = struct { a: Id, b: Id };
        var pending: std.ArrayList(Pair) = .empty;
        defer pending.deinit(scratch_allocator);
        try pending.append(scratch_allocator, .{ .a = left, .b = right });
        var budget: usize = 1_000_000;
        while (pending.pop()) |pair| {
            if (budget == 0) return error.TypeLimit;
            budget -= 1;
            const a = self.node(pair.a);
            const b = self.node(pair.b);
            if (a.tag != b.tag) return false;
            switch (a.tag) {
                .variable, .absent => return false,
                .function, .demand, .provider => {
                    const ar = self.effects.node(a.c);
                    const br = self.effects.node(b.c);
                    if (ar.tail != .closed or br.tail != .closed or ar.labels.len != br.labels.len) return false;
                    for (self.effects.list(ar.labels)) |label| {
                        var ac: usize = 0;
                        var bc: usize = 0;
                        for (self.effects.list(ar.labels)) |v| ac += @intFromBool(v == label);
                        for (self.effects.list(br.labels)) |v| bc += @intFromBool(v == label);
                        if (ac != bc) return false;
                    }
                    if (a.tag == .function) try pending.append(scratch_allocator, .{ .a = a.b, .b = b.b });
                    try pending.append(scratch_allocator, .{ .a = a.a, .b = b.a });
                },
                .array, .list, .resolver => try pending.append(scratch_allocator, .{ .a = a.a, .b = b.a }),
                .state_provider => try pending.appendSlice(scratch_allocator, &.{ .{ .a = a.a, .b = b.a }, .{ .a = a.b, .b = b.b }, .{ .a = a.c, .b = b.c } }),
                .type_constructor => if (a.a != b.a or a.b != b.b) return false,
                .product => {
                    if (a.b != b.b) return false;
                    for (self.list(.{ .start = a.a, .len = a.b }), self.list(.{ .start = b.a, .len = b.b })) |av, bv| try pending.append(scratch_allocator, .{ .a = av, .b = bv });
                },
                .nominal => {
                    if (a.a != b.a or a.b != b.b) return false;
                    const aa = self.nominalArguments(a);
                    const ba = self.nominalArguments(b);
                    if (aa.len != ba.len) return false;
                    for (aa, ba) |av, bv| try pending.append(scratch_allocator, .{ .a = av, .b = bv });
                },
                .record => {
                    if (a.b != b.b) return false;
                    for (0..a.b) |i| {
                        const field = self.recordField(a, i);
                        var found: ?Id = null;
                        for (0..b.b) |j| {
                            const other = self.recordField(b, j);
                            if (field.name == other.name) {
                                found = other.ty;
                                break;
                            }
                        }
                        try pending.append(scratch_allocator, .{ .a = field.ty, .b = found orelse return false });
                    }
                },
                else => {},
            }
        }
        return true;
    }
    /// Failed unification leaves all owned tables exactly at the entry mark.
    pub const MismatchReporter = struct {
        context: *anyopaque,
        report: *const fn (*anyopaque, *const Store, Id, Id) std.mem.Allocator.Error!void,
    };
    fn mismatch(self: *const Store, reporter: ?MismatchReporter, left: Id, right: Id) Error {
        if (reporter) |observer| observer.report(observer.context, self, left, right) catch return error.OutOfMemory;
        return error.TypeMismatch;
    }
    pub fn unify(self: *Store, left: Id, right: Id) Error!void {
        return self.unifyWithReporter(left, right, null);
    }
    /// Observe the failing resolved equation before transactional rollback.
    /// The reporter may copy diagnostics; it cannot change the solver.
    pub fn unifyWithReporter(self: *Store, left: Id, right: Id, reporter: ?MismatchReporter) Error!void {
        var scratch_buffer: [512]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const scratch_allocator = scratch.allocator();
        const point = self.mark();
        errdefer self.rollback(point);
        const Pair = struct { a: Id, b: Id, effect_row: bool = false };
        var pending: std.ArrayList(Pair) = .empty;
        defer pending.deinit(scratch_allocator);
        try pending.append(scratch_allocator, .{ .a = left, .b = right });
        while (pending.pop()) |pair| {
            if (pair.effect_row) {
                try self.unifyEffects(pair.a, pair.b);
                continue;
            }
            const a = try self.resolve(pair.a, 0);
            const b = try self.resolve(pair.b, 0);
            if (a == b or a == never or b == never) continue;
            const an = self.node(a);
            const bn = self.node(b);
            if (an.tag == .variable and bn.tag == .variable and an.a == bn.a) continue;
            if (an.tag == .variable) {
                if (try self.occurs(an.a, b)) return error.InfiniteType;
                try self.appendVersion(a, b);
            } else if (bn.tag == .variable) {
                if (try self.occurs(bn.a, a)) return error.InfiniteType;
                try self.appendVersion(b, a);
            } else if (an.tag != bn.tag) return self.mismatch(reporter, a, b) else switch (an.tag) {
                .function => {
                    // Stack order makes parameter constraints precede results.
                    try pending.append(scratch_allocator, .{ .a = an.c, .b = bn.c, .effect_row = true });
                    try pending.append(scratch_allocator, .{ .a = an.b, .b = bn.b });
                    try pending.append(scratch_allocator, .{ .a = an.a, .b = bn.a });
                },
                .product => {
                    if (an.b != bn.b) return self.mismatch(reporter, a, b);
                    var i: usize = an.b;
                    while (i != 0) {
                        i -= 1;
                        try pending.append(scratch_allocator, .{ .a = self.extra.items[an.a + i], .b = self.extra.items[bn.a + i] });
                    }
                },
                .array, .list, .resolver => try pending.append(scratch_allocator, .{ .a = an.a, .b = bn.a }),
                .demand, .provider => {
                    try pending.append(scratch_allocator, .{ .a = an.c, .b = bn.c, .effect_row = true });
                    try pending.append(scratch_allocator, .{ .a = an.a, .b = bn.a });
                },
                .state_provider => {
                    try pending.append(scratch_allocator, .{ .a = an.c, .b = bn.c });
                    try pending.append(scratch_allocator, .{ .a = an.b, .b = bn.b });
                    try pending.append(scratch_allocator, .{ .a = an.a, .b = bn.a });
                },
                .type_constructor => if (an.a != bn.a or an.b != bn.b) return self.mismatch(reporter, a, b),
                .nominal => {
                    if (an.a != bn.a or an.b != bn.b) return self.mismatch(reporter, a, b);
                    // Enqueue numeric child IDs before solving another pair.
                    // Pending-work growth does not mutate Store.extra; these
                    // borrowed spans expire before later resolve/write growth.
                    const aa = self.nominalArguments(an);
                    const bb = self.nominalArguments(bn);
                    if (aa.len != bb.len) return self.mismatch(reporter, a, b);
                    var i = aa.len;
                    while (i != 0) {
                        i -= 1;
                        try pending.append(scratch_allocator, .{ .a = aa[i], .b = bb[i] });
                    }
                },
                .record => {
                    if (an.b != bn.b) return self.mismatch(reporter, a, b);
                    for (0..an.b) |i| {
                        const af = self.recordField(an, i);
                        var found: ?Id = null;
                        for (0..bn.b) |j| {
                            const bf = self.recordField(bn, j);
                            if (af.name == bf.name) {
                                found = bf.ty;
                                break;
                            }
                        }
                        try pending.append(scratch_allocator, .{ .a = af.ty, .b = found orelse return self.mismatch(reporter, a, b) });
                    }
                },
                else => {},
            }
        }
    }
    pub fn freeVariables(self: *Store, root: Id) Error![]Id {
        return self.freeVariablesMode(root, true);
    }
    // The unbuffered mode is the original traversal used by differential laws.
    fn freeVariablesMode(self: *Store, root: Id, comptime bounded: bool) Error![]Id {
        // Only the worklist and visited set borrow this buffer. Returned
        // variable IDs always use the Store allocator; large graphs spill.
        var scratch_bytes: [1024]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_bytes, self.allocator);
        const temporary = if (bounded) scratch.allocator() else self.allocator;
        var values: std.ArrayList(Id) = .empty;
        errdefer values.deinit(self.allocator);
        var pending: std.ArrayList(Id) = .empty;
        defer pending.deinit(temporary);
        const resolved = try self.resolve(root, 0);
        // A certified graph is independent of substitution history and
        // contains no free type or row variable. Resolution has checked depth.
        if (bounded and (resolved <= never or self.closedHeight(resolved) != 0)) return &.{};
        if (bounded and self.node(resolved).tag == .variable) return self.allocator.dupe(Id, &.{resolved});
        try pending.append(temporary, resolved);
        var seen: std.AutoHashMapUnmanaged(Id, void) = .empty;
        defer seen.deinit(temporary);
        while (pending.pop()) |id| {
            if (bounded and self.closedHeight(id) != 0) continue;
            const entry = try seen.getOrPut(temporary, id);
            if (entry.found_existing) continue;
            const value = self.node(id);
            switch (value.tag) {
                .variable => try values.append(self.allocator, id),
                .function => try pending.appendSlice(temporary, &.{ value.a, value.b }),
                .product => try pending.appendSlice(temporary, self.list(.{ .start = value.a, .len = value.b })),
                .array, .list, .demand, .resolver, .provider => try pending.append(temporary, value.a),
                .state_provider => try pending.appendSlice(temporary, &.{ value.a, value.b, value.c }),
                .record => for (0..value.b) |i| {
                    try pending.append(temporary, self.recordField(value, i).ty);
                },
                .nominal => try pending.appendSlice(temporary, self.nominalArguments(value)),
                else => {},
            }
        }
        return values.toOwnedSlice(self.allocator);
    }
    fn has(values: []const u32, value: u32) bool {
        for (values) |item| if (item == value) return true;
        return false;
    }
    fn unionInto(self: *Store, values: *std.ArrayList(u32), added: []const u32) Error!void {
        for (added) |item| if (!has(values.items, item)) try values.append(self.allocator, item);
    }
    /// Covariant pure rows close in principal schemes; rows tied to callback
    /// parameters, returned values or retained predicates remain polymorphic.
    pub fn closeCovariant(self: *Store, root: Id, generalized: []const u32, protected: []const u32) Error!Id {
        return self.closeCovariantDepth(root, generalized, protected, null, 0);
    }
    /// The returned raw tail indices certify only the decisions made by the
    /// covariance rule. They do not mutate inference history or authorize
    /// closing any other unresolved row in a retained body.
    pub fn closeCovariantCertified(self: *Store, root: Id, generalized: []const u32, protected: []const u32) Error!ClosedCovariant {
        var decisions: std.ArrayList(u32) = .empty;
        defer decisions.deinit(self.allocator);
        const closed = try self.closeCovariantDepth(root, generalized, protected, &decisions, 0);
        return .{ .root = closed, .closed_rows = try self.saveList(decisions.items) };
    }
    fn closeCovariantDepth(self: *Store, root: Id, generalized: []const u32, protected: []const u32, decisions: ?*std.ArrayList(u32), depth: usize) Error!Id {
        if (depth >= 1024) return error.TypeLimit;
        const value = self.node(root);
        switch (value.tag) {
            .provider => {
                var effect_row = value.c;
                const tail = self.effects.node(effect_row).tail;
                const token_rows = try self.freeRowVariables(value.a);
                defer self.allocator.free(token_rows);
                if (tail == .variable and has(generalized, tail.variable) and !has(protected, tail.variable) and !has(token_rows, tail.variable)) {
                    if (decisions) |recorded| if (!has(recorded.items, tail.variable)) try recorded.append(self.allocator, tail.variable);
                    effect_row = self.effects.row(self.rowLabels(effect_row), .closed) catch |err| return effectError(err);
                }
                return self.provider(value.a, effect_row);
            },
            .function => {
                const parameter_free = try self.freeRowVariables(value.a);
                defer self.allocator.free(parameter_free);
                const result_free = try self.freeRowVariables(value.b);
                defer self.allocator.free(result_free);
                var effect_row = value.c;
                const tail = self.effects.node(effect_row).tail;
                if (tail == .variable and has(generalized, tail.variable) and !has(protected, tail.variable) and !has(parameter_free, tail.variable) and !has(result_free, tail.variable)) {
                    if (decisions) |recorded| if (!has(recorded.items, tail.variable)) try recorded.append(self.allocator, tail.variable);
                    effect_row = self.effects.row(self.rowLabels(effect_row), .closed) catch |err| return effectError(err);
                }
                var nested: std.ArrayList(u32) = .empty;
                defer nested.deinit(self.allocator);
                try self.unionInto(&nested, protected);
                try self.unionInto(&nested, parameter_free);
                const closed_tail = self.effects.node(effect_row).tail;
                if (closed_tail == .variable) try self.unionInto(&nested, &.{closed_tail.variable});
                return self.functionWithEffects(value.a, try self.closeCovariantDepth(value.b, generalized, nested.items, decisions, depth + 1), effect_row);
            },
            .product, .record => {
                var protected_siblings: std.ArrayList(u32) = .empty;
                defer protected_siblings.deinit(self.allocator);
                try self.unionInto(&protected_siblings, protected);
                for (0..value.b) |i| {
                    const child = if (value.tag == .record) self.recordField(value, i).ty else self.extra.items[value.a + i];
                    try self.covariantInputs(child, &protected_siblings, depth + 1);
                }
                var children: std.ArrayList(Id) = .empty;
                defer children.deinit(self.allocator);
                var fields: std.ArrayList(Field) = .empty;
                defer fields.deinit(self.allocator);
                for (0..value.b) |i| {
                    const field = if (value.tag == .record) self.recordField(value, i) else Field{ .name = 0, .ty = self.extra.items[value.a + i] };
                    const child = try self.closeCovariantDepth(field.ty, generalized, protected_siblings.items, decisions, depth + 1);
                    if (value.tag == .record) try fields.append(self.allocator, .{ .name = field.name, .ty = child }) else try children.append(self.allocator, child);
                }
                return if (value.tag == .record) self.record(fields.items) else self.product(children.items);
            },
            .array, .list => return self.sequence(value.tag, try self.closeCovariantDepth(value.a, generalized, protected, decisions, depth + 1)),
            // Nominal arguments and Demand's latent computation are invariant.
            else => return root,
        }
    }
    fn covariantInputs(self: *Store, root: Id, out: *std.ArrayList(u32), depth: usize) Error!void {
        if (depth >= 1024) return error.TypeLimit;
        const value = self.node(root);
        switch (value.tag) {
            .function => {
                const free = try self.freeRowVariables(value.a);
                defer self.allocator.free(free);
                try self.unionInto(out, free);
                try self.covariantInputs(value.b, out, depth + 1);
            },
            .nominal, .demand, .state_provider => {
                const free = try self.freeRowVariables(root);
                defer self.allocator.free(free);
                try self.unionInto(out, free);
            },
            .provider => {
                const free = try self.freeRowVariables(value.a);
                defer self.allocator.free(free);
                try self.unionInto(out, free);
            },
            .product, .record => for (0..value.b) |i| {
                try self.covariantInputs(if (value.tag == .record) self.recordField(value, i).ty else self.extra.items[value.a + i], out, depth + 1);
            },
            .array, .list => try self.covariantInputs(value.a, out, depth + 1),
            else => {},
        }
    }
    /// Each use opens only covariant closed rows. A callback's parameter row
    /// remains the exact requirement checked by its producer.
    pub fn openCovariant(self: *Store, root: Id) Error!Id {
        return self.openCovariantDepth(root, 0);
    }
    fn openCovariantDepth(self: *Store, root: Id, depth: usize) Error!Id {
        if (depth >= 1024) return error.TypeLimit;
        const value = self.node(root);
        switch (value.tag) {
            .provider => {
                var effect_row = value.c;
                if (self.effects.node(effect_row).tail == .closed) {
                    const opened_row = try self.freshEffects();
                    effect_row = self.effects.row(self.rowLabels(effect_row), self.effects.node(opened_row).tail) catch |err| return effectError(err);
                }
                return self.provider(value.a, effect_row);
            },
            .function => {
                const result = try self.openCovariantDepth(value.b, depth + 1);
                var effect_row = value.c;
                if (self.effects.node(effect_row).tail == .closed) {
                    const opened_row = try self.freshEffects();
                    effect_row = self.effects.row(self.rowLabels(effect_row), self.effects.node(opened_row).tail) catch |err| return effectError(err);
                }
                return self.functionWithEffects(value.a, result, effect_row);
            },
            .product, .record => {
                var children: std.ArrayList(Id) = .empty;
                defer children.deinit(self.allocator);
                var fields: std.ArrayList(Field) = .empty;
                defer fields.deinit(self.allocator);
                for (0..value.b) |i| {
                    const field = if (value.tag == .record) self.recordField(value, i) else Field{ .name = 0, .ty = self.extra.items[value.a + i] };
                    const child = try self.openCovariantDepth(field.ty, depth + 1);
                    if (value.tag == .record) try fields.append(self.allocator, .{ .name = field.name, .ty = child }) else try children.append(self.allocator, child);
                }
                return if (value.tag == .record) self.record(fields.items) else self.product(children.items);
            },
            .array, .list => return self.sequence(value.tag, try self.openCovariantDepth(value.a, depth + 1)),
            else => return root,
        }
    }
    /// Row quantifiers inhabit a separate namespace from value type variables.
    pub fn freeRowVariables(self: *Store, root: Id) Error![]u32 {
        return self.freeRowVariablesMode(root, true);
    }
    // The unbuffered mode is the original traversal used by differential laws.
    fn freeRowVariablesMode(self: *Store, root: Id, comptime bounded: bool) Error![]u32 {
        if (bounded and (root <= never or self.closedHeight(root) != 0)) return &.{};
        if (bounded) {
            const selected = self.head(root, 0);
            if (selected <= never or self.node(selected).tag == .variable or self.node(selected).tag == .type_constructor) return &.{};
        }
        // Only the worklist and visited set borrow this buffer. Returned
        // variable IDs always use the Store allocator; large graphs spill.
        var scratch_bytes: [1024]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_bytes, self.allocator);
        const temporary = if (bounded) scratch.allocator() else self.allocator;
        var result: std.ArrayList(u32) = .empty;
        errdefer result.deinit(self.allocator);
        // Inspect historical views without allocating normalized type/row
        // copies. Recursive environments can ask for the same raw callable
        // at many cursors; materializing every observation makes them quadratic.
        const Work = struct { id: Id, at: Cursor, depth: u32 = 0 };
        var pending: std.ArrayList(Work) = .empty;
        defer pending.deinit(temporary);
        var seen: std.AutoHashMapUnmanaged(u64, void) = .empty;
        defer seen.deinit(temporary);
        try pending.append(temporary, .{ .id = root, .at = 0 });
        while (pending.pop()) |work| {
            if (work.depth >= 1024) return error.TypeLimit;
            var id = work.id;
            var at = work.at;
            while (self.node(id).tag == .variable) {
                const variable = self.node(id);
                at = @max(at, variable.b);
                const write = self.replacement(variable.a, at) orelse break;
                id = write.replacement;
                at = write.position + 1;
            }
            if (bounded) {
                if (id <= never or self.node(id).tag == .variable or self.node(id).tag == .type_constructor) continue;
                const height = self.closedHeight(id);
                if (height != 0) {
                    // Skipping an empty subtree still charges its full depth.
                    if (@as(usize, work.depth) + height > 1024) return error.TypeLimit;
                    continue;
                }
            }
            const entry = try seen.getOrPut(temporary, (@as(u64, id) << 32) | at);
            if (entry.found_existing) continue;
            const value = self.node(id);
            if (value.tag == .function or value.tag == .demand or value.tag == .provider) {
                var row_ = self.effects.node(value.c);
                var row_at = @max(at, row_.cursor);
                while (row_.tail == .variable) {
                    row_at = @max(row_at, row_.cursor);
                    const write = self.effects.replacementAt(row_.tail.variable, row_at) orelse break;
                    row_ = self.effects.node(write.replacement);
                    row_at = write.position + 1;
                }
                if (row_.tail == .variable and !has(result.items, row_.tail.variable)) try result.append(self.allocator, row_.tail.variable);
            }
            switch (value.tag) {
                .function => {
                    try pending.append(temporary, .{ .id = value.a, .at = at, .depth = work.depth + 1 });
                    try pending.append(temporary, .{ .id = value.b, .at = at, .depth = work.depth + 1 });
                },
                .product => for (self.list(.{ .start = value.a, .len = value.b })) |child| {
                    try pending.append(temporary, .{ .id = child, .at = at, .depth = work.depth + 1 });
                },
                .array, .list, .demand, .resolver, .provider => try pending.append(temporary, .{ .id = value.a, .at = at, .depth = work.depth + 1 }),
                .state_provider => {
                    try pending.append(temporary, .{ .id = value.a, .at = at, .depth = work.depth + 1 });
                    try pending.append(temporary, .{ .id = value.b, .at = at, .depth = work.depth + 1 });
                    try pending.append(temporary, .{ .id = value.c, .at = at, .depth = work.depth + 1 });
                },
                .record => for (0..value.b) |i| {
                    try pending.append(temporary, .{ .id = self.recordField(value, i).ty, .at = at, .depth = work.depth + 1 });
                },
                .nominal => for (self.nominalArguments(value)) |child| {
                    try pending.append(temporary, .{ .id = child, .at = at, .depth = work.depth + 1 });
                },
                else => {},
            }
        }
        return result.toOwnedSlice(self.allocator);
    }
    /// Substitute quantified scheme variables, without writing solver history.
    pub fn substitute(self: *Store, root: Id, old: []const Id, fresh_ids: []const Id) Error!Id {
        return self.substituteWithRows(root, old, fresh_ids, &.{}, &.{});
    }
    pub fn substituteWithRows(self: *Store, root: Id, old: []const Id, fresh_ids: []const Id, old_rows: []const u32, fresh_rows: []const Effects.Id) Error!Id {
        std.debug.assert(old.len == fresh_ids.len and old_rows.len == fresh_rows.len);
        // A monomorphic scheme needs no type copying. Keep its raw historical
        // view; callers still reopen eligible covariant latent rows separately.
        if (old.len == 0 and old_rows.len == 0) return root;
        return self.substituteDepth(root, old, fresh_ids, old_rows, fresh_rows, 0);
    }
    fn substitutedRow(self: *Store, effect_row: Effects.Id, old: []const u32, replacements: []const Effects.Id) Error!Effects.Id {
        var result = effect_row;
        for (old, replacements) |variable, replacement_id| result = self.effects.substitute(result, variable, replacement_id) catch |err| return effectError(err);
        return result;
    }
    fn substituteDepth(self: *Store, root: Id, old: []const Id, fresh_ids: []const Id, old_rows: []const u32, fresh_rows: []const Effects.Id, depth: usize) Error!Id {
        if (depth >= 1024) return error.TypeLimit;
        for (old, fresh_ids) |a, b| if (root == a) return b;
        const value = self.node(root);
        switch (value.tag) {
            .function => return self.functionWithEffects(try self.substituteDepth(value.a, old, fresh_ids, old_rows, fresh_rows, depth + 1), try self.substituteDepth(value.b, old, fresh_ids, old_rows, fresh_rows, depth + 1), try self.substitutedRow(value.c, old_rows, fresh_rows)),
            .product => {
                var fields: std.ArrayList(Id) = .empty;
                defer fields.deinit(self.allocator);
                for (0..value.b) |i| try fields.append(self.allocator, try self.substituteDepth(self.extra.items[value.a + i], old, fresh_ids, old_rows, fresh_rows, depth + 1));
                return self.product(fields.items);
            },
            .array, .list => return self.sequence(value.tag, try self.substituteDepth(value.a, old, fresh_ids, old_rows, fresh_rows, depth + 1)),
            .demand => return self.demandWithEffects(try self.substituteDepth(value.a, old, fresh_ids, old_rows, fresh_rows, depth + 1), try self.substitutedRow(value.c, old_rows, fresh_rows)),
            .provider => return self.provider(try self.substituteDepth(value.a, old, fresh_ids, old_rows, fresh_rows, depth + 1), try self.substitutedRow(value.c, old_rows, fresh_rows)),
            .state_provider => return self.stateProvider(try self.substituteDepth(value.a, old, fresh_ids, old_rows, fresh_rows, depth + 1), try self.substituteDepth(value.b, old, fresh_ids, old_rows, fresh_rows, depth + 1), try self.substituteDepth(value.c, old, fresh_ids, old_rows, fresh_rows, depth + 1)),
            .resolver => return self.resolver(try self.substituteDepth(value.a, old, fresh_ids, old_rows, fresh_rows, depth + 1)),
            .record => {
                var fields: std.ArrayList(Field) = .empty;
                defer fields.deinit(self.allocator);
                for (0..value.b) |i| {
                    const field = self.recordField(value, i);
                    try fields.append(self.allocator, .{ .name = field.name, .ty = try self.substituteDepth(field.ty, old, fresh_ids, old_rows, fresh_rows, depth + 1) });
                }
                return self.record(fields.items);
            },
            .nominal => {
                const prior = try self.allocator.dupe(Id, self.nominalArguments(value));
                defer self.allocator.free(prior);
                var args: std.ArrayList(Id) = .empty;
                defer args.deinit(self.allocator);
                for (prior) |child| try args.append(self.allocator, try self.substituteDepth(child, old, fresh_ids, old_rows, fresh_rows, depth + 1));
                return self.nominal(.{ .unit = value.a, .decl = value.b }, args.items);
            },
            else => return root,
        }
    }
};

test "cursor histories retain repeated writes and self references" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const a = try store.fresh();
    const b = try store.fresh();
    try store.appendVersion(a, b);
    try store.appendVersion(b, a);
    try store.appendVersion(a, u32_type);
    try store.appendVersion(a, f32_type);
    try std.testing.expectEqual(u32_type, try store.resolve(a, 0));
    try std.testing.expectEqual(f32_type, try store.resolve(a, 3));
    const view = try store.resolve(a, 4);
    try std.testing.expectEqual(store.node(a).a, store.node(view).a);
    try std.testing.expectEqual(@as(u32, 4), store.node(view).b);
    const point = store.mark();
    try store.appendVersion(b, boolean);
    try std.testing.expectEqual(boolean, try store.resolve(b, 4));
    store.rollback(point);
    const b_view = try store.resolve(b, 4);
    try std.testing.expectEqual(store.node(b).a, store.node(b_view).a);
}
test "occurs and mismatch rollback preserve prior constraints" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const a = try store.fresh();
    const recursive = try store.function(a, u32_type);
    const point = store.mark();
    try std.testing.expectError(error.InfiniteType, store.unify(a, recursive));
    try std.testing.expectEqual(point, store.mark());
    const left = try store.product(&.{ a, boolean });
    const right = try store.product(&.{ f32_type, u32_type });
    const before = store.mark();
    try std.testing.expectError(error.TypeMismatch, store.unify(left, right));
    try std.testing.expectEqual(before, store.mark());
    try std.testing.expectEqual(a, try store.resolve(a, 0));
}
test "indexed scalar histories equal sequential replacement oracle at every cursor" {
    var random = std.Random.DefaultPrng.init(0x12345678);
    for (0..80) |_| {
        var store = try Store.init(std.testing.allocator);
        defer store.deinit();
        var ids: [8]Id = undefined;
        for (&ids) |*id| id.* = try store.fresh();
        for (0..40) |_| {
            const variable = ids[random.random().uintLessThan(usize, ids.len)];
            const selection = random.random().uintLessThan(usize, 11);
            const replacement_id = if (selection < 8) ids[selection] else ([_]Id{ u32_type, f32_type, boolean })[selection - 8];
            try store.appendVersion(variable, replacement_id);
        }
        for (0..41) |at| for (ids) |root| {
            var expected = root;
            for (store.versions.items[at..]) |write| {
                const value = store.node(expected);
                if (value.tag == .variable and value.a == write.variable) expected = write.replacement;
            }
            const actual = try store.resolve(root, @intCast(at));
            if (store.node(expected).tag == .variable) {
                try std.testing.expectEqual(Tag.variable, store.node(actual).tag);
                try std.testing.expectEqual(store.node(expected).a, store.node(actual).a);
                try std.testing.expectEqual(actual, try store.resolve(actual, 0));
            } else try std.testing.expectEqual(expected, actual);
        };
    }
}
test "principal scheme substitution creates independent uses" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const generic = try store.fresh();
    const root = try store.function(generic, generic);
    const first = try store.fresh();
    const second = try store.fresh();
    const a = try store.substitute(root, &.{generic}, &.{first});
    const b = try store.substitute(root, &.{generic}, &.{second});
    try store.unify(store.node(a).a, u32_type);
    try store.unify(store.node(b).a, f32_type);
    try std.testing.expectEqual(u32_type, store.node(try store.resolve(a, 0)).b);
    try std.testing.expectEqual(f32_type, store.node(try store.resolve(b, 0)).b);
    try std.testing.expectEqual(generic, try store.resolve(generic, 0));
}

test "unchanged aggregate resolution and empty substitution allocate no copies" {
    const Memory = @import("memory.zig");
    var tracked: Memory.TrackedAllocator = .{ .backing = std.testing.allocator };
    var store = try Store.init(tracked.allocator());
    defer store.deinit();
    const captured = try store.fresh();
    const callback = try store.function(unit, captured);
    const record_type = try store.record(&.{ .{ .name = 11, .ty = callback }, .{ .name = 12, .ty = f32_type } });
    const family = try store.nominal(.{ .unit = 3, .decl = 8 }, &.{ record_type, captured });
    const root = try store.product(&.{ u32_type, record_type, family });
    const before = tracked.counts;
    const point = store.mark();
    for (0..32) |_| {
        try std.testing.expectEqual(root, try store.resolve(root, 0));
        try std.testing.expectEqual(root, try store.substituteWithRows(root, &.{}, &.{}, &.{}, &.{}));
    }
    try std.testing.expectEqualDeep(before, tracked.counts);
    try std.testing.expectEqualDeep(point, store.mark());

    // Empty substitution must not resolve captured historical variables, and
    // it must not replace the separate per-use opening of covariant rows.
    try store.appendVersion(captured, u32_type);
    const written = store.mark();
    try std.testing.expectEqual(callback, try store.substitute(callback, &.{}, &.{}));
    try std.testing.expectEqualDeep(written, store.mark());
    try std.testing.expectEqual(captured, store.node(callback).b);
    const first = try store.openCovariant(try store.substitute(callback, &.{}, &.{}));
    const second = try store.openCovariant(try store.substitute(callback, &.{}, &.{}));
    try std.testing.expect(store.row(store.node(first).c).tail.variable != store.row(store.node(second).c).tail.variable);
    try std.testing.expectEqual(u32_type, store.node(try store.resolve(first, 0)).b);
    try std.testing.expectEqual(u32_type, store.node(try store.resolve(second, 0)).b);
}

fn aggregateResolutionScenario(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const variable = try store.fresh();
    const child = try store.product(&.{ variable, try store.array(variable), variable });
    var original: [65]Id = undefined;
    var fields: [65]Field = undefined;
    for (0..64) |i| {
        original[i] = if (i % 2 == 0) u32_type else f32_type;
        fields[i] = .{ .name = @intCast(100 + i), .ty = original[i] };
    }
    original[64] = child;
    fields[64] = .{ .name = 164, .ty = child };
    const product_type = try store.product(&original);
    const record_type = try store.record(&fields);
    const family = try store.nominal(.{ .unit = 7, .decl = 13 }, &original);
    try store.appendVersion(variable, boolean);
    // Force a recursive child rewrite to relocate the side table before the
    // parent's unchanged prefix is copied. Source ranges remain numeric IDs.
    const spare = store.extra.capacity - store.extra.items.len;
    for (0..spare) |_| _ = try store.saveList(&.{unit});
    const product_node = store.node(try store.resolve(product_type, 0));
    try std.testing.expectEqualSlices(Id, original[0..64], store.extra.items[product_node.a..][0..64]);
    const product_child = store.node(store.extra.items[product_node.a + 64]);
    try std.testing.expectEqual(boolean, store.extra.items[product_child.a]);
    try std.testing.expectEqual(boolean, store.node(store.extra.items[product_child.a + 1]).a);
    const record_node = store.node(try store.resolve(record_type, 0));
    for (fields[0..64], 0..) |field, i| try std.testing.expectEqualDeep(field, store.recordField(record_node, i));
    const record_child = store.node(store.recordField(record_node, 64).ty);
    try std.testing.expectEqual(boolean, store.extra.items[record_child.a + 2]);
    const nominal_node = store.node(try store.resolve(family, 0));
    try std.testing.expectEqualSlices(Id, original[0..64], store.nominalArguments(nominal_node)[0..64]);
    const nominal_child = store.node(store.nominalArguments(nominal_node)[64]);
    try std.testing.expectEqual(boolean, store.extra.items[nominal_child.a]);
    // The original payload tables stay immutable even when new views grow.
    try std.testing.expectEqualSlices(Id, &original, store.nominalArguments(store.node(family)));
}

test "changed aggregate resolution rereads numeric ranges after nested side table growth" {
    try aggregateResolutionScenario(std.testing.allocator);
}

test "lazy aggregate resolution releases every failed allocation" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, aggregateResolutionScenario, .{});
}

test "following a composite replacement skips earlier writes to its children" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const child = try store.fresh();
    const root = try store.fresh();
    const signature = try store.function(child, child);
    try store.appendVersion(child, u32_type);
    try store.appendVersion(root, signature);
    try store.appendVersion(child, f32_type);
    const resolved = store.node(try store.resolve(root, 0));
    try std.testing.expectEqual(f32_type, resolved.a);
    try std.testing.expectEqual(f32_type, resolved.b);
    // The same direct child still sees its earliest chronological write.
    try std.testing.expectEqual(u32_type, try store.resolve(child, 0));
}

test "unbound composite child retains the advanced cursor across later inspection" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const child = try store.fresh();
    const root = try store.fresh();
    try store.appendVersion(child, u32_type);
    try store.appendVersion(root, try store.function(child, child));
    const resolved = store.node(try store.resolve(root, 0));
    try std.testing.expectEqual(Tag.variable, store.node(resolved.a).tag);
    try std.testing.expectEqual(@as(u32, 2), store.node(resolved.a).b);
    try std.testing.expectEqual(resolved.a, try store.resolve(resolved.a, 0));
    try store.appendVersion(child, f32_type);
    try std.testing.expectEqual(f32_type, try store.resolve(resolved.a, 0));
}

test "nominal record and array children retain advanced chronological views" {
    const a = std.testing.allocator;
    var types = try Store.init(a);
    defer types.deinit();
    const field = try types.fresh();
    const root = try types.fresh();
    const payload = try types.record(&.{.{ .name = 42, .ty = try types.array(field) }});
    const family = try types.nominal(.{ .unit = 7, .decl = 11 }, &.{payload});
    try types.appendVersion(field, u32_type);
    try types.appendVersion(root, family);
    const projected = try types.resolve(root, 0);
    const args = types.nominalArguments(types.node(projected));
    const record_type = types.node(args[0]);
    const advanced = types.recordField(record_type, 0).ty;
    try std.testing.expectEqual(Tag.variable, types.node(types.node(advanced).a).tag);
    try types.appendVersion(field, f32_type);
    const next = try types.resolve(advanced, 0);
    try std.testing.expectEqual(f32_type, types.node(next).a);
    const original = try types.resolve(payload, 0);
    try std.testing.expectEqual(u32_type, types.node(types.recordField(types.node(original), 0).ty).a);
    // A nominal declaration with the same spelling/declaration slot in another
    // source unit has a distinct identity and cannot unify.
    const other = try types.nominal(.{ .unit = 8, .decl = 11 }, &.{payload});
    try std.testing.expectError(error.TypeMismatch, types.unify(family, other));
}
test "aggregate occurs checks and rejected shapes leave the complete region unchanged" {
    const a = std.testing.allocator;
    var types = try Store.init(a);
    defer types.deinit();
    const variable = try types.fresh();
    const record_ = try types.record(&.{.{ .name = 1, .ty = variable }});
    const array_ = try types.array(record_);
    const nominal_ = try types.nominal(.{ .unit = 1, .decl = 7 }, &.{array_});
    const point = types.mark();
    try std.testing.expectError(error.InfiniteType, types.unify(variable, nominal_));
    try std.testing.expectEqualDeep(point, types.mark());
    const differently_named = try types.record(&.{.{ .name = 2, .ty = u32_type }});
    const before = types.mark();
    try std.testing.expectError(error.TypeMismatch, types.unify(record_, differently_named));
    try std.testing.expectEqualDeep(before, types.mark());
    try types.unify(variable, u32_type);
    try std.testing.expectEqual(u32_type, try types.resolve(variable, 0));
}

test "demand types preserve chronological children and reject eager function modes" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const variable = try store.fresh();
    const suspended = try store.demand(variable);
    try store.unify(variable, u32_type);
    const resolved = store.node(try store.resolve(suspended, 0));
    try std.testing.expectEqual(Tag.demand, resolved.tag);
    try std.testing.expectEqual(u32_type, resolved.a);
    const lazy = try store.function(try store.demand(u32_type), u32_type);
    const eager = try store.function(u32_type, u32_type);
    const before = store.mark();
    try std.testing.expectError(error.TypeMismatch, store.unify(lazy, eager));
    try std.testing.expectEqual(before, store.mark());
    const generic = try store.fresh();
    const scheme = try store.demand(generic);
    const integer = try store.substitute(scheme, &.{generic}, &.{u32_type});
    const floating = try store.substitute(scheme, &.{generic}, &.{f32_type});
    try std.testing.expectEqual(u32_type, store.node(integer).a);
    try std.testing.expectEqual(f32_type, store.node(floating).a);
    try std.testing.expectEqual(Tag.variable, store.node(store.node(scheme).a).tag);
}

test "type and row replacements share one history cursor through function and demand children" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const ty = try store.fresh();
    const effect_row = try store.freshEffects();
    const variable = store.effects.node(effect_row).tail.variable;
    const first = try store.effects.row(&.{11}, .closed);
    const later = try store.effects.row(&.{22}, .closed);
    try store.effects.appendVersion(variable, first); // global position 0
    try store.appendVersion(ty, try store.functionWithEffects(unit, u32_type, effect_row)); // 1
    try store.effects.appendVersion(variable, later); // 2
    const resolved = store.node(try store.resolve(ty, 0));
    try std.testing.expectEqualSlices(u32, &.{22}, store.effects.list(store.effects.node(resolved.c).labels));
    try std.testing.expectEqual(@as(u32, 3), store.cursor());
    const suspended = try store.fresh();
    const demand_row = try store.freshEffects();
    try store.effects.appendVersion(store.effects.node(demand_row).tail.variable, first); // 3
    try store.appendVersion(suspended, try store.demandWithEffects(u32_type, demand_row)); // 4
    try store.effects.appendVersion(store.effects.node(demand_row).tail.variable, later); // 5
    const demand_node = store.node(try store.resolve(suspended, 0));
    try std.testing.expectEqualSlices(u32, &.{22}, store.effects.list(store.effects.node(demand_node.c).labels));
    try std.testing.expectEqual(@as(u32, 6), store.cursor());
}
test "rejected function effect rows roll back type and row writes and shared chronology" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const parameter = try store.fresh();
    const effect_row = try store.freshEffects();
    const left = try store.functionWithEffects(parameter, try store.functionWithEffects(unit, u32_type, effect_row), try store.effects.row(&.{11}, .closed));
    const right = try store.functionWithEffects(u32_type, try store.function(unit, u32_type), try store.effects.row(&.{22}, .closed));
    const point = store.mark();
    try std.testing.expectError(error.EffectMismatch, store.unify(left, right));
    try std.testing.expectEqualDeep(point, store.mark());
    try std.testing.expectEqual(parameter, try store.resolve(parameter, 0));
    try std.testing.expectEqual(effect_row, try store.resolveEffects(effect_row, 0));
}
test "recursive latent rows report InfiniteEffect without changing type or row history" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const latent = try store.freshEffects();
    const recursive = try store.effects.row(&.{11}, store.row(latent).tail);
    const left = try store.functionWithEffects(unit, u32_type, latent);
    const right = try store.functionWithEffects(unit, u32_type, recursive);
    const point = store.mark();
    try std.testing.expectError(error.InfiniteEffect, store.unify(left, right));
    try std.testing.expectEqualDeep(point, store.mark());
}
test "value and effect quantifiers freshen independently without accidental numeric identity" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const ty = try store.fresh();
    const effect_row = try store.freshEffects();
    const root = try store.functionWithEffects(ty, try store.demandWithEffects(ty, effect_row), effect_row);
    const rows = try store.freeRowVariables(root);
    defer store.allocator.free(rows);
    try std.testing.expectEqualSlices(u32, &.{0}, rows);
    const one_row = try store.freshEffects();
    const two_row = try store.freshEffects();
    const one = try store.substituteWithRows(root, &.{ty}, &.{u32_type}, rows, &.{one_row});
    const two = try store.substituteWithRows(root, &.{ty}, &.{f32_type}, rows, &.{two_row});
    const label = try store.effects.row(&.{ 7, 7 }, .closed);
    try store.unifyEffects(store.node(one).c, label);
    try std.testing.expectEqual(Effects.Tail.variable, std.meta.activeTag(store.effects.node(try store.resolveEffects(store.node(two).c, 0)).tail));
    const one_result = store.node(store.node(try store.resolve(one, 0)).b);
    try std.testing.expectEqual(u32_type, one_result.a);
    try std.testing.expectEqualSlices(u32, &.{ 7, 7 }, store.effects.list(store.effects.node(one_result.c).labels));
}
fn effectAllocationFailures(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const a = try store.fresh();
    const effect_row = try store.freshEffects();
    const function = try store.functionWithEffects(a, try store.demandWithEffects(a, effect_row), effect_row);
    const instantiated = try store.substituteWithRows(function, &.{a}, &.{u32_type}, &.{0}, &.{try store.freshEffects()});
    const point = store.mark();
    try store.unify(instantiated, try store.functionWithEffects(u32_type, try store.demandWithEffects(u32_type, try store.effects.row(&.{1}, .closed)), try store.effects.row(&.{1}, .closed)));
    _ = try store.resolve(instantiated, 0);
    store.rollback(point);
}
test "owned type effect integration releases every failed allocation" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, effectAllocationFailures, .{});
}

fn rowObservationScenario(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const first = try store.freshEffects();
    const second = try store.freshEffects();
    const first_variable = store.row(first).tail.variable;
    const second_variable = store.row(second).tail.variable;
    const callable = try store.functionWithEffects(unit, u32_type, first);
    const indirect = try store.fresh();
    try store.effects.appendVersion(first_variable, 0);
    try store.appendVersion(indirect, callable);
    try store.effects.appendVersion(second_variable, 0);
    try store.effects.appendVersion(first_variable, second);
    const record_ = try store.record(&.{.{ .name = 1, .ty = indirect }});
    const root = try store.product(&.{ callable, indirect, record_, try store.array(indirect), try store.nominal(.{ .unit = 1, .decl = 1 }, &.{indirect}), try store.demandWithEffects(indirect, first), try store.resolver(indirect) });
    const before = store.mark();
    const views = store.variable_views.count();
    // Direct access sees the first closed replacement. The composite type
    // replacement advances past it and reaches the second raw tail after its
    // older closed replacement. Both observations share the callable ID.
    const direct_rows = try store.freeRowVariables(callable);
    defer store.allocator.free(direct_rows);
    try std.testing.expectEqual(@as(usize, 0), direct_rows.len);
    for (0..8) |_| {
        const rows = try store.freeRowVariables(root);
        defer store.allocator.free(rows);
        try std.testing.expectEqualSlices(u32, &.{second_variable}, rows);
    }
    try std.testing.expectEqualDeep(before, store.mark());
    try std.testing.expectEqual(views, store.variable_views.count());
}
test "free row inspection preserves cursor-specific views without retained allocations" {
    try rowObservationScenario(std.testing.allocator);
}
test "free row observation releases every failed allocation" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, rowObservationScenario, .{});
}
fn providerTypeScenario(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const element = try store.fresh();
    const latent = try store.freshEffects();
    const row_variable = store.row(latent).tail.variable;
    const read = try store.nominal(.{ .unit = 2, .decl = 10 }, &.{element});
    const write = try store.nominal(.{ .unit = 2, .decl = 11 }, &.{element});
    const provider_ = try store.provider(read, latent);
    const state = try store.stateProvider(read, write, element);
    const root = try store.product(&.{ provider_, state });
    const free = try store.freeVariables(root);
    defer store.allocator.free(free);
    try std.testing.expectEqualSlices(Id, &.{element}, free);
    const rows = try store.freeRowVariables(root);
    defer store.allocator.free(rows);
    try std.testing.expectEqualSlices(u32, &.{row_variable}, rows);
    const replacement_row = try store.effects.row(&.{foreign_operation}, .closed);
    const concrete = try store.substituteWithRows(root, &.{element}, &.{u32_type}, &.{row_variable}, &.{replacement_row});
    const parts = store.list(.{ .start = store.node(concrete).a, .len = 2 });
    const actual_provider = store.node(parts[0]);
    const actual_state = store.node(parts[1]);
    try std.testing.expectEqual(Tag.provider, actual_provider.tag);
    try std.testing.expectEqual(Tag.state_provider, actual_state.tag);
    try std.testing.expectEqual(u32_type, actual_state.c);
    try std.testing.expectEqualSlices(Id, &.{u32_type}, store.nominalArguments(store.node(actual_state.a)));
    try std.testing.expectEqualSlices(Id, &.{u32_type}, store.nominalArguments(store.node(actual_state.b)));
    try std.testing.expect(try store.equalClosed(concrete, concrete));
    const closed = try store.closeCovariantCertified(provider_, &.{row_variable}, &.{});
    try std.testing.expectEqualSlices(u32, &.{row_variable}, store.list(closed.closed_rows));
    try std.testing.expect(store.row(store.node(closed.root).c).tail == .closed);
    try std.testing.expect(store.row(latent).tail == .variable);
    const reopened = try store.openCovariant(closed.root);
    try std.testing.expect(store.row(store.node(reopened).c).tail == .variable);
    const cycle = try store.fresh();
    const bad = try store.stateProvider(read, write, cycle);
    const mark_ = store.mark();
    if (store.unify(cycle, bad)) |_| {
        return error.TestExpectedError;
    } else |err| switch (err) {
        error.InfiniteType => {},
        error.OutOfMemory => return err,
        else => return err,
    }
    try std.testing.expectEqualDeep(mark_, store.mark());
}
test "provider and State type substitution preserves identities latent rows and occurs checks" {
    try providerTypeScenario(std.testing.allocator);
}
test "provider type inference releases every failed allocation" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, providerTypeScenario, .{});
}

test "closing principal rows preserves callback relationships and reopens each covariant use" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const row_id = try store.freshEffects();
    const variable = store.row(row_id).tail.variable;
    const pure = try store.functionWithEffects(u32_type, u32_type, row_id);
    const closed = try store.closeCovariant(pure, &.{variable}, &.{});
    try std.testing.expectEqual(@as(u32, 0), store.node(closed).c);
    const first = try store.openCovariant(closed);
    const second = try store.openCovariant(closed);
    try std.testing.expect(store.row(store.node(first).c).tail.variable != store.row(store.node(second).c).tail.variable);
    const callback = try store.functionWithEffects(unit, u32_type, row_id);
    const higher = try store.functionWithEffects(callback, u32_type, row_id);
    const protected = try store.closeCovariant(higher, &.{variable}, &.{});
    try std.testing.expectEqual(row_id, store.node(protected).c);
    try std.testing.expectEqual(row_id, store.node(store.node(protected).a).c);
    const opened = try store.openCovariant(try store.function(try store.function(unit, u32_type), u32_type));
    try std.testing.expectEqual(@as(u32, 0), store.node(store.node(opened).a).c);
    try std.testing.expect(store.row(store.node(opened).c).tail == .variable);
}
test "principal product siblings protect shared callback and nominal argument rows" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const row_id = try store.freshEffects();
    const callback = try store.functionWithEffects(unit, u32_type, row_id);
    const producer = try store.functionWithEffects(unit, u32_type, row_id);
    const consumer = try store.function(callback, u32_type);
    const product_type = try store.product(&.{ producer, consumer });
    const closed = try store.closeCovariant(product_type, &.{store.row(row_id).tail.variable}, &.{});
    const siblings = store.list(.{ .start = store.node(closed).a, .len = 2 });
    try std.testing.expectEqual(row_id, store.node(siblings[0]).c);
    const nominal_type = try store.nominal(.{ .unit = 1, .decl = 20 }, &.{callback});
    const invariant = try store.closeCovariant(nominal_type, &.{store.row(row_id).tail.variable}, &.{});
    try std.testing.expectEqual(nominal_type, invariant);
    try std.testing.expectEqual(nominal_type, try store.openCovariant(nominal_type));
}
test "covariant certificates record only owned positive tails and leave raw body rows unchanged" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const pure = try store.freshEffects();
    const callback = try store.freshEffects();
    const protected = try store.freshEffects();
    const demand_row = try store.freshEffects();
    const pure_type = try store.functionWithEffects(unit, u32_type, pure);
    const connected_type = try store.functionWithEffects(try store.functionWithEffects(unit, u32_type, callback), u32_type, callback);
    const protected_type = try store.functionWithEffects(unit, u32_type, protected);
    const delayed_type = try store.demandWithEffects(u32_type, demand_row);
    const root = try store.product(&.{ pure_type, connected_type, protected_type, delayed_type });
    const free = try store.freeRowVariables(root);
    defer store.allocator.free(free);
    const raw_mark = store.effects.mark();
    const closed = try store.closeCovariantCertified(root, free, &.{store.row(protected).tail.variable});
    try std.testing.expectEqualSlices(u32, &.{store.row(pure).tail.variable}, store.list(closed.closed_rows));
    const parts = store.list(.{ .start = store.node(closed.root).a, .len = store.node(closed.root).b });
    try std.testing.expectEqual(Effects.Tail.closed, store.row(store.node(parts[0]).c).tail);
    try std.testing.expectEqualDeep(store.row(callback).tail, store.row(store.node(parts[1]).c).tail);
    try std.testing.expectEqualDeep(store.row(protected).tail, store.row(store.node(parts[2]).c).tail);
    try std.testing.expectEqualDeep(store.row(demand_row).tail, store.row(store.node(parts[3]).c).tail);
    try std.testing.expectEqualDeep(store.row(pure).tail, store.row(store.node(pure_type).c).tail);
    try std.testing.expectEqual(raw_mark.versions, store.effects.mark().versions);
    try std.testing.expectEqual(raw_mark.next_position, store.effects.mark().next_position);
}
test "operation catalogs distinguish nominal phantom arguments and closed latent effect multiplicity" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const identity: NominalIdentity = .{ .unit = 8, .decl = 6 };
    const one = try store.nominal(.{ .unit = 3, .decl = 9 }, &.{u32_type});
    const same = try store.nominal(.{ .unit = 3, .decl = 9 }, &.{u32_type});
    const two = try store.nominal(.{ .unit = 3, .decl = 9 }, &.{f32_type});
    const label = try store.internOperation(identity, &.{one});
    try std.testing.expectEqual(label, try store.internOperation(identity, &.{same}));
    try std.testing.expect(label != try store.internOperation(identity, &.{two}));
    const closed_one = try store.functionWithEffects(unit, u32_type, try store.effects.row(&.{foreign_operation}, .closed));
    const closed_two = try store.functionWithEffects(unit, u32_type, try store.effects.row(&.{ foreign_operation, foreign_operation }, .closed));
    try std.testing.expect(try store.internOperation(identity, &.{closed_one}) != try store.internOperation(identity, &.{closed_two}));
    const open = try store.functionWithEffects(unit, u32_type, try store.freshEffects());
    const point = store.mark();
    try std.testing.expectError(error.TypeMismatch, store.internOperation(identity, &.{open}));
    try std.testing.expectEqualDeep(point, store.mark());
}

const VariableScratchTests = struct {
    const Fixture = struct {
        store: Store,
        variables: [32]Id,
        effect: Effects.Id,
        root: Id,

        fn init(allocator: std.mem.Allocator, certified: bool) !Fixture {
            var store = try Store.initWithOptions(allocator, .{ .closed_graphs = certified });
            errdefer store.deinit();
            var variables: [32]Id = undefined;
            for (&variables) |*variable| variable.* = try store.fresh();
            const effect = try store.freshEffects();
            var fields: [192]Field = undefined;
            for (&fields, 0..) |*field, i| {
                const child = if (i % 2 == 0) variables[i % variables.len] else u32_type;
                const row = if (i % 3 == 0) effect else 0;
                const value = try store.functionWithEffects(try store.sequence(.list, child), try store.array(child), row);
                field.* = .{ .name = @intCast(i + 1), .ty = if (i % 17 == 0) try store.typeConstructor(.{ .unit = 5, .decl = 23 }) else try store.nominal(.{ .unit = 3, .decl = 19 }, &.{value}) };
            }
            const root = try store.record(&fields);
            return .{ .store = store, .variables = variables, .effect = effect, .root = root };
        }
    };

    fn compare(left: *Store, right: *Store, roots: [2]Id) !void {
        const expected_types = try left.freeVariablesMode(roots[0], false);
        defer left.allocator.free(expected_types);
        const expected_rows = try left.freeRowVariablesMode(roots[0], false);
        defer left.allocator.free(expected_rows);
        const actual_types = try right.freeVariables(roots[1]);
        defer right.allocator.free(actual_types);
        const actual_rows = try right.freeRowVariables(roots[1]);
        defer right.allocator.free(actual_rows);
        try std.testing.expectEqualSlices(u32, expected_types, actual_types);
        try std.testing.expectEqualSlices(u32, expected_rows, actual_rows);
        try std.testing.expectEqualDeep(left.mark(), right.mark());
    }

    fn histories(allocator: std.mem.Allocator) !void {
        var left = try Fixture.init(allocator, false);
        defer left.store.deinit();
        var right = try Fixture.init(allocator, true);
        defer right.store.deinit();
        const roots = [_]Id{ left.root, right.root };
        for (0..never + 1) |scalar| try compare(&left.store, &right.store, .{ @intCast(scalar), @intCast(scalar) });
        try compare(&left.store, &right.store, .{ left.variables[0], right.variables[0] });
        try compare(&left.store, &right.store, roots);
        const marks = [_]Mark{ left.store.mark(), right.store.mark() };
        for ([_]*Fixture{ &left, &right }) |fixture| {
            try fixture.store.appendVersion(fixture.variables[31], try fixture.store.functionWithEffects(u32_type, fixture.variables[30], fixture.effect));
            for (fixture.variables[0..16]) |variable| try fixture.store.appendVersion(variable, u32_type);
            try fixture.store.effects.appendVersion(fixture.store.row(fixture.effect).tail.variable, 0);
        }
        try compare(&left.store, &right.store, .{ left.variables[0], right.variables[0] });
        try compare(&left.store, &right.store, .{ left.variables[31], right.variables[31] });
        try compare(&left.store, &right.store, roots);
        for ([_]*Fixture{ &left, &right }, marks) |fixture, mark| fixture.store.rollback(mark);
        try compare(&left.store, &right.store, roots);
        for ([_]*Fixture{ &left, &right }) |fixture| {
            const record = fixture.store.node(fixture.root);
            fixture.store.replaceListItem(.{ .start = record.a, .len = record.b * 2 }, 1, try fixture.store.fresh());
        }
        try compare(&left.store, &right.store, roots);
    }
};

test "variable scratch preserves ordered answers history physical writes and heap fallback through every allocation failure" {
    try VariableScratchTests.histories(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, VariableScratchTests.histories, .{});
}

test "variable scratch closed subgraphs retain exact nesting errors across the certificate boundary" {
    const a = std.testing.allocator;
    var left = try Store.init(a);
    defer left.deinit();
    var right = try Store.initWithOptions(a, .{ .closed_graphs = true });
    defer right.deinit();
    var roots = [_]Id{ u32_type, u32_type };
    for (0..1024) |depth| {
        roots[0] = try left.sequence(.list, roots[0]);
        roots[1] = try right.sequence(.list, roots[1]);
        if (depth == 253 or depth == 254 or depth == 255 or depth == 1022) try VariableScratchTests.compare(&left, &right, roots);
    }
    try std.testing.expectError(error.TypeLimit, left.freeVariablesMode(roots[0], false));
    try std.testing.expectError(error.TypeLimit, left.freeRowVariablesMode(roots[0], false));
    try std.testing.expectError(error.TypeLimit, right.freeVariables(roots[1]));
    try std.testing.expectError(error.TypeLimit, right.freeRowVariables(roots[1]));
}
