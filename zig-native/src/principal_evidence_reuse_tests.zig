//! Complete backend principal-prepass reuse laws. Frozen Core remains alive
//! while its independently owned retained backend capture is replayed.
const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const artifacts = @import("code_artifacts.zig");
const capture = @import("artifact_capture.zig");
const identity = @import("runtime_identity.zig");
const a = std.testing.allocator;

const Fixture = struct {
    units: []core.Module,
    names: identity.Metadata,

    fn init(source: []const u8) !Fixture {
        var tokens = try lexer.lex(a, source);
        defer tokens.deinit(a);
        var names: symbols.Pool = .{};
        defer names.deinit(a);
        // Both catalog edits retain their complete qualified spellings in the
        // same namespace, so rejection exercises changed Core catalog facts.
        _ = try names.intern(a, "U32.add");
        _ = try names.intern(a, "U32.sub");
        var tree = try parser.parse(a, source, tokens.tokens.items, &names);
        defer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try checker.checkModuleWithOptions(a, &tree, &names, &.{}, &.{}, 1, .{ .builtin_catalog = true });
        defer checked.deinit(a);
        for (checked.diagnostics) |issue| std.debug.print("principal fixture check {s}: {s} at {d}\n", .{ @tagName(issue.code), issue.message(), issue.span.start });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        const units = try a.alloc(core.Module, 1);
        errdefer a.free(units);
        units[0] = try core.lower(a, &tree, &names, &checked);
        errdefer units[0].deinit(a);
        try std.testing.expectEqual(@as(usize, 0), units[0].diagnostics.len);
        return .{ .units = units, .names = try identity.Metadata.capture(a, &names, &.{.{ .unit = 1, .path = "/principal-reuse/main.blot" }}, 1) };
    }

    fn target(self: *const Fixture, name: []const u8) core.BindingRef {
        for (self.units[0].bodies[1..]) |body| if (std.mem.eql(u8, self.units[0].name(body.export_name), name)) return .{ .unit = 1, .binding = body.binding };
        unreachable;
    }

    fn emit(self: *const Fixture, allocator: std.mem.Allocator, options: backend.CompileOptions) !backend.Result {
        var configured = options;
        configured.identity = self.names.view();
        return backend.compileWithOptions(allocator, self.units, 1, configured);
    }

    fn deinit(self: *Fixture) void {
        for (self.units) |*unit| unit.deinit(a);
        a.free(self.units);
        self.names.deinit(a);
        self.* = undefined;
    }
};

const positive_source =
    \\const identity = fn value => value
    \\entry const schema: U32 = 7
    \\entry const builder: U32 where { type_rep U32 } = identity 42
;

fn successful(result: *const backend.Result) !void {
    if (result.diagnostic) |issue| std.debug.print("principal reuse backend {s}: {s}\n", .{ @tagName(issue.code), issue.message() });
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}

fn equalEmission(fresh: *const backend.Result, reused: *const backend.Result) !void {
    try successful(fresh);
    try successful(reused);
    try std.testing.expectEqualSlices(u8, fresh.bytes, reused.bytes);
    try std.testing.expectEqual(fresh.constant_steps, reused.constant_steps);
    try std.testing.expectEqual(fresh.code_instances, reused.code_instances);
    try std.testing.expectEqual(fresh.callable_wrappers, reused.callable_wrappers);
}

fn savedProof(old: *const capture.Capture, target: core.BindingRef) ?*const artifacts.PrincipalProof {
    for (old.metadata.principal_proofs.items) |*proof| if (std.meta.eql(proof.target, target)) return proof;
    return null;
}

test "principal cache reuses unchanged nonfunction prepass after independent scalar schema edit with fresh output and evaluation" {
    var before = try Fixture.init(positive_source);
    defer before.deinit();
    var after = try Fixture.init(positive_source);
    defer after.deinit();
    const schema = after.target("schema");
    after.units[0].nodes[after.units[0].body(schema.binding).?.root].a = 8;
    const builder = before.target("builder");
    const body = before.units[0].body(builder.binding).?;
    try std.testing.expect(!body.is_function);
    try std.testing.expect(body.scheme.obligations.len > 0);
    const old_core = artifacts.stamp(before.units);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const old = &initial.capture.?;
    try std.testing.expect(savedProof(old, builder) != null);
    try std.testing.expect(initial.principal.captured > 0);
    try std.testing.expect(initial.principal.fresh_regions > 0);
    var fresh = try after.emit(a, .{ .retain_artifacts = true });
    defer fresh.deinit(a);
    var reused = try after.emit(a, .{ .previous = old, .retain_artifacts = true });
    defer reused.deinit(a);
    try equalEmission(&fresh, &reused);
    try std.testing.expect(!std.mem.eql(u8, initial.bytes, reused.bytes));
    try std.testing.expect(reused.principal.requests > 0);
    try std.testing.expect(reused.principal.hits > 0);
    try std.testing.expect(reused.principal.fresh_unit_requests > 0);
    try std.testing.expect(reused.principal.fresh_unit_hits > 0);
    try std.testing.expectEqual(@as(usize, 0), reused.principal.evidence_declined);
    try std.testing.expect(reused.principal.fresh_regions < fresh.principal.fresh_regions);
    try std.testing.expect(savedProof(&reused.capture.?, after.target("builder")) != null);
    try std.testing.expectEqualSlices(u8, &old_core, &artifacts.stamp(before.units));
}

