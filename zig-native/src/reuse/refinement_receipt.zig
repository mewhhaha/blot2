//! PRIVATE experiment: complete code-refinement queries, independent of code
//! fragment admission. Not a principal scheme and never an evaluated value.
const std = @import("std");
const core = @import("../check/core.zig");
const eval = @import("../eval/core_eval.zig");
const evidence = @import("../eval/type_evidence.zig");
const expectation = @import("code_expectation.zig");
const receipt = @import("specialization_receipt.zig");
const queries = @import("semantic_query_table.zig");
const Allocator = std.mem.Allocator;

pub const Root = union(enum) { body: core.BindingRef, closure: struct { unit: u32, catalog: u32 } };
fn namedOwner(module: *const core.Module, binding: core.BindingId) bool {
    return binding < module.bindings.len and module.body(binding) != null;
}
fn rootOwner(module: *const core.Module, root: Root) bool {
    return switch (root) {
        .body => |body| namedOwner(module, body.binding),
        .closure => |closure| closure.catalog < module.closures.len,
    };
}
fn queryOwners(units: []const core.Module, root: Root, sources: []const core.BindingRef) bool {
    const unit = switch (root) {
        .body => |body| body.unit,
        .closure => |closure| closure.unit,
    };
    if (unit == 0 or unit > units.len or !rootOwner(&units[unit - 1], root)) return false;
    for (sources) |source| {
        if (source.unit == 0 or source.unit > units.len or !namedOwner(&units[source.unit - 1], source.binding)) return false;
    }
    return true;
}
/// Refinement receipts do not own invocation-version relocation, even when
/// the solved result erases a generated identity from an executed helper.
pub fn generativeQuery(a: Allocator, units: []const core.Module, root: Root, sources: []const core.BindingRef) Allocator.Error!bool {
    if (!queryOwners(units, root, sources)) return true;
    const graph = @import("source_value_template.zig");
    const unit = switch (root) {
        .body => |body| body.unit,
        .closure => |closure| closure.unit,
    };
    if (unit == 0 or unit > units.len) return true;
    const generated = switch (root) {
        .body => |body| try graph.generativeNamed(a, &units[unit - 1], body.binding),
        .closure => |closure| try graph.generativeClosure(a, &units[unit - 1], closure.catalog),
    };
    if (generated) return true;
    for (sources) |source| {
        if (source.unit == 0 or source.unit > units.len) return true;
        if (try graph.generativeNamed(a, &units[source.unit - 1], source.binding)) return true;
    }
    return false;
}
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
pub const Key = struct {
    root: Root,
    expected: u32,
    seeds: []evidence.Mapping,
    rows: []evidence.RowMapping,
    options: eval.Options,
    depth: usize,
    pub fn deinit(self: *Key, a: Allocator) void {
        a.free(self.seeds);
        a.free(self.rows);
    }
};
pub const Adapter = struct {
    pub const kind: queries.Kind = .refinement;
    pub const Key = @import("refinement_receipt.zig").Key;
    pub const Dependencies = receipt.Record;
    pub const Result = eval.SolvedEvidence;
    pub fn fingerprint(key: @This().Key) u64 {
        return rootFingerprint(key.root);
    }
    pub fn complete(record_: Record) bool {
        const facts = record_.dependencies;
        return facts.complete and facts.steps == 0 and facts.values_added == 0 and facts.children_added == 0 and facts.views.len == 0 and record_.value.selected.len == 0 and std.meta.eql(record_.key.options, facts.options) and record_.key.depth == facts.depth;
    }
    pub fn bytes(record_: Record) usize {
        var total: usize = 0;
        inline for (.{ "seeds", "rows" }) |field| {
            const entries = @field(record_.key, field);
            total +|= entries.len *| @sizeOf(@TypeOf(entries[0]));
        }
        inline for (.{ "sources", "scalar_reads", "call_reads", "call_publications", "views", "plain_facts" }) |field| {
            const entries = @field(record_.dependencies, field);
            total +|= entries.len *| @sizeOf(@TypeOf(entries[0]));
        }
        inline for (.{ "types", "rows", "selected" }) |field| {
            const entries = @field(record_.value, field);
            total +|= entries.len *| @sizeOf(@TypeOf(entries[0]));
        }
        return total;
    }
};
pub const Table = queries.Table(Adapter);
pub const Record = Table.Record;
fn rootFingerprint(root: Root) u64 {
    var state = std.hash.Wyhash.init(0);
    std.hash.autoHash(&state, root);
    return state.final();
}
pub const Reason = enum { mode, root, source, shape, seed, scalar, call, plain, import };
pub const RecordDecline = enum { owner, source, generative, incomplete, capacity };
pub const Stats = struct {
    record_declines: [@typeInfo(RecordDecline).@"enum".field_names.len]usize = @splat(0),
    call_became_present: usize = 0,
    call_missing: usize = 0,
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
    local_candidates: usize = 0,
    indexed_positions: usize = 0,
    retained_records: usize = 0,
    retained_payload_bytes: usize = 0,
    retained_capacity_bytes: usize = 0,
    saturated: usize = 0,
    body_cutoff_hits: usize = 0,
    reasons: [@typeInfo(Reason).@"enum".field_names.len]usize = @splat(0),
};

