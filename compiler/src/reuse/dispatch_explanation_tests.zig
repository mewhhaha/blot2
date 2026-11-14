const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
const explanation_ = @import("dispatch_explanation.zig");
const Allocator = std.mem.Allocator;

const box =
    \\type Box is data= $Box U32
    \\type Num is data= $Num U32
    \\
;
const Expected = struct { side: explanation_.Side, operand: ?[]const u8, outcome: explanation_.Outcome };
fn implementationExplanation(allocator: Allocator) !void {
    var builder: explanation_.Builder = .{ .allocator = allocator };
    defer builder.deinit();
    var long_bytes: [300]u8 = undefined;
    for (0..100) |index| @memcpy(long_bytes[index * 3 ..][0..3], "雪");
    const long = &long_bytes;
    var escaped_bytes: [256]u8 = undefined;
    for (&escaped_bytes, 0..) |*byte, index| {
        byte.* = '\n';
        if (index % 2 != 0) byte.* = '\t';
    }
    const escaped = &escaped_bytes;
    for (0..6) |_| {
        const operand = try builder.ownText(long);
        errdefer allocator.free(operand);
        const origin = try builder.makeOrigin(long, escaped, .{ .start = 1, .end = 20 });
        builder.addOrigin(operand, .head_mismatch, origin);
    }
    for (0..10) |_| try builder.addStep(long, try builder.ownText(long), .requires_evidence);
    const result = try builder.finish(null, "Source");
    defer result.deinit(allocator);
    try std.testing.expect(result.truncated and result.candidates.len == 4 and result.steps.len == 8);
    const encoded = try std.json.Stringify.valueAlloc(allocator, result, .{});
    defer allocator.free(encoded);
    try std.testing.expect(encoded.len <= 2048);
    const copy = try result.clone(allocator);
    defer copy.deinit(allocator);
    try std.testing.expectEqualDeep(result, copy);
}
test "implementation explanations own bounded origins steps and encoded text through OOM" {
    try implementationExplanation(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, implementationExplanation, .{});
}