test "principal cache imports closed row facts from a qualified local generic builder" {
    const source =
        \\entry const schema: U32 = 7
        \\entry const builder: U32 where { type_rep U32 } = do:
        \\  let local = fn value => value
        \\  return local 42
    ;
    var before = try Fixture.init(source);
    defer before.deinit();
    var after = try Fixture.init(source);
    defer after.deinit();
    const schema = after.target("schema");
    after.units[0].nodes[after.units[0].body(schema.binding).?.root].a = 8;
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const old = &initial.capture.?;
    const proof = savedProof(old, before.target("builder")) orelse return error.TestExpectedPrincipalCapture;
    try std.testing.expect(proof.rows.len > 0);
    for (proof.rows) |mapping| try std.testing.expectEqual(@as(u32, 0), mapping.evidence);
    var fresh = try after.emit(a, .{ .retain_artifacts = true });
    defer fresh.deinit(a);
    var reused = try after.emit(a, .{ .previous = old, .retain_artifacts = true });
    defer reused.deinit(a);
    try equalEmission(&fresh, &reused);
    try std.testing.expect(reused.principal.hits > 0);
    try std.testing.expectEqual(@as(usize, 0), reused.principal.evidence_declined);
    try std.testing.expect(reused.principal.fresh_regions < fresh.principal.fresh_regions);
    const imported = savedProof(&reused.capture.?, after.target("builder")) orelse return error.TestExpectedPrincipalCapture;
    try std.testing.expectEqualDeep(proof.rows, imported.rows);
    try std.testing.expect(proof.rows.ptr != imported.rows.ptr);
}

test "principal cache rejects changed transitive staged dependencies and matches fresh emission" {
    const source =
        \\const identity = fn value => value
        \\entry const schema: U32 = 7
        \\entry const intermediate: U32 = schema
        \\entry const builder: U32 where { type_rep U32 } = identity intermediate
    ;
    var before = try Fixture.init(source);
    defer before.deinit();
    var after = try Fixture.init(source);
    defer after.deinit();
    const schema = after.target("schema");
    after.units[0].nodes[after.units[0].body(schema.binding).?.root].a = 8;
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const old = &initial.capture.?;
    try std.testing.expect(savedProof(old, before.target("builder")) != null);
    var fresh = try after.emit(a, .{ .retain_artifacts = true });
    defer fresh.deinit(a);
    var reused = try after.emit(a, .{ .previous = old, .retain_artifacts = true });
    defer reused.deinit(a);
    try equalEmission(&fresh, &reused);
    try std.testing.expect(!std.mem.eql(u8, initial.bytes, reused.bytes));
    try std.testing.expect(reused.principal.requests > 0);
    try std.testing.expectEqual(@as(usize, 0), reused.principal.hits);
    try std.testing.expect(reused.principal.changed_or_unsupported > 0);
    try std.testing.expectEqual(fresh.principal.fresh_regions, reused.principal.fresh_regions);
}

test "principal cache globally rejects real type associated catalog and provider edits with identical namespaces" {
    const type_prefix =
        \\entry const integer: U32 = 0
        \\entry const floating: F32 = 0.0
    ;
    const associated_prefix =
        \\const add = fn value => value
        \\const sub = fn value => value
    ;
    const provider_prefix = "type State a is effect = { get: Unit -> a, set: a -> Unit }\n";
    const cases = [_]struct { label: []const u8, before: []const u8, after: []const u8 }{
        .{ .label = "type", .before = type_prefix ++ "\ntype Cell is data = #Cell U32\n" ++ positive_source, .after = type_prefix ++ "\ntype Cell is data = #Cell F32\n" ++ positive_source },
        .{ .label = "catalog", .before = associated_prefix ++ "\nconst U32.add = fn left => fn right => @u32.add left right\n" ++ positive_source, .after = associated_prefix ++ "\nconst U32.sub = fn left => fn right => @u32.add left right\n" ++ positive_source },
        .{ .label = "provider", .before = provider_prefix ++ "const state = @effect.state (State.get U32) (State.set U32) 1\n" ++ positive_source, .after = provider_prefix ++ "const state = @effect.state (State.get U32) (State.set U32) 2\n" ++ positive_source },
    };
    for (cases) |case| {
        var before = try Fixture.init(case.before);
        defer before.deinit();
        var after = try Fixture.init(case.after);
        defer after.deinit();
        try std.testing.expect(!std.mem.eql(u8, &artifacts.stamp(before.units), &artifacts.stamp(after.units)));
        if (std.mem.eql(u8, case.label, "catalog")) {
            try std.testing.expect(before.units[0].associated.len > 0 and after.units[0].associated.len > 0);
            try std.testing.expect(!std.mem.eql(u8, &artifacts.stamp(before.units[0].associated), &artifacts.stamp(after.units[0].associated)));
        }
        try std.testing.expectEqualDeep(before.names.view(), after.names.view());
        var initial = try before.emit(a, .{ .retain_artifacts = true });
        defer initial.deinit(a);
        try successful(&initial);
        const old = &initial.capture.?;
        try std.testing.expect(savedProof(old, before.target("builder")) != null);
        const retained_core = artifacts.stamp(before.units);
        const retained_proofs = artifacts.stamp(old.metadata.principal_proofs.items);
        var fresh = try after.emit(a, .{ .retain_artifacts = true });
        defer fresh.deinit(a);
        var reused = try after.emit(a, .{ .previous = old, .retain_artifacts = true });
        defer reused.deinit(a);
        try equalEmission(&fresh, &reused);
        try std.testing.expect(reused.principal.requests > 0);
        try std.testing.expectEqual(@as(usize, 0), reused.principal.hits);
        try std.testing.expect(reused.principal.changed_or_unsupported > 0);
        try std.testing.expectEqualSlices(u8, &retained_core, &artifacts.stamp(before.units));
        try std.testing.expectEqualSlices(u8, &retained_proofs, &artifacts.stamp(old.metadata.principal_proofs.items));
    }
}

fn allocationReuse(allocator: std.mem.Allocator, fixture: *const Fixture, old: *const capture.Capture, expected: *const backend.Result) !void {
    const retained_proofs = artifacts.stamp(old.metadata.principal_proofs.items);
    const retained_emission = artifacts.stamp(old.emission.instructions);
    var result = try fixture.emit(allocator, .{ .previous = old, .retain_artifacts = true });
    defer result.deinit(allocator);
    try equalEmission(expected, &result);
    try std.testing.expect(result.principal.hits > 0);
    try std.testing.expect(savedProof(&result.capture.?, fixture.target("builder")) != null);
    try std.testing.expectEqualSlices(u8, &retained_proofs, &artifacts.stamp(old.metadata.principal_proofs.items));
    try std.testing.expectEqualSlices(u8, &retained_emission, &artifacts.stamp(old.emission.instructions));
}