/// Complete records in the current Context share its immutable evidence owner.
/// Newest-first is the legacy local priority; exact keys and facts still gate.
pub fn lookupLocal(g: anytype, root: Root, expected: u32, seeds: []const evidence.Mapping, rows: []const evidence.RowMapping) Allocator.Error!?eval.SolvedEvidence {
    const owner = g.refinement_owner orelse return null;
    const session = &g.evaluator;
    if (session.receipt_tape != null or session.principal_reads != null) return null;
    g.refinement_stats.local_requests += 1;
    const table = &owner.refinement_queries;
    const records = table.records.items;
    var cursor = table.candidates(rootFingerprint(root), .newest_first);
    while (cursor.next()) |id| {
        g.refinement_stats.local_candidates += 1;
        g.refinement_stats.indexed_positions += 1;
        const record_ = &records[id];
        const facts = &record_.dependencies;
        if (!std.meta.eql(record_.key.root, root) or record_.key.expected != expected or record_.key.seeds.len != seeds.len or record_.key.rows.len != rows.len) continue;
        var same = true;
        for (record_.key.seeds, seeds) |left, right| same = same and std.meta.eql(left, right);
        for (record_.key.rows, rows) |left, right| same = same and std.meta.eql(left, right);
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
        for (facts.call_reads) |read| if (read.present and !session.specializations.validated_calls.contains(.{ .target = .{ .unit = read.unit - 1, .binding = read.binding }, .evidence = read.evidence })) {
            same = false;
            break;
        };
        for (facts.call_publications) |read| if (!session.specializations.validated_calls.contains(.{ .target = .{ .unit = read.unit - 1, .binding = read.binding }, .evidence = read.evidence })) {
            same = false;
            break;
        };
        for (facts.plain_facts) |fact| {
            const actual = session.specializations.plain_nominals.get(fact.key);
            if ((fact.read and !fact.present) or actual == null or actual.? != fact.plain) {
                same = false;
                break;
            }
        }
        if (!same) continue;
        const result = try copyResult(g.allocator, record_.value);
        g.refinement_stats.local_hits += 1;
        g.refinement_stats.collected_removed += facts.collected;
        g.refinement_stats.nodes_removed += facts.solver_nodes;
        return result;
    }
    return null;
}
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
    // Publication now validates its callable source owner. Keep this local
    // memo law rooted in checked Core instead of a fabricated absent body.
    const source = "const memo = fn value => value";
    var names: @import("../parse/symbols.zig").Pool = .{};
    defer names.deinit(a);
    var tokens = try @import("../parse/lexer.zig").lex(a, source);
    defer tokens.deinit(a);
    var tree = try @import("../parse/parser.zig").parse(a, source, tokens.tokens.items, &names);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try @import("../check/check.zig").checkModule(a, &tree, &names, &.{}, &.{}, 1);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &tree, &names, &checked);
    defer module.deinit(a);
    var g: TestGenerator = .{ .allocator = a, .refinement_owner = &context, .evaluator = try eval.Session.init(a, &.{module}) };
    defer g.evaluator.deinit();
    const root: Root = .{ .body = .{ .unit = 1, .binding = module.bodies[1].binding } };
    const call: eval.CallProofKey = .{ .target = .{ .unit = 0, .binding = 9 }, .evidence = 3 };
    var tape: receipt.Tape = .{};
    defer tape.deinit(a);
    try tape.call_reads.append(a, .{ .unit = 1, .binding = 9, .evidence = 3, .present = false });
    try tape.call_publications.append(a, .{ .unit = 1, .binding = 9, .evidence = 3, .present = true });
    try tape.plain_facts.append(a, .{ .key = 19, .plain = true });
    var types = [_]evidence.Mapping{.{ .variable = 17, .evidence = 3 }};
    const result: eval.SolvedEvidence = .{ .types = &types, .rows = &.{}, .selected = &.{} };
    // Absence of generative forms skips only the deep scan, never ownership.
    try std.testing.expect(!g.evaluator.has_generative_sources);
    const missing: core.BindingRef = .{ .unit = 1, .binding = @intCast(module.bindings.len) };
    try record(&g, .{ .body = missing }, 3, &types, &.{}, result, &tape, .{ .regions = 1 }, g.evaluator.storage.values.items.len, g.evaluator.storage.children.items.len, g.evaluator.steps);
    try record(&g, .{ .closure = .{ .unit = 1, .catalog = @intCast(module.closures.len) } }, 3, &types, &.{}, result, &tape, .{ .regions = 1 }, g.evaluator.storage.values.items.len, g.evaluator.storage.children.items.len, g.evaluator.steps);
    try tape.sources.append(a, missing);
    try record(&g, root, 3, &types, &.{}, result, &tape, .{ .regions = 1 }, g.evaluator.storage.values.items.len, g.evaluator.storage.children.items.len, g.evaluator.steps);
    try std.testing.expectEqual(@as(usize, 0), context.refinement_queries.records.items.len);
    tape.sources.clearRetainingCapacity();
    try record(&g, root, 3, &types, &.{}, result, &tape, .{ .regions = 1 }, g.evaluator.storage.values.items.len, g.evaluator.storage.children.items.len, g.evaluator.steps);
    try std.testing.expect((try lookupLocal(&g, root, 3, &types, &.{})) == null);
    try g.evaluator.specializations.validated_calls.put(a, call, {});
    try g.evaluator.specializations.plain_nominals.put(a, 19, true);
    var hit = (try lookupLocal(&g, root, 3, &types, &.{})) orelse return error.TestUnexpectedResult;
    defer hit.deinit(a);
    try std.testing.expectEqualDeep(result, hit);
    // Returned storage belongs to the caller; changing it cannot poison reuse.
    hit.types[0].evidence = 4;
    var again = (try lookupLocal(&g, root, 3, &types, &.{})) orelse return error.TestUnexpectedResult;
    defer again.deinit(a);
    try std.testing.expectEqual(@as(u32, 3), again.types[0].evidence);
    try std.testing.expect((try lookupLocal(&g, root, 3, &.{.{ .variable = 17, .evidence = 4 }}, &.{})) == null);
    try std.testing.expect((try lookupLocal(&g, .{ .closure = .{ .unit = 1, .catalog = 7 } }, 3, &types, &.{})) == null);
    g.evaluator.options.max_depth -= 1;
    try std.testing.expect((try lookupLocal(&g, root, 3, &types, &.{})) == null);
    g.evaluator.options.max_depth += 1;
    g.evaluator.specializations.plain_nominals.getPtr(19).?.* = false;
    try std.testing.expect((try lookupLocal(&g, root, 3, &types, &.{})) == null);
}

