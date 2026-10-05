const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const evaluator = @import("core_eval.zig");
const a = std.testing.allocator;

const Failure = struct { source: []const u8, point: u32, detail: checker.Diagnostic.TypeApplication };
fn reject(allocator: std.mem.Allocator, failure: Failure) !void {
    var tokens = try lexer.lex(allocator, failure.source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var syntax = try parser.parse(allocator, failure.source, tokens.tokens.items, &names);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.check(allocator, &syntax, &names);
    defer checked.deinit(allocator);
    try std.testing.expect(checked.diagnostics.len != 0);
    const diagnostic = checked.diagnostics[0];
    try std.testing.expectEqual(checker.Code.type_arity, diagnostic.code);
    try std.testing.expectEqual(failure.point, diagnostic.span.start);
    try std.testing.expectEqual(failure.point, diagnostic.span.end);
    try std.testing.expectEqual(@as(?checker.Diagnostic.TypeApplication, failure.detail), diagnostic.type_application);
}

test "annotation application diagnoses unsaturated and extra type arguments at the frozen application origin under every allocation failure" {
    for ([_]Failure{
        .{ .source = "const values: Array = #[]\n", .point = 14, .detail = .missing_array },
        .{ .source = "const values: ((Array)) = #[]\n", .point = 14, .detail = .missing_array },
        .{ .source = "const values: (Array U32 Bool) = #[]\n", .point = 15, .detail = .extra },
        .{ .source = "const values: Array U32 Bool = #[]\n", .point = 14, .detail = .extra },
        .{ .source = "const value: U32 Bool = 1\n", .point = 13, .detail = .extra },
        .{ .source = "const values: Array Array = #[]\n", .point = 14, .detail = .missing_array },
        .{ .source = "type Maybe a is data = #Some a | #Nothing\nconst value: Maybe = #Nothing\n", .point = 55, .detail = .missing_nominal },
        .{ .source = "type Maybe a is data = #Some a | #Nothing\nconst value: (Maybe) = #Nothing\n", .point = 55, .detail = .missing_nominal },
        .{ .source = "type Maybe a is data = #Some a | #Nothing\nconst value: Maybe U32 Bool = #Nothing\n", .point = 55, .detail = .extra },
        .{ .source = "type Maybe a is data = #Some a | #Nothing\nconst value: Maybe Array Bool = #Nothing\n", .point = 55, .detail = .missing_array },
        .{ .source = "type Pair a => type b is data = #Pair (a,b)\nconst value: Pair U32 = #Pair (1,2)\n", .point = 57, .detail = .missing_nominal },
    }) |failure| {
        try reject(a, failure);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, reject, .{failure});
    }
}

fn unknownBeforeArity(allocator: std.mem.Allocator) !void {
    const source = "const values: Array U32 Missing = #[]\n";
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer syntax.deinit(allocator);
    var checked = try checker.check(allocator, &syntax, &names);
    defer checked.deinit(allocator);
    try std.testing.expect(checked.diagnostics.len != 0);
    try std.testing.expectEqual(checker.Code.unsupported_type, checked.diagnostics[0].code);
    try std.testing.expectEqual(@as(u32, 24), checked.diagnostics[0].span.start);
    try std.testing.expectEqual(@as(u32, 24), checked.diagnostics[0].span.end);
}
test "annotation application resolves argument names before declaring a saturated constructor overapplied" {
    try unknownBeforeArity(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, unknownBeforeArity, .{});
}

test "annotation application preserves curried and shaped nominal constructor instantiation in frozen Core" {
    const source =
        \\type Curried a => type b is data = #Curried (a,b)
        \\type Shaped [a,b] is data = #Shaped (a,b)
        \\const curried: Curried U32 F32 = #Curried (20,1.5)
        \\const shaped: Shaped [U32,F32] = #Shaped (22,2.5)
        \\entry const answer = do:
        \\  let #Curried (left,_) = curried
        \\  let #Shaped (right,_) = shaped
        \\  return @u32.add left right
    ;
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var syntax = try parser.parse(a, source, tokens.tokens.items, &names);
    defer syntax.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.check(a, &syntax, &names);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &syntax, &names, &checked);
    defer module.deinit(a);
    module.unit = 1;
    var session = try evaluator.Session.init(a, &.{module});
    defer session.deinit();
    for (module.bodies) |body| if (body.exported) {
        try std.testing.expectEqual(@as(u32, 42), (try session.value(.{ .unit = 1, .binding = body.binding })).bits);
        return;
    };
    return error.TestUnexpectedResult;
}
