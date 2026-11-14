const std = @import("std");
const core = @import("core.zig");
const a = std.testing.allocator;
test "task lexical evidence cannot instantiate an ordinary universal data witness" {
    const T = @import("types.zig");
    var nodes = [_]T.Node{
        .{ .tag = .absent },                                              .{ .tag = .unit },                             .{ .tag = .boolean },
        .{ .tag = .u32 },                                                 .{ .tag = .f32 },                              .{ .tag = .never },
        .{ .tag = .bound, .a = 0, .b = 0, .c = 0 },                       .{ .tag = .function, .a = 6, .b = 6, .c = 0 }, .{ .tag = .forall, .a = 7, .b = 0, .c = 1 },
        .{ .tag = .nominal, .a = std.math.maxInt(u32), .b = 16, .c = 1 }, .{ .tag = .scoped, .a = 9, .b = 1, .c = 1 },   .{ .tag = .function, .a = 10, .b = 10, .c = 0 },
    };
    var extra = [_]T.Id{ 6, 0 };
    var rows = [_]T.Effects.Row{.{}};
    const types: core.Types = .{ .nodes = &nodes, .extra = &extra, .effects = .{ .rows = &rows } };
    var remaining: usize = 65_536;
    var proof: @import("package_contracts.zig").Principal = .{ .left = &types, .right = &types, .remaining = &remaining };
    const actual_group = nodes[11];
    nodes[11] = .{ .tag = .function, .a = T.u32_type, .b = T.u32_type, .c = 0 };
    try proof.instantiate(8, 11);
    nodes[11] = actual_group;
    try std.testing.expectError(error.InvalidArtifact, proof.instantiate(8, 11));
}
