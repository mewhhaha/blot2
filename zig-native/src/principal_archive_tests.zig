const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const identity = @import("runtime_identity.zig");
const archive = @import("backend_checkpoint.zig");
const a = std.testing.allocator;
const compiler: [32]u8 = @splat(17);
const source =
    \\type Box is data = #Box U32
    \\const extract = fn (box: Box) -> U32 => case box of
    \\  #Box value => value
    \\entry const answer: U32 where { type_rep U32 } = @u32.div 8 (extract (#Box 2))
;
const Fixture = struct {
    units: [1]core.Module,
    names: identity.Metadata,
    fn init(text: []const u8) !Fixture {
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tokens = try lexer.lex(a, text);
        defer tokens.deinit(a);
        var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try checker.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        var module = try core.lower(a, &tree, &pool, &checked);
        errdefer module.deinit(a);
        return .{ .units = .{module}, .names = try identity.Metadata.capture(a, &pool, &.{.{ .unit = 1, .path = "/checkpoint/main.blot" }}, 1) };
    }
    fn emit(self: *const Fixture, allocator: std.mem.Allocator, cache: ?*const archive.Checkpoint) !backend.Result {
        return backend.compileWithOptions(allocator, &self.units, 1, .{ .identity = self.names.view(), .policy = .project, .retain_artifacts = true, .checkpoint = cache });
    }
    fn deinit(self: *Fixture) void {
        self.units[0].deinit(a);
        self.names.deinit(a);
    }
};
fn makeCheckpoint() ![]u8 {
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    var compiled = try fixture.emit(a, null);
    defer compiled.deinit(a);
    try std.testing.expect(compiled.diagnostic == null);
    return archive.encode(a, compiler, &compiled.capture.?);
}
fn importScenario(allocator: std.mem.Allocator, fixture: *const Fixture, bytes: []const u8, expected: []const u8) !void {
    var loaded = try archive.decode(allocator, compiler, bytes);
    defer loaded.deinit();
    var compiled = try fixture.emit(allocator, &loaded);
    defer compiled.deinit(allocator);
    try std.testing.expect(compiled.diagnostic == null);
    try std.testing.expect(compiled.principal.persisted_hits > 0);
    try std.testing.expect(compiled.principal.persisted_call_proofs > 0);
    try std.testing.expectEqualSlices(u8, expected, compiled.bytes);
}
test "portable semantic checkpoints outlive source owners and preserve inference through allocation failures" {
    const bytes = try makeCheckpoint();
    defer a.free(bytes);
    var fixture = try Fixture.init(source);
    defer fixture.deinit();
    var fresh = try fixture.emit(a, null);
    defer fresh.deinit(a);
    try importScenario(a, &fixture, bytes, fresh.bytes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, importScenario, .{ &fixture, bytes, fresh.bytes });
}
test "portable semantic checkpoints reject source settings and malformed semantic graph candidates" {
    const bytes = try makeCheckpoint();
    defer a.free(bytes);
    try std.testing.expectError(error.StaleArtifact, archive.decode(a, @splat(18), bytes));
    var loaded = try archive.decode(a, compiler, bytes);
    defer loaded.deinit();
    const changed = try std.mem.replaceOwned(u8, a, source, "Box 2", "Box 0");
    defer a.free(changed);
    var fixture = try Fixture.init(changed);
    defer fixture.deinit();
    var fresh = try fixture.emit(a, null);
    defer fresh.deinit(a);
    var attempted = try fixture.emit(a, &loaded);
    defer attempted.deinit(a);
    try std.testing.expect(fresh.diagnostic != null);
    try std.testing.expectEqualDeep(fresh.diagnostic, attempted.diagnostic);
    try std.testing.expectEqual(@as(usize, 0), attempted.principal.persisted_hits);
    var matching = try Fixture.init(source);
    defer matching.deinit();
    const call = loaded.principal.snapshot.proofs[0].inputs.call_publications[0];
    loaded.principal.snapshot.evidence.nodes[call.evidence].a = std.math.maxInt(u32);
    var declined = try matching.emit(a, &loaded);
    defer declined.deinit(a);
    try std.testing.expect(declined.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 0), declined.principal.persisted_hits);
    try std.testing.expect(declined.principal.persisted_declines > 0);
}
