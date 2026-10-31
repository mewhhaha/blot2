//! Lexical package authority over immutable Core. Bounds/cycles/catalogs are
//! checked by the enclosing reader before this independently reconstructs uses.
const core = @import("core.zig");
const std = @import("std");
const T = @import("types.zig");
const contracts = @import("package_contracts.zig");
const Error = error{InvalidArtifact};
const Equations = @import("scheme_equations.zig");
fn require(ok: bool) Error!void {
    if (!ok) return error.InvalidArtifact;
}
/// Successful lexical proofs for exactly one immutable compilation environment.
/// This is never serialized or retained across source revisions. It caches
/// bodies, not instantiated signatures, call rows, handlers or borrow scopes.
pub const SourceProofCache = struct {
    const TargetKey = struct { unit: u32, target_unit: u32, target_binding: core.BindingId };
    const FactKey = struct { unit: u32, root: T.Id };
    const HeaderKey = struct {
        producer: core.BindingRef,
        kind: T.ObligationKind,
        name: u32,
        operator: T.Operator,
        identity: T.NominalIdentity,
    };
    allocator: std.mem.Allocator,
    units: []const *const core.Module,
    completed: std.AutoHashMapUnmanaged(core.BindingRef, void) = .empty,
    targets: std.AutoHashMapUnmanaged(TargetKey, std.ArrayList(core.BindingId)) = .empty,
    indexed_catalogs: std.AutoHashMapUnmanaged(u32, void) = .empty,
    usage_facts: std.AutoHashMapUnmanaged(FactKey, bool) = .empty,
    absent_headers: std.AutoHashMapUnmanaged(HeaderKey, void) = .empty,
    module_work: ?[]usize = null,
    exhausted_unit: ?u32 = null,
    pub fn init(allocator: std.mem.Allocator, units: []const *const core.Module) Equations.Error!SourceProofCache {
        if (units.len == 0) return error.InvalidArtifact;
        for (units, 0..) |unit, index| {
            if (unit.unit == 0) return error.InvalidArtifact;
            for (units[0..index]) |prior| if (prior == unit or prior.unit == unit.unit) return error.InvalidArtifact;
        }
        return .{ .allocator = allocator, .units = try allocator.dupe(*const core.Module, units) };
    }
    /// Opt-in source checking envelope: each immutable module keeps one shared
    /// allowance across all roots and recursive bodies. The total is bounded
    /// by the validated module inventory times this unchanged local allowance.
    /// `init` retains the caller's explicit global-budget contract.
    pub fn initWithModuleBudget(allocator: std.mem.Allocator, units: []const *const core.Module, work_per_module: usize) Equations.Error!SourceProofCache {
        if (work_per_module == 0) return error.InvalidArtifact;
        _ = std.math.mul(usize, units.len, work_per_module) catch return error.InvalidArtifact;
        var cache = try init(allocator, units);
        errdefer cache.deinit();
        const work = try allocator.alloc(usize, units.len);
        @memset(work, work_per_module);
        cache.module_work = work;
        return cache;
    }
    /// Source-only inventory envelope for large, finite modules. Small units
    /// retain one million work steps; larger immutable graphs receive 256
    /// steps per node/word, capped at 32 million for each module. The whole
    /// compilation is consequently bounded by 32 million times its module
    /// inventory. No completed lookup or nested body replenishes an allowance.
    /// Explicit global and fixed-module budget APIs above remain unchanged.
    pub fn initWithInventoryBudget(allocator: std.mem.Allocator, units: []const *const core.Module) Equations.Error!SourceProofCache {
        const base: usize = 1_000_000;
        const cap: usize = 32_000_000;
        _ = std.math.mul(usize, units.len, cap) catch return error.InvalidArtifact;
        var cache = try initWithModuleBudget(allocator, units, base);
        errdefer cache.deinit();
        for (units, cache.module_work.?) |unit, *remaining| {
            var inventory: usize = 0;
            for ([_]usize{ unit.nodes.len, unit.extra.len, unit.types.nodes.len, unit.types.extra.len, unit.obligations.len }) |count|
                inventory = std.math.add(usize, inventory, count) catch return error.InvalidArtifact;
            const proportional = std.math.mul(usize, inventory, 256) catch return error.InvalidArtifact;
            remaining.* = @min(cap, @max(base, proportional));
        }
        return cache;
    }
    pub fn moduleRemaining(self: *const SourceProofCache, unit: u32) ?usize {
        const work = self.module_work orelse return null;
        for (self.units, work) |owner, remaining| if (owner.unit == unit) return remaining;
        return null;
    }
    pub fn exhaustedUnit(self: *const SourceProofCache) ?u32 {
        return self.exhausted_unit;
    }
    pub fn remainingTotal(self: *const SourceProofCache) ?usize {
        const work = self.module_work orelse return null;
        var total: usize = 0;
        for (work) |remaining| total += remaining;
        return total;
    }
    fn moduleWork(self: *SourceProofCache, module: *const core.Module) ?*usize {
        const work = self.module_work orelse return null;
        for (self.units, 0..) |owner, index| if (owner == module) return &work[index];
        return null;
    }
    pub fn deinit(self: *SourceProofCache) void {
        var targets = self.targets.valueIterator();
        while (targets.next()) |bindings| bindings.deinit(self.allocator);
        self.targets.deinit(self.allocator);
        self.indexed_catalogs.deinit(self.allocator);
        self.usage_facts.deinit(self.allocator);
        self.absent_headers.deinit(self.allocator);
        if (self.module_work) |work| self.allocator.free(work);
        self.completed.deinit(self.allocator);
        self.allocator.free(self.units);
        self.* = undefined;
    }
    fn environment(self: *const SourceProofCache, units: []const *const core.Module) bool {
        return std.mem.eql(*const core.Module, self.units, units);
    }
    fn owns(self: *const SourceProofCache, module: *const core.Module) bool {
        for (self.units) |unit| if (unit == module) return true;
        return false;
    }
    fn contains(self: *const SourceProofCache, module: *const core.Module, binding: core.BindingId) bool {
        return self.owns(module) and self.completed.contains(.{ .unit = module.unit, .binding = binding });
    }
    fn reserve(self: *SourceProofCache, count: usize) Equations.Error!void {
        const extra = std.math.cast(u32, count) orelse return error.InvalidArtifact;
        try self.completed.ensureUnusedCapacity(self.allocator, extra);
    }
    fn publish(self: *SourceProofCache, module: *const core.Module, binding: core.BindingId) void {
        std.debug.assert(self.owns(module));
        self.completed.putAssumeCapacity(.{ .unit = module.unit, .binding = binding }, {});
    }
    /// Immutable negative metadata, never an instantiated predicate receipt.
    /// A possible header still requires the ordinary body/type/row proof.
    fn possibleHeader(self: *SourceProofCache, initial: *const core.Module, binding: core.BindingId, wanted: core.Obligation, depth: usize, remaining: *usize) Equations.Error!bool {
        if (!self.owns(initial)) return error.InvalidArtifact;
        try headerStep(depth, remaining);
        const key: HeaderKey = .{ .producer = .{ .unit = initial.unit, .binding = binding }, .kind = wanted.kind, .name = wanted.name, .operator = wanted.operator, .identity = wanted.identity };
        if (self.absent_headers.contains(key)) return false;
        const possible = try reachableHeaderMetadata(self.allocator, self.units, initial, initial, binding, wanted, depth, remaining);
        // A failed/incomplete search, including allocation or work exhaustion,
        // cannot publish an absence. Mutable solver types never enter the key.
        if (!possible) try self.absent_headers.put(self.allocator, key, {});
        return possible;
    }
    /// A structural fact, independent of lexical/effect authority. Mutable
    /// solver graphs are inspected directly and never read or publish facts.
    pub fn containsUsage(self: *SourceProofCache, module: *const core.Module, root: T.Id, remaining: *usize) Equations.Error!bool {
        var immutable = false;
        for (self.units) |owner| if (owner.unit == module.unit and
            owner.types.nodes.ptr == module.types.nodes.ptr and owner.types.nodes.len == module.types.nodes.len and
            owner.types.extra.ptr == module.types.extra.ptr and owner.types.extra.len == module.types.extra.len and
            owner.nominals.ptr == module.nominals.ptr and owner.nominals.len == module.nominals.len)
        {
            immutable = true;
            break;
        };
        const key: FactKey = .{ .unit = module.unit, .root = root };
        if (remaining.* == 0) return error.InvalidArtifact;
        remaining.* -= 1;
        if (immutable) if (self.usage_facts.get(key)) |fact| return fact;
        var work: @import("usage_check.zig").Work = .{ .remaining = remaining.* };
        defer remaining.* = work.remaining;
        const fact = @import("usage_check.zig").containsNominalWork(&module.types, module.nominals, root, &work) catch return error.InvalidArtifact;
        if (immutable) try self.usage_facts.put(self.allocator, key, fact);
        return fact;
    }
    fn targetBindings(self: *SourceProofCache, module: *const core.Module, target_: core.BindingRef, remaining: *usize) Equations.Error![]const core.BindingId {
        // Solver views replace only the type graph. Index the exact immutable
        // binding catalog they borrow, never the substituted type environment.
        var catalog: ?*const core.Module = null;
        for (self.units) |owner| if (owner.unit == module.unit and owner.bindings.ptr == module.bindings.ptr and owner.bindings.len == module.bindings.len) {
            catalog = owner;
            break;
        };
        const source = catalog orelse return error.InvalidArtifact;
        if (!self.indexed_catalogs.contains(source.unit)) try self.indexCatalog(source, remaining);
        const key: TargetKey = .{ .unit = module.unit, .target_unit = target_.unit, .target_binding = target_.binding };
        return if (self.targets.get(key)) |bindings| bindings.items else &.{};
    }
    /// Index exact declaration targets once, preserving ordinal order and both
    /// local target spellings. This is catalog lookup only: each matched binding
    /// still proves its producer link, instantiated signature and performed rows.
    fn indexCatalog(self: *SourceProofCache, module: *const core.Module, remaining: *usize) Equations.Error!void {
        var pending: std.AutoHashMapUnmanaged(TargetKey, std.ArrayList(core.BindingId)) = .empty;
        defer pending.deinit(self.allocator);
        errdefer {
            var lists = pending.valueIterator();
            while (lists.next()) |list| list.deinit(self.allocator);
        }
        for (module.bindings, 0..) |binding, ordinal| {
            if (remaining.* == 0) return error.InvalidArtifact;
            remaining.* -= 1;
            const id: core.BindingId = @intCast(ordinal);
            const targets = [_]core.BindingRef{ .{ .binding = id }, .{ .unit = module.unit, .binding = id }, binding.target };
            for (targets[0..if (binding.kind == .external) @as(usize, 3) else 2]) |target_| {
                const item = try pending.getOrPut(self.allocator, .{ .unit = module.unit, .target_unit = target_.unit, .target_binding = target_.binding });
                if (!item.found_existing) item.value_ptr.* = .empty;
                try item.value_ptr.append(self.allocator, id);
            }
        }
        // Allocate before publication; a failed index leaves no partial facts.
        try self.targets.ensureUnusedCapacity(self.allocator, pending.count());
        try self.indexed_catalogs.ensureUnusedCapacity(self.allocator, 1);
        var entries = pending.iterator();
        while (entries.next()) |entry| self.targets.putAssumeCapacity(entry.key_ptr.*, entry.value_ptr.*);
        self.indexed_catalogs.putAssumeCapacity(module.unit, {});
    }
};
fn headerStep(depth: usize, remaining: *usize) Equations.Error!void {
    if (depth >= 128 or remaining.* == 0) return error.InvalidArtifact;
    remaining.* -= 1;
}
fn headerModule(units: []const *const core.Module, origin: *const core.Module, unit: u32) Equations.Error!*const core.Module {
    if (unit == origin.unit) return origin;
    for (units) |owner| if (owner.unit == unit) return owner;
    return error.InvalidArtifact;
}
/// Conservative closure search over declaration catalogs only. Both cached and
/// uncached callers use the same search; no lexical/solver facts are consulted.
fn reachableHeaderMetadata(allocator: std.mem.Allocator, units: []const *const core.Module, origin: *const core.Module, initial: *const core.Module, binding: core.BindingId, wanted: core.Obligation, depth: usize, remaining: *usize) Equations.Error!bool {
    var pending: std.ArrayList(core.BindingRef) = .empty;
    defer pending.deinit(allocator);
    var visited: std.AutoHashMapUnmanaged(core.BindingRef, void) = .empty;
    defer visited.deinit(allocator);
    try pending.append(allocator, .{ .unit = initial.unit, .binding = binding });
    while (pending.pop()) |reference_| {
        var reference = reference_;
        var owner = try headerModule(units, origin, reference.unit);
        var forwards: usize = 0;
        while (true) {
            try headerStep(depth + forwards, remaining);
            if (reference.binding == 0 or reference.binding >= owner.bindings.len) return error.InvalidArtifact;
            const declaration = owner.binding(reference.binding);
            if (declaration.kind != .external) break;
            var target_ = declaration.target;
            if (target_.unit == 0) target_.unit = owner.unit;
            const next = try headerModule(units, origin, target_.unit);
            if (target_.binding == 0 or target_.binding >= next.bindings.len) return error.InvalidArtifact;
            const imported = next.binding(target_.binding);
            if (declaration.public_variables.len != imported.public_variables.len or declaration.public_rows.len != imported.public_rows.len) return error.InvalidArtifact;
            reference = target_;
            owner = next;
            forwards += 1;
        }
        reference.unit = owner.unit;
        const seen = try visited.getOrPut(allocator, reference);
        if (seen.found_existing) continue;
        const declaration = owner.binding(reference.binding);
        // Unknown lexical producers are not evidence for a negative result.
        if (declaration.kind != .global or owner.body(reference.binding) == null) return true;
        for (owner.obligations[declaration.scheme.obligations.start..][0..declaration.scheme.obligations.len]) |goal| {
            try headerStep(depth, remaining);
            if (goal.kind == .callee_use) {
                try pending.append(allocator, .{ .unit = if (goal.identity.unit == 0) owner.unit else goal.identity.unit, .binding = goal.identity.decl });
            } else if (goal.kind == wanted.kind and goal.name == wanted.name and goal.operator == wanted.operator and std.meta.eql(goal.identity, wanted.identity)) return true;
        }
    }
    return false;
}
const Admission = Equations.Admission;
fn headerTestModule(unit: u32, bindings: []core.Binding, bodies: []core.Body, obligations: []core.Obligation) core.Module {
    return .{
        .unit = unit,
        .types = .{ .nodes = &.{}, .extra = &.{} },
        .nodes = &.{},
        .spans = &.{},
        .extra = &.{},
        .bindings = bindings,
        .bodies = bodies,
        .parameters = &.{},
        .references = &.{},
        .calls = &.{},
        .merges = &.{},
        .merge_ranges = &.{},
        .names = &.{},
        .obligations = obligations,
        .diagnostics = &.{},
        .body_lowerings = 0,
    };
}
fn headerTestBinding(kind: @FieldType(core.Binding, "kind"), first: u32, count: u32) core.Binding {
    return .{ .kind = kind, .body_id = if (kind == .global) 1 else 0, .ty = 0, .scheme = .{ .obligations = .{ .start = first, .len = count } }, .target = .{ .binding = 0 }, .span = .{ .start = 0, .end = 0 } };
}
fn headerMemoScenario(allocator: std.mem.Allocator) !void {
    var bodies = [_]core.Body{ .{}, .{} };
    var first_bindings = [_]core.Binding{ headerTestBinding(.local, 0, 0), headerTestBinding(.global, 0, 2), headerTestBinding(.local, 0, 0), headerTestBinding(.global, 2, 1) };
    var first_goals = [_]core.Obligation{
        .{ .ty = 1, .kind = .callee_use, .identity = .{ .unit = 2, .decl = 1 }, .span = .{ .start = 0, .end = 0 } },
        .{ .ty = 1, .kind = .callee_use, .identity = .{ .unit = 3, .decl = 1 }, .span = .{ .start = 0, .end = 0 } },
        .{ .ty = 1, .kind = .field, .name = 99, .span = .{ .start = 0, .end = 0 } },
    };
    var proxy_bindings = [_]core.Binding{ headerTestBinding(.local, 0, 0), headerTestBinding(.external, 0, 0) };
    proxy_bindings[1].target = .{ .unit = 4, .binding = 1 };
    var branch_bindings = [_]core.Binding{ headerTestBinding(.local, 0, 0), headerTestBinding(.global, 0, 1) };
    var branch_goals = [_]core.Obligation{.{ .ty = 1, .kind = .callee_use, .identity = .{ .unit = 4, .decl = 1 }, .span = .{ .start = 0, .end = 0 } }};
    var leaf_bindings = [_]core.Binding{ headerTestBinding(.local, 0, 0), headerTestBinding(.global, 0, 6), headerTestBinding(.global, 6, 1) };
    var leaf_goals = [_]core.Obligation{
        .{ .ty = 1, .kind = .field, .name = 17, .span = .{ .start = 0, .end = 0 } },
        .{ .ty = 1, .kind = .writable_field, .name = 99, .span = .{ .start = 0, .end = 0 } },
        .{ .ty = 1, .kind = .field, .name = 99, .operator = .add, .span = .{ .start = 0, .end = 0 } },
        .{ .ty = 1, .kind = .field, .name = 99, .identity = .{ .unit = 1, .decl = 0 }, .span = .{ .start = 0, .end = 0 } },
        .{ .ty = 1, .kind = .field, .name = 99, .identity = .{ .unit = 0, .decl = 1 }, .span = .{ .start = 0, .end = 0 } },
        .{ .ty = 1, .kind = .callee_use, .identity = .{ .unit = 1, .decl = 1 }, .span = .{ .start = 0, .end = 0 } },
        .{ .ty = 1, .kind = .field, .name = 99, .span = .{ .start = 0, .end = 0 } },
    };
    var broken_bindings = [_]core.Binding{ headerTestBinding(.local, 0, 0), headerTestBinding(.external, 0, 0), headerTestBinding(.external, 0, 0) };
    broken_bindings[1].target = .{ .unit = 4, .binding = 1 };
    broken_bindings[1].public_variables.len = 1;
    broken_bindings[2].target = .{ .unit = 999, .binding = 1 };
    const first = headerTestModule(1, &first_bindings, &bodies, &first_goals);
    const proxy = headerTestModule(2, &proxy_bindings, &bodies, &.{});
    const branch = headerTestModule(3, &branch_bindings, &bodies, &branch_goals);
    const leaf = headerTestModule(4, &leaf_bindings, &bodies, &leaf_goals);
    const broken = headerTestModule(5, &broken_bindings, &bodies, &.{});
    var cache = try SourceProofCache.init(allocator, &.{ &first, &proxy, &branch, &leaf, &broken });
    defer cache.deinit();
    const wanted = first_goals[2];
    var remaining: usize = 1000;
    // A possible header beyond a proxy/diamond must not be cached as authority.
    for (leaf_goals[0..5]) |present| {
        try std.testing.expect(try cache.possibleHeader(&first, 1, present, 0, &remaining));
        try std.testing.expectEqual(@as(u32, 0), cache.absent_headers.count());
    }
    try std.testing.expect(try cache.possibleHeader(&first, 2, wanted, 0, &remaining));
    try std.testing.expectEqual(@as(u32, 0), cache.absent_headers.count());
    remaining = 2;
    if (cache.possibleHeader(&first, 1, wanted, 0, &remaining)) |_| return error.TestExpectedError else |err| {
        try std.testing.expectEqual(@as(u32, 0), cache.absent_headers.count());
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.InvalidArtifact, err);
    }
    remaining = 1000;
    try std.testing.expectError(error.InvalidArtifact, cache.possibleHeader(&first, 1, wanted, 128, &remaining));
    for ([_]core.BindingId{ 1, 2 }) |invalid| {
        if (cache.possibleHeader(&broken, invalid, wanted, 0, &remaining)) |_| return error.TestExpectedError else |err| {
            try std.testing.expectEqual(@as(u32, 0), cache.absent_headers.count());
            if (err == error.OutOfMemory) return err;
            try std.testing.expectEqual(error.InvalidArtifact, err);
        }
    }
    try std.testing.expectEqual(@as(u32, 0), cache.absent_headers.count());
    remaining = 1000;
    const result = cache.possibleHeader(&first, 1, wanted, 0, &remaining) catch |err| {
        try std.testing.expectEqual(@as(u32, 0), cache.absent_headers.count());
        return err;
    };
    try std.testing.expect(!result);
    try std.testing.expectEqual(@as(u32, 1), cache.absent_headers.count());
    remaining = 1;
    try std.testing.expect(!try cache.possibleHeader(&first, 1, wanted, 0, &remaining));
    try std.testing.expectEqual(@as(usize, 0), remaining);
    try std.testing.expectError(error.InvalidArtifact, cache.possibleHeader(&first, 1, wanted, 0, &remaining));
    remaining = 1000;
    // Every header component, as well as producer unit/binding, stays exact.
    for (leaf_goals[0..5]) |present| try std.testing.expect(try cache.possibleHeader(&first, 1, present, 0, &remaining));
    try std.testing.expect(try cache.possibleHeader(&first, 3, wanted, 0, &remaining));
    try std.testing.expect(try cache.possibleHeader(&leaf, 2, wanted, 0, &remaining));
    var different_bindings = first_bindings;
    var different_view = first;
    different_view.bindings = &different_bindings;
    try std.testing.expectError(error.InvalidArtifact, cache.possibleHeader(&different_view, 1, wanted, 0, &remaining));
    // A different immutable environment sees a newly present header. No result
    // is shared by unit numbers, solver substitutions, or a retained revision.
    var changed_bindings = leaf_bindings;
    changed_bindings[1].scheme.obligations.len = 7;
    const changed = headerTestModule(4, &changed_bindings, &bodies, &leaf_goals);
    var fresh = try SourceProofCache.init(allocator, &.{ &first, &proxy, &branch, &changed, &broken });
    defer fresh.deinit();
    try std.testing.expect(try fresh.possibleHeader(&first, 1, wanted, 0, &remaining));
    try std.testing.expectEqual(@as(u32, 0), fresh.absent_headers.count());
    // Uncached calls retain their lexical origin even when the context only
    // lists the imported producer and its summary points back into the caller.
    var return_bindings = [_]core.Binding{ headerTestBinding(.local, 0, 0), headerTestBinding(.global, 0, 1) };
    var return_goals = [_]core.Obligation{.{ .ty = 1, .kind = .callee_use, .identity = .{ .unit = 1, .decl = 3 }, .span = .{ .start = 0, .end = 0 } }};
    const returning = headerTestModule(6, &return_bindings, &bodies, &return_goals);
    try std.testing.expect(try reachableHeaderMetadata(allocator, &.{&returning}, &first, &returning, 1, wanted, 0, &remaining));
}
test "source header absence memo preserves forwarding keys budgets and atomic failure" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, headerMemoScenario, .{});
}
test "source goal header rejection preserves epochs while failed type proofs still roll back" {
    const allocator = std.testing.allocator;
    var source = try T.Store.init(allocator);
    defer source.deinit();
    var module = headerTestModule(1, &.{}, &.{}, &.{});
    module.types = .{ .nodes = source.nodes.items, .extra = source.extra.items, .effects = .{ .rows = source.effects.rows.items, .labels = source.effects.labels.items, .variable_count = @intCast(source.effects.variables.items.len) }, .operations = source.operations.items };
    var remaining: usize = 65_536;
    var scopes: contracts.Context = .{ .types = &module.types, .remaining = &remaining };
    var solver = try Equations.Solver.init(allocator, &module, &scopes, &remaining);
    defer solver.deinit();
    solver.view = &module.types;
    solver.refresh();
    scopes.solver = &solver;
    var workspace: Equations.Workspace = .{ .allocator = allocator };
    var admission: Admission = .{ .remaining = &remaining, .workspace = &workspace, .source_bodies = true };
    var walker: Walker = .{ .module = &module, .context = .{}, .scopes = &scopes, .admission = &admission };
    const warm_variable = try solver.store.fresh();
    const warm_root = try solver.store.array(warm_variable);
    solver.refresh();
    try solver.unify(warm_variable, T.u32_type);
    const warmed = try solver.resolve(warm_root);
    const resolution_steps = solver.store.resolution_steps;
    const wanted: core.Obligation = .{ .ty = T.u32_type, .kind = .field, .name = 17, .span = .{ .start = 0, .end = 0 } };
    var mismatches: [5]core.Obligation = undefined;
    @memset(&mismatches, wanted);
    mismatches[0].kind = .writable_field;
    mismatches[1].name = 18;
    mismatches[2].operator = .add;
    mismatches[3].identity.unit = 2;
    mismatches[4].identity.decl = 3;
    for (mismatches) |given| {
        const type_epoch = solver.store.mutation_epoch;
        const effect_epoch = solver.store.effects.mutation_epoch;
        const physical_epoch = solver.store.effects.physical_epoch;
        var proof: contracts.Principal = .{ .left = &module.types, .right = &module.types, .remaining = &remaining, .views = &scopes, .foreign_views = true };
        try std.testing.expect(!try walker.goalMatches(&proof, wanted, given, false));
        try std.testing.expectEqual(type_epoch, solver.store.mutation_epoch);
        try std.testing.expectEqual(effect_epoch, solver.store.effects.mutation_epoch);
        try std.testing.expectEqual(physical_epoch, solver.store.effects.physical_epoch);
        try std.testing.expect(!proof.foreign_views);
        try std.testing.expectEqual(warmed, try solver.resolve(warm_root));
        try std.testing.expectEqual(resolution_steps, solver.store.resolution_steps);
    }
    var different_type = wanted;
    different_type.ty = T.f32_type;
    const unchanged_mark = solver.store.mark();
    const unchanged_type_epoch = solver.store.mutation_epoch;
    const unchanged_effect_epoch = solver.store.effects.mutation_epoch;
    const unchanged_physical_epoch = solver.store.effects.physical_epoch;
    var read_proof: contracts.Principal = .{ .left = &module.types, .right = &module.types, .remaining = &remaining, .views = &scopes };
    try std.testing.expect(!try walker.goalMatches(&read_proof, wanted, different_type, false));
    try std.testing.expectEqualDeep(unchanged_mark, solver.store.mark());
    try std.testing.expectEqual(unchanged_type_epoch, solver.store.mutation_epoch);
    try std.testing.expectEqual(unchanged_effect_epoch, solver.store.effects.mutation_epoch);
    try std.testing.expectEqual(unchanged_physical_epoch, solver.store.effects.physical_epoch);
    try std.testing.expectEqual(warmed, try solver.resolve(warm_root));
    try std.testing.expectEqual(resolution_steps, solver.store.resolution_steps);
    const fresh = try solver.store.fresh();
    const left = try solver.store.product(&.{ fresh, T.u32_type });
    const right = try solver.store.product(&.{ T.f32_type, T.f32_type });
    solver.refresh();
    var first = wanted;
    var second = wanted;
    first.ty = left;
    second.ty = right;
    const epoch = solver.store.mutation_epoch;
    var proof: contracts.Principal = .{ .left = &module.types, .right = &module.types, .remaining = &remaining, .views = &scopes };
    // The first tuple element can unify, but the second rejects. That actual
    // speculative proof must still revoke its binding and resolution epoch.
    try std.testing.expect(!try walker.goalMatches(&proof, first, second, false));
    try std.testing.expectEqual(fresh, solver.store.head(fresh, 0));
    try std.testing.expect(solver.store.mutation_epoch > epoch);
    second.ty = try solver.store.product(&.{ T.f32_type, T.u32_type });
    solver.refresh();
    proof = .{ .left = &module.types, .right = &module.types, .remaining = &remaining, .views = &scopes };
    try std.testing.expect(try walker.goalMatches(&proof, first, second, false));
    try std.testing.expectEqual(T.f32_type, solver.store.head(fresh, 0));
    solver.store.mutation_epoch = std.math.maxInt(u64);
    const saturated_generation = solver.store.closed_generation;
    proof = .{ .left = &module.types, .right = &module.types, .remaining = &remaining, .views = &scopes };
    try std.testing.expect(!try walker.goalMatches(&proof, wanted, different_type, false));
    try std.testing.expect(solver.store.closed_generation > saturated_generation);
}
test "source target catalog indexes exact aliases once and publishes atomically" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, targetCatalogScenario, .{});
}
fn targetCatalogScenario(allocator: std.mem.Allocator) !void {
    var bindings = [_]core.Binding{
        .{ .kind = .local, .ty = T.u32_type, .scheme = .{}, .target = .{ .binding = 0 }, .span = .{ .start = 0, .end = 0 } },
        .{ .kind = .external, .ty = T.u32_type, .scheme = .{}, .target = .{ .unit = 2, .binding = 7 }, .span = .{ .start = 0, .end = 0 } },
        .{ .kind = .external, .ty = T.u32_type, .scheme = .{}, .target = .{ .unit = 2, .binding = 7 }, .span = .{ .start = 0, .end = 0 } },
        .{ .kind = .external, .ty = T.u32_type, .scheme = .{}, .target = .{ .binding = 1 }, .span = .{ .start = 0, .end = 0 } },
    };
    const module: core.Module = .{
        .unit = 1,
        .types = .{ .nodes = &.{}, .extra = &.{} },
        .nodes = &.{},
        .spans = &.{},
        .extra = &.{},
        .bindings = &bindings,
        .bodies = &.{},
        .parameters = &.{},
        .references = &.{},
        .calls = &.{},
        .merges = &.{},
        .merge_ranges = &.{},
        .names = &.{},
        .obligations = &.{},
        .diagnostics = &.{},
        .body_lowerings = 0,
    };
    var cache = try SourceProofCache.init(allocator, &.{&module});
    defer cache.deinit();
    var remaining: usize = bindings.len - 1;
    if (cache.targetBindings(&module, .{ .unit = 2, .binding = 7 }, &remaining)) |_| return error.TestExpectedError else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.InvalidArtifact, err);
    }
    try std.testing.expectEqual(@as(u32, 0), cache.targets.count());
    try std.testing.expectEqual(@as(u32, 0), cache.indexed_catalogs.count());
    remaining = bindings.len;
    try std.testing.expectEqualSlices(core.BindingId, &.{ 1, 2 }, try cache.targetBindings(&module, .{ .unit = 2, .binding = 7 }, &remaining));
    try std.testing.expectEqual(@as(usize, 0), remaining);
    // Distinct local spellings remain exact: only the unqualified target has
    // the extra imported alias. Hits and absent targets spend no further scan.
    try std.testing.expectEqualSlices(core.BindingId, &.{ 1, 3 }, try cache.targetBindings(&module, .{ .binding = 1 }, &remaining));
    try std.testing.expectEqualSlices(core.BindingId, &.{1}, try cache.targetBindings(&module, .{ .unit = 1, .binding = 1 }, &remaining));
    try std.testing.expectEqual(@as(usize, 0), (try cache.targetBindings(&module, .{ .unit = 9, .binding = 7 }, &remaining)).len);
}
fn sourceRowIndexScenario(allocator: std.mem.Allocator) !void {
    const rows = try allocator.alloc(T.Effects.Row, 5001);
    defer allocator.free(rows);
    for (rows, 0..) |*row, id| row.* = .{ .tail = .{ .variable = @intCast(id * 2) } };
    var module: core.Module = .{
        .unit = 1,
        .types = .{ .nodes = &.{}, .extra = &.{}, .effects = .{ .rows = rows, .variable_count = 10001 } },
        .nodes = &.{},
        .spans = &.{},
        .extra = &.{},
        .bindings = &.{},
        .bodies = &.{},
        .parameters = &.{},
        .references = &.{},
        .calls = &.{},
        .merges = &.{},
        .merge_ranges = &.{},
        .names = &.{},
        .obligations = &.{},
        .diagnostics = &.{},
        .body_lowerings = 0,
    };
    var remaining: usize = 1_000_000;
    var workspace: Equations.Workspace = .{ .allocator = allocator };
    var admission: Admission = .{ .remaining = &remaining, .workspace = &workspace, .source_bodies = true };
    defer {
        for (admission.source_rows.items) |index| allocator.free(index.rows);
        admission.source_rows.deinit(allocator);
    }
    var scopes: contracts.Context = .{ .types = &module.types, .remaining = &remaining, .large_plain_graph = true, .source_instances = true };
    var walker: Walker = .{ .module = &module, .context = .{}, .scopes = &scopes, .admission = &admission };
    const selected = walker.rowsForVariable(10000) catch |err| return if (workspace.oom) error.OutOfMemory else err;
    try std.testing.expectEqualSlices(T.Effects.Id, &.{5000}, selected);
    try std.testing.expect(!scopes.closed_rows.contains(5000) and !scopes.pure_rows.contains(5000));
    var second: Walker = .{ .module = &module, .context = .{}, .scopes = &scopes, .admission = &admission };
    const before = remaining;
    try std.testing.expectEqualSlices(T.Effects.Id, &.{5000}, try second.rowsForVariable(10000));
    try std.testing.expect(before - remaining < 20);
    try std.testing.expectEqual(@as(usize, 0), (try second.rowsForVariable(9999)).len);
    var exhausted: Admission = .{ .remaining = &remaining, .workspace = &workspace, .source_bodies = true };
    defer exhausted.source_rows.deinit(allocator);
    var failed: Walker = .{ .module = &module, .context = .{}, .scopes = &scopes, .admission = &exhausted };
    remaining = 1;
    if (failed.rowsForVariable(10000)) |_| return error.TestExpectedError else |err| {
        if (workspace.oom) return error.OutOfMemory;
        try std.testing.expectEqual(error.InvalidArtifact, err);
    }
    try std.testing.expectEqual(@as(usize, 0), exhausted.source_rows.items.len);
    try std.testing.expect(failed.source_row_index == null);
}
test "source row indexes retain high identities without granting lexical authority through allocation failure" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, sourceRowIndexScenario, .{});
}

