//! Disjointness is reconstructed from one moved binding version and literal
//! half-open ranges. This private plan is never decoded as proof authority.
const std = @import("std");
const C = @import("core.zig");
const T = @import("types.zig");
const tasks = @import("task_types.zig");
const Error = error{InvalidArtifact};
pub const Range = struct { first: u32, end: u32 };
pub const Plan = struct { owner: C.BindingRef, payload: T.Id, ranges: [16]Range = undefined, len: usize, limit: u32 = 0 };
fn require(condition: bool) Error!void {
    if (!condition) return error.InvalidArtifact;
}
pub fn partition(module: *const C.Module, id: C.Id) Error!Plan {
    const node = module.node(id);
    try require(node.tag == .task and node.c == @backingInt(tasks.Op.split) and node.b == 3);
    const operands = module.children(id);
    try require(module.node(operands[0]).tag == .reference);
    const owner = module.reference(operands[0]);
    try require(owner.unit == 0 or owner.unit == module.unit);
    const wrapper = module.types.node(module.typeOf(operands[0]));
    try require(wrapper.tag == .usage and wrapper.b == @backingInt(T.UsageKind.unique) and wrapper.c == 0 and module.types.node(wrapper.a).tag == .array);
    const ranges = module.node(operands[1]);
    try require(ranges.tag == .product and ranges.b != 0 and ranges.b <= 16);
    var result: Plan = .{ .owner = owner, .payload = wrapper.a, .len = ranges.b };
    for (module.children(operands[1]), 0..) |range_id, index| {
        const range = module.node(range_id);
        try require(range.tag == .product and range.b == 2);
        const endpoints = module.children(range_id);
        const first = module.node(endpoints[0]);
        const end = module.node(endpoints[1]);
        try require(first.tag == .constant and end.tag == .constant and first.ty == T.u32_type and end.ty == T.u32_type and first.a <= end.a);
        result.ranges[index] = .{ .first = first.a, .end = end.a };
        result.limit = @max(result.limit, end.a);
        for (result.ranges[0..index]) |prior| try require(prior.first == prior.end or first.a == end.a or prior.end <= first.a or end.a <= prior.first);
    }
    try require(module.node(operands[2]).tag == .closure);
    const callback = module.closure(operands[2]);
    const parameters = module.types.node(callback.parameter.ty);
    try require(parameters.tag == .product and parameters.b == result.len);
    var remaining: usize = 4096;
    var scope: T.Node = .{ .tag = .absent };
    for (module.types.list(.{ .start = parameters.a, .len = parameters.b }), 0..) |input, ordinal| {
        const view = tasks.viewInfo(&module.types, input) orelse return error.InvalidArtifact;
        try require(@import("rank_equal.zig").equalWithBudget(&module.types, view.payload, result.payload, true, &remaining) catch return error.InvalidArtifact);
        const version = module.types.node(view.version);
        try require(version.a == module.unit and version.b == owner.binding and version.c == ordinal);
        const region = module.types.node(view.scope);
        if (ordinal == 0) scope = region else try require(region.b == scope.b and region.c == scope.c);
    }
    return result;
}
