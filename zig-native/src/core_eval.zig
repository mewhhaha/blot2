//! Pure evaluation over immutable core. A compilation shares one session
//! so producer tracing and global constant values survive every code instance.
const std = @import("std");
const receipt = @import("specialization_receipt.zig");
const principal_inputs = @import("principal_inputs.zig");
const core = @import("core.zig");
const scalar_ops = @import("scalar_ops.zig");
const types = @import("types.zig");
const solver_capacity = @import("solver_capacity.zig");
const type_evidence = @import("type_evidence.zig");
const checked_types = @import("check.zig");
const code_expectation = @import("code_expectation.zig");
const provider_chain = @import("provider_chain.zig");
const body_recipe = @import("body_recipe.zig");
const runtime_identity = @import("runtime_identity.zig");
const Allocator = std.mem.Allocator;
const collection_growth = @import("eval_collection_growth.zig");
pub const Value = scalar_ops.Value;
pub const ValueId = u32;
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
/// Optional source-owned principal prepass reuse. Every request has expected
/// semantic evidence zero and empty caller seeds. Omitted facts remain holes.
/// A provider never reuses values or publishes a callable validation proof.
pub const PrincipalProvider = struct {
    context: *anyopaque,
    lookup: *const fn (*anyopaque, core.BindingRef, Options) Allocator.Error!?SolvedEvidence,
    record: *const fn (*anyopaque, core.BindingRef, Options, SolvedEvidence, ?*const principal_inputs.Key) Allocator.Error!void,
};
pub const ValueKind = enum(u8) { scalar, product, record, nominal, array, list, closure, suspension, type_constructor, resolver, provider, state_provider, effect_set, effect_descriptor, computation, request_decision, cursor };
pub const DemandState = enum { pending, evaluating, cached };
pub const Demand = struct { state: DemandState = .pending, value: ValueId = 0 };
/// A creation identity within one completed source constant evaluation. This
/// record is not a ready certificate: consumers must match exact captures and
/// inspect the current demand memo after completing their body/read proof.
pub const SourceSuspension = struct { producer: core.BindingRef, unit: u32, node: core.Id, value: ValueId };
pub const ClosureOrigin = enum(u8) { named, anonymous, constructor, primitive, operation };
/// Anonymous identities index core.Module.closures; named identities are binding
/// IDs; constructor identities index its constructor catalog. Children store
/// lexical captures or already supplied arguments in their immutable order.
pub const ClosureValue = struct { unit: u32, identity: u32, applied: u32 = 0, origin: ClosureOrigin, mappings: core.List = .{}, row_mappings: core.List = .{}, ty: types.Id = 0 };
/// Scalars carry exact bits; nominal bits are the constructor tag. Aggregate
/// children are immutable handles in a separate contiguous buffer. Nominal
/// identity is the producer unit/declaration pair, independent of type arguments.
pub const ValueInfo = struct {
    nominal: u64 = 0,
    start: u32 = 0,
    len: u32 = 0,
    bits: u32 = 0,
    kind: ValueKind = .scalar,
    scalar: @TypeOf(@as(Value, undefined).scalar) = .unit,
};
pub const Snapshot = struct {
    values: []ValueInfo,
    children: []ValueId,
    closures: []ClosureValue,
    value_evidence: []type_evidence.Id,
    type_mappings: []type_evidence.Mapping,
    row_mappings: []type_evidence.RowMapping,
    evidence: type_evidence.Snapshot,
    value_records: []u32,
    record_layouts: []core.List,
    field_names: []u32,
    demands: []Demand,
    pub fn deinit(self: *Snapshot, allocator: Allocator) void {
        allocator.free(self.values);
        allocator.free(self.children);
        allocator.free(self.closures);
        allocator.free(self.value_evidence);
        allocator.free(self.type_mappings);
        allocator.free(self.row_mappings);
        self.evidence.deinit(allocator);
        allocator.free(self.value_records);
        allocator.free(self.record_layouts);
        allocator.free(self.field_names);
        allocator.free(self.demands);
        self.* = undefined;
    }
};
pub const View = struct { values: []const ValueInfo, children: []const ValueId, closures: []const ClosureValue, value_evidence: []const type_evidence.Id, type_mappings: []const type_evidence.Mapping, row_mappings: []const type_evidence.RowMapping, evidence: type_evidence.View, value_records: []const u32, record_layouts: []const core.List, field_names: []const u32, demands: []const Demand };
pub const Error = Allocator.Error || error{ Declined, RequestUnwind };
pub const Options = struct {
    reuse_body_recipes: bool = true,
    reuse_validated_calls: bool = true,
    max_steps: usize = 1_000_000,
    max_depth: usize = 256,
    max_values: usize = 1_000_000,
    max_children: usize = 4_194_304,
    /// Code generation traces initializer dependencies without executing runtime
    /// globals. Constant reads remain forbidden independently of this option.
    trace_runtime_dependencies: bool = false,
    retain_source_suspensions: bool = false,
};
pub const Code = @import("diagnostic_code.zig").Code;
pub const Diagnostic = struct {
    unit: u32,
    span: core.Span,
    code: Code,
    detail: []const u8 = "",
    /// Tag application has already selected its public source invocation.
    tag_origin: bool = false,
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
const Flow = union(enum) { value: ValueId, returning: struct { target: core.Id, value: ValueId }, breaking: struct { target: core.Id, values: core.List } };
const Frame = struct {
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
const ViewKey = struct { value: ValueId, evidence: type_evidence.Id };
// Offsets remain stable when field_names grows. The context is supplied for
// every lookup, so no hash-table key borrows a reallocatable slice pointer.
const RecordNames = struct {
    words: []const u32,
    pub fn hash(self: @This(), key: core.List) u64 {
        return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(self.words[key.start..][0..key.len]));
    }
    pub fn eql(self: @This(), a: core.List, b: core.List) bool {
        return std.mem.eql(u32, self.words[a.start..][0..a.len], self.words[b.start..][0..b.len]);
    }
    const Adapter = struct {
        words: []const u32,
        pub fn hash(_: @This(), names: []const u32) u64 {
            return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(names));
        }
        pub fn eql(self: @This(), names: []const u32, key: core.List) bool {
            return std.mem.eql(u32, names, self.words[key.start..][0..key.len]);
        }
    };
};
const RecordKey = struct { unit: usize, ty: types.Id };
const unit_value: Value = .{ .scalar = .unit, .bits = 0 };

/// Semantic inputs retained beside a callable template's erased environment.
/// Type IDs belong to `unit`; evidence IDs belong to this Session. Importing
/// this description imports signatures without evaluating their values. The
/// selected instance still collects and solves its complete body separately.
pub const RetainedValue = struct { binding: core.BindingId, evidence: type_evidence.Id };
pub const RetainedCapture = struct {
    binding: core.BindingId,
    unit: u32,
    node: core.Id,
    mappings: type_evidence.Id = 0,
    rows: []const type_evidence.RowMapping = &.{},
    values: []const RetainedValue = &.{},
    captures: []const RetainedCapture = &.{},
    computation: bool = false,
};
pub const ProofStats = struct { proof_published: usize = 0, proof_reused: usize = 0 };
pub const DiagnosticContext = struct { identity: ?runtime_identity.View = null, entry: u32 = 0, prelude: u32 = 0, source_mode: bool = false };
const IndexedRegion = struct {
    owner: usize,
    frame: *Frame,
    original: ValueId,
    children: []ValueId,
    plan: @import("eval_indexed_builder.zig").Plan,
};

