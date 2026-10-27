const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
const backend = @import("../backend/core_backend.zig");
const identity = @import("../backend/runtime_identity.zig");
const inputs = @import("principal_inputs.zig");
const image = @import("principal_input_image.zig");
const eval = @import("../eval/core_eval.zig");
const T = @import("../check/types.zig");
const a = std.testing.allocator;
const Fixture = struct {
    units: [1]core.Module,
    names: identity.Metadata,
    fn init(source: []const u8) !Fixture {
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tokens = try lexer.lex(a, source);
        defer tokens.deinit(a);
        var tree = try parser.parse(a, source, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try checker.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        var module = try core.lower(a, &tree, &pool, &checked);
        errdefer module.deinit(a);
        return .{ .units = .{module}, .names = try identity.Metadata.capture(a, &pool, &.{.{ .unit = 1, .path = "/principal-input/main.blot" }}, 1) };
    }
    fn emit(self: *const Fixture, options: backend.CompileOptions) !backend.Result {
        return self.emitUsing(a, options);
    }
    fn emitUsing(self: *const Fixture, allocator: std.mem.Allocator, options: backend.CompileOptions) !backend.Result {
        var configured = options;
        configured.identity = self.names.view();
        return backend.compileWithOptions(allocator, &self.units, 1, configured);
    }
    fn deinit(self: *Fixture) void {
        self.units[0].deinit(a);
        self.names.deinit(a);
    }
};

test "principal input image retains inference while current staged literals change output" {
    var before = try Fixture.init("entry const answer: U32 where { type_rep U32 } = @u32.add 1 2\n");
    defer before.deinit();
    var after = try Fixture.init("entry const answer: U32 where { type_rep U32 } = @u32.add 1 3\n");
    defer after.deinit();
    try std.testing.expect(image.moduleEqual(&before.units[0], &after.units[0]));
    var initial = try before.emit(.{ .retain_artifacts = true });
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    try std.testing.expect(initial.capture.?.metadata.principal_queries.records.items[0].dependencies.inputs != null);
    var fresh = try after.emit(.{ .retain_artifacts = true });
    defer fresh.deinit(a);
    var candidate = try after.emit(.{ .retain_artifacts = true, .principal_previous = &initial.capture.? });
    defer candidate.deinit(a);
    try std.testing.expect(candidate.diagnostic == null);
    try std.testing.expect(candidate.principal.projected_empty_hits > 0);
    try std.testing.expect(candidate.principal.fresh_regions < fresh.principal.fresh_regions);
    try std.testing.expectEqualSlices(u8, fresh.bytes, candidate.bytes);
    try std.testing.expectEqual(fresh.constant_steps, candidate.constant_steps);
    try std.testing.expect(!std.mem.eql(u8, initial.bytes, candidate.bytes));
    var reverted = try before.emit(.{ .retain_artifacts = true, .principal_previous = &candidate.capture.? });
    defer reverted.deinit(a);
    try std.testing.expect(reverted.principal.projected_empty_hits > 0);
    try std.testing.expectEqualSlices(u8, initial.bytes, reverted.bytes);
}

fn nonemptyReplayFailure(allocator: std.mem.Allocator, fixture: *const Fixture, old: *const @import("artifact_capture.zig").Capture, expected: []const u8) !void {
    var actual = try fixture.emitUsing(allocator, .{ .retain_artifacts = true, .principal_previous = old });
    defer actual.deinit(allocator);
    try std.testing.expect(actual.diagnostic == null);
    try std.testing.expect(actual.principal.projected_nonempty_hits > 0);
    try std.testing.expectEqualSlices(u8, expected, actual.bytes);
}

test "principal nonempty projected rows own translated results through edits reverts and allocation failures" {
    const prefix = "entry const builder: U32 where { type_rep U32 } = do:\n  let local = fn value => value\n  break local ";
    var before = try Fixture.init(prefix ++ "42\n");
    defer before.deinit();
    var after = try Fixture.init(prefix ++ "43\n");
    defer after.deinit();
    var initial = try before.emit(.{ .retain_artifacts = true });
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    var fresh = try after.emit(.{});
    defer fresh.deinit(a);
    try std.testing.expect(fresh.diagnostic == null);
    const stamp = @import("code_artifacts.zig").stamp(initial.capture.?.metadata.principal_queries.records.items);
    try nonemptyReplayFailure(a, &after, &initial.capture.?, fresh.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, nonemptyReplayFailure, .{ &after, &initial.capture.?, fresh.bytes });
    var edited = try after.emit(.{ .retain_artifacts = true, .principal_previous = &initial.capture.? });
    defer edited.deinit(a);
    try nonemptyReplayFailure(a, &before, &edited.capture.?, initial.bytes);
    try std.testing.expectEqualSlices(u8, &stamp, &@import("code_artifacts.zig").stamp(initial.capture.?.metadata.principal_queries.records.items));
}

test "principal observed sources retain memo outputs across unrelated body edits and reject consumed source edits" {
    // Establish both operation names before the edited declaration, so the
    // negative case tests source admission with the same ordered namespace.
    const operations = "const add = fn value => @u32.add value 2\nconst subtract = fn value => @u32.sub value 2\n";
    const prefix = operations ++ "const local = fn value => @u32.add value 1\nentry const answer: U32 where { type_rep U32 } = local 41\n";
    var before = try Fixture.init(prefix ++ "const unrelated = fn value => @u32.add value 2\n");
    defer before.deinit();
    var after = try Fixture.init(prefix ++ "const unrelated = fn value => @u32.sub value 2\n");
    defer after.deinit();
    var initial = try before.emit(.{ .retain_artifacts = true });
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    const observed = initial.capture.?.metadata.principal_queries.records.items[0].dependencies.inputs.?;
    try std.testing.expect(observed.source_complete and observed.sources.len > 0);
    try std.testing.expect(!image.moduleEqual(&before.units[0], &after.units[0]));
    var fresh = try after.emit(.{});
    defer fresh.deinit(a);
    var edited = try after.emit(.{ .retain_artifacts = true, .principal_previous = &initial.capture.? });
    defer edited.deinit(a);
    try std.testing.expect(edited.diagnostic == null);
    try std.testing.expect(edited.principal.call_publications_replayed > 0);
    try std.testing.expectEqualSlices(u8, fresh.bytes, edited.bytes);
    var changed = try Fixture.init(operations ++ "const local = fn value => @u32.sub value 1\nentry const answer: U32 where { type_rep U32 } = local 41\nconst unrelated = fn value => @u32.sub value 2\n");
    defer changed.deinit();
    var expected = try changed.emit(.{});
    defer expected.deinit(a);
    // This fixture consumes only the checked local interface. Verify that
    // explicitly recording the stronger body dependency still revokes replay.
    var local: core.BindingRef = .{ .unit = 1, .binding = 0 };
    for (after.units[0].bodies) |body| if (std.mem.eql(u8, after.units[0].name(body.declaration_name), "local")) {
        local.binding = body.binding;
    };
    try std.testing.expect(local.binding != 0);
    const key = &edited.capture.?.metadata.principal_queries.records.items[0].dependencies.inputs.?;
    const sources = try a.alloc(core.BindingRef, key.sources.len + 1);
    @memcpy(sources[0..key.sources.len], key.sources);
    sources[key.sources.len] = local;
    a.free(key.sources);
    key.sources = sources;
    var declined = try changed.emit(.{ .retain_artifacts = true, .principal_previous = &edited.capture.? });
    defer declined.deinit(a);
    try std.testing.expect(declined.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 0), declined.principal.call_publications_replayed);
    try std.testing.expect(declined.principal.fresh_regions > 0);
    try std.testing.expect(declined.principal.projected_image_declines > 0);
    try std.testing.expectEqualSlices(u8, expected.bytes, declined.bytes);
}

