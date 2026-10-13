//! Portable previous-revision semantic owner for selected specialization
//! replay. The archive persists each unit's exact checked Core (including type
//! node certificate bytes, so structural equality and stamps survive), the
//! identity namespace, the evaluator snapshot, binding slots, field locations
//! and complete selected receipts. Decoding validates every ordinal before rebuilding an
//! independent Capture whose module pins name the archive's own Core; the
//! ordinary Gate, Importer and graph Plan still compare it with current source
//! and re-admit every receipt. Executable fragments, layouts, captures,
//! templates, provider/request state and demand memos are not represented.
const std = @import("std");
const core = @import("core.zig");
const eval = @import("core_eval.zig");
const T = @import("types.zig");
const metadata = @import("code_artifacts.zig");
const capture = @import("artifact_capture.zig");
const receipt = @import("specialization_receipt.zig");
const selected = @import("selected_query.zig");
const identity = @import("runtime_identity.zig");
const portable = @import("portable_query.zig");
const format = @import("dependency_format.zig");
const validation = @import("frozen_core_validation.zig");
const A = std.mem.Allocator;

pub const Unit = struct {
    unit: u32,
    canonical_path: []u8,
    stamp: format.Digest,
    /// Empty when every type node certificate is zero; otherwise one word per
    /// `core.types.nodes` entry: `closed_height | closed_generation << 8`.
    certificates: []u32,
    core: core.Module,
};
pub const RecordKey = struct { input: u32, expected: u32, options: eval.Options, depth: usize };
pub const Dependencies = struct {
    values_before: usize,
    children_before: usize,
    values_added: usize,
    children_added: usize,
    collected: usize,
    source_scopes: usize,
    solver_nodes: usize,
    sources: []core.BindingRef,
    scalar_reads: []receipt.ScalarRead,
    call_reads: []receipt.CallRead,
    call_publications: []receipt.CallRead,
    views: []receipt.ViewEffect,
    plain_facts: []receipt.PlainFact,
};
pub const RecordResult = struct { selected: u32 };
pub const Record = struct { key: RecordKey, dependencies: Dependencies, result: RecordResult };
pub const Section = portable.Section(.selected_complete_proof, Record);
pub const Snapshot = struct {
    identity: identity.Metadata,
    units: []Unit,
    evaluator: eval.Snapshot,
    /// One slot per binding, in unit order; offsets are recomputed from Core.
    slots: []metadata.Slot,
    /// The Importer requires exact physical field positions before import.
    field_locations: []metadata.FieldLocation,
    queries: Section,
};
pub fn wireKey(compiler: format.Digest) format.Key {
    return .{ .compiler = compiler, .settings = format.digest("blot-semantic-archive-v3:selected-implementations"), .source = @splat(0), .dependencies = @splat(0) };
}
pub const limits: format.Limits = .{ .elements = 64 * 1024 * 1024 };

/// Returns null when the capture has no complete project semantic owner or no
/// completed selected receipt to replay. An owner over the artifact limit is
/// also omitted; restart then recomputes.
pub fn encode(a: A, compiler: format.Digest, source: *const capture.Capture) format.Error!?[]u8 {
    const pools = &(source.metadata.pools orelse return null);
    const names = if (pools.identity) |value| value else return null;
    if (!pools.project_identity or pools.modules.len == 0) return null;
    const complete = for (source.metadata.specialization_queries.records.items) |query| {
        if (query.dependencies.member == null and selected.Adapter.complete(query)) break true;
    } else false;
    if (!complete) return null;
    const units = try a.alloc(Unit, pools.modules.len);
    defer a.free(units);
    var certificates: std.ArrayList([]u32) = .empty;
    defer {
        for (certificates.items) |words| a.free(words);
        certificates.deinit(a);
    }
    for (pools.modules, units) |pin, *unit| {
        const nodes = pin.module.types.nodes;
        var words: []u32 = &.{};
        for (nodes) |node| if (node.closed_height != 0 or node.closed_generation != 0) {
            words = try a.alloc(u32, nodes.len);
            try certificates.append(a, words);
            for (nodes, words) |item, *word| word.* = @as(u32, item.closed_height) | @as(u32, item.closed_generation) << 8;
            break;
        };
        unit.* = .{ .unit = pin.unit, .canonical_path = pin.canonical_path, .stamp = pin.stamp, .certificates = words, .core = pin.module.* };
    }
    var records: std.ArrayList(Record) = .empty;
    defer records.deinit(a);
    for (source.metadata.specialization_queries.records.items) |query| {
        const proof = query.dependencies;
        // The portable closure schema cannot own Array-member authority.
        if (proof.member != null or !selected.Adapter.complete(query)) continue;
        try records.append(a, .{
            .key = .{ .input = proof.input, .expected = proof.expected, .options = proof.options, .depth = proof.depth },
            .dependencies = .{ .values_before = proof.values_before, .children_before = proof.children_before, .values_added = proof.values_added, .children_added = proof.children_added, .collected = proof.collected, .source_scopes = proof.source_scopes, .solver_nodes = proof.solver_nodes, .sources = proof.sources, .scalar_reads = proof.scalar_reads, .call_reads = proof.call_reads, .call_publications = proof.call_publications, .views = proof.views, .plain_facts = proof.plain_facts },
            .result = .{ .selected = proof.selected },
        });
    }
    const snapshot: Snapshot = .{ .identity = names, .units = units, .evaluator = pools.evaluator, .slots = pools.slots, .field_locations = pools.field_locations, .queries = .{ .header = portable.header(Section.claim), .records = records.items } };
    return format.encodeWithLimits(a, wireKey(compiler), snapshot, limits) catch |err| switch (err) {
        error.ArtifactLimit => null,
        else => err,
    };
}

