//! Dedicated successful constant-slot receipts. Snapshot IDs name the immutable
//! artifact owner; graph transport alone grants neither fuel nor slot authority.
const std = @import("std");
const core = @import("core.zig");
const eval = @import("core_eval.zig");
const A = std.mem.Allocator;

/// The measured 105-step class could not pay for lookup/owner work; the
/// profitable primitive spines start at 161 steps. Admission stays source based.
pub const minimum_steps: usize = 128;
/// A selected judgment costs more than scalar transport. The166-step class
/// regressed retained Fast CPU;1069-step method bodies repaid its owner work.
pub const minimum_member_steps: usize = 1024;

/// Decline known unsupported result heads before installing observation. Open
/// types still use the ordinary evaluator and the exact result admission below.
pub fn recordable(module: *const core.Module, root: core.Id, declared: u32) bool {
    if (literal(module, root)) return false;
    const head = module.types.node(declared);
    switch (head.tag) {
        .unit, .boolean, .u32, .f32, .variable, .projection => return true,
        .array, .list => switch (module.types.node(head.a).tag) {
            .unit, .boolean, .u32, .f32, .variable, .projection => return true,
            else => return false,
        },
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
pub const Read = struct { target: core.BindingRef, value: eval.ValueId };
pub const Source = union(enum) { named: core.BindingRef, anonymous: struct { unit: u32, catalog: u32 } };
/// A Session position is remapped to an immutable selected-query table
/// position during capture. The table, its snapshot and this tape share one
/// artifact owner; the position only locates proof, never supplies proof.
pub const MemberEvent = struct { record: u32, values: usize, depth: usize, inference_observations: u64 };
pub const Event = union(enum) { work: Resources, read: Read, member: MemberEvent };
pub const Inputs = struct {
    types: []const @import("type_evidence.zig").Mapping = &.{},
    rows: []const @import("type_evidence.zig").RowMapping = &.{},
    fn clone(self: Inputs, a: A) A.Error!Inputs {
        const types = try a.dupe(@import("type_evidence.zig").Mapping, self.types);
        errdefer a.free(types);
        return .{ .types = types, .rows = try a.dupe(@import("type_evidence.zig").RowMapping, self.rows) };
    }
    fn deinit(self: *Inputs, a: A) void {
        a.free(self.types);
        a.free(self.rows);
        self.* = .{};
    }
};
pub const Record = struct {
    target: core.BindingRef,
    value: eval.ValueId,
    options: eval.Options,
    events: []Event,
    sources: []Source,
    inputs: Inputs = .{},
    pub fn sourceSteps(self: Record) usize {
        var steps: usize = 0;
        for (self.events) |event| switch (event) {
            .work => |work| steps +|= work.steps,
            .read, .member => {},
        };
        return steps;
    }
    pub fn productive(self: Record, floor: usize) bool {
        const steps = self.sourceSteps();
        if (steps < floor) return false;
        for (self.events) |event| if (event == .member and steps < minimum_member_steps) return false;
        return true;
    }
    /// Exact payload requested by the immutable artifact owner, excluding the
    /// shared evaluator snapshot and allocator bookkeeping/capacity slack.
    pub fn ownedBytes(self: Record) usize {
        return @sizeOf(Record) + self.events.len * @sizeOf(Event) + self.sources.len * @sizeOf(Source) + self.inputs.types.len * @sizeOf(@import("type_evidence.zig").Mapping) + self.inputs.rows.len * @sizeOf(@import("type_evidence.zig").RowMapping);
    }
    pub fn deinit(self: *Record, a: A) void {
        a.free(self.events);
        a.free(self.sources);
        self.inputs.deinit(a);
        self.* = undefined;
    }
    pub fn clone(self: Record, a: A) A.Error!Record {
        var result = self;
        result.events = try a.dupe(Event, self.events);
        errdefer a.free(result.events);
        result.sources = try a.dupe(Source, self.sources);
        errdefer a.free(result.sources);
        result.inputs = try self.inputs.clone(a);
        return result;
    }
};
pub const Reason = enum { mode, source, resource, ready, graph, read, imported };
pub const Stats = struct {
    reasons: [@typeInfo(Reason).@"enum".field_names.len]usize = @splat(0),
    lookups: usize = 0,
    candidates: usize = 0,
    reused: usize = 0,
    scalar_reused: usize = 0,
    recorded: usize = 0,
    declined: usize = 0,
    source_steps_replayed: usize = 0,
    values_imported: usize = 0,
    member_recorded: usize = 0,
    member_replayed: usize = 0,
    member_declined: usize = 0,
    owned_payload_bytes: usize = 0,
    lookup_comparisons: usize = 0,
    graph_values_examined: usize = 0,
    graph_index_bytes: usize = 0,
};
pub const Provider = struct {
    context: *anyopaque,
    lookup: *const fn (*anyopaque, *eval.Session, core.BindingRef, Inputs) A.Error!?eval.ValueId,
};

/// Borrowed by one ordinary evaluation frame. Child frames replace this
/// recorder, so the parent's work excludes nested constant evaluation.
pub const Recorder = struct {
    events: std.ArrayList(Event) = .empty,
    sources: std.ArrayList(Source) = .empty,
    view_inputs: std.AutoHashMapUnmanaged(u32, void) = .empty,
    inputs: Inputs = .{},
    owns_inputs: bool = false,
    mark: Resources,
    base_depth: usize,
    base_calls: usize,
    inference_serial: u64,
    collection_serial: u64,
    summary_transitions: usize,
    summary_work: usize,
    summary_exhausted: bool,
    query_budgets: [8]usize,
    depth: usize = 0,
    call_depth: usize = 0,
    eligible: bool = true,
    members: usize = 0,
    pub fn init(session: *const eval.Session) Recorder {
        return .{ .mark = position(session), .base_depth = session.depth, .base_calls = session.call_depth, .inference_serial = session.constant_inference_serial, .collection_serial = session.collection_buffers.mutation_serial, .summary_transitions = session.summary_transitions, .summary_work = session.summary_graph_work, .summary_exhausted = session.summary_exhausted, .query_budgets = queryBudgets(session) };
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
        self.events.deinit(a);
        self.sources.deinit(a);
        self.view_inputs.deinit(a);
    }
    pub fn view(self: *Recorder, a: A, input: u32) A.Error!void {
        if (!self.eligible or self.view_inputs.contains(input)) return;
        if (self.view_inputs.count() >= 4096) {
            self.eligible = false;
            return;
        }
        try self.view_inputs.put(a, input, {});
    }
    fn viewsEscape(self: *const Recorder, a: A, session: *const eval.Session, result: u32) A.Error!bool {
        if (self.view_inputs.count() == 0) return false;
        var pending: std.ArrayList(u32) = .empty;
        defer pending.deinit(a);
        var seen: std.AutoHashMapUnmanaged(u32, void) = .empty;
        defer seen.deinit(a);
        try pending.append(a, result);
        for (self.events.items) |event| switch (event) {
            .read => |dependency| try pending.append(a, dependency.value),
            .work, .member => {},
        };
        while (pending.pop()) |id| {
            if (seen.contains(id)) continue;
            // A reachable view key requires cache-publication ownership. Dead
            // temporary keys cannot be named by any later ordinary expression.
            if (self.view_inputs.contains(id)) return true;
            if (seen.count() >= 65536) return true;
            try seen.put(a, id, {});
            const children = session.valueChildren(id);
            if (pending.items.len > 65536 or children.len > 65536 - pending.items.len) return true;
            try pending.appendSlice(a, children);
        }
        return false;
    }
    pub fn observe(self: *Recorder, session: *const eval.Session) void {
        self.depth = @max(self.depth, session.depth - self.base_depth);
        self.call_depth = @max(self.call_depth, session.call_depth - self.base_calls);
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
        try self.events.append(a, .{ .work = work });
        self.reset(session);
    }
    pub fn reset(self: *Recorder, session: *const eval.Session) void {
        self.mark = position(session);
        self.depth = 0;
        self.call_depth = 0;
    }
    pub fn read(self: *Recorder, a: A, session: *const eval.Session, target: core.BindingRef, value: eval.ValueId) A.Error!void {
        if (self.eligible) try self.events.append(a, .{ .read = .{ .target = target, .value = value } });
        self.reset(session);
    }
    pub fn member(self: *Recorder, a: A, session: *const eval.Session, before: usize, inference_before: u64) A.Error!bool {
        if (self.inference_serial != inference_before or session.constant_inference_serial == std.math.maxInt(u64)) return false;
        if (!self.eligible or self.members != 0 or session.specialization_receipts.items.len != before + 1) return false;
        const record = session.specialization_receipts.items[before];
        if (!admittedMember(session.snapshot(), record)) return false;
        if (self.collection_serial == std.math.maxInt(u64) or session.collection_buffers.mutation_serial != self.collection_serial) return false;
        if (session.summary_transitions != self.summary_transitions or session.summary_graph_work != self.summary_work or session.summary_exhausted != self.summary_exhausted or !std.meta.eql(self.query_budgets, queryBudgets(session))) return false;
        try self.events.append(a, .{ .member = .{ .record = @intCast(before), .values = record.values_added, .depth = session.depth - self.base_depth, .inference_observations = session.constant_inference_serial - inference_before } });
        self.members = 1;
        self.inference_serial = session.constant_inference_serial;
        self.reset(session);
        return true;
    }
    pub fn finish(self: *Recorder, a: A, session: *const eval.Session, target: core.BindingRef, value: eval.ValueId) A.Error!?Record {
        try self.flush(a, session);
        if (!self.eligible) return null;
        if (self.collection_serial == std.math.maxInt(u64) or session.collection_buffers.mutation_serial != self.collection_serial) return null;
        // Cumulative inference work has its own fallback state. Until an exact
        // tape owns those charges, observing a transition keeps evaluation
        // ordinary rather than silently giving later queries a larger budget.
        if (session.constant_inference_serial == std.math.maxInt(u64) or session.constant_inference_serial != self.inference_serial) return null;
        if (session.summary_transitions != self.summary_transitions or session.summary_graph_work != self.summary_work or session.summary_exhausted != self.summary_exhausted) return null;
        if (!std.meta.eql(self.query_budgets, queryBudgets(session))) return null;
        var steps: usize = 0;
        for (self.events.items) |event| switch (event) {
            .work => |work| steps += work.steps,
            .read, .member => {},
        };
        if (steps < session.minimum_constant_steps or (self.members != 0 and steps < minimum_member_steps)) return null;
        // Compound graph indexes did not pay for themselves on the captured
        // workload. Only measured primitive payloads retain this authority.
        if (!admittedGraph(session.snapshot(), value)) return null;
        for (self.events.items) |event| switch (event) {
            .read => |dependency| if (session.valueInfo(dependency.value).kind != .scalar) return null,
            .work, .member => {},
        };
        const info = session.valueInfo(value);
        if (self.members != 0 and info.kind != .scalar) return null;
        if ((info.kind == .array or info.kind == .list) and info.len > steps / 4) return null;
        if (try self.viewsEscape(a, session, value)) return null;
        const events = try self.events.toOwnedSlice(a);
        errdefer a.free(events);
        const sources = try self.sources.toOwnedSlice(a);
        errdefer a.free(sources);
        return .{ .target = target, .value = value, .options = session.options, .events = events, .sources = sources, .inputs = try self.inputs.clone(a) };
    }
};
fn position(session: *const eval.Session) Resources {
    return .{ .steps = session.steps, .values = session.constantValueCount(), .children = session.constantChildCount() };
}

pub fn queryBudgets(session: *const eval.Session) [8]usize {
    return .{
        session.canonical_specializations.examined_words,
        session.canonical_specializations.retained_words,
        @intFromBool(session.canonical_specializations.enabled),
        session.lexical_inputs.examined_words,
        session.lexical_inputs.retained_words,
        session.lexical_inputs.interface_visits,
        session.lexical_inputs.inputs.items.len,
        session.canonical_specializations.table.records.items.len,
    };
}

/// Admission is independent from names, source paths and captured fixtures.
pub fn admittedGraph(snapshot: anytype, value: u32) bool {
    if (value >= snapshot.values.len) return false;
    const info = snapshot.values[value];
    if (info.kind == .scalar) return true;
    if (info.kind != .array and info.kind != .list) return false;
    if (info.start > snapshot.children.len or info.len > snapshot.children.len - info.start) return false;
    for (snapshot.children[info.start..][0..info.len]) |child| {
        if (child >= snapshot.values.len or snapshot.values[child].kind != .scalar) return false;
    }
    return true;
}

/// First enclosing law: a fresh empty receiver and no staged cache/proof
/// effects. All dynamic principal/source/ready reads remain selected-query
/// authority. Other receiver and publication shapes keep ordinary evaluation.
pub fn admittedMember(snapshot: anytype, record: @import("specialization_receipt.zig").Record) bool {
    if (record.member == null or !record.complete or record.steps != 0 or record.input >= snapshot.values.len or record.expected == 0 or record.children_added != 0) return false;
    const ordinary = eval.Options{};
    inline for (.{ "max_values", "max_children", "max_depth", "max_type_depth", "max_steps" }) |field| if (@field(record.options, field) != @field(ordinary, field)) return false;
    const input = snapshot.values[record.input];
    if (input.kind != .array or input.len != 0 or snapshot.value_evidence[record.input] != 0) return false;
    if (record.views.len != 0 or record.call_reads.len != 0 or record.call_publications.len != 0 or record.plain_facts.len != 0) return false;
    return true;
}