pub const Session = struct {
    timing: ?*@import("backend_timing.zig").Work = null,
    /// Private storage policy; no solver evidence or source owner is pooled.
    reuse_solver_capacity: bool = true,
    reuse_region_scratch: bool = true,
    reuse_callable_definitions: bool = true,
    reuse_evidence_imports: bool = true,
    reuse_closed_source_types: bool = true,
    split_closed_calls: bool = false,
    split_active: std.AutoHashMapUnmanaged(Target, void) = .empty,
    split_attempts: usize = 0,
    split_accepted: usize = 0,
    split_declined: usize = 0,
    closed_source_types: @import("closed_source_types.zig").Facts = .{},
    closed_source_imports: usize = 0,
    closed_source_reused: usize = 0,
    evidence_import_requests: usize = 0,
    evidence_import_reused: usize = 0,
    callable_definitions: std.AutoHashMapUnmanaged(ClosureRegion.DefinitionKey, core.BindingId) = .empty,
    callable_definition_units: std.AutoHashMapUnmanaged(usize, void) = .empty,
    region_scratch_pool: @import("scratch_pool.zig").Pool(ClosureRegion.Scratch) = .{},
    solver_capacity_pool: solver_capacity.Pool = .{},
    retain_specialization_receipts: bool = false,
    specialization_provider: ?receipt.Provider = null,
    specialization_receipts: std.ArrayList(receipt.Record) = .empty,
    receipt_tape: ?*receipt.Tape = null,
    refinement_observation: ?*@import("refinement_receipt.zig").Observation = null,
    principal_provider: ?PrincipalProvider = null,
    principal_regions: usize = 0,
    retain_principal_inputs: bool = false,
    principal_reads: ?*principal_inputs.Recorder = null,
    owned_diagnostic_message: []u8 = &.{},
    /// Borrowed only during emission. Core owns the low-level API fallback;
    /// project origin policy is explicit and belongs to the current consumer.
    diagnostic_context: DiagnosticContext = .{},
    body_recipes: body_recipe.Cache = .{},
    proofs: ProofStats = .{},
    validated_calls: std.AutoHashMapUnmanaged(CallProofKey, void) = .empty,
    plain_nominals: std.AutoHashMapUnmanaged(u64, bool) = .empty,
    allocator: Allocator,
    units: []const core.Module,
    providers: provider_chain.Store,
    options: Options = .{},
    steps: usize = 0,
    diagnostic: ?Diagnostic = null,
    traced_bodies: usize = 0,
    traced_nodes: usize = 0,
    binding_offsets: []usize,
    node_offsets: []usize,
    slots: []Slot,
    visited_nodes: []bool,
    pending: std.ArrayList(Target) = .empty,
    draining_pending: bool = false,
    values: std.ArrayList(ValueInfo) = .empty,
    children: std.ArrayList(ValueId) = .empty,
    collection_buffers: collection_growth.Store = .{},
    indexed_region: ?*IndexedRegion = null,
    closures: std.ArrayList(ClosureValue) = .empty,
    demands: std.ArrayList(Demand) = .empty,
    source_suspensions: std.ArrayList(SourceSuspension) = .empty,
    source_producer: ?Target = null,
    value_evidence: std.ArrayList(type_evidence.Id) = .empty,
    type_mappings: std.ArrayList(type_evidence.Mapping) = .empty,
    row_mappings: std.ArrayList(type_evidence.RowMapping) = .empty,
    evidence: type_evidence.Store,
    typed_views: std.AutoHashMapUnmanaged(ViewKey, ValueId) = .empty,
    specialized_closures: std.AutoHashMapUnmanaged(ViewKey, ValueId) = .empty,
    value_records: std.ArrayList(u32) = .empty,
    record_layouts: std.ArrayList(core.List) = .empty,
    field_names: std.ArrayList(u32) = .empty,
    record_types: std.AutoHashMapUnmanaged(RecordKey, u32) = .empty,
    record_shapes: std.HashMapUnmanaged(core.List, u32, RecordNames, 80) = .empty,
    break_values: std.ArrayList(ValueId) = .empty,
    field_locations: std.AutoHashMapUnmanaged(FieldKey, FieldLocation) = .empty,
    request_cells: std.ArrayList(RequestCell) = .empty,
    request_handlers: std.ArrayList(RequestHandler) = .empty,
    request_owner: u32 = 0,
    demanded: usize = 0,
    depth: usize = 0,

    pub fn init(allocator: Allocator, units: []const core.Module) Allocator.Error!Session {
        const binding_offsets = try allocator.alloc(usize, units.len);
        errdefer allocator.free(binding_offsets);
        const node_offsets = try allocator.alloc(usize, units.len);
        errdefer allocator.free(node_offsets);
        var binding_count: usize = 0;
        var node_count: usize = 0;
        for (units, 0..) |module, index| {
            binding_offsets[index] = binding_count;
            node_offsets[index] = node_count;
            binding_count = std.math.add(usize, binding_count, module.bindings.len) catch return error.OutOfMemory;
            node_count = std.math.add(usize, node_count, module.nodes.len) catch return error.OutOfMemory;
        }
        const slots = try allocator.alloc(Slot, binding_count);
        errdefer allocator.free(slots);
        @memset(slots, .{});
        const visited_nodes = try allocator.alloc(bool, node_count);
        errdefer allocator.free(visited_nodes);
        @memset(visited_nodes, false);
        var values: std.ArrayList(ValueInfo) = .empty;
        errdefer values.deinit(allocator);
        try values.append(allocator, .{});
        var value_evidence: std.ArrayList(type_evidence.Id) = .empty;
        errdefer value_evidence.deinit(allocator);
        try value_evidence.append(allocator, types.unit);
        var value_records: std.ArrayList(u32) = .empty;
        errdefer value_records.deinit(allocator);
        try value_records.append(allocator, 0);
        var record_layouts: std.ArrayList(core.List) = .empty;
        errdefer record_layouts.deinit(allocator);
        try record_layouts.append(allocator, .{});
        var evidence = type_evidence.Store.init(allocator) catch return error.OutOfMemory;
        errdefer evidence.deinit();
        var field_locations: std.AutoHashMapUnmanaged(FieldKey, FieldLocation) = .empty;
        errdefer field_locations.deinit(allocator);
        var families: std.AutoHashMapUnmanaged(u64, void) = .empty;
        defer families.deinit(allocator);
        for (units, 0..) |module, index| {
            const unit_id: u32 = if (module.unit != 0) module.unit else @intCast(index + 1);
            for (module.nominals) |nominal| {
                if (nominal.identity.decl == 0) continue;
                const family = (@as(u64, if (nominal.identity.unit == 0) unit_id else nominal.identity.unit) << 32) | nominal.identity.decl;
                const entry = try families.getOrPut(allocator, family);
                if (entry.found_existing) continue;
                for (module.extra[nominal.constructors.start..][0..nominal.constructors.len]) |constructor_index| {
                    const constructor = module.constructor(constructor_index);
                    if (constructor.payload == 0) continue;
                    const payload = module.types.node(constructor.payload);
                    if (payload.tag != .record) continue;
                    for (0..payload.b) |field| try field_locations.put(allocator, .{ .family = family, .tag = constructor.tag, .name = module.types.recordField(payload, field).name }, .{ .field = @intCast(field), .len = payload.b });
                }
            }
        }
        return .{ .region_scratch_pool = .init(allocator), .solver_capacity_pool = solver_capacity.Pool.init(allocator), .allocator = allocator, .units = units, .providers = provider_chain.Store.init(allocator), .binding_offsets = binding_offsets, .node_offsets = node_offsets, .slots = slots, .visited_nodes = visited_nodes, .values = values, .field_locations = field_locations, .value_evidence = value_evidence, .evidence = evidence, .value_records = value_records, .record_layouts = record_layouts };
    }
    pub fn deinit(self: *Session) void {
        self.solver_capacity_pool.deinit();
        self.region_scratch_pool.deinit();
        self.callable_definitions.deinit(self.allocator);
        self.callable_definition_units.deinit(self.allocator);
        self.allocator.free(self.owned_diagnostic_message);
        self.body_recipes.deinit(self.allocator);
        self.closed_source_types.deinit(self.allocator);
        self.split_active.deinit(self.allocator);
        self.validated_calls.deinit(self.allocator);
        self.plain_nominals.deinit(self.allocator);
        self.allocator.free(self.binding_offsets);
        self.allocator.free(self.node_offsets);
        self.allocator.free(self.slots);
        self.allocator.free(self.visited_nodes);
        self.pending.deinit(self.allocator);
        self.values.deinit(self.allocator);
        self.children.deinit(self.allocator);
        self.collection_buffers.deinit(self.allocator);
        self.closures.deinit(self.allocator);
        self.demands.deinit(self.allocator);
        self.source_suspensions.deinit(self.allocator);
        self.value_evidence.deinit(self.allocator);
        self.type_mappings.deinit(self.allocator);
        self.row_mappings.deinit(self.allocator);
        self.evidence.deinit();
        self.providers.deinit();
        self.request_cells.deinit(self.allocator);
        self.request_handlers.deinit(self.allocator);
        self.typed_views.deinit(self.allocator);
        self.specialized_closures.deinit(self.allocator);
        for (self.specialization_receipts.items) |*record| record.deinit(self.allocator);
        self.specialization_receipts.deinit(self.allocator);
        self.value_records.deinit(self.allocator);
        self.record_layouts.deinit(self.allocator);
        self.field_names.deinit(self.allocator);
        self.record_types.deinit(self.allocator);
        self.record_shapes.deinit(self.allocator);
        self.break_values.deinit(self.allocator);
        self.field_locations.deinit(self.allocator);
        self.* = undefined;
    }
    pub fn valueInfo(self: *const Session, id: ValueId) ValueInfo {
        return self.values.items[id];
    }
    pub fn valueChildren(self: *const Session, id: ValueId) []const ValueId {
        const info = self.valueInfo(id);
        return self.children.items[info.start..][0..info.len];
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
        return self.closures.items[info.bits];
    }
    pub fn suspensionInfo(self: *const Session, id: ValueId) ClosureValue {
        std.debug.assert(self.valueInfo(id).kind == .suspension);
        return self.closureInfo(id);
    }
    pub fn suspensionCached(self: *const Session, id: ValueId) ?ValueId {
        const info = self.valueInfo(id);
        std.debug.assert(info.kind == .suspension);
        const memo = self.demands.items[@intCast(info.nominal)];
        return if (memo.state == .cached) memo.value else null;
    }
    pub fn singleSourceSuspension(self: *const Session, producer: core.BindingRef, unit: u32, node: core.Id) ?ValueId {
        if (self.principal_reads) |reads| reads.invalidate(.suspension);
        // Startup creation history is not part of a completed specialization
        // receipt. A future caller under that tape must take the fresh path.
        if (self.receipt_tape) |tape| tape.unknown = true;
        var found: ?ValueId = null;
        for (self.source_suspensions.items) |source| {
            if (!std.meta.eql(source.producer, producer) or source.unit != unit or source.node != node) continue;
            if (found != null) return null;
            found = source.value;
        }
        return found;
    }
    pub fn valueEvidence(self: *const Session, id: ValueId) type_evidence.Id {
        return self.value_evidence.items[id];
    }
    pub fn evidenceView(self: *const Session) type_evidence.View {
        return self.evidence.view();
    }
    /// Names follow storage slots, independently of semantic record equality.
    pub fn recordFieldNames(self: *const Session, id: ValueId) []const u32 {
        const span = self.record_layouts.items[self.value_records.items[id]];
        return self.field_names.items[span.start..][0..span.len];
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
        const key: ViewKey = .{ .value = value_, .evidence = 0 };
        if (self.specialized_closures.get(key)) |existing| return existing;
        try self.specialized_closures.ensureUnusedCapacity(self.allocator, 1);
        var region = ClosureRegion.init(self) catch return error.OutOfMemory;
        defer region.deinit();
        const inferred: ?ValueId = if (entry_interface)
            region.inferEntry(value_) catch |err| return self.evidenceFailure(owner, span, err)
        else
            region.infer(value_) catch |err| return self.evidenceFailure(owner, span, err);
        if (inferred) |selected| try self.cacheSpecialization(key, selected);
        return inferred;
    }
    pub fn specializeSuspension(self: *Session, value_: ValueId, expected: type_evidence.Id) Error!ValueId {
        if (self.valueInfo(value_).kind != .suspension) return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        return self.specializeRetained(value_, expected);
    }
    fn specializeRetained(self: *Session, value_: ValueId, expected: type_evidence.Id) Error!ValueId {
        const metadata = self.closureInfo(value_);
        const owner = self.findUnit(metadata.unit, null) orelse return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        const module = &self.units[owner];
        const span = switch (metadata.origin) {
            .anonymous => module.span(module.closures[metadata.identity].body),
            .named => (module.body(metadata.identity) orelse return self.fail(owner, .{ .start = 0, .end = 0 }, .unsupported)).span,
            .constructor, .primitive, .operation => core.Span{ .start = 0, .end = 0 },
        };
        const expected_kind: type_evidence.Tag = if (self.valueInfo(value_).kind == .suspension) .demand else .function;
        if (expected == 0 or self.evidence.node(expected).tag != expected_kind) return self.fail(owner, span, .unsupported);
        const key: ViewKey = .{ .value = value_, .evidence = expected };
        if (self.principal_reads) |reads| reads.invalidate(.specialize);
        if (self.receipt_tape) |tape| tape.nested = true;
        if (self.specialized_closures.get(key)) |existing| return existing;
        if (self.receipt_tape == null) if (self.specialization_provider) |provider| if (try provider.lookup(provider.context, self, value_, expected)) |selected| return selected;
        try self.specialized_closures.ensureUnusedCapacity(self.allocator, 1);
        const values_before = self.values.items.len;
        const children_before = self.children.items.len;
        const steps_before = self.steps;
        var tape: receipt.Tape = .{};
        defer tape.deinit(self.allocator);
        const previous_tape = self.receipt_tape;
        const recording = self.retain_specialization_receipts and previous_tape == null;
        if (recording) self.receipt_tape = &tape;
        defer self.receipt_tape = previous_tape;
        if (recording) try self.specialization_receipts.ensureUnusedCapacity(self.allocator, 1);
        var region = ClosureRegion.init(self) catch return error.OutOfMemory;
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
            .values_added = self.values.items.len - values_before,
            .children_added = self.children.items.len - children_before,
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
        try self.cacheSpecialization(key, specialized);
        if (record) |owned| {
            self.specialization_receipts.appendAssumeCapacity(owned);
            record = null;
        }
        return specialized;
    }
    fn cacheSpecialization(self: *Session, key: ViewKey, selected: ValueId) Allocator.Error!void {
        // Nested refinement may consume the capacity reserved before the region.
        try self.specialized_closures.put(self.allocator, key, selected);
    }
    /// Reconstruct the source-owned public interface before ordinary evaluation.
    /// The region may retain unresolved staging obligations; it never reads or
    /// publishes an evaluated constant or a caller-constrained closure header.
    pub fn sourceInterface(self: *Session, reference: core.BindingRef) Error!SourceInterface {
        const resolved = try self.external(try self.target(null, reference));
        const module = &self.units[resolved.unit];
        const body = module.body(resolved.binding) orelse return self.fail(resolved.unit, module.binding(resolved.binding).span, .unsupported);
        var region = ClosureRegion.init(self) catch return error.OutOfMemory;
        defer region.deinit();
        return region.sourceInterface(resolved, body) catch |err| return self.evidenceFailure(resolved.unit, body.span, err);
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
        var region = ClosureRegion.init(self) catch return error.OutOfMemory;
        defer region.deinit();
        return region.bodyEvidence(target_.unit, body.root, module.binding(target_.binding).ty, body.closed_rows, body.scheme, .{ .code = .{ .view = expectations, .id = expected } }, seeds) catch |err| return self.evidenceFailure(target_.unit, module.span(body.root), err);
    }
    pub fn bodyEvidencePartialFull(self: *Session, reference: core.BindingRef, expectations: code_expectation.View, expected: code_expectation.Id, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping) Error!SolvedEvidence {
        const target_ = try self.external(try self.target(null, reference));
        const module = &self.units[target_.unit];
        const body = module.body(target_.binding) orelse return self.fail(target_.unit, module.binding(target_.binding).span, .unsupported);
        var region = ClosureRegion.init(self) catch return error.OutOfMemory;
        defer region.deinit();
        return region.bodyEvidenceFull(target_.unit, body.root, module.binding(target_.binding).ty, body.closed_rows, body.scheme, .{ .code = .{ .view = expectations, .id = expected } }, seeds, row_seeds) catch |err| return self.evidenceFailure(target_.unit, module.span(body.root), err);
    }
    /// Copy only completed primitive inputs into a fresh, independently owned
    /// probe for these same immutable units. No rich semantic IDs are copied.
    pub fn seedScalarInputs(self: *Session, current: *const Session) Error!void {
        if (self.units.ptr != current.units.ptr or self.units.len != current.units.len) return error.Declined;
        for (self.units, 0..) |module, owner| {
            for (module.bindings, 0..) |binding, index| {
                if (binding.kind != .global) continue;
                const body = module.body(@intCast(index)) orelse continue;
                if (body.runtime) continue;
                const offset = self.binding_offsets[owner] + index;
                const old = current.slots[offset];
                if (old.state != .complete) continue;
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
        var region = ClosureRegion.init(self) catch return error.OutOfMemory;
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
        var region = ClosureRegion.init(self) catch return error.OutOfMemory;
        defer region.deinit();
        return region.bodyEvidenceFull(target_.unit, body.root, module.binding(target_.binding).ty, body.closed_rows, body.scheme, .{ .semantic = expected }, seeds, row_seeds) catch |err| return self.evidenceFailure(target_.unit, module.span(body.root), err);
    }
    /// Initializer-specific source dependencies, obtained without executing a
    /// value. Generic producers are instantiated in this region; two callers
    /// may therefore select different methods without merging their edges.
    pub fn startupDependencies(self: *Session, reference: core.BindingRef) Error!StartupDependencies {
        const target_ = try self.external(try self.target(null, reference));
        const module = &self.units[target_.unit];
        const body = module.body(target_.binding) orelse return self.fail(target_.unit, module.binding(target_.binding).span, .unsupported);
        var region = ClosureRegion.init(self) catch return error.OutOfMemory;
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
                .associated, .project, .result_associated, .resolver_op, .update, .operation_value, .invalid => return false,
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
                .block, .suite, .product, .record, .array, .array_op, .call => for (module.children(key.node)) |id| {
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
        var region = ClosureRegion.init(self) catch return error.OutOfMemory;
        defer region.deinit();
        return region.closureEvidence(owner, closure, .{ .semantic = expected }, seeds) catch |err| return self.evidenceFailure(owner, module.span(closure.body), err);
    }
    pub fn closureEvidencePartial(self: *Session, unit: u32, catalog: u32, expectations: code_expectation.View, expected: code_expectation.Id, seeds: []const type_evidence.Mapping) Error![]type_evidence.Mapping {
        const owner = self.findUnit(unit, null) orelse return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        const module = &self.units[owner];
        if (catalog >= module.closures.len) return self.fail(owner, .{ .start = 0, .end = 0 }, .unsupported);
        const closure = module.closures[catalog];
        var region = ClosureRegion.init(self) catch return error.OutOfMemory;
        defer region.deinit();
        return region.closureEvidence(owner, closure, .{ .code = .{ .view = expectations, .id = expected } }, seeds) catch |err| return self.evidenceFailure(owner, module.span(closure.body), err);
    }
    pub fn closureEvidencePartialFull(self: *Session, unit: u32, catalog: u32, expectations: code_expectation.View, expected: code_expectation.Id, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping) Error!SolvedEvidence {
        const owner = self.findUnit(unit, null) orelse return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        const module = &self.units[owner];
        if (catalog >= module.closures.len) return self.fail(owner, .{ .start = 0, .end = 0 }, .unsupported);
        const closure = module.closures[catalog];
        var region = ClosureRegion.init(self) catch return error.OutOfMemory;
        defer region.deinit();
        return region.closureEvidenceFull(owner, closure, .{ .code = .{ .view = expectations, .id = expected } }, seeds, row_seeds) catch |err| return self.evidenceFailure(owner, module.span(closure.body), err);
    }
    pub fn closureEvidencePartialCaptures(self: *Session, unit: u32, catalog: u32, expectations: code_expectation.View, expected: code_expectation.Id, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping, captures: []const RetainedCapture) Error!SolvedEvidence {
        const owner = self.findUnit(unit, null) orelse return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        const module = &self.units[owner];
        if (catalog >= module.closures.len) return self.fail(owner, .{ .start = 0, .end = 0 }, .unsupported);
        const closure_ = module.closures[catalog];
        var region = ClosureRegion.init(self) catch return error.OutOfMemory;
        defer region.deinit();
        return region.closureEvidenceCaptures(owner, closure_, .{ .code = .{ .view = expectations, .id = expected } }, seeds, row_seeds, captures) catch |err| return self.evidenceFailure(owner, module.span(closure_.body), err);
    }
    pub fn closureEvidenceFull(self: *Session, unit: u32, catalog: u32, expected: type_evidence.Id, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping) Error!SolvedEvidence {
        const owner = self.findUnit(unit, null) orelse return self.fail(self.units.len, .{ .start = 0, .end = 0 }, .unsupported);
        const module = &self.units[owner];
        if (catalog >= module.closures.len) return self.fail(owner, .{ .start = 0, .end = 0 }, .unsupported);
        const closure = module.closures[catalog];
        var region = ClosureRegion.init(self) catch return error.OutOfMemory;
        defer region.deinit();
        return region.closureEvidenceFull(owner, closure, .{ .semantic = expected }, seeds, row_seeds) catch |err| return self.evidenceFailure(owner, module.span(closure.body), err);
    }
    fn solveEvidence(self: *Session, owner: usize, body: core.Id, root: types.Id, closed_rows: types.List, scheme: types.Scheme, expected: type_evidence.Id, seeds: []const type_evidence.Mapping) Error![]type_evidence.Mapping {
        var region = ClosureRegion.init(self) catch return error.OutOfMemory;
        defer region.deinit();
        return region.bodyEvidence(owner, body, root, closed_rows, scheme, .{ .semantic = expected }, seeds) catch |err| return self.evidenceFailure(owner, self.units[owner].span(body), err);
    }
    fn evidenceFailure(self: *Session, owner: usize, span: core.Span, err: ClosureRegion.RegionError) Error {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.Declined => error.Declined,
            error.RequestUnwind => error.RequestUnwind,
            error.TypeLimit, error.EvidenceLimit => self.fail(owner, span, .constant_fuel),
            error.TypeMismatch, error.InfiniteType => self.fail(owner, span, .type_mismatch),
            error.EffectMismatch => self.fail(owner, span, .effect_mismatch),
            error.InfiniteEffect => self.fail(owner, span, .infinite_effect),
            error.UnresolvedType => self.fail(owner, span, .unsupported),
        };
    }
    /// Borrowed until this session is destroyed. Array growth preserves handles,
    /// so consumers obtain the view after evaluation rather than retaining slices.
    pub fn snapshot(self: *const Session) View {
        return .{ .values = self.values.items, .children = self.children.items, .closures = self.closures.items, .value_evidence = self.value_evidence.items, .type_mappings = self.type_mappings.items, .row_mappings = self.row_mappings.items, .evidence = self.evidence.view(), .value_records = self.value_records.items, .record_layouts = self.record_layouts.items, .field_names = self.field_names.items, .demands = self.demands.items };
    }
    pub fn copySnapshot(self: *const Session, allocator: Allocator) Allocator.Error!Snapshot {
        const values = try allocator.dupe(ValueInfo, self.values.items);
        errdefer allocator.free(values);
        const children = try allocator.dupe(ValueId, self.children.items);
        errdefer allocator.free(children);
        const closures = try allocator.dupe(ClosureValue, self.closures.items);
        errdefer allocator.free(closures);
        const value_evidence = try allocator.dupe(type_evidence.Id, self.value_evidence.items);
        errdefer allocator.free(value_evidence);
        const type_mappings = try allocator.dupe(type_evidence.Mapping, self.type_mappings.items);
        errdefer allocator.free(type_mappings);
        const row_mappings = try allocator.dupe(type_evidence.RowMapping, self.row_mappings.items);
        errdefer allocator.free(row_mappings);
        const value_records = try allocator.dupe(u32, self.value_records.items);
        errdefer allocator.free(value_records);
        const record_layouts = try allocator.dupe(core.List, self.record_layouts.items);
        errdefer allocator.free(record_layouts);
        const field_names = try allocator.dupe(u32, self.field_names.items);
        errdefer allocator.free(field_names);
        const demands = try allocator.dupe(Demand, self.demands.items);
        errdefer allocator.free(demands);
        return .{ .values = values, .children = children, .closures = closures, .value_evidence = value_evidence, .type_mappings = type_mappings, .row_mappings = row_mappings, .evidence = try self.evidence.copyOwned(allocator), .value_records = value_records, .record_layouts = record_layouts, .field_names = field_names, .demands = demands };
    }
    fn makeClosure(self: *Session, owner: usize, source: core.Id, metadata: ClosureValue, captures: []const ValueId) Error!ValueId {
        if (self.closures.items.len >= std.math.maxInt(u32)) return self.failNode(owner, source, .constant_fuel);
        const index: u32 = @intCast(self.closures.items.len);
        try self.closures.ensureUnusedCapacity(self.allocator, 1);
        try self.demands.ensureUnusedCapacity(self.allocator, 1);
        const id = try self.makeAggregate(owner, source, .closure, 0, index, captures);
        self.closures.appendAssumeCapacity(metadata);
        self.demands.appendAssumeCapacity(.{});
        return id;
    }
    fn makeScalar(self: *Session, owner: usize, source: core.Id, value_: Value) Error!ValueId {
        if (value_.scalar == .unit) return 0;
        if (self.values.items.len >= self.options.max_values or self.values.items.len >= std.math.maxInt(ValueId)) return self.failNode(owner, source, .constant_fuel);
        const id: ValueId = @intCast(self.values.items.len);
        try self.values.ensureUnusedCapacity(self.allocator, 1);
        try self.value_evidence.ensureUnusedCapacity(self.allocator, 1);
        try self.value_records.ensureUnusedCapacity(self.allocator, 1);
        self.values.appendAssumeCapacity(.{ .scalar = value_.scalar, .bits = value_.bits });
        self.value_evidence.appendAssumeCapacity(switch (value_.scalar) {
            .unit => types.unit,
            .bool => types.boolean,
            .u32 => types.u32_type,
            .f32 => types.f32_type,
            else => 0,
        });
        self.value_records.appendAssumeCapacity(0);
        return id;
    }
    fn makeAggregate(self: *Session, owner: usize, source: core.Id, kind: ValueKind, nominal: u64, tag: u32, children_: []const ValueId) Error!ValueId {
        if (self.values.items.len >= self.options.max_values or self.values.items.len >= std.math.maxInt(ValueId) or children_.len > self.options.max_children -| self.children.items.len or children_.len > std.math.maxInt(u32) - self.children.items.len) return self.failNode(owner, source, .constant_fuel);
        // Both allocations precede mutation, so failed growth leaves every
        // published handle and child span valid.
        try self.values.ensureUnusedCapacity(self.allocator, 1);
        try self.value_evidence.ensureUnusedCapacity(self.allocator, 1);
        try self.value_records.ensureUnusedCapacity(self.allocator, 1);
        try self.children.ensureUnusedCapacity(self.allocator, children_.len);
        const id: ValueId = @intCast(self.values.items.len);
        const start: u32 = @intCast(self.children.items.len);
        self.children.appendSliceAssumeCapacity(children_);
        self.values.appendAssumeCapacity(.{ .kind = kind, .nominal = nominal, .bits = tag, .start = start, .len = @intCast(children_.len) });
        self.value_evidence.appendAssumeCapacity(0);
        self.value_records.appendAssumeCapacity(0);
        return id;
    }
    fn copyAggregate(self: *Session, owner: usize, source: core.Id, original: ValueId, field: u32, replacement: ValueId) Error!ValueId {
        const info = self.valueInfo(original);
        if (field >= info.len) return self.failNode(owner, source, .unsupported);
        if (self.values.items.len >= self.options.max_values or self.values.items.len >= std.math.maxInt(ValueId) or info.len > self.options.max_children -| self.children.items.len or info.len > std.math.maxInt(u32) - self.children.items.len) return self.failNode(owner, source, .constant_fuel);
        try self.values.ensureUnusedCapacity(self.allocator, 1);
        try self.value_evidence.ensureUnusedCapacity(self.allocator, 1);
        try self.value_records.ensureUnusedCapacity(self.allocator, 1);
        try self.children.ensureUnusedCapacity(self.allocator, info.len);
        const id: ValueId = @intCast(self.values.items.len);
        const start: u32 = @intCast(self.children.items.len);
        // Reacquire the source after growth. Its span ends before the appended
        // destination, so one contiguous copy needs no second scratch buffer.
        self.children.appendSliceAssumeCapacity(self.valueChildren(original));
        self.children.items[start + field] = replacement;
        self.values.appendAssumeCapacity(.{ .kind = info.kind, .nominal = info.nominal, .bits = info.bits, .start = start, .len = info.len });
        self.value_evidence.appendAssumeCapacity(self.valueEvidence(original));
        self.value_records.appendAssumeCapacity(self.value_records.items[original]);
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
    fn projectType(self: *Session, owner: usize, source: core.Id, ty: types.Id, mappings: []const type_evidence.Mapping, rows: []const type_evidence.RowMapping) Error!type_evidence.Id {
        return self.evidence.projectWithRows(&self.units[owner].types, ty, mappings, rows) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnresolvedType => return 0,
            error.EvidenceLimit => return self.failNode(owner, source, .constant_fuel),
            error.TypeMismatch => return self.failNode(owner, source, .unsupported),
        };
    }
    fn matchType(self: *Session, owner: usize, source: core.Id, producer: usize, ty: types.Id, actual: type_evidence.Id, mappings: *std.ArrayList(type_evidence.Mapping), rows: *std.ArrayList(type_evidence.RowMapping)) Error!bool {
        if (actual == 0) return false;
        return self.evidence.matchWithRows(&self.units[producer].types, ty, actual, mappings, rows) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.EvidenceLimit => return self.failNode(owner, source, .constant_fuel),
            error.UnresolvedType, error.TypeMismatch => return self.failNode(owner, source, .unsupported),
        };
    }
    fn matchCovariantType(self: *Session, owner: usize, source: core.Id, producer: usize, ty: types.Id, actual: type_evidence.Id, mappings: *std.ArrayList(type_evidence.Mapping), rows: *std.ArrayList(type_evidence.RowMapping)) Error!bool {
        if (try self.matchType(owner, source, producer, ty, actual, mappings, rows)) return true;
        var region = ClosureRegion.init(self) catch return error.OutOfMemory;
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
        const key: ViewKey = .{ .value = value_, .evidence = actual };
        if (self.typed_views.get(key)) |existing| {
            if (self.receipt_tape) |tape| try tape.views.append(self.allocator, .{ .value = value_, .evidence = actual, .selected = existing, .existed = true });
            return existing;
        }
        if (self.values.items.len >= self.options.max_values or self.values.items.len >= std.math.maxInt(ValueId)) return self.failNode(owner, source, .constant_fuel);
        var info = self.valueInfo(value_);
        var provider_child: ?ValueId = null;
        if (info.kind == .provider) {
            const provider_type = self.evidence.node(actual);
            if (provider_type.tag != .provider or info.nominal == 0 or info.len != 1) return self.failNode(owner, source, .invalid_provider);
            const operation = self.evidence.node(@intCast(info.nominal));
            if (operation.tag != .function) return self.failNode(owner, source, .invalid_provider);
            const implementation_type = self.evidence.internWithEffects(.function, operation.a, operation.b, provider_type.c, &.{}) catch |err| switch (err) {
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
            info.start = @intCast(self.children.items.len);
        }
        if (self.values.items.len >= self.options.max_values or self.values.items.len >= std.math.maxInt(ValueId)) return self.failNode(owner, source, .constant_fuel);
        if (provider_child != null and (self.children.items.len >= self.options.max_children or self.children.items.len >= std.math.maxInt(u32))) return self.failNode(owner, source, .constant_fuel);
        try self.values.ensureUnusedCapacity(self.allocator, 1);
        try self.value_evidence.ensureUnusedCapacity(self.allocator, 1);
        try self.value_records.ensureUnusedCapacity(self.allocator, 1);
        try self.typed_views.ensureUnusedCapacity(self.allocator, 1);
        if (provider_child != null) try self.children.ensureUnusedCapacity(self.allocator, 1);
        if (provider_child) |child| self.children.appendAssumeCapacity(child);
        const id: ValueId = @intCast(self.values.items.len);
        if (self.receipt_tape) |tape| try tape.views.append(self.allocator, .{ .value = value_, .evidence = actual, .selected = id, .existed = false });
        self.values.appendAssumeCapacity(info);
        self.value_evidence.appendAssumeCapacity(actual);
        self.value_records.appendAssumeCapacity(self.value_records.items[value_]);
        self.typed_views.putAssumeCapacity(key, id);
        return id;
    }
    fn captureMappings(self: *Session, owner: usize, source: core.Id, mappings: []const type_evidence.Mapping) Error!core.List {
        if (mappings.len > std.math.maxInt(u32) - self.type_mappings.items.len) return self.failNode(owner, source, .constant_fuel);
        const start: u32 = @intCast(self.type_mappings.items.len);
        try self.type_mappings.appendSlice(self.allocator, mappings);
        return .{ .start = start, .len = @intCast(mappings.len) };
    }
    fn captureRowMappings(self: *Session, owner: usize, source: core.Id, mappings: []const type_evidence.RowMapping) Error!core.List {
        if (mappings.len > std.math.maxInt(u32) - self.row_mappings.items.len) return self.failNode(owner, source, .constant_fuel);
        const start: u32 = @intCast(self.row_mappings.items.len);
        try self.row_mappings.appendSlice(self.allocator, mappings);
        return .{ .start = start, .len = @intCast(mappings.len) };
    }
    fn unitId(self: *const Session, index: usize) u32 {
        return if (self.units[index].unit != 0) self.units[index].unit else @intCast(index + 1);
    }
    fn fail(self: *Session, owner: usize, span: core.Span, code: Code) Error {
        if (self.diagnostic == null) self.diagnostic = .{ .unit = if (owner < self.units.len) self.unitId(owner) else 0, .span = span, .code = code };
        return error.Declined;
    }
    fn failNode(self: *Session, owner: usize, id: core.Id, code: Code) Error {
        return self.fail(owner, self.units[owner].span(id), code);
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

    pub fn prepare(self: *Session, reference: core.BindingRef) Error!void {
        return self.prepareWork(.{ .binding = try self.target(null, reference) });
    }
    fn prepareWork(self: *Session, initial: Work) Error!void {
        if (self.diagnostic != null) return error.Declined;
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
                    .constant, .primitive_function, .panic => {},
                    .suspend_ => if (self.options.trace_runtime_dependencies) {
                        // Source selection retains named declarations inside a
                        // waiting demand, without forcing its expression/value.
                        try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = module.suspension(operation.id).body } });
                    },
                    .reference => try work.append(self.allocator, .{ .binding = try self.target(operation.unit, module.reference(operation.id)) }),
                    .scalar, .logical, .associated, .record_merge, .type_same, .effect_provider, .handle => {
                        if (n.b != 0) try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.b } });
                        try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.a } });
                    },
                    .call, .block, .suite, .product, .record, .array, .array_op => {
                        const children = module.children(operation.id);
                        var index = children.len;
                        while (index != 0) {
                            index -= 1;
                            try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = children[index] } });
                        }
                        if (n.tag == .call) try work.append(self.allocator, .{ .binding = try self.target(operation.unit, module.call(operation.id).target) });
                    },
                    .if_value, .if_stmt, .state_provider => {
                        if (n.c != 0) try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.c } });
                        try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.b } });
                        try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.a } });
                    },
                    .bind => try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.b } }),
                    .return_, .result_associated, .force => try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.a } }),
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
                    .computation => try work.append(self.allocator, .{ .node = .{ .unit = operation.unit, .id = n.a } }),
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
    fn constant(self: *Session, raw: Target) Error!ValueId {
        const timing = if (self.timing) |work| work.enter(.evaluation) else null;
        defer if (timing) |scope| scope.deinit();
        if (self.principal_reads) |reads| reads.invalidate(.evaluate);
        const resolved = try self.external(raw);
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
        const flow = try self.expression(resolved.unit, body.root, &frame);
        const result = switch (flow) {
            .value => |value_| value_,
            .returning, .breaking => return self.fail(resolved.unit, body.span, .unsupported),
        };
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
        self.slot(resolved).value = published;
        self.slot(resolved).state = .complete;
        return published;
    }
    fn principalEvidence(self: *Session, resolved: Target, body: *const core.Body, binding_type: types.Id) Error!?SolvedEvidence {
        const principal_target: core.BindingRef = .{ .unit = self.unitId(resolved.unit), .binding = resolved.binding };
        if (self.principal_provider) |provider| if (try provider.lookup(provider.context, principal_target, self.options)) |cached| {
            var solved = cached;
            errdefer solved.deinit(self.allocator);
            try provider.record(provider.context, principal_target, self.options, solved, null);
            return solved;
        };
        if (self.principal_provider != null) self.principal_regions += 1;
        var reads: principal_inputs.Recorder = .{ .eligible = self.validated_calls.count() == 0, .max_reads = self.options.max_values };
        defer reads.deinit(self.allocator);
        const previous_reads = self.principal_reads;
        const recording = self.retain_principal_inputs and self.principal_provider != null;
        if (recording) self.principal_reads = &reads;
        defer self.principal_reads = previous_reads;
        var region = ClosureRegion.init(self) catch return error.OutOfMemory;
        defer region.deinit();
        defer region.profile_rejected = reads.rejected;
        region.profile_principal = true;
        region.profile_input_calls = self.validated_calls.count();
        var solved = region.bodyEvidenceMode(resolved.unit, body.root, binding_type, body.closed_rows, body.scheme, .{ .semantic = 0 }, &.{}, &.{}, true) catch |err| switch (err) {
            // Partial source results preserve unresolved facts; ordinary fresh
            // evaluation still owns value-dependent obligations and diagnostics.
            error.UnresolvedType => return null,
            else => return self.evidenceFailure(resolved.unit, body.span, err),
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
        return self.evidence.effects.internOperation(operation.identity, arguments.items) catch |err| return self.evidenceFailure(owner, self.units[owner].span(id), err);
    }
    fn containsReflectionType(self: *Session, owner: usize, id: core.Id, evidence: type_evidence.Id, depth: usize) Error!bool {
        if (evidence == 0) return false;
        if (depth >= 1024) return self.failNode(owner, id, .ambiguous_state);
        const n = self.evidence.node(evidence);
        switch (n.tag) {
            .nominal => {
                if (types.isReflectionIdentity(n.a, n.b)) return true;
                for (self.evidence.children(evidence)) |child| if (try self.containsReflectionType(owner, id, child, depth + 1)) return true;
            },
            .product => for (self.evidence.children(evidence)) |child| {
                if (try self.containsReflectionType(owner, id, child, depth + 1)) return true;
            },
            .record => {
                const fields = self.evidence.children(evidence);
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
            actual = try self.projectType(owner, 0, ty, self.type_mappings.items[closure.mappings.start..][0..closure.mappings.len], self.row_mappings.items[closure.row_mappings.start..][0..closure.row_mappings.len]);
        }
        for (0..1024) |_| {
            const node = self.evidence.node(actual);
            if (node.tag != .function) return actual;
            actual = node.b;
        } else return 0;
    }
    fn principalValueType(self: *Session, owner: usize, id: core.Id, value_: ValueId, frame: *const Frame) Error!type_evidence.Id {
        const module = &self.units[owner];
        const node = module.node(id);
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
    fn expressionInner(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        if (self.principal_reads) |reads| reads.invalidate(.evaluate);
        if (id == 0) return .{ .value = 0 };
        const module = &self.units[owner];
        if (id >= module.nodes.len) return self.fail(owner, .{ .start = 0, .end = 0 }, .unsupported);
        if (self.steps >= self.options.max_steps or self.depth >= self.options.max_depth) return self.failNode(owner, id, .constant_fuel);
        self.steps += 1;
        self.depth += 1;
        defer self.depth -= 1;
        const n = module.node(id);
        if (self.indexed_region) |region| if (region.owner == owner and region.frame == frame) {
            for (region.plan.edits[0..region.plan.edit_count]) |edit| if (edit.update == id) return self.indexedEdit(region, edit);
        };
        switch (n.tag) {
            .constant => {
                const scalar = if (n.ty < module.types.nodes.len) switch (module.types.node(n.ty).tag) {
                    .unit => @as(@TypeOf(unit_value.scalar), .unit),
                    .u32 => .u32,
                    .f32 => .f32,
                    .boolean => .bool,
                    else => return self.failNode(owner, id, .unsupported),
                } else return self.failNode(owner, id, .unsupported);
                return .{ .value = try self.makeScalar(owner, id, .{ .scalar = scalar, .bits = n.a }) };
            },
            .reference => {
                const resolved = try self.external(try self.target(owner, module.reference(id)));
                const binding = self.units[resolved.unit].binding(resolved.binding);
                if (binding.kind == .local or binding.kind == .parameter) {
                    if (resolved.unit != owner) return self.failNode(owner, id, .unsupported);
                    return .{ .value = frame.values.get(resolved.binding) orelse return self.failNode(owner, id, .unsupported) };
                }
                return .{ .value = try self.constant(resolved) };
            },
            .product, .record, .array => return self.aggregate(owner, id, frame),
            .record_merge => return self.recordMerge(owner, id, frame),
            .array_op => return self.arrayOperation(owner, id, frame),
            .closure => {
                const bindings = module.closureCaptures(id);
                var storage_buffer: [256]u8 align(@alignOf(usize)) = undefined;
                var storage: std.heap.BufferFirstAllocator = .init(&storage_buffer, self.allocator);
                const scratch = storage.allocator();
                const captures = try scratch.alloc(ValueId, bindings.len);
                defer scratch.free(captures);
                for (bindings, 0..) |binding, index| captures[index] = frame.values.get(binding) orelse return self.failNode(owner, id, .unsupported);
                return .{ .value = try self.makeClosure(owner, id, .{ .origin = .anonymous, .unit = self.unitId(owner), .identity = n.a, .mappings = try self.captureMappings(owner, id, frame.mappings.items), .row_mappings = try self.captureRowMappings(owner, id, frame.row_mappings.items) }, captures) };
            },
            .suspend_ => {
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
                if (producer != null) try self.source_suspensions.ensureUnusedCapacity(self.allocator, 1);
                const demand = try self.makeClosure(owner, id, .{ .origin = .anonymous, .unit = self.unitId(owner), .identity = n.a, .mappings = try self.captureMappings(owner, id, frame.mappings.items), .row_mappings = try self.captureRowMappings(owner, id, frame.row_mappings.items) }, captures);
                self.values.items[demand].kind = .suspension;
                self.values.items[demand].nominal = self.values.items[demand].bits;
                if (producer) |target_| self.source_suspensions.appendAssumeCapacity(.{ .producer = .{ .unit = self.unitId(target_.unit), .binding = target_.binding }, .unit = self.unitId(owner), .node = id, .value = demand });
                return .{ .value = demand };
            },
            .force => {
                const operand = try self.expression(owner, n.a, frame);
                if (operand != .value) return operand;
                return self.forceValue(owner, id, operand.value, frame.providers);
            },
            .type_constructor => {
                const actual = try self.projectType(owner, id, n.ty, frame.mappings.items, frame.row_mappings.items);
                if (actual == 0) return self.failNode(owner, id, .type_constructor_required);
                const token = self.evidence.node(actual);
                if (token.tag != .type_constructor) return self.failNode(owner, id, .type_constructor_required);
                return .{ .value = try self.makeAggregate(owner, id, .type_constructor, (@as(u64, token.a) << 32) | token.b, 0, &.{}) };
            },
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
            .effect_reflection => {
                const kind: checked_types.ReflectionKind = @fromBackingInt(@intCast(n.a));
                if (kind == .of or kind == .descriptor) {
                    const identity = if (kind == .of) types.effect_set_identity else types.effect_descriptor_identity;
                    const evidence = self.evidence.intern(.nominal, identity.unit, identity.decl, &.{}) catch |err| return self.evidenceFailure(owner, module.span(id), err);
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
                        break :blk self.evidence.effects.internRow(labels.items[0..kept]) catch |err| return self.evidenceFailure(owner, module.span(id), err);
                    } else try self.reflectionLabel(owner, id, n.b, frame);
                    const result = try self.makeAggregate(owner, id, if (kind == .of) .effect_set else .effect_descriptor, 0, bits, &.{});
                    self.value_evidence.items[result] = evidence;
                    return .{ .value = result };
                }
                const left = try self.expression(owner, n.b, frame);
                if (left != .value) return left;
                const first = self.valueInfo(left.value);
                if (kind == .count) {
                    if (first.kind != .effect_set) return self.failNode(owner, id, .type_mismatch);
                    const labels = self.evidence.effects.view().rowLabels(first.bits);
                    return .{ .value = try self.makeScalar(owner, id, .{ .scalar = .u32, .bits = @intCast(labels.len) }) };
                }
                const right = try self.expression(owner, n.c, frame);
                if (right != .value) return right;
                const second = self.valueInfo(right.value);
                if (second.kind != .effect_descriptor) return self.failNode(owner, id, .type_mismatch);
                const matches = if (kind == .has) blk: {
                    if (first.kind != .effect_set) return self.failNode(owner, id, .type_mismatch);
                    break :blk std.mem.findScalar(u32, self.evidence.effects.view().rowLabels(first.bits), second.bits) != null;
                } else blk: {
                    if (first.kind != .effect_descriptor) return self.failNode(owner, id, .type_mismatch);
                    break :blk first.bits == second.bits;
                };
                return .{ .value = try self.makeScalar(owner, id, .{ .scalar = .bool, .bits = @intFromBool(matches) }) };
            },
            .operation_value => {
                const operation = module.operationValue(id);
                if (operation.witness != 0) {
                    const witness = module.node(operation.witness);
                    if (witness.tag != .reference) return self.failNode(owner, id, .unsupported);
                    const reference = module.reference(operation.witness);
                    const value_ = frame.values.get(reference.binding) orelse return self.failNode(owner, id, .unsupported);
                    const head = try self.witnessHead(value_);
                    if (try self.containsReflectionType(owner, id, head, 0)) return self.failNode(owner, id, .ambiguous_state);
                    if (head == 0 or !try self.matchType(owner, id, owner, operation.witness_result, head, &frame.mappings, &frame.row_mappings)) return self.failNode(owner, id, .unsupported);
                }
                return .{ .value = try self.makeClosure(owner, id, .{ .origin = .operation, .unit = self.unitId(owner), .identity = n.a, .ty = n.ty, .mappings = try self.captureMappings(owner, id, frame.mappings.items), .row_mappings = try self.captureRowMappings(owner, id, frame.row_mappings.items) }, &.{}) };
            },
            .effect_provider => {
                const operation = try self.expression(owner, n.a, frame);
                if (operation != .value) return operation;
                const implementation = try self.expression(owner, n.b, frame);
                if (implementation != .value) return implementation;
                const token = try self.operationToken(owner, id, operation.value);
                if (self.valueInfo(implementation.value).kind != .closure) return self.failNode(owner, id, .invalid_provider);
                const signature = self.valueEvidence(operation.value);
                if (signature == 0 or self.evidence.node(signature).tag != .function) return self.failNode(owner, id, .invalid_provider);
                return .{ .value = try self.makeAggregate(owner, id, .provider, signature, token, &.{implementation.value}) };
            },
            .state_provider => {
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
            },
            .handle => return self.handle(owner, id, frame),
            .panic => {
                if (self.diagnostic == null) self.diagnostic = .{ .unit = self.unitId(owner), .span = module.span(id), .code = .const_panic, .detail = module.panicMessage(id) };
                return error.Declined;
            },
            .apply => {
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
            },
            .associated => return self.dispatch(owner, id, frame),
            .result_associated => return self.resultDispatch(owner, id, frame),
            .type_same => {
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
                while (self.evidence.node(left_type).tag == .function) left_type = self.evidence.node(left_type).b;
                while (self.evidence.node(right_type).tag == .function) right_type = self.evidence.node(right_type).b;
                for ([_]type_evidence.Id{ left_type, right_type }) |selected| if (try self.containsReflectionType(owner, id, selected, 0)) return self.failNode(owner, id, .ambiguous_state);
                return .{ .value = try self.makeScalar(owner, id, .{ .scalar = .bool, .bits = @intFromBool(left_type == right_type) }) };
            },
            .construct => {
                const constructor = module.constructor(n.a);
                const nominal = module.nominal(constructor.nominal);
                const family = self.nominalIdentity(owner, nominal.identity.unit, nominal.identity.decl);
                if (n.b == 0) return .{ .value = try self.makeAggregate(owner, id, .nominal, family, constructor.tag, &.{}) };
                const payload = try self.expression(owner, n.b, frame);
                if (payload != .value) return payload;
                const stored = if (n.c != 0) try self.recordArgument(owner, owner, id, n.a, payload.value) else payload.value;
                return .{ .value = try self.makeAggregate(owner, id, .nominal, family, constructor.tag, &.{stored}) };
            },
            .project => {
                const operand = try self.expression(owner, n.a, frame);
                if (operand != .value) return operand;
                return self.memberValue(owner, id, n.b, operand.value, frame);
            },
            .match => return self.match(owner, id, frame),
            .pattern_bind => {
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
            },
            .update => return self.update(owner, id, frame),
            .scalar => {
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
            },
            .logical => {
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
            },
            .call => return self.call(owner, id, frame),
            .if_value, .if_stmt => {
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
            },
            .block, .suite => {
                for (module.children(id)) |child| {
                    const outcome = try self.expression(owner, child, frame);
                    if (outcome != .value) {
                        if (n.tag == .block and outcome == .returning and outcome.returning.target == id) return .{ .value = outcome.returning.value };
                        return outcome;
                    }
                }
                return .{ .value = 0 };
            },
            .bind => {
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
            },
            .return_ => {
                const outcome = try self.expression(owner, n.a, frame);
                return switch (outcome) {
                    .value => |value_| .{ .returning = .{ .target = n.b, .value = value_ } },
                    .returning, .breaking => outcome,
                };
            },
            .loop => return self.loop(owner, id, frame),
            .break_ => return self.breakFlow(owner, id, frame),
            .invalid => return self.failNode(owner, id, .unsupported),
        }
    }
    fn nominalIdentity(self: *const Session, owner: usize, unit: u32, declaration: u32) u64 {
        return (@as(u64, if (unit == 0) self.unitId(owner) else unit) << 32) | declaration;
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
        const kind: ValueKind = if (n.tag == .record) .record else if (n.tag == .array) (if (module.types.node(n.ty).tag == .list) .list else .array) else .product;
        const record_layout = if (kind == .record) try self.recordLayout(owner, id, n.ty) else 0;
        const result = try self.makeAggregate(owner, id, kind, 0, 0, values);
        self.value_records.items[result] = record_layout;
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
        self.value_records.items[value_] = shape;
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
        if (closed) self.value_evidence.items[value_] = self.evidence.intern(.record, 0, 0, words) catch |err| return self.evidenceFailure(owner, self.units[owner].span(source), err);
        return .{ .value = value_ };
    }
    fn internRecordLayout(self: *Session, owner: usize, source: core.Id, names: []const u32) Error!u32 {
        if (names.len == 0) return 0;
        if (self.record_shapes.getAdapted(names, RecordNames.Adapter{ .words = self.field_names.items })) |existing| return existing;
        if (names.len > std.math.maxInt(u32) - self.field_names.items.len or self.record_layouts.items.len >= std.math.maxInt(u32)) return self.failNode(owner, source, .constant_fuel);
        try self.record_layouts.ensureUnusedCapacity(self.allocator, 1);
        try self.field_names.ensureUnusedCapacity(self.allocator, names.len);
        try self.record_shapes.ensureUnusedCapacityContext(self.allocator, 1, .{ .words = self.field_names.items });
        const shape: u32 = @intCast(self.record_layouts.items.len);
        const span: core.List = .{ .start = @intCast(self.field_names.items.len), .len = @intCast(names.len) };
        self.field_names.appendSliceAssumeCapacity(names);
        self.record_layouts.appendAssumeCapacity(span);
        self.record_shapes.putAssumeCapacityContext(span, shape, .{ .words = self.field_names.items });
        return shape;
    }
    fn recordLayout(self: *Session, owner: usize, source: core.Id, ty: types.Id) Error!u32 {
        const key: RecordKey = .{ .unit = owner, .ty = ty };
        if (self.record_types.get(key)) |existing| return existing;
        const module = &self.units[owner];
        const record = module.types.node(ty);
        if (record.tag != .record) return self.failNode(owner, source, .unsupported);
        var buffer: [256]u8 align(@alignOf(u32)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&buffer, self.allocator);
        const names = try scratch.allocator().alloc(u32, record.b);
        defer scratch.allocator().free(names);
        for (names, 0..) |*name, index| name.* = module.types.recordField(record, index).name;
        const shape = try self.internRecordLayout(owner, source, names);
        try self.record_types.put(self.allocator, key, shape);
        return shape;
    }
    fn filledArray(self: *Session, owner: usize, source: core.Id, count: u32, value_: ValueId, kind: ValueKind) Error!ValueId {
        if (count >= 4_194_304) return self.arrayLengthFailure(owner);
        try self.chargeCells(owner, source, count);
        if (self.values.items.len >= self.options.max_values or self.values.items.len >= std.math.maxInt(ValueId) or count > self.options.max_children -| self.children.items.len or count > std.math.maxInt(u32) - self.children.items.len) return self.failNode(owner, source, .constant_fuel);
        try self.values.ensureUnusedCapacity(self.allocator, 1);
        try self.value_evidence.ensureUnusedCapacity(self.allocator, 1);
        try self.value_records.ensureUnusedCapacity(self.allocator, 1);
        try self.children.ensureUnusedCapacity(self.allocator, count);
        const id: ValueId = @intCast(self.values.items.len);
        const start: u32 = @intCast(self.children.items.len);
        self.children.items.len += count;
        @memset(self.children.items[start..], value_);
        self.values.appendAssumeCapacity(.{ .kind = kind, .start = start, .len = count });
        self.value_evidence.appendAssumeCapacity(0);
        self.value_records.appendAssumeCapacity(0);
        return id;
    }
    fn arrayOperation(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const operation = module.arrayOperation(id);
        const arguments = module.children(id);
        const arity = @import("collection_ops.zig").arity(operation);
        if (arguments.len != arity) return self.failNode(owner, id, .unsupported);
        var values: [3]ValueId = undefined;
        for (arguments, 0..) |argument, index| {
            const outcome = try self.expression(owner, argument, frame);
            if (outcome != .value) return outcome;
            values[index] = outcome.value;
        }
        return .{ .value = try self.arrayValues(owner, id, operation, values[0..arity], frame.providers) };
    }
    fn extendCollection(self: *Session, owner: usize, source: core.Id, original: ValueId, value_: ValueId, front: bool) Error!ValueId {
        const before = self.valueInfo(original);
        if (before.len >= 4_194_303) return self.arrayLengthFailure(owner);
        if (self.values.items.len >= self.options.max_values or self.values.items.len >= std.math.maxInt(ValueId)) return self.failNode(owner, source, .constant_fuel);
        try self.values.ensureUnusedCapacity(self.allocator, 1);
        try self.value_evidence.ensureUnusedCapacity(self.allocator, 1);
        try self.value_records.ensureUnusedCapacity(self.allocator, 1);
        const span = self.collection_buffers.extend(self.allocator, &self.children, .{ .start = before.start, .len = before.len }, value_, front, self.options.max_children) catch |err| switch (err) {
            error.Limit => return self.failNode(owner, source, .constant_fuel),
            error.OutOfMemory => return error.OutOfMemory,
        };
        const id: ValueId = @intCast(self.values.items.len);
        self.values.appendAssumeCapacity(.{ .kind = before.kind, .start = span.start, .len = span.len });
        self.value_evidence.appendAssumeCapacity(0);
        self.value_records.appendAssumeCapacity(0);
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
            if (count.bits > self.options.max_children -| self.children.items.len) return self.failNode(owner, id, .constant_fuel);
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
        if (index.bits >= array.len) return self.failNode(owner, id, .array_bounds);
        if (operation == .get) return self.valueChildren(values[0])[index.bits];
        try self.chargeCells(owner, id, array.len);
        return self.copyAggregate(owner, id, values[0], index.bits, values[2]);
    }
    fn simdValue(self: *Session, owner: usize, id: core.Id, op: core.Op, left: ValueId, right: ValueId) Error!ValueId {
        if (self.valueInfo(left).len != 4 or (right != 0 and (self.valueInfo(right).kind != .product or self.valueInfo(right).len != 4))) return self.failNode(owner, id, .unsupported);
        const a: [4]ValueId = self.valueChildren(left)[0..4].*;
        const b: [4]ValueId = if (right == 0) @splat(0) else self.valueChildren(right)[0..4].*;
        var values: [4]ValueId = undefined;
        for (&values, a, b) |*result, first, second| {
            const lane = scalar_ops.evaluate(op, try self.requireScalar(owner, id, first), try self.requireScalar(owner, id, second)) catch return self.failNode(owner, id, .unsupported);
            result.* = try self.makeScalar(owner, id, lane);
        }
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
    /// Complete evidence is optional for an aggregate with unresolved empty
    /// children. Import its actual structure and the selected method signature
    /// into a private region; export only concrete substitutions. The generic
    /// source scheme and every existing value header remain immutable.
    fn partialArrayMember(self: *Session, owner: usize, source: core.Id, target_: Target, receiver: ValueId, expected: type_evidence.Id) Error!ValueId {
        var region = ClosureRegion.init(self) catch return error.OutOfMemory;
        defer region.deinit();
        return region.arrayMember(target_, receiver, expected) catch |err| return self.evidenceFailure(owner, self.units[owner].span(source), err);
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
        const actual = if (closed) self.evidence.intern(.record, 0, 0, words) catch |err| return self.evidenceFailure(owner, self.units[owner].span(source), err) else 0;
        const layout = try self.recordLayout(producer, 0, payload);
        const result = try self.makeAggregate(owner, source, .record, 0, 0, values);
        self.value_records.items[result] = layout;
        self.value_evidence.items[result] = actual;
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
        return self.evidence.intern(.product, 0, 0, fields) catch |err| return self.evidenceFailure(owner, self.units[owner].span(source), err);
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
        return .{ .breaking = .{ .target = module.node(id).a, .values = .{ .start = start, .len = @intCast(values.len) } } };
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
        self.indexed_region = &region;
        defer self.indexed_region = previous;
        const outcome = try self.loopIterations(owner, id, frame, first, begin, end);
        if (outcome != .value) return outcome;
        const result = if (begin >= end) original else try self.makeAggregate(owner, id, info.kind, info.nominal, info.bits, children);
        self.value_evidence.items[result] = self.valueEvidence(original);
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
                break;
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
        const n = self.evidence.node(actual);
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
                return .{ .unit = self.unitId(target_.unit), .binding = target_.binding };
            }
        }
        return null;
    }
    fn candidate(self: *Session, owner: usize, source: core.Id, identity: types.NominalIdentity, op: types.Operator, member: u32, left: type_evidence.Id, right: type_evidence.Id, expected: type_evidence.Id) Error!?Selection {
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
            if (expected != 0 and !try self.matchType(owner, source, resolved.unit, second.b, expected, &mappings, &row_mappings)) return self.failNode(owner, source, .type_mismatch);
            const result = try self.projectType(resolved.unit, body.root, second.b, mappings.items, row_mappings.items);
            if (result == 0) return self.failNode(owner, source, .unsupported);
            return .{ .target = resolved, .full_type = try self.projectType(resolved.unit, body.root, body.scheme.root, mappings.items, row_mappings.items), .result = result };
        }
        return null;
    }
    fn select(self: *Session, owner: usize, source: core.Id, op: types.Operator, member: u32, left: type_evidence.Id, right: type_evidence.Id, expected: type_evidence.Id) Error!Selection {
        const left_identity = self.evidenceIdentity(left);
        if (left_identity) |identity| if (try self.candidate(owner, source, identity, op, member, left, right, expected)) |chosen| return chosen;
        if (member == 0 and left != 0 and left == right) {
            const scalar = self.evidence.node(left).tag;
            const comparison = op == .equal or op == .not_equal or op == .less or op == .less_equal or op == .greater or op == .greater_equal;
            if (op != .none and (scalar == .u32 or scalar == .f32 or (scalar == .boolean and (op == .equal or op == .not_equal)))) {
                const result = if (comparison) types.boolean else left;
                if (expected != 0 and expected != result) return self.failNode(owner, source, .type_mismatch);
                return .{ .result = result };
            }
        }
        if (self.evidenceIdentity(right)) |identity| if (left_identity == null or !std.meta.eql(left_identity.?, identity)) {
            if (try self.candidate(owner, source, identity, op, member, left, right, expected)) |chosen| return chosen;
        };
        return self.failNode(owner, source, if (member == 0) .ambiguous_operator else .missing_associated);
    }
    fn dispatch(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const n = self.units[owner].node(id);
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
        if (expected == 0) return self.failNode(owner, source, .ambiguous_associated);
        const identity = self.evidenceIdentity(expected) orelse return self.failNode(owner, source, .missing_associated);
        if (try self.associatedTarget(self.unitId(owner), identity, member, .none)) |method| {
            const target_ = try self.target(null, method);
            const module = &self.units[target_.unit];
            const body = module.body(target_.binding) orelse return self.failNode(owner, source, .unsupported);
            const arrow = module.types.node(body.scheme.root);
            if (arrow.tag != .function) return self.failNode(owner, source, .type_mismatch);
            var mappings: std.ArrayList(type_evidence.Mapping) = .empty;
            var row_mappings: std.ArrayList(type_evidence.RowMapping) = .empty;
            defer row_mappings.deinit(self.allocator);
            defer mappings.deinit(self.allocator);
            if (!try self.matchType(owner, source, target_.unit, arrow.a, input, &mappings, &row_mappings) or !try self.matchType(owner, source, target_.unit, arrow.b, expected, &mappings, &row_mappings)) return self.failNode(owner, source, .type_mismatch);
            return .{ .target = target_, .full_type = try self.projectType(target_.unit, body.root, body.scheme.root, mappings.items, row_mappings.items), .result = expected };
        }
        return self.failNode(owner, source, .missing_associated);
    }
    fn resultDispatch(self: *Session, owner: usize, id: core.Id, frame: *Frame) Error!Flow {
        const module = &self.units[owner];
        const n = module.node(id);
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
        for (self.units[owner].obligations[scheme.obligations.start..][0..scheme.obligations.len]) |obligation| if (obligation.explicit) return true;
        return false;
    }
    fn validateScheme(self: *Session, owner: usize, source: core.Id, scheme: types.Scheme, frame: *Frame, allow_remaining: bool) Error!void {
        if (!self.hasExplicitScheme(owner, scheme)) return;
        var region = ClosureRegion.init(self) catch return error.OutOfMemory;
        defer region.deinit();
        const scope = region.typeScope(owner) catch |err| return self.evidenceFailure(owner, self.units[owner].span(source), err);
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
            if (obligation.kind == .type_head) {
                var actual = try self.projectType(owner, body.root, obligation.ty, frame.mappings.items, frame.row_mappings.items);
                if (actual == 0) continue;
                for (0..1024) |_| {
                    const head = self.evidence.node(actual);
                    if (head.tag != .function) break;
                    actual = head.b;
                } else return self.fail(owner, obligation.span, .backend_limit);
                if (!try self.matchType(owner, body.root, owner, obligation.result, actual, &frame.mappings, &frame.row_mappings)) return self.fail(owner, obligation.span, .type_mismatch);
                continue;
            }
            if (obligation.kind == .monad_factory) {
                const input = try self.projectType(owner, body.root, obligation.ty, frame.mappings.items, frame.row_mappings.items);
                if (input != 0 and self.evidence.node(input).tag != .type_constructor) return self.fail(owner, obligation.span, .type_constructor_required);
                continue;
            }
            if (obligation.kind == .resolver_dispatch) {
                const actual = try self.projectType(owner, body.root, obligation.ty, frame.mappings.items, frame.row_mappings.items);
                if (actual == 0) continue;
                const provider = self.evidence.node(actual);
                if (provider.tag != .resolver) return self.fail(owner, obligation.span, .invalid_provider);
                const token = self.evidence.node(provider.a);
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
                const provider = self.evidence.node(actual);
                if (provider.tag != .resolver) return self.fail(owner, obligation.span, .invalid_provider);
                const token = self.evidence.node(provider.a);
                const output = self.evidence.node(result);
                if (output.tag != .never and (output.tag != .nominal or output.a != token.a or output.b != token.b)) return self.fail(owner, obligation.span, .type_mismatch);
                continue;
            }
            if (obligation.kind == .result_dispatch) {
                const input = try self.projectType(owner, body.root, obligation.ty, frame.mappings.items, frame.row_mappings.items);
                const expected = try self.projectType(owner, body.root, obligation.result, frame.mappings.items, frame.row_mappings.items);
                if (input != 0 and expected != 0) _ = try self.resultSelection(owner, body.root, obligation.name, input, expected);
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
        if (!body.is_function or arguments.len != parameters.len) return self.failNode(owner, source, .unsupported);
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
        const outcome = try self.expression(resolved.unit, body.root, &callee);
        if (outcome != .value) return self.fail(resolved.unit, body.span, .unsupported);
        return outcome;
    }
    fn applyValue(self: *Session, owner: usize, source: core.Id, function: ValueId, argument: ValueId, head: provider_chain.Head) Error!Flow {
        const actual = self.valueEvidence(function);
        const outcome = try self.applyValueInner(owner, source, function, argument, head);
        if (outcome == .value and actual != 0) {
            const full = self.evidence.node(actual);
            if (full.tag != .function) return self.failNode(owner, source, .unsupported);
            return .{ .value = try self.typedView(owner, source, outcome.value, full.b) };
        }
        return outcome;
    }
    fn forceValue(self: *Session, owner: usize, source: core.Id, value_: ValueId, head: provider_chain.Head) Error!Flow {
        const info = self.valueInfo(value_);
        if (info.kind != .suspension) return self.failNode(owner, source, .unsupported);
        const slot_index: usize = @intCast(info.nominal);
        const actual = self.valueEvidence(value_);
        const result = if (actual != 0) blk: {
            const n = self.evidence.node(actual);
            if (n.tag != .demand) return self.failNode(owner, source, .unsupported);
            break :blk n.a;
        } else 0;
        if (self.demands.items[slot_index].state == .cached) return .{ .value = try self.typedView(owner, source, self.demands.items[slot_index].value, result) };
        if (self.demands.items[slot_index].state == .evaluating) return self.failNode(owner, source, .cycle);
        self.demands.items[slot_index].state = .evaluating;
        errdefer self.demands.items[slot_index].state = .pending;
        const metadata = self.suspensionInfo(value_);
        const producer = self.findUnit(metadata.unit, null) orelse return self.failNode(owner, source, .unsupported);
        const template = self.units[producer].closures[metadata.identity];
        try self.prepareWork(.{ .node = .{ .unit = producer, .id = template.body } });
        // An ordinary internal thunk header shares numeric code/capture identity;
        // the source demand keeps its independent semantic tag and memo slot.
        const captures = try self.allocator.dupe(ValueId, self.valueChildren(value_));
        defer self.allocator.free(captures);
        const function = try self.makeClosure(owner, source, metadata, captures);
        const expected = if (result != 0) self.evidence.internWithEffects(.function, types.unit, result, self.evidence.node(actual).c, &.{}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return self.failNode(owner, source, .unsupported),
        } else 0;
        const typed = try self.typedView(owner, source, function, expected);
        const outcome = try self.applyValue(owner, source, typed, 0, head);
        if (outcome != .value) return self.failNode(owner, source, .unsupported);
        self.demands.items[slot_index] = .{ .state = .cached, .value = outcome.value };
        return outcome;
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
        try mappings.appendSlice(self.allocator, self.type_mappings.items[closure.mappings.start..][0..closure.mappings.len]);
        try rows.appendSlice(self.allocator, self.row_mappings.items[closure.row_mappings.start..][0..closure.row_mappings.len]);
        const actual = self.valueEvidence(function);
        if (actual != 0) {
            const selected = self.evidence.node(actual);
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
        return self.evidence.effects.internOperation(identity, arguments.items) catch |err| switch (err) {
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
        const mappings = self.type_mappings.items[closure.mappings.start..][0..closure.mappings.len];
        const rows = self.row_mappings.items[closure.row_mappings.start..][0..closure.row_mappings.len];
        const parameter = try self.projectType(producer, source, signature.a, mappings, rows);
        const result = try self.projectType(producer, source, signature.b, mappings, rows);
        if (parameter == 0 or result == 0) return 0;
        const row = self.evidence.effects.internRow(&.{token}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return self.failNode(owner, source, .constant_fuel),
        };
        return self.evidence.internWithEffects(.function, parameter, result, row, &.{}) catch |err| switch (err) {
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
        const actual = if (argument_type != 0 and state_type != 0) self.evidence.intern(.product, 0, 0, &.{ argument_type, state_type }) catch |err| return self.evidenceFailure(owner, self.units[owner].span(id), err) else 0;
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
            const label = try self.reflectionLabel(owner, id, arm.operation, frame);
            if (self.request_handlers.items.len >= std.math.maxInt(u32)) return self.failNode(owner, id, .constant_fuel);
            const handler: u32 = @intCast(self.request_handlers.items.len);
            try self.request_handlers.append(self.allocator, .{ .callback = callback.value, .cell = cell, .outer = frame.providers });
            head = self.providers.installRequest(self.evidence.effects.view(), head, label, handler) catch |err| return self.providerFailure(owner, id, err);
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
            .provider => frame.providers = self.providers.installProvider(self.evidence.effects.view(), outer, self.providerInfo(value_)) catch |err| return self.providerFailure(owner, id, err),
            .state_provider => {
                const installation = self.providers.installState(self.evidence.effects.view(), outer, self.stateProviderInfo(value_)) catch |err| return self.providerFailure(owner, id, err);
                frame.providers = installation.head;
                cell = installation.cell;
            },
            else => return self.failNode(owner, id, .invalid_provider),
        }
        const body = try self.expression(owner, node.b, frame);
        if (body != .value or cell == 0) return body;
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
        if (self.valueInfo(function).kind != .closure) return self.failNode(owner, source, .unsupported);
        const closure = self.closureInfo(function);
        const producer = self.findUnit(closure.unit, null) orelse return self.failNode(owner, source, .unsupported);
        const module = &self.units[producer];
        switch (closure.origin) {
            .operation => {
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
                const stored = if (module.types.node(constructor.payload).tag == .record) try self.recordArgument(producer, owner, source, closure.identity, argument) else argument;
                return .{ .value = try self.makeAggregate(owner, source, .nominal, self.nominalIdentity(producer, nominal.identity.unit, nominal.identity.decl), constructor.tag, &.{stored}) };
            },
            .anonymous => {
                const template = module.closures[closure.identity];
                const bindings = module.extra[template.captures.start..][0..template.captures.len];
                if (bindings.len != self.valueInfo(function).len or closure.applied != 0) return self.failNode(owner, source, .unsupported);
                var callee: Frame = .{ .providers = head };
                defer callee.deinit(self.allocator);
                try callee.mappings.appendSlice(self.allocator, self.type_mappings.items[closure.mappings.start..][0..closure.mappings.len]);
                try callee.row_mappings.appendSlice(self.allocator, self.row_mappings.items[closure.row_mappings.start..][0..closure.row_mappings.len]);
                const actual = self.valueEvidence(function);
                if (actual != 0) {
                    const full = self.evidence.node(actual);
                    if (full.tag != .function) return self.failNode(owner, source, .unsupported);
                    if (template.function_type != 0) {
                        if (!try self.matchCovariantType(owner, source, producer, template.function_type, actual, &callee.mappings, &callee.row_mappings)) return self.failNode(owner, source, .unsupported);
                    } else if (!try self.matchType(owner, source, producer, template.parameter.ty, full.a, &callee.mappings, &callee.row_mappings) or !try self.matchType(owner, source, producer, module.typeOf(template.body), full.b, &callee.mappings, &callee.row_mappings)) return self.failNode(owner, source, .unsupported);
                }
                if (self.valueEvidence(argument) != 0 and !try self.matchType(owner, source, producer, template.parameter.ty, self.valueEvidence(argument), &callee.mappings, &callee.row_mappings)) return self.failNode(owner, source, .unsupported);
                for (bindings, 0..) |binding, index| try callee.values.put(self.allocator, binding, self.valueChildren(function)[index]);
                const typed = try self.typedView(owner, source, argument, try self.projectType(producer, template.body, template.parameter.ty, callee.mappings.items, callee.row_mappings.items));
                if (template.parameter.binding != 0) try callee.values.put(self.allocator, template.parameter.binding, typed);
                if (template.qualifier != 0) try self.validateScheme(producer, template.body, module.binding(template.qualifier).scheme, &callee, false);
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
                try callee.mappings.appendSlice(self.allocator, self.type_mappings.items[closure.mappings.start..][0..closure.mappings.len]);
                try callee.row_mappings.appendSlice(self.allocator, self.row_mappings.items[closure.row_mappings.start..][0..closure.row_mappings.len]);
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
        const actual = try self.projectType(owner, id, invocation.callee_type, caller.mappings.items, caller.row_mappings.items);
        const resolved = try self.external(try self.target(owner, invocation.target));
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
    const Source = struct { binding: core.BindingId = 0, value: ValueId, owner: usize, root: types.Id = 0, body: core.Id = 0, closed_rows: types.List = .{} };
    const Import = struct { scope: u32, ty: types.Id };
    const RowImport = struct { scope: u32, row: types.Effects.Id };
    const LabelImport = struct { scope: u32, label: types.Effects.Label };
    const RowVariable = struct { scope: u32, variable: u32 };
    const RowParameter = struct { owner: usize, parameter: u32 };
    const CompletedDemand = struct { scope: u32, node: core.Id, body: core.Id, root: types.Id };
    const Variable = struct { source: Import, region: types.Id };
    const Edge = struct { parent: u32, child: u32, slot: u32, formal: types.Id };
    const DataAlias = struct { instance: types.Id, principal: types.Id, solved: bool = false };
    const CallKey = struct { owner: usize, binding: core.BindingId, evidence: type_evidence.Id, caller: u32 = 0 };
    const DefinitionKey = struct { owner: usize, node: core.Id };
    const CandidateKey = struct { caller: u32, node: core.Id, target: Target };
    const ConstraintKind = enum { binary, field, result_dispatch, resolver, resolver_shape, effect_operation, effect_handler, type_head, type_compare, physical_field, receiver, update, type_rep, effect_rep, invocation, collection, record_merge };
    const Constraint = struct { explicit: bool = false, qualification_span: ?core.Span = null, qualification_unit: u32 = 0, diagnostic_name: []const u8 = &.{}, span: ?core.Span = null, row_carrier: bool = false, source_selection: bool = false, scope: u32, node: core.Id, left: types.Id, right: types.Id = 0, result: types.Id, signature: types.Id = 0, identity: types.NominalIdentity = .{ .unit = 0, .decl = 0 }, op: types.Operator = .none, member: u32 = 0, projection: u32 = 0, kind: ConstraintKind = .binary, writable: bool = false, deferred_member: bool = false, solved: bool = false };
    const Scratch = struct {
        projection_cache: @import("projection_cache.zig").Cache = .{},
        evidence_import_cache: @import("evidence_import_cache.zig").Cache = .{},
        closed_source_cache: @import("closed_source_types.zig").Cache = .{},
        sources: std.ArrayList(Source) = .empty,
        imported: std.AutoHashMapUnmanaged(Import, types.Id) = .empty,
        definitions: std.AutoHashMapUnmanaged(DefinitionKey, core.BindingId) = .empty,
        definition_units: std.AutoHashMapUnmanaged(usize, void) = .empty,
        imported_rows: std.AutoHashMapUnmanaged(RowImport, types.Effects.Id) = .empty,
        imported_labels: std.AutoHashMapUnmanaged(LabelImport, types.Effects.Label) = .empty,
        row_variables: std.AutoHashMapUnmanaged(RowVariable, types.Effects.Id) = .empty,
        row_parameters: std.AutoHashMapUnmanaged(RowParameter, u32) = .empty,
        evidence_rows: std.AutoHashMapUnmanaged(u32, types.Effects.Id) = .empty,
        evidence_labels: std.AutoHashMapUnmanaged(u32, types.Effects.Label) = .empty,
        variables: std.ArrayList(Variable) = .empty,
        edges: std.ArrayList(Edge) = .empty,
        constraints: std.ArrayList(Constraint) = .empty,
        selected_targets: std.ArrayList(core.BindingRef) = .empty,
        data_aliases: std.ArrayList(DataAlias) = .empty,
        frozen: std.AutoHashMapUnmanaged(u32, ValueId) = .empty,
        call_instances: std.AutoHashMapUnmanaged(CallKey, u32) = .empty,
        candidate_instances: std.AutoHashMapUnmanaged(CandidateKey, u32) = .empty,
        unresolved_calls: std.AutoHashMapUnmanaged(Target, u32) = .empty,
        source_functions: std.ArrayList(types.Id) = .empty,
        completed_demands: std.ArrayList(CompletedDemand) = .empty,
        witness_inputs: std.AutoHashMapUnmanaged(types.Id, types.Id) = .empty,

        pub fn deinit(self: *Scratch, allocator: Allocator) void {
            inline for (@typeInfo(Scratch).@"struct".field_names) |field| @field(self, field).deinit(allocator);
            self.* = undefined;
        }
        pub fn clearRetainingCapacity(self: *Scratch) void {
            inline for (@typeInfo(Scratch).@"struct".field_names) |field| @field(self, field).clearRetainingCapacity();
        }
        pub fn storageBound(self: *const Scratch) ?usize {
            var bytes: usize = 0;
            inline for (@typeInfo(Scratch).@"struct".field_names) |field| {
                const value = @field(self, field);
                const buffer = if (comptime @hasField(@TypeOf(value), "answers")) value.answers else value;
                const size = @import("scratch_pool.zig").bufferBound(buffer) orelse return null;
                bytes = std.math.add(usize, bytes, size) catch return null;
            }
            return bytes;
        }
    };
    profile_principal: bool = false,
    profile_rejected: u16 = 0,
    profile_input_calls: usize = 0,
    profile_recorded_inputs: bool = false,
    profile_output_types: usize = 0,
    profile_output_rows: usize = 0,
    session: *Session,
    scratch: Scratch = .{},
    scratch_allocator: Allocator,
    timing: ?@import("backend_timing.zig").Work.Scope = null,
    solver: types.Store,
    solver_initial: ?types.Mark = null,
    retain_selected: bool = false,
    startup_coverage_complete: bool = true,
    include_callables: bool = false,
    source_interface: bool = false,
    speculative_source_entry: bool = false,
    source_selection_failed: bool = false,
    complete_demand_bodies: bool = false,
    source_entry: ?Target = null,
    // A generic nested lambda selects its members in its own concrete code
    // instance. Its enclosing proof still gathers mandatory effect equations.
    defer_members: bool = false,
    collect_depth: usize = 0,
    code_expectation_remaining: usize = 0,

    fn init(session: *Session) types.Error!ClosureRegion {
        const timing = if (session.timing) |work| work.enter(.inference) else null;
        errdefer if (timing) |scope| scope.deinit();
        var region: ClosureRegion = if (session.reuse_solver_capacity) blk: {
            const lease = try session.solver_capacity_pool.take(session.allocator);
            break :blk .{ .session = session, .timing = timing, .solver = lease.solver, .solver_initial = lease.initial, .scratch_allocator = session.allocator };
        } else .{ .session = session, .timing = timing, .solver = try types.Store.initWithOptions(session.allocator, .{ .closed_graphs = true }), .scratch_allocator = session.allocator };
        if (session.reuse_region_scratch) region.scratch = session.region_scratch_pool.take(session.allocator);
        return region;
    }
    fn deinit(self: *ClosureRegion) void {
        defer if (self.timing) |scope| scope.deinit();
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
        if (self.solver_initial) |initial| {
            self.session.solver_capacity_pool.give(.{ .solver = self.solver, .initial = initial });
            self.solver = undefined;
        } else self.solver.deinit();
        if (self.session.reuse_region_scratch) self.session.region_scratch_pool.give(self.scratch_allocator, self.scratch) else self.scratch.deinit(self.scratch_allocator);
        self.scratch = undefined;
    }
    fn failConstraint(self: *ClosureRegion, constraint: Constraint, code: Code) Error {
        const owner = self.scratch.sources.items[constraint.scope].owner;
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
            if (!obligation.explicit) continue;
            const kind: ConstraintKind = switch (obligation.kind) {
                .dispatch => .binary,
                .field => .physical_field,
                .receiver => .receiver,
                .update => .update,
                .record_merge => .record_merge,
                .effect_operation => .effect_operation,
                .type_rep => .type_rep,
                .effect_rep => .effect_rep,
                else => return error.UnresolvedType,
            };
            try self.scratch.constraints.append(self.session.allocator, .{
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
                .row_carrier = obligation.kind == .dispatch or obligation.kind == .receiver or obligation.kind == .update,
            });
        }
    }
    fn seed(self: *ClosureRegion, scope: u32, mappings: []const type_evidence.Mapping) RegionError!void {
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        for (mappings) |mapping| {
            if (mapping.variable == 0 or mapping.variable >= module.types.nodes.len) return error.UnresolvedType;
            try self.solver.unify(try self.importType(scope, mapping.variable, 0), try self.importEvidence(mapping.evidence, 0));
        }
    }
    fn exportMappings(self: *ClosureRegion, scope: u32) RegionError![]type_evidence.Mapping {
        var mappings: std.ArrayList(type_evidence.Mapping) = .empty;
        errdefer mappings.deinit(self.session.allocator);
        for (self.scratch.variables.items) |variable| if (variable.source.scope == scope) {
            const actual = try self.project(variable.region);
            if (actual != 0) try mappings.append(self.session.allocator, .{ .variable = variable.source.ty, .evidence = actual });
        };
        return mappings.toOwnedSlice(self.session.allocator);
    }
    fn seedRows(self: *ClosureRegion, scope: u32, mappings: []const type_evidence.RowMapping) RegionError!void {
        for (mappings) |mapping| try self.solver.unifyEffects(try self.importRowVariable(scope, mapping.variable), try self.importEvidenceRow(mapping.evidence, 0));
    }
    /// Only a recorded principal closing decision licenses an unresolved tail
    /// to become empty. Expected/captured rows are solved before this fallback;
    /// their existing labels and closed facts remain authoritative.
    fn closeCertificates(self: *ClosureRegion) RegionError!bool {
        var certified: std.AutoHashMapUnmanaged(RowVariable, void) = .empty;
        defer certified.deinit(self.session.allocator);
        for (self.scratch.sources.items, 0..) |source, scope| {
            for (self.session.units[source.owner].types.list(source.closed_rows)) |variable|
                try certified.put(self.session.allocator, .{ .scope = @intCast(scope), .variable = variable }, {});
        }
        if (certified.count() == 0) return false;
        // A reusable pure producer can be admitted under an unresolved caller
        // ambient. Its certificate cannot close that caller's unrelated row.
        // Physical code-shape holes have no source identity and impose no such
        // semantic restriction, so their residuals may receive the certificate.
        var protected: std.AutoHashMapUnmanaged(u32, void) = .empty;
        defer protected.deinit(self.session.allocator);
        var imported = self.scratch.row_variables.iterator();
        while (imported.next()) |entry| {
            if (certified.contains(entry.key_ptr.*)) continue;
            const resolved = try self.solver.resolveEffects(entry.value_ptr.*, 0);
            const tail = self.solver.row(resolved).tail;
            if (tail == .variable) try protected.put(self.session.allocator, tail.variable, {});
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
        const mappings = try self.exportMappings(scope);
        errdefer self.session.allocator.free(mappings);
        var rows: std.ArrayList(type_evidence.RowMapping) = .empty;
        errdefer rows.deinit(self.session.allocator);
        var variables = self.scratch.row_variables.iterator();
        while (variables.next()) |entry| {
            if (entry.key_ptr.scope != scope) continue;
            const resolved = try self.solver.resolveEffects(entry.value_ptr.*, 0);
            if (self.solver.row(resolved).tail != .closed) continue;
            const actual = self.session.evidence.projectEffects(&self.solver, resolved, &.{}, &.{}) catch |err| switch (err) {
                error.UnresolvedType => continue,
                else => return err,
            };
            try rows.append(self.session.allocator, .{ .variable = entry.key_ptr.variable, .evidence = actual });
        }
        std.mem.sort(type_evidence.RowMapping, rows.items, {}, struct {
            fn less(_: void, left: type_evidence.RowMapping, right: type_evidence.RowMapping) bool {
                return left.variable < right.variable;
            }
        }.less);
        const selected = try self.session.allocator.dupe(core.BindingRef, self.scratch.selected_targets.items);
        errdefer self.session.allocator.free(selected);
        return .{ .types = mappings, .rows = try rows.toOwnedSlice(self.session.allocator), .selected = selected };
    }
    fn selectedTarget(self: *ClosureRegion, target_: Target) RegionError!void {
        if (!self.retain_selected) return;
        const resolved = try self.session.external(target_);
        const reference: core.BindingRef = .{ .unit = self.session.unitId(resolved.unit), .binding = resolved.binding };
        for (self.scratch.selected_targets.items) |prior| if (std.meta.eql(prior, reference)) return;
        try self.scratch.selected_targets.append(self.session.allocator, reference);
    }
    fn sourceInterface(self: *ClosureRegion, target_: Target, body: *const core.Body) RegionError!SourceInterface {
        self.source_interface = true;
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
        try self.scratch.unresolved_calls.put(self.session.allocator, target_, scope);
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
        if (pending != 0) return .{ .pending = pending, .generic = try self.genericEntryInterface(scope) };
        for (self.scratch.sources.items) |source| {
            const module = &self.session.units[source.owner];
            if (source.binding == 0 or source.binding >= module.bindings.len) continue;
            const binding = module.binding(source.binding);
            const own = if (module.body(source.binding)) |definition| definition.is_function else binding.initializer != 0 and module.node(binding.initializer).tag == .closure;
            if (own) try self.scratch.source_functions.append(self.session.allocator, source.root);
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
        if (constraint.kind == .receiver) self.solver.unify(constraint.right, types.unit) catch |err| return self.sourceSelectionFailure(constraint, err);
        self.solver.unify(constraint.result, actual) catch |err| return self.sourceSelectionFailure(constraint, err);
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
        try self.solver.unify(try self.solver.openCovariant(actual), try self.importEvidence(expected, 0));
        return self.exportSolved(scope);
    }
    fn bodyEvidenceFull(self: *ClosureRegion, owner: usize, body: core.Id, root: types.Id, closed_rows: types.List, scheme: types.Scheme, expected: Expected, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping) RegionError!SolvedEvidence {
        return self.bodyEvidenceMode(owner, body, root, closed_rows, scheme, expected, seeds, row_seeds, false);
    }
    fn bodyEvidenceMode(self: *ClosureRegion, owner: usize, body: core.Id, root: types.Id, closed_rows: types.List, scheme: types.Scheme, expected: Expected, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping, allow_remaining: bool) RegionError!SolvedEvidence {
        self.include_callables = true;
        const scope = try self.typeScope(owner);
        self.scratch.sources.items[scope].body = body;
        self.scratch.sources.items[scope].closed_rows = closed_rows;
        self.scratch.sources.items[scope].root = try self.importType(scope, root, 0);
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
        return self.exportSolved(scope);
    }
    fn closureEvidence(self: *ClosureRegion, owner: usize, closure: core.ClosureInfo, expected: Expected, seeds: []const type_evidence.Mapping) RegionError![]type_evidence.Mapping {
        const solved = try self.closureEvidenceFull(owner, closure, expected, seeds, &.{});
        self.session.allocator.free(solved.rows);
        return solved.types;
    }
    fn closureEvidenceFull(self: *ClosureRegion, owner: usize, closure: core.ClosureInfo, expected: Expected, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping) RegionError!SolvedEvidence {
        return self.closureEvidenceCaptures(owner, closure, expected, seeds, row_seeds, &.{});
    }
    fn importRetainedCapture(self: *ClosureRegion, capture: RetainedCapture, depth: usize) RegionError!types.Id {
        // A captured generic helper is not an invocation. Keep its source
        // signature and lexical semantic inputs; its concrete call uses the
        // ordinary per-use proof. No unselected source body is certified here.
        if (depth >= self.session.options.max_depth) return error.TypeLimit;
        const owner = self.session.findUnit(capture.unit, null) orelse return error.UnresolvedType;
        const module = &self.session.units[owner];
        if (capture.node == 0 or capture.node >= module.nodes.len) return error.UnresolvedType;
        const node = module.node(capture.node);
        const scope = try self.typeScope(owner);
        self.scratch.sources.items[scope].root = try self.importType(scope, node.ty, 0);
        if (capture.mappings != 0) {
            if (capture.mappings >= self.session.evidence.nodes.items.len) return error.UnresolvedType;
            const words = try self.session.allocator.dupe(type_evidence.Id, self.session.evidence.children(capture.mappings));
            defer self.session.allocator.free(words);
            if (self.session.evidence.node(capture.mappings).tag != .record or words.len % 2 != 0) return error.TypeMismatch;
            for (0..words.len / 2) |index| {
                if (words[index * 2] >= module.types.nodes.len or words[index * 2 + 1] >= self.session.evidence.nodes.items.len) return error.UnresolvedType;
                try self.solver.unify(try self.importType(scope, words[index * 2], 0), try self.importEvidence(words[index * 2 + 1], 0));
            }
        }
        try self.seedRows(scope, capture.rows);
        const capture_list = if (node.tag == .closure or node.tag == .suspend_) module.closures[node.a].captures else core.List{};
        const captured = module.extra[capture_list.start..][0..capture_list.len];
        for (capture.values) |value| {
            if (value.binding == 0 or value.binding >= module.bindings.len or value.evidence >= self.session.evidence.nodes.items.len or std.mem.findScalar(core.BindingId, captured, value.binding) == null) return error.UnresolvedType;
            try self.solver.unify(try self.importType(scope, module.binding(value.binding).ty, 0), try self.importEvidence(value.evidence, 0));
        }
        for (capture.captures) |child| {
            if (child.binding == 0 or child.binding >= module.bindings.len or std.mem.findScalar(core.BindingId, captured, child.binding) == null) return error.UnresolvedType;
            const actual = try self.importRetainedCapture(child, depth + 1);
            try self.solver.unify(try self.importType(scope, module.binding(child.binding).ty, 0), try self.solver.openCovariant(try self.solver.resolve(actual, 0)));
        }
        if (node.tag == .closure or node.tag == .suspend_) {
            const closure_ = module.closures[node.a];
            if (node.tag == .closure) {
                try self.alignClosure(scope, capture.node);
            } else {
                const demanded = self.solver.node(try self.solver.resolve(self.scratch.sources.items[scope].root, 0));
                if (demanded.tag != .demand) return error.TypeMismatch;
                try self.solver.unify(demanded.a, try self.importType(scope, module.typeOf(closure_.body), 0));
                if (closure_.function_type != 0) try self.solver.unify(try self.importType(scope, closure_.function_type, 0), try self.solver.functionWithEffects(types.unit, demanded.a, demanded.c));
            }
        } else if (node.tag != .reference and node.tag != .constructor_function and node.tag != .primitive_function) return error.UnresolvedType;
        const actual = self.scratch.sources.items[scope].root;
        return if (capture.computation) try self.solver.nominal(.{ .unit = std.math.maxInt(u32), .decl = 5 }, &.{actual}) else actual;
    }
    fn closureEvidenceCaptures(self: *ClosureRegion, owner: usize, closure: core.ClosureInfo, expected: Expected, seeds: []const type_evidence.Mapping, row_seeds: []const type_evidence.RowMapping, captures: []const RetainedCapture) RegionError!SolvedEvidence {
        self.include_callables = true;
        const scope = try self.typeScope(owner);
        const module = &self.session.units[owner];
        self.scratch.sources.items[scope].body = closure.body;
        self.scratch.sources.items[scope].binding = closure.qualifier;
        self.scratch.sources.items[scope].closed_rows = closure.closed_rows;
        self.scratch.sources.items[scope].root = if (closure.function_type != 0) try self.importType(scope, closure.function_type, 0) else try self.solver.function(try self.importType(scope, closure.parameter.ty, 0), try self.importType(scope, module.typeOf(closure.body), 0));
        try self.seed(scope, seeds);
        try self.seedRows(scope, row_seeds);
        try self.expectShape(self.scratch.sources.items[scope].root, expected);
        for (captures) |capture| {
            if (capture.binding == 0 or capture.binding >= module.bindings.len) return error.UnresolvedType;
            if (std.mem.findScalar(core.BindingId, module.extra[closure.captures.start..][0..closure.captures.len], capture.binding) == null and capture.binding != closure.parameter.binding) return error.UnresolvedType;
            const actual = try self.importRetainedCapture(capture, 0);
            try self.solver.unify(try self.importType(scope, module.binding(capture.binding).ty, 0), try self.solver.openCovariant(try self.solver.resolve(actual, 0)));
        }
        if (closure.qualifier != 0) try self.importScheme(scope, module.binding(closure.qualifier).scheme, closure.body);
        try self.collect(scope, closure.body);
        try self.solve();
        try self.publishValidatedCalls();
        return self.exportSolved(scope);
    }
    // This first retention path only admits interfaces containing plain data.
    // Higher-order arguments, demands, providers and nominal payloads need a
    // richer evidence key. A complete prior region proves all imported source
    // bodies under their exact semantic arrow, including effect rows.
    fn firstOrderData(self: *ClosureRegion, evidence: type_evidence.Id, depth: usize) RegionError!bool {
        if (depth >= self.session.options.max_depth or evidence == 0) return false;
        const value = self.session.evidence.node(evidence);
        switch (value.tag) {
            .unit, .boolean, .u32, .f32, .never => return true,
            .array, .list, .cursor => return self.firstOrderData(value.a, depth + 1),
            .nominal => {
                for (self.session.evidence.children(evidence)) |argument| if (!try self.firstOrderData(argument, depth + 1)) return false;
                return self.plainNominal(value.a, value.b, depth + 1);
            },
            .product => for (self.session.evidence.children(evidence)) |child| {
                if (!try self.firstOrderData(child, depth + 1)) return false;
            },
            .record => {
                const children = self.session.evidence.children(evidence);
                for (0..children.len / 2) |index| {
                    if (!try self.firstOrderData(children[index * 2 + 1], depth + 1)) return false;
                }
            },
            else => return false,
        }
        return true;
    }
    fn sourceData(self: *ClosureRegion, owner: usize, ty: types.Id, variables: types.List, depth: usize) RegionError!bool {
        if (depth >= self.session.options.max_depth or ty == 0) return false;
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
        if (depth >= self.session.options.max_depth) return false;
        const key = (@as(u64, unit_id) << 32) | decl;
        if (self.session.principal_reads) |reads| try reads.plainRead(self.session.allocator, key, self.session.plain_nominals.get(key));
        if (self.session.plain_nominals.get(key)) |known| {
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
        if (self.session.principal_reads) |reads| try reads.plainPublish(self.session.allocator, key, plain);
        try self.session.plain_nominals.put(self.session.allocator, key, plain);
        return plain;
    }
    fn firstOrderArrow(self: *ClosureRegion, evidence: type_evidence.Id) RegionError!bool {
        var current = evidence;
        var depth: usize = 0;
        while (current != 0) {
            if (depth >= self.session.options.max_depth) return false;
            const value = self.session.evidence.node(current);
            if (value.tag != .function) return depth != 0 and try self.firstOrderData(current, depth);
            if (!try self.firstOrderData(value.a, depth + 1)) return false;
            current = value.b;
            depth += 1;
        }
        return false;
    }
    // This quick source test can only exclude a proof. Variables still need
    // the complete semantic-evidence check below before admission.
    fn potentialData(self: *ClosureRegion, owner: usize, ty: types.Id, depth: usize) RegionError!bool {
        if (depth >= self.session.options.max_depth or ty == 0) return false;
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
            if (depth >= self.session.options.max_depth) return false;
            const value = module.types.node(current);
            if (value.tag != .function) return depth != 0 and try self.potentialData(owner, current, depth);
            if (!try self.potentialData(owner, value.a, depth + 1)) return false;
            current = value.b;
            depth += 1;
        }
        return false;
    }
    fn publishValidatedCalls(self: *ClosureRegion) RegionError!void {
        if (!self.session.options.reuse_validated_calls) return;
        for (self.scratch.constraints.items) |constraint| if (!constraint.solved) return;
        for (self.scratch.sources.items) |source| {
            if (source.value != 0 or source.binding == 0 or source.root == 0) continue;
            const module = &self.session.units[source.owner];
            const binding = module.binding(source.binding);
            if (binding.kind != .global or module.body(source.binding) == null) continue;
            if (!try self.potentialArrow(source.owner, binding.ty)) continue;
            const actual = try self.project(source.root);
            if (!try self.firstOrderArrow(actual)) continue;
            if (self.session.principal_reads) |reads| try reads.callPublish(self.session.allocator, .{ .unit = self.session.unitId(source.owner), .binding = source.binding }, actual);
            if (self.session.receipt_tape) |tape| try tape.call_publications.append(self.session.allocator, .{ .unit = self.session.unitId(source.owner), .binding = source.binding, .evidence = actual, .present = true });
            const entry = try self.session.validated_calls.getOrPut(self.session.allocator, .{ .target = .{ .unit = source.owner, .binding = source.binding }, .evidence = actual });
            if (!entry.found_existing) self.session.proofs.proof_published += 1;
        }
    }
    fn expectShape(self: *ClosureRegion, root: types.Id, expected: Expected) RegionError!void {
        switch (expected) {
            .semantic => |actual| if (actual != 0) try self.solver.unify(root, try self.importEvidence(actual, 0)),
            .code => |actual| {
                self.code_expectation_remaining = self.session.options.max_values;
                try self.solver.unify(root, try self.importCodeExpectation(actual.view, actual.id, 0));
            },
        }
    }
    fn importCodeExpectation(self: *ClosureRegion, view: code_expectation.View, actual: code_expectation.Id, depth: usize) RegionError!types.Id {
        if (depth >= self.session.options.max_depth or self.code_expectation_remaining == 0) return error.TypeLimit;
        self.code_expectation_remaining -= 1;
        if (actual == 0) return self.solver.fresh();
        if (actual >= view.nodes.len) return error.UnresolvedType;
        const node = view.node(actual);
        return switch (node.tag) {
            .absent => error.UnresolvedType,
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
                var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.session.allocator);
                const allocator = scratch.allocator();
                const children = view.children(actual);
                const fields = try allocator.alloc(types.Field, children.len / 2);
                defer allocator.free(fields);
                for (fields, 0..) |*field, index| field.* = .{ .name = children[index * 2], .ty = try self.importCodeExpectation(view, children[index * 2 + 1], depth + 1) };
                break :blk try self.solver.record(fields);
            },
            .product, .nominal => blk: {
                var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
                var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.session.allocator);
                const allocator = scratch.allocator();
                const children = view.children(actual);
                const values = try allocator.alloc(types.Id, children.len);
                defer allocator.free(values);
                for (children, values) |child, *value| value.* = try self.importCodeExpectation(view, child, depth + 1);
                break :blk if (node.tag == .nominal) try self.solver.nominal(.{ .unit = node.a, .decl = node.b }, values) else try self.solver.product(values);
            },
        };
    }
    fn importType(self: *ClosureRegion, scope: u32, ty: types.Id, depth: usize) RegionError!types.Id {
        if (depth >= self.session.options.max_depth or self.scratch.imported.count() >= self.session.options.max_values) return error.TypeLimit;
        const key: Import = .{ .scope = scope, .ty = ty };
        if (self.scratch.imported.get(key)) |existing| return existing;
        const owner = self.scratch.sources.items[scope].owner;
        const source = &self.session.units[owner].types;
        const node = source.node(ty);
        const shared = self.session.reuse_closed_source_types and ty > types.never and
            try self.session.closed_source_types.closed(self.session.allocator, self.session.units, owner, ty, 0);
        const closed_key = @import("closed_source_types.zig").Cache.key(owner, ty, depth);
        if (shared) {
            self.session.closed_source_imports += 1;
            if (self.scratch.closed_source_cache.activate(&self.solver, self.session.options.max_depth)) {
                if (self.scratch.closed_source_cache.answers.get(closed_key)) |existing| {
                    self.session.closed_source_reused += 1;
                    return existing;
                }
            }
        }
        const result = switch (node.tag) {
            .absent => return error.UnresolvedType,
            .unit, .boolean, .u32, .f32, .never => ty,
            .variable => try self.solver.fresh(),
            .function => try self.solver.functionWithEffects(try self.importType(scope, node.a, depth + 1), try self.importType(scope, node.b, depth + 1), try self.importRow(scope, node.c, depth + 1)),
            .array, .list, .cursor => try self.solver.sequence(node.tag, try self.importType(scope, node.a, depth + 1)),
            .demand => try self.solver.demandWithEffects(try self.importType(scope, node.a, depth + 1), try self.importRow(scope, node.c, depth + 1)),
            .provider => try self.solver.provider(try self.importType(scope, node.a, depth + 1), try self.importRow(scope, node.c, depth + 1)),
            .state_provider => try self.solver.stateProvider(try self.importType(scope, node.a, depth + 1), try self.importType(scope, node.b, depth + 1), try self.importType(scope, node.c, depth + 1)),
            .resolver => try self.solver.resolver(try self.importType(scope, node.a, depth + 1)),
            .type_constructor => try self.solver.typeConstructor(.{ .unit = node.a, .decl = node.b }),
            .record => blk: {
                var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
                var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.session.allocator);
                const allocator = scratch.allocator();
                const fields = try allocator.alloc(types.Field, node.b);
                defer allocator.free(fields);
                for (fields, 0..) |*imported, index| {
                    const field = source.recordField(node, index);
                    imported.* = .{ .name = field.name, .ty = try self.importType(scope, field.ty, depth + 1) };
                }
                break :blk try self.solver.record(fields);
            },
            .product, .nominal => blk: {
                const children = if (node.tag == .nominal) source.nominalArguments(node) else source.list(.{ .start = node.a, .len = node.b });
                var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
                var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.session.allocator);
                const allocator = scratch.allocator();
                const values = try allocator.alloc(types.Id, children.len);
                defer allocator.free(values);
                for (children, values) |child, *value| value.* = try self.importType(scope, child, depth + 1);
                break :blk if (node.tag == .nominal) try self.solver.nominal(.{ .unit = node.a, .decl = node.b }, values) else try self.solver.product(values);
            },
        };
        if (shared and self.scratch.closed_source_cache.activate(&self.solver, self.session.options.max_depth)) {
            try self.scratch.closed_source_cache.answers.put(self.session.allocator, closed_key, result);
        } else try self.scratch.imported.put(self.session.allocator, key, result);
        if (node.tag == .variable) try self.scratch.variables.append(self.session.allocator, .{ .source = key, .region = result });
        return result;
    }
    fn importLabel(self: *ClosureRegion, scope: u32, label: types.Effects.Label, depth: usize) RegionError!types.Effects.Label {
        if (depth >= self.session.options.max_depth) return error.TypeLimit;
        const key: LabelImport = .{ .scope = scope, .label = label };
        if (self.scratch.imported_labels.get(key)) |known| return known;
        const source = &self.session.units[self.scratch.sources.items[scope].owner].types;
        if (label == 0 or label >= source.operations.len) return error.UnresolvedType;
        var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.session.allocator);
        const allocator = scratch.allocator();
        const original = source.operationArguments(label);
        const arguments = try allocator.alloc(types.Id, original.len);
        defer allocator.free(arguments);
        for (original, arguments) |argument, *imported| imported.* = try self.importType(scope, argument, depth + 1);
        const result = try self.solver.internOperation(source.operation(label).identity, arguments);
        try self.scratch.imported_labels.put(self.session.allocator, key, result);
        return result;
    }
    fn importRow(self: *ClosureRegion, scope: u32, row: types.Effects.Id, depth: usize) RegionError!types.Effects.Id {
        if (row == 0) return 0;
        if (depth >= self.session.options.max_depth) return error.TypeLimit;
        const key: RowImport = .{ .scope = scope, .row = row };
        if (self.scratch.imported_rows.get(key)) |known| return known;
        const source = &self.session.units[self.scratch.sources.items[scope].owner].types;
        if (row >= source.effects.rows.len) return error.UnresolvedType;
        const original = source.row(row);
        var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.session.allocator);
        const allocator = scratch.allocator();
        const source_labels = source.rowLabels(row);
        const labels = try allocator.alloc(types.Effects.Label, source_labels.len);
        defer allocator.free(labels);
        for (source_labels, labels) |label, *imported| imported.* = try self.importLabel(scope, label, depth + 1);
        const tail: types.Effects.Tail = switch (original.tail) {
            .closed => .closed,
            .variable => |variable| blk: {
                const fresh = try self.importRowVariable(scope, variable);
                break :blk self.solver.effects.node(fresh).tail;
            },
            .parameter => |parameter| blk: {
                const parameter_key: RowParameter = .{ .owner = self.scratch.sources.items[scope].owner, .parameter = parameter };
                const fresh = self.scratch.row_parameters.get(parameter_key) orelse fresh: {
                    if (self.scratch.row_parameters.count() >= std.math.maxInt(u32)) return error.TypeLimit;
                    const created: u32 = @intCast(self.scratch.row_parameters.count());
                    try self.scratch.row_parameters.put(self.session.allocator, parameter_key, created);
                    break :fresh created;
                };
                break :blk .{ .parameter = fresh };
            },
        };
        const result = self.solver.effects.row(labels, tail) catch |err| return types.effectError(err);
        try self.scratch.imported_rows.put(self.session.allocator, key, result);
        return result;
    }
    fn importRowVariable(self: *ClosureRegion, scope: u32, variable: u32) RegionError!types.Effects.Id {
        const owner = self.scratch.sources.items[scope].owner;
        if (variable >= self.session.units[owner].types.effects.variable_count) return error.UnresolvedType;
        const key: RowVariable = .{ .scope = scope, .variable = variable };
        if (self.scratch.row_variables.get(key)) |known| return known;
        const fresh = try self.solver.freshEffects();
        try self.scratch.row_variables.put(self.session.allocator, key, fresh);
        return fresh;
    }
    fn importEvidence(self: *ClosureRegion, actual: type_evidence.Id, depth: usize) RegionError!types.Id {
        if (depth >= self.session.options.max_depth) return error.TypeLimit;
        if (actual == 0) return error.UnresolvedType;
        if (actual <= types.never) return actual;
        self.session.evidence_import_requests += 1;
        self.prepareEvidenceImports();
        const memo = &self.scratch.evidence_import_cache;
        const key = if (self.session.reuse_evidence_imports) memo.key(actual, depth) else null;
        if (key) |id| if (memo.answers.get(id)) |known| {
            self.session.evidence_import_reused += 1;
            return known;
        };
        const result = try self.importEvidenceGraph(actual, depth);
        // Construction may synchronize the solver's physical effect clock.
        self.prepareEvidenceImports();
        if (key) |id| if (memo.key(actual, depth) != null) try memo.answers.put(self.session.allocator, id, result);
        return result;
    }
    fn prepareEvidenceImports(self: *ClosureRegion) void {
        if (self.scratch.evidence_import_cache.activate(&self.session.evidence, &self.solver, self.solver.closed_generation, self.solver.effects.physical_epoch, self.session.options.max_depth)) {
            self.scratch.evidence_rows.clearRetainingCapacity();
            self.scratch.evidence_labels.clearRetainingCapacity();
        }
    }
    fn importEvidenceGraph(self: *ClosureRegion, actual: type_evidence.Id, depth: usize) RegionError!types.Id {
        const node = self.session.evidence.node(actual);
        return switch (node.tag) {
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
                var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.session.allocator);
                const allocator = scratch.allocator();
                const children = self.session.evidence.children(actual);
                const fields = try allocator.alloc(types.Field, children.len / 2);
                defer allocator.free(fields);
                for (fields, 0..) |*field, index| field.* = .{ .name = children[index * 2], .ty = try self.importEvidence(children[index * 2 + 1], depth + 1) };
                break :blk try self.solver.record(fields);
            },
            .product, .nominal => blk: {
                var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
                var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.session.allocator);
                const allocator = scratch.allocator();
                const children = self.session.evidence.children(actual);
                const values = try allocator.alloc(types.Id, children.len);
                defer allocator.free(values);
                for (children, values) |child, *value| value.* = try self.importEvidence(child, depth + 1);
                break :blk if (node.tag == .nominal) try self.solver.nominal(.{ .unit = node.a, .decl = node.b }, values) else try self.solver.product(values);
            },
        };
    }
    fn importEvidenceLabel(self: *ClosureRegion, label: u32, depth: usize) RegionError!types.Effects.Label {
        if (depth >= self.session.options.max_depth) return error.TypeLimit;
        self.prepareEvidenceImports();
        if (self.scratch.evidence_labels.get(label)) |known| return known;
        const source = self.session.evidence.view().effects;
        const operation = source.operation(label);
        var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.session.allocator);
        const allocator = scratch.allocator();
        const original = source.operationArguments(label);
        const arguments = try allocator.alloc(types.Id, original.len);
        defer allocator.free(arguments);
        for (original, arguments) |argument, *imported| imported.* = try self.importEvidence(argument, depth + 1);
        const result = try self.solver.internOperation(operation.identity, arguments);
        try self.scratch.evidence_labels.put(self.session.allocator, label, result);
        return result;
    }
    fn importEvidenceRow(self: *ClosureRegion, row: u32, depth: usize) RegionError!types.Effects.Id {
        if (row == 0) return 0;
        if (depth >= self.session.options.max_depth) return error.TypeLimit;
        self.prepareEvidenceImports();
        if (self.scratch.evidence_rows.get(row)) |known| return known;
        const source = self.session.evidence.view().effects;
        var scratch_buffer: [128]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.session.allocator);
        const allocator = scratch.allocator();
        const source_labels = source.rowLabels(row);
        const labels = try allocator.alloc(types.Effects.Label, source_labels.len);
        defer allocator.free(labels);
        for (source_labels, labels) |label, *imported| imported.* = try self.importEvidenceLabel(label, depth + 1);
        const result = self.solver.effects.row(labels, .closed) catch |err| return types.effectError(err);
        try self.scratch.evidence_rows.put(self.session.allocator, row, result);
        return result;
    }
    fn project(self: *ClosureRegion, ty: types.Id) RegionError!type_evidence.Id {
        const resolved = try self.solver.resolve(ty, 0);
        return self.session.evidence.projectOwned(&self.solver, resolved, &self.scratch.projection_cache) catch |err| switch (err) {
            error.UnresolvedType => 0,
            else => return err,
        };
    }
    fn addValue(self: *ClosureRegion, value_: ValueId, depth: usize) RegionError!u32 {
        if (depth >= self.session.options.max_depth or self.scratch.sources.items.len >= self.session.options.max_values or self.scratch.sources.items.len >= std.math.maxInt(u32)) return error.TypeLimit;
        const kind = self.session.valueInfo(value_).kind;
        if (kind != .closure and kind != .suspension) return self.addAggregate(value_, depth);
        const metadata = self.session.closureInfo(value_);
        const owner = self.session.findUnit(metadata.unit, null) orelse return error.UnresolvedType;
        const module = &self.session.units[owner];
        const scope: u32 = @intCast(self.scratch.sources.items.len);
        try self.scratch.sources.append(self.session.allocator, .{ .value = value_, .owner = owner });
        var body: core.Id = 0;
        const root = switch (metadata.origin) {
            .anonymous => blk: {
                const template = module.closures[metadata.identity];
                body = template.body;
                self.scratch.sources.items[scope].closed_rows = template.closed_rows;
                if (template.function_type != 0) {
                    const function = try self.importType(scope, template.function_type, 0);
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
                var full = module.binding(metadata.identity).ty;
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
        for (self.session.type_mappings.items[metadata.mappings.start..][0..metadata.mappings.len]) |mapping| try self.solver.unify(try self.importType(scope, mapping.variable, 0), try self.importEvidence(mapping.evidence, 0));
        try self.seedRows(scope, self.session.row_mappings.items[metadata.row_mappings.start..][0..metadata.row_mappings.len]);
        const existing = self.session.valueEvidence(value_);
        if (existing != 0) try self.solver.unify(root, try self.importEvidence(existing, 0));
        const captures = try self.session.allocator.dupe(ValueId, self.session.valueChildren(value_));
        defer self.session.allocator.free(captures);
        for (captures, 0..) |capture, index| {
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
                try self.solver.unify(formal, try self.solver.openCovariant(actual));
                try self.scratch.edges.append(self.session.allocator, .{ .parent = scope, .child = child, .slot = @intCast(index), .formal = formal });
            } else {
                const actual = self.session.valueEvidence(capture);
                if (actual == 0) return error.UnresolvedType;
                try self.solver.unify(formal, try self.importEvidence(actual, 0));
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
        if (body != 0) try self.collect(scope, body);
        return scope;
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
        try self.scratch.sources.append(self.session.allocator, .{ .owner = owner, .value = value_ });
        const captures = try self.session.allocator.dupe(ValueId, self.session.valueChildren(value_));
        defer self.session.allocator.free(captures);
        var children: std.ArrayList(types.Id) = .empty;
        defer children.deinit(self.session.allocator);
        for (captures, 0..) |capture, index| {
            const child = try self.addValue(capture, depth + 1);
            const formal = self.scratch.sources.items[child].root;
            try children.append(self.session.allocator, formal);
            try self.scratch.edges.append(self.session.allocator, .{ .parent = scope, .child = child, .slot = @intCast(index), .formal = formal });
        }
        const root = switch (info.kind) {
            .scalar, .type_constructor, .resolver, .provider, .state_provider => try self.importEvidence(self.session.valueEvidence(value_), 0),
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
                for (children.items) |child| try self.solver.unify(element, child);
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
                try self.solver.unify(try self.importType(scope, constructor.payload, 0), children.items[0]);
                break :blk arrow.b;
            },
            .effect_set, .effect_descriptor, .computation, .request_decision => try self.importEvidence(self.session.valueEvidence(value_), 0),
            .closure, .suspension => return error.UnresolvedType,
        };
        self.scratch.sources.items[scope].root = root;
        const existing = self.session.valueEvidence(value_);
        if (existing != 0) try self.solver.unify(root, try self.importEvidence(existing, 0));
        return scope;
    }
    fn collectCall(self: *ClosureRegion, caller: u32, reference: core.BindingRef, callee_type: types.Id, arguments: []const core.Id) RegionError!void {
        const target_ = try self.session.external(try self.session.target(self.scratch.sources.items[caller].owner, reference));
        const module = &self.session.units[target_.unit];
        const binding = module.binding(target_.binding);
        const definition = module.body(target_.binding);
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
                const present = self.session.validated_calls.contains(.{ .target = target_, .evidence = known });
                if (self.session.receipt_tape) |tape| try tape.call_reads.append(self.session.allocator, .{ .unit = self.session.unitId(target_.unit), .binding = target_.binding, .evidence = known, .present = present });
                if (present) {
                    if (self.session.principal_reads) |reads| if (!reads.calls_seen.contains(.{ .target = .{ .unit = self.session.unitId(target_.unit), .binding = target_.binding }, .evidence = known })) reads.invalidate(.call_read);
                    self.session.proofs.proof_reused += 1;
                    return;
                }
            }
            if (self.scratch.call_instances.get(.{ .owner = target_.unit, .binding = target_.binding, .evidence = known, .caller = lexical_caller })) |prior| {
                _ = try self.admitSignature(instantiated, self.scratch.sources.items[prior].root);
                return;
            }
            if (definition != null and binding.kind == .global and try self.partitionCall(target_, known)) return;
        }
        if (self.session.receipt_tape) |tape| if (binding.kind == .global)
            try tape.sources.append(self.session.allocator, .{ .unit = self.session.unitId(target_.unit), .binding = target_.binding });
        const scope = try self.typeScope(target_.unit);
        self.scratch.sources.items[scope].body = body_root;
        self.scratch.sources.items[scope].binding = target_.binding;
        self.scratch.sources.items[scope].closed_rows = if (definition) |body| body.closed_rows else if (module.node(body_root).tag == .closure) module.closure(body_root).closed_rows else binding.scheme.closed_rows;
        self.scratch.sources.items[scope].root = try self.importType(scope, source_type, 0);
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
                    try self.scratch.witness_inputs.put(self.session.allocator, arrow.a, actual);
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
        const actual = try self.project(self.scratch.sources.items[scope].root);
        if (actual != 0) {
            const key: CallKey = .{ .owner = target_.unit, .binding = target_.binding, .evidence = actual, .caller = lexical_caller };
            if (self.scratch.call_instances.get(key)) |prior| {
                _ = try self.admitSignature(instantiated, self.scratch.sources.items[prior].root);
                return;
            }
            try self.scratch.call_instances.put(self.session.allocator, key, scope);
            try self.collect(scope, body_root);
        } else {
            if (self.scratch.unresolved_calls.get(target_)) |active| {
                // Recursive uses share the active monomorphic inference root.
                // Closed instances keep their separate evidence-keyed cache.
                _ = try self.admitSignature(instantiated, self.scratch.sources.items[active].root);
                return;
            }
            try self.scratch.unresolved_calls.put(self.session.allocator, target_, scope);
            defer _ = self.scratch.unresolved_calls.remove(target_);
            try self.collect(scope, body_root);
        }
        if (definition == null) try self.shareLexical(scope, caller, binding.scheme);
    }
    /// The closed first-order arrow is the entire boundary. No lexical solver
    /// variable or higher-order capture enters the child region. A recursive
    /// component stays within one region; only a complete exact arrow may
    /// replace source collection in the parent.
    fn partitionCall(self: *ClosureRegion, target_: Target, expected: type_evidence.Id) RegionError!bool {
        const session = self.session;
        if (!session.split_closed_calls or !session.options.reuse_validated_calls or self.retain_selected or self.source_interface or session.diagnostic != null or session.split_active.count() >= 32 or session.split_active.contains(target_)) return false;
        if (!try self.firstOrderArrow(expected)) return false;
        session.split_attempts += 1;
        try session.split_active.put(session.allocator, target_, {});
        defer _ = session.split_active.remove(target_);
        var child = try ClosureRegion.init(session);
        defer child.deinit();
        child.collect_depth = self.collect_depth;
        const accepted = child.closedCall(target_, expected) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => false,
        };
        if (!accepted) {
            // A failed speculative source proof never owns the diagnostic.
            // Ordinary chronological collection reports the authoritative one.
            session.allocator.free(session.owned_diagnostic_message);
            session.owned_diagnostic_message = &.{};
            session.diagnostic = null;
            session.split_declined += 1;
            return false;
        }
        session.split_accepted += 1;
        return true;
    }
    fn closedCall(self: *ClosureRegion, target_: Target, expected: type_evidence.Id) RegionError!bool {
        self.include_callables = true;
        const scope = try self.callableScope(target_);
        const root = self.scratch.sources.items[scope].root;
        _ = try self.admitSignature(try self.importEvidence(expected, 0), root);
        const actual = try self.project(root);
        if (actual != 0) try self.scratch.call_instances.put(self.session.allocator, .{ .owner = target_.unit, .binding = target_.binding, .evidence = actual }, scope);
        try self.scratch.unresolved_calls.put(self.session.allocator, target_, scope);
        try self.collect(scope, self.scratch.sources.items[scope].body);
        try self.solve();
        if (!self.allConstraintsSolved() or try self.project(root) != expected) return false;
        try self.publishValidatedCalls();
        return self.session.validated_calls.contains(.{ .target = target_, .evidence = expected });
    }
    fn shareLexical(self: *ClosureRegion, scope: u32, caller: u32, scheme: types.Scheme) RegionError!void {
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        // Existing records never change; imports only append. Fix the initial
        // length and reload each record by value after any intervening growth.
        const variable_count = self.scratch.variables.items.len;
        for (0..variable_count) |index| {
            const variable = self.scratch.variables.items[index];
            if (variable.source.scope != scope or std.mem.findScalar(types.Id, module.types.list(scheme.variables), variable.source.ty) != null) continue;
            try self.solver.unify(variable.region, try self.importType(caller, variable.source.ty, 0));
        }
        var rows: std.ArrayList(RowVariable) = .empty;
        defer rows.deinit(self.session.allocator);
        var iterator = self.scratch.row_variables.iterator();
        while (iterator.next()) |entry| {
            const key = entry.key_ptr.*;
            if (key.scope != scope or std.mem.findScalar(types.Id, module.types.list(scheme.row_variables), key.variable) != null or std.mem.findScalar(types.Id, module.types.list(self.scratch.sources.items[scope].closed_rows), key.variable) != null) continue;
            try rows.append(self.session.allocator, key);
        }
        for (rows.items) |row| try self.solver.unifyEffects(self.scratch.row_variables.get(row).?, try self.importRowVariable(caller, row.variable));
    }
    fn alignClosure(self: *ClosureRegion, scope: u32, id: core.Id) RegionError!void {
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        const closure = module.closure(id);
        const actual = try self.importType(scope, module.typeOf(id), 0);
        const envelope = if (closure.function_type != 0) try self.importType(scope, closure.function_type, 0) else actual;
        const signature = self.solver.node(try self.solver.resolve(envelope, 0));
        if (signature.tag != .function) return error.TypeMismatch;
        const shape = try self.solver.functionWithEffects(try self.importType(scope, closure.parameter.ty, 0), try self.importType(scope, module.typeOf(closure.body), 0), signature.c);
        try self.solver.unify(actual, envelope);
        try self.solver.unify(actual, shape);
        if (self.source_interface) try self.scratch.source_functions.append(self.session.allocator, actual);
    }
    fn operationConstraint(self: *ClosureRegion, scope: u32, id: core.Id, operation: core.OperationValue) RegionError!void {
        const owner = self.scratch.sources.items[scope].owner;
        const module = &self.session.units[owner];
        var arguments: std.ArrayList(types.Id) = .empty;
        defer arguments.deinit(self.session.allocator);
        for (module.types.list(operation.arguments)) |argument| try arguments.append(self.session.allocator, try self.importType(scope, argument, 0));
        const signature = try self.importType(scope, operation.signature, 0);
        if (operation.witness != 0) {
            try self.scratch.constraints.append(self.session.allocator, .{ .scope = scope, .node = id, .left = try self.importType(scope, module.typeOf(operation.witness), 0), .right = try self.importType(scope, operation.witness_result, 0), .result = 0, .kind = .type_head });
        }
        try self.scratch.constraints.append(self.session.allocator, .{ .scope = scope, .node = id, .left = signature, .right = try self.solver.product(arguments.items), .result = 0, .signature = signature, .identity = .{ .unit = if (operation.identity.unit == 0) self.session.unitId(owner) else operation.identity.unit, .decl = operation.identity.decl }, .kind = .effect_operation });
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
            if (!std.meta.eql(self.solver.operation(label).identity, constraint.identity)) continue;
            if (selected == label) continue;
            const arguments = try self.session.allocator.dupe(types.Id, self.solver.operationArguments(label));
            defer self.session.allocator.free(arguments);
            const candidate = try self.solver.product(arguments);
            const point = self.solver.mark();
            self.solver.unify(constraint.right, candidate) catch |err| switch (err) {
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
        try self.solver.unify(constraint.right, try self.solver.product(arguments));
        return true;
    }
    fn definitionIndex(self: *ClosureRegion) *std.AutoHashMapUnmanaged(DefinitionKey, core.BindingId) {
        return if (self.session.reuse_callable_definitions) &self.session.callable_definitions else &self.scratch.definitions;
    }
    fn callableDefinitions(self: *ClosureRegion, owner: usize) RegionError!void {
        // This index reads immutable Core, never the current inference scope.
        // Its lifetime is the Session's source owner, not a solver region.
        const definitions = self.definitionIndex();
        const owners = if (self.session.reuse_callable_definitions) &self.session.callable_definition_units else &self.scratch.definition_units;
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
    fn collect(self: *ClosureRegion, scope: u32, body: core.Id) RegionError!void {
        if (self.collect_depth >= self.session.options.max_depth) return error.TypeLimit;
        self.collect_depth += 1;
        defer self.collect_depth -= 1;
        const module = &self.session.units[self.scratch.sources.items[scope].owner];
        if (self.session.receipt_tape) |tape| {
            const source = self.scratch.sources.items[scope];
            if (source.binding != 0 and module.binding(source.binding).kind == .global) try tape.sources.append(self.session.allocator, .{ .unit = self.session.unitId(source.owner), .binding = source.binding });
        }
        try self.callableDefinitions(self.scratch.sources.items[scope].owner);
        const recipe = if (self.session.options.reuse_body_recipes) try self.session.body_recipes.get(self.session.allocator, self.session.units, .{ .owner = self.scratch.sources.items[scope].owner, .body = body, .callables = self.include_callables }, self.session.options.max_values) else null;
        var work: body_recipe.Walk = .{ .recipe = recipe };
        defer work.deinit(self.session.allocator);
        try work.append(self.session.allocator, body);
        while (try work.next(self.session.allocator)) |id| {
            if (work.count > self.session.options.max_values) return error.TypeLimit;
            if (recipe != null) self.session.body_recipes.replayed_visits += 1;
            const n = module.node(id);
            if (self.session.receipt_tape) |tape| {
                tape.collected += 1;
                if (n.tag == .suspend_ or n.tag == .request_loop or n.tag == .request_decision) tape.unknown = true;
            }
            if (n.tag == .reference) {
                const reference = module.reference(id);
                if (reference.unit == 0 or reference.unit == self.session.unitId(self.scratch.sources.items[scope].owner)) {
                    const binding = module.binding(reference.binding);
                    if (binding.kind == .local) try self.scratch.data_aliases.append(self.session.allocator, .{ .instance = try self.importType(scope, n.ty, 0), .principal = try self.importType(scope, binding.ty, 0) });
                }
            }
            if (self.include_callables and !self.source_interface and n.tag == .reference) {
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
                    if (actual != 0) try self.solver.unify(try self.importType(scope, n.ty, 0), try self.importEvidence(actual, 0));
                }
            }
            if (self.include_callables and n.tag == .reference and module.types.node(n.ty).tag == .function) {
                const definition = self.definitionIndex().get(.{ .owner = self.scratch.sources.items[scope].owner, .node = id });
                if (definition == null or definition.? == self.scratch.sources.items[scope].binding) {
                    const previous = self.defer_members;
                    self.defer_members = true;
                    defer self.defer_members = previous;
                    try self.collectCall(scope, module.reference(id), n.ty, &.{});
                }
            }
            const source_signature = module.dispatchSignature(id);
            const dispatch_signature = if (source_signature == 0) 0 else try self.importType(scope, source_signature, 0);
            if (n.tag == .handle) if (module.handleEffects(id)) |handler| {
                try self.scratch.constraints.append(self.session.allocator, .{ .scope = scope, .node = id, .left = try self.importType(scope, handler.first, 0), .right = if (handler.second == 0) 0 else try self.importType(scope, handler.second, 0), .result = try self.solver.functionWithEffects(types.unit, types.unit, try self.importRow(scope, handler.residual, 0)), .signature = try self.solver.functionWithEffects(types.unit, types.unit, try self.importRow(scope, handler.extended, 0)), .kind = .effect_handler });
            };
            if (self.include_callables and n.tag == .call) try self.collectCall(scope, module.call(id).target, module.call(id).callee_type, module.children(id));
            if (self.include_callables and n.tag == .apply) {
                const callee = module.node(n.a);
                if (callee.tag == .closure) {
                    try self.alignClosure(scope, n.a);
                    try work.append(self.session.allocator, module.closure(n.a).body);
                }
                if (callee.tag == .reference) {
                    const reference = module.reference(n.a);
                    const target_ = try self.session.external(try self.session.target(self.scratch.sources.items[scope].owner, reference));
                    const binding = self.session.units[target_.unit].binding(target_.binding);
                    if (binding.kind == .global or binding.initializer != 0) try self.collectCall(scope, reference, callee.ty, &.{n.b}) else if (self.retain_selected) {
                        self.startup_coverage_complete = false;
                    }
                } else if (callee.tag != .closure and self.retain_selected) {
                    self.startup_coverage_complete = false;
                }
            }
            if (n.tag == .record_merge) try self.scratch.constraints.append(self.session.allocator, .{ .scope = scope, .node = id, .left = try self.importType(scope, module.typeOf(n.a), 0), .right = try self.importType(scope, module.typeOf(n.b), 0), .result = try self.importType(scope, n.ty, 0), .kind = .record_merge });
            if (self.source_interface and n.tag == .type_same) try self.scratch.constraints.append(self.session.allocator, .{ .scope = scope, .node = id, .left = try self.importType(scope, module.typeOf(n.a), 0), .right = try self.importType(scope, module.typeOf(n.b), 0), .result = types.boolean, .kind = .type_compare });
            if (n.tag == .associated or (n.tag == .scalar and n.c != 0 and n.b != 0)) try self.scratch.constraints.append(self.session.allocator, .{ .scope = scope, .node = id, .left = try self.importType(scope, module.typeOf(n.a), 0), .right = try self.importType(scope, module.typeOf(n.b), 0), .result = try self.importType(scope, n.ty, 0), .signature = dispatch_signature, .deferred_member = self.defer_members, .op = Session.operator(n.op), .member = if (n.tag == .associated) n.c else 0 });
            if (n.tag == .project) try self.scratch.constraints.append(self.session.allocator, .{ .scope = scope, .node = id, .left = try self.importType(scope, module.typeOf(n.a), 0), .result = try self.importType(scope, n.ty, 0), .signature = dispatch_signature, .projection = n.b, .kind = .field, .deferred_member = self.defer_members });
            if (n.tag == .result_associated) try self.scratch.constraints.append(self.session.allocator, .{ .scope = scope, .node = id, .left = try self.importType(scope, module.typeOf(n.a), 0), .result = try self.importType(scope, n.ty, 0), .signature = dispatch_signature, .member = n.b, .kind = .result_dispatch, .deferred_member = self.defer_members });
            switch (n.tag) {
                .scalar, .associated, .logical, .record_merge, .type_same, .apply, .effect_provider, .handle => try work.appendSlice(self.session.allocator, &.{ n.a, n.b }),
                .if_value, .if_stmt, .state_provider => try work.appendSlice(self.session.allocator, &.{ n.a, n.b, n.c }),
                .array_op => {
                    const args = module.children(id);
                    const operation = module.arrayOperation(id);
                    if (operation == .cursor_has or operation == .cursor_value or operation == .cursor_advance) {
                        // A generic cursor retains its collection kind as well
                        // as its element. Replay that relationship when a body
                        // is specialized, just as the source checker does.
                        const collection = try self.solver.fresh();
                        try self.solver.unify(try self.importType(scope, module.typeOf(args[0]), 0), try self.solver.sequence(.cursor, collection));
                        try self.scratch.constraints.append(self.session.allocator, .{
                            .kind = .collection,
                            .scope = scope,
                            .node = id,
                            .left = collection,
                            .result = if (operation == .cursor_value) try self.importType(scope, n.ty, 0) else try self.solver.fresh(),
                        });
                    }
                    if (module.arrayOperation(id) == .get and module.types.node(module.typeOf(args[0])).tag == .variable) try self.scratch.constraints.append(self.session.allocator, .{
                        .kind = .collection,
                        .scope = scope,
                        .node = id,
                        .left = try self.importType(scope, module.typeOf(args[0]), 0),
                        .result = try self.importType(scope, n.ty, 0),
                    });
                    try work.appendSlice(self.session.allocator, args);
                },
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
                    if (iteration.kind == .array and iteration.pattern != 0 and module.types.node(module.typeOf(iteration.first)).tag == .variable) try self.scratch.constraints.append(self.session.allocator, .{
                        .kind = .collection,
                        .scope = scope,
                        .node = id,
                        .left = try self.importType(scope, module.typeOf(iteration.first), 0),
                        .result = try self.importType(scope, module.pattern(iteration.pattern).ty, 0),
                    });
                    try work.appendSlice(self.session.allocator, &.{ iteration.first, iteration.end, iteration.body });
                },
                .break_ => try work.appendSlice(self.session.allocator, module.breakValues(id)),
                .resolver_op => {
                    const metadata = module.resolverInfo(id);
                    try work.append(self.session.allocator, metadata.resolver);
                    try work.appendSlice(self.session.allocator, module.resolverArguments(id));
                    if (metadata.operation == .forward) {
                        const arguments = module.resolverArguments(id);
                        if (arguments.len != 1) return error.TypeMismatch;
                        try self.solver.unify(try self.importType(scope, module.typeOf(arguments[0]), 0), try self.importType(scope, module.typeOf(id), 0));
                    }
                    if (metadata.operation == .run) {
                        const arguments = module.resolverArguments(id);
                        if (arguments.len != 1) return error.TypeMismatch;
                        const action = try self.importType(scope, module.typeOf(arguments[0]), 0);
                        const signature = self.solver.node(try self.solver.resolve(action, 0));
                        if (signature.tag != .function) return error.TypeMismatch;
                        try self.solver.unify(action, try self.solver.functionWithEffects(types.unit, try self.importType(scope, module.typeOf(id), 0), signature.c));
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
                            try self.solver.unify(arrow.a, try self.importType(scope, module.typeOf(argument), 0));
                            suffix = arrow.b;
                        }
                        try self.solver.unify(suffix, try self.importType(scope, module.typeOf(id), 0));
                        try self.scratch.constraints.append(self.session.allocator, .{ .scope = scope, .node = id, .left = try self.importType(scope, module.typeOf(metadata.resolver), 0), .right = signature, .result = try self.importType(scope, module.typeOf(id), 0), .kind = .resolver });
                    }
                    if (metadata.operation != .monad) try self.scratch.constraints.append(self.session.allocator, .{ .scope = scope, .node = id, .left = try self.importType(scope, module.typeOf(metadata.resolver), 0), .result = try self.importType(scope, module.typeOf(id), 0), .kind = .resolver_shape });
                },
                .update => {
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
                            try self.solver.unify(assigned, try self.importType(scope, selector.result_type, 0));
                            assigned = try self.importType(scope, selector.source_type, 0);
                        } else {
                            const result = if (reverse == 0) try self.importType(scope, n.ty, 0) else try self.solver.fresh();
                            try self.scratch.constraints.append(self.session.allocator, .{ .scope = scope, .node = id, .left = try self.importType(scope, selector.source_type, 0), .right = assigned, .result = result, .signature = try self.solver.function(types.unit, types.unit), .member = module.projection(selector.projection).field, .kind = .update, .deferred_member = self.defer_members });
                            assigned = result;
                        }
                    }
                    if (selectors.len != 0) for (selectors) |selector| {
                        if (selector.kind == .index) {
                            try work.append(self.session.allocator, selector.index);
                            if (module.types.node(selector.source_type).tag == .variable) try self.scratch.constraints.append(self.session.allocator, .{
                                .kind = .collection,
                                .scope = scope,
                                .node = id,
                                .left = try self.importType(scope, selector.source_type, 0),
                                .result = try self.importType(scope, selector.result_type, 0),
                            });
                            continue;
                        }
                        try self.scratch.constraints.append(self.session.allocator, .{ .scope = scope, .node = id, .left = try self.importType(scope, selector.source_type, 0), .result = try self.importType(scope, selector.result_type, 0), .projection = selector.projection, .kind = .field, .writable = true, .deferred_member = self.defer_members });
                    } else for (module.updatePath(id)) |projection_index| {
                        const projection = module.projection(projection_index);
                        try self.scratch.constraints.append(self.session.allocator, .{ .scope = scope, .node = id, .left = try self.importType(scope, projection.source_type, 0), .result = try self.importType(scope, projection.result_type, 0), .projection = projection_index, .kind = .field, .writable = true, .deferred_member = self.defer_members });
                    };
                },
                .operation_value => try self.operationConstraint(scope, id, module.operationValue(id)),
                .closure => if (self.include_callables) {
                    const qualifier = self.definitionIndex().get(.{ .owner = self.scratch.sources.items[scope].owner, .node = id }) orelse module.closure(id).qualifier;
                    if (qualifier != 0 and self.scratch.sources.items[scope].binding != qualifier) {
                        if (self.retain_selected and !try self.session.startupSelectorFree(self.scratch.sources.items[scope].owner, module.closure(id).body)) self.startup_coverage_complete = false;
                        continue;
                    }
                    try self.alignClosure(scope, id);
                    const previous = self.defer_members;
                    self.defer_members = true;
                    defer self.defer_members = previous;
                    try self.collect(scope, module.closure(id).body);
                },
                .effect_reflection => {
                    const kind: checked_types.ReflectionKind = @fromBackingInt(@intCast(n.a));
                    if (kind == .count or kind == .has or kind == .same) try work.append(self.session.allocator, n.b);
                    if (n.c != 0) try work.append(self.session.allocator, n.c);
                },
                .computation => try work.append(self.session.allocator, n.a),
                .request_decision => try work.appendSlice(self.session.allocator, &.{ n.b, n.c }),
                .request_loop => {
                    const metadata = module.requestLoopInfo(id);
                    try self.collectStartupPatterns(scope, &.{metadata.completion_pattern});
                    try work.appendSlice(self.session.allocator, &.{ metadata.computation, metadata.completion_body });
                    for (module.requestArms(id)) |arm| try work.append(self.session.allocator, arm.callback);
                },
                .suspend_ => {
                    if (self.retain_selected and !try self.session.startupSelectorFree(self.scratch.sources.items[scope].owner, module.closures[n.a].body)) self.startup_coverage_complete = false;
                    if (self.complete_demand_bodies) {
                        const closure = module.closures[n.a];
                        const actual = try self.importType(scope, n.ty, 0);
                        const demanded = self.solver.node(try self.solver.resolve(actual, 0));
                        if (demanded.tag != .demand) return error.TypeMismatch;
                        try self.solver.unify(demanded.a, try self.importType(scope, module.typeOf(closure.body), 0));
                        if (closure.function_type != 0) try self.solver.unify(try self.importType(scope, closure.function_type, 0), try self.solver.functionWithEffects(types.unit, demanded.a, demanded.c));
                        if (closure.qualifier != 0 and closure.qualifier != self.scratch.sources.items[scope].binding) try self.importScheme(scope, module.binding(closure.qualifier).scheme, closure.body);
                        try self.collect(scope, closure.body);
                        // Only a completed exact source body can participate in
                        // retained row inference. No value/memo is created.
                        if (self.scratch.completed_demands.items.len >= self.session.options.max_values) return error.TypeLimit;
                        try self.scratch.completed_demands.append(self.session.allocator, .{ .scope = scope, .node = id, .body = closure.body, .root = actual });
                    }
                },
                .constant, .reference, .constructor_function, .primitive_function, .panic, .type_constructor => {},
                .invalid => return error.UnresolvedType,
            }
        }
    }
    fn solve(self: *ClosureRegion) RegionError!void {
        return self.solveMode(false);
    }
    /// Local uses retain their producer's selected data facts. Callable
    /// components keep their own instances and rows; unresolved producer
    /// variables never acquire facts from a use.
    fn solveDataAliases(self: *ClosureRegion) RegionError!bool {
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
        if (depth >= self.session.options.max_depth) return error.TypeLimit;
        const actual = try self.solver.resolve(principal, 0);
        if (try self.closedDataShape(actual, depth)) {
            try self.solver.unify(instance, actual);
            return true;
        }
        const source = self.solver.node(actual);
        const use = self.solver.node(try self.solver.resolve(instance, 0));
        if (source.tag == .variable) return false;
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
        if (depth >= self.session.options.max_depth) return error.TypeLimit;
        const node = self.solver.node(try self.solver.resolve(root, 0));
        return switch (node.tag) {
            .unit, .boolean, .u32, .f32, .never => true,
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
        while (depth < self.session.options.max_depth) : (depth += 1) {
            head = self.scratch.witness_inputs.get(head) orelse head;
            head = try self.solver.resolve(head, 0);
            const node = self.solver.node(head);
            if (node.tag != .function) return head;
            head = node.b;
        }
        return error.TypeLimit;
    }
    fn solveMode(self: *ClosureRegion, allow_remaining: bool) RegionError!void {
        var fallback = false;
        while (true) {
            var remaining: usize = 0;
            var required: usize = 0;
            var progress = try self.solveDataAliases();
            var index: usize = 0;
            while (index < self.scratch.constraints.items.len) : (index += 1) {
                const constraint = self.scratch.constraints.items[index];
                if (constraint.solved) continue;
                remaining += 1;
                if (!constraint.deferred_member) required += 1;
                if (constraint.kind == .record_merge) {
                    if (try self.solver.mergeRecords(constraint.left, constraint.right)) |merged| {
                        try self.solver.unify(merged, constraint.result);
                        self.scratch.constraints.items[index].solved = true;
                        progress = true;
                    }
                    continue;
                }
                if (constraint.kind == .collection) {
                    const owner_type = self.solver.node(try self.solver.resolve(constraint.left, 0));
                    if (owner_type.tag == .variable) continue;
                    if (owner_type.tag != .array and owner_type.tag != .list) return error.TypeMismatch;
                    try self.solver.unify(owner_type.a, constraint.result);
                    self.scratch.constraints.items[index].solved = true;
                    progress = true;
                    continue;
                }
                if (constraint.kind == .type_rep or constraint.kind == .effect_rep) {
                    const represented = if (constraint.kind == .type_rep) constraint.left else constraint.signature;
                    if (try self.project(represented) == 0) continue;
                    self.scratch.constraints.items[index].solved = true;
                    progress = true;
                    continue;
                }
                if (constraint.kind == .invocation) {
                    const selected = self.invocation(constraint) catch |err| return self.sourceSelectionFailure(constraint, err);
                    if (!selected) continue;
                    self.scratch.constraints.items[index].solved = true;
                    progress = true;
                    continue;
                }
                if (constraint.kind == .physical_field or constraint.kind == .receiver) {
                    if (!try self.solveFieldConstraint(constraint)) continue;
                    self.scratch.constraints.items[index].solved = true;
                    progress = true;
                    continue;
                }
                if (constraint.kind == .update) {
                    if (!try self.updateConstraint(constraint)) continue;
                    self.scratch.constraints.items[index].solved = true;
                    progress = true;
                    continue;
                }
                if (constraint.kind == .effect_handler) {
                    var labels: std.ArrayList(types.Effects.Label) = .empty;
                    defer labels.deinit(self.session.allocator);
                    var closed = true;
                    for ([_]types.Id{ constraint.left, constraint.right }) |token_type| {
                        if (token_type == 0) continue;
                        const token = try self.solver.resolve(token_type, 0);
                        if (!try self.solver.equalClosed(token, token)) {
                            closed = false;
                            break;
                        }
                        const nominal = self.solver.node(token);
                        if (nominal.tag != .nominal) return error.TypeMismatch;
                        const arguments = try self.session.allocator.dupe(types.Id, self.solver.nominalArguments(nominal));
                        defer self.session.allocator.free(arguments);
                        try labels.append(self.session.allocator, try self.solver.internOperation(.{ .unit = nominal.a, .decl = nominal.b }, arguments));
                    }
                    if (!closed) continue;
                    const remainder = self.solver.node(try self.solver.resolve(constraint.result, 0));
                    const extended = self.solver.node(try self.solver.resolve(constraint.signature, 0));
                    if (remainder.tag != .function or extended.tag != .function) return error.TypeMismatch;
                    const residual = try self.solver.resolveEffects(remainder.c, 0);
                    try labels.appendSlice(self.session.allocator, self.solver.rowLabels(residual));
                    const row = self.solver.effects.rowAt(labels.items, self.solver.row(residual).tail, self.solver.row(residual).cursor) catch |err| return types.effectError(err);
                    try self.solver.unifyEffects(extended.c, row);
                    self.scratch.constraints.items[index].solved = true;
                    progress = true;
                    continue;
                }
                if (constraint.kind == .type_compare) {
                    const left = try self.sourceWitnessHead(constraint.left);
                    const right = try self.sourceWitnessHead(constraint.right);
                    if (self.solver.node(left).tag == .never or self.solver.node(right).tag == .never) {
                        const target = self.source_entry.?;
                        const point = self.session.units[target.unit].sourceNamePoint(target.binding);
                        return self.session.fail(target.unit, .{ .start = point, .end = point }, .invalid_annotation);
                    }
                    if (try self.project(left) == 0 or try self.project(right) == 0) continue;
                    self.scratch.constraints.items[index].solved = true;
                    progress = true;
                    continue;
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
                    if (self.solver.node(try self.solver.resolve(head, 0)).tag == .variable) continue;
                    try self.solver.unify(head, constraint.right);
                    self.scratch.constraints.items[index].solved = true;
                    progress = true;
                    continue;
                }
                if (constraint.kind == .effect_operation) {
                    var argument_pack = try self.solver.resolve(constraint.right, 0);
                    if (!try self.solver.equalClosed(argument_pack, argument_pack)) {
                        if (!try self.recoverOperationArguments(constraint)) continue;
                        argument_pack = try self.solver.resolve(constraint.right, 0);
                    }
                    const signature = self.solver.node(try self.solver.resolve(constraint.left, 0));
                    if (signature.tag == .variable) continue;
                    if (signature.tag != .function) return error.TypeMismatch;
                    const arguments = self.solver.list(.{ .start = self.solver.node(argument_pack).a, .len = self.solver.node(argument_pack).b });
                    const label = try self.solver.internOperation(constraint.identity, arguments);
                    const residual = if (constraint.explicit) 0 else try self.solver.freshEffects();
                    const row = self.solver.effects.row(&.{label}, self.solver.row(residual).tail) catch |err| return types.effectError(err);
                    const selected = try self.solver.functionWithEffects(signature.a, signature.b, row);
                    try self.solver.unify(constraint.left, selected);
                    if (constraint.signature != 0) try self.solver.unify(constraint.signature, selected);
                    self.scratch.constraints.items[index].solved = true;
                    progress = true;
                    continue;
                }
                if (constraint.kind == .field) {
                    if (!try self.solveFieldConstraint(constraint)) continue;
                    self.scratch.constraints.items[index].solved = true;
                    progress = true;
                    continue;
                }
                if (constraint.kind == .resolver) {
                    const actual = try self.project(constraint.left);
                    if (actual == 0) continue;
                    const resolver = self.session.evidence.node(actual);
                    if (resolver.tag != .resolver) return error.TypeMismatch;
                    const token = self.session.evidence.node(resolver.a);
                    if (token.tag != .type_constructor) return error.TypeMismatch;
                    const source = self.scratch.sources.items[constraint.scope];
                    const metadata = self.session.units[source.owner].resolverInfo(constraint.node);
                    const target_ = try self.session.resolverTarget(source.owner, constraint.node, metadata, (@as(u64, token.a) << 32) | token.b);
                    const body = self.session.units[target_.unit].body(target_.binding) orelse return error.UnresolvedType;
                    const scope = try self.typeScope(target_.unit);
                    try self.solver.unify(constraint.right, try self.importType(scope, body.scheme.root, 0));
                    try self.collect(scope, body.root);
                    try self.selectedTarget(target_);
                    self.scratch.constraints.items[index].solved = true;
                    progress = true;
                    continue;
                }
                if (constraint.kind == .resolver_shape) {
                    const actual = try self.project(constraint.left);
                    if (actual == 0) continue;
                    const provider = self.session.evidence.node(actual);
                    if (provider.tag != .resolver) return error.TypeMismatch;
                    const token = self.session.evidence.node(provider.a);
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
                        try self.solver.unify(constraint.result, try self.solver.nominal(.{ .unit = token.a, .decl = token.b }, arguments.items));
                    } else if (result.tag != .nominal or result.a != token.a or result.b != token.b) return error.TypeMismatch;
                    self.scratch.constraints.items[index].solved = true;
                    progress = true;
                    continue;
                }
                const selected = if (constraint.kind == .result_dispatch) try self.resultConstraint(constraint) else try self.binaryConstraint(constraint, fallback);
                if (!selected) continue;
                self.scratch.constraints.items[index].solved = true;
                progress = true;
            }
            if (remaining == 0) {
                _ = try self.closeCertificates();
                return;
            }
            if (progress or try self.closeCertificates()) {
                fallback = false;
            } else if (!fallback) {
                // Receivers and calls reveal operand owners before a stalled
                // pass may infer an unknown operand from the known receiver.
                fallback = true;
            } else if (allow_remaining or required == 0) {
                return;
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
            try self.scratch.candidate_instances.put(self.session.allocator, key, candidate);
            break :scope candidate;
        };
        const signature = self.scratch.sources.items[scope].root;
        const first = self.solver.node(signature);
        if (first.tag != .function) return false;
        const second = self.solver.node(first.b);
        if (second.tag != .function) return false;
        const point = self.solver.mark();
        self.solver.unify(first.a, constraint.left) catch |err| switch (err) {
            error.TypeMismatch, error.InfiniteType, error.EffectMismatch, error.InfiniteEffect => {
                self.solver.rollback(point);
                return false;
            },
            else => return err,
        };
        self.solver.unify(second.a, constraint.right) catch |err| switch (err) {
            error.TypeMismatch, error.InfiniteType, error.EffectMismatch, error.InfiniteEffect => {
                self.solver.rollback(point);
                return false;
            },
            else => return err,
        };
        // Operand admission selects the method before its result is checked.
        // A result mismatch never licenses trying the other receiver.
        try self.solver.unify(constraint.result, second.b);
        if (constraint.row_carrier) try self.addInvocation(constraint, signature, true) else _ = try self.admitSignature(constraint.signature, signature);
        try self.collectSelected(scope, target_);
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
            try self.solver.unify(constraint.result, if (comparison) types.boolean else constraint.left);
            if (constraint.row_carrier) try self.pureInvocation(constraint);
            return true;
        }
        if (right) |identity| if (left == null or !std.meta.eql(left.?, identity)) {
            if (try self.binaryCandidate(constraint, identity)) return true;
        };
        if (try self.project(constraint.left) == 0 or try self.project(constraint.right) == 0) return false;
        return self.failConstraint(constraint, if (constraint.member == 0) .ambiguous_operator else .missing_associated);
    }
    fn resultConstraint(self: *ClosureRegion, constraint: Constraint) RegionError!bool {
        const identity = try self.identityOf(constraint.result) orelse return false;
        const source = self.scratch.sources.items[constraint.scope];
        const reference = (try self.session.associatedTarget(self.session.unitId(source.owner), identity, constraint.member, .none)) orelse return self.session.failNode(source.owner, constraint.node, .missing_associated);
        const target_ = try self.session.target(null, reference);
        const scope = try self.callableScope(target_);
        const signature = self.scratch.sources.items[scope].root;
        const arrow = self.solver.node(signature);
        if (arrow.tag != .function) return error.TypeMismatch;
        try self.solver.unify(constraint.left, arrow.a);
        try self.solver.unify(constraint.result, arrow.b);
        _ = try self.admitSignature(constraint.signature, signature);
        try self.collectSelected(scope, target_);
        return true;
    }
    fn collectSelected(self: *ClosureRegion, scope: u32, target_: Target) RegionError!void {
        // This path runs only after a candidate has been admitted. Record even
        // when its body instance was already collected in this region.
        try self.selectedTarget(target_);
        const root = self.scratch.sources.items[scope].root;
        const actual = try self.project(root);
        if (actual != 0) {
            const key: CallKey = .{ .owner = target_.unit, .binding = target_.binding, .evidence = actual };
            if (self.scratch.call_instances.get(key)) |prior| {
                try self.solver.unify(root, self.scratch.sources.items[prior].root);
                return;
            }
            try self.scratch.call_instances.put(self.session.allocator, key, scope);
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
            const message = try @import("mismatch_display.zig").render(self.session.allocator, solver, .{
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
        try self.solver.unifyWithReporter(expected, admitted, reporter);
        return admitted;
    }
    fn typeScope(self: *ClosureRegion, owner: usize) RegionError!u32 {
        if (self.scratch.sources.items.len >= self.session.options.max_values or self.scratch.sources.items.len >= std.math.maxInt(u32)) return error.TypeLimit;
        const scope: u32 = @intCast(self.scratch.sources.items.len);
        try self.scratch.sources.append(self.session.allocator, .{ .value = 0, .owner = owner });
        return scope;
    }
    fn callableScope(self: *ClosureRegion, target_: Target) RegionError!u32 {
        const module = &self.session.units[target_.unit];
        const body = module.body(target_.binding) orelse return error.UnresolvedType;
        const scope = try self.typeScope(target_.unit);
        self.scratch.sources.items[scope].body = body.root;
        self.scratch.sources.items[scope].closed_rows = body.closed_rows;
        self.scratch.sources.items[scope].root = try self.importType(scope, module.binding(target_.binding).ty, 0);
        self.scratch.sources.items[scope].binding = target_.binding;
        try self.importScheme(scope, body.scheme, body.root);
        return scope;
    }
    fn arrayMember(self: *ClosureRegion, target_: Target, receiver: ValueId, expected: type_evidence.Id) RegionError!ValueId {
        const actual = try self.addValue(receiver, 0);
        const scope = try self.callableScope(target_);
        const root = self.scratch.sources.items[scope].root;
        const arrow = self.solver.node(root);
        if (arrow.tag != .function) return error.TypeMismatch;
        try self.solver.unify(arrow.a, self.scratch.sources.items[actual].root);
        if (expected != 0) try self.solver.unify(try self.solver.openCovariant(arrow.b), try self.importEvidence(expected, 0));
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
            for (nominal_module.constructors) |constructor| {
                const nominal = nominal_module.nominal(constructor.nominal);
                if (self.session.nominalIdentity(nominal_owner, nominal.identity.unit, nominal.identity.decl) != (@as(u64, owner.a) << 32) | owner.b) continue;
                constructors += 1;
                if (constructor.payload == 0) {
                    field = null;
                    break;
                }
                const scope = try self.typeScope(nominal_owner);
                const arrow = self.solver.node(try self.importType(scope, constructor.scheme.root, 0));
                if (arrow.tag != .function) return error.TypeMismatch;
                try self.solver.unify(arrow.b, receiver);
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
                if (field) |prior| try self.solver.unify(prior, found.?) else field = found;
            }
            if (constructors == 0) return error.UnresolvedType;
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
        try self.solver.unify(arrow.a, receiver);
        var mismatch: MemberMismatch = .{ .region = self, .constraint = constraint };
        const reporter: types.Store.MismatchReporter = .{ .context = &mismatch, .report = MemberMismatch.report };
        const admitted = if (constraint.row_carrier) row: {
            try self.addInvocation(constraint, signature, false);
            break :row signature;
        } else try self.admitSignatureObserved(constraint.signature, signature, reporter);
        // Named member recursion reuses its already admitted body instance.
        // collectSelected still records the target on an instance hit.
        try self.collectSelected(scope, target_);
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
        try self.scratch.constraints.append(self.session.allocator, invocation_);
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
                if (existing != null) try self.solver.unify(field.ty, assigned);
            } else if (existing != null) try self.solver.unify(field.ty, prior.ty);
            try fields.append(self.session.allocator, .{ .name = field.name, .ty = if (field.name == member) assigned else field.ty });
        }
        return if (found) try self.solver.record(fields.items) else null;
    }
    fn updateConstraint(self: *ClosureRegion, constraint: Constraint) RegionError!bool {
        const owner = self.solver.node(try self.solver.resolve(constraint.left, 0));
        if (owner.tag == .variable) return false;
        if (owner.tag == .record) {
            const updated = try self.updatedRecord(constraint.left, constraint.right, constraint.member, null) orelse return self.failConstraint(constraint, .missing_field);
            try self.solver.unify(constraint.result, updated);
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
                try self.solver.unify(input.b, constraint.left);
                _ = try self.updatedRecord(try self.importType(output_scope, constructor.payload, 0), constraint.right, constraint.member, try self.importType(input_scope, constructor.payload, 0)) orelse return self.failConstraint(constraint, .missing_field);
                try self.solver.unify(output.b, constraint.result);
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
        const captures = try self.session.allocator.dupe(ValueId, self.session.valueChildren(source.value));
        defer self.session.allocator.free(captures);
        for (self.scratch.edges.items) |edge| if (edge.parent == scope) {
            captures[edge.slot] = try self.freeze(edge.child);
        };
        const value_kind = self.session.valueInfo(source.value).kind;
        if (value_kind != .closure and value_kind != .suspension) {
            const info = self.session.valueInfo(source.value);
            if (info.kind == .scalar) return self.session.typedView(source.owner, source.body, source.value, actual);
            const result = try self.session.makeAggregate(source.owner, source.body, info.kind, info.nominal, info.bits, captures);
            self.session.value_records.items[result] = self.session.value_records.items[source.value];
            const typed = try self.session.typedView(source.owner, source.body, result, actual);
            try self.scratch.frozen.put(self.session.allocator, scope, typed);
            return typed;
        }
        var metadata = self.session.closureInfo(source.value);
        var solved = try self.exportSolved(scope);
        defer solved.deinit(self.session.allocator);
        metadata.mappings = try self.session.captureMappings(source.owner, source.body, solved.types);
        metadata.row_mappings = try self.session.captureRowMappings(source.owner, source.body, solved.rows);
        const header = try self.session.makeClosure(source.owner, source.body, metadata, captures);
        if (value_kind == .suspension) {
            self.session.values.items[header].kind = .suspension;
            self.session.values.items[header].nominal = self.session.valueInfo(source.value).nominal;
        }
        const result = try self.session.typedView(source.owner, source.body, header, actual);
        try self.scratch.frozen.put(self.session.allocator, scope, result);
        return result;
    }
    fn allConstraintsSolved(self: *const ClosureRegion) bool {
        for (self.scratch.constraints.items) |constraint| if (!constraint.solved) return false;
        return true;
    }
    fn closeRetainedFunctionRows(self: *ClosureRegion, root: types.Id, parameters: usize) RegionError!bool {
        if (parameters == 0) return false;
        if (parameters > self.session.options.max_depth) return error.TypeLimit;
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
        defer self.session.allocator.free(variables);
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
        defer self.session.allocator.free(header);
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
        try self.solver.unify(try self.solver.openCovariant(actual), try self.importEvidence(expected, 0));
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
    var tracked: @import("memory.zig").TrackedAllocator = .{ .backing = backing };
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
    const exact = try allocator.dupe(ClosureRegion.Variable, region.scratch.variables.items);
    region.scratch.variables.deinit(allocator);
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
        const label: types.Effects.Label = @intCast(index + 1);
        try region.solver.unifyEffects(actual, try region.solver.effects.row(&.{label}, .closed));
        const retained = try region.importRowVariable(callee, variable);
        if (index == 0) {
            try std.testing.expectEqualSlices(types.Effects.Label, &.{label}, region.solver.rowLabels(try region.solver.resolveEffects(retained, 0)));
        } else {
            try region.solver.unifyEffects(retained, try region.solver.effects.row(&.{label + 10}, .closed));
            try std.testing.expectEqualSlices(types.Effects.Label, &.{label}, region.solver.rowLabels(try region.solver.resolveEffects(actual, 0)));
        }
    }
    try std.testing.expectEqual(@as(usize, 0), session.steps);
}
test "lexical sharing snapshots initial numeric records across growth and preserves quantified type and row independence" {
    for ([_]usize{ 0, 1, 80 }) |eligible| try lexicalSnapshotScenario(std.testing.allocator, eligible);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, lexicalSnapshotScenario, .{@as(usize, 1)});
}

