//! Owned metadata for one complete, pinned backend run. IDs below name their
//! explicitly owned pools; they are not portable keys or edit-reuse admission.
//! Only immutable Core is borrowed, and its caller must retain it through replay.
const std = @import("std");
const core = @import("core.zig");
const layout = @import("layout.zig");
const substitution_keys = @import("substitution_keys.zig");
const core_eval = @import("core_eval.zig");
const type_evidence = @import("type_evidence.zig");
const runtime_operations = @import("runtime_operations.zig");
const runtime_identity = @import("runtime_identity.zig");
const code_expectation = @import("code_expectation.zig");
const provider_chain = @import("provider_chain.zig");
const structural = @import("structural.zig");
const Allocator = std.mem.Allocator;
const Hash = std.crypto.hash.Blake3;
const IdentityMetadata = runtime_identity.Metadata;
pub const max_parameters = 16;
pub const Key = struct { target: core.BindingRef, parameters: [max_parameters]layout.Id = @splat(1), count: u8 = 0, result: layout.Id = 1, effects: [max_parameters]u32 = @splat(0), templates: substitution_keys.Id = 0, template_result: bool = false };
pub const ClosureKey = struct { unit: u32, catalog: u32, ty: layout.Id, captures: layout.Id, templates: substitution_keys.Id = 0, evidence: u32 = 0, rows: substitution_keys.Id = 0, parameter_template: u32 = 0, template_result: bool = false, static_values: substitution_keys.Id = 0 };
pub const CapturedTemplate = struct { unit: u32 = 0, node: core.Id, captures: layout.Id, templates: substitution_keys.Id, has_environment: bool, computation: bool = false, evidence: u32 = 0, rows: substitution_keys.Id = 0 };
pub const CallableKey = struct { target: core.BindingRef, ty: layout.Id, applied: u32 = 0 };
pub const ConstructorKey = struct { unit: u32, catalog: u32, ty: layout.Id };
pub const PrimitiveKey = struct { unit: u32, catalog: u32, ty: layout.Id, applied: u32 = 0 };
pub const OperationKey = struct { operation: runtime_operations.Id, ty: layout.Id };
pub const ConstantKey = struct { target: core.BindingRef, ty: layout.Id };
pub const Request = union(enum) {
    named: Key,
    closure: ClosureKey,
    callable: CallableKey,
    constructor: ConstructorKey,
    primitive: PrimitiveKey,
    operation: OperationKey,
    host: layout.Id,
    constant: ConstantKey,
    runtime_global: core.BindingRef,
};
pub const State = enum { pending, reserved, hit, complete, failed };
pub const ValueResult = struct { value: core_eval.ValueId, layout: layout.Id };
pub const StaticRead = struct { target: core.BindingRef, value: core_eval.ValueId };
pub const Job = struct {
    parent: u32,
    request: Request,
    /// Unsupported executable dependencies preserve their snapshot but force
    /// this job to rebuild. Static reads below extend Request's validity with
    /// exact value, evidence, callable-source and capture-graph comparison.
    reusable: bool = true,
    /// Inlining consumes executable bodies without creating a callee job.
    /// Each consumed declaration has its own exact executable dependency.
    inline_bodies: std.ArrayList(core.BindingRef) = .empty,
    static_reads: std.ArrayList(StaticRead) = .empty,
    state: State = .pending,
    function: ?u32 = null,
    target_job: u32 = 0,
    mappings: []layout.Mapping = &.{},
    rows: []layout.RowMapping = &.{},
    templates: []substitution_keys.Entry = &.{},
    solved: bool = false,
    result_template: ?u32 = null,
    value: ?ValueResult = null,
    global: ?u32 = null,
    pub fn hasStaticValues(self: *const Job) bool {
        return self.static_reads.items.len != 0 or switch (self.request) {
            .closure => |key| key.static_values != 0,
            else => false,
        };
    }
    fn deinit(self: *Job, allocator: Allocator) void {
        self.inline_bodies.deinit(allocator);
        self.static_reads.deinit(allocator);
        allocator.free(self.mappings);
        allocator.free(self.rows);
        allocator.free(self.templates);
    }
};
pub const Event = union(enum) {
    enter: u32,
    hit: struct { job: u32, target: u32, function: u32 },
    reserve: struct { job: u32, function: u32 },
    solved: u32,
    complete: struct { job: u32, function: u32, result_template: ?u32 },
    complete_value: struct { job: u32, result: ValueResult },
    complete_global: struct { job: u32, global: u32 },
    hit_global: struct { job: u32, target: u32, global: u32 },
    leave: struct { job: u32, parent: u32 },
};
pub const StampedEvent = struct { sequence: u64, event: Event };

