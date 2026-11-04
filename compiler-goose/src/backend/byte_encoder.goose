// Wire encoding used by wasm. All mutable bytes belong to the caller.
namespace blot_backend_byte_encoder;
import std;
import .runtime_ir;
import .wasm_simd_ops;
import support.error;

struct Bytes { buffer: u8[>..]& }
fn init(buffer: u8[>..]&) -> Bytes { Bytes { buffer: buffer } }
fn items(bytes: Bytes&) -> const u8[:] { bytes.buffer[..] }
fn clear(bytes: Bytes&) { bytes.buffer.clear(); }
fn byte(bytes: Bytes&, value: u8) { bytes.buffer.push(value); }
fn raw(bytes: Bytes&, value: const u8[:]) { bytes.buffer.append(value); }
fn uleb(bytes: Bytes&, value: u32) {
    var remaining = value;
    loop {
        var low = (remaining & 127) as u8; remaining >>= 7;
        if remaining != 0 { low |= 128; }
        byte(bytes, low); if remaining == 0 { return; }
    }
}
fn sleb(bytes: Bytes&, value: i32) {
    var remaining = value;
    loop {
        var low = (remaining as! u32 & 127) as u8; remaining >>= 7;
        let done = (remaining == 0 && (low & 64) == 0) || (remaining == -1 && (low & 64) != 0);
        if !done { low |= 128; }
        byte(bytes, low); if done { return; }
    }
}
fn name(bytes: Bytes&, value: const u8[:]) -> blot_error::Error {
    if value.len > 4294967295 { return blot_error::Error.module_too_large; }
    uleb(bytes, value.len as u32); raw(bytes, value); return blot_error::Error.none;
}
fn section(bytes: Bytes&, id: u8, payload: const u8[:]) -> blot_error::Error {
    byte(bytes, id);
    if payload.len > 4294967295 { return blot_error::Error.module_too_large; }
    uleb(bytes, payload.len as u32); raw(bytes, payload); return blot_error::Error.none;
}
fn word(bytes: Bytes&, value: u32) {
    for index in 0..4 { byte(bytes, (value >> (index * 8)) as! u8); }
}

