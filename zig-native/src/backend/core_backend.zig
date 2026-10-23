//! Code instances and compile-time values share immutable typed core bodies.
const DictionaryOwner = @import("../check/dictionary_owner.zig").Owner;
const std = @import("std");
const core = @import("../check/core.zig");
const types = @import("../check/types.zig");
const wasm = @import("wasm.zig");
const scalar_ops = @import("scalar_ops.zig");
const core_eval = @import("../eval/core_eval.zig");
const type_evidence = @import("../eval/type_evidence.zig");
const substitution_keys = @import("../reuse/substitution_keys.zig");
const provider_chain = @import("provider_chain.zig");
const layout = @import("layout.zig");
const request_runtime = @import("../runtime/request_runtime.zig");
const heap = @import("../runtime/runtime_layout.zig");
const function_facts = @import("function_facts.zig");
const ragged_builder = @import("ragged_builder.zig");
const runtime_operations = @import("runtime_operations.zig");
const runtime_identity = @import("runtime_identity.zig");
const dispatch_explanation = @import("../reuse/dispatch_explanation.zig");
const ir = @import("runtime_ir.zig");
const owned_arrays = @import("owned_arrays.zig");
const artifact_emitter = @import("../reuse/artifact_emitter.zig");
const code_artifacts = @import("../reuse/code_artifacts.zig");
const artifact_capture = @import("../reuse/artifact_capture.zig");
const artifact_fragment = @import("../reuse/artifact_fragment.zig");
const principal_evidence_reuse = @import("../reuse/principal_evidence_reuse.zig");
const completed_specialization_query = @import("../eval/completed_specialization_query.zig");
const shared_query_gate = @import("../reuse/shared_query_gate.zig");
const discarded_bindings = @import("discarded_bindings.zig");
const startup_emission_facts = @import("startup_emission_facts.zig");
const Allocator = std.mem.Allocator;
const Scalar = wasm.Scalar;
const Value = scalar_ops.Value;
const max_parameters = code_artifacts.max_parameters;
pub const Code = @import("../check/diagnostic_code.zig").Code;
pub const Diagnostic = struct {
    unit: u32,
    span: core.Span,
    code: Code,
    detail: []const u8 = &.{},
    /// Assembly rejection copied before the generated module is released.
    ownership: ?wasm.OwnershipFailure = null,
    /// Candidates of the failed dispatch this diagnostic reports.
    dispatch: ?core_eval.DispatchRecord = null,
    implementation_trace: ?@import("../eval/implementation_trace.zig").Record = null,
    related: ?core_eval.SourceLocation = null,
    origins: @import("../check/staging_origins.zig").Trace = .{},
    pub fn message(self: Diagnostic) []const u8 {
        return self.code.message(self.detail);
    }
};
pub const ArtifactSummary = struct { demands: usize, jobs: usize, functions: usize, helpers: usize, emission_events: usize, metadata_events: usize, operation_symbols: usize, templates: usize, pinned_modules: usize };
pub const Result = struct {
    demand_lowering: ?@import("demand_lowering.zig").Snapshot = null,
    allocation_emission: ?@import("allocation_emission.zig").Snapshot = null,
    timing: @import("backend_timing.zig").Stats = .{},
    /// Deterministic work counters for budgets; unlike timing, always recorded.
    counters: @import("../work_counters.zig").Counters = .{},
    optimization: function_facts.Stats = .{},
    runtime_optimization: @import("optimized_bodies.zig").Stats = .{},
    module_stamps: struct { computed: usize = 0, reused: usize = 0, comparisons: usize = 0, copied: usize = 0, hashed: usize = 0 } = .{},
    refinements: @import("../reuse/refinement_receipt.zig").Stats = .{},
    completed_queries: completed_specialization_query.Stats = .{},
    query_tables: struct {
        selected: @import("../reuse/semantic_query_table.zig").Storage = .{},
        principal: @import("../reuse/semantic_query_table.zig").Storage = .{},
        portable_principal: @import("../reuse/semantic_query_table.zig").Storage = .{},
        canonical: @import("../reuse/semantic_query_table.zig").Storage = .{},
        source_description: @import("../reuse/semantic_query_table.zig").Storage = .{},
        open_residual: @import("../reuse/semantic_query_table.zig").Storage = .{},
        executable_fragment: @import("../reuse/semantic_query_table.zig").Storage = .{},
        executable_optimizer: @import("../reuse/semantic_query_table.zig").Storage = .{},
    } = .{},
    artifacts: ?ArtifactSummary = null,
    capture: ?artifact_capture.Capture = null,
    reuse: artifact_fragment.Stats = .{},
    principal: principal_evidence_reuse.Stats = .{},
    source_validation: @import("../reuse/dependency_certificate.zig").Stats = .{},
    bytes: []u8 = &.{},
    diagnostic: ?Diagnostic = null,
    code_instances: usize = 0,
    callable_wrappers: usize = 0,
    emitted_functions: usize = 0,
    constant_steps: usize = 0,
    constant_receipts: @import("../reuse/constant_receipt.zig").Stats = .{},
    owned_message: []u8 = &.{},
    /// Owned, spelled candidates of a failed dispatch `diagnostic` reports.
    explanation: ?dispatch_explanation.Explanation = null,
    startup_observation: ?startup_emission_facts.Snapshot = null,
    pub fn deinit(self: *Result, allocator: Allocator) void {
        if (self.demand_lowering) |*snapshot| snapshot.deinit(allocator);
        if (self.allocation_emission) |*snapshot| snapshot.deinit(allocator);
        allocator.free(self.bytes);
        allocator.free(self.owned_message);
        if (self.explanation) |explanation| explanation.deinit(allocator);
        if (self.capture) |*capture| capture.deinit();
        if (self.startup_observation) |*observation| observation.deinit(allocator);
        self.* = .{};
    }
};
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
const StaticCodeProjection = specialization.PhysicalProjection;
const specialization = @import("../eval/specialization.zig");
const refinement_receipt = @import("../reuse/refinement_receipt.zig");
const EvidenceRoot = refinement_receipt.Root;
pub const Generator = struct {
    pub const Emission = Emitter;
    inline_named: bool = true,
    /// Closed generalized locals whose uses disagree may keep evaluator
    /// values. A failed compilation that did so retries without them.
    speculative_locals: bool = true,
    speculated: bool = false,
    demand_lowering: @import("demand_lowering.zig").Store = .{},
    ragged_probe_limit: u32 = ragged_builder.probe_limit,
    work_timing: @import("backend_timing.zig").Work = .{},
    allocator: Allocator,
    units: []const core.Module,
    artifacts: ?*code_artifacts.Context = null,
    retained: ?*artifact_fragment.State = null,
    principal_state: ?*principal_evidence_reuse.State = null,
    persisted_principals: ?*@import("../reuse/principal_archive.zig").Reader = null,
    principal_stats: principal_evidence_reuse.Stats = .{},
    query_state: ?*completed_specialization_query.State = null,
    constant_state: ?*@import("../reuse/constant_receipt_reuse.zig").State = null,
    demand_owner: ?*code_artifacts.Context = null,
    refinement_owner: ?*code_artifacts.Context = null,
    refinement_stats: refinement_receipt.Stats = .{},
    work: artifact_fragment.Stats = .{},
    module: wasm.Module,
    planning: @import("backend_plan.zig").State,
    evaluator: core_eval.Session,
    representations: @import("backend_representations.zig").State,
    static_data: @import("backend_static_data.zig").State = .{},
    numeric_rows: @import("numeric_rows.zig").Cache = .{},
    persistent_outputs: bool = false,
    public_owners: ?@import("../runtime/public_owners.zig").Runtime = null,
    task_context: ?@import("../runtime/task_context.zig").Functions = null,
    request_owner: ?u32 = null,
    scoped_effects: bool = false,
    diagnostic: ?Diagnostic = null,
    staging_trace: @import("../check/staging_origins.zig").Trace = .{},
    instance_depth: usize = 0,
    fn completedQueryLookup(context: *anyopaque, session: *core_eval.Session, input: u32, expected: u32) Allocator.Error!?u32 {
        const self: *Generator = @ptrCast(@alignCast(context));
        if (session != &self.evaluator) return null;
        if (self.query_state) |state| return state.lookup(self, input, expected);
        return null;
    }
    fn completedMemberLookup(context: *anyopaque, session: *core_eval.Session, target: core.BindingRef, input: u32, expected: u32) Allocator.Error!?u32 {
        const self: *Generator = @ptrCast(@alignCast(context));
        if (session != &self.evaluator) return null;
        if (self.query_state) |state| return state.lookupMember(self, target, input, expected);
        return null;
    }
    fn constantLookup(context: *anyopaque, session: *core_eval.Session, target: core.BindingRef, inputs: @import("../reuse/constant_receipt.zig").Inputs) Allocator.Error!?@import("../reuse/constant_receipt.zig").Lookup {
        const self: *Generator = @ptrCast(@alignCast(context));
        if (session != &self.evaluator) return null;
        if (self.constant_state) |state| return state.lookup(self, target, inputs);
        return null;
    }
    fn init(allocator: Allocator, units: []const core.Module, journal: ?*artifact_emitter.Recorder) Error!Generator {
        var evaluator = try core_eval.Session.init(allocator, units);
        errdefer evaluator.deinit();
        evaluator.options.trace_runtime_dependencies = true;
        evaluator.options.retain_source_suspensions = true;
        var representations = try @import("backend_representations.zig").State.init(allocator, units);
        errdefer representations.deinit(allocator);
        var module = wasm.Module.init(allocator);
        module.defer_cycles = true;
        module.artifacts = journal;
        errdefer module.deinit();
        var requests = false;
        for (units) |unit_| requests = requests or unit_.request_loops.len != 0;
        const owner = if (requests) try module.addGlobal(.u32, 0, true) else null;
        var scoped_effects = false;
        for (units) |unit_| for (unit_.closures) |closure_| {
            if (unit_.types.node(closure_.parameter.ty).tag == .scoped) scoped_effects = true;
        };
        return .{ .allocator = allocator, .units = units, .module = module, .request_owner = owner, .scoped_effects = scoped_effects, .evaluator = evaluator, .representations = representations, .planning = @import("backend_plan.zig").State.init(allocator) };
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
    fn principalRecord(context: *anyopaque, target: core.BindingRef, options: core_eval.Options, solved: core_eval.SolvedEvidence, inputs: ?*const @import("../reuse/principal_inputs.zig").Key) Allocator.Error!void {
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
        if (self.artifacts) |artifacts| result.captured = artifacts.principal_queries.records.items.len;
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
    /// Re-serializes an admitted aggregate constant in the current owner and
    /// returns its root address.
    pub fn replayConstant(self: *Generator, request: code_artifacts.Request) Error!u32 {
        std.debug.assert(request == .constant);
        const value = try self.constant(request.constant.target, request.constant.ty);
        if (value.scalar != .pointer) return error.InvalidFunctionReference;
        return value.bits;
    }
    pub fn publishRetained(self: *Generator, request: code_artifacts.Request, function_id: u32) Error!void {
        switch (request) {
            .named => |key| try self.planning.instances.put(self.allocator, key, function_id),
            .closure => |key| try self.planning.closures.put(self.allocator, key, function_id),
            else => return error.InvalidFunctionReference,
        }
    }
    pub fn publishRetainedStatic(self: *Generator, function_id: u32) Error!void {
        try self.static_data.closures.append(self.allocator, function_id);
    }
    pub fn publishRetainedResult(self: *Generator, request: code_artifacts.Request, template: ?u32) Error!void {
        if (template) |id| switch (request) {
            .named => |key| try self.planning.template_results.put(self.allocator, key, id),
            .closure => |key| try self.planning.closure_template_results.put(self.allocator, key, id),
            else => return error.InvalidFunctionReference,
        };
    }
    fn deinit(self: *Generator) void {
        self.numeric_rows.deinit(self.allocator);
        self.demand_lowering.deinit(self.allocator);
        self.planning.deinit(self.allocator);
        self.module.deinit();
        self.representations.deinit(self.allocator);
        self.evaluator.deinit();
        self.static_data.deinit(self.allocator);
    }
    pub fn demandSite(self: *Generator, unit_id: u32, id: core.Id, lowering: @import("demand_lowering.zig").Kind, reason: @import("demand_lowering.zig").Reason) Allocator.Error!void {
        if (!self.demand_lowering.enabled) return;
        const path = if (self.evaluator.diagnostic_context.identity) |identity| identity.owner(unit_id) orelse "" else "";
        try self.demand_lowering.add(self.allocator, path, unit_id, self.unit(unit_id).span(id), lowering, reason);
    }
    pub fn unusedAggregate(self: *Generator, unit_id: u32, binding: core.BindingId) Error!bool {
        if (self.planning.discard_proofs.getPtr(unit_id)) |proof| return proof.admits(binding);
        var proof = try discarded_bindings.Proof.init(self.allocator, self.unit(unit_id), unit_id);
        errdefer proof.deinit(self.allocator);
        try self.planning.discard_proofs.put(self.allocator, unit_id, proof);
        return proof.admits(binding);
    }
    /// Whether a declaration of unit `unit_id` quantifies or closes type
    /// variable or, for `row`, row variable `variable`.
    pub fn quantifiedVariable(self: *Generator, unit_id: u32, variable: u32, row: bool) Error!bool {
        if (self.planning.quantified.getPtr(unit_id)) |set| return set.has(variable, row);
        var set = try @import("unit_index.zig").Quantified.init(self.allocator, self.unit(unit_id));
        errdefer set.deinit(self.allocator);
        try self.planning.quantified.put(self.allocator, unit_id, set);
        return set.has(variable, row);
    }
    /// The def-use index of unit `unit_id` with at least the groups `need`
    /// names, each built on first use. The pointer stays valid for the whole
    /// compile attempt.
    pub fn unitUses(self: *Generator, unit_id: u32, need: @import("unit_index.zig").Uses.Need) Error!*const @import("unit_index.zig").Uses {
        const index = self.planning.uses.get(unit_id) orelse created: {
            try self.planning.uses.ensureUnusedCapacity(self.allocator, 1);
            const fresh = try self.allocator.create(@import("unit_index.zig").Uses);
            errdefer self.allocator.destroy(fresh);
            fresh.* = try @import("unit_index.zig").Uses.initBase(self.allocator, self.unit(unit_id), unit_id);
            self.planning.uses.putAssumeCapacityNoClobber(unit_id, fresh);
            break :created fresh;
        };
        try index.ensure(self.allocator, self.unit(unit_id), unit_id, need);
        return index;
    }
    pub fn ownsArrayUpdate(self: *Generator, unit_id: u32, id: core.Id) Error!bool {
        if (self.planning.array_proofs.get(unit_id)) |proof| return proof.admits(id);
        var proof = try owned_arrays.Proof.init(self.allocator, self.units, unit_id);
        errdefer proof.deinit(self.allocator);
        try self.planning.array_proofs.put(self.allocator, unit_id, proof);
        return proof.admits(id);
    }
    pub fn unit(self: *const Generator, id: u32) *const core.Module {
        return &self.units[id - 1];
    }
    pub fn nestedRow(self: *Generator, id: layout.Id) Allocator.Error!?@import("numeric_rows.zig").Plan {
        if (@import("packed_layout.zig").rowWords(&self.representations.store, id) != 0) return null;
        const tag = self.representations.store.node(id).tag;
        if (tag != .record and tag != .product and tag != .nominal) return null;
        return self.numeric_rows.get(self.allocator, self, id);
    }
    pub fn rowWords(self: *Generator, id: layout.Id) Allocator.Error!u32 {
        const flat = @import("packed_layout.zig").rowWords(&self.representations.store, id);
        if (flat != 0) return flat;
        const plan = try self.nestedRow(id) orelse return 0;
        return plan.leaf_count;
    }
    pub fn collectionRowWords(self: *Generator, id: layout.Id) Allocator.Error!u32 {
        const node = self.representations.store.node(id);
        return if (node.tag == .array or node.tag == .list) self.rowWords(node.a) else 0;
    }
    pub fn numericCheck(self: *Generator, unit_id: u32, id: core.Id) Error!bool {
        if (id == 0) return false;
        if (self.planning.numeric_plans.getPtr(unit_id)) |plan| return plan.admits(id);
        const units = try self.allocator.alloc(*const core.Module, self.units.len);
        defer self.allocator.free(units);
        for (self.units, units) |*source, *target| target.* = source;
        var plan = try @import("../check/numeric_proof_core.zig").analyze(self.allocator, self.unit(unit_id), units, .{});
        errdefer plan.deinit(self.allocator);
        const admitted = plan.admits(id);
        try self.planning.numeric_plans.put(self.allocator, unit_id, plan);
        return admitted;
    }
    pub fn functionRoot(self: *Generator, unit_id: u32, ty: types.Id, span: core.Span) Error!types.Id {
        return self.unit(unit_id).types.withoutForall(ty) catch self.decline(unit_id, span, .complexity);
    }
    pub fn decline(self: *Generator, unit_id: u32, span: core.Span, code: Code) Error {
        if (self.diagnostic == null) self.diagnostic = .{ .unit = unit_id, .span = span, .code = code, .origins = self.staging_trace };
        return error.Declined;
    }
    pub fn fail(self: *Generator, unit_id: u32, node: core.Id, code: Code) Error {
        return self.decline(unit_id, self.unit(unit_id).span(node), code);
    }
    pub fn failSpecialization(self: *Generator, unit_id: u32, node: core.Id, code: Code) Error {
        const fresh = self.diagnostic == null;
        const failure = self.fail(unit_id, node, code);
        if (fresh and core_eval.callerDependentUse(self.unit(unit_id), node)) if (self.evaluator.specialization_origin) |origin| {
            const diagnostic_ = &self.diagnostic.?;
            if (unit_id != origin.unit or !std.meta.eql(diagnostic_.span, origin.span)) {
                diagnostic_.related = .{ .unit = unit_id, .span = diagnostic_.span };
                diagnostic_.unit = origin.unit;
                diagnostic_.span = origin.span;
            }
        };
        return failure;
    }
    /// The ownership role of a value with checked layout `id`. Every
    /// aggregate, collection, closure, demand and provider is a heap
    /// reference or zero; scalars never are.
    pub fn layoutRole(self: *const Generator, id: layout.Id) ir.Role {
        const n = self.representations.store.node(id);
        if (n.tag == .nominal and self.representations.store.scalar(id) != null) return .scalar;
        return switch (n.tag) {
            .scoped, .unit, .boolean, .u32, .f32, .never, .type_constructor, .resolver, .erased_proof => .scalar,
            .associated, .owning, .universal, .existential, .opened, .product, .record, .array, .list, .cursor, .function, .demand, .provider, .state_provider => .reference,
            // Compiler-defined nominals keep their own representations.
            .nominal => nominal: {
                if (n.a != std.math.maxInt(u32) or n.b == 5 or n.b == 6 or n.b == layout.capability_layout_decl) break :nominal .reference;
                break :nominal .value;
            },
            .invalid, .erased => .value,
        };
    }
    pub fn bodyResultRole(self: *const Generator, selected: layout.Id, owner: u32, root: core.Id) ir.Role {
        const role = self.layoutRole(selected);
        if (selected == layout.erased and @import("bottom_result.zig").proves(self.units, owner, root)) return .scalar;
        return role;
    }
    pub fn setParameterRoles(self: *Generator, function_id: u32, roles: u64, provider: ?u16) Error!void {
        try self.module.setParameterRoles(function_id, roles);
        self.evaluator.counters.parameter_role_functions += 1;
        // The existing packed role interface describes only its first 32
        // words. A larger source ABI keeps the unknown, nonauthorizing fact.
        if (provider) |index| if (index >= 32) return;
        try self.module.setProviderParameter(function_id, provider orelse ir.no_provider);
    }
    /// Roles of a closure body's (environment, argument, provider) parameters.
    pub fn closureRoles(self: *const Generator, argument: layout.Id) u64 {
        if (self.representations.store.node(argument).tag == .erased_proof) return ir.packParameterRoles(&.{ .reference, .reference });
        return ir.packParameterRoles(&.{ .reference, self.layoutRole(argument), .reference });
    }
    fn dictionaryClosureRoles(self: *const Generator, argument: layout.Id) u64 {
        if (self.representations.store.node(argument).tag == .erased_proof) return ir.packParameterRoles(&.{ .reference, .reference, .reference });
        return ir.packParameterRoles(&.{ .reference, self.layoutRole(argument), .reference, .reference });
    }
    pub fn dictionaryClosureSignature(self: *Generator, argument: layout.Id, result: layout.Id) Error!u32 {
        if (self.representations.store.node(argument).tag == .erased_proof) return self.module.internType(&.{ .i32, .i32, .i32 }, self.resultMachine(result));
        return self.module.internType(&.{ .i32, self.representations.store.machine(argument), .i32, .i32 }, self.resultMachine(result));
    }
    pub fn closureSignature(self: *Generator, argument: layout.Id, result: layout.Id) Error!u32 {
        if (self.representations.store.node(argument).tag == .erased_proof) return self.module.internType(&.{ .i32, .i32 }, self.resultMachine(result));
        return self.module.internType(&.{ .i32, self.representations.store.machine(argument), .i32 }, self.resultMachine(result));
    }
    pub fn taskRuntime(self: *Generator) Error!@import("../runtime/task_context.zig").Functions {
        if (self.task_context) |present| return present;
        if (self.artifacts) |artifacts| artifacts.requireFreshCode();
        try @import("../runtime/task_abi.zig").ensure(&self.module);
        _ = try self.module.ensureHostReferences();
        const functions = try @import("../runtime/task_context.zig").emit(&self.module, self.request_owner);
        inline for (@typeInfo(@TypeOf(functions)).@"struct".field_names) |name| try self.module.exportTaskAdapter(@field(functions, name), "blot:task_context/" ++ name, true);
        const arena = self.module.arena.?;
        inline for (.{ "retain", "release" }) |name| {
            const wrapper = try self.module.addTypedFunction(&.{.i32}, .none, .scalar);
            try self.module.emitSlice(wrapper, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = @field(arena, name) } });
            try self.module.exportTaskAdapter(wrapper, "blot:task_" ++ name, true);
        }
        self.task_context = functions;
        return functions;
    }
    pub fn taskMover(self: *Generator, ty: layout.Id) Error!u32 {
        if (self.planning.task_movers.get(ty)) |present| return present;
        const function_id = try self.module.addTypedFunction(&.{.i32}, .none, .scalar);
        try self.setParameterRoles(function_id, ir.packParameterRoles(&.{.reference}), null);
        try self.planning.task_movers.put(self.allocator, ty, function_id);
        var emitter: Emitter = .{ .generator = self, .unit_id = 1, .function_id = function_id, .mappings = &.{} };
        defer emitter.deinit();
        try emitter.taskMoveBody(ty, 0, 0);
        return function_id;
    }
    pub fn resourceAdapter(self: *Generator, payload: layout.Id) Error!u32 {
        const role = self.layoutRole(payload);
        const machine = self.representations.store.machine(payload);
        var selected: u32 = 0;
        if (machine == .f32) selected = 1;
        if (role == .reference) selected = 2;
        if (role != .scalar and role != .reference) return error.Declined;
        const present = self.module.resourceCount();
        if (present > selected) return selected;
        const arena = try self.module.ensureArena();
        var count: usize = 2;
        if (selected == 2) count = 3;
        for (present..count) |index| {
            var payload_role: ir.Role = .scalar;
            if (index == 2) payload_role = .reference;
            var argument_machine: wasm.ValueType = .i32;
            if (index == 1) argument_machine = .f32;
            const cleanup = try self.module.addTypedFunction(&.{ .i32, .i32, .i32 }, .none, .scalar);
            try self.setParameterRoles(cleanup, ir.packParameterRoles(&.{ payload_role, .reference, .reference }), 2);
            try self.module.emitSlice(cleanup, &.{
                .{ .op = .local_get, .operand = 1 }, .{ .op = .i32_load, .operand = heap.offset(heap.Closure, "environment") },
                .{ .op = .local_get },
            });
            if (index == 1) try self.module.emit(cleanup, .{ .op = .f32_reinterpret_i32 });
            var adapter_emitter: Emitter = .{ .generator = self, .unit_id = 1, .function_id = cleanup, .mappings = &.{} };
            defer adapter_emitter.deinit();
            try adapter_emitter.boxOwnerStorage(argument_machine, payload_role);
            try self.module.emitSlice(cleanup, &.{
                .{ .op = .local_get, .operand = 2 },                                                            .{ .op = .local_get, .operand = 1 },
                .{ .op = .i32_load, .operand = heap.offset(heap.Closure, "function") },                         ir.callResult(.scalar),
                .{ .op = .call_indirect, .operand = try self.module.internType(&.{ .i32, .i32, .i32 }, .i32) }, .{ .op = .drop },
            });
            const drop = try self.module.addTypedFunction(&.{ .i32, .i32, .i32 }, .none, .scalar);
            try self.setParameterRoles(drop, ir.packParameterRoles(&.{ payload_role, .reference, .reference }), 2);
            var first: usize = 1;
            if (index == 2) first = 0;
            for (first..3) |local| {
                try self.module.emitSlice(drop, &.{ .{ .op = .local_get, .operand = @intCast(local) }, .{ .op = .call, .operand = arena.release } });
            }
            const cleanup_name = try self.allocator.print("blot:resource_cleanup/{d}", .{index});
            defer self.allocator.free(cleanup_name);
            const drop_name = try self.allocator.print("blot:resource_drop/{d}", .{index});
            defer self.allocator.free(drop_name);
            try self.module.exportResourceAdapter(cleanup, cleanup_name);
            try self.module.exportResourceAdapter(drop, drop_name);
        }
        return selected;
    }
    fn resultMachine(self: *const Generator, result: layout.Id) wasm.ValueType {
        if (self.representations.store.node(result).tag == .erased_proof) return .none;
        return self.representations.store.machine(result);
    }
    pub fn evaluationFailure(self: *Generator) Error {
        if (self.evaluator.diagnostic) |item| {
            // The evaluator's unsupported and cycle failures have no public code of their own.
            const code: Code = switch (item.code) {
                .unsupported, .cycle => .constant_expression,
                else => item.code,
            };
            // Reference panic diagnostics name the constant phase, with no
            // declaration offset. Preserve its detail and producer owner.
            const public_span: core.Span = if (code == .const_panic and !item.tag_origin and item.origins.len == 0 and self.staging_trace.len == 0) .{ .start = 0, .end = 0 } else item.span;
            const fresh = self.diagnostic == null;
            const result = self.decline(item.unit, public_span, code);
            if (self.diagnostic) |*diagnostic_| diagnostic_.detail = item.detail;
            if (fresh) {
                self.diagnostic.?.dispatch = item.dispatch;
                self.diagnostic.?.implementation_trace = item.implementation_trace;
                self.diagnostic.?.related = item.related;
                if (item.origins.len != 0) self.diagnostic.?.origins = item.origins;
            }
            return result;
        }
        return self.decline(1, .{ .start = 0, .end = 0 }, .constant_expression);
    }
    /// Spells a failed dispatch's candidates while their evidence is live.
    /// Types without a source name keep a null operand.
    fn explainDispatch(self: *Generator, record: core_eval.DispatchRecord) Allocator.Error!dispatch_explanation.Explanation {
        var builder: dispatch_explanation.Builder = .{ .allocator = self.allocator };
        defer builder.deinit();
        for (record.items()) |candidate| {
            var display: EntryDisplay = .{ .generator = self };
            defer display.text.deinit(self.allocator);
            const spelled = candidate.operand != 0 and try display.ty(candidate.operand, 16);
            builder.add(candidate.side, if (spelled) try builder.own(&display.text) else null, candidate.outcome);
        }
        const named = if (record.member == 0) null else if (self.evaluator.diagnostic_context.identity) |identity| identity.symbol(record.member) else null;
        var result = try builder.finish(dispatch_explanation.operatorSymbol(record.op), named orelse dispatch_explanation.operatorMember(record.op));
        errdefer result.deinit(self.allocator);
        if (record.context_len != 0) {
            result.contexts = try self.allocator.alloc(dispatch_explanation.Context, record.context_len);
            for (result.contexts) |*context| context.* = .{ .kind = .left_operand, .path = null, .span = .{ .start = 0, .end = 0 } };
            for (record.contexts[0..record.context_len], result.contexts) |source, *context| {
                context.* = .{ .kind = switch (source.kind) {
                    .left_operand => .left_operand,
                    .right_operand => .right_operand,
                }, .path = null, .span = source.span };
                if (self.evaluator.diagnostic_context.identity) |identity| if (identity.owner(source.unit)) |path| {
                    if (path.len <= dispatch_explanation.max_text) {
                        context.path = try self.allocator.dupe(u8, path);
                    } else result.truncated = true;
                };
            }
            try result.fit(self.allocator);
        }
        return result;
    }
    fn explainImplementation(self: *Generator, trace: @import("../eval/implementation_trace.zig").Record) Allocator.Error!dispatch_explanation.Explanation {
        var builder: dispatch_explanation.Builder = .{ .allocator = self.allocator, .truncated = trace.truncated };
        defer builder.deinit();
        const names = self.evaluator.diagnostic_context.identity;
        for (trace.candidates[0..trace.len]) |candidate| {
            var declaration: ?core.Implementation = null;
            for (self.units) |module| {
                for (module.implementations) |known| if (std.meta.eql(known.identity, candidate.identity)) {
                    declaration = known;
                    break;
                };
                if (declaration != null) break;
            }
            const known = declaration orelse continue;
            var name: []const u8 = "implementation";
            var path: ?[]const u8 = null;
            if (names) |identity| {
                name = identity.symbol(known.name) orelse name;
                path = identity.owner(known.identity.unit);
            }
            // Core owns archive provenance, but has no source availability
            // certificate. Related source positions therefore remain absent.
            builder.addOrigin(null, candidate.outcome, try builder.makeOrigin(name, path, null));
        }
        for (trace.steps[0..trace.step_len]) |step| {
            var display: EntryDisplay = .{ .generator = self };
            defer display.text.deinit(self.allocator);
            var spelling: ?[]u8 = null;
            if (step.ty != 0 and try display.ty(step.ty, 16)) spelling = try builder.own(&display.text);
            var member: ?[]const u8 = null;
            if (names) |identity| if (step.member != 0) {
                member = identity.symbol(step.member);
            };
            try builder.addStep(member, spelling, step.outcome);
        }
        var member: ?[]const u8 = null;
        if (names) |identity| member = identity.symbol(trace.contract.decl & ~types.opaque_name_bit);
        return builder.finish(null, member);
    }
    pub fn constant(self: *Generator, target: core.BindingRef, ty: layout.Id) Error!Value {
        const timing = self.work_timing.enter(.constants);
        defer timing.deinit();
        var scope: ?code_artifacts.Scope = if (self.artifacts) |context| try context.enter(.{ .constant = .{ .target = target, .ty = ty } }) else null;
        defer if (scope) |*actor| actor.deinit();
        const id = self.evaluator.richValue(target) catch |err| switch (err) {
            error.RequestUnwind => return self.evaluationFailure(),
            error.Declined => return self.evaluationFailure(),
            error.OutOfMemory => return error.OutOfMemory,
        };
        if (self.representations.store.node(ty).tag != .owning) if (self.evaluator.valueScalar(id)) |value| {
            if (scope) |*actor| try actor.completeValue(id, ty);
            return value;
        };
        const bits = try self.static_data.serialize(self, id, ty, 0);
        if (scope) |*actor| try actor.completeValue(id, ty);
        return .{ .scalar = self.representations.store.scalar(ty) orelse .pointer, .bits = bits };
    }
    pub fn discardableClosure(self: *Generator, owner: u32, catalog: u32) bool {
        const source = self.unit(owner);
        const metadata = source.closures[catalog];
        if (metadata.qualifier != 0 and source.binding(metadata.qualifier).scheme.obligations.len != 0) return false;
        const body = source.node(metadata.body);
        if (body.tag == .constant or body.tag == .panic) return true;
        if (body.tag != .reference) return false;
        const reference = source.reference(metadata.body);
        return (reference.unit == 0 or reference.unit == owner) and reference.binding == metadata.parameter.binding;
    }
    pub fn discardableValue(self: *Generator, id: core_eval.ValueId, depth: usize) bool {
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
    fn callableLayout(self: *Generator, function_id: u32, ty: layout.Id) Error!void {
        const arrow = self.representations.store.node(ty);
        if (arrow.tag != .function or ty >= 1 << 26) return;
        const body = self.module.functions.items[function_id];
        if (body.entry or body.signature != try self.closureSignature(arrow.a, arrow.b) or body.parameter_roles != self.closureRoles(arrow.a) or body.result_role != self.layoutRole(arrow.b)) return;
        try self.module.setCallableLayout(function_id, ty);
    }
    pub fn emitValue(self: *Generator, function_id: u32, value: Value) Error!void {
        if (value.scalar == .pointer or value.scalar == .array_u32 or value.scalar == .array_f32) {
            try self.module.emit(function_id, ir.immortalReference());
            try self.module.emitReference(function_id, .{ .op = .i32_const, .operand = value.bits }, .static_address);
        } else try self.module.emit(function_id, .{ .op = if (value.scalar == .f32) .f32_const else .i32_const, .operand = value.bits });
    }
    /// Fill unselected slots along a retained demand/function interface.
    /// All selected types and rows remain the consumer's inputs to ordinary
    /// specialization. The proof comes from full body/capture inference.
    pub fn completeRetainedRows(self: *Generator, requested: layout.Id, actual: layout.Id, depth: usize) Error!layout.Id {
        if (depth >= 128) return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
        if (requested == layout.erased) return actual;
        const wanted = self.representations.store.node(requested);
        const proven = self.representations.store.node(actual);
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
    pub fn retainedLayoutConcrete(self: *const Generator, ty: layout.Id, callable_rows: bool, depth: usize, budget: *usize) bool {
        if (depth >= 128 or budget.* == 0 or ty == 0 or ty >= self.representations.store.nodes.items.len) return false;
        budget.* -= 1;
        const node = self.representations.store.node(ty);
        switch (node.tag) {
            .associated, .universal, .existential, .opened, .invalid, .erased => return false,
            .unit, .boolean, .u32, .f32, .never, .type_constructor, .erased_proof => return true,
            .function => return (callable_rows or node.c != layout.unknown_row) and self.retainedLayoutConcrete(node.a, callable_rows, depth + 1, budget) and self.retainedLayoutConcrete(node.b, callable_rows, depth + 1, budget),
            .demand => return (callable_rows or node.c != layout.unknown_row) and self.retainedLayoutConcrete(node.a, callable_rows, depth + 1, budget),
            .owning, .array, .list, .cursor, .resolver => return self.retainedLayoutConcrete(node.a, false, depth + 1, budget),
            .scoped => return node.b != 0 and node.c != 0 and self.retainedLayoutConcrete(node.a, false, depth + 1, budget),
            .provider => return node.c != layout.unknown_row and self.retainedLayoutConcrete(node.a, false, depth + 1, budget),
            .state_provider => return self.retainedLayoutConcrete(node.a, false, depth + 1, budget) and self.retainedLayoutConcrete(node.b, false, depth + 1, budget) and self.retainedLayoutConcrete(node.c, false, depth + 1, budget),
            .product, .nominal => {
                for (self.representations.store.children(ty)) |child| if (!self.retainedLayoutConcrete(child, false, depth + 1, budget)) return false;
                return true;
            },
            .record => {
                const children = self.representations.store.children(ty);
                for (0..children.len / 2) |i| if (!self.retainedLayoutConcrete(children[i * 2 + 1], false, depth + 1, budget)) return false;
                return true;
            },
        }
    }
    pub fn nominalPayload(self: *Generator, family: u64, tag: u32, ty: layout.Id) Error!layout.Id {
        const owner: u32 = @intCast(family >> 32);
        const declaration: u32 = @truncate(family);
        const source = self.unit(owner);
        for (source.constructors) |constructor| {
            const nominal = source.nominal(constructor.nominal);
            if (nominal.identity.unit != owner or nominal.identity.decl != declaration or constructor.tag != tag) continue;
            const parameters = source.types.list(nominal.parameters);
            const arguments = self.representations.store.children(ty);
            if (parameters.len != arguments.len) return self.decline(owner, .{ .start = 0, .end = 0 }, .unresolved_type);
            var mappings: std.ArrayList(Mapping) = .empty;
            defer mappings.deinit(self.allocator);
            for (parameters, arguments) |parameter, argument| try self.mapType(owner, &mappings, parameter, argument, .{ .start = 0, .end = 0 });
            return self.codeLayout(owner, constructor.payload, mappings.items, .{ .start = 0, .end = 0 });
        }
        return self.decline(owner, .{ .start = 0, .end = 0 }, .unresolved_type);
    }
    /// The exact immutable acyclic proof of `ty`; see `acyclic_layout.zig`.
    pub fn acyclicLayout(self: *Generator, ty: layout.Id) Error!bool {
        return @import("acyclic_layout.zig").proven(&self.representations.store, self.units, ty);
    }
    pub fn captureLayout(self: *Generator, owner: u32, binding: core.BindingId, value: core_eval.ValueId, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping)) Error!layout.Id {
        const source = self.unit(owner);
        const declaration = source.binding(binding);
        return self.captureTypeLayout(owner, declaration.ty, declaration.span, value, mappings, rows);
    }
    pub fn captureTypeLayout(self: *Generator, owner: u32, ty: types.Id, span: core.Span, value: core_eval.ValueId, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping)) Error!layout.Id {
        const source = self.unit(owner);
        if (self.representations.store.fromTypeWithRows(source, ty, mappings.items, rows.items, false)) |concrete| return concrete else |err| if (err == error.OutOfMemory) return error.OutOfMemory;
        const actual = self.evaluator.valueEvidence(value);
        if (actual != 0) {
            const concrete = self.representations.fromEvidence(self.evaluator.evidenceStore(), actual) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(owner, span, .unresolved_type);
            try self.mapTypeDepth(owner, mappings, rows, ty, concrete, span, 0);
            return self.codeLayoutWithRows(owner, ty, mappings.items, rows.items, span);
        }
        return self.codeLayoutWithRows(owner, ty, mappings.items, rows.items, span);
    }
    /// Private helpers consume exact live captures. Their enclosing artifact
    /// must rebuild; neither a closed semantic receipt nor a portable code key
    /// can represent the partial capture graph.
    pub fn capturedClosureFunction(self: *Generator, header: core_eval.ClosureValue, ty: layout.Id, captured: []const core_eval.ValueId, mappings: []const Mapping, rows: []const RowMapping) Error!u32 {
        const source = self.unit(header.unit);
        const metadata = source.closures[header.identity];
        const bindings = source.extra[metadata.captures.start..][0..metadata.captures.len];
        if (self.instance_depth >= 256) return self.fail(header.unit, metadata.body, .complexity);
        self.instance_depth += 1;
        defer self.instance_depth -= 1;
        if (self.artifacts) |artifacts| artifacts.requireFreshCode();
        const arrow = self.representations.store.node(ty);
        const function_id = try self.module.addTypedFunction(&.{ .i32, self.representations.store.machine(arrow.a), .i32 }, self.representations.store.machine(arrow.b), self.bodyResultRole(arrow.b, header.unit, metadata.body));
        try self.setParameterRoles(function_id, self.closureRoles(arrow.a), 2);
        try self.static_data.closures.append(self.allocator, function_id);
        self.work.fresh_closures += 1;
        try self.planning.startup_facts.request(self.allocator, function_id, .anonymous, header.unit, header.identity, false);
        const caller = self.planning.startup_facts.active;
        self.planning.startup_facts.active = function_id;
        defer self.planning.startup_facts.active = caller;
        var emitter: Emitter = .{ .generator = self, .unit_id = header.unit, .function_id = function_id, .provider_local = 2, .mappings = mappings, .row_mappings = rows };
        defer emitter.deinit();
        if (metadata.parameter.binding != 0) try emitter.locals.put(self.allocator, metadata.parameter.binding, 1);
        for (bindings, captured) |binding, actual| try emitter.static_values.put(self.allocator, binding, actual);
        try emitter.bodyExpression(metadata.body, 0, false);
        if (source.types.node(source.typeOf(metadata.body)).tag == .never) try emitter.emit(.unreachable_, 0);
        self.planning.startup_facts.complete(function_id);
        return function_id;
    }
    pub fn normalize(self: *Generator, owner: u32, reference: core.BindingRef) Error!core.BindingRef {
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
                const tag = self.unit(target.unit).types.node(binding.ty).tag;
                if ((tag == .function or tag == .forall) and body.parameters.len == 0 and self.unit(target.unit).node(body.root).tag == .reference) {
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
        return self.representations.store.scalar(try self.codeLayout(unit_id, ty, mappings, span)) orelse .pointer;
    }
    fn typeLayout(self: *Generator, unit_id: u32, ty: types.Id, mappings: []const Mapping, span: core.Span) Error!layout.Id {
        return self.representations.store.fromType(self.unit(unit_id), ty, mappings) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => self.decline(unit_id, span, .unresolved_type),
        };
    }
    pub fn codeLayout(self: *Generator, unit_id: u32, ty: types.Id, mappings: []const Mapping, span: core.Span) Error!layout.Id {
        return self.representations.store.fromTypePartial(self.unit(unit_id), ty, mappings) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => self.decline(unit_id, span, .unresolved_type),
        };
    }
    pub fn internLayout(self: *Generator, tag: layout.Tag, a: u32, b: u32, values: []const u32) Error!layout.Id {
        return (if (tag == .record) self.representations.store.internRecord(values) else self.representations.store.intern(tag, a, b, values)) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => self.decline(1, .{ .start = 0, .end = 0 }, .complexity),
        };
    }
    pub fn internLayoutWithEffects(self: *Generator, tag: layout.Tag, a: u32, b: u32, row: u32, values: []const u32) Error!layout.Id {
        return self.representations.store.internWithEffects(tag, a, b, row, values) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(1, .{ .start = 0, .end = 0 }, .complexity);
    }
    pub fn codeLayoutWithRows(self: *Generator, unit_id: u32, ty: types.Id, mappings: []const Mapping, rows: []const RowMapping, span: core.Span) Error!layout.Id {
        const timing = self.work_timing.enter(.layouts);
        defer timing.deinit();
        return self.representations.store.fromTypeWithRows(self.unit(unit_id), ty, mappings, rows, true) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
    }
    pub fn associatedTarget(self: *Generator, origin: u32, identity: types.NominalIdentity, member: u32, op: types.Operator) Error!?core.BindingRef {
        return self.evaluator.associatedTarget(origin, identity, member, op) catch |err| switch (err) {
            error.RequestUnwind => return self.evaluationFailure(),
            error.Declined => self.evaluationFailure(),
            error.OutOfMemory => error.OutOfMemory,
        };
    }
    pub fn scalarWithRows(self: *Generator, unit_id: u32, ty: types.Id, mappings: []const Mapping, rows: []const RowMapping, span: core.Span) Error!Scalar {
        return self.representations.store.scalar(try self.codeLayoutWithRows(unit_id, ty, mappings, rows, span)) orelse .pointer;
    }
    fn entrySignature(self: *Generator, target: core.BindingRef, ty: types.Id, span: core.Span) Error!Key {
        if (self.representations.store.fromType(self.unit(target.unit), ty, &.{})) |_| {
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
        const concrete = self.representations.fromEvidence(self.evaluator.evidenceStore(), self.evaluator.valueEvidence(inferred)) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(target.unit, span, .unresolved_type);
        var mappings: std.ArrayList(Mapping) = .empty;
        defer mappings.deinit(self.allocator);
        var rows: std.ArrayList(RowMapping) = .empty;
        defer rows.deinit(self.allocator);
        // An alias may retain a closure from another owner. Map its complete
        // semantic proof back to the exported source interface before ABI checks.
        try self.mapTypeDepth(target.unit, &mappings, &rows, ty, concrete, span, 0);
        _ = self.representations.store.fromTypeWithRows(self.unit(target.unit), ty, mappings.items, rows.items, false) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(target.unit, span, .unresolved_type);
        return self.signature(target, ty, target.unit, mappings.items, rows.items, span, false);
    }
    pub fn signature(self: *Generator, target: core.BindingRef, ty: types.Id, source: u32, mappings: []const Mapping, rows: []const RowMapping, span: core.Span, complete: bool) Error!Key {
        var key: Key = .{ .target = try self.normalize(source, target) };
        var current = try self.functionRoot(source, ty, span);
        var instances: [max_parameters]types.NominalIdentity = undefined;
        var has_instances = false;
        const producer = self.unit(key.target.unit).body(key.target.binding);
        const limit: usize = if (producer) |body| if (body.parameters.len == 0) max_parameters else body.parameters.len else max_parameters;
        while (self.unit(source).types.node(current).tag == .function and key.count < limit) {
            if (key.count == max_parameters) return self.decline(source, span, .complexity);
            const n = self.unit(source).types.node(current);
            const input = self.unit(source).types.node(n.a);
            if (input.tag == .scoped) {
                if (!has_instances) {
                    @memset(instances[0..key.count], .{ .unit = 0, .decl = 0 });
                    has_instances = true;
                }
                instances[key.count] = types.selectionAtom(self.unit(source).types, layout.mappedInstance(.{ .unit = input.b, .decl = input.c }, mappings));
            } else if (has_instances) {
                instances[key.count] = .{ .unit = 0, .decl = 0 };
            }
            key.parameters[key.count] = if (complete) try self.typeLayout(source, n.a, mappings, span) else try self.codeLayoutWithRows(source, n.a, mappings, rows, span);
            key.effects[key.count] = self.representations.store.rowFromType(self.unit(source), n.c, mappings, rows, !complete) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(source, span, .unresolved_type);
            key.count += 1;
            current = n.b;
        }
        if (has_instances) key.instance_arguments = self.representations.instance_arguments.intern(self.allocator, instances[0..key.count]) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(source, span, .complexity);
        key.result = if (complete) try self.typeLayout(source, current, mappings, span) else try self.codeLayoutWithRows(source, current, mappings, rows, span);
        return key;
    }
    pub fn seedNamedInstance(self: *Generator, key: Key, mappings: *std.ArrayList(Mapping)) Error!void {
        if (key.instance_arguments == 0) return;
        const source = self.unit(key.target.unit);
        var root = try self.functionRoot(key.target.unit, source.binding(key.target.binding).ty, source.binding(key.target.binding).span);
        for (self.representations.instance_arguments.get(key.instance_arguments)) |instance| {
            const arrow = source.types.node(root);
            if (arrow.tag != .function) return self.decline(key.target.unit, source.binding(key.target.binding).span, .unresolved_type);
            root = arrow.b;
            const input = source.types.node(arrow.a);
            if (input.tag != .scoped or input.b != 0 or instance.unit == 0) continue;
            var found = false;
            for (mappings.items) |entry| if (entry.variable == input.c) {
                if (!std.meta.eql(entry.instance, instance)) return self.decline(key.target.unit, source.binding(key.target.binding).span, .unresolved_type);
                found = true;
                break;
            };
            if (found) continue;
            if (mappings.capacity == 0) try mappings.ensureTotalCapacityPrecise(self.allocator, 4);
            try mappings.append(self.allocator, .{ .variable = input.c, .layout = layout.erased, .instance = instance });
        }
    }

    pub fn specializer(self: *Generator) Allocator.Error!specialization.Service {
        return .{ .timing = &self.work_timing, .allocator = self.allocator, .units = self.units, .evaluator = &self.evaluator, .layouts = &self.representations.store, .bridge = try self.representations.representationBridge(self.evaluator.evidenceStore()), .refinement_stats = &self.refinement_stats, .refinement_regions = &self.work.refinement_regions, .cache = .{ .context = self, .lookup = lookupRefinement, .record = recordRefinement } };
    }
    fn lookupRefinement(context: *anyopaque, root: EvidenceRoot, shape: @import("../reuse/code_expectation.zig").View, expected: u32, seeds: []const type_evidence.Mapping, rows: []const type_evidence.RowMapping) Allocator.Error!?core_eval.SolvedEvidence {
        const self: *Generator = @ptrCast(@alignCast(context));
        if (try refinement_receipt.lookupLocal(self, root, expected, seeds, rows)) |result| return result;
        return refinement_receipt.lookup(self, root, shape, expected, seeds, rows);
    }
    fn recordRefinement(context: *anyopaque, record: specialization.Record) Allocator.Error!void {
        const self: *Generator = @ptrCast(@alignCast(context));
        return refinement_receipt.record(self, record.root, record.expected, record.seeds, record.rows, record.result, record.tape, record.observed, record.before_values, record.before_children, record.before_steps);
    }
    pub fn specializationFailure(self: *Generator, service: specialization.Service, err: specialization.Error) Error {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        const failure = service.failure.?;
        return switch (failure.code) {
            .evaluation => self.evaluationFailure(),
            .complexity => self.decline(failure.unit, failure.span, .complexity),
            .unresolved_type => self.decline(failure.unit, failure.span, .unresolved_type),
        };
    }
    pub fn mapType(self: *Generator, unit_id: u32, mappings: *std.ArrayList(Mapping), ty: types.Id, concrete: layout.Id, span: core.Span) Error!void {
        var service = try self.specializer();
        service.mapType(unit_id, mappings, ty, concrete, span) catch |err| return self.specializationFailure(service, err);
    }
    pub fn mapTypeDepth(self: *Generator, unit_id: u32, mappings: *std.ArrayList(Mapping), rows: ?*std.ArrayList(RowMapping), ty: types.Id, concrete: layout.Id, span: core.Span, depth: usize) Error!void {
        var service = try self.specializer();
        service.mapTypeDepth(unit_id, mappings, rows, ty, concrete, span, depth) catch |err| return self.specializationFailure(service, err);
    }
    pub fn mapFunctionResult(self: *Generator, unit_id: u32, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), ty: types.Id, concrete: layout.Id, span: core.Span) Error!void {
        var service = try self.specializer();
        service.mapFunctionResult(unit_id, mappings, rows, ty, concrete, span, 0) catch |err| return self.specializationFailure(service, err);
    }
    pub fn mapRow(self: *Generator, unit_id: u32, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), source_row: types.Effects.Id, actual_row: u32, span: core.Span, covariant: bool) Error!void {
        var service = try self.specializer();
        service.mapRow(unit_id, mappings, rows, source_row, actual_row, span, covariant) catch |err| return self.specializationFailure(service, err);
    }
    pub fn refineMappings(self: *Generator, unit_id: u32, root: EvidenceRoot, expected: layout.Id, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), span: core.Span) Error!void {
        var service = try self.specializer();
        service.refineMappings(unit_id, root, expected, mappings, rows, span) catch |err| return self.specializationFailure(service, err);
    }
    fn refineMappingsCaptures(self: *Generator, unit_id: u32, root: EvidenceRoot, expected: layout.Id, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), span: core.Span, captures: []const core_eval.RetainedCapture) Error!void {
        var service = try self.specializer();
        service.refineMappingsCaptures(unit_id, root, expected, mappings, rows, span, captures) catch |err| return self.specializationFailure(service, err);
    }
    pub fn refineAccessorMappings(self: *Generator, unit_id: u32, catalog: u32, expected: layout.Id, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), span: core.Span, captures: []const core_eval.RetainedCapture) Error!void {
        var projection: StaticCodeProjection = .{ .allocator = self.allocator, .layouts = &self.representations.store, .mappings = mappings };
        var service = try self.specializer();
        service.code_projection = .{ .context = &projection, .mapping = StaticCodeProjection.mapping };
        service.refineMappingsCaptures(unit_id, .{ .closure = .{ .unit = unit_id, .catalog = catalog } }, expected, mappings, rows, span, captures) catch |err| return self.specializationFailure(service, err);
    }
    pub fn mapCapturedFunction(self: *Generator, unit_id: u32, function_type: types.Id, expected: layout.Id, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), span: core.Span) Error!void {
        const source = self.unit(unit_id).types.node(function_type);
        const actual = self.representations.store.node(expected);
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
    pub fn function(self: *Generator, key: Key) Error!u32 {
        var scope: ?code_artifacts.Scope = if (self.artifacts) |context| try context.enter(.{ .named = key }) else null;
        defer if (scope) |*actor| actor.deinit();
        if (self.planning.instances.get(key)) |existing| {
            try self.planning.startup_facts.request(self.allocator, existing, .named, key.target.unit, key.target.binding, true);
            if (scope) |*actor| try actor.hit(existing);
            return existing;
        }
        if (self.retained) |retained| if (try self.findRetained(retained, .{ .named = key })) |job| {
            const function_id = try self.reconstructRetained(retained, job, .{ .named = key }, if (scope) |*actor| actor else null);
            try self.planning.startup_facts.request(self.allocator, function_id, .named, key.target.unit, key.target.binding, true);
            self.planning.startup_facts.complete(function_id);
            return function_id;
        };
        self.work.fresh_named += 1;
        const unit_id = key.target.unit;
        const source = self.unit(unit_id);
        const body = source.body(key.target.binding) orelse return self.decline(unit_id, source.binding(key.target.binding).span, .unsupported);
        if (body.is_function and body.parameters.len != key.count) return self.decline(unit_id, body.span, .unsupported);
        if (self.instance_depth >= 256 or self.planning.instances.count() >= 65536) return self.decline(unit_id, body.span, .complexity);
        self.instance_depth += 1;
        defer self.instance_depth -= 1;
        var parameters: [max_parameters + 2]wasm.ValueType = undefined;
        var roles: [max_parameters + 2]ir.Role = undefined;
        var parameter_locals: [max_parameters]u32 = @splat(std.math.maxInt(u32));
        var runtime_count: u32 = 0;
        for (key.parameters[0..key.count], 0..) |item, i| {
            if (self.representations.store.node(item).tag == .erased_proof) continue;
            parameter_locals[i] = runtime_count;
            parameters[runtime_count] = self.representations.store.machine(item);
            roles[runtime_count] = self.layoutRole(item);
            if (body.is_function) if (self.capturedTemplate(key.templates, source.bodyParameters(body)[i].binding)) |template| {
                if (template.scalar_environment) roles[runtime_count] = .scalar;
            };
            runtime_count += 1;
        }
        if (!body.is_function and runtime_count != key.count) return self.decline(unit_id, body.span, .unsupported);
        parameters[runtime_count] = .i32;
        roles[runtime_count] = .reference;
        var machine_count = runtime_count + 1;
        if (key.dictionaries) {
            _ = DictionaryOwner.forBinding(source, body.binding) orelse return self.decline(unit_id, body.span, .unsupported);
            parameters[machine_count] = .i32;
            roles[machine_count] = .reference;
            machine_count += 1;
        }
        const function_id = try self.module.addTypedFunction(parameters[0..machine_count], self.resultMachine(key.result), self.bodyResultRole(key.result, unit_id, body.root));
        try self.setParameterRoles(function_id, ir.packParameterRoles(roles[0..machine_count]), @intCast(runtime_count));
        try self.planning.instances.put(self.allocator, key, function_id);
        if (scope) |*actor| try actor.reserve(function_id);
        try self.planning.startup_facts.request(self.allocator, function_id, .named, unit_id, key.target.binding, false);
        const caller = self.planning.startup_facts.active;
        self.planning.startup_facts.active = function_id;
        defer self.planning.startup_facts.active = caller;
        if (!body.is_function) {
            var full = key.result;
            var reverse: usize = key.count;
            while (reverse > 0) {
                reverse -= 1;
                full = try self.internLayoutWithEffects(.function, key.parameters[reverse], full, key.effects[reverse], &.{});
            }
            if (source.binding(key.target.binding).has_explicit) {
                var mappings: std.ArrayList(Mapping) = .empty;
                var rows: std.ArrayList(RowMapping) = .empty;
                defer mappings.deinit(self.allocator);
                defer rows.deinit(self.allocator);
                try self.refineMappings(unit_id, .{ .body = key.target }, full, &mappings, &rows, body.span);
            }
            const global = if (body.runtime) try self.planning.runtimeGlobal(self, key.target) else null;
            const constant_ = if (global == null) try self.constant(key.target, full) else null;
            const callee = try self.module.addLocal(function_id, .i32);
            if (global) |index| try self.module.emit(function_id, .{ .op = .global_get, .operand = index }) else try self.emitValue(function_id, constant_.?);
            var ty_ = full;
            for (0..key.count) |index| {
                const arrow = self.representations.store.node(ty_);
                if (arrow.tag != .function) return self.decline(unit_id, body.span, .unresolved_type);
                for ([_]wasm.Instruction{
                    .{ .op = .local_set, .operand = callee },
                    .{ .op = .local_get, .operand = callee },
                    .{ .op = .i32_load, .operand = 4 },
                    .{ .op = .local_get, .operand = @intCast(index) },
                    .{ .op = .local_get, .operand = key.count },
                    .{ .op = .local_get, .operand = callee },
                    .{ .op = .i32_load },
                    .{ .op = .call_indirect, .operand = try self.module.internType(&.{ .i32, self.representations.store.machine(arrow.a), .i32 }, self.representations.store.machine(arrow.b)) },
                }) |instruction| {
                    if (instruction.op == .call_indirect) try self.module.emit(function_id, ir.callResult(self.layoutRole(arrow.b)));
                    try self.module.emit(function_id, instruction);
                    if (instruction.op == .call_indirect) if (self.request_owner) |owner| try request_runtime.guard(&self.module, function_id, owner, &.{});
                }
                ty_ = arrow.b;
            }
            // addFunction owns a copied signature; only a numeric handle escapes.
            if (scope) |*actor| try actor.complete(function_id, self.planning.template_results.get(key));
            self.planning.startup_facts.complete(function_id);
            // zig-analyzer: disable-next-line returning-local-slice
            return function_id;
        }
        var service = try self.specializer();
        var resolved = service.named(key, self.representations.instance_arguments.get(key.instance_arguments)) catch |err| return self.specializationFailure(service, err);
        defer resolved.deinit(self.allocator);
        if (key.dictionaries) {
            const owner = DictionaryOwner.forBinding(source, body.binding) orelse return self.decline(unit_id, body.span, .unsupported);
            @import("dictionary_layout.zig").bindOwner(self.allocator, source, &self.representations.store, &resolved.mappings, owner, 0, owner.formals(source), false) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.fail(unit_id, body.root, .unresolved_type);
        }
        const emitter = try self.allocator.create(Emitter);
        emitter.* = .{ .generator = self, .unit_id = unit_id, .function_id = function_id, .provider_local = runtime_count, .mappings = resolved.mappings.items, .row_mappings = resolved.rows.items, .factory_template = key.template_result };
        defer {
            emitter.deinit();
            self.allocator.destroy(emitter);
        }
        for (source.bodyParameters(body), 0..) |parameter, index| if (parameter.binding != 0) {
            const local = parameter_locals[index];
            if (local == std.math.maxInt(u32)) continue;
            if (self.capturedTemplate(key.templates, parameter.binding)) |template| {
                try emitter.templates.put(self.allocator, parameter.binding, .{ .unit = template.unit, .node = template.node, .environment = if (template.has_environment) local else null, .captures = template.captures, .templates = template.templates, .staged = template.staged, .scalar_environment = template.scalar_environment, .demand_cell = template.demand_cell, .computation = template.computation, .evidence = template.evidence, .rows = template.rows, .callable_instances = template.callable_instances });
            } else try emitter.locals.put(self.allocator, parameter.binding, local);
        };
        if (key.dictionaries) try emitter.installDictionary(body.root, runtime_count + 1, DictionaryOwner.forBinding(source, body.binding).?);
        if (key.template_result) {
            try emitter.bodyExpression(@backingInt(resolved.root), 0, true);
            const template = emitter.result_template orelse return self.fail(unit_id, body.root, .unresolved_type);
            try self.planning.template_results.put(self.allocator, key, template);
        } else {
            try emitter.bodyExpression(@backingInt(resolved.root), 0, false);
            if (source.types.node(source.typeOf(body.root)).tag == .never) try emitter.emit(.unreachable_, 0);
        }
        if (scope) |*actor| try actor.solved(resolved.mappings.items, resolved.rows.items, self.representations.template_keys.get(key.templates));
        // addFunction copied parameters into an owned signature; only its ID escapes.
        if (scope) |*actor| try actor.complete(function_id, self.planning.template_results.get(key));
        self.planning.startup_facts.complete(function_id);
        // zig-analyzer: disable-next-line returning-local-slice
        return function_id;
    }
    pub fn mappingEvidence(self: *Generator, mappings: []const Mapping) Error!u32 {
        var words: std.ArrayList(u32) = .empty;
        defer words.deinit(self.allocator);
        for (mappings) |mapping| {
            if (mapping.instance.decl != 0) continue;
            const actual = self.representations.toEvidence(self.evaluator.evidenceStore(), mapping.layout) catch |err| switch (err) {
                error.UnresolvedType => continue,
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type),
            };
            try words.appendSlice(self.allocator, &.{ mapping.variable, actual });
        }
        // Semantic record interning canonicalizes variable order and checks
        // equality after hash collisions. Its owner is the evaluation session.
        return self.evaluator.storage.evidence.intern(.record, 0, 0, words.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
    }
    pub fn rowMappingEvidence(self: *Generator, rows: []const RowMapping) Error!substitution_keys.Id {
        var entries: std.ArrayList(substitution_keys.Entry) = .empty;
        defer entries.deinit(self.allocator);
        for (rows) |mapping| {
            if (mapping.row == layout.unknown_row) continue;
            const actual = self.representations.rowToEvidence(self.evaluator.evidenceStore(), mapping.row) catch |err| switch (err) {
                error.UnresolvedType => continue,
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type),
            };
            try entries.append(self.allocator, .{ .variable = mapping.variable, .value = actual });
        }
        return self.representations.row_keys.intern(entries.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
    }
    pub fn loadSemanticRows(self: *Generator, mappings: []const type_evidence.RowMapping, rows: *std.ArrayList(RowMapping)) Error!void {
        for (mappings) |mapping| {
            const concrete = self.representations.rowFromEvidence(self.evaluator.evidenceStore(), mapping.evidence) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
            try rows.append(self.allocator, .{ .variable = mapping.variable, .row = concrete });
        }
    }
    pub fn captureTemplate(self: *Generator, template: Template) Error!u32 {
        const retained: CapturedTemplate = .{ .unit = template.unit, .node = template.node, .captures = template.captures, .templates = template.templates, .staged = template.staged, .has_environment = template.environment != null, .scalar_environment = template.scalar_environment, .demand_cell = template.demand_cell, .computation = template.computation, .evidence = template.evidence, .rows = template.rows, .callable_instances = template.callable_instances };
        if (self.planning.template_instances.get(retained)) |existing| return existing;
        if (self.planning.template_catalog.items.len >= std.math.maxInt(u32)) return error.ModuleTooLarge;
        const id: u32 = @intCast(self.planning.template_catalog.items.len + 1);
        try self.planning.template_catalog.append(self.allocator, retained);
        try self.planning.template_instances.put(self.allocator, retained, id);
        return id;
    }
    pub fn capturedTemplate(self: *Generator, key: substitution_keys.Id, binding: core.BindingId) ?CapturedTemplate {
        for (self.representations.template_keys.get(key)) |entry| if (entry.variable == binding) return self.planning.template_catalog.items[entry.value - 1];
        return null;
    }
    fn capturedStatic(self: *Generator, key: substitution_keys.Id, binding: core.BindingId) ?core_eval.ValueId {
        for (self.representations.static_keys.get(key)) |entry| if (entry.variable == binding) return entry.value;
        return null;
    }
    pub fn directCallableEnvironment(self: *const Generator, ty: layout.Id, applied: usize) bool {
        var current = ty;
        var retained: ?layout.Id = null;
        for (0..applied) |_| {
            const arrow = self.representations.store.node(current);
            if (arrow.tag != .function) return false;
            current = arrow.b;
            if (self.representations.store.node(arrow.a).tag == .erased_proof) continue;
            if (retained != null) return false;
            retained = arrow.a;
        }
        if (retained) |argument| return self.layoutRole(argument) == .reference;
        return false;
    }
    fn retainedCapture(self: *Generator, allocator: Allocator, binding: core.BindingId, template: CapturedTemplate, depth: usize) Error!core_eval.RetainedCapture {
        if (depth >= 256) return self.fail(template.unit, template.node, .complexity);
        var rows: std.ArrayList(type_evidence.RowMapping) = .empty;
        errdefer rows.deinit(allocator);
        for (self.representations.row_keys.get(template.rows)) |row| try rows.append(allocator, .{ .variable = row.variable, .evidence = row.value });
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
                } else if (index < self.representations.store.children(template.captures).len) {
                    const actual = self.representations.toEvidence(self.evaluator.evidenceStore(), self.representations.store.children(template.captures)[index]) catch |err| switch (err) {
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
    pub fn resolveClosureMappings(self: *Generator, key: ClosureKey, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping)) Error!void {
        const source = self.unit(key.unit);
        const metadata = source.closures[key.catalog];
        const captures = source.extra[metadata.captures.start..][0..metadata.captures.len];
        const fn_type = self.representations.store.node(key.ty);
        for (self.representations.row_keys.get(key.rows)) |mapping| {
            const concrete = self.representations.rowFromEvidence(self.evaluator.evidenceStore(), mapping.value) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.fail(key.unit, metadata.body, .unresolved_type);
            try rows.append(self.allocator, .{ .variable = mapping.variable, .row = concrete });
        }
        if (key.evidence != 0) {
            const words = self.evaluator.storage.evidence.children(key.evidence);
            var index: usize = 0;
            while (index < words.len) : (index += 2) {
                const concrete = self.representations.fromEvidence(self.evaluator.evidenceStore(), words[index + 1]) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.fail(key.unit, metadata.body, .unresolved_type);
                try self.mapType(key.unit, mappings, words[index], concrete, source.span(metadata.body));
            }
        }
        for (captures, 0..) |binding, index| if (self.capturedTemplate(key.templates, binding) == null and self.capturedStatic(key.static_values, binding) == null) {
            try self.mapType(key.unit, mappings, source.binding(binding).ty, self.representations.store.children(key.captures)[index], source.span(metadata.body));
        };
        try self.mapType(key.unit, mappings, metadata.parameter.ty, fn_type.a, metadata.parameter.span);
        try self.mapType(key.unit, mappings, source.typeOf(metadata.body), fn_type.b, source.span(metadata.body));
        if (metadata.function_type != 0) try self.mapTypeDepth(key.unit, mappings, rows, metadata.function_type, key.ty, source.span(metadata.body), 0);
        var hint_arena = std.heap.ArenaAllocator.init(self.allocator);
        defer hint_arena.deinit();
        var hints: std.ArrayList(core_eval.RetainedCapture) = .empty;
        for (captures) |binding| {
            if (self.capturedStatic(key.static_values, binding)) |value| {
                try hints.append(hint_arena.allocator(), .{ .binding = binding, .unit = key.unit, .node = 0, .value = value });
            } else if (self.capturedTemplate(key.templates, binding)) |template| try hints.append(hint_arena.allocator(), try self.retainedCapture(hint_arena.allocator(), binding, template, 0));
        }
        if (key.parameter_template != 0) try hints.append(hint_arena.allocator(), try self.retainedCapture(hint_arena.allocator(), metadata.parameter.binding, self.planning.template_catalog.items[key.parameter_template - 1], 0));
        try self.refineMappingsCaptures(key.unit, .{ .closure = .{ .unit = key.unit, .catalog = key.catalog } }, key.ty, mappings, rows, source.span(metadata.body), hints.items);
    }
    pub fn closureFunction(self: *Generator, key: ClosureKey) Error!u32 {
        var scope: ?code_artifacts.Scope = if (self.artifacts) |context| try context.enter(.{ .closure = key }) else null;
        defer if (scope) |*actor| actor.deinit();
        if (self.planning.closures.get(key)) |existing| {
            try self.planning.startup_facts.request(self.allocator, existing, .anonymous, key.unit, key.catalog, true);
            if (scope) |*actor| try actor.hit(existing);
            return existing;
        }
        // Static captures use executable graph admission, independently of
        // the closed principal mappings saved below.
        if (key.staged == 0) if (self.retained) |retained| if (try self.findRetained(retained, .{ .closure = key })) |job| {
            const function_id = try self.reconstructRetained(retained, job, .{ .closure = key }, if (scope) |*actor| actor else null);
            try self.planning.startup_facts.request(self.allocator, function_id, .anonymous, key.unit, key.catalog, true);
            self.planning.startup_facts.complete(function_id);
            return function_id;
        };
        self.work.fresh_closures += 1;
        const source = self.unit(key.unit);
        const metadata = source.closures[key.catalog];
        const captures = source.extra[metadata.captures.start..][0..metadata.captures.len];
        const fn_type = self.representations.store.node(key.ty);
        if (fn_type.tag != .function or captures.len != self.representations.store.children(key.captures).len) return self.fail(key.unit, metadata.body, .unresolved_type);
        if (key.scalar_environment and (!self.representations.store.scalarEnvironment(key.captures) or key.templates != 0 or key.static_values != 0)) return self.fail(key.unit, metadata.body, .unresolved_type);
        if (self.instance_depth >= 256) return self.fail(key.unit, metadata.body, .complexity);
        self.instance_depth += 1;
        defer self.instance_depth -= 1;
        var wrapper_signature = try self.closureSignature(fn_type.a, fn_type.b);
        var roles = self.closureRoles(fn_type.a);
        if (key.dictionaries) {
            wrapper_signature = try self.dictionaryClosureSignature(fn_type.a, fn_type.b);
            roles = self.dictionaryClosureRoles(fn_type.a);
        }
        if (key.parameter_template != 0 and self.planning.template_catalog.items[key.parameter_template - 1].scalar_environment) roles = (roles & ~@as(u64, 3 << 2)) | (@as(u64, @backingInt(ir.Role.scalar)) << 2);
        if (key.scalar_environment) roles = (roles & ~@as(u64, 3)) | @as(u64, @backingInt(ir.Role.scalar));
        const function_id = try self.module.addTypedFunctionForSignature(wrapper_signature, self.bodyResultRole(fn_type.b, key.unit, metadata.body));
        try self.setParameterRoles(function_id, roles, 2);
        try self.callableLayout(function_id, key.ty);
        try self.planning.closures.put(self.allocator, key, function_id);
        if (scope) |*actor| try actor.reserve(function_id);
        try self.planning.startup_facts.request(self.allocator, function_id, .anonymous, key.unit, key.catalog, false);
        const caller = self.planning.startup_facts.active;
        self.planning.startup_facts.active = function_id;
        defer self.planning.startup_facts.active = caller;
        var mappings: std.ArrayList(Mapping) = .empty;
        var rows: std.ArrayList(RowMapping) = .empty;
        defer rows.deinit(self.allocator);
        defer mappings.deinit(self.allocator);
        try self.resolveClosureMappings(key, &mappings, &rows);
        if (key.dictionaries) {
            const owner = source.types.node(metadata.function_type);
            @import("dictionary_layout.zig").bind(self.allocator, source, &self.representations.store, &mappings, metadata.function_type, 0, .{ .start = owner.b, .len = owner.c }, false) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.fail(key.unit, metadata.body, .unresolved_type);
        }
        var emitter: Emitter = .{ .generator = self, .unit_id = key.unit, .function_id = function_id, .provider_local = 2, .mappings = mappings.items, .row_mappings = rows.items, .factory_template = key.template_result, .staged = if (key.staged == 0) null else key.staged };
        defer emitter.deinit();
        if (metadata.parameter.binding != 0) {
            if (key.parameter_template != 0) {
                const template = self.planning.template_catalog.items[key.parameter_template - 1];
                try emitter.templates.put(self.allocator, metadata.parameter.binding, .{ .unit = template.unit, .node = template.node, .environment = if (template.has_environment) 1 else null, .captures = template.captures, .templates = template.templates, .staged = template.staged, .scalar_environment = template.scalar_environment, .demand_cell = template.demand_cell, .computation = template.computation, .evidence = template.evidence, .rows = template.rows, .callable_instances = template.callable_instances });
            } else try emitter.locals.put(self.allocator, metadata.parameter.binding, 1);
        }
        for (captures, 0..) |binding, index| {
            if (self.capturedStatic(key.static_values, binding)) |value| {
                try emitter.static_values.put(self.allocator, binding, value);
                continue;
            }
            const capture_type = self.representations.store.children(key.captures)[index];
            const machine = self.representations.store.machine(capture_type);
            const local = try self.module.addLocal(function_id, machine);
            try emitter.emit(.local_get, 0);
            if (!key.scalar_environment) try emitter.emit(if (machine == .f32) .f32_load else .i32_load, @intCast(index * 4));
            try emitter.emit(.local_set, local);
            if (self.capturedTemplate(key.templates, binding)) |template| {
                try emitter.templates.put(self.allocator, binding, .{ .unit = template.unit, .node = template.node, .environment = if (template.has_environment) local else null, .captures = template.captures, .templates = template.templates, .staged = template.staged, .scalar_environment = template.scalar_environment, .demand_cell = template.demand_cell, .computation = template.computation, .evidence = template.evidence, .rows = template.rows, .callable_instances = template.callable_instances });
            } else try emitter.locals.put(self.allocator, binding, local);
        }
        if (key.dictionaries) {
            if (source.types.node(metadata.function_type).tag != .forall or source.types.quantifierGoals(metadata.function_type).len == 0) return self.decline(key.unit, source.span(metadata.body), .unsupported);
            try emitter.installUniversalDictionary(metadata.body, 3, metadata.function_type);
        }
        if (key.template_result) {
            try emitter.bodyExpression(metadata.body, 0, true);
            const template = emitter.result_template orelse return self.fail(key.unit, metadata.body, .unresolved_type);
            try self.planning.closure_template_results.put(self.allocator, key, template);
        } else {
            try emitter.bodyExpression(metadata.body, 0, false);
            if (source.types.node(source.typeOf(metadata.body)).tag == .never) try emitter.emit(.unreachable_, 0);
        }
        // Generic static fields may retain erased layouts. Their complete
        // capture graph belongs to the code key; it is not a closed principal
        // mapping receipt suitable for independent semantic reuse.
        if (key.static_values == 0) if (scope) |*actor| try actor.solved(mappings.items, rows.items, self.representations.template_keys.get(key.templates));
        if (scope) |*actor| try actor.complete(function_id, self.planning.closure_template_results.get(key));
        self.planning.startup_facts.complete(function_id);
        return function_id;
    }
    pub fn selectMemberTemplate(self: *Generator, unit_id: u32, node: core.Id, reference: core.BindingRef, expected: layout.Id) Error!core.BindingRef {
        if (!self.evaluator.has_implementations) return reference;
        var declaration_unit = unit_id;
        if (reference.unit != 0) declaration_unit = reference.unit;
        const declaration = self.unit(declaration_unit);
        var template = false;
        for (declaration.member_templates) |member| if (member.binding == reference.binding) {
            template = true;
            break;
        };
        if (!template) return reference;
        const owner = for (self.units, 0..) |source, index| {
            if (source.unit == unit_id) break index;
        } else return self.fail(unit_id, node, .unsupported);
        const actual = self.representations.toEvidence(self.evaluator.evidenceStore(), expected) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return self.fail(unit_id, node, .unresolved_type),
        };
        return self.evaluator.selectTemplate(owner, node, reference, actual) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return self.evaluationFailure(),
        };
    }
    pub fn callable(self: *Generator, key: CallableKey) Error!u32 {
        if (key.bound_dictionaries and !key.dictionaries) return self.decline(key.target.unit, self.unit(key.target.unit).binding(key.target.binding).span, .unsupported);
        const selected = try self.selectMemberTemplate(key.target.unit, 0, key.target, key.ty);
        if (!std.meta.eql(selected, key.target)) {
            var actual = key;
            actual.target = selected;
            // Producer bindings belong to the original source namespace.
            actual.templates = 0;
            return self.callable(actual);
        }
        var scope: ?code_artifacts.Scope = if (self.artifacts) |context| try context.enter(.{ .callable = key }) else null;
        defer if (scope) |*actor| actor.deinit();
        if (self.planning.callables.get(key)) |existing| {
            if (scope) |*actor| try actor.hit(existing);
            return existing;
        }
        const source = self.unit(key.target.unit);
        const body = source.body(key.target.binding) orelse return self.decline(key.target.unit, source.binding(key.target.binding).span, .unsupported);
        if (body.parameters.len == 0) {
            if (key.applied != 0) return self.decline(key.target.unit, body.span, .unsupported);
            const arrow = self.representations.store.node(key.ty);
            if (arrow.tag != .function) return self.decline(key.target.unit, body.span, .unresolved_type);
            if (self.representations.store.node(arrow.a).tag == .erased_proof) return self.decline(key.target.unit, body.span, .unsupported);
            const function_id = try self.module.addTypedFunction(&.{ .i32, self.representations.store.machine(arrow.a), .i32 }, self.representations.store.machine(arrow.b), self.layoutRole(arrow.b));
            try self.setParameterRoles(function_id, self.closureRoles(arrow.a), 2);
            try self.callableLayout(function_id, key.ty);
            try self.planning.callables.put(self.allocator, key, function_id);
            if (scope) |*actor| try actor.reserve(function_id);
            const global = if (body.runtime) try self.planning.runtimeGlobal(self, key.target) else null;
            const constant_ = if (global == null) try self.constant(key.target, key.ty) else null;
            // constant() just serialized this checked source callable and its
            // complete captures. Consume those compiler-owned operands here;
            // runtime globals and opaque or mismatched callables stay indirect.
            if (constant_) |value| if (value.scalar == .pointer and value.bits <= self.module.data.items.len and self.module.data.items.len - value.bits >= @sizeOf(heap.Closure)) {
                const target_id = std.mem.readInt(u32, self.module.data.items[value.bits + heap.offset(heap.Closure, "function") ..][0..4], .little);
                const environment = std.mem.readInt(u32, self.module.data.items[value.bits + heap.offset(heap.Closure, "environment") ..][0..4], .little);
                if (target_id != function_id and target_id < self.module.functions.items.len) {
                    const target = self.module.functions.items[target_id];
                    if (!target.entry and target.signature == self.module.functions.items[function_id].signature and target.result_role == self.layoutRole(arrow.b) and target.parameter_roles == self.closureRoles(arrow.a)) {
                        try self.module.emit(function_id, ir.immortalReference());
                        try self.module.emitReference(function_id, .{ .op = .i32_const, .operand = environment }, .static_address);
                        try self.module.emitSlice(function_id, &.{ .{ .op = .local_get, .operand = 1 }, .{ .op = .local_get, .operand = 2 }, .{ .op = .call, .operand = target_id } });
                        if (self.request_owner) |owner| try request_runtime.guard(&self.module, function_id, owner, &.{});
                        if (scope) |*actor| try actor.complete(function_id, null);
                        return function_id;
                    }
                }
            };
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
                .{ .op = .call_indirect, .operand = try self.module.internType(&.{ .i32, self.representations.store.machine(arrow.a), .i32 }, self.representations.store.machine(arrow.b)) },
            }) |instruction| {
                if (instruction.op == .call_indirect) try self.module.emit(function_id, ir.callResult(self.layoutRole(arrow.b)));
                try self.module.emit(function_id, instruction);
                if (instruction.op == .call_indirect) if (self.request_owner) |owner| try request_runtime.guard(&self.module, function_id, owner, &.{});
            }
            if (scope) |*actor| try actor.complete(function_id, null);
            return function_id;
        }
        if (body.parameters.len > max_parameters or key.applied >= body.parameters.len) return self.decline(key.target.unit, body.span, .unsupported);
        var direct: Key = .{ .target = key.target, .count = @intCast(body.parameters.len), .templates = key.templates, .dictionaries = key.dictionaries, .instance_arguments = key.instance_arguments };
        var ty = key.ty;
        var current: layout.Node = undefined;
        for (0..body.parameters.len) |index| {
            const n = self.representations.store.node(ty);
            if (n.tag != .function) return self.decline(key.target.unit, body.span, .unresolved_type);
            direct.parameters[index] = n.a;
            direct.effects[index] = n.c;
            if (index == key.applied) current = n;
            ty = n.b;
        }
        direct.result = ty;
        const erased_argument = self.representations.store.node(current.a).tag == .erased_proof;
        var wrapper_type = try self.closureSignature(current.a, current.b);
        if (key.dictionaries and !key.bound_dictionaries and key.applied == 0) wrapper_type = try self.dictionaryClosureSignature(current.a, current.b);
        const function_id = try self.module.addTypedFunctionForSignature(wrapper_type, self.layoutRole(current.b));
        var provider_local: u32 = 2;
        if (erased_argument) provider_local = 1;
        var parameter_roles = self.closureRoles(current.a);
        if (key.dictionaries and !key.bound_dictionaries and key.applied == 0) parameter_roles = self.dictionaryClosureRoles(current.a);
        try self.setParameterRoles(function_id, parameter_roles, @intCast(provider_local));
        try self.callableLayout(function_id, try self.internLayoutWithEffects(.function, current.a, current.b, current.c, &.{}));
        try self.planning.callables.put(self.allocator, key, function_id);
        if (scope) |*actor| try actor.reserve(function_id);
        var emitter: Emitter = .{ .generator = self, .unit_id = key.target.unit, .function_id = function_id, .provider_local = provider_local, .mappings = &.{} };
        defer emitter.deinit();
        if (key.applied + 1 == body.parameters.len) {
            const target_function = try self.function(direct);
            var stored: u32 = 0;
            for (direct.parameters[0..key.applied]) |parameter| {
                if (self.representations.store.node(parameter).tag == .erased_proof) continue;
                try emitter.emit(.local_get, 0);
                if (key.dictionaries or !self.directCallableEnvironment(key.ty, key.applied)) try emitter.emit(if (self.representations.store.machine(parameter) == .f32) .f32_load else .i32_load, (stored + @intFromBool(key.dictionaries)) * 4);
                stored += 1;
            }
            if (!erased_argument) try emitter.emit(.local_get, 1);
            try emitter.providerHead();
            if (key.dictionaries) {
                if (key.applied == 0 and !key.bound_dictionaries) {
                    try emitter.emit(.local_get, provider_local + 1);
                } else {
                    try emitter.emit(.local_get, 0);
                    try emitter.emit(.i32_load, 0);
                }
            }
            try emitter.emit(.call, target_function);
        } else if (erased_argument) {
            const next = try self.callable(.{ .target = key.target, .ty = key.ty, .applied = key.applied + 1, .templates = key.templates, .dictionaries = key.dictionaries, .bound_dictionaries = key.bound_dictionaries, .instance_arguments = key.instance_arguments });
            try emitter.descriptor(next, 0);
        } else if (!key.dictionaries and self.directCallableEnvironment(key.ty, key.applied + 1)) {
            const next = try self.callable(.{ .target = key.target, .ty = key.ty, .applied = key.applied + 1, .templates = key.templates, .dictionaries = key.dictionaries, .bound_dictionaries = key.bound_dictionaries, .instance_arguments = key.instance_arguments });
            try emitter.descriptor(next, 1);
        } else {
            var retained: [max_parameters + 1]layout.Id = undefined;
            var count: u32 = 0;
            if (key.dictionaries) {
                retained[0] = try self.internLayout(.array, 3, 0, &.{});
                count = 1;
            }
            for (direct.parameters[0 .. key.applied + 1]) |parameter| {
                if (self.representations.store.node(parameter).tag == .erased_proof) continue;
                retained[count] = parameter;
                count += 1;
            }
            const environment_roles = try emitter.layoutRoles(self.allocator, retained[0..count]);
            defer self.allocator.free(environment_roles);
            const environment = try emitter.allocate(count * 4, .{ .words = environment_roles });
            var stored: u32 = 0;
            if (key.dictionaries) {
                try emitter.emit(.local_get, environment);
                if (key.applied == 0 and !key.bound_dictionaries) {
                    try emitter.emit(.local_get, provider_local + 1);
                } else {
                    try emitter.emit(.local_get, 0);
                    try emitter.emit(.i32_load, 0);
                }
                try emitter.emit(.i32_store, 0);
                stored = 1;
            }
            for (direct.parameters[0..key.applied]) |parameter| {
                if (self.representations.store.node(parameter).tag == .erased_proof) continue;
                const floating = self.representations.store.machine(parameter) == .f32;
                try emitter.emit(.local_get, environment);
                try emitter.emit(.local_get, 0);
                if (key.dictionaries or !self.directCallableEnvironment(key.ty, key.applied)) try emitter.emit(if (floating) .f32_load else .i32_load, stored * 4);
                try emitter.emit(if (floating) .f32_store else .i32_store, stored * 4);
                stored += 1;
            }
            try emitter.emit(.local_get, environment);
            try emitter.emit(.local_get, 1);
            try emitter.emit(if (self.representations.store.machine(current.a) == .f32) .f32_store else .i32_store, stored * 4);
            const next = try self.callable(.{ .target = key.target, .ty = key.ty, .applied = key.applied + 1, .templates = key.templates, .dictionaries = key.dictionaries, .bound_dictionaries = key.bound_dictionaries, .instance_arguments = key.instance_arguments });
            try emitter.descriptor(next, environment);
        }
        if (scope) |*actor| try actor.complete(function_id, null);
        return function_id;
    }
    pub fn constructorFunction(self: *Generator, key: ConstructorKey) Error!u32 {
        var scope: ?code_artifacts.Scope = if (self.artifacts) |context| try context.enter(.{ .constructor = key }) else null;
        defer if (scope) |*actor| actor.deinit();
        if (self.planning.constructor_functions.get(key)) |existing| {
            if (scope) |*actor| try actor.hit(existing);
            return existing;
        }
        const fn_type = self.representations.store.node(key.ty);
        if (fn_type.tag != .function) return self.decline(key.unit, .{ .start = 0, .end = 0 }, .unresolved_type);
        const function_id = try self.module.addTypedFunction(&.{ .i32, self.representations.store.machine(fn_type.a), .i32 }, self.representations.store.machine(fn_type.b), self.layoutRole(fn_type.b));

        try self.setParameterRoles(function_id, self.closureRoles(fn_type.a), 2);
        try self.callableLayout(function_id, key.ty);
        try self.planning.constructor_functions.put(self.allocator, key, function_id);
        if (scope) |*actor| try actor.reserve(function_id);
        var emitter: Emitter = .{ .generator = self, .unit_id = key.unit, .function_id = function_id, .provider_local = 2, .mappings = &.{} };
        defer emitter.deinit();
        const metadata = self.unit(key.unit).constructor(key.catalog);
        if (self.unit(key.unit).nominal(metadata.nominal).is_opaque) {
            try emitter.emit(.local_get, 1);
            if (scope) |*actor| try actor.complete(function_id, null);
            return function_id;
        }
        const payload_type = self.unit(key.unit).types.node(metadata.payload);
        const record_local = if (payload_type.tag == .record and payload_type.b == 1) blk: {
            const record = try emitter.allocate(4, .{ .words = &.{self.layoutRole(fn_type.a)} });
            try emitter.emit(.local_get, record);
            try emitter.emit(.local_get, 1);
            try emitter.emit(if (self.representations.store.machine(fn_type.a) == .f32) .f32_store else .i32_store, 0);
            break :blk record;
        } else if (payload_type.tag == .record) try emitter.recordRepresentation(payload_type, 1, true) else null;
        if (record_local) |record| if (record != 1) try emitter.markAcyclic(record, fn_type.a);
        // A constructor cell is its tag, then its boxed record or argument.
        const address = try emitter.allocate(8, .{ .words = &.{ .scalar, if (record_local != null) .reference else self.layoutRole(fn_type.a) } });
        if (record_local != null or self.layoutRole(fn_type.a) == .reference) try emitter.markAcyclic(address, fn_type.b);
        try emitter.emit(.local_get, address);
        try emitter.emit(.i32_const, metadata.tag);
        try emitter.emit(.i32_store, 0);
        try emitter.emit(.local_get, address);
        try emitter.emit(.local_get, record_local orelse 1);
        try emitter.emit(if (record_local == null and self.representations.store.machine(fn_type.a) == .f32) .f32_store else .i32_store, 4);
        try emitter.emit(.local_get, address);
        if (scope) |*actor| try actor.complete(function_id, null);
        return function_id;
    }
    pub fn primitiveFunction(self: *Generator, key: PrimitiveKey) Error!u32 {
        var scope: ?code_artifacts.Scope = if (self.artifacts) |context| try context.enter(.{ .primitive = key }) else null;
        defer if (scope) |*actor| actor.deinit();
        if (self.planning.primitive_functions.get(key)) |existing| {
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
            const arrow = self.representations.store.node(ty);
            if (arrow.tag != .function) return self.fail(key.unit, 0, .unresolved_type);
            parameters[index] = arrow.a;
            if (index == key.applied) current = arrow;
            ty = arrow.b;
        }
        if (self.planning.primitive_functions.count() >= 65536) return self.fail(key.unit, 0, .complexity);
        const function_id = try self.module.addTypedFunction(&.{ .i32, self.representations.store.machine(current.a), .i32 }, self.representations.store.machine(current.b), self.layoutRole(current.b));
        try self.setParameterRoles(function_id, self.closureRoles(current.a), 2);
        try self.callableLayout(function_id, try self.internLayoutWithEffects(.function, current.a, current.b, current.c, &.{}));
        try self.planning.primitive_functions.put(self.allocator, key, function_id);
        if (scope) |*actor| try actor.reserve(function_id);
        var emitter: Emitter = .{ .generator = self, .unit_id = key.unit, .function_id = function_id, .provider_local = 2, .mappings = &.{} };
        defer emitter.deinit();
        if (key.applied + 1 == metadata.arity) {
            var locals: [3]u32 = undefined;
            var machines: [3]wasm.ValueType = undefined;
            for (parameters[0..metadata.arity], 0..) |parameter, index| {
                const machine = self.representations.store.machine(parameter);
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
                .scalar => if (self.representations.store.node(parameters[0]).tag == .product) {
                    // A callable value cannot carry literal lane selectors.
                    const simd = @import("simd_intrinsics.zig");
                    if (simd.literalLanes(metadata.op)) return self.fail(key.unit, 0, .simd_lane_literal);
                    var operands: [3]u32 = undefined;
                    operands[0] = locals[0];
                    var count: usize = 1;
                    if (metadata.arity == 2 and simd.pairs(metadata.op)) {
                        try emitter.simdPairLocals(locals[1], operands[1..3]);
                        count = 3;
                    } else if (metadata.arity == 2) {
                        operands[1] = locals[1];
                        count = 2;
                    }
                    try emitter.simdLocals(metadata.op, operands[0..count], null, parameters[0], ty);
                } else {
                    const scalar_type = self.representations.store.scalar(parameters[0]) orelse return self.fail(key.unit, 0, .unsupported);
                    const opcode = scalar_ops.opcode(metadata.op, scalar_type) orelse return self.fail(key.unit, 0, .unsupported);
                    for (locals[0..metadata.arity]) |local| try emitter.emit(.local_get, local);
                    try emitter.emit(opcode, 0);
                },
                .array => try emitter.arrayLocals(0, metadata.array_op, locals[0..metadata.arity], machines[0..metadata.arity], ty, parameters[0]),
            }
        } else {
            const environment_roles = try emitter.layoutRoles(self.allocator, parameters[0 .. key.applied + 1]);
            defer self.allocator.free(environment_roles);
            const environment = try emitter.allocate((key.applied + 1) * 4, .{ .words = environment_roles });
            for (parameters[0..key.applied], 0..) |parameter, index| {
                const floating = self.representations.store.machine(parameter) == .f32;
                try emitter.emit(.local_get, environment);
                try emitter.emit(.local_get, 0);
                try emitter.emit(if (floating) .f32_load else .i32_load, @intCast(index * 4));
                try emitter.emit(if (floating) .f32_store else .i32_store, @intCast(index * 4));
            }
            try emitter.emit(.local_get, environment);
            try emitter.emit(.local_get, 1);
            try emitter.emit(if (self.representations.store.machine(current.a) == .f32) .f32_store else .i32_store, key.applied * 4);
            const next = try self.primitiveFunction(.{ .unit = key.unit, .catalog = key.catalog, .ty = key.ty, .applied = key.applied + 1 });
            try emitter.descriptor(next, environment);
        }
        if (scope) |*actor| try actor.complete(function_id, null);
        return function_id;
    }
    pub fn runtimeDataWord(self: *Generator, address: u32, operation: runtime_operations.Id) Error!void {
        self.planning.runtime_operations.dataWord(&self.module, address, operation) catch |err| switch (err) {
            error.InvalidOperation => return error.InvalidFunctionReference,
            error.OutOfMemory => return error.OutOfMemory,
            error.ModuleTooLarge => return error.ModuleTooLarge,
        };
    }
    pub fn runtimeOperation(self: *Generator, label: type_evidence.Effects.Label, unit_id: u32, span: core.Span) Error!runtime_operations.Id {
        // Runtime descriptors contain declaration/signature only. The scoped
        // owner is an independent owned environment edge, never a static tag.
        var descriptor_label = label;
        const descriptor = self.evaluator.storage.evidence.effects.view().operation(label);
        if (descriptor.instance.decl != 0) descriptor_label = self.evaluator.storage.evidence.effects.internOperation(descriptor.identity, self.evaluator.storage.evidence.effects.view().operationArguments(label)) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
        const previous_count = self.planning.runtime_operations.entries.items.len;
        const operation = self.planning.runtime_operations.intern(self.evaluator.storage.evidence.view(), descriptor_label) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.ModuleTooLarge => error.ModuleTooLarge,
            error.InvalidOperation => self.decline(unit_id, span, .unresolved_type),
        };
        try self.module.demandResource(.operation, operation, operation <= previous_count);
        return operation;
    }
    pub fn operationLabel(self: *Generator, unit_id: u32, catalog: u32, mappings: []const Mapping, rows: []const RowMapping, span: core.Span) Error!type_evidence.Effects.Label {
        const source = self.unit(unit_id);
        if (catalog >= source.operation_values.len) return self.decline(unit_id, span, .unsupported);
        const operation = source.operation_values[catalog];
        var arguments: std.ArrayList(type_evidence.Id) = .empty;
        defer arguments.deinit(self.allocator);
        for (source.types.list(operation.arguments)) |argument| {
            const concrete = try self.codeLayoutWithRows(unit_id, argument, mappings, rows, span);
            const actual = self.representations.toEvidence(self.evaluator.evidenceStore(), concrete) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
            try arguments.append(self.allocator, actual);
        }
        const semantic_label = self.evaluator.storage.evidence.effects.internOperationInstance(operation.identity, arguments.items, layout.mappedInstance(operation.instance, mappings)) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
        return semantic_label;
    }
    pub fn operationLayoutLabel(self: *Generator, operation_type: layout.Id, unit_id: u32, span: core.Span) Error!type_evidence.Effects.Label {
        const operation = self.representations.store.node(operation_type);
        if (operation.tag != .nominal) return self.decline(unit_id, span, .unresolved_type);
        var arguments: std.ArrayList(type_evidence.Id) = .empty;
        defer arguments.deinit(self.allocator);
        const source_arguments = try self.allocator.dupe(layout.Id, self.representations.store.children(operation_type));
        defer self.allocator.free(source_arguments);
        for (source_arguments) |argument| {
            const actual = self.representations.toEvidence(self.evaluator.evidenceStore(), argument) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
            try arguments.append(self.allocator, actual);
        }
        const semantic_label = self.evaluator.storage.evidence.effects.internOperation(.{ .unit = operation.a, .decl = operation.b }, arguments.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
        return semantic_label;
    }
    pub fn requestLabel(self: *Generator, unit_id: u32, label: types.Effects.Label, mappings: []const Mapping, rows: []const RowMapping, span: core.Span) Error!type_evidence.Effects.Label {
        const source = self.unit(unit_id);
        const operation = source.types.operation(label);
        var arguments: std.ArrayList(type_evidence.Id) = .empty;
        defer arguments.deinit(self.allocator);
        for (source.types.list(operation.arguments)) |argument| {
            const concrete = try self.codeLayoutWithRows(unit_id, argument, mappings, rows, span);
            const actual = self.representations.toEvidence(self.evaluator.evidenceStore(), concrete) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
            try arguments.append(self.allocator, actual);
        }
        const semantic_label = self.evaluator.storage.evidence.effects.internOperationInstance(operation.identity, arguments.items, operation.instance) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(unit_id, span, .unresolved_type);
        return semantic_label;
    }
    pub fn operationFunction(self: *Generator, key: OperationKey) Error!u32 {
        var scope: ?code_artifacts.Scope = if (self.artifacts) |context| try context.enter(.{ .operation = key }) else null;
        defer if (scope) |*actor| actor.deinit();
        if (self.planning.operation_functions.get(key)) |existing| {
            if (scope) |*actor| try actor.hit(existing);
            return existing;
        }
        const arrow = self.representations.store.node(key.ty);
        if (arrow.tag != .function) return self.decline(1, .{ .start = 0, .end = 0 }, .unresolved_type);
        const argument_machine = self.representations.store.machine(arrow.a);
        const result_machine = self.representations.store.machine(arrow.b);
        const function_id = try self.module.addTypedFunction(&.{ .i32, argument_machine, .i32 }, result_machine, self.layoutRole(arrow.b));
        try self.setParameterRoles(function_id, self.closureRoles(arrow.a), 2);
        try self.callableLayout(function_id, key.ty);
        try self.planning.operation_functions.put(self.allocator, key, function_id);
        if (scope) |*actor| try actor.reserve(function_id);
        var emitter: Emitter = .{ .generator = self, .unit_id = 1, .function_id = function_id, .provider_local = 2, .mappings = &.{} };
        defer emitter.deinit();
        if (key.scoped) {
            try emitter.emit(.local_get, 0);
            try emitter.emit(.i32_load, heap.offset(heap.EffectAuthority, "active"));
            try emitter.emit(.i32_eqz, 0);
            try emitter.emit(.if_, 0);
            try emitter.emit(.unreachable_, 0);
            try emitter.emit(.end, 0);
        }
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
        if (self.scoped_effects) {
            try emitter.operationOwnerMatch(frame, key.scoped);
            try emitter.emit(.i32_and, 0);
        }
        try emitter.emit(.br_if, 1);
        try emitter.emit(.local_get, frame);
        try emitter.emit(.i32_load, @offsetOf(heap.StateFrame, "kind"));
        try emitter.emit(.i32_const, heap.StateFrame.tag);
        try emitter.emit(.i32_eq, 0);
        if (self.scoped_effects) {
            try emitter.emit(.local_get, frame);
            try emitter.emit(.i32_load, @offsetOf(heap.StateFrame, "kind"));
            try emitter.emit(.i32_const, heap.ScopedStateFrame.tag);
            try emitter.emit(.i32_eq, 0);
            try emitter.emit(.i32_or, 0);
        }
        try emitter.emit(.if_, 0);
        try emitter.emit(.local_get, frame);
        try emitter.emit(.i32_load, @offsetOf(heap.StateFrame, "write"));
        try emitter.operationConstant(key.operation);
        try emitter.emit(.i32_eq, 0);
        if (self.scoped_effects) {
            try emitter.operationOwnerMatch(frame, key.scoped);
            try emitter.emit(.i32_and, 0);
        }
        try emitter.emit(.br_if, 2);
        try emitter.emit(.end, 0);
        try emitter.emit(.local_get, frame);
        try emitter.emit(.i32_load, @offsetOf(provider_chain.Frame, "outer"));
        try emitter.emit(.local_set, frame);
        try emitter.emit(.br, 0);
        try emitter.emit(.end, 0);
        try emitter.emit(.end, 0);
        try emitter.emit(.local_get, frame);
        try emitter.emit(.i32_load, @offsetOf(heap.StateFrame, "kind"));
        try emitter.emit(.i32_const, heap.StateFrame.tag);
        try emitter.emit(.i32_eq, 0);
        if (self.scoped_effects) {
            try emitter.emit(.local_get, frame);
            try emitter.emit(.i32_load, @offsetOf(heap.StateFrame, "kind"));
            try emitter.emit(.i32_const, heap.ScopedStateFrame.tag);
            try emitter.emit(.i32_eq, 0);
            try emitter.emit(.i32_or, 0);
        }
        try emitter.emit(.if_, @backingInt(result_machine));
        try emitter.emit(.local_get, frame);
        try emitter.emit(.i32_load, @offsetOf(heap.StateFrame, "read"));
        try emitter.operationConstant(key.operation);
        try emitter.emit(.i32_eq, 0);
        try emitter.emit(.if_, @backingInt(result_machine));
        if (arrow.a == types.unit) {
            try emitter.emit(.local_get, frame);
            try emitter.emit(if (result_machine == .f32) .f32_load else .i32_load, @offsetOf(heap.StateFrame, "value"));
        } else try emitter.emit(.unreachable_, 0);
        try emitter.emit(.else_, 0);
        if (arrow.b == types.unit) {
            try emitter.storeTypedWord(frame, @offsetOf(heap.StateFrame, "value"), 1, self.representations.store.scalar(arrow.a) orelse .pointer, 0);
            try emitter.emit(.i32_const, 0);
        } else try emitter.emit(.unreachable_, 0);
        try emitter.emit(.end, 0);
        try emitter.emit(.else_, 0);
        try emitter.emit(.local_get, frame);
        try emitter.emit(.i32_load, @offsetOf(provider_chain.Frame, "kind"));
        try emitter.emit(.i32_const, @backingInt(provider_chain.Kind.callback));
        try emitter.emit(.i32_eq, 0);
        if (self.scoped_effects) {
            try emitter.emit(.local_get, frame);
            try emitter.emit(.i32_load, @offsetOf(provider_chain.Frame, "kind"));
            try emitter.emit(.i32_const, heap.ScopedFrame.tag);
            try emitter.emit(.i32_eq, 0);
            try emitter.emit(.i32_or, 0);
        }
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
        try self.module.emit(function_id, ir.callResult(self.layoutRole(arrow.b)));
        try emitter.emit(.call_indirect, try self.module.internType(&.{ .i32, argument_machine, .i32 }, result_machine));
        try emitter.emit(.else_, 0);
        if (self.request_owner != null) {
            try emitter.emit(.local_get, frame);
            try emitter.emit(.i32_load, @offsetOf(provider_chain.Frame, "kind"));
            try emitter.emit(.i32_const, request_runtime.request_kind);
            try emitter.emit(.i32_eq, 0);
            if (self.scoped_effects) {
                try emitter.emit(.local_get, frame);
                try emitter.emit(.i32_load, heap.offset(heap.ProviderFrame, "kind"));
                try emitter.emit(.i32_const, heap.ScopedRequestFrame.tag);
                try emitter.emit(.i32_eq, 0);
                try emitter.emit(.i32_or, 0);
            }
            try emitter.emit(.if_, @backingInt(result_machine));
            try emitter.invokeRequest(frame, 1, argument_machine, result_machine, self.layoutRole(arrow.a));
            try emitter.emit(.else_, 0);
            try emitter.emit(.unreachable_, 0);
            try emitter.emit(.end, 0);
        } else try emitter.emit(.unreachable_, 0);
        try emitter.emit(.end, 0);
        try emitter.emit(.end, 0);
        if (scope) |*actor| try actor.complete(function_id, null);
        return function_id;
    }
    fn foreignRow(self: *const Generator, row: u32, singleton: bool) bool {
        if (row == layout.unknown_row) return false;
        const view = self.representations.store.effects.view();
        const labels = view.rowLabels(row);
        if (singleton and labels.len != 1) return false;
        for (labels) |label| {
            const operation = view.operation(label);
            if (operation.instance.unit != 0 or operation.instance.decl != 0 or operation.identity.unit != 0 or operation.identity.decl != 1 or operation.arguments.len != 0) return false;
        }
        return true;
    }
    fn hostCallback(self: *const Generator, ty: layout.Id) ?wasm.Callback {
        const arrow = self.representations.store.node(ty);
        if (arrow.tag != .function or !self.foreignRow(arrow.c, true)) return null;
        const argument = self.representations.store.node(arrow.a);
        if (argument.tag == .owning) {
            if (argument.b != @backingInt(types.UsageKind.unique) or self.representations.store.node(arrow.b).tag != .unit) return null;
            const payload = self.representations.store.node(argument.a);
            if (payload.tag == .unit or payload.tag == .boolean or payload.tag == .u32 or payload.tag == .f32 or payload.tag == .array and (self.representations.store.node(payload.a).tag == .u32 or self.representations.store.node(payload.a).tag == .f32)) {
                return .{ .parameter = self.representations.store.abi(argument.a) orelse return null, .result = .unit, .cleanup = true, .owned = self.persistent_outputs };
            }
            return .{ .parameter = .u32, .result = .unit, .cleanup = true, .owned = self.persistent_outputs, .data = true, .schema = argument.a };
        }
        return .{ .parameter = self.representations.store.abi(arrow.a) orelse return null, .result = self.representations.store.abi(arrow.b) orelse return null };
    }
    fn hostFunction(self: *Generator, key: code_artifacts.HostKey) Error!u32 {
        const ty = key.ty;
        var scope: ?code_artifacts.Scope = if (self.artifacts) |context| try context.enter(.{ .host = key }) else null;
        defer if (scope) |*actor| actor.deinit();
        if (self.planning.host_functions.get(key)) |existing| {
            if (scope) |*actor| try actor.hit(existing);
            return existing;
        }
        var callback = self.hostCallback(ty) orelse return self.decline(1, .{ .start = 0, .end = 0 }, .entry_type);
        if (key.owned and !callback.cleanup) return error.InvalidFunctionReference;
        callback.owned = key.owned;
        const references = try self.module.ensureHostReferences();
        const imported = try self.module.importHostCallback(callback);
        const arrow = self.representations.store.node(ty);
        const function_id = try self.module.addTypedFunction(&.{ .i32, self.representations.store.machine(arrow.a), .i32 }, callback.result.machine(), callback.result.role());
        try self.setParameterRoles(function_id, ir.packParameterRoles(&.{ .reference, self.layoutRole(arrow.a), .reference }), 2);
        try self.callableLayout(function_id, ty);
        try self.planning.host_functions.put(self.allocator, key, function_id);
        if (scope) |*actor| try actor.reserve(function_id);
        // A scalar host stub only borrows its caller's arguments; the exact
        // generated import cannot allocate a guest reply or return an owner.
        const borrowed: ir.Ownership = .{ .kind = .scope, .chunk = 14 };
        try self.module.emit(function_id, .{ .op = .ownership, .operand = @bitCast(borrowed) });
        // Check the live descriptor identity before reading its externref handle.
        if (!callback.owned) for ([_]wasm.Instruction{
            .{ .op = .local_get, .operand = 0 }, .{ .op = .global_get, .operand = references.active },
            .{ .op = .i32_ne },                  .{ .op = .if_ },
            .{ .op = .unreachable_ },            .{ .op = .end },
            .{ .op = .local_get, .operand = 0 }, .{ .op = .i32_load, .operand = 8 },
            .{ .op = .host_ref_get },            .{ .op = .local_get, .operand = 1 },
        }) |instruction| try self.module.emit(function_id, instruction);
        if (callback.owned) {
            try self.module.emit(function_id, .{ .op = .local_get, .operand = 0 });
            try self.module.emit(function_id, .{ .op = .i32_load, .operand = heap.offset(heap.HostClosure, "handle") });
            try self.module.emit(function_id, .{ .op = .local_get, .operand = 1 });
        }
        if (callback.data) {
            const payload = try self.module.addLocal(function_id, .i32);
            try self.module.emit(function_id, .{ .op = .local_set, .operand = payload });
            try self.module.emit(function_id, .{ .op = .i32_const, .operand = callback.schema });
            try self.module.emit(function_id, .{ .op = .local_get, .operand = payload });
        }
        if (callback.cleanup) {
            var load: wasm.Op = .i32_load;
            if (callback.parameter == .f32) load = .f32_load;
            try self.module.emit(function_id, .{ .op = load, .operand = heap.offset(heap.Owning, "payload") });
        }
        try self.module.emit(function_id, .{ .op = .call_import, .operand = imported });
        if (scope) |*actor| try actor.complete(function_id, null);
        return function_id;
    }
    fn emitHostDataSchemas(self: *Generator) Error!void {
        const shapes = @import("host_cleanup_shapes.zig");
        var roots: std.ArrayList(layout.Id) = .empty;
        defer roots.deinit(self.allocator);
        for (self.module.exports.items) |item| if (item.callback) |callback| {
            if (callback.data) try roots.append(self.allocator, callback.schema);
        };
        if (roots.items.len == 0) return;
        const Context = struct {
            generator: *Generator,
            layouts: *layout.Store,
            const Physical = struct { floating: bool = false, reference: bool = false };
            pub fn physical(context: @This(), id: layout.Id, remaining: *usize, depth: usize) error{LayoutLimit}!Physical {
                if (depth >= 128 or remaining.* == 0 or id == 0 or id >= context.layouts.nodes.items.len) return error.LayoutLimit;
                remaining.* -= 1;
                const node = context.layouts.node(id);
                switch (node.tag) {
                    .unit, .boolean, .u32 => return .{},
                    .f32 => return .{ .floating = true },
                    .product, .record, .array, .list => return .{ .reference = true },
                    .nominal => {
                        if (node.a == 0 or node.a > context.generator.units.len) return error.LayoutLimit;
                        const source = context.generator.unit(node.a);
                        const definition = for (source.nominals) |candidate| {
                            if (remaining.* == 0) return error.LayoutLimit;
                            remaining.* -= 1;
                            if (candidate.identity.unit == node.a and candidate.identity.decl == node.b) break candidate;
                        } else return error.LayoutLimit;
                        if (!definition.closed_storage or definition.has_usage) return error.LayoutLimit;
                        if (!definition.is_opaque) return .{ .reference = true };
                        switch (definition.storage.kind) {
                            .unit, .boolean, .u32 => return .{},
                            .f32 => return .{ .floating = true },
                            .reference => return .{ .reference = true },
                            .parameter => {
                                const parameters = source.types.list(definition.parameters);
                                const actuals = context.layouts.children(id);
                                if (definition.storage.parameter >= parameters.len or parameters.len != actuals.len) return error.LayoutLimit;
                                var ordinal: u32 = 0;
                                const selected = try context.selectParameter(source, parameters[definition.storage.parameter], actuals[definition.storage.parameter], definition.storage.selector, &ordinal, remaining, depth + 1) orelse return error.LayoutLimit;
                                return context.physical(selected, remaining, depth + 1);
                            },
                            .unknown => return error.LayoutLimit,
                        }
                    },
                    else => return error.LayoutLimit,
                }
            }
            fn selectParameter(context: @This(), source: *const core.Module, parameter: u32, actual: layout.Id, target: u32, ordinal: *u32, remaining: *usize, depth: usize) error{LayoutLimit}!?layout.Id {
                if (depth >= 128 or remaining.* == 0 or parameter == 0 or parameter >= source.types.nodes.len or actual == 0 or actual >= context.layouts.nodes.items.len) return error.LayoutLimit;
                remaining.* -= 1;
                const node = source.types.node(parameter);
                if (node.tag == .variable) {
                    const selected = ordinal.*;
                    ordinal.* += 1;
                    if (selected == target) return actual;
                    return null;
                }
                const supplied = context.layouts.node(actual);
                if (node.tag == .product and supplied.tag == .product and node.b == supplied.b) {
                    for (source.types.list(.{ .start = node.a, .len = node.b }), context.layouts.children(actual)) |child, argument| {
                        if (try context.selectParameter(source, child, argument, target, ordinal, remaining, depth + 1)) |selected| return selected;
                    }
                } else if (node.tag == .record and supplied.tag == .record) {
                    const fields = context.layouts.children(actual);
                    for (0..node.b) |index| {
                        const field = source.types.recordField(node, index);
                        for (0..fields.len / 2) |slot| {
                            if (remaining.* == 0) return error.LayoutLimit;
                            remaining.* -= 1;
                            if (fields[slot * 2] != field.name) continue;
                            if (try context.selectParameter(source, field.ty, fields[slot * 2 + 1], target, ordinal, remaining, depth + 1)) |selected| return selected;
                            break;
                        }
                    }
                }
                return null;
            }
            pub fn rowWords(context: @This(), id: layout.Id, _: *usize, _: usize) Allocator.Error!u32 {
                return context.generator.rowWords(id);
            }
            pub fn nominal(context: @This(), id: layout.Id, remaining: *usize) (Allocator.Error || error{LayoutLimit})!shapes.Facts {
                const g = context.generator;
                const node = context.layouts.node(id);
                if (node.a == 0 or node.a > g.units.len) return error.LayoutLimit;
                const source = g.unit(node.a);
                const definition = for (source.nominals) |definition| {
                    if (remaining.* == 0) return error.LayoutLimit;
                    remaining.* -= 1;
                    if (definition.identity.unit == node.a and definition.identity.decl == node.b) break definition;
                } else return error.LayoutLimit;
                if (!definition.closed_storage or definition.has_usage or context.layouts.children(id).len != definition.parameters.len) return error.LayoutLimit;
                const hidden = definition.is_opaque or definition.private;
                var variants: std.ArrayList(shapes.Variant) = .empty;
                errdefer variants.deinit(g.allocator);
                var mappings: std.ArrayList(Mapping) = .empty;
                defer mappings.deinit(g.allocator);
                for (source.types.list(definition.parameters), context.layouts.children(id)) |parameter, actual| {
                    try shapeTypeWork(source, parameter, remaining, 0);
                    g.mapType(node.a, &mappings, parameter, actual, .{ .start = 0, .end = 0 }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.LayoutLimit;
                }
                if (hidden) return .{ .name = source.name(definition.diagnostic_name), .hidden = true, .variants = &.{} };
                for (source.constructors) |constructor| {
                    if (remaining.* == 0) return error.LayoutLimit;
                    remaining.* -= 1;
                    if (!std.meta.eql(source.nominal(constructor.nominal).identity, definition.identity)) continue;
                    try shapeTypeWork(source, constructor.payload, remaining, 0);
                    const child = g.codeLayoutWithRows(node.a, constructor.payload, mappings.items, &.{}, .{ .start = 0, .end = 0 }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.LayoutLimit;
                    try variants.append(g.allocator, .{ .tag = constructor.tag, .child = child });
                }
                return .{ .name = source.name(definition.diagnostic_name), .hidden = false, .variants = try variants.toOwnedSlice(g.allocator) };
            }
        };
        const bytes = shapes.build(self.allocator, Context{ .generator = self, .layouts = &self.representations.store }, roots.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else self.decline(1, .{ .start = 0, .end = 0 }, .complexity);
        defer self.allocator.free(bytes);
        try self.module.setCleanupDataMetadata(bytes);
    }
    fn ownerRuntime(self: *Generator) Error!@import("../runtime/public_owners.zig").Runtime {
        if (self.public_owners) |runtime| return runtime;
        const runtime = try @import("../runtime/public_owners.zig").emit(&self.module);
        try self.module.exportOwnerFunction(runtime.release, "blot:owner_release", .u32, .unit, false, null, null, true);
        try self.module.exportOwnerFunction(runtime.token, "blot:owner_token", .u32, .u32, false, null, null, true);
        self.public_owners = runtime;
        return runtime;
    }
    fn ownerBoundary(self: *const Generator, ty: layout.Id) ?wasm.OwnerBoundary {
        const node = self.representations.store.node(ty);
        if (node.tag != .owning) return null;
        var kind: @FieldType(wasm.OwnerBoundary, "kind") = .unique;
        if (node.b == @backingInt(types.UsageKind.shared)) kind = .shared;
        return .{ .schema = node.a, .kind = kind };
    }
    fn freshOwnerInput(self: *const Generator, ty: layout.Id) ?Scalar {
        const payload = self.representations.store.node(ty);
        switch (payload.tag) {
            .unit, .boolean, .u32, .f32 => return self.representations.store.abi(ty),
            .array => switch (self.representations.store.node(payload.a).tag) {
                .u32, .f32 => return self.representations.store.abi(ty),
                else => return null,
            },
            else => return null,
        }
    }
    fn publishOwner(self: *Generator, emitter: *Emitter, owner: wasm.OwnerBoundary) Error!void {
        const runtime = try self.ownerRuntime();
        try emitter.emit(.i32_const, owner.schema);
        try emitter.emit(.i32_const, @backingInt(owner.kind));
        try emitter.emit(.call, runtime.publish);
    }
    fn onceEntry(self: *Generator, wrapper: u32, guard: ?u32) Error!void {
        const consumed = guard orelse return;
        // Consume before invoking user code, allocating arguments or resetting
        // an active callback. Raw Wasm callers cannot bypass this obligation.
        for ([_]wasm.Instruction{
            .{ .op = .global_get, .operand = consumed }, .{ .op = .if_ },
            .{ .op = .unreachable_ },                    .{ .op = .end },
            .{ .op = .i32_const, .operand = 1 },         .{ .op = .global_set, .operand = consumed },
        }) |instruction| try self.module.emit(wrapper, instruction);
    }
    fn hostDescriptor(self: *Generator, emitter: *Emitter, stub: u32, handle: u32) Error!u32 {
        _ = self;
        const descriptor = try emitter.allocate(@sizeOf(heap.HostClosure), .heap(heap.HostClosure));
        try emitter.emit(.local_get, descriptor);
        try emitter.referenceConstant(stub, .table_function);
        try emitter.emit(.i32_store, 0);
        try emitter.emit(.local_get, descriptor);
        try emitter.emit(.local_get, descriptor);
        const identity = ir.selfIdentityStore();
        try emitter.emit(identity.op, identity.operand);
        try emitter.emit(.i32_store, 4);
        try emitter.emit(.local_get, descriptor);
        try emitter.emit(.local_get, handle);
        try emitter.emit(.i32_store, heap.offset(heap.HostClosure, "handle"));
        return descriptor;
    }
    fn entryCallbackFunction(self: *Generator, target: u32, parameter: layout.Id, result: Scalar, guard: ?u32, output: ?wasm.OwnerBoundary) Error!u32 {
        const callback = self.hostCallback(parameter) orelse return error.InvalidFunctionReference;
        const stub = try self.hostFunction(.{ .ty = parameter, .owned = callback.owned });
        const arena = try self.module.ensureArena();
        const references = try self.module.ensureHostReferences();
        const wrapper = try self.module.addTypedFunction(&.{.externref}, result.machine(), result.role());
        try self.onceEntry(wrapper, guard);
        var emitter: Emitter = .{ .generator = self, .unit_id = 1, .function_id = wrapper, .mappings = &.{} };
        defer emitter.deinit();
        const confined = @import("host_entry.zig").confined(&self.module, target, stub, parameter, self.request_owner);
        var previous: ?u32 = null;
        if (confined) {
            previous = try emitter.temporary(.i32);
            try emitter.emit(.global_get, references.active);
            try emitter.emit(.local_set, previous.?);
        }
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
        if (callback.owned) {
            if (callback.data) try emitter.emit(.i32_const, callback.schema);
            try emitter.emit(.call_import, try self.module.importOwnedCleanupBind(callback));
        } else try emitter.emit(.call, references.retain);
        try emitter.emit(.local_set, handle);
        // The environment word is a borrowed identity token for this same
        // descriptor. A retained descriptor cannot alias a later allocation.
        var descriptor: u32 = undefined;
        if (confined) {
            descriptor = try emitter.temporary(.i32);
            try emitter.emit(.local_get, previous.?);
            try emitter.emit(.if_, 0);
            const nested = try self.hostDescriptor(&emitter, stub, handle);
            try emitter.emit(.local_get, nested);
            try emitter.emit(.local_set, descriptor);
            try emitter.emit(.else_, 0);
            // The exact executable callback formal stays within this call.
            // Invocation revocation still precedes every subsequent binding.
            const address: u32 = @intCast(self.module.data.items.len);
            _ = try self.module.dataObject(heap.HostClosure{ .function = stub, .environment = address, .handle = 0 });
            try self.module.dataReference(address, .{ .role = .callable_function, .value = stub });
            try self.module.dataReference(address + 4, .{ .role = .static_address, .value = address });
            try emitter.emit(.local_get, handle);
            try emitter.emit(.if_, 0);
            try emitter.emit(.unreachable_, 0);
            try emitter.emit(.end, 0);
            try emitter.referenceConstant(address, .static_address);
            try emitter.emit(.local_set, descriptor);
            // A forged descriptor cannot silently bind another code endpoint,
            // borrowed identity or externref slot on a later invocation.
            inline for (.{ 0, 4, 8 }) |offset| {
                try emitter.emit(.local_get, descriptor);
                try emitter.emit(.i32_load, offset);
                if (offset == 0) try emitter.referenceConstant(stub, .table_function) else if (offset == 4) try emitter.referenceConstant(address, .static_address) else try emitter.emit(.i32_const, 0);
                try emitter.emit(.i32_ne, 0);
                try emitter.emit(.if_, 0);
                try emitter.emit(.unreachable_, 0);
                try emitter.emit(.end, 0);
            }
            try emitter.emit(.end, 0);
        } else descriptor = try self.hostDescriptor(&emitter, stub, handle);
        try emitter.emit(.local_get, descriptor);
        try emitter.emit(.global_set, references.active);
        try emitter.emit(.local_get, descriptor);
        try emitter.emit(.i32_const, 0);
        try emitter.emit(.call, target);
        if (output) |owner| try self.publishOwner(&emitter, owner);
        const saved = try emitter.temporary(result.machine());
        try emitter.emit(.local_set, saved);
        try emitter.emit(.i32_const, 0);
        try emitter.emit(.call, references.release);
        try emitter.emit(.local_get, saved);
        return wrapper;
    }
    fn entryFunction(self: *Generator, target: u32, parameter: Scalar, result: Scalar, owning: ?layout.Id, guard: ?u32, input: ?wasm.OwnerBoundary, output: ?wasm.OwnerBoundary, leased: bool) Error!u32 {
        const wrapper = try self.module.addTypedFunction(&.{parameter.machine()}, result.machine(), result.role());
        try self.setParameterRoles(wrapper, ir.packParameterRoles(&.{parameter.role()}), null);
        try self.onceEntry(wrapper, guard);
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
        var emitter: Emitter = .{ .generator = self, .unit_id = 1, .function_id = wrapper, .mappings = &.{} };
        defer emitter.deinit();
        try emitter.emit(.local_get, 0);
        if (leased) {
            const owner = input orelse unreachable;
            const runtime = try self.ownerRuntime();
            try emitter.emit(.i32_const, owner.schema);
            try emitter.emit(.i32_const, @backingInt(owner.kind));
            try emitter.emit(.i32_const, @intFromBool(owner.kind == .unique));
            try emitter.emit(.call, runtime.take);
        } else if (owning) |payload| try emitter.boxOwner(payload);
        try emitter.emit(.i32_const, 0);
        try emitter.emit(.call, target);
        if (output) |owner| try self.publishOwner(&emitter, owner);
        return wrapper;
    }
};

fn ownershipRejection(allocator: Allocator, location: Diagnostic, rejection: wasm.OwnershipFailure) Allocator.Error!Result {
    const reason = switch (rejection.fallback) {
        .none => "ownership roots are unavailable",
        .no_arena => "the module has no allocation arena",
        .public_arena => "a public arena has no checked ownership roots",
        .host_references => "host references have no checked ownership roots",
        .imports => "imports have no checked ownership roots",
        .initializer => "the initializer has no checked ownership roots",
        .static_sequence_cache => "static sequence storage has no complete ownership proof",
        .unproven_body => "the function body has no complete allocation and exit proof",
    };
    var message: []u8 = undefined;
    if (rejection.function) |function| {
        message = try allocator.print("{s} (function {d}; {s}: {s})", .{ Code.ownership_unproved.message(""), function, @tagName(rejection.fallback), reason });
    } else {
        message = try allocator.print("{s} (module; {s}: {s})", .{ Code.ownership_unproved.message(""), @tagName(rejection.fallback), reason });
    }
    var diagnostic_ = location;
    diagnostic_.ownership = rejection;
    diagnostic_.detail = message;
    return .{ .diagnostic = diagnostic_, .owned_message = message };
}

test "ownership rejection owns function and fallback diagnostics after module teardown" {
    const allocator = std.testing.allocator;
    var result = try ownershipRejection(allocator, .{ .unit = 2, .span = .{ .start = 17, .end = 41 }, .code = .ownership_unproved }, .{ .function = 73, .fallback = .unproven_body });
    defer result.deinit(allocator);
    const diagnostic_ = result.diagnostic.?;
    try std.testing.expectEqual(@as(u32, 2), diagnostic_.unit);
    try std.testing.expectEqual(core.Span{ .start = 17, .end = 41 }, diagnostic_.span);
    try std.testing.expectEqual(@as(?u32, 73), diagnostic_.ownership.?.function);
    try std.testing.expectEqual(wasm.OwnershipFallback.unproven_body, diagnostic_.ownership.?.fallback);
    try std.testing.expect(std.mem.find(u8, diagnostic_.message(), "function 73; unproven_body") != null);
    try std.testing.expectEqualStrings(result.owned_message, diagnostic_.message());
    var module = try ownershipRejection(allocator, .{ .unit = 1, .span = .{ .start = 0, .end = 0 }, .code = .ownership_unproved }, .{ .fallback = .imports });
    defer module.deinit(allocator);
    try std.testing.expect(std.mem.find(u8, module.diagnostic.?.message(), "module; imports") != null);
}

pub fn compile(allocator: Allocator, units: []const core.Module, entry: u32) Error!Result {
    return compileWithOptions(allocator, units, entry, .{ .artifact_replay = default_artifact_replay, .artifact_dump = default_artifact_replay });
}

const default_artifact_replay = if (@hasDecl(@import("root"), "compiler_defaults")) @import("root").compiler_defaults.artifact_replay else false;
pub const CompileOptions = struct {
    /// Private ABI inspection control; avoids hiding callees through inlining.
    inline_named: bool = true,
    /// Collect bounded explanations; code is regenerated to observe every site.
    explain_demands: bool = false,
    explain_allocations: bool = false,
    /// Private differential/qualification controls, never source language limits.
    ragged_builders: bool = true,
    constant_receipts: bool = true,
    /// Private differential laws for the existing evaluator limits.
    constant_limits: struct { steps: ?usize = null, values: ?usize = null, children: ?usize = null, depth: ?usize = null, calls: ?usize = null } = .{},
    ragged_probe_limit: u32 = ragged_builder.probe_limit,
    checkpoint: ?*const @import("backend_checkpoint.zig").Checkpoint = null,
    io: ?std.Io = null,
    /// Detailed hot-region clocks are opt-in; broad phase timing stays cheap.
    profile_backend: bool = false,
    policy: @import("../execution_policy.zig").Policy = .{},
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
    /// Opt-in integrity validation: captured pins carry their Core digest, and
    /// a later revision recomputes it before trusting a retained pin. Tokens
    /// alone decide reuse otherwise; the decisions are the same either way.
    validate_pins: bool = false,
};

pub fn compileWithIdentity(allocator: Allocator, units: []const core.Module, entry: u32, names: runtime_identity.View) Error!Result {
    return compileWithOptions(allocator, units, entry, .{ .identity = names, .artifact_replay = default_artifact_replay, .artifact_dump = default_artifact_replay });
}

/// Private differential hook: irrelevant semantic proofs must not select tags.
pub fn compileWithEvidenceNoise(allocator: Allocator, units: []const core.Module, entry: u32, noise: bool) Error!Result {
    return compileWithOptions(allocator, units, entry, .{ .evidence_noise = noise });
}

pub fn compileWithOptions(allocator: Allocator, units: []const core.Module, entry: u32, options: CompileOptions) Error!Result {
    return compileLocals(allocator, units, entry, options, true) catch |err| {
        if (err != error.SpeculativeLocalRetry) return @errorCast(err);
        // A promoted generalized local could not serve one of its uses, or
        // the program fails anyway. The fresh attempt keeps every such local
        // on its ordinary runtime path and owns the reported outcome.
        return @errorCast(compileLocals(allocator, units, entry, options, false));
    };
}
fn compileLocals(allocator: Allocator, units: []const core.Module, entry: u32, options: CompileOptions, speculative: bool) (Error || error{SpeculativeLocalRetry})!Result {
    return compileAttempt(allocator, units, entry, options, false, speculative) catch |err| {
        if (err != error.ConstantReceiptRetry) return @errorCast(err);
        std.debug.assert(options.constant_receipts);
        // compileAttempt has destroyed every mutable owner before retrying.
        // Ordinary recording remains enabled for the next revision; only
        // partial receipt reuse is disabled during this fresh attempt.
        var result = compileAttempt(allocator, units, entry, options, true, speculative) catch |retry_error| {
            std.debug.assert(retry_error != error.ConstantReceiptRetry);
            return @errorCast(retry_error);
        };
        result.constant_receipts.retries = 1;
        return result;
    };
}
// One compilation attempt owns its mutable compiler, admission and capture
// state. Callback and bridge borrows bind in prepare after the caller places
// this owner; replay explicitly retires the generator before materialization.
const CompileRun = struct {
    allocator: Allocator,
    units: []const core.Module,
    entry: u32,
    options: CompileOptions,
    clock: @import("backend_timing.zig").Clock = undefined,
    timing: @import("backend_timing.zig").Stats = .{},
    recording: bool = false,
    speculative_locals: bool = true,
    module_stamps: code_artifacts.ModuleStamps = undefined,
    stamps_alive: bool = false,
    stamps: ?*code_artifacts.ModuleStamps = null,
    journal: artifact_emitter.Recorder = undefined,
    journal_alive: bool = false,
    metadata: code_artifacts.Context = undefined,
    metadata_alive: bool = false,
    generator: Generator = undefined,
    generator_alive: bool = false,
    retained: ?artifact_fragment.State = null,
    principal_state: ?principal_evidence_reuse.State = null,
    persisted_principals: ?@import("../reuse/principal_archive.zig").Reader = null,
    query_state: ?completed_specialization_query.State = null,
    constant_state: ?@import("../reuse/constant_receipt_reuse.zig").State = null,
    candidate: ?@import("region_candidate.zig").Extension = null,
    /// Four-lane worker view over the assembled module; it borrows bodies
    /// from `candidate` or the generator's module.
    vectors: ?@import("simd_abi.zig").View = null,
    optimized: ?@import("optimized_bodies.zig").Capture = null,
    fn deinit(self: *CompileRun) void {
        if (self.optimized) |*owner| owner.deinit();
        if (self.vectors) |*owner| owner.deinit();
        if (self.candidate) |*owner| owner.deinit();
        if (self.constant_state) |*state| state.deinit();
        if (self.query_state) |*state| state.deinit();
        if (self.persisted_principals) |*state| state.deinit();
        if (self.principal_state) |*state| state.deinit();
        if (self.retained) |*state| state.deinit();
        if (self.generator_alive) self.generator.deinit();
        if (self.metadata_alive) self.metadata.deinit();
        if (self.journal_alive) self.journal.deinit();
        if (self.stamps_alive) self.module_stamps.deinit();
    }
    fn prepare(self: *CompileRun, skip_constant_replay: bool) (Error || error{ConstantReceiptRetry})!void {
        self.clock = @import("backend_timing.zig").Clock.init(self.options.io);
        self.timing = .{};
        if (self.options.identity) |names| {
            // Project emission requires a complete dense owner view; Core-only
            // callers cannot accidentally publish a project-domain fragment.
            if (names.owners.len != self.units.len) return error.InvalidFunctionReference;
            for (self.units, 0..) |*unit, index| {
                if (unit.unit != index + 1 or names.owner(unit.unit) == null) return error.InvalidFunctionReference;
            }
        }
        self.recording = self.options.artifact_replay or self.options.retain_artifacts or self.options.previous != null or self.options.query_previous != null;
        // A restarted process may supply the persisted semantic owner. The same
        // Gate, Importer and graph Plan admission run against it; an in-process
        // previous revision always takes precedence.
        const query_previous = self.options.query_previous orelse self.options.previous orelse if (self.options.checkpoint) |checkpoint| (if (checkpoint.semantic) |*owner| &owner.capture else null) else null;
        self.module_stamps = .{ .allocator = self.allocator, .current = self.units, .previous = if (query_previous) |old| if (old.metadata.pools) |*pools| pools else null else null, .compare_contents = true, .validate = self.options.validate_pins };
        self.stamps_alive = true;
        self.stamps = if (self.module_stamps.previous != null) &self.module_stamps else null;
        self.journal = artifact_emitter.Recorder.init(self.allocator);
        self.journal_alive = true;
        self.metadata = code_artifacts.Context.init(self.allocator);
        self.metadata_alive = true;
        if (self.recording) {
            self.journal.owner = &self.metadata.active_job;
            self.journal.clock = &self.metadata.clock;
        }
        self.generator = try Generator.init(self.allocator, self.units, if (self.recording) &self.journal else null);
        self.generator.inline_named = self.options.inline_named;
        self.generator.speculative_locals = self.speculative_locals;
        if (self.options.constant_limits.steps) |limit| self.generator.evaluator.options.max_steps = limit;
        if (self.options.constant_limits.values) |limit| self.generator.evaluator.options.max_values = limit;
        if (self.options.constant_limits.children) |limit| self.generator.evaluator.options.max_children = limit;
        if (self.options.constant_limits.depth) |limit| self.generator.evaluator.options.max_depth = limit;
        if (self.options.constant_limits.calls) |limit| self.generator.evaluator.options.max_call_depth = limit;
        self.generator.demand_lowering.enabled = self.options.explain_demands;
        self.generator.ragged_probe_limit = self.options.ragged_probe_limit;
        if (!self.options.ragged_builders) self.generator.ragged_probe_limit = 0;
        self.generator.evaluator.ragged_probe_limit = self.generator.ragged_probe_limit;
        self.generator.work_timing.clock = .init(if (self.options.profile_backend) self.options.io else null);
        self.generator.evaluator.timing = if (self.options.profile_backend) &self.generator.work_timing else null;
        // The replay gate destroys all mutable compiler state before materialization.
        if (self.recording) self.generator.artifacts = &self.metadata;
        self.generator.demand_owner = &self.metadata;
        self.generator.refinement_owner = &self.metadata;
        self.generator_alive = true;
        self.generator.evaluator.diagnostic_context = .{ .identity = self.options.identity, .entry = self.entry, .prelude = self.options.diagnostic_prelude_unit, .source_mode = self.options.diagnostic_source_mode };
        self.generator.planning.startup_facts.enabled = self.options.observe_startup;
        if (self.options.identity) |names| self.generator.planning.runtime_operations = runtime_operations.Store.initProject(self.allocator, names);
        if (self.recording) self.generator.planning.runtime_operations.artifacts = &self.journal;
        try self.prepareReuse(skip_constant_replay);
        if (self.options.evidence_noise) {
            for (0..7) |index| _ = self.generator.evaluator.storage.evidence.effects.internOperation(.{ .unit = std.math.maxInt(u32), .decl = @intCast(9000 + index) }, &.{types.f32_type}) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.ModuleTooLarge;
        }
        self.timing.prepare_us = self.clock.lap();
    }
    fn prepareReuse(self: *CompileRun, skip_constant_replay: bool) Error!void {
        const principal_previous = self.options.principal_previous orelse self.options.previous;
        const query_previous = self.options.query_previous orelse self.options.previous orelse if (self.options.checkpoint) |checkpoint| (if (checkpoint.semantic) |*owner| &owner.capture else null) else null;
        if (if (self.options.explain_demands) null else self.options.previous) |previous| {
            if (previous.emission.sealed and previous.metadata.pools != null) {
                self.retained = try artifact_fragment.State.initWithStamps(self.allocator, previous, self.units, self.options.identity, self.options.cached_units, self.stamps);
                self.generator.retained = &self.retained.?;
                if (self.retained.?.importer.code_gate) |*gate| try @import("demand_summary.zig").retain(self.allocator, &self.metadata.demand_summaries, &previous.metadata.demand_summaries, gate, &self.generator.evaluator.counters);
            }
        }
        self.persisted_principals = if (self.options.checkpoint) |checkpoint| .{ .allocator = self.allocator, .archive = &checkpoint.principal, .units = self.units, .names = self.options.identity } else null;
        if (self.options.retain_artifacts or self.options.previous != null or self.options.checkpoint != null) {
            if (self.persisted_principals) |*reader| self.generator.persisted_principals = reader;
            if (principal_previous) |previous| if (previous.emission.sealed and previous.metadata.pools != null) {
                // Executable admission already checked this semantic source pair.
                // Clone only under identical admission options and owner pairing;
                // code still needs its separate exact body/value checks. Repeating
                // the whole dependency validation here would tax every small edit.
                if (self.retained) |*state| if (state.importer.code_gate) |*checked| {
                    if (shared_query_gate.share(self.allocator, &previous.metadata.pools.?, self.units, &checked.semantic)) |admission| {
                        self.principal_state = .{ .allocator = self.allocator, .old = previous, .gate = admission, .names = self.options.identity };
                    }
                };
                if (self.principal_state == null) self.principal_state = try principal_evidence_reuse.State.init(self.allocator, previous, self.units, self.options.identity, self.stamps);
                self.generator.principal_state = &self.principal_state.?;
            };
            // Bind callbacks only after the Generator reaches its stable stack address.
            self.generator.evaluator.principal_provider = .{ .context = &self.generator, .lookup = Generator.principalLookup, .record = Generator.principalRecord };
        }
        self.generator.evaluator.retain_specialization_receipts = self.recording;
        self.generator.evaluator.retain_constant_receipts = self.recording and self.options.constant_receipts;
        if (query_previous) |previous| if (previous.metadata.pools != null) {
            // Both States are prepared here from this compile's same immutable
            // source pair and identity. A new namespace is never admitted by a
            // lease.
            if (self.principal_state) |*principal| {
                if (shared_query_gate.share(self.allocator, &previous.metadata.pools.?, self.units, &principal.gate)) |gate| {
                    self.query_state = .{ .allocator = self.allocator, .old = previous, .graph_scratch = .{ .allocator = self.allocator }, .gate = gate };
                    self.query_state.?.stats.shared_gates = 1;
                    self.query_state.?.stats.shared_gate_bytes = shared_query_gate.validationBytes(&self.query_state.?.gate);
                }
            }
            if (self.query_state == null) {
                // Initialize the Gate before the optional: a failed initializer
                // inside the literal would leave a non-null, partial query state.
                const gate = try @import("../reuse/principal_reuse_gate.zig").Gate.initWithStamps(self.allocator, &previous.metadata.pools.?, self.units, self.options.identity, self.stamps);
                self.query_state = .{ .allocator = self.allocator, .old = previous, .graph_scratch = .{ .allocator = self.allocator }, .gate = gate };
                self.query_state.?.stats.gate_fresh = 1;
            }
            self.query_state.?.io = self.options.io;
            self.query_state.?.semantic_workers = self.options.policy.semantic_workers;
            self.generator.query_state = &self.query_state.?;
            self.generator.evaluator.specialization_provider = .{ .context = &self.generator, .lookup = Generator.completedQueryLookup, .member = Generator.completedMemberLookup };
        };
        if (self.options.constant_receipts and !skip_constant_replay) if (self.query_state) |*state| {
            const pools = &state.old.metadata.pools.?;
            if (@import("../reuse/constant_receipt.zig").hasProductiveRecord(pools.constant_records, self.generator.evaluator.minimum_constant_steps)) {
                var gate = state.gate.retain();
                if (!gate.enabled) {
                    gate.deinit();
                    gate = try @import("../reuse/principal_reuse_gate.zig").Gate.initConstantReceipts(self.allocator, pools, self.units, self.options.identity, self.stamps);
                }
                self.constant_state = .{ .allocator = self.allocator, .old = pools, .gate = gate };
                self.generator.constant_state = &self.constant_state.?;
                self.generator.evaluator.constant_provider = .{ .context = &self.generator, .lookup = Generator.constantLookup };
            }
        };
    }
    fn emit(self: *CompileRun) (Error || error{ConstantReceiptRetry})!?Result {
        self.generator.evaluator.semantic_io = self.options.io;
        self.generator.evaluator.semantic_component_workers = if (self.options.policy.semantic_components or self.options.policy.semantic_workers > 1) self.options.policy.semantic_workers else 0;
        generate(&self.generator, self.entry, self.options.unit_order) catch |err| {
            if (err != error.OutOfMemory and self.generator.evaluator.constant_receipt_retry) return error.ConstantReceiptRetry;
            switch (err) {
                error.Declined => {
                    var diagnostic_ = self.generator.diagnostic;
                    const detail = if (diagnostic_) |item| item.detail else &.{};
                    const owned_message = try self.allocator.dupe(u8, detail);
                    if (diagnostic_) |*item| item.detail = owned_message;
                    errdefer self.allocator.free(owned_message);
                    var explanation: ?dispatch_explanation.Explanation = null;
                    if (diagnostic_) |item| {
                        if (item.implementation_trace) |trace| {
                            explanation = try self.generator.explainImplementation(trace);
                        } else if (item.dispatch) |record| explanation = try self.generator.explainDispatch(record);
                    }
                    errdefer if (explanation) |value| value.deinit(self.allocator);
                    return .{ .counters = self.generator.evaluator.counters, .principal = self.generator.principalStats(), .diagnostic = diagnostic_, .owned_message = owned_message, .explanation = explanation, .startup_observation = if (self.options.observe_startup) try self.generator.planning.startup_facts.capture(self.allocator, &self.generator.module) else null, .code_instances = self.generator.planning.codeCount(self.generator.static_data.closures.items.len), .callable_wrappers = self.generator.planning.wrapperCount(), .emitted_functions = self.generator.module.functions.items.len, .constant_steps = self.generator.evaluator.steps, .constant_receipts = self.generator.evaluator.constant_stats };
                },
                else => return err,
            }
        };
        if (self.generator.evaluator.constant_receipt_retry) return error.ConstantReceiptRetry;
        self.timing.generate_us = self.clock.lap();
        try self.generator.planning.initializeRuntime(&self.generator);
        if (self.recording) try self.journal.captureOperations(self.generator.planning.runtime_operations.entries.items);
        self.generator.planning.runtime_operations.finish(&self.generator.module) catch |err| switch (err) {
            error.InvalidOperation => return error.InvalidFunctionReference,
            error.OutOfMemory => return error.OutOfMemory,
            error.ModuleTooLarge => return error.ModuleTooLarge,
        };
        try self.generator.module.prepareCycles();
        self.timing.initialize_us = self.clock.lap();
        return null;
    }
    fn assemble(self: *CompileRun) Error!Result {
        if (@import("cohort_candidate.zig").possible(&self.generator.module)) {
            const view = try @import("activation_model.zig").Borrowed.init(self.allocator, &self.generator, self.options.identity);
            defer view.deinit(self.allocator);
            self.candidate = try @import("region_candidate.zig").prepare(self.allocator, &self.generator.module, view.model());
        }
        var assembled_module: *const wasm.Module = &self.generator.module;
        if (self.candidate) |*owned| assembled_module = &owned.view.module;
        // Scalar replacement removes the boxes the worker view introduces;
        // the development tier keeps the boxed ABI.
        if (self.options.policy.codegen_tier == .optimized) self.vectors = try @import("simd_abi.zig").prepare(self.allocator, assembled_module);
        if (self.vectors) |*owned| assembled_module = &owned.module;
        self.optimized = if (self.options.retain_artifacts) .{ .allocator = self.allocator } else null;
        var runtime_optimization: @import("optimized_bodies.zig").Stats = .{};
        const retained_optimized = if (self.options.previous) |previous| if (previous.optimized) |*owned| owned else null else null;
        const checkpoint_optimized = if (self.options.checkpoint) |checkpoint| if (checkpoint.optimizer) |*owned| owned else null else null;
        const optimized_previous = retained_optimized orelse checkpoint_optimized;
        var rejection: wasm.OwnershipFailure = .{};
        const emitted = assembled_module.assembleCheckedWithOptions(.{ .rejection = &rejection, .io = self.options.io, .workers = self.options.policy.codegen_workers, .tier = self.options.policy.codegen_tier, .share_machine_code = self.options.policy.share_machine_code, .previous = optimized_previous, .current = if (self.optimized) |*owned| owned else null, .stats = &runtime_optimization }) catch |err| switch (err) {
            error.IncompleteOwnership => {
                var location: Diagnostic = .{ .unit = self.entry, .span = .{ .start = 0, .end = 0 }, .code = .ownership_unproved };
                if (rejection.function) |failed| {
                    var instances = self.generator.planning.instances.iterator();
                    while (instances.next()) |instance| if (instance.value_ptr.* == failed) {
                        const target = instance.key_ptr.target;
                        location.unit = target.unit;
                        location.span = self.generator.unit(target.unit).binding(target.binding).span;
                        break;
                    };
                }
                if (rejection.function) |failed| {
                    // Captured templates and closures do not live in named instances.
                    if (location.span.end == 0) {
                        var templates = self.generator.planning.template_instances.iterator();
                        while (templates.next()) |instance| if (instance.value_ptr.* == failed) {
                            location.unit = instance.key_ptr.unit;
                            location.span = self.generator.unit(location.unit).span(instance.key_ptr.node);
                            break;
                        };
                    }
                    if (location.span.end == 0) {
                        var closures = self.generator.planning.closures.iterator();
                        while (closures.next()) |instance| if (instance.value_ptr.* == failed) {
                            location.unit = instance.key_ptr.unit;
                            location.span = self.generator.unit(location.unit).span(self.generator.unit(location.unit).closures[instance.key_ptr.catalog].body);
                            break;
                        };
                    }
                }
                if (location.span.end == 0) {
                    // Unmapped generated code points to its public build boundary.
                    location.unit = self.entry;
                    for (self.generator.unit(self.entry).bodies[1..]) |body| if (body.exported) {
                        location.span = self.generator.unit(self.entry).binding(body.binding).span;
                        break;
                    };
                }
                var failure = try ownershipRejection(self.allocator, location, rejection);
                failure.counters = self.generator.evaluator.counters;
                failure.constant_steps = self.generator.evaluator.steps;
                return failure;
            },
            error.OutOfMemory => return error.OutOfMemory,
            error.ModuleTooLarge => return error.ModuleTooLarge,
            error.InvalidGlobalReference => return error.InvalidGlobalReference,
            else => return error.InvalidFunctionReference,
        };
        return Result{ .runtime_optimization = runtime_optimization, .bytes = emitted, .code_instances = self.generator.planning.codeCount(self.generator.static_data.closures.items.len), .callable_wrappers = self.generator.planning.wrapperCount(), .emitted_functions = assembled_module.functions.items.len, .constant_steps = self.generator.evaluator.steps, .constant_receipts = self.generator.evaluator.constant_stats };
    }
    fn observe(self: *CompileRun, result: *Result) Error!void {
        // A retained Gate lease zeros its work counters. Sum original gates once,
        // keeping validation work separate from principal-query hits/misses.
        if (self.retained) |*state| if (state.importer.code_gate) |*checked| result.source_validation.observe(&checked.semantic);
        if (self.principal_state) |*state| result.source_validation.observe(&state.gate);
        if (self.query_state) |*state| result.source_validation.observe(&state.gate);
        result.emitted_functions -= result.runtime_optimization.shared;
        self.timing.assemble_us = self.clock.lap();
        self.timing.profiled = self.options.profile_backend;
        if (self.options.profile_backend) self.timing.work = self.generator.work_timing.snapshot();
        result.optimization = self.generator.planning.facts.stats;
        result.optimization.region_requests = self.generator.evaluator.regions.region_arena_pool.stats.requested;
        result.optimization.region_reused = self.generator.evaluator.regions.region_arena_pool.stats.reused;
        result.optimization.region_retained_bytes = self.generator.evaluator.regions.region_arena_pool.stats.retained_bytes;
        result.optimization.evidence_import_requests = self.generator.evaluator.evidence_import_requests;
        result.optimization.evidence_import_reused = self.generator.evaluator.evidence_import_reused;
        result.optimization.closed_source_imports = self.generator.evaluator.closed_source_imports;
        result.optimization.closed_source_reused = self.generator.evaluator.closed_source_reused;
        result.optimization.split_attempts = self.generator.evaluator.split_attempts;
        result.optimization.split_accepted = self.generator.evaluator.split_accepted;
        result.optimization.split_declined = self.generator.evaluator.split_declined;
        result.counters = self.generator.evaluator.counters;
        result.demand_lowering = try self.generator.demand_lowering.take(self.allocator);
        if (self.options.explain_allocations) result.allocation_emission = try @import("allocation_emission.zig").capture(self.allocator, self.units, self.options.identity, &self.generator.module, self.entry, self.options.diagnostic_prelude_unit);
        if (self.options.observe_startup) result.startup_observation = try self.generator.planning.startup_facts.capture(self.allocator, &self.generator.module);
        result.principal = self.generator.principalStats();
        if (self.query_state) |state| result.completed_queries = state.stats;
        result.completed_queries.recorded = self.generator.evaluator.retained.specialization_receipts.items.len;
        for (self.generator.evaluator.retained.specialization_receipts.items) |record| if (record.complete) {
            result.completed_queries.complete_records += 1;
            if (record.member != null) result.completed_queries.member_recorded += 1;
        };
        result.reuse = self.generator.work;
        result.refinements = self.generator.refinement_stats;
        result.query_tables.canonical = self.generator.evaluator.specializations.canonical_specializations.table.storage();
        if (self.persisted_principals) |*reader| result.query_tables.portable_principal = reader.storage();
        result.query_tables.source_description = self.generator.evaluator.principalQueryStorage().source_description;
        result.query_tables.open_residual = self.generator.evaluator.principalQueryStorage().open_residual;
        if (self.retained) |state| {
            result.reuse.reused_named = state.stats.reused_named;
            result.reuse.reused_closures = state.stats.reused_closures;
            result.reuse.candidates = state.stats.candidates;
            result.reuse.declined = state.stats.declined;
            result.reuse.reused_scalar_constants = state.stats.reused_scalar_constants;
            result.reuse.reused_aggregate_constants = state.stats.reused_aggregate_constants;
        }
    }
    fn recordArtifact(self: *CompileRun, result: *Result) Error!void {
        if (self.recording) {
            for (self.generator.evaluator.retained.specialization_receipts.items) |record| {
                var input = record.input;
                if (record.member) |member| input = member.function;
                _ = try @import("../eval/selected_query.zig").remember(&self.metadata.specialization_queries, self.allocator, self.generator.evaluator.closureInfo(input), try record.clone(self.allocator));
            }
            for (self.metadata.specialization_queries.records.items) |record| if (record.dependencies.member != null) {
                result.completed_queries.member_payload_bytes += @sizeOf(@import("../eval/selected_query.zig").Table.Record) + @import("../reuse/specialization_receipt.zig").ownedBytes(record.dependencies);
            };
            // Records exist only for parallel semantic inference.
            if (self.query_state) |*state| if (self.options.policy.semantic_workers > 1) {
                try self.metadata.independent_calls.ensureUnusedCapacity(self.allocator, state.independent_calls.items.len);
                for (state.independent_calls.items) |record| self.metadata.independent_calls.appendAssumeCapacity(try record.clone(self.allocator));
            };
            result.query_tables.selected = self.metadata.specialization_queries.storage();
            result.query_tables.principal = self.metadata.principal_queries.storage();
            // Without a previous revision every pin takes a fresh token; the
            // memo is needed only to share retained tokens or to validate.
            try self.metadata.capturePoolsWithStamps(&self.generator, self.options.identity, if (self.stamps != null or self.options.validate_pins) &self.module_stamps else null);
            result.counters = self.generator.evaluator.counters;
            // Publish validation only with this candidate's owned artifact pools.
            // A failed edit leaves the previous certificate and source pins intact.
            if (self.principal_state) |*state| {
                self.metadata.pools.?.dependency_certificate = try state.gate.freezeValidation(self.allocator, self.metadata.pools.?.modules);
            } else if (self.retained) |*state| if (state.importer.code_gate) |*checked| {
                self.metadata.pools.?.dependency_certificate = try checked.semantic.freezeValidation(self.allocator, self.metadata.pools.?.modules);
            };
            if (self.metadata.pools.?.dependency_certificate) |*certificate| {
                result.source_validation.retained = certificate.storage();
                result.source_validation.reused_images = certificate.reused_images;
            }
            self.journal.seal();
            try self.journal.freezeFunctions(self.metadata.function_jobs.items);
            // These helpers capture values absent from ClosureKey. Full journal
            // replay is exact; fragment admission requires fresh enclosing code.
            for (self.generator.static_data.closures.items) |function_id| self.journal.functions[function_id].role = .static_closure;
            for (self.metadata.pools.?.runtime_globals) |slot| self.journal.functions[slot.initializer].role = .runtime_initializer;
            var task_movers = self.generator.planning.task_movers.valueIterator();
            while (task_movers.next()) |function_id| self.journal.functions[function_id.*].role = .task_mover;
            for (self.journal.functions) |function_| if (function_.role == .unknown) return error.InvalidFunctionReference;
            // The journal retains symbolic function/table identities. Assembly may
            // map several private identities to one physical machine-code body.
            if (self.journal.functions.len != self.generator.module.functions.items.len) return error.InvalidFunctionReference;
            for (self.metadata.jobs.items) |job| if (job.state == .failed or job.state == .pending or job.state == .reserved) return error.InvalidFunctionReference;
            for (self.metadata.pools.?.functions) |function_| {
                if (function_.function >= self.journal.functions.len) return error.InvalidFunctionReference;
                const owner = self.journal.functions[function_.function].owner;
                if (owner == 0 or owner > self.metadata.jobs.items.len) return error.InvalidFunctionReference;
                const job = self.metadata.jobs.items[owner - 1];
                if (job.state != .complete or job.function == null or job.function.? != function_.function or !std.meta.eql(job.request, function_.request) or job.result_template != function_.result_template) return error.InvalidFunctionReference;
            }
            const globals = self.generator.module.globals.items.len;
            const imports = self.generator.module.imports.items.len;
            const signatures = self.generator.module.signatures.items.len;
            const data_bytes = self.generator.module.data.items.len;
            if (self.options.artifact_replay) try self.replayArtifact(result);
            result.artifacts = .{ .demands = self.metadata.jobs.items.len, .jobs = self.metadata.pools.?.functions.len, .functions = self.journal.functions.len, .helpers = self.journal.functions.len - self.metadata.pools.?.functions.len, .emission_events = self.journal.records.items.len, .metadata_events = self.metadata.events.items.len, .operation_symbols = self.journal.operations.items.len, .templates = self.metadata.pools.?.captures.len, .pinned_modules = self.metadata.pools.?.modules.len };
            if (self.options.artifact_dump) {
                try printArtifact(self.allocator, "ARTIFACT_JOBS", self.metadata.jobs.items);
                try printArtifact(self.allocator, "ARTIFACT_DEMAND_EVENTS", self.metadata.events.items);
                try printArtifact(self.allocator, "ARTIFACT_EMISSION", .{ .records = self.journal.records.items, .bytes = self.journal.bytes.items, .parameters = self.journal.parameters.items, .operations = self.journal.operations.items, .functions = self.journal.functions, .locals = self.journal.locals, .instructions = self.journal.instructions });
                const pools = &self.metadata.pools.?;
                for (pools.modules) |pin| try printArtifact(self.allocator, "ARTIFACT_MODULE_PIN", .{ .unit = pin.unit, .path = pin.canonical_path, .token = pin.token, .stamp = pin.stamp });
                try printArtifact(self.allocator, "ARTIFACT_OWNED_POOLS", .{ .project_identity = pools.project_identity, .identity = pools.identity, .layouts = pools.layouts, .evaluator = pools.evaluator, .rows = pools.rows, .templates = pools.templates, .captures = pools.captures, .bridge = pools.bridge, .field_locations = pools.field_locations, .field_locations_stamp = pools.field_locations_stamp, .functions = pools.functions, .serialized = pools.serialized, .runtime_globals = pools.runtime_globals, .runtime_order = pools.runtime_order, .operations = pools.operations, .operation_relocations = pools.operation_relocations, .operations_finalized = pools.operations_finalized });
                std.debug.print("ARTIFACT_METADATA {{\"demands\":{d},\"events\":{d},\"complete_functions\":{d},\"templates\":{d},\"pinned_modules\":{d}}}\n", .{ self.metadata.jobs.items.len, self.metadata.events.items.len, self.metadata.pools.?.functions.len, self.metadata.pools.?.captures.len, self.metadata.pools.?.modules.len });
                std.debug.print("ARTIFACT_REPLAY {{\"events\":{d},\"owned_bytes\":{d},\"functions\":{d},\"globals\":{d},\"imports\":{d},\"signatures\":{d},\"data_bytes\":{d},\"source_work_during_replay\":0,\"semantic_reuse\":false}}\n", .{ self.journal.records.items.len, self.journal.bytes.items.len, result.emitted_functions, globals, imports, signatures, data_bytes });
            }
        }
    }
    fn replayArtifact(self: *CompileRun, result: *Result) Error!void {
        self.generator.deinit();
        self.generator_alive = false;
        var replayed = self.journal.materialize(self.allocator) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ModuleTooLarge => return error.ModuleTooLarge,
            else => return error.InvalidFunctionReference,
        };
        defer replayed.deinit();
        var replay_candidate = try @import("region_candidate.zig").prepare(self.allocator, &replayed, @import("activation_model.zig").fromPools(self.units, &self.metadata.pools.?));
        defer if (replay_candidate) |*owned| owned.deinit();
        var replay_module: *const wasm.Module = &replayed;
        if (replay_candidate) |*owned| replay_module = &owned.view.module;
        var replay_vectors = if (self.options.policy.codegen_tier == .optimized) try @import("simd_abi.zig").prepare(self.allocator, replay_module) else null;
        defer if (replay_vectors) |*owned| owned.deinit();
        if (replay_vectors) |*owned| replay_module = &owned.module;
        const actual_bytes = replay_module.assembleCheckedWithOptions(.{ .tier = self.options.policy.codegen_tier, .share_machine_code = self.options.policy.share_machine_code }) catch |err| switch (err) {
            error.IncompleteOwnership => return error.InvalidFunctionReference,
            error.OutOfMemory => return error.OutOfMemory,
            error.ModuleTooLarge => return error.ModuleTooLarge,
            error.InvalidGlobalReference => return error.InvalidGlobalReference,
            else => return error.InvalidFunctionReference,
        };
        errdefer self.allocator.free(actual_bytes);
        if (!std.mem.eql(u8, result.bytes, actual_bytes)) {
            return error.InvalidFunctionReference;
        }
        self.allocator.free(result.bytes);
        result.bytes = actual_bytes;
    }
    fn publish(self: *CompileRun, result: *Result) Error!void {
        if (self.options.retain_artifacts) {
            result.capture = .{ .metadata = self.metadata, .emission = self.journal, .cached_units = self.options.cached_units, .optimized = self.optimized };
            self.optimized = null;
            self.metadata_alive = false;
            self.journal_alive = false;
            try result.capture.?.sealExecutableQueries();
            result.query_tables.executable_fragment = result.capture.?.executable_queries.storage();
            if (result.capture.?.optimized) |*owner| result.query_tables.executable_optimizer = owner.queries.storage();
        }
        result.module_stamps = .{ .computed = self.module_stamps.computed, .reused = self.module_stamps.reused, .comparisons = self.module_stamps.comparisons, .copied = self.module_stamps.copied, .hashed = self.module_stamps.hashed };
        self.timing.capture_us = self.clock.lap();
        result.timing = self.timing;
    }
};

fn compileAttempt(allocator: Allocator, units: []const core.Module, entry: u32, options: CompileOptions, skip_constant_replay: bool, speculative_locals: bool) (Error || error{ ConstantReceiptRetry, SpeculativeLocalRetry })!Result {
    var run: CompileRun = .{ .allocator = allocator, .units = units, .entry = entry, .options = options, .speculative_locals = speculative_locals };
    defer run.deinit();
    try run.prepare(skip_constant_replay);
    if (try run.emit()) |failure| {
        if (!run.generator.speculated) return failure;
        var discarded = failure;
        discarded.deinit(allocator);
        return error.SpeculativeLocalRetry;
    }
    const speculated = run.generator.speculated;
    var result = try run.assemble();
    if (result.diagnostic != null) {
        if (!speculated) return result;
        result.deinit(allocator);
        return error.SpeculativeLocalRetry;
    }
    errdefer result.deinit(allocator);
    try run.observe(&result);
    try run.recordArtifact(&result);
    try run.publish(&result);
    return result;
}

fn printArtifact(allocator: Allocator, label: []const u8, value: anytype) Allocator.Error!void {
    const bytes = try std.json.Stringify.valueAlloc(allocator, value, .{ .emit_strings_as_arrays = true, .emit_nonportable_numbers_as_strings = true });
    defer allocator.free(bytes);
    std.debug.print("{s} {s}\n", .{ label, bytes });
}

fn entryInterfaceAdmissible(g: *const Generator, view: type_evidence.View, id: type_evidence.Id) bool {
    const node = view.node(id);
    if (node.tag != .function) return entryData(view, id, false);
    if (!entryData(view, node.b, true) and !entryOwner(g, view, node.b) or !entryForeign(view, node.c, false)) return false;
    if (entryData(view, node.a, true)) return true;
    const parameter = view.node(node.a);
    if (parameter.tag == .usage and parameter.b == @backingInt(types.UsageKind.concurrent) and parameter.c == 0) {
        const host = view.node(parameter.a);
        return host.tag == .function and entryData(view, host.a, true) and entryData(view, host.b, true) and entryForeign(view, host.c, true);
    }
    if (parameter.tag == .usage and parameter.b == @backingInt(types.UsageKind.cleanup) and parameter.c == 0) {
        const cleanup = view.node(parameter.a);
        if (cleanup.tag != .function or view.node(cleanup.b).tag != .unit or !entryForeign(view, cleanup.c, true)) return false;
        const owner = view.node(cleanup.a);
        return owner.tag == .usage and owner.b == @backingInt(types.UsageKind.unique) and owner.c == 0 and entryOwnerPayload(g, view, owner.a);
    }
    if (entryOwner(g, view, node.a)) return true;
    return parameter.tag == .function and entryData(view, parameter.a, true) and entryData(view, parameter.b, true) and entryForeign(view, parameter.c, true);
}
fn entryOwner(g: *const Generator, view: type_evidence.View, id: type_evidence.Id) bool {
    const owner = view.node(id);
    if (owner.tag != .usage or owner.c != 0 or (owner.b != @backingInt(types.UsageKind.unique) and owner.b != @backingInt(types.UsageKind.shared))) return false;
    var remaining: usize = 65536;
    return entryClosedData(g, view, owner.a, 0, &remaining);
}
fn entryClosedData(g: *const Generator, view: type_evidence.View, id: type_evidence.Id, depth: usize, remaining: *usize) bool {
    if (remaining.* == 0 or depth >= 128 or id >= view.nodes.len) return false;
    remaining.* -= 1;
    const node = view.node(id);
    switch (node.tag) {
        .unit, .boolean, .u32, .f32 => return true,
        .array, .list => return entryClosedData(g, view, node.a, depth + 1, remaining),
        .product, .record, .nominal => {
            if (node.tag == .nominal) {
                if (node.a == 0 or node.a > g.units.len) return false;
                var found = false;
                for (g.units[node.a - 1].nominals) |nominal| {
                    if (remaining.* == 0) return false;
                    remaining.* -= 1;
                    if (nominal.identity.unit != node.a or nominal.identity.decl != node.b) continue;
                    if (found or !nominal.closed_storage or nominal.has_usage or view.children(id).len != nominal.parameters.len) return false;
                    found = true;
                }
                if (!found) return false;
            }
            for (view.children(id), 0..) |child, index| {
                if (node.tag == .record and index % 2 == 0) continue;
                if (!entryClosedData(g, view, child, depth + 1, remaining)) return false;
            }
            return true;
        },
        else => return false,
    }
}
fn shapeTypeWork(module: *const core.Module, id: u32, remaining: *usize, depth: usize) error{LayoutLimit}!void {
    if (remaining.* == 0 or depth >= 128 or id == 0 or id >= module.types.nodes.len) return error.LayoutLimit;
    remaining.* -= 1;
    const node = module.types.node(id);
    switch (node.tag) {
        .unit, .boolean, .u32, .f32, .variable => {},
        .array, .list => try shapeTypeWork(module, node.a, remaining, depth + 1),
        .product => for (module.types.list(.{ .start = node.a, .len = node.b })) |child| try shapeTypeWork(module, child, remaining, depth + 1),
        .record => {
            // Sorted parameter matching may inspect each field pair. Charge it
            // here before representation selection can traverse that catalogue.
            const pairs = std.math.mul(usize, node.b, node.b) catch return error.LayoutLimit;
            if (remaining.* < pairs) return error.LayoutLimit;
            remaining.* -= pairs;
            for (0..node.b) |index| try shapeTypeWork(module, module.types.recordField(node, index).ty, remaining, depth + 1);
        },
        .nominal => for (module.types.nominalArguments(node)) |child| try shapeTypeWork(module, child, remaining, depth + 1),
        else => return error.LayoutLimit,
    }
}
fn entryOwnerPayload(g: *const Generator, view: type_evidence.View, id: type_evidence.Id) bool {
    var remaining: usize = 65_536;
    return entryClosedData(g, view, id, 0, &remaining);
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
        if (operation.instance.unit != 0 or operation.instance.decl != 0 or operation.identity.unit != 0 or operation.identity.decl != 1 or operation.arguments.len != 0) return false;
    }
    return true;
}
const entry_abi_rule = "entry functions take or return Unit, U32, F32, Bool, Array U32, Array F32, or unique/shared owners of closed data; one exact Foreign scalar/numeric-array callback or synchronous cleanup descriptor is also accepted as input; every other effect must be handled; entry values are Unit, U32, F32 or Bool";

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
        if (!header.selected or header.generic or (header.evidence != 0 and !entryInterfaceAdmissible(g, g.evaluator.evidenceView(), header.evidence))) {
            return declineEntryInterface(g, entry, body, header);
        }
        if (unit_.has_usage_contracts and header.evidence != 0) {
            const view = g.evaluator.evidenceView();
            const interface = view.node(header.evidence);
            if (interface.tag == .function and entryOwner(g, view, interface.b)) g.persistent_outputs = true;
        }
        // Residual source dispatch keeps the ordinary complete-proof path.
        // It is not a reusable source-interface certificate.
    };
}

