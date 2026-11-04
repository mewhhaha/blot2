namespace blot_backend_scalar_ops;
import std;
import math;
import .runtime_ir;
import check.core;
import support.error;
import support.option;

struct Value { scalar: blot_backend_runtime_ir::Scalar = blot_backend_runtime_ir::SC_unit, bits: u32 = 0 }
fn opcode(op: blot_check_core::Op, scalar: blot_backend_runtime_ir::Scalar) -> blot_support::Option<blot_backend_runtime_ir::Op> {
    let floating = scalar == blot_backend_runtime_ir::SC_f32;
    if op == blot_check_core::Op.add { if floating { return blot_support::some(blot_backend_runtime_ir::OP_f32_add); } return blot_support::some(blot_backend_runtime_ir::OP_i32_add); }
    if op == blot_check_core::Op.sub { if floating { return blot_support::some(blot_backend_runtime_ir::OP_f32_sub); } return blot_support::some(blot_backend_runtime_ir::OP_i32_sub); }
    if op == blot_check_core::Op.mul { if floating { return blot_support::some(blot_backend_runtime_ir::OP_f32_mul); } return blot_support::some(blot_backend_runtime_ir::OP_i32_mul); }
    if op == blot_check_core::Op.div { if floating { return blot_support::some(blot_backend_runtime_ir::OP_f32_div); } return blot_support::some(blot_backend_runtime_ir::OP_i32_div_u); }
    if op == blot_check_core::Op.equal { if floating { return blot_support::some(blot_backend_runtime_ir::OP_f32_eq); } return blot_support::some(blot_backend_runtime_ir::OP_i32_eq); }
    if op == blot_check_core::Op.not_equal { if floating { return blot_support::some(blot_backend_runtime_ir::OP_f32_ne); } return blot_support::some(blot_backend_runtime_ir::OP_i32_ne); }
    if op == blot_check_core::Op.less { if floating { return blot_support::some(blot_backend_runtime_ir::OP_f32_lt); } return blot_support::some(blot_backend_runtime_ir::OP_i32_lt_u); }
    if op == blot_check_core::Op.less_equal { if floating { return blot_support::some(blot_backend_runtime_ir::OP_f32_le); } return blot_support::some(blot_backend_runtime_ir::OP_i32_le_u); }
    if op == blot_check_core::Op.greater { if floating { return blot_support::some(blot_backend_runtime_ir::OP_f32_gt); } return blot_support::some(blot_backend_runtime_ir::OP_i32_gt_u); }
    if op == blot_check_core::Op.greater_equal { if floating { return blot_support::some(blot_backend_runtime_ir::OP_f32_ge); } return blot_support::some(blot_backend_runtime_ir::OP_i32_ge_u); }
    if op == blot_check_core::Op.convert_u32_f32 { return blot_support::some(blot_backend_runtime_ir::OP_f32_convert_i32_u); }
    if op == blot_check_core::Op.convert_f32_u32 { return blot_support::some(blot_backend_runtime_ir::OP_i32_trunc_sat_f32_u); }
    if floating {
        if op == blot_check_core::Op.neg { return blot_support::some(blot_backend_runtime_ir::OP_f32_neg); }
        if op == blot_check_core::Op.abs { return blot_support::some(blot_backend_runtime_ir::OP_f32_abs); }
        if op == blot_check_core::Op.ceil { return blot_support::some(blot_backend_runtime_ir::OP_f32_ceil); }
        if op == blot_check_core::Op.floor { return blot_support::some(blot_backend_runtime_ir::OP_f32_floor); }
        if op == blot_check_core::Op.trunc { return blot_support::some(blot_backend_runtime_ir::OP_f32_trunc); }
        if op == blot_check_core::Op.sqrt { return blot_support::some(blot_backend_runtime_ir::OP_f32_sqrt); }
        if op == blot_check_core::Op.min { return blot_support::some(blot_backend_runtime_ir::OP_f32_min); }
        if op == blot_check_core::Op.max { return blot_support::some(blot_backend_runtime_ir::OP_f32_max); }
        if op == blot_check_core::Op.bits { return blot_support::some(blot_backend_runtime_ir::OP_i32_reinterpret_f32); }
    } else {
        if op == blot_check_core::Op.rem { return blot_support::some(blot_backend_runtime_ir::OP_i32_rem_u); }
        if op == blot_check_core::Op.bit_and { return blot_support::some(blot_backend_runtime_ir::OP_i32_and); }
        if op == blot_check_core::Op.bit_or { return blot_support::some(blot_backend_runtime_ir::OP_i32_or); }
        if op == blot_check_core::Op.bit_xor { return blot_support::some(blot_backend_runtime_ir::OP_i32_xor); }
        if op == blot_check_core::Op.shift_left { return blot_support::some(blot_backend_runtime_ir::OP_i32_shl); }
        if op == blot_check_core::Op.shift_right { return blot_support::some(blot_backend_runtime_ir::OP_i32_shr_u); }
        if op == blot_check_core::Op.from_bits { return blot_support::some(blot_backend_runtime_ir::OP_f32_reinterpret_i32); }
    }
    return blot_support::none<blot_backend_runtime_ir::Op>();
}
fn resultScalar(op: blot_check_core::Op, scalar: blot_backend_runtime_ir::Scalar) -> blot_backend_runtime_ir::Scalar {
    if op == blot_check_core::Op.equal || op == blot_check_core::Op.not_equal || op == blot_check_core::Op.less || op == blot_check_core::Op.less_equal || op == blot_check_core::Op.greater || op == blot_check_core::Op.greater_equal { return blot_backend_runtime_ir::SC_bool; }
    if op == blot_check_core::Op.convert_u32_f32 || op == blot_check_core::Op.from_bits { return blot_backend_runtime_ir::SC_f32; }
    if op == blot_check_core::Op.convert_f32_u32 || op == blot_check_core::Op.bits { return blot_backend_runtime_ir::SC_u32; }
    return scalar;
}
fn floatBits(value: f32) -> u32 {
    let values: f32[1] = [value]; let bytes = bytes_of(values);
    return bytes[0] as u32 | (bytes[1] as u32 << 8) | (bytes[2] as u32 << 16) | (bytes[3] as u32 << 24);
}
fn bitsFloat(value: u32) -> f32 {
    let image: u8[5] = [4, value as! u8, (value >> 8) as! u8, (value >> 16) as! u8, (value >> 24) as! u8];
    let values, valid = from_bytes<f32[]>(image); assert(valid && values.len == 1); return values[0];
}
fn boolean(value: bool) -> u32 { if value { return 1; } return 0; }
fn evaluate(op: blot_check_core::Op, a: Value, b: Value) -> Value, blot_error::Error {
    let selected = opcode(op, a.scalar);
    if !selected.present { return Value {}, blot_error::Error.unsupported; }
    let machine = selected.value; let x = bitsFloat(a.bits); let y = bitsFloat(b.bits); var bits: u32 = 0;
    if machine == blot_backend_runtime_ir::OP_i32_add { bits = (a.bits as u64 + b.bits as u64) as! u32; }
    else if machine == blot_backend_runtime_ir::OP_i32_sub { bits = (a.bits as u64 + 4294967296 - b.bits as u64) as! u32; }
    else if machine == blot_backend_runtime_ir::OP_i32_mul { bits = (a.bits as u64 * b.bits as u64) as! u32; }
    else if machine == blot_backend_runtime_ir::OP_i32_div_u || machine == blot_backend_runtime_ir::OP_i32_rem_u {
        if b.bits == 0 { return Value {}, blot_error::Error.integer_divide_by_zero; }
        if machine == blot_backend_runtime_ir::OP_i32_div_u { bits = a.bits / b.bits; } else { bits = a.bits % b.bits; }
    } else if machine == blot_backend_runtime_ir::OP_i32_and { bits = a.bits & b.bits; }
    else if machine == blot_backend_runtime_ir::OP_i32_or { bits = a.bits | b.bits; }
    else if machine == blot_backend_runtime_ir::OP_i32_xor { bits = a.bits ^ b.bits; }
    else if machine == blot_backend_runtime_ir::OP_i32_shl { bits = a.bits << (b.bits & 31); }
    else if machine == blot_backend_runtime_ir::OP_i32_shr_u { bits = a.bits >> (b.bits & 31); }
    else if machine == blot_backend_runtime_ir::OP_i32_eq { bits = boolean(a.bits == b.bits); }
    else if machine == blot_backend_runtime_ir::OP_i32_ne { bits = boolean(a.bits != b.bits); }
    else if machine == blot_backend_runtime_ir::OP_i32_lt_u { bits = boolean(a.bits < b.bits); }
    else if machine == blot_backend_runtime_ir::OP_i32_gt_u { bits = boolean(a.bits > b.bits); }
    else if machine == blot_backend_runtime_ir::OP_i32_le_u { bits = boolean(a.bits <= b.bits); }
    else if machine == blot_backend_runtime_ir::OP_i32_ge_u { bits = boolean(a.bits >= b.bits); }
    else if machine == blot_backend_runtime_ir::OP_f32_eq { bits = boolean(x == y); }
    else if machine == blot_backend_runtime_ir::OP_f32_ne { bits = boolean(x != y); }
    else if machine == blot_backend_runtime_ir::OP_f32_lt { bits = boolean(x < y); }
    else if machine == blot_backend_runtime_ir::OP_f32_gt { bits = boolean(x > y); }
    else if machine == blot_backend_runtime_ir::OP_f32_le { bits = boolean(x <= y); }
    else if machine == blot_backend_runtime_ir::OP_f32_ge { bits = boolean(x >= y); }
    else if machine == blot_backend_runtime_ir::OP_f32_add { bits = floatBits(x + y); }
    else if machine == blot_backend_runtime_ir::OP_f32_sub { bits = floatBits(x - y); }
    else if machine == blot_backend_runtime_ir::OP_f32_mul { bits = floatBits(x * y); }
    else if machine == blot_backend_runtime_ir::OP_f32_div { bits = floatBits(x / y); }
    else if machine == blot_backend_runtime_ir::OP_f32_abs { bits = a.bits & 0x7fffffff; }
    else if machine == blot_backend_runtime_ir::OP_f32_neg { bits = a.bits ^ 0x80000000; }
    else if machine == blot_backend_runtime_ir::OP_f32_ceil { bits = floatBits(ceil(x)); }
    else if machine == blot_backend_runtime_ir::OP_f32_floor { bits = floatBits(floor(x)); }
    else if machine == blot_backend_runtime_ir::OP_f32_trunc { bits = floatBits(trunc(x)); }
    else if machine == blot_backend_runtime_ir::OP_f32_sqrt { bits = floatBits(sqrt(x)); }
    else if machine == blot_backend_runtime_ir::OP_f32_min || machine == blot_backend_runtime_ir::OP_f32_max {
        if x != x || y != y { bits = 0x7fc00000; }
        else if x == y { if machine == blot_backend_runtime_ir::OP_f32_min { bits = a.bits | b.bits; } else { bits = a.bits & b.bits; } }
        else if (machine == blot_backend_runtime_ir::OP_f32_min && x < y) || (machine == blot_backend_runtime_ir::OP_f32_max && x > y) { bits = a.bits; }
        else { bits = b.bits; }
    } else if machine == blot_backend_runtime_ir::OP_i32_reinterpret_f32 || machine == blot_backend_runtime_ir::OP_f32_reinterpret_i32 { bits = a.bits; }
    else if machine == blot_backend_runtime_ir::OP_f32_convert_i32_u { bits = floatBits(a.bits as f32); }
    else if machine == blot_backend_runtime_ir::OP_i32_trunc_sat_f32_u {
        if x != x || x <= 0.0 { bits = 0; } else if x >= 4294967296.0 { bits = 4294967295; } else { bits = x as u32; }
    } else { return Value {}, blot_error::Error.unsupported; }
    return Value { scalar: resultScalar(op, a.scalar), bits: bits }, blot_error::Error.none;
}
fn evaluateExact(op: blot_check_core::Op, a: Value, b: Value) -> Value, blot_error::Error {
    let result, error = evaluate(op, a, b); if error != blot_error::Error.none { return result, error; }
    if result.scalar == blot_backend_runtime_ir::SC_f32 && (op == blot_check_core::Op.add || op == blot_check_core::Op.sub || op == blot_check_core::Op.mul || op == blot_check_core::Op.div || op == blot_check_core::Op.ceil || op == blot_check_core::Op.floor || op == blot_check_core::Op.trunc || op == blot_check_core::Op.sqrt || op == blot_check_core::Op.min || op == blot_check_core::Op.max) {
        let value = bitsFloat(result.bits); if value != value { return Value {}, blot_error::Error.unsupported; }
    }
    return result, blot_error::Error.none;
}
