//! Resolved per-function instruction emission. Each owner borrows one backend
//! run and immutable mappings, and releases its own plans, locals and cleanups.
const DictionaryOwner = @import("../check/dictionary_owner.zig").Owner;
const std = @import("std");
const core = @import("../check/core.zig");
const types = @import("../check/types.zig");
const wasm = @import("wasm.zig");
const scalar_ops = @import("scalar_ops.zig");
const simd_intrinsics = @import("simd_intrinsics.zig");
const core_eval = @import("../eval/core_eval.zig");
const type_evidence = @import("../eval/type_evidence.zig");
const substitution_keys = @import("../reuse/substitution_keys.zig");
const provider_chain = @import("provider_chain.zig");
const layout = @import("layout.zig");
const resolved_call = @import("resolved_call.zig");
const resolved_body = @import("resolved_body.zig");
const packed_layout = @import("packed_layout.zig");
const row_projection_uses = @import("../reuse/row_projection_uses.zig");
const list_traversal = @import("list_traversal.zig");
const runtime_cleanup = @import("../runtime/runtime_cleanup.zig");
const request_runtime = @import("../runtime/request_runtime.zig");
const heap = @import("../runtime/runtime_layout.zig");
const function_facts = @import("function_facts.zig");
const exact_builder = @import("exact_builder.zig");
const ragged_builder = @import("ragged_builder.zig");
const runtime_operations = @import("runtime_operations.zig");
const resolved_flow = @import("resolved_flow.zig");
const ir = @import("runtime_ir.zig");
const artifact_emitter = @import("../reuse/artifact_emitter.zig");
const code_artifacts = @import("../reuse/code_artifacts.zig");
const Allocator = std.mem.Allocator;
const Scalar = wasm.Scalar;
const Value = scalar_ops.Value;
const max_parameters = code_artifacts.max_parameters;
const Key = code_artifacts.Key;
const Mapping = layout.Mapping;
const RowMapping = layout.RowMapping;
const ClosureKey = code_artifacts.ClosureKey;
const CallableKey = code_artifacts.CallableKey;
const ConstructorKey = code_artifacts.ConstructorKey;
const PrimitiveKey = code_artifacts.PrimitiveKey;
const OperationKey = code_artifacts.OperationKey;
const Code = @import("../check/diagnostic_code.zig").Code;
pub const Error = Allocator.Error || error{ Declined, ModuleTooLarge, InvalidFunctionReference, InvalidGlobalReference };
pub const CarrierKey = struct { from: layout.Id, to: layout.Id };
pub const Template = struct { scalar_environment: bool = false, callable_instances: u32 = 0, staged: u32 = 0, unit: u32 = 0, node: core.Id, environment: ?u32 = null, captures: layout.Id = 0, templates: substitution_keys.Id = 0, demand_cell: bool = false, computation: bool = false, evidence: u32 = 0, rows: substitution_keys.Id = 0 };
const Generator = @import("core_backend.zig").Generator;
pub const Owner = struct {
    const Emitter = @This();
    const ReturnTarget = struct { node: core.Id, label: u32, cleanup: runtime_cleanup.Mark, template_result: bool = false };
    const CarryRoot = struct { iteration: core.BindingId, outgoing: core.BindingId, slot: u32 };
    const ContinueTarget = struct { plan: resolved_flow.Loop, metadata: core.LoopInfo, input: LoopInput, outer_cleanup: runtime_cleanup.Mark, inner_cleanup: runtime_cleanup.Mark, row_label: u32, head_label: u32 };
    const LoopTarget = struct { node: core.Id, label: u32, cleanup: runtime_cleanup.Mark, roots: []const CarryRoot = &.{}, backedge: ?ContinueTarget = null };

    const RaggedCount = struct { plan: ragged_builder.Plan, count: u32, eligible: u32, budget: u32, limit: u32, exit: u32, cleanup: runtime_cleanup.Mark };
    const ResolverPlan = union(enum) { monad, forward, run: resolved_call.Arrow, call: resolved_call.Applied };
    const DispatchPlan = union(enum) {
        scalar: wasm.Op,
        simd: struct { input: layout.Id, result: layout.Id },
        selected: struct { key: Key, call: resolved_call.Applied },
    };
    const TemplatePreparation = struct {
        metadata: Template,
        capture_types: []layout.Id,
        capture_roles: []ir.Role,
        static_key: ?ClosureKey = null,
        fn deinit(self: *TemplatePreparation, a: Allocator) void {
            a.free(self.capture_types);
            a.free(self.capture_roles);
        }
    };
    const FieldPlan = struct {
        index: u32,
        projection: core.Projection,
        variants: std.ArrayList(core.ProjectionVariant) = .empty,
        slots: std.ArrayList(u32) = .empty,
        fn deinit(self: *FieldPlan, a: Allocator) void {
            self.variants.deinit(a);
            self.slots.deinit(a);
        }
    };
    const ProjectionPlan = union(enum) {
        field: FieldPlan,
        member: struct { direct: Key, wrapper: CallableKey },
        empty_cursor: u32,
        fn deinit(self: *ProjectionPlan, a: Allocator) void {
            switch (self.*) {
                .field => |*field| field.deinit(a),
                .member, .empty_cursor => {},
            }
        }
    };
    const FactoryPlan = struct {
        callee: union(enum) { named: Key, closure: ClosureKey },
        admitted: [max_parameters]bool = @splat(false),
        result: Template,
    };
    const DemandPlan = struct { uses: [max_parameters]u8 };
    const DemandDecision = struct { plan: ?DemandPlan = null, reason: @import("demand_lowering.zig").Reason };
    const DictionaryMemberPlan = struct { offset: usize, signature: layout.Id };
    const NamedPlan = struct {
        call: resolved_call.Named,
        spawn: ?@import("../check/task_core.zig").SpawnApplication = null,
        evaluated: ?*EvaluatedNamed = null,
        dictionary_owner: ?DictionaryOwner = null,
        dictionary_member: ?DictionaryMemberPlan = null,
        demand: ?DemandPlan = null,
        factory: ?FactoryPlan = null,
        fn deinit(self: *NamedPlan, a: Allocator) void {
            if (self.evaluated) |value| a.destroy(value);
            self.call.deinit(a);
        }
    };
    const SourceCall = struct { key: Key, arguments: [max_parameters]core.Id, count: usize };
    const EvaluatedNamed = struct {
        key: Key,
        arguments: [max_parameters]core.Id,
        count: usize,
        captured: [max_parameters]core_eval.ValueId,
        capture_count: usize,
    };
    const ApplyPlan = struct {
        spawn: ?@import("../check/task_core.zig").SpawnApplication = null,
        factory: ?FactoryPlan = null,
        evaluated: ?*EvaluatedNamed = null,
        static_closure: ?StaticClosurePlan = null,
        partial: ?SourceCall = null,
        known: ?SourceCall = null,
        arrow: ?resolved_call.Arrow = null,
        universal: ?layout.Id = null,
        quantifier: types.Id = 0,
        never: bool = false,
        local_callback: core.Id = 0,
        fn deinit(self: *ApplyPlan, a: Allocator) void {
            if (self.evaluated) |value| a.destroy(value);
            if (self.static_closure) |*closure_| closure_.deinit(a);
        }
    };
    const ProviderPlan = struct { ty: layout.Node, read: type_evidence.Effects.Label, write: ?type_evidence.Effects.Label = null };
    const StagingPlan = struct {
        value: core_eval.ValueId,
        body: ?*Body = null,
        fn deinit(self: *StagingPlan, allocator: Allocator) void {
            if (self.body) |body| {
                body.deinit(allocator);
                allocator.destroy(body);
            }
        }
    };
    /// One evaluation of a generalized local's producer at one checked use
    /// layout, prepared under the local's instance facts.
    const LocalInstance = struct { layout: layout.Id, body: *Body };
    const Plan = union(enum) {
        staging: StagingPlan,
        static_binding: core_eval.ValueId,
        instances: []LocalInstance,
        operation: struct { ty: layout.Id, label: type_evidence.Effects.Label },
        provider: ProviderPlan,
        projection: ?ProjectionPlan,
        update_locations: []FieldPlan,
        pattern: ?[]StaticBinding,
        template: TemplatePreparation,
        reference: ?core.BindingRef,
        named: NamedPlan,
        application: ApplyPlan,
        resource_scope: struct { acquire: layout.Id, release: layout.Id, callback: layout.Id },
        usage_borrow: layout.Id,
        usage_read: layout.Id,
        usage_share: layout.Id,
        resolver: ResolverPlan,
        dispatch: DispatchPlan,
        comparison: bool,
        constructor_subject: core.Id,
        result_member: CallableKey,
        join: resolved_flow.Join,
        match: resolved_flow.Match,
        loop: resolved_flow.Loop,
        exit: resolved_flow.SymbolicExit,
        request: resolved_flow.RequestLoop,
        collection_step: struct { pattern: core.Id, receiver: core.Id, key: Key },
        collection_pattern: void,
        private_cursor: struct { input: core.Id, linear: ?@import("linear_cursor.zig").Plan = null },
        private_row: layout.Id,
        private_pattern: layout.Id,
        pub fn deinit(self: *Plan, a: Allocator) void {
            switch (self.*) {
                .staging => |*staged| staged.deinit(a),
                .instances => |instances| {
                    for (instances) |instance| {
                        instance.body.deinit(a);
                        a.destroy(instance.body);
                    }
                    a.free(instances);
                },
                .request => |request| a.free(request.operations),
                .pattern => |bindings| if (bindings) |owned| a.free(owned),
                .template => |*metadata| metadata.deinit(a),
                .projection => |*projection_| if (projection_.*) |*prepared| prepared.deinit(a),
                .update_locations => |locations| {
                    for (locations) |*place| place.deinit(a);
                    a.free(locations);
                },
                .named => |*plan| plan.deinit(a),
                .application => |*application| application.deinit(a),
                .resolver => |*plan| switch (plan.*) {
                    .call => |*call| call.deinit(a),
                    else => {},
                },
                .dispatch => |*plan| switch (plan.*) {
                    .selected => |*selected| selected.call.deinit(a),
                    else => {},
                },
                else => {},
            }
            self.* = undefined;
        }
    };
    const Body = resolved_body.Body(Plan);
    const max_local_instances = 4;
    /// Local reads of an instanced producer. Each instance repeats them.
    const InstanceReads = struct { nodes: [32]core.Id = undefined, len: usize = 0 };
    /// A generalized local whose concrete checked uses disagree evaluates its
    /// pure producer once per distinct use layout (issue #10).
    const FactRange = struct { start: usize = 0, len: usize = 0 };
    const InstanceDecision = struct {
        statement: core.Id,
        count: usize = 0,
        layouts: [max_local_instances]layout.Id = undefined,
        /// Ranges of `InstanceDecisions.facts` and `.rows` that close the
        /// local's quantified type and row holes at each instance.
        facts: [max_local_instances]FactRange = @splat(.{}),
        rows: [max_local_instances]FactRange = @splat(.{}),
        reads: InstanceReads = .{},
    };
    const InstanceDecisions = struct {
        decisions: std.ArrayList(InstanceDecision) = .empty,
        facts: std.ArrayList(Mapping) = .empty,
        rows: std.ArrayList(RowMapping) = .empty,
        fn deinit(self: *InstanceDecisions, a: Allocator) void {
            self.decisions.deinit(a);
            self.facts.deinit(a);
            self.rows.deinit(a);
        }
        fn find(self: *const InstanceDecisions, statement: core.Id) ?*const InstanceDecision {
            for (self.decisions.items) |*decision| if (decision.statement == statement) return decision;
            return null;
        }
        fn factsAt(self: *const InstanceDecisions, decision: *const InstanceDecision, index: usize) []const Mapping {
            const range = decision.facts[index];
            return self.facts.items[range.start..][0..range.len];
        }
        fn rowsAt(self: *const InstanceDecisions, decision: *const InstanceDecision, index: usize) []const RowMapping {
            const range = decision.rows[index];
            return self.rows.items[range.start..][0..range.len];
        }
        /// The instanced producer containing a reference, if any.
        fn reader(self: *const InstanceDecisions, node: core.Id) ?*const InstanceDecision {
            for (self.decisions.items) |*decision| {
                if (std.mem.findScalar(core.Id, decision.reads.nodes[0..decision.reads.len], node) != null) return decision;
            }
            return null;
        }
    };
    const InstanceLocals = struct { count: usize = 0, layouts: [max_local_instances]layout.Id = undefined, locals: [max_local_instances]u32 = undefined };

    const RowView = struct { binding: core.BindingId, row: layout.Id, address: u32, limit_address: u32 };
    const CursorDirectory = struct { directory: ListDirectory, span: [3]u32 };
    const ListDirectory = struct { storage: u32, array: u32, offset: u32 };
    const LayoutEntry = struct { ty: types.Id = 0, value: layout.Id = 0 };
    const SmallCollection = struct { values: [function_facts.small_limit]u32 = undefined, len: usize = 0, machine: wasm.ValueType = .i32, kind: enum { collection, cursor } = .collection };
    body: ?*const Body = null,
    staged: ?core_eval.ValueId = null,
    preparation_depth: u16 = 0,
    preparing: bool = false,
    has_collection_steps: bool = false,
    planned_returns: std.ArrayList(struct { node: core.Id, template_result: bool }) = .empty,
    planned_loops: std.ArrayList(core.Id) = .empty,
    small_values: std.AutoHashMapUnmanaged(core.BindingId, SmallCollection) = .empty,
    row_views: std.ArrayList(RowView) = .empty,
    diagnostic_context: u32 = 0,
    cursor_directories: std.AutoHashMapUnmanaged(core.Id, CursorDirectory) = .empty,
    small_result: ?struct { root: core.Id, value: *SmallCollection } = null,
    analysis_root: core.Id = 0,
    exact_probe: bool = false,
    exact_build: ?struct { plan: exact_builder.Plan, storage: u32, index: u32, row_words: u32 } = null,
    ragged_fill: bool = false,
    ragged_count: ?*const RaggedCount = null,
    generator: *Generator,
    unit_id: u32,
    function_id: u32,
    semantic_node: core.Id = 0,
    semantic_context: ?struct { mappings: u32, rows: u32 } = null,
    /// Dynamic provider scope is an invocation argument, never a capture.
    provider_local: ?u32 = null,
    dictionary_local: ?u32 = null,
    dictionary_owner: ?DictionaryOwner = null,
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
    /// Preparation borrows the decisions of the body being prepared.
    local_instances: ?*const InstanceDecisions = null,
    /// Encoding: the instance locals of each instanced generalized local.
    instance_locals: std.AutoHashMapUnmanaged(core.BindingId, InstanceLocals) = .empty,

    // Source owner and mappings are immutable for this emitter's lifetime.
    // Cache only completed root conversions, preserving recursive work limits.
    layout_cache: [32]LayoutEntry = @splat(.{}),

    fn resolvedPlan(self: *Emitter, id: core.Id) Plan {
        const counters = &self.generator.evaluator.counters;
        counters.resolved_plan_reads += 1;
        const prepared = self.body.?.get(id);
        switch (prepared) {
            .join => counters.prepared_joins += 1,
            .match => {
                counters.prepared_joins += 1;
                counters.prepared_matches += 1;
            },
            .loop => counters.prepared_loops += 1,
            .exit => counters.prepared_exits += 1,
            .request => {
                counters.prepared_exits += 2;
                counters.prepared_request_loops += 1;
            },
            else => {},
        }
        return prepared;
    }
    /// A generalized local whose checked instances agree on one layout may
    /// use that instance's private storage. Only its quantified holes acquire
    /// facts; captures, merges and carries decline. Statements are visited
    /// last to first, so a later local's facts close the instances of an
    /// alias or rebinding chain feeding it (issue #10). Uses that disagree
    /// may instead evaluate a pure producer once per use layout
    /// (`decideInstances`); a read inside such a producer occurs once per
    /// instance. A use whose only holes are ambiguous variables is closed
    /// with storage this whole body gives them (`closeAmbiguousUse`), and
    /// `rows` receives the row facts that choice adds. This never unifies the
    /// semantic producer scheme.
    fn localStorageMappings(self: *Emitter, root: core.Id, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), instances: *InstanceDecisions) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        // Built only once some statement reaches the scan.
        var unit_uses: ?*const @import("unit_index.zig").Uses = null;
        const statements = source.children(root);
        // References read only by an unused local alias need no instance.
        var dead_aliases: [16]core.Id = undefined;
        var dead_count: usize = 0;
        var scratch: std.ArrayList(Mapping) = .empty;
        defer scratch.deinit(g.allocator);
        var scratch_rows: std.ArrayList(RowMapping) = .empty;
        defer scratch_rows.deinit(g.allocator);
        var ambiguous: Ambiguous = .{};
        defer ambiguous.deinit(g.allocator);
        var with_ambiguous: std.ArrayList(Mapping) = .empty;
        defer with_ambiguous.deinit(g.allocator);
        var with_ambiguous_rows: std.ArrayList(RowMapping) = .empty;
        defer with_ambiguous_rows.deinit(g.allocator);
        var scratch_plain: std.ArrayList(Mapping) = .empty;
        defer scratch_plain.deinit(g.allocator);
        var position = statements.len;
        statements: while (position > 0) {
            position -= 1;
            const statement = statements[position];
            const n = source.node(statement);
            if (n.tag != .bind or n.a == 0) continue;
            const producer = source.node(n.b);
            // Built data never takes the shared storage below; only distinct
            // instances may serve it.
            const built = producer.tag == .construct or producer.tag == .product or producer.tag == .record or producer.tag == .array;
            if (!built and producer.tag != .call and producer.tag != .apply and producer.tag != .project and producer.tag != .reference) continue;
            const binding = source.binding(n.a);
            if (binding.kind != .local or binding.scheme.variables.len == 0) continue;
            const produced = try self.codeLayout(binding.ty, source.span(statement));
            if (!self.hasErasedType(produced, 0)) continue;
            if (producer.tag == .project) {
                if (source.projectionVariants(producer.b).len != 0) continue;
                const projection = source.projection(producer.b);
                const receiver = try self.codeLayout(projection.source_type, source.span(n.b));
                if (try self.memberTarget(n.b, projection.field, receiver) == null) continue;
            }
            if (producer.tag == .reference) {
                const aliased = source.reference(n.b);
                if (aliased.unit != 0 and aliased.unit != self.unit_id) continue;
                if (source.binding(aliased.binding).kind != .local) continue;
            }
            const plain = if (mappings.items.len == 0) self.mappings else mappings.items;
            with_ambiguous.clearRetainingCapacity();
            try withFacts(Mapping, g.allocator, plain, ambiguous.types.items, &with_ambiguous);
            const previous = with_ambiguous.items;
            with_ambiguous_rows.clearRetainingCapacity();
            try withFacts(RowMapping, g.allocator, self.row_mappings, ambiguous.rows.items, &with_ambiguous_rows);
            const previous_rows = with_ambiguous_rows.items;
            var uses: [max_local_instances]layout.Id = undefined;
            var use_count: usize = 0;
            var open = false;
            // Whether a use closes only through ambiguous storage.
            var widened = false;
            const index = unit_uses orelse try g.unitUses(self.unit_id, .{});
            unit_uses = index;
            scan: for (index.references.get(n.a)) |use| {
                const reference = source.reference(use);
                if (reference.unit != 0 and reference.unit != self.unit_id) continue;
                if (std.mem.findScalar(core.Id, dead_aliases[0..dead_count], use) != null) continue;
                const reader = instances.reader(use);
                const contexts = if (reader) |held| held.count else 1;
                for (0..contexts) |context| {
                    var context_mappings = previous;
                    var context_rows = previous_rows;
                    if (reader) |held| {
                        scratch.clearRetainingCapacity();
                        try withFacts(Mapping, g.allocator, previous, instances.factsAt(held, context), &scratch);
                        context_mappings = scratch.items;
                        scratch_rows.clearRetainingCapacity();
                        try withFacts(RowMapping, g.allocator, previous_rows, instances.rowsAt(held, context), &scratch_rows);
                        context_rows = scratch_rows.items;
                    }
                    const use_type = source.typeOf(use);
                    const span = source.span(use);
                    const instance = try g.codeLayoutWithRows(self.unit_id, use_type, context_mappings, context_rows, span);
                    if (self.hasErasedType(instance, 0)) {
                        // Scan this local again once its ambiguous holes
                        // have storage.
                        if (try self.closeAmbiguousUse(use_type, context_mappings, context_rows, span, &ambiguous)) {
                            position += 1;
                            continue :statements;
                        }
                        open = true;
                        break :scan;
                    }
                    if (ambiguous.types.items.len != 0 and !widened) {
                        scratch_plain.clearRetainingCapacity();
                        try withFacts(Mapping, g.allocator, plain, if (reader) |held| instances.factsAt(held, context) else &.{}, &scratch_plain);
                        widened = self.hasErasedType(try g.codeLayoutWithRows(self.unit_id, use_type, scratch_plain.items, context_rows, span), 0);
                    }
                    if (std.mem.findScalar(layout.Id, uses[0..use_count], instance) != null) continue;
                    if (use_count == uses.len) {
                        open = true;
                        break :scan;
                    }
                    uses[use_count] = instance;
                    use_count += 1;
                }
            }
            if (open) continue;
            if (use_count == 0 and producer.tag == .reference) {
                if (dead_count < dead_aliases.len) {
                    dead_aliases[dead_count] = n.b;
                    dead_count += 1;
                }
                continue;
            }
            const flags = index.flagsOf(n.a);
            if (flags.captured or flags.merge_branch or flags.carried) continue;
            // The promoting attempt keeps a closed initializer's evaluator
            // value and serializes each use at its own layout. A local that
            // only ambiguous storage closes keeps that path, as it did while
            // the hole was open, rather than evaluate its producer at runtime.
            // That is speculation too: a runtime-dependent initializer is not
            // promoted, so a failing attempt retries and decides it then.
            const promotable = producer.tag == .call or producer.tag == .apply or producer.tag == .project or producer.tag == .construct or producer.tag == .product or producer.tag == .record;
            if (widened and g.speculative_locals and promotable) {
                g.speculated = true;
                continue;
            }
            // Built data with one use is a single instance.
            if (use_count > 1 or (built and use_count == 1)) {
                try self.decideInstances(statement, previous, previous_rows, uses[0..use_count], instances);
                continue;
            }
            if (built) continue;
            const actual: ?layout.Id = if (use_count == 1) uses[0] else null;
            var next: std.ArrayList(Mapping) = .empty;
            defer next.deinit(g.allocator);
            try next.appendSlice(g.allocator, previous);
            if (actual) |selected| {
                try g.mapTypeDepth(self.unit_id, &next, null, binding.ty, selected, source.span(statement), 0);
                try g.mapTypeDepth(self.unit_id, &next, null, source.typeOf(n.b), selected, source.span(statement), 0);
            } else {
                // No instance observes this pure local, so any physical
                // choice for its quantified holes is sound; take a scalar word.
                for (source.types.list(binding.scheme.variables)) |variable| {
                    for (next.items) |mapping| {
                        if (mapping.variable == variable) break;
                    } else try next.append(g.allocator, .{ .variable = variable, .layout = layout.word });
                }
                const closed = try g.codeLayoutWithRows(self.unit_id, binding.ty, next.items, previous_rows, source.span(statement));
                if (self.hasErasedType(closed, 0)) continue;
                try g.mapTypeDepth(self.unit_id, &next, null, source.typeOf(n.b), closed, source.span(statement), 0);
            }
            var private = true;
            for (next.items) |mapping| {
                const old = for (previous) |prior| {
                    if (prior.variable == mapping.variable) break prior.layout;
                } else layout.erased;
                if (mapping.layout == old) continue;
                if (std.mem.findScalar(types.Id, source.types.list(binding.scheme.variables), mapping.variable) == null) private = false;
            }
            if (!private) continue;
            mappings.deinit(g.allocator);
            mappings.* = next;
            next = .empty;
        }
        if (ambiguous.types.items.len == 0) return;
        {
            var merged: std.ArrayList(Mapping) = .empty;
            errdefer merged.deinit(g.allocator);
            try withFacts(Mapping, g.allocator, if (mappings.items.len == 0) self.mappings else mappings.items, ambiguous.types.items, &merged);
            mappings.deinit(g.allocator);
            mappings.* = merged;
        }
        if (ambiguous.rows.items.len == 0) return;
        rows.clearRetainingCapacity();
        try withFacts(RowMapping, g.allocator, self.row_mappings, ambiguous.rows.items, rows);
    }
    /// Ambiguous variables some use of one body left open, with the storage
    /// the whole body gives them: a scalar word for a type variable and the
    /// closed empty row for an effect row tail.
    const Ambiguous = struct {
        types: std.ArrayList(Mapping) = .empty,
        rows: std.ArrayList(RowMapping) = .empty,
        fn deinit(self: *Ambiguous, a: Allocator) void {
            self.types.deinit(a);
            self.rows.deinit(a);
        }
    };
    /// Closes a use whose holes are all ambiguous: no scheme or declaration
    /// of this unit quantifies them. Checking left such a type variable
    /// unconstrained, so no value of its type is ever built and no code reads
    /// one, and such a row tail adds no effect to the labels before it. Each
    /// takes a scalar word, or the closed empty row, throughout the body. The
    /// choice depends only on the variable, so bodies that make it agree, and
    /// a value of such a type reaches another body only through a layout,
    /// which carries the choice into nested closures and callee instances.
    /// A quantified hole declines: it stands for each type its instances
    /// choose, and a later use may read its shared storage at a concrete type.
    /// A quantified row tail stays unknown, which leaves no hole. True when
    /// the use is closed; otherwise `ambiguous` is unchanged.
    fn closeAmbiguousUse(self: *Emitter, ty: types.Id, mappings: []const Mapping, rows: []const RowMapping, span: core.Span, ambiguous: *Ambiguous) Error!bool {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        var variables: TypeVariables = .{ .source = source };
        if (!variables.visit(ty, 0)) return false;
        const known_types = ambiguous.types.items.len;
        const known_rows = ambiguous.rows.items.len;
        var closed = false;
        defer if (!closed) {
            ambiguous.types.shrinkRetainingCapacity(known_types);
            ambiguous.rows.shrinkRetainingCapacity(known_rows);
        };
        for (variables.types[0..variables.type_count]) |variable| {
            if (for (mappings) |mapping| {
                if (mapping.variable == variable) break true;
            } else false) continue;
            if (try g.quantifiedVariable(self.unit_id, variable, false)) return false;
            try ambiguous.types.append(g.allocator, .{ .variable = variable, .layout = layout.word });
        }
        if (ambiguous.types.items.len == known_types) return false;
        for (variables.rows[0..variables.row_count]) |variable| {
            if (for (rows) |mapping| {
                if (mapping.variable == variable) break true;
            } else false) continue;
            if (try g.quantifiedVariable(self.unit_id, variable, true)) continue;
            try ambiguous.rows.append(g.allocator, .{ .variable = variable, .row = 0 });
        }
        var closed_types: std.ArrayList(Mapping) = .empty;
        defer closed_types.deinit(g.allocator);
        var closed_rows: std.ArrayList(RowMapping) = .empty;
        defer closed_rows.deinit(g.allocator);
        try withFacts(Mapping, g.allocator, mappings, ambiguous.types.items[known_types..], &closed_types);
        try withFacts(RowMapping, g.allocator, rows, ambiguous.rows.items[known_rows..], &closed_rows);
        closed = !self.hasErasedType(try g.codeLayoutWithRows(self.unit_id, ty, closed_types.items, closed_rows.items, span), 0);
        return closed;
    }
    /// The distinct type variables and row tail variables a type mentions.
    /// `visit` is false when there are more than fit, the walk exceeds its
    /// bound, or a node is not one these storage choices can describe.
    const TypeVariables = struct {
        source: *const core.Module,
        types: [32]types.Id = undefined,
        type_count: usize = 0,
        rows: [16]u32 = undefined,
        row_count: usize = 0,
        remaining: usize = 1024,
        fn visit(self: *TypeVariables, ty: types.Id, depth: usize) bool {
            if (depth >= 64 or self.remaining == 0) return false;
            self.remaining -= 1;
            const source = self.source;
            const n = source.types.node(ty);
            switch (n.tag) {
                .unit, .boolean, .u32, .f32, .never, .erased_proof, .type_constructor, .bound => return true,
                .variable => {
                    if (std.mem.findScalar(types.Id, self.types[0..self.type_count], ty) != null) return true;
                    if (self.type_count == self.types.len) return false;
                    self.types[self.type_count] = ty;
                    self.type_count += 1;
                    return true;
                },
                .function, .demand, .provider => {
                    if (n.tag == .function and !self.visit(n.b, depth + 1)) return false;
                    return self.row(n.c, depth + 1) and self.visit(n.a, depth + 1);
                },
                .array, .list, .cursor, .resolver, .usage, .scoped, .forall, .existential => return self.visit(n.a, depth + 1),
                .state_provider => return self.visit(n.a, depth + 1) and self.visit(n.b, depth + 1) and self.visit(n.c, depth + 1),
                .product, .nominal => {
                    const children = if (n.tag == .nominal) source.types.nominalArguments(n) else source.types.list(.{ .start = n.a, .len = n.b });
                    for (children) |child| if (!self.visit(child, depth + 1)) return false;
                    return true;
                },
                .record => {
                    for (0..n.b) |index| if (!self.visit(source.types.recordField(n, index).ty, depth + 1)) return false;
                    return true;
                },
                else => return false,
            }
        }
        fn row(self: *TypeVariables, id: types.Effects.Id, depth: usize) bool {
            const source = self.source;
            for (source.types.rowLabels(id)) |label| for (source.types.operationArguments(label)) |argument| {
                if (!self.visit(argument, depth + 1)) return false;
            };
            switch (source.types.row(id).tail) {
                .variable => |variable| {
                    if (std.mem.findScalar(u32, self.rows[0..self.row_count], variable) != null) return true;
                    if (self.row_count == self.rows.len) return false;
                    self.rows[self.row_count] = variable;
                    self.row_count += 1;
                    return true;
                },
                else => return true,
            }
        }
    };
    /// Uses of one generalized local at different layouts share no physical
    /// value: closure ABI and field words depend on the layout. A pure
    /// producer with a representation-free value instead runs once per
    /// distinct use layout, each under facts closing only the local's
    /// quantified holes. Authority, usage contracts and effects decline.
    /// `previous` and `previous_rows` are the body's substitutions so far.
    fn decideInstances(self: *Emitter, statement: core.Id, previous: []const Mapping, previous_rows: []const RowMapping, uses: []const layout.Id, decisions: *InstanceDecisions) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const n = source.node(statement);
        const binding = source.binding(n.a);
        const span = source.span(statement);
        // Qualified and generative schemes choose evidence per use, not storage.
        if (binding.scheme.obligations.len != 0 or binding.scheme.generative.len != 0) return;
        if (!@import("../eval/closed_local_value.zig").dataShape(g.units, self.unit_id, binding.ty)) return;
        if (source.has_usage_contracts and (@import("../check/usage_check.zig").containsNominal(&source.types, source.nominals, binding.ty) catch true)) return;
        var decision: InstanceDecision = .{ .statement = statement, .count = uses.len };
        var scan: ProducerScan = .{ .source = source, .reads = &decision.reads };
        if (!scan.visit(n.b, 0)) return;
        // An edit proven to consume its collection in place may run only once.
        for (scan.edits[0..scan.edit_count]) |edit| if (try g.ownsArrayUpdate(self.unit_id, edit)) return;
        const fact_start = decisions.facts.items.len;
        const row_start = decisions.rows.items.len;
        var next: std.ArrayList(Mapping) = .empty;
        defer next.deinit(g.allocator);
        var next_rows: std.ArrayList(RowMapping) = .empty;
        defer next_rows.deinit(g.allocator);
        var closed: std.ArrayList(Mapping) = .empty;
        defer closed.deinit(g.allocator);
        var closed_rows: std.ArrayList(RowMapping) = .empty;
        defer closed_rows.deinit(g.allocator);
        const variables = source.types.list(binding.scheme.variables);
        const row_variables = source.types.list(binding.scheme.row_variables);
        const admitted = admitted: for (uses, 0..) |selected, index| {
            next.clearRetainingCapacity();
            next_rows.clearRetainingCapacity();
            try next.appendSlice(g.allocator, previous);
            try next_rows.appendSlice(g.allocator, previous_rows);
            try g.mapTypeDepth(self.unit_id, &next, &next_rows, binding.ty, selected, span, 0);
            try g.mapTypeDepth(self.unit_id, &next, &next_rows, source.typeOf(n.b), selected, span, 0);
            // Only the local's own quantified holes may differ by instance.
            const facts_first = decisions.facts.items.len;
            for (next.items) |mapping| {
                const old = for (previous) |prior| {
                    if (prior.variable == mapping.variable) break prior.layout;
                } else layout.erased;
                if (mapping.layout == old) continue;
                if (std.mem.findScalar(types.Id, variables, mapping.variable) == null) break :admitted false;
                try decisions.facts.append(g.allocator, mapping);
            }
            // A row the body leaves unknown closes to the row this use sees;
            // a known row still reconciles exactly.
            const rows_first = decisions.rows.items.len;
            for (next_rows.items) |mapping| {
                const old = for (previous_rows) |prior| {
                    if (prior.variable == mapping.variable) break prior.row;
                } else layout.unknown_row;
                if (mapping.row == old) continue;
                if (old != layout.unknown_row and std.mem.findScalar(u32, row_variables, mapping.variable) == null) break :admitted false;
                try decisions.rows.append(g.allocator, mapping);
            }
            decision.facts[index] = .{ .start = facts_first, .len = decisions.facts.items.len - facts_first };
            decision.rows[index] = .{ .start = rows_first, .len = decisions.rows.items.len - rows_first };
            decision.layouts[index] = selected;
            closed.clearRetainingCapacity();
            closed_rows.clearRetainingCapacity();
            try withFacts(Mapping, g.allocator, previous, decisions.factsAt(&decision, index), &closed);
            try withFacts(RowMapping, g.allocator, previous_rows, decisions.rowsAt(&decision, index), &closed_rows);
            if (try g.codeLayoutWithRows(self.unit_id, binding.ty, closed.items, closed_rows.items, span) != selected) break :admitted false;
        } else true;
        if (!admitted) {
            decisions.facts.shrinkRetainingCapacity(fact_start);
            decisions.rows.shrinkRetainingCapacity(row_start);
            return;
        }
        try decisions.decisions.append(g.allocator, decision);
    }
    /// `base` with `facts` replacing or extending its substitutions.
    fn withFacts(comptime Fact: type, a: Allocator, base: []const Fact, facts: []const Fact, out: *std.ArrayList(Fact)) Allocator.Error!void {
        try out.appendSlice(a, base);
        for (facts) |fact| {
            for (out.items) |*mapping| {
                if (mapping.variable == fact.variable) {
                    mapping.* = fact;
                    break;
                }
            } else try out.append(a, fact);
        }
    }
    /// A producer built only from pure construction, calls, applications and
    /// local reads. Pure `let` initializers generalize, so repeating one per
    /// instance repeats no effect. Blocks, matches, effects, usage operations,
    /// suspensions and any value of a usage-contract type decline. Possible
    /// in-place collection edits are collected for the exact ownership proof.
    const ProducerScan = struct {
        source: *const core.Module,
        reads: *InstanceReads,
        edits: [32]core.Id = undefined,
        edit_count: usize = 0,
        remaining: usize = 256,
        fn visit(self: *ProducerScan, id: core.Id, depth: usize) bool {
            if (id == 0 or depth >= 64 or self.remaining == 0) return false;
            self.remaining -= 1;
            const source = self.source;
            const n = source.node(id);
            // A repeated read or capture would duplicate a unique owner.
            if (source.has_usage_contracts) {
                const usage = @import("../check/usage_check.zig");
                if (usage.containsNominal(&source.types, source.nominals, n.ty) catch true) return false;
                if (n.tag == .closure) {
                    const metadata = source.closure(id);
                    for (source.extra[metadata.captures.start..][0..metadata.captures.len]) |held| {
                        if (usage.containsNominal(&source.types, source.nominals, source.binding(held).ty) catch true) return false;
                    }
                }
            }
            if (n.tag == .call or n.tag == .apply or n.tag == .array_op) {
                if (self.edit_count == self.edits.len) return false;
                self.edits[self.edit_count] = id;
                self.edit_count += 1;
            }
            switch (n.tag) {
                .constant, .constructor_function, .primitive_function, .closure => return true,
                .reference => {
                    if (self.reads.len == self.reads.nodes.len) return false;
                    self.reads.nodes[self.reads.len] = id;
                    self.reads.len += 1;
                    return true;
                },
                .scalar => return self.visit(n.a, depth + 1) and (n.b == 0 or self.visit(n.b, depth + 1)),
                .logical, .associated, .apply, .record_merge => return self.visit(n.a, depth + 1) and self.visit(n.b, depth + 1),
                .if_value => return self.visit(n.a, depth + 1) and self.visit(n.b, depth + 1) and self.visit(n.c, depth + 1),
                .project => return self.visit(n.a, depth + 1),
                .construct => return n.b == 0 or self.visit(n.b, depth + 1),
                .call, .product, .record, .array, .array_op => {
                    for (source.children(id)) |child| if (!self.visit(child, depth + 1)) return false;
                    return true;
                },
                else => return false,
            }
        }
    };
    /// Every source-body route enters here after its exact capture bindings
    /// exist. Preparation owns decisions; encoding alone owns runtime locals,
    /// labels, environments and the original lazy function-index order.
    fn prepareBody(self: *Emitter, root: core.Id, depth: usize, template: bool) Error!Body {
        const g = self.generator;
        const inference_stage = g.evaluator.enterInferenceStage(.preparation);
        defer inference_stage.deinit();
        if (self.preparation_depth >= 256) return g.fail(self.unit_id, root, .complexity);
        var storage: std.ArrayList(Mapping) = .empty;
        defer storage.deinit(g.allocator);
        var storage_rows: std.ArrayList(RowMapping) = .empty;
        defer storage_rows.deinit(g.allocator);
        var instances: InstanceDecisions = .{};
        defer instances.deinit(g.allocator);
        try self.localStorageMappings(root, &storage, &storage_rows, &instances);
        const source = g.unit(self.unit_id);
        if (@import("bottom_result.zig").proves(g.units, self.unit_id, root) and try self.codeLayout(source.typeOf(root), source.span(root)) == layout.erased) {
            if (storage.items.len == 0) try storage.appendSlice(g.allocator, self.mappings);
            var rows: std.ArrayList(RowMapping) = .empty;
            defer rows.deinit(g.allocator);
            try g.mapTypeDepth(self.unit_id, &storage, &rows, source.typeOf(root), 5, source.span(root), 0);
        }
        return self.prepareMapped(root, depth, template, if (storage.items.len == 0) self.mappings else storage.items, if (storage_rows.items.len == 0) self.row_mappings else storage_rows.items, if (instances.decisions.items.len == 0) null else &instances);
    }
    /// Prepares `root` under exact physical substitutions. Instance bodies
    /// enter here directly with their facts and no storage decisions.
    fn prepareMapped(self: *Emitter, root: core.Id, depth: usize, template: bool, mappings: []const Mapping, rows: []const RowMapping, instances: ?*const InstanceDecisions) Error!Body {
        const g = self.generator;
        const inference_stage = g.evaluator.enterInferenceStage(.preparation);
        defer inference_stage.deinit();
        if (self.preparation_depth >= 256) return g.fail(self.unit_id, root, .complexity);
        var body = try Body.init(g.allocator, self.unit_id, root, mappings, rows);
        errdefer body.deinit(g.allocator);
        body.rows_evidence = try g.rowMappingEvidence(rows);
        for (body.mappings) |mapping| if (g.representations.store.hasOwners(mapping.layout) catch return g.fail(self.unit_id, root, .complexity)) {
            body.has_owners = true;
            break;
        };
        var preparer: Emitter = .{ .generator = g, .unit_id = self.unit_id, .function_id = self.function_id, .mappings = body.mappings, .row_mappings = body.rows, .factory_template = self.factory_template, .inline_demands = self.inline_demands, .preparation_depth = self.preparation_depth + 1, .preparing = true, .staged = self.staged };
        defer preparer.deinit();
        preparer.dictionary_local = self.dictionary_local;
        preparer.dictionary_owner = self.dictionary_owner;
        preparer.locals = try self.locals.clone(g.allocator);
        preparer.templates = try self.templates.clone(g.allocator);
        preparer.static_values = try self.static_values.clone(g.allocator);
        preparer.local_instances = instances;
        try preparer.prepareNode(&body, root, depth, template);
        if (preparer.has_collection_steps) try preparer.prepareCursorFamilies(&body);
        try preparer.prepareLinearCursors(&body);
        try preparer.prepareNumeric(&body);
        try @import("safe_local_sinking.zig").plan(g.allocator, g.unit(self.unit_id), try g.unitUses(self.unit_id, .{}), root, &body.entries, &body.sinks);
        g.evaluator.counters.safe_local_sinks += body.sinks.count();
        g.evaluator.counters.resolved_bodies += 1;
        g.evaluator.counters.resolved_plan_entries += body.entries.count();
        return body;
    }
    fn prepareCursorFamilies(self: *Emitter, plans: *Body) Error!void {
        const proof = @import("private_cursor.zig");
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const uses = try g.unitUses(self.unit_id, .{ .flow = true });
        var steps: [64]proof.Step = undefined;
        var count: usize = 0;
        var entries = plans.entries.keyIterator();
        while (entries.next()) |id| {
            const selected = plans.get(id.*);
            if (selected != .collection_step or source.node(selected.collection_step.receiver).tag != .reference) continue;
            const receiver = source.reference(selected.collection_step.receiver);
            if (receiver.unit != 0 and receiver.unit != self.unit_id) continue;
            if (count == steps.len) return;
            const pattern = source.node(selected.collection_step.pattern);
            const fields = source.patternChildren(source.pattern(pattern.a).b);
            const rest = source.pattern(fields[1]);
            steps[count] = .{ .node = source.node(id.*).b, .pattern = selected.collection_step.pattern, .input = receiver.binding, .rest = if (rest.tag == .bind) rest.a else 0 };
            count += 1;
        }
        var handled: [64]bool = @splat(false);
        for (steps[0..count], 0..) |step, index| {
            if (handled[index]) continue;
            const family = proof.checkSteps(source, uses, plans.root, step.input, steps[0..count]) orelse continue;
            var admissible = true;
            // The existing whole-loop conversion already owns its progress
            // locals and skips these protocol nodes entirely.
            var planned = plans.entries.keyIterator();
            while (planned.next()) |planned_id| {
                const id = planned_id.*;
                if (source.node(id).tag != .loop) continue;
                const loop = plans.get(id);
                if (loop != .loop or loop.loop.collection == null) continue;
                for (source.loopCarries(id)) |carry| {
                    if (std.mem.findScalar(core.BindingId, family.bindings[0..family.len], carry.iteration) != null) {
                        admissible = false;
                        break;
                    }
                }
                if (!admissible) break;
            }
            if (!admissible) continue;
            for (family.bindings[0..family.len]) |binding| {
                const concrete = try self.codeLayout(source.binding(binding).ty, source.span(plans.root));
                const cursor = g.representations.store.node(concrete);
                if (cursor.tag != .cursor or try g.collectionRowWords(cursor.a) != 0 or (g.representations.store.node(cursor.a).tag != .array and g.representations.store.node(cursor.a).tag != .list)) {
                    admissible = false;
                    break;
                }
                _ = g.representations.toEvidence(g.evaluator.evidenceStore(), concrete) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    admissible = false;
                    break;
                };
                if (source.binding(binding).kind != .local) {
                    admissible = false;
                    break;
                }
            }
            if (!admissible) continue;
            for (steps[0..count], 0..) |other, other_index| if (std.mem.findScalar(core.BindingId, family.bindings[0..family.len], other.input) != null) {
                handled[other_index] = true;
            };
            // Plan each member's definitions in node order.
            var definitions: std.ArrayList(core.Id) = .empty;
            defer definitions.deinit(g.allocator);
            for (family.bindings[0..family.len]) |binding| try definitions.appendSlice(g.allocator, uses.definitions.get(binding));
            std.mem.sort(core.Id, definitions.items, {}, std.sort.asc(core.Id));
            for (definitions.items, 0..) |id, position| {
                if (position != 0 and definitions.items[position - 1] == id) continue;
                if (plans.entries.contains(id)) continue;
                const input = try self.privateCursorConstructor(plans, source.node(id).b);
                try plans.put(g.allocator, id, .{ .private_cursor = .{ .input = input orelse 0 } });
            }
        }
    }
    fn prepareLinearCursors(self: *Emitter, body: *Body) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        var entries = body.entries.keyIterator();
        while (entries.next()) |statement| {
            const selected = body.get(statement.*);
            if (selected != .private_cursor or selected.private_cursor.input == 0) continue;
            const cursor = g.representations.store.node(try self.codeLayout(source.binding(source.node(statement.*).a).ty, source.span(statement.*)));
            if (cursor.tag != .cursor or g.representations.store.node(cursor.a).tag != .list or try g.collectionRowWords(cursor.a) == 0) continue;
            const uses = try g.unitUses(self.unit_id, .{ .parents = true, .flow = true });
            const linear = @import("linear_cursor.zig").check(source, uses, body.root, statement.*) orelse continue;
            if (!body.entries.contains(linear.advance) or body.get(linear.advance) != .private_cursor) continue;
            if (!body.entries.contains(linear.loop) or body.get(linear.loop) != .loop or body.get(linear.loop).loop.collection != null) continue;
            body.getPtr(.private_cursor, statement.*).linear = linear;
        }
    }
    fn prepareNumeric(self: *Emitter, body: *Body) Error!void {
        if (!body.has_associated or !body.has_numeric_checks) return;
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const numeric = @import("../check/numeric_proof_core.zig");
        var selected: std.ArrayList(numeric.Selected) = .empty;
        defer selected.deinit(g.allocator);
        var nodes = body.entries.keyIterator();
        while (nodes.next()) |id| {
            if (source.node(id.*).tag != .associated) continue;
            const plan = body.get(id.*);
            if (plan != .dispatch or plan.dispatch != .selected) continue;
            const invocation = plan.dispatch.selected;
            if (invocation.call.consumed == 0 or invocation.call.consumed > 2 or invocation.call.extra.items.len != 2 - invocation.call.consumed) continue;
            if (selected.items.len >= 256) return;
            try selected.append(g.allocator, .{ .node = id.*, .target = invocation.key.target });
        }
        if (selected.items.len == 0) return;
        const original = for (source.bodies[1..]) |*candidate| {
            if (candidate.root == body.root and candidate.is_function) break candidate;
        } else return;
        const units = try g.allocator.alloc(*const core.Module, g.units.len);
        defer g.allocator.free(units);
        for (g.units, units) |*unit_, *pointer| pointer.* = unit_;
        var plan = try numeric.analyzePrepared(g.allocator, source, units, original, selected.items, .{});
        errdefer plan.deinit(g.allocator);
        var checks = plan.checks.iterator();
        var improves = false;
        while (checks.next()) |check| if (check.value_ptr.* and !try g.numericCheck(self.unit_id, check.key_ptr.*)) {
            improves = true;
            break;
        };
        if (!improves) {
            plan.deinit(g.allocator);
            return;
        }
        body.numeric = plan;
        // These exact selected-body reads have no portable numeric receipt.
        // Keep the existing fresh-code boundary for the containing job.
        if (g.artifacts) |artifacts| artifacts.requireFreshCode();
    }
    fn numericCheck(self: *Emitter, id: core.Id) Error!bool {
        if (self.body) |body| if (body.numeric) |*plan| if (plan.admits(id)) return true;
        return self.generator.numericCheck(self.unit_id, id);
    }
    pub fn bodyExpression(self: *Emitter, root: core.Id, depth: usize, template: bool) Error!void {
        var body = try self.prepareBody(root, depth, template);
        defer body.deinit(self.generator.allocator);
        try self.preparedExpression(&body, root, depth, template);
    }
    /// Encodes `root` under a body prepared for it, with that body's exact
    /// substitutions in force until it returns.
    fn preparedExpression(self: *Emitter, body: *const Body, root: core.Id, depth: usize, template: bool) Error!void {
        const inference_stage = self.generator.evaluator.enterInferenceStage(.lowering);
        defer inference_stage.deinit();
        const previous_context = self.semantic_context;
        self.semantic_context = null;
        defer self.semantic_context = previous_context;
        const previous = self.body;
        self.body = body;
        defer self.body = previous;
        const old_mappings = self.mappings;
        var changed = old_mappings.len != body.mappings.len;
        if (!changed) for (old_mappings, body.mappings) |old, current| {
            if (old.variable != current.variable or old.layout != current.layout) {
                changed = true;
                break;
            }
        };
        // Ordinary bodies copy the caller's row substitutions; an instance
        // body may close the local's quantified rows.
        const old_rows = self.row_mappings;
        var rows_changed = old_rows.len != body.rows.len;
        if (!rows_changed) for (old_rows, body.rows) |old, current| {
            if (old.variable != current.variable or old.row != current.row) {
                rows_changed = true;
                break;
            }
        };
        if (rows_changed) self.row_mappings = body.rows;
        changed = changed or rows_changed;
        self.mappings = body.mappings;
        if (changed) self.layout_cache = @splat(.{});
        defer {
            self.mappings = old_mappings;
            self.row_mappings = old_rows;
            if (changed) self.layout_cache = @splat(.{});
        }
        if (template) try self.templateExpression(root, depth) else try self.expression(root, depth);
    }
    fn stagingConstant(self: *Emitter, id: core.Id) Error!core_eval.ValueId {
        const g = self.generator;
        var mappings: std.ArrayList(type_evidence.Mapping) = .empty;
        defer mappings.deinit(g.allocator);
        var rows: std.ArrayList(type_evidence.RowMapping) = .empty;
        defer rows.deinit(g.allocator);
        for (self.mappings) |mapping| {
            if (mapping.instance.decl != 0) continue;
            const actual = g.representations.toEvidence(g.evaluator.evidenceStore(), mapping.layout) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => continue,
            };
            try mappings.append(g.allocator, .{ .variable = mapping.variable, .evidence = actual });
        }
        for (self.row_mappings) |mapping| {
            if (mapping.row == layout.unknown_row) continue;
            const actual = g.representations.rowToEvidence(g.evaluator.evidenceStore(), mapping.row) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .stage_unavailable);
            try rows.append(g.allocator, .{ .variable = mapping.variable, .evidence = actual });
        }
        return g.evaluator.closedNode(self.unit_id, id, &self.static_values, mappings.items, rows.items) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            if (g.evaluator.diagnostic) |*issue| if (issue.code == .unsupported or issue.code == .const_runtime_dependency) {
                issue.code = .stage_unavailable;
            };
            return g.evaluationFailure();
        };
    }
    fn prepareStaging(self: *Emitter, id: core.Id, depth: usize) Error!StagingPlan {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        const op: @import("../check/typed_staging.zig").Op = @fromBackingInt(node.c);
        var value: core_eval.ValueId = undefined;
        if (op == .lift or op == .splice) {
            const code_value = self.staged orelse return g.fail(self.unit_id, id, .stage_unavailable);
            value = g.evaluator.stagedReplacement(code_value, id) orelse return g.fail(self.unit_id, id, .stage_unavailable);
        } else if (op == .emit) {
            value = try self.stagingConstant(node.a);
        } else {
            if (op == .quote) return g.fail(self.unit_id, id, .stage_unavailable);
            value = try self.stagingConstant(id);
        }
        if (op != .emit and op != .splice) return .{ .value = value };
        const metadata = g.evaluator.stagedInfo(value) orelse return g.fail(self.unit_id, id, .code_shape_mismatch);
        const previous_trace = g.staging_trace;
        defer g.staging_trace = previous_trace;
        @import("../check/staging_origins.zig").code(&g.staging_trace, g.evaluator.units, metadata, .{ .unit = self.unit_id, .node = id }, @import("../check/staging_origins.zig").generator(g.evaluator.storage.code_origins.items, value), op == .splice) catch |err| {
            var issue: Code = .staging_budget;
            if (err == error.InvalidOrigin) issue = .code_shape_mismatch;
            return g.fail(self.unit_id, id, issue);
        };
        var mappings: std.ArrayList(Mapping) = .empty;
        defer mappings.deinit(g.allocator);
        var rows: std.ArrayList(RowMapping) = .empty;
        defer rows.deinit(g.allocator);
        for (g.evaluator.storage.type_mappings.items[metadata.mappings.start..][0..metadata.mappings.len]) |mapping| {
            const actual = g.representations.fromEvidence(g.evaluator.evidenceStore(), mapping.evidence) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .stage_unavailable);
            try mappings.append(g.allocator, .{ .variable = mapping.variable, .layout = actual });
        }
        for (g.evaluator.storage.row_mappings.items[metadata.row_mappings.start..][0..metadata.row_mappings.len]) |mapping| {
            const actual = g.representations.rowFromEvidence(g.evaluator.evidenceStore(), mapping.evidence) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .stage_unavailable);
            try rows.append(g.allocator, .{ .variable = mapping.variable, .row = actual });
        }
        var future: Emitter = .{ .generator = g, .unit_id = metadata.unit, .function_id = self.function_id, .mappings = mappings.items, .row_mappings = rows.items, .staged = value, .provider_local = self.provider_local, .labels = self.labels, .preparation_depth = self.preparation_depth + 1, .preparing = true };
        defer future.deinit();
        const body = try g.allocator.create(Body);
        errdefer g.allocator.destroy(body);
        body.* = try future.prepareBody(metadata.identity, depth + 1, false);
        return .{ .value = value, .body = body };
    }
    fn emitStaging(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const plan = self.resolvedPlan(id).staging;
        if (plan.body) |body| {
            const metadata = g.evaluator.stagedInfo(plan.value) orelse return g.fail(self.unit_id, id, .code_shape_mismatch);
            var future: Emitter = .{ .generator = g, .unit_id = metadata.unit, .function_id = self.function_id, .mappings = body.mappings, .row_mappings = body.rows, .staged = plan.value, .provider_local = self.provider_local, .labels = self.labels, .body = body };
            defer future.deinit();
            return future.expression(metadata.identity, depth + 1);
        }
        if (g.evaluator.valueScalar(plan.value)) |value| return g.emitValue(self.function_id, value);
        const ty = try self.codeLayout(g.unit(self.unit_id).typeOf(id), g.unit(self.unit_id).span(id));
        try g.emitValue(self.function_id, .{ .scalar = .pointer, .bits = try g.static_data.serialize(g, plan.value, ty, 0) });
    }
    /// Plans are keyed by node, and one body has one set of substitutions, so
    /// each instance of a producer owns a body prepared under its facts.
    fn prepareInstances(self: *Emitter, decisions: *const InstanceDecisions, decision: *const InstanceDecision, depth: usize) Error![]LocalInstance {
        const g = self.generator;
        const producer = g.unit(self.unit_id).node(decision.statement).b;
        const instances = try g.allocator.alloc(LocalInstance, decision.count);
        var prepared: usize = 0;
        errdefer {
            for (instances[0..prepared]) |instance| {
                instance.body.deinit(g.allocator);
                g.allocator.destroy(instance.body);
            }
            g.allocator.free(instances);
        }
        var mappings: std.ArrayList(Mapping) = .empty;
        defer mappings.deinit(g.allocator);
        var rows: std.ArrayList(RowMapping) = .empty;
        defer rows.deinit(g.allocator);
        for (instances, 0..) |*instance, index| {
            mappings.clearRetainingCapacity();
            rows.clearRetainingCapacity();
            try withFacts(Mapping, g.allocator, self.mappings, decisions.factsAt(decision, index), &mappings);
            try withFacts(RowMapping, g.allocator, self.row_mappings, decisions.rowsAt(decision, index), &rows);
            const body = try g.allocator.create(Body);
            errdefer g.allocator.destroy(body);
            body.* = try self.prepareMapped(producer, depth + 1, false, mappings.items, rows.items, null);
            instance.* = .{ .layout = decision.layouts[index], .body = body };
            prepared += 1;
        }
        return instances;
    }
    /// Evaluates each instance once, in order, at the binding. Its free
    /// locals are immutable, so every instance reads the same values. A use
    /// reads the instance of its own checked layout (`emitReference`).
    fn bindInstances(self: *Emitter, statement: core.Id, instances: []const LocalInstance, depth: usize) Error!void {
        const g = self.generator;
        const n = g.unit(self.unit_id).node(statement);
        var held: InstanceLocals = .{};
        for (instances) |instance| {
            try self.preparedExpression(instance.body, n.b, depth + 1, false);
            const local = try self.temporary(g.representations.store.machine(instance.layout));
            try self.emit(.local_set, local);
            held.layouts[held.count] = instance.layout;
            held.locals[held.count] = local;
            held.count += 1;
        }
        try self.instance_locals.put(g.allocator, n.a, held);
    }
    /// Each use serializes, and so checks, a promoted value. An unused value
    /// would skip those checks, so it keeps its ordinary path.
    fn useCount(self: *Emitter, binding: core.BindingId) Error!usize {
        const source = self.generator.unit(self.unit_id);
        var count: usize = 0;
        for ((try self.generator.unitUses(self.unit_id, .{})).references.get(binding)) |index| {
            const reference = source.reference(index);
            if (reference.unit == 0 or reference.unit == self.unit_id) count += 1;
        }
        return count;
    }
    fn hasMutableUse(self: *Emitter, binding: core.BindingId) Error!bool {
        // These edges consume one physical local. An initializer's closed
        // value cannot replace the storage shared by later state versions.
        const flags = (try self.generator.unitUses(self.unit_id, .{})).flagsOf(binding);
        return flags.carried or flags.merge_branch or flags.merge_result;
    }
    fn prepareNode(self: *Emitter, body: *Body, id: core.Id, depth: usize, template: bool) Error!void {
        std.debug.assert(self.preparing);
        if (id == 0 or body.entries.contains(id)) return;
        const g = self.generator;
        const source = g.unit(self.unit_id);
        if (depth >= 1024) return g.fail(self.unit_id, id, .complexity);
        const n = source.node(id);
        if (source.has_usage_contracts and !body.has_owners) body.has_owners = @import("../check/usage_check.zig").containsNominal(&source.types, source.nominals, n.ty) catch return g.fail(self.unit_id, id, .complexity);
        if (n.tag == .staging) {
            var plan = try self.prepareStaging(id, depth);
            errdefer plan.deinit(g.allocator);
            try body.put(g.allocator, id, .{ .staging = plan });
            return;
        }
        if (n.tag == .proof_guard or (n.tag == .array_op and (source.arrayOperation(id) == .get or source.arrayOperation(id) == .set))) body.has_numeric_checks = true;
        var compile_only = false;
        if (n.tag == .bind) compile_only = @import("../check/typed_staging.zig").compileOnly(&source.types, source.binding(n.a).ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .staging_budget);
        if (compile_only) {
            const value = try self.stagingConstant(n.b);
            try self.static_values.put(g.allocator, n.a, value);
            try body.put(g.allocator, id, .{ .static_binding = value });
            return;
        }
        if (n.tag == .bind) {
            const binding = source.binding(n.a);
            const shape = source.types.node(binding.ty);
            if (binding.kind == .local and binding.scheme.variables.len != 0 and !try self.hasMutableUse(n.a)) {
                const data = shape.tag == .nominal or shape.tag == .product or shape.tag == .record;
                if (if (data) @import("../eval/closed_local_value.zig").analyze(g.units, self.unit_id, n.b) else null) |proof| {
                    if (g.artifacts) |artifacts| {
                        for (proof.dependencies[0..proof.len]) |target| try artifacts.readInlineBody(target);
                        // No completed local constant receipt yet owns this
                        // promotion's value graph across executable reuse.
                        artifacts.requireFreshCode();
                    }
                    const value = g.evaluator.closedConstructorNode(self.unit_id, n.b) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.evaluationFailure();
                    try self.static_values.put(g.allocator, n.a, value);
                    try body.put(g.allocator, id, .{ .static_binding = value });
                    return;
                }
                // Instances at different layouts share no private storage
                // (issue #10). A closed initializer that evaluates instead
                // keeps its value, and each use serializes it at its own
                // layout. Local closures keep their callable templates. It
                // may read locals that already hold values, so each link of a
                // := chain headed by a promoted value is promoted too. If
                // any use cannot be served, compilation retries without this.
                const producer = source.node(n.b).tag;
                const built = producer == .call or producer == .apply or producer == .project or producer == .construct or producer == .product or producer == .record;
                if (g.speculative_locals and built and (try self.useCount(n.a)) != 0 and self.hasErasedType(try self.codeLayout(binding.ty, source.span(id)), 0) and @import("../eval/closed_local_value.zig").dataShape(g.units, self.unit_id, binding.ty)) {
                    if (try g.evaluator.attemptClosedNode(self.unit_id, n.b, &self.static_values)) |value| {
                        // Body reads made by the evaluation are not recorded.
                        if (g.artifacts) |artifacts| artifacts.requireFreshCode();
                        g.speculated = true;
                        try self.static_values.put(g.allocator, n.a, value);
                        try body.put(g.allocator, id, .{ .static_binding = value });
                        return;
                    }
                }
            }
            // A runtime producer whose uses disagree runs once per use layout.
            if (self.local_instances) |decisions| if (decisions.find(id)) |decision| {
                const instances = try self.prepareInstances(decisions, decision, depth);
                body.put(g.allocator, id, .{ .instances = instances }) catch |err| {
                    var owned: Plan = .{ .instances = instances };
                    owned.deinit(g.allocator);
                    return err;
                };
                return;
            };
        }
        var entry: ?Plan = switch (n.tag) {
            .resource_acquire, .resource_scope => .{ .resource_scope = try self.prepareResourceScope(id) },
            .resource_release => null,
            .usage_borrow => .{ .usage_borrow = try self.prepareUsageBorrow(id) },
            .usage_share => .{ .usage_share = try self.prepareUsageShare(id) },
            .usage_read => .{ .usage_read = try self.prepareUsageRead(id) },
            .bind => private: {
                if (try self.prepareCollectionStep(body, id, depth)) |step| break :private step;
                const value = source.node(n.b);
                if (value.tag == .array_op and source.arrayOperation(n.b) == .cursor_value) {
                    const operand = source.children(n.b)[0];
                    if (source.node(operand).tag == .reference) {
                        const ref = source.reference(operand);
                        const cursor = g.representations.store.node(try self.codeLayout(source.typeOf(operand), source.span(id)));
                        if ((ref.unit == 0 or ref.unit == self.unit_id) and cursor.tag == .cursor and try g.collectionRowWords(cursor.a) != 0 and @import("private_cursor.zig").check(source, try g.unitUses(self.unit_id, .{ .flow = true }), body.root, ref.binding)) {
                            const row = g.representations.store.node(cursor.a).a;
                            if (packed_layout.rowWords(&g.representations.store, row) != 0 and row_projection_uses.checkBinding(source, body.root, id, n.a, &g.representations.store, row)) break :private .{ .private_row = row };
                        }
                    }
                }
                if (source.types.node(source.binding(n.a).ty).tag != .cursor) break :private null;
                const cursor = g.representations.store.node(try self.codeLayout(source.binding(n.a).ty, source.span(id)));
                if (cursor.tag != .cursor or g.representations.store.node(cursor.a).tag != .list or try g.collectionRowWords(cursor.a) == 0) break :private null;
                if (!@import("private_cursor.zig").check(source, try g.unitUses(self.unit_id, .{ .flow = true }), body.root, n.a)) break :private null;
                try self.prepareNode(body, n.b, depth + 1, false);
                const input = try self.privateCursorConstructor(body, n.b);
                if (input == null and source.node(n.b).tag != .reference and !(source.node(n.b).tag == .array_op and source.arrayOperation(n.b) == .cursor_advance)) break :private null;
                break :private .{ .private_cursor = .{ .input = input orelse 0 } };
            },
            .operation_value => .{ .operation = .{ .ty = try self.codeLayout(n.ty, source.span(id)), .label = try g.operationLabel(self.unit_id, n.a, self.mappings, self.row_mappings, source.span(id)) } },
            .effect_provider, .state_provider => .{ .provider = try self.prepareProvider(id) },
            .effect_reflection => return g.fail(self.unit_id, id, .backend_const_only),
            .pattern_bind => pattern: {
                if (try self.prepareCollectionStep(body, id, depth)) |step| break :pattern step;
                break :pattern try self.preparePrivateCursorPattern(body, id);
            },
            .closure, .suspend_ => .{ .template = try self.prepareTemplate(id) },
            .reference => .{ .reference = try self.prepareReference(id) },
            .project => .{ .projection = try self.prepareProjection(body, id, depth) },
            .update => .{ .update_locations = try self.prepareUpdateLocations(id) },
            .call => .{ .named = try self.prepareNamedCall(id) },
            .apply => .{ .application = try self.prepareApplication(id) },
            .scalar, .associated => .{ .dispatch = try self.resolveDispatch(id) },
            .type_same => .{ .comparison = try self.prepareTypeComparison(id) },
            .result_associated => .{ .result_member = try self.prepareResultAssociated(id) },
            .resolver_op => .{ .resolver = try self.prepareResolver(id) },
            .block, .if_value => .{ .join = try self.prepareJoin(id, if (template) .template else .value) },
            .if_stmt => .{ .join = try self.prepareJoin(id, .statement) },
            .match => .{ .match = try self.prepareMatch(id) },
            .loop => .{ .loop = try self.prepareLoop(body, id, depth) },
            .request_loop => .{ .request = try self.prepareRequestLoop(id) },
            .return_ => .{ .exit = try self.prepareReturn(id, .return_, n.b) },
            .break_ => .{ .exit = try self.prepareBreak(id) },
            else => null,
        };
        if (entry) |*owned| {
            body.put(g.allocator, id, owned.*) catch |err| {
                owned.deinit(g.allocator);
                return err;
            };
        }
        if (n.tag == .associated) body.has_associated = true;
        try self.prepareChildren(body, id, depth, template);
        if (n.tag == .call or n.tag == .apply) {
            const factory = try self.prepareFactory(body, id);
            if (n.tag == .call) body.getPtr(.named, id).factory = factory else body.getPtr(.application, id).factory = factory;
        }
    }
    fn prepareChildren(self: *Emitter, body: *Body, id: core.Id, depth: usize, template: bool) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const n = source.node(id);
        switch (n.tag) {
            .package_pack => for (source.children(id)) |child| try self.prepareNode(body, child, depth + 1, false),
            .package_unpack => try self.preparePackageBody(body, id, depth),
            .block => {
                try self.planned_returns.append(g.allocator, .{ .node = id, .template_result = template });
                defer _ = self.planned_returns.pop();
                for (source.children(id)) |child| {
                    try self.prepareNode(body, child, depth + 1, false);
                    const tag = source.node(child).tag;
                    if (tag == .return_ or tag == .break_ or source.types.node(source.typeOf(child)).tag == .never) break;
                }
            },
            .task, .suite, .product, .record, .array, .array_op, .call => for (source.children(id)) |child| {
                try self.prepareNode(body, child, depth + 1, false);
                if (n.tag == .suite and (source.node(child).tag == .return_ or source.node(child).tag == .break_ or source.types.node(source.typeOf(child)).tag == .never)) break;
            },
            .bind => try self.prepareBindingBody(body, id, depth),
            .pattern_bind => {
                const selected = body.get(id);
                if (selected == .pattern) if (selected.pattern) |bindings| {
                    for (bindings) |binding| try self.static_values.put(g.allocator, binding.binding, binding.value);
                    return;
                };
                try self.preparePattern(body, n.a, depth + 1);
                try self.prepareNode(body, n.b, depth + 1, false);
                try self.prepareNode(body, n.c, depth + 1, false);
            },
            .return_ => try self.prepareNode(body, n.a, depth + 1, body.get(id).exit.template_result),
            .break_ => for (source.breakValues(id)) |child| try self.prepareNode(body, child, depth + 1, false),
            .loop => {
                const loop = source.loopInfo(id);
                try self.prepareNode(body, loop.first, depth + 1, false);
                try self.prepareNode(body, loop.end, depth + 1, false);
                try self.planned_loops.append(g.allocator, id);
                defer _ = self.planned_loops.pop();
                try self.preparePattern(body, loop.pattern, depth + 1);
                try self.prepareNode(body, loop.body, depth + 1, false);
            },
            .request_loop => {
                const request = source.requestLoopInfo(id);
                try self.prepareNode(body, request.computation, depth + 1, false);
                for (source.requestArms(id)) |arm| {
                    try self.prepareNode(body, arm.callback, depth + 1, false);
                    if (arm.selector != 0) try self.prepareNode(body, arm.selector, depth + 1, false);
                }
                try self.planned_loops.append(g.allocator, id);
                defer _ = self.planned_loops.pop();
                try self.preparePattern(body, request.completion_pattern, depth + 1);
                try self.prepareNode(body, request.completion_body, depth + 1, false);
            },
            .match => {
                for (source.matchInputs(id)) |child| try self.prepareNode(body, child, depth + 1, false);
                for (source.matchArms(id)) |arm| {
                    for (source.armRows(arm)) |row| for (source.rowPatterns(row)) |pattern_id| try self.preparePattern(body, pattern_id, depth + 1);
                    try self.prepareNode(body, arm.guard, depth + 1, false);
                    try self.prepareNode(body, arm.body, depth + 1, false);
                    try self.prepareConstructorSubject(body, id, arm);
                }
            },
            .update => {
                const metadata = source.updateInfo(id);
                try self.prepareNode(body, metadata.root, depth + 1, false);
                for (source.updateSelectors(id)) |selector| if (selector.kind == .index) try self.prepareNode(body, selector.index, depth + 1, false);
                try self.prepareNode(body, metadata.value, depth + 1, false);
            },
            .resolver_op => {
                try self.prepareNode(body, source.resolverInfo(id).resolver, depth + 1, false);
                for (source.resolverArguments(id)) |child| try self.prepareNode(body, child, depth + 1, false);
            },
            .if_value, .if_stmt => {
                try self.prepareNode(body, n.a, depth + 1, false);
                try self.prepareNode(body, n.b, depth + 1, template);
                try self.prepareNode(body, n.c, depth + 1, template);
            },
            .resource_acquire, .scalar, .associated, .logical, .type_same, .apply, .record_merge, .handle, .usage_borrow, .proof_guard => {
                try self.prepareNode(body, n.a, depth + 1, false);
                try self.prepareNode(body, n.b, depth + 1, false);
            },
            .resource_release, .usage_share, .project, .force, .result_associated, .computation, .effect_scope, .usage_read => try self.prepareNode(body, n.a, depth + 1, false),
            .construct => try self.prepareNode(body, n.b, depth + 1, false),
            .effect_provider => {
                if (self.scopedProvider(n.ty)) try self.prepareNode(body, n.a, depth + 1, false);
                try self.prepareNode(body, n.b, depth + 1, false);
            },
            .resource_scope => {
                try self.prepareNode(body, n.a, depth + 1, false);
                try self.prepareNode(body, n.b, depth + 1, false);
                try self.prepareNode(body, n.c, depth + 1, false);
            },
            .state_provider => {
                if (self.scopedProvider(n.ty)) try self.prepareNode(body, n.a, depth + 1, false);
                try self.prepareNode(body, n.b, depth + 1, false);
                try self.prepareNode(body, n.c, depth + 1, false);
            },
            .operation_value => {
                const operation = source.operationValue(id);
                if (operation.capability != 0) try self.prepareNode(body, operation.capability, depth + 1, false);
            },
            .request_decision => {
                try self.prepareNode(body, n.b, depth + 1, false);
                try self.prepareNode(body, n.c, depth + 1, false);
            },
            else => {},
        }
    }
    fn preparePackageBody(self: *Emitter, body: *Body, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const n = source.node(id);
        try self.prepareNode(body, n.a, depth + 1, false);
        const opening = source.packageOpening(id);
        var mappings: std.ArrayList(Mapping) = .empty;
        defer mappings.deinit(g.allocator);
        try mappings.appendSlice(g.allocator, self.mappings);
        for (source.types.list(opening.binders), 0..) |binder, ordinal| try mappings.append(g.allocator, .{ .variable = binder, .layout = try g.internLayout(.opened, @intCast(ordinal), 0, &.{}) });
        @import("dictionary_layout.zig").bind(g.allocator, source, &g.representations.store, &mappings, source.typeOf(n.a), n.b, opening.binders, false) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .unresolved_type);
        const previous = self.mappings;
        self.mappings = mappings.items;
        defer self.mappings = previous;
        try self.prepareNode(body, opening.body, depth + 1, false);
    }
    fn prepareBindingBody(self: *Emitter, body: *Body, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const n = source.node(id);
        try self.prepareNode(body, n.b, depth + 1, false);
        if (try self.describeComputation(body, n.b, depth + 1)) |metadata| {
            try self.templates.put(g.allocator, n.a, metadata);
            return;
        }
        const value = source.node(n.b);
        if (value.tag == .closure and body.get(n.b).template.static_key != null) {
            try self.locals.put(g.allocator, n.a, 0);
            return;
        }
        if (value.tag == .closure or value.tag == .primitive_function or value.tag == .constructor_function) {
            const metadata = if (value.tag == .closure) body.get(n.b).template.metadata else Template{ .unit = self.unit_id, .node = n.b };
            try self.templates.put(g.allocator, n.a, metadata);
        } else if (value.tag == .computation and source.node(value.a).tag == .closure) {
            var metadata = body.get(value.a).template.metadata;
            metadata.computation = true;
            try self.templates.put(g.allocator, n.a, metadata);
        } else if (value.tag == .reference and self.templates.get(source.reference(n.b).binding) != null) {
            try self.templates.put(g.allocator, n.a, self.templates.get(source.reference(n.b).binding).?);
        } else try self.locals.put(g.allocator, n.a, 0);
    }

    // Reconstructing an unchanged immutable variant can share its cell. The
    // existing descriptor retains exact erased-payload evidence; no new field
    // is published and no unobserved type parameter needs a guessed role.
    fn prepareConstructorSubject(self: *Emitter, body: *Body, match_id: core.Id, arm: core.MatchArm) Error!void {
        const source = self.generator.unit(self.unit_id);
        const inputs = source.matchInputs(match_id);
        if (inputs.len != 1 or source.node(inputs[0]).tag != .reference) return;
        const subject = source.reference(inputs[0]);
        if (subject.unit != 0 and subject.unit != self.unit_id) return;
        if (!self.locals.contains(subject.binding)) return;
        const rows = source.armRows(arm);
        if (rows.len != 1) return;
        const patterns = source.rowPatterns(rows[0]);
        if (patterns.len != 1) return;
        const pattern = source.pattern(patterns[0]);
        if (pattern.tag != .constructor or pattern.b == 0) return;
        const payload = source.pattern(pattern.b);
        if (payload.tag != .bind or payload.a == 0) return;
        var constructed_id = arm.body;
        for (0..32) |_| {
            const node = source.node(constructed_id);
            switch (node.tag) {
                .return_ => {
                    if (node.a == 0) return;
                    constructed_id = node.a;
                },
                .block, .suite => {
                    const children = source.children(constructed_id);
                    if (children.len != 1) return;
                    constructed_id = children[0];
                },
                else => break,
            }
        }
        const constructed = source.node(constructed_id);
        if (constructed.tag != .construct or constructed.a != pattern.a or constructed.c != 0 or constructed.b == 0) return;
        if (source.node(constructed.b).tag != .reference) return;
        const reference = source.reference(constructed.b);
        if ((reference.unit != 0 and reference.unit != self.unit_id) or reference.binding != payload.a) return;
        try body.put(self.generator.allocator, constructed_id, .{ .constructor_subject = inputs[0] });
    }

    fn preparePattern(self: *Emitter, body: *Body, id: core.PatternId, depth: usize) Error!void {
        if (id == 0) return;
        const g = self.generator;
        const source = g.unit(self.unit_id);
        if (depth >= 1024) return g.fail(self.unit_id, body.root, .complexity);
        const pattern = source.pattern(id);
        switch (pattern.tag) {
            .value => try self.prepareNode(body, pattern.a, depth + 1, false),
            .bind => if (pattern.a != 0) try self.locals.put(g.allocator, pattern.a, 0),
            .product => for (source.patternChildren(id)) |child| try self.preparePattern(body, child, depth + 1),
            .constructor, .record_payload => try self.preparePattern(body, pattern.b, depth + 1),
            else => {},
        }
    }
    fn staticCallableValue(self: *Emitter, id: core.Id, remaining: *usize, depth: usize) Error!?core_eval.ValueId {
        if (remaining.* == 0 or depth >= 64) return null;
        remaining.* -= 1;
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        if (node.tag == .reference) {
            const reference = source.reference(id);
            if (reference.unit == 0 or reference.unit == self.unit_id) return self.static_values.get(reference.binding);
            return null;
        }
        if (node.tag != .project) return null;
        const container_value = (try self.staticCallableValue(node.a, remaining, depth + 1)) orelse return null;
        const projection = source.projection(node.b);
        if (projection.nominal.unit != 0 or projection.nominal.decl != 0) return null;
        const info = g.evaluator.valueInfo(container_value);
        if (projection.field != 0) {
            if (info.kind != .record) return null;
            for (g.evaluator.recordFieldNames(container_value), 0..) |name, index| {
                if (remaining.* == 0) return null;
                remaining.* -= 1;
                if (name == projection.field) return g.evaluator.valueChildren(container_value)[index];
            }
            return null;
        }
        if (info.kind != .product or projection.variants.len != 1) return null;
        const variant = source.projectionVariants(node.b)[0];
        if (variant.tag != 0 or variant.field >= info.len) return null;
        return g.evaluator.valueChildren(container_value)[variant.field];
    }
    fn staticCallableTemplate(self: *Emitter, id: core.Id) Error!?Template {
        if (self.static_values.count() == 0) return null;
        const g = self.generator;
        var remaining: usize = 65_536;
        const value = (try self.staticCallableValue(id, &remaining, 0)) orelse return null;
        if (g.evaluator.valueInfo(value).kind != .closure) return null;
        const metadata = g.evaluator.closureInfo(value);
        if (metadata.origin != .named or metadata.applied != 0 or metadata.mappings.len != 0 or metadata.row_mappings.len != 0) return null;
        const target: core.BindingRef = .{ .unit = metadata.unit, .binding = metadata.identity };
        // Reuse an owned reference node to this exact evaluated producer. No
        // source name, function arrow or first matching effect row selects it.
        for (g.units, 1..) |*owner, ordinal| {
            const unit: u32 = if (owner.unit == 0) @intCast(ordinal) else owner.unit;
            for (owner.nodes, 0..) |node, index| {
                if (remaining == 0) return null;
                remaining -= 1;
                if (node.tag != .reference) continue;
                const normalized = try g.normalize(unit, owner.reference(@intCast(index)));
                if (!std.meta.eql(normalized, target)) continue;
                return .{ .unit = unit, .node = @intCast(index), .callable_instances = try self.scopedCallableTargetInstances(id, target) };
            }
        }
        return null;
    }
    fn describeCallable(self: *Emitter, body: *const Body, id: core.Id) Error!?Template {
        if (try self.staticCallableTemplate(id)) |template| return template;
        const source = self.generator.unit(self.unit_id);
        const node = source.node(id);
        if (node.tag == .closure or node.tag == .suspend_) return body.get(id).template.metadata;
        if (node.tag == .primitive_function or node.tag == .constructor_function) return .{ .unit = self.unit_id, .node = id, .callable_instances = try self.scopedCallableInstances(id) };
        if (node.tag != .reference) return null;
        const reference = source.reference(id);
        if (reference.unit == 0 or reference.unit == self.unit_id) {
            if (self.templates.get(reference.binding)) |metadata| return try self.templateAt(metadata, id);
            const kind = source.binding(reference.binding).kind;
            if (kind != .global and kind != .external) return null;
        }
        return .{ .unit = self.unit_id, .node = id, .callable_instances = try self.scopedCallableInstances(id) };
    }
    fn describeComputation(self: *Emitter, body: *const Body, id: core.Id, depth: usize) Error!?Template {
        if (id == 0) return null;
        const g = self.generator;
        const source = g.unit(self.unit_id);
        if (depth >= 1024) return g.fail(self.unit_id, id, .complexity);
        const node = source.node(id);
        switch (node.tag) {
            .computation, .effect_scope => {
                var metadata = try self.describeCallable(body, node.a) orelse return null;
                metadata.computation = true;
                return metadata;
            },
            .reference => {
                const reference = source.reference(id);
                if (reference.unit == 0 or reference.unit == self.unit_id) if (self.templates.get(reference.binding)) |metadata| if (metadata.computation) return metadata;
                return null;
            },
            .call => return if (body.get(id).named.factory) |factory| factory.result else null,
            .apply => return if (body.get(id).application.factory) |factory| factory.result else null,
            .block => {
                for (source.children(id)) |statement| {
                    const value = source.node(statement);
                    if (value.tag == .return_ and value.b == id) return self.describeComputation(body, value.a, depth + 1);
                }
                return null;
            },
            .if_value => {
                const left = try self.describeComputation(body, node.b, depth + 1) orelse return null;
                const right = try self.describeComputation(body, node.c, depth + 1) orelse return null;
                if (try g.captureTemplate(left) != try g.captureTemplate(right)) return g.fail(self.unit_id, id, .unresolved_type);
                return left;
            },
            else => return null,
        }
    }
    fn prepareFactory(self: *Emitter, body: *const Body, id: core.Id) Error!?FactoryPlan {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        const result_type = source.types.node(node.ty);
        if (result_type.tag != .nominal or result_type.a != std.math.maxInt(u32) or result_type.b != 5) return null;
        if (self.preparation_depth >= 256) return g.fail(self.unit_id, id, .complexity);
        var admitted: [max_parameters]bool = @splat(false);
        var callee: @FieldType(FactoryPlan, "callee") = undefined;
        var owner: u32 = undefined;
        var root: core.Id = undefined;
        var mappings: std.ArrayList(Mapping) = .empty;
        var rows: std.ArrayList(RowMapping) = .empty;
        defer mappings.deinit(g.allocator);
        defer rows.deinit(g.allocator);
        var preparer: Emitter = .{ .generator = g, .unit_id = 0, .function_id = self.function_id, .mappings = &.{}, .factory_template = true, .preparation_depth = self.preparation_depth + 1, .preparing = true };
        defer preparer.deinit();
        if (node.tag == .call) {
            const call = source.call(id);
            var key = body.get(id).named.call.key;
            if (key.count != call.arguments.len or self.computationAction(key.result) == null) return null;
            const producer = g.unit(key.target.unit);
            const definition = producer.body(key.target.binding) orelse return null;
            if (!definition.is_function or definition.parameters.len != key.count) return null;
            for (call.arguments, 0..) |argument, i| admitted[i] = self.isCallableTemplate(argument);
            if (!self.factoryTemplateResult(key.target.unit, definition.root, producer.bodyParameters(definition), admitted[0..key.count], 0)) return null;
            var entries: std.ArrayList(substitution_keys.Entry) = .empty;
            defer entries.deinit(g.allocator);
            for (call.arguments, producer.bodyParameters(definition), 0..) |argument, parameter, i| {
                if (admitted[i]) {
                    key.parameters[i] = try self.sourceArgumentLayout(key.parameters[i], try self.codeLayout(source.typeOf(argument), source.span(argument)), 0);
                    const metadata = try self.describeCallable(body, argument) orelse return g.fail(self.unit_id, argument, .unresolved_type);
                    try entries.append(g.allocator, .{ .variable = parameter.binding, .value = try g.captureTemplate(metadata) });
                    try preparer.templates.put(g.allocator, parameter.binding, metadata);
                } else if (parameter.binding != 0) try preparer.locals.put(g.allocator, parameter.binding, 0);
            }
            key.templates = g.representations.template_keys.intern(entries.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .complexity);
            key.template_result = true;
            var service = try g.specializer();
            var resolved = service.named(key, g.representations.instance_arguments.get(key.instance_arguments)) catch |err| return g.specializationFailure(service, err);
            defer resolved.deinit(g.allocator);
            try mappings.appendSlice(g.allocator, resolved.mappings.items);
            try rows.appendSlice(g.allocator, resolved.rows.items);
            callee = .{ .named = key };
            owner = key.target.unit;
            root = definition.root;
        } else {
            if (!self.isCallableTemplate(node.a)) return null;
            const factory = try self.describeCallable(body, node.a) orelse return null;
            owner = factory.unit;
            if (owner == 0) owner = self.unit_id;
            const producer = g.unit(owner);
            const factory_node = producer.node(factory.node);
            if (factory_node.tag != .closure) return null;
            const metadata = producer.closures[factory_node.a];
            admitted[0] = self.isCallableTemplate(node.b);
            if (!self.factoryTemplateResult(owner, metadata.body, &.{metadata.parameter}, admitted[0..1], 0)) return null;
            var ty = try self.codeLayout(source.typeOf(node.a), source.span(id));
            if (admitted[0]) {
                const arrow = g.representations.store.node(ty);
                ty = try g.internLayoutWithEffects(.function, try self.sourceArgumentLayout(arrow.a, try self.codeLayout(source.typeOf(node.b), source.span(node.b)), 0), arrow.b, arrow.c, &.{});
            }
            var key: ClosureKey = .{ .unit = owner, .catalog = factory_node.a, .ty = ty, .scalar_environment = factory.scalar_environment, .captures = factory.captures, .templates = factory.templates, .evidence = factory.evidence, .rows = factory.rows, .template_result = true };
            if (admitted[0]) {
                const argument = try self.describeCallable(body, node.b) orelse return g.fail(self.unit_id, node.b, .unresolved_type);
                key.parameter_template = try g.captureTemplate(argument);
                try preparer.templates.put(g.allocator, metadata.parameter.binding, argument);
            } else if (metadata.parameter.binding != 0) try preparer.locals.put(g.allocator, metadata.parameter.binding, 0);
            try g.resolveClosureMappings(key, &mappings, &rows);
            for (producer.extra[metadata.captures.start..][0..metadata.captures.len], 0..) |binding, index| {
                if (g.capturedTemplate(key.templates, binding)) |captured| {
                    try preparer.templates.put(g.allocator, binding, .{ .unit = captured.unit, .node = captured.node, .environment = if (captured.has_environment) 0 else null, .captures = captured.captures, .templates = captured.templates, .scalar_environment = captured.scalar_environment, .demand_cell = captured.demand_cell, .computation = captured.computation, .evidence = captured.evidence, .rows = captured.rows });
                } else {
                    _ = index;
                    try preparer.locals.put(g.allocator, binding, 0);
                }
            }
            callee = .{ .closure = key };
            root = metadata.body;
        }
        preparer.unit_id = owner;
        preparer.mappings = mappings.items;
        preparer.row_mappings = rows.items;
        var prepared = try Body.init(g.allocator, owner, root, mappings.items, rows.items);
        defer prepared.deinit(g.allocator);
        try preparer.prepareNode(&prepared, root, 0, true);
        var result = try preparer.describeComputation(&prepared, root, 0) orelse return g.fail(owner, root, .unresolved_type);
        result.scalar_environment = false;
        return .{ .callee = callee, .admitted = admitted, .result = result };
    }

    fn codeLayout(self: *Emitter, ty: types.Id, span: core.Span) Error!layout.Id {
        const g = self.generator;
        g.planning.facts.stats.layout_requests += 1;
        const slot = &self.layout_cache[ty % self.layout_cache.len];
        if (slot.ty == ty and slot.value != 0) {
            g.planning.facts.stats.layout_reused += 1;
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
        root_slot: ?u32 = null,
        machine: wasm.ValueType,
        role: ir.Role,

        fn root(self: InlineDemand) ?u32 {
            if (self.role == .scalar) return null;
            return self.value;
        }
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
            const analysis = @import("demand_inline.zig").Plan.analyzeGraph(g.units, target, body);
            g.evaluator.counters.demand_inline_nodes += analysis.visited;
            const child = analysis.plan orelse return false;
            for (call.arguments, 0..) |argument, i| {
                if (self.hasErasedType(key.parameters[i], 0)) return false;
                if (g.representations.store.node(key.parameters[i]).tag == .demand and source.node(argument).tag != .suspend_) return false;
            }
            var next_mappings: std.ArrayList(Mapping) = .empty;
            var next_rows: std.ArrayList(RowMapping) = .empty;
            defer next_mappings.deinit(g.allocator);
            defer next_rows.deinit(g.allocator);
            try g.seedNamedInstance(key, &next_mappings);
            for (target.bodyParameters(body), 0..) |parameter, i| {
                try g.mapTypeDepth(key.target.unit, &next_mappings, &next_rows, parameter.ty, key.parameters[i], body.span, 0);
            }
            try g.mapTypeDepth(key.target.unit, &next_mappings, &next_rows, target.typeOf(body.root), key.result, body.span, 0);
            if (!try self.demandCallShapes(key.target.unit, &child, next_mappings.items, next_rows.items, depth + 1)) return false;
        }
        return true;
    }

    fn demandSummary(self: *Emitter, target: core.BindingRef) Error!?*const @import("demand_summary.zig").Summary {
        std.debug.assert(self.preparing);
        const demand = @import("demand_summary.zig");
        const g = self.generator;
        const owner = g.demand_owner orelse return null;
        const table = &owner.demand_summaries;
        const key = demand.keyFor(g.units, target, .{});
        var cursor = table.candidates(demand.fingerprint(key), .oldest_first);
        while (cursor.next()) |position| {
            const record = &table.records.items[position];
            if (!std.meta.eql(record.key, key)) continue;
            g.evaluator.counters.demand_summary_hits += 1;
            return &record.value;
        }
        const analysis = try demand.analyzeCached(g.allocator, g.units, target, key.limits, &g.evaluator.counters, table);
        const installed = try demand.insert(g.allocator, table, key, analysis.dependencies, analysis.summary) orelse return null;
        return &table.records.items[installed].value;
    }

    fn prepareDemandCall(self: *Emitter, key: Key, arguments: []const core.Id) Error!DemandDecision {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const source = g.unit(key.target.unit);
        const body = source.body(key.target.binding) orelse return .{ .reason = .unavailable_body };
        if (body.parameters.len != key.count) return .{ .reason = .unresolved_shape };
        var has_demand = false;
        for (source.bodyParameters(body)) |parameter| if (source.types.node(parameter.ty).tag == .demand) {
            has_demand = true;
        };
        if (!has_demand) return .{ .reason = .unresolved_shape };
        const analysis = @import("demand_inline.zig").Plan.analyzeGraph(g.units, source, body);
        g.evaluator.counters.demand_inline_nodes += analysis.visited;
        const shape = analysis.plan orelse {
            _ = try self.demandSummary(key.target);
            return .{ .reason = analysis.reason };
        };
        if (arguments.len != key.count) return .{ .reason = .unresolved_shape };
        var uses = shape.uses;
        if (try self.demandSummary(key.target)) |facts| {
            var summary_uses: [max_parameters]u8 = @splat(0);
            var known = true;
            for (source.bodyParameters(body), 0..) |parameter, i| {
                if (source.types.node(parameter.ty).tag != .demand) continue;
                const fact = facts.parameter(i);
                // The summary conservatively treats closure captures as an
                // escape. A complete lexical-callback proof checks every use.
                if (fact.outcome() == .escaping) {
                    if (!shape.local_callbacks) return .{ .reason = .escaping_use };
                    known = false;
                }
                if (fact.outcome() == .unknown) known = false;
                summary_uses[i] = fact.count;
            }
            if (known) uses = summary_uses;
        }
        const caller = g.unit(self.unit_id);
        for (arguments, 0..) |argument, i| {
            if (self.hasErasedType(key.parameters[i], 0)) return .{ .reason = .unresolved_shape };
            if (g.representations.store.node(key.parameters[i]).tag == .demand and caller.node(argument).tag != .suspend_) return .{ .reason = .unresolved_shape };
        }
        var mappings: std.ArrayList(Mapping) = .empty;
        var rows: std.ArrayList(RowMapping) = .empty;
        defer mappings.deinit(g.allocator);
        defer rows.deinit(g.allocator);
        try g.seedNamedInstance(key, &mappings);
        for (source.bodyParameters(body), 0..) |parameter, i| try g.mapTypeDepth(key.target.unit, &mappings, &rows, parameter.ty, key.parameters[i], body.span, 0);
        try g.mapTypeDepth(key.target.unit, &mappings, &rows, source.typeOf(body.root), key.result, body.span, 0);
        if (!try self.demandCallShapes(key.target.unit, &shape, mappings.items, rows.items, 0)) return .{ .reason = .unresolved_control };
        if (g.artifacts) |artifacts| {
            try artifacts.readInlineBody(key.target);
            if (g.demand_owner) |owner| {
                const demand = @import("demand_summary.zig");
                const summary_key = demand.keyFor(g.units, key.target, .{});
                var cursor = owner.demand_summaries.candidates(demand.fingerprint(summary_key), .oldest_first);
                while (cursor.next()) |position| {
                    const record = &owner.demand_summaries.records.items[position];
                    if (!std.meta.eql(record.key, summary_key)) continue;
                    for (record.dependencies.bodies) |dependency| try artifacts.readInlineBody(dependency);
                    break;
                }
            }
        }
        return .{ .plan = .{ .uses = uses }, .reason = .proved_local };
    }
    fn inlineDemandCall(self: *Emitter, key: Key, arguments: []const core.Id, prepared: ?DemandPlan, depth: usize) Error!bool {
        const plan = prepared orelse return false;
        const g = self.generator;
        const source = g.unit(key.target.unit);
        const body = source.body(key.target.binding).?;
        const caller = g.unit(self.unit_id);
        var mappings: std.ArrayList(Mapping) = .empty;
        var rows: std.ArrayList(RowMapping) = .empty;
        defer mappings.deinit(g.allocator);
        defer rows.deinit(g.allocator);
        try g.seedNamedInstance(key, &mappings);
        for (source.bodyParameters(body), 0..) |parameter, i| {
            try g.mapTypeDepth(key.target.unit, &mappings, &rows, parameter.ty, key.parameters[i], body.span, 0);
        }
        try g.mapTypeDepth(key.target.unit, &mappings, &rows, source.typeOf(body.root), key.result, body.span, 0);
        var emitter: Emitter = .{ .generator = g, .unit_id = key.target.unit, .function_id = self.function_id, .provider_local = self.provider_local, .mappings = mappings.items, .row_mappings = rows.items, .cleanups = .{ .parent = &self.cleanups }, .diagnostic_context = try self.inlineContext(), .labels = self.labels };
        defer emitter.deinit();
        var demands: [max_parameters]InlineDemand = undefined;
        var count: usize = 0;
        // Eager arguments still run once, left to right. Deferred expressions
        // retain the caller's immutable binding versions, without an object.
        for (arguments, source.bodyParameters(body), 0..) |argument, parameter, i| {
            const ty = g.representations.store.node(key.parameters[i]);
            if (ty.tag != .demand) {
                const local = try self.capture(argument, depth);
                if (parameter.binding != 0) try emitter.locals.put(g.allocator, parameter.binding, local);
                continue;
            }
            const uses = plan.uses[i];
            if (uses == 0) {
                g.evaluator.counters.demand_eliminated += 1;
                try g.demandSite(self.unit_id, argument, .eliminated, .unused);
            } else if (uses == 1) {
                g.evaluator.counters.demand_direct += 1;
                try g.demandSite(self.unit_id, argument, .direct, .proved_local);
            } else {
                g.evaluator.counters.demand_local_memo_slots += 2;
                try g.demandSite(self.unit_id, argument, .local_memo, .repeated_local);
            }
            const machine = g.representations.store.machine(ty.a);
            const memo = uses > 1;
            var memo_value: ?u32 = null;
            var memo_ready: ?u32 = null;
            var memo_root: ?u32 = null;
            if (memo) {
                memo_value = try self.temporary(machine);
                memo_ready = try self.temporary(.i32);
                if (g.layoutRole(ty.a) == .reference) {
                    // A first force inside a callee iteration must survive
                    // that iteration. Reserve its owner in the caller frame.
                    memo_root = try self.temporary(.i32);
                    g.evaluator.counters.demand_local_memo_slots += 1;
                    try self.rootDirective(3, memo_root.?);
                }
            }
            demands[count] = .{
                .binding = parameter.binding,
                .caller = self,
                .expression = caller.closures[caller.node(argument).a].body,
                .value = memo_value,
                .ready = memo_ready,
                .root_slot = memo_root,
                .machine = machine,
                .role = g.layoutRole(ty.a),
            };
            // The call may occur inside a loop; Wasm local initialization alone
            // would incorrectly share a result across successive invocations.
            if (demands[count].ready) |ready| {
                if (demands[count].role != .scalar) {
                    if (machine == .f32) {
                        try self.emit(.f32_const, 0);
                    } else {
                        try self.emit(.i32_const, 0);
                    }
                    try self.emit(.local_set, demands[count].value.?);
                }
                try self.emit(.i32_const, 0);
                try self.emit(.local_set, ready);
            }
            count += 1;
        }
        emitter.inline_demands = demands[0..count];
        try emitter.bodyExpression(body.root, depth + 1, false);
        return true;
    }

    fn memoParent(self: *const Emitter) ?*const Emitter {
        if (self.inline_demands.len == 0) return null;
        return self.inline_demands[0].caller;
    }

    fn inlineDemandBinding(self: *const Emitter, binding: core.BindingId) ?*const InlineDemand {
        const source = self.generator.unit(self.unit_id);
        var current = binding;
        for (0..64) |_| {
            for (self.inline_demands) |*demand| if (demand.binding == current) return demand;
            const initializer = source.binding(current).initializer;
            if (initializer == 0 or source.node(initializer).tag != .reference) return null;
            const reference = source.reference(initializer);
            if (reference.unit != 0 and reference.unit != self.unit_id) return null;
            current = reference.binding;
        }
        return null;
    }

    fn inlineDemand(self: *Emitter, id: core.Id, depth: usize) Error!bool {
        const source = self.generator.unit(self.unit_id);
        const operand = source.node(id).a;
        if (source.node(operand).tag != .reference) return false;
        const reference = source.reference(operand);
        if (reference.unit != 0 and reference.unit != self.unit_id) return false;
        if (self.inlineDemandBinding(reference.binding)) |demand| {
            if (demand.ready) |ready| {
                try self.emit(.local_get, ready);
                try self.emit(.if_, @backingInt(demand.machine));
                self.labels += 1;
                try self.emit(.local_get, demand.value.?);
                try self.emit(.else_, 0);
            }
            // Preserve creation-time binding versions while borrowing the
            // force site's provider, labels and cancellation obligations. The
            // snapshot includes callee loop scratch, without a parent cycle.
            const inherited = try self.cleanups.snapshot(self.generator.allocator);
            const saved_cleanups = demand.caller.cleanups;
            demand.caller.cleanups = inherited;
            defer {
                demand.caller.cleanups.deinit(self.generator.allocator);
                demand.caller.cleanups = saved_cleanups;
            }
            const saved_labels = demand.caller.labels;
            demand.caller.labels = self.labels;
            defer demand.caller.labels = saved_labels;
            const saved_provider = demand.caller.provider_local;
            demand.caller.provider_local = self.provider_local;
            defer demand.caller.provider_local = saved_provider;
            try demand.caller.bodyExpression(demand.expression, depth + 1, false);
            if (demand.ready) |ready| {
                try self.emit(.local_set, demand.value.?);
                if (demand.root_slot) |slot| try self.rootDirective(4, slot | (demand.value.? << 13));
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
        if (g.artifacts) |artifacts| {
            try artifacts.readInlineBody(plan.target);
            if (plan.forwarded_target) |target| try artifacts.readInlineBody(target);
        }
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
            var emitter: Emitter = .{ .generator = g, .unit_id = plan.target.unit, .function_id = self.function_id, .provider_local = self.provider_local, .mappings = mappings.items, .row_mappings = rows.items, .cleanups = .{ .parent = &self.cleanups }, .diagnostic_context = try self.inlineContext(), .labels = self.labels, .owned_edit = if (try g.ownsArrayUpdate(self.unit_id, id)) plan.edit else null };
            defer emitter.deinit();
            for (producer.bodyParameters(body), 0..) |parameter, i| if (parameter.binding != 0) try emitter.locals.put(g.allocator, parameter.binding, values[i]);
            try emitter.bodyExpression(body.root, depth + 1, false);
            return true;
        }
        const order = plan.positions;
        const result = try self.codeLayout(source.typeOf(id), source.span(id));
        var operands: [3]u32 = undefined;
        var machines: [3]wasm.ValueType = undefined;
        for (order[0..plan.count], 0..) |position, i| {
            operands[i] = values[position];
            machines[i] = g.representations.store.machine(key.parameters[position]);
        }
        try self.arrayLocals(id, plan.op, operands[0..plan.count], machines[0..plan.count], result, key.parameters[order[0]]);
        return true;
    }

    /// A direct wrapper of a shuffle, swizzle or broadcast takes its lane
    /// selectors from this call's literal argument. A wrapper of select or
    /// relaxed madd lowers here too, so its operand pair never boxes.
    fn inlineSimdCall(self: *Emitter, id: core.Id, key: Key, depth: usize) Error!bool {
        const g = self.generator;
        const plan = @import("simd_call.zig").analyze(g.units, self.unit_id, id) orelse return false;
        if (key.count != plan.count or !std.meta.eql(plan.target, key.target)) return false;
        if (g.artifacts) |artifacts| try artifacts.readInlineBody(plan.target);
        var lanes: ?[4]u8 = null;
        if (plan.lanes) |position| lanes = self.simdLaneLiterals(plan.arguments[position], plan.op) orelse return g.fail(self.unit_id, plan.arguments[position], .simd_lane_literal);
        var values: [3]u32 = undefined;
        for (plan.arguments[0..plan.count], 0..) |argument, i| {
            if (plan.lanes != i) values[i] = try self.capture(argument, depth);
        }
        var operands: [3]u32 = undefined;
        var count: usize = 0;
        for (plan.vectors[0..plan.vector_count], 0..) |position, i| {
            if (plan.pair_parameter and i + 1 == plan.vector_count) {
                var pair: [2]u32 = undefined;
                try self.simdPairLocals(values[position], &pair);
                operands[count..][0..2].* = pair;
                count += 2;
            } else {
                operands[count] = values[position];
                count += 1;
            }
        }
        const source = g.unit(self.unit_id);
        const result = try self.codeLayout(source.typeOf(id), source.span(id));
        try self.simdLocals(plan.op, operands[0..count], lanes, result, result);
        return true;
    }

    fn inlineNamedCall(self: *Emitter, key: Key, arguments: []const core.Id, depth: usize) Error!bool {
        if (!self.generator.inline_named) return false;
        return self.inlineNamedValues(key, arguments, null, depth);
    }
    fn inlineNamedValues(self: *Emitter, key: Key, arguments: []const core.Id, captured: ?[]const u32, depth: usize) Error!bool {
        return self.inlineNamedValuesMode(key, arguments, captured, depth, null);
    }
    fn borrowedRowArgument(self: *const Emitter, id: core.Id) ?RowView {
        const source = self.generator.unit(self.unit_id);
        if (source.node(id).tag != .reference) return null;
        const reference = source.reference(id);
        if (reference.unit != 0 and reference.unit != self.unit_id) return null;
        var index = self.row_views.items.len;
        while (index != 0) {
            index -= 1;
            const view = self.row_views.items[index];
            if (view.binding == reference.binding) return view;
        }
        return null;
    }
    fn readsRow(self: *Emitter, source: *const core.Module, root: core.Id, binding: core.BindingId, row: layout.Id) Error!bool {
        const g = self.generator;
        if (try g.nestedRow(row)) |plan| return row_projection_uses.checkNumeric(source, root, binding, &g.representations.store, &plan);
        return row_projection_uses.check(source, root, binding, &g.representations.store, row);
    }
    // Preparation owns the large mapping/initialization frame. It returns
    // before recursively emitting an inlined body, so deep call graphs retain
    // only the small emission continuation on the native stack.
    fn prepareNamedInline(self: *Emitter, key: Key, arguments: []const core.Id, captured: ?[]const u32, small_result: ?*SmallCollection, mappings: *std.ArrayList(Mapping), rows: *std.ArrayList(RowMapping), borrowed_collections: *u16) Error!?*Emitter {
        const g = self.generator;
        // An inlined principal needs its own lexical dictionary frame. Keep
        // this call on the stored ABI rather than infer authority from layouts.
        if (self.dictionary_owner != null) return null;
        if (self.inline_depth >= 6 or g.module.functions.items[self.function_id].codeLength() > 4096 or (if (captured) |values| values.len != key.count else arguments.len < key.count) or key.templates != 0 or key.template_result) return null;
        const source = g.unit(key.target.unit);
        const body = source.body(key.target.binding) orelse return null;
        if (!body.is_function or body.parameters.len != key.count) return null;
        const facts = try g.planning.facts.get(g.allocator, g.units, key.target);
        borrowed_collections.* = facts.borrowed_collections;
        const in_loop = self.inline_loop or self.loop_targets.items.len != 0;
        // Opaque constructors and projections are representation adapters even
        // outside loops. Expose their bounded source bodies before freezing
        // RuntimeIR; readInlineBody below retains the exact executable read.
        var expose_data = small_result != null or (in_loop and self.inlineDataType(key.result)) or self.inlineOpaqueType(key.result);
        for (key.parameters[0..key.count]) |ty| expose_data = expose_data or self.inlineOpaqueType(ty);
        if (captured == null) for (key.parameters[0..key.count], arguments[0..key.count], 0..) |ty, argument, i| {
            expose_data = expose_data or (g.representations.store.node(ty).tag == .function and self.isCallableTemplate(argument));
            if (i < 16 and facts.borrowed_collections & (@as(u16, 1) << @intCast(i)) != 0 and self.smallCollectionCandidate(argument)) expose_data = true;
            if (in_loop and try g.rowWords(ty) != 0) expose_data = true;
        };
        const ordinary_limit: u16 = if (expose_data) 64 else 4;
        var numeric_limit: u16 = 0;
        if (facts.inline_cost == null or facts.inline_cost.? > ordinary_limit) {
            numeric_limit = try self.numericInlineBudget(key.result);
            for (key.parameters[0..key.count]) |ty| numeric_limit = @max(numeric_limit, try self.numericInlineBudget(ty));
        }
        const inline_cost = facts.inline_cost orelse (if (numeric_limit != 0) @import("inline_body.zig").numericCost(source, body.root) else null) orelse return null;
        if (inline_cost > @max(ordinary_limit, numeric_limit) or self.hasErasedType(key.result, 0)) return null;
        for (key.parameters[0..key.count]) |ty| if (self.hasErasedType(ty, 0) or g.representations.store.node(ty).tag == .demand) return null;
        try g.seedNamedInstance(key, mappings);
        var source_type = try g.functionRoot(key.target.unit, source.binding(key.target.binding).ty, body.span);
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
        const diagnostic_context = try self.inlineContext();
        const emitter = try g.allocator.create(Emitter);
        emitter.* = .{ .generator = g, .unit_id = key.target.unit, .function_id = self.function_id, .provider_local = self.provider_local, .mappings = mappings.items, .row_mappings = rows.items, .cleanups = .{ .parent = &self.cleanups }, .diagnostic_context = diagnostic_context, .labels = self.labels, .inline_depth = self.inline_depth + 1, .inline_loop = in_loop };
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
            if (self.borrowedRowArgument(argument)) |borrowed| {
                if (parameter.binding != 0 and key.parameters[i] == borrowed.row and try self.readsRow(source, body.root, parameter.binding, borrowed.row)) {
                    var view = borrowed;
                    view.binding = parameter.binding;
                    try emitter.row_views.append(g.allocator, view);
                    continue;
                }
            }
            if (i < 16 and borrowed_collections & (@as(u16, 1) << @intCast(i)) != 0) if (try self.captureSmallCollection(argument, depth)) |values| {
                if (parameter.binding != 0) try emitter.small_values.put(g.allocator, parameter.binding, values);
                continue;
            };
            if (g.representations.store.node(key.parameters[i]).tag == .function and self.static_values.count() == 0 and self.isCallableTemplate(argument)) {
                const template = (try self.callableTemplate(argument)).?;
                if (parameter.binding != 0) try emitter.templates.put(g.allocator, parameter.binding, template);
            } else {
                const value = try self.capture(argument, depth);
                if (parameter.binding != 0) try emitter.locals.put(g.allocator, parameter.binding, value);
            }
        }
        const remaining = if (captured != null) &.{} else arguments[key.count..];
        var prepared_body = try emitter.prepareBody(body.root, depth + 1, false);
        defer prepared_body.deinit(g.allocator);
        emitter.body = &prepared_body;
        // Encoding reads the substitutions the plans were prepared under,
        // including local storage and ambiguous-variable facts.
        emitter.mappings = prepared_body.mappings;
        emitter.row_mappings = prepared_body.rows;
        emitter.layout_cache = @splat(.{});
        if (remaining.len != 0 and try emitter.saturatedAssociated(body.root, self, remaining, depth)) return true;
        if (remaining.len == 0 and small_result == null and try emitter.emitOpaqueAdapterBody(body.root, depth + 1)) return true;
        try emitter.expression(body.root, depth + 1);
        var ty = key.result;
        for (remaining) |argument| {
            const arrow = g.representations.store.node(ty);
            const callee = try self.temporary(.i32);
            try self.emit(.local_set, callee);
            const value = try self.capture(argument, depth);
            try self.emit(.local_get, callee);
            try self.emit(.i32_load, heap.offset(heap.Closure, "environment"));
            try self.emit(.local_get, value);
            try self.providerHead();
            try self.emit(.local_get, callee);
            try self.emit(.i32_load, heap.offset(heap.Closure, "function"));
            try self.generator.module.emit(self.function_id, ir.callResult(g.layoutRole(arrow.b)));
            try self.emit(.call_indirect, try g.module.internType(&.{ .i32, g.representations.store.machine(arrow.a), .i32 }, g.representations.store.machine(arrow.b)));
            ty = arrow.b;
        }
        return true;
    }

    // An unpack-only prefix and its final pure projection need no result
    // block or local copies. Validate the entire path before changing locals;
    // source bodies and executable dependencies still use the ordinary inliner.
    fn emitOpaqueAdapterBody(self: *Emitter, root: core.Id, depth: usize) Error!bool {
        if (self.small_result != null) return false;
        const source = self.generator.unit(self.unit_id);
        if (source.node(root).tag != .block) return false;
        const statements = source.children(root);
        if (statements.len < 2 or statements.len > 9) return false;
        const result = source.node(statements[statements.len - 1]);
        if (result.tag != .return_ or result.b != root) return false;
        const Alias = struct { binding: core.BindingId, local: u32 };
        var aliases: [8]Alias = undefined;
        var count: usize = 0;
        for (statements[0 .. statements.len - 1]) |statement| {
            const node = source.node(statement);
            if (node.tag != .pattern_bind or node.c != 0 or source.node(node.b).tag != .reference) return false;
            const reference = source.reference(node.b);
            if ((reference.unit != 0 and reference.unit != self.unit_id) or try self.hasMutableUse(reference.binding)) return false;
            const local = self.locals.get(reference.binding) orelse local: {
                for (aliases[0..count]) |alias| if (alias.binding == reference.binding) break :local alias.local;
                return false;
            };
            var pattern_id = node.a;
            var found_opaque = false;
            const binding = for (0..32) |_| {
                const pattern = source.pattern(pattern_id);
                switch (pattern.tag) {
                    .constructor => {
                        const nominal = source.nominal(source.constructor(pattern.a).nominal);
                        if (!nominal.is_opaque or nominal.storage.kind == .unknown or nominal.affine or nominal.has_usage or pattern.b == 0) return false;
                        found_opaque = true;
                        pattern_id = pattern.b;
                    },
                    .bind => break pattern.a,
                    .wildcard => break @as(core.BindingId, 0),
                    else => return false,
                }
            } else return false;
            if (!found_opaque) return false;
            if (binding == 0) continue;
            if (binding >= source.bindings.len or source.types.node(source.binding(binding).ty).tag == .erased_proof or self.locals.contains(binding) or try self.hasMutableUse(binding)) return false;
            for (aliases[0..count]) |alias| if (alias.binding == binding) return false;
            aliases[count] = .{ .binding = binding, .local = local };
            count += 1;
        }
        var leaf = result.a;
        for (0..32) |_| {
            const node = source.node(leaf);
            if (node.tag == .project) {
                // Generic payloads acquire their record shape in this exact
                // prepared body; the source type can still be a variable.
                const input = self.generator.representations.store.node(try self.codeLayout(source.typeOf(node.a), source.span(leaf)));
                const projection = self.resolvedPlan(leaf).projection orelse return false;
                if (input.tag != .record or projection != .field or projection.field.projection.nominal.decl != 0 or projection.field.variants.items.len != 1) return false;
                leaf = node.a;
            } else if (node.tag == .reference) {
                const reference = source.reference(leaf);
                if (reference.unit != 0 and reference.unit != self.unit_id) return false;
                var known = self.locals.contains(reference.binding);
                for (aliases[0..count]) |alias| known = known or alias.binding == reference.binding;
                if (!known or try self.hasMutableUse(reference.binding)) return false;
                break;
            } else return false;
        } else return false;
        for (aliases[0..count]) |alias| try self.locals.put(self.generator.allocator, alias.binding, alias.local);
        try self.expression(result.a, depth + 1);
        return true;
    }

    fn inlineOpaqueType(self: *const Emitter, ty: layout.Id) bool {
        const g = self.generator;
        const selected = g.representations.store.node(ty);
        if (selected.tag != .nominal or selected.a == 0 or selected.a > g.units.len) return false;
        for (g.unit(selected.a).nominals) |nominal| {
            if (nominal.identity.unit == selected.a and nominal.identity.decl == selected.b)
                return nominal.is_opaque and nominal.storage.kind != .unknown;
        }
        return false;
    }
    fn inlineDataType(self: *const Emitter, ty: layout.Id) bool {
        return switch (self.generator.representations.store.node(ty).tag) {
            .record, .product, .nominal, .cursor => true,
            else => false,
        };
    }

    /// Expose bounded numeric adapters on either side of a call. This changes
    /// no value or public ABI: ordinary ownership and scalar replacement still
    /// decide whether any of the exposed allocations can disappear.
    fn numericInlineBudget(self: *Emitter, ty: layout.Id) Error!u16 {
        const tag = self.generator.representations.store.node(ty).tag;
        if (tag != .record and tag != .product and tag != .nominal) return 0;
        var remaining: usize = 128;
        var words: usize = 0;
        // Keep expanded numeric inlining to four or more scalar fields.
        // Smaller records use the ordinary budget: duplicating their helpers
        // throughout a large application can cost more than it saves.
        if (!try self.numericLeaves(ty, &remaining, &words, 0) or words < 4) return 0;
        // Bound expanded code by the scalar representation it can eliminate.
        // A small vector must not acquire the whole matrix-sized budget.
        return @intCast(@min(128, words * 8));
    }
    fn numericLeaves(self: *Emitter, ty: layout.Id, remaining: *usize, words: *usize, depth: usize) Error!bool {
        if (remaining.* == 0 or depth >= 16) return false;
        remaining.* -= 1;
        const g = self.generator;
        const node = g.representations.store.node(ty);
        switch (node.tag) {
            .unit, .boolean, .u32, .f32 => {
                words.* += 1;
                return words.* <= 16;
            },
            .record, .product => {
                const step: usize = if (node.tag == .record) 2 else 1;
                const count = g.representations.store.children(ty).len / step;
                for (0..count) |index| {
                    const child = g.representations.store.children(ty)[index * step + step - 1];
                    if (!try self.numericLeaves(child, remaining, words, depth + 1)) return false;
                }
                return true;
            },
            .nominal => {
                if (node.a == 0 or node.a > g.units.len) return false;
                const source = g.unit(node.a);
                var tag: ?u32 = null;
                for (source.constructors) |constructor| {
                    if (remaining.* == 0) return false;
                    remaining.* -= 1;
                    const identity = source.nominal(constructor.nominal).identity;
                    if (identity.unit != node.a or identity.decl != node.b) continue;
                    if (tag != null) return false;
                    tag = constructor.tag;
                }
                const payload = g.nominalPayload((@as(u64, node.a) << 32) | node.b, tag orelse return false, ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
                return self.numericLeaves(payload, remaining, words, depth + 1);
            },
            else => return false,
        }
    }

    // Fuse a fully supplied method selected by an ordinary source adapter.
    // Selection and type evidence remain the same as the curried call path.
    fn saturatedAssociated(self: *Emitter, id: core.Id, caller: *Emitter, extra: []const core.Id, depth: usize) Error!bool {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        if (node.tag != .associated or node.op != .none or extra.len + 2 > max_parameters) return false;
        const selected = self.resolvedPlan(id).dispatch;
        if (selected != .selected) return false;
        var key = selected.selected.key;
        const result = key.result;
        const body = g.unit(key.target.unit).body(key.target.binding) orelse return false;
        if (!body.is_function or body.parameters.len != extra.len + 2) return false;
        var result_type = result;
        for (extra, 2..) |_, i| {
            const arrow = g.representations.store.node(result_type);
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
        const layouts = &self.generator.representations.store;
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
    // Constructor source arrows own canonical payload adapters on the ordinary
    // callable-template path. This plan injects evaluator values instead, so
    // keep constructors there, including those nested in captured graphs.
    fn evaluatedCaptureSupported(self: *const Emitter, value: core_eval.ValueId, remaining: *usize, depth: usize) bool {
        if (remaining.* == 0 or depth >= 128) return false;
        remaining.* -= 1;
        const evaluator = &self.generator.evaluator;
        if (evaluator.valueInfo(value).kind == .closure and evaluator.closureInfo(value).origin == .constructor) return false;
        for (evaluator.valueChildren(value)) |child| if (!self.evaluatedCaptureSupported(child, remaining, depth + 1)) return false;
        return true;
    }
    fn prepareEvaluatedNamed(self: *Emitter, id: core.Id) Error!?*EvaluatedNamed {
        const g = self.generator;
        const diagnostic = g.diagnostic;
        return self.prepareEvaluatedNamedInner(id) catch |err| switch (err) {
            error.Declined => {
                g.diagnostic = diagnostic;
                return null;
            },
            else => return err,
        };
    }
    fn prepareEvaluatedNamedInner(self: *Emitter, id: core.Id) Error!?*EvaluatedNamed {
        const g = self.generator;
        if (!g.inline_named or self.dictionary_owner != null or self.factory_template or self.inline_demands.len != 0) return null;
        const source = g.unit(self.unit_id);
        var arguments: [max_parameters]core.Id = undefined;
        var count: usize = 0;
        var selected: layout.Id = undefined;
        var value: core_eval.ValueId = undefined;
        if (source.node(id).tag == .call) {
            const call = source.call(id);
            if (call.arguments.len == 0 or call.arguments.len > max_parameters) return null;
            const target = try g.normalize(self.unit_id, call.target);
            const definition = g.unit(target.unit).body(target.binding) orelse return null;
            if (definition.runtime or definition.is_function) return null;
            value = g.evaluator.richValue(target) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.evaluationFailure();
            if (g.artifacts) |artifacts| try artifacts.readStaticValue(target, value);
            count = call.arguments.len;
            @memcpy(arguments[0..count], call.arguments);
            selected = try self.codeLayout(call.callee_type, source.span(id));
        } else {
            var root = id;
            while (source.node(root).tag == .apply) {
                if (count == max_parameters) return null;
                arguments[count] = source.node(root).b;
                count += 1;
                root = source.node(root).a;
            }
            if (count == 0) return null;
            std.mem.reverse(core.Id, arguments[0..count]);
            value = try self.staticReference(root) orelse return null;
            selected = try self.codeLayout(source.typeOf(root), source.span(id));
        }
        if (g.evaluator.valueInfo(value).kind != .closure) return null;
        const header = g.evaluator.closureInfo(value);
        if (header.origin != .named or header.staged != 0) return null;
        const producer = g.unit(header.unit);
        const definition = producer.body(header.identity) orelse return null;
        if (!definition.is_function or definition.parameters.len > max_parameters or header.applied + count != definition.parameters.len or @import("inline_body.zig").cost(producer, definition.root) == null) return null;
        const capture_count = header.applied;
        if (g.evaluator.valueInfo(value).len != capture_count) return null;
        var captured: [max_parameters]core_eval.ValueId = undefined;
        @memcpy(captured[0..capture_count], g.evaluator.valueChildren(value));
        var capture_budget: usize = 65_536;
        for (captured[0..capture_count]) |actual| if (!self.evaluatedCaptureSupported(actual, &capture_budget, 0)) return null;
        var mappings: std.ArrayList(Mapping) = .empty;
        var rows: std.ArrayList(RowMapping) = .empty;
        defer mappings.deinit(g.allocator);
        defer rows.deinit(g.allocator);
        for (g.evaluator.storage.type_mappings.items[header.mappings.start..][0..header.mappings.len]) |mapping| {
            const concrete = g.representations.fromEvidence(g.evaluator.evidenceStore(), mapping.evidence) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .unresolved_type);
            try g.mapType(header.unit, &mappings, mapping.variable, concrete, definition.span);
        }
        try g.loadSemanticRows(g.evaluator.storage.row_mappings.items[header.row_mappings.start..][0..header.row_mappings.len], &rows);
        var source_type = try g.functionRoot(header.unit, producer.binding(header.identity).ty, definition.span);
        for (producer.bodyParameters(definition)[0..capture_count], captured[0..capture_count]) |parameter, actual| {
            const concrete = try g.captureTypeLayout(header.unit, parameter.ty, parameter.span, actual, &mappings, &rows);
            const arrow = producer.types.node(source_type);
            if (arrow.tag != .function) return g.fail(self.unit_id, id, .unresolved_type);
            try g.mapType(header.unit, &mappings, arrow.a, concrete, definition.span);
            source_type = arrow.b;
        }
        try g.mapTypeDepth(header.unit, &mappings, &rows, source_type, selected, definition.span, 0);
        var full = try g.codeLayoutWithRows(header.unit, producer.binding(header.identity).ty, mappings.items, rows.items, definition.span);
        try g.refineMappings(header.unit, .{ .body = .{ .unit = header.unit, .binding = header.identity } }, full, &mappings, &rows, definition.span);
        full = try g.codeLayoutWithRows(header.unit, producer.binding(header.identity).ty, mappings.items, rows.items, definition.span);
        var key: Key = .{ .target = .{ .unit = header.unit, .binding = header.identity }, .count = @intCast(definition.parameters.len), .result = 0 };
        for (0..key.count) |index| {
            const arrow = g.representations.store.node(full);
            if (arrow.tag != .function or self.hasErasedType(arrow.a, 0) or g.representations.store.node(arrow.a).tag == .universal or g.representations.store.node(arrow.a).tag == .demand) {
                return null;
            }
            key.parameters[index] = arrow.a;
            key.effects[index] = arrow.c;
            if (index >= capture_count and try self.codeLayout(source.typeOf(arguments[index - capture_count]), source.span(id)) != arrow.a) {
                return null;
            }
            full = arrow.b;
        }
        if (self.hasErasedType(full, 0)) {
            return null;
        }
        key.result = full;
        const plan = try g.allocator.create(EvaluatedNamed);
        plan.* = .{ .key = key, .arguments = arguments, .count = count, .captured = captured, .capture_count = capture_count };
        return plan;
    }
    fn emitEvaluatedNamed(self: *Emitter, plan: *const EvaluatedNamed, depth: usize) Error!bool {
        const g = self.generator;
        if (self.inline_depth >= 6 or g.instance_depth >= 256 or g.module.functions.items[self.function_id].codeLength() > 4096) return false;
        const source = g.unit(plan.key.target.unit);
        const definition = source.body(plan.key.target.binding).?;
        var service = try g.specializer();
        var resolved = service.named(plan.key, &.{}) catch |err| return g.specializationFailure(service, err);
        defer resolved.deinit(g.allocator);
        if (g.artifacts) |artifacts| {
            // Complete static reads or an owned capture graph already belong
            // to this job's executable identity. Live unrecorded values keep
            // the same fresh-code fallback as ordinary static inlining.
            if (!artifacts.hasStaticValues()) artifacts.requireFreshCode();
            try artifacts.readInlineBody(plan.key.target);
        }
        g.instance_depth += 1;
        defer g.instance_depth -= 1;
        const diagnostic_context = try self.inlineContext();
        const emitter = try g.allocator.create(Emitter);
        emitter.* = .{ .generator = g, .unit_id = plan.key.target.unit, .function_id = self.function_id, .provider_local = self.provider_local, .mappings = resolved.mappings.items, .row_mappings = resolved.rows.items, .cleanups = .{ .parent = &self.cleanups }, .diagnostic_context = diagnostic_context, .labels = self.labels, .inline_depth = self.inline_depth + 1, .inline_loop = self.inline_loop or self.loop_targets.items.len != 0 };
        defer {
            emitter.deinit();
            g.allocator.destroy(emitter);
        }
        const parameters = source.bodyParameters(definition);
        for (parameters[0..plan.capture_count], plan.captured[0..plan.capture_count]) |parameter, actual| if (parameter.binding != 0) try emitter.static_values.put(g.allocator, parameter.binding, actual);
        for (parameters[plan.capture_count..], plan.arguments[0..plan.count]) |parameter, argument| {
            const local = try self.capture(argument, depth);
            if (parameter.binding != 0) try emitter.locals.put(g.allocator, parameter.binding, local);
        }
        try emitter.bodyExpression(@backingInt(resolved.root), depth + 1, false);
        return true;
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
        try g.seedNamedInstance(key, &mappings);
        var source_type = try g.functionRoot(key.target.unit, source.binding(key.target.binding).ty, body.span);
        for (key.parameters[0..key.count], 0..) |parameter_type, index| {
            const arrow = source.types.node(source_type);
            if (arrow.tag != .function) return g.decline(key.target.unit, body.span, .unresolved_type);
            try g.mapTypeDepth(key.target.unit, &mappings, &rows, arrow.a, parameter_type, body.span, 0);
            try g.mapRow(key.target.unit, &mappings, &rows, arrow.c, key.effects[index], body.span, true);
            source_type = arrow.b;
        }
        try g.mapTypeDepth(key.target.unit, &mappings, &rows, source_type, key.result, body.span, 0);
        try g.refineMappings(key.target.unit, .{ .body = key.target }, full, &mappings, &rows, body.span);
        var emitter: Emitter = .{ .generator = g, .unit_id = key.target.unit, .function_id = self.function_id, .provider_local = self.provider_local, .mappings = mappings.items, .row_mappings = rows.items, .cleanups = .{ .parent = &self.cleanups }, .diagnostic_context = try self.inlineContext(), .labels = self.labels };
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
            try self.bodyExpression(body.root, depth + 1, false);
            if (source.types.node(source.typeOf(body.root)).tag == .never) try self.emit(.unreachable_, 0);
            return;
        }
        const result_machine = if (supplied + 1 == key.count) g.representations.store.machine(key.result) else .i32;
        var result_role: ir.Role = .reference;
        if (supplied + 1 == key.count) result_role = g.layoutRole(key.result);
        const function_id = try g.module.addTypedFunction(&.{ .i32, g.representations.store.machine(key.parameters[supplied]), .i32 }, result_machine, result_role);
        try g.setParameterRoles(function_id, g.closureRoles(key.parameters[supplied]), 2);
        try g.static_data.closures.append(g.allocator, function_id);
        g.work.fresh_closures += 1;
        try g.planning.startup_facts.request(g.allocator, function_id, .named, key.target.unit, key.target.binding, false);
        var emitter: Emitter = .{ .generator = g, .unit_id = key.target.unit, .function_id = function_id, .provider_local = 2, .mappings = self.mappings, .row_mappings = self.row_mappings };
        defer emitter.deinit();
        const environment_roles = try emitter.layoutRoles(g.allocator, key.parameters[0..supplied]);
        defer g.allocator.free(environment_roles);
        const environment = try self.allocate(@intCast(supplied * 4), .{ .words = environment_roles });
        const parameters = source.bodyParameters(body);
        for (parameters[0..supplied], 0..) |parameter, index| {
            const value = self.static_values.get(parameter.binding);
            try self.emit(.local_get, environment);
            if (value != null or parameter.binding == 0) {
                try self.emit(.i32_const, 0);
                try self.emit(.i32_store, @intCast(index * 4));
                if (value) |static_value| try emitter.static_values.put(g.allocator, parameter.binding, static_value);
            } else {
                const machine = g.representations.store.machine(key.parameters[index]);
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
        const caller = g.planning.startup_facts.active;
        g.planning.startup_facts.active = function_id;
        defer g.planning.startup_facts.active = caller;
        try emitter.finishStaticCall(key, supplied + 1, depth);
        g.planning.startup_facts.complete(function_id);
        g.planning.startup_facts.active = caller;
        try self.descriptor(function_id, environment);
    }
    fn preparePartialStaticCall(self: *Emitter, id: core.Id) Error!?SourceCall {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const source = g.unit(self.unit_id);
        var reversed: [max_parameters]core.Id = undefined;
        var count: usize = 0;
        var root = id;
        while (source.node(root).tag == .apply) {
            if (count == max_parameters) return null;
            const node = source.node(root);
            reversed[count] = node.b;
            count += 1;
            root = node.a;
        }
        if (source.node(root).tag != .reference) return null;
        const reference = source.reference(root);
        if (reference.unit == 0 or reference.unit == self.unit_id) {
            if (self.locals.contains(reference.binding) or self.templates.contains(reference.binding) or self.static_values.contains(reference.binding)) return null;
            const kind = source.binding(reference.binding).kind;
            if (kind != .global and kind != .external) return null;
        }
        const target = try g.normalize(self.unit_id, reference);
        const body = g.unit(target.unit).body(target.binding) orelse return null;
        if (!body.is_function or count >= body.parameters.len) return null;
        const key = try g.signature(target, source.typeOf(root), self.unit_id, self.mappings, self.row_mappings, source.span(id), false);
        std.mem.reverse(core.Id, reversed[0..count]);
        return .{ .key = key, .arguments = reversed, .count = count };
    }

    pub fn operationConstant(self: *Emitter, operation: runtime_operations.Id) Error!void {
        self.generator.planning.runtime_operations.emit(&self.generator.module, self.function_id, operation) catch |err| switch (err) {
            error.InvalidOperation => return error.InvalidFunctionReference,
            error.OutOfMemory => return error.OutOfMemory,
            error.ModuleTooLarge => return error.ModuleTooLarge,
        };
    }
    pub fn deinit(self: *Emitter) void {
        self.planned_returns.deinit(self.generator.allocator);
        self.planned_loops.deinit(self.generator.allocator);
        self.row_views.deinit(self.generator.allocator);
        self.cursor_directories.deinit(self.generator.allocator);
        self.small_values.deinit(self.generator.allocator);
        self.locals.deinit(self.generator.allocator);
        self.cleanups.deinit(self.generator.allocator);
        self.return_targets.deinit(self.generator.allocator);
        self.loop_targets.deinit(self.generator.allocator);
        self.templates.deinit(self.generator.allocator);
        self.static_values.deinit(self.generator.allocator);
        self.computation_values.deinit(self.generator.allocator);
        self.instance_locals.deinit(self.generator.allocator);
    }
    fn inlineContext(self: *Emitter) Error!u32 {
        const g = self.generator;
        if (!g.memory_profile or self.semantic_node == 0) return self.diagnostic_context;
        return g.diagnostic_contexts.intern(g.allocator, .{ .unit = self.unit_id, .node = self.semantic_node, .parent = self.diagnostic_context }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ModuleTooLarge => return g.fail(self.unit_id, self.semantic_node, .complexity),
        };
    }
    fn recordSemantic(self: *Emitter, op: wasm.Op, operand: u32) Error!void {
        if (self.semantic_node == 0) return;
        const g = self.generator;
        const call = op == .call or op == .call_indirect or op == .call_import;
        const memory = g.memory_profile and (ir.fixed(op).bytes != 0 or op == .memory_copy or op == .memory_fill);
        if (!call and !memory) return;
        var kind: @FieldType(wasm.Module.SemanticSite, "kind") = undefined;
        if (memory) kind = .diagnostic_memory else if (op == .call and g.module.arena != null and g.module.arena.?.isAllocation(operand)) kind = .allocation else if (op == .call and g.module.runtimeHelper(operand)) {
            if (!g.memory_profile) return;
            kind = .diagnostic_call;
        } else kind = .call;
        if (self.semantic_context == null) self.semantic_context = .{ .mappings = try g.mappingEvidence(self.mappings), .rows = try g.rowMappingEvidence(self.row_mappings) };
        try g.module.recordSemanticSite(.{ .diagnostic_context = self.diagnostic_context, .function = self.function_id, .place = @intCast(g.module.functions.items[self.function_id].instructions.items.len), .unit = self.unit_id, .node = self.semantic_node, .root = if (self.body) |body| body.root else self.analysis_root, .mappings = self.semantic_context.?.mappings, .rows = self.semantic_context.?.rows, .kind = kind });
    }
    pub fn emit(self: *Emitter, op: wasm.Op, operand: u32) Error!void {
        std.debug.assert(!self.preparing);
        try self.recordSemantic(op, operand);
        try self.generator.module.emit(self.function_id, .{ .op = op, .operand = operand });
        if (op == .call and self.generator.module.runtimeHelper(operand)) return;
        if (op == .call or op == .call_indirect or op == .call_import) {
            if (self.generator.request_owner) |owner| try request_runtime.guard(&self.generator.module, self.function_id, owner, &self.cleanups);
        }
    }
    pub fn referenceConstant(self: *Emitter, value: u32, role: artifact_emitter.Role) Error!void {
        if (role == .static_address) try self.generator.module.emit(self.function_id, ir.immortalReference());
        try self.generator.module.emitReference(self.function_id, .{ .op = .i32_const, .operand = value }, role);
    }
    fn emitUnguarded(self: *Emitter, op: wasm.Op, operand: u32) Error!void {
        try self.recordSemantic(op, operand);
        try self.generator.module.emit(self.function_id, .{ .op = op, .operand = operand });
    }
    pub fn providerHead(self: *Emitter) Error!void {
        if (self.provider_local) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
    }
    fn scalar(self: *Emitter, id: core.Id) Error!Scalar {
        const unit_ = self.generator.unit(self.unit_id);
        var shape: layout.Id = undefined;
        if (unit_.node(id).tag == .reference) shape = try self.referenceLayout(id) else shape = try self.codeLayout(unit_.typeOf(id), unit_.span(id));
        return self.generator.representations.store.scalar(shape) orelse .pointer;
    }
    pub fn temporary(self: *Emitter, machine: wasm.ValueType) Error!u32 {
        std.debug.assert(!self.preparing);
        return self.generator.module.addLocal(self.function_id, machine);
    }
    fn capture(self: *Emitter, id: core.Id, depth: usize) Error!u32 {
        if (self.generator.unit(self.unit_id).types.node(self.generator.unit(self.unit_id).typeOf(id)).tag == .erased_proof) {
            try self.expression(id, depth + 1);
            return std.math.maxInt(u32);
        }
        const local = try self.temporary((try self.scalar(id)).machine());
        try self.expression(id, depth + 1);
        try self.emit(.local_set, local);
        return local;
    }
    /// Word roles of a fresh allocation from checked layouts. Words past
    /// `words` take `rest`.
    const AllocationRoles = struct {
        words: []const ir.Role = &.{},
        rest: ir.Role = .unknown,
        const scalar: AllocationRoles = .{ .rest = .scalar };
        /// Roles of a runtime heap structure, from its role table.
        pub fn heap(comptime T: type) AllocationRoles {
            const table = comptime table: {
                var result: [T.roles.len]ir.Role = undefined;
                for (T.roles, 0..) |role, index| result[index] = switch (role) {
                    .scalar, .table_function, .owner_token => .scalar,
                    .reference => .reference,
                    .value => .value,
                };
                break :table result;
            };
            return .{ .words = &table };
        }
    };
    pub fn allocate(self: *Emitter, bytes: u32, roles: AllocationRoles) Error!u32 {
        return self.allocateStorage(bytes, false, roles);
    }
    pub fn markAcyclic(self: *Emitter, value: u32, ty: layout.Id) Error!void {
        if (!try self.generator.acyclicLayout(ty)) return;
        try self.emit(.local_get, value);
        try self.emit(.call, self.generator.module.arena.?.mark_acyclic);
    }
    /// The `new`/`from_array` row argument of a List with this element layout.
    /// A reference layout with an exact acyclic proof marks the whole tree.
    fn listKind(self: *Emitter, scalar_words: u32, element: layout.Id) Error!u32 {
        if (scalar_words != 0 or !try self.generator.acyclicLayout(element)) return scalar_words;
        return @import("../runtime/list_runtime.zig").acyclic_kind;
    }
    fn allocatePrivate(self: *Emitter, bytes: u32, roles: AllocationRoles) Error!u32 {
        const local = try self.allocate(bytes, roles);
        try self.cleanups.append(self.generator.allocator, .{ .release = @fromBackingInt(@intCast(local)) });
        return local;
    }
    /// Precedes an allocation's constant size with its word roles.
    fn annotateAllocation(self: *Emitter, roles: AllocationRoles) Error!void {
        var buffer: [ir.max_annotations]ir.Instruction = undefined;
        for (ir.annotations(roles.words, roles.rest, &buffer)) |annotation| try self.emit(annotation.op, annotation.operand);
        self.generator.evaluator.counters.allocation_role_runs += 1;
    }
    /// Roles of words holding values of these checked layouts, in order.
    pub fn layoutRoles(self: *Emitter, scratch: Allocator, layouts: []const layout.Id) Error![]ir.Role {
        const roles = try scratch.alloc(ir.Role, layouts.len);
        for (layouts, roles) |item, *role| role.* = self.generator.layoutRole(item);
        return roles;
    }
    fn cleanupTo(self: *Emitter, checkpoint: runtime_cleanup.Mark) Error!void {
        try self.cleanups.emitTo(&self.generator.module, @fromBackingInt(@intCast(self.function_id)), checkpoint);
    }
    fn wideShape(self: *Emitter, bytes: u32, roles: AllocationRoles, force: bool) Error!?u32 {
        if (bytes == 0 or bytes % 4 != 0) return null;
        if (!force and bytes <= 128) return null;
        const count = bytes / 4;
        var tail: ir.Role = .unknown;
        var wide = false;
        for (0..count) |word| {
            var role = roles.rest;
            if (word < roles.words.len) role = roles.words[word];
            if (role != .scalar and role != .reference) return null;
            if (word == 31) tail = role;
            if (word > 31 and role != tail) wide = true;
        }
        if (!wide and !force and count <= 16 * ir.Ownership.words_per_chunk) return null;
        const g = self.generator;
        const bitmap = try g.allocator.alloc(u32, 1 + (count + 31) / 32);
        defer g.allocator.free(bitmap);
        @memset(bitmap, 0);
        bitmap[0] = count;
        for (0..count) |word| {
            var role = roles.rest;
            if (word < roles.words.len) role = roles.words[word];
            if (role == .reference) bitmap[1 + word / 32] |= @as(u32, 1) << @intCast(word % 32);
        }
        const address = try g.module.dataWords(bitmap);
        const arena = g.module.arena.?;
        const flags = g.module.globals.items[arena.rc_enabled].bits | @import("../runtime/shared_rc.zig").shaped_mode;
        if (g.module.artifacts) |journal| try journal.append(.{ .global_bits = .{ .id = arena.rc_enabled, .bits = .{ .value = flags } } });
        g.module.globals.items[arena.rc_enabled].bits = flags;
        return address;
    }
    fn allocateStorage(self: *Emitter, bytes: u32, scalar_payload: bool, roles: AllocationRoles) Error!u32 {
        const arena = try self.generator.module.ensureArena();
        const local = try self.temporary(.i32);
        var shape: ?u32 = null;
        if (!scalar_payload) shape = try self.wideShape(bytes, roles, false);
        if (shape) |address| {
            try self.emit(.i32_const, bytes);
            try self.referenceConstant(address, .static_address);
            try self.emit(.call, arena.allocate_shaped);
        } else {
            try self.annotateAllocation(if (scalar_payload) .scalar else roles);
            try self.emit(.i32_const, bytes);
            try self.emit(.call, if (scalar_payload) arena.allocate_scalar else arena.allocate);
        }
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
                const target = self.resolvedPlan(id).reference.?;
                const body = g.unit(target.unit).body(target.binding) orelse return g.fail(self.unit_id, id, .unsupported);
                if (body.runtime and !body.is_function) {
                    _ = try g.planning.runtimeGlobal(g, target);
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
        if (g.representations.store.node(left_type).tag != .record or g.representations.store.node(right_type).tag != .record or g.representations.store.node(result_type).tag != .record) return g.fail(self.unit_id, id, .unresolved_type);
        // Even an overwritten field's computation remains observable.
        const left = try self.capture(node.a, depth);
        const right = try self.capture(node.b, depth);
        const left_fields = g.representations.store.children(left_type);
        const right_fields = g.representations.store.children(right_type);
        const fields = g.representations.store.children(result_type);
        if (left_fields.len == 0 or right_fields.len == 0) return self.emit(.local_get, if (left_fields.len == 0) right else left);
        if (fields.len / 2 > std.math.maxInt(u32) / 4) return g.fail(self.unit_id, id, .complexity);
        const merged_roles = try g.allocator.alloc(ir.Role, fields.len / 2);
        defer g.allocator.free(merged_roles);
        for (merged_roles, 0..) |*role, field| role.* = g.layoutRole(fields[field * 2 + 1]);
        const result = try self.allocate(@intCast(fields.len * 2), .{ .words = merged_roles });
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
        for (children) |child| {
            try locals.append(scratch_allocator, try self.capture(child, depth));
            if (unit_.types.node(unit_.typeOf(child)).tag == .never) return;
        }
        const record = unit_.node(id).tag == .record;
        const destinations = if (record) unit_.recordDestinations(id) else &.{};
        var aggregate_type = unit_.typeOf(id);
        if (unit_.types.node(aggregate_type).tag == .usage) aggregate_type = unit_.types.node(aggregate_type).a;
        const physical = if (record) try @import("../check/record_order.zig").destinations(scratch_allocator, unit_.types, unit_.types.node(aggregate_type), &g.representations.store.record_names) else &.{};
        defer scratch_allocator.free(physical);
        const slot_roles = try scratch_allocator.alloc(ir.Role, children.len);
        defer scratch_allocator.free(slot_roles);
        for (children, 0..) |child, index| {
            const declared = if (record) destinations[index] else index;
            slot_roles[if (physical.len == 0) declared else physical[declared]] = g.layoutRole(try self.codeLayout(unit_.typeOf(child), unit_.span(child)));
        }
        const address = try self.allocate(@intCast(children.len * 4), .{ .words = slot_roles });
        if (std.mem.findScalar(ir.Role, slot_roles, .reference) != null) try self.markAcyclic(address, try self.codeLayout(unit_.typeOf(id), unit_.span(id)));
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
    pub fn recordRepresentation(self: *Emitter, record: types.Node, value: u32, into_record: bool) Error!u32 {
        const g = self.generator;
        var buffer: [256]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&buffer, g.allocator);
        const order = try @import("../check/record_order.zig").destinations(scratch.allocator(), g.unit(self.unit_id).types, record, &g.representations.store.record_names);
        defer scratch.allocator().free(order);
        if (order.len == 0) return value;
        if (record.b > std.math.maxInt(u32) / 4) return g.decline(self.unit_id, .{ .start = 0, .end = 0 }, .complexity);
        const field_roles = try scratch.allocator().alloc(ir.Role, record.b);
        defer scratch.allocator().free(field_roles);
        for (order, 0..) |physical, declared| {
            const field = g.unit(self.unit_id).types.recordField(record, declared);
            field_roles[if (into_record) physical else declared] = g.layoutRole(try self.codeLayout(field.ty, .{ .start = 0, .end = 0 }));
        }
        const address = try self.allocate(record.b * 4, .{ .words = field_roles });
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
    fn nullaryConstructor(self: *Emitter, tag: u32) Error!void {
        const address = try self.generator.module.dataWords(&.{ tag, 0 });
        // A missing payload is zero, including in a reference-payload family.
        try self.emit(.ownership, @bitCast(ir.Ownership{ .kind = .words, .chunk = 14, .roles = @truncate(tag) }));
        try self.emit(.ownership, @bitCast(ir.Ownership{ .kind = .words, .chunk = 15, .roles = @intCast(tag >> 26) }));
        var facts: [ir.max_annotations]ir.Instruction = undefined;
        const run = ir.annotations(&.{ .scalar, .reference }, .unknown, &facts);
        var terminator: ir.Ownership = @bitCast(run[run.len - 1].operand);
        terminator.chunk = 15;
        run[run.len - 1].operand = @bitCast(terminator);
        for (run) |fact| try self.generator.module.emit(self.function_id, fact);
        try self.generator.module.emitReference(self.function_id, .{ .op = .i32_const, .operand = address }, .static_address);
    }
    fn construct(self: *Emitter, id: core.Id, depth: usize) Error!void {
        if (self.body.?.entries.contains(id)) {
            try self.expression(self.resolvedPlan(id).constructor_subject, depth + 1);
            return;
        }
        const unit_ = self.generator.unit(self.unit_id);
        const n = unit_.node(id);
        const constructor = unit_.constructor(n.a);
        if (unit_.nominal(constructor.nominal).is_opaque) {
            if (n.b == 0) {
                try self.emit(.i32_const, 0);
            } else try self.expression(n.b, depth + 1);
            return;
        }
        if (n.b == 0 and n.c == 0) return self.nullaryConstructor(constructor.tag);
        var payload = if (n.b == 0) null else try self.capture(n.b, depth);
        if (n.b != 0 and unit_.types.node(unit_.typeOf(n.b)).tag == .never) return;
        var floating = n.b != 0 and try self.scalar(n.b) == .f32;
        if (n.c != 0) {
            const record = unit_.types.node(unit_.constructor(n.a).payload);
            if (record.tag != .record or record.b == 0 or payload == null) return self.generator.fail(self.unit_id, id, .unsupported);
            if (record.b == 1) {
                // The stored operand owns its selected representation. The
                // declaration field may retain an uninstantiated type binder.
                const payload_layout = try self.codeLayout(unit_.typeOf(n.b), unit_.span(n.b));
                const address = try self.allocate(4, .{ .words = &.{self.generator.layoutRole(payload_layout)} });
                try self.emit(.local_get, address);
                try self.emit(.local_get, payload.?);
                try self.emit(if (floating) .f32_store else .i32_store, 0);
                payload = address;
            } else {
                const source = payload.?;
                payload = try self.recordRepresentation(record, source, true);
                // A reordered copy is a fresh record of the same layout.
                if (payload.? != source) try self.markAcyclic(payload.?, try self.codeLayout(unit_.typeOf(n.b), unit_.span(n.b)));
            }
            floating = false;
        }
        // A constructor cell is its tag, then its payload or zero.
        const payload_role: ir.Role = if (n.c != 0) .reference else if (n.b == 0) .scalar else self.generator.layoutRole(try self.codeLayout(unit_.typeOf(n.b), unit_.span(n.b)));
        const address = try self.allocate(8, .{ .words = &.{ .scalar, payload_role } });
        if (payload_role == .reference) try self.markAcyclic(address, try self.codeLayout(n.ty, unit_.span(id)));
        try self.emit(.local_get, address);
        try self.emit(.i32_const, unit_.constructor(n.a).tag);
        try self.emit(.i32_store, 0);
        try self.emit(.local_get, address);
        if (payload) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
        try self.emit(if (floating) .f32_store else .i32_store, 4);
        try self.emit(.local_get, address);
    }
    const Location = struct { owner: u32, container: u32, offset: u32, size: ?u32, wrapped: bool, list_index: ?u32 = null, row_words: u32 = 0, row_layout: layout.Id = 0, array_scalar: ?bool = null, mask: ?u32 = null, scalar_storage: bool = false, shape: ?u32 = null, acyclic: bool = false };
    fn payloadLayout(self: *Emitter, projection: core.Projection, tag: u32, id: core.Id) Error!layout.Id {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        for (unit_.constructors) |constructor| {
            const nominal = unit_.nominal(constructor.nominal);
            if (!std.meta.eql(nominal.identity, projection.nominal) or constructor.tag != tag) continue;
            const concrete = try self.codeLayout(projection.source_type, unit_.span(id));
            const arguments = g.representations.store.children(concrete);
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
        const n = self.generator.representations.store.node(try self.payloadLayout(projection, tag, id));
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
        const owner_node = g.representations.store.node(owner);
        if (owner_node.tag == .record) {
            const fields = g.representations.store.children(owner);
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
                if (g.representations.store.node(payload).tag != .record) return g.fail(self.unit_id, id, .unresolved_type);
                const fields = g.representations.store.children(payload);
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
    fn prepareField(self: *Emitter, id: core.Id, index: u32, sizes: bool) Error!FieldPlan {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        var result: FieldPlan = .{ .index = index, .projection = source.projection(index) };
        errdefer result.deinit(g.allocator);
        const variants = source.projectionVariants(index);
        if (result.projection.field != 0 or variants.len == 0) {
            result.projection = try self.resolveProjection(result.projection, &result.variants, id);
        } else try result.variants.appendSlice(g.allocator, variants);
        if (sizes) for (result.variants.items) |variant| {
            const slots = if (result.projection.nominal.decl != 0) try self.payloadSlots(result.projection, variant.tag, id) else g.representations.store.node(try self.codeLayout(result.projection.source_type, source.span(id))).b;
            if (slots > std.math.maxInt(u32) / 4) return g.fail(self.unit_id, id, .complexity);
            try result.slots.append(g.allocator, slots);
        };
        return result;
    }
    fn prepareUpdateLocations(self: *Emitter, id: core.Id) Error![]FieldPlan {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const source = g.unit(self.unit_id);
        var fields: std.ArrayList(FieldPlan) = .empty;
        defer fields.deinit(g.allocator);
        errdefer for (fields.items) |*field| field.deinit(g.allocator);
        const selectors = source.updateSelectors(id);
        if (selectors.len == 0) {
            for (source.updatePath(id)) |index| {
                var field = try self.prepareField(id, index, true);
                fields.append(g.allocator, field) catch |err| {
                    field.deinit(g.allocator);
                    return err;
                };
            }
        } else for (selectors) |selector| if (selector.kind == .field) {
            var field = try self.prepareField(id, selector.projection, true);
            fields.append(g.allocator, field) catch |err| {
                field.deinit(g.allocator);
                return err;
            };
        };
        return fields.toOwnedSlice(g.allocator);
    }
    fn fieldPlan(self: *Emitter, id: core.Id, index: u32) *const FieldPlan {
        const prepared = self.resolvedPlan(id);
        switch (prepared) {
            .projection => return &self.body.?.getConstPtr(.projection, id).*.?.field,
            .update_locations => |locations| {
                for (locations) |*place| if (place.index == index) return place;
                unreachable;
            },
            else => unreachable,
        }
    }
    fn prepareProjection(self: *Emitter, body: *Body, id: core.Id, depth: usize) Error!?ProjectionPlan {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        if (source.types.node(source.typeOf(node.a)).tag == .never) return null;
        const metadata = source.projection(node.b);
        if (source.projectionVariants(node.b).len != 0) return .{ .field = try self.prepareField(id, node.b, false) };
        const previous = g.diagnostic;
        var field = self.prepareField(id, node.b, false) catch |err| switch (err) {
            error.Declined => declined: {
                g.diagnostic = previous;
                break :declined null;
            },
            else => return err,
        };
        errdefer if (field) |*owned| owned.deinit(g.allocator);
        const concrete = try self.codeLayout(metadata.source_type, source.span(id));
        const method = try self.memberTarget(id, metadata.field, concrete);
        if (field != null and method != null) return g.fail(self.unit_id, id, .ambiguous_member);
        if (field) |owned| return .{ .field = owned };
        const target = method orelse return g.fail(self.unit_id, id, .missing_member);
        const result = try self.codeLayout(node.ty, source.span(id));
        const full = try g.internLayout(.function, concrete, result, &.{});
        const signature = try self.dispatchCallableLayout(id, full);
        var direct: Key = .{ .target = target, .count = 1, .result = result };
        direct.parameters[0] = concrete;
        direct.effects[0] = g.representations.store.node(signature).c;
        const producer = g.unit(target.unit);
        if (producer.body(target.binding)) |method_body| {
            const root = producer.node(method_body.root);
            if (root.tag == .if_value and producer.node(root.b).tag == .construct and @import("collection_iteration.zig").cursorNext(producer, target.binding, producer, producer.node(root.b).a) and !producer.nominal(producer.constructor(producer.node(root.b).a).nominal).is_opaque) {
                try self.prepareNode(body, node.a, depth + 1, false);
                if (try self.privateCursorConstructor(body, node.a)) |input| {
                    if (source.node(input).tag == .array and source.children(input).len == 0) {
                        if (g.artifacts) |context| context.requireFreshCode();
                        return .{ .empty_cursor = producer.constructor(producer.node(root.c).a).tag };
                    }
                }
            }
        }
        return .{ .member = .{ .direct = direct, .wrapper = .{ .target = target, .ty = signature } } };
    }
    /// The counted representation supports 31 explicit words and one uniform
    /// tail. Unknown or heterogeneous tails retain the ordinary storage path.
    fn fieldMask(self: *Emitter, projection: core.Projection, tag: u32, id: core.Id) Error!?u32 {
        const g = self.generator;
        const ty = if (projection.nominal.decl != 0) try self.payloadLayout(projection, tag, id) else try self.codeLayout(projection.source_type, g.unit(self.unit_id).span(id));
        const node = g.representations.store.node(ty);
        if (node.tag != .product and node.tag != .record) return null;
        const fields = g.representations.store.children(ty);
        var mask: u32 = 0;
        var tail: ir.Role = .scalar;
        for (0..node.b) |word| {
            var index = word;
            if (node.tag == .record) index = word * 2 + 1;
            const role = g.layoutRole(fields[index]);
            if (role != .scalar and role != .reference) return null;
            if (word < 31) {
                if (role == .reference) mask |= @as(u32, 1) << @intCast(word);
            } else if (word == 31) {
                tail = role;
                if (role == .reference) mask |= 0x80000000;
            } else if (role != tail) return null;
        }
        return mask;
    }
    fn fieldShape(self: *Emitter, projection: core.Projection, tag: u32, id: core.Id) Error!?u32 {
        const g = self.generator;
        const ty = if (projection.nominal.decl != 0) try self.payloadLayout(projection, tag, id) else try self.codeLayout(projection.source_type, g.unit(self.unit_id).span(id));
        const node = g.representations.store.node(ty);
        if (node.tag != .product and node.tag != .record) return null;
        const fields = g.representations.store.children(ty);
        var buffer: [256]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&buffer, g.allocator);
        const roles = try scratch.allocator().alloc(ir.Role, node.b);
        defer scratch.allocator().free(roles);
        for (roles, 0..) |*role, word| {
            var index = word;
            if (node.tag == .record) index = word * 2 + 1;
            role.* = g.layoutRole(fields[index]);
        }
        return self.wideShape(node.b * 4, .{ .words = roles }, true);
    }
    fn location(self: *Emitter, owner: u32, projection_index: u32, id: core.Id, need_size: bool) Error!Location {
        const g = self.generator;
        const prepared = self.fieldPlan(id, projection_index);
        const projection = prepared.projection;
        const variants = prepared.variants.items;
        // The checked whole-owner proof covers both its payload and wrapper.
        // Copies must preserve it before publishing any owning fields.
        const acyclic = need_size and try g.acyclicLayout(try self.codeLayout(projection.source_type, g.unit(self.unit_id).span(id)));
        var wrapped = projection.nominal.decl != 0;
        if (wrapped) for (g.unit(projection.nominal.unit).nominals) |nominal| {
            if (std.meta.eql(nominal.identity, projection.nominal) and nominal.is_opaque) {
                wrapped = false;
                break;
            }
        };
        const container = if (wrapped) try self.temporary(.i32) else owner;
        const offset = try self.temporary(.i32);
        const size = if (need_size) try self.temporary(.i32) else null;
        var scalar_storage = need_size;
        if (need_size) for (variants) |variant| {
            if (try self.fieldMask(projection, variant.tag, id) != 0) scalar_storage = false;
        };
        const mask = if (need_size and !scalar_storage) blk: {
            for (variants) |variant| if (try self.fieldMask(projection, variant.tag, id) == null) break :blk null;
            break :blk try self.temporary(.i32);
        } else null;
        var shapes: std.ArrayList(u32) = .empty;
        defer shapes.deinit(g.allocator);
        const shape = if (need_size and !scalar_storage and mask == null) blk: {
            for (variants) |variant| {
                const address = try self.fieldShape(projection, variant.tag, id) orelse break :blk null;
                try shapes.append(g.allocator, address);
            }
            break :blk try self.temporary(.i32);
        } else null;
        if (wrapped) {
            try self.emit(.local_get, owner);
            try self.nonzeroLoad(.i32_load, 4);
            try self.emit(.local_set, container);
        }
        if (variants.len == 1) {
            const variant = variants[0];
            if (wrapped) {
                try self.emit(.local_get, owner);
                try self.nonzeroLoad(.i32_load, 0);
                try self.emit(.i32_const, variant.tag);
                try self.emit(.i32_ne, 0);
                try self.emit(.if_, 0);
                try self.emit(.unreachable_, 0);
                try self.emit(.end, 0);
            }
            try self.emit(.i32_const, variant.field * 4);
            try self.emit(.local_set, offset);
            if (size) |size_local| {
                const slots = prepared.slots.items[0];
                if (slots > std.math.maxInt(u32) / 4) return g.fail(self.unit_id, id, .complexity);
                try self.emit(.i32_const, slots * 4);
                try self.emit(.local_set, size_local);
            }
            if (mask) |mask_local| {
                try self.emit(.i32_const, (try self.fieldMask(projection, variant.tag, id)).?);
                try self.emit(.local_set, mask_local);
            }
            if (shape) |shape_local| {
                try self.referenceConstant(shapes.items[0], .static_address);
                try self.emit(.local_set, shape_local);
            }
            return .{ .owner = owner, .container = container, .offset = offset, .size = size, .wrapped = wrapped, .mask = mask, .scalar_storage = scalar_storage, .shape = shape, .acyclic = acyclic };
        }
        try self.emit(.i32_const, std.math.maxInt(u32));
        try self.emit(.local_set, offset);
        for (variants, 0..) |variant, variant_index| {
            if (wrapped) {
                try self.emit(.local_get, owner);
                try self.nonzeroLoad(.i32_load, 0);
                try self.emit(.i32_const, variant.tag);
                try self.emit(.i32_eq, 0);
                try self.emit(.if_, 0);
                self.labels += 1;
            }
            try self.emit(.i32_const, variant.field * 4);
            try self.emit(.local_set, offset);
            if (size) |size_local| {
                const slots = prepared.slots.items[variant_index];
                if (slots > std.math.maxInt(u32) / 4) return g.fail(self.unit_id, id, .complexity);
                try self.emit(.i32_const, slots * 4);
                try self.emit(.local_set, size_local);
            }
            if (mask) |mask_local| {
                try self.emit(.i32_const, (try self.fieldMask(projection, variant.tag, id)).?);
                try self.emit(.local_set, mask_local);
            }
            if (shape) |shape_local| {
                try self.referenceConstant(shapes.items[variant_index], .static_address);
                try self.emit(.local_set, shape_local);
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
        return .{ .owner = owner, .container = container, .offset = offset, .size = size, .wrapped = wrapped, .mask = mask, .scalar_storage = scalar_storage, .shape = shape, .acyclic = acyclic };
    }
    fn nonzeroLoad(self: *Emitter, op: wasm.Op, offset: u32) Error!void {
        try self.generator.module.emit(self.function_id, ir.nonzeroRead());
        try self.emit(op, offset);
    }
    fn loadLocation(self: *Emitter, place: Location, scalar_: Scalar) Error!void {
        if (place.list_index) |index| if (place.row_words != 0) return self.readListRow(place.owner, index, place.row_words, null, null, place.row_layout);
        try self.emit(.local_get, place.container);
        try self.emit(.local_get, place.offset);
        try self.emit(.i32_add, 0);
        try self.readElement(scalar_.machine(), 0, place.row_words, place.row_layout);
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
        if (try self.staticCallableTemplate(id)) |template| {
            return self.templateValue(template, try self.codeLayout(g.unit(self.unit_id).typeOf(id), g.unit(self.unit_id).span(id)));
        }
        const unit_ = g.unit(self.unit_id);
        const n = unit_.node(id);
        if (unit_.types.node(unit_.typeOf(n.a)).tag == .never) {
            try self.expression(n.a, depth + 1);
            return;
        }
        const prepared = self.resolvedPlan(id).projection.?;
        if (prepared == .empty_cursor) {
            try self.expression(n.a, depth + 1);
            try self.emit(.drop, 0);
            try self.nullaryConstructor(prepared.empty_cursor);
            return;
        }
        if (prepared == .member) {
            const member = prepared.member;
            if (try self.inlineNamedCall(member.direct, &.{n.a}, depth)) return;
            const wrapper = try g.callable(member.wrapper);
            const receiver = try self.capture(n.a, depth);
            try self.emit(.i32_const, 0);
            try self.emit(.local_get, receiver);
            try self.providerHead();
            try self.emit(.call, wrapper);
            return;
        }
        if (try self.packedProjection(id, depth)) return;
        for (self.row_views.items) |view| {
            if (try g.nestedRow(view.row)) |plan| {
                if (row_projection_uses.numericOffset(unit_, id, view.binding, &g.representations.store, &plan)) |offset| {
                    try self.loadRowView(view, offset, (try self.scalar(id)).machine());
                    return;
                }
            }
        }
        if (unit_.node(n.a).tag == .reference) {
            const reference = unit_.reference(n.a);
            if (reference.unit == 0 or reference.unit == self.unit_id) {
                var index = self.row_views.items.len;
                while (index != 0) {
                    index -= 1;
                    const view = self.row_views.items[index];
                    if (view.binding != reference.binding) continue;
                    const offset = row_projection_uses.fieldOffset(unit_, n.b, &g.representations.store, view.row) orelse return g.fail(self.unit_id, id, .unresolved_type);
                    try self.loadRowView(view, offset, (try self.scalar(id)).machine());
                    return;
                }
            }
        }
        const owner = try self.capture(n.a, depth);
        const place = try self.location(owner, n.b, id, false);
        try self.emit(.local_get, place.container);
        try self.emit(.local_get, place.offset);
        try self.emit(.i32_add, 0);
        var load: wasm.Op = .i32_load;
        if ((try self.scalar(id)).machine() == .f32) load = .f32_load;
        try self.nonzeroLoad(load, 0);
    }
    /// Selecting one scalar field from an already constructed packed row needs
    /// no extracted box. Producer evaluation and the original bounds check
    /// remain eager; admission never looks through an arbitrary source call.
    fn packedProjection(self: *Emitter, id: core.Id, depth: usize) Error!bool {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        var origin = source.node(id).a;
        var remaining: usize = 16;
        while (source.node(origin).tag == .project and remaining != 0) : (remaining -= 1) origin = source.node(origin).a;
        const value = source.node(origin);
        if (value.tag != .array_op) return false;
        const op = source.arrayOperation(origin);
        if (op != .get and op != .cursor_value) return false;
        const operands = source.children(origin);
        const input = try self.codeLayout(source.typeOf(operands[0]), source.span(id));
        const collection = if (op == .cursor_value) g.representations.store.node(input).a else input;
        const words = try g.collectionRowWords(collection);
        if (words == 0) return false;
        const row = g.representations.store.node(collection).a;
        const field: u32 = if (try g.nestedRow(row)) |plan| blk: {
            const offset = row_projection_uses.numericExpressionOffset(source, id, origin, &g.representations.store, &plan) orelse return false;
            break :blk offset / 4;
        } else blk: {
            const projected = source.node(id);
            if (origin != projected.a) return false;
            const offset = row_projection_uses.fieldOffset(source, projected.b, &g.representations.store, row) orelse return false;
            break :blk offset / 4;
        };
        var container = try self.capture(operands[0], depth);
        const cursor = if (op == .cursor_value) container else null;
        var cache: ?[2]u32 = null;
        const index = if (op == .get) try self.capture(operands[1], depth) else blk: {
            if (self.privateCursorReference(operands[0])) |fields| {
                container = fields.values[0];
                cache = .{ fields.values[2], fields.values[3] };
                break :blk fields.values[1];
            }
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
        const is_list = g.representations.store.node(collection).tag == .list;
        if (is_list) {
            if (cache) |cached| {
                try self.privateCursorBounds(container, index, words);
                try self.cachedListWordAddress(container, index, field, cached);
            } else {
                try self.listRowBounds(container, index, words);
                const base = try self.multiplyLocal(index, words);
                if (cursor) |cached| try self.cachedListWordAddress(container, base, field, try self.cursorCache(cached)) else try self.listWordAddress(container, base, field, false);
            }
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
                    try self.editListRow(place.owner, element_index, changed, place.row_words, null, reuse, place.row_layout);
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
                if (place.array_scalar) |scalar_elements| {
                    try self.allocateArray(scalar_elements, place.row_layout);
                } else if (place.scalar_storage) {
                    try self.emit(.call, arena.allocate_scalar);
                } else if (place.mask) |mask_local| {
                    try self.emit(.local_get, mask_local);
                    try self.emit(.call, arena.allocate_typed);
                } else if (place.shape) |shape_local| {
                    try self.emit(.local_get, shape_local);
                    try self.emit(.call, arena.allocate_shaped);
                } else try self.emit(.call, if (place.row_words != 0) arena.allocate_scalar else arena.allocate);
                try self.emit(.local_set, container);
                if (place.acyclic and !place.scalar_storage) {
                    try self.emit(.local_get, container);
                    try self.emit(.call, arena.mark_acyclic);
                }
                if (place.array_scalar != null or place.mask != null or place.shape != null) try self.emit(.local_get, container);
                try self.emit(.local_get, container);
                try self.emit(.local_get, place.container);
                try self.emit(.local_get, place.size.?);
                if (place.array_scalar != null or place.mask != null or place.shape != null) try self.emit(.call, arena.copy_words) else try self.emit(.memory_copy, 0);
            }
            try self.emit(.local_get, container);
            try self.emit(.local_get, place.offset);
            try self.emit(.i32_add, 0);
            try self.emit(.local_get, changed);
            // A numeric Array's checked element layout has no edges, so its
            // word takes the annotated scalar store `arrayFill` uses. The
            // bounds check stays in `indexLocation`; only the runtime layout
            // lookup of `store_word` goes. Owning and masked words keep it.
            const numeric_word = place.array_scalar == true and place.mask == null and place.shape == null and place.row_words == 0;
            if (numeric_word) {
                try self.storeElement(changed_scalar.machine(), 0, 0, true, 0);
            } else if ((place.array_scalar != null or place.mask != null or place.shape != null) and place.row_words == 0) try self.storeCollectionWord(container, false, changed_scalar.machine(), 0) else try self.storeElement(changed_scalar.machine(), 0, place.row_words, changed_scalar != .pointer, place.row_layout);
            if (place.wrapped) {
                // A copy of a constructor cell: its tag, then its payload.
                const wrapper = if (reuse) place.owner else try self.allocate(8, .{ .words = &.{ .scalar, .reference } });
                if (!reuse) {
                    if (place.acyclic) {
                        try self.emit(.local_get, wrapper);
                        try self.emit(.call, g.module.arena.?.mark_acyclic);
                    }
                    try self.emit(.local_get, wrapper);
                    try self.emit(.local_get, place.owner);
                    try self.emit(.i32_const, 8);
                    try self.emit(.memory_copy, 0);
                }
                try self.emit(.local_get, wrapper);
                try self.emit(.local_get, container);
                try self.storeCollectionWord(wrapper, false, .i32, 4);
                changed = wrapper;
            } else changed = container;
            changed_scalar = .pointer;
        }
        try self.emit(.local_get, changed);
    }
    fn indexLocation(self: *Emitter, array_: u32, index: u32, collection: layout.Id) Error!Location {
        const is_list = self.generator.representations.store.node(collection).tag == .list;
        const words = try self.generator.collectionRowWords(collection);
        if (is_list and words != 0) {
            try self.listRowBounds(array_, index, words);
            return .{ .owner = array_, .container = array_, .offset = index, .size = null, .wrapped = false, .list_index = index, .row_words = words, .row_layout = self.generator.representations.store.node(collection).a };
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
        const row_words = try self.generator.collectionRowWords(collection);
        const size = try self.arraySize(count, packed_layout.stride(row_words));
        const offset = try self.temporary(.i32);
        try self.emit(.local_get, index);
        try self.emit(.i32_const, packed_layout.stride(row_words));
        try self.emit(.i32_mul, 0);
        try self.emit(.i32_const, 4);
        try self.emit(.i32_add, 0);
        try self.emit(.local_set, offset);
        const scalar_elements = row_words != 0 or self.generator.representations.store.scalar(self.generator.representations.store.node(collection).a) != null;
        return .{ .owner = array_, .container = array_, .offset = offset, .size = size, .wrapped = false, .row_words = row_words, .row_layout = self.generator.representations.store.node(collection).a, .array_scalar = scalar_elements };
    }
    fn prepareCollectionStep(self: *Emitter, plans: *Body, id: core.Id, depth: usize) Error!?Plan {
        if (self.dictionary_owner != null) return null;
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const initializer = source.node(id).b;
        const tag = source.node(initializer).tag;
        if (tag != .project and tag != .call) return null;
        const proof = @import("collection_iteration.zig");
        const sink = proof.stepSink(source, try g.unitUses(self.unit_id, .{ .parents = true }), id) orelse return null;
        try self.prepareNode(plans, initializer, depth + 1, false);
        if (!plans.entries.contains(initializer)) return null;
        const initializer_plan = plans.get(initializer);
        var key: Key = undefined;
        var receiver: core.Id = 0;
        if (initializer_plan == .projection and initializer_plan.projection != null and initializer_plan.projection.? == .member) {
            key = initializer_plan.projection.?.member.direct;
            receiver = source.node(initializer).a;
        } else if (tag == .call and initializer_plan == .named and source.call(initializer).arguments.len == 1) {
            key = initializer_plan.named.call.key;
            receiver = source.call(initializer).arguments[0];
        } else return null;
        if (key.count != 1 or key.effects[0] != 0 or key.dictionaries or key.templates != 0 or key.template_result) return null;
        const producer = g.unit(key.target.unit);
        if (!proof.cursorNext(producer, key.target.binding, source, sink.constructor)) return null;
        if (source.nominal(source.constructor(sink.constructor).nominal).is_opaque) return null;
        const cursor = g.representations.store.node(key.parameters[0]);
        if (cursor.tag != .cursor) return null;
        const collection = g.representations.store.node(cursor.a);
        if ((collection.tag != .array and collection.tag != .list) or try g.collectionRowWords(cursor.a) != 0) return null;
        _ = g.representations.toEvidence(g.evaluator.evidenceStore(), key.parameters[0]) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
        const pattern = source.node(sink.pattern);
        const fields = source.patternChildren(source.pattern(pattern.a).b);
        const expected = [_]layout.Id{ collection.a, key.parameters[0] };
        for (fields, expected) |field, concrete| {
            const item = source.pattern(field);
            if (item.tag == .bind and try self.codeLayout(item.ty, source.span(id)) != concrete) return null;
        }
        if (g.artifacts) |artifacts| try artifacts.readInlineBody(key.target);
        try self.preparePattern(plans, pattern.a, depth + 1);
        try self.prepareNode(plans, pattern.b, depth + 1, false);
        try self.prepareNode(plans, pattern.c, depth + 1, false);
        if (sink.pattern != id) try plans.put(g.allocator, sink.pattern, .collection_pattern);
        self.has_collection_steps = true;
        return .{ .collection_step = .{ .pattern = sink.pattern, .receiver = receiver, .key = key } };
    }
    fn emitCollectionStep(self: *Emitter, id: core.Id, depth: usize) Error!bool {
        if (!self.body.?.entries.contains(id)) return false;
        const selected = self.resolvedPlan(id);
        if (selected != .collection_step) return false;
        const plan = selected.collection_step;
        const g = self.generator;
        const producer = g.unit(plan.key.target.unit);
        const producer_body = producer.body(plan.key.target.binding).?.*;
        var service = try g.specializer();
        var resolved = service.named(plan.key, g.representations.instance_arguments.get(plan.key.instance_arguments)) catch |err| return g.specializationFailure(service, err);
        defer resolved.deinit(g.allocator);
        const private = self.privateCursorReference(plan.receiver);
        const receiver = if (private) |fields| fields.values[0] else try self.capture(plan.receiver, depth + 1);
        var emitter: Emitter = .{ .generator = g, .unit_id = plan.key.target.unit, .function_id = self.function_id, .provider_local = self.provider_local, .mappings = resolved.mappings.items, .row_mappings = resolved.rows.items, .cleanups = .{ .parent = &self.cleanups }, .diagnostic_context = try self.inlineContext(), .labels = self.labels };
        defer emitter.deinit();
        const parameter = producer.bodyParameters(&producer_body)[0].binding;
        try emitter.locals.put(g.allocator, parameter, receiver);
        if (private) |fields| try emitter.small_values.put(g.allocator, parameter, fields);
        var prepared = try emitter.prepareBody(producer_body.root, depth + 1, false);
        defer prepared.deinit(g.allocator);
        emitter.body = &prepared;
        emitter.analysis_root = producer_body.root;
        const root = producer.node(producer_body.root);
        try emitter.expression(root.a, depth + 1);
        try self.emit(.if_, 0);
        self.labels += 1;
        emitter.labels = self.labels;
        const source = g.unit(self.unit_id);
        const pattern = source.node(plan.pattern);
        const fields = source.patternChildren(source.pattern(pattern.a).b);
        const values = producer.children(producer.node(root.b).b);
        for (fields, values, 0..) |field, value, index| {
            const bound = source.pattern(field);
            if (index == 1 and private != null) {
                const next = try emitter.advancePrivateCursor(private.?, g.representations.store.listInput(plan.key.parameters[0]));
                if (bound.tag == .bind) try self.savePrivateCursor(bound.a, next);
            } else {
                try emitter.expression(value, depth + 1);
                if (bound.tag == .bind) try self.save(bound.a, plan.pattern) else try self.emit(.drop, 0);
            }
        }
        try self.emit(.else_, 0);
        if (pattern.c == 0) try self.emit(.unreachable_, 0) else if (!try self.suite(pattern.c, depth + 1)) return g.fail(self.unit_id, plan.pattern, .unsupported);
        self.labels -= 1;
        try self.emit(.end, 0);
        return true;
    }
    fn preparePrivateCursorPattern(self: *Emitter, body: *const Body, id: core.Id) Error!Plan {
        if (try self.prepareStaticPattern(id)) |bindings| return .{ .pattern = bindings };
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        if (source.pattern(node.a).tag != .product or source.node(node.b).tag != .array_op or source.arrayOperation(node.b) != .cursor_value) return .{ .pattern = null };
        const operand = source.children(node.b)[0];
        if (source.node(operand).tag != .reference) return .{ .pattern = null };
        const ref = source.reference(operand);
        const cursor = g.representations.store.node(try self.codeLayout(source.typeOf(operand), source.span(id)));
        if ((ref.unit != 0 and ref.unit != self.unit_id) or cursor.tag != .cursor or g.representations.store.node(cursor.a).tag != .list) return .{ .pattern = null };
        const words = try g.collectionRowWords(cursor.a);
        const row = g.representations.store.node(cursor.a).a;
        if (words == 0 or g.representations.store.node(row).tag != .product or source.patternChildren(node.a).len != words or !@import("private_cursor.zig").check(source, try g.unitUses(self.unit_id, .{ .flow = true }), body.root, ref.binding)) return .{ .pattern = null };
        const fields = g.representations.store.children(row);
        for (source.patternChildren(node.a), 0..) |child, index| {
            const pattern = source.pattern(child);
            if (pattern.tag == .wildcard) continue;
            if (pattern.tag != .bind) return .{ .pattern = null };
            const concrete = try self.codeLayout(pattern.ty, source.span(id));
            if (g.representations.store.scalar(concrete) == null or g.representations.store.machine(concrete) != g.representations.store.machine(fields[index])) return .{ .pattern = null };
        }
        return .{ .private_pattern = row };
    }
    fn privateCursorConstructor(self: *Emitter, body: *const Body, id: core.Id) Error!?core.Id {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        if (node.tag == .array_op) {
            if (source.arrayOperation(id) == .cursor) return source.children(id)[0];
            return null;
        }
        if (!body.entries.contains(id)) return null;
        const selected = body.get(id);
        var target: core.BindingRef = undefined;
        var input: core.Id = 0;
        switch (selected) {
            .named => |plan| {
                if (plan.call.key.count != 1 or source.children(id).len != 1) return null;
                target = plan.call.key.target;
                input = source.children(id)[0];
            },
            .projection => |projection_| if (projection_) |projection| switch (projection) {
                .member => |member| {
                    if (member.direct.count != 1) return null;
                    target = member.direct.target;
                    input = node.a;
                },
                else => return null,
            } else return null,
            else => return null,
        }
        const producer = g.unit(target.unit);
        const wrapper = producer.body(target.binding) orelse return null;
        if (wrapper.parameters.len != 1 or producer.node(wrapper.root).tag != .array_op or producer.arrayOperation(wrapper.root) != .cursor) return null;
        const operand = producer.children(wrapper.root)[0];
        if (producer.node(operand).tag != .reference) return null;
        const ref = producer.reference(operand);
        if ((ref.unit != 0 and ref.unit != target.unit) or ref.binding != producer.bodyParameters(wrapper)[0].binding) return null;
        if (g.artifacts) |artifacts| try artifacts.readInlineBody(target);
        return input;
    }
    fn privateCursor(self: *const Emitter, binding: core.BindingId) ?SmallCollection {
        const value = self.small_values.get(binding) orelse return null;
        if (value.kind != .cursor) return null;
        return value;
    }
    fn privateCursorReference(self: *const Emitter, id: core.Id) ?SmallCollection {
        const source = self.generator.unit(self.unit_id);
        if (source.node(id).tag != .reference) return null;
        const ref = source.reference(id);
        if (ref.unit != 0 and ref.unit != self.unit_id) return null;
        return self.privateCursor(ref.binding);
    }
    fn savePrivateCursor(self: *Emitter, binding: core.BindingId, value: SmallCollection) Error!void {
        const g = self.generator;
        var snapshot: SmallCollection = .{ .kind = .cursor, .len = 4 };
        // Every lexical version has independent progress locals. Fields are
        // read before any predecessor version can be overwritten.
        for (value.values[0..4], 0..) |from, index| {
            snapshot.values[index] = try self.temporary(.i32);
            try self.emit(.local_get, from);
            try self.emit(.local_set, snapshot.values[index]);
        }
        try self.small_values.put(g.allocator, binding, snapshot);
        try self.emit(.local_get, snapshot.values[0]);
        try self.save(binding, 0);
    }
    fn privateCursorRow(self: *Emitter, statement: core.Id, row: layout.Id) Error!?RowView {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const binding = source.node(statement);
        const operand = source.children(binding.b)[0];
        const cursor = self.privateCursorReference(operand) orelse return null;
        const input = g.representations.store.node(try self.codeLayout(source.typeOf(operand), source.span(statement)));
        const words = packed_layout.rowWords(&g.representations.store, row);
        const address = try self.temporary(.i32);
        std.debug.assert(g.representations.store.node(input.a).tag == .list);
        try self.privateCursorBounds(cursor.values[0], cursor.values[1], words);
        try self.emit(.local_get, cursor.values[2]);
        try self.emit(.local_get, cursor.values[1]);
        try self.emit(.local_get, cursor.values[3]);
        try self.emit(.i32_sub, 0);
        try self.emit(.i32_const, 4);
        try self.emit(.i32_mul, 0);
        try self.emit(.i32_add, 0);
        try self.emit(.i32_const, @import("../runtime/list_runtime.zig").header);
        try self.emit(.i32_add, 0);
        try self.emit(.local_set, address);
        return .{ .binding = 0, .row = row, .address = address, .limit_address = address };
    }
    fn bindPrivateRow(self: *Emitter, statement: core.Id) Error!bool {
        if (self.body == null or !self.body.?.entries.contains(statement)) return false;
        const selected = self.body.?.get(statement);
        if (selected != .private_row) return false;
        var view = try self.privateCursorRow(statement, selected.private_row) orelse return false;
        view.binding = self.generator.unit(self.unit_id).node(statement).a;
        // The collection owns the leaf. This interior view stays in machine
        // locals and checked projections, never a published source value.
        try self.row_views.append(self.generator.allocator, view);
        return true;
    }
    fn bindPrivateCursor(self: *Emitter, statement: core.Id, depth: usize) Error!bool {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(statement);
        if (self.body == null or !self.body.?.entries.contains(statement)) return false;
        const selected = self.body.?.get(statement);
        if (selected != .private_cursor) return false;
        if (self.privateCursorReference(node.b)) |value| {
            try self.savePrivateCursor(node.a, value);
            return true;
        }
        const value_node = source.node(node.b);
        const cursor = g.representations.store.node(try self.codeLayout(source.binding(node.a).ty, source.span(statement)));
        const is_list = g.representations.store.node(cursor.a).tag == .list;
        const words = @max(1, try g.collectionRowWords(cursor.a));
        var collection: u32 = undefined;
        const index = try self.temporary(.i32);
        var previous: ?CursorPrevious = null;
        if (selected.private_cursor.input != 0) {
            collection = try self.capture(selected.private_cursor.input, depth);
            if (is_list) {
                try self.emit(.local_get, collection);
                try self.emit(.call, try g.module.ensureListSnapshot());
                collection = try self.temporary(.i32);
                try self.emit(.local_set, collection);
            }
            try self.emit(.i32_const, 0);
        } else if (value_node.tag == .array_op and source.arrayOperation(node.b) == .cursor_advance) {
            const value = self.privateCursorReference(source.children(node.b)[0]) orelse return false;
            collection = value.values[0];
            try self.privateCursorBounds(collection, value.values[1], words);
            try self.emit(.local_get, value.values[1]);
            try self.emit(.i32_const, words);
            try self.emit(.i32_add, 0);
            previous = .{ .fields = .{ value.values[2], value.values[3] } };
        } else {
            const boxed = try self.capture(node.b, depth);
            var fields: SmallCollection = .{ .kind = .cursor, .len = 4 };
            inline for (.{ "collection", "index", "leaf", "base" }, 0..) |name, field| {
                fields.values[field] = try self.temporary(.i32);
                try self.emit(.local_get, boxed);
                try self.emit(.i32_load, heap.offset(heap.Cursor, name));
                try self.emit(.local_set, fields.values[field]);
            }
            try self.rootDirective(5, fields.values[0]);
            try self.savePrivateCursor(node.a, fields);
            return true;
        }
        try self.emit(.local_set, index);
        if (selected.private_cursor.linear) |linear| {
            const directory = try self.startCursorDirectory(collection);
            try self.cursor_directories.put(g.allocator, linear.advance, directory);
            try self.savePrivateCursor(node.a, try self.cursorDirectoryFields(collection, index, directory));
        } else if (self.cursor_directories.get(statement)) |directory| {
            try self.savePrivateCursor(node.a, try self.cursorDirectoryFields(collection, index, directory));
        } else try self.savePrivateCursor(node.a, try self.cursorFields(collection, index, is_list, previous, 1));
        return true;
    }
    fn startCursorDirectory(self: *Emitter, collection: u32) Error!CursorDirectory {
        var span: [3]u32 = undefined;
        for (&span) |*field| {
            field.* = try self.temporary(.i32);
            try self.emit(.i32_const, 0);
            try self.emit(.local_set, field.*);
        }
        const length = try self.temporary(.i32);
        try self.emit(.local_get, collection);
        try self.emit(.i32_load, heap.offset(heap.ListDescriptor, "length"));
        try self.emit(.local_set, length);
        // Existing directory construction and its owning holder run once at
        // cursor creation. Per-row reads below do not update descriptor hints,
        // call runtime helpers or alter the current root journal.
        const directory = try self.loopListDirectory(collection, length);
        // Carry roots live in a child frame that closes before the holder's
        // identity-detaching recycle. This preserves the existing persistent
        // slot proof across the whole loop without admitting recycle calls.
        try self.openRootScope();
        return .{ .directory = directory, .span = span };
    }
    fn cursorDirectoryFields(self: *Emitter, collection: u32, index: u32, cursor: CursorDirectory) Error!SmallCollection {
        // Only the admitted monotone advance moves this private directory
        // position. Saved versions keep copied immutable leaf/base fields.
        try self.emit(.local_get, index);
        try self.emit(.local_get, collection);
        try self.emit(.i32_load, heap.offset(heap.ListDescriptor, "length"));
        try self.emit(.i32_lt_u, 0);
        try self.emit(.if_, 0);
        try self.emit(.local_get, index);
        try self.emit(.local_get, cursor.span[2]);
        try self.emit(.i32_ge_u, 0);
        try self.emit(.if_, 0);
        try self.emit(.local_get, cursor.directory.array);
        try self.emit(.local_get, cursor.directory.offset);
        try self.emit(.i32_add, 0);
        try self.emit(.i32_load, @sizeOf(heap.Array));
        try self.emit(.local_set, cursor.span[0]);
        try self.emit(.local_get, cursor.directory.offset);
        try self.emit(.i32_const, 4);
        try self.emit(.i32_add, 0);
        try self.emit(.local_set, cursor.directory.offset);
        try self.emit(.local_get, cursor.span[2]);
        try self.emit(.local_tee, cursor.span[1]);
        try self.emit(.local_get, cursor.span[0]);
        try self.emit(.i32_load, heap.offset(heap.ListNode, "length"));
        try self.emit(.i32_add, 0);
        try self.emit(.local_set, cursor.span[2]);
        try self.emit(.end, 0);
        try self.emit(.end, 0);
        var fields: SmallCollection = .{ .kind = .cursor, .len = 4 };
        fields.values[0] = collection;
        fields.values[1] = index;
        fields.values[2] = cursor.span[0];
        fields.values[3] = cursor.span[1];
        return fields;
    }
    fn smallCollectionCandidate(self: *const Emitter, id: core.Id) bool {
        const source = self.generator.unit(self.unit_id);
        const n = source.node(id);
        if (n.tag == .reference) {
            if (source.types.node(n.ty).tag == .cursor) return false;
            const ref = source.reference(id);
            if (ref.unit != 0 and ref.unit != self.unit_id) return false;
            const value = self.small_values.get(ref.binding) orelse return false;
            return value.kind == .collection;
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
        const ty = g.representations.store.node(try self.codeLayout(n.ty, source.span(id)));
        if ((ty.tag != .array and ty.tag != .list) or g.representations.store.scalar(ty.a) == null) return null;
        var result: SmallCollection = .{ .machine = g.representations.store.machine(ty.a) };
        if (n.tag == .array) {
            const children = source.children(id);
            result.len = children.len;
            for (children, 0..) |child, i| result.values[i] = try self.capture(child, depth);
            g.planning.facts.stats.small_collections += 1;
            return result;
        }
        const call = source.call(id);
        const key = self.resolvedPlan(id).named.call.key;
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
        for (children) |child| {
            try locals.append(scratch, try self.capture(child, depth));
            if (unit_.types.node(unit_.typeOf(child)).tag == .never) return;
        }
        var collection_layout = g.representations.store.node(try self.codeLayout(unit_.typeOf(id), unit_.span(id)));
        if (collection_layout.tag == .owning) collection_layout = g.representations.store.node(collection_layout.a);
        const row_words = try g.rowWords(collection_layout.a);
        const scalar_elements = row_words != 0 or g.representations.store.scalar(collection_layout.a) != null;
        if (collection_layout.tag == .list) {
            const runtime = try g.module.ensureLists();
            const address = try self.temporary(.i32);
            if (children.len > 0x10000000 / @max(1, row_words)) return g.fail(self.unit_id, id, .complexity);
            try self.emit(.i32_const, @intCast(children.len * @max(1, row_words)));
            var scalar_words: u32 = 0;
            if (scalar_elements) scalar_words = @max(1, row_words);
            try self.emit(.i32_const, try self.listKind(scalar_words, collection_layout.a));
            try self.emit(.i32_const, @import("../runtime/list_runtime.zig").leafLimit(@max(1, row_words)));
            try self.emit(.call, runtime.new);
            try self.emit(.local_set, address);
            for (children, locals.items, 0..) |child, value, index| {
                if (row_words != 0) {
                    const position = try self.temporary(.i32);
                    try self.emit(.i32_const, @intCast(index));
                    try self.emit(.local_set, position);
                    try self.storeListRow(address, position, value, row_words, collection_layout.a);
                    continue;
                }
                try self.emit(.local_get, address);
                try self.emit(.i32_const, @intCast(index));
                try self.emit(.call, runtime.address);
                try self.emit(.local_get, value);
                const machine = (try self.scalar(child)).machine();
                if (scalar_elements) {
                    try self.storeScalar(if (machine == .f32) .f32_store else .i32_store, 0);
                } else if (g.layoutRole(collection_layout.a) == .reference) {
                    try self.storeCollectionWord(address, true, machine, 0);
                } else try self.emit(if (machine == .f32) .f32_store else .i32_store, 0);
            }
            try self.emit(.local_get, address);
            return;
        }
        const stride = packed_layout.stride(row_words);
        if (children.len > (std.math.maxInt(u32) - 4) / stride) return g.fail(self.unit_id, id, .complexity);
        // A length word, then the elements.
        const address = try self.allocateStorage(@intCast(children.len * stride + 4), scalar_elements or row_words != 0, .{ .words = &.{.scalar}, .rest = g.layoutRole(collection_layout.a) });
        if (!scalar_elements and row_words == 0 and g.layoutRole(collection_layout.a) == .reference) try self.markAcyclic(address, collection_layout.a);
        try self.emit(.local_get, address);
        try self.emit(.i32_const, @intCast(children.len));
        try self.emit(.i32_store, 0);
        for (children, locals.items, 0..) |child, value, index| {
            try self.emit(.local_get, address);
            try self.emit(.local_get, value);
            try self.storeElement((try self.scalar(child)).machine(), @intCast(index * stride + 4), row_words, scalar_elements, collection_layout.a);
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
    const NumericPlan = @import("numeric_rows.zig").Plan;
    /// Nested blocks guard every dereference; an inactive arm never supplies a
    /// pointer or payload. The same plan controls the packed and owning ABI.
    fn rowGuard(self: *Emitter, plan: *const NumericPlan, guard: ?u8, objects: ?[]const u32, fields: []const u32) Error!usize {
        const id = guard orelse return 0;
        const condition = plan.guards[id];
        const depth = try self.rowGuard(plan, condition.parent, objects, fields);
        if (objects) |values| {
            try self.emit(.local_get, values[condition.owner]);
            try self.emit(.i32_load, 0);
        } else try self.emit(.local_get, fields[condition.word]);
        try self.emit(.i32_const, condition.tag);
        try self.emit(.i32_eq, 0);
        try self.emit(.if_, 0);
        return depth + 1;
    }
    fn rowGuardEnd(self: *Emitter, count: usize) Error!void {
        for (0..count) |_| try self.emit(.end, 0);
    }
    fn validateRowTags(self: *Emitter, plan: *const NumericPlan, fields: []const u32) Error!void {
        for (plan.leaves[0..plan.leaf_count]) |leaf| {
            if (!leaf.discriminant) continue;
            const blocks = try self.rowGuard(plan, leaf.guard, null, fields);
            var first = true;
            for (plan.guards[0..plan.guard_count]) |guard| {
                if (guard.owner != leaf.owner or guard.word != leaf.word) continue;
                try self.emit(.local_get, fields[leaf.word]);
                try self.emit(.i32_const, guard.tag);
                try self.emit(.i32_eq, 0);
                if (!first) try self.emit(.i32_or, 0);
                first = false;
            }
            std.debug.assert(!first);
            try self.emit(.i32_eqz, 0);
            try self.emit(.if_, 0);
            try self.emit(.unreachable_, 0);
            try self.emit(.end, 0);
            try self.rowGuardEnd(blocks);
        }
    }
    fn unpackRow(self: *Emitter, fields: []const u32, element: layout.Id) Error!void {
        const plan = try self.generator.nestedRow(element) orelse {
            const row = try self.allocateStorage(@intCast(fields.len * 4), true, .scalar);
            for (fields, 0..) |field, index| {
                try self.emit(.local_get, row);
                try self.emit(.local_get, field);
                try self.emit(.i32_store, @intCast(index * 4));
            }
            return self.emit(.local_get, row);
        };
        std.debug.assert(fields.len == plan.word_count);
        try self.validateRowTags(&plan, fields);
        var objects: [32]u32 = undefined;
        for (plan.storage[0..plan.storage_count], 0..) |storage, index| {
            if (storage.guard != null or storage.unit_payload) objects[index] = try self.temporary(.i32);
        }
        const result = if (plan.storage[0].guard != null) try self.temporary(.i32) else null;
        var next: usize = plan.storage_count;
        while (next > 0) {
            next -= 1;
            const storage = plan.storage[next];
            const blocks = try self.rowGuard(&plan, storage.guard, null, fields);
            if (storage.unit_payload) {
                // Empty variants keep their ordinary immortal representation.
                // Materializing a packed Nothing must not allocate on every read.
                try self.nullaryConstructor(storage.tag.?);
                try self.emit(.local_set, objects[next]);
                if (storage.parent == null and result != null) {
                    try self.emit(.local_get, objects[next]);
                    try self.emit(.local_set, result.?);
                }
                try self.rowGuardEnd(blocks);
                continue;
            }
            var roles: [16]ir.Role = undefined;
            for (0..storage.bytes / 4) |index| roles[index] = if (storage.references & (@as(u16, 1) << @intCast(index)) != 0) .reference else .scalar;
            const object = try self.allocateStorage(storage.bytes, storage.references == 0, .{ .words = roles[0 .. storage.bytes / 4], .rest = .scalar });
            if (storage.tag) |tag| {
                try self.emit(.local_get, object);
                try self.emit(.i32_const, tag);
                try self.emit(.i32_store, 0);
            }
            for (plan.leaves[0..plan.leaf_count]) |leaf| {
                if (leaf.owner != next or leaf.discriminant) continue;
                try self.emit(.local_get, object);
                try self.emit(.local_get, fields[leaf.word]);
                try self.emit(.i32_store, leaf.offset);
            }
            for (plan.storage[0..plan.storage_count], 0..) |child, index| {
                if (child.parent == null or child.parent.? != next) continue;
                const active = try self.rowGuard(&plan, child.guard, null, fields);
                try self.emit(.local_get, object);
                try self.emit(.local_get, objects[index]);
                try self.emit(.i32_store, child.offset);
                try self.rowGuardEnd(active);
            }
            if (storage.references != 0) try self.markAcyclic(object, storage.layout);
            // Initialize through the allocation's own local before publishing
            // an alias. Unguarded rows need no merge local: retaining the direct
            // owner lets scalar replacement erase their temporary boxes.
            if (storage.guard != null) {
                try self.emit(.local_get, object);
                try self.emit(.local_set, objects[next]);
            } else objects[next] = object;
            if (storage.parent == null and result != null) {
                try self.emit(.local_get, object);
                try self.emit(.local_set, result.?);
            }
            try self.rowGuardEnd(blocks);
        }
        try self.emit(.local_get, result orelse objects[0]);
    }
    fn packRow(self: *Emitter, row: u32, words: u32, element: layout.Id) Error![16]u32 {
        var fields: [16]u32 = undefined;
        for (fields[0..words]) |*field| field.* = try self.temporary(.i32);
        if (try self.generator.nestedRow(element)) |plan| {
            std.debug.assert(words == plan.word_count);
            // This path can run repeatedly in a loop. Reset padding on every row.
            if (plan.guard_count != 0) for (fields[0..words]) |field| {
                try self.emit(.i32_const, 0);
                try self.emit(.local_set, field);
            };
            var objects: [32]u32 = undefined;
            for (plan.storage[0..plan.storage_count], 0..) |storage, index| {
                objects[index] = try self.temporary(.i32);
                var blocks: usize = 0;
                if (storage.parent) |parent| {
                    blocks = try self.rowGuard(&plan, plan.storage[parent].guard, &objects, &.{});
                    try self.emit(.local_get, objects[parent]);
                    try self.emit(.i32_load, storage.offset);
                } else try self.emit(.local_get, row);
                try self.emit(.local_set, objects[index]);
                try self.rowGuardEnd(blocks);
            }
            for (plan.leaves[0..plan.leaf_count]) |leaf| {
                const blocks = try self.rowGuard(&plan, leaf.guard, &objects, &.{});
                try self.emit(.local_get, objects[leaf.owner]);
                try self.emit(.i32_load, leaf.offset);
                try self.emit(.local_set, fields[leaf.word]);
                try self.rowGuardEnd(blocks);
            }
            try self.validateRowTags(&plan, fields[0..words]);
        } else for (fields[0..words], 0..) |field, index| {
            try self.emit(.local_get, row);
            try self.emit(.i32_load, @intCast(index * 4));
            try self.emit(.local_set, field);
        }
        return fields;
    }
    fn readElement(self: *Emitter, machine: wasm.ValueType, offset: u32, row_words: u32, element: layout.Id) Error!void {
        if (row_words == 0) return self.emit(if (machine == .f32) .f32_load else .i32_load, offset);
        const source = try self.temporary(.i32);
        try self.emit(.local_set, source);
        if (try self.generator.nestedRow(element) == null) {
            const row = try self.allocateStorage(row_words * 4, true, .scalar);
            for (0..row_words) |i| {
                const field: u32 = @intCast(i * 4);
                try self.emit(.local_get, row);
                try self.emit(.local_get, source);
                try self.emit(.i32_load, offset + field);
                try self.emit(.i32_store, field);
            }
            return self.emit(.local_get, row);
        }
        var fields: [16]u32 = undefined;
        for (0..row_words) |i| {
            const field: u32 = @intCast(i * 4);
            fields[i] = try self.temporary(.i32);
            try self.emit(.local_get, source);
            try self.emit(.i32_load, offset + field);
            try self.emit(.local_set, fields[i]);
        }
        try self.unpackRow(fields[0..row_words], element);
    }
    fn storeScalar(self: *Emitter, op: wasm.Op, offset: u32) Error!void {
        try self.generator.module.emit(self.function_id, ir.scalarStore(ir.fixed(op).bytes));
        try self.emit(op, offset);
    }
    fn storeElement(self: *Emitter, machine: wasm.ValueType, offset: u32, row_words: u32, scalar_element: bool, element: layout.Id) Error!void {
        if (row_words == 0) {
            const op: wasm.Op = if (machine == .f32) .f32_store else .i32_store;
            if (scalar_element) return self.storeScalar(op, offset);
            return self.emit(op, offset);
        }
        const row = try self.temporary(.i32);
        const destination = try self.temporary(.i32);
        try self.emit(.local_set, row);
        try self.emit(.local_set, destination);
        const fields: ?[16]u32 = if (try self.generator.nestedRow(element) != null) try self.packRow(row, row_words, element) else null;
        for (0..row_words) |i| {
            const field: u32 = @intCast(i * 4);
            try self.emit(.local_get, destination);
            if (fields) |values| {
                try self.emit(.local_get, values[i]);
            } else {
                try self.emit(.local_get, row);
                try self.emit(.i32_load, field);
            }
            try self.storeScalar(.i32_store, offset + field);
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
    /// One check admits four elements from `index`, before any address
    /// arithmetic, so a wrapping index cannot select unrelated lanes.
    fn simdArrayBounds(self: *Emitter, array_: u32, index: u32) Error!void {
        const length = try self.temporary(.i32);
        try self.emit(.local_get, array_);
        try self.emit(.i32_load, 0);
        try self.emit(.local_tee, length);
        try self.emit(.i32_const, 4);
        try self.emit(.i32_lt_u, 0);
        try self.emit(.local_get, index);
        try self.emit(.local_get, length);
        try self.emit(.i32_const, 4);
        try self.emit(.i32_sub, 0);
        try self.emit(.i32_gt_u, 0);
        try self.emit(.i32_or, 0);
        try self.emit(.if_, 0);
        try self.emit(.unreachable_, 0);
        try self.emit(.end, 0);
    }
    /// A fresh copy of a word-element Array whose snapshot must survive.
    fn copyScalarArray(self: *Emitter, source: u32) Error!u32 {
        const changed = try self.temporary(.i32);
        const count = try self.temporary(.i32);
        try self.emit(.local_get, source);
        try self.emit(.i32_load, 0);
        try self.emit(.local_set, count);
        const size = try self.arraySize(count, 4);
        try self.emit(.local_get, size);
        try self.allocateArray(true, null);
        try self.emit(.local_set, changed);
        try self.emit(.local_get, changed);
        try self.emit(.local_get, changed);
        try self.emit(.local_get, source);
        try self.emit(.local_get, size);
        try self.emit(.call, (try self.generator.module.ensureArena()).copy_words);
        return changed;
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
    /// A numeric Array has no children; other elements are owning references.
    /// A known reference element layout with an exact acyclic proof marks
    /// the fresh Array once for all of its edges. Scalar storage has none.
    fn allocateArray(self: *Emitter, scalar_elements: bool, element: ?layout.Id) Error!void {
        const arena = try self.generator.module.ensureArena();
        if (scalar_elements) return self.emit(.call, arena.allocate_scalar);
        try self.emit(.i32_const, 0xfffffffe);
        try self.emit(.call, arena.allocate_typed);
        const known = element orelse return;
        if (!try self.generator.acyclicLayout(known)) return;
        const array_ = try self.temporary(.i32);
        try self.emit(.local_tee, array_);
        try self.emit(.call, arena.mark_acyclic);
        try self.emit(.local_get, array_);
    }
    /// The address/value stack pair targets an explicitly known allocation.
    /// List element addresses borrow the descriptor's current leaf base.
    fn storeCollectionWord(self: *Emitter, owner: u32, is_list: bool, machine: wasm.ValueType, offset: u32) Error!void {
        const value = try self.temporary(.i32);
        const address = try self.temporary(.i32);
        if (machine == .f32) try self.emit(.i32_reinterpret_f32, 0);
        try self.emit(.local_set, value);
        try self.emit(.local_set, address);
        try self.emit(.local_get, owner);
        if (is_list) try self.emit(.i32_load, heap.offset(heap.ListDescriptor, "cached_leaf"));
        try self.emit(.local_get, address);
        if (offset != 0) {
            try self.emit(.i32_const, offset);
            try self.emit(.i32_add, 0);
        }
        try self.emit(.local_get, value);
        try self.emit(.call, (try self.generator.module.ensureArena()).store_word);
    }
    const PackedProducer = struct { template: Template, ty: layout.Id };
    fn packedValue(self: *Emitter, comptime encoding: bool, id: core.Id, plan: *const NumericPlan, parent: ?u8, offset: u32, fields: []const u32, depth: usize) Error!bool {
        if (depth >= 64) return false;
        const g = self.generator;
        const source = g.unit(self.unit_id);
        for (plan.leaves[0..plan.leaf_count]) |leaf| {
            if (leaf.discriminant or parent != leaf.owner or offset != leaf.offset) continue;
            if (encoding) {
                if (id == 0) try self.emit(.i32_const, 0) else {
                    try self.expression(id, depth + 1);
                    if (leaf.floating) try self.emit(.i32_reinterpret_f32, 0);
                }
                try self.emit(.local_set, fields[leaf.word]);
            }
            return true;
        }
        if (id == 0) return false;
        const node = source.node(id);
        if (node.tag == .if_value) {
            if (encoding) {
                try self.expression(node.a, depth + 1);
                try self.emit(.if_, 0);
                self.labels += 1;
            }
            if (!try self.packedValue(encoding, node.b, plan, parent, offset, fields, depth + 1)) return false;
            if (encoding) try self.emit(.else_, 0);
            if (!try self.packedValue(encoding, node.c, plan, parent, offset, fields, depth + 1)) return false;
            if (encoding) {
                self.labels -= 1;
                try self.emit(.end, 0);
            }
            return true;
        }
        if (node.tag != .construct and node.tag != .record and node.tag != .product) {
            return false;
        }
        const tag: ?u32 = if (node.tag == .construct) source.constructor(node.a).tag else null;
        const selected: u8 = for (plan.storage[0..plan.storage_count], 0..) |storage, index| {
            if (storage.parent == parent and storage.offset == offset and storage.tag == tag) break @intCast(index);
        } else return false;
        if (node.tag == .construct) {
            if (encoding) if (plan.storage[selected].guard) |active| {
                const guard = plan.guards[active];
                // A single-constructor wrapper inherits its parent's guard.
                if (guard.owner == selected or plan.storage[guard.owner].parent == parent and plan.storage[guard.owner].offset == offset) {
                    try self.emit(.i32_const, tag.?);
                    try self.emit(.local_set, fields[guard.word]);
                }
            };
            return self.packedValue(encoding, node.b, plan, selected, 4, fields, depth + 1);
        }
        const children = source.children(id);
        const record = node.tag == .record;
        const destinations = if (record) source.recordDestinations(id) else &.{};
        const physical = if (record) try @import("../check/record_order.zig").destinations(g.allocator, source.types, source.types.node(source.typeOf(id)), &g.representations.store.record_names) else &.{};
        defer g.allocator.free(physical);
        for (children, 0..) |child, index| {
            const declared = if (record) destinations[index] else index;
            const slot = if (physical.len == 0) declared else physical[declared];
            if (!try self.packedValue(encoding, child, plan, selected, @intCast(slot * 4), fields, depth + 1)) return false;
        }
        return true;
    }
    fn generatedPackedRow(self: *Emitter, producer: PackedProducer, index: u32, destination: u32, is_list: bool, plan: *const NumericPlan) Error!bool {
        const g = self.generator;
        if (self.inline_depth >= 6 or producer.template.templates != 0 or producer.template.staged != 0 or producer.template.callable_instances != 0 or self.dictionary_owner != null) return false;
        const owner = if (producer.template.unit == 0) self.unit_id else producer.template.unit;
        const source = g.unit(owner);
        const node = source.node(producer.template.node);
        const arrow = g.representations.store.node(producer.ty);
        var mappings: std.ArrayList(Mapping) = .empty;
        var rows: std.ArrayList(RowMapping) = .empty;
        defer mappings.deinit(g.allocator);
        defer rows.deinit(g.allocator);
        var emitter: Emitter = .{ .generator = g, .unit_id = owner, .function_id = self.function_id, .provider_local = self.provider_local, .mappings = &.{}, .cleanups = .{ .parent = &self.cleanups }, .diagnostic_context = try self.inlineContext(), .labels = self.labels, .inline_depth = self.inline_depth + 1, .inline_loop = true };
        defer emitter.deinit();
        var root: core.Id = undefined;
        if (node.tag == .reference) {
            const target = try g.normalize(owner, source.reference(producer.template.node));
            const unit_ = g.unit(target.unit);
            const body = unit_.body(target.binding) orelse return false;
            if (body.parameters.len != 1 or !body.is_function) return false;
            if ((@import("inline_body.zig").cost(unit_, body.root) orelse return false) > 64) return false;
            var key: Key = .{ .target = target, .count = 1, .result = arrow.b };
            key.parameters[0] = arrow.a;
            key.effects[0] = arrow.c;
            var service = try g.specializer();
            var resolved = service.named(key, &.{}) catch |err| return g.specializationFailure(service, err);
            defer resolved.deinit(g.allocator);
            try mappings.appendSlice(g.allocator, resolved.mappings.items);
            try rows.appendSlice(g.allocator, resolved.rows.items);
            emitter.unit_id = target.unit;
            root = body.root;
            try emitter.locals.put(g.allocator, unit_.bodyParameters(body)[0].binding, index);
            if (g.artifacts) |artifacts| try artifacts.readInlineBody(target);
        } else if (node.tag == .closure) {
            const closure_ = source.closures[node.a];
            if ((@import("inline_body.zig").cost(source, closure_.body) orelse return false) > 64) return false;
            const key: ClosureKey = .{ .unit = owner, .catalog = node.a, .ty = producer.ty, .captures = producer.template.captures, .scalar_environment = producer.template.scalar_environment, .evidence = producer.template.evidence, .rows = producer.template.rows };
            try g.resolveClosureMappings(key, &mappings, &rows);
            root = closure_.body;
            try emitter.locals.put(g.allocator, closure_.parameter.binding, index);
        } else return false;
        emitter.mappings = mappings.items;
        emitter.row_mappings = rows.items;
        if (!try emitter.packedValue(false, root, plan, null, 0, &.{}, 0)) return false;
        if (node.tag == .closure) {
            const closure_ = source.closures[node.a];
            for (source.extra[closure_.captures.start..][0..closure_.captures.len], 0..) |binding, position| {
                const concrete = g.representations.store.children(producer.template.captures)[position];
                const machine = g.representations.store.machine(concrete);
                const local = try self.temporary(machine);
                try self.emit(.local_get, producer.template.environment.?);
                if (!producer.template.scalar_environment) try self.emit(if (machine == .f32) .f32_load else .i32_load, @intCast(position * 4));
                try self.emit(.local_set, local);
                try emitter.locals.put(g.allocator, binding, local);
            }
        }
        var body = try emitter.prepareBody(root, 0, false);
        defer body.deinit(g.allocator);
        emitter.body = &body;
        emitter.analysis_root = root;
        emitter.mappings = body.mappings;
        emitter.row_mappings = body.rows;
        var fields: [16]u32 = undefined;
        for (fields[0..plan.word_count]) |*field| {
            field.* = try self.temporary(.i32);
            try self.emit(.i32_const, 0);
            try self.emit(.local_set, field.*);
        }
        std.debug.assert(try emitter.packedValue(true, root, plan, null, 0, fields[0..plan.word_count], 0));
        const base = if (is_list) try self.multiplyLocal(index, plan.word_count) else undefined;
        for (fields[0..plan.word_count], 0..) |field, position| {
            if (is_list) try self.listWordAddress(destination, base, @intCast(position), false) else try self.arrayAddress(destination, index, plan.stride());
            try self.emit(.local_get, field);
            try self.storeScalar(.i32_store, if (is_list) 0 else @intCast(4 + position * 4));
        }
        return true;
    }
    fn arrayFill(self: *Emitter, count: u32, value: u32, machine: wasm.ValueType, is_generated: bool, is_list: bool, known: ?u32, element: layout.Id, producer: ?PackedProducer) Error!void {
        const row_words = try self.generator.rowWords(element);
        const copied_row_scope = is_generated and try self.generator.nestedRow(element) != null;
        const iteration_cleanup = self.cleanups.mark();
        defer if (copied_row_scope) self.cleanups.restore(iteration_cleanup);
        const stride = packed_layout.stride(row_words);
        const scalar_elements = row_words != 0 or self.generator.representations.store.scalar(element) != null;
        const size = try self.arraySize(count, stride);
        const array_ = try self.temporary(.i32);
        const index = try self.temporary(.i32);
        const physical = if (is_list and row_words > 1) try self.listWordCount(count, row_words) else count;
        try self.emit(.local_get, if (is_list) physical else size);
        if (is_list) {
            var scalar_words: u32 = 0;
            if (scalar_elements) scalar_words = @max(1, row_words);
            try self.emit(.i32_const, try self.listKind(scalar_words, element));
            try self.emit(.i32_const, @import("../runtime/list_runtime.zig").leafLimit(@max(1, row_words)));
        }
        if (is_list) try self.emit(.call, (try self.generator.module.ensureLists()).new) else try self.allocateArray(scalar_elements, element);
        try self.emit(.local_set, array_);
        try self.emit(.local_get, array_);
        try self.emit(.local_get, if (is_list) physical else count);
        if (is_list) try self.storeCollectionWord(array_, false, .i32, 0) else try self.emit(.i32_store, 0);
        try self.emit(.i32_const, 0);
        try self.emit(.local_set, index);
        try self.emit(.block, 0);
        try self.emit(.loop, 0);
        self.labels += 2;
        try self.emit(.local_get, index);
        try self.emit(.local_get, count);
        try self.emit(.i32_ge_u, 0);
        try self.emit(.br_if, 1);
        // Bound temporary object graphs to 32 rows while amortizing frame
        // bookkeeping. The destination owns only scalar bits. Older captures
        // still belong to their enclosing normal root scope.
        var chunk_end: ?u32 = null;
        if (copied_row_scope) {
            try self.openRootScope();
            chunk_end = try self.temporary(.i32);
            // arraySize already bounds count below 2^30, so adding 32 cannot
            // wrap. Clamp the final partial chunk to the checked count.
            try self.emit(.local_get, index);
            try self.emit(.i32_const, 32);
            try self.emit(.i32_add, 0);
            try self.emit(.local_tee, chunk_end.?);
            try self.emit(.local_get, count);
            try self.emit(.i32_gt_u, 0);
            try self.emit(.if_, 0);
            try self.emit(.local_get, count);
            try self.emit(.local_set, chunk_end.?);
            try self.emit(.end, 0);
            try self.emit(.loop, 0);
            self.labels += 1;
        }
        const direct = if (producer) |candidate| direct: {
            const plan = try self.generator.nestedRow(element) orelse break :direct false;
            if (plan.guard_count == 0) break :direct false;
            break :direct try self.generatedPackedRow(candidate, index, array_, is_list, &plan);
        } else false;
        if (!direct) {
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
                try self.storeListRow(array_, index, row, row_words, element);
            } else if (is_list) try self.storeCollectionWord(array_, true, machine, 0) else if (!scalar_elements) try self.storeCollectionWord(array_, false, machine, 4) else try self.storeElement(machine, 4, row_words, scalar_elements, element);
        }
        try self.emit(.local_get, index);
        try self.emit(.i32_const, 1);
        try self.emit(.i32_add, 0);
        try self.emit(.local_set, index);
        if (copied_row_scope) {
            try self.emit(.local_get, index);
            try self.emit(.local_get, chunk_end.?);
            try self.emit(.i32_lt_u, 0);
            try self.emit(.br_if, 0);
            self.labels -= 1;
            try self.emit(.end, 0);
            try self.cleanupTo(iteration_cleanup);
            self.cleanups.restore(iteration_cleanup);
        }
        try self.emit(.br, 0);
        self.labels -= 2;
        try self.emit(.end, 0);
        try self.emit(.end, 0);
        try self.emit(.local_get, array_);
    }
    fn advancePrivateCursor(self: *Emitter, fields: SmallCollection, is_list: bool) Error!SmallCollection {
        try self.privateCursorBounds(fields.values[0], fields.values[1], 1);
        const index = try self.temporary(.i32);
        try self.emit(.local_get, fields.values[1]);
        try self.emit(.i32_const, 1);
        try self.emit(.i32_add, 0);
        try self.emit(.local_set, index);
        return self.cursorFields(fields.values[0], index, is_list, .{ .fields = .{ fields.values[2], fields.values[3] } }, 1);
    }
    fn privateCursorOperation(self: *Emitter, id: core.Id) Error!bool {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const op = source.arrayOperation(id);
        if (op != .cursor_has and op != .cursor_value) return false;
        const operand = source.children(id)[0];
        const cursor = self.privateCursorReference(operand) orelse return false;
        const input = g.representations.store.node(try self.codeLayout(source.typeOf(operand), source.span(id)));
        const collection = g.representations.store.node(input.a);
        const words = try g.collectionRowWords(input.a);
        if (words == 0) {
            if (op == .cursor_has) {
                try self.privateCursorRemaining(cursor.values[0], cursor.values[1]);
                try self.emit(.i32_const, 1);
                try self.emit(.i32_ge_u, 0);
            } else {
                try self.privateCursorBounds(cursor.values[0], cursor.values[1], 1);
                if (collection.tag == .list) try self.cachedListWordAddress(cursor.values[0], cursor.values[1], 0, .{ cursor.values[2], cursor.values[3] }) else try self.arrayAddress(cursor.values[0], cursor.values[1], 4);
                try self.readElement(g.representations.store.machine(collection.a), if (collection.tag == .list) 0 else 4, 0, collection.a);
            }
            return true;
        }
        std.debug.assert(collection.tag == .list);
        if (op == .cursor_has) {
            try self.privateCursorRemaining(cursor.values[0], cursor.values[1]);
            try self.emit(.i32_const, words);
            try self.emit(.i32_ge_u, 0);
        } else {
            try self.privateCursorBounds(cursor.values[0], cursor.values[1], words);
            // Owned extraction still consumes the ordinary logical-row API.
            const index = try self.temporary(.i32);
            try self.emit(.local_get, cursor.values[1]);
            try self.emit(.i32_const, words);
            try self.emit(.i32_div_u, 0);
            try self.emit(.local_set, index);
            try self.readListRow(cursor.values[0], index, words, .{ cursor.values[2], cursor.values[3] }, null, collection.a);
        }
        return true;
    }
    fn arrayOperation(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const operands = unit_.children(id);
        if (try self.privateCursorOperation(id)) return;
        if (operands.len > 3) return g.fail(self.unit_id, id, .unsupported);
        if (self.ragged_count) |probe| {
            if (probe.plan.storage.conversion == id) return self.expression(operands[0], depth + 1);
            if (probe.plan.storage.append == id) {
                try self.emit(.local_get, probe.count);
                try self.emit(.i32_const, probe.limit);
                try self.emit(.i32_ge_u, 0);
                try self.declineRaggedCount();
                try self.emit(.local_get, probe.count);
                try self.emit(.i32_const, 1);
                try self.emit(.i32_add, 0);
                try self.emit(.local_set, probe.count);
                return self.emit(.i32_const, 0);
            }
        }
        if (self.exact_build) |builder| {
            if (builder.plan.conversion == id) return self.expression(operands[0], depth + 1);
            if (builder.plan.append == id) {
                const value = try self.capture(operands[1], depth);
                const element_layout = try self.codeLayout(unit_.typeOf(operands[1]), unit_.span(operands[1]));
                const element_role = g.layoutRole(element_layout);
                const element_machine = g.representations.store.machine(element_layout);
                const is_list = builder.plan.conversion == 0;
                if (is_list and builder.row_words != 0) {
                    try self.storeListRow(builder.storage, builder.index, value, builder.row_words, element_layout);
                } else {
                    if (is_list) {
                        try self.emit(.local_get, builder.storage);
                        try self.emit(.local_get, builder.index);
                        try self.emit(.call, (try g.module.ensureLists()).address);
                    } else try self.arrayAddress(builder.storage, builder.index, packed_layout.stride(builder.row_words));
                    try self.emit(.local_get, value);
                    const offset: u32 = if (is_list) 0 else 4;
                    if (builder.row_words == 0 and element_role == .reference) {
                        try self.storeCollectionWord(builder.storage, is_list, element_machine, offset);
                    } else try self.storeElement(element_machine, offset, builder.row_words, element_role == .scalar, element_layout);
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
            const template = try self.boxTemplate((try self.callableTemplate(operands[1])).?);
            const callback = try self.codeLayout(unit_.typeOf(operands[1]), unit_.span(id));
            const result = try self.codeLayout(unit_.typeOf(id), unit_.span(id));
            const env = template.environment orelse blk: {
                const local = try self.temporary(.i32);
                try self.emit(.i32_const, 0);
                try self.emit(.local_set, local);
                break :blk local;
            };
            return self.arrayFill(count, env, g.representations.store.machine(g.representations.store.node(result).a), true, g.representations.store.node(result).tag == .list, try self.templateFunction(template, callback, false), g.representations.store.node(result).a, .{ .template = template, .ty = callback });
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
        const collection = g.representations.store.node(try self.codeLayout(source.typeOf(plan.initial), source.span(id)));
        const is_list = plan.conversion == 0;
        const row_words = try g.rowWords(collection.a);
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
        try self.fillExactBuilder(id, plan, count, eligible, depth);
        g.planning.facts.stats.exact_builders += 1;
    }
    fn fillExactBuilder(self: *Emitter, id: core.Id, plan: exact_builder.Plan, count: u32, eligible: u32, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const collection = g.representations.store.node(try self.codeLayout(source.typeOf(plan.initial), source.span(id)));
        const is_list = plan.conversion == 0;
        const row_words = try g.rowWords(collection.a);
        const stride = packed_layout.stride(row_words);
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
        const scalar_elements = row_words != 0 or g.representations.store.scalar(collection.a) != null;
        const size = if (is_list) (if (row_words > 1) try self.listWordCount(count, row_words) else count) else try self.arraySize(count, stride);
        const storage = try self.temporary(.i32);
        try self.emit(.local_get, size);
        if (is_list) {
            var scalar_words: u32 = 0;
            if (scalar_elements) scalar_words = @max(1, row_words);
            try self.emit(.i32_const, try self.listKind(scalar_words, collection.a));
            try self.emit(.i32_const, @import("../runtime/list_runtime.zig").leafLimit(@max(1, row_words)));
        }
        if (is_list) try self.emit(.call, (try g.module.ensureLists()).new) else try self.allocateArray(scalar_elements, collection.a);
        try self.emit(.local_set, storage);
        if (!is_list) {
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
    }
    const RaggedFacts = struct {
        emitter: *const Emitter,
        pub fn primitive(self: @This(), id: core.Id) bool {
            if (!self.emitter.body.?.entries.contains(id)) return false;
            const entry = self.emitter.body.?.get(id);
            if (entry == .named) {
                const key = entry.named.call.key;
                if (key.count != 2 or key.parameters[0] != key.parameters[1]) return false;
                const machine = self.emitter.generator.representations.store.scalar(key.parameters[0]) orelse return false;
                const operation = @import("../check/primitive_operator.zig").analyzeTyped(self.emitter.generator.units, key.target, machine) orelse return false;
                return @import("../check/primitive_operator.zig").total(operation);
            }
            if (entry != .dispatch) return false;
            if (entry.dispatch == .scalar) return true;
            if (entry.dispatch != .selected) return false;
            const operation = @import("../check/primitive_operator.zig").analyze(self.emitter.generator.units, entry.dispatch.selected.key.target) orelse return false;
            return @import("../check/primitive_operator.zig").total(operation);
        }
        pub fn reference(self: @This(), id: core.Id) bool {
            const source = self.emitter.generator.unit(self.emitter.unit_id);
            const ref = source.reference(id);
            if (ref.unit == 0 or ref.unit == source.unit) {
                const binding = source.binding(ref.binding);
                if (binding.kind == .local or binding.kind == .parameter) return !self.emitter.templates.contains(ref.binding);
            }
            const target = self.emitter.body.?.get(id).reference orelse return false;
            const declaration = self.emitter.generator.unit(target.unit).body(target.binding) orelse return false;
            // Runtime cells are initialized before guest entry; frozen values
            // are already established during semantic preparation. Reading an
            // existing cell executes no source behavior. Named function values
            // still require descriptor creation and remain outside this proof.
            return !declaration.is_function;
        }
        pub fn field(self: @This(), id: core.Id) bool {
            if (!self.emitter.body.?.entries.contains(id)) return false;
            const entry = self.emitter.body.?.get(id);
            if (entry != .projection) return false;
            const projection = entry.projection orelse return false;
            return projection == .field;
        }
        pub fn pattern(self: @This(), id: core.Id) bool {
            if (!self.emitter.body.?.entries.contains(id)) return false;
            const entry = self.emitter.body.?.get(id);
            return entry == .loop and !entry.loop.refutable;
        }
    };
    fn declineRaggedCount(self: *Emitter) Error!void {
        const probe = self.ragged_count.?;
        try self.emit(.if_, 0);
        self.labels += 1;
        try self.emit(.i32_const, 0);
        try self.emit(.local_set, probe.eligible);
        try self.cleanupTo(probe.cleanup);
        try self.emit(.br, self.labels - 1 - probe.exit);
        self.labels -= 1;
        try self.emit(.end, 0);
    }
    fn raggedBuilder(self: *Emitter, id: core.Id, plan: ragged_builder.Plan, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        for (plan.expressions[0..plan.expression_count]) |expression_| try self.raggedDependencies(expression_);
        try self.raggedDependencies(plan.storage.value);
        const collection = g.representations.store.node(try self.codeLayout(source.typeOf(plan.storage.initial), source.span(id)));
        const words = try g.rowWords(collection.a);
        const limit = ragged_builder.maximumCount(words, plan.storage.conversion == 0).?;
        const count = try self.temporary(.i32);
        const eligible = try self.temporary(.i32);
        const budget = try self.temporary(.i32);
        try self.emit(.i32_const, 0);
        try self.emit(.local_set, count);
        try self.emit(.i32_const, 1);
        try self.emit(.local_set, eligible);
        try self.emit(.i32_const, g.ragged_probe_limit);
        try self.emit(.local_set, budget);
        const previous_probe = self.exact_probe;
        const previous_count = self.ragged_count;
        self.exact_probe = true;
        defer {
            self.exact_probe = previous_probe;
            self.ragged_count = previous_count;
        }
        try self.emit(.block, 0);
        const probe: RaggedCount = .{ .plan = plan, .count = count, .eligible = eligible, .budget = budget, .limit = limit, .exit = self.labels, .cleanup = self.cleanups.mark() };
        self.ragged_count = &probe;
        self.labels += 1;
        try self.expression(id, depth + 1);
        try self.emit(.drop, 0);
        self.labels -= 1;
        try self.emit(.end, 0);
        self.ragged_count = previous_count;
        const previous_fill = self.ragged_fill;
        self.ragged_fill = true;
        defer self.ragged_fill = previous_fill;
        try self.fillExactBuilder(id, plan.storage, count, eligible, depth);
        g.evaluator.counters.ragged_runtime_regions += 1;
    }
    fn raggedDependencies(self: *Emitter, id: core.Id) Error!void {
        if (id == 0 or self.generator.artifacts == null) return;
        const source = self.generator.unit(self.unit_id);
        const n = source.node(id);
        switch (n.tag) {
            .scalar, .associated => {
                const dispatch = self.body.?.get(id).dispatch;
                if (dispatch == .selected) {
                    const operation = @import("../check/primitive_operator.zig").analyze(self.generator.units, dispatch.selected.key.target).?;
                    for (operation.dependencies[0..operation.dependency_count]) |target| try self.generator.artifacts.?.readInlineBody(target);
                }
                try self.raggedDependencies(n.a);
                try self.raggedDependencies(n.b);
            },
            .call => {
                const key = self.body.?.get(id).named.call.key;
                const machine = self.generator.representations.store.scalar(key.parameters[0]).?;
                const operation = @import("../check/primitive_operator.zig").analyzeTyped(self.generator.units, key.target, machine).?;
                for (operation.dependencies[0..operation.dependency_count]) |target| try self.generator.artifacts.?.readInlineBody(target);
                for (source.children(id)) |child| try self.raggedDependencies(child);
            },
            .logical => {
                try self.raggedDependencies(n.a);
                try self.raggedDependencies(n.b);
            },
            .if_value => {
                try self.raggedDependencies(n.a);
                try self.raggedDependencies(n.b);
                try self.raggedDependencies(n.c);
            },
            .project => try self.raggedDependencies(n.a),
            .array_op => try self.raggedDependencies(source.children(id)[0]),
            else => {},
        }
    }
    pub fn arrayLocals(self: *Emitter, id: core.Id, op: core.ArrayOp, locals: []const u32, machines: []const wasm.ValueType, result_layout: layout.Id, input_layout: layout.Id) Error!void {
        const g = self.generator;
        const result = g.representations.store.machine(result_layout);
        const input_list = g.representations.store.listInput(input_layout);
        const input_node = g.representations.store.node(input_layout);
        const input_collection = if (input_node.tag == .cursor) input_node.a else input_layout;
        const row_words = try g.collectionRowWords(input_collection);
        const stride = packed_layout.stride(row_words);
        const expected = @import("collection_ops.zig").arity(op);
        if (locals.len == 0 or locals.len != expected or machines.len != expected) return g.fail(self.unit_id, id, .unsupported);
        switch (op) {
            .flatten => try self.arrayFlatten(locals[0], g.representations.store.node(result_layout).a),
            .simd_load, .simd_store => {
                // Four word-sized scalar elements move as one v128 value.
                const element = g.representations.store.scalar(input_node.a) orelse return g.fail(self.unit_id, id, .unsupported);
                if (input_list or row_words != 0 or (element != .u32 and element != .f32 and element != .bool)) return g.fail(self.unit_id, id, .unsupported);
                try self.simdArrayBounds(locals[0], locals[1]);
                if (op == .simd_load) {
                    const address = try self.allocateStorage(16, true, .scalar);
                    try self.emit(.local_get, address);
                    try self.arrayAddress(locals[0], locals[1], 4);
                    try self.emit(.v128_load, 4);
                    try self.emit(.v128_store, 0);
                    return self.emit(.local_get, address);
                }
                const reuse = id != 0 and (self.owned_edit == id or try g.ownsArrayUpdate(self.unit_id, id));
                const changed = if (reuse) locals[0] else try self.copyScalarArray(locals[0]);
                try self.arrayAddress(changed, locals[1], 4);
                try self.simdLoad(locals[2]);
                try self.storeScalar(.v128_store, 4);
                try self.emit(.local_get, changed);
            },
            .cursor => try self.createCollectionCursor(locals[0], input_list, row_words),
            .cursor_has, .cursor_value, .cursor_advance => try self.readCollectionCursor(locals[0], op, input_list, input_collection, row_words, stride, result),
            .concat, .slice => {
                if (input_list) {
                    if (op == .slice and row_words != 0) return self.sliceListRows(locals, row_words);
                    for (locals) |local| try self.emit(.local_get, local);
                    const runtime = try g.module.ensureLists();
                    try self.emit(.call, if (op == .concat) runtime.concat else runtime.slice);
                } else try self.arrayStructural(op, locals, row_words != 0 or g.representations.store.scalar(g.representations.store.node(result_layout).a) != null, stride, g.representations.store.node(result_layout).a);
            },
            .length => {
                try self.emit(.local_get, locals[0]);
                try self.emit(.i32_load, 0);
                try self.logicalListLength(input_collection);
            },
            .get => {
                const proven = try self.numericCheck(id);
                if (input_list and row_words != 0) {
                    if (!proven) try self.listRowBounds(locals[0], locals[1], row_words);
                    return self.readListRow(locals[0], locals[1], row_words, null, null, g.representations.store.node(input_collection).a);
                }
                if (!proven) try self.arrayBounds(locals[0], locals[1]);
                if (input_list) {
                    var address = (try g.module.ensureLists()).address;
                    if (proven) address = try g.module.ensureUncheckedListAddress();
                    try self.emit(.local_get, locals[0]);
                    try self.emit(.local_get, locals[1]);
                    try self.emit(.call, address);
                } else try self.arrayAddress(locals[0], locals[1], stride);
                try self.readElement(result, if (input_list) 0 else 4, row_words, g.representations.store.node(input_collection).a);
            },
            .set => {
                const reuse = id != 0 and (self.owned_edit == id or try g.ownsArrayUpdate(self.unit_id, id));
                if (input_list) {
                    if (row_words != 0) return self.editListRow(locals[0], locals[1], locals[2], row_words, null, reuse, g.representations.store.node(input_collection).a);
                    try self.emit(.local_get, locals[0]);
                    try self.emit(.local_get, locals[1]);
                    try self.emit(.local_get, locals[2]);
                    if (machines[2] == .f32) try self.emit(.i32_reinterpret_f32, 0);
                    try self.emit(.i32_const, @intFromBool(reuse));
                    var set = (try g.module.ensureLists()).set;
                    if (try self.numericCheck(id)) set = try g.module.ensureUncheckedListSet();
                    try self.emit(.call, set);
                    return;
                }
                if (!try self.numericCheck(id)) try self.arrayBounds(locals[0], locals[1]);
                const changed = if (reuse) locals[0] else try self.temporary(.i32);
                if (!reuse) {
                    const count = try self.temporary(.i32);
                    try self.emit(.local_get, locals[0]);
                    try self.emit(.i32_load, 0);
                    try self.emit(.local_set, count);
                    const size = try self.arraySize(count, stride);
                    try self.emit(.local_get, size);
                    try self.allocateArray(row_words != 0 or g.representations.store.scalar(g.representations.store.node(result_layout).a) != null, g.representations.store.node(result_layout).a);
                    try self.emit(.local_set, changed);
                    try self.emit(.local_get, changed);
                    try self.emit(.local_get, changed);
                    try self.emit(.local_get, locals[0]);
                    try self.emit(.local_get, size);
                    try self.emit(.call, (try g.module.ensureArena()).copy_words);
                }
                try self.arrayAddress(changed, locals[1], stride);
                try self.emit(.local_get, locals[2]);
                // Numeric elements are checked scalar words, as in `arrayFill`.
                const numeric = g.representations.store.scalar(g.representations.store.node(result_layout).a) != null;
                if (row_words == 0 and !numeric) try self.storeCollectionWord(changed, false, machines[2], 4) else try self.storeElement(machines[2], 4, row_words, true, g.representations.store.node(input_collection).a);
                try self.emit(.local_get, changed);
            },
            .fill => try self.arrayFill(locals[0], locals[1], machines[1], false, g.representations.store.node(result_layout).tag == .list, null, g.representations.store.node(result_layout).a, null),
            .generate => try self.arrayFill(locals[0], locals[1], g.representations.store.machine(g.representations.store.node(result_layout).a), true, g.representations.store.node(result_layout).tag == .list, null, g.representations.store.node(result_layout).a, null),
            .identity => try self.emit(.local_get, locals[0]),
            .convert => {
                const words = try g.rowWords(g.representations.store.node(result_layout).a);
                if (words != 0) return self.convertRows(locals[0], input_list, words);
                try self.emit(.local_get, locals[0]);
                const runtime = try g.module.ensureLists();
                const element = g.representations.store.node(result_layout).a;
                if (!input_list) try self.emit(.i32_const, try self.listKind(@intFromBool(g.representations.store.scalar(element) != null), element));
                try self.emit(.call, if (input_list) runtime.to_array else runtime.from_array);
            },
            .append, .prepend => {
                if (input_list) {
                    if (row_words != 0) return self.editListRow(locals[0], null, locals[1], row_words, op == .prepend, id != 0 and try g.ownsArrayUpdate(self.unit_id, id), g.representations.store.node(input_collection).a);
                    try self.emit(.local_get, locals[0]);
                    try self.emit(.local_get, locals[1]);
                    if (machines[1] == .f32) try self.emit(.i32_reinterpret_f32, 0);
                    try self.emit(.i32_const, @intFromBool(op == .prepend));
                    try self.emit(.i32_const, @intFromBool(id != 0 and try g.ownsArrayUpdate(self.unit_id, id)));
                    try self.emit(.call, (try g.module.ensureLists()).push);
                } else try self.arrayPush(locals[0], locals[1], machines[1], op == .prepend, row_words != 0 or g.representations.store.scalar(g.representations.store.node(result_layout).a) != null, row_words, g.representations.store.node(result_layout).a);
            },
        }
    }
    /// Flatten consumes already-evaluated chunks. Both passes preserve their
    /// order; copies use the same physical row plan and owning-word helper as
    /// concat/slice, so saved chunks remain valid for every element layout.
    fn arrayFlatten(self: *Emitter, chunks: u32, element: layout.Id) Error!void {
        const g = self.generator;
        const words = try g.rowWords(element);
        const stride = packed_layout.stride(words);
        const count = try self.temporary(.i32);
        const total = try self.temporary(.i32);
        const index = try self.temporary(.i32);
        const chunk = try self.temporary(.i32);
        const length = try self.temporary(.i32);
        const offset = try self.temporary(.i32);
        const destination = try self.temporary(.i32);
        try self.emit(.local_get, chunks);
        try self.emit(.i32_load, 0);
        try self.emit(.local_set, count);
        try self.emit(.i32_const, 0);
        try self.emit(.local_set, total);
        inline for (.{ false, true }) |copying| {
            if (copying) {
                const bytes = try self.arraySize(total, stride);
                try self.emit(.local_get, bytes);
                try self.allocateArray(words != 0 or g.representations.store.scalar(element) != null, element);
                try self.emit(.local_set, destination);
                try self.emit(.local_get, destination);
                try self.emit(.local_get, total);
                try self.emit(.i32_store, 0);
                try self.emit(.i32_const, 0);
                try self.emit(.local_set, offset);
            }
            try self.emit(.i32_const, 0);
            try self.emit(.local_set, index);
            try self.emit(.block, 0);
            try self.emit(.loop, 0);
            self.labels += 2;
            try self.emit(.local_get, index);
            try self.emit(.local_get, count);
            try self.emit(.i32_ge_u, 0);
            try self.emit(.br_if, 1);
            try self.arrayAddress(chunks, index, 4);
            try self.emit(.i32_load, 4);
            try self.emit(.local_tee, chunk);
            try self.emit(.i32_load, 0);
            try self.emit(.local_set, length);
            if (copying) {
                try self.emit(.local_get, destination);
                try self.arrayAddress(destination, offset, stride);
                try self.emit(.i32_const, 4);
                try self.emit(.i32_add, 0);
                try self.emit(.local_get, chunk);
                try self.emit(.i32_const, 4);
                try self.emit(.i32_add, 0);
                try self.emit(.local_get, length);
                try self.emit(.i32_const, stride);
                try self.emit(.i32_mul, 0);
                try self.emit(.call, g.module.arena.?.copy_words);
                try self.emit(.local_get, offset);
                try self.emit(.local_get, length);
                try self.emit(.i32_add, 0);
                try self.emit(.local_set, offset);
            } else {
                try self.emit(.local_get, total);
                try self.emit(.local_get, length);
                try self.emit(.i32_add, 0);
                try self.emit(.local_tee, offset);
                try self.emit(.local_get, total);
                try self.emit(.i32_lt_u, 0);
                try self.emit(.if_, 0);
                try self.emit(.unreachable_, 0);
                try self.emit(.end, 0);
                try self.emit(.local_get, offset);
                try self.emit(.local_set, total);
            }
            try self.emit(.local_get, index);
            try self.emit(.i32_const, 1);
            try self.emit(.i32_add, 0);
            try self.emit(.local_set, index);
            try self.emit(.br, 0);
            self.labels -= 2;
            try self.emit(.end, 0);
            try self.emit(.end, 0);
        }
        try self.emit(.local_get, destination);
    }
    fn createCollectionCursor(self: *Emitter, first: u32, input_list: bool, row_words: u32) Error!void {
        const g = self.generator;
        const snapshot = if (input_list) try self.temporary(.i32) else first;
        if (input_list) {
            try self.emit(.local_get, first);
            try self.emit(.call, try g.module.ensureListSnapshot());
            try self.emit(.local_set, snapshot);
        }
        const index = try self.temporary(.i32);
        try self.emit(.i32_const, 0);
        try self.emit(.local_set, index);
        try self.cursorPosition(snapshot, index, input_list, null, row_words);
    }
    fn readCollectionCursor(self: *Emitter, first: u32, op: core.ArrayOp, input_list: bool, input_collection: layout.Id, row_words: u32, stride: u32, result: wasm.ValueType) Error!void {
        const g = self.generator;
        const source = try self.temporary(.i32);
        const index = try self.temporary(.i32);
        try self.emit(.local_get, first);
        try self.emit(.i32_load, heap.offset(heap.Cursor, "collection"));
        try self.emit(.local_set, source);
        try self.emit(.local_get, first);
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
                    try self.readListRow(source, index, row_words, try self.cursorCache(first), null, g.representations.store.node(input_collection).a);
                } else {
                    const next = try self.temporary(.i32);
                    try self.emit(.local_get, index);
                    try self.emit(.i32_const, 1);
                    try self.emit(.i32_add, 0);
                    try self.emit(.local_set, next);
                    try self.cursorPosition(source, next, true, first, row_words);
                }
                return;
            }
            try self.arrayBounds(source, index);
            if (op == .cursor_value) {
                if (input_list) {
                    const leaf = try self.temporary(.i32);
                    try self.emit(.local_get, first);
                    try self.emit(.i32_load, heap.offset(heap.Cursor, "leaf"));
                    try self.emit(.local_tee, leaf);
                    try self.emit(.if_, @backingInt(wasm.ValueType.i32));
                    try self.emit(.local_get, leaf);
                    try self.emit(.local_get, index);
                    try self.emit(.local_get, first);
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
                    // The cursor bounds check above proves this exact
                    // immutable snapshot's physical word is available.
                    try self.emit(.call, try g.module.ensureUncheckedListAddress());
                    try self.emit(.end, 0);
                } else try self.arrayAddress(source, index, stride);
                try self.readElement(result, if (input_list) 0 else 4, row_words, g.representations.store.node(input_collection).a);
            } else {
                const next = try self.temporary(.i32);
                try self.emit(.local_get, index);
                try self.emit(.i32_const, 1);
                try self.emit(.i32_add, 0);
                try self.emit(.local_set, next);
                try self.cursorPosition(source, next, input_list, first, row_words);
            }
        }
    }

    /// The AVL runtime stores words. Typed boundaries translate logical row
    /// positions; a row may cross leaves without exposing interior pointers.
    fn logicalListLength(self: *Emitter, collection: layout.Id) Error!void {
        if (self.generator.representations.store.node(collection).tag != .list) return;
        const words = try self.generator.collectionRowWords(collection);
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
    fn privateCursorRemaining(self: *Emitter, source: u32, position: u32) Error!void {
        // Creation starts at zero; checked advances add a complete row, so
        // every private snapshot has position <= its immutable word length.
        try self.emit(.local_get, source);
        try self.emit(.i32_load, 0);
        try self.emit(.local_get, position);
        try self.emit(.i32_sub, 0);
    }
    fn privateCursorBounds(self: *Emitter, source: u32, position: u32, words: u32) Error!void {
        try self.privateCursorRemaining(source, position);
        try self.emit(.i32_const, words);
        try self.emit(.i32_lt_u, 0);
        try self.emit(.if_, 0);
        try self.emit(.unreachable_, 0);
        try self.emit(.end, 0);
    }
    fn listWordAddress(self: *Emitter, source: u32, base: u32, field: u32, proven: bool) Error!void {
        var address = (try self.generator.module.ensureLists()).address;
        if (proven) address = try self.generator.module.ensureUncheckedListAddress();
        try self.emit(.local_get, source);
        try self.emit(.local_get, base);
        if (field != 0) {
            try self.emit(.i32_const, field);
            try self.emit(.i32_add, 0);
        }
        try self.emit(.call, address);
    }
    fn resolveListSpan(self: *Emitter, source: u32, position: u32, span: [3]u32, walk: ?list_traversal.Walk) Error!void {
        if (walk) |path| return list_traversal.next(&self.generator.module, self.function_id, span, path);
        try self.emit(.local_get, source);
        try self.emit(.local_get, position);
        try self.emit(.call, (try self.generator.module.ensureLists()).address);
        try self.emit(.drop, 0);
        try self.emit(.local_get, source);
        try self.emit(.i32_load, 8);
        try self.emit(.local_set, span[0]);
        try self.emit(.local_get, source);
        try self.emit(.i32_load, 12);
        try self.emit(.local_tee, span[1]);
        try self.emit(.local_get, span[0]);
        try self.emit(.i32_load, 8);
        try self.emit(.i32_add, 0);
        try self.emit(.local_set, span[2]);
    }
    fn listSpanAddress(self: *Emitter, position: u32, span: [3]u32) Error!void {
        try self.emit(.local_get, span[0]);
        try self.emit(.local_get, position);
        try self.emit(.local_get, span[1]);
        try self.emit(.i32_sub, 0);
        try self.emit(.i32_const, 4);
        try self.emit(.i32_mul, 0);
        try self.emit(.i32_add, 0);
        try self.emit(.i32_const, @import("../runtime/list_runtime.zig").header);
        try self.emit(.i32_add, 0);
    }
    fn readListSpanRow(self: *Emitter, source: u32, base: u32, words: u32, span: [3]u32, walk: ?list_traversal.Walk, element: layout.Id) Error!void {
        // Every stored row occupies one leaf. The source descriptor roots its
        // immutable tree while these private physical addresses are live.
        try self.emit(.local_get, base);
        try self.emit(.local_get, span[2]);
        try self.emit(.i32_ge_u, 0);
        try self.emit(.if_, 0);
        try self.resolveListSpan(source, base, span, walk);
        try self.emit(.end, 0);
        const address = try self.temporary(.i32);
        try self.listSpanAddress(base, span);
        try self.emit(.local_set, address);
        var fields: [16]u32 = undefined;
        for (fields[0..words], 0..) |*field, i| {
            field.* = try self.temporary(.i32);
            try self.emit(.local_get, address);
            try self.emit(.i32_load, @intCast(i * 4));
            try self.emit(.local_set, field.*);
        }
        try self.unpackRow(fields[0..words], element);
    }
    fn readListRowView(self: *Emitter, words: u32, span: [3]u32, view: RowView, directory: ListDirectory) Error!void {
        // A monotone complete-row traversal begins at the next whole leaf.
        // The directory covers the immutable tree in order; every leaf is
        // nonempty and row aligned. No word-to-row-to-word round trip or
        // physical one-past pointer is needed to recover its two addresses.
        try self.emit(.local_get, directory.array);
        try self.emit(.local_get, directory.offset);
        try self.emit(.i32_add, 0);
        try self.emit(.i32_load, @sizeOf(heap.Array));
        try self.emit(.local_set, span[0]);
        try self.emit(.local_get, directory.offset);
        try self.emit(.i32_const, 4);
        try self.emit(.i32_add, 0);
        try self.emit(.local_set, directory.offset);
        try self.emit(.local_get, span[0]);
        try self.emit(.i32_const, @import("../runtime/list_runtime.zig").header);
        try self.emit(.i32_add, 0);
        try self.emit(.local_set, view.address);
        try self.emit(.local_get, span[0]);
        try self.emit(.i32_load, heap.offset(heap.ListNode, "length"));
        const length = try self.temporary(.i32);
        try self.emit(.local_set, length);
        try self.emit(.local_get, span[2]);
        try self.emit(.local_get, length);
        try self.emit(.i32_add, 0);
        try self.emit(.local_set, span[2]);
        try self.emit(.local_get, view.address);
        try self.emit(.local_get, length);
        try self.emit(.i32_const, words);
        try self.emit(.i32_sub, 0);
        try self.emit(.i32_const, 4);
        try self.emit(.i32_mul, 0);
        try self.emit(.i32_add, 0);
        try self.emit(.local_set, view.limit_address);
    }
    fn readListRow(self: *Emitter, source: u32, index: u32, words: u32, cache: ?[2]u32, span_end: ?u32, element: layout.Id) Error!void {
        const base = try self.multiplyLocal(index, words);
        var fields: [16]u32 = undefined;
        for (fields[0..words]) |*field| field.* = try self.temporary(.i32);
        if (cache) |cached| {
            const relative = try self.temporary(.i32);
            try self.emit(.local_get, base);
            try self.emit(.local_get, cached[1]);
            try self.emit(.i32_sub, 0);
            try self.emit(.local_set, relative);
            if (span_end) |end| {
                // A direct loop has resolved the nonempty immutable leaf and
                // proved base >= its start. List storage is bounded well below
                // u32 overflow, so only the row's end needs checking here.
                try self.emit(.local_get, base);
                try self.emit(.i32_const, words);
                try self.emit(.i32_add, 0);
                try self.emit(.local_get, end);
                try self.emit(.i32_le_u, 0);
            } else {
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
            }
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
            try self.listWordAddress(source, base, @intCast(i), true);
            try self.emit(.i32_load, 0);
            try self.emit(.local_set, field);
        }
        if (cache != null) try self.emit(.end, 0);
        // Resolve conditional leaf reads before initializing the row, so the
        // ordinary scalar replacement proof sees complete dominating stores.
        try self.unpackRow(fields[0..words], element);
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
        try self.listWordAddress(source, base, field, false);
        try self.emit(.end, 0);
    }
    fn storeListRow(self: *Emitter, source: u32, index: u32, row: u32, words: u32, element: layout.Id) Error!void {
        const base = try self.multiplyLocal(index, words);
        const fields: ?[16]u32 = if (try self.generator.nestedRow(element) != null) try self.packRow(row, words, element) else null;
        for (0..words) |i| {
            try self.listWordAddress(source, base, @intCast(i), false);
            if (fields) |values| {
                try self.emit(.local_get, values[i]);
            } else {
                try self.emit(.local_get, row);
                try self.emit(.i32_load, @intCast(i * 4));
            }
            try self.storeScalar(.i32_store, 0);
        }
    }
    fn editListRow(self: *Emitter, source: u32, index: ?u32, row: u32, words: u32, front: ?bool, reuse: bool, element: layout.Id) Error!void {
        const runtime = try self.generator.module.ensureLists();
        const result = try self.temporary(.i32);
        const base = if (index) |value| blk: {
            try self.listRowBounds(source, value, words);
            break :blk try self.multiplyLocal(value, words);
        } else null;
        const fields: ?[16]u32 = if (try self.generator.nestedRow(element) != null) try self.packRow(row, words, element) else null;
        for (0..words) |step| {
            const i = if (front == true) words - 1 - step else step;
            try self.emit(.local_get, if (step == 0) source else result);
            if (base) |position| {
                try self.emit(.local_get, position);
                try self.emit(.i32_const, @intCast(i));
                try self.emit(.i32_add, 0);
            }
            if (fields) |values| {
                try self.emit(.local_get, values[i]);
            } else {
                try self.emit(.local_get, row);
                try self.emit(.i32_load, @intCast(i * 4));
            }
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
            try self.storeScalar(.i32_store, 0);
            try self.emit(.local_get, result);
        }
    }
    /// Construct all fields once, so local cursors still admit scalar
    /// replacement. Stored pointers are allocation bases, never interior
    /// addresses, and a published cursor is never mutated.
    const CursorPrevious = union(enum) { boxed: u32, fields: [2]u32 };
    fn cursorFields(self: *Emitter, source: u32, index: u32, is_list: bool, previous: ?CursorPrevious, row_words: u32) Error!SmallCollection {
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
                switch (cursor) {
                    .boxed => |value| {
                        try self.emit(.local_get, value);
                        try self.emit(.i32_load, heap.offset(heap.Cursor, "base"));
                        try self.emit(.local_set, base);
                        try self.emit(.local_get, value);
                        try self.emit(.i32_load, heap.offset(heap.Cursor, "leaf"));
                    },
                    .fields => |values| {
                        try self.emit(.local_get, values[1]);
                        try self.emit(.local_set, base);
                        try self.emit(.local_get, values[0]);
                    },
                }
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
        var fields: SmallCollection = .{ .kind = .cursor, .len = 4 };
        fields.values[0] = source;
        fields.values[1] = index;
        fields.values[2] = leaf;
        fields.values[3] = base;
        return fields;
    }
    fn cursorPosition(self: *Emitter, source: u32, index: u32, is_list: bool, previous: ?u32, row_words: u32) Error!void {
        var old: ?CursorPrevious = null;
        if (previous) |cursor| old = .{ .boxed = cursor };
        const fields = try self.cursorFields(source, index, is_list, old, row_words);
        const address = try self.allocate(@sizeOf(heap.Cursor), .heap(heap.Cursor));
        inline for (.{ "collection", "index", "leaf", "base" }, 0..) |name, i| {
            const value = fields.values[i];
            try self.emit(.local_get, address);
            try self.emit(.local_get, value);
            try self.emit(.i32_store, heap.offset(heap.Cursor, name));
        }
        try self.emit(.local_get, address);
    }
    fn arrayPush(self: *Emitter, source: u32, value: u32, machine: wasm.ValueType, front: bool, scalar_elements: bool, row_words: u32, element: layout.Id) Error!void {
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
        try self.allocateArray(scalar_elements, element);
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
        try self.storeElement(machine, if (front) 4 else 0, row_words, scalar_elements, element);
        try self.emit(.local_get, result);
    }
    /// Applies one four-lane operation to captured operand locals. Vector
    /// operands are product addresses, a shift count is a scalar word, and a
    /// pair operand arrives as its two vector addresses. The result is a fresh
    /// scalar-only product (or a Bool for a reduction); scalar replacement
    /// keeps private products in v128 locals.
    pub fn simdLocals(self: *Emitter, op: core.Op, operands: []const u32, lanes: ?[4]u8, input: layout.Id, result: layout.Id) Error!void {
        const g = self.generator;
        const vector_layout = if (simd_intrinsics.pairs(op) or op == .swizzle) result else input;
        const fields = g.representations.store.children(vector_layout);
        if (fields.len != 4) return g.fail(self.unit_id, 0, .unsupported);
        const scalar_type = g.representations.store.scalar(fields[0]) orelse return g.fail(self.unit_id, 0, .unsupported);
        for (fields) |field| if (field != fields[0]) return g.fail(self.unit_id, 0, .unsupported);
        const floating = scalar_type == .f32;
        const expected: usize = switch (op) {
            .select, .relaxed_madd, .relaxed_nmadd => 3,
            .shuffle, .shift_left, .shift_right, .shift_right_signed, .min, .max, .bit_andnot => 2,
            .swizzle, .broadcast, .bits, .from_bits, .bit_not, .any_true, .all_true => 1,
            else => operands.len,
        };
        if (operands.len != expected or operands.len == 0) return g.fail(self.unit_id, 0, .unsupported);
        if (simd_intrinsics.literalLanes(op) and lanes == null) return g.fail(self.unit_id, 0, .simd_lane_literal);
        if (op == .any_true or op == .all_true) {
            try self.simdLoad(operands[0]);
            return self.emit(if (op == .any_true) .v128_any_true else .i32x4_all_true, 0);
        }
        const address = try self.allocateStorage(16, true, .scalar);
        try self.emit(.local_get, address);
        switch (op) {
            .shift_left, .shift_right, .shift_right_signed => {
                if (floating) return g.fail(self.unit_id, 0, .unsupported);
                try self.simdLoad(operands[0]);
                try self.emit(.local_get, operands[1]);
                try self.emit(switch (op) {
                    .shift_left => .i32x4_shl,
                    .shift_right => .i32x4_shr_u,
                    else => .i32x4_shr_s,
                }, 0);
            },
            .shuffle, .swizzle, .broadcast => {
                // Swizzles and broadcasts select only from the first operand.
                try self.simdLoad(operands[0]);
                try self.simdLoad(operands[operands.len - 1]);
                var packed_lanes: u32 = 0;
                for (lanes.?, 0..) |lane, index| packed_lanes |= @as(u32, lane) << @intCast(index * 3);
                try self.emit(.i8x16_shuffle, packed_lanes);
            },
            .select => {
                // v128.bitselect takes yes, no, then the mask.
                try self.simdLoad(operands[1]);
                try self.simdLoad(operands[2]);
                try self.simdLoad(operands[0]);
                try self.emit(.v128_bitselect, 0);
            },
            .relaxed_madd, .relaxed_nmadd => {
                if (!floating) return g.fail(self.unit_id, 0, .unsupported);
                for (operands) |operand| try self.simdLoad(operand);
                try self.emit(if (op == .relaxed_madd) .f32x4_relaxed_madd else .f32x4_relaxed_nmadd, 0);
            },
            .convert_i32_f32, .convert_f32_i32 => {
                if (floating != (op == .convert_f32_i32)) return g.fail(self.unit_id, 0, .unsupported);
                try self.simdLoad(operands[0]);
                try self.emit(if (op == .convert_i32_f32) .f32x4_convert_i32x4_s else .i32x4_trunc_sat_f32x4_s, 0);
            },
            .min, .max => if (floating) {
                // pmin b a is `a < b ? a : b`, the prelude's `min a b`;
                // pmax b a is `b < a ? a : b`, the prelude's `max a b`.
                try self.simdLoad(operands[1]);
                try self.simdLoad(operands[0]);
                try self.emit(if (op == .min) .f32x4_pmin else .f32x4_pmax, 0);
            } else {
                try self.simdLoad(operands[0]);
                try self.simdLoad(operands[1]);
                try self.emit(if (op == .min) .i32x4_min_u else .i32x4_max_u, 0);
            },
            // Reinterpretation keeps every bit; only the result type changes.
            .bits, .from_bits => try self.simdLoad(operands[0]),
            .bit_not => {
                try self.simdLoad(operands[0]);
                try self.emit(.v128_not, 0);
            },
            .bit_andnot => {
                try self.simdLoad(operands[0]);
                try self.simdLoad(operands[1]);
                try self.emit(.v128_andnot, 0);
            },
            .equal, .not_equal, .less, .less_equal, .greater, .greater_equal => {
                try self.simdLoad(operands[0]);
                try self.simdLoad(operands[1]);
                try self.emit(switch (op) {
                    .equal => if (floating) .f32x4_eq else .i32x4_eq,
                    .not_equal => if (floating) .f32x4_ne else .i32x4_ne,
                    .less => if (floating) .f32x4_lt else .i32x4_lt_u,
                    .less_equal => if (floating) .f32x4_le else .i32x4_le_u,
                    .greater => if (floating) .f32x4_gt else .i32x4_gt_u,
                    else => if (floating) .f32x4_ge else .i32x4_ge_u,
                }, 0);
            },
            else => {
                const scalar_op = scalar_ops.opcode(op, scalar_type) orelse return g.fail(self.unit_id, 0, .unsupported);
                const vector_op = @import("runtime_ir.zig").lift(scalar_op) orelse return g.fail(self.unit_id, 0, .unsupported);
                for (operands) |operand| try self.simdLoad(operand);
                try self.emit(vector_op, 0);
            },
        }
        try self.emit(.v128_store, 0);
        try self.emit(.local_get, address);
    }
    fn simdLoad(self: *Emitter, operand: u32) Error!void {
        try self.emit(.local_get, operand);
        try self.emit(.v128_load, 0);
    }
    /// A pair operand that is not a literal product is a product of two
    /// vector addresses.
    pub fn simdPairLocals(self: *Emitter, pair: u32, into: *[2]u32) Error!void {
        for (into, 0..) |*local, index| {
            local.* = try self.temporary(.i32);
            try self.emit(.local_get, pair);
            try self.emit(.i32_load, @intCast(index * 4));
            try self.emit(.local_set, local.*);
        }
    }
    /// Literal lane selectors: a U32 constant, or a product of four.
    fn simdLaneLiterals(self: *Emitter, id: core.Id, op: core.Op) ?[4]u8 {
        const source = self.generator.unit(self.unit_id);
        const limit = simd_intrinsics.laneLimit(op);
        if (op == .broadcast) {
            const lane = laneLiteral(source, id, limit) orelse return null;
            return @splat(lane);
        }
        if (source.node(id).tag != .product) return null;
        const children = source.children(id);
        if (children.len != 4) return null;
        var lanes: [4]u8 = undefined;
        for (&lanes, children) |*lane, child| lane.* = laneLiteral(source, child, limit) orelse return null;
        return lanes;
    }
    fn laneLiteral(source: *const core.Module, id: core.Id, limit: u32) ?u8 {
        const node = source.node(id);
        if (node.tag != .constant or source.types.node(source.typeOf(id)).tag != .u32 or node.a >= limit) return null;
        return @intCast(node.a);
    }
    /// Evaluates a SIMD primitive's operands in written order. Literal lane
    /// selectors emit no code; a literal pair contributes its two vectors.
    fn simdExpression(self: *Emitter, id: core.Id, input: layout.Id, result: layout.Id, depth: usize) Error!void {
        const g = self.generator;
        const value = g.unit(self.unit_id).node(id);
        var lanes: ?[4]u8 = null;
        var operands: [3]u32 = undefined;
        var count: usize = 0;
        if (value.op == .shuffle or value.op == .swizzle) {
            lanes = self.simdLaneLiterals(value.a, value.op) orelse return g.fail(self.unit_id, value.a, .simd_lane_literal);
        } else {
            operands[0] = try self.capture(value.a, depth);
            count = 1;
        }
        if (value.op == .broadcast) {
            lanes = self.simdLaneLiterals(value.b, value.op) orelse return g.fail(self.unit_id, value.b, .simd_lane_literal);
        } else if (value.b != 0) {
            count += try self.simdOperand(value.op, value.b, operands[count..][0..2], depth);
        }
        try self.simdLocals(value.op, operands[0..count], lanes, input, result);
    }
    fn simdOperand(self: *Emitter, op: core.Op, id: core.Id, into: *[2]u32, depth: usize) Error!usize {
        const source = self.generator.unit(self.unit_id);
        if (!simd_intrinsics.pairs(op)) {
            into[0] = try self.capture(id, depth);
            return 1;
        }
        if (source.node(id).tag == .product and source.children(id).len == 2) {
            for (into, source.children(id)) |*local, child| local.* = try self.capture(child, depth);
        } else try self.simdPairLocals(try self.capture(id, depth), into);
        return 2;
    }
    fn arrayStructural(self: *Emitter, op: core.ArrayOp, locals: []const u32, scalar_elements: bool, stride: u32, element: layout.Id) Error!void {
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
        try self.allocateArray(scalar_elements, element);
        try self.emit(.local_set, address);
        try self.emit(.local_get, address);
        try self.emit(.local_get, count);
        try self.emit(.i32_store, 0);
        try self.emit(.local_get, address);
        try self.emit(.local_get, address);
        try self.emit(.i32_const, 4);
        try self.emit(.i32_add, 0);
        if (op == .slice) try self.arrayAddress(locals[0], locals[1], stride) else try self.emit(.local_get, locals[0]);
        try self.emit(.i32_const, 4);
        try self.emit(.i32_add, 0);
        try self.emit(.local_get, if (op == .slice) count else left_count);
        try self.emit(.i32_const, stride);
        try self.emit(.i32_mul, 0);
        try self.emit(.call, self.generator.module.arena.?.copy_words);
        if (op == .concat) {
            try self.emit(.local_get, address);
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
            try self.emit(.call, self.generator.module.arena.?.copy_words);
        }
        try self.emit(.local_get, address);
    }
    pub fn descriptor(self: *Emitter, function_id: u32, environment: ?u32) Error!void {
        if (environment == null) {
            const address = try self.generator.static_data.closureData(self.generator, function_id, 0);
            try self.referenceConstant(address, .static_address);
            return;
        }
        const environment_role = self.generator.module.functions.items[function_id].parameterRole(0);
        const address = try self.allocate(@sizeOf(heap.Closure), .{ .words = &.{ .scalar, environment_role } });
        try self.emit(.local_get, address);
        try self.referenceConstant(function_id, .callable_function);
        try self.emit(.i32_store, heap.offset(heap.Closure, "function"));
        try self.emit(.local_get, address);
        if (environment) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
        try self.emit(.i32_store, heap.offset(heap.Closure, "environment"));
        try self.emit(.local_get, address);
    }
    fn demandDescriptor(self: *Emitter, function_id: u32, environment: ?u32) Error!void {
        self.generator.evaluator.counters.demand_allocations += 1;
        const cached_role = self.generator.module.functions.items[function_id].result_role;
        const address = try self.allocate(@sizeOf(heap.Demand), .{ .words = &.{ .scalar, .reference, .scalar, cached_role } });
        try self.emit(.local_get, address);
        try self.referenceConstant(function_id, .demand_function);
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
    fn callableImplementationLayout(self: *Emitter, id: core.Id) Error!layout.Id {
        const source = self.generator.unit(self.unit_id);
        const value = try self.codeLayout(source.typeOf(id), source.span(id));
        const node = self.generator.representations.store.node(value);
        if (node.tag == .universal) return node.a;
        return value;
    }
    fn prepareTemplate(self: *Emitter, id: core.Id) Error!TemplatePreparation {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const n = unit_.node(id);
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
        const capture_roles = try self.layoutRoles(g.allocator, capture_types.items);
        errdefer g.allocator.free(capture_roles);
        // A captured template is stored as its environment pointer, while its
        // layout slot holds the unit placeholder.
        for (captures, capture_roles) |binding, *role| if (self.templates.contains(binding)) {
            role.* = .reference;
            if (self.templates.get(binding).?.scalar_environment) role.* = .scalar;
        };
        var metadata: Template = .{ .unit = self.unit_id, .node = id, .staged = self.staged orelse 0, .environment = if (captures.len == 0) null else 0, .captures = capture_layout, .templates = g.representations.template_keys.intern(templates.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .complexity), .evidence = if (self.factory_template) try g.mappingEvidence(self.mappings) else 0, .rows = if (self.factory_template) try g.rowMappingEvidence(self.row_mappings) else 0 };
        var static_key: ?ClosureKey = null;
        if (n.tag == .closure and self.static_values.count() != 0) {
            var values: std.ArrayList(substitution_keys.Entry) = .empty;
            defer values.deinit(g.allocator);
            var static_types: std.ArrayList(layout.Id) = .empty;
            defer static_types.deinit(g.allocator);
            for (captures) |binding| {
                if (self.static_values.get(binding)) |value| try values.append(g.allocator, .{ .variable = binding, .value = value });
                try static_types.append(g.allocator, try self.codeLayout(unit_.binding(binding).ty, unit_.span(id)));
            }
            if (values.items.len != 0) static_key = .{ .unit = self.unit_id, .catalog = n.a, .ty = try self.callableImplementationLayout(id), .captures = try g.internLayout(.product, 0, 0, static_types.items), .templates = metadata.templates, .staged = metadata.staged, .static_values = g.representations.static_keys.intern(values.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .complexity) };
        }
        if (n.tag == .closure and !self.factory_template and static_key == null and templates.items.len == 0 and g.representations.store.scalarEnvironment(capture_layout)) metadata.scalar_environment = true;
        return .{ .metadata = metadata, .capture_types = try capture_types.toOwnedSlice(g.allocator), .capture_roles = capture_roles, .static_key = static_key };
    }
    fn scopedCallableInstances(self: *Emitter, id: core.Id) Error!u32 {
        return self.scopedCallableTargetInstances(id, null);
    }
    fn scopedCallableTargetInstances(self: *Emitter, id: core.Id, supplied: ?core.BindingRef) Error!u32 {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        if (node.tag != .reference and supplied == null) return 0;
        var ty = node.ty;
        var scoped = false;
        for (0..max_parameters) |_| {
            const arrow = source.types.node(ty);
            if (arrow.tag != .function) break;
            if (source.types.node(arrow.a).tag == .scoped) scoped = true;
            ty = arrow.b;
        }
        if (!scoped) return 0;
        const target = supplied orelse try g.normalize(self.unit_id, source.reference(id));
        const selected = try g.signature(target, node.ty, self.unit_id, self.mappings, self.row_mappings, source.span(id), false);
        return selected.instance_arguments;
    }
    fn templateAt(self: *Emitter, template: Template, id: core.Id) Error!Template {
        const g = self.generator;
        const owner = if (template.unit == 0) self.unit_id else template.unit;
        const source = g.unit(owner);
        if (source.node(template.node).tag != .reference) return template;
        const target = try g.normalize(owner, source.reference(template.node));
        const instances = try self.scopedCallableTargetInstances(id, target);
        if (instances == 0) return template;
        var selected = template;
        selected.callable_instances = instances;
        return selected;
    }
    fn newTemplate(self: *Emitter, id: core.Id) Error!Template {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const n = unit_.node(id);
        if (n.tag == .reference) {
            const reference = unit_.reference(id);
            if (reference.unit == 0 or reference.unit == self.unit_id) {
                if (self.templates.get(reference.binding)) |template| return try self.templateAt(template, id);
            }
            return .{ .unit = self.unit_id, .node = id, .callable_instances = try self.scopedCallableInstances(id) };
        }
        if (n.tag == .constructor_function or n.tag == .primitive_function) return .{ .unit = self.unit_id, .node = id, .callable_instances = try self.scopedCallableInstances(id) };
        const captures = if (n.tag == .suspend_) unit_.suspensionCaptures(id) else unit_.closureCaptures(id);
        const prepared = self.resolvedPlan(id).template;
        const capture_types = prepared.capture_types;
        const capture_roles = prepared.capture_roles;
        if (prepared.metadata.scalar_environment) {
            const environment = try self.temporary(.i32);
            try self.emit(.local_get, self.locals.get(captures[0]) orelse return g.fail(self.unit_id, id, .unsupported));
            try self.emit(.local_set, environment);
            var metadata = prepared.metadata;
            metadata.environment = environment;
            return metadata;
        }
        const environment = if (captures.len == 0) null else try self.allocate(@intCast(captures.len * 4), .{ .words = capture_roles });
        for (captures, capture_types, 0..) |binding, capture_type, index| {
            try self.emit(.local_get, environment.?);
            if (self.locals.get(binding)) |local| try self.emit(.local_get, local) else if (self.templates.get(binding)) |template| {
                if (template.environment) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
            } else return g.fail(self.unit_id, id, .unsupported);
            try self.emit(if (g.representations.store.machine(capture_type) == .f32) .f32_store else .i32_store, @intCast(index * 4));
        }
        var metadata = prepared.metadata;
        metadata.environment = environment;
        return metadata;
    }
    fn computationAction(self: *Emitter, ty: layout.Id) ?layout.Id {
        const layouts = &self.generator.representations.store;
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
        const layouts = &self.generator.representations.store;
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
            .computation, .effect_scope => return self.sourceTemplate(owner, n.a, parameters, arguments, depth + 1),
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
        if (self.dictionary_owner != null and n.tag == .reference) {
            const reference = source.reference(id);
            const owner = if (reference.unit == 0) self.unit_id else reference.unit;
            const kind = self.generator.unit(owner).binding(reference.binding).kind;
            if (kind == .global or kind == .external) {
                const target = self.generator.normalize(self.unit_id, reference) catch return false;
                if (DictionaryOwner.forBinding(self.generator.unit(target.unit), target.binding) != null) return false;
            }
        }
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
        const wanted = g.representations.store.node(selected);
        const given = g.representations.store.node(actual);
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
            const count = g.representations.store.children(selected).len;
            if (count != g.representations.store.children(actual).len) return selected;
            var children: std.ArrayList(layout.Id) = .empty;
            defer children.deinit(g.allocator);
            for (0..count) |index| {
                const left = g.representations.store.children(selected)[index];
                const right = g.representations.store.children(actual)[index];
                try children.append(g.allocator, try self.sourceArgumentLayout(left, right, depth + 1));
            }
            return g.internLayout(wanted.tag, if (wanted.tag == .nominal) wanted.a else 0, if (wanted.tag == .nominal) wanted.b else 0, children.items);
        }
        if (wanted.tag == .record) {
            const count = g.representations.store.children(selected).len;
            if (count != g.representations.store.children(actual).len) return selected;
            var children: std.ArrayList(layout.Id) = .empty;
            defer children.deinit(g.allocator);
            var index: usize = 0;
            while (index < count) : (index += 2) {
                const name = g.representations.store.children(selected)[index];
                const left = g.representations.store.children(selected)[index + 1];
                var right: ?layout.Id = null;
                var position: usize = 0;
                while (position < count) : (position += 2) if (g.representations.store.children(actual)[position] == name) {
                    right = g.representations.store.children(actual)[position + 1];
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
        if (try self.staticCallableTemplate(id)) |template| return template;
        const source = self.generator.unit(self.unit_id);
        const n = source.node(id);
        if (n.tag == .closure or n.tag == .primitive_function or n.tag == .constructor_function) return try self.newTemplate(id);
        if (n.tag != .reference) return null;
        const reference = source.reference(id);
        if (reference.unit == 0 or reference.unit == self.unit_id) {
            if (self.templates.get(reference.binding)) |template| return if (template.computation) null else try self.templateAt(template, id);
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
        const plan = switch (n.tag) {
            .apply => self.resolvedPlan(id).application.factory orelse return null,
            .call => self.resolvedPlan(id).named.factory orelse return null,
            else => return null,
        };
        var arguments: [max_parameters]u32 = undefined;
        var environment: ?u32 = null;
        const operands = if (n.tag == .apply) &.{n.b} else source.call(id).arguments;
        if (n.tag == .apply) {
            const factory = try self.callableTemplate(n.a) orelse return g.fail(self.unit_id, n.a, .unresolved_type);
            environment = factory.environment;
        }
        for (operands, 0..) |argument, index| {
            if (n.tag == .apply) arguments[index] = try self.temporary((try self.scalar(argument)).machine());
            if (plan.admitted[index]) {
                const argument_node = source.node(argument);
                var retained: ?Template = null;
                if (argument_node.tag == .reference) {
                    const reference = source.reference(argument);
                    if (reference.unit == 0 or reference.unit == self.unit_id) retained = self.templates.get(reference.binding);
                }
                const metadata = retained orelse try self.callableTemplate(argument) orelse return g.fail(self.unit_id, argument, .unresolved_type);
                if (n.tag != .apply) arguments[index] = try self.temporary(.i32);
                if (metadata.environment) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
                try self.emit(.local_set, arguments[index]);
            } else if (n.tag == .apply) {
                try self.expression(argument, 0);
                try self.emit(.local_set, arguments[index]);
            } else arguments[index] = try self.capture(argument, 0);
        }
        const function_id = switch (plan.callee) {
            .named => |key| try g.function(key),
            .closure => |key| try g.closureFunction(key),
        };
        if (n.tag == .apply) {
            if (environment) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
        }
        for (arguments[0..operands.len]) |argument| try self.emit(.local_get, argument);
        try self.providerHead();
        try self.emit(.call, function_id);
        const result_environment = try self.temporary(.i32);
        try self.emit(.local_set, result_environment);
        var result = plan.result;
        if (result.environment != null) result.environment = result_environment;
        return result;
    }
    fn boxTemplate(self: *Emitter, template: Template) Error!Template {
        if (!template.scalar_environment) return template;
        const environment = try self.allocate(4, .{ .words = &.{.scalar} });
        try self.emit(.local_get, environment);
        try self.emit(.local_get, template.environment.?);
        try self.emit(.i32_store, 0);
        var boxed = template;
        boxed.environment = environment;
        boxed.scalar_environment = false;
        return boxed;
    }
    fn publishTemplate(self: *Emitter, supplied: Template, source: core.Id) Error!void {
        const template = try self.boxTemplate(supplied);
        const g = self.generator;
        const retained = try g.captureTemplate(template);
        if (self.result_template) |prior| {
            if (prior != retained) return g.fail(self.unit_id, source, .unresolved_type);
        } else self.result_template = retained;
        if (template.environment) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
    }
    fn templateExpression(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const previous_semantic = self.semantic_node;
        self.semantic_node = id;
        defer self.semantic_node = previous_semantic;
        const g = self.generator;
        if (depth >= 1024) return g.fail(self.unit_id, id, .complexity);
        const source = g.unit(self.unit_id);
        const n = source.node(id);
        switch (n.tag) {
            .computation, .reference, .call, .apply => try self.publishTemplate(try self.computationTemplate(id) orelse return g.fail(self.unit_id, id, .unresolved_type), id),
            .block => {
                const join = self.resolvedPlan(id).join;
                try self.emit(.block, @backingInt(join.result.?));
                try self.return_targets.append(g.allocator, .{ .node = id, .label = self.labels, .cleanup = self.cleanups.mark(), .template_result = true });
                self.labels += 1;
                const terminated = try self.suite(id, depth + 1);
                if (terminated) try self.emit(.unreachable_, 0) else return g.fail(self.unit_id, id, .unresolved_type);
                self.labels -= 1;
                _ = self.return_targets.pop();
                try self.emit(.end, 0);
            },
            .if_value => {
                const join = self.resolvedPlan(id).join;
                try self.expression(n.a, depth + 1);
                try self.emit(.if_, @backingInt(join.result.?));
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
        if (template.demand_cell) {
            const demanded = g.representations.store.node(requested);
            if (demanded.tag != .demand or template.environment == null) return g.fail(self.unit_id, template.node, .unresolved_type);
            return self.emit(.local_get, template.environment.?);
        }
        var ty = requested;
        var dictionaries = false;
        if (template.computation) {
            const value = g.representations.store.node(requested);
            if (value.tag != .nominal or value.a != std.math.maxInt(u32) or value.b != 5 or g.representations.store.children(requested).len != 1) return g.fail(self.unit_id, template.node, .unresolved_type);
            ty = g.representations.store.children(requested)[0];
        }
        if (g.representations.store.node(ty).tag == .universal) {
            const producer = g.unit(if (template.unit == 0) self.unit_id else template.unit);
            const principal = producer.typeOf(template.node);
            dictionaries = producer.types.node(principal).tag == .forall and producer.types.quantifierGoals(principal).len != 0;
            ty = g.representations.store.node(ty).a;
        }
        const owner = if (template.unit == 0) self.unit_id else template.unit;
        const unit_ = g.unit(owner);
        const n = unit_.node(template.node);
        if (n.tag == .suspend_) {
            try g.demandSite(owner, template.node, .stored, .unresolved_control);
            const demanded = g.representations.store.node(ty);
            if (demanded.tag != .demand) return g.fail(self.unit_id, template.node, .unresolved_type);
            const fn_type = try g.internLayoutWithEffects(.function, 1, demanded.a, demanded.c, &.{});
            const function_id = try g.closureFunction(.{ .unit = owner, .catalog = n.a, .ty = fn_type, .captures = template.captures, .templates = template.templates, .staged = template.staged, .evidence = template.evidence, .rows = if (template.rows != 0) template.rows else if (owner == self.unit_id) self.body.?.rows_evidence else 0 });
            try self.demandDescriptor(function_id, template.environment);
            return;
        }
        try self.descriptor(try self.templateFunction(template, ty, dictionaries), template.environment);
    }
    fn templateFunction(self: *Emitter, template: Template, ty: layout.Id, dictionaries: bool) Error!u32 {
        const g = self.generator;
        const owner = if (template.unit == 0) self.unit_id else template.unit;
        const unit_ = g.unit(owner);
        const n = unit_.node(template.node);
        return switch (n.tag) {
            .closure => try g.closureFunction(.{ .unit = owner, .catalog = n.a, .ty = ty, .scalar_environment = template.scalar_environment, .captures = template.captures, .templates = template.templates, .staged = template.staged, .evidence = template.evidence, .rows = template.rows, .dictionaries = dictionaries }),
            .constructor_function => try g.constructorFunction(.{ .unit = owner, .catalog = n.a, .ty = ty }),
            .primitive_function => try g.primitiveFunction(.{ .unit = owner, .catalog = n.a, .ty = ty }),
            .reference => try g.callable(.{ .target = try g.normalize(owner, unit_.reference(template.node)), .ty = ty, .dictionaries = dictionaries, .instance_arguments = template.callable_instances }),
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
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const prepared = self.resolvedPlan(id).template;
        const key = prepared.static_key orelse return false;
        const captures = source.closureCaptures(id);
        // Emitting the closure may intern layouts and move the store's lists.
        const capture_types = try g.allocator.dupe(layout.Id, g.representations.store.children(key.captures));
        defer g.allocator.free(capture_types);
        const function_id = try g.closureFunction(key);
        const capture_roles = try self.layoutRoles(g.allocator, capture_types);
        defer g.allocator.free(capture_roles);
        // Compile-time captures carry their evidence in the code key and store
        // zero in the environment, regardless of the selected erased type.
        for (captures, capture_roles) |binding, *role| if (self.static_values.contains(binding)) {
            role.* = .scalar;
        };
        const environment = try self.allocate(@intCast(captures.len * 4), .{ .words = capture_roles });
        for (captures, capture_types, 0..) |binding, concrete, index| {
            try self.emit(.local_get, environment);
            if (self.static_values.contains(binding)) {
                try self.emit(.i32_const, 0);
                try self.emit(.i32_store, @intCast(index * 4));
                continue;
            }
            if (self.locals.get(binding)) |local| try self.emit(.local_get, local) else if (self.templates.get(binding)) |template| {
                if (template.environment) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
            } else return g.fail(self.unit_id, id, .unsupported);
            try self.emit(if (g.representations.store.machine(concrete) == .f32) .f32_store else .i32_store, @intCast(index * 4));
        }
        try self.descriptor(function_id, environment);
        return true;
    }

    pub fn invokeRequest(self: *Emitter, frame: u32, argument: u32, argument_machine: wasm.ValueType, result_machine: wasm.ValueType, argument_role: ir.Role) Error!void {
        const g = self.generator;
        const cell = try self.temporary(.i32);
        const callback = try self.temporary(.i32);
        try self.emit(.local_get, frame);
        try self.emit(.i32_load, heap.offset(heap.RequestFrame, "cell"));
        try self.emit(.local_set, cell);
        try self.emit(.local_get, frame);
        try self.emit(.i32_load, heap.offset(heap.RequestFrame, "target"));
        try self.emit(.local_set, callback);
        const arena = try g.module.ensureArena();
        const pair = try self.temporary(.i32);
        // The state type belongs to the runner. Its immutable checked mask
        // supplies this dispatcher with the exact second-field role. Legacy
        // tracing conservatively scans both words instead of reading RC masks.
        try self.emit(.global_get, arena.rc_enabled);
        try self.emit(.i32_eqz, 0);
        try self.emit(.local_get, cell);
        try self.emit(.i32_const, @sizeOf(heap.ArenaHeader));
        try self.emit(.i32_sub, 0);
        try self.emit(.i32_load, heap.offset(heap.ArenaHeader, "layout"));
        try self.emit(.i32_const, 4);
        try self.emit(.i32_and, 0);
        try self.emit(.i32_or, 0);
        try self.emit(.if_, 0);
        self.labels += 1;
        const references = try self.allocate(@sizeOf(heap.Pair), .{ .words = &.{ argument_role, .reference } });
        try self.emit(.local_get, references);
        try self.emit(.local_set, pair);
        try self.emit(.else_, 0);
        const scalars = try self.allocate(@sizeOf(heap.Pair), .{ .words = &.{ argument_role, .scalar } });
        try self.emit(.local_get, scalars);
        try self.emit(.local_set, pair);
        self.labels -= 1;
        try self.emit(.end, 0);
        try self.storeTypedWord(pair, heap.offset(heap.Pair, "first"), argument, if (argument_machine == .f32) .f32 else .u32, 0);
        const state = try self.temporary(.i32);
        try self.emit(.local_get, cell);
        try self.emit(.i32_load, heap.offset(heap.RequestCell, "state"));
        try self.emit(.local_set, state);
        try self.storeTypedWord(pair, heap.offset(heap.Pair, "second"), state, .u32, 0);
        try self.emit(.local_get, callback);
        try self.emit(.i32_load, heap.offset(heap.Closure, "environment"));
        try self.emit(.local_get, pair);
        try self.emit(.local_get, frame);
        try self.emit(.i32_load, heap.offset(heap.RequestFrame, "runner_outer"));
        try self.emit(.local_get, callback);
        try self.emit(.i32_load, heap.offset(heap.Closure, "function"));
        // The checked request arm returns the compiler's boxed Decision,
        // independently of the operation's payload/state/result machines.
        try g.module.emit(self.function_id, ir.callResult(.reference));
        try self.emit(.call_indirect, try g.module.internType(&.{ .i32, .i32, .i32 }, .i32));
        const decision = try self.temporary(.i32);
        try self.emit(.local_set, decision);
        // State and exit are representation words. Their consumers use the
        // independently proved state/result machines; no reply cast occurs.
        try self.emit(.local_get, decision);
        try self.emit(.i32_load, heap.offset(heap.Decision, "state"));
        try self.emit(.local_set, state);
        try self.storeTypedWord(cell, heap.offset(heap.RequestCell, "state"), state, .u32, 0);
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
        try self.emit(.local_get, decision);
        try self.emit(.i32_load, heap.offset(heap.Decision, "kind"));
        try self.emit(.local_set, state);
        try self.storeTypedWord(cell, heap.offset(heap.RequestCell, "status"), state, .u32, 0);
        try self.emit(.local_get, decision);
        try self.emit(.i32_load, heap.offset(heap.Decision, "payload"));
        try self.emit(.local_set, state);
        try self.storeTypedWord(cell, heap.offset(heap.RequestCell, "exit"), state, .u32, 0);
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
        const payload_role = if (node.b != 0) g.layoutRole(try self.codeLayout(g.unit(self.unit_id).typeOf(node.b), g.unit(self.unit_id).span(id))) else ir.Role.scalar;
        const state_role = if (node.c != 0) g.layoutRole(try self.codeLayout(g.unit(self.unit_id).typeOf(node.c), g.unit(self.unit_id).span(id))) else ir.Role.scalar;
        const decision = try self.allocate(@sizeOf(heap.Decision), .{ .words = &.{ .scalar, payload_role, state_role } });
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
            const bits = try self.generator.static_data.serialize(self.generator, value, ty, 0);
            const scalar_ = self.generator.representations.store.scalar(ty) orelse .pointer;
            try self.generator.emitValue(self.function_id, .{ .scalar = scalar_, .bits = bits });
            return;
        }
        return self.generator.fail(self.unit_id, id, .unsupported);
    }
    fn requestState(self: *Emitter, id: core.Id, carries: []const core.LoopCarry, ty: layout.Id) Error!u32 {
        if (carries.len == 1) {
            const state = try self.temporary(self.generator.representations.store.machine(ty));
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
        const child_types = try self.generator.allocator.dupe(layout.Id, self.generator.representations.store.children(ty));
        defer self.generator.allocator.free(child_types);
        if (child_types.len != carries.len) return self.generator.fail(self.unit_id, id, .unresolved_type);
        const state_roles = try self.layoutRoles(self.generator.allocator, child_types);
        defer self.generator.allocator.free(state_roles);
        const state = try self.allocate(@intCast(carries.len * 4), .{ .words = state_roles });
        for (carries, child_types, 0..) |carry, child_type, index| {
            try self.emit(.local_get, state);
            try self.requestStateValue(id, carry.incoming, child_type);
            try self.emit(if (self.generator.representations.store.machine(child_type) == .f32) .f32_store else .i32_store, @intCast(index * 4));
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
        const plan = self.resolvedPlan(id).request;
        const exited = try self.bindExit(plan.exited);
        const exit_label = self.labels;
        const metadata = source.requestLoopInfo(id);
        const carries = plan.broken.carries;
        const computation = try self.capture(metadata.computation, depth);
        const state_layout = try self.codeLayout(metadata.state_type, source.span(id));
        const initial = try self.requestState(id, carries, state_layout);
        const state_machine = g.representations.store.machine(state_layout);
        const value_machine = (try g.scalarWithRows(self.unit_id, metadata.value_type, self.mappings, self.row_mappings, source.span(id))).machine();
        const result_machine = (try g.scalarWithRows(self.unit_id, metadata.result_type, self.mappings, self.row_mappings, source.span(id))).machine();
        const exit_role = g.layoutRole(try self.codeLayout(metadata.result_type, source.span(id)));
        const cell = try self.allocatePrivate(@sizeOf(request_runtime.Cell), .{ .words = &.{ .scalar, exit_role, g.layoutRole(state_layout) } });
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
        for (plan.arms, plan.operations) |arm, operation| {
            const callback = try self.capture(arm.callback, depth);
            const scoped = arm.selector != 0;
            var owner: ?u32 = null;
            if (scoped) owner = try self.operationOwner(arm.selector, depth);
            const frame = if (scoped) try self.allocatePrivate(@sizeOf(heap.ScopedRequestFrame), .heap(heap.ScopedRequestFrame)) else try self.allocatePrivate(@sizeOf(request_runtime.Frame), .heap(request_runtime.Frame));
            if (owner) |authority| {
                try self.emit(.local_get, frame);
                try self.emit(.local_get, authority);
                try self.emit(.i32_store, heap.offset(heap.ScopedRequestFrame, "owner"));
            }
            try self.emit(.local_get, frame);
            try self.operationConstant(try g.runtimeOperation(operation, self.unit_id, source.span(id)));
            try self.emit(.i32_store, heap.offset(heap.RequestFrame, "operation"));
            try self.emit(.local_get, frame);
            try self.emit(.local_get, callback);
            try self.emit(.i32_store, heap.offset(heap.RequestFrame, "target"));
            try self.emit(.local_get, frame);
            try self.emit(.local_get, provider);
            try self.emit(.i32_store, heap.offset(heap.RequestFrame, "outer"));
            try self.emit(.local_get, frame);
            try self.emit(.i32_const, if (scoped) heap.ScopedRequestFrame.tag else request_runtime.request_kind);
            try self.emit(.i32_store, heap.offset(heap.RequestFrame, "kind"));
            try self.emit(.local_get, frame);
            try self.emit(.local_get, cell);
            try self.emit(.i32_store, heap.offset(heap.RequestFrame, "cell"));
            try self.emit(.local_get, frame);
            try self.emit(.local_get, outer);
            try self.emit(.i32_store, heap.offset(heap.RequestFrame, "runner_outer"));
            try self.providerOrigin(frame, if (scoped) heap.ScopedRequestFrame.tag else request_runtime.request_kind, .reference, try g.runtimeOperation(operation, self.unit_id, source.span(id)), null);
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
        try g.module.emit(self.function_id, ir.callResult(g.layoutRole(try self.codeLayout(metadata.value_type, source.span(id)))));
        try self.emitUnguarded(.call_indirect, try g.module.internType(&.{ .i32, .i32, .i32 }, value_machine));
        try self.emit(.local_set, value);
        try request_runtime.runner(&g.module, self.function_id, g.request_owner.?, cell, &self.cleanups);
        const state = try self.temporary(state_machine);
        try self.emit(.local_get, cell);
        try self.emit(if (state_machine == .f32) .f32_load else .i32_load, heap.offset(heap.RequestCell, "state"));
        try self.emit(.local_set, state);
        // The runner opens no structured labels. The exit scope's cleanup mark
        // follows the cell and frames, which the loop's own close releases.
        std.debug.assert(self.labels == exit_label);
        const broken = plan.broken.bind(exit_label, self.cleanups.mark());
        try self.emit(.block, 0);
        self.labels += 1;
        try self.loop_targets.append(g.allocator, .{ .node = id, .label = broken.label, .cleanup = broken.cleanup });
        try self.emit(.local_get, cell);
        try self.emit(.i32_load, heap.offset(heap.RequestCell, "status"));
        try self.emit(.i32_const, @backingInt(request_runtime.Status.exited));
        try self.emit(.i32_eq, 0);
        try self.emit(.if_, 0);
        self.labels += 1;
        try self.emit(.local_get, cell);
        try self.emit(if (result_machine == .f32) .f32_load else .i32_load, heap.offset(heap.RequestCell, "exit"));
        try self.takeExit(exited);
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
        std.debug.assert(self.cleanups.since(broken.cleanup).len == 0);
        try self.takeExit(broken);
        self.labels -= 1;
        try self.emit(.end, 0);
        try self.requestBindState(id, state, source.requestCompletionBindings(id));
        try self.emit(.block, 0);
        const pattern_failure = self.labels;
        self.labels += 1;
        try self.matchPattern(id, plan.completion_pattern, value, pattern_failure, depth + 1);
        _ = try self.suite(plan.completion_body, depth + 1);
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
        const arena = try g.module.ensureArena();
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
        // Reserve the force owner before publishing evaluating state.
        try self.rootDirective(6, demand);
        try self.storeTypedWord(demand, heap.offset(heap.Demand, "status"), null, .u32, 1);
        try self.emit(.local_get, demand);
        try self.emit(.i32_load, heap.offset(heap.Demand, "environment"));
        try self.emit(.i32_const, 0);
        try self.providerHead();
        var known: ?u32 = null;
        const operand = g.unit(self.unit_id).node(n.a);
        if (operand.tag == .reference) {
            const reference = g.unit(self.unit_id).reference(n.a);
            if (reference.unit == 0 or reference.unit == self.unit_id) if (self.templates.get(reference.binding)) |template| if (template.demand_cell) {
                const owner = if (template.unit == 0) self.unit_id else template.unit;
                const suspended = g.unit(owner).node(template.node);
                if (suspended.tag != .suspend_) return g.fail(self.unit_id, id, .unresolved_type);
                const demanded = g.representations.store.node(try self.codeLayout(g.unit(self.unit_id).typeOf(n.a), g.unit(self.unit_id).span(id)));
                const ty = try g.internLayoutWithEffects(.function, 1, demanded.a, demanded.c, &.{});
                const target = try g.closureFunction(.{ .unit = owner, .catalog = suspended.a, .ty = ty, .captures = template.captures, .templates = template.templates, .staged = template.staged, .evidence = template.evidence, .rows = template.rows });
                const body = g.module.functions.items[target];
                if (body.entry or body.signature != try g.module.internType(&.{ .i32, .i32, .i32 }, result.machine()) or body.parameter_roles != g.closureRoles(1) or body.result_role != result.role()) return g.fail(self.unit_id, id, .unresolved_type);
                known = target;
            };
        }
        if (known) |target| {
            try self.emitUnguarded(.call, target);
        } else {
            g.evaluator.counters.demand_indirect_calls += 1;
            try self.emit(.local_get, demand);
            try self.emit(.i32_load, heap.offset(heap.Demand, "function"));
            try self.emitUnguarded(.call_indirect, try g.module.internType(&.{ .i32, .i32, .i32 }, result.machine()));
        }
        try self.emit(.local_set, cached);
        if (g.request_owner) |owner| {
            const checkpoint = self.cleanups.mark();
            defer self.cleanups.restore(checkpoint);
            try self.cleanups.append(g.allocator, .{ .reset_demand = @fromBackingInt(@intCast(demand)) });
            try request_runtime.guard(&g.module, self.function_id, owner, &self.cleanups);
        }
        try self.storeTypedWord(demand, heap.offset(heap.Demand, "cached"), cached, result, 0);
        try self.storeTypedWord(demand, heap.offset(heap.Demand, "status"), null, .u32, 2);
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
    pub fn storeTypedWord(self: *Emitter, demand: u32, offset: u32, local: ?u32, scalar_: Scalar, literal: u32) Error!void {
        const arena = try self.generator.module.ensureArena();
        try self.emit(.local_get, demand);
        try self.emit(.local_get, demand);
        try self.emit(.i32_const, offset);
        try self.emit(.i32_add, 0);
        if (local) |value| {
            try self.emit(.local_get, value);
            if (scalar_ == .f32) try self.emit(.i32_reinterpret_f32, 0);
        } else try self.emit(.i32_const, literal);
        try self.emit(.call, arena.store_word);
    }
    // A selected getter may accept data containing an unobserved callback row.
    // Its ABI is concrete even though that nested row has no closed semantic
    // header. Keep the actual closure/captures in this Session and prove its
    // body against the selected code shape instead of materializing that row.
    // Inlining limits select emission strategy, never source admission.
    /// A statically known anonymous closure applied to one argument: its
    /// captured values, interface and specialization, selected before any of
    /// the application's instructions.
    const StaticClosurePlan = struct {
        header: core_eval.ClosureValue,
        ty: layout.Id,
        captured: []core_eval.ValueId,
        mappings: std.ArrayList(Mapping) = .empty,
        rows: std.ArrayList(RowMapping) = .empty,
        fn deinit(self: *StaticClosurePlan, a: Allocator) void {
            a.free(self.captured);
            self.mappings.deinit(a);
            self.rows.deinit(a);
            self.* = undefined;
        }
    };
    fn prepareStaticClosure(self: *Emitter, id: core.Id) Error!?StaticClosurePlan {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        if (self.static_values.count() == 0) return null;
        const value = try self.staticReference(node.a) orelse return null;
        if (g.evaluator.valueInfo(value).kind != .closure) return null;
        const header = g.evaluator.closureInfo(value);
        if (header.origin != .anonymous) return null;
        const ty = try self.codeLayout(source.typeOf(node.a), source.span(id));
        const arrow = g.representations.store.node(ty);
        if (arrow.tag != .function or arrow.c == layout.unknown_row) return null;
        if (g.representations.toEvidence(g.evaluator.evidenceStore(), ty)) |_| return null else |err| switch (err) {
            error.UnresolvedType => {},
            error.OutOfMemory => return error.OutOfMemory,
            else => return null,
        }
        if (self.hasErasedType(ty, 0)) return null;
        const producer = g.unit(header.unit);
        const metadata = producer.closures[header.identity];
        const bindings = producer.extra[metadata.captures.start..][0..metadata.captures.len];
        var plan: StaticClosurePlan = .{ .header = header, .ty = ty, .captured = try g.allocator.dupe(core_eval.ValueId, g.evaluator.valueChildren(value)) };
        errdefer plan.deinit(g.allocator);
        if (bindings.len != plan.captured.len) return g.fail(header.unit, metadata.body, .unsupported);
        if (g.artifacts) |artifacts| artifacts.requireFreshCode();
        for (g.evaluator.storage.type_mappings.items[header.mappings.start..][0..header.mappings.len]) |mapping| {
            const concrete = g.representations.fromEvidence(g.evaluator.evidenceStore(), mapping.evidence) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(header.unit, metadata.body, .unresolved_type);
            try g.mapType(header.unit, &plan.mappings, mapping.variable, concrete, producer.span(metadata.body));
        }
        try g.loadSemanticRows(g.evaluator.storage.row_mappings.items[header.row_mappings.start..][0..header.row_mappings.len], &plan.rows);
        if (metadata.function_type != 0) {
            try g.mapCapturedFunction(header.unit, metadata.function_type, ty, &plan.mappings, &plan.rows, producer.span(metadata.body));
        } else {
            try g.mapType(header.unit, &plan.mappings, metadata.parameter.ty, arrow.a, metadata.parameter.span);
            try g.mapType(header.unit, &plan.mappings, producer.typeOf(metadata.body), arrow.b, producer.span(metadata.body));
        }
        const hints_len = std.math.add(usize, plan.captured.len, @intFromBool(metadata.parameter.binding != 0)) catch return g.fail(header.unit, metadata.body, .complexity);
        const hints = try g.allocator.alloc(core_eval.RetainedCapture, hints_len);
        defer g.allocator.free(hints);
        for (bindings, plan.captured, hints[0..plan.captured.len]) |binding, actual, *hint| {
            hint.* = .{ .binding = binding, .unit = header.unit, .node = 0, .value = actual };
        }
        var argument_rows: std.ArrayList(type_evidence.RowMapping) = .empty;
        defer argument_rows.deinit(g.allocator);
        for (self.row_mappings) |mapping| {
            if (mapping.row == layout.unknown_row) continue;
            const evidence = g.representations.rowToEvidence(g.evaluator.evidenceStore(), mapping.row) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .unresolved_type);
            try argument_rows.append(g.allocator, .{ .variable = mapping.variable, .evidence = evidence });
        }
        if (metadata.parameter.binding != 0) hints[plan.captured.len] = .{
            .binding = metadata.parameter.binding,
            .unit = self.unit_id,
            .node = node.b,
            .mappings = try g.mappingEvidence(self.mappings),
            .rows = argument_rows.items,
            .signature_only = true,
        };
        // The caller's frozen argument signature retains known effect labels
        // beside its open tails. These live hints disable semantic receipts.
        try g.refineAccessorMappings(header.unit, header.identity, ty, &plan.mappings, &plan.rows, producer.span(metadata.body), hints);
        return plan;
    }
    fn staticApply(self: *Emitter, id: core.Id, depth: usize) Error!bool {
        const g = self.generator;
        const node = g.unit(self.unit_id).node(id);
        const plan = self.resolvedPlan(id).application.static_closure orelse return false;
        g.evaluator.counters.prepared_static_closures += 1;
        const header = plan.header;
        const producer = g.unit(header.unit);
        const metadata = producer.closures[header.identity];
        const bindings = producer.extra[metadata.captures.start..][0..metadata.captures.len];
        const argument = try self.capture(node.b, depth);
        // Inlining depends on the code emitted so far, so emission decides it.
        const inline_body = self.inline_depth < 6 and g.module.functions.items[self.function_id].codeLength() <= 4096 and @import("inline_body.zig").cost(producer, metadata.body) != null;
        if (!inline_body) {
            const function_id = try g.capturedClosureFunction(header, plan.ty, plan.captured, plan.mappings.items, plan.rows.items);
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
            .mappings = plan.mappings.items,
            .row_mappings = plan.rows.items,
            .cleanups = .{ .parent = &self.cleanups },
            .diagnostic_context = try self.inlineContext(),
            .labels = self.labels,
            .inline_depth = self.inline_depth + 1,
        };
        defer emitter.deinit();
        if (metadata.parameter.binding != 0) try emitter.locals.put(g.allocator, metadata.parameter.binding, argument);
        for (bindings, plan.captured) |binding, actual| try emitter.static_values.put(g.allocator, binding, actual);
        try emitter.bodyExpression(metadata.body, depth + 1, false);
        return true;
    }
    fn universalCallee(self: *Emitter, callee: core.Id, use: core.Id) Error!?struct { layout: layout.Id, quantifier: types.Id } {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(callee);
        var ty: types.Id = 0;
        switch (node.tag) {
            .reference => {
                const reference = source.reference(callee);
                if (reference.unit != 0 and reference.unit != self.unit_id) return null;
                const declaration = source.binding(reference.binding);
                if (declaration.kind != .parameter and declaration.kind != .local) return null;
                ty = declaration.ty;
            },
            .project => ty = source.projection(node.b).result_type,
            .call => {
                const call = source.call(callee);
                ty = source.types.withoutForall(call.callee_type) catch return g.fail(self.unit_id, use, .complexity);
                for (call.arguments) |_| {
                    const arrow = source.types.node(ty);
                    if (arrow.tag != .function) return null;
                    ty = arrow.b;
                }
            },
            else => return null,
        }
        if (source.types.node(ty).tag != .forall) return null;
        const representation = try self.codeLayout(ty, source.span(use));
        if (g.representations.store.node(representation).tag != .universal) return null;
        return .{ .layout = representation, .quantifier = ty };
    }
    fn prepareApplication(self: *Emitter, id: core.Id) Error!ApplyPlan {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        if (try self.prepareSpawnApplication(id)) |spawn| return .{ .spawn = spawn };
        if (source.types.node(source.typeOf(node.a)).tag == .never) return .{ .never = true };
        if (self.inline_demands.len != 0) if (@import("demand_inline.zig").localClosure(source, node.a)) |closure_id| {
            return .{ .local_callback = closure_id, .arrow = try self.prepareIndirect(node.a, id) };
        };
        var result: ApplyPlan = .{};
        errdefer result.deinit(g.allocator);
        if (try self.universalCallee(node.a, id)) |stored| {
            result.arrow = try self.prepareIndirect(node.a, id);
            result.universal = g.representations.store.node(stored.layout).a;
            result.quantifier = stored.quantifier;
            return result;
        }
        result.evaluated = try self.prepareEvaluatedNamed(id);
        if (result.evaluated != null) {
            result.arrow = try self.prepareIndirect(node.a, id);
            return result;
        }
        result.static_closure = try self.prepareStaticClosure(id);
        if (result.static_closure != null) return result;
        result.partial = try self.preparePartialStaticCall(id);
        if (@import("known_call.zig").resolve(g.units, self.unit_id, id)) |known| if (known.signature != 0) {
            const key = try g.signature(known.target, known.signature, self.unit_id, self.mappings, self.row_mappings, source.span(id), false);
            if (key.count == known.count) result.known = .{ .key = key, .arguments = known.arguments, .count = known.count };
        };
        result.arrow = try self.prepareIndirect(node.a, id);
        return result;
    }
    fn apply(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const n = unit_.node(id);
        const prepared = self.resolvedPlan(id).application;
        if (prepared.spawn) |spawn| return self.emitSpawnApplication(spawn, depth);
        if (prepared.universal) |boxed| {
            const concrete = prepared.arrow.?;
            const abstract = g.representations.store.node(boxed);
            if (abstract.tag != .function) return g.fail(self.unit_id, id, .unresolved_type);
            try self.carrierRows(abstract.c, concrete.row, id);
            const callee = try self.capture(n.a, depth);
            const input = try self.capture(n.b, depth);
            const argument = try self.carrierValue(input, concrete.parameter, abstract.a, 0);
            const qualified = unit_.types.quantifierGoals(prepared.quantifier).len != 0;
            var dictionary: u32 = 0;
            if (qualified) dictionary = try self.universalDictionary(id, prepared.quantifier, n.a);
            try self.emit(.local_get, callee);
            try self.emit(.i32_load, heap.offset(heap.Closure, "environment"));
            try self.emit(.local_get, argument);
            try self.providerHead();
            if (qualified) try self.emit(.local_get, dictionary);
            try self.emit(.local_get, callee);
            try self.emit(.i32_load, heap.offset(heap.Closure, "function"));
            try g.module.emit(self.function_id, ir.callResult(g.layoutRole(abstract.b)));
            var signature = try g.closureSignature(abstract.a, abstract.b);
            if (qualified) signature = try g.dictionaryClosureSignature(abstract.a, abstract.b);
            try self.emit(.call_indirect, signature);
            const output = try self.temporary(g.representations.store.machine(abstract.b));
            try self.emit(.local_set, output);
            const result = try self.carrierValue(output, abstract.b, concrete.result, 0);
            return self.emit(.local_get, result);
        }
        if (prepared.local_callback != 0) {
            const metadata = unit_.closure(prepared.local_callback);
            const arrow = prepared.arrow.?;
            var mappings: std.ArrayList(Mapping) = .empty;
            var rows: std.ArrayList(RowMapping) = .empty;
            defer mappings.deinit(g.allocator);
            defer rows.deinit(g.allocator);
            try mappings.appendSlice(g.allocator, self.mappings);
            try rows.appendSlice(g.allocator, self.row_mappings);
            if (metadata.function_type != 0) {
                const ty = try g.internLayoutWithEffects(.function, arrow.parameter, arrow.result, arrow.row, &.{});
                try g.mapCapturedFunction(self.unit_id, metadata.function_type, ty, &mappings, &rows, unit_.span(metadata.body));
            } else {
                try g.mapTypeDepth(self.unit_id, &mappings, &rows, metadata.parameter.ty, arrow.parameter, metadata.parameter.span, 0);
                try g.mapTypeDepth(self.unit_id, &mappings, &rows, unit_.typeOf(metadata.body), arrow.result, unit_.span(metadata.body), 0);
            }
            const argument = try self.capture(n.b, depth);
            var callback: Emitter = .{
                .generator = g,
                .unit_id = self.unit_id,
                .function_id = self.function_id,
                .provider_local = self.provider_local,
                .mappings = mappings.items,
                .row_mappings = rows.items,
                .cleanups = .{ .parent = &self.cleanups },
                .diagnostic_context = try self.inlineContext(),
                .labels = self.labels,
                .inline_demands = self.inline_demands,
            };
            defer callback.deinit();
            callback.locals = try self.locals.clone(g.allocator);
            callback.static_values = try self.static_values.clone(g.allocator);
            if (metadata.parameter.binding != 0) try callback.locals.put(g.allocator, metadata.parameter.binding, argument);
            try callback.bodyExpression(metadata.body, depth + 1, false);
            return;
        }
        if (prepared.never) {
            try self.expression(n.a, depth + 1);
            try self.emit(.unreachable_, 0);
            return;
        }
        if (prepared.arrow) |arrow| if (g.representations.store.node(arrow.parameter).tag == .demand and unit_.node(n.b).tag == .suspend_ and unit_.node(n.a).tag == .reference) {
            const ref = unit_.reference(n.a);
            const owner = if (ref.unit == 0) self.unit_id else ref.unit;
            const kind = g.unit(owner).binding(ref.binding).kind;
            if (kind == .global or kind == .external) {
                const target = try g.normalize(self.unit_id, ref);
                const producer = g.unit(target.unit);
                if (producer.body(target.binding)) |body| if (body.is_function and body.parameters.len != 0) {
                    var metadata = self.resolvedPlan(n.b).template.metadata;
                    metadata.environment = 0;
                    metadata.demand_cell = true;
                    const retained = try g.captureTemplate(metadata);
                    const templates = g.representations.template_keys.intern(&.{.{ .variable = producer.bodyParameters(body)[0].binding, .value = retained }}) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .complexity);
                    const function = try g.callable(.{ .target = target, .ty = try self.codeLayout(unit_.typeOf(n.a), unit_.span(id)), .templates = templates });
                    const argument = try self.capture(n.b, depth);
                    try self.emit(.i32_const, 0);
                    try self.emit(.local_get, argument);
                    try self.providerHead();
                    try self.emit(.call, function);
                    return;
                };
            }
        };
        if (prepared.evaluated) |plan| if (try self.emitEvaluatedNamed(plan, depth)) return;
        if (try self.staticApply(id, depth)) return;
        if (prepared.partial) |partial| if (try self.inlineStaticCall(partial.key, partial.arguments[0..partial.count], depth)) return;
        if (prepared.known) |known| {
            if (try self.inlineCollectionEdit(id, known.key, depth)) return;
            if (try self.inlineSimdCall(id, known.key, depth)) return;
            if (try self.inlineNamedCall(known.key, known.arguments[0..known.count], depth)) return;
        }
        if (self.static_values.count() == 0 and self.isCallableTemplate(n.a)) {
            const template = (try self.callableTemplate(n.a)).?;
            const ty = try self.codeLayout(unit_.typeOf(n.a), unit_.span(id));
            const function = try self.templateFunction(template, ty, false);
            const argument = try self.capture(n.b, depth);
            if (template.environment) |env| try self.emit(.local_get, env) else try self.emit(.i32_const, 0);
            try self.emit(.local_get, argument);
            try self.providerHead();
            try self.emit(.call, function);
            return;
        }
        if (unit_.node(n.a).tag == .operation_value) {
            const selected = self.resolvedPlan(n.a).operation;
            const operation = unit_.operationValue(n.a);
            const token = try g.runtimeOperation(selected.label, self.unit_id, unit_.span(n.a));
            // The checked operation value selects this exact dispatcher. Keep
            // capability-before-argument evaluation and its authority checks;
            // values transported through an unknown callable remain indirect.
            const function = try g.operationFunction(.{ .operation = token, .ty = selected.ty, .scoped = operation.capability != 0 });
            const arrow = prepared.arrow.?;
            const expected = try g.closureSignature(arrow.parameter, arrow.result);
            const callee = g.module.functions.items[function];
            if (callee.signature == expected and callee.result_role == g.layoutRole(arrow.result) and callee.parameter_roles == g.closureRoles(arrow.parameter)) {
                const environment = if (operation.capability != 0) try self.capture(operation.capability, depth) else null;
                const argument = try self.capture(n.b, depth);
                if (environment) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
                if (g.representations.store.node(arrow.parameter).tag != .erased_proof) try self.emit(.local_get, argument);
                try self.providerHead();
                try self.emit(.call, function);
                return;
            }
        }
        const arrow = prepared.arrow.?;
        if (try self.selectedNumericCall(id, arrow, depth)) return;
        g.evaluator.counters.prepared_indirect_calls += 1;
        const callee = try self.capture(n.a, depth);
        const argument = try self.capture(n.b, depth);
        const signature = try g.closureSignature(arrow.parameter, arrow.result);
        try self.emit(.local_get, callee);
        try self.emit(.i32_load, heap.offset(heap.Closure, "environment"));
        if (g.representations.store.node(arrow.parameter).tag != .erased_proof) try self.emit(.local_get, argument);
        try self.providerHead();
        try self.emit(.local_get, callee);
        const logical = try g.internLayoutWithEffects(.function, arrow.parameter, arrow.result, arrow.row, &.{});
        if (logical < 1 << 26) try g.module.emitReference(self.function_id, .{ .op = .ownership, .operand = logical }, .callable_layout);
        try self.emit(.i32_load, heap.offset(heap.Closure, "function"));
        try g.module.emit(self.function_id, ir.callResult(g.layoutRole(arrow.result)));
        try self.emit(.call_indirect, signature);
    }
    // These are guarded optimization candidates, not dispatch authority. A
    // changed capture, unresolved alias or unlisted target keeps the original
    // indirect call. No closure descriptor or public calling convention changes.
    fn numericCallTargets(self: *Emitter, id: core.Id, targets: *[4]u32, count: *usize, budget: *usize) Error!void {
        if (id == 0 or budget.* == 0 or count.* == targets.len or self.body == null) return;
        budget.* -= 1;
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        if (node.tag == .if_value) {
            try self.numericCallTargets(node.b, targets, count, budget);
            return self.numericCallTargets(node.c, targets, count, budget);
        }
        var template: Template = undefined;
        if (node.tag == .closure) {
            if (!self.body.?.entries.contains(id) or self.body.?.get(id) != .template) return;
            const prepared = self.body.?.get(id).template;
            if (prepared.static_key != null) return;
            template = prepared.metadata;
        } else if (node.tag == .reference) {
            const reference = source.reference(id);
            if (reference.unit == 0 or reference.unit == self.unit_id) {
                const binding = source.binding(reference.binding);
                if (binding.kind != .global and binding.kind != .external) return self.numericCallTargets(binding.initializer, targets, count, budget);
            }
            if (!self.isCallableTemplate(id)) return;
            const owner = if (reference.unit == 0) self.unit_id else reference.unit;
            const body = g.unit(owner).body(reference.binding) orelse return;
            if (!body.is_function) return;
            template = try self.newTemplate(id);
        } else return;
        const ty = try self.codeLayout(source.typeOf(id), source.span(id));
        if (g.representations.store.node(ty).tag != .function) return;
        const target = try self.templateFunction(template, ty, false);
        for (targets[0..count.*]) |existing| if (existing == target) return;
        targets[count.*] = target;
        count.* += 1;
    }
    fn selectedNumericCall(self: *Emitter, id: core.Id, arrow: resolved_call.Arrow, depth: usize) Error!bool {
        const g = self.generator;
        if (!g.inline_named or self.static_values.count() != 0 or g.layoutRole(arrow.result) != .scalar) return false;
        const node = g.unit(self.unit_id).node(id);
        const view = self.borrowedRowArgument(node.b) orelse return false;
        if (view.row != arrow.parameter) return false;
        var targets: [4]u32 = undefined;
        var count: usize = 0;
        var budget: usize = 32;
        try self.numericCallTargets(node.a, &targets, &count, &budget);
        if (count == 0) return false;
        const signature = try g.closureSignature(arrow.parameter, arrow.result);
        for (targets[0..count]) |target| if (g.module.functions.items[target].signature != signature) return false;
        const callee = try self.capture(node.a, depth);
        const selector = try self.temporary(.i32);
        try self.emit(.local_get, callee);
        try self.emit(.i32_load, heap.offset(heap.Closure, "function"));
        try self.emit(.local_set, selector);
        for (targets[0..count]) |target| {
            try self.emit(.local_get, selector);
            try self.referenceConstant(target, .callable_function);
            try self.emit(.i32_eq, 0);
            try self.emit(.if_, @backingInt(g.representations.store.machine(arrow.result)));
            self.labels += 1;
            // Only a borrowed row read is delayed into this arm. Its scalar
            // fields are immutable and the enclosing collection stays live.
            // Each arm owns its materialization; SROA can erase an admitted
            // reader's boxes without changing the unknown target fallback.
            const argument = try self.capture(node.b, depth);
            try self.emit(.local_get, callee);
            try self.emit(.i32_load, heap.offset(heap.Closure, "environment"));
            try self.emit(.local_get, argument);
            try self.providerHead();
            try self.emit(.call, target);
            try self.emit(.else_, 0);
        }
        const argument = try self.capture(node.b, depth);
        try self.emit(.local_get, callee);
        try self.emit(.i32_load, heap.offset(heap.Closure, "environment"));
        try self.emit(.local_get, argument);
        try self.providerHead();
        try self.emit(.local_get, selector);
        try g.module.emit(self.function_id, ir.callResult(g.layoutRole(arrow.result)));
        try self.emit(.call_indirect, signature);
        for (0..count) |_| {
            self.labels -= 1;
            try self.emit(.end, 0);
        }
        return true;
    }
    fn prepareResourceScope(self: *Emitter, id: core.Id) Error!@FieldType(Plan, "resource_scope") {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        const transferred = node.tag == .resource_acquire;
        var count: usize = 3;
        if (transferred) count = 2;
        const callables = [_]u32{ node.a, node.b, node.c };
        const kinds = [_]types.UsageKind{ .once, .cleanup, .once };
        if (!source.has_usage_contracts or (transferred and node.c != 0)) return g.fail(self.unit_id, id, .unsupported);
        for (callables[0..count], kinds[0..count]) |callable, kind| {
            if (source.node(callable).tag != .closure and !(kind == .cleanup and @import("../check/cleanup_contracts.zig").immutableHost(source, callable))) return g.fail(self.unit_id, id, .unsupported);
            const wrapper = source.types.node(source.typeOf(callable));
            if (wrapper.tag != .usage or wrapper.b != @backingInt(kind) or wrapper.c != 0) return g.fail(self.unit_id, id, .unsupported);
        }
        if (transferred) @import("../check/cleanup_contracts.zig").immutableTransferred(source, node.b) catch return g.fail(self.unit_id, id, .unsupported) else @import("../check/cleanup_contracts.zig").immutable(source, node.b) catch return g.fail(self.unit_id, id, .unsupported);
        const acquire = try self.codeLayout(source.typeOf(node.a), source.span(id));
        const release = try self.codeLayout(source.typeOf(node.b), source.span(id));
        const acquired = g.representations.store.node(acquire);
        const released = g.representations.store.node(release);
        if (acquired.tag != .function or released.tag != .function) return g.fail(self.unit_id, id, .unresolved_type);
        const acquire_wrapper = source.types.node(source.typeOf(node.a));
        const owner = source.types.node(source.types.node(acquire_wrapper.a).b);
        if (owner.tag != .usage or owner.b != @backingInt(types.UsageKind.unique) or owner.c != 0 or !@import("../check/cleanup_contracts.zig").payloadNominal(&source.types, source.nominals, owner.a)) return g.fail(self.unit_id, id, .unsupported);
        if (g.representations.store.node(acquired.a).tag != .unit or g.representations.store.node(released.b).tag != .unit or acquired.b != released.a or g.representations.store.node(acquired.b).tag != .owning) return g.fail(self.unit_id, id, .unresolved_type);
        var callback: layout.Id = 0;
        if (transferred) {
            _ = try g.module.resourceTransferImports();
            if (acquired.b != try self.codeLayout(node.ty, source.span(id))) return g.fail(self.unit_id, id, .unresolved_type);
        } else {
            callback = try self.codeLayout(source.typeOf(node.c), source.span(id));
            const called = g.representations.store.node(callback);
            if (called.tag != .function or g.representations.store.node(acquired.b).a != called.a or called.b != try self.codeLayout(node.ty, source.span(id))) return g.fail(self.unit_id, id, .unresolved_type);
        }
        return .{ .acquire = acquire, .release = release, .callback = callback };
    }
    fn invokeUsageClosure(self: *Emitter, callable: u32, argument: ?u32, arrow: layout.Node) Error!void {
        const g = self.generator;
        try self.emit(.local_get, callable);
        try self.emit(.i32_load, heap.offset(heap.Closure, "environment"));
        if (argument) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
        try self.providerHead();
        try self.emit(.local_get, callable);
        try self.emit(.i32_load, heap.offset(heap.Closure, "function"));
        try g.module.emit(self.function_id, ir.callResult(g.layoutRole(arrow.b)));
        try self.emit(.call_indirect, try g.closureSignature(arrow.a, arrow.b));
    }
    fn resourceAcquire(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const node = g.unit(self.unit_id).node(id);
        const plan = self.resolvedPlan(id).resource_scope;
        const acquire_arrow = g.representations.store.node(plan.acquire);
        const payload = g.representations.store.node(acquire_arrow.b).a;
        const imports = try g.module.resourceTransferImports();
        const adapter = try g.resourceAdapter(payload);
        const acquire = try self.capture(node.a, depth);
        const cleanup = try self.capture(node.b, depth);
        const token = try self.temporary(.i32);
        try self.emit(.call_import, imports.reserve);
        try self.emit(.local_set, token);
        // Allocate the result carrier before acquisition. Publication after
        // acquisition only writes this prepared storage and retained roots.
        try self.emit(if (g.representations.store.machine(payload) == .f32) .f32_const else .i32_const, 0);
        try self.boxOwner(payload);
        const owner = try self.temporary(.i32);
        try self.emit(.local_set, owner);
        const acquired = try self.temporary(.i32);
        try self.invokeUsageClosure(acquire, null, acquire_arrow);
        try self.emit(.local_set, acquired);
        // Reacquiring an owner with an attached obligation would erase its
        // existing adapter. Reject before acquiring another journal root.
        try self.emit(.local_get, acquired);
        try self.emit(.i32_load, heap.offset(heap.Owning, "token"));
        try self.emit(.if_, 0);
        try self.emit(.unreachable_, 0);
        try self.emit(.end, 0);
        const raw = try self.temporary(g.representations.store.machine(payload));
        try self.emit(.local_get, acquired);
        try self.emit(if (g.representations.store.machine(payload) == .f32) .f32_load else .i32_load, heap.offset(heap.Owning, "payload"));
        try self.emit(.local_set, raw);
        try self.storeTypedWord(owner, heap.offset(heap.Owning, "payload"), raw, g.representations.store.scalar(payload) orelse .pointer, 0);
        const arena = g.module.arena.?;
        if (g.layoutRole(payload) == .reference) {
            try self.emit(.local_get, raw);
            try self.emit(.call, arena.retain);
        }
        try self.emit(.local_get, cleanup);
        try self.emit(.call, arena.retain);
        try self.emit(.local_get, token);
        try self.emit(.i32_const, adapter);
        try self.emit(.local_get, raw);
        if (g.representations.store.machine(payload) == .f32) try self.emit(.i32_reinterpret_f32, 0);
        try self.emit(.local_get, cleanup);
        try self.emit(.i32_const, 0); // Independently pure cleanup owns no provider.
        try self.emit(.local_get, owner);
        try self.emit(.call_import, imports.register);
        try self.emit(.local_get, owner);
    }
    fn resourceRelease(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        const wrapper = source.types.node(source.typeOf(node.a));
        if (node.b != 0 or node.c != 0 or node.ty != types.unit or wrapper.tag != .usage or wrapper.b != @backingInt(types.UsageKind.unique) or wrapper.c != 0 or !@import("../check/cleanup_contracts.zig").payloadNominal(&source.types, source.nominals, wrapper.a)) return g.fail(self.unit_id, id, .unsupported);
        const imports = try g.module.resourceTransferImports();
        _ = try g.resourceAdapter(g.representations.store.node(try self.codeLayout(source.typeOf(node.a), source.span(id))).a);
        const captured = try self.capture(node.a, depth);
        const owner = try self.temporary(.i32);
        try self.emit(.local_get, captured);
        try self.emit(.local_set, owner);
        // Package views own an older owner. Follow that exact allocation shape
        // to its one token; views themselves never register cleanup authority.
        try self.emit(.block, 0);
        self.labels += 1;
        try self.emit(.loop, 0);
        self.labels += 1;
        try self.emit(.local_get, owner);
        try self.emit(.i32_const, @sizeOf(heap.ArenaHeader));
        try self.emit(.i32_sub, 0);
        try self.emit(.i32_load, heap.offset(heap.ArenaHeader, "requested"));
        try self.emit(.i32_const, @sizeOf(heap.OwningView));
        try self.emit(.i32_ne, 0);
        try self.emit(.br_if, 1);
        try self.emit(.local_get, owner);
        try self.emit(.i32_load, heap.offset(heap.OwningView, "owner"));
        try self.emit(.local_set, owner);
        try self.emit(.br, 0);
        self.labels -= 1;
        try self.emit(.end, 0);
        self.labels -= 1;
        try self.emit(.end, 0);
        const token = try self.temporary(.i32);
        try self.emit(.local_get, owner);
        try self.emit(.i32_load, heap.offset(heap.Owning, "token"));
        try self.emit(.local_tee, token);
        try self.emit(.if_, 0);
        try self.emit(.local_get, token);
        try self.emit(.call_import, imports.release);
        try self.emit(.end, 0);
        try self.emit(.i32_const, 0);
    }
    /// The ownership mover follows the selected physical schema, stopping at
    /// shared boxes and scoped loans. Numeric payloads are never pointer guesses.
    fn taskMove(self: *Emitter, ty: layout.Id, value: u32, depth: usize) Error!void {
        if (depth >= 128) return error.Declined;
        if (self.generator.layoutRole(ty) != .reference) return;
        const function = try self.generator.taskMover(ty);
        try self.emit(.local_get, value);
        try self.emit(.call, function);
    }
    pub fn taskMoveBody(self: *Emitter, ty: layout.Id, value: u32, depth: usize) Error!void {
        const g = self.generator;
        if (depth >= 128) return error.Declined;
        const n = g.representations.store.node(ty);
        if (g.layoutRole(ty) != .reference) return;
        switch (n.tag) {
            .owning => {
                if (n.b != @backingInt(types.UsageKind.unique)) return;
                const payload = g.representations.store.node(n.a);
                if (payload.tag == .nominal and payload.a == std.math.maxInt(u32) and payload.b == layout.capability_layout_decl) return;
                const token = try self.temporary(.i32);
                try self.emit(.local_get, value);
                try self.emit(.i32_load, heap.offset(heap.Owning, "token"));
                try self.emit(.local_tee, token);
                try self.emit(.if_, 0);
                try self.emit(.local_get, token);
                try self.emit(.call_import, g.module.taskImportNamed("transfer").?);
                try self.emit(.end, 0);
                if (g.layoutRole(n.a) == .reference) {
                    const child = try self.temporary(.i32);
                    try self.emit(.local_get, value);
                    try self.emit(.i32_load, heap.offset(heap.Owning, "payload"));
                    try self.emit(.local_set, child);
                    try self.taskMove(n.a, child, depth + 1);
                }
            },
            .product, .record => {
                const children = g.representations.store.children(ty);
                const count = if (n.tag == .record) children.len / 2 else children.len;
                for (0..count) |index| {
                    const child_ty = children[if (n.tag == .record) index * 2 + 1 else index];
                    if (g.layoutRole(child_ty) != .reference) continue;
                    const child = try self.temporary(.i32);
                    try self.emit(.local_get, value);
                    try self.emit(.i32_load, @intCast(index * 4));
                    try self.emit(.local_set, child);
                    try self.taskMove(child_ty, child, depth + 1);
                }
            },
            .array, .list => {
                if (g.layoutRole(n.a) != .reference or try g.rowWords(n.a) != 0) return;
                const index = try self.temporary(.i32);
                const child = try self.temporary(.i32);
                try self.emit(.i32_const, 0);
                try self.emit(.local_set, index);
                try self.emit(.block, 0);
                try self.emit(.loop, 0);
                try self.emit(.local_get, index);
                try self.emit(.local_get, value);
                try self.emit(.i32_load, 0);
                try self.emit(.i32_ge_u, 0);
                try self.emit(.br_if, 1);
                if (n.tag == .list) {
                    try self.emit(.local_get, value);
                    try self.emit(.local_get, index);
                    try self.emit(.call, (try g.module.ensureLists()).address);
                    try self.emit(.i32_load, 0);
                } else {
                    try self.arrayAddress(value, index, 4);
                    try self.emit(.i32_load, 4);
                }
                try self.emit(.local_set, child);
                try self.taskMove(n.a, child, depth + 1);
                try self.emit(.local_get, index);
                try self.emit(.i32_const, 1);
                try self.emit(.i32_add, 0);
                try self.emit(.local_set, index);
                try self.emit(.br, 0);
                try self.emit(.end, 0);
                try self.emit(.end, 0);
            },
            // Immutable callable environments use the exact capture schema
            // through taskMoveTemplate, rather than their arrow type.
            .function, .demand => return error.Declined,
            .nominal => {
                if (n.a == std.math.maxInt(u32) and n.b == layout.capability_layout_decl) return;
                if (g.representations.store.scalar(ty) != null) return;
                if (n.a == 0 or n.a > g.units.len) return error.Declined;
                const owner = g.unit(n.a);
                var found = false;
                for (owner.constructors) |constructor| {
                    const nominal = owner.nominal(constructor.nominal);
                    if (nominal.identity.unit != n.a or nominal.identity.decl != n.b) continue;
                    found = true;
                    if (constructor.payload == 0) continue;
                    const payload = try g.nominalPayload((@as(u64, n.a) << 32) | n.b, constructor.tag, ty);
                    if (g.layoutRole(payload) != .reference) continue;
                    if (nominal.is_opaque) {
                        try self.taskMove(payload, value, depth + 1);
                    } else {
                        try self.emit(.local_get, value);
                        try self.emit(.i32_load, 0);
                        try self.emit(.i32_const, constructor.tag);
                        try self.emit(.i32_eq, 0);
                        try self.emit(.if_, 0);
                        const child = try self.temporary(.i32);
                        try self.emit(.local_get, value);
                        try self.emit(.i32_load, 4);
                        try self.emit(.local_set, child);
                        try self.taskMove(payload, child, depth + 1);
                        try self.emit(.end, 0);
                    }
                }
                if (!found) return error.Declined;
            },
            else => {},
        }
    }
    fn taskMoveTemplate(self: *Emitter, metadata: anytype, environment: u32, depth: usize) Error!void {
        const g = self.generator;
        if (depth >= 128) return error.Declined;
        const source = g.unit(metadata.unit);
        const n = source.node(metadata.node);
        if (n.tag != .closure and n.tag != .suspend_) return;
        if (metadata.scalar_environment) return;
        const captures = if (n.tag == .closure) source.closureCaptures(metadata.node) else source.suspensionCaptures(metadata.node);
        for (captures, g.representations.store.children(metadata.captures), 0..) |binding, ty, index| {
            const child = try self.temporary(.i32);
            if (g.capturedTemplate(metadata.templates, binding)) |nested| {
                try self.emit(.local_get, environment);
                try self.emit(.i32_load, @intCast(index * 4));
                try self.emit(.local_set, child);
                if (nested.demand_cell) {
                    // A captured cell is a descriptor, while an ordinary
                    // captured template slot stores only its environment.
                    try self.emit(.local_get, child);
                    try self.emit(.i32_load, heap.offset(heap.Demand, "status"));
                    try self.emit(.i32_const, 1);
                    try self.emit(.i32_and, 0);
                    try self.emit(.if_, 0);
                    try self.emit(.unreachable_, 0);
                    try self.emit(.end, 0);
                    const environment_ = try self.temporary(.i32);
                    try self.emit(.local_get, child);
                    try self.emit(.i32_load, heap.offset(heap.Demand, "environment"));
                    try self.emit(.local_set, environment_);
                    try self.taskMoveTemplate(nested, environment_, depth + 1);
                    var result: ?layout.Id = null;
                    var instances = g.planning.closures.iterator();
                    while (instances.next()) |instance| {
                        const key = instance.key_ptr.*;
                        if (key.unit != nested.unit or key.catalog != g.unit(nested.unit).node(nested.node).a or key.captures != nested.captures or key.templates != nested.templates or key.staged != nested.staged or key.evidence != nested.evidence or key.rows != nested.rows) continue;
                        const payload = g.representations.store.node(key.ty).b;
                        if (result != null and result.? != payload) return error.Declined;
                        result = payload;
                    }
                    const payload = result orelse return error.Declined;
                    if (g.layoutRole(payload) == .reference) {
                        try self.emit(.local_get, child);
                        try self.emit(.i32_load, heap.offset(heap.Demand, "status"));
                        try self.emit(.i32_const, 2);
                        try self.emit(.i32_eq, 0);
                        try self.emit(.if_, 0);
                        const cached = try self.temporary(.i32);
                        try self.emit(.local_get, child);
                        try self.emit(.i32_load, heap.offset(heap.Demand, "cached"));
                        try self.emit(.local_set, cached);
                        try self.taskMove(payload, cached, depth + 1);
                        try self.emit(.end, 0);
                    }
                } else try self.taskMoveTemplate(nested, child, depth + 1);
            } else if (g.layoutRole(ty) == .reference) {
                const semantic = source.types.node(source.binding(binding).ty);
                if (semantic.tag == .usage and (semantic.b == @backingInt(types.UsageKind.concurrent) or semantic.b == @backingInt(types.UsageKind.borrow))) continue;
                try self.emit(.local_get, environment);
                try self.emit(.i32_load, @intCast(index * 4));
                try self.emit(.local_set, child);
                try self.taskMove(ty, child, depth + 1);
            }
        }
    }
    fn taskDescriptor(self: *Emitter, thunk: core.Id) Error!u32 {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const metadata = metadata: {
            if (source.node(thunk).tag == .reference) {
                if (self.templates.get(source.reference(thunk).binding)) |selected| break :metadata selected;
            }
            const actual = @import("../check/task_core.zig").callable(source, thunk) catch return error.Declined;
            const prepared = self.resolvedPlan(actual).template;
            var selected = prepared.metadata;
            if (prepared.static_key) |key| selected.captures = key.captures;
            break :metadata selected;
        };
        const owner_id = if (metadata.unit == 0) self.unit_id else metadata.unit;
        const owner = g.unit(owner_id);
        if (owner.node(metadata.node).tag != .closure) return error.Declined;
        const ty = try self.codeLayout(source.typeOf(thunk), source.span(thunk));
        const arrow = g.representations.store.node(ty);
        const task_descriptor = g.module.taskCount();
        const run = try g.module.addTypedFunction(&.{.i32}, .i32, .reference);
        try g.setParameterRoles(run, ir.packParameterRoles(&.{.reference}), null);
        var adapter: Emitter = .{ .generator = g, .unit_id = self.unit_id, .function_id = run, .mappings = self.mappings, .row_mappings = self.row_mappings };
        defer adapter.deinit();
        const callable = try adapter.temporary(.i32);
        const provider = try adapter.temporary(.i32);
        try adapter.emit(.local_get, 0);
        try adapter.emit(.i32_load, 0);
        try adapter.emit(.local_set, callable);
        try adapter.emit(.local_get, 0);
        try adapter.emit(.i32_load, 4);
        try adapter.emit(.local_set, provider);
        adapter.provider_local = provider;
        try adapter.invokeUsageClosure(callable, null, arrow);
        const result_role = g.bodyResultRole(arrow.b, owner_id, owner.closure(metadata.node).body);
        try adapter.boxOwnerStorage(g.representations.store.machine(arrow.b), result_role);
        const result = try adapter.temporary(.i32);
        try adapter.emit(.local_tee, result);
        try adapter.emit(.call, g.module.arena.?.retain);
        try adapter.emit(.local_get, result);
        const name = try g.allocator.print("blot:task_start/{d}", .{task_descriptor});
        defer g.allocator.free(name);
        try g.module.exportTaskAdapter(run, name, false);
        inline for (.{ false, true }) |result_move| {
            const move = try g.module.addTypedFunction(&.{.i32}, .none, .scalar);
            try g.setParameterRoles(move, ir.packParameterRoles(&.{.reference}), null);
            var mover: Emitter = .{ .generator = g, .unit_id = self.unit_id, .function_id = move, .mappings = self.mappings, .row_mappings = self.row_mappings };
            defer mover.deinit();
            const value = try mover.temporary(.i32);
            try mover.emit(.local_get, 0);
            try mover.emit(.i32_load, 0);
            try mover.emit(.local_set, value);
            if (result_move) {
                if (result_role == .reference) try mover.taskMove(arrow.b, value, 0);
            } else {
                const environment = try mover.temporary(.i32);
                try mover.emit(.local_get, value);
                try mover.emit(.i32_load, heap.offset(heap.Closure, "environment"));
                try mover.emit(.local_set, environment);
                try mover.taskMoveTemplate(metadata, environment, 0);
            }
            const move_name = try g.allocator.print("blot:task_move_{s}/{d}", .{ if (result_move) "result" else "captures", task_descriptor });
            defer g.allocator.free(move_name);
            try g.module.exportTaskAdapter(move, move_name, false);
        }
        return task_descriptor;
    }
    fn taskSplit(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const args = source.children(id);
        const plan = @import("../check/task_regions.zig").partition(source, id) catch return g.fail(self.unit_id, id, .unsupported);
        const owner = try self.capture(args[0], depth);
        try self.expression(args[1], depth + 1);
        try self.emit(.drop, 0);
        const callback = try self.capture(args[2], depth);
        const array_ = try self.temporary(.i32);
        try self.emit(.local_get, owner);
        try self.emit(.i32_load, heap.offset(heap.Owning, "payload"));
        try self.emit(.local_set, array_);
        try self.emit(.local_get, array_);
        try self.emit(.i32_load, 0);
        try self.emit(.i32_const, plan.limit);
        try self.emit(.i32_lt_u, 0);
        try self.emit(.if_, 0);
        try self.emit(.unreachable_, 0);
        try self.emit(.end, 0);
        const checkpoint = self.cleanups.mark();
        defer self.cleanups.restore(checkpoint);
        var views: [16]u32 = undefined;
        for (plan.ranges[0..plan.len], views[0..plan.len]) |range, *slot| {
            const view = try self.allocate(16, .{ .words = &.{ .scalar, .reference, .scalar, .scalar } });
            for ([_]u32{ 0, 8, 12 }, [_]u32{ 1, range.first, range.end }) |offset, bits| {
                try self.emit(.local_get, view);
                try self.emit(.i32_const, bits);
                try self.emit(.i32_store, offset);
            }
            try self.emit(.local_get, view);
            try self.emit(.local_get, owner);
            try self.emit(.i32_store, 4);
            try self.cleanups.append(g.allocator, .{ .revoke_effect = @fromBackingInt(@intCast(view)) });
            try self.emit(.local_get, view);
            try self.emit(.call, g.module.arena.?.root_authority);
            try self.emit(.local_get, view);
            try self.boxOwnerStorage(.i32, .reference);
            slot.* = try self.temporary(.i32);
            try self.emit(.local_set, slot.*);
        }
        const roles = try g.allocator.alloc(ir.Role, plan.len);
        defer g.allocator.free(roles);
        @memset(roles, .reference);
        const product = try self.allocate(@intCast(plan.len * 4), .{ .words = roles });
        for (views[0..plan.len], 0..) |view, index| {
            try self.emit(.local_get, product);
            try self.emit(.local_get, view);
            try self.emit(.i32_store, @intCast(index * 4));
        }
        const arrow = g.representations.store.node(try self.codeLayout(source.typeOf(args[2]), source.span(id)));
        try self.invokeUsageClosure(callback, product, arrow);
        const result = try self.temporary(g.representations.store.machine(arrow.b));
        try self.emit(.local_set, result);
        try self.emit(.call_import, g.module.taskImportNamed("drain").?);
        try self.cleanupTo(checkpoint);
        const pair = try self.allocate(8, .{ .words = &.{ .reference, g.layoutRole(arrow.b) } });
        try self.emit(.local_get, pair);
        try self.emit(.local_get, owner);
        try self.emit(.i32_store, 0);
        try self.emit(.local_get, pair);
        try self.emit(.local_get, result);
        try self.emit(if (g.representations.store.machine(arrow.b) == .f32) .f32_store else .i32_store, 4);
        try self.emit(.local_get, pair);
    }
    fn taskView(self: *Emitter, id: core.Id, depth: usize, write: bool) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const args = source.children(id);
        const boxed = try self.capture(args[0], depth);
        const index = try self.capture(args[1], depth);
        const value = if (write) try self.capture(args[2], depth) else 0;
        const view = try self.temporary(.i32);
        const array_ = try self.temporary(.i32);
        const absolute = try self.temporary(.i32);
        try self.emit(.local_get, boxed);
        try self.emit(.i32_load, 0);
        try self.emit(.local_set, view);
        try self.emit(.local_get, view);
        try self.emit(.i32_load, 0);
        try self.emit(.i32_eqz, 0);
        try self.emit(.if_, 0);
        try self.emit(.unreachable_, 0);
        try self.emit(.end, 0);
        try self.emit(.local_get, index);
        try self.emit(.local_get, view);
        try self.emit(.i32_load, 12);
        try self.emit(.local_get, view);
        try self.emit(.i32_load, 8);
        try self.emit(.i32_sub, 0);
        try self.emit(.i32_ge_u, 0);
        try self.emit(.if_, 0);
        try self.emit(.unreachable_, 0);
        try self.emit(.end, 0);
        try self.emit(.local_get, index);
        try self.emit(.local_get, view);
        try self.emit(.i32_load, 8);
        try self.emit(.i32_add, 0);
        try self.emit(.local_set, absolute);
        try self.emit(.local_get, view);
        try self.emit(.i32_load, 4);
        try self.emit(.i32_load, 0);
        try self.emit(.local_set, array_);
        const info = @import("../check/task_types.zig").viewInfo(&source.types, source.typeOf(args[0])).?;
        const element = try self.codeLayout(source.types.node(info.payload).a, source.span(id));
        const machine = g.representations.store.machine(element);
        const row_words = try g.rowWords(element);
        const stride = packed_layout.stride(row_words);
        if (row_words != 0) {
            try self.arrayAddress(array_, absolute, stride);
            if (write) {
                try self.emit(.local_get, value);
                try self.storeElement(machine, 4, row_words, true, element);
                try self.emit(.i32_const, 0);
            } else try self.readElement(machine, 4, row_words, element);
            return;
        }
        if (write and g.layoutRole(element) == .reference) {
            try self.emit(.local_get, array_);
            try self.arrayAddress(array_, absolute, stride);
            try self.emit(.i32_const, 4);
            try self.emit(.i32_add, 0);
            try self.emit(.local_get, value);
            try self.emit(.call, g.module.arena.?.store_word);
        } else {
            try self.arrayAddress(array_, absolute, stride);
            if (write) {
                try self.emit(.local_get, value);
                try self.storeScalar(if (machine == .f32) .f32_store else .i32_store, 4);
            } else try self.emit(if (machine == .f32) .f32_load else .i32_load, 4);
        }
        if (write) try self.emit(.i32_const, 0);
    }
    fn task(self: *Emitter, id: core.Id, depth: usize) Error!void {
        return self.taskImpl(id, depth) catch |err| switch (err) {
            error.Declined => self.generator.fail(self.unit_id, id, .unsupported),
            else => err,
        };
    }
    fn prepareSpawnApplication(self: *Emitter, id: core.Id) Error!?@import("../check/task_core.zig").SpawnApplication {
        const g = self.generator;
        if (g.spawn_units.len == 0) return null;
        return @import("../check/task_core.zig").spawnApplication(g.unit(self.unit_id), id, g.spawn_units) catch return g.fail(self.unit_id, id, .unsupported);
    }
    fn emitSpawnApplication(self: *Emitter, application: @import("../check/task_core.zig").SpawnApplication, depth: usize) Error!void {
        switch (application) {
            .partial => |group_source| {
                const group = try self.capture(group_source, depth);
                // Private, non-callable carrier for a checked partial spawn.
                // Core admits only further application and aliasing of it.
                const carrier = try self.allocate(8, .{ .words = &.{ .scalar, .reference } });
                try self.emit(.local_get, carrier);
                try self.emit(.i32_const, 0);
                try self.emit(.i32_store, heap.offset(heap.Closure, "function"));
                try self.emit(.local_get, carrier);
                try self.emit(.local_get, group);
                try self.emit(.i32_store, heap.offset(heap.Closure, "environment"));
                try self.emit(.local_get, carrier);
            },
            .full => |call| {
                const group = if (call.carrier == 0) try self.capture(call.group, depth) else group: {
                    const carrier = try self.capture(call.carrier, depth);
                    const local = try self.temporary(.i32);
                    try self.emit(.local_get, carrier);
                    try self.emit(.i32_load, heap.offset(heap.Closure, "environment"));
                    try self.emit(.local_set, local);
                    break :group local;
                };
                const thunk = try self.capture(call.action, depth);
                try self.emitTaskSpawn(group, thunk, try self.taskDescriptor(call.action));
            },
        }
    }
    fn emitTaskSpawn(self: *Emitter, group: u32, thunk: u32, task_descriptor: u32) Error!void {
        const g = self.generator;
        _ = try g.taskRuntime();
        const captures = try self.allocate(8, .{ .words = &.{ .reference, .reference } });
        try self.emit(.local_get, captures);
        try self.emit(.local_get, thunk);
        try self.emit(.i32_store, 0);
        try self.emit(.local_get, captures);
        try self.providerHead();
        try self.emit(.i32_store, 4);
        const handle = try self.allocate(8, .{ .words = &.{ .scalar, .scalar } });
        try self.emit(.local_get, handle);
        try self.boxOwnerStorage(.i32, .reference);
        const boxed = try self.temporary(.i32);
        try self.emit(.local_set, boxed);
        try self.emit(.local_get, handle);
        try self.emit(.local_get, group);
        try self.emit(.i32_load, heap.offset(heap.EffectAuthority, "active"));
        try self.emit(.i32_const, task_descriptor);
        try self.emit(.local_get, captures);
        try self.emit(.call_import, g.module.taskImportNamed("spawn").?);
        try self.emit(.i32_store, 0);
        try self.emit(.local_get, handle);
        try self.emit(.i32_const, task_descriptor);
        try self.emit(.i32_store, 4);
        try self.emit(.local_get, boxed);
    }
    fn taskImpl(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const n = source.node(id);
        const args = source.children(id);
        _ = try g.taskRuntime();
        const op: @import("../check/task_types.zig").Op = @fromBackingInt(n.c);
        switch (op) {
            .scope => {
                if (source.node(args[0]).tag != .closure and @import("../check/task_types.zig").scopeCallback(&source.types, source.typeOf(args[0])) == null) return error.Declined;
                const checkpoint = self.cleanups.mark();
                defer self.cleanups.restore(checkpoint);
                const callback = try self.capture(args[0], depth);
                const owner = try self.allocatePrivate(@sizeOf(heap.EffectAuthority), .heap(heap.EffectAuthority));
                try self.emit(.local_get, owner);
                try self.emit(.call_import, g.module.taskImportNamed("open").?);
                try self.emit(.i32_store, heap.offset(heap.EffectAuthority, "active"));
                try self.emit(.local_get, owner);
                try self.emit(.call, g.module.arena.?.root_authority);
                try self.cleanups.append(g.allocator, .{ .revoke_effect = @fromBackingInt(@intCast(owner)) });
                try self.cleanups.append(g.allocator, .{ .task_group = .{ .owner = @fromBackingInt(@intCast(owner)), .close = g.module.taskImportNamed("close").? } });
                var callable = g.representations.store.node(try self.codeLayout(source.typeOf(args[0]), source.span(id)));
                if (callable.tag == .universal) callable = g.representations.store.node(callable.a);
                const arrow = callable;
                try self.invokeUsageClosure(callback, owner, arrow);
                const result = try self.temporary(g.representations.store.machine(arrow.b));
                try self.emit(.local_set, result);
                try self.cleanupTo(checkpoint);
                try self.emit(.local_get, result);
            },
            .spawn => {
                const group = try self.capture(args[0], depth);
                const thunk = try self.capture(args[1], depth);
                const task_descriptor = try self.taskDescriptor(args[1]);
                try self.emitTaskSpawn(group, thunk, task_descriptor);
            },
            .join, .cancel, .receive => {
                if (op == .receive and g.representations.store.node(try self.codeLayout(source.typeOf(args[0]), source.span(id))).tag == .product) return self.taskCollect(id, depth);
                const boxed = try self.capture(args[0], depth);
                const handle = try self.temporary(.i32);
                try self.emit(.local_get, boxed);
                try self.emit(.i32_load, heap.offset(heap.Owning, "payload"));
                try self.emit(.local_set, handle);
                const slot = try self.temporary(.i32);
                if (op != .cancel) try self.rootDirective(3, slot);
                try self.emit(.local_get, handle);
                try self.emit(.i32_load, 0);
                if (op != .cancel) {
                    try self.emit(.local_get, handle);
                    try self.emit(.i32_load, 4);
                }
                try self.emit(.call_import, g.module.taskImportNamed(if (op != .cancel) "join" else "cancel").?);
                if (op == .cancel) {
                    try self.emit(.i32_const, 0);
                } else {
                    const envelope = try self.temporary(.i32);
                    try self.emit(.local_set, envelope);
                    try self.rootDirective(4, slot | (envelope << 13));
                    const result = try self.codeLayout(n.ty, source.span(id));
                    const raw = try self.temporary(g.representations.store.machine(result));
                    try self.emit(.local_get, envelope);
                    try self.emit(if (g.representations.store.machine(result) == .f32) .f32_load else .i32_load, 0);
                    try self.emit(.local_set, raw);
                    // The reserved root now owns the envelope and its typed
                    // payload, so the host's publication lease can retire.
                    try self.emit(.local_get, envelope);
                    try self.emit(.call, g.module.arena.?.release);
                    try self.emit(.local_get, raw);
                }
            },
            .split => try self.taskSplit(id, depth),
            .collect => try self.taskCollect(id, depth),
            .read, .write => try self.taskView(id, depth, op == .write),
        }
    }
    fn taskCollect(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const result = try self.codeLayout(source.typeOf(id), source.span(id));
        const shape = g.representations.store.node(result);
        if (shape.tag != .product or shape.b == 0 or shape.b > 16) return g.fail(self.unit_id, id, .unsupported);
        var field_buffer: [16]layout.Id = undefined;
        @memcpy(field_buffer[0..shape.b], g.representations.store.children(result));
        const fields = field_buffer[0..shape.b];
        const input = try self.capture(source.children(id)[0], depth);
        const scalar_roles: [32]ir.Role = @splat(.scalar);
        const handles = try self.allocate(shape.b * 8, .{ .words = scalar_roles[0 .. shape.b * 2] });
        for (0..shape.b) |index| {
            const handle = try self.temporary(.i32);
            try self.emit(.local_get, input);
            try self.emit(.i32_load, @intCast(index * 4));
            try self.emit(.i32_load, heap.offset(heap.Owning, "payload"));
            try self.emit(.local_set, handle);
            inline for (0..2) |word| {
                try self.emit(.local_get, handles);
                try self.emit(.local_get, handle);
                try self.emit(.i32_load, word * 4);
                try self.emit(.i32_store, @intCast(index * 8 + word * 4));
            }
        }
        const envelopes = try self.allocate(shape.b * 4, .{ .words = scalar_roles[0..shape.b] });
        var slots: [16]u32 = undefined;
        var roles: [16]ir.Role = undefined;
        for (fields, 0..) |field, index| {
            slots[index] = try self.temporary(.i32);
            try self.rootDirective(3, slots[index]);
            roles[index] = g.layoutRole(field);
        }
        const output = try self.allocate(shape.b * 4, .{ .words = roles[0..shape.b] });
        try self.emit(.local_get, handles);
        try self.emit(.i32_const, shape.b);
        try self.emit(.local_get, envelopes);
        try self.emit(.call_import, g.module.taskImportNamed("collect").?);
        for (fields, 0..) |field, index| {
            const envelope = try self.temporary(.i32);
            try self.emit(.local_get, envelopes);
            try self.emit(.i32_load, @intCast(index * 4));
            try self.emit(.local_set, envelope);
            try self.rootDirective(4, slots[index] | (envelope << 13));
            try self.emit(.local_get, output);
            try self.emit(.local_get, envelope);
            const floating = g.representations.store.machine(field) == .f32;
            try self.emit(if (floating) .f32_load else .i32_load, 0);
            try self.emit(if (floating) .f32_store else .i32_store, @intCast(index * 4));
            try self.emit(.local_get, envelope);
            try self.emit(.call, g.module.arena.?.release);
        }
        try self.emit(.local_get, output);
    }
    fn resourceScope(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const node = g.unit(self.unit_id).node(id);
        const plan = self.resolvedPlan(id).resource_scope;
        const acquire_arrow = g.representations.store.node(plan.acquire);
        const body_arrow = g.representations.store.node(plan.callback);
        const payload = g.representations.store.node(acquire_arrow.b).a;
        const adapter = try g.resourceAdapter(payload);
        const reserve = try g.module.importFunction("blot:resource/1", "reserve", &.{}, .i32);
        const register = try g.module.importFunction("blot:resource/1", "register", &.{ .i32, .i32, .i32, .i32, .i32 }, .none);
        const release = try g.module.importFunction("blot:resource/1", "release", &.{.i32}, .none);
        const acquire = try self.capture(node.a, depth);
        const cleanup = try self.capture(node.b, depth);
        const callback = try self.capture(node.c, depth);
        const token = try self.temporary(.i32);
        try self.emit(.call_import, reserve);
        try self.emit(.local_set, token);
        const owner = try self.temporary(g.representations.store.machine(acquire_arrow.b));
        try self.invokeUsageClosure(acquire, null, acquire_arrow);
        try self.emit(.local_set, owner);
        const raw = try self.temporary(g.representations.store.machine(payload));
        try self.emit(.local_get, owner);
        try self.emit(if (g.representations.store.machine(payload) == .f32) .f32_load else .i32_load, heap.offset(heap.Owning, "payload"));
        try self.emit(.local_set, raw);
        const provider = try self.temporary(.i32);
        try self.providerHead();
        try self.emit(.local_set, provider);
        // The bounded journal reserves before acquisition; registration cannot
        // allocate. It owns the payload/adapter/provider roots before exposing
        // a loan, independently of the invocation frame's temporary roots.
        const arena = g.module.arena.?;
        if (g.layoutRole(payload) == .reference) {
            try self.emit(.local_get, raw);
            try self.emit(.call, arena.retain);
        }
        for ([_]u32{ cleanup, provider }) |root| {
            try self.emit(.local_get, root);
            try self.emit(.call, arena.retain);
        }
        try self.emit(.local_get, token);
        try self.emit(.i32_const, adapter);
        try self.emit(.local_get, raw);
        if (g.representations.store.machine(payload) == .f32) try self.emit(.i32_reinterpret_f32, 0);
        try self.emit(.local_get, cleanup);
        try self.emit(.local_get, provider);
        try self.emit(.call_import, register);
        const checkpoint = self.cleanups.mark();
        try self.cleanups.append(g.allocator, .{ .resource = .{ .token = @fromBackingInt(@intCast(token)), .release = release } });
        try self.invokeUsageClosure(callback, raw, body_arrow);
        const result = try self.temporary(g.representations.store.machine(body_arrow.b));
        try self.emit(.local_set, result);
        self.cleanups.restore(checkpoint);
        if (g.module.taskImportNamed("drain")) |drain| try self.emit(.call_import, drain);
        try self.emit(.local_get, token);
        try self.emit(.call_import, release);
        try self.emit(.local_get, result);
    }
    fn prepareUsageBorrow(self: *Emitter, id: core.Id) Error!layout.Id {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        if (node.c > 1 or source.node(node.b).tag != .closure) return g.fail(self.unit_id, id, .unsupported);
        const callback = try self.codeLayout(source.typeOf(node.b), source.span(id));
        const arrow = g.representations.store.node(callback);
        var owner = try self.codeLayout(source.typeOf(node.a), source.span(id));
        if (g.representations.store.node(owner).tag == .owning) owner = g.representations.store.node(owner).a;
        if (arrow.tag != .function or arrow.a != owner or arrow.b != try self.codeLayout(node.ty, source.span(id))) return g.fail(self.unit_id, id, .unresolved_type);
        if (g.layoutRole(owner) != .scalar and g.layoutRole(owner) != .reference) return g.fail(self.unit_id, id, .unresolved_type);
        return callback;
    }
    fn prepareUsageShare(self: *Emitter, id: core.Id) Error!layout.Id {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        const owner = source.types.node(source.typeOf(node.a));
        const shared = source.types.node(node.ty);
        if (node.b != 0 or node.c != 0 or owner.tag != .usage or owner.b != @backingInt(types.UsageKind.unique) or owner.c != 0 or shared.tag != .usage or shared.b != @backingInt(types.UsageKind.shared) or shared.c != 0 or !@import("../check/cleanup_contracts.zig").payloadNominal(&source.types, source.nominals, owner.a) or !(@import("../check/rank_equal.zig").equal(&source.types, owner.a, shared.a, true) catch return g.fail(self.unit_id, id, .unsupported))) return g.fail(self.unit_id, id, .unsupported);
        const payload = try self.codeLayout(source.typeOf(node.a), source.span(id));
        const result = try self.codeLayout(node.ty, source.span(id));
        if (g.representations.store.node(payload).tag != .owning or g.representations.store.node(result).tag != .owning or g.representations.store.node(payload).a != g.representations.store.node(result).a) return g.fail(self.unit_id, id, .unresolved_type);
        return payload;
    }
    fn prepareUsageRead(self: *Emitter, id: core.Id) Error!layout.Id {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        var owner = try self.codeLayout(source.typeOf(node.a), source.span(id));
        if (g.representations.store.node(owner).tag == .owning) owner = g.representations.store.node(owner).a;
        const tag = g.representations.store.node(owner).tag;
        const result = try self.codeLayout(node.ty, source.span(id));
        if (node.c != 0) return g.fail(self.unit_id, id, .unsupported);
        switch (node.b) {
            0 => if (g.representations.store.scalar(owner) == null or owner != result) return g.fail(self.unit_id, id, .unresolved_type),
            1 => if (tag != .array or g.representations.store.node(result).tag != .u32) return g.fail(self.unit_id, id, .unresolved_type),
            2 => if (tag != .list or g.representations.store.node(result).tag != .u32) return g.fail(self.unit_id, id, .unresolved_type),
            else => return g.fail(self.unit_id, id, .unsupported),
        }
        return owner;
    }
    fn usageBorrow(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const node = g.unit(self.unit_id).node(id);
        const ty = self.resolvedPlan(id).usage_borrow;
        // The loan is the owner's checked payload, borrowed by one direct
        // callback invocation. Its ordinary caller frame keeps the owner live.
        const owner = try self.capture(node.a, depth);
        const callback = try self.newTemplate(node.b);
        const function = try self.templateFunction(callback, ty, false);
        if (callback.environment) |environment| try self.emit(.local_get, environment) else try self.emit(.i32_const, 0);
        try self.emit(.local_get, owner);
        const storage = g.representations.store.node(try self.codeLayout(g.unit(self.unit_id).typeOf(node.a), g.unit(self.unit_id).span(id)));
        if (storage.tag == .owning) try self.emit(if (g.representations.store.machine(storage.a) == .f32) .f32_load else .i32_load, heap.offset(heap.Owning, "payload"));
        try self.providerHead();
        try self.emit(.call, function);
    }
    fn providerTokenLabel(self: *Emitter, token: types.Id, span: core.Span) Error!type_evidence.Effects.Label {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const wrapper = source.types.node(token);
        if (wrapper.tag != .scoped) return g.operationLayoutLabel(try self.codeLayout(token, span), self.unit_id, span);
        const operation_descriptor = source.types.node(wrapper.a);
        if (operation_descriptor.tag != .nominal) return g.decline(self.unit_id, span, .unresolved_type);
        var arguments: std.ArrayList(type_evidence.Id) = .empty;
        defer arguments.deinit(g.allocator);
        for (source.types.nominalArguments(operation_descriptor)) |argument| {
            const physical = try self.codeLayout(argument, span);
            const semantic = g.representations.toEvidence(g.evaluator.evidenceStore(), physical) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.decline(self.unit_id, span, .unresolved_type);
            try arguments.append(g.allocator, semantic);
        }
        return g.evaluator.storage.evidence.effects.internOperationInstance(.{ .unit = operation_descriptor.a, .decl = operation_descriptor.b }, arguments.items, layout.mappedInstance(.{ .unit = wrapper.b, .decl = wrapper.c }, self.mappings)) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.decline(self.unit_id, span, .unresolved_type);
    }
    fn prepareProvider(self: *Emitter, id: core.Id) Error!ProviderPlan {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const n = source.node(id);
        const ty = g.representations.store.node(try self.codeLayout(n.ty, source.span(id)));
        if (n.tag == .effect_provider) {
            if (ty.tag != .provider) return g.fail(self.unit_id, id, .unresolved_type);
            return .{ .ty = ty, .read = try self.providerTokenLabel(source.types.node(n.ty).a, source.span(id)) };
        }
        if (ty.tag != .state_provider) return g.fail(self.unit_id, id, .unresolved_type);
        return .{ .ty = ty, .read = try self.providerTokenLabel(source.types.node(n.ty).a, source.span(id)), .write = try self.providerTokenLabel(source.types.node(n.ty).b, source.span(id)) };
    }
    pub fn operationOwnerMatch(self: *Emitter, frame: u32, scoped: bool) Error!void {
        try self.emit(.local_get, frame);
        try self.emit(.i32_load, heap.offset(heap.ProviderFrame, "kind"));
        try self.emit(.i32_const, heap.ScopedStateFrame.tag);
        try self.emit(.i32_ge_u, 0);
        if (!scoped) {
            try self.emit(.i32_eqz, 0);
            return;
        }
        try self.emit(.if_, @backingInt(wasm.ValueType.i32));
        try self.emit(.local_get, frame);
        try self.emit(.i32_load, heap.offset(heap.ProviderFrame, "kind"));
        try self.emit(.i32_const, heap.ScopedStateFrame.tag);
        try self.emit(.i32_eq, 0);
        try self.emit(.if_, @backingInt(wasm.ValueType.i32));
        try self.emit(.local_get, frame);
        try self.emit(.i32_load, heap.offset(heap.ScopedStateFrame, "owner"));
        try self.emit(.else_, 0);
        try self.emit(.local_get, frame);
        try self.emit(.i32_load, heap.offset(heap.ProviderFrame, "kind"));
        try self.emit(.i32_const, heap.ScopedRequestFrame.tag);
        try self.emit(.i32_eq, 0);
        try self.emit(.if_, @backingInt(wasm.ValueType.i32));
        try self.emit(.local_get, frame);
        try self.emit(.i32_load, heap.offset(heap.ScopedRequestFrame, "owner"));
        try self.emit(.else_, 0);
        try self.emit(.local_get, frame);
        try self.emit(.i32_load, heap.offset(heap.ScopedFrame, "owner"));
        try self.emit(.end, 0);
        try self.emit(.end, 0);
        try self.emit(.local_get, 0);
        try self.emit(.i32_eq, 0);
        try self.emit(.else_, 0);
        try self.emit(.i32_const, 0);
        try self.emit(.end, 0);
    }
    fn scopedProvider(self: *Emitter, provider_type: types.Id) bool {
        const source = self.generator.unit(self.unit_id);
        const provider_ = source.types.node(provider_type);
        if (provider_.tag != .provider and provider_.tag != .state_provider) return false;
        return source.types.node(provider_.a).tag == .scoped;
    }
    fn effectScope(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const checkpoint = self.cleanups.mark();
        defer self.cleanups.restore(checkpoint);
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const n = source.node(id);
        if (g.artifacts) |context| context.requireFreshCode();
        const callback = try self.capture(n.a, depth);
        const owner = try self.allocatePrivate(@sizeOf(heap.EffectAuthority), .heap(heap.EffectAuthority));
        try self.cleanups.append(g.allocator, .{ .revoke_effect = @fromBackingInt(@intCast(owner)) });
        try self.emit(.local_get, owner);
        try self.emit(.i32_const, 1);
        try self.emit(.i32_store, heap.offset(heap.EffectAuthority, "active"));
        try self.emit(.local_get, owner);
        try self.emit(.call, g.module.arena.?.root_authority);
        try self.emit(.local_get, callback);
        try self.emit(.i32_load, heap.offset(heap.Closure, "environment"));
        try self.emit(.local_get, owner);
        try self.providerHead();
        try self.emit(.local_get, callback);
        try self.emit(.i32_load, heap.offset(heap.Closure, "function"));
        const result = try self.codeLayout(n.ty, source.span(id));
        const machine = g.representations.store.machine(result);
        try g.module.emit(self.function_id, ir.callResult(g.layoutRole(result)));
        try self.emit(.call_indirect, try g.module.internType(&.{ .i32, .i32, .i32 }, machine));
        const value = try self.temporary(machine);
        try self.emit(.local_set, value);
        try self.cleanupTo(checkpoint);
        try self.emit(.local_get, value);
    }
    fn operationOwner(self: *Emitter, id: core.Id, depth: usize) Error!u32 {
        const source = self.generator.unit(self.unit_id);
        if (source.node(id).tag == .operation_value) {
            const operation = source.operationValue(id);
            if (operation.capability != 0) return self.capture(operation.capability, depth);
        }
        const operation = try self.capture(id, depth);
        const owner = try self.temporary(.i32);
        try self.emit(.local_get, operation);
        try self.emit(.i32_load, heap.offset(heap.Closure, "environment"));
        try self.emit(.local_set, owner);
        return owner;
    }
    fn providerValue(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const n = source.node(id);
        const prepared = self.resolvedPlan(id).provider;
        const ty = prepared.ty;
        const scoped = self.scopedProvider(n.ty);
        if (n.tag == .effect_provider) {
            const token = try g.runtimeOperation(prepared.read, self.unit_id, source.span(id));
            const implementation = try self.capture(n.b, depth);
            var owner: ?u32 = null;
            if (scoped) {
                owner = try self.operationOwner(n.a, depth);
            }
            const provider = if (scoped) try self.allocate(@sizeOf(heap.ScopedProvider), .heap(heap.ScopedProvider)) else try self.allocate(@sizeOf(provider_chain.Provider), .heap(provider_chain.Provider));
            if (owner) |owned| {
                try self.emit(.local_get, provider);
                try self.emit(.local_get, owned);
                try self.emit(.i32_store, heap.offset(heap.ScopedProvider, "owner"));
            }
            try self.emit(.local_get, provider);
            try self.operationConstant(token);
            try self.emit(.i32_store, @offsetOf(provider_chain.Provider, "operation"));
            try self.emit(.local_get, provider);
            try self.emit(.local_get, implementation);
            try self.emit(.i32_store, @offsetOf(provider_chain.Provider, "implementation"));
            try self.emit(.local_get, provider);
        } else {
            const read = try g.runtimeOperation(prepared.read, self.unit_id, source.span(id));
            const write = try g.runtimeOperation(prepared.write.?, self.unit_id, source.span(id));
            const initial = try self.capture(n.c, depth);
            var owner: ?u32 = null;
            if (scoped) {
                owner = try self.operationOwner(n.a, depth);
            }
            const provider = if (scoped) try self.allocate(@sizeOf(heap.ScopedStateProvider), .{ .words = &.{ .scalar, .scalar, g.layoutRole(ty.c), .reference } }) else try self.allocate(@sizeOf(provider_chain.StateProvider), .{ .words = &.{ .scalar, .scalar, g.layoutRole(ty.c) } });
            if (owner) |owned| {
                try self.emit(.local_get, provider);
                try self.emit(.local_get, owned);
                try self.emit(.i32_store, heap.offset(heap.ScopedStateProvider, "owner"));
            }
            try self.emit(.local_get, provider);
            try self.operationConstant(read);
            try self.emit(.i32_store, @offsetOf(provider_chain.StateProvider, "read"));
            try self.emit(.local_get, provider);
            try self.operationConstant(write);
            try self.emit(.i32_store, @offsetOf(provider_chain.StateProvider, "write"));
            try self.emit(.local_get, provider);
            try self.emit(.local_get, initial);
            try self.emit(if (g.representations.store.machine(ty.c) == .f32) .f32_store else .i32_store, @offsetOf(provider_chain.StateProvider, "initial"));
            try self.emit(.local_get, provider);
        }
    }
    fn providerOrigin(self: *Emitter, frame: u32, kind: u32, role: ir.Role, read: runtime_operations.Id, write: ?runtime_operations.Id) Error!void {
        const origins = @import("provider_origins.zig");
        try self.emit(.ownership, @bitCast(ir.Ownership{ .kind = .rest, .chunk = origins.begin_chunk, .roles = @intCast(frame) }));
        try self.operationConstant(read);
        try self.emit(.drop, 0);
        if (write) |operation| {
            try self.operationConstant(operation);
            try self.emit(.drop, 0);
        }
        try self.emit(.ownership, @bitCast(ir.Ownership{ .kind = .rest, .chunk = origins.end_chunk, .roles = @intCast(kind | @as(u32, @backingInt(role)) << 3) }));
    }
    fn providerOperation(self: *Emitter, ty: layout.Id, id: core.Id) Error!?runtime_operations.Id {
        const g = self.generator;
        var selected = ty;
        if (g.representations.store.node(selected).tag == .scoped) selected = g.representations.store.node(selected).a;
        if (g.representations.store.node(selected).tag != .nominal) return null;
        const diagnostic = g.diagnostic;
        const label = g.operationLayoutLabel(selected, self.unit_id, g.unit(self.unit_id).span(id)) catch |err| switch (err) {
            error.Declined => {
                g.diagnostic = diagnostic;
                return null;
            },
            else => return err,
        };
        return g.runtimeOperation(label, self.unit_id, g.unit(self.unit_id).span(id)) catch |err| switch (err) {
            error.Declined => {
                g.diagnostic = diagnostic;
                return null;
            },
            else => return err,
        };
    }
    fn callbackFrame(self: *Emitter, provider: u32, target: u32, outer: ?u32, scoped: bool, operation: ?runtime_operations.Id) Error!u32 {
        const frame = if (scoped) try self.allocatePrivate(@sizeOf(heap.ScopedFrame), .heap(heap.ScopedFrame)) else try self.allocatePrivate(@sizeOf(provider_chain.Frame), .heap(provider_chain.Frame));
        if (scoped) {
            try self.emit(.local_get, frame);
            try self.emit(.local_get, provider);
            try self.emit(.i32_load, heap.offset(heap.ScopedProvider, "owner"));
            try self.emit(.i32_store, heap.offset(heap.ScopedFrame, "owner"));
        }
        try self.emit(.local_get, frame);
        if (operation) |token| {
            try self.operationConstant(token);
        } else {
            try self.emit(.local_get, provider);
            try self.emit(.i32_load, @offsetOf(provider_chain.Provider, "operation"));
        }
        try self.emit(.i32_store, @offsetOf(provider_chain.Frame, "operation"));
        try self.emit(.local_get, frame);
        try self.emit(.local_get, target);
        try self.emit(.i32_store, @offsetOf(provider_chain.Frame, "target"));
        try self.emit(.local_get, frame);
        if (outer) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
        try self.emit(.i32_store, @offsetOf(provider_chain.Frame, "outer"));
        try self.emit(.local_get, frame);
        try self.emit(.i32_const, if (scoped) heap.ScopedFrame.tag else @backingInt(provider_chain.Kind.callback));
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
        const ty = g.representations.store.node(concrete);
        const provider = try self.capture(n.a, depth);
        const scoped = self.scopedProvider(source.typeOf(n.a));
        const outer = self.provider_local;
        defer self.provider_local = outer;
        if (ty.tag == .provider) {
            const implementation = try self.temporary(.i32);
            try self.emit(.local_get, provider);
            try self.emit(.i32_load, @offsetOf(provider_chain.Provider, "implementation"));
            try self.emit(.local_set, implementation);
            const operation = try self.providerOperation(ty.a, id);
            self.provider_local = try self.callbackFrame(provider, implementation, outer, scoped, operation);
            if (operation) |token| try self.providerOrigin(self.provider_local.?, if (scoped) heap.ScopedFrame.tag else @backingInt(provider_chain.Kind.callback), .reference, token, null);
            try self.expression(n.b, depth + 1);
        } else if (ty.tag == .state_provider) {
            const state_machine = g.representations.store.machine(ty.c);
            const read_operation = try self.providerOperation(ty.a, id);
            const write_operation = try self.providerOperation(ty.b, id);
            const frame = if (scoped) try self.allocatePrivate(@sizeOf(heap.ScopedStateFrame), .{ .words = &.{ .scalar, g.layoutRole(ty.c), .reference, .scalar, .scalar, .reference } }) else try self.allocatePrivate(@sizeOf(heap.StateFrame), .{ .words = &.{ .scalar, g.layoutRole(ty.c), .reference, .scalar, .scalar } });
            if (scoped) {
                try self.emit(.local_get, frame);
                try self.emit(.local_get, provider);
                try self.emit(.i32_load, heap.offset(heap.ScopedStateProvider, "owner"));
                try self.emit(.i32_store, heap.offset(heap.ScopedStateFrame, "owner"));
            }
            inline for (.{ "read", "write" }, .{ read_operation, write_operation }) |field, operation| {
                try self.emit(.local_get, frame);
                if (operation) |token| {
                    try self.operationConstant(token);
                } else {
                    try self.emit(.local_get, provider);
                    try self.emit(.i32_load, @offsetOf(provider_chain.StateProvider, field));
                }
                try self.emit(.i32_store, @offsetOf(heap.StateFrame, field));
            }
            try self.emit(.local_get, frame);
            try self.emit(.local_get, provider);
            try self.emit(if (state_machine == .f32) .f32_load else .i32_load, @offsetOf(provider_chain.StateProvider, "initial"));
            try self.emit(if (state_machine == .f32) .f32_store else .i32_store, @offsetOf(heap.StateFrame, "value"));
            try self.emit(.local_get, frame);
            if (outer) |local| try self.emit(.local_get, local) else try self.emit(.i32_const, 0);
            try self.emit(.i32_store, @offsetOf(heap.StateFrame, "outer"));
            try self.emit(.local_get, frame);
            try self.emit(.i32_const, if (scoped) heap.ScopedStateFrame.tag else heap.StateFrame.tag);
            try self.emit(.i32_store, @offsetOf(heap.StateFrame, "kind"));
            if (read_operation) |read| if (write_operation) |write| try self.providerOrigin(frame, if (scoped) heap.ScopedStateFrame.tag else heap.StateFrame.tag, g.layoutRole(ty.c), read, write);
            self.provider_local = frame;
            const result = try self.capture(n.b, depth);
            const result_machine = (try self.scalar(n.b)).machine();
            // The final state, then the result.
            const pair = try self.allocate(8, .{ .words = &.{ g.layoutRole(ty.c), g.layoutRole(try self.codeLayout(g.unit(self.unit_id).typeOf(n.b), g.unit(self.unit_id).span(n.b))) } });
            try self.emit(.local_get, pair);
            try self.emit(.local_get, frame);
            try self.emit(if (state_machine == .f32) .f32_load else .i32_load, @offsetOf(heap.StateFrame, "value"));
            try self.emit(if (state_machine == .f32) .f32_store else .i32_store, 0);
            try self.emit(.local_get, pair);
            try self.emit(.local_get, result);
            try self.emit(if (result_machine == .f32) .f32_store else .i32_store, 4);
            try self.emit(.local_get, pair);
        } else return g.fail(self.unit_id, id, .invalid_provider);
        try self.cleanupTo(checkpoint);
    }
    /// Selects a resolver method's target and how it consumes the arguments.
    fn prepareResolverCall(self: *Emitter, id: core.Id, provider: layout.Node) Error!resolved_call.Applied {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const metadata = unit_.resolverInfo(id);
        const arguments = unit_.resolverArguments(id);
        const token = g.representations.store.node(provider.a);
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
        var plan: resolved_call.Applied = undefined;
        if (body.parameters.len != 0 and body.parameters.len <= arguments.len and body.parameters.len <= max_parameters) {
            var key: Key = .{ .target = target, .count = @intCast(body.parameters.len) };
            for (0..body.parameters.len) |index| {
                const arrow = g.representations.store.node(ty);
                if (arrow.tag != .function) return g.fail(self.unit_id, id, .unresolved_type);
                key.parameters[index] = arrow.a;
                key.effects[index] = arrow.c;
                ty = arrow.b;
            }
            key.result = ty;
            plan = .{ .callee = .{ .direct = key }, .consumed = body.parameters.len };
        } else {
            plan = .{ .callee = .{ .wrapper = .{ .target = target, .ty = ty } }, .consumed = 1 };
            ty = g.representations.store.node(ty).b;
        }
        errdefer plan.deinit(g.allocator);
        _ = resolved_call.arrows(g.allocator, &g.representations.store, ty, arguments.len - plan.consumed, &plan.extra) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.NotFunction => return g.fail(self.unit_id, id, .unresolved_type),
        };
        return plan;
    }
    fn prepareResolver(self: *Emitter, id: core.Id) Error!ResolverPlan {
        std.debug.assert(self.preparing);
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
        const provider = g.representations.store.node(provider_type);
        // Everything the operation selects is prepared before its first
        // instruction, including the resolver expression's.
        return if (metadata.operation == .monad) monad: {
            if (provider.tag != .type_constructor) return g.fail(self.unit_id, id, .type_constructor_required);
            break :monad .monad;
        } else operation: {
            if (provider.tag != .resolver) return g.fail(self.unit_id, id, .invalid_provider);
            break :operation switch (metadata.operation) {
                .forward => .forward,
                .run => .{ .run = try self.prepareIndirect(arguments[0], id) },
                else => .{ .call = try self.prepareResolverCall(id, provider) },
            };
        };
    }
    fn resolverOperation(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const metadata = unit_.resolverInfo(id);
        const arguments = unit_.resolverArguments(id);
        const prepared = self.resolvedPlan(id).resolver;
        try self.expression(metadata.resolver, depth + 1);
        try self.emit(.drop, 0);
        switch (prepared) {
            .monad => try self.emit(.i32_const, 0),
            .forward => try self.expression(arguments[0], depth + 1),
            .run => |arrow| {
                g.evaluator.counters.prepared_indirect_calls += 1;
                const action = try self.capture(arguments[0], depth);
                const signature = try g.closureSignature(arrow.parameter, arrow.result);
                try self.emit(.local_get, action);
                try self.emit(.i32_load, heap.offset(heap.Closure, "environment"));
                try self.emit(.i32_const, 0);
                try self.providerHead();
                try self.emit(.local_get, action);
                try self.emit(.i32_load, heap.offset(heap.Closure, "function"));
                try g.module.emit(self.function_id, ir.callResult(g.layoutRole(arrow.result)));
                try self.emit(.call_indirect, signature);
            },
            .call => |plan| {
                g.evaluator.counters.prepared_resolver_calls += 1;
                g.evaluator.counters.prepared_extra_applications += plan.extra.items.len;
                switch (plan.callee) {
                    .direct => |key| {
                        const function = try g.function(key);
                        for (arguments[0..key.count]) |argument| try self.expression(argument, depth + 1);
                        try self.providerHead();
                        try self.emit(.call, function);
                    },
                    .wrapper => |callable_key| {
                        const wrapper = try g.callable(callable_key);
                        const value = try self.capture(arguments[0], depth);
                        try self.emit(.i32_const, 0);
                        try self.emit(.local_get, value);
                        try self.providerHead();
                        try self.emit(.call, wrapper);
                    },
                }
                try self.applyExtra(arguments[plan.consumed..], plan.extra.items, depth);
            },
        }
    }
    fn selectedDictionaryUse(self: *Emitter, id: core.Id) Error!?core_eval.Session.MethodSelection {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const present = for (source.dictionary_uses) |use| {
            if (use.node == id and use.introduction != 0) break true;
        } else false;
        if (!present) return null;
        var semantic: std.ArrayList(type_evidence.Mapping) = .empty;
        var rows: std.ArrayList(type_evidence.RowMapping) = .empty;
        defer semantic.deinit(g.allocator);
        defer rows.deinit(g.allocator);
        for (self.mappings) |mapping| {
            const actual = g.representations.toEvidence(g.evaluator.evidenceStore(), mapping.layout) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                continue;
            };
            try semantic.append(g.allocator, .{ .variable = mapping.variable, .evidence = actual });
        }
        for (self.row_mappings) |mapping| {
            if (mapping.row == layout.unknown_row) continue;
            const actual = g.representations.rowToEvidence(g.evaluator.evidenceStore(), mapping.row) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                continue;
            };
            try rows.append(g.allocator, .{ .variable = mapping.variable, .evidence = actual });
        }
        const owner = for (g.units, 0..) |unit_, ordinal| {
            if (unit_.unit == self.unit_id) break ordinal;
        } else return g.fail(self.unit_id, id, .unsupported);
        return g.evaluator.dictionaryUse(owner, id, semantic.items, rows.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.evaluationFailure();
    }
    fn referenceLayout(self: *Emitter, id: core.Id) Error!layout.Id {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const reference = source.reference(id);
        if (!g.evaluator.has_implementations) return self.codeLayout(source.typeOf(id), source.span(id));
        if ((reference.unit == 0 or reference.unit == self.unit_id) and source.binding(reference.binding).kind != .global and source.binding(reference.binding).kind != .external) return self.codeLayout(source.typeOf(id), source.span(id));
        const target = try g.normalize(self.unit_id, reference);
        const producer = g.unit(target.unit);
        const selected = for (producer.member_templates) |member| {
            if (member.binding == target.binding) break true;
        } else false;
        if (!selected) return self.codeLayout(source.typeOf(id), source.span(id));
        // Project the complete checked reference signature through the current
        // owned implementation context before choosing its physical wrapper.
        var semantic: std.ArrayList(type_evidence.Mapping) = .empty;
        var rows: std.ArrayList(type_evidence.RowMapping) = .empty;
        defer semantic.deinit(g.allocator);
        defer rows.deinit(g.allocator);
        for (self.mappings) |mapping| {
            if (mapping.instance.decl != 0) continue;
            const actual = g.representations.toEvidence(g.evaluator.evidenceStore(), mapping.layout) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                continue;
            };
            try semantic.append(g.allocator, .{ .variable = mapping.variable, .evidence = actual });
        }
        for (self.row_mappings) |mapping| {
            if (mapping.row == layout.unknown_row) continue;
            const actual = g.representations.rowToEvidence(g.evaluator.evidenceStore(), mapping.row) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                continue;
            };
            try rows.append(g.allocator, .{ .variable = mapping.variable, .evidence = actual });
        }
        const owner = for (g.units, 0..) |unit_, ordinal| {
            if (unit_.unit == self.unit_id) break ordinal;
        } else return g.fail(self.unit_id, id, .unsupported);
        const actual = g.evaluator.projectType(owner, id, source.typeOf(id), semantic.items, rows.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.evaluationFailure();
        if (actual == 0) return g.fail(self.unit_id, id, .unresolved_type);
        return g.representations.fromEvidence(g.evaluator.evidenceStore(), actual) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .unresolved_type);
    }
    fn prepareReference(self: *Emitter, id: core.Id) Error!?core.BindingRef {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const reference = source.reference(id);
        if (reference.unit == 0 or reference.unit == self.unit_id) {
            const kind = source.binding(reference.binding).kind;
            if (kind != .global and kind != .external) {
                if (self.locals.contains(reference.binding)) return null;
                const selected = try self.selectedDictionaryUse(id);
                if (selected) |method| return try g.normalize(self.unit_id, method.target);
                return null;
            }
        }
        const normalized = try g.normalize(self.unit_id, reference);
        if (!g.evaluator.has_implementations) return normalized;
        const ty = try self.referenceLayout(id);
        return try g.selectMemberTemplate(self.unit_id, id, normalized, ty);
    }
    fn emitReference(self: *Emitter, id: core.Id) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const n = unit_.node(id);
        const reference = unit_.reference(id);
        if (reference.unit == 0 or reference.unit == self.unit_id) {
            if (self.privateCursor(reference.binding)) |fields| {
                const cursor = g.representations.store.node(try self.codeLayout(n.ty, unit_.span(id)));
                if (try g.collectionRowWords(cursor.a) == 0) {
                    const address = try self.allocate(@sizeOf(heap.Cursor), .heap(heap.Cursor));
                    inline for (.{ "collection", "index", "leaf", "base" }, 0..) |name, field| {
                        try self.emit(.local_get, address);
                        try self.emit(.local_get, fields.values[field]);
                        try self.emit(.i32_store, heap.offset(heap.Cursor, name));
                    }
                    return self.emit(.local_get, address);
                }
            }
            var view_index = self.row_views.items.len;
            while (view_index != 0) {
                view_index -= 1;
                const view = self.row_views.items[view_index];
                if (view.binding == reference.binding) {
                    const words = try g.rowWords(view.row);
                    if (try g.nestedRow(view.row) != null) {
                        try self.emit(.local_get, view.address);
                        return self.readElement(.i32, 0, words, view.row);
                    }
                    const row = try self.allocateStorage(words * 4, true, .scalar);
                    for (0..words) |word| {
                        const offset: u32 = @intCast(word * 4);
                        try self.emit(.local_get, row);
                        try self.emit(.local_get, view.address);
                        try self.emit(.i32_load, offset);
                        try self.emit(.i32_store, offset);
                    }
                    return self.emit(.local_get, row);
                }
            }

            if (self.computation_values.contains(reference.binding)) {
                const expected = try self.codeLayout(n.ty, unit_.span(id));
                try self.checkComputationABI(reference.binding, expected, id);
            }
            if (self.static_values.get(reference.binding)) |static_value| {
                const ty = try self.codeLayout(n.ty, unit_.span(id));
                if (g.evaluator.valueScalar(static_value)) |value| {
                    try g.emitValue(self.function_id, value);
                } else {
                    const bits = try g.static_data.serialize(g, static_value, ty, 0);
                    const scalar_ = g.representations.store.scalar(ty) orelse .pointer;
                    try g.emitValue(self.function_id, .{ .scalar = scalar_, .bits = bits });
                }
                return;
            }
            if (self.templates.get(reference.binding)) |template| {
                try self.templateValue(try self.templateAt(template, id), try self.codeLayout(n.ty, unit_.span(id)));
                return;
            }
            if (self.instance_locals.get(reference.binding)) |held| {
                const actual = try self.codeLayout(unit_.typeOf(id), unit_.span(id));
                for (held.layouts[0..held.count], held.locals[0..held.count]) |instance, local| {
                    if (instance == actual) return self.emit(.local_get, local);
                }
                return g.fail(self.unit_id, id, .unsupported);
            }
            if (self.body.?.sinks.get(reference.binding)) |initializer| return self.expression(initializer, 0);
            if (self.locals.get(reference.binding)) |local| {
                try self.emit(.local_get, local);
                return;
            }
        }
        const normalized = self.resolvedPlan(id).reference.?;
        if (g.unit(normalized.unit).body(normalized.binding)) |body| {
            if (body.runtime and !body.is_function) {
                try self.emit(.global_get, try g.planning.runtimeGlobal(g, normalized));
                return;
            }
        }
        const representation = g.representations.store.node(try self.referenceLayout(id));
        if (representation.tag == .universal) {
            const target = self.resolvedPlan(id).reference.?;
            try self.descriptor(try g.callable(.{ .target = target, .ty = representation.a, .dictionaries = unit_.types.quantifierGoals(n.ty).len != 0 }), null);
            return;
        }
        if (unit_.types.node(n.ty).tag == .function) {
            const target = self.resolvedPlan(id).reference.?;
            const ty = try self.referenceLayout(id);
            if (g.unit(target.unit).body(target.binding).?.is_function) {
                if (DictionaryOwner.forBinding(g.unit(target.unit), target.binding)) |owner| {
                    if (try self.forwardDictionary(id, g.unit(target.unit), owner, n.ty)) |dictionary| {
                        const environment = try self.allocate(4, .{ .words = &.{.reference} });
                        try self.emit(.local_get, environment);
                        try self.emit(.local_get, dictionary);
                        try self.emit(.i32_store, 0);
                        try self.descriptor(try g.callable(.{ .target = target, .ty = ty, .dictionaries = true, .bound_dictionaries = true, .instance_arguments = try self.scopedCallableInstances(id) }), environment);
                        return;
                    }
                }
                try self.descriptor(try g.callable(.{ .target = target, .ty = ty, .instance_arguments = try self.scopedCallableInstances(id) }), null);
            } else {
                const value = try g.constant(target, ty);
                try g.emitValue(self.function_id, value);
            }
            return;
        }
        const value = try g.constant(self.resolvedPlan(id).reference.?, try self.codeLayout(n.ty, unit_.span(id)));
        try g.emitValue(self.function_id, value);
    }
    /// Only a checked action with no normal result settles an erased result
    /// slot. This chooses its physical zero cancellation result, not source
    /// type evidence or a default for an arbitrary polymorphic value.
    fn bottomArgumentLayout(self: *Emitter, id: core.Id) Error!layout.Id {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const selected = try self.codeLayout(source.typeOf(id), source.span(id));
        const node = source.node(id);
        const action_layout = self.computationAction(selected) orelse return selected;
        var action_node: core.Id = 0;
        if (node.tag == .computation) action_node = node.a else if (node.tag == .call) {
            const call = source.call(id);
            const target = try g.normalize(self.unit_id, call.target);
            const producer = g.unit(target.unit);
            const definition = producer.body(target.binding) orelse return selected;
            if (!definition.is_function or definition.parameters.len != call.arguments.len) return selected;
            const result = producer.node(definition.root);
            if (result.tag != .computation) return selected;
            const action = producer.node(result.a);
            if (action.tag != .reference) return selected;
            const reference = producer.reference(result.a);
            if (reference.unit != 0 and reference.unit != target.unit) return selected;
            for (producer.bodyParameters(definition), call.arguments) |parameter, argument| {
                if (parameter.binding == reference.binding) {
                    action_node = argument;
                    break;
                }
            }
        }
        if (action_node == 0) return selected;
        const arrow = g.representations.store.node(action_layout);
        if (arrow.tag != .function or arrow.b != layout.erased) return selected;
        const action = source.node(action_node);
        if (action.tag != .closure) return selected;
        if (!@import("bottom_result.zig").proves(g.units, self.unit_id, source.closure(action_node).body)) return selected;
        const refined = try g.internLayoutWithEffects(.function, arrow.a, 5, arrow.c, &.{});
        return g.internLayout(.nominal, std.math.maxInt(u32), 5, &.{refined});
    }
    /// Selects a named call's specialization and the closures its further
    /// arguments apply, before emitting any of its instructions.
    fn dictionaryMember(self: *Emitter, id: core.Id, target: core.BindingRef, signature: types.Id) Error!?DictionaryMemberPlan {
        const owner = self.dictionary_owner orelse return null;
        if (self.dictionary_local == null) return null;
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const normalized = try g.normalize(self.unit_id, target);
        const producer = g.unit(normalized.unit);
        const template = for (producer.member_templates) |candidate| {
            if (candidate.binding == normalized.binding) break candidate;
        } else return null;
        var remaining: usize = 65_536;
        var scopes: @import("../check/package_contracts.zig").Context = .{ .types = &source.types, .remaining = &remaining };
        scopes.initialize() catch return g.fail(self.unit_id, id, .unresolved_type);
        owner.enter(source, &scopes) catch return g.fail(self.unit_id, id, .unresolved_type);
        for (0..owner.count(source)) |ordinal| {
            if (remaining == 0) return g.fail(self.unit_id, id, .complexity);
            remaining -= 1;
            const goal = owner.goal(source, ordinal);
            if (goal.kind != .contract or goal.identity.unit != template.contract.unit or goal.identity.decl != template.contract.decl) continue;
            const contract = for (source.contracts) |candidate| {
                if (candidate.identity.unit == goal.identity.unit and candidate.identity.decl == goal.identity.decl) break candidate;
            } else return g.fail(self.unit_id, id, .unresolved_type);
            const application = source.types.node(goal.ty);
            if (application.tag != .product or application.b != contract.parameters.len or contract.variables.len > 128 or contract.row_variables.len != 0) return g.fail(self.unit_id, id, .unsupported);
            const arguments = source.types.list(.{ .start = application.a, .len = application.b });
            var replacements: [128]types.Id = @splat(0);
            var substitution: @import("../check/package_contracts.zig").Principal = .{ .left = &source.types, .right = &source.types, .remaining = &remaining, .views = &scopes, .foreign_views = true };
            for (source.types.list(contract.parameters), arguments) |formal, actual| {
                substitution.substituted(contract.variables, replacements[0..contract.variables.len], formal, actual) catch return g.fail(self.unit_id, id, .unresolved_type);
                for (substitution.witnesses[0..contract.variables.len], 0..) |witness, ordinal_| replacements[ordinal_] = witness;
            }
            for (source.contract_members[contract.members.start..][0..contract.members.len], 0..) |member, member_ordinal| {
                if (member.kind != .value or member.name != template.name) continue;
                substitution.substituted(contract.variables, replacements[0..contract.variables.len], member.root, signature) catch {
                    if (remaining == 0) return g.fail(self.unit_id, id, .complexity);
                    continue;
                };
                const offset = owner.offset(source, ordinal, member_ordinal, &remaining) catch return g.fail(self.unit_id, id, .unresolved_type);
                return .{ .offset = offset, .signature = try self.dictionaryOwnerMemberLayout(id, owner, @intCast(ordinal), member_ordinal) };
            }
        }
        return null;
    }
    fn prepareNamedCall(self: *Emitter, id: core.Id) Error!NamedPlan {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const call = unit_.call(id);
        const previous_origin = g.evaluator.specialization_origin;
        if (self.unit_id == g.evaluator.diagnostic_context.entry) {
            if (previous_origin == null) g.evaluator.specialization_origin = .{ .unit = self.unit_id, .span = unit_.span(id) };
        } else if (!core_eval.callerDependentUse(unit_, id)) {
            g.evaluator.specialization_origin = .{ .unit = self.unit_id, .span = unit_.span(id) };
        }
        defer g.evaluator.specialization_origin = previous_origin;
        var target = call.target;
        const dictionary_member = try self.dictionaryMember(id, target, call.callee_type);
        if (dictionary_member == null and g.evaluator.has_implementations) target = try g.selectMemberTemplate(self.unit_id, id, target, try self.codeLayout(call.callee_type, unit_.span(id)));
        var key = try g.signature(target, call.callee_type, self.unit_id, self.mappings, self.row_mappings, unit_.span(id), false);
        if (try self.prepareSpawnApplication(id)) |spawn| return .{ .call = .{ .key = key }, .spawn = spawn };
        if (dictionary_member != null) {
            // A stored method is a curried value. Its erased declaration's
            // flattened arity cannot delay this application boundary.
            while (key.count > call.arguments.len) {
                key.count -= 1;
                key.result = try g.internLayoutWithEffects(.function, key.parameters[key.count], key.result, key.effects[key.count], &.{});
            }
        }
        var physical: std.ArrayList(Mapping) = .empty;
        defer physical.deinit(g.allocator);
        var rows: std.ArrayList(RowMapping) = .empty;
        defer rows.deinit(g.allocator);
        if (key.result == layout.erased and key.count <= call.arguments.len) for (call.arguments[0..key.count], key.parameters[0..key.count]) |argument, parameter| {
            const action = self.computationAction(parameter) orelse continue;
            if (g.representations.store.node(action).b != layout.erased) continue;
            const actual = try self.bottomArgumentLayout(argument);
            const selected = try self.codeLayout(unit_.typeOf(argument), unit_.span(argument));
            if (actual == selected) continue;
            if (physical.items.len == 0) try physical.appendSlice(g.allocator, self.mappings);
            try g.mapTypeDepth(self.unit_id, &physical, &rows, unit_.typeOf(argument), actual, unit_.span(argument), 0);
        };
        if (physical.items.len != 0) key = try g.signature(target, call.callee_type, self.unit_id, physical.items, self.row_mappings, unit_.span(id), false);
        var plan: resolved_call.Named = .{ .key = key };
        if (plan.key.result == layout.erased) if (g.unit(plan.key.target.unit).body(plan.key.target.binding)) |definition| {
            if (@import("bottom_result.zig").proves(g.units, plan.key.target.unit, definition.root)) plan.key.result = 5;
        };
        errdefer plan.deinit(g.allocator);
        if (plan.key.count > call.arguments.len) return g.fail(self.unit_id, id, .unsupported);
        _ = resolved_call.arrows(g.allocator, &g.representations.store, plan.key.result, call.arguments.len - plan.key.count, &plan.extra) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.NotFunction => return g.fail(self.unit_id, id, .unresolved_type),
        };
        var dictionary_owner: ?DictionaryOwner = null;
        const producer = g.unit(plan.key.target.unit);
        if (dictionary_member == null) {
            if (DictionaryOwner.forBinding(producer, plan.key.target.binding)) |owner| {
                var incomplete = false;
                for (plan.key.parameters[0..plan.key.count]) |parameter| {
                    _ = g.representations.toEvidence(g.evaluator.evidenceStore(), parameter) catch |err| {
                        if (err == error.OutOfMemory) return error.OutOfMemory;
                        incomplete = true;
                        continue;
                    };
                }
                if (incomplete) {
                    plan.key.dictionaries = true;
                    dictionary_owner = owner;
                }
            }
        }
        const decision = try self.prepareDemandCall(plan.key, call.arguments);
        if (g.demand_lowering.enabled and decision.plan == null) for (call.arguments) |argument| {
            if (unit_.node(argument).tag == .suspend_) try g.demandSite(self.unit_id, argument, .stored, decision.reason);
        };
        const evaluated = if (!plan.key.dictionaries and dictionary_member == null) try self.prepareEvaluatedNamed(id) else null;
        return .{ .call = plan, .evaluated = evaluated, .demand = decision.plan, .dictionary_owner = dictionary_owner, .dictionary_member = dictionary_member };
    }
    /// A closure applied through its table entry, typed by the callee.
    fn prepareIndirect(self: *Emitter, callee: core.Id, id: core.Id) Error!resolved_call.Arrow {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const application = unit_.node(id);
        if (g.demand_lowering.enabled and application.tag == .apply and unit_.node(application.b).tag == .suspend_) {
            var reason: @import("demand_lowering.zig").Reason = .unknown_callee;
            if (@import("known_call.zig").resolve(g.units, self.unit_id, id)) |known| {
                // A known partial application transports the demand into its
                // returned closure. Its pending state escapes this call stage.
                const target = try g.normalize(self.unit_id, known.target);
                if (g.unit(target.unit).body(target.binding)) |body| {
                    if (known.count < body.parameters.len) reason = .escaping_use;
                }
            }
            try g.demandSite(self.unit_id, application.b, .stored, reason);
        }
        var signature_type = unit_.typeOf(callee);
        if (application.c != 0) signature_type = application.c;
        const node = g.representations.store.node(try self.codeLayout(signature_type, unit_.span(id)));
        if (node.tag != .function) return g.fail(self.unit_id, id, .unresolved_type);
        return .{ .parameter = node.a, .result = node.b, .row = node.c };
    }
    fn emitNamedCall(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const call = unit_.call(id);
        const previous_origin = g.evaluator.specialization_origin;
        if (self.unit_id == g.evaluator.diagnostic_context.entry) {
            if (previous_origin == null) g.evaluator.specialization_origin = .{ .unit = self.unit_id, .span = unit_.span(id) };
        } else if (!core_eval.callerDependentUse(unit_, id)) {
            g.evaluator.specialization_origin = .{ .unit = self.unit_id, .span = unit_.span(id) };
        }
        defer g.evaluator.specialization_origin = previous_origin;
        const prepared = self.resolvedPlan(id).named;
        if (prepared.spawn) |spawn| return self.emitSpawnApplication(spawn, depth);
        if (prepared.evaluated) |evaluated| if (try self.emitEvaluatedNamed(evaluated, depth)) return;
        const plan = prepared.call;
        g.evaluator.counters.prepared_named_calls += 1;
        g.evaluator.counters.prepared_extra_applications += plan.extra.items.len;
        var key = plan.key;
        // An affine demand carries the actual construction catalog, so moving
        // it into a task never infers hidden captures from its result type.
        var templates: std.ArrayList(substitution_keys.Entry) = .empty;
        defer templates.deinit(g.allocator);
        for (call.arguments[0..key.count], key.parameters[0..key.count], 0..) |argument, parameter, index| {
            if (g.representations.store.node(parameter).tag != .demand or unit_.node(argument).tag != .suspend_) continue;
            const affine = @import("../check/usage_check.zig").affineNominal(&unit_.types, unit_.nominals, unit_.typeOf(argument)) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, argument, .complexity);
            if (!affine) continue;
            var metadata = self.resolvedPlan(argument).template.metadata;
            metadata.environment = 0;
            metadata.demand_cell = true;
            const body = g.unit(key.target.unit).body(key.target.binding) orelse return g.fail(self.unit_id, id, .unsupported);
            const formal = g.unit(key.target.unit).bodyParameters(body)[index].binding;
            if (templates.items.len == 0) try templates.appendSlice(g.allocator, g.representations.template_keys.get(key.templates));
            try templates.append(g.allocator, .{ .variable = formal, .value = try g.captureTemplate(metadata) });
        }
        if (templates.items.len != 0) key.templates = g.representations.template_keys.intern(templates.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .complexity);
        if (prepared.dictionary_member) |member| {
            var arrows: std.ArrayList(resolved_call.Arrow) = .empty;
            defer arrows.deinit(g.allocator);
            const result = resolved_call.arrows(g.allocator, &g.representations.store, member.signature, call.arguments.len, &arrows) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .unresolved_type);
            try self.emit(.local_get, self.dictionary_local.?);
            try self.emit(.i32_load, @intCast((member.offset - 1) * 4));
            try self.applyExtra(call.arguments, arrows.items, depth);
            const wanted = try self.codeLayout(unit_.typeOf(id), unit_.span(id));
            if (result != wanted) {
                const value = try self.temporary(g.representations.store.machine(result));
                try self.emit(.local_set, value);
                const converted = try self.carrierValue(value, result, wanted, 0);
                try self.emit(.local_get, converted);
            }
            return;
        }
        if (!key.dictionaries) {
            if (try self.inlineCollectionEdit(id, key, depth)) return;
            if (try self.inlineSimdCall(id, key, depth)) return;
            if (try self.inlineDemandCall(key, call.arguments, prepared.demand, depth)) return;
            if (try self.inlineStaticCall(key, call.arguments, depth)) return;
            if (try self.inlineNamedCall(key, call.arguments, depth)) return;
        }
        const function_id = try g.function(key);
        var dictionary: u32 = 0;
        if (key.dictionaries) dictionary = (try self.forwardDictionary(id, g.unit(key.target.unit), prepared.dictionary_owner.?, call.callee_type)) orelse return g.fail(self.unit_id, id, .ambiguous_qualified);
        for (call.arguments[0..key.count]) |argument| try self.expression(argument, depth + 1);
        try self.providerHead();
        if (key.dictionaries) try self.emit(.local_get, dictionary);
        try self.emit(.call, function_id);
        try self.applyExtra(call.arguments[key.count..], plan.extra.items, depth);
    }
    fn prepareTypeComparison(self: *Emitter, id: core.Id) Error!bool {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const n = unit_.node(id);
        const left_type = try self.codeLayout(unit_.typeOf(n.a), unit_.span(n.a));
        const right_type = try self.codeLayout(unit_.typeOf(n.b), unit_.span(n.b));
        var left = left_type;
        var right = right_type;
        while (g.representations.store.node(left).tag == .function) left = g.representations.store.node(left).b;
        while (g.representations.store.node(right).tag == .function) right = g.representations.store.node(right).b;
        const left_evidence = g.representations.toEvidence(g.evaluator.evidenceStore(), left) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .unresolved_type);
        const right_evidence = g.representations.toEvidence(g.evaluator.evidenceStore(), right) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .unresolved_type);
        const abstract_left = g.evaluator.storage.evidence.containsAbstract(left_evidence) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return g.fail(self.unit_id, id, .complexity);
        };
        const abstract_right = g.evaluator.storage.evidence.containsAbstract(right_evidence) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return g.fail(self.unit_id, id, .complexity);
        };
        if (abstract_left or abstract_right) return g.fail(self.unit_id, id, .unresolved_type);
        return left_evidence == right_evidence;
    }
    fn emitTypeComparison(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const n = self.generator.unit(self.unit_id).node(id);
        const equal = self.resolvedPlan(id).comparison;
        try self.expression(n.a, depth + 1);
        try self.emit(.drop, 0);
        try self.expression(n.b, depth + 1);
        try self.emit(.drop, 0);
        try self.emit(.i32_const, @intFromBool(equal));
    }
    fn prepareResultAssociated(self: *Emitter, id: core.Id) Error!CallableKey {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const n = unit_.node(id);
        const expected = try self.codeLayout(n.ty, unit_.span(id));
        const target = try self.memberTarget(id, n.b, expected) orelse return g.failSpecialization(self.unit_id, id, .missing_associated);
        const input = try self.codeLayout(unit_.typeOf(n.a), unit_.span(id));
        const full = try g.internLayout(.function, input, expected, &.{});
        return .{ .target = target, .ty = try self.dispatchCallableLayout(id, full) };
    }
    fn emitResultAssociated(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const n = g.unit(self.unit_id).node(id);
        const wrapper = try g.callable(self.resolvedPlan(id).result_member);
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
        if (!self.exact_probe and g.ragged_probe_limit != 0) if (ragged_builder.analyze(unit_, id, RaggedFacts{ .emitter = self })) |plan| return self.raggedBuilder(id, plan, depth);
        const join = self.resolvedPlan(id).join;
        const checkpoint = self.cleanups.mark();
        defer self.cleanups.restore(checkpoint);
        const resource_scope = self.body.?.has_owners;
        if (resource_scope) try self.openRootScope();
        try self.emit(.block, @backingInt(join.result.?));
        try self.return_targets.append(g.allocator, .{ .node = id, .label = self.labels, .cleanup = checkpoint });
        self.labels += 1;
        var pipeline = if (self.dictionary_owner == null and self.inline_depth < 6) @import("pipeline_builder.zig").analyze(g.units, self.unit_id, id) else null;
        if (pipeline) |plan| {
            var budget: usize = 256;
            for (plan.total[0..plan.total_count]) |value| {
                const previous = g.diagnostic;
                const total = self.pipelineProof(value, &budget) catch |err| switch (err) {
                    error.Declined => declined: {
                        g.diagnostic = previous;
                        break :declined false;
                    },
                    else => return err,
                };
                if (!total) {
                    pipeline = null;
                    break;
                }
            }
        }
        const terminated = if (pipeline) |plan| try self.pipelineSuite(id, plan, depth + 1) else try self.suite(id, depth + 1);
        if (terminated) {
            try self.emit(.unreachable_, 0);
        } else if (join.result.? != .none) {
            try self.emit(if (join.result.? == .f32) .f32_const else .i32_const, 0);
        }
        if (resource_scope and !terminated) try self.cleanupTo(checkpoint);
        self.labels -= 1;
        _ = self.return_targets.pop();
        try self.emit(.end, 0);
        // An exit from an enclosing function can leave this block without
        // targeting its end. Wasm still considers code after `end` reachable;
        // seal a bottom-typed block so its caller need not supply a value.
        if (unit_.types.node(unit_.typeOf(id)).tag == .never) try self.emit(.unreachable_, 0);
    }
    fn pipelineProof(self: *Emitter, value: core.Id, budget: *usize) Error!bool {
        const g = self.generator;
        var probe: Emitter = .{ .generator = g, .unit_id = self.unit_id, .function_id = self.function_id, .provider_local = self.provider_local, .mappings = self.mappings, .row_mappings = self.row_mappings };
        defer probe.deinit();
        var body = try probe.prepareBody(value, 0, false);
        defer body.deinit(g.allocator);
        probe.body = &body;
        probe.mappings = body.mappings;
        probe.row_mappings = body.rows;
        return probe.pipelineTotal(value, budget, 0);
    }
    /// Purity/termination is checked through the exact selected implementation,
    /// including primitive operator methods. Names and generic signatures do
    /// not authorize moving a call across eager collection stages.
    fn pipelineTotal(self: *Emitter, id: core.Id, budget: *usize, depth: usize) Error!bool {
        if (id == 0) return true;
        if (budget.* == 0 or depth >= 8) return false;
        budget.* -= 1;
        const source = self.generator.unit(self.unit_id);
        const n = source.node(id);
        switch (n.tag) {
            .constant => return true,
            .reference => {
                const ref = source.reference(id);
                if (ref.unit != 0 and ref.unit != self.unit_id) return false;
                const kind = source.binding(ref.binding).kind;
                return kind == .parameter or kind == .local;
            },
            .logical => return try self.pipelineTotal(n.a, budget, depth) and try self.pipelineTotal(n.b, budget, depth),
            .if_value => return try self.pipelineTotal(n.a, budget, depth) and try self.pipelineTotal(n.b, budget, depth) and try self.pipelineTotal(n.c, budget, depth),
            .scalar, .associated => {
                if (!try self.pipelineTotal(n.a, budget, depth) or !try self.pipelineTotal(n.b, budget, depth)) return false;
                switch (self.resolvedPlan(id).dispatch) {
                    .scalar => |op| return op != .i32_div_u and op != .i32_rem_u,
                    .selected => |selected| {
                        if (selected.call.extra.items.len != 0 or selected.call.callee != .direct) return false;
                        return self.pipelineNamedTotal(selected.call.callee.direct, budget, depth + 1);
                    },
                    .simd => return false,
                }
            },
            .call => {
                const named = self.resolvedPlan(id).named;
                if (named.dictionary_owner != null or named.dictionary_member != null or named.spawn != null or named.call.extra.items.len != 0) return false;
                for (source.call(id).arguments) |arg| if (!try self.pipelineTotal(arg, budget, depth)) return false;
                return self.pipelineNamedTotal(named.call.key, budget, depth + 1);
            },
            else => return false,
        }
    }
    fn pipelineNamedTotal(self: *Emitter, key: Key, budget: *usize, depth: usize) Error!bool {
        const g = self.generator;
        if (depth >= 8 or budget.* == 0 or key.templates != 0 or key.dictionaries or key.template_result) return false;
        const source = g.unit(key.target.unit);
        const definition = source.body(key.target.binding) orelse return false;
        if (!definition.is_function or definition.parameters.len != key.count) return false;
        var service = try g.specializer();
        var resolved = service.named(key, &.{}) catch |err| return g.specializationFailure(service, err);
        defer resolved.deinit(g.allocator);
        var probe: Emitter = .{ .generator = g, .unit_id = key.target.unit, .function_id = self.function_id, .provider_local = self.provider_local, .mappings = resolved.mappings.items, .row_mappings = resolved.rows.items };
        defer probe.deinit();
        var body = try probe.prepareBody(definition.root, 0, false);
        defer body.deinit(g.allocator);
        probe.body = &body;
        probe.mappings = body.mappings;
        probe.row_mappings = body.rows;
        if (g.artifacts) |artifacts| try artifacts.readInlineBody(key.target);
        return probe.pipelineTotal(definition.root, budget, depth);
    }
    fn pipelineSuite(self: *Emitter, id: core.Id, plan: @import("pipeline_builder.zig").Plan, depth: usize) Error!bool {
        const g = self.generator;
        if (g.artifacts) |artifacts| for (plan.dependencies[0..plan.dependency_count]) |dependency| try artifacts.readInlineBody(dependency);
        const count = try self.capture(plan.count, depth);
        // Oversized inputs execute the original eager stages, including their
        // original failure ordering. Every moved scalar expression is total.
        try self.emit(.local_get, count);
        try self.emit(.i32_const, (std.math.maxInt(u32) - 4) / 4 / @max(1, plan.width));
        try self.emit(.i32_le_u, 0);
        try self.emit(.if_, 0);
        self.labels += 1;
        const total = try self.multiplyLocal(count, plan.width);
        const size = try self.arraySize(total, 4);
        const destination = try self.temporary(.i32);
        try self.emit(.local_get, size);
        try self.allocateArray(true, null);
        try self.emit(.local_set, destination);
        try self.emit(.local_get, destination);
        try self.emit(.local_get, total);
        try self.emit(.i32_store, 0);
        const outer = try self.temporary(.i32);
        const inner = try self.temporary(.i32);
        const offset = try self.temporary(.i32);
        try self.emit(.i32_const, 0);
        try self.emit(.local_set, outer);
        try self.emit(.i32_const, 0);
        try self.emit(.local_set, offset);
        try self.emit(.block, 0);
        try self.emit(.loop, 0);
        self.labels += 2;
        try self.emit(.local_get, outer);
        try self.emit(.local_get, count);
        try self.emit(.i32_ge_u, 0);
        try self.emit(.br_if, 1);
        try self.emit(.i32_const, 0);
        try self.emit(.local_set, inner);
        try self.emit(.block, 0);
        try self.emit(.loop, 0);
        self.labels += 2;
        try self.emit(.local_get, inner);
        try self.emit(.i32_const, plan.width);
        try self.emit(.i32_ge_u, 0);
        try self.emit(.br_if, 1);
        var emitter: Emitter = .{ .generator = g, .unit_id = self.unit_id, .function_id = self.function_id, .provider_local = self.provider_local, .mappings = self.mappings, .row_mappings = self.row_mappings, .cleanups = .{ .parent = &self.cleanups }, .diagnostic_context = try self.inlineContext(), .labels = self.labels, .inline_depth = self.inline_depth + 1, .inline_loop = true };
        defer emitter.deinit();
        var captured = self.locals.iterator();
        while (captured.next()) |entry| try emitter.locals.put(g.allocator, entry.key_ptr.*, entry.value_ptr.*);
        try emitter.locals.put(g.allocator, plan.outer, outer);
        try emitter.locals.put(g.allocator, plan.inner, inner);
        var body = try emitter.prepareBody(plan.value, 0, false);
        defer body.deinit(g.allocator);
        emitter.body = &body;
        emitter.mappings = body.mappings;
        emitter.row_mappings = body.rows;
        try self.arrayAddress(destination, offset, 4);
        try emitter.expression(plan.value, depth + 1);
        try self.storeScalar(if (try emitter.scalar(plan.value) == .f32) .f32_store else .i32_store, 4);
        for ([_]u32{ inner, offset }) |local| {
            try self.emit(.local_get, local);
            try self.emit(.i32_const, 1);
            try self.emit(.i32_add, 0);
            try self.emit(.local_set, local);
        }
        try self.emit(.br, 0);
        self.labels -= 2;
        try self.emit(.end, 0);
        try self.emit(.end, 0);
        try self.emit(.local_get, outer);
        try self.emit(.i32_const, 1);
        try self.emit(.i32_add, 0);
        try self.emit(.local_set, outer);
        try self.emit(.br, 0);
        self.labels -= 2;
        try self.emit(.end, 0);
        try self.emit(.end, 0);
        try self.emit(.local_get, destination);
        try self.save(plan.result, plan.result_source);
        const fused_terminated = try self.suiteSkip(id, depth, 3);
        try self.emit(.else_, 0);
        const ordinary_terminated = try self.suite(id, depth);
        self.labels -= 1;
        try self.emit(.end, 0);
        return fused_terminated and ordinary_terminated;
    }
    fn proofGuard(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const n = source.node(id);
        const Relation = @import("../check/numeric_proof_terms.zig").Relation;
        if (n.c > @backingInt(Relation.index)) return g.fail(self.unit_id, id, .unsupported);
        const relation: Relation = @fromBackingInt(@as(u8, @intCast(n.c)));
        if (try self.numericCheck(id)) {
            try self.expression(n.a, depth + 1);
            try self.emit(.drop, 0);
            try self.expression(n.b, depth + 1);
            try self.emit(.drop, 0);
            return;
        }
        const left = try self.capture(n.a, depth);
        const right = try self.capture(n.b, depth);
        try self.emit(.local_get, left);
        if (relation == .index) {
            try self.emit(.i32_load, 0);
            try self.logicalListLength(try self.codeLayout(source.typeOf(n.a), source.span(n.a)));
        }
        if (relation == .add_fits) try self.emit(.i32_const, std.math.maxInt(u32));
        try self.emit(.local_get, right);
        if (relation == .add_fits) try self.emit(.i32_sub, 0);
        try self.emit(switch (relation) {
            .eq => .i32_ne,
            .lt => .i32_ge_u,
            .le, .add_fits => .i32_gt_u,
            .sub_fits => .i32_lt_u,
            .index => .i32_le_u,
        }, 0);
        try self.emit(.if_, 0);
        try self.emit(.unreachable_, 0);
        try self.emit(.end, 0);
    }
    /// Converts only checked private package boundaries. Abstract leaves own
    /// uniform cells; structured payloads reuse the existing owned layout graph.
    pub fn carrierRows(self: *Emitter, from: u32, to: u32, source: core.Id) Error!void {
        const g = self.generator;
        if (from == layout.unknown_row or to == layout.unknown_row or from >= g.representations.store.effects.rows.items.len or to >= g.representations.store.effects.rows.items.len) return g.fail(self.unit_id, source, .unresolved_type);
        if (from == to) return;
        if (g.representations.store.effects.rows.items[from].formal == 0 and g.representations.store.effects.rows.items[to].formal == 0) return g.fail(self.unit_id, source, .unresolved_type);
        // Exact Source/Core instantiation proves the row correspondence. The
        // adapter forwards the invocation's provider head without widening it.
    }
    fn carrierValue(self: *Emitter, value: u32, from: layout.Id, to: layout.Id, depth: usize) Error!u32 {
        const g = self.generator;
        if (depth >= 128) return g.fail(self.unit_id, 0, .complexity);
        if (from == to) return value;
        const input = g.representations.store.node(from);
        const output = g.representations.store.node(to);
        if (output.tag == .opened or output.tag == .associated) {
            // Each abstract slot already uses the checked typed-carrier ABI.
            // Source/Core owner matching proves its semantic correspondence;
            // lexical depth changes do not change the carrier's physical role.
            if (input.tag == .opened or input.tag == .associated) return value;
            if (input.tag == .erased or input.tag == .invalid or input.tag == .erased_proof or input.tag == .provider or input.tag == .state_provider) return g.fail(self.unit_id, 0, .unsupported);
            const cell = try self.allocate(8, .{ .words = &.{ .scalar, g.layoutRole(from) } });
            try self.emit(.local_get, cell);
            try self.emit(.i32_const, 0);
            try self.emit(.i32_store, 0);
            try self.emit(.local_get, cell);
            try self.emit(.local_get, value);
            var store: wasm.Op = .i32_store;
            if (g.representations.store.machine(from) == .f32) store = .f32_store;
            try self.emit(store, 4);
            return cell;
        }
        if (input.tag == .opened or input.tag == .associated) {
            if (output.tag == .erased or output.tag == .invalid or output.tag == .erased_proof or output.tag == .provider or output.tag == .state_provider) return g.fail(self.unit_id, 0, .unsupported);
            const result = try self.temporary(g.representations.store.machine(to));
            try self.emit(.local_get, value);
            var load: wasm.Op = .i32_load;
            if (g.representations.store.machine(to) == .f32) load = .f32_load;
            try self.emit(load, 4);
            try self.emit(.local_set, result);
            return result;
        }
        if (input.tag == .universal and output.tag == .universal) {
            if (input.b != output.b) return g.fail(self.unit_id, 0, .unresolved_type);
            return self.carrierValue(value, input.a, output.a, depth + 1);
        }
        if (input.tag != output.tag) return g.fail(self.unit_id, 0, .unresolved_type);
        if (input.tag == .owning) {
            if (input.b != output.b or (input.b != @backingInt(types.UsageKind.unique) and input.b != @backingInt(types.UsageKind.shared))) return g.fail(self.unit_id, 0, .unsupported);
            const payload = try self.temporary(g.representations.store.machine(input.a));
            try self.emit(.local_get, value);
            try self.emit(if (g.representations.store.machine(input.a) == .f32) .f32_load else .i32_load, heap.offset(heap.Owning, "payload"));
            try self.emit(.local_set, payload);
            const converted = try self.carrierValue(payload, input.a, output.a, depth + 1);
            const view = try self.allocate(@sizeOf(heap.OwningView), .{ .words = &.{ g.layoutRole(output.a), .scalar, .reference } });
            try self.storeTypedWord(view, heap.offset(heap.OwningView, "payload"), converted, g.representations.store.scalar(output.a) orelse .pointer, 0);
            try self.emit(.local_get, view);
            try self.emit(.i32_const, 0);
            try self.emit(.i32_store, heap.offset(heap.OwningView, "token"));
            try self.storeTypedWord(view, heap.offset(heap.OwningView, "owner"), value, .pointer, 0);
            return view;
        }
        if (input.tag == .array or input.tag == .list) return self.carrierCollection(value, from, to, depth);
        if (input.tag == .nominal) return self.carrierNominal(value, from, to, depth);
        if (input.tag == .product or input.tag == .record) {
            const left = g.representations.store.children(from);
            const right = g.representations.store.children(to);
            if (left.len != right.len) return g.fail(self.unit_id, 0, .unresolved_type);
            var start: usize = 0;
            var step: usize = 1;
            if (input.tag == .record) {
                start = 1;
                step = 2;
            }
            var roles: std.ArrayList(ir.Role) = .empty;
            defer roles.deinit(g.allocator);
            var index = start;
            while (index < right.len) : (index += step) {
                if (start == 1 and left[index - 1] != right[index - 1]) return g.fail(self.unit_id, 0, .unresolved_type);
                try roles.append(g.allocator, g.layoutRole(right[index]));
            }
            const converted_product = try self.allocate(@intCast(roles.items.len * 4), .{ .words = roles.items });
            index = start;
            var slot: u32 = 0;
            while (index < right.len) : (index += step) {
                const field = try self.temporary(g.representations.store.machine(left[index]));
                try self.emit(.local_get, value);
                var load: wasm.Op = .i32_load;
                if (g.representations.store.machine(left[index]) == .f32) load = .f32_load;
                try self.emit(load, slot);
                try self.emit(.local_set, field);
                const converted = try self.carrierValue(field, left[index], right[index], depth + 1);
                try self.emit(.local_get, converted_product);
                try self.emit(.local_get, converted);
                var store: wasm.Op = .i32_store;
                if (g.representations.store.machine(right[index]) == .f32) store = .f32_store;
                try self.emit(store, slot);
                slot += 4;
            }
            return converted_product;
        }
        if (input.tag == .function) {
            // The wrapper closes over one concrete callable. Its argument is
            // converted contravariantly and its result covariantly; the caller's
            // invocation-local provider is passed through unchanged.
            try self.carrierRows(input.c, output.c, 0);
            const adapter = try self.carrierFunction(from, to, depth);
            try self.descriptor(adapter, value);
            const result = try self.temporary(.i32);
            try self.emit(.local_set, result);
            return result;
        }
        return g.fail(self.unit_id, 0, .unsupported);
    }
    pub fn carrierFunction(self: *Emitter, from: layout.Id, to: layout.Id, depth: usize) Error!u32 {
        const g = self.generator;
        const input = g.representations.store.node(from);
        const output = g.representations.store.node(to);
        const key: CarrierKey = .{ .from = from, .to = to };
        var adapter: u32 = undefined;
        if (g.planning.carrier_adapters.get(key)) |known| {
            adapter = known;
        } else {
            const function = try g.module.addTypedFunction(&.{ .i32, g.representations.store.machine(output.a), .i32 }, g.representations.store.machine(output.b), g.layoutRole(output.b));
            try g.setParameterRoles(function, g.closureRoles(output.a), 2);
            try g.planning.carrier_adapters.put(g.allocator, key, function);
            // Layout adapters are private helpers without an independent
            // source job. Exact full replay owns them; fragment reuse must
            // rebuild the enclosing source, as for captured static helpers.
            try g.static_data.closures.append(g.allocator, function);
            var emitter: Emitter = .{ .generator = g, .unit_id = self.unit_id, .function_id = function, .provider_local = 2, .mappings = &.{} };
            defer emitter.deinit();
            const argument = try emitter.carrierValue(1, output.a, input.a, depth + 1);
            try emitter.emit(.local_get, 0);
            try emitter.emit(.i32_load, heap.offset(heap.Closure, "environment"));
            try emitter.emit(.local_get, argument);
            try emitter.emit(.local_get, 2);
            try emitter.emit(.local_get, 0);
            try emitter.emit(.i32_load, heap.offset(heap.Closure, "function"));
            try g.module.emit(function, ir.callResult(g.layoutRole(input.b)));
            try emitter.emit(.call_indirect, try g.closureSignature(input.a, input.b));
            const returned = try emitter.temporary(g.representations.store.machine(input.b));
            try emitter.emit(.local_set, returned);
            const result = try emitter.carrierValue(returned, input.b, output.b, depth + 1);
            try emitter.emit(.local_get, result);
            adapter = function;
        }
        return adapter;
    }
    fn carrierCollection(self: *Emitter, value: u32, from: layout.Id, to: layout.Id, depth: usize) Error!u32 {
        const g = self.generator;
        const input = g.representations.store.node(from);
        const output = g.representations.store.node(to);
        const is_list = input.tag == .list;
        var element_offset: u32 = 4;
        if (is_list) element_offset = 0;
        const input_words = try g.rowWords(input.a);
        const output_words = try g.rowWords(output.a);
        const count = try self.temporary(.i32);
        const index = try self.temporary(.i32);
        const result = try self.temporary(.i32);
        try self.emit(.local_get, value);
        try self.emit(.i32_load, 0);
        try self.logicalListLength(from);
        try self.emit(.local_set, count);
        const scalar_elements = output_words != 0 or g.representations.store.scalar(output.a) != null;
        var physical = count;
        if (is_list and output_words > 1) physical = try self.listWordCount(count, output_words);
        if (is_list) {
            try self.emit(.local_get, physical);
            var scalar_words: u32 = 0;
            if (scalar_elements) scalar_words = @max(1, output_words);
            try self.emit(.i32_const, try self.listKind(scalar_words, output.a));
            try self.emit(.i32_const, @import("../runtime/list_runtime.zig").leafLimit(@max(1, output_words)));
            try self.emit(.call, (try g.module.ensureLists()).new);
        } else {
            const size = try self.arraySize(count, packed_layout.stride(output_words));
            try self.emit(.local_get, size);
            try self.allocateArray(scalar_elements, output.a);
        }
        try self.emit(.local_set, result);
        if (!is_list) {
            try self.emit(.local_get, result);
            try self.emit(.local_get, count);
            try self.emit(.i32_store, 0);
        }
        try self.emit(.i32_const, 0);
        try self.emit(.local_set, index);
        try self.emit(.block, 0);
        try self.emit(.loop, 0);
        self.labels += 2;
        defer self.labels -= 2;
        try self.emit(.local_get, index);
        try self.emit(.local_get, count);
        try self.emit(.i32_ge_u, 0);
        try self.emit(.br_if, 1);
        if (is_list and input_words != 0) {
            try self.readListRow(value, index, input_words, null, null, input.a);
        } else {
            if (is_list) {
                try self.emit(.local_get, value);
                try self.emit(.local_get, index);
                try self.emit(.call, (try g.module.ensureLists()).address);
            } else try self.arrayAddress(value, index, packed_layout.stride(input_words));
            try self.readElement(g.representations.store.machine(input.a), element_offset, input_words, input.a);
        }
        const element = try self.temporary(g.representations.store.machine(input.a));
        try self.emit(.local_set, element);
        const converted = try self.carrierValue(element, input.a, output.a, depth + 1);
        if (is_list and output_words != 0) {
            try self.storeListRow(result, index, converted, output_words, output.a);
        } else {
            if (is_list) {
                try self.emit(.local_get, result);
                try self.emit(.local_get, index);
                try self.emit(.call, (try g.module.ensureLists()).address);
            } else try self.arrayAddress(result, index, packed_layout.stride(output_words));
            try self.emit(.local_get, converted);
            if (output_words != 0) {
                try self.storeElement(g.representations.store.machine(output.a), element_offset, output_words, true, output.a);
            } else try self.storeCollectionWord(result, is_list, g.representations.store.machine(output.a), element_offset);
        }
        try self.emit(.local_get, index);
        try self.emit(.i32_const, 1);
        try self.emit(.i32_add, 0);
        try self.emit(.local_set, index);
        try self.emit(.br, 0);
        try self.emit(.end, 0);
        try self.emit(.end, 0);
        return result;
    }
    fn carrierNominal(self: *Emitter, value: u32, from: layout.Id, to: layout.Id, depth: usize) Error!u32 {
        const g = self.generator;
        const input = g.representations.store.node(from);
        const output = g.representations.store.node(to);
        if (input.a == 0 or input.a > g.units.len or input.a != output.a or input.b != output.b) return g.fail(self.unit_id, 0, .unsupported);
        const source = g.unit(input.a);
        const key: CarrierKey = .{ .from = from, .to = to };
        var adapter: u32 = undefined;
        if (g.planning.carrier_adapters.get(key)) |known| {
            adapter = known;
        } else {
            var is_opaque = false;
            for (source.nominals) |nominal| if (nominal.identity.unit == input.a and nominal.identity.decl == input.b) {
                is_opaque = nominal.is_opaque;
            };
            adapter = try g.module.addTypedFunction(&.{g.representations.store.machine(from)}, g.representations.store.machine(to), g.layoutRole(to));
            try g.setParameterRoles(adapter, ir.packParameterRoles(&.{g.layoutRole(from)}), null);
            // Publish the helper before visiting payloads: recursive nominal
            // edges call the same owned helper instead of expanding the graph.
            try g.planning.carrier_adapters.put(g.allocator, key, adapter);
            try g.static_data.closures.append(g.allocator, adapter);
            var emitter: Emitter = .{ .generator = g, .unit_id = input.a, .function_id = adapter, .mappings = &.{} };
            defer emitter.deinit();
            var found = false;
            for (source.constructors) |constructor| {
                const nominal = source.nominal(constructor.nominal);
                if (nominal.identity.unit != input.a or nominal.identity.decl != input.b) continue;
                found = true;
                if (!is_opaque) {
                    try emitter.emit(.local_get, 0);
                    try emitter.emit(.i32_load, 0);
                    try emitter.emit(.i32_const, constructor.tag);
                    try emitter.emit(.i32_eq, 0);
                    try emitter.emit(.if_, 0);
                    emitter.labels += 1;
                }
                if (constructor.payload == 0) {
                    try emitter.emit(.local_get, 0);
                } else {
                    const family = (@as(u64, input.a) << 32) | input.b;
                    const left = try g.nominalPayload(family, constructor.tag, from);
                    const right = try g.nominalPayload(family, constructor.tag, to);
                    var payload: u32 = 0;
                    if (!is_opaque) {
                        payload = try emitter.temporary(g.representations.store.machine(left));
                        try emitter.emit(.local_get, 0);
                        var load: wasm.Op = .i32_load;
                        if (g.representations.store.machine(left) == .f32) load = .f32_load;
                        try emitter.emit(load, 4);
                        try emitter.emit(.local_set, payload);
                    }
                    const converted = try emitter.carrierValue(payload, left, right, depth + 1);
                    if (is_opaque) {
                        try emitter.emit(.local_get, converted);
                    } else {
                        const envelope = try emitter.allocate(8, .{ .words = &.{ .scalar, g.layoutRole(right) } });
                        try emitter.emit(.local_get, envelope);
                        try emitter.emit(.i32_const, constructor.tag);
                        try emitter.emit(.i32_store, 0);
                        try emitter.emit(.local_get, envelope);
                        try emitter.emit(.local_get, converted);
                        var store: wasm.Op = .i32_store;
                        if (g.representations.store.machine(right) == .f32) store = .f32_store;
                        try emitter.emit(store, 4);
                        try emitter.emit(.local_get, envelope);
                    }
                }
                try emitter.emit(.return_, 0);
                if (!is_opaque) {
                    emitter.labels -= 1;
                    try emitter.emit(.end, 0);
                }
            }
            if (!found) return g.fail(self.unit_id, 0, .unsupported);
            try emitter.emit(.unreachable_, 0);
        }
        const result = try self.temporary(g.representations.store.machine(to));
        try self.emit(.local_get, value);
        try self.emit(.call, adapter);
        try self.emit(.local_set, result);
        return result;
    }
    fn forwardDictionary(self: *Emitter, id: core.Id, producer: *const core.Module, dictionary: DictionaryOwner, signature: types.Id) Error!?u32 {
        const incoming = self.dictionary_local orelse return null;
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const given_owner = self.dictionary_owner orelse return null;
        var remaining: usize = 65_536;
        var scopes: @import("../check/package_contracts.zig").Context = .{ .types = &source.types, .remaining = &remaining };
        scopes.initialize() catch return if (remaining == 0) g.fail(self.unit_id, id, .complexity) else null;
        given_owner.enter(source, &scopes) catch return if (remaining == 0) g.fail(self.unit_id, id, .complexity) else null;
        var instance: @import("../check/package_contracts.zig").Principal = .{ .left = &producer.types, .right = &source.types, .remaining = &remaining, .views = &scopes };
        dictionary.instantiate(producer, &instance, signature) catch return if (remaining == 0) g.fail(self.unit_id, id, .complexity) else null;
        const formals = dictionary.formals(producer);
        const witnesses = instance.witnesses[0..formals.len];
        var values: [128]u32 = undefined;
        var count: usize = 0;
        for (0..dictionary.count(producer)) |goal_ordinal| {
            if (remaining == 0) return g.fail(self.unit_id, id, .complexity);
            remaining -= 1;
            const goal = dictionary.goal(producer, goal_ordinal);
            if (goal.kind != .contract) return null;
            const inputs = producer.types.node(goal.ty);
            if (inputs.tag != .product) return null;
            var selected: ?u32 = null;
            for (0..given_owner.count(source)) |ordinal| {
                if (remaining == 0) return g.fail(self.unit_id, id, .complexity);
                remaining -= 1;
                const given = given_owner.goal(source, ordinal);
                if (given.kind != .contract or given.identity.unit != goal.identity.unit or given.identity.decl != goal.identity.decl) continue;
                const arguments = source.types.node(given.ty);
                if (arguments.tag != .product or arguments.b != inputs.b) continue;
                var matches = true;
                for (producer.types.list(.{ .start = inputs.a, .len = inputs.b }), source.types.list(.{ .start = arguments.a, .len = arguments.b })) |expected, actual| {
                    var comparison: @import("../check/package_contracts.zig").Principal = .{ .left = &producer.types, .right = &source.types, .remaining = &remaining, .views = &scopes };
                    comparison.substituted(formals, witnesses, expected, actual) catch {
                        if (remaining == 0) return g.fail(self.unit_id, id, .complexity);
                        matches = false;
                        break;
                    };
                }
                if (matches) {
                    selected = @intCast(ordinal);
                    break;
                }
            }
            const matched = selected orelse return null;
            const declaration = for (producer.contracts) |contract| {
                if (contract.identity.unit == goal.identity.unit and contract.identity.decl == goal.identity.decl) break contract;
            } else return null;
            for (producer.contract_members[declaration.members.start..][0..declaration.members.len], 0..) |member, ordinal| {
                if (member.kind != .value) continue;
                if (count >= values.len) return g.fail(self.unit_id, id, .complexity);
                const offset = given_owner.offset(source, matched, ordinal, &remaining) catch return g.fail(self.unit_id, id, .unresolved_type);
                const value = try self.temporary(.i32);
                try self.emit(.local_get, incoming);
                try self.emit(.i32_load, @intCast((offset - 1) * 4));
                try self.emit(.local_set, value);
                values[count] = value;
                count += 1;
            }
        }
        const roles: [128]ir.Role = @splat(.reference);
        const vector = try self.allocate(@intCast(@max(count, 1) * 4), .{ .words = roles[0..count] });
        for (values[0..count], 0..) |value, ordinal| {
            try self.emit(.local_get, vector);
            try self.emit(.local_get, value);
            try self.emit(.i32_store, @intCast(ordinal * 4));
        }
        return vector;
    }
    fn universalDictionary(self: *Emitter, id: core.Id, quantifier: types.Id, callee: core.Id) Error!u32 {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const owner = source.types.node(quantifier);
        if (owner.tag != .forall) return g.fail(self.unit_id, id, .unresolved_type);
        const application = source.node(id);
        var selected_type = source.typeOf(callee);
        if (application.tag == .apply and application.c != 0) selected_type = application.c;
        if (try self.forwardDictionary(id, source, .{ .quantified = quantifier }, selected_type)) |vector| return vector;
        var mappings: std.ArrayList(Mapping) = .empty;
        var rows: std.ArrayList(RowMapping) = .empty;
        defer mappings.deinit(g.allocator);
        defer rows.deinit(g.allocator);
        try mappings.appendSlice(g.allocator, self.mappings);
        try rows.appendSlice(g.allocator, self.row_mappings);
        try g.mapTypeDepth(self.unit_id, &mappings, &rows, owner.a, try self.codeLayout(selected_type, source.span(callee)), source.span(id), 0);
        var semantic: std.ArrayList(type_evidence.Mapping) = .empty;
        var semantic_rows: std.ArrayList(type_evidence.RowMapping) = .empty;
        defer semantic.deinit(g.allocator);
        defer semantic_rows.deinit(g.allocator);
        for (mappings.items) |mapping| {
            const actual = g.representations.toEvidence(g.evaluator.evidenceStore(), mapping.layout) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                continue;
            };
            try semantic.append(g.allocator, .{ .variable = mapping.variable, .evidence = actual });
        }
        for (rows.items) |mapping| {
            if (mapping.row == layout.unknown_row) continue;
            const actual = g.representations.rowToEvidence(g.evaluator.evidenceStore(), mapping.row) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                continue;
            };
            try semantic_rows.append(g.allocator, .{ .variable = mapping.variable, .evidence = actual });
        }
        const owner_index = for (g.units, 0..) |unit_, ordinal| {
            if (unit_.unit == self.unit_id) break ordinal;
        } else return g.fail(self.unit_id, id, .unsupported);
        var values: [128]u32 = undefined;
        var count: usize = 0;
        for (source.types.quantifierGoals(quantifier), 0..) |goal, goal_ordinal| {
            if (goal.kind != .contract) return g.fail(self.unit_id, id, .unsupported);
            const contract = for (source.contracts) |candidate| {
                if (candidate.identity.unit == goal.identity.unit and candidate.identity.decl == goal.identity.decl) break candidate;
            } else return g.fail(self.unit_id, id, .unresolved_type);
            for (source.contract_members[contract.members.start..][0..contract.members.len], 0..) |member, member_ordinal| {
                if (member.kind != .value) continue;
                if (count >= values.len) return g.fail(self.unit_id, id, .complexity);
                const selected = g.evaluator.dictionaryMember(owner_index, id, quantifier, @intCast(goal_ordinal), @intCast(member_ordinal), semantic.items, semantic_rows.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.evaluationFailure();
                const actual = g.representations.fromEvidence(g.evaluator.evidenceStore(), selected.signature) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .unresolved_type);
                const value = try self.temporary(.i32);
                try self.descriptor(try g.callable(.{ .target = try g.normalize(self.unit_id, selected.target), .ty = actual }), null);
                try self.emit(.local_set, value);
                const abstract = try self.dictionaryMemberLayout(id, quantifier, @intCast(goal_ordinal), member_ordinal);
                values[count] = try self.carrierValue(value, actual, abstract, 0);
                count += 1;
            }
        }
        const roles: [128]ir.Role = @splat(.reference);
        const vector = try self.allocate(@intCast(@max(count, 1) * 4), .{ .words = roles[0..count] });
        for (values[0..count], 0..) |value, ordinal| {
            try self.emit(.local_get, vector);
            try self.emit(.local_get, value);
            try self.emit(.i32_store, @intCast(ordinal * 4));
        }
        return vector;
    }
    pub fn installUniversalDictionary(self: *Emitter, root: core.Id, dictionary: u32, quantifier: types.Id) Error!void {
        return self.installDictionary(root, dictionary, .{ .quantified = quantifier });
    }
    pub fn installDictionary(self: *Emitter, root: core.Id, dictionary: u32, owner: DictionaryOwner) Error!void {
        self.dictionary_local = dictionary;
        self.dictionary_owner = owner;
        const g = self.generator;
        const source = g.unit(self.unit_id);
        var remaining: usize = 65_536;
        for (source.dictionary_uses) |use| {
            if (remaining == 0) return g.fail(self.unit_id, root, .complexity);
            remaining -= 1;
            if (use.introduction == 0 or use.introduction != root) continue;
            const offset = owner.offset(source, use.goal, use.member, &remaining) catch return g.fail(self.unit_id, root, .unresolved_type);
            const local = try self.temporary(.i32);
            try self.emit(.local_get, dictionary);
            try self.emit(.i32_load, @intCast((offset - 1) * 4));
            try self.emit(.local_set, local);
            try self.locals.put(g.allocator, use.binding, local);
        }
    }
    pub fn dictionaryMemberLayout(self: *Emitter, source_id: core.Id, quantifier: types.Id, goal_ordinal: u32, member_ordinal: usize) Error!layout.Id {
        return self.dictionaryOwnerMemberLayout(source_id, .{ .quantified = quantifier }, goal_ordinal, member_ordinal);
    }
    fn dictionaryOwnerMemberLayout(self: *Emitter, source_id: core.Id, dictionary: DictionaryOwner, goal_ordinal: u32, member_ordinal: usize) Error!layout.Id {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        if (goal_ordinal >= dictionary.count(source)) return g.fail(self.unit_id, source_id, .unresolved_type);
        const goal = dictionary.goal(source, goal_ordinal);
        if (goal.kind != .contract) return g.fail(self.unit_id, source_id, .unsupported);
        const contract = for (source.contracts) |candidate| {
            if (candidate.identity.unit == goal.identity.unit and candidate.identity.decl == goal.identity.decl) break candidate;
        } else return g.fail(self.unit_id, source_id, .unresolved_type);
        const application = source.types.node(goal.ty);
        if (application.tag != .product or application.b != contract.parameters.len or contract.row_variables.len != 0 or member_ordinal >= contract.members.len) return g.fail(self.unit_id, source_id, .unsupported);
        var mappings: std.ArrayList(Mapping) = .empty;
        defer mappings.deinit(g.allocator);
        const formals = dictionary.formals(source);
        try mappings.appendSlice(g.allocator, self.mappings);
        for (source.types.list(formals), 0..) |binder, ordinal| {
            const present = for (self.mappings) |mapping| {
                if (mapping.variable == binder) break true;
            } else false;
            if (!present) try mappings.append(g.allocator, .{ .variable = binder, .layout = try g.internLayout(.opened, @intCast(ordinal), 0, &.{}) });
        }
        const arguments = source.types.list(.{ .start = application.a, .len = application.b });
        for (source.types.list(contract.parameters), arguments) |parameter, argument| {
            const shape = g.representations.store.fromTypeWithRows(source, argument, mappings.items, self.row_mappings, false) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return g.fail(self.unit_id, source_id, .unresolved_type),
            };
            const frontier = mappings.items.len;
            try g.mapTypeDepth(self.unit_id, &mappings, null, parameter, shape, source.span(source_id), 0);
            for (mappings.items[frontier..]) |mapping| {
                if (std.mem.findScalar(types.Id, source.types.list(contract.variables), mapping.variable) == null) return g.fail(self.unit_id, source_id, .unresolved_type);
            }
        }
        const member = source.contract_members[contract.members.start + member_ordinal];
        if (member.kind != .value) return g.fail(self.unit_id, source_id, .unsupported);
        @import("dictionary_layout.zig").bindOwner(g.allocator, source, &g.representations.store, &mappings, dictionary, 0, formals, true) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, source_id, .unresolved_type);
        return g.representations.store.fromTypeWithRows(source, member.root, mappings.items, self.row_mappings, false) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return g.fail(self.unit_id, source_id, .unresolved_type),
        };
    }
    fn packagePack(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        const package = g.representations.store.node(try self.codeLayout(node.ty, source.span(id)));
        if (package.tag != .existential or node.c != package.b) return g.fail(self.unit_id, id, .unresolved_type);
        const payload_type = try self.codeLayout(source.typeOf(node.a), source.span(id));
        const payload = try self.capture(node.a, depth);
        const converted = try self.carrierValue(payload, payload_type, package.a, 0);
        var values: [128]u32 = undefined;
        var roles: [128]ir.Role = undefined;
        values[0] = converted;
        roles[0] = g.layoutRole(package.a);
        var count: usize = 1;
        for (source.dictionary_selections) |selection| {
            if (selection.owner != id) continue;
            for (source.extra[selection.members.start..][0..selection.members.len], 0..) |member, ordinal| {
                if (member == 0) continue;
                if (count == values.len) return g.fail(self.unit_id, id, .complexity);
                const abstract = try self.dictionaryMemberLayout(id, selection.quantifier, selection.goal, ordinal);
                // A concretely specialized forall has no incoming dictionary local.
                // Reconstruct its exact checked given before asking for representation;
                // an associated result alone never selects the implementation.
                var selected: ?core_eval.Session.MethodSelection = null;
                if (source.node(member).tag == .reference) {
                    const reference = source.reference(member);
                    if ((reference.unit == 0 or reference.unit == self.unit_id) and !self.locals.contains(reference.binding)) selected = try self.selectedDictionaryUse(member);
                }
                var actual: layout.Id = undefined;
                var value: u32 = undefined;
                if (selected) |method| {
                    actual = g.representations.fromEvidence(g.evaluator.evidenceStore(), method.signature) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, member, .unresolved_type);
                    value = try self.temporary(.i32);
                    try self.descriptor(try g.callable(.{ .target = try g.normalize(self.unit_id, method.target), .ty = actual }), null);
                    try self.emit(.local_set, value);
                } else {
                    actual = try self.codeLayout(source.typeOf(member), source.span(member));
                    value = try self.capture(member, depth);
                }
                values[count] = try self.carrierValue(value, actual, abstract, 0);
                roles[count] = g.layoutRole(abstract);
                count += 1;
            }
        }
        const envelope = try self.allocate(@intCast(count * 4), .{ .words = roles[0..count] });
        try self.emit(.local_get, envelope);
        try self.emit(.local_get, converted);
        var store: wasm.Op = .i32_store;
        if (g.representations.store.machine(package.a) == .f32) store = .f32_store;
        try self.emit(store, 0);
        for (values[1..count], 1..) |value, ordinal| {
            try self.emit(.local_get, envelope);
            try self.emit(.local_get, value);
            try self.emit(.i32_store, @intCast(ordinal * 4));
        }
        try self.emit(.local_get, envelope);
    }
    fn packageUnpack(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        const package = g.representations.store.node(try self.codeLayout(source.typeOf(node.a), source.span(id)));
        if (package.tag != .existential) return g.fail(self.unit_id, id, .unresolved_type);
        const opening = source.packageOpening(id);
        if (opening.binders.len != package.b) return g.fail(self.unit_id, id, .unresolved_type);
        const carrier = try g.module.addLocal(self.function_id, g.representations.store.machine(package.a));
        const envelope = try self.temporary(.i32);
        try self.expression(node.a, depth + 1);
        try self.emit(.local_set, envelope);
        try self.emit(.local_get, envelope);
        var load: wasm.Op = .i32_load;
        if (g.representations.store.machine(package.a) == .f32) load = .f32_load;
        try self.emit(load, 0);
        try self.emit(.local_set, carrier);
        const previous_value = self.locals.get(node.b);
        try self.locals.put(g.allocator, node.b, carrier);
        defer {
            if (previous_value) |previous| self.locals.getPtr(node.b).?.* = previous else _ = self.locals.remove(node.b);
        }
        var mappings: std.ArrayList(Mapping) = .empty;
        defer mappings.deinit(g.allocator);
        try mappings.appendSlice(g.allocator, self.mappings);
        for (source.types.list(opening.binders), 0..) |binder, ordinal| {
            const leaf = source.types.node(binder);
            if (leaf.tag != .bound or leaf.a != ordinal or leaf.b != 0 or leaf.c != node.b) return g.fail(self.unit_id, id, .unresolved_type);
            try mappings.append(g.allocator, .{ .variable = binder, .layout = try g.internLayout(.opened, @intCast(ordinal), 0, &.{}) });
        }
        @import("dictionary_layout.zig").bind(g.allocator, source, &g.representations.store, &mappings, source.typeOf(node.a), node.b, opening.binders, false) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else g.fail(self.unit_id, id, .unresolved_type);
        const previous_mappings = self.mappings;
        self.mappings = mappings.items;
        defer self.mappings = previous_mappings;
        var installed: std.ArrayList(struct { binding: core.BindingId, previous: ?u32 }) = .empty;
        defer {
            var index = installed.items.len;
            while (index != 0) {
                index -= 1;
                const entry = installed.items[index];
                if (entry.previous) |previous| self.locals.getPtr(entry.binding).?.* = previous else _ = self.locals.remove(entry.binding);
            }
            installed.deinit(g.allocator);
        }
        for (source.dictionary_uses) |use| {
            if (use.opening != node.b) continue;
            const offset = source.dictionaryOffset(use.quantifier, use.goal, use.member) catch return g.fail(self.unit_id, id, .unresolved_type);
            const local = try self.temporary(.i32);
            try self.emit(.local_get, envelope);
            try self.emit(.i32_load, @intCast(offset * 4));
            try self.emit(.local_set, local);
            const previous = self.locals.get(use.binding);
            try installed.append(g.allocator, .{ .binding = use.binding, .previous = previous });
            self.locals.put(g.allocator, use.binding, local) catch |err| {
                _ = installed.pop();
                return err;
            };
        }
        try self.expression(opening.body, depth + 1);
    }
    fn expression(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const previous_semantic = self.semantic_node;
        self.semantic_node = id;
        defer self.semantic_node = previous_semantic;
        if (self.ragged_count) |probe| {
            if (id == probe.plan.storage.initial) {
                var opcode: wasm.Op = .i32_const;
                if (try self.scalar(id) == .f32) opcode = .f32_const;
                return self.emit(opcode, 0);
            }
            try self.emit(.local_get, probe.budget);
            try self.emit(.i32_eqz, 0);
            try self.declineRaggedCount();
            try self.emit(.local_get, probe.budget);
            try self.emit(.i32_const, 1);
            try self.emit(.i32_sub, 0);
            try self.emit(.local_set, probe.budget);
        }
        const previous_root = self.analysis_root;
        if (previous_root == 0) self.analysis_root = id;
        defer self.analysis_root = previous_root;
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        if (depth >= 1024) return g.fail(self.unit_id, id, .complexity);
        const n = unit_.node(id);
        if (n.tag == .reference and unit_.types.node(n.ty).tag == .erased_proof) return;
        if (g.inline_named) if (@import("identity_array.zig").analyze(g.units, self.unit_id, id)) |plan| {
            if (g.artifacts) |artifacts| for (plan.dependencies[0..plan.dependency_count]) |target| try artifacts.readInlineBody(target);
            return self.expression(plan.source, depth + 1);
        };
        switch (n.tag) {
            .resource_acquire => try self.resourceAcquire(id, depth),
            .resource_release => try self.resourceRelease(id, depth),
            .task => try self.task(id, depth),
            .resource_scope => try self.resourceScope(id, depth),
            .usage_borrow => try self.usageBorrow(id, depth),
            .usage_share => try self.expression(n.a, depth + 1),
            .usage_read => {
                const owner = self.resolvedPlan(id).usage_read;
                try self.expression(n.a, depth + 1);
                const storage = g.representations.store.node(try self.codeLayout(unit_.typeOf(n.a), unit_.span(id)));
                if (storage.tag == .owning) try self.emit(if (g.representations.store.machine(storage.a) == .f32) .f32_load else .i32_load, heap.offset(heap.Owning, "payload"));
                if (n.b != 0) try self.emit(.i32_load, 0);
                if (n.b == 2) try self.logicalListLength(owner);
            },
            .staging => try self.emitStaging(id, depth),
            .package_pack => try self.packagePack(id, depth),
            .package_unpack => try self.packageUnpack(id, depth),
            .proof_guard => try self.proofGuard(id, depth),
            .effect_provider, .state_provider => try self.providerValue(id, depth),
            .computation => try self.expression(n.a, depth + 1),
            .effect_scope => try self.effectScope(id, depth),
            .request_decision => try self.requestDecision(id, depth),
            .request_loop => {
                try self.requestLoop(id, depth);
                try self.emit(.i32_const, 0);
            },
            .effect_reflection => return g.fail(self.unit_id, id, .backend_const_only),
            .handle => try self.effectHandle(id, depth),
            .operation_value => {
                const prepared = self.resolvedPlan(id).operation;
                const token = try g.runtimeOperation(prepared.label, self.unit_id, unit_.span(id));
                const operation = unit_.operationValue(id);
                var environment: ?u32 = null;
                if (operation.capability != 0) environment = try self.capture(operation.capability, depth);
                try self.descriptor(try g.operationFunction(.{ .operation = token, .ty = prepared.ty, .scoped = environment != null }), environment);
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
            .constant => {
                var shape = try self.codeLayout(n.ty, unit_.span(id));
                if (g.representations.store.node(shape).tag == .owning) shape = g.representations.store.node(shape).a;
                try self.emit(if (g.representations.store.machine(shape) == .f32) .f32_const else .i32_const, n.a);
            },
            .reference => try self.emitReference(id),
            .scalar, .associated => try self.dispatchScalar(id, depth),
            .logical => try self.emitLogical(id, depth),
            .call => try self.emitNamedCall(id, depth),
            .if_value => {
                const join = self.resolvedPlan(id).join;
                try self.expression(n.a, depth + 1);
                try self.emit(.if_, @backingInt(join.result.?));
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
        if (n.tag == .constant or n.tag == .array or n.tag == .product or n.tag == .record or n.tag == .construct) {
            const shape = g.representations.store.node(try self.codeLayout(n.ty, unit_.span(id)));
            if (shape.tag == .owning) try self.boxOwner(shape.a);
        }
    }
    pub fn boxOwner(self: *Emitter, payload: layout.Id) Error!void {
        const g = self.generator;
        try self.boxOwnerStorage(g.representations.store.machine(payload), g.layoutRole(payload));
    }
    pub fn boxOwnerStorage(self: *Emitter, machine: wasm.ValueType, role: ir.Role) Error!void {
        const value = try self.temporary(machine);
        try self.emit(.local_set, value);
        const box = try self.allocate(@sizeOf(heap.Owning), .{ .words = &.{ role, .scalar } });
        try self.emit(.local_get, box);
        try self.emit(.local_get, value);
        try self.emit(if (machine == .f32) .f32_store else .i32_store, heap.offset(heap.Owning, "payload"));
        try self.emit(.local_get, box);
        try self.emit(.i32_const, 0);
        try self.emit(.i32_store, heap.offset(heap.Owning, "token"));
        try self.emit(.local_get, box);
    }
    fn save(self: *Emitter, binding: core.BindingId, source: core.Id) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        if (binding == 0 or binding >= unit_.bindings.len) return g.fail(self.unit_id, source, .unsupported);
        if (unit_.types.node(unit_.bindings[binding].ty).tag == .erased_proof) return;
        const local = self.locals.get(binding) orelse local: {
            const ty = try g.scalarWithRows(self.unit_id, unit_.binding(binding).ty, self.mappings, self.row_mappings, unit_.span(source));
            const result = try g.module.addLocal(self.function_id, ty.machine());
            try self.locals.put(g.allocator, binding, result);
            break :local result;
        };
        try self.emit(.local_set, local);
        if (self.carryRoot(binding)) |slot| try self.rootDirective(4, slot | (local << 13));
    }
    fn carryRoot(self: *const Emitter, binding: core.BindingId) ?u32 {
        var index = self.loop_targets.items.len;
        while (index != 0) {
            index -= 1;
            for (self.loop_targets.items[index].roots) |root| {
                if (root.iteration == binding or root.outgoing == binding) return root.slot;
            }
        }
        return null;
    }
    fn rootDirective(self: *Emitter, operation: u4, operand: u32) Error!void {
        if (operand > std.math.maxInt(u26)) {
            try self.rootDirective(15, 0);
            return;
        }
        const scope: ir.Ownership = .{ .kind = .scope, .chunk = operation, .roles = @intCast(operand) };
        try self.emit(.ownership, @bitCast(scope));
    }
    fn openRootScope(self: *Emitter) Error!void {
        try self.rootDirective(0, 0);
        try self.cleanups.append(self.generator.allocator, .{ .root_scope = {} });
    }
    fn suite(self: *Emitter, id: core.Id, depth: usize) Error!bool {
        return self.suiteSkip(id, depth, 0);
    }
    fn suiteSkip(self: *Emitter, id: core.Id, depth: usize, skip: usize) Error!bool {
        const previous_root = self.analysis_root;
        if (previous_root == 0) self.analysis_root = id;
        defer self.analysis_root = previous_root;
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        if (depth >= 1024) return g.fail(self.unit_id, id, .complexity);
        for (unit_.children(id)[skip..]) |statement| {
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
                    if (self.body.?.sinks.contains(n.a)) continue;
                    if (self.body.?.entries.contains(statement)) {
                        const plan = self.body.?.get(statement);
                        if (plan == .static_binding) {
                            try self.static_values.put(g.allocator, n.a, plan.static_binding);
                            continue;
                        }
                        if (plan == .instances) {
                            try self.bindInstances(statement, plan.instances, depth);
                            continue;
                        }
                    }
                    if (self.ragged_count) |probe| if (n.a == probe.plan.payload_binding) {
                        var opcode: wasm.Op = .i32_const;
                        if (try self.scalar(n.b) == .f32) opcode = .f32_const;
                        try self.emit(opcode, 0);
                        try self.save(n.a, statement);
                        continue;
                    };

                    if (try self.emitCollectionStep(statement, depth)) continue;
                    if (try self.bindPrivateRow(statement)) continue;
                    if (try self.bindPrivateCursor(statement, depth)) continue;
                    if (self.inlineDemandBinding(n.a) != null) continue;
                    if (self.inline_demands.len != 0 and @import("demand_inline.zig").localClosure(unit_, n.b) != null) continue;
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
                        const ref = unit_.reference(n.b);
                        var view_index = self.row_views.items.len;
                        var borrowed = false;
                        while (view_index != 0) {
                            view_index -= 1;
                            var view = self.row_views.items[view_index];
                            if (view.binding != ref.binding or (ref.unit != 0 and ref.unit != self.unit_id)) continue;
                            view.binding = n.a;
                            try self.row_views.append(g.allocator, view);
                            borrowed = true;
                            break;
                        }
                        if (borrowed) continue;
                    }

                    if (value_node.tag == .reference) {
                        const reference = unit_.reference(n.b);
                        if (reference.unit == 0 or reference.unit == self.unit_id) if (self.templates.get(reference.binding)) |retained| {
                            try self.templates.put(g.allocator, n.a, retained);
                            continue;
                        };
                    }
                    var template = value_node.tag == .closure or value_node.tag == .constructor_function or value_node.tag == .primitive_function;
                    if (value_node.tag == .closure and self.body.?.get(n.b).template.static_key != null) template = false;
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
                    const loop = self.resolvedPlan(statement).loop;
                    try self.loopStatement(loop, depth + 1);
                    if (loop.diverges) {
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
                    if (unit_.types.node(unit_.typeOf(statement)).tag != .erased_proof) try self.emit(.drop, 0);
                },
                .return_ => {
                    const exit = try self.bindExit(self.resolvedPlan(statement).exit);
                    if (exit.template_result) try self.templateExpression(exit.value, depth + 1) else try self.expression(exit.value, depth + 1);
                    try self.takeExit(exit);
                    return true;
                },
                .if_stmt => {
                    const join = self.resolvedPlan(statement).join;
                    const scoped = self.body.?.has_owners;
                    var roots: std.ArrayList(BranchRoot) = .empty;
                    defer roots.deinit(g.allocator);
                    if (scoped) for (join.merges) |merge| {
                        const actual = try self.codeLayout(unit_.binding(merge.result).ty, unit_.span(statement));
                        if (g.layoutRole(actual) != .reference) continue;
                        const slot = try self.temporary(.i32);
                        try self.rootDirective(3, slot);
                        try roots.append(g.allocator, .{ .binding = merge.result, .slot = slot });
                    };
                    try self.expression(n.a, depth + 1);
                    try self.emit(.if_, 0);
                    self.labels += 1;
                    const then_returns = try self.branchSuite(n.b, join, true, roots.items, scoped, depth + 1);
                    var else_returns = false;
                    if (join.else_arm) {
                        try self.emit(.else_, 0);
                        else_returns = try self.branchSuite(n.c, join, false, roots.items, scoped, depth + 1);
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
                    if (unit_.types.node(unit_.typeOf(statement)).tag != .erased_proof) try self.emit(.drop, 0);
                },
            }
        }
        return false;
    }
    const BranchRoot = struct { binding: u32, slot: u32 };
    fn branchSuite(self: *Emitter, source: core.Id, join: resolved_flow.Join, left: bool, roots: []const BranchRoot, scoped: bool, depth: usize) Error!bool {
        const checkpoint = self.cleanups.mark();
        defer self.cleanups.restore(checkpoint);
        if (scoped) try self.openRootScope();
        var terminated = false;
        if (source != 0) terminated = try self.suite(source, depth);
        if (!terminated) {
            try self.mergeBranch(join, left);
            // Merge slots belong to the outer frame. Publish every result
            // before closing the branch's temporary owners.
            for (roots) |root| try self.rootDirective(4, root.slot | (self.locals.get(root.binding).? << 13));
            if (scoped) try self.cleanupTo(checkpoint);
        }
        return terminated;
    }
    fn loopListDirectory(self: *Emitter, source: u32, end: u32) Error!ListDirectory {
        const directory: ListDirectory = .{ .storage = try self.temporary(.i32), .array = try self.temporary(.i32), .offset = try self.temporary(.i32) };
        try self.emit(.i32_const, 0);
        try self.emit(.local_set, directory.storage);
        try self.emit(.i32_const, 0);
        try self.emit(.local_set, directory.offset);
        try self.emit(.local_get, end);
        try self.emit(.if_, 0);
        // Only descriptor/directory edges belong to this holder. Row and carry
        // roots retain their existing, independently checked lifetime paths.
        try self.emit(.local_get, source);
        try self.emit(.call, (try self.generator.module.ensureLists()).directory);
        try self.emit(.local_set, directory.array);
        const storage = try self.allocate(8, .{ .words = &.{ .reference, .reference }, .rest = .scalar });
        try self.emit(.local_get, storage);
        try self.emit(.local_get, source);
        try self.storeCollectionWord(storage, false, .i32, 0);
        try self.emit(.local_get, storage);
        try self.emit(.local_get, directory.array);
        try self.storeCollectionWord(storage, false, .i32, 4);
        try self.emit(.local_get, storage);
        try self.emit(.local_set, directory.storage);
        try self.emit(.end, 0);
        try self.cleanups.append(self.generator.allocator, .{ .release_if_nonzero = @fromBackingInt(@intCast(directory.storage)) });
        return directory;
    }
    fn loopListWalk(self: *Emitter, source: u32, end: u32, span: ?[3]u32) Error!?list_traversal.Walk {
        const leaf = span orelse return null;
        const arena = try self.generator.module.ensureArena();
        try self.openRootScope();
        const walk: list_traversal.Walk = .{ .storage = try self.temporary(.i32), .top = try self.temporary(.i32), .limit = try self.temporary(.i32), .node = try self.temporary(.i32) };
        try self.emit(.i32_const, 0);
        try self.emit(.local_set, walk.storage);
        try self.emit(.local_get, end);
        try self.emit(.if_, 0);
        // One descriptor word and at most height + 1 pending subtrees. A
        // leaf needs only two words, including the initial root entry.
        const size = try self.temporary(.i32);
        try self.emit(.local_get, source);
        try self.emit(.i32_load, heap.offset(heap.ListDescriptor, "root"));
        try self.emit(.local_tee, walk.node);
        try self.emit(.i32_load, heap.offset(heap.ListNode, "height"));
        try self.emit(.local_tee, size);
        try self.emit(.i32_eqz, 0);
        try self.emit(.if_, 0);
        // A single leaf needs no pending subtree storage. The checked source
        // descriptor stays rooted until this traversal's exits retire its scope.
        try self.rootDirective(5, source);
        try self.emit(.local_get, walk.node);
        try self.emit(.local_set, leaf[0]);
        try self.emit(.i32_const, 0);
        try self.emit(.local_set, leaf[1]);
        try self.emit(.local_get, walk.node);
        try self.emit(.i32_load, heap.offset(heap.ListNode, "length"));
        try self.emit(.local_set, leaf[2]);
        try self.emit(.else_, 0);
        try self.emit(.local_get, size);
        try self.emit(.i32_const, list_traversal.capacity - 1);
        try self.emit(.i32_gt_u, 0);
        try self.emit(.if_, 0);
        try self.emit(.unreachable_, 0);
        try self.emit(.end, 0);
        try self.emit(.local_get, size);
        try self.emit(.i32_const, 2);
        try self.emit(.i32_add, 0);
        try self.emit(.i32_const, 4);
        try self.emit(.i32_mul, 0);
        try self.emit(.local_set, size);
        // The descriptor owns the tree; later path words borrow its nodes.
        const storage = try self.temporary(.i32);
        try self.emit(.local_get, size);
        try self.emit(.i32_const, 1);
        try self.emit(.call, arena.allocate_typed);
        try self.emit(.local_set, storage);
        try self.emit(.local_get, storage);
        try self.emit(.local_set, walk.storage);
        try list_traversal.initializeSized(&self.generator.module, self.function_id, source, walk, size);
        try self.emit(.end, 0);
        try self.emit(.end, 0);
        try self.cleanups.append(self.generator.allocator, .{ .release_if_nonzero = @fromBackingInt(@intCast(walk.storage)) });
        return walk;
    }
    fn loopRowView(self: *Emitter, id: core.Id, span: ?[3]u32) Error!?RowView {
        var private = self.ragged_count != null;
        if (self.ragged_fill and self.exact_build != null) private = true;
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const loop = source.loopInfo(id);
        if (loop.pattern == 0) return null;
        const pattern = source.pattern(loop.pattern);
        const collection = try self.codeLayout(source.typeOf(loop.first), source.span(loop.first));
        if (span == null and !private and g.representations.store.node(collection).tag != .array) return null;
        const words = try g.collectionRowWords(collection);
        if (words == 0) return null;
        const element = g.representations.store.node(collection).a;
        if (pattern.tag == .bind) {
            if (!private and !try self.readsRow(source, loop.body, pattern.a, element)) return null;
        } else if (pattern.tag == .product) {
            if (try g.nestedRow(element) != null) return null;
            const children = source.patternChildren(loop.pattern);
            if (children.len != words) return null;
            for (children) |child| switch (source.pattern(child).tag) {
                .bind, .wildcard => {},
                else => return null,
            };
        } else return null;
        const view: RowView = .{ .binding = if (pattern.tag == .bind) pattern.a else 0, .row = g.representations.store.node(collection).a, .address = try self.temporary(.i32), .limit_address = try self.temporary(.i32) };
        if (view.binding != 0) try self.row_views.append(g.allocator, view);
        return view;
    }
    fn loadRowView(self: *Emitter, view: RowView, offset: u32, machine: wasm.ValueType) Error!void {
        const words = try self.generator.rowWords(view.row);
        try self.emit(.local_get, view.address);
        if (machine == .f32 and offset / 16 * 4 + 4 <= words) {
            // The checked complete row includes this whole block. Repeated
            // scalar projections share the load; arithmetic stays ordered.
            try self.emit(.v128_load, offset / 16 * 16);
            try self.emit(.f32x4_extract_lane, offset / 4 % 4);
            return;
        }
        try self.emit(if (machine == .f32) .f32_load else .i32_load, offset);
    }
    fn bindRowViewPattern(self: *Emitter, id: core.Id, pattern: core.PatternId, view: RowView) Error!void {
        if (view.binding != 0) return;
        const g = self.generator;
        const source = g.unit(self.unit_id);
        for (source.patternChildren(pattern), 0..) |child, field| {
            const binding = source.pattern(child);
            if (binding.tag == .wildcard) continue;
            const concrete = try self.codeLayout(binding.ty, source.span(id));
            try self.loadRowView(view, @intCast(field * 4), g.representations.store.machine(concrete));
            try self.save(binding.a, id);
        }
    }
    fn loopInputLayout(self: *Emitter, plan: resolved_flow.Loop, first: core.Id) Error!layout.Id {
        if (plan.collection) |collection| return collection.input;
        const source = self.generator.unit(self.unit_id);
        return self.codeLayout(source.typeOf(first), source.span(first));
    }
    fn loopStatement(self: *Emitter, plan: resolved_flow.Loop, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const id = plan.node;
        var metadata = source.loopInfo(id);
        if (plan.collection) |collection| {
            metadata.kind = .array;
            metadata.first = collection.receiver;
            metadata.pattern = collection.pattern;
        }
        const carries = plan.carries;
        if (!plan.roots) try self.rootDirective(15, 0);
        const cleanup_mark = self.cleanups.mark();
        defer self.cleanups.restore(cleanup_mark);
        const view_count = self.row_views.items.len;
        defer self.row_views.shrinkRetainingCapacity(view_count);
        const input = try self.captureLoopInput(plan, metadata, depth);
        var roots: std.ArrayList(CarryRoot) = .empty;
        defer roots.deinit(g.allocator);
        for (carries, 0..) |carry, index| {
            var role = ir.Role.unknown;
            if (plan.roots) role = @fromBackingInt(@as(u2, @truncate(plan.carry_roles >> @intCast(index * 2))));
            if (role == .reference) {
                const slot = try self.temporary(.i32);
                if (slot > 8191) try self.rootDirective(15, 0);
                try self.rootDirective(3, slot);
                try roots.append(g.allocator, .{ .iteration = carry.iteration, .outgoing = carry.outgoing, .slot = slot });
            }
        }
        // Carry slots outlive this traversal's private owner scope.
        var walk_span: ?[3]u32 = null;
        if (input.row_view == null) walk_span = input.list_span;
        const list_walk = try self.loopListWalk(input.array_local, input.end, walk_span);
        const exit_label = self.labels;
        const target_count = self.loop_targets.items.len;
        defer self.loop_targets.shrinkRetainingCapacity(target_count);
        try self.loop_targets.append(g.allocator, .{ .node = id, .label = exit_label, .cleanup = self.cleanups.mark(), .roots = roots.items });
        for (carries) |carry| {
            if (self.privateCursor(carry.incoming)) |value| {
                try self.savePrivateCursor(carry.iteration, value);
                try self.savePrivateCursor(carry.outgoing, value);
                continue;
            }
            const incoming = self.locals.get(carry.incoming) orelse return g.fail(self.unit_id, id, .unsupported);
            try self.emit(.local_get, incoming);
            try self.save(carry.iteration, id);
            // Initialize the exit version before entering the loop, including
            // its zero-iteration path. Backedges and break edges replace it.
            try self.emit(.local_get, incoming);
            try self.save(carry.outgoing, id);
        }
        try self.emit(.block, 0);
        self.labels += 1;
        try self.emit(.loop, 0);
        const head_label = self.labels;
        self.labels += 1;
        if (metadata.kind != .forever) {
            try self.emit(.local_get, input.counter);
            try self.emit(.local_get, input.end);
            try self.emit(.i32_ge_u, 0);
            try self.emit(.br_if, self.labels - 1 - exit_label);
        }
        const outer_cleanup = self.cleanups.mark();
        try self.openRootScope();
        for (carries, 0..) |carry, index| {
            var role = ir.Role.unknown;
            if (plan.roots) role = @fromBackingInt(@as(u2, @truncate(plan.carry_roles >> @intCast(index * 2))));
            if (role == .reference) try self.rootDirective(5, self.locals.get(carry.iteration).?);
        }
        try self.bindLoopElement(plan, metadata, input, list_walk, depth);
        const inner_cleanup = self.cleanups.mark();
        const row_label = self.labels;
        if (input.row_view != null) {
            try self.emit(.loop, 0);
            self.labels += 1;
            try self.openRootScope();
            for (carries, 0..) |carry, index| {
                var role = ir.Role.unknown;
                if (plan.roots) role = @fromBackingInt(@as(u2, @truncate(plan.carry_roles >> @intCast(index * 2))));
                if (role == .reference) try self.rootDirective(5, self.locals.get(carry.iteration).?);
            }
        }
        if (input.borrowed_view) |view| try self.bindRowViewPattern(id, metadata.pattern, view);
        self.loop_targets.items[self.loop_targets.items.len - 1].backedge = .{ .plan = plan, .metadata = metadata, .input = input, .outer_cleanup = outer_cleanup, .inner_cleanup = inner_cleanup, .row_label = row_label, .head_label = head_label };
        var skip: usize = 0;
        if (plan.collection) |collection| {
            try self.locals.put(g.allocator, collection.rest, self.locals.get(collection.iteration).?);
            skip = 2;
        }
        if (!try self.suiteSkip(metadata.body, depth + 1, skip)) {
            try self.commitLoopBackedge(plan, metadata, input, outer_cleanup, inner_cleanup, row_label, head_label, true);
        }
        if (input.row_view != null) {
            self.labels -= 1;
            try self.emit(.end, 0);
        }
        self.labels -= 1;
        try self.emit(.end, 0);
        self.labels -= 1;
        _ = self.loop_targets.pop();
        try self.emit(.end, 0);
        self.cleanups.restore(outer_cleanup);
        try self.cleanupTo(cleanup_mark);
    }
    const LoopInput = struct {
        counter: u32,
        end: u32,
        array_local: u32,
        list_span: ?[3]u32,
        small: ?SmallCollection,
        borrowed_view: ?RowView,
        row_view: ?RowView,
        array_view: ?RowView,
        list_directory: ?ListDirectory,
    };
    fn captureLoopInput(self: *Emitter, plan: resolved_flow.Loop, metadata: core.LoopInfo, depth: usize) Error!LoopInput {
        const g = self.generator;
        const id = plan.node;
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
            if (plan.collection) |collection| {
                array_local = try self.temporary(.i32);
                try self.emit(.local_get, self.locals.get(collection.incoming).?);
                try self.emit(.i32_load, heap.offset(heap.Cursor, "collection"));
                try self.emit(.local_set, array_local);
                // The exact cursor owns this edge; publish its borrowed child
                // before releasing the cursor or allocating traversal storage.
                try self.rootDirective(5, array_local);
            } else if (small == null) array_local = try self.capture(metadata.first, depth);
            counter = try self.temporary(.i32);
            end = try self.temporary(.i32);
            try self.emit(.i32_const, 0);
            try self.emit(.local_set, counter);
            if (small) |values| {
                try self.emit(.i32_const, @intCast(values.len));
            } else {
                try self.emit(.local_get, array_local);
                try self.emit(.i32_load, 0);
                const input = try self.loopInputLayout(plan, metadata.first);
                try self.logicalListLength(input);
            }
            try self.emit(.local_set, end);
            const collection = try self.loopInputLayout(plan, metadata.first);
            if (small == null and g.representations.store.node(collection).tag == .list) {
                list_span = .{ try self.temporary(.i32), try self.temporary(.i32), try self.temporary(.i32) };
                // Initialize explicitly: this source loop may run inside an
                // outer loop, so Wasm's function-entry local zeroing is not enough.
                try self.emit(.i32_const, 0);
                try self.emit(.local_set, list_span.?[2]);
            }
        }
        var borrowed_view: ?RowView = null;
        if (plan.collection == null) borrowed_view = try self.loopRowView(id, list_span);
        var row_view: ?RowView = null;
        var array_view: ?RowView = null;
        if (list_span != null) row_view = borrowed_view else array_view = borrowed_view;
        if (row_view != null) {
            // Complete leaves and the descriptor length use storage words.
            // Share that counter instead of dividing at each leaf boundary.
            counter = list_span.?[2];
            try self.emit(.local_get, array_local);
            try self.emit(.i32_load, 0);
            try self.emit(.local_set, end);
        }
        var list_directory: ?ListDirectory = null;
        if (row_view != null) list_directory = try self.loopListDirectory(array_local, end);
        return .{ .counter = counter, .end = end, .array_local = array_local, .list_span = list_span, .small = small, .borrowed_view = borrowed_view, .row_view = row_view, .array_view = array_view, .list_directory = list_directory };
    }
    fn bindLoopElement(self: *Emitter, plan: resolved_flow.Loop, metadata: core.LoopInfo, input: LoopInput, list_walk: ?list_traversal.Walk, depth: usize) Error!void {
        const g = self.generator;
        const id = plan.node;
        if (input.row_view) |view| {
            const collection = try self.loopInputLayout(plan, metadata.first);
            const words = try g.collectionRowWords(collection);
            try self.readListRowView(words, input.list_span.?, view, input.list_directory.?);
        } else if (input.array_view) |view| {
            const collection = try self.loopInputLayout(plan, metadata.first);
            const words = try g.collectionRowWords(collection);
            try self.arrayAddress(input.array_local, input.counter, packed_layout.stride(words));
            try self.emit(.i32_const, 4);
            try self.emit(.i32_add, 0);
            try self.emit(.local_set, view.address);
        } else if (metadata.pattern != 0) {
            var element = input.counter;
            if (metadata.kind == .array) {
                const array_type = try self.loopInputLayout(plan, metadata.first);
                const machine = g.representations.store.machine(g.representations.store.node(array_type).a);
                element = try self.temporary(machine);
                const is_list = g.representations.store.node(array_type).tag == .list;
                const words = try g.collectionRowWords(array_type);
                if (input.small) |values| {
                    try self.smallCollectionElement(values, input.counter, 0, values.len);
                } else if (input.list_span) |span| {
                    const position = if (words > 1) try self.multiplyLocal(input.counter, words) else input.counter;
                    if (words != 0) {
                        try self.readListSpanRow(input.array_local, position, words, span, list_walk, g.representations.store.node(array_type).a);
                    } else {
                        // Scalar and boxed elements retain one leaf per span.
                        try self.emit(.local_get, position);
                        try self.emit(.local_get, span[2]);
                        try self.emit(.i32_ge_u, 0);
                        try self.emit(.if_, 0);
                        try self.resolveListSpan(input.array_local, position, span, list_walk);
                        try self.emit(.end, 0);
                        try self.emit(.local_get, span[0]);
                        try self.emit(.i32_const, @import("../runtime/list_runtime.zig").header);
                        try self.emit(.i32_add, 0);
                        try self.emit(.local_get, position);
                        try self.emit(.local_get, span[1]);
                        try self.emit(.i32_sub, 0);
                        try self.emit(.i32_const, 4);
                        try self.emit(.i32_mul, 0);
                        try self.emit(.i32_add, 0);
                    }
                } else try self.arrayAddress(input.array_local, input.counter, packed_layout.stride(try g.collectionRowWords(array_type)));
                if (input.small == null and !(is_list and words != 0)) try self.readElement(machine, if (is_list) 0 else 4, try g.collectionRowWords(array_type), g.representations.store.node(array_type).a);
                try self.emit(.local_set, element);
            }
            if (!plan.refutable) {
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
    }
    fn commitLoopBackedge(self: *Emitter, plan: resolved_flow.Loop, metadata: core.LoopInfo, input: LoopInput, outer_cleanup: runtime_cleanup.Mark, inner_cleanup: runtime_cleanup.Mark, row_label: u32, head_label: u32, restore_cleanup: bool) Error!void {
        const g = self.generator;
        const id = plan.node;
        const carries = plan.carries;

        // Push every predecessor before changing any iteration slot.
        for (carries) |carry| {
            if (self.privateCursor(carry.backedge)) |value| {
                for (value.values[0..4]) |field| try self.emit(.local_get, field);
            } else {
                const backedge = self.locals.get(carry.backedge) orelse return g.fail(self.unit_id, id, .unsupported);
                try self.emit(.local_get, backedge);
            }
        }
        var index = carries.len;
        while (index != 0) {
            index -= 1;
            if (self.privateCursor(carries[index].iteration)) |value| {
                var field: usize = 4;
                while (field != 0) {
                    field -= 1;
                    try self.emit(.local_set, value.values[field]);
                }
                try self.emit(.local_get, value.values[0]);
            }
            try self.save(carries[index].iteration, id);
        }
        for (carries) |carry| {
            if (self.privateCursor(carry.iteration)) |value| {
                const outgoing = self.privateCursor(carry.outgoing).?;
                for (value.values[0..4]) |field| try self.emit(.local_get, field);
                var field: usize = 4;
                while (field != 0) {
                    field -= 1;
                    try self.emit(.local_set, outgoing.values[field]);
                }
            }
            try self.emit(.local_get, self.locals.get(carry.iteration).?);
            try self.save(carry.outgoing, id);
        }
        if (input.row_view == null) try self.cleanupTo(outer_cleanup);
        if (metadata.kind != .forever and input.row_view == null) {
            try self.emit(.local_get, input.counter);
            try self.emit(.i32_const, 1);
            try self.emit(.i32_add, 0);
            try self.emit(.local_set, input.counter);
        }
        if (input.row_view) |view| {
            const collection = try self.loopInputLayout(plan, metadata.first);
            const bytes = try g.collectionRowWords(collection) * 4;
            // Row alignment places both addresses on the same stride
            // grid. Compare before advancing: only a following complete
            // row permits pointer addition, including at Wasm32's limit.
            try self.emit(.local_get, view.address);
            try self.emit(.local_get, view.limit_address);
            try self.emit(.i32_lt_u, 0);
            try self.emit(.if_, 0);
            self.labels += 1;
            try self.cleanupTo(inner_cleanup);
            if (restore_cleanup) self.cleanups.restore(inner_cleanup);
            try self.emit(.local_get, view.address);
            try self.emit(.i32_const, bytes);
            try self.emit(.i32_add, 0);
            try self.emit(.local_set, view.address);
            try self.emit(.br, self.labels - 1 - row_label);
            self.labels -= 1;
            try self.emit(.end, 0);
            // No physical one-past address is formed at a leaf boundary.
        }
        if (input.row_view != null) try self.cleanupTo(outer_cleanup);
        try self.emit(.br, self.labels - 1 - head_label);
    }

    fn breakStatement(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const symbolic = self.resolvedPlan(id).exit;
        for (symbolic.values) |value| {
            if (self.privateCursorReference(value)) |fields| {
                for (fields.values[0..4]) |field| try self.emit(.local_get, field);
            } else try self.expression(value, depth + 1);
        }
        var index = symbolic.carries.len;
        while (index != 0) {
            index -= 1;
            const destination = if (symbolic.kind == .continue_) symbolic.carries[index].backedge else symbolic.carries[index].outgoing;
            if (self.privateCursor(destination)) |fields| {
                var field: usize = 4;
                while (field != 0) {
                    field -= 1;
                    try self.emit(.local_set, fields.values[field]);
                }
                try self.emit(.local_get, fields.values[0]);
            }
            try self.save(destination, id);
        }
        if (symbolic.kind == .continue_) {
            var target_index = self.loop_targets.items.len;
            while (target_index != 0) {
                target_index -= 1;
                const target = self.loop_targets.items[target_index];
                if (target.node != symbolic.target) continue;
                const backedge = target.backedge orelse return self.generator.fail(self.unit_id, id, .unsupported);
                try self.commitLoopBackedge(backedge.plan, backedge.metadata, backedge.input, backedge.outer_cleanup, backedge.inner_cleanup, backedge.row_label, backedge.head_label, false);
                return;
            }
            return self.generator.fail(self.unit_id, id, .unsupported);
        }
        try self.takeExit(try self.bindExit(symbolic));
    }
    /// Selects the block a `return` (or a request handler's return) leaves,
    /// before any instruction of the edge.
    fn prepareReturn(self: *Emitter, source: core.Id, kind: resolved_flow.Exit.Kind, block: core.Id) Error!resolved_flow.SymbolicExit {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const target = for (self.planned_returns.items) |target| {
            if (target.node == block) break target;
        } else return g.fail(self.unit_id, source, .unsupported);
        const value = if (kind == .return_) g.unit(self.unit_id).node(source).a else 0;
        const role = if (value != 0 and !target.template_result) g.layoutRole(try self.codeLayout(g.unit(self.unit_id).typeOf(value), g.unit(self.unit_id).span(value))) else ir.Role.scalar;
        return .{ .kind = kind, .source = source, .target = block, .template_result = target.template_result, .value = value, .result_role = role };
    }
    /// Selects the loop a `break` leaves and the carries its values replace.
    fn prepareBreak(self: *Emitter, id: core.Id) Error!resolved_flow.SymbolicExit {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const loop = source.node(id).a;
        for (self.planned_loops.items) |target| {
            if (target == loop) break;
        } else return g.fail(self.unit_id, id, .unsupported);
        const carries = if (source.node(loop).tag == .request_loop) source.requestLoopCarries(loop) else source.loopCarries(loop);
        const values = source.breakValues(id);
        if (values.len != carries.len) return g.fail(self.unit_id, id, .unsupported);
        return .{ .kind = if (source.node(id).op == .continue_) .continue_ else .break_, .source = id, .target = loop, .values = values, .carries = carries };
    }
    /// Symbolic edges retain the source target; encoding binds only its
    /// machine label and invocation-local cleanup boundary.
    fn bindExit(self: *Emitter, symbolic: resolved_flow.SymbolicExit) Error!resolved_flow.Exit {
        if (symbolic.kind == .return_ or symbolic.kind == .request_return) {
            for (self.return_targets.items) |target| if (target.node == symbolic.target) return symbolic.bind(target.label, target.cleanup);
        } else {
            for (self.loop_targets.items) |target| if (target.node == symbolic.target) return symbolic.bind(target.label, target.cleanup);
        }
        return self.generator.fail(self.unit_id, symbolic.source, .unsupported);
    }
    /// Discharges the cleanup of every scope the exit leaves, then branches.
    fn takeExit(self: *Emitter, exit: resolved_flow.Exit) Error!void {
        for (self.cleanups.since(exit.cleanup)) |action| {
            if (action != .root_scope) self.generator.evaluator.counters.prepared_exit_cleanups += 1;
        }
        if (exit.result_role == .reference) {
            const result = try self.temporary(.i32);
            try self.emit(.local_set, result);
            // Private providers/request cells can own the selected child.
            // Keep it counted before their cleanup removes that last edge.
            for (self.cleanups.since(exit.cleanup)) |action| switch (action) {
                .release, .release_if_nonzero => {
                    try self.rootDirective(5, result);
                    break;
                },
                else => {},
            };
            try self.cleanups.emitToResult(&self.generator.module, @fromBackingInt(@intCast(self.function_id)), exit.cleanup, result);
            try self.emit(.local_get, result);
        } else try self.cleanupTo(exit.cleanup);
        try self.emit(.br, exit.depthAt(self.labels));
    }
    const JoinKind = enum { value, template, statement, match_statement };
    fn prepareJoin(self: *Emitter, id: core.Id, kind: JoinKind) Error!resolved_flow.Join {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const source = g.unit(self.unit_id);
        if (kind == .value) {
            var result: wasm.ValueType = .none;
            if (source.types.node(source.typeOf(id)).tag != .erased_proof) result = (try self.scalar(id)).machine();
            return .{ .node = id, .result = result, .merges = &.{} };
        }
        return switch (kind) {
            .value => unreachable,
            // A callable template's value is its i32 handle.
            .template => .{ .node = id, .result = .i32, .merges = &.{} },
            .statement => .{ .node = id, .result = null, .merges = source.branchMerges(id), .else_arm = source.node(id).c != 0 or source.branchMerges(id).len != 0 },
            // A statement match's arms leave Unit on its result block.
            .match_statement => .{ .node = id, .result = (try self.scalar(id)).machine(), .merges = source.branchMerges(id) },
        };
    }
    fn prepareMatch(self: *Emitter, id: core.Id) Error!resolved_flow.Match {
        std.debug.assert(self.preparing);
        const source = self.generator.unit(self.unit_id);
        const metadata = source.matchInfo(id);
        const join = try self.prepareJoin(id, if (metadata.statement) .match_statement else .value);
        return .{ .join = join, .inputs = source.matchInputs(id), .arms = source.matchArms(id), .statement = metadata.statement };
    }
    fn prepareLoop(self: *Emitter, body: *Body, id: core.Id, depth: usize) Error!resolved_flow.Loop {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const metadata = source.loopInfo(id);
        const carries = source.loopCarries(id);
        var roots = carries.len <= 32;
        var roles: u64 = 0;
        for (carries, 0..) |carry, index| {
            const role = g.layoutRole(try self.codeLayout(source.binding(carry.iteration).ty, source.span(id)));
            if (role != .scalar and role != .reference) roots = false;
            if (index < 32) roles |= @as(u64, @backingInt(role)) << @intCast(index * 2);
        }
        var plan: resolved_flow.Loop = .{ .node = id, .kind = metadata.kind, .carries = carries, .carry_roles = roles, .roots = roots, .refutable = metadata.pattern != 0 and !plainBindingPattern(source, metadata.pattern, 0), .diverges = metadata.kind == .forever and !metadata.can_exit };
        if (!roots) return plan;
        const proof = @import("collection_iteration.zig");
        const candidate = proof.candidate(source, try g.unitUses(self.unit_id, .{ .flow = true }), id) orelse return plan;
        if (!body.entries.contains(candidate.iter)) return plan;
        const creation = body.get(candidate.iter);
        if (creation != .projection or creation.projection == null or creation.projection.? != .member) return plan;
        const iter = creation.projection.?.member.direct;
        if (!proof.cursorCreation(g.unit(iter.target.unit), iter.target.binding)) return plan;
        const input = try self.codeLayout(source.typeOf(source.node(candidate.iter).a), source.span(candidate.iter));
        const tag = g.representations.store.node(input).tag;
        if ((tag != .array and tag != .list) or try g.collectionRowWords(input) != 0) return plan;
        try self.prepareNode(body, candidate.next, depth + 1, false);
        const operation = body.get(candidate.next);
        if (operation != .projection or operation.projection == null or operation.projection.? != .member) return plan;
        const next = operation.projection.?.member.direct;
        if (!proof.cursorNext(g.unit(next.target.unit), next.target.binding, source, candidate.constructor)) return plan;
        // The proof reads exact producer bodies. Until their read set has its
        // own artifact law, regenerate this containing code job conservatively.
        if (g.artifacts) |context| context.requireFreshCode();
        plan.kind = .array;
        plan.refutable = !plainBindingPattern(source, candidate.pattern, 0);
        plan.collection = .{ .input = input, .incoming = candidate.incoming, .iteration = candidate.iteration, .rest = candidate.rest, .receiver = candidate.receiver, .pattern = candidate.pattern };
        return plan;
    }
    /// Selects every edge out of a request loop before its first instruction.
    /// Its own exit label is the next one the loop opens.
    fn prepareRequestLoop(self: *Emitter, id: core.Id) Error!resolved_flow.RequestLoop {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const metadata = source.requestLoopInfo(id);
        const exited = try self.prepareReturn(id, .request_return, metadata.return_target);
        const arms = source.requestArms(id);
        const operations = try g.allocator.alloc(type_evidence.Effects.Label, arms.len);
        errdefer g.allocator.free(operations);
        for (arms, operations) |arm, *operation| operation.* = try g.requestLabel(self.unit_id, arm.operation, self.mappings, self.row_mappings, source.span(id));
        return .{
            .node = id,
            .arms = arms,
            .operations = operations,
            .exited = exited,
            // The cleanup mark is bound when the exit scope opens, after the
            // cell and handler frames this loop allocates.
            .broken = .{ .kind = .request_break, .source = id, .target = id, .carries = source.requestLoopCarries(id) },
            .completion_pattern = metadata.completion_pattern,
            .completion_body = metadata.completion_body,
        };
    }
    fn dispatchIdentity(self: *Emitter, concrete: layout.Id) ?types.NominalIdentity {
        const value = self.generator.representations.store.node(concrete);
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
                    const arrow = g.representations.store.node(ty);
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
    /// Splits a selected operator method between its direct parameters (or a
    /// callable wrapper) and the closures applied to the remaining operands.
    fn prepareDispatch(self: *Emitter, id: core.Id, key: Key) Error!resolved_call.Applied {
        const g = self.generator;
        const body = g.unit(key.target.unit).body(key.target.binding) orelse return g.fail(self.unit_id, id, .unsupported);
        // A selected method can return a function before or after consuming both operands.
        const arity = if (body.is_function) body.parameters.len else key.count;
        var plan: resolved_call.Applied = undefined;
        var ty = key.result;
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
            plan = .{ .callee = .{ .direct = direct }, .consumed = arity };
        } else {
            var full = key.result;
            var reverse: usize = key.count;
            while (reverse > 0) {
                reverse -= 1;
                full = try g.internLayoutWithEffects(.function, key.parameters[reverse], full, key.effects[reverse], &.{});
            }
            plan = .{ .callee = .{ .wrapper = .{ .target = key.target, .ty = full } }, .consumed = 1 };
            ty = g.representations.store.node(full).b;
        }
        errdefer plan.deinit(g.allocator);
        _ = resolved_call.arrows(g.allocator, &g.representations.store, ty, 2 - plan.consumed, &plan.extra) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.NotFunction => return g.fail(self.unit_id, id, .unresolved_type),
        };
        return plan;
    }
    fn dispatchCall(self: *Emitter, id: core.Id, key: Key, plan: resolved_call.Applied, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const node = source.node(id);
        const arguments = [_]core.Id{ node.a, node.b };
        g.evaluator.counters.prepared_dispatch_calls += 1;
        g.evaluator.counters.prepared_extra_applications += plan.extra.items.len;
        switch (plan.callee) {
            .direct => |direct| {
                if (direct.count == key.count and try self.inlineNamedCall(direct, arguments[0..direct.count], depth)) return;
                const function = try g.function(direct);
                for (arguments[0..direct.count]) |argument| try self.expression(argument, depth + 1);
                try self.providerHead();
                try self.emit(.call, function);
            },
            .wrapper => |callable_key| {
                const wrapper = try g.callable(callable_key);
                const argument = try self.capture(arguments[0], depth);
                try self.emit(.i32_const, 0);
                try self.emit(.local_get, argument);
                try self.providerHead();
                try self.emit(.call, wrapper);
            },
        }
        try self.applyExtra(arguments[plan.consumed..], plan.extra.items, depth);
    }
    /// Applies each returned closure to its argument through the planned arrow.
    fn applyExtra(self: *Emitter, arguments: []const core.Id, extra: []const resolved_call.Arrow, depth: usize) Error!void {
        const g = self.generator;
        for (arguments, extra) |argument, arrow| {
            const callee = try self.temporary(.i32);
            try self.emit(.local_set, callee);
            const value = try self.capture(argument, depth);
            try self.emit(.local_get, callee);
            try self.emit(.i32_load, heap.offset(heap.Closure, "environment"));
            if (g.representations.store.node(arrow.parameter).tag != .erased_proof) try self.emit(.local_get, value);
            try self.providerHead();
            try self.emit(.local_get, callee);
            try self.emit(.i32_load, heap.offset(heap.Closure, "function"));
            try self.generator.module.emit(self.function_id, ir.callResult(g.layoutRole(arrow.result)));
            try self.emit(.call_indirect, try g.closureSignature(arrow.parameter, arrow.result));
        }
    }
    fn resolveDispatch(self: *Emitter, id: core.Id) Error!DispatchPlan {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const value = unit_.node(id);
        if (value.tag == .scalar and (value.c == 0 or value.b == 0)) {
            const input = try self.codeLayout(unit_.typeOf(value.a), unit_.span(id));
            if (g.representations.store.node(input).tag == .product) {
                return .{ .simd = .{ .input = input, .result = try self.codeLayout(value.ty, unit_.span(id)) } };
            }
            const opcode = scalar_ops.opcode(value.op, try self.scalar(value.a)) orelse return g.fail(self.unit_id, id, .unsupported);
            return .{ .scalar = opcode };
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
            return .{ .selected = .{ .key = key, .call = try self.prepareDispatch(id, key) } };
        };
        if (left == right) if (g.representations.store.scalar(left)) |scalar_type| {
            const admitted = scalar_type == .u32 or scalar_type == .f32 or (scalar_type == .bool and (operation == .equal or operation == .not_equal));
            if (admitted) if (scalar_ops.opcode(value.op, scalar_type)) |opcode| {
                const comparison = operation == .equal or operation == .not_equal or operation == .less or operation == .less_equal or operation == .greater or operation == .greater_equal;
                if (result != (if (comparison) types.boolean else left)) return g.fail(self.unit_id, id, .unresolved_type);
                return .{ .scalar = opcode };
            };
        };
        if (self.dispatchIdentity(right)) |identity| if (left_identity == null or left_identity.?.unit != identity.unit or left_identity.?.decl != identity.decl) {
            if (try self.dispatchCandidate(id, identity, operation, member, left, right, result)) |key| {
                return .{ .selected = .{ .key = key, .call = try self.prepareDispatch(id, key) } };
            }
        };
        return g.failSpecialization(self.unit_id, id, .unsupported);
    }
    fn dispatchScalar(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const value = self.generator.unit(self.unit_id).node(id);
        switch (self.resolvedPlan(id).dispatch) {
            .scalar => |opcode| {
                try self.expression(value.a, depth + 1);
                if (value.b != 0) try self.expression(value.b, depth + 1);
                try self.emit(opcode, 0);
            },
            .simd => |plan| try self.simdExpression(id, plan.input, plan.result, depth),
            .selected => |selected| try self.dispatchCall(id, selected.key, selected.call, depth),
        }
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
    fn irrefutableBindingPattern(source: *const core.Module, id: core.PatternId, depth: usize) bool {
        if (depth >= 32) return false;
        const pattern = source.pattern(id);
        return switch (pattern.tag) {
            .bind, .wildcard => true,
            .product => blk: {
                for (source.patternChildren(id)) |child| if (!irrefutableBindingPattern(source, child, depth + 1)) break :blk false;
                break :blk true;
            },
            .record_payload => irrefutableBindingPattern(source, pattern.b, depth + 1),
            .constructor => source.nominal(source.constructor(pattern.a).nominal).is_opaque and (pattern.b == 0 or irrefutableBindingPattern(source, pattern.b, depth + 1)),
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
        const order = if (record.tag == .record) try @import("../check/record_order.zig").destinations(scratch.allocator(), unit_.types, record, &g.representations.store.record_names) else &.{};
        defer scratch.allocator().free(order);
        for (unit_.patternChildren(pattern_id), 0..) |child, index| {
            const child_pattern = unit_.pattern(child);
            const machine = try self.patternMachine(child_pattern.ty, child_pattern.span);
            const local = try g.module.addLocal(self.function_id, machine);
            try self.emit(.local_get, value_local);
            try self.nonzeroLoad(if (machine == .f32) .f32_load else .i32_load, @intCast((if (order.len == 0) index else order[index]) * 4));
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
                    try self.nonzeroLoad(if (machine == .f32) .f32_load else .i32_load, 0);
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
                const metadata = unit_.constructor(p.a);
                if (unit_.nominal(metadata.nominal).is_opaque) {
                    if (p.b != 0) try self.matchPattern(source, p.b, value_local, failure_label, depth + 1);
                    return;
                }
                _ = try g.module.ensureArena();
                try self.emit(.local_get, value_local);
                try self.nonzeroLoad(.i32_load, 0);
                try self.emit(.i32_const, metadata.tag);
                try self.emit(.i32_ne, 0);
                try self.emit(.br_if, self.labels - 1 - failure_label);
                if (p.b != 0) {
                    const payload = unit_.pattern(p.b);
                    const machine = try self.patternMachine(payload.ty, payload.span);
                    const local = try g.module.addLocal(self.function_id, machine);
                    try self.emit(.local_get, value_local);
                    try self.nonzeroLoad(if (machine == .f32) .f32_load else .i32_load, 4);
                    try self.emit(.local_set, local);
                    try self.matchPattern(source, p.b, local, failure_label, depth + 1);
                }
            },
            .invalid => return g.decline(self.unit_id, p.span, .unsupported),
        }
    }
    fn matchPackedProduct(self: *Emitter, source_id: core.Id, pattern_id: core.PatternId, view: RowView, plan: *const NumericPlan, owner: u8, failure: u32, record: types.Node, depth: usize) Error!void {
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const order = if (record.tag == .record) try @import("../check/record_order.zig").destinations(g.allocator, source.types, record, &g.representations.store.record_names) else &.{};
        defer g.allocator.free(order);
        for (source.patternChildren(pattern_id), 0..) |child, index| {
            try self.matchPackedPattern(source_id, child, view, plan, owner, @intCast((if (order.len == 0) index else order[index]) * 4), failure, depth + 1);
        }
    }
    fn matchPackedPattern(self: *Emitter, source_id: core.Id, pattern_id: core.PatternId, view: RowView, plan: *const NumericPlan, parent: ?u8, offset: u32, failure: u32, depth: usize) Error!void {
        if (depth >= 64) return self.generator.fail(self.unit_id, source_id, .complexity);
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const pattern = source.pattern(pattern_id);
        if (pattern.tag == .wildcard) return;
        for (plan.leaves[0..plan.leaf_count]) |leaf| {
            if (leaf.discriminant or parent != leaf.owner or offset != leaf.offset) continue;
            const machine: wasm.ValueType = if (leaf.floating) .f32 else .i32;
            const local = try self.temporary(machine);
            try self.loadRowView(view, @as(u32, leaf.word) * 4, machine);
            try self.emit(.local_set, local);
            return self.matchPattern(source_id, pattern_id, local, failure, depth + 1);
        }
        if (pattern.tag == .bind) {
            const concrete = try self.codeLayout(pattern.ty, pattern.span);
            for (plan.storage[0..plan.storage_count]) |storage| {
                if (storage.parent != parent or storage.offset != offset or storage.layout != concrete) continue;
                const address = try self.temporary(.i32);
                try self.emit(.local_get, view.address);
                try self.emit(.i32_const, @as(u32, storage.word) * 4);
                try self.emit(.i32_add, 0);
                try self.emit(.local_set, address);
                try self.row_views.append(g.allocator, .{ .binding = pattern.a, .row = concrete, .address = address, .limit_address = view.limit_address });
                return;
            }
            return g.fail(self.unit_id, source_id, .unsupported);
        }
        const tag: ?u32 = if (pattern.tag == .constructor) source.constructor(pattern.a).tag else null;
        const owner: u8 = for (plan.storage[0..plan.storage_count], 0..) |storage, index| {
            if (storage.parent == parent and storage.offset == offset and storage.tag == tag) break @intCast(index);
        } else return g.fail(self.unit_id, source_id, .unsupported);
        switch (pattern.tag) {
            .constructor => {
                if (plan.storage[owner].guard) |active| {
                    const guard = plan.guards[active];
                    if (plan.storage[guard.owner].parent == parent and plan.storage[guard.owner].offset == offset) {
                        try self.loadRowView(view, @as(u32, guard.word) * 4, .i32);
                        try self.emit(.i32_const, tag.?);
                        try self.emit(.i32_ne, 0);
                        try self.emit(.br_if, self.labels - 1 - failure);
                    }
                }
                if (pattern.b != 0) try self.matchPackedPattern(source_id, pattern.b, view, plan, owner, 4, failure, depth + 1);
            },
            .product => try self.matchPackedProduct(source_id, pattern_id, view, plan, owner, failure, source.types.node(pattern.ty), depth + 1),
            .record_payload => {
                if (pattern.a == 1) {
                    try self.matchPackedPattern(source_id, pattern.b, view, plan, owner, 0, failure, depth + 1);
                } else if (source.pattern(pattern.b).tag != .wildcard) try self.matchPackedProduct(source_id, pattern.b, view, plan, owner, failure, source.types.node(pattern.ty), depth + 1);
            },
            else => return g.fail(self.unit_id, source_id, .unsupported),
        }
    }
    fn borrowedPattern(self: *Emitter, id: core.PatternId, guard: core.Id, body: core.Id, depth: usize) Error!bool {
        if (id == 0) return true;
        if (depth >= 32) return false;
        const source = self.generator.unit(self.unit_id);
        const pattern = source.pattern(id);
        switch (pattern.tag) {
            .bind => {
                const concrete = try self.codeLayout(pattern.ty, pattern.span);
                if (self.generator.representations.store.scalar(concrete)) |scalar_| if (scalar_ != .pointer) return true;
                if (try self.generator.nestedRow(concrete) == null) return false;
                return try self.readsRow(source, guard, pattern.a, concrete) and try self.readsRow(source, body, pattern.a, concrete);
            },
            .constructor, .record_payload => return self.borrowedPattern(pattern.b, guard, body, depth + 1),
            .product => {
                for (source.patternChildren(id)) |child| if (!try self.borrowedPattern(child, guard, body, depth + 1)) return false;
            },
            else => {},
        }
        return true;
    }
    fn matchExpression(self: *Emitter, id: core.Id, depth: usize) Error!bool {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        if (depth >= 1024) return g.fail(self.unit_id, id, .complexity);
        const plan = self.resolvedPlan(id).match;
        const join = plan.join;
        var storage_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var storage: std.heap.BufferFirstAllocator = .init(&storage_buffer, g.allocator);
        const scratch = storage.allocator();
        var inputs: std.ArrayList(u32) = .empty;
        defer inputs.deinit(scratch);
        try inputs.ensureTotalCapacityPrecise(scratch, @min(plan.inputs.len, 16));
        var borrowed: std.ArrayList(?RowView) = .empty;
        defer borrowed.deinit(scratch);
        for (plan.inputs, 0..) |input, position| {
            var view = self.borrowedRowArgument(input);
            if (view) |candidate| {
                if (try g.nestedRow(candidate.row) == null) view = null;
                for (plan.arms) |arm| for (unit_.armRows(arm)) |row| {
                    const pattern = unit_.rowPatterns(row)[position];
                    if (!row_projection_uses.packedPattern(unit_, pattern, 0) or !try self.borrowedPattern(pattern, arm.guard, arm.body, 0)) view = null;
                };
            }
            try borrowed.append(scratch, view);
            if (view) |candidate| {
                try inputs.append(scratch, candidate.address);
                continue;
            }
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
        try self.emit(.block, @backingInt(join.result.?));
        const result_label = self.labels;
        self.labels += 1;
        var all_terminate = plan.statement;
        for (plan.arms, 0..) |arm, arm_index| {
            try self.emit(.block, 0);
            const next_arm = self.labels;
            self.labels += 1;
            for (unit_.armRows(arm)) |row| {
                const view_count = self.row_views.items.len;
                defer self.row_views.shrinkRetainingCapacity(view_count);
                const patterns = unit_.rowPatterns(row);
                if (patterns.len != inputs.items.len) return g.fail(self.unit_id, id, .unsupported);
                try self.emit(.block, 0);
                const next_row = self.labels;
                self.labels += 1;
                for (patterns, inputs.items, borrowed.items) |pattern_id, local, view| {
                    if (view) |candidate| {
                        const numeric = (try g.nestedRow(candidate.row)).?;
                        try self.matchPackedPattern(id, pattern_id, candidate, &numeric, null, 0, next_row, depth + 1);
                    } else try self.matchPattern(id, pattern_id, local, next_row, depth + 1);
                }
                if (arm.guard != 0) {
                    try self.expression(arm.guard, depth + 1);
                    try self.emit(.i32_eqz, 0);
                    // Alternatives share one selected binding set and guard.
                    // A rejected guard advances to the next source arm.
                    try self.emit(.br_if, self.labels - 1 - next_arm);
                }
                const terminated = if (plan.statement) try self.suite(arm.body, depth + 1) else terminated: {
                    try self.expression(arm.body, depth + 1);
                    break :terminated false;
                };
                all_terminate = all_terminate and terminated;
                if (!terminated) {
                    if (plan.statement) {
                        try self.mergeBranch(join, arm_index == 0);
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
    fn prepareStaticPattern(self: *Emitter, id: core.Id) Error!?[]StaticBinding {
        std.debug.assert(self.preparing);
        const g = self.generator;
        const source = g.unit(self.unit_id);
        const n = source.node(id);
        // Concrete values use ordinary runtime loads. This path retains only
        // a constant whose polymorphic children cannot yet have one layout.
        if (g.representations.store.fromType(source, source.typeOf(n.b), self.mappings)) |ty| {
            if (!self.hasErasedType(ty, 0)) return null;
        } else |err| if (err == error.OutOfMemory) return error.OutOfMemory;
        const value = try self.staticReference(n.b) orelse return null;
        var bindings: std.ArrayList(StaticBinding) = .empty;
        defer bindings.deinit(g.allocator);
        if (!try self.staticPattern(n.a, value, &bindings, 0)) return null;
        return try bindings.toOwnedSlice(g.allocator);
    }
    fn staticPatternBinding(self: *Emitter, id: core.Id) Error!bool {
        const selected = self.resolvedPlan(id);
        if (selected != .pattern) return false;
        const bindings = selected.pattern orelse return false;
        for (bindings) |binding| try self.static_values.put(self.generator.allocator, binding.binding, binding.value);
        return true;
    }
    fn patternBinding(self: *Emitter, id: core.Id, depth: usize) Error!void {
        const g = self.generator;
        const unit_ = g.unit(self.unit_id);
        const n = unit_.node(id);
        if (try self.staticPatternBinding(id)) return;
        const selected = self.resolvedPlan(id);
        if (selected == .collection_step) {
            _ = try self.emitCollectionStep(id, depth);
            return;
        }
        if (selected == .collection_pattern) return;
        if (selected == .private_pattern) if (try self.privateCursorRow(id, selected.private_pattern)) |view| {
            try self.bindRowViewPattern(id, n.a, view);
            return;
        };
        const local = try g.module.addLocal(self.function_id, (try self.scalar(n.b)).machine());
        try self.expression(n.b, depth + 1);
        try self.emit(.local_set, local);
        // An opaque constructor contributes no runtime test. Avoid introducing
        // failure control flow for a fully irrefutable payload: it hides the
        // ordinary record projection from scalar replacement after inlining.
        if (irrefutableBindingPattern(unit_, n.a, 0)) {
            try self.matchPattern(id, n.a, local, self.labels, depth + 1);
            return;
        }
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
    fn mergeBranch(self: *Emitter, join: resolved_flow.Join, left: bool) Error!void {
        const g = self.generator;
        for (join.merges) |merge| {
            const binding = if (left) merge.then_binding else merge.else_binding;
            const local = self.locals.get(binding) orelse return g.fail(self.unit_id, join.node, .unsupported);
            try self.emit(.local_get, local);
            try self.save(merge.result, join.node);
        }
    }
};
