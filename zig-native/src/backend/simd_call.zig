//! Direct source wrappers of SIMD shuffles, swizzles and broadcasts keep the
//! primitive's literal lane contract at the call. Parameters must be used
//! exactly once; body matching never uses a source name. The remaining actual
//! arguments are still evaluated in their written order.
const core = @import("../check/core.zig");
const known_call = @import("known_call.zig");
const simd = @import("simd_intrinsics.zig");
pub const Plan = struct {
    target: core.BindingRef,
    op: core.Op,
    count: usize,
    arguments: [3]core.Id,
    /// The argument holding the literal lane selectors.
    lanes: usize,
    /// Vector operands in primitive order, as argument positions. A pair
    /// parameter that is not a literal product occupies one position.
    vectors: [2]usize,
    vector_count: usize,
    /// The right operand is a whole pair parameter rather than two vectors.
    pair_parameter: bool,
};
pub fn analyze(units: []const core.Module, owner: u32, id: core.Id) ?Plan {
    const call = known_call.resolve(units, owner, id) orelse return null;
    if (call.count < 2 or call.count > 3) return null;
    const found = known_call.wrapper(units, owner, call) orelse return null;
    const source = &units[found.target.unit - 1];
    const root = source.node(found.body.root);
    if (root.tag != .scalar or root.c != 0 or !simd.literalLanes(root.op) or root.b == 0) return null;
    const parameters = source.bodyParameters(&found.body);
    var used: u8 = 0;
    var plan: Plan = .{ .target = found.target, .op = root.op, .count = call.count, .arguments = call.arguments[0..3].*, .lanes = 0, .vectors = .{ 0, 0 }, .vector_count = 0, .pair_parameter = false };
    // Broadcast reads its vector first and its lane second.
    const lane_operand = if (root.op == .broadcast) root.b else root.a;
    const vector_operand = if (root.op == .broadcast) root.a else root.b;
    plan.lanes = known_call.parameterPosition(source, found.target.unit, parameters, lane_operand, &used) orelse return null;
    if (simd.pairs(root.op) and source.node(vector_operand).tag == .product) {
        const children = source.children(vector_operand);
        if (children.len != 2) return null;
        for (children, 0..) |child, index| plan.vectors[index] = known_call.parameterPosition(source, found.target.unit, parameters, child, &used) orelse return null;
        plan.vector_count = 2;
    } else {
        plan.vectors[0] = known_call.parameterPosition(source, found.target.unit, parameters, vector_operand, &used) orelse return null;
        plan.vector_count = 1;
        plan.pair_parameter = simd.pairs(root.op);
    }
    if (used != (@as(u8, 1) << @intCast(call.count)) - 1) return null;
    return plan;
}
