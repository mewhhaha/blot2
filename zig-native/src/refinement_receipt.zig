//! PRIVATE experiment: complete code-refinement queries, independent of code
//! fragment admission. Not a principal scheme and never an evaluated value.
const std = @import("std");
const core = @import("core.zig");
const eval = @import("core_eval.zig");
const evidence = @import("type_evidence.zig");
const expectation = @import("code_expectation.zig");
const receipt = @import("specialization_receipt.zig");
const Allocator = std.mem.Allocator;

pub const Root = union(enum) { body: core.BindingRef, closure: struct { unit: u32, catalog: u32 } };
pub const Observation = struct {
    regions: usize = 0,
    scopes: usize = 0,
    nodes: usize = 0,
    complete: bool = true,
    pub fn observe(self: *Observation, region: anytype) void {
        self.regions += 1;
        self.scopes += region.scratch.sources.items.len;
        self.nodes += region.solver.nodes.items.len;
        self.complete = self.complete and !region.source_interface and !region.retain_selected and !region.complete_demand_bodies;
        for (region.scratch.constraints.items) |constraint| self.complete = self.complete and constraint.solved;
    }
};
pub const Record = struct {
    root: Root,
    expected: u32,
    seeds: []evidence.Mapping,
    rows: []evidence.RowMapping,
    result: eval.SolvedEvidence,
    facts: receipt.Record,
    pub fn deinit(self: *Record, a: Allocator) void {
        a.free(self.seeds);
        a.free(self.rows);
        self.result.deinit(a);
        self.facts.deinit(a);
    }
};
pub const Reason = enum { mode, root, source, shape, seed, scalar, call, plain, import };
pub const Stats = struct {
    requests: usize = 0,
    recorded: usize = 0,
    complete: usize = 0,
    candidates: usize = 0,
    hits: usize = 0,
    collected_removed: usize = 0,
    nodes_removed: usize = 0,
    publications: usize = 0,
    local_requests: usize = 0,
    local_hits: usize = 0,
    body_cutoff_hits: usize = 0,
    reasons: [@typeInfo(Reason).@"enum".field_names.len]usize = @splat(0),
};