/// Owns the decoded Core array and a Capture whose pools pin it. Pins point
/// into the heap Core array, so moving the Archive keeps them valid.
pub const Archive = struct {
    allocator: A,
    units: []Unit,
    capture: capture.Capture,
    pub fn deinit(self: *Archive) void {
        self.capture.deinit();
        for (self.units) |*unit| unit.canonical_path = &.{};
        format.deinit(self.allocator, &self.units);
        self.* = undefined;
    }
};

pub fn decode(a: A, compiler: format.Digest, bytes: []const u8) format.Error!Archive {
    var snapshot = try format.decodeWithLimits(Snapshot, a, bytes, wireKey(compiler), limits);
    defer format.deinit(a, &snapshot);
    for (snapshot.units) |*unit| try restoreCertificates(unit);
    try validate(a, &snapshot);
    return adopt(a, &snapshot);
}

fn restoreCertificates(unit: *Unit) format.Error!void {
    if (unit.certificates.len == 0) return;
    const nodes = unit.core.types.nodes;
    if (unit.certificates.len != nodes.len) return error.InvalidArtifact;
    for (nodes, unit.certificates) |*node, word| {
        if (word >> 24 != 0) return error.InvalidArtifact;
        node.closed_height = @truncate(word);
        node.closed_generation = @truncate(word >> 8);
    }
}

fn require(value: bool) format.Error!void {
    if (!value) return error.InvalidArtifact;
}
fn validSpan(len: usize, start: usize, count: usize) bool {
    return start <= len and count <= len - start;
}
fn validBinding(units: []const Unit, target: core.BindingRef) bool {
    return target.unit != 0 and target.unit <= units.len and target.binding != 0 and target.binding < units[target.unit - 1].core.bindings.len;
}