test "principal cache candidate allocation failures preserve old capture and a later revert" {
    var before = try Fixture.init(positive_source);
    defer before.deinit();
    var after = try Fixture.init(positive_source);
    defer after.deinit();
    const schema = after.target("schema");
    const schema_root = after.units[0].body(schema.binding).?.root;
    after.units[0].nodes[schema_root].a = 8;
    const retained_core = artifacts.stamp(before.units);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const old = &initial.capture.?;
    const retained_proofs = artifacts.stamp(old.metadata.principal_proofs.items);
    const retained_emission = artifacts.stamp(old.emission.instructions);
    var fresh = try after.emit(a, .{ .policy = .{} });
    defer fresh.deinit(a);
    try allocationReuse(a, &after, old, &fresh);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationReuse, .{ &after, old, &fresh });
    try std.testing.expectEqualSlices(u8, &retained_core, &artifacts.stamp(before.units));
    try std.testing.expectEqualSlices(u8, &retained_proofs, &artifacts.stamp(old.metadata.principal_proofs.items));
    try std.testing.expectEqualSlices(u8, &retained_emission, &artifacts.stamp(old.emission.instructions));
    after.units[0].nodes[schema_root].a = 7;
    var reverted = try after.emit(a, .{ .previous = old, .retain_artifacts = true });
    defer reverted.deinit(a);
    try equalEmission(&initial, &reverted);
    try std.testing.expect(reverted.principal.hits > 0);
}

test "principal cache failed backend candidate leaves prior captured proofs reusable" {
    const source = positive_source ++ "\nentry const failure: U32 = @u32.div 1 schema\n";
    var before = try Fixture.init(source);
    defer before.deinit();
    var failed = try Fixture.init(source);
    defer failed.deinit();
    const schema = failed.target("schema");
    failed.units[0].nodes[failed.units[0].body(schema.binding).?.root].a = 0;
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const old = &initial.capture.?;
    const retained_core = artifacts.stamp(before.units);
    const retained_proofs = artifacts.stamp(old.metadata.principal_proofs.items);
    const retained_emission = artifacts.stamp(old.emission.instructions);
    var fresh_failure = try failed.emit(a, .{ .policy = .{} });
    defer fresh_failure.deinit(a);
    var candidate = try failed.emit(a, .{ .previous = old, .retain_artifacts = true });
    defer candidate.deinit(a);
    try std.testing.expectEqual(backend.Code.integer_divide_by_zero, candidate.diagnostic.?.code);
    try std.testing.expectEqualDeep(fresh_failure.diagnostic, candidate.diagnostic);
    try std.testing.expectEqual(fresh_failure.constant_steps, candidate.constant_steps);
    try std.testing.expect(candidate.principal.hits > 0);
    try std.testing.expect(candidate.capture == null and candidate.bytes.len == 0);
    try std.testing.expectEqualSlices(u8, &retained_core, &artifacts.stamp(before.units));
    try std.testing.expectEqualSlices(u8, &retained_proofs, &artifacts.stamp(old.metadata.principal_proofs.items));
    try std.testing.expectEqualSlices(u8, &retained_emission, &artifacts.stamp(old.emission.instructions));
    var reverted = try before.emit(a, .{ .previous = old, .retain_artifacts = true });
    defer reverted.deinit(a);
    try equalEmission(&initial, &reverted);
    try std.testing.expect(reverted.principal.hits > 0);
}

test "principal cache requires exact evaluator options and falls back to fresh proof" {
    var before = try Fixture.init(positive_source);
    defer before.deinit();
    var after = try Fixture.init(positive_source);
    defer after.deinit();
    const schema = after.target("schema");
    after.units[0].nodes[after.units[0].body(schema.binding).?.root].a = 8;
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const builder = before.target("builder");
    const proof = for (initial.capture.?.metadata.principal_proofs.items) |*entry| {
        if (std.meta.eql(entry.target, builder)) break entry;
    } else return error.TestExpectedPrincipalCapture;
    const original_options = proof.options;
    // This test-owned metadata mutation occurs before candidate demand; normal
    // retained runs keep Capture and its pinned Core immutable throughout use.
    proof.options.max_steps += 1;
    defer proof.options = original_options;
    const old = &initial.capture.?;
    const changed_proof = artifacts.stamp(old.metadata.principal_proofs.items);
    var fresh = try after.emit(a, .{ .retain_artifacts = true });
    defer fresh.deinit(a);
    var candidate = try after.emit(a, .{ .previous = old, .retain_artifacts = true });
    defer candidate.deinit(a);
    try equalEmission(&fresh, &candidate);
    try std.testing.expect(candidate.principal.options_declined > 0);
    try std.testing.expectEqual(@as(usize, 0), candidate.principal.hits);
    try std.testing.expectEqual(fresh.principal.fresh_regions, candidate.principal.fresh_regions);
    try std.testing.expectEqualSlices(u8, &changed_proof, &artifacts.stamp(old.metadata.principal_proofs.items));
    proof.options = original_options;
    var retry = try after.emit(a, .{ .previous = old });
    defer retry.deinit(a);
    try equalEmission(&fresh, &retry);
    try std.testing.expect(retry.principal.hits > 0);
}

const principal_reuse = @import("principal_evidence_reuse.zig");
const evaluator = @import("core_eval.zig");
const semantic = @import("type_evidence.zig");
const layouts = @import("layout.zig");
const LazyGenerator = struct {
    evaluator: evaluator.Session,
    layouts: layouts.Store,
    fn init(allocator: std.mem.Allocator, fixture: *const Fixture) !LazyGenerator {
        var session = try evaluator.Session.init(allocator, fixture.units);
        errdefer session.deinit();
        return .{ .evaluator = session, .layouts = try layouts.Store.init(allocator) };
    }
    fn deinit(self: *LazyGenerator) void {
        self.layouts.deinit();
        self.evaluator.deinit();
    }
};
const closed_row_source =
    \\effect Read: Unit -> U32
    \\const read = fn () => Read ()
    \\entry const schema: U32 = 7
    \\entry const builder: U32 where { type_rep U32 } = do:
    \\  let local = fn value => value
    \\  return local 42
