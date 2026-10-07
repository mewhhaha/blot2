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
        configured.policy.reuse_projected_principals = true;
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
    var candidate = try after.emit(.{ .retain_artifacts = true, .principal_previous = &initial.capture.?, .policy = .{ .reuse_unaffected_modules = true } });
    defer candidate.deinit(a);
    try std.testing.expect(candidate.diagnostic == null);
    try std.testing.expect(candidate.principal.projected_empty_hits > 0);
    try std.testing.expect(candidate.principal.fresh_regions < fresh.principal.fresh_regions);
    try std.testing.expectEqualSlices(u8, fresh.bytes, candidate.bytes);
    try std.testing.expectEqual(fresh.constant_steps, candidate.constant_steps);
    try std.testing.expect(!std.mem.eql(u8, initial.bytes, candidate.bytes));
    var reverted = try before.emit(.{ .retain_artifacts = true, .principal_previous = &candidate.capture.?, .policy = .{ .reuse_unaffected_modules = true } });
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
    var candidate = try after.emit(.{ .retain_artifacts = true, .principal_previous = &initial.capture.?, .policy = .{ .reuse_unaffected_modules = true } });
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

fn replayFailure(allocator: std.mem.Allocator, fixture: *const Fixture, old: *const @import("artifact_capture.zig").Capture, expected: []const u8) !void {
    var candidate = try fixture.emitUsing(allocator, .{ .retain_artifacts = true, .principal_previous = old, .policy = .{ .reuse_unaffected_modules = true } });
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
