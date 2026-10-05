const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const evaluator = @import("core_eval.zig");
const a = std.testing.allocator;

fn lower(source: []const u8) !core.Module {
    var lexed = try lexer.lex(a, source);
    defer lexed.deinit(a);
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var syntax = try parser.parse(a, source, lexed.tokens.items, &names);
    defer syntax.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.check(a, &syntax, &names);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &syntax, &names, &checked);
    errdefer module.deinit(a);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

fn reject(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    // The language's bootstrap limit must win before a smaller implementation
    // work/cell budget, allocating array cells, or invoking the generator.
    session.options.max_steps = 64;
    session.options.max_children = 8;
    for (module.bodies) |body| if (body.exported) {
        if (session.richValue(.{ .unit = 1, .binding = body.binding })) |_| {
            return error.TestUnexpectedResult;
        } else |err| {
            if (err == error.OutOfMemory) return err;
            try std.testing.expectEqual(error.Declined, err);
        }
        const diagnostic = session.diagnostic.?;
        try std.testing.expectEqual(evaluator.Code.backend_limit, diagnostic.code);
        try std.testing.expectEqual(@as(u32, 0), diagnostic.span.start);
        try std.testing.expectEqual(@as(u32, 0), diagnostic.span.end);
        try std.testing.expectEqualStrings("array length exceeds the 16 MiB bootstrap arena", diagnostic.message());
        try std.testing.expect(session.snapshot().children.len <= 1);
        return;
    };
    return error.TestUnexpectedResult;
}

test "compile-time array bootstrap boundary rejects before cells or generator invocation and releases every failed allocation" {
    for ([_][]const u8{
        "entry const answer = @array.length (@array.generate 4194304 (fn (index: U32) -> U32 => index))\n",
        "entry const answer = @array.length (@array.generate 4294967295 (fn (index: U32) -> U32 => @panic \"unvisited\"))\n",
        "entry const answer = @array.length (@array.fill 4194304 7)\n",
        "entry const answer = @array.length (@array.fill 4294967295 7)\n",
    }) |source| {
        var module = try lower(source);
        defer module.deinit(a);
        const nodes = try a.dupe(core.Node, module.nodes);
        defer a.free(nodes);
        try reject(a, &module);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, reject, .{&module});
        try std.testing.expectEqualDeep(nodes, module.nodes);
    }
}