// Call-site anonymous structs must not instantiate the recursive proof engine.
const Context = struct { units: []const *const core.Module = &.{}, source_proofs: ?*SourceProofCache = null };
fn contextView(context: anytype) Context {
    return .{ .units = if (@hasField(@TypeOf(context), "units")) context.units else &.{}, .source_proofs = if (@hasField(@TypeOf(context), "source_proofs")) context.source_proofs else null };
}
pub fn executable(module: *const core.Module, context: anytype) Error!void {
    var remaining: usize = 65_536;
    return executableWithBudget(module, context, &remaining);
}
pub fn executableWithBudget(module: *const core.Module, context: anytype, remaining: *usize) Error!void {
    var admission: Admission = .{ .remaining = remaining };
    try owned(module, contextView(context), &admission);
}
pub fn executableWorkspace(module: *const core.Module, context: anytype, remaining: *usize, workspace: *Equations.Workspace) Error!void {
    var admission: Admission = .{ .remaining = remaining, .workspace = workspace };
    const parent = workspace.admission;
    if (parent == null) workspace.admission = &admission;
    defer workspace.admission = parent;
    const shared = workspace.admission.?;
    try require(shared.remaining == remaining);
    try owned(module, contextView(context), shared);
}
// Bounds and catalog admission belong to the enclosing reader. This repeats
// the exact lexical body proof before retaining its abstract dictionary ABI.
pub fn parametricBody(module: *const core.Module, binding: core.BindingId, context: anytype, remaining: *usize) Error!void {
    try require(binding != 0 and binding < module.bindings.len);
    const body = module.body(binding) orelse return error.InvalidArtifact;
    try require(body.is_function);
    var admission: Admission = .{ .remaining = remaining };
    var scopes: contracts.Context = .{ .types = &module.types, .remaining = remaining, .executable = true, .obligations = module.obligations };
    try scopes.initialize();
    var walker: Walker = .{ .module = module, .context = contextView(context), .scopes = &scopes, .admission = &admission };
    try walker.proveBody(body.*);
}
/// The caller has already validated immutable Core and its dependency bounds.
/// Reconstruct one body's interface, allowing ordinary scheme equations for
/// inferred callee requirements. This does not certify the enclosing module.
pub fn checkedInterfaceBody(module: *const core.Module, binding: core.BindingId, context: anytype, remaining: *usize, allocator: std.mem.Allocator) Equations.Error!void {
    return checkedInterfaceBodyOrigin(module, binding, context, remaining, allocator, null, null);
}
/// A caller-owned cache must belong to the exact immutable module environment.
/// Each actual call still proves its instantiated signature and performed rows.
pub fn checkedInterfaceBodyCached(cache: *SourceProofCache, module: *const core.Module, binding: core.BindingId, remaining: *usize, failure: ?*?Equations.SourceFailure, proved: ?*std.ArrayList(core.BindingRef)) Equations.Error!void {
    if (!cache.owns(module)) return error.InvalidArtifact;
    return checkedInterfaceBodyOrigin(module, binding, .{ .units = cache.units, .source_proofs = cache }, remaining, cache.allocator, failure, proved);
}
/// Completed claims belong only to this already bounds-checked immutable source
/// context. Publish them together after every recursive header hypothesis has
/// discharged; a failed proof publishes none. They are not portable evidence.
pub fn checkedInterfaceBodyOrigin(module: *const core.Module, binding: core.BindingId, context: anytype, remaining: *usize, allocator: std.mem.Allocator, failure: ?*?Equations.SourceFailure, proved: ?*std.ArrayList(core.BindingRef)) Equations.Error!void {
    const source_context = contextView(context);
    if (source_context.source_proofs) |cache| {
        if (!cache.environment(source_context.units) or !cache.owns(module)) return error.InvalidArtifact;
        cache.exhausted_unit = null;
    }
    var workspace: Equations.Workspace = .{ .allocator = allocator };
    var admission: Admission = .{ .remaining = remaining, .workspace = &workspace, .source_bodies = true, .source_failure = failure };
    defer admission.bodies.deinit(allocator);
    defer {
        for (admission.source_rows.items) |index| allocator.free(index.rows);
        admission.source_rows.deinit(allocator);
        for (admission.source_definitions.items) |index| allocator.free(index.values);
        admission.source_definitions.deinit(allocator);
    }
    workspace.admission = &admission;
    sourceBody(module, binding, source_context, &admission) catch {
        // Temporary integration trace, compiled only with error tracing enabled.
        if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
        return if (workspace.oom) error.OutOfMemory else error.InvalidArtifact;
    };
    if (workspace.oom) return error.OutOfMemory;
    // Reserve every output before publishing any receipt. Allocation failure
    // cannot publish a partially completed proof batch.
    if (proved) |claims| try claims.ensureUnusedCapacity(allocator, admission.bodies.items.len);
    if (source_context.source_proofs) |cache| try cache.reserve(admission.bodies.items.len);
    if (proved) |claims| for (admission.bodies.items) |body| claims.appendAssumeCapacity(.{ .unit = body.module.unit, .binding = body.binding });
    if (source_context.source_proofs) |cache| for (admission.bodies.items) |body| cache.publish(body.module, body.binding);
}
/// Declaration-sized source authority. Active recursive declarations use their
/// own headers as hypotheses, just as module admission does; all reached bodies
/// must finish successfully. A failed branch rolls back every nested claim.
/// This private mode assumes the caller already validated immutable Core bounds
/// for the complete source context. It never certifies a serialized package.
fn sourceBody(module: *const core.Module, binding: core.BindingId, context: Context, admission: *Admission) Error!void {
    std.debug.assert(admission.source_bodies);
    try require(binding != 0 and binding < module.bindings.len);
    try require(module.binding(binding).kind == .global);
    const body = module.body(binding) orelse return error.InvalidArtifact;
    if (context.source_proofs) |cache| {
        try require(cache.owns(module));
        if (cache.contains(module, binding)) return;
    }
    errdefer if (admission.source_failure) |failure| {
        if (failure.* == null) failure.* = .{ .unit = module.unit, .span = body.span };
    };
    for (admission.bodies.items) |prior| if (prior.module == module and prior.binding == binding) return;
    const prior_remaining = admission.remaining;
    if (context.source_proofs) |cache| if (cache.moduleWork(module)) |work| {
        admission.remaining = work;
    };
    defer admission.remaining = prior_remaining;
    errdefer if (context.source_proofs) |cache| {
        if (cache.module_work != null and admission.remaining.* == 0 and cache.exhausted_unit == null) cache.exhausted_unit = module.unit;
    };
    try require(admission.bodies.items.len < 65_536);
    const before = admission.bodies.items.len;
    errdefer admission.bodies.shrinkRetainingCapacity(before);
    const workspace = admission.workspace orelse return error.InvalidArtifact;
    admission.bodies.append(workspace.allocator, .{ .module = module, .binding = binding }) catch {
        workspace.oom = true;
        return error.InvalidArtifact;
    };
    var scopes: contracts.Context = .{ .types = &module.types, .remaining = admission.remaining, .executable = true, .obligations = module.obligations, .large_plain_graph = true, .source_instances = true };
    try scopes.initialize();
    var walker: Walker = .{ .module = module, .context = context, .scopes = &scopes, .admission = admission };
    try walker.proveBody(body.*);
}
pub fn parametricBodyWorkspace(module: *const core.Module, binding: core.BindingId, context: anytype, remaining: *usize, workspace: *Equations.Workspace) Error!void {
    try require(binding != 0 and binding < module.bindings.len);
    const body = module.body(binding) orelse return error.InvalidArtifact;
    try require(body.is_function);
    var admission: Admission = .{ .remaining = remaining, .workspace = workspace };
    const parent = workspace.admission;
    if (parent == null) workspace.admission = &admission;
    defer workspace.admission = parent;
    const shared = workspace.admission.?;
    try require(shared.remaining == remaining);
    try owned(module, contextView(context), shared);
}
/// Caller lexical type/row owners have already been reconstructed. This proves
/// the actual declaration instance and all of its ordinary scheme predicates.
pub fn callInstance(module: *const core.Module, reference: core.BindingRef, expected: T.Id, context: anytype, scopes: *contracts.Context, remaining: *usize) Error!contracts.Principal {
    try require(scopes.types == &module.types and scopes.remaining == remaining);
    var admission: Admission = .{ .remaining = remaining };
    var walker: Walker = .{ .module = module, .context = contextView(context), .scopes = scopes, .admission = &admission };
    return walker.principalMapping(reference, expected);
}
pub fn callInstanceWorkspace(module: *const core.Module, reference: core.BindingRef, expected: T.Id, context: anytype, scopes: *contracts.Context, remaining: *usize, workspace: *Equations.Workspace) Error!contracts.Principal {
    var admission: Admission = .{ .remaining = remaining, .workspace = workspace };
    const parent = workspace.admission;
    if (parent == null) workspace.admission = &admission;
    defer workspace.admission = parent;
    const shared = workspace.admission.?;
    try require(shared.remaining == remaining);
    var walker: Walker = .{ .module = module, .context = contextView(context), .scopes = scopes, .admission = shared };
    return walker.principalMapping(reference, expected);
}
fn owned(module: *const core.Module, context: Context, admission: *Admission) Error!void {
    if (admission.workspace) |workspace| if (workspace.proved(module)) return;
    for (admission.units[0..admission.count]) |prior| if (prior == module) return;
    try require(admission.count < admission.units.len);
    const prior_count = admission.count;
    errdefer admission.count = prior_count;
    admission.units[admission.count] = module;
    admission.count += 1;
    var scopes: contracts.Context = .{ .types = &module.types, .remaining = admission.remaining, .executable = true, .obligations = module.obligations };
    try scopes.initialize();
    try require(module.bindings.len <= 4096 and module.nodes.len <= 4096);
    // Validate every copied certificate, even when no executable node calls
    // the import. The producer's own body is reconstructed recursively.
    for (module.bindings) |binding| {
        if (binding.kind != .external) continue;
        const reference = binding.target;
        if (reference.unit == 0 or reference.unit == module.unit) {
            try require(binding.scheme.closed_rows.len == 0);
            continue;
        }
        const owner = for (context.units) |candidate| {
            if (candidate.unit == reference.unit) break candidate;
        } else return error.InvalidArtifact;
        try Equations.bounds(admission.workspace, owner, .{ .units = context.units });
        try require(reference.binding != 0 and reference.binding < owner.bindings.len);
        const original = owner.bindings[reference.binding];
        if (binding.scheme.closed_rows.len == 0 and original.scheme.closed_rows.len == 0) continue;
        try require(original.kind == .global and owner.body(reference.binding) != null);
        try owned(owner, context, admission);
        var views: contracts.Context = .{ .types = &module.types, .remaining = admission.remaining, .obligations = module.obligations };
        try views.initialize();
        try views.generic(binding.scheme);
        for (module.types.effects.rows, 0..) |row, id| {
            if (row.tail != .variable) continue;
            for (module.types.list(binding.scheme.closed_rows)) |variable| {
                try require(admission.remaining.* != 0);
                admission.remaining.* -= 1;
                if (row.tail.variable != variable) continue;
                try views.closed_rows.set(id);
                if (row.labels.len == 0) try views.pure_rows.set(id);
            }
        }
        var proof: contracts.Principal = .{ .left = &owner.types, .right = &module.types, .remaining = admission.remaining, .views = &views, .left_rows = original.scheme.closed_rows };
        try proof.certifiedScheme(original.scheme, binding.scheme, owner.obligations[original.scheme.obligations.start..][0..original.scheme.obligations.len], module.obligations[binding.scheme.obligations.start..][0..binding.scheme.obligations.len]);
    }
    var opening_slots: std.bit_set.Static(4096) = .empty;
    var opening_bindings: std.bit_set.Static(4096) = .empty;
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .package_unpack) continue;
        try require(!opening_bindings.isSet(node.b));
        opening_bindings.set(node.b);
        const opening = module.packageOpening(@intCast(id));
        for (module.types.list(opening.binders), 0..) |binder, ordinal| {
            const leaf = module.types.node(binder);
            try require(leaf.tag == .bound and leaf.a == ordinal and leaf.b == 0 and leaf.c == node.b and !opening_slots.isSet(binder));
            opening_slots.set(binder);
        }
    }
    for (module.types.nodes, 0..) |node, id| {
        if (node.tag == .bound and node.b == 0 and node.c != 0) try require(opening_slots.isSet(id));
    }
    var walker: Walker = .{ .module = module, .context = contextView(context), .scopes = &scopes, .admission = admission };
    for (module.bodies) |body| try walker.proveBody(body);
    if (admission.workspace) |workspace| if (prior_count == 0) {
        // Publish the whole successfully checked component together. A nested
        // proof can still depend on an active recursive producer.
        for (admission.units[0..admission.count]) |proved| {
            if (workspace.proved(proved)) continue;
            try require(workspace.module_count < workspace.modules.len);
            workspace.modules[workspace.module_count] = proved;
            workspace.module_count += 1;
        }
    };
}
const Walker = struct {
    module: *const core.Module,
    origin: ?*const core.Module = null,
    resolver_callback: core.Id = 0,
    context: Context,
    scopes: *contracts.Context,
    admission: *Admission,
    sealed: std.bit_set.Static(4096) = .empty,
    definitions: [4096]core.Id = @splat(0),
    definitions_indexed: bool = false,
    row_index: [4096]T.Effects.Id = undefined,
    row_index_len: usize = 0,
    rows_indexed: bool = false,
    source_row_index: ?[]const T.Effects.Id = null,
    closed_rows: T.List = .{},
    foreign_allowed: bool = false,
    body_row: T.Effects.Id = 0,
    goal_depth: usize = 0,
    handled: [128]T.Id = undefined,
    handled_count: usize = 0,
    scope_owner: ?*const ScopeOwner = null,
    return_owner: ?*const ControlOwner = null,
    loop_owner: ?*const ControlOwner = null,
    decision_owner: ?*const DecisionOwner = null,
    call_owner: core.Id = 0,
    const ScopeOwner = struct { identity: T.NominalIdentity, parent: ?*const ScopeOwner };
    const ControlOwner = struct { node: core.Id, parent: ?*const ControlOwner };
    const DecisionOwner = struct { callback: core.Id, ty: T.Id };
    const Self = @This();
    fn knownInstance(self: *Self, instance: T.NominalIdentity) Error!bool {
        return self.knownInstanceDepth(instance, 0);
    }
    fn knownInstanceDepth(self: *Self, instance: T.NominalIdentity, depth: usize) Error!bool {
        try self.step(depth);
        if (instance.decl == 0) return instance.unit == 0;
        var owner = self.scope_owner;
        while (owner) |current| : (owner = current.parent) {
            try self.step(0);
            if (std.meta.eql(current.identity, instance)) return true;
        }
        if (instance.unit == 0 and instance.decl < self.module.types.nodes.len) {
            const selected = self.module.types.node(instance.decl);
            if (selected.tag != .instance_selection) return false;
            const choices = self.module.types.nominalArguments(selected);
            try require(choices.len == 2 or choices.len == 3);
            for (choices[0..2]) |choice| {
                const capability = self.module.types.node(choice);
                try require(capability.tag == .scoped);
                if (!try self.knownInstanceDepth(.{ .unit = capability.b, .decl = capability.c }, depth + 1)) return false;
            }
            return true;
        }
        return false;
    }
    fn operationAuthority(self: *Self, operation: core.OperationValue) Error!void {
        try require(operation.witness == 0 and operation.witness_result == 0 and try self.knownInstance(operation.instance));
        if (operation.instance.decl == 0) return require(operation.capability == 0);
        try require(operation.capability != 0);
        const capability = self.module.types.node(self.module.typeOf(operation.capability));
        try require(capability.tag == .scoped and capability.b == operation.instance.unit and capability.c == operation.instance.decl);
    }
    fn proveBody(self: *Self, body: core.Body) Error!void {
        if (body.root == 0) return;
        self.return_owner = null;
        self.loop_owner = null;
        self.decision_owner = null;
        // The enclosing implementation admission reconstructs these erased
        // declaration proxies, including their required scheme and operands.
        // Their contract variables are not executable package opening slots.
        const root = self.module.node(body.root);
        if (root.tag == .contract_method) {
            try require(root.a < self.module.member_templates.len);
            const template = self.module.member_templates[root.a];
            try require(template.binding == body.binding and body.is_function and root.c == body.parameters.len);
            try require(std.meta.eql(body.scheme, self.module.binding(body.binding).scheme));
            return;
        }
        self.scopes.pure_rows = .{};
        self.scopes.closed_rows = .{};
        self.closed_rows = body.closed_rows;
        try self.closeRows(body.closed_rows);
        try self.providerRows(body.root, 0);
        const signature = self.module.binding(body.binding).ty;
        self.body_row = try self.effectSignature(signature, self.module.bodyParameters(&body).len);
        self.foreign_allowed = self.rowHasForeign(self.body_row);
        try self.scopes.generic(body.scheme);
        try self.scopes.visit(signature);
        try self.same(signature, body.scheme.root);
        try self.schemeFor(body.scheme, body.binding);
        const parent = self.scope_owner;
        defer self.scope_owner = parent;
        var owners: [128]ScopeOwner = undefined;
        var count: usize = 0;
        for (self.module.bodyParameters(&body)) |parameter| {
            const ty = self.module.types.node(parameter.ty);
            if (ty.tag != .scoped) continue;
            try require(count < owners.len);
            owners[count] = .{ .identity = .{ .unit = ty.b, .decl = ty.c }, .parent = self.scope_owner };
            self.scope_owner = &owners[count];
            count += 1;
        }
        const quantified = self.module.types.node(signature).tag == .forall;
        if (quantified) {
            try self.scopes.enter(signature);
            self.scopes.introductions[self.scopes.formal_count - 1] = body.root;
        }
        defer if (quantified) self.scopes.leave();
        try self.header(signature, self.module.parameters[body.parameters.start..][0..body.parameters.len], body.root, false);
        try self.bodyStorage(self.module.parameters[body.parameters.start..][0..body.parameters.len], body.root);
        try self.expression(body.root, 0);
        try require(self.scopes.opening_count == 0);
    }
    fn units(self: *Self) []const *const core.Module {
        return self.context.units;
    }
    fn step(self: *Self, depth: usize) Error!void {
        try require(depth < 128 and self.scopes.remaining.* != 0);
        self.scopes.remaining.* -= 1;
    }
    fn same(self: *Self, first: T.Id, second: T.Id) Error!void {
        var proof: contracts.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes, .foreign_views = true };
        try proof.validate(first, second);
    }
    fn strictSame(self: *Self, first: T.Id, second: T.Id) Error!void {
        var proof: contracts.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes };
        try proof.validate(first, second);
    }
    fn scheme(self: *Self, value: T.Scheme) Error!void {
        return self.schemeFor(value, 0);
    }
    fn schemeFor(self: *Self, value: T.Scheme, body: core.BindingId) Error!void {
        try self.step(0);
        for (self.module.types.list(value.row_variables)) |variable| {
            try self.step(0);
            try require(try self.scopes.ownsRow(variable));
        }
        var assumed = false;
        for (self.scopes.schemes[0..self.scopes.scheme_count]) |owner| {
            try self.step(0);
            if (std.meta.eql(owner, value)) assumed = true;
        }
        if (body != 0) try require(std.meta.eql(self.module.binding(body).scheme, value));
        if (assumed) try @import("scheme_predicates.zig").scope(self.scopes, try self.scopes.schemeGoals(value)) else try @import("dictionary_contracts.zig").requirements(self.module, value.obligations, self.scopes, body);
        if (value.variables.len != 0) {
            const owner = self.module.types.node(value.root);
            if (owner.tag == .forall) {
                try require(value.variables.len == owner.c);
                try require(std.mem.eql(T.Id, self.module.types.list(value.variables), self.module.types.list(.{ .start = owner.b, .len = owner.c })));
            } else for (self.module.types.list(value.variables)) |variable| {
                try self.step(0);
                try require(self.module.types.node(variable).tag == .variable and try self.scopes.ownsVariable(variable));
            }
        }
        for (self.module.types.list(value.closed_rows)) |row| try require(try self.closedRowOwned(row));
        // Generative admission correlates these pairs with actual creator
        // expressions. Package admission still checks their lexical types.
        const binders = self.module.types.list(value.generative);
        try require(binders.len % 2 == 0);
        for (0..binders.len / 2) |index| {
            try require(self.module.types.node(binders[index * 2]).tag == .function);
            try require(self.module.types.node(binders[index * 2 + 1]).tag == .scoped);
            try self.scopes.visit(binders[index * 2]);
            try self.scopes.visit(binders[index * 2 + 1]);
        }
    }
    fn rowsForVariable(self: *Self, variable: u32) Error![]const T.Effects.Id {
        const index = if (self.admission.source_bodies) try self.sourceRows() else package_rows: {
            if (!self.rows_indexed) {
                for (self.module.types.effects.rows, 0..) |row, id| {
                    try self.step(0);
                    if (row.tail != .variable) continue;
                    try require(self.row_index_len < self.row_index.len);
                    self.row_index[self.row_index_len] = @intCast(id);
                    self.row_index_len += 1;
                }
                try self.sortRows(self.row_index[0..self.row_index_len]);
                self.rows_indexed = true;
            }
            break :package_rows self.row_index[0..self.row_index_len];
        };
        var first: usize = 0;
        var end = index.len;
        while (first < end) {
            try self.step(0);
            const middle = first + (end - first) / 2;
            if (self.module.types.row(index[middle]).tail.variable < variable) first = middle + 1 else end = middle;
        }
        end = first;
        while (end < index.len) : (end += 1) {
            try self.step(0);
            if (self.module.types.row(index[end]).tail.variable != variable) break;
        }
        return index[first..end];
    }
    fn sortRows(self: *Self, rows: []T.Effects.Id) Error!void {
        const Sort = struct {
            types: *const core.Types,
            remaining: *usize,
            fn less(context: @This(), first: T.Effects.Id, second: T.Effects.Id) bool {
                context.remaining.* -|= 1;
                return context.types.row(first).tail.variable < context.types.row(second).tail.variable;
            }
        };
        std.mem.sortUnstable(T.Effects.Id, rows, Sort{ .types = &self.module.types, .remaining = self.scopes.remaining }, Sort.less);
        try require(self.scopes.remaining.* != 0);
    }
    fn sourceRows(self: *Self) Error![]const T.Effects.Id {
        if (self.source_row_index) |rows| return rows;
        for (self.admission.source_rows.items) |index| if (index.module == self.module) {
            self.source_row_index = index.rows;
            return index.rows;
        };
        const workspace = self.admission.workspace orelse return error.InvalidArtifact;
        var pending: std.ArrayList(T.Effects.Id) = .empty;
        defer pending.deinit(workspace.allocator);
        for (self.module.types.effects.rows, 0..) |row, id| {
            try self.step(0);
            if (row.tail != .variable) continue;
            pending.append(workspace.allocator, @intCast(id)) catch {
                workspace.oom = true;
                return error.InvalidArtifact;
            };
        }
        try self.sortRows(pending.items);
        const rows = pending.toOwnedSlice(workspace.allocator) catch {
            workspace.oom = true;
            return error.InvalidArtifact;
        };
        errdefer workspace.allocator.free(rows);
        // Source-sized lookup only: lexical closed/pure authority stays on the
        // walker. No partial index is retained on budget or allocation failure.
        self.admission.source_rows.append(workspace.allocator, .{ .module = self.module, .rows = rows }) catch {
            workspace.oom = true;
            return error.InvalidArtifact;
        };
        self.source_row_index = rows;
        return rows;
    }
    fn closeRows(self: *Self, owned_rows: T.List) Error!void {
        for (self.module.types.list(owned_rows)) |variable| {
            for (try self.rowsForVariable(variable)) |id| {
                try self.scopes.closed_rows.set(id);
                if (self.module.types.row(id).labels.len == 0) try self.scopes.pure_rows.set(id);
            }
        }
    }
    fn closedRowOwned(self: *Self, variable: u32) Error!bool {
        if (std.mem.findScalar(u32, self.module.types.list(self.closed_rows), variable) != null) return true;
        for (try self.rowsForVariable(variable)) |id| if (self.scopes.closed_rows.contains(id)) return true;
        return false;
    }
    fn providerRows(self: *Self, source: core.Id, depth: usize) Error!void {
        try self.step(depth);
        const node = self.module.node(source);
        if (node.tag == .operation_value) {
            const operation = self.module.operationValue(source);
            try self.operationAuthority(operation);
            const signature = self.module.types.node(operation.signature);
            const view = self.module.types.node(node.ty);
            try require(signature.tag == .function and view.tag == .function);
            const row = self.module.types.row(signature.c);
            // An operation intrinsically performs only its exact owned
            // selector. Its contextual empty tail is a declaration view,
            // independently checked against the actual label below.
            if (row.tail == .variable and !try self.scopes.ownsRow(row.tail.variable)) try self.scopes.closed_rows.set(signature.c);
            const selected = self.module.types.row(view.c);
            if (selected.tail == .variable and !try self.scopes.ownsRow(selected.tail.variable)) try self.scopes.closed_rows.set(view.c);
            return;
        }
        if (node.tag != .effect_provider) return;
        const provider = self.module.types.node(node.ty);
        const implementation = self.module.node(node.b);
        if (provider.tag != .provider or implementation.tag != .closure) return;
        const closure = self.module.closure(node.b);
        const arrow = self.module.types.node(closure.function_type);
        if (arrow.tag != .function or arrow.c != provider.c) return;
        const row = self.module.types.row(provider.c);
        if (row.tail != .variable or std.mem.findScalar(u32, self.module.types.list(closure.closed_rows), row.tail.variable) == null) return;
        // This exact callback is checked independently below. The provider
        // retains its latent row; construction does not execute the callback.
        try self.scopes.closed_rows.set(provider.c);
        if (row.labels.len == 0) try self.scopes.pure_rows.set(provider.c);
    }
    fn target(self: *Self, reference: core.BindingRef) Error!*const core.Module {
        if (reference.unit == 0 or reference.unit == self.module.unit) return self.origin orelse self.module;
        for (self.units()) |unit| if (unit.unit == reference.unit) return unit;
        return error.InvalidArtifact;
    }
    fn containsUsage(self: *Self, root: T.Id) Error!bool {
        if (self.context.source_proofs) |cache| return cache.containsUsage(self.module, root, self.scopes.remaining) catch |err| {
            if (err == error.OutOfMemory) if (self.admission.workspace) |workspace| {
                workspace.oom = true;
            };
            return error.InvalidArtifact;
        };
        var work: @import("usage_check.zig").Work = .{ .remaining = self.scopes.remaining.* };
        defer self.scopes.remaining.* = work.remaining;
        return @import("usage_check.zig").containsNominalWork(&self.module.types, self.module.nominals, root, &work) catch return error.InvalidArtifact;
    }
    /// A large source summary can hide many prerequisite-only variables.
    /// Only observable root variables belong to the endpoint correspondence;
    /// the dynamic equation solver independently instantiates the full scheme.
    fn endpointScheme(self: *Self, owner: *const core.Module, binding: core.BindingId) Error!T.Scheme {
        const declaration = owner.binding(binding);
        var endpoint = declaration.scheme;
        if (!self.admission.source_bodies or owner.types.node(endpoint.root).tag == .forall or
            (endpoint.variables.len <= 128 and endpoint.row_variables.len <= 128)) return endpoint;
        try require(declaration.public_variables.len <= contracts.ordinary_source_type_limit and declaration.public_rows.len <= 128);
        for (owner.types.list(declaration.public_variables)) |formal| {
            try self.step(0);
            try require(std.mem.findScalar(T.Id, owner.types.list(endpoint.variables), formal) != null);
        }
        for (owner.types.list(declaration.public_rows)) |formal| {
            try self.step(0);
            try require(std.mem.findScalar(T.Id, owner.types.list(endpoint.row_variables), formal) != null);
        }
        endpoint.variables = declaration.public_variables;
        endpoint.row_variables = declaration.public_rows;
        return endpoint;
    }
    fn principal(self: *Self, reference: core.BindingRef, expected: T.Id) Error!void {
        _ = try self.principalMapping(reference, expected);
    }
    fn principalMapping(self: *Self, reference: core.BindingRef, expected: T.Id) Error!contracts.Principal {
        const instances_before = self.scopes.instance_variables;
        const rows_before = self.scopes.instance_rows;
        errdefer self.scopes.instance_variables = instances_before;
        errdefer self.scopes.instance_rows = rows_before;
        const owner = try self.target(reference);
        try require(reference.binding != 0 and reference.binding < owner.bindings.len);
        const declaration = owner.binding(reference.binding);
        var version_pairs: [16]contracts.Principal.VersionPair = undefined;
        const version_count = try self.invocationVersions(owner, reference, expected, &version_pairs);
        if (self.scopes.solver) |solver| return self.solverInstance(solver, owner, reference.binding, expected, version_pairs[0..version_count]);
        if (declaration.kind == .external) {
            try require(!try contracts.quantified(&owner.types, declaration.ty, self.scopes.remaining));
            try require(declaration.scheme.variables.len == 0 and declaration.scheme.row_variables.len == 0 and declaration.scheme.obligations.len == 0);
        }
        if (self.admission.source_bodies) {
            if (declaration.kind == .global) try sourceBody(owner, reference.binding, self.context, self.admission);
        } else if (owner != self.module) {
            // The sibling may not yet have reached its enclosing reader's
            // bounds pass. Check before following any claimed body edge.
            var checked = false;
            for (self.admission.units[0..self.admission.count]) |prior| if (prior == owner) {
                checked = true;
                break;
            };
            if (!checked) {
                try Equations.bounds(self.admission.workspace, owner, .{ .units = self.units() });
                try owned(owner, self.context, self.admission);
            }
            try require((declaration.kind == .global and owner.body(reference.binding) != null) or declaration.kind == .external);
        }
        var proof: contracts.Principal = .{ .left = &owner.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes, .foreign_views = true };
        if (owner.body(reference.binding)) |body| proof.left_rows = body.closed_rows;
        proof.version_pairs = version_pairs[0..version_count];
        const signature = owner.binding(reference.binding).ty;
        if (owner.types.node(signature).tag == .forall and self.module.types.node(expected).tag != .forall) {
            try proof.instantiateTypes(signature, expected);
            try @import("dictionary_contracts.zig").instantiated(self.module, owner, signature, proof.witnesses[0..owner.types.node(signature).c], self.scopes);
            const quantified = owner.types.node(signature);
            for (owner.types.list(.{ .start = quantified.b, .len = quantified.c }), proof.witnesses[0..quantified.c]) |binder, witness| {
                if (witness == 0 or owner.types.node(binder).b != 0) continue;
                try require(!try self.containsUsage(witness));
            }
        } else if (owner.types.node(signature).tag != .forall and (declaration.scheme.variables.len != 0 or declaration.scheme.row_variables.len != 0)) {
            var projection: @import("scheme_projection.zig").Resolver = .{ .module = self.module, .producer = owner, .binding = reference.binding };
            proof.projection_resolver = projection.resolver();
            const endpoint_scheme = try self.endpointScheme(owner, reference.binding);
            try proof.instantiateScheme(endpoint_scheme, expected);
            const quantifier_use = self.module.types.node(expected).tag == .forall;
            if (quantifier_use) try self.scopes.enter(expected);
            defer if (quantifier_use) self.scopes.leave();
            proof.instance = endpoint_scheme.variables;
            proof.instance_rows = endpoint_scheme.row_variables;
            try self.instantiatedGoals(owner, reference.binding, declaration.scheme, &proof, 0);
            if (self.admission.source_bodies and self.scopes.source_instances) {
                for (proof.scheme_row_witnesses[0..endpoint_scheme.row_variables.len]) |witness| {
                    try self.step(0);
                    const row = witness orelse continue;
                    const tail = self.module.types.row(row.row).tail;
                    if (tail == .variable) try self.scopes.instance_rows.set(tail.variable);
                }
            }
            proof.instance = .{};
            proof.instance_rows = .{};
            for (proof.witnesses[0..endpoint_scheme.variables.len]) |witness| {
                if (witness == 0) continue;
                // The independently checked identity body returns its sole
                // argument exactly once. It can forward a value carrying a
                // scoped callback contract without treating it as plain data.
                if (declaration.capability_flow == .identity or declaration.capability_flow == .consume_task or declaration.capability_flow == .spawn_task) continue;
                try require(!try self.containsUsage(witness));
            }
            // Unused fields of a known polymorphic record can retain ordinary
            // inference holes. The exact producer scheme and every prerequisite
            // above establish these instances before any leaf is admitted.
            if (self.admission.source_bodies and self.scopes.source_instances) for (proof.witnesses[0..endpoint_scheme.variables.len]) |witness| {
                if (witness != 0) try self.scopes.sourceInstance(witness, 0);
            };
        } else try proof.validate(signature, expected);
        proof.projection_resolver = null;
        proof.version_pairs = &.{};
        return proof;
    }
    fn invocationVersions(self: *Self, owner: *const core.Module, reference: core.BindingRef, expected: T.Id, pairs: *[16]contracts.Principal.VersionPair) Error!usize {
        const scheme_value = owner.binding(reference.binding).scheme;
        if (scheme_value.generative.len == 0 or self.call_owner == 0) return 0;
        const call = @import("capability_flow.zig").coreCall(self.module, self.call_owner) orelse return 0;
        if (!std.meta.eql(call.target, reference) or call.signature != expected) return 0;
        var relation = try @import("generative_relocation.zig").Relocation.init(owner, self.module, scheme_value, call.signature, self.module.typeOf(self.call_owner), call.len, self.module.span(self.call_owner).end + 1);
        if (self.module.node(self.call_owner).tag == .apply) try relation.applications(self.call_owner);
        const used = 65_536 - relation.remaining;
        try require(used <= self.scopes.remaining.*);
        self.scopes.remaining.* -= used;
        for (relation.fresh_pairs[0..relation.fresh_pair_len], 0..) |pair, index| pairs[index] = .{ .left = owner.types.node(pair.before), .right = self.module.types.node(pair.after) };
        return relation.fresh_pair_len;
    }
    fn solverInstance(self: *Self, solver: *Equations.Solver, owner: *const core.Module, binding: core.BindingId, expected: T.Id, version_pairs: []const contracts.Principal.VersionPair) Error!contracts.Principal {
        // The selected endpoint cannot substitute for the real declaration
        // and its ordinary body proof, including foreign module ownership.
        if (self.admission.source_bodies) {
            if (owner.binding(binding).kind == .global) try sourceBody(owner, binding, self.context, self.admission);
        } else if (owner != self.origin) try owned(owner, self.context, self.admission);
        const source_scheme = owner.binding(binding).scheme;
        var frozen: @import("frozen_types.zig").Graph = undefined;
        var copy = solver.importer(owner, &frozen, source_scheme) catch |err| return solver.readerError(err);
        defer copy.deinit();
        const actual = solver.copy(&copy, source_scheme.root) catch |err| return solver.readerError(err);
        var principal_value: contracts.Principal = .{ .left = self.scopes.types, .right = self.scopes.types, .remaining = self.scopes.remaining, .views = self.scopes, .foreign_views = true };
        principal_value.version_pairs = version_pairs;
        try principal_value.validate(actual, expected);
        try self.solverGoals(solver, owner, source_scheme, &copy, 0);
        principal_value.version_pairs = &.{};
        return principal_value;
    }
    fn solverGoals(self: *Self, solver: *Equations.Solver, producer: *const core.Module, source_scheme: T.Scheme, copy: *@import("check_scheme_import.zig").Copier, depth: usize) Error!void {
        const allocator = solver.store.allocator;
        const source_goals = producer.obligations[source_scheme.obligations.start..][0..source_scheme.obligations.len];
        const pending = allocator.alloc(core.Obligation, source_goals.len) catch {
            solver.oom = true;
            return error.InvalidArtifact;
        };
        defer allocator.free(pending);
        for (source_goals, pending) |goal, *destination| {
            destination.* = goal;
            inline for (.{ "ty", "other", "result", "signature" }) |field| @field(destination.*, field) = solver.copy(copy, @field(goal, field)) catch |err| return solver.readerError(err);
        }
        var count = pending.len;
        while (count != 0) {
            try self.step(depth);
            var progress = false;
            // Physical fields supply exact type equations. Establish those
            // before choosing a generic prerequisite hypothesis: otherwise a
            // fresh codec output can be guessed equal to an unrelated caller
            // buffer before the known Codec.encode field fixes its Array type.
            if (self.admission.source_bodies) {
                var physical_progress = true;
                while (physical_progress and count != 0) {
                    physical_progress = false;
                    for (pending) |*goal| {
                        if (goal.ty == 0 or (goal.kind != .field and goal.kind != .writable_field)) continue;
                        // Field identity needs only the current receiver head.
                        // Deep resolution traverses every unrelated access field
                        // again; strict field matching resolves selected children.
                        try self.step(depth);
                        goal.ty = solver.store.head(goal.ty, 0);
                        if (!try self.physicalField(goal.*, depth + 1)) continue;
                        inline for (.{ "other", "result", "signature" }) |field| {
                            try self.step(depth);
                            @field(goal.*, field) = solver.store.head(@field(goal.*, field), 0);
                        }
                        const point = solver.store.mark();
                        if (!try self.closedGoal(goal.*, depth + 1)) {
                            solver.rollback(point);
                            try require(!solver.oom);
                            continue;
                        }
                        goal.ty = 0;
                        count -= 1;
                        progress = true;
                        physical_progress = true;
                    }
                }
            }
            for (pending) |*goal| {
                if (goal.ty == 0) continue;
                inline for (.{ "ty", "other", "result", "signature" }) |field| @field(goal.*, field) = solver.resolve(@field(goal.*, field)) catch |err| return solver.readerError(err);
                const point = solver.store.mark();
                if (!try self.prerequisiteGoal(goal.*, depth + 1)) {
                    solver.rollback(point);
                    try require(!solver.oom);
                    continue;
                }
                goal.ty = 0;
                count -= 1;
                progress = true;
            }
            if (!progress) {
                for (pending) |goal| {
                    if (goal.ty == 0) continue;
                    if (self.admission.source_failure) |failure| {
                        if (failure.* == null) failure.* = .{ .unit = producer.unit, .span = goal.span };
                    }
                    break;
                }
                return error.InvalidArtifact;
            }
        }
    }
    fn physicalField(self: *Self, goal: core.Obligation, depth: usize) Error!bool {
        const owner = self.module.types.node(goal.ty);
        if (owner.tag == .record) {
            for (0..owner.b) |ordinal| {
                try self.step(depth);
                if (self.module.types.recordField(owner, ordinal).name == goal.name) return true;
            }
            return false;
        }
        if (owner.tag != .nominal or @import("storage_types.zig").identity(owner.a, owner.b) != null) return false;
        for (self.module.associated) |method| {
            try self.step(depth);
            if (method.identity.unit == owner.a and method.identity.decl == owner.b and method.member == goal.name) return false;
        }
        for (self.module.constructors) |constructor| {
            try self.step(depth);
            const family = self.module.nominals[constructor.nominal];
            if (family.identity.unit != owner.a or family.identity.decl != owner.b or family.constructors.len != 1) continue;
            const payload = self.module.types.node(constructor.payload);
            if (payload.tag != .record) continue;
            for (0..payload.b) |ordinal| {
                try self.step(depth);
                if (self.module.types.recordField(payload, ordinal).name == goal.name) return true;
            }
        }
        return false;
    }
    fn prerequisiteGoal(self: *Self, goal: core.Obligation, depth: usize) Error!bool {
        return self.prerequisiteGoalMode(goal, depth, true);
    }
    fn prerequisiteGoalMode(self: *Self, goal: core.Obligation, depth: usize, shared: bool) Error!bool {
        // Instantiating a function's prerequisites does not call that function.
        // Match check.zig's proveImplementationPredicate: the prerequisite's
        // own invocation carrier supplies its ambient. Producer/principal
        // checks still prove the actual method fits that complete signature;
        // arguments() checks real execution against the enclosing body row.
        const prior_row = self.body_row;
        defer self.body_row = prior_row;
        const signature = if (goal.kind == .resolver_dispatch) goal.other else goal.signature;
        if (signature != 0) {
            const arrow = self.module.types.node(signature);
            try require(arrow.tag == .function);
            self.body_row = arrow.c;
        }
        return try self.goalGivenMode(goal, depth + 1, shared) or try self.closedGoal(goal, depth + 1);
    }
    fn solveInstantiated(self: *Self, workspace: *Equations.Workspace, producer: *const core.Module, source_scheme: T.Scheme, mapping: *contracts.Principal, depth: usize) Error!void {
        var solver = Equations.Solver.init(workspace.allocator, self.module, self.scopes, self.scopes.remaining) catch |err| {
            if (err == error.OutOfMemory) workspace.oom = true;
            return error.InvalidArtifact;
        };
        defer solver.deinit();
        var frozen: @import("frozen_types.zig").Graph = undefined;
        var copy = solver.importer(producer, &frozen, source_scheme) catch |err| {
            if (err == error.OutOfMemory) workspace.oom = true;
            return error.InvalidArtifact;
        };
        defer copy.deinit();
        for (producer.types.list(source_scheme.variables)) |formal| {
            const ordinal = std.mem.findScalar(T.Id, mapping.left.list(mapping.instance), formal) orelse continue;
            try require(ordinal < mapping.witnesses.len);
            const witness = mapping.witnesses[ordinal];
            if (witness == 0) continue;
            const fresh = copy.mapping.get(formal) orelse return error.InvalidArtifact;
            solver.unify(fresh, witness) catch |err| {
                if (err == error.OutOfMemory) workspace.oom = true;
                return error.InvalidArtifact;
            };
        }
        for (producer.types.list(source_scheme.row_variables)) |formal| {
            const ordinal = std.mem.findScalar(T.Id, mapping.left.list(mapping.instance_rows), formal) orelse continue;
            try require(ordinal < mapping.scheme_row_witnesses.len);
            const actual = mapping.scheme_row_witnesses[ordinal] orelse continue;
            var labels: [256]T.Effects.Label = undefined;
            var length: usize = 0;
            for (solver.graph.rowLabels(actual.row), 0..) |label, index| {
                if (actual.excluded.isSet(index)) continue;
                try require(length < labels.len);
                labels[length] = label;
                length += 1;
            }
            const row = solver.store.effects.row(labels[0..length], solver.graph.row(actual.row).tail) catch |err| {
                if (err == error.OutOfMemory) workspace.oom = true;
                return error.InvalidArtifact;
            };
            copy.row_variables.put(copy.allocator, formal, row) catch {
                workspace.oom = true;
                return error.InvalidArtifact;
            };
            solver.refresh();
        }
        var temporary = self.module.*;
        solver.view = &temporary.types;
        solver.refresh();
        var scopes = self.scopes.*;
        scopes.types = &temporary.types;
        scopes.solver = &solver;
        var walker = self.*;
        walker.module = &temporary;
        walker.origin = self.origin orelse self.module;
        walker.scopes = &scopes;
        walker.solverGoals(&solver, producer, source_scheme, &copy, depth + 1) catch |err| {
            if (solver.oom) workspace.oom = true;
            return err;
        };
    }
    fn goalRows(self: *Self, signature: T.Id, arity: ?usize, depth: usize) Error!void {
        // Only applied arrows execute. In particular, selecting a callback
        // field does not execute the callback returned by the getter. The full
        // signature is still proved by goalMatches/principal before this check.
        var cursor = signature;
        var count: usize = 0;
        while ((arity == null or count < arity.?) and cursor != 0 and self.module.types.node(cursor).tag == .function) {
            try self.step(depth + count);
            const arrow = self.module.types.node(cursor);
            try self.allowedRow(arrow.c, true);
            cursor = arrow.b;
            count += 1;
        }
        try require(count != 0 and (arity == null or count == arity.?));
    }
    fn goalArity(self: *Self, kind: T.ObligationKind, signature: T.Id) ?usize {
        const arrow = self.module.types.node(signature);
        // Explicit qualifications carry one Unit -> Unit effect witness,
        // independently of the arity of the operation they qualify.
        if (arrow.tag == .function and arrow.a == T.unit and arrow.b == T.unit) return 1;
        return switch (kind) {
            .dispatch => 2,
            .field, .receiver, .result_dispatch => 1,
            else => null,
        };
    }
    fn canonicalCallee(self: *Self, identity_: T.NominalIdentity, types: *const core.Types, public: T.Id) Error!T.NominalIdentity {
        var owner = try self.target(.{ .unit = identity_.unit, .binding = identity_.decl });
        var binding = identity_.decl;
        var forwards: usize = 0;
        while (true) {
            try self.step(forwards);
            try require(binding != 0 and binding < owner.bindings.len);
            const declaration = owner.binding(binding);
            try require(public < types.nodes.len);
            const pack = types.node(public);
            try require(pack.tag == .product and pack.b == declaration.public_variables.len + declaration.public_rows.len);
            if (declaration.kind != .external) {
                try require(declaration.kind == .global and owner.body(binding) != null);
                try sourceBody(owner, binding, self.context, self.admission);
                return .{ .unit = owner.unit, .decl = binding };
            }
            var target_ = declaration.target;
            if (target_.unit == 0) target_.unit = owner.unit;
            const next = try self.target(target_);
            try require(target_.binding != 0 and target_.binding < next.bindings.len);
            const imported = next.binding(target_.binding);
            try require(declaration.public_variables.len == imported.public_variables.len and declaration.public_rows.len == imported.public_rows.len);
            owner = next;
            binding = target_.binding;
            forwards += 1;
        }
    }
    fn goalMatches(self: *Self, proof: *contracts.Principal, wanted_: anytype, given_: anytype, covariant_signature: bool) Error!bool {
        try self.step(0);
        var wanted = wanted_;
        var given = given_;
        if (self.admission.source_bodies and wanted.kind == .callee_use and given.kind == .callee_use and !std.meta.eql(wanted.identity, given.identity)) {
            // Imports preserve the checked predicate's local proxy identity.
            // The proxy and producer describe the same dictionary only when
            // their exact target chain and public argument packs agree.
            wanted.identity = try self.canonicalCallee(wanted.identity, proof.left, wanted.ty);
            given.identity = try self.canonicalCallee(given.identity, proof.right, given.ty);
        }
        proof.foreign_views = false;
        // Header rejection performs no solver operation. Avoid a vacuous
        // rollback that would revoke exact-epoch resolution caches before the
        // next, potentially relevant hypothesis is checked.
        if (wanted.kind != given.kind or wanted.name != given.name or wanted.operator != given.operator or wanted.identity.unit != given.identity.unit or wanted.identity.decl != given.identity.decl) return false;
        const solver = self.scopes.solver;
        const point = if (solver) |owner| owner.store.mark() else null;
        const type_epoch = if (solver) |owner| owner.store.mutation_epoch else 0;
        const effect_epoch = if (solver) |owner| owner.store.effects.mutation_epoch else 0;
        const physical_epoch = if (solver) |owner| owner.store.effects.physical_epoch else 0;
        var accepted = false;
        defer if (!accepted) {
            if (solver) |owner| {
                // A failed comparison can have read only: retain its derived
                // resolution caches only when every semantic store clock and
                // allocation/version boundary is unchanged. Saturated clocks
                // and OOM cannot certify that condition.
                const unchanged = !owner.oom and
                    type_epoch != std.math.maxInt(u64) and effect_epoch != std.math.maxInt(u64) and physical_epoch != std.math.maxInt(u64) and
                    owner.store.mutation_epoch == type_epoch and owner.store.effects.mutation_epoch == effect_epoch and owner.store.effects.physical_epoch == physical_epoch and
                    std.meta.eql(point.?, owner.store.mark());
                if (!unchanged) owner.rollback(point.?);
            }
        };

        inline for (.{ "ty", "other", "result" }) |field| {
            const left = @field(wanted, field);
            const right = @field(given, field);
            if (left == 0 or right == 0) {
                if (left != right) return false;
            } else proof.validate(left, right) catch return false;
        }
        if (wanted.signature != 0 and given.signature != 0) {
            const left = proof.left.node(wanted.signature);
            const right = proof.right.node(given.signature);
            if (left.tag == .function and left.a == T.unit and left.b == T.unit and right.tag == .function) {
                proof.rows(left.c, right.c) catch return false;
            } else {
                proof.foreign_views = covariant_signature;
                proof.validate(wanted.signature, given.signature) catch return false;
            }
        }
        accepted = true;
        return true;
    }
    /// A negative metadata search grants no predicate authority. Follow every
    /// forwarded callee summary before rejecting a candidate, so unrelated
    /// factory helpers do not require importing their entire type graph.
    /// Positive candidates still pass the ordinary body/type/row proof below.
    fn reachableHeader(self: *Self, initial: *const core.Module, binding: core.BindingId, wanted: core.Obligation, depth: usize) Error!bool {
        const solver = self.scopes.solver orelse return true;
        if (self.context.source_proofs) |cache| {
            if (cache.owns(initial)) return cache.possibleHeader(initial, binding, wanted, depth, self.scopes.remaining) catch |err| return solver.readerError(err);
        }
        return reachableHeaderMetadata(solver.store.allocator, self.units(), self.origin orelse self.module, initial, binding, wanted, depth, self.scopes.remaining) catch |err| return solver.readerError(err);
    }
    fn sharedGoal(self: *Self, wanted: ?core.Obligation, given: core.Obligation, depth: usize) Error!bool {
        try self.step(depth);
        const solver = self.scopes.solver orelse return false;
        try require(given.kind == .callee_use and given.other == 0 and given.result == 0 and given.signature == 0 and given.name == 0 and given.operator == .none);
        var owner = try self.target(.{ .unit = given.identity.unit, .binding = given.identity.decl });
        var binding = given.identity.decl;
        try require(binding != 0 and binding < owner.bindings.len);
        var declaration = owner.binding(binding);
        // An imported source summary names a local external proxy. Its target
        // and public argument positions identify the actual producer; only that
        // producer's scheme and independently checked body supply requirements.
        // This does not widen portable package admission.
        var forwards: usize = 0;
        while (declaration.kind == .external) {
            try self.step(depth + forwards);
            try require(self.admission.source_bodies);
            var target_ = declaration.target;
            if (target_.unit == 0) target_.unit = owner.unit;
            const next = try self.target(target_);
            try require(target_.binding != 0 and target_.binding < next.bindings.len);
            const imported = next.binding(target_.binding);
            try require(declaration.public_variables.len == imported.public_variables.len and declaration.public_rows.len == imported.public_rows.len);
            owner = next;
            binding = target_.binding;
            declaration = imported;
            forwards += 1;
        }
        try require(declaration.kind == .global and owner.body(binding) != null);
        if (wanted) |target_goal| {
            if (!try self.reachableHeader(owner, binding, target_goal, depth + 1)) return false;
        }
        if (self.admission.source_bodies) try sourceBody(owner, binding, self.context, self.admission);
        const product = self.module.types.node(given.ty);
        try require(product.tag == .product and product.b == declaration.public_variables.len + declaration.public_rows.len);
        const parts = solver.store.allocator.dupe(T.Id, self.module.types.list(.{ .start = product.a, .len = product.b })) catch {
            solver.oom = true;
            return error.InvalidArtifact;
        };
        defer solver.store.allocator.free(parts);
        const point = solver.store.mark();
        var accepted = false;
        defer if (!accepted) solver.rollback(point);
        var graph: @import("frozen_types.zig").Graph = undefined;
        var copy = solver.importer(owner, &graph, declaration.scheme) catch |err| return solver.readerError(err);
        defer copy.deinit();
        for (owner.types.list(declaration.public_variables), parts[0..declaration.public_variables.len]) |formal, actual| {
            try require(std.mem.findScalar(T.Id, owner.types.list(declaration.scheme.variables), formal) != null);
            const fresh = copy.mapping.get(formal) orelse return error.InvalidArtifact;
            solver.unify(fresh, actual) catch |err| return solver.readerError(err);
        }
        for (owner.types.list(declaration.public_rows), parts[declaration.public_variables.len..]) |formal, actual| {
            try require(std.mem.findScalar(T.Id, owner.types.list(declaration.scheme.row_variables), formal) != null);
            const carrier = self.module.types.node(actual);
            try require(carrier.tag == .function and carrier.a == T.unit and carrier.b == T.unit);
            copy.row_variables.put(copy.allocator, formal, carrier.c) catch {
                solver.oom = true;
                return error.InvalidArtifact;
            };
        }
        if (wanted) |target_goal| {
            for (owner.obligations[declaration.scheme.obligations.start..][0..declaration.scheme.obligations.len]) |source_goal| {
                try self.step(depth);
                // These immutable headers are the first exact checks in
                // goalMatches. Unrelated fields need neither instantiation
                // nor private receiver grounding. A nested callee remains a
                // candidate because its checked prerequisites may supply the
                // requested predicate.
                if (source_goal.kind != .callee_use and
                    (source_goal.kind != target_goal.kind or source_goal.name != target_goal.name or
                        source_goal.operator != target_goal.operator or !std.meta.eql(source_goal.identity, target_goal.identity))) continue;
                var goal = source_goal;
                inline for (.{ "ty", "other", "result", "signature" }) |field| @field(goal, field) = solver.copy(&copy, @field(source_goal, field)) catch |err| return solver.readerError(err);
                if (goal.kind == .callee_use) {
                    if (!try self.sharedGoal(target_goal, goal, depth + 1)) continue;
                } else {
                    if ((goal.kind == .field or goal.kind == .writable_field) and
                        !try self.groundSharedFieldOwner(solver, owner, declaration.scheme, &copy, goal.ty, depth + 1)) continue;
                    var proof: contracts.Principal = .{ .left = self.scopes.types, .right = self.scopes.types, .remaining = self.scopes.remaining, .views = self.scopes };
                    if (!try self.goalMatches(&proof, goal, target_goal, true)) {
                        try require(!solver.oom);
                        continue;
                    }
                    if (target_goal.kind != .task_receive and target_goal.signature != 0) try self.goalRows(target_goal.signature, self.goalArity(target_goal.kind, target_goal.signature), depth + 1);
                }
                accepted = true;
                return true;
            }
            return false;
        }
        try self.solverGoals(solver, owner, declaration.scheme, &copy, depth + 1);
        accepted = true;
        return true;
    }
    /// A callee summary may quantify variables used only by prerequisites.
    /// Its public argument pack does not identify those variables. In
    /// particular, access.brushes -> pool and pool.at -> element must remain
    /// correlated: the fresh pool cannot be chosen by matching a requested
    /// field from an unrelated receiver. Establish accessor dependencies from
    /// independently available fields before exporting such a field fact.
    fn groundSharedFieldOwner(self: *Self, solver: *Equations.Solver, producer: *const core.Module, source_scheme: T.Scheme, copy: *@import("check_scheme_import.zig").Copier, receiver: T.Id, depth: usize) Error!bool {
        if (solver.store.node(solver.store.head(receiver, 0)).tag != .variable) return true;
        const source_goals = producer.obligations[source_scheme.obligations.start..][0..source_scheme.obligations.len];
        const completed = solver.store.allocator.alloc(bool, source_goals.len) catch {
            solver.oom = true;
            return error.InvalidArtifact;
        };
        defer solver.store.allocator.free(completed);
        @memset(completed, false);
        var progress = true;
        while (progress) {
            try self.step(depth);
            progress = false;
            for (source_goals, completed) |source_goal, *done| {
                if (done.* or (source_goal.kind != .field and source_goal.kind != .writable_field)) continue;
                var goal = source_goal;
                inline for (.{ "ty", "other", "result", "signature" }) |field| @field(goal, field) = solver.copy(copy, @field(source_goal, field)) catch |err| return solver.readerError(err);
                goal.ty = solver.resolve(goal.ty) catch |err| return solver.readerError(err);
                if (solver.store.node(goal.ty).tag == .variable) continue;
                const point = solver.store.mark();
                if (!try self.prerequisiteGoalMode(goal, depth + 1, false)) {
                    solver.rollback(point);
                    try require(!solver.oom);
                    continue;
                }
                done.* = true;
                progress = true;
                if (solver.store.node(solver.store.head(receiver, 0)).tag != .variable) return true;
            }
        }
        return false;
    }
    fn goalGiven(self: *Self, wanted: core.Obligation, depth: usize) Error!bool {
        return self.goalGivenMode(wanted, depth, true);
    }
    fn goalGivenMode(self: *Self, wanted: core.Obligation, depth: usize, shared: bool) Error!bool {
        try self.step(depth);
        for (self.scopes.schemes[0..self.scopes.scheme_count]) |principal_value| {
            for (try self.scopes.schemeGoals(principal_value)) |given| {
                if (given.kind == .callee_use and wanted.kind != .callee_use and self.scopes.solver != null) {
                    if (!shared) continue;
                    if (try self.sharedGoal(wanted, given, depth + 1)) return true;
                    continue;
                }
                var proof: contracts.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes };
                if (!try self.goalMatches(&proof, given, wanted, true)) continue;
                if (given.kind != .task_receive and given.signature != 0) try self.goalRows(given.signature, self.goalArity(given.kind, given.signature), depth + 1);
                return true;
            }
        }
        for (self.scopes.formals[0..self.scopes.formal_count]) |owner| {
            for (self.module.types.quantifierGoals(owner)) |given| {
                var proof: contracts.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes };
                if (!try self.goalMatches(&proof, given, wanted, true)) continue;
                if (given.kind != .task_receive and given.signature != 0) try self.goalRows(given.signature, self.goalArity(given.kind, given.signature), depth + 1);
                return true;
            }
        }
        for (self.scopes.openings[0..self.scopes.opening_count]) |opening| {
            const owner = self.module.types.node(opening.quantifier);
            for (self.module.types.quantifierGoals(opening.quantifier)) |given| {
                var proof: contracts.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes, .instance = .{ .start = owner.b, .len = owner.c } };
                @memcpy(proof.witnesses[0..opening.binders.len], self.module.types.list(opening.binders));
                if (!try self.goalMatches(&proof, given, wanted, true)) continue;
                if (given.kind != .task_receive and given.signature != 0) try self.goalRows(try self.mappedRoot(&proof, given.signature, depth + 1), self.goalArity(given.kind, given.signature), depth + 1);
                return true;
            }
        }
        return false;
    }
    fn mappedRoot(self: *Self, proof: *contracts.Principal, root: T.Id, depth: usize) Error!T.Id {
        if (root == 0) return 0;
        try self.step(depth);
        for (proof.left.list(proof.instance), proof.witnesses[0..proof.instance.len]) |formal, witness| {
            if (root == formal and witness != 0) return witness;
        }
        switch (proof.left.node(root).tag) {
            .unit => return T.unit,
            .boolean => return T.boolean,
            .u32 => return T.u32_type,
            .f32 => return T.f32_type,
            .never => return T.never,
            else => {},
        }
        for (1..self.module.types.nodes.len) |candidate| {
            try self.step(depth);
            var comparison = proof.*;
            comparison.foreign_views = false;
            comparison.validate(root, @intCast(candidate)) catch continue;
            proof.witnesses = comparison.witnesses;
            proof.row_witnesses = comparison.row_witnesses;
            proof.scheme_row_witnesses = comparison.scheme_row_witnesses;
            return @intCast(candidate);
        }
        return error.InvalidArtifact;
    }
    /// The caller can retain one checked callee dictionary instead of its
    /// expanded prerequisites. Its hidden witnesses stay correlated when the
    /// exact declaration and every public type/effect argument agree.
    fn givenInvocation(self: *Self, producer: *const core.Module, binding: core.BindingId, mapping: *contracts.Principal, depth: usize) Error!bool {
        const declaration = producer.binding(binding);
        for (self.scopes.schemes[0..self.scopes.scheme_count]) |caller_scheme| {
            for (try self.scopes.schemeGoals(caller_scheme)) |given| {
                if (given.kind != .callee_use) continue;
                try require(given.other == 0 and given.result == 0 and given.signature == 0 and given.name == 0 and given.operator == .none);
                var reference: core.BindingRef = .{ .unit = given.identity.unit, .binding = given.identity.decl };
                var steps: usize = 0;
                while (true) {
                    try self.step(depth + steps);
                    const owner = try self.target(reference);
                    try require(reference.binding != 0 and reference.binding < owner.bindings.len);
                    const source = owner.binding(reference.binding);
                    if (source.kind != .external) {
                        reference.unit = owner.unit;
                        break;
                    }
                    reference = source.target;
                    if (reference.unit == 0) reference.unit = owner.unit;
                    steps += 1;
                }
                if (reference.unit != producer.unit or reference.binding != binding) continue;
                _ = try self.canonicalCallee(given.identity, &self.module.types, given.ty);
                const pack = self.module.types.node(given.ty);
                try require(pack.tag == .product and pack.b == declaration.public_variables.len + declaration.public_rows.len);
                var proof = mapping.*;
                proof.publicArguments(declaration.public_variables, declaration.public_rows, self.module.types.list(.{ .start = pack.a, .len = pack.b })) catch continue;
                return true;
            }
        }
        return false;
    }
    fn instantiatedGoals(self: *Self, producer: *const core.Module, binding: core.BindingId, principal_value: T.Scheme, mapping: *contracts.Principal, depth: usize) Error!void {
        if (principal_value.obligations.len == 0) return;
        try self.step(depth + self.goal_depth);
        self.goal_depth += 1;
        defer self.goal_depth -= 1;
        if (self.admission.source_bodies and try self.givenInvocation(producer, binding, mapping, depth + 1)) return;
        if (self.admission.workspace) |workspace| {
            var direct = mapping.*;
            var found_all = true;
            for (producer.obligations[principal_value.obligations.start..][0..principal_value.obligations.len]) |goal| {
                var found = false;
                for (self.scopes.schemes[0..self.scopes.scheme_count]) |owner| {
                    for (try self.scopes.schemeGoals(owner)) |given| {
                        var proof = direct;
                        if (!try self.goalMatches(&proof, goal, given, false)) continue;
                        direct = proof;
                        found = true;
                        break;
                    }
                    if (found) break;
                }
                if (!found) for (self.scopes.formals[0..self.scopes.formal_count]) |owner| {
                    for (self.module.types.quantifierGoals(owner)) |given| {
                        var proof = direct;
                        if (!try self.goalMatches(&proof, goal, given, false)) continue;
                        direct = proof;
                        found = true;
                        break;
                    }
                    if (found) break;
                };
                if (!found) {
                    found_all = false;
                    break;
                }
            }
            if (found_all) {
                mapping.* = direct;
                return;
            }
            return self.solveInstantiated(workspace, producer, principal_value, mapping, depth + 1);
        }
        for (producer.obligations[principal_value.obligations.start..][0..principal_value.obligations.len]) |goal| {
            var found = false;
            for (self.scopes.schemes[0..self.scopes.scheme_count]) |frame| {
                for (try self.scopes.schemeGoals(frame)) |given| {
                    var proof = mapping.*;
                    if (!try self.goalMatches(&proof, goal, given, false)) continue;
                    found = true;
                    break;
                }
                if (found) break;
            }
            if (!found) for (self.scopes.formals[0..self.scopes.formal_count]) |owner| {
                for (self.module.types.quantifierGoals(owner)) |given| {
                    var proof = mapping.*;
                    if (!try self.goalMatches(&proof, goal, given, false)) continue;
                    found = true;
                    break;
                }
                if (found) break;
            };
            if (found) continue;
            var actual: core.Obligation = .{ .ty = 0, .kind = goal.kind, .span = .{ .start = 0, .end = 0 }, .name = goal.name, .operator = goal.operator, .identity = goal.identity };
            inline for (.{ "ty", "other", "result", "signature" }) |field| @field(actual, field) = try self.mappedRoot(mapping, @field(goal, field), depth + 1);
            try require(try self.prerequisiteGoal(actual, depth + 1));
        }
    }
    fn identity(self: *Self, root: T.Id) ?T.NominalIdentity {
        const node = self.module.types.node(root);
        return switch (node.tag) {
            .nominal, .type_constructor => .{ .unit = node.a, .decl = node.b },
            .unit => .{ .unit = 0, .decl = T.unit },
            .u32 => .{ .unit = 0, .decl = T.u32_type },
            .f32 => .{ .unit = 0, .decl = T.f32_type },
            .boolean => .{ .unit = 0, .decl = T.boolean },
            .array => .{ .unit = 0, .decl = std.math.maxInt(u32) },
            .list => .{ .unit = 0, .decl = std.math.maxInt(u32) - 1 },
            .cursor => .{ .unit = 0, .decl = std.math.maxInt(u32) - 2 },
            else => null,
        };
    }
    fn closedGoal(self: *Self, goal: core.Obligation, depth: usize) Error!bool {
        try self.step(depth);
        switch (goal.kind) {
            .record_merge => {
                const left = self.module.types.node(goal.ty);
                const right = self.module.types.node(goal.other);
                const result = self.module.types.node(goal.result);
                if (left.tag != .record or right.tag != .record or result.tag != .record) return false;
                // Instantiation discharges the retained generic dictionary
                // against the same exact physical merge used by concrete Core.
                try self.recordMergeFields(left, right, result, depth + 1);
                return true;
            },
            .callee_use => return self.sharedGoal(null, goal, depth + 1),
            .collection => {
                const sequence = self.module.types.node(goal.ty);
                const element = if (sequence.tag == .list) sequence.a else @import("storage_types.zig").readableElement(&self.module.types, goal.ty) orelse return false;
                try self.strictSame(element, goal.result);
                return true;
            },
            .task_receive => {
                const tasks = @import("task_types.zig");
                if (!tasks.receivers(&self.module.types, goal.ty)) return false;
                try @import("task_core.zig").receiveType(self.module, goal.ty, goal.result, self.scopes.remaining);
                const signature = self.module.types.node(goal.signature);
                try require(signature.tag == .function);
                try self.strictSame(signature.a, goal.ty);
                try self.strictSame(signature.b, goal.result);
                const input = self.module.types.node(goal.ty);
                const members = if (input.tag == .product) self.module.types.list(.{ .start = input.a, .len = input.b }) else &.{goal.ty};
                for (members) |member| {
                    const wrapper = self.module.types.node(member);
                    const handle = self.module.types.node(wrapper.a);
                    const parts = self.module.types.nominalArguments(handle);
                    const arrow = self.module.types.node(parts[1]);
                    var proof: contracts.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes };
                    try proof.subsetRow(arrow.c, signature.c);
                }
                return true;
            },
            .arithmetic, .ordered, .integer, .equality => {
                const tag = self.module.types.node(goal.ty).tag;
                if (goal.kind == .integer) return tag == .u32;
                if (tag == .u32 or tag == .f32) return true;
                return goal.kind == .equality and tag == .boolean;
            },
            .field, .writable_field => {
                const owner = self.module.types.node(goal.ty);
                if (goal.kind == .field) if (self.identity(goal.ty)) |family| {
                    if (family.unit == 0 or @import("storage_types.zig").identity(family.unit, family.decl) != null) {
                        var member = goal;
                        member.kind = .receiver;
                        member.other = T.unit;
                        return self.closedGoal(member, depth + 1);
                    }
                };
                if (owner.tag == .record) {
                    for (0..owner.b) |ordinal| {
                        try self.step(depth);
                        const field = self.module.types.recordField(owner, ordinal);
                        if (field.name != goal.name) continue;
                        try self.strictSame(field.ty, goal.result);
                        return true;
                    }
                    return false;
                }
                if (owner.tag != .nominal) return false;
                if (goal.kind == .field) for (self.module.associated) |method| {
                    try self.step(depth);
                    if (method.identity.unit == owner.a and method.identity.decl == owner.b and method.member == goal.name) {
                        var member = goal;
                        member.kind = .receiver;
                        member.other = T.unit;
                        return self.closedGoal(member, depth + 1);
                    }
                };
                var count: usize = 0;
                for (self.module.constructors) |constructor| {
                    try self.step(depth);
                    const family = self.module.nominals[constructor.nominal];
                    if (family.identity.unit != owner.a or family.identity.decl != owner.b) continue;
                    try require(!family.is_opaque or family.identity.unit == self.module.unit);
                    const payload = self.module.types.node(constructor.payload);
                    const signature = self.module.types.node(constructor.scheme.root);
                    if (payload.tag != .record or signature.tag != .function) return false;
                    var found = false;
                    for (0..payload.b) |ordinal| {
                        try self.step(depth);
                        const field = self.module.types.recordField(payload, ordinal);
                        if (field.name != goal.name) continue;
                        if (self.scopes.solver) |solver| {
                            // Caller inference variables are rigid in this
                            // solver. Constructor formals have a separate,
                            // independently declared binder owner: instantiate
                            // only those through the immutable source scheme.
                            const source_owner = self.origin orelse self.module;
                            try require(source_owner.unit == self.module.unit);
                            var frozen: @import("frozen_types.zig").Graph = undefined;
                            var copy = solver.importer(source_owner, &frozen, constructor.scheme) catch |err| return solver.readerError(err);
                            defer copy.deinit();
                            const instantiated_output = solver.copy(&copy, signature.b) catch |err| return solver.readerError(err);
                            const value = solver.copy(&copy, field.ty) catch |err| return solver.readerError(err);
                            var proof: contracts.Principal = .{ .left = self.scopes.types, .right = self.scopes.types, .remaining = self.scopes.remaining, .views = self.scopes };
                            try proof.validate(instantiated_output, goal.ty);
                            try proof.validate(value, goal.result);
                        } else {
                            var proof: contracts.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes, .instance = constructor.scheme.variables, .instance_rows = constructor.scheme.row_variables };
                            try proof.validate(signature.b, goal.ty);
                            try proof.validate(field.ty, goal.result);
                        }
                        found = true;
                        break;
                    }
                    if (!found) return false;
                    count += 1;
                }
                return count != 0;
            },
            .effect_operation => {
                const arguments_ = self.module.types.node(goal.other);
                const actual = self.module.types.node(goal.ty);
                const signature = self.module.types.node(goal.signature);
                if (arguments_.tag != .product or actual.tag != .function or signature.tag != .function) return false;
                if (signature.a != T.unit or signature.b != T.unit) {
                    try self.strictSame(actual.a, signature.a);
                    try self.strictSame(actual.b, signature.b);
                }
                for (self.module.types.rowLabels(signature.c)) |label| {
                    try self.step(depth);
                    const operation = self.module.types.operation(label);
                    if (!std.meta.eql(operation.identity, goal.identity) or operation.arguments.len != arguments_.b) continue;
                    if (!try self.knownInstance(operation.instance)) continue;
                    var matches = true;
                    const solver = self.scopes.solver;
                    const point = if (solver) |owner| owner.store.mark() else null;
                    for (self.module.types.list(operation.arguments), self.module.types.list(.{ .start = arguments_.a, .len = arguments_.b })) |left, right| self.strictSame(left, right) catch {
                        matches = false;
                        break;
                    };
                    if (!matches) {
                        if (solver) |owner| owner.rollback(point.?);
                        continue;
                    }
                    var producer = self.origin orelse self.module;
                    if (operation.identity.unit != 0 and operation.identity.unit != producer.unit) {
                        var found: ?*const core.Module = null;
                        for (self.units()) |owner| if (owner.unit == operation.identity.unit) {
                            try require(found == null);
                            found = owner;
                        };
                        producer = found orelse return error.InvalidArtifact;
                        try Equations.bounds(self.admission.workspace, producer, .{ .units = self.units() });
                    }
                    try @import("staging_core.zig").declaredOperationIn(self.module, producer, operation, actual.a, actual.b, self.scopes.remaining);
                    return true;
                }
                return false;
            },
            .monad_factory => return @import("resolver_core.zig").factoryWorkspace(self.module, self.units(), goal, self.scopes.remaining, self.admission.workspace),
            .resolver_shape => return @import("resolver_core.zig").resultShapeWorkspace(self.module, self.units(), goal, self.scopes.remaining, self.admission.workspace),
            .resolver_dispatch => {
                const resolvers = @import("resolver_core.zig");
                const family = resolvers.resolverIdentity(self.module, goal.ty) orelse return false;
                const reference = try resolvers.methodWorkspace(self.module, self.units(), family, goal.name, self.scopes.remaining, self.admission.workspace);
                try self.principal(reference, goal.other);
                try self.goalRows(goal.other, null, depth + 1);
                return true;
            },
            .type_eq => {
                try self.strictSame(goal.ty, goal.result);
                return true;
            },
            .type_rep => return self.closedType(goal.ty, depth + 1),
            .effect_rep => {
                const carrier = self.module.types.node(goal.signature);
                return carrier.tag == .function and (self.scopes.isPure(carrier.c) or self.scopes.isForeign(carrier.c));
            },
            .dispatch, .result_dispatch, .receiver => {
                const subjects = [_]T.Id{ if (goal.kind == .result_dispatch) goal.result else goal.ty, goal.other };
                for (subjects, 0..) |subject, side| {
                    if (side != 0 and goal.kind != .dispatch) break;
                    const owner = self.identity(subject) orelse continue;
                    for (self.module.associated) |method| {
                        try self.step(depth);
                        if (!std.meta.eql(owner, method.identity)) continue;
                        if (goal.name != 0) {
                            if (method.member != goal.name) continue;
                        } else if (method.operator != goal.operator) continue;
                        if (goal.signature == 0) continue;
                        // The local imported binding is independently linked
                        // to its producer before its signature grants authority.
                        if (self.context.source_proofs) |cache| {
                            const bindings = cache.targetBindings(self.module, method.target, self.scopes.remaining) catch |err| {
                                if (err == error.OutOfMemory) if (self.admission.workspace) |workspace| {
                                    workspace.oom = true;
                                };
                                return error.InvalidArtifact;
                            };
                            for (bindings) |binding| {
                                try self.step(depth);
                                if (try self.associatedTarget(binding, goal, depth + 1)) return true;
                            }
                            continue;
                        }
                        for (self.module.bindings, 0..) |binding, ordinal| {
                            try self.step(depth);
                            if ((method.target.unit == 0 or method.target.unit == self.module.unit) and method.target.binding == ordinal) {
                                if (try self.associatedTarget(@intCast(ordinal), goal, depth + 1)) return true;
                            }
                            if (binding.kind == .external and std.meta.eql(binding.target, method.target)) {
                                if (try self.associatedTarget(@intCast(ordinal), goal, depth + 1)) return true;
                            }
                        }
                    }
                }
                return false;
            },
            .contract => {
                const inputs = self.module.types.node(goal.ty);
                if (inputs.tag != .product) return false;
                for (self.module.selected_proofs) |selected| {
                    try self.step(depth);
                    if (selected.kind != .implementation or selected.contract.unit != goal.identity.unit or selected.contract.decl != goal.identity.decl or selected.arguments.len != inputs.b) continue;
                    const solver = self.scopes.solver;
                    const point = if (solver) |owner| owner.store.mark() else null;
                    var matches = true;
                    for (self.module.types.list(.{ .start = inputs.a, .len = inputs.b }), self.module.types.list(selected.arguments)) |expected, actual| {
                        var proof: contracts.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes };
                        proof.validate(expected, actual) catch {
                            matches = false;
                            break;
                        };
                    }
                    if (matches) return true;
                    if (solver) |owner| owner.rollback(point.?);
                }
                return false;
            },
            else => return false,
        }
    }
    fn associatedTarget(self: *Self, binding: core.BindingId, goal: core.Obligation, depth: usize) Error!bool {
        const signature = goal.signature;
        try self.step(depth);
        const prior_failure = if (self.admission.source_failure) |failure| failure.* else null;
        const pure_rows = self.scopes.pure_rows;
        const closed_rows = self.scopes.closed_rows;
        const instance_variables = self.scopes.instance_variables;
        const instance_rows = self.scopes.instance_rows;
        const solver = self.scopes.solver;
        const point = if (solver) |owner| owner.store.mark() else null;
        var accepted = false;
        defer {
            if (!accepted) {
                if (self.admission.source_failure) |failure| failure.* = prior_failure;
                if (solver) |owner| owner.rollback(point.?);
                self.scopes.pure_rows = pure_rows;
                self.scopes.closed_rows = closed_rows;
                self.scopes.instance_variables = instance_variables;
                self.scopes.instance_rows = instance_rows;
            }
        }
        self.principal(.{ .binding = binding }, signature) catch {
            try require(self.scopes.remaining.* != 0);
            return false;
        };
        self.goalRows(signature, self.goalArity(goal.kind, signature), depth + 1) catch {
            try require(self.scopes.remaining.* != 0);
            return false;
        };
        accepted = true;
        return true;
    }
    fn closedType(self: *Self, root: T.Id, depth: usize) Error!bool {
        try self.step(depth);
        const node = self.module.types.node(root);
        switch (node.tag) {
            .unit, .boolean, .u32, .f32, .never => return true,
            .array, .list, .cursor => return self.closedType(node.a, depth + 1),
            .function => return (self.scopes.isPure(node.c) or self.scopes.isForeign(node.c)) and try self.closedType(node.a, depth + 1) and try self.closedType(node.b, depth + 1),
            .product => for (self.module.types.list(.{ .start = node.a, .len = node.b })) |child| {
                if (!try self.closedType(child, depth + 1)) return false;
            },
            .record => for (0..node.b) |ordinal| {
                if (!try self.closedType(self.module.types.recordField(node, ordinal).ty, depth + 1)) return false;
            },
            .nominal => for (self.module.types.nominalArguments(node)) |child| {
                if (!try self.closedType(child, depth + 1)) return false;
            },
            else => return false,
        }
        return true;
    }
    fn memberProjection(self: *Self, projection: core.Projection, depth: usize) Error!void {
        try require(projection.field != 0 and projection.variants.len == 0);
        const reference = try @import("resolver_core.zig").methodWorkspace(self.origin orelse self.module, self.units(), projection.nominal, projection.field, self.scopes.remaining, self.admission.workspace);
        const workspace = self.admission.workspace orelse return error.InvalidArtifact;
        var solver = Equations.Solver.init(workspace.allocator, self.module, self.scopes, self.scopes.remaining) catch |err| {
            if (err == error.OutOfMemory) workspace.oom = true;
            return error.InvalidArtifact;
        };
        defer solver.deinit();
        var temporary = self.module.*;
        solver.view = &temporary.types;
        solver.refresh();
        var scopes = self.scopes.*;
        scopes.types = &temporary.types;
        scopes.solver = &solver;
        var walker = self.*;
        walker.module = &temporary;
        walker.origin = self.origin orelse self.module;
        walker.scopes = &scopes;
        const owner = try walker.target(reference);
        // A receiver projection has an actual argument and result but no
        // selected arrow. Its use inherits the independently owned ambient;
        // the real member declaration must fit that row covariantly.
        const expected = solver.store.functionWithEffects(projection.source_type, projection.result_type, self.body_row) catch |err| {
            if (err == error.OutOfMemory) workspace.oom = true;
            return error.InvalidArtifact;
        };
        solver.refresh();
        _ = walker.solverInstance(&solver, owner, reference.binding, expected, &.{}) catch |err| {
            if (solver.oom) workspace.oom = true;
            return err;
        };
        try self.step(depth);
    }
    fn nominalProjection(self: *Self, projection: core.Projection, depth: usize) Error!void {
        try self.step(depth);
        const source = self.module.types.node(projection.source_type);
        try require(source.tag == .nominal and source.a == projection.nominal.unit and source.b == projection.nominal.decl);
        if (projection.variants.len == 0) return self.memberProjection(projection, depth + 1);
        var count: usize = 0;
        for (self.module.constructors) |constructor| {
            try self.step(depth);
            const family = self.module.nominals[constructor.nominal];
            if (!std.meta.eql(family.identity, projection.nominal)) continue;
            try require(!family.is_opaque or family.identity.unit == self.module.unit);
            const arrow = self.module.types.node(constructor.scheme.root);
            const payload = self.module.types.node(constructor.payload);
            try require(arrow.tag == .function and payload.tag == .record);
            var selected: ?u32 = null;
            for (self.module.projection_variants[projection.variants.start..][0..projection.variants.len]) |variant| {
                try self.step(depth);
                if (variant.tag != constructor.tag) continue;
                try require(selected == null);
                selected = variant.field;
            }
            const slot = selected orelse return error.InvalidArtifact;
            try require(slot < payload.b);
            const field = self.module.types.recordField(payload, slot);
            try require(field.name == projection.field);
            var proof: contracts.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes, .instance = constructor.scheme.variables, .instance_rows = constructor.scheme.row_variables };
            try proof.validate(arrow.b, projection.source_type);
            try proof.validate(field.ty, projection.result_type);
            count += 1;
        }
        try require(count != 0 and count == projection.variants.len);
    }
    fn output(self: *Self, expected: T.Id, body: core.Id) Error!void {
        if (self.module.types.node(self.module.typeOf(body)).tag == .never) return;
        try self.strictSame(expected, self.module.typeOf(body));
    }
    fn header(self: *Self, signature: T.Id, parameters: []const core.Parameter, body: core.Id, resolver_parameter: bool) Error!void {
        var cursor = signature;
        for (0..128) |_| {
            const wrapper = self.module.types.node(cursor);
            if (wrapper.tag != .usage and (wrapper.tag != .forall or parameters.len == 0)) break;
            cursor = wrapper.a;
        } else return error.InvalidArtifact;
        for (parameters) |parameter| {
            const arrow = self.module.types.node(cursor);
            try require(arrow.tag == .function);
            try self.scopes.validateRow(arrow.c, 0);
            try self.strictSame(arrow.a, parameter.ty);
            if (parameter.binding == 0) {
                try require(parameter.ty == T.unit);
            } else {
                const binding = self.module.binding(parameter.binding);
                try require(binding.kind == .parameter or (resolver_parameter and binding.kind == .local));
                try self.same(parameter.ty, binding.ty);
                try self.same(parameter.ty, binding.scheme.root);
                try self.scheme(binding.scheme);
            }
            cursor = arrow.b;
        }
        try self.output(cursor, body);
    }
    fn tokenMatches(self: *Self, label: T.Effects.Label, token_id: T.Id, depth: usize) Error!bool {
        try self.step(depth);
        var token = self.module.types.node(token_id);
        var instance: T.NominalIdentity = .{ .unit = 0, .decl = 0 };
        if (token.tag == .scoped) {
            instance = .{ .unit = token.b, .decl = token.c };
            token = self.module.types.node(token.a);
        }
        if (token.tag != .nominal) return false;
        const operation = self.module.types.operation(label);
        if (!std.meta.eql(operation.identity, T.NominalIdentity{ .unit = token.a, .decl = token.b }) or !std.meta.eql(operation.instance, instance)) return false;
        const arguments_ = self.module.types.nominalArguments(token);
        if (arguments_.len != operation.arguments.len) return false;
        for (arguments_, self.module.types.list(operation.arguments)) |left, right| self.strictSame(left, right) catch {
            try require(self.scopes.remaining.* != 0);
            return false;
        };
        return true;
    }
    fn operationGoal(self: *Self, operation: core.OperationValue, goal: anytype, span: core.Span, depth: usize) Error!bool {
        try self.step(depth);
        if (goal.kind != .effect_operation or !std.meta.eql(goal.identity, operation.identity)) return false;
        const arguments_ = self.module.types.node(goal.other);
        if (arguments_.tag != .product or arguments_.b != operation.arguments.len) return false;
        for (self.module.types.list(.{ .start = arguments_.a, .len = arguments_.b }), self.module.types.list(operation.arguments)) |left, right| self.strictSame(left, right) catch {
            try require(self.scopes.remaining.* != 0);
            return false;
        };
        // The current lexical predicate owns this unresolved equation.
        // Its signature and complete argument product must describe the
        // actual operation; an unrelated header cannot grant the use.
        return self.goalGiven(.{ .kind = .effect_operation, .ty = operation.signature, .other = goal.other, .signature = operation.signature, .identity = operation.identity, .span = span }, depth + 1);
    }
    fn operationGiven(self: *Self, source: core.Id, operation: core.OperationValue, depth: usize) Error!bool {
        for (self.scopes.schemes[0..self.scopes.scheme_count]) |scheme_| {
            for (try self.scopes.schemeGoals(scheme_)) |goal| if (try self.operationGoal(operation, goal, self.module.span(source), depth + 1)) return true;
        }
        for (self.scopes.formals[0..self.scopes.formal_count]) |owner| {
            for (self.module.types.quantifierGoals(owner)) |goal| if (try self.operationGoal(operation, goal, self.module.span(source), depth + 1)) return true;
        }
        return false;
    }
    fn excludedHandlers(self: *Self, row: T.Effects.Id, depth: usize) Error!std.bit_set.Static(256) {
        const labels = self.module.types.rowLabels(row);
        try require(labels.len <= 256);
        var excluded: std.bit_set.Static(256) = .empty;
        for (self.handled[0..self.handled_count]) |token| {
            for (labels, 0..) |label, ordinal| {
                try self.step(depth);
                if (excluded.isSet(ordinal)) continue;
                if (!try self.tokenMatches(label, token, depth + 1)) continue;
                excluded.set(ordinal);
                break;
            }
        }
        return excluded;
    }
    fn allowedRow(self: *Self, row: T.Effects.Id, subset: bool) Error!void {
        var proof: contracts.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes };
        const excluded = try self.excludedHandlers(row, 0);
        try proof.handledRow(row, self.body_row, excluded, subset);
    }
    fn operationToken(self: *Self, source: core.Id, token: T.Id, depth: usize) Error!void {
        try self.step(depth);
        const node = self.module.node(source);
        try require(node.tag == .operation_value);
        const operation = self.module.operationValue(source);
        var nominal = self.module.types.node(token);
        if (nominal.tag == .scoped) {
            try require(nominal.b == operation.instance.unit and nominal.c == operation.instance.decl);
            nominal = self.module.types.node(nominal.a);
        } else try require(operation.instance.unit == 0 and operation.instance.decl == 0);
        try require(nominal.tag == .nominal and nominal.a == operation.identity.unit and nominal.b == operation.identity.decl);
        const arguments_ = self.module.types.nominalArguments(nominal);
        try require(arguments_.len == operation.arguments.len);
        for (arguments_, self.module.types.list(operation.arguments)) |left, right| try self.strictSame(left, right);
    }
    fn arguments(self: *Self, signature: T.Id, values: []const core.Id, output_: T.Id, projection: ?contracts.PrincipalProjectionResolver) Error!void {
        var cursor = signature;
        for (0..128) |_| {
            const wrapper = self.module.types.node(cursor);
            if (wrapper.tag != .usage and wrapper.tag != .forall) break;
            cursor = wrapper.a;
        } else return error.InvalidArtifact;
        for (values) |value| {
            const arrow = self.module.types.node(cursor);
            try require(arrow.tag == .function);
            if (!self.scopes.isPure(arrow.c)) {
                try self.allowedRow(arrow.c, true);
            }
            var proof: contracts.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes, .projection_resolver = projection };
            try proof.validate(arrow.a, self.module.typeOf(value));
            cursor = arrow.b;
        }
        var result: contracts.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes, .foreign_views = true, .projection_resolver = projection };
        try result.validate(cursor, output_);
    }
    fn effectSignature(self: *Self, signature: T.Id, arity: usize) Error!T.Effects.Id {
        var cursor = signature;
        for (0..128) |_| {
            const wrapper = self.module.types.node(cursor);
            if (wrapper.tag != .usage and wrapper.tag != .forall) break;
            cursor = wrapper.a;
        } else return error.InvalidArtifact;
        var result_: T.Effects.Id = 0;
        for (0..arity) |_| {
            const arrow = self.module.types.node(cursor);
            try require(arrow.tag == .function);
            result_ = arrow.c;
            cursor = arrow.b;
        }
        return result_;
    }
    fn rowHasForeign(self: *Self, id: T.Effects.Id) bool {
        if (id >= self.module.types.effects.rows.len) return false;
        return std.mem.findScalar(T.Effects.Label, self.module.types.rowLabels(id), T.foreign_operation) != null;
    }
    fn scalarContract(self: *Self, operation: core.Op, inputs: []const T.Id, output_: T.Id) Error!void {
        if (inputs.len != 0 and self.module.types.node(inputs[0]).tag == .product) {
            return @import("simd_contracts.zig").validate(&self.module.types, operation, inputs, output_);
        }
        try self.step(0);
        const unary = switch (operation) {
            .neg, .abs, .ceil, .floor, .trunc, .sqrt, .convert_u32_f32, .convert_f32_u32 => true,
            else => false,
        };
        var arity: usize = 2;
        if (unary) arity = 1;
        try require(inputs.len == arity);
        const input = self.module.types.node(inputs[0]).tag;
        var machine: @import("../backend/wasm.zig").Scalar = .u32;
        switch (input) {
            .u32 => {},
            .f32 => machine = .f32,
            .boolean => {
                try require(operation == .equal or operation == .not_equal);
                machine = .bool;
            },
            else => return error.InvalidArtifact,
        }
        try require(@import("../backend/scalar_ops.zig").opcode(operation, machine) != null);
        if (inputs.len == 2) try self.same(inputs[0], inputs[1]);
        var expected = inputs[0];
        switch (operation) {
            .equal, .not_equal, .less, .less_equal, .greater, .greater_equal => expected = T.boolean,
            .convert_u32_f32 => {
                try require(input == .u32);
                expected = T.f32_type;
            },
            .convert_f32_u32 => {
                try require(input == .f32);
                expected = T.u32_type;
            },
            else => {},
        }
        try self.same(expected, output_);
    }
    fn collectionSequence(self: *Self, sequence: T.Id, element: T.Id) Error!void {
        for (self.scopes.schemes[0..self.scopes.scheme_count]) |scheme_| {
            for (try self.scopes.schemeGoals(scheme_)) |goal| {
                try self.step(0);
                if (goal.kind != .collection) continue;
                try require(goal.result != 0 and goal.other == 0 and goal.signature == 0);
                const solver = self.scopes.solver;
                const point = if (solver) |owner| owner.store.mark() else null;
                self.strictSame(goal.ty, sequence) catch {
                    if (solver) |owner| owner.rollback(point.?);
                    continue;
                };
                if (element != 0) self.strictSame(goal.result, element) catch {
                    if (solver) |owner| owner.rollback(point.?);
                    continue;
                };
                return;
            }
        }
        return error.InvalidArtifact;
    }
    fn collectionContract(self: *Self, operation: core.ArrayOp, inputs: []const T.Id, output_: T.Id) Error!void {
        try self.step(0);
        const Proof = struct {
            walker: *Self,
            pub fn same(proof: @This(), first: T.Id, second: T.Id) Error!void {
                try proof.walker.strictSame(first, second);
            }
            pub fn callback(proof: @This(), row: T.Effects.Id) Error!void {
                try require(proof.walker.scopes.isPure(row) or (proof.walker.foreign_allowed and proof.walker.scopes.isForeign(row)));
            }
            pub fn collection(proof: @This(), sequence: T.Id, element: T.Id) Error!void {
                try proof.walker.collectionSequence(sequence, element);
            }
        };
        try @import("collection_contracts.zig").validate(&self.module.types, operation, inputs, output_, Proof{ .walker = self });
    }
    fn openType(self: *Self, ty: T.Id, depth: usize) Error!bool {
        return self.scopeType(ty, depth, false);
    }
    fn unsealedType(self: *Self, ty: T.Id, depth: usize) Error!bool {
        return self.scopeType(ty, depth, true);
    }
    fn scopeType(self: *Self, ty: T.Id, depth: usize, sealing: bool) Error!bool {
        try self.step(depth);
        const node = self.module.types.node(ty);
        switch (node.tag) {
            .bound => return node.c != 0 and (!sealing or !self.sealed.isSet(ty)),
            .function => return try self.scopeType(node.a, depth + 1, sealing) or try self.scopeType(node.b, depth + 1, sealing),
            .usage => return self.scopeType(node.a, depth + 1, sealing),
            .array, .list => return self.scopeType(node.a, depth + 1, sealing),
            .product => for (self.module.types.list(.{ .start = node.a, .len = node.b })) |child| {
                if (try self.scopeType(child, depth + 1, sealing)) return true;
            },
            .record => for (0..node.b) |index| {
                if (try self.scopeType(self.module.types.recordField(node, index).ty, depth + 1, sealing)) return true;
            },
            .nominal, .projection => for (self.module.types.nominalArguments(node)) |child| {
                if (try self.scopeType(child, depth + 1, sealing)) return true;
            },
            else => {},
        }
        return false;
    }
    fn sealWitness(self: *Self, ty: T.Id, depth: usize) Error!void {
        try self.step(depth);
        const node = self.module.types.node(ty);
        switch (node.tag) {
            .bound => {
                try require((node.c != 0 or self.scopes.ownsFormal(ty)) and ty < self.sealed.capacity());
                self.sealed.set(ty);
            },
            .function => {
                try self.sealWitness(node.a, depth + 1);
                try self.sealWitness(node.b, depth + 1);
            },
            .array, .list => try self.sealWitness(node.a, depth + 1),
            .usage => try self.sealWitness(node.a, depth + 1),
            .product => for (self.module.types.list(.{ .start = node.a, .len = node.b })) |child| try self.sealWitness(child, depth + 1),
            .record => for (0..node.b) |index| try self.sealWitness(self.module.types.recordField(node, index).ty, depth + 1),
            .projection => {
                try require(ty < self.sealed.capacity());
                self.sealed.set(ty);
                for (self.module.types.nominalArguments(node)) |child| try self.sealWitness(child, depth + 1);
            },
            .nominal => for (self.module.types.nominalArguments(node)) |child| try self.sealWitness(child, depth + 1),
            .unit, .boolean, .u32, .f32, .never => {},
            else => return error.InvalidArtifact,
        }
    }
    fn pattern(self: *Self, id: core.PatternId, expected: T.Id, definitions: ?*Definitions, depth: usize) Error!void {
        try self.step(depth);
        const p = self.module.pattern(id);
        try self.same(p.ty, expected);
        switch (p.tag) {
            .wildcard => try require(p.a == 0 and p.b == 0 and p.c == 0),
            .bind => {
                const binding = self.module.binding(p.a);
                try require(binding.kind == .local and binding.initializer == 0 and p.b == 0 and p.c == 0);
                try self.same(binding.ty, expected);
                if (binding.scheme.root != 0) try self.same(binding.scheme.root, expected);
                try self.scheme(binding.scheme);
                if (definitions) |locals_| {
                    try require(!locals_.isSet(p.a));
                    try locals_.set(p.a);
                }
            },
            .product => {
                const shape = self.module.types.node(expected);
                const children = self.module.patternChildren(id);
                try require((shape.tag == .product or shape.tag == .record) and children.len == shape.b and p.c == 0);
                for (children, 0..) |child, index| {
                    var part: T.Id = 0;
                    if (shape.tag == .product) part = self.module.types.list(.{ .start = shape.a, .len = shape.b })[index] else part = self.module.types.recordField(shape, index).ty;
                    try self.pattern(child, part, definitions, depth + 1);
                }
            },
            .constructor => {
                try require(p.c == 0);
                const constructor = self.module.constructor(p.a);
                const family = self.module.nominals[constructor.nominal];
                try require(!family.is_opaque or family.identity.unit == self.module.unit);
                var proof: contracts.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes, .instance = constructor.scheme.variables, .instance_rows = constructor.scheme.row_variables };
                const signature = self.module.types.node(constructor.scheme.root);
                if (signature.tag == .function) {
                    try proof.validate(signature.b, expected);
                    try require(p.b != 0);
                    try proof.validate(constructor.payload, self.module.pattern(p.b).ty);
                    try self.pattern(p.b, self.module.pattern(p.b).ty, definitions, depth + 1);
                } else {
                    try require(p.b == 0 and constructor.payload == 0);
                    try proof.validate(constructor.scheme.root, expected);
                }
            },
            .record_payload => {
                const shape = self.module.types.node(expected);
                try require(shape.tag == .record and p.a == shape.b and p.b != 0 and p.c == 0);
                if (shape.b == 1) {
                    try self.pattern(p.b, self.module.types.recordField(shape, 0).ty, definitions, depth + 1);
                } else {
                    const child = self.module.pattern(p.b);
                    const input = self.module.types.node(child.ty);
                    try require(input.tag == .product and input.b == shape.b);
                    for (self.module.types.list(.{ .start = input.a, .len = input.b }), 0..) |part, index| try self.same(part, self.module.types.recordField(shape, index).ty);
                    try self.pattern(p.b, child.ty, definitions, depth + 1);
                }
            },
            .constant => try require(p.b == 0 and p.c == 0 and (self.module.types.node(expected).tag == .u32 or self.module.types.node(expected).tag == .boolean or self.module.types.node(expected).tag == .f32)),
            .value => {
                try require(p.b == 0 and p.c == 0);
                try self.expression(p.a, depth + 1);
                try self.same(self.module.typeOf(p.a), expected);
            },
            .invalid => return error.InvalidArtifact,
        }
    }
    fn binds(self: *Self, id: core.PatternId, binding: core.BindingId, depth: usize) Error!bool {
        try self.step(depth);
        const p = self.module.pattern(id);
        if (p.tag == .bind) return p.a == binding;
        if (p.tag == .constructor or p.tag == .record_payload) return p.b != 0 and try self.binds(p.b, binding, depth + 1);
        if (p.tag == .product) for (self.module.patternChildren(id)) |child| {
            if (try self.binds(child, binding, depth + 1)) return true;
        };
        return false;
    }
    fn genericOperation(self: *Self, reference: core.BindingRef) Error!bool {
        const owner = try self.target(reference);
        const declaration = owner.binding(reference.binding);
        if (owner.types.node(declaration.ty).tag == .forall and (declaration.kind == .parameter or declaration.kind == .local)) return true;
        if (owner.body(reference.binding) == null) return false;
        return owner.types.node(declaration.ty).tag == .forall or declaration.scheme.variables.len != 0 or declaration.scheme.row_variables.len != 0;
    }
    fn openingOperation(self: *Self, source: core.Id, depth: usize) Error!bool {
        try self.step(depth);
        const node = self.module.node(source);
        if (node.tag == .project or node.tag == .apply) return self.openingOperation(node.a, depth + 1);
        if (node.tag != .reference) return false;
        const reference = self.module.reference(source);
        if (try self.genericOperation(reference)) return true;
        if (reference.unit != 0 and reference.unit != self.module.unit) return false;
        for (self.module.dictionary_uses) |use| {
            try self.step(depth);
            if (use.node != source) continue;
            try @import("dictionary_contracts.zig").use(self.module, source, self.scopes);
            return true;
        }
        for (self.scopes.openings[0..self.scopes.opening_count]) |opening| if (opening.binding == reference.binding) return true;
        const binding = self.module.binding(reference.binding);
        if (binding.initializer != 0) return self.openingOperation(binding.initializer, depth + 1);
        for (self.module.nodes) |definition| {
            try self.step(depth);
            if (definition.tag == .bind and definition.a == reference.binding) return self.openingOperation(definition.b, depth + 1);
            if (definition.tag == .pattern_bind and try self.binds(definition.a, reference.binding, depth + 1)) return self.openingOperation(definition.b, depth + 1);
        }
        return false;
    }
    fn retainedCall(self: *Self, source: core.Id, depth: usize) Error!?bool {
        try self.step(depth);
        const flow = @import("capability_flow.zig");
        const call = flow.coreCall(self.module, source) orelse return null;
        const owner = try self.target(call.target);
        const resolved = flow.coreCallBody(owner, call) orelse return null;
        const retained = flow.retainedCore(owner, resolved.body, resolved.bindings[0..resolved.len], self.scopes.remaining) orelse return null;
        for (call.arguments[0..call.len], 0..) |argument, ordinal| {
            if (retained & (@as(u16, 1) << @intCast(ordinal)) == 0) continue;
            if (try self.capturesOpening(argument, depth + 1)) return true;
        }
        return false;
    }
    fn lookupDefinition(self: *Self, binding: core.BindingId, depth: usize) Error!core.Id {
        try self.step(depth);
        if (self.admission.source_bodies) return self.sourceDefinition(binding, depth);
        try require(binding < self.definitions.len);
        if (!self.definitions_indexed) {
            for (self.module.nodes) |node| {
                try self.step(depth);
                if (node.tag != .bind) continue;
                try require(node.a < self.definitions.len and self.module.binding(node.a).kind == .local);
                try require(self.definitions[node.a] == 0 or self.definitions[node.a] == node.b);
                self.definitions[node.a] = node.b;
            }
            self.definitions_indexed = true;
        }
        return self.definitions[binding];
    }
    fn sourceDefinition(self: *Self, binding: core.BindingId, depth: usize) Error!core.Id {
        try require(binding < self.module.bindings.len);
        for (self.admission.source_definitions.items) |index| if (index.module == self.module) return index.values[binding];
        const workspace = self.admission.workspace orelse return error.InvalidArtifact;
        // The source context already owns validated bounds. Charge its actual
        // extent before allocating; publish only a completely checked index.
        if (self.module.bindings.len > self.scopes.remaining.*) {
            self.scopes.remaining.* = 0;
            return error.InvalidArtifact;
        }
        self.scopes.remaining.* -= self.module.bindings.len;
        const values = workspace.allocator.alloc(core.Id, self.module.bindings.len) catch {
            workspace.oom = true;
            return error.InvalidArtifact;
        };
        errdefer workspace.allocator.free(values);
        @memset(values, 0);
        for (self.module.nodes) |node| {
            try self.step(depth);
            if (node.tag != .bind) continue;
            try require(node.a < values.len and self.module.binding(node.a).kind == .local);
            try require(values[node.a] == 0 or values[node.a] == node.b);
            values[node.a] = node.b;
        }
        self.admission.source_definitions.append(workspace.allocator, .{ .module = self.module, .values = values }) catch {
            workspace.oom = true;
            return error.InvalidArtifact;
        };
        return values[binding];
    }
    fn capturesOpening(self: *Self, source: core.Id, depth: usize) Error!bool {
        try self.step(depth);
        const node = self.module.node(source);
        if (try self.unsealedType(node.ty, depth + 1)) return true;
        switch (self.module.types.node(node.ty).tag) {
            .unit, .boolean, .u32, .f32, .never => return false,
            else => {},
        }
        switch (node.tag) {
            .package_pack => return false,
            .reference => {
                const reference = self.module.reference(source);
                for (self.module.dictionary_uses) |use| {
                    try self.step(depth);
                    if (use.node != source) continue;
                    try @import("dictionary_contracts.zig").use(self.module, source, self.scopes);
                    for (self.scopes.openings[0..self.scopes.opening_count]) |opening| {
                        if (opening.binding != use.opening) continue;
                        const goals = self.module.types.quantifierGoals(opening.quantifier);
                        try require(use.quantifier == opening.quantifier and use.goal < goals.len);
                        const goal = goals[use.goal];
                        inline for (.{ "ty", "other", "result", "signature" }) |field| {
                            const endpoint = @field(goal, field);
                            if (endpoint != 0 and try self.scopes.goalFootprint(endpoint, opening.quantifier, opening.binders, &self.sealed, depth + 1)) return true;
                        }
                    }
                }
                if (reference.unit != 0 and reference.unit != self.module.unit) return false;
                const binding = self.module.binding(reference.binding);
                for (self.scopes.openings[0..self.scopes.opening_count]) |opening| if (opening.binding == reference.binding) return self.unsealedType(binding.ty, depth + 1);
                if (binding.initializer != 0) return self.capturesOpening(binding.initializer, depth + 1);
                if (binding.kind != .local) return false;
                const initializer = try self.lookupDefinition(reference.binding, depth + 1);
                if (initializer != 0) return self.capturesOpening(initializer, depth + 1);
            },
            .closure, .suspend_ => {
                const closure = self.module.closures[node.a];
                for (self.module.extra[closure.captures.start..][0..closure.captures.len]) |binding| {
                    const declaration = self.module.binding(binding);
                    if (try self.unsealedType(declaration.ty, depth + 1)) return true;
                    if (declaration.initializer != 0 and try self.capturesOpening(declaration.initializer, depth + 1)) return true;
                    if (declaration.kind != .local) continue;
                    const initializer = try self.lookupDefinition(binding, depth + 1);
                    if (initializer != 0 and try self.capturesOpening(initializer, depth + 1)) return true;
                }
                // Listed captures are producer claims; inspect references.
                return self.capturedReferences(closure.body, depth + 1);
            },
            .staging, .proof_guard => {
                if (try self.capturedReferences(node.a, depth + 1)) return true;
                if (node.b != 0) return self.capturedReferences(node.b, depth + 1);
            },
            .product, .record, .array => for (self.module.children(source)) |child| {
                if (try self.capturesOpening(child, depth + 1)) return true;
            },
            .block => return self.returnCaptures(source, source, depth + 1),
            .suite => return false,
            .handle => {
                if (try self.capturesOpening(node.a, depth + 1)) return true;
                const body = self.module.node(node.b);
                if (body.tag == .suite) return self.returnCaptures(node.b, source, depth + 1);
                return self.capturesOpening(node.b, depth + 1);
            },
            .effect_provider => return try self.capturesOpening(node.a, depth + 1) or try self.capturesOpening(node.b, depth + 1),
            .state_provider => return try self.capturesOpening(node.a, depth + 1) or try self.capturesOpening(node.b, depth + 1) or try self.capturesOpening(node.c, depth + 1),
            .construct => return node.b != 0 and try self.capturesOpening(node.b, depth + 1),
            .project, .return_ => return self.capturesOpening(node.a, depth + 1),
            .bind => return self.capturesOpening(node.b, depth + 1),
            .if_value => return try self.capturesOpening(node.b, depth + 1) or try self.capturesOpening(node.c, depth + 1),
            .apply => {
                if (try self.retainedCall(source, depth + 1)) |captured| return captured;
                return try self.capturesOpening(node.a, depth + 1) or try self.capturesOpening(node.b, depth + 1);
            },
            .task => {
                for (self.module.children(source)) |operand| if (try self.capturesOpening(operand, depth + 1)) return true;
            },
            .call => {
                if (try self.retainedCall(source, depth + 1)) |captured| return captured;
                for (self.module.call(source).arguments) |argument| {
                    if (try self.capturesOpening(argument, depth + 1)) return true;
                }
            },
            else => {},
        }
        return false;
    }
    const CaptureChildren = struct {
        walker: *Self,
        found: bool = false,
        return_target: ?core.Id = null,
        depth: usize,
        pub fn append(self: *@This(), _: std.mem.Allocator, id: core.Id) (std.mem.Allocator.Error || error{PlanLimit})!void {
            if (id == 0 or self.found) return;
            if (self.return_target) |target_| {
                self.found = self.walker.returnCaptures(id, target_, self.depth + 1) catch return error.PlanLimit;
            } else self.found = self.walker.capturedReferences(id, self.depth + 1) catch return error.PlanLimit;
        }
        pub fn appendSlice(self: *@This(), allocator: std.mem.Allocator, ids: []const core.Id) (std.mem.Allocator.Error || error{PlanLimit})!void {
            for (ids) |id| try self.append(allocator, id);
        }
    };
    fn returnCaptures(self: *Self, source: core.Id, target_: core.Id, depth: usize) Error!bool {
        try self.step(depth);
        const node = self.module.node(source);
        if (node.tag == .return_) {
            if (node.b == target_) return self.capturesOpening(node.a, depth + 1);
            return false;
        }
        var children: CaptureChildren = .{ .walker = self, .return_target = target_, .depth = depth };
        @import("../eval/body_recipe.zig").appendChildren(&children, undefined, self.module, source, false) catch return error.InvalidArtifact;
        return children.found;
    }
    fn patternCaptures(self: *Self, id: core.PatternId, depth: usize) Error!bool {
        try self.step(depth);
        const pattern_ = self.module.pattern(id);
        switch (pattern_.tag) {
            .value => return self.capturedReferences(pattern_.a, depth + 1),
            .constructor, .record_payload => if (pattern_.b != 0) return self.patternCaptures(pattern_.b, depth + 1),
            .product => for (self.module.patternChildren(id)) |child| if (try self.patternCaptures(child, depth + 1)) return true,
            .invalid => return error.InvalidArtifact,
            else => {},
        }
        return false;
    }
    fn capturedReferences(self: *Self, source: core.Id, depth: usize) Error!bool {
        try self.step(depth);
        const node = self.module.node(source);
        switch (node.tag) {
            .reference, .closure, .suspend_ => return self.capturesOpening(source, depth + 1),
            .package_pack => return false,
            .match => for (self.module.matchArms(source)) |arm| {
                for (self.module.armRows(arm)) |row| for (self.module.rowPatterns(row)) |pattern_| if (try self.patternCaptures(pattern_, depth + 1)) return true;
            },
            .pattern_bind => if (try self.patternCaptures(node.a, depth + 1)) return true,
            .loop => {
                const pattern_ = self.module.loopInfo(source).pattern;
                if (pattern_ != 0 and try self.patternCaptures(pattern_, depth + 1)) return true;
            },
            .request_loop => {
                const pattern_ = self.module.requestLoopInfo(source).completion_pattern;
                if (pattern_ != 0 and try self.patternCaptures(pattern_, depth + 1)) return true;
            },
            .invalid => return error.InvalidArtifact,
            else => {},
        }
        var children: CaptureChildren = .{ .walker = self, .depth = depth };
        if (node.tag == .operation_value) {
            const operation = self.module.operationValue(source);
            children.appendSlice(undefined, &.{ operation.capability, operation.witness }) catch return error.InvalidArtifact;
        } else @import("../eval/body_recipe.zig").appendChildren(&children, undefined, self.module, source, false) catch return error.InvalidArtifact;
        return children.found;
    }
    const Definitions = struct {
        const empty: @This() = .{};
        facts: @import("package_row_facts.zig").Facts = .{},
        fn isSet(self: *const @This(), binding: core.BindingId) bool {
            return self.facts.contains(binding);
        }
        fn set(self: *@This(), binding: core.BindingId) Error!void {
            try self.facts.set(binding);
        }
        fn eql(self: *const @This(), other: @This()) bool {
            return self.facts.eql(&other.facts);
        }
    };
    fn declareStorage(self: *Self, binding: core.BindingId, definitions: *Definitions) Error!void {
        try require(binding != 0 and !definitions.isSet(binding));
        const kind = self.module.binding(binding).kind;
        try require(kind == .local or kind == .parameter);
        try definitions.set(binding);
    }
    fn bodyStorage(self: *Self, parameters: []const core.Parameter, body: core.Id) Error!void {
        var definitions: Definitions = .empty;
        for (parameters) |parameter| if (parameter.binding != 0) try self.declareStorage(parameter.binding, &definitions);
        _ = try self.storage(body, &definitions, 0);
    }
    fn closureStorage(self: *Self, closure: core.ClosureInfo) Error!void {
        if (closure.qualifier != 0) try self.scheme(self.module.binding(closure.qualifier).scheme);
        var definitions: Definitions = .empty;
        if (closure.parameter.binding != 0) try self.declareStorage(closure.parameter.binding, &definitions);
        for (self.module.extra[closure.captures.start..][0..closure.captures.len]) |binding| try self.declareStorage(binding, &definitions);
        _ = try self.storage(closure.body, &definitions, 0);
    }
    fn patternStorage(self: *Self, id: core.PatternId, definitions: *Definitions, depth: usize) Error!void {
        try self.step(depth);
        const pattern_ = self.module.pattern(id);
        switch (pattern_.tag) {
            .value => _ = try self.storage(pattern_.a, definitions, depth + 1),
            .product => for (self.module.patternChildren(id)) |child| try self.patternStorage(child, definitions, depth + 1),
            .constructor, .record_payload => if (pattern_.b != 0) try self.patternStorage(pattern_.b, definitions, depth + 1),
            else => {},
        }
    }
    fn storageMerges(self: *Self, source: core.Id, definitions: *Definitions, branches: []const Definitions, exits: []const bool) Error!void {
        const merges = self.module.branchMerges(source);
        if (merges.len == 0) return;
        try require(branches.len == 2 and exits.len == 2);
        for (merges) |merge| {
            try require(merge.node == source);
            for ([_]core.BindingId{ merge.then_binding, merge.else_binding }, branches, exits) |binding, branch, exited| {
                if (!exited) try require(branch.isSet(binding));
            }
            try self.declareStorage(merge.result, definitions);
        }
    }
    fn storage(self: *Self, source: core.Id, definitions: *Definitions, depth: usize) Error!bool {
        try self.step(depth);
        if (source == 0) return false;
        const node = self.module.node(source);
        for (self.module.dictionary_uses) |use| if (use.introduction != 0 and use.introduction == source) try definitions.set(use.binding);
        switch (node.tag) {
            .reference => {
                const reference = self.module.reference(source);
                if (reference.unit != 0 and reference.unit != self.module.unit) return false;
                const kind = self.module.binding(reference.binding).kind;
                if (kind == .local or kind == .parameter) try require(definitions.isSet(reference.binding));
            },
            .closure, .suspend_ => {
                const child = self.module.closures[node.a];
                for (self.module.extra[child.captures.start..][0..child.captures.len]) |binding| try require(definitions.isSet(binding));
            },
            .bind => {
                _ = try self.storage(node.b, definitions, depth + 1);
                try self.declareStorage(node.a, definitions);
            },
            .pattern_bind => {
                _ = try self.storage(node.b, definitions, depth + 1);
                if (node.c != 0) {
                    var fallback = definitions.*;
                    try require(try self.storage(node.c, &fallback, depth + 1));
                }
                try self.patternStorage(node.a, definitions, depth + 1);
                try self.pattern(node.a, self.module.typeOf(node.b), definitions, depth + 1);
            },
            .block => {
                var local = definitions.*;
                for (self.module.children(source)) |child| _ = try self.storage(child, &local, depth + 1);
            },
            .suite => {
                var exits = false;
                for (self.module.children(source)) |child| exits = try self.storage(child, definitions, depth + 1) or exits;
                return exits;
            },
            .package_unpack => {
                _ = try self.storage(node.a, definitions, depth + 1);
                var local = definitions.*;
                try self.declareStorage(node.b, &local);
                for (self.module.dictionary_uses) |use| if (use.opening == node.b) try local.set(use.binding);
                _ = try self.storage(self.module.packageOpening(source).body, &local, depth + 1);
            },
            .if_value, .if_stmt => {
                _ = try self.storage(node.a, definitions, depth + 1);
                var branches = [_]Definitions{ definitions.*, definitions.* };
                var exits: [2]bool = undefined;
                for ([_]core.Id{ node.b, node.c }, &branches, &exits) |branch, *local, *exited| exited.* = try self.storage(branch, local, depth + 1);
                // The checker directly names a surviving branch's successor
                // when the other branch exits; no merge binding is necessary.
                if (node.tag == .if_stmt and exits[0] != exits[1]) definitions.* = branches[if (exits[0]) 1 else 0];
                try self.storageMerges(source, definitions, &branches, &exits);
                return node.tag == .if_stmt and exits[0] and exits[1];
            },
            .match => {
                for (self.module.matchInputs(source)) |input| _ = try self.storage(input, definitions, depth + 1);
                var branches: [2]Definitions = undefined;
                var exits: [2]bool = undefined;
                var all_exit = true;
                var survivor: Definitions = undefined;
                var continuing: usize = 0;
                for (self.module.matchArms(source), 0..) |arm, index| {
                    var local = definitions.*;
                    for (self.module.armRows(arm), 0..) |row, ordinal| {
                        var alternate = definitions.*;
                        for (self.module.rowPatterns(row)) |pattern_| {
                            try self.patternStorage(pattern_, &alternate, depth + 1);
                            try self.pattern(pattern_, self.module.pattern(pattern_).ty, &alternate, depth + 1);
                        }
                        if (ordinal == 0) local = alternate else try require(local.eql(alternate));
                    }
                    _ = try self.storage(arm.guard, &local, depth + 1);
                    const exited = try self.storage(arm.body, &local, depth + 1);
                    all_exit = all_exit and exited;
                    if (!exited) {
                        survivor = local;
                        continuing += 1;
                    }
                    if (index < branches.len) {
                        branches[index] = local;
                        exits[index] = exited;
                    }
                }
                if (self.module.matchInfo(source).statement and continuing == 1) definitions.* = survivor;
                if (self.module.branchMerges(source).len != 0) {
                    try require(self.module.matchArms(source).len == 2);
                    try self.storageMerges(source, definitions, &branches, &exits);
                }
                return self.module.matchInfo(source).statement and all_exit;
            },
            .loop => {
                const info = self.module.loopInfo(source);
                _ = try self.storage(info.first, definitions, depth + 1);
                _ = try self.storage(info.end, definitions, depth + 1);
                var local = definitions.*;
                for (self.module.loopCarries(source)) |carry| {
                    try require(definitions.isSet(carry.incoming));
                    try self.declareStorage(carry.iteration, &local);
                }
                if (info.pattern != 0) {
                    try self.patternStorage(info.pattern, &local, depth + 1);
                    try self.pattern(info.pattern, self.module.pattern(info.pattern).ty, &local, depth + 1);
                }
                const exited = try self.storage(info.body, &local, depth + 1);
                for (self.module.loopCarries(source)) |carry| {
                    if (!exited) try require(local.isSet(carry.backedge));
                    try self.declareStorage(carry.outgoing, definitions);
                }
            },
            .request_loop => {
                const info = self.module.requestLoopInfo(source);
                _ = try self.storage(info.computation, definitions, depth + 1);
                for (self.module.requestArms(source)) |arm| {
                    _ = try self.storage(arm.selector, definitions, depth + 1);
                    _ = try self.storage(arm.callback, definitions, depth + 1);
                }
                var local = definitions.*;
                for (self.module.requestCompletionBindings(source)) |binding| try self.declareStorage(binding, &local);
                try self.patternStorage(info.completion_pattern, &local, depth + 1);
                try self.pattern(info.completion_pattern, info.value_type, &local, depth + 1);
                _ = try self.storage(info.completion_body, &local, depth + 1);
                for (self.module.requestLoopCarries(source)) |carry| {
                    try require(definitions.isSet(carry.incoming));
                    try self.declareStorage(carry.outgoing, definitions);
                }
            },
            .update => {
                const info = self.module.updateInfo(source);
                _ = try self.storage(info.root, definitions, depth + 1);
                for (self.module.updateSelectors(source)) |selector| if (selector.kind == .index) {
                    _ = try self.storage(selector.index, definitions, depth + 1);
                };
                var local = definitions.*;
                try self.declareStorage(info.self_binding, &local);
                _ = try self.storage(info.value, &local, depth + 1);
            },
            .invalid => return error.InvalidArtifact,
            else => {
                var work: StorageChildren = .{ .walker = self, .definitions = definitions, .depth = depth };
                if (node.tag == .operation_value) {
                    const operation = self.module.operationValue(source);
                    work.appendSlice(std.heap.page_allocator, &.{ operation.capability, operation.witness }) catch return error.InvalidArtifact;
                } else if (node.tag == .package_pack) {
                    work.appendSlice(std.heap.page_allocator, self.module.children(source)) catch return error.InvalidArtifact;
                } else @import("../eval/body_recipe.zig").appendChildren(&work, std.heap.page_allocator, self.module, source, false) catch return error.InvalidArtifact;
                return node.tag == .return_ or node.tag == .break_ or node.ty == T.never;
            },
        }
        return false;
    }
    const StorageChildren = struct {
        walker: *Self,
        definitions: *Definitions,
        depth: usize,
        pub fn append(self: *@This(), _: std.mem.Allocator, id: core.Id) (std.mem.Allocator.Error || error{PlanLimit})!void {
            if (id == 0) return;
            _ = self.walker.storage(id, self.definitions, self.depth + 1) catch return error.PlanLimit;
        }
        pub fn appendSlice(self: *@This(), allocator: std.mem.Allocator, ids: []const core.Id) (std.mem.Allocator.Error || error{PlanLimit})!void {
            for (ids) |id| try self.append(allocator, id);
        }
    };
    fn sameOperation(self: *Self, first: T.Operation, second: T.Operation, depth: usize) Error!bool {
        try self.step(depth);
        if (!std.meta.eql(first.identity, second.identity) or !std.meta.eql(first.instance, second.instance) or first.arguments.len != second.arguments.len) return false;
        for (self.module.types.list(first.arguments), self.module.types.list(second.arguments)) |left, right| self.strictSame(left, right) catch {
            try require(self.scopes.remaining.* != 0);
            return false;
        };
        return true;
    }
    fn requestArm(self: *Self, info: core.RequestLoopInfo, arm: core.RequestArm, depth: usize) Error!void {
        const node = self.module.node(arm.callback);
        try require(node.tag == .closure);
        const callback = self.module.closure(arm.callback);
        const arrow = self.module.types.node(callback.function_type);
        try require(arrow.tag == .function);
        try self.strictSame(node.ty, callback.function_type);
        try self.strictSame(arrow.a, callback.parameter.ty);
        try self.output(arrow.b, callback.body);
        const input = self.module.types.node(arrow.a);
        const output_ = self.module.types.node(arrow.b);
        try require(input.tag == .product and input.b == 2 and output_.tag == .nominal and output_.a == std.math.maxInt(u32) and output_.b == 6);
        const parameters = self.module.types.list(.{ .start = input.a, .len = input.b });
        const results = self.module.types.nominalArguments(output_);
        try require(results.len == 3);
        try self.strictSame(info.state_type, parameters[1]);
        try self.strictSame(info.state_type, results[1]);
        try self.strictSame(info.result_type, results[2]);
        const operation = self.module.types.operation(arm.operation);
        try @import("staging_core.zig").declaredOperation(self.module, self.context.units, operation, parameters[0], results[0], self.scopes.remaining);
        if (operation.instance.decl == 0) {
            try require(arm.selector == 0);
        } else {
            try require(arm.selector != 0 and self.module.node(arm.selector).tag == .operation_value);
            const selector = self.module.operationValue(arm.selector);
            try require(try self.sameOperation(operation, .{ .identity = selector.identity, .instance = selector.instance, .arguments = selector.arguments }, depth + 1));
            try self.expression(arm.selector, depth + 1);
        }
        const saved = self.decision_owner;
        const owner: DecisionOwner = .{ .callback = arm.callback, .ty = arrow.b };
        self.decision_owner = &owner;
        defer self.decision_owner = saved;
        try self.expression(arm.callback, depth + 1);
        // Clauses execute outside this request installation.
        try self.allowedRow(arrow.c, true);
    }
    fn requestLoop(self: *Self, source: core.Id, depth: usize) Error!void {
        const info = self.module.requestLoopInfo(source);
        const destination = self.return_owner orelse return error.InvalidArtifact;
        try require(self.module.typeOf(source) == T.unit and info.return_target == destination.node);
        try self.strictSame(info.result_type, self.module.typeOf(destination.node));
        const computation = self.module.types.node(self.module.typeOf(info.computation));
        try require(computation.tag == .nominal and computation.a == std.math.maxInt(u32) and computation.b == 5);
        const arguments_ = self.module.types.nominalArguments(computation);
        try require(arguments_.len == 1);
        const action = self.module.types.node(arguments_[0]);
        const selected = self.module.types.node(info.action_type);
        try require(action.tag == .function and selected.tag == .function and action.a == T.unit and selected.a == T.unit);
        try self.strictSame(action.b, info.value_type);
        try self.strictSame(selected.b, info.value_type);
        try self.expression(info.computation, depth + 1);
        var actual_rows: T.List = .{};
        const value = self.module.node(info.computation);
        if (value.tag == .computation and self.module.node(value.a).tag == .closure) actual_rows = self.module.closure(value.a).closed_rows;
        var request_proof: contracts.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes, .left_rows = actual_rows, .foreign_views = true };
        try request_proof.validate(arguments_[0], info.action_type);
        const carries = self.module.requestLoopCarries(source);
        const completion = self.module.requestCompletionBindings(source);
        try require(completion.len == carries.len);
        const state = self.module.types.node(info.state_type);
        if (carries.len == 0) try require(info.state_type == T.unit);
        if (carries.len > 1) try require(state.tag == .product and state.b == carries.len);
        for (carries, completion, 0..) |carry, binding, index| {
            var part = info.state_type;
            if (carries.len > 1) part = self.module.types.list(.{ .start = state.a, .len = state.b })[index];
            inline for (.{ "incoming", "iteration", "backedge", "outgoing" }) |field| try self.strictSame(part, self.module.binding(@field(carry, field)).ty);
            try self.strictSame(part, self.module.binding(binding).ty);
            try require(self.module.binding(carry.iteration).initializer == 0 and self.module.binding(carry.outgoing).initializer == 0);
            try require(self.module.binding(binding).kind == .parameter and self.module.binding(binding).initializer == 0);
        }
        const labels = self.module.types.rowLabels(selected.c);
        try require(labels.len <= 256);
        var handled: std.bit_set.Static(256) = .empty;
        const arms = self.module.requestArms(source);
        for (arms, 0..) |arm, index| {
            const operation = self.module.types.operation(arm.operation);
            for (arms[0..index]) |earlier| try require(!try self.sameOperation(operation, self.module.types.operation(earlier.operation), depth + 1));
            var found = false;
            for (labels, 0..) |label, ordinal| {
                if (handled.isSet(ordinal) or !try self.sameOperation(operation, self.module.types.operation(label), depth + 1)) continue;
                handled.set(ordinal);
                found = true;
                break;
            }
            try require(found);
            try self.requestArm(info, arm, depth + 1);
        }
        try self.closeRows(actual_rows);
        try request_proof.handledRow(selected.c, self.body_row, handled, true);
        try self.pattern(info.completion_pattern, info.value_type, null, depth + 1);
        const owner: ControlOwner = .{ .node = source, .parent = self.loop_owner };
        self.loop_owner = &owner;
        defer self.loop_owner = owner.parent;
        try self.expression(info.completion_body, depth + 1);
    }
    fn requestDecision(self: *Self, source: core.Id, depth: usize) Error!void {
        const owner = self.decision_owner orelse return error.InvalidArtifact;
        const node = self.module.node(source);
        try self.strictSame(node.ty, owner.ty);
        const shape = self.module.types.node(owner.ty);
        try require(shape.tag == .nominal and shape.a == std.math.maxInt(u32) and shape.b == 6);
        const parts = self.module.types.nominalArguments(shape);
        try require(parts.len == 3 and node.a <= @backingInt(core.RequestDecisionKind.break_));
        const kind: core.RequestDecisionKind = @fromBackingInt(node.a);
        if (kind == .break_) try require(node.b == 0) else {
            var expected = parts[0];
            if (kind == .cancel) expected = parts[2];
            try self.expression(node.b, depth + 1);
            try self.output(expected, node.b);
        }
        if (kind == .cancel) try require(node.c == 0) else {
            try self.expression(node.c, depth + 1);
            try self.output(parts[1], node.c);
        }
    }

    fn builtin(self: *Self, ty: T.Id, instance: T.NominalIdentity) Error!void {
        const shape = self.module.types.node(ty);
        try require(shape.tag == .nominal and shape.a == instance.unit and shape.b == instance.decl and self.module.types.nominalArguments(shape).len == 0);
    }
    fn reflection(self: *Self, source: core.Id, depth: usize) Error!void {
        const node = self.module.node(source);
        const kind: @import("check.zig").ReflectionKind = @fromBackingInt(@intCast(node.a));
        switch (kind) {
            .of => {
                try require(node.c == 0);
                try self.builtin(node.ty, T.effect_set_identity);
                try self.scopes.validateRow(node.b, depth + 1);
            },
            .descriptor => {
                try require(node.c == 0);
                try self.builtin(node.ty, T.effect_descriptor_identity);
                const operation = self.module.types.operation(node.b);
                try require(try self.knownInstance(operation.instance));
                for (self.module.types.list(operation.arguments)) |argument| try self.scopes.visit(argument);
            },
            .count => {
                try require(node.c == 0);
                try self.expression(node.b, depth + 1);
                try self.builtin(self.module.typeOf(node.b), T.effect_set_identity);
                try self.strictSame(node.ty, T.u32_type);
            },
            .has, .same => {
                try self.expression(node.b, depth + 1);
                try self.expression(node.c, depth + 1);
                var left = T.effect_set_identity;
                if (kind == .same) left = T.effect_descriptor_identity;
                try self.builtin(self.module.typeOf(node.b), left);
                try self.builtin(self.module.typeOf(node.c), T.effect_descriptor_identity);
                try self.strictSame(node.ty, T.boolean);
            },
        }
    }
    fn projectionContract(self: *Self, source: core.Id, projection: core.Projection, writing: bool, depth: usize) Error!void {
        const owner = self.module.types.node(projection.source_type);
        if (projection.nominal.unit != 0 or projection.nominal.decl != 0) return self.nominalProjection(projection, depth + 1);
        if (projection.variants.len == 0) {
            const goal: core.Obligation = .{ .ty = projection.source_type, .kind = if (writing) .writable_field else .field, .name = projection.field, .result = projection.result_type, .span = self.module.span(source) };
            // An inferred getter may have become a concrete physical field
            // through an earlier callee equation. Reconstruct that field from
            // the checked constructor catalog before seeking a named method.
            if (try self.goalGiven(goal, depth + 1) or try self.closedGoal(goal, depth + 1)) return;
            if (writing) {
                // An inferred rebinding records an update requirement rather
                // than a separate writable-field requirement. This profile
                // admits it only when both field and owner keep their types.
                const update_goal: core.Obligation = .{ .ty = projection.source_type, .kind = .update, .name = projection.field, .other = projection.result_type, .result = projection.source_type, .span = self.module.span(source) };
                if (try self.goalGiven(update_goal, depth + 1)) return;
                return error.InvalidArtifact;
            }
            // Symbolic getters carry no physical nominal projection.
            // Reconstruct the original receiver from its checked type;
            // the ordinary member/scheme proof still owns selection.
            if (T.receiverIdentity(owner)) |family| {
                var member = projection;
                member.nominal = family;
                return self.memberProjection(member, depth + 1);
            }
            return error.InvalidArtifact;
        }
        try require(projection.variants.len == 1);
        const variant = self.module.projection_variants[projection.variants.start];
        try require(variant.tag == 0);
        var field: T.Id = 0;
        switch (owner.tag) {
            .product => {
                try require(variant.field < owner.b);
                field = self.module.types.list(.{ .start = owner.a, .len = owner.b })[variant.field];
            },
            .record => {
                try require(variant.field < owner.b);
                const member = self.module.types.recordField(owner, variant.field);
                if (projection.field != 0) try require(projection.field == member.name);
                field = member.ty;
            },
            else => return error.InvalidArtifact,
        }
        try self.strictSame(field, projection.result_type);
    }
    fn update(self: *Self, source: core.Id, depth: usize) Error!void {
        const info = self.module.updateInfo(source);
        try self.expression(info.root, depth + 1);
        var selected = self.module.typeOf(info.root);
        try self.strictSame(selected, self.module.typeOf(source));
        const selectors = self.module.updateSelectors(source);
        const path = self.module.updatePath(source);
        try require(selectors.len == 0 or path.len == 0);
        var through_array = false;
        const has_index = for (selectors) |selector| {
            if (selector.kind == .index) break true;
        } else false;
        for (selectors) |selector| {
            try self.step(depth);
            try self.strictSame(selected, selector.source_type);
            if (selector.kind == .field) {
                try require(selector.index == 0);
                const projection = self.module.projection(selector.projection);
                try self.strictSame(selected, projection.source_type);
                try self.strictSame(selector.result_type, projection.result_type);
                try self.projectionContract(source, projection, through_array or !has_index, depth + 1);
            } else {
                through_array = true;
                try require(selector.projection == 0);
                const element = @import("storage_types.zig").arrayElement(&self.module.types, selected) orelse return error.InvalidArtifact;
                try self.strictSame(element, selector.result_type);
                try self.expression(selector.index, depth + 1);
                try self.strictSame(T.u32_type, self.module.typeOf(selector.index));
            }
            selected = selector.result_type;
        }
        for (path) |id| {
            const projection = self.module.projection(id);
            try self.strictSame(selected, projection.source_type);
            try self.projectionContract(source, projection, true, depth + 1);
            selected = projection.result_type;
        }
        const binding = self.module.binding(info.self_binding);
        try require(binding.kind == .local and binding.initializer == 0);
        try self.strictSame(binding.ty, selected);
        try self.expression(info.value, depth + 1);
        try self.output(selected, info.value);
    }
    fn recordMerge(self: *Self, source: core.Id, depth: usize) Error!void {
        const node = self.module.node(source);
        try self.expression(node.a, depth + 1);
        try self.expression(node.b, depth + 1);
        const left = self.module.types.node(self.module.typeOf(node.a));
        const right = self.module.types.node(self.module.typeOf(node.b));
        const result = self.module.types.node(node.ty);
        if (left.tag != .record or right.tag != .record or result.tag != .record) {
            // The checker retains an exact merge dictionary when an ordinary
            // source helper abstracts its record inputs or result. That
            // dictionary proves this operation, not any physical field layout.
            // Known non-record heads and portable bodies still fail closed.
            try require(self.admission.source_bodies);
            for ([_]T.Node{ left, right, result }) |head| switch (head.tag) {
                .record, .variable, .bound, .rigid, .projection => {},
                else => return error.InvalidArtifact,
            };
            try require(try self.goalGivenMode(.{
                .kind = .record_merge,
                .ty = self.module.typeOf(node.a),
                .other = self.module.typeOf(node.b),
                .result = node.ty,
                .span = self.module.span(source),
            }, depth + 1, false));
            return;
        }
        try self.recordMergeFields(left, right, result, depth);
    }
    fn recordMergeFields(self: *Self, left: T.Node, right: T.Node, result: T.Node, depth: usize) Error!void {
        var output_: usize = 0;
        for (0..left.b) |index| {
            try self.step(depth);
            var field = self.module.types.recordField(left, index);
            for (0..right.b) |candidate| {
                try self.step(depth);
                const replacement = self.module.types.recordField(right, candidate);
                if (replacement.name == field.name) {
                    field = replacement;
                    break;
                }
            }
            try require(output_ < result.b);
            const actual = self.module.types.recordField(result, output_);
            try require(field.name == actual.name);
            // Selection preserves an identical opaque type without granting
            // its executable row, package or borrow authority. Different IDs
            // still require the full structural equality proof.
            if (field.ty != actual.ty) try self.strictSame(field.ty, actual.ty);
            output_ += 1;
        }
        for (0..right.b) |index| {
            try self.step(depth);
            const field = self.module.types.recordField(right, index);
            var present = false;
            for (0..left.b) |candidate| {
                try self.step(depth);
                if (self.module.types.recordField(left, candidate).name == field.name) {
                    present = true;
                    break;
                }
            }
            if (present) continue;
            try require(output_ < result.b);
            const actual = self.module.types.recordField(result, output_);
            try require(field.name == actual.name);
            // Selection preserves an identical opaque type without granting
            // its executable row, package or borrow authority. Different IDs
            // still require the full structural equality proof.
            if (field.ty != actual.ty) try self.strictSame(field.ty, actual.ty);
            output_ += 1;
        }
        try require(output_ == result.b);
    }

    fn loop(self: *Self, source: core.Id, depth: usize) Error!void {
        const info = self.module.loopInfo(source);
        try require(self.module.typeOf(source) == T.unit and self.module.node(info.body).tag == .suite and self.module.typeOf(info.body) == T.unit);
        var element: T.Id = 0;
        switch (info.kind) {
            .forever => try require(info.first == 0 and info.end == 0 and info.pattern == 0),
            .range => {
                try self.expression(info.first, depth + 1);
                try self.expression(info.end, depth + 1);
                try self.strictSame(T.u32_type, self.module.typeOf(info.first));
                try self.strictSame(T.u32_type, self.module.typeOf(info.end));
                element = T.u32_type;
            },
            .array => {
                try require(info.end == 0);
                try self.expression(info.first, depth + 1);
                const array = self.module.types.node(self.module.typeOf(info.first));
                element = if (array.tag == .list) array.a else @import("storage_types.zig").readableElement(&self.module.types, self.module.typeOf(info.first)) orelse return error.InvalidArtifact;
            },
        }
        for (self.module.loopCarries(source)) |carry| {
            const input = self.module.binding(carry.incoming).ty;
            inline for (.{ "iteration", "backedge", "outgoing" }) |field| try self.strictSame(input, self.module.binding(@field(carry, field)).ty);
            try require(self.module.binding(carry.iteration).initializer == 0 and self.module.binding(carry.outgoing).initializer == 0);
        }
        if (info.pattern != 0) {
            try require(element != 0);
            try self.pattern(info.pattern, element, null, depth + 1);
        }
        const owner: ControlOwner = .{ .node = source, .parent = self.loop_owner };
        self.loop_owner = &owner;
        defer self.loop_owner = owner.parent;
        try self.expression(info.body, depth + 1);
    }
    fn breakLoop(self: *Self, source: core.Id, depth: usize) Error!void {
        const owner = self.loop_owner orelse return error.InvalidArtifact;
        const node = self.module.node(source);
        try require(node.a == owner.node and node.ty == T.never);
        var carries: []const core.LoopCarry = undefined;
        if (self.module.node(owner.node).tag == .request_loop) {
            carries = self.module.requestLoopCarries(owner.node);
        } else carries = self.module.loopCarries(owner.node);
        const values = self.module.breakValues(source);
        try require(values.len == carries.len);
        for (values, carries) |value, carry| {
            try self.expression(value, depth + 1);
            try self.output(self.module.binding(carry.iteration).ty, value);
        }
    }
    fn match(self: *Self, source: core.Id, depth: usize) Error!void {
        const info = self.module.matchInfo(source);
        const inputs = self.module.matchInputs(source);
        try require(inputs.len != 0);
        for (inputs) |input| try self.expression(input, depth + 1);
        for (self.module.matchArms(source)) |arm| {
            const rows = self.module.armRows(arm);
            try require(rows.len != 0);
            var names: ?Definitions = null;
            for (rows) |row| {
                const patterns = self.module.rowPatterns(row);
                try require(patterns.len == inputs.len);
                var definitions: Definitions = .empty;
                for (patterns, inputs) |pattern_, input| try self.pattern(pattern_, self.module.typeOf(input), &definitions, depth + 1);
                if (names) |prior| try require(prior.eql(definitions));
                names = definitions;
            }
            if (arm.guard != 0) {
                try self.expression(arm.guard, depth + 1);
                try self.strictSame(T.boolean, self.module.typeOf(arm.guard));
            }
            try self.expression(arm.body, depth + 1);
            if (info.statement) {
                try require(self.module.typeOf(source) == T.unit);
                if (arm.body != 0) try require(self.module.node(arm.body).tag == .suite and self.module.typeOf(arm.body) == T.unit);
            } else try self.output(self.module.typeOf(source), arm.body);
        }
    }

    fn expression(self: *Self, source: core.Id, depth: usize) Error!void {
        errdefer if (self.admission.source_failure) |failure| {
            if (failure.* == null) failure.* = .{ .unit = self.module.unit, .span = self.module.span(source) };
        };
        try self.step(depth);
        if (source == 0) return;
        const node = self.module.node(source);
        if (node.tag == .reference) {
            try @import("dictionary_contracts.zig").use(self.module, source, self.scopes);
            try self.principal(self.module.reference(source), node.ty);
        }
        try self.providerRows(source, depth + 1);
        // A call's checked producer establishes its instantiated result rows,
        // just as a reference does above. Validate that result only after the
        // complete call correspondence and actual operands have passed.
        if (node.tag != .closure and node.tag != .suspend_ and node.tag != .call and node.tag != .apply) try self.scopes.visit(node.ty);
        switch (node.tag) {
            .package_pack => {
                const witnesses = self.module.types.list(.{ .start = node.b, .len = node.c });
                const dictionaries = @import("dictionary_contracts.zig");
                try dictionaries.pack(self.module, source, self.scopes);
                var projection: dictionaries.PackProjection = .{ .module = self.module, .owner = source };
                const prior_resolver = self.scopes.projection_resolver;
                self.scopes.projection_resolver = projection.resolver();
                defer self.scopes.projection_resolver = prior_resolver;
                try self.scopes.pack(node.ty, self.module.typeOf(node.a), witnesses);
                const outer = self.sealed;
                defer self.sealed = outer;
                for (witnesses) |witness| try self.sealWitness(witness, depth + 1);
                for (self.module.children(source)) |child| {
                    try self.expression(child, depth + 1);
                    try require(!try self.capturesOpening(child, depth + 1));
                }
            },
            .package_unpack => {
                try self.expression(node.a, depth + 1);
                const opening = self.module.packageOpening(source);
                try require(self.module.binding(node.b).kind == .local);
                const binding = self.module.binding(node.b);
                try require(binding.scheme.root == 0);
                try self.scheme(binding.scheme);
                try self.scopes.open(self.module.typeOf(node.a), node.b, opening.binders, self.module.binding(node.b).ty);
                defer self.scopes.close();
                try self.expression(opening.body, depth + 1);
                try self.output(node.ty, opening.body);
                try require(!try self.capturesOpening(opening.body, depth + 1));
            },
            .reference => {},
            .resolver_op => {
                const resolvers = @import("resolver_core.zig");
                const info = self.module.resolverInfo(source);
                const judgments = try resolvers.judgments(self.module, source);
                try self.expression(info.resolver, depth + 1);
                const operands = self.module.resolverArguments(source);
                const parent_callback = self.resolver_callback;
                defer self.resolver_callback = parent_callback;
                if (info.operation == .bind or info.operation == .iterate) self.resolver_callback = operands[1];
                for (operands) |argument| try self.expression(argument, depth + 1);
                inline for (.{ "factory", "dispatch", "result" }) |field| if (@field(judgments, field)) |goal| {
                    try require(try self.goalGiven(goal, depth + 1) or try self.closedGoal(goal, depth + 1));
                };
                if (judgments.dispatch != null) {
                    if (try resolvers.selectedCallWorkspace(self.module, self.units(), source, self.scopes.remaining, self.admission.workspace)) |call| try self.principal(call.target, call.callee_type);
                    try self.arguments(info.method_type, operands, node.ty, null);
                } else if (info.operation == .forward) {
                    try self.strictSame(self.module.typeOf(operands[0]), node.ty);
                } else if (info.operation == .run) {
                    var callback = self.module.types.node(self.module.typeOf(operands[0]));
                    if (callback.tag == .usage) callback = self.module.types.node(callback.a);
                    try require(callback.tag == .function);
                    try require(callback.a == T.unit);
                    try self.same(callback.b, node.ty);
                    try self.allowedRow(callback.c, true);
                }
            },
            .request_loop => try self.requestLoop(source, depth + 1),
            .request_decision => try self.requestDecision(source, depth + 1),
            .computation => {
                const shape = self.module.types.node(node.ty);
                try require(shape.tag == .nominal and shape.a == std.math.maxInt(u32) and shape.b == 5);
                const parameters = self.module.types.nominalArguments(shape);
                try require(parameters.len == 1);
                try self.expression(node.a, depth + 1);
                try self.strictSame(parameters[0], self.module.typeOf(node.a));
            },
            .force => {
                const shape = self.module.types.node(self.module.typeOf(node.a));
                try require(shape.tag == .demand);
                try self.expression(node.a, depth + 1);
                try self.strictSame(node.ty, shape.a);
                try self.allowedRow(shape.c, true);
            },
            .operation_value => {
                const operation = self.module.operationValue(source);
                try self.operationAuthority(operation);
                if (operation.capability != 0) try self.expression(operation.capability, depth + 1);
                try self.same(operation.signature, node.ty);
                const arrow = self.module.types.node(operation.signature);
                try require(arrow.tag == .function);
                try self.scopes.validateRow(arrow.c, depth + 1);
                var found = false;
                for (self.module.types.rowLabels(arrow.c)) |label| {
                    try self.step(depth);
                    const actual = self.module.types.operation(label);
                    if (!std.meta.eql(actual.identity, operation.identity) or !std.meta.eql(actual.instance, operation.instance) or actual.arguments.len != operation.arguments.len) continue;
                    var matches = true;
                    for (self.module.types.list(actual.arguments), self.module.types.list(operation.arguments)) |left, right| self.strictSame(left, right) catch {
                        try require(self.scopes.remaining.* != 0);
                        matches = false;
                        break;
                    };
                    if (!matches) continue;
                    found = true;
                    break;
                }
                if (!found) try require(operation.instance.decl == 0 and try self.operationGiven(source, operation, depth + 1));
            },
            .closure, .suspend_ => {
                const outer_return = self.return_owner;
                const parent_call = self.call_owner;
                self.call_owner = 0;
                defer self.call_owner = parent_call;
                const outer_loop = self.loop_owner;
                const outer_decision = self.decision_owner;
                self.return_owner = null;
                self.loop_owner = null;
                if (self.decision_owner) |owner| if (owner.callback != source) {
                    self.decision_owner = null;
                };
                defer self.return_owner = outer_return;
                defer self.loop_owner = outer_loop;
                defer self.decision_owner = outer_decision;
                const closure = self.module.closures[node.a];
                const prior_scope = self.scope_owner;
                var region_owner: ScopeOwner = undefined;
                if (node.tag == .closure) if (@import("task_types.zig").scopeCallback(&self.module.types, node.ty)) |arrow| {
                    const group = self.module.types.node(arrow.a);
                    region_owner = .{ .identity = .{ .unit = group.b, .decl = group.c }, .parent = prior_scope };
                    self.scope_owner = &region_owner;
                };
                defer self.scope_owner = prior_scope;
                var signature = node.ty;
                if (node.tag == .suspend_) {
                    const demand = self.module.types.node(node.ty);
                    const arrow = self.module.types.node(closure.function_type);
                    try require(demand.tag == .demand and arrow.tag == .function and arrow.a == T.unit);
                    try self.strictSame(demand.a, arrow.b);
                    var rows: contracts.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes };
                    try rows.rows(demand.c, arrow.c);
                    signature = closure.function_type;
                }
                const outer_rows = self.closed_rows;
                const outer_pure = self.scopes.pure_rows;
                const outer_closed = self.scopes.closed_rows;
                const outer_instances = self.scopes.instance_variables;
                const outer_instance_rows = self.scopes.instance_rows;
                const outer_foreign = self.foreign_allowed;
                const outer_body_row = self.body_row;
                const outer_handled = self.handled_count;
                self.handled_count = 0;
                defer self.handled_count = outer_handled;
                defer self.closed_rows = outer_rows;
                defer self.scopes.pure_rows = outer_pure;
                defer self.scopes.closed_rows = outer_closed;
                defer self.scopes.instance_variables = outer_instances;
                defer self.scopes.instance_rows = outer_instance_rows;
                defer self.foreign_allowed = outer_foreign;
                defer self.body_row = outer_body_row;
                self.closed_rows = closure.closed_rows;
                self.body_row = try self.effectSignature(signature, 1);
                self.foreign_allowed = self.rowHasForeign(self.body_row);
                try self.closeRows(closure.closed_rows);
                try self.scopes.visit(node.ty);
                try self.same(signature, closure.function_type);
                var quantified_signature = signature;
                while (self.module.types.node(quantified_signature).tag == .usage) quantified_signature = self.module.types.node(quantified_signature).a;
                const quantified = self.module.types.node(quantified_signature).tag == .forall;
                if (quantified) {
                    try self.scopes.enter(quantified_signature);
                    self.scopes.introductions[self.scopes.formal_count - 1] = closure.body;
                }
                defer if (quantified) self.scopes.leave();
                try self.closureStorage(closure);
                const resolver_parameter = self.resolver_callback == source;
                const parent_callback = self.resolver_callback;
                self.resolver_callback = 0;
                defer self.resolver_callback = parent_callback;
                try self.header(signature, &.{closure.parameter}, closure.body, resolver_parameter);
                try self.expression(closure.body, depth + 1);
            },
            .effect_scope => {
                try require(self.module.node(node.a).tag == .closure);
                const callback = self.module.closure(node.a);
                const capability = self.module.types.node(callback.parameter.ty);
                try require(capability.tag == .scoped and capability.c != 0);
                const instance: T.NominalIdentity = .{ .unit = capability.b, .decl = capability.c };
                try require(!try self.knownInstance(instance));
                const owner: ScopeOwner = .{ .identity = instance, .parent = self.scope_owner };
                self.scope_owner = &owner;
                defer self.scope_owner = owner.parent;
                try self.expression(node.a, depth + 1);
                const arrow = self.module.types.node(callback.function_type);
                try require(arrow.tag == .function);
                try self.strictSame(node.ty, arrow.b);
            },
            .apply => {
                const parent_callback = self.resolver_callback;
                if (self.module.node(node.a).tag == .closure) self.resolver_callback = node.a;
                {
                    const parent_call = self.call_owner;
                    if (parent_call == 0) self.call_owner = source;
                    defer self.call_owner = parent_call;
                    self.expression(node.a, depth + 1) catch |err| {
                        self.resolver_callback = parent_callback;
                        return err;
                    };
                }
                self.resolver_callback = parent_callback;
                {
                    const parent_call = self.call_owner;
                    self.call_owner = 0;
                    defer self.call_owner = parent_call;
                    try self.expression(node.b, depth + 1);
                }
                const initializer = self.module.node(node.b);
                if (initializer.tag == .closure or initializer.tag == .suspend_) {
                    // Publish its closing facts only after independently
                    // reconstructing the actual initializer body above.
                    try self.closeRows(self.module.closures[initializer.a].closed_rows);
                }
                var signature = self.module.typeOf(node.a);
                if (node.c != 0) {
                    try self.scopes.visit(node.c);
                    const callee = self.module.node(node.a);
                    if (self.module.types.node(signature).tag == .forall) {
                        var proof: contracts.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes };
                        try proof.instantiateTypes(signature, node.c);
                        try @import("dictionary_contracts.zig").instantiated(self.module, self.module, signature, proof.witnesses[0..self.module.types.node(signature).c], self.scopes);
                    } else {
                        try require(callee.tag == .reference);
                        const reference = self.module.reference(node.a);
                        const owner = try self.target(reference);
                        const declaration = owner.binding(reference.binding);
                        try require(owner.types.node(declaration.ty).tag == .forall or declaration.scheme.variables.len != 0 or declaration.scheme.row_variables.len != 0);
                        {
                            const parent_call = self.call_owner;
                            self.call_owner = source;
                            defer self.call_owner = parent_call;
                            try self.principal(reference, node.c);
                        }
                        try self.same(signature, node.c);
                    }
                    signature = node.c;
                } else try require(self.module.types.node(signature).tag != .forall);
                try self.arguments(signature, &.{node.b}, node.ty, null);
                if (try self.capturesOpening(node.b, depth + 1)) try require(try self.openingOperation(node.a, depth + 1));
                try self.scopes.visit(node.ty);
            },
            .effect_provider => {
                const provider = self.module.types.node(node.ty);
                try require(provider.tag == .provider and provider.b == 0);
                try self.expression(node.a, depth + 1);
                try self.expression(node.b, depth + 1);
                try self.operationToken(node.a, provider.a, depth + 1);
                const operation = self.module.types.node(self.module.typeOf(node.a));
                const implementation = self.module.types.node(self.module.typeOf(node.b));
                try require(operation.tag == .function and implementation.tag == .function);
                try self.strictSame(operation.a, implementation.a);
                try self.strictSame(operation.b, implementation.b);
                var rows: contracts.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes };
                try rows.rows(provider.c, implementation.c);
            },
            .state_provider => {
                const provider = self.module.types.node(node.ty);
                try require(provider.tag == .state_provider);
                try self.expression(node.a, depth + 1);
                try self.expression(node.b, depth + 1);
                try self.expression(node.c, depth + 1);
                try self.operationToken(node.a, provider.a, depth + 1);
                try self.operationToken(node.b, provider.b, depth + 1);
                const reader = self.module.types.node(self.module.typeOf(node.a));
                const writer = self.module.types.node(self.module.typeOf(node.b));
                try require(reader.tag == .function and writer.tag == .function);
                try self.strictSame(reader.a, T.unit);
                try self.strictSame(writer.b, T.unit);
                try self.strictSame(reader.b, writer.a);
                try self.strictSame(provider.c, reader.b);
                try self.strictSame(provider.c, self.module.typeOf(node.c));
                var proof: contracts.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes };
                if (proof.validate(provider.a, provider.b)) |_| return error.InvalidArtifact else |_| try require(self.scopes.remaining.* != 0);
            },
            .handle => {
                try self.expression(node.a, depth + 1);
                const provider = self.module.types.node(self.module.typeOf(node.a));
                try require(provider.tag == .provider or provider.tag == .state_provider);
                if (provider.tag == .provider) try self.allowedRow(provider.c, true);
                const count = self.handled_count;
                defer self.handled_count = count;
                try require(count < self.handled.len);
                self.handled[count] = provider.a;
                self.handled_count += 1;
                if (provider.tag == .state_provider) {
                    try require(self.handled_count < self.handled.len);
                    self.handled[self.handled_count] = provider.b;
                    self.handled_count += 1;
                }
                if (self.module.handleEffects(source)) |metadata| {
                    try self.strictSame(metadata.first, provider.a);
                    if (provider.tag == .state_provider) try self.strictSame(metadata.second, provider.b) else try require(metadata.second == 0);
                    var rows: contracts.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes };
                    try rows.rows(metadata.residual, self.body_row);
                    try self.allowedRow(metadata.extended, false);
                }
                try self.expression(node.b, depth + 1);
                if (provider.tag == .provider or self.module.typeOf(node.b) == T.never) {
                    try self.output(node.ty, node.b);
                } else {
                    const result = self.module.types.node(node.ty);
                    try require(result.tag == .product and result.b == 2);
                    const parts = self.module.types.list(.{ .start = result.a, .len = result.b });
                    try self.strictSame(parts[0], provider.c);
                    try self.output(parts[1], node.b);
                }
            },
            .task => {
                try @import("task_core.zig").validateOperationContextWorkspace(self.module, self.units(), source, self.scopes.remaining, self.admission.workspace);
                const operands = self.module.children(source);
                if (node.c == @backingInt(@import("task_types.zig").Op.scope)) {
                    var signature = self.module.typeOf(operands[0]);
                    for (0..128) |_| {
                        const wrapper = self.module.types.node(signature);
                        if (wrapper.tag != .usage and wrapper.tag != .forall) break;
                        signature = wrapper.a;
                    } else return error.InvalidArtifact;
                    const arrow = self.module.types.node(signature);
                    try require(arrow.tag == .function);
                    const group = self.module.types.node(arrow.a);
                    try require(group.tag == .scoped and group.c != 0);
                    const parent = self.scope_owner;
                    var owner: ScopeOwner = .{ .identity = .{ .unit = group.b, .decl = group.c }, .parent = parent };
                    self.scope_owner = &owner;
                    defer self.scope_owner = parent;
                    try self.expression(operands[0], depth + 1);
                } else for (operands) |operand| try self.expression(operand, depth + 1);
            },
            .resource_acquire, .usage_borrow => {
                if (node.tag == .resource_acquire) try require(self.foreign_allowed);
                try self.expression(node.a, depth + 1);
                try self.expression(node.b, depth + 1);
            },
            .resource_scope => {
                try require(self.foreign_allowed);
                try self.expression(node.a, depth + 1);
                try self.expression(node.b, depth + 1);
                try self.expression(node.c, depth + 1);
            },
            .usage_read, .resource_release, .usage_share => {
                if (node.tag == .resource_release) try require(self.foreign_allowed);
                try self.expression(node.a, depth + 1);
                try require(!try self.openType(node.ty, depth + 1));
                // Immutable usage_core independently proves intrinsic
                // ownership, loan scopes, payloads and release authority.
            },
            .staging => {
                const staging = @import("typed_staging.zig");
                const operation: staging.Op = @fromBackingInt(node.c);
                if (operation == .quote) {
                    const shape = staging.codeInfo(&self.module.types, node.ty) orelse return error.InvalidArtifact;
                    try self.scopes.validateRow(shape.effects, depth + 1);
                    const outer = self.foreign_allowed;
                    const outer_body_row = self.body_row;
                    const outer_handled = self.handled_count;
                    self.handled_count = 0;
                    defer self.handled_count = outer_handled;
                    self.foreign_allowed = self.rowHasForeign(shape.effects);
                    self.body_row = shape.effects;
                    defer self.foreign_allowed = outer;
                    defer self.body_row = outer_body_row;
                    try self.expression(node.a, depth + 1);
                } else {
                    // Stage/shape admission owns the code graph. Emission
                    // still consumes its exact latent row at this use.
                    if (operation == .emit or operation == .splice) {
                        const shape = staging.codeInfo(&self.module.types, self.module.typeOf(node.a)) orelse return error.InvalidArtifact;
                        try self.allowedRow(shape.effects, true);
                    }
                    try self.expression(node.a, depth + 1);
                    try self.expression(node.b, depth + 1);
                }
            },
            .call => {
                const call = self.module.call(source);
                var mapping: contracts.Principal = undefined;
                {
                    const parent_call = self.call_owner;
                    self.call_owner = source;
                    defer self.call_owner = parent_call;
                    mapping = try self.principalMapping(call.target, call.callee_type);
                }
                const producer = try self.target(call.target);
                const callee_scheme = producer.binding(call.target.binding).scheme;
                const endpoint_scheme = try self.endpointScheme(producer, call.target.binding);
                mapping.instance = endpoint_scheme.variables;
                mapping.instance_rows = endpoint_scheme.row_variables;
                var projection: @import("scheme_projection.zig").Resolver = .{ .module = self.module, .producer = producer, .binding = call.target.binding, .applied = &mapping };
                var resolver: ?contracts.PrincipalProjectionResolver = null;
                if (producer.types.node(callee_scheme.root).tag != .forall and callee_scheme.obligations.len != 0) resolver = projection.resolver();
                for (call.arguments) |argument| {
                    const parent_call = self.call_owner;
                    self.call_owner = 0;
                    defer self.call_owner = parent_call;
                    try self.expression(argument, depth + 1);
                    if (try self.capturesOpening(argument, depth + 1)) try require(try self.genericOperation(call.target));
                }
                try self.arguments(call.callee_type, call.arguments, node.ty, resolver);
                try self.scopes.visit(node.ty);
            },
            .project => {
                try self.expression(node.a, depth + 1);
                const projection = self.module.projection(node.b);
                try self.same(projection.source_type, self.module.typeOf(node.a));
                try self.same(projection.result_type, node.ty);
                try self.projectionContract(source, projection, false, depth + 1);
            },
            .bind => {
                const binding = self.module.binding(node.a);
                try self.scopes.pushGeneric(binding.scheme);
                defer self.scopes.popGeneric();
                try self.expression(node.b, depth + 1);
                const initializer = self.module.node(node.b);
                if (initializer.tag == .closure or initializer.tag == .suspend_) try self.closeRows(self.module.closures[initializer.a].closed_rows);
                try self.same(binding.ty, self.module.typeOf(node.b));
                if (binding.scheme.root != 0) try self.same(binding.ty, binding.scheme.root);
                try self.scheme(binding.scheme);
            },
            .pattern_bind => {
                try require(node.ty == T.unit);
                try self.expression(node.b, depth + 1);
                if (node.c != 0) {
                    try require(self.module.node(node.c).tag == .suite and self.module.typeOf(node.c) == T.unit);
                    try self.expression(node.c, depth + 1);
                }
                try self.pattern(node.a, self.module.typeOf(node.b), null, depth + 1);
            },
            .return_ => {
                var owner = self.return_owner;
                while (owner) |candidate| {
                    if (candidate.node == node.b) break;
                    owner = candidate.parent;
                }
                try require(owner != null);
                try self.expression(node.a, depth + 1);
                try require(self.module.types.node(node.ty).tag == .never);
                if (self.module.typeOf(node.a) != T.never) try self.same(self.module.typeOf(node.b), self.module.typeOf(node.a));
                try require(!try self.capturesOpening(node.a, depth + 1));
            },
            .loop => try self.loop(source, depth + 1),
            .break_ => try self.breakLoop(source, depth + 1),
            .match => try self.match(source, depth + 1),
            .if_stmt => {
                try require(node.ty == T.unit);
                try self.expression(node.a, depth + 1);
                try self.strictSame(T.boolean, self.module.typeOf(node.a));
                for ([_]core.Id{ node.b, node.c }) |branch| if (branch != 0) {
                    try require(self.module.node(branch).tag == .suite and self.module.typeOf(branch) == T.unit);
                    try self.expression(branch, depth + 1);
                };
                for (self.module.branchMerges(source)) |merge| {
                    try require(merge.node == source and self.module.binding(merge.result).initializer == 0);
                    try self.strictSame(self.module.binding(merge.result).ty, self.module.binding(merge.then_binding).ty);
                    try self.strictSame(self.module.binding(merge.result).ty, self.module.binding(merge.else_binding).ty);
                }
            },
            .if_value => {
                try self.expression(node.a, depth + 1);
                try require(self.module.types.node(self.module.typeOf(node.a)).tag == .boolean);
                try self.expression(node.b, depth + 1);
                try self.expression(node.c, depth + 1);
                const result = self.module.types.node(node.ty);
                if (result.tag == .scoped and result.b == 0 and self.module.types.node(result.c).tag == .instance_selection) {
                    const selection = self.module.types.node(result.c);
                    const choices = self.module.types.nominalArguments(selection);
                    try require(selection.a == self.module.unit and (choices.len == 2 or choices.len == 3));
                    for (choices[0..2], [_]core.Id{ node.b, node.c }) |choice, branch| {
                        const capability = self.module.types.node(choice);
                        try require(capability.tag == .scoped);
                        try self.strictSame(result.a, capability.a);
                        try self.strictSame(choice, self.module.typeOf(branch));
                    }
                } else {
                    try self.output(node.ty, node.b);
                    try self.output(node.ty, node.c);
                }
            },
            .product, .record, .array => {
                var aggregate_type = node.ty;
                var aggregate = self.module.types.node(aggregate_type);
                if (aggregate.tag == .usage) {
                    try require(aggregate.b == @backingInt(T.UsageKind.unique) and aggregate.c == 0);
                    aggregate_type = aggregate.a;
                    aggregate = self.module.types.node(aggregate_type);
                }
                try require((node.tag == .product and aggregate.tag == .product and node.b == aggregate.b) or (node.tag == .record and aggregate.tag == .record and node.b == aggregate.b) or (node.tag == .array and (aggregate.tag == .list or @import("storage_types.zig").isArray(&self.module.types, aggregate_type))));
                for (self.module.children(source), 0..) |child, index| {
                    try self.expression(child, depth + 1);
                    var expected = if (node.tag == .array and aggregate.tag != .list) @import("storage_types.zig").arrayElement(&self.module.types, aggregate_type).? else aggregate.a;
                    if (node.tag == .product) expected = self.module.types.list(.{ .start = aggregate.a, .len = aggregate.b })[index];
                    if (node.tag == .record) expected = self.module.types.recordField(aggregate, self.module.extra[node.c + index]).ty;
                    try self.same(expected, self.module.typeOf(child));
                }
            },
            .block => {
                const owner: ControlOwner = .{ .node = source, .parent = self.return_owner };
                self.return_owner = &owner;
                defer self.return_owner = owner.parent;
                for (self.module.children(source)) |child| try self.expression(child, depth + 1);
            },
            .suite => for (self.module.children(source)) |child| try self.expression(child, depth + 1),
            .construct, .constructor_function => {
                const constructor = self.module.constructor(node.a);
                const family = self.module.nominals[constructor.nominal];
                try require(!family.is_opaque or family.identity.unit == self.module.unit);
                var proof: contracts.Principal = .{ .left = &self.module.types, .right = &self.module.types, .remaining = self.scopes.remaining, .views = self.scopes, .instance = constructor.scheme.variables, .instance_rows = constructor.scheme.row_variables };
                if (node.tag == .constructor_function) {
                    try require(node.b == 0 and node.c == 0);
                    try proof.validate(constructor.scheme.root, node.ty);
                } else {
                    try require(node.c <= 1);
                    const signature = self.module.types.node(constructor.scheme.root);
                    if (signature.tag == .function) {
                        try proof.validate(signature.b, node.ty);
                        try require(node.b != 0);
                        try self.expression(node.b, depth + 1);
                        const input = if (node.c == 0) constructor.payload else signature.a;
                        try proof.validate(input, self.module.typeOf(node.b));
                    } else {
                        try require(node.b == 0 and node.c == 0 and constructor.payload == 0);
                        try proof.validate(constructor.scheme.root, node.ty);
                    }
                }
            },
            .associated, .result_associated => {
                try self.expression(node.a, depth + 1);
                if (node.tag == .associated) try self.expression(node.b, depth + 1);
                const goal: core.Obligation = .{ .ty = self.module.typeOf(node.a), .other = if (node.tag == .associated) self.module.typeOf(node.b) else 0, .result = node.ty, .signature = self.module.dispatchSignature(source), .kind = if (node.tag == .associated) .dispatch else .result_dispatch, .name = if (node.tag == .associated) node.c else node.b, .operator = if (@backingInt(node.op) <= @backingInt(core.Op.shift_right)) @fromBackingInt(@intCast(@backingInt(node.op))) else .none, .span = self.module.span(source) };
                try require(!try self.openType(goal.ty, depth + 1) and (goal.other == 0 or !try self.openType(goal.other, depth + 1)));
                try require(try self.goalGiven(goal, depth + 1) or try self.closedGoal(goal, depth + 1));
            },
            .scalar, .logical => {
                try require(!try self.openType(node.ty, depth + 1));
                try self.expression(node.a, depth + 1);
                try require(!try self.openType(self.module.typeOf(node.a), depth + 1));
                if (node.b != 0) {
                    try self.expression(node.b, depth + 1);
                    try require(!try self.openType(self.module.typeOf(node.b), depth + 1));
                }
                if (node.tag == .scalar) {
                    try require(node.c == 0);
                    var inputs = [_]T.Id{ self.module.typeOf(node.a), 0 };
                    var count: usize = 1;
                    if (node.b != 0) {
                        inputs[1] = self.module.typeOf(node.b);
                        count = 2;
                    }
                    try self.scalarContract(node.op, inputs[0..count], node.ty);
                } else {
                    try require(node.op == .and_ or node.op == .or_);
                    if (self.module.typeOf(node.a) != T.never) try self.same(T.boolean, self.module.typeOf(node.a));
                    if (self.module.typeOf(node.b) != T.never) try self.same(T.boolean, self.module.typeOf(node.b));
                    try self.same(T.boolean, node.ty);
                }
            },
            .storage => {
                const contract_ = try @import("storage_core.zig").contract(self.module, source);
                for (self.module.children(source)) |argument| try self.expression(argument, depth + 1);
                for (contract_.pairs[0..contract_.len]) |pair| try self.strictSame(pair.expected, pair.actual);
            },
            .array_op => {
                var inputs: [3]T.Id = undefined;
                const arguments_ = self.module.children(source);
                try require(arguments_.len <= inputs.len);
                for (arguments_, 0..) |argument, index| {
                    try self.expression(argument, depth + 1);
                    inputs[index] = self.module.typeOf(argument);
                }
                try self.collectionContract(self.module.arrayOperation(source), inputs[0..arguments_.len], node.ty);
            },
            .constant => {
                try require(node.b == 0 and node.c == 0);
                var literal_type = self.module.types.node(node.ty);
                if (literal_type.tag == .usage) {
                    try require(literal_type.b == @backingInt(T.UsageKind.unique) and literal_type.c == 0);
                    literal_type = self.module.types.node(literal_type.a);
                }
                switch (literal_type.tag) {
                    .u32, .f32 => {},
                    .unit => try require(node.a == 0),
                    .boolean => try require(node.a <= 1),
                    else => return error.InvalidArtifact,
                }
            },
            .primitive_function => {
                const primitive = self.module.primitive(source);
                try require((primitive.kind == .scalar or primitive.kind == .array) and primitive.arity <= 3);
                var inputs: [3]T.Id = undefined;
                var cursor = node.ty;
                for (inputs[0..primitive.arity]) |*input| {
                    const arrow = self.module.types.node(cursor);
                    try require(arrow.tag == .function and self.scopes.isPure(arrow.c));
                    input.* = arrow.a;
                    cursor = arrow.b;
                }
                if (primitive.kind == .scalar) {
                    try self.scalarContract(primitive.op, inputs[0..primitive.arity], cursor);
                } else try self.collectionContract(primitive.array_op, inputs[0..primitive.arity], cursor);
            },
            .effect_reflection => try self.reflection(source, depth + 1),
            .update => try self.update(source, depth + 1),
            .record_merge => try self.recordMerge(source, depth + 1),
            .type_constructor => {
                const token = self.module.types.node(node.ty);
                try require(token.tag == .type_constructor and node.a == 0 and node.b == 0 and node.c == 0);
            },
            .type_same => {
                try self.expression(node.a, depth + 1);
                try self.expression(node.b, depth + 1);
                try self.strictSame(node.ty, T.boolean);
                try self.scopes.representation(self.module.typeOf(node.a));
                try self.scopes.representation(self.module.typeOf(node.b));
            },
            .proof_guard => {
                try require(self.module.types.node(node.ty).tag == .erased_proof);
                try self.expression(node.a, depth + 1);
                try self.expression(node.b, depth + 1);
            },
            .panic => try require(node.ty == T.never),
            else => return error.InvalidArtifact,
        }
    }
};
