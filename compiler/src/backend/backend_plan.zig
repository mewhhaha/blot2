//! Owns one run's admitted code identities, source proof plans and startup
//! storage/order. Keys retain IDs in the caller's live Core/evaluator/layout
//! owners; maps and nested proof arrays are released before those owners.
const std = @import("std");
const core = @import("../check/core.zig");
const wasm = @import("wasm.zig");
const scalar_ops = @import("scalar_ops.zig");
const startup_graph = @import("startup_graph.zig");
const startup_runtime_reach = @import("startup_runtime_reach.zig");
const layout = @import("layout.zig");
const heap = @import("../runtime/runtime_layout.zig");
const function_facts = @import("function_facts.zig");
const runtime_operations = @import("runtime_operations.zig");
const owned_arrays = @import("owned_arrays.zig");
const code_artifacts = @import("../reuse/code_artifacts.zig");
const discarded_bindings = @import("discarded_bindings.zig");
const unit_index = @import("unit_index.zig");
const startup_emission_facts = @import("startup_emission_facts.zig");
const startup_occurrence_flow = @import("startup_occurrence_flow.zig");
const startup_occurrence_plan = @import("startup_occurrence_plan.zig");
const Allocator = std.mem.Allocator;
const Scalar = wasm.Scalar;
const Value = scalar_ops.Value;
const max_parameters = code_artifacts.max_parameters;
const Error = @import("backend_emission.zig").Error;
const Key = code_artifacts.Key;
const CarrierKey = @import("backend_emission.zig").CarrierKey;
const Mapping = layout.Mapping;
const RowMapping = layout.RowMapping;
const ClosureKey = code_artifacts.ClosureKey;
const CapturedTemplate = code_artifacts.CapturedTemplate;
const CallableKey = code_artifacts.CallableKey;
const ConstructorKey = code_artifacts.ConstructorKey;
const PrimitiveKey = code_artifacts.PrimitiveKey;
const OperationKey = code_artifacts.OperationKey;
// Complete source plans allocate all storage first. In an unconfirmed plan,
// `active` retains the original recursive initializer emission guard.
const RuntimeSlot = struct { global: u32, initializer: u32, active: bool = true };
pub const State = struct {
    instances: std.AutoHashMapUnmanaged(Key, u32) = .empty,
    template_results: std.AutoHashMapUnmanaged(Key, u32) = .empty,
    template_catalog: std.ArrayList(CapturedTemplate) = .empty,
    template_instances: std.AutoHashMapUnmanaged(CapturedTemplate, u32) = .empty,
    closures: std.AutoHashMapUnmanaged(ClosureKey, u32) = .empty,
    closure_template_results: std.AutoHashMapUnmanaged(ClosureKey, u32) = .empty,
    callables: std.AutoHashMapUnmanaged(CallableKey, u32) = .empty,
    carrier_adapters: std.AutoHashMapUnmanaged(CarrierKey, u32) = .empty,
    constructor_functions: std.AutoHashMapUnmanaged(ConstructorKey, u32) = .empty,
    primitive_functions: std.AutoHashMapUnmanaged(PrimitiveKey, u32) = .empty,
    operation_functions: std.AutoHashMapUnmanaged(OperationKey, u32) = .empty,
    runtime_operations: runtime_operations.Store,
    host_functions: std.AutoHashMapUnmanaged(code_artifacts.HostKey, u32) = .empty,
    runtime_globals: std.AutoHashMapUnmanaged(core.BindingRef, RuntimeSlot) = .empty,
    runtime_plan_confirmed: bool = false,
    occurrence_plan_active: bool = false,
    occurrence_plan_cells: []const core.BindingRef = &.{},
    startup_facts: startup_emission_facts.Store = .{},
    runtime_order: std.ArrayList(u32) = .empty,
    array_proofs: std.AutoHashMapUnmanaged(u32, owned_arrays.Proof) = .empty,
    numeric_plans: std.AutoHashMapUnmanaged(u32, @import("../check/numeric_proof_core.zig").Plan) = .empty,
    facts: function_facts.Store = .{},
    discard_proofs: std.AutoHashMapUnmanaged(u32, discarded_bindings.Proof) = .empty,
    quantified: std.AutoHashMapUnmanaged(u32, unit_index.Quantified) = .empty,
    /// Heap-owned so a held index outlives later insertions.
    uses: std.AutoHashMapUnmanaged(u32, *unit_index.Uses) = .empty,
    task_movers: std.AutoHashMapUnmanaged(layout.Id, u32) = .empty,
    pub fn init(a: Allocator) State {
        return .{ .runtime_operations = runtime_operations.Store.init(a) };
    }
    pub fn deinit(self: *State, a: Allocator) void {
        self.instances.deinit(a);
        self.template_results.deinit(a);
        self.template_catalog.deinit(a);
        self.template_instances.deinit(a);
        self.closures.deinit(a);
        self.closure_template_results.deinit(a);
        self.callables.deinit(a);
        self.carrier_adapters.deinit(a);
        self.constructor_functions.deinit(a);
        self.primitive_functions.deinit(a);
        self.operation_functions.deinit(a);
        self.runtime_operations.deinit();
        self.host_functions.deinit(a);
        self.runtime_globals.deinit(a);
        self.startup_facts.deinit(a);
        self.runtime_order.deinit(a);
        var proofs = self.array_proofs.valueIterator();
        while (proofs.next()) |proof| proof.deinit(a);
        self.array_proofs.deinit(a);
        var numeric = self.numeric_plans.valueIterator();
        while (numeric.next()) |plan| plan.deinit(a);
        self.numeric_plans.deinit(a);
        self.facts.deinit(a);
        var discarded = self.discard_proofs.valueIterator();
        while (discarded.next()) |proof| proof.deinit(a);
        self.discard_proofs.deinit(a);
        var quantified = self.quantified.valueIterator();
        while (quantified.next()) |set| set.deinit(a);
        self.quantified.deinit(a);
        var uses = self.uses.valueIterator();
        while (uses.next()) |index| {
            index.*.deinit(a);
            a.destroy(index.*);
        }
        self.uses.deinit(a);
        self.task_movers.deinit(a);
    }
    pub fn runtimeGlobal(self: *State, g: anytype, target: core.BindingRef) Error!u32 {
        var scope: ?code_artifacts.Scope = if (g.artifacts) |context| try context.enter(.{ .runtime_global = target }) else null;
        defer if (scope) |*actor| actor.deinit();
        if (self.occurrence_plan_active) {
            const included = for (self.occurrence_plan_cells) |cell| {
                if (std.meta.eql(cell, target)) break true;
            } else false;
            if (!included) return g.decline(target.unit, g.unit(target.unit).binding(target.binding).span, .constant_expression);
        }
        try self.startup_facts.event(g.allocator, .{ .kind = .runtime_global_request, .caller = self.startup_facts.active, .target = if (self.runtime_globals.get(target)) |slot| slot.global else startup_emission_facts.none, .unit = target.unit, .identity = target.binding, .flag = if (self.runtime_globals.get(target)) |slot| slot.active else true });
        if (self.runtime_globals.get(target)) |slot| {
            if (!self.runtime_plan_confirmed and slot.active) return g.decline(target.unit, g.unit(target.unit).binding(target.binding).span, .constant_expression);
            if (scope) |*actor| try actor.hitGlobal(slot.global);
            return slot.global;
        }
        const source = g.unit(target.unit);
        const body = source.body(target.binding) orelse return g.decline(target.unit, source.binding(target.binding).span, .unsupported);
        if (!body.runtime or body.is_function) return g.decline(target.unit, body.span, .unsupported);
        const expected = try g.codeLayout(target.unit, body.scheme.root, &.{}, body.span);
        const scalar_ = g.representations.store.scalar(expected) orelse .pointer;
        const global = try g.module.addGlobal(scalar_, 0, true);
        const initializer = try g.module.addTypedFunction(&.{}, .none, .scalar);
        try self.runtime_globals.put(g.allocator, target, .{ .global = global, .initializer = initializer });
        try self.startup_facts.event(g.allocator, .{ .kind = .cell_registration, .target = global, .unit = target.unit, .identity = target.binding, .auxiliary = initializer });
        // A partial type inquiry cannot license reads of pending storage.
        // Fallback emits recursively, including newly discovered globals.
        if (!self.runtime_plan_confirmed) try self.emitRuntimeInitializer(g, target);
        if (scope) |*actor| try actor.hitGlobal(global);
        return global;
    }
    /// Storage exists for the complete accepted plan before any initializer's
    /// code can recursively emit a helper that reads one of those slots.
    pub fn emitRuntimeInitializer(self: *State, g: anytype, target: core.BindingRef) Error!void {
        const slot = self.runtime_globals.get(target) orelse return error.InvalidGlobalReference;
        if (!slot.active) return;
        var scope: ?code_artifacts.Scope = if (g.artifacts) |context| try context.enter(.{ .runtime_global = target }) else null;
        defer if (scope) |*actor| actor.deinit();
        try self.startup_facts.request(g.allocator, slot.initializer, .runtime_initializer, target.unit, target.binding, false);
        const caller = self.startup_facts.active;
        self.startup_facts.active = slot.initializer;
        defer self.startup_facts.active = caller;
        const source = g.unit(target.unit);
        const body = source.body(target.binding) orelse return error.InvalidGlobalReference;
        var mappings: std.ArrayList(Mapping) = .empty;
        defer mappings.deinit(g.allocator);
        var rows: std.ArrayList(RowMapping) = .empty;
        defer rows.deinit(g.allocator);
        const expected = try g.codeLayout(target.unit, body.scheme.root, &.{}, body.span);
        try g.mapTypeDepth(target.unit, &mappings, &rows, source.binding(target.binding).ty, expected, body.span, 0);
        try g.refineMappings(target.unit, .{ .body = target }, expected, &mappings, &rows, body.span);
        var emitter: @TypeOf(g.*).Emission = .{ .generator = g, .unit_id = target.unit, .function_id = slot.initializer, .mappings = mappings.items, .row_mappings = rows.items };
        defer emitter.deinit();
        try emitter.bodyExpression(body.root, 0, false);
        try emitter.emit(.global_set, slot.global);
        self.runtime_globals.getPtr(target).?.active = false;
        self.startup_facts.complete(slot.initializer);
        try self.runtime_order.append(g.allocator, slot.initializer);
        if (scope) |*actor| try actor.completeGlobal(slot.global);
    }

    pub fn initializeRuntime(self: *State, g: anytype) Error!void {
        var slots = self.runtime_globals.iterator();
        while (slots.next()) |slot| if (slot.value_ptr.active) return error.InvalidGlobalReference;
        if (self.runtime_order.items.len == 0 and g.module.static_fields.items.len == 0) return;
        try g.module.finishStaticFields();
        const start = try g.module.addTypedFunction(&.{}, .none, .scalar);
        for (self.runtime_order.items) |initializer| try g.module.emit(start, .{ .op = .call, .operand = initializer });
        if (g.module.arena) |arena| {
            try g.module.emit(start, .{ .op = .global_get, .operand = arena.heap });
            try g.module.emit(start, .{ .op = .global_set, .operand = arena.base });
        }
        try g.module.setStart(start);
    }

    pub fn codeCount(self: *const State, static_closures: usize) usize {
        return self.instances.count() + self.closures.count() + static_closures;
    }

    pub fn wrapperCount(self: *const State) usize {
        return self.callables.count() + self.constructor_functions.count() + self.primitive_functions.count() + self.operation_functions.count() + self.host_functions.count();
    }

    fn addStartupSelections(g: anytype, target: core.BindingRef, processed: *std.AutoHashMapUnmanaged(core.BindingRef, void), selections: *std.ArrayList(startup_graph.Selection), confirmed: *bool) Error!void {
        var facts = g.evaluator.startupDependencies(target) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.evaluationFailure();
        defer facts.deinit(g.allocator);
        if (!facts.complete) confirmed.* = false;
        for (facts.selected) |method| {
            try selections.append(g.allocator, .{ .source = target, .target = method });
            // Normal source tracing completes ordinary constants needed by the
            // admitted method. Runtime initializers remain unevaluated source.
            g.evaluator.prepare(method) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.evaluationFailure();
        }
        try processed.put(g.allocator, target, {});
    }

    pub fn planRuntime(self: *State, g: anytype, entry: u32, supplied_order: []const u32) Error!void {
        var has_runtime = false;
        for (g.units) |*unit| for (unit.bodies[1..]) |body| {
            if (body.runtime and !body.is_function) has_runtime = true;
        };
        if (!has_runtime) return;
        const order = try g.allocator.alloc(u32, g.units.len);
        defer g.allocator.free(order);
        if (supplied_order.len == 0) {
            for (order, 1..) |*unit, i| unit.* = @intCast(i);
        } else {
            if (supplied_order.len != order.len) return error.InvalidFunctionReference;
            @memcpy(order, supplied_order);
        }
        var selections: std.ArrayList(startup_graph.Selection) = .empty;
        defer selections.deinit(g.allocator);
        var processed: std.AutoHashMapUnmanaged(core.BindingRef, void) = .empty;
        defer processed.deinit(g.allocator);
        var confirmed = true;
        // A declared entry function can select a method that is absent from its
        // syntactic reference list. Retain that admitted target before computing
        // runtime reach. Entry facts select roots; only each reached initializer's
        // own complete proof can certify allocation and emission below.
        for (g.unit(entry).bodies[1..]) |body| {
            if (!body.exported or !body.is_function) continue;
            const target: core.BindingRef = .{ .unit = entry, .binding = body.binding };
            var facts = g.evaluator.startupDependencies(target) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.evaluationFailure();
            defer facts.deinit(g.allocator);
            for (facts.selected) |method| {
                try selections.append(g.allocator, .{ .source = target, .target = method });
                g.evaluator.prepare(method) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.evaluationFailure();
            }
        }
        for (g.units, 1..) |*source, unit_id| for (source.bodies[1..]) |body| {
            if (!body.runtime or body.is_function) continue;
            const target: core.BindingRef = .{ .unit = @intCast(unit_id), .binding = body.binding };
            if (!(g.evaluator.bindingTraced(target) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.evaluationFailure())) continue;
            try addStartupSelections(g, target, &processed, &selections, &confirmed);
        };
        // A newly selected method can reach another runtime initializer. Iterate
        // to closure so no cell receives a certificate from an earlier partial DAG.
        while (true) {
            var declarations = startup_graph.fromCoreWithSelections(g.allocator, g.units, order, selections.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidFunctionReference;
            defer declarations.deinit(g.allocator);
            const selected = try g.allocator.alloc(bool, declarations.nodes.len);
            defer g.allocator.free(selected);
            for (declarations.nodes, selected) |node, *chosen| chosen.* = g.evaluator.bindingTraced(node.target) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.evaluationFailure();
            var reachable = startup_runtime_reach.collect(g.allocator, g.units, &declarations, &g.evaluator, selected, entry) catch |err| return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.Declined, error.RequestUnwind => g.evaluationFailure(),
                error.CoreLimit => g.decline(entry, .{ .start = 0, .end = 0 }, .complexity),
                error.InvalidDependencyGraph => error.InvalidFunctionReference,
            };
            defer reachable.deinit(g.allocator);
            if (reachable.const_only) |origin| return g.fail(origin.unit, origin.node, .backend_const_only);
            var changed = false;
            for (declarations.nodes, reachable.reached) |node, reached| {
                if (!reached or !node.runtime or node.is_function or processed.contains(node.target)) continue;
                try addStartupSelections(g, node.target, &processed, &selections, &confirmed);
                changed = true;
            }
            if (changed) continue;
            // Retained callbacks belong to this Session. Their bodies/captures are
            // covered conservatively, never used as solved source evidence.
            const initializer_roots = try g.allocator.alloc(bool, declarations.nodes.len);
            defer g.allocator.free(initializer_roots);
            for (declarations.nodes, reachable.reached, initializer_roots) |node, reached, *root| root.* = reached and node.runtime and !node.is_function;
            var coverage = startup_runtime_reach.collect(g.allocator, g.units, &declarations, &g.evaluator, initializer_roots, entry) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidFunctionReference;
            defer coverage.deinit(g.allocator);
            for (coverage.callable_values) |value| if (!(g.evaluator.startupCallableComplete(value) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.evaluationFailure())) {
                confirmed = false;
            };
            var occurrence: ?startup_occurrence_flow.Result = null;
            defer if (occurrence) |*facts| facts.deinit(g.allocator);
            var original: ?startup_graph.Graph = null;
            defer if (original) |*graph| graph.deinit(g.allocator);
            if (!confirmed) {
                var roots: std.ArrayList(core.BindingRef) = .empty;
                defer roots.deinit(g.allocator);
                for (declarations.nodes, reachable.reached) |node, reached| if (reached and node.runtime and !node.is_function) try roots.append(g.allocator, node.target);
                if (roots.items.len == 0) return g.decline(entry, .{ .start = 0, .end = 0 }, .constant_expression);
                occurrence = startup_occurrence_flow.collect(g.allocator, g.units, &g.evaluator, roots.items) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.Incomplete => return g.decline(roots.items[0].unit, g.unit(roots.items[0].unit).binding(roots.items[0].binding).span, .constant_expression),
                };
                var discovered = false;
                for (occurrence.?.edges) |edge| {
                    const found = for (declarations.nodes, reachable.reached) |node, reached| {
                        if (std.meta.eql(node.target, edge.target)) break reached;
                    } else false;
                    if (found) continue;
                    g.evaluator.prepare(edge.target) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.evaluationFailure();
                    try selections.append(g.allocator, .{ .source = edge.root, .target = edge.target });
                    discovered = true;
                }
                if (discovered) continue;
                original = startup_graph.fromCore(g.allocator, g.units, order) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidFunctionReference;
            }
            var plan = if (occurrence) |facts|
                startup_occurrence_plan.plan(g.allocator, &original.?, facts.edges, reachable.reached) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidFunctionReference
            else
                startup_graph.Graph.plan(&declarations, g.allocator, reachable.reached) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidFunctionReference;
            defer plan.deinit(g.allocator);
            if (plan.cycle) |target| {
                const point = g.unit(target.unit).runtimeNamePoint(target.binding);
                return g.decline(target.unit, .{ .start = point, .end = point }, .initialization_cycle);
            }
            self.runtime_plan_confirmed = confirmed or occurrence != null;
            self.occurrence_plan_active = occurrence != null;
            self.occurrence_plan_cells = if (occurrence != null) plan.initializers else &.{};
            // Entry emission may discover additional cells through its own method
            // selection. Its on-demand path has no initializer-plan certificate.
            defer self.runtime_plan_confirmed = false;
            defer self.occurrence_plan_active = false;
            defer self.occurrence_plan_cells = &.{};
            for (plan.initializers) |target| _ = try self.runtimeGlobal(g, target);
            if (self.runtime_plan_confirmed) for (plan.initializers) |target| try self.emitRuntimeInitializer(g, target);
            var slots = self.runtime_globals.iterator();
            while (slots.next()) |slot| if (slot.value_ptr.active) return error.InvalidGlobalReference;
            return;
        }
    }
};