fn checkedInterfaceReplay(allocator: std.mem.Allocator, fixture: *const Fixture, old: *const @import("artifact_capture.zig").Capture, expected: []const u8) !void {
    var result = try fixture.emitUsing(allocator, .{ .retain_artifacts = true, .principal_previous = old });
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.principal.projected_empty_hits + result.principal.projected_nonempty_hits > 0);
    try std.testing.expectEqualSlices(u8, expected, result.bytes);
}
test "checked interface observations preserve principal inference while staged body edits execute current code through OOM" {
    const prefix = "const add = fn (x: U32) -> U32 => @u32.add x 1\nconst sub = fn (x: U32) -> U32 => @u32.sub x 1\nconst local = fn (x: U32) -> U32 => ";
    const suffix = " x 1\nentry const answer: U32 where { type_rep U32 } = local 41\n";
    var before = try Fixture.init(prefix ++ "@u32.add" ++ suffix);
    defer before.deinit();
    var after = try Fixture.init(prefix ++ "@u32.sub" ++ suffix);
    defer after.deinit();
    var initial = try before.emit(.{ .retain_artifacts = true });
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    var interface_reads: usize = 0;
    for (initial.capture.?.metadata.principal_queries.records.items) |record| if (record.dependencies.inputs) |observed| {
        interface_reads += observed.interfaces.len;
    };
    try std.testing.expect(interface_reads > 0);
    var expected = try after.emit(.{});
    defer expected.deinit(a);
    try std.testing.expect(expected.diagnostic == null);
    try std.testing.expect(!std.mem.eql(u8, initial.bytes, expected.bytes));
    try checkedInterfaceReplay(a, &after, &initial.capture.?, expected.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, checkedInterfaceReplay, .{ &after, &initial.capture.?, expected.bytes });
    var edited = try after.emit(.{ .retain_artifacts = true, .principal_previous = &initial.capture.? });
    defer edited.deinit(a);
    try checkedInterfaceReplay(a, &before, &edited.capture.?, initial.bytes);
}