pub const Span = struct { start: u32, len: u32 };
pub const Substitutions = struct {
    entries: []substitution_keys.Entry,
    spans: []Span,
    fn capture(allocator: Allocator, store: *const substitution_keys.Store) Allocator.Error!Substitutions {
        const entries = try allocator.dupe(substitution_keys.Entry, store.entries.items);
        errdefer allocator.free(entries);
        const spans = try allocator.alloc(Span, store.spans.items.len);
        for (store.spans.items, spans) |from, *to| to.* = .{ .start = from.start, .len = from.len };
        return .{ .entries = entries, .spans = spans };
    }
    pub fn get(self: *const Substitutions, id: u32) []const substitution_keys.Entry {
        if (id == 0) return &.{};
        const span = self.spans[id - 1];
        return self.entries[span.start..][0..span.len];
    }
    fn deinit(self: *Substitutions, allocator: Allocator) void {
        allocator.free(self.entries);
        allocator.free(self.spans);
    }
};
pub const Layouts = struct {
    nodes: []layout.Node,
    extra: []u32,
    effects: type_evidence.Effects.Snapshot,
    fn capture(allocator: Allocator, store: *const layout.Store) Allocator.Error!Layouts {
        const nodes = try allocator.dupe(layout.Node, store.nodes.items);
        errdefer allocator.free(nodes);
        const extra = try allocator.dupe(u32, store.extra.items);
        errdefer allocator.free(extra);
        return .{ .nodes = nodes, .extra = extra, .effects = try store.effects.copyOwned(allocator) };
    }
    pub fn children(self: *const Layouts, id: layout.Id) []const u32 {
        const node = self.nodes[id];
        return switch (node.tag) {
            .product => self.extra[node.a..][0..node.b],
            .record => self.extra[node.a..][0 .. @as(usize, node.b) * 2],
            .nominal => self.extra[node.c + 1 ..][0..self.extra[node.c]],
            else => &.{},
        };
    }
    fn deinit(self: *Layouts, allocator: Allocator) void {
        allocator.free(self.nodes);
        allocator.free(self.extra);
        self.effects.deinit(allocator);
    }
};
pub const Bridge = struct {
    nodes: []code_expectation.Node,
    extra: []u32,
    to: []u32,
    from: []u32,
    row_to: []u32,
    row_from: []u32,
    shapes: []u32,
    fn capture(allocator: Allocator, store: anytype) Allocator.Error!Bridge {
        const nodes = try allocator.dupe(code_expectation.Node, store.partial.nodes.items);
        errdefer allocator.free(nodes);
        const extra = try allocator.dupe(u32, store.partial.extra.items);
        errdefer allocator.free(extra);
        const to = try allocator.dupe(u32, store.to.items);
        errdefer allocator.free(to);
        const from = try allocator.dupe(u32, store.from.items);
        errdefer allocator.free(from);
        const row_to = try allocator.dupe(u32, store.row_to.items);
        errdefer allocator.free(row_to);
        const row_from = try allocator.dupe(u32, store.row_from.items);
        errdefer allocator.free(row_from);
        return .{ .nodes = nodes, .extra = extra, .to = to, .from = from, .row_to = row_to, .row_from = row_from, .shapes = try allocator.dupe(u32, store.shapes.items) };
    }
    fn deinit(self: *Bridge, allocator: Allocator) void {
        allocator.free(self.nodes);
        allocator.free(self.extra);
        allocator.free(self.to);
        allocator.free(self.from);
        allocator.free(self.row_to);
        allocator.free(self.row_from);
        allocator.free(self.shapes);
    }
};
pub const FieldLocation = struct { family: u64, tag: u32, name: u32, field: u32, len: u32 };
pub const Operation = struct { key: []u8, foreign: bool, runtime: u32 };
pub const OperationLocation = union(enum) { instruction: struct { function: u32, index: u32 }, word: u32 };
pub const OperationRelocation = struct { operation: u32, location: OperationLocation };
pub const Function = struct { request: Request, function: u32, result_template: ?u32 = null };
pub const Serialized = struct { value: core_eval.ValueId, ty: layout.Id, suspension: bool, address: u32 };
pub const RuntimeGlobal = struct { target: core.BindingRef, global: u32, initializer: u32, active: bool };
pub const Slot = struct { state: u8, traced: bool, value: core_eval.ValueId };
pub const RequestCell = struct { state: core_eval.ValueId, exit: core_eval.ValueId, status: core.RequestDecisionKind };
pub const RequestHandler = struct { callback: core_eval.ValueId, cell: u32, outer: provider_chain.Head };
pub const ArrayProof = struct { unit: u32, updates: []bool };
pub const DiscardProof = struct { unit: u32, unused: []bool };
pub const BodyPin = struct { unit: u32, catalog: u32, body: core.Body, module_stamp: [32]u8, stamp: [32]u8 };
pub const ModulePin = struct {
    unit: u32,
    /// Exact immutable caller-owned module, retained until replay is finished.
    module: *const core.Module,
    canonical_path: []u8,
    stamp: [32]u8,
};
pub const Pools = struct {
    /// This run's namespaces are owned below; there is deliberately no portable
    /// validity key. Rechecking edited-source dependencies is a later gate.
    project_identity: bool,
    /// Monotone only within this Context owner, never a cross-owner identity.
    generation: u64 = 0,
    identity: ?IdentityMetadata = null,
    modules: []ModulePin,
    dependency_certificate: ?@import("dependency_certificate.zig").Certificate = null,
    bodies: []BodyPin,
    layouts: Layouts,
    evaluator: core_eval.Snapshot,
    rows: Substitutions,
    templates: Substitutions,
    static_values: Substitutions = .{ .entries = &.{}, .spans = &.{} },
    captures: []CapturedTemplate,
    bridge: ?Bridge = null,
    field_locations: []FieldLocation,
    field_locations_stamp: [32]u8,
    operations: []Operation,
    operation_relocations: []OperationRelocation,
    operations_finalized: bool,
    functions: []Function,
    serialized: []Serialized,
    runtime_globals: []RuntimeGlobal,
    runtime_order: []u32,
    binding_offsets: []usize,
    node_offsets: []usize,
    slots: []Slot,
    visited_nodes: []bool,
    provider_frames: []provider_chain.Frame,
    provider_cells: []provider_chain.Cell,
    request_cells: []RequestCell,
    request_handlers: []RequestHandler,
    break_values: []core_eval.ValueId,
    array_proofs: []ArrayProof,
    discard_proofs: []DiscardProof,
    evaluator_steps: usize,
    evaluator_demanded: usize,
    evaluator_traced_bodies: usize,
    evaluator_traced_nodes: usize,
    pub fn deinit(self: *Pools, allocator: Allocator) void {
        if (self.dependency_certificate) |*certificate| certificate.deinit(allocator);
        if (self.identity) |*identity| identity.deinit(allocator);
        for (self.modules) |module| allocator.free(module.canonical_path);
        allocator.free(self.modules);
        allocator.free(self.bodies);
        self.layouts.deinit(allocator);
        self.evaluator.deinit(allocator);
        self.rows.deinit(allocator);
        self.templates.deinit(allocator);
        self.static_values.deinit(allocator);
        allocator.free(self.captures);
        if (self.bridge) |*bridge| bridge.deinit(allocator);
        allocator.free(self.field_locations);
        for (self.operations) |operation| allocator.free(operation.key);
        allocator.free(self.operations);
        allocator.free(self.operation_relocations);
        allocator.free(self.functions);
        allocator.free(self.serialized);
        allocator.free(self.runtime_globals);
        allocator.free(self.runtime_order);
        allocator.free(self.binding_offsets);
        allocator.free(self.node_offsets);
        allocator.free(self.slots);
        allocator.free(self.visited_nodes);
        allocator.free(self.provider_frames);
        allocator.free(self.provider_cells);
        allocator.free(self.request_cells);
        allocator.free(self.request_handlers);
        allocator.free(self.break_values);
        for (self.array_proofs) |proof| allocator.free(proof.updates);
        allocator.free(self.array_proofs);
        for (self.discard_proofs) |proof| allocator.free(proof.unused);
        allocator.free(self.discard_proofs);
        self.* = undefined;
    }
};