/// Answers completed in this Generator already belong to its evidence owner.
/// This index contains receipt positions, never pointers into growing arrays.
pub const Memo = struct {
    buckets: std.AutoHashMapUnmanaged(u64, usize) = .empty,
    next: std.ArrayList(?usize) = .empty,
    pub fn deinit(self: *Memo, a: Allocator) void {
        self.buckets.deinit(a);
        self.next.deinit(a);
    }
    fn hash(root: Root, expected: u32, seeds: []const evidence.Mapping, rows: []const evidence.RowMapping) u64 {
        var state = std.hash.Wyhash.init(0);
        std.hash.autoHash(&state, root);
        std.hash.autoHash(&state, expected);
        for (seeds) |seed| std.hash.autoHash(&state, seed);
        for (rows) |row| std.hash.autoHash(&state, row);
        return state.final();
    }
    pub fn lookup(self: *Memo, g: anytype, root: Root, expected: u32, seeds: []const evidence.Mapping, rows: []const evidence.RowMapping) Allocator.Error!?eval.SolvedEvidence {
        const owner = g.refinement_owner orelse return null;
        const session = &g.evaluator;
        if (session.receipt_tape != null or session.principal_reads != null) return null;
        g.refinement_stats.local_requests += 1;
        const records = owner.refinement_receipts.items;
        try self.next.ensureTotalCapacity(g.allocator, records.len);
        while (self.next.items.len < records.len) {
            const id = self.next.items.len;
            const record_ = records[id];
            if (!record_.facts.complete) {
                self.next.appendAssumeCapacity(null);
                continue;
            }
            const bucket = try self.buckets.getOrPut(g.allocator, hash(record_.root, record_.expected, record_.seeds, record_.rows));
            self.next.appendAssumeCapacity(if (bucket.found_existing) bucket.value_ptr.* else null);
            bucket.value_ptr.* = id;
        }
        var candidate = self.buckets.get(hash(root, expected, seeds, rows));
        while (candidate) |id| {
            candidate = self.next.items[id];
            const record_ = &records[id];
            const facts = &record_.facts;
            if (!std.meta.eql(record_.root, root) or record_.expected != expected or record_.seeds.len != seeds.len or record_.rows.len != rows.len) continue;
            var same = true;
            for (record_.seeds, seeds) |left, right| same = same and std.meta.eql(left, right);
            for (record_.rows, rows) |left, right| same = same and std.meta.eql(left, right);
            if (!same or !std.meta.eql(facts.options, session.options) or facts.depth != session.depth or facts.steps != 0 or facts.values_added != 0 or facts.children_added != 0 or facts.views.len != 0) continue;
            for (facts.scalar_reads) |read| {
                const module = &session.units[read.target.unit - 1];
                const body = module.body(read.target.binding).?;
                const slot = session.slots[session.binding_offsets[read.target.unit - 1] + read.target.binding];
                const actual = if (!body.runtime and slot.state == .complete and session.valueInfo(slot.value).kind == .scalar) session.valueEvidence(slot.value) else 0;
                if (read.evidence != actual) {
                    same = false;
                    break;
                }
            }
            if (!same) continue;
            // Closed call proofs only accumulate within this immutable Session.
            // A now-present proof may skip previously successful work; it cannot
            // change that completed result. Publications must still be present.
            for (facts.call_reads) |read| if (read.present and !session.validated_calls.contains(.{ .target = .{ .unit = read.unit - 1, .binding = read.binding }, .evidence = read.evidence })) {
                same = false;
                break;
            };
            for (facts.call_publications) |read| if (!session.validated_calls.contains(.{ .target = .{ .unit = read.unit - 1, .binding = read.binding }, .evidence = read.evidence })) {
                same = false;
                break;
            };
            for (facts.plain_facts) |fact| {
                const actual = session.plain_nominals.get(fact.key);
                if ((fact.read and !fact.present) or actual == null or actual.? != fact.plain) {
                    same = false;
                    break;
                }
            }
            if (!same) continue;
            const result = try copyResult(g.allocator, record_.result);
            g.refinement_stats.local_hits += 1;
            g.refinement_stats.collected_removed += facts.collected;
            g.refinement_stats.nodes_removed += facts.solver_nodes;
            return result;
        }
        return null;
    }
};
fn decline(g: anytype, reason: Reason) void {
    g.refinement_stats.reasons[@backingInt(reason)] += 1;
}
fn copyResult(a: Allocator, result: eval.SolvedEvidence) Allocator.Error!eval.SolvedEvidence {
    const types = try a.dupe(evidence.Mapping, result.types);
    errdefer a.free(types);
    const rows = try a.dupe(evidence.RowMapping, result.rows);
    errdefer a.free(rows);
    return .{ .types = types, .rows = rows, .selected = try a.dupe(core.BindingRef, result.selected) };
}