test "checked requirement observations retain transitive headers through body edits and allocation failures" {
    const prefix = "const add = fn (x: U32) -> U32 => @u32.add x 1\nconst sub = fn (x: U32) -> U32 => @u32.sub x 1\nconst local: U32 -> U32 where { type_rep U32 } = fn x => ";
    const suffix = " x 1\nconst wrapper: U32 -> U32 where { type_rep U32 } = fn x => local x\nentry const answer: U32 where { type_rep U32 } = wrapper 41\n";
    var before = try Fixture.init(prefix ++ "@u32.add" ++ suffix);
    defer before.deinit();
    var after = try Fixture.init(prefix ++ "@u32.sub" ++ suffix);
    defer after.deinit();
    var initial = try before.emit(.{ .retain_artifacts = true });
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    var requirement_reads: usize = 0;
    for (initial.capture.?.metadata.principal_queries.records.items) |record| if (record.dependencies.inputs) |observed| {
        for (observed.interfaces) |source| if (before.units[source.unit - 1].binding(source.binding).scheme.obligations.len != 0) {
            requirement_reads += 1;
        };
    };
    try std.testing.expect(requirement_reads > 0);
    var expected = try after.emit(.{});
    defer expected.deinit(a);
    try std.testing.expect(expected.diagnostic == null);
    try std.testing.expect(!std.mem.eql(u8, initial.bytes, expected.bytes));
    try checkedInterfaceReplay(a, &after, &initial.capture.?, expected.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, checkedInterfaceReplay, .{ &after, &initial.capture.?, expected.bytes });
}

test "completed inferred result interfaces preserve body edits and reverts without recollecting principals through OOM" {
    const prefix =
        "type Token is data = #Token U32\n" ++
        "const Token.from = fn value => #Token (@f32.to_u32 value)\n" ++
        "const from = fn value => @type.result \"from\" value\n" ++
        "const floor_impl = fn value => @f32.floor value\n" ++
        "const ceil_impl = fn value => @f32.ceil value\n" ++
        "const floor = floor_impl\n" ++
        "const ceil = ceil_impl\n" ++
        "const local = fn value => from (";
    const suffix = " value)\nentry const answer: U32 where { type_rep U32 } = case local 41.25 of\n  #Token value => value\n";
    var before = try Fixture.init(prefix ++ "floor" ++ suffix);
    defer before.deinit();
    var after = try Fixture.init(prefix ++ "ceil" ++ suffix);
    defer after.deinit();
    var initial = try before.emit(.{ .retain_artifacts = true });
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    try std.testing.expect(initial.counters.completed_interface_proofs > 0);
    try std.testing.expect(initial.counters.completed_interface_imports > 0);
    var expected = try after.emit(.{});
    defer expected.deinit(a);
    try std.testing.expect(expected.diagnostic == null);
    try std.testing.expect(!std.mem.eql(u8, initial.bytes, expected.bytes));
    try checkedInterfaceReplay(a, &after, &initial.capture.?, expected.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, checkedInterfaceReplay, .{ &after, &initial.capture.?, expected.bytes });
    var edited = try after.emit(.{ .retain_artifacts = true, .principal_previous = &initial.capture.? });
    defer edited.deinit(a);
    try checkedInterfaceReplay(a, &before, &edited.capture.?, initial.bytes);
}