pub const Context = struct {
    allocator: Allocator,
    /// Zero is the output root. The recorder borrows this field only while the
    /// Context is alive; no such pointer is part of the finished artifact.
    active_job: u32 = 0,
    /// Shared with the emission recorder while recording, then wholly owned.
    clock: u64 = 0,
    jobs: std.ArrayList(Job) = .empty,
    events: std.ArrayList(StampedEvent) = .empty,
    function_jobs: std.ArrayList(u32) = .empty,
    global_jobs: std.ArrayList(u32) = .empty,
    pools: ?Pools = null,
    principal_queries: @import("principal_query.zig").Table = .{},
    specialization_queries: @import("selected_query.zig").Table = .{},
    independent_calls: std.ArrayList(@import("independent_call_proof.zig").Record) = .empty,
    refinement_queries: @import("refinement_receipt.zig").Table = .{},
    pub fn init(allocator: Allocator) Context {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Context) void {
        self.principal_queries.deinit(self.allocator);
        self.specialization_queries.deinit(self.allocator);
        self.refinement_queries.deinit(self.allocator);
        for (self.independent_calls.items) |*record| record.deinit(self.allocator);
        self.independent_calls.deinit(self.allocator);
        for (self.jobs.items) |*job| job.deinit(self.allocator);
        self.jobs.deinit(self.allocator);
        self.events.deinit(self.allocator);
        self.function_jobs.deinit(self.allocator);
        self.global_jobs.deinit(self.allocator);
        if (self.pools) |*pools| pools.deinit(self.allocator);
        self.* = undefined;
    }
    pub fn enter(self: *Context, request: Request) Allocator.Error!Scope {
        if (self.jobs.items.len == std.math.maxInt(u32)) return error.OutOfMemory;
        // Reserve leave storage for every live scope. Deinit cannot allocate.
        const live_depth = self.depth();
        try self.jobs.ensureUnusedCapacity(self.allocator, 1);
        try self.events.ensureUnusedCapacity(self.allocator, live_depth + 2);
        const id: u32 = @intCast(self.jobs.items.len + 1);
        const parent = self.active_job;
        self.jobs.appendAssumeCapacity(.{ .parent = parent, .request = request });
        self.appendAssumeCapacity(.{ .enter = id });
        self.active_job = id;
        return .{ .context = self, .id = id, .parent = parent };
    }
    pub fn requireFreshCode(self: *Context) void {
        if (self.active_job != 0) self.jobs.items[self.active_job - 1].reusable = false;
    }
    pub fn readInlineBody(self: *Context, target: core.BindingRef) Allocator.Error!void {
        if (self.active_job == 0) return;
        const reads = &self.jobs.items[self.active_job - 1].inline_bodies;
        for (reads.items) |read| if (std.meta.eql(read, target)) return;
        try reads.append(self.allocator, target);
    }
    pub fn readStaticValue(self: *Context, target: core.BindingRef, value: core_eval.ValueId) Allocator.Error!void {
        if (self.active_job == 0) return;
        const reads = &self.jobs.items[self.active_job - 1].static_reads;
        for (reads.items) |read| if (std.meta.eql(read.target, target) and read.value == value) return;
        try reads.append(self.allocator, .{ .target = target, .value = value });
    }
    pub fn hasStaticValues(self: *const Context) bool {
        return self.active_job != 0 and self.jobs.items[self.active_job - 1].hasStaticValues();
    }
    fn depth(self: *const Context) usize {
        var id = self.active_job;
        var count: usize = 0;
        while (id != 0) {
            id = self.jobs.items[id - 1].parent;
            count += 1;
        }
        return count;
    }
    fn append(self: *Context, event: Event) Allocator.Error!void {
        try self.events.ensureUnusedCapacity(self.allocator, self.depth() + 1);
        self.appendAssumeCapacity(event);
    }
    fn appendAssumeCapacity(self: *Context, event: Event) void {
        self.events.appendAssumeCapacity(.{ .sequence = self.clock, .event = event });
        self.clock += 1;
    }
    fn functionCapacity(self: *Context, function: u32) Allocator.Error!void {
        if (function >= self.function_jobs.items.len) try self.function_jobs.appendNTimes(self.allocator, 0, @as(usize, function) + 1 - self.function_jobs.items.len);
    }
    /// Publish only after every pool capture succeeds. A failed capture leaves
    /// the prior graph usable and can be retried; mutable Generator owners do
    /// not escape through the metadata. Immutable Core is the explicit pin.
    pub fn capturePools(self: *Context, generator: anytype, identity: ?runtime_identity.View) Allocator.Error!void {
        return self.capturePoolsWithStamps(generator, identity, null);
    }
    pub fn capturePoolsWithStamps(self: *Context, generator: anytype, identity: ?runtime_identity.View, memo: ?*ModuleStamps) Allocator.Error!void {
        std.debug.assert(self.active_job == 0);
        var candidate = try capture(self.allocator, generator, identity, memo);
        errdefer candidate.deinit(self.allocator);
        candidate.generation = if (self.pools) |previous| previous.generation + 1 else 1;
        if (self.pools) |*previous| previous.deinit(self.allocator);
        self.pools = candidate;
    }
    /// Copies source-owned prepass facts into the unpublished candidate. The
    /// enclosing Capture owns their semantic graph only after backend success.
    pub fn recordPrincipal(self: *Context, target: core.BindingRef, options: core_eval.Options, solved: core_eval.SolvedEvidence, inputs: ?*const @import("principal_inputs.zig").Key) Allocator.Error!void {
        if (solved.selected.len != 0) return;
        const query = @import("principal_query.zig");
        var cursor = self.principal_queries.candidates(query.fingerprint(target), .oldest_first);
        while (cursor.next()) |position| if (std.meta.eql(self.principal_queries.records.items[position].key.target, target)) return;
        const mappings = try self.allocator.dupe(type_evidence.Mapping, solved.types);
        var owned = true;
        defer if (owned) self.allocator.free(mappings);
        const rows = try self.allocator.dupe(type_evidence.RowMapping, solved.rows);
        defer if (owned) self.allocator.free(rows);
        const input_key = if (inputs) |observed| try observed.clone(self.allocator) else null;
        var builder = query.Table.begin(self.allocator, .{ .target = target, .options = options });
        defer builder.abort();
        builder.read(.{ .inputs = input_key });
        builder.stage(.{ .types = mappings, .rows = rows });
        owned = false;
        var candidate = builder.complete() orelse return;
        defer candidate.abort();
        const prepared = try self.principal_queries.prepare(self.allocator, &candidate) orelse return;
        _ = self.principal_queries.publish(prepared, &candidate);
    }
};
pub const PrincipalProof = @import("principal_query.zig").Table.Record;