fn bodyRecipeLower(source: []const u8) !core.Module {
    const allocator = std.testing.allocator;
    var tokens = try @import("lexer.zig").lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: @import("symbols.zig").Pool = .{};
    defer names.deinit(allocator);
    var syntax = try @import("parser.zig").parse(allocator, source, tokens.tokens.items, &names);
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
    try std.testing.expectEqualDeep(reference.session.evidence.nodes.items, replay.session.evidence.nodes.items);
    try std.testing.expectEqualDeep(reference.session.evidence.extra.items, replay.session.evidence.extra.items);
    try std.testing.expectEqualDeep(reference.session.evidence.effects.rows.items, replay.session.evidence.effects.rows.items);
    try std.testing.expectEqualDeep(reference.session.evidence.effects.labels.items, replay.session.evidence.effects.labels.items);
    try std.testing.expectEqualDeep(reference.session.evidence.effects.operations.items, replay.session.evidence.effects.operations.items);
}
fn bodyRecipeHistoryScenario(allocator: Allocator, module: *const core.Module, wanted: []const []const u8, valid: bool) !void {
    var reference_session = try Session.init(allocator, &.{module.*});
    defer reference_session.deinit();
    reference_session.options.reuse_body_recipes = false;
    reference_session.reuse_callable_definitions = false;
    reference_session.reuse_region_scratch = false;
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
    try std.testing.expectEqual(@as(usize, 0), reference_session.body_recipes.builds);
    try std.testing.expect(replay_session.body_recipes.builds > 0);
    if (valid) {
        try std.testing.expect(replay_session.body_recipes.requests > replay_session.body_recipes.builds);
        try std.testing.expect(replay_session.body_recipes.replayed_visits > replay_session.body_recipes.planned_visits);
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(allocator, bodyRecipeHistoryScenario, .{ module, wanted, valid });
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
        @embedFile("captured-callable-fixtures/bound-cache-effects.blot"),
        @embedFile("captured-callable-fixtures/bound-cache-nominals.blot"),
        @embedFile("captured-callable-fixtures/bound-cache-missing.blot"),
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
    reference_session.reuse_callable_definitions = false;
    reference_session.reuse_region_scratch = false;
    var replay_session = try Session.init(allocator, &.{module.*});
    defer replay_session.deinit();
    // Populate a complete recipe where admission permits it. A later smaller
    // quota must decline this cached recipe before any semantic action.
    _ = try replay_session.body_recipes.get(allocator, &.{module.*}, .{ .owner = 0, .body = root, .callables = true }, 1_000_000);
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
    try std.testing.expect(replay_session.body_recipes.declined_walks > 0);
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(allocator, bodyRecipeQuotaScenario, .{ &module, @as(core.Id, 1), @as(?ClosureRegion.RegionError, error.UnresolvedType) });
    for ([_]core.ResolverOperation{ .forward, .run }) |operation| {
        resolvers[0].operation = operation;
        nodes[3] = .{ .tag = .resolver_op, .a = 0, .ty = types.u32_type };
        try bodyRecipeQuotaScenario(allocator, &module, 1, error.TypeMismatch);
        try @import("allocation_failures.zig").checkAllAllocationFailures(allocator, bodyRecipeQuotaScenario, .{ &module, @as(core.Id, 1), @as(?ClosureRegion.RegionError, error.TypeMismatch) });
    }
    // No semantic prefix: the original traversal budget is the eventual
    // failure. The optimization must decline the entire wide walk first.
    nodes[3] = .{ .tag = .constant, .ty = types.u32_type };
    try bodyRecipeQuotaScenario(allocator, &module, 1, error.TypeLimit);
    try @import("allocation_failures.zig").checkAllAllocationFailures(allocator, bodyRecipeQuotaScenario, .{ &module, @as(core.Id, 1), @as(?ClosureRegion.RegionError, error.TypeLimit) });
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
    try std.testing.expect(!session.specialized_closures.contains(key));
    // Match the real public path's early reservation and full outer region.
    try session.specialized_closures.ensureUnusedCapacity(session.allocator, 1);
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
    while (session.specialized_closures.available != 0) {
        const alias = try session.makeClosure(0, body, metadata, children);
        _ = try session.inferClosure(alias);
        inner_count += 1;
    }
    try std.testing.expect(inner_count != 0);
    try std.testing.expectEqual(@as(u32, 0), session.specialized_closures.available);
    const before = session.specialized_closures.count();
    try std.testing.expect(!session.specialized_closures.contains(key));
    failing.fail_index = failing.alloc_index;
    failing.resize_fail_index = failing.resize_index;
    try std.testing.expectError(error.OutOfMemory, session.cacheSpecialization(key, selected));
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(before, session.specialized_closures.count());
    try std.testing.expect(!session.specialized_closures.contains(key));
    try std.testing.expectEqual(previous, session.specialized_closures.get(prior_key).?);
    failing.fail_index = std.math.maxInt(usize);
    failing.resize_fail_index = std.math.maxInt(usize);
    try session.cacheSpecialization(key, selected);
    try std.testing.expectEqual(selected, session.specialized_closures.get(key).?);
    try std.testing.expectEqual(previous, session.specialized_closures.get(prior_key).?);
    try std.testing.expectEqual(before + 1, session.specialized_closures.count());
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
    const arrow = session.evidence.node(result.evidence);
    try std.testing.expectEqual(type_evidence.Tag.function, arrow.tag);
    try std.testing.expectEqual(type_evidence.Tag.unit, session.evidence.node(arrow.a).tag);
    try std.testing.expectEqual(type_evidence.Tag.u32, session.evidence.node(arrow.b).tag);
    try std.testing.expect(session.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 0), session.steps);
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
        try @import("allocation_failures.zig").checkAllAllocationFailures(allocator, concreteSelfRuntimeInterfaceScenario, .{&module});
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
    var tracked: @import("memory.zig").TrackedAllocator = .{ .backing = backing };
    const allocator = tracked.allocator();
    var session = try Session.init(allocator, &.{});
    var session_alive = true;
    defer if (session_alive) session.deinit();
    session.reuse_solver_capacity = true;
    var region = try ClosureRegion.init(&session);
    var region_alive = true;
    defer if (region_alive) region.deinit();
    const root = try region.solver.array(types.u32_type);
    try region.scratch.variables.append(allocator, .{ .source = .{ .scope = 0, .ty = 19 }, .region = root });
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
    try std.testing.expectEqual(@as(usize, 1), session.region_scratch_pool.stats.reused);
    const replacement = try next.solver.array(types.f32_type);
    try std.testing.expectEqual(root, replacement);
    const newer_evidence = try next.project(replacement);
    try std.testing.expectEqual(types.u32_type, session.evidence.nodes.items[retained_evidence].a);
    try std.testing.expectEqual(types.f32_type, session.evidence.nodes.items[newer_evidence].a);
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
test "solver capacity exports own projected evidence across region ID recycling teardown and OOM" {
    try solverCapacityExportsScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, solverCapacityExportsScenario, .{});
}
test "solver capacity regions keep fresh maps and active solvers across nested return" {
    const allocator = std.testing.allocator;
    var session = try Session.init(allocator, &.{});
    defer session.deinit();
    session.reuse_solver_capacity = true;
    var outer = try ClosureRegion.init(&session);
    var outer_alive = true;
    defer if (outer_alive) outer.deinit();
    const root = try outer.solver.fresh();
    try outer.solver.appendVersion(root, types.u32_type);
    try outer.scratch.imported.put(allocator, .{ .scope = 7, .ty = 13 }, root);
    var inner = try ClosureRegion.init(&session);
    var inner_alive = true;
    defer if (inner_alive) inner.deinit();
    try std.testing.expect(inner.solver.nodes.items.ptr != outer.solver.nodes.items.ptr);
    try std.testing.expectEqual(@as(u32, 0), inner.scratch.imported.count());
    const inner_nodes = inner.solver.nodes.items.ptr;
    inner.deinit();
    inner_alive = false;
    try std.testing.expectEqual(types.u32_type, try outer.solver.resolve(root, 0));
    try std.testing.expectEqual(root, outer.scratch.imported.get(.{ .scope = 7, .ty = 13 }).?);
    outer.deinit();
    outer_alive = false;
    try std.testing.expect(session.solver_capacity_pool.slot.?.solver.nodes.items.ptr == inner_nodes);
}

