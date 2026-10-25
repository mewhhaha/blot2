//! Temporary ordinary solver workspace for immutable declaration equations.
//! Caller identities stay rigid; only an actual declaration's formals are fresh.
const std = @import("std");
const core = @import("core.zig");
const T = @import("types.zig");
const F = @import("frozen_types.zig");
const Import = @import("check_scheme_import.zig").Copier;
pub const Error = error{ InvalidArtifact, OutOfMemory };
pub const Admission = struct {
    const Body = struct { module: *const core.Module, binding: core.BindingId };
    workspace: ?*Workspace = null,
    remaining: *usize,
    units: [128]*const core.Module = undefined,
    count: usize = 0,
    source_bodies: bool = false,
    bodies: [128]Body = undefined,
    body_count: usize = 0,
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
    pub fn init(allocator: std.mem.Allocator, module: *const core.Module, views: anytype, remaining: *usize) Error!Solver {
        var store = T.Store.initWithOptions(allocator, .{ .resolution_cache = false, .composite_cache = false }) catch |err| return convert(err);
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
                const rigid = store.rigid(scope, row.tail.variable, 1) catch |err| return convert(err);
                store.effects.rows.items[index].tail = .{ .formal = rigid };
            }
        }
        store.has_projections = true;
        store.has_rank_types = true;
        store.has_usage_types = true;
        var result: Solver = .{ .store = store, .scope = scope, .remaining = remaining, .rigid_types = rigid_types, .rigid_type_overflow = rigid_type_overflow, .rigid_rows = rigid_rows };
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
    pub fn deinit(self: *Solver) void {
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
        if (@typeInfo(@TypeOf(context)).@"struct".field_names.len != 3) @compileError("register every bounds Context field in the receipt");
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
        if (receipt.module == module and receipt.symbol_count == context.symbol_count and receipt.source_length == context.source_length) return;
    };
    try @import("frozen_core_validation.zig").validateBounds(module, context);
    if (!same_context or owner.bounds_count == owner.bounds_receipts.len) return;
    owner.bounds_receipts[owner.bounds_count] = .{ .module = module, .symbol_count = context.symbol_count, .source_length = context.source_length };
    owner.bounds_count += 1;
}
