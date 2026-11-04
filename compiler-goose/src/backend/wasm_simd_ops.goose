namespace blot_backend_wasm_simd_ops;
import .runtime_ir;

fn code(op: blot_backend_runtime_ir::Op) -> u32, bool {
    if op == blot_backend_runtime_ir::OP_v128_load { return 0x00, true; }
    if op == blot_backend_runtime_ir::OP_v128_store { return 0x0b, true; }
    if op == blot_backend_runtime_ir::OP_i32x4_splat { return 0x11, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_splat { return 0x13, true; }
    if op == blot_backend_runtime_ir::OP_i32x4_replace_lane { return 0x1c, true; }
    if op == blot_backend_runtime_ir::OP_i32x4_extract_lane { return 0x1b, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_extract_lane { return 0x1f, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_replace_lane { return 0x20, true; }
    if op == blot_backend_runtime_ir::OP_i32x4_add { return 0xae, true; }
    if op == blot_backend_runtime_ir::OP_i32x4_sub { return 0xb1, true; }
    if op == blot_backend_runtime_ir::OP_i32x4_mul { return 0xb5, true; }
    if op == blot_backend_runtime_ir::OP_v128_and { return 0x4e, true; }
    if op == blot_backend_runtime_ir::OP_v128_or { return 0x50, true; }
    if op == blot_backend_runtime_ir::OP_v128_xor { return 0x51, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_abs { return 0xe0, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_neg { return 0xe1, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_ceil { return 0x67, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_floor { return 0x68, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_trunc { return 0x69, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_sqrt { return 0xe3, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_add { return 0xe4, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_sub { return 0xe5, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_mul { return 0xe6, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_div { return 0xe7, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_convert_i32x4_u { return 0xfb, true; }
    if op == blot_backend_runtime_ir::OP_i32x4_trunc_sat_f32x4_u { return 0xf9, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_convert_i32x4_s { return 0xfa, true; }
    if op == blot_backend_runtime_ir::OP_i32x4_trunc_sat_f32x4_s { return 0xf8, true; }
    if op == blot_backend_runtime_ir::OP_i8x16_shuffle { return 0x0d, true; }
    if op == blot_backend_runtime_ir::OP_i32x4_eq { return 0x37, true; }
    if op == blot_backend_runtime_ir::OP_i32x4_ne { return 0x38, true; }
    if op == blot_backend_runtime_ir::OP_i32x4_lt_u { return 0x3a, true; }
    if op == blot_backend_runtime_ir::OP_i32x4_gt_u { return 0x3c, true; }
    if op == blot_backend_runtime_ir::OP_i32x4_le_u { return 0x3e, true; }
    if op == blot_backend_runtime_ir::OP_i32x4_ge_u { return 0x40, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_eq { return 0x41, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_ne { return 0x42, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_lt { return 0x43, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_gt { return 0x44, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_le { return 0x45, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_ge { return 0x46, true; }
    if op == blot_backend_runtime_ir::OP_v128_not { return 0x4d, true; }
    if op == blot_backend_runtime_ir::OP_v128_andnot { return 0x4f, true; }
    if op == blot_backend_runtime_ir::OP_v128_bitselect { return 0x52, true; }
    if op == blot_backend_runtime_ir::OP_v128_any_true { return 0x53, true; }
    if op == blot_backend_runtime_ir::OP_i32x4_all_true { return 0xa3, true; }
    if op == blot_backend_runtime_ir::OP_i32x4_shl { return 0xab, true; }
    if op == blot_backend_runtime_ir::OP_i32x4_shr_s { return 0xac, true; }
    if op == blot_backend_runtime_ir::OP_i32x4_shr_u { return 0xad, true; }
    if op == blot_backend_runtime_ir::OP_i32x4_min_u { return 0xb7, true; }
    if op == blot_backend_runtime_ir::OP_i32x4_max_u { return 0xb9, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_pmin { return 0xea, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_pmax { return 0xeb, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_relaxed_madd { return 0x105, true; }
    if op == blot_backend_runtime_ir::OP_f32x4_relaxed_nmadd { return 0x106, true; }
    return 0, false;
}
