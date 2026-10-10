//! Private independently checked call judgments. No retained value or source
//! inference context crosses this boundary; publication is owned by the query.
const std = @import("std");
const core = @import("core.zig");
const eval = @import("core_eval.zig");
const receipt = @import("specialization_receipt.zig");
const importer = @import("artifact_import.zig");
const layout = @import("layout.zig");
const Allocator = std.mem.Allocator;
pub const ScalarInput = struct { target: core.BindingRef, evidence: u32, value: ?eval.Value };
pub const Record = struct {
    target: core.BindingRef,
    evidence: u32,
    options: eval.Options,
    depth: usize,
    sources: []core.BindingRef,
    scalar_reads: []ScalarInput,
    pub fn deinit(self: *Record, a: Allocator) void {
        a.free(self.sources);
        a.free(self.scalar_reads);
    }
    pub fn clone(self: Record, a: Allocator) Allocator.Error!Record {
        var result = self;
        result.sources = try a.dupe(core.BindingRef, self.sources);
        errdefer a.free(result.sources);
        result.scalar_reads = try a.dupe(ScalarInput, self.scalar_reads);
        return result;
    }
};
fn scalarInput(g: anytype, target: core.BindingRef) ?ScalarInput {
    const module = &g.evaluator.units[target.unit - 1];
    const body = module.body(target.binding) orelse return null;
    const slot = g.evaluator.slots[g.evaluator.binding_offsets[target.unit - 1] + target.binding];
    const actual = if (!body.runtime and slot.state == .complete and g.evaluator.valueInfo(slot.value).kind == .scalar) g.evaluator.valueEvidence(slot.value) else 0;
    if (actual > 4) return null;
    return .{ .target = target, .evidence = actual, .value = if (actual != 0) g.evaluator.valueScalar(slot.value) else null };
}
fn scalarMatches(g: anytype, read: ScalarInput) bool {
    const actual = scalarInput(g, read.target) orelse return false;
    return std.meta.eql(actual, read);
}
pub fn acquire(state: anytype, g: anytype, read: receipt.CallRead, actual: u32) Allocator.Error!?Record {
    const a = state.allocator;
    const target: core.BindingRef = .{ .unit = read.unit, .binding = read.binding };
    if (!state.gate.admits(target)) return null;
    if (comptime @hasField(@TypeOf(state.*), "completed_worker_proofs")) {
        for (state.completed_worker_proofs.items) |record| {
            if (!std.meta.eql(record.target, target) or record.evidence != actual or record.depth != g.evaluator.depth or !std.meta.eql(record.options, g.evaluator.options)) continue;
            var valid = true;
            for (record.sources) |source| if (!state.gate.admits(source)) {
                valid = false;
                break;
            };
            if (valid) for (record.scalar_reads) |input| if (!scalarMatches(g, input)) {
                valid = false;
                break;
            };
            if (!valid) continue;
            state.stats.independent_reused += 1;
            return try record.clone(a);
        }
    }
    for (state.old.metadata.independent_calls.items) |record| {
        if (!std.meta.eql(record.target, target) or record.evidence != read.evidence or record.depth != g.evaluator.depth or !std.meta.eql(record.options, g.evaluator.options)) continue;
        var valid = true;
        for (record.sources) |source| if (!state.gate.admits(source)) {
            valid = false;
            break;
        };
        if (valid) for (record.scalar_reads) |input| {
            if (!state.gate.admits(input.target) or !scalarMatches(g, input)) {
                valid = false;
                break;
            }
        };
        if (!valid) continue;
        var result = try record.clone(a);
        result.evidence = actual;
        state.stats.independent_reused += 1;
        return result;
    }
    const result = try recheck(state, g, read, actual);
    if (result != null) state.stats.independent_rechecked += 1 else state.stats.independent_declined += 1;
    return result;
}
fn recheck(state: anytype, g: anytype, read: receipt.CallRead, actual: u32) Allocator.Error!?Record {
    const a = state.allocator;
    const target: core.BindingRef = .{ .unit = read.unit, .binding = read.binding };
    const Probe = struct { evaluator: eval.Session, layouts: layout.Store };
    var probe: Probe = .{ .evaluator = try eval.Session.init(a, g.evaluator.units), .layouts = undefined };
    defer probe.evaluator.deinit();
    probe.layouts = layout.Store.init(a) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
    defer probe.layouts.deinit();
    probe.evaluator.options = g.evaluator.options;
    probe.evaluator.depth = g.evaluator.depth;
    probe.evaluator.seedScalarInputs(&g.evaluator) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Declined, error.RequestUnwind => return null,
    };
    var maps = (try importer.Importer.initIndependentQuery(a, &state.old.metadata.pools.?, g.evaluator.units, &state.gate)) orelse return null;
    defer maps.deinit();
    const expected = (try maps.importEvidence(&probe, read.evidence)) orelse return null;
    var tape: receipt.Tape = .{};
    defer tape.deinit(a);
    var observation: @import("refinement_receipt.zig").Observation = .{};
    probe.evaluator.receipt_tape = &tape;
    probe.evaluator.refinement_observation = &observation;
    const before_values = probe.evaluator.values.items.len;
    const before_children = probe.evaluator.children.items.len;
    const proved = probe.evaluator.recheckCallProof(target, expected) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Declined, error.RequestUnwind => return null,
    };
    if (!proved or probe.evaluator.diagnostic != null or tape.unknown or tape.nested or tape.views.items.len != 0 or observation.regions != 1 or !observation.complete or probe.evaluator.steps != 0 or probe.evaluator.values.items.len != before_values or probe.evaluator.children.items.len != before_children) return null;
    // Recheck has no incoming call certificates or plain-data facts.
    // Its primitive values are independent copies of checked current inputs.
    // Negative call reads trigger ordinary source inference. A successful
    // judgment therefore has no external call-presence premise to replay.
    for (tape.call_reads.items) |input| if (input.present) return null;
    var scalar_reads: std.ArrayList(ScalarInput) = .empty;
    defer scalar_reads.deinit(a);
    for (tape.scalar_reads.items) |input| {
        if (!state.gate.admits(input.target)) return null;
        const actual_read = scalarInput(g, input.target) orelse return null;
        if (actual_read.evidence != input.evidence) return null;
        try scalar_reads.append(a, actual_read);
    }
    try tape.sources.append(a, target);
    for (tape.sources.items) |source| if (!state.gate.admits(source)) return null;
    const sources = try tape.sources.toOwnedSlice(a);
    errdefer a.free(sources);
    return .{ .target = target, .evidence = actual, .options = g.evaluator.options, .depth = g.evaluator.depth, .sources = sources, .scalar_reads = try scalar_reads.toOwnedSlice(a) };
}
