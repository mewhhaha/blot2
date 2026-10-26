//! Pure evaluation over immutable core. A compilation shares one session
//! so producer tracing and global constant values survive every code instance.
const std = @import("std");
const receipt = @import("../reuse/specialization_receipt.zig");
const principal_inputs = @import("../reuse/principal_inputs.zig");
const core = @import("../check/core.zig");
const scalar_ops = @import("../backend/scalar_ops.zig");
const types = @import("../check/types.zig");
const region_arena = @import("region_arena.zig");
const type_evidence = @import("type_evidence.zig");
const implementation_evidence = @import("implementation_evidence.zig");
const checked_types = @import("../check/check.zig");
const code_expectation = @import("../reuse/code_expectation.zig");
const provider_chain = @import("../backend/provider_chain.zig");
const body_recipe = @import("body_recipe.zig");
const principal_type_graph = @import("../reuse/principal_type_graph.zig");
const lexical_capture_inputs = @import("lexical_capture_inputs.zig");
const scope_components = @import("scope_components.zig");
const runtime_identity = @import("../backend/runtime_identity.zig");
const dispatch_explanation = @import("../reuse/dispatch_explanation.zig");
const Allocator = std.mem.Allocator;
const ragged = @import("../backend/ragged_builder.zig");
const ragged_count = @import("eval_ragged_count.zig");
const primitive_operator = @import("../check/primitive_operator.zig");
const collection_growth = @import("eval_collection_growth.zig");
const value_storage = @import("eval_values.zig");
pub const Value = scalar_ops.Value;
pub const ValueId = u32;
const FrozenCapture = struct { slot: u32, value: ValueId };
/// Source interface inquiry owns no values and performs no constant demand.
pub const SourceInterface = struct { evidence: type_evidence.Id = 0, generic: bool = false, pending: usize = 0, selected: bool = true };
pub const StartupDependencies = struct {
    selected: []core.BindingRef,
    complete: bool,
    pub fn deinit(self: *StartupDependencies, allocator: Allocator) void {
        allocator.free(self.selected);
        self.* = undefined;
    }
};
pub const SolvedEvidence = struct {
    types: []type_evidence.Mapping,
    rows: []type_evidence.RowMapping,
    /// Exact source implementations selected in one initializer's type region.
    /// IDs remain in this Session's immutable Core namespace, never an arena.
    selected: []core.BindingRef = &.{},
    pub fn deinit(self: *SolvedEvidence, allocator: Allocator) void {
        allocator.free(self.types);
        allocator.free(self.rows);
        allocator.free(self.selected);
        self.* = undefined;
    }
};
pub const ReceiptJudgment = struct {
    matched: bool = true,
    solved: SolvedEvidence,
    pub fn deinit(self: *ReceiptJudgment, allocator: Allocator) void {
        self.solved.deinit(allocator);
    }
};
/// Optional source-owned principal prepass reuse. Every request has expected
/// semantic evidence zero and empty caller seeds. Omitted facts remain holes.
/// A provider never reuses values or publishes a callable validation proof.
pub const PrincipalProvider = struct {
    context: *anyopaque,
    lookup: *const fn (*anyopaque, core.BindingRef, Options) Allocator.Error!?SolvedEvidence,
    record: *const fn (*anyopaque, core.BindingRef, Options, SolvedEvidence, ?*const principal_inputs.Key) Allocator.Error!void,
};
pub const ValueKind = value_storage.ValueKind;
pub const DemandState = value_storage.DemandState;
pub const Demand = value_storage.Demand;
pub const SourceSuspension = value_storage.SourceSuspension;
pub const ClosureOrigin = value_storage.ClosureOrigin;
pub const ClosureValue = value_storage.ClosureValue;
pub const ValueInfo = value_storage.ValueInfo;
pub const Snapshot = value_storage.Snapshot;
pub const View = value_storage.View;
pub const Error = Allocator.Error || error{ Declined, RequestUnwind };
pub const Options = struct {
    reuse_body_recipes: bool = true,
    reuse_validated_calls: bool = true,
    reuse_lexical_summaries: bool = true,
    max_steps: usize = 1_000_000,
    /// Nested executed compile-time expressions and patterns, across calls.
    /// A structural bound on native recursion, sized to the compile thread.
    max_depth: usize = 65_536,
    /// Nested compile-time function calls; the limit programs meet first.
    max_call_depth: usize = 4096,
    /// Structural evidence depth, independent of the call graph and execution.
    max_type_depth: usize = 256,
    /// Speculative graph discovery and scheduling, per top-level type inquiry.
    /// Exhaustion disables sharing; ordinary inference retains its own bounds.
    max_summary_transitions: usize = 1_000_000,
    max_values: usize = 1_000_000,
    max_children: usize = 4_194_304,
    /// Code generation traces initializer dependencies without executing runtime
    /// globals. Constant reads remain forbidden independently of this option.
    trace_runtime_dependencies: bool = false,
    retain_source_suspensions: bool = false,
};
pub const Code = @import("../check/diagnostic_code.zig").Code;
/// The candidates of a failed dispatch in the order selection considered
/// them. It is plain data so copied and restored diagnostics carry it; its
/// evidence names the failing session's store, so the backend spells it
/// before that session is released.
pub const DispatchRecord = struct {
    pub const Candidate = struct { side: dispatch_explanation.Side, operand: type_evidence.Id, outcome: dispatch_explanation.Outcome };
    pub const Context = struct {
        kind: enum { left_operand, right_operand },
        unit: u32,
        span: core.Span,
    };
    op: types.Operator = .none,
    member: u32 = 0,
    /// Unused slots stay defined so diagnostics compare and copy as values.
    candidates: [3]Candidate = @splat(.{ .side = .left, .operand = 0, .outcome = .no_member }),
    len: u8 = 0,
    contexts: [2]Context = .{
        .{ .kind = .left_operand, .unit = 0, .span = .{ .start = 0, .end = 0 } },
        .{ .kind = .right_operand, .unit = 0, .span = .{ .start = 0, .end = 0 } },
    },
    context_len: u8 = 0,
    pub fn add(self: *DispatchRecord, side: dispatch_explanation.Side, operand: type_evidence.Id, outcome: dispatch_explanation.Outcome) void {
        if (self.len == self.candidates.len) return;
        self.candidates[self.len] = .{ .side = side, .operand = operand, .outcome = outcome };
        self.len += 1;
    }
    pub fn items(self: *const DispatchRecord) []const Candidate {
        return self.candidates[0..self.len];
    }
};
pub const SourceLocation = @import("../check/staging_origins.zig").Location;

/// Source variables are the only positions a caller can substitute.
pub fn callerDependent(source: *const core.Types, ty: types.Id, depth: usize) bool {
    if (ty == 0 or depth >= 256) return false;
    const n = source.node(ty);
    if (n.tag == .function or n.tag == .demand or n.tag == .provider) {
        for (source.rowLabels(n.c)) |label| for (source.operationArguments(label)) |argument| {
            if (callerDependent(source, argument, depth + 1)) return true;
        };
    }
    switch (n.tag) {
        .variable, .bound => return true,
        .usage, .forall => return callerDependent(source, n.a, depth + 1),
        .function, .provider => return callerDependent(source, n.a, depth + 1) or callerDependent(source, n.b, depth + 1),
        .array, .list, .cursor, .demand, .resolver => return callerDependent(source, n.a, depth + 1),
        .state_provider => return callerDependent(source, n.a, depth + 1) or callerDependent(source, n.b, depth + 1) or callerDependent(source, n.c, depth + 1),
        .product => for (source.list(.{ .start = n.a, .len = n.b })) |child| {
            if (callerDependent(source, child, depth + 1)) return true;
        },
        .record => for (0..n.b) |index| {
            if (callerDependent(source, source.recordField(n, index).ty, depth + 1)) return true;
        },
        .nominal => for (source.nominalArguments(n)) |child| {
            if (callerDependent(source, child, depth + 1)) return true;
        },
        else => {},
    }
    return false;
}

pub fn callerDependentUse(module: *const core.Module, id: core.Id) bool {
    const node = module.node(id);
    switch (node.tag) {
        .call => for (module.children(id)) |argument| {
            if (callerDependent(&module.types, module.typeOf(argument), 0)) return true;
        },
        .apply => return callerDependent(&module.types, module.typeOf(node.b), 0),
        .associated, .scalar => return callerDependent(&module.types, module.typeOf(node.a), 0) or callerDependent(&module.types, module.typeOf(node.b), 0),
        .project => return callerDependent(&module.types, module.typeOf(node.a), 0),
        .result_associated => return callerDependent(&module.types, node.ty, 0),
        else => {},
    }
    return false;
}

fn obligationDependent(source: *const core.Types, obligation: core.Obligation) bool {
    if (obligation.kind == .dispatch) return callerDependent(source, obligation.ty, 0) or callerDependent(source, obligation.other, 0);
    if (obligation.kind == .result_dispatch) return callerDependent(source, obligation.result, 0);
    return callerDependent(source, obligation.ty, 0) or callerDependent(source, obligation.other, 0) or callerDependent(source, obligation.result, 0);
}

pub const Diagnostic = struct {
    unit: u32,
    span: core.Span,
    code: Code,
    detail: []const u8 = "",
    /// Tag application has already selected its public source invocation.
    tag_origin: bool = false,
    related: ?SourceLocation = null,
    origins: @import("../check/staging_origins.zig").Trace = .{},
    dispatch: ?DispatchRecord = null,
    implementation_trace: ?@import("implementation_trace.zig").Record = null,
    pub fn message(self: Diagnostic) []const u8 {
        return self.code.message(self.detail);
    }
};
pub const Result = struct { value: ?Value = null, diagnostic: ?Diagnostic = null, steps: usize = 0 };
const State = enum { unseen, evaluating, complete };
const Slot = struct { state: State = .unseen, traced: bool = false, value: ValueId = 0 };
const Target = struct { unit: usize, binding: core.BindingId };
pub const CallProofKey = struct { target: Target, evidence: type_evidence.Id };
const Work = union(enum) {
    binding: Target,
    node: struct { unit: usize, id: core.Id },
    pattern: struct { unit: usize, id: core.PatternId },
};
const Flow = union(enum) { value: ValueId, returning: struct { target: core.Id, value: ValueId }, breaking: struct { target: core.Id, values: core.List, continues: bool = false } };
const Frame = struct {
    staged: ?ValueId = null,
    providers: provider_chain.Head = provider_chain.empty,
    values: std.AutoHashMapUnmanaged(core.BindingId, ValueId) = .empty,
    mappings: std.ArrayList(type_evidence.Mapping) = .empty,
    row_mappings: std.ArrayList(type_evidence.RowMapping) = .empty,
    fn deinit(self: *Frame, allocator: Allocator) void {
        self.values.deinit(allocator);
        self.mappings.deinit(allocator);
        self.row_mappings.deinit(allocator);
    }
};
const RequestCell = struct { state: ValueId, exit: ValueId = 0, status: core.RequestDecisionKind = .reply };
const RequestHandler = struct { callback: ValueId, cell: u32, outer: provider_chain.Head };
const Bound = struct { binding: core.BindingId, value: ValueId, previous: ?ValueId = null };
const FieldKey = struct { family: u64, tag: u32, name: u32 };
const FieldLocation = struct { field: u32, len: u32 };
const ViewKey = value_storage.ViewKey;
const RecordKey = value_storage.RecordKey;
const RecordNames = value_storage.RecordNames;
const unit_value: Value = .{ .scalar = .unit, .bits = 0 };

/// Semantic inputs retained beside a callable template's erased environment.
/// Type IDs belong to `unit`; evidence IDs belong to this Session. Importing
/// this description imports signatures without evaluating their values. The
/// selected instance still collects and solves its complete body separately.
pub const RetainedValue = struct { binding: core.BindingId, evidence: type_evidence.Id };
pub const RetainedCapture = struct {
    /// A live value owned by this exact Session. Such hints are used only by
    /// uncached code refinement and never enter a portable record.
    value: ValueId = 0,
    /// Import an immutable expression signature without evaluating its body.
    /// This retains source effect labels omitted from a partial code shape.
    signature_only: bool = false,
    binding: core.BindingId,
    unit: u32,
    node: core.Id,
    mappings: type_evidence.Id = 0,
    rows: []const type_evidence.RowMapping = &.{},
    values: []const RetainedValue = &.{},
    captures: []const RetainedCapture = &.{},
    computation: bool = false,
};
/// A synchronous representation consumer for an uncached, fully solved region.
/// The solver is borrowed only during this call; its nodes are not evidence and
/// cannot escape the region or enter a semantic receipt.
pub const CodeProjection = struct {
    context: *anyopaque,
    mapping: *const fn (*anyopaque, *types.Store, types.Id, types.Id) (types.Error || error{UnresolvedType})!void,
    instance: ?*const fn (*anyopaque, u32, types.Id) ?types.NominalIdentity = null,
};
pub const ProofStats = struct { proof_published: usize = 0, proof_reused: usize = 0 };
pub const DiagnosticContext = struct { identity: ?runtime_identity.View = null, entry: u32 = 0, prelude: u32 = 0, source_mode: bool = false };
const RaggedRegion = struct {
    owner: usize,
    frame: *Frame,
    plan: ragged.Plan,
    original: ValueId = 0,
    children: []ValueId,
    written: usize = 0,
    published: ?ValueId = null,
    reserved: bool = true,
};
const IndexedRegion = struct {
    owner: usize,
    frame: *Frame,
    original: ValueId,
    children: []ValueId,
    plan: @import("eval_indexed_builder.zig").Plan,
};

/// An immutable source-owned interface with residual body actions and shared
/// callee edges. Each import freshens its binders in the receiving solver.
pub const PrincipalGraph = struct {
    pub const Key = struct { target: Target, source_interface: bool, deferred_member: bool, options: Options };
    const TypeImport = struct { source: types.Id, graph: types.Id };
    const RowImport = struct { source: u32, graph: types.Effects.Id };
    const Action = union(enum) { constraint: u32, alias: u32, function: u32, reference: u32 };
    key: Key,
    leases: usize = 1,
    /// Only source descriptions with no session observations or publications
    /// may cross revisions. A residual theorem is a separate, stronger claim.
    retention_eligible: bool = false,
    allocations: @import("../runtime/memory.zig").TrackedAllocator,
    types: types.Store,
    root: types.Id = 0,
    imports: []TypeImport = &.{},
    rows: []RowImport = &.{},
    requirements: []ClosureRegion.Constraint = &.{},
    constraints: []ClosureRegion.Constraint = &.{},
    aliases: []ClosureRegion.DataAlias = &.{},
    functions: []types.Id = &.{},
    arguments: []core.Id = &.{},
    references: []Target = &.{},
    actions: []Action = &.{},
    source_complete: bool = false,
    dependencies: []core.BindingRef = &.{},
    plain_reads: []receipt.PlainFact = &.{},
    /// Dynamic reads that neither consumer can replay.
    untracked_reads: bool = false,
    /// Collected source scopes outside the target's unit. Principal input
    /// keys compare every module's source image; source receipts do not.
    foreign_sources: bool = false,
    /// The graph builder proved every non-root scope contains only imported
    /// types, never a body, binding or evaluated value. Principal admission
    /// separately requires the complete exact type/semantic catalogs.
    foreign_types_only: bool = false,

    fn nodeCount(self: *const PrincipalGraph) usize {
        return self.types.nodes.items.len + self.types.effects.rows.items.len + self.types.operations.items.len;
    }

    fn edgeCount(self: *const PrincipalGraph) usize {
        var count = self.types.extra.items.len +| self.types.effects.labels.items.len +| self.actions.len +| self.imports.len +| self.rows.len +| self.arguments.len +| self.aliases.len *| 2 +| self.functions.len +| self.references.len +| self.dependencies.len +| self.plain_reads.len;
        for (self.constraints) |constraint| count +|= 5 +| constraint.diagnostic_name.len;
        for (self.requirements) |constraint| count +|= 5 +| constraint.diagnostic_name.len;
        return count;
    }

    fn retain(self: *PrincipalGraph) void {
        std.debug.assert(self.leases != std.math.maxInt(usize));
        self.leases += 1;
    }

    fn deinit(self: *PrincipalGraph, _: Allocator) void {
        std.debug.assert(self.leases != 0);
        self.leases -= 1;
        if (self.leases != 0) return;
        const backing = self.allocations.backing;
        const allocator = self.allocations.allocator();
        for (self.constraints) |constraint| allocator.free(constraint.diagnostic_name);
        for (self.requirements) |constraint| allocator.free(constraint.diagnostic_name);
        allocator.free(self.constraints);
        allocator.free(self.requirements);
        allocator.free(self.imports);
        allocator.free(self.rows);
        allocator.free(self.aliases);
        allocator.free(self.functions);
        allocator.free(self.arguments);
        allocator.free(self.references);
        allocator.free(self.actions);
        allocator.free(self.dependencies);
        allocator.free(self.plain_reads);
        self.types.deinit();
        std.debug.assert(self.allocations.counts.live_bytes == 0);
        backing.destroy(self);
    }
};

/// Borrowed, source-owned graph. The receiving session must acquire its own
/// lease only after its private query table has reserved publication storage.
pub const PrincipalGraphProvider = struct {
    context: *anyopaque,
    lookup: *const fn (*anyopaque, PrincipalGraph.Key) ?*PrincipalGraph,
};

/// A bounded set of immutable source descriptions used by the last successful
/// revision. No solver history, values, mutable memo facts or negative answers
/// are retained here. Unused descriptions disappear at the next publication.
pub const RetainedPrincipalGraphs = struct {
    queries: PrincipalQueries(.source_description) = .{},

    pub fn deinit(self: *RetainedPrincipalGraphs, a: Allocator) void {
        self.queries.deinit(a);
    }

    pub fn capture(self: *RetainedPrincipalGraphs, session: *Session) Allocator.Error!void {
        std.debug.assert(self.queries.count() == 0);
        for (session.specializations.call_summaries.principals.table.records.items) |record| {
            const graph = record.value.graph orelse continue;
            if (!graph.retention_eligible) continue;
            if (!try self.queries.put(session.allocator, graph.key, graph, session)) continue;
            graph.retain();
            session.counters.principal_graph_retained += 1;
            session.counters.principal_graph_retained_bytes += @sizeOf(PrincipalGraph) + graph.allocations.counts.live_bytes;
        }
    }

    /// The supplied gate pairs these exact source pins with current immutable
    /// Core. Body IDs and diagnostic spans require structural correspondence;
    /// interface-only equality is deliberately insufficient for this artifact.
    pub fn lookup(self: *const RetainedPrincipalGraphs, key: PrincipalGraph.Key, gate: anytype) ?*PrincipalGraph {
        if (!gate.admits(.{ .unit = @intCast(key.target.unit + 1), .binding = key.target.binding })) return null;
        const Queries = PrincipalQueries(.source_description);
        var cursor = self.queries.table.candidates(Queries.Adapter.fingerprint(.{ .source = key }), .oldest_first);
        var remaining = self.queries.lookup_budget;
        candidate: while (cursor.next()) |position| {
            if (remaining == 0) return null;
            remaining -= 1;
            const record = self.queries.table.records.items[position];
            if (!std.meta.eql(record.key.source, key)) continue;
            const graph = record.value.graph orelse continue;
            if (!graph.retention_eligible) continue;
            for (graph.dependencies) |source| {
                if (remaining == 0) return null;
                remaining -= 1;
                if (!gate.admits(source)) continue :candidate;
            }
            for (graph.references) |source| {
                if (remaining == 0) return null;
                remaining -= 1;
                if (!gate.admits(.{ .unit = @intCast(source.unit + 1), .binding = source.binding })) continue :candidate;
            }
            return graph;
        }
        return null;
    }
};

const PrincipalClaim = enum { source_description, open_residual };
fn PrincipalQueries(comptime claim: PrincipalClaim) type {
    return struct {
        const Self = @This();
        const StoredGraph = if (claim == .source_description) ?*PrincipalGraph else *PrincipalGraph;
        const QueryKey = struct {
            source: PrincipalGraph.Key,
            claim_: PrincipalClaim = claim,
            forced: bool = false,
            pub fn deinit(_: *QueryKey, _: Allocator) void {}
        };
        const Dependencies = struct {
            sources: []core.BindingRef,
            plain: []receipt.PlainFact,
            has_writes: bool = false,
            pub fn deinit(self: *Dependencies, a: Allocator) void {
                a.free(self.sources);
                a.free(self.plain);
            }
        };
        const GraphResult = struct {
            graph: StoredGraph,
            pub fn deinit(self: *GraphResult, a: Allocator) void {
                const graph = if (claim == .source_description) self.graph orelse return else self.graph;
                graph.deinit(a);
            }
        };
        const Adapter = struct {
            pub const kind: @import("../reuse/semantic_query_table.zig").Kind = .principal;
            pub const Key = QueryKey;
            pub const Dependencies = Self.Dependencies;
            pub const Result = Self.GraphResult;
            pub fn fingerprint(key: QueryKey) u64 {
                if (key.forced) return 0;
                var hash = std.hash.Wyhash.init(0);
                std.hash.autoHash(&hash, key.source);
                return hash.final();
            }
            pub fn complete(record: Table.Record) bool {
                const graph = if (claim == .source_description) record.value.graph orelse return false else record.value.graph;
                if (record.key.claim_ != claim or graph.root == 0 or !std.meta.eql(record.key.source, graph.key) or record.dependencies.sources.len != graph.dependencies.len or record.dependencies.plain.len != graph.plain_reads.len) return false;
                for (record.dependencies.sources, graph.dependencies) |left, right| if (!std.meta.eql(left, right)) return false;
                for (record.dependencies.plain, graph.plain_reads) |left, right| if (!std.meta.eql(left, right)) return false;
                var has_writes = false;
                for (record.dependencies.plain) |fact| has_writes = has_writes or !fact.read;
                return has_writes == record.dependencies.has_writes;
            }
            pub fn bytes(record: Table.Record) usize {
                const graph = if (claim == .source_description) record.value.graph orelse return 0 else record.value.graph;
                return @sizeOf(PrincipalGraph) +| graph.allocations.counts.live_bytes +|
                    record.dependencies.sources.len *| @sizeOf(core.BindingRef) +| record.dependencies.plain.len *| @sizeOf(receipt.PlainFact);
            }
        };
        const Table = @import("../reuse/semantic_query_table.zig").Table(Adapter);
        table: Table = .{},
        // Unsupported source descriptions are private owner-scoped work memos,
        // never a completed principal answer or a persisted failure.
        declines: std.AutoHashMapUnmanaged(PrincipalGraph.Key, void) = .empty,
        owner: ?usize = null,
        units: ?[*]const core.Module = null,
        unit_count: usize = 0,
        force_collision: bool = false,
        lookup_budget: usize = 4096,
        inspected_positions: usize = 0,
        inspected_dependencies: usize = 0,
        lookup_declines: usize = 0,
        pub fn storage(self: *const Self) @import("../reuse/semantic_query_table.zig").Storage {
            var result = self.table.storage();
            result.inspected_positions = self.inspected_positions;
            result.inspected_dependencies = self.inspected_dependencies;
            result.lookup_declines = self.lookup_declines;
            return result;
        }
        fn inspect(self: *Self, remaining: *usize, dependency: bool) bool {
            if (remaining.* == 0) {
                self.lookup_declines +|= 1;
                return false;
            }
            remaining.* -= 1;
            if (dependency) self.inspected_dependencies +|= 1 else self.inspected_positions +|= 1;
            return true;
        }
        pub fn deinit(self: *Self, a: Allocator) void {
            self.table.deinit(a);
            self.declines.deinit(a);
        }
        pub fn count(self: *const Self) usize {
            return self.table.records.items.len + self.declines.count();
        }
        pub fn get(self: *Self, key: PrincipalGraph.Key, session: *const Session) ?StoredGraph {
            const result = self.getInner(key, session);
            if (session.member_trace) |trace| {
                var outcome: receipt.PrincipalOutcome = .missing;
                if (result) |graph| {
                    outcome = .graph;
                    if (claim == .source_description and graph == null) outcome = .declined;
                }
                trace.append(.{ .target = .{ .unit = session.unitId(key.target.unit), .binding = key.target.binding }, .open = claim == .open_residual, .source_interface = key.source_interface, .deferred_member = key.deferred_member, .outcome = outcome });
            }
            return result;
        }
        fn getInner(self: *Self, key: PrincipalGraph.Key, session: *const Session) ?StoredGraph {
            if (self.owner != @intFromPtr(session) or self.units != session.units.ptr or self.unit_count != session.units.len) return null;
            if (claim == .source_description and self.declines.contains(key)) return @as(StoredGraph, null);
            var cursor = self.table.candidates(Adapter.fingerprint(.{ .source = key, .forced = self.force_collision }), .oldest_first);
            var remaining = self.lookup_budget;
            while (cursor.next()) |position| {
                if (!self.inspect(&remaining, false)) return null;
                const record = &self.table.records.items[position];
                if (!std.meta.eql(record.key.source, key)) continue;
                var valid = true;
                for (record.dependencies.plain, 0..) |fact, index| {
                    if (!self.inspect(&remaining, true)) return null;
                    if (!fact.read) continue;
                    var actual = session.specializations.plain_nominals.get(fact.key);
                    if (record.dependencies.has_writes) {
                        var prior = index;
                        while (prior != 0) {
                            prior -= 1;
                            if (!self.inspect(&remaining, true)) return null;
                            const write = record.dependencies.plain[prior];
                            if (!write.read and write.key == fact.key) {
                                actual = write.plain;
                                break;
                            }
                        }
                    }
                    valid = valid and (if (fact.present) actual != null and actual.? == fact.plain else actual == null);
                    if (!valid) break;
                }
                if (valid) return record.value.graph;
            }
            return null;
        }
        pub fn contains(self: *Self, key: PrincipalGraph.Key, session: *const Session) bool {
            return self.get(key, session) != null;
        }
        /// Transfers a complete owned graph only after table preparation. On a
        /// budget decline the caller still owns it and takes ordinary checking.
        pub fn put(self: *Self, a: Allocator, key: PrincipalGraph.Key, value: StoredGraph, session: *Session) Allocator.Error!bool {
            if (session.member_trace) |trace| trace.complete = false;
            if (self.owner) |owner| {
                if (owner != @intFromPtr(session) or self.units != session.units.ptr or self.unit_count != session.units.len) return false;
            } else {
                self.owner = @intFromPtr(session);
                self.units = session.units.ptr;
                self.unit_count = session.units.len;
            }
            const graph = if (claim == .source_description) value orelse {
                if (self.declines.count() >= self.table.limits.records) return false;
                try self.declines.put(a, key, {});
                return true;
            } else value;
            const sources = try a.dupe(core.BindingRef, graph.dependencies);
            errdefer a.free(sources);
            const plain = try a.dupe(receipt.PlainFact, graph.plain_reads);
            var has_writes = false;
            for (plain) |fact| has_writes = has_writes or !fact.read;
            // A builder owns copied reads, while the caller owns the graph until
            // success. Keep its ownership out of abort on OOM/budget decline.
            var candidate: Table.Candidate = .{ .allocator = a, .record = .{
                .key = .{ .source = key, .forced = self.force_collision },
                .dependencies = .{ .sources = sources, .plain = plain, .has_writes = has_writes },
                .value = .{ .graph = value },
            } };
            defer if (candidate.record) |*record| a.free(record.dependencies.plain);
            const prepared = try self.table.prepare(a, &candidate) orelse {
                a.free(sources);
                return false;
            };
            _ = self.table.publish(prepared, &candidate);
            return true;
        }
        const Values = struct {
            records: []Table.Record,
            position: usize = 0,
            pub fn next(self: *Values) ?*StoredGraph {
                if (self.position == self.records.len) return null;
                const result = &self.records[self.position].value.graph;
                self.position += 1;
                return result;
            }
        };
        pub fn valueIterator(self: *Self) Values {
            return .{ .records = self.table.records.items };
        }
        const Keys = struct {
            records: []Table.Record,
            position: usize = 0,
            pub fn next(self: *Keys) ?*PrincipalGraph.Key {
                if (self.position == self.records.len) return null;
                const result = &self.records[self.position].key.source;
                self.position += 1;
                return result;
            }
        };
        pub fn keyIterator(self: *Self) Keys {
            return .{ .records = self.table.records.items };
        }
    };
}

fn principalQueryTestGraph(a: Allocator, key: PrincipalGraph.Key, plain: ?bool) Allocator.Error!*PrincipalGraph {
    const graph = try a.create(PrincipalGraph);
    graph.* = .{ .key = key, .allocations = .{ .backing = a }, .types = undefined };
    const owned = graph.allocations.allocator();
    graph.types = types.Store.init(owned) catch {
        a.destroy(graph);
        return error.OutOfMemory;
    };
    errdefer graph.deinit(a);
    graph.root = types.u32_type;
    graph.dependencies = try owned.dupe(core.BindingRef, &.{.{ .unit = 1, .binding = key.target.binding }});
    graph.plain_reads = try owned.dupe(receipt.PlainFact, &.{.{ .key = 7, .plain = plain orelse false, .present = plain != null }});
    return graph;
}
// Principal input keys compare every module's source image, so a graph that
// collected source scopes from another unit reads nothing they miss. Source
// receipts admit sources per binding and still treat such a graph as unknown.
test "recorded principal regions keep input keys over foreign graph sources" {
    const a = std.testing.allocator;
    var session = try Session.init(a, &.{});
    defer session.deinit();
    var region = try ClosureRegion.initAt(&session, @src());
    defer region.deinit();
    const graph = try principalQueryTestGraph(a, .{ .target = .{ .unit = 0, .binding = 1 }, .source_interface = false, .deferred_member = false, .options = .{} }, true);
    defer graph.deinit(a);
    graph.foreign_sources = true;
    for ([_]bool{ false, true }) |types_only| {
        graph.foreign_types_only = types_only;
        for ([_]bool{ false, true }) |untracked| {
            graph.untracked_reads = untracked;
            var reads: principal_inputs.Recorder = .{ .eligible = true, .max_reads = 8, .serial = 1 };
            defer reads.deinit(a);
            var tape: receipt.Tape = .{};
            defer tape.deinit(a);
            session.principal_reads = &reads;
            session.receipt_tape = &tape;
            defer {
                session.principal_reads = null;
                session.receipt_tape = null;
            }
            try region.principalDependencies(graph, false);
            try std.testing.expectEqual(!untracked, reads.eligible);
            try std.testing.expect(tape.unknown);
            if (!untracked) try std.testing.expectEqual(types_only, reads.source_complete);
        }
    }
}
fn principalQueryTestRecord(cache: anytype, session: *Session, key: PrincipalGraph.Key, plain: ?bool) !*PrincipalGraph {
    const a = session.allocator;
    const graph = try principalQueryTestGraph(a, key, plain);
    var owned = true;
    defer if (owned) {
        graph.deinit(a);
    };
    if (!try cache.put(a, key, graph, session)) return error.TestUnexpectedDecline;
    owned = false;
    return graph;
}
fn principalQueryCollisionScenario(a: Allocator) !void {
    var session = try Session.init(a, &.{});
    defer session.deinit();
    var foreign = try Session.init(a, &.{});
    defer foreign.deinit();
    var cache: PrincipalQueries(.source_description) = .{ .force_collision = true };
    defer cache.deinit(a);
    var normalized: PrincipalQueries(.open_residual) = .{ .force_collision = true };
    defer normalized.deinit(a);
    const key: PrincipalGraph.Key = .{ .target = .{ .unit = 0, .binding = 1 }, .source_interface = true, .deferred_member = false, .options = .{} };
    const first = try principalQueryTestRecord(&cache, &session, key, null);
    try std.testing.expect(cache.get(key, &session).?.? == first);
    try std.testing.expect(cache.get(key, &foreign) == null);
    try std.testing.expect(normalized.get(key, &session) == null);
    var unequal = key;
    unequal.source_interface = false;
    try std.testing.expect(cache.get(unequal, &session) == null);
    unequal = key;
    unequal.deferred_member = true;
    try std.testing.expect(cache.get(unequal, &session) == null);
    unequal = key;
    unequal.options.max_depth = 1;
    try std.testing.expect(cache.get(unequal, &session) == null);
    try session.specializations.plain_nominals.put(a, 7, false);
    try std.testing.expect(cache.get(key, &session) == null);
    const second = try principalQueryTestRecord(&cache, &session, key, false);
    try std.testing.expect(cache.get(key, &session).?.? == second);
    try session.specializations.plain_nominals.put(a, 7, true);
    try std.testing.expect(cache.get(key, &session) == null);
    const third = try principalQueryTestRecord(&cache, &session, key, true);
    try std.testing.expect(cache.get(key, &session).?.? == third);
    cache.lookup_budget = 0;
    try std.testing.expect(cache.get(key, &session) == null);
    cache.lookup_budget = 4096;
    try std.testing.expect(cache.get(key, &session).?.? == third);
    const residual = try principalQueryTestRecord(&normalized, &session, key, true);
    try std.testing.expect(normalized.get(key, &session).? == residual);
    try std.testing.expect(cache.get(key, &session).?.? == third);
    var declined = key;
    declined.target.binding = 2;
    try std.testing.expect(try cache.put(a, declined, null, &session));
    try std.testing.expect(cache.get(declined, &session).? == null);
    var ordered_key = key;
    ordered_key.target.binding = 3;
    const ordered = try principalQueryTestGraph(a, ordered_key, null);
    var owns_ordered = true;
    defer if (owns_ordered) {
        ordered.deinit(a);
    };
    const graph_allocator = ordered.allocations.allocator();
    graph_allocator.free(ordered.plain_reads);
    ordered.plain_reads = &.{};
    ordered.plain_reads = try graph_allocator.dupe(receipt.PlainFact, &.{
        .{ .key = 9, .plain = false, .present = false },
        .{ .key = 9, .plain = false, .read = false },
        .{ .key = 9, .plain = false },
    });
    try std.testing.expect(try cache.put(a, ordered_key, ordered, &session));
    owns_ordered = false;
    try std.testing.expect(cache.get(ordered_key, &session).?.? == ordered);
    try std.testing.expect(!session.specializations.plain_nominals.contains(9));
    try session.specializations.plain_nominals.put(a, 9, false);
    try std.testing.expect(cache.get(ordered_key, &session) == null);
    try std.testing.expectEqual(@as(usize, 4), cache.table.records.items.len);
    try std.testing.expectEqual(@as(usize, 1), cache.declines.count());
    const bytes = cache.table.owned_bytes;
    try std.testing.expect(bytes > first.allocations.counts.live_bytes + second.allocations.counts.live_bytes + third.allocations.counts.live_bytes);
    cache.table.limits.records = 4;
    const unexpected: ?*PrincipalGraph = principalQueryTestRecord(&cache, &session, key, true) catch |err| switch (err) {
        error.TestUnexpectedDecline => null,
        else => return err,
    };
    try std.testing.expect(unexpected == null);
    try std.testing.expectEqual(bytes, cache.table.owned_bytes);
    try std.testing.expect(cache.get(key, &session).?.? == third);
}
test "principal query templates distinguish owners claims flags plain observations and collisions under every allocation failure" {
    try principalQueryCollisionScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, principalQueryCollisionScenario, .{});
}

const RetainedGraphTestProvider = struct {
    old: *const RetainedPrincipalGraphs,
    denied: core.BindingId = 0,
    pub fn admits(self: *const RetainedGraphTestProvider, source: core.BindingRef) bool {
        return source.unit == 1 and source.binding != 0 and source.binding != self.denied;
    }
    fn lookup(context: *anyopaque, key: PrincipalGraph.Key) ?*PrincipalGraph {
        const self: *RetainedGraphTestProvider = @ptrCast(@alignCast(context));
        return self.old.lookup(key, self);
    }
};
fn retainedGraphScenario(a: Allocator, module: *const core.Module) !void {
    const root = for (module.bodies) |body| {
        if (body.exported) break body.binding;
    } else return error.TestExpectedRoot;
    const dependency = for (module.bodies) |body| {
        if (body.binding != 0 and body.binding != root) break body.binding;
    } else return error.TestExpectedDependency;
    const key: PrincipalGraph.Key = .{ .target = .{ .unit = 0, .binding = root }, .source_interface = true, .deferred_member = false, .options = .{} };
    var retained: RetainedPrincipalGraphs = .{};
    defer retained.deinit(a);
    {
        var original = try Session.init(a, &.{module.*});
        defer original.deinit();
        var region = try ClosureRegion.init(&original);
        defer region.deinit();
        const graph = (try region.principalGraphForKey(key)).?;
        try std.testing.expect(graph.retention_eligible);
        // Exercise dependency rejection separately from rejection of the root.
        const owner = graph.allocations.allocator();
        owner.free(graph.dependencies);
        graph.dependencies = &.{};
        graph.dependencies = try owner.dupe(core.BindingRef, &.{.{ .unit = 1, .binding = dependency }});
        try retained.capture(&original);
        try std.testing.expectEqual(@as(usize, 2), graph.leases);
    }
    var provider: RetainedGraphTestProvider = .{ .old = &retained };
    const graph = retained.lookup(key, &provider).?;
    try std.testing.expectEqual(@as(usize, 1), graph.leases);
    var different = key;
    different.options.max_type_depth -= 1;
    try std.testing.expect(retained.lookup(different, &provider) == null);
    different = key;
    different.deferred_member = true;
    try std.testing.expect(retained.lookup(different, &provider) == null);
    different = key;
    different.source_interface = false;
    try std.testing.expect(retained.lookup(different, &provider) == null);
    provider.denied = dependency;
    try std.testing.expect(retained.lookup(key, &provider) == null);
    provider.denied = key.target.binding;
    try std.testing.expect(retained.lookup(key, &provider) == null);
    provider.denied = 0;
    var current = try Session.init(a, &.{module.*});
    defer current.deinit();
    current.principal_graph_provider = .{ .context = &provider, .lookup = RetainedGraphTestProvider.lookup };
    var region = try ClosureRegion.init(&current);
    defer region.deinit();
    const before = current.counters.inference_regions;
    try std.testing.expect((try region.principalGraphForKey(key)).? == graph);
    try std.testing.expectEqual(before, current.counters.inference_regions);
    try std.testing.expectEqual(@as(u64, 1), current.counters.principal_graph_retained_hits);
    var next: RetainedPrincipalGraphs = .{};
    defer next.deinit(a);
    try next.capture(&current);
    retained.deinit(a);
    retained = .{};
    try std.testing.expectEqual(@as(usize, 2), graph.leases);
    try std.testing.expect(current.specializations.call_summaries.principals.get(key, &current).?.? == graph);
    var limited: RetainedPrincipalGraphs = .{};
    defer limited.deinit(a);
    limited.queries.table.limits.owned_bytes = 0;
    try limited.capture(&current);
    try std.testing.expectEqual(@as(usize, 0), limited.queries.count());
    try std.testing.expectEqual(@as(usize, 2), graph.leases);
    // A later capture carries only the graphs that revision actually used.
    var unused = try Session.init(a, &.{module.*});
    defer unused.deinit();
    var pruned: RetainedPrincipalGraphs = .{};
    defer pruned.deinit(a);
    try pruned.capture(&unused);
    try std.testing.expectEqual(@as(usize, 0), pruned.queries.count());
}
test "retained immutable principal graphs outlive sessions validate dependencies and release leases through OOM" {
    var module = try bodyRecipeLower("entry const identity = fn value => value\nconst dependency = fn value => value\n");
    defer module.deinit(std.testing.allocator);
    try retainedGraphScenario(std.testing.allocator, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, retainedGraphScenario, .{&module});
}

fn largeInterfaceScenario(a: Allocator, module: *const core.Module, binding: core.BindingId) !void {
    const equations = @import("../check/scheme_equations.zig");
    const contracts = @import("../check/package_contracts.zig");
    var remaining: usize = 65_536;
    try @import("../check/package_core.zig").checkedInterfaceBody(module, binding, .{ .units = &[_]*const core.Module{module} }, &remaining, a);
    // A large ordinary type graph does not enlarge the package reader's ABI.
    var small: contracts.Context = .{ .types = &module.types, .remaining = &remaining };
    try std.testing.expectError(error.InvalidArtifact, small.initialize());
    var views: contracts.Context = .{ .types = &module.types, .remaining = &remaining, .large_plain_graph = true };
    try views.initialize();
    var scheme = module.binding(binding).scheme;
    scheme.variables = .{ .start = @intCast(module.types.extra.len - 1), .len = 1 };
    try views.generic(scheme);
    try views.closed_rows.set(5000);
    var solver = try equations.Solver.init(a, module, &views, &remaining);
    defer solver.deinit();
    try std.testing.expect(solver.ownsRigid(solver.store.nodes.items[4100]));
    try std.testing.expect(!solver.ownsRigid(solver.store.nodes.items[4101]));
    var other_scope = solver.store.nodes.items[4100];
    other_scope.a += 1;
    try std.testing.expect(!solver.ownsRigid(other_scope));
    try std.testing.expect(solver.store.effects.rows.items[5000].tail == .closed);
    try std.testing.expect(solver.store.effects.rows.items[5001].tail == .formal);
}
test "completed body interfaces admit large ordinary type graphs with exact rigid owners through OOM" {
    const a = std.testing.allocator;
    var module = try bodyRecipeLower("entry const identity = fn value => value\n");
    defer module.deinit(a);
    const binding = for (module.bodies) |body| {
        if (body.exported) break body.binding;
    } else return error.TestExpectedRoot;
    const nodes = try a.alloc(types.Node, 4200);
    @memcpy(nodes[0..module.types.nodes.len], module.types.nodes);
    @memset(nodes[module.types.nodes.len..], .{ .tag = .u32 });
    nodes[4100] = .{ .tag = .variable };
    nodes[4101] = .{ .tag = .variable };
    a.free(module.types.nodes);
    module.types.nodes = nodes;
    const extra = try a.alloc(u32, module.types.extra.len + 1);
    @memcpy(extra[0..module.types.extra.len], module.types.extra);
    extra[extra.len - 1] = 4100;
    a.free(module.types.extra);
    module.types.extra = extra;
    const rows = try a.alloc(types.Effects.Row, 6000);
    @memcpy(rows[0..module.types.effects.rows.len], module.types.effects.rows);
    @memset(rows[module.types.effects.rows.len..], .{ .labels = .{}, .tail = .closed });
    rows[5000].tail = .{ .variable = module.types.effects.variable_count };
    rows[5001].tail = rows[5000].tail;
    module.types.effects.variable_count += 1;
    a.free(module.types.effects.rows);
    module.types.effects.rows = rows;
    try largeInterfaceScenario(a, &module, binding);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, largeInterfaceScenario, .{ &module, binding });
}

fn sourceBodyDependencyScenario(a: Allocator, module: *core.Module, root: core.BindingId, producer: core.BindingId, bad: core.Id) !void {
    const proof = @import("../check/package_core.zig");
    var remaining: usize = 65_536;
    try proof.checkedInterfaceBody(module, root, .{ .units = &[_]*const core.Module{module} }, &remaining, a);
    for (module.bodies) |*body| if (body.binding == producer) {
        const original = body.root;
        defer body.root = original;
        body.root = bad;
        remaining = 65_536;
        proof.checkedInterfaceBody(module, root, .{ .units = &[_]*const core.Module{module} }, &remaining, a) catch |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expectEqual(error.InvalidArtifact, err);
            return;
        };
        return error.TestExpectedInvalidProducer;
    };
    return error.TestExpectedProducer;
}
test "source interface authority checks every reached declaration body through allocation failures" {
    const a = std.testing.allocator;
    var module = try bodyRecipeLower("const producer: U32 -> U32 = fn value => @u32.add value 1\nentry const relay: U32 -> U32 = fn value => producer value\nconst unrelated = #True\n");
    defer module.deinit(a);
    var producer: core.BindingId = 0;
    var root: core.BindingId = 0;
    var bad: core.Id = 0;
    for (module.bodies) |body| {
        if (body.exported) root = body.binding;
        if (std.mem.eql(u8, module.name(body.declaration_name), "producer")) producer = body.binding;
        if (std.mem.eql(u8, module.name(body.declaration_name), "unrelated")) bad = body.root;
    }
    try std.testing.expect(root != 0 and producer != 0 and bad != 0);
    try sourceBodyDependencyScenario(a, &module, root, producer, bad);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, sourceBodyDependencyScenario, .{ &module, root, producer, bad });
}

const CallSummaries = struct {
    const Key = struct { target: Target, inputs: type_evidence.Id, source_interface: bool, lexical: u32 = 0, expected_result: type_evidence.Id = 0, expected_signature: type_evidence.Id = 0, deferred_member: bool = false, options: Options = .{} };
    const JobState = enum { queued, running, waiting, complete, declined };
    /// `recorded` names the principal input recorder that was attached while
    /// the job ran, or zero. Its reads and publications went to that recorder.
    /// `private_declined` marks a member of a component whose private job
    /// returned no publishable package; the coordinator does not offer it
    /// again and the serial path, which decides every job either way, runs it.
    const Job = struct { key: Key, state: JobState = .queued, region: ?*ClosureRegion = null, scope: ?u32 = null, result: type_evidence.Id = 0, recorded: u64 = 0, private_declined: bool = false };
    const HeaderParts = struct { mask: []bool, has_private: bool = false };
    regions: std.heap.MemoryPool(ClosureRegion) = .empty,
    keys: std.AutoHashMapUnmanaged(Key, usize) = .empty,
    jobs: std.ArrayList(Job) = .empty,
    stack: std.ArrayList(usize) = .empty,
    active: std.AutoHashMapUnmanaged(Target, usize) = .empty,
    active_lexical: std.AutoHashMapUnmanaged(u32, usize) = .empty,
    components: scope_components.Graph = .{},
    current: ?usize = null,
    restart: ?usize = null,
    eligibility: std.AutoHashMapUnmanaged(Target, bool) = .empty,
    checked_requirements: std.AutoHashMapUnmanaged(Target, bool) = .empty,
    completed_interfaces: std.AutoHashMapUnmanaged(Target, ?[]Target) = .empty,
    completed_interface_targets: usize = 0,
    // Exact source slots consumed by the mandatory header graph. These are
    // immutable source facts, not a live instantiation or a completed proof.
    public_requirements: std.AutoHashMapUnmanaged(Target, HeaderParts) = .empty,
    public_requirement_slots: usize = 0,
    constant_requirements: std.AutoHashMapUnmanaged(Target, void) = .empty,
    principals: PrincipalQueries(.source_description) = .{},
    normalized_principals: PrincipalQueries(.open_residual) = .{},
    open_principals: std.AutoHashMapUnmanaged(PrincipalGraph.Key, bool) = .empty,
    result_principals: std.AutoHashMapUnmanaged(PrincipalGraph.Key, bool) = .empty,
    draining: bool = false,

    fn observation(session: *const Session, key: Key, result: type_evidence.Id) ?principal_inputs.Summary {
        if (key.lexical != 0 or key.expected_result != 0 or key.expected_signature != 0 or key.source_interface or !std.meta.eql(key.options, session.options)) return null;
        return .{ .key = .{ .target = .{ .unit = session.unitId(key.target.unit), .binding = key.target.binding }, .inputs = key.inputs, .deferred_member = key.deferred_member }, .result = result };
    }

    const Member = struct { index: usize, key: Key };
    const Edge = struct { from: u32, to: u32 };
    const Component = struct {
        members: []Member,
        edges: []Edge,
        budget: usize = 0,
        fn deinit(self: *Component, a: Allocator) void {
            a.free(self.members);
            a.free(self.edges);
        }
        fn less(_: void, left: Component, right: Component) bool {
            const l = left.members[0].key.target;
            const r = right.members[0].key.target;
            return if (l.unit != r.unit) l.unit < r.unit else if (l.binding != r.binding) l.binding < r.binding else left.members[0].index < right.members[0].index;
        }
    };
    const ComponentResult = struct {
        snapshot: ?type_evidence.Snapshot = null,
        keys: []Key = &.{},
        roots: []type_evidence.Id = &.{},
        sources: []core.BindingRef = &.{},
        recursive_members: usize = 0,
        restarts: usize = 0,
        transitions: usize = 0,
        counters: @import("../work_counters.zig").Counters = .{},
        job_nanos: u64 = 0,
        pub fn deinit(self: *ComponentResult, a: Allocator) void {
            if (self.snapshot) |*snapshot_| snapshot_.deinit(a);
            a.free(self.keys);
            a.free(self.roots);
            a.free(self.sources);
        }
        fn measured(session: *const Session) ComponentResult {
            return .{ .transitions = session.summary_transitions, .counters = session.counters };
        }
    };
    fn executeComponent(scratch: Allocator, output: Allocator, input: *const Session, component_: Component) Allocator.Error!?ComponentResult {
        var clock = @import("../backend/backend_timing.zig").Clock.init(if (input.timing != null) input.semantic_io else null);
        var result = try executeComponentOwned(scratch, output, input, component_);
        if (result) |*owned| owned.job_nanos = clock.lapNanos();
        return result;
    }
    fn executeComponentOwned(scratch: Allocator, output: Allocator, input: *const Session, component_: Component) Allocator.Error!?ComponentResult {
        var private = try Session.initShared(scratch, input);
        defer private.deinit();
        private.options = input.options;
        private.semantic_job_budget = component_.budget;
        private.depth = input.depth;
        private.seedScalarInputs(input) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else ComponentResult.measured(&private);
        var dependencies: receipt.Tape = .{};
        defer dependencies.deinit(scratch);
        private.receipt_tape = &dependencies;
        var imports: @import("semantic_evidence_import.zig").Importer = .{ .allocator = scratch, .source = input.storage.evidence.view(), .destination = &private.storage.evidence, .max_depth = input.options.max_type_depth };
        defer imports.deinit();
        var lexical_origins: std.ArrayList(u32) = .empty;
        defer lexical_origins.deinit(scratch);
        const requested_keys = try scratch.alloc(Key, component_.members.len);
        defer scratch.free(requested_keys);
        for (component_.members, requested_keys) |member_, *key| {
            key.* = member_.key;
            if (key.lexical != 0) {
                const original = key.lexical;
                if (std.mem.findScalar(u32, lexical_origins.items, original)) |index| {
                    key.lexical = @intCast(index + 1);
                } else {
                    const original_input = input.specializations.lexical_inputs.inputs.items[original - 1];
                    if (original_input.words.len > private.options.max_children -| private.specializations.lexical_inputs.retained_words) return ComponentResult.measured(&private);
                    try lexical_origins.ensureUnusedCapacity(scratch, 1);
                    try private.specializations.lexical_inputs.inputs.ensureUnusedCapacity(scratch, 1);
                    const copied = original_input.copyTyping(scratch, &imports) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else ComponentResult.measured(&private);
                    key.lexical = @intCast(lexical_origins.items.len + 1);
                    lexical_origins.appendAssumeCapacity(original);
                    private.specializations.lexical_inputs.inputs.appendAssumeCapacity(copied);
                    // Opaque parent key words contain parent evidence/value
                    // ordinals. Only the remapped typing fields are consumed
                    // here; never index foreign words in the private cache.
                    // A newly interned private input gets a fresh ordinal and
                    // cannot escape the origin check below.
                    private.specializations.lexical_inputs.retained_words += copied.words.len;
                    private.specializations.lexical_inputs.examined_words += copied.words.len;
                }
            }
            key.inputs = imports.ty(key.inputs, 0) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else ComponentResult.measured(&private);
            key.expected_result = imports.ty(key.expected_result, 0) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else ComponentResult.measured(&private);
            key.expected_signature = imports.ty(key.expected_signature, 0) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else ComponentResult.measured(&private);
            _ = private.specializations.call_summaries.request(&private, key.*) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else ComponentResult.measured(&private);
        }
        for (component_.edges) |edge| _ = private.specializations.call_summaries.components.add(scratch, edge.from, edge.to, requested_keys.len, &private.summary_transitions, private.summaryLimit()) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else ComponentResult.measured(&private);
        const before_values = private.storage.values.items.len;
        const before_children = private.storage.children.items.len;
        private.specializations.call_summaries.drain(&private) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return .{ .transitions = private.summary_transitions, .counters = private.counters };
        };
        var result: ComponentResult = .{ .transitions = private.summary_transitions, .counters = private.counters };
        errdefer result.deinit(output);
        if (private.diagnostic != null or dependencies.unknown or dependencies.nested or private.steps != 0 or private.storage.values.items.len != before_values or private.storage.children.items.len != before_children) return result;
        for (requested_keys) |key| {
            const index = private.specializations.call_summaries.keys.get(key) orelse return result;
            if (private.specializations.call_summaries.jobs.items[index].state != .complete) return result;
        }
        // Return every completed private member, including SCC members found
        // during execution. No provisional or declined judgment crosses owners.
        const Export = struct {
            key: Key,
            root: type_evidence.Id,
            fn less(_: void, left: @This(), right: @This()) bool {
                const l = left.key;
                const r = right.key;
                inline for (.{ "unit", "binding" }) |field| if (@field(l.target, field) != @field(r.target, field)) return @field(l.target, field) < @field(r.target, field);
                inline for (.{ "lexical", "inputs", "expected_result", "expected_signature" }) |field| if (@field(l, field) != @field(r, field)) return @field(l, field) < @field(r, field);
                if (l.source_interface != r.source_interface) return !l.source_interface;
                return !l.deferred_member and r.deferred_member;
            }
        };
        var exports: std.ArrayList(Export) = .empty;
        defer exports.deinit(scratch);
        for (private.specializations.call_summaries.jobs.items) |job| {
            if (job.state != .complete) continue;
            var key = job.key;
            if (key.lexical != 0) {
                if (key.lexical > lexical_origins.items.len) return result;
                key.lexical = lexical_origins.items[key.lexical - 1];
            }
            try exports.append(scratch, .{ .key = key, .root = job.result });
        }
        std.mem.sortUnstable(Export, exports.items, {}, Export.less);
        result.keys = try output.alloc(Key, exports.items.len);
        result.roots = try output.alloc(type_evidence.Id, exports.items.len);
        for (exports.items, result.keys, result.roots) |entry, *key, *root| {
            key.* = entry.key;
            root.* = entry.root;
        }
        result.recursive_members = private.component_members_published;
        result.restarts = private.component_restarts;
        result.snapshot = try private.storage.evidence.copyOwned(output);
        result.sources = try output.dupe(core.BindingRef, dependencies.sources.items);
        return result;
    }
    fn parallelReady(self: *CallSummaries, session: *Session) ClosureRegion.RegionError!bool {
        session.counters.semantic_component_attempts += 1;
        const io = session.semantic_io orelse {
            session.counters.semantic_component_no_io += 1;
            return false;
        };
        if (session.semantic_component_workers == 0) {
            session.counters.semantic_component_disabled += 1;
            return false;
        }
        if (session.receipt_tape != null or session.recordingConstant() or session.principal_reads != null) {
            session.counters.semantic_component_recording += 1;
            return false;
        }
        if (session.refinement_observation != null) {
            session.counters.semantic_component_observing += 1;
            return false;
        }
        if (session.summary_exhausted) {
            session.counters.semantic_component_exhausted += 1;
            return false;
        }
        const coordination = if (session.timing) |timing| timing.enter(.semantic_coordination) else null;
        defer if (coordination) |scope| scope.deinit();
        const a = session.allocator;
        var ready: std.ArrayList(Component) = .empty;
        defer {
            for (ready.items) |*component_| component_.deinit(a);
            ready.deinit(a);
        }
        for (self.jobs.items, 0..) |job, index| {
            if (job.state != .queued or self.components.component(@intCast(index)) != index) continue;
            var members: std.ArrayList(Member) = .empty;
            defer members.deinit(a);
            var eligible = true;
            for (self.jobs.items, 0..) |member_, member_index| {
                if (!self.member(index, member_index)) continue;
                if ((member_.state != .queued and member_.state != .waiting) or member_.region != null or member_.private_declined or member_.key.lexical > session.specializations.lexical_inputs.inputs.items.len) {
                    eligible = false;
                    break;
                }
                // An active SCC has one monomorphic root per source owner.
                // Distinct closed instances of that owner remain separate
                // components; a merged ambiguous component stays serial.
                for (members.items) |prior| {
                    const same_owner = if (member_.key.lexical != 0 or prior.key.lexical != 0) member_.key.lexical != 0 and member_.key.lexical == prior.key.lexical else std.meta.eql(member_.key.target, prior.key.target);
                    if (same_owner) eligible = false;
                }
                if (!eligible) break;
                try members.append(a, .{ .index = member_index, .key = member_.key });
            }
            if (!eligible) continue;
            var edges: std.ArrayList(Edge) = .empty;
            defer edges.deinit(a);
            for (self.components.edges.items) |edge| {
                if (!self.member(index, edge.from)) continue;
                if (!self.member(index, edge.to)) {
                    if (self.jobs.items[edge.to].state != .complete and self.jobs.items[edge.to].state != .declined) eligible = false;
                    continue;
                }
                var from: u32 = 0;
                var to: u32 = 0;
                for (members.items, 0..) |member_, local| {
                    if (member_.index == edge.from) from = @intCast(local);
                    if (member_.index == edge.to) to = @intCast(local);
                }
                try edges.append(a, .{ .from = from, .to = to });
            }
            if (!eligible) continue;
            const owned_members = try members.toOwnedSlice(a);
            errdefer a.free(owned_members);
            const owned_edges = try edges.toOwnedSlice(a);
            errdefer a.free(owned_edges);
            try ready.append(a, .{ .members = owned_members, .edges = owned_edges });
        }
        if (ready.items.len < 2) return false;
        std.mem.sortUnstable(Component, ready.items, {}, Component.less);
        const budget = (session.summaryLimit() -| session.summary_transitions) / ready.items.len;
        if (budget == 0) return false;
        for (ready.items) |*component_| component_.budget = budget;
        const jobs = @import("semantic_job_batch.zig");
        var cancellation: jobs.Cancellation = .{};
        var batch = blk: {
            const dispatch = if (session.timing) |timing| timing.enter(.semantic_dispatch) else null;
            defer if (dispatch) |scope| scope.deinit();
            break :blk try jobs.run(ComponentResult, a, io, ready.items, session.semantic_component_workers, &cancellation, @as(*const Session, session), executeComponent);
        };
        defer batch.deinit();
        session.counters.semantic_component_batches += 1;
        session.counters.semantic_component_jobs += ready.items.len;
        session.counters.max_semantic_component_workers = @max(session.counters.max_semantic_component_workers, batch.workers);
        var failed = false;
        var progressed = false;
        for (ready.items, batch.outcomes) |component_, outcome| switch (outcome) {
            .out_of_memory => failed = true,
            .complete => |result| {
                if (session.timing) |timing| timing.semantic_job_nanos +|= result.job_nanos;
                session.counters.merge(result.counters);
                if (!session.summaryCharge(result.transitions)) continue;
                const snapshot_ = result.snapshot orelse {
                    self.declinePrivate(component_);
                    continue;
                };
                var independent_sources = true;
                for (result.sources) |source| {
                    const owner = session.findUnit(source.unit, null) orelse {
                        independent_sources = false;
                        break;
                    };
                    if (self.active.contains(.{ .unit = owner, .binding = source.binding })) {
                        independent_sources = false;
                        break;
                    }
                }
                if (!independent_sources) continue;
                const publication = if (session.timing) |timing| timing.enter(.semantic_publication) else null;
                defer if (publication) |scope| scope.deinit();
                // Import into a complete private destination. A failed import
                // cannot mutate parent evidence or publish a subset of an SCC.
                var staged = session.storage.evidence.clone(a) catch {
                    failed = true;
                    continue;
                };
                defer staged.deinit();
                var imports: @import("semantic_evidence_import.zig").Importer = .{ .allocator = a, .source = snapshot_.view(), .destination = &staged, .max_depth = session.options.max_type_depth };
                defer imports.deinit();
                const Staged = struct { key: Key, index: ?usize, evidence: type_evidence.Id };
                const prepared = a.alloc(Staged, result.roots.len) catch {
                    failed = true;
                    continue;
                };
                defer a.free(prepared);
                var valid = true;
                for (component_.members) |member_| {
                    const job = self.jobs.items[member_.index];
                    if (!std.meta.eql(job.key, member_.key) or job.region != null or job.state == .declined or job.state == .running) valid = false;
                }
                if (!valid) continue;
                var added: usize = 0;
                for (result.keys, result.roots, prepared) |key, root, *entry| {
                    // Late discovery of a source currently being inferred by
                    // the coordinator must restart through its serial SCC path.
                    if ((if (key.lexical != 0) self.active_lexical.contains(key.lexical) else self.active.contains(key.target)) or !std.meta.eql(key.options, session.options)) {
                        valid = false;
                        break;
                    }
                    var mapped_key = key;
                    mapped_key.inputs = imports.ty(key.inputs, 0) catch |err| {
                        if (err == error.OutOfMemory) failed = true;
                        valid = false;
                        break;
                    };
                    mapped_key.expected_result = imports.ty(key.expected_result, 0) catch |err| {
                        if (err == error.OutOfMemory) failed = true;
                        valid = false;
                        break;
                    };
                    mapped_key.expected_signature = imports.ty(key.expected_signature, 0) catch |err| {
                        if (err == error.OutOfMemory) failed = true;
                        valid = false;
                        break;
                    };
                    const mapped = imports.ty(root, 0) catch |err| {
                        if (err == error.OutOfMemory) failed = true;
                        valid = false;
                        break;
                    };
                    const existing = self.keys.get(mapped_key);
                    if (existing) |index| {
                        const job = self.jobs.items[index];
                        if (job.region != null or job.state == .declined or (job.state == .complete and job.result != mapped)) {
                            valid = false;
                            break;
                        }
                    } else added += 1;
                    entry.* = .{ .key = mapped_key, .index = existing, .evidence = mapped };
                }
                if (!valid or added > session.options.max_values -| self.jobs.items.len) continue;
                self.keys.ensureUnusedCapacity(a, @intCast(added)) catch {
                    failed = true;
                    continue;
                };
                self.jobs.ensureUnusedCapacity(a, added) catch {
                    failed = true;
                    continue;
                };
                // Every member/key/effect mapping and index capacity is ready
                // before the allocation-free publication of this whole package.
                std.mem.swap(type_evidence.Store, &staged, &session.storage.evidence);
                for (prepared) |entry| {
                    if (entry.index) |index| {
                        if (self.jobs.items[index].state != .complete) self.finish(session, index, entry.evidence);
                    } else {
                        self.keys.putAssumeCapacity(entry.key, self.jobs.items.len);
                        self.jobs.appendAssumeCapacity(.{ .key = entry.key, .state = .complete, .result = entry.evidence });
                        session.split_attempts += 1;
                        session.split_accepted += 1;
                    }
                }
                session.component_restarts += result.restarts;
                session.component_members_published += result.recursive_members;
                progressed = true;
            },
            .declined => self.declinePrivate(component_),
            else => {},
        };
        if (failed) return error.OutOfMemory;
        if (cancellation.cancelled()) return error.Declined;
        return progressed;
    }
    /// Private declines come from reads a package cannot carry (runtime or
    /// suspended sources, implementation proofs, untracked principal reads),
    /// which the same keys repeat on a later offer. Skipping that offer only
    /// moves the job to the serial path, so publication is unchanged. Only
    /// jobs still holding the dispatched keys are marked.
    fn declinePrivate(self: *CallSummaries, component_: Component) void {
        for (component_.members) |member_| {
            if (member_.index >= self.jobs.items.len) continue;
            const job = &self.jobs.items[member_.index];
            if (std.meta.eql(job.key, member_.key)) job.private_declined = true;
        }
    }

    fn deinit(self: *CallSummaries, session: *Session) void {
        for (self.jobs.items) |job| if (job.region) |region| {
            region.deinit();
            self.regions.destroy(region);
        };
        self.regions.deinit(session.allocator);
        self.keys.deinit(session.allocator);
        self.jobs.deinit(session.allocator);
        self.stack.deinit(session.allocator);
        self.active.deinit(session.allocator);
        self.active_lexical.deinit(session.allocator);
        self.components.deinit(session.allocator);
        self.eligibility.deinit(session.allocator);
        self.checked_requirements.deinit(session.allocator);
        var interfaces = self.completed_interfaces.valueIterator();
        while (interfaces.next()) |targets| if (targets.*) |owned| session.allocator.free(owned);
        self.completed_interfaces.deinit(session.allocator);
        var public_requirements = self.public_requirements.valueIterator();
        while (public_requirements.next()) |parts| session.allocator.free(parts.mask);
        self.public_requirements.deinit(session.allocator);
        self.constant_requirements.deinit(session.allocator);
        self.result_principals.deinit(session.allocator);
        self.principals.deinit(session.allocator);
        self.normalized_principals.deinit(session.allocator);
        self.open_principals.deinit(session.allocator);
    }
    fn request(self: *CallSummaries, session: *Session, key: Key) ClosureRegion.RegionError!?Job {
        if (session.summary_exhausted) return null;
        if (if (key.lexical != 0) self.active_lexical.get(key.lexical) else self.active.get(key.target)) |active| {
            if (!try self.dependency(session, active)) return null;
            return self.jobs.items[active];
        }
        if (self.keys.get(key)) |index| {
            if (self.jobs.items[index].state == .complete or self.jobs.items[index].state == .declined) return self.jobs.items[index];
            if (!try self.dependency(session, index)) return null;
            const job = self.jobs.items[index];
            if (job.state == .queued) {
                const at = std.mem.findScalar(usize, self.stack.items, index).?;
                _ = self.stack.orderedRemove(at);
                self.stack.appendAssumeCapacity(index);
            }
            return job;
        }
        if (self.jobs.items.len >= session.options.max_values) return error.TypeLimit;
        const a = session.allocator;
        try self.keys.ensureUnusedCapacity(a, 1);
        try self.jobs.ensureUnusedCapacity(a, 1);
        try self.stack.ensureUnusedCapacity(a, 1);
        const index = self.jobs.items.len;
        self.keys.putAssumeCapacity(key, index);
        self.jobs.appendAssumeCapacity(.{ .key = key });
        self.stack.appendAssumeCapacity(index);
        session.split_attempts += 1;
        if (!try self.dependency(session, index)) return null;
        return self.jobs.items[index];
    }
    fn dependency(self: *CallSummaries, session: *Session, index: usize) ClosureRegion.RegionError!bool {
        const from = self.current orelse return session.summaryCharge(1);
        const root = self.components.component(@intCast(from));
        if (root == self.components.component(@intCast(index)) and root < self.components.nodes.items.len and self.components.nodes.items[root].recursive) return false;
        const before = session.summary_transitions;
        const merged = self.components.add(session.allocator, @intCast(from), @intCast(index), self.jobs.items.len, &session.summary_transitions, session.summaryLimit()) catch |err| {
            if (err == error.OutOfMemory) return err;
            session.summary_exhausted = true;
            return false;
        };
        session.summary_graph_work +|= session.summary_transitions - before;
        if (merged) self.restart = self.components.component(@intCast(from));
        return true;
    }
    fn finish(self: *CallSummaries, session: *Session, index: usize, result: type_evidence.Id) void {
        const job = &self.jobs.items[index];
        if (job.key.lexical != 0) {
            _ = self.active_lexical.remove(job.key.lexical);
        } else {
            _ = self.active.remove(job.key.target);
        }
        if (job.region) |region| {
            region.deinit();
            self.regions.destroy(region);
            job.region = null;
        }
        job.result = result;
        job.state = if (result == 0) .declined else .complete;
        job.recorded = if (session.principal_reads) |reads| reads.serial else 0;
        if (result == 0) session.split_declined += 1 else session.split_accepted += 1;
        // A job can enqueue children while collecting or solving. Remove its
        // own frame without discarding any independently scheduled work.
        if (std.mem.findScalar(usize, self.stack.items, index)) |at| _ = self.stack.orderedRemove(at);
    }
    fn decline(self: *CallSummaries, session: *Session, index: usize, err: ClosureRegion.RegionError) ClosureRegion.RegionError!void {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        session.allocator.free(session.owned_diagnostic_message);
        session.owned_diagnostic_message = &.{};
        session.diagnostic = null;
        self.finish(session, index, 0);
    }
    fn abandonPending(self: *CallSummaries) void {
        // A failed allocation is neither a semantic decline nor a partially
        // initialized job that another inquiry may resume. Rebuild indices
        // without allocating, retaining only finished independent judgments.
        self.keys.clearRetainingCapacity();
        var retained: usize = 0;
        for (self.jobs.items) |job| {
            if (job.state == .queued or job.state == .running or job.state == .waiting) {
                if (job.region) |region| {
                    region.deinit();
                    self.regions.destroy(region);
                }
            } else {
                self.jobs.items[retained] = job;
                self.keys.putAssumeCapacity(job.key, retained);
                retained += 1;
            }
        }
        self.jobs.items.len = retained;
        self.stack.clearRetainingCapacity();
        self.active.clearRetainingCapacity();
        self.active_lexical.clearRetainingCapacity();
        self.components.clear();
        self.current = null;
        self.restart = null;
    }
    fn drain(self: *CallSummaries, session: *Session) ClosureRegion.RegionError!void {
        std.debug.assert(!self.draining);
        self.draining = true;
        defer self.draining = false;
        defer self.current = null;
        errdefer self.abandonPending();
        while (self.stack.items.len != 0) {
            if (try self.parallelReady(session)) continue;
            const index = self.stack.items[self.stack.items.len - 1];
            self.current = index;
            if (!session.summaryCharge(1)) {
                session.discardDiagnostic();
                for (0..self.jobs.items.len) |pending| {
                    const state = self.jobs.items[pending].state;
                    if (state == .queued or state == .running or state == .waiting) self.finish(session, pending, 0);
                }
                return;
            }
            const job = self.jobs.items[index];
            if (job.state == .queued) {
                const region = try self.regions.create(session.allocator);
                region.* = ClosureRegion.initAt(session, @src()) catch |err| {
                    self.regions.destroy(region);
                    return err;
                };
                self.jobs.items[index].region = region;
                self.jobs.items[index].state = .running;
                self.beginComponent(session, index, region) catch |err| try self.declineComponent(session, index, err);
                continue;
            }
            const region = job.region.?;
            const done = region.solveStep(false) catch |err| {
                if (err == error.OutOfMemory) return err;
                if (self.restart) |root| self.restartComponent(session, root) else try self.declineComponent(session, index, err);
                continue;
            };
            if (self.restart) |root| {
                self.restartComponent(session, root);
                continue;
            }
            if (!done) continue;
            if (session.summary_exhausted) {
                try self.declineComponent(session, index, error.TypeLimit);
                continue;
            }
            self.publishComponent(session, index, region) catch |err| {
                try self.declineComponent(session, index, err);
                continue;
            };
        }
    }
    fn member(self: *const CallSummaries, root: usize, index: usize) bool {
        return self.components.component(@intCast(index)) == self.components.component(@intCast(root));
    }
    fn beginComponent(self: *CallSummaries, session: *Session, root: usize, region: *ClosureRegion) ClosureRegion.RegionError!void {
        for (0..self.jobs.items.len) |index| {
            if (!self.member(root, index)) continue;
            const key = self.jobs.items[index].key;
            if (key.lexical != 0) try self.active_lexical.put(session.allocator, key.lexical, index) else try self.active.put(session.allocator, key.target, index);
            self.jobs.items[index].state = if (index == root) .running else .waiting;
            self.jobs.items[index].scope = try region.beginSummary(key);
        }
        // Edges are replayed between fresh member scopes, never old solver IDs.
        for (self.components.edges.items) |edge| {
            if (self.member(root, edge.from) and self.member(root, edge.to)) try region.bodyEdge(self.jobs.items[edge.from].scope.?, self.jobs.items[edge.to].scope.?);
        }
    }
    fn restartComponent(self: *CallSummaries, session: *Session, root: usize) void {
        session.discardDiagnostic();
        for (0..self.jobs.items.len) |index| {
            if (!self.member(root, index)) continue;
            const job = &self.jobs.items[index];
            std.debug.assert(job.state != .complete and job.state != .declined);
            if (job.region) |region| {
                region.deinit();
                self.regions.destroy(region);
                job.region = null;
            }
            if (job.key.lexical != 0) _ = self.active_lexical.remove(job.key.lexical) else _ = self.active.remove(job.key.target);
            job.state = if (index == root) .queued else .waiting;
            job.scope = null;
        }
        var keep: usize = 0;
        for (self.stack.items) |index| if (!self.member(root, index)) {
            self.stack.items[keep] = index;
            keep += 1;
        };
        self.stack.items.len = keep;
        self.stack.appendAssumeCapacity(root);
        self.restart = null;
        session.component_restarts += 1;
    }
    fn declineComponent(self: *CallSummaries, session: *Session, root: usize, err: ClosureRegion.RegionError) ClosureRegion.RegionError!void {
        if (err == error.OutOfMemory) return err;
        session.discardDiagnostic();
        for (0..self.jobs.items.len) |index| if (self.member(root, index)) self.finish(session, index, 0);
    }
    fn publishComponent(self: *CallSummaries, session: *Session, root: usize, region: *ClosureRegion) ClosureRegion.RegionError!void {
        if (!region.allConstraintsSolved()) return self.declineComponent(session, root, error.UnresolvedType);
        try region.closeRetainedRows();
        const StagedResult = struct { index: usize, evidence: type_evidence.Id };
        var staged: std.ArrayList(StagedResult) = .empty;
        defer staged.deinit(session.allocator);
        for (0..self.jobs.items.len) |index| {
            if (!self.member(root, index)) continue;
            const job = self.jobs.items[index];
            const source = region.scratch.sources.items[job.scope.?];
            const parameters = if (job.key.lexical != 0) session.specializations.lexical_inputs.inputs.items[job.key.lexical - 1].parameters else session.units[source.owner].body(source.binding).?.parameters.len;
            _ = try region.closeRetainedFunctionRows(source.root, parameters);
            const result = try region.project(source.root);
            if (result == 0 or !try region.summaryValue(result, 0)) return self.declineComponent(session, root, error.UnresolvedType);
            try staged.append(session.allocator, .{ .index = index, .evidence = result });
        }
        // All member results are owned and complete before the allocation-free
        // commit. Joint jobs retain private judgments, not global proof facts.
        if (staged.items.len == 1 and !region.source_interface) try region.publishValidatedCalls();
        if (session.principal_reads) |reads| for (staged.items) |result| {
            if (observation(session, self.jobs.items[result.index].key, result.evidence)) |fact| try reads.summaryPublish(session.allocator, fact);
        };
        if (staged.items.len > 1) session.component_members_published += staged.items.len;
        for (staged.items) |result| self.finish(session, result.index, result.evidence);
    }
};

const RegionStorage = struct {
    region_arena_pool: region_arena.Pool,
    principal_source_owners: @import("source_owners.zig").Cache = .{},
    callable_definitions: std.AutoHashMapUnmanaged(ClosureRegion.DefinitionKey, core.BindingId) = .empty,
    callable_definition_units: std.AutoHashMapUnmanaged(usize, void) = .empty,
    fn init(allocator: Allocator) RegionStorage {
        return .{ .region_arena_pool = .init(allocator) };
    }
    fn deinit(self: *RegionStorage, allocator: Allocator) void {
        self.region_arena_pool.deinit();
        self.principal_source_owners.deinit(allocator);
        self.callable_definitions.deinit(allocator);
        self.callable_definition_units.deinit(allocator);
    }
};
const SpecializationCaches = struct {
    call_summaries: CallSummaries = .{},
    lexical_inputs: lexical_capture_inputs.Cache = .{},
    canonical_specializations: @import("canonical_specialization.zig").Cache = .{},
    body_recipes: body_recipe.Cache = .{},
    closed_source_types: @import("closed_source_types.zig").Facts = .{},
    validated_calls: std.AutoHashMapUnmanaged(CallProofKey, void) = .empty,
    plain_nominals: std.AutoHashMapUnmanaged(u64, bool) = .empty,
    fn deinit(self: *SpecializationCaches, session: *Session) void {
        self.call_summaries.deinit(session);
        self.lexical_inputs.deinit(session.allocator);
        self.canonical_specializations.deinit(session.allocator);
        self.body_recipes.deinit(session.allocator);
        self.closed_source_types.deinit(session.allocator);
        self.validated_calls.deinit(session.allocator);
        self.plain_nominals.deinit(session.allocator);
    }
};
const RetainedRecords = struct {
    constant_records: std.ArrayList(@import("../reuse/constant_receipt.zig").Record) = .empty,
    specialization_receipts: std.ArrayList(receipt.Record) = .empty,
    source_suspensions: std.ArrayList(SourceSuspension) = .empty,
    fn deinit(self: *RetainedRecords, allocator: Allocator) void {
        for (self.constant_records.items) |*record| record.deinit(allocator);
        self.constant_records.deinit(allocator);
        for (self.specialization_receipts.items) |*record| record.deinit(allocator);
        self.specialization_receipts.deinit(allocator);
        self.source_suspensions.deinit(allocator);
    }
};

pub const Session = struct {
    pub const InferenceStage = @import("../work_counters.zig").InferenceStage;
    pub const StageScope = struct {
        session: *Session,
        previous: InferenceStage,
        pub fn deinit(self: StageScope) void {
            self.session.inference_stage = self.previous;
        }
    };
    pub fn enterInferenceStage(self: *Session, stage: InferenceStage) StageScope {
        const result: StageScope = .{ .session = self, .previous = self.inference_stage };
        self.inference_stage = stage;
        return result;
    }
    inference_stage: InferenceStage = .general,
    dense_unit_ids: bool = false,
    retained: RetainedRecords = .{},
    specializations: SpecializationCaches = .{},
    regions: RegionStorage,
    storage: value_storage.Store,
    semantic_io: ?std.Io = null,
    /// Zero keeps ordinary inference. An explicit policy enables joined jobs.
    semantic_component_workers: u8 = 0,
    /// Private operational bound; it does not alter a canonical Options key.
    semantic_job_budget: ?usize = null,
    timing: ?*@import("../backend/backend_timing.zig").Work = null,
    split_attempts: usize = 0,
    split_accepted: usize = 0,
    split_declined: usize = 0,
    summary_eligibility_visits: usize = 0,
    inquiry_regions: usize = 0,
    constant_inference_serial: u64 = 0,
    summary_transitions: usize = 0,
    summary_exhausted: bool = false,
    summary_graph_work: usize = 0,
    component_restarts: usize = 0,
    component_members_published: usize = 0,
    reuse_principal_graphs: bool = true,
    principal_graph_builds: usize = 0,
    principal_graph_imports: usize = 0,
    principal_graph_deferred: usize = 0,
    principal_graph_nodes: usize = 0,
    principal_graph_edges: usize = 0,
    counters: @import("../work_counters.zig").Counters = .{},
    closed_source_imports: usize = 0,
    closed_source_reused: usize = 0,
    evidence_import_requests: usize = 0,
    evidence_import_reused: usize = 0,
    retain_constant_receipts: bool = false,
    minimum_constant_steps: usize = @import("../reuse/constant_receipt.zig").minimum_steps,
    constant_receipt_retry: bool = false,
    constant_provider: ?@import("../reuse/constant_receipt.zig").Provider = null,
    constant_recorder: ?*@import("../reuse/constant_receipt.zig").Recorder = null,
    constant_stats: @import("../reuse/constant_receipt.zig").Stats = .{},
    retain_specialization_receipts: bool = false,
    specialization_provider: ?receipt.Provider = null,
    receipt_tape: ?*receipt.Tape = null,
    member_trace: ?*receipt.MemberTrace = null,
    refinement_observation: ?*@import("../reuse/refinement_receipt.zig").Observation = null,
    principal_provider: ?PrincipalProvider = null,
    principal_graph_provider: ?PrincipalGraphProvider = null,
    principal_regions: usize = 0,
    principal_recordings: u64 = 0,
    principal_reads: ?*principal_inputs.Recorder = null,
    /// The recorder a detached principal-graph description still reports
    /// plain-nominal memo reads and publications to.
    principal_plain_reads: ?*principal_inputs.Recorder = null,
    owned_diagnostic_message: []u8 = &.{},
    /// Borrowed only during emission. Core owns the low-level API fallback;
    /// project origin policy is explicit and belongs to the current consumer.
    diagnostic_context: DiagnosticContext = .{},
    /// Request-scoped provenance; never participates in specialization identity.
    specialization_origin: ?SourceLocation = null,
    proofs: ProofStats = .{},
    allocator: Allocator,
    units: []const core.Module,
    providers: provider_chain.Store,
    /// Live invocation-local capability values; never exported as receipt authority.
    capability_scopes: std.ArrayList(ValueId) = .empty,
    options: Options = .{},
    closed_constructor: bool = false,
    steps: usize = 0,
    constant_value_debt: usize = 0,
    constant_child_debt: usize = 0,
    diagnostic: ?Diagnostic = null,
    traced_bodies: usize = 0,
    traced_nodes: usize = 0,
    binding_offsets: []usize,
    node_offsets: []usize,
    slots: []Slot,
    /// Allocated by the first dependency trace; `node_count` entries.
    visited_nodes: []bool = &.{},
    node_count: usize = 0,
    /// Offsets and field locations belong to the parent of initShared.
    borrowed_tables: bool = false,
    pending: std.ArrayList(Target) = .empty,
    draining_pending: bool = false,
    indexed_region: ?*IndexedRegion = null,
    ragged_region: ?*RaggedRegion = null,
    ragged_probe_limit: usize = ragged.probe_limit,
    ragged_reserved_children: usize = 0,
    source_producer: ?Target = null,
    generator_origin: ?@import("../check/staging_origins.zig").Source = null,
    staging_trace: @import("../check/staging_origins.zig").Trace = .{},
    implementation_proofs: @import("implementation_evidence.zig").Store,
    associated_remaining: usize = 1_000_000,
    has_implementations: bool = false,
    has_generative_sources: bool = false,
    break_values: std.ArrayList(ValueId) = .empty,
    field_locations: std.AutoHashMapUnmanaged(FieldKey, FieldLocation) = .empty,
    request_cells: std.ArrayList(RequestCell) = .empty,
    request_handlers: std.ArrayList(RequestHandler) = .empty,
    request_owner: u32 = 0,
    demanded: usize = 0,
    depth: usize = 0,
    call_depth: usize = 0,

    fn recordingConstant(self: *const Session) bool {
        const recorder = self.constant_recorder orelse return false;
        return recorder.eligible;
    }
    fn declineConstant(self: *Session) void {
        if (self.constant_recorder) |recorder| recorder.eligible = false;
        self.constant_recorder = null;
    }
    fn observeConstantInference(self: *Session) void {
        self.constant_inference_serial +|= 1;
        self.declineConstant();
    }

    /// Replayed constants retain the ordinary resource charges of temporary
    /// values whose immutable result no longer needs their physical storage.
    pub fn constantValueCount(self: *const Session) usize {
        return self.storage.values.items.len +| self.constant_value_debt;
    }
    pub fn constantChildCount(self: *const Session) usize {
        return self.storage.children.items.len +| self.constant_child_debt;
    }
    fn summaryLimit(self: *const Session) usize {
        return @min(self.options.max_summary_transitions, self.semantic_job_budget orelse self.options.max_summary_transitions);
    }

    fn summaryCharge(self: *Session, count: usize) bool {
        if (self.summary_exhausted) return false;
        if (count > self.summaryLimit() -| self.summary_transitions) {
            self.summary_exhausted = true;
            return false;
        }
        self.summary_transitions += count;
        return true;
    }

    pub fn init(allocator: Allocator, units: []const core.Module) Allocator.Error!Session {
        const binding_offsets = try allocator.alloc(usize, units.len);
        errdefer allocator.free(binding_offsets);
        const node_offsets = try allocator.alloc(usize, units.len);
        errdefer allocator.free(node_offsets);
        var has_implementations = false;
        var has_generative_sources = false;
        var dense_unit_ids = true;
        var binding_count: usize = 0;
        var node_count: usize = 0;
        for (units, 0..) |module, index| {
            dense_unit_ids = dense_unit_ids and (module.unit == 0 or module.unit == index + 1);
            has_implementations = has_implementations or module.implementations.len != 0 or module.member_templates.len != 0;
            has_generative_sources = has_generative_sources or @import("../reuse/source_value_template.zig").moduleGenerative(&module);
            binding_offsets[index] = binding_count;
            node_offsets[index] = node_count;
            binding_count = std.math.add(usize, binding_count, module.bindings.len) catch return error.OutOfMemory;
            node_count = std.math.add(usize, node_count, module.nodes.len) catch return error.OutOfMemory;
        }
        const slots = try allocator.alloc(Slot, binding_count);
        errdefer allocator.free(slots);
        @memset(slots, .{});
        var storage = try value_storage.Store.init(allocator);
        errdefer storage.deinit(allocator);
        var field_locations: std.AutoHashMapUnmanaged(FieldKey, FieldLocation) = .empty;
        errdefer field_locations.deinit(allocator);
        var families: std.AutoHashMapUnmanaged(u64, void) = .empty;
        defer families.deinit(allocator);
        // Count first so both tables are sized once instead of rehashing as
        // they grow; the first owner of each family supplies its fields.
        const First = struct { module: usize, nominal: usize, family: u64 };
        var firsts: std.ArrayList(First) = .empty;
        defer firsts.deinit(allocator);
        var nominal_count: usize = 0;
        for (units) |module| nominal_count += module.nominals.len;
        try families.ensureTotalCapacity(allocator, std.math.cast(u32, nominal_count) orelse return error.OutOfMemory);
        try firsts.ensureTotalCapacityPrecise(allocator, nominal_count);
        var field_count: usize = 0;
        for (units, 0..) |module, index| {
            const unit_id: u32 = if (module.unit != 0) module.unit else @intCast(index + 1);
            for (module.nominals, 0..) |nominal, nominal_index| {
                if (nominal.identity.decl == 0) continue;
                const family = (@as(u64, if (nominal.identity.unit == 0) unit_id else nominal.identity.unit) << 32) | nominal.identity.decl;
                if (families.getOrPutAssumeCapacity(family).found_existing) continue;
                firsts.appendAssumeCapacity(.{ .module = index, .nominal = nominal_index, .family = family });
                for (module.extra[nominal.constructors.start..][0..nominal.constructors.len]) |constructor_index| {
                    const constructor = module.constructor(constructor_index);
                    if (constructor.payload == 0) continue;
                    const payload = module.types.node(constructor.payload);
                    if (payload.tag == .record) field_count += payload.b;
                }
            }
        }
        try field_locations.ensureTotalCapacity(allocator, std.math.cast(u32, field_count) orelse return error.OutOfMemory);
        for (firsts.items) |first| {
            const module = &units[first.module];
            const nominal = module.nominals[first.nominal];
            for (module.extra[nominal.constructors.start..][0..nominal.constructors.len]) |constructor_index| {
                const constructor = module.constructor(constructor_index);
                if (constructor.payload == 0) continue;
                const payload = module.types.node(constructor.payload);
                if (payload.tag != .record) continue;
                for (0..payload.b) |field| field_locations.putAssumeCapacity(.{ .family = first.family, .tag = constructor.tag, .name = module.types.recordField(payload, field).name }, .{ .field = @intCast(field), .len = payload.b });
            }
        }
        return .{ .associated_remaining = @import("../inference_limits.zig").configured(), .storage = storage, .regions = .init(allocator), .allocator = allocator, .units = units, .dense_unit_ids = dense_unit_ids, .providers = provider_chain.Store.init(allocator), .binding_offsets = binding_offsets, .node_offsets = node_offsets, .slots = slots, .node_count = node_count, .field_locations = field_locations, .implementation_proofs = .{ .allocator = allocator }, .has_implementations = has_implementations, .has_generative_sources = has_generative_sources };
    }
    /// A private session over exactly `parent.units`. The facts Session.init
    /// derives from those immutable units (the implementation and generative
    /// source probes, offsets and nominal field locations) are borrowed from
    /// the parent, which must outlive it and leave them unchanged; all
    /// evaluation state starts empty, as from Session.init.
    pub fn initShared(allocator: Allocator, parent: *const Session) Allocator.Error!Session {
        const slots = try allocator.alloc(Slot, parent.slots.len);
        errdefer allocator.free(slots);
        @memset(slots, .{});
        var storage = try value_storage.Store.init(allocator);
        errdefer storage.deinit(allocator);
        return .{ .associated_remaining = @import("../inference_limits.zig").configured(), .storage = storage, .regions = .init(allocator), .allocator = allocator, .units = parent.units, .dense_unit_ids = parent.dense_unit_ids, .providers = provider_chain.Store.init(allocator), .binding_offsets = parent.binding_offsets, .node_offsets = parent.node_offsets, .slots = slots, .node_count = parent.node_count, .borrowed_tables = true, .inference_stage = parent.inference_stage, .field_locations = parent.field_locations, .implementation_proofs = .{ .allocator = allocator }, .has_implementations = parent.has_implementations, .has_generative_sources = parent.has_generative_sources };
    }
    pub fn deinit(self: *Session) void {
        self.retained.deinit(self.allocator);
        self.specializations.deinit(self);
        self.regions.deinit(self.allocator);
        self.implementation_proofs.deinit();
        self.allocator.free(self.owned_diagnostic_message);
        if (!self.borrowed_tables) {
            self.allocator.free(self.binding_offsets);
            self.allocator.free(self.node_offsets);
            self.field_locations.deinit(self.allocator);
        }
        self.allocator.free(self.slots);
        self.allocator.free(self.visited_nodes);
        self.pending.deinit(self.allocator);
        self.storage.deinit(self.allocator);
        self.providers.deinit();
        self.capability_scopes.deinit(self.allocator);
        self.request_cells.deinit(self.allocator);
        self.request_handlers.deinit(self.allocator);
        self.break_values.deinit(self.allocator);
        self.* = undefined;
    }
    pub fn principalQueryStorage(self: *const Session) struct { source_description: @import("../reuse/semantic_query_table.zig").Storage, open_residual: @import("../reuse/semantic_query_table.zig").Storage } {
        return .{ .source_description = self.specializations.call_summaries.principals.storage(), .open_residual = self.specializations.call_summaries.normalized_principals.storage() };
    }
    pub fn valueInfo(self: *const Session, id: ValueId) ValueInfo {
        return self.storage.values.items[id];
    }
    pub fn valueChildren(self: *const Session, id: ValueId) []const ValueId {
        const info = self.valueInfo(id);
        return self.storage.children.items[info.start..][0..info.len];
    }
    pub fn providerInfo(self: *const Session, id: ValueId) provider_chain.Provider {
        const info = self.valueInfo(id);
        std.debug.assert(info.kind == .provider and info.len == 1);
        return .{ .operation = info.bits, .implementation = self.valueChildren(id)[0] };
    }
    pub fn stateProviderInfo(self: *const Session, id: ValueId) provider_chain.StateProvider {
        const info = self.valueInfo(id);
        std.debug.assert(info.kind == .state_provider and info.len == 1);
        return .{ .read = info.bits, .write = @intCast(info.nominal), .initial = self.valueChildren(id)[0] };
    }
    pub fn valueScalar(self: *const Session, id: ValueId) ?Value {
        const info = self.valueInfo(id);
        return if (info.kind == .scalar) .{ .scalar = info.scalar, .bits = info.bits } else null;
    }
    pub fn constructorTag(self: *const Session, id: ValueId) ?u32 {
        const info = self.valueInfo(id);
        return if (info.kind == .nominal) info.bits else null;
    }
    pub fn closureInfo(self: *const Session, id: ValueId) ClosureValue {
        const info = self.valueInfo(id);
        std.debug.assert(info.kind == .closure or info.kind == .suspension);
        return self.storage.closures.items[info.bits];
    }
    pub fn suspensionInfo(self: *const Session, id: ValueId) ClosureValue {
        std.debug.assert(self.valueInfo(id).kind == .suspension);
        return self.closureInfo(id);
    }
    pub fn suspensionCached(self: *const Session, id: ValueId) ?ValueId {
        const info = self.valueInfo(id);
        std.debug.assert(info.kind == .suspension);
        const memo = self.storage.demands.items[@intCast(info.nominal)];
        return if (memo.state == .cached) memo.value else null;
    }
    pub fn singleSourceSuspension(self: *const Session, producer: core.BindingRef, unit: u32, node: core.Id) ?ValueId {
        if (self.principal_reads) |reads| reads.invalidate(.suspension);
        // Startup creation history is not part of a completed specialization
        // receipt. A future caller under that tape must take the fresh path.
        if (self.receipt_tape) |tape| tape.unknown = true;
        var found: ?ValueId = null;
        for (self.retained.source_suspensions.items) |source| {
            if (!std.meta.eql(source.producer, producer) or source.unit != unit or source.node != node) continue;
            if (found != null) return null;
            found = source.value;
        }
        return found;
    }
    pub fn valueEvidence(self: *const Session, id: ValueId) type_evidence.Id {
        return self.storage.value_evidence.items[id];
    }
    pub fn evidenceStore(self: *Session) *type_evidence.Store {
        return &self.storage.evidence;
    }
    pub fn evidenceView(self: *const Session) type_evidence.View {
        return self.storage.evidence.view();
    }
    /// Names follow storage slots, independently of semantic record equality.
    pub fn recordFieldNames(self: *const Session, id: ValueId) []const u32 {
        const span = self.storage.record_layouts.items[self.storage.value_records.items[id]];
        return self.storage.field_names.items[span.start..][0..span.len];
    }
    /// Specialize retained principal type graphs, including captured closure
    /// correspondences. This executes no core body and never changes an alias.
    pub fn specializeClosure(self: *Session, value_: ValueId, expected: type_evidence.Id) Error!ValueId {
        if (self.valueInfo(value_).kind != .closure) return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        return self.specializeRetained(value_, expected);
    }
    /// Infer a retained closure's concrete source proof without executing it.
    /// The selected header owns its evidence; the original alias is unchanged.
    pub fn inferClosure(self: *Session, value_: ValueId) Error!ValueId {
        if (self.valueInfo(value_).kind != .closure) return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        return (try self.inferClosureMode(value_, false)) orelse self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
    }
    /// A waiting demand keeps its memo unchanged. Only its complete retained
    /// body and capture proof can supply an unselected representation row.
    pub fn inferSuspension(self: *Session, value_: ValueId) Error!ValueId {
        if (self.valueInfo(value_).kind != .suspension) return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        return (try self.inferClosureMode(value_, false)) orelse self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
    }
    /// A generic public interface is an export rejection, distinct from an
    /// unresolved body or retained capture proof. No header is published here.
    pub fn inferEntryClosure(self: *Session, value_: ValueId) Error!?ValueId {
        return self.inferClosureMode(value_, true);
    }
    fn inferClosureMode(self: *Session, value_: ValueId, entry_interface: bool) Error!?ValueId {
        const outer = self.constant_recorder orelse return self.inferClosureModeInner(value_, entry_interface);
        try outer.beforeRead(self.allocator, self);
        self.constant_recorder = null;
        defer self.constant_recorder = outer;
        errdefer outer.eligible = false;
        const selected = try self.inferClosureModeInner(value_, entry_interface);
        var kind: @TypeOf(@as(@import("../reuse/constant_receipt.zig").Query, undefined).kind) = .inferred;
        if (entry_interface) kind = .entry;
        try outer.query(self.allocator, self, .{ .kind = kind, .input = value_, .selected = selected orelse 0 });
        return selected;
    }
    pub fn receiptQuery(self: *Session, query: @import("../reuse/constant_receipt.zig").Query) Error!?ValueId {
        return switch (query.kind) {
            .inferred => self.inferClosureMode(query.input, false),
            .entry => self.inferClosureMode(query.input, true),
            .specialized => try self.specializeRetained(query.input, query.expected),
            .array_member => blk: {
                const target_ = try self.external(try self.target(null, query.target));
                const body = self.units[target_.unit].body(target_.binding) orelse return self.fail(target_.unit, .{ .start = 0, .end = 0 }, .unsupported);
                // Caller source locations affect diagnostics only. A failed
                // barrier discards this attempt and evaluates at the real site.
                break :blk try self.partialArrayMember(target_.unit, body.root, target_, query.input, query.expected);
            },
            .judgment => self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported),
            .source => self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported),
        };
    }
    pub fn receiptJudgment(self: *Session, query: *const @import("../reuse/constant_receipt.zig").Judgment, expected: type_evidence.Id) Error!ReceiptJudgment {
        const owner = self.findUnit(query.unit, null) orelse return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        if (query.kind == .body) return .{ .solved = try self.solveEvidenceOwnedCodeInner(owner, query.source, query.root, query.closed_rows, query.scheme, .{ .semantic = expected }, query.inputs.types, query.inputs.rows, null) };
        var frame: Frame = .{};
        defer frame.deinit(self.allocator);
        try frame.mappings.appendSlice(self.allocator, query.inputs.types);
        try frame.row_mappings.appendSlice(self.allocator, query.inputs.rows);
        var matched = true;
        switch (query.kind) {
            .match, .covariant => {
                const producer = self.findUnit(query.producer, null) orelse return self.failNode(owner, query.source, .unsupported);
                if (query.kind == .match) matched = try self.matchTypeInner(owner, query.source, producer, query.root, expected, &frame.mappings, &frame.row_mappings) else matched = try self.matchCovariantTypeInner(owner, query.source, producer, query.root, expected, &frame.mappings, &frame.row_mappings);
            },
            .scheme => try self.validateSchemeInner(owner, query.source, query.scheme, &frame, query.allow_remaining),
            .body => unreachable,
        }
        const types_ = try frame.mappings.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(types_);
        const rows = try frame.row_mappings.toOwnedSlice(self.allocator);
        return .{ .matched = matched, .solved = .{ .types = types_, .rows = rows } };
    }
    fn inferClosureModeInner(self: *Session, value_: ValueId, entry_interface: bool) Error!?ValueId {
        self.observeConstantInference();
        if (self.principal_reads) |reads| reads.invalidate(.specialize);
        if (self.receipt_tape) |tape| tape.nested = true;
        const kind = self.valueInfo(value_).kind;
        if (kind != .closure and (kind != .suspension or entry_interface)) return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        const metadata = self.closureInfo(value_);
        const owner = self.findUnit(metadata.unit, null) orelse return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        const module = &self.units[owner];
        const span = switch (metadata.origin) {
            .anonymous => module.span(module.closures[metadata.identity].body),
            .named => (module.body(metadata.identity) orelse return self.fail(owner, .{ .start = 0, .end = 0 }, .unsupported)).span,
            .constructor, .primitive, .operation => core.Span{ .start = 0, .end = 0 },
        };
        // Specialization requires nonzero evidence, leaving this key for inference.
        const key: ViewKey = .{ .value = value_, .evidence = 0, .entry_interface = entry_interface };
        if (self.storage.specialized_closures.get(key)) |existing| return existing;
        const mode: @import("canonical_specialization.zig").Mode = if (entry_interface) .entry else .inferred;
        var canonical = try self.specializations.canonical_specializations.key(self, value_);
        defer if (canonical) |*input| input.deinit(self.allocator);
        if (canonical) |*input| if (try self.specializations.canonical_specializations.lookup(self, input, 0, mode)) |selected| return selected;
        const values_before = self.storage.values.items.len;
        const children_before = self.storage.children.items.len;
        const steps_before = self.steps;
        var tape: receipt.Tape = .{};
        defer tape.deinit(self.allocator);
        const previous_tape = self.receipt_tape;
        if (canonical != null) self.receipt_tape = &tape;
        defer self.receipt_tape = previous_tape;
        try self.storage.specialized_closures.ensureUnusedCapacity(self.allocator, 1);
        var region = ClosureRegion.initAt(self, @src()) catch return error.OutOfMemory;
        defer region.deinit();
        const inferred: ?ValueId = if (entry_interface)
            region.inferEntry(value_) catch |err| return self.evidenceFailure(owner, span, err)
        else
            region.infer(value_) catch |err| return self.evidenceFailure(owner, span, err);
        if (inferred) |selected| {
            try self.cacheSpecialization(key, selected);
            if (canonical) |input| {
                var record = try tape.finish(self.allocator, .{
                    .input = value_,
                    .expected = 0,
                    .selected = selected,
                    .options = self.options,
                    .depth = self.depth,
                    .values_before = values_before,
                    .children_before = children_before,
                    .values_added = self.storage.values.items.len - values_before,
                    .children_added = self.storage.children.items.len - children_before,
                    .steps = self.steps - steps_before,
                    .collected = tape.collected,
                    .source_scopes = region.scratch.sources.items.len,
                    .solver_nodes = region.solver.nodes.items.len,
                    .complete = region.allConstraintsSolved() and self.steps == steps_before and !region.source_interface and !region.retain_selected,
                    .sources = &.{},
                    .scalar_reads = &.{},
                    .call_reads = &.{},
                    .call_publications = &.{},
                    .views = &.{},
                    .plain_facts = &.{},
                });
                defer record.deinit(self.allocator);
                canonical = null;
                try self.specializations.canonical_specializations.remember(self, input, record, mode);
            }
        }
        return inferred;
    }
    pub fn specializeSuspension(self: *Session, value_: ValueId, expected: type_evidence.Id) Error!ValueId {
        if (self.valueInfo(value_).kind != .suspension) return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        return self.specializeRetained(value_, expected);
    }
    fn specializeRetained(self: *Session, value_: ValueId, expected: type_evidence.Id) Error!ValueId {
        const outer = self.constant_recorder orelse return self.specializeRetainedInner(value_, expected);
        try outer.beforeRead(self.allocator, self);
        self.constant_recorder = null;
        defer self.constant_recorder = outer;
        errdefer outer.eligible = false;
        const selected = try self.specializeRetainedInner(value_, expected);
        try outer.query(self.allocator, self, .{ .kind = .specialized, .input = value_, .expected = expected, .selected = selected });
        return selected;
    }
    fn specializeRetainedInner(self: *Session, value_: ValueId, expected: type_evidence.Id) Error!ValueId {
        self.observeConstantInference();
        const metadata = self.closureInfo(value_);
        const owner = self.findUnit(metadata.unit, null) orelse return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        const module = &self.units[owner];
        if (metadata.origin == .named and self.has_implementations) {
            const reference: core.BindingRef = .{ .unit = metadata.unit, .binding = metadata.identity };
            const selected = try self.selectTemplate(owner, 0, reference, expected);
            if (!std.meta.eql(reference, selected)) {
                try self.prepare(selected);
                const selected_value = try self.constant(try self.external(try self.target(owner, selected)));
                return self.specializeRetained(selected_value, expected);
            }
        }
        const span = switch (metadata.origin) {
            .anonymous => module.span(module.closures[metadata.identity].body),
            .named => (module.body(metadata.identity) orelse return self.fail(owner, .{ .start = 0, .end = 0 }, .unsupported)).span,
            .constructor, .primitive, .operation => core.Span{ .start = 0, .end = 0 },
        };
        const expected_kind: type_evidence.Tag = if (self.valueInfo(value_).kind == .suspension) .demand else .function;
        if (expected == 0 or self.storage.evidence.node(expected).tag != expected_kind) return self.fail(owner, span, .unsupported);
        const key: ViewKey = .{ .value = value_, .evidence = expected };
        if (self.principal_reads) |reads| reads.invalidate(.specialize);
        if (self.receipt_tape) |tape| tape.nested = true;
        if (self.storage.specialized_closures.get(key)) |existing| return existing;
        if (self.receipt_tape == null) if (self.specialization_provider) |provider| if (try provider.lookup(provider.context, self, value_, expected)) |selected| return selected;
        var canonical = try self.specializations.canonical_specializations.key(self, value_);
        defer if (canonical) |*input| input.deinit(self.allocator);
        if (canonical) |*input| if (try self.specializations.canonical_specializations.lookup(self, input, expected, .selected)) |selected| return selected;
        try self.storage.specialized_closures.ensureUnusedCapacity(self.allocator, 1);
        const values_before = self.storage.values.items.len;
        const children_before = self.storage.children.items.len;
        const steps_before = self.steps;
        var tape: receipt.Tape = .{};
        defer tape.deinit(self.allocator);
        const previous_tape = self.receipt_tape;
        const recording = (self.retain_specialization_receipts or canonical != null) and previous_tape == null;
        if (recording) self.receipt_tape = &tape;
        defer self.receipt_tape = previous_tape;
        if (recording and self.retain_specialization_receipts) try self.retained.specialization_receipts.ensureUnusedCapacity(self.allocator, 1);
        var region = ClosureRegion.initAt(self, @src()) catch return error.OutOfMemory;
        defer region.deinit();
        const specialized = region.specialize(value_, expected) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Declined => return error.Declined,
            error.RequestUnwind => return error.RequestUnwind,
            error.TypeLimit, error.EvidenceLimit => return self.fail(owner, span, .constant_fuel),
            error.TypeMismatch, error.InfiniteType => return self.fail(owner, span, .type_mismatch),
            error.EffectMismatch => return self.fail(owner, span, .effect_mismatch),
            error.InfiniteEffect => return self.fail(owner, span, .infinite_effect),
            error.UnresolvedType => return self.fail(owner, span, .unsupported),
        };
        var record: ?receipt.Record = null;
        defer if (record) |*owned| owned.deinit(self.allocator);
        if (recording) record = try tape.finish(self.allocator, .{
            .input = value_,
            .expected = expected,
            .selected = specialized,
            .options = self.options,
            .depth = self.depth,
            .values_before = values_before,
            .children_before = children_before,
            .values_added = self.storage.values.items.len - values_before,
            .children_added = self.storage.children.items.len - children_before,
            .steps = self.steps - steps_before,
            .collected = tape.collected,
            .source_scopes = region.scratch.sources.items.len,
            .solver_nodes = region.solver.nodes.items.len,
            .complete = region.allConstraintsSolved() and self.steps == steps_before and !region.source_interface and !region.retain_selected and !region.complete_demand_bodies,
            .sources = &.{},
            .scalar_reads = &.{},
            .call_reads = &.{},
            .call_publications = &.{},
            .views = &.{},
            .plain_facts = &.{},
        });
        try self.cacheCompletedSpecialization(key, specialized, &region);
        if (record) |*owned| if (owned.complete) {
            // The same solved region proves the frozen capture closures, not
            // merely the outer interface. Carry those exact completed results
            // with this query's dependencies so replay need not infer them again.
            var completed: std.ArrayList(u32) = .empty;
            defer completed.deinit(self.allocator);
            var frozen = region.scratch.frozen.valueIterator();
            while (frozen.next()) |frozen_value| {
                if (self.valueInfo(frozen_value.*).kind != .closure or self.valueEvidence(frozen_value.*) == 0) continue;
                if (frozen_value.* == specialized and self.valueEvidence(frozen_value.*) == expected) continue;
                try completed.append(self.allocator, frozen_value.*);
            }
            std.mem.sort(u32, completed.items, {}, std.sort.asc(u32));
            var count: usize = 0;
            for (completed.items) |frozen_value| {
                if (count != 0 and completed.items[count - 1] == frozen_value) continue;
                completed.items[count] = frozen_value;
                count += 1;
            }
            completed.items.len = count;
            owned.completed_closures = try completed.toOwnedSlice(self.allocator);
        };
        if (record) |owned| {
            if (canonical) |input| {
                canonical = null;
                try self.specializations.canonical_specializations.remember(self, input, owned, .selected);
            }
            if (self.retain_specialization_receipts) {
                self.retained.specialization_receipts.appendAssumeCapacity(owned);
                record = null;
            }
        }
        return specialized;
    }
    fn cacheSpecialization(self: *Session, key: ViewKey, selected: ValueId) Allocator.Error!void {
        // Nested refinement may consume the capacity reserved before the region.
        try self.storage.specialized_closures.put(self.allocator, key, selected);
    }
    fn cacheCompletedSpecialization(self: *Session, key: ViewKey, selected: ValueId, region: *const ClosureRegion) Allocator.Error!void {
        // Every frozen child owns its solved capture graph. Publish fixed points
        // only after all obligations are checked; a typed view is not a proof.
        // Nested refinement may have consumed the early map reservation.
        const complete = region.allConstraintsSolved();
        try self.storage.specialized_closures.ensureUnusedCapacity(self.allocator, if (complete) 2 + region.scratch.frozen.count() else 1);
        self.storage.specialized_closures.putAssumeCapacity(key, selected);
        if (!complete) return;
        self.storage.specialized_closures.putAssumeCapacity(.{ .value = selected, .evidence = key.evidence }, selected);
        var frozen = region.scratch.frozen.valueIterator();
        while (frozen.next()) |value_| {
            const kind = self.valueInfo(value_.*).kind;
            if (kind != .closure and kind != .suspension) continue;
            self.storage.specialized_closures.putAssumeCapacity(.{ .value = value_.*, .evidence = self.valueEvidence(value_.*) }, value_.*);
        }
    }
    /// Reconstruct the source-owned public interface before ordinary evaluation.
    /// The region may retain unresolved staging obligations; it never reads or
    /// publishes an evaluated constant or a caller-constrained closure header.
    pub fn sourceInterface(self: *Session, reference: core.BindingRef) Error!SourceInterface {
        const outer = self.constant_recorder orelse return self.sourceInterfaceInner(reference);
        try outer.beforeRead(self.allocator, self);
        self.constant_recorder = null;
        defer self.constant_recorder = outer;
        errdefer outer.eligible = false;
        const result = try self.sourceInterfaceInner(reference);
        try outer.query(self.allocator, self, .{ .kind = .source, .target = reference, .result = result });
        return result;
    }
    fn sourceInterfaceInner(self: *Session, reference: core.BindingRef) Error!SourceInterface {
        self.observeConstantInference();
        const resolved = try self.external(try self.target(null, reference));
        const module = &self.units[resolved.unit];
        const body = module.body(resolved.binding) orelse return self.fail(resolved.unit, module.binding(resolved.binding).span, .unsupported);
        var region = ClosureRegion.initAt(self, @src()) catch return error.OutOfMemory;
        defer region.deinit();
        return region.sourceInterface(resolved, body) catch |err| {
            if (err == error.OutOfMemory or !region.principal_only_used) return self.evidenceFailure(resolved.unit, body.span, err);
            // A delayed edge can discover a failure after later caller work.
            // Ordinary collection owns the diagnostic traversal and witnesses.
            self.discardDiagnostic();
            const sharing = self.reuse_principal_graphs;
            self.reuse_principal_graphs = false;
            defer self.reuse_principal_graphs = sharing;
            var ordinary = ClosureRegion.initAt(self, @src()) catch return error.OutOfMemory;
            defer ordinary.deinit();
            return ordinary.sourceInterface(resolved, body) catch |failed| return self.evidenceFailure(resolved.unit, body.span, failed);
        };
    }
    fn discardDiagnostic(self: *Session) void {
        self.diagnostic = null;
        self.allocator.free(self.owned_diagnostic_message);
        self.owned_diagnostic_message = &.{};
    }
    /// Returns an owned mapping array in this body's frozen variable namespace.
    /// The region reads semantic core only: it evaluates no value or capture.
    pub fn bodyEvidence(self: *Session, reference: core.BindingRef, expected: type_evidence.Id, seeds: []const type_evidence.Mapping) Error![]type_evidence.Mapping {
        const target_ = try self.external(try self.target(null, reference));
        const module = &self.units[target_.unit];
        const body = module.body(target_.binding) orelse return self.fail(target_.unit, module.binding(target_.binding).span, .unsupported);
        return self.solveEvidence(target_.unit, body.root, module.binding(target_.binding).ty, body.closed_rows, body.scheme, expected, seeds);
    }
    /// Code requirements may leave representation-neutral children unspecified.
    /// Holes live in their own graph and never enter semantic evidence storage.
    pub fn bodyEvidencePartial(self: *Session, reference: core.BindingRef, expectations: code_expectation.View, expected: code_expectation.Id, seeds: []const type_evidence.Mapping) Error![]type_evidence.Mapping {
        const target_ = try self.external(try self.target(null, reference));
        const module = &self.units[target_.unit];
        const body = module.body(target_.binding) orelse return self.fail(target_.unit, module.binding(target_.binding).span, .unsupported);
        const solved = try self.solveEvidenceOwned(target_.unit, body.root, module.binding(target_.binding).ty, body.closed_rows, body.scheme, .{ .code = .{ .view = expectations, .id = expected } }, seeds, &.{});
        self.allocator.free(solved.rows);
        self.allocator.free(solved.selected);
        return solved.types;
    }
    pub fn bodyEvidencePartialFull(self: *Session, reference: core.BindingRef, expectations: code_expectation.View, expected: code_expectation.Id, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping) Error!SolvedEvidence {
        return self.bodyEvidencePartialFullCode(reference, expectations, expected, seeds, row_seeds, null);
    }
    pub fn bodyEvidencePartialFullCode(self: *Session, reference: core.BindingRef, expectations: code_expectation.View, expected: code_expectation.Id, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping, projection: ?CodeProjection) Error!SolvedEvidence {
        const target_ = try self.external(try self.target(null, reference));
        const module = &self.units[target_.unit];
        const body = module.body(target_.binding) orelse return self.fail(target_.unit, module.binding(target_.binding).span, .unsupported);
        return self.solveEvidenceOwnedCode(target_.unit, body.root, module.binding(target_.binding).ty, body.closed_rows, body.scheme, .{ .code = .{ .view = expectations, .id = expected } }, seeds, row_seeds, projection);
    }
    /// Copy only completed primitive inputs into a fresh, independently owned
    /// probe for these same immutable units. No rich semantic IDs are copied.
    pub fn seedScalarInputs(self: *Session, current: *const Session) Error!void {
        if (self.units.ptr != current.units.ptr or self.units.len != current.units.len) return error.Declined;
        for (self.units, 0..) |module, owner| {
            // Slots are laid out by unit, then binding: visiting the completed
            // ones in that order seeds the bindings the full scan would.
            const start = self.binding_offsets[owner];
            for (current.slots[start..][0..module.bindings.len], 0..) |old, index| {
                if (old.state != .complete) continue;
                const binding = module.bindings[index];
                if (binding.kind != .global) continue;
                const body = module.body(@intCast(index)) orelse continue;
                if (body.runtime) continue;
                const offset = start + index;
                const scalar_input = current.valueScalar(old.value) orelse continue;
                const expected: u32 = switch (scalar_input.scalar) {
                    .unit => types.unit,
                    .bool => types.boolean,
                    .u32 => types.u32_type,
                    .f32 => types.f32_type,
                    else => continue,
                };
                if (current.valueEvidence(old.value) != expected) continue;
                const copied = try self.makeScalar(owner, body.root, scalar_input);
                self.slots[offset] = .{ .state = .complete, .value = copied };
            }
        }
    }
    /// Private independent proof attempt. The caller owns an isolated Session
    /// and confirms its observed inputs before publishing any closed call key.
    pub fn recheckCallProof(self: *Session, reference: core.BindingRef, expected: type_evidence.Id) Error!bool {
        const target_ = try self.external(try self.target(null, reference));
        const module = &self.units[target_.unit];
        const body = module.body(target_.binding) orelse return false;
        if (module.binding(target_.binding).kind != .global) return false;
        if (body.runtime and !body.is_function) return false;
        var region = ClosureRegion.initAt(self, @src()) catch return error.OutOfMemory;
        defer region.deinit();
        if (!(region.firstOrderArrow(expected) catch |err| return self.evidenceFailure(target_.unit, module.span(body.root), err))) return false;
        var solved = region.bodyEvidenceFull(target_.unit, body.root, module.binding(target_.binding).ty, body.closed_rows, body.scheme, .{ .semantic = expected }, &.{}, &.{}) catch |err| return self.evidenceFailure(target_.unit, module.span(body.root), err);
        defer solved.deinit(self.allocator);
        if (!region.allConstraintsSolved() or solved.selected.len != 0 or region.scratch.sources.items.len == 0) return false;
        return (region.project(region.scratch.sources.items[0].root) catch |err| return self.evidenceFailure(target_.unit, module.span(body.root), err)) == expected;
    }
    pub fn bodyEvidenceFull(self: *Session, reference: core.BindingRef, expected: type_evidence.Id, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping) Error!SolvedEvidence {
        const target_ = try self.external(try self.target(null, reference));
        const module = &self.units[target_.unit];
        const body = module.body(target_.binding) orelse return self.fail(target_.unit, module.binding(target_.binding).span, .unsupported);
        return self.solveEvidenceOwned(target_.unit, body.root, module.binding(target_.binding).ty, body.closed_rows, body.scheme, .{ .semantic = expected }, seeds, row_seeds);
    }
    /// Initializer-specific source dependencies, obtained without executing a
    /// value. Generic producers are instantiated in this region; two callers
    /// may therefore select different methods without merging their edges.
    pub fn startupDependencies(self: *Session, reference: core.BindingRef) Error!StartupDependencies {
        const target_ = try self.external(try self.target(null, reference));
        const module = &self.units[target_.unit];
        const body = module.body(target_.binding) orelse return self.fail(target_.unit, module.binding(target_.binding).span, .unsupported);
        var region = ClosureRegion.initAt(self, @src()) catch return error.OutOfMemory;
        defer region.deinit();
        region.retain_selected = true;
        var solved = region.bodyEvidenceMode(target_.unit, body.root, module.binding(target_.binding).ty, body.closed_rows, body.scheme, .{ .semantic = 0 }, &.{}, &.{}, true) catch |err| switch (err) {
            // Staged bodies can require values; the existing executable path
            // remains authoritative when no source-only proof is available.
            error.UnresolvedType => return .{ .selected = try self.allocator.alloc(core.BindingRef, 0), .complete = false },
            else => return self.evidenceFailure(target_.unit, body.span, err),
        };
        defer solved.deinit(self.allocator);
        const selected = solved.selected;
        solved.selected = &.{};
        var complete = region.startup_coverage_complete;
        for (region.scratch.constraints.items) |constraint| if (!constraint.solved) {
            complete = false;
        };
        return .{ .selected = selected, .complete = complete };
    }
    /// Skipped source and already retained callable values are not solved
    /// evidence. They certify coverage only when their actual source graph has
    /// no dispatch syntax. This walk never evaluates a value or admits a method.
    pub fn startupSelectorFree(self: *Session, owner: usize, body: core.Id) Error!bool {
        const Key = struct { owner: usize, node: core.Id };
        var work: std.ArrayList(Key) = .empty;
        defer work.deinit(self.allocator);
        var seen: std.AutoHashMapUnmanaged(Key, void) = .empty;
        defer seen.deinit(self.allocator);
        try work.append(self.allocator, .{ .owner = owner, .node = body });
        while (work.pop()) |key| {
            if (key.node == 0 or seen.contains(key)) continue;
            if (seen.count() >= self.options.max_values) return false;
            try seen.put(self.allocator, key, {});
            const module = &self.units[key.owner];
            const n = module.node(key.node);
            const selected_reference: ?core.BindingRef = switch (n.tag) {
                .reference => module.reference(key.node),
                .call => module.call(key.node).target,
                else => null,
            };
            if (selected_reference) |reference| {
                const target_ = try self.external(try self.target(key.owner, reference));
                const source = &self.units[target_.unit];
                const binding = source.binding(target_.binding);
                if (source.body(target_.binding)) |definition| {
                    if (!definition.runtime or definition.is_function) try work.append(self.allocator, .{ .owner = target_.unit, .node = definition.root });
                } else if (binding.initializer != 0) {
                    try work.append(self.allocator, .{ .owner = target_.unit, .node = binding.initializer });
                }
            }
            switch (n.tag) {
                .task, .resource_acquire, .resource_release, .usage_share, .resource_scope, .usage_borrow, .usage_read, .staging, .package_pack, .package_unpack, .associated, .project, .result_associated, .resolver_op, .update, .operation_value, .effect_scope, .proof_guard, .invalid => return false,
                .scalar => {
                    if (n.c != 0 and n.b != 0) return false;
                    for ([_]core.Id{ n.a, n.b }) |id| try work.append(self.allocator, .{ .owner = key.owner, .node = id });
                },
                .logical, .record_merge, .type_same, .apply, .effect_provider, .handle => for ([_]core.Id{ n.a, n.b }) |id| {
                    try work.append(self.allocator, .{ .owner = key.owner, .node = id });
                },
                .if_value, .if_stmt, .state_provider => for ([_]core.Id{ n.a, n.b, n.c }) |id| {
                    try work.append(self.allocator, .{ .owner = key.owner, .node = id });
                },
                .block, .suite, .product, .record, .array, .array_op, .call, .contract_method => for (module.children(key.node)) |id| {
                    try work.append(self.allocator, .{ .owner = key.owner, .node = id });
                },
                .bind => try work.append(self.allocator, .{ .owner = key.owner, .node = n.b }),
                .return_, .force, .computation => try work.append(self.allocator, .{ .owner = key.owner, .node = n.a }),
                .construct => try work.append(self.allocator, .{ .owner = key.owner, .node = n.b }),
                .pattern_bind => {
                    if (!try self.startupPatternsFree(key.owner, &.{n.a})) return false;
                    for ([_]core.Id{ n.b, n.c }) |id| try work.append(self.allocator, .{ .owner = key.owner, .node = id });
                },
                .match => {
                    for (module.matchArms(key.node)) |arm| for (module.armRows(arm)) |row| {
                        if (!try self.startupPatternsFree(key.owner, module.rowPatterns(row))) return false;
                    };
                    for (module.matchInputs(key.node)) |id| try work.append(self.allocator, .{ .owner = key.owner, .node = id });
                    for (module.matchArms(key.node)) |arm| for ([_]core.Id{ arm.guard, arm.body }) |id| {
                        try work.append(self.allocator, .{ .owner = key.owner, .node = id });
                    };
                },
                .loop => {
                    const loop_ = module.loopInfo(key.node);
                    if (!try self.startupPatternsFree(key.owner, &.{loop_.pattern})) return false;
                    for ([_]core.Id{ loop_.first, loop_.end, loop_.body }) |id| try work.append(self.allocator, .{ .owner = key.owner, .node = id });
                },
                .break_ => for (module.breakValues(key.node)) |id| {
                    try work.append(self.allocator, .{ .owner = key.owner, .node = id });
                },
                .closure, .suspend_ => try work.append(self.allocator, .{ .owner = key.owner, .node = module.closures[n.a].body }),
                .effect_reflection => {
                    const kind: checked_types.ReflectionKind = @fromBackingInt(@intCast(n.a));
                    if (kind == .count or kind == .has or kind == .same) try work.append(self.allocator, .{ .owner = key.owner, .node = n.b });
                    if (n.c != 0) try work.append(self.allocator, .{ .owner = key.owner, .node = n.c });
                },
                .request_decision => for ([_]core.Id{ n.b, n.c }) |id| {
                    try work.append(self.allocator, .{ .owner = key.owner, .node = id });
                },
                .request_loop => {
                    const request = module.requestLoopInfo(key.node);
                    if (!try self.startupPatternsFree(key.owner, &.{request.completion_pattern})) return false;
                    for ([_]core.Id{ request.computation, request.completion_body }) |id| try work.append(self.allocator, .{ .owner = key.owner, .node = id });
                    for (module.requestArms(key.node)) |arm| try work.append(self.allocator, .{ .owner = key.owner, .node = arm.callback });
                },
                .constant, .reference, .constructor_function, .primitive_function, .panic, .type_constructor => {},
            }
        }
        return true;
    }
    fn startupPatternsFree(self: *Session, owner: usize, roots: []const core.PatternId) Error!bool {
        const module = &self.units[owner];
        var work: std.ArrayList(core.PatternId) = .empty;
        defer work.deinit(self.allocator);
        var seen: std.AutoHashMapUnmanaged(core.PatternId, void) = .empty;
        defer seen.deinit(self.allocator);
        try work.appendSlice(self.allocator, roots);
        while (work.pop()) |id| {
            if (id == 0 or seen.contains(id)) continue;
            if (seen.count() >= self.options.max_values) return false;
            try seen.put(self.allocator, id, {});
            const pattern = module.pattern(id);
            switch (pattern.tag) {
                .invalid, .value => return false,
                .constructor, .record_payload => try work.append(self.allocator, pattern.b),
                .product => try work.appendSlice(self.allocator, module.patternChildren(id)),
                .wildcard, .bind, .constant => {},
            }
        }
        return true;
    }
    pub fn startupCallableComplete(self: *Session, value_: ValueId) Error!bool {
        const metadata = self.closureInfo(value_);
        const owner = self.findUnit(metadata.unit, null) orelse return false;
        const module = &self.units[owner];
        const body: core.Id = switch (metadata.origin) {
            .named => (module.body(metadata.identity) orelse return false).root,
            .anonymous => module.closures[metadata.identity].body,
            .constructor, .primitive, .operation => return true,
        };
        return self.startupSelectorFree(owner, body);
    }
    /// A catalog may describe an ordinary closure or an internal Unit thunk.
    /// Both expose an ordinary function shape to their separately keyed code.
    pub fn closureEvidence(self: *Session, unit: u32, catalog: u32, expected: type_evidence.Id, seeds: []const type_evidence.Mapping) Error![]type_evidence.Mapping {
        const owner = self.findUnit(unit, null) orelse return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        const module = &self.units[owner];
        if (catalog >= module.closures.len) return self.fail(owner, .{ .start = 0, .end = 0 }, .unsupported);
        const closure = module.closures[catalog];
        var region = ClosureRegion.initAt(self, @src()) catch return error.OutOfMemory;
        defer region.deinit();
        return region.closureEvidence(owner, closure, .{ .semantic = expected }, seeds) catch |err| return self.evidenceFailure(owner, module.span(closure.body), err);
    }
    pub fn closureEvidencePartial(self: *Session, unit: u32, catalog: u32, expectations: code_expectation.View, expected: code_expectation.Id, seeds: []const type_evidence.Mapping) Error![]type_evidence.Mapping {
        const owner = self.findUnit(unit, null) orelse return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        const module = &self.units[owner];
        if (catalog >= module.closures.len) return self.fail(owner, .{ .start = 0, .end = 0 }, .unsupported);
        const closure = module.closures[catalog];
        var region = ClosureRegion.initAt(self, @src()) catch return error.OutOfMemory;
        defer region.deinit();
        return region.closureEvidence(owner, closure, .{ .code = .{ .view = expectations, .id = expected } }, seeds) catch |err| return self.evidenceFailure(owner, module.span(closure.body), err);
    }
    pub fn closureEvidencePartialFull(self: *Session, unit: u32, catalog: u32, expectations: code_expectation.View, expected: code_expectation.Id, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping) Error!SolvedEvidence {
        const owner = self.findUnit(unit, null) orelse return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        const module = &self.units[owner];
        if (catalog >= module.closures.len) return self.fail(owner, .{ .start = 0, .end = 0 }, .unsupported);
        const closure = module.closures[catalog];
        var region = ClosureRegion.initAt(self, @src()) catch return error.OutOfMemory;
        defer region.deinit();
        return region.closureEvidenceFull(owner, closure, .{ .code = .{ .view = expectations, .id = expected } }, seeds, row_seeds) catch |err| return self.evidenceFailure(owner, module.span(closure.body), err);
    }
    pub fn closureEvidencePartialCaptures(self: *Session, unit: u32, catalog: u32, expectations: code_expectation.View, expected: code_expectation.Id, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping, captures: []const RetainedCapture) Error!SolvedEvidence {
        return self.closureEvidencePartialCapturesCode(unit, catalog, expectations, expected, seeds, row_seeds, captures, null);
    }
    pub fn closureEvidencePartialCapturesCode(self: *Session, unit: u32, catalog: u32, expectations: code_expectation.View, expected: code_expectation.Id, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping, captures: []const RetainedCapture, projection: ?CodeProjection) Error!SolvedEvidence {
        const owner = self.findUnit(unit, null) orelse return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        const module = &self.units[owner];
        if (catalog >= module.closures.len) return self.fail(owner, .{ .start = 0, .end = 0 }, .unsupported);
        const closure_ = module.closures[catalog];
        var region = ClosureRegion.initAt(self, @src()) catch return error.OutOfMemory;
        defer region.deinit();
        return region.closureEvidenceCaptures(owner, closure_, .{ .code = .{ .view = expectations, .id = expected } }, seeds, row_seeds, captures, projection) catch |err| return self.evidenceFailure(owner, module.span(closure_.body), err);
    }
    pub fn closureEvidenceFull(self: *Session, unit: u32, catalog: u32, expected: type_evidence.Id, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping) Error!SolvedEvidence {
        const owner = self.findUnit(unit, null) orelse return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        const module = &self.units[owner];
        if (catalog >= module.closures.len) return self.fail(owner, .{ .start = 0, .end = 0 }, .unsupported);
        const closure = module.closures[catalog];
        var region = ClosureRegion.initAt(self, @src()) catch return error.OutOfMemory;
        defer region.deinit();
        return region.closureEvidenceFull(owner, closure, .{ .semantic = expected }, seeds, row_seeds) catch |err| return self.evidenceFailure(owner, module.span(closure.body), err);
    }
    fn solveEvidence(self: *Session, owner: usize, body: core.Id, root: types.Id, closed_rows: types.List, scheme: types.Scheme, expected: type_evidence.Id, seeds: []const type_evidence.Mapping) Error![]type_evidence.Mapping {
        const solved = try self.solveEvidenceOwned(owner, body, root, closed_rows, scheme, .{ .semantic = expected }, seeds, &.{});
        self.allocator.free(solved.rows);
        self.allocator.free(solved.selected);
        return solved.types;
    }
    fn solveEvidenceOwned(self: *Session, owner: usize, body: core.Id, root: types.Id, closed_rows: types.List, scheme: types.Scheme, expected: ClosureRegion.Expected, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping) Error!SolvedEvidence {
        return self.solveEvidenceOwnedCode(owner, body, root, closed_rows, scheme, expected, seeds, row_seeds, null);
    }
    fn solveEvidenceOwnedCode(self: *Session, owner: usize, body: core.Id, root: types.Id, closed_rows: types.List, scheme: types.Scheme, expected: ClosureRegion.Expected, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping, projection: ?CodeProjection) Error!SolvedEvidence {
        const outer = self.constant_recorder orelse return self.solveEvidenceOwnedCodeInner(owner, body, root, closed_rows, scheme, expected, seeds, row_seeds, projection);
        // A borrowed representation consumer has no immutable owner on this
        // tape. Its ordinary query remains responsible for that live proof.
        if (projection != null or expected != .semantic) return self.solveEvidenceOwnedCodeInner(owner, body, root, closed_rows, scheme, expected, seeds, row_seeds, projection);
        try outer.beforeRead(self.allocator, self);
        self.constant_recorder = null;
        defer self.constant_recorder = outer;
        errdefer outer.eligible = false;
        var result = try self.solveEvidenceOwnedCodeInner(owner, body, root, closed_rows, scheme, expected, seeds, row_seeds, projection);
        errdefer result.deinit(self.allocator);
        var judgment: @import("../reuse/constant_receipt.zig").Judgment = .{ .kind = .body, .unit = self.unitId(owner), .source = body, .root = root, .scheme = scheme, .closed_rows = closed_rows, .inputs = .{ .types = seeds, .rows = row_seeds }, .outputs = .{ .types = result.types, .rows = result.rows }, .selected = result.selected };
        try outer.query(self.allocator, self, .{ .kind = .judgment, .expected = expected.semantic, .judgment = &judgment });
        return result;
    }
    fn solveEvidenceOwnedCodeInner(self: *Session, owner: usize, body: core.Id, root: types.Id, closed_rows: types.List, scheme: types.Scheme, expected: ClosureRegion.Expected, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping, projection: ?CodeProjection) Error!SolvedEvidence {
        var region = ClosureRegion.initAt(self, @src()) catch return error.OutOfMemory;
        defer region.deinit();
        region.code_projection = projection;
        return region.bodyEvidenceFull(owner, body, root, closed_rows, scheme, expected, seeds, row_seeds) catch |err| {
            if (err == error.OutOfMemory or !region.principal_only_used) return self.evidenceFailure(owner, self.units[owner].span(body), err);
            // Complete and partial code queries have the same witness-order
            // boundary as source selection. A speculative graph failure never
            // replaces the diagnostic from ordinary body collection.
            self.discardDiagnostic();
            const sharing = self.reuse_principal_graphs;
            self.reuse_principal_graphs = false;
            defer self.reuse_principal_graphs = sharing;
            return self.solveEvidenceOwnedCode(owner, body, root, closed_rows, scheme, expected, seeds, row_seeds, projection);
        };
    }
    fn evidenceFailure(self: *Session, owner: usize, span: core.Span, err: ClosureRegion.RegionError) Error {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.Declined => error.Declined,
            error.RequestUnwind => error.RequestUnwind,
            error.TypeLimit, error.EvidenceLimit => blk: {
                if (self.has_implementations and (self.associated_remaining == 0 or self.implementation_proofs.failure == .associated_limit)) break :blk self.fail(owner, span, .associated_limit);
                break :blk self.fail(owner, span, .constant_fuel);
            },
            error.TypeMismatch, error.InfiniteType => self.fail(owner, span, .type_mismatch),
            error.EffectMismatch => self.fail(owner, span, .effect_mismatch),
            error.InfiniteEffect => self.fail(owner, span, .infinite_effect),
            error.UnresolvedType => self.fail(owner, span, .unsupported),
        };
    }
    /// Borrowed until this session is destroyed. Array growth preserves handles,
    /// so consumers obtain the view after evaluation rather than retaining slices.
    pub fn snapshot(self: *const Session) View {
        return self.storage.view(self.implementation_proofs.view());
    }
    pub fn copySnapshotMeasured(self: *Session, backing: Allocator) Allocator.Error!Snapshot {
        // Only slices escape this adapter. Their durable caller frees with the
        // same backing allocator; no allocator pointer enters the snapshot.
        var meter: @import("../runtime/memory.zig").TrackedAllocator = .{ .backing = backing };
        defer {
            self.counters.snapshot_copy_bytes += meter.counts.allocated_bytes;
            self.counters.snapshot_copy_allocations += meter.counts.allocations;
        }
        return self.copySnapshot(meter.allocator());
    }
    pub fn copySnapshot(self: *const Session, allocator: Allocator) Allocator.Error!Snapshot {
        return self.storage.copySnapshot(allocator, &self.implementation_proofs);
    }
    fn makeClosure(self: *Session, owner: usize, source: core.Id, metadata: ClosureValue, captures: []const ValueId) Error!ValueId {
        if (self.storage.closures.items.len >= std.math.maxInt(u32)) return self.failNode(owner, source, .constant_fuel);
        const index: u32 = @intCast(self.storage.closures.items.len);
        try self.storage.closures.ensureUnusedCapacity(self.allocator, 1);
        try self.storage.demands.ensureUnusedCapacity(self.allocator, 1);
        const id = try self.makeAggregate(owner, source, .closure, 0, index, captures);
        self.storage.closures.appendAssumeCapacity(metadata);
        self.storage.demands.appendAssumeCapacity(.{});
        return id;
    }
    fn makeScalar(self: *Session, owner: usize, source: core.Id, value_: Value) Error!ValueId {
        if (value_.scalar == .unit) return 0;
        if (self.constantValueCount() >= self.options.max_values or self.storage.values.items.len >= std.math.maxInt(ValueId)) return self.failNode(owner, source, .constant_fuel);
        return self.storage.scalar(self.allocator, value_);
    }
    fn makeAggregate(self: *Session, owner: usize, source: core.Id, kind: ValueKind, nominal: u64, tag: u32, children_: []const ValueId) Error!ValueId {
        // Allocation alone has no executable authority. The final reachable
        // graph proves transportability; mutable execution declines at its owner.
        if (self.constantValueCount() >= self.options.max_values or self.storage.values.items.len >= std.math.maxInt(ValueId) or children_.len > self.options.max_children -| self.constantChildCount() -| self.ragged_reserved_children or children_.len > std.math.maxInt(u32) - self.storage.children.items.len) return self.failNode(owner, source, .constant_fuel);
        return self.storage.aggregate(self.allocator, kind, nominal, tag, children_);
    }
    fn copyFrozenAggregate(self: *Session, owner: usize, source: core.Id, original: ValueId, replacements: []const FrozenCapture, metadata: ?ClosureValue) Error!ValueId {
        const info = self.valueInfo(original);
        if (self.constantValueCount() >= self.options.max_values or self.storage.values.items.len >= std.math.maxInt(ValueId) or info.len > self.options.max_children -| self.constantChildCount() or info.len > std.math.maxInt(u32) - self.storage.children.items.len) return self.failNode(owner, source, .constant_fuel);
        if (metadata != null and self.storage.closures.items.len >= std.math.maxInt(u32)) return self.failNode(owner, source, .constant_fuel);
        try self.storage.values.ensureUnusedCapacity(self.allocator, 1);
        try self.storage.value_evidence.ensureUnusedCapacity(self.allocator, 1);
        try self.storage.value_records.ensureUnusedCapacity(self.allocator, 1);
        try self.storage.children.ensureUnusedCapacity(self.allocator, info.len);
        if (metadata != null) {
            try self.storage.closures.ensureUnusedCapacity(self.allocator, 1);
            try self.storage.demands.ensureUnusedCapacity(self.allocator, 1);
        }
        const id: ValueId = @intCast(self.storage.values.items.len);
        const start: u32 = @intCast(self.storage.children.items.len);
        // The original span ends before this destination. Reacquire it only
        // after all capacity growth; prepared children are stable handles.
        self.storage.children.appendSliceAssumeCapacity(self.valueChildren(original));
        for (replacements) |replacement| self.storage.children.items[start + replacement.slot] = replacement.value;
        self.storage.values.appendAssumeCapacity(.{ .kind = if (metadata != null) .closure else info.kind, .nominal = if (metadata != null) 0 else info.nominal, .bits = if (metadata != null) @intCast(self.storage.closures.items.len) else info.bits, .start = start, .len = info.len });
        self.storage.value_evidence.appendAssumeCapacity(0);
        self.storage.value_records.appendAssumeCapacity(0);
        if (metadata) |closure_| {
            self.storage.closures.appendAssumeCapacity(closure_);
            self.storage.demands.appendAssumeCapacity(.{});
        }
        if (@import("../check/staging_origins.zig").generator(self.storage.code_origins.items, original)) |origin| try self.storage.code_origins.append(self.allocator, .{ .value = id, .generator = origin });
        self.counters.frozen_capture_published_bytes += info.len * @sizeOf(ValueId);
        return id;
    }
    fn copyAggregate(self: *Session, owner: usize, source: core.Id, original: ValueId, field: u32, replacement: ValueId) Error!ValueId {
        const info = self.valueInfo(original);
        if (field >= info.len) return self.failNode(owner, source, .unsupported);
        if (self.constantValueCount() >= self.options.max_values or self.storage.values.items.len >= std.math.maxInt(ValueId) or info.len > self.options.max_children -| self.constantChildCount() or info.len > std.math.maxInt(u32) - self.storage.children.items.len) return self.failNode(owner, source, .constant_fuel);
        try self.storage.values.ensureUnusedCapacity(self.allocator, 1);
        try self.storage.value_evidence.ensureUnusedCapacity(self.allocator, 1);
        try self.storage.value_records.ensureUnusedCapacity(self.allocator, 1);
        try self.storage.children.ensureUnusedCapacity(self.allocator, info.len);
        const id: ValueId = @intCast(self.storage.values.items.len);
        const start: u32 = @intCast(self.storage.children.items.len);
        // Reacquire the source after growth. Its span ends before the appended
        // destination, so one contiguous copy needs no second scratch buffer.
        self.storage.children.appendSliceAssumeCapacity(self.valueChildren(original));
        self.storage.children.items[start + field] = replacement;
        self.storage.values.appendAssumeCapacity(.{ .kind = info.kind, .nominal = info.nominal, .bits = info.bits, .start = start, .len = info.len });
        self.storage.value_evidence.appendAssumeCapacity(self.valueEvidence(original));
        self.storage.value_records.appendAssumeCapacity(self.storage.value_records.items[original]);
        return id;
    }
    fn chargeCells(self: *Session, owner: usize, source: core.Id, count: usize) Error!void {
        if (count > self.options.max_steps -| self.steps) {
            self.steps = self.options.max_steps;
            return self.failNode(owner, source, .constant_fuel);
        }
        self.steps += count;
    }
    fn requireScalar(self: *Session, owner: usize, source: core.Id, id: ValueId) Error!Value {
        return self.valueScalar(id) orelse return self.failNode(owner, source, .unsupported);
    }
    fn implementationContext(self: *const Session, owner: usize) u32 {
        if (self.specialization_origin) |origin| return origin.unit;
        return self.unitId(owner);
    }
    fn privateImplementationMethod(self: *const Session, owner: usize, binding: core.BindingId) bool {
        if (!self.has_implementations) return false;
        const module = &self.units[owner];
        for (module.implementations) |declaration| {
            if (!declaration.private or declaration.identity.unit != self.unitId(owner)) continue;
            for (module.implementation_members[declaration.members.start..][0..declaration.members.len]) |member| {
                if (member.kind == .value and (member.target.unit == 0 or member.target.unit == self.unitId(owner)) and member.target.binding == binding) return true;
            }
        }
        return false;
    }
    fn implementationUseContext(self: *const Session, owner: usize, source: core.Id) u32 {
        const module = &self.units[owner];
        for (module.selected_uses) |use| if (use.node == source) {
            const proof = module.selected_proofs[use.proof];
            if (proof.kind == .implementation) {
                if (proof.context == 0) return self.unitId(owner);
                return proof.context;
            }
        };
        if (self.has_implementations and source != 0) {
            const span = module.span(source);
            for (module.bodies) |body| {
                if (span.start < body.span.start or span.end > body.span.end) continue;
                if (self.privateImplementationMethod(owner, body.binding)) return self.unitId(owner);
            }
        }
        return self.implementationContext(owner);
    }
    pub fn selectTemplate(self: *Session, owner: usize, source: core.Id, reference: core.BindingRef, actual: type_evidence.Id) Error!core.BindingRef {
        return (try self.selectTemplateSelection(owner, source, reference, actual)).target;
    }
    fn selectTemplateSelection(self: *Session, owner: usize, source: core.Id, reference: core.BindingRef, actual: type_evidence.Id) Error!MethodSelection {
        if (!self.has_implementations) return .{ .target = reference, .signature = actual };
        const target_ = try self.external(try self.target(owner, reference));
        const module = &self.units[target_.unit];
        for (module.member_templates) |template| {
            if (template.binding != target_.binding) continue;
            if (actual == 0) return self.failNode(owner, source, .ambiguous_qualified);
            var mappings: std.ArrayList(type_evidence.Mapping) = .empty;
            defer mappings.deinit(self.allocator);
            var rows: std.ArrayList(type_evidence.RowMapping) = .empty;
            defer rows.deinit(self.allocator);
            var projection: ImplementationProjection = .{ .session = self, .context = self.implementationUseContext(owner, source) };
            if (!(self.storage.evidence.matchTemplate(&module.types, module.binding(template.binding).ty, actual, &mappings, &rows, projection.resolver()) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.EvidenceLimit => return self.failNode(owner, source, .associated_limit),
                error.UnresolvedType => return self.failNode(owner, source, .ambiguous_qualified),
                error.TypeMismatch => return self.implementationMatchFailure(owner, source, projection, err),
            })) return self.failNode(owner, source, .type_mismatch);
            const previous = self.specialization_origin;
            self.specialization_origin = .{ .unit = projection.context, .span = self.units[owner].span(source) };
            defer self.specialization_origin = previous;
            return self.implementationMethodAt(target_.unit, owner, source, projection.context, template, mappings.items, rows.items);
        }
        return .{ .target = reference, .signature = actual };
    }
    fn implementationFailure(self: *Session, owner: usize, source: core.Id) Error {
        const code = self.implementation_proofs.failure orelse .missing_implementation;
        const fresh = self.diagnostic == null;
        const result = self.failNode(owner, source, switch (code) {
            .missing_implementation => .missing_implementation,
            .incompatible_implementation => .incompatible_implementation,
            .recursive_evidence => .recursive_evidence,
            .recursive_associated_type => .recursive_associated_type,
            .associated_limit => .associated_limit,
        });
        if (fresh) self.diagnostic.?.implementation_trace = self.implementation_proofs.trace;
        return result;
    }
    pub fn implementationRead(self: *Session, context: u32, implementation: types.NominalIdentity) Allocator.Error!void {
        // Selected proofs are required semantic owners. Until a complete read
        // set is exportable, optional executable/principal receipts decline.
        if (self.principal_reads) |reads| reads.invalidate(.specialize);
        if (self.receipt_tape) |tape| tape.unknown = true;
        _ = context;
        _ = implementation;
    }
    pub fn implementationLegacyPredicate(self: *Session, context: u32, requirement: core.Obligation, operands: [4]type_evidence.Id, resolver: type_evidence.ProjectionResolver) type_evidence.Error!?implementation_evidence.LegacyChoice {
        const owner = self.findUnit(context, null) orelse return error.TypeMismatch;
        if (requirement.kind == .field or requirement.kind == .writable_field) {
            const shape = self.storage.evidence.node(operands[0]);
            if (shape.tag == .record) {
                const fields = self.storage.evidence.children(operands[0]);
                var at: usize = 0;
                while (at < fields.len) : (at += 2) {
                    if (fields[at] == requirement.name) {
                        if (operands[2] == 0 or operands[2] == fields[at + 1]) return .{ .target = .{ .unit = 0, .binding = 0 }, .carrier = operands[3] };
                        return null;
                    }
                }
            }
        }
        if (requirement.kind != .dispatch and requirement.kind != .receiver and requirement.kind != .field and requirement.kind != .result_dispatch and requirement.kind != .resolver_dispatch) return null;
        var first: ?core.BindingRef = null;
        var second: ?core.BindingRef = null;
        var selection_owner = operands[0];
        var selected_identity: ?types.NominalIdentity = null;
        if (requirement.kind == .result_dispatch) selection_owner = operands[2];
        if (requirement.kind == .resolver_dispatch) {
            const resolver_type = self.storage.evidence.node(operands[0]);
            if (resolver_type.tag != .resolver) return null;
            const constructor = self.storage.evidence.node(resolver_type.a);
            if (constructor.tag != .type_constructor) return null;
            selected_identity = .{ .unit = constructor.a, .decl = constructor.b };
        } else {
            selected_identity = self.evidenceIdentity(selection_owner);
        }
        if (selected_identity) |identity| first = self.associatedTarget(context, identity, requirement.name, requirement.operator) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.TypeMismatch,
        };
        if (requirement.kind == .dispatch) {
            if (self.evidenceIdentity(operands[1])) |identity| second = self.associatedTarget(context, identity, requirement.name, requirement.operator) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return error.TypeMismatch,
            };
        }
        for ([_]?core.BindingRef{ first, second }, 0..) |target_, side| {
            if (side == 1 and requirement.kind == .dispatch and requirement.name == 0) {
                if (@import("implementation_predicates.zig").primitiveResult(&self.storage.evidence, requirement.operator, operands[0], operands[1])) |result| {
                    if (result != operands[2]) return null;
                    var carrier = operands[3];
                    if (carrier == 0) carrier = try self.storage.evidence.intern(.function, types.unit, types.unit, &.{});
                    return .{ .target = .{ .unit = 0, .binding = 0 }, .carrier = carrier };
                }
            }
            const target_ref = target_ orelse continue;
            const target_owner = self.findUnit(target_ref.unit, owner) orelse continue;
            const module = &self.units[target_owner];
            const binding = module.binding(target_ref.binding);
            var mappings: std.ArrayList(type_evidence.Mapping) = .empty;
            defer mappings.deinit(self.allocator);
            var rows: std.ArrayList(type_evidence.RowMapping) = .empty;
            defer rows.deinit(self.allocator);
            var arity: usize = 2;
            if (requirement.kind == .field or requirement.kind == .result_dispatch) arity = 1;
            var carrier: type_evidence.Id = 0;
            if (requirement.kind == .resolver_dispatch) {
                if (!try self.storage.evidence.matchLegacySignature(&module.types, binding.scheme.root, operands[1], &mappings, &rows, resolver)) continue;
            } else carrier = try self.storage.evidence.matchPrerequisite(&module.types, binding.scheme.root, operands, arity, &mappings, &rows, resolver) orelse continue;
            // Never infer an unquantified captured slot from a wanted result.
            for (mappings.items) |mapping| {
                if (std.mem.findScalar(types.Id, module.types.list(binding.scheme.variables), mapping.variable) == null) return null;
            }
            for (rows.items) |mapping| if (std.mem.findScalar(u32, module.types.list(binding.scheme.row_variables), mapping.variable) == null) return null;
            var original = target_ref;
            if (original.unit == 0) original.unit = self.unitId(target_owner);
            return .{ .target = original, .carrier = carrier };
        }
        return null;
    }
    const ImplementationProjection = struct {
        session: *Session,
        context: u32,
        resolved: bool = false,
        fn resolve(raw: *anyopaque, contract: types.NominalIdentity, member: u32, arguments: []const type_evidence.Id) type_evidence.Error!type_evidence.Id {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.resolved = true;
            return self.session.implementation_proofs.projection(self.session, self.context, contract, member, arguments) catch |err| switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.AssociatedLimit, error.EvidenceLimit => error.EvidenceLimit,
                error.UnresolvedType => error.UnresolvedType,
                else => error.TypeMismatch,
            };
        }
        fn resolver(self: *@This()) type_evidence.ProjectionResolver {
            return .{ .context = self, .remaining = &self.session.associated_remaining, .resolve = resolve };
        }
    };
    fn implementationMatchFailure(self: *Session, owner: usize, source: core.Id, projection: ImplementationProjection, err: type_evidence.Error) Error {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        if (projection.resolved and self.implementation_proofs.failure != null) return self.implementationFailure(owner, source);
        if (err == error.EvidenceLimit) return self.failNode(owner, source, .associated_limit);
        if (err == error.UnresolvedType) return self.failNode(owner, source, .ambiguous_qualified);
        return self.failNode(owner, source, .type_mismatch);
    }
    pub const MethodSelection = struct { target: core.BindingRef, signature: type_evidence.Id };
    pub fn implementationMethod(self: *Session, owner: usize, source: core.Id, template: core.MemberTemplate, mappings: []const type_evidence.Mapping, rows: []const type_evidence.RowMapping) Error!MethodSelection {
        return self.implementationMethodAt(owner, owner, source, self.implementationUseContext(owner, source), template, mappings, rows);
    }
    fn implementationMethodAt(self: *Session, owner: usize, caller: usize, source: core.Id, context: u32, template: core.MemberTemplate, mappings: []const type_evidence.Mapping, rows: []const type_evidence.RowMapping) Error!MethodSelection {
        var arguments: std.ArrayList(type_evidence.Id) = .empty;
        defer arguments.deinit(self.allocator);
        for (self.units[owner].types.list(template.arguments)) |root| {
            const actual = try self.projectType(owner, 0, root, mappings, rows);
            if (actual == 0) return self.failNode(caller, source, .ambiguous_qualified);
            try arguments.append(self.allocator, actual);
        }
        const proof = self.implementation_proofs.resolve(self, context, template.contract, arguments.items) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnresolvedType => return self.failNode(caller, source, .ambiguous_qualified),
            else => return self.implementationFailure(caller, source),
        };
        const declaration = self.implementation_proofs.proofs.items[proof];
        for (self.implementation_proofs.members.items[declaration.members.start..][0..declaration.members.len]) |member| {
            if (member.name == template.name) return .{ .target = member.target, .signature = member.root };
        }
        return self.failNode(caller, source, .missing_implementation);
    }
    pub fn dictionaryMember(self: *Session, owner: usize, id: core.Id, quantifier: types.Id, goal_ordinal: u32, member_ordinal: u32, mappings: []const type_evidence.Mapping, rows: []const type_evidence.RowMapping) Error!MethodSelection {
        const module = &self.units[owner];
        const goals = module.types.quantifierGoals(quantifier);
        if (goal_ordinal >= goals.len) return self.failNode(owner, id, .type_mismatch);
        const goal = goals[goal_ordinal];
        if (goal.kind != .contract) return self.failNode(owner, id, .unsupported);
        const application = try self.projectType(owner, id, goal.ty, mappings, rows);
        if (application == 0 or self.storage.evidence.node(application).tag != .product) return self.failNode(owner, id, .ambiguous_qualified);
        const proof = self.implementation_proofs.resolve(self, self.implementationUseContext(owner, id), goal.identity, self.storage.evidence.children(application)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnresolvedType => return self.failNode(owner, id, .ambiguous_qualified),
            else => return self.implementationFailure(owner, id),
        };
        const selected = self.implementation_proofs.proofs.items[proof];
        if (member_ordinal >= selected.members.len) return self.failNode(owner, id, .missing_implementation);
        const member = self.implementation_proofs.members.items[selected.members.start + member_ordinal];
        if (member.kind != .value) return self.failNode(owner, id, .unsupported);
        return .{ .target = member.target, .signature = member.root };
    }
    pub fn dictionaryUse(self: *Session, owner: usize, id: core.Id, mappings: []const type_evidence.Mapping, rows: []const type_evidence.RowMapping) Error!?MethodSelection {
        for (self.units[owner].dictionary_uses) |use| {
            if (use.node != id or use.introduction == 0) continue;
            return try self.dictionaryMember(owner, id, use.quantifier, use.goal, use.member, mappings, rows);
        }
        return null;
    }
    fn contractMethod(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const template = module.member_templates[module.node(id).a];
        const selected = try self.implementationMethod(owner, id, template, frame.mappings.items, frame.row_mappings.items);
        const target_ = try self.external(try self.target(owner, selected.target));
        try self.prepare(selected.target);
        const children = module.children(id);
        const arguments = try self.allocator.alloc(ValueId, children.len);
        defer self.allocator.free(arguments);
        for (children, arguments) |child, *argument| {
            const outcome = try self.expression(owner, child, frame);
            if (outcome != .value) return outcome;
            argument.* = outcome.value;
        }
        return self.invokeNamed(target_, arguments, owner, id, selected.signature, frame.providers);
    }
    pub fn projectType(self: *Session, owner: usize, source: core.Id, ty: types.Id, mappings: []const type_evidence.Mapping, rows: []const type_evidence.RowMapping) Error!type_evidence.Id {
        if (!self.has_implementations) return self.storage.evidence.projectWithRows(&self.units[owner].types, ty, mappings, rows) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnresolvedType => return 0,
            error.EvidenceLimit => return self.failNode(owner, source, .constant_fuel),
            error.TypeMismatch => return self.failNode(owner, source, .unsupported),
        };
        var projection: ImplementationProjection = .{ .session = self, .context = self.implementationUseContext(owner, source) };
        return self.storage.evidence.projectSelected(&self.units[owner].types, ty, mappings, rows, projection.resolver()) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnresolvedType => return 0,
            else => return self.implementationMatchFailure(owner, source, projection, err),
        };
    }
    fn matchType(self: *Session, owner: usize, source: core.Id, producer: usize, ty: types.Id, actual: type_evidence.Id, mappings: *std.ArrayList(type_evidence.Mapping), rows: *std.ArrayList(type_evidence.RowMapping)) Error!bool {
        const outer = self.constant_recorder orelse return self.matchTypeInner(owner, source, producer, ty, actual, mappings, rows);
        // Structural matching only updates the caller's mappings. Without
        // implementation projection it has no ordinary solver work to replay.
        if (!self.has_implementations or try self.specializations.closed_source_types.closed(self.allocator, self.units, producer, ty, 0)) return self.matchTypeInner(owner, source, producer, ty, actual, mappings, rows);
        try outer.beforeRead(self.allocator, self);
        var seeds = try (@import("../reuse/constant_receipt.zig").Inputs{ .types = mappings.items, .rows = rows.items }).clone(self.allocator);
        defer seeds.deinit(self.allocator);
        self.constant_recorder = null;
        defer self.constant_recorder = outer;
        errdefer outer.eligible = false;
        const result = try self.matchTypeInner(owner, source, producer, ty, actual, mappings, rows);
        var judgment: @import("../reuse/constant_receipt.zig").Judgment = .{ .kind = .match, .unit = self.unitId(owner), .producer = self.unitId(producer), .source = source, .root = ty, .matched = result, .inputs = seeds, .outputs = .{ .types = mappings.items, .rows = rows.items } };
        try outer.query(self.allocator, self, .{ .kind = .judgment, .expected = actual, .judgment = &judgment });
        return result;
    }
    fn matchTypeInner(self: *Session, owner: usize, source: core.Id, producer: usize, ty: types.Id, actual: type_evidence.Id, mappings: *std.ArrayList(type_evidence.Mapping), rows: *std.ArrayList(type_evidence.RowMapping)) Error!bool {
        if (actual == 0) return false;
        if (self.has_implementations) {
            var projection: ImplementationProjection = .{ .session = self, .context = self.implementationUseContext(owner, source) };
            return self.storage.evidence.matchSelected(&self.units[producer].types, ty, actual, mappings, rows, projection.resolver()) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.UnresolvedType => return false,
                else => return self.implementationMatchFailure(owner, source, projection, err),
            };
        }
        return self.storage.evidence.matchWithRows(&self.units[producer].types, ty, actual, mappings, rows) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.EvidenceLimit => return self.failNode(owner, source, .constant_fuel),
            error.UnresolvedType, error.TypeMismatch => return self.failNode(owner, source, .unsupported),
        };
    }
    fn matchCovariantType(self: *Session, owner: usize, source: core.Id, producer: usize, ty: types.Id, actual: type_evidence.Id, mappings: *std.ArrayList(type_evidence.Mapping), rows: *std.ArrayList(type_evidence.RowMapping)) Error!bool {
        const outer = self.constant_recorder orelse return self.matchCovariantTypeInner(owner, source, producer, ty, actual, mappings, rows);
        try outer.beforeRead(self.allocator, self);
        var seeds = try (@import("../reuse/constant_receipt.zig").Inputs{ .types = mappings.items, .rows = rows.items }).clone(self.allocator);
        defer seeds.deinit(self.allocator);
        self.constant_recorder = null;
        defer self.constant_recorder = outer;
        errdefer outer.eligible = false;
        const result = try self.matchCovariantTypeInner(owner, source, producer, ty, actual, mappings, rows);
        var judgment: @import("../reuse/constant_receipt.zig").Judgment = .{ .kind = .covariant, .unit = self.unitId(owner), .producer = self.unitId(producer), .source = source, .root = ty, .matched = result, .inputs = seeds, .outputs = .{ .types = mappings.items, .rows = rows.items } };
        try outer.query(self.allocator, self, .{ .kind = .judgment, .expected = actual, .judgment = &judgment });
        return result;
    }
    fn matchCovariantTypeInner(self: *Session, owner: usize, source: core.Id, producer: usize, ty: types.Id, actual: type_evidence.Id, mappings: *std.ArrayList(type_evidence.Mapping), rows: *std.ArrayList(type_evidence.RowMapping)) Error!bool {
        if (try self.matchType(owner, source, producer, ty, actual, mappings, rows)) return true;
        var region = ClosureRegion.initAt(self, @src()) catch return error.OutOfMemory;
        defer region.deinit();
        var solved = region.covariantEvidence(producer, ty, actual, mappings.items, rows.items) catch |err| switch (err) {
            error.TypeMismatch, error.InfiniteType, error.EffectMismatch, error.InfiniteEffect => return false,
            else => return self.evidenceFailure(owner, self.units[owner].span(source), err),
        };
        defer solved.deinit(self.allocator);
        try mappings.appendSlice(self.allocator, solved.types);
        try rows.appendSlice(self.allocator, solved.rows);
        return true;
    }
    /// A polymorphic use can select a new semantic type without changing a
    /// captured alias. The small immutable header shares children and code.
    fn typedView(self: *Session, owner: usize, source: core.Id, value_: ValueId, actual: type_evidence.Id) Error!ValueId {
        if (actual == 0 or self.valueEvidence(value_) == actual) return value_;
        if (self.constant_recorder) |recorder| {
            try recorder.view(self.allocator, value_);
            try recorder.prepareView(self.allocator);
        }
        const key: ViewKey = .{ .value = value_, .evidence = actual };
        if (self.storage.typed_views.get(key)) |existing| {
            if (self.receipt_tape) |tape| try tape.views.append(self.allocator, .{ .value = value_, .evidence = actual, .selected = existing, .existed = true });
            if (self.constant_recorder) |recorder| try recorder.cacheView(self.allocator, self, .{ .value = value_, .evidence = actual, .selected = existing, .existed = true });
            return existing;
        }
        if (self.constantValueCount() >= self.options.max_values or self.storage.values.items.len >= std.math.maxInt(ValueId)) return self.failNode(owner, source, .constant_fuel);
        var info = self.valueInfo(value_);
        var provider_child: ?ValueId = null;
        if (info.kind == .provider) {
            const provider_type = self.storage.evidence.node(actual);
            if (provider_type.tag != .provider or info.nominal == 0 or info.len != 1) return self.failNode(owner, source, .invalid_provider);
            const operation = self.storage.evidence.node(@intCast(info.nominal));
            if (operation.tag != .function) return self.failNode(owner, source, .invalid_provider);
            const implementation_type = self.storage.evidence.internWithEffects(.function, operation.a, operation.b, provider_type.c, &.{}) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return self.failNode(owner, source, .unsupported),
            };
            const original = self.valueChildren(value_)[0];
            // The provider's checked type supplies the implementation row.
            // Principal publication applies its recorded closing decision;
            // contextual publication preserves the selected ambient row.
            provider_child = if (self.valueEvidence(original) == 0)
                try self.specializeClosure(original, implementation_type)
            else
                original;
            info.start = @intCast(self.storage.children.items.len);
        }
        if (self.constantValueCount() >= self.options.max_values or self.storage.values.items.len >= std.math.maxInt(ValueId)) return self.failNode(owner, source, .constant_fuel);
        if (provider_child != null and (self.constantChildCount() >= self.options.max_children or self.storage.children.items.len >= std.math.maxInt(u32))) return self.failNode(owner, source, .constant_fuel);
        try self.storage.values.ensureUnusedCapacity(self.allocator, 1);
        try self.storage.value_evidence.ensureUnusedCapacity(self.allocator, 1);
        try self.storage.value_records.ensureUnusedCapacity(self.allocator, 1);
        try self.storage.typed_views.ensureUnusedCapacity(self.allocator, 1);
        if (provider_child != null) try self.storage.children.ensureUnusedCapacity(self.allocator, 1);
        if (provider_child) |child| self.storage.children.appendAssumeCapacity(child);
        const id: ValueId = @intCast(self.storage.values.items.len);
        if (self.receipt_tape) |tape| try tape.views.append(self.allocator, .{ .value = value_, .evidence = actual, .selected = id, .existed = false });
        self.storage.values.appendAssumeCapacity(info);
        self.storage.value_evidence.appendAssumeCapacity(actual);
        self.storage.value_records.appendAssumeCapacity(self.storage.value_records.items[value_]);
        if (@import("../check/staging_origins.zig").generator(self.storage.code_origins.items, value_)) |origin| try self.storage.code_origins.append(self.allocator, .{ .value = id, .generator = origin });
        self.storage.typed_views.putAssumeCapacity(key, id);
        if (self.constant_recorder) |recorder| try recorder.cacheView(self.allocator, self, .{ .value = value_, .evidence = actual, .selected = id, .existed = false });
        return id;
    }
    fn captureMappings(self: *Session, owner: usize, source: core.Id, mappings: []const type_evidence.Mapping) Error!core.List {
        if (mappings.len > std.math.maxInt(u32) - self.storage.type_mappings.items.len) return self.failNode(owner, source, .constant_fuel);
        const start: u32 = @intCast(self.storage.type_mappings.items.len);
        try self.storage.type_mappings.appendSlice(self.allocator, mappings);
        return .{ .start = start, .len = @intCast(mappings.len) };
    }
    fn captureRowMappings(self: *Session, owner: usize, source: core.Id, mappings: []const type_evidence.RowMapping) Error!core.List {
        if (mappings.len > std.math.maxInt(u32) - self.storage.row_mappings.items.len) return self.failNode(owner, source, .constant_fuel);
        const start: u32 = @intCast(self.storage.row_mappings.items.len);
        try self.storage.row_mappings.appendSlice(self.allocator, mappings);
        return .{ .start = start, .len = @intCast(mappings.len) };
    }
    /// Dense project catalogs are proved once. General Session callers retain
    /// first-match lookup for explicit/non-dense unit identities.
    pub fn unitIndex(self: *const Session, unit: u32) ?usize {
        if (self.dense_unit_ids and unit != 0) return if (unit <= self.units.len) unit - 1 else null;
        for (self.units, 0..) |module, index| if (module.unit == unit or (module.unit == 0 and index + 1 == unit)) return index;
        return null;
    }
    fn unitId(self: *const Session, index: usize) u32 {
        return if (self.units[index].unit != 0) self.units[index].unit else @intCast(index + 1);
    }
    fn fail(self: *Session, owner: usize, span: core.Span, code: Code) Error {
        if (self.diagnostic == null) self.diagnostic = .{ .unit = if (owner < self.units.len) self.unitId(owner) else 0, .span = span, .code = code, .origins = self.staging_trace };
        return error.Declined;
    }
    fn failNode(self: *Session, owner: usize, id: core.Id, code: Code) Error {
        return self.fail(owner, self.units[owner].span(id), code);
    }
    pub fn anchorSpecialization(self: *Session, origin: ?SourceLocation) void {
        const use = origin orelse return;
        const issue = if (self.diagnostic) |*item| item else return;
        switch (issue.code) {
            .missing_associated, .ambiguous_associated, .ambiguous_operator, .missing_member, .missing_field, .ambiguous_qualified, .type_mismatch, .effect_mismatch, .invalid_provider, .type_constructor_required => {},
            else => return,
        }
        if (issue.related != null or (issue.unit == use.unit and std.meta.eql(issue.span, use.span))) return;
        issue.related = .{ .unit = issue.unit, .span = issue.span };
        issue.unit = use.unit;
        issue.span = use.span;
    }
    fn invocationOrigin(self: *Session, owner: usize, source: core.Id, dependent: bool) ?SourceLocation {
        if (self.unitId(owner) == self.diagnostic_context.entry) {
            if (self.specialization_origin) |origin| return origin;
            return .{ .unit = self.unitId(owner), .span = self.units[owner].span(source) };
        }
        if (dependent) return self.specialization_origin;
        return .{ .unit = self.unitId(owner), .span = self.units[owner].span(source) };
    }
    fn failDispatch(self: *Session, owner: usize, id: core.Id, code: Code, record: DispatchRecord) Error {
        const fresh = self.diagnostic == null;
        const result = self.failNode(owner, id, code);
        if (fresh) {
            var explained = record;
            self.dispatchContexts(owner, id, self.specialization_origin, &explained);
            self.diagnostic.?.dispatch = explained;
        }
        return result;
    }
    fn dispatchContexts(self: *Session, owner: usize, id: core.Id, call_origin: ?SourceLocation, record: *DispatchRecord) void {
        if (id == 0 or record.context_len != 0) return;
        if (call_origin) |origin| if (origin.unit != 0 and origin.unit <= self.units.len) {
            const caller = &self.units[origin.unit - 1];
            for (caller.nodes, 0..) |item, index| {
                if (item.tag != .call) continue;
                const span = caller.span(@intCast(index));
                if (span.start != origin.span.start or span.end != origin.span.end) continue;
                const arguments = caller.children(@intCast(index));
                if (arguments.len != 2) continue;
                record.contexts = .{
                    .{ .kind = .left_operand, .unit = origin.unit, .span = caller.span(arguments[0]) },
                    .{ .kind = .right_operand, .unit = origin.unit, .span = caller.span(arguments[1]) },
                };
                record.context_len = 2;
                return;
            }
        };
        const module = &self.units[owner];
        const node = module.node(id);
        if (node.tag != .associated or node.a == 0 or node.b == 0) return;
        const unit = self.unitId(owner);
        record.contexts = .{
            .{ .kind = .left_operand, .unit = unit, .span = module.span(node.a) },
            .{ .kind = .right_operand, .unit = unit, .span = module.span(node.b) },
        };
        record.context_len = 2;
    }
    /// Rebuilds, from catalogs alone, why binary candidates were rejected:
    /// the left owner, a built-in scalar operation for an unnamed operator,
    /// then a right owner other than the left one.
    fn rejectedCandidates(self: *Session, owner: usize, op: types.Operator, member: u32, left: type_evidence.Id, right: type_evidence.Id, include_right: bool) Error!DispatchRecord {
        var record: DispatchRecord = .{ .op = op, .member = member };
        const left_identity = self.evidenceIdentity(left);
        record.add(.left, left, try self.ownerOutcome(owner, left_identity, op, member));
        if (member == 0 and left != 0 and left == right) switch (self.storage.evidence.node(left).tag) {
            .u32, .f32, .boolean => record.add(.builtin, left, .unsupported_scalar),
            else => {},
        };
        const right_identity = self.evidenceIdentity(right);
        const same = left_identity != null and right_identity != null and std.meta.eql(left_identity.?, right_identity.?);
        if (include_right and !same) record.add(.right, right, try self.ownerOutcome(owner, right_identity, op, member));
        return record;
    }
    fn ownerOutcome(self: *Session, owner: usize, identity: ?types.NominalIdentity, op: types.Operator, member: u32) Error!dispatch_explanation.Outcome {
        const declared = identity orelse return .no_member;
        return if (try self.associatedTarget(self.unitId(owner), declared, member, op) != null) .incompatible else .no_member;
    }
    fn slot(self: *Session, location: Target) *Slot {
        return &self.slots[self.binding_offsets[location.unit] + location.binding];
    }
    fn findUnit(self: *const Session, id: u32, owner: ?usize) ?usize {
        if (id == 0) return owner orelse if (self.units.len == 1) @as(usize, 0) else null;
        if (id <= self.units.len and self.unitId(id - 1) == id) return id - 1;
        for (self.units, 0..) |_, index| if (self.unitId(index) == id) return index;
        return null;
    }
    fn target(self: *Session, owner: ?usize, reference: core.BindingRef) Error!Target {
        const index = self.findUnit(reference.unit, owner) orelse return self.fail(owner orelse self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        if (reference.binding == 0 or reference.binding >= self.units[index].bindings.len) return self.fail(index, .{ .start = 0, .end = 0 }, .unsupported);
        return .{ .unit = index, .binding = reference.binding };
    }
    fn external(self: *Session, initial: Target) Error!Target {
        var resolved = initial;
        var seen: [256]Target = undefined;
        var count: usize = 0;
        while (true) {
            const binding = self.units[resolved.unit].binding(resolved.binding);
            if (binding.kind != .external) return resolved;
            for (seen[0..count]) |previous| if (std.meta.eql(previous, resolved)) return self.fail(resolved.unit, binding.span, .cycle);
            if (count == seen.len) return self.fail(resolved.unit, binding.span, .constant_fuel);
            seen[count] = resolved;
            count += 1;
            resolved = try self.target(resolved.unit, binding.target);
        }
    }
    /// Discover global dependencies before executing values. References in all
    /// syntactic branches count, including function bodies passed as values.
    /// Direct operations in unselected branches are never executed by tracing.
    /// Read-only source selection/value queries; no new demand or mutation.
    pub fn bindingTraced(self: *Session, reference: core.BindingRef) Error!bool {
        return self.slot(try self.external(try self.target(null, reference))).traced;
    }
    pub fn cachedBindingValue(self: *Session, reference: core.BindingRef) Error!?ValueId {
        const stored = self.slot(try self.external(try self.target(null, reference)));
        return if (stored.state == .complete) stored.value else null;
    }
    /// Canonical receipt targets already name their original producer. This
    /// query cannot resolve aliases, demand a value or create a diagnostic.
    pub fn readyConstantAnchor(self: *const Session, reference: core.BindingRef) ?ValueId {
        if (reference.unit == 0 or reference.binding == 0) return null;
        const owner = self.findUnit(reference.unit, null) orelse return null;
        if (reference.binding >= self.units[owner].bindings.len or self.units[owner].binding(reference.binding).kind != .global) return null;
        const index = std.math.add(usize, self.binding_offsets[owner], reference.binding) catch return null;
        if (index >= self.slots.len or self.slots[index].state != .complete) return null;
        return self.slots[index].value;
    }

    pub fn prepare(self: *Session, reference: core.BindingRef) Error!void {
        return self.prepareWork(.{ .binding = try self.target(null, reference) });
    }
    fn prepareWork(self: *Session, initial: Work) Error!void {
        if (self.diagnostic != null) return error.Declined;
        if (self.visited_nodes.len != self.node_count) {
            const visited = try self.allocator.alloc(bool, self.node_count);
            @memset(visited, false);
            self.allocator.free(self.visited_nodes);
            self.visited_nodes = visited;
        }
        const pending_start = self.pending.items.len;
        var work: std.ArrayList(Work) = .empty;
        defer work.deinit(self.allocator);
        try work.append(self.allocator, initial);
        while (work.pop()) |item| switch (item) {
            .binding => |raw| {
                const resolved = try self.external(raw);
                const module = &self.units[resolved.unit];
                const binding = module.binding(resolved.binding);
                if (binding.kind != .global) continue;
                if (self.slot(resolved).traced) continue;
                const body = module.body(resolved.binding) orelse return self.fail(resolved.unit, binding.span, .unsupported);
                if (body.runtime and !self.options.trace_runtime_dependencies) return self.fail(resolved.unit, body.span, .unsupported);
                self.slot(resolved).traced = true;
                self.traced_bodies += 1;
                if (!body.is_function and !body.runtime) try self.pending.append(self.allocator, resolved);
                try work.append(self.allocator, .{ .node = .{ .unit = resolved.unit, .id = body.root } });
            },
            .node => |operation| {
                if (operation.id == 0) continue;
                const module = &self.units[operation.unit];
                if (operation.id >= module.nodes.len) return self.fail(operation.unit, .{ .start = 0, .end = 0 }, .unsupported);
                const seen = &self.visited_nodes[self.node_offsets[operation.unit] + operation.id];
                if (seen.*) continue;
                seen.* = true;
                self.traced_nodes += 1;
                const n = module.node(operation.id);
                if (std.sort.binarySearch(core.ErasedDeclarationReference, module.erased_declaration_references, operation.id, struct {
                    fn compare(key: core.Id, stored_reference: core.ErasedDeclarationReference) std.math.Order {
                        return std.math.order(key, stored_reference.node);
                    }
                }.compare)) |i| try work.append(self.allocator, .{ .binding = try self.target(operation.unit, module.erased_declaration_references[i].target) });
                switch (n.tag) {
                    .staging => {
                        if (n.a != 0) try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.a } });
                        if (n.b != 0) try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.b } });
                    },
                    .task, .package_pack => for (module.children(operation.id)) |child| try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = child } }),
                    .usage_share, .usage_read => try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.a } }),
                    .package_unpack => {
                        try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = module.packageOpening(operation.id).body } });
                        try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.a } });
                    },
                    .constant, .primitive_function, .panic => {},
                    .suspend_ => if (self.options.trace_runtime_dependencies) {
                        // Source selection retains named declarations inside a
                        // waiting demand, without forcing its expression/value.
                        try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = module.suspension(operation.id).body } });
                    },
                    .reference => try work.append(self.allocator, .{ .binding = try self.target(operation.unit, module.reference(operation.id)) }),
                    .resource_acquire, .usage_borrow, .scalar, .logical, .associated, .record_merge, .type_same, .effect_provider, .handle, .proof_guard => {
                        if (n.b != 0) try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.b } });
                        try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.a } });
                    },
                    .call, .contract_method, .block, .suite, .product, .record, .array, .array_op => {
                        const children = module.children(operation.id);
                        var index = children.len;
                        while (index != 0) {
                            index -= 1;
                            try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = children[index] } });
                        }
                        if (n.tag == .call) try work.append(self.allocator, .{ .binding = try self.target(operation.unit, module.call(operation.id).target) });
                    },
                    .resource_scope, .if_value, .if_stmt, .state_provider => {
                        if (n.c != 0) try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.c } });
                        try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.b } });
                        try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.a } });
                    },
                    .bind => try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.b } }),
                    .resource_release, .return_, .result_associated, .force => try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.a } }),
                    .construct => if (n.b != 0) try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.b } }),
                    .project => try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.a } }),
                    .closure => try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = module.closure(operation.id).body } }),
                    .apply => {
                        try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.b } });
                        try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.a } });
                    },
                    .effect_reflection => {
                        const kind: checked_types.ReflectionKind = @fromBackingInt(@intCast(n.a));
                        if (kind == .count or kind == .has or kind == .same) try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.b } });
                        if (n.c != 0) try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.c } });
                    },
                    .computation, .effect_scope => try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.a } }),
                    .request_decision => {
                        if (n.c != 0) try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.c } });
                        if (n.b != 0) try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.b } });
                    },
                    .request_loop => {
                        const metadata = module.requestLoopInfo(operation.id);
                        try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = metadata.completion_body } });
                        try work.append(self.allocator, .{ .pattern = .{ .unit = operation.unit, .id = metadata.completion_pattern } });
                        for (module.requestArms(operation.id)) |arm| try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = arm.callback } });
                        try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = metadata.computation } });
                    },
                    .constructor_function, .type_constructor, .operation_value => {},
                    .resolver_op => {
                        const metadata = module.resolverInfo(operation.id);
                        const children_ = module.resolverArguments(operation.id);
                        var index = children_.len;
                        while (index != 0) {
                            index -= 1;
                            try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = children_[index] } });
                        }
                        try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = metadata.resolver } });
                        if (metadata.method.binding != 0) try work.append(self.allocator, .{ .binding = try self.target(operation.unit, metadata.method) });
                    },
                    .pattern_bind => {
                        if (n.c != 0) try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.c } });
                        try work.append(self.allocator, .{ .pattern = .{ .unit = operation.unit, .id = n.a } });
                        try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.b } });
                    },
                    .match => {
                        const arms = module.matchArms(operation.id);
                        var arm_index = arms.len;
                        while (arm_index != 0) {
                            arm_index -= 1;
                            const arm = arms[arm_index];
                            try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = arm.body } });
                            if (arm.guard != 0) try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = arm.guard } });
                            const rows = module.armRows(arm);
                            var row_index = rows.len;
                            while (row_index != 0) {
                                row_index -= 1;
                                const patterns = module.rowPatterns(rows[row_index]);
                                var pattern_index = patterns.len;
                                while (pattern_index != 0) {
                                    pattern_index -= 1;
                                    try work.append(self.allocator, .{ .pattern = .{ .unit = operation.unit, .id = patterns[pattern_index] } });
                                }
                            }
                        }
                        const inputs = module.matchInputs(operation.id);
                        var input_index = inputs.len;
                        while (input_index != 0) {
                            input_index -= 1;
                            try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = inputs[input_index] } });
                        }
                    },
                    .update => {
                        const metadata = module.updateInfo(operation.id);
                        try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = metadata.value } });
                        try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = metadata.root } });
                    },
                    .loop => {
                        const iteration = module.loopInfo(operation.id);
                        try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = iteration.body } });
                        if (iteration.pattern != 0) try work.append(self.allocator, .{ .pattern = .{ .unit = operation.unit, .id = iteration.pattern } });
                        if (iteration.end != 0) try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = iteration.end } });
                        if (iteration.first != 0) try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = iteration.first } });
                    },
                    .break_ => {
                        const children = module.breakValues(operation.id);
                        var index = children.len;
                        while (index != 0) {
                            index -= 1;
                            try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = children[index] } });
                        }
                    },
                    .invalid => return self.failNode(operation.unit, operation.id, .unsupported),
                }
            },
            .pattern => |operation| {
                const module = &self.units[operation.unit];
                const pattern = module.pattern(operation.id);
                switch (pattern.tag) {
                    .wildcard, .bind, .constant => {},
                    .value => try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = pattern.a } }),
                    .constructor, .record_payload => if (pattern.b != 0) try work.append(self.allocator, .{ .pattern = .{ .unit = operation.unit, .id = pattern.b } }),
                    .product => {
                        const children = module.patternChildren(operation.id);
                        var index = children.len;
                        while (index != 0) {
                            index -= 1;
                            try work.append(self.allocator, .{ .pattern = .{ .unit = operation.unit, .id = children[index] } });
                        }
                    },
                    .invalid => return self.fail(operation.unit, pattern.span, .unsupported),
                }
            },
        };
        // Nested lookup/forcing must demand its newly reached constants before
        // publishing a value, but cannot start older queued dependents while
        // their input constant is still active in the outer drain.
        if (self.draining_pending) {
            var index = pending_start;
            while (index < self.pending.items.len) : (index += 1) {
                const dependency = self.pending.items[index];
                if (self.slot(dependency).state != .evaluating) _ = try self.constant(dependency);
            }
            return;
        }
        self.draining_pending = true;
        defer self.draining_pending = false;
        while (self.demanded < self.pending.items.len) {
            const dependency = self.pending.items[self.demanded];
            // A method chosen during evaluation can discover dependencies while
            // its surrounding constant is on this queue. The active root is
            // already being evaluated; actual cyclic reads still fail in
            // constant(), and newly appended named constants are demanded here.
            if (self.slot(dependency).state != .evaluating) _ = try self.constant(dependency);
            self.demanded += 1;
        }
    }

    pub fn value(self: *Session, reference: core.BindingRef) Error!Value {
        const id = try self.richValue(reference);
        const resolved = try self.target(null, reference);
        return self.valueScalar(id) orelse return self.fail(resolved.unit, self.units[resolved.unit].binding(resolved.binding).span, .unsupported);
    }
    pub fn richValue(self: *Session, reference: core.BindingRef) Error!ValueId {
        try self.prepare(reference);
        return self.constant(try self.target(null, reference));
    }
    pub fn closedNode(self: *Session, unit: u32, id: core.Id, values: *const std.AutoHashMapUnmanaged(core.BindingId, ValueId), mappings: []const type_evidence.Mapping, rows: []const type_evidence.RowMapping) Error!ValueId {
        var owner: ?usize = null;
        for (self.units, 0..) |_, index| if (self.unitId(index) == unit) {
            owner = index;
            break;
        };
        const producer = owner orelse return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .stage_unavailable);
        var frame: Frame = .{};
        defer frame.deinit(self.allocator);
        frame.values = try values.clone(self.allocator);
        try frame.mappings.appendSlice(self.allocator, mappings);
        try frame.row_mappings.appendSlice(self.allocator, rows);
        const result = try self.expression(producer, id, &frame);
        if (result != .value) return self.failNode(producer, id, .stage_unavailable);
        return result.value;
    }
    /// Closed constructor evaluation owns a finite body proof. It builds value
    /// graphs without demanding concrete evidence for generalized callback
    /// fields; those callables are specialized only at their later use.
    pub fn closedConstructorNode(self: *Session, unit: u32, id: core.Id) Error!ValueId {
        if (@import("closed_local_value.zig").analyze(self.units, unit, id) == null) return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .stage_unavailable);
        const previous = self.closed_constructor;
        self.closed_constructor = true;
        defer self.closed_constructor = previous;
        const values: std.AutoHashMapUnmanaged(core.BindingId, ValueId) = .empty;
        return self.closedNode(unit, id, &values, &.{}, &.{});
    }
    /// Attempts a closed initializer without a totality proof. It may read
    /// only enclosing locals that already hold evaluator `values`. Any
    /// failure, including a read of another enclosing local, declines without
    /// publishing a diagnostic, so the caller keeps its ordinary runtime path.
    pub fn attemptClosedNode(self: *Session, unit: u32, id: core.Id, values: *const std.AutoHashMapUnmanaged(core.BindingId, ValueId)) Allocator.Error!?ValueId {
        const saved = self.diagnostic;
        return self.closedNode(unit, id, values, &.{}, &.{}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                self.diagnostic = saved;
                return null;
            },
        };
    }
    pub fn stagedReplacement(self: *const Session, code_value: ValueId, id: core.Id) ?ValueId {
        if (self.valueInfo(code_value).kind != .code) return null;
        for (self.valueChildren(code_value)) |replacement| {
            const info = self.valueInfo(replacement);
            if (info.kind == .staged_value and info.nominal == id and info.len == 1) return self.valueChildren(replacement)[0];
        }
        return null;
    }
    pub fn stagedInfo(self: *const Session, value_: ValueId) ?ClosureValue {
        const info = self.valueInfo(value_);
        if (info.kind != .code or info.bits >= self.storage.closures.items.len) return null;
        return self.storage.closures.items[info.bits];
    }
    /// A proven tape reaches this dependency at its ordinary resource position.
    /// The replay owner must abort the attempt if later validation fails.
    pub fn receiptRead(self: *Session, reference: core.BindingRef) Error!ValueId {
        return self.constant(try self.target(null, reference));
    }
    fn constant(self: *Session, raw: Target) Error!ValueId {
        const resolved = try self.external(raw);
        const reference: core.BindingRef = .{ .unit = self.unitId(resolved.unit), .binding = resolved.binding };
        const parent = self.constant_recorder;
        if (parent) |recorder| try recorder.beforeRead(self.allocator, self);
        self.constant_recorder = null;
        defer self.constant_recorder = parent;
        const was_ready = self.slot(resolved).state == .complete;
        const value_ = try self.constantInner(resolved);
        if (self.member_trace) |trace| trace.readyRead(.{ .target = reference, .value = value_ }, was_ready);
        if (parent) |recorder| try recorder.read(self.allocator, self, reference, value_);
        return value_;
    }
    fn constantInner(self: *Session, resolved: Target) Error!ValueId {
        const timing = if (self.timing) |work| work.enter(.evaluation) else null;
        defer if (timing) |scope| scope.deinit();
        if (self.principal_reads) |reads| reads.invalidate(.evaluate);
        const module = &self.units[resolved.unit];
        const binding = module.binding(resolved.binding);
        const body = module.body(resolved.binding) orelse return self.fail(resolved.unit, binding.span, .unsupported);
        if (binding.kind != .global) return self.fail(resolved.unit, body.span, .unsupported);
        if (body.runtime) {
            const point = if (body.is_function) module.runtimeNamePoint(resolved.binding) else 0;
            const failed = self.fail(resolved.unit, .{ .start = point, .end = point }, .const_runtime_dependency);
            if (body.is_function) self.diagnostic.?.detail = "a const initializer cannot read a top-level let function";
            return failed;
        }
        const previous = self.slot(resolved).state;
        if (previous == .complete) return self.slot(resolved).value;
        if (previous == .evaluating) return self.fail(resolved.unit, body.span, .cycle);
        const reference: core.BindingRef = .{ .unit = self.unitId(resolved.unit), .binding = resolved.binding };
        const previous_producer = self.source_producer;
        self.source_producer = resolved;
        defer self.source_producer = previous_producer;
        self.slot(resolved).state = .evaluating;
        errdefer self.slot(resolved).state = .unseen;
        if (body.is_function) {
            const closure = try self.makeClosure(resolved.unit, body.root, .{ .origin = .named, .unit = self.unitId(resolved.unit), .identity = resolved.binding }, &.{});
            self.slot(resolved).value = closure;
            self.slot(resolved).state = .complete;
            return closure;
        }
        var frame: Frame = .{};
        defer frame.deinit(self.allocator);
        if (body.scheme.obligations.len != 0) evidence: {
            var solved = (try self.principalEvidence(resolved, body, binding.ty)) orelse break :evidence;
            defer solved.deinit(self.allocator);
            try frame.mappings.appendSlice(self.allocator, solved.types);
            try frame.row_mappings.appendSlice(self.allocator, solved.rows);
        }
        // Principal and publication inference retain their ordinary positions
        // and all budget/cache effects. This receipt skips only value work.
        const inputs: @import("../reuse/constant_receipt.zig").Inputs = .{ .types = frame.mappings.items, .rows = frame.row_mappings.items };
        var pending: ?@import("../reuse/constant_receipt.zig").Record = null;
        defer if (pending) |*record| record.deinit(self.allocator);
        var outcome: ?ValueId = null;
        const recordable = @import("../reuse/constant_receipt.zig").recordable(module, body.root, body.scheme.root);
        if (recordable) {
            if (self.constant_provider) |provider| if (try provider.lookup(provider.context, self, reference, inputs)) |completed| {
                outcome = completed.value;
                frame.mappings.clearRetainingCapacity();
                frame.row_mappings.clearRetainingCapacity();
                try frame.mappings.appendSlice(self.allocator, completed.outputs.types);
                try frame.row_mappings.appendSlice(self.allocator, completed.outputs.rows);
            };
            if (self.constant_receipt_retry) return error.Declined;
        }
        if (outcome == null) {
            var recording = @import("../reuse/constant_receipt.zig").Recorder.init(self);
            defer recording.deinit(self.allocator);
            if (self.retain_constant_receipts and recordable) {
                try recording.captureInputs(self.allocator, inputs);
                self.constant_recorder = &recording;
            }
            defer self.constant_recorder = null;
            const flow = try self.expression(resolved.unit, body.root, &frame);
            outcome = switch (flow) {
                .value => |value_| value_,
                .returning, .breaking => return self.fail(resolved.unit, body.span, .unsupported),
            };
            if (self.constant_recorder != null) {
                pending = try recording.finish(self.allocator, self, reference, outcome.?, .{ .types = frame.mappings.items, .rows = frame.row_mappings.items });
            }
        }
        const result = outcome.?;
        if (self.valueInfo(result).kind != .closure and self.hasExplicitScheme(resolved.unit, body.scheme)) {
            const actual_value = self.valueEvidence(result);
            if (actual_value != 0 and !try self.matchType(resolved.unit, body.root, resolved.unit, body.scheme.root, actual_value, &frame.mappings, &frame.row_mappings))
                return self.failNode(resolved.unit, body.root, .type_mismatch);
            try self.validateScheme(resolved.unit, body.root, body.scheme, &frame, false);
        }
        // A constant publishes its checked principal interface. The raw body
        // may retain covariant row variables for later contextual uses, while
        // the principal type records its exact certified closing decisions.
        const actual = try self.projectType(resolved.unit, body.root, body.scheme.root, frame.mappings.items, frame.row_mappings.items);
        const published = try self.typedView(resolved.unit, body.root, result, actual);
        // Neither a failed publication query nor OOM publishes a new owner.
        // The successful raw-value tape moves only after ordinary validation.
        if (pending) |record| {
            try self.retained.constant_records.append(self.allocator, record);
            pending = null;
            self.constant_stats.recorded += 1;
            for (record.events) |event| switch (event) {
                .query => self.constant_stats.queries_recorded += 1,
                else => {},
            };
            self.constant_stats.owned_payload_bytes += record.ownedBytes();
        }
        self.slot(resolved).value = published;
        self.slot(resolved).state = .complete;
        return published;
    }
    fn observePrincipalSource(self: *Session, owner: usize, binding: core.BindingId) Allocator.Error!void {
        const reads = self.principal_reads orelse return;
        if (owner >= self.units.len or binding == 0 or binding >= self.units[owner].bindings.len) {
            reads.source_complete = false;
            return;
        }
        const unit = self.unitId(owner);
        if (self.units[owner].binding(binding).kind == .global) {
            try reads.source(self.allocator, .{ .unit = unit, .binding = binding });
        } else if (try self.regions.principal_source_owners.binding(self.allocator, self.units, owner, binding, self.options.max_values)) |declaration| {
            try reads.source(self.allocator, .{ .unit = unit, .binding = declaration });
            self.counters.principal_containing_sources += 1;
        } else {
            try reads.sourceUnit(self.allocator, unit);
            self.counters.principal_module_sources += 1;
        }
    }
    fn principalSummaryKey(self: *const Session, key: principal_inputs.SummaryKey) ?CallSummaries.Key {
        if (key.target.unit == 0 or key.target.unit > self.units.len or key.target.binding == 0 or key.target.binding >= self.units[key.target.unit - 1].bindings.len) return null;
        return .{ .target = .{ .unit = key.target.unit - 1, .binding = key.target.binding }, .inputs = key.inputs, .source_interface = false, .deferred_member = key.deferred_member, .options = self.options };
    }
    pub fn principalSummaryMatches(self: *const Session, fact: principal_inputs.Summary) bool {
        const key = self.principalSummaryKey(fact.key) orelse return false;
        const index = self.specializations.call_summaries.keys.get(key) orelse return false;
        const job = self.specializations.call_summaries.jobs.items[index];
        return job.state == .complete and job.result == fact.result;
    }
    pub fn reservePrincipalSummaries(self: *Session, count: usize) Allocator.Error!void {
        try self.specializations.call_summaries.keys.ensureUnusedCapacity(self.allocator, @intCast(count));
        try self.specializations.call_summaries.jobs.ensureUnusedCapacity(self.allocator, count);
    }
    /// The caller has proved the complete source/input key and translated both
    /// graphs. These are closed memo judgments, never global call certificates.
    pub fn publishPrincipalSummary(self: *Session, fact: principal_inputs.Summary) void {
        const key = self.principalSummaryKey(fact.key) orelse return;
        const summaries = &self.specializations.call_summaries;
        // Preserve pending work and already-owned outcomes at this key.
        if (summaries.keys.contains(key) or summaries.jobs.items.len >= self.options.max_values) return;
        const index = summaries.jobs.items.len;
        summaries.jobs.appendAssumeCapacity(.{ .key = key, .state = .complete, .result = fact.result });
        summaries.keys.putAssumeCapacity(key, index);
    }
    fn principalEvidence(self: *Session, resolved: Target, body: *const core.Body, binding_type: types.Id) Error!?SolvedEvidence {
        self.observeConstantInference();
        const principal_target: core.BindingRef = .{ .unit = self.unitId(resolved.unit), .binding = resolved.binding };
        if (self.principal_provider) |provider| if (try provider.lookup(provider.context, principal_target, self.options)) |cached| {
            var solved = cached;
            errdefer solved.deinit(self.allocator);
            try provider.record(provider.context, principal_target, self.options, solved, null);
            return solved;
        };
        if (self.principal_provider != null) self.principal_regions += 1;
        self.principal_recordings += 1;
        var reads: principal_inputs.Recorder = .{ .eligible = true, .empty_call_inputs = self.specializations.validated_calls.count() == 0, .root = principal_target, .max_reads = self.options.max_values, .serial = self.principal_recordings };
        defer reads.deinit(self.allocator);
        const previous_reads = self.principal_reads;
        const recording = self.principal_provider != null;
        if (recording) try reads.source(self.allocator, principal_target);
        if (recording) self.principal_reads = &reads;
        defer self.principal_reads = previous_reads;
        var region = ClosureRegion.initAt(self, @src()) catch return error.OutOfMemory;
        defer region.deinit();
        defer region.profile_rejected = reads.rejected;
        region.profile_principal = true;
        region.profile_input_calls = self.specializations.validated_calls.count();
        var solved = region.bodyEvidenceMode(resolved.unit, body.root, binding_type, body.closed_rows, body.scheme, .{ .semantic = 0 }, &.{}, &.{}, true) catch |err| ordinary: {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            if (region.principal_only_used) {
                self.discardDiagnostic();
                const sharing = self.reuse_principal_graphs;
                self.reuse_principal_graphs = false;
                defer self.reuse_principal_graphs = sharing;
                var fallback = ClosureRegion.initAt(self, @src()) catch return error.OutOfMemory;
                defer fallback.deinit();
                break :ordinary fallback.bodyEvidenceMode(resolved.unit, body.root, binding_type, body.closed_rows, body.scheme, .{ .semantic = 0 }, &.{}, &.{}, true) catch |failed| switch (failed) {
                    error.UnresolvedType => return null,
                    else => return self.evidenceFailure(resolved.unit, body.span, failed),
                };
            }
            // Partial source results preserve unresolved facts; ordinary fresh
            // evaluation still owns value-dependent obligations and diagnostics.
            if (err == error.UnresolvedType) return null;
            return self.evidenceFailure(resolved.unit, body.span, err);
        };
        errdefer solved.deinit(self.allocator);
        const key = if (recording) reads.key() else null;
        region.profile_recorded_inputs = key != null;
        region.profile_output_types = solved.types.len;
        region.profile_output_rows = solved.rows.len;
        if (self.principal_provider) |provider| try provider.record(provider.context, principal_target, self.options, solved, if (key) |*input| input else null);
        return solved;
    }
    fn expression(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const outcome = try self.expressionInner(owner, id, frame);
        if (outcome != .value or id == 0) return outcome;
        var actual = try self.projectType(owner, id, self.units[owner].typeOf(id), frame.mappings.items, frame.row_mappings.items);
        if (actual == 0) actual = try self.principalValueType(owner, id, outcome.value, frame);
        return .{ .value = try self.typedView(owner, id, outcome.value, actual) };
    }
    fn reflectionLabel(self: *Session, owner: usize, id: core.Id, label: u32, frame: *const Frame) Error!u32 {
        const operation = self.units[owner].types.operation(label);
        var arguments: std.ArrayList(type_evidence.Id) = .empty;
        defer arguments.deinit(self.allocator);
        for (self.units[owner].types.operationArguments(label)) |argument| {
            const actual = try self.projectType(owner, id, argument, frame.mappings.items, frame.row_mappings.items);
            if (actual == 0) return self.failNode(owner, id, .unsupported);
            try arguments.append(self.allocator, actual);
        }
        return self.storage.evidence.effects.internOperationInstance(operation.identity, arguments.items, operation.instance) catch |err| return self.evidenceFailure(owner, self.units[owner].span(id), err);
    }
    fn containsReflectionType(self: *Session, owner: usize, id: core.Id, evidence: type_evidence.Id, depth: usize) Error!bool {
        if (evidence == 0) return false;
        if (depth >= 1024) return self.failNode(owner, id, .ambiguous_state);
        const n = self.storage.evidence.node(evidence);
        switch (n.tag) {
            .nominal => {
                if (types.isReflectionIdentity(n.a, n.b)) return true;
                for (self.storage.evidence.children(evidence)) |child| if (try self.containsReflectionType(owner, id, child, depth + 1)) return true;
            },
            .product => for (self.storage.evidence.children(evidence)) |child| {
                if (try self.containsReflectionType(owner, id, child, depth + 1)) return true;
            },
            .record => {
                const fields = self.storage.evidence.children(evidence);
                var index: usize = 1;
                while (index < fields.len) : (index += 2) if (try self.containsReflectionType(owner, id, fields[index], depth + 1)) return true;
            },
            .function => return try self.containsReflectionType(owner, id, n.a, depth + 1) or try self.containsReflectionType(owner, id, n.b, depth + 1),
            .array, .demand, .provider => return self.containsReflectionType(owner, id, n.a, depth + 1),
            .state_provider => return try self.containsReflectionType(owner, id, n.a, depth + 1) or try self.containsReflectionType(owner, id, n.b, depth + 1) or try self.containsReflectionType(owner, id, n.c, depth + 1),
            else => {},
        }
        return false;
    }
    fn witnessHead(self: *Session, value_: ValueId) Error!type_evidence.Id {
        var actual = self.valueEvidence(value_);
        if (actual == 0 and self.valueInfo(value_).kind == .closure) {
            const closure = self.closureInfo(value_);
            const owner = self.findUnit(closure.unit, null) orelse return 0;
            const module = &self.units[owner];
            var ty = switch (closure.origin) {
                .anonymous => module.closures[closure.identity].function_type,
                .named => module.binding(closure.identity).ty,
                .constructor => module.constructor(closure.identity).scheme.root,
                .primitive => closure.ty,
                .operation => module.operation_values[closure.identity].signature,
            };
            for (0..1024) |_| {
                const node = module.types.node(ty);
                if (node.tag != .function) break;
                ty = node.b;
            } else return 0;
            actual = try self.projectType(owner, 0, ty, self.storage.type_mappings.items[closure.mappings.start..][0..closure.mappings.len], self.storage.row_mappings.items[closure.row_mappings.start..][0..closure.row_mappings.len]);
        }
        for (0..1024) |_| {
            const node = self.storage.evidence.node(actual);
            if (node.tag != .function) return actual;
            actual = node.b;
        } else return 0;
    }
    fn principalValueType(self: *Session, owner: usize, id: core.Id, value_: ValueId, frame: *const Frame) Error!type_evidence.Id {
        const module = &self.units[owner];
        const node = module.node(id);
        if (node.tag == .staging and node.c == @backingInt(@import("../check/typed_staging.zig").Op.quote)) {
            const metadata = self.stagedInfo(value_) orelse return self.failNode(owner, id, .code_shape_mismatch);
            return self.projectType(owner, id, node.ty, self.storage.type_mappings.items[metadata.mappings.start..][0..metadata.mappings.len], self.storage.row_mappings.items[metadata.row_mappings.start..][0..metadata.row_mappings.len]);
        }
        if (node.tag == .constructor_function) return self.projectType(owner, id, module.constructor(node.a).scheme.root, frame.mappings.items, frame.row_mappings.items);
        if (node.tag == .operation_value) {
            const operation = module.operationValue(id);
            for (module.types.list(operation.arguments)) |argument| {
                if (try self.projectType(owner, id, argument, frame.mappings.items, frame.row_mappings.items) == 0) return 0;
            }
            return self.operationSignature(owner, id, value_, try self.operationToken(owner, id, value_));
        }
        const certificates = if (node.tag == .closure) module.types.list(module.closure(id).closed_rows) else &.{};
        if (certificates.len == 0 and node.tag != .construct and node.tag != .product and node.tag != .record and node.tag != .array) return 0;
        var mappings: std.ArrayList(type_evidence.Mapping) = .empty;
        defer mappings.deinit(self.allocator);
        var rows: std.ArrayList(type_evidence.RowMapping) = .empty;
        defer rows.deinit(self.allocator);
        try mappings.appendSlice(self.allocator, frame.mappings.items);
        try rows.appendSlice(self.allocator, frame.row_mappings.items);
        // Publish only the lambda's recorded principal closing decision. An
        // already selected contextual row overrides that certificate, and the
        // immutable closure retains its raw type for subsequent instantiation.
        for (certificates) |variable| {
            const mapped = for (rows.items) |mapping| {
                if (mapping.variable == variable) break true;
            } else false;
            if (!mapped) try rows.append(self.allocator, .{ .variable = variable, .evidence = 0 });
        }
        if (node.tag == .construct and node.b != 0) {
            const children = self.valueChildren(value_);
            if (children.len != 1) return self.failNode(owner, id, .unsupported);
            const child_type = if (node.c != 0) try self.canonicalRecordEvidence(owner, id, children[0]) else self.valueEvidence(children[0]);
            if (child_type != 0 and !try self.matchType(owner, id, owner, module.typeOf(node.b), child_type, &mappings, &rows)) return self.failNode(owner, id, .unsupported);
        } else if (node.tag == .product or node.tag == .record or node.tag == .array) {
            const children = self.valueChildren(value_);
            const expressions = module.children(id);
            if (expressions.len != children.len) return 0;
            const destinations = if (node.tag == .record) module.recordDestinations(id) else &.{};
            for (expressions, 0..) |child, index| {
                const destination = if (node.tag == .record) destinations[index] else index;
                if (destination >= children.len) return self.failNode(owner, id, .unsupported);
                const child_type = self.valueEvidence(children[destination]);
                if (child_type != 0 and !try self.matchType(owner, id, owner, module.typeOf(child), child_type, &mappings, &rows)) return self.failNode(owner, id, .unsupported);
            }
        }
        return self.projectType(owner, id, node.ty, mappings.items, rows.items);
    }
    const RaggedFacts = struct {
        session: *Session,
        owner: usize,
        frame: *Frame,
        module: *const core.Module,
        operations: [256]struct { id: core.Id, operation: primitive_operator.Operation } = undefined,
        operation_count: usize = 0,
        fields: [256]core.Id = undefined,
        field_count: usize = 0,
        remaining: usize = 256,

        fn prepare(self: *@This(), id: core.Id) Error!bool {
            if (id == 0) return true;
            if (self.remaining == 0) return false;
            self.remaining -= 1;
            const n = self.module.node(id);
            switch (n.tag) {
                .scalar, .associated, .call => {
                    if (try self.selected(id)) |operation_| {
                        self.operations[self.operation_count] = .{ .id = id, .operation = operation_ };
                        self.operation_count += 1;
                    }
                    if (n.tag == .call) {
                        for (self.module.children(id)) |child| if (!try self.prepare(child)) return false;
                        return true;
                    }
                    return try self.prepare(n.a) and try self.prepare(n.b);
                },
                .project => {
                    const projection = self.module.projection(n.b);
                    const evidence = try self.session.projectType(self.owner, id, self.module.typeOf(n.a), self.frame.mappings.items, self.frame.row_mappings.items);
                    if (self.module.projectionVariants(n.b).len != 0 or (evidence != 0 and self.session.storage.evidence.node(evidence).tag == .record and projection.field != 0)) {
                        self.fields[self.field_count] = id;
                        self.field_count += 1;
                    }
                    return self.prepare(n.a);
                },
                .logical => return try self.prepare(n.a) and try self.prepare(n.b),
                .if_value, .if_stmt => return try self.prepare(n.a) and try self.prepare(n.b) and try self.prepare(n.c),
                .bind => return self.prepare(n.b),
                .return_ => return self.prepare(n.a),
                .block, .suite, .array, .array_op => {
                    for (self.module.children(id)) |child| if (!try self.prepare(child)) return false;
                },
                .loop => {
                    const info = self.module.loopInfo(id);
                    return try self.prepare(info.first) and try self.prepare(info.end) and try self.prepare(info.body);
                },
                else => {},
            }
            return true;
        }
        fn selected(self: *@This(), id: core.Id) Error!?primitive_operator.Operation {
            const n = self.module.node(id);
            if (n.tag == .scalar and n.c == 0) return .{ .op = n.op };
            const session = self.session;
            var first = n.a;
            var second = n.b;
            if (n.tag == .call) {
                const args = self.module.children(id);
                if (args.len != 2) return null;
                first = args[0];
                second = args[1];
            }
            const left = try session.projectType(self.owner, id, self.module.typeOf(first), self.frame.mappings.items, self.frame.row_mappings.items);
            const right = try session.projectType(self.owner, id, self.module.typeOf(second), self.frame.mappings.items, self.frame.row_mappings.items);
            if (left == 0 or left != right) return null;
            const tag = session.storage.evidence.node(left).tag;
            if (tag != .u32 and tag != .f32 and tag != .boolean) return null;
            if (n.tag == .call) {
                var machine: @import("../backend/wasm.zig").Scalar = .u32;
                if (tag == .f32) machine = .f32;
                if (tag == .boolean) machine = .bool;
                var target_ = self.module.call(id).target;
                if (target_.unit == 0) target_.unit = session.unitId(self.owner);
                return primitive_operator.analyzeTyped(session.units, target_, machine);
            }
            var member: u32 = 0;
            if (n.tag == .associated) member = n.c;
            const identity = session.evidenceIdentity(left) orelse return null;
            if (try session.associatedTarget(session.unitId(self.owner), identity, member, Session.operator(n.op))) |target_| return primitive_operator.analyze(session.units, target_);
            if (member != 0 or n.op == .none) return null;
            return .{ .op = n.op };
        }
        pub fn operation(self: @This(), id: core.Id) ?primitive_operator.Operation {
            for (self.operations[0..self.operation_count]) |entry| if (entry.id == id) return entry.operation;
            return null;
        }
        pub fn primitive(self: @This(), id: core.Id) bool {
            return primitive_operator.total(self.operation(id) orelse return false);
        }
        fn existing(self: @This(), ref: core.BindingRef) ?ValueId {
            var target_ = ref;
            if (target_.unit == 0) target_.unit = self.session.unitId(self.owner);
            const resolved = primitive_operator.resolve(self.session.units, target_) orelse return null;
            const owner_ = self.session.findUnit(resolved.unit, null) orelse return null;
            const stored = self.session.slot(.{ .unit = owner_, .binding = resolved.binding });
            if (stored.state != .complete) return null;
            return stored.value;
        }
        pub fn reference(self: @This(), id: core.Id) bool {
            const ref = self.module.reference(id);
            if (ref.unit == 0 or ref.unit == self.module.unit) {
                const kind = self.module.binding(ref.binding).kind;
                if (kind == .local or kind == .parameter) return true;
            }
            return self.existing(ref) != null;
        }
        pub fn field(self: @This(), id: core.Id) bool {
            for (self.fields[0..self.field_count]) |field_id| if (field_id == id) return true;
            return false;
        }
        fn irrefutable(self: @This(), id: core.PatternId, remaining: usize) bool {
            if (id == 0) return true;
            if (remaining == 0) return false;
            switch (self.module.pattern(id).tag) {
                .bind, .wildcard => return true,
                .product => {
                    for (self.module.patternChildren(id)) |child| if (!self.irrefutable(child, remaining - 1)) return false;
                    return true;
                },
                else => return false,
            }
        }
        pub fn pattern(self: @This(), id: core.Id) bool {
            return self.irrefutable(self.module.loopInfo(id).pattern, 16);
        }
        pub fn constantType(self: @This(), id: core.Id) ?@import("../backend/wasm.zig").Scalar {
            return switch (self.module.types.node(self.module.typeOf(id)).tag) {
                .unit => .unit,
                .u32 => .u32,
                .f32 => .f32,
                .boolean => .bool,
                else => null,
            };
        }
        pub fn scalar(self: @This(), value_: ValueId) ?Value {
            return self.session.valueScalar(value_);
        }
        pub fn lookup(self: @This(), ref: core.BindingRef) ?ragged_count.Value {
            if (ref.unit == 0 or ref.unit == self.module.unit) {
                if (self.frame.values.get(ref.binding)) |existing_value| return .{ .borrowed = existing_value };
            }
            return .{ .borrowed = self.existing(ref) orelse return null };
        }
        pub fn children(self: @This(), value_: ValueId) []const ValueId {
            return self.session.valueChildren(value_);
        }
        pub fn length(self: @This(), value_: ValueId) ?u32 {
            const info = self.session.valueInfo(value_);
            if (info.kind != .array and info.kind != .list) return null;
            return info.len;
        }
        pub fn project(self: @This(), id: core.Id, value_: ValueId) ?ragged_count.Value {
            const session = self.session;
            const projection = self.module.projection(self.module.node(id).b);
            const info = session.valueInfo(value_);
            if (info.kind == .record) {
                for (session.recordFieldNames(value_), 0..) |name, index| if (name == projection.field) return .{ .borrowed = session.valueChildren(value_)[index] };
                return null;
            }
            var container = value_;
            var field_: ?u32 = null;
            const variants = self.module.projectionVariants(self.module.node(id).b);
            if (info.kind == .nominal) {
                if (info.len != 1) return null;
                container = session.valueChildren(value_)[0];
                for (variants) |variant| if (variant.tag == info.bits) {
                    field_ = variant.field;
                    break;
                };
            } else if (projection.nominal.decl == 0 and variants.len == 1) field_ = variants[0].field;
            const field_index = field_ orelse return null;
            const payload = session.valueInfo(container);
            if ((payload.kind != .product and payload.kind != .record) or field_index >= payload.len) return null;
            return .{ .borrowed = session.valueChildren(container)[field_index] };
        }
    };
    fn blockChildren(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        for (module.children(id)) |child| {
            const outcome = try self.expression(owner, child, frame);
            if (outcome != .value) {
                if (module.node(id).tag == .block and outcome == .returning and outcome.returning.target == id) return .{ .value = outcome.returning.value };
                return outcome;
            }
        }
        return .{ .value = 0 };
    }
    fn raggedBlock(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!?Flow {
        const module = &self.units[owner];
        const body = module.children(id);
        if (body.len < 3 or module.node(body[0]).tag != .bind) return null;
        const initial = module.node(body[0]).b;
        if (module.node(initial).tag != .array or module.children(initial).len != 0) return null;
        var facts: RaggedFacts = .{ .session = self, .owner = owner, .frame = frame, .module = module };
        const diagnostic = self.diagnostic;
        const prepared = facts.prepare(id) catch |err| switch (err) {
            error.Declined => {
                // Speculative evidence limits cannot diagnose unreached source.
                self.diagnostic = diagnostic;
                return null;
            },
            else => return err,
        };
        if (!prepared) return null;
        const plan = ragged.analyze(module, id, facts) orelse return null;
        const available = @min(@as(usize, 4_194_303), self.options.max_children -| self.constantChildCount());
        var probe: ragged_count.Counter(RaggedFacts) = .{ .adapter = facts, .plan = plan, .remaining = self.ragged_probe_limit, .limit = @intCast(available) };
        const count = probe.run();
        self.counters.ragged_probe_visits += probe.visits;
        if (count == null) {
            self.counters.ragged_probe_declines += 1;
            return null;
        }
        const children_ = try self.allocator.alloc(ValueId, count.?);
        defer self.allocator.free(children_);
        var region: RaggedRegion = .{ .owner = owner, .frame = frame, .plan = plan, .children = children_ };
        self.ragged_reserved_children += count.?;
        defer if (region.reserved) {
            self.ragged_reserved_children -= count.?;
        };
        self.declineConstant();
        self.ragged_region = &region;
        defer self.ragged_region = null;
        const outcome = try self.blockChildren(owner, id, frame);
        if (outcome != .value) return outcome;
        std.debug.assert(region.written == children_.len);
        var result = outcome.value;
        if (region.published == null and count.? != 0) {
            self.ragged_reserved_children -= count.?;
            region.reserved = false;
            result = try self.makeAggregate(owner, id, .list, 0, 0, children_);
        }
        self.counters.ragged_staged_regions += 1;
        self.counters.ragged_selected += count.?;
        self.counters.ragged_published_children += count.?;
        return .{ .value = result };
    }
    fn literal(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!ValueId {
        const module = &self.units[owner];
        const node = module.node(id);
        if (node.ty >= module.types.nodes.len) return self.failNode(owner, id, .unsupported);
        var shape = module.types.node(node.ty);
        const qualified = shape.tag == .usage;
        if (qualified) {
            if (shape.c != 0 or (shape.b != @backingInt(types.UsageKind.unique) and shape.b != @backingInt(types.UsageKind.shared))) return self.failNode(owner, id, .unsupported);
            self.declineConstant();
            shape = module.types.node(shape.a);
        }
        const scalar: @TypeOf(unit_value.scalar) = switch (shape.tag) {
            .unit => .unit,
            .u32 => .u32,
            .f32 => .f32,
            .boolean => .bool,
            else => return self.failNode(owner, id, .unsupported),
        };
        const value_ = try self.makeScalar(owner, id, .{ .scalar = scalar, .bits = node.a });
        if (!qualified) return value_;
        const actual = try self.projectType(owner, id, node.ty, frame.mappings.items, frame.row_mappings.items);
        return self.typedView(owner, id, value_, actual);
    }
    fn referenceExpression(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const n = self.units[owner].node(id);
        const declared = module.reference(id);
        if ((declared.unit == 0 or declared.unit == self.unitId(owner)) and frame.values.get(declared.binding) != null) return .{ .value = frame.values.get(declared.binding).? };
        if (try self.dictionaryUse(owner, id, frame.mappings.items, frame.row_mappings.items)) |selected| {
            try self.prepare(selected.target);
            const resolved = try self.external(try self.target(owner, selected.target));
            return .{ .value = try self.typedView(owner, id, try self.constant(resolved), selected.signature) };
        }
        var reference = module.reference(id);
        if (self.has_implementations) {
            const actual = try self.projectType(owner, id, n.ty, frame.mappings.items, frame.row_mappings.items);
            reference = try self.selectTemplate(owner, id, reference, actual);
            if (!std.meta.eql(reference, module.reference(id))) try self.prepare(reference);
        }
        const resolved = try self.external(try self.target(owner, reference));
        const binding = self.units[resolved.unit].binding(resolved.binding);
        if (binding.kind == .local or binding.kind == .parameter) {
            if (resolved.unit != owner) return self.failNode(owner, id, .unsupported);
            return .{ .value = frame.values.get(resolved.binding) orelse return self.failNode(owner, id, .unsupported) };
        }
        return .{ .value = try self.constant(resolved) };
    }
    fn closureExpression(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const n = self.units[owner].node(id);
        const bindings = module.closureCaptures(id);
        var storage_buffer: [256]u8 align(@alignOf(usize)) = undefined;
        var storage: std.heap.BufferFirstAllocator = .init(&storage_buffer, self.allocator);
        const scratch = storage.allocator();
        const captures = try scratch.alloc(ValueId, bindings.len);
        defer scratch.free(captures);
        for (bindings, 0..) |binding, index| captures[index] = frame.values.get(binding) orelse return self.failNode(owner, id, .unsupported);
        return .{ .value = try self.makeClosure(owner, id, .{ .origin = .anonymous, .unit = self.unitId(owner), .identity = n.a, .staged = frame.staged orelse 0, .mappings = try self.captureMappings(owner, id, frame.mappings.items), .row_mappings = try self.captureRowMappings(owner, id, frame.row_mappings.items) }, captures) };
    }
    fn suspensionExpression(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        self.declineConstant();
        const module = &self.units[owner];
        const n = self.units[owner].node(id);
        const bindings = module.suspensionCaptures(id);
        var storage_buffer: [256]u8 align(@alignOf(usize)) = undefined;
        var storage: std.heap.BufferFirstAllocator = .init(&storage_buffer, self.allocator);
        const scratch = storage.allocator();
        const captures = try scratch.alloc(ValueId, bindings.len);
        defer scratch.free(captures);
        for (bindings, 0..) |binding, index| captures[index] = frame.values.get(binding) orelse return self.failNode(owner, id, .unsupported);
        const producer = if (self.options.retain_source_suspensions) self.source_producer else null;
        if (producer != null) {
            if (self.receipt_tape) |tape| tape.unknown = true;
        }
        if (producer != null) try self.retained.source_suspensions.ensureUnusedCapacity(self.allocator, 1);
        const demand = try self.makeClosure(owner, id, .{ .origin = .anonymous, .staged = frame.staged orelse 0, .unit = self.unitId(owner), .identity = n.a, .mappings = try self.captureMappings(owner, id, frame.mappings.items), .row_mappings = try self.captureRowMappings(owner, id, frame.row_mappings.items) }, captures);
        self.storage.values.items[demand].kind = .suspension;
        self.storage.values.items[demand].nominal = self.storage.values.items[demand].bits;
        if (producer) |target_| self.retained.source_suspensions.appendAssumeCapacity(.{ .producer = .{ .unit = self.unitId(target_.unit), .binding = target_.binding }, .unit = self.unitId(owner), .node = id, .value = demand });
        return .{ .value = demand };
    }
    fn reflectionExpression(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const n = self.units[owner].node(id);
        const kind: checked_types.ReflectionKind = @fromBackingInt(@intCast(n.a));
        if (kind == .of or kind == .descriptor) {
            const identity = if (kind == .of) types.effect_set_identity else types.effect_descriptor_identity;
            const evidence = self.storage.evidence.intern(.nominal, identity.unit, identity.decl, &.{}) catch |err| return self.evidenceFailure(owner, module.span(id), err);
            const bits = if (kind == .of) blk: {
                var labels: std.ArrayList(u32) = .empty;
                defer labels.deinit(self.allocator);
                for (module.types.rowLabels(n.b)) |label| try labels.append(self.allocator, try self.reflectionLabel(owner, id, label, frame));
                std.mem.sortUnstable(u32, labels.items, {}, std.sort.asc(u32));
                var kept: usize = 0;
                for (labels.items) |label| {
                    if (kept == 0 or labels.items[kept - 1] != label) {
                        labels.items[kept] = label;
                        kept += 1;
                    }
                }
                break :blk self.storage.evidence.effects.internRow(labels.items[0..kept]) catch |err| return self.evidenceFailure(owner, module.span(id), err);
            } else try self.reflectionLabel(owner, id, n.b, frame);
            const result = try self.makeAggregate(owner, id, if (kind == .of) .effect_set else .effect_descriptor, 0, bits, &.{});
            self.storage.value_evidence.items[result] = evidence;
            return .{ .value = result };
        }
        const left = try self.expression(owner, n.b, frame);
        if (left != .value) return left;
        const first = self.valueInfo(left.value);
        if (kind == .count) {
            if (first.kind != .effect_set) return self.failNode(owner, id, .type_mismatch);
            const labels = self.storage.evidence.effects.view().rowLabels(first.bits);
            return .{ .value = try self.makeScalar(owner, id, .{ .scalar = .u32, .bits = @intCast(labels.len) }) };
        }
        const right = try self.expression(owner, n.c, frame);
        if (right != .value) return right;
        const second = self.valueInfo(right.value);
        if (second.kind != .effect_descriptor) return self.failNode(owner, id, .type_mismatch);
        const matches = if (kind == .has) blk: {
            if (first.kind != .effect_set) return self.failNode(owner, id, .type_mismatch);
            break :blk std.mem.findScalar(u32, self.storage.evidence.effects.view().rowLabels(first.bits), second.bits) != null;
        } else blk: {
            if (first.kind != .effect_descriptor) return self.failNode(owner, id, .type_mismatch);
            break :blk first.bits == second.bits;
        };
        return .{ .value = try self.makeScalar(owner, id, .{ .scalar = .bool, .bits = @intFromBool(matches) }) };
    }
    fn operationExpression(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const n = self.units[owner].node(id);
        const operation = module.operationValue(id);
        var capability: ?ValueId = null;
        if (operation.capability != 0) {
            const value_ = try self.expression(owner, operation.capability, frame);
            if (value_ != .value) return value_;
            _ = try self.capabilityIdentity(owner, id, value_.value);
            capability = value_.value;
        }
        if (operation.witness != 0) {
            const witness = module.node(operation.witness);
            if (witness.tag != .reference) return self.failNode(owner, id, .unsupported);
            const reference = module.reference(operation.witness);
            const value_ = frame.values.get(reference.binding) orelse return self.failNode(owner, id, .unsupported);
            const head = try self.witnessHead(value_);
            if (try self.containsReflectionType(owner, id, head, 0)) return self.failNode(owner, id, .ambiguous_state);
            if (head == 0 or !try self.matchType(owner, id, owner, operation.witness_result, head, &frame.mappings, &frame.row_mappings)) return self.failNode(owner, id, .unsupported);
        }
        return .{ .value = try self.makeClosure(owner, id, .{ .origin = .operation, .unit = self.unitId(owner), .identity = n.a, .ty = n.ty, .mappings = try self.captureMappings(owner, id, frame.mappings.items), .row_mappings = try self.captureRowMappings(owner, id, frame.row_mappings.items) }, if (capability) |value_| &.{value_} else &.{}) };
    }
    fn stateProviderExpression(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const n = self.units[owner].node(id);
        const read = try self.expression(owner, n.a, frame);
        if (read != .value) return read;
        const write = try self.expression(owner, n.b, frame);
        if (write != .value) return write;
        const initial = try self.expression(owner, n.c, frame);
        if (initial != .value) return initial;
        if (try self.containsReflectionType(owner, id, self.valueEvidence(initial.value), 0)) return self.failNode(owner, id, .ambiguous_state);
        const read_token = try self.operationToken(owner, id, read.value);
        const write_token = try self.operationToken(owner, id, write.value);
        if (read_token == write_token) return self.failNode(owner, id, .invalid_provider);
        return .{ .value = try self.makeAggregate(owner, id, .state_provider, write_token, read_token, &.{initial.value}) };
    }
    fn applicationExpression(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const n = self.units[owner].node(id);
        const callee = try self.expression(owner, n.a, frame);
        if (callee != .value) return callee;
        const argument = try self.expression(owner, n.b, frame);
        if (argument != .value) return argument;
        return self.applyValue(owner, id, callee.value, argument.value, frame.providers) catch |err| {
            if (err == error.Declined and module.isTagCall(id)) {
                if (self.diagnostic) |*diagnostic| {
                    diagnostic.unit = self.unitId(owner);
                    diagnostic.span = module.span(id);
                    diagnostic.tag_origin = true;
                }
            }
            return err;
        };
    }
    fn sameTypeExpression(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const n = self.units[owner].node(id);
        const left = try self.expression(owner, n.a, frame);
        if (left != .value) return left;
        const right = try self.expression(owner, n.b, frame);
        if (right != .value) return right;
        var left_source = module.typeOf(n.a);
        var right_source = module.typeOf(n.b);
        while (module.types.node(left_source).tag == .function) left_source = module.types.node(left_source).b;
        while (module.types.node(right_source).tag == .function) right_source = module.types.node(right_source).b;
        var left_type = try self.projectType(owner, id, left_source, frame.mappings.items, frame.row_mappings.items);
        var right_type = try self.projectType(owner, id, right_source, frame.mappings.items, frame.row_mappings.items);
        if (left_type == 0) left_type = self.valueEvidence(left.value);
        if (right_type == 0) right_type = self.valueEvidence(right.value);
        if (left_type == 0 or right_type == 0) return self.failNode(owner, id, .unsupported);
        while (self.storage.evidence.node(left_type).tag == .function) left_type = self.storage.evidence.node(left_type).b;
        while (self.storage.evidence.node(right_type).tag == .function) right_type = self.storage.evidence.node(right_type).b;
        for ([_]type_evidence.Id{ left_type, right_type }) |selected| if (try self.containsReflectionType(owner, id, selected, 0)) return self.failNode(owner, id, .ambiguous_state);
        return .{ .value = try self.makeScalar(owner, id, .{ .scalar = .bool, .bits = @intFromBool(left_type == right_type) }) };
    }
    fn scalarExpression(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const n = self.units[owner].node(id);
        if (n.c != 0 and n.b != 0) return self.dispatch(owner, id, frame);
        const first = try self.expression(owner, n.a, frame);
        const a = switch (first) {
            .value => |value_| value_,
            .returning, .breaking => return first,
        };
        const second = try self.expression(owner, n.b, frame);
        const b = switch (second) {
            .value => |value_| value_,
            .returning, .breaking => return second,
        };
        if (self.valueInfo(a).kind == .product) return .{ .value = try self.simdValue(owner, id, n.op, a, b) };
        const result = scalar_ops.evaluate(n.op, try self.requireScalar(owner, id, a), try self.requireScalar(owner, id, b)) catch |err| return self.failNode(owner, id, switch (err) {
            error.IntegerDivideByZero => .integer_divide_by_zero,
            error.Unsupported => .unsupported,
        });
        return .{ .value = try self.makeScalar(owner, id, result) };
    }
    fn logicalExpression(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const n = self.units[owner].node(id);
        const first = try self.expression(owner, n.a, frame);
        const a = switch (first) {
            .value => |value_| value_,
            .returning, .breaking => return first,
        };
        const scalar_a = try self.requireScalar(owner, id, a);
        if (scalar_a.scalar != .bool) return self.failNode(owner, id, .unsupported);
        if ((n.op == .and_ and scalar_a.bits == 0) or (n.op == .or_ and scalar_a.bits != 0)) return .{ .value = a };
        if (n.op != .and_ and n.op != .or_) return self.failNode(owner, id, .unsupported);
        const second = try self.expression(owner, n.b, frame);
        if (second == .value and (try self.requireScalar(owner, id, second.value)).scalar != .bool) return self.failNode(owner, id, .unsupported);
        return second;
    }
    fn branchExpression(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const n = self.units[owner].node(id);
        const condition = try self.expression(owner, n.a, frame);
        const value_ = switch (condition) {
            .value => |value__| value__,
            .returning, .breaking => return condition,
        };
        const scalar_condition = try self.requireScalar(owner, id, value_);
        if (scalar_condition.scalar != .bool) return self.failNode(owner, id, .unsupported);
        const yes = scalar_condition.bits != 0;
        const selected = try self.expression(owner, if (yes) n.b else n.c, frame);
        if (n.tag == .if_value or selected != .value) return selected;
        for (module.branchMerges(id)) |merge| {
            const source = if (yes) merge.then_binding else merge.else_binding;
            const merged = frame.values.get(source) orelse return self.failNode(owner, id, .unsupported);
            try frame.values.put(self.allocator, merge.result, merged);
        }
        return .{ .value = 0 };
    }
    fn usageReadExpression(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const n = self.units[owner].node(id);
        const operand = try self.expression(owner, n.a, frame);
        if (operand != .value) return operand;
        const info = self.valueInfo(operand.value);
        if (n.b == 0) {
            if (info.kind != .scalar) return self.failNode(owner, id, .type_mismatch);
            return .{ .value = try self.makeScalar(owner, id, .{ .scalar = info.scalar, .bits = info.bits }) };
        }
        if ((n.b == 1 and info.kind != .array) or (n.b == 2 and info.kind != .list) or n.b > 2) return self.failNode(owner, id, .type_mismatch);
        return .{ .value = try self.makeScalar(owner, id, .{ .scalar = .u32, .bits = info.len }) };
    }
    fn bindingExpression(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const n = self.units[owner].node(id);
        const outcome = try self.expression(owner, n.b, frame);
        const value_ = switch (outcome) {
            .value => |value__| value__,
            .returning, .breaking => return outcome,
        };
        const binding = module.binding(n.a);
        if (module.types.node(binding.ty).tag != .function and self.hasExplicitScheme(owner, binding.scheme)) {
            const actual = self.valueEvidence(value_);
            if (actual != 0 and !try self.matchType(owner, id, owner, binding.ty, actual, &frame.mappings, &frame.row_mappings)) return self.failNode(owner, id, .type_mismatch);
            try self.validateScheme(owner, id, binding.scheme, frame, false);
        }
        try frame.values.put(self.allocator, n.a, value_);
        return .{ .value = 0 };
    }
    fn typeConstructorExpression(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const n = self.units[owner].node(id);
        const actual = try self.projectType(owner, id, n.ty, frame.mappings.items, frame.row_mappings.items);
        if (actual == 0) return self.failNode(owner, id, .type_constructor_required);
        const token = self.storage.evidence.node(actual);
        if (token.tag != .type_constructor) return self.failNode(owner, id, .type_constructor_required);
        return .{ .value = try self.makeAggregate(owner, id, .type_constructor, (@as(u64, token.a) << 32) | token.b, 0, &.{}) };
    }
    fn providerExpression(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const n = self.units[owner].node(id);
        const operation = try self.expression(owner, n.a, frame);
        if (operation != .value) return operation;
        const implementation = try self.expression(owner, n.b, frame);
        if (implementation != .value) return implementation;
        const token = try self.operationToken(owner, id, operation.value);
        if (self.valueInfo(implementation.value).kind != .closure) return self.failNode(owner, id, .invalid_provider);
        const signature = self.valueEvidence(operation.value);
        if (signature == 0 or self.storage.evidence.node(signature).tag != .function) return self.failNode(owner, id, .invalid_provider);
        return .{ .value = try self.makeAggregate(owner, id, .provider, signature, token, &.{implementation.value}) };
    }
    fn constructExpression(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const n = self.units[owner].node(id);
        const constructor = module.constructor(n.a);
        const nominal = module.nominal(constructor.nominal);
        const family = self.nominalIdentity(owner, nominal.identity.unit, nominal.identity.decl);
        if (n.b == 0) return .{ .value = try self.makeAggregate(owner, id, .nominal, family, constructor.tag, &.{}) };
        const payload = try self.expression(owner, n.b, frame);
        if (payload != .value) return payload;
        const stored = if (n.c != 0) try self.recordArgument(owner, owner, id, n.a, payload.value) else payload.value;
        return .{ .value = try self.makeAggregate(owner, id, .nominal, family, constructor.tag, &.{stored}) };
    }
    fn patternBindingExpression(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const n = self.units[owner].node(id);
        const operand = try self.expression(owner, n.b, frame);
        if (operand != .value) return operand;
        var bound: std.ArrayList(Bound) = .empty;
        defer bound.deinit(self.allocator);
        if (try self.matchPattern(owner, n.a, operand.value, frame, &bound, 0)) {
            try self.installBindings(frame, bound.items);
            return .{ .value = 0 };
        }
        if (n.c == 0) return self.failNode(owner, id, .unsupported);
        return self.expression(owner, n.c, frame);
    }
    fn expressionInner(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        if (self.principal_reads) |reads| reads.invalidate(.evaluate);
        if (id == 0) return .{ .value = 0 };
        const module = &self.units[owner];
        if (id >= module.nodes.len) return self.fail(owner, .{ .start = 0, .end = 0 }, .unsupported);
        if (self.steps >= self.options.max_steps or self.depth >= self.options.max_depth) return self.failNode(owner, id, .constant_fuel);
        self.steps += 1;
        self.depth += 1;
        if (self.constant_recorder) |recorder| recorder.observe(self);
        defer self.depth -= 1;
        const n = module.node(id);
        if (self.indexed_region) |region| if (region.owner == owner and region.frame == frame) {
            for (region.plan.edits[0..region.plan.edit_count]) |edit| if (edit.update == id) return self.indexedEdit(region, edit);
        };
        switch (n.tag) {
            .task => return self.failNode(owner, id, .const_effect),
            .staging => return self.stagingExpression(owner, id, frame),
            .constant => return .{ .value = try self.literal(owner, id, frame) },
            .contract_method => return self.contractMethod(owner, id, frame),
            .reference => return self.referenceExpression(owner, id, frame),
            .product, .record, .array => {
                const outcome = try self.aggregate(owner, id, frame);
                if (self.ragged_region) |region| if (region.owner == owner and region.frame == frame and region.plan.storage.initial == id and outcome == .value) {
                    region.original = outcome.value;
                };
                return outcome;
            },
            .record_merge => return self.recordMerge(owner, id, frame),
            .array_op => return self.arrayOperation(owner, id, frame),
            .closure => return self.closureExpression(owner, id, frame),
            .suspend_ => return self.suspensionExpression(owner, id, frame),
            .force => {
                const operand = try self.expression(owner, n.a, frame);
                if (operand != .value) return operand;
                return self.forceValue(owner, id, operand.value, frame.providers);
            },
            .type_constructor => return self.typeConstructorExpression(owner, id, frame),
            .computation => {
                const action = try self.expression(owner, n.a, frame);
                if (action != .value) return action;
                if (self.valueInfo(action.value).kind != .closure) return self.failNode(owner, id, .unsupported);
                return .{ .value = try self.makeAggregate(owner, id, .computation, 0, 0, &.{action.value}) };
            },
            .request_decision => {
                const payload = try self.expression(owner, n.b, frame);
                if (payload != .value) return payload;
                const state = try self.expression(owner, n.c, frame);
                if (state != .value) return state;
                return .{ .value = try self.makeAggregate(owner, id, .request_decision, 0, n.a, &.{ payload.value, state.value }) };
            },
            .request_loop => return self.requestLoop(owner, id, frame),
            .resolver_op => return self.resolverOperation(owner, id, frame),
            .constructor_function => return .{ .value = try self.makeClosure(owner, id, .{ .origin = .constructor, .unit = self.unitId(owner), .identity = n.a }, &.{}) },
            .primitive_function => return .{ .value = try self.makeClosure(owner, id, .{ .origin = .primitive, .unit = self.unitId(owner), .identity = n.a, .ty = n.ty }, &.{}) },
            .effect_reflection => return self.reflectionExpression(owner, id, frame),
            .effect_scope => return self.effectScope(owner, id, frame),
            .operation_value => return self.operationExpression(owner, id, frame),
            .effect_provider => return self.providerExpression(owner, id, frame),
            .state_provider => return self.stateProviderExpression(owner, id, frame),
            .handle => return self.handle(owner, id, frame),
            .panic => {
                if (self.diagnostic == null) self.diagnostic = .{ .unit = self.unitId(owner), .span = module.span(id), .code = .const_panic, .detail = module.panicMessage(id) };
                return error.Declined;
            },
            .apply => return self.applicationExpression(owner, id, frame),
            .associated => return self.dispatch(owner, id, frame),
            .result_associated => return self.resultDispatch(owner, id, frame),
            .type_same => return self.sameTypeExpression(owner, id, frame),
            .construct => return self.constructExpression(owner, id, frame),
            .project => {
                const operand = try self.expression(owner, n.a, frame);
                if (operand != .value) return operand;
                return self.memberValue(owner, id, n.b, operand.value, frame);
            },
            .match => return self.match(owner, id, frame),
            .pattern_bind => return self.patternBindingExpression(owner, id, frame),
            .update => return self.update(owner, id, frame),
            .scalar => return self.scalarExpression(owner, id, frame),
            .logical => return self.logicalExpression(owner, id, frame),
            .call => return self.call(owner, id, frame),
            .if_value, .if_stmt => return self.branchExpression(owner, id, frame),
            .block, .suite => {
                if (n.tag == .block and self.ragged_region == null and self.indexed_region == null and self.ragged_probe_limit != 0) {
                    if (try self.raggedBlock(owner, id, frame)) |outcome| return outcome;
                }
                return self.blockChildren(owner, id, frame);
            },
            .resource_acquire, .resource_release, .resource_scope => return self.failNode(owner, id, .unsupported),
            .usage_borrow => return self.usageBorrow(owner, id, frame),
            .usage_share => {
                self.declineConstant();
                const operand = try self.expression(owner, n.a, frame);
                if (operand != .value) return operand;
                const actual = try self.projectType(owner, id, n.ty, frame.mappings.items, frame.row_mappings.items);
                return .{ .value = try self.typedView(owner, id, operand.value, actual) };
            },
            .usage_read => return self.usageReadExpression(owner, id, frame),
            .package_pack => return self.packagePack(owner, id, frame),
            .package_unpack => return self.packageUnpack(owner, id, frame),
            .bind => return self.bindingExpression(owner, id, frame),
            .return_ => {
                const outcome = try self.expression(owner, n.a, frame);
                return switch (outcome) {
                    .value => |value_| .{ .returning = .{ .target = n.b, .value = value_ } },
                    .returning, .breaking => outcome,
                };
            },
            .loop => return self.loop(owner, id, frame),
            .break_ => return self.breakFlow(owner, id, frame),
            .proof_guard => return self.proofGuard(owner, id, frame),
            .invalid => return self.failNode(owner, id, .unsupported),
        }
    }
    fn usageBorrow(self: *Session, owner: usize, source: core.Id, caller: *Frame) Error!Flow {
        // Private loan views never become semantic receipts or public evidence.
        // Immutable Core independently proves that their result paths cannot
        // escape, before code generation or constant execution reaches here.
        if (self.recordingConstant()) self.declineConstant();
        const module = &self.units[owner];
        const node = module.node(source);
        const input = try self.expression(owner, node.a, caller);
        if (input != .value) return input;
        const callback = module.closure(node.b);
        var callee: Frame = .{ .providers = caller.providers, .staged = caller.staged };
        defer callee.deinit(self.allocator);
        try callee.mappings.appendSlice(self.allocator, caller.mappings.items);
        try callee.row_mappings.appendSlice(self.allocator, caller.row_mappings.items);
        for (module.extra[callback.captures.start..][0..callback.captures.len]) |binding| {
            const captured = caller.values.get(binding) orelse try self.richValue(.{ .unit = self.unitId(owner), .binding = binding });
            try callee.values.put(self.allocator, binding, captured);
        }
        if (self.constantValueCount() >= self.options.max_values or self.storage.values.items.len >= std.math.maxInt(ValueId)) return self.failNode(owner, source, .constant_fuel);
        const view: ValueId = @intCast(self.storage.values.items.len);
        const info = self.valueInfo(input.value);
        const record = self.storage.value_records.items[input.value];
        try self.storage.values.ensureUnusedCapacity(self.allocator, 1);
        try self.storage.value_evidence.ensureUnusedCapacity(self.allocator, 1);
        try self.storage.value_records.ensureUnusedCapacity(self.allocator, 1);
        self.storage.values.appendAssumeCapacity(info);
        self.storage.value_evidence.appendAssumeCapacity(0);
        self.storage.value_records.appendAssumeCapacity(record);
        try callee.values.put(self.allocator, callback.parameter.binding, view);
        if (self.call_depth >= self.options.max_call_depth) return self.failNode(owner, source, .constant_recursion);
        self.call_depth += 1;
        defer self.call_depth -= 1;
        return self.expression(owner, callback.body, &callee);
    }
    fn nominalIdentity(self: *const Session, owner: usize, unit: u32, declaration: u32) u64 {
        return (@as(u64, if (unit == 0) self.unitId(owner) else unit) << 32) | declaration;
    }
    fn proofGuard(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const node = self.units[owner].node(id);
        const proof_terms = @import("../check/numeric_proof_terms.zig");
        if (node.c > @backingInt(proof_terms.Relation.index)) return self.failNode(owner, id, .unsupported);
        const relation: proof_terms.Relation = @fromBackingInt(@as(u8, @intCast(node.c)));
        const first = try self.expression(owner, node.a, frame);
        if (first != .value) return first;
        const second = try self.expression(owner, node.b, frame);
        if (second != .value) return second;
        var left: u32 = undefined;
        if (relation == .index) {
            const collection = self.valueInfo(first.value);
            if (collection.kind != .array and collection.kind != .list) return self.failNode(owner, id, .type_mismatch);
            left = collection.len;
        } else {
            const operand = try self.requireScalar(owner, id, first.value);
            if (operand.scalar != .u32) return self.failNode(owner, id, .type_mismatch);
            left = operand.bits;
        }
        const right = try self.requireScalar(owner, id, second.value);
        if (right.scalar != .u32) return self.failNode(owner, id, .type_mismatch);
        if (!proof_terms.holds(relation, left, right.bits)) {
            if (relation == .index) return self.failNode(owner, id, .array_bounds);
            return self.failNode(owner, id, .invalid_numeric_proof);
        }
        const proof_type = self.storage.evidence.intern(.erased_proof, 0, 0, &.{}) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return self.failNode(owner, id, .unresolved_type);
        };
        const witness = try self.makeAggregate(owner, id, .proof, 0, 0, &.{});
        self.storage.value_evidence.items[witness] = proof_type;
        return .{ .value = witness };
    }
    fn packagePack(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const node = module.node(id);
        const package = module.types.node(node.ty);
        if (package.tag != .existential or package.c != node.c) return self.failNode(owner, id, .type_mismatch);
        const payload = try self.expression(owner, node.a, frame);
        if (payload != .value) return payload;
        const witnesses = try self.allocator.alloc(type_evidence.Id, node.c);
        defer self.allocator.free(witnesses);
        for (module.types.list(.{ .start = node.b, .len = node.c }), witnesses) |ty, *witness| {
            witness.* = try self.projectType(owner, id, ty, frame.mappings.items, frame.row_mappings.items);
            if (witness.* == 0) return self.failNode(owner, id, .unsupported);
        }
        const dictionary = self.storage.evidence.intern(.product, 0, 0, witnesses) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return self.failNode(owner, id, .constant_fuel),
        };
        const recipe = self.storage.evidence.projectWithRows(&module.types, node.ty, frame.mappings.items, frame.row_mappings.items) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => 0,
        };
        const stored_members = for (module.dictionary_selections) |selection| {
            if (selection.owner == id) break true;
        } else false;
        if (!stored_members) return .{ .value = try self.makeAggregate(owner, id, .package, dictionary, recipe, &.{payload.value}) };
        var members: std.ArrayList(ValueId) = .empty;
        defer members.deinit(self.allocator);
        try members.append(self.allocator, payload.value);
        for (module.dictionary_selections) |selection| {
            if (selection.owner != id) continue;
            for (module.extra[selection.members.start..][0..selection.members.len]) |member| {
                if (member == 0) continue;
                const outcome = try self.expression(owner, member, frame);
                if (outcome != .value) return outcome;
                try members.append(self.allocator, outcome.value);
            }
        }
        return .{ .value = try self.makeAggregate(owner, id, .package, dictionary, recipe, members.items) };
    }
    fn packageUnpack(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const node = module.node(id);
        const package_value = try self.expression(owner, node.a, frame);
        if (package_value != .value) return package_value;
        const info = self.valueInfo(package_value.value);
        const package = module.types.node(module.typeOf(node.a));
        if (info.kind != .package or info.len == 0 or info.nominal >= self.storage.evidence.nodes.items.len or package.tag != .existential) return self.failNode(owner, id, .type_mismatch);
        const dictionary: type_evidence.Id = @intCast(info.nominal);
        if (self.storage.evidence.node(dictionary).tag != .product) return self.failNode(owner, id, .type_mismatch);
        const witnesses = self.storage.evidence.children(dictionary);
        if (witnesses.len != package.c) return self.failNode(owner, id, .type_mismatch);
        const opening = module.packageOpening(id);
        if (opening.binders.len != witnesses.len) return self.failNode(owner, id, .type_mismatch);
        const frontier = frame.mappings.items.len;
        defer frame.mappings.shrinkRetainingCapacity(frontier);
        for (module.types.list(opening.binders), witnesses, 0..) |binder, witness, ordinal| {
            const leaf = module.types.node(binder);
            if (leaf.tag != .bound or leaf.a != ordinal or leaf.b != 0 or leaf.c != node.b) return self.failNode(owner, id, .type_mismatch);
            try frame.mappings.append(self.allocator, .{ .variable = binder, .evidence = witness });
        }
        const payload = self.valueChildren(package_value.value)[0];
        const previous = frame.values.get(node.b);
        try frame.values.put(self.allocator, node.b, payload);
        defer {
            if (previous) |old_value| frame.values.getPtr(node.b).?.* = old_value else _ = frame.values.remove(node.b);
        }
        var bound: std.ArrayList(Bound) = .empty;
        defer bound.deinit(self.allocator);
        for (module.dictionary_uses) |use| {
            if (use.opening != node.b) continue;
            const offset = module.dictionaryOffset(use.quantifier, use.goal, use.member) catch return self.failNode(owner, id, .type_mismatch);
            const children = self.valueChildren(package_value.value);
            if (offset >= children.len) return self.failNode(owner, id, .type_mismatch);
            try bound.append(self.allocator, .{ .binding = use.binding, .value = children[offset] });
        }
        try self.installBindings(frame, bound.items);
        defer self.restoreBindings(frame, bound.items);
        return self.expression(owner, opening.body, frame);
    }
    fn liftableValue(self: *Session, owner: usize, source: core.Id, value_: ValueId, depth: usize, remaining: *usize) Error!bool {
        if (depth >= 128 or remaining.* == 0) return self.failNode(owner, source, .staging_budget);
        remaining.* -= 1;
        switch (self.valueInfo(value_).kind) {
            .scalar => return true,
            .product, .record, .nominal, .array, .list => {
                for (self.valueChildren(value_)) |child| if (!try self.liftableValue(owner, source, child, depth + 1, remaining)) return false;
                return true;
            },
            else => return false,
        }
    }
    fn quote(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!ValueId {
        const module = &self.units[owner];
        const root = module.node(id).a;
        const Visit = struct { node: core.Id, stage: u8 };
        const Pending = struct {
            items: std.ArrayList(Visit) = .empty,
            stage: u8 = 1,
            pub fn append(work: *@This(), allocator: Allocator, node: core.Id) Allocator.Error!void {
                try work.items.append(allocator, .{ .node = node, .stage = work.stage });
            }
            pub fn appendSlice(work: *@This(), allocator: Allocator, nodes: []const core.Id) Allocator.Error!void {
                try work.items.ensureUnusedCapacity(allocator, nodes.len);
                for (nodes) |node| work.items.appendAssumeCapacity(.{ .node = node, .stage = work.stage });
            }
            fn deinit(work: *@This(), allocator: Allocator) void {
                work.items.deinit(allocator);
            }
        };
        var pending: Pending = .{};
        defer pending.deinit(self.allocator);
        var replacements: std.ArrayList(ValueId) = .empty;
        defer replacements.deinit(self.allocator);
        var seen: [4096]core.Id = undefined;
        var count: usize = 0;
        try pending.append(self.allocator, root);
        while (pending.items.pop()) |visit| {
            const next = visit.node;
            pending.stage = visit.stage;
            if (next == 0) continue;
            if (std.mem.findScalar(core.Id, seen[0..count], next) != null) continue;
            if (count == seen.len or self.steps >= self.options.max_steps) return self.failNode(owner, id, .staging_budget);
            seen[count] = next;
            count += 1;
            self.steps += 1;
            const node = module.node(next);
            if (node.tag == .staging) {
                const op: @import("../check/typed_staging.zig").Op = @fromBackingInt(node.c);
                if (op == .quote) {
                    if (visit.stage == 128) return self.failNode(owner, next, .staging_budget);
                    pending.stage += 1;
                    try pending.append(self.allocator, node.a);
                    continue;
                }
                if (op == .lift or op == .splice) {
                    if (visit.stage > 1) {
                        pending.stage -= 1;
                        try pending.append(self.allocator, node.a);
                        continue;
                    }
                    const outcome = try self.expression(owner, node.a, frame);
                    if (outcome != .value) return self.failNode(owner, next, .stage_unavailable);
                    if (op == .splice) {
                        if (self.valueInfo(outcome.value).kind != .code) return self.failNode(owner, next, .code_shape_mismatch);
                    } else {
                        var remaining: usize = 4096;
                        if (!try self.liftableValue(owner, next, outcome.value, 0, &remaining)) return self.failNode(owner, next, .cross_stage_authority);
                    }
                    try replacements.append(self.allocator, try self.makeAggregate(owner, next, .staged_value, next, node.c, &.{outcome.value}));
                    continue;
                }
            }
            if (node.tag == .closure or node.tag == .suspend_) {
                try pending.append(self.allocator, module.closures[node.a].body);
            } else if (node.tag == .operation_value) {
                try pending.append(self.allocator, module.operation_values[node.a].witness);
            } else @import("body_recipe.zig").appendChildren(&pending, self.allocator, module, next, false) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                return self.failNode(owner, next, .staging_budget);
            };
        }
        if (self.storage.closures.items.len >= std.math.maxInt(u32)) return self.failNode(owner, id, .staging_budget);
        var rows: std.ArrayList(type_evidence.RowMapping) = .empty;
        defer rows.deinit(self.allocator);
        try rows.appendSlice(self.allocator, frame.row_mappings.items);
        // The returned lambda owns its principal closing decision. Keep that
        // exact owner's certificate with the code graph, so later descriptor
        // observation and portable projection see the same closed interface.
        // A caller's selected contextual row still takes precedence.
        if (module.node(root).tag == .closure) {
            for (module.types.list(module.closure(root).closed_rows)) |variable| {
                const present = for (rows.items) |mapping| {
                    if (mapping.variable == variable) break true;
                } else false;
                if (!present) try rows.append(self.allocator, .{ .variable = variable, .evidence = 0 });
            }
        }
        const metadata: ClosureValue = .{ .unit = self.unitId(owner), .identity = root, .origin = .anonymous, .ty = module.typeOf(id), .mappings = try self.captureMappings(owner, id, frame.mappings.items), .row_mappings = try self.captureRowMappings(owner, id, rows.items) };
        const index: u32 = @intCast(self.storage.closures.items.len);
        try self.storage.closures.ensureUnusedCapacity(self.allocator, 1);
        try self.storage.demands.ensureUnusedCapacity(self.allocator, 1);
        if (self.generator_origin != null) try self.storage.code_origins.ensureUnusedCapacity(self.allocator, 1);
        const value_ = try self.makeAggregate(owner, id, .code, root, index, replacements.items);
        self.storage.closures.appendAssumeCapacity(metadata);
        self.storage.demands.appendAssumeCapacity(.{});
        if (self.generator_origin) |origin| self.storage.code_origins.appendAssumeCapacity(.{ .value = value_, .generator = origin });
        return value_;
    }
    fn executeCode(self: *Session, owner: usize, id: core.Id, value_: ValueId, frame: *Frame) Error!Flow {
        const metadata = self.stagedInfo(value_) orelse return self.failNode(owner, id, .code_shape_mismatch);
        var producer: ?usize = null;
        for (self.units, 0..) |_, index| if (self.unitId(index) == metadata.unit) {
            producer = index;
            break;
        };
        const selected = producer orelse return self.failNode(owner, id, .stage_unavailable);
        const previous_trace = self.staging_trace;
        defer self.staging_trace = previous_trace;
        const op: @import("../check/typed_staging.zig").Op = @fromBackingInt(self.units[owner].node(id).c);
        @import("../check/staging_origins.zig").code(&self.staging_trace, self.units, metadata, .{ .unit = self.unitId(owner), .node = id }, @import("../check/staging_origins.zig").generator(self.storage.code_origins.items, value_), op == .splice) catch |err| {
            var issue: Code = .staging_budget;
            if (err == error.InvalidOrigin) issue = .code_shape_mismatch;
            return self.failNode(owner, id, issue);
        };
        var future: Frame = .{ .staged = value_, .providers = frame.providers };
        defer future.deinit(self.allocator);
        try future.mappings.appendSlice(self.allocator, self.storage.type_mappings.items[metadata.mappings.start..][0..metadata.mappings.len]);
        try future.row_mappings.appendSlice(self.allocator, self.storage.row_mappings.items[metadata.row_mappings.start..][0..metadata.row_mappings.len]);
        const outcome = try self.expression(selected, metadata.identity, &future);
        if (outcome != .value) return self.failNode(selected, metadata.identity, .stage_unavailable);
        return outcome;
    }
    fn stagingExpression(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        self.declineConstant();
        const module = &self.units[owner];
        const node = module.node(id);
        const op: @import("../check/typed_staging.zig").Op = @fromBackingInt(node.c);
        if (op == .quote) return .{ .value = try self.quote(owner, id, frame) };
        if (op == .lift or op == .splice) {
            const code_value = frame.staged orelse return self.failNode(owner, id, .stage_unavailable);
            const value_ = self.stagedReplacement(code_value, id) orelse return self.failNode(owner, id, .stage_unavailable);
            if (op == .splice) return self.executeCode(owner, id, value_, frame);
            return .{ .value = value_ };
        }
        const outcome = try self.expression(owner, node.a, frame);
        if (outcome != .value) return outcome;
        const value_ = outcome.value;
        if (op == .emit or op == .run) return self.executeCode(owner, id, value_, frame);
        const info = self.valueInfo(value_);
        if (op == .same) {
            const right = try self.expression(owner, node.b, frame);
            if (right != .value) return right;
            const other = self.valueInfo(right.value);
            if (info.kind != .descriptor or other.kind != .descriptor) return self.failNode(owner, id, .code_shape_mismatch);
            return .{ .value = try self.makeScalar(owner, id, .{ .scalar = .bool, .bits = @intFromBool(info.nominal == other.nominal) }) };
        }
        var values: std.ArrayList(ValueId) = .empty;
        defer values.deinit(self.allocator);
        if (op == .fields) {
            if (info.kind != .descriptor or info.nominal >= self.storage.evidence.nodes.items.len) return self.failNode(owner, id, .code_shape_mismatch);
            const input = try self.projectType(owner, id, module.typeOf(node.a), frame.mappings.items, frame.row_mappings.items);
            const arguments = self.storage.evidence.children(input);
            if (arguments.len != 1 or arguments[0] != info.nominal) return self.failNode(owner, id, .code_shape_mismatch);
            const output = try self.projectType(owner, id, node.ty, frame.mappings.items, frame.row_mappings.items);
            if (self.storage.evidence.node(output).tag != .record) return self.failNode(owner, id, .code_shape_mismatch);
            // Checked Core reconstructs every published field from the exact
            // public constructor catalog. Evaluation instantiates that recipe.
            const fields = try self.allocator.dupe(u32, self.storage.evidence.children(output));
            defer self.allocator.free(fields);
            for (0..fields.len / 2) |index| {
                const described = self.storage.evidence.children(fields[index * 2 + 1]);
                if (described.len != 1) return self.failNode(owner, id, .code_shape_mismatch);
                try values.append(self.allocator, try self.makeAggregate(owner, id, .descriptor, described[0], 0, &.{}));
            }
        } else {
            if (info.kind != .code) return self.failNode(owner, id, .code_shape_mismatch);
            const code_type = self.valueEvidence(value_);
            const arguments = self.storage.evidence.children(code_type);
            if (arguments.len != 2) return self.failNode(owner, id, .code_shape_mismatch);
            const result_type = arguments[0];
            const row = self.storage.evidence.node(arguments[1]).c;
            const result_descriptor = try self.makeAggregate(owner, id, .descriptor, result_type, 0, &.{});
            const effects = try self.makeAggregate(owner, id, .effect_set, 0, row, &.{});
            const result_shape = module.types.node(node.ty);
            for (0..result_shape.b) |index| {
                const name = module.fieldSpelling(module.types.recordField(result_shape, index).name) orelse return self.failNode(owner, id, .code_shape_mismatch);
                if (std.mem.eql(u8, name, "result")) try values.append(self.allocator, result_descriptor) else try values.append(self.allocator, effects);
            }
        }
        const result = try self.makeAggregate(owner, id, .record, 0, 0, values.items);
        self.storage.value_records.items[result] = try self.recordLayout(owner, id, node.ty);
        return .{ .value = result };
    }
    fn aggregate(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const n = module.node(id);
        const operands = module.children(id);
        const values = try self.allocator.alloc(ValueId, operands.len);
        defer self.allocator.free(values);
        const destinations = if (n.tag == .record) module.recordDestinations(id) else &.{};
        // Execute written order; only the completed handles are permuted into
        // canonical declaration order for projection and pattern matching.
        for (operands, 0..) |operand, index| {
            const outcome = try self.expression(owner, operand, frame);
            if (outcome != .value) return outcome;
            const destination = if (n.tag == .record) destinations[index] else index;
            if (destination >= values.len) return self.failNode(owner, id, .unsupported);
            values[destination] = outcome.value;
        }
        var aggregate_type = n.ty;
        if (module.types.node(aggregate_type).tag == .usage) aggregate_type = module.types.node(aggregate_type).a;
        const kind: ValueKind = if (n.tag == .record) .record else if (n.tag == .array) (if (module.types.node(aggregate_type).tag == .list) .list else .array) else .product;
        const record_layout = if (kind == .record) try self.recordLayout(owner, id, aggregate_type) else 0;
        const result = try self.makeAggregate(owner, id, kind, 0, 0, values);
        self.storage.value_records.items[result] = record_layout;
        return .{ .value = result };
    }
    fn recordMerge(self: *Session, owner: usize, source: core.Id, frame: *Frame) Error!Flow {
        const node = self.units[owner].node(source);
        const left = try self.expression(owner, node.a, frame);
        if (left != .value) return left;
        const right = try self.expression(owner, node.b, frame);
        if (right != .value) return right;
        if (self.valueInfo(left.value).kind != .record or self.valueInfo(right.value).kind != .record) return self.failNode(owner, source, .type_mismatch);
        if (self.valueInfo(left.value).len == 0) return right;
        if (self.valueInfo(right.value).len == 0) return left;
        var buffer: [1024]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&buffer, self.allocator);
        const allocator = scratch.allocator();
        var names: std.ArrayList(u32) = .empty;
        defer names.deinit(allocator);
        var children: std.ArrayList(ValueId) = .empty;
        defer children.deinit(allocator);
        var slots: std.AutoHashMapUnmanaged(u32, usize) = .empty;
        defer slots.deinit(allocator);
        for ([_]ValueId{ left.value, right.value }) |input| {
            for (self.recordFieldNames(input), self.valueChildren(input)) |name, child| {
                const entry = try slots.getOrPut(allocator, name);
                if (entry.found_existing) children.items[entry.value_ptr.*] = child else {
                    entry.value_ptr.* = children.items.len;
                    try names.append(allocator, name);
                    try children.append(allocator, child);
                }
            }
        }
        const shape = try self.internRecordLayout(owner, source, names.items);
        const value_ = try self.makeAggregate(owner, source, .record, 0, 0, children.items);
        self.storage.value_records.items[value_] = shape;
        // These are the surviving values' existing closed facts, including
        // independently closed callback rows. Never infer a principal scheme
        // from a caller's expected result or copy a discarded field's type.
        const word_count = std.math.mul(usize, names.items.len, 2) catch return self.failNode(owner, source, .constant_fuel);
        const words = try allocator.alloc(u32, word_count);
        defer allocator.free(words);
        const closed = for (names.items, children.items, 0..) |name, child, index| {
            words[index * 2] = name;
            words[index * 2 + 1] = self.valueEvidence(child);
            if (words[index * 2 + 1] == 0) break false;
        } else true;
        if (closed) self.storage.value_evidence.items[value_] = self.storage.evidence.intern(.record, 0, 0, words) catch |err| return self.evidenceFailure(owner, self.units[owner].span(source), err);
        return .{ .value = value_ };
    }
    fn internRecordLayout(self: *Session, owner: usize, source: core.Id, names: []const u32) Error!u32 {
        if (names.len == 0) return 0;
        if (self.storage.record_shapes.getAdapted(names, RecordNames.Adapter{ .words = self.storage.field_names.items })) |existing| return existing;
        if (names.len > std.math.maxInt(u32) - self.storage.field_names.items.len or self.storage.record_layouts.items.len >= std.math.maxInt(u32)) return self.failNode(owner, source, .constant_fuel);
        try self.storage.record_layouts.ensureUnusedCapacity(self.allocator, 1);
        try self.storage.field_names.ensureUnusedCapacity(self.allocator, names.len);
        try self.storage.record_shapes.ensureUnusedCapacityContext(self.allocator, 1, .{ .words = self.storage.field_names.items });
        const shape: u32 = @intCast(self.storage.record_layouts.items.len);
        const span: core.List = .{ .start = @intCast(self.storage.field_names.items.len), .len = @intCast(names.len) };
        self.storage.field_names.appendSliceAssumeCapacity(names);
        self.storage.record_layouts.appendAssumeCapacity(span);
        self.storage.record_shapes.putAssumeCapacityContext(span, shape, .{ .words = self.storage.field_names.items });
        return shape;
    }
    fn recordLayout(self: *Session, owner: usize, source: core.Id, ty: types.Id) Error!u32 {
        const key: RecordKey = .{ .unit = owner, .ty = ty };
        if (self.storage.record_types.get(key)) |existing| return existing;
        const module = &self.units[owner];
        const record = module.types.node(ty);
        if (record.tag != .record) return self.failNode(owner, source, .unsupported);
        var buffer: [256]u8 align(@alignOf(u32)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&buffer, self.allocator);
        const names = try scratch.allocator().alloc(u32, record.b);
        defer scratch.allocator().free(names);
        for (names, 0..) |*name, index| name.* = module.types.recordField(record, index).name;
        const shape = try self.internRecordLayout(owner, source, names);
        try self.storage.record_types.put(self.allocator, key, shape);
        return shape;
    }
    fn filledArray(self: *Session, owner: usize, source: core.Id, count: u32, value_: ValueId, kind: ValueKind) Error!ValueId {
        if (count >= 4_194_304) return self.arrayLengthFailure(owner);
        try self.chargeCells(owner, source, count);
        if (self.constantValueCount() >= self.options.max_values or self.storage.values.items.len >= std.math.maxInt(ValueId) or count > self.options.max_children -| self.constantChildCount() or count > std.math.maxInt(u32) - self.storage.children.items.len) return self.failNode(owner, source, .constant_fuel);
        try self.storage.values.ensureUnusedCapacity(self.allocator, 1);
        try self.storage.value_evidence.ensureUnusedCapacity(self.allocator, 1);
        try self.storage.value_records.ensureUnusedCapacity(self.allocator, 1);
        try self.storage.children.ensureUnusedCapacity(self.allocator, count);
        const id: ValueId = @intCast(self.storage.values.items.len);
        const start: u32 = @intCast(self.storage.children.items.len);
        self.storage.children.items.len += count;
        @memset(self.storage.children.items[start..], value_);
        self.storage.values.appendAssumeCapacity(.{ .kind = kind, .start = start, .len = count });
        self.storage.value_evidence.appendAssumeCapacity(0);
        self.storage.value_records.appendAssumeCapacity(0);
        return id;
    }
    fn arrayOperation(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const operation = module.arrayOperation(id);
        const arguments = module.children(id);
        const arity = @import("../backend/collection_ops.zig").arity(operation);
        if (arguments.len != arity) return self.failNode(owner, id, .unsupported);
        var values: [3]ValueId = undefined;
        for (arguments, 0..) |argument, index| {
            const outcome = try self.expression(owner, argument, frame);
            if (outcome != .value) return outcome;
            values[index] = outcome.value;
        }
        if (self.ragged_region) |region| if (region.owner == owner and region.frame == frame) {
            if (id == region.plan.storage.append) {
                std.debug.assert(region.written < region.children.len);
                region.children[region.written] = values[1];
                region.written += 1;
                return .{ .value = region.original };
            }
            if (id == region.plan.storage.conversion) {
                std.debug.assert(region.written == region.children.len);
                self.ragged_reserved_children -= region.children.len;
                region.reserved = false;
                const published = try self.makeAggregate(owner, id, .array, 0, 0, region.children);
                region.published = published;
                return .{ .value = published };
            }
        };
        return .{ .value = try self.arrayValues(owner, id, operation, values[0..arity], frame.providers) };
    }
    fn extendCollection(self: *Session, owner: usize, source: core.Id, original: ValueId, value_: ValueId, front: bool) Error!ValueId {
        const before = self.valueInfo(original);
        if (self.constant_recorder) |recorder| if (!recorder.canGrow(self, .{ .start = before.start, .len = before.len })) self.declineConstant();
        if (before.len >= 4_194_303) return self.arrayLengthFailure(owner);
        if (self.constantValueCount() >= self.options.max_values or self.storage.values.items.len >= std.math.maxInt(ValueId)) return self.failNode(owner, source, .constant_fuel);
        try self.storage.values.ensureUnusedCapacity(self.allocator, 1);
        try self.storage.value_evidence.ensureUnusedCapacity(self.allocator, 1);
        try self.storage.value_records.ensureUnusedCapacity(self.allocator, 1);
        const span = self.storage.collection_buffers.extend(self.allocator, &self.storage.children, .{ .start = before.start, .len = before.len }, value_, front, self.options.max_children -| self.constant_child_debt) catch |err| switch (err) {
            error.Limit => return self.failNode(owner, source, .constant_fuel),
            error.OutOfMemory => return error.OutOfMemory,
        };
        if (self.constant_recorder) |recorder| recorder.grew(self);
        const id: ValueId = @intCast(self.storage.values.items.len);
        self.storage.values.appendAssumeCapacity(.{ .kind = before.kind, .start = span.start, .len = span.len });
        self.storage.value_evidence.appendAssumeCapacity(0);
        self.storage.value_records.appendAssumeCapacity(0);
        return id;
    }
    fn arrayValues(self: *Session, owner: usize, id: core.Id, operation: core.ArrayOp, values: []const ValueId, head: provider_chain.Head) Error!ValueId {
        const kind: ValueKind = if (self.units[owner].types.node(self.units[owner].typeOf(id)).tag == .list) .list else .array;
        if (operation == .cursor_has or operation == .cursor_value or operation == .cursor_advance) {
            const cursor = self.valueInfo(values[0]);
            if (cursor.kind != .cursor or cursor.len != 1) return self.failNode(owner, id, .unsupported);
            const source = self.valueChildren(values[0])[0];
            const count = self.valueInfo(source).len;
            if (operation == .cursor_has) return self.makeScalar(owner, id, .{ .scalar = .bool, .bits = @intFromBool(cursor.bits < count) });
            if (cursor.bits >= count) return self.failNode(owner, id, .array_bounds);
            if (operation == .cursor_value) return self.valueChildren(source)[cursor.bits];
            return self.makeAggregate(owner, id, .cursor, 0, cursor.bits + 1, &.{source});
        }
        if (operation == .generate) {
            const count = try self.requireScalar(owner, id, values[0]);
            if (count.scalar != .u32 or self.valueInfo(values[1]).kind != .closure) return self.failNode(owner, id, .unsupported);
            if (count.bits >= 4_194_304) return self.arrayLengthFailure(owner);
            if (count.bits > self.options.max_children -| self.constantChildCount()) return self.failNode(owner, id, .constant_fuel);
            try self.chargeCells(owner, id, count.bits);
            const children_ = try self.allocator.alloc(ValueId, count.bits);
            defer self.allocator.free(children_);
            for (children_, 0..) |*child, index| {
                const argument = try self.makeScalar(owner, id, .{ .scalar = .u32, .bits = @intCast(index) });
                const outcome = try self.applyValue(owner, id, values[1], argument, head);
                if (outcome != .value) return self.failNode(owner, id, .unsupported);
                child.* = outcome.value;
            }
            return self.makeAggregate(owner, id, kind, 0, 0, children_);
        }
        if (operation == .fill) {
            const count = try self.requireScalar(owner, id, values[0]);
            if (count.scalar != .u32) return self.failNode(owner, id, .unsupported);
            return self.filledArray(owner, id, count.bits, values[1], kind);
        }
        const array = self.valueInfo(values[0]);
        if (array.kind != .array and array.kind != .list) return self.failNode(owner, id, .unsupported);
        if (operation == .flatten) {
            var length: u32 = 0;
            for (self.valueChildren(values[0])) |child| {
                const chunk = self.valueInfo(child);
                if (chunk.kind != .array) return self.failNode(owner, id, .unsupported);
                if (chunk.len >= 4_194_304 -| length) return self.arrayLengthFailure(owner);
                length += chunk.len;
            }
            try self.chargeCells(owner, id, length);
            const copied = try self.allocator.alloc(ValueId, length);
            defer self.allocator.free(copied);
            var offset: usize = 0;
            for (self.valueChildren(values[0])) |child| {
                const chunk = self.valueChildren(child);
                @memcpy(copied[offset..][0..chunk.len], chunk);
                offset += chunk.len;
            }
            return self.makeAggregate(owner, id, .array, 0, 0, copied);
        }
        if (operation == .cursor) return self.makeAggregate(owner, id, .cursor, 0, 0, &.{values[0]});
        if (operation == .slice) {
            const start = try self.requireScalar(owner, id, values[1]);
            const count = try self.requireScalar(owner, id, values[2]);
            if (start.scalar != .u32 or count.scalar != .u32) return self.failNode(owner, id, .unsupported);
            if (start.bits > array.len or count.bits > array.len - start.bits) return self.failNode(owner, id, .array_bounds);
            const copied = try self.allocator.dupe(ValueId, self.valueChildren(values[0])[start.bits..][0..count.bits]);
            defer self.allocator.free(copied);
            return self.makeAggregate(owner, id, array.kind, 0, 0, copied);
        }
        if (operation == .concat) {
            const other = self.valueInfo(values[1]);
            if (other.kind != array.kind) return self.failNode(owner, id, .unsupported);
            if (other.len >= 4_194_304 -| array.len) return self.arrayLengthFailure(owner);
            const length = std.math.add(u32, array.len, other.len) catch return self.arrayLengthFailure(owner);
            try self.chargeCells(owner, id, length);
            const copied = try self.allocator.alloc(ValueId, length);
            defer self.allocator.free(copied);
            @memcpy(copied[0..array.len], self.valueChildren(values[0]));
            @memcpy(copied[array.len..], self.valueChildren(values[1]));
            return self.makeAggregate(owner, id, array.kind, 0, 0, copied);
        }
        if (operation == .length) return self.makeScalar(owner, id, .{ .scalar = .u32, .bits = array.len });
        if (operation == .identity) return values[0];
        if (operation == .convert) {
            const copied = try self.allocator.dupe(ValueId, self.valueChildren(values[0]));
            defer self.allocator.free(copied);
            return self.makeAggregate(owner, id, if (array.kind == .list) .array else .list, 0, 0, copied);
        }
        if (operation == .append or operation == .prepend) {
            return self.extendCollection(owner, id, values[0], values[1], operation == .prepend);
        }
        const index = try self.requireScalar(owner, id, values[1]);
        if (index.scalar != .u32) return self.failNode(owner, id, .unsupported);
        if (operation == .simd_load or operation == .simd_store) {
            if (array.len < 4 or index.bits > array.len - 4) return self.failNode(owner, id, .array_bounds);
            if (operation == .simd_load) {
                // Copy the handles first: allocation can move child storage.
                const loaded: [4]ValueId = self.valueChildren(values[0])[index.bits..][0..4].*;
                return self.makeAggregate(owner, id, .product, 0, 0, &loaded);
            }
            const lanes = self.valueInfo(values[2]);
            if (lanes.kind != .product or lanes.len != 4) return self.failNode(owner, id, .unsupported);
            try self.chargeCells(owner, id, array.len);
            const copied = try self.allocator.dupe(ValueId, self.valueChildren(values[0]));
            defer self.allocator.free(copied);
            @memcpy(copied[index.bits..][0..4], self.valueChildren(values[2]));
            return self.makeAggregate(owner, id, array.kind, 0, 0, copied);
        }
        if (index.bits >= array.len) return self.failNode(owner, id, .array_bounds);
        if (operation == .get) return self.valueChildren(values[0])[index.bits];
        try self.chargeCells(owner, id, array.len);
        return self.copyAggregate(owner, id, values[0], index.bits, values[2]);
    }
    fn simdLanes(self: *Session, owner: usize, id: core.Id, vector: ValueId) Error![4]Value {
        if (vector == 0 or self.valueInfo(vector).kind != .product or self.valueInfo(vector).len != 4) return self.failNode(owner, id, .unsupported);
        var lanes: [4]Value = undefined;
        for (&lanes, self.valueChildren(vector)[0..4]) |*lane, child| lane.* = try self.requireScalar(owner, id, child);
        return lanes;
    }
    fn simdPair(self: *Session, owner: usize, id: core.Id, pair: ValueId) Error![2][4]Value {
        if (pair == 0 or self.valueInfo(pair).kind != .product or self.valueInfo(pair).len != 2) return self.failNode(owner, id, .unsupported);
        const children = self.valueChildren(pair);
        return .{ try self.simdLanes(owner, id, children[0]), try self.simdLanes(owner, id, children[1]) };
    }
    /// Each lane follows its scalar kernel exactly. Min/max use the prelude's
    /// ordered selection; relaxed multiply-add is evaluated fused here.
    fn simdValue(self: *Session, owner: usize, id: core.Id, op: core.Op, left: ValueId, right: ValueId) Error!ValueId {
        const simd = @import("../backend/simd_intrinsics.zig");
        const a = try self.simdLanes(owner, id, left);
        var lanes: [4]Value = undefined;
        switch (op) {
            .any_true, .all_true => {
                var count: u32 = 0;
                for (a) |lane| count += @intFromBool(lane.bits != 0);
                const truth = if (op == .any_true) count != 0 else count == 4;
                return self.makeScalar(owner, id, .{ .scalar = .bool, .bits = @intFromBool(truth) });
            },
            .bit_not, .bits, .from_bits => for (&lanes, a) |*lane, item| {
                lane.* = .{ .scalar = if (op == .from_bits) .f32 else .u32, .bits = if (op == .bit_not) ~item.bits else item.bits };
            },
            .shift_left, .shift_right, .shift_right_signed, .broadcast => {
                const count = try self.requireScalar(owner, id, right);
                if (count.scalar != .u32) return self.failNode(owner, id, .unsupported);
                if (op == .broadcast and count.bits >= simd.laneLimit(op)) return self.failNode(owner, id, .simd_lane_literal);
                for (&lanes, a) |*lane, item| {
                    const shift: u5 = @truncate(count.bits);
                    lane.* = .{ .scalar = item.scalar, .bits = switch (op) {
                        .shift_left => item.bits << shift,
                        .shift_right => item.bits >> shift,
                        .shift_right_signed => @bitCast(@as(i32, @bitCast(item.bits)) >> shift),
                        else => a[count.bits].bits,
                    } };
                }
            },
            .convert_i32_f32, .convert_f32_i32 => {
                for (&lanes, a) |*lane, item| {
                    if (op == .convert_i32_f32) {
                        lane.* = .{ .scalar = .f32, .bits = @bitCast(@as(f32, @floatFromInt(@as(i32, @bitCast(item.bits))))) };
                    } else {
                        const value_: f32 = @bitCast(item.bits);
                        const signed: i32 = if (std.math.isNan(value_)) 0 else if (value_ <= -2147483648.0) std.math.minInt(i32) else if (value_ >= 2147483648.0) std.math.maxInt(i32) else @intFromFloat(value_);
                        lane.* = .{ .scalar = .u32, .bits = @bitCast(signed) };
                    }
                }
            },
            .select, .relaxed_madd, .relaxed_nmadd, .shuffle => {
                const pair = try self.simdPair(owner, id, right);
                for (&lanes, a, 0..) |*lane, item, index| lane.* = switch (op) {
                    .select => .{ .scalar = pair[0][index].scalar, .bits = (pair[0][index].bits & item.bits) | (pair[1][index].bits & ~item.bits) },
                    .relaxed_madd => .{ .scalar = .f32, .bits = @bitCast(@mulAdd(f32, @bitCast(item.bits), @bitCast(pair[0][index].bits), @bitCast(pair[1][index].bits))) },
                    .relaxed_nmadd => .{ .scalar = .f32, .bits = @bitCast(@mulAdd(f32, -@as(f32, @bitCast(item.bits)), @bitCast(pair[0][index].bits), @bitCast(pair[1][index].bits))) },
                    else => blk: {
                        if (item.bits >= simd.laneLimit(op)) return self.failNode(owner, id, .simd_lane_literal);
                        break :blk pair[item.bits / 4][item.bits % 4];
                    },
                };
            },
            .swizzle => {
                const vector = try self.simdLanes(owner, id, right);
                for (&lanes, a) |*lane, item| {
                    if (item.bits >= simd.laneLimit(op)) return self.failNode(owner, id, .simd_lane_literal);
                    lane.* = vector[item.bits];
                }
            },
            else => {
                const b = if (right == 0) a else try self.simdLanes(owner, id, right);
                for (&lanes, a, b) |*lane, first, second| {
                    lane.* = switch (op) {
                        .min, .max => blk: {
                            // min chooses the left lane when left < right and
                            // max when right < left, otherwise the right lane.
                            const ordered = scalar_ops.evaluate(.less, if (op == .min) first else second, if (op == .min) second else first) catch return self.failNode(owner, id, .unsupported);
                            break :blk if (ordered.bits != 0) first else second;
                        },
                        .bit_andnot => .{ .scalar = first.scalar, .bits = first.bits & ~second.bits },
                        else => scalar_ops.evaluate(op, first, if (right == 0) .{ .scalar = .unit, .bits = 0 } else second) catch return self.failNode(owner, id, .unsupported),
                    };
                    // Lane comparisons produce all-ones or all-zero U32 masks.
                    if (lane.scalar == .bool) lane.* = .{ .scalar = .u32, .bits = if (lane.bits != 0) std.math.maxInt(u32) else 0 };
                }
            },
        }
        var values: [4]ValueId = undefined;
        for (&values, lanes) |*result, lane| result.* = try self.makeScalar(owner, id, lane);
        return self.makeAggregate(owner, id, .product, 0, 0, &values);
    }
    fn arrayLengthFailure(self: *Session, owner: usize) Error {
        if (self.diagnostic == null) self.diagnostic = .{ .unit = self.unitId(owner), .span = .{ .start = 0, .end = 0 }, .code = .backend_limit, .detail = "array length exceeds the 16 MiB bootstrap arena" };
        return error.Declined;
    }
    const Location = struct { container: ValueId, field: u32, wrapped: bool };
    fn genericField(self: *Session, owner: usize, source: core.Id, name: u32, value_: ValueId) Error!Location {
        const info = self.valueInfo(value_);
        if (info.kind == .record) {
            const names = self.recordFieldNames(value_);
            if (names.len != info.len) return self.failNode(owner, source, .unsupported);
            for (names, 0..) |field, index| if (field == name) return .{ .container = value_, .field = @intCast(index), .wrapped = false };
            return self.failNode(owner, source, .unsupported);
        }
        if (info.kind != .nominal or info.len != 1 or name == 0) return self.failNode(owner, source, .unsupported);
        if (@as(u32, @truncate(info.nominal)) & types.opaque_name_bit != 0 and info.nominal >> 32 != self.unitId(owner)) return self.failNode(owner, source, .missing_field);
        const location = self.field_locations.get(.{ .family = info.nominal, .tag = info.bits, .name = name }) orelse return self.failNode(owner, source, .unsupported);
        const container = self.valueChildren(value_)[0];
        const record = self.valueInfo(container);
        if (record.kind != .record or record.len != location.len) return self.failNode(owner, source, .unsupported);
        return .{ .container = container, .field = location.field, .wrapped = true };
    }
    fn projectionLocation(self: *Session, owner: usize, source: core.Id, projection_index: u32, value_: ValueId) Error!Location {
        const module = &self.units[owner];
        const projection = module.projection(projection_index);
        const variants = module.projectionVariants(projection_index);
        if (projection.nominal.decl == 0 and variants.len == 0) return self.genericField(owner, source, projection.field, value_);
        const info = self.valueInfo(value_);
        if (info.kind == .record and projection.field != 0) return self.genericField(owner, source, projection.field, value_);
        var field: ?u32 = null;
        var container = value_;
        var wrapped = false;
        if (info.kind == .nominal) {
            if (@as(u32, @truncate(info.nominal)) & types.opaque_name_bit != 0 and info.nominal >> 32 != self.unitId(owner)) return self.failNode(owner, source, .missing_field);
            if (info.nominal != self.nominalIdentity(owner, projection.nominal.unit, projection.nominal.decl) or info.len != 1) return self.failNode(owner, source, .unsupported);
            for (variants) |variant| if (variant.tag == info.bits) {
                field = variant.field;
                break;
            };
            container = self.valueChildren(value_)[0];
            wrapped = true;
        } else {
            if (projection.nominal.decl != 0 or variants.len != 1) return self.failNode(owner, source, .unsupported);
            field = variants[0].field;
        }
        const selected = field orelse return self.failNode(owner, source, .unsupported);
        const payload = self.valueInfo(container);
        if ((payload.kind != .product and payload.kind != .record) or selected >= payload.len) return self.failNode(owner, source, .unsupported);
        return .{ .container = container, .field = selected, .wrapped = wrapped };
    }
    fn projectValue(self: *Session, owner: usize, source: core.Id, projection_index: u32, value_: ValueId) Error!ValueId {
        const location = try self.projectionLocation(owner, source, projection_index, value_);
        return self.valueChildren(location.container)[location.field];
    }
    fn memberValue(self: *Session, owner: usize, source: core.Id, projection_index: u32, receiver: ValueId, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const projection = module.projection(projection_index);
        if (module.projectionVariants(projection_index).len != 0) return .{ .value = try self.projectValue(owner, source, projection_index, receiver) };
        const previous = self.diagnostic;
        const field: ?Location = self.genericField(owner, source, projection.field, receiver) catch |err| switch (err) {
            error.Declined => blk: {
                self.diagnostic = previous;
                break :blk null;
            },
            else => return err,
        };
        const selected_field: ?ValueId = if (field) |location| self.valueChildren(location.container)[location.field] else null;
        const actual = self.valueEvidence(receiver);
        // Empty collections can leave element evidence open inside a cursor
        // or a user-defined wrapper too. Their outer identity is still known;
        // solve only this use without completing the shared generic element.
        const info = self.valueInfo(receiver);
        const identity = self.evidenceIdentity(actual) orelse if (actual == 0) switch (info.kind) {
            .array => types.NominalIdentity{ .unit = 0, .decl = std.math.maxInt(u32) },
            .list => types.NominalIdentity{ .unit = 0, .decl = std.math.maxInt(u32) - 1 },
            .cursor => types.NominalIdentity{ .unit = 0, .decl = std.math.maxInt(u32) - 2 },
            .nominal => types.NominalIdentity{ .unit = @intCast(info.nominal >> 32), .decl = @truncate(info.nominal) },
            else => null,
        } else null;
        var method_target: ?Target = null;
        if (identity) |receiver_identity| if (try self.associatedTarget(self.unitId(owner), receiver_identity, projection.field, .none)) |method| {
            method_target = try self.target(null, method);
        };
        if (selected_field) |value_| {
            if (method_target != null) return self.failNode(owner, source, .ambiguous_member);
            return .{ .value = value_ };
        }
        const target_ = method_target orelse return self.failNode(owner, source, .missing_member);
        const producer = &self.units[target_.unit];
        const body = producer.body(target_.binding) orelse return self.failNode(owner, source, .unsupported);
        const arrow = producer.types.node(body.scheme.root);
        if (arrow.tag != .function) return self.failNode(owner, source, .type_mismatch);
        const expected = try self.projectType(owner, source, module.typeOf(source), frame.mappings.items, frame.row_mappings.items);
        if (actual == 0) {
            if (try self.shapeOnlyArrayMember(owner, source, target_, receiver, expected)) |function|
                return self.applyValue(owner, source, function, receiver, frame.providers);
            const function = try self.partialArrayMember(owner, source, target_, receiver, expected);
            return self.applyValue(owner, source, function, receiver, frame.providers);
        }
        var mappings: std.ArrayList(type_evidence.Mapping) = .empty;
        var row_mappings: std.ArrayList(type_evidence.RowMapping) = .empty;
        defer row_mappings.deinit(self.allocator);
        defer mappings.deinit(self.allocator);
        if (!try self.matchType(owner, source, target_.unit, arrow.a, actual, &mappings, &row_mappings)) return self.failNode(owner, source, .type_mismatch);
        if (expected != 0 and !try self.matchCovariantType(owner, source, target_.unit, arrow.b, expected, &mappings, &row_mappings)) return self.failNode(owner, source, .type_mismatch);
        const full = try self.projectType(target_.unit, body.root, body.scheme.root, mappings.items, row_mappings.items);
        const function = try self.richValue(.{ .unit = self.unitId(target_.unit), .binding = target_.binding });
        const typed = if (full == 0)
            try self.partialNamedView(owner, source, function, mappings.items, row_mappings.items)
        else
            try self.typedView(owner, source, function, full);
        return self.applyValue(owner, source, typed, receiver, frame.providers);
    }
    /// An exact generic length body observes the container, not any element
    /// interface or captured callable. Keep its ordinary invocation and fuel.
    fn shapeOnlyArrayMember(self: *Session, owner: usize, source: core.Id, target_: Target, receiver: ValueId, expected: type_evidence.Id) Error!?ValueId {
        const ordinary = Options{};
        if (self.options.max_steps != ordinary.max_steps or self.options.max_values != ordinary.max_values or self.options.max_children != ordinary.max_children or self.options.max_depth != ordinary.max_depth or self.options.max_call_depth != ordinary.max_call_depth or self.options.max_type_depth != ordinary.max_type_depth or self.options.max_summary_transitions != ordinary.max_summary_transitions) return null;
        if (expected != 0 and self.storage.evidence.node(expected).tag != .u32) return null;
        const module = &self.units[target_.unit];
        const body = module.body(target_.binding) orelse return null;
        if (body.runtime or !body.is_function or body.parameters.len != 1 or body.scheme.variables.len != 1 or body.scheme.row_variables.len != 0 or body.scheme.obligations.len != 0) return null;
        const arrow = module.types.node(body.scheme.root);
        if (arrow.tag != .function or arrow.b != types.u32_type or arrow.c != 0) return null;
        const parameter = module.types.node(arrow.a);
        const kind = self.valueInfo(receiver).kind;
        if (parameter.tag != .array or kind != .array) {
            if (parameter.tag != .list or kind != .list) return null;
        }
        if (module.types.node(parameter.a).tag != .variable or module.types.list(body.scheme.variables)[0] != parameter.a) return null;
        const root = module.node(body.root);
        if (root.tag != .array_op or root.c != @backingInt(core.ArrayOp.length) or root.b != 1 or root.ty != types.u32_type) return null;
        const operand = module.extra[root.a];
        if (module.node(operand).tag != .reference) return null;
        const reference = module.reference(operand);
        const input = module.bodyParameters(body)[0];
        if (reference.unit != 0 or reference.binding != input.binding or module.typeOf(operand) != input.ty) return null;
        const body_parameter = module.types.node(input.ty);
        if (body_parameter.tag != parameter.tag or module.types.node(body_parameter.a).tag != .variable) return null;
        const function = try self.richValue(.{ .unit = self.unitId(target_.unit), .binding = target_.binding });
        const header = self.closureInfo(function);
        if (header.origin != .named or header.applied != 0 or header.mappings.len != 0 or header.row_mappings.len != 0 or self.valueInfo(function).len != 0) return null;
        return try self.makeClosure(owner, source, header, &.{});
    }
    fn partialNamedView(self: *Session, owner: usize, source: core.Id, function: ValueId, mappings: []const type_evidence.Mapping, rows: []const type_evidence.RowMapping) Error!ValueId {
        if (mappings.len == 0 and rows.len == 0) return function;
        var metadata = self.closureInfo(function);
        // richValue publishes a fresh named principal with no private seeds.
        // Preserve that immutable header; this use owns its selected facts.
        std.debug.assert(metadata.origin == .named and metadata.applied == 0 and metadata.mappings.len == 0 and metadata.row_mappings.len == 0);
        metadata.mappings = try self.captureMappings(owner, source, mappings);
        metadata.row_mappings = try self.captureRowMappings(owner, source, rows);
        const captures = try self.allocator.dupe(ValueId, self.valueChildren(function));
        defer self.allocator.free(captures);
        return self.makeClosure(owner, source, metadata, captures);
    }
    /// A preceding ordinary use must already own the immutable syntax recipe.
    /// Small source methods cannot repay a separate graph receipt.
    pub fn memberReceiptEligible(self: *const Session, reference: core.BindingRef) bool {
        if (reference.unit == 0 or reference.unit > self.units.len) return false;
        const owner = reference.unit - 1;
        if (reference.binding >= self.units[owner].bindings.len) return false;
        const body = self.units[owner].body(reference.binding) orelse return false;
        const recipe = self.specializations.body_recipes.recipes.get(.{ .owner = owner, .body = body.root, .callables = true }) orelse return false;
        return recipe.visits.items.len >= 64;
    }
    /// Complete evidence is optional for an aggregate with unresolved empty
    /// children. Import its actual structure and the selected method signature
    /// into a private region; export only concrete substitutions. The generic
    /// source scheme and every existing value header remain immutable.
    pub fn memberPrincipalsMatch(self: *Session, member: *const receipt.Member) bool {
        if (member.principal_graphs != self.reuse_principal_graphs) return false;
        for (member.principals) |read| {
            if (read.target.unit == 0 or read.target.unit > self.units.len) return false;
            const key: PrincipalGraph.Key = .{ .target = .{ .unit = read.target.unit - 1, .binding = read.target.binding }, .source_interface = read.source_interface, .deferred_member = read.deferred_member, .options = self.options };
            var outcome: receipt.PrincipalOutcome = .missing;
            if (read.open) {
                if (self.specializations.call_summaries.normalized_principals.get(key, self) != null) outcome = .graph;
            } else if (self.specializations.call_summaries.principals.get(key, self)) |graph| {
                outcome = .graph;
                if (graph == null) outcome = .declined;
            }
            if (outcome != read.outcome) return false;
        }
        return true;
    }
    fn partialArrayMember(self: *Session, owner: usize, source: core.Id, target_: Target, receiver: ValueId, expected: type_evidence.Id) Error!ValueId {
        const outer = self.constant_recorder orelse return self.partialArrayMemberInner(owner, source, target_, receiver, expected);
        try outer.beforeRead(self.allocator, self);
        self.constant_recorder = null;
        defer self.constant_recorder = outer;
        errdefer outer.eligible = false;
        const selected = try self.partialArrayMemberInner(owner, source, target_, receiver, expected);
        try outer.query(self.allocator, self, .{ .kind = .array_member, .target = .{ .unit = self.unitId(target_.unit), .binding = target_.binding }, .input = receiver, .expected = expected, .selected = selected });
        return selected;
    }
    fn partialArrayMemberInner(self: *Session, owner: usize, source: core.Id, target_: Target, receiver: ValueId, expected: type_evidence.Id) Error!ValueId {
        if (self.receipt_tape) |tape| tape.nested = true;
        const member_target: core.BindingRef = .{ .unit = self.unitId(target_.unit), .binding = target_.binding };
        if (self.receipt_tape == null and self.inquiry_regions == 0 and self.memberReceiptEligible(member_target)) if (self.specialization_provider) |provider| if (provider.member) |lookup| if (try lookup(provider.context, self, member_target, receiver, expected)) |selected| {
            self.observeConstantInference();
            return selected;
        };
        const method_slot = self.slots[self.binding_offsets[target_.unit] + target_.binding];
        const recording = self.retain_specialization_receipts and self.receipt_tape == null and self.inquiry_regions == 0 and self.semantic_job_budget == null and method_slot.state == .complete and self.memberReceiptEligible(member_target);
        const query_budgets = @import("../reuse/constant_receipt.zig").queryBudgets(self);
        const summary_work = self.summary_graph_work;
        const principal_nodes = self.principal_graph_nodes;
        const principal_edges = self.principal_graph_edges;
        const values_before = self.storage.values.items.len;
        const children_before = self.storage.children.items.len;
        const steps_before = self.steps;
        var tape: receipt.Tape = .{};
        defer tape.deinit(self.allocator);
        const previous_tape = self.receipt_tape;
        if (recording) self.receipt_tape = &tape;
        defer self.receipt_tape = previous_tape;
        var member_trace: receipt.MemberTrace = .{};
        const previous_trace = self.member_trace;
        if (recording) self.member_trace = &member_trace;
        defer self.member_trace = previous_trace;
        var region = ClosureRegion.initAt(self, @src()) catch return error.OutOfMemory;
        defer region.deinit();
        const selected = region.arrayMember(target_, receiver, expected) catch |err| return self.evidenceFailure(owner, self.units[owner].span(source), err);
        if (recording) {
            var record = try tape.finish(self.allocator, .{
                .input = receiver,
                .expected = expected,
                .selected = selected,
                .options = self.options,
                .depth = self.depth,
                .values_before = values_before,
                .children_before = children_before,
                .values_added = self.storage.values.items.len - values_before,
                .children_added = self.storage.children.items.len - children_before,
                .steps = self.steps - steps_before,
                .collected = tape.collected,
                .source_scopes = region.scratch.sources.items.len,
                .solver_nodes = region.solver.nodes.items.len,
                .complete = region.allConstraintsSolved() and self.steps == steps_before and !region.source_interface and !region.retain_selected and !region.complete_demand_bodies and self.summary_graph_work == summary_work and self.principal_graph_nodes == principal_nodes and self.principal_graph_edges == principal_edges and std.meta.eql(query_budgets, @import("../reuse/constant_receipt.zig").queryBudgets(self)),
                .sources = &.{},
                .scalar_reads = &.{},
                .call_reads = &.{},
                .call_publications = &.{},
                .views = &.{},
                .plain_facts = &.{},
            });
            var owns_record = true;
            defer if (owns_record) record.deinit(self.allocator);
            if (record.complete and member_trace.complete and !self.summary_exhausted and self.summary_transitions <= self.summaryLimit()) {
                try self.retained.specialization_receipts.ensureUnusedCapacity(self.allocator, 1);
                const member = try self.allocator.create(receipt.Member);
                errdefer self.allocator.destroy(member);
                const principal_reads = try self.allocator.dupe(receipt.PrincipalRead, member_trace.entries[0..member_trace.len]);
                errdefer self.allocator.free(principal_reads);
                const ready_reads = try self.allocator.dupe(receipt.ReadyRead, member_trace.ready[0..member_trace.ready_len]);
                member.* = .{ .ready = ready_reads, .principals = principal_reads, .principal_graphs = self.reuse_principal_graphs, .target = member_target, .function = method_slot.value, .query_budgets = query_budgets, .summary_work = summary_work, .principal_nodes = principal_nodes, .principal_edges = principal_edges, .transitions = self.summary_transitions, .exhausted = self.summary_exhausted };
                record.member = member;
                self.retained.specialization_receipts.appendAssumeCapacity(record);
                owns_record = false;
            }
        }
        return selected;
    }
    fn replaceProjection(self: *Session, owner: usize, source: core.Id, projection_index: u32, value_: ValueId, replacement: ValueId) Error!ValueId {
        const location = try self.projectionLocation(owner, source, projection_index, value_);
        const changed = try self.copyAggregate(owner, source, location.container, location.field, replacement);
        if (!location.wrapped) return changed;
        const wrapper = self.valueInfo(value_);
        return self.makeAggregate(owner, source, .nominal, wrapper.nominal, wrapper.bits, &.{changed});
    }
    fn update(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const metadata = module.updateInfo(id);
        const original = try self.expression(owner, metadata.root, frame);
        if (original != .value) return original;
        const path = module.updatePath(id);
        const selectors = module.updateSelectors(id);
        const count = if (selectors.len != 0) selectors.len else path.len;
        const chain = try self.allocator.alloc(ValueId, count + 1);
        defer self.allocator.free(chain);
        const indices = try self.allocator.alloc(u32, selectors.len);
        defer self.allocator.free(indices);
        chain[0] = original.value;
        if (selectors.len != 0) {
            for (selectors, 0..) |selector, index| {
                if (selector.kind == .field) {
                    chain[index + 1] = try self.projectValue(owner, id, selector.projection, chain[index]);
                } else {
                    const position = try self.expression(owner, selector.index, frame);
                    if (position != .value) return position;
                    const scalar_ = try self.requireScalar(owner, selector.index, position.value);
                    const array_ = self.valueInfo(chain[index]);
                    if (scalar_.scalar != .u32 or (array_.kind != .array and array_.kind != .list)) return self.failNode(owner, id, .unsupported);
                    if (scalar_.bits >= array_.len) return self.failNode(owner, id, .array_bounds);
                    indices[index] = scalar_.bits;
                    chain[index + 1] = self.valueChildren(chain[index])[scalar_.bits];
                }
            }
        } else for (path, 0..) |projection, index| chain[index + 1] = try self.projectValue(owner, id, projection, chain[index]);
        // installBindings writes previous through this mutable slice.
        // zig-analyzer: disable-next-line never-mutated-var
        var bound = [_]Bound{.{ .binding = metadata.self_binding, .value = chain[count] }};
        const self_binding = if (metadata.self_binding == 0) bound[0..0] else bound[0..1];
        try self.installBindings(frame, self_binding);
        defer self.restoreBindings(frame, self_binding);
        const outcome = try self.expression(owner, metadata.value, frame);
        if (outcome != .value) return outcome;
        var changed = outcome.value;
        var index = count;
        while (index != 0) {
            index -= 1;
            if (selectors.len != 0) {
                const selector = selectors[index];
                changed = if (selector.kind == .field)
                    try self.replaceProjection(owner, id, selector.projection, chain[index], changed)
                else
                    try self.copyAggregate(owner, id, chain[index], indices[index], changed);
            } else changed = try self.replaceProjection(owner, id, path[index], chain[index], changed);
        }
        return .{ .value = changed };
    }
    fn installBindings(self: *Session, frame: *Frame, bound: []Bound) Allocator.Error!void {
        var installed: usize = 0;
        errdefer self.restoreBindings(frame, bound[0..installed]);
        for (bound) |*entry| {
            entry.previous = frame.values.get(entry.binding);
            try frame.values.put(self.allocator, entry.binding, entry.value);
            installed += 1;
        }
    }
    fn restoreBindings(_: *Session, frame: *Frame, bound: []const Bound) void {
        var index = bound.len;
        while (index != 0) {
            index -= 1;
            const entry = bound[index];
            if (entry.previous) |previous| frame.values.getPtr(entry.binding).?.* = previous else _ = frame.values.remove(entry.binding);
        }
    }
    fn matchPattern(self: *Session, owner: usize, pattern_id: core.PatternId, value_: ValueId, frame: *Frame, bound: *std.ArrayList(Bound), nesting: usize) Error!bool {
        const module = &self.units[owner];
        const pattern = module.pattern(pattern_id);
        if (self.steps >= self.options.max_steps or nesting >= self.options.max_depth -| self.depth) return self.fail(owner, pattern.span, .constant_fuel);
        self.steps += 1;
        if (self.constant_recorder) |recorder| recorder.depth = @max(recorder.depth, (self.depth -| recorder.base_depth) +| nesting +| 1);
        switch (pattern.tag) {
            .wildcard => return true,
            .bind => {
                if (pattern.a != 0) try bound.append(self.allocator, .{ .binding = pattern.a, .value = value_ });
                return true;
            },
            .constant => {
                const actual = self.valueScalar(value_) orelse return false;
                const expected_scalar: @TypeOf(actual.scalar) = switch (module.types.node(pattern.ty).tag) {
                    .unit => .unit,
                    .u32 => .u32,
                    .boolean => .bool,
                    else => return self.fail(owner, pattern.span, .unsupported),
                };
                return actual.scalar == expected_scalar and actual.bits == pattern.a;
            },
            .value => {
                const expected = try self.expression(owner, pattern.a, frame);
                if (expected != .value) return self.fail(owner, pattern.span, .unsupported);
                const actual_scalar = self.valueScalar(value_) orelse return false;
                const expected_scalar = try self.requireScalar(owner, pattern.a, expected.value);
                if (actual_scalar.scalar != .u32 and actual_scalar.scalar != .bool) return self.fail(owner, pattern.span, .unsupported);
                return std.meta.eql(actual_scalar, expected_scalar);
            },
            .product => {
                const info = self.valueInfo(value_);
                const expected_kind: ValueKind = switch (module.types.node(pattern.ty).tag) {
                    .record => .record,
                    .product => .product,
                    else => return self.fail(owner, pattern.span, .unsupported),
                };
                const patterns = module.patternChildren(pattern_id);
                if (info.kind != expected_kind or info.len != patterns.len) return false;
                for (patterns, 0..) |child, index| {
                    var field_slot = index;
                    if (expected_kind == .record) {
                        const name = module.types.recordField(module.types.node(pattern.ty), index).name;
                        const names = self.recordFieldNames(value_);
                        field_slot = std.mem.findScalar(u32, names, name) orelse return false;
                    }
                    const child_value = self.valueChildren(value_)[field_slot];
                    if (!try self.matchPattern(owner, child, child_value, frame, bound, nesting + 1)) return false;
                }
                return true;
            },
            .record_payload => {
                const info = self.valueInfo(value_);
                if (info.kind != .record or info.len != pattern.a) return false;
                const canonical = try self.recordPayload(self.unitId(owner), pattern_id, value_);
                return self.matchPattern(owner, pattern.b, canonical, frame, bound, nesting + 1);
            },
            .constructor => {
                const constructor = module.constructor(pattern.a);
                const nominal = module.nominal(constructor.nominal);
                const info = self.valueInfo(value_);
                if (info.kind != .nominal or info.nominal != self.nominalIdentity(owner, nominal.identity.unit, nominal.identity.decl) or info.bits != constructor.tag) return false;
                if (pattern.b == 0) return info.len == 0;
                if (info.len != 1) return false;
                return self.matchPattern(owner, pattern.b, self.valueChildren(value_)[0], frame, bound, nesting + 1);
            },
            .invalid => return self.fail(owner, pattern.span, .unsupported),
        }
    }
    fn recordArgument(self: *Session, producer: usize, owner: usize, source: core.Id, catalog: u32, value_: ValueId) Error!ValueId {
        const module = &self.units[producer];
        const payload = module.constructor(catalog).payload;
        const record = module.types.node(payload);
        if (record.tag != .record or record.b == 0) return self.failNode(owner, source, .unsupported);
        var storage_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var storage: std.heap.BufferFirstAllocator = .init(&storage_buffer, self.allocator);
        const scratch = storage.allocator();
        const values = try scratch.alloc(ValueId, record.b);
        defer scratch.free(values);
        if (record.b == 1) values[0] = value_ else {
            const info = self.valueInfo(value_);
            if (info.kind != .product or info.len != record.b) return self.failNode(owner, source, .type_mismatch);
            @memcpy(values, self.valueChildren(value_));
        }
        const word_count = std.math.mul(usize, record.b, 2) catch return error.OutOfMemory;
        const words = try scratch.alloc(type_evidence.Id, word_count);
        defer scratch.free(words);
        var closed = true;
        for (values, 0..) |child_value, index| {
            words[index * 2] = module.types.recordField(record, index).name;
            words[index * 2 + 1] = self.valueEvidence(child_value);
            closed = closed and words[index * 2 + 1] != 0;
        }
        const actual = if (closed) self.storage.evidence.intern(.record, 0, 0, words) catch |err| return self.evidenceFailure(owner, self.units[owner].span(source), err) else 0;
        const layout = try self.recordLayout(producer, 0, payload);
        const result = try self.makeAggregate(owner, source, .record, 0, 0, values);
        self.storage.value_records.items[result] = layout;
        self.storage.value_evidence.items[result] = actual;
        return result;
    }
    fn canonicalRecordEvidence(self: *Session, owner: usize, source: core.Id, value_: ValueId) Error!type_evidence.Id {
        const children = self.valueChildren(value_);
        if (children.len == 1) return self.valueEvidence(children[0]);
        var storage_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var storage: std.heap.BufferFirstAllocator = .init(&storage_buffer, self.allocator);
        const scratch = storage.allocator();
        const fields = try scratch.alloc(type_evidence.Id, children.len);
        defer scratch.free(fields);
        for (children, fields) |child, *field| {
            field.* = self.valueEvidence(child);
            if (field.* == 0) return 0;
        }
        return self.storage.evidence.intern(.product, 0, 0, fields) catch |err| return self.evidenceFailure(owner, self.units[owner].span(source), err);
    }
    /// A constructor pattern owns this view of its retained record payload.
    /// Reuse field handles in declaration order without changing the record.
    pub fn recordPayload(self: *Session, unit: u32, pattern_id: core.PatternId, value_: ValueId) Error!ValueId {
        const owner = self.findUnit(unit, null) orelse return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        const pattern = self.units[owner].pattern(pattern_id);
        const record = self.units[owner].types.node(pattern.ty);
        const info = self.valueInfo(value_);
        const names = self.recordFieldNames(value_);
        if (pattern.tag != .record_payload or record.tag != .record or info.kind != .record or pattern.a == 0 or info.len != pattern.a or names.len != pattern.a) return self.fail(owner, pattern.span, .unsupported);
        for (names, 0..) |name, index| if (name != self.units[owner].types.recordField(record, index).name) return self.fail(owner, pattern.span, .type_mismatch);
        if (pattern.a == 1) return self.valueChildren(value_)[0];
        // makeAggregate may grow the child table; its borrowed input therefore
        // needs separate scratch ownership before publishing the product view.
        var storage_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var storage: std.heap.BufferFirstAllocator = .init(&storage_buffer, self.allocator);
        const scratch = storage.allocator();
        const children = try scratch.dupe(ValueId, self.valueChildren(value_));
        defer scratch.free(children);
        return self.makeAggregate(owner, 0, .product, 0, 0, children);
    }
    fn match(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const inputs = module.matchInputs(id);
        const values = try self.allocator.alloc(ValueId, inputs.len);
        defer self.allocator.free(values);
        for (inputs, 0..) |input, index| {
            const outcome = try self.expression(owner, input, frame);
            if (outcome != .value) return outcome;
            values[index] = outcome.value;
        }
        var bound: std.ArrayList(Bound) = .empty;
        defer bound.deinit(self.allocator);
        arms: for (module.matchArms(id), 0..) |arm, arm_index| {
            var matched = false;
            for (module.armRows(arm)) |row| {
                bound.clearRetainingCapacity();
                const patterns = module.rowPatterns(row);
                if (patterns.len != values.len) return self.fail(owner, arm.span, .unsupported);
                matched = true;
                for (patterns, values) |pattern, value_| if (!try self.matchPattern(owner, pattern, value_, frame, &bound, 0)) {
                    matched = false;
                    break;
                };
                if (matched) break;
            }
            if (!matched) continue;
            try self.installBindings(frame, bound.items);
            defer self.restoreBindings(frame, bound.items);
            if (arm.guard != 0) {
                const guard = try self.expression(owner, arm.guard, frame);
                if (guard != .value) return guard;
                const condition = try self.requireScalar(owner, arm.guard, guard.value);
                if (condition.scalar != .bool) return self.fail(owner, arm.span, .unsupported);
                if (condition.bits == 0) continue :arms;
            }
            const outcome = try self.expression(owner, arm.body, frame);
            if (!module.matchInfo(id).statement or outcome != .value) return outcome;
            for (module.branchMerges(id)) |merge| {
                const source = if (arm_index == 0) merge.then_binding else merge.else_binding;
                const merged = frame.values.get(source) orelse return self.failNode(owner, id, .unsupported);
                try frame.values.put(self.allocator, merge.result, merged);
            }
            return .{ .value = 0 };
        }
        return self.failNode(owner, id, .unsupported);
    }
    fn breakFlow(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const references = module.breakValues(id);
        var storage_buffer: [256]u8 align(@alignOf(usize)) = undefined;
        var storage: std.heap.BufferFirstAllocator = .init(&storage_buffer, self.allocator);
        const scratch = storage.allocator();
        const values = try scratch.alloc(ValueId, references.len);
        defer scratch.free(values);
        for (references, 0..) |reference, index| {
            const outcome = try self.expression(owner, reference, frame);
            if (outcome != .value) return outcome;
            values[index] = outcome.value;
        }
        if (values.len > self.options.max_children -| self.break_values.items.len or values.len > std.math.maxInt(u32) - self.break_values.items.len) return self.failNode(owner, id, .constant_fuel);
        const start: u32 = @intCast(self.break_values.items.len);
        try self.break_values.appendSlice(self.allocator, values);
        return .{ .breaking = .{ .target = module.node(id).a, .values = .{ .start = start, .len = @intCast(values.len) }, .continues = module.node(id).op == .continue_ } };
    }
    fn indexedEdit(self: *Session, region: *IndexedRegion, edit: @import("eval_indexed_builder.zig").Edit) Error!Flow {
        const owner = region.owner;
        const frame = region.frame;
        const selected = try self.expression(owner, edit.index, frame);
        if (selected != .value) return selected;
        const offset = try self.requireScalar(owner, edit.update, selected.value);
        if (offset.scalar != .u32) return self.failNode(owner, edit.update, .unsupported);
        if (edit.bounds_first and offset.bits >= region.children.len) return self.failNode(owner, edit.update, .array_bounds);
        if (edit.self_binding != 0) try frame.values.put(self.allocator, edit.self_binding, region.children[offset.bits]);
        const next = try self.expression(owner, edit.value, frame);
        if (next != .value) return next;
        if (offset.bits >= region.children.len) return self.failNode(owner, edit.update, .array_bounds);
        region.children[offset.bits] = next.value;
        // This opaque carry is never observed inside an admitted region. It
        // keeps ordinary loop/scalar evaluation intact without publishing a
        // mutable ValueInfo or child span to a closure, cache or snapshot.
        return .{ .value = region.original };
    }
    fn indexedLoop(self: *Session, owner: usize, id: core.Id, frame: *Frame, first: ValueId, begin: u32, end: u32, plan: @import("eval_indexed_builder.zig").Plan) Error!Flow {
        const original = frame.values.get(plan.incoming) orelse return self.failNode(owner, id, .unsupported);
        const info = self.valueInfo(original);
        if (info.kind != .array and info.kind != .list) return self.failNode(owner, id, .unsupported);
        try self.chargeCells(owner, id, info.len);
        const children = try self.allocator.dupe(ValueId, self.valueChildren(original));
        defer self.allocator.free(children);
        var region: IndexedRegion = .{ .owner = owner, .frame = frame, .original = original, .children = children, .plan = plan };
        const previous = self.indexed_region;
        self.declineConstant();
        self.indexed_region = &region;
        defer self.indexed_region = previous;
        const outcome = try self.loopIterations(owner, id, frame, first, begin, end);
        if (outcome != .value) return outcome;
        const result = if (begin >= end) original else try self.makeAggregate(owner, id, info.kind, info.nominal, info.bits, children);
        self.storage.value_evidence.items[result] = self.valueEvidence(original);
        try frame.values.put(self.allocator, plan.outgoing, result);
        return outcome;
    }
    fn loop(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const metadata = module.loopInfo(id);
        const first = try self.expression(owner, metadata.first, frame);
        if (first != .value) return first;
        const last = try self.expression(owner, metadata.end, frame);
        if (last != .value) return last;
        var index: u32 = 0;
        var end: u32 = 0;
        if (metadata.kind == .range) {
            const lower = try self.requireScalar(owner, id, first.value);
            const upper = try self.requireScalar(owner, id, last.value);
            if (lower.scalar != .u32 or upper.scalar != .u32) return self.failNode(owner, id, .unsupported);
            index = lower.bits;
            end = upper.bits;
        } else if (metadata.kind == .array) {
            const array = self.valueInfo(first.value);
            if (array.kind != .array and array.kind != .list) return self.failNode(owner, id, .unsupported);
            end = array.len;
        }
        if (self.indexed_region == null) if (@import("eval_indexed_builder.zig").analyze(module, id)) |plan| return self.indexedLoop(owner, id, frame, first.value, index, end, plan);
        return self.loopIterations(owner, id, frame, first.value, index, end);
    }
    fn loopIterations(self: *Session, owner: usize, id: core.Id, frame: *Frame, first: ValueId, begin: u32, end: u32) Error!Flow {
        const module = &self.units[owner];
        const metadata = module.loopInfo(id);
        const carries = module.loopCarries(id);
        var index = begin;
        var storage_buffer: [256]u8 align(@alignOf(usize)) = undefined;
        var storage: std.heap.BufferFirstAllocator = .init(&storage_buffer, self.allocator);
        const scratch = storage.allocator();
        const current = try scratch.alloc(ValueId, carries.len);
        defer scratch.free(current);
        for (carries, 0..) |carry, position| current[position] = frame.values.get(carry.incoming) orelse return self.failNode(owner, id, .unsupported);
        while (metadata.kind == .forever or index < end) {
            try self.chargeCells(owner, id, 1);
            for (carries, current) |carry, value_| try frame.values.put(self.allocator, carry.iteration, value_);
            if (metadata.pattern != 0) {
                const iterator = if (metadata.kind == .array) self.valueChildren(first)[index] else try self.makeScalar(owner, id, .{ .scalar = .u32, .bits = index });
                var bound: std.ArrayList(Bound) = .empty;
                defer bound.deinit(self.allocator);
                if (!try self.matchPattern(owner, metadata.pattern, iterator, frame, &bound, 0)) return self.failNode(owner, id, .unsupported);
                try self.installBindings(frame, bound.items);
            }
            const outcome = try self.expression(owner, metadata.body, frame);
            if (outcome == .returning) return outcome;
            if (outcome == .breaking) {
                if (outcome.breaking.target != id) return outcome;
                const span = outcome.breaking.values;
                if (span.len != carries.len) return self.failNode(owner, id, .unsupported);
                @memcpy(current, self.break_values.items[span.start..][0..span.len]);
                self.break_values.shrinkRetainingCapacity(span.start);
                if (!outcome.breaking.continues) break;
                if (metadata.kind != .forever) index += 1;
                continue;
            }
            // Read all successors before replacing any iteration slot.
            for (carries, 0..) |carry, position| current[position] = frame.values.get(carry.backedge) orelse return self.failNode(owner, id, .unsupported);
            if (metadata.kind != .forever) index += 1;
        }
        for (carries, current) |carry, value_| try frame.values.put(self.allocator, carry.outgoing, value_);
        return .{ .value = 0 };
    }
    const Selection = struct { target: ?Target = null, full_type: type_evidence.Id = 0, result: type_evidence.Id };
    fn operator(op: core.Op) types.Operator {
        return switch (op) {
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
            else => .none,
        };
    }
    fn evidenceIdentity(self: *const Session, actual: type_evidence.Id) ?types.NominalIdentity {
        if (actual == 0) return null;
        const n = self.storage.evidence.node(actual);
        return switch (n.tag) {
            .nominal => .{ .unit = n.a, .decl = n.b },
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
    /// Generic producer bodies retain the nominal declaration's method owner.
    /// Their own import catalog can precede the actual operand's producer.
    pub fn associatedTarget(self: *Session, origin: u32, identity: types.NominalIdentity, member: u32, op: types.Operator) Error!?core.BindingRef {
        const owner = self.findUnit(origin, null) orelse return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        const nominal_owner = if (identity.unit == 0) owner else self.findUnit(identity.unit, null) orelse return null;
        for ([_]usize{ owner, nominal_owner }, 0..) |catalog, index| {
            if (index != 0 and catalog == owner) continue;
            for (self.units[catalog].associated) |method| {
                if ((if (member != 0) method.member != member else method.operator != op) or !std.meta.eql(method.identity, identity)) continue;
                const target_ = try self.external(try self.target(catalog, method.target));
                if (target_.unit != owner and self.units[target_.unit].binding(target_.binding).private) continue;
                return .{ .unit = self.unitId(target_.unit), .binding = target_.binding };
            }
        }
        return null;
    }
    fn candidate(self: *Session, owner: usize, source: core.Id, identity: types.NominalIdentity, op: types.Operator, member: u32, left: type_evidence.Id, right: type_evidence.Id, expected: type_evidence.Id, side: dispatch_explanation.Side) Error!?Selection {
        if (try self.associatedTarget(self.unitId(owner), identity, member, op)) |method| {
            const resolved = try self.target(null, method);
            const module = &self.units[resolved.unit];
            const body = module.body(resolved.binding) orelse return null;
            const first = module.types.node(body.scheme.root);
            if (first.tag != .function) return null;
            const second = module.types.node(first.b);
            if (second.tag != .function) return null;
            var mappings: std.ArrayList(type_evidence.Mapping) = .empty;
            var row_mappings: std.ArrayList(type_evidence.RowMapping) = .empty;
            defer row_mappings.deinit(self.allocator);
            defer mappings.deinit(self.allocator);
            if (!try self.matchType(owner, source, resolved.unit, first.a, left, &mappings, &row_mappings) or !try self.matchType(owner, source, resolved.unit, second.a, right, &mappings, &row_mappings)) return null;
            // Operand admission chooses the method. A result mismatch belongs
            // to this chosen use, and must never select the other receiver.
            if (expected != 0 and !try self.matchType(owner, source, resolved.unit, second.b, expected, &mappings, &row_mappings)) {
                var record = if (side == .right) try self.rejectedCandidates(owner, op, member, left, right, false) else DispatchRecord{ .op = op, .member = member };
                record.add(side, if (side == .right) right else left, .result_mismatch);
                return self.failDispatch(owner, source, .type_mismatch, record);
            }
            const result = try self.projectType(resolved.unit, body.root, second.b, mappings.items, row_mappings.items);
            if (result == 0) return self.failNode(owner, source, .unsupported);
            return .{ .target = resolved, .full_type = try self.projectType(resolved.unit, body.root, body.scheme.root, mappings.items, row_mappings.items), .result = result };
        }
        return null;
    }
    fn select(self: *Session, owner: usize, source: core.Id, op: types.Operator, member: u32, left: type_evidence.Id, right: type_evidence.Id, expected: type_evidence.Id) Error!Selection {
        const left_identity = self.evidenceIdentity(left);
        if (left_identity) |identity| if (try self.candidate(owner, source, identity, op, member, left, right, expected, .left)) |chosen| return chosen;
        if (member == 0 and left != 0 and left == right) {
            const scalar = self.storage.evidence.node(left).tag;
            const comparison = op == .equal or op == .not_equal or op == .less or op == .less_equal or op == .greater or op == .greater_equal;
            if (op != .none and (scalar == .u32 or scalar == .f32 or (scalar == .boolean and (op == .equal or op == .not_equal)))) {
                const result = if (comparison) types.boolean else left;
                if (expected != 0 and expected != result) {
                    var record: DispatchRecord = .{ .op = op, .member = member };
                    record.add(.left, left, try self.ownerOutcome(owner, left_identity, op, member));
                    record.add(.builtin, left, .result_mismatch);
                    return self.failDispatch(owner, source, .type_mismatch, record);
                }
                return .{ .result = result };
            }
        }
        if (self.evidenceIdentity(right)) |identity| if (left_identity == null or !std.meta.eql(left_identity.?, identity)) {
            if (try self.candidate(owner, source, identity, op, member, left, right, expected, .right)) |chosen| return chosen;
        };
        return self.failDispatch(owner, source, if (member == 0) .ambiguous_operator else .missing_associated, try self.rejectedCandidates(owner, op, member, left, right, true));
    }
    fn dispatch(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const n = self.units[owner].node(id);
        const dependent = callerDependent(&self.units[owner].types, self.units[owner].typeOf(n.a), 0) or callerDependent(&self.units[owner].types, self.units[owner].typeOf(n.b), 0);
        errdefer if (dependent) self.anchorSpecialization(self.specialization_origin);
        const left_type = try self.projectType(owner, id, self.units[owner].typeOf(n.a), frame.mappings.items, frame.row_mappings.items);
        const right_type = try self.projectType(owner, id, self.units[owner].typeOf(n.b), frame.mappings.items, frame.row_mappings.items);
        const expected = try self.projectType(owner, id, n.ty, frame.mappings.items, frame.row_mappings.items);
        const preflight: ?Selection = if (left_type != 0 and right_type != 0) try self.select(owner, id, operator(n.op), if (n.tag == .associated) n.c else 0, left_type, right_type, expected) else null;
        const left = try self.expression(owner, n.a, frame);
        if (left != .value) return left;
        const right = try self.expression(owner, n.b, frame);
        if (right != .value) return right;
        const chosen = preflight orelse try self.select(owner, id, operator(n.op), if (n.tag == .associated) n.c else 0, self.valueEvidence(left.value), self.valueEvidence(right.value), expected);
        if (chosen.target) |producer| {
            try self.prepare(.{ .unit = self.unitId(producer.unit), .binding = producer.binding });
            return self.invokeNamed(producer, &.{ left.value, right.value }, owner, id, chosen.full_type, frame.providers);
        }
        const result = scalar_ops.evaluate(n.op, try self.requireScalar(owner, id, left.value), try self.requireScalar(owner, id, right.value)) catch |err| return self.failNode(owner, id, switch (err) {
            error.IntegerDivideByZero => .integer_divide_by_zero,
            error.Unsupported => .unsupported,
        });
        return .{ .value = try self.makeScalar(owner, id, result) };
    }
    fn resultSelection(self: *Session, owner: usize, source: core.Id, member: u32, input: type_evidence.Id, expected: type_evidence.Id) Error!Selection {
        var record: DispatchRecord = .{ .member = member };
        if (expected == 0) {
            record.add(.destination, 0, .unknown_operand);
            return self.failDispatch(owner, source, .ambiguous_associated, record);
        }
        const identity = self.evidenceIdentity(expected) orelse {
            record.add(.destination, expected, .no_member);
            return self.failDispatch(owner, source, .missing_associated, record);
        };
        if (try self.associatedTarget(self.unitId(owner), identity, member, .none)) |method| {
            const target_ = try self.target(null, method);
            const module = &self.units[target_.unit];
            const body = module.body(target_.binding) orelse return self.failNode(owner, source, .unsupported);
            const arrow = module.types.node(body.scheme.root);
            record.add(.destination, expected, .incompatible);
            if (arrow.tag != .function) return self.failDispatch(owner, source, .type_mismatch, record);
            var mappings: std.ArrayList(type_evidence.Mapping) = .empty;
            var row_mappings: std.ArrayList(type_evidence.RowMapping) = .empty;
            defer row_mappings.deinit(self.allocator);
            defer mappings.deinit(self.allocator);
            if (!try self.matchType(owner, source, target_.unit, arrow.a, input, &mappings, &row_mappings) or !try self.matchType(owner, source, target_.unit, arrow.b, expected, &mappings, &row_mappings)) return self.failDispatch(owner, source, .type_mismatch, record);
            return .{ .target = target_, .full_type = try self.projectType(target_.unit, body.root, body.scheme.root, mappings.items, row_mappings.items), .result = expected };
        }
        record.add(.destination, expected, .no_member);
        return self.failDispatch(owner, source, .missing_associated, record);
    }
    fn resultDispatch(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const n = module.node(id);
        errdefer if (callerDependent(&module.types, n.ty, 0)) self.anchorSpecialization(self.specialization_origin);
        const input = try self.projectType(owner, id, module.typeOf(n.a), frame.mappings.items, frame.row_mappings.items);
        const expected = try self.projectType(owner, id, n.ty, frame.mappings.items, frame.row_mappings.items);
        const preflight: ?Selection = if (input != 0 and expected != 0) try self.resultSelection(owner, id, n.b, input, expected) else null;
        const argument = try self.expression(owner, n.a, frame);
        if (argument != .value) return argument;
        const selection = preflight orelse try self.resultSelection(owner, id, n.b, self.valueEvidence(argument.value), expected);
        const target_ = selection.target.?;
        const function = try self.richValue(.{ .unit = self.unitId(target_.unit), .binding = target_.binding });
        const typed = try self.typedView(owner, id, function, selection.full_type);
        return self.applyValue(owner, id, typed, argument.value, frame.providers);
    }
    fn hasExplicitScheme(self: *const Session, owner: usize, scheme: types.Scheme) bool {
        const module = &self.units[owner];
        for (module.obligations[scheme.obligations.start..][0..scheme.obligations.len]) |obligation| {
            if (obligation.explicit) return true;
            if (obligation.kind == .callee_use and (obligation.identity.unit == 0 or obligation.identity.unit == self.unitId(owner)) and module.binding(obligation.identity.decl).has_explicit) return true;
        }
        return false;
    }
    fn validateScheme(self: *Session, owner: usize, source: core.Id, scheme: types.Scheme, frame: *Frame, allow_remaining: bool) Error!void {
        if (!self.hasExplicitScheme(owner, scheme)) return;
        const outer = self.constant_recorder orelse return self.validateSchemeInner(owner, source, scheme, frame, allow_remaining);
        try outer.beforeRead(self.allocator, self);
        var seeds = try (@import("../reuse/constant_receipt.zig").Inputs{ .types = frame.mappings.items, .rows = frame.row_mappings.items }).clone(self.allocator);
        defer seeds.deinit(self.allocator);
        self.constant_recorder = null;
        defer self.constant_recorder = outer;
        errdefer outer.eligible = false;
        try self.validateSchemeInner(owner, source, scheme, frame, allow_remaining);
        var judgment: @import("../reuse/constant_receipt.zig").Judgment = .{ .kind = .scheme, .unit = self.unitId(owner), .source = source, .scheme = scheme, .allow_remaining = allow_remaining, .inputs = seeds, .outputs = .{ .types = frame.mappings.items, .rows = frame.row_mappings.items } };
        try outer.query(self.allocator, self, .{ .kind = .judgment, .judgment = &judgment });
    }
    fn validateSchemeInner(self: *Session, owner: usize, source: core.Id, scheme: types.Scheme, frame: *Frame, allow_remaining: bool) Error!void {
        if (!self.hasExplicitScheme(owner, scheme)) return;
        var region = ClosureRegion.initAt(self, @src()) catch return error.OutOfMemory;
        defer region.deinit();
        const scope = region.typeScope(owner) catch |err| return self.evidenceFailure(owner, self.units[owner].span(source), err);
        if (self.has_implementations) region.current_implementation_context = self.implementationUseContext(owner, source);
        region.scratch.sources.items[scope].closed_rows = scheme.closed_rows;
        region.seed(scope, frame.mappings.items) catch |err| return self.evidenceFailure(owner, self.units[owner].span(source), err);
        region.seedRows(scope, frame.row_mappings.items) catch |err| return self.evidenceFailure(owner, self.units[owner].span(source), err);
        region.importScheme(scope, scheme, source) catch |err| return self.evidenceFailure(owner, self.units[owner].span(source), err);
        region.solveMode(allow_remaining) catch |err| return self.evidenceFailure(owner, self.units[owner].span(source), err);
        var solved = region.exportSolved(scope) catch |err| return self.evidenceFailure(owner, self.units[owner].span(source), err);
        defer solved.deinit(self.allocator);
        for (solved.types) |mapping| {
            const existing = for (frame.mappings.items) |prior| {
                if (prior.variable == mapping.variable) break prior.evidence;
            } else null;
            if (existing) |actual| {
                if (actual != mapping.evidence) return self.failNode(owner, source, .type_mismatch);
            } else try frame.mappings.append(self.allocator, mapping);
        }
        for (solved.rows) |mapping| {
            const existing = for (frame.row_mappings.items) |prior| {
                if (prior.variable == mapping.variable) break prior.evidence;
            } else null;
            if (existing) |actual| {
                if (actual != mapping.evidence) return self.failNode(owner, source, .effect_mismatch);
            } else try frame.row_mappings.append(self.allocator, mapping);
        }
    }
    fn validateBody(self: *Session, owner: usize, body: *const core.Body, frame: *Frame) Error!void {
        try self.validateScheme(owner, body.root, body.scheme, frame, false);
        for (self.units[owner].obligations[body.scheme.obligations.start..][0..body.scheme.obligations.len]) |obligation| {
            const source_types = &self.units[owner].types;
            const dependent = obligationDependent(source_types, obligation);
            errdefer if (dependent) self.anchorSpecialization(self.specialization_origin);
            if (obligation.kind == .type_head) {
                var actual = try self.projectType(owner, body.root, obligation.ty, frame.mappings.items, frame.row_mappings.items);
                if (actual == 0) continue;
                for (0..1024) |_| {
                    const head = self.storage.evidence.node(actual);
                    if (head.tag != .function) break;
                    actual = head.b;
                } else return self.fail(owner, obligation.span, .backend_limit);
                if (!try self.matchType(owner, body.root, owner, obligation.result, actual, &frame.mappings, &frame.row_mappings)) return self.fail(owner, obligation.span, .type_mismatch);
                continue;
            }
            if (obligation.kind == .monad_factory) {
                const input = try self.projectType(owner, body.root, obligation.ty, frame.mappings.items, frame.row_mappings.items);
                if (input != 0 and self.storage.evidence.node(input).tag != .type_constructor) return self.fail(owner, obligation.span, .type_constructor_required);
                continue;
            }
            if (obligation.kind == .resolver_dispatch) {
                const actual = try self.projectType(owner, body.root, obligation.ty, frame.mappings.items, frame.row_mappings.items);
                if (actual == 0) continue;
                const provider = self.storage.evidence.node(actual);
                if (provider.tag != .resolver) return self.fail(owner, obligation.span, .invalid_provider);
                const token = self.storage.evidence.node(provider.a);
                if (token.tag != .type_constructor) return self.fail(owner, obligation.span, .invalid_provider);
                const target_ = (try self.resolverMemberTarget(owner, obligation.name, (@as(u64, token.a) << 32) | token.b)) orelse return self.fail(owner, obligation.span, .missing_member);
                const producer = &self.units[target_.unit];
                const definition = producer.body(target_.binding) orelse return self.fail(owner, obligation.span, .unsupported);
                const signature = try self.projectType(owner, body.root, obligation.other, frame.mappings.items, frame.row_mappings.items);
                if (signature != 0) {
                    var mappings: std.ArrayList(type_evidence.Mapping) = .empty;
                    var row_mappings: std.ArrayList(type_evidence.RowMapping) = .empty;
                    defer row_mappings.deinit(self.allocator);
                    defer mappings.deinit(self.allocator);
                    if (!try self.matchType(owner, body.root, target_.unit, definition.scheme.root, signature, &mappings, &row_mappings)) return self.fail(owner, obligation.span, .type_mismatch);
                }
                try self.prepare(.{ .unit = self.unitId(target_.unit), .binding = target_.binding });
                continue;
            }
            if (obligation.kind == .resolver_shape) {
                const actual = try self.projectType(owner, body.root, obligation.ty, frame.mappings.items, frame.row_mappings.items);
                const result = try self.projectType(owner, body.root, obligation.result, frame.mappings.items, frame.row_mappings.items);
                if (actual == 0 or result == 0) continue;
                const provider = self.storage.evidence.node(actual);
                if (provider.tag != .resolver) return self.fail(owner, obligation.span, .invalid_provider);
                const token = self.storage.evidence.node(provider.a);
                const output = self.storage.evidence.node(result);
                if (output.tag != .never and (output.tag != .nominal or output.a != token.a or output.b != token.b)) return self.fail(owner, obligation.span, .type_mismatch);
                continue;
            }
            if (obligation.kind == .result_dispatch) {
                const input = try self.projectType(owner, body.root, obligation.ty, frame.mappings.items, frame.row_mappings.items);
                const expected = try self.projectType(owner, body.root, obligation.result, frame.mappings.items, frame.row_mappings.items);
                if (input != 0 and expected != 0) _ = self.resultSelection(owner, body.root, obligation.name, input, expected) catch |err| {
                    if (err == error.Declined and self.diagnostic != null) self.diagnostic.?.span = obligation.span;
                    return err;
                };
                continue;
            }
            if (obligation.kind != .dispatch) continue;
            const left = try self.projectType(owner, body.root, obligation.ty, frame.mappings.items, frame.row_mappings.items);
            const right = try self.projectType(owner, body.root, obligation.other, frame.mappings.items, frame.row_mappings.items);
            const result = try self.projectType(owner, body.root, obligation.result, frame.mappings.items, frame.row_mappings.items);
            if (left == 0 or right == 0) continue;
            _ = self.select(owner, body.root, obligation.operator, obligation.name, left, right, result) catch |err| {
                if (err == error.Declined and self.diagnostic != null) self.diagnostic.?.span = obligation.span;
                return err;
            };
        }
    }
    fn invokeNamed(self: *Session, resolved: Target, arguments: []const ValueId, owner: usize, source: core.Id, actual: type_evidence.Id, head: provider_chain.Head) Error!Flow {
        return self.invokeNamedWithSeeds(resolved, arguments, owner, source, actual, head, &.{}, &.{});
    }
    fn invokeNamedWithSeeds(self: *Session, resolved: Target, arguments: []const ValueId, owner: usize, source: core.Id, actual: type_evidence.Id, head: provider_chain.Head, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping) Error!Flow {
        const module = &self.units[resolved.unit];
        const body = module.body(resolved.binding) orelse return self.failNode(owner, source, .unsupported);
        const parameters = module.bodyParameters(body);
        if (self.constant_recorder) |recorder| try recorder.source(self.allocator, .{ .unit = self.unitId(resolved.unit), .binding = resolved.binding });
        if (!body.is_function or arguments.len != parameters.len) return self.failNode(owner, source, .unsupported);
        const previous_generator = self.generator_origin;
        if (self.generator_origin == null) self.generator_origin = .{ .unit = self.unitId(owner), .node = source };
        defer self.generator_origin = previous_generator;
        const previous_origin = self.specialization_origin;
        self.specialization_origin = self.invocationOrigin(owner, source, callerDependentUse(&self.units[owner], source));
        defer self.specialization_origin = previous_origin;
        var callee: Frame = .{ .providers = head };
        defer callee.deinit(self.allocator);
        try callee.mappings.appendSlice(self.allocator, seeds);
        try callee.row_mappings.appendSlice(self.allocator, row_seeds);
        if (actual != 0 and !try self.matchType(owner, source, resolved.unit, module.binding(resolved.binding).ty, actual, &callee.mappings, &callee.row_mappings)) return self.failNode(owner, source, .unsupported);
        for (arguments, parameters) |argument, parameter| {
            if (self.valueEvidence(argument) != 0 and !try self.matchType(owner, source, resolved.unit, parameter.ty, self.valueEvidence(argument), &callee.mappings, &callee.row_mappings)) return self.failNode(owner, source, .unsupported);
            const expected = try self.projectType(resolved.unit, body.root, parameter.ty, callee.mappings.items, callee.row_mappings.items);
            const typed = try self.typedView(owner, source, argument, expected);
            if (parameter.binding != 0) try callee.values.put(self.allocator, parameter.binding, typed);
        }
        try self.validateBody(resolved.unit, body, &callee);
        try self.enterCall(owner, source);
        defer self.call_depth -= 1;
        errdefer self.anchorRecursion(owner, source);
        const outcome = try self.expression(resolved.unit, body.root, &callee);
        if (outcome != .value) return self.fail(resolved.unit, body.span, .unsupported);
        return outcome;
    }
    /// Each compile-time function body entered counts once, however deeply
    /// its expressions nest.
    fn enterCall(self: *Session, owner: usize, source: core.Id) Error!void {
        if (self.call_depth >= self.options.max_call_depth) return self.failNode(owner, source, .constant_recursion);
        self.call_depth += 1;
        if (self.constant_recorder) |recorder| recorder.observe(self);
    }
    /// Unwinding frames move a call-depth failure to their own call site, so
    /// it ends at the outermost call of the evaluation, in the caller's code.
    fn anchorRecursion(self: *Session, owner: usize, source: core.Id) void {
        const issue = if (self.diagnostic) |*diagnostic| diagnostic else return;
        if (issue.code != .constant_recursion or owner >= self.units.len) return;
        issue.unit = self.unitId(owner);
        issue.span = self.units[owner].span(source);
    }
    fn callableEvidence(self: *Session, owner: usize, source: core.Id, actual: type_evidence.Id) Error!type_evidence.Node {
        var current = actual;
        for (0..128) |_| {
            const node = self.storage.evidence.node(current);
            if (node.tag == .function) return node;
            if (node.tag != .usage or node.c != 0 or (node.b != @backingInt(types.UsageKind.once) and node.b != @backingInt(types.UsageKind.many) and node.b != @backingInt(types.UsageKind.cleanup))) return self.failNode(owner, source, .unsupported);
            current = node.a;
        }
        return self.failNode(owner, source, .unsupported);
    }
    fn applyValue(self: *Session, owner: usize, source: core.Id, function: ValueId, argument: ValueId, head: provider_chain.Head) Error!Flow {
        const actual = self.valueEvidence(function);
        const outcome = try self.applyValueInner(owner, source, function, argument, head);
        if (outcome == .value and actual != 0) {
            const full = try self.callableEvidence(owner, source, actual);
            return .{ .value = try self.typedView(owner, source, outcome.value, full.b) };
        }
        return outcome;
    }
    fn forceValue(self: *Session, owner: usize, source: core.Id, value_: ValueId, head: provider_chain.Head) Error!Flow {
        self.declineConstant();
        const info = self.valueInfo(value_);
        if (info.kind != .suspension) return self.failNode(owner, source, .unsupported);
        const slot_index: usize = @intCast(info.nominal);
        const actual = self.valueEvidence(value_);
        const result = if (actual != 0) blk: {
            const n = self.storage.evidence.node(actual);
            if (n.tag != .demand) return self.failNode(owner, source, .unsupported);
            break :blk n.a;
        } else 0;
        if (self.storage.demands.items[slot_index].state == .cached) return .{ .value = try self.typedView(owner, source, self.storage.demands.items[slot_index].value, result) };
        if (self.storage.demands.items[slot_index].state == .evaluating) return self.failNode(owner, source, .cycle);
        self.storage.demands.items[slot_index].state = .evaluating;
        errdefer self.storage.demands.items[slot_index].state = .pending;
        const metadata = self.suspensionInfo(value_);
        const producer = self.findUnit(metadata.unit, null) orelse return self.failNode(owner, source, .unsupported);
        const template = self.units[producer].closures[metadata.identity];
        try self.prepareWork(.{ .node = .{ .unit = producer, .id = template.body } });
        // An ordinary internal thunk header shares numeric code/capture identity;
        // the source demand keeps its independent semantic tag and memo slot.
        const captures = try self.allocator.dupe(ValueId, self.valueChildren(value_));
        defer self.allocator.free(captures);
        const function = try self.makeClosure(owner, source, metadata, captures);
        const expected = if (result != 0) self.storage.evidence.internWithEffects(.function, types.unit, result, self.storage.evidence.node(actual).c, &.{}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return self.failNode(owner, source, .unsupported),
        } else 0;
        const typed = try self.typedView(owner, source, function, expected);
        const outcome = try self.applyValue(owner, source, typed, 0, head);
        if (outcome != .value) return self.failNode(owner, source, .unsupported);
        self.storage.demands.items[slot_index] = .{ .state = .cached, .value = outcome.value };
        return outcome;
    }
    /// Dedicated capability values carry only invocation-local authority.
    /// Their nominal word names their original allocation, including typed aliases.
    fn capabilityIdentity(self: *Session, owner: usize, source: core.Id, value_: ValueId) Error!u32 {
        const info = self.valueInfo(value_);
        const actual = self.valueEvidence(value_);
        if (info.kind != .capability or info.len != 0 or info.nominal == 0 or info.nominal > std.math.maxInt(u32) or actual == 0 or self.storage.evidence.node(actual).tag != .scoped) return self.failNode(owner, source, .invalid_provider);
        const identity: u32 = @intCast(info.nominal);
        if (std.mem.findScalar(ValueId, self.capability_scopes.items, identity) == null) return self.failNode(owner, source, .invalid_provider);
        return identity;
    }
    fn capabilityToken(self: *const Session, token: provider_chain.Operation, identity: ValueId) bool {
        if (token == 0 or token >= self.storage.evidence.effects.operations.items.len) return false;
        const instance = self.storage.evidence.effects.view().operation(token).instance;
        return instance.unit == 0 and instance.decl == identity;
    }
    fn capabilityEscapes(self: *Session, owner: usize, source: core.Id, value_: ValueId, identity: ValueId) Error!bool {
        var work: std.ArrayList(ValueId) = .empty;
        defer work.deinit(self.allocator);
        var seen: std.AutoHashMapUnmanaged(ValueId, void) = .empty;
        defer seen.deinit(self.allocator);
        try work.append(self.allocator, value_);
        while (work.pop()) |current| {
            const entry = try seen.getOrPut(self.allocator, current);
            if (entry.found_existing) continue;
            if (seen.count() > self.options.max_values) return self.failNode(owner, source, .constant_fuel);
            const info = self.valueInfo(current);
            if (info.kind == .capability and info.nominal == identity) return true;
            switch (info.kind) {
                .provider, .state_provider, .effect_descriptor => {
                    if (self.capabilityToken(info.bits, identity)) return true;
                    if (info.kind == .state_provider and info.nominal <= std.math.maxInt(u32) and self.capabilityToken(@intCast(info.nominal), identity)) return true;
                },
                .effect_set => for (self.storage.evidence.effects.view().rowLabels(info.bits)) |token| {
                    if (self.capabilityToken(token, identity)) return true;
                },
                else => {},
            }
            try work.appendSlice(self.allocator, self.valueChildren(current));
            if (info.kind == .suspension) if (self.suspensionCached(current)) |cached| try work.append(self.allocator, cached);
        }
        return false;
    }
    fn effectScope(self: *Session, owner: usize, source: core.Id, frame: *Frame) Error!Flow {
        self.declineConstant();
        const callback = try self.expression(owner, self.units[owner].node(source).a, frame);
        if (callback != .value) return callback;
        const actual = self.valueEvidence(callback.value);
        if (actual == 0) return self.failNode(owner, source, .unsupported);
        const arrow = self.storage.evidence.node(actual);
        if (arrow.tag != .function or self.storage.evidence.node(arrow.a).tag != .scoped) return self.failNode(owner, source, .unsupported);
        // Values are never recycled within a Session, so repeated entries at the
        // same source site get distinct keys without a global identity counter.
        const capability = try self.makeAggregate(owner, source, .capability, 0, 0, &.{});
        self.storage.values.items[capability].nominal = capability;
        self.storage.value_evidence.items[capability] = arrow.a;
        try self.capability_scopes.append(self.allocator, capability);
        defer _ = self.capability_scopes.pop();
        const result = try self.applyValue(owner, source, callback.value, capability, frame.providers);
        if (result != .value or try self.capabilityEscapes(owner, source, result.value, capability)) return self.failNode(owner, source, .unsupported);
        return result;
    }
    fn operationToken(self: *Session, owner: usize, source: core.Id, function: ValueId) Error!provider_chain.Operation {
        if (self.valueInfo(function).kind != .closure) return self.failNode(owner, source, .invalid_provider);
        const closure = self.closureInfo(function);
        if (closure.origin != .operation or closure.applied != 0) return self.failNode(owner, source, .invalid_provider);
        const producer = self.findUnit(closure.unit, null) orelse return self.failNode(owner, source, .unsupported);
        const module = &self.units[producer];
        const operation = module.operation_values[closure.identity];
        var mappings: std.ArrayList(type_evidence.Mapping) = .empty;
        defer mappings.deinit(self.allocator);
        var rows: std.ArrayList(type_evidence.RowMapping) = .empty;
        defer rows.deinit(self.allocator);
        try mappings.appendSlice(self.allocator, self.storage.type_mappings.items[closure.mappings.start..][0..closure.mappings.len]);
        try rows.appendSlice(self.allocator, self.storage.row_mappings.items[closure.row_mappings.start..][0..closure.row_mappings.len]);
        const actual = self.valueEvidence(function);
        if (actual != 0) {
            const selected = self.storage.evidence.node(actual);
            const signature = module.types.node(operation.signature);
            if (selected.tag != .function or signature.tag != .function or
                !try self.matchType(owner, source, producer, signature.a, selected.a, &mappings, &rows) or
                !try self.matchType(owner, source, producer, signature.b, selected.b, &mappings, &rows)) return self.failNode(owner, source, .type_mismatch);
        }
        var arguments: std.ArrayList(type_evidence.Id) = .empty;
        defer arguments.deinit(self.allocator);
        for (module.types.list(operation.arguments)) |argument| {
            const projected = try self.projectType(producer, source, argument, mappings.items, rows.items);
            if (projected == 0) return self.failNode(owner, source, .unsupported);
            try arguments.append(self.allocator, projected);
        }
        const identity: types.NominalIdentity = .{ .unit = if (operation.identity.unit == 0) self.unitId(producer) else operation.identity.unit, .decl = operation.identity.decl };
        var instance = operation.instance;
        const witnesses = self.valueChildren(function);
        if (witnesses.len != 0) {
            if (witnesses.len != 1) return self.failNode(owner, source, .invalid_provider);
            instance = .{ .unit = 0, .decl = try self.capabilityIdentity(owner, source, witnesses[0]) };
        } else if (instance.unit != 0 or instance.decl != 0) return self.failNode(owner, source, .invalid_provider);
        return self.storage.evidence.effects.internOperationInstance(identity, arguments.items, instance) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.EvidenceLimit => self.failNode(owner, source, .constant_fuel),
            else => self.failNode(owner, source, .unsupported),
        };
    }
    /// An operation value owns exactly its selected label. Its source invocation
    /// signature may widen that row in a caller, and remains unchanged in core.
    fn operationSignature(self: *Session, owner: usize, source: core.Id, function: ValueId, token: provider_chain.Operation) Error!type_evidence.Id {
        const closure = self.closureInfo(function);
        const producer = self.findUnit(closure.unit, null) orelse return self.failNode(owner, source, .unsupported);
        const module = &self.units[producer];
        const signature = module.types.node(module.operation_values[closure.identity].signature);
        if (signature.tag != .function) return self.failNode(owner, source, .invalid_provider);
        const mappings = self.storage.type_mappings.items[closure.mappings.start..][0..closure.mappings.len];
        const rows = self.storage.row_mappings.items[closure.row_mappings.start..][0..closure.row_mappings.len];
        const parameter = try self.projectType(producer, source, signature.a, mappings, rows);
        const result = try self.projectType(producer, source, signature.b, mappings, rows);
        if (parameter == 0 or result == 0) return 0;
        const row = self.storage.evidence.effects.internRow(&.{token}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return self.failNode(owner, source, .constant_fuel),
        };
        return self.storage.evidence.internWithEffects(.function, parameter, result, row, &.{}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return self.failNode(owner, source, .constant_fuel),
        };
    }
    fn providerFailure(self: *Session, owner: usize, source: core.Id, err: provider_chain.Error) Error {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.ProviderLimit => self.failNode(owner, source, .constant_fuel),
            else => self.failNode(owner, source, .invalid_provider),
        };
    }
    fn requestStateValue(self: *Session, owner: usize, id: core.Id, ty: types.Id, bindings: []const core.BindingId, frame: *Frame) Error!ValueId {
        if (bindings.len == 0) return 0;
        if (bindings.len == 1) return frame.values.get(bindings[0]) orelse self.failNode(owner, id, .unsupported);
        var storage_buffer: [256]u8 align(@alignOf(usize)) = undefined;
        var storage: std.heap.BufferFirstAllocator = .init(&storage_buffer, self.allocator);
        const scratch = storage.allocator();
        const values_ = try scratch.alloc(ValueId, bindings.len);
        defer scratch.free(values_);
        for (bindings, 0..) |binding, index| values_[index] = frame.values.get(binding) orelse return self.failNode(owner, id, .unsupported);
        const value_ = try self.makeAggregate(owner, id, .product, 0, 0, values_);
        return self.typedView(owner, id, value_, try self.projectType(owner, id, ty, frame.mappings.items, frame.row_mappings.items));
    }
    fn requestInstallState(self: *Session, owner: usize, id: core.Id, bindings: []const core.BindingId, state: ValueId, frame: *Frame) Error!void {
        if (bindings.len == 0) return;
        if (bindings.len == 1) {
            try frame.values.put(self.allocator, bindings[0], state);
            return;
        }
        const info = self.valueInfo(state);
        if (info.kind != .product or info.len != bindings.len) return self.failNode(owner, id, .unsupported);
        for (bindings, 0..) |binding, index| try frame.values.put(self.allocator, binding, self.valueChildren(state)[index]);
    }
    fn requestOperation(self: *Session, owner: usize, id: core.Id, handler_id: u32, argument: ValueId) Error!Flow {
        if (handler_id >= self.request_handlers.items.len) return self.failNode(owner, id, .unsupported);
        // Copy numeric records before invoking arbitrary nested computations.
        const handler = self.request_handlers.items[handler_id];
        if (handler.cell == 0 or handler.cell > self.request_cells.items.len) return self.failNode(owner, id, .unsupported);
        const state = self.request_cells.items[handler.cell - 1].state;
        const arguments = try self.makeAggregate(owner, id, .product, 0, 0, &.{ argument, state });
        const argument_type = self.valueEvidence(argument);
        const state_type = self.valueEvidence(state);
        const actual = if (argument_type != 0 and state_type != 0) self.storage.evidence.intern(.product, 0, 0, &.{ argument_type, state_type }) catch |err| return self.evidenceFailure(owner, self.units[owner].span(id), err) else 0;
        const typed = try self.typedView(owner, id, arguments, actual);
        const outcome = try self.applyValue(owner, id, handler.callback, typed, handler.outer);
        if (outcome != .value) return self.failNode(owner, id, .unsupported);
        const decision = self.valueInfo(outcome.value);
        if (decision.kind != .request_decision or decision.len != 2 or decision.bits > @backingInt(core.RequestDecisionKind.break_)) return self.failNode(owner, id, .unsupported);
        const payload = self.valueChildren(outcome.value)[0];
        const successor = self.valueChildren(outcome.value)[1];
        const kind: core.RequestDecisionKind = @fromBackingInt(@intCast(decision.bits));
        if (kind == .reply) {
            self.request_cells.items[handler.cell - 1].state = successor;
            return .{ .value = payload };
        }
        self.request_cells.items[handler.cell - 1].status = kind;
        if (kind == .cancel) self.request_cells.items[handler.cell - 1].exit = payload else self.request_cells.items[handler.cell - 1].state = successor;
        self.request_owner = handler.cell;
        return error.RequestUnwind;
    }
    fn requestLoop(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const metadata = module.requestLoopInfo(id);
        const computation = try self.expression(owner, metadata.computation, frame);
        if (computation != .value) return computation;
        const computation_info = self.valueInfo(computation.value);
        if (computation_info.kind != .computation or computation_info.len != 1) return self.failNode(owner, id, .unsupported);
        const action = self.valueChildren(computation.value)[0];
        const carries = module.requestLoopCarries(id);
        var storage_buffer: [512]u8 align(@alignOf(usize)) = undefined;
        var storage: std.heap.BufferFirstAllocator = .init(&storage_buffer, self.allocator);
        const scratch = storage.allocator();
        const incoming = try scratch.alloc(core.BindingId, carries.len);
        defer scratch.free(incoming);
        for (carries, 0..) |carry, index| incoming[index] = carry.incoming;
        const initial = try self.requestStateValue(owner, id, metadata.state_type, incoming, frame);
        const cell_mark = self.request_cells.items.len;
        const handler_mark = self.request_handlers.items.len;
        const provider_mark = self.providers.mark();
        defer self.request_cells.shrinkRetainingCapacity(cell_mark);
        defer self.request_handlers.shrinkRetainingCapacity(handler_mark);
        defer self.providers.rewind(provider_mark);
        if (cell_mark >= std.math.maxInt(u32)) return self.failNode(owner, id, .constant_fuel);
        const cell: u32 = @intCast(cell_mark + 1);
        try self.request_cells.append(self.allocator, .{ .state = initial });
        var head = frame.providers;
        for (module.requestArms(id)) |arm| {
            const callback = try self.expression(owner, arm.callback, frame);
            if (callback != .value) return callback;
            var label: provider_chain.Operation = undefined;
            if (arm.selector != 0) {
                const selected = try self.expression(owner, arm.selector, frame);
                if (selected != .value) return selected;
                label = try self.operationToken(owner, id, selected.value);
            } else label = try self.reflectionLabel(owner, id, arm.operation, frame);
            if (self.request_handlers.items.len >= std.math.maxInt(u32)) return self.failNode(owner, id, .constant_fuel);
            const handler: u32 = @intCast(self.request_handlers.items.len);
            try self.request_handlers.append(self.allocator, .{ .callback = callback.value, .cell = cell, .outer = frame.providers });
            head = self.providers.installRequest(self.storage.evidence.effects.view(), head, label, handler) catch |err| return self.providerFailure(owner, id, err);
        }
        const outcome = self.applyValue(owner, id, action, 0, head) catch |err| {
            if (err != error.RequestUnwind or self.request_owner != cell) return err;
            self.request_owner = 0;
            const finished = self.request_cells.items[cell - 1];
            if (finished.status == .cancel) return .{ .returning = .{ .target = metadata.return_target, .value = finished.exit } };
            if (finished.status != .break_) return self.failNode(owner, id, .unsupported);
            const outgoing = try scratch.alloc(core.BindingId, carries.len);
            defer scratch.free(outgoing);
            for (carries, 0..) |carry, index| outgoing[index] = carry.outgoing;
            try self.requestInstallState(owner, id, outgoing, finished.state, frame);
            return .{ .value = 0 };
        };
        if (outcome != .value) return outcome;
        // Completion and all operation clauses run under the original ambient
        // provider head; no request installation remains visible to them.
        try self.requestInstallState(owner, id, module.requestCompletionBindings(id), self.request_cells.items[cell - 1].state, frame);
        var bound: std.ArrayList(Bound) = .empty;
        defer bound.deinit(self.allocator);
        if (!try self.matchPattern(owner, metadata.completion_pattern, outcome.value, frame, &bound, 0)) return self.failNode(owner, id, .unsupported);
        try self.installBindings(frame, bound.items);
        const completion = try self.expression(owner, metadata.completion_body, frame);
        if (completion == .breaking and completion.breaking.target == id) {
            const values_ = completion.breaking.values;
            if (values_.len != carries.len) return self.failNode(owner, id, .unsupported);
            for (carries, 0..) |carry, index| try frame.values.put(self.allocator, carry.outgoing, self.break_values.items[values_.start + index]);
            self.break_values.shrinkRetainingCapacity(values_.start);
            return .{ .value = 0 };
        }
        return completion;
    }
    fn handle(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const node = self.units[owner].node(id);
        const outcome = try self.expression(owner, node.a, frame);
        if (outcome != .value) return outcome;
        const value_ = outcome.value;
        const kind = self.valueInfo(value_).kind;
        const point = self.providers.mark();
        defer self.providers.rewind(point);
        const outer = frame.providers;
        defer frame.providers = outer;
        var cell: provider_chain.CellId = 0;
        switch (kind) {
            .provider => frame.providers = self.providers.installProvider(self.storage.evidence.effects.view(), outer, self.providerInfo(value_)) catch |err| return self.providerFailure(owner, id, err),
            .state_provider => {
                const installation = self.providers.installState(self.storage.evidence.effects.view(), outer, self.stateProviderInfo(value_)) catch |err| return self.providerFailure(owner, id, err);
                frame.providers = installation.head;
                cell = installation.cell;
            },
            else => return self.failNode(owner, id, .invalid_provider),
        }
        const body = try self.expression(owner, node.b, frame);
        if (body != .value or cell == 0) return body;
        self.declineConstant();
        const successor = self.providers.read(cell) catch |err| return self.providerFailure(owner, id, err);
        return .{ .value = try self.makeAggregate(owner, id, .product, 0, 0, &.{ successor, body.value }) };
    }
    fn resolverMemberTarget(self: *Session, owner: usize, member: u32, family: u64) Error!?Target {
        const identity: types.NominalIdentity = .{ .unit = @intCast(family >> 32), .decl = @truncate(family) };
        const method = try self.associatedTarget(self.unitId(owner), identity, member, .none) orelse return null;
        return try self.target(null, method);
    }
    fn resolverTarget(self: *Session, owner: usize, source: core.Id, metadata: core.ResolverInfo, family: u64) Error!Target {
        if (metadata.method.binding != 0) return self.external(try self.target(owner, metadata.method));
        return (try self.resolverMemberTarget(owner, metadata.member, family)) orelse self.failNode(owner, source, .missing_member);
    }
    fn resolverResult(self: *Session, owner: usize, source: core.Id, family: u64, flow: Flow) Error!Flow {
        if (flow != .value) return flow;
        const result = self.valueInfo(flow.value);
        if (result.kind != .nominal or result.nominal != family) return self.failNode(owner, source, .type_mismatch);
        return flow;
    }
    fn resolverOperation(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const metadata = module.resolverInfo(id);
        const arguments = module.resolverArguments(id);
        const arity: usize = switch (metadata.operation) {
            .monad => 0,
            .pure, .forward, .run => 1,
            .bind, .iterate => 2,
        };
        if (arguments.len != arity) return self.failNode(owner, id, .unsupported);
        const provider = try self.expression(owner, metadata.resolver, frame);
        if (provider != .value) return provider;
        const info = self.valueInfo(provider.value);
        if (metadata.operation == .monad) {
            if (info.kind != .type_constructor) return self.failNode(owner, id, .type_constructor_required);
            return .{ .value = try self.makeAggregate(owner, id, .resolver, info.nominal, 0, &.{}) };
        }
        if (info.kind != .resolver) return self.failNode(owner, id, .invalid_provider);
        // Resolve the actual source method before evaluating its operands.
        // Continuations remain ordinary closures: the producer controls how
        // often they run and what wrapped result they return.
        const chosen: ?Target = switch (metadata.operation) {
            .pure, .bind, .iterate => try self.resolverTarget(owner, id, metadata, info.nominal),
            .forward, .run => null,
            .monad => unreachable,
        };
        if (chosen) |target_| try self.prepare(.{ .unit = self.unitId(target_.unit), .binding = target_.binding });
        var values_: [2]ValueId = undefined;
        for (arguments, 0..) |argument, index| {
            const value_ = try self.expression(owner, argument, frame);
            if (value_ != .value) return value_;
            values_[index] = value_.value;
        }
        if (metadata.operation == .forward) return self.resolverResult(owner, id, info.nominal, .{ .value = values_[0] });
        if (metadata.operation == .run) return self.resolverResult(owner, id, info.nominal, try self.applyValue(owner, id, values_[0], 0, frame.providers));
        const target_ = chosen.?;
        const producer = &self.units[target_.unit];
        const body = producer.body(target_.binding) orelse return self.failNode(owner, id, .unsupported);
        var mappings: std.ArrayList(type_evidence.Mapping) = .empty;
        var row_mappings: std.ArrayList(type_evidence.RowMapping) = .empty;
        defer row_mappings.deinit(self.allocator);
        defer mappings.deinit(self.allocator);
        var method_type = body.scheme.root;
        for (values_[0..arity]) |argument| {
            const arrow = producer.types.node(method_type);
            if (arrow.tag != .function) return self.failNode(owner, id, .type_mismatch);
            const actual = self.valueEvidence(argument);
            if (actual != 0 and !try self.matchType(owner, id, target_.unit, arrow.a, actual, &mappings, &row_mappings)) return self.failNode(owner, id, .type_mismatch);
            method_type = arrow.b;
        }
        const expected = try self.projectType(owner, id, module.typeOf(id), frame.mappings.items, frame.row_mappings.items);
        if (expected != 0 and !try self.matchType(owner, id, target_.unit, method_type, expected, &mappings, &row_mappings)) return self.failNode(owner, id, .type_mismatch);
        const declared = if (metadata.method_type != 0) try self.projectType(owner, id, metadata.method_type, frame.mappings.items, frame.row_mappings.items) else 0;
        if (declared != 0 and !try self.matchType(owner, id, target_.unit, body.scheme.root, declared, &mappings, &row_mappings)) return self.failNode(owner, id, .type_mismatch);
        const full = try self.projectType(target_.unit, body.root, body.scheme.root, mappings.items, row_mappings.items);
        var function = try self.typedView(owner, id, try self.constant(target_), full);
        for (values_[0..arity]) |argument| {
            const outcome = try self.applyValue(owner, id, function, argument, frame.providers);
            if (outcome != .value) return outcome;
            function = outcome.value;
        }
        return self.resolverResult(owner, id, info.nominal, .{ .value = function });
    }
    fn applyValueInner(self: *Session, owner: usize, source: core.Id, function: ValueId, argument: ValueId, head: provider_chain.Head) Error!Flow {
        const previous_generator = self.generator_origin;
        if (self.generator_origin == null) self.generator_origin = .{ .unit = self.unitId(owner), .node = source };
        defer self.generator_origin = previous_generator;
        if (self.valueInfo(function).kind != .closure) return self.failNode(owner, source, .unsupported);
        const closure = self.closureInfo(function);
        const producer = self.findUnit(closure.unit, null) orelse return self.failNode(owner, source, .unsupported);
        const module = &self.units[producer];
        switch (closure.origin) {
            .operation => {
                self.declineConstant();
                const token = try self.operationToken(owner, source, function);
                const matched = self.providers.lookup(head, token) catch |err| return self.providerFailure(owner, source, err);
                const selected = matched orelse return self.failNode(owner, source, .const_effect);
                return switch (selected.frame.kind) {
                    .callback => self.applyValue(owner, source, selected.frame.target, argument, selected.frame.outer),
                    .request => self.requestOperation(owner, source, selected.frame.target, argument),
                    .state_read => .{ .value = self.providers.read(selected.frame.target) catch |err| return self.providerFailure(owner, source, err) },
                    .state_write => blk: {
                        self.providers.write(selected.frame.target, argument) catch |err| return self.providerFailure(owner, source, err);
                        break :blk .{ .value = 0 };
                    },
                };
            },
            .primitive => {
                const primitive = module.primitives[closure.identity];
                if (closure.applied >= primitive.arity or self.valueInfo(function).len != closure.applied or primitive.arity > 3) return self.failNode(owner, source, .unsupported);
                var arguments: [3]ValueId = undefined;
                @memcpy(arguments[0..closure.applied], self.valueChildren(function));
                arguments[closure.applied] = argument;
                const count = closure.applied + 1;
                if (count < primitive.arity) {
                    var partial = closure;
                    partial.applied = count;
                    return .{ .value = try self.makeClosure(owner, source, partial, arguments[0..count]) };
                }
                if (primitive.kind == .array) return .{ .value = try self.arrayValues(owner, source, primitive.array_op, arguments[0..count], head) };
                if (self.valueInfo(arguments[0]).kind == .product) return .{ .value = try self.simdValue(owner, source, primitive.op, arguments[0], if (count == 1) 0 else arguments[1]) };
                const a = try self.requireScalar(owner, source, arguments[0]);
                const b = if (count == 1) unit_value else try self.requireScalar(owner, source, arguments[1]);
                const value_ = scalar_ops.evaluate(primitive.op, a, b) catch |err| return self.failNode(owner, source, switch (err) {
                    error.IntegerDivideByZero => .integer_divide_by_zero,
                    error.Unsupported => .unsupported,
                });
                return .{ .value = try self.makeScalar(owner, source, value_) };
            },
            .constructor => {
                const constructor = module.constructor(closure.identity);
                if (constructor.payload == 0) return self.failNode(owner, source, .unsupported);
                const nominal = module.nominal(constructor.nominal);
                var stored = argument;
                if (!nominal.is_opaque and module.types.node(constructor.payload).tag == .record) stored = try self.recordArgument(producer, owner, source, closure.identity, argument);
                return .{ .value = try self.makeAggregate(owner, source, .nominal, self.nominalIdentity(producer, nominal.identity.unit, nominal.identity.decl), constructor.tag, &.{stored}) };
            },
            .anonymous => {
                if (self.constant_recorder) |recorder| try recorder.closure(self.allocator, closure.unit, closure.identity);
                const template = module.closures[closure.identity];
                const bindings = module.extra[template.captures.start..][0..template.captures.len];
                if (bindings.len != self.valueInfo(function).len or closure.applied != 0) return self.failNode(owner, source, .unsupported);
                var callee: Frame = .{ .providers = head, .staged = if (closure.staged == 0) null else closure.staged };
                defer callee.deinit(self.allocator);
                try callee.mappings.appendSlice(self.allocator, self.storage.type_mappings.items[closure.mappings.start..][0..closure.mappings.len]);
                try callee.row_mappings.appendSlice(self.allocator, self.storage.row_mappings.items[closure.row_mappings.start..][0..closure.row_mappings.len]);
                const actual = self.valueEvidence(function);
                if (actual != 0) {
                    const full = try self.callableEvidence(owner, source, actual);
                    if (template.function_type != 0) {
                        var signature = template.function_type;
                        const declared = module.types.node(signature);
                        if (declared.tag == .usage and self.storage.evidence.node(actual).tag == .function) {
                            // Invocation selects an arrow from the checked
                            // owning callable. Instantiate its body signature;
                            // its declaration still owns the affine move proof.
                            if (declared.c != 0 or (declared.b != @backingInt(types.UsageKind.once) and declared.b != @backingInt(types.UsageKind.many) and declared.b != @backingInt(types.UsageKind.cleanup))) return self.failNode(owner, source, .unsupported);
                            signature = declared.a;
                        }
                        if (!try self.matchCovariantType(owner, source, producer, signature, actual, &callee.mappings, &callee.row_mappings)) return self.failNode(owner, source, .unsupported);
                    } else if (!try self.matchType(owner, source, producer, template.parameter.ty, full.a, &callee.mappings, &callee.row_mappings) or !try self.matchType(owner, source, producer, module.typeOf(template.body), full.b, &callee.mappings, &callee.row_mappings)) return self.failNode(owner, source, .unsupported);
                }
                if (self.valueEvidence(argument) != 0 and !try self.matchType(owner, source, producer, template.parameter.ty, self.valueEvidence(argument), &callee.mappings, &callee.row_mappings)) return self.failNode(owner, source, .unsupported);
                for (bindings, 0..) |binding, index| try callee.values.put(self.allocator, binding, self.valueChildren(function)[index]);
                const typed = try self.typedView(owner, source, argument, try self.projectType(producer, template.body, template.parameter.ty, callee.mappings.items, callee.row_mappings.items));
                if (template.parameter.binding != 0) try callee.values.put(self.allocator, template.parameter.binding, typed);
                if (template.qualifier != 0) try self.validateScheme(producer, template.body, module.binding(template.qualifier).scheme, &callee, false);
                try self.enterCall(owner, source);
                defer self.call_depth -= 1;
                errdefer self.anchorRecursion(owner, source);
                const outcome = try self.expression(producer, template.body, &callee);
                if (outcome != .value) return self.failNode(owner, source, .unsupported);
                return outcome;
            },
            .named => {
                const resolved = try self.external(try self.target(null, .{ .unit = closure.unit, .binding = closure.identity }));
                const body = self.units[resolved.unit].body(resolved.binding) orelse return self.failNode(owner, source, .unsupported);
                const parameters = self.units[resolved.unit].bodyParameters(body);
                if (!body.is_function or closure.applied >= parameters.len or self.valueInfo(function).len != closure.applied) return self.failNode(owner, source, .unsupported);
                var storage_buffer: [256]u8 align(@alignOf(usize)) = undefined;
                var storage: std.heap.BufferFirstAllocator = .init(&storage_buffer, self.allocator);
                const scratch = storage.allocator();
                const arguments = try scratch.alloc(ValueId, closure.applied + 1);
                defer scratch.free(arguments);
                @memcpy(arguments[0..closure.applied], self.valueChildren(function));
                arguments[closure.applied] = argument;
                var callee: Frame = .{ .providers = head };
                defer callee.deinit(self.allocator);
                try callee.mappings.appendSlice(self.allocator, self.storage.type_mappings.items[closure.mappings.start..][0..closure.mappings.len]);
                try callee.row_mappings.appendSlice(self.allocator, self.storage.row_mappings.items[closure.row_mappings.start..][0..closure.row_mappings.len]);
                const actual = self.valueEvidence(function);
                if (actual != 0) {
                    var suffix = self.units[resolved.unit].binding(resolved.binding).ty;
                    for (0..closure.applied) |_| suffix = self.units[resolved.unit].types.node(suffix).b;
                    if (!try self.matchCovariantType(owner, source, resolved.unit, suffix, actual, &callee.mappings, &callee.row_mappings)) return self.failNode(owner, source, .unsupported);
                }
                for (arguments, parameters[0..arguments.len]) |arg, parameter| if (self.valueEvidence(arg) != 0 and !try self.matchType(owner, source, resolved.unit, parameter.ty, self.valueEvidence(arg), &callee.mappings, &callee.row_mappings)) return self.failNode(owner, source, .unsupported);
                if (arguments.len == parameters.len) {
                    const full = try self.projectType(resolved.unit, body.root, self.units[resolved.unit].binding(resolved.binding).ty, callee.mappings.items, callee.row_mappings.items);
                    // A partial aggregate can leave the full arrow unresolved
                    // while its result or invocation row is already selected.
                    // Retain those exact facts when entering the named body.
                    if (full == 0) return self.invokeNamedWithSeeds(resolved, arguments, owner, source, full, head, callee.mappings.items, callee.row_mappings.items);
                    return self.invokeNamed(resolved, arguments, owner, source, full, head);
                }
                var partial = closure;
                partial.applied += 1;
                partial.mappings = try self.captureMappings(owner, source, callee.mappings.items);
                partial.row_mappings = try self.captureRowMappings(owner, source, callee.row_mappings.items);
                return .{ .value = try self.makeClosure(owner, source, partial, arguments) };
            },
        }
    }
    fn call(self: *Session, owner: usize, id: core.Id, caller: *Frame) Error!Flow {
        const invocation = self.units[owner].call(id);
        if (self.closed_constructor) {
            const resolved = try self.external(try self.target(owner, invocation.target));
            const module = &self.units[resolved.unit];
            const body = module.body(resolved.binding) orelse return self.failNode(owner, id, .stage_unavailable);
            const parameters = module.bodyParameters(body);
            if (!body.is_function or body.runtime or parameters.len != invocation.arguments.len) return self.failNode(owner, id, .stage_unavailable);
            var callee: Frame = .{};
            defer callee.deinit(self.allocator);
            for (parameters, invocation.arguments) |parameter, argument| {
                const value_ = try self.expression(owner, argument, caller);
                if (value_ != .value) return self.failNode(owner, id, .stage_unavailable);
                if (parameter.binding != 0) try callee.values.put(self.allocator, parameter.binding, value_.value);
            }
            try self.enterCall(owner, id);
            defer self.call_depth -= 1;
            const value_ = try self.expression(resolved.unit, body.root, &callee);
            if (value_ != .value) return self.failNode(owner, id, .stage_unavailable);
            return value_;
        }
        const caller_type = try self.projectType(owner, id, invocation.callee_type, caller.mappings.items, caller.row_mappings.items);
        const selected = try self.selectTemplateSelection(owner, id, invocation.target, caller_type);
        const actual = selected.signature;
        const selected_target = selected.target;
        if (!std.meta.eql(selected_target, invocation.target)) try self.prepare(selected_target);
        const resolved = try self.external(try self.target(owner, selected_target));
        const module = &self.units[resolved.unit];
        const body = module.body(resolved.binding) orelse return self.failNode(owner, id, .unsupported);
        if (module.binding(resolved.binding).kind != .global) return self.failNode(owner, id, .unsupported);
        if (body.runtime) {
            // A direct named call evaluates its first argument before entering
            // the guarded RuntimeInit body. Later curried arguments cannot run.
            if (body.is_function and invocation.arguments.len != 0) {
                const evaluated = try self.expression(owner, invocation.arguments[0], caller);
                if (evaluated != .value) return evaluated;
            }
            return self.fail(resolved.unit, .{ .start = 0, .end = 0 }, .const_runtime_dependency);
        }
        if (body.is_function and actual != 0) {
            var preflight: Frame = .{ .providers = caller.providers };
            defer preflight.deinit(self.allocator);
            if (!try self.matchType(owner, id, resolved.unit, module.binding(resolved.binding).ty, actual, &preflight.mappings, &preflight.row_mappings)) return self.failNode(owner, id, .type_mismatch);
            try self.validateBody(resolved.unit, body, &preflight);
        }
        const parameters = module.bodyParameters(body);
        var consumed: usize = 0;
        var outcome: Flow = undefined;
        if (body.is_function) {
            consumed = @min(parameters.len, invocation.arguments.len);
            var storage_buffer: [256]u8 align(@alignOf(usize)) = undefined;
            var storage: std.heap.BufferFirstAllocator = .init(&storage_buffer, self.allocator);
            const scratch = storage.allocator();
            const arguments = try scratch.alloc(ValueId, consumed);
            defer scratch.free(arguments);
            for (invocation.arguments[0..consumed], 0..) |argument, index| {
                const evaluated = try self.expression(owner, argument, caller);
                if (evaluated != .value) return evaluated;
                arguments[index] = evaluated.value;
            }
            if (consumed < parameters.len) {
                var callee: Frame = .{ .providers = caller.providers };
                defer callee.deinit(self.allocator);
                if (actual != 0 and !try self.matchType(owner, id, resolved.unit, module.binding(resolved.binding).ty, actual, &callee.mappings, &callee.row_mappings)) return self.failNode(owner, id, .unsupported);
                for (arguments, parameters[0..consumed]) |argument, parameter| if (self.valueEvidence(argument) != 0 and !try self.matchType(owner, id, resolved.unit, parameter.ty, self.valueEvidence(argument), &callee.mappings, &callee.row_mappings)) return self.failNode(owner, id, .unsupported);
                return .{ .value = try self.makeClosure(owner, id, .{ .origin = .named, .unit = self.unitId(resolved.unit), .identity = resolved.binding, .applied = @intCast(consumed), .mappings = try self.captureMappings(owner, id, callee.mappings.items), .row_mappings = try self.captureRowMappings(owner, id, callee.row_mappings.items) }, arguments) };
            }
            outcome = try self.invokeNamed(resolved, arguments, owner, id, actual, caller.providers);
        } else {
            outcome = .{ .value = try self.typedView(owner, id, try self.constant(resolved), actual) };
        }
        for (invocation.arguments[consumed..]) |argument| {
            if (outcome != .value) return outcome;
            const evaluated = try self.expression(owner, argument, caller);
            if (evaluated != .value) return evaluated;
            outcome = try self.applyValue(owner, id, outcome.value, evaluated.value, caller.providers);
        }
        return outcome;
    }
};

/// The region imports only frozen semantic graphs. Variables are scoped per
/// actual closure occurrence, so unrelated polymorphic producers cannot share
/// substitutions. Dense owned inference state disappears after publication.
const ClosureRegion = struct {
    const RegionError = Error || types.Error || type_evidence.Error;
    const Expected = union(enum) {
        semantic: type_evidence.Id,
        code: struct { view: code_expectation.View, id: code_expectation.Id },
    };
    const CollectionExit = struct {
        remove: ?Target = null,
        lexical_caller: ?u32 = null,
        lexical_scheme: types.Scheme = .{},
        demand: ?CompletedDemand = null,
    };
    const CollectionFrame = struct {
        scope: u32,
        body: core.Id,
        deferred_member: bool,
        started: bool = false,
        walk: body_recipe.Walk = .{},
        exit: CollectionExit = .{},
    };
    const Collector = struct {
        active: bool = false,
        frames: std.ArrayList(CollectionFrame) = .empty,
        fn clear(self: *Collector, allocator: Allocator) void {
            for (self.frames.items) |*frame| frame.walk.deinit(allocator);
            self.frames.clearRetainingCapacity();
        }
        fn deinit(self: *Collector, allocator: Allocator) void {
            self.clear(allocator);
            self.frames.deinit(allocator);
        }
    };
    const Source = struct { row_first: u32 = std.math.maxInt(u32), row_last: u32 = std.math.maxInt(u32), variable_first: u32 = std.math.maxInt(u32), variable_last: u32 = std.math.maxInt(u32), origin: ?SourceLocation = null, implementation_context: ?u32 = null, binding: core.BindingId = 0, value: ValueId, owner: usize, root: types.Id = 0, body: core.Id = 0, closed_rows: types.List = .{}, body_collected: bool = false, import_parent: ?u32 = null, import_binders: types.List = .{} };
    const Import = struct { scope: u32, ty: types.Id };
    const RowImport = struct { scope: u32, row: types.Effects.Id };
    const LabelImport = struct { scope: u32, label: types.Effects.Label };
    const RowVariable = struct { scope: u32, variable: u32 };
    const ImportedRowVariable = struct { source: RowVariable, region: types.Effects.Id, next: u32 = std.math.maxInt(u32) };
    const RowParameter = struct { owner: usize, parameter: u32 };
    const CompletedDemand = struct { scope: u32, node: core.Id, body: core.Id, root: types.Id };
    const Variable = struct { source: Import, region: types.Id, next: u32 = std.math.maxInt(u32) };
    const Edge = struct { parent: u32, child: u32, slot: u32, formal: types.Id };
    const DataAlias = struct { instance: types.Id, principal: types.Id, solved: bool = false };
    const CallKey = struct { owner: usize, binding: core.BindingId, evidence: type_evidence.Id, caller: u32 = 0 };
    const SchemeInstance = struct { target: Target, public: type_evidence.Id, deferred_member: bool, open: u32 = 0, constant: bool = false, physical: u64 = 0, generation: u16 = 0 };
    const SchemeInputs = struct {
        keys: std.StringHashMapUnmanaged(u32) = .empty,
        parts: usize = 0,

        fn deinit(self: *SchemeInputs, allocator: Allocator) void {
            var keys = self.keys.keyIterator();
            while (keys.next()) |key| allocator.free(key.*);
            self.keys.deinit(allocator);
        }
    };
    const DefinitionKey = struct { owner: usize, node: core.Id };
    const CandidateKey = struct { caller: u32, node: core.Id, target: Target };
    const ConstraintKind = enum { binary, field, result_dispatch, resolver, resolver_shape, effect_operation, effect_handler, type_head, type_compare, physical_field, receiver, update, type_rep, effect_rep, invocation, collection, record_merge, call_summary, scheme_use, callback_use, type_eq, contract, implementation_method, task_receive };
    const Constraint = struct { use_node: core.Id = 0, origin: ?SourceLocation = null, lexical_key: u32 = 0, callback_slot: u32 = 0, callback_stage: u32 = 0, callback_interface: bool = false, target: Target = .{ .unit = 0, .binding = 0 }, arguments: core.List = .{}, explicit: bool = false, qualification_span: ?core.Span = null, qualification_unit: u32 = 0, diagnostic_name: []const u8 = &.{}, span: ?core.Span = null, row_carrier: bool = false, source_selection: bool = false, scope: u32, node: core.Id, left: types.Id, right: types.Id = 0, result: types.Id, signature: types.Id = 0, instance: types.NominalIdentity = .{ .unit = 0, .decl = 0 }, identity: types.NominalIdentity = .{ .unit = 0, .decl = 0 }, op: types.Operator = .none, member: u32 = 0, projection: u32 = 0, kind: ConstraintKind = .binary, writable: bool = false, deferred_member: bool = false, principal_only: bool = false, solved: bool = false };
    const Worklists = struct {
        constraints: @import("../check/solver_worklist.zig").Queue = .{},
        aliases: @import("../check/solver_worklist.zig").Queue = .{},
        observed_revision: u64 = 0,
        fn deinit(self: *Worklists, allocator: Allocator) void {
            self.constraints.deinit(allocator);
            self.aliases.deinit(allocator);
            self.* = undefined;
        }
    };
    const CallbackOriginUse = struct { owner: usize, span: core.Span, origin: SourceLocation, parameter: core.BindingId = 0 };
    const Scratch = struct {
        callback_origins: std.ArrayList(CallbackOriginUse) = .empty,
        projection_cache: @import("../reuse/projection_cache.zig").Cache = .{},
        evidence_import_cache: @import("evidence_import_cache.zig").Cache = .{},
        closed_source_cache: @import("closed_source_types.zig").Cache = .{},
        scheme_memberships: @import("scheme_membership.zig").Cache = .{},
        sources: std.ArrayList(Source) = .empty,
        imported: std.AutoHashMapUnmanaged(Import, types.Id) = .empty,
        imported_rows: std.AutoHashMapUnmanaged(RowImport, types.Effects.Id) = .empty,
        imported_labels: std.AutoHashMapUnmanaged(LabelImport, types.Effects.Label) = .empty,
        row_variables: std.AutoHashMapUnmanaged(RowVariable, types.Effects.Id) = .empty,
        row_variable_entries: std.ArrayList(ImportedRowVariable) = .empty,
        row_parameters: std.AutoHashMapUnmanaged(RowParameter, u32) = .empty,
        evidence_rows: std.AutoHashMapUnmanaged(u32, types.Effects.Id) = .empty,
        evidence_labels: std.AutoHashMapUnmanaged(u32, types.Effects.Label) = .empty,
        variables: std.ArrayList(Variable) = .empty,
        edges: std.ArrayList(Edge) = .empty,
        constraints: std.ArrayList(Constraint) = .empty,
        worklists: ?*Worklists = null,
        selected_targets: std.ArrayList(core.BindingRef) = .empty,
        summary_arguments: std.ArrayList(core.Id) = .empty,
        data_aliases: std.ArrayList(DataAlias) = .empty,
        frozen: std.AutoHashMapUnmanaged(u32, ValueId) = .empty,
        value_scopes: std.AutoHashMapUnmanaged(ValueId, u32) = .empty,
        call_instances: std.AutoHashMapUnmanaged(CallKey, u32) = .empty,
        candidate_instances: std.AutoHashMapUnmanaged(CandidateKey, u32) = .empty,
        unresolved_calls: std.AutoHashMapUnmanaged(Target, u32) = .empty,
        target_scopes: std.AutoHashMapUnmanaged(Target, u32) = .empty,
        components: scope_components.Graph = .{},
        source_functions: std.ArrayList(types.Id) = .empty,
        completed_demands: std.ArrayList(CompletedDemand) = .empty,
        witness_inputs: std.AutoHashMapUnmanaged(types.Id, types.Id) = .empty,
        principal_references: std.ArrayList(Target) = .empty,
        principal_actions: std.ArrayList(PrincipalGraph.Action) = .empty,
        /// Region-local scheduling shares a header's outstanding work.
        /// Its predicates remain required; this is never a published proof.
        scheme_instances: std.AutoHashMapUnmanaged(SchemeInstance, void) = .empty,
        scheme_inputs: SchemeInputs = .{},

        pub fn deinit(self: *Scratch, allocator: Allocator) void {
            if (self.worklists) |work| {
                work.deinit(allocator);
                allocator.destroy(work);
            }
            inline for (@typeInfo(Scratch).@"struct".field_names) |field| {
                if (comptime !std.mem.eql(u8, field, "worklists")) @field(self, field).deinit(allocator);
            }
            self.* = undefined;
        }
    };
    inference_stage: Session.InferenceStage = .general,
    reference_scan: bool = false,
    work_revision: u64 = 0,
    component_work: usize = 0,
    collector: Collector = .{},
    profile_principal: bool = false,
    profile_rejected: u16 = 0,
    profile_input_calls: usize = 0,
    profile_recorded_inputs: bool = false,
    profile_output_types: usize = 0,
    profile_output_rows: usize = 0,
    session: *Session,
    current_origin: ?SourceLocation = null,
    current_implementation_context: ?u32 = null,
    current_use: core.Id = 0,
    scratch: Scratch = .{},
    scratch_allocator: Allocator,
    timing: ?@import("../backend/backend_timing.zig").Work.Scope = null,
    solver: types.Store,
    projection_scopes: std.AutoHashMapUnmanaged(types.Id, u32) = .empty,
    normalization_memo: std.AutoHashMapUnmanaged(NormalizationKey, void) = .empty,
    associated_observed: usize = 0,
    arena: *region_arena.Arena,
    retain_selected: bool = false,
    startup_coverage_complete: bool = true,
    include_callables: bool = false,
    rank_evidence_frames: std.ArrayList([]const types.Id) = .empty,
    source_interface: bool = false,
    building_principal: bool = false,
    partial_principal: bool = false,
    unkeyed_capture_inputs: bool = false,
    principal_only_used: bool = false,
    speculative_source_entry: bool = false,
    source_selection_failed: bool = false,
    complete_demand_bodies: bool = false,
    source_entry: ?Target = null,
    // A generic nested lambda selects its members in its own concrete code
    // instance. Its enclosing proof still gathers mandatory effect equations.
    defer_members: bool = false,
    summary_job: bool = false,
    lexical_summary_job: u32 = 0,
    result_summary_job: bool = false,
    principal_result_job: bool = false,
    code_expectation_remaining: usize = 0,
    code_projection: ?CodeProjection = null,
    profile_caller: *const @import("../backend/backend_timing.zig").RegionCaller = &.{},
    importing_evidence: bool = false,

    const NormalizationKey = struct { root: types.Id, types: u64, rows: u64 };

    fn init(session: *Session) types.Error!ClosureRegion {
        return initAt(session, @src());
    }
    fn initAt(session: *Session, comptime caller: std.lang.SourceLocation) types.Error!ClosureRegion {
        return initWithSolverAllocatorAt(session, null, caller);
    }
    fn initWithSolverAllocator(session: *Session, solver_allocator: ?Allocator) types.Error!ClosureRegion {
        return initWithSolverAllocatorAt(session, solver_allocator, @src());
    }
    fn initWithSolverAllocatorAt(session: *Session, solver_allocator: ?Allocator, comptime caller: std.lang.SourceLocation) types.Error!ClosureRegion {
        session.observeConstantInference();
        const timing = if (session.timing) |work| work.enter(.inference) else null;
        errdefer if (timing) |scope| scope.deinit();
        const arena = try session.regions.region_arena_pool.take(session.allocator);
        errdefer session.regions.region_arena_pool.give(arena);
        const allocator = arena.scratchAllocator();
        var region: ClosureRegion = .{ .session = session, .current_origin = session.specialization_origin, .timing = timing, .solver = try types.Store.initWithOptions(solver_allocator orelse arena.solverAllocator(), .{ .closed_graphs = true }), .scratch_allocator = allocator, .arena = arena };
        region.scratch.projection_cache.allocator = allocator;
        region.inference_stage = session.inference_stage;
        region.profile_caller = comptime &.{ .function = caller.fn_name, .line = caller.line };
        if (session.inquiry_regions == 0 and session.semantic_job_budget == null) {
            session.summary_transitions = 0;
            session.summary_exhausted = false;
        }
        session.inquiry_regions += 1;
        return region;
    }
    fn deinit(self: *ClosureRegion) void {
        const scopes = self.scratch.sources.items.len;
        const nodes = self.solver.nodes.items.len;
        self.rank_evidence_frames.deinit(self.scratch_allocator);
        self.projection_scopes.deinit(self.session.allocator);
        self.normalization_memo.deinit(self.session.allocator);
        std.debug.assert(self.session.inquiry_regions != 0);
        self.session.inquiry_regions -= 1;
        defer if (self.timing) |scope| scope.deinit();
        const counters = &self.session.counters;
        counters.inference_regions += 1;
        switch (self.inference_stage) {
            inline else => |stage| {
                @field(counters, "inference_" ++ @tagName(stage) ++ "_regions") += 1;
                @field(counters, "inference_" ++ @tagName(stage) ++ "_nodes") += nodes;
            },
        }
        counters.region_scopes += self.scratch.sources.items.len;
        counters.max_region_scopes = @max(counters.max_region_scopes, self.scratch.sources.items.len);
        // Arena pooling retains backing memory, never the solver. This region
        // owns a fresh Store and contributes its counters exactly once.
        counters.occurs_steps += self.solver.occurs_steps;
        if (self.scratch.worklists) |work| {
            inline for (.{ "subscriber_visits", "retained_watches", "refreshed_watches", "ready_word_scans" }) |field| @field(counters, "worklist_" ++ field) += @field(work.constraints, field) + @field(work.aliases, field);
        }
        counters.normalization.merge(self.solver.normalization);
        if (self.timing) |scope| if (self.scratch.sources.items.len != 0 and scope.owner.clock.io != null) {
            const elapsed = scope.elapsedUs();
            if (elapsed >= 1000) {
                const source = self.scratch.sources.items[0];
                const module = &self.session.units[source.owner];
                const binding = if (source.binding != 0) source.binding else for (module.bodies[1..]) |body| {
                    if (body.root == source.body) break body.binding;
                } else 0;
                const name = if (self.session.diagnostic_context.identity) |identity| identity.owner(self.session.unitId(source.owner)) orelse "" else "";
                scope.owner.region(.{ .unit = self.session.unitId(source.owner), .binding = binding, .body = source.body, .offset = if (binding != 0) module.sourceNamePoint(binding) else if (source.body != 0) module.span(source.body).start else 0, .scopes = self.scratch.sources.items.len, .nodes = self.solver.nodes.items.len, .us = elapsed, .principal = self.profile_principal, .rejected = self.profile_rejected, .input_calls = self.profile_input_calls, .recorded_inputs = self.profile_recorded_inputs, .output_types = self.profile_output_types, .output_rows = self.profile_output_rows }, name);
            }
        };
        if (self.session.refinement_observation) |observation| observation.observe(self);
        self.collector.deinit(self.session.allocator);
        self.solver.deinit();
        self.scratch.deinit(self.scratch_allocator);
        counters.solver_requested_bytes += self.arena.solver_meter.counts.allocated_bytes;
        counters.solver_allocations += self.arena.solver_meter.counts.allocations;
        counters.scratch_requested_bytes += self.arena.scratch_meter.counts.allocated_bytes;
        counters.scratch_allocations += self.arena.scratch_meter.counts.allocations;
        counters.max_solver_live_bytes = @max(counters.max_solver_live_bytes, self.arena.solver_meter.counts.peak_bytes);
        counters.max_scratch_live_bytes = @max(counters.max_scratch_live_bytes, self.arena.scratch_meter.counts.peak_bytes);
        if (self.timing) |scope| scope.owner.region_callers.add(.{
            .caller = self.profile_caller,
            .stage = self.inference_stage,
            .regions = 1,
            .inclusive_us = scope.elapsedUs(),
            .scopes = scopes,
            .nodes = nodes,
            .solver_bytes = self.arena.solver_meter.counts.allocated_bytes,
            .scratch_bytes = self.arena.scratch_meter.counts.allocated_bytes,
            .solver_allocations = self.arena.solver_meter.counts.allocations,
            .scratch_allocations = self.arena.scratch_meter.counts.allocations,
        });
        self.session.regions.region_arena_pool.give(self.arena);
        self.scratch = undefined;
    }
    fn callbackUseOrigin(self: *ClosureRegion, owner: usize, id: core.Id) ?SourceLocation {
        if (id == 0) return null;
        const module = &self.session.units[owner];
        const use_span = module.span(id);
        const node = module.node(id);
        for (self.scratch.callback_origins.items) |callback| {
            if (callback.owner != owner or callback.span.start > use_span.start or callback.span.end < use_span.end) continue;
            if (node.tag == .call) {
                for (module.children(id)) |argument| if (parameterOperand(module, argument, callback.parameter, 0)) return callback.origin;
            } else switch (node.tag) {
                .associated, .scalar => if (parameterOperand(module, node.a, callback.parameter, 0) or parameterOperand(module, node.b, callback.parameter, 0)) return callback.origin,
                .project => if (parameterOperand(module, node.a, callback.parameter, 0)) return callback.origin,
                else => {},
            }
        }
        return null;
    }
    fn parameterOperand(module: *const core.Module, id: core.Id, binding: core.BindingId, depth: usize) bool {
        if (id == 0 or depth >= 256) return false;
        const node = module.node(id);
        if (node.tag == .reference) {
            const reference = module.reference(id);
            if (reference.unit != 0 and reference.unit != module.unit) return false;
            if (reference.binding == binding) return true;
            const source = module.binding(reference.binding);
            if (source.kind == .local and source.initializer != 0) return parameterOperand(module, source.initializer, binding, depth + 1);
        }
        if (node.tag == .project) return parameterOperand(module, node.a, binding, depth + 1);
        return false;
    }
    fn failDispatchConstraint(self: *ClosureRegion, constraint: Constraint, code: Code, record: DispatchRecord) Error {
        const fresh = self.session.diagnostic == null;
        const result = self.failConstraint(constraint, code);
        if (fresh) if (self.session.diagnostic) |*diagnostic| {
            var explained = record;
            self.session.dispatchContexts(self.scratch.sources.items[constraint.scope].owner, constraint.node, self.current_origin, &explained);
            diagnostic.dispatch = explained;
        };
        return result;
    }
    fn failConstraint(self: *ClosureRegion, constraint: Constraint, code: Code) Error {
        const source = self.scratch.sources.items[constraint.scope];
        const owner = source.owner;
        const module = &self.session.units[owner];
        var dependent = false;
        if (constraint.span) |span| {
            for (module.obligations) |obligation| if (std.meta.eql(span, obligation.span)) {
                dependent = obligationDependent(&module.types, obligation);
                break;
            };
        } else if (constraint.node != 0) {
            const node = module.node(constraint.node);
            switch (node.tag) {
                .associated, .scalar => dependent = callerDependent(&module.types, module.typeOf(node.a), 0) or callerDependent(&module.types, module.typeOf(node.b), 0),
                .project => dependent = callerDependent(&module.types, module.typeOf(node.a), 0),
                .result_associated => dependent = callerDependent(&module.types, node.ty, 0),
                else => {},
            }
        }
        var use_origin = constraint.origin orelse source.origin;
        if (self.callbackUseOrigin(owner, constraint.node)) |callback_origin| {
            dependent = true;
            use_origin = callback_origin;
        }
        defer if (dependent) self.session.anchorSpecialization(use_origin);
        if (code == .missing_field and constraint.explicit) if (constraint.qualification_span) |qualification| {
            const origin = if (constraint.qualification_unit == 0) owner else self.session.findUnit(constraint.qualification_unit, null) orelse owner;
            return self.session.fail(origin, .{ .start = qualification.start, .end = qualification.start }, code);
        };
        if (code == .ambiguous_qualified or code == .effect_mismatch) if (constraint.qualification_span) |span| {
            const origin = if (constraint.qualification_unit == 0) owner else self.session.findUnit(constraint.qualification_unit, null) orelse owner;
            return self.session.fail(origin, span, code);
        };
        return if (constraint.span) |span| self.session.fail(owner, span, code) else self.session.failNode(owner, constraint.node, code);
    }
    fn importScheme(self: *ClosureRegion, scope: u32, scheme: types.Scheme, source: core.Id) RegionError!void {
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        for (module.obligations[scheme.obligations.start..][0..scheme.obligations.len]) |obligation| {
            if (obligation.kind == .callee_use) {
                const target_ = try self.schemeTarget(self.scratch.sources.items[scope].owner, obligation.identity);
                if (self.session.units[target_.unit].binding(target_.binding).has_explicit) {
                    const index = self.scratch.constraints.items.len;
                    try self.appendConstraint(.{ .scope = scope, .node = source, .span = obligation.span, .kind = .scheme_use, .target = target_, .left = try self.importType(scope, obligation.ty, 0), .result = 0 });
                    if (!self.building_principal) _ = try self.solveSchemeUse(index);
                }
                continue;
            }
            if (!obligation.explicit) continue;
            const kind: ConstraintKind = switch (obligation.kind) {
                .dispatch => .binary,
                .result_dispatch => .result_dispatch,
                .field => .physical_field,
                .receiver => .receiver,
                .update => .update,
                .record_merge => .record_merge,
                .effect_operation => .effect_operation,
                .type_eq => .type_eq,
                .contract => .contract,
                .type_rep => .type_rep,
                .effect_rep => .effect_rep,
                else => return error.UnresolvedType,
            };
            try self.appendConstraint(.{
                .scope = scope,
                .node = source,
                .span = obligation.span,
                .explicit = true,
                .qualification_span = obligation.qualification_span,
                .qualification_unit = obligation.qualification_unit,
                .diagnostic_name = module.name(obligation.diagnostic_name),
                .kind = kind,
                .left = try self.importType(scope, obligation.ty, 0),
                .right = if (obligation.other == 0) 0 else try self.importType(scope, obligation.other, 0),
                .result = if (obligation.result == 0) 0 else try self.importType(scope, obligation.result, 0),
                .signature = if (obligation.signature == 0) 0 else try self.importType(scope, obligation.signature, 0),
                .member = obligation.name,
                .op = obligation.operator,
                .identity = .{ .unit = if (obligation.identity.unit == 0) self.session.unitId(self.scratch.sources.items[scope].owner) else obligation.identity.unit, .decl = obligation.identity.decl },
                .row_carrier = obligation.kind == .dispatch or obligation.kind == .result_dispatch or obligation.kind == .receiver or obligation.kind == .update,
            });
        }
    }
    fn seed(self: *ClosureRegion, scope: u32, mappings: []const type_evidence.Mapping) RegionError!void {
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        for (mappings) |mapping| {
            if (mapping.variable == 0 or mapping.variable >= module.types.nodes.len) return error.UnresolvedType;
            try self.unify(try self.importType(scope, mapping.variable, 0), try self.importEvidence(mapping.evidence, 0));
        }
    }
    fn exportMappings(self: *ClosureRegion, scope: u32) RegionError![]type_evidence.Mapping {
        var scratch_buffer: [512]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.session.allocator);
        const temporary = scratch.allocator();
        var mappings: std.ArrayList(type_evidence.Mapping) = .empty;
        defer mappings.deinit(temporary);
        for (self.scratch.variables.items) |variable| if (variable.source.scope == scope) {
            const actual = try self.project(variable.region);
            if (actual != 0) try mappings.append(temporary, .{ .variable = variable.source.ty, .evidence = actual });
        };
        return self.session.allocator.dupe(type_evidence.Mapping, mappings.items);
    }
    fn seedRows(self: *ClosureRegion, scope: u32, mappings: []const type_evidence.RowMapping) RegionError!void {
        for (mappings) |mapping| try self.solver.unifyEffects(try self.importRowVariable(scope, mapping.variable), try self.importEvidenceRow(mapping.evidence, 0));
    }
    /// Only a recorded principal closing decision licenses an unresolved tail
    /// to become empty. Expected/captured rows are solved before this fallback;
    /// their existing labels and closed facts remain authoritative.
    fn closeCertificates(self: *ClosureRegion) RegionError!bool {
        var scratch_buffer: [512]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.session.allocator);
        const temporary = scratch.allocator();
        var certified: std.AutoHashMapUnmanaged(RowVariable, void) = .empty;
        defer certified.deinit(temporary);
        for (self.scratch.sources.items, 0..) |source, scope| {
            for (self.session.units[source.owner].types.list(source.closed_rows)) |variable|
                try certified.put(temporary, .{ .scope = @intCast(scope), .variable = variable }, {});
        }
        if (certified.count() == 0) return false;
        // A reusable pure producer can be admitted under an unresolved caller
        // ambient. Its certificate cannot close that caller's unrelated row.
        // Physical code-shape holes have no source identity and impose no such
        // semantic restriction, so their residuals may receive the certificate.
        var protected: std.AutoHashMapUnmanaged(u32, void) = .empty;
        defer protected.deinit(temporary);
        var imported = self.scratch.row_variables.iterator();
        while (imported.next()) |entry| {
            if (certified.contains(entry.key_ptr.*)) continue;
            const resolved = try self.solver.resolveEffects(entry.value_ptr.*, 0);
            const tail = self.solver.row(resolved).tail;
            if (tail == .variable) try protected.put(temporary, tail.variable, {});
        }
        var changed = false;
        for (self.scratch.sources.items, 0..) |source, scope| {
            const module = &self.session.units[source.owner];
            for (module.types.list(source.closed_rows)) |variable| {
                const row_variable = try self.importRowVariable(@intCast(scope), variable);
                const resolved = try self.solver.resolveEffects(row_variable, 0);
                const row = self.solver.row(resolved);
                if (row.tail != .variable or protected.contains(row.tail.variable)) continue;
                const closed = self.solver.effects.row(self.solver.rowLabels(resolved), .closed) catch |err| return types.effectError(err);
                try self.solver.unifyEffects(resolved, closed);
                changed = true;
            }
        }
        return changed;
    }
    fn exportSolved(self: *ClosureRegion, scope: u32) RegionError!SolvedEvidence {
        var scratch_buffer: [512]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.session.allocator);
        const temporary = scratch.allocator();
        const mappings = try self.exportMappings(scope);
        errdefer self.session.allocator.free(mappings);
        var rows: std.ArrayList(type_evidence.RowMapping) = .empty;
        defer rows.deinit(temporary);
        var variables = self.scratch.row_variables.iterator();
        while (variables.next()) |entry| {
            if (entry.key_ptr.scope != scope) continue;
            const resolved = try self.solver.resolveEffects(entry.value_ptr.*, 0);
            if (self.solver.row(resolved).tail != .closed) continue;
            const actual = self.session.storage.evidence.projectEffects(&self.solver, resolved, &.{}, &.{}) catch |err| switch (err) {
                error.UnresolvedType => continue,
                else => return err,
            };
            try rows.append(temporary, .{ .variable = entry.key_ptr.variable, .evidence = actual });
        }
        std.mem.sort(type_evidence.RowMapping, rows.items, {}, struct {
            fn less(_: void, left: type_evidence.RowMapping, right: type_evidence.RowMapping) bool {
                return left.variable < right.variable;
            }
        }.less);
        const selected = try self.session.allocator.dupe(core.BindingRef, self.scratch.selected_targets.items);
        errdefer self.session.allocator.free(selected);
        return .{ .types = mappings, .rows = try self.session.allocator.dupe(type_evidence.RowMapping, rows.items), .selected = selected };
    }
    fn selectedTarget(self: *ClosureRegion, target_: Target) RegionError!void {
        if (!self.retain_selected) return;
        const resolved = try self.session.external(target_);
        const reference: core.BindingRef = .{ .unit = self.session.unitId(resolved.unit), .binding = resolved.binding };
        for (self.scratch.selected_targets.items) |prior| if (std.meta.eql(prior, reference)) return;
        try self.scratch.selected_targets.append(self.scratch_allocator, reference);
    }
    fn sourceInterface(self: *ClosureRegion, target_: Target, body: *const core.Body) RegionError!SourceInterface {
        self.source_interface = true;
        self.partial_principal = true;
        self.source_entry = target_;
        self.include_callables = true;
        const entry_module = &self.session.units[target_.unit];
        // Initial checking already validated every declaration. A function
        // whose input/result cannot be a guest ABI candidate is not a demanded
        // specialization root. Residual member resolution can still retain its
        // complete closed interface; a failed member attempt retains no body
        // or header proof and the later export check reports the missing entry.
        self.speculative_source_entry = body.is_function and !sourceEntryCandidate(&entry_module.types, entry_module.binding(body.binding).ty) and self.session.diagnostic == null and self.session.owned_diagnostic_message.len == 0;
        const scope = try self.callableScope(target_);
        try self.scratch.unresolved_calls.put(self.scratch_allocator, target_, scope);
        try self.collect(scope, body.root);
        self.solveMode(true) catch |err| {
            if (!self.source_selection_failed) return err;
            // Solver mappings and instance/body facts belong to this disposable
            // region. Selection never finishes/publishes callable validation,
            // values, captures, readiness or completed suspension facts.
            self.session.diagnostic = null;
            self.session.allocator.free(self.session.owned_diagnostic_message);
            self.session.owned_diagnostic_message = &.{};
            return .{ .selected = false };
        };
        if (!body.is_function and try self.retainedComparison()) {
            // The original nongeneric-entry traversal reports an unresolved
            // witness at its source leaf. Keep that traversal authoritative.
            self.principal_only_used = true;
            return error.UnresolvedType;
        }
        if (!body.is_function) for (self.scratch.constraints.items) |constraint| {
            if (constraint.solved or constraint.kind != .type_compare) continue;
            const owner = self.scratch.sources.items[constraint.scope].owner;
            const point = self.session.units[owner].span(constraint.node).start;
            const result = self.session.fail(owner, .{ .start = point, .end = point }, .ambiguous_associated);
            if (self.session.diagnostic) |*diagnostic| diagnostic.detail = "cannot select @type.same until operand types can be inferred; annotate the exported parameter or call the generic function with concrete types";
            return result;
        };
        var pending: usize = 0;
        for (self.scratch.constraints.items) |constraint| if (!constraint.solved) {
            pending += 1;
        };
        if (pending != 0) {
            const head = self.solver.node(try self.solver.resolve(self.scratch.sources.items[scope].root, 0));
            const result_directed = for (self.scratch.constraints.items) |constraint| {
                if (!constraint.solved and constraint.kind == .result_dispatch) break true;
            } else false;
            // An unselected destination retains ordinary result-dispatch
            // diagnostics. Other unowned entry types must be rejected before
            // evaluating an initializer merely to discover its representation.
            return .{ .pending = pending, .generic = (head.tag == .variable and !result_directed) or try self.genericEntryInterface(scope) };
        }
        for (self.scratch.sources.items) |source| {
            const module = &self.session.units[source.owner];
            if (source.binding == 0 or source.binding >= module.bindings.len) continue;
            const binding = module.binding(source.binding);
            const own = if (module.body(source.binding)) |definition| definition.is_function else binding.initializer != 0 and module.node(binding.initializer).tag == .closure;
            if (own) try self.appendFunction(source.root);
        }
        var changed = true;
        while (changed) {
            changed = false;
            for (self.scratch.source_functions.items) |function| {
                const arrow = self.solver.node(try self.solver.resolve(function, 0));
                if (arrow.tag != .function or try self.project(arrow.a) == 0 or try self.project(arrow.b) == 0) continue;
                const row = try self.solver.resolveEffects(arrow.c, 0);
                if (self.solver.row(row).tail != .variable) continue;
                const closed = self.solver.effects.row(self.solver.rowLabels(row), .closed) catch |err| return types.effectError(err);
                try self.solver.unifyEffects(row, closed);
                changed = true;
            }
        }
        const evidence = try self.project(self.scratch.sources.items[scope].root);
        if (evidence != 0) return .{ .evidence = evidence };
        const head = self.solver.node(try self.solver.resolve(self.scratch.sources.items[scope].root, 0));
        return .{ .generic = head.tag == .variable or try self.genericEntryInterface(scope) };
    }
    fn sourceEntryDataCandidate(table: *const core.Types, id: types.Id) bool {
        return switch (table.node(id).tag) {
            .unit, .boolean, .u32, .f32, .variable => true,
            .array => switch (table.node(table.node(id).a).tag) {
                .u32, .f32, .variable => true,
                else => false,
            },
            else => false,
        };
    }
    fn sourceEntryCandidate(table: *const core.Types, id: types.Id) bool {
        const arrow = table.node(id);
        if (arrow.tag != .function or !sourceEntryDataCandidate(table, arrow.b)) return false;
        if (sourceEntryDataCandidate(table, arrow.a)) return true;
        const callback = table.node(arrow.a);
        // Candidate selection deliberately ignores rows: a supported caller
        // must still demand and validate every selected body/effect afterward.
        return callback.tag == .function and sourceEntryDataCandidate(table, callback.a) and sourceEntryDataCandidate(table, callback.b);
    }
    fn deferredSourceSelection(self: *const ClosureRegion, constraint: Constraint) bool {
        if (constraint.kind == .receiver) return true;
        if (constraint.kind != .field or constraint.writable) return false;
        const module = &self.session.units[self.scratch.sources.items[constraint.scope].owner];
        return module.projection(constraint.projection).field != 0 and module.projectionVariants(constraint.projection).len == 0;
    }
    fn sourceSelectionFailure(self: *ClosureRegion, constraint: Constraint, err: RegionError) RegionError {
        if (!self.speculative_source_entry or !(constraint.source_selection or self.deferredSourceSelection(constraint))) return err;
        const semantic = switch (err) {
            error.TypeMismatch, error.InfiniteType, error.EffectMismatch, error.InfiniteEffect => true,
            error.Declined => if (self.session.diagnostic) |diagnostic| switch (diagnostic.code) {
                .type_mismatch, .effect_mismatch, .infinite_effect, .missing_member, .ambiguous_member, .ambiguous_qualified => true,
                else => false,
            } else false,
            else => false,
        };
        if (semantic) self.source_selection_failed = true;
        return err;
    }
    fn solveFieldConstraint(self: *ClosureRegion, constraint: Constraint) RegionError!bool {
        const selected = self.fieldType(constraint) catch |err| return self.sourceSelectionFailure(constraint, err);
        const actual = selected orelse return false;
        if (constraint.kind == .receiver) self.unify(constraint.right, types.unit) catch |err| return self.sourceSelectionFailure(constraint, err);
        self.unify(constraint.result, actual) catch |err| return self.sourceSelectionFailure(constraint, err);
        return true;
    }
    fn bodyEvidence(self: *ClosureRegion, owner: usize, body: core.Id, root: types.Id, closed_rows: types.List, scheme: types.Scheme, expected: Expected, seeds: []const type_evidence.Mapping) RegionError![]type_evidence.Mapping {
        const solved = try self.bodyEvidenceFull(owner, body, root, closed_rows, scheme, expected, seeds, &.{});
        self.session.allocator.free(solved.rows);
        self.session.allocator.free(solved.selected);
        return solved.types;
    }
    fn covariantEvidence(self: *ClosureRegion, owner: usize, root: types.Id, expected: type_evidence.Id, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping) RegionError!SolvedEvidence {
        const scope = try self.typeScope(owner);
        const imported = try self.importType(scope, root, 0);
        try self.seed(scope, seeds);
        try self.seedRows(scope, row_seeds);
        const actual = try self.solver.resolve(imported, 0);
        try self.unify(try self.solver.openCovariant(actual), try self.importEvidence(expected, 0));
        return self.exportSolved(scope);
    }
    fn bodyEvidenceFull(self: *ClosureRegion, owner: usize, body: core.Id, root: types.Id, closed_rows: types.List, scheme: types.Scheme, expected: Expected, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping) RegionError!SolvedEvidence {
        return self.bodyEvidenceMode(owner, body, root, closed_rows, scheme, expected, seeds, row_seeds, false);
    }
    fn bodyEvidenceMode(self: *ClosureRegion, owner: usize, body: core.Id, root: types.Id, closed_rows: types.List, scheme: types.Scheme, expected: Expected, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping, allow_remaining: bool) RegionError!SolvedEvidence {
        self.include_callables = true;
        self.partial_principal = allow_remaining;
        const scope = try self.typeScope(owner);
        self.scratch.sources.items[scope].body = body;
        self.scratch.sources.items[scope].closed_rows = closed_rows;
        self.setSourceRoot(scope, try self.importImplementation(scope, root));
        try self.seed(scope, seeds);
        try self.seedRows(scope, row_seeds);
        try self.expectShape(self.scratch.sources.items[scope].root, expected);
        try self.importScheme(scope, scheme, body);
        try self.collect(scope, body);
        try self.solveMode(allow_remaining);
        // An optional prepass can retain only a completely solved proof. The
        // publication guard rejects remaining obligations and admits the same
        // closed first-order arrows as ordinary body evidence.
        try self.publishValidatedCalls();
        if (self.code_projection) |consumer| for (self.scratch.variables.items) |variable| {
            if (variable.source.scope != scope or try self.project(variable.region) != 0) continue;
            // An uninstantiated local result has no physical shape to publish.
            if (self.solver.node(self.solver.head(variable.region, 0)).tag == .projection) continue;
            try consumer.mapping(consumer.context, &self.solver, variable.source.ty, variable.region);
        };
        return self.exportSolved(scope);
    }
    fn closureEvidence(self: *ClosureRegion, owner: usize, closure: core.ClosureInfo, expected: Expected, seeds: []const type_evidence.Mapping) RegionError![]type_evidence.Mapping {
        const solved = try self.closureEvidenceFull(owner, closure, expected, seeds, &.{});
        self.session.allocator.free(solved.rows);
        return solved.types;
    }
    fn closureEvidenceFull(self: *ClosureRegion, owner: usize, closure: core.ClosureInfo, expected: Expected, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping) RegionError!SolvedEvidence {
        return self.closureEvidenceCaptures(owner, closure, expected, seeds, row_seeds, &.{}, null);
    }
    fn importRetainedCapture(self: *ClosureRegion, capture: RetainedCapture, depth: usize) RegionError!types.Id {
        if (capture.value != 0) {
            if (capture.value >= self.session.storage.values.items.len) return error.UnresolvedType;
            const scope = try self.addValue(capture.value, depth + 1);
            return self.scratch.sources.items[scope].root;
        }
        // A captured generic helper is not an invocation. Keep its source
        // signature and lexical semantic inputs; its concrete call uses the
        // ordinary per-use proof. No unselected source body is certified here.
        if (depth >= self.session.options.max_type_depth) return error.TypeLimit;
        const owner = self.session.findUnit(capture.unit, null) orelse return error.UnresolvedType;
        const module = &self.session.units[owner];
        if (capture.node == 0 or capture.node >= module.nodes.len) return error.UnresolvedType;
        const node = module.node(capture.node);
        const scope = try self.typeScope(owner);
        self.setSourceRoot(scope, try self.importType(scope, node.ty, 0));
        if (capture.mappings != 0) {
            if (capture.mappings >= self.session.storage.evidence.nodes.items.len) return error.UnresolvedType;
            const words = try self.session.allocator.dupe(type_evidence.Id, self.session.storage.evidence.children(capture.mappings));
            defer self.session.allocator.free(words);
            if (self.session.storage.evidence.node(capture.mappings).tag != .record or words.len % 2 != 0) return error.TypeMismatch;
            for (0..words.len / 2) |index| {
                if (words[index * 2] >= module.types.nodes.len or words[index * 2 + 1] >= self.session.storage.evidence.nodes.items.len) return error.UnresolvedType;
                try self.unify(try self.importType(scope, words[index * 2], 0), try self.importEvidence(words[index * 2 + 1], 0));
            }
        }
        try self.seedRows(scope, capture.rows);
        if (capture.signature_only) return self.scratch.sources.items[scope].root;
        const capture_list = if (node.tag == .closure or node.tag == .suspend_) module.closures[node.a].captures else core.List{};
        const captured = module.extra[capture_list.start..][0..capture_list.len];
        for (capture.values) |value| {
            if (value.binding == 0 or value.binding >= module.bindings.len or value.evidence >= self.session.storage.evidence.nodes.items.len or std.mem.findScalar(core.BindingId, captured, value.binding) == null) return error.UnresolvedType;
            try self.unify(try self.importType(scope, module.binding(value.binding).ty, 0), try self.importEvidence(value.evidence, 0));
        }
        for (capture.captures) |child| {
            if (child.binding == 0 or child.binding >= module.bindings.len or std.mem.findScalar(core.BindingId, captured, child.binding) == null) return error.UnresolvedType;
            const actual = try self.importRetainedCapture(child, depth + 1);
            try self.unify(try self.importType(scope, module.binding(child.binding).ty, 0), try self.solver.openCovariant(try self.solver.resolve(actual, 0)));
        }
        if (node.tag == .closure or node.tag == .suspend_) {
            const closure_ = module.closures[node.a];
            if (node.tag == .closure) {
                try self.alignClosure(scope, capture.node);
            } else {
                const demanded = self.solver.node(try self.solver.resolve(self.scratch.sources.items[scope].root, 0));
                if (demanded.tag != .demand) return error.TypeMismatch;
                try self.unify(demanded.a, try self.importType(scope, module.typeOf(closure_.body), 0));
                if (closure_.function_type != 0) try self.unify(try self.importType(scope, closure_.function_type, 0), try self.solver.functionWithEffects(types.unit, demanded.a, demanded.c));
            }
        } else if (node.tag != .reference and node.tag != .constructor_function and node.tag != .primitive_function) return error.UnresolvedType;
        const actual = self.scratch.sources.items[scope].root;
        return if (capture.computation) try self.solver.nominal(.{ .unit = std.math.maxInt(u32), .decl = 5 }, &.{actual}) else actual;
    }
    fn closureEvidenceCaptures(self: *ClosureRegion, owner: usize, closure: core.ClosureInfo, expected: Expected, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping, captures: []const RetainedCapture, projection: ?CodeProjection) RegionError!SolvedEvidence {
        self.include_callables = true;
        self.unkeyed_capture_inputs = captures.len != 0 or closure.captures.len != 0;
        const scope = try self.typeScope(owner);
        const module = &self.session.units[owner];
        self.scratch.sources.items[scope].body = closure.body;
        self.scratch.sources.items[scope].binding = closure.qualifier;
        self.scratch.sources.items[scope].closed_rows = closure.closed_rows;
        self.setSourceRoot(scope, if (closure.function_type != 0) try self.importImplementation(scope, closure.function_type) else try self.solver.function(try self.importType(scope, closure.parameter.ty, 0), try self.importType(scope, module.typeOf(closure.body), 0)));
        try self.seed(scope, seeds);
        try self.seedRows(scope, row_seeds);
        try self.expectShape(self.scratch.sources.items[scope].root, expected);
        for (captures) |capture| {
            if (capture.binding == 0 or capture.binding >= module.bindings.len) return error.UnresolvedType;
            if (std.mem.findScalar(core.BindingId, module.extra[closure.captures.start..][0..closure.captures.len], capture.binding) == null and capture.binding != closure.parameter.binding) return error.UnresolvedType;
            const actual = try self.importRetainedCapture(capture, 0);
            const declared = try self.importType(scope, module.binding(capture.binding).ty, 0);
            const shape = try self.solver.openCovariant(try self.solver.resolve(actual, 0));
            switch (expected) {
                .code => try self.captureShape(declared, shape),
                .semantic => try self.unify(declared, shape),
            }
        }
        if (closure.qualifier != 0) try self.importScheme(scope, module.binding(closure.qualifier).scheme, closure.body);
        try self.collect(scope, closure.body);
        try self.solve();
        try self.publishValidatedCalls();
        if (projection) |consumer| for (self.scratch.variables.items) |variable| {
            if (variable.source.scope != scope or try self.project(variable.region) != 0) continue;
            if (self.solver.node(self.solver.head(variable.region, 0)).tag == .projection) continue;
            try consumer.mapping(consumer.context, &self.solver, variable.source.ty, variable.region);
        };
        return self.exportSolved(scope);
    }
    // This first retention path only admits interfaces containing plain data.
    // Higher-order arguments, demands, providers and nominal payloads need a
    // richer evidence key. A complete prior region proves all imported source
    // bodies under their exact semantic arrow, including effect rows.
    fn firstOrderData(self: *ClosureRegion, evidence: type_evidence.Id, depth: usize) RegionError!bool {
        var memo: FirstOrderMemo = .empty;
        defer memo.deinit(self.scratch_allocator);
        if (!self.session.has_implementations) return self.firstOrderDataNode(evidence, depth, null);
        return self.firstOrderDataDepth(evidence, depth, &memo);
    }
    const FirstOrderKey = struct { root: type_evidence.Id, depth: usize };
    const FirstOrderMemo = std.AutoHashMapUnmanaged(FirstOrderKey, bool);
    fn firstOrderDataDepth(self: *ClosureRegion, evidence: type_evidence.Id, depth: usize, memo: ?*FirstOrderMemo) RegionError!bool {
        if (memo) |answers| {
            if (self.session.associated_remaining == 0) return error.TypeLimit;
            self.session.associated_remaining -= 1;
            const key: FirstOrderKey = .{ .root = evidence, .depth = depth };
            if (answers.get(key)) |known| return known;
            const result = try self.firstOrderDataNode(evidence, depth, memo);
            try answers.put(self.scratch_allocator, key, result);
            return result;
        }
        return self.firstOrderDataNode(evidence, depth, null);
    }
    fn firstOrderDataNode(self: *ClosureRegion, evidence: type_evidence.Id, depth: usize, memo: ?*FirstOrderMemo) RegionError!bool {
        if (depth >= self.session.options.max_type_depth or evidence == 0) return false;
        const value = self.session.storage.evidence.node(evidence);
        switch (value.tag) {
            .unit, .boolean, .u32, .f32, .never => return true,
            .array, .list, .cursor => return self.firstOrderDataDepth(value.a, depth + 1, memo),
            .nominal => {
                for (self.session.storage.evidence.children(evidence)) |argument| if (!try self.firstOrderDataDepth(argument, depth + 1, memo)) return false;
                return self.plainNominal(value.a, value.b, depth + 1);
            },
            .product => for (self.session.storage.evidence.children(evidence)) |child| {
                if (!try self.firstOrderDataDepth(child, depth + 1, memo)) return false;
            },
            .record => {
                const children = self.session.storage.evidence.children(evidence);
                for (0..children.len / 2) |index| {
                    if (!try self.firstOrderDataDepth(children[index * 2 + 1], depth + 1, memo)) return false;
                }
            },
            else => return false,
        }
        return true;
    }
    fn sourceData(self: *ClosureRegion, owner: usize, ty: types.Id, variables: types.List, depth: usize) RegionError!bool {
        if (depth >= self.session.options.max_type_depth or ty == 0) return false;
        const module = &self.session.units[owner];
        const value = module.types.node(ty);
        switch (value.tag) {
            .unit, .boolean, .u32, .f32, .never => return true,
            .variable => return std.mem.findScalar(types.Id, module.types.list(variables), ty) != null,
            .array, .list, .cursor => return self.sourceData(owner, value.a, variables, depth + 1),
            .product => for (module.types.list(.{ .start = value.a, .len = value.b })) |child| {
                if (!try self.sourceData(owner, child, variables, depth + 1)) return false;
            },
            .record => for (0..value.b) |index| {
                if (!try self.sourceData(owner, module.types.recordField(value, index).ty, variables, depth + 1)) return false;
            },
            .nominal => {
                for (module.types.nominalArguments(value)) |child| if (!try self.sourceData(owner, child, variables, depth + 1)) return false;
                return self.plainNominal(if (value.a == 0) self.session.unitId(owner) else value.a, value.b, depth + 1);
            },
            else => return false,
        }
        return true;
    }
    fn plainNominal(self: *ClosureRegion, unit_id: u32, decl: u32, depth: usize) RegionError!bool {
        if (depth >= self.session.options.max_type_depth) return false;
        const key = (@as(u64, unit_id) << 32) | decl;
        const plain_reads = self.session.principal_reads orelse self.session.principal_plain_reads;
        if (plain_reads) |reads| try reads.plainRead(self.session.allocator, key, self.session.specializations.plain_nominals.get(key));
        if (self.session.specializations.plain_nominals.get(key)) |known| {
            if (self.session.receipt_tape) |tape| try tape.plain_facts.append(self.session.allocator, .{ .key = key, .plain = known });
            return known;
        }
        const owner = self.session.findUnit(unit_id, null) orelse return false;
        if (self.session.receipt_tape) |tape| try tape.plain_facts.append(self.session.allocator, .{ .key = key, .plain = false, .present = false });
        const module = &self.session.units[owner];
        const nominal = for (module.nominals) |candidate| {
            if (candidate.identity.decl == decl and (if (candidate.identity.unit == 0) self.session.unitId(owner) else candidate.identity.unit) == unit_id) break candidate;
        } else return false;
        var plain = nominal.constructors.len != 0;
        for (module.extra[nominal.constructors.start..][0..nominal.constructors.len]) |constructor| {
            const payload = module.constructor(constructor).payload;
            if (payload != 0 and !try self.sourceData(owner, payload, nominal.variables, depth + 1)) {
                plain = false;
                break;
            }
        }
        if (self.session.receipt_tape) |tape| try tape.plain_facts.append(self.session.allocator, .{ .key = key, .plain = plain, .read = false });
        if (plain_reads) |reads| try reads.plainPublish(self.session.allocator, key, plain);
        try self.session.specializations.plain_nominals.put(self.session.allocator, key, plain);
        return plain;
    }
    fn firstOrderArrow(self: *ClosureRegion, evidence: type_evidence.Id) RegionError!bool {
        var current = evidence;
        var depth: usize = 0;
        while (current != 0) {
            if (depth >= self.session.options.max_type_depth) return false;
            const value = self.session.storage.evidence.node(current);
            if (value.tag != .function) return depth != 0 and try self.firstOrderData(current, depth);
            if (!try self.firstOrderData(value.a, depth + 1)) return false;
            current = value.b;
            depth += 1;
        }
        return false;
    }
    /// Complete callback interfaces are semantic inputs; executable identity
    /// and captures are checked by their value owner, never by this shape test.
    fn summaryValue(self: *ClosureRegion, evidence: type_evidence.Id, depth: usize) RegionError!bool {
        if (depth >= self.session.options.max_type_depth or evidence == 0) return false;
        const node = self.session.storage.evidence.node(evidence);
        if (node.tag != .function) return self.firstOrderData(evidence, depth);
        if (try self.firstOrderArrow(evidence)) return true;
        const Item = struct { id: type_evidence.Id, depth: usize };
        var pending: std.ArrayList(Item) = .empty;
        defer pending.deinit(self.scratch_allocator);
        var seen: std.AutoHashMapUnmanaged(type_evidence.Id, usize) = .empty;
        defer seen.deinit(self.scratch_allocator);
        try pending.append(self.scratch_allocator, .{ .id = evidence, .depth = depth });
        var edges: usize = 0;
        while (pending.pop()) |item| {
            if (item.depth >= self.session.options.max_type_depth or item.id == 0) return false;
            const value = self.session.storage.evidence.node(item.id);
            if (value.tag != .function) {
                if (!try self.firstOrderData(item.id, item.depth)) return false;
                continue;
            }
            if (seen.get(item.id)) |prior| if (prior >= item.depth) continue;
            if (seen.count() >= self.session.options.max_values or 2 > self.session.options.max_children -| edges) return false;
            try seen.put(self.scratch_allocator, item.id, item.depth);
            try pending.appendSlice(self.scratch_allocator, &.{ .{ .id = value.a, .depth = item.depth + 1 }, .{ .id = value.b, .depth = item.depth + 1 } });
            edges += 2;
        }
        return true;
    }
    fn potentialSummaryValue(self: *ClosureRegion, owner: usize, ty: types.Id, depth: usize) RegionError!bool {
        if (depth >= self.session.options.max_type_depth or ty == 0) return false;
        const module = &self.session.units[owner];
        if (module.types.node(ty).tag != .function) return self.potentialData(owner, ty, depth);
        const Item = struct { id: types.Id, depth: usize };
        var pending: std.ArrayList(Item) = .empty;
        defer pending.deinit(self.scratch_allocator);
        var seen: std.AutoHashMapUnmanaged(types.Id, usize) = .empty;
        defer seen.deinit(self.scratch_allocator);
        try pending.append(self.scratch_allocator, .{ .id = ty, .depth = depth });
        var edges: usize = 0;
        while (pending.pop()) |item| {
            if (item.depth >= self.session.options.max_type_depth or item.id == 0) return false;
            const node = module.types.node(item.id);
            if (node.tag != .function) {
                if (!try self.potentialData(owner, item.id, item.depth)) return false;
                continue;
            }
            if (module.types.row(node.c).tail == .parameter) return false;
            if (seen.get(item.id)) |prior| if (prior >= item.depth) continue;
            if (seen.count() >= self.session.options.max_values or 2 > self.session.options.max_children -| edges) return false;
            try seen.put(self.scratch_allocator, item.id, item.depth);
            try pending.appendSlice(self.scratch_allocator, &.{ .{ .id = node.a, .depth = item.depth + 1 }, .{ .id = node.b, .depth = item.depth + 1 } });
            edges += 2;
        }
        return true;
    }
    // This quick source test can only exclude a proof. Variables still need
    // the complete semantic-evidence check below before admission.
    fn potentialData(self: *ClosureRegion, owner: usize, ty: types.Id, depth: usize) RegionError!bool {
        if (depth >= self.session.options.max_type_depth or ty == 0) return false;
        const module = &self.session.units[owner];
        const value = module.types.node(ty);
        switch (value.tag) {
            .unit, .boolean, .u32, .f32, .never, .variable => return true,
            .array, .list, .cursor => return self.potentialData(owner, value.a, depth + 1),
            .product => for (module.types.list(.{ .start = value.a, .len = value.b })) |child| {
                if (!try self.potentialData(owner, child, depth + 1)) return false;
            },
            .record => for (0..value.b) |index| {
                if (!try self.potentialData(owner, module.types.recordField(value, index).ty, depth + 1)) return false;
            },
            .nominal => {
                for (module.types.nominalArguments(value)) |child| if (!try self.potentialData(owner, child, depth + 1)) return false;
                return self.plainNominal(if (value.a == 0) self.session.unitId(owner) else value.a, value.b, depth + 1);
            },
            else => return false,
        }
        return true;
    }
    fn potentialArrow(self: *ClosureRegion, owner: usize, ty: types.Id) RegionError!bool {
        const module = &self.session.units[owner];
        var current = ty;
        var depth: usize = 0;
        while (current != 0) {
            if (depth >= self.session.options.max_type_depth) return false;
            const value = module.types.node(current);
            if (value.tag != .function) return depth != 0 and try self.potentialData(owner, current, depth);
            if (!try self.potentialData(owner, value.a, depth + 1)) return false;
            current = value.b;
            depth += 1;
        }
        return false;
    }
    fn publishValidatedCalls(self: *ClosureRegion) RegionError!void {
        // A lexical result is certified by its complete capture key. It cannot
        // publish a capture-free proof for a source qualifier's global name.
        if (self.lexical_summary_job != 0) return;
        if (!self.session.options.reuse_validated_calls or !self.allConstraintsSolved()) return;
        for (self.scratch.sources.items) |source| try self.publishValidatedSource(source);
    }
    fn publishValidatedSource(self: *ClosureRegion, source: Source) RegionError!void {
        if (self.lexical_summary_job != 0) return;
        if (source.value != 0 or source.binding == 0 or source.root == 0) return;
        const module = &self.session.units[source.owner];
        const binding = module.binding(source.binding);
        if (binding.kind != .global or module.body(source.binding) == null) return;
        if (!try self.potentialArrow(source.owner, binding.ty)) return;
        const actual = try self.project(source.root);
        if (!try self.firstOrderArrow(actual)) return;
        if (self.session.principal_reads) |reads| try reads.callPublish(self.session.allocator, .{ .unit = self.session.unitId(source.owner), .binding = source.binding }, actual);
        if (self.session.receipt_tape) |tape| try tape.call_publications.append(self.session.allocator, .{ .unit = self.session.unitId(source.owner), .binding = source.binding, .evidence = actual, .present = true });
        const entry = try self.session.specializations.validated_calls.getOrPut(self.session.allocator, .{ .target = .{ .unit = source.owner, .binding = source.binding }, .evidence = actual });
        if (!entry.found_existing) self.session.proofs.proof_published += 1;
    }
    fn expectShape(self: *ClosureRegion, root: types.Id, expected: Expected) RegionError!void {
        switch (expected) {
            .semantic => |actual| if (actual != 0) try self.unify(root, try self.importEvidence(actual, 0)),
            .code => |actual| {
                self.code_expectation_remaining = self.session.options.max_values;
                var required = root;
                if (self.solver.has_usage_types) required = try self.codeUsageView(root, 0);
                try self.matchCodeShape(required, actual.view, actual.id, 0);
            },
        }
    }
    // A partial machine shape constrains an already-owned declaration. Its
    // holes never manufacture associated types or erase the declaration's goals.
    fn matchCodeShape(self: *ClosureRegion, root: types.Id, view: code_expectation.View, actual: code_expectation.Id, depth: usize) RegionError!void {
        if (depth >= self.session.options.max_type_depth or self.code_expectation_remaining == 0) return error.TypeLimit;
        self.code_expectation_remaining -= 1;
        if (actual == 0) return;
        if (actual >= view.nodes.len) return error.UnresolvedType;
        const shape = view.node(actual);
        const id = self.solver.head(root, 0);
        const declared = self.solver.node(id);
        const expected_tag: types.Tag = switch (shape.tag) {
            inline else => |tag| @field(types.Tag, @tagName(tag)),
        };
        if (declared.tag == expected_tag) switch (shape.tag) {
            .forall, .existential => {
                if (shape.b == 0 or shape.b > 128 or declared.c != shape.b or self.rank_evidence_frames.items.len == 128) return error.TypeMismatch;
                const binders = try self.scratch_allocator.dupe(types.Id, self.solver.list(.{ .start = declared.b, .len = declared.c }));
                defer self.scratch_allocator.free(binders);
                for (view.children(actual), binders, 0..) |formal, binder, ordinal| {
                    const leaf = view.node(formal);
                    const owned = self.solver.node(binder);
                    if (leaf.tag != .bound or leaf.a != ordinal or leaf.b != owned.b or leaf.c != 0) return error.TypeMismatch;
                }
                try self.rank_evidence_frames.append(self.scratch_allocator, binders);
                defer _ = self.rank_evidence_frames.pop();
                return self.matchCodeShape(declared.a, view, shape.a, depth + 1);
            },
            .function, .state_provider => {
                try self.matchCodeShape(declared.a, view, shape.a, depth + 1);
                try self.matchCodeShape(declared.b, view, shape.b, depth + 1);
                if (shape.tag == .state_provider) try self.matchCodeShape(declared.c, view, shape.c, depth + 1);
                return;
            },
            .usage => {
                if (declared.b != shape.b) return error.TypeMismatch;
                return self.matchCodeShape(declared.a, view, shape.a, depth + 1);
            },
            .array, .list, .cursor, .demand, .provider, .resolver => return self.matchCodeShape(declared.a, view, shape.a, depth + 1),
            .product, .nominal => {
                var children: []const types.Id = undefined;
                if (shape.tag == .product) children = self.solver.list(.{ .start = declared.a, .len = declared.b }) else {
                    if (declared.a != shape.a or declared.b != shape.b) return error.TypeMismatch;
                    children = self.solver.nominalArguments(declared);
                }
                const saved = try self.scratch_allocator.dupe(types.Id, children);
                defer self.scratch_allocator.free(saved);
                const values = view.children(actual);
                if (saved.len != values.len) return error.TypeMismatch;
                for (saved, values) |child, value| try self.matchCodeShape(child, view, value, depth + 1);
                return;
            },
            .record => {
                const fields = view.children(actual);
                if (fields.len != @as(usize, declared.b) * 2) return error.TypeMismatch;
                var by_name: std.AutoHashMapUnmanaged(u32, code_expectation.Id) = .empty;
                defer by_name.deinit(self.scratch_allocator);
                try by_name.ensureTotalCapacity(self.scratch_allocator, declared.b);
                for (0..declared.b) |ordinal| {
                    if (self.code_expectation_remaining == 0) return error.TypeLimit;
                    self.code_expectation_remaining -= 1;
                    const entry = try by_name.getOrPut(self.scratch_allocator, fields[ordinal * 2]);
                    if (entry.found_existing) return error.TypeMismatch;
                    entry.value_ptr.* = fields[ordinal * 2 + 1];
                }
                for (0..declared.b) |ordinal| {
                    if (self.code_expectation_remaining == 0) return error.TypeLimit;
                    self.code_expectation_remaining -= 1;
                    const field = self.solver.recordField(declared, ordinal);
                    const expected_field = by_name.get(field.name) orelse return error.TypeMismatch;
                    try self.matchCodeShape(field.ty, view, expected_field, depth + 1);
                }
                return;
            },
            else => {},
        };
        try self.unify(root, try self.importCodeExpectation(view, actual, depth + 1));
    }
    // Physical code keys never prove ownership. They constrain only the
    // representation beneath a separately checked, preserved usage contract.
    fn codeUsageView(self: *ClosureRegion, root: types.Id, depth: usize) RegionError!types.Id {
        if (depth >= 128) return error.TypeLimit;
        const id = self.solver.head(root, 0);
        const node = self.solver.node(id);
        switch (node.tag) {
            .usage => {
                const payload = try self.codeUsageView(node.a, depth + 1);
                if (node.b == @backingInt(types.UsageKind.unique) or node.b == @backingInt(types.UsageKind.shared)) return self.solver.usage(payload, @fromBackingInt(@intCast(node.b)), 0);
                return payload;
            },
            .function => return self.solver.functionWithEffects(try self.codeUsageView(node.a, depth + 1), try self.codeUsageView(node.b, depth + 1), node.c),
            .array, .list, .cursor => return self.solver.sequence(node.tag, try self.codeUsageView(node.a, depth + 1)),
            .product, .nominal => {
                const task_handle = @import("../check/task_types.zig").handle;
                if (node.tag == .nominal and node.a == task_handle.unit and node.b == task_handle.decl) {
                    // A handle's private payload is two scalar identifiers.
                    // Its region and result remain in the semantic graph;
                    // neither can be reconstructed from this physical key.
                    return self.solver.product(&.{ types.u32_type, types.u32_type });
                }
                const count = if (node.tag == .product) node.b else self.solver.nominalArguments(node).len;
                const values = try self.scratch_allocator.alloc(types.Id, count);
                defer self.scratch_allocator.free(values);
                for (values, 0..) |*value, index| {
                    const child = if (node.tag == .product) self.solver.extra.items[node.a + index] else self.solver.nominalArguments(node)[index];
                    value.* = try self.codeUsageView(child, depth + 1);
                }
                if (node.tag == .product) return self.solver.product(values);
                return self.solver.nominal(.{ .unit = node.a, .decl = node.b }, values);
            },
            .record => {
                const fields = try self.scratch_allocator.alloc(types.Field, node.b);
                defer self.scratch_allocator.free(fields);
                for (fields, 0..) |*field, index| {
                    const prior = self.solver.recordField(node, index);
                    field.* = .{ .name = prior.name, .ty = try self.codeUsageView(prior.ty, depth + 1) };
                }
                return self.solver.record(fields);
            },
            else => return root,
        }
    }
    fn importCodeExpectation(self: *ClosureRegion, view: code_expectation.View, actual: code_expectation.Id, depth: usize) RegionError!types.Id {
        if (depth >= self.session.options.max_type_depth or self.code_expectation_remaining == 0) return error.TypeLimit;
        self.code_expectation_remaining -= 1;
        if (actual == 0) return self.solver.fresh();
        if (actual >= view.nodes.len) return error.UnresolvedType;
        const node = view.node(actual);
        return switch (node.tag) {
            .projection => error.UnresolvedType,
            .forall, .existential => blk: {
                if (node.b == 0 or node.b > 128) return error.TypeLimit;
                var binders: [128]types.Id = undefined;
                for (view.children(actual), binders[0..node.b], 0..) |formal, *binder, ordinal| {
                    const leaf = view.node(formal);
                    if (leaf.tag != .bound or leaf.a != ordinal or leaf.b > 2 or leaf.c != 0) return error.UnresolvedType;
                    binder.* = try self.solver.boundType(@intCast(ordinal), leaf.b);
                }
                if (self.rank_evidence_frames.items.len == 128) return error.TypeLimit;
                try self.rank_evidence_frames.append(self.scratch_allocator, binders[0..node.b]);
                defer _ = self.rank_evidence_frames.pop();
                var tag: types.Tag = .existential;
                if (node.tag == .forall) tag = .forall;
                break :blk try self.solver.quantified(tag, try self.importCodeExpectation(view, node.a, depth + 1), binders[0..node.b]);
            },
            .bound => blk: {
                // A representation-only opened slot outside a quantifier is
                // a hole for inference, not published abstract authority.
                if (self.rank_evidence_frames.items.len == 0 and node.b == 0 and node.c == 0) break :blk self.solver.fresh();
                if (node.c >= self.rank_evidence_frames.items.len) return error.UnresolvedType;
                const binders = self.rank_evidence_frames.items[self.rank_evidence_frames.items.len - 1 - node.c];
                if (node.a >= binders.len or self.solver.node(binders[node.a]).b != node.b) return error.UnresolvedType;
                break :blk binders[node.a];
            },
            .absent => error.UnresolvedType,
            .usage => self.solver.usage(try self.importCodeExpectation(view, node.a, depth + 1), @fromBackingInt(@intCast(node.b)), 0),
            .scoped => error.UnresolvedType,
            .erased_proof => self.solver.proofKind(),
            .unit => types.unit,
            .boolean => types.boolean,
            .u32 => types.u32_type,
            .f32 => types.f32_type,
            .never => types.never,
            .function => self.solver.functionWithEffects(try self.importCodeExpectation(view, node.a, depth + 1), try self.importCodeExpectation(view, node.b, depth + 1), try self.solver.freshEffects()),
            .array, .list, .cursor => self.solver.sequence(switch (node.tag) {
                .list => .list,
                .cursor => .cursor,
                else => .array,
            }, try self.importCodeExpectation(view, node.a, depth + 1)),
            .demand => self.solver.demandWithEffects(try self.importCodeExpectation(view, node.a, depth + 1), try self.solver.freshEffects()),
            .provider => self.solver.provider(try self.importCodeExpectation(view, node.a, depth + 1), try self.solver.freshEffects()),
            .state_provider => self.solver.stateProvider(try self.importCodeExpectation(view, node.a, depth + 1), try self.importCodeExpectation(view, node.b, depth + 1), try self.importCodeExpectation(view, node.c, depth + 1)),
            .resolver => self.solver.resolver(try self.importCodeExpectation(view, node.a, depth + 1)),
            .type_constructor => self.solver.typeConstructor(.{ .unit = node.a, .decl = node.b }),
            .record => blk: {
                var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
                var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.scratch_allocator);
                const allocator = scratch.allocator();
                const children = view.children(actual);
                const fields = try allocator.alloc(types.Field, children.len / 2);
                defer allocator.free(fields);
                for (fields, 0..) |*field, index| field.* = .{ .name = children[index * 2], .ty = try self.importCodeExpectation(view, children[index * 2 + 1], depth + 1) };
                break :blk try self.solver.record(fields);
            },
            .product, .nominal => blk: {
                var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
                var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.scratch_allocator);
                const allocator = scratch.allocator();
                const children = view.children(actual);
                const values = try allocator.alloc(types.Id, children.len);
                defer allocator.free(values);
                for (children, values) |child, *value| value.* = try self.importCodeExpectation(view, child, depth + 1);
                break :blk if (node.tag == .nominal) try self.solver.nominal(.{ .unit = node.a, .decl = node.b }, values) else try self.solver.product(values);
            },
        };
    }
    fn importImplementation(self: *ClosureRegion, scope: u32, root: types.Id) RegionError!types.Id {
        const source = &self.session.units[self.scratch.sources.items[scope].owner].types;
        const body = source.withoutForall(root) catch return error.TypeLimit;
        const wrapper = source.node(body);
        if (wrapper.tag == .usage) {
            // A callable qualifier does not move its quantifier into the
            // implementation. Open the callback's own binders just as for an
            // unqualified rank-polymorphic function body.
            return self.solver.usage(try self.importImplementation(scope, wrapper.a), @fromBackingInt(@intCast(wrapper.b)), if (wrapper.c == 0) 0 else try self.importType(scope, wrapper.c, 0));
        }
        return self.importType(scope, body, 0);
    }
    fn importType(self: *ClosureRegion, scope: u32, ty: types.Id, depth: usize) RegionError!types.Id {
        if (depth >= self.session.options.max_type_depth or self.scratch.imported.count() >= self.session.options.max_values) return error.TypeLimit;
        const key: Import = .{ .scope = scope, .ty = ty };
        if (self.scratch.imported.get(key)) |existing| return existing;
        const owner = self.scratch.sources.items[scope].owner;
        const source = &self.session.units[owner].types;
        const node = source.node(ty);
        if (self.scratch.sources.items[scope].import_parent) |parent| {
            if (node.tag == .variable or node.tag == .bound) return self.importType(parent, ty, depth + 1);
        }
        const shared = ty > types.never and
            try self.session.specializations.closed_source_types.closed(self.session.allocator, self.session.units, owner, ty, 0);
        const closed_key = @import("closed_source_types.zig").Cache.key(owner, ty, depth);
        if (shared) {
            self.session.closed_source_imports += 1;
            if (self.scratch.closed_source_cache.activate(&self.solver, self.session.options.max_type_depth)) {
                if (self.scratch.closed_source_cache.answers.get(closed_key)) |existing| {
                    self.session.closed_source_reused += 1;
                    return existing;
                }
            }
        }
        const result = switch (node.tag) {
            .instance_version => try self.solver.instanceVersion(.{ .unit = node.a, .decl = node.b }, node.c),
            .bound => blk: {
                if (node.b == 0) break :blk try self.solver.fresh();
                if (node.b == 1 and node.c == 0) break :blk try self.solver.freshRowType();
                if (node.b != 2 or node.c >= self.session.units[owner].bindings.len) return error.UnresolvedType;
                if (node.c == 0) break :blk try self.solver.freshRegion();
                // Import's (source scope, type) key includes the source owner.
                // A fresh solver scope never conflates equal lexical IDs in
                // different modules or independently instantiated bodies.
                break :blk try self.solver.rigid(try self.solver.rigidScope(), node.a, 2);
            },
            .forall, .existential => blk: {
                // Bound imports belong only to this type expression. A later
                // visit to its executable callback body opens fresh inference
                // slots, rather than inheriting a free bound type from here.
                const inner = try self.typeScope(owner);
                self.scratch.sources.items[inner].import_parent = scope;
                self.scratch.sources.items[inner].import_binders = .{ .start = node.b, .len = node.c };
                self.scratch.sources.items[inner].closed_rows = self.scratch.sources.items[scope].closed_rows;
                const binders = try self.scratch_allocator.alloc(types.Id, node.c);
                defer self.scratch_allocator.free(binders);
                for (source.list(.{ .start = node.b, .len = node.c }), binders, 0..) |binder, *bound, ordinal| {
                    const leaf = source.node(binder);
                    if (leaf.tag != .bound or leaf.a != ordinal or leaf.b > 2 or leaf.c != 0) return error.UnresolvedType;
                    const binder_key: Import = .{ .scope = inner, .ty = binder };
                    if (self.scratch.imported.get(binder_key)) |existing| {
                        const imported = self.solver.node(existing);
                        if (imported.tag != .bound or imported.a != ordinal or imported.b != leaf.b) return error.UnresolvedType;
                        bound.* = existing;
                    } else {
                        bound.* = try self.solver.boundType(@intCast(ordinal), leaf.b);
                        try self.scratch.imported.put(self.scratch_allocator, binder_key, bound.*);
                    }
                }
                const body = try self.importType(inner, node.a, depth + 1);
                break :blk try self.solver.quantified(node.tag, body, binders);
            },
            .rigid => return error.UnresolvedType,
            .instance_selection => blk: {
                const choices = source.nominalArguments(node);
                if (choices.len != 2 and choices.len != 3) return error.UnresolvedType;
                // A declaration-owned invocation binder opens in this call's
                // inference region. Captured, already evaluated selections
                // retain their exact source-call versions below.
                if (choices.len == 3) for (self.session.units[owner].bindings) |binding| {
                    const words = source.list(binding.scheme.generative);
                    for (0..words.len / 2) |index| {
                        const selected = source.node(words[index * 2 + 1]);
                        if (selected.tag == .scoped and selected.b == 0 and selected.c == ty) break :blk try self.solver.fresh();
                    }
                };
                var imported: std.ArrayList(types.Id) = .empty;
                defer imported.deinit(self.scratch_allocator);
                for (choices) |choice| try imported.append(self.scratch_allocator, try self.importType(scope, choice, depth + 1));
                const owned: types.Id = try self.solver.instanceSelection(.{ .unit = node.a, .decl = node.b }, imported.items);
                break :blk owned;
            },
            .absent => return error.UnresolvedType,
            .erased_proof => try self.solver.proofKind(),
            .unit, .boolean, .u32, .f32, .never => ty,
            .variable => try self.solver.fresh(),
            .scoped => blk: {
                const descriptor = try self.importType(scope, node.a, depth + 1);
                var instance: types.NominalIdentity = .{ .unit = node.b, .decl = node.c };
                if (node.b == 0) {
                    const identity = try self.importType(scope, node.c, depth + 1);
                    instance.decl = identity;
                    if (self.code_projection) |projection| if (projection.instance) |lookup| if (lookup(projection.context, self.session.unitId(owner), node.c)) |actual| {
                        // The binder proves one value owner, shared by family
                        // capabilities and each differently shaped operation.
                        // Reusing it cannot equate those descriptors.
                        const bound = self.solver.node(try self.solver.resolve(identity, 0));
                        if (bound.tag == .variable) {
                            try self.unify(identity, try self.solver.scoped(descriptor, actual));
                        } else if (bound.tag == .instance_selection) {
                            if (!std.meta.eql(types.selectionAtom(&self.solver, .{ .unit = 0, .decl = identity }), actual)) return error.TypeMismatch;
                        } else if (bound.tag != .scoped or bound.b != actual.unit or bound.c != actual.decl) return error.TypeMismatch;
                        instance = actual;
                    };
                }
                break :blk try self.solver.scoped(descriptor, instance);
            },
            .function => try self.solver.functionWithEffects(try self.importType(scope, node.a, depth + 1), try self.importType(scope, node.b, depth + 1), try self.importRow(scope, node.c, depth + 1)),
            .usage => try self.solver.usage(try self.importType(scope, node.a, depth + 1), @fromBackingInt(@intCast(node.b)), if (node.c == 0) 0 else try self.importType(scope, node.c, depth + 1)),
            .array, .list, .cursor => try self.solver.sequence(node.tag, try self.importType(scope, node.a, depth + 1)),
            .demand => try self.solver.demandWithEffects(try self.importType(scope, node.a, depth + 1), try self.importRow(scope, node.c, depth + 1)),
            .provider => try self.solver.provider(try self.importType(scope, node.a, depth + 1), try self.importRow(scope, node.c, depth + 1)),
            .state_provider => try self.solver.stateProvider(try self.importType(scope, node.a, depth + 1), try self.importType(scope, node.b, depth + 1), try self.importType(scope, node.c, depth + 1)),
            .resolver => try self.solver.resolver(try self.importType(scope, node.a, depth + 1)),
            .type_constructor => try self.solver.typeConstructor(.{ .unit = node.a, .decl = node.b }),
            .record => blk: {
                var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
                var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.scratch_allocator);
                const allocator = scratch.allocator();
                const fields = try allocator.alloc(types.Field, node.b);
                defer allocator.free(fields);
                for (fields, 0..) |*imported, index| {
                    const field = source.recordField(node, index);
                    imported.* = .{ .name = field.name, .ty = try self.importType(scope, field.ty, depth + 1) };
                }
                break :blk try self.solver.record(fields);
            },
            .product, .nominal, .projection => blk: {
                const children = if (node.tag == .nominal or node.tag == .projection) source.nominalArguments(node) else source.list(.{ .start = node.a, .len = node.b });
                var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
                var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.scratch_allocator);
                const allocator = scratch.allocator();
                const values = try allocator.alloc(types.Id, children.len);
                defer allocator.free(values);
                for (children, values) |child, *value| value.* = try self.importType(scope, child, depth + 1);
                if (node.tag == .projection) break :blk try self.solver.projection(.{ .unit = node.a, .decl = node.b }, source.projectionMember(node), values);
                break :blk if (node.tag == .nominal) try self.solver.nominal(.{ .unit = node.a, .decl = node.b }, values) else try self.solver.product(values);
            },
        };
        if (shared and self.scratch.closed_source_cache.activate(&self.solver, self.session.options.max_type_depth)) {
            try self.scratch.closed_source_cache.answers.put(self.scratch_allocator, closed_key, result);
        } else try self.scratch.imported.put(self.scratch_allocator, key, result);
        // Lexical loan regions remain in the import map for exact semantic
        // checks. They are not type substitutions or physical code parameters.
        if (node.tag == .variable or (node.tag == .bound and node.b == 0) or node.tag == .projection) try self.appendVariable(.{ .source = key, .region = result });
        if (node.tag == .projection) try self.projection_scopes.put(self.session.allocator, result, scope);
        return result;
    }
    fn importLabel(self: *ClosureRegion, scope: u32, label: types.Effects.Label, depth: usize) RegionError!types.Effects.Label {
        if (depth >= self.session.options.max_type_depth) return error.TypeLimit;
        const key: LabelImport = .{ .scope = scope, .label = label };
        if (self.scratch.imported_labels.get(key)) |known| return known;
        const source = &self.session.units[self.scratch.sources.items[scope].owner].types;
        if (label == 0 or label >= source.operations.len) return error.UnresolvedType;
        var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.scratch_allocator);
        const allocator = scratch.allocator();
        const original = source.operationArguments(label);
        const arguments = try allocator.alloc(types.Id, original.len);
        defer allocator.free(arguments);
        for (original, arguments) |argument, *imported| imported.* = try self.importType(scope, argument, depth + 1);
        var instance = source.operation(label).instance;
        if (instance.unit == 0 and instance.decl != 0) instance.decl = try self.importType(scope, instance.decl, depth + 1);
        const result = try self.solver.internScopedOperation(source.operation(label).identity, instance, arguments);
        try self.scratch.imported_labels.put(self.scratch_allocator, key, result);
        return result;
    }
    fn importRow(self: *ClosureRegion, scope: u32, row: types.Effects.Id, depth: usize) RegionError!types.Effects.Id {
        if (row == 0) return 0;
        if (depth >= self.session.options.max_type_depth) return error.TypeLimit;
        const key: RowImport = .{ .scope = scope, .row = row };
        if (self.scratch.imported_rows.get(key)) |known| return known;
        const source = &self.session.units[self.scratch.sources.items[scope].owner].types;
        if (row >= source.effects.rows.len) return error.UnresolvedType;
        const original = source.row(row);
        var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.scratch_allocator);
        const allocator = scratch.allocator();
        const source_labels = source.rowLabels(row);
        const labels = try allocator.alloc(types.Effects.Label, source_labels.len);
        defer allocator.free(labels);
        for (source_labels, labels) |label, *imported| imported.* = try self.importLabel(scope, label, depth + 1);
        const tail: types.Effects.Tail = switch (original.tail) {
            .closed => .closed,
            .formal => |formal| self.solver.row(try self.importRowVariable(scope, try types.formalRowKey(formal))).tail,
            .variable => |variable| blk: {
                const fresh = try self.importRowVariable(scope, variable);
                break :blk self.solver.effects.node(fresh).tail;
            },
            .parameter => |parameter| blk: {
                const parameter_key: RowParameter = .{ .owner = self.scratch.sources.items[scope].owner, .parameter = parameter };
                const fresh = self.scratch.row_parameters.get(parameter_key) orelse fresh: {
                    if (self.scratch.row_parameters.count() >= std.math.maxInt(u32)) return error.TypeLimit;
                    const created: u32 = @intCast(self.scratch.row_parameters.count());
                    try self.scratch.row_parameters.put(self.scratch_allocator, parameter_key, created);
                    break :fresh created;
                };
                break :blk .{ .parameter = fresh };
            },
        };
        const result = self.solver.effects.row(labels, tail) catch |err| return types.effectError(err);
        try self.scratch.imported_rows.put(self.scratch_allocator, key, result);
        return result;
    }
    fn importRowVariable(self: *ClosureRegion, scope: u32, variable: u32) RegionError!types.Effects.Id {
        const owner = self.scratch.sources.items[scope].owner;
        const source = &self.session.units[owner].types;
        const formal = types.rowKeyFormal(variable);
        if (self.scratch.sources.items[scope].import_parent) |parent| {
            const owned = if (formal) |binder| std.mem.findScalar(types.Id, source.list(self.scratch.sources.items[scope].import_binders), binder) != null else false;
            if (!owned) return self.importRowVariable(parent, variable);
        }
        const key: RowVariable = .{ .scope = scope, .variable = variable };
        if (self.scratch.row_variables.get(key)) |known| return known;
        if (formal) |binder| {
            if (binder == 0 or binder >= source.nodes.len) return error.UnresolvedType;
            const leaf = source.node(binder);
            if (leaf.tag != .bound or leaf.b != 1 or leaf.c != 0) return error.UnresolvedType;
            var owners: usize = 0;
            for (source.nodes) |quantifier| {
                try self.solver.chargeProjection();
                if (quantifier.tag != .forall) continue;
                if (quantifier.b > source.extra.len or quantifier.c > source.extra.len - quantifier.b) return error.UnresolvedType;
                if (leaf.a < quantifier.c and source.extra[quantifier.b + leaf.a] == binder) owners += 1;
            }
            if (owners != 1) return error.UnresolvedType;
        } else if (variable >= source.effects.variable_count) return error.UnresolvedType;
        var fresh: types.Effects.Id = undefined;
        if (formal) |binder| fresh = try self.solver.rowType(try self.importType(scope, binder, 0)) else fresh = try self.solver.freshEffects();
        try self.scratch.row_variable_entries.ensureUnusedCapacity(self.scratch_allocator, 1);
        try self.scratch.row_variables.put(self.scratch_allocator, key, fresh);
        const index: u32 = @intCast(self.scratch.row_variable_entries.items.len);
        self.scratch.row_variable_entries.appendAssumeCapacity(.{ .source = key, .region = fresh });
        const owner_scope = &self.scratch.sources.items[scope];
        if (owner_scope.row_last != std.math.maxInt(u32)) self.scratch.row_variable_entries.items[owner_scope.row_last].next = index else owner_scope.row_first = index;
        owner_scope.row_last = index;
        return fresh;
    }
    fn importEvidence(self: *ClosureRegion, actual: type_evidence.Id, depth: usize) RegionError!types.Id {
        const nested = self.importing_evidence;
        const solver_before = self.arena.solver_meter.counts.allocated_bytes;
        const scratch_before = self.arena.scratch_meter.counts.allocated_bytes;
        self.importing_evidence = true;
        defer {
            self.importing_evidence = nested;
            if (!nested) {
                self.session.counters.evidence_import_solver_bytes += self.arena.solver_meter.counts.allocated_bytes - solver_before;
                self.session.counters.evidence_import_scratch_bytes += self.arena.scratch_meter.counts.allocated_bytes - scratch_before;
            }
        }
        if (depth >= self.session.options.max_type_depth) return error.TypeLimit;
        if (actual == 0) return error.UnresolvedType;
        if (actual <= types.never) return actual;
        self.session.evidence_import_requests += 1;
        if (self.rank_evidence_frames.items.len != 0) return self.importEvidenceGraph(actual, depth);
        self.prepareEvidenceImports();
        const memo = &self.scratch.evidence_import_cache;
        const key = memo.key(actual, depth);
        if (key) |id| if (memo.answers.get(id)) |known| {
            self.session.evidence_import_reused += 1;
            return known;
        };
        const result = try self.importEvidenceGraph(actual, depth);
        // Construction may synchronize the solver's physical effect clock.
        self.prepareEvidenceImports();
        if (key) |id| if (memo.key(actual, depth) != null) try memo.answers.put(self.scratch_allocator, id, result);
        return result;
    }
    fn prepareEvidenceImports(self: *ClosureRegion) void {
        if (self.scratch.evidence_import_cache.activate(&self.session.storage.evidence, &self.solver, self.solver.closed_generation, self.solver.effects.physical_epoch, self.session.options.max_type_depth)) {
            self.scratch.evidence_rows.clearRetainingCapacity();
            self.scratch.evidence_labels.clearRetainingCapacity();
        }
    }
    fn importEvidenceGraph(self: *ClosureRegion, actual: type_evidence.Id, depth: usize) RegionError!types.Id {
        const node = self.session.storage.evidence.node(actual);
        return switch (node.tag) {
            .forall, .existential => blk: {
                if (node.b == 0 or node.b > 128) return error.TypeLimit;
                var binders: [128]types.Id = undefined;
                for (self.session.storage.evidence.children(actual), binders[0..node.b], 0..) |formal, *binder, ordinal| {
                    const leaf = self.session.storage.evidence.node(formal);
                    if (leaf.tag != .bound or leaf.a != ordinal or leaf.b > 2 or leaf.c != 0) return error.UnresolvedType;
                    binder.* = try self.solver.boundType(@intCast(ordinal), leaf.b);
                }
                if (self.rank_evidence_frames.items.len == 128) return error.TypeLimit;
                try self.rank_evidence_frames.append(self.scratch_allocator, binders[0..node.b]);
                defer _ = self.rank_evidence_frames.pop();
                var tag: types.Tag = .existential;
                if (node.tag == .forall) tag = .forall;
                var goals: std.ArrayList(types.Obligation) = .empty;
                defer goals.deinit(self.scratch_allocator);
                for (self.session.storage.evidence.view().quantifierGoals(actual)) |goal| {
                    try self.solver.chargeProjection();
                    var value: types.Obligation = .{ .ty = 0, .kind = goal.kind, .source = 0, .name = goal.name, .operator = goal.operator, .identity = goal.identity, .explicit = goal.explicit };
                    inline for (.{ "ty", "other", "result", "signature" }) |field| {
                        const endpoint = @field(goal, field);
                        if (endpoint != 0) @field(value, field) = try self.importEvidence(endpoint, depth + 1);
                    }
                    try goals.append(self.scratch_allocator, value);
                }
                break :blk try self.solver.quantifiedWithGoals(tag, try self.importEvidence(node.a, depth + 1), binders[0..node.b], goals.items);
            },
            .projection => blk: {
                const descriptor = self.session.storage.evidence.view().projection(actual);
                if (descriptor.scope >= self.rank_evidence_frames.items.len) return error.UnresolvedType;
                const arguments = self.session.storage.evidence.children(actual);
                const imported = try self.scratch_allocator.alloc(types.Id, arguments.len);
                defer self.scratch_allocator.free(imported);
                for (arguments, imported) |argument, *target| target.* = try self.importEvidence(argument, depth + 1);
                break :blk try self.solver.projection(.{ .unit = node.a, .decl = node.b }, descriptor.member, imported);
            },
            .bound => blk: {
                if (node.c >= self.rank_evidence_frames.items.len) return error.UnresolvedType;
                const binders = self.rank_evidence_frames.items[self.rank_evidence_frames.items.len - 1 - node.c];
                if (node.a >= binders.len or self.solver.node(binders[node.a]).b != node.b) return error.UnresolvedType;
                break :blk binders[node.a];
            },
            .usage => self.solver.usage(try self.importEvidence(node.a, depth + 1), @fromBackingInt(@intCast(node.b)), if (node.c == 0) 0 else try self.importEvidence(node.c, depth + 1)),
            .scoped => self.solver.scoped(try self.importEvidence(node.a, depth + 1), .{ .unit = node.b, .decl = node.c }),
            .erased_proof => self.solver.proofKind(),
            .absent => error.UnresolvedType,
            .unit, .boolean, .u32, .f32, .never => actual,
            .function => self.solver.functionWithEffects(try self.importEvidence(node.a, depth + 1), try self.importEvidence(node.b, depth + 1), try self.importEvidenceRow(node.c, depth + 1)),
            .array, .list, .cursor => self.solver.sequence(switch (node.tag) {
                .list => .list,
                .cursor => .cursor,
                else => .array,
            }, try self.importEvidence(node.a, depth + 1)),
            .demand => self.solver.demandWithEffects(try self.importEvidence(node.a, depth + 1), try self.importEvidenceRow(node.c, depth + 1)),
            .provider => self.solver.provider(try self.importEvidence(node.a, depth + 1), try self.importEvidenceRow(node.c, depth + 1)),
            .state_provider => self.solver.stateProvider(try self.importEvidence(node.a, depth + 1), try self.importEvidence(node.b, depth + 1), try self.importEvidence(node.c, depth + 1)),
            .resolver => self.solver.resolver(try self.importEvidence(node.a, depth + 1)),
            .type_constructor => self.solver.typeConstructor(.{ .unit = node.a, .decl = node.b }),
            .record => blk: {
                var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
                var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.scratch_allocator);
                const allocator = scratch.allocator();
                const children = self.session.storage.evidence.children(actual);
                const fields = try allocator.alloc(types.Field, children.len / 2);
                defer allocator.free(fields);
                for (fields, 0..) |*field, index| field.* = .{ .name = children[index * 2], .ty = try self.importEvidence(children[index * 2 + 1], depth + 1) };
                break :blk try self.solver.record(fields);
            },
            .product, .nominal => blk: {
                var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
                var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.scratch_allocator);
                const allocator = scratch.allocator();
                const children = self.session.storage.evidence.children(actual);
                const values = try allocator.alloc(types.Id, children.len);
                defer allocator.free(values);
                for (children, values) |child, *value| value.* = try self.importEvidence(child, depth + 1);
                break :blk if (node.tag == .nominal) try self.solver.nominal(.{ .unit = node.a, .decl = node.b }, values) else try self.solver.product(values);
            },
        };
    }
    fn importEvidenceLabel(self: *ClosureRegion, label: u32, depth: usize) RegionError!types.Effects.Label {
        if (depth >= self.session.options.max_type_depth) return error.TypeLimit;
        self.prepareEvidenceImports();
        if (self.rank_evidence_frames.items.len == 0) if (self.scratch.evidence_labels.get(label)) |known| return known;
        const source = self.session.storage.evidence.view().effects;
        const operation = source.operation(label);
        var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.scratch_allocator);
        const allocator = scratch.allocator();
        const original = source.operationArguments(label);
        const arguments = try allocator.alloc(types.Id, original.len);
        defer allocator.free(arguments);
        for (original, arguments) |argument, *imported| imported.* = try self.importEvidence(argument, depth + 1);
        const result = try self.solver.internScopedOperation(operation.identity, operation.instance, arguments);
        if (self.rank_evidence_frames.items.len == 0) try self.scratch.evidence_labels.put(self.scratch_allocator, label, result);
        return result;
    }
    fn importEvidenceRow(self: *ClosureRegion, row: u32, depth: usize) RegionError!types.Effects.Id {
        if (row == 0) return 0;
        if (depth >= self.session.options.max_type_depth) return error.TypeLimit;
        self.prepareEvidenceImports();
        if (self.rank_evidence_frames.items.len == 0) if (self.scratch.evidence_rows.get(row)) |known| return known;
        const source = self.session.storage.evidence.view().effects;
        var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.scratch_allocator);
        const allocator = scratch.allocator();
        const source_labels = source.rowLabels(row);
        const labels = try allocator.alloc(types.Effects.Label, source_labels.len);
        defer allocator.free(labels);
        for (source_labels, labels) |label, *imported| imported.* = try self.importEvidenceLabel(label, depth + 1);
        var tail: types.Effects.Tail = .closed;
        const formal = source.rows[row].formal;
        if (formal != 0) tail = .{ .formal = try self.importEvidence(formal, depth + 1) };
        const result = self.solver.effects.row(labels, tail) catch |err| return types.effectError(err);
        if (self.rank_evidence_frames.items.len == 0) try self.scratch.evidence_rows.put(self.scratch_allocator, row, result);
        return result;
    }
    fn associatedContext(self: *ClosureRegion, scope: u32) u32 {
        const source = self.scratch.sources.items[scope];
        if (self.session.privateImplementationMethod(source.owner, source.binding)) return self.session.unitId(source.owner);
        if (self.current_implementation_context) |context| return context;
        if (source.implementation_context) |context| return context;
        if (self.current_origin) |origin| return origin.unit;
        if (source.origin) |origin| return origin.unit;
        return self.session.unitId(source.owner);
    }
    fn normalizeProjection(self: *ClosureRegion, root: types.Id, depth: usize) RegionError!void {
        if (!self.solver.has_projections) return;
        try self.associatedSync();
        errdefer self.associatedDebit();
        try self.normalizeProjectionNode(root, depth);
        try self.associatedSync();
    }
    fn associatedDebit(self: *ClosureRegion) void {
        const spent = self.solver.projection_steps - self.associated_observed;
        self.session.associated_remaining -= @min(self.session.associated_remaining, spent);
        self.associated_observed = self.solver.projection_steps;
    }
    fn associatedSync(self: *ClosureRegion) RegionError!void {
        const spent = self.solver.projection_steps - self.associated_observed;
        if (spent > self.session.associated_remaining) {
            self.associatedDebit();
            self.session.implementation_proofs.failure = .associated_limit;
            return error.TypeLimit;
        }
        self.associatedDebit();
        self.solver.projection_limit = self.solver.projection_steps + self.session.associated_remaining;
    }
    fn projectAssociatedOwned(self: *ClosureRegion, root: types.Id) type_evidence.Error!type_evidence.Id {
        return self.session.storage.evidence.projectAssociatedOwned(&self.solver, root, &self.scratch.projection_cache, &self.session.associated_remaining) catch |err| {
            if (err == error.EvidenceLimit) self.session.implementation_proofs.failure = .associated_limit;
            return err;
        };
    }
    fn normalizeProjectionNode(self: *ClosureRegion, root: types.Id, depth: usize) RegionError!void {
        if (depth >= 256 or self.session.associated_remaining == 0) {
            self.session.implementation_proofs.failure = .associated_limit;
            return error.TypeLimit;
        }
        self.session.associated_remaining -= 1;
        const id = self.solver.head(root, 0);
        const node = self.solver.node(id);
        if (id <= types.never or node.tag == .variable) return;
        const key: NormalizationKey = .{ .root = id, .types = self.solver.mutation_epoch, .rows = self.solver.effects.mutation_epoch };
        if (self.normalization_memo.contains(key)) return;
        switch (node.tag) {
            .function, .state_provider => {
                try self.normalizeProjection(node.a, depth + 1);
                try self.normalizeProjection(node.b, depth + 1);
                if (node.tag == .state_provider) try self.normalizeProjection(node.c, depth + 1);
            },
            .array, .list, .cursor, .demand, .provider, .resolver => try self.normalizeProjection(node.a, depth + 1),
            .product, .nominal, .projection => {
                var children: []const types.Id = undefined;
                if (node.tag == .product) {
                    children = self.solver.list(.{ .start = node.a, .len = node.b });
                } else children = self.solver.nominalArguments(node);
                const saved = try self.scratch_allocator.dupe(types.Id, children);
                defer self.scratch_allocator.free(saved);
                for (saved) |child| try self.normalizeProjection(child, depth + 1);
                if (node.tag == .projection) {
                    const scope = self.projection_scopes.get(id) orelse return;
                    const arguments = try self.scratch_allocator.alloc(type_evidence.Id, saved.len);
                    defer self.scratch_allocator.free(arguments);
                    for (saved, arguments) |child, *argument| {
                        argument.* = self.projectAssociatedOwned(try self.solver.resolve(child, 0)) catch |err| switch (err) {
                            error.OutOfMemory => return error.OutOfMemory,
                            error.UnresolvedType => return,
                            error.EvidenceLimit => return error.TypeLimit,
                            error.TypeMismatch => return error.TypeMismatch,
                        };
                    }
                    const context = self.associatedContext(scope);
                    const actual = self.session.implementation_proofs.projection(self.session, context, .{ .unit = node.a, .decl = node.b }, self.solver.projectionMember(node), arguments) catch |err| switch (err) {
                        error.OutOfMemory => return error.OutOfMemory,
                        error.UnresolvedType => return,
                        else => return self.session.implementationFailure(self.scratch.sources.items[scope].owner, self.scratch.sources.items[scope].body),
                    };
                    try self.associatedSync();
                    try self.solver.bindAssociated(id, try self.importEvidence(actual, 0));
                }
            },
            .record => {
                for (0..node.b) |ordinal| try self.normalizeProjection(self.solver.recordField(node, ordinal).ty, depth + 1);
            },
            else => {},
        }
        try self.normalization_memo.put(self.session.allocator, .{ .root = id, .types = self.solver.mutation_epoch, .rows = self.solver.effects.mutation_epoch }, {});
    }
    fn captureShape(self: *ClosureRegion, declared: types.Id, actual: types.Id) RegionError!void {
        // A template hint carries machine shape; the declared binding owns
        // its usage contract, already independently checked in immutable Core.
        if (self.solver.has_usage_types) return self.unify(try self.codeUsageView(declared, 0), try self.codeUsageView(actual, 0));
        return self.unify(declared, actual);
    }
    fn unify(self: *ClosureRegion, left: types.Id, right: types.Id) RegionError!void {
        if (!self.solver.has_projections) return self.solver.unify(left, right);
        return self.unifyAssociatedRoot(left, right, null);
    }
    fn unifyAssociatedRoot(self: *ClosureRegion, left: types.Id, right: types.Id, reporter: ?types.Store.MismatchReporter) RegionError!void {
        try self.associatedSync();
        errdefer self.associatedDebit();
        var pairs: std.AutoHashMapUnmanaged(u64, void) = .empty;
        defer pairs.deinit(self.scratch_allocator);
        try self.unifyAssociated(left, right, 0, reporter, &pairs);
        try self.associatedSync();
    }
    fn unifyAssociated(self: *ClosureRegion, left: types.Id, right: types.Id, depth: usize, reporter: ?types.Store.MismatchReporter, pairs: *std.AutoHashMapUnmanaged(u64, void)) RegionError!void {
        const a = self.solver.head(left, 0);
        const b = self.solver.head(right, 0);
        if (a == b) return;
        const key = (@as(u64, a) << 32) | b;
        if (pairs.contains(key)) return;
        if (self.session.associated_remaining == 0) return error.TypeLimit;
        self.session.associated_remaining -= 1;
        try self.unifyAssociatedPair(left, right, depth, reporter, pairs);
        try pairs.put(self.scratch_allocator, key, {});
    }
    fn unifyAssociatedPair(self: *ClosureRegion, left: types.Id, right: types.Id, depth: usize, reporter: ?types.Store.MismatchReporter, pairs: *std.AutoHashMapUnmanaged(u64, void)) RegionError!void {
        if (depth >= 256) return error.TypeLimit;
        const a = self.solver.head(left, 0);
        const b = self.solver.head(right, 0);
        const first = self.solver.node(a);
        const second = self.solver.node(b);
        if (first.tag == .function and second.tag == .function) {
            // Inputs determine public binders before an associated result can
            // be normalized. A result never determines a projection's input.
            try self.unifyAssociated(first.a, second.a, depth + 1, reporter, pairs);
            try self.unifyAssociated(first.b, second.b, depth + 1, reporter, pairs);
            return self.solver.unifyEffects(first.c, second.c);
        }
        if (first.tag == second.tag) {
            switch (first.tag) {
                .array, .list, .cursor => return self.unifyAssociated(first.a, second.a, depth + 1, reporter, pairs),
                .product => {
                    if (first.b != second.b) return error.TypeMismatch;
                    for (0..first.b) |ordinal| try self.unifyAssociated(self.solver.list(.{ .start = first.a, .len = first.b })[ordinal], self.solver.list(.{ .start = second.a, .len = second.b })[ordinal], depth + 1, reporter, pairs);
                    return;
                },
                else => {},
            }
        }
        try self.normalizeProjection(a, 0);
        try self.normalizeProjection(b, 0);
        return self.solver.unifyWithReporter(a, b, reporter);
    }
    fn project(self: *ClosureRegion, ty: types.Id) RegionError!type_evidence.Id {
        try self.normalizeProjection(ty, 0);
        const resolved = try self.solver.resolve(ty, 0);
        if (self.solver.has_projections) return self.projectAssociatedOwned(resolved) catch |err| switch (err) {
            error.UnresolvedType => 0,
            else => return err,
        };
        return self.session.storage.evidence.projectOwned(&self.solver, resolved, &self.scratch.projection_cache) catch |err| switch (err) {
            error.UnresolvedType => 0,
            else => return err,
        };
    }
    fn addValue(self: *ClosureRegion, value_: ValueId, depth: usize) RegionError!u32 {
        if (depth >= self.session.options.max_type_depth or self.scratch.sources.items.len >= self.session.options.max_values or self.scratch.sources.items.len >= std.math.maxInt(u32)) return error.TypeLimit;
        // Only a complete imported interface enters this map. Open callable
        // values still instantiate independently at every use.
        if (self.scratch.value_scopes.get(value_)) |prior| return prior;
        const kind = self.session.valueInfo(value_).kind;
        if (kind != .closure and kind != .suspension) return self.addAggregate(value_, depth);
        const metadata = self.session.closureInfo(value_);
        const owner = self.session.findUnit(metadata.unit, null) orelse return error.UnresolvedType;
        const module = &self.session.units[owner];
        const scope: u32 = @intCast(self.scratch.sources.items.len);
        try self.scratch.sources.append(self.scratch_allocator, .{ .value = value_, .owner = owner });
        var body: core.Id = 0;
        const root = switch (metadata.origin) {
            .anonymous => blk: {
                const template = module.closures[metadata.identity];
                body = template.body;
                self.scratch.sources.items[scope].closed_rows = template.closed_rows;
                if (template.function_type != 0) {
                    const function = try self.importImplementation(scope, template.function_type);
                    if (kind != .suspension) break :blk function;
                    const signature = self.solver.node(function);
                    if (signature.tag != .function) return error.TypeMismatch;
                    break :blk try self.solver.demandWithEffects(signature.b, signature.c);
                }
                const result = try self.importType(scope, module.typeOf(template.body), 0);
                break :blk if (kind == .suspension) try self.solver.demand(result) else try self.solver.function(try self.importType(scope, template.parameter.ty, 0), result);
            },
            .named => blk: {
                const definition = module.body(metadata.identity) orelse return error.UnresolvedType;
                body = definition.root;
                self.scratch.sources.items[scope].closed_rows = definition.closed_rows;
                var full = module.types.withoutForall(module.binding(metadata.identity).ty) catch return error.TypeLimit;
                for (0..metadata.applied) |_| {
                    const n = module.types.node(full);
                    if (n.tag != .function) return error.TypeMismatch;
                    full = n.b;
                }
                break :blk try self.importType(scope, full, 0);
            },
            .constructor => try self.importType(scope, module.constructor(metadata.identity).scheme.root, 0),
            .primitive => blk: {
                if (metadata.ty == 0) return error.UnresolvedType;
                var full = metadata.ty;
                for (0..metadata.applied) |_| {
                    const n = module.types.node(full);
                    if (n.tag != .function) return error.TypeMismatch;
                    full = n.b;
                }
                break :blk try self.importType(scope, full, 0);
            },
            .operation => blk: {
                const operation = module.operation_values[metadata.identity];
                const signature = try self.importType(scope, operation.signature, 0);
                try self.operationConstraint(scope, 0, operation);
                break :blk signature;
            },
        };
        self.scratch.sources.items[scope].root = root;
        self.scratch.sources.items[scope].body = body;
        for (self.session.storage.type_mappings.items[metadata.mappings.start..][0..metadata.mappings.len]) |mapping| try self.unify(try self.importType(scope, mapping.variable, 0), try self.importEvidence(mapping.evidence, 0));
        try self.seedRows(scope, self.session.storage.row_mappings.items[metadata.row_mappings.start..][0..metadata.row_mappings.len]);
        const existing = self.session.valueEvidence(value_);
        if (existing != 0) try self.unify(root, try self.importEvidence(existing, 0));
        const capture_count = self.session.valueInfo(value_).len;
        self.unkeyed_capture_inputs = self.unkeyed_capture_inputs or capture_count != 0;
        for (0..capture_count) |index| {
            const capture = self.session.valueChildren(value_)[index];
            const formal_source = switch (metadata.origin) {
                .anonymous => module.binding(module.extra[module.closures[metadata.identity].captures.start + index]).ty,
                .named => module.bodyParameters(module.body(metadata.identity).?)[index].ty,
                .primitive => blk: {
                    var full = metadata.ty;
                    for (0..index) |_| full = module.types.node(full).b;
                    break :blk module.types.node(full).a;
                },
                .constructor, .operation => return error.TypeMismatch,
            };
            const formal = try self.importType(scope, formal_source, 0);
            if (self.session.valueInfo(capture).kind != .scalar) {
                const child = try self.addValue(capture, depth + 1);
                const actual = try self.solver.resolve(self.scratch.sources.items[child].root, 0);
                // Admit the capture's ambient view while retaining its implementation row.
                try self.unify(formal, try self.solver.openCovariant(actual));
                try self.scratch.edges.append(self.scratch_allocator, .{ .parent = scope, .child = child, .slot = @intCast(index), .formal = formal });
            } else {
                const actual = self.session.valueEvidence(capture);
                if (actual == 0) return error.UnresolvedType;
                try self.unify(formal, try self.importEvidence(actual, 0));
            }
        }
        if (metadata.origin == .named) {
            self.scratch.sources.items[scope].binding = metadata.identity;
            try self.importScheme(scope, module.binding(metadata.identity).scheme, body);
        } else if (metadata.origin == .anonymous) {
            const qualifier = module.closures[metadata.identity].qualifier;
            self.scratch.sources.items[scope].binding = qualifier;
            if (qualifier != 0) try self.importScheme(scope, module.binding(qualifier).scheme, body);
        }
        if (try self.project(root) != 0) try self.scratch.value_scopes.put(self.scratch_allocator, value_, scope);
        if (body != 0 and !try self.deferLexicalBody(scope, value_)) try self.collect(scope, body);
        return scope;
    }
    fn deferLexicalBody(self: *ClosureRegion, scope: u32, value: ValueId) RegionError!bool {
        if (!self.session.options.reuse_lexical_summaries or self.building_principal or self.source_interface or self.retain_selected or self.complete_demand_bodies or self.session.valueInfo(value).kind != .closure) return false;
        // Portable receipts require explicit replay of every observation.
        // Their current ordinary path retains the complete source/capture proof.
        if (self.session.receipt_tape != null or self.session.recordingConstant() or self.session.principal_reads != null or self.session.refinement_observation != null) return false;
        if (self.session.specializations.lexical_inputs.examined_words >= self.session.options.max_children) return false;
        // The key never admits an empty environment, and it reads interfaces
        // only for values reachable from the captures. Views of unrelated
        // values cannot enter it, so only reachable scopes are projected.
        if (self.session.valueInfo(value).len == 0) return false;
        var reachable: std.AutoHashMapUnmanaged(ValueId, void) = .empty;
        defer reachable.deinit(self.scratch_allocator);
        var pending: std.ArrayList(ValueId) = .empty;
        defer pending.deinit(self.scratch_allocator);
        try pending.appendSlice(self.scratch_allocator, self.session.valueChildren(value));
        while (pending.pop()) |current| {
            if (self.session.specializations.lexical_inputs.interface_visits >= self.session.options.max_children or reachable.count() >= self.session.options.max_values) return false;
            self.session.specializations.lexical_inputs.interface_visits += 1;
            if (current >= self.session.storage.values.items.len) return false;
            if ((try reachable.getOrPut(self.scratch_allocator, current)).found_existing) continue;
            try pending.appendSlice(self.scratch_allocator, self.session.valueChildren(current));
        }
        var selected: lexical_capture_inputs.Interfaces = .empty;
        defer selected.deinit(self.scratch_allocator);
        for (self.scratch.sources.items) |capture| {
            if (self.session.specializations.lexical_inputs.interface_visits >= self.session.options.max_children) return false;
            self.session.specializations.lexical_inputs.interface_visits += 1;
            if (capture.value == 0 or capture.root == 0 or !reachable.contains(capture.value)) continue;
            self.session.counters.lexical_interface_projections += 1;
            const actual = try self.project(capture.root);
            if (actual == 0) continue;
            if (selected.get(capture.value)) |prior| {
                // One live polymorphic value can still have incompatible
                // per-use views. It has no single complete capture interface.
                if (prior != actual) return false;
            } else try selected.put(self.scratch_allocator, capture.value, actual);
        }
        const lexical = try self.session.specializations.lexical_inputs.intern(self.session.allocator, self.session, value, &selected) orelse return false;
        const source = self.scratch.sources.items[scope];
        try self.appendConstraint(.{ .kind = .call_summary, .lexical_key = lexical, .target = .{ .unit = source.owner, .binding = 0 }, .scope = scope, .node = source.body, .left = source.root, .result = source.root, .deferred_member = self.defer_members });
        return true;
    }
    fn addAggregate(self: *ClosureRegion, value_: ValueId, depth: usize) RegionError!u32 {
        const info = self.session.valueInfo(value_);
        var owner: usize = 0;
        var constructor_index: ?u32 = null;
        if (info.kind == .nominal) {
            owner = self.session.findUnit(@intCast(info.nominal >> 32), null) orelse return error.UnresolvedType;
            const module = &self.session.units[owner];
            for (module.constructors, 0..) |constructor, index| {
                const family = module.nominal(constructor.nominal).identity;
                if (self.session.nominalIdentity(owner, family.unit, family.decl) == info.nominal and constructor.tag == info.bits) {
                    constructor_index = @intCast(index);
                    break;
                }
            }
            if (constructor_index == null) return error.UnresolvedType;
        }
        const scope: u32 = @intCast(self.scratch.sources.items.len);
        try self.scratch.sources.append(self.scratch_allocator, .{ .owner = owner, .value = value_ });
        var capture_count = self.session.valueInfo(value_).len;
        if (info.kind == .code or info.kind == .descriptor) capture_count = 0;
        var children: std.ArrayList(types.Id) = .empty;
        defer children.deinit(self.scratch_allocator);
        for (0..capture_count) |index| {
            const capture = self.session.valueChildren(value_)[index];
            const child = try self.addValue(capture, depth + 1);
            const formal = self.scratch.sources.items[child].root;
            try children.append(self.scratch_allocator, formal);
            try self.scratch.edges.append(self.scratch_allocator, .{ .parent = scope, .child = child, .slot = @intCast(index), .formal = formal });
        }
        var root = switch (info.kind) {
            .staged_value => return error.UnresolvedType,
            .code, .descriptor, .scalar, .type_constructor, .resolver, .provider, .state_provider, .proof, .capability => try self.importEvidence(self.session.valueEvidence(value_), 0),
            .product => try self.solver.product(children.items),
            .cursor => if (children.items.len == 1) try self.solver.sequence(.cursor, children.items[0]) else return error.TypeMismatch,
            .record => blk: {
                const names = self.session.recordFieldNames(value_);
                if (names.len != children.items.len) return error.UnresolvedType;
                var fields: std.ArrayList(types.Field) = .empty;
                defer fields.deinit(self.session.allocator);
                for (names, children.items) |name, ty| try fields.append(self.session.allocator, .{ .name = name, .ty = ty });
                break :blk try self.solver.record(fields.items);
            },
            .array, .list => blk: {
                const element = if (children.items.len == 0) try self.solver.fresh() else children.items[0];
                for (children.items) |child| try self.unify(element, child);
                break :blk try self.solver.sequence(if (info.kind == .list) .list else .array, element);
            },
            .nominal => blk: {
                const constructor = self.session.units[owner].constructor(constructor_index.?);
                const scheme = try self.importType(scope, constructor.scheme.root, 0);
                if (constructor.payload == 0) {
                    if (children.items.len != 0) return error.TypeMismatch;
                    break :blk scheme;
                }
                if (children.items.len != 1) return error.TypeMismatch;
                const arrow = self.solver.node(scheme);
                if (arrow.tag != .function) return error.TypeMismatch;
                // Stored callbacks have exact rows; a checked use may widen
                // them, so their covariant rows reopen before the invariant
                // nominal argument is fixed (as the checker does per use).
                const payload = try self.solver.openCovariant(try self.solver.resolve(children.items[0], 0));
                try self.unify(try self.importType(scope, constructor.payload, 0), payload);
                break :blk arrow.b;
            },
            .effect_set, .effect_descriptor, .computation, .request_decision => try self.importEvidence(self.session.valueEvidence(value_), 0),
            .package => blk: {
                if (info.bits == 0) return error.UnresolvedType;
                break :blk try self.importEvidence(info.bits, 0);
            },
            .closure, .suspension => return error.UnresolvedType,
        };
        const existing = self.session.valueEvidence(value_);
        if (existing != 0) {
            const wrapper = self.session.storage.evidence.node(existing);
            if ((info.kind == .array or info.kind == .list) and wrapper.tag == .usage) {
                if (wrapper.c != 0 or (wrapper.b != @backingInt(types.UsageKind.unique) and wrapper.b != @backingInt(types.UsageKind.shared))) return error.TypeMismatch;
                // Reconstruct the observed storage before preserving the exact
                // owning qualifier from this value's checked creation.
                try self.unify(root, try self.importEvidence(wrapper.a, 0));
                root = try self.solver.usage(root, @fromBackingInt(@intCast(wrapper.b)), 0);
            } else try self.unify(root, try self.importEvidence(existing, 0));
        }
        self.scratch.sources.items[scope].root = root;
        if (try self.project(root) != 0) try self.scratch.value_scopes.put(self.scratch_allocator, value_, scope);
        return scope;
    }
    fn collectCall(self: *ClosureRegion, caller: u32, reference: core.BindingRef, callee_type: types.Id, arguments: []const core.Id) RegionError!void {
        return self.collectCallAt(caller, reference, callee_type, arguments, 0);
    }
    fn collectCallAt(self: *ClosureRegion, caller: u32, reference: core.BindingRef, callee_type: types.Id, arguments: []const core.Id, site: core.Id) RegionError!void {
        const caller_owner = self.scratch.sources.items[caller].owner;
        const previous_implementation_context = self.current_implementation_context;
        if (self.session.has_implementations and site != 0) self.current_implementation_context = self.session.implementationUseContext(caller_owner, site);
        defer self.current_implementation_context = previous_implementation_context;
        if (self.session.has_implementations and site != 0) {
            const resolved = try self.session.external(try self.session.target(caller_owner, reference));
            const module = &self.session.units[resolved.unit];
            for (module.member_templates) |template| {
                if (template.binding != resolved.binding) continue;
                const actual = try self.project(try self.importType(caller, callee_type, 0));
                if (actual == 0) break;
                const selected = try self.session.selectTemplate(caller_owner, site, reference, actual);
                try self.session.prepare(selected);
                return self.collectCall(caller, selected, callee_type, arguments);
            }
        }
        if (!self.building_principal) if (self.current_origin) |origin| {
            const caller_module = &self.session.units[caller_owner];
            for (arguments) |argument| {
                if (caller_module.types.node(caller_module.typeOf(argument)).tag != .function) continue;
                var argument_owner = caller_owner;
                var callback = argument;
                var parameter: core.BindingId = 0;
                if (caller_module.node(argument).tag == .reference) {
                    const target = try self.session.external(try self.session.target(caller_owner, caller_module.reference(argument)));
                    argument_owner = target.unit;
                    const producer = &self.session.units[target.unit];
                    if (producer.body(target.binding)) |body| {
                        callback = body.root;
                        for (producer.bodyParameters(body)) |input| if (input.inferred) {
                            parameter = input.binding;
                            break;
                        };
                    } else continue;
                }
                const producer = &self.session.units[argument_owner];
                if (producer.node(callback).tag == .closure) {
                    const closure = producer.closure(callback);
                    if (closure.parameter.inferred) parameter = closure.parameter.binding;
                } else {
                    for (producer.closures) |closure| if (closure.body == callback and closure.parameter.inferred) {
                        parameter = closure.parameter.binding;
                        break;
                    };
                }
                if (parameter != 0) try self.scratch.callback_origins.append(self.scratch_allocator, .{ .owner = argument_owner, .span = producer.span(callback), .origin = origin, .parameter = parameter });
            }
        };
        const target_ = try self.session.external(try self.session.target(caller_owner, reference));
        const module = &self.session.units[target_.unit];
        const binding = module.binding(target_.binding);
        const definition = module.body(target_.binding);
        if (self.building_principal) {
            if (self.formalCallback(caller, reference)) |slot| {
                // Merely referencing a formal callback does not select its
                // implementation. Each actual application has its own action.
                var arrow = try self.importType(caller, callee_type, 0);
                for (arguments, 0..) |argument, stage| {
                    const node = self.solver.node(try self.solver.resolve(arrow, 0));
                    if (node.tag != .function) return error.UnresolvedType;
                    try self.appendConstraint(.{ .kind = .callback_use, .scope = caller, .node = argument, .callback_slot = slot, .callback_stage = @intCast(stage), .left = arrow, .right = try self.importType(caller, self.session.units[self.scratch.sources.items[caller].owner].typeOf(argument), 0), .result = node.b, .signature = try self.callbackSignature(caller, slot) });
                    arrow = node.b;
                }
                return;
            }
            if (binding.kind != .global or !try self.summaryShapeEligible(target_)) return error.UnresolvedType;
            const start = self.scratch.summary_arguments.items.len;
            if (arguments.len > std.math.maxInt(u32) - start) return error.TypeLimit;
            try self.scratch.summary_arguments.appendSlice(self.scratch_allocator, arguments);
            // An edge contains its symbolic interface and original witnesses;
            // describing it never imports a selected callee or expands a path.
            const signature = try self.importType(caller, callee_type, 0);
            try self.appendConstraint(.{ .kind = .call_summary, .target = target_, .scope = caller, .node = 0, .left = signature, .result = signature, .right = callee_type, .arguments = .{ .start = @intCast(start), .len = @intCast(arguments.len) }, .deferred_member = self.defer_members });
            return;
        }
        if (self.session.receipt_tape) |tape| if (binding.kind == .global) {
            if (definition == null or (definition.?.runtime and !definition.?.is_function)) tape.unknown = true;
        };
        if (self.session.principal_reads) |reads| if (binding.kind == .global and (definition == null or (definition.?.runtime and !definition.?.is_function))) {
            reads.invalidate(.runtime_source);
        };
        const lexical_caller: u32 = if (definition == null) caller + 1 else 0;
        const body_root = if (definition) |body| body.root else binding.initializer;
        if (body_root == 0) {
            if (self.retain_selected) self.startup_coverage_complete = false;
            return;
        }
        const source_type = if (definition) |body| body.scheme.root else binding.scheme.root;
        if (module.types.node(source_type).tag != .function) {
            if (self.retain_selected) self.startup_coverage_complete = false;
            return;
        }
        const instantiated = try self.importType(caller, callee_type, 0);
        const known = try self.project(instantiated);
        if (known != 0) {
            if (!self.retain_selected and !self.source_interface and self.session.options.reuse_validated_calls and definition != null and binding.kind == .global) {
                const present = self.session.specializations.validated_calls.contains(.{ .target = target_, .evidence = known });
                if (self.session.receipt_tape) |tape| try tape.call_reads.append(self.session.allocator, .{ .unit = self.session.unitId(target_.unit), .binding = target_.binding, .evidence = known, .present = present });
                if (self.session.principal_reads) |reads| try reads.callRead(self.session.allocator, .{ .unit = self.session.unitId(target_.unit), .binding = target_.binding }, known, present);
                if (present) {
                    self.session.proofs.proof_reused += 1;
                    return;
                }
            }
            if (self.scratch.call_instances.get(.{ .owner = target_.unit, .binding = target_.binding, .evidence = known, .caller = lexical_caller })) |prior| {
                self.session.counters.call_memo_hits += 1;
                _ = try self.admitSignature(instantiated, self.scratch.sources.items[prior].root);
                return;
            }
        }
        // Input-keyed jobs already bound repeated concrete calls. An eager
        // interface import must not expand their shared callee graph again.
        const completed_interface = self.session.reuse_principal_graphs and self.partial_principal and !self.retain_selected and !self.complete_demand_bodies and
            definition != null and definition.?.is_function and binding.kind == .global and
            binding.scheme.obligations.len != 0 and !try self.summaryEligible(target_) and try self.completedInterface(target_);
        // Source checking proves a declared body under its written requirements.
        // Import those requirements with fresh variables; do not recollect the
        // body or publish a closed call proof before its predicates are solved.
        if ((!self.source_interface or binding.scheme.obligations.len != 0) and !self.retain_selected and !self.complete_demand_bodies and definition != null and definition.?.is_function and binding.kind == .global and (completed_interface or try self.checkedSchemeReusable(target_))) {
            // This branch consumes the freshly checked scheme, not its body.
            // Requirement producers are checked headers too. Record the entire
            // reachable header graph, even when checkedRequirements hit its
            // session cache or a producer currently has no explicit leaves.
            try self.observeCheckedScheme(target_);
            // Keep shared residual edges before importing an interface tree.
            // Repeated callee requirements may form a diamond; expanding every
            // path loses the bounded principal-graph algorithm.
            if (binding.scheme.obligations.len != 0 and self.partial_principal and try self.retainOpenPrincipal(.{ .target = target_, .scope = caller, .node = body_root, .left = instantiated, .result = instantiated, .deferred_member = self.defer_members })) {
                const start = self.scratch.summary_arguments.items.len;
                if (arguments.len > std.math.maxInt(u32) - start) return error.TypeLimit;
                try self.scratch.summary_arguments.appendSlice(self.scratch_allocator, arguments);
                try self.appendConstraint(.{ .kind = .call_summary, .target = target_, .scope = caller, .node = body_root, .left = instantiated, .result = instantiated, .right = callee_type, .arguments = .{ .start = @intCast(start), .len = @intCast(arguments.len) }, .deferred_member = self.defer_members, .principal_only = true });
                self.principal_only_used = true;
                return;
            }
            const scope = try self.typeScope(target_.unit);
            self.scratch.sources.items[scope].body = body_root;
            self.scratch.sources.items[scope].binding = target_.binding;
            self.scratch.sources.items[scope].closed_rows = definition.?.closed_rows;
            self.setSourceRoot(scope, try self.importType(scope, source_type, 0));
            _ = try self.admitSignature(instantiated, self.scratch.sources.items[scope].root);
            if (completed_interface) {
                self.principal_only_used = true;
                try self.importCompletedInterface(scope, target_);
            } else try self.importScheme(scope, binding.scheme, body_root);
            if (self.source_interface) {
                var formal = self.scratch.sources.items[scope].root;
                const caller_module = &self.session.units[self.scratch.sources.items[caller].owner];
                for (arguments) |argument| {
                    const arrow = self.solver.node(try self.solver.resolve(formal, 0));
                    if (arrow.tag != .function) break;
                    const actual = try self.importType(caller, caller_module.typeOf(argument), 0);
                    if (self.solver.node(try self.solver.resolve(actual, 0)).tag == .never)
                        try self.scratch.witness_inputs.put(self.scratch_allocator, arrow.a, actual);
                    formal = arrow.b;
                }
            }
            if (self.session.receipt_tape) |tape| try tape.sources.append(self.session.allocator, .{ .unit = self.session.unitId(target_.unit), .binding = target_.binding });
            if (self.session.constant_recorder) |recorder| try recorder.source(self.session.allocator, .{ .unit = self.session.unitId(target_.unit), .binding = target_.binding });
            const actual = try self.project(self.scratch.sources.items[scope].root);
            if (actual != 0) {
                try self.scratch.call_instances.put(self.scratch_allocator, .{ .owner = target_.unit, .binding = target_.binding, .evidence = actual, .caller = 0 }, scope);
                // This checked scheme has no outstanding body obligations. Its
                // closed proof is independent of later failures in the caller.
                if (binding.scheme.obligations.len == 0 and self.session.options.reuse_validated_calls) try self.publishValidatedSource(self.scratch.sources.items[scope]);
            }
            return;
        }
        if (definition != null and binding.kind == .global and !self.retain_selected) {
            const independent = !self.principal_result_job and (!self.unkeyed_capture_inputs or try self.completeCallbackInputs(target_, instantiated)) and try self.summaryEligible(target_);
            const residual = !independent and self.partial_principal and try self.retainOpenPrincipal(.{ .kind = .call_summary, .target = target_, .scope = caller, .node = body_root, .left = instantiated, .result = instantiated, .deferred_member = self.defer_members });
            const result_directed = !independent and !residual and try self.resultPrincipalEligible(target_, self.defer_members);
            if (!independent and !residual and !result_directed) return self.collectInlineCall(caller, target_, callee_type, arguments);
            const start = self.scratch.summary_arguments.items.len;
            if (arguments.len > std.math.maxInt(u32) - start) return error.TypeLimit;
            try self.scratch.summary_arguments.appendSlice(self.scratch_allocator, arguments);
            try self.appendConstraint(.{ .kind = .call_summary, .target = target_, .scope = caller, .node = body_root, .left = instantiated, .result = instantiated, .right = callee_type, .arguments = .{ .start = @intCast(start), .len = @intCast(arguments.len) }, .deferred_member = self.defer_members, .principal_only = residual or result_directed });
            self.principal_only_used = self.principal_only_used or residual or result_directed;
            return;
        }
        try self.collectInlineCall(caller, target_, callee_type, arguments);
    }
    /// A complete first-order interface includes inferred leaves. It is
    /// admitted only after independent lexical body validation; unsupported
    /// requirements and cycles continue through ordinary body collection.
    fn completedInterface(self: *ClosureRegion, root: Target) RegionError!bool {
        self.session.counters.completed_interface_requests += 1;
        const cache = &self.session.specializations.call_summaries.completed_interfaces;
        const targets = (if (cache.getPtr(root)) |known| known: {
            self.session.counters.completed_interface_hits += 1;
            break :known known.*;
        } else fresh: {
            if (cache.count() >= self.session.options.max_values) return false;
            const complete = try self.checkCompletedInterface(root);
            errdefer if (complete) |owned| self.session.allocator.free(owned);
            if (complete) |owned| if (owned.len > self.session.options.max_children -| self.session.specializations.call_summaries.completed_interface_targets) {
                self.session.allocator.free(owned);
                return false;
            };
            try cache.put(self.session.allocator, root, complete);
            if (complete) |owned| self.session.specializations.call_summaries.completed_interface_targets += owned.len;
            if (complete != null) self.session.counters.completed_interface_proofs += 1 else self.session.counters.completed_interface_declines += 1;
            break :fresh complete;
        }) orelse return false;
        // Only the immutable lexical proof is cached. These shape inquiries
        // consume mutable plain-data memo facts, including negative reads, and
        // must be observed again by each principal or refinement recorder.
        for (targets) |target_| {
            const module = &self.session.units[target_.unit];
            const body = module.body(target_.binding).?;
            var ty = body.scheme.root;
            // A source alias has no parameter binders of its own. Its checked
            // arrow still exposes the same complete first-order interface.
            var arrows: usize = 0;
            while (module.types.node(ty).tag == .function) : (arrows += 1) {
                if (arrows >= self.session.options.max_type_depth) return false;
                const arrow = module.types.node(ty);
                if (!try self.potentialData(target_.unit, arrow.a, 0)) return false;
                ty = arrow.b;
            }
            if (!try self.potentialData(target_.unit, ty, 0)) return false;
        }
        return true;
    }
    fn checkCompletedInterface(self: *ClosureRegion, root: Target) RegionError!?[]Target {
        const Visit = struct { target: Target, next: usize = 0 };
        var pending: std.ArrayList(Visit) = .empty;
        defer pending.deinit(self.scratch_allocator);
        var seen: std.AutoHashMapUnmanaged(Target, bool) = .empty;
        defer seen.deinit(self.scratch_allocator);
        try pending.append(self.scratch_allocator, .{ .target = root });
        try seen.put(self.scratch_allocator, root, false);
        var inferred = false;
        var edges: usize = 0;
        while (pending.items.len != 0) {
            const at = pending.items.len - 1;
            const frame = pending.items[at];
            const module = &self.session.units[frame.target.unit];
            const binding = module.binding(frame.target.binding);
            _ = module.body(frame.target.binding) orelse return null;
            if (frame.next == 0 and binding.kind != .global) return null;
            if (frame.next == binding.scheme.obligations.len) {
                seen.getPtr(frame.target).?.* = true;
                _ = pending.pop();
                continue;
            }
            pending.items[at].next += 1;
            edges += 1;
            if (edges > self.session.options.max_children) return null;
            const requirement = module.obligations[binding.scheme.obligations.start + frame.next];
            if (requirement.kind == .callee_use) {
                const child = try self.schemeTarget(frame.target.unit, requirement.identity);
                if (seen.get(child)) |complete| {
                    if (!complete) return null;
                    continue;
                }
                if (seen.count() >= self.session.options.max_values) return null;
                try seen.put(self.scratch_allocator, child, false);
                try pending.append(self.scratch_allocator, .{ .target = child });
            } else {
                if (completedRequirementKind(requirement.kind) == null) return null;
                // An inferred selection may choose an associated accessor;
                // the physical-field predicate alone does not encode that
                // decision. Keep its original body until the plan owns it.
                if (requirement.kind == .field and !requirement.explicit) return null;
                inferred = inferred or !requirement.explicit;
                if (requirement.kind == .dispatch or requirement.kind == .result_dispatch) {
                    if (requirement.signature == 0 or module.types.node(requirement.signature).tag != .function) return null;
                }
            }
        }
        // Keep existing written-header behavior and its exact diagnostic order.
        if (!inferred) return null;
        var buffer: [1024]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&buffer, self.scratch_allocator);
        const owners = try scratch.allocator().alloc(*const core.Module, self.session.units.len);
        defer scratch.allocator().free(owners);
        for (owners, self.session.units) |*owner, *module| owner.* = module;
        var remaining: usize = @min(self.session.options.max_children, 65_536);
        const proof_budget = remaining;
        defer self.session.counters.completed_interface_proof_work += proof_budget - remaining;
        var targets = seen.keyIterator();
        while (targets.next()) |target_| {
            self.session.counters.completed_interface_body_proofs += 1;
            @import("../check/package_core.zig").checkedInterfaceBody(&self.session.units[target_.unit], target_.binding, .{ .units = owners }, &remaining, self.scratch_allocator) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
        }
        const result = try self.session.allocator.alloc(Target, seen.count());
        targets = seen.keyIterator();
        for (result) |*target_| target_.* = targets.next().?.*;
        return result;
    }
    fn completedRequirementKind(kind: types.ObligationKind) ?ConstraintKind {
        return switch (kind) {
            .dispatch => .binary,
            .result_dispatch => .result_dispatch,
            .field => .physical_field,
            .type_rep => .type_rep,
            .effect_rep => .effect_rep,
            else => null,
        };
    }
    fn importCompletedInterface(self: *ClosureRegion, scope: u32, root: Target) RegionError!void {
        const InterfaceFrame = struct { target: Target, scope: u32, next: usize = 0 };
        const a = self.scratch_allocator;
        var pending: std.ArrayList(InterfaceFrame) = .empty;
        defer pending.deinit(a);
        try pending.append(a, .{ .target = root, .scope = scope });
        var edges: usize = 0;
        while (pending.items.len != 0) {
            const at = pending.items.len - 1;
            const target_ = pending.items[at].target;
            const frame_scope = pending.items[at].scope;
            const module = &self.session.units[target_.unit];
            const scheme = module.binding(target_.binding).scheme;
            if (pending.items[at].next == scheme.obligations.len) {
                _ = pending.pop();
                continue;
            }
            edges += 1;
            if (edges > self.session.options.max_children) return error.TypeLimit;
            const requirement = module.obligations[scheme.obligations.start + pending.items[at].next];
            pending.items[at].next += 1;
            if (requirement.kind == .callee_use) {
                const target = try self.schemeTarget(target_.unit, requirement.identity);
                const producer = &self.session.units[target.unit];
                const principal = producer.binding(target.binding);
                const body = producer.body(target.binding).?;
                const actual = try self.importType(frame_scope, requirement.ty, 0);
                const product = self.solver.node(actual);
                if (product.tag != .product or product.b != principal.public_variables.len + principal.public_rows.len) return error.UnresolvedType;
                const arguments = try a.dupe(types.Id, self.solver.list(.{ .start = product.a, .len = product.b }));
                defer a.free(arguments);
                const child_scope = try self.typeScope(target.unit);
                self.scratch.sources.items[child_scope].body = body.root;
                self.scratch.sources.items[child_scope].binding = target.binding;
                self.scratch.sources.items[child_scope].closed_rows = body.closed_rows;
                self.setSourceRoot(child_scope, try self.importType(child_scope, body.scheme.root, 0));
                for (producer.types.list(principal.public_variables), arguments[0..principal.public_variables.len]) |variable, value|
                    try self.unify(try self.importType(child_scope, variable, 0), value);
                for (producer.types.list(principal.public_rows), arguments[principal.public_variables.len..]) |variable, value|
                    try self.solver.unifyEffects(try self.importRowVariable(child_scope, variable), self.solver.node(value).c);
                try pending.append(a, .{ .target = target, .scope = child_scope });
                continue;
            }
            const kind = completedRequirementKind(requirement.kind) orelse return error.UnresolvedType;
            try self.appendConstraint(.{ .scope = frame_scope, .node = module.body(target_.binding).?.root, .span = requirement.span, .explicit = requirement.explicit, .qualification_span = requirement.qualification_span, .qualification_unit = requirement.qualification_unit, .diagnostic_name = module.name(requirement.diagnostic_name), .kind = kind, .left = try self.importType(frame_scope, requirement.ty, 0), .right = if (requirement.other == 0) 0 else try self.importType(frame_scope, requirement.other, 0), .result = if (requirement.result == 0) 0 else try self.importType(frame_scope, requirement.result, 0), .signature = if (requirement.signature == 0) 0 else try self.importType(frame_scope, requirement.signature, 0), .member = requirement.name, .op = requirement.operator, .identity = .{ .unit = if (requirement.identity.unit == 0) self.session.unitId(target_.unit) else requirement.identity.unit, .decl = requirement.identity.decl }, .row_carrier = requirement.explicit and (requirement.kind == .dispatch or requirement.kind == .result_dispatch), .deferred_member = self.defer_members });
            self.session.counters.completed_interface_imports += 1;
        }
    }
    fn observeCheckedScheme(self: *ClosureRegion, target_: Target) RegionError!void {
        const reads = self.session.principal_reads orelse return;
        var next = reads.interfaces.items.len;
        try reads.interface(self.session.allocator, .{ .unit = self.session.unitId(target_.unit), .binding = target_.binding });
        // The recorder's bounded, deduplicated output doubles as a worklist.
        // No region-local graph or second set of allocations is needed.
        while (reads.eligible and reads.source_complete and next < reads.interfaces.items.len) : (next += 1) {
            const source = reads.interfaces.items[next];
            const owner = self.session.unitIndex(source.unit) orelse return error.UnresolvedType;
            const module = &self.session.units[owner];
            const scheme = module.binding(source.binding).scheme;
            for (module.obligations[scheme.obligations.start..][0..scheme.obligations.len]) |requirement| {
                if (requirement.kind != .callee_use) continue;
                const original = try self.session.target(owner, .{ .unit = requirement.identity.unit, .binding = requirement.identity.decl });
                const child = try self.schemeTarget(owner, requirement.identity);
                // An alias chain needs its own source projection. Observing
                // only its final producer would omit a retargeted alias.
                if (!std.meta.eql(original, child)) {
                    reads.source_complete = false;
                    return;
                }
                try reads.interface(self.session.allocator, .{ .unit = self.session.unitId(child.unit), .binding = child.binding });
                if (!reads.eligible or !reads.source_complete) break;
            }
        }
    }
    fn checkedSchemeReusable(self: *ClosureRegion, target_: Target) RegionError!bool {
        const module = &self.session.units[target_.unit];
        const body = module.body(target_.binding) orelse return false;
        if (module.binding(target_.binding).scheme.obligations.len == 0) return true;
        if (!try self.checkedRequirements(target_)) return false;
        var arrow_type = body.scheme.root;
        for (0..body.parameters.len) |_| {
            const arrow = module.types.node(arrow_type);
            if (arrow.tag != .function or !try self.potentialData(target_.unit, arrow.a, 0)) return false;
            arrow_type = arrow.b;
        }
        return self.potentialData(target_.unit, arrow_type, 0);
    }
    fn schemeTarget(self: *ClosureRegion, owner: usize, identity: types.NominalIdentity) RegionError!Target {
        return self.session.external(try self.session.target(owner, .{ .unit = identity.unit, .binding = identity.decl }));
    }
    fn checkedRequirements(self: *ClosureRegion, root: Target) RegionError!bool {
        if (self.session.specializations.call_summaries.checked_requirements.get(root)) |known| return known;
        const Visit = struct { target: Target, next: usize = 0 };
        var stack: std.ArrayList(Visit) = .empty;
        defer stack.deinit(self.scratch_allocator);
        var visited: std.AutoHashMapUnmanaged(Target, bool) = .empty;
        defer visited.deinit(self.scratch_allocator);
        try stack.append(self.scratch_allocator, .{ .target = root });
        try visited.put(self.scratch_allocator, root, false);
        var edges: usize = 0;
        while (stack.items.len != 0) {
            const last = stack.items.len - 1;
            const frame = stack.items[last];
            const module = &self.session.units[frame.target.unit];
            const scheme = module.binding(frame.target.binding).scheme;
            if (frame.next == scheme.obligations.len) {
                visited.getPtr(frame.target).?.* = true;
                _ = stack.pop();
                continue;
            }
            stack.items[last].next += 1;
            edges += 1;
            if (edges > self.session.options.max_children) return false;
            const requirement = module.obligations[scheme.obligations.start + frame.next];
            if (requirement.kind == .callee_use) {
                const child = try self.schemeTarget(frame.target.unit, requirement.identity);
                if (visited.get(child)) |done| {
                    if (!done) return false;
                    continue;
                }
                if (visited.count() >= self.session.options.max_values) return false;
                try visited.put(self.scratch_allocator, child, false);
                try stack.append(self.scratch_allocator, .{ .target = child });
            } else {
                if (!requirement.explicit) return false;
                switch (requirement.kind) {
                    .dispatch, .result_dispatch, .field, .receiver, .update, .record_merge, .effect_operation, .type_eq, .contract, .type_rep, .effect_rep => {},
                    else => return false,
                }
            }
        }
        try self.session.specializations.call_summaries.checked_requirements.ensureUnusedCapacity(self.session.allocator, @intCast(visited.count()));
        var targets = visited.keyIterator();
        while (targets.next()) |target_| self.session.specializations.call_summaries.checked_requirements.putAssumeCapacity(target_.*, true);
        return true;
    }
    const SchemeFrame = struct {
        use: Constraint,
        key: SchemeInstance,
        copy: principal_type_graph.FrozenCopy,
        next: u32 = 0,
    };
    const SchemeImport = union(enum) { solved, open, frame: SchemeFrame };
    fn autonomousRowCarrier(self: *ClosureRegion, target_: Target, requirement: core.Obligation) bool {
        if (requirement.kind != .dispatch and requirement.kind != .result_dispatch and requirement.kind != .receiver and requirement.kind != .update) return false;
        if (requirement.signature == 0) return false;
        const module = &self.session.units[target_.unit];
        const carrier = module.types.node(requirement.signature);
        if (carrier.tag != .function or carrier.a != types.unit or carrier.b != types.unit) return false;
        const row = module.types.row(carrier.c);
        return row.labels.len == 0 and row.tail == .variable and std.mem.findScalar(u32, module.types.list(module.binding(target_.binding).public_rows), row.tail.variable) == null;
    }
    fn constantRequirements(self: *ClosureRegion, root: Target) RegionError!bool {
        if (self.session.specializations.call_summaries.constant_requirements.contains(root)) return true;
        if (self.session.specializations.call_summaries.constant_requirements.count() >= self.session.options.max_values) return false;
        const Header = struct { target: Target, next: u32 = 0 };
        var pending: std.ArrayList(Header) = .empty;
        defer pending.deinit(self.scratch_allocator);
        var visited: std.AutoHashMapUnmanaged(Target, bool) = .empty;
        defer visited.deinit(self.scratch_allocator);
        try visited.put(self.scratch_allocator, root, false);
        try pending.append(self.scratch_allocator, .{ .target = root });
        var edges: usize = 0;
        while (pending.items.len != 0) {
            const last = pending.items.len - 1;
            const frame = pending.items[last];
            const module = &self.session.units[frame.target.unit];
            const scheme = module.binding(frame.target.binding).scheme;
            if (frame.next == scheme.obligations.len) {
                visited.getPtr(frame.target).?.* = true;
                _ = pending.pop();
                continue;
            }
            pending.items[last].next += 1;
            edges += 1;
            if (edges > self.session.options.max_children) return false;
            const requirement = module.obligations[scheme.obligations.start + frame.next];
            if (requirement.kind == .callee_use) {
                const child = try self.schemeTarget(frame.target.unit, requirement.identity);
                if (!self.session.units[child.unit].binding(child.binding).has_explicit or self.session.specializations.call_summaries.constant_requirements.contains(child)) continue;
                if (visited.get(child)) |complete| {
                    if (!complete) return false;
                    continue;
                }
                if (visited.count() >= self.session.options.max_values) return false;
                try visited.put(self.scratch_allocator, child, false);
                try pending.append(self.scratch_allocator, .{ .target = child });
            } else if (requirement.explicit) {
                for ([_]types.Id{ requirement.ty, requirement.other, requirement.result, requirement.signature }) |operand| {
                    if (operand != 0 and operand == requirement.signature and self.autonomousRowCarrier(frame.target, requirement)) continue;
                    if (operand != 0 and !try self.session.specializations.closed_source_types.closed(self.session.allocator, self.session.units, frame.target.unit, operand, 0)) return false;
                }
            }
        }
        if (visited.count() > self.session.options.max_values -| self.session.specializations.call_summaries.constant_requirements.count()) return false;
        try self.session.specializations.call_summaries.constant_requirements.ensureUnusedCapacity(self.session.allocator, @intCast(visited.count()));
        var targets = visited.keyIterator();
        while (targets.next()) |target_| self.session.specializations.call_summaries.constant_requirements.putAssumeCapacity(target_.*, {});
        return true;
    }
    fn publicRequirementOperand(self: *ClosureRegion, target_: Target, root: types.Id, parts: *CallSummaries.HeaderParts) RegionError!bool {
        const module = &self.session.units[target_.unit];
        const binding = module.binding(target_.binding);
        const Part = union(enum) { ty: types.Id, row: types.Effects.Id };
        var pending: std.ArrayList(Part) = .empty;
        defer pending.deinit(self.scratch_allocator);
        var seen: std.AutoHashMapUnmanaged(u64, void) = .empty;
        defer seen.deinit(self.scratch_allocator);
        try pending.append(self.scratch_allocator, .{ .ty = root });
        while (pending.pop()) |part| {
            const key: u64 = switch (part) {
                .ty => |id| id,
                .row => |id| (@as(u64, 1) << 32) | id,
            };
            if (seen.contains(key)) continue;
            if (seen.count() >= self.session.options.max_values) return false;
            try seen.put(self.scratch_allocator, key, {});
            switch (part) {
                .row => |id| {
                    const row = module.types.row(id);
                    if (row.tail == .parameter) return false;
                    if (row.tail == .variable) {
                        if (std.mem.findScalar(u32, module.types.list(binding.public_rows), row.tail.variable)) |slot| {
                            parts.mask[binding.public_variables.len + slot] = true;
                        } else parts.has_private = true;
                    }
                    for (module.types.rowLabels(id)) |label| for (module.types.operationArguments(label)) |argument| try pending.append(self.scratch_allocator, .{ .ty = argument });
                },
                .ty => |id| {
                    const node = module.types.node(id);
                    switch (node.tag) {
                        .variable => {
                            if (std.mem.findScalar(types.Id, module.types.list(binding.public_variables), id)) |slot| {
                                parts.mask[slot] = true;
                            } else parts.has_private = true;
                        },
                        .instance_version, .forall, .existential, .bound, .rigid, .absent, .projection, .scoped, .instance_selection, .erased_proof => return false,
                        .unit, .boolean, .u32, .f32, .never, .type_constructor => {},
                        .usage, .array, .list, .cursor, .resolver => try pending.append(self.scratch_allocator, .{ .ty = node.a }),
                        .function, .demand, .provider => {
                            try pending.append(self.scratch_allocator, .{ .ty = node.a });
                            if (node.tag == .function) try pending.append(self.scratch_allocator, .{ .ty = node.b });
                            try pending.append(self.scratch_allocator, .{ .row = node.c });
                        },
                        .state_provider => for ([_]types.Id{ node.a, node.b, node.c }) |child| try pending.append(self.scratch_allocator, .{ .ty = child }),
                        .product, .nominal => {
                            const children = if (node.tag == .nominal) module.types.nominalArguments(node) else module.types.list(.{ .start = node.a, .len = node.b });
                            for (children) |child| try pending.append(self.scratch_allocator, .{ .ty = child });
                        },
                        .record => for (0..node.b) |i| try pending.append(self.scratch_allocator, .{ .ty = module.types.recordField(node, i).ty }),
                    }
                },
            }
            if (pending.items.len > self.session.options.max_values) return false;
        }
        return true;
    }
    fn publicRequirements(self: *ClosureRegion, root: Target) RegionError!?CallSummaries.HeaderParts {
        const store = &self.session.specializations.call_summaries;
        if (store.public_requirements.get(root)) |known| return known;
        if (store.public_requirements.count() >= self.session.options.max_values) return null;
        const Header = struct { target: Target, next: u32 = 0 };
        const Parts = struct { header: CallSummaries.HeaderParts, complete: bool = false };
        var pending: std.ArrayList(Header) = .empty;
        defer pending.deinit(self.scratch_allocator);
        var visited: std.AutoHashMapUnmanaged(Target, Parts) = .empty;
        var published = false;
        defer {
            if (!published) {
                var parts = visited.valueIterator();
                while (parts.next()) |part| self.session.allocator.free(part.header.mask);
            }
            visited.deinit(self.scratch_allocator);
        }
        const binding = self.session.units[root.unit].binding(root.binding);
        var slots = std.math.add(usize, binding.public_variables.len, binding.public_rows.len) catch return null;
        if (slots > self.session.options.max_children -| store.public_requirement_slots) return null;
        const first = try self.session.allocator.alloc(bool, slots);
        @memset(first, false);
        visited.put(self.scratch_allocator, root, .{ .header = .{ .mask = first } }) catch |err| {
            self.session.allocator.free(first);
            return err;
        };
        try pending.append(self.scratch_allocator, .{ .target = root });
        var edges: usize = 0;
        while (pending.items.len != 0) {
            const last = pending.items.len - 1;
            const frame = pending.items[last];
            const module = &self.session.units[frame.target.unit];
            const scheme = module.binding(frame.target.binding).scheme;
            if (frame.next == scheme.obligations.len) {
                visited.getPtr(frame.target).?.complete = true;
                _ = pending.pop();
                continue;
            }
            edges += 1;
            if (edges > self.session.options.max_children) return null;
            const requirement = module.obligations[scheme.obligations.start + frame.next];
            if (requirement.kind == .callee_use) {
                const child = try self.schemeTarget(frame.target.unit, requirement.identity);
                const child_binding = self.session.units[child.unit].binding(child.binding);
                if (!child_binding.has_explicit) {
                    pending.items[last].next += 1;
                    continue;
                }
                const child_parts: CallSummaries.HeaderParts = if (store.public_requirements.get(child)) |known| known else if (visited.get(child)) |known| blk: {
                    if (!known.complete) return null;
                    break :blk known.header;
                } else {
                    if (visited.count() >= self.session.options.max_values -| store.public_requirements.count()) return null;
                    const count = std.math.add(usize, child_binding.public_variables.len, child_binding.public_rows.len) catch return null;
                    if (count > self.session.options.max_children -| store.public_requirement_slots -| slots) return null;
                    const mask = try self.session.allocator.alloc(bool, count);
                    @memset(mask, false);
                    visited.put(self.scratch_allocator, child, .{ .header = .{ .mask = mask } }) catch |err| {
                        self.session.allocator.free(mask);
                        return err;
                    };
                    slots += count;
                    try pending.append(self.scratch_allocator, .{ .target = child });
                    continue;
                };
                const product = module.types.node(requirement.ty);
                if (product.tag != .product or product.b != child_parts.mask.len) return error.UnresolvedType;
                const parts = &visited.getPtr(frame.target).?.header;
                parts.has_private = parts.has_private or child_parts.has_private;
                for (module.types.list(.{ .start = product.a, .len = product.b }), child_parts.mask) |operand, consumed| {
                    if (consumed and !try self.publicRequirementOperand(frame.target, operand, parts)) return null;
                }
            } else if (requirement.explicit) {
                // Open private binders keep fresh work. A closed public
                // instantiation may share the header's required constraints,
                // just as the original complete-public key does.
                for ([_]types.Id{ requirement.ty, requirement.other, requirement.result, requirement.signature }) |operand| {
                    if (operand != 0 and operand == requirement.signature and self.autonomousRowCarrier(frame.target, requirement)) continue;
                    if (operand != 0 and !try self.publicRequirementOperand(frame.target, operand, &visited.getPtr(frame.target).?.header)) return null;
                }
            }
            pending.items[last].next += 1;
        }
        if (visited.count() > self.session.options.max_values -| store.public_requirements.count()) return null;
        try store.public_requirements.ensureUnusedCapacity(self.session.allocator, @intCast(visited.count()));
        var targets = visited.iterator();
        while (targets.next()) |entry| store.public_requirements.putAssumeCapacity(entry.key_ptr.*, entry.value_ptr.header);
        store.public_requirement_slots += slots;
        published = true;
        return store.public_requirements.get(root).?;
    }
    fn schemeInputs(self: *ClosureRegion, target_: Target, root: types.Id, header: CallSummaries.HeaderParts) RegionError!u32 {
        const binding = self.session.units[target_.unit].binding(target_.binding);
        const product = self.solver.node(try self.solver.resolve(root, 0));
        if (product.tag != .product or product.b != header.mask.len) return error.UnresolvedType;
        // Resolution may grow the solver's side arrays. Keep an owned copy of
        // the slot handles, and use exact live IDs rather than alpha equality.
        var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.scratch_allocator);
        const temporary = scratch.allocator();
        const instance = try temporary.dupe(types.Id, self.solver.list(.{ .start = product.a, .len = product.b }));
        defer temporary.free(instance);
        var parts: std.ArrayList(u32) = .empty;
        defer parts.deinit(self.scratch_allocator);
        for (instance, header.mask, 0..) |operand, consumed, slot| {
            if (!consumed) continue;
            const actual = try self.solver.resolve(operand, 0);
            if (slot < binding.public_variables.len) {
                const closed = try self.project(actual);
                if (header.has_private and closed == 0) return 0;
                try parts.appendSlice(self.scratch_allocator, &.{ if (closed == 0) 0 else 2, if (closed == 0) actual else closed });
            } else {
                const carrier = self.solver.node(actual);
                if (carrier.tag != .function or carrier.a != types.unit or carrier.b != types.unit) return error.UnresolvedType;
                const row = try self.solver.resolveEffects(carrier.c, 0);
                const view = self.solver.row(row);
                if (header.has_private and view.tail != .closed) return 0;
                const closed = if (view.tail == .closed) self.session.storage.evidence.projectEffects(&self.solver, row, &.{}, &.{}) catch |err| switch (err) {
                    error.UnresolvedType => 0,
                    else => return err,
                } else 0;
                if (header.has_private and closed == 0 and row != 0) return 0;
                if (view.tail == .closed and (closed != 0 or row == 0)) {
                    try parts.appendSlice(self.scratch_allocator, &.{ 3, closed });
                    continue;
                }
                try parts.appendSlice(self.scratch_allocator, &.{ 1, view.cursor, @backingInt(std.meta.activeTag(view.tail)), switch (view.tail) {
                    .closed => 0,
                    .variable => |variable| variable,
                    .parameter => |parameter| parameter,
                    .formal => |formal| formal,
                }, view.labels.len });
                try parts.appendSlice(self.scratch_allocator, self.solver.rowLabels(row));
            }
            if (parts.items.len > self.session.options.max_children) return 0;
        }
        const key = std.mem.sliceAsBytes(parts.items);
        const inputs = &self.scratch.scheme_inputs;
        if (inputs.keys.get(key)) |known| return known;
        if (inputs.keys.count() >= self.session.options.max_values or inputs.keys.count() == std.math.maxInt(u32) or parts.items.len > self.session.options.max_children -| inputs.parts) return 0;
        const owned = try self.scratch_allocator.dupe(u8, key);
        errdefer self.scratch_allocator.free(owned);
        try inputs.keys.ensureUnusedCapacity(self.scratch_allocator, 1);
        const id: u32 = @intCast(inputs.keys.count() + 1);
        inputs.keys.putAssumeCapacity(owned, id);
        inputs.parts += parts.items.len;
        return id;
    }
    fn schemeImport(self: *ClosureRegion, use: Constraint) RegionError!SchemeImport {
        const public = try self.project(use.left);
        const cacheable = self.solver.closed_generation != std.math.maxInt(u16) and self.solver.effects.physical_epoch != std.math.maxInt(u64);
        const constant = public == 0 and try self.constantRequirements(use.target);
        const open = if (cacheable and public == 0 and !constant) blk: {
            const mask = try self.publicRequirements(use.target) orelse break :blk 0;
            break :blk try self.schemeInputs(use.target, use.left, mask);
        } else 0;
        const key: SchemeInstance = .{ .target = use.target, .public = if (cacheable) public else 0, .deferred_member = use.deferred_member, .open = open, .constant = cacheable and constant, .physical = self.solver.effects.physical_epoch, .generation = self.solver.closed_generation };
        if ((key.public != 0 or key.open != 0 or key.constant) and self.scratch.scheme_instances.contains(key)) return .solved;
        const module = &self.session.units[use.target.unit];
        const binding = module.binding(use.target.binding);
        const product = self.solver.node(try self.solver.resolve(use.left, 0));
        if (product.tag != .product or product.b != binding.public_variables.len + binding.public_rows.len) return error.UnresolvedType;
        var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.scratch_allocator);
        const temporary = scratch.allocator();
        const instance = try temporary.dupe(types.Id, self.solver.list(.{ .start = product.a, .len = product.b }));
        defer temporary.free(instance);
        var copy: principal_type_graph.FrozenCopy = .{ .allocator = self.scratch_allocator, .source = &module.types, .destination = &self.solver, .max_depth = self.session.options.max_type_depth, .max_nodes = self.session.options.max_values };
        errdefer copy.deinit();
        for (module.types.list(binding.public_variables), instance[0..binding.public_variables.len]) |variable, actual| {
            try copy.types.put(self.scratch_allocator, variable, actual);
            try copy.variables.put(self.scratch_allocator, module.types.node(variable).a, actual);
        }
        for (module.types.list(binding.public_rows), instance[binding.public_variables.len..]) |variable, carrier| try copy.row_variables.put(self.scratch_allocator, variable, self.solver.node(carrier).c);
        // An entirely unknown written graph remains a residual edge in the
        // optional inquiry. Known endpoints still receive ordinary checking.
        if (self.partial_principal and public == 0 and !constant) {
            var unknown = true;
            for (instance[0..binding.public_variables.len]) |ty| unknown = unknown and self.solver.node(try self.solver.resolve(ty, 0)).tag == .variable;
            for (instance[binding.public_variables.len..]) |ty| {
                const carrier = self.solver.node(try self.solver.resolve(ty, 0));
                const row = self.solver.row(try self.solver.resolveEffects(carrier.c, 0));
                unknown = unknown and row.labels.len == 0 and row.tail != .parameter;
            }
            if (unknown and try self.retainOpenPrincipal(.{ .target = use.target, .scope = use.scope, .node = use.node, .left = try copy.ty(binding.scheme.root, 0), .result = 0, .deferred_member = use.deferred_member })) {
                self.principal_only_used = true;
                self.session.principal_graph_deferred += 1;
                self.session.counters.principal_graph_deferred += 1;
                copy.deinit();
                return .open;
            }
        }
        return .{ .frame = .{ .use = use, .key = key, .copy = copy } };
    }
    fn solveSchemeUse(self: *ClosureRegion, index: usize) RegionError!SummaryProgress {
        const first = try self.schemeImport(self.scratch.constraints.items[index]);
        switch (first) {
            .open => return .open,
            .solved => {
                self.scratch.constraints.items[index].solved = true;
                return .solved;
            },
            .frame => {},
        }
        var pending: std.ArrayList(SchemeFrame) = .empty;
        defer {
            for (pending.items) |*frame| frame.copy.deinit();
            pending.deinit(self.scratch_allocator);
        }
        pending.append(self.scratch_allocator, first.frame) catch |err| {
            var failed = first.frame;
            failed.copy.deinit();
            return err;
        };
        // Header leaves retain their ordinary source order ahead of body
        // constraints. A graph edge must not postpone an earlier witness until
        // after a duplicate requirement collected from the callee's body.
        var edges: usize = 0;
        while (pending.items.len != 0) {
            const last = pending.items.len - 1;
            const use = pending.items[last].use;
            const module = &self.session.units[use.target.unit];
            const scheme = module.binding(use.target.binding).scheme;
            if (pending.items[last].next == scheme.obligations.len) {
                const key = pending.items[last].key;
                if (key.public != 0 or key.open != 0 or key.constant) try self.scratch.scheme_instances.put(self.scratch_allocator, key, {});
                var done = pending.pop().?;
                done.copy.deinit();
                continue;
            }
            edges += 1;
            if (edges > self.session.options.max_children or pending.items.len > self.session.options.max_values) return error.TypeLimit;
            const requirement = module.obligations[scheme.obligations.start + pending.items[last].next];
            pending.items[last].next += 1;
            if (requirement.kind == .callee_use) {
                const target_ = try self.schemeTarget(use.target.unit, requirement.identity);
                if (!self.session.units[target_.unit].binding(target_.binding).has_explicit) continue;
                // Checked recursive components flatten their internal header
                // uses. A cyclic retained header is malformed, not a proof.
                for (pending.items) |active| if (std.meta.eql(active.use.target, target_)) return error.TypeLimit;
                const child: Constraint = .{ .scope = use.scope, .node = use.node, .span = use.span, .kind = .scheme_use, .target = target_, .left = try pending.items[last].copy.ty(requirement.ty, 0), .result = 0, .deferred_member = use.deferred_member };
                const imported = try self.schemeImport(child);
                switch (imported) {
                    .open => try self.appendConstraint(child),
                    .solved => {},
                    .frame => pending.append(self.scratch_allocator, imported.frame) catch |err| {
                        var failed = imported.frame;
                        failed.copy.deinit();
                        return err;
                    },
                }
            } else {
                if (!requirement.explicit) continue;
                const kind: ConstraintKind = switch (requirement.kind) {
                    .dispatch => .binary,
                    .result_dispatch => .result_dispatch,
                    .field => .physical_field,
                    .receiver => .receiver,
                    .update => .update,
                    .record_merge => .record_merge,
                    .effect_operation => .effect_operation,
                    .type_eq => .type_eq,
                    .contract => .contract,
                    .type_rep => .type_rep,
                    .effect_rep => .effect_rep,
                    else => return error.UnresolvedType,
                };
                try self.appendConstraint(.{ .scope = use.scope, .node = use.node, .span = use.span, .kind = kind, .explicit = true, .qualification_span = requirement.qualification_span, .qualification_unit = requirement.qualification_unit, .diagnostic_name = module.name(requirement.diagnostic_name), .left = try pending.items[last].copy.ty(requirement.ty, 0), .right = try pending.items[last].copy.ty(requirement.other, 0), .result = try pending.items[last].copy.ty(requirement.result, 0), .signature = try pending.items[last].copy.ty(requirement.signature, 0), .member = requirement.name, .op = requirement.operator, .identity = .{ .unit = if (requirement.identity.unit == 0) self.session.unitId(use.target.unit) else requirement.identity.unit, .decl = requirement.identity.decl }, .row_carrier = requirement.kind == .dispatch or requirement.kind == .result_dispatch or requirement.kind == .receiver or requirement.kind == .update });
            }
        }
        self.scratch.constraints.items[index].solved = true;
        return .solved;
    }
    fn registerBodyScope(self: *ClosureRegion, scope: u32) RegionError!void {
        const source = self.scratch.sources.items[scope];
        if (source.body_collected or source.value != 0 or source.binding == 0) return;
        const module = &self.session.units[source.owner];
        if (module.binding(source.binding).kind != .global) return;
        try self.scratch.target_scopes.put(self.scratch_allocator, .{ .unit = source.owner, .binding = source.binding }, scope);
        self.scratch.sources.items[scope].body_collected = true;
    }
    fn bodyEdge(self: *ClosureRegion, caller: u32, callee: u32) RegionError!void {
        self.scratch.sources.items[callee].origin = self.current_origin;
        self.scratch.sources.items[callee].implementation_context = self.current_implementation_context;
        const before = self.component_work;
        if (try self.scratch.components.add(self.scratch_allocator, caller, callee, self.scratch.sources.items.len, &self.component_work, self.session.options.max_children)) self.work_revision +|= 1;
        _ = self.session.summaryCharge(self.component_work - before);
    }
    fn recursiveBodyScope(self: *ClosureRegion, caller: u32, target_: Target, signature: types.Id) RegionError!?u32 {
        if (!self.scratch.target_scopes.contains(target_)) return null;
        const actual = try self.project(signature);
        const before = self.component_work;
        defer _ = self.session.summaryCharge(self.component_work - before);
        try self.scratch.components.beginAncestors(self.scratch_allocator, caller, self.scratch.sources.items.len);
        var candidate: ?u32 = null;
        while (try self.scratch.components.nextAncestor(self.scratch_allocator, &self.component_work, self.session.options.max_children)) |scope| {
            const source = self.scratch.sources.items[scope];
            if (!source.body_collected or source.value != 0 or source.owner != target_.unit or source.binding != target_.binding) continue;
            // Checked polymorphic recursion retains distinct closed instances.
            // Open recursive uses share the same ordinary monomorphic root.
            if (actual != 0 and try self.project(source.root) != actual) continue;
            if (candidate == null or candidate.? < scope) candidate = scope;
        }
        return candidate;
    }
    fn collectInlineCall(self: *ClosureRegion, caller: u32, target_: Target, callee_type: types.Id, arguments: []const core.Id) RegionError!void {
        try self.session.observePrincipalSource(target_.unit, target_.binding);
        const module = &self.session.units[target_.unit];
        const binding = module.binding(target_.binding);
        const definition = module.body(target_.binding);
        const body_root = if (definition) |body| body.root else binding.initializer;
        const source_type = if (definition) |body| body.scheme.root else binding.scheme.root;
        const lexical_caller: u32 = if (definition == null) caller + 1 else 0;
        const instantiated = try self.importType(caller, callee_type, 0);
        if (self.session.receipt_tape) |tape| if (binding.kind == .global)
            try tape.sources.append(self.session.allocator, .{ .unit = self.session.unitId(target_.unit), .binding = target_.binding });
        if (try self.recursiveBodyScope(caller, target_, instantiated)) |prior| {
            _ = try self.admitSignature(instantiated, self.scratch.sources.items[prior].root);
            try self.bodyEdge(caller, prior);
            self.session.counters.call_memo_hits += 1;
            return;
        }
        const scope = try self.typeScope(target_.unit);
        self.scratch.sources.items[scope].body = body_root;
        self.scratch.sources.items[scope].binding = target_.binding;
        self.scratch.sources.items[scope].closed_rows = if (definition) |body| body.closed_rows else if (module.node(body_root).tag == .closure) module.closure(body_root).closed_rows else binding.scheme.closed_rows;
        self.setSourceRoot(scope, try self.importType(scope, source_type, 0));
        try self.importScheme(scope, binding.scheme, body_root);
        if (self.source_interface) {
            var formal = self.scratch.sources.items[scope].root;
            const caller_module = &self.session.units[self.scratch.sources.items[caller].owner];
            for (arguments) |argument| {
                const arrow = self.solver.node(try self.solver.resolve(formal, 0));
                if (arrow.tag != .function) break;
                const actual = try self.importType(caller, caller_module.typeOf(argument), 0);
                // Bottom remains ordinary control flow in the solver. Witness
                // selection owns this exact applied argument separately.
                if (self.solver.node(try self.solver.resolve(actual, 0)).tag == .never)
                    try self.scratch.witness_inputs.put(self.scratch_allocator, arrow.a, actual);
                formal = arrow.b;
            }
        }
        if (definition == null) {
            if (module.node(body_root).tag == .closure) {
                for (module.closureCaptures(body_root)) |capture| _ = try self.importType(scope, module.binding(capture).ty, 0);
            }
            try self.shareLexical(scope, caller, binding.scheme);
        }
        _ = try self.admitSignature(instantiated, self.scratch.sources.items[scope].root);
        try self.bodyEdge(caller, scope);
        const actual = try self.project(self.scratch.sources.items[scope].root);
        if (actual != 0) {
            const key: CallKey = .{ .owner = target_.unit, .binding = target_.binding, .evidence = actual, .caller = lexical_caller };
            if (self.scratch.call_instances.get(key)) |prior| {
                self.session.counters.call_memo_hits += 1;
                _ = try self.admitSignature(instantiated, self.scratch.sources.items[prior].root);
                try self.bodyEdge(caller, prior);
                return;
            }
            try self.scratch.call_instances.put(self.scratch_allocator, key, scope);
            self.session.counters.call_collections_closed += 1;
            try self.collectWithExit(scope, body_root, .{ .lexical_caller = if (definition == null) caller else null, .lexical_scheme = binding.scheme });
        } else {
            if (self.scratch.unresolved_calls.get(target_)) |active| {
                // Recursive uses share the active monomorphic inference root.
                // Closed instances keep their separate evidence-keyed cache.
                _ = try self.admitSignature(instantiated, self.scratch.sources.items[active].root);
                try self.bodyEdge(caller, active);
                return;
            }
            try self.scratch.unresolved_calls.put(self.scratch_allocator, target_, scope);
            self.session.counters.call_collections_unresolved += 1;
            try self.collectWithExit(scope, body_root, .{ .remove = target_, .lexical_caller = if (definition == null) caller else null, .lexical_scheme = binding.scheme });
        }
    }
    /// Jobs own their solver variables. A body with result-directed or
    /// externally supplied evidence must keep the caller's inference scope.
    fn summaryEligible(self: *ClosureRegion, target_: Target) RegionError!bool {
        if (self.scratch.unresolved_calls.contains(target_)) return false;
        if (self.session.specializations.call_summaries.draining and !self.summary_job) return false;
        if (!try self.summaryShapeEligible(target_)) return false;
        if (self.session.specializations.call_summaries.eligibility.get(target_)) |known| return known;
        return self.checkSummaryEligibility(target_);
    }
    fn summaryShapeEligible(self: *ClosureRegion, target_: Target) RegionError!bool {
        const module = &self.session.units[target_.unit];
        const body = module.body(target_.binding) orelse return false;
        if (!body.is_function or body.parameters.len == 0) return false;
        var arrow_type = body.scheme.root;
        for (0..body.parameters.len) |_| {
            const arrow = module.types.node(arrow_type);
            if (arrow.tag != .function or !try self.potentialSummaryValue(target_.unit, arrow.a, 0)) return false;
            arrow_type = arrow.b;
        }
        return self.potentialSummaryValue(target_.unit, arrow_type, 0);
    }
    fn higherOrderBody(self: *ClosureRegion, target_: Target) bool {
        const module = &self.session.units[target_.unit];
        const body = module.body(target_.binding) orelse return false;
        var cursor = body.scheme.root;
        for (0..body.parameters.len) |_| {
            const arrow = module.types.node(cursor);
            if (arrow.tag != .function) return false;
            if (module.types.node(arrow.a).tag == .function) return true;
            cursor = arrow.b;
        }
        return module.types.node(cursor).tag == .function;
    }
    fn completeCallbackInputs(self: *ClosureRegion, target_: Target, actual: types.Id) RegionError!bool {
        const module = &self.session.units[target_.unit];
        const body = module.body(target_.binding) orelse return false;
        var source = body.scheme.root;
        var cursor = actual;
        for (0..body.parameters.len) |_| {
            const arrow = module.types.node(source);
            const supplied = self.solver.node(try self.solver.resolve(cursor, 0));
            if (arrow.tag != .function or supplied.tag != .function) return false;
            if (module.types.node(arrow.a).tag == .function and try self.project(supplied.a) == 0) return false;
            source = arrow.b;
            cursor = supplied.b;
        }
        return true;
    }
    fn checkSummaryEligibility(self: *ClosureRegion, target_: Target) RegionError!bool {
        const Candidate = struct { target: Target, bad: bool = false, parents: u32 = std.math.maxInt(u32) };
        const Parent = struct { index: u32, next: u32 };
        const a = self.session.allocator;
        const limit = @min(self.session.options.max_values, std.math.maxInt(u32));
        if (limit == 0) return false;
        var nodes: std.ArrayList(Candidate) = .empty;
        defer nodes.deinit(a);
        var indices: std.AutoHashMapUnmanaged(Target, u32) = .empty;
        defer indices.deinit(a);
        var edges: std.ArrayList(Parent) = .empty;
        defer edges.deinit(a);
        var pending: std.ArrayList(u32) = .empty;
        defer pending.deinit(a);
        try nodes.append(a, .{ .target = target_ });
        try indices.put(a, target_, 0);
        var index: usize = 0;
        while (index < nodes.items.len) : (index += 1) {
            if (@import("builtin").is_test) self.session.summary_eligibility_visits += 1;
            const target = nodes.items[index].target;
            const unit = &self.session.units[target.unit];
            const scheme = unit.binding(target.binding).scheme;
            for (unit.obligations[scheme.obligations.start..][0..scheme.obligations.len]) |requirement| {
                if (requirement.explicit) {
                    nodes.items[index].bad = true;
                    continue;
                }
                switch (requirement.kind) {
                    .dispatch, .field, .writable_field, .receiver, .collection, .record_merge, .update, .effect_operation, .effect_handler, .type_head, .type_rep, .effect_rep => {},
                    .callee_use => {
                        const child = try self.session.external(.{ .unit = target.unit, .binding = requirement.identity.decl });
                        if (self.session.specializations.call_summaries.eligibility.get(child)) |eligible| {
                            if (!eligible) nodes.items[index].bad = true;
                            continue;
                        }
                        const entry = try indices.getOrPut(a, child);
                        if (!entry.found_existing) {
                            if (nodes.items.len >= limit) return false;
                            entry.value_ptr.* = @intCast(nodes.items.len);
                            try nodes.append(a, .{ .target = child });
                        }
                        const child_index = entry.value_ptr.*;
                        if (edges.items.len >= limit) return false;
                        const edge_index: u32 = @intCast(edges.items.len);
                        try edges.append(a, .{ .index = @intCast(index), .next = nodes.items[child_index].parents });
                        nodes.items[child_index].parents = edge_index;
                    },
                    else => nodes.items[index].bad = true,
                }
            }
        }
        for (nodes.items, 0..) |candidate, i| if (candidate.bad) try pending.append(a, @intCast(i));
        while (pending.pop()) |child| {
            var edge = nodes.items[child].parents;
            while (edge != std.math.maxInt(u32)) {
                const parent = edges.items[edge];
                if (!nodes.items[parent.index].bad) {
                    nodes.items[parent.index].bad = true;
                    try pending.append(a, parent.index);
                }
                edge = parent.next;
            }
        }
        // Every reachable component is now classified. A bad descendant only
        // declines its ancestors, never an unrelated valid sibling.
        try self.session.specializations.call_summaries.eligibility.ensureUnusedCapacity(a, @intCast(nodes.items.len));
        for (nodes.items) |candidate| self.session.specializations.call_summaries.eligibility.putAssumeCapacity(candidate.target, !candidate.bad);
        return !nodes.items[0].bad;
    }
    fn summaryInputs(self: *ClosureRegion, constraint: Constraint) RegionError!type_evidence.Id {
        const parameters = if (constraint.lexical_key != 0) self.session.specializations.lexical_inputs.inputs.items[constraint.lexical_key - 1].parameters else self.session.units[constraint.target.unit].body(constraint.target.binding).?.parameters.len;
        var arguments: std.ArrayList(type_evidence.Id) = .empty;
        defer arguments.deinit(self.session.allocator);
        var cursor = constraint.left;
        for (0..parameters) |_| {
            const arrow = self.solver.node(try self.solver.resolve(cursor, 0));
            if (arrow.tag != .function) return 0;
            const actual = try self.project(arrow.a);
            if (actual == 0 or !try self.summaryValue(actual, 0)) return 0;
            if (self.source_interface and self.session.storage.evidence.node(actual).tag == .never) return 0;
            try arguments.append(self.session.allocator, actual);
            cursor = arrow.b;
        }
        return self.session.storage.evidence.intern(.product, 0, 0, arguments.items);
    }
    const SummaryProgress = enum { solved, waiting, open };
    fn solveSummary(self: *ClosureRegion, index: usize) RegionError!SummaryProgress {
        const constraint = self.scratch.constraints.items[index];
        if (constraint.principal_only) {
            if (self.partial_principal and try self.retainOpenPrincipal(constraint)) return .open;
            if (try self.resultPrincipalEligible(constraint.target, constraint.deferred_member)) {
                const body = self.session.units[constraint.target.unit].body(constraint.target.binding).?;
                var result = constraint.left;
                for (0..body.parameters.len) |_| {
                    const arrow = self.solver.node(try self.solver.resolve(result, 0));
                    if (arrow.tag != .function) return error.UnresolvedType;
                    result = arrow.b;
                }
                // The destination chooses the implementation. Leave this
                // edge in the caller until that destination has an owner;
                // another edge may supply it without expanding a diamond.
                if (self.solver.node(try self.solver.resolve(result, 0)).tag == .variable) return .open;
                const expected = try self.project(result);
                if (expected != 0) {
                    const complete = try self.project(constraint.left);
                    const signature = if (complete != 0 and try self.firstOrderArrow(complete)) complete else 0;
                    const key: CallSummaries.Key = .{ .target = constraint.target, .inputs = 0, .source_interface = self.source_interface, .expected_result = if (signature == 0) expected else 0, .expected_signature = signature, .deferred_member = constraint.deferred_member, .options = self.session.options };
                    const job = try self.session.specializations.call_summaries.request(self.session, key);
                    if (job) |entry| switch (entry.state) {
                        .queued, .running, .waiting => return .waiting,
                        .complete => {
                            const arrow = try self.importEvidence(entry.result, 0);
                            const point = self.solver.mark();
                            _ = self.admitSignature(constraint.left, arrow) catch |err| {
                                self.solver.rollback(point);
                                if (err == error.OutOfMemory) return err;
                                self.scratch.constraints.items[index].solved = true;
                                try self.expandSummary(constraint);
                                return .solved;
                            };
                            self.scratch.constraints.items[index].solved = true;
                            self.session.counters.call_memo_hits += 1;
                            return .solved;
                        },
                        .declined => {},
                    };
                }
            }
            // Result-directed relationships are never submitted to the
            // independent input-only job key, even after inputs become known.
            self.scratch.constraints.items[index].solved = true;
            try self.expandSummary(constraint);
            return .solved;
        }
        const inputs = try self.summaryInputs(constraint);
        if (inputs == 0) return .open;
        const key: CallSummaries.Key = .{ .target = constraint.target, .inputs = inputs, .source_interface = self.source_interface, .lexical = constraint.lexical_key, .deferred_member = constraint.deferred_member, .options = self.session.options };
        const job = try self.session.specializations.call_summaries.request(self.session, key);
        if (job) |entry| switch (entry.state) {
            .queued, .running, .waiting => return .waiting,
            .complete => {
                const target: core.BindingRef = .{ .unit = self.session.unitId(constraint.target.unit), .binding = constraint.target.binding };
                if (constraint.lexical_key != 0) {
                    const actual = try self.importEvidence(entry.result, 0);
                    const point = self.solver.mark();
                    _ = self.admitSignature(constraint.left, actual) catch |err| {
                        self.solver.rollback(point);
                        if (err == error.OutOfMemory) return err;
                        // The caller's expected result/row never entered this
                        // job. Its original body owns a rejected-use diagnostic.
                        self.scratch.constraints.items[index].solved = true;
                        try self.expandSummary(constraint);
                        return .solved;
                    };
                    self.scratch.constraints.items[index].solved = true;
                    self.session.counters.call_memo_hits += 1;
                    return .solved;
                }
                if (!self.source_interface) if (self.session.receipt_tape) |tape| {
                    try tape.sources.append(self.session.allocator, target);
                    try tape.call_reads.append(self.session.allocator, .{ .unit = target.unit, .binding = target.binding, .evidence = entry.result, .present = true });
                };
                // A job drained under this recorder is part of the recorded
                // region: its reads, publications and consumed jobs are here.
                if (!self.source_interface) if (self.session.principal_reads) |reads| if ((entry.recorded == 0 or entry.recorded != reads.serial) and !reads.calls_seen.contains(.{ .target = target, .evidence = entry.result })) {
                    if (self.session.specializations.validated_calls.contains(.{ .target = constraint.target, .evidence = entry.result })) {
                        try reads.callRead(self.session.allocator, target, entry.result, true);
                    } else if (CallSummaries.observation(self.session, entry.key, entry.result)) |fact| {
                        try reads.summaryRead(self.session.allocator, fact);
                    } else reads.invalidate(.call_read);
                };
                _ = try self.admitSignature(constraint.left, try self.importEvidence(entry.result, 0));
                self.scratch.constraints.items[index].solved = true;
                self.session.counters.call_memo_hits += 1;
                return .solved;
            },
            .declined => {},
        };
        self.scratch.constraints.items[index].solved = true;
        try self.expandSummary(constraint);
        return .solved;
    }
    fn expandSummary(self: *ClosureRegion, constraint: Constraint) RegionError!void {
        const saved = self.defer_members;
        self.defer_members = constraint.deferred_member;
        defer self.defer_members = saved;
        // Open summaries may be expanded outside attemptConstraint, after the
        // traversal has restored its previous source location. Carry the
        // recorded use into the newly collected callee scope.
        const previous_origin = self.current_origin;
        self.current_origin = constraint.origin orelse self.scratch.sources.items[constraint.scope].origin orelse previous_origin;
        defer self.current_origin = previous_origin;
        if (constraint.lexical_key != 0) return self.collect(constraint.scope, constraint.node);
        if (constraint.source_selection) {
            const scope = try self.callableScope(constraint.target);
            _ = try self.admitSignature(constraint.left, self.scratch.sources.items[scope].root);
            try self.collectSelected(constraint.scope, scope, constraint.target);
            return;
        }
        // Argument IDs are consumed before collecting any nested call that
        // could grow this scratch list. They retain the original witness sites.
        const arguments = self.scratch.summary_arguments.items[constraint.arguments.start..][0..constraint.arguments.len];
        try self.collectInlineCall(constraint.scope, constraint.target, constraint.right, arguments);
    }
    fn expandOpenSummaries(self: *ClosureRegion, allow_remaining: bool) RegionError!bool {
        const limit = self.scratch.constraints.items.len;
        var changed = false;
        for (0..limit) |index| {
            const constraint = self.scratch.constraints.items[index];
            if (constraint.solved or constraint.kind != .call_summary) continue;
            if (constraint.lexical_key == 0 and allow_remaining and try self.retainOpenPrincipal(constraint)) {
                self.session.principal_graph_deferred += 1;
                self.session.counters.principal_graph_deferred += 1;
                self.principal_only_used = true;
                const key: PrincipalGraph.Key = .{ .target = constraint.target, .source_interface = self.source_interface, .deferred_member = constraint.deferred_member, .options = self.session.options };
                if ((try self.principalGraphForKey(key)).?.source_complete) {
                    self.scratch.constraints.items[index].solved = true;
                    changed = true;
                }
                continue;
            }
            self.scratch.constraints.items[index].solved = true;
            try self.expandSummary(constraint);
            changed = true;
        }
        return changed;
    }
    fn beginSummary(self: *ClosureRegion, key: CallSummaries.Key) RegionError!u32 {
        self.summary_job = true;
        self.result_summary_job = self.result_summary_job or key.expected_result != 0 or key.expected_signature != 0;
        self.principal_result_job = self.principal_result_job or key.expected_result != 0;
        self.source_interface = key.source_interface;
        self.defer_members = key.deferred_member;
        self.include_callables = true;
        const scope = if (key.lexical != 0) try self.lexicalScope(key.lexical) else try self.callableScope(key.target);
        var cursor = self.scratch.sources.items[scope].root;
        if (key.expected_signature != 0) {
            // Every domain, result and operation row belongs to the complete
            // key. Normal operand selection is safe in this independent job;
            // it never guesses a caller's still-open input or ambient row.
            try self.unify(cursor, try self.importEvidence(key.expected_signature, 0));
            try self.scratch.unresolved_calls.put(self.scratch_allocator, key.target, scope);
            try self.collect(scope, self.scratch.sources.items[scope].body);
            return scope;
        }
        if (key.expected_result != 0) {
            const body = self.session.units[key.target.unit].body(key.target.binding).?;
            for (0..body.parameters.len) |_| {
                const arrow = self.solver.node(try self.solver.resolve(cursor, 0));
                if (arrow.tag != .function) return error.UnresolvedType;
                cursor = arrow.b;
            }
            // Quantified inputs remain fresh in this solver. A destination can
            // prove their types through the selected source constructor, but
            // operand dispatch must never guess an unselected input.
            try self.unify(cursor, try self.importEvidence(key.expected_result, 0));
            try self.scratch.unresolved_calls.put(self.scratch_allocator, key.target, scope);
            try self.collect(scope, self.scratch.sources.items[scope].body);
            return scope;
        }
        // The input evidence is copied into this solver; no caller-owned
        // inference variable or result expectation enters the job.
        const inputs = try self.session.allocator.dupe(type_evidence.Id, self.session.storage.evidence.children(key.inputs));
        defer self.session.allocator.free(inputs);
        for (inputs) |input| {
            const arrow = self.solver.node(try self.solver.resolve(cursor, 0));
            if (arrow.tag != .function) return error.UnresolvedType;
            try self.unify(arrow.a, try self.importEvidence(input, 0));
            cursor = arrow.b;
        }
        if (key.lexical == 0) try self.scratch.unresolved_calls.put(self.scratch_allocator, key.target, scope);
        try self.collect(scope, self.scratch.sources.items[scope].body);
        return scope;
    }
    fn lexicalScope(self: *ClosureRegion, lexical: u32) RegionError!u32 {
        self.lexical_summary_job = lexical;
        const input = self.session.specializations.lexical_inputs.inputs.items[lexical - 1];
        const owner = self.session.findUnit(input.unit, null) orelse return error.UnresolvedType;
        const module = &self.session.units[owner];
        const scope = try self.typeScope(owner);
        var source_type: types.Id = undefined;
        var qualifier: core.BindingId = 0;
        if (input.anonymous) {
            const closure = module.closures[input.identity];
            self.scratch.sources.items[scope].body = closure.body;
            self.scratch.sources.items[scope].closed_rows = closure.closed_rows;
            qualifier = closure.qualifier;
            if (closure.function_type == 0) {
                self.setSourceRoot(scope, try self.solver.function(try self.importType(scope, closure.parameter.ty, 0), try self.importType(scope, module.typeOf(closure.body), 0)));
            } else self.setSourceRoot(scope, try self.importType(scope, closure.function_type, 0));
        } else {
            const body = module.body(input.identity) orelse return error.UnresolvedType;
            self.scratch.sources.items[scope].body = body.root;
            self.scratch.sources.items[scope].closed_rows = body.closed_rows;
            qualifier = input.identity;
            source_type = module.binding(input.identity).ty;
            for (0..input.applied) |_| {
                const arrow = module.types.node(source_type);
                if (arrow.tag != .function) return error.TypeMismatch;
                source_type = arrow.b;
            }
            self.setSourceRoot(scope, try self.importType(scope, source_type, 0));
        }
        // These arrays are owned by the Session key. Neither a live value
        // handle nor a caller solver variable is imported into the private job.
        try self.seed(scope, input.mappings);
        try self.seedRows(scope, input.rows);
        if (input.existing != 0) try self.unify(self.scratch.sources.items[scope].root, try self.importEvidence(input.existing, 0));
        for (input.slots, 0..) |capture, index| {
            const formal = if (input.anonymous) module.binding(capture.binding).ty else module.bodyParameters(module.body(input.identity).?)[index].ty;
            try self.unify(try self.importType(scope, formal, 0), try self.importEvidence(capture.interface, 0));
        }
        if (qualifier != 0) try self.importScheme(scope, module.binding(qualifier).scheme, self.scratch.sources.items[scope].body);
        self.scratch.sources.items[scope].binding = qualifier;
        return scope;
    }
    fn appendVariable(self: *ClosureRegion, variable: Variable) Allocator.Error!void {
        const index: u32 = @intCast(self.scratch.variables.items.len);
        try self.scratch.variables.append(self.scratch_allocator, variable);
        const source = &self.scratch.sources.items[variable.source.scope];
        if (source.variable_last != std.math.maxInt(u32)) self.scratch.variables.items[source.variable_last].next = index else source.variable_first = index;
        source.variable_last = index;
    }
    fn shareLexical(self: *ClosureRegion, scope: u32, caller: u32, scheme: types.Scheme) RegionError!void {
        const source = self.scratch.sources.items[scope];
        const module = &self.session.units[source.owner];
        const memberships = &self.scratch.scheme_memberships;
        const variables = try memberships.prepare(self.scratch_allocator, &self.session.counters.scheme_membership, source.owner, scheme.variables, module.types.list(scheme.variables));
        const quantified_rows = try memberships.prepare(self.scratch_allocator, &self.session.counters.scheme_membership, source.owner, scheme.row_variables, module.types.list(scheme.row_variables));
        const closed_rows = try memberships.prepare(self.scratch_allocator, &self.session.counters.scheme_membership, source.owner, source.closed_rows, module.types.list(source.closed_rows));
        // Per-scope links keep the original insertion order. The bound excludes
        // imports appended by unification, as the former whole-region scan did.
        const variable_count = self.scratch.variables.items.len;
        self.session.counters.lexical_region_candidates += variable_count;
        var index = source.variable_first;
        while (index < variable_count) {
            const variable = self.scratch.variables.items[index];
            index = variable.next;
            self.session.counters.lexical_scope_candidates += 1;
            if (variables.contains(variable.source.ty)) continue;
            // Projections also occupy this table for physical result mapping.
            // Their argument variables own lexical sharing; a projection of a
            // quantified argument belongs to each independent call instance.
            if (module.types.node(variable.source.ty).tag == .projection) continue;
            try self.unify(variable.region, try self.importType(caller, variable.source.ty, 0));
        }
        // Links retain numeric keys, so unification may grow either the map
        // or the arrays without invalidating an iterator. Only entries present
        // at entry participate, matching the former two-stage collection.
        const row_count = self.scratch.row_variable_entries.items.len;
        self.session.counters.lexical_row_region_candidates += row_count;
        var row_index = source.row_first;
        while (row_index < row_count) {
            const entry = self.scratch.row_variable_entries.items[row_index];
            row_index = entry.next;
            self.session.counters.lexical_row_scope_candidates += 1;
            const variable = entry.source.variable;
            if (quantified_rows.contains(variable) or closed_rows.contains(variable)) continue;
            try self.solver.unifyEffects(entry.region, try self.importRowVariable(caller, variable));
        }
    }
    fn formalCallback(self: *ClosureRegion, scope: u32, reference: core.BindingRef) ?u32 {
        const source = self.scratch.sources.items[scope];
        if (reference.unit != 0 and reference.unit != self.session.unitId(source.owner)) return null;
        const module = &self.session.units[source.owner];
        const body = module.body(source.binding) orelse return null;
        for (module.bodyParameters(body), 0..) |parameter, index| {
            if (parameter.binding == reference.binding and module.types.node(parameter.ty).tag == .function) return @intCast(index);
        }
        return null;
    }
    fn callbackSignature(self: *ClosureRegion, scope: u32, slot: u32) RegionError!types.Id {
        const source = self.scratch.sources.items[scope];
        const module = &self.session.units[source.owner];
        const body = module.body(source.binding) orelse return error.UnresolvedType;
        const parameters = module.bodyParameters(body);
        if (slot >= parameters.len) return error.UnresolvedType;
        return self.importType(scope, parameters[slot].ty, 0);
    }
    const CallbackOrigin = struct { slot: u32, stage: u32 };
    fn callbackOrigin(self: *ClosureRegion, scope: u32, callee: core.Id) ?CallbackOrigin {
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        var cursor = callee;
        for (0..self.session.options.max_type_depth) |stage| {
            const node = module.node(cursor);
            if (node.tag == .reference) {
                const slot = self.formalCallback(scope, module.reference(cursor)) orelse return null;
                return .{ .slot = slot, .stage = @intCast(stage) };
            }
            if (node.tag != .apply) return null;
            cursor = node.a;
        }
        return null;
    }
    fn sourceCallable(self: *ClosureRegion, scope: u32, callee: core.Id) bool {
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        var cursor = callee;
        for (0..self.session.options.max_type_depth) |_| {
            const node = module.node(cursor);
            switch (node.tag) {
                .apply => cursor = node.a,
                .call, .associated, .project, .result_associated, .operation_value => return true,
                .reference => {
                    const reference = module.reference(cursor);
                    if (reference.unit != 0 and reference.unit != self.session.unitId(self.scratch.sources.items[scope].owner)) return true;
                    return module.binding(reference.binding).kind == .global;
                },
                .scalar => return node.c != 0 and node.b != 0,
                else => return false,
            }
        }
        return false;
    }
    fn callbackUse(self: *ClosureRegion, scope: u32, id: core.Id, origin: CallbackOrigin) RegionError!void {
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        const node = module.node(id);
        try self.appendConstraint(.{ .kind = .callback_use, .scope = scope, .node = id, .callback_slot = origin.slot, .callback_stage = origin.stage, .left = try self.importType(scope, module.typeOf(node.a), 0), .right = try self.importType(scope, module.typeOf(node.b), 0), .result = try self.importType(scope, node.ty, 0), .signature = try self.callbackSignature(scope, origin.slot) });
    }
    fn alignClosure(self: *ClosureRegion, scope: u32, id: core.Id) RegionError!void {
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        const closure = module.closure(id);
        const actual = try self.importImplementation(scope, module.typeOf(id));
        const envelope = if (closure.function_type != 0) try self.importImplementation(scope, closure.function_type) else actual;
        const wrapper = self.solver.node(try self.solver.resolve(envelope, 0));
        var callable = envelope;
        if (wrapper.tag == .usage) callable = wrapper.a;
        const signature = self.solver.node(try self.solver.resolve(callable, 0));
        if (signature.tag != .function) return error.TypeMismatch;
        const shape = try self.solver.functionWithEffects(try self.importType(scope, closure.parameter.ty, 0), try self.importType(scope, module.typeOf(closure.body), 0), signature.c);
        try self.unify(actual, envelope);
        try self.unify(callable, shape);
        if (self.source_interface) try self.appendFunction(actual);
    }
    fn operationConstraint(self: *ClosureRegion, scope: u32, id: core.Id, operation: core.OperationValue) RegionError!void {
        const owner = self.scratch.sources.items[scope].owner;
        const module = &self.session.units[owner];
        var arguments: std.ArrayList(types.Id) = .empty;
        defer arguments.deinit(self.session.allocator);
        for (module.types.list(operation.arguments)) |argument| try arguments.append(self.session.allocator, try self.importType(scope, argument, 0));
        const signature = try self.importType(scope, operation.signature, 0);
        if (operation.witness != 0 and !try self.sourceHeadProven(owner, module.typeOf(operation.witness), operation.witness_result)) {
            try self.appendConstraint(.{ .scope = scope, .node = id, .left = try self.importType(scope, module.typeOf(operation.witness), 0), .right = try self.importType(scope, operation.witness_result, 0), .result = 0, .kind = .type_head });
        }
        var instance = operation.instance;
        if (instance.unit == 0 and instance.decl != 0) instance.decl = try self.importType(scope, instance.decl, 0);
        try self.appendConstraint(.{ .scope = scope, .node = id, .left = signature, .right = try self.solver.product(arguments.items), .result = 0, .signature = signature, .identity = .{ .unit = if (operation.identity.unit == 0) self.session.unitId(owner) else operation.identity.unit, .decl = operation.identity.decl }, .instance = instance, .kind = .effect_operation, .solved = self.building_principal and try self.sourceOperationProven(owner, operation) });
    }
    fn sourceOperationProven(self: *ClosureRegion, owner: usize, operation: core.OperationValue) RegionError!bool {
        // A source-seeded exact instance already owns its row prefix. This
        // discharges only that redundant equation; every row import and handler
        // equation remains in the template. Inferred instances stay residual.
        const source = &self.session.units[owner].types;
        const signature = source.node(operation.signature);
        if (signature.tag != .function) return false;
        const arguments = source.list(operation.arguments);
        for (arguments) |argument| {
            const complete = self.session.storage.evidence.project(source, argument, &.{}) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => return false,
            };
            if (!try self.firstOrderData(complete, 0)) return false;
        }
        for (source.rowLabels(signature.c)) |label| {
            if (std.meta.eql(source.operation(label).instance, operation.instance) and std.meta.eql(source.operation(label).identity, operation.identity) and std.mem.eql(types.Id, source.operationArguments(label), arguments)) return true;
        }
        return false;
    }
    fn sourceHeadProven(self: *ClosureRegion, owner: usize, witness: types.Id, result: types.Id) RegionError!bool {
        // Only immutable source facts may discharge this redundant equation.
        // A caller-selected witness must still infer/check its result normally.
        const source = &self.session.units[owner].types;
        var head = witness;
        for (0..self.session.options.max_type_depth) |_| {
            const node = source.node(head);
            if (node.tag != .function) break;
            head = node.b;
        } else return false;
        // A fixed outer constructor stays the same under every fresh binder
        // substitution. An unknown outer binder can later become an arrow,
        // whose witness head differs from the binder itself.
        if (head == result) switch (source.node(head).tag) {
            .absent, .variable, .never => {},
            else => return true,
        };
        const actual = self.session.storage.evidence.project(source, head, &.{}) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return false,
        };
        const expected = self.session.storage.evidence.project(source, result, &.{}) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return false,
        };
        return actual == expected and self.session.storage.evidence.node(actual).tag != .never and try self.firstOrderData(actual, 0);
    }
    /// An invocation can retain a generic result while its source row already
    /// proves the operation arguments. Recover that proof only from a complete
    /// row with one compatible exact instance; never choose between instances.
    fn recoverOperationArguments(self: *ClosureRegion, constraint: Constraint) RegionError!bool {
        const signature = self.solver.node(try self.solver.resolve(constraint.left, 0));
        if (signature.tag != .function) return false;
        const row = try self.solver.resolveEffects(signature.c, 0);
        if (self.solver.row(row).tail != .closed) return false;
        var selected: ?types.Effects.Label = null;
        for (0..self.solver.rowLabels(row).len) |index| {
            const label = self.solver.rowLabels(row)[index];
            if (!std.meta.eql(self.solver.operation(label).instance, constraint.instance) or !std.meta.eql(self.solver.operation(label).identity, constraint.identity)) continue;
            if (selected == label) continue;
            const arguments = try self.session.allocator.dupe(types.Id, self.solver.operationArguments(label));
            defer self.session.allocator.free(arguments);
            const candidate = try self.solver.product(arguments);
            if (!try self.solver.equalClosed(candidate, candidate)) continue;
            const point = self.solver.mark();
            self.unify(constraint.right, candidate) catch |err| switch (err) {
                error.TypeMismatch, error.InfiniteType, error.EffectMismatch, error.InfiniteEffect => {
                    self.solver.rollback(point);
                    continue;
                },
                else => return err,
            };
            self.solver.rollback(point);
            if (selected != null) return false;
            selected = label;
        }
        const label = selected orelse return false;
        const arguments = try self.session.allocator.dupe(types.Id, self.solver.operationArguments(label));
        defer self.session.allocator.free(arguments);
        try self.unify(constraint.right, try self.solver.product(arguments));
        return true;
    }
    fn definitionIndex(self: *ClosureRegion) *std.AutoHashMapUnmanaged(DefinitionKey, core.BindingId) {
        return &self.session.regions.callable_definitions;
    }
    fn callableDefinitions(self: *ClosureRegion, owner: usize) RegionError!void {
        // This index reads immutable Core, never the current inference scope.
        // Its lifetime is the Session's source owner, not a solver region.
        const definitions = self.definitionIndex();
        const owners = &self.session.regions.callable_definition_units;
        if (owners.contains(owner)) return;
        const module = &self.session.units[owner];
        var work: std.ArrayList(core.Id) = .empty;
        defer work.deinit(self.session.allocator);
        for (module.bindings, 0..) |binding, index| {
            if (binding.initializer == 0 or module.types.node(binding.ty).tag != .function) continue;
            try work.append(self.session.allocator, binding.initializer);
            while (work.pop()) |id| {
                const node = module.node(id);
                switch (node.tag) {
                    .reference, .closure => try definitions.put(self.session.allocator, .{ .owner = owner, .node = id }, @intCast(index)),
                    .return_ => try work.append(self.session.allocator, node.a),
                    .if_value, .if_stmt => try work.appendSlice(self.session.allocator, &.{ node.b, node.c }),
                    .match => for (module.matchArms(id)) |arm| {
                        try work.append(self.session.allocator, arm.body);
                    },
                    .block, .suite => for (module.children(id)) |child| {
                        const tag = module.node(child).tag;
                        if (tag == .return_ or tag == .if_stmt or tag == .match) try work.append(self.session.allocator, child);
                    },
                    else => {},
                }
            }
        }
        try owners.put(self.session.allocator, owner, {});
    }
    fn collectStartupPatterns(self: *ClosureRegion, scope: u32, roots: []const core.PatternId) RegionError!void {
        if (!self.retain_selected) return;
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        var work: std.ArrayList(core.PatternId) = .empty;
        defer work.deinit(self.session.allocator);
        var seen: std.AutoHashMapUnmanaged(core.PatternId, void) = .empty;
        defer seen.deinit(self.session.allocator);
        try work.appendSlice(self.session.allocator, roots);
        while (work.pop()) |id| {
            if (id == 0 or seen.contains(id)) continue;
            if (seen.count() >= self.session.options.max_values) return error.TypeLimit;
            try seen.put(self.session.allocator, id, {});
            const pattern = module.pattern(id);
            switch (pattern.tag) {
                .value => {
                    self.startup_coverage_complete = false;
                    // Retain selected targets for the SCC diagnostic, while
                    // the whole plan still uses guarded recursive emission.
                    try self.collect(scope, pattern.a);
                },
                .constructor, .record_payload => try work.append(self.session.allocator, pattern.b),
                .product => try work.appendSlice(self.session.allocator, module.patternChildren(id)),
                .wildcard, .bind, .constant => {},
                .invalid => self.startup_coverage_complete = false,
            }
        }
    }
    fn appendConstraint(self: *ClosureRegion, original_constraint: Constraint) RegionError!void {
        var constraint = original_constraint;
        if (constraint.use_node == 0) constraint.use_node = self.current_use;
        if (self.building_principal) constraint.origin = null else constraint.origin = self.current_origin;
        const index = self.scratch.constraints.items.len;
        try self.scratch.constraints.append(self.scratch_allocator, constraint);
        if (self.building_principal) try self.scratch.principal_actions.append(self.scratch_allocator, .{ .constraint = @intCast(index) });
    }
    fn appendAlias(self: *ClosureRegion, alias: DataAlias) RegionError!void {
        const index = self.scratch.data_aliases.items.len;
        try self.scratch.data_aliases.append(self.scratch_allocator, alias);
        if (self.building_principal) try self.scratch.principal_actions.append(self.scratch_allocator, .{ .alias = @intCast(index) });
    }
    fn appendFunction(self: *ClosureRegion, function: types.Id) RegionError!void {
        const index = self.scratch.source_functions.items.len;
        try self.scratch.source_functions.append(self.scratch_allocator, function);
        if (self.building_principal) try self.scratch.principal_actions.append(self.scratch_allocator, .{ .function = @intCast(index) });
    }
    fn appendReference(self: *ClosureRegion, reference: Target) RegionError!void {
        const index = self.scratch.principal_references.items.len;
        try self.scratch.principal_references.append(self.scratch_allocator, reference);
        if (self.building_principal) try self.scratch.principal_actions.append(self.scratch_allocator, .{ .reference = @intCast(index) });
    }
    fn describePrincipal(self: *ClosureRegion, key: PrincipalGraph.Key) RegionError!?*PrincipalGraph {
        const a = self.session.allocator;
        const initial_steps = self.session.steps;
        const initial_values = self.session.storage.values.items.len;
        const initial_children = self.session.storage.children.items.len;
        const tape = self.session.receipt_tape;
        const reads = self.session.principal_reads;
        const plain_reads = self.session.principal_plain_reads;
        const observation = self.session.refinement_observation;
        var dependencies: receipt.Tape = .{};
        defer dependencies.deinit(a);
        self.session.receipt_tape = &dependencies;
        self.session.principal_reads = null;
        // Plain-nominal memo entries are session state this description
        // reads and fills inside the caller's recorded region. They reach
        // the caller's recorder in order; replaying the finished graph's
        // facts later would mistake its own publications for prior inputs.
        self.session.principal_plain_reads = reads orelse plain_reads;
        self.session.refinement_observation = null;
        defer {
            self.session.receipt_tape = tape;
            self.session.principal_reads = reads;
            self.session.principal_plain_reads = plain_reads;
            self.session.refinement_observation = observation;
        }
        // Collection and solving are speculative source inquiries. Neither may
        // replace the diagnostic owned by the authoritative caller inquiry.
        const diagnostic = self.session.diagnostic;
        const message = self.session.owned_diagnostic_message;
        self.session.diagnostic = null;
        self.session.owned_diagnostic_message = &.{};
        defer {
            self.session.allocator.free(self.session.owned_diagnostic_message);
            self.session.owned_diagnostic_message = message;
            self.session.diagnostic = diagnostic;
        }
        var region = try ClosureRegion.initWithSolverAllocatorAt(self.session, a, @src());
        defer region.deinit();
        region.building_principal = true;
        region.source_interface = key.source_interface;
        region.defer_members = key.deferred_member;
        region.include_callables = true;
        const scope = try region.callableScope(key.target);
        const body_constraints = region.scratch.constraints.items.len;
        const body_actions = region.scratch.principal_actions.items.len;
        region.collect(scope, region.scratch.sources.items[scope].body) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return null,
        };
        // This region contains only fresh immutable-source inputs. Source
        // equations may refine its binders, but a template never owns their
        // chronological solver history or emits speculative diagnostics.
        var previous = region.solver.mark();
        var transitions: usize = 0;
        var fallback = false;
        var imported_children: std.AutoHashMapUnmanaged(usize, void) = .empty;
        defer imported_children.deinit(a);
        while (true) {
            var constraint_index: usize = 0;
            var attempted = false;
            while (constraint_index < region.scratch.constraints.items.len) : (constraint_index += 1) {
                const constraint = region.scratch.constraints.items[constraint_index];
                if (constraint.kind == .call_summary) {
                    if (imported_children.contains(constraint_index)) continue;
                    const child_key: PrincipalGraph.Key = .{ .target = constraint.target, .source_interface = key.source_interface, .deferred_member = constraint.deferred_member, .options = key.options };
                    const child = self.session.specializations.call_summaries.normalized_principals.get(child_key, self.session) orelse continue;
                    var child_copy: principal_type_graph.Copy = .{ .allocator = a, .source = &child.types, .destination = &region.solver, .max_depth = self.session.options.max_type_depth, .max_nodes = self.session.options.max_values };
                    defer child_copy.deinit();
                    _ = region.admitSignature(constraint.left, try child_copy.ty(child.root, 0)) catch |err| switch (err) {
                        error.OutOfMemory => return err,
                        else => return null,
                    };
                    try imported_children.put(a, constraint_index, {});
                    self.session.counters.solver_constraint_visits += 1;
                    continue;
                }
                // Operation selection retains the receiving region's ambient
                // row. It remains a fresh residual obligation, even when its
                // source-owned argument representation is already complete.
                if (constraint.solved or constraint.callback_interface or constraint.kind == .call_summary or constraint.kind == .scheme_use or constraint.kind == .effect_operation) continue;
                if (transitions >= self.session.options.max_children) return null;
                transitions += 1;
                attempted = true;
                self.session.counters.solver_constraint_visits += 1;
                _ = region.attemptConstraint(constraint_index, fallback) catch |err| switch (err) {
                    error.OutOfMemory => return err,
                    else => return null,
                };
            }
            if (attempted) self.session.counters.solver_passes += 1;
            const current = region.solver.mark();
            if (current.versions == previous.versions and current.effects.versions == previous.effects.versions) {
                if (fallback or !attempted) break;
                fallback = true;
            } else fallback = false;
            previous = current;
        }
        if (region.scratch.edges.items.len != 0) return null;
        for (region.scratch.sources.items, 0..) |source, index_| {
            if (index_ != scope and (source.body != 0 or source.value != 0 or source.binding != 0)) return null;
        }
        for (region.scratch.constraints.items) |constraint| if (constraint.scope != scope) return null;
        for (region.solver.effects.rows.items) |row| if (row.tail == .parameter) return null;
        const graph = try a.create(PrincipalGraph);
        graph.* = .{ .key = key, .allocations = .{ .backing = a }, .types = undefined };
        graph.types = types.Store.init(graph.allocations.allocator()) catch |err| {
            a.destroy(graph);
            return err;
        };
        errdefer graph.deinit(a);
        var copy_meter: @import("../runtime/memory.zig").TrackedAllocator = .{ .backing = graph.allocations.allocator() };
        defer {
            self.session.counters.principal_copy_buffer_bytes += copy_meter.counts.allocated_bytes;
            self.session.counters.principal_copy_buffer_allocations += copy_meter.counts.allocations;
        }
        const buffers = copy_meter.allocator();
        graph.untracked_reads = dependencies.unknown or dependencies.nested or dependencies.call_reads.items.len != 0 or dependencies.views.items.len != 0;
        for (region.scratch.sources.items) |source| graph.foreign_sources = graph.foreign_sources or source.owner != key.target.unit;
        graph.foreign_types_only = true;
        graph.dependencies = try buffers.dupe(core.BindingRef, dependencies.sources.items);
        graph.plain_reads = try buffers.dupe(receipt.PlainFact, dependencies.plain_facts.items);
        graph.retention_eligible = !graph.untracked_reads and dependencies.scalar_reads.items.len == 0 and
            dependencies.call_publications.items.len == 0 and graph.plain_reads.len == 0 and imported_children.count() == 0 and
            self.session.steps == initial_steps and self.session.storage.values.items.len == initial_values and
            self.session.storage.children.items.len == initial_children;
        var copy: principal_type_graph.NormalizedCopy = .{ .allocator = buffers, .source = &region.solver, .destination = &graph.types, .max_depth = self.session.options.max_type_depth, .max_nodes = self.session.options.max_values };
        defer copy.deinit();
        graph.root = try copy.ty(try region.solver.resolve(region.scratch.sources.items[scope].root, 0), 0);
        var import_count: usize = 0;
        var imported_keys = region.scratch.imported.keyIterator();
        while (imported_keys.next()) |entry| if (entry.scope == scope) {
            import_count += 1;
        };
        graph.imports = try buffers.alloc(PrincipalGraph.TypeImport, import_count);
        var imports = region.scratch.imported.iterator();
        var index: usize = 0;
        while (imports.next()) |entry| {
            if (entry.key_ptr.scope != scope) continue;
            graph.imports[index] = .{ .source = entry.key_ptr.ty, .graph = try copy.ty(try region.solver.resolve(entry.value_ptr.*, 0), 0) };
            index += 1;
        }
        var row_count: usize = 0;
        var row_keys = region.scratch.row_variables.keyIterator();
        while (row_keys.next()) |entry| if (entry.scope == scope) {
            row_count += 1;
        };
        graph.rows = try buffers.alloc(PrincipalGraph.RowImport, row_count);
        var rows = region.scratch.row_variables.iterator();
        index = 0;
        while (rows.next()) |entry| {
            if (entry.key_ptr.scope != scope) continue;
            graph.rows[index] = .{ .source = entry.key_ptr.variable, .graph = try copy.row(try region.solver.resolveEffects(entry.value_ptr.*, 0), 0) };
            index += 1;
        }
        const residuals = region.scratch.constraints.items[body_constraints..];
        const requirements = region.scratch.constraints.items[0..body_constraints];
        graph.requirements = try buffers.dupe(Constraint, requirements);
        for (graph.requirements) |*constraint| constraint.diagnostic_name = &.{};
        for (graph.requirements, requirements) |*constraint, original| {
            constraint.diagnostic_name = try buffers.dupe(u8, original.diagnostic_name);
            try region.freezePrincipalConstraint(&copy, constraint);
        }
        graph.constraints = try buffers.dupe(Constraint, residuals);
        for (graph.constraints) |*constraint| constraint.diagnostic_name = &.{};
        for (graph.constraints, residuals) |*constraint, original| {
            constraint.diagnostic_name = try buffers.dupe(u8, original.diagnostic_name);
            try region.freezePrincipalConstraint(&copy, constraint);
        }
        graph.aliases = try buffers.dupe(DataAlias, region.scratch.data_aliases.items);
        for (graph.aliases) |*alias| {
            alias.instance = try copy.ty(try region.solver.resolve(alias.instance, 0), 0);
            alias.principal = try copy.ty(try region.solver.resolve(alias.principal, 0), 0);
        }
        graph.functions = try buffers.dupe(types.Id, region.scratch.source_functions.items);
        for (graph.functions) |*function| function.* = try copy.ty(try region.solver.resolve(function.*, 0), 0);
        graph.arguments = try buffers.dupe(core.Id, region.scratch.summary_arguments.items);
        graph.references = try buffers.dupe(Target, region.scratch.principal_references.items);
        graph.actions = try buffers.dupe(PrincipalGraph.Action, region.scratch.principal_actions.items[body_actions..]);
        for (graph.actions) |*action| if (action.* == .constraint) {
            action.constraint -= @intCast(body_constraints);
        };
        return graph;
    }
    fn freezePrincipalConstraint(self: *ClosureRegion, copy: *principal_type_graph.NormalizedCopy, constraint: *Constraint) RegionError!void {
        constraint.left = try copy.ty(try self.solver.resolve(constraint.left, 0), 0);
        // A callee edge's right operand remains an immutable Core type handle.
        if (constraint.kind != .call_summary) constraint.right = try copy.ty(try self.solver.resolve(constraint.right, 0), 0);
        constraint.result = try copy.ty(try self.solver.resolve(constraint.result, 0), 0);
        constraint.signature = try copy.ty(try self.solver.resolve(constraint.signature, 0), 0);
    }
    fn principalGraph(self: *ClosureRegion, scope: u32, body: core.Id) RegionError!?*PrincipalGraph {
        // Captures are explicit selected inputs here, never an open principal
        // qualifier whose complete global arrow can be freshened by a caller.
        if (self.lexical_summary_job != 0) return null;
        if (self.building_principal or self.summary_job or !self.session.reuse_principal_graphs or !self.include_callables or self.retain_selected or self.complete_demand_bodies or self.speculative_source_entry) return null;
        // Quota-bound inquiries keep their original collector and its exact
        // prefix/limit diagnostics. Templates are an optional sharing policy.
        if (self.session.options.max_values < 4096 or self.session.options.max_type_depth < 64) return null;
        const source = self.scratch.sources.items[scope];
        if (source.value != 0 or source.binding == 0) return null;
        const module = &self.session.units[source.owner];
        if (module.binding(source.binding).kind != .global) return null;
        const target_: Target = .{ .unit = source.owner, .binding = source.binding };
        const definition = module.body(source.binding) orelse return null;
        if (definition.root != body or !try self.summaryShapeEligible(target_)) return null;
        if (self.unkeyed_capture_inputs and self.higherOrderBody(target_)) return null;
        // Complete data inputs/results already share their input-keyed
        // judgments. An ambient row alone does not need a symbolic template.
        var arrow_type = source.root;
        var open = false;
        for (0..definition.parameters.len) |_| {
            const arrow = self.solver.node(try self.solver.resolve(arrow_type, 0));
            if (arrow.tag != .function) return null;
            open = open or try self.project(arrow.a) == 0;
            arrow_type = arrow.b;
        }
        if (!open and try self.project(arrow_type) != 0) return null;
        const key: PrincipalGraph.Key = .{ .target = target_, .source_interface = self.source_interface, .deferred_member = self.defer_members, .options = self.session.options };
        return self.principalGraphForKey(key);
    }
    fn principalGraphForKey(self: *ClosureRegion, key: PrincipalGraph.Key) RegionError!?*PrincipalGraph {
        if (self.session.specializations.call_summaries.normalized_principals.get(key, self.session)) |graph| return graph;
        if (self.session.specializations.call_summaries.principals.get(key, self.session)) |graph| return graph;
        if (!self.session.summaryCharge(1)) return null;
        if (self.session.specializations.call_summaries.principals.count() >= self.session.options.max_values) return null;
        if (self.session.principal_graph_provider) |provider| {
            self.session.counters.principal_graph_retained_requests += 1;
            if (provider.lookup(provider.context, key)) |retained| {
                const nodes = retained.nodeCount();
                const edges = retained.edgeCount();
                if (nodes <= self.session.options.max_values -| self.session.principal_graph_nodes and edges <= self.session.options.max_children -| self.session.principal_graph_edges and
                    try self.session.specializations.call_summaries.principals.put(self.session.allocator, key, retained, self.session))
                {
                    retained.retain();
                    self.session.principal_graph_nodes += nodes;
                    self.session.principal_graph_edges += edges;
                    self.session.counters.principal_graph_retained_hits += 1;
                    return retained;
                }
            }
        }
        const graph = self.describePrincipal(key) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => null,
        };
        if (graph) |owned| {
            const nodes = owned.nodeCount();
            const edges = owned.edgeCount();
            if (nodes > self.session.options.max_values -| self.session.principal_graph_nodes or edges > self.session.options.max_children -| self.session.principal_graph_edges) {
                owned.deinit(self.session.allocator);
                return null;
            }
        }
        errdefer if (graph) |owned| {
            owned.deinit(self.session.allocator);
        };
        // The visible graph appears only after every owner and index allocation
        // succeeds. Allocation failure is never retained as ineligibility.
        if (!try self.session.specializations.call_summaries.principals.put(self.session.allocator, key, graph, self.session)) {
            if (graph) |owned| {
                owned.deinit(self.session.allocator);
            }
            return null;
        }
        if (graph) |owned| {
            self.session.principal_graph_builds += 1;
            self.session.counters.principal_graph_builds += 1;
            self.session.principal_graph_nodes += owned.nodeCount();
            self.session.principal_graph_edges += owned.edgeCount();
        }
        return graph;
    }
    fn resultPrincipalEligible(self: *ClosureRegion, target_: Target, deferred: bool) RegionError!bool {
        if (!self.session.reuse_principal_graphs or (self.summary_job and !self.result_summary_job) or self.retain_selected or self.complete_demand_bodies or self.speculative_source_entry) return false;
        if (self.unkeyed_capture_inputs and self.higherOrderBody(target_)) return false;
        if (self.session.options.max_values < 4096 or self.session.options.max_type_depth < 64) return false;
        const root: PrincipalGraph.Key = .{ .target = target_, .source_interface = self.source_interface, .deferred_member = deferred, .options = self.session.options };
        if (self.session.specializations.call_summaries.result_principals.get(root)) |known| return known;
        if (self.session.specializations.call_summaries.result_principals.count() >= self.session.options.max_values) return false;
        const ready = try self.checkResultPrincipal(root);
        try self.session.specializations.call_summaries.result_principals.put(self.session.allocator, root, ready);
        return ready;
    }
    fn checkResultPrincipal(self: *ClosureRegion, root: PrincipalGraph.Key) RegionError!bool {
        const Visit = struct { key: PrincipalGraph.Key, graph: *PrincipalGraph, next: usize = 0 };
        var pending: std.ArrayList(Visit) = .empty;
        defer pending.deinit(self.scratch_allocator);
        var visited: std.AutoHashMapUnmanaged(PrincipalGraph.Key, bool) = .empty;
        defer visited.deinit(self.scratch_allocator);
        if (!try self.summaryShapeEligible(root.target)) return false;
        const first = try self.principalGraphForKey(root) orelse return false;
        try pending.append(self.scratch_allocator, .{ .key = root, .graph = first });
        try visited.put(self.scratch_allocator, root, false);
        var result_directed = false;
        var edges: usize = 0;
        while (pending.items.len != 0) {
            const last = pending.items.len - 1;
            const frame = pending.items[last];
            if (frame.next == frame.graph.requirements.len + frame.graph.constraints.len) {
                visited.getPtr(frame.key).?.* = true;
                _ = pending.pop();
                continue;
            }
            pending.items[last].next += 1;
            const constraint = if (frame.next < frame.graph.requirements.len) frame.graph.requirements[frame.next] else frame.graph.constraints[frame.next - frame.graph.requirements.len];
            edges += 1;
            if (edges > self.session.options.max_children) return false;
            switch (constraint.kind) {
                .result_dispatch, .effect_operation => result_directed = true,
                .binary, .field, .physical_field, .receiver, .update, .collection, .record_merge, .type_head, .type_compare, .type_rep, .effect_rep, .effect_handler => {},
                .call_summary, .scheme_use => {
                    const child: PrincipalGraph.Key = .{ .target = constraint.target, .source_interface = root.source_interface, .deferred_member = constraint.deferred_member, .options = root.options };
                    if (visited.get(child)) |done| {
                        if (!done) return false;
                        continue;
                    }
                    if (visited.count() >= self.session.options.max_values or !try self.summaryShapeEligible(child.target)) return false;
                    const graph = try self.principalGraphForKey(child) orelse return false;
                    try visited.put(self.scratch_allocator, child, false);
                    try pending.append(self.scratch_allocator, .{ .key = child, .graph = graph });
                },
                else => return false,
            }
        }
        return result_directed;
    }
    fn retainOpenPrincipal(self: *ClosureRegion, constraint: Constraint) RegionError!bool {
        if (!self.session.reuse_principal_graphs or self.summary_job or self.retain_selected or self.complete_demand_bodies or self.speculative_source_entry) return false;
        if (self.unkeyed_capture_inputs and self.higherOrderBody(constraint.target)) return false;
        if (self.session.options.max_values < 4096 or self.session.options.max_type_depth < 64) return false;
        const key: PrincipalGraph.Key = .{ .target = constraint.target, .source_interface = self.source_interface, .deferred_member = constraint.deferred_member, .options = self.session.options };
        var graph = try self.principalGraphForKey(key) orelse return false;
        if (!self.session.specializations.call_summaries.open_principals.contains(key) and self.session.specializations.call_summaries.open_principals.count() >= self.session.options.max_values) return false;
        const ready = self.session.specializations.call_summaries.open_principals.get(key) orelse ready: {
            const checked = try self.checkOpenPrincipal(key) and try self.openPrincipalPays(key);
            try self.session.specializations.call_summaries.open_principals.put(self.session.allocator, key, checked);
            break :ready checked;
        };
        if (!ready) return false;
        graph = (try self.principalGraphForKey(key)).?;
        // Replay only equations inferred from immutable source. Caller
        // selections never enter the template. Covariant rows retain the
        // caller's ambient view; failed admission leaves the solver unchanged.
        const point = self.solver.mark();
        var accepted = false;
        defer if (!accepted) self.solver.rollback(point);
        var copy: principal_type_graph.Copy = .{ .allocator = self.scratch_allocator, .source = &graph.types, .destination = &self.solver, .max_depth = self.session.options.max_type_depth, .max_nodes = self.session.options.max_values };
        defer copy.deinit();
        const interface = self.admitSignature(constraint.left, try copy.ty(graph.root, 0)) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return false,
        };
        if (!try principal_type_graph.matchesOpen(self.scratch_allocator, &graph.types, graph.root, &self.solver, try self.solver.resolve(interface, 0), self.session.options.max_type_depth, self.session.options.max_values)) return false;
        accepted = true;
        // This is an exported residual edge, never a completed call proof. A
        // partial prepass cannot retain a dependency-complete selected result.
        if (graph.source_complete) {
            try self.principalDependencies(graph, true);
        } else {
            if (self.session.principal_reads) |reads| reads.invalidate(.call_read);
            if (self.session.receipt_tape) |tape| tape.unknown = true;
        }
        return true;
    }
    fn principalDependencies(self: *ClosureRegion, first: *const PrincipalGraph, transitive: bool) RegionError!void {
        if (self.session.principal_reads == null and self.session.receipt_tape == null and !self.session.recordingConstant()) return;
        var pending: std.ArrayList(*const PrincipalGraph) = .empty;
        defer pending.deinit(self.scratch_allocator);
        var seen: std.AutoHashMapUnmanaged(PrincipalGraph.Key, void) = .empty;
        defer seen.deinit(self.scratch_allocator);
        try pending.append(self.scratch_allocator, first);
        var edges: usize = 0;
        while (pending.pop()) |graph| {
            if (seen.contains(graph.key)) continue;
            if (seen.count() >= self.session.options.max_values) return error.TypeLimit;
            try seen.put(self.scratch_allocator, graph.key, {});
            if (graph.untracked_reads) if (self.session.principal_reads) |reads| reads.invalidate(.call_read);
            if (self.session.principal_reads) |reads| {
                if (graph.foreign_sources and !graph.foreign_types_only) reads.source_complete = false;
                for (graph.dependencies) |target_| try reads.source(self.session.allocator, target_);
            }
            if (graph.untracked_reads or graph.foreign_sources) if (self.session.receipt_tape) |tape| {
                tape.unknown = true;
            };
            if (self.session.receipt_tape) |tape| try tape.sources.appendSlice(self.session.allocator, graph.dependencies);
            if (self.session.constant_recorder) |recorder| {
                if (graph.untracked_reads or graph.foreign_sources) recorder.eligible = false;
                for (graph.dependencies) |target_| try recorder.source(self.session.allocator, target_);
            }
            for (graph.plain_reads) |fact| {
                const actual = self.session.specializations.plain_nominals.get(fact.key);
                if (self.session.principal_reads) |reads| try reads.plainRead(self.session.allocator, fact.key, actual);
                if (self.session.receipt_tape) |tape| try tape.plain_facts.append(self.session.allocator, .{ .key = fact.key, .plain = actual orelse false, .present = actual != null });
            }
            if (!transitive) continue;
            for ([_][]const Constraint{ graph.requirements, graph.constraints }) |constraints| for (constraints) |constraint| {
                edges += 1;
                if (edges > self.session.options.max_children) return error.TypeLimit;
                if (constraint.kind != .call_summary and constraint.kind != .scheme_use) continue;
                const key: PrincipalGraph.Key = .{ .target = constraint.target, .source_interface = graph.key.source_interface, .deferred_member = constraint.deferred_member, .options = graph.key.options };
                const child = try self.principalGraphForKey(key) orelse {
                    if (self.session.principal_reads) |reads| reads.invalidate(.call_read);
                    if (self.session.receipt_tape) |tape| tape.unknown = true;
                    continue;
                };
                try pending.append(self.scratch_allocator, child);
            };
        }
    }
    /// Ordinary collection collects a callee body once per call path, while a
    /// retained open edge costs one normalized graph per distinct body plus
    /// solving that stays open longer. Retention pays only when shared callees
    /// multiply the paths, as in a diamond; a tree collects ordinarily. Both
    /// choices give the same judgments. `root`'s graph is normalized.
    fn openPrincipalPays(self: *ClosureRegion, root: PrincipalGraph.Key) RegionError!bool {
        const a = self.scratch_allocator;
        const PathFrame = struct { key: PrincipalGraph.Key, expanded: bool };
        var paths: std.AutoHashMapUnmanaged(PrincipalGraph.Key, u64) = .empty;
        defer paths.deinit(a);
        var pending: std.ArrayList(PathFrame) = .empty;
        defer pending.deinit(a);
        try pending.append(a, .{ .key = root, .expanded = false });
        while (pending.pop()) |frame| {
            if (!frame.expanded and paths.contains(frame.key)) continue;
            const graph = self.session.specializations.call_summaries.normalized_principals.get(frame.key, self.session) orelse return true;
            if (!frame.expanded) {
                if (paths.count() >= self.session.options.max_values) return true;
                try pending.append(a, .{ .key = frame.key, .expanded = true });
                for ([_][]const Constraint{ graph.requirements, graph.constraints }) |constraints| for (constraints) |constraint| {
                    if (constraint.kind != .call_summary) continue;
                    const child: PrincipalGraph.Key = .{ .target = constraint.target, .source_interface = root.source_interface, .deferred_member = constraint.deferred_member, .options = root.options };
                    if (!paths.contains(child)) try pending.append(a, .{ .key = child, .expanded = false });
                };
                continue;
            }
            var total: u64 = 1;
            for ([_][]const Constraint{ graph.requirements, graph.constraints }) |constraints| for (constraints) |constraint| {
                if (constraint.kind != .call_summary) continue;
                const child: PrincipalGraph.Key = .{ .target = constraint.target, .source_interface = root.source_interface, .deferred_member = constraint.deferred_member, .options = root.options };
                total +|= paths.get(child) orelse return true;
            };
            try paths.put(a, frame.key, total);
        }
        return paths.get(root).? >= 2 *| @as(u64, paths.count());
    }
    fn checkOpenPrincipal(self: *ClosureRegion, root: PrincipalGraph.Key) RegionError!bool {
        if (self.session.specializations.call_summaries.normalized_principals.contains(root, self.session)) return true;
        const Visit = struct { key: PrincipalGraph.Key, graph: *PrincipalGraph, next: usize = 0 };
        const a = self.scratch_allocator;
        var pending: std.ArrayList(Visit) = .empty;
        defer pending.deinit(a);
        var visited: std.AutoHashMapUnmanaged(PrincipalGraph.Key, bool) = .empty;
        defer visited.deinit(a);
        const first = try self.principalGraphForKey(root) orelse return false;
        if (!try self.unknownPrincipalBody(first)) return false;
        try pending.append(a, .{ .key = root, .graph = first });
        try visited.put(a, root, false);
        var edges: usize = 0;
        while (pending.items.len != 0) {
            const last = pending.items.len - 1;
            const frame = pending.items[last];
            if (frame.next == frame.graph.requirements.len + frame.graph.constraints.len) {
                const normalized = try self.describePrincipal(frame.key) orelse return false;
                var published = false;
                defer if (!published) {
                    normalized.deinit(self.session.allocator);
                };
                if (!try self.unknownPrincipalBody(normalized)) return false;
                // Source equations can expose a selected implementation that
                // the original description could not name. Check those new
                // edges before publishing, including a newly revealed cycle.
                var waiting = false;
                discover: for ([_][]const Constraint{ normalized.requirements, normalized.constraints }) |constraints| for (constraints) |constraint| {
                    if (constraint.kind != .call_summary and constraint.kind != .scheme_use) continue;
                    edges += 1;
                    if (edges > self.session.options.max_children) return false;
                    const child: PrincipalGraph.Key = .{ .target = constraint.target, .source_interface = root.source_interface, .deferred_member = constraint.deferred_member, .options = root.options };
                    if (self.session.specializations.call_summaries.normalized_principals.contains(child, self.session)) continue;
                    if (visited.get(child)) |done| {
                        if (!done) return false;
                        continue;
                    }
                    if (visited.count() >= self.session.options.max_values) return false;
                    const child_graph = try self.principalGraphForKey(child) orelse return false;
                    if (!try self.unknownPrincipalBody(child_graph)) return false;
                    try visited.put(a, child, false);
                    try pending.append(a, .{ .key = child, .graph = child_graph });
                    waiting = true;
                    break :discover;
                };
                if (waiting) continue;
                var complete = true;
                for (normalized.aliases) |alias| complete = complete and try principal_type_graph.sameOpen(a, &normalized.types, alias.instance, alias.principal, self.session.options.max_type_depth, self.session.options.max_values);
                for (normalized.requirements) |requirement| complete = complete and requirement.solved;
                for (normalized.constraints) |constraint| {
                    if (constraint.kind == .call_summary or constraint.kind == .scheme_use) {
                        const child: PrincipalGraph.Key = .{ .target = constraint.target, .source_interface = root.source_interface, .deferred_member = constraint.deferred_member, .options = root.options };
                        const child_graph = (try self.principalGraphForKey(child)).?;
                        if (constraint.kind == .call_summary and !try principal_type_graph.matchesOpen(a, &child_graph.types, child_graph.root, &normalized.types, constraint.left, self.session.options.max_type_depth, self.session.options.max_values)) return false;
                        complete = complete and child_graph.source_complete;
                    } else {
                        if (!try self.unknownPrincipalConstraint(normalized, constraint)) return false;
                        complete = complete and (constraint.solved or constraint.callback_interface);
                    }
                }
                // A parametric source theorem is distinct from a closed call
                // judgment. Its unresolved binders remain fresh at each use.
                normalized.source_complete = complete;
                const nodes = normalized.nodeCount();
                const graph_edges = normalized.edgeCount();
                if (nodes > self.session.options.max_values -| self.session.principal_graph_nodes or graph_edges > self.session.options.max_children -| self.session.principal_graph_edges) return false;
                if (!try self.session.specializations.call_summaries.normalized_principals.put(self.session.allocator, frame.key, normalized, self.session)) return false;
                published = true;
                self.session.principal_graph_builds += 1;
                self.session.counters.principal_graph_builds += 1;
                self.session.principal_graph_nodes += nodes;
                self.session.principal_graph_edges += graph_edges;
                visited.getPtr(frame.key).?.* = true;
                _ = pending.pop();
                continue;
            }
            pending.items[last].next += 1;
            const constraint = if (frame.next < frame.graph.requirements.len) frame.graph.requirements[frame.next] else frame.graph.constraints[frame.next - frame.graph.requirements.len];
            edges += 1;
            if (edges > self.session.options.max_children) return false;
            if (constraint.kind != .call_summary and constraint.kind != .scheme_use) {
                continue;
            }
            if (constraint.kind == .scheme_use) {
                if (!try self.unknownPrincipalConstraint(frame.graph, constraint)) return false;
            }
            const child: PrincipalGraph.Key = .{ .target = constraint.target, .source_interface = root.source_interface, .deferred_member = constraint.deferred_member, .options = root.options };
            const graph = try self.principalGraphForKey(child) orelse return false;
            if (self.session.specializations.call_summaries.normalized_principals.contains(child, self.session)) continue;
            if (visited.get(child)) |done| {
                if (!done) return false; // Joint recursive inference is separate.
                continue;
            }
            if (visited.count() >= self.session.options.max_values) return false;
            if (!try self.unknownPrincipalBody(graph)) return false;
            try visited.put(a, child, false);
            try pending.append(a, .{ .key = child, .graph = graph });
        }
        return true;
    }
    fn unknownPrincipalBody(self: *ClosureRegion, graph: *const PrincipalGraph) RegionError!bool {
        if (!try principal_type_graph.matchesOpen(self.scratch_allocator, &graph.types, graph.root, &graph.types, graph.root, self.session.options.max_type_depth, self.session.options.max_values)) return false;
        for (graph.requirements) |requirement| if (!try self.unknownPrincipalConstraint(graph, requirement)) return false;
        // An alias or declared bound can infer a concrete endpoint even when
        // the caller currently sees only variables. Keep those equations in
        // ordinary collection instead of deferring their consequences.
        for (graph.aliases) |alias| {
            if (alias.instance == alias.principal) continue;
            if (!try principal_type_graph.matchesOpen(self.scratch_allocator, &graph.types, alias.principal, &graph.types, alias.instance, self.session.options.max_type_depth, self.session.options.max_values)) return false;
        }
        for (graph.functions) |function| if (!try principal_type_graph.matchesOpen(self.scratch_allocator, &graph.types, function, &graph.types, function, self.session.options.max_type_depth, self.session.options.max_values)) return false;
        return true;
    }
    fn unknownPrincipalConstraint(self: *ClosureRegion, graph: *const PrincipalGraph, constraint: Constraint) RegionError!bool {
        if (constraint.kind == .callback_use) return self.principalCallback(graph, constraint);
        if (constraint.solved) return true;
        if (constraint.kind == .scheme_use) {
            const product = graph.types.node(constraint.left);
            if (product.tag != .product) return false;
            for (graph.types.list(.{ .start = product.a, .len = product.b })) |part| {
                const node = graph.types.node(part);
                if (node.tag == .variable) continue;
                if (node.tag != .function or node.a != types.unit or node.b != types.unit) return false;
                const row = graph.types.row(node.c);
                if (row.labels.len != 0 or row.tail == .parameter) return false;
            }
            return true;
        }
        switch (constraint.kind) {
            .binary, .field, .result_dispatch, .physical_field, .receiver, .update, .collection, .record_merge, .type_head, .type_compare, .type_rep, .effect_rep, .effect_operation => {},
            else => return false,
        }
        // A known source constructor may shape the result, but a predicate's
        // selection owner must remain unknown. Caller-selected structures are
        // rejected separately by the source-to-caller skeleton match.
        switch (constraint.kind) {
            .binary => if (graph.types.node(constraint.left).tag != .variable and graph.types.node(constraint.right).tag != .variable) return false,
            .field, .physical_field, .receiver, .update, .collection => if (graph.types.node(constraint.left).tag != .variable) return false,
            .result_dispatch => if (graph.types.node(constraint.result).tag != .variable) return false,
            .record_merge => if (graph.types.node(constraint.left).tag != .variable and graph.types.node(constraint.right).tag != .variable) return false,
            .type_head => if (graph.types.node(try self.principalWitnessHead(graph, constraint.left)).tag != .variable) return false,
            .type_rep => if (!try self.unknownPrincipalData(graph, constraint.left)) return false,
            .effect_rep => {
                const carrier = graph.types.node(constraint.signature);
                if (carrier.tag != .function) return false;
                const row = graph.types.row(carrier.c);
                var open = row.tail == .variable;
                for (graph.types.rowLabels(carrier.c)) |label| for (graph.types.operationArguments(label)) |argument| {
                    open = open or try self.unknownPrincipalData(graph, argument);
                };
                if (!open) return false;
            },
            .type_compare => {
                const left = try self.principalWitnessHead(graph, constraint.left);
                const right = try self.principalWitnessHead(graph, constraint.right);
                if (graph.types.node(left).tag == .never or graph.types.node(right).tag == .never) return false;
                if (!try self.unknownPrincipalData(graph, left) and !try self.unknownPrincipalData(graph, right)) return false;
            },
            .effect_operation => {
                // The source fixes the operation family. Its residual action
                // still adds the exact label and checks the caller's row.
                if (constraint.identity.unit == 0) return false;
                const signature = graph.types.node(constraint.left);
                if (signature.tag != .function) return false;
                const row = graph.types.row(signature.c);
                if (row.tail == .parameter) return false;
            },
            else => {},
        }
        for ([_]types.Id{ constraint.left, constraint.right, constraint.result, constraint.signature }, 0..) |operand, index| {
            // Receiver checking waits for its owner; the Unit argument is
            // arity metadata, not a second operand dispatch candidate.
            if (constraint.kind == .receiver and index == 1 and operand == types.unit) continue;
            if (constraint.row_carrier and index == 3 and operand != 0) {
                const carrier = graph.types.node(operand);
                if (carrier.tag == .function and carrier.a == types.unit and carrier.b == types.unit) {
                    const row = graph.types.row(carrier.c);
                    if (row.labels.len == 0 and row.tail != .parameter) continue;
                }
            }
            if (operand != 0) {
                if (!try principal_type_graph.matchesOpen(self.scratch_allocator, &graph.types, operand, &graph.types, operand, self.session.options.max_type_depth, self.session.options.max_values)) return false;
            }
        }
        return true;
    }
    fn principalCallback(self: *ClosureRegion, graph: *const PrincipalGraph, constraint: Constraint) RegionError!bool {
        if (!constraint.callback_interface or constraint.callback_slot >= self.session.options.max_type_depth or constraint.callback_stage >= self.session.options.max_type_depth) return false;
        var cursor = graph.root;
        for (0..constraint.callback_slot) |_| {
            const arrow = graph.types.node(cursor);
            if (arrow.tag != .function) return false;
            cursor = arrow.b;
        }
        const owner = graph.types.node(cursor);
        if (owner.tag != .function) return false;
        const a = self.scratch_allocator;
        const depth = self.session.options.max_type_depth;
        const nodes = self.session.options.max_values;
        if (!try principal_type_graph.sameOpen(a, &graph.types, owner.a, constraint.signature, depth, nodes)) return false;
        cursor = constraint.signature;
        for (0..constraint.callback_stage) |_| {
            const arrow = graph.types.node(cursor);
            if (arrow.tag != .function) return false;
            cursor = arrow.b;
        }
        if (!try principal_type_graph.sameOpen(a, &graph.types, cursor, constraint.left, depth, nodes)) return false;
        const arrow = graph.types.node(constraint.left);
        if (arrow.tag != .function) return false;
        return try principal_type_graph.sameOpen(a, &graph.types, arrow.a, constraint.right, depth, nodes) and try principal_type_graph.sameOpen(a, &graph.types, arrow.b, constraint.result, depth, nodes);
    }
    fn principalWitnessHead(self: *ClosureRegion, graph: *const PrincipalGraph, root: types.Id) RegionError!types.Id {
        var head = root;
        for (0..self.session.options.max_type_depth) |_| {
            const node = graph.types.node(head);
            if (node.tag != .function) return head;
            head = node.b;
        }
        return error.TypeLimit;
    }
    fn unknownPrincipalData(self: *ClosureRegion, graph: *const PrincipalGraph, root: types.Id) RegionError!bool {
        var pending: std.ArrayList(types.Id) = .empty;
        defer pending.deinit(self.scratch_allocator);
        var seen: std.AutoHashMapUnmanaged(types.Id, void) = .empty;
        defer seen.deinit(self.scratch_allocator);
        try pending.append(self.scratch_allocator, root);
        var edges: usize = 0;
        while (pending.pop()) |id| {
            if (seen.contains(id)) continue;
            if (seen.count() >= self.session.options.max_values) return false;
            try seen.put(self.scratch_allocator, id, {});
            const node = graph.types.node(id);
            switch (node.tag) {
                .variable => return true,
                .unit, .boolean, .u32, .f32, .never, .type_constructor => {},
                .array, .list, .cursor => try pending.append(self.scratch_allocator, node.a),
                .product, .nominal => {
                    const children = if (node.tag == .nominal) graph.types.nominalArguments(node) else graph.types.list(.{ .start = node.a, .len = node.b });
                    try pending.appendSlice(self.scratch_allocator, children);
                    edges +|= children.len;
                },
                .record => for (0..node.b) |index| {
                    try pending.append(self.scratch_allocator, graph.types.recordField(node, index).ty);
                    edges +|= 1;
                },
                else => return false,
            }
            if (edges > self.session.options.max_children or pending.items.len > self.session.options.max_values) return false;
        }
        return false;
    }
    fn retainedComparison(self: *ClosureRegion) RegionError!bool {
        var pending: std.ArrayList(PrincipalGraph.Key) = .empty;
        defer pending.deinit(self.scratch_allocator);
        var seen: std.AutoHashMapUnmanaged(PrincipalGraph.Key, void) = .empty;
        defer seen.deinit(self.scratch_allocator);
        for (self.scratch.constraints.items) |constraint| {
            if (!constraint.solved and constraint.kind == .call_summary) try pending.append(self.scratch_allocator, .{ .target = constraint.target, .source_interface = self.source_interface, .deferred_member = constraint.deferred_member, .options = self.session.options });
        }
        var edges: usize = 0;
        while (pending.pop()) |key| {
            if (seen.contains(key)) continue;
            if (seen.count() >= self.session.options.max_values) return error.TypeLimit;
            try seen.put(self.scratch_allocator, key, {});
            const graph = self.session.specializations.call_summaries.principals.get(key, self.session) orelse return true;
            const source = graph orelse return true;
            for ([_][]const Constraint{ source.requirements, source.constraints }) |constraints| for (constraints) |constraint| {
                edges +|= 1;
                if (edges > self.session.options.max_children) return error.TypeLimit;
                if (!constraint.solved and constraint.kind == .type_compare) return true;
                if (constraint.kind == .call_summary or constraint.kind == .scheme_use) try pending.append(self.scratch_allocator, .{ .target = constraint.target, .source_interface = key.source_interface, .deferred_member = constraint.deferred_member, .options = key.options });
            };
            if (pending.items.len > self.session.options.max_values) return error.TypeLimit;
        }
        return false;
    }
    fn importPrincipal(self: *ClosureRegion, scope: u32, graph: *PrincipalGraph) RegionError!void {
        std.debug.assert(graph.key.target.unit == self.scratch.sources.items[scope].owner and graph.key.target.binding == self.scratch.sources.items[scope].binding);
        self.work_revision +|= 1;
        var copy: principal_type_graph.Copy = .{ .allocator = self.scratch_allocator, .source = &graph.types, .destination = &self.solver, .max_depth = self.session.options.max_type_depth, .max_nodes = self.session.options.max_values };
        defer copy.deinit();
        for (graph.imports) |entry| {
            const original = try self.importType(scope, entry.source, 0);
            const node = graph.types.node(entry.graph);
            if (node.tag == .variable) {
                if (copy.variables.get(node.a)) |prior| try self.unify(prior, original) else try copy.variables.put(self.scratch_allocator, node.a, original);
            }
        }
        for (graph.rows) |entry| {
            const existing = try self.importRowVariable(scope, entry.source);
            const row = graph.types.row(entry.graph);
            if (row.tail == .variable and row.labels.len == 0) {
                if (copy.row_variables.get(row.tail.variable)) |prior| try self.solver.unifyEffects(prior, existing) else try copy.row_variables.put(self.scratch_allocator, row.tail.variable, existing);
            }
        }
        for (graph.imports) |entry| try self.unify(try self.importType(scope, entry.source, 0), try copy.ty(entry.graph, 0));
        for (graph.rows) |entry| try self.solver.unifyEffects(try self.importRowVariable(scope, entry.source), try copy.row(entry.graph, 0));
        self.principal_only_used = true;
        try self.principalDependencies(graph, false);
        const source = self.scratch.sources.items[scope];
        try self.session.observePrincipalSource(source.owner, source.binding);
        if (self.session.receipt_tape) |tape| try tape.sources.append(self.session.allocator, .{ .unit = self.session.unitId(source.owner), .binding = source.binding });
        if (self.session.constant_recorder) |recorder| try recorder.source(self.session.allocator, .{ .unit = self.session.unitId(source.owner), .binding = source.binding });
        for (graph.actions) |action| switch (action) {
            .reference => |index| {
                const target_ = graph.references[index];
                const ref: core.BindingRef = .{ .unit = self.session.unitId(target_.unit), .binding = target_.binding };
                if (self.session.principal_reads) |reads| try reads.scalar(self.session.allocator, ref, 0);
                if (self.session.receipt_tape) |tape| {
                    try tape.sources.append(self.session.allocator, ref);
                    try tape.scalar_reads.append(self.session.allocator, .{ .target = ref, .evidence = 0 });
                }
            },
            .alias => |index| {
                const alias = graph.aliases[index];
                try self.appendAlias(.{ .instance = try copy.ty(alias.instance, 0), .principal = try copy.ty(alias.principal, 0) });
            },
            .function => |index| try self.appendFunction(try copy.ty(graph.functions[index], 0)),
            .constraint => |index| {
                const original = graph.constraints[index];
                const previous_origin = self.current_origin;
                const previous_use = self.current_use;
                self.current_use = original.use_node;
                self.current_origin = source.origin;
                if (original.use_node != 0 and original.kind == .call_summary) {
                    const caller_module = &self.session.units[source.owner];
                    if (self.session.unitId(source.owner) == self.session.diagnostic_context.entry and self.current_origin == null) {
                        self.current_origin = .{ .unit = self.session.unitId(source.owner), .span = caller_module.span(original.use_node) };
                    } else if (self.session.unitId(source.owner) != self.session.diagnostic_context.entry) {
                        var dependent = false;
                        for (graph.arguments[original.arguments.start..][0..original.arguments.len]) |argument| dependent = dependent or callerDependent(&caller_module.types, caller_module.typeOf(argument), 0);
                        if (!dependent) self.current_origin = .{ .unit = self.session.unitId(source.owner), .span = caller_module.span(original.use_node) };
                    }
                }
                if (self.callbackUseOrigin(source.owner, original.use_node)) |origin| self.current_origin = origin;
                defer self.current_use = previous_use;
                defer self.current_origin = previous_origin;
                if (original.kind == .call_summary) {
                    if (original.source_selection) {
                        var constraint = original;
                        constraint.scope = scope;
                        constraint.left = try copy.ty(original.left, 0);
                        try self.appendConstraint(constraint);
                        continue;
                    }
                    const deferred = self.defer_members;
                    self.defer_members = original.deferred_member;
                    defer self.defer_members = deferred;
                    try self.collectCall(scope, .{ .unit = self.session.unitId(original.target.unit), .binding = original.target.binding }, original.right, graph.arguments[original.arguments.start..][0..original.arguments.len]);
                } else {
                    var constraint = original;
                    constraint.scope = scope;
                    constraint.left = try copy.ty(original.left, 0);
                    constraint.right = try copy.ty(original.right, 0);
                    constraint.result = try copy.ty(original.result, 0);
                    constraint.signature = try copy.ty(original.signature, 0);
                    try self.appendConstraint(constraint);
                }
            },
        };
        self.session.principal_graph_imports += 1;
        self.session.counters.principal_graph_imports += 1;
    }
    fn collect(self: *ClosureRegion, scope: u32, body: core.Id) RegionError!void {
        return self.collectWithExit(scope, body, .{});
    }
    fn collectWithExit(self: *ClosureRegion, scope: u32, body: core.Id, exit: CollectionExit) RegionError!void {
        const allocator = self.session.allocator;
        if (self.collector.frames.items.len >= self.session.options.max_values) return error.TypeLimit;
        try self.collector.frames.append(allocator, .{ .scope = scope, .body = body, .deferred_member = self.defer_members, .exit = exit });
        if (self.collector.active) return;
        self.collector.active = true;
        defer self.collector.active = false;
        const saved_deferred = self.defer_members;
        defer self.defer_members = saved_deferred;
        errdefer self.collector.clear(allocator);
        while (self.collector.frames.pop()) |stored| {
            var frame = stored;
            var retained = false;
            defer if (!retained) frame.walk.deinit(allocator);
            self.defer_members = frame.deferred_member;
            if (!frame.started) {
                frame.walk = try self.startCollection(frame.scope, frame.body);
                frame.started = true;
            }
            const id = try frame.walk.next(allocator) orelse {
                if (frame.exit.remove) |target_| _ = self.scratch.unresolved_calls.remove(target_);
                if (frame.exit.lexical_caller) |caller| try self.shareLexical(frame.scope, caller, frame.exit.lexical_scheme);
                if (frame.exit.demand) |demand| {
                    if (self.scratch.completed_demands.items.len >= self.session.options.max_values) return error.TypeLimit;
                    try self.scratch.completed_demands.append(self.scratch_allocator, demand);
                }
                continue;
            };
            if (frame.walk.count > self.session.options.max_values) return error.TypeLimit;
            if (frame.walk.recipe != null) self.session.specializations.body_recipes.replayed_visits += 1;
            const first_child = self.collector.frames.items.len;
            try self.collectNode(frame.scope, id, &frame.walk);
            // Child bodies retain the original DFS order and contextual flags;
            // the caller's walker resumes only after their completion exits.
            std.mem.reverse(CollectionFrame, self.collector.frames.items[first_child..]);
            try self.collector.frames.insert(allocator, first_child, frame);
            retained = true;
        }
    }
    fn startCollection(self: *ClosureRegion, scope: u32, body: core.Id) RegionError!body_recipe.Walk {
        if (self.session.principal_reads) |reads| {
            const source = self.scratch.sources.items[scope];
            if (source.binding != 0 and self.session.units[source.owner].binding(source.binding).kind == .global) {
                try reads.source(self.session.allocator, .{ .unit = self.session.unitId(source.owner), .binding = source.binding });
            } else if (self.session.unitId(source.owner) != reads.root.unit) {
                const unit = self.session.unitId(source.owner);
                if (try self.session.regions.principal_source_owners.node(self.session.allocator, self.session.units, source.owner, body, self.session.options.max_values)) |declaration| {
                    try reads.source(self.session.allocator, .{ .unit = unit, .binding = declaration });
                    self.session.counters.principal_containing_sources += 1;
                } else {
                    try reads.sourceUnit(self.session.allocator, unit);
                    self.session.counters.principal_module_sources += 1;
                }
            }
        }
        if (!self.building_principal and body == self.scratch.sources.items[scope].body) try self.registerBodyScope(scope);
        const recipe = if (self.session.options.reuse_body_recipes) try self.session.specializations.body_recipes.get(self.session.allocator, self.session.units, .{ .owner = self.scratch.sources.items[scope].owner, .body = body, .callables = self.include_callables }, self.session.options.max_values) else null;
        // This immutable syntax classification precedes graph admission, so a
        // later-discovered inline capture cannot retroactively turn a source
        // callback interface into a complete lexical input. No recipe means
        // no proof of an empty lexical boundary; ordinary checking remains.
        self.unkeyed_capture_inputs = self.unkeyed_capture_inputs or (if (recipe) |plan| plan.has_lexical_captures else self.include_callables);
        if (try self.principalGraph(scope, body)) |graph| {
            try self.importPrincipal(scope, graph);
            return .{};
        }
        self.work_revision +|= 1;
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        if (self.session.receipt_tape) |tape| {
            const source = self.scratch.sources.items[scope];
            if (source.binding != 0 and module.binding(source.binding).kind == .global) try tape.sources.append(self.session.allocator, .{ .unit = self.session.unitId(source.owner), .binding = source.binding });
        }
        if (self.session.constant_recorder) |recorder| {
            const source = self.scratch.sources.items[scope];
            if (source.binding != 0 and module.binding(source.binding).kind == .global) try recorder.source(self.session.allocator, .{ .unit = self.session.unitId(source.owner), .binding = source.binding });
        }
        try self.callableDefinitions(self.scratch.sources.items[scope].owner);
        var work: body_recipe.Walk = .{ .recipe = recipe };
        errdefer work.deinit(self.session.allocator);
        try work.append(self.session.allocator, body);
        return work;
    }
    fn normalizePackPayload(self: *ClosureRegion, scope: u32, pack_id: core.Id, payload: types.Id) RegionError!void {
        if (!self.solver.has_projections) return;
        try self.associatedSync();
        errdefer self.associatedDebit();
        try self.packPayloadNode(scope, pack_id, payload, 0);
        try self.associatedSync();
    }
    fn packPayloadNode(self: *ClosureRegion, scope: u32, pack_id: core.Id, root: types.Id, depth: usize) RegionError!void {
        if (depth >= 128 or self.session.associated_remaining == 0) return error.TypeLimit;
        self.session.associated_remaining -= 1;
        const id = self.solver.head(root, 0);
        const node = self.solver.node(id);
        switch (node.tag) {
            .projection => {
                const module = &self.session.units[self.scratch.sources.items[scope].owner];
                const arguments = try self.scratch_allocator.dupe(types.Id, self.solver.nominalArguments(node));
                defer self.scratch_allocator.free(arguments);
                for (module.dictionary_selections) |selection| {
                    if (self.session.associated_remaining == 0) return error.TypeLimit;
                    self.session.associated_remaining -= 1;
                    if (selection.owner != pack_id) continue;
                    const goal = module.types.quantifierGoals(selection.quantifier)[selection.goal];
                    if (goal.kind != .contract or goal.identity.unit != node.a or goal.identity.decl != node.b) continue;
                    const selected = switch (selection.proof) {
                        .given => continue,
                        .selected => |proof| module.selected_proofs[proof],
                    };
                    if (selected.kind != .implementation or selected.arguments.len != arguments.len) continue;
                    var same = true;
                    for (module.types.list(selected.arguments), arguments) |argument, actual| {
                        const expected = try self.importType(scope, argument, 0);
                        if (!try self.solver.equalSymbolic(try self.solver.resolve(expected, 0), try self.solver.resolve(actual, 0))) same = false;
                    }
                    if (!same) continue;
                    const member_name = self.solver.projectionMember(node);
                    for (module.selected_members[selected.members.start..][0..selected.members.len]) |member| {
                        if (self.session.associated_remaining == 0) return error.TypeLimit;
                        self.session.associated_remaining -= 1;
                        if (member.name != member_name) continue;
                        if (member.kind != .type_) return error.TypeMismatch;
                        // Only the substituted payload copy receives this
                        // selected equation; its sealed quantifier stays opaque.
                        try self.solver.bindAssociated(id, try self.importType(scope, member.root, 0));
                        return;
                    }
                    return error.TypeMismatch;
                }
            },
            .function, .state_provider => {
                try self.packPayloadNode(scope, pack_id, node.a, depth + 1);
                try self.packPayloadNode(scope, pack_id, node.b, depth + 1);
                if (node.tag == .state_provider) try self.packPayloadNode(scope, pack_id, node.c, depth + 1);
            },
            .usage, .array, .list, .cursor, .demand, .provider, .resolver => try self.packPayloadNode(scope, pack_id, node.a, depth + 1),
            .product, .nominal => {
                var children: []const types.Id = undefined;
                if (node.tag == .product) children = self.solver.list(.{ .start = node.a, .len = node.b }) else children = self.solver.nominalArguments(node);
                const saved = try self.scratch_allocator.dupe(types.Id, children);
                defer self.scratch_allocator.free(saved);
                for (saved) |child| try self.packPayloadNode(scope, pack_id, child, depth + 1);
            },
            .record => for (0..node.b) |ordinal| try self.packPayloadNode(scope, pack_id, self.solver.recordField(node, ordinal).ty, depth + 1),
            else => {},
        }
    }
    fn collectReference(self: *ClosureRegion, scope: u32, id: core.Id) RegionError!void {
        const owner = self.scratch.sources.items[scope].owner;
        const module = &self.session.units[owner];
        const n = module.node(id);
        if (n.tag == .reference) {
            const reference = module.reference(id);
            if (self.session.constant_recorder) |recorder| {
                const target_ = try self.session.external(try self.session.target(owner, reference));
                if (self.session.units[target_.unit].binding(target_.binding).kind == .global) try recorder.source(self.session.allocator, .{ .unit = self.session.unitId(target_.unit), .binding = target_.binding });
            }
            if (reference.unit == 0 or reference.unit == self.session.unitId(self.scratch.sources.items[scope].owner)) {
                const binding = module.binding(reference.binding);
                if (binding.kind == .local) {
                    var principal = try self.importType(scope, binding.ty, 0);
                    if (module.types.node(binding.ty).tag == .forall and module.types.node(n.ty).tag != .forall) principal = (try self.solver.instantiateRank(principal, false)).body;
                    try self.appendAlias(.{ .instance = try self.importType(scope, n.ty, 0), .principal = principal });
                }
            }
        }
        if (self.include_callables and !self.source_interface and !self.building_principal and n.tag == .reference) {
            const resolved = try self.session.external(try self.session.target(self.scratch.sources.items[scope].owner, module.reference(id)));
            const producer = &self.session.units[resolved.unit];
            const binding = producer.binding(resolved.binding);
            const definition = producer.body(resolved.binding);
            const cached = self.session.slot(resolved);
            if (self.session.principal_reads) |reads| if (binding.kind == .global) {
                if (definition == null or (definition.?.runtime and !definition.?.is_function)) reads.invalidate(.runtime_source) else {
                    const actual_read = if (!definition.?.runtime and cached.state == .complete and self.session.valueInfo(cached.value).kind == .scalar) self.session.valueEvidence(cached.value) else 0;
                    try reads.scalar(self.session.allocator, .{ .unit = self.session.unitId(resolved.unit), .binding = resolved.binding }, actual_read);
                }
            };
            if (self.session.receipt_tape) |tape| if (binding.kind == .global) {
                const target_ref: core.BindingRef = .{ .unit = self.session.unitId(resolved.unit), .binding = resolved.binding };
                try tape.sources.append(self.session.allocator, target_ref);
                const actual_read = if (definition != null and !definition.?.runtime and cached.state == .complete and self.session.valueInfo(cached.value).kind == .scalar) self.session.valueEvidence(cached.value) else 0;
                try tape.scalar_reads.append(self.session.allocator, .{ .target = target_ref, .evidence = actual_read });
                if (definition == null or (definition.?.runtime and !definition.?.is_function)) tape.unknown = true;
            };
            if (binding.kind == .global and definition != null and !definition.?.runtime and cached.state == .complete and self.session.valueInfo(cached.value).kind == .scalar) {
                // A completed immutable scalar supplies its exact selected type.
                const actual = self.session.valueEvidence(cached.value);
                if (actual != 0) try self.unify(try self.importType(scope, n.ty, 0), try self.importEvidence(actual, 0));
            }
        }
        if (self.include_callables and n.tag == .reference and module.types.node(n.ty).tag == .function) {
            const definition = self.definitionIndex().get(.{ .owner = self.scratch.sources.items[scope].owner, .node = id });
            if (definition == null or definition.? == self.scratch.sources.items[scope].binding) {
                const previous = self.defer_members;
                self.defer_members = true;
                defer self.defer_members = previous;
                try self.collectCallAt(scope, module.reference(id), n.ty, &.{}, id);
            }
        }
    }
    fn collectPackagePack(self: *ClosureRegion, scope: u32, id: core.Id, work: *body_recipe.Walk) RegionError!void {
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        const n = module.node(id);
        const package = self.solver.node(try self.importType(scope, n.ty, 0));
        if (package.tag != .existential or package.c != n.c) return error.UnresolvedType;
        const witnesses = try self.scratch_allocator.alloc(types.Id, n.c);
        defer self.scratch_allocator.free(witnesses);
        for (module.types.list(.{ .start = n.b, .len = n.c }), witnesses) |ty, *witness| witness.* = try self.importType(scope, ty, 0);
        const payload = try self.solver.substitute(package.a, self.solver.list(.{ .start = package.b, .len = package.c }), witnesses);
        try self.normalizePackPayload(scope, id, payload);
        try self.appendAlias(.{ .instance = try self.importType(scope, module.typeOf(n.a), 0), .principal = payload });
        try work.append(self.session.allocator, n.a);
    }
    fn collectPackageUnpack(self: *ClosureRegion, scope: u32, id: core.Id, work: *body_recipe.Walk) RegionError!void {
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        const n = module.node(id);
        const package = self.solver.node(try self.importType(scope, module.typeOf(n.a), 0));
        const opening = module.packageOpening(id);
        if (package.tag != .existential or package.c != opening.binders.len) return error.UnresolvedType;
        const rigid_scope = try self.solver.rigidScope();
        for (module.types.list(opening.binders), 0..) |binder, ordinal| {
            const leaf = module.types.node(binder);
            if (leaf.tag != .bound or leaf.a != ordinal or leaf.b != 0 or leaf.c != n.b) return error.UnresolvedType;
            const binder_key: Import = .{ .scope = scope, .ty = binder };
            if (self.scratch.imported.contains(binder_key)) return error.UnresolvedType;
            try self.scratch.imported.put(self.scratch_allocator, binder_key, try self.solver.rigid(rigid_scope, @intCast(ordinal), 0));
        }
        try work.appendSlice(self.session.allocator, &.{ n.a, opening.body });
    }
    fn collectArrayNode(self: *ClosureRegion, scope: u32, id: core.Id, work: *body_recipe.Walk) RegionError!void {
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        const n = module.node(id);
        const args = module.children(id);
        const operation = module.arrayOperation(id);
        if (operation == .cursor_has or operation == .cursor_value or operation == .cursor_advance) {
            // A generic cursor retains its collection kind as well
            // as its element. Replay that relationship when a body
            // is specialized, just as the source checker does.
            const collection = try self.solver.fresh();
            try self.unify(try self.importType(scope, module.typeOf(args[0]), 0), try self.solver.sequence(.cursor, collection));
            try self.appendConstraint(.{
                .kind = .collection,
                .scope = scope,
                .node = id,
                .left = collection,
                .result = if (operation == .cursor_value) try self.importType(scope, n.ty, 0) else try self.solver.fresh(),
            });
        }
        if (module.arrayOperation(id) == .get and module.types.node(module.typeOf(args[0])).tag == .variable) try self.appendConstraint(.{
            .kind = .collection,
            .scope = scope,
            .node = id,
            .left = try self.importType(scope, module.typeOf(args[0]), 0),
            .result = try self.importType(scope, n.ty, 0),
        });
        try work.appendSlice(self.session.allocator, args);
    }
    fn collectResolverNode(self: *ClosureRegion, scope: u32, id: core.Id, work: *body_recipe.Walk) RegionError!void {
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        const metadata = module.resolverInfo(id);
        try work.append(self.session.allocator, metadata.resolver);
        try work.appendSlice(self.session.allocator, module.resolverArguments(id));
        if (metadata.operation == .forward) {
            const arguments = module.resolverArguments(id);
            if (arguments.len != 1) return error.TypeMismatch;
            try self.unify(try self.importType(scope, module.typeOf(arguments[0]), 0), try self.importType(scope, module.typeOf(id), 0));
        }
        if (metadata.operation == .run) {
            const arguments = module.resolverArguments(id);
            if (arguments.len != 1) return error.TypeMismatch;
            const action = try self.importType(scope, module.typeOf(arguments[0]), 0);
            const signature = self.solver.node(try self.solver.resolve(action, 0));
            if (signature.tag != .function) return error.TypeMismatch;
            try self.unify(action, try self.solver.functionWithEffects(types.unit, try self.importType(scope, module.typeOf(id), 0), signature.c));
        }
        if (self.include_callables and (metadata.operation == .run or metadata.operation == .bind or metadata.operation == .iterate)) for (module.resolverArguments(id)) |argument| {
            const callback = module.node(argument);
            if (callback.tag == .closure) {
                try self.alignClosure(scope, argument);
                try work.append(self.session.allocator, module.closure(argument).body);
            }
        };
        if (metadata.operation == .pure or metadata.operation == .bind or metadata.operation == .iterate) {
            if (metadata.method_type == 0) return error.UnresolvedType;
            const signature = try self.importType(scope, metadata.method_type, 0);
            var suffix = signature;
            for (module.resolverArguments(id)) |argument| {
                const arrow = self.solver.node(try self.solver.resolve(suffix, 0));
                if (arrow.tag != .function) return error.TypeMismatch;
                try self.unify(arrow.a, try self.importType(scope, module.typeOf(argument), 0));
                suffix = arrow.b;
            }
            try self.unify(suffix, try self.importType(scope, module.typeOf(id), 0));
            try self.appendConstraint(.{ .scope = scope, .node = id, .left = try self.importType(scope, module.typeOf(metadata.resolver), 0), .right = signature, .result = try self.importType(scope, module.typeOf(id), 0), .kind = .resolver });
        }
        if (metadata.operation != .monad) try self.appendConstraint(.{ .scope = scope, .node = id, .left = try self.importType(scope, module.typeOf(metadata.resolver), 0), .result = try self.importType(scope, module.typeOf(id), 0), .kind = .resolver_shape });
    }
    fn collectUpdateNode(self: *ClosureRegion, scope: u32, id: core.Id, work: *body_recipe.Walk) RegionError!void {
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        const n = module.node(id);
        const update = module.updateInfo(id);
        try work.appendSlice(self.session.allocator, &.{ update.root, update.value });
        const selectors = module.updateSelectors(id);
        var assigned = try self.importType(scope, module.typeOf(update.value), 0);
        var reverse = if (selectors.len != 0) selectors.len else module.updatePath(id).len;
        while (reverse != 0) {
            reverse -= 1;
            const selector = if (selectors.len != 0) selectors[reverse] else selector: {
                const projection_index = module.updatePath(id)[reverse];
                const projection = module.projection(projection_index);
                break :selector core.UpdateStep{ .kind = .field, .projection = projection_index, .source_type = projection.source_type, .result_type = projection.result_type };
            };
            if (selector.kind == .index) {
                try self.unify(assigned, try self.importType(scope, selector.result_type, 0));
                assigned = try self.importType(scope, selector.source_type, 0);
            } else {
                const result = if (reverse == 0) try self.importType(scope, n.ty, 0) else try self.solver.fresh();
                try self.appendConstraint(.{ .scope = scope, .node = id, .left = try self.importType(scope, selector.source_type, 0), .right = assigned, .result = result, .signature = try self.solver.function(types.unit, types.unit), .member = module.projection(selector.projection).field, .kind = .update, .deferred_member = self.defer_members });
                assigned = result;
            }
        }
        if (selectors.len != 0) for (selectors) |selector| {
            if (selector.kind == .index) {
                try work.append(self.session.allocator, selector.index);
                if (module.types.node(selector.source_type).tag == .variable) try self.appendConstraint(.{
                    .kind = .collection,
                    .scope = scope,
                    .node = id,
                    .left = try self.importType(scope, selector.source_type, 0),
                    .result = try self.importType(scope, selector.result_type, 0),
                });
                continue;
            }
            try self.appendConstraint(.{ .scope = scope, .node = id, .left = try self.importType(scope, selector.source_type, 0), .result = try self.importType(scope, selector.result_type, 0), .projection = selector.projection, .kind = .field, .writable = true, .deferred_member = self.defer_members });
        } else for (module.updatePath(id)) |projection_index| {
            const projection = module.projection(projection_index);
            try self.appendConstraint(.{ .scope = scope, .node = id, .left = try self.importType(scope, projection.source_type, 0), .result = try self.importType(scope, projection.result_type, 0), .projection = projection_index, .kind = .field, .writable = true, .deferred_member = self.defer_members });
        };
    }
    fn collectSuspensionNode(self: *ClosureRegion, scope: u32, id: core.Id) RegionError!void {
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        const n = module.node(id);
        if (self.retain_selected and !try self.session.startupSelectorFree(self.scratch.sources.items[scope].owner, module.closures[n.a].body)) self.startup_coverage_complete = false;
        if (self.complete_demand_bodies) {
            const closure = module.closures[n.a];
            const actual = try self.importType(scope, n.ty, 0);
            const demanded = self.solver.node(try self.solver.resolve(actual, 0));
            if (demanded.tag != .demand) return error.TypeMismatch;
            try self.unify(demanded.a, try self.importType(scope, module.typeOf(closure.body), 0));
            if (closure.function_type != 0) try self.unify(try self.importType(scope, closure.function_type, 0), try self.solver.functionWithEffects(types.unit, demanded.a, demanded.c));
            if (closure.qualifier != 0 and closure.qualifier != self.scratch.sources.items[scope].binding) try self.importScheme(scope, module.binding(closure.qualifier).scheme, closure.body);
            try self.collectWithExit(scope, closure.body, .{ .demand = .{ .scope = scope, .node = id, .body = closure.body, .root = actual } });
        }
    }
    fn collectClosureNode(self: *ClosureRegion, scope: u32, id: core.Id) RegionError!void {
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        const qualifier = self.definitionIndex().get(.{ .owner = self.scratch.sources.items[scope].owner, .node = id }) orelse module.closure(id).qualifier;
        if (qualifier != 0 and self.scratch.sources.items[scope].binding != qualifier) {
            if (self.retain_selected and !try self.session.startupSelectorFree(self.scratch.sources.items[scope].owner, module.closure(id).body)) self.startup_coverage_complete = false;
            return;
        }
        try self.alignClosure(scope, id);
        const previous = self.defer_members;
        self.defer_members = true;
        defer self.defer_members = previous;
        try self.collect(scope, module.closure(id).body);
    }
    fn collectChildren(self: *ClosureRegion, scope: u32, id: core.Id, work: *body_recipe.Walk) RegionError!void {
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        const n = module.node(id);
        switch (n.tag) {
            .task => {
                if (n.c == @backingInt(@import("../check/task_types.zig").Op.receive)) {
                    const input = try self.importType(scope, module.typeOf(module.children(id)[0]), 0);
                    const output = try self.importType(scope, n.ty, 0);
                    var signature = try self.solver.functionWithEffects(input, output, try self.solver.freshEffects());
                    for (module.obligations) |goal| {
                        if (goal.kind == .task_receive and std.meta.eql(goal.span, module.span(id))) {
                            signature = try self.importType(scope, goal.signature, 0);
                            break;
                        }
                    }
                    try self.appendConstraint(.{ .kind = .task_receive, .scope = scope, .node = id, .left = input, .result = output, .signature = signature });
                }
                try work.appendSlice(self.session.allocator, module.children(id));
            },
            .resource_release, .usage_share, .usage_read => try work.append(self.session.allocator, n.a),
            .resource_scope => try work.appendSlice(self.session.allocator, &.{ n.a, n.b, n.c }),
            .resource_acquire, .usage_borrow, .staging => try work.appendSlice(self.session.allocator, &.{ n.a, n.b }),
            .package_pack => try self.collectPackagePack(scope, id, work),
            .package_unpack => try self.collectPackageUnpack(scope, id, work),
            .contract_method => {
                const template = module.member_templates[n.a];
                var arguments: std.ArrayList(types.Id) = .empty;
                defer arguments.deinit(self.scratch_allocator);
                for (module.types.list(template.arguments)) |root| try arguments.append(self.scratch_allocator, try self.importType(scope, root, 0));
                try self.appendConstraint(.{ .scope = scope, .node = id, .kind = .implementation_method, .identity = template.contract, .member = template.name, .left = try self.solver.product(arguments.items), .result = try self.importType(scope, n.ty, 0) });
            },
            .scalar, .associated, .logical, .record_merge, .type_same, .apply, .effect_provider, .handle, .proof_guard => try work.appendSlice(self.session.allocator, &.{ n.a, n.b }),
            .if_value, .if_stmt, .state_provider => try work.appendSlice(self.session.allocator, &.{ n.a, n.b, n.c }),
            .array_op => try self.collectArrayNode(scope, id, work),
            .block, .suite, .product, .record, .array, .call => try work.appendSlice(self.session.allocator, module.children(id)),
            .bind => {
                const binding = module.binding(n.a);
                if (module.types.node(binding.ty).tag != .function) try self.importScheme(scope, binding.scheme, n.b);
                try work.append(self.session.allocator, n.b);
            },
            .return_, .project, .result_associated, .force => try work.append(self.session.allocator, n.a),
            .construct => try work.append(self.session.allocator, n.b),
            .pattern_bind => {
                try self.collectStartupPatterns(scope, &.{n.a});
                try work.appendSlice(self.session.allocator, &.{ n.b, n.c });
            },
            .match => {
                if (self.retain_selected) for (module.matchArms(id)) |arm| for (module.armRows(arm)) |row| {
                    try self.collectStartupPatterns(scope, module.rowPatterns(row));
                };
                try work.appendSlice(self.session.allocator, module.matchInputs(id));
                for (module.matchArms(id)) |arm| try work.appendSlice(self.session.allocator, &.{ arm.guard, arm.body });
            },
            .loop => {
                const iteration = module.loopInfo(id);
                try self.collectStartupPatterns(scope, &.{iteration.pattern});
                if (iteration.kind == .array and iteration.pattern != 0 and module.types.node(module.typeOf(iteration.first)).tag == .variable) try self.appendConstraint(.{
                    .kind = .collection,
                    .scope = scope,
                    .node = id,
                    .left = try self.importType(scope, module.typeOf(iteration.first), 0),
                    .result = try self.importType(scope, module.pattern(iteration.pattern).ty, 0),
                });
                try work.appendSlice(self.session.allocator, &.{ iteration.first, iteration.end, iteration.body });
            },
            .break_ => try work.appendSlice(self.session.allocator, module.breakValues(id)),
            .resolver_op => try self.collectResolverNode(scope, id, work),
            .update => try self.collectUpdateNode(scope, id, work),
            .operation_value => try self.operationConstraint(scope, id, module.operationValue(id)),
            .closure => if (self.include_callables) try self.collectClosureNode(scope, id),
            .effect_reflection => {
                const kind: checked_types.ReflectionKind = @fromBackingInt(@intCast(n.a));
                if (kind == .count or kind == .has or kind == .same) try work.append(self.session.allocator, n.b);
                if (n.c != 0) try work.append(self.session.allocator, n.c);
            },
            .computation, .effect_scope => try work.append(self.session.allocator, n.a),
            .request_decision => try work.appendSlice(self.session.allocator, &.{ n.b, n.c }),
            .request_loop => {
                const metadata = module.requestLoopInfo(id);
                try self.collectStartupPatterns(scope, &.{metadata.completion_pattern});
                try work.appendSlice(self.session.allocator, &.{ metadata.computation, metadata.completion_body });
                for (module.requestArms(id)) |arm| try work.append(self.session.allocator, arm.callback);
            },
            .suspend_ => try self.collectSuspensionNode(scope, id),
            .constant, .reference, .constructor_function, .primitive_function, .panic, .type_constructor => {},
            .invalid => return error.UnresolvedType,
        }
    }
    fn collectNode(self: *ClosureRegion, scope: u32, id: core.Id, work: *body_recipe.Walk) RegionError!void {
        const previous_use = self.current_use;
        self.current_use = id;
        defer self.current_use = previous_use;
        const previous_origin = self.current_origin;
        self.current_origin = self.scratch.sources.items[scope].origin;
        const owner = self.scratch.sources.items[scope].owner;
        const module_ = &self.session.units[owner];
        const node_ = module_.node(id);
        if (node_.tag == .call or node_.tag == .apply or node_.tag == .associated or node_.tag == .result_associated) {
            if (self.session.unitId(owner) == self.session.diagnostic_context.entry and self.current_origin == null) {
                self.current_origin = .{ .unit = self.session.unitId(owner), .span = module_.span(id) };
            } else if (self.session.unitId(owner) != self.session.diagnostic_context.entry) {
                if (!callerDependentUse(module_, id)) self.current_origin = .{ .unit = self.session.unitId(owner), .span = module_.span(id) };
            }
        }
        if (self.callbackUseOrigin(owner, id)) |origin| self.current_origin = origin;
        defer self.current_origin = previous_origin;
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        const n = module.node(id);
        if (self.building_principal) {
            switch (n.tag) {
                .closure, .suspend_, .force, .request_loop, .request_decision, .resolver_op, .invalid => return error.UnresolvedType,
                else => {},
            }
            if (n.tag == .reference) {
                const resolved = try self.session.external(try self.session.target(self.scratch.sources.items[scope].owner, module.reference(id)));
                const producer = &self.session.units[resolved.unit];
                if (producer.binding(resolved.binding).kind == .global) {
                    if (producer.body(resolved.binding) == null or producer.types.node(producer.binding(resolved.binding).ty).tag != .function) return error.UnresolvedType;
                    if (!self.source_interface) try self.appendReference(resolved);
                }
            }
        }
        if (self.session.receipt_tape) |tape| {
            tape.collected += 1;
            // A complete refinement query owns this checked demand header,
            // without collecting or creating its suspended value/body. Actual
            // creation/history reads still revoke the tape at their own sites.
            const refinement_header = n.tag == .suspend_ and self.session.refinement_observation != null and !self.source_interface and !self.building_principal and !self.retain_selected and !self.complete_demand_bodies;
            if (!refinement_header and (n.tag == .suspend_ or n.tag == .request_loop or n.tag == .request_decision)) tape.unknown = true;
        }
        if (n.tag == .reference) try self.collectReference(scope, id);
        const source_signature = module.dispatchSignature(id);
        const dispatch_signature = if (source_signature == 0) 0 else try self.importType(scope, source_signature, 0);
        if (n.tag == .handle) if (module.handleEffects(id)) |handler| {
            try self.appendConstraint(.{ .scope = scope, .node = id, .left = try self.importType(scope, handler.first, 0), .right = if (handler.second == 0) 0 else try self.importType(scope, handler.second, 0), .result = try self.solver.functionWithEffects(types.unit, types.unit, try self.importRow(scope, handler.residual, 0)), .signature = try self.solver.functionWithEffects(types.unit, types.unit, try self.importRow(scope, handler.extended, 0)), .kind = .effect_handler });
        };
        if (self.include_callables and n.tag == .call) try self.collectCallAt(scope, module.call(id).target, module.call(id).callee_type, module.children(id), id);
        if (self.include_callables and n.tag == .apply) {
            const callee = module.node(n.a);
            const callback = if (self.building_principal) self.callbackOrigin(scope, n.a) else null;
            if (callback) |origin| try self.callbackUse(scope, id, origin);
            if (callee.tag == .closure) {
                try self.alignClosure(scope, n.a);
                try work.append(self.session.allocator, module.closure(n.a).body);
            }
            if (callback == null and callee.tag == .reference) {
                const reference = module.reference(n.a);
                const target_ = try self.session.external(try self.session.target(self.scratch.sources.items[scope].owner, reference));
                const binding = self.session.units[target_.unit].binding(target_.binding);
                if (binding.kind == .global or binding.initializer != 0) try self.collectCallAt(scope, reference, callee.ty, &.{n.b}, id) else if (self.retain_selected) {
                    self.startup_coverage_complete = false;
                }
            } else if (callback == null and callee.tag != .closure and self.retain_selected) {
                self.startup_coverage_complete = false;
            }
            if (self.building_principal and callback == null and !self.sourceCallable(scope, n.a)) return error.UnresolvedType;
        }
        if (n.tag == .record_merge) try self.appendConstraint(.{ .scope = scope, .node = id, .left = try self.importType(scope, module.typeOf(n.a), 0), .right = try self.importType(scope, module.typeOf(n.b), 0), .result = try self.importType(scope, n.ty, 0), .kind = .record_merge });
        if (self.source_interface and n.tag == .type_same) try self.appendConstraint(.{ .scope = scope, .node = id, .left = try self.importType(scope, module.typeOf(n.a), 0), .right = try self.importType(scope, module.typeOf(n.b), 0), .result = types.boolean, .kind = .type_compare });
        if (n.tag == .associated or (n.tag == .scalar and n.c != 0 and n.b != 0)) try self.appendConstraint(.{ .scope = scope, .node = id, .left = try self.importType(scope, module.typeOf(n.a), 0), .right = try self.importType(scope, module.typeOf(n.b), 0), .result = try self.importType(scope, n.ty, 0), .signature = dispatch_signature, .deferred_member = self.defer_members, .op = Session.operator(n.op), .member = if (n.tag == .associated) n.c else 0 });
        if (n.tag == .project) try self.appendConstraint(.{ .scope = scope, .node = id, .left = try self.importType(scope, module.typeOf(n.a), 0), .result = try self.importType(scope, n.ty, 0), .signature = dispatch_signature, .projection = n.b, .kind = .field, .deferred_member = self.defer_members });
        if (n.tag == .result_associated) try self.appendConstraint(.{ .scope = scope, .node = id, .left = try self.importType(scope, module.typeOf(n.a), 0), .result = try self.importType(scope, n.ty, 0), .signature = dispatch_signature, .member = n.b, .kind = .result_dispatch, .deferred_member = self.defer_members });
        try self.collectChildren(scope, id, work);
    }
    fn solve(self: *ClosureRegion) RegionError!void {
        return self.solveMode(false);
    }
    /// Local uses retain their producer's selected data facts. Callable
    /// components keep their own instances and rows; unresolved producer
    /// variables never acquire facts from a use.
    fn solveDataAliasesReference(self: *ClosureRegion) RegionError!bool {
        var changed = false;
        while (true) {
            const before = self.solver.cursor();
            for (self.scratch.data_aliases.items) |*alias| {
                if (alias.solved) continue;
                alias.solved = try self.transferDataFacts(alias.principal, alias.instance, 0);
            }
            if (self.solver.cursor() == before) return changed;
            changed = true;
        }
    }
    fn transferDataFacts(self: *ClosureRegion, principal: types.Id, instance: types.Id, depth: usize) RegionError!bool {
        if (depth >= self.session.options.max_type_depth) return error.TypeLimit;
        const actual = try self.solver.resolve(principal, 0);
        if (try self.closedDataShape(actual, depth)) {
            try self.unify(instance, actual);
            return true;
        }
        const source = self.solver.node(actual);
        const use = self.solver.node(try self.solver.resolve(instance, 0));
        if (source.tag == .variable) return false;
        if (source.tag == .usage and source.c == 0 and (source.b == @backingInt(types.UsageKind.once) or source.b == @backingInt(types.UsageKind.many)) and self.solver.node(try self.solver.resolve(source.a, 0)).tag == .function) return true;
        if (source.tag == .function or source.tag == .demand or source.tag == .provider or source.tag == .state_provider or source.tag == .resolver or source.tag == .type_constructor) return true;
        if (use.tag == .variable) return false;
        if (source.tag != use.tag) return error.TypeMismatch;
        switch (source.tag) {
            .array, .list, .cursor => return self.transferDataFacts(source.a, use.a, depth + 1),
            .product => {
                if (source.b != use.b) return error.TypeMismatch;
                var complete = true;
                for (0..source.b) |index| {
                    const left = self.solver.list(.{ .start = source.a, .len = source.b })[index];
                    const right = self.solver.list(.{ .start = use.a, .len = use.b })[index];
                    complete = try self.transferDataFacts(left, right, depth + 1) and complete;
                }
                return complete;
            },
            .record => {
                if (source.b != use.b) return error.TypeMismatch;
                var complete = true;
                for (0..source.b) |index| {
                    const left = self.solver.recordField(source, index);
                    const right = for (0..use.b) |other| {
                        const candidate = self.solver.recordField(use, other);
                        if (left.name == candidate.name) break candidate;
                    } else return error.TypeMismatch;
                    complete = try self.transferDataFacts(left.ty, right.ty, depth + 1) and complete;
                }
                return complete;
            },
            .nominal => {
                if (source.a != use.a or source.b != use.b or self.solver.nominalArguments(source).len != self.solver.nominalArguments(use).len) return error.TypeMismatch;
                var complete = true;
                for (0..self.solver.nominalArguments(source).len) |index| {
                    const left = self.solver.nominalArguments(source)[index];
                    const right = self.solver.nominalArguments(use)[index];
                    complete = try self.transferDataFacts(left, right, depth + 1) and complete;
                }
                return complete;
            },
            else => return false,
        }
    }
    fn closedDataShape(self: *ClosureRegion, root: types.Id, depth: usize) RegionError!bool {
        if (depth >= self.session.options.max_type_depth) return error.TypeLimit;
        const node = self.solver.node(try self.solver.resolve(root, 0));
        return switch (node.tag) {
            .unit, .boolean, .u32, .f32, .never => true,
            .usage => if (node.c == 0 and (node.b == @backingInt(types.UsageKind.unique) or node.b == @backingInt(types.UsageKind.shared))) self.closedDataShape(node.a, depth + 1) else false,
            .array, .list, .cursor => self.closedDataShape(node.a, depth + 1),
            .product => blk: {
                for (self.solver.list(.{ .start = node.a, .len = node.b })) |child| if (!try self.closedDataShape(child, depth + 1)) break :blk false;
                break :blk true;
            },
            .record => blk: {
                for (0..node.b) |index| if (!try self.closedDataShape(self.solver.recordField(node, index).ty, depth + 1)) break :blk false;
                break :blk true;
            },
            .nominal => blk: {
                for (self.solver.nominalArguments(node)) |child| if (!try self.closedDataShape(child, depth + 1)) break :blk false;
                break :blk true;
            },
            else => false,
        };
    }
    fn sourceWitnessHead(self: *ClosureRegion, input: types.Id) RegionError!types.Id {
        var head = input;
        var depth: usize = 0;
        while (depth < self.session.options.max_type_depth) : (depth += 1) {
            head = self.scratch.witness_inputs.get(head) orelse head;
            head = try self.solver.resolve(head, 0);
            const node = self.solver.node(head);
            if (node.tag != .function) return head;
            head = node.b;
        }
        return error.TypeLimit;
    }
    fn solveMode(self: *ClosureRegion, allow_remaining: bool) RegionError!void {
        // The caller may fail after enqueueing a dependency but before the
        // drain starts. Its query boundary also abandons pending tickets.
        errdefer if (!self.session.specializations.call_summaries.draining) self.session.specializations.call_summaries.abandonPending();
        while (!try self.solveStep(allow_remaining)) try self.session.specializations.call_summaries.drain(self.session);
    }
    fn schedulingTransition(self: *ClosureRegion) RegionError!void {
        if (self.component_work >= self.session.options.max_children) return error.TypeLimit;
        self.component_work += 1;
        _ = self.session.summaryCharge(1);
    }
    fn synchronizeWork(self: *ClosureRegion) RegionError!void {
        const a = self.scratch_allocator;
        const work = &self.scratch.worklists.?.constraints;
        while (work.entries.items.len < self.scratch.constraints.items.len) {
            const item = self.scratch.constraints.items[work.entries.items.len];
            try work.add(a, !item.deferred_member);
            if (item.solved) work.complete(work.entries.items.len - 1);
        }
        const aliases = &self.scratch.worklists.?.aliases;
        while (aliases.entries.items.len < self.scratch.data_aliases.items.len) {
            const item = self.scratch.data_aliases.items[aliases.entries.items.len];
            try aliases.add(a, true);
            if (item.solved) aliases.complete(aliases.entries.items.len - 1);
        }
        work.observe(&self.solver);
        aliases.observe(&self.solver);
        if (self.scratch.worklists.?.observed_revision != self.work_revision or self.work_revision == std.math.maxInt(u64)) {
            work.wakeAll();
            aliases.wakeAll();
            self.scratch.worklists.?.observed_revision = self.work_revision;
        }
    }
    fn solveDataAliases(self: *ClosureRegion) RegionError!bool {
        var changed = false;
        const work = &self.scratch.worklists.?.aliases;
        while (true) {
            const before = self.solver.cursor();
            var next: usize = 0;
            while (work.take(next)) |index| {
                const alias = self.scratch.data_aliases.items[index];
                const solved = try self.transferDataFacts(alias.principal, alias.instance, 0);
                self.scratch.data_aliases.items[index].solved = solved;
                try self.synchronizeWork();
                if (solved) work.complete(index) else try work.watch(self.scratch_allocator, &self.solver, index, &.{ alias.principal, alias.instance }, false, false);
                next = index + 1;
            }
            if (self.solver.cursor() == before) return changed;
            changed = true;
        }
    }
    fn needsIndexedWork(self: *const ClosureRegion) bool {
        return self.scratch.constraints.items.len > 8 or self.scratch.data_aliases.items.len > 8;
    }
    fn solveStep(self: *ClosureRegion, allow_remaining: bool) RegionError!bool {
        if (@import("builtin").is_test and self.reference_scan) return self.solveStepReference(allow_remaining);
        if (self.scratch.worklists == null) {
            if (!self.needsIndexedWork()) return self.solveStepReference(allow_remaining);
            const work = try self.scratch_allocator.create(Worklists);
            work.* = .{};
            self.scratch.worklists = work;
        }
        var fallback = false;
        const work = &self.scratch.worklists.?.constraints;
        try self.synchronizeWork();
        // A summary job can be resumed directly by the session's stack driver,
        // without going through solveMode after its children finish.
        work.wakeExternal();
        while (true) {
            try self.schedulingTransition();
            self.session.counters.solver_passes += 1;
            var progress = try self.solveDataAliases();
            const remaining = work.remaining;
            var next: usize = 0;
            while (work.take(next)) |index| {
                self.session.counters.solver_constraint_visits += 1;
                const state = try self.attemptConstraint(index, fallback);
                try self.synchronizeWork();
                if (state == .solved) {
                    work.complete(index);
                    progress = true;
                } else {
                    const item = self.scratch.constraints.items[index];
                    try work.watch(self.scratch_allocator, &self.solver, index, &.{ item.left, if (item.kind == .call_summary or item.kind == .invocation) 0 else item.right, item.result, item.signature }, item.kind == .call_summary, item.kind == .type_compare or item.kind == .effect_operation);
                    work.setWaiting(index, state == .waiting);
                }
                next = index + 1;
            }
            if (remaining == 0) {
                _ = try self.closeCertificates();
                return true;
            }
            if (progress or try self.closeCertificates()) {
                fallback = false;
                try self.synchronizeWork();
            } else if (work.waiting != 0) {
                return false;
            } else if (try self.expandOpenSummaries(allow_remaining)) {
                // Expansion marks the old summary constraints solved directly.
                for (self.scratch.constraints.items, 0..) |item, index| if (item.solved and index < work.entries.items.len) work.complete(index);
                try self.synchronizeWork();
                fallback = false;
            } else if (!fallback) {
                fallback = true;
                work.wakeAll();
            } else if (allow_remaining or work.required == 0) {
                return true;
            } else {
                for (self.scratch.constraints.items) |constraint| if (!constraint.solved and constraint.explicit)
                    return self.failConstraint(constraint, .ambiguous_qualified);
                return error.UnresolvedType;
            }
        }
    }
    fn attemptConstraint(self: *ClosureRegion, index: usize, fallback: bool) RegionError!SummaryProgress {
        try self.schedulingTransition();
        const constraint = self.scratch.constraints.items[index];
        const previous_origin = self.current_origin;
        self.current_origin = constraint.origin;
        if (self.current_origin == null and constraint.scope < self.scratch.sources.items.len)
            self.current_origin = self.scratch.sources.items[constraint.scope].origin;
        defer self.current_origin = previous_origin;
        if (constraint.kind == .callback_use) {
            // Check the interface relationship, not the callback's executable
            // identity. Its latent row is the exact row of this arrow and
            // remains shared with the source's enclosing row equations.
            if (constraint.callback_stage >= self.session.options.max_type_depth) return error.TypeLimit;
            var signature = constraint.signature;
            if (self.solver.node(try self.solver.resolve(signature, 0)).tag == .forall) signature = (try self.solver.instantiateRank(signature, false)).body;
            for (0..constraint.callback_stage) |_| {
                const stage = self.solver.node(try self.solver.resolve(signature, 0));
                if (stage.tag != .function) return error.TypeMismatch;
                signature = stage.b;
            }
            try self.unify(signature, constraint.left);
            const arrow = self.solver.node(try self.solver.resolve(constraint.left, 0));
            if (arrow.tag != .function) return error.TypeMismatch;
            try self.unify(arrow.a, constraint.right);
            try self.unify(arrow.b, constraint.result);
            if (self.building_principal) {
                self.scratch.constraints.items[index].callback_interface = true;
                return .open;
            }
            self.scratch.constraints.items[index].solved = true;
            return .solved;
        }
        // A destination-only principal job may infer inputs from a fixed
        // result-selected declaration, but cannot choose between associated
        // operand candidates on behalf of an unknown caller input or row.
        if (self.principal_result_job and constraint.kind == .binary and
            (try self.project(constraint.left) == 0 or try self.project(constraint.right) == 0)) return .open;
        if (constraint.kind == .scheme_use) return self.solveSchemeUse(index);
        if (constraint.kind == .call_summary) return self.solveSummary(index);
        if (constraint.kind == .record_merge) {
            if (try self.solver.mergeRecords(constraint.left, constraint.right)) |merged| {
                try self.unify(merged, constraint.result);
                self.scratch.constraints.items[index].solved = true;
                return .solved;
            }
            return .open;
        }
        if (constraint.kind == .collection) {
            const owner_type = self.solver.node(try self.solver.resolve(constraint.left, 0));
            if (owner_type.tag == .variable) return .open;
            if (owner_type.tag != .array and owner_type.tag != .list) return error.TypeMismatch;
            try self.unify(owner_type.a, constraint.result);
            self.scratch.constraints.items[index].solved = true;
            return .solved;
        }
        if (constraint.kind == .task_receive) {
            const signature = self.solver.node(try self.solver.resolve(constraint.signature, 0));
            if (signature.tag != .function) return error.TypeMismatch;
            const result = try @import("../check/task_types.zig").receiveResult(&self.solver, constraint.left, signature.c) orelse return .open;
            try self.unify(result, constraint.result);
            self.scratch.constraints.items[index].solved = true;
            return .solved;
        }
        if (constraint.kind == .type_eq) {
            if (self.session.has_implementations) {
                try self.normalizeProjection(constraint.left, 0);
                try self.normalizeProjection(constraint.result, 0);
            }
            if (try self.solver.equalSymbolic(constraint.left, constraint.result)) {
                self.scratch.constraints.items[index].solved = true;
                return .solved;
            }
            // Ordinary binders may be determined by equality. Residual
            // projections cannot determine their inputs or a concrete layout.
            if (try self.solver.containsProjection(constraint.left) or try self.solver.containsProjection(constraint.result)) return .open;
            try self.unify(constraint.left, constraint.result);
            if (try self.project(constraint.left) == 0 or try self.project(constraint.result) == 0) return .open;
            self.scratch.constraints.items[index].solved = true;
            return .solved;
        }
        if (constraint.kind == .contract) {
            const root = try self.project(constraint.left);
            if (root == 0) return .open;
            const context = self.associatedContext(constraint.scope);
            _ = self.session.implementation_proofs.resolve(self.session, context, constraint.identity, self.session.storage.evidence.children(root)) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.UnresolvedType => return .open,
                else => return self.session.implementationFailure(self.scratch.sources.items[constraint.scope].owner, constraint.node),
            };
            self.scratch.constraints.items[index].solved = true;
            return .solved;
        }
        if (constraint.kind == .implementation_method) {
            const root = try self.project(constraint.left);
            if (root == 0) return .open;
            const owner = self.scratch.sources.items[constraint.scope].owner;
            const context = self.associatedContext(constraint.scope);
            const proof = self.session.implementation_proofs.resolve(self.session, context, constraint.identity, self.session.storage.evidence.children(root)) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.UnresolvedType => return .open,
                else => return self.session.implementationFailure(owner, constraint.node),
            };
            const selected = self.session.implementation_proofs.proofs.items[proof];
            for (self.session.implementation_proofs.members.items[selected.members.start..][0..selected.members.len]) |member| {
                if (member.name != constraint.member) continue;
                const module = &self.session.units[owner];
                const template = module.member_templates[module.node(constraint.node).a];
                try self.collectCall(constraint.scope, member.target, module.binding(template.binding).ty, module.children(constraint.node));
                self.scratch.constraints.items[index].solved = true;
                return .solved;
            }
            return self.session.failNode(owner, constraint.node, .missing_implementation);
        }
        if (constraint.kind == .type_rep or constraint.kind == .effect_rep) {
            const represented = if (constraint.kind == .type_rep) constraint.left else constraint.signature;
            if (try self.project(represented) == 0) return .open;
            self.scratch.constraints.items[index].solved = true;
            return .solved;
        }
        if (constraint.kind == .invocation) {
            const selected = self.invocation(constraint) catch |err| return self.sourceSelectionFailure(constraint, err);
            if (!selected) return .open;
            self.scratch.constraints.items[index].solved = true;
            return .solved;
        }
        if (constraint.kind == .physical_field or constraint.kind == .receiver) {
            if (!try self.solveFieldConstraint(constraint)) return .open;
            self.scratch.constraints.items[index].solved = true;
            return .solved;
        }
        if (constraint.kind == .update) {
            if (!try self.updateConstraint(constraint)) return .open;
            self.scratch.constraints.items[index].solved = true;
            return .solved;
        }
        if (constraint.kind == .effect_handler) {
            var labels: std.ArrayList(types.Effects.Label) = .empty;
            defer labels.deinit(self.session.allocator);
            var closed = true;
            for ([_]types.Id{ constraint.left, constraint.right }) |token_type| {
                if (token_type == 0) continue;
                var token = try self.solver.resolve(token_type, 0);
                const scoped = self.solver.node(token);
                var instance: types.NominalIdentity = .{ .unit = 0, .decl = 0 };
                if (scoped.tag == .scoped) {
                    instance = .{ .unit = scoped.b, .decl = scoped.c };
                    token = try self.solver.resolve(scoped.a, 0);
                }
                if (!try self.solver.equalClosed(token, token)) {
                    closed = false;
                    break;
                }
                const nominal = self.solver.node(token);
                if (nominal.tag != .nominal) return error.TypeMismatch;
                const arguments = try self.session.allocator.dupe(types.Id, self.solver.nominalArguments(nominal));
                defer self.session.allocator.free(arguments);
                try labels.append(self.session.allocator, try self.solver.internScopedOperation(.{ .unit = nominal.a, .decl = nominal.b }, instance, arguments));
            }
            if (!closed) return .open;
            const remainder = self.solver.node(try self.solver.resolve(constraint.result, 0));
            const extended = self.solver.node(try self.solver.resolve(constraint.signature, 0));
            if (remainder.tag != .function or extended.tag != .function) return error.TypeMismatch;
            const residual = try self.solver.resolveEffects(remainder.c, 0);
            try labels.appendSlice(self.session.allocator, self.solver.rowLabels(residual));
            const row = self.solver.effects.rowAt(labels.items, self.solver.row(residual).tail, self.solver.row(residual).cursor) catch |err| return types.effectError(err);
            try self.solver.unifyEffects(extended.c, row);
            self.scratch.constraints.items[index].solved = true;
            return .solved;
        }
        if (constraint.kind == .type_compare) {
            const left = try self.sourceWitnessHead(constraint.left);
            const right = try self.sourceWitnessHead(constraint.right);
            if (self.solver.node(left).tag == .never or self.solver.node(right).tag == .never) {
                // An independent job has no caller witness. Decline it so the
                // caller's authoritative source traversal owns this error.
                const target = self.source_entry orelse return error.UnresolvedType;
                const point = self.session.units[target.unit].sourceNamePoint(target.binding);
                return self.session.fail(target.unit, .{ .start = point, .end = point }, .invalid_annotation);
            }
            if (try self.project(left) == 0 or try self.project(right) == 0) return .open;
            self.scratch.constraints.items[index].solved = true;
            return .solved;
        }
        if (constraint.kind == .type_head) {
            var head = constraint.left;
            var depth: usize = 0;
            while (true) {
                if (depth >= 1024) return error.TypeLimit;
                const node = self.solver.node(try self.solver.resolve(head, 0));
                if (node.tag != .function) break;
                head = node.b;
                depth += 1;
            }
            if (self.solver.node(try self.solver.resolve(head, 0)).tag == .variable) return .open;
            try self.unify(head, constraint.right);
            self.scratch.constraints.items[index].solved = true;
            return .solved;
        }
        if (constraint.kind == .effect_operation) {
            var argument_pack = try self.solver.resolve(constraint.right, 0);
            if (!try self.solver.equalClosed(argument_pack, argument_pack)) {
                if (!try self.recoverOperationArguments(constraint)) return .open;
                argument_pack = try self.solver.resolve(constraint.right, 0);
            }
            const signature = self.solver.node(try self.solver.resolve(constraint.left, 0));
            if (signature.tag == .variable) return .open;
            if (signature.tag != .function) return error.TypeMismatch;
            const arguments = self.solver.list(.{ .start = self.solver.node(argument_pack).a, .len = self.solver.node(argument_pack).b });
            const label = try self.solver.internScopedOperation(constraint.identity, constraint.instance, arguments);
            const residual = if (constraint.explicit) 0 else try self.solver.freshEffects();
            const row = self.solver.effects.row(&.{label}, self.solver.row(residual).tail) catch |err| return types.effectError(err);
            const selected = try self.solver.functionWithEffects(signature.a, signature.b, row);
            try self.unify(constraint.left, selected);
            if (constraint.signature != 0) try self.unify(constraint.signature, selected);
            self.scratch.constraints.items[index].solved = true;
            return .solved;
        }
        if (constraint.kind == .field) {
            if (!try self.solveFieldConstraint(constraint)) return .open;
            self.scratch.constraints.items[index].solved = true;
            return .solved;
        }
        if (constraint.kind == .resolver) {
            const actual = try self.project(constraint.left);
            if (actual == 0) return .open;
            const resolver = self.session.storage.evidence.node(actual);
            if (resolver.tag != .resolver) return error.TypeMismatch;
            const token = self.session.storage.evidence.node(resolver.a);
            if (token.tag != .type_constructor) return error.TypeMismatch;
            const source = self.scratch.sources.items[constraint.scope];
            const metadata = self.session.units[source.owner].resolverInfo(constraint.node);
            const target_ = try self.session.resolverTarget(source.owner, constraint.node, metadata, (@as(u64, token.a) << 32) | token.b);
            // Resolver methods have the same selected declaration, contextual
            // covariant rows and body owners as ordinary named calls.
            try self.collectCallAt(constraint.scope, .{ .unit = self.session.unitId(target_.unit), .binding = target_.binding }, metadata.method_type, self.session.units[source.owner].resolverArguments(constraint.node), constraint.node);
            try self.selectedTarget(target_);
            self.scratch.constraints.items[index].solved = true;
            return .solved;
        }
        if (constraint.kind == .resolver_shape) {
            const actual = try self.project(constraint.left);
            if (actual == 0) return .open;
            const provider = self.session.storage.evidence.node(actual);
            if (provider.tag != .resolver) return error.TypeMismatch;
            const token = self.session.storage.evidence.node(provider.a);
            if (token.tag != .type_constructor) return error.TypeMismatch;
            const result = self.solver.node(try self.solver.resolve(constraint.result, 0));
            if (result.tag == .variable) {
                const owner = self.scratch.sources.items[constraint.scope].owner;
                const module = &self.session.units[owner];
                const family = (@as(u64, token.a) << 32) | token.b;
                const nominal = for (module.nominals) |nominal| {
                    if (self.session.nominalIdentity(owner, nominal.identity.unit, nominal.identity.decl) == family) break nominal;
                } else return error.UnresolvedType;
                var arguments: std.ArrayList(types.Id) = .empty;
                defer arguments.deinit(self.session.allocator);
                for (0..nominal.parameters.len) |_| try arguments.append(self.session.allocator, try self.solver.fresh());
                try self.unify(constraint.result, try self.solver.nominal(.{ .unit = token.a, .decl = token.b }, arguments.items));
            } else if (result.tag != .nominal or result.a != token.a or result.b != token.b) return error.TypeMismatch;
            self.scratch.constraints.items[index].solved = true;
            return .solved;
        }
        const selected = if (constraint.kind == .result_dispatch) try self.resultConstraint(constraint) else try self.binaryConstraint(constraint, fallback);
        if (!selected) return .open;
        self.scratch.constraints.items[index].solved = true;
        return .solved;
    }
    fn solveStepReference(self: *ClosureRegion, allow_remaining: bool) RegionError!bool {
        var fallback = false;
        while (true) {
            try self.schedulingTransition();
            // A small region can grow while selecting or expanding a body.
            // Switch before another whole pass once its bounded fast path ends.
            if (!(@import("builtin").is_test and self.reference_scan) and self.needsIndexedWork()) return self.solveStep(allow_remaining);
            self.session.counters.solver_passes += 1;
            var remaining: usize = 0;
            var required: usize = 0;
            var waiting = false;
            var progress = try self.solveDataAliasesReference();
            var index: usize = 0;
            while (index < self.scratch.constraints.items.len) : (index += 1) {
                const constraint = self.scratch.constraints.items[index];
                if (constraint.solved) continue;
                remaining += 1;
                self.session.counters.solver_constraint_visits += 1;
                if (!constraint.deferred_member) required += 1;
                switch (try self.attemptConstraint(index, fallback)) {
                    .solved => progress = true,
                    .waiting => waiting = true,
                    .open => {},
                }
            }
            if (remaining == 0) {
                _ = try self.closeCertificates();
                return true;
            }
            if (progress or try self.closeCertificates()) {
                fallback = false;
            } else if (waiting) {
                return false;
            } else if (try self.expandOpenSummaries(allow_remaining)) {
                fallback = false;
            } else if (!fallback) {
                // Receivers and calls reveal operand owners before a stalled
                // pass may infer an unknown operand from the known receiver.
                fallback = true;
            } else if (allow_remaining or required == 0) {
                return true;
            } else {
                for (self.scratch.constraints.items) |constraint| if (!constraint.solved and constraint.explicit)
                    return self.failConstraint(constraint, .ambiguous_qualified);
                return error.UnresolvedType;
            }
        }
    }
    fn identityOf(self: *ClosureRegion, ty: types.Id) RegionError!?types.NominalIdentity {
        const node = self.solver.node(try self.solver.resolve(ty, 0));
        return switch (node.tag) {
            .nominal => .{ .unit = node.a, .decl = node.b },
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
    fn binaryCandidate(self: *ClosureRegion, constraint: Constraint, identity: types.NominalIdentity) RegionError!bool {
        const source = self.scratch.sources.items[constraint.scope];
        const reference = (try self.session.associatedTarget(self.session.unitId(source.owner), identity, constraint.member, constraint.op)) orelse return false;
        const target_ = try self.session.target(null, reference);
        const key: CandidateKey = .{ .caller = constraint.scope, .node = constraint.node, .target = target_ };
        const scope = self.scratch.candidate_instances.get(key) orelse scope: {
            const candidate = try self.callableScope(target_);
            try self.scratch.candidate_instances.put(self.scratch_allocator, key, candidate);
            break :scope candidate;
        };
        const signature = self.scratch.sources.items[scope].root;
        const first = self.solver.node(signature);
        if (first.tag != .function) return false;
        const second = self.solver.node(first.b);
        if (second.tag != .function) return false;
        const point = self.solver.mark();
        self.unify(first.a, constraint.left) catch |err| switch (err) {
            error.TypeMismatch, error.InfiniteType, error.EffectMismatch, error.InfiniteEffect => {
                self.solver.rollback(point);
                return false;
            },
            else => return err,
        };
        self.unify(second.a, constraint.right) catch |err| switch (err) {
            error.TypeMismatch, error.InfiniteType, error.EffectMismatch, error.InfiniteEffect => {
                self.solver.rollback(point);
                return false;
            },
            else => return err,
        };
        // Operand admission selects the method before its result is checked.
        // A result mismatch never licenses trying the other receiver.
        try self.unify(constraint.result, second.b);
        if (constraint.row_carrier) try self.addInvocation(constraint, signature, true) else _ = try self.admitSignature(constraint.signature, signature);
        try self.collectSelected(constraint.scope, scope, target_);
        return true;
    }
    fn binaryConstraint(self: *ClosureRegion, constraint: Constraint, fallback: bool) RegionError!bool {
        const left = try self.identityOf(constraint.left);
        const right = try self.identityOf(constraint.right);
        if (!fallback and (left == null or right == null)) return false;
        if (left) |identity| if (try self.binaryCandidate(constraint, identity)) return true;
        const a = self.solver.node(try self.solver.resolve(constraint.left, 0));
        const b = self.solver.node(try self.solver.resolve(constraint.right, 0));
        if (constraint.member == 0 and constraint.op != .none and a.tag == b.tag and (a.tag == .u32 or a.tag == .f32 or (a.tag == .boolean and (constraint.op == .equal or constraint.op == .not_equal)))) {
            const comparison = constraint.op == .equal or constraint.op == .not_equal or constraint.op == .less or constraint.op == .less_equal or constraint.op == .greater or constraint.op == .greater_equal;
            try self.unify(constraint.result, if (comparison) types.boolean else constraint.left);
            if (constraint.row_carrier) try self.pureInvocation(constraint);
            return true;
        }
        if (right) |identity| if (left == null or !std.meta.eql(left.?, identity)) {
            if (try self.binaryCandidate(constraint, identity)) return true;
        };
        var left_evidence = try self.project(constraint.left);
        var right_evidence = try self.project(constraint.right);
        if (fallback) {
            // A callable operand can have a known parameter and result while
            // its latent effect row remains open. That row cannot make the
            // callable acquire an associated operator, so retain the known
            // shape for a source diagnostic after both candidates failed.
            if (left_evidence == 0) left_evidence = try self.diagnosticCallable(constraint.left);
            if (right_evidence == 0) right_evidence = try self.diagnosticCallable(constraint.right);
        }
        if (left_evidence == 0 or right_evidence == 0) return false;
        const owner = self.scratch.sources.items[constraint.scope].owner;
        return self.failDispatchConstraint(constraint, if (constraint.member == 0) .ambiguous_operator else .missing_associated, try self.session.rejectedCandidates(owner, constraint.op, constraint.member, left_evidence, right_evidence, true));
    }
    fn diagnosticCallable(self: *ClosureRegion, ty: types.Id) RegionError!type_evidence.Id {
        const node = self.solver.node(try self.solver.resolve(ty, 0));
        if (node.tag != .function) return 0;
        const parameter = try self.project(node.a);
        const result = try self.project(node.b);
        if (parameter == 0 or result == 0) return 0;
        // Used only by the diagnostic display, never by dispatch selection.
        return self.session.storage.evidence.internWithEffects(.function, parameter, result, 0, &.{});
    }
    fn resultConstraint(self: *ClosureRegion, constraint: Constraint) RegionError!bool {
        const identity = try self.identityOf(constraint.result) orelse return false;
        const source = self.scratch.sources.items[constraint.scope];
        const reference = (try self.session.associatedTarget(self.session.unitId(source.owner), identity, constraint.member, .none)) orelse {
            var record: DispatchRecord = .{ .member = constraint.member };
            record.add(.destination, try self.project(constraint.result), .no_member);
            return self.failDispatchConstraint(constraint, .missing_associated, record);
        };
        const target_ = try self.session.target(null, reference);
        const scope = try self.callableScope(target_);
        const signature = self.scratch.sources.items[scope].root;
        const arrow = self.solver.node(signature);
        if (arrow.tag != .function) return error.TypeMismatch;
        try self.unify(constraint.left, arrow.a);
        try self.unify(constraint.result, arrow.b);
        if (constraint.row_carrier) try self.addInvocation(constraint, signature, false) else _ = try self.admitSignature(constraint.signature, signature);
        try self.collectSelected(constraint.scope, scope, target_);
        return true;
    }
    fn collectSelected(self: *ClosureRegion, caller: u32, scope: u32, target_: Target) RegionError!void {
        self.scratch.sources.items[scope].origin = self.current_origin;
        // This path runs only after a candidate has been admitted. Record even
        // when its body instance was already collected in this region.
        try self.selectedTarget(target_);
        const root = self.scratch.sources.items[scope].root;
        if (!self.building_principal) try self.bodyEdge(caller, scope);
        if (self.building_principal) {
            if (!try self.summaryShapeEligible(target_)) return error.UnresolvedType;
            try self.appendConstraint(.{ .kind = .call_summary, .scope = 0, .node = 0, .target = target_, .left = root, .result = 0, .source_selection = true, .deferred_member = self.defer_members });
            self.scratch.sources.items[scope].body = 0;
            self.scratch.sources.items[scope].binding = 0;
            return;
        }
        const actual = try self.project(root);
        if (actual != 0) {
            const key: CallKey = .{ .owner = target_.unit, .binding = target_.binding, .evidence = actual };
            if (self.scratch.call_instances.get(key)) |prior| {
                try self.unify(root, self.scratch.sources.items[prior].root);
                return;
            }
            try self.scratch.call_instances.put(self.scratch_allocator, key, scope);
        }
        // callableScope already imported this instance's written requirements.
        // Emission and complete demand checking still collect the actual body.
        if (!self.retain_selected and !self.complete_demand_bodies) {
            const module = &self.session.units[target_.unit];
            const binding = module.binding(target_.binding);
            if (binding.kind == .global and binding.scheme.obligations.len != 0 and try self.checkedSchemeReusable(target_)) {
                if (self.session.receipt_tape) |tape| try tape.sources.append(self.session.allocator, .{ .unit = self.session.unitId(target_.unit), .binding = target_.binding });
                if (self.session.constant_recorder) |recorder| try recorder.source(self.session.allocator, .{ .unit = self.session.unitId(target_.unit), .binding = target_.binding });
                return;
            }
        }
        try self.collect(scope, self.scratch.sources.items[scope].body);
    }
    const MemberMismatch = struct {
        region: *ClosureRegion,
        constraint: Constraint,
        fn report(context: *anyopaque, solver: *const types.Store, expected: types.Id, actual: types.Id) Allocator.Error!void {
            const observation: *MemberMismatch = @ptrCast(@alignCast(context));
            const self = observation.region;
            if (self.session.diagnostic != null) return;
            if (observation.constraint.kind != .field) return;
            const source = self.scratch.sources.items[observation.constraint.scope];
            const module = &self.session.units[source.owner];
            const point = module.projection(observation.constraint.projection).diagnostic_point;
            if (point == 0) return;
            const context_ = self.session.diagnostic_context;
            const message = try @import("../reuse/mismatch_display.zig").render(self.session.allocator, solver, .{
                .units = self.session.units,
                .identity = context_.identity,
                .entry = context_.entry,
                .prelude = context_.prelude,
                .source_mode = context_.source_mode,
            }, actual, expected) orelse return;
            // Publish only after all diagnostic storage is owned. The failed
            // solver transaction can now roll back and destroy its region.
            self.session.allocator.free(self.session.owned_diagnostic_message);
            self.session.owned_diagnostic_message = message;
            self.session.diagnostic = .{ .unit = self.session.unitId(source.owner), .span = .{ .start = point, .end = point }, .code = .type_mismatch, .detail = message };
        }
    };
    fn admitSignature(self: *ClosureRegion, expected: types.Id, actual: types.Id) RegionError!types.Id {
        return self.admitSignatureObserved(expected, actual, null);
    }
    fn admitSignatureObserved(self: *ClosureRegion, expected: types.Id, actual: types.Id, reporter: ?types.Store.MismatchReporter) RegionError!types.Id {
        if (expected == 0) return actual;
        // A selected implementation's covariant rows admit the caller's
        // ambient capability. Its source type and callback input rows retain
        // their exact requirements in the same imported scope.
        const admitted = try self.solver.openCovariant(try self.solver.resolve(actual, 0));
        if (self.solver.has_projections) {
            try self.unifyAssociatedRoot(expected, admitted, reporter);
        } else try self.solver.unifyWithReporter(expected, admitted, reporter);
        return admitted;
    }
    fn typeScope(self: *ClosureRegion, owner: usize) RegionError!u32 {
        if (self.scratch.sources.items.len >= self.session.options.max_values or self.scratch.sources.items.len >= std.math.maxInt(u32)) return error.TypeLimit;
        const scope: u32 = @intCast(self.scratch.sources.items.len);
        try self.scratch.sources.append(self.scratch_allocator, .{ .value = 0, .owner = owner, .origin = self.current_origin });
        return scope;
    }
    fn setSourceRoot(self: *ClosureRegion, scope: u32, root: types.Id) void {
        // Importing a quantified type may append a lexical type scope and
        // relocate sources. Evaluate the imported root before taking its slot.
        self.scratch.sources.items[scope].root = root;
    }
    fn callableScope(self: *ClosureRegion, target_: Target) RegionError!u32 {
        try self.session.observePrincipalSource(target_.unit, target_.binding);
        const module = &self.session.units[target_.unit];
        const body = module.body(target_.binding) orelse return error.UnresolvedType;
        const scope = try self.typeScope(target_.unit);
        self.scratch.sources.items[scope].body = body.root;
        self.scratch.sources.items[scope].closed_rows = body.closed_rows;
        self.setSourceRoot(scope, try self.importImplementation(scope, module.binding(target_.binding).ty));
        self.scratch.sources.items[scope].binding = target_.binding;
        if (!self.building_principal or scope == 0) try self.importScheme(scope, body.scheme, body.root);
        return scope;
    }
    fn arrayMember(self: *ClosureRegion, target_: Target, receiver: ValueId, expected: type_evidence.Id) RegionError!ValueId {
        const actual = try self.addValue(receiver, 0);
        const scope = try self.callableScope(target_);
        const root = self.scratch.sources.items[scope].root;
        const arrow = self.solver.node(root);
        if (arrow.tag != .function) return error.TypeMismatch;
        try self.unify(arrow.a, self.scratch.sources.items[actual].root);
        if (expected != 0) try self.unify(try self.solver.openCovariant(arrow.b), try self.importEvidence(expected, 0));
        try self.collect(scope, self.scratch.sources.items[scope].body);
        self.solve() catch |err| {
            if (err == error.UnresolvedType) {
                // This selected use needs the destination of @type.result.
                // Keep an unresolved element independent from that missing
                // destination, and report the first outstanding requirement.
                for (self.scratch.constraints.items) |constraint| {
                    if (constraint.solved or constraint.deferred_member) continue;
                    if (constraint.kind == .result_dispatch and try self.identityOf(constraint.result) == null)
                        return self.failConstraint(constraint, .ambiguous_associated);
                    break;
                }
            }
            return err;
        };
        var proof = try self.exportSolved(scope);
        defer proof.deinit(self.session.allocator);
        const function = try self.session.richValue(.{ .unit = self.session.unitId(target_.unit), .binding = target_.binding });
        var header = self.session.closureInfo(function);
        header.mappings = try self.session.captureMappings(target_.unit, self.scratch.sources.items[scope].body, proof.types);
        header.row_mappings = try self.session.captureRowMappings(target_.unit, self.scratch.sources.items[scope].body, proof.rows);
        const captures = try self.session.allocator.dupe(ValueId, self.session.valueChildren(function));
        defer self.session.allocator.free(captures);
        const selected = try self.session.makeClosure(target_.unit, self.scratch.sources.items[scope].body, header, captures);
        return self.session.typedView(target_.unit, self.scratch.sources.items[scope].body, selected, try self.project(root));
    }
    fn fieldType(self: *ClosureRegion, constraint: Constraint) RegionError!?types.Id {
        const source = self.scratch.sources.items[constraint.scope];
        const module = &self.session.units[source.owner];
        const explicit = constraint.kind == .physical_field or constraint.kind == .receiver;
        const projection = if (explicit) core.Projection{ .field = constraint.member, .nominal = .{ .unit = 0, .decl = 0 }, .source_type = 0, .result_type = 0, .variants = .{} } else module.projection(constraint.projection);
        const receiver = try self.solver.resolve(constraint.left, 0);
        const owner = self.solver.node(receiver);
        if (owner.tag == .variable) return null;
        var field: ?types.Id = null;
        if (projection.field == 0) {
            if (owner.tag == .never) return types.never;
            const variants = module.projectionVariants(constraint.projection);
            if (variants.len != 1 or (owner.tag != .product and owner.tag != .record)) return error.TypeMismatch;
            const index = variants[0].field;
            if (index >= owner.b) return error.TypeMismatch;
            return if (owner.tag == .record) self.solver.recordField(owner, index).ty else self.solver.list(.{ .start = owner.a, .len = owner.b })[index];
        }
        if (owner.tag == .record) {
            for (0..owner.b) |index| {
                const entry = self.solver.recordField(owner, index);
                if (entry.name == projection.field) {
                    field = entry.ty;
                    break;
                }
            }
        } else if (owner.tag == .nominal) {
            // Keep facts in the body's imported catalog. A caller can also
            // provide a nominal absent from that catalog; only then consult
            // its defining unit for fields and associated-member ambiguity.
            const family = (@as(u64, owner.a) << 32) | owner.b;
            const nominal_owner = visible: {
                for (module.constructors) |constructor| {
                    const nominal = module.nominal(constructor.nominal);
                    if (self.session.nominalIdentity(source.owner, nominal.identity.unit, nominal.identity.decl) == family)
                        break :visible source.owner;
                }
                break :visible self.session.findUnit(owner.a, null) orelse return error.UnresolvedType;
            };
            const nominal_module = &self.session.units[nominal_owner];
            var constructors: usize = 0;
            var hidden = false;
            for (nominal_module.constructors) |constructor| {
                const nominal = nominal_module.nominal(constructor.nominal);
                if (self.session.nominalIdentity(nominal_owner, nominal.identity.unit, nominal.identity.decl) != (@as(u64, owner.a) << 32) | owner.b) continue;
                if (nominal.is_opaque and nominal.identity.unit != self.session.unitId(source.owner)) {
                    hidden = true;
                    continue;
                }
                constructors += 1;
                if (constructor.payload == 0) {
                    field = null;
                    break;
                }
                const scope = try self.typeScope(nominal_owner);
                const arrow = self.solver.node(try self.importType(scope, constructor.scheme.root, 0));
                if (arrow.tag != .function) return error.TypeMismatch;
                try self.unify(arrow.b, receiver);
                const payload = self.solver.node(try self.solver.resolve(try self.importType(scope, constructor.payload, 0), 0));
                if (payload.tag != .record) {
                    field = null;
                    break;
                }
                var found: ?types.Id = null;
                for (0..payload.b) |index| {
                    const entry = self.solver.recordField(payload, index);
                    if (entry.name == projection.field) {
                        found = entry.ty;
                        break;
                    }
                }
                if (found == null) {
                    field = null;
                    break;
                }
                if (field) |prior| try self.unify(prior, found.?) else field = found;
            }
            if (constructors == 0 and !hidden) return error.UnresolvedType;
        }
        const identity: ?types.NominalIdentity = switch (owner.tag) {
            .nominal => .{ .unit = owner.a, .decl = owner.b },
            .unit => .{ .unit = 0, .decl = types.unit },
            .boolean => .{ .unit = 0, .decl = types.boolean },
            .u32 => .{ .unit = 0, .decl = types.u32_type },
            .f32 => .{ .unit = 0, .decl = types.f32_type },
            .array => .{ .unit = 0, .decl = std.math.maxInt(u32) },
            .list => .{ .unit = 0, .decl = std.math.maxInt(u32) - 1 },
            .cursor => .{ .unit = 0, .decl = std.math.maxInt(u32) - 2 },
            else => null,
        };
        var method_target: ?Target = null;
        if (!constraint.writable and (explicit or module.projectionVariants(constraint.projection).len == 0) and identity != null) {
            if (try self.session.associatedTarget(self.session.unitId(source.owner), identity.?, projection.field, .none)) |method| method_target = try self.session.target(null, method);
        }
        if (field) |result| {
            if (method_target != null) return self.failConstraint(constraint, .ambiguous_member);
            if (constraint.row_carrier) try self.pureInvocation(constraint);
            return result;
        }
        if (constraint.kind == .physical_field) return self.missingPhysicalField(constraint, owner);
        const target_ = method_target orelse return self.failConstraint(constraint, .missing_member);
        const scope = try self.callableScope(target_);
        const signature = self.scratch.sources.items[scope].root;
        const arrow = self.solver.node(signature);
        if (arrow.tag != .function) return error.TypeMismatch;
        try self.unify(arrow.a, receiver);
        var mismatch: MemberMismatch = .{ .region = self, .constraint = constraint };
        const reporter: types.Store.MismatchReporter = .{ .context = &mismatch, .report = MemberMismatch.report };
        const admitted = if (constraint.row_carrier) row: {
            try self.addInvocation(constraint, signature, false);
            break :row signature;
        } else try self.admitSignatureObserved(constraint.signature, signature, reporter);
        // Named member recursion reuses its already admitted body instance.
        // collectSelected still records the target on an instance hit.
        try self.collectSelected(constraint.scope, scope, target_);
        return self.solver.node(admitted).b;
    }
    fn missingPhysicalField(self: *ClosureRegion, constraint: Constraint, receiver: types.Node) Error {
        const first_failure = self.session.diagnostic == null;
        const result = self.failConstraint(constraint, .missing_field);
        if (!first_failure) return result;
        // Rendering follows the actual failed selection. It does not ask the
        // solver another question or retain a region/source pointer.
        if (!constraint.explicit or constraint.diagnostic_name.len == 0 or receiver.tag != .nominal or self.solver.nominalArguments(receiver).len != 0) return result;
        const owner = self.session.findUnit(receiver.a, null) orelse return result;
        const module = &self.session.units[owner];
        const nominal = for (module.nominals) |item| {
            if (item.identity.decl == receiver.b and (item.identity.unit == 0 or item.identity.unit == receiver.a)) break item;
        } else return result;
        const name = module.name(nominal.diagnostic_name);
        if (name.len == 0) return result;
        const context = self.session.diagnostic_context;
        var owned_origin: ?[]u8 = null;
        defer if (owned_origin) |text| self.session.allocator.free(text);
        const origin = if (context.identity) |identity| current: {
            if (receiver.a == context.prelude and context.prelude != 0) break :current "std/prelude";
            if (context.source_mode and receiver.a == context.entry) break :current "main";
            const entry_path = identity.owner(context.entry) orelse return result;
            const owner_path = identity.owner(receiver.a) orelse return result;
            const directory = std.Io.Dir.path.dirname(entry_path) orelse return result;
            owned_origin = std.Io.Dir.path.relativeAlloc(self.session.allocator, directory, null, directory, owner_path) catch return error.OutOfMemory;
            break :current owned_origin.?;
        } else module.name(nominal.diagnostic_origin);
        if (origin.len == 0) return result;
        const message = self.session.allocator.print("no field {s} on {s}::{s}", .{ constraint.diagnostic_name, origin, name }) catch return error.OutOfMemory;
        self.session.allocator.free(self.session.owned_diagnostic_message);
        self.session.owned_diagnostic_message = message;
        if (self.session.diagnostic) |*diagnostic| diagnostic.detail = message;
        return result;
    }
    fn pureInvocation(self: *ClosureRegion, constraint: Constraint) RegionError!void {
        const carrier = self.solver.node(try self.solver.resolve(constraint.signature, 0));
        if (carrier.tag != .function) return error.TypeMismatch;
        self.solver.unifyEffects(carrier.c, 0) catch |err| {
            if (err == error.EffectMismatch and constraint.explicit) return self.failConstraint(constraint, .effect_mismatch);
            return err;
        };
    }
    fn addInvocation(self: *ClosureRegion, constraint: Constraint, signature: types.Id, binary: bool) RegionError!void {
        var invocation_ = constraint;
        invocation_.kind = .invocation;
        invocation_.source_selection = self.deferredSourceSelection(constraint);
        invocation_.left = signature;
        invocation_.right = if (binary) 1 else 0;
        try self.appendConstraint(invocation_);
    }
    fn invocation(self: *ClosureRegion, constraint: Constraint) RegionError!bool {
        const carrier = self.solver.node(try self.solver.resolve(constraint.signature, 0));
        const first = self.solver.node(try self.solver.resolve(constraint.left, 0));
        if (carrier.tag != .function or first.tag != .function) return error.TypeMismatch;
        var selected = try self.solver.resolveEffects(first.c, 0);
        if (constraint.right != 0) {
            const second = self.solver.node(try self.solver.resolve(first.b, 0));
            if (second.tag != .function) return error.TypeMismatch;
            const inner = try self.solver.resolveEffects(second.c, 0);
            const outer_empty = self.solver.row(selected).tail == .closed and self.solver.rowLabels(selected).len == 0;
            const inner_empty = self.solver.row(inner).tail == .closed and self.solver.rowLabels(inner).len == 0;
            if (outer_empty) selected = inner else if (!inner_empty) {
                if (self.solver.row(selected).tail != .closed or self.solver.row(inner).tail != .closed) return false;
                var labels: std.ArrayList(types.Effects.Label) = .empty;
                defer labels.deinit(self.session.allocator);
                const outer = self.solver.rowLabels(selected);
                const nested = self.solver.rowLabels(inner);
                try labels.appendSlice(self.session.allocator, outer);
                for (nested, 0..) |label, index| {
                    var outer_count: usize = 0;
                    var inner_count: usize = 0;
                    for (outer) |other| if (label == other) {
                        outer_count += 1;
                    };
                    for (nested[0 .. index + 1]) |other| if (label == other) {
                        inner_count += 1;
                    };
                    if (inner_count > outer_count) try labels.append(self.session.allocator, label);
                }
                selected = self.solver.effects.row(labels.items, .closed) catch |err| return types.effectError(err);
            }
        }
        self.solver.unifyEffects(carrier.c, selected) catch |err| {
            if (err == error.EffectMismatch and constraint.explicit) return self.failConstraint(constraint, .effect_mismatch);
            return err;
        };
        return true;
    }
    fn updatedRecord(self: *ClosureRegion, original: types.Id, assigned: types.Id, member: u32, existing: ?types.Id) RegionError!?types.Id {
        const record = self.solver.node(try self.solver.resolve(original, 0));
        if (record.tag != .record) return null;
        const comparison = if (existing) |ty| self.solver.node(try self.solver.resolve(ty, 0)) else record;
        if (comparison.tag != .record or comparison.b != record.b) return error.TypeMismatch;
        var fields: std.ArrayList(types.Field) = .empty;
        defer fields.deinit(self.session.allocator);
        var found = false;
        for (0..record.b) |index| {
            const field = self.solver.recordField(record, index);
            const prior = self.solver.recordField(comparison, index);
            if (field.name != prior.name) return error.TypeMismatch;
            if (field.name == member) {
                found = true;
                if (existing != null) try self.unify(field.ty, assigned);
            } else if (existing != null) try self.unify(field.ty, prior.ty);
            try fields.append(self.session.allocator, .{ .name = field.name, .ty = if (field.name == member) assigned else field.ty });
        }
        return if (found) try self.solver.record(fields.items) else null;
    }
    fn updateConstraint(self: *ClosureRegion, constraint: Constraint) RegionError!bool {
        const owner = self.solver.node(try self.solver.resolve(constraint.left, 0));
        if (owner.tag == .variable) return false;
        if (owner.tag == .record) {
            const updated = try self.updatedRecord(constraint.left, constraint.right, constraint.member, null) orelse return self.failConstraint(constraint, .missing_field);
            try self.unify(constraint.result, updated);
        } else if (owner.tag == .nominal) {
            const source = self.scratch.sources.items[constraint.scope];
            const module = &self.session.units[source.owner];
            var constructors: usize = 0;
            for (module.constructors) |constructor| {
                const nominal = module.nominal(constructor.nominal);
                if (self.session.nominalIdentity(source.owner, nominal.identity.unit, nominal.identity.decl) != (@as(u64, owner.a) << 32) | owner.b) continue;
                constructors += 1;
                if (constructor.payload == 0) return self.failConstraint(constraint, .missing_field);
                const input_scope = try self.typeScope(source.owner);
                const output_scope = try self.typeScope(source.owner);
                const input = self.solver.node(try self.importType(input_scope, constructor.scheme.root, 0));
                const output = self.solver.node(try self.importType(output_scope, constructor.scheme.root, 0));
                if (input.tag != .function or output.tag != .function) return error.TypeMismatch;
                try self.unify(input.b, constraint.left);
                _ = try self.updatedRecord(try self.importType(output_scope, constructor.payload, 0), constraint.right, constraint.member, try self.importType(input_scope, constructor.payload, 0)) orelse return self.failConstraint(constraint, .missing_field);
                try self.unify(output.b, constraint.result);
            }
            if (constructors == 0) return error.UnresolvedType;
        } else return self.failConstraint(constraint, .missing_field);
        try self.pureInvocation(constraint);
        return true;
    }
    fn freeze(self: *ClosureRegion, scope: u32) RegionError!ValueId {
        if (self.scratch.frozen.get(scope)) |existing| return existing;
        const source = self.scratch.sources.items[scope];
        const actual = try self.project(source.root);
        if (actual == 0) return error.UnresolvedType;
        var edge_count: usize = 0;
        for (self.scratch.edges.items) |edge| if (edge.parent == scope) {
            edge_count += 1;
        };
        const replacements = try self.scratch_allocator.alloc(FrozenCapture, edge_count);
        defer self.scratch_allocator.free(replacements);
        self.session.counters.frozen_edge_scratch_bytes += replacements.len * @sizeOf(FrozenCapture);
        var index: usize = 0;
        for (self.scratch.edges.items) |edge| if (edge.parent == scope) {
            replacements[index] = .{ .slot = edge.slot, .value = try self.freeze(edge.child) };
            index += 1;
        };
        const value_kind = self.session.valueInfo(source.value).kind;
        if (value_kind != .closure and value_kind != .suspension) {
            const info = self.session.valueInfo(source.value);
            if (info.kind == .scalar) return self.session.typedView(source.owner, source.body, source.value, actual);
            const result = try self.session.copyFrozenAggregate(source.owner, source.body, source.value, replacements, null);
            self.session.storage.value_records.items[result] = self.session.storage.value_records.items[source.value];
            const typed = try self.session.typedView(source.owner, source.body, result, actual);
            try self.scratch.frozen.put(self.scratch_allocator, scope, typed);
            return typed;
        }
        var metadata = self.session.closureInfo(source.value);
        var solved = try self.exportSolved(scope);
        defer solved.deinit(self.session.allocator);
        metadata.mappings = try self.session.captureMappings(source.owner, source.body, solved.types);
        metadata.row_mappings = try self.session.captureRowMappings(source.owner, source.body, solved.rows);
        const header = try self.session.copyFrozenAggregate(source.owner, source.body, source.value, replacements, metadata);
        if (value_kind == .suspension) {
            self.session.storage.values.items[header].kind = .suspension;
            self.session.storage.values.items[header].nominal = self.session.valueInfo(source.value).nominal;
        }
        const result = try self.session.typedView(source.owner, source.body, header, actual);
        try self.scratch.frozen.put(self.scratch_allocator, scope, result);
        return result;
    }
    fn allConstraintsSolved(self: *const ClosureRegion) bool {
        for (self.scratch.constraints.items) |constraint| if (!constraint.solved) return false;
        return true;
    }
    fn closeRetainedFunctionRows(self: *ClosureRegion, root: types.Id, parameters: usize) RegionError!bool {
        if (parameters == 0) return false;
        if (parameters > self.session.options.max_type_depth) return error.TypeLimit;
        const arrow = self.solver.node(try self.solver.resolve(root, 0));
        if (arrow.tag != .function) return false;
        // A named curried body owns each of its parameter arrows. Close from
        // the last parameter outward, without closing a returned callback or
        // any function supplied by the caller.
        const changed = try self.closeRetainedFunctionRows(arrow.b, parameters - 1);
        if (try self.project(arrow.a) == 0 or try self.project(arrow.b) == 0) return changed;
        const row = try self.solver.resolveEffects(arrow.c, 0);
        if (self.solver.row(row).tail != .variable) return changed;
        const closed = self.solver.effects.row(self.solver.rowLabels(row), .closed) catch |err| return types.effectError(err);
        try self.solver.unifyEffects(row, closed);
        return true;
    }
    fn closeRetainedRows(self: *ClosureRegion) RegionError!void {
        if (!self.allConstraintsSolved()) return;
        var changed = true;
        while (changed) {
            changed = false;
            for (self.scratch.completed_demands.items) |demand| {
                const module = &self.session.units[self.scratch.sources.items[demand.scope].owner];
                const node = module.node(demand.node);
                if (node.tag != .suspend_ or module.closures[node.a].body != demand.body) return error.UnresolvedType;
                const arrow = self.solver.node(try self.solver.resolve(demand.root, 0));
                if (arrow.tag != .demand or try self.project(arrow.a) == 0) continue;
                const row = try self.solver.resolveEffects(arrow.c, 0);
                if (self.solver.row(row).tail != .variable) continue;
                const closed = self.solver.effects.row(self.solver.rowLabels(row), .closed) catch |err| return types.effectError(err);
                try self.solver.unifyEffects(row, closed);
                changed = true;
            }
            for (self.scratch.sources.items) |source| {
                if (source.value == 0) continue;
                const kind = self.session.valueInfo(source.value).kind;
                if (kind != .closure and kind != .suspension) continue;
                const arrow = self.solver.node(try self.solver.resolve(source.root, 0));
                if (kind == .closure) {
                    const metadata = self.session.closureInfo(source.value);
                    const parameters = if (metadata.origin == .named) count: {
                        const body = self.session.units[source.owner].body(metadata.identity) orelse return error.UnresolvedType;
                        if (metadata.applied > body.parameters.len) return error.UnresolvedType;
                        break :count body.parameters.len - metadata.applied;
                    } else if (metadata.origin == .anonymous) count: {
                        // `fn a => fn b => ...` is curried like a named body:
                        // a closure literal that is the whole body is this
                        // closure's own arrow, not a returned callback.
                        const module = &self.session.units[source.owner];
                        var count: usize = 1;
                        var body = module.closures[metadata.identity].body;
                        while (module.node(body).tag == .closure and count < self.session.options.max_type_depth) : (count += 1) body = module.closure(body).body;
                        break :count count;
                    } else 1;
                    changed = try self.closeRetainedFunctionRows(source.root, parameters) or changed;
                    continue;
                } else if (source.body == 0 or arrow.tag != .demand or try self.project(arrow.a) == 0) continue;
                const row = try self.solver.resolveEffects(arrow.c, 0);
                if (self.solver.row(row).tail != .variable) continue;
                // A complete concrete body proves only its own remaining ambient.
                const closed = self.solver.effects.row(self.solver.rowLabels(row), .closed) catch |err| return types.effectError(err);
                try self.solver.unifyEffects(row, closed);
                changed = true;
            }
        }
    }
    fn headerVariablesOnly(self: *ClosureRegion, ty: types.Id, header: []const types.Id) RegionError!bool {
        if (ty == 0) return true;
        const variables = try self.solver.freeVariables(ty);
        defer self.solver.allocator.free(variables);
        for (variables) |variable| {
            var found = false;
            for (header) |candidate| if (variable == candidate) {
                found = true;
                break;
            };
            if (!found) return false;
        }
        return true;
    }
    fn genericEntryInterface(self: *ClosureRegion, scope: u32) RegionError!bool {
        const arrow = self.solver.node(try self.solver.resolve(self.scratch.sources.items[scope].root, 0));
        if (arrow.tag != .function) return false;
        if (try self.project(arrow.a) != 0 and try self.project(arrow.b) != 0) return false;
        // Incomplete captured sources remain body proof failures, including
        // captures whose representation was erased by an unrelated use.
        for (self.scratch.sources.items, 0..) |source, index| {
            if (index == scope or source.value == 0) continue;
            if (try self.project(source.root) == 0) return false;
        }
        const root = try self.solver.product(&.{ arrow.a, arrow.b });
        const header = try self.solver.freeVariables(root);
        defer self.solver.allocator.free(header);
        for (self.scratch.constraints.items) |constraint| {
            if (constraint.solved) continue;
            if (constraint.scope != scope or constraint.explicit or constraint.deferred_member) return false;
            switch (constraint.kind) {
                .binary, .field, .result_dispatch, .physical_field, .receiver, .update, .type_compare, .collection, .record_merge => {},
                else => return false,
            }
            for ([_]types.Id{ constraint.left, constraint.right, constraint.result, constraint.signature }) |ty| {
                if (!try self.headerVariablesOnly(ty, header)) return false;
            }
        }
        return true;
    }
    fn inferEntry(self: *ClosureRegion, value_: ValueId) RegionError!?ValueId {
        self.include_callables = true;
        const scope = try self.addValue(value_, 0);
        try self.solveMode(true);
        try self.closeRetainedRows();
        if (try self.genericEntryInterface(scope)) return null;
        try self.solve();
        if (!self.allConstraintsSolved()) return error.UnresolvedType;
        try self.closeRetainedRows();
        const selected = try self.freeze(scope);
        try self.publishValidatedCalls();
        return selected;
    }
    fn infer(self: *ClosureRegion, value_: ValueId) RegionError!ValueId {
        self.include_callables = true;
        self.complete_demand_bodies = true;
        const scope = try self.addValue(value_, 0);
        try self.solve();
        if (!self.allConstraintsSolved()) return error.UnresolvedType;
        try self.closeRetainedRows();
        const selected = try self.freeze(scope);
        try self.publishValidatedCalls();
        return selected;
    }
    fn specialize(self: *ClosureRegion, value_: ValueId, expected: type_evidence.Id) RegionError!ValueId {
        self.include_callables = true;
        const scope = try self.addValue(value_, 0);
        const actual = try self.solver.resolve(self.scratch.sources.items[scope].root, 0);
        try self.unify(try self.solver.openCovariant(actual), try self.importEvidence(expected, 0));
        try self.solve();
        try self.closeRetainedRows();
        const selected = try self.session.typedView(self.scratch.sources.items[scope].owner, self.scratch.sources.items[scope].body, try self.freeze(scope), expected);
        try self.publishValidatedCalls();
        return selected;
    }
};

pub fn evaluate(allocator: Allocator, units: []const core.Module, target: core.BindingRef, options: Options) Allocator.Error!Result {
    var session = try Session.init(allocator, units);
    defer session.deinit();
    session.options = options;
    const value_ = session.value(target) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Declined => null,
        error.RequestUnwind => blk: {
            // A checked handler always consumes its own cancellation. Keep an
            // invalid numeric owner from publishing a successful empty result.
            if (session.diagnostic == null) session.diagnostic = .{ .unit = target.unit, .span = .{ .start = 0, .end = 0 }, .code = .unsupported };
            break :blk null;
        },
    };
    return .{ .value = value_, .diagnostic = session.diagnostic, .steps = session.steps };
}

fn lexicalSnapshotScenario(backing: Allocator, eligible: usize) !void {
    var tracked: @import("../runtime/memory.zig").TrackedAllocator = .{ .backing = backing };
    const allocator = tracked.allocator();
    var source = try types.Store.init(allocator);
    defer source.deinit();
    var originals: std.ArrayList(types.Id) = .empty;
    defer originals.deinit(allocator);
    for (0..eligible + 1) |_| try originals.append(allocator, try source.fresh());
    var source_rows: [3]types.Effects.Id = undefined;
    for (&source_rows) |*row| row.* = try source.freshEffects();
    const quantified = try source.saveList(&.{originals.items[eligible]});
    const quantified_rows = try source.saveList(&.{source.effects.node(source_rows[1]).tail.variable});
    const certified_rows = try source.saveList(&.{source.effects.node(source_rows[2]).tail.variable});
    const module: core.Module = .{
        .types = .{ .nodes = source.nodes.items, .extra = source.extra.items, .effects = .{ .rows = source.effects.rows.items, .labels = source.effects.labels.items, .variable_count = @intCast(source.effects.variables.items.len) }, .operations = source.operations.items },
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
    var session = try Session.init(allocator, &.{module});
    defer session.deinit();
    var region = try ClosureRegion.init(&session);
    defer region.deinit();
    const caller = try region.typeScope(0);
    const callee = try region.typeScope(0);
    const unrelated = try region.typeScope(0);
    region.scratch.sources.items[callee].closed_rows = certified_rows;
    for (originals.items) |original| {
        _ = try region.importType(unrelated, original, 0);
        _ = try region.importType(callee, original, 0);
    }
    // Force the first new caller import to grow this buffer. No borrowed slice
    // or record pointer may survive that import; newly appended records must
    // not join the initial lexical snapshot.
    const exact = try region.scratch_allocator.dupe(ClosureRegion.Variable, region.scratch.variables.items);
    region.scratch.variables.deinit(region.scratch_allocator);
    region.scratch.variables = .fromOwnedSlice(exact);
    const initial = region.scratch.variables.items.len;
    if (eligible == 0) {
        // Unrelated and quantified records impose no allocation requirement on
        // an empty lexical transfer, even with a nonempty inference table.
        const allocations = tracked.counts.allocations;
        try region.shareLexical(callee, caller, .{ .variables = quantified, .row_variables = quantified_rows });
        try std.testing.expectEqual(allocations, tracked.counts.allocations);
    }
    for (source_rows) |row| _ = try region.importRowVariable(callee, source.effects.node(row).tail.variable);
    try region.shareLexical(callee, caller, .{ .variables = quantified, .row_variables = quantified_rows });
    try std.testing.expectEqual(initial + eligible, region.scratch.variables.items.len);
    for (originals.items[0..eligible]) |original| {
        const actual = try region.importType(caller, original, 0);
        try region.solver.unify(actual, types.u32_type);
        try std.testing.expectEqual(types.u32_type, try region.solver.resolve(try region.importType(callee, original, 0), 0));
        const separate = try region.importType(unrelated, original, 0);
        try region.solver.unify(separate, types.boolean);
        try std.testing.expectEqual(types.boolean, try region.solver.resolve(separate, 0));
    }
    const generic = originals.items[eligible];
    const fresh_caller = try region.importType(caller, generic, 0);
    try region.solver.unify(fresh_caller, types.u32_type);
    const fresh_callee = try region.importType(callee, generic, 0);
    try region.solver.unify(fresh_callee, types.f32_type);
    try std.testing.expectEqual(types.u32_type, try region.solver.resolve(fresh_caller, 0));
    try std.testing.expectEqual(types.f32_type, try region.solver.resolve(fresh_callee, 0));
    for (source_rows, 0..) |row, index| {
        const variable = source.effects.node(row).tail.variable;
        const actual = try region.importRowVariable(caller, variable);
        const label = try region.solver.internOperation(.{ .unit = 2, .decl = @intCast(index + 1) }, &.{});
        try region.solver.unifyEffects(actual, try region.solver.effects.row(&.{label}, .closed));
        const retained = try region.importRowVariable(callee, variable);
        if (index == 0) {
            try std.testing.expectEqualSlices(types.Effects.Label, &.{label}, region.solver.rowLabels(try region.solver.resolveEffects(retained, 0)));
        } else {
            const other = try region.solver.internOperation(.{ .unit = 2, .decl = @intCast(index + 11) }, &.{});
            try region.solver.unifyEffects(retained, try region.solver.effects.row(&.{other}, .closed));
            try std.testing.expectEqualSlices(types.Effects.Label, &.{label}, region.solver.rowLabels(try region.solver.resolveEffects(actual, 0)));
        }
    }
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}
test "lexical sharing snapshots initial numeric records across growth and preserves quantified type and row independence" {
    for ([_]usize{ 0, 1, 80 }) |eligible| try lexicalSnapshotScenario(std.testing.allocator, eligible);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, lexicalSnapshotScenario, .{@as(usize, 1)});
}

fn indexedChainScenario(allocator: Allocator, indexed: bool, aliases: bool, count: usize) !u64 {
    var session = try Session.init(allocator, &.{});
    defer session.deinit();
    var region = try ClosureRegion.init(&session);
    defer region.deinit();
    region.reference_scan = !indexed;
    const variables = try allocator.alloc(types.Id, count + 1);
    defer allocator.free(variables);
    for (variables) |*variable| variable.* = try region.solver.fresh();
    var seed: types.Id = types.u32_type;
    if (!aliases) for (0..count) |_| {
        seed = try region.solver.array(seed);
    };
    try region.solver.unify(variables[0], seed);
    for (0..count) |offset| {
        const i = count - offset - 1;
        if (aliases) {
            try region.scratch.data_aliases.append(region.scratch_allocator, .{ .principal = variables[i], .instance = variables[i + 1] });
        } else {
            try region.scratch.constraints.append(region.scratch_allocator, .{ .kind = .collection, .scope = 0, .node = 0, .left = variables[i], .result = variables[i + 1] });
        }
    }
    try region.solve();
    try std.testing.expectEqual(types.u32_type, try region.solver.resolve(variables[count], 0));
    for (region.scratch.constraints.items) |constraint| try std.testing.expect(constraint.solved);
    for (region.scratch.data_aliases.items) |alias| try std.testing.expect(alias.solved);
    return session.counters.solver_constraint_visits;
}
fn indexedChainAllocationScenario(allocator: Allocator) !void {
    _ = try indexedChainScenario(allocator, true, false, 4);
    _ = try indexedChainScenario(allocator, true, false, 12);
    _ = try indexedChainScenario(allocator, true, true, 12);
}
test "indexed solver preserves reverse constraint and data alias chains with bounded visits and allocation recovery" {
    const a = std.testing.allocator;
    const ordinary = try indexedChainScenario(a, false, false, 64);
    const indexed = try indexedChainScenario(a, true, false, 64);
    try std.testing.expectEqual(@as(u64, 2080), ordinary);
    try std.testing.expectEqual(@as(u64, 127), indexed);
    _ = try indexedChainScenario(a, false, true, 64);
    _ = try indexedChainScenario(a, true, true, 64);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, indexedChainAllocationScenario, .{});
}

test "indexed solver switches a small completed region to watched work after new aliases arrive" {
    var session = try Session.init(std.testing.allocator, &.{});
    defer session.deinit();
    var region = try ClosureRegion.init(&session);
    defer region.deinit();
    var variables: [13]types.Id = undefined;
    for (&variables) |*variable| variable.* = try region.solver.fresh();
    try region.solver.unify(variables[0], types.u32_type);
    for (0..2) |index| try region.scratch.data_aliases.append(region.scratch_allocator, .{ .principal = variables[index], .instance = variables[index + 1] });
    try region.solve();
    try std.testing.expect(region.scratch.worklists == null);
    try std.testing.expectEqual(types.u32_type, try region.solver.resolve(variables[2], 0));
    for (0..10) |offset| {
        const index = 11 - offset;
        try region.scratch.data_aliases.append(region.scratch_allocator, .{ .principal = variables[index], .instance = variables[index + 1] });
    }
    try region.solve();
    try std.testing.expect(region.scratch.worklists != null);
    try std.testing.expectEqual(types.u32_type, try region.solver.resolve(variables[12], 0));
}

fn bodyRecipeLower(source: []const u8) !core.Module {
    const allocator = std.testing.allocator;
    var tokens = try @import("../parse/lexer.zig").lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: @import("../parse/symbols.zig").Pool = .{};
    defer names.deinit(allocator);
    var syntax = try @import("../parse/parser.zig").parse(allocator, source, tokens.tokens.items, &names);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checked_types.checkModuleWithOptions(allocator, &syntax, &names, &.{}, &.{}, 1, .{ .builtin_catalog = true });
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &syntax, &names, &checked);
    errdefer module.deinit(allocator);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}
fn semanticTestTarget(module: *const core.Module, name: []const u8) Target {
    for (module.bodies) |body| if (std.mem.eql(u8, module.name(body.export_name), name)) return .{ .unit = 0, .binding = body.binding };
    unreachable;
}
fn privateLexicalScenario(a: Allocator, module: *const core.Module, workers: u8) !void {
    var session = try Session.init(a, &.{module.*});
    defer session.deinit();
    session.semantic_io = std.testing.io;
    session.semantic_component_workers = workers;
    const selected: lexical_capture_inputs.Interfaces = .empty;
    const inputs = try session.storage.evidence.intern(.product, 0, 0, &.{types.u32_type});
    var requested: [2]CallSummaries.Key = undefined;
    for ([_][]const u8{ "first", "other" }, &requested) |name, *key| {
        const target_ = semanticTestTarget(module, name);
        const value = try session.richValue(.{ .unit = 1, .binding = target_.binding });
        const lexical = try session.specializations.lexical_inputs.intern(a, &session, value, &selected) orelse return error.ExpectedLexicalInput;
        key.* = .{ .target = .{ .unit = 0, .binding = 0 }, .inputs = inputs, .source_interface = false, .lexical = lexical, .options = session.options };
        _ = try session.specializations.call_summaries.request(&session, key.*);
    }
    const before_values = session.storage.values.items.len;
    const before_steps = session.steps;
    try session.specializations.call_summaries.drain(&session);
    try std.testing.expectEqual(@as(u64, 2), session.counters.semantic_component_jobs);
    try std.testing.expectEqual(@as(usize, 2), session.specializations.lexical_inputs.inputs.items.len);
    for (requested) |key| {
        const job = session.specializations.call_summaries.jobs.items[session.specializations.call_summaries.keys.get(key).?];
        try std.testing.expectEqual(CallSummaries.JobState.complete, job.state);
        const arrow = session.storage.evidence.node(job.result);
        try std.testing.expectEqual(type_evidence.Tag.function, arrow.tag);
        try std.testing.expectEqual(types.u32_type, arrow.a);
        try std.testing.expectEqual(types.u32_type, arrow.b);
    }
    try std.testing.expectEqual(before_values, session.storage.values.items.len);
    try std.testing.expectEqual(before_steps, session.steps);
}
test "private semantic lexical components remap capture interfaces without exporting live handles through allocation failures" {
    var module = try bodyRecipeLower(
        \\const make: U32 -> (U32 -> U32 ! {}) = fn captured => fn value => @u32.add captured value
        \\entry const first = make 1
        \\entry const other = make 2
    );
    defer module.deinit(std.testing.allocator);
    for ([_]u8{ 1, 4 }) |workers| try privateLexicalScenario(std.testing.allocator, &module, workers);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, privateLexicalScenario, .{ &module, @as(u8, 1) });
}
fn sharedSessionScenario(a: Allocator, units: []const core.Module) !void {
    var parent = try Session.init(a, units);
    defer parent.deinit();
    var shared = try Session.initShared(a, &parent);
    defer shared.deinit();
    try std.testing.expectEqual(parent.units.ptr, shared.units.ptr);
    try std.testing.expectEqual(parent.units.len, shared.units.len);
    try std.testing.expectEqual(parent.binding_offsets.ptr, shared.binding_offsets.ptr);
    try std.testing.expectEqual(parent.node_offsets.ptr, shared.node_offsets.ptr);
    try std.testing.expect(shared.borrowed_tables and !parent.borrowed_tables);
    try std.testing.expectEqual(parent.slots.len, shared.slots.len);
    try std.testing.expectEqual(parent.node_count, shared.node_count);
    // Trace marks are allocated by the first trace, not by either init.
    try std.testing.expectEqual(@as(usize, 0), shared.visited_nodes.len);
    for (shared.slots) |slot| try std.testing.expectEqual(Slot{}, slot);
    try std.testing.expectEqual(parent.has_implementations, shared.has_implementations);
    try std.testing.expectEqual(parent.has_generative_sources, shared.has_generative_sources);
    try std.testing.expectEqual(parent.field_locations.count(), shared.field_locations.count());
    try std.testing.expect(parent.field_locations.count() != 0);
    var entries = parent.field_locations.iterator();
    while (entries.next()) |entry| try std.testing.expectEqual(entry.value_ptr.*, shared.field_locations.get(entry.key_ptr.*).?);
}
test "a shared private session derives every unit fact Session.init derives through allocation failures" {
    var module = try bodyRecipeLower(
        \\type Pair is data = #Pair { left: U32, right: U32 }
        \\type Shape is data = #Square { side: U32 } | #Rect { width: U32, height: U32 }
        \\entry const area = fn (shape: Shape) => case shape of
        \\  #Square { side } => @u32.mul side side
        \\  #Rect { width, height } => @u32.mul width height
        \\entry const total = fn (pair: Pair) => @u32.add pair.left pair.right
    );
    defer module.deinit(std.testing.allocator);
    const units = [_]core.Module{module};
    try sharedSessionScenario(std.testing.allocator, &units);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, sharedSessionScenario, .{@as([]const core.Module, &units)});
}
fn privateRecursiveScenario(a: Allocator, module: *const core.Module, workers: u8) !void {
    var session = try Session.init(a, &.{module.*});
    defer session.deinit();
    session.semantic_io = std.testing.io;
    session.semantic_component_workers = workers;
    session.options.max_steps = 0;
    const inputs = try session.storage.evidence.intern(.product, 0, 0, &.{types.u32_type});
    var requested: [3]CallSummaries.Key = undefined;
    for ([_][]const u8{ "even", "odd", "independent" }, &requested) |name, *key| {
        key.* = .{ .target = semanticTestTarget(module, name), .inputs = inputs, .source_interface = false, .options = session.options };
        _ = try session.specializations.call_summaries.request(&session, key.*);
    }
    _ = try session.specializations.call_summaries.components.add(a, 0, 1, 3, &session.summary_transitions, session.summaryLimit());
    _ = try session.specializations.call_summaries.components.add(a, 1, 0, 3, &session.summary_transitions, session.summaryLimit());
    session.specializations.call_summaries.drain(&session) catch |err| {
        // The SCC package publishes all requested members, or none, even if
        // another successful package survives an allocation failure.
        const first = session.specializations.call_summaries.keys.get(requested[0]);
        const second = session.specializations.call_summaries.keys.get(requested[1]);
        try std.testing.expectEqual(first != null, second != null);
        if (first) |index| try std.testing.expectEqual(CallSummaries.JobState.complete, session.specializations.call_summaries.jobs.items[index].state);
        return err;
    };
    try std.testing.expectEqual(@as(u64, 2), session.counters.semantic_component_jobs);
    try std.testing.expect(session.component_members_published >= 2);
    for (requested) |key| {
        const job = session.specializations.call_summaries.jobs.items[session.specializations.call_summaries.keys.get(key).?];
        try std.testing.expectEqual(CallSummaries.JobState.complete, job.state);
        const arrow = session.storage.evidence.node(job.result);
        try std.testing.expectEqual(types.u32_type, arrow.a);
        try std.testing.expectEqual(types.u32_type, arrow.b);
    }
}
test "private semantic known recursive components publish every member atomically beside independent jobs" {
    var module = try bodyRecipeLower(
        \\entry const even: U32 -> U32 = fn value => if @u32.eq value 0 then 42 else odd (@u32.sub value 1)
        \\entry const odd: U32 -> U32 = fn value => if @u32.eq value 0 then 42 else even (@u32.sub value 1)
        \\entry const independent = fn value => @u32.add value 1
    );
    defer module.deinit(std.testing.allocator);
    for ([_]u8{ 1, 4 }) |workers| try privateRecursiveScenario(std.testing.allocator, &module, workers);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, privateRecursiveScenario, .{ &module, @as(u8, 1) });
}
test "private semantic declined jobs preserve successful siblings and late active dependencies return to serial inference" {
    const a = std.testing.allocator;
    var module = try bodyRecipeLower(
        \\entry const leaf = fn value => @u32.add value 1
        \\entry const caller: U32 -> U32 = fn value => leaf value
        \\entry const independent: U32 -> U32 = fn value => @u32.add value 2
    );
    defer module.deinit(a);
    for ([_]u8{ 1, 4 }) |workers| {
        var session = try Session.init(a, &.{module});
        defer session.deinit();
        session.semantic_io = std.testing.io;
        session.semantic_component_workers = workers;
        session.options.max_steps = 0;
        const inputs = try session.storage.evidence.intern(.product, 0, 0, &.{types.u32_type});
        var requested: [3]CallSummaries.Key = undefined;
        for ([_][]const u8{ "leaf", "caller", "independent" }, &requested) |name, *key| {
            key.* = .{ .target = semanticTestTarget(&module, name), .inputs = inputs, .source_interface = false, .options = session.options };
            _ = try session.specializations.call_summaries.request(&session, key.*);
        }
        session.specializations.call_summaries.jobs.items[0].state = .running;
        try session.specializations.call_summaries.active.put(a, requested[0].target, 0);
        try std.testing.expect(try session.specializations.call_summaries.parallelReady(&session));
        try std.testing.expectEqual(CallSummaries.JobState.queued, session.specializations.call_summaries.jobs.items[1].state);
        try std.testing.expectEqual(CallSummaries.JobState.complete, session.specializations.call_summaries.jobs.items[2].state);
        _ = session.specializations.call_summaries.active.remove(requested[0].target);
        session.specializations.call_summaries.jobs.items[0].state = .queued;
        try session.specializations.call_summaries.drain(&session);
        for (requested) |key| try std.testing.expectEqual(CallSummaries.JobState.complete, session.specializations.call_summaries.jobs.items[session.specializations.call_summaries.keys.get(key).?].state);
        var rejected = requested[0];
        rejected.inputs = try session.storage.evidence.intern(.product, 0, 0, &.{types.f32_type});
        _ = try session.specializations.call_summaries.request(&session, rejected);
        // A separate exact key prevents reusing the earlier completed sibling.
        var good = requested[2];
        good.source_interface = true;
        _ = try session.specializations.call_summaries.request(&session, good);
        try session.specializations.call_summaries.drain(&session);
        try std.testing.expectEqual(CallSummaries.JobState.declined, session.specializations.call_summaries.jobs.items[session.specializations.call_summaries.keys.get(rejected).?].state);
        try std.testing.expectEqual(CallSummaries.JobState.complete, session.specializations.call_summaries.jobs.items[session.specializations.call_summaries.keys.get(good).?].state);
        try std.testing.expectEqual(@as(usize, 0), session.steps);
        try std.testing.expect(session.diagnostic == null);
    }
}
fn privateDeclineScenario(a: Allocator, module: *const core.Module, workers: u8) !void {
    var session = try Session.init(a, &.{module.*});
    defer session.deinit();
    session.semantic_io = std.testing.io;
    session.semantic_component_workers = workers;
    session.options.max_steps = 0;
    // F32 inputs to U32 bodies: every private job declines, and each would
    // still be ready while the serial path takes the others one by one.
    const inputs = try session.storage.evidence.intern(.product, 0, 0, &.{types.f32_type});
    const names = [_][]const u8{ "first", "second", "third" };
    var requested: [names.len]CallSummaries.Key = undefined;
    for (names, &requested) |name, *key| {
        key.* = .{ .target = semanticTestTarget(module, name), .inputs = inputs, .source_interface = false, .options = session.options };
        _ = try session.specializations.call_summaries.request(&session, key.*);
    }
    try session.specializations.call_summaries.drain(&session);
    try std.testing.expectEqual(@as(u64, 1), session.counters.semantic_component_batches);
    try std.testing.expectEqual(@as(u64, names.len), session.counters.semantic_component_jobs);
    for (requested) |key| {
        const job = session.specializations.call_summaries.jobs.items[session.specializations.call_summaries.keys.get(key).?];
        try std.testing.expectEqual(CallSummaries.JobState.declined, job.state);
        try std.testing.expect(job.private_declined);
    }
    try std.testing.expect(session.diagnostic == null);
}
test "private semantic declines are offered once and the serial path still decides them" {
    var module = try bodyRecipeLower(
        \\entry const first: U32 -> U32 = fn value => @u32.add value 1
        \\entry const second: U32 -> U32 = fn value => @u32.add value 2
        \\entry const third: U32 -> U32 = fn value => @u32.add value 3
    );
    defer module.deinit(std.testing.allocator);
    for ([_]u8{ 1, 4 }) |workers| try privateDeclineScenario(std.testing.allocator, &module, workers);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, privateDeclineScenario, .{ &module, @as(u8, 1) });
}
test "private semantic recursive generic jobs keep distinct complete U32 and F32 inputs" {
    const a = std.testing.allocator;
    var module = try bodyRecipeLower(
        \\entry const recursive = fn value => fn (count: U32) => if @u32.eq count 0 then value else recursive value (@u32.sub count 1)
    );
    defer module.deinit(a);
    for ([_]u8{ 0, 1, 4 }) |workers| {
        var session = try Session.init(a, &.{module});
        defer session.deinit();
        session.semantic_io = std.testing.io;
        session.semantic_component_workers = workers;
        session.options.max_steps = 0;
        var requested: [2]CallSummaries.Key = undefined;
        for ([_]types.Id{ types.u32_type, types.f32_type }, &requested) |input, *key| {
            const inputs = try session.storage.evidence.intern(.product, 0, 0, &.{ input, types.u32_type });
            key.* = .{ .target = semanticTestTarget(&module, "recursive"), .inputs = inputs, .source_interface = false, .options = session.options };
            _ = try session.specializations.call_summaries.request(&session, key.*);
        }
        try session.specializations.call_summaries.drain(&session);
        for (requested, [_]types.Id{ types.u32_type, types.f32_type }) |key, input| {
            const job = session.specializations.call_summaries.jobs.items[session.specializations.call_summaries.keys.get(key).?];
            try std.testing.expectEqual(CallSummaries.JobState.complete, job.state);
            const arrow = session.storage.evidence.node(job.result);
            try std.testing.expectEqual(input, arrow.a);
            const inner = session.storage.evidence.node(arrow.b);
            try std.testing.expectEqual(types.u32_type, inner.a);
            try std.testing.expectEqual(input, inner.b);
        }
        if (workers != 0) try std.testing.expectEqual(@as(u64, 2), session.counters.semantic_component_jobs);
        try std.testing.expectEqual(@as(usize, 0), session.steps);
    }
}
fn expectRecipeSolverEqual(reference: *const ClosureRegion, replay: *const ClosureRegion) !void {
    try std.testing.expectEqualDeep(reference.scratch.sources.items, replay.scratch.sources.items);
    try std.testing.expectEqualDeep(reference.scratch.variables.items, replay.scratch.variables.items);
    try std.testing.expectEqualDeep(reference.scratch.constraints.items, replay.scratch.constraints.items);
    try std.testing.expectEqualDeep(reference.scratch.data_aliases.items, replay.scratch.data_aliases.items);
    try std.testing.expectEqualDeep(reference.solver.nodes.items, replay.solver.nodes.items);
    try std.testing.expectEqualDeep(reference.solver.extra.items, replay.solver.extra.items);
    try std.testing.expectEqualDeep(reference.solver.variables.items, replay.solver.variables.items);
    try std.testing.expectEqualDeep(reference.solver.versions.items, replay.solver.versions.items);
    try std.testing.expectEqualDeep(reference.solver.operations.items, replay.solver.operations.items);
    try std.testing.expectEqualDeep(reference.solver.effects.rows.items, replay.solver.effects.rows.items);
    try std.testing.expectEqualDeep(reference.solver.effects.labels.items, replay.solver.effects.labels.items);
    try std.testing.expectEqualDeep(reference.solver.effects.variables.items, replay.solver.effects.variables.items);
    try std.testing.expectEqualDeep(reference.solver.effects.versions.items, replay.solver.effects.versions.items);
    try std.testing.expectEqual(reference.solver.cursor(), replay.solver.cursor());
    try std.testing.expectEqual(reference.scratch.unresolved_calls.count(), replay.scratch.unresolved_calls.count());
    try std.testing.expectEqual(reference.scratch.call_instances.count(), replay.scratch.call_instances.count());
    try std.testing.expectEqualDeep(reference.session.storage.evidence.nodes.items, replay.session.storage.evidence.nodes.items);
    try std.testing.expectEqualDeep(reference.session.storage.evidence.extra.items, replay.session.storage.evidence.extra.items);
    try std.testing.expectEqualDeep(reference.session.storage.evidence.effects.rows.items, replay.session.storage.evidence.effects.rows.items);
    try std.testing.expectEqualDeep(reference.session.storage.evidence.effects.labels.items, replay.session.storage.evidence.effects.labels.items);
    try std.testing.expectEqualDeep(reference.session.storage.evidence.effects.operations.items, replay.session.storage.evidence.effects.operations.items);
}
fn bodyRecipeHistoryScenario(allocator: Allocator, module: *const core.Module, wanted: []const []const u8, valid: bool) !void {
    var reference_session = try Session.init(allocator, &.{module.*});
    defer reference_session.deinit();
    reference_session.options.reuse_body_recipes = false;
    reference_session.options.reuse_validated_calls = false;
    var replay_session = try Session.init(allocator, &.{module.*});
    defer replay_session.deinit();
    replay_session.options.reuse_validated_calls = false;
    var reference = try ClosureRegion.init(&reference_session);
    defer reference.deinit();
    var replay = try ClosureRegion.init(&replay_session);
    defer replay.deinit();
    for (0..2) |_| for (wanted) |name| {
        const body = for (module.bodies[1..]) |candidate| {
            if (std.mem.eql(u8, module.name(candidate.export_name), name)) break candidate;
        } else return error.TestUnexpectedResult;
        const binding = module.binding(body.binding);
        const input: [2]*ClosureRegion = .{ &reference, &replay };
        var failures: [2]?ClosureRegion.RegionError = .{ null, null };
        var results: [2]?SolvedEvidence = .{ null, null };
        defer for (&results) |*result| if (result.*) |*proof| proof.deinit(allocator);
        for (input, 0..) |region, index| {
            results[index] = region.bodyEvidenceFull(0, body.root, binding.ty, body.closed_rows, binding.scheme, .{ .semantic = 0 }, &.{}, &.{}) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => failed: {
                    failures[index] = err;
                    break :failed null;
                },
            };
        }
        try std.testing.expectEqual(failures[0], failures[1]);
        try std.testing.expectEqual(valid, failures[0] == null);
        try std.testing.expectEqualDeep(reference_session.diagnostic, replay_session.diagnostic);
        if (valid) {
            try std.testing.expectEqualDeep(results[0].?.types, results[1].?.types);
            try std.testing.expectEqualDeep(results[0].?.rows, results[1].?.rows);
        }
        try expectRecipeSolverEqual(&reference, &replay);
        try std.testing.expectEqual(@as(usize, 0), reference_session.steps);
        try std.testing.expectEqual(@as(usize, 0), replay_session.steps);
        if (!valid) break;
        // Cursor-bearing projections are repeated after both type and effect
        // writes, including rollback and catalog ID recycling. Recipes must
        // retain no solved type, row, or projected evidence from a prior use.
        const points = .{ reference.solver.mark(), replay.solver.mark() };
        var roots: [2]types.Id = undefined;
        const before = reference.solver.cursor();
        for (input, 0..) |region, index| {
            const variable = try region.solver.fresh();
            const row = try region.solver.freshEffects();
            roots[index] = try region.solver.functionWithEffects(variable, variable, row);
            try region.solver.unify(variable, types.u32_type);
            const label = try region.solver.internOperation(types.builtin_state_read, &.{types.u32_type});
            try region.solver.unifyEffects(row, try region.solver.effects.row(&.{label}, .closed));
        }
        for ([_]types.Cursor{ 0, before, reference.solver.cursor() }) |at| {
            const first = try reference.solver.resolve(roots[0], at);
            const second = try replay.solver.resolve(roots[1], at);
            try std.testing.expectEqual(first, second);
            try expectRecipeSolverEqual(&reference, &replay);
        }
        reference.solver.rollback(points[0]);
        replay.solver.rollback(points[1]);
        for (input) |region| {
            const variable = try region.solver.fresh();
            try region.solver.unify(variable, types.f32_type);
            _ = try region.solver.internOperation(types.builtin_state_write, &.{types.f32_type});
        }
        for (reference.scratch.sources.items, 0..) |source, index| if (source.root != 0) {
            try std.testing.expectEqual(try reference.project(source.root), try replay.project(replay.scratch.sources.items[index].root));
        };
        try expectRecipeSolverEqual(&reference, &replay);
    };
    try std.testing.expectEqual(@as(usize, 0), reference_session.specializations.body_recipes.builds);
    try std.testing.expect(replay_session.specializations.body_recipes.builds > 0);
    if (valid) {
        try std.testing.expect(replay_session.specializations.body_recipes.requests > replay_session.specializations.body_recipes.builds);
        try std.testing.expect(replay_session.specializations.body_recipes.replayed_visits > replay_session.specializations.body_recipes.planned_visits);
    }
}
fn bodyRecipeImmutableLaw(module: *const core.Module, wanted: []const []const u8, valid: bool) !void {
    const allocator = std.testing.allocator;
    const inputs = .{ module.nodes, module.extra, module.bindings, module.closures, module.projections, module.loops, module.loop_carries, module.resolver_ops, module.operation_values, module.handle_effects, module.request_loops, module.request_arms, module.types.nodes, module.types.extra, module.types.effects.rows, module.types.effects.labels, module.types.operations };
    var saved: @TypeOf(inputs) = undefined;
    var copied: usize = 0;
    defer inline for (0..inputs.len) |index| {
        if (index < copied) allocator.free(saved[index]);
    };
    inline for (inputs, 0..) |items, index| {
        saved[index] = try allocator.dupe(std.meta.Child(@TypeOf(items)), items);
        copied += 1;
    }
    try bodyRecipeHistoryScenario(allocator, module, wanted, valid);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, bodyRecipeHistoryScenario, .{ module, wanted, valid });
    inline for (inputs, 0..) |items, index| try std.testing.expectEqualDeep(saved[index], items);
}
test "body recipes preserve complete recursive SCC scope histories and independent scalar instances" {
    var module = try bodyRecipeLower(
        \\infixl 60 (+) = add
        \\const add = fn left => fn right => @type.call "add" left right
        \\const U32.add = fn left => fn right => @u32.add left right
        \\const F32.add = fn left => fn right => @f32.add left right
        \\const recursive = fn value => fn (count: U32) => do:
        \\  if @u32.eq count 0:
        \\    return value
        \\  return recursive (value + value) (@u32.sub count 1)
        \\entry const integer = fn () => recursive 21 1
        \\entry const floating = fn () => recursive 1.25 1
        \\const even = fn (value: U32) => do:
        \\  if @u32.eq value 0:
        \\    return 42
        \\  return odd (@u32.sub value 1)
        \\const odd = fn (value: U32) => do:
        \\  if @u32.eq value 0:
        \\    return 42
        \\  return even (@u32.sub value 1)
        \\entry const mutual = fn () => even 5
    );
    defer module.deinit(std.testing.allocator);
    const wanted: []const []const u8 = &.{ "integer", "floating", "mutual" };
    try bodyRecipeImmutableLaw(&module, wanted, true);
}
test "body recipes preserve capture identities ambient effects and mandatory negative member proofs" {
    for ([_][]const u8{
        @import("fixtures").source("captured-callable-fixtures/bound-cache-effects.blot"),
        @import("fixtures").source("captured-callable-fixtures/bound-cache-nominals.blot"),
        @import("fixtures").source("captured-callable-fixtures/bound-cache-missing.blot"),
    }, 0..) |source, index| {
        var module = try bodyRecipeLower(source);
        defer module.deinit(std.testing.allocator);
        const wanted: []const []const u8 = &.{"answer"};
        try bodyRecipeImmutableLaw(&module, wanted, index != 2);
    }
}

fn bodyRecipeQuotaScenario(allocator: Allocator, module: *const core.Module, root: core.Id, expected_prefix: ?ClosureRegion.RegionError) !void {
    var reference_session = try Session.init(allocator, &.{module.*});
    defer reference_session.deinit();
    reference_session.options.reuse_body_recipes = false;
    var replay_session = try Session.init(allocator, &.{module.*});
    defer replay_session.deinit();
    // Populate a complete recipe where admission permits it. A later smaller
    // quota must decline this cached recipe before any semantic action.
    _ = try replay_session.specializations.body_recipes.get(allocator, &.{module.*}, .{ .owner = 0, .body = root, .callables = true }, 1_000_000);
    for ([_]usize{ 0, 1, 2, 4, 16, 128, 4096 }) |limit| {
        // Scope creation precedes the deliberately tiny body quota. This
        // isolates the traversal budget from unrelated type-import limits.
        reference_session.options.max_values = 1_000_000;
        replay_session.options.max_values = 1_000_000;
        var reference = try ClosureRegion.init(&reference_session);
        defer reference.deinit();
        var replay = try ClosureRegion.init(&replay_session);
        defer replay.deinit();
        const first = try reference.typeScope(0);
        const second = try replay.typeScope(0);
        reference.include_callables = true;
        replay.include_callables = true;
        reference_session.options.max_values = limit;
        replay_session.options.max_values = limit;
        var errors: [2]?ClosureRegion.RegionError = .{ null, null };
        reference.collect(first, root) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => errors[0] = err,
        };
        replay.collect(second, root) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => errors[1] = err,
        };
        try std.testing.expectEqual(errors[0], errors[1]);
        if (limit < 2) try std.testing.expectEqual(error.TypeLimit, errors[0].?) else if (expected_prefix) |expected| try std.testing.expectEqual(expected, errors[0].?);
        try expectRecipeSolverEqual(&reference, &replay);
    }
    try std.testing.expect(replay_session.specializations.body_recipes.declined_walks > 0);
}
fn recipeRetryScenario(allocator: Allocator, module: *const core.Module, root: core.Id) !void {
    var cache: body_recipe.Cache = .{};
    defer cache.deinit(allocator);
    const key: body_recipe.Key = .{ .owner = 0, .body = root, .callables = true };
    try std.testing.expectEqual(null, try cache.get(allocator, &.{module.*}, key, 1));
    try std.testing.expectEqual(null, try cache.get(allocator, &.{module.*}, key, 1));
    try std.testing.expectEqual(@as(usize, 1), cache.reused_declines);
    const recipe = (try cache.get(allocator, &.{module.*}, key, 16)) orelse return error.TestUnexpectedResult;
    try std.testing.expect(recipe.visits.items.len > 1);
    try std.testing.expectEqual(null, try cache.get(allocator, &.{module.*}, key, 1));
    try std.testing.expectEqual(recipe, (try cache.get(allocator, &.{module.*}, key, 16)).?);
}
test "declined body recipes retry larger bounds and preserve later small-quota rejection through OOM" {
    var module = try bodyRecipeLower("entry const answer = @u32.add 1 2");
    defer module.deinit(std.testing.allocator);
    const root = for (module.bodies) |body| {
        if (body.exported) break body.root;
    } else return error.TestUnexpectedResult;
    try recipeRetryScenario(std.testing.allocator, &module, root);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, recipeRetryScenario, .{ &module, root });
}
test "body recipes decline bounded wide walks and preserve cached low-quota prefix error order" {
    const allocator = std.testing.allocator;
    var source = try types.Store.init(allocator);
    defer source.deinit();
    var nodes: [5005]core.Node = @splat(.{ .tag = .constant, .ty = types.u32_type });
    var spans: [5005]core.Span = @splat(.{ .start = 0, .end = 0 });
    var extra: [5002]core.Id = undefined;
    for (extra[0..5000], 0..) |*id, index| id.* = @intCast(index + 5);
    // Visit the semantic prefix before the distant wide product, using the
    // actual LIFO order of suite children.
    extra[5000] = 2;
    extra[5001] = 3;
    nodes[1] = .{ .tag = .suite, .a = 5000, .b = 2, .ty = types.unit };
    nodes[2] = .{ .tag = .product, .a = 0, .b = 5000, .ty = types.unit };
    nodes[3] = .{ .tag = .invalid };
    var resolvers: [1]core.ResolverInfo = .{.{ .operation = .forward, .resolver = 0 }};
    const module: core.Module = .{
        .unit = 1,
        .types = .{ .nodes = source.nodes.items, .extra = source.extra.items, .effects = .{ .rows = source.effects.rows.items, .labels = source.effects.labels.items, .variable_count = 0 }, .operations = source.operations.items },
        .nodes = &nodes,
        .spans = &spans,
        .extra = &extra,
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
        .resolver_ops = &resolvers,
        .body_lowerings = 0,
    };
    // A cached short invalid-prefix recipe must not choose a quota overflow in
    // its unreachable suffix. Uncached malformed resolver arity has the same
    // priority over that suffix and cannot grow the bounded plan's stack.
    try bodyRecipeQuotaScenario(allocator, &module, 1, error.UnresolvedType);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, bodyRecipeQuotaScenario, .{ &module, @as(core.Id, 1), @as(?ClosureRegion.RegionError, error.UnresolvedType) });
    for ([_]core.ResolverOperation{ .forward, .run }) |operation| {
        resolvers[0].operation = operation;
        nodes[3] = .{ .tag = .resolver_op, .a = 0, .ty = types.u32_type };
        try bodyRecipeQuotaScenario(allocator, &module, 1, error.TypeMismatch);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, bodyRecipeQuotaScenario, .{ &module, @as(core.Id, 1), @as(?ClosureRegion.RegionError, error.TypeMismatch) });
    }
    // No semantic prefix: the original traversal budget is the eventual
    // failure. The optimization must decline the entire wide walk first.
    nodes[3] = .{ .tag = .constant, .ty = types.u32_type };
    try bodyRecipeQuotaScenario(allocator, &module, 1, error.TypeLimit);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, bodyRecipeQuotaScenario, .{ &module, @as(core.Id, 1), @as(?ClosureRegion.RegionError, error.TypeLimit) });
}

fn specializationCapacityScenario(specialization: bool) !void {
    const allocator = std.testing.allocator;
    var module = try bodyRecipeLower(
        \\const plus = fn captured => fn value => @u32.add captured value
        \\const lift = fn callback => fn value => callback value
        \\entry const callback = lift (plus 42)
        \\entry const previous = lift (plus 43)
    );
    defer module.deinit(allocator);
    var failing = std.testing.FailingAllocator.init(allocator, .{});
    var session = try Session.init(failing.allocator(), &.{module});
    defer session.deinit();
    var raw: ValueId = 0;
    var prior: ValueId = 0;
    for (module.bodies) |body| if (body.exported) {
        const value_ = try session.richValue(.{ .unit = 1, .binding = body.binding });
        if (std.mem.eql(u8, module.name(body.export_name), "callback")) raw = value_ else prior = value_;
    };
    try std.testing.expect(raw != 0 and prior != 0);
    const previous = try session.inferClosure(prior);
    const prior_key = ViewKey{ .value = prior, .evidence = 0 };
    const expected = session.valueEvidence(previous);
    const key = ViewKey{ .value = raw, .evidence = if (specialization) expected else 0 };
    try std.testing.expect(!session.storage.specialized_closures.contains(key));
    // Match the real public path's early reservation and full outer region.
    try session.storage.specialized_closures.ensureUnusedCapacity(session.allocator, 1);
    var region = try ClosureRegion.init(&session);
    defer region.deinit();
    const selected = if (specialization) try region.specialize(raw, expected) else try region.infer(raw);
    const metadata = session.closureInfo(raw);
    const body = switch (metadata.origin) {
        .named => module.body(metadata.identity).?.root,
        .anonymous => module.closures[metadata.identity].body,
        else => unreachable,
    };
    const children = try allocator.dupe(ValueId, session.valueChildren(raw));
    defer allocator.free(children);
    var inner_count: usize = 0;
    // Complete real inner body proofs between reservation and outer insertion.
    // No fabricated map answer is used to consume the reserved capacity.
    while (session.storage.specialized_closures.available != 0) {
        const alias = try session.makeClosure(0, body, metadata, children);
        _ = try session.inferClosure(alias);
        inner_count += 1;
    }
    try std.testing.expect(inner_count != 0);
    try std.testing.expectEqual(@as(u32, 0), session.storage.specialized_closures.available);
    const before = session.storage.specialized_closures.count();
    try std.testing.expect(!session.storage.specialized_closures.contains(key));
    failing.fail_index = failing.alloc_index;
    failing.resize_fail_index = failing.resize_index;
    if (specialization) {
        try std.testing.expectError(error.OutOfMemory, session.cacheCompletedSpecialization(key, selected, &region));
        try std.testing.expect(!session.storage.specialized_closures.contains(.{ .value = selected, .evidence = expected }));
    } else try std.testing.expectError(error.OutOfMemory, session.cacheSpecialization(key, selected));
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(before, session.storage.specialized_closures.count());
    try std.testing.expect(!session.storage.specialized_closures.contains(key));
    try std.testing.expectEqual(previous, session.storage.specialized_closures.get(prior_key).?);
    failing.fail_index = std.math.maxInt(usize);
    failing.resize_fail_index = std.math.maxInt(usize);
    if (specialization) try session.cacheCompletedSpecialization(key, selected, &region) else try session.cacheSpecialization(key, selected);
    try std.testing.expectEqual(selected, session.storage.specialized_closures.get(key).?);
    try std.testing.expectEqual(previous, session.storage.specialized_closures.get(prior_key).?);
    if (specialization) try std.testing.expect(session.storage.specialized_closures.count() >= before + 2) else try std.testing.expectEqual(before + 1, session.storage.specialized_closures.count());
    if (specialization) try std.testing.expectEqual(selected, try session.specializeClosure(selected, expected));
    // The public retry now reads the completed selected header without growth.
    const retried = if (specialization) try session.specializeClosure(raw, expected) else try session.inferClosure(raw);
    try std.testing.expectEqual(selected, retried);
}

test "specialization map inference publication regrows after real nested proofs and OOM retry" {
    try specializationCapacityScenario(false);
}

test "specialization map expected-evidence publication regrows after real nested proofs and OOM retry" {
    try specializationCapacityScenario(true);
}

fn concreteSelfRuntimeInterfaceScenario(allocator: Allocator, module: *const core.Module) !void {
    var session = try Session.init(allocator, &.{module.*});
    defer session.deinit();
    // Runtime body collection must converge without executing the recursive
    // method. A small source-scope budget catches inference recursion early.
    session.options.max_values = 128;
    const selected = for (module.bodies) |body| {
        if (body.exported and std.mem.eql(u8, module.name(body.export_name), "selected")) break body.binding;
    } else return error.TestUnexpectedResult;
    const result = try session.sourceInterface(.{ .unit = 1, .binding = selected });
    try std.testing.expectEqual(@as(usize, 0), result.pending);
    try std.testing.expect(result.evidence != 0);
    const arrow = session.storage.evidence.node(result.evidence);
    try std.testing.expectEqual(type_evidence.Tag.function, arrow.tag);
    try std.testing.expectEqual(type_evidence.Tag.unit, session.storage.evidence.node(arrow.a).tag);
    try std.testing.expectEqual(type_evidence.Tag.u32, session.storage.evidence.node(arrow.b).tag);
    try std.testing.expect(session.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}

fn constantReceiptTapeScenario(allocator: Allocator, module: *const core.Module) !void {
    var ordinary = try Session.init(allocator, &.{module.*});
    defer ordinary.deinit();
    var recorded = try Session.init(allocator, &.{module.*});
    defer recorded.deinit();
    recorded.retain_constant_receipts = true;
    recorded.minimum_constant_steps = 0;
    const entry = for (module.bodies) |body| {
        if (body.exported) break body.binding;
    } else return error.TestUnexpectedResult;
    const reference: core.BindingRef = .{ .unit = 1, .binding = entry };
    try std.testing.expectEqual(try ordinary.value(reference), try recorded.value(reference));
    try std.testing.expectEqual(ordinary.steps, recorded.steps);
    try std.testing.expect(recorded.constant_recorder == null);
    var steps: usize = 0;
    var reads: usize = 0;
    for (recorded.retained.constant_records.items) |record| for (record.events) |event| switch (event) {
        .growth, .view, .query => return error.TestUnexpectedResult,
        .work => |work| steps += work.steps,
        .read => |read| {
            reads += 1;
            try std.testing.expectEqual(read.value, (try recorded.cachedBindingValue(read.target)).?);
        },
    };
    try std.testing.expectEqual(recorded.steps, steps);
    try std.testing.expect(reads >= 3);
    var limited = try Session.init(allocator, &.{module.*});
    defer limited.deinit();
    limited.retain_constant_receipts = true;
    limited.options.max_steps = ordinary.steps - 1;
    if (limited.value(reference)) |_| return error.TestUnexpectedResult else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.Declined, err);
    }
    try std.testing.expectEqual(Code.constant_fuel, limited.diagnostic.?.code);
    try std.testing.expect(try limited.cachedBindingValue(reference) == null);
}

test "constant receipt tape separates nested reads and preserves ordinary fuel" {
    const allocator = std.testing.allocator;
    var module = try bodyRecipeLower(
        \\const leaf = @u32.add 1 2
        \\const outer = @u32.add leaf leaf
        \\entry const answer = @u32.add outer leaf
    );
    defer module.deinit(allocator);
    try constantReceiptTapeScenario(allocator, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, constantReceiptTapeScenario, .{&module});
}

test "concrete self runtime method interface terminates without executing recursive typed or plain bodies" {
    const allocator = std.testing.allocator;
    for ([_][]const u8{
        \\type Box is data = #Box U32
        \\const Box.read: Box -> U32 where {} = fn (value: Box) => value.read
        \\entry const selected: Unit -> U32 = fn () => (#Box 1).read
        \\entry const answer = 42
        ,
        \\type Box is data = #Box U32
        \\const Box.read: Box -> U32 where {} = fn value => value.read
        \\entry const selected: Unit -> U32 = fn () => (#Box 1).read
        \\entry const answer = 42
        ,
    }) |source| {
        var module = try bodyRecipeLower(source);
        defer module.deinit(allocator);
        try concreteSelfRuntimeInterfaceScenario(allocator, &module);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, concreteSelfRuntimeInterfaceScenario, .{&module});
    }
}

test "concrete self runtime method remains fuel-limited when a constant forces recursion" {
    const allocator = std.testing.allocator;
    for ([_][]const u8{
        \\type Box is data = #Box U32
        \\const Box.read: Box -> U32 where {} = fn (value: Box) => value.read
        \\entry const answer = (#Box 1).read
        ,
        \\type Box is data = #Box U32
        \\const Box.read: Box -> U32 where {} = fn value => value.read
        \\entry const answer = (#Box 1).read
        ,
    }) |source| {
        var module = try bodyRecipeLower(source);
        defer module.deinit(allocator);
        var session = try Session.init(allocator, &.{module});
        defer session.deinit();
        session.options.max_values = 2048;
        session.options.max_steps = 64;
        session.options.max_depth = 32;
        const answer = for (module.bodies) |body| {
            if (body.exported) break body.binding;
        } else return error.TestUnexpectedResult;
        try std.testing.expectError(error.Declined, session.richValue(.{ .unit = 1, .binding = answer }));
        try std.testing.expectEqual(Code.constant_fuel, session.diagnostic.?.code);
        try std.testing.expect(session.steps != 0 and session.steps <= session.options.max_steps);
    }
}

fn solverCapacityExportsScenario(backing: Allocator) !void {
    var tracked: @import("../runtime/memory.zig").TrackedAllocator = .{ .backing = backing };
    const allocator = tracked.allocator();
    var session = try Session.init(allocator, &.{});
    var session_alive = true;
    defer if (session_alive) session.deinit();
    var region = try ClosureRegion.init(&session);
    var region_alive = true;
    defer if (region_alive) region.deinit();
    const root = try region.solver.array(types.u32_type);
    try region.scratch.variables.append(region.scratch_allocator, .{ .source = .{ .scope = 0, .ty = 19 }, .region = root });
    var solved = try region.exportSolved(0);
    var solved_alive = true;
    defer if (solved_alive) solved.deinit(allocator);
    try std.testing.expectEqual(@as(types.Id, 19), solved.types[0].variable);
    const retained_evidence = solved.types[0].evidence;
    region.deinit();
    region_alive = false;
    var next = try ClosureRegion.init(&session);
    var next_alive = true;
    defer if (next_alive) next.deinit();
    try std.testing.expectEqual(@as(u32, 0), next.scratch.imported.count());
    try std.testing.expectEqual(@as(usize, 0), next.scratch.variables.items.len);
    try std.testing.expectEqual(@as(usize, 1), session.regions.region_arena_pool.stats.reused);
    const replacement = try next.solver.array(types.f32_type);
    try std.testing.expectEqual(root, replacement);
    const newer_evidence = try next.project(replacement);
    try std.testing.expectEqual(types.u32_type, session.storage.evidence.nodes.items[retained_evidence].a);
    try std.testing.expectEqual(types.f32_type, session.storage.evidence.nodes.items[newer_evidence].a);
    next.deinit();
    next_alive = false;
    session.deinit();
    session_alive = false;
    // SolvedEvidence owns its exported arrays independently of Session/pool.
    try std.testing.expectEqual(retained_evidence, solved.types[0].evidence);
    solved.deinit(allocator);
    solved_alive = false;
    try std.testing.expectEqual(@as(usize, 0), tracked.counts.live_bytes);
}

fn lexicalRowIndexScenario(a: Allocator, module: *const core.Module) !void {
    var session = try Session.init(a, &.{module.*});
    defer session.deinit();
    var region = try ClosureRegion.init(&session);
    defer region.deinit();
    try std.testing.expect(module.types.effects.variable_count != 0);
    for (0..3) |_| try region.scratch.sources.append(region.scratch_allocator, .{ .owner = 0, .value = 0 });
    const callee = try region.importRowVariable(1, 0);
    const unrelated = try region.importRowVariable(2, 0);
    try region.shareLexical(1, 0, .{});
    const caller = try region.importRowVariable(0, 0);
    const current_callee = region.solver.row(try region.solver.resolveEffects(callee, 0));
    const current_caller = region.solver.row(try region.solver.resolveEffects(caller, 0));
    const current_unrelated = region.solver.row(try region.solver.resolveEffects(unrelated, 0));
    try std.testing.expect(std.meta.eql(current_callee.tail, current_caller.tail));
    try std.testing.expect(!std.meta.eql(current_callee.tail, current_unrelated.tail));
    try std.testing.expectEqual(@as(u64, 1), session.counters.lexical_row_scope_candidates);
    try std.testing.expectEqual(@as(u64, 2), session.counters.lexical_row_region_candidates);
}

test "lexical row scope index preserves unrelated binders and imports appended during sharing through OOM" {
    var module = try bodyRecipeLower("const apply = fn f => fn value => f value\nentry const answer = 7");
    defer module.deinit(std.testing.allocator);
    try lexicalRowIndexScenario(std.testing.allocator, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, lexicalRowIndexScenario, .{&module});
}

fn principalSourceOwnerScenario(a: Allocator, module: *const core.Module) !void {
    var session = try Session.init(a, &.{module.*});
    defer session.deinit();
    var reads: principal_inputs.Recorder = .{ .eligible = true, .max_reads = 256, .root = .{ .unit = 2, .binding = 1 } };
    defer reads.deinit(a);
    session.principal_reads = &reads;
    defer session.principal_reads = null;
    var found = false;
    for (module.bindings, 0..) |binding, id| {
        if (binding.kind != .local or binding.initializer == 0) continue;
        const owner = (try session.regions.principal_source_owners.binding(a, session.units, 0, @intCast(id), session.options.max_values)) orelse return error.TestUnexpectedResult;
        try std.testing.expect(module.binding(owner).kind == .global);
        try session.observePrincipalSource(0, @intCast(id));
        try std.testing.expect(reads.sources_seen.contains(.{ .unit = 1, .binding = owner }));
        found = true;
    }
    try std.testing.expect(found);
    try std.testing.expectEqual(@as(usize, 0), reads.source_units.items.len);
    var has_suspension = false;
    for (module.nodes) |node| has_suspension = has_suspension or node.tag == .suspend_;
    try std.testing.expect(has_suspension);
    for (module.closures) |closure| {
        if (closure.body == 0) continue;
        const owner = (try session.regions.principal_source_owners.node(a, session.units, 0, closure.body, session.options.max_values)) orelse return error.TestUnexpectedResult;
        try std.testing.expect(module.binding(owner).kind == .global);
    }
    var bounded: @import("source_owners.zig").Cache = .{};
    defer bounded.deinit(a);
    try std.testing.expect((try bounded.node(a, session.units, 0, 1, 1)) == null);
    // Shared physical nodes cannot grant one declaration ownership when two
    // declarations reach them. Such inputs keep the whole-module fallback.
    var shared = module.*;
    shared.bodies = try a.dupe(core.Body, module.bodies);
    defer a.free(shared.bodies);
    var reached: [2]usize = undefined;
    var count: usize = 0;
    for (shared.bodies, 0..) |body, index| {
        if (body.root == 0 or body.binding == 0) continue;
        reached[count] = index;
        count += 1;
        if (count == reached.len) break;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
    const shared_root = shared.bodies[reached[0]].root;
    shared.bodies[reached[1]].root = shared_root;
    var ambiguous: @import("source_owners.zig").Cache = .{};
    defer ambiguous.deinit(a);
    try std.testing.expect((try ambiguous.node(a, &.{shared}, 0, shared_root, session.options.max_values)) == null);
}

fn unitIndexScenario(a: Allocator, module: *const core.Module) !void {
    for ([_][2]u32{ .{ 1, 2 }, .{ 0, 2 }, .{ 7, 3 }, .{ 7, 7 }, .{ 0, 0 } }) |ids| {
        var units = [_]core.Module{ module.*, module.* };
        for (&units, ids) |*item, id| item.unit = id;
        var session = try Session.init(a, &units);
        defer session.deinit();
        for ([_]u32{ 0, 1, 2, 3, 7, 9999 }) |unit| {
            const expected: ?usize = for (units, 0..) |item, index| {
                if (item.unit == unit or (item.unit == 0 and index + 1 == unit)) break index;
            } else null;
            try std.testing.expectEqual(expected, session.unitIndex(unit));
        }
    }
}
test "Session unit lookup preserves dense implicit sparse and duplicate first owner identities through OOM" {
    var module = try bodyRecipeLower("entry const answer = 7");
    defer module.deinit(std.testing.allocator);
    try unitIndexScenario(std.testing.allocator, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, unitIndexScenario, .{&module});
}

test "principal source containment owns nested closures and local reads with bounded allocation failure cleanup" {
    var module = try bodyRecipeLower(
        \\const first = fn (x: U32) => do:
        \\  let captured = fn (y: U32) => @u32.add x y
        \\  break captured
        \\const second = fn (x: U32) => @u32.sub x 1
        \\const force = fn ~(value: U32) => @force value
        \\entry const delayed = force (@u32.add 1 2)
        \\entry const answer = 7
    );
    defer module.deinit(std.testing.allocator);
    try principalSourceOwnerScenario(std.testing.allocator, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, principalSourceOwnerScenario, .{&module});
}
test "region arena exports own projected evidence across region ID recycling teardown and OOM" {
    try solverCapacityExportsScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, solverCapacityExportsScenario, .{});
}
test "region arena regions keep fresh maps and active solvers across nested return" {
    const allocator = std.testing.allocator;
    var session = try Session.init(allocator, &.{});
    defer session.deinit();
    var outer = try ClosureRegion.init(&session);
    var outer_alive = true;
    defer if (outer_alive) outer.deinit();
    const root = try outer.solver.fresh();
    try outer.solver.appendVersion(root, types.u32_type);
    try outer.scratch.imported.put(outer.scratch_allocator, .{ .scope = 7, .ty = 13 }, root);
    var inner = try ClosureRegion.init(&session);
    var inner_alive = true;
    defer if (inner_alive) inner.deinit();
    try std.testing.expect(inner.solver.nodes.items.ptr != outer.solver.nodes.items.ptr);
    try std.testing.expectEqual(@as(u32, 0), inner.scratch.imported.count());
    const inner_arena = inner.arena;
    inner.deinit();
    inner_alive = false;
    try std.testing.expectEqual(types.u32_type, try outer.solver.resolve(root, 0));
    try std.testing.expectEqual(root, outer.scratch.imported.get(.{ .scope = 7, .ty = 13 }).?);
    outer.deinit();
    outer_alive = false;
    try std.testing.expect(session.regions.region_arena_pool.slot.? == inner_arena);
}

test "region arena Session allocator swaps preserve the original durable slot" {
    const allocator = std.testing.allocator;
    var session = try Session.init(allocator, &.{});
    defer session.deinit();
    var first = try ClosureRegion.init(&session);
    first.deinit();
    const retained_arena = session.regions.region_arena_pool.slot.?;
    var wrapper = std.testing.FailingAllocator.init(allocator, .{});
    session.allocator = wrapper.allocator();
    var temporary = ClosureRegion.init(&session) catch |err| {
        session.allocator = allocator;
        return err;
    };
    var temporary_alive = true;
    defer {
        session.allocator = allocator;
        if (temporary_alive) temporary.deinit();
    }
    try std.testing.expect(temporary.arena != retained_arena);
    session.allocator = allocator;
    temporary.deinit();
    temporary_alive = false;
    try std.testing.expect(session.regions.region_arena_pool.slot.? == retained_arena);
    var next = try ClosureRegion.init(&session);
    defer next.deinit();
    try std.testing.expect(next.arena == retained_arena);
    try std.testing.expect(next.arena.backing.ptr == allocator.ptr and next.arena.backing.vtable == allocator.vtable);
}

test "inference scratch retains bounded capacity and discards oversized regions" {
    const a = std.testing.allocator;
    var session = try Session.init(a, &.{});
    defer session.deinit();
    var first = try ClosureRegion.init(&session);
    try first.scratch.variables.append(first.scratch_allocator, .{ .source = .{ .scope = 0, .ty = 17 }, .region = types.u32_type });
    first.deinit();
    try std.testing.expect(session.regions.region_arena_pool.slot != null);
    try std.testing.expect(session.regions.region_arena_pool.stats.retained_bytes <= region_arena.limit);
    var oversized = try ClosureRegion.init(&session);
    try std.testing.expectEqual(@as(usize, 0), oversized.scratch.variables.items.len);
    try oversized.scratch.variables.ensureTotalCapacity(oversized.scratch_allocator, region_arena.limit / @sizeOf(ClosureRegion.Variable) + 1);
    oversized.deinit();
    try std.testing.expect(session.regions.region_arena_pool.slot == null);
    var next = try ClosureRegion.init(&session);
    defer next.deinit();
    try std.testing.expectEqual(@as(usize, 0), next.scratch.variables.items.len);
    try std.testing.expectEqual(@as(u32, 0), next.scratch.imported.count());
}

fn evidenceImportSharingScenario(allocator: Allocator) !void {
    var session = try Session.init(allocator, &.{});
    defer session.deinit();
    const e = &session.storage.evidence;
    const nominal = try e.intern(.nominal, 1, 7, &.{types.u32_type});
    const list = try e.intern(.list, nominal, 0, &.{});
    const operation = try e.effects.internOperation(.{ .unit = 1, .decl = 9 }, &.{list});
    const row = try e.effects.internRow(&.{operation});
    const provider = try e.internWithEffects(.provider, nominal, 0, row, &.{});
    const state = try e.internStateProvider(nominal, nominal, list);
    const record = try e.intern(.record, 0, 0, &.{ 11, provider, 13, state });
    const arrow = try e.internWithEffects(.function, record, list, row, &.{});
    const root = try e.intern(.product, 0, 0, &.{ arrow, arrow, list, record });
    var shared = try ClosureRegion.init(&session);
    defer shared.deinit();
    const imported = try shared.importEvidence(root, 0);
    const count = shared.solver.nodes.items.len;
    const cursor = shared.solver.cursor();
    for (0..16) |_| try std.testing.expectEqual(imported, try shared.importEvidence(root, 0));
    try std.testing.expectEqual(count, shared.solver.nodes.items.len);
    try std.testing.expectEqual(cursor, shared.solver.cursor());
    try std.testing.expectEqual(root, try shared.project(imported));
    try std.testing.expect(session.evidence_import_reused >= 16);
    // Closed graphs may be shared across independent variable histories, but
    // those histories remain distinct and retain cursor-relative resolution.
    const first = try shared.solver.fresh();
    const before = shared.solver.cursor();
    try shared.solver.unify(first, imported);
    const after = shared.solver.cursor();
    try std.testing.expectEqual(imported, try shared.solver.resolve(first, before));
    try std.testing.expectEqual(types.Tag.variable, shared.solver.node(try shared.solver.resolve(first, after)).tag);
    const second = try shared.solver.fresh();
    try shared.solver.unify(second, types.f32_type);
    try std.testing.expectEqual(root, try shared.project(imported));
}

fn closedSourceSharingScenario(a: Allocator, module: *const core.Module) !void {
    var session = try Session.init(a, @as([*]const core.Module, @ptrCast(module))[0..1]);
    defer session.deinit();
    var region = try ClosureRegion.init(&session);
    defer region.deinit();
    const left = try region.typeScope(0);
    const right = try region.typeScope(0);
    const concrete = module.bodies[1].scheme.root;
    const first = try region.importType(left, concrete, 0);
    const nodes = region.solver.nodes.items.len;
    try std.testing.expectEqual(first, try region.importType(right, concrete, 0));
    try std.testing.expectEqual(nodes, region.solver.nodes.items.len);
    try std.testing.expect(session.closed_source_reused != 0);
    const generic = module.types.node(module.bodies[2].scheme.root).a;
    const l = try region.importType(left, generic, 0);
    const r = try region.importType(right, generic, 0);
    try std.testing.expect(l != r);
    try region.solver.unify(l, types.u32_type);
    try region.solver.unify(r, types.f32_type);
    try std.testing.expectEqual(types.u32_type, try region.solver.resolve(l, 0));
    try std.testing.expectEqual(types.f32_type, try region.solver.resolve(r, 0));
    // Cached shallow success cannot hide a deeper request exceeding the quota.
    session.options.max_type_depth = 1;
    const deeper = try region.typeScope(0);
    try std.testing.expectError(error.TypeLimit, region.importType(deeper, concrete, 0));
    session.options.max_type_depth = 256;
    var rollback = try ClosureRegion.init(&session);
    defer rollback.deinit();
    const scope = try rollback.typeScope(0);
    const mark = rollback.solver.mark();
    _ = try rollback.importType(scope, concrete, 0);
    rollback.solver.rollback(mark);
    _ = try rollback.solver.array(types.f32_type);
    const restored = try rollback.importType(scope, concrete, 0);
    try std.testing.expectEqual(try region.project(first), try rollback.project(restored));
}

test "closed source imports share immutable graphs but isolate variables limits rollback and OOM" {
    const a = std.testing.allocator;
    var module = try bodyRecipeLower(
        \\const closed = fn (xs: Array { value: U32, enabled: Bool }) => xs
        \\const generic = fn xs => xs
        \\entry const answer = fn () => 42
    );
    defer module.deinit(a);
    try closedSourceSharingScenario(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, closedSourceSharingScenario, .{&module});
}

test "closed evidence imports share graphs and preserve semantic effects and chronology under allocation failures" {
    try evidenceImportSharingScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, evidenceImportSharingScenario, .{});
}

test "closed evidence imports preserve request depth limits and recover after failure" {
    var session = try Session.init(std.testing.allocator, &.{});
    defer session.deinit();
    const array = try session.storage.evidence.intern(.array, types.u32_type, 0, &.{});
    const root = try session.storage.evidence.intern(.list, array, 0, &.{});
    var region = try ClosureRegion.init(&session);
    defer region.deinit();
    session.options.max_type_depth = 3;
    const known = try region.importEvidence(root, 0);
    try std.testing.expectEqual(known, try region.importEvidence(root, 0));
    try std.testing.expectError(error.TypeLimit, region.importEvidence(root, 1));
    session.options.max_type_depth = 2;
    try std.testing.expectError(error.TypeLimit, region.importEvidence(root, 0));
    session.options.max_type_depth = 3;
    try std.testing.expectEqual(root, try region.project(try region.importEvidence(root, 0)));
}

test "closed evidence imports revoke recycled IDs physical mutations and saturated clocks" {
    var session = try Session.init(std.testing.allocator, &.{});
    defer session.deinit();
    const root = try session.storage.evidence.intern(.product, 0, 0, &.{ types.u32_type, types.boolean });
    var region = try ClosureRegion.init(&session);
    defer region.deinit();
    const mark = region.solver.mark();
    const old = try region.importEvidence(root, 0);
    region.solver.rollback(mark);
    try std.testing.expectEqual(old, try region.solver.array(types.f32_type));
    const current = try region.importEvidence(root, 0);
    try std.testing.expect(current != old);
    try std.testing.expectEqual(root, try region.project(current));
    const node = region.solver.node(current);
    region.solver.replaceListItem(.{ .start = node.a, .len = node.b }, 0, types.f32_type);
    const corrected = try region.importEvidence(root, 0);
    try std.testing.expect(corrected != current);
    try std.testing.expectEqual(root, try region.project(corrected));
    region.solver.closed_generation = std.math.maxInt(u16);
    const saturated = try region.importEvidence(root, 0);
    try std.testing.expect(saturated != try region.importEvidence(root, 0));
    region.solver.effects.physical_epoch = std.math.maxInt(u64);
    const exhausted = try region.importEvidence(root, 0);
    try std.testing.expect(exhausted != try region.importEvidence(root, 0));
}

test "closed evidence imports revoke effect rows on rollback and clear scratch between regions" {
    var session = try Session.init(std.testing.allocator, &.{});
    defer session.deinit();
    const op = try session.storage.evidence.effects.internOperation(.{ .unit = 1, .decl = 5 }, &.{types.u32_type});
    const row = try session.storage.evidence.effects.internRow(&.{op});
    const root = try session.storage.evidence.internWithEffects(.function, types.u32_type, types.u32_type, row, &.{});
    {
        var region = try ClosureRegion.init(&session);
        defer region.deinit();
        const before = region.solver.mark();
        _ = try region.importEvidence(root, 0);
        region.solver.rollback(before);
        _ = try region.solver.internOperation(.{ .unit = 2, .decl = 1 }, &.{types.f32_type});
        _ = try region.solver.effects.row(&.{1}, .closed);
        try std.testing.expectEqual(root, try region.project(try region.importEvidence(root, 0)));
    }
    var next = try ClosureRegion.init(&session);
    defer next.deinit();
    try std.testing.expectEqual(@as(u32, 0), next.scratch.evidence_import_cache.answers.count());
    try std.testing.expect(next.scratch.evidence_import_cache.source == null);
    _ = try next.solver.array(types.boolean);
    try std.testing.expectEqual(root, try next.project(try next.importEvidence(root, 0)));
}

fn mandatoryHeaderKey(region: *ClosureRegion, use: ClosureRegion.Constraint) !ClosureRegion.SchemeInstance {
    var imported = try region.schemeImport(use);
    try std.testing.expect(imported == .frame);
    defer imported.frame.copy.deinit();
    return imported.frame.key;
}

fn mandatoryHeaderHistoryScenario(allocator: Allocator, module: *const core.Module) !void {
    var session = try Session.init(allocator, &.{module.*});
    defer session.deinit();
    var region = try ClosureRegion.init(&session);
    defer region.deinit();
    const target_: Target = for (module.bodies) |body| {
        if (body.exported) break .{ .unit = 0, .binding = body.binding };
    } else unreachable;
    const binding = module.binding(target_.binding);
    var slots: std.ArrayList(types.Id) = .empty;
    defer slots.deinit(allocator);
    const before = region.solver.mark();
    for (0..binding.public_variables.len) |_| try slots.append(allocator, try region.solver.fresh());
    for (0..binding.public_rows.len) |_| try slots.append(allocator, try region.solver.functionWithEffects(types.unit, types.unit, try region.solver.freshEffects()));
    var use: ClosureRegion.Constraint = .{ .target = target_, .scope = 0, .node = 0, .left = try region.solver.product(slots.items), .result = 0 };
    const first = try mandatoryHeaderKey(&region, use);
    try std.testing.expect(first.open != 0);
    try region.scratch.scheme_instances.put(region.scratch_allocator, first, {});
    use.left = try region.solver.product(slots.items);
    try std.testing.expect((try region.schemeImport(use)) == .solved);

    // A second unknown type/row is a different input, even if its complete
    // representation is still unavailable. Repeated aliases also differ from
    // two independent unknowns.
    if (binding.public_variables.len != 0) {
        slots.items[slots.items.len - 1] = try region.solver.fresh();
    } else slots.items[slots.items.len - 1] = try region.solver.functionWithEffects(types.unit, types.unit, try region.solver.freshEffects());
    use.left = try region.solver.product(slots.items);
    const separate = try mandatoryHeaderKey(&region, use);
    try std.testing.expect(separate.open != first.open);
    if (binding.public_variables.len == 2) {
        slots.items[1] = slots.items[0];
        use.left = try region.solver.product(slots.items);
        const aliased = try mandatoryHeaderKey(&region, use);
        try std.testing.expect(aliased.open != first.open and aliased.open != separate.open);
    }

    region.solver.rollback(before);
    slots.clearRetainingCapacity();
    for (0..binding.public_variables.len) |_| try slots.append(allocator, try region.solver.fresh());
    for (0..binding.public_rows.len) |_| try slots.append(allocator, try region.solver.functionWithEffects(types.unit, types.unit, try region.solver.freshEffects()));
    use.left = try region.solver.product(slots.items);
    const recycled = try mandatoryHeaderKey(&region, use);
    try std.testing.expectEqual(first.open, recycled.open);
    try std.testing.expect(!std.meta.eql(first, recycled));
    try region.scratch.scheme_instances.put(region.scratch_allocator, recycled, {});
    try std.testing.expect((try region.schemeImport(use)) == .solved);

    region.solver.closed_generation = std.math.maxInt(u16);
    const saturated = try mandatoryHeaderKey(&region, use);
    try std.testing.expect(saturated.public == 0 and saturated.open == 0 and !saturated.constant);
    region.solver.effects.physical_epoch = std.math.maxInt(u64);
    const exhausted = try mandatoryHeaderKey(&region, use);
    try std.testing.expect(exhausted.public == 0 and exhausted.open == 0 and !exhausted.constant);
}

test "mandatory header inputs preserve unknown aliases rows rollback recycling saturation and ownership" {
    const allocator = std.testing.allocator;
    for ([_][]const u8{
        "entry const required: a -> b -> Unit where { type_rep a, type_rep b } = fn left => fn right => ()\n",
        "entry const required: Unit -> Unit ! {| e} where { effect_rep ! {| e} } = fn () => ()\n",
    }) |source| {
        var module = try bodyRecipeLower(source);
        defer module.deinit(allocator);
        try mandatoryHeaderHistoryScenario(allocator, &module);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, mandatoryHeaderHistoryScenario, .{&module});
    }
}

fn sourceHeadScenario(allocator: Allocator, module: *const core.Module) !void {
    var session = try Session.init(allocator, &.{module.*});
    defer session.deinit();
    var region = try ClosureRegion.init(&session);
    defer region.deinit();
    const scope = try region.typeScope(0);
    var closed: usize = 0;
    var open: usize = 0;
    for (module.operation_values) |operation| {
        if (operation.witness == 0) continue;
        const witness = module.typeOf(operation.witness);
        if (module.types.node(witness).tag == .variable) {
            const selected = try region.importType(scope, witness, 0);
            try region.solver.unify(selected, types.u32_type);
            try std.testing.expect(!try region.sourceHeadProven(0, witness, types.u32_type));
            open += 1;
        } else {
            try std.testing.expect(try region.sourceHeadProven(0, witness, operation.witness_result));
            try std.testing.expect(!try region.sourceHeadProven(0, witness, types.f32_type));
            closed += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), closed);
    try std.testing.expectEqual(@as(usize, 1), open);
    try std.testing.expect(!try region.sourceHeadProven(0, types.never, types.never));
    session.options.max_type_depth = 0;
    try std.testing.expect(!try region.sourceHeadProven(0, types.u32_type, types.u32_type));
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}

fn revealedCycleScenario(allocator: Allocator, module: *const core.Module, parent: core.BindingId, read: core.BindingId) !void {
    var session = try Session.init(allocator, &.{module.*});
    defer session.deinit();
    var region = try ClosureRegion.init(&session);
    defer region.deinit();
    region.source_interface = true;
    region.include_callables = true;
    const key: PrincipalGraph.Key = .{ .target = .{ .unit = 0, .binding = parent }, .source_interface = true, .deferred_member = false, .options = session.options };
    const original = (try region.principalGraphForKey(key)).?;
    for (original.constraints) |constraint| if (constraint.kind == .call_summary or constraint.kind == .scheme_use) {
        try std.testing.expect(constraint.target.binding != read);
    };
    for (0..2) |_| {
        try std.testing.expect(!try region.checkOpenPrincipal(key));
        var published = session.specializations.call_summaries.normalized_principals.keyIterator();
        while (published.next()) |entry| {
            try std.testing.expect(entry.target.binding != parent and entry.target.binding != read);
        }
        try std.testing.expect(session.diagnostic == null);
    }
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}

test "newly revealed source selection cycles decline without publishing partial members under allocation failure" {
    const allocator = std.testing.allocator;
    var module = try bodyRecipeLower(
        \\type Seed is data = #Seed
        \\type Box a is data = #Box a
        \\const Seed.build: a -> Seed -> Box a = fn value => fn seed => #Box value
        \\const f_0 = fn value => @type.call "build" value #Seed
        \\entry const parent: a -> a = fn value => (f_0 value).read
        \\const Box.read: Box a -> a = fn box => case box of
        \\  #Box value => value
        \\entry const recursive_read: Box a -> a = fn box => case box of
        \\  #Box value => parent value
    );
    defer module.deinit(allocator);
    var parent: core.BindingId = 0;
    var read: core.BindingId = 0;
    for (module.bodies) |body| {
        if (std.mem.eql(u8, module.name(body.export_name), "parent")) parent = body.binding;
        if (std.mem.eql(u8, module.name(body.export_name), "recursive_read")) read = body.binding;
    }
    try std.testing.expect(parent != 0 and read != 0);
    // Change an equally typed catalog target in the fixture before freezing it.
    // Component inference and its ordinary fallback are qualified in task 007;
    // this law isolates cycle-safe publication of the optional source graph.
    module.associated[1].target.binding = read;
    const frozen = try allocator.dupe(types.Node, module.types.nodes);
    defer allocator.free(frozen);
    const methods = try allocator.dupe(core.Associated, module.associated);
    defer allocator.free(methods);
    try revealedCycleScenario(allocator, &module, parent, read);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, revealedCycleScenario, .{ &module, parent, read });
    try std.testing.expectEqualDeep(frozen, module.types.nodes);
    try std.testing.expectEqualDeep(methods, module.associated);
}

test "source head theorems require immutable fixed heads and retain mismatches caller selections Never and limits" {
    const allocator = std.testing.allocator;
    var module = try bodyRecipeLower(
        \\type Cell a is data = #Cell a
        \\const closed = fn ignored => @state.get (#Cell 0)
        \\const parametric = fn (witness: Cell a) -> Cell a => @state.get witness
        \\const open = fn witness => @state.get witness
        \\entry const answer = 42
    );
    defer module.deinit(allocator);
    const frozen = try allocator.dupe(types.Node, module.types.nodes);
    defer allocator.free(frozen);
    try sourceHeadScenario(allocator, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, sourceHeadScenario, .{&module});
    try std.testing.expectEqualDeep(frozen, module.types.nodes);
}

fn callbackShapeDagScenario(allocator: Allocator) !void {
    var session = try Session.init(allocator, &.{});
    defer session.deinit();
    var shape = try session.storage.evidence.intern(.function, types.u32_type, types.u32_type, &.{});
    for (0..24) |_| shape = try session.storage.evidence.intern(.function, shape, shape, &.{});
    var region = try ClosureRegion.initWithSolverAllocator(&session, allocator);
    defer region.deinit();
    try std.testing.expect(try region.summaryValue(shape, 0));
    session.options.max_type_depth = 8;
    try std.testing.expect(!try region.summaryValue(shape, 0));
    session.options.max_type_depth = 256;
    session.options.max_children = 1;
    try std.testing.expect(!try region.summaryValue(shape, 0));
    session.options.max_children = 4096;
    session.options.max_values = 1;
    try std.testing.expect(!try region.summaryValue(shape, 0));
    session.options.max_values = 4096;
    try std.testing.expect(try region.summaryValue(shape, 0));
    const array = try session.storage.evidence.intern(.array, shape, 0, &.{});
    try std.testing.expect(!try region.summaryValue(array, 0));
    try std.testing.expect(!try region.firstOrderData(shape, 0));
}

test "callback shape admission bounds shared function DAGs and preserves the first order data boundary under allocation failure" {
    try callbackShapeDagScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, callbackShapeDagScenario, .{});
}

fn constantWarmQueryScenario(allocator: Allocator, module: *const core.Module) !void {
    var session = try Session.init(allocator, &.{module.*});
    defer session.deinit();
    session.minimum_constant_steps = 0;
    const callback = try session.richValue(.{ .unit = 1, .binding = 1 });
    const answer = try session.richValue(.{ .unit = 1, .binding = 2 });
    _ = try session.inferClosure(callback);
    const regions = session.counters.inference_regions;
    var warm = @import("../reuse/constant_receipt.zig").Recorder.init(&session);
    defer warm.deinit(allocator);
    session.constant_recorder = &warm;
    _ = try session.inferClosure(callback);
    try std.testing.expectEqual(regions, session.counters.inference_regions);
    try std.testing.expect(warm.eligible);
    try std.testing.expect(session.constant_recorder == &warm);
    var found_query = false;
    for (warm.events.items) |event| switch (event) {
        .query => |query| {
            try std.testing.expect(!found_query);
            try std.testing.expectEqual(callback, query.input);
            try std.testing.expect(query.kind == .inferred);
            found_query = true;
        },
        .work => |work| try std.testing.expectEqual(@as(usize, 0), work.steps),
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expect(found_query);
    try std.testing.expect(try warm.finish(allocator, &session, .{ .unit = 1, .binding = 2 }, answer, .{}) == null);
    session.constant_recorder = null;

    // Canonical key collection spends a cumulative budget even when it never
    // opens a solver region. The independent budget snapshot catches that too.
    var key_reads = @import("../reuse/constant_receipt.zig").Recorder.init(&session);
    defer key_reads.deinit(allocator);
    const serial = session.constant_inference_serial;
    const examined = session.specializations.canonical_specializations.examined_words;
    var key = (try session.specializations.canonical_specializations.key(&session, callback)) orelse return error.TestUnexpectedResult;
    defer key.deinit(allocator);
    try std.testing.expect(session.specializations.canonical_specializations.examined_words > examined);
    try std.testing.expectEqual(serial, session.constant_inference_serial);
    try std.testing.expect(try key_reads.finish(allocator, &session, .{ .unit = 1, .binding = 2 }, answer, .{}) == null);
}

test "constant receipt records ordinary warm query barriers and declines unowned canonical budget changes" {
    const allocator = std.testing.allocator;
    var module = try bodyRecipeLower("const callback = fn () -> U32 => 42\nentry const answer = 42\n");
    defer module.deinit(allocator);
    try constantWarmQueryScenario(allocator, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, constantWarmQueryScenario, .{&module});
}

fn constantReachableViewScenario(allocator: Allocator, module: *const core.Module) !void {
    var session = try Session.init(allocator, &.{module.*});
    defer session.deinit();
    session.minimum_constant_steps = 0;
    const reference: core.BindingRef = .{ .unit = 1, .binding = 1 };
    const empty = try session.richValue(reference);
    try std.testing.expectEqual(@as(u32, 0), session.valueEvidence(empty));
    const array = try session.storage.evidence.intern(.array, types.u32_type, 0, &.{});
    var recording = @import("../reuse/constant_receipt.zig").Recorder.init(&session);
    defer recording.deinit(allocator);
    try recording.read(allocator, &session, reference, empty);
    session.constant_recorder = &recording;
    defer session.constant_recorder = null;
    const selected = try session.typedView(0, module.body(1).?.root, empty, array);
    try std.testing.expect(selected != empty);
    const warm_values = session.storage.values.items.len;
    const warm_children = session.storage.children.items.len;
    try std.testing.expectEqual(selected, try session.typedView(0, module.body(1).?.root, empty, array));
    try std.testing.expectEqual(warm_values, session.storage.values.items.len);
    try std.testing.expectEqual(warm_children, session.storage.children.items.len);
    // The raw input stays reachable, so missing cache observation rejects.
    recording.view_inputs.getPtr(empty).?.* = false;
    try std.testing.expect(try recording.finish(allocator, &session, reference, selected, .{}) == null);
    recording.view_inputs.getPtr(empty).?.* = true;
    var owned = (try recording.finish(allocator, &session, reference, selected, .{})).?;
    defer owned.deinit(allocator);
    var effects: usize = 0;
    for (owned.events) |event| if (event == .view) {
        try std.testing.expectEqual(empty, event.view.value);
        try std.testing.expectEqual(selected, event.view.selected);
        try std.testing.expectEqual(effects != 0, event.view.existed);
        effects += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), effects);
    session.constant_recorder = null;
    // Model the missing publication while retaining both value headers, as a
    // graph-only replay would. Ordinary evaluation allocates a distinct alias.
    try std.testing.expect(session.storage.typed_views.remove(.{ .value = empty, .evidence = array }));
    const cold = try session.typedView(0, module.body(1).?.root, empty, array);
    try std.testing.expect(cold != selected);
    try std.testing.expectEqual(warm_values + 1, session.storage.values.items.len);
    try std.testing.expectEqual(warm_children, session.storage.children.items.len);
    try std.testing.expect(std.meta.eql(session.valueInfo(selected), session.valueInfo(cold)));
    // The difference is semantic under a tight ordinary value quota: a warm
    // alias succeeds at the limit, but another missing publication fails.
    session.options.max_values = session.constantValueCount();
    try std.testing.expectEqual(cold, try session.typedView(0, module.body(1).?.root, empty, array));
    try std.testing.expect(session.storage.typed_views.remove(.{ .value = empty, .evidence = array }));
    try std.testing.expectError(error.Declined, session.typedView(0, module.body(1).?.root, empty, array));
    try std.testing.expectEqual(Code.constant_fuel, session.diagnostic.?.code);
}

test "constant receipt owns reachable warm view effects and rejects incomplete observation" {
    const allocator = std.testing.allocator;
    var module = try bodyRecipeLower("const empty = #[]\nentry const answer = 42\n");
    defer module.deinit(allocator);
    try constantReachableViewScenario(allocator, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, constantReachableViewScenario, .{&module});
}

fn memberPrincipalScenario(a: Allocator) !void {
    const modules = [_]core.Module{.{ .types = .{ .nodes = &.{}, .extra = &.{}, .effects = .{ .rows = &.{}, .labels = &.{}, .variable_count = 0 }, .operations = &.{} }, .nodes = &.{}, .spans = &.{}, .extra = &.{}, .bindings = &.{}, .bodies = &.{}, .parameters = &.{}, .references = &.{}, .calls = &.{}, .merges = &.{}, .merge_ranges = &.{}, .names = &.{}, .obligations = &.{}, .diagnostics = &.{}, .body_lowerings = 0 }};
    var session = try Session.init(a, &modules);
    defer session.deinit();
    const key: PrincipalGraph.Key = .{ .target = .{ .unit = 0, .binding = 1 }, .source_interface = false, .deferred_member = false, .options = .{} };
    _ = try principalQueryTestRecord(&session.specializations.call_summaries.principals, &session, key, null);
    var trace: receipt.MemberTrace = .{};
    session.member_trace = &trace;
    try std.testing.expect(session.specializations.call_summaries.principals.get(key, &session) != null);
    try std.testing.expect(session.specializations.call_summaries.normalized_principals.get(key, &session) == null);
    session.member_trace = null;
    var member: receipt.Member = .{ .principals = trace.entries[0..trace.len], .principal_graphs = true, .target = .{ .unit = 1, .binding = 1 }, .function = 0, .query_budgets = @splat(0), .principal_nodes = 0, .principal_edges = 0, .summary_work = 0, .transitions = 0, .exhausted = false };
    try std.testing.expect(session.memberPrincipalsMatch(&member));
    // Counts and entries remain equal: the actual bounded lookup now declines.
    session.specializations.call_summaries.principals.lookup_budget = 0;
    try std.testing.expect(!session.memberPrincipalsMatch(&member));
    session.specializations.call_summaries.principals.lookup_budget = 4096;
    try std.testing.expect(session.memberPrincipalsMatch(&member));
    session.member_trace = &trace;
    try std.testing.expect(try session.specializations.call_summaries.principals.put(a, key, null, &session));
    session.member_trace = null;
    try std.testing.expect(!trace.complete);
}
test "constant receipt member judgments pin actual principal lookup outcomes and OOM" {
    try memberPrincipalScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, memberPrincipalScenario, .{});
}

fn shapeMemberScenario(allocator: Allocator, module: *const core.Module) !void {
    for ([_][]const u8{ "count_array", "count_list" }) |name| {
        const target_ = semanticTestTarget(module, name);
        const source = module.body(target_.binding).?.root;
        var expected_steps: usize = 0;
        for ([_]bool{ false, true }) |fast| {
            var session = try Session.init(allocator, &.{module.*});
            defer session.deinit();
            const empty = try session.makeAggregate(0, source, .array, 0, 0, &.{});
            var kind: ValueKind = .array;
            if (std.mem.eql(u8, name, "count_list")) kind = .list;
            const receiver = try session.makeAggregate(0, source, kind, 0, 0, &.{ empty, empty });
            try std.testing.expectEqual(@as(type_evidence.Id, 0), session.valueEvidence(receiver));
            var function: ValueId = undefined;
            if (fast) {
                function = (try session.shapeOnlyArrayMember(0, source, target_, receiver, types.u32_type)) orelse return error.ExpectedShapeMember;
                try std.testing.expectEqual(@as(u64, 0), session.counters.inference_regions);
            } else {
                function = try session.partialArrayMember(0, source, target_, receiver, types.u32_type);
                try std.testing.expect(session.counters.inference_regions != 0);
            }
            const result = try session.applyValue(0, source, function, receiver, 0);
            try std.testing.expect(result == .value);
            const answer = session.valueScalar(result.value) orelse return error.ExpectedScalar;
            try std.testing.expectEqual(@as(u32, 2), answer.bits);
            if (fast) try std.testing.expectEqual(expected_steps, session.steps) else expected_steps = session.steps;
        }
    }
}
test "shape only generic collection members preserve ordinary answers fuel and allocation failure" {
    var module = try bodyRecipeLower(
        \\entry const count_array: Array a -> U32 = fn values => @array.length values
        \\entry const count_list: List a -> U32 = fn values => @list.length values
    );
    defer module.deinit(std.testing.allocator);
    try shapeMemberScenario(std.testing.allocator, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, shapeMemberScenario, .{&module});
}

test "shape only member proofs retain changed bodies typed inputs effects and resource limits" {
    const allocator = std.testing.allocator;
    var module = try bodyRecipeLower(
        \\entry const generic: Array a -> U32 = fn values => @array.length values
        \\entry const concrete: Array U32 -> U32 = fn values => @array.length values
        \\entry const changed: Array a -> U32 = fn values => @u32.add 1 (@array.length values)
        \\entry const foreign: Array a -> U32 ! {Foreign} = fn values => @array.length values
    );
    defer module.deinit(allocator);
    var session = try Session.init(allocator, &.{module});
    defer session.deinit();
    const target_ = semanticTestTarget(&module, "generic");
    const source = module.body(target_.binding).?.root;
    const receiver = try session.makeAggregate(0, source, .array, 0, 0, &.{});
    for ([_][]const u8{ "concrete", "changed", "foreign" }) |name|
        try std.testing.expectEqual(@as(?ValueId, null), try session.shapeOnlyArrayMember(0, source, semanticTestTarget(&module, name), receiver, types.u32_type));
    try std.testing.expectEqual(@as(?ValueId, null), try session.shapeOnlyArrayMember(0, source, target_, receiver, types.f32_type));
    inline for (.{ "max_steps", "max_values", "max_children", "max_depth", "max_call_depth", "max_type_depth", "max_summary_transitions" }) |field| {
        const original = @field(session.options, field);
        @field(session.options, field) = original - 1;
        try std.testing.expectEqual(@as(?ValueId, null), try session.shapeOnlyArrayMember(0, source, target_, receiver, types.u32_type));
        @field(session.options, field) = original;
    }
    try std.testing.expect((try session.shapeOnlyArrayMember(0, source, target_, receiver, types.u32_type)) != null);
}

fn constantChildSpanScenario(allocator: Allocator, module: *const core.Module) !void {
    var session = try Session.init(allocator, &.{module.*});
    defer session.deinit();
    var parent = @import("../reuse/constant_receipt.zig").Recorder.init(&session);
    defer parent.deinit(allocator);
    try parent.beforeRead(allocator, &session);
    const reference: core.BindingRef = .{ .unit = 1, .binding = 1 };
    const value = try session.richValue(reference);
    try parent.read(allocator, &session, reference, value);
    const child = session.valueInfo(value);
    // Even an aligned observation serial cannot turn a child's new storage
    // into this parent's private buffer ownership.
    parent.collection_serial = session.storage.collection_buffers.mutation_serial;
    try std.testing.expect(!parent.canGrow(&session, .{ .start = child.start, .len = child.len }));
}

test "constant receipts exclude suspended dependency child spans from growth ownership" {
    const allocator = std.testing.allocator;
    var module = try bodyRecipeLower("const nested = @list.append [] 7\nentry const answer = 42\n");
    defer module.deinit(allocator);
    try constantChildSpanScenario(allocator, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, constantChildSpanScenario, .{&module});
}

fn constantViewDescriptorScenario(allocator: Allocator, module: *const core.Module) !void {
    var session = try Session.init(allocator, &.{module.*});
    defer session.deinit();
    const input = try session.richValue(.{ .unit = 1, .binding = 1 });
    const actual = try session.storage.evidence.intern(.function, types.u32_type, types.u32_type, &.{});
    const selected = try session.typedView(0, module.body(1).?.root, input, actual);
    try std.testing.expect(input != selected);
    const descriptor = session.valueInfo(input).bits;
    const copy: u32 = @intCast(session.storage.closures.items.len);
    try session.storage.closures.append(allocator, session.storage.closures.items[descriptor]);
    session.storage.values.items[selected].bits = copy;
    try session.storage.children.append(allocator, 0);
    // Zero-width starts and copied descriptor slots carry no identity.
    session.storage.values.items[selected].start = 1;
    const effect: receipt.ViewEffect = .{ .value = input, .selected = selected, .evidence = actual, .existed = false };
    try std.testing.expect(@import("../reuse/constant_receipt.zig").validView(session.snapshot(), effect));
    session.storage.closures.items[copy].identity += 1;
    try std.testing.expect(!@import("../reuse/constant_receipt.zig").validView(session.snapshot(), effect));
    session.storage.closures.items[copy].identity -= 1;
    var wrong = effect;
    wrong.evidence = types.u32_type;
    try std.testing.expect(!@import("../reuse/constant_receipt.zig").validView(session.snapshot(), wrong));
}

test "constant view receipts compare exact closure descriptors across metadata slots" {
    const allocator = std.testing.allocator;
    var module = try bodyRecipeLower("const callback = fn (value: U32) => @u32.add value 1\n");
    defer module.deinit(allocator);
    try constantViewDescriptorScenario(allocator, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, constantViewDescriptorScenario, .{&module});
}

fn partialRecordFieldScenario(allocator: Allocator) !void {
    var session = try Session.init(allocator, &.{});
    defer session.deinit();
    var expectations = try code_expectation.Store.init(allocator);
    defer expectations.deinit();
    for ([_][]const u32{
        &.{ 22, types.f32_type, 11, types.u32_type },
        &.{ 11, types.u32_type },
        &.{ 11, types.u32_type, 11, types.u32_type },
        &.{ 22, types.f32_type, 33, types.u32_type },
        &.{ 22, types.f32_type, 11, types.boolean },
    }, 0..) |fields, index| {
        var region = try ClosureRegion.initWithSolverAllocator(&session, allocator);
        defer region.deinit();
        const declared = try region.solver.record(&.{ .{ .name = 11, .ty = types.u32_type }, .{ .name = 22, .ty = types.f32_type } });
        const expected = try expectations.intern(.record, 0, 0, fields);
        region.code_expectation_remaining = 128;
        if (index == 0) {
            try region.matchCodeShape(declared, expectations.view(), expected, 0);
            region.code_expectation_remaining = 2;
            region.matchCodeShape(declared, expectations.view(), expected, 0) catch |err| {
                if (err == error.OutOfMemory) return err;
                try std.testing.expectEqual(error.TypeLimit, err);
                continue;
            };
            return error.ExpectedRecordShapeLimit;
        }
        region.matchCodeShape(declared, expectations.view(), expected, 0) catch |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expectEqual(error.TypeMismatch, err);
            continue;
        };
        return error.ExpectedRecordShapeMismatch;
    }
}
test "partial code record expectations match exact field names and payloads independent of order through OOM" {
    try partialRecordFieldScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, partialRecordFieldScenario, .{});
}

fn localCapabilityExitScenario(allocator: Allocator) !void {
    var session = try Session.init(allocator, &.{});
    defer session.deinit();
    const capability = try session.makeAggregate(0, 0, .capability, 0, 0, &.{});
    session.storage.values.items[capability].nominal = capability;
    const read = try session.storage.evidence.effects.internOperationInstance(.{ .unit = 1, .decl = 1 }, &.{}, .{ .unit = 0, .decl = capability });
    const write = try session.storage.evidence.effects.internOperationInstance(.{ .unit = 1, .decl = 2 }, &.{}, .{ .unit = 0, .decl = capability });
    const static = try session.storage.evidence.effects.internOperation(.{ .unit = 1, .decl = 1 }, &.{});
    const provider = try session.makeAggregate(0, 0, .provider, 0, read, &.{0});
    const state = try session.makeAggregate(0, 0, .state_provider, write, static, &.{0});
    const descriptor = try session.makeAggregate(0, 0, .effect_descriptor, 0, read, &.{});
    const row = try session.storage.evidence.effects.internRow(&.{ static, write });
    const set = try session.makeAggregate(0, 0, .effect_set, 0, row, &.{});
    for ([_]ValueId{ provider, state, descriptor, set }) |value_| {
        const nested = try session.makeAggregate(0, 0, .product, 0, 0, &.{value_});
        try std.testing.expect(try session.capabilityEscapes(0, 0, nested, capability));
    }
    const unrelated = try session.makeAggregate(0, 0, .state_provider, static, static, &.{0});
    try std.testing.expect(!try session.capabilityEscapes(0, 0, unrelated, capability));
}

test "compile time capability scope exit follows provider tokens and reflected keys through OOM" {
    try localCapabilityExitScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, localCapabilityExitScenario, .{});
}
