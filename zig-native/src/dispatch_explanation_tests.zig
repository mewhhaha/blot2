const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const explanation_ = @import("dispatch_explanation.zig");
const Allocator = std.mem.Allocator;

const box =
    \\type Box is data=#Box U32
    \\type Num is data=#Num U32
    \\
;
const Expected = struct { side: explanation_.Side, operand: ?[]const u8, outcome: explanation_.Outcome };
const Case = struct {
    source: []const u8,
    /// The checker reports it; otherwise the backend does.
    checked: bool,
    code: []const u8,
    operation: ?[]const u8,
    member: []const u8,
    candidates: []const Expected,
};

/// Checks and, when the checker accepts, lowers and compiles one module
/// without a prelude. Returns the first diagnostic's explanation, cloned.
fn explain(allocator: Allocator, source: []const u8, checked_stage: *bool, code: *[]const u8) !?explanation_.Explanation {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    if (checked.diagnostics.len != 0) {
        checked_stage.* = true;
        code.* = @tagName(checked.diagnostics[0].code);
        return if (checked.diagnostics[0].explanation) |value| try value.clone(allocator) else null;
    }
    checked_stage.* = false;
    var module = try core.lower(allocator, &tree, &pool, &checked);
    defer module.deinit(allocator);
    module.unit = 1;
    var identity = try @import("runtime_identity.zig").Metadata.capture(allocator, &pool, &.{.{ .unit = 1, .path = "main.blot" }}, 1);
    defer identity.deinit(allocator);
    var result = try backend.compileWithOptions(allocator, &.{module}, 1, .{ .identity = identity.view(), .diagnostic_source_mode = true });
    defer result.deinit(allocator);
    const diagnostic = result.diagnostic orelse return error.TestExpectedDiagnostic;
    code.* = @tagName(diagnostic.code);
    return if (result.explanation) |value| try value.clone(allocator) else null;
}

fn expectCase(allocator: Allocator, case: Case) !void {
    var checked_stage = false;
    var code: []const u8 = "";
    const explained = (try explain(allocator, case.source, &checked_stage, &code)) orelse return error.TestExpectedExplanation;
    defer explained.deinit(allocator);
    errdefer if (std.json.Stringify.valueAlloc(allocator, explained, .{})) |json| {
        std.debug.print("{s} {s}\n", .{ code, json });
        allocator.free(json);
    } else |_| {};
    try std.testing.expectEqual(case.checked, checked_stage);
    try std.testing.expectEqualStrings(case.code, code);
    if (case.operation) |operation| try std.testing.expectEqualStrings(operation, explained.operation orelse "") else try std.testing.expect(explained.operation == null);
    try std.testing.expectEqualStrings(case.member, explained.member orelse "");
    try std.testing.expect(!explained.truncated);
    try std.testing.expectEqual(case.candidates.len, explained.candidates.len);
    for (case.candidates, explained.candidates) |want, got| {
        try std.testing.expectEqual(want.side, got.side);
        try std.testing.expectEqual(want.outcome, got.outcome);
        if (want.operand) |operand| try std.testing.expectEqualStrings(operand, got.operand orelse "") else try std.testing.expect(got.operand == null);
    }
}