pub const Scope = struct {
    context: *Context,
    id: u32,
    parent: u32,
    pub fn hit(self: *Scope, function: u32) Allocator.Error!void {
        const context = self.context;
        std.debug.assert(context.active_job == self.id);
        try context.functionCapacity(function);
        const target = context.function_jobs.items[function];
        try context.append(.{ .hit = .{ .job = self.id, .target = target, .function = function } });
        const job = &context.jobs.items[self.id - 1];
        job.function = function;
        job.target_job = target;
        job.state = .hit;
    }
    pub fn reserve(self: *Scope, function: u32) Allocator.Error!void {
        const context = self.context;
        std.debug.assert(context.active_job == self.id);
        try context.functionCapacity(function);
        std.debug.assert(context.function_jobs.items[function] == 0);
        try context.append(.{ .reserve = .{ .job = self.id, .function = function } });
        context.function_jobs.items[function] = self.id;
        const job = &context.jobs.items[self.id - 1];
        job.function = function;
        job.state = .reserved;
    }
    pub fn solved(self: *Scope, mappings: []const layout.Mapping, rows: []const layout.RowMapping, templates: []const substitution_keys.Entry) Allocator.Error!void {
        const context = self.context;
        std.debug.assert(context.active_job == self.id);
        const owned_mappings = try context.allocator.dupe(layout.Mapping, mappings);
        errdefer context.allocator.free(owned_mappings);
        const owned_rows = try context.allocator.dupe(layout.RowMapping, rows);
        errdefer context.allocator.free(owned_rows);
        const owned_templates = try context.allocator.dupe(substitution_keys.Entry, templates);
        errdefer context.allocator.free(owned_templates);
        try context.append(.{ .solved = self.id });
        const job = &context.jobs.items[self.id - 1];
        context.allocator.free(job.mappings);
        context.allocator.free(job.rows);
        context.allocator.free(job.templates);
        job.mappings = owned_mappings;
        job.rows = owned_rows;
        job.templates = owned_templates;
        job.solved = true;
    }
    pub fn complete(self: *Scope, function: u32, result_template: ?u32) Allocator.Error!void {
        const context = self.context;
        std.debug.assert(context.active_job == self.id);
        try context.functionCapacity(function);
        const owner = context.function_jobs.items[function];
        std.debug.assert(owner == 0 or owner == self.id);
        try context.append(.{ .complete = .{ .job = self.id, .function = function, .result_template = result_template } });
        context.function_jobs.items[function] = self.id;
        const job = &context.jobs.items[self.id - 1];
        job.function = function;
        job.result_template = result_template;
        job.state = .complete;
    }
    pub fn completeValue(self: *Scope, value: core_eval.ValueId, shape: layout.Id) Allocator.Error!void {
        const context = self.context;
        std.debug.assert(context.active_job == self.id);
        const result: ValueResult = .{ .value = value, .layout = shape };
        try context.append(.{ .complete_value = .{ .job = self.id, .result = result } });
        const job = &context.jobs.items[self.id - 1];
        job.value = result;
        job.state = .complete;
    }
    pub fn completeGlobal(self: *Scope, global: u32) Allocator.Error!void {
        const context = self.context;
        std.debug.assert(context.active_job == self.id);
        if (global >= context.global_jobs.items.len) try context.global_jobs.appendNTimes(context.allocator, 0, @as(usize, global) + 1 - context.global_jobs.items.len);
        std.debug.assert(context.global_jobs.items[global] == 0);
        try context.append(.{ .complete_global = .{ .job = self.id, .global = global } });
        context.global_jobs.items[global] = self.id;
        const job = &context.jobs.items[self.id - 1];
        job.global = global;
        job.state = .complete;
    }
    pub fn hitGlobal(self: *Scope, global: u32) Allocator.Error!void {
        const context = self.context;
        std.debug.assert(context.active_job == self.id);
        const target = if (global < context.global_jobs.items.len) context.global_jobs.items[global] else 0;
        try context.append(.{ .hit_global = .{ .job = self.id, .target = target, .global = global } });
        const job = &context.jobs.items[self.id - 1];
        job.global = global;
        job.target_job = target;
        job.state = .hit;
    }
    pub fn deinit(self: *Scope) void {
        const context = self.context;
        std.debug.assert(context.active_job == self.id);
        const job = &context.jobs.items[self.id - 1];
        if (job.state == .pending or job.state == .reserved) job.state = .failed;
        context.appendAssumeCapacity(.{ .leave = .{ .job = self.id, .parent = self.parent } });
        context.active_job = self.parent;
        self.* = undefined;
    }
};