test "solver capacity Session allocator swaps preserve the original durable slot" {
    const allocator = std.testing.allocator;
    var session = try Session.init(allocator, &.{});
    defer session.deinit();
    session.reuse_solver_capacity = true;
    var first = try ClosureRegion.init(&session);
    first.deinit();
    const retained_nodes = session.solver_capacity_pool.slot.?.solver.nodes.items.ptr;
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
    try std.testing.expect(temporary.solver.nodes.items.ptr != retained_nodes);
    session.allocator = allocator;
    temporary.deinit();
    temporary_alive = false;
    try std.testing.expect(session.solver_capacity_pool.slot.?.solver.nodes.items.ptr == retained_nodes);
    var next = try ClosureRegion.init(&session);
    defer next.deinit();
    try std.testing.expect(next.solver.nodes.items.ptr == retained_nodes);
    try std.testing.expect(next.solver.allocator.ptr == allocator.ptr and next.solver.allocator.vtable == allocator.vtable);
}

test "inference scratch retains bounded capacity and discards oversized regions" {
    const a = std.testing.allocator;
    var session = try Session.init(a, &.{});
    defer session.deinit();
    var first = try ClosureRegion.init(&session);
    try first.scratch.variables.append(a, .{ .source = .{ .scope = 0, .ty = 17 }, .region = types.u32_type });
    first.deinit();
    try std.testing.expect(session.region_scratch_pool.slot != null);
    try std.testing.expect(session.region_scratch_pool.stats.retained_bytes <= @import("scratch_pool.zig").limit);
    var oversized = try ClosureRegion.init(&session);
    try std.testing.expectEqual(@as(usize, 0), oversized.scratch.variables.items.len);
    try oversized.scratch.variables.ensureTotalCapacity(a, @import("scratch_pool.zig").limit / @sizeOf(ClosureRegion.Variable) + 1);
    oversized.deinit();
    try std.testing.expect(session.region_scratch_pool.slot == null);
    var next = try ClosureRegion.init(&session);
    defer next.deinit();
    try std.testing.expectEqual(@as(usize, 0), next.scratch.variables.items.len);
    try std.testing.expectEqual(@as(u32, 0), next.scratch.imported.count());
}