test "principal input image does not hide staged errors or change the last good capture" {
    var before = try Fixture.init("entry const answer: U32 where { type_rep U32 } = @u32.div 8 2\n");
    defer before.deinit();
    var after = try Fixture.init("entry const answer: U32 where { type_rep U32 } = @u32.div 8 0\n");
    defer after.deinit();
    var initial = try before.emit(.{ .retain_artifacts = true });
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    const stamp = @import("code_artifacts.zig").stamp(initial.capture.?.metadata.principal_queries.records.items);
    var fresh = try after.emit(.{ .retain_artifacts = true });
    defer fresh.deinit(a);
    var candidate = try after.emit(.{ .retain_artifacts = true, .principal_previous = &initial.capture.? });
    defer candidate.deinit(a);
    try std.testing.expect(candidate.diagnostic != null);
    try std.testing.expectEqualDeep(fresh.diagnostic, candidate.diagnostic);
    try std.testing.expectEqual(fresh.constant_steps, candidate.constant_steps);
    try std.testing.expect(candidate.capture == null and candidate.bytes.len == 0);
    try std.testing.expect(candidate.principal.projected_empty_hits > 0);
    try std.testing.expectEqualSlices(u8, &stamp, &@import("code_artifacts.zig").stamp(initial.capture.?.metadata.principal_queries.records.items));
}

test "principal input image rejects changed types collection identities and effects" {
    var list = try Fixture.init("entry const value = [1]\n");
    defer list.deinit();
    var array = try Fixture.init("entry const value = #[1]\n");
    defer array.deinit();
    var floating = try Fixture.init("entry const value = [1.0]\n");
    defer floating.deinit();
    try std.testing.expect(!image.moduleEqual(&list.units[0], &array.units[0]));
    try std.testing.expect(!image.moduleEqual(&list.units[0], &floating.units[0]));
    var changed = try Fixture.init("entry const value = [1]\n");
    defer changed.deinit();
    changed.units[0].types.effects.variable_count += 1;
    try std.testing.expect(!image.moduleEqual(&list.units[0], &changed.units[0]));
}

test "principal input certificate preserves absent scalar reads and rejects executed values" {
    var fixture = try Fixture.init("entry const answer: U32 = 7\n");
    defer fixture.deinit();
    const target: core.BindingRef = .{ .unit = 1, .binding = fixture.units[0].bodies[1].binding };
    var reads: inputs.Recorder = .{ .eligible = true, .max_reads = 32 };
    defer reads.deinit(a);
    try reads.scalar(a, target, 0);
    var key = try reads.key().?.clone(a);
    defer key.deinit(a);
    var session = try eval.Session.init(a, &fixture.units);
    defer session.deinit();
    try std.testing.expect(key.matches(&session));
    session.principal_reads = &reads;
    _ = try session.richValue(target);
    session.principal_reads = null;
    try std.testing.expect(reads.key() == null);
    try std.testing.expect(!key.matches(&session));
    const present: inputs.Key = .{ .scalar_reads = &.{.{ .target = target, .evidence = T.u32_type }} };
    try std.testing.expect(present.matches(&session));
    try session.specializations.validated_calls.put(a, .{ .target = .{ .unit = 0, .binding = target.binding }, .evidence = T.u32_type }, {});
    try std.testing.expect(!present.matches(&session));
}

fn callRecordingFailures(allocator: std.mem.Allocator) !void {
    const target: core.BindingRef = .{ .unit = 1, .binding = 1 };
    var reads: inputs.Recorder = .{ .eligible = true, .empty_call_inputs = false, .max_reads = 4 };
    defer reads.deinit(allocator);
    try reads.callRead(allocator, target, 6, false);
    try reads.callRead(allocator, target, 7, true);
    try reads.callPublish(allocator, target, 6);
    try reads.callRead(allocator, target, 6, true);
    var copied = try reads.key().?.clone(allocator);
    defer copied.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), copied.call_reads.len);
    try std.testing.expect(!copied.call_reads[0].present);
    try std.testing.expect(copied.call_reads[1].present);
    try std.testing.expectEqual(@as(usize, 1), copied.call_publications.len);
    try reads.callRead(allocator, target, 7, false);
    try std.testing.expect(reads.key() == null);
    var bounded: inputs.Recorder = .{ .eligible = true, .empty_call_inputs = false, .max_reads = 1 };
    defer bounded.deinit(allocator);
    try bounded.callRead(allocator, target, 6, false);
    try bounded.callRead(allocator, target, 7, false);
    try std.testing.expect(bounded.key() == null);
}

test "principal call input recording preserves absence internal publications conflicts and allocation ownership" {
    try callRecordingFailures(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, callRecordingFailures, .{});
}

