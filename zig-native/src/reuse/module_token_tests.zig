//! Module tokens decide reuse exactly as validated pins (Core digests) do, a
//! changed module never keeps an old token, and tokens never cross a process:
//! restored checkpoints issue fresh ones and validate their archived digests.
const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
const backend = @import("../backend/core_backend.zig");
const identity = @import("../backend/runtime_identity.zig");
const checkpoint = @import("../backend/backend_checkpoint.zig");
const artifacts = @import("code_artifacts.zig");
const Capture = @import("artifact_capture.zig").Capture;
const a = std.testing.allocator;
const compiler: [32]u8 = @splat(29);

const source =
    \\type Box is data = #Box U32
    \\const open = fn (box: Box) -> U32 => case box of
    \\  #Box value => value
    \\const factory = fn number => fn extra => @u32.add number (open (#Box extra))
    \\const callback = factory 42
    \\const other = 0
    \\entry const schema: U32 = 7
    \\entry const answer = fn (extra: U32) -> U32 => callback extra
    \\entry const plain = fn (x: U32) => @u32.add x 2
    \\entry const unrelated = fn () => other
;
/// A literal edit, a body edit and a revert to the original program.
const edits = [_]struct { from: []const u8, to: []const u8 }{
    .{ .from = "const other = 0", .to = "const other = 1" },
    .{ .from = "@u32.add x 2", .to = "@u32.add x 3" },
    .{ .from = "", .to = "" },
};

const Fixture = struct {
    units: []core.Module,
    names: identity.Metadata,
    fn init(text: []const u8) !Fixture {
        var tokens = try lexer.lex(a, text);
        defer tokens.deinit(a);
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try checker.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        const units = try a.alloc(core.Module, 1);
        errdefer a.free(units);
        units[0] = try core.lower(a, &tree, &pool, &checked);
        errdefer units[0].deinit(a);
        return .{ .units = units, .names = try identity.Metadata.capture(a, &pool, &.{.{ .unit = 1, .path = "/tokens/main.blot" }}, 1) };
    }
    fn edited(from: []const u8, to: []const u8) !Fixture {
        if (from.len == 0) return init(source);
        const text = try std.mem.replaceOwned(u8, a, source, from, to);
        defer a.free(text);
        try std.testing.expect(!std.mem.eql(u8, text, source));
        return init(text);
    }
    fn deinit(self: *Fixture) void {
        self.units[0].deinit(a);
        a.free(self.units);
        self.names.deinit(a);
    }
    fn compile(self: *const Fixture, allocator: std.mem.Allocator, previous: ?*const Capture, validate: bool) !backend.Result {
        var result = try backend.compileWithOptions(allocator, self.units, 1, .{ .identity = self.names.view(), .retain_artifacts = true, .previous = previous, .validate_pins = validate });
        errdefer result.deinit(allocator);
        try std.testing.expect(result.diagnostic == null);
        return result;
    }
};
fn pins(result: *const backend.Result) []const artifacts.ModulePin {
    return result.capture.?.metadata.pools.?.modules;
}

test "tokens and validated pins make identical reuse decisions over an edit series" {
    var populated = [2]?backend.Result{ null, null };
    defer for (&populated) |*result| if (result.*) |*owned| owned.deinit(a);
    var base = try Fixture.init(source);
    defer base.deinit();
    for (&populated, [_]bool{ false, true }) |*result, validate| result.* = try base.compile(a, null, validate);
    var previous: [2]*const backend.Result = .{ &populated[0].?, &populated[1].? };
    var revisions: [edits.len][2]?backend.Result = @splat(.{ null, null });
    defer for (&revisions) |*pair| for (pair) |*result| if (result.*) |*owned| owned.deinit(a);
    var fixtures: [edits.len]?Fixture = @splat(null);
    defer for (&fixtures) |*fixture| if (fixture.*) |*owned| owned.deinit();
    for (edits, &revisions, &fixtures) |edit, *pair, *fixture| {
        fixture.* = try Fixture.edited(edit.from, edit.to);
        for (pair, previous, [_]bool{ false, true }) |*result, before, validate| {
            result.* = try fixture.*.?.compile(a, &before.capture.?, validate);
            const stamps = result.*.?.module_stamps;
            // Tokens alone hash no Core; validation hashes the old pin and the
            // current module once each.
            try std.testing.expectEqual(@as(usize, if (validate) 2 else 0), stamps.hashed);
            for (pins(&result.*.?)) |pin| try std.testing.expectEqual(validate, pin.stamp != null);
            if (validate) try std.testing.expectEqual(artifacts.stamp(fixture.*.?.units[0]), pins(&result.*.?)[0].stamp.?);
        }
        const tokens = &pair[0].?;
        const validated = &pair[1].?;
        try std.testing.expectEqualSlices(u8, validated.bytes, tokens.bytes);
        try std.testing.expectEqualDeep(validated.reuse, tokens.reuse);
        try std.testing.expectEqual(validated.module_stamps.computed, tokens.module_stamps.computed);
        try std.testing.expectEqual(validated.module_stamps.copied, tokens.module_stamps.copied);
        try std.testing.expectEqual(validated.completed_queries.reused, tokens.completed_queries.reused);
        try std.testing.expectEqual(validated.source_validation.reused_images, tokens.source_validation.reused_images);
        // Each revision differs from its predecessor, so its Core gets a fresh
        // token in both modes.
        for (previous, pair) |before, *result| try std.testing.expect(pins(before)[0].token != pins(&result.*.?)[0].token);
        previous = .{ tokens, validated };
    }
}

test "an unchanged module keeps its token across revisions and a stream-equal copy inherits it" {
    var base = try Fixture.init(source);
    defer base.deinit();
    var first = try base.compile(a, null, false);
    defer first.deinit(a);
    // The same buffers: the pin's token carries over without comparing.
    var same = try base.compile(a, &first.capture.?, false);
    defer same.deinit(a);
    try std.testing.expectEqual(pins(&first)[0].token, pins(&same)[0].token);
    try std.testing.expectEqual(@as(usize, 0), same.module_stamps.computed);
    try std.testing.expectEqual(@as(usize, 0), same.module_stamps.copied);
    // Equal contents in other buffers: one comparison, then the same token.
    var copy = try Fixture.init(source);
    defer copy.deinit();
    var copied = try copy.compile(a, &same.capture.?, false);
    defer copied.deinit(a);
    try std.testing.expectEqual(pins(&first)[0].token, pins(&copied)[0].token);
    try std.testing.expectEqual(@as(usize, 1), copied.module_stamps.copied);
    try std.testing.expectEqualSlices(u8, first.bytes, copied.bytes);
    try std.testing.expectEqual(same.reuse.reused_named, copied.reuse.reused_named);
    // A changed module never keeps the old token.
    var changed = try Fixture.edited(edits[0].from, edits[0].to);
    defer changed.deinit();
    var edited = try changed.compile(a, &copied.capture.?, false);
    defer edited.deinit(a);
    try std.testing.expect(pins(&edited)[0].token != pins(&copied)[0].token);
    try std.testing.expectEqual(@as(usize, 1), edited.module_stamps.computed);
}

fn retainedRevision(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const backend.Result, expected: *const backend.Result) !void {
    var result = try fixture.compile(allocator, &previous.capture.?, false);
    defer result.deinit(allocator);
    try std.testing.expectEqualSlices(u8, expected.bytes, result.bytes);
    try std.testing.expectEqual(expected.reuse.reused_named, result.reuse.reused_named);
    try std.testing.expectEqual(pins(expected)[0].token == pins(previous)[0].token, pins(&result)[0].token == pins(previous)[0].token);
}

test "token capture and admission release every allocation failure and keep their decisions" {
    var base = try Fixture.init(source);
    defer base.deinit();
    var first = try base.compile(a, null, false);
    defer first.deinit(a);
    var copy = try Fixture.init(source);
    defer copy.deinit();
    var expected = try copy.compile(a, &first.capture.?, false);
    defer expected.deinit(a);
    try std.testing.expectEqual(pins(&first)[0].token, pins(&expected)[0].token);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, retainedRevision, .{ &copy, &first, &expected });
}

test "checkpoints persist digests, never tokens, and restored pins validate before reuse" {
    var producer = try Fixture.init(source);
    defer producer.deinit();
    // Restored pin validation needs a selected semantic receipt. Inlining
    // can legitimately omit that optional owner; keep this law on query replay.
    var initial = try backend.compileWithOptions(a, producer.units, 1, .{ .identity = producer.names.view(), .retain_artifacts = true, .inline_named = false });
    defer initial.deinit(a);
    try std.testing.expect(initial.diagnostic == null);
    const bytes = try checkpoint.encode(a, compiler, &initial.capture.?);
    defer a.free(bytes);
    for (0..2) |attempt| {
        var loaded = try checkpoint.decode(a, compiler, bytes);
        defer loaded.deinit();
        try std.testing.expect(loaded.semantic != null);
        const restored = loaded.semantic.?.capture.metadata.pools.?.modules;
        // Each decode issues fresh tokens; the archived digest is the Core's.
        try std.testing.expect(restored[0].token != pins(&initial)[0].token);
        try std.testing.expectEqual(artifacts.stamp(producer.units[0]), restored[0].stamp.?);
        try std.testing.expect(try artifacts.pinIntact(&restored[0], null));
        var fixture = try Fixture.init(source);
        defer fixture.deinit();
        var restarted = try backend.compileWithOptions(a, fixture.units, 1, .{ .identity = fixture.names.view(), .retain_artifacts = true, .checkpoint = &loaded, .inline_named = false });
        defer restarted.deinit(a);
        try std.testing.expect(restarted.diagnostic == null);
        try std.testing.expectEqualSlices(u8, initial.bytes, restarted.bytes);
        try std.testing.expect(restarted.completed_queries.reused > 0);
        // The archived pin's digest is recomputed once; current content equal
        // to it inherits the restored token, never the producer's.
        try std.testing.expectEqual(@as(usize, 1), restarted.module_stamps.hashed);
        try std.testing.expectEqual(restored[0].token, pins(&restarted)[0].token);
        try std.testing.expect(pins(&restarted)[0].stamp == null);
        _ = attempt;
    }
}