;

fn editSchema(fixture: *Fixture, value: u32) void {
    const schema = fixture.target("schema");
    fixture.units[0].nodes[fixture.units[0].body(schema.binding).?.root].a = value;
}

test "lazy empty principal proof needs no graph importer or lookup allocations and preserves fresh eager output" {
    var before = try Fixture.init(positive_source);
    defer before.deinit();
    var after = try Fixture.init(positive_source);
    defer after.deinit();
    editSchema(&after, 8);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const old = &initial.capture.?;
    const target = before.target("builder");
    const proof = savedProof(old, target) orelse return error.TestExpectedPrincipalCapture;
    try std.testing.expect(proof.types.len == 0 and proof.rows.len == 0);
    var failures = std.testing.FailingAllocator.init(a, .{});
    const allocator = failures.allocator();
    var generator = try LazyGenerator.init(allocator, &after);
    defer generator.deinit();
    var state = try principal_reuse.State.init(allocator, old, after.units, after.names.view(), null);
    defer state.deinit();
    try std.testing.expect(state.graphs == null and state.gate.admits(target));
    failures.fail_index = failures.alloc_index;
    var result = (try state.lookup(&generator, target, proof.options)) orelse return error.TestExpectedPrincipalHit;
    defer result.deinit(allocator);
    try std.testing.expect(result.types.len == 0 and result.rows.len == 0);
    try std.testing.expect(state.graphs == null);
    try std.testing.expectEqual(@as(usize, 0), state.stats.graph_importers_initialized);
    try std.testing.expectEqual(@as(usize, 1), state.stats.empty_hits);
    failures.fail_index = std.math.maxInt(usize);
    var fresh = try after.emit(a, .{});
    defer fresh.deinit(a);
    var lazy = try after.emit(a, .{ .previous = old, .retain_artifacts = true });
    defer lazy.deinit(a);
    try equalEmission(&fresh, &lazy);
    try std.testing.expectEqual(@as(usize, 0), lazy.principal.graph_importers_initialized);
    try std.testing.expectEqual(lazy.principal.hits, lazy.principal.empty_hits);
    try std.testing.expect(savedProof(&lazy.capture.?, target) != null);
}

test "lazy principal graph construction follows target and exact options admission including foreign namespace" {
    var fixture = try Fixture.init(positive_source);
    defer fixture.deinit();
    var initial = try fixture.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const target = fixture.target("builder");
    const proof = savedProof(&initial.capture.?, target) orelse return error.TestExpectedPrincipalCapture;
    var generator = try LazyGenerator.init(a, &fixture);
    defer generator.deinit();
    var state = try principal_reuse.State.init(a, &initial.capture.?, fixture.units, fixture.names.view(), null);
    defer state.deinit();
    var options = proof.options;
    options.max_steps += 1;
    try std.testing.expect((try state.lookup(&generator, target, options)) == null);
    try std.testing.expect((try state.lookup(&generator, .{ .unit = 0, .binding = target.binding }, proof.options)) == null);
    try std.testing.expect((try state.lookup(&generator, .{ .unit = 2, .binding = target.binding }, proof.options)) == null);
    try std.testing.expectEqual(@as(usize, 1), state.stats.options_declined);
    try std.testing.expectEqual(@as(usize, 2), state.stats.changed_or_unsupported);
    try std.testing.expect(state.graphs == null);
    // A different canonical producer path disables the complete gate even for
    // an empty proof. The retained producer remains separately owned.
    var foreign = try Fixture.init(positive_source);
    defer foreign.deinit();
    foreign.names.bytes[foreign.names.owners[0].start + 1] = 'x';
    var rejected = try principal_reuse.State.init(a, &initial.capture.?, foreign.units, foreign.names.view(), null);
    defer rejected.deinit();
    try std.testing.expect(!rejected.gate.enabled);
    try std.testing.expect((try rejected.lookup(&generator, target, proof.options)) == null);
    try std.testing.expect(rejected.graphs == null);
}

fn lazyNonemptyScenario(allocator: std.mem.Allocator, old: *const capture.Capture, after: *const Fixture, target: core.BindingRef, options: evaluator.Options) !void {
    const old_graph = artifacts.stamp(old.metadata.pools.?.evaluator.evidence);
    defer std.debug.assert(std.mem.eql(u8, &old_graph, &artifacts.stamp(old.metadata.pools.?.evaluator.evidence)));
    var generator = try LazyGenerator.init(allocator, after);
    defer generator.deinit();
    // Shift current-session IDs before import; raw IDs are not a certificate.
    const noise = try generator.evaluator.evidence.intern(.array, 4, 0, &.{});
    var state = try principal_reuse.State.init(allocator, old, after.units, after.names.view(), null);
    defer state.deinit();
    try std.testing.expect(state.graphs == null);
    const values = generator.evaluator.values.items.len;
    var solved = (try state.lookup(&generator, target, options)) orelse return error.TestExpectedPrincipalHit;
    defer solved.deinit(allocator);
    try std.testing.expect(state.graphs != null);
    try std.testing.expectEqual(@as(usize, 1), state.stats.graph_importers_initialized);
    try std.testing.expectEqual(@as(usize, 0), state.stats.empty_hits);
    try std.testing.expectEqual(@as(usize, 1), state.stats.nonempty_requests);
    try std.testing.expect(solved.rows.len > 0);
    for (solved.rows) |row| try std.testing.expectEqual(@as(u32, 0), row.evidence);
    try std.testing.expectEqual(values, generator.evaluator.values.items.len);
    try std.testing.expectEqual(@as(usize, 0), generator.evaluator.validated_calls.count());
    try std.testing.expectEqual(semantic.Tag.array, generator.evaluator.evidence.node(noise).tag);
    var again = (try state.lookup(&generator, target, options)) orelse return error.TestExpectedPrincipalHit;
    defer again.deinit(allocator);
    try std.testing.expectEqualDeep(solved.rows, again.rows);
    try std.testing.expectEqual(@as(usize, 1), state.stats.graph_importers_initialized);
}

