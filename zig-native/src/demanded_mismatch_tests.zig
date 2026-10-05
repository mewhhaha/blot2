const std = @import("std");
const types = @import("types.zig");
const display = @import("mismatch_display.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const format = @import("dependency_format.zig");
const a = std.testing.allocator;
const input = "type Box is data = #Box U32\nconst Box.read: Box -> (Unit -> U32) where {} = fn (value: Box) => fn () => value.read\nentry const answer: Unit -> U32 = fn () => (#Box 1).read ()\n";
const native_message = "cannot unify (Unit -> U32 ! {| ?e2}) with U32";

const Observation = struct {
    allocator: std.mem.Allocator,
    variable: types.Id,
    message: ?[]u8 = null,
    fn report(context: *anyopaque, store: *const types.Store, left: types.Id, right: types.Id) std.mem.Allocator.Error!void {
        const self: *Observation = @ptrCast(@alignCast(context));
        std.debug.assert(store.head(self.variable, 0) == types.unit);
        std.debug.assert(left == types.f32_type and right == types.u32_type);
        self.message = try display.render(self.allocator, store, .{ .units = &.{} }, left, right);
    }
};
fn equationScenario(allocator: std.mem.Allocator) !void {
    var owned: ?[]u8 = null;
    defer if (owned) |message| allocator.free(message);
    {
        var store = try types.Store.init(allocator);
        defer store.deinit();
        const variable = try store.fresh();
        const left = try store.function(variable, types.f32_type);
        const right = try store.function(types.unit, types.u32_type);
        const point = store.mark();
        var observed: Observation = .{ .allocator = allocator, .variable = variable };
        defer if (observed.message) |message| allocator.free(message);
        store.unifyWithReporter(left, right, .{ .context = &observed, .report = Observation.report }) catch |err| switch (err) {
            error.TypeMismatch => {},
            else => return err,
        };
        try std.testing.expectEqual(variable, store.head(variable, 0));
        try std.testing.expectEqualDeep(point, store.mark());
        owned = observed.message;
        observed.message = null;
    }
    try std.testing.expectEqualStrings("cannot unify F32 with U32", owned.?);
}
test "failed unification reports the actual leaf before rollback and owns its text after store destruction under every allocation failure" {
    try equationScenario(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, equationScenario, .{});
}

fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer tree.deinit(allocator);
    var checked = try checker.check(allocator, &tree, &names);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &tree, &names, &checked);
    module.unit = 1;
    return module;
}
fn compileScenario(allocator: std.mem.Allocator, source: []const u8, point: u32) !void {
    var result = owned: {
        var module = try lower(allocator, source);
        defer module.deinit(allocator);
        const before = @import("core_snapshot_tests.zig").stamp(module);
        const compiled = try backend.compile(allocator, &.{module}, 1);
        errdefer {
            var cleanup = compiled;
            cleanup.deinit(allocator);
        }
        try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
        break :owned compiled;
    };
    defer result.deinit(allocator);
    try std.testing.expectEqual(backend.Code.type_mismatch, result.diagnostic.?.code);
    try std.testing.expectEqual(point, result.diagnostic.?.span.start);
    try std.testing.expectEqual(point, result.diagnostic.?.span.end);
    try std.testing.expectEqual(@as(usize, 0), result.constant_steps);
    // This law records the honest dense solver namespace, not the reference
    // compiler's ?e3. Exact public numbering remains a separate unresolved gate.
    try std.testing.expectEqualStrings(native_message, result.diagnostic.?.message());
    try std.testing.expectEqualSlices(u8, result.owned_message, result.diagnostic.?.detail);
}
test "demanded nested member mismatch preserves body origin and owned detail after Core destruction under every allocation failure" {
    try compileScenario(a, input, 110);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compileScenario, .{ input, @as(u32, 110) });
}
test "member token origin survives independent prefix text and whitespace without eager checking unused bodies" {
    const prefix = "// unrelated offset\nconst unrelated = 99\n";
    const shifted = prefix ++ input;
    try compileScenario(a, shifted, prefix.len + 110);
    const spaced = "type Box is data = #Box U32\nconst Box.read: Box -> (Unit -> U32) where {} = fn (value: Box) => fn () => value.  read\nentry const answer: Unit -> U32 = fn () => (#Box 1).read ()\n";
    try compileScenario(a, spaced, 112);
    const unused = "type Box is data = #Box U32\nconst Box.read: Box -> (Unit -> U32) where {} = fn (value: Box) => fn () => value.read\nentry const answer = 42\n";
    var module = try lower(a, unused);
    defer module.deinit(a);
    var result = try backend.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.bytes.len > 8);
}
test "a demanded body mismatch follows caller order and does not replace a prior owned diagnostic" {
    const definitions = "type Box is data = #Box U32\nconst Box.read: Box -> (Unit -> U32) where {} = fn (value: Box) => fn () => value.read\n" ++
        "type Other is data = #Other U32\nconst Other.read: Other -> (Unit -> F32) where {} = fn (value: Other) => fn () => value.read\n";
    const first_box = definitions ++ "entry const first: Unit -> U32 = fn () => (#Box 1).read ()\nentry const second: Unit -> F32 = fn () => (#Other 1).read ()\n";
    const first_other = definitions ++ "entry const second: Unit -> F32 = fn () => (#Other 1).read ()\nentry const first: Unit -> U32 = fn () => (#Box 1).read ()\n";
    for ([_][]const u8{ first_box, first_other }, 0..) |source, index| {
        var module = try lower(a, source);
        defer module.deinit(a);
        var result = try backend.compile(a, &.{module}, 1);
        defer result.deinit(a);
        try std.testing.expectEqual(@as(u32, if (index == 0) 110 else 235), result.diagnostic.?.span.start);
        try std.testing.expectEqualStrings(if (index == 0) native_message else "cannot unify (Unit -> F32 ! {| ?e2}) with F32", result.diagnostic.?.message());
    }
    var module = try lower(a, input);
    defer module.deinit(a);
    var session = try @import("core_eval.zig").Session.init(a, &.{module});
    defer session.deinit();
    const prior: @import("core_eval.zig").Diagnostic = .{ .unit = 1, .span = .{ .start = 7, .end = 8 }, .code = .array_bounds };
    session.diagnostic = prior;
    const body = for (module.bodies) |candidate| {
        if (candidate.exported) break candidate;
    } else unreachable;
    try std.testing.expectError(error.Declined, session.sourceInterface(.{ .unit = 1, .binding = body.binding }));
    try std.testing.expectEqualDeep(prior, session.diagnostic.?);
    try std.testing.expectEqual(@as(usize, 0), session.owned_diagnostic_message.len);
}
fn portableScenario(allocator: std.mem.Allocator) !void {
    const key: format.Key = .{ .compiler = @splat(1), .settings = @splat(2), .source = @splat(3), .dependencies = @splat(4) };
    var decoded = owned: {
        var module = try lower(allocator, input);
        defer module.deinit(allocator);
        const bytes = try format.encode(allocator, key, module);
        defer allocator.free(bytes);
        break :owned try format.decode(core.Module, allocator, bytes, key);
    };
    defer format.deinit(allocator, &decoded);
    try std.testing.expectEqual(@as(u32, 110), decoded.projections[0].diagnostic_point);
    try @import("frozen_core_validation.zig").validate(allocator, &decoded, .{ .source_length = input.len });
    const before = @import("core_snapshot_tests.zig").stamp(decoded);
    var result = try backend.compile(allocator, &.{decoded}, 1);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 110), result.diagnostic.?.span.start);
    try std.testing.expectEqualStrings(native_message, result.diagnostic.?.message());
    decoded.projections[0].diagnostic_point = input.len + 1;
    try std.testing.expect(!std.mem.eql(u8, &before, &@import("core_snapshot_tests.zig").stamp(decoded)));
    try std.testing.expectError(error.InvalidArtifact, @import("frozen_core_validation.zig").validate(allocator, &decoded, .{ .source_length = input.len }));
}
test "portable Core owns and validates source member origins and includes them in conservative structural identity under every allocation failure" {
    try portableScenario(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, portableScenario, .{});
}
