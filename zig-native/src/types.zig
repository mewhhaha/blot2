//! Owned dense types and ordered substitution history. Resolution follows the
//! first replacement at or after its cursor, then advances past that write.
//! It deliberately does not collapse history into union-find representatives.
const std = @import("std");
const resolution_cache = @import("resolution_cache.zig");
const epoch_cache = @import("epoch_resolution_cache.zig");
const composite_cache = @import("composite_resolution_cache.zig");
pub const Effects = @import("effects.zig");
pub const Id = u32;
pub const Cursor = u32;
pub const absent: Id = 0;
pub const unit: Id = 1;
pub const boolean: Id = 2;
pub const u32_type: Id = 3;
pub const f32_type: Id = 4;
pub const never: Id = 5;
pub const Tag = enum(u8) { absent, unit, boolean, u32, f32, never, variable, function, product, record, nominal, array, list, cursor, demand, type_constructor, resolver, provider, state_provider, projection, scoped, instance_selection };
pub const Node = struct {
    tag: Tag,
    // Owned structural certificate, kept in the existing three padding bytes.
    // Zero height declines the shortcut; generation never reuses rollback IDs.
    closed_height: u8 = 0,
    closed_generation: u16 = 0,
    a: u32 = 0,
    b: u32 = 0,
    // For a solver-owned variable with lower bound zero, c may contain a
    // resolution certified by closed_generation. Open answers also check the
    // remaining variable's last write. Publication rebuilds source variables
    // without this certificate; variable semantics still read only a and b.
    c: u32 = 0,
};
comptime {
    std.debug.assert(@sizeOf(Node) == 16);
}
/// Opaque declarations use a relocated spelling handle rather than an AST ordinal.
pub const opaque_name_bit: u32 = 0x80000000;
pub const NominalIdentity = struct { unit: u32, decl: u32 };
pub const Operation = struct { identity: NominalIdentity, arguments: List = .{}, instance: NominalIdentity = .{ .unit = 0, .decl = 0 } };
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
pub const ObligationKind = enum { arithmetic, ordered, equality, integer, field, writable_field, dispatch, result_dispatch, monad_factory, resolver_dispatch, resolver_shape, effect_operation, effect_handler, receiver, update, type_rep, effect_rep, type_head, collection, record_merge, callee_use, type_eq, contract };
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

