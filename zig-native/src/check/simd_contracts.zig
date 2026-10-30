//! Exact four-lane product authority for immutable Core. Namespace legality
//! comes from the source intrinsic catalog; unrelated products never coerce.
const core = @import("core.zig");
const T = @import("types.zig");
const simd = @import("../backend/simd_intrinsics.zig");
const Error = error{InvalidArtifact};
fn scalar(types: *const core.Types, id: T.Id, tag: T.Tag) bool {
    return id < types.nodes.len and types.node(id).tag == tag;
}
fn product(types: *const core.Types, id: T.Id, count: u32) ?[]const T.Id {
    if (id >= types.nodes.len) return null;
    const node = types.node(id);
    if (node.tag != .product or node.b != count or node.a > types.extra.len or count > types.extra.len - node.a) return null;
    return types.extra[node.a..][0..count];
}
fn vector(types: *const core.Types, id: T.Id, lane: simd.Lane) bool {
    const values = product(types, id, 4) orelse return false;
    const tag: T.Tag = if (lane == .u32) .u32 else .f32;
    for (values) |value| if (!scalar(types, value, tag)) return false;
    return true;
}
fn pair(types: *const core.Types, id: T.Id, lane: simd.Lane) bool {
    const values = product(types, id, 2) orelse return false;
    return vector(types, values[0], lane) and vector(types, values[1], lane);
}
fn matches(types: *const core.Types, description: simd.Intrinsic, inputs: []const T.Id, output: T.Id) bool {
    if (inputs.len != description.arity) return false;
    const lane = description.lane();
    if (description.shape == .reduce) {
        return vector(types, inputs[0], lane) and scalar(types, output, .boolean);
    }
    if (!vector(types, output, description.resultLane())) return false;
    return switch (description.shape) {
        .unary, .convert => vector(types, inputs[0], lane),
        .binary, .compare => vector(types, inputs[0], lane) and vector(types, inputs[1], lane),
        .shift, .broadcast => vector(types, inputs[0], lane) and scalar(types, inputs[1], .u32),
        .select, .shuffle => vector(types, inputs[0], .u32) and pair(types, inputs[1], lane),
        .madd => vector(types, inputs[0], lane) and pair(types, inputs[1], lane),
        .swizzle => vector(types, inputs[0], .u32) and vector(types, inputs[1], lane),
        .reduce => unreachable,
    };
}
pub fn validate(types: *const core.Types, operation_: core.Op, inputs: []const T.Id, output: T.Id) Error!void {
    inline for (.{ simd.Lane.u32, simd.Lane.f32 }) |lane| {
        if (simd.operation(operation_, lane)) |description| {
            if (matches(types, description, inputs, output)) return;
        }
    }
    return error.InvalidArtifact;
}