fn copyIdentity(allocator: Allocator, view: runtime_identity.View) Allocator.Error!IdentityMetadata {
    const bytes = try allocator.dupe(u8, view.bytes);
    errdefer allocator.free(bytes);
    const symbols = try allocator.dupe(@typeInfo(@TypeOf(view.symbols)).pointer.child, view.symbols);
    errdefer allocator.free(symbols);
    return .{ .bytes = bytes, .symbols = symbols, .owners = try allocator.dupe(@typeInfo(@TypeOf(view.owners)).pointer.child, view.owners) };
}
/// Deterministic structural stamps exclude pointers and padding. These qualify
/// one pinned run only; stamps do not establish edited-source validity.
/// Buffering is the qualified production implementation. Differential controls
/// and counters belong to an explicit caller-owned context.
pub const stamp_buffer_bytes = 4096;
pub const StampCounts = struct {
    stamps: usize = 0,
    bytes: usize = 0,
    input_updates: usize = 0,
    hash_updates: usize = 0,
    buffer_flushes: usize = 0,
    direct_chunks: usize = 0,
    pub fn delta(after: StampCounts, before: StampCounts) StampCounts {
        var result: StampCounts = .{};
        inline for (@typeInfo(StampCounts).@"struct".field_names) |name| @field(result, name) = @field(after, name) - @field(before, name);
        return result;
    }
};
pub const Stamping = struct {
    algorithm: enum { buffered, reference } = .buffered,
    counts: ?*StampCounts = null,

    pub fn stamp(self: Stamping, value: anytype) [32]u8 {
        if (self.counts) |counts| return switch (self.algorithm) {
            .buffered => measuredStamp(value, true, counts),
            .reference => measuredStamp(value, false, counts),
        };
        return switch (self.algorithm) {
            .buffered => stampBuffered(value),
            .reference => stampReference(value),
        };
    }
};
pub fn stamp(value: anytype) [32]u8 {
    return (Stamping{}).stamp(value);
}
/// Frozen original stream/digest algorithm, used as the private reference.
pub fn stampReference(value: anytype) [32]u8 {
    var hash = Hash.init(.{});
    hash.update("BLOT-PINNED-ARTIFACT-1");
    structural.hash(&hash, value);
    var result: [32]u8 = undefined;
    hash.final(&result);
    return result;
}
/// Only batching changes. Scalars keep their original primitive asBytes
/// representation; structs are visited field by field, never copied wholesale.
fn BufferedHash(comptime counted: bool) type {
    return struct {
        hash: Hash = Hash.init(.{}),
        bytes: [stamp_buffer_bytes]u8 = undefined,
        len: usize = 0,
        counts: StampCounts = .{},
        fn flush(self: *@This()) void {
            if (self.len == 0) return;
            self.hash.update(self.bytes[0..self.len]);
            if (counted) {
                self.counts.hash_updates += 1;
                self.counts.buffer_flushes += 1;
            }
            self.len = 0;
        }
        pub inline fn update(self: *@This(), source: []const u8) void {
            if (counted) {
                self.counts.input_updates += 1;
                self.counts.bytes += source.len;
            }
            if (source.len >= self.bytes.len) {
                self.flush();
                self.hash.update(source);
                if (counted) {
                    self.counts.hash_updates += 1;
                    self.counts.direct_chunks += 1;
                }
                return;
            }
            var remaining = source;
            while (remaining.len != 0) {
                const take = @min(remaining.len, self.bytes.len - self.len);
                @memcpy(self.bytes[self.len..][0..take], remaining[0..take]);
                self.len += take;
                remaining = remaining[take..];
                if (self.len == self.bytes.len) self.flush();
            }
        }
        fn final(self: *@This(), result: *[32]u8) void {
            self.flush();
            self.hash.final(result);
        }
    };
}
const CountedHash = struct {
    hash: Hash = Hash.init(.{}),
    counts: StampCounts = .{},
    pub inline fn update(self: *CountedHash, bytes: []const u8) void {
        self.counts.bytes += bytes.len;
        self.counts.input_updates += 1;
        self.counts.hash_updates += 1;
        self.hash.update(bytes);
    }
    fn final(self: *CountedHash, result: *[32]u8) void {
        self.hash.final(result);
    }
};
pub fn stampBuffered(value: anytype) [32]u8 {
    var hash: BufferedHash(false) = .{};
    hash.update("BLOT-PINNED-ARTIFACT-1");
    structural.hash(&hash, value);
    var result: [32]u8 = undefined;
    hash.final(&result);
    return result;
}
fn measuredStamp(value: anytype, comptime buffered: bool, counts: *StampCounts) [32]u8 {
    var hash: if (buffered) BufferedHash(true) else CountedHash = .{};
    hash.update("BLOT-PINNED-ARTIFACT-1");
    structural.hash(&hash, value);
    var result: [32]u8 = undefined;
    hash.final(&result);
    hash.counts.stamps = 1;
    inline for (@typeInfo(StampCounts).@"struct".field_names) |name| @field(counts, name) += @field(hash.counts, name);
    return result;
}
/// One backend invocation owns this memo. All current/previous Core buffers
/// must remain alive and immutable until deinit; nothing is retained in a
/// published artifact. Every invocation freshly hashes or exactly compares its
/// inputs before reuse.
pub const ModuleStamps = struct {
    allocator: Allocator,
    current: []const core.Module,
    previous: ?*const Pools,
    compare_contents: bool = false,
    entries: std.ArrayList(Entry) = .empty,
    computed: usize = 0,
    reused: usize = 0,
    comparisons: usize = 0,
    /// Distinct immutable views admitted by complete stamp-input equality.
    copied: usize = 0,
    const Entry = struct { module: core.Module, digest: [32]u8 };

    pub fn deinit(self: *ModuleStamps) void {
        self.entries.deinit(self.allocator);
        self.* = undefined;
    }
    fn owns(self: *const ModuleStamps, module: *const core.Module) bool {
        for (self.current) |*owned| if (owned == module) return true;
        if (self.previous) |old| for (old.modules) |pin| {
            if (pin.module == module) return true;
        };
        return false;
    }
    /// Let an existing structural admission pass share this exact comparison.
    /// The left input must already have been hashed in this invocation. Success
    /// proves complete Core equality and records the right immutable view;
    /// it grants no namespace, dependency, evidence or code admission.
    pub fn proveSame(self: *ModuleStamps, left: *const core.Module, right: *const core.Module) Allocator.Error!bool {
        if (!self.compare_contents or !self.owns(left) or !self.owns(right)) return false;
        const digest = for (self.entries.items) |entry| {
            if (sameStorage(entry.module, left.*)) break entry.digest;
        } else return false;
        if (sameStorage(left.*, right.*)) return true;
        self.comparisons += 1;
        if (!sameStampValue(left.*, right.*)) return false;
        try self.entries.append(self.allocator, .{ .module = right.*, .digest = digest });
        self.reused += 1;
        self.copied += 1;
        return true;
    }
    pub fn get(self: *ModuleStamps, module: *const core.Module) Allocator.Error![32]u8 {
        // Unpaired owners keep the ordinary path. Pointer equality here only
        // identifies buffers covered by this invocation's immutable borrow.
        if (!self.owns(module)) return stamp(module.*);
        for (self.entries.items) |*entry| if (sameStorage(entry.module, module.*)) {
            self.reused += 1;
            return entry.digest;
        };
        if (self.compare_contents) for (self.entries.items) |entry| {
            if (entry.module.unit != module.unit) continue;
            self.comparisons += 1;
            if (!sameStampValue(entry.module, module.*)) continue;
            // Both views belong to this immutable borrow. Equality covers the
            // entire stamp input, not just a type/catalog projection. Record
            // the copied view so later requests need only compare its header.
            try self.entries.append(self.allocator, .{ .module = module.*, .digest = entry.digest });
            self.reused += 1;
            self.copied += 1;
            return entry.digest;
        };
        const digest = stamp(module.*);
        try self.entries.append(self.allocator, .{ .module = module.*, .digest = digest });
        self.computed += 1;
        return digest;
    }
};

