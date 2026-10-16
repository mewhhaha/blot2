//! Dedicated successful constant-slot receipts. Snapshot IDs name the immutable
//! artifact owner; graph transport alone grants neither fuel nor slot authority.
const std = @import("std");
const core = @import("../check/core.zig");
const eval = @import("../eval/core_eval.zig");
const A = std.mem.Allocator;

/// The measured 105-step class could not pay for lookup/owner work; the
/// profitable primitive spines start at 161 steps. Admission stays source based.
pub const minimum_steps: usize = 128;
/// A selected judgment costs more than scalar transport. The166-step class
/// regressed retained Fast CPU;1069-step method bodies repaid its owner work.
pub const minimum_query_steps: usize = 1024;

/// Decline known unsupported result heads before installing observation. Open
/// types still use the ordinary evaluator and the exact result admission below.
pub fn recordable(module: *const core.Module, root: core.Id, declared: u32) bool {
    if (literal(module, root)) return false;
    const head = module.types.node(declared);
    switch (head.tag) {
        .unit, .boolean, .u32, .f32, .variable, .projection, .nominal, .product, .record, .function, .cursor, .array, .list, .existential, .forall => return true,
        else => return false,
    }
}

pub fn hasProductiveRecord(records: []const Record, floor: usize) bool {
    for (records) |record| if (record.productive(floor)) return true;
    return false;
}

/// Literal collections cannot pay for graph validation and copying. Decide
/// before installing a recorder so their ordinary evaluation paths stay cheap.
pub fn literal(module: *const core.Module, id: core.Id) bool {
    if (module.node(id).tag == .constant) return true;
    if (module.node(id).tag != .array) return false;
    for (module.children(id)) |child| if (module.node(child).tag != .constant) return false;
    return true;
}

pub const Resources = struct {
    steps: usize = 0,
    values: usize = 0,
    children: usize = 0,
    depth: usize = 0,
    call_depth: usize = 0,
};
pub const Read = struct { target: core.BindingRef, value: eval.ValueId, depth: usize = 0, call_depth: usize = 0 };
pub const Source = union(enum) { named: core.BindingRef, anonymous: struct { unit: u32, catalog: u32 } };
pub const Growth = struct { mutations: u64, frontier: ?@import("../eval/eval_collection_growth.zig").Frontier = null };
/// A typed header shares representation and children while selecting evidence.
/// Imported metadata tables may assign new slots to identical descriptors.
pub fn validView(snapshot: anytype, effect: @import("specialization_receipt.zig").ViewEffect) bool {
    if (effect.value == 0 or effect.selected == 0 or effect.value >= snapshot.values.len or effect.selected >= snapshot.values.len or snapshot.value_evidence[effect.selected] != effect.evidence) return false;
    var left = snapshot.values[effect.value];
    var right = snapshot.values[effect.selected];
    if (left.len == 0) left.start = 0;
    if (right.len == 0) right.start = 0;
    if (left.kind == .closure and right.kind == .closure) {
        var before = snapshot.closures[left.bits];
        var after = snapshot.closures[right.bits];
        if (before.mappings.len != after.mappings.len or before.row_mappings.len != after.row_mappings.len) return false;
        for (snapshot.type_mappings[before.mappings.start..][0..before.mappings.len], snapshot.type_mappings[after.mappings.start..][0..after.mappings.len]) |a_, b_| if (!std.meta.eql(a_, b_)) return false;
        for (snapshot.row_mappings[before.row_mappings.start..][0..before.row_mappings.len], snapshot.row_mappings[after.row_mappings.start..][0..after.row_mappings.len]) |a_, b_| if (!std.meta.eql(a_, b_)) return false;
        before.mappings.start = 0;
        after.mappings.start = 0;
        before.row_mappings.start = 0;
        after.row_mappings.start = 0;
        if (!std.meta.eql(before, after)) return false;
        left.bits = 0;
        right.bits = 0;
    }
    if (!std.meta.eql(left, right)) return false;
    const left_record = snapshot.value_records[effect.value];
    const right_record = snapshot.value_records[effect.selected];
    if (left_record == 0 or right_record == 0) return left_record == right_record;
    const before = snapshot.record_layouts[left_record];
    const after = snapshot.record_layouts[right_record];
    return std.mem.eql(u32, snapshot.field_names[before.start..][0..before.len], snapshot.field_names[after.start..][0..after.len]);
}
/// An inference barrier re-executes the current query before value replay
/// continues. Its old output locates a graph to compare, never callable proof.
pub const Query = struct {
    kind: enum { inferred, entry, specialized, source, array_member, judgment },
    input: u32 = 0,
    expected: u32 = 0,
    selected: u32 = 0,
    target: core.BindingRef = .{ .unit = 0, .binding = 0 },
    result: eval.SourceInterface = .{},
    judgment: ?*Judgment = null,
    depth: usize = 0,
    call_depth: usize = 0,
    pub fn clone(self: Query, a: A) A.Error!*Query {
        const result = try a.create(Query);
        result.* = self;
        errdefer a.destroy(result);
        if (self.judgment) |judgment| result.judgment = try judgment.clone(a);
        return result;
    }
    pub fn destroy(self: *Query, a: A) void {
        if (self.judgment) |judgment| judgment.destroy(a);
        a.destroy(self);
    }
    pub fn ownedBytes(self: Query) usize {
        var bytes: usize = @sizeOf(Query);
        if (self.judgment) |judgment| bytes += judgment.ownedBytes();
        return bytes;
    }
};
pub const Event = union(enum) {
    work: Resources,
    read: Read,
    growth: Growth,
    view: @import("specialization_receipt.zig").ViewEffect,
    query: *Query,
    fn clone(self: Event, a: A) A.Error!Event {
        if (self == .query) return .{ .query = try self.query.clone(a) };
        return self;
    }
    fn deinit(self: *Event, a: A) void {
        if (self.* == .query) self.query.destroy(a);
    }
};
pub fn sourceMappingKey(module: *const core.Module, id: u32) bool {
    if (id == 0 or id >= module.types.nodes.len) return false;
    const node = module.types.node(id);
    if (node.tag == .variable) return true;
    if (node.tag != .bound or node.b != 0) return false;
    for (module.types.nodes) |owner| {
        if (owner.tag != .forall and owner.tag != .existential) continue;
        for (module.types.list(.{ .start = owner.b, .len = owner.c }), 0..) |binder, ordinal| if (binder == id and node.a == ordinal) return true;
    }
    for (module.nodes, 0..) |value, source| {
        if (value.tag != .package_unpack) continue;
        const opening = module.packageOpening(@intCast(source));
        for (module.types.list(opening.binders), 0..) |binder, ordinal| if (binder == id and node.a == ordinal and node.c == value.b) return true;
    }
    return false;
}

