//! Scalar pattern comparisons preserve the language's F32 equality semantics.
const Code = @import("runtime_code.zig").Code;
const Local = @import("runtime_code.zig").Local;
pub fn equal(c: Code, left: Local, right: Local, floating: bool) !Local {
    const result = try c.temp();
    if (floating) {
        try c.value(left);
        try c.op(.f32_reinterpret_i32, 0);
        try c.value(right);
        try c.op(.f32_reinterpret_i32, 0);
        try c.op(.f32_eq, 0);
        try c.op(.local_set, result.id);
    } else try c.set(result, .{ .i32_eq, left, right });
    return result;
}