fn comparableStampBytes(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .int, .@"enum" => std.meta.hasUniqueRepresentation(T),
        .float => @bitSizeOf(T) == @sizeOf(T) * 8,
        .array => |array| comparableStampBytes(array.child) and std.meta.hasUniqueRepresentation(T),
        .@"struct" => |s| blk: {
            if (!std.meta.hasUniqueRepresentation(T)) break :blk false;
            for (s.field_names) |name| if (!comparableStampBytes(@FieldType(T, name))) break :blk false;
            break :blk true;
        },
        else => false,
    };
}
/// Exact equality of the structural stamp stream. Padding and addresses are
/// excluded, floats retain their bits, and slice order/length remain visible.
fn sameStampValue(left: anytype, right: @TypeOf(left)) bool {
    const T = @TypeOf(left);
    return switch (@typeInfo(T)) {
        .pointer => |p| blk: {
            if (p.size != .slice) @compileError("Artifact stamps require structural slices");
            if (left.len != right.len) break :blk false;
            if (left.len == 0 or left.ptr == right.ptr) break :blk true;
            if (comptime comparableStampBytes(p.child)) break :blk std.mem.eql(u8, std.mem.sliceAsBytes(left), std.mem.sliceAsBytes(right));
            for (left, right) |a, b| if (!sameStampValue(a, b)) break :blk false;
            break :blk true;
        },
        .array => blk: {
            for (left, right) |a, b| if (!sameStampValue(a, b)) break :blk false;
            break :blk true;
        },
        .@"struct" => |s| blk: {
            inline for (s.field_names) |name| if (!sameStampValue(@field(left, name), @field(right, name))) break :blk false;
            break :blk true;
        },
        .optional => if (left) |a| if (right) |b| sameStampValue(a, b) else false else right == null,
        .@"union" => if (std.meta.activeTag(left) != std.meta.activeTag(right)) false else switch (left) {
            inline else => |value, tag| sameStampValue(value, @field(right, @tagName(tag))),
        },
        .float => std.mem.eql(u8, std.mem.asBytes(&left), std.mem.asBytes(&right)),
        .int, .bool, .@"enum" => left == right,
        .void => true,
        else => @compileError("Unsupported structural stamp value"),
    };
}

test "exact stamp input equality excludes padding and preserves float bits and nested values" {
    const Padded = extern struct { first: u8, number: u64, last: u16 };
    var left: [3]Padded = undefined;
    var right: [3]Padded = undefined;
    @memset(std.mem.asBytes(&left), 0xa5);
    @memset(std.mem.asBytes(&right), 0x5a);
    for (&left, &right, 0..) |*a, *b, index| {
        a.first = @intCast(index);
        a.number = 0xfedcba9876543200 + index;
        a.last = @intCast(index * 100);
        b.first = a.first;
        b.number = a.number;
        b.last = a.last;
    }
    try std.testing.expect(sameStampValue(@as([]const Padded, &left), @as([]const Padded, &right)));
    try std.testing.expectEqual(stampReference(@as([]const Padded, &left)), stampReference(@as([]const Padded, &right)));
    for ([_]u32{ 0, 0x80000000, 0x7f800000, 0x7fc00001, 0x7fc00002 }) |a| {
        for ([_]u32{ 0, 0x80000000, 0x7f800000, 0x7fc00001, 0x7fc00002 }) |b| {
            const xs = [_]f32{@bitCast(a)};
            const ys = [_]f32{@bitCast(b)};
            try std.testing.expectEqual(a == b, sameStampValue(@as([]const f32, &xs), @as([]const f32, &ys)));
            try std.testing.expectEqual(a == b, std.mem.eql(u8, &stampReference(xs), &stampReference(ys)));
        }
    }
    const Choice = union(enum) { absent: void, value: ?[]const Padded };
    const first: Choice = .{ .value = &left };
    const second: Choice = .{ .value = &right };
    try std.testing.expect(sameStampValue(first, second));
    try std.testing.expect(!sameStampValue(first, Choice{ .value = null }));
    try std.testing.expect(!sameStampValue(first, Choice{ .absent = {} }));
    right[2].number ^= 1;
    try std.testing.expect(!sameStampValue(first, second));
}