fn localMemoScenario(a: Allocator) !void {
    var context = @import("code_artifacts.zig").Context.init(a);
    defer context.deinit();
    const TestGenerator = struct {
        allocator: Allocator,
        refinement_owner: ?*@import("code_artifacts.zig").Context,
        evaluator: eval.Session,
        refinement_stats: Stats = .{},
    };
    var g: TestGenerator = .{ .allocator = a, .refinement_owner = &context, .evaluator = try eval.Session.init(a, &.{}) };
    defer g.evaluator.deinit();
    var memo: Memo = .{};
    defer memo.deinit(a);
    const root: Root = .{ .body = .{ .unit = 1, .binding = 7 } };
    const call: eval.CallProofKey = .{ .target = .{ .unit = 0, .binding = 9 }, .evidence = 3 };
    var tape: receipt.Tape = .{};
    defer tape.deinit(a);
    try tape.call_reads.append(a, .{ .unit = 1, .binding = 9, .evidence = 3, .present = false });
    try tape.call_publications.append(a, .{ .unit = 1, .binding = 9, .evidence = 3, .present = true });
    try tape.plain_facts.append(a, .{ .key = 19, .plain = true });
    var types = [_]evidence.Mapping{.{ .variable = 17, .evidence = 3 }};
    const result: eval.SolvedEvidence = .{ .types = &types, .rows = &.{}, .selected = &.{} };
    try record(&g, root, 3, &types, &.{}, result, &tape, .{ .regions = 1 }, g.evaluator.values.items.len, g.evaluator.children.items.len, g.evaluator.steps);
    try std.testing.expect((try memo.lookup(&g, root, 3, &types, &.{})) == null);
    try g.evaluator.validated_calls.put(a, call, {});
    try g.evaluator.plain_nominals.put(a, 19, true);
    var hit = (try memo.lookup(&g, root, 3, &types, &.{})) orelse return error.TestUnexpectedResult;
    defer hit.deinit(a);
    try std.testing.expectEqualDeep(result, hit);
    // Returned storage belongs to the caller; changing it cannot poison reuse.
    hit.types[0].evidence = 4;
    var again = (try memo.lookup(&g, root, 3, &types, &.{})) orelse return error.TestUnexpectedResult;
    defer again.deinit(a);
    try std.testing.expectEqual(@as(u32, 3), again.types[0].evidence);
    try std.testing.expect((try memo.lookup(&g, root, 3, &.{.{ .variable = 17, .evidence = 4 }}, &.{})) == null);
    try std.testing.expect((try memo.lookup(&g, .{ .closure = .{ .unit = 1, .catalog = 7 } }, 3, &types, &.{})) == null);
    g.evaluator.options.max_depth -= 1;
    try std.testing.expect((try memo.lookup(&g, root, 3, &types, &.{})) == null);
    g.evaluator.options.max_depth += 1;
    g.evaluator.plain_nominals.getPtr(19).?.* = false;
    try std.testing.expect((try memo.lookup(&g, root, 3, &types, &.{})) == null);
}

test "local refinement memo preserves dynamic facts identity ownership and failed allocation" {
    try localMemoScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, localMemoScenario, .{});
}
pub fn record(g: anytype, root: Root, expected: u32, seeds: []const evidence.Mapping, rows: []const evidence.RowMapping, result: eval.SolvedEvidence, tape: *receipt.Tape, observed: Observation, before_values: usize, before_children: usize, before_steps: usize) Allocator.Error!void {
    const a = g.allocator;
    const owner = g.refinement_owner orelse return;
    if (root == .body) try tape.sources.append(a, root.body);
    var facts = try tape.finish(a, .{
        .input = 0,
        .expected = 0,
        .selected = 0,
        .options = g.evaluator.options,
        .depth = g.evaluator.depth,
        .values_before = before_values,
        .children_before = before_children,
        .values_added = g.evaluator.values.items.len - before_values,
        .children_added = g.evaluator.children.items.len - before_children,
        .steps = g.evaluator.steps - before_steps,
        .collected = tape.collected,
        .source_scopes = observed.scopes,
        .solver_nodes = observed.nodes,
        .complete = observed.complete and observed.regions == 1 and result.selected.len == 0 and g.evaluator.values.items.len == before_values and g.evaluator.children.items.len == before_children and g.evaluator.steps == before_steps and tape.views.items.len == 0,
        .sources = &.{},
        .scalar_reads = &.{},
        .call_reads = &.{},
        .call_publications = &.{},
        .views = &.{},
        .plain_facts = &.{},
    });
    errdefer facts.deinit(a);
    const inputs = try a.dupe(evidence.Mapping, seeds);
    errdefer a.free(inputs);
    const input_rows = try a.dupe(evidence.RowMapping, rows);
    errdefer a.free(input_rows);
    var output = try copyResult(a, result);
    errdefer output.deinit(a);
    try owner.refinement_receipts.append(a, .{ .root = root, .expected = expected, .seeds = inputs, .rows = input_rows, .result = output, .facts = facts });
    g.refinement_stats.recorded += 1;
    g.refinement_stats.complete += @intFromBool(facts.complete);
}

