//! Owned dense types and ordered substitution history. Resolution follows the
//! first replacement at or after its cursor, then advances past that write.
//! It deliberately does not collapse history into union-find representatives.
const std = @import("std");
const resolution_cache = @import("../reuse/resolution_cache.zig");
const epoch_cache = @import("../reuse/epoch_resolution_cache.zig");
const composite_cache = @import("../reuse/composite_resolution_cache.zig");
pub const Effects = @import("effects.zig");
pub const Id = u32;
pub const Cursor = u32;
pub const absent: Id = 0;
pub const unit: Id = 1;
pub const boolean: Id = 2;
pub const u32_type: Id = 3;
pub const f32_type: Id = 4;
pub const never: Id = 5;
pub const Tag = enum(u8) { absent, unit, boolean, u32, f32, never, variable, function, product, record, nominal, array, list, cursor, demand, type_constructor, resolver, provider, state_provider, projection, scoped, instance_selection, erased_proof, forall, existential, bound, rigid, usage, instance_version };
pub const UsageKind = @import("../parse/ast.zig").UsageKind;
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
/// Compiler-owned nominal constructors have no Source declaration recipe.
/// Their schema belongs to this compiler image, including each type argument.
pub fn compilerNominalArity(identity: NominalIdentity) ?u32 {
    if (identity.unit != std.math.maxInt(u32)) return null;
    return switch (identity.decl) {
        3, 4 => 0, // EffectSet, EffectDescriptor
        5 => 1, // Computation[action]
        6 => 3, // Decision[reply, state, result]
        8 => 2, // Code[result, latent effects]
        9 => 1, // Descriptor[target]
        16 => 0, // Task group (scoped)
        17, 18 => 2, // Task[group, thunk], View[array, instance version]
        else => null,
    };
}
/// The version argument is a source binding identity, rather than a type or
/// an AST point. It is part of View's compiler-owned constructor schema.
pub fn compilerNominalVersionArgument(identity: NominalIdentity) ?u32 {
    if (identity.unit == std.math.maxInt(u32) and identity.decl == 18) return 1;
    return null;
}
pub const effect_set_identity: NominalIdentity = .{ .unit = std.math.maxInt(u32), .decl = 3 };
pub const effect_descriptor_identity: NominalIdentity = .{ .unit = std.math.maxInt(u32), .decl = 4 };
pub const builtin_state_write: NominalIdentity = .{ .unit = std.math.maxInt(u32), .decl = 2 };
pub const Field = struct { name: u32, ty: Id };
pub const List = struct { start: u32 = 0, len: u32 = 0 };
/// These keys belong to the row mapping namespace, not the type mapping table.
/// A formal key names the exact owned bound leaf in its source type graph.
pub fn formalRowKey(binder: Id) Error!u32 {
    if (binder == 0 or binder >= Effects.formal_key_bit) return error.TypeLimit;
    return Effects.formal_key_bit | binder;
}
pub fn rowKeyFormal(key: u32) ?Id {
    if (key & Effects.formal_key_bit == 0) return null;
    return key & ~Effects.formal_key_bit;
}
pub const Scheme = struct { root: Id = absent, variables: List = .{}, row_variables: List = .{}, closed_rows: List = .{}, obligations: List = .{}, generative: List = .{} };
pub const ClosedCovariant = struct { root: Id, closed_rows: List };
pub const Operator = enum { none, add, sub, mul, div, rem, equal, not_equal, less, less_equal, greater, greater_equal, bit_and, bit_or, bit_xor, shift_left, shift_right };
pub const ObligationKind = enum { arithmetic, ordered, equality, integer, field, writable_field, dispatch, result_dispatch, monad_factory, resolver_dispatch, resolver_shape, effect_operation, effect_handler, receiver, update, type_rep, effect_rep, type_head, collection, record_merge, callee_use, type_eq, contract, task_receive };
pub const QuantifierGoals = struct { owner: Id, goals: List };
pub const Obligation = struct { ty: Id, kind: ObligationKind, source: u32, name: u32 = 0, result: Id = 0, other: Id = 0, signature: Id = 0, operator: Operator = .none, identity: NominalIdentity = .{ .unit = 0, .decl = 0 }, explicit: bool = false, qualification_span: ?@import("../parse/ast.zig").Span = null, qualification_unit: u32 = 0 };
pub const Version = struct { variable: u32, replacement: Id, position: Cursor, previous: u32, next: u32 = none };
const none = std.math.maxInt(u32);
const Variable = struct { first: u32 = none, last: u32 = none, region: bool = false, row_effect: Effects.Id = none };
pub const Mark = struct { nodes: usize, extra: usize, variables: usize, versions: usize, operations: usize, quantifier_goals: usize = 0, quantifier_obligations: usize = 0, effects: Effects.Mark };
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
const OperationKey = struct { identity: NominalIdentity, instance: NominalIdentity, arity: u32, shape: u64 };
const OperationChain = struct { first: Effects.Label, last: Effects.Label };
const OperationLink = struct { next: Effects.Label = none, previous: Effects.Label = none, shape: u64 = 0 };
const RowCertificate = struct { generation: u16 = 0, argument_height: u8 = 0, has_arguments: bool = false };
const ClosedRow = struct {
    row: Effects.Id = 0,
    generation: u16 = 0,
    argument_height: u8 = 0,
    has_arguments: bool = false,
};
const OperationRow = struct {
    row: Effects.Id = 0,
    result: Effects.Id = 0,
    at: Cursor = 0,
    depth: usize = 0,
    limit: usize = 0,
    mutation: u64 = std.math.maxInt(u64),
    effects: u64 = std.math.maxInt(u64),
};