fn evidenceImportSharingScenario(allocator: Allocator) !void {
    var session = try Session.init(allocator, &.{});
    defer session.deinit();
    const e = &session.evidence;
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
    session.reuse_evidence_imports = false;
    var reference = try ClosureRegion.init(&session);
    defer reference.deinit();
    const copied = try reference.importEvidence(root, 0);
    try std.testing.expectEqual(root, try reference.project(copied));
    try std.testing.expect(reference.solver.nodes.items.len > count);
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
    session.options.max_depth = 1;
    const deeper = try region.typeScope(0);
    try std.testing.expectError(error.TypeLimit, region.importType(deeper, concrete, 0));
    session.options.max_depth = 256;
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, closedSourceSharingScenario, .{&module});
}

test "closed evidence imports share graphs and preserve semantic effects and chronology under allocation failures" {
    try evidenceImportSharingScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, evidenceImportSharingScenario, .{});
}

test "closed evidence imports preserve request depth limits and recover after failure" {
    var session = try Session.init(std.testing.allocator, &.{});
    defer session.deinit();
    const array = try session.evidence.intern(.array, types.u32_type, 0, &.{});
    const root = try session.evidence.intern(.list, array, 0, &.{});
    var region = try ClosureRegion.init(&session);
    defer region.deinit();
    session.options.max_depth = 3;
    const known = try region.importEvidence(root, 0);
    try std.testing.expectEqual(known, try region.importEvidence(root, 0));
    try std.testing.expectError(error.TypeLimit, region.importEvidence(root, 1));
    session.options.max_depth = 2;
    try std.testing.expectError(error.TypeLimit, region.importEvidence(root, 0));
    session.options.max_depth = 3;
    try std.testing.expectEqual(root, try region.project(try region.importEvidence(root, 0)));
}

test "closed evidence imports revoke recycled IDs physical mutations and saturated clocks" {
    var session = try Session.init(std.testing.allocator, &.{});
    defer session.deinit();
    const root = try session.evidence.intern(.product, 0, 0, &.{ types.u32_type, types.boolean });
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
    const op = try session.evidence.effects.internOperation(.{ .unit = 1, .decl = 5 }, &.{types.u32_type});
    const row = try session.evidence.effects.internRow(&.{op});
    const root = try session.evidence.internWithEffects(.function, types.u32_type, types.u32_type, row, &.{});
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