test "lazy nonempty row principal imports keep fresh output and release every failed allocation" {
    var before = try Fixture.init(closed_row_source);
    defer before.deinit();
    var after = try Fixture.init(closed_row_source);
    defer after.deinit();
    editSchema(&after, 8);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const target = before.target("builder");
    const proof = savedProof(&initial.capture.?, target) orelse return error.TestExpectedPrincipalCapture;
    try std.testing.expect(proof.rows.len > 0);
    try lazyNonemptyScenario(a, &initial.capture.?, &after, target, proof.options);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, lazyNonemptyScenario, .{ &initial.capture.?, &after, target, proof.options });
    var fresh = try after.emit(a, .{});
    defer fresh.deinit(a);
    var lazy = try after.emit(a, .{ .previous = &initial.capture.? });
    defer lazy.deinit(a);
    try equalEmission(&fresh, &lazy);
    try std.testing.expectEqual(@as(usize, 1), lazy.principal.graph_importers_initialized);
}

test "lazy principal importer construction OOM leaves no published graph and retry then revert use owned facts" {
    var before = try Fixture.init(closed_row_source);
    defer before.deinit();
    var after = try Fixture.init(closed_row_source);
    defer after.deinit();
    editSchema(&after, 8);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const old = &initial.capture.?;
    const target = before.target("builder");
    const proof = savedProof(old, target) orelse return error.TestExpectedPrincipalCapture;
    const old_proofs = artifacts.stamp(old.metadata.principal_proofs.items);
    var failures = std.testing.FailingAllocator.init(a, .{});
    const allocator = failures.allocator();
    var generator = try LazyGenerator.init(allocator, &after);
    defer generator.deinit();
    var state = try principal_reuse.State.init(allocator, old, after.units, after.names.view(), null);
    defer state.deinit();
    failures.fail_index = failures.alloc_index;
    try std.testing.expectError(error.OutOfMemory, state.lookup(&generator, target, proof.options));
    try std.testing.expect(state.graphs == null);
    try std.testing.expectEqual(@as(usize, 0), state.stats.graph_importers_initialized);
    try std.testing.expectEqual(@as(usize, 0), state.stats.hits);
    failures.fail_index = std.math.maxInt(usize);
    var solved = (try state.lookup(&generator, target, proof.options)) orelse return error.TestExpectedPrincipalHit;
    defer solved.deinit(allocator);
    try std.testing.expect(state.graphs != null and state.stats.hits == 1);
    try std.testing.expectEqualSlices(u8, &old_proofs, &artifacts.stamp(old.metadata.principal_proofs.items));
    var reverted = try before.emit(a, .{ .previous = old });
    defer reverted.deinit(a);
    try equalEmission(&initial, &reverted);
    try std.testing.expect(reverted.principal.hits > 0);
}

test "lazy nonempty principal graphs remap owned type and effect IDs without carrying foreign values" {
    var fixture = try Fixture.init(closed_row_source);
    defer fixture.deinit();
    var initial = try fixture.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const old = &initial.capture.?;
    const target = fixture.target("builder");
    const proof = for (old.metadata.principal_proofs.items) |*item| {
        if (std.meta.eql(item.target, target)) break item;
    } else return error.TestExpectedPrincipalCapture;
    const variable: u32 = for (fixture.units[0].types.nodes, 0..) |node, index| {
        if (node.tag == .variable) break @intCast(index);
    } else return error.TestExpectedSourceVariable;
    const operation: u32 = for (fixture.units[0].types.operations) |entry| {
        if (entry.identity.unit == 1 and entry.identity.decl != 0) break entry.identity.decl;
    } else return error.TestExpectedSourceOperation;
    // This import law constructs owned closed facts with the same qualified
    // source namespace. They are not used as a validated-call certificate or
    // passed to the backend: ordinary real-builder output is checked above.
    var facts = try semantic.Store.init(a);
    defer facts.deinit();
    const array = try facts.intern(.array, 3, 0, &.{});
    const label = try facts.effects.internOperation(.{ .unit = 1, .decl = operation }, &.{3});
    const row = try facts.effects.internRow(&.{label});
    const function = try facts.internWithEffects(.function, array, 3, row, &.{});
    const owned = try facts.copyOwned(a);
    const prior = old.metadata.pools.?.evaluator.evidence;
    old.metadata.pools.?.evaluator.evidence = owned;
    defer {
        old.metadata.pools.?.evaluator.evidence.deinit(a);
        old.metadata.pools.?.evaluator.evidence = prior;
    }
    const type_maps = try a.dupe(semantic.Mapping, &.{.{ .variable = variable, .evidence = function }});
    defer a.free(type_maps);
    const row_maps = try a.dupe(semantic.RowMapping, &.{.{ .variable = 0, .evidence = row }});
    defer a.free(row_maps);
    const original_types = proof.types;
    const original_rows = proof.rows;
    proof.types = type_maps;
    proof.rows = row_maps;
    defer {
        proof.types = original_types;
        proof.rows = original_rows;
    }
    var generator = try LazyGenerator.init(a, &fixture);
    defer generator.deinit();
    const noise = try generator.evaluator.evidence.intern(.array, 4, 0, &.{});
    const noise_label = try generator.evaluator.evidence.effects.internOperation(.{ .unit = 1, .decl = operation }, &.{4});
    _ = try generator.evaluator.evidence.effects.internRow(&.{noise_label});
    const values = generator.evaluator.values.items.len;
    var state = try principal_reuse.State.init(a, old, fixture.units, fixture.names.view(), null);
    defer state.deinit();
    var solved = (try state.lookup(&generator, target, proof.options)) orelse return error.TestExpectedPrincipalHit;
    defer solved.deinit(a);
    try std.testing.expect(solved.types[0].evidence != function);
    try std.testing.expect(solved.rows[0].evidence != row);
    const view = &generator.evaluator.evidence;
    const arrow = view.node(solved.types[0].evidence);
    try std.testing.expectEqual(semantic.Tag.function, arrow.tag);
    try std.testing.expectEqual(semantic.Tag.array, view.node(arrow.a).tag);
    try std.testing.expectEqual(@as(u32, 3), view.node(arrow.a).a);
    try std.testing.expectEqual(solved.rows[0].evidence, arrow.c);
    const labels = view.effects.view().rowLabels(arrow.c);
    try std.testing.expectEqual(@as(usize, 1), labels.len);
    const selected = view.effects.view().operation(labels[0]);
    try std.testing.expectEqual(@as(u32, 1), selected.identity.unit);
    try std.testing.expectEqual(operation, selected.identity.decl);
    try std.testing.expectEqualSlices(u32, &.{3}, view.effects.view().operationArguments(labels[0]));
    try std.testing.expectEqual(semantic.Tag.array, view.node(noise).tag);
    try std.testing.expectEqual(values, generator.evaluator.values.items.len);
    try std.testing.expectEqual(@as(usize, 0), generator.evaluator.validated_calls.count());
    try std.testing.expectEqual(@as(usize, 1), state.stats.graph_importers_initialized);
}