const ProjectionResolution = struct { root: Id, at: Cursor, depth: u32 };
pub const Store = struct {
    use_closed_graphs: bool = false,
    has_projections: bool = false,
    projection_limit: usize = 1_000_000,
    projection_steps: usize = 0,
    resolution_depth_limit: usize = 1024,
    projection_exhausted: bool = false,
    associated_equations: std.AutoHashMapUnmanaged(Id, Id) = .empty,
    projection_resolution_types: u64 = 0,
    projection_resolution_rows: u64 = 0,
    projection_resolutions: std.AutoHashMapUnmanaged(ProjectionResolution, Id) = .empty,
    closed_generation: u16 = 1,
    closed_effect_physical_epoch: u64 = 0,
    // Writes and rollback advance this clock; recycled numeric IDs never make
    // an entry from a discarded history valid again. It is not rolled back.
    mutation_epoch: u64 = 0,
    /// Deterministic work counter: type nodes visited by occurs checks. It is
    /// never rolled back or consulted by solving, so pooled stores accumulate.
    occurs_steps: u64 = 0,
    /// Test-only normalizer visits, independent of cache admission and rollback.
    resolution_steps: u64 = 0,
    occurs_seen: std.ArrayList(u32) = .empty,
    occurs_generation: u32 = 0,
    use_resolution_cache: bool = true,
    resolved: epoch_cache.Cache = .{},
    use_composite_cache: bool = true,
    composite_min_growth: usize = 4,
    composites: composite_cache.Cache = .{},
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
    pub const Options = struct { resolution_cache: bool = true, closed_graphs: bool = false, composite_cache: bool = true, composite_min_growth: usize = 4 };

    pub fn init(allocator: std.mem.Allocator) Error!Store {
        return initWithOptions(allocator, .{});
    }
    pub fn initWithOptions(allocator: std.mem.Allocator, options: Options) Error!Store {
        var self: Store = .{ .allocator = allocator, .use_closed_graphs = options.closed_graphs, .use_resolution_cache = options.resolution_cache, .effects = Effects.Store.initWithOptions(allocator, .{ .resolution_cache = options.resolution_cache }) catch |err| return effectError(err) };
        self.use_composite_cache = options.composite_cache and options.closed_graphs;
        self.composite_min_growth = options.composite_min_growth;
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
        self.projection_resolutions.deinit(self.allocator);
        self.associated_equations.deinit(self.allocator);
        self.composites.deinit(self.allocator);
        self.occurs_seen.deinit(self.allocator);
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
    fn closedRowHeight(self: *const Store, id: Effects.Id) u8 {
        const r = self.effects.node(id);
        if (r.tail != .closed) return 0;
        var height: u8 = 0;
        for (self.effects.list(r.labels)) |label| {
            if (label >= self.operations.items.len) return 0;
            const instance = self.operations.items[label].instance;
            if (instance.unit == 0 and instance.decl != 0) return 0;
            for (self.list(self.operations.items[label].arguments)) |arg| {
                const argument_height = self.closedHeight(arg);
                if (argument_height == 0) return 0;
                height = @max(height, argument_height);
            }
        }
        if (height == std.math.maxInt(u8)) return 0;
        return height + 1;
    }
    fn closedNodeHeight(self: *const Store, n: Node) u8 {
        var height: u8 = 0;
        switch (n.tag) {
            .absent, .variable => return 0,
            .function, .demand, .provider => {
                const row_height = self.closedRowHeight(n.c);
                if (row_height == 0) return 0;
                height = self.closedHeight(n.a);
                if (height == 0) return 0;
                height = @max(height, row_height);
                if (n.tag == .function) {
                    const result = self.closedHeight(n.b);
                    if (result == 0) return 0;
                    height = @max(height, result);
                }
            },
            .scoped, .array, .list, .cursor, .resolver => {
                if (n.tag == .scoped and n.b == 0) return 0;
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
            .projection => return 0,
            .nominal, .instance_selection => for (self.nominalArguments(n)) |child| {
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
        std.debug.assert(tag == .array or tag == .list or tag == .cursor);
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
    /// A concrete instance names a lexical scope; unit0 with nonzero decl
    /// names an owned identity-variable type edge. Dynamic authority is created
    /// only by scope execution, never by a solver binder.
    pub fn scoped(self: *Store, descriptor: Id, instance: NominalIdentity) Error!Id {
        return self.add(.{ .tag = .scoped, .a = descriptor, .b = instance.unit, .c = instance.decl });
    }
    pub fn capabilityParameter(self: *Store, descriptor: Id) Error!Id {
        return self.scoped(descriptor, .{ .unit = 0, .decl = try self.fresh() });
    }
    fn resolveInstance(self: *Store, instance: NominalIdentity, at: Cursor, depth: usize) Error!NominalIdentity {
        if (instance.unit != 0 or instance.decl == 0) return instance;
        const bound = try self.resolveDepth(instance.decl, at, depth + 1);
        const value = self.node(bound);
        if (value.tag == .variable or value.tag == .instance_selection) return .{ .unit = 0, .decl = bound };
        if (value.tag != .scoped) return error.TypeMismatch;
        return .{ .unit = value.b, .decl = value.c };
    }
    pub fn instanceSelection(self: *Store, identity: NominalIdentity, arguments: []const Id) Error!Id {
        if (identity.unit == 0 or identity.decl == 0 or arguments.len != 2) return error.TypeMismatch;
        for (arguments) |argument| if (argument >= self.nodes.items.len or self.node(argument).tag != .scoped) return error.TypeMismatch;
        if (self.nodes.items.len > 65_536) return error.TypeLimit;
        for (self.nodes.items, 0..) |value, index| {
            if (value.tag != .instance_selection or value.a != identity.unit or value.b != identity.decl) continue;
            const choices = self.nominalArguments(value);
            // Payload writes do not create a new value identity. Each origin
            // retains its descriptor separately from its exact owner term.
            var same = true;
            for (choices, arguments) |choice, argument| {
                const old = self.node(choice);
                const next = self.node(argument);
                same = same and old.b == next.b and old.c == next.c;
            }
            if (same) return @intCast(index);
        }
        return self.nominalLike(.instance_selection, identity, arguments);
    }
    pub fn nominal(self: *Store, identity: NominalIdentity, arguments: []const Id) Error!Id {
        return self.nominalLike(.nominal, identity, arguments);
    }
    fn nominalLike(self: *Store, tag: Tag, identity: NominalIdentity, arguments: []const Id) Error!Id {
        if (arguments.len >= std.math.maxInt(u32) or self.extra.items.len > std.math.maxInt(u32) - arguments.len - 1) return error.TypeLimit;
        const owned = try self.allocator.dupe(Id, arguments);
        defer self.allocator.free(owned);
        const start: u32 = @intCast(self.extra.items.len);
        try self.extra.ensureUnusedCapacity(self.allocator, owned.len + 1);
        self.extra.appendAssumeCapacity(@intCast(owned.len));
        self.extra.appendSliceAssumeCapacity(owned);
        return self.add(.{ .tag = tag, .a = identity.unit, .b = identity.decl, .c = start });
    }
    /// Symbolic associated output. The tail word is the original member name;
    /// arguments use the ordinary owned span so substitution shares the graph.
    pub fn chargeProjection(self: *Store) Error!void {
        if (self.projection_steps >= self.projection_limit) {
            self.projection_exhausted = true;
            return error.TypeLimit;
        }
        self.projection_steps += 1;
    }
    pub fn projection(self: *Store, identity: NominalIdentity, member: u32, arguments: []const Id) Error!Id {
        self.has_projections = true;
        const id = try self.nominal(identity, arguments);
        try self.extra.append(self.allocator, member);
        self.nodes.items[id].tag = .projection;
        self.nodes.items[id].closed_height = 0;
        return id;
    }
    pub fn projectionMember(self: *const Store, value: Node) u32 {
        std.debug.assert(value.tag == .projection);
        return self.extra.items[value.c + 1 + self.extra.items[value.c]];
    }
    pub fn nominalArguments(self: *const Store, value: Node) []const Id {
        std.debug.assert(value.tag == .nominal or value.tag == .projection or value.tag == .instance_selection);
        return self.extra.items[value.c + 1 ..][0..self.extra.items[value.c]];
    }
    pub fn recordField(self: *const Store, value: Node, index: usize) Field {
        std.debug.assert(value.tag == .record and index < value.b);
        return .{ .name = self.extra.items[value.a + index * 2], .ty = self.extra.items[value.a + index * 2 + 1] };
    }
    /// A deferred shape equation. Right fields replace left fields, including
    /// their types; the remaining left fields keep their identities.
    pub fn mergeRecords(self: *Store, left: Id, right: Id) Error!?Id {
        const a = self.node(self.head(left, 0));
        const b = self.node(self.head(right, 0));
        if (a.tag == .never or b.tag == .never) return never;
        if ((a.tag != .record and a.tag != .variable) or (b.tag != .record and b.tag != .variable)) return error.TypeMismatch;
        if (a.tag == .variable or b.tag == .variable) return null;
        if (a.b == 0) return right;
        if (b.b == 0) return left;
        var buffer: [1024]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&buffer, self.allocator);
        const allocator = scratch.allocator();
        var fields: std.ArrayList(Field) = .empty;
        defer fields.deinit(allocator);
        var slots: std.AutoHashMapUnmanaged(u32, usize) = .empty;
        defer slots.deinit(allocator);
        for ([_]Node{ a, b }) |shape| for (0..shape.b) |index| {
            const field = self.recordField(shape, index);
            const slot = try slots.getOrPut(allocator, field.name);
            if (slot.found_existing) fields.items[slot.value_ptr.*] = field else {
                slot.value_ptr.* = fields.items.len;
                try fields.append(allocator, field);
            }
        };
        return try self.record(fields.items);
    }
    pub fn cursor(self: *const Store) Cursor {
        return self.effects.next_position;
    }
    pub fn mark(self: *const Store) Mark {
        return .{ .nodes = self.nodes.items.len, .extra = self.extra.items.len, .variables = self.variables.items.len, .versions = self.versions.items.len, .operations = self.operations.items.len, .effects = self.effects.mark() };
    }
    pub fn rollback(self: *Store, point: Mark) void {
        if (self.associated_equations.count() != 0) {
            var entries = self.associated_equations.iterator();
            while (entries.next()) |entry| {
                if (entry.key_ptr.* >= point.nodes or entry.value_ptr.* >= point.nodes) _ = self.associated_equations.remove(entry.key_ptr.*);
            }
        }
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
        // The type generation was already revoked above. A later row read
        // must not announce this same rollback as another physical change.
        self.closed_effect_physical_epoch = self.effects.physical_epoch;
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
    /// The caller supplies a complete selected proof. Both roots belong to this
    /// solver; freezing resolves the equation and retains no mutable lookup.
    pub fn bindAssociated(self: *Store, projection_: Id, result: Id) Error!void {
        try self.chargeProjection();
        if (self.node(projection_).tag != .projection) return error.TypeMismatch;
        try self.associated_equations.put(self.allocator, projection_, result);
        self.mutation_epoch +|= 1;
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
        if (self.associated_equations.count() != 0) {
            if (self.associated_equations.get(id)) |equation| id = equation;
        }
        const value = self.node(id);
        return if (value.tag == .variable) self.variable_views.get((@as(u64, value.a) << 32) | position) orelse id else id;
    }
    fn compositeWindow(self: *Store, root: Id, at: Cursor) Error!Id {
        const enabled = self.use_composite_cache and
            resolution_cache.stamp(self.mutation_epoch) != null and resolution_cache.stamp(self.effects.mutation_epoch) != null;
        if (enabled and self.composites.entries.len != 0 and self.composites.activate(self.closed_generation, self.effects.physical_epoch)) if (self.composites.get(root, at)) |certificate| {
            if (self.validResolution(certificate)) return certificate.result;
        };
        const before_nodes = self.nodes.items.len;
        const result = try self.resolveDepth(root, at, 0);
        // An unchanged query cannot acquire fresh retained storage. Existing
        // slots may retain its frontier without any additional allocation.
        if (enabled and (result != root or self.composites.entries.len != 0) and self.nodes.items.len - before_nodes >= self.composite_min_growth and self.composites.activate(self.closed_generation, self.effects.physical_epoch)) {
            if (self.resolutionDependencies(result)) |certificate| try self.composites.put(self.allocator, root, at, certificate);
        }
        return result;
    }
    fn validResolution(self: *const Store, certificate: *const composite_cache.Record) bool {
        if (certificate.future_clock) |clock| if (clock != self.cursor()) return false;
        for (certificate.dependencies[0..certificate.count]) |dependency| {
            const last = if (dependency.effect) self.effects.variables.items[dependency.variable].last else self.variables.items[dependency.variable].last;
            if (last != dependency.last) return false;
        }
        return true;
    }
    fn resolutionDependencies(self: *const Store, result: Id) ?composite_cache.Record {
        var certificate: composite_cache.Record = .{ .result = result };
        var pending: [128]Id = undefined;
        pending[0] = result;
        var count: usize = 1;
        var budget: usize = 256;
        while (count != 0) {
            count -= 1;
            const id = pending[count];
            if (self.closedHeight(id) != 0 or id <= never) continue;
            if (budget == 0) return null;
            budget -= 1;
            const n = self.node(id);
            if (n.tag == .variable) {
                const variable = self.variables.items[n.a];
                if (!certificate.add(.{ .variable = n.a, .last = variable.last })) return null;
                if (variable.first == none and n.b > self.cursor()) certificate.future_clock = self.cursor();
                continue;
            }
            if (n.tag == .function or n.tag == .demand or n.tag == .provider) {
                const row_ = self.row(n.c);
                for (self.rowLabels(n.c)) |label| {
                    const arguments = self.operationArguments(label);
                    if (arguments.len > pending.len - count) return null;
                    @memcpy(pending[count..][0..arguments.len], arguments);
                    count += arguments.len;
                    const instance = self.operation(label).instance;
                    if (instance.unit == 0 and instance.decl != 0) {
                        if (count == pending.len) return null;
                        pending[count] = instance.decl;
                        count += 1;
                    }
                }
                if (row_.tail == .variable and !certificate.add(.{ .variable = row_.tail.variable, .last = self.effects.variables.items[row_.tail.variable].last, .effect = true })) return null;
            }
            var children: [3]Id = undefined;
            const tail: []const Id = switch (n.tag) {
                .function => blk: {
                    children = .{ n.a, n.b, 0 };
                    break :blk children[0..2];
                },
                .scoped => blk: {
                    children = .{ n.a, n.c, 0 };
                    if (n.b == 0) break :blk children[0..2];
                    break :blk children[0..1];
                },
                .array, .list, .cursor, .resolver, .demand, .provider => blk: {
                    children[0] = n.a;
                    break :blk children[0..1];
                },
                .state_provider => blk: {
                    children = .{ n.a, n.b, n.c };
                    break :blk &children;
                },
                .product => self.list(.{ .start = n.a, .len = n.b }),
                .nominal, .projection, .instance_selection => self.nominalArguments(n),
                .record => blk: {
                    if (n.b > pending.len - count) return null;
                    for (0..n.b) |i| pending[count + i] = self.recordField(n, i).ty;
                    count += n.b;
                    break :blk &.{};
                },
                else => &.{},
            };
            if (tail.len > pending.len - count) return null;
            @memcpy(pending[count..][0..tail.len], tail);
            count += tail.len;
        }
        return certificate;
    }
    pub fn resolve(self: *Store, root: Id, at: Cursor) Error!Id {
        if (self.use_closed_graphs) {
            self.synchronizeClosedGraphs();
            // A certified raw graph has no cursor-dependent children or tails.
            if (self.closedHeight(root) != 0) return root;
            const raw = self.node(root);
            if (self.use_resolution_cache and at == 0 and raw.tag == .variable and raw.b == 0 and raw.c != 0 and raw.closed_generation == self.closed_generation and self.closed_generation != std.math.maxInt(u16) and self.effects.physical_epoch != std.math.maxInt(u64)) {
                const remaining = self.node(raw.c);
                if (self.closedHeight(raw.c) != 0) return raw.c;
                if (remaining.tag == .variable) {
                    const last = self.variables.items[remaining.a].last;
                    if (last == none) {
                        // Once the clock reaches an unwritten future view,
                        // variableView canonicalizes it to the principal ID.
                        if (remaining.b == 0 or remaining.b > self.cursor()) return raw.c;
                    } else if (self.versions.items[last].position < remaining.b) return raw.c;
                }
            }
        }
        if (!self.use_resolution_cache or root <= never) return self.resolveDepth(root, at, 0);
        if (at != 0) return self.compositeWindow(root, at);
        const mutation = resolution_cache.stamp(self.mutation_epoch) orelse return self.resolveDepth(root, at, 0);
        const effects = resolution_cache.stamp(self.effects.mutation_epoch) orelse return self.resolveDepth(root, at, 0);
        if (!self.resolved.activate(mutation, effects)) return self.resolveDepth(root, at, 0);
        if (self.resolved.get(root)) |result| return result;
        // Current-epoch hits are already complete and cheaper than validating
        // a frontier. Consult cross-epoch certificates only on an epoch miss.
        // An empty table cannot answer a query. Defer physical certificate
        // checks until lookup or a costly normalization can use them.
        const composite = self.use_composite_cache;
        if (composite and self.composites.entries.len != 0 and self.composites.activate(self.closed_generation, self.effects.physical_epoch)) if (self.composites.get(root, at)) |certificate| {
            if (self.validResolution(certificate)) {
                const result = certificate.result;
                if (result != root or root < self.resolved.high_water) try self.resolved.put(self.allocator, root, result);
                return result;
            }
        };
        const before_nodes = self.nodes.items.len;
        const result = try self.resolveDepth(root, at, 0);
        if (self.use_closed_graphs and self.closed_generation != std.math.maxInt(u16) and self.effects.physical_epoch != std.math.maxInt(u64) and (self.closedHeight(result) != 0 or self.node(result).tag == .variable) and self.node(root).tag == .variable and self.node(root).b == 0) {
            // Closed answers survive appended writes. An open answer watches
            // only its remaining chronological variable. Physical edits,
            // rollback and saturated certificates revoke either proof.
            self.nodes.items[root].c = result;
            self.nodes.items[root].closed_generation = self.closed_generation;
            return result;
        }
        // An unchanged query must not acquire fresh retained storage.
        if (result == root and root >= self.resolved.high_water) return result;
        try self.resolved.put(self.allocator, root, result);
        if (composite and self.nodes.items.len - before_nodes >= self.composite_min_growth and self.composites.activate(self.closed_generation, self.effects.physical_epoch)) if (self.resolutionDependencies(result)) |certificate| try self.composites.put(self.allocator, root, at, certificate);
        return result;
    }
    fn resolveDepth(self: *Store, root: Id, at: Cursor, depth: usize) Error!Id {
        // Associated equations produce shared open DAGs. Keep exact recursive
        // results in the same epoch as the root query; legacy stores retain
        // their ordinary path and allocation policy.
        if (self.has_projections and self.use_resolution_cache and depth != 0 and root > never) {
            if (self.mutation_epoch == std.math.maxInt(u64) or self.effects.mutation_epoch == std.math.maxInt(u64)) return self.resolveNode(root, at, depth);
            if (self.projection_resolution_types != self.mutation_epoch or self.projection_resolution_rows != self.effects.mutation_epoch) {
                self.projection_resolutions.clearRetainingCapacity();
                self.projection_resolution_types = self.mutation_epoch;
                self.projection_resolution_rows = self.effects.mutation_epoch;
            }
            try self.chargeProjection();
            const key: ProjectionResolution = .{ .root = root, .at = at, .depth = @as(u32, @intCast(depth)) };
            if (self.projection_resolutions.get(key)) |result| return result;
            const result = try self.resolveNode(root, at, depth);
            if (self.projection_resolutions.count() < 65_536) try self.projection_resolutions.put(self.allocator, key, result);
            return result;
        }
        return self.resolveNode(root, at, depth);
    }
    fn resolveNode(self: *Store, root: Id, at: Cursor, depth: usize) Error!Id {
        if (self.associated_equations.count() != 0) {
            if (self.associated_equations.get(root)) |equation| return self.resolveDepth(equation, at, depth + 1);
        }
        if (self.has_projections) try self.chargeProjection();
        if (@import("builtin").is_test) self.resolution_steps += 1;
        if (depth >= self.resolution_depth_limit) return error.TypeLimit;
        const height = self.closedHeight(root);
        if (height != 0) {
            if (depth + height > self.resolution_depth_limit) return error.TypeLimit;
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
                if (depth + selected_height > self.resolution_depth_limit) return error.TypeLimit;
                return id;
            }
        }
        const value = self.node(id);
        defer if (self.use_closed_graphs and value.tag != .variable and self.closed_generation != std.math.maxInt(u16)) {
            // Rollback revokes structural certificates. An ordinary traversal
            // can prove an unchanged graph closed again, from its leaves up.
            const refreshed = self.closedNodeHeight(value);
            if (refreshed != 0) {
                self.nodes.items[id].closed_height = refreshed;
                self.nodes.items[id].closed_generation = self.closed_generation;
            }
        };
        switch (value.tag) {
            .scoped => {
                const child = try self.resolveDepth(value.a, position, depth + 1);
                const instance = try self.resolveInstance(.{ .unit = value.b, .decl = value.c }, position, depth + 1);
                if (child == value.a and instance.unit == value.b and instance.decl == value.c) return id;
                return self.scoped(child, instance);
            },
            .variable => return self.variableView(value.a, position),
            .function => {
                const parameter = try self.resolveDepth(value.a, position, depth + 1);
                const result = try self.resolveDepth(value.b, position, depth + 1);
                const effect_row = try self.resolveOperationRow(value.c, position, depth + 1);
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
            .array, .list, .cursor, .resolver => {
                const child = try self.resolveDepth(value.a, position, depth + 1);
                return if (child == value.a) id else if (value.tag == .resolver) self.resolver(child) else self.sequence(value.tag, child);
            },
            .demand, .provider => {
                const child = try self.resolveDepth(value.a, position, depth + 1);
                const effect_row = try self.resolveOperationRow(value.c, position, depth + 1);
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
            .nominal, .projection, .instance_selection => {
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
                if (!changed) return id;
                if (value.tag == .projection) return self.projection(.{ .unit = value.a, .decl = value.b }, self.projectionMember(value), args.items);
                if (value.tag == .instance_selection) return self.instanceSelection(.{ .unit = value.a, .decl = value.b }, args.items);
                return self.nominal(.{ .unit = value.a, .decl = value.b }, args.items);
            },
            else => return id,
        }
    }
    fn occurs(self: *Store, variable: u32, root: Id) Error!bool {
        const resolved_root = try self.resolve(root, 0);
        if (self.closedHeight(resolved_root) != 0 or resolved_root <= never) {
            self.occurs_steps += 1;
            return false;
        }
        const prior_length = self.occurs_seen.items.len;
        if (prior_length < self.nodes.items.len) {
            try self.occurs_seen.resize(self.allocator, self.nodes.items.len);
            @memset(self.occurs_seen.items[prior_length..], 0);
        }
        self.occurs_generation +%= 1;
        if (self.occurs_generation == 0) {
            @memset(self.occurs_seen.items, 0);
            self.occurs_generation = 1;
        }
        var scratch_buffer: [512]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const scratch_allocator = scratch.allocator();
        var pending: std.ArrayList(Id) = .empty;
        defer pending.deinit(scratch_allocator);
        try pending.append(scratch_allocator, resolved_root);
        var budget: usize = 1_000_000;
        while (pending.pop()) |id| {
            if (self.occurs_seen.items[id] == self.occurs_generation) continue;
            self.occurs_seen.items[id] = self.occurs_generation;
            if (budget == 0) return error.TypeLimit;
            budget -= 1;
            self.occurs_steps += 1;
            if (self.closedHeight(id) != 0) continue;
            const value = self.node(id);
            if (value.tag == .function or value.tag == .demand or value.tag == .provider)
                for (self.rowLabels(value.c)) |label| {
                    try pending.appendSlice(scratch_allocator, self.operationArguments(label));
                    const instance = self.operation(label).instance;
                    if (instance.unit == 0 and instance.decl != 0) try pending.append(scratch_allocator, instance.decl);
                };
            switch (value.tag) {
                .variable => if (value.a == variable) return true,
                .function => try pending.appendSlice(scratch_allocator, &.{ value.a, value.b }),
                .product => try pending.appendSlice(scratch_allocator, self.list(.{ .start = value.a, .len = value.b })),
                .scoped => {
                    try pending.append(scratch_allocator, value.a);
                    if (value.b == 0) try pending.append(scratch_allocator, value.c);
                },
                .array, .list, .cursor, .demand, .resolver, .provider => try pending.append(scratch_allocator, value.a),
                .state_provider => try pending.appendSlice(scratch_allocator, &.{ value.a, value.b, value.c }),
                .record => for (0..value.b) |i| {
                    try pending.append(scratch_allocator, self.recordField(value, i).ty);
                },
                .nominal, .projection, .instance_selection => try pending.appendSlice(scratch_allocator, self.nominalArguments(value)),
                else => {},
            }
        }
        return false;
    }
    pub fn unifyEffects(self: *Store, left: Effects.Id, right: Effects.Id) Error!void {
        const point = self.mark();
        errdefer self.rollback(point);
        const a = try self.resolveEffects(left, 0);
        const b = try self.resolveEffects(right, 0);
        var symbolic = false;
        for (self.rowLabels(a)) |label| symbolic = symbolic or try self.symbolicOperation(label);
        for (self.rowLabels(b)) |label| symbolic = symbolic or try self.symbolicOperation(label);
        if (!symbolic) {
            self.effects.unify(a, b) catch |err| return effectError(err);
            return;
        }
        const labels = try self.allocator.dupe(Effects.Label, self.rowLabels(a));
        defer self.allocator.free(labels);
        const candidates = try self.allocator.dupe(Effects.Label, self.rowLabels(b));
        defer self.allocator.free(candidates);
        for (labels) |label| {
            var exact = false;
            for (candidates) |candidate| exact = exact or candidate == label;
            if (exact) continue;
            const operation_ = self.operation(label);
            var selected: ?Effects.Label = null;
            for (candidates) |candidate| {
                const other = self.operation(candidate);
                if (!std.meta.eql(operation_.identity, other.identity) or !std.meta.eql(operation_.instance, other.instance) or operation_.arguments.len != other.arguments.len) continue;
                const trial = self.mark();
                const matched = self.unifyOperationArguments(label, candidate) catch |err| {
                    self.rollback(trial);
                    if (err == error.OutOfMemory or err == error.TypeLimit) return err;
                    continue;
                };
                self.rollback(trial);
                if (!matched) continue;
                if (selected) |previous| {
                    if (previous != candidate) return error.EffectMismatch;
                } else selected = candidate;
            }
            if (selected) |candidate| _ = try self.unifyOperationArguments(label, candidate);
        }
        self.effects.unify(try self.resolveEffects(a, 0), try self.resolveEffects(b, 0)) catch |err| return effectError(err);
    }
    fn symbolicOperation(self: *const Store, label: Effects.Label) Error!bool {
        for (self.operationArguments(label)) |argument| {
            if (self.closedHeight(argument) != 0) continue;
            if (!try self.equalClosed(argument, argument)) return true;
        }
        return false;
    }
    fn unifyOperationArguments(self: *Store, left: Effects.Label, right: Effects.Label) Error!bool {
        if (!try self.symbolicOperation(left) and !try self.symbolicOperation(right)) return false;
        const a = try self.allocator.dupe(Id, self.operationArguments(left));
        defer self.allocator.free(a);
        const b = try self.allocator.dupe(Id, self.operationArguments(right));
        defer self.allocator.free(b);
        for (a, b) |first, second| try self.unify(first, second);
        return true;
    }
    pub fn freshEffects(self: *Store) Error!Effects.Id {
        return self.effects.fresh() catch |err| return effectError(err);
    }
    pub fn resolveEffects(self: *Store, effect_row: Effects.Id, at: Cursor) Error!Effects.Id {
        if (self.use_closed_graphs) self.synchronizeClosedGraphs();
        return self.resolveOperationRow(effect_row, at, 0);
    }
    fn resolveOperationRow(self: *Store, root: Effects.Id, at: Cursor, depth: usize) Error!Effects.Id {
        if (depth >= 1024) return error.TypeLimit;
        const id = self.effects.resolve(root, at) catch |err| return effectError(err);
        const row_ = self.row(id);
        var labels: std.ArrayList(Effects.Label) = .empty;
        defer labels.deinit(self.allocator);
        var changed = false;
        for (0..row_.labels.len) |index| {
            const label = self.effects.list(row_.labels)[index];
            const operation_ = self.operation(label);
            var closed = operation_.instance.unit != 0 or operation_.instance.decl == 0;
            for (self.list(operation_.arguments)) |argument| {
                const height = self.closedHeight(argument);
                if (height == 0) closed = false;
                if (height != 0 and depth + 1 + height > self.resolution_depth_limit) return error.TypeLimit;
            }
            if (closed) {
                if (changed) labels.appendAssumeCapacity(label);
                continue;
            }
            var arguments: std.ArrayList(Id) = .empty;
            defer arguments.deinit(self.allocator);
            var argument_changed = false;
            for (0..operation_.arguments.len) |offset| {
                const argument = self.list(operation_.arguments)[offset];
                const resolved = try self.resolveDepth(argument, at, depth + 1);
                if (!argument_changed and resolved != argument) {
                    try arguments.ensureTotalCapacity(self.allocator, operation_.arguments.len);
                    arguments.appendSliceAssumeCapacity(self.list(operation_.arguments)[0..offset]);
                    argument_changed = true;
                }
                if (argument_changed) arguments.appendAssumeCapacity(resolved);
            }
            const instance = try self.resolveInstance(operation_.instance, at, depth + 1);
            var next = label;
            if (argument_changed or !std.meta.eql(instance, operation_.instance)) next = try self.internResolvedOperation(operation_.identity, instance, if (argument_changed) arguments.items else self.list(operation_.arguments), true);
            if (!changed and next != label) {
                try labels.ensureTotalCapacity(self.allocator, row_.labels.len);
                labels.appendSliceAssumeCapacity(self.effects.list(row_.labels)[0..index]);
                changed = true;
            }
            if (changed) labels.appendAssumeCapacity(next);
        }
        if (!changed) return id;
        return self.effects.rowAt(labels.items, row_.tail, row_.cursor) catch |err| return effectError(err);
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
    /// Closed operation identity; executable evidence must use this boundary.
    pub fn internOperation(self: *Store, identity: NominalIdentity, arguments: []const Id) Error!Effects.Label {
        return self.internOperationMode(identity, .{ .unit = 0, .decl = 0 }, arguments, false);
    }
    /// Principal operation identity. Symbolic arguments belong to this solver
    /// and must be substituted or copied with their enclosing scheme.
    pub fn internSymbolicOperation(self: *Store, identity: NominalIdentity, arguments: []const Id) Error!Effects.Label {
        return self.internOperationMode(identity, .{ .unit = 0, .decl = 0 }, arguments, true);
    }
    pub fn internScopedOperation(self: *Store, identity: NominalIdentity, instance: NominalIdentity, arguments: []const Id) Error!Effects.Label {
        if (identity.unit == 0 and identity.decl == 1 and (instance.unit != 0 or instance.decl != 0)) return error.TypeMismatch;
        return self.internOperationMode(identity, try self.resolveInstance(instance, 0, 0), arguments, true);
    }
    fn internOperationMode(self: *Store, identity: NominalIdentity, instance: NominalIdentity, arguments: []const Id, symbolic: bool) Error!Effects.Label {
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
            if (!symbolic and !try self.equalClosed(ty, ty)) return error.TypeMismatch;
            try resolved.append(scratch_allocator, ty);
        }
        return self.internResolvedOperation(identity, instance, resolved.items, symbolic);
    }
    fn internResolvedOperation(self: *Store, identity: NominalIdentity, instance: NominalIdentity, resolved: []const Id, symbolic: bool) Error!Effects.Label {
        const point = self.mark();
        errdefer self.rollback(point);
        for (self.operations.items[1..], 1..) |candidate, index| {
            if (!std.meta.eql(identity, candidate.identity) or !std.meta.eql(instance, candidate.instance)) continue;
            const old = self.list(candidate.arguments);
            if (old.len != resolved.len) continue;
            var same = true;
            for (old, resolved) |a, b| same = same and try self.equalGraph(a, b, symbolic);
            if (same) return @intCast(index);
        }
        if (self.operations.items.len == none) return error.TypeLimit;
        const span = try self.saveList(resolved);
        const id: Effects.Label = @intCast(self.operations.items.len);
        try self.operations.append(self.allocator, .{ .identity = identity, .arguments = span, .instance = instance });
        return id;
    }
    /// Read-only exact comparison. A variable or open latent row is not closed,
    /// even when the two source IDs happen to be identical.
    pub fn equalClosed(self: *const Store, left: Id, right: Id) Error!bool {
        return self.equalGraph(left, right, false);
    }
    pub fn equalSymbolic(self: *const Store, left: Id, right: Id) Error!bool {
        return self.equalGraph(left, right, true);
    }
    fn equalGraph(self: *const Store, left: Id, right: Id, symbolic: bool) Error!bool {
        var scratch_buffer: [512]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const scratch_allocator = scratch.allocator();
        const Pair = struct { a: Id, b: Id };
        var pending: std.ArrayList(Pair) = .empty;
        defer pending.deinit(scratch_allocator);
        try pending.append(scratch_allocator, .{ .a = left, .b = right });
        var seen: std.AutoHashMapUnmanaged(Pair, void) = .empty;
        defer seen.deinit(scratch_allocator);
        var budget: usize = 1_000_000;
        while (pending.pop()) |pair| {
            if (self.has_projections) try @constCast(self).chargeProjection();
            if (symbolic) {
                if (pair.a == pair.b) continue;
            }
            // Closed equality must inspect each leaf even for identical roots.
            // Associated selections can share exponentially many paths to that
            // leaf, so visit each pair once without treating identity as proof.
            if (symbolic or self.has_projections) {
                const entry = try seen.getOrPut(scratch_allocator, pair);
                if (entry.found_existing) continue;
            }
            if (budget == 0) return error.TypeLimit;
            budget -= 1;
            const a = self.node(pair.a);
            const b = self.node(pair.b);
            if (a.tag != b.tag) return false;
            switch (a.tag) {
                .absent => return false,
                .variable => {
                    if (!symbolic or a.a != b.a or a.b != b.b) return false;
                },
                .function, .demand, .provider => {
                    const ar = self.effects.node(a.c);
                    const br = self.effects.node(b.c);
                    if (symbolic) {
                        if (!std.meta.eql(ar.tail, br.tail) or ar.cursor != br.cursor) return false;
                    } else if (ar.tail != .closed or br.tail != .closed) return false;
                    if (ar.labels.len != br.labels.len) return false;
                    for (self.effects.list(ar.labels)) |label| {
                        var ac: usize = 0;
                        var bc: usize = 0;
                        for (self.effects.list(ar.labels)) |v| ac += @intFromBool(v == label);
                        for (self.effects.list(br.labels)) |v| bc += @intFromBool(v == label);
                        if (ac != bc) return false;
                        for (self.operationArguments(label)) |argument| try pending.append(scratch_allocator, .{ .a = argument, .b = argument });
                        const instance = self.operation(label).instance;
                        if (instance.unit == 0 and instance.decl != 0) try pending.append(scratch_allocator, .{ .a = instance.decl, .b = instance.decl });
                    }
                    if (a.tag == .function) try pending.append(scratch_allocator, .{ .a = a.b, .b = b.b });
                    try pending.append(scratch_allocator, .{ .a = a.a, .b = b.a });
                },
                .array, .list, .cursor, .resolver => try pending.append(scratch_allocator, .{ .a = a.a, .b = b.a }),
                .state_provider => try pending.appendSlice(scratch_allocator, &.{ .{ .a = a.a, .b = b.a }, .{ .a = a.b, .b = b.b }, .{ .a = a.c, .b = b.c } }),
                .scoped => {
                    if (a.b != b.b or a.c != b.c) return false;
                    if (a.b == 0) try pending.append(scratch_allocator, .{ .a = a.c, .b = b.c });
                    try pending.append(scratch_allocator, .{ .a = a.a, .b = b.a });
                },
                .type_constructor => if (a.a != b.a or a.b != b.b) return false,
                .product => {
                    if (a.b != b.b) return false;
                    for (self.list(.{ .start = a.a, .len = a.b }), self.list(.{ .start = b.a, .len = b.b })) |av, bv| try pending.append(scratch_allocator, .{ .a = av, .b = bv });
                },
                .nominal, .projection, .instance_selection => {
                    if (a.a != b.a or a.b != b.b) return false;
                    if (a.tag == .projection and self.projectionMember(a) != self.projectionMember(b)) return false;
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
        return self.unifyMode(left, right, reporter, false);
    }
    pub fn unifyPattern(self: *Store, left: Id, right: Id) Error!void {
        return self.unifyMode(left, right, null, true);
    }
    fn unifyMode(self: *Store, left: Id, right: Id, reporter: ?MismatchReporter, comptime associated: bool) Error!void {
        var scratch_buffer: [512]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const scratch_allocator = scratch.allocator();
        const point = self.mark();
        errdefer self.rollback(point);
        const Pair = struct { a: Id, b: Id, effect_row: bool = false };
        var seen: std.AutoHashMapUnmanaged(Pair, void) = .empty;
        defer seen.deinit(scratch_allocator);
        var pending: std.ArrayList(Pair) = .empty;
        defer pending.deinit(scratch_allocator);
        try pending.append(scratch_allocator, .{ .a = left, .b = right });
        const bounded = associated or self.has_projections;
        while (pending.pop()) |pair| {
            if (bounded) try self.chargeProjection();
            if (pair.effect_row) {
                if (bounded) {
                    for (self.rowLabels(pair.a)) |_| try self.chargeProjection();
                    for (self.rowLabels(pair.b)) |_| try self.chargeProjection();
                }
                try self.unifyEffects(pair.a, pair.b);
                continue;
            }
            const a = try self.resolve(pair.a, 0);
            const b = try self.resolve(pair.b, 0);
            if (a == b or a == never or b == never) continue;
            if (bounded) {
                const found = try seen.getOrPut(scratch_allocator, .{ .a = a, .b = b });
                if (found.found_existing) continue;
            }
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
                .array, .list, .cursor, .resolver => try pending.append(scratch_allocator, .{ .a = an.a, .b = bn.a }),
                .demand, .provider => {
                    try pending.append(scratch_allocator, .{ .a = an.c, .b = bn.c, .effect_row = true });
                    try pending.append(scratch_allocator, .{ .a = an.a, .b = bn.a });
                },
                .state_provider => {
                    try pending.append(scratch_allocator, .{ .a = an.c, .b = bn.c });
                    try pending.append(scratch_allocator, .{ .a = an.b, .b = bn.b });
                    try pending.append(scratch_allocator, .{ .a = an.a, .b = bn.a });
                },
                .scoped => {
                    if (an.b == 0 and self.node(an.c).tag == .variable) {
                        if (bn.b != 0 or an.c != bn.c) try pending.append(scratch_allocator, .{ .a = an.c, .b = b });
                    } else if (bn.b == 0 and self.node(bn.c).tag == .variable) {
                        try pending.append(scratch_allocator, .{ .a = bn.c, .b = a });
                    } else if (an.b == 0 and bn.b == 0) {
                        try pending.append(scratch_allocator, .{ .a = an.c, .b = bn.c });
                    } else if (an.b != bn.b or an.c != bn.c) return self.mismatch(reporter, a, b);
                    try pending.append(scratch_allocator, .{ .a = an.a, .b = bn.a });
                },
                .type_constructor => if (an.a != bn.a or an.b != bn.b) return self.mismatch(reporter, a, b),
                .projection => {
                    if (an.a != bn.a or an.b != bn.b or self.projectionMember(an) != self.projectionMember(bn)) return self.mismatch(reporter, a, b);
                    const aa = self.nominalArguments(an);
                    const bb = self.nominalArguments(bn);
                    if (aa.len != bb.len) return self.mismatch(reporter, a, b);
                    for (aa, bb) |left_arg, right_arg| {
                        const al = try self.resolve(left_arg, 0);
                        const bl = try self.resolve(right_arg, 0);
                        if (al == bl) continue;
                        if (!try self.equalSymbolic(al, bl)) return self.mismatch(reporter, a, b);
                    }
                },
                .nominal, .instance_selection => {
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
            if (self.has_projections) try self.chargeProjection();
            if (bounded and self.closedHeight(id) != 0) continue;
            const entry = try seen.getOrPut(temporary, id);
            if (entry.found_existing) continue;
            const value = self.node(id);
            if (value.tag == .function or value.tag == .demand or value.tag == .provider)
                for (self.rowLabels(value.c)) |label| {
                    try pending.appendSlice(temporary, self.operationArguments(label));
                    const instance = self.operation(label).instance;
                    if (instance.unit == 0 and instance.decl != 0) try pending.append(temporary, instance.decl);
                };
            switch (value.tag) {
                .variable => try values.append(self.allocator, id),
                .function => try pending.appendSlice(temporary, &.{ value.a, value.b }),
                .product => try pending.appendSlice(temporary, self.list(.{ .start = value.a, .len = value.b })),
                .scoped => {
                    try pending.append(temporary, value.a);
                    if (value.b == 0) try pending.append(temporary, value.c);
                },
                .array, .list, .cursor, .demand, .resolver, .provider => try pending.append(temporary, value.a),
                .state_provider => try pending.appendSlice(temporary, &.{ value.a, value.b, value.c }),
                .record => for (0..value.b) |i| {
                    try pending.append(temporary, self.recordField(value, i).ty);
                },
                .nominal, .projection, .instance_selection => try pending.appendSlice(temporary, self.nominalArguments(value)),
                else => {},
            }
        }
        return values.toOwnedSlice(self.allocator);
    }
    pub fn containsProjection(self: *Store, root: Id) Error!bool {
        if (!self.has_projections or root == 0) return false;
        const Work = struct { root: Id, row: bool = false };
        var pending: std.ArrayList(Work) = .empty;
        defer pending.deinit(self.allocator);
        var seen: std.AutoHashMapUnmanaged(Work, void) = .empty;
        defer seen.deinit(self.allocator);
        try pending.append(self.allocator, .{ .root = root });
        var remaining: usize = 1_000_000;
        while (pending.pop()) |item| {
            if (self.has_projections) try self.chargeProjection();
            if (remaining == 0) return error.TypeLimit;
            remaining -= 1;
            const entry = try seen.getOrPut(self.allocator, item);
            if (entry.found_existing) continue;
            if (item.row) {
                for (self.rowLabels(item.root)) |label| for (self.operationArguments(label)) |argument| try pending.append(self.allocator, .{ .root = argument });
                continue;
            }
            const id = self.head(item.root, 0);
            if (self.closedHeight(id) != 0) continue;
            const n = self.node(id);
            switch (n.tag) {
                .projection => return true,
                .function => try pending.appendSlice(self.allocator, &.{ .{ .root = n.a }, .{ .root = n.b }, .{ .root = n.c, .row = true } }),
                .demand, .provider => try pending.appendSlice(self.allocator, &.{ .{ .root = n.a }, .{ .root = n.c, .row = true } }),
                .scoped, .array, .list, .cursor, .resolver => try pending.append(self.allocator, .{ .root = n.a }),
                .state_provider => for ([_]Id{ n.a, n.b, n.c }) |child| try pending.append(self.allocator, .{ .root = child }),
                .product => for (self.list(.{ .start = n.a, .len = n.b })) |child| try pending.append(self.allocator, .{ .root = child }),
                .record => for (0..n.b) |at| try pending.append(self.allocator, .{ .root = self.recordField(n, at).ty }),
                .nominal, .instance_selection => for (self.nominalArguments(n)) |child| try pending.append(self.allocator, .{ .root = child }),
                else => {},
            }
        }
        return false;
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
        var memo: CovariantMemo = .{};
        defer memo.deinit(self.allocator);
        return self.closeCovariantDepth(root, generalized, protected, null, &memo, 0);
    }
    /// The returned raw tail indices certify only the decisions made by the
    /// covariance rule. They do not mutate inference history or authorize
    /// closing any other unresolved row in a retained body.
    pub fn closeCovariantCertified(self: *Store, root: Id, generalized: []const u32, protected: []const u32) Error!ClosedCovariant {
        var decisions: std.ArrayList(u32) = .empty;
        defer decisions.deinit(self.allocator);
        var memo: CovariantMemo = .{};
        defer memo.deinit(self.allocator);
        const closed = try self.closeCovariantDepth(root, generalized, protected, &decisions, &memo, 0);
        return .{ .root = closed, .closed_rows = try self.saveList(decisions.items) };
    }
    const CovariantMemo = struct {
        entries: std.ArrayList(struct { root: Id, depth: usize, protected: []u32, result: Id }) = .empty,
        fn deinit(self: *CovariantMemo, allocator: std.mem.Allocator) void {
            for (self.entries.items) |entry| allocator.free(entry.protected);
            self.entries.deinit(allocator);
        }
    };
    fn closeCovariantDepth(self: *Store, root: Id, generalized: []const u32, protected: []const u32, decisions: ?*std.ArrayList(u32), memo: *CovariantMemo, depth: usize) Error!Id {
        if (self.has_projections) try self.chargeProjection();
        if (depth >= 1024) return error.TypeLimit;
        if (self.has_projections) {
            if (generalized.len == 0) return root;
            for (memo.entries.items) |entry| if (entry.root == root and entry.depth == depth and std.mem.eql(u32, entry.protected, protected)) return entry.result;
            const rows = try self.freeRowVariables(root);
            defer self.allocator.free(rows);
            const changes = for (rows) |row_id| {
                if (has(generalized, row_id) and !has(protected, row_id)) break true;
            } else false;
            if (!changes) return root;
        }
        const result = try self.closeCovariantNode(root, generalized, protected, decisions, memo, depth);
        if (self.has_projections and memo.entries.items.len < 65_536) {
            const owned = try self.allocator.dupe(u32, protected);
            errdefer self.allocator.free(owned);
            try memo.entries.append(self.allocator, .{ .root = root, .depth = depth, .protected = owned, .result = result });
        }
        return result;
    }
    fn closeCovariantNode(self: *Store, root: Id, generalized: []const u32, protected: []const u32, decisions: ?*std.ArrayList(u32), memo: *CovariantMemo, depth: usize) Error!Id {
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
                // These lists only answer membership. Copying the inherited set
                // needs no per-item search; deduplicating it was quadratic in
                // its size at every nested function.
                var nested: std.ArrayList(u32) = .empty;
                defer nested.deinit(self.allocator);
                try nested.appendSlice(self.allocator, protected);
                try self.unionInto(&nested, parameter_free);
                const closed_tail = self.effects.node(effect_row).tail;
                if (closed_tail == .variable) try self.unionInto(&nested, &.{closed_tail.variable});
                return self.functionWithEffects(value.a, try self.closeCovariantDepth(value.b, generalized, nested.items, decisions, memo, depth + 1), effect_row);
            },
            .product, .record => {
                var protected_siblings: std.ArrayList(u32) = .empty;
                defer protected_siblings.deinit(self.allocator);
                try protected_siblings.appendSlice(self.allocator, protected);
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
                    const child = try self.closeCovariantDepth(field.ty, generalized, protected_siblings.items, decisions, memo, depth + 1);
                    if (value.tag == .record) try fields.append(self.allocator, .{ .name = field.name, .ty = child }) else try children.append(self.allocator, child);
                }
                return if (value.tag == .record) self.record(fields.items) else self.product(children.items);
            },
            .array, .list, .cursor => return self.sequence(value.tag, try self.closeCovariantDepth(value.a, generalized, protected, decisions, memo, depth + 1)),
            // Nominal arguments and Demand's latent computation are invariant.
            else => return root,
        }
    }
    fn covariantInputs(self: *Store, root: Id, out: *std.ArrayList(u32), depth: usize) Error!void {
        var seen: CovariantSeen = .empty;
        defer seen.deinit(self.allocator);
        try self.covariantInputsSeen(root, out, depth, &seen);
    }
    const CovariantInput = struct { root: Id, depth: usize };
    const CovariantSeen = std.AutoHashMapUnmanaged(CovariantInput, void);
    fn covariantInputsSeen(self: *Store, root: Id, out: *std.ArrayList(u32), depth: usize, seen: *CovariantSeen) Error!void {
        if (self.has_projections) try self.chargeProjection();
        if (depth >= 1024) return error.TypeLimit;
        if (self.has_projections) {
            const entry = try seen.getOrPut(self.allocator, .{ .root = root, .depth = depth });
            if (entry.found_existing) return;
        }
        const value = self.node(root);
        switch (value.tag) {
            .function => {
                const free = try self.freeRowVariables(value.a);
                defer self.allocator.free(free);
                try self.unionInto(out, free);
                try self.covariantInputsSeen(value.b, out, depth + 1, seen);
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
                try self.covariantInputsSeen(if (value.tag == .record) self.recordField(value, i).ty else self.extra.items[value.a + i], out, depth + 1, seen);
            },
            .array, .list, .cursor => try self.covariantInputsSeen(value.a, out, depth + 1, seen),
            else => {},
        }
    }
    /// Each use opens only covariant closed rows. A callback's parameter row
    /// remains the exact requirement checked by its producer.
    pub fn openCovariant(self: *Store, root: Id) Error!Id {
        var memo: std.AutoHashMapUnmanaged(Id, Id) = .empty;
        defer memo.deinit(self.allocator);
        return self.openCovariantDepth(root, &memo, 0);
    }
    fn openCovariantDepth(self: *Store, root: Id, memo: *std.AutoHashMapUnmanaged(Id, Id), depth: usize) Error!Id {
        if (self.has_projections) {
            if (memo.get(root)) |result| return result;
            const result = try self.openCovariantNode(root, memo, depth);
            if (memo.count() < 65_536) try memo.put(self.allocator, root, result);
            return result;
        }
        return self.openCovariantNode(root, memo, depth);
    }
    fn openCovariantNode(self: *Store, root: Id, memo: *std.AutoHashMapUnmanaged(Id, Id), depth: usize) Error!Id {
        if (self.has_projections) try self.chargeProjection();
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
                const result = try self.openCovariantDepth(value.b, memo, depth + 1);
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
                    const child = try self.openCovariantDepth(field.ty, memo, depth + 1);
                    if (value.tag == .record) try fields.append(self.allocator, .{ .name = field.name, .ty = child }) else try children.append(self.allocator, child);
                }
                return if (value.tag == .record) self.record(fields.items) else self.product(children.items);
            },
            .array, .list, .cursor => return self.sequence(value.tag, try self.openCovariantDepth(value.a, memo, depth + 1)),
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
            if (self.has_projections) try self.chargeProjection();
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
                while (true) {
                    for (self.effects.list(row_.labels)) |label| for (self.operationArguments(label)) |argument|
                        try pending.append(temporary, .{ .id = argument, .at = at, .depth = work.depth + 1 });
                    if (row_.tail != .variable) break;
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
                .scoped, .array, .list, .cursor, .demand, .resolver, .provider => try pending.append(temporary, .{ .id = value.a, .at = at, .depth = work.depth + 1 }),
                .state_provider => {
                    try pending.append(temporary, .{ .id = value.a, .at = at, .depth = work.depth + 1 });
                    try pending.append(temporary, .{ .id = value.b, .at = at, .depth = work.depth + 1 });
                    try pending.append(temporary, .{ .id = value.c, .at = at, .depth = work.depth + 1 });
                },
                .record => for (0..value.b) |i| {
                    try pending.append(temporary, .{ .id = self.recordField(value, i).ty, .at = at, .depth = work.depth + 1 });
                },
                .nominal, .projection, .instance_selection => for (self.nominalArguments(value)) |child| {
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
        var scratch_buffer: [1024]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        var copied: std.AutoHashMapUnmanaged(Id, Id) = .empty;
        defer copied.deinit(scratch.allocator());
        return self.substituteDepth(root, old, fresh_ids, old_rows, fresh_rows, &copied, scratch.allocator(), 0);
    }
    fn substitutedRow(self: *Store, root: Effects.Id, old: []const Id, fresh_ids: []const Id, old_rows: []const u32, fresh_rows: []const Effects.Id, copied: *std.AutoHashMapUnmanaged(Id, Id), scratch: std.mem.Allocator, depth: usize) Error!Effects.Id {
        if (self.has_projections) try self.chargeProjection();
        const row_ = self.row(root);
        var labels: std.ArrayList(Effects.Label) = .empty;
        defer labels.deinit(scratch);
        var changed = false;
        for (0..row_.labels.len) |index| {
            const label = self.effects.list(row_.labels)[index];
            if (self.has_projections) try self.chargeProjection();
            const operation_ = self.operation(label);
            var arguments: std.ArrayList(Id) = .empty;
            defer arguments.deinit(scratch);
            var argument_changed = false;
            for (0..operation_.arguments.len) |offset| {
                const argument = self.list(operation_.arguments)[offset];
                const next = try self.substituteDepth(argument, old, fresh_ids, old_rows, fresh_rows, copied, scratch, depth + 1);
                argument_changed = argument_changed or next != argument;
                try arguments.append(scratch, next);
            }
            var instance = operation_.instance;
            if (instance.unit == 0 and instance.decl != 0) instance.decl = try self.substituteDepth(instance.decl, old, fresh_ids, old_rows, fresh_rows, copied, scratch, depth + 1);
            var next = label;
            if (argument_changed or !std.meta.eql(instance, operation_.instance)) next = try self.internResolvedOperation(operation_.identity, instance, arguments.items, true);
            changed = changed or next != label;
            try labels.append(scratch, next);
        }
        var result = root;
        if (changed) result = self.effects.rowAt(labels.items, row_.tail, row_.cursor) catch |err| return effectError(err);
        for (old_rows, fresh_rows) |variable, replacement_id| result = self.effects.substitute(result, variable, replacement_id) catch |err| return effectError(err);
        return result;
    }
    // A type graph is a DAG. Repeated children must retain sharing during
    // instantiation; aliases and generic signatures can otherwise expand a
    // linear graph into an exponential tree. The memo is local to this exact
    // substitution, so historical variable views and fresh identities stay exact.
    fn substituteDepth(self: *Store, root: Id, old: []const Id, fresh_ids: []const Id, old_rows: []const u32, fresh_rows: []const Effects.Id, copied: *std.AutoHashMapUnmanaged(Id, Id), scratch: std.mem.Allocator, depth: usize) Error!Id {
        if (self.has_projections) try self.chargeProjection();
        if (depth >= 1024) return error.TypeLimit;
        for (old, fresh_ids) |before, after| if (root == before) return after;
        if (root <= never) return root;
        if (self.node(root).tag == .variable) return root;
        // The input graph is acyclic: the initial root cannot recur beneath
        // itself. Leaf signatures then need no memo allocation at all.
        if (depth != 0) if (copied.get(root)) |known| return known;
        const result = try self.substituteNode(root, old, fresh_ids, old_rows, fresh_rows, copied, scratch, depth);
        if (depth != 0) try copied.put(scratch, root, result);
        return result;
    }
    fn substituteNode(self: *Store, root: Id, old: []const Id, fresh_ids: []const Id, old_rows: []const u32, fresh_rows: []const Effects.Id, copied: *std.AutoHashMapUnmanaged(Id, Id), scratch: std.mem.Allocator, depth: usize) Error!Id {
        if (depth >= 1024) return error.TypeLimit;
        const value = self.node(root);
        switch (value.tag) {
            .scoped => {
                const descriptor = try self.substituteDepth(value.a, old, fresh_ids, old_rows, fresh_rows, copied, scratch, depth + 1);
                var instance: NominalIdentity = .{ .unit = value.b, .decl = value.c };
                if (instance.unit == 0) instance.decl = try self.substituteDepth(instance.decl, old, fresh_ids, old_rows, fresh_rows, copied, scratch, depth + 1);
                return self.scoped(descriptor, instance);
            },
            .function => return self.functionWithEffects(try self.substituteDepth(value.a, old, fresh_ids, old_rows, fresh_rows, copied, scratch, depth + 1), try self.substituteDepth(value.b, old, fresh_ids, old_rows, fresh_rows, copied, scratch, depth + 1), try self.substitutedRow(value.c, old, fresh_ids, old_rows, fresh_rows, copied, scratch, depth + 1)),
            .product => {
                var fields: std.ArrayList(Id) = .empty;
                defer fields.deinit(self.allocator);
                for (0..value.b) |i| try fields.append(self.allocator, try self.substituteDepth(self.extra.items[value.a + i], old, fresh_ids, old_rows, fresh_rows, copied, scratch, depth + 1));
                return self.product(fields.items);
            },
            .array, .list, .cursor => return self.sequence(value.tag, try self.substituteDepth(value.a, old, fresh_ids, old_rows, fresh_rows, copied, scratch, depth + 1)),
            .demand => return self.demandWithEffects(try self.substituteDepth(value.a, old, fresh_ids, old_rows, fresh_rows, copied, scratch, depth + 1), try self.substitutedRow(value.c, old, fresh_ids, old_rows, fresh_rows, copied, scratch, depth + 1)),
            .provider => return self.provider(try self.substituteDepth(value.a, old, fresh_ids, old_rows, fresh_rows, copied, scratch, depth + 1), try self.substitutedRow(value.c, old, fresh_ids, old_rows, fresh_rows, copied, scratch, depth + 1)),
            .state_provider => return self.stateProvider(try self.substituteDepth(value.a, old, fresh_ids, old_rows, fresh_rows, copied, scratch, depth + 1), try self.substituteDepth(value.b, old, fresh_ids, old_rows, fresh_rows, copied, scratch, depth + 1), try self.substituteDepth(value.c, old, fresh_ids, old_rows, fresh_rows, copied, scratch, depth + 1)),
            .resolver => return self.resolver(try self.substituteDepth(value.a, old, fresh_ids, old_rows, fresh_rows, copied, scratch, depth + 1)),
            .record => {
                var fields: std.ArrayList(Field) = .empty;
                defer fields.deinit(self.allocator);
                for (0..value.b) |i| {
                    const field = self.recordField(value, i);
                    try fields.append(self.allocator, .{ .name = field.name, .ty = try self.substituteDepth(field.ty, old, fresh_ids, old_rows, fresh_rows, copied, scratch, depth + 1) });
                }
                return self.record(fields.items);
            },
            .nominal, .projection, .instance_selection => {
                const prior = try self.allocator.dupe(Id, self.nominalArguments(value));
                defer self.allocator.free(prior);
                var args: std.ArrayList(Id) = .empty;
                defer args.deinit(self.allocator);
                for (prior) |child| try args.append(self.allocator, try self.substituteDepth(child, old, fresh_ids, old_rows, fresh_rows, copied, scratch, depth + 1));
                if (value.tag == .projection) return self.projection(.{ .unit = value.a, .decl = value.b }, self.projectionMember(value), args.items);
                if (value.tag == .instance_selection) return self.instanceSelection(.{ .unit = value.a, .decl = value.b }, args.items);
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
test "occurs steps count visited nodes and survive rollback" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    try std.testing.expectEqual(@as(u64, 0), store.occurs_steps);
    const a = try store.fresh();
    const recursive = try store.function(a, u32_type);
    const point = store.mark();
    try std.testing.expectError(error.InfiniteType, store.unify(a, recursive));
    const counted = store.occurs_steps;
    try std.testing.expect(counted >= 2);
    store.rollback(point);
    try std.testing.expectEqual(counted, store.occurs_steps);
}
fn sharedOccursLaw(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const leaf = try store.fresh();
    const other = try store.fresh();
    var root = leaf;
    for (0..12) |_| root = try store.product(&.{ root, root });
    const before = store.occurs_steps;
    try std.testing.expect(!try store.occurs(store.node(other).a, root));
    try std.testing.expect(store.occurs_steps - before <= 13);
    const point = store.mark();
    try std.testing.expectError(error.InfiniteType, store.unify(leaf, root));
    try std.testing.expectEqual(point, store.mark());
    try store.unify(other, root);
    store.rollback(point);
    // A reused ID and a wrapped visitation clock must not hide a cycle.
    store.occurs_generation = std.math.maxInt(u32);
    try std.testing.expectError(error.InfiniteType, store.unify(leaf, root));
    try std.testing.expect(!try store.occurs(store.node(other).a, root));
}
test "occurs visits shared graphs once and preserves cycles through rollback and allocation failures" {
    try sharedOccursLaw(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, sharedOccursLaw, .{});
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
    const later_label = try store.internOperation(.{ .unit = 8, .decl = 22 }, &.{});
    const first = try store.effects.row(&.{foreign_operation}, .closed);
    const later = try store.effects.row(&.{later_label}, .closed);
    try store.effects.appendVersion(variable, first); // global position 0
    try store.appendVersion(ty, try store.functionWithEffects(unit, u32_type, effect_row)); // 1
    try store.effects.appendVersion(variable, later); // 2
    const resolved = store.node(try store.resolve(ty, 0));
    try std.testing.expectEqualSlices(u32, &.{later_label}, store.effects.list(store.effects.node(resolved.c).labels));
    try std.testing.expectEqual(@as(u32, 3), store.cursor());
    const suspended = try store.fresh();
    const demand_row = try store.freshEffects();
    try store.effects.appendVersion(store.effects.node(demand_row).tail.variable, first); // 3
    try store.appendVersion(suspended, try store.demandWithEffects(u32_type, demand_row)); // 4
    try store.effects.appendVersion(store.effects.node(demand_row).tail.variable, later); // 5
    const demand_node = store.node(try store.resolve(suspended, 0));
    try std.testing.expectEqualSlices(u32, &.{later_label}, store.effects.list(store.effects.node(demand_node.c).labels));
    try std.testing.expectEqual(@as(u32, 6), store.cursor());
}
test "rejected function effect rows roll back type and row writes and shared chronology" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const parameter = try store.fresh();
    const effect_row = try store.freshEffects();
    const other = try store.internOperation(.{ .unit = 8, .decl = 22 }, &.{});
    const left = try store.functionWithEffects(parameter, try store.functionWithEffects(unit, u32_type, effect_row), try store.effects.row(&.{foreign_operation}, .closed));
    const right = try store.functionWithEffects(u32_type, try store.function(unit, u32_type), try store.effects.row(&.{other}, .closed));
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
    const recursive = try store.effects.row(&.{foreign_operation}, store.row(latent).tail);
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
    const label = try store.effects.row(&.{ foreign_operation, foreign_operation }, .closed);
    try store.unifyEffects(store.node(one).c, label);
    try std.testing.expectEqual(Effects.Tail.variable, std.meta.activeTag(store.effects.node(try store.resolveEffects(store.node(two).c, 0)).tail));
    const one_result = store.node(store.node(try store.resolve(one, 0)).b);
    try std.testing.expectEqual(u32_type, one_result.a);
    try std.testing.expectEqualSlices(u32, &.{ foreign_operation, foreign_operation }, store.effects.list(store.effects.node(one_result.c).labels));
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

fn sharedSubstitutionLaw(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const variable = try store.fresh();
    var root = variable;
    for (0..64) |_| root = try store.product(&.{ root, root });
    const before = store.nodes.items.len;
    var result = try store.substitute(root, &.{variable}, &.{u32_type});
    // The output describes 2^64 leaves using 64 shared product nodes.
    try std.testing.expect(store.nodes.items.len - before <= 64);
    for (0..64) |_| {
        const node_ = store.node(result);
        try std.testing.expectEqual(Tag.product, node_.tag);
        const fields = store.list(.{ .start = node_.a, .len = node_.b });
        try std.testing.expectEqual(fields[0], fields[1]);
        result = fields[0];
    }
    try std.testing.expectEqual(u32_type, result);
    // A second substitution owns distinct replacements; no memo survives calls.
    const next = try store.substitute(root, &.{variable}, &.{f32_type});
    try std.testing.expect(next != result);
    try std.testing.expectEqual(f32_type, try store.substitute(u32_type, &.{u32_type}, &.{f32_type}));
}
test "shared type substitution stays linear and releases scratch on allocation failure" {
    try sharedSubstitutionLaw(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, sharedSubstitutionLaw, .{});
}

test "type substitution preserves historical views and independent row replacements" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const variable = try store.fresh();
    try store.appendVersion(variable, u32_type);
    const future = try store.resolve(variable, store.cursor());
    try store.appendVersion(variable, f32_type);
    const root = try store.product(&.{ variable, future, future });
    const selected = try store.substitute(root, &.{variable}, &.{boolean});
    const node_ = store.node(selected);
    const fields = store.list(.{ .start = node_.a, .len = node_.b });
    try std.testing.expectEqual(boolean, fields[0]);
    try std.testing.expectEqual(future, fields[1]);
    try std.testing.expectEqual(future, fields[2]);
    try std.testing.expectEqual(f32_type, try store.resolve(fields[1], 0));
    const row_ = try store.freshEffects();
    const callable = try store.functionWithEffects(unit, u32_type, row_);
    const pair = try store.product(&.{ callable, callable });
    const row_variable = store.row(row_).tail.variable;
    const pure = try store.substituteWithRows(pair, &.{}, &.{}, &.{row_variable}, &.{0});
    const foreign = try store.effects.row(&.{foreign_operation}, .closed);
    const effectful = try store.substituteWithRows(pair, &.{}, &.{}, &.{row_variable}, &.{foreign});
    const pure_function = store.node(store.list(.{ .start = store.node(pure).a, .len = 2 })[0]);
    const effectful_function = store.node(store.list(.{ .start = store.node(effectful).a, .len = 2 })[0]);
    try std.testing.expectEqual(@as(Effects.Id, 0), pure_function.c);
    try std.testing.expectEqualSlices(Effects.Label, &.{foreign_operation}, store.rowLabels(effectful_function.c));
}

fn closedVariableCertificateLaw(allocator: std.mem.Allocator) !void {
    var cached = try Store.initWithOptions(allocator, .{ .closed_graphs = true });
    defer cached.deinit();
    var oracle = try Store.initWithOptions(allocator, .{ .resolution_cache = false });
    defer oracle.deinit();
    var roots: [2][8]Id = undefined;
    for ([_]*Store{ &cached, &oracle }, &roots) |store, *variables| for (variables) |*variable| {
        variable.* = try store.fresh();
    };
    const marks = [_]Mark{ cached.mark(), oracle.mark() };
    var proof = try @import("type_evidence.zig").Store.init(allocator);
    defer proof.deinit();
    for (0..16) |step| {
        for ([_]*Store{ &cached, &oracle }, roots) |store, variables| {
            const selected: Id = if (step % 3 == 0) variables[(step + 1) % variables.len] else if (step % 3 == 1) u32_type else f32_type;
            try store.appendVersion(variables[step % variables.len], selected);
        }
        for (0..cached.cursor() + 1) |at| for (roots[0], roots[1]) |left, right| {
            const l = try cached.resolve(left, @intCast(at));
            const r = try oracle.resolve(right, @intCast(at));
            const expected = proof.project(&oracle, r, &.{}) catch |err| switch (err) {
                error.UnresolvedType => 0,
                else => return err,
            };
            const actual = proof.project(&cached, l, &.{}) catch |err| switch (err) {
                error.UnresolvedType => 0,
                else => return err,
            };
            try std.testing.expectEqual(expected, actual);
            if (expected == 0) {
                try std.testing.expectEqual(oracle.node(r).a, cached.node(l).a);
                try std.testing.expectEqual(oracle.node(r).b, cached.node(l).b);
            }
        };
    }
    for ([_]*Store{ &cached, &oracle }, marks) |store, mark_| store.rollback(mark_);
    for ([_]*Store{ &cached, &oracle }, roots) |store, variables| {
        try store.appendVersion(variables[0], f32_type);
        try std.testing.expectEqual(f32_type, try store.resolve(variables[0], 0));
        try std.testing.expectEqual(variables[1], try store.resolve(variables[1], 0));
        const record = try store.record(&.{.{ .name = 10, .ty = u32_type }});
        try store.appendVersion(variables[1], record);
        _ = try store.resolve(variables[1], 0);
        const shape = store.node(record);
        store.replaceListItem(.{ .start = shape.a, .len = shape.b * 2 }, 1, f32_type);
        const resolved = store.node(try store.resolve(variables[1], 0));
        try std.testing.expectEqual(f32_type, store.recordField(resolved, 0).ty);
    }
    const point = cached.effects.mark();
    const row = try cached.effects.row(&.{foreign_operation}, .closed);
    const callback = try cached.functionWithEffects(unit, u32_type, row);
    try cached.appendVersion(roots[0][2], callback);
    try std.testing.expectEqual(row, cached.node(try cached.resolve(roots[0][2], 0)).c);
    cached.effects.rollback(point);
    const replacement_row = try cached.effects.row(&.{ foreign_operation, foreign_operation }, .closed);
    try std.testing.expectEqual(row, replacement_row);
    const changed = cached.node(try cached.resolve(roots[0][2], 0));
    try std.testing.expectEqualSlices(Effects.Label, &.{ foreign_operation, foreign_operation }, cached.rowLabels(changed.c));
    cached.closed_generation = std.math.maxInt(u16);
    try std.testing.expectEqual(f32_type, try cached.resolve(roots[0][0], 0));
}
test "closed variable certificates preserve chronological cursors physical edits rollback and allocation failure" {
    try closedVariableCertificateLaw(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, closedVariableCertificateLaw, .{});
}

fn symbolicOperationLaw(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const identity: NominalIdentity = .{ .unit = 9, .decl = 21 };
    const argument = try store.fresh();
    const other = try store.fresh();
    const label = try store.internSymbolicOperation(identity, &.{argument});
    try std.testing.expectEqual(label, try store.internSymbolicOperation(identity, &.{argument}));
    try std.testing.expect(label != try store.internSymbolicOperation(identity, &.{other}));
    const open = try store.freshEffects();
    const root = try store.functionWithEffects(unit, unit, try store.effects.row(&.{ label, label }, store.row(open).tail));
    const variables = try store.freeVariables(root);
    defer allocator.free(variables);
    try std.testing.expectEqualSlices(Id, &.{argument}, variables);
    const closed = try store.internOperation(identity, &.{u32_type});
    const instantiated = try store.substituteWithRows(root, &.{argument}, &.{u32_type}, &.{store.row(open).tail.variable}, &.{0});
    const row_ = store.node(instantiated).c;
    try std.testing.expectEqualSlices(Effects.Label, &.{ closed, closed }, store.rowLabels(row_));
    try std.testing.expect(store.row(row_).tail == .closed);
    try store.unify(argument, f32_type);
    const floating = try store.internOperation(identity, &.{f32_type});
    const resolved = try store.resolve(root, 0);
    try std.testing.expectEqualSlices(Effects.Label, &.{ floating, floating }, store.rowLabels(store.node(resolved).c));
    try std.testing.expectEqualSlices(Effects.Label, &.{ label, label }, store.rowLabels(store.node(root).c));
    try store.unifyEffects(store.node(root).c, try store.effects.row(&.{ floating, floating }, .closed));
    store.unifyEffects(row_, try store.effects.row(&.{floating}, .closed)) catch |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.EffectMismatch, err);
        return;
    };
    return error.TestExpectedError;
}

test "symbolic operation arguments substitute and resolve without erasing row multiplicity" {
    try symbolicOperationLaw(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, symbolicOperationLaw, .{});
}

fn symbolicOperationInferenceLaw(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const identity: NominalIdentity = .{ .unit = 9, .decl = 21 };
    const argument = try store.fresh();
    const label = try store.internSymbolicOperation(identity, &.{argument});
    const symbolic = try store.effects.row(&.{ label, label }, .closed);
    const integer = try store.internOperation(identity, &.{u32_type});
    const floating = try store.internOperation(identity, &.{f32_type});
    try store.unifyEffects(symbolic, try store.effects.row(&.{ integer, integer }, .closed));
    try std.testing.expectEqual(u32_type, try store.resolve(argument, 0));
    const future = try store.resolve(argument, store.cursor());
    const future_label = try store.internSymbolicOperation(identity, &.{future});
    const future_row = try store.effects.row(&.{future_label}, .closed);
    try store.appendVersion(argument, f32_type);
    try std.testing.expectEqualSlices(Effects.Label, &.{ integer, integer }, store.rowLabels(try store.resolveEffects(symbolic, 0)));
    try std.testing.expectEqualSlices(Effects.Label, &.{floating}, store.rowLabels(try store.resolveEffects(future_row, 0)));

    const unresolved = try store.fresh();
    const unknown = try store.internSymbolicOperation(identity, &.{unresolved});
    const requirement = try store.effects.row(&.{unknown}, .closed);
    const ambiguous = try store.effects.row(&.{ integer, floating }, .closed);
    const point = store.mark();
    store.unifyEffects(requirement, ambiguous) catch |err| {
        try std.testing.expectEqualDeep(point, store.mark());
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.EffectMismatch, err);
        try std.testing.expectEqual(unresolved, try store.resolve(unresolved, 0));
        return;
    };
    return error.TestExpectedError;
}

test "symbolic operation inference preserves chronological argument views and rejects ambiguous instances transactionally" {
    try symbolicOperationInferenceLaw(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, symbolicOperationInferenceLaw, .{});
}

fn symbolicNestedRowLaw(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const nested = try store.freshEffects();
    const callback = try store.functionWithEffects(unit, u32_type, nested);
    const label = try store.internSymbolicOperation(.{ .unit = 7, .decl = 19 }, &.{callback});
    const root = try store.functionWithEffects(unit, unit, try store.effects.row(&.{label}, .closed));
    try std.testing.expect(!try store.equalClosed(root, root));
    const rows = try store.freeRowVariables(root);
    defer allocator.free(rows);
    try std.testing.expectEqualSlices(u32, &.{store.row(nested).tail.variable}, rows);
    const concrete = try store.substituteWithRows(root, &.{}, &.{}, rows, &.{0});
    try std.testing.expect(try store.equalClosed(concrete, concrete));
    const substituted = store.operationArguments(store.rowLabels(store.node(concrete).c)[0])[0];
    try std.testing.expectEqual(@as(Effects.Id, 0), store.node(substituted).c);
}

test "symbolic operation arguments quantify nested row binders and require closed evidence" {
    try symbolicNestedRowLaw(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, symbolicNestedRowLaw, .{});
}

test "closed operation argument heights preserve cached and uncached resolution depth limits" {
    const a = std.testing.allocator;
    var store = try Store.initWithOptions(a, .{ .closed_graphs = true });
    defer store.deinit();
    var root: Id = unit;
    // Construct the immutable graph without asking resolution to certify it.
    // The admission depth boundary is independent of the allocator/owner graph.
    for (0..600) |_| {
        const label: Effects.Label = @intCast(store.operations.items.len);
        const arguments = try store.saveList(&.{root});
        try store.operations.append(a, .{ .identity = .{ .unit = 7, .decl = 19 }, .arguments = arguments });
        root = try store.functionWithEffects(unit, unit, try store.effects.row(&.{label}, .closed));
    }
    const cached = store.resolve(root, 0);
    store.use_closed_graphs = false;
    store.use_resolution_cache = false;
    store.use_composite_cache = false;
    const uncached = store.resolve(root, 0);
    try std.testing.expectError(error.TypeLimit, uncached);
    try std.testing.expectError(error.TypeLimit, cached);
}

fn scopedOperationIdentityLaw(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const identity: NominalIdentity = .{ .unit = 7, .decl = 8 };
    const left: NominalIdentity = .{ .unit = 7, .decl = 90 };
    const right: NominalIdentity = .{ .unit = 7, .decl = 91 };
    const variable = try store.fresh();
    const static = try store.internOperation(identity, &.{u32_type});
    const first = try store.internScopedOperation(identity, left, &.{variable});
    const second = try store.internScopedOperation(identity, right, &.{u32_type});
    try store.unify(variable, u32_type);
    const row_ = try store.effects.row(&.{ first, first, second, static }, .closed);
    const resolved = try store.resolveEffects(row_, 0);
    const labels = store.rowLabels(resolved);
    try std.testing.expectEqual(@as(usize, 4), labels.len);
    try std.testing.expectEqual(labels[0], labels[1]);
    try std.testing.expect(labels[0] != labels[2] and labels[0] != labels[3]);
    try std.testing.expectEqual(left, store.operation(labels[0]).instance);
    const nominal_ = try store.nominal(identity, &.{variable});
    const scoped_ = try store.scoped(nominal_, left);
    const other = try store.scoped(nominal_, right);
    try std.testing.expect(!try store.equalSymbolic(scoped_, other));
    store.unify(scoped_, other) catch |err| switch (err) {
        error.TypeMismatch => {},
        else => return err,
    };
    const normalized = store.node(try store.resolve(scoped_, 0));
    try std.testing.expectEqual(Tag.scoped, normalized.tag);
    try std.testing.expectEqual(left.unit, normalized.b);
    try std.testing.expectEqual(left.decl, normalized.c);
}
test "scoped effect identity survives normalization and preserves multiplicity" {
    try scopedOperationIdentityLaw(std.testing.allocator);
}
test "scoped effect identity releases every failed allocation" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, scopedOperationIdentityLaw, .{});
}

fn capabilityParameterLaw(allocator: std.mem.Allocator) !void {
    var store = try Store.initWithOptions(allocator, .{ .closed_graphs = true });
    defer store.deinit();
    const descriptor = try store.nominal(.{ .unit = 1, .decl = 7 }, &.{u32_type});
    const parameter = try store.capabilityParameter(descriptor);
    const term = store.node(parameter);
    try std.testing.expect(!try store.equalClosed(parameter, parameter));
    const read = try store.internScopedOperation(.{ .unit = 1, .decl = 8 }, .{ .unit = term.b, .decl = term.c }, &.{u32_type});
    const latent = try store.effects.row(&.{ read, read }, .closed);
    const signature = try store.functionWithEffects(parameter, u32_type, latent);
    const variables = try store.freeVariables(signature);
    defer allocator.free(variables);
    try std.testing.expectEqualSlices(Id, &.{term.c}, variables);
    const first_variable = try store.fresh();
    const second_variable = try store.fresh();
    const first = try store.substitute(signature, variables, &.{first_variable});
    const second = try store.substitute(signature, variables, &.{second_variable});
    try std.testing.expectEqual(first_variable, store.node(store.node(first).a).c);
    try std.testing.expectEqual(second_variable, store.operation(store.rowLabels(store.node(second).c)[0]).instance.decl);
    const left = try store.scoped(descriptor, .{ .unit = 1, .decl = 30 });
    const right = try store.scoped(descriptor, .{ .unit = 1, .decl = 31 });
    const point = store.mark();
    try store.unify(store.node(first).a, left);
    const resolved = store.node(try store.resolve(first, 0));
    const labels = store.rowLabels(resolved.c);
    try std.testing.expectEqual(2, labels.len);
    try std.testing.expectEqual(NominalIdentity{ .unit = 1, .decl = 30 }, store.operation(labels[0]).instance);
    try std.testing.expectEqual(NominalIdentity{ .unit = 0, .decl = second_variable }, store.operation(store.rowLabels(store.node(second).c)[0]).instance);
    store.rollback(point);
    try store.unify(store.node(first).a, right);
    const rerouted = store.node(try store.resolve(first, 0));
    try std.testing.expectEqual(NominalIdentity{ .unit = 1, .decl = 31 }, store.operation(store.rowLabels(rerouted.c)[0]).instance);
    try std.testing.expectError(error.TypeMismatch, store.unify(left, right));
}
test "capability identity parameters freshen resolve precise rows and revoke on rollback" {
    try capabilityParameterLaw(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, capabilityParameterLaw, .{});
}

/// Physical keys copy a selection's stable atom rather than retaining a type edge.
/// Semantic rows retain the owned edge for footprint and equality proofs.
pub fn selectionAtom(source: anytype, original: NominalIdentity) NominalIdentity {
    if (original.unit != 0 or original.decl == 0) return original;
    const value = source.node(original.decl);
    if (value.tag != .instance_selection) return original;
    return .{ .unit = value.a, .decl = value.b };
}

fn selectionIdentityLaw(allocator: std.mem.Allocator) !void {
    var store = try Store.initWithOptions(allocator, .{ .closed_graphs = true });
    defer store.deinit();
    const descriptor = try store.nominal(.{ .unit = 1, .decl = 23 }, &.{u32_type});
    const left = try store.scoped(descriptor, .{ .unit = 1, .decl = 31 });
    const right = try store.scoped(descriptor, .{ .unit = 1, .decl = 32 });
    const term = try store.instanceSelection(.{ .unit = 1, .decl = 50 }, &.{ left, right });
    try std.testing.expectEqual(term, try store.instanceSelection(.{ .unit = 1, .decl = 50 }, &.{ left, right }));
    const other = try store.instanceSelection(.{ .unit = 1, .decl = 51 }, &.{ left, right });
    const selected = try store.scoped(descriptor, .{ .unit = 0, .decl = term });
    const independent = try store.scoped(descriptor, .{ .unit = 0, .decl = other });
    try std.testing.expect(!try store.equalSymbolic(selected, independent));
    const formal = try store.capabilityParameter(descriptor);
    try store.unify(formal, selected);
    try std.testing.expect(try store.equalSymbolic(try store.resolve(formal, 0), selected));
    const supplied = try store.internScopedOperation(.{ .unit = 1, .decl = 24 }, .{ .unit = 0, .decl = term }, &.{u32_type});
    const original = try store.internScopedOperation(.{ .unit = 1, .decl = 24 }, .{ .unit = 1, .decl = 31 }, &.{u32_type});
    const selected_row = try store.effects.row(&.{supplied}, .closed);
    const original_row = try store.effects.row(&.{original}, .closed);
    const payload = try store.fresh();
    const symbolic_descriptor = try store.nominal(.{ .unit = 1, .decl = 23 }, &.{payload});
    const symbolic_left = try store.scoped(symbolic_descriptor, .{ .unit = 1, .decl = 31 });
    const symbolic_right = try store.scoped(symbolic_descriptor, .{ .unit = 1, .decl = 32 });
    const symbolic_term = try store.instanceSelection(.{ .unit = 1, .decl = 52 }, &.{ symbolic_left, symbolic_right });
    const symbolic_selected = try store.scoped(symbolic_descriptor, .{ .unit = 0, .decl = symbolic_term });
    const symbolic_operation = try store.internScopedOperation(.{ .unit = 1, .decl = 24 }, .{ .unit = 0, .decl = symbolic_term }, &.{payload});
    const symbolic_row = try store.effects.row(&.{symbolic_operation}, .closed);
    try store.unify(payload, u32_type);
    const normalized = try store.resolve(symbolic_selected, 0);
    const normalized_term = store.node(normalized).c;
    const normalized_row = try store.resolveEffects(symbolic_row, 0);
    try std.testing.expectEqual(normalized_term, store.operation(store.rowLabels(normalized_row)[0]).instance.decl);
    const copied = try store.substitute(normalized, &.{}, &.{});
    try std.testing.expectEqual(normalized_term, store.node(copied).c);
    try std.testing.expectEqual(symbolic_term, normalized_term);
    try std.testing.expectError(error.TypeMismatch, store.instanceSelection(.{ .unit = 1, .decl = 50 }, &.{ u32_type, right }));
    const swapped = try store.instanceSelection(.{ .unit = 1, .decl = 50 }, &.{ right, left });
    try std.testing.expect(swapped != term);
    try std.testing.expectEqual(normalized_term, store.node(try store.resolve(symbolic_selected, 0)).c);
    const mark_ = store.mark();
    try store.unifyEffects(selected_row, selected_row);
    try std.testing.expectEqual(NominalIdentity{ .unit = 1, .decl = 50 }, selectionAtom(&store, .{ .unit = 0, .decl = term }));
    try std.testing.expectEqualSlices(Id, &.{ left, right }, store.nominalArguments(store.node(term)));
    store.unifyEffects(selected_row, original_row) catch |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.EffectMismatch, err);
        try std.testing.expectEqualDeep(mark_, store.mark());
        return;
    };
    return error.TestUnexpectedResult;
}
test "selected identity terms preserve alias edges and reject independent roots transactionally through OOM" {
    try selectionIdentityLaw(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, selectionIdentityLaw, .{});
}