// Gate namespace equality certifies producer and symbol ordinals. Graph IDs
// still belong to their respective owners. Each hole occurrence stays a hole;
// comparison introduces no equality between separately instantiated holes.
fn sameShape(left: expectation.View, l: u32, right: expectation.View, r: u32, depth: usize, budget: *usize) bool {
    if (depth >= 1024 or budget.* == 0 or l >= left.nodes.len or r >= right.nodes.len) return false;
    budget.* -= 1;
    if (l == 0 or r == 0) return l == 0 and r == 0;
    const a = left.node(l);
    const b = right.node(r);
    if (a.tag != b.tag) return false;
    switch (a.tag) {
        .absent, .unit, .boolean, .u32, .f32, .never => return true,
        .type_constructor => return a.a == b.a and a.b == b.b,
        .function => return sameShape(left, a.a, right, b.a, depth + 1, budget) and sameShape(left, a.b, right, b.b, depth + 1, budget),
        .array, .list, .cursor, .resolver, .demand, .provider => return sameShape(left, a.a, right, b.a, depth + 1, budget),
        .state_provider => return sameShape(left, a.a, right, b.a, depth + 1, budget) and sameShape(left, a.b, right, b.b, depth + 1, budget) and sameShape(left, a.c, right, b.c, depth + 1, budget),
        .product, .record, .nominal => {
            if (a.tag == .nominal and (a.a != b.a or a.b != b.b)) return false;
            const lc = left.children(l);
            const rc = right.children(r);
            if (lc.len != rc.len) return false;
            for (lc, rc, 0..) |li, ri, index| {
                if (a.tag == .record and index % 2 == 0) {
                    if (li != ri) return false;
                } else if (!sameShape(left, li, right, ri, depth + 1, budget)) return false;
            }
            return true;
        },
    }
}