fn summaryReplayFailures(allocator: std.mem.Allocator, fixture: *const Fixture) !void {
    var session = try eval.Session.init(allocator, &fixture.units);
    defer session.deinit();
    const target: core.BindingRef = .{ .unit = 1, .binding = fixture.units[0].bodies[1].binding };
    const signature = try session.storage.evidence.intern(.function, T.u32_type, T.u32_type, &.{});
    const arguments = try session.storage.evidence.intern(.product, 0, 0, &.{T.u32_type});
    const fact: inputs.Summary = .{ .key = .{ .target = target, .inputs = arguments }, .result = signature };
    var reads: inputs.Recorder = .{ .eligible = true, .empty_call_inputs = false, .max_reads = 4 };
    defer reads.deinit(allocator);
    try reads.summaryRead(allocator, fact);
    try reads.summaryRead(allocator, fact);
    var key = try reads.key().?.clone(allocator);
    defer key.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), key.summary_reads.len);
    try std.testing.expect(!key.matches(&session));
    var publications = [_]inputs.Summary{fact};
    const output: inputs.Key = .{ .scalar_reads = &.{}, .summary_publications = &publications };
    output.publish(&session) catch |err| {
        try std.testing.expect(!session.principalSummaryMatches(fact));
        try std.testing.expectEqual(@as(usize, 0), session.specializations.validated_calls.count());
        return err;
    };
    try std.testing.expect(key.matches(&session));
    try std.testing.expectEqual(@as(usize, 0), session.specializations.validated_calls.count());
    key.summary_reads[0].key.deferred_member = true;
    try std.testing.expect(!key.matches(&session));
    key.summary_reads[0] = fact;
    key.summary_reads[0].result = T.u32_type;
    try std.testing.expect(!key.matches(&session));
    // Replayed optional outputs preserve the current owner's existing result.
    publications[0].result = T.u32_type;
    try output.publish(&session);
    try std.testing.expect(session.principalSummaryMatches(fact));
    try reads.summaryPublish(allocator, fact);
    try reads.summaryRead(allocator, fact);
    try std.testing.expectEqual(@as(usize, 1), reads.summary_reads.items.len);
    var changed = fact;
    changed.result = T.u32_type;
    try reads.summaryRead(allocator, changed);
    try std.testing.expect(reads.key() == null);
}

test "principal summary replay requires exact inputs and results without publishing global certificates through OOM" {
    var fixture = try Fixture.init("const local = fn value => @u32.add value 1\nentry const answer = local 41\n");
    defer fixture.deinit();
    try summaryReplayFailures(a, &fixture);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, summaryReplayFailures, .{&fixture});
}

fn recordingFailures(allocator: std.mem.Allocator) !void {
    var reads: inputs.Recorder = .{ .eligible = true, .max_reads = 2 };
    defer reads.deinit(allocator);
    const first: core.BindingRef = .{ .unit = 1, .binding = 1 };
    const second: core.BindingRef = .{ .unit = 2, .binding = 1 };
    try reads.scalar(allocator, first, T.u32_type);
    try reads.scalar(allocator, first, T.u32_type);
    try reads.scalar(allocator, second, 0);
    var copied = try reads.key().?.clone(allocator);
    defer copied.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), copied.scalar_reads.len);
    try reads.scalar(allocator, second, T.boolean);
    try std.testing.expect(reads.key() == null);
    var bounded: inputs.Recorder = .{ .eligible = true, .max_reads = 1 };
    defer bounded.deinit(allocator);
    try bounded.scalar(allocator, first, 0);
    try bounded.scalar(allocator, second, 0);
    try std.testing.expect(bounded.key() == null);
    var open: inputs.Recorder = .{ .eligible = true, .max_reads = 2 };
    defer open.deinit(allocator);
    try open.scalar(allocator, first, T.never + 1);
    try std.testing.expect(open.key() == null);
}

test "principal input recording bounds conflicting reads and frees every failing allocation" {
    try recordingFailures(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, recordingFailures, .{});
}

fn nominalRecording(allocator: std.mem.Allocator) !void {
    var reads: inputs.Recorder = .{ .eligible = true, .max_reads = 3 };
    defer reads.deinit(allocator);
    const first: u64 = (@as(u64, 1) << 32) | 1;
    const second: u64 = (@as(u64, 1) << 32) | 2;
    // A recursive computation may first publish a negative, then overwrite it.
    // Reads following either write are internal to this query, not new inputs.
    try reads.plainRead(allocator, first, null);
    try reads.plainPublish(allocator, first, false);
    try reads.plainRead(allocator, first, false);
    try reads.plainPublish(allocator, first, true);
    try reads.plainRead(allocator, first, true);
    try reads.plainRead(allocator, second, false);
    try reads.scalar(allocator, .{ .unit = 1, .binding = 1 }, 0);
    var copy = try reads.key().?.clone(allocator);
    defer copy.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), copy.plain_reads.len);
    try std.testing.expect(copy.plain_reads[0].value == null);
    try std.testing.expectEqual(@as(?bool, false), copy.plain_reads[1].value);
    try std.testing.expectEqualSlices(inputs.PlainPublication, &.{.{ .key = first, .value = true }}, copy.plain_publications);
    try reads.plainRead(allocator, second, true);
    try std.testing.expect(reads.key() == null);
}

