const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const eval = @import("core_eval.zig");
const types = @import("types.zig");
const a = std.testing.allocator;

fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(allocator, &syntax, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(allocator, &syntax, &names, &checked);
    errdefer result.deinit(allocator);
    result.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    return result;
}
const Case = struct { source: []const u8, code: ?backend.Code, point: ?u32 = null, detail: ?[]const u8 = null };
const cases = [_]Case{
    .{ .source = "let runtime = 42\nentry const answer = runtime\n", .code = .const_runtime_dependency, .point = 0 },
    .{ .source = "let runtime = fn () => 42\nconst copied = runtime\nentry const answer: Unit -> U32 = copied\n", .code = .const_runtime_dependency, .point = 4, .detail = "a const initializer cannot read a top-level let function" },
    .{ .source = "// 😀\nlet runtime = fn () => 42\nconst copied = runtime\nentry const answer: Unit -> U32 = copied\n", .code = .const_runtime_dependency, .point = 12 },
    .{ .source = "let saved.action = fn () => 42\nconst copied = saved.action\nentry const answer: Unit -> U32 = copied\n", .code = .const_runtime_dependency, .point = 4 },
    .{ .source = "let runtime = fn value => fn other => 42\nentry const answer: U32 = runtime 1 (@panic \"later\")\n", .code = .const_runtime_dependency, .point = 0 },
    .{ .source = "let runtime = fn value => fn other => 42\nentry const answer: U32 = runtime (@panic \"first\") (@panic \"later\")\n", .code = .const_panic, .detail = "first" },
    .{ .source = "let runtime = fn value => fn other => 42\nentry const answer: U32 = runtime (@u32.div 1 0) (@panic \"later\")\n", .code = .integer_divide_by_zero },
    .{ .source = "let runtime = if #True then (fn value => 42) else (fn value => 41)\nentry const answer: U32 = runtime (@panic \"argument\")\n", .code = .const_runtime_dependency, .point = 0 },
    .{ .source = "let runtime = fn () => 42\nentry const answer = if #True then 42 else runtime ()\n", .code = null },
    .{ .source = "let runtime = 42\nconst copied = runtime\nentry const answer = 42\n", .code = null },
    .{ .source = "let runtime = 42\nentry const answer: Unit -> U32 = fn () => runtime\n", .code = null },
};
fn compile(allocator: std.mem.Allocator, module: *const core.Module, case: Case) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    if (case.code) |code| {
        try std.testing.expect(result.diagnostic != null);
        try std.testing.expectEqual(code, result.diagnostic.?.code);
        try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
        if (case.point) |point| try std.testing.expectEqual(core.Span{ .start = point, .end = point }, result.diagnostic.?.span);
        if (case.detail) |detail| try std.testing.expectEqualStrings(detail, result.diagnostic.?.message());
    } else {
        try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
        try std.testing.expect(result.bytes.len > 8);
    }
}
fn fingerprint(module: *const core.Module) u64 {
    var hash = std.hash.Wyhash.init(0);
    inline for (.{ "runtime_names", "nodes", "spans", "extra", "bindings", "bodies", "parameters", "references", "calls", "obligations" }) |field| hash.update(std.mem.sliceAsBytes(@field(module, field)));
    hash.update(std.mem.sliceAsBytes(module.types.nodes));
    hash.update(std.mem.sliceAsBytes(module.types.extra));
    hash.update(std.mem.sliceAsBytes(module.types.effects.rows));
    hash.update(std.mem.sliceAsBytes(module.types.effects.labels));
    return hash.final();
}
test "startup reads distinguish retained functions from guarded value invocation" {
    for (cases) |case| {
        var module = try lower(a, case.source);
        defer module.deinit(a);
        const before = fingerprint(&module);
        try compile(a, &module, case);
        try std.testing.expectEqual(before, fingerprint(&module));
    }
}
test "runtime declaration points are sparse owned numeric records after frontend teardown" {
    var module = try lower(a, cases[2].source);
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 8), @sizeOf(core.RuntimeName));
    try std.testing.expectEqual(@as(usize, 1), module.runtime_names.len);
    try std.testing.expectEqual(@as(u32, 12), module.runtimeNamePoint(module.runtime_names[0].binding));
    var plain = try lower(a, "entry const answer = 42\n");
    defer plain.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), plain.runtime_names.len);
}
test "startup diagnostics release every backend failure without changing frozen evidence" {
    for (cases[0..8]) |case| {
        var module = try lower(a, case.source);
        defer module.deinit(a);
        const before = fingerprint(&module);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, compile, .{ &module, case });
        try std.testing.expectEqual(before, fingerprint(&module));
    }
}
fn frontendOwnership(allocator: std.mem.Allocator, source: []const u8) !void {
    var module = try lower(allocator, source);
    defer module.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), module.runtime_names.len);
    try std.testing.expectEqual(@as(u32, 12), module.runtime_names[0].point);
}
test "sparse parser and Core runtime points release every frontend allocation failure" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, frontendOwnership, .{cases[2].source});
}
test "dependency classification does not bypass native work guards or reuse execution" {
    var module = try lower(a, cases[0].source);
    defer module.deinit(a);
    for ([_]bool{ true, false }) |reuse| {
        var session = try eval.Session.init(a, &.{module});
        session.options = .{ .trace_runtime_dependencies = true, .reuse_validated_calls = reuse, .max_steps = 0 };
        defer session.deinit();
        try std.testing.expectError(error.Declined, session.richValue(.{ .unit = 1, .binding = module.bodies[2].binding }));
        try std.testing.expectEqual(eval.Code.constant_fuel, session.diagnostic.?.code);
    }
}