/// Source selection and runtime value retention differ. All selected runtime
/// initializer cells are roots; ordinary constants contribute their completed
/// value graphs. Planning reads immutable owned Core and never spends fuel.
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
        try g.planning.planRuntime(g, entry, unit_order);
    }
    for (unit_.bodies[1..]) |*body| {
        if (!body.exported) continue;
        const target: core.BindingRef = .{ .unit = entry, .binding = body.binding };
        if (body.is_function or unit_.types.node(unit_.binding(body.binding).ty).tag == .function) {
            const key = try g.entrySignature(target, body.scheme.root, body.span);
            if (key.count != 1 or !g.foreignRow(key.effects[0], false)) return g.decline(entry, body.span, .entry_type);
            const output = g.ownerBoundary(key.result);
            var result = g.representations.store.abi(key.result);
            if (output != null) result = .u32;
            if (result == null) return g.decline(entry, body.span, .entry_type);
            const callback = g.hostCallback(key.parameters[0]);
            const input = g.representations.store.node(key.parameters[0]);
            var owner_input = g.ownerBoundary(key.parameters[0]);
            var payload: ?layout.Id = null;
            var parameter = g.representations.store.abi(key.parameters[0]);
            var leased = false;
            if (owner_input) |*owner| {
                owner.fresh = g.freshOwnerInput(input.a);
                parameter = owner.fresh;
                if (parameter == null) {
                    parameter = .u32;
                    leased = true;
                } else payload = input.a;
            }
            // Input-only scalar/Array modules keep their invocation ABI: no
            // public lease can be produced in this instance.
            if (!g.persistent_outputs and payload != null) owner_input = null;
            if (callback == null and parameter == null) return g.decline(entry, body.span, .entry_type);
            const function_id = try g.function(key);
            var header = unit_.types.node(body.scheme.root);
            while (header.tag == .forall) header = unit_.types.node(header.a);
            const once = header.tag == .usage and header.b == @backingInt(types.UsageKind.once);
            var guard: ?u32 = null;
            if (once) guard = try g.module.addGlobal(.u32, 0, true);
            if (callback) |incoming| {
                var host = incoming;
                var signature = unit_.types.node(body.scheme.root);
                while (signature.tag == .forall or signature.tag == .usage) signature = unit_.types.node(signature.a);
                const qualified = unit_.types.node(signature.a);
                if (qualified.tag == .usage and qualified.b == @backingInt(types.UsageKind.concurrent)) {
                    host.concurrent = true;
                    _ = try g.taskRuntime();
                }
                try g.module.exportOwnerCallbackFunction(try g.entryCallbackFunction(function_id, key.parameters[0], result.?, guard, output), unit_.name(body.export_name), host, result.?, once, output);
            } else {
                try g.module.exportOwnerFunction(try g.entryFunction(function_id, parameter.?, result.?, payload, guard, owner_input, output, leased), unit_.name(body.export_name), parameter.?, result.?, once, owner_input, output, false);
                if (owner_input != null and !leased) {
                    const name = try g.allocator.print("blot:owner_call/{s}", .{unit_.name(body.export_name)});
                    defer g.allocator.free(name);
                    try g.module.exportOwnerFunction(try g.entryFunction(function_id, .u32, result.?, null, guard, owner_input, output, true), name, .u32, result.?, once, null, null, true);
                }
            }
            if (owner_input != null or output != null) _ = try g.ownerRuntime();
        } else if (body.runtime) {
            const concrete = try g.typeLayout(entry, body.scheme.root, &.{}, body.span);
            const scalar_ = g.representations.store.abi(concrete) orelse return g.decline(entry, body.span, .entry_type);
            if (scalar_ == .array_u32 or scalar_ == .array_f32) return g.decline(entry, body.span, .entry_type);
            try g.module.exportGlobal(try g.planning.runtimeGlobal(g, target), unit_.name(body.export_name));
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
    try g.emitHostDataSchemas();
}

const Template = @import("backend_emission.zig").Template;
const Emitter = @import("backend_emission.zig").Owner;