const primitive_source =
    \\const from = fn value => @type.result "from" value
    \\const U32.from = fn value => @f32.to_u32 value
    \\const F32.from = fn value => @u32.to_f32 value
    \\const U32.add = fn left => fn right => @u32.add left right
    \\const F32.add = fn left => fn right => @f32.add left right
    \\const add = fn left => fn right => @type.call "add" left right
    \\const count = 10000
    \\entry const schema: U32 = 7
    \\entry const builder = add (from (@f32.ceil (@f32.sqrt (from count)))) 2
;
fn primitiveScenario(allocator: std.mem.Allocator, old: *const capture.Capture, after: *const Fixture, target: core.BindingRef, options: evaluator.Options) !void {
    var generator = try LazyGenerator.init(allocator, after);
    defer generator.deinit();
    _ = try generator.evaluator.evidence.intern(.array, 4, 0, &.{});
    var state = try principal_reuse.State.init(allocator, old, after.units, after.names.view(), null);
    defer state.deinit();
    const prior_values = generator.evaluator.values.items.len;
    var solved = (try state.lookup(&generator, target, options)) orelse return error.TestExpectedPrincipalHit;
    defer solved.deinit(allocator);
    try std.testing.expect(solved.types.len > 0 and solved.rows.len == 0);
    for (solved.types) |mapping| try std.testing.expectEqual(@as(u32, 3), mapping.evidence);
    try std.testing.expect(state.graphs == null);
    try std.testing.expectEqual(@as(usize, 1), state.stats.primitive_hits);
    try std.testing.expectEqual(@as(usize, 0), state.stats.graph_importers_initialized);
    try std.testing.expectEqual(prior_values, generator.evaluator.values.items.len);
    try std.testing.expectEqual(@as(usize, 0), generator.evaluator.validated_calls.count());
}

test "primitive principal copies actual U32 facts without importer with exact fresh output and allocation failure cleanup" {
    var before = try Fixture.init(primitive_source);
    defer before.deinit();
    var after = try Fixture.init(primitive_source);
    defer after.deinit();
    editSchema(&after, 8);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const old = &initial.capture.?;
    const target = before.target("builder");
    const proof = savedProof(old, target) orelse return error.TestExpectedPrincipalCapture;
    try std.testing.expect(proof.types.len > 0 and proof.rows.len == 0);
    for (proof.types) |mapping| try std.testing.expectEqual(@as(u32, 3), mapping.evidence);
    try primitiveScenario(a, old, &after, target, proof.options);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, primitiveScenario, .{ old, &after, target, proof.options });
    var fresh = try after.emit(a, .{});
    defer fresh.deinit(a);
    var primitive = try after.emit(a, .{ .previous = old, .retain_artifacts = true });
    defer primitive.deinit(a);
    try equalEmission(&fresh, &primitive);
    try std.testing.expectEqual(@as(usize, 1), primitive.principal.primitive_hits);
    try std.testing.expectEqual(@as(usize, 0), primitive.principal.graph_importers_initialized);
    const current = savedProof(&primitive.capture.?, target) orelse return error.TestExpectedPrincipalCapture;
    try std.testing.expectEqualDeep(proof.types, current.types);
    try std.testing.expect(@intFromPtr(proof.types.ptr) != @intFromPtr(current.types.ptr));
    var reverted = try before.emit(a, .{ .previous = &primitive.capture.? });
    defer reverted.deinit(a);
    try equalEmission(&initial, &reverted);
}

fn mutablePrincipalProof(old: *capture.Capture, target: core.BindingRef) !*artifacts.PrincipalProof {
    for (old.metadata.principal_proofs.items) |*proof| if (std.meta.eql(proof.target, target)) return proof;
    return error.TestExpectedPrincipalCapture;
}
fn sourceVariable(fixture: *const Fixture) !u32 {
    for (fixture.units[0].types.nodes, 0..) |node, id| if (node.tag == .variable) return @intCast(id);
    return error.TestExpectedSourceVariable;
}