pub const Store = struct {
    // Positive, solver-owned metadata. No allocation, frozen graph or row ABI
    // changes; both clocks prevent recycled IDs from reviving old proofs.
    use_closed_rows: bool = true,
    closed_rows: [4]ClosedRow = @splat(.{}),
    // Dense, solver-owned positive certificates avoid collision-driven walks
    // on large rows. Growth happens only at the fallible resolver boundary;
    // infallible construction can still use the tiny inline fallback.
    closed_row_index: std.ArrayList(RowCertificate) = .empty,
    // Rows often repeat the same operation argument vector. Positive facts
    // belong to this solver generation, independently of row storage sharing.
    closed_operation_index: std.ArrayList(RowCertificate) = .empty,
    use_operation_rows: bool = true,
    operation_rows: [64]OperationRow = @splat(.{}),
    has_usage_types: bool = false,
    has_rank_types: bool = false,
    next_rigid_scope: u32 = 1,
    use_closed_graphs: bool = false,
    has_proof_kinds: bool = false,
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
    normalization: @import("../work_counters.zig").Normalization = .{},
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
    /// Interned operations chained by identity, instance and arity, oldest
    /// first; `operation_links` covers the leading operations linked so far.
    /// Interning appends and rollback truncates; other writers only append.
    operation_chains: std.AutoHashMapUnmanaged(OperationKey, OperationChain) = .empty,
    operation_links: std.ArrayList(OperationLink) = .empty,
    use_operation_shapes: bool = true,
    operation_shape_generation: u16 = 0,
    operation_shape_enabled: bool = false,
    quantifier_goals: std.ArrayList(QuantifierGoals) = .empty,
    quantifier_obligations: std.ArrayList(Obligation) = .empty,

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
        self.closed_row_index.deinit(self.allocator);
        self.closed_operation_index.deinit(self.allocator);
        self.effects.deinit();
        self.operations.deinit(self.allocator);
        self.operation_chains.deinit(self.allocator);
        self.operation_links.deinit(self.allocator);
        self.quantifier_goals.deinit(self.allocator);
        self.quantifier_obligations.deinit(self.allocator);
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
    fn closedRow(self: *const Store, id: Effects.Id) ?ClosedRow {
        // The shared physical-epoch guard is the same as closedHeight.
        // Both synchronizeClosedGraphs and rollback advance the generation
        // before adopting a changed physical epoch; old entries cannot revive.
        if (!self.use_closed_rows or !self.use_closed_graphs or self.closed_generation == std.math.maxInt(u16) or self.effects.physical_epoch == std.math.maxInt(u64) or self.closed_effect_physical_epoch != self.effects.physical_epoch) return null;
        const value: ClosedRow = if (id < self.closed_row_index.items.len) value: {
            const proof = self.closed_row_index.items[id];
            break :value .{ .row = id, .generation = proof.generation, .argument_height = proof.argument_height, .has_arguments = proof.has_arguments };
        } else self.closed_rows[id % self.closed_rows.len];
        return if (value.row == id and value.generation == self.closed_generation) value else null;
    }
    fn saveClosedRow(self: *Store, id: Effects.Id, height: u8, has_arguments: bool) void {
        if (!self.use_closed_rows or !self.use_closed_graphs or self.closed_generation == std.math.maxInt(u16) or self.effects.physical_epoch == std.math.maxInt(u64) or self.closed_effect_physical_epoch != self.effects.physical_epoch) return;
        if (id < self.closed_row_index.items.len) {
            self.closed_row_index.items[id] = .{ .generation = self.closed_generation, .argument_height = height, .has_arguments = has_arguments };
            return;
        }
        const slot = &self.closed_rows[id % self.closed_rows.len];
        if (slot.generation == self.closed_generation and slot.row != id) self.normalization.closed_row_evictions += 1;
        slot.* = .{ .row = id, .generation = self.closed_generation, .argument_height = height, .has_arguments = has_arguments };
    }
    fn closedOperation(self: *const Store, label: Effects.Label) ?RowCertificate {
        if (!self.use_closed_rows or !self.use_closed_graphs or self.closed_generation == std.math.maxInt(u16) or self.effects.physical_epoch == std.math.maxInt(u64) or self.closed_effect_physical_epoch != self.effects.physical_epoch or label >= self.closed_operation_index.items.len) return null;
        const proof = self.closed_operation_index.items[label];
        return if (proof.generation == self.closed_generation) proof else null;
    }
    fn saveClosedOperation(self: *Store, label: Effects.Label, height: u8, has_arguments: bool) void {
        if (!self.use_closed_rows or !self.use_closed_graphs or self.closed_generation == std.math.maxInt(u16) or self.effects.physical_epoch == std.math.maxInt(u64) or self.closed_effect_physical_epoch != self.effects.physical_epoch or label >= self.closed_operation_index.items.len) return;
        self.closed_operation_index.items[label] = .{ .generation = self.closed_generation, .argument_height = height, .has_arguments = has_arguments };
    }
    fn closedRowHeight(self: *Store, id: Effects.Id) u8 {
        const r = self.effects.node(id);
        if (r.tail != .closed) return 0;
        if (r.labels.len == 0) return 1;
        if (self.closedRow(id)) |cached| return if (cached.argument_height == std.math.maxInt(u8)) 0 else cached.argument_height + 1;
        var height: u8 = 0;
        var has_arguments = false;
        for (self.effects.list(r.labels)) |label| {
            if (label >= self.operations.items.len) return 0;
            if (self.closedOperation(label)) |proof| {
                height = @max(height, proof.argument_height);
                has_arguments = has_arguments or proof.has_arguments;
                continue;
            }
            const instance = self.operations.items[label].instance;
            if (instance.unit == 0 and instance.decl != 0) return 0;
            var operation_height: u8 = 0;
            for (self.list(self.operations.items[label].arguments)) |arg| {
                has_arguments = true;
                const argument_height = self.closedHeight(arg);
                if (argument_height == 0) return 0;
                height = @max(height, argument_height);
                operation_height = @max(operation_height, argument_height);
            }
            self.saveClosedOperation(label, operation_height, self.operations.items[label].arguments.len != 0);
        }
        self.saveClosedRow(id, height, has_arguments);
        if (height == std.math.maxInt(u8)) return 0;
        return height + 1;
    }
    fn closedNodeHeight(self: *Store, n: Node) u8 {
        var height: u8 = 0;
        switch (n.tag) {
            .absent, .variable, .forall, .existential, .bound, .rigid => return 0,
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
            .usage, .scoped, .array, .list, .cursor, .resolver => {
                if ((n.tag == .scoped and n.b == 0) or (n.tag == .usage and n.c != 0)) return 0;
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
    /// Bound leaves belong to the surrounding owned quantifier. Their numeric
    /// handles remain distinct even when two scopes use the same ordinal.
    pub fn boundType(self: *Store, ordinal: u32, sort: u32) Error!Id {
        self.has_rank_types = true;
        return self.add(.{ .tag = .bound, .a = ordinal, .b = sort });
    }
    pub fn rigidScope(self: *Store) Error!u32 {
        if (self.next_rigid_scope == std.math.maxInt(u32)) return error.TypeLimit;
        const scope = self.next_rigid_scope;
        self.next_rigid_scope += 1;
        return scope;
    }
    pub fn rigid(self: *Store, scope: u32, ordinal: u32, sort: u32) Error!Id {
        self.has_rank_types = true;
        return self.add(.{ .tag = .rigid, .a = scope, .b = ordinal, .c = sort });
    }
    // Quantifiers own the binder list; a=body,b/c=list span. Publication must
    // preserve binder edges and reject request-local rigid leaves.
    pub fn quantifierGoals(self: *const Store, owner: Id) []const Obligation {
        return @import("quantifier_goals.zig").get(self.quantifier_goals.items, self.quantifier_obligations.items, owner);
    }
    pub fn quantified(self: *Store, tag: Tag, body: Id, binders: []const Id) Error!Id {
        return self.quantifiedWithGoals(tag, body, binders, &.{});
    }
    pub fn quantifiedWithGoals(self: *Store, tag: Tag, body: Id, binders: []const Id, goals: []const Obligation) Error!Id {
        std.debug.assert(tag == .forall or tag == .existential);
        if (binders.len == 0 or binders.len > 4096) return error.TypeLimit;
        for (binders, 0..) |binder, ordinal| {
            if (binder >= self.nodes.items.len) return error.TypeMismatch;
            const leaf = self.node(binder);
            if (leaf.tag != .bound or leaf.a != ordinal or leaf.b > 2 or leaf.c != 0) return error.TypeMismatch;
        }
        self.has_rank_types = true;
        const owned_goals = try self.allocator.dupe(Obligation, goals);
        defer self.allocator.free(owned_goals);
        for (owned_goals) |goal| {
            inline for (.{ "ty", "other", "result", "signature" }) |field| if (@field(goal, field) >= self.nodes.items.len) return error.TypeMismatch;
        }
        const point = self.mark();
        errdefer self.rollback(point);
        const span = try self.saveList(binders);
        const owner = try self.add(.{ .tag = tag, .a = body, .b = span.start, .c = span.len });
        if (owned_goals.len != 0) {
            const stored = try self.saveQuantifierGoals(owned_goals);
            try self.quantifier_goals.append(self.allocator, .{ .owner = owner, .goals = stored });
        }
        return owner;
    }
    /// Only a written rank annotation may bind an outer inference slot to a
    /// quantifier. Ordinary unification keeps impredicative inference disabled.
    pub fn bindRankAnnotation(self: *Store, slot: Id, required: Id) Error!void {
        const root = try self.resolve(slot, 0);
        if (self.node(root).tag != .variable) return self.unify(root, required);
        var quantified_root = required;
        if (self.node(quantified_root).tag == .usage) quantified_root = self.node(quantified_root).a;
        if (self.node(quantified_root).tag != .forall) return error.TypeMismatch;
        if (try self.occurs(self.node(root).a, required)) return error.InfiniteType;
        try self.appendVersion(root, required);
    }
    fn reownQuantified(self: *Store, tag: Tag, body: Id, binders: []const Id, goals: []Obligation) Error!Id {
        const replacements = try self.allocator.alloc(Id, binders.len);
        defer self.allocator.free(replacements);
        for (binders, replacements) |binder, *fresh_binder| {
            const leaf = self.node(binder);
            fresh_binder.* = try self.boundType(leaf.a, leaf.b);
        }
        const owned_body = try self.substitute(body, binders, replacements);
        for (goals) |*goal| goal.* = try self.substituteGoal(goal.*, binders, replacements);
        return self.quantifiedWithGoals(tag, owned_body, replacements, goals);
    }
    pub fn saveQuantifierGoals(self: *Store, goals: []const Obligation) Error!List {
        if (goals.len > 4096 or goals.len > std.math.maxInt(u32) - self.quantifier_obligations.items.len) return error.TypeLimit;
        const start: u32 = @intCast(self.quantifier_obligations.items.len);
        try self.quantifier_obligations.appendSlice(self.allocator, goals);
        return .{ .start = start, .len = @intCast(goals.len) };
    }
    pub fn substituteGoal(self: *Store, goal: Obligation, old: []const Id, fresh_ids: []const Id) Error!Obligation {
        var result = goal;
        inline for (.{ "ty", "other", "result", "signature" }) |field| {
            const child = @field(goal, field);
            if (child != 0) @field(result, field) = try self.substitute(child, old, fresh_ids);
        }
        if (goal.identity.unit == 0 and goal.identity.decl != 0) result.identity.decl = try self.substitute(goal.identity.decl, old, fresh_ids);
        return result;
    }
    pub const RankInstance = struct { body: Id, scope: u32 = 0, goals: List = .{} };
    pub fn instantiateRank(self: *Store, root: Id, skolemize: bool) Error!RankInstance {
        const resolved = try self.resolve(root, 0);
        const node_ = self.node(resolved);
        if (node_.tag != .forall and node_.tag != .existential) return error.TypeMismatch;
        const binders = try self.allocator.dupe(Id, self.list(.{ .start = node_.b, .len = node_.c }));
        defer self.allocator.free(binders);
        const replacements = try self.allocator.alloc(Id, binders.len);
        defer self.allocator.free(replacements);
        var scope: u32 = 0;
        if (skolemize) scope = try self.rigidScope();
        for (binders, replacements) |binder, *fresh_type| {
            const leaf = self.node(binder);
            if (leaf.tag != .bound or leaf.b > 2) return error.TypeMismatch;
            if (skolemize) {
                fresh_type.* = try self.rigid(scope, leaf.a, leaf.b);
            } else if (leaf.b == 1) {
                fresh_type.* = try self.freshRowType();
            } else if (leaf.b == 2) {
                fresh_type.* = try self.freshRegion();
            } else fresh_type.* = try self.fresh();
        }
        const source_goals = try self.allocator.dupe(Obligation, self.quantifierGoals(resolved));
        defer self.allocator.free(source_goals);
        for (source_goals) |*goal| goal.* = try self.substituteGoal(goal.*, binders, replacements);
        const goals = try self.saveQuantifierGoals(source_goals);
        return .{ .body = try self.substitute(node_.a, binders, replacements), .scope = scope, .goals = goals };
    }
    pub fn containsQuantifier(self: *Store, root: Id) Error!bool {
        if (!self.has_rank_types) return false;
        return @import("rank_walk.zig").quantified(self, root);
    }
    pub fn containsRigidRow(self: *Store, root: Effects.Id, scope: u32) Error!bool {
        if (!self.has_rank_types) return false;
        return @import("rank_walk.zig").containsRow(self, root, scope);
    }
    pub fn containsRigid(self: *Store, root: Id, scope: u32) Error!bool {
        if (!self.has_rank_types) return false;
        return @import("rank_walk.zig").contains(self, root, scope, false);
    }
    fn freeBound(self: *Store, root: Id) Error!bool {
        if (!self.has_rank_types) return false;
        return @import("rank_walk.zig").contains(self, root, 0, true);
    }
    pub fn fresh(self: *Store) Error!Id {
        const index: u32 = @intCast(self.variables.items.len);
        try self.variables.append(self.allocator, .{});
        errdefer _ = self.variables.pop();
        return self.variableView(index, 0);
    }
    pub fn freshRegion(self: *Store) Error!Id {
        const index: u32 = @intCast(self.variables.items.len);
        try self.variables.append(self.allocator, .{ .region = true });
        errdefer _ = self.variables.pop();
        self.has_rank_types = true;
        return self.variableView(index, 0);
    }
    /// Solver row handles stay private type variables. Immutable row tails
    /// point only to exact sort-one leaves owned by a written quantifier.
    pub fn freshRowType(self: *Store) Error!Id {
        const point = self.mark();
        errdefer self.rollback(point);
        const row_ = try self.freshEffects();
        const index: u32 = @intCast(self.variables.items.len);
        try self.variables.append(self.allocator, .{ .row_effect = row_ });
        self.has_rank_types = true;
        return self.variableView(index, 0);
    }
    pub fn rowType(self: *Store, root: Id) Error!Effects.Id {
        const resolved = try self.resolve(root, 0);
        const leaf = self.node(resolved);
        if (leaf.tag == .variable and self.variables.items[leaf.a].row_effect != none) return self.variables.items[leaf.a].row_effect;
        if ((leaf.tag == .bound and leaf.b == 1 and leaf.c == 0) or (leaf.tag == .rigid and leaf.c == 1)) return self.effects.row(&.{}, .{ .formal = resolved }) catch |err| return effectError(err);
        return error.TypeMismatch;
    }
    fn rowIdentity(self: *const Store, root: Id) bool {
        if (root >= self.nodes.items.len) return false;
        const leaf = self.node(self.head(root, 0));
        return switch (leaf.tag) {
            .variable => self.variables.items[leaf.a].row_effect != none,
            .bound => leaf.b == 1 and leaf.c == 0,
            .rigid => leaf.c == 1,
            else => false,
        };
    }
    fn regionIdentity(self: *const Store, root: Id) bool {
        if (root >= self.nodes.items.len) return false;
        const node_ = self.node(self.head(root, 0));
        return switch (node_.tag) {
            .variable => self.variables.items[node_.a].region,
            .bound => node_.b == 2,
            .rigid => node_.c == 2,
            else => false,
        };
    }
    /// A kind marker only. Exact propositions belong to the checked body's
    /// value owner; matching this marker never establishes a witness.
    pub fn usage(self: *Store, payload: Id, kind: UsageKind, region: Id) Error!Id {
        if (payload == absent or payload >= self.nodes.items.len) return error.TypeMismatch;
        if (self.node(self.head(payload, 0)).tag == .erased_proof) return error.TypeMismatch;
        if (kind == .shared and try @import("usage_check.zig").affine(self, payload)) return error.TypeMismatch;
        const loan = kind == .borrow or kind == .borrow_mut;
        if (loan != (region != 0)) return error.TypeMismatch;
        if (loan and !self.regionIdentity(region)) return error.TypeMismatch;
        self.has_usage_types = true;
        return self.add(.{ .tag = .usage, .a = payload, .b = @backingInt(kind), .c = region });
    }
    pub fn proofKind(self: *Store) Error!Id {
        const marker = try self.add(.{ .tag = .erased_proof });
        self.has_proof_kinds = true;
        return marker;
    }
    fn dataKind(self: *const Store, root: Id) Error!void {
        if (self.has_rank_types and (self.regionIdentity(root) or self.rowIdentity(root))) return error.TypeMismatch;
        if (!self.has_proof_kinds) return;
        if (self.node(self.head(root, 0)).tag == .erased_proof) return error.TypeMismatch;
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
        if (self.has_rank_types and (self.regionIdentity(parameter) or self.regionIdentity(result) or self.rowIdentity(parameter) or self.rowIdentity(result))) return error.TypeMismatch;
        return self.add(.{ .tag = .function, .a = parameter, .b = result, .c = effect_row });
    }
    pub fn product(self: *Store, fields: []const Id) Error!Id {
        for (fields) |field| try self.dataKind(field);
        const span = try self.saveList(fields);
        return self.add(.{ .tag = .product, .a = span.start, .b = span.len });
    }
    pub fn array(self: *Store, element: Id) Error!Id {
        try self.dataKind(element);
        return self.add(.{ .tag = .array, .a = element });
    }
    pub fn sequence(self: *Store, tag: Tag, element: Id) Error!Id {
        std.debug.assert(tag == .array or tag == .list or tag == .cursor);
        try self.dataKind(element);
        return self.add(.{ .tag = tag, .a = element });
    }
    pub fn demand(self: *Store, element: Id) Error!Id {
        return self.demandWithEffects(element, 0);
    }
    pub fn demandWithEffects(self: *Store, element: Id, effect_row: Effects.Id) Error!Id {
        try self.dataKind(element);
        return self.add(.{ .tag = .demand, .a = element, .c = effect_row });
    }
    pub fn typeConstructor(self: *Store, identity: NominalIdentity) Error!Id {
        return self.add(.{ .tag = .type_constructor, .a = identity.unit, .b = identity.decl });
    }
    pub fn resolver(self: *Store, token: Id) Error!Id {
        try self.dataKind(token);
        return self.add(.{ .tag = .resolver, .a = token });
    }
    /// The nominal child identifies an operation and its shaped arguments,
    /// without borrowing a local effect catalog label. Implementation effects
    /// remain latent until the provider is installed.
    pub fn provider(self: *Store, operation_type: Id, implementation_effects: Effects.Id) Error!Id {
        try self.dataKind(operation_type);
        return self.add(.{ .tag = .provider, .a = operation_type, .c = implementation_effects });
    }
    pub fn stateProvider(self: *Store, read: Id, write: Id, state_type: Id) Error!Id {
        try self.dataKind(state_type);
        return self.add(.{ .tag = .state_provider, .a = read, .b = write, .c = state_type });
    }
    pub fn record(self: *Store, fields: []const Field) Error!Id {
        for (fields) |field| try self.dataKind(field.ty);
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
        try self.dataKind(descriptor);
        return self.add(.{ .tag = .scoped, .a = descriptor, .b = instance.unit, .c = instance.decl });
    }
    pub fn capabilityParameter(self: *Store, descriptor: Id) Error!Id {
        return self.scoped(descriptor, .{ .unit = 0, .decl = try self.fresh() });
    }
    fn resolveInstance(self: *Store, instance: NominalIdentity, at: Cursor, depth: usize) Error!NominalIdentity {
        if (instance.unit != 0 or instance.decl == 0) return instance;
        const bound = try self.resolveDepth(instance.decl, at, depth + 1);
        const value = self.node(bound);
        if (value.tag == .variable or value.tag == .instance_selection or self.regionIdentity(bound)) return .{ .unit = 0, .decl = bound };
        if (value.tag != .scoped) return error.TypeMismatch;
        return .{ .unit = value.b, .decl = value.c };
    }
    pub fn instanceVersion(self: *Store, identity: NominalIdentity, ordinal: u32) Error!Id {
        if (identity.unit == 0 or identity.decl == 0 or identity.decl >= 0x04000000 or ordinal >= 16) return error.TypeMismatch;
        return self.add(.{ .tag = .instance_version, .a = identity.unit, .b = identity.decl, .c = ordinal });
    }
    pub fn instanceSelection(self: *Store, identity: NominalIdentity, arguments: []const Id) Error!Id {
        if (identity.unit == 0 or identity.decl == 0 or (arguments.len != 2 and arguments.len != 3)) return error.TypeMismatch;
        for (arguments[0..2]) |argument| if (argument >= self.nodes.items.len or self.node(argument).tag != .scoped) return error.TypeMismatch;
        if (arguments.len == 3 and (arguments[2] >= self.nodes.items.len or self.node(arguments[2]).tag != .instance_version)) return error.TypeMismatch;
        if (self.nodes.items.len > 65_536) return error.TypeLimit;
        for (self.nodes.items, 0..) |value, index| {
            if (value.tag != .instance_selection or value.a != identity.unit or value.b != identity.decl) continue;
            const choices = self.nominalArguments(value);
            if (choices.len != arguments.len) continue;
            if (choices.len == 3 and !std.meta.eql(self.node(choices[2]), self.node(arguments[2]))) continue;
            // Payload writes do not create a new value identity. Each origin
            // retains its descriptor separately from its exact owner term.
            var same = true;
            for (choices[0..2], arguments[0..2]) |choice, argument| {
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
        for (arguments) |argument| try self.dataKind(argument);
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
        for (arguments) |argument| try self.dataKind(argument);
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
        return .{ .nodes = self.nodes.items.len, .extra = self.extra.items.len, .variables = self.variables.items.len, .versions = self.versions.items.len, .operations = self.operations.items.len, .quantifier_goals = self.quantifier_goals.items.len, .quantifier_obligations = self.quantifier_obligations.items.len, .effects = self.effects.mark() };
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
        self.unlinkOperations(point.operations);
        self.operations.shrinkRetainingCapacity(point.operations);
        self.quantifier_goals.shrinkRetainingCapacity(point.quantifier_goals);
        self.quantifier_obligations.shrinkRetainingCapacity(point.quantifier_obligations);
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
        if (old.row_effect != none) {
            if (!self.rowIdentity(replacement_id)) return error.TypeMismatch;
        } else if (old.region) {
            if (!self.regionIdentity(replacement_id)) return error.TypeMismatch;
        } else try self.dataKind(replacement_id);
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
        if (version == none) return null;
        const first = self.versions.items[version];
        if (first.position >= at) return first;
        if (self.versions.items[self.variables.items[index].last].position < at) return null;
        version = first.next;
        while (version != none) : (version = self.versions.items[version].next) {
            const value = self.versions.items[version];
            if (value.position >= at) return value;
        }
        return null;
    }
    /// The caller supplies a complete selected proof. Both roots belong to this
    /// solver; freezing resolves the equation and retains no mutable lookup.
    pub fn bindAssociated(self: *Store, projection_: Id, result: Id) Error!void {
        try self.dataKind(result);
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
                .usage => blk: {
                    children = .{ n.a, n.c, 0 };
                    if (n.c != 0) break :blk children[0..2];
                    break :blk children[0..1];
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
            .forall, .existential => {
                const binders = try self.allocator.dupe(Id, self.list(.{ .start = value.b, .len = value.c }));
                defer self.allocator.free(binders);
                const body = try self.resolveDepth(value.a, position, depth + 1);
                const goals = try self.allocator.dupe(Obligation, self.quantifierGoals(id));
                defer self.allocator.free(goals);
                var changed = body != value.a;
                for (goals) |*goal| {
                    inline for (.{ "ty", "other", "result", "signature" }) |field| {
                        const child = @field(goal.*, field);
                        if (child != 0) {
                            const resolved_child = try self.resolveDepth(child, position, depth + 1);
                            changed = changed or child != resolved_child;
                            @field(goal.*, field) = resolved_child;
                        }
                    }
                }
                if (!changed) return id;
                return self.reownQuantified(value.tag, body, binders, goals);
            },
            .usage => {
                const payload = try self.resolveDepth(value.a, position, depth + 1);
                var region = value.c;
                if (region != 0) region = try self.resolveDepth(region, position, depth + 1);
                if (payload == value.a and region == value.c) return id;
                return self.usage(payload, @fromBackingInt(@intCast(value.b)), region);
            },
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
                .usage => {
                    try pending.append(scratch_allocator, value.a);
                    if (value.c != 0) try pending.append(scratch_allocator, value.c);
                },
                .scoped => {
                    try pending.append(scratch_allocator, value.a);
                    if (value.b == 0) try pending.append(scratch_allocator, value.c);
                },
                .forall, .existential => {
                    try pending.append(scratch_allocator, value.a);
                    for (self.quantifierGoals(id)) |goal| {
                        inline for (.{ "ty", "other", "result", "signature" }) |field| if (@field(goal, field) != 0) try pending.append(scratch_allocator, @field(goal, field));
                    }
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
        self.normalization.row_requests += 1;
        if (depth >= 1024) return error.TypeLimit;
        const id = self.effects.resolve(root, at) catch |err| return effectError(err);
        const row_ = self.row(id);
        if (row_.labels.len == 0) return id;
        if (self.use_closed_rows and self.use_closed_graphs and id >= self.closed_row_index.items.len) {
            const previous = self.closed_row_index.items.len;
            try self.closed_row_index.resize(self.allocator, self.effects.rows.items.len);
            @memset(self.closed_row_index.items[previous..], .{});
            // Preserve fallback proofs already built during type construction.
            for (self.closed_rows) |value| if (value.row >= previous and value.row < self.closed_row_index.items.len) {
                self.closed_row_index.items[value.row] = .{ .generation = value.generation, .argument_height = value.argument_height, .has_arguments = value.has_arguments };
            };
        }
        if (self.closedRow(id)) |cached| {
            self.normalization.closed_row_hits += 1;
            // No-argument operations have no argument-depth check in the
            // ordinary resolver. A row height alone cannot express that case.
            if (cached.has_arguments and depth + 1 + cached.argument_height > self.resolution_depth_limit) return error.TypeLimit;
            return id;
        }
        // Unresolved arguments cannot receive a closed certificate. Repeated
        // queries within the exact same history can still reuse normalization.
        // Writes and both rollback paths advance these non-recycled clocks.
        const mutation = self.mutation_epoch;
        const effects = self.effects.mutation_epoch;
        const cacheable = self.use_operation_rows and self.use_resolution_cache and mutation != std.math.maxInt(u64) and effects != std.math.maxInt(u64);
        const slot = id % self.operation_rows.len;
        if (cacheable) {
            const saved = self.operation_rows[slot];
            if (saved.row == id and saved.at == at and saved.depth == depth and saved.limit == self.resolution_depth_limit and saved.mutation == mutation and saved.effects == effects) {
                self.normalization.epoch_row_hits += 1;
                return saved.result;
            }
        }
        const result = try self.resolveOperationArguments(id, at, depth);
        if (cacheable and self.mutation_epoch == mutation and self.effects.mutation_epoch == effects) self.operation_rows[slot] = .{ .row = id, .result = result, .at = at, .depth = depth, .limit = self.resolution_depth_limit, .mutation = mutation, .effects = effects };
        return result;
    }
    fn resolveOperationArguments(self: *Store, id: Effects.Id, at: Cursor, depth: usize) Error!Effects.Id {
        self.normalization.argument_rows += 1;
        if (self.use_closed_rows and self.use_closed_graphs and self.closed_operation_index.items.len < self.operations.items.len) {
            const before = self.closed_operation_index.items.len;
            try self.closed_operation_index.resize(self.allocator, self.operations.items.len);
            @memset(self.closed_operation_index.items[before..], .{});
        }
        const row_ = self.row(id);
        // Resolving the row above already selects its chronological tail.
        // This certificate covers only immutable operation arguments: an
        // open tail does not make those arguments change. closedRowHeight
        // separately requires a closed tail before certifying a whole type.
        var all_closed = true;
        var argument_height: u8 = 0;
        var has_arguments = false;
        var labels: std.ArrayList(Effects.Label) = .empty;
        defer labels.deinit(self.allocator);
        var changed = false;
        for (0..row_.labels.len) |index| {
            const label = self.effects.list(row_.labels)[index];
            const operation_ = self.operation(label);
            self.normalization.labels += 1;
            self.normalization.arguments += operation_.arguments.len;
            if (self.closedOperation(label)) |proof| {
                self.normalization.closed_operation_hits += 1;
                has_arguments = has_arguments or proof.has_arguments;
                argument_height = @max(argument_height, proof.argument_height);
                if (proof.has_arguments and depth + 1 + proof.argument_height > self.resolution_depth_limit) return error.TypeLimit;
                if (changed) labels.appendAssumeCapacity(label);
                continue;
            }
            var closed = operation_.instance.unit != 0 or operation_.instance.decl == 0;
            var operation_height: u8 = 0;
            for (self.list(operation_.arguments)) |argument| {
                has_arguments = true;
                const height = self.closedHeight(argument);
                self.normalization.argument_height_checks += 1;
                argument_height = @max(argument_height, height);
                operation_height = @max(operation_height, height);
                if (height == 0) closed = false;
                if (height != 0 and depth + 1 + height > self.resolution_depth_limit) return error.TypeLimit;
            }
            all_closed = all_closed and closed;
            if (closed) {
                self.saveClosedOperation(label, operation_height, operation_.arguments.len != 0);
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
        if (!changed) {
            if (all_closed) self.saveClosedRow(id, argument_height, has_arguments);
            return id;
        }
        self.normalization.changed_rows += 1;
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
            try self.dataKind(ty);
            if (!symbolic and !try self.equalClosed(ty, ty)) return error.TypeMismatch;
            try resolved.append(scratch_allocator, ty);
        }
        return self.internResolvedOperation(identity, instance, resolved.items, symbolic);
    }
    fn internResolvedOperation(self: *Store, identity: NominalIdentity, instance: NominalIdentity, resolved: []const Id, symbolic: bool) Error!Effects.Label {
        self.normalization.interner_requests += 1;
        const point = self.mark();
        errdefer self.rollback(point);
        try self.linkOperations();
        // Only candidates sharing identity, instance and arity can match; the
        // chain visits them in index order, so the oldest equal one wins.
        if (resolved.len <= std.math.maxInt(u32)) if (self.operation_chains.get(.{ .identity = identity, .instance = instance, .arity = @intCast(resolved.len), .shape = self.operationShape(resolved) })) |chain| {
            var index = chain.first;
            while (index != none) : (index = self.operation_links.items[index].next) {
                self.normalization.interner_candidates += 1;
                const old = self.list(self.operations.items[index].arguments);
                var same = true;
                for (old, resolved) |a, b| {
                    if (!same) break;
                    self.normalization.interner_arguments += 1;
                    same = try self.equalGraph(a, b, symbolic);
                }
                if (same) return index;
            }
        };
        if (self.operations.items.len == none) return error.TypeLimit;
        const span = try self.saveList(resolved);
        const id: Effects.Label = @intCast(self.operations.items.len);
        try self.operations.append(self.allocator, .{ .identity = identity, .arguments = span, .instance = instance });
        return id;
    }
    /// A bounded structural prefilter, never an equality proof. It excludes
    /// graph ordinals, record order and closedness metadata. Equal symbolic or
    /// closed arguments therefore select the same bucket even when allocated
    /// independently. Projections retain ordinary per-pair budget accounting.
    fn operationShape(self: *const Store, arguments: []const Id) u64 {
        if (!self.operation_shape_enabled) return 0;
        var hash: u64 = arguments.len;
        for (arguments[0..@min(arguments.len, 4)]) |argument| hash = mixShape(hash, self.operationTypeShape(argument, 2));
        return hash;
    }
    fn mixShape(left: u64, right: u64) u64 {
        return (left ^ right) *% 0x9e3779b97f4a7c15 +% 0x85ebca6b;
    }
    fn operationTypeShape(self: *const Store, id: Id, depth: usize) u64 {
        const n = self.node(id);
        var hash: u64 = @backingInt(n.tag);
        switch (n.tag) {
            .variable, .nominal, .type_constructor, .instance_selection => hash = mixShape(mixShape(hash, n.a), n.b),
            .rigid, .instance_version => hash = mixShape(mixShape(mixShape(hash, n.a), n.b), n.c),
            .record, .product => hash = mixShape(hash, n.b),
            .usage => hash = mixShape(mixShape(hash, n.b), @intFromBool(n.c != 0)),
            .scoped => hash = mixShape(mixShape(hash, n.b), if (n.b != 0) n.c else 0),
            else => {},
        }
        if (depth == 0) return hash;
        switch (n.tag) {
            .array, .list, .cursor, .resolver, .demand, .provider, .usage, .scoped => hash = mixShape(hash, self.operationTypeShape(n.a, depth - 1)),
            .function => {
                hash = mixShape(hash, self.operationTypeShape(n.a, depth - 1));
                hash = mixShape(hash, self.operationTypeShape(n.b, depth - 1));
            },
            // These children are ordered. Record fields deliberately are not.
            .product => for (self.list(.{ .start = n.a, .len = @min(n.b, 2) })) |child| {
                hash = mixShape(hash, self.operationTypeShape(child, depth - 1));
            },
            else => {},
        }
        return hash;
    }
    /// Links every operation appended since the last call into its chain.
    fn linkOperations(self: *Store) Error!void {
        const enabled = self.use_operation_shapes and !self.has_projections and self.closed_generation != std.math.maxInt(u16);
        // Slot 0 is never interned; a shrink outside rollback relinks.
        if (self.operation_links.items.len > self.operations.items.len or self.operation_shape_generation != self.closed_generation or self.operation_shape_enabled != enabled) {
            self.normalization.interner_rebuilds += 1;
            self.operation_chains.clearRetainingCapacity();
            self.operation_links.clearRetainingCapacity();
        }
        self.operation_shape_generation = self.closed_generation;
        self.operation_shape_enabled = enabled;
        if (self.operation_links.items.len == 0) try self.operation_links.append(self.allocator, .{});
        while (self.operation_links.items.len < self.operations.items.len) {
            self.normalization.interner_linked += 1;
            const index: Effects.Label = @intCast(self.operation_links.items.len);
            const operation_ = self.operations.items[index];
            try self.operation_links.ensureUnusedCapacity(self.allocator, 1);
            const shape = self.operationShape(self.list(operation_.arguments));
            const entry = try self.operation_chains.getOrPut(self.allocator, .{ .identity = operation_.identity, .instance = operation_.instance, .arity = operation_.arguments.len, .shape = shape });
            if (entry.found_existing) {
                self.operation_links.items[entry.value_ptr.last].next = index;
                self.operation_links.appendAssumeCapacity(.{ .previous = entry.value_ptr.last, .shape = shape });
                entry.value_ptr.last = index;
            } else {
                self.operation_links.appendAssumeCapacity(.{ .shape = shape });
                entry.value_ptr.* = .{ .first = index, .last = index };
            }
        }
    }
    /// Removes linked operations at or after `length`, newest first.
    fn unlinkOperations(self: *Store, length: usize) void {
        if (self.operation_links.items.len > self.operations.items.len) {
            self.operation_chains.clearRetainingCapacity();
            self.operation_links.clearRetainingCapacity();
        }
        while (self.operation_links.items.len > @max(length, 1)) {
            const index: Effects.Label = @intCast(self.operation_links.items.len - 1);
            const operation_ = self.operations.items[index];
            const key: OperationKey = .{ .identity = operation_.identity, .instance = operation_.instance, .arity = operation_.arguments.len, .shape = self.operation_links.items[index].shape };
            const chain = self.operation_chains.getPtr(key).?;
            std.debug.assert(chain.last == index);
            const previous = self.operation_links.pop().?.previous;
            if (previous == none) {
                _ = self.operation_chains.remove(key);
            } else {
                self.operation_links.items[previous].next = none;
                chain.last = previous;
            }
        }
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
        // Most operation-chain candidates disagree at the root. Avoid setting
        // up graph traversal for those exact negatives. Projection stores keep
        // the ordinary path because every visited pair owns budget accounting.
        if (!self.has_projections) {
            if (symbolic and left == right) return true;
            if (!symbolic and left == right and self.closedHeight(left) != 0) return true;
            const l = self.node(left);
            const r = self.node(right);
            if (l.tag != r.tag) return false;
            switch (l.tag) {
                .absent, .bound => return false,
                .unit, .boolean, .u32, .f32, .never => return true,
                .nominal, .instance_selection, .type_constructor => if (l.a != r.a or l.b != r.b) return false,
                else => {},
            }
        }
        return self.equalGraphWalk(left, right, symbolic);
    }
    fn equalGraphWalk(self: *const Store, left: Id, right: Id, symbolic: bool) Error!bool {
        // A positive certificate proves acyclic closed descendants. It is safe
        // to reuse visited pairs there; uncertified closed graphs retain the
        // ordinary walk and its rejection of cyclic/open inputs.
        const shared_closed = !symbolic and !self.has_projections and self.closedHeight(left) != 0 and self.closedHeight(right) != 0;
        var scratch_buffer: [512]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const scratch_allocator = scratch.allocator();
        const Pair = struct { a: Id, b: Id };
        var pending: std.ArrayList(Pair) = .empty;
        defer pending.deinit(scratch_allocator);
        try pending.append(scratch_allocator, .{ .a = left, .b = right });
        var seen: std.AutoHashMapUnmanaged(Pair, void) = .empty;
        defer seen.deinit(scratch_allocator);
        // Most comparisons visit a handful of pairs; they stay in this list
        // and the map takes over only once it is full.
        var few: [16]Pair = undefined;
        var few_count: usize = 0;
        var budget: usize = 1_000_000;
        while (pending.pop()) |pair| {
            if (self.has_projections) try @constCast(self).chargeProjection();
            if (symbolic) {
                if (pair.a == pair.b) continue;
            }
            // Closed equality must inspect each leaf even for identical roots.
            // Associated selections can share exponentially many paths to that
            // leaf, so visit each pair once without treating identity as proof.
            if (symbolic or self.has_projections or shared_closed) {
                if (few_count < few.len) {
                    const repeated = for (few[0..few_count]) |prior| {
                        if (prior.a == pair.a and prior.b == pair.b) break true;
                    } else false;
                    if (repeated) continue;
                    few[few_count] = pair;
                    few_count += 1;
                } else {
                    if (seen.count() == 0) for (few) |prior| try seen.put(scratch_allocator, prior, {});
                    const entry = try seen.getOrPut(scratch_allocator, pair);
                    if (entry.found_existing) continue;
                }
            }
            if (budget == 0) return error.TypeLimit;
            budget -= 1;
            const a = self.node(pair.a);
            const b = self.node(pair.b);
            if (a.tag != b.tag) return false;
            switch (a.tag) {
                .bound => return false,
                .rigid => if (!symbolic or a.a != b.a or a.b != b.b or a.c != b.c) return false,
                .usage => {
                    if (a.b != b.b or (a.c == 0) != (b.c == 0)) return false;
                    try pending.append(scratch_allocator, .{ .a = a.a, .b = b.a });
                    if (a.c != 0) try pending.append(scratch_allocator, .{ .a = a.c, .b = b.c });
                },
                .forall, .existential => if (!try @import("rank_equal.zig").equal(self, pair.a, pair.b, symbolic)) return false,
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
                    if (!try equalLabelMultisets(scratch_allocator, self.effects.list(ar.labels), self.effects.list(br.labels))) return false;
                    for (self.effects.list(ar.labels)) |label| {
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
                    if (a.b != b.b) return false;
                    if (a.b == 0) {
                        try pending.append(scratch_allocator, .{ .a = a.c, .b = b.c });
                    } else if (a.c != b.c) return false;
                    try pending.append(scratch_allocator, .{ .a = a.a, .b = b.a });
                },
                .instance_version => if (a.a != b.a or a.b != b.b or a.c != b.c) return false,
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
                    var fields: std.AutoHashMapUnmanaged(u32, Id) = .empty;
                    defer fields.deinit(scratch_allocator);
                    if (b.b > 16) {
                        try fields.ensureTotalCapacity(scratch_allocator, b.b);
                        for (0..b.b) |j| {
                            const other = self.recordField(b, j);
                            const entry = fields.getOrPutAssumeCapacity(other.name);
                            // Preserve the reference walk's first-match rule.
                            if (!entry.found_existing) entry.value_ptr.* = other.ty;
                        }
                    }
                    for (0..a.b) |i| {
                        const field = self.recordField(a, i);
                        if (b.b > 16) {
                            try pending.append(scratch_allocator, .{ .a = field.ty, .b = fields.get(field.name) orelse return false });
                            continue;
                        }
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
    fn equalLabelMultisets(allocator: std.mem.Allocator, left: []const Effects.Label, right: []const Effects.Label) std.mem.Allocator.Error!bool {
        if (left.len != right.len) return false;
        if (std.mem.eql(Effects.Label, left, right)) return true;
        if (left.len <= 16) {
            for (left) |label| {
                var before: usize = 0;
                var after: usize = 0;
                for (left) |value| before += @intFromBool(value == label);
                for (right) |value| after += @intFromBool(value == label);
                if (before != after) return false;
            }
            return true;
        }
        var counts: std.AutoHashMapUnmanaged(Effects.Label, usize) = .empty;
        defer counts.deinit(allocator);
        for (left) |label| {
            const entry = try counts.getOrPut(allocator, label);
            if (!entry.found_existing) entry.value_ptr.* = 0;
            entry.value_ptr.* += 1;
        }
        for (right) |label| {
            const count = counts.getPtr(label) orelse return false;
            if (count.* == 0) return false;
            count.* -= 1;
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
        var rank_active = false;
        var rank_remaining: usize = 4096;
        while (pending.pop()) |pair| {
            if (rank_active) {
                if (rank_remaining == 0) return error.TypeLimit;
                rank_remaining -= 1;
            }
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
            const an = self.node(a);
            const bn = self.node(b);
            if (self.rowIdentity(a) or self.rowIdentity(b)) {
                if (!self.rowIdentity(a) or !self.rowIdentity(b)) return self.mismatch(reporter, a, b);
                try self.unifyEffects(try self.rowType(a), try self.rowType(b));
                continue;
            }
            if (an.tag == .variable and self.variables.items[an.a].region and !self.regionIdentity(b)) return self.mismatch(reporter, a, b);
            if (bn.tag == .variable and self.variables.items[bn.a].region and !self.regionIdentity(a)) return self.mismatch(reporter, a, b);
            if (a == b or a == never or b == never) continue;
            if (self.has_rank_types and (an.tag == .forall or an.tag == .existential or an.tag == .bound or an.tag == .rigid or bn.tag == .forall or bn.tag == .existential or bn.tag == .bound or bn.tag == .rigid)) rank_active = true;
            if (bounded or rank_active) {
                const found = try seen.getOrPut(scratch_allocator, .{ .a = a, .b = b });
                if (found.found_existing) continue;
            }
            if (an.tag == .variable and bn.tag == .variable and an.a == bn.a) continue;
            if (an.tag == .variable) {
                if (bn.tag == .forall or (!self.variables.items[an.a].region and try self.freeBound(b))) return self.mismatch(reporter, a, b);
                if (try self.occurs(an.a, b)) return error.InfiniteType;
                try self.appendVersion(a, b);
            } else if (bn.tag == .variable) {
                if (an.tag == .forall or (!self.variables.items[bn.a].region and try self.freeBound(a))) return self.mismatch(reporter, a, b);
                if (try self.occurs(bn.a, a)) return error.InfiniteType;
                try self.appendVersion(b, a);
            } else if (an.tag != bn.tag) return self.mismatch(reporter, a, b) else switch (an.tag) {
                .usage => {
                    if (an.b != bn.b or (an.c == 0) != (bn.c == 0)) return self.mismatch(reporter, a, b);
                    try pending.append(scratch_allocator, .{ .a = an.a, .b = bn.a });
                    if (an.c != 0) try pending.append(scratch_allocator, .{ .a = an.c, .b = bn.c });
                },
                .bound => return self.mismatch(reporter, a, b),
                .rigid, .instance_version => if (an.a != bn.a or an.b != bn.b or an.c != bn.c) return self.mismatch(reporter, a, b),
                .forall, .existential => {
                    if (an.c != bn.c) return self.mismatch(reporter, a, b);
                    const old = try scratch_allocator.dupe(Id, self.list(.{ .start = bn.b, .len = bn.c }));
                    defer scratch_allocator.free(old);
                    const fresh_ids = try scratch_allocator.dupe(Id, self.list(.{ .start = an.b, .len = an.c }));
                    defer scratch_allocator.free(fresh_ids);
                    for (old, fresh_ids) |left_, right_| if (self.node(left_).b != self.node(right_).b) return self.mismatch(reporter, a, b);
                    const left_goals = try scratch_allocator.dupe(Obligation, self.quantifierGoals(a));
                    defer scratch_allocator.free(left_goals);
                    const right_goals = try scratch_allocator.dupe(Obligation, self.quantifierGoals(b));
                    defer scratch_allocator.free(right_goals);
                    if (left_goals.len != right_goals.len) return self.mismatch(reporter, a, b);
                    for (left_goals, right_goals) |left_goal, right_goal| {
                        if (!@import("quantifier_goals.zig").sameHead(left_goal, right_goal)) return self.mismatch(reporter, a, b);
                        const replaced = try self.substituteGoal(right_goal, old, fresh_ids);
                        inline for (.{ "ty", "other", "result", "signature" }) |field| {
                            const left_child = @field(left_goal, field);
                            const right_child = @field(replaced, field);
                            if ((left_child == 0) != (right_child == 0)) return self.mismatch(reporter, a, b);
                            if (left_child != 0) try pending.append(scratch_allocator, .{ .a = left_child, .b = right_child });
                        }
                    }
                    const body = try self.substitute(bn.a, old, fresh_ids);
                    try pending.append(scratch_allocator, .{ .a = an.a, .b = body });
                },
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
                    // An ordinary capability parameter binds to the whole
                    // scoped carrier. A sorted region binds to its identity.
                    // Prefer the carrier variable when the two meet.
                    if (an.b == 0 and self.node(an.c).tag == .variable and !self.regionIdentity(an.c)) {
                        if (bn.b != 0 or an.c != bn.c) try pending.append(scratch_allocator, .{ .a = an.c, .b = b });
                    } else if (bn.b == 0 and self.node(bn.c).tag == .variable and !self.regionIdentity(bn.c)) {
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
                .usage => {
                    try pending.append(temporary, value.a);
                    if (value.c != 0) try pending.append(temporary, value.c);
                },
                .scoped => {
                    try pending.append(temporary, value.a);
                    if (value.b == 0) try pending.append(temporary, value.c);
                },
                .forall, .existential => {
                    try pending.append(temporary, value.a);
                    for (self.quantifierGoals(id)) |goal| {
                        inline for (.{ "ty", "other", "result", "signature" }) |field| if (@field(goal, field) != 0) try pending.append(temporary, @field(goal, field));
                    }
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
                .usage => {
                    try pending.append(self.allocator, .{ .root = n.a });
                    if (n.c != 0) try pending.append(self.allocator, .{ .root = n.c });
                },
                .forall, .existential => {
                    try pending.append(self.allocator, .{ .root = n.a });
                    for (self.quantifierGoals(id)) |goal| {
                        inline for (.{ "ty", "other", "result", "signature" }) |field| if (@field(goal, field) != 0) try pending.append(self.allocator, .{ .root = @field(goal, field) });
                    }
                },
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
            .usage => return self.usage(try self.closeCovariantDepth(value.a, generalized, protected, decisions, memo, depth + 1), @fromBackingInt(@intCast(value.b)), value.c),
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
            .usage, .array, .list, .cursor => try self.covariantInputsSeen(value.a, out, depth + 1, seen),
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
            .usage => {
                // Cleanup descriptors promise one exact non-suspending host role.
                // Reopening their row would erase that portable authority.
                if (value.b == @backingInt(UsageKind.cleanup) or value.b == @backingInt(UsageKind.concurrent)) return root;
                return self.usage(try self.openCovariantDepth(value.a, memo, depth + 1), @fromBackingInt(@intCast(value.b)), value.c);
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
                .usage => {
                    try pending.append(temporary, .{ .id = value.a, .at = at, .depth = work.depth + 1 });
                    if (value.c != 0) try pending.append(temporary, .{ .id = value.c, .at = at, .depth = work.depth + 1 });
                },
                .forall, .existential => {
                    try pending.append(temporary, .{ .id = value.a, .at = at, .depth = work.depth + 1 });
                    for (self.quantifierGoals(id)) |goal| {
                        inline for (.{ "ty", "other", "result", "signature" }) |field| if (@field(goal, field) != 0) try pending.append(temporary, .{ .id = @field(goal, field), .at = at, .depth = work.depth + 1 });
                    }
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
    /// One instantiation applied to several roots, such as a scheme's root
    /// and each of its obligations. Every root still gets its own copy, made
    /// exactly as `substituteWithRows` makes it. Large binder lists are found
    /// by index instead of a scan, and the replacement kinds are checked
    /// again only after a store write that could change their answer.
    pub const Substitution = struct {
        old: []const Id,
        fresh_ids: []const Id,
        old_rows: []const u32,
        fresh_rows: []const Effects.Id,
        /// First position of each old binder, present only for long lists.
        leaves: std.AutoHashMapUnmanaged(Id, u32) = .empty,
        row_leaves: std.AutoHashMapUnmanaged(u32, u32) = .empty,
        /// Store state under which every replacement last passed its check.
        checked: ?KindStamp = null,

        const indexed_length = 16;
        const KindStamp = struct { mutation_epoch: u64, rank_types: bool, proof_kinds: bool };

        pub fn deinit(self: *Substitution, allocator: std.mem.Allocator) void {
            self.leaves.deinit(allocator);
            self.row_leaves.deinit(allocator);
            self.* = undefined;
        }
        fn typeIndex(self: *const Substitution, root: Id) ?usize {
            if (self.leaves.count() != 0) return if (self.leaves.get(root)) |index| index else null;
            for (self.old, 0..) |before, index| if (before == root) return index;
            return null;
        }
        /// First row binder at or after `from` naming `variable`.
        fn rowIndex(self: *const Substitution, variable: u32, from: usize) ?usize {
            if (from == 0 and self.row_leaves.count() != 0) return if (self.row_leaves.get(variable)) |index| index else null;
            for (self.old_rows[from..], from..) |before, index| if (before == variable) return index;
            return null;
        }
    };
    /// Borrows the four lists; the caller keeps them alive until `deinit`.
    pub fn prepareSubstitution(self: *Store, old: []const Id, fresh_ids: []const Id, old_rows: []const u32, fresh_rows: []const Effects.Id) Error!Substitution {
        std.debug.assert(old.len == fresh_ids.len and old_rows.len == fresh_rows.len);
        var result: Substitution = .{ .old = old, .fresh_ids = fresh_ids, .old_rows = old_rows, .fresh_rows = fresh_rows };
        errdefer result.deinit(self.allocator);
        if (old.len > Substitution.indexed_length) {
            try result.leaves.ensureTotalCapacity(self.allocator, @intCast(old.len));
            for (old, 0..) |before, index| {
                const entry = result.leaves.getOrPutAssumeCapacity(before);
                if (!entry.found_existing) entry.value_ptr.* = @intCast(index);
            }
        }
        if (old_rows.len > Substitution.indexed_length) {
            try result.row_leaves.ensureTotalCapacity(self.allocator, @intCast(old_rows.len));
            for (old_rows, 0..) |before, index| {
                const entry = result.row_leaves.getOrPutAssumeCapacity(before);
                if (!entry.found_existing) entry.value_ptr.* = @intCast(index);
            }
        }
        return result;
    }
    /// Substitute quantified scheme variables, without writing solver history.
    pub fn substitute(self: *Store, root: Id, old: []const Id, fresh_ids: []const Id) Error!Id {
        return self.substituteWithRows(root, old, fresh_ids, &.{}, &.{});
    }
    pub fn substituteWithRows(self: *Store, root: Id, old: []const Id, fresh_ids: []const Id, old_rows: []const u32, fresh_rows: []const Effects.Id) Error!Id {
        std.debug.assert(old.len == fresh_ids.len and old_rows.len == fresh_rows.len);
        var substitution: Substitution = .{ .old = old, .fresh_ids = fresh_ids, .old_rows = old_rows, .fresh_rows = fresh_rows };
        return self.substitutePrepared(&substitution, root);
    }
    pub fn substitutePrepared(self: *Store, substitution: *Substitution, root: Id) Error!Id {
        try self.checkReplacementKinds(substitution);
        // A monomorphic scheme needs no type copying. Keep its raw historical
        // view; callers still reopen eligible covariant latent rows separately.
        if (substitution.old.len == 0 and substitution.old_rows.len == 0) return root;
        var scratch_buffer: [1024]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        var copied: std.AutoHashMapUnmanaged(Id, Id) = .empty;
        defer copied.deinit(scratch.allocator());
        return self.substituteDepth(root, substitution, &copied, scratch.allocator(), 0);
    }
    /// The answer reads only resolved heads (every write, rollback and
    /// associated equation advances `mutation_epoch`), variable kinds fixed
    /// at creation, and the two store-wide kind flags.
    fn checkReplacementKinds(self: *Store, substitution: *Substitution) Error!void {
        const stamp: Substitution.KindStamp = .{ .mutation_epoch = self.mutation_epoch, .rank_types = self.has_rank_types, .proof_kinds = self.has_proof_kinds };
        if (substitution.checked) |checked| if (stamp.mutation_epoch != std.math.maxInt(u64) and std.meta.eql(checked, stamp)) return;
        for (substitution.old, substitution.fresh_ids) |original, replacement_id| {
            const leaf = self.node(original);
            if ((leaf.tag == .bound and leaf.b == 1) or (leaf.tag == .rigid and leaf.c == 1)) {
                if (!self.rowIdentity(replacement_id)) return error.TypeMismatch;
            } else if ((leaf.tag == .bound and leaf.b == 2) or (leaf.tag == .rigid and leaf.c == 2)) {
                if (!self.regionIdentity(replacement_id)) return error.TypeMismatch;
            } else try self.dataKind(replacement_id);
        }
        substitution.checked = stamp;
    }
    fn substitutedRow(self: *Store, root: Effects.Id, substitution: *const Substitution, copied: *std.AutoHashMapUnmanaged(Id, Id), scratch: std.mem.Allocator, depth: usize) Error!Effects.Id {
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
                const next = try self.substituteDepth(argument, substitution, copied, scratch, depth + 1);
                argument_changed = argument_changed or next != argument;
                try arguments.append(scratch, next);
            }
            var instance = operation_.instance;
            if (instance.unit == 0 and instance.decl != 0) instance.decl = try self.substituteDepth(instance.decl, substitution, copied, scratch, depth + 1);
            var next = label;
            if (argument_changed or !std.meta.eql(instance, operation_.instance)) next = try self.internResolvedOperation(operation_.identity, instance, arguments.items, true);
            changed = changed or next != label;
            try labels.append(scratch, next);
        }
        var result = root;
        if (row_.tail == .formal) if (substitution.typeIndex(row_.tail.formal)) |index| {
            const replacement_row = try self.rowType(substitution.fresh_ids[index]);
            result = self.effects.substituteFormal(root, substitution.old[index], replacement_row) catch |err| return effectError(err);
        };
        if (changed) {
            const replaced = self.row(result);
            if (result != root) try labels.appendSlice(scratch, self.effects.list(replaced.labels)[row_.labels.len..]);
            result = self.effects.rowAt(labels.items, replaced.tail, @max(row_.cursor, replaced.cursor)) catch |err| return effectError(err);
        }
        // Binders apply in list order, and a replaced tail can meet a later
        // binder. Only the next matching binder can change the row.
        var from: usize = 0;
        while (from < substitution.old_rows.len) {
            const tail = self.effects.node(result).tail;
            if (tail != .variable) break;
            const index = substitution.rowIndex(tail.variable, from) orelse break;
            result = self.effects.substitute(result, substitution.old_rows[index], substitution.fresh_rows[index]) catch |err| return effectError(err);
            from = index + 1;
        }
        return result;
    }
    // A type graph is a DAG. Repeated children must retain sharing during
    // instantiation; aliases and generic signatures can otherwise expand a
    // linear graph into an exponential tree. The memo is local to this exact
    // substitution, so historical variable views and fresh identities stay exact.
    fn substituteDepth(self: *Store, root: Id, substitution: *const Substitution, copied: *std.AutoHashMapUnmanaged(Id, Id), scratch: std.mem.Allocator, depth: usize) Error!Id {
        if (self.has_projections) try self.chargeProjection();
        if (depth >= 1024) return error.TypeLimit;
        if (substitution.typeIndex(root)) |index| return substitution.fresh_ids[index];
        if (root <= never) return root;
        if (self.node(root).tag == .variable) return root;
        // The input graph is acyclic: the initial root cannot recur beneath
        // itself. Leaf signatures then need no memo allocation at all.
        if (depth != 0) if (copied.get(root)) |known| return known;
        const result = try self.substituteNode(root, substitution, copied, scratch, depth);
        if (depth != 0) try copied.put(scratch, root, result);
        return result;
    }
    fn substituteNode(self: *Store, root: Id, substitution: *const Substitution, copied: *std.AutoHashMapUnmanaged(Id, Id), scratch: std.mem.Allocator, depth: usize) Error!Id {
        if (depth >= 1024) return error.TypeLimit;
        const value = self.node(root);
        switch (value.tag) {
            .forall, .existential => {
                const binders = try self.allocator.dupe(Id, self.list(.{ .start = value.b, .len = value.c }));
                defer self.allocator.free(binders);
                const body = try self.substituteDepth(value.a, substitution, copied, scratch, depth + 1);
                const goals = try scratch.dupe(Obligation, self.quantifierGoals(root));
                defer scratch.free(goals);
                for (goals) |*goal| {
                    inline for (.{ "ty", "other", "result", "signature" }) |field| {
                        const child = @field(goal.*, field);
                        if (child != 0) @field(goal.*, field) = try self.substituteDepth(child, substitution, copied, scratch, depth + 1);
                    }
                }
                var changed = body != value.a;
                const originals = self.quantifierGoals(root);
                for (goals, originals) |goal, original| {
                    inline for (.{ "ty", "other", "result", "signature" }) |field| changed = changed or @field(goal, field) != @field(original, field);
                }
                if (!changed) return root;
                return self.reownQuantified(value.tag, body, binders, goals);
            },
            .usage => return self.usage(try self.substituteDepth(value.a, substitution, copied, scratch, depth + 1), @fromBackingInt(@intCast(value.b)), if (value.c == 0) 0 else try self.substituteDepth(value.c, substitution, copied, scratch, depth + 1)),
            .scoped => {
                const descriptor = try self.substituteDepth(value.a, substitution, copied, scratch, depth + 1);
                var instance: NominalIdentity = .{ .unit = value.b, .decl = value.c };
                if (instance.unit == 0) instance.decl = try self.substituteDepth(instance.decl, substitution, copied, scratch, depth + 1);
                return self.scoped(descriptor, instance);
            },
            .function => return self.functionWithEffects(try self.substituteDepth(value.a, substitution, copied, scratch, depth + 1), try self.substituteDepth(value.b, substitution, copied, scratch, depth + 1), try self.substitutedRow(value.c, substitution, copied, scratch, depth + 1)),
            .product => {
                var fields: std.ArrayList(Id) = .empty;
                defer fields.deinit(self.allocator);
                for (0..value.b) |i| try fields.append(self.allocator, try self.substituteDepth(self.extra.items[value.a + i], substitution, copied, scratch, depth + 1));
                return self.product(fields.items);
            },
            .array, .list, .cursor => return self.sequence(value.tag, try self.substituteDepth(value.a, substitution, copied, scratch, depth + 1)),
            .demand => return self.demandWithEffects(try self.substituteDepth(value.a, substitution, copied, scratch, depth + 1), try self.substitutedRow(value.c, substitution, copied, scratch, depth + 1)),
            .provider => return self.provider(try self.substituteDepth(value.a, substitution, copied, scratch, depth + 1), try self.substitutedRow(value.c, substitution, copied, scratch, depth + 1)),
            .state_provider => return self.stateProvider(try self.substituteDepth(value.a, substitution, copied, scratch, depth + 1), try self.substituteDepth(value.b, substitution, copied, scratch, depth + 1), try self.substituteDepth(value.c, substitution, copied, scratch, depth + 1)),
            .resolver => return self.resolver(try self.substituteDepth(value.a, substitution, copied, scratch, depth + 1)),
            .record => {
                var fields: std.ArrayList(Field) = .empty;
                defer fields.deinit(self.allocator);
                for (0..value.b) |i| {
                    const field = self.recordField(value, i);
                    try fields.append(self.allocator, .{ .name = field.name, .ty = try self.substituteDepth(field.ty, substitution, copied, scratch, depth + 1) });
                }
                return self.record(fields.items);
            },
            .nominal, .projection, .instance_selection => {
                const prior = try self.allocator.dupe(Id, self.nominalArguments(value));
                defer self.allocator.free(prior);
                var args: std.ArrayList(Id) = .empty;
                defer args.deinit(self.allocator);
                for (prior) |child| try args.append(self.allocator, try self.substituteDepth(child, substitution, copied, scratch, depth + 1));
                if (value.tag == .projection) return self.projection(.{ .unit = value.a, .decl = value.b }, self.projectionMember(value), args.items);
                if (value.tag == .instance_selection) return self.instanceSelection(.{ .unit = value.a, .decl = value.b }, args.items);
                return self.nominal(.{ .unit = value.a, .decl = value.b }, args.items);
            },
            else => return root,
        }
    }
};

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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, sharedOccursLaw, .{});
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, VariableScratchTests.histories, .{});
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

/// Physical keys copy a selection's stable atom rather than retaining a type edge.
/// Semantic rows retain the owned edge for footprint and equality proofs.
pub fn selectionAtom(source: anytype, original: NominalIdentity) NominalIdentity {
    if (original.unit != 0 or original.decl == 0) return original;
    const value = source.node(original.decl);
    if (value.tag != .instance_selection) return original;
    const choices = source.nominalArguments(value);
    if (choices.len == 3) {
        const version = source.node(choices[2]);
        return .{ .unit = version.a, .decl = 0x40000000 | (version.b << 4) | version.c };
    }
    return .{ .unit = value.a, .decl = value.b };
}

const OperationIndexTests = struct {
    /// The interning scan the chains replace: the oldest equal candidate.
    fn scan(store: *const Store, identity: NominalIdentity, instance: NominalIdentity, resolved: []const Id, symbolic: bool) Error!?Effects.Label {
        for (store.operations.items[1..], 1..) |candidate, index| {
            if (!std.meta.eql(identity, candidate.identity) or !std.meta.eql(instance, candidate.instance)) continue;
            const old = store.list(candidate.arguments);
            if (old.len != resolved.len) continue;
            var same = true;
            for (old, resolved) |a, b| same = same and try store.equalGraphWalk(a, b, symbolic);
            if (same) return @intCast(index);
        }
        return null;
    }
    fn intern(store: *Store, identity: NominalIdentity, instance: NominalIdentity, resolved: []const Id, symbolic: bool) !Effects.Label {
        const expected = try scan(store, identity, instance, resolved, symbolic);
        const before = store.operations.items.len;
        const actual = try store.internResolvedOperation(identity, instance, resolved, symbolic);
        if (expected) |label| try std.testing.expectEqual(label, actual) else try std.testing.expectEqual(before, actual);
        return actual;
    }
    fn histories(allocator: std.mem.Allocator) !void {
        var store = try Store.init(allocator);
        defer store.deinit();
        // A direct append before any interning, as a table seeded from a
        // module's operations is.
        const seeded = try store.saveList(&.{u32_type});
        try store.operations.append(allocator, .{ .identity = .{ .unit = 3, .decl = 1 }, .arguments = seeded });
        const variable = try store.fresh();
        // Distinct IDs with equal closed graphs, and a symbolic-only pair.
        const pool = [_]Id{ u32_type, f32_type, try store.array(u32_type), try store.array(u32_type), try store.sequence(.list, f32_type), variable, try store.array(variable), try store.array(variable) };
        var arguments: [3]Id = undefined;
        var state: u32 = 0x9e3779b9;
        for (0..240) |step| {
            state = state *% 1664525 +% 1013904223;
            const arity = (state >> 8) % 4;
            for (arguments[0..arity], 0..) |*argument, index| argument.* = pool[(state >> @intCast(12 + index * 3)) % pool.len];
            const identity: NominalIdentity = .{ .unit = 3, .decl = 1 + (state >> 20) % 3 };
            const instance: NominalIdentity = if ((state >> 24) % 3 == 0) .{ .unit = 5, .decl = 1 + (state >> 26) % 2 } else .{ .unit = 0, .decl = 0 };
            const symbolic = (state >> 28) % 2 == 0;
            if (step % 40 == 17) {
                // Speculative interning rolls back; the chains forget it.
                const point = store.mark();
                _ = try intern(&store, .{ .unit = 3, .decl = 9 }, instance, arguments[0..arity], symbolic);
                _ = try intern(&store, identity, instance, arguments[0..arity], symbolic);
                store.rollback(point);
                // Rollback unlinks exactly what it removed.
                try std.testing.expect(store.operation_links.items.len <= store.operations.items.len);
                if (store.operation_links.items.len > 1) try std.testing.expectEqual(store.operations.items.len, store.operation_links.items.len);
            } else if (step == 120) {
                // A physical write to an interned argument list stays visible.
                const label = try intern(&store, identity, instance, &.{ u32_type, f32_type }, false);
                store.replaceListItem(store.operations.items[label].arguments, 1, u32_type);
                _ = try intern(&store, identity, instance, &.{ u32_type, u32_type }, false);
                _ = try intern(&store, identity, instance, &.{ u32_type, f32_type }, false);
            } else _ = try intern(&store, identity, instance, arguments[0..arity], symbolic);
        }
    }
};

test "operation chains intern exactly the oldest equal operation through rollback writes and allocation failures" {
    try OperationIndexTests.histories(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, OperationIndexTests.histories, .{});
}

fn operationShapesScenario(a: std.mem.Allocator) !void {
    var store = try Store.initWithOptions(a, .{ .closed_graphs = true });
    defer store.deinit();
    const operation_: NominalIdentity = .{ .unit = 7, .decl = 9 };
    var labels: [24]Effects.Label = undefined;
    for (&labels, 0..) |*label, index| {
        const ty = try store.nominal(.{ .unit = 3, .decl = @intCast(index + 1) }, &.{});
        label.* = try OperationIndexTests.intern(&store, operation_, .{ .unit = 0, .decl = 0 }, &.{ty}, false);
    }
    const candidates = store.normalization.interner_candidates;
    const duplicate = try store.nominal(.{ .unit = 3, .decl = 24 }, &.{});
    try std.testing.expectEqual(labels[23], try OperationIndexTests.intern(&store, operation_, .{ .unit = 0, .decl = 0 }, &.{duplicate}, false));
    try std.testing.expectEqual(candidates + 1, store.normalization.interner_candidates);
    // Record order is not semantic equality, and physical list mutation must
    // rebuild the index before any obsolete bucket can hide an equal entry.
    const first = try store.record(&.{ .{ .name = 3, .ty = u32_type }, .{ .name = 7, .ty = f32_type } });
    const second = try store.record(&.{ .{ .name = 7, .ty = f32_type }, .{ .name = 3, .ty = u32_type } });
    const label = try OperationIndexTests.intern(&store, operation_, .{ .unit = 0, .decl = 0 }, &.{first}, false);
    try std.testing.expectEqual(label, try OperationIndexTests.intern(&store, operation_, .{ .unit = 0, .decl = 0 }, &.{second}, false));
    const tuple = try store.product(&.{u32_type});
    const tuple_label = try OperationIndexTests.intern(&store, operation_, .{ .unit = 0, .decl = 0 }, &.{tuple}, false);
    const point = store.mark();
    _ = try OperationIndexTests.intern(&store, operation_, .{ .unit = 0, .decl = 0 }, &.{boolean}, false);
    store.rollback(point);
    const n = store.node(tuple);
    store.replaceListItem(.{ .start = n.a, .len = n.b }, 0, f32_type);
    const changed = try store.product(&.{f32_type});
    try std.testing.expectEqual(tuple_label, try OperationIndexTests.intern(&store, operation_, .{ .unit = 0, .decl = 0 }, &.{changed}, false));
    store.closed_generation = std.math.maxInt(u16);
    try std.testing.expectEqual(tuple_label, try OperationIndexTests.intern(&store, operation_, .{ .unit = 0, .decl = 0 }, &.{changed}, false));
}

test "operation argument shapes preserve structural equality physical edits rollback saturation and allocation failures" {
    try operationShapesScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, operationShapesScenario, .{});
}

test "closed equality visits shared certified DAG pairs without accepting open or cyclic graphs" {
    var store = try Store.initWithOptions(std.testing.allocator, .{ .closed_graphs = true });
    defer store.deinit();
    var left = u32_type;
    var right = u32_type;
    for (0..22) |_| {
        left = try store.product(&.{ left, left });
        right = try store.product(&.{ right, right });
    }
    try std.testing.expect(try store.equalClosed(left, right));
    const open = try store.fresh();
    try std.testing.expect(!try store.equalClosed(open, open));
    const cycle = try store.product(&.{u32_type});
    const node_ = store.node(cycle);
    store.replaceListItem(.{ .start = node_.a, .len = node_.b }, 0, cycle);
    try std.testing.expectError(error.TypeLimit, store.equalClosed(cycle, cycle));
}

fn wideEqualityScenario(a: std.mem.Allocator) !void {
    var store = try Store.initWithOptions(a, .{ .closed_graphs = true });
    defer store.deinit();
    var fields: [32]Field = undefined;
    var reversed: [32]Field = undefined;
    for (&fields, 0..) |*field, index| field.* = .{ .name = @intCast(index + 1), .ty = if (index % 2 == 0) u32_type else boolean };
    for (fields, 0..) |field, index| reversed[fields.len - index - 1] = field;
    const left = try store.record(&fields);
    const right = try store.record(&reversed);
    try std.testing.expect(try store.equalClosed(left, right));
    reversed[0].ty = f32_type;
    try std.testing.expect(!try store.equalClosed(left, try store.record(&reversed)));
    reversed[0] = fields[fields.len - 1];
    reversed[0].name = 99;
    try std.testing.expect(!try store.equalClosed(left, try store.record(&reversed)));
    var labels: [24]Effects.Label = undefined;
    for (&labels, 0..) |*label, index| label.* = try store.internOperation(.{ .unit = 7, .decl = @intCast(index % 8 + 1) }, &.{u32_type});
    var reverse_labels: [24]Effects.Label = undefined;
    for (labels, 0..) |label, index| reverse_labels[labels.len - index - 1] = label;
    const first = try store.functionWithEffects(u32_type, u32_type, try store.effects.row(&labels, .closed));
    const second = try store.functionWithEffects(u32_type, u32_type, try store.effects.row(&reverse_labels, .closed));
    try std.testing.expect(try store.equalClosed(first, second));
    reverse_labels[0] = labels[0];
    const changed = try store.functionWithEffects(u32_type, u32_type, try store.effects.row(&reverse_labels, .closed));
    try std.testing.expect(!try store.equalClosed(first, changed));
    const open = try store.internSymbolicOperation(.{ .unit = 7, .decl = 9 }, &.{try store.fresh()});
    const open_row = try store.effects.row(&.{open}, .closed);
    const open_function = try store.functionWithEffects(u32_type, u32_type, open_row);
    try std.testing.expect(!try store.equalClosed(open_function, open_function));
}
test "wide equality preserves reordered fields duplicate effect multiplicities and open arguments through OOM" {
    try wideEqualityScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, wideEqualityScenario, .{});
}

const ClosedRowTests = struct {
    fn scenario(allocator: std.mem.Allocator) !void {
        for ([_]bool{ true, false }) |enabled| {
            var store = try Store.initWithOptions(allocator, .{ .closed_graphs = true });
            defer store.deinit();
            store.use_closed_rows = enabled;
            store.use_operation_rows = enabled;
            const argument = try store.array(u32_type);
            const label = try store.internOperation(.{ .unit = 7, .decl = 19 }, &.{argument});
            const row_ = try store.effects.row(&.{ label, label }, .closed);
            try std.testing.expectEqual(@as(u8, 3), store.closedRowHeight(row_));
            _ = try store.functionWithEffects(unit, u32_type, row_);
            for (0..3) |_| try std.testing.expectEqual(row_, try store.resolveEffects(row_, 0));
            var many: [17]Effects.Id = undefined;
            for (&many) |*value| {
                value.* = try store.effects.row(&.{ label, label }, .closed);
                _ = try store.resolveEffects(value.*, 0);
            }
            const visits = store.normalization.argument_rows;
            if (enabled) try std.testing.expect(store.normalization.closed_operation_hits > 0) else try std.testing.expectEqual(@as(u64, 0), store.normalization.closed_operation_hits);
            for (many) |value| try std.testing.expectEqual(value, try store.resolveEffects(value, 0));
            if (enabled) try std.testing.expectEqual(visits, store.normalization.argument_rows);
            store.resolution_depth_limit = 3;
            try std.testing.expectEqual(row_, try store.resolveOperationRow(row_, 0, 0));
            store.resolution_depth_limit = 2;
            try std.testing.expectError(error.TypeLimit, store.resolveOperationRow(row_, 0, 0));
            // Empty/no-argument rows never had an argument-height limit. The
            // resolver's independent hard depth boundary remains in force.
            const no_arguments = try store.effects.row(&.{foreign_operation}, .closed);
            _ = store.closedRowHeight(no_arguments);
            store.resolution_depth_limit = 0;
            try std.testing.expectEqual(no_arguments, try store.resolveOperationRow(no_arguments, 0, 1023));
            try std.testing.expectEqual(@as(Effects.Id, 0), try store.resolveOperationRow(0, 0, 1023));
            try std.testing.expectError(error.TypeLimit, store.resolveOperationRow(no_arguments, 0, 1024));
            store.resolution_depth_limit = 1024;
            // An operation's physical argument replacement revokes a warm
            // proof, including when the new argument is not resolved yet.
            const unknown = try store.fresh();
            store.replaceListItem(store.operation(label).arguments, 0, unknown);
            try std.testing.expectEqual(@as(u8, 0), store.closedRowHeight(row_));
            try store.appendVersion(unknown, u32_type);
            try store.appendVersion(unknown, f32_type);
            const first = try store.resolveEffects(row_, 0);
            const later = try store.resolveEffects(row_, 1);
            try std.testing.expectEqual(u32_type, store.operationArguments(store.rowLabels(first)[0])[0]);
            try std.testing.expectEqual(f32_type, store.operationArguments(store.rowLabels(later)[0])[0]);
            // The normalized result has immutable arguments at every view.
            try std.testing.expectEqual(first, try store.resolveEffects(first, 1));
            // Store rollback recycles row IDs but never proof generations.
            const point = store.mark();
            const temporary = try store.effects.row(&.{store.rowLabels(first)[0]}, .closed);
            _ = store.closedRowHeight(temporary);
            store.rollback(point);
            const reused = try store.effects.row(&.{store.rowLabels(later)[0]}, .closed);
            try std.testing.expectEqual(temporary, reused);
            const changed = try store.resolveEffects(reused, 0);
            try std.testing.expectEqual(f32_type, store.operationArguments(store.rowLabels(changed)[0])[0]);
            // Physical row rollback has its own epoch, even without calling
            // the type-store rollback or advancing its substitution history.
            const physical = store.effects.mark();
            const old_row = try store.effects.row(&.{store.rowLabels(first)[0]}, .closed);
            _ = store.closedRowHeight(old_row);
            store.effects.rollback(physical);
            const new_row = try store.effects.row(&.{store.rowLabels(later)[0]}, .closed);
            try std.testing.expectEqual(old_row, new_row);
            const current = try store.resolveEffects(new_row, 0);
            try std.testing.expectEqual(f32_type, store.operationArguments(store.rowLabels(current)[0])[0]);
            // A symbolic instance must still resolve after its variable is
            // assigned; closed type arguments alone cannot certify it.
            const descriptor = try store.nominal(.{ .unit = 1, .decl = 7 }, &.{u32_type});
            const parameter = try store.capabilityParameter(descriptor);
            const term = store.node(parameter);
            const symbolic = try store.internScopedOperation(.{ .unit = 1, .decl = 8 }, .{ .unit = term.b, .decl = term.c }, &.{u32_type});
            const symbolic_row = try store.effects.row(&.{symbolic}, .closed);
            try std.testing.expectEqual(@as(u8, 0), store.closedRowHeight(symbolic_row));
            _ = try store.resolveEffects(symbolic_row, 0);
            const selected = try store.scoped(descriptor, .{ .unit = 1, .decl = 30 });
            try store.unify(parameter, selected);
            const resolved = try store.resolveEffects(symbolic_row, 0);
            try std.testing.expectEqual(NominalIdentity{ .unit = 1, .decl = 30 }, store.operation(store.rowLabels(resolved)[0]).instance);
            const open = try store.freshEffects();
            try std.testing.expectEqual(@as(u8, 0), store.closedRowHeight(open));
            _ = try store.resolveEffects(open, 0);
            try std.testing.expect(store.closedRow(open) == null);
            const open_arguments = try store.effects.row(&.{store.rowLabels(first)[0]}, store.row(open).tail);
            const normalized_open = try store.resolveEffects(open_arguments, 0);
            try std.testing.expectEqual(@as(u8, 0), store.closedRowHeight(normalized_open));
            try std.testing.expectEqual(enabled, store.closedRow(normalized_open) != null);
            const row_variable = store.row(open).tail.variable;
            const clock = store.cursor();
            try store.effects.appendVersionAt(row_variable, first, clock + 2);
            try store.effects.appendVersionAt(row_variable, later, clock + 5);
            const old_view = try store.resolveEffects(open, clock);
            const new_view = try store.resolveEffects(open, clock + 3);
            try std.testing.expectEqual(u32_type, store.operationArguments(store.rowLabels(old_view)[0])[0]);
            try std.testing.expectEqual(f32_type, store.operationArguments(store.rowLabels(new_view)[0])[0]);
            const prefixed_old = try store.resolveEffects(open_arguments, clock);
            const prefixed_new = try store.resolveEffects(open_arguments, clock + 3);
            // Keep the prefix and both repeated operations from the tail.
            try std.testing.expectEqual(@as(usize, 3), store.rowLabels(prefixed_old).len);
            try std.testing.expectEqual(@as(usize, 3), store.rowLabels(prefixed_new).len);
            try std.testing.expectEqual(u32_type, store.operationArguments(store.rowLabels(prefixed_old)[1])[0]);
            try std.testing.expectEqual(f32_type, store.operationArguments(store.rowLabels(prefixed_new)[1])[0]);
            const future = try store.resolveEffects(open, clock + 6);
            try std.testing.expect(store.row(future).tail == .variable);
            try std.testing.expectEqual(row_variable, store.row(future).tail.variable);
            try std.testing.expectEqual(clock + 6, store.row(future).cursor);
            try std.testing.expectEqual(@as(u8, 0), store.closedRowHeight(future));
            store.closed_generation = std.math.maxInt(u16);
            try std.testing.expectEqual(first, try store.resolveEffects(first, 0));
            try std.testing.expect(store.closedRow(first) == null);
            store.effects.physical_epoch = std.math.maxInt(u64);
            try std.testing.expectEqual(later, try store.resolveEffects(later, 1));
            try std.testing.expect(store.closedRow(later) == null);
        }
    }
};

test "closed row certificates preserve depth history physical edits instances and saturation through OOM" {
    try ClosedRowTests.scenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ClosedRowTests.scenario, .{});
}

fn operationRowScenario(allocator: std.mem.Allocator) !void {
    for ([_]bool{ true, false }) |enabled| {
        var store = try Store.init(allocator);
        defer store.deinit();
        store.use_operation_rows = enabled;
        const variable = try store.fresh();
        const argument = try store.array(variable);
        const label = try store.internSymbolicOperation(.{ .unit = 1, .decl = 1 }, &.{argument});
        const row_ = try store.effects.row(&.{ label, label }, .closed);
        const initial = try store.resolveEffects(row_, 0);
        const visits = store.resolution_steps;
        try std.testing.expect(visits > 0);
        for (0..4) |_| try std.testing.expectEqual(initial, try store.resolveEffects(row_, 0));
        try std.testing.expectEqual(enabled, store.resolution_steps == visits);
        store.resolution_depth_limit = 1;
        try std.testing.expectError(error.TypeLimit, store.resolveEffects(row_, 0));
        store.resolution_depth_limit = 1024;
        const point = store.mark();
        try store.appendVersion(variable, u32_type);
        try store.appendVersion(variable, f32_type);
        for ([_]Id{ u32_type, f32_type }, 0..) |expected, at| {
            const resolved = try store.resolveEffects(row_, @intCast(at));
            const item = store.operationArguments(store.rowLabels(resolved)[0])[0];
            try std.testing.expectEqual(expected, store.node(item).a);
        }
        store.rollback(point);
        try std.testing.expectEqual(initial, try store.resolveEffects(row_, 0));
        for ([_]bool{ true, false }) |types_clock| {
            if (types_clock) store.mutation_epoch = std.math.maxInt(u64) else store.effects.mutation_epoch = std.math.maxInt(u64);
            const before = store.resolution_steps;
            for (0..2) |_| try std.testing.expectEqual(initial, try store.resolveEffects(row_, 0));
            try std.testing.expect(store.resolution_steps > before);
        }
    }
}

test "operation row normalization preserves unresolved arguments histories depth rollback and saturated epochs through OOM" {
    try operationRowScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, operationRowScenario, .{});
}