/// Compare every header field and slice boundary, never padding or contents.
/// A hit means the exact same immutable bytes will be traversed. Distinct
/// buffers with equal contents intentionally miss; this is no semantic key.
fn sameStorage(left: anytype, right: @TypeOf(left)) bool {
    return switch (@typeInfo(@TypeOf(left))) {
        .pointer => |p| blk: {
            if (p.size != .slice) @compileError("Core stamp views require slices");
            break :blk left.len == right.len and (left.len == 0 or left.ptr == right.ptr);
        },
        .@"struct" => |s| blk: {
            inline for (s.field_names) |name| if (!sameStorage(@field(left, name), @field(right, name))) break :blk false;
            break :blk true;
        },
        .array => blk: {
            for (left, right) |a, b| if (!sameStorage(a, b)) break :blk false;
            break :blk true;
        },
        .optional => if (left) |a| if (right) |b| sameStorage(a, b) else false else right == null,
        .@"union" => if (std.meta.activeTag(left) != std.meta.activeTag(right)) false else switch (left) {
            inline else => |a, tag| sameStorage(a, @field(right, @tagName(tag))),
        },
        .float => std.mem.eql(u8, std.mem.asBytes(&left), std.mem.asBytes(&right)),
        .int, .bool, .@"enum" => left == right,
        .void => true,
        else => @compileError("Unsupported Core stamp view"),
    };
}

pub fn moduleStamp(module: *const core.Module, memo: ?*ModuleStamps) Allocator.Error![32]u8 {
    return if (memo) |cache| cache.get(module) else stamp(module.*);
}