test "primitive empty facts preserve options owner namespace and dirty source rejection without graph publication" {
    var before = try Fixture.init(positive_source);
    defer before.deinit();
    var after = try Fixture.init(positive_source);
    defer after.deinit();
    editSchema(&after, 8);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const old = &initial.capture.?;
    const target = before.target("builder");
    const proof = savedProof(old, target) orelse return error.TestExpectedPrincipalCapture;
    var generator = try LazyGenerator.init(a, &after);
    defer generator.deinit();
    var state = try principal_reuse.State.init(a, old, after.units, after.names.view(), null);
    defer state.deinit();
    var changed = proof.options;
    changed.max_steps += 1;
    try std.testing.expect((try state.lookup(&generator, target, changed)) == null);
    try std.testing.expect((try state.lookup(&generator, .{ .unit = 0, .binding = target.binding }, proof.options)) == null);
    try std.testing.expect((try state.lookup(&generator, .{ .unit = 2, .binding = target.binding }, proof.options)) == null);
    // The changed scalar itself has no reusable principal certificate.
    try std.testing.expect((try state.lookup(&generator, after.target("schema"), proof.options)) == null);
    var solved = (try state.lookup(&generator, target, proof.options)) orelse return error.TestExpectedPrincipalHit;
    defer solved.deinit(a);
    try std.testing.expect(solved.types.len == 0 and solved.rows.len == 0);
    try std.testing.expect(state.graphs == null);
    try std.testing.expectEqual(@as(usize, 1), state.stats.empty_hits);
    try std.testing.expectEqual(@as(usize, 0), state.stats.primitive_hits);
    var foreign = try Fixture.init(positive_source);
    defer foreign.deinit();
    foreign.names.bytes[foreign.names.owners[0].start + 1] = 'x';
    var other = try principal_reuse.State.init(a, old, foreign.units, foreign.names.view(), null);
    defer other.deinit();
    try std.testing.expect((try other.lookup(&generator, target, proof.options)) == null);
    try std.testing.expect(other.graphs == null and !other.gate.enabled);
}

test "primitive fact import declines zero nonvariable out of bounds and duplicate source keys without fallback acceptance" {
    var fixture = try Fixture.init(positive_source);
    defer fixture.deinit();
    var initial = try fixture.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const old = &initial.capture.?;
    const target = fixture.target("builder");
    const proof = try mutablePrincipalProof(old, target);
    const original = proof.types;
    defer proof.types = original;
    const variable = try sourceVariable(&fixture);
    const bad_keys = [_]u32{ 0, 3, @intCast(fixture.units[0].types.nodes.len) };
    var generator = try LazyGenerator.init(a, &fixture);
    defer generator.deinit();
    for (bad_keys) |key| {
        var maps = [_]semantic.Mapping{.{ .variable = key, .evidence = 3 }};
        proof.types = &maps;
        var state = try principal_reuse.State.init(a, old, fixture.units, fixture.names.view(), null);
        defer state.deinit();
        try std.testing.expect((try state.lookup(&generator, target, proof.options)) == null);
        try std.testing.expect(state.graphs == null);
        try std.testing.expectEqual(@as(usize, 1), state.stats.primitive_key_declined);
        try std.testing.expectEqual(@as(usize, 0), state.stats.primitive_hits);
    }
    var duplicate = [_]semantic.Mapping{ .{ .variable = variable, .evidence = 3 }, .{ .variable = variable, .evidence = 3 } };
    proof.types = &duplicate;
    var state = try principal_reuse.State.init(a, old, fixture.units, fixture.names.view(), null);
    defer state.deinit();
    try std.testing.expect((try state.lookup(&generator, target, proof.options)) == null);
    try std.testing.expect(state.graphs == null);
    try std.testing.expectEqual(@as(usize, 1), state.stats.primitive_key_declined);
}

test "primitive facts never attach source keys to a different current Core owner" {
    var fixture = try Fixture.init(positive_source);
    defer fixture.deinit();
    var other = try Fixture.init(positive_source);
    defer other.deinit();
    var initial = try fixture.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const old = &initial.capture.?;
    const target = fixture.target("builder");
    const proof = try mutablePrincipalProof(old, target);
    const original = proof.types;
    defer proof.types = original;
    var maps = [_]semantic.Mapping{.{ .variable = try sourceVariable(&fixture), .evidence = 3 }};
    proof.types = &maps;
    var generator = try LazyGenerator.init(a, &other);
    defer generator.deinit();
    var state = try principal_reuse.State.init(a, old, fixture.units, fixture.names.view(), null);
    defer state.deinit();
    try std.testing.expect(state.gate.admits(target));
    try std.testing.expect((try state.lookup(&generator, target, proof.options)) == null);
    try std.testing.expect(state.graphs == null);
    try std.testing.expectEqual(@as(usize, 1), state.stats.primitive_key_declined);
}

test "primitive malformed old U32 declines and current prefix mismatch uses the unchanged graph importer" {
    var fixture = try Fixture.init(positive_source);
    defer fixture.deinit();
    var initial = try fixture.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const old = &initial.capture.?;
    const target = fixture.target("builder");
    const proof = try mutablePrincipalProof(old, target);
    const original = proof.types;
    defer proof.types = original;
    var maps = [_]semantic.Mapping{.{ .variable = try sourceVariable(&fixture), .evidence = 3 }};
    proof.types = &maps;
    var generator = try LazyGenerator.init(a, &fixture);
    defer generator.deinit();
    const original_u32 = old.metadata.pools.?.evaluator.evidence.nodes[3];
    old.metadata.pools.?.evaluator.evidence.nodes[3].a = 1;
    defer old.metadata.pools.?.evaluator.evidence.nodes[3] = original_u32;
    var malformed = try principal_reuse.State.init(a, old, fixture.units, fixture.names.view(), null);
    defer malformed.deinit();
    try std.testing.expect((try malformed.lookup(&generator, target, proof.options)) == null);
    try std.testing.expectEqual(@as(usize, 1), malformed.stats.primitive_fallbacks);
    try std.testing.expectEqual(@as(usize, 0), malformed.stats.primitive_hits);
    try std.testing.expectEqual(@as(usize, 1), malformed.stats.evidence_declined);
    old.metadata.pools.?.evaluator.evidence.nodes[3] = original_u32;
    // Corrupt an unrelated primitive prefix slot, leaving the requested U32
    // leaf intact: fast admission must decline, ordinary U32 import still works.
    const original_boolean = generator.evaluator.evidence.nodes.items[2];
    generator.evaluator.evidence.nodes.items[2].a = 1;
    defer generator.evaluator.evidence.nodes.items[2] = original_boolean;
    var fallback = try principal_reuse.State.init(a, old, fixture.units, fixture.names.view(), null);
    defer fallback.deinit();
    var solved = (try fallback.lookup(&generator, target, proof.options)) orelse return error.TestExpectedPrincipalHit;
    defer solved.deinit(a);
    try std.testing.expectEqual(@as(u32, 3), solved.types[0].evidence);
    try std.testing.expectEqual(@as(usize, 1), fallback.stats.graph_importers_initialized);
    try std.testing.expectEqual(@as(usize, 1), fallback.stats.primitive_fallbacks);
    try std.testing.expectEqual(@as(usize, 0), fallback.stats.primitive_hits);
}