test "refinement receipt partial shape keys preserve holes owners collection kinds and physical record order" {
    const a = std.testing.allocator;
    var left = try expectation.Store.init(a);
    defer left.deinit();
    var right = try expectation.Store.init(a);
    defer right.deinit();
    const l_list = try left.intern(.list, 3, 0, &.{});
    const r_array = try right.intern(.array, 3, 0, &.{});
    const r_list = try right.intern(.list, 3, 0, &.{});
    const lp = try left.intern(.function, 0, l_list, &.{});
    const rp = try right.intern(.function, 0, r_list, &.{});
    var budget: usize = 1000;
    try std.testing.expect(sameShape(left.view(), lp, right.view(), rp, 0, &budget));
    try std.testing.expect(!sameShape(left.view(), l_list, right.view(), r_array, 0, &budget));
    const concrete = try right.intern(.function, 3, r_list, &.{});
    try std.testing.expect(!sameShape(left.view(), lp, right.view(), concrete, 0, &budget));
    const nl = try left.intern(.nominal, 1, 7, &.{0});
    const nr = try right.intern(.nominal, 2, 7, &.{0});
    try std.testing.expect(!sameShape(left.view(), nl, right.view(), nr, 0, &budget));
    const lr = try left.intern(.record, 0, 0, &.{ 9, 3, 10, 4 });
    const rr = try right.intern(.record, 0, 0, &.{ 10, 4, 9, 3 });
    try std.testing.expect(!sameShape(left.view(), lr, right.view(), rr, 0, &budget));
}
pub fn lookup(g: anytype, root: Root, shape: expectation.View, expected: u32, seeds: []const evidence.Mapping, rows: []const evidence.RowMapping) Allocator.Error!?eval.SolvedEvidence {
    const state = g.query_state orelse return null;
    const owner = g.artifacts orelse return null;
    const gate = &state.gate;
    const a = g.allocator;
    const ordinary: eval.Options = .{ .trace_runtime_dependencies = true, .retain_source_suspensions = true };
    if (!gate.enabled or g.evaluator.receipt_tape != null or !std.meta.eql(g.evaluator.options, ordinary) or g.evaluator.depth != 0 or gate.units.ptr != g.evaluator.units.ptr or gate.units.len != g.evaluator.units.len or state.allocator.ptr != a.ptr or state.allocator.vtable != a.vtable) {
        decline(g, .mode);
        return null;
    }
    const pools = &state.old.metadata.pools.?;
    const bridge = pools.bridge orelse return null;
    const before_shape: expectation.View = .{ .nodes = bridge.nodes, .extra = bridge.extra };
    for (state.old.metadata.refinement_receipts.items) |*prior| {
        if (!std.meta.eql(prior.root, root)) continue;
        g.refinement_stats.candidates += 1;
        const facts = &prior.facts;
        if (!facts.complete or facts.steps != 0 or facts.values_added != 0 or facts.children_added != 0 or facts.views.len != 0 or facts.depth != g.evaluator.depth or !std.meta.eql(facts.options, g.evaluator.options)) {
            decline(g, .mode);
            continue;
        }
        const root_unit = switch (root) {
            .body => |body| body.unit,
            .closure => |closure| closure.unit,
        };
        const cutoff = g.reuse_body_proof_cutoff;
        if (root_unit == 0 or root_unit > gate.structural_units.len or !gate.structural_units[root_unit - 1] or (root == .body and !(if (cutoff) gate.admitsLocalSource(root.body) else gate.admits(root.body)))) {
            decline(g, .root);
            continue;
        }
        const transitive = gate.admitsReceipt(facts.*);
        var valid = transitive or (cutoff and gate.admitsRefinement(facts.*));
        if (!valid) {
            decline(g, .source);
            continue;
        }
        var budget: usize = 65536;
        if (!sameShape(before_shape, prior.expected, shape, expected, 0, &budget)) {
            decline(g, .shape);
            continue;
        }
        if (seeds.len != prior.seeds.len or rows.len != prior.rows.len) {
            decline(g, .seed);
            continue;
        }
        const maps = try state.pairedImporter();
        if (!maps.enabled) continue;
        for (seeds, prior.seeds) |now, old| if (now.variable != old.variable or now.evidence != try maps.importEvidence(g, old.evidence)) {
            valid = false;
            break;
        };
        if (valid) for (rows, prior.rows) |now, old| if (now.variable != old.variable or now.evidence != try maps.importSemanticRow(g, old.evidence)) {
            valid = false;
            break;
        };
        if (!valid) {
            decline(g, .seed);
            continue;
        }
        for (facts.scalar_reads) |read| {
            const module = &gate.units[read.target.unit - 1];
            const body = module.body(read.target.binding).?;
            const slot = g.evaluator.slots[g.evaluator.binding_offsets[read.target.unit - 1] + read.target.binding];
            const actual = if (!body.runtime and slot.state == .complete and g.evaluator.valueInfo(slot.value).kind == .scalar) g.evaluator.valueEvidence(slot.value) else 0;
            const old = if (read.evidence == 0) @as(?u32, 0) else try maps.importEvidence(g, read.evidence);
            if (old != actual) {
                valid = false;
                break;
            }
        }
        if (!valid) {
            decline(g, .scalar);
            continue;
        }
        for (facts.call_reads) |read| {
            const actual = (try maps.importEvidence(g, read.evidence)) orelse {
                valid = false;
                break;
            };
            if (g.evaluator.validated_calls.contains(.{ .target = .{ .unit = read.unit - 1, .binding = read.binding }, .evidence = actual }) != read.present) {
                valid = false;
                break;
            }
        }
        if (!valid) {
            decline(g, .call);
            continue;
        }
        var plain: std.AutoHashMapUnmanaged(u64, bool) = .empty;
        defer plain.deinit(a);
        for (facts.plain_facts) |fact| {
            const unit: u32 = @intCast(fact.key >> 32);
            if (unit == 0 or unit > gate.units.len or !gate.structural_units[unit - 1]) {
                valid = false;
                break;
            }
            if (fact.read) {
                const current = plain.get(fact.key) orelse g.evaluator.plain_nominals.get(fact.key);
                if ((fact.present and (current == null or current.? != fact.plain)) or (!fact.present and current != null)) {
                    valid = false;
                    break;
                }
            } else try plain.put(a, fact.key, fact.plain);
        }
        if (!valid) {
            decline(g, .plain);
            continue;
        }
        var next_facts = try facts.clone(a);
        var owns_facts = true;
        defer if (owns_facts) next_facts.deinit(a);
        var output = try copyResult(a, prior.result);
        var owns_output = true;
        defer if (owns_output) output.deinit(a);
        for (output.types) |*mapping| mapping.evidence = (try maps.importEvidence(g, mapping.evidence)) orelse {
            valid = false;
            break;
        };
        if (valid) for (output.rows) |*mapping| {
            mapping.evidence = (try maps.importSemanticRow(g, mapping.evidence)) orelse {
                valid = false;
                break;
            };
        };
        if (valid) for (next_facts.scalar_reads) |*read| {
            if (read.evidence != 0) read.evidence = (try maps.importEvidence(g, read.evidence)) orelse {
                valid = false;
                break;
            };
        };
        if (valid) for (next_facts.call_reads) |*read| {
            read.evidence = (try maps.importEvidence(g, read.evidence)) orelse {
                valid = false;
                break;
            };
        };
        if (valid) for (next_facts.call_publications) |*read| {
            read.evidence = (try maps.importEvidence(g, read.evidence)) orelse {
                valid = false;
                break;
            };
        };
        if (!valid) {
            decline(g, .import);
            continue;
        }
        const next_seeds = try a.dupe(evidence.Mapping, seeds);
        var owns_seeds = true;
        defer if (owns_seeds) a.free(next_seeds);
        const next_rows = try a.dupe(evidence.RowMapping, rows);
        var owns_rows = true;
        defer if (owns_rows) a.free(next_rows);
        var next_output = try copyResult(a, output);
        var owns_next_output = true;
        defer if (owns_next_output) next_output.deinit(a);
        try g.evaluator.validated_calls.ensureUnusedCapacity(a, @intCast(next_facts.call_publications.len));
        try g.evaluator.plain_nominals.ensureUnusedCapacity(a, @intCast(plain.count()));
        try owner.refinement_receipts.ensureUnusedCapacity(a, 1);
        // Every allocation/import precedes publication. Candidate ownership
        // keeps these facts and the retained receipt out of failed revisions.
        for (next_facts.call_publications) |call| {
            const key: eval.CallProofKey = .{ .target = .{ .unit = call.unit - 1, .binding = call.binding }, .evidence = call.evidence };
            if (!g.evaluator.validated_calls.contains(key)) g.evaluator.proofs.proof_published += 1;
            g.evaluator.validated_calls.putAssumeCapacity(key, {});
        }
        var facts_iter = plain.iterator();
        while (facts_iter.next()) |fact| g.evaluator.plain_nominals.putAssumeCapacity(fact.key_ptr.*, fact.value_ptr.*);
        next_facts.values_before = g.evaluator.values.items.len;
        next_facts.children_before = g.evaluator.children.items.len;
        owner.refinement_receipts.appendAssumeCapacity(.{ .root = root, .expected = expected, .seeds = next_seeds, .rows = next_rows, .result = next_output, .facts = next_facts });
        owns_facts = false;
        owns_seeds = false;
        owns_rows = false;
        owns_next_output = false;
        owns_output = false;
        for (facts.call_reads) |read| if (read.present) {
            g.evaluator.proofs.proof_reused += 1;
        };
        g.refinement_stats.hits += 1;
        g.refinement_stats.body_cutoff_hits += @intFromBool(!transitive);
        g.refinement_stats.recorded += 1;
        g.refinement_stats.complete += 1;
        g.refinement_stats.collected_removed += facts.collected;
        g.refinement_stats.nodes_removed += facts.solver_nodes;
        g.refinement_stats.publications += facts.call_publications.len;
        return output;
    }
    return null;
}
