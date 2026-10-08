const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const identity = @import("runtime_identity.zig");
const inputs = @import("principal_inputs.zig");
const image = @import("principal_input_image.zig");
const eval = @import("core_eval.zig");
const T = @import("types.zig");
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
    try std.testing.expect(initial.capture.?.metadata.principal_proofs.items[0].inputs != null);
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

test "principal input image does not hide staged errors or change the last good capture" {
    var before = try Fixture.init("entry const answer: U32 where { type_rep U32 } = @u32.div 8 2\n");
    defer before.deinit();
    var after = try Fixture.init("entry const answer: U32 where { type_rep U32 } = @u32.div 8 0\n");
    defer after.deinit();
    var initial = try before.emit(.{ .retain_artifacts = true });
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    const stamp = @import("code_artifacts.zig").stamp(initial.capture.?.metadata.principal_proofs.items);
    var fresh = try after.emit(.{ .retain_artifacts = true });
    defer fresh.deinit(a);
    var candidate = try after.emit(.{ .retain_artifacts = true, .principal_previous = &initial.capture.? });
    defer candidate.deinit(a);
    try std.testing.expect(candidate.diagnostic != null);
    try std.testing.expectEqualDeep(fresh.diagnostic, candidate.diagnostic);
    try std.testing.expectEqual(fresh.constant_steps, candidate.constant_steps);
    try std.testing.expect(candidate.capture == null and candidate.bytes.len == 0);
    try std.testing.expect(candidate.principal.projected_empty_hits > 0);
    try std.testing.expectEqualSlices(u8, &stamp, &@import("code_artifacts.zig").stamp(initial.capture.?.metadata.principal_proofs.items));
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
    try session.validated_calls.put(a, .{ .target = .{ .unit = 0, .binding = target.binding }, .evidence = T.u32_type }, {});
    try std.testing.expect(!present.matches(&session));
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, recordingFailures, .{});
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, nominalRecording, .{});
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
    try std.testing.expect(session.plain_nominals.count() == 0);
    failure.fail_index = std.math.maxInt(usize);
    try key.publish(&session);
    try std.testing.expectEqual(@as(?bool, true), session.plain_nominals.get(nominal));
    try std.testing.expect(!key.matches(&session));
    try session.plain_nominals.put(session.allocator, nominal, false);
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
    const key = initial.capture.?.metadata.principal_proofs.items[0].inputs orelse return error.TestExpectedPrincipalInputs;
    try std.testing.expect(key.call_publications.len > 0);
    try std.testing.expect(key.plain_reads.len > 0);
    const stamp = @import("code_artifacts.zig").stamp(initial.capture.?.metadata.principal_proofs.items);
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
    try std.testing.expectEqualSlices(u8, &stamp, &@import("code_artifacts.zig").stamp(initial.capture.?.metadata.principal_proofs.items));
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, replayFailure, .{ &after, &initial.capture.?, fresh.bytes });
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
    try std.testing.expectEqual(@as(usize, 1), old.metadata.principal_proofs.items[0].inputs.?.scalar_reads.len);
    const stamp = @import("code_artifacts.zig").stamp(old.metadata.principal_proofs.items);
    var fresh = try after.emit(.{ .retain_artifacts = true });
    defer fresh.deinit(a);
    try std.testing.expect(fresh.diagnostic == null);
    try replayFailure(a, &after, old, fresh.bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, replayFailure, .{ &after, old, fresh.bytes });
    try std.testing.expectEqualSlices(u8, &stamp, &@import("code_artifacts.zig").stamp(old.metadata.principal_proofs.items));
}
