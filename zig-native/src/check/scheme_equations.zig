//! Temporary ordinary solver workspace for immutable declaration equations.
//! Caller identities stay rigid; only an actual declaration's formals are fresh.
const std = @import("std");
const core = @import("core.zig");
const T = @import("types.zig");
const F = @import("frozen_types.zig");
const Import = @import("check_scheme_import.zig").Copier;
pub const Error = error{ InvalidArtifact, OutOfMemory };
pub const SourceFailure = struct { unit: u32, span: core.Span };
pub const Admission = struct {
    const Body = struct { module: *const core.Module, binding: core.BindingId };
    workspace: ?*Workspace = null,
    remaining: *usize,
    units: [128]*const core.Module = undefined,
    count: usize = 0,
    source_bodies: bool = false,
    bodies: std.ArrayList(Body) = .empty,
    source_rows: std.ArrayList(struct { module: *const core.Module, rows: []T.Effects.Id }) = .empty,
    source_definitions: std.ArrayList(struct { module: *const core.Module, values: []core.Id }) = .empty,
    source_failure: ?*?SourceFailure = null,
};
pub const Workspace = struct {
    allocator: std.mem.Allocator,
    oom: bool = false,
    admission: ?*Admission = null,
    modules: [128]*const core.Module = undefined,
    module_count: usize = 0,
    bounds_units: [128]*const core.Module = undefined,
    bounds_unit_count: ?usize = null,
    bounds_receipts: [128]BoundsReceipt = undefined,
    bounds_count: usize = 0,
    const BoundsReceipt = struct {
        module: *const core.Module,
        symbol_count: ?usize,
        source_length: ?u32,
        forbidden_owner: ?u32,
    };
    pub fn proved(self: *const Workspace, module: *const core.Module) bool {
        for (self.modules[0..self.module_count]) |candidate| if (candidate == module) return true;
        return false;
    }
};
fn convert(err: T.Error) Error {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    return error.InvalidArtifact;
}
/// Receipts contain only IDs in the solver's immutable copied prefix. A
/// rollback can discard an imported graph without recycling this evidence.
pub const SharedGoal = struct {
    producer: *const core.Module,
    origin: ?*const core.Module,
    binding: core.BindingId,
    call_owner: core.Id,
    resolver_callback: core.Id,
    goal_depth: usize,
    ambient: T.Effects.Id,
    foreign_allowed: bool,
    type_count: u8,
    row_count: u8,
    arguments: [128]T.Id = @splat(0),
};
/// One inquiry may mutate row/instance facts while choosing evidence. Reuse
/// only the exact lexical authority first observed by this solver.
const SharedAuthority = struct {
    context: *const anyopaque,
    pure_rows: @import("package_row_facts.zig").Facts,
    closed_rows: @import("package_row_facts.zig").Facts,
    instance_variables: @import("package_row_facts.zig").Facts,
    instance_rows: @import("package_row_facts.zig").Facts,
    schemes: [128]T.Scheme = @splat(.{}),
    scheme_count: usize,
    generic_variables: T.List,
    generic_rows: T.List,
    obligations: []const core.Obligation,
    source_obligations: []const T.Obligation,
    source_instances: bool,
    executable: bool,
    large_plain_graph: bool,

    fn eligible(views: anytype) bool {
        return views.formal == null and views.formal_count == 0 and views.opening_count == 0 and
            !views.witness and views.representation_floor == null and views.projection_resolver == null;
    }
    fn init(views: anytype) SharedAuthority {
        var result: SharedAuthority = .{
            .context = views,
            .pure_rows = views.pure_rows,
            .closed_rows = views.closed_rows,
            .instance_variables = views.instance_variables,
            .instance_rows = views.instance_rows,
            .scheme_count = views.scheme_count,
            .generic_variables = views.generic_variables,
            .generic_rows = views.generic_rows,
            .obligations = views.obligations,
            .source_obligations = views.source_obligations,
            .source_instances = views.source_instances,
            .executable = views.executable,
            .large_plain_graph = views.large_plain_graph,
        };
        @memcpy(result.schemes[0..views.scheme_count], views.schemes[0..views.scheme_count]);
        return result;
    }
    fn matches(self: *const SharedAuthority, views: anytype) bool {
        if (!eligible(views) or self.context != @as(*const anyopaque, views) or self.scheme_count != views.scheme_count or
            !std.meta.eql(self.generic_variables, views.generic_variables) or !std.meta.eql(self.generic_rows, views.generic_rows) or
            self.obligations.ptr != views.obligations.ptr or self.obligations.len != views.obligations.len or
            self.source_obligations.ptr != views.source_obligations.ptr or self.source_obligations.len != views.source_obligations.len or
            self.source_instances != views.source_instances or self.executable != views.executable or self.large_plain_graph != views.large_plain_graph) return false;
        for (self.schemes[0..self.scheme_count], views.schemes[0..views.scheme_count]) |before, after| if (!std.meta.eql(before, after)) return false;
        return self.pure_rows.eql(&views.pure_rows) and self.closed_rows.eql(&views.closed_rows) and
            self.instance_variables.eql(&views.instance_variables) and self.instance_rows.eql(&views.instance_rows);
    }
};
pub const Solver = struct {
    store: T.Store,
    graph: core.Types = undefined,
    view: ?*core.Types = null,
    scope: u32,
    oom: bool = false,
    rigid_types: std.bit_set.Static(4096) = .empty,
    rigid_type_overflow: std.AutoHashMapUnmanaged(T.Id, void) = .empty,
    rigid_rows: std.AutoHashMapUnmanaged(u32, void) = .empty,
    remaining: *usize,
    prefix_nodes: usize,
    prefix_rows: usize,
    prefix_operations: usize,
    prefix_extra: usize,
    prefix_row_variables: usize,
    shared_authority: ?*SharedAuthority = null,
    shared_goals: std.AutoHashMapUnmanaged(SharedGoal, usize) = .empty,
    shared_goal_hits: usize = 0,
    pub fn init(allocator: std.mem.Allocator, module: *const core.Module, views: anytype, remaining: *usize) Error!Solver {
        // This private store owns its mutation/rollback epochs. Reuse exact
        // epoch resolutions (including rank walks), never cross-epoch or
        // lexical proof facts. The copied prefix is finalized before queries.
        var store = T.Store.initWithOptions(allocator, .{ .resolution_cache = true, .composite_cache = false }) catch |err| return convert(err);
        errdefer store.deinit();
        store.nodes.clearRetainingCapacity();
        try store.nodes.appendSlice(allocator, module.types.nodes);
        store.extra.clearRetainingCapacity();
        try store.extra.appendSlice(allocator, module.types.extra);
        store.operations.clearRetainingCapacity();
        try store.operations.appendSlice(allocator, module.types.operations);
        try store.quantifier_goals.appendSlice(allocator, module.types.quantifier_goals);
        try store.quantifier_obligations.appendSlice(allocator, module.types.quantifier_obligations);
        store.effects.rows.clearRetainingCapacity();
        try store.effects.rows.appendSlice(allocator, module.types.effects.rows);
        store.effects.labels.clearRetainingCapacity();
        try store.effects.labels.appendSlice(allocator, module.types.effects.labels);
        var rigid_types: std.bit_set.Static(4096) = .empty;
        var rigid_type_overflow: std.AutoHashMapUnmanaged(T.Id, void) = .empty;
        errdefer rigid_type_overflow.deinit(allocator);
        var rigid_rows: std.AutoHashMapUnmanaged(u32, void) = .empty;
        errdefer rigid_rows.deinit(allocator);
        const scope = store.rigidScope() catch |err| return convert(err);
        for (views.schemes[0..views.scheme_count]) |scheme| {
            if (module.types.node(scheme.root).tag != .forall) for (module.types.list(scheme.variables)) |formal| {
                if (remaining.* == 0 or formal >= module.types.nodes.len) return error.InvalidArtifact;
                remaining.* -= 1;
                if (formal < rigid_types.capacity()) rigid_types.set(formal) else try rigid_type_overflow.put(allocator, formal, {});
            };
            for (module.types.list(scheme.row_variables)) |formal| {
                if (remaining.* == 0) return error.InvalidArtifact;
                remaining.* -= 1;
                try rigid_rows.put(allocator, formal, {});
            }
        }
        for (store.nodes.items, 0..) |*node, id| {
            node.closed_height = 0;
            node.closed_generation = 0;
            if (node.tag == .variable) {
                // A checked source instance remains the same rigid caller
                // identity in this inquiry. Carry its existing ownership;
                // this neither makes it flexible nor infers its concrete type.
                if (views.source_instances and views.instance_variables.contains(id)) {
                    if (remaining.* == 0) return error.InvalidArtifact;
                    remaining.* -= 1;
                    if (id < rigid_types.capacity()) rigid_types.set(id) else try rigid_type_overflow.put(allocator, @intCast(id), {});
                }
                node.* = .{ .tag = .rigid, .a = scope, .b = @intCast(id) };
            }
        }
        // Do not infer a closed row from its absence in a selected signature.
        // Only the caller's independently reconstructed row view closes it.
        for (0..module.types.effects.rows.len) |index| {
            const row = store.effects.rows.items[index];
            if (row.tail != .variable) continue;
            if (views.closed_rows.contains(index)) {
                store.effects.rows.items[index].tail = .closed;
            } else {
                if (views.source_instances and views.instance_rows.contains(row.tail.variable) and !rigid_rows.contains(row.tail.variable)) {
                    if (remaining.* == 0 or row.tail.variable >= module.types.effects.variable_count) return error.InvalidArtifact;
                    remaining.* -= 1;
                    try rigid_rows.put(allocator, row.tail.variable, {});
                }
                const rigid = store.rigid(scope, row.tail.variable, 1) catch |err| return convert(err);
                store.effects.rows.items[index].tail = .{ .formal = rigid };
            }
        }
        store.has_projections = true;
        store.has_rank_types = true;
        store.has_usage_types = true;
        var result: Solver = .{ .store = store, .scope = scope, .remaining = remaining, .rigid_types = rigid_types, .rigid_type_overflow = rigid_type_overflow, .rigid_rows = rigid_rows, .prefix_nodes = store.nodes.items.len, .prefix_rows = store.effects.rows.items.len, .prefix_operations = store.operations.items.len, .prefix_extra = store.extra.items.len, .prefix_row_variables = module.types.effects.variable_count };
        result.refresh();
        return result;
    }
    pub fn readerError(self: *Solver, err: Error) error{InvalidArtifact} {
        if (err == error.OutOfMemory) self.oom = true;
        return error.InvalidArtifact;
    }
    pub fn ownsRigid(self: *const Solver, node: T.Node) bool {
        if (node.tag != .rigid or node.a != self.scope) return false;
        if (node.c == 0) return if (node.b < self.rigid_types.capacity()) self.rigid_types.isSet(node.b) else self.rigid_type_overflow.contains(node.b);
        return node.c == 1 and self.rigid_rows.contains(node.b);
    }
    fn prefixFacts(facts: @import("package_row_facts.zig").Facts, limit: usize) bool {
        for (facts.pages) |page| {
            if (page.bits == 0) continue;
            const first = (page.key - 1) * 64;
            if (first >= limit) return false;
            const count = limit - first;
            if (count < 64 and page.bits >> @intCast(count) != 0) return false;
        }
        return true;
    }
    pub fn sharedAuthority(self: *Solver, views: anytype) Error!bool {
        if (!SharedAuthority.eligible(views) or
            !prefixFacts(views.pure_rows, self.prefix_rows) or !prefixFacts(views.closed_rows, self.prefix_rows) or
            !prefixFacts(views.instance_variables, self.prefix_nodes) or !prefixFacts(views.instance_rows, self.prefix_row_variables)) return false;
        for (views.schemes[0..views.scheme_count]) |scheme| {
            if (scheme.root >= self.prefix_nodes or scheme.generative.len != 0) return false;
            inline for (.{ "variables", "row_variables", "closed_rows" }) |name| {
                const span = @field(scheme, name);
                if (span.start > self.prefix_extra or span.len > self.prefix_extra - span.start) return false;
                const maximum = if (comptime std.mem.eql(u8, name, "variables")) self.prefix_nodes else self.prefix_row_variables;
                for (self.store.list(span)) |id| if (id >= maximum) return false;
            }
        }
        if (self.shared_authority) |authority| return authority.matches(views);
        const authority = try self.store.allocator.create(SharedAuthority);
        authority.* = SharedAuthority.init(views);
        self.shared_authority = authority;
        return true;
    }
    pub fn sharedGoalHit(self: *Solver, key: SharedGoal, depth: usize) bool {
        const proved_depth = self.shared_goals.get(key) orelse return false;
        if (depth > proved_depth) return false;
        self.shared_goal_hits += 1;
        return true;
    }
    pub fn rememberSharedGoal(self: *Solver, key: SharedGoal, depth: usize) Error!void {
        if (self.shared_goals.getPtr(key)) |proved_depth| {
            proved_depth.* = @max(proved_depth.*, depth);
            return;
        }
        // This optional receipt table cannot grow with an unbounded inquiry.
        // At capacity the completed ordinary proof simply remains uncached.
        if (self.shared_goals.count() >= 65_536) return;
        try self.shared_goals.put(self.store.allocator, key, depth);
    }
    pub fn deinit(self: *Solver) void {
        if (self.shared_authority) |authority| self.store.allocator.destroy(authority);
        self.shared_goals.deinit(self.store.allocator);
        self.rigid_type_overflow.deinit(self.store.allocator);
        self.rigid_rows.deinit(self.store.allocator);
        self.store.deinit();
    }
    pub fn refresh(self: *Solver) void {
        self.graph = .{ .nodes = self.store.nodes.items, .extra = self.store.extra.items, .effects = .{ .rows = self.store.effects.rows.items, .labels = self.store.effects.labels.items, .variable_count = @intCast(self.store.effects.variables.items.len) }, .operations = self.store.operations.items, .quantifier_goals = self.store.quantifier_goals.items, .quantifier_obligations = self.store.quantifier_obligations.items };
        if (self.view) |view| view.* = self.graph;
    }
    pub fn step(self: *Solver) Error!void {
        if (self.remaining.* == 0) return error.InvalidArtifact;
        self.remaining.* -= 1;
    }
    fn beginWork(self: *Solver) void {
        self.store.projection_steps = 0;
        self.store.projection_limit = self.remaining.*;
    }
    fn endWork(self: *Solver) void {
        self.remaining.* -= @min(self.remaining.*, self.store.projection_steps);
        self.refresh();
    }
    pub fn unify(self: *Solver, left: T.Id, right: T.Id) Error!void {
        try self.step();
        self.beginWork();
        defer self.endWork();
        self.store.unify(left, right) catch |err| return convert(err);
    }
    pub fn rows(self: *Solver, left: T.Effects.Id, right: T.Effects.Id) Error!void {
        try self.step();
        self.beginWork();
        defer self.endWork();
        self.store.unifyEffects(left, right) catch |err| return convert(err);
    }
    pub fn resolve(self: *Solver, id: T.Id) Error!T.Id {
        try self.step();
        self.beginWork();
        defer self.endWork();
        return self.store.resolve(id, 0) catch |err| return convert(err);
    }
    pub fn resolveRow(self: *Solver, id: T.Effects.Id) Error!T.Effects.Id {
        try self.step();
        self.beginWork();
        defer self.endWork();
        return self.store.resolveEffects(id, 0) catch |err| return convert(err);
    }
    pub fn rollback(self: *Solver, mark: T.Mark) void {
        self.store.rollback(mark);
        self.refresh();
    }
    pub fn importer(self: *Solver, module: *const core.Module, frozen: *F.Graph, scheme: T.Scheme) Error!Import {
        frozen.* = .{ .nodes = module.types.nodes, .extra = module.types.extra, .rows = module.types.effects.rows, .labels = module.types.effects.labels, .operations = module.types.operations, .row_variable_count = module.types.effects.variable_count, .quantifier_goals = module.types.quantifier_goals, .quantifier_obligations = module.types.quantifier_obligations };
        var import_: Import = .{ .allocator = self.store.allocator, .source = .{ .frozen = frozen }, .destination = &self.store, .associated = true };
        errdefer import_.deinit();
        for (module.types.list(scheme.variables)) |formal| try import_.mapping.put(import_.allocator, formal, self.store.fresh() catch |err| return convert(err));
        for (module.types.list(scheme.row_variables)) |formal| try import_.row_variables.put(import_.allocator, formal, self.store.freshEffects() catch |err| return convert(err));
        for (module.types.list(scheme.closed_rows)) |formal| try import_.row_variables.put(import_.allocator, formal, 0);
        self.refresh();
        return import_;
    }
    pub fn copy(self: *Solver, importer_: *Import, root: T.Id) Error!T.Id {
        try self.step();
        self.beginWork();
        defer self.endWork();
        return importer_.copy(root, 0) catch |err| return convert(err);
    }
};

