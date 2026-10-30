const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const evaluator = @import("core_eval.zig");
const backend = @import("../backend/core_backend.zig");
const types = @import("../check/types.zig");
const a = std.testing.allocator;

fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try check.check(allocator, &syntax, &names);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(allocator, &syntax, &names, &checked);
    errdefer result.deinit(allocator);
    result.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    return result;
}

fn emit(allocator: std.mem.Allocator, module: *const core.Module, valid: bool) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    if (valid) {
        try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
        try std.testing.expect(result.bytes.len > 8);
    } else {
        try std.testing.expect(result.diagnostic != null);
        try std.testing.expectEqual(backend.Code.missing_associated, result.diagnostic.?.code);
        try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
    }
}

const nominal_source =
    \\type Box is data = #Box U32
    \\const Box.add = func left => return func right => return do:
    \\  let #Box a = left
    \\  let #Box b = right
    \\  break #Box (@u32.add a b)
    \\entry const answer = func () => return case @type.call "add" (#Box 21) (#Box 21) of
    \\  #Box value => value
    \\entry const folded = answer ()
;

fn evaluate(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    for (module.bodies) |body| if (body.exported and std.mem.eql(u8, module.name(body.export_name), "folded")) {
        try std.testing.expectEqual(@as(u32, 42), (try session.value(.{ .unit = 1, .binding = body.binding })).bits);
        return;
    };
    return error.TestUnexpectedResult;
}

fn checkScenario(allocator: std.mem.Allocator, source: []const u8) !void {
    var module = try lower(allocator, source);
    defer module.deinit(allocator);
}

test "named primitive associated calls require a catalog in both constant evaluation and body specialization" {
    for ([_][]const u8{
        "entry const answer = func () => return @type.call \"add\" 21 21\n",
        "entry const folded = @type.call \"add\" 21 21\n",
        "entry const answer = func () => return @type.call \"eq\" true true\n",
        "entry const folded = @type.call \"eq\" true true\n",
        "const U32.add = func left => return func right => return @u32.add left right\nentry const answer = func () => return @type.call \"add\" 21 21\n",
        "const U32.add = func left => return func right => return @u32.add left right\nentry const folded = @type.call \"add\" 21 21\n",
    }) |source| {
        try checkScenario(a, source);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, checkScenario, .{source});
        var module = try lower(a, source);
        defer module.deinit(a);
        const nodes = try a.dupe(types.Node, module.types.nodes);
        defer a.free(nodes);
        const extra = try a.dupe(types.Id, module.types.extra);
        defer a.free(extra);
        const rows = try a.dupe(types.Effects.Row, module.types.effects.rows);
        defer a.free(rows);
        try emit(a, &module, false);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{ &module, false });
        try std.testing.expectEqualSlices(types.Node, nodes, module.types.nodes);
        try std.testing.expectEqualSlices(types.Id, extra, module.types.extra);
        try std.testing.expectEqualSlices(types.Effects.Row, rows, module.types.effects.rows);
    }
}

test "ordinary qualified primitive names and nominal catalogs remain callable without a prelude" {
    for ([_][]const u8{
        "const U32.add = func left => return func right => return @u32.add left right\nentry const answer = func () => return U32.add 21 21\nentry const folded = answer ()\n",
        nominal_source,
    }) |source| {
        var module = try lower(a, source);
        defer module.deinit(a);
        const nodes = try a.dupe(core.Node, module.nodes);
        defer a.free(nodes);
        const type_nodes = try a.dupe(types.Node, module.types.nodes);
        defer a.free(type_nodes);
        try evaluate(a, &module);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, evaluate, .{&module});
        try emit(a, &module, true);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{ &module, true });
        try std.testing.expectEqualSlices(core.Node, nodes, module.nodes);
        try std.testing.expectEqualSlices(types.Node, type_nodes, module.types.nodes);
    }
}
