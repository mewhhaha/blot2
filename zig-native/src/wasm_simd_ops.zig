//! Strict four-lane operations from the core WebAssembly SIMD specification.
//! https://webassembly.github.io/spec/core/appendix/index-instructions.html
const w = @import("wasm.zig");
pub fn code(op: w.Op) ?u32 {
    return switch (op) {
        .v128_load => 0x00,
        .v128_store => 0x0b,
        .i32x4_splat => 0x11,
        .f32x4_splat => 0x13,
        .i32x4_replace_lane => 0x1c,
        .i32x4_extract_lane => 0x1b,
        .f32x4_extract_lane => 0x1f,
        .i32x4_add => 0xae,
        .i32x4_sub => 0xb1,
        .i32x4_mul => 0xb5,
        .v128_and => 0x4e,
        .v128_or => 0x50,
        .v128_xor => 0x51,
        .f32x4_abs => 0xe0,
        .f32x4_neg => 0xe1,
        .f32x4_ceil => 0x67,
        .f32x4_floor => 0x68,
        .f32x4_trunc => 0x69,
        .f32x4_sqrt => 0xe3,
        .f32x4_add => 0xe4,
        .f32x4_sub => 0xe5,
        .f32x4_mul => 0xe6,
        .f32x4_div => 0xe7,
        .f32x4_convert_i32x4_u => 0xfb,
        .i32x4_trunc_sat_f32x4_u => 0xf9,
        else => null,
    };
}