fn capture(allocator: Allocator, generator: anytype, identity: ?runtime_identity.View, memo: ?*ModuleStamps) Allocator.Error!Pools {
    var names: ?IdentityMetadata = null;
    if (identity) |view| names = try copyIdentity(allocator, view);
    errdefer if (names) |*value| value.deinit(allocator);
    const modules = try allocator.alloc(ModulePin, generator.units.len);
    var module_count: usize = 0;
    errdefer {
        for (modules[0..module_count]) |module| allocator.free(module.canonical_path);
        allocator.free(modules);
    }
    var bodies: std.ArrayList(BodyPin) = .empty;
    errdefer bodies.deinit(allocator);
    for (generator.units, modules, 0..) |*module, *pin, index| {
        const unit: u32 = if (module.unit != 0) module.unit else @intCast(index + 1);
        const path = if (names) |*view| view.view().owner(unit) orelse "" else "";
        pin.* = .{ .unit = unit, .module = module, .canonical_path = try allocator.dupe(u8, path), .stamp = undefined };
        module_count += 1;
        pin.stamp = try moduleStamp(module, memo);
        for (module.bodies, 0..) |body, catalog| try bodies.append(allocator, .{ .unit = unit, .catalog = @intCast(catalog), .body = body, .module_stamp = pin.stamp, .stamp = stamp(.{ pin.stamp, body }) });
    }
    var layouts = try Layouts.capture(allocator, &generator.layouts);
    errdefer layouts.deinit(allocator);
    var evaluator = try generator.evaluator.copySnapshotMeasured(allocator);
    errdefer evaluator.deinit(allocator);
    var rows = try Substitutions.capture(allocator, &generator.row_keys);
    errdefer rows.deinit(allocator);
    var templates = try Substitutions.capture(allocator, &generator.template_keys);
    errdefer templates.deinit(allocator);
    var static_values = try Substitutions.capture(allocator, &generator.static_keys);
    errdefer static_values.deinit(allocator);
    const captures = try allocator.dupe(CapturedTemplate, generator.template_catalog.items);
    errdefer allocator.free(captures);
    var bridge: ?Bridge = if (generator.representation_bridge) |*store| try Bridge.capture(allocator, store) else null;
    errdefer if (bridge) |*value| value.deinit(allocator);
    const locations = try allocator.alloc(FieldLocation, generator.evaluator.field_locations.count());
    errdefer allocator.free(locations);
    var fields = generator.evaluator.field_locations.iterator();
    var field_index: usize = 0;
    while (fields.next()) |entry| : (field_index += 1) locations[field_index] = .{ .family = entry.key_ptr.family, .tag = entry.key_ptr.tag, .name = entry.key_ptr.name, .field = entry.value_ptr.field, .len = entry.value_ptr.len };
    std.mem.sortUnstable(FieldLocation, locations, {}, struct {
        fn less(_: void, left: FieldLocation, right: FieldLocation) bool {
            if (left.family != right.family) return left.family < right.family;
            if (left.tag != right.tag) return left.tag < right.tag;
            return left.name < right.name;
        }
    }.less);
    const operations = try allocator.alloc(Operation, generator.runtime_operations.entries.items.len);
    var operation_count: usize = 0;
    errdefer {
        for (operations[0..operation_count]) |operation| allocator.free(operation.key);
        allocator.free(operations);
    }
    for (generator.runtime_operations.entries.items, operations) |entry, *operation| {
        operation.* = .{ .key = try allocator.dupe(u8, entry.key), .foreign = entry.foreign, .runtime = entry.runtime };
        operation_count += 1;
    }
    const relocations = try allocator.alloc(OperationRelocation, generator.runtime_operations.relocations.items.len);
    errdefer allocator.free(relocations);
    for (generator.runtime_operations.relocations.items, relocations) |entry, *relocation| relocation.* = .{ .operation = entry.operation, .location = switch (entry.location) {
        .instruction => |location| .{ .instruction = .{ .function = location.function, .index = location.index } },
        .word => |address| .{ .word = address },
    } };
    var functions: std.ArrayList(Function) = .empty;
    errdefer functions.deinit(allocator);
    var named = generator.instances.iterator();
    while (named.next()) |entry| try functions.append(allocator, .{ .request = .{ .named = entry.key_ptr.* }, .function = entry.value_ptr.*, .result_template = generator.template_results.get(entry.key_ptr.*) });
    var closures = generator.closures.iterator();
    while (closures.next()) |entry| try functions.append(allocator, .{ .request = .{ .closure = entry.key_ptr.* }, .function = entry.value_ptr.*, .result_template = generator.closure_template_results.get(entry.key_ptr.*) });
    var callables = generator.callables.iterator();
    while (callables.next()) |entry| try functions.append(allocator, .{ .request = .{ .callable = entry.key_ptr.* }, .function = entry.value_ptr.* });
    var constructors = generator.constructor_functions.iterator();
    while (constructors.next()) |entry| try functions.append(allocator, .{ .request = .{ .constructor = entry.key_ptr.* }, .function = entry.value_ptr.* });
    var primitives = generator.primitive_functions.iterator();
    while (primitives.next()) |entry| try functions.append(allocator, .{ .request = .{ .primitive = entry.key_ptr.* }, .function = entry.value_ptr.* });
    var wrappers = generator.operation_functions.iterator();
    while (wrappers.next()) |entry| try functions.append(allocator, .{ .request = .{ .operation = entry.key_ptr.* }, .function = entry.value_ptr.* });
    var hosts = generator.host_functions.iterator();
    while (hosts.next()) |entry| try functions.append(allocator, .{ .request = .{ .host = entry.key_ptr.* }, .function = entry.value_ptr.* });
    std.mem.sortUnstable(Function, functions.items, {}, struct {
        fn less(_: void, left: Function, right: Function) bool {
            return left.function < right.function;
        }
    }.less);
    const serialized = try allocator.alloc(Serialized, generator.serialized.count());
    errdefer allocator.free(serialized);
    var values = generator.serialized.iterator();
    var value_index: usize = 0;
    while (values.next()) |entry| : (value_index += 1) serialized[value_index] = .{ .value = entry.key_ptr.value, .ty = entry.key_ptr.ty, .suspension = entry.key_ptr.suspension, .address = entry.value_ptr.* };
    const globals = try allocator.alloc(RuntimeGlobal, generator.runtime_globals.count());
    errdefer allocator.free(globals);
    var runtime_globals = generator.runtime_globals.iterator();
    var global_index: usize = 0;
    while (runtime_globals.next()) |entry| : (global_index += 1) globals[global_index] = .{ .target = entry.key_ptr.*, .global = entry.value_ptr.global, .initializer = entry.value_ptr.initializer, .active = entry.value_ptr.active };
    const runtime_order = try allocator.dupe(u32, generator.runtime_order.items);
    errdefer allocator.free(runtime_order);
    const binding_offsets = try allocator.dupe(usize, generator.evaluator.binding_offsets);
    errdefer allocator.free(binding_offsets);
    const node_offsets = try allocator.dupe(usize, generator.evaluator.node_offsets);
    errdefer allocator.free(node_offsets);
    const slots = try allocator.alloc(Slot, generator.evaluator.slots.len);
    errdefer allocator.free(slots);
    for (generator.evaluator.slots, slots) |from, *to| to.* = .{ .state = @intCast(@backingInt(from.state)), .traced = from.traced, .value = from.value };
    const visited_nodes = try allocator.dupe(bool, generator.evaluator.visited_nodes);
    errdefer allocator.free(visited_nodes);
    const provider_frames = try allocator.dupe(provider_chain.Frame, generator.evaluator.providers.frames.items);
    errdefer allocator.free(provider_frames);
    const provider_cells = try allocator.dupe(provider_chain.Cell, generator.evaluator.providers.cells.items);
    errdefer allocator.free(provider_cells);
    const request_cells = try allocator.alloc(RequestCell, generator.evaluator.request_cells.items.len);
    errdefer allocator.free(request_cells);
    for (generator.evaluator.request_cells.items, request_cells) |from, *to| to.* = .{ .state = from.state, .exit = from.exit, .status = from.status };
    const request_handlers = try allocator.alloc(RequestHandler, generator.evaluator.request_handlers.items.len);
    errdefer allocator.free(request_handlers);
    for (generator.evaluator.request_handlers.items, request_handlers) |from, *to| to.* = .{ .callback = from.callback, .cell = from.cell, .outer = from.outer };
    const break_values = try allocator.dupe(core_eval.ValueId, generator.evaluator.break_values.items);
    errdefer allocator.free(break_values);
    const array_proofs = try allocator.alloc(ArrayProof, generator.array_proofs.count());
    var array_count: usize = 0;
    errdefer {
        for (array_proofs[0..array_count]) |proof| allocator.free(proof.updates);
        allocator.free(array_proofs);
    }
    var arrays = generator.array_proofs.iterator();
    while (arrays.next()) |entry| {
        array_proofs[array_count] = .{ .unit = entry.key_ptr.*, .updates = try allocator.dupe(bool, entry.value_ptr.updates) };
        array_count += 1;
    }
    const discard_proofs = try allocator.alloc(DiscardProof, generator.discard_proofs.count());
    var discard_count: usize = 0;
    errdefer {
        for (discard_proofs[0..discard_count]) |proof| allocator.free(proof.unused);
        allocator.free(discard_proofs);
    }
    var discards = generator.discard_proofs.iterator();
    while (discards.next()) |entry| {
        discard_proofs[discard_count] = .{ .unit = entry.key_ptr.*, .unused = try allocator.dupe(bool, entry.value_ptr.unused) };
        discard_count += 1;
    }
    const owned_functions = try functions.toOwnedSlice(allocator);
    errdefer allocator.free(owned_functions);
    const owned_bodies = try bodies.toOwnedSlice(allocator);
    errdefer allocator.free(owned_bodies);
    return .{
        .project_identity = identity != null,
        .identity = names,
        .modules = modules,
        .bodies = owned_bodies,
        .layouts = layouts,
        .evaluator = evaluator,
        .rows = rows,
        .templates = templates,
        .static_values = static_values,
        .captures = captures,
        .bridge = bridge,
        .field_locations = locations,
        .field_locations_stamp = stamp(locations),
        .operations = operations,
        .operation_relocations = relocations,
        .operations_finalized = generator.runtime_operations.finalized,
        .functions = owned_functions,
        .serialized = serialized,
        .runtime_globals = globals,
        .runtime_order = runtime_order,
        .binding_offsets = binding_offsets,
        .node_offsets = node_offsets,
        .slots = slots,
        .visited_nodes = visited_nodes,
        .provider_frames = provider_frames,
        .provider_cells = provider_cells,
        .request_cells = request_cells,
        .request_handlers = request_handlers,
        .break_values = break_values,
        .array_proofs = array_proofs,
        .discard_proofs = discard_proofs,
        .evaluator_steps = generator.evaluator.steps,
        .evaluator_demanded = generator.evaluator.demanded,
        .evaluator_traced_bodies = generator.evaluator.traced_bodies,
        .evaluator_traced_nodes = generator.evaluator.traced_nodes,
    };
}