pub const Inputs = struct {
    types: []const @import("../eval/type_evidence.zig").Mapping = &.{},
    rows: []const @import("../eval/type_evidence.zig").RowMapping = &.{},
    pub fn clone(self: Inputs, a: A) A.Error!Inputs {
        const types = try a.dupe(@import("../eval/type_evidence.zig").Mapping, self.types);
        errdefer a.free(types);
        return .{ .types = types, .rows = try a.dupe(@import("../eval/type_evidence.zig").RowMapping, self.rows) };
    }
    pub fn deinit(self: *Inputs, a: A) void {
        a.free(self.types);
        a.free(self.rows);
        self.* = .{};
    }
};
/// Source keys are interpreted only with an exact current immutable module
/// owner. Outputs describe the ordinary judgment and never grant proof authority.
pub const Judgment = struct {
    kind: enum { match, covariant, scheme, body },
    unit: u32,
    producer: u32 = 0,
    source: core.Id,
    root: u32 = 0,
    scheme: @import("../check/types.zig").Scheme = .{},
    closed_rows: @import("../check/types.zig").List = .{},
    allow_remaining: bool = false,
    matched: bool = true,
    inputs: Inputs = .{},
    outputs: Inputs = .{},
    selected: []const core.BindingRef = &.{},
    pub fn clone(self: Judgment, a: A) A.Error!*Judgment {
        const result = try a.create(Judgment);
        errdefer a.destroy(result);
        result.* = self;
        result.inputs = try self.inputs.clone(a);
        errdefer result.inputs.deinit(a);
        result.outputs = try self.outputs.clone(a);
        errdefer result.outputs.deinit(a);
        result.selected = try a.dupe(core.BindingRef, self.selected);
        return result;
    }
    pub fn destroy(self: *Judgment, a: A) void {
        self.inputs.deinit(a);
        self.outputs.deinit(a);
        a.free(self.selected);
        a.destroy(self);
    }
    pub fn ownedBytes(self: Judgment) usize {
        return @sizeOf(Judgment) + (self.inputs.types.len + self.outputs.types.len) * @sizeOf(@import("../eval/type_evidence.zig").Mapping) + (self.inputs.rows.len + self.outputs.rows.len) * @sizeOf(@import("../eval/type_evidence.zig").RowMapping) + self.selected.len * @sizeOf(core.BindingRef);
    }
};
pub const Record = struct {
    buffers: []const @import("../eval/eval_collection_growth.zig").BufferEffect = &.{},
    ordered_reads: bool = false,
    values_before: usize = 0,
    target: core.BindingRef,
    value: eval.ValueId,
    options: eval.Options,
    events: []Event,
    sources: []Source,
    inputs: Inputs = .{},
    outputs: ?*Inputs = null,
    pub fn sourceSteps(self: Record) usize {
        var steps: usize = 0;
        for (self.events) |event| switch (event) {
            .work => |work| steps +|= work.steps,
            .read, .growth, .view, .query => {},
        };
        return steps;
    }
    pub fn productive(self: Record, floor: usize) bool {
        const steps = self.sourceSteps();
        if (steps < floor) return false;
        for (self.events) |event| if (event == .query and steps < minimum_query_steps) return false;
        return true;
    }
    /// Exact payload requested by the immutable artifact owner, excluding the
    /// shared evaluator snapshot and allocator bookkeeping/capacity slack.
    pub fn ownedBytes(self: Record) usize {
        var queries: usize = 0;
        for (self.events) |event| if (event == .query) {
            queries += event.query.ownedBytes();
        };
        var output_bytes: usize = 0;
        if (self.outputs) |outputs| output_bytes = @sizeOf(Inputs) + outputs.types.len * @sizeOf(@import("../eval/type_evidence.zig").Mapping) + outputs.rows.len * @sizeOf(@import("../eval/type_evidence.zig").RowMapping);
        return queries + output_bytes + @sizeOf(Record) + self.buffers.len * @sizeOf(@import("../eval/eval_collection_growth.zig").BufferEffect) + self.events.len * @sizeOf(Event) + self.sources.len * @sizeOf(Source) + self.inputs.types.len * @sizeOf(@import("../eval/type_evidence.zig").Mapping) + self.inputs.rows.len * @sizeOf(@import("../eval/type_evidence.zig").RowMapping);
    }
    pub fn deinit(self: *Record, a: A) void {
        a.free(self.buffers);
        for (self.events) |*event| event.deinit(a);
        a.free(self.events);
        a.free(self.sources);
        self.inputs.deinit(a);
        if (self.outputs) |outputs| {
            outputs.deinit(a);
            a.destroy(outputs);
        }
        self.* = undefined;
    }
    pub fn clone(self: Record, a: A) A.Error!Record {
        var result = self;
        result.buffers = try a.dupe(@import("../eval/eval_collection_growth.zig").BufferEffect, self.buffers);
        errdefer a.free(result.buffers);
        result.events = try a.alloc(Event, self.events.len);
        var completed: usize = 0;
        errdefer {
            for (result.events[0..completed]) |*event| event.deinit(a);
            a.free(result.events);
        }
        for (self.events, result.events) |event, *copy| {
            copy.* = try event.clone(a);
            completed += 1;
        }
        result.sources = try a.dupe(Source, self.sources);
        errdefer a.free(result.sources);
        result.inputs = try self.inputs.clone(a);
        errdefer result.inputs.deinit(a);
        if (self.outputs) |outputs| {
            const payload = try a.create(Inputs);
            errdefer a.destroy(payload);
            payload.* = try outputs.clone(a);
            result.outputs = payload;
        }
        return result;
    }
};
pub const Reason = enum { mode, source, resource, ready, graph, read, imported };
pub const Stats = struct {
    retries: usize = 0,
    reasons: [@typeInfo(Reason).@"enum".field_names.len]usize = @splat(0),
    lookups: usize = 0,
    candidates: usize = 0,
    reused: usize = 0,
    scalar_reused: usize = 0,
    recorded: usize = 0,
    declined: usize = 0,
    source_steps_replayed: usize = 0,
    values_imported: usize = 0,
    queries_recorded: usize = 0,
    queries_replayed: usize = 0,
    owned_payload_bytes: usize = 0,
    lookup_comparisons: usize = 0,
    graph_values_examined: usize = 0,
    graph_index_bytes: usize = 0,
};
pub const Lookup = struct { value: eval.ValueId, outputs: Inputs };
pub const Provider = struct {
    context: *anyopaque,
    lookup: *const fn (*anyopaque, *eval.Session, core.BindingRef, Inputs) A.Error!?Lookup,
};