test "principal nominal inputs retain absence negatives and final publications under allocation failures" {
    try nominalRecording(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, nominalRecording, .{});
}

test "principal nominal replay requires exact memo inputs and publishes atomically" {
    var fixture = try Fixture.init("type Box is data = #Box U32\nentry const answer = 7\n");
    defer fixture.deinit();
    var failure = std.testing.FailingAllocator.init(a, .{});
    var session = try eval.Session.init(failure.allocator(), &fixture.units);
    defer session.deinit();
    const nominal: u64 = (@as(u64, 1) << 32) | fixture.units[0].nominals[0].identity.decl;
    const key: inputs.Key = .{ .scalar_reads = &.{}, .plain_reads = &.{.{ .key = nominal, .value = null }}, .plain_publications = &.{.{ .key = nominal, .value = true }} };
    try std.testing.expect(key.matches(&session));
    failure.fail_index = failure.alloc_index;
    try std.testing.expectError(error.OutOfMemory, key.publish(&session));
    try std.testing.expect(session.specializations.plain_nominals.count() == 0);
    failure.fail_index = std.math.maxInt(usize);
    try key.publish(&session);
    try std.testing.expectEqual(@as(?bool, true), session.specializations.plain_nominals.get(nominal));
    try std.testing.expect(!key.matches(&session));
    try session.specializations.plain_nominals.put(session.allocator, nominal, false);
    try std.testing.expect(!key.matches(&session));
    const negative: inputs.Key = .{ .scalar_reads = &.{}, .plain_reads = &.{.{ .key = nominal, .value = false }} };
    try std.testing.expect(negative.matches(&session));
}

