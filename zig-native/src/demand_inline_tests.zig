const std = @import("std");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const demand = @import("demand_inline.zig");

fn lower(a: std.mem.Allocator, source: []const u8) !core.Module {
    var lexed = try @import("lexer.zig").lex(a, source);
    defer lexed.deinit(a);
    var names: @import("symbols.zig").Pool = .{};
    defer names.deinit(a);
    var tree = try @import("parser.zig").parse(a, source, lexed.tokens.items, &names);
    defer tree.deinit(a);
    var checked = try @import("check.zig").check(a, &tree, &names);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(a, &tree, &names, &checked);
    result.unit = 1;
    return result;
}

fn emit(a: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compile(a, &.{module.*}, 1);
    defer result.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.bytes.len > 8);
}

test "demand forwarding bounds nested proofs and preserves immutable Core under allocation failure" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const twice = fn ~(value: U32) => @u32.add (@demand value) (@demand value)
        \\const forward = fn ~(value: U32) => twice (@demand value)
        \\const many = fn ~(value: U32) => @u32.add (forward (@demand value)) (twice (@demand value))
        \\const ignore = fn ~(value: U32) => 42
        \\const discard = fn ~(value: U32) => ignore (@demand value)
        \\entry const run = fn (value: U32) => many value
        \\entry const skip = fn (value: U32) => discard (@u32.div 1 value)
    );
    defer module.deinit(a);
    var forwarded: usize = 0;
    for (module.bodies) |*body| if (demand.Plan.init(&module, body)) |plan| {
        if (plan.call_count != 0) forwarded += 1;
        for (plan.uses) |uses| try std.testing.expect(uses <= 2);
    };
    try std.testing.expect(forwarded >= 3);
    const before = @import("core_snapshot_tests.zig").stamp(module);
    try emit(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(module));
}

test "recursive demand forwarding declines its bounded inline proof" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const recursive: ~U32 -> U32 = fn ~(value: U32) => recursive (@demand value)
        \\entry const unused = 42
    );
    defer module.deinit(a);
    for (module.bodies) |*body| {
        if (body.parameters.len == 0) continue;
        try std.testing.expect(demand.Plan.init(&module, body) == null);
    }
}