test "primitive non U32 and generative provider facts retain original graph validation and no call certificates" {
    var fixture = try Fixture.init(positive_source);
    defer fixture.deinit();
    var initial = try fixture.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const old = &initial.capture.?;
    const target = fixture.target("builder");
    const proof = try mutablePrincipalProof(old, target);
    const original = proof.types;
    defer proof.types = original;
    const variable = try sourceVariable(&fixture);
    var f32_maps = [_]semantic.Mapping{.{ .variable = variable, .evidence = 4 }};
    proof.types = &f32_maps;
    var generator = try LazyGenerator.init(a, &fixture);
    defer generator.deinit();
    var state = try principal_reuse.State.init(a, old, fixture.units, fixture.names.view(), null);
    defer state.deinit();
    var solved = (try state.lookup(&generator, target, proof.options)) orelse return error.TestExpectedPrincipalHit;
    defer solved.deinit(a);
    try std.testing.expectEqual(@as(u32, 4), solved.types[0].evidence);
    try std.testing.expectEqual(@as(usize, 1), state.stats.primitive_fallbacks);
    try std.testing.expectEqual(@as(usize, 0), state.stats.primitive_hits);
    try std.testing.expectEqual(@as(usize, 1), state.stats.graph_importers_initialized);
    // Owned representation fixtures exercise the original provider decline;
    // these altered facts are never passed to the backend as valid evidence.
    var facts = try semantic.Store.init(a);
    defer facts.deinit();
    const nominal = try facts.intern(.nominal, 1, 1, &.{});
    const provider = try facts.intern(.provider, nominal, 0, &.{});
    const state_provider = try facts.internStateProvider(nominal, nominal, nominal);
    const owned = try facts.copyOwned(a);
    const prior = old.metadata.pools.?.evaluator.evidence;
    old.metadata.pools.?.evaluator.evidence = owned;
    defer {
        old.metadata.pools.?.evaluator.evidence.deinit(a);
        old.metadata.pools.?.evaluator.evidence = prior;
    }
    for ([_]u32{ provider, state_provider }) |id| {
        var maps = [_]semantic.Mapping{.{ .variable = variable, .evidence = id }};
        proof.types = &maps;
        var unsupported = try principal_reuse.State.init(a, old, fixture.units, fixture.names.view(), null);
        defer unsupported.deinit();
        try std.testing.expect((try unsupported.lookup(&generator, target, proof.options)) == null);
        try std.testing.expectEqual(@as(usize, 1), unsupported.stats.graph_importers_initialized);
        try std.testing.expectEqual(@as(usize, 1), unsupported.stats.evidence_declined);
        try std.testing.expectEqual(@as(usize, 0), unsupported.stats.primitive_hits);
    }
    try std.testing.expectEqual(@as(usize, 0), generator.evaluator.validated_calls.count());
}

test "primitive nonempty row facts fall back and retain exact fresh output" {
    var before = try Fixture.init(closed_row_source);
    defer before.deinit();
    var after = try Fixture.init(closed_row_source);
    defer after.deinit();
    editSchema(&after, 8);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    var fresh = try after.emit(a, .{});
    defer fresh.deinit(a);
    var primitive = try after.emit(a, .{ .previous = &initial.capture.? });
    defer primitive.deinit(a);
    try equalEmission(&fresh, &primitive);
    try std.testing.expectEqual(@as(usize, 1), primitive.principal.graph_importers_initialized);
    try std.testing.expectEqual(@as(usize, 1), primitive.principal.primitive_fallbacks);
    try std.testing.expectEqual(@as(usize, 0), primitive.principal.primitive_hits);
}

test "primitive mapping copy OOM publishes no importer or hit and retry then revert keep owned proof facts" {
    var before = try Fixture.init(primitive_source);
    defer before.deinit();
    var after = try Fixture.init(primitive_source);
    defer after.deinit();
    editSchema(&after, 8);
    var initial = try before.emit(a, .{ .retain_artifacts = true });
    defer initial.deinit(a);
    try successful(&initial);
    const old = &initial.capture.?;
    const target = before.target("builder");
    const proof = savedProof(old, target) orelse return error.TestExpectedPrincipalCapture;
    const old_facts = artifacts.stamp(old.metadata.principal_proofs.items);
    var failure = std.testing.FailingAllocator.init(a, .{});
    const allocator = failure.allocator();
    var generator = try LazyGenerator.init(allocator, &after);
    defer generator.deinit();
    var state = try principal_reuse.State.init(allocator, old, after.units, after.names.view(), null);
    defer state.deinit();
    failure.fail_index = failure.alloc_index;
    try std.testing.expectError(error.OutOfMemory, state.lookup(&generator, target, proof.options));
    try std.testing.expect(state.graphs == null);
    try std.testing.expectEqual(@as(usize, 0), state.stats.hits);
    try std.testing.expectEqual(@as(usize, 0), state.stats.primitive_hits);
    failure.fail_index = std.math.maxInt(usize);
    var solved = (try state.lookup(&generator, target, proof.options)) orelse return error.TestExpectedPrincipalHit;
    defer solved.deinit(allocator);
    try std.testing.expect(state.graphs == null);
    try std.testing.expectEqual(@as(usize, 1), state.stats.primitive_hits);
    try std.testing.expectEqualSlices(u8, &old_facts, &artifacts.stamp(old.metadata.principal_proofs.items));
    var reverted = try before.emit(a, .{ .previous = old });
    defer reverted.deinit(a);
    try equalEmission(&initial, &reverted);
}