const nominal_prelude =
    \\type Box is data = #Box U32
    \\const extract = fn (box: Box) -> U32 => case box of
    \\  #Box value => value
    \\entry const answer: U32 where { type_rep U32 } = @u32.div 8 (extract (#Box
;

test "principal input replay restores nominal and closed call publications across edits errors and recovery" {
    var before = try Fixture.init(nominal_prelude ++ " 2))\n");
    defer before.deinit();
    var after = try Fixture.init(nominal_prelude ++ " 4))\n");
    defer after.deinit();
    var invalid = try Fixture.init(nominal_prelude ++ " 0))\n");
    defer invalid.deinit();
    var initial = try before.emit(.{ .retain_artifacts = true });
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    const key = initial.capture.?.metadata.principal_queries.records.items[0].dependencies.inputs orelse return error.TestExpectedPrincipalInputs;
    try std.testing.expect(key.call_publications.len > 0);
    try std.testing.expect(key.plain_reads.len > 0);
    const stamp = @import("code_artifacts.zig").stamp(initial.capture.?.metadata.principal_queries.records.items);
    var fresh = try after.emit(.{ .retain_artifacts = true });
    defer fresh.deinit(a);
    var reused = try after.emit(.{ .retain_artifacts = true, .principal_previous = &initial.capture.? });
    defer reused.deinit(a);
    try std.testing.expect(reused.diagnostic == null);
    try std.testing.expect(reused.principal.projected_empty_hits > 0);
    try std.testing.expect(reused.principal.call_publications_replayed > 0);
    try std.testing.expectEqualSlices(u8, fresh.bytes, reused.bytes);
    try std.testing.expectEqual(fresh.constant_steps, reused.constant_steps);
    // Replayed evidence must be owned by the current capture for the next edit.
    var failed_fresh = try invalid.emit(.{});
    defer failed_fresh.deinit(a);
    var failed = try invalid.emit(.{ .retain_artifacts = true, .principal_previous = &reused.capture.? });
    defer failed.deinit(a);
    try std.testing.expect(failed.diagnostic != null and failed.capture == null);
    try std.testing.expect(failed.principal.call_publications_replayed > 0);
    try std.testing.expectEqualDeep(failed_fresh.diagnostic, failed.diagnostic);
    try std.testing.expectEqual(failed_fresh.constant_steps, failed.constant_steps);
    var recovered = try before.emit(.{ .retain_artifacts = true, .principal_previous = &reused.capture.? });
    defer recovered.deinit(a);
    try std.testing.expect(recovered.principal.call_publications_replayed > 0);
    try std.testing.expectEqualSlices(u8, initial.bytes, recovered.bytes);
    try std.testing.expectEqualSlices(u8, &stamp, &@import("code_artifacts.zig").stamp(initial.capture.?.metadata.principal_queries.records.items));
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replayFailure, .{ &after, &initial.capture.?, fresh.bytes });
}

fn replayFailure(allocator: std.mem.Allocator, fixture: *const Fixture, old: *const @import("artifact_capture.zig").Capture, expected: []const u8) !void {
    var candidate = try fixture.emitUsing(allocator, .{ .retain_artifacts = true, .principal_previous = old });
    defer candidate.deinit(allocator);
    try std.testing.expect(candidate.diagnostic == null);
    try std.testing.expect(candidate.principal.projected_empty_hits > 0);
    try std.testing.expectEqualSlices(u8, expected, candidate.bytes);
}

test "principal input replay owns read keys and preserves the prior capture at every allocation failure" {
    const prefix = "entry const schema: U32 = 7\n";
    var before = try Fixture.init(prefix ++ "entry const answer: U32 where { type_rep U32 } = @u32.add schema 2\n");
    defer before.deinit();
    var after = try Fixture.init(prefix ++ "entry const answer: U32 where { type_rep U32 } = @u32.add schema 3\n");
    defer after.deinit();
    var initial = try before.emit(.{ .retain_artifacts = true });
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    const old = &initial.capture.?;
    try std.testing.expectEqual(@as(usize, 1), old.metadata.principal_queries.records.items[0].dependencies.inputs.?.scalar_reads.len);
    const stamp = @import("code_artifacts.zig").stamp(old.metadata.principal_queries.records.items);
    var fresh = try after.emit(.{ .retain_artifacts = true });
    defer fresh.deinit(a);
    try std.testing.expect(fresh.diagnostic == null);
    try replayFailure(a, &after, old, fresh.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replayFailure, .{ &after, old, fresh.bytes });
    try std.testing.expectEqualSlices(u8, &stamp, &@import("code_artifacts.zig").stamp(old.metadata.principal_queries.records.items));
}

fn partialReplayFailure(allocator: std.mem.Allocator, fixture: *const Fixture, old: *const @import("artifact_capture.zig").Capture, expected: []const u8, accepted: usize) !void {
    var candidate = try fixture.emitUsing(allocator, .{ .retain_artifacts = true, .principal_previous = old });
    defer candidate.deinit(allocator);
    try std.testing.expect(candidate.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 1), candidate.principal.projected_empty_hits);
    try std.testing.expectEqual(@as(usize, 2), candidate.principal.call_publications_declined);
    try std.testing.expectEqual(accepted, candidate.principal.call_publications_replayed);
    try std.testing.expectEqualSlices(u8, expected, candidate.bytes);
    const recorded = candidate.capture.?.metadata.principal_queries.records.items[0].dependencies.inputs.?;
    try std.testing.expectEqual(accepted, recorded.call_publications.len);
}

test "principal input replay omits declined memo outputs while owning accepted proofs through every allocation failure" {
    var before = try Fixture.init(nominal_prelude ++ " 2))\n");
    defer before.deinit();
    var after = try Fixture.init(nominal_prelude ++ " 4))\n");
    defer after.deinit();
    var initial = try before.emit(.{ .retain_artifacts = true });
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    const key = &initial.capture.?.metadata.principal_queries.records.items[0].dependencies.inputs.?;
    const accepted = key.call_publications.len;
    try std.testing.expect(accepted > 0);
    const target = key.call_publications[0].target;
    const extended = try a.alloc(inputs.CallPublication, accepted + 2);
    @memcpy(extended[0..accepted], key.call_publications);
    // Invalid/non-function outputs must never become call proof authority.
    // The independently proven empty result still has its exact image/inputs.
    extended[accepted] = .{ .target = target, .evidence = 0 };
    extended[accepted + 1] = .{ .target = target, .evidence = T.u32_type };
    a.free(key.call_publications);
    key.call_publications = extended;
    var fresh = try after.emit(.{ .retain_artifacts = true });
    defer fresh.deinit(a);
    try std.testing.expect(fresh.diagnostic == null);
    const stamp = @import("code_artifacts.zig").stamp(initial.capture.?.metadata.principal_queries.records.items);
    try partialReplayFailure(a, &after, &initial.capture.?, fresh.bytes, accepted);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, partialReplayFailure, .{ &after, &initial.capture.?, fresh.bytes, accepted });
    try std.testing.expectEqualSlices(u8, &stamp, &@import("code_artifacts.zig").stamp(initial.capture.?.metadata.principal_queries.records.items));
    // All outputs may decline too, including the owning shrink to zero.
    const declined = try a.dupe(inputs.CallPublication, key.call_publications[accepted..]);
    a.free(key.call_publications);
    key.call_publications = declined;
    try partialReplayFailure(a, &after, &initial.capture.?, fresh.bytes, 0);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, partialReplayFailure, .{ &after, &initial.capture.?, fresh.bytes, @as(usize, 0) });
}