fn scalarCode(op: blot_backend_runtime_ir::Op) -> u8, bool {
    if op == blot_backend_runtime_ir::OP_unreachable_ { return 0x00, true; }
    if op == blot_backend_runtime_ir::OP_nop { return 0x01, true; }
    if op == blot_backend_runtime_ir::OP_block { return 0x02, true; }
    if op == blot_backend_runtime_ir::OP_loop { return 0x03, true; }
    if op == blot_backend_runtime_ir::OP_if_ { return 0x04, true; }
    if op == blot_backend_runtime_ir::OP_else_ { return 0x05, true; }
    if op == blot_backend_runtime_ir::OP_end { return 0x0b, true; }
    if op == blot_backend_runtime_ir::OP_br { return 0x0c, true; }
    if op == blot_backend_runtime_ir::OP_br_if { return 0x0d, true; }
    if op == blot_backend_runtime_ir::OP_return_ { return 0x0f, true; }
    if op == blot_backend_runtime_ir::OP_call || op == blot_backend_runtime_ir::OP_call_import { return 0x10, true; }
    if op == blot_backend_runtime_ir::OP_call_indirect { return 0x11, true; }
    if op == blot_backend_runtime_ir::OP_host_ref_get { return 0x25, true; }
    if op == blot_backend_runtime_ir::OP_host_ref_set { return 0x26, true; }
    if op == blot_backend_runtime_ir::OP_host_ref_size || op == blot_backend_runtime_ir::OP_host_ref_grow { return 0xfc, true; }
    if op == blot_backend_runtime_ir::OP_host_ref_null { return 0xd0, true; }
    if op == blot_backend_runtime_ir::OP_host_ref_is_null { return 0xd1, true; }
    if op == blot_backend_runtime_ir::OP_drop { return 0x1a, true; }
    if op == blot_backend_runtime_ir::OP_i32_select { return 0x1b, true; }
    if op == blot_backend_runtime_ir::OP_local_get { return 0x20, true; }
    if op == blot_backend_runtime_ir::OP_local_set { return 0x21, true; }
    if op == blot_backend_runtime_ir::OP_local_tee { return 0x22, true; }
    if op == blot_backend_runtime_ir::OP_global_get { return 0x23, true; }
    if op == blot_backend_runtime_ir::OP_global_set { return 0x24, true; }
    if op == blot_backend_runtime_ir::OP_i32_load { return 0x28, true; }
    if op == blot_backend_runtime_ir::OP_f32_load { return 0x2a, true; }
    if op == blot_backend_runtime_ir::OP_i32_store { return 0x36, true; }
    if op == blot_backend_runtime_ir::OP_f32_store { return 0x38, true; }
    if op == blot_backend_runtime_ir::OP_memory_size { return 0x3f, true; }
    if op == blot_backend_runtime_ir::OP_memory_grow { return 0x40, true; }
    if op == blot_backend_runtime_ir::OP_memory_copy || op == blot_backend_runtime_ir::OP_memory_fill { return 0xfc, true; }
    if op == blot_backend_runtime_ir::OP_i32_reinterpret_f32 { return 0xbc, true; }
    if op == blot_backend_runtime_ir::OP_f32_reinterpret_i32 { return 0xbe, true; }
    if op == blot_backend_runtime_ir::OP_i32_const { return 0x41, true; }
    if op == blot_backend_runtime_ir::OP_f32_const { return 0x43, true; }
    if op == blot_backend_runtime_ir::OP_i32_eqz { return 0x45, true; }
    if op == blot_backend_runtime_ir::OP_i32_eq { return 0x46, true; }
    if op == blot_backend_runtime_ir::OP_i32_ne { return 0x47, true; }
    if op == blot_backend_runtime_ir::OP_i32_lt_u { return 0x49, true; }
    if op == blot_backend_runtime_ir::OP_i32_gt_u { return 0x4b, true; }
    if op == blot_backend_runtime_ir::OP_i32_le_u { return 0x4d, true; }
    if op == blot_backend_runtime_ir::OP_i32_ge_u { return 0x4f, true; }
    if op == blot_backend_runtime_ir::OP_f32_eq { return 0x5b, true; }
    if op == blot_backend_runtime_ir::OP_f32_ne { return 0x5c, true; }
    if op == blot_backend_runtime_ir::OP_f32_lt { return 0x5d, true; }
    if op == blot_backend_runtime_ir::OP_f32_gt { return 0x5e, true; }
    if op == blot_backend_runtime_ir::OP_f32_le { return 0x5f, true; }
    if op == blot_backend_runtime_ir::OP_f32_ge { return 0x60, true; }
    if op == blot_backend_runtime_ir::OP_i32_add { return 0x6a, true; }
    if op == blot_backend_runtime_ir::OP_i32_sub { return 0x6b, true; }
    if op == blot_backend_runtime_ir::OP_i32_mul { return 0x6c, true; }
    if op == blot_backend_runtime_ir::OP_i32_div_u { return 0x6e, true; }
    if op == blot_backend_runtime_ir::OP_i32_rem_u { return 0x70, true; }
    if op == blot_backend_runtime_ir::OP_i32_and { return 0x71, true; }
    if op == blot_backend_runtime_ir::OP_i32_or { return 0x72, true; }
    if op == blot_backend_runtime_ir::OP_i32_xor { return 0x73, true; }
    if op == blot_backend_runtime_ir::OP_i32_shl { return 0x74, true; }
    if op == blot_backend_runtime_ir::OP_i32_shr_u { return 0x76, true; }
    if op == blot_backend_runtime_ir::OP_i32_clz { return 0x67, true; }
    if op == blot_backend_runtime_ir::OP_i32_ctz { return 0x68, true; }
    if op == blot_backend_runtime_ir::OP_f32_abs { return 0x8b, true; }
    if op == blot_backend_runtime_ir::OP_f32_neg { return 0x8c, true; }
    if op == blot_backend_runtime_ir::OP_f32_ceil { return 0x8d, true; }
    if op == blot_backend_runtime_ir::OP_f32_floor { return 0x8e, true; }
    if op == blot_backend_runtime_ir::OP_f32_trunc { return 0x8f, true; }
    if op == blot_backend_runtime_ir::OP_f32_sqrt { return 0x91, true; }
    if op == blot_backend_runtime_ir::OP_f32_add { return 0x92, true; }
    if op == blot_backend_runtime_ir::OP_f32_sub { return 0x93, true; }
    if op == blot_backend_runtime_ir::OP_f32_mul { return 0x94, true; }
    if op == blot_backend_runtime_ir::OP_f32_div { return 0x95, true; }
    if op == blot_backend_runtime_ir::OP_f32_min { return 0x96, true; }
    if op == blot_backend_runtime_ir::OP_f32_max { return 0x97, true; }
    if op == blot_backend_runtime_ir::OP_f32_convert_i32_u { return 0xb3, true; }
    if op == blot_backend_runtime_ir::OP_i32_trunc_sat_f32_u { return 0xfc, true; }
    return 0, false;
}
fn encodeInstruction(bytes: Bytes&, inst: blot_backend_runtime_ir::Instruction, functions: i64, table_slots: i64, globals: i64, signatures: i64, imports: u32) -> blot_error::Error {
    if inst.table_reference && (inst.op != blot_backend_runtime_ir::OP_i32_const || inst.operand >= table_slots) { return blot_error::Error.invalid_function_reference; }
    if inst.op == blot_backend_runtime_ir::OP_ownership { return blot_error::Error.none; }
    let simd, is_simd = blot_backend_wasm_simd_ops::code(inst.op);
    if is_simd {
        byte(bytes, 0xfd); uleb(bytes, simd);
        if inst.op == blot_backend_runtime_ir::OP_v128_load || inst.op == blot_backend_runtime_ir::OP_v128_store { uleb(bytes, 2); uleb(bytes, inst.operand); }
        if inst.op == blot_backend_runtime_ir::OP_i32x4_replace_lane || inst.op == blot_backend_runtime_ir::OP_i32x4_extract_lane || inst.op == blot_backend_runtime_ir::OP_f32x4_extract_lane || inst.op == blot_backend_runtime_ir::OP_f32x4_replace_lane {
            if inst.operand >= 4 { return blot_error::Error.module_too_large; }
            byte(bytes, inst.operand as u8);
        }
        if inst.op == blot_backend_runtime_ir::OP_i8x16_shuffle {
            if inst.operand >= 4096 { return blot_error::Error.module_too_large; }
            for lane in 0..4 {
                let selected = ((inst.operand >> (lane * 3)) & 7) as u8;
                for index in 0..4 { byte(bytes, selected * 4 + index as u8); }
            }
        }
        return blot_error::Error.none;
    }
    let code, found = scalarCode(inst.op);
    if !found { return blot_error::Error.module_too_large; }
    byte(bytes, code);
    let op = inst.op;
    if op == blot_backend_runtime_ir::OP_block || op == blot_backend_runtime_ir::OP_loop || op == blot_backend_runtime_ir::OP_if_ {
        var value: u8 = 0x40; if inst.operand != 0 { value = inst.operand as u8; } byte(bytes, value);
    } else if op == blot_backend_runtime_ir::OP_br || op == blot_backend_runtime_ir::OP_br_if || op == blot_backend_runtime_ir::OP_local_get || op == blot_backend_runtime_ir::OP_local_set || op == blot_backend_runtime_ir::OP_local_tee {
        uleb(bytes, inst.operand);
    } else if op == blot_backend_runtime_ir::OP_call {
        if inst.operand >= functions { return blot_error::Error.invalid_function_reference; }
        uleb(bytes, inst.operand + imports);
    } else if op == blot_backend_runtime_ir::OP_call_import {
        if inst.operand >= imports { return blot_error::Error.invalid_function_reference; }
        uleb(bytes, inst.operand);
    } else if op == blot_backend_runtime_ir::OP_call_indirect {
        if inst.operand >= signatures { return blot_error::Error.invalid_function_reference; }
        uleb(bytes, inst.operand); byte(bytes, 0);
    } else if op == blot_backend_runtime_ir::OP_global_get || op == blot_backend_runtime_ir::OP_global_set {
        if inst.operand >= globals { return blot_error::Error.invalid_global_reference; }
        uleb(bytes, inst.operand);
    } else if op == blot_backend_runtime_ir::OP_i32_const { sleb(bytes, inst.operand as! i32); }
    else if op == blot_backend_runtime_ir::OP_f32_const { word(bytes, inst.operand); }
    else if op == blot_backend_runtime_ir::OP_i32_trunc_sat_f32_u { byte(bytes, 1); }
    else if op == blot_backend_runtime_ir::OP_i32_load || op == blot_backend_runtime_ir::OP_f32_load || op == blot_backend_runtime_ir::OP_i32_store || op == blot_backend_runtime_ir::OP_f32_store { uleb(bytes, 2); uleb(bytes, inst.operand); }
    else if op == blot_backend_runtime_ir::OP_memory_size || op == blot_backend_runtime_ir::OP_memory_grow { byte(bytes, 0); }
    else if op == blot_backend_runtime_ir::OP_memory_copy { raw(bytes, [10, 0, 0]); }
    else if op == blot_backend_runtime_ir::OP_memory_fill { raw(bytes, [11, 0]); }
    else if op == blot_backend_runtime_ir::OP_host_ref_get || op == blot_backend_runtime_ir::OP_host_ref_set { uleb(bytes, 1); }
    else if op == blot_backend_runtime_ir::OP_host_ref_size { raw(bytes, [16, 1]); }
    else if op == blot_backend_runtime_ir::OP_host_ref_grow { raw(bytes, [15, 1]); }
    else if op == blot_backend_runtime_ir::OP_host_ref_null { byte(bytes, 0x6f); }
    return blot_error::Error.none;
}
fn encodeLocals(bytes: Bytes&, locals: const blot_backend_runtime_ir::ValueType[:], observed: u32 = 0) {
    var groups: u32 = 0; var previous: blot_backend_runtime_ir::ValueType = 0;
    for local in locals { if previous != local { groups++; } previous = local; }
    if observed != 0 { groups++; }
    uleb(bytes, groups);
    var start = 0;
    while start < locals.len {
        var end = start + 1; while end < locals.len && locals[end] == locals[start] { end++; }
        uleb(bytes, (end - start) as u32); byte(bytes, locals[start]); start = end;
    }
    if observed != 0 { uleb(bytes, observed); byte(bytes, blot_backend_runtime_ir::VT_i32); }
}