test "local refinement memo preserves dynamic facts identity ownership and failed allocation" {
    try localMemoScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, localMemoScenario, .{});
}
pub fn record(g: anytype, root: Root, expected: u32, seeds: []const evidence.Mapping, rows: []const evidence.RowMapping, result: eval.SolvedEvidence, tape: *receipt.Tape, observed: Observation, before_values: usize, before_children: usize, before_steps: usize) Allocator.Error!void {
    const a = g.allocator;
    const owner = g.refinement_owner orelse {
        g.refinement_stats.record_declines[@backingInt(RecordDecline.owner)] += 1;
        return;
    };
    defer storageStats(g, &owner.refinement_queries);
    if (!queryOwners(g.evaluator.units, root, tape.sources.items)) {
        g.refinement_stats.record_declines[@backingInt(RecordDecline.source)] += 1;
        return;
    }
    if (g.evaluator.has_generative_sources and try generativeQuery(a, g.evaluator.units, root, tape.sources.items)) {
        g.refinement_stats.record_declines[@backingInt(RecordDecline.generative)] += 1;
        return;
    }
    if (root == .body) try tape.sources.append(a, root.body);
    var facts = try tape.finish(a, .{
        .input = 0,
        .expected = 0,
        .selected = 0,
        .options = g.evaluator.options,
        .depth = g.evaluator.depth,
        .values_before = before_values,
        .children_before = before_children,
        .values_added = g.evaluator.storage.values.items.len - before_values,
        .children_added = g.evaluator.storage.children.items.len - before_children,
        .steps = g.evaluator.steps - before_steps,
        .collected = tape.collected,
        .source_scopes = observed.scopes,
        .solver_nodes = observed.nodes,
        .complete = observed.complete and observed.regions == 1 and result.selected.len == 0 and g.evaluator.storage.values.items.len == before_values and g.evaluator.storage.children.items.len == before_children and g.evaluator.steps == before_steps and tape.views.items.len == 0,
        .sources = &.{},
        .scalar_reads = &.{},
        .call_reads = &.{},
        .call_publications = &.{},
        .views = &.{},
        .plain_facts = &.{},
    });
    var owns_facts = true;
    defer if (owns_facts) facts.deinit(a);
    const inputs = try a.dupe(evidence.Mapping, seeds);
    var owns_inputs = true;
    defer if (owns_inputs) a.free(inputs);
    const input_rows = try a.dupe(evidence.RowMapping, rows);
    var builder = Table.begin(a, .{ .root = root, .expected = expected, .seeds = inputs, .rows = input_rows, .options = facts.options, .depth = facts.depth });
    defer builder.abort();
    owns_inputs = false;
    builder.read(facts);
    owns_facts = false;
    builder.stage(try copyResult(a, result));
    var candidate = builder.complete() orelse {
        g.refinement_stats.record_declines[@backingInt(RecordDecline.incomplete)] += 1;
        return;
    };
    defer candidate.abort();
    const prepared = try owner.refinement_queries.prepare(a, &candidate) orelse {
        g.refinement_stats.record_declines[@backingInt(RecordDecline.capacity)] += 1;
        return;
    };
    _ = owner.refinement_queries.publish(prepared, &candidate);
    g.refinement_stats.recorded += 1;
    g.refinement_stats.complete += 1;
}
fn storageStats(g: anytype, table: *const Table) void {
    g.refinement_stats.retained_records = table.records.items.len;
    g.refinement_stats.retained_payload_bytes = table.owned_bytes;
    g.refinement_stats.retained_capacity_bytes = table.capacity_bytes;
    g.refinement_stats.saturated = table.saturated;
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
        .projection, .scoped, .forall, .existential, .bound => return false,
        .absent, .unit, .boolean, .u32, .f32, .never, .erased_proof => return true,
        .usage => return a.b == b.b and sameShape(left, a.a, right, b.a, depth + 1, budget),
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
    defer storageStats(g, &owner.refinement_queries);
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
    const table = &state.old.metadata.refinement_queries;
    var cursor = table.candidates(rootFingerprint(root), .oldest_first);
    while (cursor.next()) |position| {
        g.refinement_stats.indexed_positions += 1;
        const prior = &table.records.items[position];
        if (!std.meta.eql(prior.key.root, root)) continue;
        g.refinement_stats.candidates += 1;
        const facts = &prior.dependencies;
        if (!facts.complete or facts.steps != 0 or facts.values_added != 0 or facts.children_added != 0 or facts.views.len != 0 or facts.depth != g.evaluator.depth or !std.meta.eql(facts.options, g.evaluator.options)) {
            decline(g, .mode);
            continue;
        }
        const root_unit = switch (root) {
            .body => |body| body.unit,
            .closure => |closure| closure.unit,
        };
        // Roots in an edited module are admitted by their declaration's exact
        // projection and identity; the facts below carry the interface cutoff.
        const admitted = switch (root) {
            .body => |body| gate.admitsLocalSource(body),
            .closure => |closure| gate.admitsClosure(closure.unit, closure.catalog),
        };
        if (root_unit == 0 or root_unit > gate.structural_units.len or !admitted) {
            decline(g, .root);
            continue;
        }
        if (!queryOwners(g.evaluator.units, root, facts.sources) or !rootOwner(pools.modules[root_unit - 1].module, root)) {
            decline(g, .source);
            continue;
        }
        var owners_valid = true;
        for (facts.sources) |source| {
            if (source.unit == 0 or source.unit > pools.modules.len or !namedOwner(pools.modules[source.unit - 1].module, source.binding)) {
                owners_valid = false;
                break;
            }
        }
        if (!owners_valid) {
            decline(g, .source);
            continue;
        }
        if (gate.has_generative_sources) {
            if (try generativeQuery(a, g.evaluator.units, root, facts.sources)) {
                decline(g, .source);
                continue;
            }
            const graph = @import("source_value_template.zig");
            const old_module = pools.modules[root_unit - 1].module;
            var generated = switch (root) {
                .body => |body| try graph.generativeNamed(a, old_module, body.binding),
                .closure => |closure| try graph.generativeClosure(a, old_module, closure.catalog),
            };
            for (facts.sources) |source| {
                if (source.unit == 0 or source.unit > pools.modules.len) {
                    generated = true;
                    break;
                }
                if (try graph.generativeNamed(a, pools.modules[source.unit - 1].module, source.binding)) {
                    generated = true;
                    break;
                }
            }
            if (generated) {
                decline(g, .source);
                continue;
            }
        }
        const transitive = gate.admitsReceipt(facts.*);
        var valid = transitive or gate.admitsRefinement(facts.*);
        if (!valid) {
            decline(g, .source);
            continue;
        }
        var budget: usize = 65536;
        if (!sameShape(before_shape, prior.key.expected, shape, expected, 0, &budget)) {
            decline(g, .shape);
            continue;
        }
        if (seeds.len != prior.key.seeds.len or rows.len != prior.key.rows.len) {
            decline(g, .seed);
            continue;
        }
        const maps = try state.pairedImporter();
        if (!maps.enabled) continue;
        for (seeds, prior.key.seeds) |now, old| if (now.variable != old.variable or now.evidence != try maps.importEvidence(g, old.evidence)) {
            valid = false;
            break;
        };
        if (valid) for (rows, prior.key.rows) |now, old| if (now.variable != old.variable or now.evidence != try maps.importSemanticRow(g, old.evidence)) {
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
            const present = g.evaluator.specializations.validated_calls.contains(.{ .target = .{ .unit = read.unit - 1, .binding = read.binding }, .evidence = actual });
            if (present != read.present) {
                if (present) g.refinement_stats.call_became_present += 1 else g.refinement_stats.call_missing += 1;
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
                const current = plain.get(fact.key) orelse g.evaluator.specializations.plain_nominals.get(fact.key);
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
        var output = try copyResult(a, prior.value);
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
        var builder = Table.begin(a, .{ .root = root, .expected = expected, .seeds = next_seeds, .rows = next_rows, .options = next_facts.options, .depth = next_facts.depth });
        defer builder.abort();
        owns_seeds = false;
        owns_rows = false;
        next_facts.values_before = g.evaluator.storage.values.items.len;
        next_facts.children_before = g.evaluator.storage.children.items.len;
        builder.read(next_facts);
        owns_facts = false;
        builder.stage(try copyResult(a, output));
        var candidate = builder.complete() orelse continue;
        defer candidate.abort();
        const prepared = try owner.refinement_queries.prepare(a, &candidate) orelse continue;
        try g.evaluator.specializations.validated_calls.ensureUnusedCapacity(a, @intCast(next_facts.call_publications.len));
        try g.evaluator.specializations.plain_nominals.ensureUnusedCapacity(a, @intCast(plain.count()));
        // Every allocation/import precedes publication. Candidate ownership
        // keeps these facts and the retained receipt out of failed revisions.
        for (next_facts.call_publications) |call| {
            const key: eval.CallProofKey = .{ .target = .{ .unit = call.unit - 1, .binding = call.binding }, .evidence = call.evidence };
            if (!g.evaluator.specializations.validated_calls.contains(key)) g.evaluator.proofs.proof_published += 1;
            g.evaluator.specializations.validated_calls.putAssumeCapacity(key, {});
        }
        var facts_iter = plain.iterator();
        while (facts_iter.next()) |fact| g.evaluator.specializations.plain_nominals.putAssumeCapacity(fact.key_ptr.*, fact.value_ptr.*);
        _ = owner.refinement_queries.publish(prepared, &candidate);
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