fn sourceUnitOwnershipScenario(allocator: std.mem.Allocator) !void {
    var reads: inputs.Recorder = .{ .eligible = true, .max_reads = 3 };
    defer reads.deinit(allocator);
    const root: core.BindingRef = .{ .unit = 1, .binding = 7 };
    try reads.source(allocator, root);
    try reads.sourceUnit(allocator, 2);
    try reads.interface(allocator, .{ .unit = 1, .binding = 8 });
    try reads.interface(allocator, .{ .unit = 1, .binding = 8 });
    try reads.source(allocator, root);
    try reads.sourceUnit(allocator, 2);
    try std.testing.expect(reads.source_complete);
    var key = try reads.key().?.clone(allocator);
    defer key.deinit(allocator);
    reads.sources.items[0].binding = 9;
    reads.source_units.items[0] = 3;
    reads.interfaces.items[0].binding = 10;
    try std.testing.expectEqual(@as(u32, 8), key.interfaces[0].binding);
    try std.testing.expectEqual(root, key.sources[0]);
    try std.testing.expectEqualSlices(u32, &.{2}, key.source_units);
    try reads.sourceUnit(allocator, 4);
    try std.testing.expect(!reads.source_complete);
    try std.testing.expect(key.source_complete);
}
test "principal anonymous module observations own their inputs and permit duplicates at the observation bound through OOM" {
    try sourceUnitOwnershipScenario(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, sourceUnitOwnershipScenario, .{});
}

test "principal anonymous module dependencies reject memo replay after unrelated body changes" {
    const prefix = "const add = fn value => @u32.add value 2\nconst sub = fn value => @u32.sub value 2\nconst local = fn value => @u32.add value 1\nentry const answer: U32 where { type_rep U32 } = local 41\n";
    const suffix = "const changed = fn value => ";
    var before = try Fixture.init(prefix ++ suffix ++ "@u32.add value 2\n");
    defer before.deinit();
    var after = try Fixture.init(prefix ++ suffix ++ "@u32.sub value 2\n");
    defer after.deinit();
    var initial = try before.emit(.{ .retain_artifacts = true });
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    for (initial.capture.?.metadata.principal_queries.records.items) |*record| {
        if (record.dependencies.inputs) |*observed| {
            a.free(observed.source_units);
            observed.source_units = &.{};
            observed.source_units = try a.dupe(u32, &.{1});
        }
    }
    var fresh = try after.emit(.{});
    defer fresh.deinit(a);
    var edited = try after.emit(.{ .retain_artifacts = true, .principal_previous = &initial.capture.? });
    defer edited.deinit(a);
    try std.testing.expect(edited.diagnostic == null);
    try std.testing.expectEqualSlices(u8, fresh.bytes, edited.bytes);
    // Exact named-source results may remain valid independently. Their memo
    // outputs must not replay or carry a broader unverified module observation.
    try std.testing.expectEqual(@as(usize, 0), edited.principal.call_publications_replayed);
    try std.testing.expectEqual(.module_image, edited.principal.source_declines[0].reason);
}

test "combined source inventory accepts exactly max and rejects next unique input" {
    var recorder: inputs.Recorder = .{ .eligible = true, .max_reads = 3 };
    defer recorder.deinit(a);
    try recorder.source(a, .{ .unit = 1, .binding = 1 });
    try recorder.interface(a, .{ .unit = 1, .binding = 2 });
    try recorder.sourceUnit(a, 2);
    try std.testing.expect(recorder.source_complete);
    try recorder.sourceUnit(a, 2);
    try std.testing.expect(recorder.source_complete);
    try recorder.source(a, .{ .unit = 1, .binding = 3 });
    try std.testing.expect(!recorder.source_complete);
    var empty: inputs.Recorder = .{ .eligible = true, .max_reads = 0 };
    defer empty.deinit(a);
    try empty.sourceUnit(a, 1);
    try std.testing.expect(!empty.source_complete);
}