/// Only successful bounds checks in this immutable validation may be reused.
/// Semantic module admission is a separate receipt and never follows from this.
pub fn bounds(workspace: ?*Workspace, module: *const core.Module, context: @import("frozen_core_validation.zig").Context) error{InvalidArtifact}!void {
    comptime {
        if (@typeInfo(@TypeOf(context)).@"struct".field_names.len != 4) @compileError("register every bounds Context field in the receipt");
    }
    const owner = workspace orelse return @import("frozen_core_validation.zig").validateBounds(module, context);
    var same_context = context.units.len <= owner.bounds_units.len;
    if (same_context) {
        if (owner.bounds_unit_count) |count| {
            same_context = std.mem.eql(*const core.Module, owner.bounds_units[0..count], context.units);
        } else {
            @memcpy(owner.bounds_units[0..context.units.len], context.units);
            owner.bounds_unit_count = context.units.len;
        }
    }
    if (same_context) for (owner.bounds_receipts[0..owner.bounds_count]) |receipt| {
        if (receipt.module == module and receipt.symbol_count == context.symbol_count and receipt.source_length == context.source_length and receipt.forbidden_owner == context.forbidden_owner) return;
    };
    try @import("frozen_core_validation.zig").validateBounds(module, context);
    if (!same_context or owner.bounds_count == owner.bounds_receipts.len) return;
    owner.bounds_receipts[owner.bounds_count] = .{ .module = module, .symbol_count = context.symbol_count, .source_length = context.source_length, .forbidden_owner = context.forbidden_owner };
    owner.bounds_count += 1;
}
