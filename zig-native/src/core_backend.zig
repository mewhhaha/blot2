//! Code instances and compile-time values share immutable typed core bodies.
const std = @import("std");
const core = @import("core.zig");
const types = @import("types.zig");
const wasm = @import("wasm.zig");
const scalar_ops = @import("scalar_ops.zig");
const core_eval = @import("core_eval.zig");
const startup_graph = @import("startup_graph.zig");
const startup_runtime_reach = @import("startup_runtime_reach.zig");
const type_evidence = @import("type_evidence.zig");
const layout_bridge = @import("layout_bridge.zig");
const substitution_keys = @import("substitution_keys.zig");
const provider_chain = @import("provider_chain.zig");
const layout = @import("layout.zig");
const packed_layout = @import("packed_layout.zig");
const runtime_cleanup = @import("runtime_cleanup.zig");
const request_runtime = @import("request_runtime.zig");
const heap = @import("runtime_layout.zig");
const function_facts = @import("function_facts.zig");
const exact_builder = @import("exact_builder.zig");
const runtime_operations = @import("runtime_operations.zig");
const runtime_identity = @import("runtime_identity.zig");
const owned_arrays = @import("owned_arrays.zig");
const artifact_emitter = @import("artifact_emitter.zig");
const code_artifacts = @import("code_artifacts.zig");
const artifact_capture = @import("artifact_capture.zig");
const artifact_fragment = @import("artifact_fragment.zig");
const principal_evidence_reuse = @import("principal_evidence_reuse.zig");
const source_value_template = @import("source_value_template.zig");
const completed_specialization_query = @import("completed_specialization_query.zig");
const shared_query_gate = @import("shared_query_gate.zig");
const discarded_bindings = @import("discarded_bindings.zig");
const startup_emission_facts = @import("startup_emission_facts.zig");
const startup_occurrence_flow = @import("startup_occurrence_flow.zig");
const startup_occurrence_plan = @import("startup_occurrence_plan.zig");
const Allocator = std.mem.Allocator;
const Scalar = wasm.Scalar;
const Value = scalar_ops.Value;
const max_parameters = 16;
pub const Code = @import("diagnostic_code.zig").Code;
pub const Diagnostic = struct {
    unit: u32,
    span: core.Span,
    code: Code,
    detail: []const u8 = &.{},
    pub fn message(self: Diagnostic) []const u8 {
        return self.code.message(self.detail);
    }
};
pub const ArtifactSummary = struct { demands: usize, jobs: usize, functions: usize, helpers: usize, emission_events: usize, metadata_events: usize, operation_symbols: usize, templates: usize, pinned_modules: usize };
pub const Result = struct {
    timing: @import("backend_timing.zig").Stats = .{},
    /// Deterministic work counters for budgets; unlike timing, always recorded.
    counters: @import("work_counters.zig").Counters = .{},
    optimization: function_facts.Stats = .{},
    runtime_optimization: @import("optimized_bodies.zig").Stats = .{},
    module_stamps: struct { computed: usize = 0, reused: usize = 0, comparisons: usize = 0, copied: usize = 0 } = .{},
    refinements: @import("refinement_receipt.zig").Stats = .{},
    completed_queries: completed_specialization_query.Stats = .{},
    artifacts: ?ArtifactSummary = null,
    capture: ?artifact_capture.Capture = null,
    reuse: artifact_fragment.Stats = .{},
    principal: principal_evidence_reuse.Stats = .{},
    bytes: []u8 = &.{},
    diagnostic: ?Diagnostic = null,
    code_instances: usize = 0,
    callable_wrappers: usize = 0,
    emitted_functions: usize = 0,
    constant_steps: usize = 0,
    owned_message: []u8 = &.{},
    startup_observation: ?startup_emission_facts.Snapshot = null,
    pub fn deinit(self: *Result, allocator: Allocator) void {
        allocator.free(self.bytes);
        allocator.free(self.owned_message);
        if (self.capture) |*capture| capture.deinit();
        if (self.startup_observation) |*observation| observation.deinit(allocator);
        self.* = .{};
    }
};
const Error = Allocator.Error || error{ Declined, ModuleTooLarge, InvalidFunctionReference, InvalidGlobalReference };
const Key = code_artifacts.Key;
const Mapping = layout.Mapping;
const RowMapping = layout.RowMapping;
const ClosureKey = code_artifacts.ClosureKey;
const CapturedTemplate = code_artifacts.CapturedTemplate;
const CallableKey = code_artifacts.CallableKey;
const ConstructorKey = code_artifacts.ConstructorKey;
const PrimitiveKey = code_artifacts.PrimitiveKey;
const OperationKey = code_artifacts.OperationKey;
const SerializedKey = struct { value: core_eval.ValueId, ty: layout.Id, suspension: bool = false };
const StaticCodeProjection = struct {
    generator: *Generator,
    mappings: *std.ArrayList(Mapping),
    fn mapping(context: *anyopaque, solver: *types.Store, variable: types.Id, root: types.Id) (types.Error || error{UnresolvedType})!void {
        const self: *@This() = @ptrCast(@alignCast(context));
        for (self.mappings.items) |entry| if (entry.variable == variable and entry.layout != layout.erased) return;
        const concrete = self.generator.layouts.fromSolver(solver, root) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.TypeMismatch => error.TypeMismatch,
            error.UnresolvedType => error.UnresolvedType,
            error.LayoutLimit => error.TypeLimit,
        };
        for (self.mappings.items) |*entry| if (entry.variable == variable) {
            entry.layout = concrete;
            return;
        };
        try self.mappings.append(self.generator.allocator, .{ .variable = variable, .layout = concrete });
    }
};
const specialization = @import("specialization.zig");
const refinement_receipt = @import("refinement_receipt.zig");
const EvidenceRoot = refinement_receipt.Root;
// Complete source plans allocate all storage first. In an unconfirmed plan,
// `active` retains the original recursive initializer emission guard.
const RuntimeSlot = struct { global: u32, initializer: u32, active: bool = true };
const Generator = struct {
    work_timing: @import("backend_timing.zig").Work = .{},
    allocator: Allocator,
    units: []const core.Module,
    artifacts: ?*code_artifacts.Context = null,
    retained: ?*artifact_fragment.State = null,
    principal_state: ?*principal_evidence_reuse.State = null,
    persisted_principals: ?*@import("principal_archive.zig").Reader = null,
    principal_stats: principal_evidence_reuse.Stats = .{},
    query_state: ?*completed_specialization_query.State = null,
    refinement_owner: ?*code_artifacts.Context = null,
    refinement_stats: refinement_receipt.Stats = .{},
    refinement_memo: refinement_receipt.Memo = .{},
    work: artifact_fragment.Stats = .{},
    module: wasm.Module,
    instances: std.AutoHashMapUnmanaged(Key, u32) = .empty,
    template_results: std.AutoHashMapUnmanaged(Key, u32) = .empty,
    evaluator: core_eval.Session,
    layouts: layout.Store,
    representation_bridge: ?layout_bridge.Store = null,
    row_keys: substitution_keys.Store,
    template_keys: substitution_keys.Store,
    static_keys: substitution_keys.Store,
    template_catalog: std.ArrayList(CapturedTemplate) = .empty,
    template_instances: std.AutoHashMapUnmanaged(CapturedTemplate, u32) = .empty,
    serialized: std.AutoHashMapUnmanaged(SerializedKey, u32) = .empty,
    closures: std.AutoHashMapUnmanaged(ClosureKey, u32) = .empty,
    static_closures: std.ArrayList(u32) = .empty,
    closure_template_results: std.AutoHashMapUnmanaged(ClosureKey, u32) = .empty,
    callables: std.AutoHashMapUnmanaged(CallableKey, u32) = .empty,
    constructor_functions: std.AutoHashMapUnmanaged(ConstructorKey, u32) = .empty,
    primitive_functions: std.AutoHashMapUnmanaged(PrimitiveKey, u32) = .empty,
    operation_functions: std.AutoHashMapUnmanaged(OperationKey, u32) = .empty,
    runtime_operations: runtime_operations.Store,
    host_functions: std.AutoHashMapUnmanaged(layout.Id, u32) = .empty,
    runtime_globals: std.AutoHashMapUnmanaged(core.BindingRef, RuntimeSlot) = .empty,
    runtime_plan_confirmed: bool = false,
    occurrence_plan_active: bool = false,
    occurrence_plan_cells: []const core.BindingRef = &.{},
    startup_facts: startup_emission_facts.Store = .{},
    runtime_order: std.ArrayList(u32) = .empty,
    array_proofs: std.AutoHashMapUnmanaged(u32, owned_arrays.Proof) = .empty,
    facts: function_facts.Store = .{},
    discard_proofs: std.AutoHashMapUnmanaged(u32, discarded_bindings.Proof) = .empty,
    request_owner: ?u32 = null,
    diagnostic: ?Diagnostic = null,
    instance_depth: usize = 0,
    fn completedQueryLookup(context: *anyopaque, session: *core_eval.Session, input: u32, expected: u32) Allocator.Error!?u32 {
        const self: *Generator = @ptrCast(@alignCast(context));
        if (session != &self.evaluator) return null;
        if (self.query_state) |state| return state.lookup(self, input, expected);
        return null;
    }
    fn init(allocator: Allocator, units: []const core.Module, journal: ?*artifact_emitter.Recorder) Error!Generator {
        var evaluator = try core_eval.Session.init(allocator, units);
        errdefer evaluator.deinit();
        evaluator.options.trace_runtime_dependencies = true;
        evaluator.options.retain_source_suspensions = true;
        var layouts = layout.Store.init(allocator) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => unreachable,
        };
        errdefer layouts.deinit();
        for (units) |*unit_| layouts.record_names.add(allocator, unit_) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.TypeMismatch => return error.Declined,
        };
        var module = wasm.Module.init(allocator);
        module.artifacts = journal;
        errdefer module.deinit();
        var requests = false;
        for (units) |unit_| requests = requests or unit_.request_loops.len != 0;
        const owner = if (requests) try module.addGlobal(.u32, 0, true) else null;
        return .{ .allocator = allocator, .units = units, .module = module, .request_owner = owner, .evaluator = evaluator, .layouts = layouts, .runtime_operations = runtime_operations.Store.init(allocator), .row_keys = substitution_keys.Store.init(allocator), .template_keys = substitution_keys.Store.init(allocator), .static_keys = substitution_keys.Store.init(allocator) };
    }
    fn principalLookup(context: *anyopaque, target: core.BindingRef, options: core_eval.Options) Allocator.Error!?core_eval.SolvedEvidence {
        const self: *Generator = @ptrCast(@alignCast(context));
        if (self.persisted_principals) |reader| reader.clearInputs();
        if (self.principal_state) |state| {
            if (try state.lookup(self, target, options)) |solved| return solved;
        } else {
            self.principal_stats.requests += 1;
            self.principal_stats.missing += 1;
        }
        if (self.persisted_principals) |reader| return reader.lookup(&self.evaluator, target, options);
        return null;
    }
    fn principalRecord(context: *anyopaque, target: core.BindingRef, options: core_eval.Options, solved: core_eval.SolvedEvidence, inputs: ?*const @import("principal_inputs.zig").Key) Allocator.Error!void {
        const self: *Generator = @ptrCast(@alignCast(context));
        const retained_inputs = if (self.principal_state) |state| state.last_inputs else null;
        const persisted_inputs = if (self.persisted_principals) |reader| if (reader.last_inputs) |*observed| observed else null else null;
        if (self.artifacts) |artifacts| try artifacts.recordPrincipal(target, options, solved, inputs orelse retained_inputs orelse persisted_inputs);
    }
    fn principalStats(self: *const Generator) principal_evidence_reuse.Stats {
        var result = if (self.principal_state) |state| state.stats else self.principal_stats;
        result.fresh_regions = self.evaluator.principal_regions;
        if (self.persisted_principals) |reader| {
            result.persisted_requests = reader.stats.requests;
            result.persisted_hits = reader.stats.hits;
            result.persisted_nonempty_hits = reader.stats.nonempty_hits;
            result.persisted_call_proofs = reader.stats.call_proofs;
            result.persisted_declines = reader.stats.declined;
        }
        if (self.artifacts) |artifacts| result.captured = artifacts.principal_proofs.items.len;
        return result;
    }
    pub fn replayRequest(self: *Generator, request: code_artifacts.Request) Error!u32 {
        return switch (request) {
            .named => |key| self.function(key),
            .closure => |key| self.closureFunction(key),
            .callable => |key| self.callable(key),
            .constructor => |key| self.constructorFunction(key),
            .primitive => |key| self.primitiveFunction(key),
            .operation => |key| self.operationFunction(key),
            .host => |key| self.hostFunction(key),
            .constant, .runtime_global => error.InvalidFunctionReference,
        };
    }
    pub fn replayScalarConstant(self: *Generator, request: code_artifacts.Request) Error!void {
        std.debug.assert(request == .constant);
        _ = try self.constant(request.constant.target, request.constant.ty);
    }
    pub fn publishRetained(self: *Generator, request: code_artifacts.Request, function_id: u32) Error!void {
        switch (request) {
            .named => |key| try self.instances.put(self.allocator, key, function_id),
            .closure => |key| try self.closures.put(self.allocator, key, function_id),
            else => return error.InvalidFunctionReference,
        }
    }
    pub fn publishRetainedStatic(self: *Generator, function_id: u32) Error!void {
        try self.static_closures.append(self.allocator, function_id);
    }
    pub fn publishRetainedResult(self: *Generator, request: code_artifacts.Request, template: ?u32) Error!void {
        if (template) |id| switch (request) {
            .named => |key| try self.template_results.put(self.allocator, key, id),
            .closure => |key| try self.closure_template_results.put(self.allocator, key, id),
            else => return error.InvalidFunctionReference,
        };
    }
    fn representationBridge(self: *Generator) Allocator.Error!*layout_bridge.Store {
        // Bind only after init has returned and the Generator has a stable address.
        if (self.representation_bridge == null) self.representation_bridge = try layout_bridge.Store.init(self.allocator, &self.layouts, &self.evaluator.evidence);
        return &self.representation_bridge.?;
    }
    fn toEvidence(self: *Generator, id: layout.Id) type_evidence.Error!type_evidence.Id {
        return @backingInt(try (try self.representationBridge()).toEvidence(@fromBackingInt(@intCast(id))));
    }
    fn fromEvidence(self: *Generator, id: type_evidence.Id) layout.Error!layout.Id {
        return @backingInt(try (try self.representationBridge()).fromEvidence(@fromBackingInt(@intCast(id))));
    }
    fn rowToEvidence(self: *Generator, id: type_evidence.Effects.Id) type_evidence.Error!type_evidence.Effects.Id {
        return @backingInt(try (try self.representationBridge()).rowToEvidence(@fromBackingInt(@intCast(id))));
    }
    fn rowFromEvidence(self: *Generator, id: type_evidence.Effects.Id) layout.Error!type_evidence.Effects.Id {
        return @backingInt(try (try self.representationBridge()).rowFromEvidence(@fromBackingInt(@intCast(id))));
    }
    fn deinit(self: *Generator) void {
        self.refinement_memo.deinit(self.allocator);
        self.startup_facts.deinit(self.allocator);
        if (self.representation_bridge) |*bridge| bridge.deinit();
        self.module.deinit();
        self.instances.deinit(self.allocator);
        self.template_results.deinit(self.allocator);
        self.evaluator.deinit();
        self.layouts.deinit();
        self.row_keys.deinit();
        self.template_keys.deinit();
        self.static_keys.deinit();
        self.template_catalog.deinit(self.allocator);
        self.template_instances.deinit(self.allocator);
        self.serialized.deinit(self.allocator);
        self.closures.deinit(self.allocator);
        self.static_closures.deinit(self.allocator);
        self.closure_template_results.deinit(self.allocator);
        self.callables.deinit(self.allocator);
        self.constructor_functions.deinit(self.allocator);
        self.primitive_functions.deinit(self.allocator);
        self.operation_functions.deinit(self.allocator);
        self.runtime_operations.deinit();
        self.host_functions.deinit(self.allocator);
        self.runtime_globals.deinit(self.allocator);
        self.runtime_order.deinit(self.allocator);
        var proofs = self.array_proofs.valueIterator();
        while (proofs.next()) |proof| proof.deinit(self.allocator);
        self.array_proofs.deinit(self.allocator);
        self.facts.deinit(self.allocator);
        var discarded = self.discard_proofs.valueIterator();
        while (discarded.next()) |proof| proof.deinit(self.allocator);
        self.discard_proofs.deinit(self.allocator);
    }
    fn unusedAggregate(self: *Generator, unit_id: u32, binding: core.BindingId) Error!bool {
        if (self.discard_proofs.getPtr(unit_id)) |proof| return proof.admits(binding);
        var proof = try discarded_bindings.Proof.init(self.allocator, self.unit(unit_id), unit_id);
        errdefer proof.deinit(self.allocator);
        try self.discard_proofs.put(self.allocator, unit_id, proof);
        return proof.admits(binding);
    }
    fn ownsArrayUpdate(self: *Generator, unit_id: u32, id: core.Id) Error!bool {
        if (self.array_proofs.get(unit_id)) |proof| return proof.admits(id);
        var proof = try owned_arrays.Proof.init(self.allocator, self.units, unit_id);
        errdefer proof.deinit(self.allocator);
        try self.array_proofs.put(self.allocator, unit_id, proof);
        return proof.admits(id);
    }
    fn codeCount(self: *const Generator) usize {
        return self.instances.count() + self.closures.count() + self.static_closures.items.len;
    }
    fn wrapperCount(self: *const Generator) usize {
        return self.callables.count() + self.constructor_functions.count() + self.primitive_functions.count() + self.operation_functions.count() + self.host_functions.count();
    }
    fn unit(self: *const Generator, id: u32) *const core.Module {
        return &self.units[id - 1];
    }
    fn decline(self: *Generator, unit_id: u32, span: core.Span, code: Code) Error {
        if (self.diagnostic == null) self.diagnostic = .{ .unit = unit_id, .span = span, .code = code };
        return error.Declined;
    }
    fn fail(self: *Generator, unit_id: u32, node: core.Id, code: Code) Error {
        return self.decline(unit_id, self.unit(unit_id).span(node), code);
    }
    fn evaluationFailure(self: *Generator) Error {
        if (self.evaluator.diagnostic) |item| {
            // The evaluator's unsupported and cycle failures have no public code of their own.
            const code: Code = switch (item.code) {
                .unsupported, .cycle => .constant_expression,
                else => item.code,
            };
            // Reference panic diagnostics name the constant phase, with no
            // declaration offset. Preserve its detail and producer owner.
            const public_span: core.Span = if (code == .const_panic and !item.tag_origin) .{ .start = 0, .end = 0 } else item.span;
            const result = self.decline(item.unit, public_span, code);
            if (self.diagnostic) |*diagnostic_| diagnostic_.detail = item.detail;
            return result;
        }
        return self.decline(1, .{ .start = 0, .end = 0 }, .constant_expression);
    }
    fn constant(self: *Generator, target: core.BindingRef, ty: layout.Id) Error!Value {
        const timing = self.work_timing.enter(.constants);
        defer timing.deinit();
        var scope: ?code_artifacts.Scope = if (self.artifacts) |context| try context.enter(.{ .constant = .{ .target = target, .ty = ty } }) else null;
        defer if (scope) |*actor| actor.deinit();
        const id = self.evaluator.richValue(target) catch |err| switch (err) {
            error.RequestUnwind => return self.evaluationFailure(),
            error.Declined => return self.evaluationFailure(),
            error.OutOfMemory => return error.OutOfMemory,
        };
        if (self.evaluator.valueScalar(id)) |value| {
            if (scope) |*actor| try actor.completeValue(id, ty);
            return value;
        }
        const bits = try self.serialize(id, ty, 0);
        if (scope) |*actor| try actor.completeValue(id, ty);
        return .{ .scalar = .pointer, .bits = bits };
    }
    fn discardableClosure(self: *Generator, owner: u32, catalog: u32) bool {
        const source = self.unit(owner);
        const metadata = source.closures[catalog];
        if (metadata.qualifier != 0 and source.binding(metadata.qualifier).scheme.obligations.len != 0) return false;
        const body = source.node(metadata.body);
        if (body.tag == .constant or body.tag == .panic) return true;
        if (body.tag != .reference) return false;
        const reference = source.reference(metadata.body);
        return (reference.unit == 0 or reference.unit == owner) and reference.binding == metadata.parameter.binding;
    }
    fn discardableValue(self: *Generator, id: core_eval.ValueId, depth: usize) bool {
        if (depth >= 256) return false;
        const info = self.evaluator.valueInfo(id);
        if (info.kind == .closure) {
            const metadata = self.evaluator.closureInfo(id);
            const source = self.unit(metadata.unit);
            switch (metadata.origin) {
                .named => {
                    const body = source.body(metadata.identity) orelse return false;
                    if (body.scheme.obligations.len != 0) return false;
                },
                .anonymous => if (!self.discardableClosure(metadata.unit, metadata.identity)) return false,
                .constructor, .primitive => {},
                .operation => return false,
            }
        } else switch (info.kind) {
            .scalar, .array, .list, .cursor, .product, .record, .nominal => {},
            else => return false,
        }
        for (self.evaluator.valueChildren(id)) |child| if (!self.discardableValue(child, depth + 1)) return false;
        return true;
    }
    fn dataValueReference(self: *Generator, address: u32, value: core_eval.ValueId, bits: u32) Error!void {
        if (self.evaluator.valueScalar(value) != null or bits == 0) return;
        try self.module.dataReference(address, .{ .role = .static_address, .value = bits });
    }
    fn closureData(self: *Generator, function_id: u32, environment: u32) Error!u32 {
        const address = try self.module.dataObject(heap.Closure{ .function = function_id, .environment = environment });
        try self.module.dataReference(address, .{ .role = .table_function, .value = function_id });
        try self.module.dataReference(address + heap.offset(heap.Closure, "environment"), .{ .role = .static_address, .value = environment });
        return address;
    }
    fn emitValue(self: *Generator, function_id: u32, value: Value) Error!void {
        if (value.scalar == .pointer or value.scalar == .array_u32 or value.scalar == .array_f32) {
            try self.module.emitReference(function_id, .{ .op = .i32_const, .operand = value.bits }, .static_address);
        } else try self.module.emit(function_id, .{ .op = if (value.scalar == .f32) .f32_const else .i32_const, .operand = value.bits });
    }
    fn serialize(self: *Generator, id: core_eval.ValueId, ty: layout.Id, depth: usize) Error!u32 {
        if (self.evaluator.valueScalar(id)) |value| return value.bits;
        const info = self.evaluator.valueInfo(id);
        try self.startup_facts.event(self.allocator, .{ .kind = .retained_value, .caller = self.startup_facts.active, .target = id, .auxiliary = @backingInt(info.kind) });
        if (info.kind == .suspension) if (self.evaluator.suspensionCached(id)) |cached| try self.startup_facts.event(self.allocator, .{ .kind = .cached_demand, .caller = self.startup_facts.active, .target = id, .auxiliary = cached });
        if (info.kind == .type_constructor or info.kind == .resolver) return 0;
        const key: SerializedKey = .{ .value = if (info.kind == .suspension) @intCast(info.nominal) else id, .ty = ty, .suspension = info.kind == .suspension };
        if (self.serialized.get(key)) |address| {
            try self.module.demandResource(.static_data, address, true);
            return address;
        }
        if (depth >= 256) return self.decline(1, .{ .start = 0, .end = 0 }, .complexity);
        if (info.kind == .computation or info.kind == .request_decision) {
            const representation = self.layouts.node(ty);
            if (representation.tag != .nominal or representation.a != std.math.maxInt(u32)) return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
            const arguments = self.layouts.children(ty);
            const children = self.evaluator.valueChildren(id);
            if (info.kind == .computation) {
                if (representation.b != 5 or arguments.len != 1 or children.len != 1) return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
                const action_type = arguments[0];
                const action = children[0];
                const address = try self.serialize(action, action_type, depth + 1);
                try self.serialized.put(self.allocator, key, address);
                return address;
            }
            if (representation.b != 6 or arguments.len != 3 or children.len != 2 or info.bits > @backingInt(core.RequestDecisionKind.break_)) return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
            const kind: core.RequestDecisionKind = @fromBackingInt(@intCast(info.bits));
            const payload_type = if (kind == .reply) arguments[0] else if (kind == .cancel) arguments[2] else 1;
            const state_type = arguments[1];
            const payload = children[0];
            const state = children[1];
            const decision: heap.Decision = .{ .kind = info.bits, .payload = try self.serialize(payload, payload_type, depth + 1), .state = try self.serialize(state, state_type, depth + 1) };
            const address = try self.module.dataObject(decision);
            try self.dataValueReference(address + heap.offset(heap.Decision, "payload"), payload, decision.payload);
            try self.dataValueReference(address + heap.offset(heap.Decision, "state"), state, decision.state);
            try self.serialized.put(self.allocator, key, address);
            return address;
        }
        if (info.kind == .provider or info.kind == .state_provider) {
            const provider_type = self.layouts.node(ty);
            if (info.len != 1) return self.decline(1, .{ .start = 0, .end = 0 }, .constant_expression);
            const child = self.evaluator.valueChildren(id)[0];
            const address = if (info.kind == .provider) ordinary: {
                if (provider_type.tag != .provider) return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
                const actual = self.evaluator.valueEvidence(child);
                if (actual == 0) return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
                const implementation_type = self.fromEvidence(actual) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
                const operation = try self.runtimeOperation(info.bits, 1, .{ .start = 0, .end = 0 });
                const implementation = try self.serialize(child, implementation_type, depth + 1);
                const address = try self.module.dataObject(heap.Provider{ .operation = 0, .implementation = implementation });
                try self.dataValueReference(address + heap.offset(heap.Provider, "implementation"), child, implementation);
                try self.runtimeDataWord(address + heap.offset(heap.Provider, "operation"), operation);
                break :ordinary address;
            } else state: {
                if (provider_type.tag != .state_provider or info.nominal > std.math.maxInt(u32)) return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
                const read = try self.runtimeOperation(info.bits, 1, .{ .start = 0, .end = 0 });
                const write = try self.runtimeOperation(@intCast(info.nominal), 1, .{ .start = 0, .end = 0 });
                const state_value = try self.serialize(child, provider_type.c, depth + 1);
                const address = try self.module.dataObject(heap.StateProvider{ .read = 0, .write = 0, .initial = state_value });
                try self.dataValueReference(address + heap.offset(heap.StateProvider, "initial"), child, state_value);
                try self.runtimeDataWord(address + heap.offset(heap.StateProvider, "read"), read);
                try self.runtimeDataWord(address + heap.offset(heap.StateProvider, "write"), write);
                break :state address;
            };
            try self.serialized.put(self.allocator, key, address);
            return address;
        }
        if (info.kind == .suspension) {
            var selected = ty;
            const expected = self.toEvidence(ty) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.UnresolvedType => inferred: {
                    var budget: usize = 100_000;
                    if (!self.retainedLayoutConcrete(ty, true, 0, &budget)) return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
                    const inferred = self.evaluator.inferSuspension(id) catch |failure| return if (failure == error.OutOfMemory) error.OutOfMemory else self.evaluationFailure();
                    const actual = self.fromEvidence(self.evaluator.valueEvidence(inferred)) catch |failure| return if (failure == error.OutOfMemory) error.OutOfMemory else self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
                    selected = try self.completeRetainedRows(ty, actual, 0);
                    break :inferred self.toEvidence(selected) catch |failure| return if (failure == error.OutOfMemory) error.OutOfMemory else self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
                },
                else => return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type),
            };
            const demanded = self.layouts.node(selected);
            if (demanded.tag != .demand) return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
            const specialized = self.evaluator.specializeSuspension(id, expected) catch |err| switch (err) {
                error.RequestUnwind => return self.evaluationFailure(),
                error.Declined => return self.evaluationFailure(),
                error.OutOfMemory => return error.OutOfMemory,
            };
            const function_type = try self.internLayoutWithEffects(.function, 1, demanded.a, demanded.c, &.{});
            const closure_address = try self.serializeClosure(specialized, function_type, depth);
            const function_id = std.mem.readInt(u32, self.module.data.items[closure_address..][0..4], .little);
            const environment = std.mem.readInt(u32, self.module.data.items[closure_address + heap.offset(heap.Closure, "environment") ..][0..4], .little);
            const cached = self.evaluator.suspensionCached(id);
            const cached_word = if (cached) |value| try self.serialize(value, demanded.a, depth + 1) else 0;
            const address = try self.module.dataObject(heap.Demand{ .function = function_id, .environment = environment, .status = if (cached != null) .ready else .pending, .cached = cached_word });
            try self.module.dataReference(address, .{ .role = .table_function, .value = function_id });
            try self.module.dataReference(address + 4, .{ .role = .static_address, .value = environment });
            if (cached) |value| try self.dataValueReference(address + heap.offset(heap.Demand, "cached"), value, cached_word);
            try self.serialized.put(self.allocator, key, address);
            return address;
        }
        if (info.kind == .closure) {
            var selected = ty;
            // A constant sum/array may contain callbacks whose parameter is
            // unobserved by this consumer. Infer that callback independently;
            // only a concrete source proof can fill its erased interface.
            // Selected types and rows still undergo ordinary specialization.
            const expected = self.toEvidence(ty) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.UnresolvedType => inferred: {
                    const inferred = self.evaluator.inferClosure(id) catch |failure| {
                        if (failure == error.OutOfMemory) return error.OutOfMemory;
                        // A still-generic alias has no concrete representation.
                        // Preserve that boundary's diagnostic when the optional
                        // independent proof cannot fill its erased interface.
                        if (self.evaluator.diagnostic) |diagnostic| if (diagnostic.code == .unsupported) {
                            var budget: usize = 100_000;
                            if (!self.retainedLayoutConcrete(ty, true, 0, &budget)) return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
                        };
                        return self.evaluationFailure();
                    };
                    const actual = self.fromEvidence(self.evaluator.valueEvidence(inferred)) catch |failure| return if (failure == error.OutOfMemory) error.OutOfMemory else self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
                    selected = try self.completeRetainedRows(ty, actual, 0);
                    break :inferred self.toEvidence(selected) catch |failure| return if (failure == error.OutOfMemory) error.OutOfMemory else self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
                },
                else => return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type),
            };
            const specialized = self.evaluator.specializeClosure(id, expected) catch |err| switch (err) {
                error.RequestUnwind => return self.evaluationFailure(),
                error.Declined => return self.evaluationFailure(),
                error.OutOfMemory => return error.OutOfMemory,
            };
            const address = try self.serializeClosure(specialized, selected, depth);
            try self.serialized.put(self.allocator, key, address);
            return address;
        }
        if (info.kind == .cursor) {
            if (info.len != 1 or self.layouts.node(ty).tag != .cursor) return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
            const source = self.evaluator.valueChildren(id)[0];
            const pointer = try self.serialize(source, self.layouts.node(ty).a, depth + 1);
            const address = try self.module.dataObject(heap.Cursor{ .collection = pointer, .index = info.bits });
            try self.dataValueReference(address, source, pointer);
            try self.serialized.put(self.allocator, key, address);
            return address;
        }
        if (info.kind == .array or info.kind == .list) {
            const row_words = packed_layout.collectionRowWords(&self.layouts, ty);
            if (row_words != 0) {
                var words: std.ArrayList(u32) = .empty;
                defer words.deinit(self.allocator);
                if (info.kind == .array) try words.append(self.allocator, info.len);
                const element = self.layouts.node(ty).a;
                const row_tag = self.layouts.node(element).tag;
                const fields = self.layouts.children(element);
                for (self.evaluator.valueChildren(id)) |row| {
                    const values = self.evaluator.valueChildren(row);
                    if (values.len != row_words) return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
                    for (0..row_words) |i| {
                        var slot = i;
                        if (row_tag == .record) {
                            slot = for (self.evaluator.recordFieldNames(row), 0..) |name, index| {
                                if (name == fields[i * 2]) break index;
                            } else return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
                        }
                        const child_type = fields[if (row_tag == .record) i * 2 + 1 else i];
                        // Only scalar children are admitted; serialization cannot
                        // specialize a closure or grow the borrowed layout table.
                        try words.append(self.allocator, try self.serialize(values[slot], child_type, depth + 1));
                    }
                }
                const address = if (info.kind == .array) try self.module.dataWords(words.items) else blk: {
                    const lists = @import("list_runtime.zig");
                    var leaves: std.ArrayList(u32) = .empty;
                    defer leaves.deinit(self.allocator);
                    var offset: usize = 0;
                    while (offset < words.items.len) {
                        const end = @min(words.items.len, offset + lists.capacity);
                        try leaves.append(self.allocator, try lists.staticChunk(&self.module, words.items[offset..end]));
                        offset = end;
                    }
                    break :blk try lists.staticScalarDescriptor(&self.module, @intCast(words.items.len), leaves.items);
                };
                try self.serialized.put(self.allocator, key, address);
                return address;
            }
        }
        var words: std.ArrayList(u32) = .empty;
        defer words.deinit(self.allocator);
        var word_values: std.ArrayList(core_eval.ValueId) = .empty;
        defer word_values.deinit(self.allocator);
        if (info.kind == .effect_set or info.kind == .effect_descriptor) return self.decline(1, .{ .start = 0, .end = 0 }, .backend_const_only);
        if (info.kind == .nominal) {
            const payload = if (info.len == 0) 0 else try self.nominalPayload(info.nominal, info.bits, ty);
            try words.appendSlice(self.allocator, &.{ info.bits, if (info.len == 0) 0 else try self.serialize(self.evaluator.valueChildren(id)[0], payload, depth + 1) });
            try word_values.appendSlice(self.allocator, &.{ 0, if (info.len == 0) 0 else self.evaluator.valueChildren(id)[0] });
        } else {
            if (info.kind == .array) {
                try words.append(self.allocator, info.len);
                try word_values.append(self.allocator, 0);
            }
            const n = self.layouts.node(ty);
            if (info.kind == .record) {
                if (self.evaluator.recordFieldNames(id).len != info.len or self.layouts.children(ty).len != @as(usize, info.len) * 2) return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
                var index: usize = 0;
                // Recursive closure specialization can grow both side tables.
                // Keep stable IDs and reload each slot before descending.
                while (index < info.len) : (index += 1) {
                    const name_ = self.layouts.children(ty)[index * 2];
                    const child_type = self.layouts.children(ty)[index * 2 + 1];
                    var source_slot: ?usize = null;
                    for (self.evaluator.recordFieldNames(id), 0..) |name, slot| if (name == name_) {
                        source_slot = slot;
                        break;
                    };
                    const child = self.evaluator.valueChildren(id)[source_slot orelse return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type)];
                    try words.append(self.allocator, try self.serialize(child, child_type, depth + 1));
                    try word_values.append(self.allocator, child);
                }
            } else for (0..info.len) |index| {
                const child_type = switch (info.kind) {
                    .array, .list => n.a,
                    .product => self.layouts.children(ty)[index],
                    else => unreachable,
                };
                const child = self.evaluator.valueChildren(id)[index];
                try words.append(self.allocator, try self.serialize(child, child_type, depth + 1));
                try word_values.append(self.allocator, child);
            }
        }
        if (info.kind == .list) {
            if (info.len > 0x10000000) return self.decline(1, .{ .start = 0, .end = 0 }, .complexity);
            const lists = @import("list_runtime.zig");
            var leaves: std.ArrayList(u32) = .empty;
            defer leaves.deinit(self.allocator);
            var offset: usize = 0;
            while (offset < words.items.len) {
                const end = @min(words.items.len, offset + lists.capacity);
                const chunk = try lists.staticChunk(&self.module, words.items[offset..end]);
                for (offset..end) |index| try self.dataValueReference(chunk + lists.header + @as(u32, @intCast((index - offset) * 4)), word_values.items[index], words.items[index]);
                try leaves.append(self.allocator, chunk);
                offset = end;
            }
            const address = try lists.staticDescriptor(&self.module, info.len, leaves.items);
            try self.serialized.put(self.allocator, key, address);
            return address;
        }
        const address = if (words.items.len == 0) 0 else try self.module.dataWords(words.items);
        for (word_values.items, words.items, 0..) |value, bits, index| if (value != 0) try self.dataValueReference(address + @as(u32, @intCast(index * 4)), value, bits);
        try self.serialized.put(self.allocator, key, address);
        return address;
    }
    /// Fill unselected slots along a retained demand/function interface.
    /// All selected types and rows remain the consumer's inputs to ordinary
    /// specialization. The proof comes from full body/capture inference.
    fn completeRetainedRows(self: *Generator, requested: layout.Id, actual: layout.Id, depth: usize) Error!layout.Id {
        if (depth >= 128) return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
        if (requested == layout.erased) return actual;
        const wanted = self.layouts.node(requested);
        const proven = self.layouts.node(actual);
        if (wanted.tag != proven.tag) return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
        switch (wanted.tag) {
            .function => return self.internLayoutWithEffects(.function, try self.completeRetainedRows(wanted.a, proven.a, depth + 1), try self.completeRetainedRows(wanted.b, proven.b, depth + 1), if (wanted.c == layout.unknown_row) proven.c else wanted.c, &.{}),
            .demand => return self.internLayoutWithEffects(.demand, try self.completeRetainedRows(wanted.a, proven.a, depth + 1), 0, if (wanted.c == layout.unknown_row) proven.c else wanted.c, &.{}),
            else => return requested,
        }
    }
    /// Row inference cannot replace erased type evidence or opaque aggregate
    /// holes. Reject those at the original conversion boundary before making
    /// a new query, preserving source admission and diagnostic ordering.
    fn retainedLayoutConcrete(self: *const Generator, ty: layout.Id, callable_rows: bool, depth: usize, budget: *usize) bool {
        if (depth >= 128 or budget.* == 0 or ty == 0 or ty >= self.layouts.nodes.items.len) return false;
        budget.* -= 1;
        const node = self.layouts.node(ty);
        switch (node.tag) {
            .invalid, .erased => return false,
            .unit, .boolean, .u32, .f32, .never, .type_constructor => return true,
            .function => return (callable_rows or node.c != layout.unknown_row) and self.retainedLayoutConcrete(node.a, callable_rows, depth + 1, budget) and self.retainedLayoutConcrete(node.b, callable_rows, depth + 1, budget),
            .demand => return (callable_rows or node.c != layout.unknown_row) and self.retainedLayoutConcrete(node.a, callable_rows, depth + 1, budget),
            .array, .list, .cursor, .resolver => return self.retainedLayoutConcrete(node.a, false, depth + 1, budget),
            .provider => return node.c != layout.unknown_row and self.retainedLayoutConcrete(node.a, false, depth + 1, budget),
            .state_provider => return self.retainedLayoutConcrete(node.a, false, depth + 1, budget) and self.retainedLayoutConcrete(node.b, false, depth + 1, budget) and self.retainedLayoutConcrete(node.c, false, depth + 1, budget),
            .product, .nominal => {
                for (self.layouts.children(ty)) |child| if (!self.retainedLayoutConcrete(child, false, depth + 1, budget)) return false;
                return true;
            },
            .record => {
                const children = self.layouts.children(ty);
                for (0..children.len / 2) |i| if (!self.retainedLayoutConcrete(children[i * 2 + 1], false, depth + 1, budget)) return false;
                return true;
            },
        }
    }
    fn nominalPayload(self: *Generator, family: u64, tag: u32, ty: layout.Id) Error!layout.Id {
        const owner: u32 = @intCast(family >> 32);
        const declaration: u32 = @truncate(family);
        const source = self.unit(owner);
        for (source.constructors) |constructor| {
            const nominal = source.nominal(constructor.nominal);
            if (nominal.identity.unit != owner or nominal.identity.decl != declaration or constructor.tag != tag) continue;
            const parameters = source.types.list(nominal.parameters);
            const arguments = self.layouts.children(ty);
            if (parameters.len != arguments.len) return self.decline(owner, .{ .start = 0, .end = 0 }, .unresolved_type);
            var mappings: std.ArrayList(Mapping) = .empty;
            defer mappings.deinit(self.allocator);
            for (parameters, arguments) |parameter, argument| try self.mapType(owner, &mappings, parameter, argument, .{ .start = 0, .end = 0 });
            return self.codeLayout(owner, constructor.payload, mappings.items, .{ .start = 0, .end = 0 });
        }
        return self.decline(owner, .{ .start = 0, .end = 0 }, .unresolved_type);
    }
    fn captureLayout(self: *Generator, owner: u32, binding: core.BindingId, value: core_eval.ValueId, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping)) Error!layout.Id {
        const source = self.unit(owner);
        const declaration = source.binding(binding);
        return self.captureTypeLayout(owner, declaration.ty, declaration.span, value, mappings, rows);
    }
    fn captureTypeLayout(self: *Generator, owner: u32, ty: types.Id, span: core.Span, value: core_eval.ValueId, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping)) Error!layout.Id {
        const source = self.unit(owner);
        if (self.layouts.fromTypeWithRows(source, ty, mappings.items, rows.items, false)) |concrete| return concrete else |err| if (err == error.OutOfMemory) return error.OutOfMemory;
        const actual = self.evaluator.valueEvidence(value);
        if (actual != 0) {
            const concrete = self.fromEvidence(actual) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(owner, span, .unresolved_type);
            try self.mapTypeDepth(owner, mappings, rows, ty, concrete, span, 0);
            return self.codeLayoutWithRows(owner, ty, mappings.items, rows.items, span);
        }
        return self.codeLayoutWithRows(owner, ty, mappings.items, rows.items, span);
    }
    fn serializeClosure(self: *Generator, id: core_eval.ValueId, ty: layout.Id, depth: usize) Error!u32 {
        const metadata = self.evaluator.closureInfo(id);
        const source = self.unit(metadata.unit);
        const child_count = self.evaluator.valueInfo(id).len;
        var child_types: std.ArrayList(layout.Id) = .empty;
        defer child_types.deinit(self.allocator);
        var mappings: std.ArrayList(Mapping) = .empty;
        var rows: std.ArrayList(RowMapping) = .empty;
        defer rows.deinit(self.allocator);
        try self.loadSemanticRows(self.evaluator.row_mappings.items[metadata.row_mappings.start..][0..metadata.row_mappings.len], &rows);
        defer mappings.deinit(self.allocator);
        var function_id: u32 = undefined;
        switch (metadata.origin) {
            .anonymous => {
                const closure_ = source.closures[metadata.identity];
                for (self.evaluator.type_mappings.items[metadata.mappings.start..][0..metadata.mappings.len]) |mapping| {
                    const concrete = self.fromEvidence(mapping.evidence) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.fail(metadata.unit, closure_.body, .unresolved_type);
                    try self.mapType(metadata.unit, &mappings, mapping.variable, concrete, source.span(closure_.body));
                }
                const fn_type = self.layouts.node(ty);
                if (fn_type.tag != .function) return self.fail(metadata.unit, closure_.body, .unresolved_type);
                try self.mapType(metadata.unit, &mappings, closure_.parameter.ty, fn_type.a, closure_.parameter.span);
                try self.mapType(metadata.unit, &mappings, source.typeOf(closure_.body), fn_type.b, source.span(closure_.body));
                const captures = source.extra[closure_.captures.start..][0..closure_.captures.len];
                if (captures.len != child_count) return self.fail(metadata.unit, closure_.body, .constant_expression);
                for (captures, 0..) |binding, index| try child_types.append(self.allocator, try self.captureLayout(metadata.unit, binding, self.evaluator.valueChildren(id)[index], &mappings, &rows));
                for (child_types.items) |capture_type| {
                    var budget: usize = 1_000_000;
                    if (!self.retainedLayoutConcrete(capture_type, false, 0, &budget)) return self.serializeStagedClosure(id, ty);
                }
                // Contextual effect widening preserves the retained implementation's row.
                const implementation_type = if (closure_.function_type == 0) ty else try self.codeLayoutWithRows(metadata.unit, closure_.function_type, mappings.items, rows.items, source.span(closure_.body));
                function_id = try self.closureFunction(.{ .unit = metadata.unit, .catalog = metadata.identity, .ty = implementation_type, .captures = try self.internLayout(.product, 0, 0, child_types.items), .evidence = try self.mappingEvidence(mappings.items), .rows = try self.rowMappingEvidence(rows.items) });
            },
            .constructor => function_id = try self.constructorFunction(.{ .unit = metadata.unit, .catalog = metadata.identity, .ty = ty }),
            .named => return self.serializeNamedClosure(id, ty, depth),
            .primitive => return self.serializePrimitiveClosure(id, ty, depth),
            .operation => {
                if (metadata.applied != 0 or child_count != 0) return self.decline(metadata.unit, .{ .start = 0, .end = 0 }, .unsupported);
                for (self.evaluator.type_mappings.items[metadata.mappings.start..][0..metadata.mappings.len]) |mapping| {
                    const concrete = self.fromEvidence(mapping.evidence) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(metadata.unit, .{ .start = 0, .end = 0 }, .unresolved_type);
                    try self.mapType(metadata.unit, &mappings, mapping.variable, concrete, .{ .start = 0, .end = 0 });
                }
                function_id = try self.operationFunction(.{ .operation = try self.operationToken(metadata.unit, metadata.identity, mappings.items, rows.items, .{ .start = 0, .end = 0 }), .ty = ty });
            },
        }
        var words: std.ArrayList(u32) = .empty;
        defer words.deinit(self.allocator);
        for (child_types.items, 0..) |child_type, index| try words.append(self.allocator, try self.serialize(self.evaluator.valueChildren(id)[index], child_type, depth + 1));
        const environment = if (words.items.len == 0) 0 else try self.module.dataWords(words.items);
        for (words.items, 0..) |bits, slot| try self.dataValueReference(environment + @as(u32, @intCast(slot * 4)), self.evaluator.valueChildren(id)[slot], bits);
        const address = try self.closureData(function_id, environment);
        try self.serialized.put(self.allocator, .{ .value = id, .ty = ty }, address);
        return address;
    }
    /// A closed selected interface can capture generic helpers whose unused
    /// interfaces remain open. Keep the exact live graph while proving and
    /// emitting this invocation, rather than serializing those open helpers.
    fn serializeStagedClosure(self: *Generator, value: core_eval.ValueId, ty: layout.Id) Error!u32 {
        const header = self.evaluator.closureInfo(value);
        const source = self.unit(header.unit);
        const metadata = source.closures[header.identity];
        const bindings = source.extra[metadata.captures.start..][0..metadata.captures.len];
        const captured = try self.allocator.dupe(core_eval.ValueId, self.evaluator.valueChildren(value));
        defer self.allocator.free(captured);
        if (bindings.len != captured.len) return self.fail(header.unit, metadata.body, .unsupported);
        var mappings: std.ArrayList(Mapping) = .empty;
        defer mappings.deinit(self.allocator);
        var rows: std.ArrayList(RowMapping) = .empty;
        defer rows.deinit(self.allocator);
        for (self.evaluator.type_mappings.items[header.mappings.start..][0..header.mappings.len]) |mapping| {
            const concrete = self.fromEvidence(mapping.evidence) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.fail(header.unit, metadata.body, .unresolved_type);
            try self.mapType(header.unit, &mappings, mapping.variable, concrete, source.span(metadata.body));
        }
        try self.loadSemanticRows(self.evaluator.row_mappings.items[header.row_mappings.start..][0..header.row_mappings.len], &rows);
        const arrow = self.layouts.node(ty);
        if (metadata.function_type != 0) {
            try self.mapCapturedFunction(header.unit, metadata.function_type, ty, &mappings, &rows, source.span(metadata.body));
        } else {
            try self.mapType(header.unit, &mappings, metadata.parameter.ty, arrow.a, metadata.parameter.span);
            try self.mapType(header.unit, &mappings, source.typeOf(metadata.body), arrow.b, source.span(metadata.body));
        }
        const hints = try self.allocator.alloc(core_eval.RetainedCapture, captured.len);
        defer self.allocator.free(hints);
        for (bindings, captured, hints) |binding, actual, *hint| hint.* = .{ .binding = binding, .unit = header.unit, .node = 0, .value = actual };
        try self.refineAccessorMappings(header.unit, header.identity, ty, &mappings, &rows, source.span(metadata.body), hints);
        const function_id = try self.capturedClosureFunction(header, ty, captured, mappings.items, rows.items);
        const address = try self.closureData(function_id, 0);
        try self.serialized.put(self.allocator, .{ .value = value, .ty = ty }, address);
        return address;
    }
    /// Private helpers consume exact live captures. Their enclosing artifact
    /// must rebuild; neither a closed semantic receipt nor a portable code key
    /// can represent the partial capture graph.
    fn capturedClosureFunction(self: *Generator, header: core_eval.ClosureValue, ty: layout.Id, captured: []const core_eval.ValueId, mappings: []const Mapping, rows: []const RowMapping) Error!u32 {
        const source = self.unit(header.unit);
        const metadata = source.closures[header.identity];
        const bindings = source.extra[metadata.captures.start..][0..metadata.captures.len];
        if (self.instance_depth >= 256) return self.fail(header.unit, metadata.body, .complexity);
        self.instance_depth += 1;
        defer self.instance_depth -= 1;
        if (self.artifacts) |artifacts| artifacts.requireFreshCode();
        const arrow = self.layouts.node(ty);
        const function_id = try self.module.addFunction(&.{ .i32, self.layouts.machine(arrow.a), .i32 }, self.layouts.machine(arrow.b));
        try self.static_closures.append(self.allocator, function_id);
        self.work.fresh_closures += 1;
        try self.startup_facts.request(self.allocator, function_id, .anonymous, header.unit, header.identity, false);
        const caller = self.startup_facts.active;
        self.startup_facts.active = function_id;
        defer self.startup_facts.active = caller;
        var emitter: Emitter = .{ .generator = self, .unit_id = header.unit, .function_id = function_id, .provider_local = 2, .mappings = mappings, .row_mappings = rows };
        defer emitter.deinit();
        if (metadata.parameter.binding != 0) try emitter.locals.put(self.allocator, metadata.parameter.binding, 1);
        for (bindings, captured) |binding, actual| try emitter.static_values.put(self.allocator, binding, actual);
        try emitter.expression(metadata.body, 0);
        if (source.types.node(source.typeOf(metadata.body)).tag == .never) try emitter.emit(.unreachable_, 0);
        self.startup_facts.complete(function_id);
        return function_id;
    }
    fn serializeNamedClosure(self: *Generator, id: core_eval.ValueId, ty: layout.Id, depth: usize) Error!u32 {
        const metadata = self.evaluator.closureInfo(id);
        const target: core.BindingRef = .{ .unit = metadata.unit, .binding = metadata.identity };
        const source = self.unit(metadata.unit);
        const body = source.body(metadata.identity) orelse return self.decline(metadata.unit, source.binding(metadata.identity).span, .constant_expression);
        const child_count = self.evaluator.valueInfo(id).len;
        if (child_count != metadata.applied or child_count >= body.parameters.len) return self.decline(metadata.unit, body.span, .constant_expression);
        var mappings: std.ArrayList(Mapping) = .empty;
        var rows: std.ArrayList(RowMapping) = .empty;
        defer rows.deinit(self.allocator);
        try self.loadSemanticRows(self.evaluator.row_mappings.items[metadata.row_mappings.start..][0..metadata.row_mappings.len], &rows);
        defer mappings.deinit(self.allocator);
        var types_: std.ArrayList(layout.Id) = .empty;
        defer types_.deinit(self.allocator);
        for (self.evaluator.type_mappings.items[metadata.mappings.start..][0..metadata.mappings.len]) |mapping| {
            const concrete = self.fromEvidence(mapping.evidence) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(metadata.unit, body.span, .unresolved_type);
            try self.mapType(metadata.unit, &mappings, mapping.variable, concrete, body.span);
        }
        var source_ty = source.binding(metadata.identity).ty;
        for (source.bodyParameters(body)[0..child_count], 0..) |parameter, index| {
            const child = self.evaluator.valueChildren(id)[index];
            // Unnamed applied parameters (including Unit patterns) have no
            // lexical BindingId. Their declared type still owns the argument.
            const concrete = try self.captureTypeLayout(metadata.unit, parameter.ty, parameter.span, child, &mappings, &rows);
            try types_.append(self.allocator, concrete);
            const n = source.types.node(source_ty);
            if (n.tag != .function) return self.decline(metadata.unit, body.span, .unresolved_type);
            try self.mapType(metadata.unit, &mappings, n.a, concrete, body.span);
            source_ty = n.b;
        }
        try self.mapType(metadata.unit, &mappings, source_ty, ty, body.span);
        const full_type = try self.codeLayoutWithRows(metadata.unit, source.binding(metadata.identity).ty, mappings.items, rows.items, body.span);
        const function_id = try self.callable(.{ .target = target, .ty = full_type, .applied = metadata.applied });
        var words: std.ArrayList(u32) = .empty;
        defer words.deinit(self.allocator);
        for (types_.items, 0..) |child_type, index| try words.append(self.allocator, try self.serialize(self.evaluator.valueChildren(id)[index], child_type, depth + 1));
        const environment = if (words.items.len == 0) 0 else try self.module.dataWords(words.items);
        for (words.items, 0..) |bits, slot| try self.dataValueReference(environment + @as(u32, @intCast(slot * 4)), self.evaluator.valueChildren(id)[slot], bits);
        const address = try self.closureData(function_id, environment);
        try self.serialized.put(self.allocator, .{ .value = id, .ty = ty }, address);
        return address;
    }
    fn serializePrimitiveClosure(self: *Generator, id: core_eval.ValueId, ty: layout.Id, depth: usize) Error!u32 {
        const metadata = self.evaluator.closureInfo(id);
        const child_count = self.evaluator.valueInfo(id).len;
        const primitive = self.unit(metadata.unit).primitives[metadata.identity];
        if (primitive.kind != .scalar) return self.decline(metadata.unit, .{ .start = 0, .end = 0 }, .constant_expression);
        var full_type = ty;
        var index = child_count;
        while (index != 0) {
            index -= 1;
            const value = self.evaluator.valueScalar(self.evaluator.valueChildren(id)[index]) orelse return self.decline(metadata.unit, .{ .start = 0, .end = 0 }, .unresolved_type);
            const argument: layout.Id = if (value.scalar == .f32) 4 else 3;
            full_type = try self.internLayout(.function, argument, full_type, &.{});
        }
        const function_id = try self.primitiveFunction(.{ .unit = metadata.unit, .catalog = metadata.identity, .ty = full_type, .applied = metadata.applied });
        var words: std.ArrayList(u32) = .empty;
        defer words.deinit(self.allocator);
        var current = full_type;
        for (0..child_count) |child_index| {
            const child = self.evaluator.valueChildren(id)[child_index];
            const n = self.layouts.node(current);
            try words.append(self.allocator, try self.serialize(child, n.a, depth + 1));
            current = n.b;
        }
        const environment = if (words.items.len == 0) 0 else try self.module.dataWords(words.items);
        for (words.items, 0..) |bits, slot| try self.dataValueReference(environment + @as(u32, @intCast(slot * 4)), self.evaluator.valueChildren(id)[slot], bits);
        const address = try self.closureData(function_id, environment);
        try self.serialized.put(self.allocator, .{ .value = id, .ty = ty }, address);
        return address;
    }
    fn normalize(self: *Generator, owner: u32, reference: core.BindingRef) Error!core.BindingRef {
        var target = reference;
        if (target.unit == 0) target.unit = owner;
        for (0..256) |_| {
            if (target.unit == 0 or target.unit > self.units.len or target.binding == 0 or target.binding >= self.unit(target.unit).bindings.len)
                return self.decline(owner, .{ .start = 0, .end = 0 }, .unsupported);
            const binding = self.unit(target.unit).binding(target.binding);
            if (binding.kind == .external) {
                const previous_unit = target.unit;
                target = binding.target;
                if (target.unit == 0) target.unit = previous_unit;
                continue;
            }
            // Named function aliases preserve producer identity/evidence.
            if (self.unit(target.unit).body(target.binding)) |body| {
                if (self.unit(target.unit).types.node(binding.ty).tag == .function and body.parameters.len == 0 and self.unit(target.unit).node(body.root).tag == .reference) {
                    const previous_unit = target.unit;
                    target = self.unit(previous_unit).reference(body.root);
                    if (target.unit == 0) target.unit = previous_unit;
                    continue;
                }
            }
            return target;
        }
        return self.decline(owner, .{ .start = 0, .end = 0 }, .complexity);
    }
    fn scalar(self: *Generator, unit_id: u32, ty: types.Id, mappings: []const Mapping, span: core.Span) Error!Scalar {
        return self.layouts.scalar(try self.codeLayout(unit_id, ty, mappings, span)) orelse .pointer;
    }
    fn typeLayout(self: *Generator, unit_id: u32, ty: types.Id, mappings: []const Mapping, span: core.Span) Error!layout.Id {
        return self.layouts.fromType(self.unit(unit_id), ty, mappings) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => self.decline(unit_id, span, .unresolved_type),
        };
    }
    fn codeLayout(self: *Generator, unit_id: u32, ty: types.Id, mappings: []const Mapping, span: core.Span) Error!layout.Id {
        return self.layouts.fromTypePartial(self.unit(unit_id), ty, mappings) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => self.decline(unit_id, span, .unresolved_type),
        };
    }
    fn internLayout(self: *Generator, tag: layout.Tag, a: u32, b: u32, values: []const u32) Error!layout.Id {
        return (if (tag == .record) self.layouts.internRecord(values) else self.layouts.intern(tag, a, b, values)) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => self.decline(1, .{ .start = 0, .end = 0 }, .complexity),
        };
    }
    fn internLayoutWithEffects(self: *Generator, tag: layout.Tag, a: u32, b: u32, row: u32, values: []const u32) Error!layout.Id {
        return self.layouts.internWithEffects(tag, a, b, row, values) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(1, .{ .start = 0, .end = 0 }, .complexity);
    }
    fn codeLayoutWithRows(self: *Generator, unit_id: u32, ty: types.Id, mappings: []const Mapping, rows: []const RowMapping, span: core.Span) Error!layout.Id {
        const timing = self.work_timing.enter(.layouts);
        defer timing.deinit();
        return self.layouts.fromTypeWithRows(self.unit(unit_id), ty, mappings, rows, true) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
    }
    fn associatedTarget(self: *Generator, origin: u32, identity: types.NominalIdentity, member: u32, op: types.Operator) Error!?core.BindingRef {
        return self.evaluator.associatedTarget(origin, identity, member, op) catch |err| switch (err) {
            error.RequestUnwind => return self.evaluationFailure(),
            error.Declined => self.evaluationFailure(),
            error.OutOfMemory => error.OutOfMemory,
        };
    }
    fn scalarWithRows(self: *Generator, unit_id: u32, ty: types.Id, mappings: []const Mapping, rows: []const RowMapping, span: core.Span) Error!Scalar {
        return self.layouts.scalar(try self.codeLayoutWithRows(unit_id, ty, mappings, rows, span)) orelse .pointer;
    }
    fn entrySignature(self: *Generator, target: core.BindingRef, ty: types.Id, span: core.Span) Error!Key {
        if (self.layouts.fromType(self.unit(target.unit), ty, &.{})) |_| {
            return self.signature(target, ty, target.unit, &.{}, &.{}, span, true);
        } else |err| if (err == error.OutOfMemory) return error.OutOfMemory;
        const value = self.evaluator.richValue(target) catch |err| switch (err) {
            error.RequestUnwind => return self.evaluationFailure(),
            error.Declined => return self.evaluationFailure(),
            error.OutOfMemory => return error.OutOfMemory,
        };
        const inferred = self.evaluator.inferEntryClosure(value) catch |err| switch (err) {
            error.RequestUnwind => return self.evaluationFailure(),
            error.Declined => {
                if (self.evaluator.diagnostic) |diagnostic_| if (diagnostic_.code == .unsupported) return self.decline(target.unit, span, .unresolved_type);
                return self.evaluationFailure();
            },
            error.OutOfMemory => return error.OutOfMemory,
        } orelse return self.decline(target.unit, span, .entry_type);
        const concrete = self.fromEvidence(self.evaluator.valueEvidence(inferred)) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(target.unit, span, .unresolved_type);
        var mappings: std.ArrayList(Mapping) = .empty;
        defer mappings.deinit(self.allocator);
        var rows: std.ArrayList(RowMapping) = .empty;
        defer rows.deinit(self.allocator);
        // An alias may retain a closure from another owner. Map its complete
        // semantic proof back to the exported source interface before ABI checks.
        try self.mapTypeDepth(target.unit, &mappings, &rows, ty, concrete, span, 0);
        _ = self.layouts.fromTypeWithRows(self.unit(target.unit), ty, mappings.items, rows.items, false) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(target.unit, span, .unresolved_type);
        return self.signature(target, ty, target.unit, mappings.items, rows.items, span, false);
    }
    fn signature(self: *Generator, target: core.BindingRef, ty: types.Id, source: u32, mappings: []const Mapping, rows: []const RowMapping, span: core.Span, complete: bool) Error!Key {
        var key: Key = .{ .target = try self.normalize(source, target) };
        var current = ty;
        const producer = self.unit(key.target.unit).body(key.target.binding);
        const limit: usize = if (producer) |body| if (body.parameters.len == 0) max_parameters else body.parameters.len else max_parameters;
        while (self.unit(source).types.node(current).tag == .function and key.count < limit) {
            if (key.count == max_parameters) return self.decline(source, span, .complexity);
            const n = self.unit(source).types.node(current);
            key.parameters[key.count] = if (complete) try self.typeLayout(source, n.a, mappings, span) else try self.codeLayoutWithRows(source, n.a, mappings, rows, span);
            key.effects[key.count] = self.layouts.rowFromType(self.unit(source), n.c, mappings, rows, !complete) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(source, span, .unresolved_type);
            key.count += 1;
            current = n.b;
        }
        key.result = if (complete) try self.typeLayout(source, current, mappings, span) else try self.codeLayoutWithRows(source, current, mappings, rows, span);
        return key;
    }
    fn specializer(self: *Generator) Allocator.Error!specialization.Service {
        return .{ .timing = &self.work_timing, .allocator = self.allocator, .units = self.units, .evaluator = &self.evaluator, .layouts = &self.layouts, .bridge = try self.representationBridge(), .refinement_stats = &self.refinement_stats, .refinement_regions = &self.work.refinement_regions, .cache = .{ .context = self, .lookup = lookupRefinement, .record = recordRefinement } };
    }
    fn lookupRefinement(context: *anyopaque, root: EvidenceRoot, shape: @import("code_expectation.zig").View, expected: u32, seeds: []const type_evidence.Mapping, rows: []const type_evidence.RowMapping) Allocator.Error!?core_eval.SolvedEvidence {
        const self: *Generator = @ptrCast(@alignCast(context));
        if (try self.refinement_memo.lookup(self, root, expected, seeds, rows)) |result| return result;
        return refinement_receipt.lookup(self, root, shape, expected, seeds, rows);
    }
    fn recordRefinement(context: *anyopaque, record: specialization.Record) Allocator.Error!void {
        const self: *Generator = @ptrCast(@alignCast(context));
        return refinement_receipt.record(self, record.root, record.expected, record.seeds, record.rows, record.result, record.tape, record.observed, record.before_values, record.before_children, record.before_steps);
    }
    fn specializationFailure(self: *Generator, service: specialization.Service, err: specialization.Error) Error {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        const failure = service.failure.?;
        return switch (failure.code) {
            .evaluation => self.evaluationFailure(),
            .complexity => self.decline(failure.unit, failure.span, .complexity),
            .unresolved_type => self.decline(failure.unit, failure.span, .unresolved_type),
        };
    }
    fn mapType(self: *Generator, unit_id: u32, mappings: *std.ArrayList(Mapping), ty: types.Id, concrete: layout.Id, span: core.Span) Error!void {
        var service = try self.specializer();
        service.mapType(unit_id, mappings, ty, concrete, span) catch |err| return self.specializationFailure(service, err);
    }
    fn mapTypeDepth(self: *Generator, unit_id: u32, mappings: *std.ArrayList(Mapping), rows: ?*std.ArrayList(RowMapping), ty: types.Id, concrete: layout.Id, span: core.Span, depth: usize) Error!void {
        var service = try self.specializer();
        service.mapTypeDepth(unit_id, mappings, rows, ty, concrete, span, depth) catch |err| return self.specializationFailure(service, err);
    }
    fn mapRow(self: *Generator, unit_id: u32, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), source_row: types.Effects.Id, actual_row: u32, span: core.Span, covariant: bool) Error!void {
        var service = try self.specializer();
        service.mapRow(unit_id, mappings, rows, source_row, actual_row, span, covariant) catch |err| return self.specializationFailure(service, err);
    }
    fn refineMappings(self: *Generator, unit_id: u32, root: EvidenceRoot, expected: layout.Id, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), span: core.Span) Error!void {
        var service = try self.specializer();
        service.refineMappings(unit_id, root, expected, mappings, rows, span) catch |err| return self.specializationFailure(service, err);
    }
    fn refineMappingsCaptures(self: *Generator, unit_id: u32, root: EvidenceRoot, expected: layout.Id, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), span: core.Span, captures: []const core_eval.RetainedCapture) Error!void {
        var service = try self.specializer();
        service.refineMappingsCaptures(unit_id, root, expected, mappings, rows, span, captures) catch |err| return self.specializationFailure(service, err);
    }
    fn refineAccessorMappings(self: *Generator, unit_id: u32, catalog: u32, expected: layout.Id, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), span: core.Span, captures: []const core_eval.RetainedCapture) Error!void {
        var projection: StaticCodeProjection = .{ .generator = self, .mappings = mappings };
        var service = try self.specializer();
        service.code_projection = .{ .context = &projection, .mapping = StaticCodeProjection.mapping };
        service.refineMappingsCaptures(unit_id, .{ .closure = .{ .unit = unit_id, .catalog = catalog } }, expected, mappings, rows, span, captures) catch |err| return self.specializationFailure(service, err);
    }
    fn mapCapturedFunction(self: *Generator, unit_id: u32, function_type: types.Id, expected: layout.Id, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), span: core.Span) Error!void {
        const source = self.unit(unit_id).types.node(function_type);
        const actual = self.layouts.node(expected);
        if (source.tag != .function or actual.tag != .function) return self.decline(unit_id, span, .unresolved_type);
        try self.mapTypeDepth(unit_id, mappings, rows, source.a, actual.a, span, 0);
        try self.mapTypeDepth(unit_id, mappings, rows, source.b, actual.b, span, 0);
        // A pure implementation can run under its caller's larger ambient
        // effect row. Parameter and result rows keep exact checking above.
        try self.mapRow(unit_id, mappings, rows, source.c, actual.c, span, true);
    }
    fn findRetained(self: *Generator, retained: *artifact_fragment.State, request: code_artifacts.Request) Allocator.Error!?u32 {
        const timing = self.work_timing.enter(.lookup);
        defer timing.deinit();
        return retained.find(self, request);
    }
    fn reconstructRetained(self: *Generator, retained: *artifact_fragment.State, id: u32, request: code_artifacts.Request, scope: ?*code_artifacts.Scope) Error!u32 {
        const timing = self.work_timing.enter(.replay);
        defer timing.deinit();
        return retained.reconstruct(self, id, request, scope);
    }
    fn function(self: *Generator, key: Key) Error!u32 {
        var scope: ?code_artifacts.Scope = if (self.artifacts) |context| try context.enter(.{ .named = key }) else null;
        defer if (scope) |*actor| actor.deinit();
        if (self.instances.get(key)) |existing| {
            try self.startup_facts.request(self.allocator, existing, .named, key.target.unit, key.target.binding, true);
            if (scope) |*actor| try actor.hit(existing);
            return existing;
        }
        if (self.retained) |retained| if (try self.findRetained(retained, .{ .named = key })) |job| {
            const function_id = try self.reconstructRetained(retained, job, .{ .named = key }, if (scope) |*actor| actor else null);
            try self.startup_facts.request(self.allocator, function_id, .named, key.target.unit, key.target.binding, true);
            self.startup_facts.complete(function_id);
            return function_id;
        };
        self.work.fresh_named += 1;
        const unit_id = key.target.unit;
        const source = self.unit(unit_id);
        const body = source.body(key.target.binding) orelse return self.decline(unit_id, source.binding(key.target.binding).span, .unsupported);
        if (body.is_function and body.parameters.len != key.count) return self.decline(unit_id, body.span, .unsupported);
        if (self.instance_depth >= 256 or self.instances.count() >= 65536) return self.decline(unit_id, body.span, .complexity);
        self.instance_depth += 1;
        defer self.instance_depth -= 1;
        var parameters: [max_parameters + 1]wasm.ValueType = undefined;
        for (key.parameters[0..key.count], 0..) |item, i| parameters[i] = self.layouts.machine(item);
        parameters[key.count] = .i32;
        const function_id = try self.module.addFunction(parameters[0 .. key.count + 1], self.layouts.machine(key.result));
        try self.instances.put(self.allocator, key, function_id);
        if (scope) |*actor| try actor.reserve(function_id);
        try self.startup_facts.request(self.allocator, function_id, .named, unit_id, key.target.binding, false);
        const caller = self.startup_facts.active;
        self.startup_facts.active = function_id;
        defer self.startup_facts.active = caller;
        if (!body.is_function) {
            var full = key.result;
            var reverse: usize = key.count;
            while (reverse > 0) {
                reverse -= 1;
                full = try self.internLayoutWithEffects(.function, key.parameters[reverse], full, key.effects[reverse], &.{});
            }
            for (source.obligations[body.scheme.obligations.start..][0..body.scheme.obligations.len]) |obligation| if (obligation.explicit) {
                var mappings: std.ArrayList(Mapping) = .empty;
                var rows: std.ArrayList(RowMapping) = .empty;
                defer mappings.deinit(self.allocator);
                defer rows.deinit(self.allocator);
                try self.refineMappings(unit_id, .{ .body = key.target }, full, &mappings, &rows, body.span);
                break;
            };
            const global = if (body.runtime) try self.runtimeGlobal(key.target) else null;
            const constant_ = if (global == null) try self.constant(key.target, full) else null;
            const callee = try self.module.addLocal(function_id, .i32);
            if (global) |index| try self.module.emit(function_id, .{ .op = .global_get, .operand = index }) else try self.emitValue(function_id, constant_.?);
            var ty_ = full;
            for (0..key.count) |index| {
                const arrow = self.layouts.node(ty_);
                if (arrow.tag != .function) return self.decline(unit_id, body.span, .unresolved_type);
                for ([_]wasm.Instruction{
                    .{ .op = .local_set, .operand = callee },
                    .{ .op = .local_get, .operand = callee },
                    .{ .op = .i32_load, .operand = 4 },
                    .{ .op = .local_get, .operand = @intCast(index) },
                    .{ .op = .local_get, .operand = key.count },
                    .{ .op = .local_get, .operand = callee },
                    .{ .op = .i32_load },
                    .{ .op = .call_indirect, .operand = try self.module.internType(&.{ .i32, self.layouts.machine(arrow.a), .i32 }, self.layouts.machine(arrow.b)) },
                }) |instruction| {
                    try self.module.emit(function_id, instruction);
                    if (instruction.op == .call_indirect) if (self.request_owner) |owner| try request_runtime.guard(&self.module, function_id, owner, &.{});
                }
                ty_ = arrow.b;
            }
            // addFunction owns a copied signature; only a numeric handle escapes.
            if (scope) |*actor| try actor.complete(function_id, self.template_results.get(key));
            self.startup_facts.complete(function_id);
            // zig-analyzer: disable-next-line returning-local-slice
            return function_id;
        }
        var service = try self.specializer();
        var resolved = service.named(key) catch |err| return self.specializationFailure(service, err);
        defer resolved.deinit(self.allocator);
        const emitter = try self.allocator.create(Emitter);
        emitter.* = .{ .generator = self, .unit_id = unit_id, .function_id = function_id, .provider_local = key.count, .mappings = resolved.mappings.items, .row_mappings = resolved.rows.items, .factory_template = key.template_result };
        defer {
            emitter.deinit();
            self.allocator.destroy(emitter);
        }
        for (source.bodyParameters(body), 0..) |parameter, index| if (parameter.binding != 0) {
            if (self.capturedTemplate(key.templates, parameter.binding)) |template| {
                try emitter.templates.put(self.allocator, parameter.binding, .{ .unit = template.unit, .node = template.node, .environment = if (template.has_environment) @intCast(index) else null, .captures = template.captures, .templates = template.templates, .computation = template.computation, .evidence = template.evidence, .rows = template.rows });
            } else try emitter.locals.put(self.allocator, parameter.binding, @intCast(index));
        };
        if (key.template_result) {
            try emitter.templateExpression(@backingInt(resolved.root), 0);
            const template = emitter.result_template orelse return self.fail(unit_id, body.root, .unresolved_type);
            try self.template_results.put(self.allocator, key, template);
        } else {
            try emitter.expression(@backingInt(resolved.root), 0);
            if (source.types.node(source.typeOf(body.root)).tag == .never) try emitter.emit(.unreachable_, 0);
        }
        if (scope) |*actor| try actor.solved(resolved.mappings.items, resolved.rows.items, self.template_keys.get(key.templates));
        // addFunction copied parameters into an owned signature; only its ID escapes.
        if (scope) |*actor| try actor.complete(function_id, self.template_results.get(key));
        self.startup_facts.complete(function_id);
        // zig-analyzer: disable-next-line returning-local-slice
        return function_id;
    }
    fn runtimeGlobal(self: *Generator, target: core.BindingRef) Error!u32 {
        var scope: ?code_artifacts.Scope = if (self.artifacts) |context| try context.enter(.{ .runtime_global = target }) else null;
        defer if (scope) |*actor| actor.deinit();
        if (self.occurrence_plan_active) {
            const included = for (self.occurrence_plan_cells) |cell| {
                if (std.meta.eql(cell, target)) break true;
            } else false;
            if (!included) return self.decline(target.unit, self.unit(target.unit).binding(target.binding).span, .constant_expression);
        }
        try self.startup_facts.event(self.allocator, .{ .kind = .runtime_global_request, .caller = self.startup_facts.active, .target = if (self.runtime_globals.get(target)) |slot| slot.global else startup_emission_facts.none, .unit = target.unit, .identity = target.binding, .flag = if (self.runtime_globals.get(target)) |slot| slot.active else true });
        if (self.runtime_globals.get(target)) |slot| {
            if (!self.runtime_plan_confirmed and slot.active) return self.decline(target.unit, self.unit(target.unit).binding(target.binding).span, .constant_expression);
            if (scope) |*actor| try actor.hitGlobal(slot.global);
            return slot.global;
        }
        const source = self.unit(target.unit);
        const body = source.body(target.binding) orelse return self.decline(target.unit, source.binding(target.binding).span, .unsupported);
        if (!body.runtime or body.is_function) return self.decline(target.unit, body.span, .unsupported);
        const expected = try self.codeLayout(target.unit, body.scheme.root, &.{}, body.span);
        const scalar_ = self.layouts.scalar(expected) orelse .pointer;
        const global = try self.module.addGlobal(scalar_, 0, true);
        const initializer = try self.module.addFunction(&.{}, .none);
        try self.runtime_globals.put(self.allocator, target, .{ .global = global, .initializer = initializer });
        try self.startup_facts.event(self.allocator, .{ .kind = .cell_registration, .target = global, .unit = target.unit, .identity = target.binding, .auxiliary = initializer });
        // A partial type inquiry cannot license reads of pending storage.
        // Fallback emits recursively, including newly discovered globals.
        if (!self.runtime_plan_confirmed) try self.emitRuntimeInitializer(target);
        if (scope) |*actor| try actor.hitGlobal(global);
        return global;
    }
    /// Storage exists for the complete accepted plan before any initializer's
    /// code can recursively emit a helper that reads one of those slots.
    fn emitRuntimeInitializer(self: *Generator, target: core.BindingRef) Error!void {
        const slot = self.runtime_globals.get(target) orelse return error.InvalidGlobalReference;
        if (!slot.active) return;
        var scope: ?code_artifacts.Scope = if (self.artifacts) |context| try context.enter(.{ .runtime_global = target }) else null;
        defer if (scope) |*actor| actor.deinit();
        try self.startup_facts.request(self.allocator, slot.initializer, .runtime_initializer, target.unit, target.binding, false);
        const caller = self.startup_facts.active;
        self.startup_facts.active = slot.initializer;
        defer self.startup_facts.active = caller;
        const source = self.unit(target.unit);
        const body = source.body(target.binding) orelse return error.InvalidGlobalReference;
        var mappings: std.ArrayList(Mapping) = .empty;
        defer mappings.deinit(self.allocator);
        var rows: std.ArrayList(RowMapping) = .empty;
        defer rows.deinit(self.allocator);
        const expected = try self.codeLayout(target.unit, body.scheme.root, &.{}, body.span);
        try self.mapTypeDepth(target.unit, &mappings, &rows, source.binding(target.binding).ty, expected, body.span, 0);
        try self.refineMappings(target.unit, .{ .body = target }, expected, &mappings, &rows, body.span);
        var emitter: Emitter = .{ .generator = self, .unit_id = target.unit, .function_id = slot.initializer, .mappings = mappings.items, .row_mappings = rows.items };
        defer emitter.deinit();
        try emitter.expression(body.root, 0);
        try emitter.emit(.global_set, slot.global);
        self.runtime_globals.getPtr(target).?.active = false;
        self.startup_facts.complete(slot.initializer);
        try self.runtime_order.append(self.allocator, slot.initializer);
        if (scope) |*actor| try actor.completeGlobal(slot.global);
    }
    fn initializeRuntime(self: *Generator) Error!void {
        var slots = self.runtime_globals.iterator();
        while (slots.next()) |slot| if (slot.value_ptr.active) return error.InvalidGlobalReference;
        if (self.runtime_order.items.len == 0) return;
        const start = try self.module.addFunction(&.{}, .none);
        for (self.runtime_order.items) |initializer| try self.module.emit(start, .{ .op = .call, .operand = initializer });
        if (self.module.arena) |arena| {
            try self.module.emit(start, .{ .op = .global_get, .operand = arena.heap });
            try self.module.emit(start, .{ .op = .global_set, .operand = arena.base });
        }
        try self.module.setStart(start);
    }
    fn mappingEvidence(self: *Generator, mappings: []const Mapping) Error!u32 {
        var words: std.ArrayList(u32) = .empty;
        defer words.deinit(self.allocator);
        for (mappings) |mapping| {
            const actual = self.toEvidence(mapping.layout) catch |err| switch (err) {
                error.UnresolvedType => continue,
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type),
            };
            try words.appendSlice(self.allocator, &.{ mapping.variable, actual });
        }
        // Semantic record interning canonicalizes variable order and checks
        // equality after hash collisions. Its owner is the evaluation session.
        return self.evaluator.evidence.intern(.record, 0, 0, words.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
    }
    fn rowMappingEvidence(self: *Generator, rows: []const RowMapping) Error!substitution_keys.Id {
        var entries: std.ArrayList(substitution_keys.Entry) = .empty;
        defer entries.deinit(self.allocator);
        for (rows) |mapping| {
            if (mapping.row == layout.unknown_row) continue;
            const actual = self.rowToEvidence(mapping.row) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
            try entries.append(self.allocator, .{ .variable = mapping.variable, .value = actual });
        }
        return self.row_keys.intern(entries.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
    }
    fn loadSemanticRows(self: *Generator, mappings: []const type_evidence.RowMapping, rows: *std.ArrayList(RowMapping)) Error!void {
        for (mappings) |mapping| {
            const concrete = self.rowFromEvidence(mapping.evidence) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
            try rows.append(self.allocator, .{ .variable = mapping.variable, .row = concrete });
        }
    }
    fn captureTemplate(self: *Generator, template: Template) Error!u32 {
        const retained: CapturedTemplate = .{ .unit = template.unit, .node = template.node, .captures = template.captures, .templates = template.templates, .has_environment = template.environment != null, .computation = template.computation, .evidence = template.evidence, .rows = template.rows };
        if (self.template_instances.get(retained)) |existing| return existing;
        if (self.template_catalog.items.len >= std.math.maxInt(u32)) return error.ModuleTooLarge;
        const id: u32 = @intCast(self.template_catalog.items.len + 1);
        try self.template_catalog.append(self.allocator, retained);
        try self.template_instances.put(self.allocator, retained, id);
        return id;
    }
    fn capturedTemplate(self: *Generator, key: substitution_keys.Id, binding: core.BindingId) ?CapturedTemplate {
        for (self.template_keys.get(key)) |entry| if (entry.variable == binding) return self.template_catalog.items[entry.value - 1];
        return null;
    }
    fn capturedStatic(self: *Generator, key: substitution_keys.Id, binding: core.BindingId) ?core_eval.ValueId {
        for (self.static_keys.get(key)) |entry| if (entry.variable == binding) return entry.value;
        return null;
    }
    fn retainedCapture(self: *Generator, allocator: Allocator, binding: core.BindingId, template: CapturedTemplate, depth: usize) Error!core_eval.RetainedCapture {
        if (depth >= 256) return self.fail(template.unit, template.node, .complexity);
        var rows: std.ArrayList(type_evidence.RowMapping) = .empty;
        errdefer rows.deinit(allocator);
        for (self.row_keys.get(template.rows)) |row| try rows.append(allocator, .{ .variable = row.variable, .evidence = row.value });
        var children: std.ArrayList(core_eval.RetainedCapture) = .empty;
        errdefer children.deinit(allocator);
        var values: std.ArrayList(core_eval.RetainedValue) = .empty;
        errdefer values.deinit(allocator);
        const source = self.unit(template.unit);
        const node = source.node(template.node);
        if (node.tag == .closure or node.tag == .suspend_) {
            const capture_list = source.extra[source.closures[node.a].captures.start..][0..source.closures[node.a].captures.len];
            for (capture_list, 0..) |captured, index| {
                if (self.capturedTemplate(template.templates, captured)) |child| {
                    try children.append(allocator, try self.retainedCapture(allocator, captured, child, depth + 1));
                } else if (index < self.layouts.children(template.captures).len) {
                    const actual = self.toEvidence(self.layouts.children(template.captures)[index]) catch |err| switch (err) {
                        error.UnresolvedType => continue,
                        error.OutOfMemory => return error.OutOfMemory,
                        else => return self.fail(template.unit, template.node, .unresolved_type),
                    };
                    try values.append(allocator, .{ .binding = captured, .evidence = actual });
                }
            }
        }
        const owned_rows = try rows.toOwnedSlice(allocator);
        errdefer allocator.free(owned_rows);
        const owned_values = try values.toOwnedSlice(allocator);
        errdefer allocator.free(owned_values);
        return .{ .binding = binding, .unit = template.unit, .node = template.node, .mappings = template.evidence, .rows = owned_rows, .values = owned_values, .captures = try children.toOwnedSlice(allocator), .computation = template.computation };
    }
    fn closureFunction(self: *Generator, key: ClosureKey) Error!u32 {
        var scope: ?code_artifacts.Scope = if (self.artifacts) |context| try context.enter(.{ .closure = key }) else null;
        defer if (scope) |*actor| actor.deinit();
        if (self.closures.get(key)) |existing| {
            try self.startup_facts.request(self.allocator, existing, .anonymous, key.unit, key.catalog, true);
            if (scope) |*actor| try actor.hit(existing);
            return existing;
        }
        if (self.retained) |retained| if (try self.findRetained(retained, .{ .closure = key })) |job| {
            const function_id = try self.reconstructRetained(retained, job, .{ .closure = key }, if (scope) |*actor| actor else null);
            try self.startup_facts.request(self.allocator, function_id, .anonymous, key.unit, key.catalog, true);
            self.startup_facts.complete(function_id);
            return function_id;
        };
        self.work.fresh_closures += 1;
        const source = self.unit(key.unit);
        const metadata = source.closures[key.catalog];
        const captures = source.extra[metadata.captures.start..][0..metadata.captures.len];
        const fn_type = self.layouts.node(key.ty);
        if (fn_type.tag != .function or captures.len != self.layouts.children(key.captures).len) return self.fail(key.unit, metadata.body, .unresolved_type);
        if (self.instance_depth >= 256) return self.fail(key.unit, metadata.body, .complexity);
        self.instance_depth += 1;
        defer self.instance_depth -= 1;
        const function_id = try self.module.addFunction(&.{ .i32, self.layouts.machine(fn_type.a), .i32 }, self.layouts.machine(fn_type.b));
        try self.closures.put(self.allocator, key, function_id);
        if (scope) |*actor| try actor.reserve(function_id);
        try self.startup_facts.request(self.allocator, function_id, .anonymous, key.unit, key.catalog, false);
        const caller = self.startup_facts.active;
        self.startup_facts.active = function_id;
        defer self.startup_facts.active = caller;
        var mappings: std.ArrayList(Mapping) = .empty;
        var rows: std.ArrayList(RowMapping) = .empty;
        defer rows.deinit(self.allocator);
        defer mappings.deinit(self.allocator);
        for (self.row_keys.get(key.rows)) |mapping| {
            const concrete = self.rowFromEvidence(mapping.value) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.fail(key.unit, metadata.body, .unresolved_type);
            try rows.append(self.allocator, .{ .variable = mapping.variable, .row = concrete });
        }
        if (key.evidence != 0) {
            const words = self.evaluator.evidence.children(key.evidence);
            var index: usize = 0;
            while (index < words.len) : (index += 2) {
                const concrete = self.fromEvidence(words[index + 1]) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.fail(key.unit, metadata.body, .unresolved_type);
                try self.mapType(key.unit, &mappings, words[index], concrete, source.span(metadata.body));
            }
        }
        for (captures, 0..) |binding, index| if (self.capturedTemplate(key.templates, binding) == null) {
            try self.mapType(key.unit, &mappings, source.binding(binding).ty, self.layouts.children(key.captures)[index], source.span(metadata.body));
        };
        try self.mapType(key.unit, &mappings, metadata.parameter.ty, fn_type.a, metadata.parameter.span);
        try self.mapType(key.unit, &mappings, source.typeOf(metadata.body), fn_type.b, source.span(metadata.body));
        if (metadata.function_type != 0) try self.mapTypeDepth(key.unit, &mappings, &rows, metadata.function_type, key.ty, source.span(metadata.body), 0);
        var hint_arena = std.heap.ArenaAllocator.init(self.allocator);
        defer hint_arena.deinit();
        var hints: std.ArrayList(core_eval.RetainedCapture) = .empty;
        for (captures) |binding| if (self.capturedTemplate(key.templates, binding)) |template| try hints.append(hint_arena.allocator(), try self.retainedCapture(hint_arena.allocator(), binding, template, 0));
        if (key.parameter_template != 0) try hints.append(hint_arena.allocator(), try self.retainedCapture(hint_arena.allocator(), metadata.parameter.binding, self.template_catalog.items[key.parameter_template - 1], 0));
        try self.refineMappingsCaptures(key.unit, .{ .closure = .{ .unit = key.unit, .catalog = key.catalog } }, key.ty, &mappings, &rows, source.span(metadata.body), hints.items);
        var emitter: Emitter = .{ .generator = self, .unit_id = key.unit, .function_id = function_id, .provider_local = 2, .mappings = mappings.items, .row_mappings = rows.items, .factory_template = key.template_result };
        defer emitter.deinit();
        if (metadata.parameter.binding != 0) {
            if (key.parameter_template != 0) {
                const template = self.template_catalog.items[key.parameter_template - 1];
                try emitter.templates.put(self.allocator, metadata.parameter.binding, .{ .unit = template.unit, .node = template.node, .environment = if (template.has_environment) 1 else null, .captures = template.captures, .templates = template.templates, .computation = template.computation, .evidence = template.evidence, .rows = template.rows });
            } else try emitter.locals.put(self.allocator, metadata.parameter.binding, 1);
        }
        for (captures, 0..) |binding, index| {
            if (self.capturedStatic(key.static_values, binding)) |value| {
                try emitter.static_values.put(self.allocator, binding, value);
                continue;
            }
            const capture_type = self.layouts.children(key.captures)[index];
            const machine = self.layouts.machine(capture_type);
            const local = try self.module.addLocal(function_id, machine);
            try emitter.emit(.local_get, 0);
            try emitter.emit(if (machine == .f32) .f32_load else .i32_load, @intCast(index * 4));
            try emitter.emit(.local_set, local);
            if (self.capturedTemplate(key.templates, binding)) |template| {
                try emitter.templates.put(self.allocator, binding, .{ .unit = template.unit, .node = template.node, .environment = if (template.has_environment) local else null, .captures = template.captures, .templates = template.templates, .computation = template.computation, .evidence = template.evidence, .rows = template.rows });
            } else try emitter.locals.put(self.allocator, binding, local);
        }
        if (key.template_result) {
            try emitter.templateExpression(metadata.body, 0);
            const template = emitter.result_template orelse return self.fail(key.unit, metadata.body, .unresolved_type);
            try self.closure_template_results.put(self.allocator, key, template);
        } else {
            try emitter.expression(metadata.body, 0);
            if (source.types.node(source.typeOf(metadata.body)).tag == .never) try emitter.emit(.unreachable_, 0);
        }
        // Generic static fields may retain erased layouts. Their complete
        // capture graph belongs to the code key; it is not a closed principal
        // mapping receipt suitable for independent semantic reuse.
        if (key.static_values == 0) if (scope) |*actor| try actor.solved(mappings.items, rows.items, self.template_keys.get(key.templates));
        if (scope) |*actor| try actor.complete(function_id, self.closure_template_results.get(key));
        self.startup_facts.complete(function_id);
        return function_id;
    }
    fn callable(self: *Generator, key: CallableKey) Error!u32 {
        var scope: ?code_artifacts.Scope = if (self.artifacts) |context| try context.enter(.{ .callable = key }) else null;
        defer if (scope) |*actor| actor.deinit();
        if (self.callables.get(key)) |existing| {
            if (scope) |*actor| try actor.hit(existing);
            return existing;
        }
        const source = self.unit(key.target.unit);
        const body = source.body(key.target.binding) orelse return self.decline(key.target.unit, source.binding(key.target.binding).span, .unsupported);
        if (body.parameters.len == 0) {
            if (key.applied != 0) return self.decline(key.target.unit, body.span, .unsupported);
            const arrow = self.layouts.node(key.ty);
            if (arrow.tag != .function) return self.decline(key.target.unit, body.span, .unresolved_type);
            const function_id = try self.module.addFunction(&.{ .i32, self.layouts.machine(arrow.a), .i32 }, self.layouts.machine(arrow.b));
            try self.callables.put(self.allocator, key, function_id);
            if (scope) |*actor| try actor.reserve(function_id);
            const global = if (body.runtime) try self.runtimeGlobal(key.target) else null;
            const constant_ = if (global == null) try self.constant(key.target, key.ty) else null;
            const callee = try self.module.addLocal(function_id, .i32);
            if (global) |index| try self.module.emit(function_id, .{ .op = .global_get, .operand = index }) else try self.emitValue(function_id, constant_.?);
            for ([_]wasm.Instruction{
                .{ .op = .local_set, .operand = callee },
                .{ .op = .local_get, .operand = callee },
                .{ .op = .i32_load, .operand = 4 },
                .{ .op = .local_get, .operand = 1 },
                .{ .op = .local_get, .operand = 2 },
                .{ .op = .local_get, .operand = callee },
                .{ .op = .i32_load },
                .{ .op = .call_indirect, .operand = try self.module.internType(&.{ .i32, self.layouts.machine(arrow.a), .i32 }, self.layouts.machine(arrow.b)) },
            }) |instruction| {
                try self.module.emit(function_id, instruction);
                if (instruction.op == .call_indirect) if (self.request_owner) |owner| try request_runtime.guard(&self.module, function_id, owner, &.{});
            }
            if (scope) |*actor| try actor.complete(function_id, null);
            return function_id;
        }
        if (body.parameters.len > max_parameters or key.applied >= body.parameters.len) return self.decline(key.target.unit, body.span, .unsupported);
        var direct: Key = .{ .target = key.target, .count = @intCast(body.parameters.len) };
        var ty = key.ty;
        var current: layout.Node = undefined;
        for (0..body.parameters.len) |index| {
            const n = self.layouts.node(ty);
            if (n.tag != .function) return self.decline(key.target.unit, body.span, .unresolved_type);
            direct.parameters[index] = n.a;
            direct.effects[index] = n.c;
            if (index == key.applied) current = n;
            ty = n.b;
        }
        direct.result = ty;
        const function_id = try self.module.addFunction(&.{ .i32, self.layouts.machine(current.a), .i32 }, self.layouts.machine(current.b));
        try self.callables.put(self.allocator, key, function_id);
        if (scope) |*actor| try actor.reserve(function_id);
        var emitter: Emitter = .{ .generator = self, .unit_id = key.target.unit, .function_id = function_id, .provider_local = 2, .mappings = &.{} };
        defer emitter.deinit();
        if (key.applied + 1 == body.parameters.len) {
            const target_function = try self.function(direct);
            for (direct.parameters[0..key.applied], 0..) |parameter, index| {
                try emitter.emit(.local_get, 0);
                try emitter.emit(if (self.layouts.machine(parameter) == .f32) .f32_load else .i32_load, @intCast(index * 4));
            }
            try emitter.emit(.local_get, 1);
            try emitter.providerHead();
            try emitter.emit(.call, target_function);
        } else {
            const environment = try emitter.allocate((key.applied + 1) * 4);
            for (direct.parameters[0..key.applied], 0..) |parameter, index| {
                const floating = self.layouts.machine(parameter) == .f32;
                try emitter.emit(.local_get, environment);
                try emitter.emit(.local_get, 0);
                try emitter.emit(if (floating) .f32_load else .i32_load, @intCast(index * 4));
                try emitter.emit(if (floating) .f32_store else .i32_store, @intCast(index * 4));
            }
            try emitter.emit(.local_get, environment);
            try emitter.emit(.local_get, 1);
            try emitter.emit(if (self.layouts.machine(current.a) == .f32) .f32_store else .i32_store, key.applied * 4);
            const next = try self.callable(.{ .target = key.target, .ty = key.ty, .applied = key.applied + 1 });
            try emitter.descriptor(next, environment);
        }
        if (scope) |*actor| try actor.complete(function_id, null);
        return function_id;
    }
    fn constructorFunction(self: *Generator, key: ConstructorKey) Error!u32 {
        var scope: ?code_artifacts.Scope = if (self.artifacts) |context| try context.enter(.{ .constructor = key }) else null;
        defer if (scope) |*actor| actor.deinit();
        if (self.constructor_functions.get(key)) |existing| {
            if (scope) |*actor| try actor.hit(existing);
            return existing;
        }
        const fn_type = self.layouts.node(key.ty);
        if (fn_type.tag != .function) return self.decline(key.unit, .{ .start = 0, .end = 0 }, .unresolved_type);
        const function_id = try self.module.addFunction(&.{ .i32, self.layouts.machine(fn_type.a), .i32 }, .i32);
        try self.constructor_functions.put(self.allocator, key, function_id);
        if (scope) |*actor| try actor.reserve(function_id);
        var emitter: Emitter = .{ .generator = self, .unit_id = key.unit, .function_id = function_id, .provider_local = 2, .mappings = &.{} };
        defer emitter.deinit();
        const metadata = self.unit(key.unit).constructor(key.catalog);
        const payload_type = self.unit(key.unit).types.node(metadata.payload);
        const record_local = if (payload_type.tag == .record and payload_type.b == 1) blk: {
            const record = try emitter.allocate(4);
            try emitter.emit(.local_get, record);
            try emitter.emit(.local_get, 1);
            try emitter.emit(if (self.layouts.machine(fn_type.a) == .f32) .f32_store else .i32_store, 0);
            break :blk record;
        } else if (payload_type.tag == .record) try emitter.recordRepresentation(payload_type, 1, true) else null;
        const address = try emitter.allocate(8);
        try emitter.emit(.local_get, address);
        try emitter.emit(.i32_const, metadata.tag);
        try emitter.emit(.i32_store, 0);
        try emitter.emit(.local_get, address);
        try emitter.emit(.local_get, record_local orelse 1);
        try emitter.emit(if (record_local == null and self.layouts.machine(fn_type.a) == .f32) .f32_store else .i32_store, 4);
        try emitter.emit(.local_get, address);
        if (scope) |*actor| try actor.complete(function_id, null);
        return function_id;
    }
    fn primitiveFunction(self: *Generator, key: PrimitiveKey) Error!u32 {
        var scope: ?code_artifacts.Scope = if (self.artifacts) |context| try context.enter(.{ .primitive = key }) else null;
        defer if (scope) |*actor| actor.deinit();
        if (self.primitive_functions.get(key)) |existing| {
            if (scope) |*actor| try actor.hit(existing);
            return existing;
        }
        const source = self.unit(key.unit);
        const metadata = source.primitives[key.catalog];
        if (metadata.arity == 0 or metadata.arity > 3 or key.applied >= metadata.arity) return self.fail(key.unit, 0, .unsupported);
        var parameters: [3]layout.Id = undefined;
        var current: layout.Node = undefined;
        var ty = key.ty;
        for (0..metadata.arity) |index| {
            const arrow = self.layouts.node(ty);
            if (arrow.tag != .function) return self.fail(key.unit, 0, .unresolved_type);
            parameters[index] = arrow.a;
            if (index == key.applied) current = arrow;
            ty = arrow.b;
        }
        if (self.primitive_functions.count() >= 65536) return self.fail(key.unit, 0, .complexity);
        const function_id = try self.module.addFunction(&.{ .i32, self.layouts.machine(current.a), .i32 }, self.layouts.machine(current.b));
        try self.primitive_functions.put(self.allocator, key, function_id);
        if (scope) |*actor| try actor.reserve(function_id);
        var emitter: Emitter = .{ .generator = self, .unit_id = key.unit, .function_id = function_id, .provider_local = 2, .mappings = &.{} };
        defer emitter.deinit();
        if (key.applied + 1 == metadata.arity) {
            var locals: [3]u32 = undefined;
            var machines: [3]wasm.ValueType = undefined;
            for (parameters[0..metadata.arity], 0..) |parameter, index| {
                const machine = self.layouts.machine(parameter);
                machines[index] = machine;
                if (index == key.applied) {
                    locals[index] = 1;
                } else {
                    locals[index] = try emitter.temporary(machine);
                    try emitter.emit(.local_get, 0);
                    try emitter.emit(if (machine == .f32) .f32_load else .i32_load, @intCast(index * 4));
                    try emitter.emit(.local_set, locals[index]);
                }
            }
            switch (metadata.kind) {
                .scalar => if (self.layouts.node(parameters[0]).tag == .product) {
                    try emitter.simdLocals(metadata.op, locals[0..metadata.arity], parameters[0]);
                } else {
                    const scalar_type = self.layouts.scalar(parameters[0]) orelse return self.fail(key.unit, 0, .unsupported);
                    const opcode = scalar_ops.opcode(metadata.op, scalar_type) orelse return self.fail(key.unit, 0, .unsupported);
                    for (locals[0..metadata.arity]) |local| try emitter.emit(.local_get, local);
                    try emitter.emit(opcode, 0);
                },
                .array => try emitter.arrayLocals(0, metadata.array_op, locals[0..metadata.arity], machines[0..metadata.arity], ty, parameters[0]),
            }
        } else {
            const environment = try emitter.allocate((key.applied + 1) * 4);
            for (parameters[0..key.applied], 0..) |parameter, index| {
                const floating = self.layouts.machine(parameter) == .f32;
                try emitter.emit(.local_get, environment);
                try emitter.emit(.local_get, 0);
                try emitter.emit(if (floating) .f32_load else .i32_load, @intCast(index * 4));
                try emitter.emit(if (floating) .f32_store else .i32_store, @intCast(index * 4));
            }
            try emitter.emit(.local_get, environment);
            try emitter.emit(.local_get, 1);
            try emitter.emit(if (self.layouts.machine(current.a) == .f32) .f32_store else .i32_store, key.applied * 4);
            const next = try self.primitiveFunction(.{ .unit = key.unit, .catalog = key.catalog, .ty = key.ty, .applied = key.applied + 1 });
            try emitter.descriptor(next, environment);
        }
        if (scope) |*actor| try actor.complete(function_id, null);
        return function_id;
    }
    fn runtimeDataWord(self: *Generator, address: u32, operation: runtime_operations.Id) Error!void {
        self.runtime_operations.dataWord(&self.module, address, operation) catch |err| switch (err) {
            error.InvalidOperation => return error.InvalidFunctionReference,
            error.OutOfMemory => return error.OutOfMemory,
            error.ModuleTooLarge => return error.ModuleTooLarge,
        };
    }
    fn runtimeOperation(self: *Generator, label: type_evidence.Effects.Label, unit_id: u32, span: core.Span) Error!runtime_operations.Id {
        const previous_count = self.runtime_operations.entries.items.len;
        const operation = self.runtime_operations.intern(self.evaluator.evidence.view(), label) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.ModuleTooLarge => error.ModuleTooLarge,
            error.InvalidOperation => self.decline(unit_id, span, .unresolved_type),
        };
        try self.module.demandResource(.operation, operation, operation <= previous_count);
        return operation;
    }
    fn operationToken(self: *Generator, unit_id: u32, catalog: u32, mappings: []const Mapping, rows: []const RowMapping, span: core.Span) Error!runtime_operations.Id {
        const source = self.unit(unit_id);
        if (catalog >= source.operation_values.len) return self.decline(unit_id, span, .unsupported);
        const operation = source.operation_values[catalog];
        var arguments: std.ArrayList(type_evidence.Id) = .empty;
        defer arguments.deinit(self.allocator);
        for (source.types.list(operation.arguments)) |argument| {
            const concrete = try self.codeLayoutWithRows(unit_id, argument, mappings, rows, span);
            const actual = self.toEvidence(concrete) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
            try arguments.append(self.allocator, actual);
        }
        const semantic_label = self.evaluator.evidence.effects.internOperation(operation.identity, arguments.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
        return self.runtimeOperation(semantic_label, unit_id, span);
    }
    fn operationLayoutToken(self: *Generator, operation_type: layout.Id, unit_id: u32, span: core.Span) Error!runtime_operations.Id {
        const operation = self.layouts.node(operation_type);
        if (operation.tag != .nominal) return self.decline(unit_id, span, .unresolved_type);
        var arguments: std.ArrayList(type_evidence.Id) = .empty;
        defer arguments.deinit(self.allocator);
        const source_arguments = try self.allocator.dupe(layout.Id, self.layouts.children(operation_type));
        defer self.allocator.free(source_arguments);
        for (source_arguments) |argument| {
            const actual = self.toEvidence(argument) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
            try arguments.append(self.allocator, actual);
        }
        const semantic_label = self.evaluator.evidence.effects.internOperation(.{ .unit = operation.a, .decl = operation.b }, arguments.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
        return self.runtimeOperation(semantic_label, unit_id, span);
    }
    fn requestOperation(self: *Generator, unit_id: u32, label: types.Effects.Label, mappings: []const Mapping, rows: []const RowMapping, span: core.Span) Error!runtime_operations.Id {
        const source = self.unit(unit_id);
        const operation = source.types.operation(label);
        var arguments: std.ArrayList(type_evidence.Id) = .empty;
        defer arguments.deinit(self.allocator);
        for (source.types.list(operation.arguments)) |argument| {
            const concrete = try self.codeLayoutWithRows(unit_id, argument, mappings, rows, span);
            const actual = self.toEvidence(concrete) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
            try arguments.append(self.allocator, actual);
        }
        const semantic_label = self.evaluator.evidence.effects.internOperation(operation.identity, arguments.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
        return self.runtimeOperation(semantic_label, unit_id, span);
    }
    fn operationFunction(self: *Generator, key: OperationKey) Error!u32 {
        var scope: ?code_artifacts.Scope = if (self.artifacts) |context| try context.enter(.{ .operation = key }) else null;
        defer if (scope) |*actor| actor.deinit();
        if (self.operation_functions.get(key)) |existing| {
            if (scope) |*actor| try actor.hit(existing);
            return existing;
        }
        const arrow = self.layouts.node(key.ty);
        if (arrow.tag != .function) return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
        const argument_machine = self.layouts.machine(arrow.a);
        const result_machine = self.layouts.machine(arrow.b);
        const function_id = try self.module.addFunction(&.{ .i32, argument_machine, .i32 }, result_machine);
        try self.operation_functions.put(self.allocator, key, function_id);
        if (scope) |*actor| try actor.reserve(function_id);
        var emitter: Emitter = .{ .generator = self, .unit_id = 1, .function_id = function_id, .provider_local = 2, .mappings = &.{} };
        defer emitter.deinit();
        const frame = try emitter.temporary(.i32);
        const implementation = try emitter.temporary(.i32);
        try emitter.emit(.local_get, 2);
        try emitter.emit(.local_set, frame);
        try emitter.emit(.block, 0);
        try emitter.emit(.loop, 0);
        try emitter.emit(.local_get, frame);
        try emitter.emit(.i32_eqz, 0);
        try emitter.emit(.if_, 0);
        try emitter.emit(.unreachable_, 0);
        try emitter.emit(.end, 0);
        try emitter.emit(.local_get, frame);
        try emitter.emit(.i32_load, @offsetOf(provider_chain.Frame, "operation"));
        try emitter.operationConstant(key.operation);
        try emitter.emit(.i32_eq, 0);
        try emitter.emit(.br_if, 1);
        try emitter.emit(.local_get, frame);
        try emitter.emit(.i32_load, @offsetOf(provider_chain.Frame, "outer"));
        try emitter.emit(.local_set, frame);
        try emitter.emit(.br, 0);
        try emitter.emit(.end, 0);
        try emitter.emit(.end, 0);
        try emitter.emit(.local_get, frame);
        try emitter.emit(.i32_load, @offsetOf(provider_chain.Frame, "kind"));
        try emitter.emit(.i32_const, @backingInt(provider_chain.Kind.callback));
        try emitter.emit(.i32_eq, 0);
        try emitter.emit(.if_, @backingInt(result_machine));
        try emitter.emit(.local_get, frame);
        try emitter.emit(.i32_load, @offsetOf(provider_chain.Frame, "target"));
        try emitter.emit(.local_set, implementation);
        try emitter.emit(.local_get, implementation);
        try emitter.emit(.i32_load, 4);
        try emitter.emit(.local_get, 1);
        // Implementations run outside the matched provider and all younger ones.
        try emitter.emit(.local_get, frame);
        try emitter.emit(.i32_load, @offsetOf(provider_chain.Frame, "outer"));
        try emitter.emit(.local_get, implementation);
        try emitter.emit(.i32_load, 0);
        try emitter.emit(.call_indirect, try self.module.internType(&.{ .i32, argument_machine, .i32 }, result_machine));
        try emitter.emit(.else_, 0);
        try emitter.emit(.local_get, frame);
        try emitter.emit(.i32_load, @offsetOf(provider_chain.Frame, "kind"));
        try emitter.emit(.i32_const, @backingInt(provider_chain.Kind.state_read));
        try emitter.emit(.i32_eq, 0);
        try emitter.emit(.if_, @backingInt(result_machine));
        if (arrow.a == types.unit) {
            try emitter.emit(.local_get, frame);
            try emitter.emit(.i32_load, @offsetOf(provider_chain.Frame, "target"));
            try emitter.emit(if (result_machine == .f32) .f32_load else .i32_load, @offsetOf(provider_chain.Cell, "value"));
        } else try emitter.emit(.unreachable_, 0);
        try emitter.emit(.else_, 0);
        try emitter.emit(.local_get, frame);
        try emitter.emit(.i32_load, @offsetOf(provider_chain.Frame, "kind"));
        try emitter.emit(.i32_const, @backingInt(provider_chain.Kind.state_write));
        try emitter.emit(.i32_eq, 0);
        try emitter.emit(.if_, @backingInt(result_machine));
        if (arrow.b == types.unit) {
            try emitter.emit(.local_get, frame);
            try emitter.emit(.i32_load, @offsetOf(provider_chain.Frame, "target"));
            try emitter.emit(.local_get, 1);
            try emitter.emit(if (argument_machine == .f32) .f32_store else .i32_store, @offsetOf(provider_chain.Cell, "value"));
            try emitter.emit(.i32_const, 0);
        } else try emitter.emit(.unreachable_, 0);
        try emitter.emit(.else_, 0);
        if (self.request_owner != null) {
            try emitter.emit(.local_get, frame);
            try emitter.emit(.i32_load, @offsetOf(provider_chain.Frame, "kind"));
            try emitter.emit(.i32_const, request_runtime.request_kind);
            try emitter.emit(.i32_eq, 0);
            try emitter.emit(.if_, @backingInt(result_machine));
            try emitter.invokeRequest(frame, 1, argument_machine, result_machine);
            try emitter.emit(.else_, 0);
            try emitter.emit(.unreachable_, 0);
            try emitter.emit(.end, 0);
        } else try emitter.emit(.unreachable_, 0);
        try emitter.emit(.end, 0);
        try emitter.emit(.end, 0);
        try emitter.emit(.end, 0);
        if (scope) |*actor| try actor.complete(function_id, null);
        return function_id;
    }
    fn foreignRow(self: *const Generator, row: u32, singleton: bool) bool {
        if (row == layout.unknown_row) return false;
        const view = self.layouts.effects.view();
        const labels = view.rowLabels(row);
        if (singleton and labels.len != 1) return false;
        for (labels) |label| {
            const operation = view.operation(label);
            if (operation.identity.unit != 0 or operation.identity.decl != 1 or operation.arguments.len != 0) return false;
        }
        return true;
    }
    fn hostCallback(self: *const Generator, ty: layout.Id) ?wasm.Callback {
        const arrow = self.layouts.node(ty);
        if (arrow.tag != .function or !self.foreignRow(arrow.c, true)) return null;
        return .{ .parameter = self.layouts.abi(arrow.a) orelse return null, .result = self.layouts.abi(arrow.b) orelse return null };
    }
    fn hostFunction(self: *Generator, ty: layout.Id) Error!u32 {
        var scope: ?code_artifacts.Scope = if (self.artifacts) |context| try context.enter(.{ .host = ty }) else null;
        defer if (scope) |*actor| actor.deinit();
        if (self.host_functions.get(ty)) |existing| {
            if (scope) |*actor| try actor.hit(existing);
            return existing;
        }
        const callback = self.hostCallback(ty) orelse return self.decline(1, .{ .start = 0, .end = 0 }, .entry_type);
        const imported = try self.module.importHostCallback(callback);
        const function_id = try self.module.addFunction(&.{ .i32, callback.parameter.machine(), .i32 }, callback.result.machine());
        try self.host_functions.put(self.allocator, ty, function_id);
        if (scope) |*actor| try actor.reserve(function_id);
        // The descriptor environment is a retained externref table index. It is
        // never a host pointer or a dynamically captured provider head.
        for ([_]wasm.Instruction{
            .{ .op = .local_get, .operand = 0 }, .{ .op = .host_ref_get },
            .{ .op = .local_get, .operand = 1 }, .{ .op = .call_import, .operand = imported },
        }) |instruction| try self.module.emit(function_id, instruction);
        if (scope) |*actor| try actor.complete(function_id, null);
        return function_id;
    }
    fn entryCallbackFunction(self: *Generator, target: u32, parameter: layout.Id, result: Scalar) Error!u32 {
        const stub = try self.hostFunction(parameter);
        const arena = try self.module.ensureArena();
        const references = try self.module.ensureHostReferences();
        const wrapper = try self.module.addFunction(&.{.externref}, result.machine());
        var emitter: Emitter = .{ .generator = self, .unit_id = 1, .function_id = wrapper, .mappings = &.{} };
        defer emitter.deinit();
        if (self.request_owner) |owner| {
            try emitter.emit(.i32_const, 0);
            try emitter.emit(.global_set, owner);
        }
        // Guest calls cannot reenter an active instance. Clear a prior failed
        // invocation here, bounding inert references even when a trap bypasses
        // normal cleanup. The guest revokes the capability in its own finally.
        try emitter.emit(.i32_const, 0);
        try emitter.emit(.call, references.release);
        try emitter.emit(.i32_const, 0);
        try emitter.emit(.call, arena.reset);
        try emitter.emit(.drop, 0);
        const handle = try emitter.temporary(.i32);
        try emitter.emit(.local_get, 0);
        try emitter.emit(.call, references.retain);
        try emitter.emit(.local_set, handle);
        const descriptor = try emitter.allocate(8);
        try emitter.emit(.local_get, descriptor);
        try emitter.referenceConstant(stub, .table_function);
        try emitter.emit(.i32_store, 0);
        try emitter.emit(.local_get, descriptor);
        try emitter.emit(.local_get, handle);
        try emitter.emit(.i32_store, 4);
        try emitter.emit(.local_get, descriptor);
        try emitter.emit(.i32_const, 0);
        try emitter.emit(.call, target);
        const saved = try emitter.temporary(result.machine());
        try emitter.emit(.local_set, saved);
        try emitter.emit(.i32_const, 0);
        try emitter.emit(.call, references.release);
        try emitter.emit(.local_get, saved);
        return wrapper;
    }
    fn entryFunction(self: *Generator, target: u32, parameter: Scalar, result: Scalar) Error!u32 {
        const wrapper = try self.module.addFunction(&.{parameter.machine()}, result.machine());
        if (self.request_owner) |owner| {
            try self.module.emit(wrapper, .{ .op = .i32_const });
            try self.module.emit(wrapper, .{ .op = .global_set, .operand = owner });
        }
        // Array arguments are allocated by the host after its reset. Resetting
        // here would overwrite them; their ABI exposes the same arena helpers.
        if (parameter != .array_u32 and parameter != .array_f32) if (self.module.arena) |arena| {
            for ([_]wasm.Instruction{
                .{ .op = .i32_const, .operand = 0 }, .{ .op = .call, .operand = arena.reset }, .{ .op = .drop },
            }) |instruction| try self.module.emit(wrapper, instruction);
        };
        for ([_]wasm.Instruction{
            .{ .op = .local_get, .operand = 0 }, .{ .op = .i32_const, .operand = 0 }, .{ .op = .call, .operand = target },
        }) |instruction| try self.module.emit(wrapper, instruction);
        return wrapper;
    }
};

pub fn compile(allocator: Allocator, units: []const core.Module, entry: u32) Error!Result {
    return compileWithOptions(allocator, units, entry, .{ .artifact_replay = default_artifact_replay, .artifact_dump = default_artifact_replay });
}

const default_artifact_replay = if (@hasDecl(@import("root"), "compiler_defaults")) @import("root").compiler_defaults.artifact_replay else false;
pub const CompileOptions = struct {
    checkpoint: ?*const @import("backend_checkpoint.zig").Checkpoint = null,
    io: ?std.Io = null,
    /// Detailed hot-region clocks are opt-in; broad phase timing stays cheap.
    profile_backend: bool = false,
    policy: @import("execution_policy.zig").Policy = .{},
    observe_startup: bool = false,
    identity: ?runtime_identity.View = null,
    evidence_noise: bool = false,
    unit_order: []const u32 = &.{},
    diagnostic_source_mode: bool = false,
    diagnostic_prelude_unit: u32 = 0,
    artifact_replay: bool = false,
    artifact_dump: bool = false,
    retain_artifacts: bool = false,
    previous: ?*const artifact_capture.Capture = null,
    principal_previous: ?*const artifact_capture.Capture = null,
    query_previous: ?*const artifact_capture.Capture = null,
    cached_units: usize = 0,
};

pub fn compileWithIdentity(allocator: Allocator, units: []const core.Module, entry: u32, names: runtime_identity.View) Error!Result {
    return compileWithOptions(allocator, units, entry, .{ .identity = names, .artifact_replay = default_artifact_replay, .artifact_dump = default_artifact_replay });
}

/// Private differential hook: irrelevant semantic proofs must not select tags.
pub fn compileWithEvidenceNoise(allocator: Allocator, units: []const core.Module, entry: u32, noise: bool) Error!Result {
    return compileWithOptions(allocator, units, entry, .{ .evidence_noise = noise });
}

pub fn compileWithOptions(allocator: Allocator, units: []const core.Module, entry: u32, options: CompileOptions) Error!Result {
    var clock = @import("backend_timing.zig").Clock.init(options.io);
    var timing: @import("backend_timing.zig").Stats = .{};
    if (options.identity) |names| {
        // Project emission requires a complete dense owner view; Core-only
        // callers cannot accidentally publish a project-domain fragment.
        if (names.owners.len != units.len) return error.InvalidFunctionReference;
        for (units, 0..) |*unit, index| {
            if (unit.unit != index + 1 or names.owner(unit.unit) == null) return error.InvalidFunctionReference;
        }
    }
    const recording = options.artifact_replay or options.retain_artifacts or options.previous != null or options.query_previous != null;
    const principal_previous = options.principal_previous orelse options.previous;
    const query_previous = options.query_previous orelse options.previous;
    var module_stamps: code_artifacts.ModuleStamps = .{ .allocator = allocator, .current = units, .previous = if (query_previous) |old| if (old.metadata.pools) |*pools| pools else null else null, .compare_contents = true };
    defer module_stamps.deinit();
    const stamps: ?*code_artifacts.ModuleStamps = if (module_stamps.previous != null) &module_stamps else null;
    var journal = artifact_emitter.Recorder.init(allocator);
    var journal_alive = true;
    defer if (journal_alive) journal.deinit();
    var metadata = code_artifacts.Context.init(allocator);
    var metadata_alive = true;
    defer if (metadata_alive) metadata.deinit();
    if (recording) {
        journal.owner = &metadata.active_job;
        journal.clock = &metadata.clock;
    }
    var generator = try Generator.init(allocator, units, if (recording) &journal else null);
    generator.work_timing.clock = .init(if (options.profile_backend) options.io else null);
    generator.evaluator.timing = if (options.profile_backend) &generator.work_timing else null;
    // The replay gate destroys all mutable compiler state before materialization.
    if (recording) generator.artifacts = &metadata;
    generator.refinement_owner = &metadata;
    var generator_alive = true;
    defer if (generator_alive) generator.deinit();
    generator.evaluator.diagnostic_context = .{ .identity = options.identity, .entry = entry, .prelude = options.diagnostic_prelude_unit, .source_mode = options.diagnostic_source_mode };
    generator.startup_facts.enabled = options.observe_startup;
    if (options.identity) |names| generator.runtime_operations = runtime_operations.Store.initProject(allocator, names);
    if (recording) generator.runtime_operations.artifacts = &journal;
    var retained: ?artifact_fragment.State = null;
    defer if (retained) |*state| state.deinit();
    if (options.previous) |previous| {
        if (previous.emission.sealed and previous.metadata.pools != null) {
            retained = try artifact_fragment.State.initWithStamps(allocator, previous, units, options.identity, options.cached_units, stamps);
            generator.retained = &retained.?;
        }
    }
    var principal_state: ?principal_evidence_reuse.State = null;
    defer if (principal_state) |*state| state.deinit();
    var persisted_principals: ?@import("principal_archive.zig").Reader = if (options.checkpoint) |checkpoint| .{ .allocator = allocator, .archive = &checkpoint.principal, .units = units, .names = options.identity } else null;
    defer if (persisted_principals) |*reader| reader.deinit();
    if (options.retain_artifacts or options.previous != null or options.checkpoint != null) {
        if (persisted_principals) |*reader| generator.persisted_principals = reader;
        if (principal_previous) |previous| if (previous.emission.sealed and previous.metadata.pools != null) {
            // Executable admission already checked this semantic source pair.
            // Clone only under identical admission options and owner pairing;
            // code still needs its separate exact body/value checks. Repeating
            // the whole dependency validation here would tax every small edit.
            if (retained) |*state| if (state.importer.code_gate) |*checked| {
                if (shared_query_gate.share(allocator, &previous.metadata.pools.?, units, &checked.semantic)) |admission| {
                    principal_state = .{ .allocator = allocator, .old = previous, .gate = admission, .names = options.identity };
                }
            };
            if (principal_state == null) principal_state = try principal_evidence_reuse.State.init(allocator, previous, units, options.identity, stamps);
            generator.principal_state = &principal_state.?;
        };
        // Bind callbacks only after the Generator reaches its stable stack address.
        generator.evaluator.principal_provider = .{ .context = &generator, .lookup = Generator.principalLookup, .record = Generator.principalRecord };
    }
    var query_state: ?completed_specialization_query.State = null;
    defer if (query_state) |*state| state.deinit();
    generator.evaluator.retain_specialization_receipts = recording;
    if (query_previous) |previous| if (previous.metadata.pools != null) {
        // Both States are prepared here from this compile's same immutable
        // source pair and identity. A new namespace is never admitted by a
        // lease.
        if (principal_state) |*principal| {
            if (shared_query_gate.share(allocator, &previous.metadata.pools.?, units, &principal.gate)) |gate| {
                query_state = .{ .allocator = allocator, .old = previous, .graph_scratch = .{ .allocator = allocator }, .gate = gate };
                query_state.?.stats.shared_gates = 1;
                query_state.?.stats.shared_gate_bytes = shared_query_gate.validationBytes(&query_state.?.gate);
            }
        }
        if (query_state == null) {
            query_state = .{ .allocator = allocator, .old = previous, .graph_scratch = .{ .allocator = allocator }, .gate = try @import("principal_reuse_gate.zig").Gate.initWithStamps(allocator, &previous.metadata.pools.?, units, options.identity, stamps) };
            query_state.?.stats.gate_fresh = 1;
        }
        query_state.?.io = options.io;
        query_state.?.semantic_workers = options.policy.semantic_workers;
        generator.query_state = &query_state.?;
        generator.evaluator.specialization_provider = .{ .context = &generator, .lookup = Generator.completedQueryLookup };
    };
    if (options.evidence_noise) {
        for (0..7) |index| _ = generator.evaluator.evidence.effects.internOperation(.{ .unit = std.math.maxInt(u32), .decl = @intCast(9000 + index) }, &.{types.f32_type}) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.ModuleTooLarge;
    }
    timing.prepare_us = clock.lap();
    generate(&generator, entry, options.unit_order) catch |err| switch (err) {
        error.Declined => {
            var diagnostic_ = generator.diagnostic;
            const detail = if (diagnostic_) |item| item.detail else &.{};
            const owned_message = try allocator.dupe(u8, detail);
            if (diagnostic_) |*item| item.detail = owned_message;
            errdefer allocator.free(owned_message);
            return .{ .counters = generator.evaluator.counters, .principal = generator.principalStats(), .diagnostic = diagnostic_, .owned_message = owned_message, .startup_observation = if (options.observe_startup) try generator.startup_facts.capture(allocator, &generator.module) else null, .code_instances = generator.codeCount(), .callable_wrappers = generator.wrapperCount(), .emitted_functions = generator.module.functions.items.len, .constant_steps = generator.evaluator.steps };
        },
        else => return err,
    };
    timing.generate_us = clock.lap();
    try generator.initializeRuntime();
    if (recording) try journal.captureOperations(generator.runtime_operations.entries.items);
    generator.runtime_operations.finish(&generator.module) catch |err| switch (err) {
        error.InvalidOperation => return error.InvalidFunctionReference,
        error.OutOfMemory => return error.OutOfMemory,
        error.ModuleTooLarge => return error.ModuleTooLarge,
    };
    timing.initialize_us = clock.lap();
    var optimized: ?@import("optimized_bodies.zig").Capture = if (options.retain_artifacts) .{ .allocator = allocator } else null;
    defer if (optimized) |*owned| owned.deinit();
    var runtime_optimization: @import("optimized_bodies.zig").Stats = .{};
    const retained_optimized = if (options.previous) |previous| if (previous.optimized) |*owned| owned else null else null;
    const checkpoint_optimized = if (options.checkpoint) |checkpoint| if (checkpoint.optimizer) |*owned| owned else null else null;
    const optimized_previous = retained_optimized orelse checkpoint_optimized;
    var result: Result = .{ .bytes = try generator.module.assembleWithOptions(.{ .io = options.io, .workers = options.policy.codegen_workers, .tier = options.policy.codegen_tier, .share_machine_code = options.policy.share_machine_code, .previous = optimized_previous, .current = if (optimized) |*owned| owned else null, .stats = &runtime_optimization }), .code_instances = generator.codeCount(), .callable_wrappers = generator.wrapperCount(), .emitted_functions = generator.module.functions.items.len, .constant_steps = generator.evaluator.steps };
    result.emitted_functions -= runtime_optimization.shared;
    result.runtime_optimization = runtime_optimization;
    timing.assemble_us = clock.lap();
    timing.profiled = options.profile_backend;
    if (options.profile_backend) timing.work = generator.work_timing.snapshot();
    result.optimization = generator.facts.stats;
    result.optimization.region_requests = generator.evaluator.region_arena_pool.stats.requested;
    result.optimization.region_reused = generator.evaluator.region_arena_pool.stats.reused;
    result.optimization.region_retained_bytes = generator.evaluator.region_arena_pool.stats.retained_bytes;
    result.optimization.evidence_import_requests = generator.evaluator.evidence_import_requests;
    result.optimization.evidence_import_reused = generator.evaluator.evidence_import_reused;
    result.optimization.closed_source_imports = generator.evaluator.closed_source_imports;
    result.optimization.closed_source_reused = generator.evaluator.closed_source_reused;
    result.optimization.split_attempts = generator.evaluator.split_attempts;
    result.optimization.split_accepted = generator.evaluator.split_accepted;
    result.optimization.split_declined = generator.evaluator.split_declined;
    result.counters = generator.evaluator.counters;
    errdefer result.deinit(allocator);
    if (options.observe_startup) result.startup_observation = try generator.startup_facts.capture(allocator, &generator.module);
    result.principal = generator.principalStats();
    if (query_state) |state| result.completed_queries = state.stats;
    result.completed_queries.recorded = generator.evaluator.specialization_receipts.items.len;
    for (generator.evaluator.specialization_receipts.items) |record| if (record.complete) {
        result.completed_queries.complete_records += 1;
    };
    result.reuse = generator.work;
    result.refinements = generator.refinement_stats;
    if (retained) |state| {
        result.reuse.reused_named = state.stats.reused_named;
        result.reuse.reused_closures = state.stats.reused_closures;
        result.reuse.candidates = state.stats.candidates;
        result.reuse.declined = state.stats.declined;
        result.reuse.reused_scalar_constants = state.stats.reused_scalar_constants;
    }
    if (recording) {
        try metadata.specialization_receipts.ensureUnusedCapacity(allocator, generator.evaluator.specialization_receipts.items.len);
        for (generator.evaluator.specialization_receipts.items) |record| metadata.specialization_receipts.appendAssumeCapacity(try record.clone(allocator));
        // Records exist only for parallel semantic inference.
        if (query_state) |*state| if (options.policy.semantic_workers > 1) {
            try metadata.independent_calls.ensureUnusedCapacity(allocator, state.independent_calls.items.len);
            for (state.independent_calls.items) |record| metadata.independent_calls.appendAssumeCapacity(try record.clone(allocator));
        };
        try metadata.capturePoolsWithStamps(&generator, options.identity, stamps);
        // Publish validation only with this candidate's owned artifact pools.
        // A failed edit leaves the previous certificate and source pins intact.
        if (principal_state) |*state| {
            metadata.pools.?.dependency_certificate = try state.gate.freezeValidation(allocator, metadata.pools.?.modules);
        } else if (retained) |*state| if (state.importer.code_gate) |*checked| {
            metadata.pools.?.dependency_certificate = try checked.semantic.freezeValidation(allocator, metadata.pools.?.modules);
        };
        journal.seal();
        try journal.freezeFunctions(metadata.function_jobs.items);
        // These helpers capture values absent from ClosureKey. Full journal
        // replay is exact; fragment admission requires fresh enclosing code.
        for (generator.static_closures.items) |function_id| journal.functions[function_id].role = .static_closure;
        for (metadata.pools.?.runtime_globals) |slot| journal.functions[slot.initializer].role = .runtime_initializer;
        for (journal.functions) |function_| if (function_.role == .unknown) return error.InvalidFunctionReference;
        // The journal retains symbolic function/table identities. Assembly may
        // map several private identities to one physical machine-code body.
        if (journal.functions.len != generator.module.functions.items.len) return error.InvalidFunctionReference;
        for (metadata.jobs.items) |job| if (job.state == .failed or job.state == .pending or job.state == .reserved) return error.InvalidFunctionReference;
        for (metadata.pools.?.functions) |function_| {
            if (function_.function >= journal.functions.len) return error.InvalidFunctionReference;
            const owner = journal.functions[function_.function].owner;
            if (owner == 0 or owner > metadata.jobs.items.len) return error.InvalidFunctionReference;
            const job = metadata.jobs.items[owner - 1];
            if (job.state != .complete or job.function == null or job.function.? != function_.function or !std.meta.eql(job.request, function_.request) or job.result_template != function_.result_template) return error.InvalidFunctionReference;
        }
        const globals = generator.module.globals.items.len;
        const imports = generator.module.imports.items.len;
        const signatures = generator.module.signatures.items.len;
        const data_bytes = generator.module.data.items.len;
        if (options.artifact_replay) {
            generator.deinit();
            generator_alive = false;
            var replayed = journal.materialize(allocator) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.ModuleTooLarge => return error.ModuleTooLarge,
                else => return error.InvalidFunctionReference,
            };
            defer replayed.deinit();
            const bytes = try replayed.assembleWithOptions(.{ .tier = options.policy.codegen_tier, .share_machine_code = options.policy.share_machine_code });
            if (!std.mem.eql(u8, result.bytes, bytes)) {
                allocator.free(bytes);
                return error.InvalidFunctionReference;
            }
            allocator.free(result.bytes);
            result.bytes = bytes;
        }
        result.artifacts = .{ .demands = metadata.jobs.items.len, .jobs = metadata.pools.?.functions.len, .functions = journal.functions.len, .helpers = journal.functions.len - metadata.pools.?.functions.len, .emission_events = journal.records.items.len, .metadata_events = metadata.events.items.len, .operation_symbols = journal.operations.items.len, .templates = metadata.pools.?.captures.len, .pinned_modules = metadata.pools.?.modules.len };
        if (options.artifact_dump) {
            try printArtifact(allocator, "ARTIFACT_JOBS", metadata.jobs.items);
            try printArtifact(allocator, "ARTIFACT_DEMAND_EVENTS", metadata.events.items);
            try printArtifact(allocator, "ARTIFACT_EMISSION", .{ .records = journal.records.items, .bytes = journal.bytes.items, .parameters = journal.parameters.items, .operations = journal.operations.items, .functions = journal.functions, .locals = journal.locals, .instructions = journal.instructions });
            const pools = &metadata.pools.?;
            for (pools.modules) |pin| try printArtifact(allocator, "ARTIFACT_MODULE_PIN", .{ .unit = pin.unit, .path = pin.canonical_path, .stamp = pin.stamp });
            try printArtifact(allocator, "ARTIFACT_OWNED_POOLS", .{ .project_identity = pools.project_identity, .identity = pools.identity, .bodies = pools.bodies, .layouts = pools.layouts, .evaluator = pools.evaluator, .rows = pools.rows, .templates = pools.templates, .captures = pools.captures, .bridge = pools.bridge, .field_locations = pools.field_locations, .field_locations_stamp = pools.field_locations_stamp, .functions = pools.functions, .serialized = pools.serialized, .runtime_globals = pools.runtime_globals, .runtime_order = pools.runtime_order, .operations = pools.operations, .operation_relocations = pools.operation_relocations, .operations_finalized = pools.operations_finalized });
            std.debug.print("ARTIFACT_METADATA {{\"demands\":{d},\"events\":{d},\"complete_functions\":{d},\"templates\":{d},\"pinned_modules\":{d}}}\n", .{ metadata.jobs.items.len, metadata.events.items.len, metadata.pools.?.functions.len, metadata.pools.?.captures.len, metadata.pools.?.modules.len });
            std.debug.print("ARTIFACT_REPLAY {{\"events\":{d},\"owned_bytes\":{d},\"functions\":{d},\"globals\":{d},\"imports\":{d},\"signatures\":{d},\"data_bytes\":{d},\"source_work_during_replay\":0,\"semantic_reuse\":false}}\n", .{ journal.records.items.len, journal.bytes.items.len, result.emitted_functions, globals, imports, signatures, data_bytes });
        }
    }
    if (options.retain_artifacts) {
        result.capture = .{ .metadata = metadata, .emission = journal, .cached_units = options.cached_units, .optimized = optimized };
        optimized = null;
        metadata_alive = false;
        journal_alive = false;
    }
    result.module_stamps = .{ .computed = module_stamps.computed, .reused = module_stamps.reused, .comparisons = module_stamps.comparisons, .copied = module_stamps.copied };
    timing.capture_us = clock.lap();
    result.timing = timing;
    return result;
}

fn printArtifact(allocator: Allocator, label: []const u8, value: anytype) Allocator.Error!void {
    const bytes = try std.json.Stringify.valueAlloc(allocator, value, .{ .emit_strings_as_arrays = true, .emit_nonportable_numbers_as_strings = true });
    defer allocator.free(bytes);
    std.debug.print("{s} {s}\n", .{ label, bytes });
}

fn entryInterfaceAdmissible(view: type_evidence.View, id: type_evidence.Id) bool {
    const node = view.node(id);
    if (node.tag != .function) return entryData(view, id, false);
    if (!entryData(view, node.b, true) or !entryForeign(view, node.c, false)) return false;
    if (entryData(view, node.a, true)) return true;
    const parameter = view.node(node.a);
    return parameter.tag == .function and entryData(view, parameter.a, true) and entryData(view, parameter.b, true) and entryForeign(view, parameter.c, true);
}
fn entryData(view: type_evidence.View, id: type_evidence.Id, arrays: bool) bool {
    const node = view.node(id);
    return switch (node.tag) {
        .unit, .boolean, .u32, .f32 => true,
        .array => arrays and switch (view.node(node.a).tag) {
            .u32, .f32 => true,
            else => false,
        },
        else => false,
    };
}
fn entryForeign(view: type_evidence.View, row: u32, exactly_one: bool) bool {
    const labels = view.effects.rowLabels(row);
    if (exactly_one and labels.len != 1) return false;
    for (labels) |label| {
        const operation = view.effects.operation(label);
        if (operation.identity.unit != 0 or operation.identity.decl != 1 or operation.arguments.len != 0) return false;
    }
    return true;
}
const entry_abi_rule = "entry functions take Unit, U32, F32, Bool, Array U32 or Array F32 (or one scalar/numeric-array callback with exactly ! {Foreign}), return one of those types and handle every other effect; entry values are Unit, U32, F32 or Bool";

/// Display only the already selected, closed source interface. A shape without
/// an owned source name keeps the existing fallback; rendering never resolves
/// a type, selects a method, evaluates a value, or changes inference order.
const EntryDisplay = struct {
    generator: *Generator,
    text: std.ArrayList(u8) = .empty,
    fn append(self: *EntryDisplay, bytes: []const u8) Allocator.Error!void {
        try self.text.appendSlice(self.generator.allocator, bytes);
    }
    fn qualified(self: *EntryDisplay, owner: u32, name: []const u8, saved_origin: []const u8) Allocator.Error!bool {
        const g = self.generator;
        if (owner == 0 or owner > g.units.len or name.len == 0) return false;
        const context = g.evaluator.diagnostic_context;
        var allocated_origin: ?[]u8 = null;
        defer if (allocated_origin) |origin| g.allocator.free(origin);
        const origin = if (context.identity) |identity| current: {
            if (owner == context.prelude and context.prelude != 0) break :current "std/prelude";
            if (context.source_mode and owner == context.entry) break :current "main";
            const entry_path = identity.owner(context.entry) orelse return false;
            const owner_path = identity.owner(owner) orelse return false;
            const directory = std.Io.Dir.path.dirname(entry_path) orelse return false;
            allocated_origin = try std.Io.Dir.path.relativeAlloc(g.allocator, directory, null, directory, owner_path);
            break :current allocated_origin.?;
        } else saved_origin;
        if (origin.len == 0) return false;
        try self.append(origin);
        try self.append("::");
        try self.append(name);
        return true;
    }
    fn nominal(self: *EntryDisplay, node: type_evidence.Node) Allocator.Error!bool {
        const g = self.generator;
        if (node.a == 0 or node.a > g.units.len) return false;
        const module = g.unit(node.a);
        const declaration = for (module.nominals) |item| {
            if (item.identity.decl == node.b and (item.identity.unit == 0 or item.identity.unit == node.a)) break item;
        } else return false;
        return self.qualified(node.a, module.name(declaration.diagnostic_name), module.name(declaration.diagnostic_origin));
    }
    fn operationName(self: *EntryDisplay, identity: types.NominalIdentity) Allocator.Error!bool {
        if (identity.unit == 0 and identity.decl == 1) {
            try self.append("blot:compiler::Foreign");
            return true;
        }
        const g = self.generator;
        if (identity.unit == 0 or identity.unit > g.units.len) return false;
        const module = g.unit(identity.unit);
        const declaration = for (module.operation_names) |item| {
            if (item.identity.decl == identity.decl and (item.identity.unit == 0 or item.identity.unit == identity.unit)) break item;
        } else return false;
        return self.qualified(identity.unit, module.name(declaration.diagnostic_name), module.name(declaration.diagnostic_origin));
    }
    fn children(self: *EntryDisplay, values: []const type_evidence.Id, depth: u8, arguments: bool) Allocator.Error!bool {
        if (depth == 0) {
            try self.append("...");
            return true;
        }
        if (values.len == 0) return true;
        if (arguments) try self.append(" (");
        if (!try self.ty(values[0], depth - 1)) return false;
        if (arguments) try self.append(")") else if (values.len > 1) try self.append(", ");
        if (!arguments and values.len == 1) return true;
        return self.children(values[1..], depth - 1, arguments);
    }
    fn row(self: *EntryDisplay, id: u32, depth: u8) Allocator.Error!bool {
        const view = self.generator.evaluator.evidenceView();
        const labels = view.effects.rowLabels(id);
        if (labels.len == 0) return true;
        try self.append(" ! {");
        for (labels, 0..) |label, index| {
            if (index != 0) try self.append(", ");
            const operation = view.effects.operation(label);
            if (!try self.operationName(operation.identity)) return false;
            for (view.effects.operationArguments(label)) |argument| {
                try self.append(" (");
                if (!try self.ty(argument, depth)) return false;
                try self.append(")");
            }
        }
        try self.append("}");
        return true;
    }
    fn ty(self: *EntryDisplay, id: type_evidence.Id, depth: u8) Allocator.Error!bool {
        if (depth == 0) {
            try self.append("...");
            return true;
        }
        const view = self.generator.evaluator.evidenceView();
        const node = view.node(id);
        switch (node.tag) {
            .unit => try self.append("Unit"),
            .boolean => try self.append("Bool"),
            .u32 => try self.append("U32"),
            .f32 => try self.append("F32"),
            .never => try self.append("Never"),
            .function => {
                try self.append("(");
                if (!try self.ty(node.a, depth - 1)) return false;
                try self.append(" -> ");
                if (!try self.ty(node.b, depth - 1) or !try self.row(node.c, depth - 1)) return false;
                try self.append(")");
            },
            .array, .list, .cursor => {
                try self.append(if (node.tag == .cursor) "Cursor (" else if (node.tag == .list) "List (" else "Array (");
                if (!try self.ty(node.a, depth - 1)) return false;
                try self.append(")");
            },
            .product => {
                try self.append("(");
                if (!try self.children(view.children(id), depth - 1, false)) return false;
                try self.append(")");
            },
            .nominal => {
                if (!try self.nominal(node)) return false;
                if (!try self.children(view.children(id), depth - 1, true)) return false;
            },
            else => return false,
        }
        return true;
    }
};
fn declineEntryInterface(g: *Generator, entry: u32, body: *const core.Body, header: core_eval.SourceInterface) Error {
    const point = g.unit(entry).sourceNamePoint(body.binding);
    const failure = g.decline(entry, .{ .start = point, .end = point }, if (body.runtime) .entry_let_type else .entry_type);
    if (!header.selected) {
        const name = g.unit(entry).name(body.export_name);
        const message = g.allocator.print("entry `{s}` has a generic type, so it cannot be a Wasm export: {s}", .{ name, entry_abi_rule }) catch return error.OutOfMemory;
        g.allocator.free(g.evaluator.owned_diagnostic_message);
        g.evaluator.owned_diagnostic_message = message;
        if (g.diagnostic) |*diagnostic| diagnostic.detail = message;
        return failure;
    }
    if (header.generic or header.evidence == 0) return failure;
    var display: EntryDisplay = .{ .generator = g };
    defer display.text.deinit(g.allocator);
    if (!(display.ty(header.evidence, 64) catch return error.OutOfMemory)) return failure;
    const name = g.unit(entry).name(body.export_name);
    const message = if (body.runtime)
        g.allocator.print("entry let `{s}` initializes a runtime value of type {s}; the guest ABI exports runtime-initialized values only as Unit, U32, F32 or Bool globals or as functions that fit it: {s}", .{ name, display.text.items, entry_abi_rule }) catch return error.OutOfMemory
    else
        g.allocator.print("entry `{s}` has type {s}, which does not fit the guest ABI: {s}", .{ name, display.text.items, entry_abi_rule }) catch return error.OutOfMemory;
    g.allocator.free(g.evaluator.owned_diagnostic_message);
    g.evaluator.owned_diagnostic_message = message;
    if (g.diagnostic) |*diagnostic| diagnostic.detail = message;
    return failure;
}
fn validateEntryInterfaces(g: *Generator, entry: u32) Error!void {
    const timing = g.work_timing.enter(.interfaces);
    defer timing.deinit();
    const unit_ = g.unit(entry);
    const headers = try g.allocator.alloc(core_eval.SourceInterface, unit_.bodies.len);
    defer g.allocator.free(headers);
    @memset(headers, .{});
    // Source selection owns every requested interface before any ABI rejection
    // or ordinary constant value. Frozen catalog order is functions, constants.
    for ([_]bool{ true, false }) |functions| for (unit_.bodies[1..], 1..) |*body, index| {
        if (!body.exported or body.is_function != functions) continue;
        const target: core.BindingRef = .{ .unit = entry, .binding = body.binding };
        const before = g.evaluator.steps;
        headers[index] = g.evaluator.sourceInterface(target) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.RequestUnwind, error.Declined => return g.evaluationFailure(),
        };
        std.debug.assert(g.evaluator.steps == before);
    };
    for ([_]bool{ true, false }) |functions| for (unit_.bodies[1..], 1..) |*body, index| {
        if (!body.exported or body.is_function != functions) continue;
        const header = headers[index];
        if (!header.selected or header.generic or (header.evidence != 0 and !entryInterfaceAdmissible(g.evaluator.evidenceView(), header.evidence))) {
            return declineEntryInterface(g, entry, body, header);
        }
        // Residual source dispatch keeps the ordinary complete-proof path.
        // It is not a reusable source-interface certificate.
    };
}

/// Source selection and runtime value retention differ. All selected runtime
/// initializer cells are roots; ordinary constants contribute their completed
/// value graphs. Planning reads immutable owned Core and never spends fuel.
fn addStartupSelections(g: *Generator, target: core.BindingRef, processed: *std.AutoHashMapUnmanaged(core.BindingRef, void), selections: *std.ArrayList(startup_graph.Selection), confirmed: *bool) Error!void {
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

fn planRuntime(g: *Generator, entry: u32, supplied_order: []const u32) Error!void {
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
        g.runtime_plan_confirmed = confirmed or occurrence != null;
        g.occurrence_plan_active = occurrence != null;
        g.occurrence_plan_cells = if (occurrence != null) plan.initializers else &.{};
        // Entry emission may discover additional cells through its own method
        // selection. Its on-demand path has no initializer-plan certificate.
        defer g.runtime_plan_confirmed = false;
        defer g.occurrence_plan_active = false;
        defer g.occurrence_plan_cells = &.{};
        for (plan.initializers) |target| _ = try g.runtimeGlobal(target);
        if (g.runtime_plan_confirmed) for (plan.initializers) |target| try g.emitRuntimeInitializer(target);
        var slots = g.runtime_globals.iterator();
        while (slots.next()) |slot| if (slot.value_ptr.active) return error.InvalidGlobalReference;
        return;
    }
}

fn generate(g: *Generator, entry: u32, unit_order: []const u32) Error!void {
    if (entry == 0 or entry > g.units.len) return g.decline(1, .{ .start = 0, .end = 0 }, .unsupported);
    const unit_ = g.unit(entry);
    var exports: usize = 0;
    {
        const timing = g.work_timing.enter(.principals);
        defer timing.deinit();
        try validateEntryInterfaces(g, entry);
        // Ordinary entry constants all finish before startup planning or any
        // executable body can demand a runtime global. Source interfaces above
        // have already selected and validated the complete entry boundary.
        for ([_]bool{ true, false }) |functions| for (unit_.bodies[1..]) |*body| {
            if (!body.exported or body.is_function != functions) continue;
            exports += 1;
            g.evaluator.prepare(.{ .unit = entry, .binding = body.binding }) catch |err| switch (err) {
                error.RequestUnwind, error.Declined => return g.evaluationFailure(),
                error.OutOfMemory => return error.OutOfMemory,
            };
        };
        if (exports == 0) return g.decline(entry, .{ .start = 0, .end = 0 }, .no_entry);
    }
    {
        const timing = g.work_timing.enter(.startup);
        defer timing.deinit();
        try planRuntime(g, entry, unit_order);
    }
    for (unit_.bodies[1..]) |*body| {
        if (!body.exported) continue;
        const target: core.BindingRef = .{ .unit = entry, .binding = body.binding };
        if (body.is_function or unit_.types.node(unit_.binding(body.binding).ty).tag == .function) {
            const key = try g.entrySignature(target, body.scheme.root, body.span);
            if (key.count != 1 or !g.foreignRow(key.effects[0], false)) return g.decline(entry, body.span, .entry_type);
            const result = g.layouts.abi(key.result) orelse return g.decline(entry, body.span, .entry_type);
            const callback = g.hostCallback(key.parameters[0]);
            const parameter = g.layouts.abi(key.parameters[0]);
            if (callback == null and parameter == null) return g.decline(entry, body.span, .entry_type);
            const function_id = try g.function(key);
            if (callback) |host| {
                try g.module.exportCallbackFunction(try g.entryCallbackFunction(function_id, key.parameters[0], result), unit_.name(body.export_name), host, result);
            } else {
                try g.module.exportFunction(try g.entryFunction(function_id, parameter.?, result), unit_.name(body.export_name), parameter.?, result);
            }
        } else if (body.runtime) {
            const concrete = try g.typeLayout(entry, body.scheme.root, &.{}, body.span);
            const scalar_ = g.layouts.abi(concrete) orelse return g.decline(entry, body.span, .entry_type);
            if (scalar_ == .array_u32 or scalar_ == .array_f32) return g.decline(entry, body.span, .entry_type);
            try g.module.exportGlobal(try g.runtimeGlobal(target), unit_.name(body.export_name));
        } else {
            // Deferred source dispatch can establish the scalar's type while
            // evaluating its retained body. The cached value owns that proof;
            // no aggregate layout or caller-selected type is needed to export it.
            const evaluated = g.evaluator.richValue(target) catch |err| switch (err) {
                error.RequestUnwind => return g.evaluationFailure(),
                error.Declined => return g.evaluationFailure(),
                error.OutOfMemory => return error.OutOfMemory,
            };
            const value = g.evaluator.valueScalar(evaluated) orelse return g.decline(entry, body.span, .entry_type);
            try g.module.exportConstant(unit_.name(body.export_name), value.scalar, value.bits);
        }
    }
    if (exports == 0) return g.decline(entry, .{ .start = 0, .end = 0 }, .no_entry);
}

const ReturnTarget = struct { node: core.Id, label: u32, cleanup: runtime_cleanup.Mark, template_result: bool = false };
const LoopTarget = struct { node: core.Id, label: u32, cleanup: runtime_cleanup.Mark };
const Template = struct { unit: u32 = 0, node: core.Id, environment: ?u32 = null, captures: layout.Id = 0, templates: substitution_keys.Id = 0, computation: bool = false, evidence: u32 = 0, rows: substitution_keys.Id = 0 };
const Emitter = struct {
    const LayoutEntry = struct { ty: types.Id = 0, value: layout.Id = 0 };
    const SmallCollection = struct { values: [function_facts.small_limit]u32 = undefined, len: usize = 0, machine: wasm.ValueType = .i32 };
    small_values: std.AutoHashMapUnmanaged(core.BindingId, SmallCollection) = .empty,
    small_result: ?struct { root: core.Id, value: *SmallCollection } = null,
    analysis_root: core.Id = 0,
    exact_probe: bool = false,
    exact_build: ?struct { plan: exact_builder.Plan, storage: u32, index: u32, row_words: u32 } = null,
    generator: *Generator,
    unit_id: u32,
    function_id: u32,
    /// Dynamic provider scope is an invocation argument, never a capture.
    provider_local: ?u32 = null,
    mappings: []const Mapping,
    row_mappings: []const RowMapping = &.{},
    locals: std.AutoHashMapUnmanaged(core.BindingId, u32) = .empty,
    cleanups: runtime_cleanup.Stack = .{},
    return_targets: std.ArrayList(ReturnTarget) = .empty,
    loop_targets: std.ArrayList(LoopTarget) = .empty,
    labels: u32 = 0,
    templates: std.AutoHashMapUnmanaged(core.BindingId, Template) = .empty,
    static_values: std.AutoHashMapUnmanaged(core.BindingId, core_eval.ValueId) = .empty,
    computation_values: std.AutoHashMapUnmanaged(core.BindingId, layout.Id) = .empty,
    result_template: ?u32 = null,
    factory_template: bool = false,
    inline_demands: []const InlineDemand = &.{},
    owned_edit: ?core.Id = null,
    inline_depth: u8 = 0,
    inline_loop: bool = false,

    // Source owner and mappings are immutable for this emitter's lifetime.
    // Cache only completed root conversions, preserving recursive work limits.
    layout_cache: [32]LayoutEntry = @splat(.{}),

    fn codeLayout(self: *Emitter, ty: types.Id, span: core.Span) Error!layout.Id {
        const g = self.generator;
        g.facts.stats.layout_requests += 1;
        const slot = &self.layout_cache[ty % self.layout_cache.len];
        if (slot.ty == ty and slot.value != 0) {
            g.facts.stats.layout_reused += 1;
            return slot.value;
        }
        const result = try g.codeLayoutWithRows(self.unit_id, ty, self.mappings, self.row_mappings, span);
        slot.* = .{ .ty = ty, .value = result };
        return result;
    }

    const InlineDemand = struct {
        binding: core.BindingId,
        caller: *Emitter,
        expression: core.Id,
        value: ?u32 = null,
        ready: ?u32 = null,
        machine: wasm.ValueType,
    };

    // Every forwarded call must keep its demand arguments as local expressions.
    // Check their concrete signatures before emitting any outer arguments, so a
    // later fallback cannot try to materialize an elided outer demand cell.
    fn demandCallShapes(self: *Emitter, unit_id: u32, plan: *const @import("demand_inline.zig").Plan, mappings: []const Mapping, rows: []const RowMapping, depth: usize) Error!bool {
        if (depth >= 96) return false;
        const g = self.generator;
        const source = g.unit(unit_id);
        for (plan.calls[0..plan.call_count]) |id| {
            const call = source.call(id);
            const key = try g.signature(call.target, call.callee_type, unit_id, mappings, rows, source.span(id), false);
            const target = g.unit(key.target.unit);
            const body = target.body(key.target.binding) orelse return false;
            if (key.count != call.arguments.len or key.count != body.parameters.len) return false;
            const child = @import("demand_inline.zig").Plan.init(target, body) orelse return false;
            for (call.arguments, 0..) |argument, i| {
                if (self.hasErasedType(key.parameters[i], 0)) return false;
                if (g.layouts.node(key.parameters[i]).tag == .demand and source.node(argument).tag != .suspend_) return false;
            }
            var next_mappings: std.ArrayList(Mapping) = .empty;
            var next_rows: std.ArrayList(RowMapping) = .empty;
            defer next_mappings.deinit(g.allocator);
            defer next_rows.deinit(g.allocator);
            for (target.bodyParameters(body), 0..) |parameter, i| {
                try g.mapTypeDepth(key.target.unit, &next_mappings, &next_rows, parameter.ty, key.parameters[i], body.span, 0);
            }
            try g.mapTypeDepth(key.target.unit, &next_mappings, &next_rows, target.typeOf(body.root), key.result, body.span, 0);
            if (!try self.demandCallShapes(key.target.unit, &child, next_mappings.items, next_rows.items, depth + 1)) return false;
        }
        return true;
    }

    fn inlineDemandCall(self: *Emitter, key: Key, arguments: []const core.Id, depth: usize) Error!bool {
        const g = self.generator;
        const source = g.unit(key.target.unit);
        const body = source.body(key.target.binding) orelse return false;
        if (arguments.len != key.count or body.parameters.len != key.count) return false;
        const plan = @import("demand_inline.zig").Plan.init(source, body) orelse return false;
        const caller = g.unit(self.unit_id);
        for (arguments, 0..) |argument, i| {
            if (self.hasErasedType(key.parameters[i], 0)) return false;
            if (g.layouts.node(key.parameters[i]).tag == .demand and caller.node(argument).tag != .suspend_) return false;
        }
        var mappings: std.ArrayList(Mapping) = .empty;
        var rows: std.ArrayList(RowMapping) = .empty;
        defer mappings.deinit(g.allocator);
        defer rows.deinit(g.allocator);
        for (source.bodyParameters(body), 0..) |parameter, i| {
            try g.mapTypeDepth(key.target.unit, &mappings, &rows, parameter.ty, key.parameters[i], body.span, 0);
        }
        try g.mapTypeDepth(key.target.unit, &mappings, &rows, source.typeOf(body.root), key.result, body.span, 0);
        if (!try self.demandCallShapes(key.target.unit, &plan, mappings.items, rows.items, 0)) return false;
        if (g.artifacts) |artifacts| try artifacts.readInlineBody(key.target);
        var emitter: Emitter = .{ .generator = g, .unit_id = key.target.unit, .function_id = self.function_id, .provider_local = self.provider_local, .mappings = mappings.items, .row_mappings = rows.items, .cleanups = .{ .parent = &self.cleanups }, .labels = self.labels };
        defer emitter.deinit();
        var demands: [max_parameters]InlineDemand = undefined;
        var count: usize = 0;
        // Eager arguments still run once, left to right. Deferred expressions
        // retain the caller's immutable binding versions, without an object.
        for (arguments, source.bodyParameters(body), 0..) |argument, parameter, i| {
            const ty = g.layouts.node(key.parameters[i]);
            if (ty.tag != .demand) {
                const local = try self.capture(argument, depth);
                if (parameter.binding != 0) try emitter.locals.put(g.allocator, parameter.binding, local);
                continue;
            }
            if (plan.uses[i] == 0) continue;
            const machine = g.layouts.machine(ty.a);
            const memo = plan.uses[i] > 1;
            demands[count] = .{
                .binding = parameter.binding,
                .caller = self,
                .expression = caller.closures[caller.node(argument).a].body,
                .value = if (memo) try self.temporary(machine) else null,
                .ready = if (memo) try self.temporary(.i32) else null,
                .machine = machine,
            };
            // The call may occur inside a loop; Wasm local initialization alone
            // would incorrectly share a result across successive invocations.
            if (demands[count].ready) |ready| {
                try self.emit(.i32_const, 0);
                try self.emit(.local_set, ready);
            }
            count += 1;
        }
        emitter.inline_demands = demands[0..count];
        try emitter.expression(body.root, depth + 1);
        return true;
    }

    fn inlineDemand(self: *Emitter, id: core.Id, depth: usize) Error!bool {
        const source = self.generator.unit(self.unit_id);
        const operand = source.node(id).a;
        if (source.node(operand).tag != .reference) return false;
        const reference = source.reference(operand);
        if (reference.unit != 0 and reference.unit != self.unit_id) return false;
        for (self.inline_demands) |demand| {
            if (demand.binding != reference.binding) continue;
            if (demand.ready) |ready| {
                try self.emit(.local_get, ready);
                try self.emit(.if_, @backingInt(demand.machine));
                self.labels += 1;
                try self.emit(.local_get, demand.value.?);
                try self.emit(.else_, 0);
            }
            // The caller emits the deferred expression in its lexical scope,
            // at the current branch depth and with the force-site providers.
            // demand_inline excludes handlers, so no intervening private cleanup
            // scopes exist between this emitter and the lexical caller.
            const saved_labels = demand.caller.labels;
            demand.caller.labels = self.labels;
            defer demand.caller.labels = saved_labels;
            try demand.caller.expression(demand.expression, depth + 1);
            if (demand.ready) |ready| {
                try self.emit(.local_set, demand.value.?);
                try self.emit(.i32_const, 1);
                try self.emit(.local_set, ready);
                try self.emit(.local_get, demand.value.?);
                self.labels -= 1;
                try self.emit(.end, 0);
            }
            return true;
        }
        return false;
    }

    fn inlineCollectionEdit(self: *Emitter, id: core.Id, key: Key, depth: usize) Error!bool {
        const g = self.generator;
        const plan = @import("collection_edit_call.zig").analyze(g.units, self.unit_id, id) orelse return false;
        if (key.count != plan.count or !std.meta.eql(plan.target, key.target)) return false;
        for (key.parameters[0..key.count]) |ty| if (self.hasErasedType(ty, 0)) return false;
        if (g.artifacts) |artifacts| try artifacts.readInlineBody(plan.target);
        const source = g.unit(self.unit_id);
        var values: [3]u32 = undefined;
        for (plan.arguments[0..plan.count], 0..) |argument, i| values[i] = try self.capture(argument, depth);
        if (plan.success != null) {
            const producer = g.unit(plan.target.unit);
            const body = producer.body(plan.target.binding).?;
            var mappings: std.ArrayList(Mapping) = .empty;
            var rows: std.ArrayList(RowMapping) = .empty;
            defer mappings.deinit(g.allocator);
            defer rows.deinit(g.allocator);
            for (producer.bodyParameters(body), 0..) |parameter, i| try g.mapTypeDepth(plan.target.unit, &mappings, &rows, parameter.ty, key.parameters[i], body.span, 0);
            try g.mapTypeDepth(plan.target.unit, &mappings, &rows, producer.typeOf(body.root), key.result, body.span, 0);
            var emitter: Emitter = .{ .generator = g, .unit_id = plan.target.unit, .function_id = self.function_id, .provider_local = self.provider_local, .mappings = mappings.items, .row_mappings = rows.items, .cleanups = .{ .parent = &self.cleanups }, .labels = self.labels, .owned_edit = if (try g.ownsArrayUpdate(self.unit_id, id)) plan.edit else null };
            defer emitter.deinit();
            for (producer.bodyParameters(body), 0..) |parameter, i| if (parameter.binding != 0) try emitter.locals.put(g.allocator, parameter.binding, values[i]);
            try emitter.expression(body.root, depth + 1);
            return true;
        }
        const order = plan.positions;
        const result = try self.codeLayout(source.typeOf(id), source.span(id));
        var operands: [3]u32 = undefined;
        var machines: [3]wasm.ValueType = undefined;
        for (order[0..plan.count], 0..) |position, i| {
            operands[i] = values[position];
            machines[i] = g.layouts.machine(key.parameters[position]);
        }
        try self.arrayLocals(id, plan.op, operands[0..plan.count], machines[0..plan.count], result, key.parameters[order[0]]);
        return true;
    }

    fn inlineNamedCall(self: *Emitter, key: Key, arguments: []const core.Id, depth: usize) Error!bool {
        return self.inlineNamedValues(key, arguments, null, depth);
    }
    fn inlineNamedValues(self: *Emitter, key: Key, arguments: []const core.Id, captured: ?[]const u32, depth: usize) Error!bool {
        return self.inlineNamedValuesMode(key, arguments, captured, depth, null);
    }
    // Preparation owns the large mapping/initialization frame. It returns
    // before recursively emitting an inlined body, so deep call graphs retain
    // only the small emission continuation on the native stack.
    fn prepareNamedInline(self: *Emitter, key: Key, arguments: []const core.Id, captured: ?[]const u32, small_result: ?*SmallCollection, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), borrowed_collections: *u16) Error!?*Emitter {
        const g = self.generator;
        if (self.inline_depth >= 6 or g.module.functions.items[self.function_id].instructions.items.len > 4096 or (if (captured) |values| values.len != key.count else arguments.len < key.count) or key.templates != 0 or key.template_result) return null;
        const source = g.unit(key.target.unit);
        const body = source.body(key.target.binding) orelse return null;
        const facts = try g.facts.get(g.allocator, g.units, key.target);
        borrowed_collections.* = facts.borrowed_collections;
        const in_loop = self.inline_loop or self.loop_targets.items.len != 0;
        var expose_data = small_result != null or (in_loop and self.inlineDataType(key.result));
        if (captured == null) for (key.parameters[0..key.count], arguments[0..key.count], 0..) |ty, argument, i| {
            expose_data = expose_data or (g.layouts.node(ty).tag == .function and self.isCallableTemplate(argument));
            if (i < 16 and facts.borrowed_collections & (@as(u16, 1) << @intCast(i)) != 0 and self.smallCollectionCandidate(argument)) expose_data = true;
        };
        if (!body.is_function or body.parameters.len != key.count or (facts.inline_cost orelse return null) > (if (expose_data) @as(u16, 64) else 4) or self.hasErasedType(key.result, 0)) return null;
        for (key.parameters[0..key.count]) |ty| if (self.hasErasedType(ty, 0) or g.layouts.node(ty).tag == .demand) return null;
        var source_type = source.binding(key.target.binding).ty;
        for (key.parameters[0..key.count], 0..) |ty, i| {
            const arrow = source.types.node(source_type);
            try g.mapTypeDepth(key.target.unit, mappings, rows, arrow.a, ty, body.span, 0);
            try g.mapRow(key.target.unit, mappings, rows, arrow.c, key.effects[i], body.span, true);
            source_type = arrow.b;
        }
        try g.mapTypeDepth(key.target.unit, mappings, rows, source_type, key.result, body.span, 0);
        var full = key.result;
        var reverse: usize = key.count;
        while (reverse != 0) {
            reverse -= 1;
            full = try g.internLayoutWithEffects(.function, key.parameters[reverse], full, key.effects[reverse], &.{});
        }
        try g.refineMappings(key.target.unit, .{ .body = key.target }, full, mappings, rows, body.span);
        if (g.artifacts) |artifacts| try artifacts.readInlineBody(key.target);
        const emitter = try g.allocator.create(Emitter);
        emitter.* = .{ .generator = g, .unit_id = key.target.unit, .function_id = self.function_id, .provider_local = self.provider_local, .mappings = mappings.items, .row_mappings = rows.items, .cleanups = .{ .parent = &self.cleanups }, .labels = self.labels, .inline_depth = self.inline_depth + 1, .inline_loop = in_loop };
        if (small_result) |result| emitter.small_result = .{ .root = body.root, .value = result };
        return emitter;
    }
    fn inlineNamedValuesMode(self: *Emitter, key: Key, arguments: []const core.Id, captured: ?[]const u32, depth: usize, small_result: ?*SmallCollection) Error!bool {
        const g = self.generator;
        var mappings: std.ArrayList(Mapping) = .empty;
        var rows: std.ArrayList(RowMapping) = .empty;
        defer mappings.deinit(g.allocator);
        defer rows.deinit(g.allocator);
        var borrowed_collections: u16 = 0;
        const emitter = try self.prepareNamedInline(key, arguments, captured, small_result, &mappings, &rows, &borrowed_collections) orelse return false;
        const source = g.unit(key.target.unit);
        const body = source.body(key.target.binding).?;
        defer {
            emitter.deinit();
            g.allocator.destroy(emitter);
        }
        for (source.bodyParameters(body), 0..) |parameter, i| {
            if (captured) |values| {
                if (parameter.binding != 0) try emitter.locals.put(g.allocator, parameter.binding, values[i]);
                continue;
            }
            const argument = arguments[i];
            if (i < 16 and borrowed_collections & (@as(u16, 1) << @intCast(i)) != 0) if (try self.captureSmallCollection(argument, depth)) |values| {
                if (parameter.binding != 0) try emitter.small_values.put(g.allocator, parameter.binding, values);
                continue;
            };
            if (g.layouts.node(key.parameters[i]).tag == .function and self.static_values.count() == 0 and self.isCallableTemplate(argument)) {
                const template = (try self.callableTemplate(argument)).?;
                if (parameter.binding != 0) try emitter.templates.put(g.allocator, parameter.binding, template);
            } else {
                const value = try self.capture(argument, depth);
                if (parameter.binding != 0) try emitter.locals.put(g.allocator, parameter.binding, value);
            }
        }
        const remaining = if (captured != null) &.{} else arguments[key.count..];
        if (remaining.len != 0 and try emitter.saturatedAssociated(body.root, self, remaining, depth)) return true;
        try emitter.expression(body.root, depth + 1);
        var ty = key.result;
        for (remaining) |argument| {
            const arrow = g.layouts.node(ty);
            const callee = try self.temporary(.i32);
            try self.emit(.local_set, callee);
            const value = try self.capture(argument, depth);
            try self.emit(.local_get, callee);
            try self.emit(.i32_load, heap.offset(heap.Closure, "environment"));
            try self.emit(.local_get, value);
            try self.providerHead();
            try self.emit(.local_get, callee);
            try self.emit(.i32_load, heap.offset(heap.Closure, "function"));
            try self.emit(.call_indirect, try g.module.internType(&.{ .i32, g.layouts.machine(arrow.a), .i32 }, g.layouts.machine(arrow.b)));
            ty = arrow.b;
        }
        return true;
    }

    fn inlineDataType(self: *const Emitter, ty: layout.Id) bool {
        return switch (self.generator.layouts.node(ty).tag) {
            .record, .product, .nominal, .cursor => true,
            else => false,
        };
    }

    // Fuse a fully supplied method selected by an ordinary source adapter.
    // Selection and type evidence remain the same as the curried call path.
    fn saturatedAssociated(self: *Emitter, id: core.Id, caller: *Emitter, extra: []const core.Id, depth: usize) Error!bool {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        if (node.tag != .associated or node.op != .none or extra.len + 2 > max_parameters) return false;
        const left = try self.codeLayout(source.typeOf(node.a), source.span(id));
        const right = try self.codeLayout(source.typeOf(node.b), source.span(id));
        const result = try self.codeLayout(node.ty, source.span(id));
        const identity = self.dispatchIdentity(left) orelse return false;
        var key = (try self.dispatchCandidate(id, identity, .none, node.c, left, right, result)) orelse return false;
        const body = g.unit(key.target.unit).body(key.target.binding) orelse return false;
        if (!body.is_function or body.parameters.len != extra.len + 2) return false;
        var result_type = result;
        for (extra, 2..) |_, i| {
            const arrow = g.layouts.node(result_type);
            if (arrow.tag != .function) return false;
            key.parameters[i] = arrow.a;
            key.effects[i] = arrow.c;
            result_type = arrow.b;
        }
        key.count = @intCast(extra.len + 2);
        key.result = result_type;
        var values: [max_parameters]u32 = undefined;
        values[0] = try self.capture(node.a, depth);
        values[1] = try self.capture(node.b, depth);
        for (extra, 2..) |argument, i| values[i] = try caller.capture(argument, depth);
        if (!try self.inlineNamedValues(key, &.{}, values[0..key.count], depth)) {
            const function = try g.function(key);
            for (values[0..key.count]) |value| try self.emit(.local_get, value);
            try self.providerHead();
            try self.emit(.call, function);
        }
        return true;
    }

    fn hasErasedType(self: *const Emitter, ty: layout.Id, depth: usize) bool {
        if (depth >= 128) return true;
        const layouts = &self.generator.layouts;
        const node = layouts.node(ty);
        return switch (node.tag) {
            .erased, .invalid => true,
            .function => self.hasErasedType(node.a, depth + 1) or self.hasErasedType(node.b, depth + 1),
            .array, .list, .cursor, .demand, .provider, .resolver => self.hasErasedType(node.a, depth + 1),
            .state_provider => self.hasErasedType(node.a, depth + 1) or self.hasErasedType(node.b, depth + 1) or self.hasErasedType(node.c, depth + 1),
            .product, .nominal => blk: {
                for (layouts.children(ty)) |child| if (self.hasErasedType(child, depth + 1)) break :blk true;
                break :blk false;
            },
            .record => blk: {
                const children = layouts.children(ty);
                var i: usize = 1;
                while (i < children.len) : (i += 2) if (self.hasErasedType(children[i], depth + 1)) break :blk true;
                break :blk false;
            },
            else => false,
        };
    }
    fn staticReference(self: *Emitter, id: core.Id) Error!?core_eval.ValueId {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        if (source.node(id).tag != .reference) return null;
        const reference = source.reference(id);
        if (reference.unit == 0 or reference.unit == self.unit_id) {
            if (self.static_values.get(reference.binding)) |value| return value;
            if (self.locals.contains(reference.binding) or self.templates.contains(reference.binding)) return null;
            const kind = source.binding(reference.binding).kind;
            if (kind != .global and kind != .external) return null;
        }
        const target = try g.normalize(self.unit_id, reference);
        const body = g.unit(target.unit).body(target.binding) orelse return null;
        if (body.runtime or body.is_function) return null;
        const value = g.evaluator.richValue(target) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.evaluationFailure();
        if (g.artifacts) |artifacts| try artifacts.readStaticValue(target, value);
        return value;
    }
    /// A constant record may contain polymorphic fields which this call never
    /// observes. Keep that value in the compiler while lowering the selected
    /// body; materialize each selected field with its own concrete use type.
    fn inlineStaticCall(self: *Emitter, key: Key, arguments: []const core.Id, depth: usize) Error!bool {
        const g = self.generator;
        if (arguments.len > key.count) return false;
        const source = g.unit(key.target.unit);
        const body = source.body(key.target.binding) orelse return false;
        if (!body.is_function or body.parameters.len != key.count) return false;
        var values: [max_parameters]?core_eval.ValueId = @splat(null);
        var retained = false;
        for (arguments, 0..) |argument, i| {
            if (!self.hasErasedType(key.parameters[i], 0)) continue;
            values[i] = try self.staticReference(argument);
            retained = retained or values[i] != null;
        }
        if (!retained) return false;
        if (g.artifacts) |artifacts| try artifacts.readInlineBody(key.target);
        if (g.artifacts) |artifacts| if (!artifacts.hasStaticValues()) {
            artifacts.requireFreshCode();
        };
        if (g.instance_depth >= 256) return g.decline(key.target.unit, body.span, .complexity);
        g.instance_depth += 1;
        defer g.instance_depth -= 1;
        var mappings: std.ArrayList(Mapping) = .empty;
        var rows: std.ArrayList(RowMapping) = .empty;
        defer mappings.deinit(g.allocator);
        defer rows.deinit(g.allocator);
        var full = key.result;
        var i: usize = key.count;
        while (i != 0) {
            i -= 1;
            full = try g.internLayoutWithEffects(.function, key.parameters[i], full, key.effects[i], &.{});
        }
        var source_type = source.binding(key.target.binding).ty;
        for (key.parameters[0..key.count], 0..) |parameter_type, index| {
            const arrow = source.types.node(source_type);
            if (arrow.tag != .function) return g.decline(key.target.unit, body.span, .unresolved_type);
            try g.mapTypeDepth(key.target.unit, &mappings, &rows, arrow.a, parameter_type, body.span, 0);
            try g.mapRow(key.target.unit, &mappings, &rows, arrow.c, key.effects[index], body.span, true);
            source_type = arrow.b;
        }
        try g.mapTypeDepth(key.target.unit, &mappings, &rows, source_type, key.result, body.span, 0);
        try g.refineMappings(key.target.unit, .{ .body = key.target }, full, &mappings, &rows, body.span);
        var emitter: Emitter = .{ .generator = g, .unit_id = key.target.unit, .function_id = self.function_id, .provider_local = self.provider_local, .mappings = mappings.items, .row_mappings = rows.items, .cleanups = .{ .parent = &self.cleanups }, .labels = self.labels };
        defer emitter.deinit();
        // Preserve left-to-right evaluation of every dynamic argument.
        for (arguments, source.bodyParameters(body)[0..arguments.len], 0..) |argument, parameter, index| {
            if (values[index]) |value| {
                if (parameter.binding != 0) try emitter.static_values.put(g.allocator, parameter.binding, value);
            } else {
                const local = try self.capture(argument, depth);
                if (parameter.binding != 0) try emitter.locals.put(g.allocator, parameter.binding, local);
            }
        }
        try emitter.finishStaticCall(key, arguments.len, depth);
        return true;
    }
    /// Each remaining arrow receives its dynamic argument at runtime. Static
    /// parameters stay in the emitter; dynamic captures retain their order and
    /// are stored once in the ordinary closure environment.
    fn finishStaticCall(self: *Emitter, key: Key, supplied: usize, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(key.target.unit);
        const body = source.body(key.target.binding).?;
        if (supplied == key.count) {
            try self.expression(body.root, depth + 1);
            if (source.types.node(source.typeOf(body.root)).tag == .never) try self.emit(.unreachable_, 0);
            return;
        }
        const result_machine = if (supplied + 1 == key.count) g.layouts.machine(key.result) else .i32;
        const function_id = try g.module.addFunction(&.{ .i32, g.layouts.machine(key.parameters[supplied]), .i32 }, result_machine);
        try g.static_closures.append(g.allocator, function_id);
        g.work.fresh_closures += 1;
        try g.startup_facts.request(g.allocator, function_id, .named, key.target.unit, key.target.binding, false);
        var emitter: Emitter = .{ .generator = g, .unit_id = key.target.unit, .function_id = function_id, .provider_local = 2, .mappings = self.mappings, .row_mappings = self.row_mappings };
        defer emitter.deinit();
        const environment = try self.allocate(@intCast(supplied * 4));
        const parameters = source.bodyParameters(body);
        for (parameters[0..supplied], 0..) |parameter, index| {
            const value = self.static_values.get(parameter.binding);
            try self.emit(.local_get, environment);
            if (value != null or parameter.binding == 0) {
                try self.emit(.i32_const, 0);
                try self.emit(.i32_store, @intCast(index * 4));
                if (value) |static_value| try emitter.static_values.put(g.allocator, parameter.binding, static_value);
            } else {
                const machine = g.layouts.machine(key.parameters[index]);
                try self.emit(.local_get, self.locals.get(parameter.binding).?);
                try self.emit(if (machine == .f32) .f32_store else .i32_store, @intCast(index * 4));
                const local = try emitter.temporary(machine);
                try emitter.emit(.local_get, 0);
                try emitter.emit(if (machine == .f32) .f32_load else .i32_load, @intCast(index * 4));
                try emitter.emit(.local_set, local);
                try emitter.locals.put(g.allocator, parameter.binding, local);
            }
        }
        if (parameters[supplied].binding != 0) try emitter.locals.put(g.allocator, parameters[supplied].binding, 1);
        const caller = g.startup_facts.active;
        g.startup_facts.active = function_id;
        defer g.startup_facts.active = caller;
        try emitter.finishStaticCall(key, supplied + 1, depth);
        g.startup_facts.complete(function_id);
        g.startup_facts.active = caller;
        try self.descriptor(function_id, environment);
    }
    fn partialStaticCall(self: *Emitter, id: core.Id, depth: usize) Error!bool {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        var reversed: [max_parameters]core.Id = undefined;
        var count: usize = 0;
        var root = id;
        while (source.node(root).tag == .apply) {
            if (count == max_parameters) return false;
            const node = source.node(root);
            reversed[count] = node.b;
            count += 1;
            root = node.a;
        }
        if (source.node(root).tag != .reference) return false;
        const reference = source.reference(root);
        if (reference.unit == 0 or reference.unit == self.unit_id) {
            if (self.locals.contains(reference.binding) or self.templates.contains(reference.binding) or self.static_values.contains(reference.binding)) return false;
            const kind = source.binding(reference.binding).kind;
            if (kind != .global and kind != .external) return false;
        }
        const target = try g.normalize(self.unit_id, reference);
        const body = g.unit(target.unit).body(target.binding) orelse return false;
        if (!body.is_function or count >= body.parameters.len) return false;
        const key = try g.signature(target, source.typeOf(root), self.unit_id, self.mappings, self.row_mappings, source.span(id), false);
        std.mem.reverse(core.Id, reversed[0..count]);
        return self.inlineStaticCall(key, reversed[0..count], depth);
    }

    fn operationConstant(self: *Emitter, operation: runtime_operations.Id) Error!void {
        self.generator.runtime_operations.emit(&self.generator.module, self.function_id, operation) catch |err| switch (err) {
            error.InvalidOperation => return error.InvalidFunctionReference,
            error.OutOfMemory => return error.OutOfMemory,
            error.ModuleTooLarge => return error.ModuleTooLarge,
        };
    }
    fn deinit(self: *Emitter) void {
        self.small_values.deinit(self.generator.allocator);
        self.locals.deinit(self.generator.allocator);
        self.cleanups.deinit(self.generator.allocator);
        self.return_targets.deinit(self.generator.allocator);
        self.loop_targets.deinit(self.generator.allocator);
        self.templates.deinit(self.generator.allocator);
        self.static_values.deinit(self.generator.allocator);
        self.computation_values.deinit(self.generator.allocator);
    }
    fn emit(self: *Emitter, op: wasm.Op, operand: u32) Error!void {
        try self.generator.module.emit(self.function_id, .{ .op = op, .operand = operand });
        if (op == .call or op == .call_indirect or op == .call_import) {
            if (self.generator.request_owner) |owner| try request_runtime.guard(&self.generator.module, self.function_id, owner, &self.cleanups);
        }
    }
    fn referenceConstant(self: *Emitter, value: u32, role: artifact_emitter.Role) Error!void {
        try self.generator.module.emitReference(self.function_id, .{ .op = .i32_const, .operand = value }, role);
    }
    fn emitUnguarded(self: *Emitter, op: wasm.Op, operand: u32) Error!void {
        try self.generator.module.emit(self.function_id, .{ .op = op, .operand = operand });
    }
    fn providerHead(self: *Emitter) Error!void {
        if (self.provider_local) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
    }
    fn scalar(self: *Emitter, id: core.Id) Error!Scalar {
        const unit_ = self.generator.unit(self.unit_id);
        return self.generator.layouts.scalar(try self.codeLayout(unit_.typeOf(id), unit_.span(id))) orelse .pointer;
    }
    fn temporary(self: *Emitter, machine: wasm.ValueType) Error!u32 {
        return self.generator.module.addLocal(self.function_id, machine);
    }
    fn capture(self: *Emitter, id: core.Id, depth: usize) Error!u32 {
        const local = try self.temporary((try self.scalar(id)).machine());
        try self.expression(id, depth + 1);
        try self.emit(.local_set, local);
        return local;
    }
    fn allocate(self: *Emitter, bytes: u32) Error!u32 {
        return self.allocateStorage(bytes, false);
    }
    fn allocatePrivate(self: *Emitter, bytes: u32) Error!u32 {
        const local = try self.allocate(bytes);
        try self.cleanups.append(self.generator.allocator, .{ .release = @fromBackingInt(@intCast(local)) });
        return local;
    }
    fn cleanupTo(self: *Emitter, checkpoint: runtime_cleanup.Mark) Error!void {
        try self.cleanups.emitTo(&self.generator.module, @fromBackingInt(@intCast(self.function_id)), checkpoint);
    }
    fn allocateStorage(self: *Emitter, bytes: u32, scalar_payload: bool) Error!u32 {
        const arena = try self.generator.module.ensureArena();
        const local = try self.temporary(.i32);
        try self.emit(.i32_const, bytes);
        try self.emit(.call, if (scalar_payload) arena.allocate_scalar else arena.allocate);
        try self.emit(.local_set, local);
        return local;
    }
    /// Storage is unobservable only for a proven unused binding. Eager
    /// operands still execute in source order, and callable/demand bodies
    /// remain deferred until invocation rather than receiving an invented ABI.
    fn discardAggregateValue(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        if (id == 0) return;
        if (depth >= 1024) return g.fail(self.unit_id, id, .complexity);
        const node = source.node(id);
        switch (node.tag) {
            .product, .record, .array => for (source.children(id)) |child| try self.discardAggregateValue(child, depth + 1),
            .construct => try self.discardAggregateValue(node.b, depth + 1),
            .constant, .constructor_function, .primitive_function => {},
            .closure, .suspend_ => {
                if (!g.discardableClosure(self.unit_id, node.a)) {
                    try self.expression(id, depth + 1);
                    try self.emit(.drop, 0);
                }
            },
            .reference => {
                const reference = source.reference(id);
                if ((reference.unit == 0 or reference.unit == self.unit_id) and source.binding(reference.binding).kind != .global and source.binding(reference.binding).kind != .external) {
                    if (source.binding(reference.binding).scheme.obligations.len != 0) {
                        try self.expression(id, depth + 1);
                        try self.emit(.drop, 0);
                    }
                    return;
                }
                const target = try g.normalize(self.unit_id, reference);
                const body = g.unit(target.unit).body(target.binding) orelse return g.fail(self.unit_id, id, .unsupported);
                if (body.runtime and !body.is_function) {
                    _ = try g.runtimeGlobal(target);
                } else if (!body.is_function) {
                    const value = g.evaluator.richValue(target) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.evaluationFailure();
                    if (!g.discardableValue(value, 0)) {
                        try self.expression(id, depth + 1);
                        try self.emit(.drop, 0);
                    }
                } else if (body.scheme.obligations.len != 0) {
                    try self.expression(id, depth + 1);
                    try self.emit(.drop, 0);
                }
            },
            else => {
                try self.expression(id, depth + 1);
                try self.emit(.drop, 0);
            },
        }
    }
    fn recordMerge(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const node = unit_.node(id);
        const left_type = try self.codeLayout(unit_.typeOf(node.a), unit_.span(id));
        const right_type = try self.codeLayout(unit_.typeOf(node.b), unit_.span(id));
        const result_type = try self.codeLayout(node.ty, unit_.span(id));
        if (g.layouts.node(left_type).tag != .record or g.layouts.node(right_type).tag != .record or g.layouts.node(result_type).tag != .record) return g.fail(self.unit_id, id, .unresolved_type);
        // Even an overwritten field's computation remains observable.
        const left = try self.capture(node.a, depth);
        const right = try self.capture(node.b, depth);
        const left_fields = g.layouts.children(left_type);
        const right_fields = g.layouts.children(right_type);
        const fields = g.layouts.children(result_type);
        if (left_fields.len == 0 or right_fields.len == 0) return self.emit(.local_get, if (left_fields.len == 0) right else left);
        if (fields.len / 2 > std.math.maxInt(u32) / 4) return g.fail(self.unit_id, id, .complexity);
        const result = try self.allocate(@intCast(fields.len * 2));
        var a: usize = 0;
        var b: usize = 0;
        var out: usize = 0;
        while (out < fields.len) : (out += 2) {
            const from_left = a < left_fields.len and left_fields[a] == fields[out];
            const from_right = b < right_fields.len and right_fields[b] == fields[out];
            if (!from_left and !from_right) return g.fail(self.unit_id, id, .unresolved_type);
            try self.emit(.local_get, result);
            try self.emit(.local_get, if (from_right) right else left);
            try self.emit(.i32_load, @intCast((if (from_right) b else a) * 2));
            try self.emit(.i32_store, @intCast(out * 2));
            if (from_left) a += 2;
            if (from_right) b += 2;
        }
        try self.emit(.local_get, result);
    }
    fn aggregate(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const children = unit_.children(id);
        if (children.len == 0) return self.emit(.i32_const, 0);
        if (children.len > std.math.maxInt(u32) / 4) return g.fail(self.unit_id, id, .complexity);
        var scratch_buffer: [256]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, g.allocator);
        const scratch_allocator = scratch.allocator();
        var locals: std.ArrayList(u32) = .empty;
        defer locals.deinit(scratch_allocator);
        // Evaluating first keeps source order independent of canonical storage.
        for (children) |child| try locals.append(scratch_allocator, try self.capture(child, depth));
        const address = try self.allocate(@intCast(children.len * 4));
        const record = unit_.node(id).tag == .record;
        const destinations = if (record) unit_.recordDestinations(id) else &.{};
        const physical = if (record) try @import("record_order.zig").destinations(scratch_allocator, unit_.types, unit_.types.node(unit_.typeOf(id)), &g.layouts.record_names) else &.{};
        defer scratch_allocator.free(physical);
        for (children, locals.items, 0..) |child, value, index| {
            const declared = if (record) destinations[index] else index;
            const slot = if (physical.len == 0) declared else physical[declared];
            try self.emit(.local_get, address);
            try self.emit(.local_get, value);
            try self.emit(if (try self.scalar(child) == .f32) .f32_store else .i32_store, @intCast(slot * 4));
        }
        try self.emit(.local_get, address);
    }
    /// Constructor tuple views follow declaration order, while every record
    /// pointer follows canonical field-name order. Identity views cost nothing.
    fn recordRepresentation(self: *Emitter, record: types.Node, value: u32, into_record: bool) Error!u32 {
        const g = self.generator;
        var buffer: [256]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&buffer, g.allocator);
        const order = try @import("record_order.zig").destinations(scratch.allocator(), g.unit(self.unit_id).types, record, &g.layouts.record_names);
        defer scratch.allocator().free(order);
        if (order.len == 0) return value;
        if (record.b > std.math.maxInt(u32) / 4) return g.decline(self.unit_id, .{ .start = 0, .end = 0 }, .complexity);
        const address = try self.allocate(record.b * 4);
        for (order, 0..) |physical, declared| {
            const source: u32 = if (into_record) @intCast(declared) else physical;
            const target: u32 = if (into_record) physical else @intCast(declared);
            try self.emit(.local_get, address);
            try self.emit(.local_get, value);
            try self.emit(.i32_load, source * 4);
            try self.emit(.i32_store, target * 4);
        }
        return address;
    }
    fn construct(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const unit_ = self.generator.unit(self.unit_id);
        const n = unit_.node(id);
        var payload = if (n.b == 0) null else try self.capture(n.b, depth);
        var floating = n.b != 0 and try self.scalar(n.b) == .f32;
        if (n.c != 0) {
            const record = unit_.types.node(unit_.constructor(n.a).payload);
            if (record.tag != .record or record.b == 0 or payload == null) return self.generator.fail(self.unit_id, id, .unsupported);
            if (record.b == 1) {
                const address = try self.allocate(4);
                try self.emit(.local_get, address);
                try self.emit(.local_get, payload.?);
                try self.emit(if (floating) .f32_store else .i32_store, 0);
                payload = address;
            } else payload = try self.recordRepresentation(record, payload.?, true);
            floating = false;
        }
        const address = try self.allocate(8);
        try self.emit(.local_get, address);
        try self.emit(.i32_const, unit_.constructor(n.a).tag);
        try self.emit(.i32_store, 0);
        try self.emit(.local_get, address);
        if (payload) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
        try self.emit(if (floating) .f32_store else .i32_store, 4);
        try self.emit(.local_get, address);
    }
    const Location = struct { owner: u32, container: u32, offset: u32, size: ?u32, wrapped: bool, list_index: ?u32 = null, row_words: u32 = 0 };
    fn payloadLayout(self: *Emitter, projection: core.Projection, tag: u32, id: core.Id) Error!layout.Id {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        for (unit_.constructors) |constructor| {
            const nominal = unit_.nominal(constructor.nominal);
            if (!std.meta.eql(nominal.identity, projection.nominal) or constructor.tag != tag) continue;
            const concrete = try self.codeLayout(projection.source_type, unit_.span(id));
            const arguments = g.layouts.children(concrete);
            const parameters = unit_.types.list(nominal.parameters);
            if (arguments.len != parameters.len) return g.fail(self.unit_id, id, .unresolved_type);
            var mappings: std.ArrayList(Mapping) = .empty;
            defer mappings.deinit(g.allocator);
            try mappings.appendSlice(g.allocator, self.mappings);
            for (parameters, arguments) |parameter, argument| try g.mapType(self.unit_id, &mappings, parameter, argument, unit_.span(id));
            return g.codeLayoutWithRows(self.unit_id, constructor.payload, mappings.items, self.row_mappings, unit_.span(id));
        }
        return g.fail(self.unit_id, id, .unsupported);
    }
    fn payloadSlots(self: *Emitter, projection: core.Projection, tag: u32, id: core.Id) Error!u32 {
        const n = self.generator.layouts.node(try self.payloadLayout(projection, tag, id));
        return switch (n.tag) {
            .product, .record => n.b,
            else => self.generator.fail(self.unit_id, id, .unsupported),
        };
    }
    fn resolveProjection(self: *Emitter, original: core.Projection, variants: *std.ArrayList(core.ProjectionVariant), id: core.Id) Error!core.Projection {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        var projection = original;
        const owner = try self.codeLayout(projection.source_type, unit_.span(id));
        const owner_node = g.layouts.node(owner);
        if (owner_node.tag == .record) {
            const fields = g.layouts.children(owner);
            var index: usize = 0;
            while (index < fields.len) : (index += 2) if (fields[index] == projection.field) {
                try variants.append(g.allocator, .{ .tag = 0, .field = @intCast(index / 2) });
                return projection;
            };
        } else if (owner_node.tag == .nominal) {
            projection.nominal = .{ .unit = owner_node.a, .decl = owner_node.b };
            for (unit_.constructors) |constructor| {
                if (!std.meta.eql(unit_.nominal(constructor.nominal).identity, projection.nominal)) continue;
                const payload = try self.payloadLayout(projection, constructor.tag, id);
                if (g.layouts.node(payload).tag != .record) return g.fail(self.unit_id, id, .unresolved_type);
                const fields = g.layouts.children(payload);
                var index: usize = 0;
                var found = false;
                while (index < fields.len) : (index += 2) if (fields[index] == projection.field) {
                    try variants.append(g.allocator, .{ .tag = constructor.tag, .field = @intCast(index / 2) });
                    found = true;
                    break;
                };
                if (!found) return g.fail(self.unit_id, id, .unresolved_type);
            }
            if (variants.items.len != 0) return projection;
        }
        return g.fail(self.unit_id, id, .unresolved_type);
    }
    fn location(self: *Emitter, owner: u32, projection_index: u32, id: core.Id, need_size: bool) Error!Location {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        var projection = unit_.projection(projection_index);
        var inferred_variants: std.ArrayList(core.ProjectionVariant) = .empty;
        defer inferred_variants.deinit(g.allocator);
        var variants = unit_.projectionVariants(projection_index);
        if (projection.field != 0 or variants.len == 0) {
            projection = try self.resolveProjection(projection, &inferred_variants, id);
            variants = inferred_variants.items;
        }
        const wrapped = projection.nominal.decl != 0;
        const container = if (wrapped) try self.temporary(.i32) else owner;
        const offset = try self.temporary(.i32);
        const size = if (need_size) try self.temporary(.i32) else null;
        if (wrapped) {
            try self.emit(.local_get, owner);
            try self.emit(.i32_load, 4);
            try self.emit(.local_set, container);
        }
        if (variants.len == 1) {
            const variant = variants[0];
            if (wrapped) {
                try self.emit(.local_get, owner);
                try self.emit(.i32_load, 0);
                try self.emit(.i32_const, variant.tag);
                try self.emit(.i32_ne, 0);
                try self.emit(.if_, 0);
                try self.emit(.unreachable_, 0);
                try self.emit(.end, 0);
            }
            try self.emit(.i32_const, variant.field * 4);
            try self.emit(.local_set, offset);
            if (size) |size_local| {
                const slots = if (wrapped) try self.payloadSlots(projection, variant.tag, id) else g.layouts.node(try self.codeLayout(projection.source_type, unit_.span(id))).b;
                if (slots > std.math.maxInt(u32) / 4) return g.fail(self.unit_id, id, .complexity);
                try self.emit(.i32_const, slots * 4);
                try self.emit(.local_set, size_local);
            }
            return .{ .owner = owner, .container = container, .offset = offset, .size = size, .wrapped = wrapped };
        }
        try self.emit(.i32_const, std.math.maxInt(u32));
        try self.emit(.local_set, offset);
        for (variants) |variant| {
            if (wrapped) {
                try self.emit(.local_get, owner);
                try self.emit(.i32_load, 0);
                try self.emit(.i32_const, variant.tag);
                try self.emit(.i32_eq, 0);
                try self.emit(.if_, 0);
                self.labels += 1;
            }
            try self.emit(.i32_const, variant.field * 4);
            try self.emit(.local_set, offset);
            if (size) |size_local| {
                const slots = if (wrapped) try self.payloadSlots(projection, variant.tag, id) else blk: {
                    const concrete = try self.codeLayout(projection.source_type, unit_.span(id));
                    break :blk g.layouts.node(concrete).b;
                };
                if (slots > std.math.maxInt(u32) / 4) return g.fail(self.unit_id, id, .complexity);
                try self.emit(.i32_const, slots * 4);
                try self.emit(.local_set, size_local);
            }
            if (wrapped) {
                self.labels -= 1;
                try self.emit(.end, 0);
            }
        }
        try self.emit(.local_get, offset);
        try self.emit(.i32_const, std.math.maxInt(u32));
        try self.emit(.i32_eq, 0);
        try self.emit(.if_, 0);
        try self.emit(.unreachable_, 0);
        try self.emit(.end, 0);
        return .{ .owner = owner, .container = container, .offset = offset, .size = size, .wrapped = wrapped };
    }
    fn loadLocation(self: *Emitter, place: Location, scalar_: Scalar) Error!void {
        if (place.list_index) |index| if (place.row_words != 0) return self.readListRow(place.owner, index, place.row_words, null);
        try self.emit(.local_get, place.container);
        try self.emit(.local_get, place.offset);
        try self.emit(.i32_add, 0);
        try self.readElement(scalar_.machine(), 0, place.row_words);
    }
    fn dispatchCallableLayout(self: *Emitter, id: core.Id, fallback: layout.Id) Error!layout.Id {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const signature = source.dispatchSignature(id);
        if (signature == 0) return fallback;
        return self.codeLayout(signature, source.span(id));
    }
    fn project(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const n = unit_.node(id);
        if (unit_.types.node(unit_.typeOf(n.a)).tag == .never) {
            try self.expression(n.a, depth + 1);
            return;
        }
        const metadata = unit_.projection(n.b);
        if (unit_.projectionVariants(n.b).len == 0) {
            var variants: std.ArrayList(core.ProjectionVariant) = .empty;
            defer variants.deinit(g.allocator);
            const previous = g.diagnostic;
            const field_available = available: {
                _ = self.resolveProjection(metadata, &variants, id) catch |err| switch (err) {
                    error.Declined => {
                        g.diagnostic = previous;
                        break :available false;
                    },
                    else => return err,
                };
                break :available true;
            };
            const concrete = try self.codeLayout(metadata.source_type, unit_.span(id));
            const method = try self.memberTarget(id, metadata.field, concrete);
            if (field_available and method != null) return g.fail(self.unit_id, id, .ambiguous_member);
            if (!field_available) {
                const target = method orelse return g.fail(self.unit_id, id, .missing_member);
                const result = try self.codeLayout(n.ty, unit_.span(id));
                const full = try g.internLayout(.function, concrete, result, &.{});
                const signature = try self.dispatchCallableLayout(id, full);
                var direct: Key = .{ .target = target, .count = 1, .result = result };
                direct.parameters[0] = concrete;
                direct.effects[0] = g.layouts.node(signature).c;
                if (try self.inlineNamedCall(direct, &.{n.a}, depth)) return;
                const wrapper = try g.callable(.{ .target = target, .ty = signature });
                const receiver = try self.capture(n.a, depth);
                try self.emit(.i32_const, 0);
                try self.emit(.local_get, receiver);
                try self.providerHead();
                try self.emit(.call, wrapper);
                return;
            }
        }
        if (try self.packedProjection(id, depth)) return;
        const owner = try self.capture(n.a, depth);
        const place = try self.location(owner, n.b, id, false);
        try self.loadLocation(place, try self.scalar(id));
    }
    /// Selecting one scalar field from an already constructed packed row needs
    /// no extracted box. Producer evaluation and the original bounds check
    /// remain eager; admission never looks through an arbitrary source call.
    fn packedProjection(self: *Emitter, id: core.Id, depth: usize) Error!bool {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const projected = source.node(id);
        const value = source.node(projected.a);
        if (value.tag != .array_op) return false;
        const op = source.arrayOperation(projected.a);
        if (op != .get and op != .cursor_value) return false;
        const operands = source.children(projected.a);
        const input = try self.codeLayout(source.typeOf(operands[0]), source.span(id));
        const collection = if (op == .cursor_value) g.layouts.node(input).a else input;
        const words = packed_layout.collectionRowWords(&g.layouts, collection);
        if (words == 0) return false;
        const row = g.layouts.node(collection).a;
        const metadata = source.projection(projected.b);
        if (metadata.nominal.decl != 0) return false;
        const field: u32 = if (g.layouts.node(row).tag == .record) blk: {
            const fields = g.layouts.children(row);
            for (0..words) |i| if (fields[i * 2] == metadata.field) break :blk @intCast(i);
            return false;
        } else blk: {
            const variants = source.projectionVariants(projected.b);
            if (variants.len != 1 or variants[0].field >= words) return false;
            break :blk variants[0].field;
        };
        var container = try self.capture(operands[0], depth);
        const cursor = if (op == .cursor_value) container else null;
        const index = if (op == .get) try self.capture(operands[1], depth) else blk: {
            const position = try self.temporary(.i32);
            try self.emit(.local_get, container);
            try self.emit(.i32_load, heap.offset(heap.Cursor, "index"));
            try self.emit(.local_set, position);
            try self.emit(.local_get, container);
            try self.emit(.i32_load, heap.offset(heap.Cursor, "collection"));
            container = try self.temporary(.i32);
            try self.emit(.local_set, container);
            break :blk position;
        };
        const is_list = g.layouts.node(collection).tag == .list;
        if (is_list) {
            try self.listRowBounds(container, index, words);
            const base = try self.multiplyLocal(index, words);
            if (cursor) |cached| try self.cachedListWordAddress(container, base, field, try self.cursorCache(cached)) else try self.listWordAddress(container, base, field);
        } else {
            try self.arrayBounds(container, index);
            try self.arrayAddress(container, index, words * 4);
        }
        try self.emit(if (try self.scalar(id) == .f32) .f32_load else .i32_load, if (is_list) 0 else 4 + field * 4);
        return true;
    }
    fn memberTarget(self: *Emitter, id: core.Id, member: u32, receiver: layout.Id) Error!?core.BindingRef {
        const identity = self.dispatchIdentity(receiver) orelse return null;
        const g = self.generator;
        _ = id;
        return g.associatedTarget(self.unit_id, identity, member, .none);
    }
    fn update(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const metadata = unit_.updateInfo(id);
        const path = unit_.updatePath(id);
        const selectors = unit_.updateSelectors(id);
        var scratch_buffer: [512]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, g.allocator);
        const scratch_allocator = scratch.allocator();
        var places: std.ArrayList(Location) = .empty;
        defer places.deinit(scratch_allocator);
        var current = try self.capture(metadata.root, depth);
        if (selectors.len != 0) {
            for (selectors) |selector| {
                const place = if (selector.kind == .field)
                    try self.location(current, selector.projection, id, true)
                else
                    try self.indexLocation(current, try self.capture(selector.index, depth), try self.codeLayout(selector.source_type, unit_.span(id)));
                try places.append(scratch_allocator, place);
                const scalar_ = try g.scalarWithRows(self.unit_id, selector.result_type, self.mappings, self.row_mappings, unit_.span(id));
                current = try self.temporary(scalar_.machine());
                try self.loadLocation(place, scalar_);
                try self.emit(.local_set, current);
            }
        } else for (path) |projection_index| {
            const place = try self.location(current, projection_index, id, true);
            try places.append(scratch_allocator, place);
            const ty = unit_.projection(projection_index).result_type;
            const scalar_ = try g.scalarWithRows(self.unit_id, ty, self.mappings, self.row_mappings, unit_.span(id));
            current = try self.temporary(scalar_.machine());
            try self.loadLocation(place, scalar_);
            try self.emit(.local_set, current);
        }
        if (metadata.self_binding != 0) {
            try self.emit(.local_get, current);
            try self.save(metadata.self_binding, id);
        }
        var changed = try self.capture(metadata.value, depth);
        var changed_scalar = try self.scalar(metadata.value);
        var index = places.items.len;
        while (index != 0) {
            index -= 1;
            const place = places.items[index];
            const reuse = try g.ownsArrayUpdate(self.unit_id, id);
            if (place.list_index) |element_index| {
                const runtime = try g.module.ensureLists();
                const container = try self.temporary(.i32);
                if (place.row_words != 0) {
                    try self.editListRow(place.owner, element_index, changed, place.row_words, null, reuse);
                    try self.emit(.local_set, container);
                    changed = container;
                    changed_scalar = .pointer;
                    continue;
                }
                try self.emit(.local_get, place.owner);
                try self.emit(.local_get, element_index);
                try self.emit(.local_get, changed);
                if (changed_scalar == .f32) try self.emit(.i32_reinterpret_f32, 0);
                try self.emit(.i32_const, @intFromBool(reuse));
                try self.emit(.call, runtime.set);
                try self.emit(.local_set, container);
                changed = container;
                changed_scalar = .pointer;
                continue;
            }
            const container = if (reuse) place.container else try self.temporary(.i32);
            if (!reuse) {
                const arena = try g.module.ensureArena();
                try self.emit(.local_get, place.size.?);
                try self.emit(.call, if (place.row_words != 0) arena.allocate_scalar else arena.allocate);
                try self.emit(.local_set, container);
                try self.emit(.local_get, container);
                try self.emit(.local_get, place.container);
                try self.emit(.local_get, place.size.?);
                try self.emit(.memory_copy, 0);
            }
            try self.emit(.local_get, container);
            try self.emit(.local_get, place.offset);
            try self.emit(.i32_add, 0);
            try self.emit(.local_get, changed);
            try self.storeElement(changed_scalar.machine(), 0, place.row_words);
            if (place.wrapped) {
                const wrapper = if (reuse) place.owner else try self.allocate(8);
                if (!reuse) {
                    try self.emit(.local_get, wrapper);
                    try self.emit(.local_get, place.owner);
                    try self.emit(.i32_const, 8);
                    try self.emit(.memory_copy, 0);
                }
                try self.emit(.local_get, wrapper);
                try self.emit(.local_get, container);
                try self.emit(.i32_store, 4);
                changed = wrapper;
            } else changed = container;
            changed_scalar = .pointer;
        }
        try self.emit(.local_get, changed);
    }
    fn indexLocation(self: *Emitter, array_: u32, index: u32, collection: layout.Id) Error!Location {
        const is_list = self.generator.layouts.node(collection).tag == .list;
        const words = packed_layout.collectionRowWords(&self.generator.layouts, collection);
        if (is_list and words != 0) {
            try self.listRowBounds(array_, index, words);
            return .{ .owner = array_, .container = array_, .offset = index, .size = null, .wrapped = false, .list_index = index, .row_words = words };
        }
        try self.arrayBounds(array_, index);
        if (is_list) {
            const runtime = try self.generator.module.ensureLists();
            const address = try self.temporary(.i32);
            const zero = try self.temporary(.i32);
            try self.emit(.local_get, array_);
            try self.emit(.local_get, index);
            try self.emit(.call, runtime.address);
            try self.emit(.local_set, address);
            try self.emit(.i32_const, 0);
            try self.emit(.local_set, zero);
            return .{ .owner = array_, .container = address, .offset = zero, .size = null, .wrapped = false, .list_index = index };
        }
        const count = try self.temporary(.i32);
        try self.emit(.local_get, array_);
        try self.emit(.i32_load, 0);
        try self.emit(.local_set, count);
        const row_words = packed_layout.arrayRowWords(&self.generator.layouts, collection);
        const size = try self.arraySize(count, packed_layout.stride(row_words));
        const offset = try self.temporary(.i32);
        try self.emit(.local_get, index);
        try self.emit(.i32_const, packed_layout.stride(row_words));
        try self.emit(.i32_mul, 0);
        try self.emit(.i32_const, 4);
        try self.emit(.i32_add, 0);
        try self.emit(.local_set, offset);
        return .{ .owner = array_, .container = array_, .offset = offset, .size = size, .wrapped = false, .row_words = row_words };
    }
    fn smallCollectionCandidate(self: *const Emitter, id: core.Id) bool {
        const source = self.generator.unit(self.unit_id);
        const n = source.node(id);
        if (n.tag == .reference) {
            const ref = source.reference(id);
            return (ref.unit == 0 or ref.unit == self.unit_id) and self.small_values.contains(ref.binding);
        }
        const ty = source.types.node(n.ty).tag;
        if (ty != .array and ty != .list) return false;
        switch (source.types.node(source.types.node(n.ty).a).tag) {
            .unit, .boolean, .u32, .f32, .variable => {},
            else => return false,
        }
        if (n.tag == .array) return source.children(id).len <= function_facts.small_limit;
        if (n.tag != .call) return false;
        const call = source.call(id);
        var target = call.target;
        if (target.unit == 0) target.unit = self.unit_id;
        for (0..16) |_| {
            if (target.unit == 0 or target.unit > self.generator.units.len) return false;
            const producer = self.generator.unit(target.unit);
            if (target.binding == 0 or target.binding >= producer.bindings.len) return false;
            const binding = producer.binding(target.binding);
            if (binding.kind == .external) {
                const owner = target.unit;
                target = binding.target;
                if (target.unit == 0) target.unit = owner;
                continue;
            }
            const body = producer.body(target.binding) orelse return false;
            return body.is_function and body.parameters.len == call.arguments.len and producer.node(body.root).tag == .array and producer.children(body.root).len <= function_facts.small_limit;
        }
        return false;
    }
    fn captureSmallCollection(self: *Emitter, id: core.Id, depth: usize) Error!?SmallCollection {
        if (!self.smallCollectionCandidate(id)) return null;
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const n = source.node(id);
        if (n.tag == .reference) return self.small_values.get(source.reference(id).binding);
        const ty = g.layouts.node(try self.codeLayout(n.ty, source.span(id)));
        if ((ty.tag != .array and ty.tag != .list) or g.layouts.scalar(ty.a) == null) return null;
        var result: SmallCollection = .{ .machine = g.layouts.machine(ty.a) };
        if (n.tag == .array) {
            const children = source.children(id);
            result.len = children.len;
            for (children, 0..) |child, i| result.values[i] = try self.capture(child, depth);
            g.facts.stats.small_collections += 1;
            return result;
        }
        const call = source.call(id);
        const key = try g.signature(call.target, call.callee_type, self.unit_id, self.mappings, self.row_mappings, source.span(id), false);
        const producer = g.unit(key.target.unit);
        const body = producer.body(key.target.binding) orelse return null;
        if (producer.node(body.root).tag != .array or producer.children(body.root).len > function_facts.small_limit or call.arguments.len != key.count) return null;
        if (!try self.inlineNamedValuesMode(key, call.arguments, null, depth, &result)) return null;
        try self.emit(.drop, 0);
        return result;
    }
    fn smallCollectionElement(self: *Emitter, values: SmallCollection, index: u32, start: usize, end: usize) Error!void {
        if (start == end) return self.emit(.unreachable_, 0);
        if (end - start == 1) return self.emit(.local_get, values.values[start]);
        const middle = start + (end - start) / 2;
        try self.emit(.local_get, index);
        try self.emit(.i32_const, @intCast(middle));
        try self.emit(.i32_lt_u, 0);
        try self.emit(.if_, @backingInt(values.machine));
        try self.smallCollectionElement(values, index, start, middle);
        try self.emit(.else_, 0);
        try self.smallCollectionElement(values, index, middle, end);
        try self.emit(.end, 0);
    }
    fn array(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        if (self.exact_build) |builder| if (builder.plan.initial == id) return self.emit(.local_get, builder.storage);
        if (self.small_result) |output| if (output.root == id) {
            output.value.* = (try self.captureSmallCollection(id, depth)).?;
            // Keep the ordinary inlined expression's stack/result contract.
            try self.emit(.i32_const, 0);
            return;
        };
        const children = unit_.children(id);
        if (children.len > 0x3ffffffe) return g.fail(self.unit_id, id, .complexity);
        var storage_buffer: [256]u8 align(@alignOf(usize)) = undefined;
        var storage: std.heap.BufferFirstAllocator = .init(&storage_buffer, g.allocator);
        const scratch = storage.allocator();
        var locals: std.ArrayList(u32) = .empty;
        defer locals.deinit(scratch);
        for (children) |child| try locals.append(scratch, try self.capture(child, depth));
        const collection_layout = g.layouts.node(try self.codeLayout(unit_.typeOf(id), unit_.span(id)));
        const row_words = packed_layout.rowWords(&g.layouts, collection_layout.a);
        const scalar_elements = row_words != 0 or g.layouts.scalar(collection_layout.a) != null;
        if (collection_layout.tag == .list) {
            const runtime = try g.module.ensureLists();
            const address = try self.temporary(.i32);
            if (children.len > 0x10000000 / @max(1, row_words)) return g.fail(self.unit_id, id, .complexity);
            try self.emit(.i32_const, @intCast(children.len * @max(1, row_words)));
            try self.emit(.i32_const, @intFromBool(scalar_elements));
            try self.emit(.call, runtime.new);
            try self.emit(.local_set, address);
            for (children, locals.items, 0..) |child, value, index| {
                if (row_words != 0) {
                    const position = try self.temporary(.i32);
                    try self.emit(.i32_const, @intCast(index));
                    try self.emit(.local_set, position);
                    try self.storeListRow(address, position, value, row_words);
                    continue;
                }
                try self.emit(.local_get, address);
                try self.emit(.i32_const, @intCast(index));
                try self.emit(.call, runtime.address);
                try self.emit(.local_get, value);
                try self.emit(if (try self.scalar(child) == .f32) .f32_store else .i32_store, 0);
            }
            try self.emit(.local_get, address);
            return;
        }
        const stride = packed_layout.stride(row_words);
        if (children.len > (std.math.maxInt(u32) - 4) / stride) return g.fail(self.unit_id, id, .complexity);
        const address = try self.allocateStorage(@intCast(children.len * stride + 4), scalar_elements or row_words != 0);
        try self.emit(.local_get, address);
        try self.emit(.i32_const, @intCast(children.len));
        try self.emit(.i32_store, 0);
        for (children, locals.items, 0..) |child, value, index| {
            try self.emit(.local_get, address);
            try self.emit(.local_get, value);
            try self.storeElement((try self.scalar(child)).machine(), @intCast(index * stride + 4), row_words);
        }
        try self.emit(.local_get, address);
    }
    fn arrayAddress(self: *Emitter, array_: u32, index: u32, stride: u32) Error!void {
        try self.emit(.local_get, array_);
        try self.emit(.local_get, index);
        try self.emit(.i32_const, stride);
        try self.emit(.i32_mul, 0);
        try self.emit(.i32_add, 0);
    }
    /// Storage boundaries copy raw scalar bits. A row extracted from an array
    /// owns an allocation base; it never exposes a borrowed interior pointer.
    /// Fixed field operations also let ordinary scalar replacement remove
    /// temporary boxes when the consumer does not let them escape.
    fn readElement(self: *Emitter, machine: wasm.ValueType, offset: u32, row_words: u32) Error!void {
        if (row_words == 0) return self.emit(if (machine == .f32) .f32_load else .i32_load, offset);
        const source = try self.temporary(.i32);
        try self.emit(.local_set, source);
        const row = try self.allocateStorage(row_words * 4, true);
        for (0..row_words) |i| {
            const field: u32 = @intCast(i * 4);
            try self.emit(.local_get, row);
            try self.emit(.local_get, source);
            try self.emit(.i32_load, offset + field);
            try self.emit(.i32_store, field);
        }
        try self.emit(.local_get, row);
    }
    fn storeElement(self: *Emitter, machine: wasm.ValueType, offset: u32, row_words: u32) Error!void {
        if (row_words == 0) return self.emit(if (machine == .f32) .f32_store else .i32_store, offset);
        const row = try self.temporary(.i32);
        const destination = try self.temporary(.i32);
        try self.emit(.local_set, row);
        try self.emit(.local_set, destination);
        for (0..row_words) |i| {
            const field: u32 = @intCast(i * 4);
            try self.emit(.local_get, destination);
            try self.emit(.local_get, row);
            try self.emit(.i32_load, field);
            try self.emit(.i32_store, offset + field);
        }
    }
    fn arrayBounds(self: *Emitter, array_: u32, index: u32) Error!void {
        try self.emit(.local_get, index);
        try self.emit(.local_get, array_);
        try self.emit(.i32_load, 0);
        try self.emit(.i32_ge_u, 0);
        try self.emit(.if_, 0);
        try self.emit(.unreachable_, 0);
        try self.emit(.end, 0);
    }
    fn arraySize(self: *Emitter, count: u32, stride: u32) Error!u32 {
        try self.emit(.local_get, count);
        try self.emit(.i32_const, (std.math.maxInt(u32) - 4) / stride);
        try self.emit(.i32_gt_u, 0);
        try self.emit(.if_, 0);
        try self.emit(.unreachable_, 0);
        try self.emit(.end, 0);
        const size = try self.temporary(.i32);
        try self.emit(.local_get, count);
        if (stride == 4) {
            try self.emit(.i32_const, 1);
            try self.emit(.i32_add, 0);
            try self.emit(.i32_const, 4);
            try self.emit(.i32_mul, 0);
        } else {
            try self.emit(.i32_const, stride);
            try self.emit(.i32_mul, 0);
            try self.emit(.i32_const, 4);
            try self.emit(.i32_add, 0);
        }
        try self.emit(.local_set, size);
        return size;
    }
    fn arrayFill(self: *Emitter, count: u32, value: u32, machine: wasm.ValueType, is_generated: bool, is_list: bool, known: ?u32, element: layout.Id) Error!void {
        const row_words = packed_layout.rowWords(&self.generator.layouts, element);
        const stride = packed_layout.stride(row_words);
        const scalar_elements = row_words != 0 or self.generator.layouts.scalar(element) != null;
        const size = try self.arraySize(count, stride);
        const arena = try self.generator.module.ensureArena();
        const array_ = try self.temporary(.i32);
        const index = try self.temporary(.i32);
        const physical = if (is_list and row_words > 1) try self.listWordCount(count, row_words) else count;
        try self.emit(.local_get, if (is_list) physical else size);
        if (is_list) try self.emit(.i32_const, @intFromBool(scalar_elements));
        try self.emit(.call, if (is_list) (try self.generator.module.ensureLists()).new else if (scalar_elements) arena.allocate_scalar else arena.allocate);
        try self.emit(.local_set, array_);
        try self.emit(.local_get, array_);
        try self.emit(.local_get, if (is_list) physical else count);
        try self.emit(.i32_store, 0);
        try self.emit(.i32_const, 0);
        try self.emit(.local_set, index);
        try self.emit(.block, 0);
        try self.emit(.loop, 0);
        self.labels += 2;
        try self.emit(.local_get, index);
        try self.emit(.local_get, count);
        try self.emit(.i32_ge_u, 0);
        try self.emit(.br_if, 1);
        if (is_list and row_words == 0) {
            try self.emit(.local_get, array_);
            try self.emit(.local_get, index);
            try self.emit(.call, (try self.generator.module.ensureLists()).address);
        } else if (!is_list) try self.arrayAddress(array_, index, stride);
        if (known) |function| {
            try self.emit(.local_get, value);
            try self.emit(.local_get, index);
            try self.providerHead();
            try self.emit(.call, function);
        } else if (is_generated) {
            const signature = try self.generator.module.internType(&.{ .i32, .i32, .i32 }, machine);
            try self.emit(.local_get, value);
            try self.emit(.i32_load, 4);
            try self.emit(.local_get, index);
            try self.providerHead();
            try self.emit(.local_get, value);
            try self.emit(.i32_load, 0);
            try self.emit(.call_indirect, signature);
        } else try self.emit(.local_get, value);
        if (is_list and row_words != 0) {
            const row = try self.temporary(.i32);
            try self.emit(.local_set, row);
            try self.storeListRow(array_, index, row, row_words);
        } else try self.storeElement(machine, if (is_list) 0 else 4, row_words);
        try self.emit(.local_get, index);
        try self.emit(.i32_const, 1);
        try self.emit(.i32_add, 0);
        try self.emit(.local_set, index);
        try self.emit(.br, 0);
        self.labels -= 2;
        try self.emit(.end, 0);
        try self.emit(.end, 0);
        try self.emit(.local_get, array_);
    }
    fn arrayOperation(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const operands = unit_.children(id);
        if (operands.len > 3) return g.fail(self.unit_id, id, .unsupported);
        if (self.exact_build) |builder| {
            if (builder.plan.conversion == id) return self.expression(operands[0], depth + 1);
            if (builder.plan.append == id) {
                const value = try self.capture(operands[1], depth);
                const is_list = builder.plan.conversion == 0;
                if (is_list and builder.row_words != 0) {
                    try self.storeListRow(builder.storage, builder.index, value, builder.row_words);
                } else {
                    if (is_list) {
                        try self.emit(.local_get, builder.storage);
                        try self.emit(.local_get, builder.index);
                        try self.emit(.call, (try g.module.ensureLists()).address);
                    } else try self.arrayAddress(builder.storage, builder.index, packed_layout.stride(builder.row_words));
                    try self.emit(.local_get, value);
                    try self.storeElement((try self.scalar(operands[1])).machine(), if (is_list) 0 else 4, builder.row_words);
                }
                try self.emit(.local_get, builder.index);
                try self.emit(.i32_const, 1);
                try self.emit(.i32_add, 0);
                try self.emit(.local_set, builder.index);
                return self.emit(.local_get, builder.storage);
            }
        }
        if (unit_.arrayOperation(id) == .length) if (try self.captureSmallCollection(operands[0], depth)) |values| {
            try self.emit(.i32_const, @intCast(values.len));
            return;
        };
        if (unit_.arrayOperation(id) == .generate and self.static_values.count() == 0 and self.isCallableTemplate(operands[1])) {
            const count = try self.capture(operands[0], depth);
            const template = (try self.callableTemplate(operands[1])).?;
            const callback = try self.codeLayout(unit_.typeOf(operands[1]), unit_.span(id));
            const result = try self.codeLayout(unit_.typeOf(id), unit_.span(id));
            const env = template.environment orelse blk: {
                const local = try self.temporary(.i32);
                try self.emit(.i32_const, 0);
                try self.emit(.local_set, local);
                break :blk local;
            };
            return self.arrayFill(count, env, g.layouts.machine(g.layouts.node(result).a), true, g.layouts.node(result).tag == .list, try self.templateFunction(template, callback), g.layouts.node(result).a);
        }
        var locals: [3]u32 = undefined;
        var machines: [3]wasm.ValueType = undefined;
        for (operands, 0..) |operand, index| {
            locals[index] = try self.capture(operand, depth);
            machines[index] = (try self.scalar(operand)).machine();
        }
        const result = try self.codeLayout(unit_.typeOf(id), unit_.span(id));
        const source_layout = try self.codeLayout(unit_.typeOf(operands[0]), unit_.span(id));
        return self.arrayLocals(id, unit_.arrayOperation(id), locals[0..operands.len], machines[0..operands.len], result, source_layout);
    }
    fn exactBuilder(self: *Emitter, id: core.Id, plan: exact_builder.Plan, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const collection = g.layouts.node(try self.codeLayout(source.typeOf(plan.initial), source.span(id)));
        const is_list = plan.conversion == 0;
        const row_words = packed_layout.rowWords(&g.layouts, collection.a);
        const stride = packed_layout.stride(row_words);
        const limit = if (is_list) 0x10000000 / @max(1, row_words) else @min(0x10000000, (std.math.maxInt(u32) - 4) / stride);
        const count = try self.temporary(.i32);
        const eligible = try self.temporary(.i32);
        try self.emit(.i32_const, 1);
        try self.emit(.local_set, count);
        try self.emit(.i32_const, 1);
        try self.emit(.local_set, eligible);
        for (plan.loops[0..plan.loop_count]) |loop_id| {
            const loop = source.loopInfo(loop_id);
            const length = try self.temporary(.i32);
            if (loop.kind == .range) {
                const first = try self.capture(loop.first, depth);
                const end = try self.capture(loop.end, depth);
                try self.emit(.local_get, end);
                try self.emit(.local_get, first);
                try self.emit(.i32_gt_u, 0);
                try self.emit(.if_, @backingInt(wasm.ValueType.i32));
                try self.emit(.local_get, end);
                try self.emit(.local_get, first);
                try self.emit(.i32_sub, 0);
                try self.emit(.else_, 0);
                try self.emit(.i32_const, 0);
                try self.emit(.end, 0);
            } else if (try self.captureSmallCollection(loop.first, depth)) |small| {
                try self.emit(.i32_const, @intCast(small.len));
            } else {
                try self.expression(loop.first, depth + 1);
                try self.emit(.i32_load, 0);
                const input = try self.codeLayout(source.typeOf(loop.first), source.span(loop.first));
                try self.logicalListLength(input);
            }
            try self.emit(.local_set, length);
            try self.emit(.local_get, count);
            try self.emit(.if_, 0);
            try self.emit(.local_get, length);
            try self.emit(.i32_const, limit);
            try self.emit(.local_get, count);
            try self.emit(.i32_div_u, 0);
            try self.emit(.i32_gt_u, 0);
            try self.emit(.if_, 0);
            try self.emit(.i32_const, 0);
            try self.emit(.local_set, eligible);
            try self.emit(.end, 0);
            try self.emit(.end, 0);
            try self.emit(.local_get, count);
            try self.emit(.local_get, length);
            try self.emit(.i32_mul, 0);
            try self.emit(.local_set, count);
        }
        const previous_probe = self.exact_probe;
        const previous_build = self.exact_build;
        self.exact_probe = true;
        defer {
            self.exact_probe = previous_probe;
            self.exact_build = previous_build;
        }
        try self.emit(.local_get, eligible);
        try self.emit(.if_, @backingInt(wasm.ValueType.i32));
        self.labels += 1;
        const scalar_elements = row_words != 0 or g.layouts.scalar(collection.a) != null;
        const size = if (is_list) (if (row_words > 1) try self.listWordCount(count, row_words) else count) else try self.arraySize(count, stride);
        const storage = try self.temporary(.i32);
        try self.emit(.local_get, size);
        if (is_list) try self.emit(.i32_const, @intFromBool(scalar_elements));
        const arena = try g.module.ensureArena();
        try self.emit(.call, if (is_list) (try g.module.ensureLists()).new else if (scalar_elements) arena.allocate_scalar else arena.allocate);
        try self.emit(.local_set, storage);
        if (!is_list) {
            if (!scalar_elements) {
                try self.emit(.local_get, storage);
                try self.emit(.i32_const, 0);
                try self.emit(.local_get, size);
                try self.emit(.memory_fill, 0);
            }
            try self.emit(.local_get, storage);
            try self.emit(.local_get, count);
            try self.emit(.i32_store, 0);
        }
        const index = try self.temporary(.i32);
        try self.emit(.i32_const, 0);
        try self.emit(.local_set, index);
        self.exact_build = .{ .plan = plan, .storage = storage, .index = index, .row_words = row_words };
        try self.expression(id, depth + 1);
        try self.emit(.else_, 0);
        self.exact_build = previous_build;
        // Oversized/overflowing counts retain the original effects and failure
        // order instead of introducing an early overflow trap.
        try self.expression(id, depth + 1);
        self.labels -= 1;
        try self.emit(.end, 0);
        g.facts.stats.exact_builders += 1;
    }
    fn arrayLocals(self: *Emitter, id: core.Id, op: core.ArrayOp, locals: []const u32, machines: []const wasm.ValueType, result_layout: layout.Id, input_layout: layout.Id) Error!void {
        const g = self.generator;
        const result = g.layouts.machine(result_layout);
        const input_list = g.layouts.listInput(input_layout);
        const input_node = g.layouts.node(input_layout);
        const input_collection = if (input_node.tag == .cursor) input_node.a else input_layout;
        const row_words = packed_layout.collectionRowWords(&g.layouts, input_collection);
        const stride = packed_layout.stride(row_words);
        const expected = @import("collection_ops.zig").arity(op);
        if (locals.len != expected or machines.len != expected) return g.fail(self.unit_id, id, .unsupported);
        switch (op) {
            .cursor => {
                const snapshot = if (input_list) try self.temporary(.i32) else locals[0];
                if (input_list) {
                    try self.emit(.local_get, locals[0]);
                    try self.emit(.i32_const, 0);
                    try self.emit(.call, (try g.module.ensureLists()).edit);
                    try self.emit(.local_set, snapshot);
                }
                const index = try self.temporary(.i32);
                try self.emit(.i32_const, 0);
                try self.emit(.local_set, index);
                try self.cursorPosition(snapshot, index, input_list, null, row_words);
            },
            .cursor_has, .cursor_value, .cursor_advance => {
                const source = try self.temporary(.i32);
                const index = try self.temporary(.i32);
                try self.emit(.local_get, locals[0]);
                try self.emit(.i32_load, heap.offset(heap.Cursor, "collection"));
                try self.emit(.local_set, source);
                try self.emit(.local_get, locals[0]);
                try self.emit(.i32_load, heap.offset(heap.Cursor, "index"));
                try self.emit(.local_set, index);
                if (op == .cursor_has) {
                    try self.emit(.local_get, index);
                    try self.emit(.local_get, source);
                    try self.emit(.i32_load, 0);
                    try self.logicalListLength(input_collection);
                    try self.emit(.i32_lt_u, 0);
                } else {
                    if (input_list and row_words != 0) {
                        try self.listRowBounds(source, index, row_words);
                        if (op == .cursor_value) {
                            try self.readListRow(source, index, row_words, try self.cursorCache(locals[0]));
                        } else {
                            const next = try self.temporary(.i32);
                            try self.emit(.local_get, index);
                            try self.emit(.i32_const, 1);
                            try self.emit(.i32_add, 0);
                            try self.emit(.local_set, next);
                            try self.cursorPosition(source, next, true, locals[0], row_words);
                        }
                        return;
                    }
                    try self.arrayBounds(source, index);
                    if (op == .cursor_value) {
                        if (input_list) {
                            const leaf = try self.temporary(.i32);
                            try self.emit(.local_get, locals[0]);
                            try self.emit(.i32_load, heap.offset(heap.Cursor, "leaf"));
                            try self.emit(.local_tee, leaf);
                            try self.emit(.if_, @backingInt(wasm.ValueType.i32));
                            try self.emit(.local_get, leaf);
                            try self.emit(.local_get, index);
                            try self.emit(.local_get, locals[0]);
                            try self.emit(.i32_load, heap.offset(heap.Cursor, "base"));
                            try self.emit(.i32_sub, 0);
                            try self.emit(.i32_const, 4);
                            try self.emit(.i32_mul, 0);
                            try self.emit(.i32_add, 0);
                            try self.emit(.i32_const, @sizeOf(heap.ListNode));
                            try self.emit(.i32_add, 0);
                            try self.emit(.else_, 0);
                            // Serialized positions start without a leaf cache.
                            try self.emit(.local_get, source);
                            try self.emit(.local_get, index);
                            try self.emit(.call, (try g.module.ensureLists()).address);
                            try self.emit(.end, 0);
                        } else try self.arrayAddress(source, index, stride);
                        try self.readElement(result, if (input_list) 0 else 4, row_words);
                    } else {
                        const next = try self.temporary(.i32);
                        try self.emit(.local_get, index);
                        try self.emit(.i32_const, 1);
                        try self.emit(.i32_add, 0);
                        try self.emit(.local_set, next);
                        try self.cursorPosition(source, next, input_list, locals[0], row_words);
                    }
                }
            },
            .concat, .slice => {
                if (input_list) {
                    if (op == .slice and row_words != 0) return self.sliceListRows(locals, row_words);
                    for (locals) |local| try self.emit(.local_get, local);
                    const runtime = try g.module.ensureLists();
                    try self.emit(.call, if (op == .concat) runtime.concat else runtime.slice);
                } else try self.arrayStructural(op, locals, row_words != 0 or g.layouts.scalar(g.layouts.node(result_layout).a) != null, stride);
            },
            .length => {
                try self.emit(.local_get, locals[0]);
                try self.emit(.i32_load, 0);
                try self.logicalListLength(input_collection);
            },
            .get => {
                if (input_list and row_words != 0) {
                    try self.listRowBounds(locals[0], locals[1], row_words);
                    return self.readListRow(locals[0], locals[1], row_words, null);
                }
                try self.arrayBounds(locals[0], locals[1]);
                if (input_list) {
                    try self.emit(.local_get, locals[0]);
                    try self.emit(.local_get, locals[1]);
                    try self.emit(.call, (try g.module.ensureLists()).address);
                } else try self.arrayAddress(locals[0], locals[1], stride);
                try self.readElement(result, if (input_list) 0 else 4, row_words);
            },
            .set => {
                const reuse = id != 0 and (self.owned_edit == id or try g.ownsArrayUpdate(self.unit_id, id));
                if (input_list) {
                    if (row_words != 0) return self.editListRow(locals[0], locals[1], locals[2], row_words, null, reuse);
                    try self.emit(.local_get, locals[0]);
                    try self.emit(.local_get, locals[1]);
                    try self.emit(.local_get, locals[2]);
                    if (machines[2] == .f32) try self.emit(.i32_reinterpret_f32, 0);
                    try self.emit(.i32_const, @intFromBool(reuse));
                    try self.emit(.call, (try g.module.ensureLists()).set);
                    return;
                }
                try self.arrayBounds(locals[0], locals[1]);
                const changed = if (reuse) locals[0] else try self.temporary(.i32);
                if (!reuse) {
                    const count = try self.temporary(.i32);
                    try self.emit(.local_get, locals[0]);
                    try self.emit(.i32_load, 0);
                    try self.emit(.local_set, count);
                    const size = try self.arraySize(count, stride);
                    const arena = try g.module.ensureArena();
                    try self.emit(.local_get, size);
                    try self.emit(.call, if (row_words != 0 or g.layouts.scalar(g.layouts.node(result_layout).a) != null) arena.allocate_scalar else arena.allocate);
                    try self.emit(.local_set, changed);
                    try self.emit(.local_get, changed);
                    try self.emit(.local_get, locals[0]);
                    try self.emit(.local_get, size);
                    try self.emit(.memory_copy, 0);
                }
                try self.arrayAddress(changed, locals[1], stride);
                try self.emit(.local_get, locals[2]);
                try self.storeElement(machines[2], 4, row_words);
                try self.emit(.local_get, changed);
            },
            .fill => try self.arrayFill(locals[0], locals[1], machines[1], false, g.layouts.node(result_layout).tag == .list, null, g.layouts.node(result_layout).a),
            .generate => try self.arrayFill(locals[0], locals[1], g.layouts.machine(g.layouts.node(result_layout).a), true, g.layouts.node(result_layout).tag == .list, null, g.layouts.node(result_layout).a),
            .identity => try self.emit(.local_get, locals[0]),
            .convert => {
                const words = packed_layout.rowWords(&g.layouts, g.layouts.node(result_layout).a);
                if (words != 0) return self.convertRows(locals[0], input_list, words);
                try self.emit(.local_get, locals[0]);
                const runtime = try g.module.ensureLists();
                if (!input_list) try self.emit(.i32_const, @intFromBool(g.layouts.scalar(g.layouts.node(result_layout).a) != null));
                try self.emit(.call, if (input_list) runtime.to_array else runtime.from_array);
            },
            .append, .prepend => {
                if (input_list) {
                    if (row_words != 0) return self.editListRow(locals[0], null, locals[1], row_words, op == .prepend, id != 0 and try g.ownsArrayUpdate(self.unit_id, id));
                    try self.emit(.local_get, locals[0]);
                    try self.emit(.local_get, locals[1]);
                    if (machines[1] == .f32) try self.emit(.i32_reinterpret_f32, 0);
                    try self.emit(.i32_const, @intFromBool(op == .prepend));
                    try self.emit(.i32_const, @intFromBool(id != 0 and try g.ownsArrayUpdate(self.unit_id, id)));
                    try self.emit(.call, (try g.module.ensureLists()).push);
                } else try self.arrayPush(locals[0], locals[1], machines[1], op == .prepend, row_words != 0 or g.layouts.scalar(g.layouts.node(result_layout).a) != null, row_words);
            },
        }
    }
    /// The AVL runtime stores words. Typed boundaries translate logical row
    /// positions; a row may cross leaves without exposing interior pointers.
    fn logicalListLength(self: *Emitter, collection: layout.Id) Error!void {
        if (self.generator.layouts.node(collection).tag != .list) return;
        const words = packed_layout.collectionRowWords(&self.generator.layouts, collection);
        if (words <= 1) return;
        try self.emit(.i32_const, words);
        try self.emit(.i32_div_u, 0);
    }
    fn listWordCount(self: *Emitter, count: u32, words: u32) Error!u32 {
        try self.emit(.local_get, count);
        try self.emit(.i32_const, 0x10000000 / words);
        try self.emit(.i32_gt_u, 0);
        try self.emit(.if_, 0);
        try self.emit(.unreachable_, 0);
        try self.emit(.end, 0);
        return self.multiplyLocal(count, words);
    }
    fn multiplyLocal(self: *Emitter, value: u32, factor: u32) Error!u32 {
        const result = try self.temporary(.i32);
        try self.emit(.local_get, value);
        try self.emit(.i32_const, factor);
        try self.emit(.i32_mul, 0);
        try self.emit(.local_set, result);
        return result;
    }
    fn listRowBounds(self: *Emitter, source: u32, index: u32, words: u32) Error!void {
        try self.emit(.local_get, index);
        try self.emit(.local_get, source);
        try self.emit(.i32_load, 0);
        try self.emit(.i32_const, words);
        try self.emit(.i32_div_u, 0);
        try self.emit(.i32_ge_u, 0);
        try self.emit(.if_, 0);
        try self.emit(.unreachable_, 0);
        try self.emit(.end, 0);
    }
    fn listWordAddress(self: *Emitter, source: u32, base: u32, field: u32) Error!void {
        try self.emit(.local_get, source);
        try self.emit(.local_get, base);
        if (field != 0) {
            try self.emit(.i32_const, field);
            try self.emit(.i32_add, 0);
        }
        try self.emit(.call, (try self.generator.module.ensureLists()).address);
    }
    fn readListRow(self: *Emitter, source: u32, index: u32, words: u32, cache: ?[2]u32) Error!void {
        const base = try self.multiplyLocal(index, words);
        var fields: [16]u32 = undefined;
        for (fields[0..words]) |*field| field.* = try self.temporary(.i32);
        if (cache) |cached| {
            const relative = try self.temporary(.i32);
            try self.emit(.local_get, base);
            try self.emit(.local_get, cached[1]);
            try self.emit(.i32_sub, 0);
            try self.emit(.local_set, relative);
            try self.emit(.local_get, cached[0]);
            try self.emit(.if_, @backingInt(wasm.ValueType.i32));
            try self.emit(.local_get, relative);
            try self.emit(.local_get, cached[0]);
            try self.emit(.i32_load, heap.offset(heap.ListNode, "length"));
            try self.emit(.i32_le_u, 0);
            try self.emit(.local_get, cached[0]);
            try self.emit(.i32_load, heap.offset(heap.ListNode, "length"));
            try self.emit(.local_get, relative);
            try self.emit(.i32_sub, 0);
            try self.emit(.i32_const, words);
            try self.emit(.i32_ge_u, 0);
            try self.emit(.i32_and, 0);
            try self.emit(.else_, 0);
            try self.emit(.i32_const, 0);
            try self.emit(.end, 0);
            try self.emit(.if_, 0);
            const address = try self.temporary(.i32);
            try self.arrayAddress(cached[0], relative, 4);
            try self.emit(.local_set, address);
            for (fields[0..words], 0..) |field, i| {
                try self.emit(.local_get, address);
                try self.emit(.i32_load, @sizeOf(heap.ListNode) + @as(u32, @intCast(i * 4)));
                try self.emit(.local_set, field);
            }
            try self.emit(.else_, 0);
        }
        for (fields[0..words], 0..) |field, i| {
            try self.listWordAddress(source, base, @intCast(i));
            try self.emit(.i32_load, 0);
            try self.emit(.local_set, field);
        }
        if (cache != null) try self.emit(.end, 0);
        // Resolve conditional leaf reads before initializing the row, so the
        // ordinary scalar replacement proof sees complete dominating stores.
        const row = try self.allocateStorage(words * 4, true);
        for (fields[0..words], 0..) |field, i| {
            try self.emit(.local_get, row);
            try self.emit(.local_get, field);
            try self.emit(.i32_store, @intCast(i * 4));
        }
        try self.emit(.local_get, row);
    }
    fn cursorCache(self: *Emitter, cursor: u32) Error![2]u32 {
        var values: [2]u32 = undefined;
        inline for (.{ "leaf", "base" }, 0..) |field, i| {
            values[i] = try self.temporary(.i32);
            try self.emit(.local_get, cursor);
            try self.emit(.i32_load, heap.offset(heap.Cursor, field));
            try self.emit(.local_set, values[i]);
        }
        return values;
    }
    fn cachedListWordAddress(self: *Emitter, source: u32, base: u32, field: u32, cache: [2]u32) Error!void {
        const leaf = cache[0];
        const relative = try self.temporary(.i32);
        try self.emit(.local_get, base);
        try self.emit(.i32_const, field);
        try self.emit(.i32_add, 0);
        try self.emit(.local_get, cache[1]);
        try self.emit(.i32_sub, 0);
        try self.emit(.local_set, relative);
        try self.emit(.local_get, leaf);
        try self.emit(.if_, @backingInt(wasm.ValueType.i32));
        try self.emit(.local_get, relative);
        try self.emit(.local_get, leaf);
        try self.emit(.i32_load, heap.offset(heap.ListNode, "length"));
        try self.emit(.i32_lt_u, 0);
        try self.emit(.else_, 0);
        try self.emit(.i32_const, 0);
        try self.emit(.end, 0);
        try self.emit(.if_, @backingInt(wasm.ValueType.i32));
        try self.emit(.local_get, leaf);
        try self.emit(.local_get, relative);
        try self.emit(.i32_const, 4);
        try self.emit(.i32_mul, 0);
        try self.emit(.i32_add, 0);
        try self.emit(.i32_const, @sizeOf(heap.ListNode));
        try self.emit(.i32_add, 0);
        try self.emit(.else_, 0);
        try self.listWordAddress(source, base, field);
        try self.emit(.end, 0);
    }
    fn storeListRow(self: *Emitter, source: u32, index: u32, row: u32, words: u32) Error!void {
        const base = try self.multiplyLocal(index, words);
        for (0..words) |i| {
            try self.listWordAddress(source, base, @intCast(i));
            try self.emit(.local_get, row);
            try self.emit(.i32_load, @intCast(i * 4));
            try self.emit(.i32_store, 0);
        }
    }
    fn editListRow(self: *Emitter, source: u32, index: ?u32, row: u32, words: u32, front: ?bool, reuse: bool) Error!void {
        const runtime = try self.generator.module.ensureLists();
        const result = try self.temporary(.i32);
        const base = if (index) |value| blk: {
            try self.listRowBounds(source, value, words);
            break :blk try self.multiplyLocal(value, words);
        } else null;
        for (0..words) |step| {
            const i = if (front == true) words - 1 - step else step;
            try self.emit(.local_get, if (step == 0) source else result);
            if (base) |position| {
                try self.emit(.local_get, position);
                try self.emit(.i32_const, @intCast(i));
                try self.emit(.i32_add, 0);
            }
            try self.emit(.local_get, row);
            try self.emit(.i32_load, @intCast(i * 4));
            if (front) |prepend| try self.emit(.i32_const, @intFromBool(prepend));
            // Only the first operation touches the possibly shared input.
            // Intermediate word edits are private until the whole row returns.
            try self.emit(.i32_const, @intFromBool(step != 0 or reuse));
            try self.emit(.call, if (base == null) runtime.push else runtime.set);
            try self.emit(.local_set, result);
        }
        try self.emit(.local_get, result);
    }
    fn sliceListRows(self: *Emitter, locals: []const u32, words: u32) Error!void {
        const count = try self.temporary(.i32);
        try self.emit(.local_get, locals[0]);
        try self.emit(.i32_load, 0);
        try self.emit(.i32_const, words);
        try self.emit(.i32_div_u, 0);
        try self.emit(.local_set, count);
        try self.emit(.local_get, locals[1]);
        try self.emit(.local_get, count);
        try self.emit(.i32_gt_u, 0);
        try self.emit(.if_, 0);
        try self.emit(.unreachable_, 0);
        try self.emit(.end, 0);
        try self.emit(.local_get, locals[2]);
        try self.emit(.local_get, count);
        try self.emit(.local_get, locals[1]);
        try self.emit(.i32_sub, 0);
        try self.emit(.i32_gt_u, 0);
        try self.emit(.if_, 0);
        try self.emit(.unreachable_, 0);
        try self.emit(.end, 0);
        const start = try self.multiplyLocal(locals[1], words);
        const length = try self.multiplyLocal(locals[2], words);
        try self.emit(.local_get, locals[0]);
        try self.emit(.local_get, start);
        try self.emit(.local_get, length);
        try self.emit(.call, (try self.generator.module.ensureLists()).slice);
    }
    fn convertRows(self: *Emitter, source: u32, input_list: bool, row_words: u32) Error!void {
        const runtime = try self.generator.module.ensureLists();
        try self.emit(.local_get, source);
        if (!input_list) try self.emit(.i32_const, row_words);
        try self.emit(.call, if (input_list) runtime.to_array else runtime.from_array);
        if (input_list and row_words > 1) {
            const result = try self.temporary(.i32);
            try self.emit(.local_set, result);
            try self.emit(.local_get, result);
            try self.emit(.local_get, result);
            try self.emit(.i32_load, 0);
            try self.emit(.i32_const, row_words);
            try self.emit(.i32_div_u, 0);
            try self.emit(.i32_store, 0);
            try self.emit(.local_get, result);
        }
    }
    /// Construct all fields once, so local cursors still admit scalar
    /// replacement. Stored pointers are allocation bases, never interior
    /// addresses, and a published cursor is never mutated.
    fn cursorPosition(self: *Emitter, source: u32, index: u32, is_list: bool, previous: ?u32, row_words: u32) Error!void {
        const position = if (is_list and row_words > 1) try self.multiplyLocal(index, row_words) else index;
        const leaf = try self.temporary(.i32);
        const base = try self.temporary(.i32);
        try self.emit(.i32_const, 0);
        try self.emit(.local_set, leaf);
        try self.emit(.i32_const, 0);
        try self.emit(.local_set, base);
        if (is_list) {
            try self.emit(.local_get, position);
            try self.emit(.local_get, source);
            try self.emit(.i32_load, heap.offset(heap.ListDescriptor, "length"));
            try self.emit(.i32_lt_u, 0);
            try self.emit(.if_, 0);
            if (previous) |cursor| {
                try self.emit(.local_get, cursor);
                try self.emit(.i32_load, heap.offset(heap.Cursor, "base"));
                try self.emit(.local_set, base);
                try self.emit(.local_get, cursor);
                try self.emit(.i32_load, heap.offset(heap.Cursor, "leaf"));
                try self.emit(.local_tee, leaf);
                try self.emit(.if_, 0);
                try self.emit(.local_get, position);
                try self.emit(.local_get, base);
                try self.emit(.i32_sub, 0);
                try self.emit(.local_get, leaf);
                try self.emit(.i32_load, heap.offset(heap.ListNode, "length"));
                try self.emit(.i32_ge_u, 0);
                try self.emit(.if_, 0);
                try self.emit(.i32_const, 0);
                try self.emit(.local_set, leaf);
                try self.emit(.end, 0);
                try self.emit(.end, 0);
            }
            try self.emit(.local_get, leaf);
            try self.emit(.i32_eqz, 0);
            try self.emit(.if_, 0);
            try self.emit(.local_get, source);
            try self.emit(.local_get, position);
            try self.emit(.call, (try self.generator.module.ensureLists()).address);
            try self.emit(.drop, 0);
            try self.emit(.local_get, source);
            try self.emit(.i32_load, heap.offset(heap.ListDescriptor, "cached_leaf"));
            try self.emit(.local_set, leaf);
            try self.emit(.local_get, source);
            try self.emit(.i32_load, heap.offset(heap.ListDescriptor, "cached_base"));
            try self.emit(.local_set, base);
            try self.emit(.end, 0);
            try self.emit(.end, 0);
        }
        const address = try self.allocate(@sizeOf(heap.Cursor));
        inline for (.{ "collection", "index", "leaf", "base" }, .{ source, index, leaf, base }) |name, value| {
            try self.emit(.local_get, address);
            try self.emit(.local_get, value);
            try self.emit(.i32_store, heap.offset(heap.Cursor, name));
        }
        try self.emit(.local_get, address);
    }
    fn arrayPush(self: *Emitter, source: u32, value: u32, machine: wasm.ValueType, front: bool, scalar_elements: bool, row_words: u32) Error!void {
        const count = try self.temporary(.i32);
        const result = try self.temporary(.i32);
        try self.emit(.local_get, source);
        try self.emit(.i32_load, 0);
        try self.emit(.i32_const, 1);
        try self.emit(.i32_add, 0);
        try self.emit(.local_set, count);
        const stride = packed_layout.stride(row_words);
        const size = try self.arraySize(count, stride);
        try self.emit(.local_get, size);
        const arena = try self.generator.module.ensureArena();
        try self.emit(.call, if (scalar_elements) arena.allocate_scalar else arena.allocate);
        try self.emit(.local_set, result);
        try self.emit(.local_get, result);
        try self.emit(.local_get, count);
        try self.emit(.i32_store, 0);
        try self.emit(.local_get, result);
        try self.emit(.i32_const, if (front) 4 + stride else 4);
        try self.emit(.i32_add, 0);
        try self.emit(.local_get, source);
        try self.emit(.i32_const, 4);
        try self.emit(.i32_add, 0);
        try self.emit(.local_get, size);
        try self.emit(.i32_const, 4 + stride);
        try self.emit(.i32_sub, 0);
        try self.emit(.memory_copy, 0);
        if (front) {
            try self.emit(.local_get, result);
        } else {
            try self.arrayAddress(result, count, stride);
            // count is the new length; the final slot starts one row earlier.
            if (stride != 4) {
                try self.emit(.i32_const, stride - 4);
                try self.emit(.i32_sub, 0);
            }
        }
        try self.emit(.local_get, value);
        try self.storeElement(machine, if (front) 4 else 0, row_words);
        try self.emit(.local_get, result);
    }
    fn simdLocals(self: *Emitter, op: core.Op, operands: []const u32, input: layout.Id) Error!void {
        const fields = self.generator.layouts.children(input);
        if (fields.len != 4) return self.generator.fail(self.unit_id, 0, .unsupported);
        const scalar_type = self.generator.layouts.scalar(fields[0]) orelse return self.generator.fail(self.unit_id, 0, .unsupported);
        for (fields) |field| if (field != fields[0]) return self.generator.fail(self.unit_id, 0, .unsupported);
        const scalar_op = scalar_ops.opcode(op, scalar_type) orelse return self.generator.fail(self.unit_id, 0, .unsupported);
        const vector_op = @import("runtime_ir.zig").lift(scalar_op) orelse return self.generator.fail(self.unit_id, 0, .unsupported);
        const address = try self.allocateStorage(16, true);
        try self.emit(.local_get, address);
        for (operands) |operand| {
            try self.emit(.local_get, operand);
            try self.emit(.v128_load, 0);
        }
        try self.emit(vector_op, 0);
        try self.emit(.v128_store, 0);
        try self.emit(.local_get, address);
    }
    fn arrayStructural(self: *Emitter, op: core.ArrayOp, locals: []const u32, scalar_elements: bool, stride: u32) Error!void {
        const count = try self.temporary(.i32);
        const left_count = try self.temporary(.i32);
        try self.emit(.local_get, locals[0]);
        try self.emit(.i32_load, 0);
        try self.emit(.local_set, left_count);
        if (op == .concat) {
            try self.emit(.local_get, left_count);
            try self.emit(.local_get, locals[1]);
            try self.emit(.i32_load, 0);
            try self.emit(.i32_add, 0);
            try self.emit(.local_tee, count);
            try self.emit(.local_get, left_count);
            try self.emit(.i32_lt_u, 0);
            try self.emit(.if_, 0);
            try self.emit(.unreachable_, 0);
            try self.emit(.end, 0);
        } else {
            try self.emit(.local_get, locals[1]);
            try self.emit(.local_get, left_count);
            try self.emit(.i32_gt_u, 0);
            try self.emit(.if_, 0);
            try self.emit(.unreachable_, 0);
            try self.emit(.end, 0);
            try self.emit(.local_get, locals[2]);
            try self.emit(.local_tee, count);
            try self.emit(.local_get, left_count);
            try self.emit(.local_get, locals[1]);
            try self.emit(.i32_sub, 0);
            try self.emit(.i32_gt_u, 0);
            try self.emit(.if_, 0);
            try self.emit(.unreachable_, 0);
            try self.emit(.end, 0);
        }
        const bytes = try self.arraySize(count, stride);
        const address = try self.temporary(.i32);
        try self.emit(.local_get, bytes);
        const arena = try self.generator.module.ensureArena();
        try self.emit(.call, if (scalar_elements) arena.allocate_scalar else arena.allocate);
        try self.emit(.local_set, address);
        try self.emit(.local_get, address);
        try self.emit(.local_get, count);
        try self.emit(.i32_store, 0);
        try self.emit(.local_get, address);
        try self.emit(.i32_const, 4);
        try self.emit(.i32_add, 0);
        if (op == .slice) try self.arrayAddress(locals[0], locals[1], stride) else try self.emit(.local_get, locals[0]);
        try self.emit(.i32_const, 4);
        try self.emit(.i32_add, 0);
        try self.emit(.local_get, if (op == .slice) count else left_count);
        try self.emit(.i32_const, stride);
        try self.emit(.i32_mul, 0);
        try self.emit(.memory_copy, 0);
        if (op == .concat) {
            try self.arrayAddress(address, left_count, stride);
            try self.emit(.i32_const, 4);
            try self.emit(.i32_add, 0);
            try self.emit(.local_get, locals[1]);
            try self.emit(.i32_const, 4);
            try self.emit(.i32_add, 0);
            try self.emit(.local_get, count);
            try self.emit(.local_get, left_count);
            try self.emit(.i32_sub, 0);
            try self.emit(.i32_const, stride);
            try self.emit(.i32_mul, 0);
            try self.emit(.memory_copy, 0);
        }
        try self.emit(.local_get, address);
    }
    fn descriptor(self: *Emitter, function_id: u32, environment: ?u32) Error!void {
        const address = try self.allocate(@sizeOf(heap.Closure));
        try self.emit(.local_get, address);
        try self.referenceConstant(function_id, .table_function);
        try self.emit(.i32_store, heap.offset(heap.Closure, "function"));
        try self.emit(.local_get, address);
        if (environment) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
        try self.emit(.i32_store, heap.offset(heap.Closure, "environment"));
        try self.emit(.local_get, address);
    }
    fn demandDescriptor(self: *Emitter, function_id: u32, environment: ?u32) Error!void {
        const address = try self.allocate(@sizeOf(heap.Demand));
        try self.emit(.local_get, address);
        try self.referenceConstant(function_id, .table_function);
        try self.emit(.i32_store, heap.offset(heap.Demand, "function"));
        try self.emit(.local_get, address);
        if (environment) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
        try self.emit(.i32_store, heap.offset(heap.Demand, "environment"));
        for ([_]u32{ heap.offset(heap.Demand, "status"), heap.offset(heap.Demand, "cached") }) |offset| {
            try self.emit(.local_get, address);
            try self.emit(.i32_const, 0);
            try self.emit(.i32_store, offset);
        }
        try self.emit(.local_get, address);
    }
    fn newTemplate(self: *Emitter, id: core.Id) Error!Template {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const n = unit_.node(id);
        if (n.tag == .reference) {
            const reference = unit_.reference(id);
            if (reference.unit == 0 or reference.unit == self.unit_id) {
                if (self.templates.get(reference.binding)) |template| return template;
            }
            return .{ .unit = self.unit_id, .node = id };
        }
        if (n.tag == .constructor_function or n.tag == .primitive_function) return .{ .unit = self.unit_id, .node = id };
        const captures = if (n.tag == .suspend_) unit_.suspensionCaptures(id) else unit_.closureCaptures(id);
        var capture_types: std.ArrayList(layout.Id) = .empty;
        defer capture_types.deinit(g.allocator);
        var templates: std.ArrayList(substitution_keys.Entry) = .empty;
        defer templates.deinit(g.allocator);
        for (captures) |binding| {
            if (self.templates.get(binding)) |template| {
                try capture_types.append(g.allocator, 1);
                try templates.append(g.allocator, .{ .variable = binding, .value = try g.captureTemplate(template) });
            } else {
                const capture_type = try self.codeLayout(unit_.binding(binding).ty, unit_.span(id));
                try self.checkComputationABI(binding, capture_type, id);
                try capture_types.append(g.allocator, capture_type);
            }
        }
        const capture_layout = try g.internLayout(.product, 0, 0, capture_types.items);
        const environment = if (captures.len == 0) null else try self.allocate(@intCast(captures.len * 4));
        for (captures, capture_types.items, 0..) |binding, capture_type, index| {
            try self.emit(.local_get, environment.?);
            if (self.locals.get(binding)) |local| try self.emit(.local_get, local) else if (self.templates.get(binding)) |template| {
                if (template.environment) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
            } else return g.fail(self.unit_id, id, .unsupported);
            try self.emit(if (g.layouts.machine(capture_type) == .f32) .f32_store else .i32_store, @intCast(index * 4));
        }
        return .{ .unit = self.unit_id, .node = id, .environment = environment, .captures = capture_layout, .templates = g.template_keys.intern(templates.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .complexity), .evidence = if (self.factory_template) try g.mappingEvidence(self.mappings) else 0, .rows = if (self.factory_template) try g.rowMappingEvidence(self.row_mappings) else 0 };
    }
    fn computationAction(self: *Emitter, ty: layout.Id) ?layout.Id {
        const layouts = &self.generator.layouts;
        const node = layouts.node(ty);
        if (node.tag != .nominal or node.a != std.math.maxInt(u32) or node.b != 5 or layouts.children(ty).len != 1) return null;
        const action = layouts.children(ty)[0];
        if (layouts.node(action).tag != .function) return null;
        return action;
    }
    fn checkComputationABI(self: *Emitter, binding: core.BindingId, expected: layout.Id, source: core.Id) Error!void {
        const actual = self.computation_values.get(binding) orelse return;
        const given = self.computationAction(actual) orelse return;
        const required = self.computationAction(expected) orelse return;
        const layouts = &self.generator.layouts;
        if (layouts.machine(layouts.node(given).b) != layouts.machine(layouts.node(required).b)) return self.generator.fail(self.unit_id, source, .unresolved_type);
    }
    fn sourceTemplate(self: *Emitter, owner: u32, id: core.Id, parameters: []const core.Parameter, arguments: []const bool, depth: usize) bool {
        if (depth >= 1024) return false;
        const source = self.generator.unit(owner);
        const n = source.node(id);
        if (n.tag == .closure or n.tag == .primitive_function or n.tag == .constructor_function) return true;
        if (n.tag != .reference) return false;
        const reference = source.reference(id);
        if (reference.unit != 0 and reference.unit != owner) return true;
        for (parameters, arguments) |parameter, argument| if (parameter.binding == reference.binding) return argument;
        if (source.types.node(n.ty).tag != .function) return false;
        const binding = source.binding(reference.binding);
        if (binding.kind == .global or binding.kind == .external) return true;
        return binding.initializer != 0 and self.sourceTemplate(owner, binding.initializer, parameters, arguments, depth + 1);
    }
    /// Check the factory's returned value position. Execution of its other
    /// statements remains in the ordinary emitter; this is source provenance,
    /// not an evaluation or purity shortcut.
    fn factoryTemplateResult(self: *Emitter, owner: u32, id: core.Id, parameters: []const core.Parameter, arguments: []const bool, depth: usize) bool {
        if (depth >= 1024) return false;
        const source = self.generator.unit(owner);
        const n = source.node(id);
        switch (n.tag) {
            .computation => return self.sourceTemplate(owner, n.a, parameters, arguments, depth + 1),
            .reference => {
                const reference = source.reference(id);
                if (reference.unit != 0 and reference.unit != owner) return false;
                for (parameters, arguments) |parameter, argument| if (parameter.binding == reference.binding) return argument;
                const binding = source.binding(reference.binding);
                return binding.initializer != 0 and self.factoryTemplateResult(owner, binding.initializer, parameters, arguments, depth + 1);
            },
            .call => {
                const call = source.call(id);
                const target = self.generator.normalize(owner, call.target) catch return false;
                const producer = self.generator.unit(target.unit);
                const body = producer.body(target.binding) orelse return false;
                if (!body.is_function or body.parameters.len != call.arguments.len or call.arguments.len > max_parameters) return false;
                var admitted: [max_parameters]bool = @splat(false);
                for (call.arguments, 0..) |argument, index| admitted[index] = self.sourceTemplate(owner, argument, parameters, arguments, depth + 1);
                return self.factoryTemplateResult(target.unit, body.root, producer.bodyParameters(body), admitted[0..call.arguments.len], depth + 1);
            },
            .block => {
                for (source.children(id)) |statement| {
                    const value = source.node(statement);
                    if (value.tag == .return_ and value.b == id) return self.factoryTemplateResult(owner, value.a, parameters, arguments, depth + 1);
                }
                return false;
            },
            .if_value => return self.factoryTemplateResult(owner, n.b, parameters, arguments, depth + 1) and self.factoryTemplateResult(owner, n.c, parameters, arguments, depth + 1),
            else => return false,
        }
    }
    fn isCallableTemplate(self: *Emitter, id: core.Id) bool {
        const source = self.generator.unit(self.unit_id);
        const n = source.node(id);
        if (n.tag == .closure or n.tag == .primitive_function or n.tag == .constructor_function) return true;
        if (n.tag != .reference) return false;
        const reference = source.reference(id);
        if (reference.unit == 0 or reference.unit == self.unit_id) {
            if (self.templates.contains(reference.binding)) return true;
            if (source.types.node(n.ty).tag != .function) return false;
            const kind = source.binding(reference.binding).kind;
            return kind == .global or kind == .external;
        }
        return source.types.node(n.ty).tag == .function;
    }
    /// Retained source values may settle a type position which the caller
    /// never observes. Only explicit erased holes are filled; selected rows
    /// and every already selected type position stay unchanged.
    fn sourceArgumentLayout(self: *Emitter, selected: layout.Id, actual: layout.Id, depth: usize) Error!layout.Id {
        const g = self.generator;
        if (depth >= 1024) return g.decline(self.unit_id, .{ .start = 0, .end = 0 }, .complexity);
        if (selected == layout.erased) return actual;
        const wanted = g.layouts.node(selected);
        const given = g.layouts.node(actual);
        if (wanted.tag != given.tag) return selected;
        if (wanted.tag == .function) {
            const parameter = try self.sourceArgumentLayout(wanted.a, given.a, depth + 1);
            const result = try self.sourceArgumentLayout(wanted.b, given.b, depth + 1);
            return g.internLayoutWithEffects(.function, parameter, result, wanted.c, &.{});
        }
        if (wanted.tag == .array or wanted.tag == .list or wanted.tag == .demand) {
            return g.internLayoutWithEffects(wanted.tag, try self.sourceArgumentLayout(wanted.a, given.a, depth + 1), wanted.b, wanted.c, &.{});
        }
        if (wanted.tag == .product or wanted.tag == .nominal) {
            if (wanted.tag == .nominal and (wanted.a != given.a or wanted.b != given.b)) return selected;
            const count = g.layouts.children(selected).len;
            if (count != g.layouts.children(actual).len) return selected;
            var children: std.ArrayList(layout.Id) = .empty;
            defer children.deinit(g.allocator);
            for (0..count) |index| {
                const left = g.layouts.children(selected)[index];
                const right = g.layouts.children(actual)[index];
                try children.append(g.allocator, try self.sourceArgumentLayout(left, right, depth + 1));
            }
            return g.internLayout(wanted.tag, if (wanted.tag == .nominal) wanted.a else 0, if (wanted.tag == .nominal) wanted.b else 0, children.items);
        }
        if (wanted.tag == .record) {
            const count = g.layouts.children(selected).len;
            if (count != g.layouts.children(actual).len) return selected;
            var children: std.ArrayList(layout.Id) = .empty;
            defer children.deinit(g.allocator);
            var index: usize = 0;
            while (index < count) : (index += 2) {
                const name = g.layouts.children(selected)[index];
                const left = g.layouts.children(selected)[index + 1];
                var right: ?layout.Id = null;
                var position: usize = 0;
                while (position < count) : (position += 2) if (g.layouts.children(actual)[position] == name) {
                    right = g.layouts.children(actual)[position + 1];
                    break;
                };
                const value = right orelse return selected;
                try children.append(g.allocator, name);
                try children.append(g.allocator, try self.sourceArgumentLayout(left, value, depth + 1));
            }
            return g.internLayout(.record, 0, 0, children.items);
        }
        return selected;
    }
    fn callableTemplate(self: *Emitter, id: core.Id) Error!?Template {
        const source = self.generator.unit(self.unit_id);
        const n = source.node(id);
        if (n.tag == .closure or n.tag == .primitive_function or n.tag == .constructor_function) return try self.newTemplate(id);
        if (n.tag != .reference) return null;
        const reference = source.reference(id);
        if (reference.unit == 0 or reference.unit == self.unit_id) {
            if (self.templates.get(reference.binding)) |template| return if (template.computation) null else template;
            const kind = source.binding(reference.binding).kind;
            if (kind != .global and kind != .external) return null;
        }
        return try self.newTemplate(id);
    }
    /// Opaque computations keep action source and declaration-time capture
    /// values. A factory runs once and returns that environment; each demand
    /// selects its own checked action signature through the callable proof.
    fn computationTemplate(self: *Emitter, id: core.Id) Error!?Template {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const n = source.node(id);
        if (n.tag == .reference) {
            const reference = source.reference(id);
            if (reference.unit == 0 or reference.unit == self.unit_id) if (self.templates.get(reference.binding)) |template| if (template.computation) return template;
            return null;
        }
        if (n.tag == .computation) {
            var template = try self.callableTemplate(n.a) orelse return null;
            template.computation = true;
            return template;
        }
        if (n.tag == .apply) {
            const result_type = source.types.node(n.ty);
            if (result_type.tag != .nominal or result_type.a != std.math.maxInt(u32) or result_type.b != 5 or !self.isCallableTemplate(n.a)) return null;
            const factory = try self.callableTemplate(n.a) orelse return null;
            const owner = if (factory.unit == 0) self.unit_id else factory.unit;
            const producer = g.unit(owner);
            const factory_node = producer.node(factory.node);
            if (factory_node.tag != .closure) return null;
            const metadata = producer.closures[factory_node.a];
            const admitted = self.isCallableTemplate(n.b);
            if (!self.factoryTemplateResult(owner, metadata.body, &.{metadata.parameter}, &.{admitted}, 0)) return null;
            var ty = try self.codeLayout(source.typeOf(n.a), source.span(id));
            if (admitted) {
                const arrow = g.layouts.node(ty);
                const actual = try self.codeLayout(source.typeOf(n.b), source.span(n.b));
                ty = try g.internLayoutWithEffects(.function, try self.sourceArgumentLayout(arrow.a, actual, 0), arrow.b, arrow.c, &.{});
            }
            var key: ClosureKey = .{ .unit = owner, .catalog = factory_node.a, .ty = ty, .captures = factory.captures, .templates = factory.templates, .evidence = factory.evidence, .rows = factory.rows, .template_result = true };
            const argument = try self.temporary((try self.scalar(n.b)).machine());
            if (admitted) {
                const argument_node = source.node(n.b);
                var retained: ?Template = null;
                if (argument_node.tag == .reference) {
                    const reference = source.reference(n.b);
                    if (reference.unit == 0 or reference.unit == self.unit_id) retained = self.templates.get(reference.binding);
                }
                const template = retained orelse try self.callableTemplate(n.b) orelse return g.fail(self.unit_id, n.b, .unresolved_type);
                key.parameter_template = try g.captureTemplate(template);
                if (template.environment) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
            } else try self.expression(n.b, 0);
            try self.emit(.local_set, argument);
            const function_id = try g.closureFunction(key);
            const retained_id = g.closure_template_results.get(key) orelse return g.fail(self.unit_id, id, .unresolved_type);
            const retained = g.template_catalog.items[retained_id - 1];
            if (factory.environment) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
            try self.emit(.local_get, argument);
            try self.providerHead();
            try self.emit(.call, function_id);
            const environment = try self.temporary(.i32);
            try self.emit(.local_set, environment);
            return .{ .unit = retained.unit, .node = retained.node, .environment = if (retained.has_environment) environment else null, .captures = retained.captures, .templates = retained.templates, .computation = true, .evidence = retained.evidence, .rows = retained.rows };
        }
        if (n.tag != .call) return null;
        const result_type = source.types.node(n.ty);
        if (result_type.tag != .nominal or result_type.a != std.math.maxInt(u32) or result_type.b != 5) return null;
        const call = source.call(id);
        var key = try g.signature(call.target, call.callee_type, self.unit_id, self.mappings, self.row_mappings, source.span(id), false);
        if (key.count != call.arguments.len or self.computationAction(key.result) == null) return null;
        const producer = g.unit(key.target.unit);
        const body = producer.body(key.target.binding) orelse return null;
        if (!body.is_function or body.parameters.len != key.count) return null;
        var admitted: [max_parameters]bool = @splat(false);
        for (call.arguments, 0..) |argument, index| admitted[index] = self.isCallableTemplate(argument);
        if (!self.factoryTemplateResult(key.target.unit, body.root, producer.bodyParameters(body), admitted[0..key.count], 0)) return null;
        for (call.arguments, 0..) |argument, index| if (admitted[index]) {
            const actual = try self.codeLayout(source.typeOf(argument), source.span(argument));
            key.parameters[index] = try self.sourceArgumentLayout(key.parameters[index], actual, 0);
        };
        var arguments: [max_parameters]u32 = undefined;
        var entries: std.ArrayList(substitution_keys.Entry) = .empty;
        defer entries.deinit(g.allocator);
        // Construct argument snapshots in source order, once. Ordinary argument
        // expressions may perform effects and must precede later snapshots.
        for (call.arguments, producer.bodyParameters(body), 0..) |argument, parameter, index| {
            if (admitted[index]) {
                const argument_node = source.node(argument);
                var retained: ?Template = null;
                if (argument_node.tag == .reference) {
                    const reference = source.reference(argument);
                    if (reference.unit == 0 or reference.unit == self.unit_id) retained = self.templates.get(reference.binding);
                }
                const template = retained orelse try self.callableTemplate(argument) orelse return g.fail(self.unit_id, argument, .unresolved_type);
                try entries.append(g.allocator, .{ .variable = parameter.binding, .value = try g.captureTemplate(template) });
                arguments[index] = try self.temporary(.i32);
                if (template.environment) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
                try self.emit(.local_set, arguments[index]);
            } else arguments[index] = try self.capture(argument, 0);
        }
        key.templates = g.template_keys.intern(entries.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .complexity);
        key.template_result = true;
        const function_id = try g.function(key);
        const retained_id = g.template_results.get(key) orelse return g.fail(self.unit_id, id, .unresolved_type);
        // Copy numeric metadata before expression emission can grow its owner.
        const retained = g.template_catalog.items[retained_id - 1];
        for (arguments[0..key.count]) |argument| try self.emit(.local_get, argument);
        try self.providerHead();
        try self.emit(.call, function_id);
        const environment = try self.temporary(.i32);
        try self.emit(.local_set, environment);
        return .{ .unit = retained.unit, .node = retained.node, .environment = if (retained.has_environment) environment else null, .captures = retained.captures, .templates = retained.templates, .computation = true, .evidence = retained.evidence, .rows = retained.rows };
    }
    fn publishTemplate(self: *Emitter, template: Template, source: core.Id) Error!void {
        const g = self.generator;
        const retained = try g.captureTemplate(template);
        if (self.result_template) |prior| {
            if (prior != retained) return g.fail(self.unit_id, source, .unresolved_type);
        } else self.result_template = retained;
        if (template.environment) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
    }
    fn templateExpression(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        if (depth >= 1024) return g.fail(self.unit_id, id, .complexity);
        const source = g.unit(self.unit_id);
        const n = source.node(id);
        switch (n.tag) {
            .computation, .reference, .call, .apply => try self.publishTemplate(try self.computationTemplate(id) orelse return g.fail(self.unit_id, id, .unresolved_type), id),
            .block => {
                try self.emit(.block, @backingInt(wasm.ValueType.i32));
                try self.return_targets.append(g.allocator, .{ .node = id, .label = self.labels, .cleanup = self.cleanups.mark(), .template_result = true });
                self.labels += 1;
                const terminated = try self.suite(id, depth + 1);
                if (terminated) try self.emit(.unreachable_, 0) else return g.fail(self.unit_id, id, .unresolved_type);
                self.labels -= 1;
                _ = self.return_targets.pop();
                try self.emit(.end, 0);
            },
            .if_value => {
                try self.expression(n.a, depth + 1);
                try self.emit(.if_, @backingInt(wasm.ValueType.i32));
                self.labels += 1;
                try self.templateExpression(n.b, depth + 1);
                try self.emit(.else_, 0);
                try self.templateExpression(n.c, depth + 1);
                self.labels -= 1;
                try self.emit(.end, 0);
            },
            .panic => try self.emit(.unreachable_, 0),
            else => return g.fail(self.unit_id, id, .unresolved_type),
        }
    }
    fn templateValue(self: *Emitter, template: Template, requested: layout.Id) Error!void {
        const g = self.generator;
        const ty = if (template.computation) comp: {
            const value = g.layouts.node(requested);
            if (value.tag != .nominal or value.a != std.math.maxInt(u32) or value.b != 5 or g.layouts.children(requested).len != 1) return g.fail(self.unit_id, template.node, .unresolved_type);
            break :comp g.layouts.children(requested)[0];
        } else requested;
        const owner = if (template.unit == 0) self.unit_id else template.unit;
        const unit_ = g.unit(owner);
        const n = unit_.node(template.node);
        if (n.tag == .suspend_) {
            const demanded = g.layouts.node(ty);
            if (demanded.tag != .demand) return g.fail(self.unit_id, template.node, .unresolved_type);
            const fn_type = try g.internLayoutWithEffects(.function, 1, demanded.a, demanded.c, &.{});
            const function_id = try g.closureFunction(.{ .unit = owner, .catalog = n.a, .ty = fn_type, .captures = template.captures, .templates = template.templates, .evidence = template.evidence, .rows = if (template.rows != 0) template.rows else if (owner == self.unit_id) try g.rowMappingEvidence(self.row_mappings) else 0 });
            try self.demandDescriptor(function_id, template.environment);
            return;
        }
        try self.descriptor(try self.templateFunction(template, ty), template.environment);
    }
    fn templateFunction(self: *Emitter, template: Template, ty: layout.Id) Error!u32 {
        const g = self.generator;
        const owner = if (template.unit == 0) self.unit_id else template.unit;
        const unit_ = g.unit(owner);
        const n = unit_.node(template.node);
        return switch (n.tag) {
            .closure => try g.closureFunction(.{ .unit = owner, .catalog = n.a, .ty = ty, .captures = template.captures, .templates = template.templates, .evidence = template.evidence, .rows = template.rows }),
            .constructor_function => try g.constructorFunction(.{ .unit = owner, .catalog = n.a, .ty = ty }),
            .primitive_function => try g.primitiveFunction(.{ .unit = owner, .catalog = n.a, .ty = ty }),
            .reference => try g.callable(.{ .target = try g.normalize(owner, unit_.reference(template.node)), .ty = ty }),
            else => return g.fail(self.unit_id, template.node, .unsupported),
        };
    }
    fn closure(self: *Emitter, id: core.Id) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        if (try self.closureWithStaticCaptures(id)) return;
        const template = try self.newTemplate(id);
        try self.templateValue(template, try self.codeLayout(unit_.typeOf(id), unit_.span(id)));
    }
    fn closureWithStaticCaptures(self: *Emitter, id: core.Id) Error!bool {
        if (self.static_values.count() == 0) return false;
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        if (node.tag != .closure) return false;
        const captures = source.closureCaptures(id);
        const retained = for (captures) |binding| {
            if (self.static_values.contains(binding)) break true;
        } else false;
        if (!retained) return false;
        if (captures.len > std.math.maxInt(u32) / 4) return g.fail(self.unit_id, id, .complexity);
        const ty = try self.codeLayout(source.typeOf(id), source.span(id));
        var capture_types: std.ArrayList(layout.Id) = .empty;
        defer capture_types.deinit(g.allocator);
        var static_values: std.ArrayList(substitution_keys.Entry) = .empty;
        defer static_values.deinit(g.allocator);
        var templates: std.ArrayList(substitution_keys.Entry) = .empty;
        defer templates.deinit(g.allocator);
        for (captures) |binding| {
            if (self.static_values.get(binding)) |value| {
                try static_values.append(g.allocator, .{ .variable = binding, .value = value });
            } else if (self.templates.get(binding)) |template| {
                try templates.append(g.allocator, .{ .variable = binding, .value = try g.captureTemplate(template) });
            }
            try capture_types.append(g.allocator, try self.codeLayout(source.binding(binding).ty, source.span(id)));
        }
        const key: ClosureKey = .{
            .unit = self.unit_id,
            .catalog = node.a,
            .ty = ty,
            .captures = try g.internLayout(.product, 0, 0, capture_types.items),
            .templates = g.template_keys.intern(templates.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .complexity),
            .static_values = g.static_keys.intern(static_values.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .complexity),
        };
        const function_id = try g.closureFunction(key);
        const environment = try self.allocate(@intCast(captures.len * 4));
        for (captures, capture_types.items, 0..) |binding, concrete, index| {
            try self.emit(.local_get, environment);
            if (self.static_values.contains(binding)) {
                try self.emit(.i32_const, 0);
                try self.emit(.i32_store, @intCast(index * 4));
                continue;
            }
            if (self.locals.get(binding)) |local| try self.emit(.local_get, local) else if (self.templates.get(binding)) |template| {
                if (template.environment) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
            } else return g.fail(self.unit_id, id, .unsupported);
            try self.emit(if (g.layouts.machine(concrete) == .f32) .f32_store else .i32_store, @intCast(index * 4));
        }
        try self.descriptor(function_id, environment);
        return true;
    }

    fn invokeRequest(self: *Emitter, frame: u32, argument: u32, argument_machine: wasm.ValueType, result_machine: wasm.ValueType) Error!void {
        const g = self.generator;
        const cell = try self.temporary(.i32);
        const callback = try self.temporary(.i32);
        try self.emit(.local_get, frame);
        try self.emit(.i32_load, heap.offset(heap.RequestFrame, "cell"));
        try self.emit(.local_set, cell);
        try self.emit(.local_get, frame);
        try self.emit(.i32_load, heap.offset(heap.RequestFrame, "target"));
        try self.emit(.local_set, callback);
        const pair = try self.allocate(@sizeOf(heap.Pair));
        try self.emit(.local_get, pair);
        try self.emit(.local_get, argument);
        try self.emit(if (argument_machine == .f32) .f32_store else .i32_store, heap.offset(heap.Pair, "first"));
        try self.emit(.local_get, pair);
        try self.emit(.local_get, cell);
        try self.emit(.i32_load, heap.offset(heap.RequestCell, "state"));
        try self.emit(.i32_store, heap.offset(heap.Pair, "second"));
        try self.emit(.local_get, callback);
        try self.emit(.i32_load, heap.offset(heap.Closure, "environment"));
        try self.emit(.local_get, pair);
        try self.emit(.local_get, frame);
        try self.emit(.i32_load, heap.offset(heap.RequestFrame, "runner_outer"));
        try self.emit(.local_get, callback);
        try self.emit(.i32_load, heap.offset(heap.Closure, "function"));
        try self.emit(.call_indirect, try g.module.internType(&.{ .i32, .i32, .i32 }, .i32));
        const decision = try self.temporary(.i32);
        try self.emit(.local_set, decision);
        // State and exit are representation words. Their consumers use the
        // independently proved state/result machines; no reply cast occurs.
        try self.emit(.local_get, cell);
        try self.emit(.local_get, decision);
        try self.emit(.i32_load, heap.offset(heap.Decision, "state"));
        try self.emit(.i32_store, heap.offset(heap.RequestCell, "state"));
        try self.emit(.local_get, decision);
        try self.emit(.i32_load, heap.offset(heap.Decision, "kind"));
        try self.emit(.i32_eqz, 0);
        try self.emit(.if_, @backingInt(result_machine));
        try self.emit(.local_get, decision);
        try self.emit(if (result_machine == .f32) .f32_load else .i32_load, heap.offset(heap.Decision, "payload"));
        try self.emit(.else_, 0);
        try self.emit(.local_get, decision);
        try self.emit(.i32_load, heap.offset(heap.Decision, "kind"));
        try self.emit(.i32_const, @backingInt(core.RequestDecisionKind.break_));
        try self.emit(.i32_gt_u, 0);
        try self.emit(.if_, 0);
        try self.emit(.unreachable_, 0);
        try self.emit(.end, 0);
        try self.emit(.local_get, cell);
        try self.emit(.local_get, decision);
        try self.emit(.i32_load, heap.offset(heap.Decision, "kind"));
        try self.emit(.i32_store, heap.offset(heap.RequestCell, "status"));
        try self.emit(.local_get, cell);
        try self.emit(.local_get, decision);
        try self.emit(.i32_load, heap.offset(heap.Decision, "payload"));
        try self.emit(.i32_store, heap.offset(heap.RequestCell, "exit"));
        try self.emit(.local_get, cell);
        try self.emit(.global_set, g.request_owner.?);
        try request_runtime.dummy(&g.module, self.function_id, &self.cleanups);
        try self.emit(.end, 0);
    }
    fn requestDecision(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const node = g.unit(self.unit_id).node(id);
        const payload = if (node.b != 0) try self.capture(node.b, depth) else null;
        const state = if (node.c != 0) try self.capture(node.c, depth) else null;
        const decision = try self.allocate(@sizeOf(heap.Decision));
        try self.emit(.local_get, decision);
        try self.emit(.i32_const, node.a);
        try self.emit(.i32_store, heap.offset(heap.Decision, "kind"));
        try self.emit(.local_get, decision);
        if (payload) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
        try self.emit(if (node.b != 0 and try self.scalar(node.b) == .f32) .f32_store else .i32_store, heap.offset(heap.Decision, "payload"));
        try self.emit(.local_get, decision);
        if (state) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
        try self.emit(if (node.c != 0 and try self.scalar(node.c) == .f32) .f32_store else .i32_store, heap.offset(heap.Decision, "state"));
        try self.emit(.local_get, decision);
    }
    fn requestStateValue(self: *Emitter, id: core.Id, binding: core.BindingId, ty: layout.Id) Error!void {
        if (self.templates.get(binding)) |template| return self.templateValue(template, ty);
        if (self.locals.get(binding)) |local| return self.emit(.local_get, local);
        if (self.static_values.get(binding)) |value| {
            if (self.generator.evaluator.valueScalar(value)) |scalar_| return self.emit(if (scalar_.scalar == .f32) .f32_const else .i32_const, scalar_.bits);
            return self.referenceConstant(try self.generator.serialize(value, ty, 0), .static_address);
        }
        return self.generator.fail(self.unit_id, id, .unsupported);
    }
    fn requestState(self: *Emitter, id: core.Id, carries: []const core.LoopCarry, ty: layout.Id) Error!u32 {
        if (carries.len == 1) {
            const state = try self.temporary(self.generator.layouts.machine(ty));
            try self.requestStateValue(id, carries[0].incoming, ty);
            try self.emit(.local_set, state);
            return state;
        }
        if (carries.len == 0) {
            const value = try self.temporary(.i32);
            try self.emit(.i32_const, 0);
            try self.emit(.local_set, value);
            return value;
        }
        if (carries.len > std.math.maxInt(u32) / 4) return self.generator.fail(self.unit_id, id, .complexity);
        const child_types = try self.generator.allocator.dupe(layout.Id, self.generator.layouts.children(ty));
        defer self.generator.allocator.free(child_types);
        if (child_types.len != carries.len) return self.generator.fail(self.unit_id, id, .unresolved_type);
        const state = try self.allocate(@intCast(carries.len * 4));
        for (carries, child_types, 0..) |carry, child_type, index| {
            try self.emit(.local_get, state);
            try self.requestStateValue(id, carry.incoming, child_type);
            try self.emit(if (self.generator.layouts.machine(child_type) == .f32) .f32_store else .i32_store, @intCast(index * 4));
        }
        return state;
    }
    fn requestBindState(self: *Emitter, id: core.Id, state: u32, bindings: []const core.BindingId) Error!void {
        for (bindings, 0..) |binding, index| {
            const ty = try self.generator.scalarWithRows(self.unit_id, self.generator.unit(self.unit_id).binding(binding).ty, self.mappings, self.row_mappings, self.generator.unit(self.unit_id).span(id));
            try self.emit(.local_get, state);
            if (bindings.len > 1) try self.emit(if (ty == .f32) .f32_load else .i32_load, @intCast(index * 4));
            try self.save(binding, id);
        }
    }
    fn requestLoop(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const checkpoint = self.cleanups.mark();
        defer self.cleanups.restore(checkpoint);
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const metadata = source.requestLoopInfo(id);
        const carries = source.requestLoopCarries(id);
        const computation = try self.capture(metadata.computation, depth);
        const state_layout = try self.codeLayout(metadata.state_type, source.span(id));
        const initial = try self.requestState(id, carries, state_layout);
        const state_machine = g.layouts.machine(state_layout);
        const value_machine = (try g.scalarWithRows(self.unit_id, metadata.value_type, self.mappings, self.row_mappings, source.span(id))).machine();
        const result_machine = (try g.scalarWithRows(self.unit_id, metadata.result_type, self.mappings, self.row_mappings, source.span(id))).machine();
        const cell = try self.allocatePrivate(@sizeOf(request_runtime.Cell));
        try self.emit(.local_get, cell);
        try self.emit(.i32_const, 0);
        try self.emit(.i32_store, heap.offset(heap.RequestCell, "status"));
        try self.emit(.local_get, cell);
        try self.emit(.i32_const, 0);
        try self.emit(.i32_store, heap.offset(heap.RequestCell, "exit"));
        try self.emit(.local_get, cell);
        try self.emit(.local_get, initial);
        try self.emit(if (state_machine == .f32) .f32_store else .i32_store, heap.offset(heap.RequestCell, "state"));
        const outer = try self.temporary(.i32);
        try self.providerHead();
        try self.emit(.local_set, outer);
        const provider = try self.temporary(.i32);
        try self.emit(.local_get, outer);
        try self.emit(.local_set, provider);
        for (source.requestArms(id)) |arm| {
            const callback = try self.capture(arm.callback, depth);
            const frame = try self.allocatePrivate(@sizeOf(request_runtime.Frame));
            try self.emit(.local_get, frame);
            try self.operationConstant(try g.requestOperation(self.unit_id, arm.operation, self.mappings, self.row_mappings, source.span(id)));
            try self.emit(.i32_store, heap.offset(heap.RequestFrame, "operation"));
            try self.emit(.local_get, frame);
            try self.emit(.local_get, callback);
            try self.emit(.i32_store, heap.offset(heap.RequestFrame, "target"));
            try self.emit(.local_get, frame);
            try self.emit(.local_get, provider);
            try self.emit(.i32_store, heap.offset(heap.RequestFrame, "outer"));
            try self.emit(.local_get, frame);
            try self.emit(.i32_const, request_runtime.request_kind);
            try self.emit(.i32_store, heap.offset(heap.RequestFrame, "kind"));
            try self.emit(.local_get, frame);
            try self.emit(.local_get, cell);
            try self.emit(.i32_store, heap.offset(heap.RequestFrame, "cell"));
            try self.emit(.local_get, frame);
            try self.emit(.local_get, outer);
            try self.emit(.i32_store, heap.offset(heap.RequestFrame, "runner_outer"));
            try self.emit(.local_get, frame);
            try self.emit(.local_set, provider);
        }
        const value = try self.temporary(value_machine);
        try self.emit(.local_get, computation);
        try self.emit(.i32_load, heap.offset(heap.Closure, "environment"));
        try self.emit(.i32_const, 0);
        try self.emit(.local_get, provider);
        try self.emit(.local_get, computation);
        try self.emit(.i32_load, heap.offset(heap.Closure, "function"));
        try self.emitUnguarded(.call_indirect, try g.module.internType(&.{ .i32, .i32, .i32 }, value_machine));
        try self.emit(.local_set, value);
        try request_runtime.runner(&g.module, self.function_id, g.request_owner.?, cell, &self.cleanups);
        const state = try self.temporary(state_machine);
        try self.emit(.local_get, cell);
        try self.emit(if (state_machine == .f32) .f32_load else .i32_load, heap.offset(heap.RequestCell, "state"));
        try self.emit(.local_set, state);
        try self.emit(.block, 0);
        const exit_label = self.labels;
        self.labels += 1;
        try self.loop_targets.append(g.allocator, .{ .node = id, .label = exit_label, .cleanup = self.cleanups.mark() });
        try self.emit(.local_get, cell);
        try self.emit(.i32_load, heap.offset(heap.RequestCell, "status"));
        try self.emit(.i32_const, @backingInt(request_runtime.Status.exited));
        try self.emit(.i32_eq, 0);
        try self.emit(.if_, 0);
        self.labels += 1;
        var return_target: ?ReturnTarget = null;
        for (self.return_targets.items) |target| if (target.node == metadata.return_target) {
            return_target = target;
            break;
        };
        const parent_return = return_target orelse return g.fail(self.unit_id, id, .unsupported);
        try self.emit(.local_get, cell);
        try self.emit(if (result_machine == .f32) .f32_load else .i32_load, heap.offset(heap.RequestCell, "exit"));
        try self.cleanupTo(parent_return.cleanup);
        try self.emit(.br, self.labels - 1 - parent_return.label);
        self.labels -= 1;
        try self.emit(.end, 0);
        try self.emit(.local_get, cell);
        try self.emit(.i32_load, heap.offset(heap.RequestCell, "status"));
        try self.emit(.i32_const, @backingInt(request_runtime.Status.broken));
        try self.emit(.i32_eq, 0);
        try self.emit(.if_, 0);
        self.labels += 1;
        for (carries, 0..) |carry, index| {
            const ty = try g.scalarWithRows(self.unit_id, source.binding(carry.outgoing).ty, self.mappings, self.row_mappings, source.span(id));
            try self.emit(.local_get, state);
            if (carries.len > 1) try self.emit(if (ty == .f32) .f32_load else .i32_load, @intCast(index * 4));
            try self.save(carry.outgoing, id);
        }
        try self.emit(.br, self.labels - 1 - exit_label);
        self.labels -= 1;
        try self.emit(.end, 0);
        try self.requestBindState(id, state, source.requestCompletionBindings(id));
        try self.emit(.block, 0);
        const pattern_failure = self.labels;
        self.labels += 1;
        try self.matchPattern(id, metadata.completion_pattern, value, pattern_failure, depth + 1);
        _ = try self.suite(metadata.completion_body, depth + 1);
        try self.emit(.unreachable_, 0);
        self.labels -= 1;
        try self.emit(.end, 0);
        try self.emit(.unreachable_, 0);
        self.labels -= 1;
        _ = self.loop_targets.pop();
        try self.emit(.end, 0);
        try self.cleanupTo(checkpoint);
    }
    fn forceDemand(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const n = g.unit(self.unit_id).node(id);
        const demand = try self.capture(n.a, depth);
        const result = try self.scalar(id);
        const cached = try self.temporary(result.machine());
        try self.emit(.local_get, demand);
        try self.emit(.i32_load, heap.offset(heap.Demand, "status"));
        try self.emit(.i32_const, 2);
        try self.emit(.i32_eq, 0);
        try self.emit(.if_, 0);
        self.labels += 1;
        try self.emit(.local_get, demand);
        try self.emit(if (result == .f32) .f32_load else .i32_load, heap.offset(heap.Demand, "cached"));
        try self.emit(.local_set, cached);
        try self.emit(.else_, 0);
        try self.emit(.local_get, demand);
        try self.emit(.i32_load, heap.offset(heap.Demand, "status"));
        try self.emit(.if_, 0);
        try self.emit(.unreachable_, 0);
        try self.emit(.end, 0);
        try self.emit(.local_get, demand);
        try self.emit(.i32_const, 1);
        try self.emit(.i32_store, heap.offset(heap.Demand, "status"));
        try self.emit(.local_get, demand);
        try self.emit(.i32_load, heap.offset(heap.Demand, "environment"));
        try self.emit(.i32_const, 0);
        try self.providerHead();
        try self.emit(.local_get, demand);
        try self.emit(.i32_load, heap.offset(heap.Demand, "function"));
        try self.emitUnguarded(.call_indirect, try g.module.internType(&.{ .i32, .i32, .i32 }, result.machine()));
        try self.emit(.local_set, cached);
        if (g.request_owner) |owner| {
            const checkpoint = self.cleanups.mark();
            defer self.cleanups.restore(checkpoint);
            try self.cleanups.append(g.allocator, .{ .reset_demand = @fromBackingInt(@intCast(demand)) });
            try request_runtime.guard(&g.module, self.function_id, owner, &self.cleanups);
        }
        try self.emit(.local_get, demand);
        try self.emit(.local_get, cached);
        try self.emit(if (result == .f32) .f32_store else .i32_store, heap.offset(heap.Demand, "cached"));
        try self.emit(.local_get, demand);
        try self.emit(.i32_const, 2);
        try self.emit(.i32_store, heap.offset(heap.Demand, "status"));
        const arena = try g.module.ensureArena();
        try self.emit(.local_get, demand);
        try self.emit(.global_get, arena.base);
        try self.emit(.i32_lt_u, 0);
        try self.emit(.if_, 0);
        try self.emit(.global_get, arena.heap);
        try self.emit(.global_set, arena.base);
        try self.emit(.end, 0);
        self.labels -= 1;
        try self.emit(.end, 0);
        try self.emit(.local_get, cached);
    }
    // A selected getter may accept data containing an unobserved callback row.
    // Its ABI is concrete even though that nested row has no closed semantic
    // header. Keep the actual closure/captures in this Session and prove its
    // body against the selected code shape instead of materializing that row.
    // Inlining limits select emission strategy, never source admission.
    fn staticApply(self: *Emitter, id: core.Id, depth: usize) Error!bool {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        if (self.static_values.count() == 0) return false;
        const value = try self.staticReference(node.a) orelse return false;
        if (g.evaluator.valueInfo(value).kind != .closure) return false;
        const header = g.evaluator.closureInfo(value);
        if (header.origin != .anonymous) return false;
        const ty = try self.codeLayout(source.typeOf(node.a), source.span(id));
        const arrow = g.layouts.node(ty);
        if (arrow.tag != .function or arrow.c == layout.unknown_row) return false;
        if (g.toEvidence(ty)) |_| return false else |err| switch (err) {
            error.UnresolvedType => {},
            error.OutOfMemory => return error.OutOfMemory,
            else => return false,
        }
        if (self.hasErasedType(ty, 0)) return false;
        const producer = g.unit(header.unit);
        const metadata = producer.closures[header.identity];
        const bindings = producer.extra[metadata.captures.start..][0..metadata.captures.len];
        const captured = try g.allocator.dupe(core_eval.ValueId, g.evaluator.valueChildren(value));
        defer g.allocator.free(captured);
        if (bindings.len != captured.len) return g.fail(header.unit, metadata.body, .unsupported);
        if (g.artifacts) |artifacts| artifacts.requireFreshCode();
        var mappings: std.ArrayList(Mapping) = .empty;
        defer mappings.deinit(g.allocator);
        var rows: std.ArrayList(RowMapping) = .empty;
        defer rows.deinit(g.allocator);
        for (g.evaluator.type_mappings.items[header.mappings.start..][0..header.mappings.len]) |mapping| {
            const concrete = g.fromEvidence(mapping.evidence) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(header.unit, metadata.body, .unresolved_type);
            try g.mapType(header.unit, &mappings, mapping.variable, concrete, producer.span(metadata.body));
        }
        try g.loadSemanticRows(g.evaluator.row_mappings.items[header.row_mappings.start..][0..header.row_mappings.len], &rows);
        if (metadata.function_type != 0) {
            try g.mapCapturedFunction(header.unit, metadata.function_type, ty, &mappings, &rows, producer.span(metadata.body));
        } else {
            try g.mapType(header.unit, &mappings, metadata.parameter.ty, arrow.a, metadata.parameter.span);
            try g.mapType(header.unit, &mappings, producer.typeOf(metadata.body), arrow.b, producer.span(metadata.body));
        }
        const hints_len = std.math.add(usize, captured.len, @intFromBool(metadata.parameter.binding != 0)) catch return g.fail(header.unit, metadata.body, .complexity);
        const hints = try g.allocator.alloc(core_eval.RetainedCapture, hints_len);
        defer g.allocator.free(hints);
        for (bindings, captured, hints[0..captured.len]) |binding, actual, *hint| {
            hint.* = .{ .binding = binding, .unit = header.unit, .node = 0, .value = actual };
        }
        var argument_rows: std.ArrayList(type_evidence.RowMapping) = .empty;
        defer argument_rows.deinit(g.allocator);
        for (self.row_mappings) |mapping| {
            if (mapping.row == layout.unknown_row) continue;
            const evidence = g.rowToEvidence(mapping.row) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .unresolved_type);
            try argument_rows.append(g.allocator, .{ .variable = mapping.variable, .evidence = evidence });
        }
        if (metadata.parameter.binding != 0) hints[captured.len] = .{
            .binding = metadata.parameter.binding,
            .unit = self.unit_id,
            .node = node.b,
            .mappings = try g.mappingEvidence(self.mappings),
            .rows = argument_rows.items,
            .signature_only = true,
        };
        // The caller's frozen argument signature retains known effect labels
        // beside its open tails. These live hints disable semantic receipts.
        try g.refineAccessorMappings(header.unit, header.identity, ty, &mappings, &rows, producer.span(metadata.body), hints);
        const argument = try self.capture(node.b, depth);
        const inline_body = self.inline_depth < 6 and g.module.functions.items[self.function_id].instructions.items.len <= 4096 and @import("inline_body.zig").cost(producer, metadata.body) != null;
        if (!inline_body) {
            const function_id = try g.capturedClosureFunction(header, ty, captured, mappings.items, rows.items);
            try self.emit(.i32_const, 0);
            try self.emit(.local_get, argument);
            try self.providerHead();
            try self.emit(.call, function_id);
            return true;
        }
        var emitter: Emitter = .{
            .generator = g,
            .unit_id = header.unit,
            .function_id = self.function_id,
            .provider_local = self.provider_local,
            .mappings = mappings.items,
            .row_mappings = rows.items,
            .cleanups = .{ .parent = &self.cleanups },
            .labels = self.labels,
            .inline_depth = self.inline_depth + 1,
        };
        defer emitter.deinit();
        if (metadata.parameter.binding != 0) try emitter.locals.put(g.allocator, metadata.parameter.binding, argument);
        for (bindings, captured) |binding, actual| try emitter.static_values.put(g.allocator, binding, actual);
        try emitter.expression(metadata.body, depth + 1);
        return true;
    }
    fn apply(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const n = unit_.node(id);
        if (unit_.types.node(unit_.typeOf(n.a)).tag == .never) {
            try self.expression(n.a, depth + 1);
            try self.emit(.unreachable_, 0);
            return;
        }
        if (try self.staticApply(id, depth)) return;
        if (try self.partialStaticCall(id, depth)) return;
        if (@import("known_call.zig").resolve(g.units, self.unit_id, id)) |known| {
            if (known.signature != 0) {
                const key = try g.signature(known.target, known.signature, self.unit_id, self.mappings, self.row_mappings, unit_.span(id), false);
                if (key.count == known.count) {
                    if (try self.inlineCollectionEdit(id, key, depth)) return;
                    if (try self.inlineNamedCall(key, known.arguments[0..known.count], depth)) return;
                }
            }
        }
        if (self.static_values.count() == 0 and self.isCallableTemplate(n.a)) {
            const template = (try self.callableTemplate(n.a)).?;
            const ty = try self.codeLayout(unit_.typeOf(n.a), unit_.span(id));
            const function = try self.templateFunction(template, ty);
            const argument = try self.capture(n.b, depth);
            if (template.environment) |env| try self.emit(.local_get, env) else try self.emit(.i32_const, 0);
            try self.emit(.local_get, argument);
            try self.providerHead();
            try self.emit(.call, function);
            return;
        }
        const callee = try self.capture(n.a, depth);
        const argument = try self.capture(n.b, depth);
        const signature = try g.module.internType(&.{ .i32, (try self.scalar(n.b)).machine(), .i32 }, (try self.scalar(id)).machine());
        try self.emit(.local_get, callee);
        try self.emit(.i32_load, heap.offset(heap.Closure, "environment"));
        try self.emit(.local_get, argument);
        try self.providerHead();
        try self.emit(.local_get, callee);
        try self.emit(.i32_load, heap.offset(heap.Closure, "function"));
        try self.emit(.call_indirect, signature);
    }
    fn providerValue(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const n = source.node(id);
        const concrete = try self.codeLayout(n.ty, source.span(id));
        const ty = g.layouts.node(concrete);
        if (n.tag == .effect_provider) {
            if (ty.tag != .provider) return g.fail(self.unit_id, id, .unresolved_type);
            const token = try g.operationLayoutToken(ty.a, self.unit_id, source.span(id));
            const implementation = try self.capture(n.b, depth);
            const provider = try self.allocate(@sizeOf(provider_chain.Provider));
            try self.emit(.local_get, provider);
            try self.operationConstant(token);
            try self.emit(.i32_store, @offsetOf(provider_chain.Provider, "operation"));
            try self.emit(.local_get, provider);
            try self.emit(.local_get, implementation);
            try self.emit(.i32_store, @offsetOf(provider_chain.Provider, "implementation"));
            try self.emit(.local_get, provider);
        } else {
            if (ty.tag != .state_provider) return g.fail(self.unit_id, id, .unresolved_type);
            const read = try g.operationLayoutToken(ty.a, self.unit_id, source.span(id));
            const write = try g.operationLayoutToken(ty.b, self.unit_id, source.span(id));
            const initial = try self.capture(n.c, depth);
            const provider = try self.allocate(@sizeOf(provider_chain.StateProvider));
            try self.emit(.local_get, provider);
            try self.operationConstant(read);
            try self.emit(.i32_store, @offsetOf(provider_chain.StateProvider, "read"));
            try self.emit(.local_get, provider);
            try self.operationConstant(write);
            try self.emit(.i32_store, @offsetOf(provider_chain.StateProvider, "write"));
            try self.emit(.local_get, provider);
            try self.emit(.local_get, initial);
            try self.emit(if (g.layouts.machine(ty.c) == .f32) .f32_store else .i32_store, @offsetOf(provider_chain.StateProvider, "initial"));
            try self.emit(.local_get, provider);
        }
    }
    fn providerFrame(self: *Emitter, provider: u32, operation_offset: u32, target: u32, outer: ?u32, kind: provider_chain.Kind) Error!u32 {
        const frame = try self.allocatePrivate(@sizeOf(provider_chain.Frame));
        try self.emit(.local_get, frame);
        try self.emit(.local_get, provider);
        try self.emit(.i32_load, operation_offset);
        try self.emit(.i32_store, @offsetOf(provider_chain.Frame, "operation"));
        try self.emit(.local_get, frame);
        try self.emit(.local_get, target);
        try self.emit(.i32_store, @offsetOf(provider_chain.Frame, "target"));
        try self.emit(.local_get, frame);
        if (outer) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
        try self.emit(.i32_store, @offsetOf(provider_chain.Frame, "outer"));
        try self.emit(.local_get, frame);
        try self.emit(.i32_const, @backingInt(kind));
        try self.emit(.i32_store, @offsetOf(provider_chain.Frame, "kind"));
        return frame;
    }
    fn effectHandle(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const checkpoint = self.cleanups.mark();
        defer self.cleanups.restore(checkpoint);
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const n = source.node(id);
        const concrete = try self.codeLayout(source.typeOf(n.a), source.span(id));
        const ty = g.layouts.node(concrete);
        const provider = try self.capture(n.a, depth);
        const outer = self.provider_local;
        defer self.provider_local = outer;
        if (ty.tag == .provider) {
            const implementation = try self.temporary(.i32);
            try self.emit(.local_get, provider);
            try self.emit(.i32_load, @offsetOf(provider_chain.Provider, "implementation"));
            try self.emit(.local_set, implementation);
            self.provider_local = try self.providerFrame(provider, @offsetOf(provider_chain.Provider, "operation"), implementation, outer, .callback);
            try self.expression(n.b, depth + 1);
        } else if (ty.tag == .state_provider) {
            const state_machine = g.layouts.machine(ty.c);
            const cell = try self.allocatePrivate(@sizeOf(provider_chain.Cell));
            try self.emit(.local_get, cell);
            try self.emit(.local_get, provider);
            try self.emit(if (state_machine == .f32) .f32_load else .i32_load, @offsetOf(provider_chain.StateProvider, "initial"));
            try self.emit(if (state_machine == .f32) .f32_store else .i32_store, @offsetOf(provider_chain.Cell, "value"));
            const write = try self.providerFrame(provider, @offsetOf(provider_chain.StateProvider, "write"), cell, outer, .state_write);
            self.provider_local = try self.providerFrame(provider, @offsetOf(provider_chain.StateProvider, "read"), cell, write, .state_read);
            const result = try self.capture(n.b, depth);
            const result_machine = (try self.scalar(n.b)).machine();
            const pair = try self.allocate(8);
            try self.emit(.local_get, pair);
            try self.emit(.local_get, cell);
            try self.emit(if (state_machine == .f32) .f32_load else .i32_load, @offsetOf(provider_chain.Cell, "value"));
            try self.emit(if (state_machine == .f32) .f32_store else .i32_store, 0);
            try self.emit(.local_get, pair);
            try self.emit(.local_get, result);
            try self.emit(if (result_machine == .f32) .f32_store else .i32_store, 4);
            try self.emit(.local_get, pair);
        } else return g.fail(self.unit_id, id, .invalid_provider);
        try self.cleanupTo(checkpoint);
    }
    fn resolverOperation(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const metadata = unit_.resolverInfo(id);
        const arguments = unit_.resolverArguments(id);
        const arity: usize = switch (metadata.operation) {
            .monad => 0,
            .pure, .forward, .run => 1,
            .bind, .iterate => 2,
        };
        if (arguments.len != arity) return g.fail(self.unit_id, id, .unsupported);
        const provider_type = try self.codeLayout(unit_.typeOf(metadata.resolver), unit_.span(id));
        const provider = g.layouts.node(provider_type);
        try self.expression(metadata.resolver, depth + 1);
        try self.emit(.drop, 0);
        if (metadata.operation == .monad) {
            if (provider.tag != .type_constructor) return g.fail(self.unit_id, id, .type_constructor_required);
            try self.emit(.i32_const, 0);
            return;
        }
        if (provider.tag != .resolver) return g.fail(self.unit_id, id, .invalid_provider);
        if (metadata.operation == .forward) return self.expression(arguments[0], depth + 1);
        if (metadata.operation == .run) {
            const action = try self.capture(arguments[0], depth);
            const signature = try g.module.internType(&.{ .i32, .i32, .i32 }, (try self.scalar(id)).machine());
            try self.emit(.local_get, action);
            try self.emit(.i32_load, heap.offset(heap.Closure, "environment"));
            try self.emit(.i32_const, 0);
            try self.providerHead();
            try self.emit(.local_get, action);
            try self.emit(.i32_load, heap.offset(heap.Closure, "function"));
            try self.emit(.call_indirect, signature);
            return;
        }
        const token = g.layouts.node(provider.a);
        if (token.tag != .type_constructor) return g.fail(self.unit_id, id, .invalid_provider);
        const identity: types.NominalIdentity = .{ .unit = token.a, .decl = token.b };
        const target = if (metadata.method.binding != 0) try g.normalize(self.unit_id, metadata.method) else (try g.associatedTarget(self.unit_id, identity, metadata.member, .none)) orelse return g.fail(self.unit_id, id, .missing_member);
        var ty = try self.codeLayout(unit_.typeOf(id), unit_.span(id));
        var reverse = arguments.len;
        while (reverse > 0) {
            reverse -= 1;
            const input = try self.codeLayout(unit_.typeOf(arguments[reverse]), unit_.span(arguments[reverse]));
            ty = try g.internLayout(.function, input, ty, &.{});
        }
        if (metadata.method_type != 0) ty = try self.codeLayout(metadata.method_type, unit_.span(id));
        const body = g.unit(target.unit).body(target.binding) orelse return g.fail(self.unit_id, id, .unsupported);
        var consumed: usize = 0;
        if (body.parameters.len != 0 and body.parameters.len <= arguments.len and body.parameters.len <= max_parameters) {
            var key: Key = .{ .target = target, .count = @intCast(body.parameters.len) };
            for (0..body.parameters.len) |index| {
                const arrow = g.layouts.node(ty);
                if (arrow.tag != .function) return g.fail(self.unit_id, id, .unresolved_type);
                key.parameters[index] = arrow.a;
                key.effects[index] = arrow.c;
                ty = arrow.b;
            }
            key.result = ty;
            const function = try g.function(key);
            for (arguments[0..body.parameters.len]) |argument| try self.expression(argument, depth + 1);
            try self.providerHead();
            try self.emit(.call, function);
            consumed = body.parameters.len;
        } else {
            const wrapper = try g.callable(.{ .target = target, .ty = ty });
            const value = try self.capture(arguments[0], depth);
            try self.emit(.i32_const, 0);
            try self.emit(.local_get, value);
            try self.providerHead();
            try self.emit(.call, wrapper);
            ty = g.layouts.node(ty).b;
            consumed = 1;
        }
        for (arguments[consumed..]) |argument| {
            const arrow = g.layouts.node(ty);
            if (arrow.tag != .function) return g.fail(self.unit_id, id, .unresolved_type);
            const function = try self.temporary(.i32);
            try self.emit(.local_set, function);
            const value = try self.capture(argument, depth);
            try self.emit(.local_get, function);
            try self.emit(.i32_load, heap.offset(heap.Closure, "environment"));
            try self.emit(.local_get, value);
            try self.providerHead();
            try self.emit(.local_get, function);
            try self.emit(.i32_load, heap.offset(heap.Closure, "function"));
            try self.emit(.call_indirect, try g.module.internType(&.{ .i32, g.layouts.machine(arrow.a), .i32 }, g.layouts.machine(arrow.b)));
            ty = arrow.b;
        }
    }
    fn emitReference(self: *Emitter, id: core.Id) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const n = unit_.node(id);
        const reference = unit_.reference(id);
        if (reference.unit == 0 or reference.unit == self.unit_id) {
            if (self.computation_values.contains(reference.binding)) {
                const expected = try self.codeLayout(n.ty, unit_.span(id));
                try self.checkComputationABI(reference.binding, expected, id);
            }
            if (self.static_values.get(reference.binding)) |static_value| {
                const ty = try self.codeLayout(n.ty, unit_.span(id));
                if (g.evaluator.valueScalar(static_value)) |value| try self.emit(if (value.scalar == .f32) .f32_const else .i32_const, value.bits) else try self.referenceConstant(try g.serialize(static_value, ty, 0), .static_address);
                return;
            }
            if (self.templates.get(reference.binding)) |template| {
                try self.templateValue(template, try self.codeLayout(n.ty, unit_.span(id)));
                return;
            }
            if (self.locals.get(reference.binding)) |local| {
                try self.emit(.local_get, local);
                return;
            }
        }
        const normalized = try g.normalize(self.unit_id, reference);
        if (g.unit(normalized.unit).body(normalized.binding)) |body| {
            if (body.runtime and !body.is_function) {
                try self.emit(.global_get, try g.runtimeGlobal(normalized));
                return;
            }
        }
        if (unit_.types.node(n.ty).tag == .function) {
            const target = try g.normalize(self.unit_id, reference);
            const ty = try self.codeLayout(n.ty, unit_.span(id));
            if (g.unit(target.unit).body(target.binding).?.is_function) {
                try self.descriptor(try g.callable(.{ .target = target, .ty = ty }), null);
            } else {
                const value = try g.constant(target, ty);
                try g.emitValue(self.function_id, value);
            }
            return;
        }
        const value = try g.constant(try g.normalize(self.unit_id, reference), try self.codeLayout(n.ty, unit_.span(id)));
        try g.emitValue(self.function_id, value);
    }
    fn emitNamedCall(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const call = unit_.call(id);
        const key = try g.signature(call.target, call.callee_type, self.unit_id, self.mappings, self.row_mappings, unit_.span(id), false);
        if (key.count > call.arguments.len) return g.fail(self.unit_id, id, .unsupported);
        if (try self.inlineCollectionEdit(id, key, depth)) return;
        if (try self.inlineDemandCall(key, call.arguments, depth)) return;
        if (try self.inlineStaticCall(key, call.arguments, depth)) return;
        if (try self.inlineNamedCall(key, call.arguments, depth)) return;
        const function_id = try g.function(key);
        for (call.arguments[0..key.count]) |argument| try self.expression(argument, depth + 1);
        try self.providerHead();
        try self.emit(.call, function_id);
        var ty = key.result;
        for (call.arguments[key.count..]) |argument| {
            const fn_type = g.layouts.node(ty);
            if (fn_type.tag != .function) return g.fail(self.unit_id, id, .unresolved_type);
            const callee = try self.temporary(.i32);
            try self.emit(.local_set, callee);
            const value = try self.capture(argument, depth);
            const signature = try g.module.internType(&.{ .i32, g.layouts.machine(fn_type.a), .i32 }, g.layouts.machine(fn_type.b));
            try self.emit(.local_get, callee);
            try self.emit(.i32_load, heap.offset(heap.Closure, "environment"));
            try self.emit(.local_get, value);
            try self.providerHead();
            try self.emit(.local_get, callee);
            try self.emit(.i32_load, heap.offset(heap.Closure, "function"));
            try self.emit(.call_indirect, signature);
            ty = fn_type.b;
        }
    }
    fn emitTypeComparison(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const n = unit_.node(id);
        const left_type = try self.codeLayout(unit_.typeOf(n.a), unit_.span(n.a));
        const right_type = try self.codeLayout(unit_.typeOf(n.b), unit_.span(n.b));
        var left = left_type;
        var right = right_type;
        while (g.layouts.node(left).tag == .function) left = g.layouts.node(left).b;
        while (g.layouts.node(right).tag == .function) right = g.layouts.node(right).b;
        const left_evidence = g.toEvidence(left) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .unresolved_type);
        const right_evidence = g.toEvidence(right) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .unresolved_type);
        try self.expression(n.a, depth + 1);
        try self.emit(.drop, 0);
        try self.expression(n.b, depth + 1);
        try self.emit(.drop, 0);
        try self.emit(.i32_const, @intFromBool(left_evidence == right_evidence));
    }
    fn emitResultAssociated(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const n = unit_.node(id);
        const expected = try self.codeLayout(n.ty, unit_.span(id));
        const target = try self.memberTarget(id, n.b, expected) orelse return g.fail(self.unit_id, id, .missing_associated);
        const input = try self.codeLayout(unit_.typeOf(n.a), unit_.span(id));
        const full = try g.internLayout(.function, input, expected, &.{});
        const wrapper = try g.callable(.{ .target = target, .ty = try self.dispatchCallableLayout(id, full) });
        const argument = try self.capture(n.a, depth);
        try self.emit(.i32_const, 0);
        try self.emit(.local_get, argument);
        try self.providerHead();
        try self.emit(.call, wrapper);
    }
    fn emitLogical(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const n = unit_.node(id);
        if (n.op != .and_ and n.op != .or_) return g.fail(self.unit_id, id, .unsupported);
        try self.expression(n.a, depth + 1);
        try self.emit(.if_, @backingInt(wasm.ValueType.i32));
        self.labels += 1;
        if (n.op == .and_) try self.expression(n.b, depth + 1) else try self.emit(.i32_const, 1);
        try self.emit(.else_, 0);
        if (n.op == .and_) try self.emit(.i32_const, 0) else try self.expression(n.b, depth + 1);
        self.labels -= 1;
        try self.emit(.end, 0);
    }
    fn emitBlock(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        if (!self.exact_probe) if (exact_builder.analyze(unit_, id)) |plan| return self.exactBuilder(id, plan, depth);
        try self.emit(.block, @backingInt((try self.scalar(id)).machine()));
        try self.return_targets.append(g.allocator, .{ .node = id, .label = self.labels, .cleanup = self.cleanups.mark() });
        self.labels += 1;
        const terminated = try self.suite(id, depth + 1);
        if (terminated) try self.emit(.unreachable_, 0) else try self.emit(if (try self.scalar(id) == .f32) .f32_const else .i32_const, 0);
        self.labels -= 1;
        _ = self.return_targets.pop();
        try self.emit(.end, 0);
    }
    fn expression(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const previous_root = self.analysis_root;
        if (previous_root == 0) self.analysis_root = id;
        defer self.analysis_root = previous_root;
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        if (depth >= 1024) return g.fail(self.unit_id, id, .complexity);
        const n = unit_.node(id);
        switch (n.tag) {
            .effect_provider, .state_provider => try self.providerValue(id, depth),
            .computation => try self.expression(n.a, depth + 1),
            .request_decision => try self.requestDecision(id, depth),
            .request_loop => {
                try self.requestLoop(id, depth);
                try self.emit(.i32_const, 0);
            },
            .effect_reflection => return g.fail(self.unit_id, id, .backend_const_only),
            .handle => try self.effectHandle(id, depth),
            .operation_value => {
                const ty = try self.codeLayout(n.ty, unit_.span(id));
                const token = try g.operationToken(self.unit_id, n.a, self.mappings, self.row_mappings, unit_.span(id));
                try self.descriptor(try g.operationFunction(.{ .operation = token, .ty = ty }), null);
            },
            .type_constructor => try self.emit(.i32_const, 0),
            .resolver_op => try self.resolverOperation(id, depth),
            .result_associated => try self.emitResultAssociated(id, depth),
            .product, .record => try self.aggregate(id, depth),
            .record_merge => try self.recordMerge(id, depth),
            .construct => try self.construct(id, depth),
            .project => try self.project(id, depth),
            .update => try self.update(id, depth),
            .array => try self.array(id, depth),
            .array_op => try self.arrayOperation(id, depth),
            .closure, .suspend_ => try self.closure(id),
            .force => if (!try self.inlineDemand(id, depth)) try self.forceDemand(id, depth),
            .apply => try self.apply(id, depth),
            .constructor_function => {
                const ty = try self.codeLayout(n.ty, unit_.span(id));
                try self.descriptor(try g.constructorFunction(.{ .unit = self.unit_id, .catalog = n.a, .ty = ty }), null);
            },
            .primitive_function => {
                const ty = try self.codeLayout(n.ty, unit_.span(id));
                try self.descriptor(try g.primitiveFunction(.{ .unit = self.unit_id, .catalog = n.a, .ty = ty }), null);
            },
            .panic => try self.emit(.unreachable_, 0),
            .type_same => try self.emitTypeComparison(id, depth),
            .constant => try self.emit(if (try self.scalar(id) == .f32) .f32_const else .i32_const, n.a),
            .reference => try self.emitReference(id),
            .scalar, .associated => try self.dispatchScalar(id, depth),
            .logical => try self.emitLogical(id, depth),
            .call => try self.emitNamedCall(id, depth),
            .if_value => {
                try self.expression(n.a, depth + 1);
                try self.emit(.if_, @backingInt((try self.scalar(id)).machine()));
                self.labels += 1;
                try self.expression(n.b, depth + 1);
                try self.emit(.else_, 0);
                try self.expression(n.c, depth + 1);
                self.labels -= 1;
                try self.emit(.end, 0);
            },
            .match => {
                _ = try self.matchExpression(id, depth + 1);
            },
            .block => try self.emitBlock(id, depth),
            else => return g.fail(self.unit_id, id, .unsupported),
        }
    }
    fn save(self: *Emitter, binding: core.BindingId, source: core.Id) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        if (binding == 0 or binding >= unit_.bindings.len) return g.fail(self.unit_id, source, .unsupported);
        const local = self.locals.get(binding) orelse local: {
            const ty = try g.scalarWithRows(self.unit_id, unit_.binding(binding).ty, self.mappings, self.row_mappings, unit_.span(source));
            const result = try g.module.addLocal(self.function_id, ty.machine());
            try self.locals.put(g.allocator, binding, result);
            break :local result;
        };
        try self.emit(.local_set, local);
    }
    fn suite(self: *Emitter, id: core.Id, depth: usize) Error!bool {
        const previous_root = self.analysis_root;
        if (previous_root == 0) self.analysis_root = id;
        defer self.analysis_root = previous_root;
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        if (depth >= 1024) return g.fail(self.unit_id, id, .complexity);
        for (unit_.children(id)) |statement| {
            const n = unit_.node(statement);
            // A diverging initializer cannot produce a value to bind or
            // destructure. Preserve its effects and seal the containing frame.
            if ((n.tag == .bind or n.tag == .pattern_bind) and unit_.types.node(unit_.typeOf(n.b)).tag == .never) {
                try self.expression(n.b, depth + 1);
                try self.emit(.unreachable_, 0);
                return true;
            }
            switch (n.tag) {
                .suite => if (try self.suite(statement, depth + 1)) return true,
                .bind => {
                    if (self.smallCollectionCandidate(n.b)) {
                        if (function_facts.privateBinding(unit_, self.analysis_root, n.a)) if (try self.captureSmallCollection(n.b, depth)) |values| {
                            try self.small_values.put(g.allocator, n.a, values);
                            continue;
                        };
                    }
                    const discarded_value = unit_.node(n.b);
                    if ((discarded_value.tag == .product or discarded_value.tag == .record) and try g.unusedAggregate(self.unit_id, n.a)) {
                        try self.discardAggregateValue(n.b, depth + 1);
                        continue;
                    }
                    if (try self.computationTemplate(n.b)) |template| {
                        try self.templates.put(g.allocator, n.a, template);
                        continue;
                    }
                    const value_node = unit_.node(n.b);
                    if (value_node.tag == .reference) {
                        const reference = unit_.reference(n.b);
                        if (reference.unit == 0 or reference.unit == self.unit_id) if (self.templates.get(reference.binding)) |retained| {
                            try self.templates.put(g.allocator, n.a, retained);
                            continue;
                        };
                    }
                    var template = value_node.tag == .closure or value_node.tag == .constructor_function or value_node.tag == .primitive_function;
                    if (value_node.tag == .reference and unit_.types.node(value_node.ty).tag == .function) {
                        const reference = unit_.reference(n.b);
                        template = reference.unit != 0 and reference.unit != self.unit_id;
                        if (!template) {
                            const kind = unit_.binding(reference.binding).kind;
                            template = kind == .global or kind == .external or self.templates.contains(reference.binding);
                        }
                    }
                    if (template) {
                        try self.templates.put(g.allocator, n.a, try self.newTemplate(n.b));
                        continue;
                    }
                    try self.expression(n.b, depth + 1);
                    const produced_node = unit_.types.node(unit_.typeOf(n.b));
                    if (produced_node.tag == .nominal and produced_node.a == std.math.maxInt(u32) and produced_node.b == 5) {
                        const produced = try self.codeLayout(unit_.typeOf(n.b), unit_.span(n.b));
                        try self.computation_values.put(g.allocator, n.a, produced);
                    }
                    try self.save(n.a, statement);
                },
                .pattern_bind => try self.patternBinding(statement, depth + 1),
                .loop => {
                    try self.loopStatement(statement, depth + 1);
                    const loop = unit_.loopInfo(statement);
                    if (loop.kind == .forever and !loop.can_exit) {
                        try self.emit(.unreachable_, 0);
                        return true;
                    }
                },
                .break_ => {
                    try self.breakStatement(statement, depth + 1);
                    return true;
                },
                .match => {
                    const terminated = try self.matchExpression(statement, depth + 1);
                    if (terminated) return true;
                    try self.emit(.drop, 0);
                },
                .return_ => {
                    var return_target: ?ReturnTarget = null;
                    for (self.return_targets.items) |target| if (target.node == n.b) {
                        return_target = target;
                        break;
                    };
                    const target = return_target orelse return g.fail(self.unit_id, statement, .unsupported);
                    if (target.template_result) try self.templateExpression(n.a, depth + 1) else try self.expression(n.a, depth + 1);
                    try self.cleanupTo(target.cleanup);
                    try self.emit(.br, self.labels - 1 - target.label);
                    return true;
                },
                .if_stmt => {
                    try self.expression(n.a, depth + 1);
                    try self.emit(.if_, 0);
                    self.labels += 1;
                    const then_returns = try self.suite(n.b, depth + 1);
                    if (!then_returns) try self.mergeBranch(statement, true);
                    var else_returns = false;
                    if (n.c != 0 or unit_.branchMerges(statement).len != 0) {
                        try self.emit(.else_, 0);
                        if (n.c != 0) else_returns = try self.suite(n.c, depth + 1);
                        if (!else_returns) try self.mergeBranch(statement, false);
                    }
                    self.labels -= 1;
                    try self.emit(.end, 0);
                    if (then_returns and else_returns) return true;
                },
                else => {
                    try self.expression(statement, depth + 1);
                    // The retained bottom type proves this expression cannot
                    // fall through, including a panic in a guard failure arm.
                    if (unit_.types.node(unit_.typeOf(statement)).tag == .never) {
                        // A nested typed Wasm block still exposes a result at
                        // its end. Seal this containing scope as unreachable.
                        try self.emit(.unreachable_, 0);
                        return true;
                    }
                    try self.emit(.drop, 0);
                },
            }
        }
        return false;
    }
    fn loopStatement(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const metadata = source.loopInfo(id);
        const carries = source.loopCarries(id);
        var counter: u32 = 0;
        var end: u32 = 0;
        var array_local: u32 = 0;
        var list_span: ?[3]u32 = null; // leaf allocation base, start index, end index
        var small: ?SmallCollection = null;
        if (metadata.kind == .range) {
            counter = try self.capture(metadata.first, depth);
            end = try self.capture(metadata.end, depth);
        } else if (metadata.kind == .array) {
            small = try self.captureSmallCollection(metadata.first, depth);
            if (small == null) array_local = try self.capture(metadata.first, depth);
            counter = try self.temporary(.i32);
            end = try self.temporary(.i32);
            try self.emit(.i32_const, 0);
            try self.emit(.local_set, counter);
            if (small) |values| {
                try self.emit(.i32_const, @intCast(values.len));
            } else {
                try self.emit(.local_get, array_local);
                try self.emit(.i32_load, 0);
                const input = try self.codeLayout(source.typeOf(metadata.first), source.span(metadata.first));
                try self.logicalListLength(input);
            }
            try self.emit(.local_set, end);
            const collection = try self.codeLayout(source.typeOf(metadata.first), source.span(metadata.first));
            if (small == null and g.layouts.node(collection).tag == .list) {
                list_span = .{ try self.temporary(.i32), try self.temporary(.i32), try self.temporary(.i32) };
                // Initialize explicitly: this source loop may run inside an
                // outer loop, so Wasm's function-entry local zeroing is not enough.
                try self.emit(.i32_const, 0);
                try self.emit(.local_set, list_span.?[2]);
            }
        }
        // A floor belongs to this activation. Earlier allocations are pinned
        // and traced. Collect after allocation traffic proportional to the
        // arena, so a small cursor does not repeatedly trace a large snapshot.
        const floor = if (metadata.kind == .forever) try self.temporary(.i32) else null;
        const cadence = if (metadata.kind == .forever) try self.temporary(.i32) else null;
        const budget = if (metadata.kind == .forever) try self.temporary(.i32) else null;
        if (floor) |local| {
            const arena = try g.module.ensureArena();
            try self.emit(.global_get, arena.heap);
            try self.emit(.local_set, local);
            try self.collectionBudget(cadence.?, budget.?);
        }
        for (carries) |carry| {
            const incoming = self.locals.get(carry.incoming) orelse return g.fail(self.unit_id, id, .unsupported);
            try self.emit(.local_get, incoming);
            try self.save(carry.iteration, id);
            // Initialize the exit version before entering the loop, including
            // its zero-iteration path. Backedges and break edges replace it.
            try self.emit(.local_get, incoming);
            try self.save(carry.outgoing, id);
        }
        try self.emit(.block, 0);
        const exit_label = self.labels;
        self.labels += 1;
        try self.loop_targets.append(g.allocator, .{ .node = id, .label = exit_label, .cleanup = self.cleanups.mark() });
        try self.emit(.loop, 0);
        const head_label = self.labels;
        self.labels += 1;
        if (metadata.kind != .forever) {
            try self.emit(.local_get, counter);
            try self.emit(.local_get, end);
            try self.emit(.i32_ge_u, 0);
            try self.emit(.br_if, self.labels - 1 - exit_label);
        }
        if (metadata.pattern != 0) {
            var element = counter;
            if (metadata.kind == .array) {
                const array_type = try self.codeLayout(source.typeOf(metadata.first), source.span(metadata.first));
                const machine = g.layouts.machine(g.layouts.node(array_type).a);
                element = try self.temporary(machine);
                const is_list = g.layouts.node(array_type).tag == .list;
                const words = packed_layout.collectionRowWords(&g.layouts, array_type);
                if (small) |values| {
                    try self.smallCollectionElement(values, counter, 0, values.len);
                } else if (list_span) |span| {
                    const position = if (words > 1) try self.multiplyLocal(counter, words) else counter;
                    // Resolve one leaf per span. Its immutable allocation base
                    // stays valid if a nested traversal changes the descriptor's
                    // lookup cache or a nested forever loop runs the collector.
                    try self.emit(.local_get, position);
                    try self.emit(.local_get, span[2]);
                    try self.emit(.i32_ge_u, 0);
                    try self.emit(.if_, 0);
                    try self.emit(.local_get, array_local);
                    try self.emit(.local_get, position);
                    try self.emit(.call, (try g.module.ensureLists()).address);
                    try self.emit(.drop, 0);
                    try self.emit(.local_get, array_local);
                    try self.emit(.i32_load, 8);
                    try self.emit(.local_set, span[0]);
                    try self.emit(.local_get, array_local);
                    try self.emit(.i32_load, 12);
                    try self.emit(.local_tee, span[1]);
                    try self.emit(.local_get, span[0]);
                    try self.emit(.i32_load, 8);
                    try self.emit(.i32_add, 0);
                    try self.emit(.local_set, span[2]);
                    try self.emit(.end, 0);
                    if (words != 0) {
                        try self.readListRow(array_local, counter, words, .{ span[0], span[1] });
                    } else {
                        try self.emit(.local_get, span[0]);
                        try self.emit(.i32_const, @import("list_runtime.zig").header);
                        try self.emit(.i32_add, 0);
                        try self.emit(.local_get, position);
                        try self.emit(.local_get, span[1]);
                        try self.emit(.i32_sub, 0);
                        try self.emit(.i32_const, 4);
                        try self.emit(.i32_mul, 0);
                        try self.emit(.i32_add, 0);
                    }
                } else try self.arrayAddress(array_local, counter, packed_layout.stride(packed_layout.arrayRowWords(&g.layouts, array_type)));
                if (small == null and !(is_list and words != 0)) try self.readElement(machine, if (is_list) 0 else 4, packed_layout.arrayRowWords(&g.layouts, array_type));
                try self.emit(.local_set, element);
            }
            if (plainBindingPattern(source, metadata.pattern, 0)) {
                // These patterns cannot branch. Their definitions dominate
                // the loop body, including scalar replacement of local rows.
                try self.matchPattern(id, metadata.pattern, element, self.labels, depth + 1);
            } else {
                // Keep a trap path for patterns that perform runtime tests.
                try self.emit(.block, 0);
                const matched = self.labels;
                self.labels += 1;
                try self.emit(.block, 0);
                const failed = self.labels;
                self.labels += 1;
                try self.matchPattern(id, metadata.pattern, element, failed, depth + 1);
                try self.emit(.br, self.labels - 1 - matched);
                self.labels -= 1;
                try self.emit(.end, 0);
                try self.emit(.unreachable_, 0);
                self.labels -= 1;
                try self.emit(.end, 0);
            }
        }
        if (!try self.suite(metadata.body, depth + 1)) {
            // Push every predecessor before changing any iteration slot.
            for (carries) |carry| {
                const backedge = self.locals.get(carry.backedge) orelse return g.fail(self.unit_id, id, .unsupported);
                try self.emit(.local_get, backedge);
            }
            var index = carries.len;
            while (index != 0) {
                index -= 1;
                try self.save(carries[index].iteration, id);
            }
            for (carries) |carry| {
                try self.emit(.local_get, self.locals.get(carry.iteration).?);
                try self.save(carry.outgoing, id);
            }
            if (floor) |local| try self.collectLoopCarries(id, carries, local, cadence.?, budget.?);
            if (metadata.kind != .forever) {
                try self.emit(.local_get, counter);
                try self.emit(.i32_const, 1);
                try self.emit(.i32_add, 0);
                try self.emit(.local_set, counter);
            }
            try self.emit(.br, self.labels - 1 - head_label);
        }
        self.labels -= 1;
        try self.emit(.end, 0);
        self.labels -= 1;
        _ = self.loop_targets.pop();
        try self.emit(.end, 0);
    }
    fn collectLoopCarries(self: *Emitter, id: core.Id, carries: []const core.LoopCarry, floor: u32, cadence: u32, budget: u32) Error!void {
        const g = self.generator;
        if (carries.len >= std.math.maxInt(u32) / 4) return g.fail(self.unit_id, id, .complexity);
        const arena = try g.module.ensureArena();
        try self.emit(.global_get, arena.allocated);
        try self.emit(.local_get, cadence);
        try self.emit(.i32_sub, 0);
        try self.emit(.local_get, budget);
        try self.emit(.i32_ge_u, 0);
        try self.emit(.if_, 0);
        self.labels += 1;
        const root = try self.allocate(@intCast((carries.len + 1) * 4));
        for (carries, 0..) |carry, index| {
            const value = self.locals.get(carry.iteration) orelse return g.fail(self.unit_id, id, .unsupported);
            const function_ = &g.module.functions.items[self.function_id];
            const machine = if (value < function_.parameters.len) function_.parameters[value] else function_.locals.items[value - function_.parameters.len];
            try self.emit(.local_get, root);
            try self.emit(.local_get, value);
            try self.emit(if (machine == .f32) .f32_store else .i32_store, @intCast(index * 4));
        }
        try self.emit(.local_get, root);
        try self.providerHead();
        try self.emit(.i32_store, @intCast(carries.len * 4));
        try self.emit(.local_get, root);
        try self.emit(.local_get, floor);
        try self.emit(.i32_const, 0);
        try self.emit(.call, arena.collect);
        try self.emit(.drop, 0);
        try self.collectionBudget(cadence, budget);
        self.labels -= 1;
        try self.emit(.end, 0);
    }
    fn collectionBudget(self: *Emitter, cadence: u32, destination: u32) Error!void {
        const arena = try self.generator.module.ensureArena();
        try self.emit(.global_get, arena.heap);
        // Startup values and static data are traced too, even below arena.base.
        // Include that retained footprint when amortizing collection work.
        try self.emit(.i32_const, 2);
        try self.emit(.i32_shr_u, 0);
        try self.emit(.local_set, destination);
        try self.emit(.local_get, destination);
        try self.emit(.i32_const, 65536);
        try self.emit(.i32_lt_u, 0);
        try self.emit(.if_, 0);
        try self.emit(.i32_const, 65536);
        try self.emit(.local_set, destination);
        try self.emit(.end, 0);
        try self.emit(.global_get, arena.allocated);
        try self.emit(.local_set, cadence);
    }
    fn breakStatement(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const target = source.node(id).a;
        var selected: ?LoopTarget = null;
        for (self.loop_targets.items) |loop_target| if (loop_target.node == target) {
            selected = loop_target;
            break;
        };
        const exit_target = selected orelse return g.fail(self.unit_id, id, .unsupported);
        const carries = if (source.node(target).tag == .request_loop) source.requestLoopCarries(target) else source.loopCarries(target);
        const values = source.breakValues(id);
        if (values.len != carries.len) return g.fail(self.unit_id, id, .unsupported);
        for (values) |value| try self.expression(value, depth + 1);
        var index = carries.len;
        while (index != 0) {
            index -= 1;
            try self.save(carries[index].outgoing, id);
        }
        try self.cleanupTo(exit_target.cleanup);
        try self.emit(.br, self.labels - 1 - exit_target.label);
    }
    fn dispatchIdentity(self: *Emitter, concrete: layout.Id) ?types.NominalIdentity {
        const value = self.generator.layouts.node(concrete);
        return switch (value.tag) {
            .nominal => .{ .unit = value.a, .decl = value.b },
            .unit => .{ .unit = 0, .decl = types.unit },
            .boolean => .{ .unit = 0, .decl = types.boolean },
            .u32 => .{ .unit = 0, .decl = types.u32_type },
            .f32 => .{ .unit = 0, .decl = types.f32_type },
            .array => .{ .unit = 0, .decl = std.math.maxInt(u32) },
            .list => .{ .unit = 0, .decl = std.math.maxInt(u32) - 1 },
            .cursor => .{ .unit = 0, .decl = std.math.maxInt(u32) - 2 },
            else => null,
        };
    }
    fn dispatchCandidate(self: *Emitter, id: core.Id, identity: types.NominalIdentity, operation: types.Operator, member: u32, left: layout.Id, right: layout.Id, result: layout.Id) Error!?Key {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        if (try g.associatedTarget(self.unit_id, identity, member, operation)) |target| {
            const producer = g.unit(target.unit);
            const first = producer.types.node(producer.binding(target.binding).scheme.root);
            if (first.tag != .function) return null;
            const second = producer.types.node(first.b);
            if (second.tag != .function) return null;
            // Failed parameter probes restore the
            // prior diagnostic and cannot affect another candidate's mapping.
            var trial: std.ArrayList(Mapping) = .empty;
            defer trial.deinit(g.allocator);
            const previous_diagnostic = g.diagnostic;
            g.mapType(target.unit, &trial, first.a, left, unit_.span(id)) catch |err| switch (err) {
                error.Declined => {
                    g.diagnostic = previous_diagnostic;
                    return null;
                },
                else => return err,
            };
            g.mapType(target.unit, &trial, second.a, right, unit_.span(id)) catch |err| switch (err) {
                error.Declined => {
                    g.diagnostic = previous_diagnostic;
                    return null;
                },
                else => return err,
            };
            // Return compatibility is checked after selection. A bad result
            // must fail this use, never select the right operand's method.
            try g.mapType(target.unit, &trial, second.b, result, unit_.span(id));
            var effects: [max_parameters]u32 = @splat(0);
            const signature = unit_.dispatchSignature(id);
            if (signature != 0) {
                var ty = try self.codeLayout(signature, unit_.span(id));
                for (0..2) |index| {
                    const arrow = g.layouts.node(ty);
                    if (arrow.tag != .function) return g.fail(self.unit_id, id, .unresolved_type);
                    effects[index] = arrow.c;
                    ty = arrow.b;
                }
            }
            return .{ .target = target, .effects = effects, .parameters = blk: {
                var parameters: [max_parameters]layout.Id = @splat(1);
                parameters[0] = left;
                parameters[1] = right;
                break :blk parameters;
            }, .count = 2, .result = result };
        }
        return null;
    }
    fn dispatchCall(self: *Emitter, id: core.Id, key: Key, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        const arguments = [_]core.Id{ node.a, node.b };
        const body = g.unit(key.target.unit).body(key.target.binding) orelse return g.fail(self.unit_id, id, .unsupported);
        // A selected method can return a function before or after consuming both operands.
        const arity = if (body.is_function) body.parameters.len else key.count;
        var ty = key.result;
        var consumed: usize = 0;
        if (arity != 0 and arity <= key.count) {
            var direct: Key = .{ .target = key.target, .count = @intCast(arity) };
            @memcpy(direct.parameters[0..arity], key.parameters[0..arity]);
            @memcpy(direct.effects[0..arity], key.effects[0..arity]);
            var reverse: usize = key.count;
            while (reverse > arity) {
                reverse -= 1;
                ty = try g.internLayoutWithEffects(.function, key.parameters[reverse], ty, key.effects[reverse], &.{});
            }
            direct.result = ty;
            if (arity == key.count and try self.inlineNamedCall(direct, arguments[0..arity], depth)) return;
            const function = try g.function(direct);
            for (arguments[0..arity]) |argument| try self.expression(argument, depth + 1);
            try self.providerHead();
            try self.emit(.call, function);
            consumed = arity;
        } else {
            var full = key.result;
            var reverse: usize = key.count;
            while (reverse > 0) {
                reverse -= 1;
                full = try g.internLayoutWithEffects(.function, key.parameters[reverse], full, key.effects[reverse], &.{});
            }
            const wrapper = try g.callable(.{ .target = key.target, .ty = full });
            const argument = try self.capture(arguments[0], depth);
            try self.emit(.i32_const, 0);
            try self.emit(.local_get, argument);
            try self.providerHead();
            try self.emit(.call, wrapper);
            ty = g.layouts.node(full).b;
            consumed = 1;
        }
        for (arguments[consumed..]) |argument| {
            const arrow = g.layouts.node(ty);
            if (arrow.tag != .function) return g.fail(self.unit_id, id, .unresolved_type);
            const callee = try self.temporary(.i32);
            try self.emit(.local_set, callee);
            const value = try self.capture(argument, depth);
            try self.emit(.local_get, callee);
            try self.emit(.i32_load, heap.offset(heap.Closure, "environment"));
            try self.emit(.local_get, value);
            try self.providerHead();
            try self.emit(.local_get, callee);
            try self.emit(.i32_load, heap.offset(heap.Closure, "function"));
            try self.emit(.call_indirect, try g.module.internType(&.{ .i32, g.layouts.machine(arrow.a), .i32 }, g.layouts.machine(arrow.b)));
            ty = arrow.b;
        }
    }
    fn dispatchScalar(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const value = unit_.node(id);
        if (value.tag == .scalar and (value.c == 0 or value.b == 0)) {
            const input = try self.codeLayout(unit_.typeOf(value.a), unit_.span(id));
            if (g.layouts.node(input).tag == .product) {
                var operands: [2]u32 = undefined;
                operands[0] = try self.capture(value.a, depth);
                if (value.b != 0) operands[1] = try self.capture(value.b, depth);
                return self.simdLocals(value.op, operands[0..if (value.b == 0) @as(usize, 1) else 2], input);
            }
            const opcode = scalar_ops.opcode(value.op, try self.scalar(value.a)) orelse return g.fail(self.unit_id, id, .unsupported);
            try self.expression(value.a, depth + 1);
            if (value.b != 0) try self.expression(value.b, depth + 1);
            return self.emit(opcode, 0);
        }
        const operation: types.Operator = switch (value.op) {
            .add => .add,
            .sub => .sub,
            .mul => .mul,
            .div => .div,
            .rem => .rem,
            .equal => .equal,
            .not_equal => .not_equal,
            .less => .less,
            .less_equal => .less_equal,
            .greater => .greater,
            .greater_equal => .greater_equal,
            .bit_and => .bit_and,
            .bit_or => .bit_or,
            .bit_xor => .bit_xor,
            .shift_left => .shift_left,
            .shift_right => .shift_right,
            .none => .none,
            else => return g.fail(self.unit_id, id, .unsupported),
        };
        const member = if (value.tag == .associated) value.c else 0;
        const left = try self.codeLayout(unit_.typeOf(value.a), unit_.span(id));
        const right = try self.codeLayout(unit_.typeOf(value.b), unit_.span(id));
        const result = try self.codeLayout(value.ty, unit_.span(id));
        const left_identity = self.dispatchIdentity(left);
        if (left_identity) |identity| if (try self.dispatchCandidate(id, identity, operation, member, left, right, result)) |key| {
            return self.dispatchCall(id, key, depth);
        };
        if (left == right) if (g.layouts.scalar(left)) |scalar_type| {
            const admitted = scalar_type == .u32 or scalar_type == .f32 or (scalar_type == .bool and (operation == .equal or operation == .not_equal));
            if (admitted) if (scalar_ops.opcode(value.op, scalar_type)) |opcode| {
                const comparison = operation == .equal or operation == .not_equal or operation == .less or operation == .less_equal or operation == .greater or operation == .greater_equal;
                if (result != (if (comparison) types.boolean else left)) return g.fail(self.unit_id, id, .unresolved_type);
                try self.expression(value.a, depth + 1);
                try self.expression(value.b, depth + 1);
                return self.emit(opcode, 0);
            };
        };
        if (self.dispatchIdentity(right)) |identity| if (left_identity == null or left_identity.?.unit != identity.unit or left_identity.?.decl != identity.decl) {
            if (try self.dispatchCandidate(id, identity, operation, member, left, right, result)) |key| {
                return self.dispatchCall(id, key, depth);
            }
        };
        return g.fail(self.unit_id, id, .unsupported);
    }
    fn patternMachine(self: *Emitter, ty: types.Id, span: core.Span) Error!wasm.ValueType {
        return (try self.generator.scalarWithRows(self.unit_id, ty, self.mappings, self.row_mappings, span)).machine();
    }
    fn plainBindingPattern(source: *const core.Module, id: core.PatternId, depth: usize) bool {
        if (depth >= 32) return false;
        return switch (source.pattern(id).tag) {
            .bind, .wildcard => true,
            .product => blk: {
                for (source.patternChildren(id)) |child| if (!plainBindingPattern(source, child, depth + 1)) break :blk false;
                break :blk true;
            },
            else => false,
        };
    }
    /// The row's failure block is shared by every nested test. Binding slots
    /// may be filled before a later test fails; their checked identities are
    /// local to this arm and a successful alternative overwrites every binder.
    fn matchProduct(self: *Emitter, source: core.Id, pattern_id: core.PatternId, value_local: u32, failure_label: u32, record: types.Node, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        if (depth >= 1024) return g.decline(self.unit_id, unit_.pattern(pattern_id).span, .complexity);
        if (unit_.patternChildren(pattern_id).len != 0) _ = try g.module.ensureArena();
        var buffer: [256]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&buffer, g.allocator);
        const order = if (record.tag == .record) try @import("record_order.zig").destinations(scratch.allocator(), unit_.types, record, &g.layouts.record_names) else &.{};
        defer scratch.allocator().free(order);
        for (unit_.patternChildren(pattern_id), 0..) |child, index| {
            const child_pattern = unit_.pattern(child);
            const machine = try self.patternMachine(child_pattern.ty, child_pattern.span);
            const local = try g.module.addLocal(self.function_id, machine);
            try self.emit(.local_get, value_local);
            try self.emit(if (machine == .f32) .f32_load else .i32_load, @intCast((if (order.len == 0) index else order[index]) * 4));
            try self.emit(.local_set, local);
            try self.matchPattern(source, child, local, failure_label, depth + 1);
        }
    }
    fn matchPattern(self: *Emitter, source: core.Id, pattern_id: core.PatternId, value_local: u32, failure_label: u32, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const p = unit_.pattern(pattern_id);
        if (depth >= 1024) return g.decline(self.unit_id, p.span, .complexity);
        switch (p.tag) {
            .wildcard => {},
            .bind => {
                try self.emit(.local_get, value_local);
                try self.save(p.a, source);
            },
            .constant, .value => {
                const machine = try self.patternMachine(p.ty, p.span);
                try self.emit(.local_get, value_local);
                if (p.tag == .constant) try self.emit(if (machine == .f32) .f32_const else .i32_const, p.a) else try self.expression(p.a, depth + 1);
                try self.emit(if (machine == .f32) .f32_ne else .i32_ne, 0);
                try self.emit(.br_if, self.labels - 1 - failure_label);
            },
            .product => try self.matchProduct(source, pattern_id, value_local, failure_label, unit_.types.node(p.ty), depth),
            .record_payload => {
                if (p.a == 1) {
                    _ = try g.module.ensureArena();
                    const child = unit_.pattern(p.b);
                    const machine = try self.patternMachine(child.ty, child.span);
                    const local = try g.module.addLocal(self.function_id, machine);
                    try self.emit(.local_get, value_local);
                    try self.emit(if (machine == .f32) .f32_load else .i32_load, 0);
                    try self.emit(.local_set, local);
                    try self.matchPattern(source, p.b, local, failure_label, depth + 1);
                } else if (unit_.pattern(p.b).tag == .product) {
                    // Destructuring only needs permuted loads, not a temporary
                    // tuple allocation. A whole-payload binder needs the view.
                    try self.matchProduct(source, p.b, value_local, failure_label, unit_.types.node(p.ty), depth + 1);
                } else if (unit_.pattern(p.b).tag != .wildcard) {
                    const product = try self.recordRepresentation(unit_.types.node(p.ty), value_local, false);
                    try self.matchPattern(source, p.b, product, failure_label, depth + 1);
                }
            },
            .constructor => {
                _ = try g.module.ensureArena();
                const metadata = unit_.constructor(p.a);
                try self.emit(.local_get, value_local);
                try self.emit(.i32_load, 0);
                try self.emit(.i32_const, metadata.tag);
                try self.emit(.i32_ne, 0);
                try self.emit(.br_if, self.labels - 1 - failure_label);
                if (p.b != 0) {
                    const payload = unit_.pattern(p.b);
                    const machine = try self.patternMachine(payload.ty, payload.span);
                    const local = try g.module.addLocal(self.function_id, machine);
                    try self.emit(.local_get, value_local);
                    try self.emit(if (machine == .f32) .f32_load else .i32_load, 4);
                    try self.emit(.local_set, local);
                    try self.matchPattern(source, p.b, local, failure_label, depth + 1);
                }
            },
            .invalid => return g.decline(self.unit_id, p.span, .unsupported),
        }
    }
    fn matchExpression(self: *Emitter, id: core.Id, depth: usize) Error!bool {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        if (depth >= 1024) return g.fail(self.unit_id, id, .complexity);
        const metadata = unit_.matchInfo(id);
        var storage_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var storage: std.heap.BufferFirstAllocator = .init(&storage_buffer, g.allocator);
        const scratch = storage.allocator();
        var inputs: std.ArrayList(u32) = .empty;
        defer inputs.deinit(scratch);
        const source_inputs = unit_.matchInputs(id);
        try inputs.ensureTotalCapacityPrecise(scratch, @min(source_inputs.len, 16));
        for (source_inputs) |input| {
            if (unit_.types.node(unit_.typeOf(input)).tag == .never) {
                try self.expression(input, depth + 1);
                try self.emit(.unreachable_, 0);
                return true;
            }
            const local = try g.module.addLocal(self.function_id, (try self.scalar(input)).machine());
            try self.expression(input, depth + 1);
            try self.emit(.local_set, local);
            try inputs.append(scratch, local);
        }
        try self.emit(.block, @backingInt((try self.scalar(id)).machine()));
        const result_label = self.labels;
        self.labels += 1;
        var all_terminate = metadata.statement;
        for (unit_.matchArms(id), 0..) |arm, arm_index| {
            try self.emit(.block, 0);
            const next_arm = self.labels;
            self.labels += 1;
            for (unit_.armRows(arm)) |row| {
                const patterns = unit_.rowPatterns(row);
                if (patterns.len != inputs.items.len) return g.fail(self.unit_id, id, .unsupported);
                try self.emit(.block, 0);
                const next_row = self.labels;
                self.labels += 1;
                for (patterns, inputs.items) |pattern_id, local| try self.matchPattern(id, pattern_id, local, next_row, depth + 1);
                if (arm.guard != 0) {
                    try self.expression(arm.guard, depth + 1);
                    try self.emit(.i32_eqz, 0);
                    // Alternatives share one selected binding set and guard.
                    // A rejected guard advances to the next source arm.
                    try self.emit(.br_if, self.labels - 1 - next_arm);
                }
                const terminated = if (metadata.statement) try self.suite(arm.body, depth + 1) else terminated: {
                    try self.expression(arm.body, depth + 1);
                    break :terminated false;
                };
                all_terminate = all_terminate and terminated;
                if (!terminated) {
                    if (metadata.statement) {
                        try self.mergeBranch(id, arm_index == 0);
                        try self.emit(.i32_const, 0);
                    }
                    try self.emit(.br, self.labels - 1 - result_label);
                }
                self.labels -= 1;
                try self.emit(.end, 0);
            }
            self.labels -= 1;
            try self.emit(.end, 0);
        }
        // The checker proves coverage; reaching this point is impossible for
        // a typed runtime value and also seals Wasm's result stack correctly.
        try self.emit(.unreachable_, 0);
        self.labels -= 1;
        try self.emit(.end, 0);
        return all_terminate;
    }
    const StaticBinding = struct { binding: core.BindingId, value: core_eval.ValueId };
    fn staticPattern(self: *Emitter, pattern_id: core.PatternId, value: core_eval.ValueId, bindings: *std.ArrayList(StaticBinding), depth: usize) Error!bool {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        if (depth >= 1024) return g.decline(self.unit_id, source.pattern(pattern_id).span, .complexity);
        const p = source.pattern(pattern_id);
        const info = g.evaluator.valueInfo(value);
        switch (p.tag) {
            .wildcard => return true,
            .bind => {
                try bindings.append(g.allocator, .{ .binding = p.a, .value = value });
                return true;
            },
            .record_payload => {
                if (info.kind != .record or info.len != p.a) return false;
                const canonical = g.evaluator.recordPayload(self.unit_id, pattern_id, value) catch |err| switch (err) {
                    error.RequestUnwind, error.Declined => return g.evaluationFailure(),
                    error.OutOfMemory => return error.OutOfMemory,
                };
                return self.staticPattern(p.b, canonical, bindings, depth + 1);
            },
            .constructor => {
                if (info.kind != .nominal) return false;
                const constructor = source.constructor(p.a);
                const family = source.nominal(constructor.nominal).identity;
                const identity = (@as(u64, if (family.unit == 0) self.unit_id else family.unit) << 32) | family.decl;
                if (info.nominal != identity or info.bits != constructor.tag) return false;
                if (p.b == 0) return true;
                const children = g.evaluator.valueChildren(value);
                if (children.len != 1) return false;
                return self.staticPattern(p.b, children[0], bindings, depth + 1);
            },
            .product => {
                if (info.kind != .product and info.kind != .record) return false;
                const patterns = source.patternChildren(pattern_id);
                const children = g.evaluator.valueChildren(value);
                if (patterns.len != children.len) return false;
                const record = source.types.node(p.ty);
                const names = g.evaluator.recordFieldNames(value);
                for (patterns, 0..) |child_pattern, index| {
                    var slot = index;
                    if (info.kind == .record) {
                        if (record.tag != .record) return false;
                        const name = source.types.recordField(record, index).name;
                        var found = false;
                        for (names, 0..) |field, field_slot| if (field == name) {
                            slot = field_slot;
                            found = true;
                            break;
                        };
                        if (!found) return false;
                    }
                    if (!try self.staticPattern(child_pattern, children[slot], bindings, depth + 1)) return false;
                }
                return true;
            },
            else => return false,
        }
    }
    fn staticPatternBinding(self: *Emitter, id: core.Id) Error!bool {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const n = source.node(id);
        // Concrete values use ordinary runtime loads. This path retains only
        // a constant whose polymorphic children cannot yet have one layout.
        if (g.layouts.fromType(source, source.typeOf(n.b), self.mappings)) |ty| {
            if (!self.hasErasedType(ty, 0)) return false;
        } else |err| if (err == error.OutOfMemory) return error.OutOfMemory;
        const value = try self.staticReference(n.b) orelse return false;
        var bindings: std.ArrayList(StaticBinding) = .empty;
        defer bindings.deinit(g.allocator);
        if (!try self.staticPattern(n.a, value, &bindings, 0)) return false;
        for (bindings.items) |binding| try self.static_values.put(g.allocator, binding.binding, binding.value);
        return true;
    }
    fn patternBinding(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const n = unit_.node(id);
        if (try self.staticPatternBinding(id)) return;
        const local = try g.module.addLocal(self.function_id, (try self.scalar(n.b)).machine());
        try self.expression(n.b, depth + 1);
        try self.emit(.local_set, local);
        try self.emit(.block, 0);
        const completed = self.labels;
        self.labels += 1;
        try self.emit(.block, 0);
        const failed = self.labels;
        self.labels += 1;
        try self.matchPattern(id, n.a, local, failed, depth + 1);
        try self.emit(.br, self.labels - 1 - completed);
        self.labels -= 1;
        try self.emit(.end, 0);
        if (n.c == 0) {
            try self.emit(.unreachable_, 0);
        } else if (!try self.suite(n.c, depth + 1)) return g.fail(self.unit_id, id, .unsupported);
        self.labels -= 1;
        try self.emit(.end, 0);
    }
    fn mergeBranch(self: *Emitter, id: core.Id, left: bool) Error!void {
        const g = self.generator;
        for (g.unit(self.unit_id).branchMerges(id)) |merge| {
            const binding = if (left) merge.then_binding else merge.else_binding;
            const local = self.locals.get(binding) orelse return g.fail(self.unit_id, id, .unsupported);
            try self.emit(.local_get, local);
            try self.save(merge.result, id);
        }
    }
};