/// Borrowed by one ordinary evaluation frame. Child frames replace this
/// recorder, so the parent's work excludes nested constant evaluation.
pub const Recorder = struct {
    events: std.ArrayList(Event) = .empty,
    sources: std.ArrayList(Source) = .empty,
    view_inputs: std.AutoHashMapUnmanaged(u32, bool) = .empty,
    ready_reads: std.AutoHashMapUnmanaged(core.BindingRef, u32) = .empty,
    cached_views: std.AutoHashMapUnmanaged(struct { value: u32, evidence: u32 }, u32) = .empty,
    inputs: Inputs = .{},
    owns_inputs: bool = false,
    mark: Resources,
    values_before: usize,
    base_depth: usize,
    base_calls: usize,
    inference_serial: u64,
    collection_serial: u64,
    child_mark: usize,
    owned_children: std.ArrayList(@import("../eval/eval_collection_growth.zig").Span) = .empty,
    growth_mutations: u64 = 0,
    buffers: std.ArrayList(@import("../eval/eval_collection_growth.zig").BufferEffect) = .empty,
    summary_transitions: usize,
    summary_work: usize,
    summary_exhausted: bool,
    query_budgets: [8]usize,
    depth: usize = 0,
    call_depth: usize = 0,
    eligible: bool = true,
    pub fn init(session: *const eval.Session) Recorder {
        return .{ .mark = position(session), .values_before = session.storage.values.items.len, .base_depth = session.depth, .base_calls = session.call_depth, .inference_serial = session.constant_inference_serial, .collection_serial = session.storage.collection_buffers.mutation_serial, .child_mark = session.storage.children.items.len, .summary_transitions = session.summary_transitions, .summary_work = session.summary_graph_work, .summary_exhausted = session.summary_exhausted, .query_budgets = queryBudgets(session) };
    }
    pub fn captureInputs(self: *Recorder, a: A, inputs: Inputs) A.Error!void {
        const owned = try inputs.clone(a);
        a.free(self.inputs.types);
        a.free(self.inputs.rows);
        self.inputs = owned;
        self.owns_inputs = true;
    }
    pub fn deinit(self: *Recorder, a: A) void {
        if (self.owns_inputs) self.inputs.deinit(a);
        for (self.events.items) |*event| event.deinit(a);
        self.events.deinit(a);
        self.sources.deinit(a);
        self.view_inputs.deinit(a);
        self.ready_reads.deinit(a);
        self.cached_views.deinit(a);
        self.owned_children.deinit(a);
        self.buffers.deinit(a);
    }
    pub fn view(self: *Recorder, a: A, input: u32) A.Error!void {
        if (!self.eligible or self.view_inputs.contains(input)) return;
        if (self.view_inputs.count() >= 4096) {
            self.eligible = false;
            return;
        }
        try self.view_inputs.put(a, input, false);
    }
    pub fn prepareView(self: *Recorder, a: A) A.Error!void {
        if (self.eligible) try self.events.ensureUnusedCapacity(a, 2);
    }
    pub fn cacheView(self: *Recorder, a: A, session: *const eval.Session, effect: @import("specialization_receipt.zig").ViewEffect) A.Error!void {
        if (!self.eligible) return;
        try self.flush(a, session);
        if (!self.eligible) return;
        if (self.cached_views.count() >= 16384) {
            self.eligible = false;
            return;
        }
        const known = try self.cached_views.getOrPut(a, .{ .value = effect.value, .evidence = effect.evidence });
        if (known.found_existing) {
            // Published cache keys are immutable. Repeated hits own no work,
            // allocation or publication beyond the first ordered effect.
            if (!effect.existed or known.value_ptr.* != effect.selected) self.eligible = false;
        } else {
            known.value_ptr.* = effect.selected;
            self.events.appendAssumeCapacity(.{ .view = effect });
        }
        self.view_inputs.getPtr(effect.value).?.* = true;
    }
    fn viewsEscape(self: *Recorder, a: A, session: *const eval.Session, result: u32) A.Error!bool {
        if (self.view_inputs.count() == 0 and self.growth_mutations == 0) return false;
        var pending: std.ArrayList(u32) = .empty;
        defer pending.deinit(a);
        var seen: std.AutoHashMapUnmanaged(u32, void) = .empty;
        defer seen.deinit(a);
        try pending.append(a, result);
        for (self.events.items) |event| switch (event) {
            .read => |dependency| try pending.append(a, dependency.value),
            .query => |query_| {
                if (query_.input != 0) try pending.append(a, query_.input);
                if (query_.selected != 0) try pending.append(a, query_.selected);
            },
            .work, .growth, .view => {},
        };
        while (pending.pop()) |id| {
            if (seen.contains(id)) continue;
            // A reachable view key requires cache-publication ownership. Dead
            // temporary keys cannot be named by any later ordinary expression.
            if (self.view_inputs.get(id)) |complete| if (!complete) return true;
            if (seen.count() >= 65536) return true;
            try seen.put(a, id, {});
            const info = session.valueInfo(id);
            if (info.kind == .array or info.kind == .list) if (session.storage.collection_buffers.buffers.get(.{ .start = info.start, .len = info.len })) |buffer| {
                if (self.ownsChildren(session, buffer)) {
                    var duplicate = false;
                    for (self.buffers.items) |effect| {
                        const prior = session.valueInfo(effect.value);
                        if (prior.start == info.start and prior.len == info.len) duplicate = true;
                    }
                    if (!duplicate) try self.buffers.append(a, .{ .value = id, .frontier = .{ .offset = info.start - buffer.start, .capacity = buffer.len } });
                }
            };
            const children = session.valueChildren(id);
            if (pending.items.len > 65536 or children.len > 65536 - pending.items.len) return true;
            try pending.appendSlice(a, children);
        }
        // Dead keys cannot be observed after this constant. Live keys carry
        // their exact existing/new cache effects through the shared tape.
        var count: usize = 0;
        for (self.events.items) |event| {
            if (event == .view and !seen.contains(event.view.value)) continue;
            self.events.items[count] = event;
            count += 1;
        }
        self.events.items.len = count;
        return false;
    }
    pub fn observe(self: *Recorder, session: *const eval.Session) void {
        self.depth = @max(self.depth, session.depth - self.base_depth);
        self.call_depth = @max(self.call_depth, session.call_depth - self.base_calls);
    }
    /// Only this constant's new child spans may change a growth frontier.
    /// Nested constants and pre-existing collections retain ordinary work.
    pub fn canGrow(self: *const Recorder, session: *const eval.Session, before: @import("../eval/eval_collection_growth.zig").Span) bool {
        if (!self.eligible or self.collection_serial == std.math.maxInt(u64) or self.collection_serial != session.storage.collection_buffers.mutation_serial) return false;
        if (before.len != 0 and !self.ownsChildren(session, before)) return false;
        if (session.storage.collection_buffers.buffers.get(before)) |buffer| if (!self.ownsChildren(session, buffer)) return false;
        return true;
    }
    fn ownsChildren(self: *const Recorder, session: *const eval.Session, span: @import("../eval/eval_collection_growth.zig").Span) bool {
        const end = @as(usize, span.start) + span.len;
        if (span.start >= self.child_mark and end <= session.storage.children.items.len) return true;
        for (self.owned_children.items) |owned| if (span.start >= owned.start and end <= @as(usize, owned.start) + owned.len) return true;
        return false;
    }
    pub fn grew(self: *Recorder, session: *const eval.Session) void {
        std.debug.assert(self.collection_serial + 1 == session.storage.collection_buffers.mutation_serial);
        self.collection_serial += 1;
        self.growth_mutations += 1;
    }
    pub fn source(self: *Recorder, a: A, target: core.BindingRef) A.Error!void {
        return self.observed(a, .{ .named = target });
    }
    pub fn closure(self: *Recorder, a: A, unit: u32, catalog: u32) A.Error!void {
        return self.observed(a, .{ .anonymous = .{ .unit = unit, .catalog = catalog } });
    }
    fn observed(self: *Recorder, a: A, target: Source) A.Error!void {
        if (!self.eligible) return;
        for (self.sources.items) |old| if (std.meta.eql(old, target)) return;
        if (self.sources.items.len >= 4096) {
            self.eligible = false;
            return;
        }
        try self.sources.append(a, target);
    }
    pub fn flush(self: *Recorder, a: A, session: *const eval.Session) A.Error!void {
        if (!self.eligible) return;
        const now = position(session);
        const work: Resources = .{ .steps = now.steps - self.mark.steps, .values = now.values - self.mark.values, .children = now.children - self.mark.children, .depth = self.depth, .call_depth = self.call_depth };
        if (self.events.items.len >= 16384) {
            self.eligible = false;
            return;
        }
        if (session.storage.children.items.len != self.child_mark) try self.owned_children.append(a, .{ .start = @intCast(self.child_mark), .len = @intCast(session.storage.children.items.len - self.child_mark) });
        if (self.events.items.len != 0 and self.events.items[self.events.items.len - 1] == .work) {
            const previous = &self.events.items[self.events.items.len - 1].work;
            previous.steps += work.steps;
            previous.values += work.values;
            previous.children += work.children;
            previous.depth = @max(previous.depth, work.depth);
            previous.call_depth = @max(previous.call_depth, work.call_depth);
        } else try self.events.append(a, .{ .work = work });
        self.reset(session);
    }
    pub fn reset(self: *Recorder, session: *const eval.Session) void {
        self.mark = position(session);
        self.child_mark = session.storage.children.items.len;
        self.depth = 0;
        self.call_depth = 0;
    }
    fn stable(self: *const Recorder, session: *const eval.Session) bool {
        return session.constant_inference_serial != std.math.maxInt(u64) and session.constant_inference_serial == self.inference_serial and
            session.summary_transitions == self.summary_transitions and session.summary_graph_work == self.summary_work and session.summary_exhausted == self.summary_exhausted and
            std.meta.eql(self.query_budgets, queryBudgets(session));
    }
    pub fn beforeRead(self: *Recorder, a: A, session: *const eval.Session) A.Error!void {
        if (!self.stable(session)) self.eligible = false;
        try self.flush(a, session);
    }
    pub fn read(self: *Recorder, a: A, session: *const eval.Session, target: core.BindingRef, value: eval.ValueId) A.Error!void {
        if (self.ready_reads.count() >= 4096) self.eligible = false;
        if (self.eligible) {
            const known = try self.ready_reads.getOrPut(a, target);
            if (known.found_existing) {
                // Completed slots are immutable and ordinary later reads do
                // no work. The first ordered read still evaluates and matches.
                if (known.value_ptr.* != value) self.eligible = false;
            } else {
                known.value_ptr.* = value;
                try self.events.append(a, .{ .read = .{ .target = target, .value = value, .depth = session.depth - self.base_depth, .call_depth = session.call_depth - self.base_calls } });
            }
        }
        // Dependency evaluation and publication ran ordinarily while suspended.
        // Every own query still revokes recording before this boundary.
        self.inference_serial = session.constant_inference_serial;
        self.summary_transitions = session.summary_transitions;
        self.summary_work = session.summary_graph_work;
        self.summary_exhausted = session.summary_exhausted;
        self.query_budgets = queryBudgets(session);
        self.reset(session);
    }
    pub fn query(self: *Recorder, a: A, session: *const eval.Session, observation: Query) A.Error!void {
        if (!self.eligible or session.constant_inference_serial == std.math.maxInt(u64)) return;
        var owned = observation;
        owned.depth = session.depth - self.base_depth;
        owned.call_depth = session.call_depth - self.base_calls;
        const payload = try owned.clone(a);
        errdefer payload.destroy(a);
        try self.events.append(a, .{ .query = payload });
        // The query ran ordinarily while recording was suspended. Its caches,
        // budget transitions and temporary allocations will run ordinarily on
        // replay, rather than becoming local value-work credit.
        self.inference_serial = session.constant_inference_serial;
        self.summary_transitions = session.summary_transitions;
        self.summary_work = session.summary_graph_work;
        self.summary_exhausted = session.summary_exhausted;
        self.query_budgets = queryBudgets(session);
        self.collection_serial = session.storage.collection_buffers.mutation_serial;
        self.reset(session);
    }
    pub fn finish(self: *Recorder, a: A, session: *const eval.Session, target: core.BindingRef, value: eval.ValueId, outputs: Inputs) A.Error!?Record {
        try self.flush(a, session);
        if (!self.eligible) return null;
        if (self.collection_serial == std.math.maxInt(u64) or session.storage.collection_buffers.mutation_serial != self.collection_serial) return null;
        // Cumulative inference work has its own fallback state. Until an exact
        // tape owns those charges, observing a transition keeps evaluation
        // ordinary rather than silently giving later queries a larger budget.
        if (session.constant_inference_serial == std.math.maxInt(u64) or session.constant_inference_serial != self.inference_serial) return null;
        if (session.summary_transitions != self.summary_transitions or session.summary_graph_work != self.summary_work or session.summary_exhausted != self.summary_exhausted) return null;
        if (!std.meta.eql(self.query_budgets, queryBudgets(session))) return null;
        var steps: usize = 0;
        for (self.events.items) |event| switch (event) {
            .work => |work| steps += work.steps,
            .read, .growth, .view, .query => {},
        };
        if (steps < session.minimum_constant_steps) return null;
        for (self.events.items) |event| if (event == .query and steps < minimum_query_steps) return null;
        // Head admission is only a cheap cutoff. Replay must validate the
        // complete reachable graph and every already-ready dependency.
        if (!admittedGraph(session.snapshot(), value)) return null;
        for (self.events.items) |event| switch (event) {
            .read => |dependency| if (!admittedGraph(session.snapshot(), dependency.value)) return null,
            .work, .growth, .view, .query => {},
        };
        const info = session.valueInfo(value);
        if ((info.kind == .array or info.kind == .list) and info.len > steps / 4) return null;
        if (try self.viewsEscape(a, session, value)) return null;
        if (self.growth_mutations != 0) {
            var growth: Growth = .{ .mutations = self.growth_mutations };
            // Retain the compact primitive root path. Compound graphs carry
            // each reachable latest span through the same Frontier contract.
            var plain = true;
            for (self.events.items) |event| if (event == .read or event == .view or event == .query) {
                plain = false;
            };
            if (plain and self.buffers.items.len == 1 and self.buffers.items[0].value == value and (info.kind == .array or info.kind == .list)) {
                var primitive = true;
                for (session.valueChildren(value)) |child| if (session.valueInfo(child).kind != .scalar) {
                    primitive = false;
                };
                if (primitive) {
                    growth.frontier = self.buffers.items[0].frontier;
                    self.buffers.clearRetainingCapacity();
                }
            }
            try self.events.append(a, .{ .growth = growth });
        }
        const buffers = try self.buffers.toOwnedSlice(a);
        errdefer a.free(buffers);
        const events = try self.events.toOwnedSlice(a);
        errdefer {
            for (events) |*event| event.deinit(a);
            a.free(events);
        }
        const sources = try self.sources.toOwnedSlice(a);
        errdefer a.free(sources);
        var owned_inputs = try self.inputs.clone(a);
        errdefer owned_inputs.deinit(a);
        var owned_outputs: ?*Inputs = null;
        if (!@import("../structural.zig").equal(self.inputs.types, outputs.types) or !@import("../structural.zig").equal(self.inputs.rows, outputs.rows)) {
            const payload = try a.create(Inputs);
            errdefer a.destroy(payload);
            payload.* = try outputs.clone(a);
            owned_outputs = payload;
        }
        return .{ .buffers = buffers, .ordered_reads = true, .values_before = self.values_before, .target = target, .value = value, .options = session.options, .events = events, .sources = sources, .inputs = owned_inputs, .outputs = owned_outputs };
    }
};
fn position(session: *const eval.Session) Resources {
    return .{ .steps = session.steps, .values = session.constantValueCount(), .children = session.constantChildCount() };
}

pub fn queryBudgets(session: *const eval.Session) [8]usize {
    return .{
        session.specializations.canonical_specializations.examined_words,
        session.specializations.canonical_specializations.retained_words,
        @intFromBool(session.specializations.canonical_specializations.enabled),
        session.specializations.lexical_inputs.examined_words,
        session.specializations.lexical_inputs.retained_words,
        session.specializations.lexical_inputs.interface_visits,
        session.specializations.lexical_inputs.inputs.items.len,
        session.specializations.canonical_specializations.table.records.items.len,
    };
}

/// Admission is independent from names, source paths and captured fixtures.
pub fn admittedGraph(snapshot: anytype, value: u32) bool {
    if (value >= snapshot.values.len) return false;
    switch (snapshot.values[value].kind) {
        .scalar, .product, .record, .nominal, .array, .list, .cursor, .closure, .package => return true,
        else => return false,
    }
}