/// Checks the section, namespace, every Core graph, evaluator graph, slots and
/// receipt ordinals. Current-source admission happens later.
pub fn validate(a: A, snapshot: *const Snapshot) format.Error!void {
    const section = snapshot.queries;
    if (section.header.version != portable.version) return error.UnsupportedVersion;
    if (!section.admitted()) return error.SchemaMismatch;
    const units = snapshot.units;
    const names = snapshot.identity.view();
    try require(units.len != 0 and units.len < std.math.maxInt(u32) and names.owners.len == units.len and names.symbols.len != 0 and names.symbols.len <= std.math.maxInt(u32));
    for (1..names.symbols.len) |id| try require(names.symbol(@intCast(id)) != null);
    var paths: std.StringHashMapUnmanaged(void) = .empty;
    defer paths.deinit(a);
    const views = try a.alloc(*const core.Module, units.len);
    defer a.free(views);
    var bindings: usize = 0;
    for (units, views, 1..) |*unit, *view, id| {
        try require(unit.unit == id and unit.core.unit == id);
        const path = names.owner(@intCast(id)) orelse return error.InvalidArtifact;
        try require(path.len != 0 and std.mem.eql(u8, path, unit.canonical_path) and std.unicode.utf8ValidateSlice(path) and std.mem.findScalar(u8, path, 0) == null);
        try require(!(try paths.getOrPut(a, path)).found_existing);
        view.* = &unit.core;
        bindings = std.math.add(usize, bindings, unit.core.bindings.len) catch return error.InvalidArtifact;
    }
    // Stamps are accelerators: each Gate recomputes them from this Core, then
    // compares the full graph with current Core before admitting any unit.
    for (units) |*unit| validation.validate(a, &unit.core, .{ .units = views, .symbol_count = names.symbols.len }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidArtifact;
    try validEvaluator(&snapshot.evaluator, units.len);
    if (snapshot.evaluator.implementation_proofs.proofs.len != 0) {
        const modules = try a.alloc(core.Module, units.len);
        defer a.free(modules);
        for (units, modules) |*unit, *module| module.* = unit.core;
        var remaining: usize = 1_000_000;
        const proofs = snapshot.evaluator.implementation_proofs;
        try @import("selected_implementation_admission.zig").snapshot(a, modules, snapshot.evaluator.evidence.view(), .{ .proofs = proofs.proofs, .arguments = proofs.arguments, .members = proofs.members, .edges = proofs.edges }, &remaining);
    }
    try require(snapshot.slots.len == bindings);
    for (snapshot.slots) |slot| try require(slot.value < snapshot.evaluator.values.len);
    // Builtin field families use the reserved unit; others name a unit here.
    for (snapshot.field_locations) |field| {
        const unit = field.family >> 32;
        try require((unit == std.math.maxInt(u32) or (unit != 0 and unit <= units.len)) and field.name < names.symbols.len);
    }
    for (section.records) |record| try validRecord(record, snapshot);
}

fn validEvaluator(snapshot: *const eval.Snapshot, units: usize) format.Error!void {
    const values = snapshot.values.len;
    const nodes = snapshot.evidence.nodes.len;
    try require(portable.validEvidence(snapshot.evidence.view()));
    try require(values != 0 and snapshot.value_evidence.len == values and snapshot.value_records.len == values);
    for (snapshot.values) |value| {
        try require(validSpan(snapshot.children.len, value.start, value.len));
        if (value.kind == .closure) try require(value.bits < snapshot.closures.len);
    }
    for (snapshot.children) |child| try require(child < values);
    for (snapshot.closures) |closure| {
        try require(closure.unit <= units);
        try require(validSpan(snapshot.type_mappings.len, closure.mappings.start, closure.mappings.len));
        try require(validSpan(snapshot.row_mappings.len, closure.row_mappings.start, closure.row_mappings.len));
    }
    for (snapshot.value_evidence) |id| try require(id < nodes);
    for (snapshot.type_mappings) |mapping| try require(mapping.evidence < nodes);
    for (snapshot.row_mappings) |mapping| try require(mapping.evidence < snapshot.evidence.effects.rows.len);
    for (snapshot.value_records) |record| try require(record < snapshot.record_layouts.len);
    for (snapshot.record_layouts) |layout| try require(validSpan(snapshot.field_names.len, layout.start, layout.len));
    for (snapshot.demands) |demand| try require(demand.value < values);
    const proofs = snapshot.implementation_proofs;
    for (proofs.arguments) |root| try require(root != 0 and root < nodes);
    for (proofs.members) |member| try require(member.root != 0 and member.root < nodes and member.target.unit <= units);
    for (proofs.proofs, 0..) |proof, ordinal| {
        try require(proof.context != 0 and proof.context <= units);
        try require(proof.implementation.unit <= units and proof.contract.unit <= units);
        try require(validSpan(proofs.arguments.len, proof.arguments.start, proof.arguments.len));
        try require(validSpan(proofs.members.len, proof.members.start, proof.members.len));
        try require(validSpan(proofs.edges.len, proof.prerequisites.start, proof.prerequisites.len));
        for (proofs.edges[proof.prerequisites.start..][0..proof.prerequisites.len]) |child| try require(child < ordinal);
        for (proof.predicate.operands) |root| try require(root < nodes);
        try require(proof.predicate.target.unit <= units);
    }
}

fn validRecord(record: Record, snapshot: *const Snapshot) format.Error!void {
    const evaluator = &snapshot.evaluator;
    const values = evaluator.values.len;
    const nodes = evaluator.evidence.nodes.len;
    const key = record.key;
    const proof = record.dependencies;
    try require(key.input != 0 and key.input < values);
    const expected_kind: @import("type_evidence.zig").Tag = switch (evaluator.values[key.input].kind) {
        .closure => .function,
        .suspension => .demand,
        else => return error.InvalidArtifact,
    };
    try require(record.result.selected < values and key.expected != 0 and key.expected < nodes and evaluator.evidence.nodes[key.expected].tag == expected_kind);
    try require(proof.values_before <= values and proof.values_added <= values - proof.values_before);
    try require(proof.children_before <= evaluator.children.len and proof.children_added <= evaluator.children.len - proof.children_before);
    for (proof.sources) |source| try require(validBinding(snapshot.units, source));
    for (proof.scalar_reads) |read| try require(validBinding(snapshot.units, read.target) and read.evidence < nodes);
    for ([_][]const receipt.CallRead{ proof.call_reads, proof.call_publications }) |calls| {
        for (calls) |call| try require(validBinding(snapshot.units, .{ .unit = call.unit, .binding = call.binding }) and call.evidence < nodes);
    }
    for (proof.views) |view| try require(view.value < values and view.selected < values and view.evidence < nodes);
}

/// Moves validated owned arrays into a Capture. Every allocation precedes the
/// moves, so failure leaves the decoded snapshot as the only owner.
fn adopt(a: A, snapshot: *Snapshot) format.Error!Archive {
    const pins = try a.alloc(metadata.ModulePin, snapshot.units.len);
    var pins_owned = true;
    defer if (pins_owned) a.free(pins);
    const offsets = try a.alloc(usize, snapshot.units.len);
    var offsets_owned = true;
    defer if (offsets_owned) a.free(offsets);
    var context = metadata.Context.init(a);
    var context_owned = true;
    defer if (context_owned) context.deinit();
    var next: usize = 0;
    for (snapshot.units, pins, offsets) |*unit, *pin, *offset| {
        pin.* = .{ .unit = unit.unit, .module = &unit.core, .canonical_path = unit.canonical_path, .stamp = unit.stamp };
        offset.* = next;
        next += unit.core.bindings.len;
    }
    // Rebuild the native selected index in wire order; limits still apply.
    for (snapshot.queries.records) |*record| {
        const proof = &record.dependencies;
        var owned: receipt.Record = .{
            .input = record.key.input,
            .expected = record.key.expected,
            .selected = record.result.selected,
            .options = record.key.options,
            .depth = record.key.depth,
            .values_before = proof.values_before,
            .children_before = proof.children_before,
            .values_added = proof.values_added,
            .children_added = proof.children_added,
            .steps = 0,
            .collected = proof.collected,
            .source_scopes = proof.source_scopes,
            .solver_nodes = proof.solver_nodes,
            .complete = true,
            .sources = proof.sources,
            .scalar_reads = proof.scalar_reads,
            .call_reads = proof.call_reads,
            .call_publications = proof.call_publications,
            .views = proof.views,
            .plain_facts = proof.plain_facts,
        };
        proof.sources = &.{};
        proof.scalar_reads = &.{};
        proof.call_reads = &.{};
        proof.call_publications = &.{};
        proof.views = &.{};
        proof.plain_facts = &.{};
        const closure = snapshot.evaluator.closures[snapshot.evaluator.values[owned.input].bits];
        _ = selected.remember(&context.specialization_queries, a, closure, owned) catch |err| {
            owned = undefined;
            return err;
        };
    }
    context.pools = .{
        .project_identity = true,
        .identity = snapshot.identity,
        .modules = pins,
        .layouts = .{ .nodes = &.{}, .extra = &.{}, .effects = .{ .operations = &.{}, .arguments = &.{}, .rows = &.{}, .labels = &.{} } },
        .evaluator = snapshot.evaluator,
        .rows = .{ .entries = &.{}, .spans = &.{} },
        .templates = .{ .entries = &.{}, .spans = &.{} },
        .captures = &.{},
        .field_locations = snapshot.field_locations,
        .field_locations_stamp = metadata.stamp(snapshot.field_locations),
        .operations = &.{},
        .operation_relocations = &.{},
        .operations_finalized = false,
        .functions = &.{},
        .serialized = &.{},
        .runtime_globals = &.{},
        .runtime_order = &.{},
        .binding_offsets = offsets,
        .node_offsets = &.{},
        .slots = snapshot.slots,
        .visited_nodes = &.{},
        .provider_frames = &.{},
        .provider_cells = &.{},
        .request_cells = &.{},
        .request_handlers = &.{},
        .break_values = &.{},
        .array_proofs = &.{},
        .discard_proofs = &.{},
        .evaluator_steps = 0,
        .evaluator_demanded = 0,
        .evaluator_traced_bodies = 0,
        .evaluator_traced_nodes = 0,
    };
    pins_owned = false;
    offsets_owned = false;
    // The pools now own namespace, evaluator, slots and canonical paths; the
    // Archive keeps the Core array the pins name.
    snapshot.identity = .{ .bytes = &.{}, .symbols = &.{}, .owners = &.{} };
    snapshot.evaluator = emptyEvaluator();
    snapshot.slots = &.{};
    snapshot.field_locations = &.{};
    const units = snapshot.units;
    snapshot.units = &.{};
    context_owned = false;
    return .{ .allocator = a, .units = units, .capture = .{ .metadata = context, .emission = @import("artifact_emitter.zig").Recorder.init(a) } };
}

fn emptyEvaluator() eval.Snapshot {
    return .{ .values = &.{}, .children = &.{}, .closures = &.{}, .value_evidence = &.{}, .type_mappings = &.{}, .row_mappings = &.{}, .evidence = .{ .nodes = &.{}, .extra = &.{}, .effects = .{ .operations = &.{}, .arguments = &.{}, .rows = &.{}, .labels = &.{} } }, .value_records = &.{}, .record_layouts = &.{}, .field_names = &.{}, .demands = &.{} };
}