const cases = [_]Case{
    // Member access searches the receiver only, never an argument's type.
    .{ .source = box ++ "const Num.grow=fn value=>value\nentry const answer=fn()=>(#Box 1).grow (#Num 2)\n", .checked = true, .code = "missing_member", .operation = null, .member = "grow", .candidates = &.{.{ .side = .receiver, .operand = "Box", .outcome = .no_member }} },
    // The left owner is considered before the right one.
    .{ .source = box ++ "const Box.add=fn (left: Box)=>fn (right: Box)=>left\nentry const answer=fn()=>@type.call \"add\" (#Box 1) (#Num 2)\n", .checked = false, .code = "missing_associated", .operation = "+", .member = "add", .candidates = &.{ .{ .side = .left, .operand = "main::Box", .outcome = .incompatible }, .{ .side = .right, .operand = "main::Num", .outcome = .no_member } } },
    // A right owner equal to the left one is not considered twice.
    .{ .source = "entry const folded=@type.call \"add\" #True #True\n", .checked = false, .code = "missing_associated", .operation = "+", .member = "add", .candidates = &.{.{ .side = .left, .operand = "Bool", .outcome = .no_member }} },
    .{ .source = box ++ "const Box.add=fn (left: Box)=>fn (right: Box)=>left\nconst Num.add=fn (left: Num)=>fn (right: Num)=>left\nentry const answer=fn()=>@type.call \"add\" (#Box 1) (#Num 2)\n", .checked = false, .code = "missing_associated", .operation = "+", .member = "add", .candidates = &.{ .{ .side = .left, .operand = "main::Box", .outcome = .incompatible }, .{ .side = .right, .operand = "main::Num", .outcome = .incompatible } } },
    // Result dispatch looks only at its destination.
    .{ .source = box ++ "entry const answer=fn()=>do:\n  let b: Box = @type.result \"from\" 3\n  return 1\n", .checked = false, .code = "missing_associated", .operation = null, .member = "from", .candidates = &.{.{ .side = .destination, .operand = "main::Box", .outcome = .no_member }} },
    // Operands select the left method; its result then conflicts with the
    // annotation, and the right method that would fit is never tried.
    .{ .source = box ++ "const Box.add=fn (left: Box)=>fn (right: Num)=>left\nconst Num.add=fn (left: Box)=>fn (right: Num)=>7\nconst sum=fn a=>fn b=>@type.call \"add\" a b\nentry const answer=fn()=>do:\n  let r: U32 = sum (#Box 1) (#Num 2)\n  return r\n", .checked = true, .code = "type_mismatch", .operation = "+", .member = "add", .candidates = &.{.{ .side = .left, .operand = "Box", .outcome = .result_mismatch }} },
    // A generic callback's dispatch is explained where it is specialized.
    .{ .source = "const twice=fn f=>fn x=>f (f x)\nentry const answer=fn()=>do:\n  let r=twice (fn v=>@type.call \"add\" v v) #True\n  return 1\n", .checked = false, .code = "missing_associated", .operation = "+", .member = "add", .candidates = &.{.{ .side = .left, .operand = "Bool", .outcome = .no_member }} },
};

test "dispatch diagnostics explain candidates in selection order" {
    for (cases) |case| expectCase(std.testing.allocator, case) catch |err| {
        std.debug.print("case failed: {s}\n", .{case.source});
        return err;
    };
}

fn explainUnderFailures(allocator: Allocator, source: []const u8) !void {
    var checked_stage = false;
    var code: []const u8 = "";
    if (try explain(allocator, source, &checked_stage, &code)) |value| value.deinit(allocator);
}
test "dispatch explanations own their text through every allocation failure" {
    for ([_]usize{ 0, 1, 5 }) |index| try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, explainUnderFailures, .{cases[index].source});
}

test "dispatch explanations cut long type spellings and mark truncation" {
    const allocator = std.testing.allocator;
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(allocator);
    const name: [300]u8 = @splat('L');
    try source.print(allocator, "type {s} is data=#Long U32\nentry const answer=fn()=>(#Long 1).missing\n", .{&name});
    var checked_stage = false;
    var code: []const u8 = "";
    const explained = (try explain(allocator, source.items, &checked_stage, &code)) orelse return error.TestExpectedExplanation;
    defer explained.deinit(allocator);
    try std.testing.expect(checked_stage);
    try std.testing.expectEqualStrings("missing_member", code);
    try std.testing.expect(explained.truncated);
    try std.testing.expectEqual(@as(usize, explanation_.max_text), explained.candidates[0].operand.?.len);
}
