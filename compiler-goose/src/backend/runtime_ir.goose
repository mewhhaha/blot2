// Typed stack IR. Integer tags preserve source and transport identities.
namespace blot_backend_runtime_ir;
import std;
import support.error;

type ValueType = u8;
let VT_i32: ValueType = 0x7f;
let VT_f32: ValueType = 0x7d;
let VT_v128: ValueType = 0x7b;
let VT_externref: ValueType = 0x6f;
let VT_none: ValueType = 0x40;
type Scalar = u8;
let SC_unit: Scalar = 0;
let SC_u32: Scalar = 1;
let SC_bool: Scalar = 2;
let SC_f32: Scalar = 3;
let SC_array_u32: Scalar = 5;
let SC_array_f32: Scalar = 6;
let SC_pointer: Scalar = 7;
type Role = u8;
let ROLE_unknown: Role = 0;
let ROLE_scalar: Role = 1;
let ROLE_reference: Role = 2;
let ROLE_value: Role = 3;
fn machine(value: Scalar) -> ValueType {
    if value == SC_f32 { return VT_f32; }
    return VT_i32;
}
fn role(value: Scalar) -> Role {
    if value == SC_array_u32 || value == SC_array_f32 || value == SC_pointer { return ROLE_reference; }
    return ROLE_scalar;
}

type Op = u8;
let OP_unreachable_: Op = 0;
let OP_nop: Op = 1;
let OP_block: Op = 2;
let OP_loop: Op = 3;
let OP_if_: Op = 4;
let OP_else_: Op = 5;
let OP_end: Op = 6;
let OP_br: Op = 7;
let OP_br_if: Op = 8;
let OP_return_: Op = 9;
let OP_call: Op = 10;
let OP_call_import: Op = 11;
let OP_call_indirect: Op = 12;
let OP_host_ref_get: Op = 13;
let OP_host_ref_set: Op = 14;
let OP_host_ref_size: Op = 15;
let OP_host_ref_grow: Op = 16;
let OP_host_ref_null: Op = 17;
let OP_host_ref_is_null: Op = 18;
let OP_drop: Op = 19;
let OP_local_get: Op = 20;
let OP_local_set: Op = 21;
let OP_local_tee: Op = 22;
let OP_global_get: Op = 23;
let OP_global_set: Op = 24;
let OP_i32_load: Op = 25;
let OP_f32_load: Op = 26;
let OP_i32_store: Op = 27;
let OP_f32_store: Op = 28;
let OP_memory_size: Op = 29;
let OP_memory_grow: Op = 30;
let OP_memory_copy: Op = 31;
let OP_memory_fill: Op = 32;
let OP_i32_reinterpret_f32: Op = 33;
let OP_f32_reinterpret_i32: Op = 34;
let OP_i32_const: Op = 35;
let OP_f32_const: Op = 36;
let OP_i32_eqz: Op = 37;
let OP_i32_eq: Op = 38;
let OP_i32_ne: Op = 39;
let OP_i32_lt_u: Op = 40;
let OP_i32_gt_u: Op = 41;
let OP_i32_le_u: Op = 42;
let OP_i32_ge_u: Op = 43;
let OP_f32_eq: Op = 44;
let OP_f32_ne: Op = 45;
let OP_f32_lt: Op = 46;
let OP_f32_gt: Op = 47;
let OP_f32_le: Op = 48;
let OP_f32_ge: Op = 49;
let OP_i32_add: Op = 50;
let OP_i32_sub: Op = 51;
let OP_i32_mul: Op = 52;
let OP_i32_div_u: Op = 53;
let OP_i32_rem_u: Op = 54;
let OP_i32_and: Op = 55;
let OP_i32_or: Op = 56;
let OP_i32_xor: Op = 57;
let OP_i32_shl: Op = 58;
let OP_i32_shr_u: Op = 59;
let OP_i32_clz: Op = 60;
let OP_i32_ctz: Op = 61;
let OP_f32_abs: Op = 62;
let OP_f32_neg: Op = 63;
let OP_f32_ceil: Op = 64;
let OP_f32_floor: Op = 65;
let OP_f32_trunc: Op = 66;
let OP_f32_sqrt: Op = 67;
let OP_f32_add: Op = 68;
let OP_f32_sub: Op = 69;
let OP_f32_mul: Op = 70;
let OP_f32_div: Op = 71;
let OP_f32_min: Op = 72;
let OP_f32_max: Op = 73;
let OP_i32_trunc_sat_f32_u: Op = 74;
let OP_f32_convert_i32_u: Op = 75;
let OP_v128_load: Op = 76;
let OP_v128_store: Op = 77;
let OP_i32x4_splat: Op = 78;
let OP_f32x4_splat: Op = 79;
let OP_i32x4_replace_lane: Op = 80;
let OP_i32x4_extract_lane: Op = 81;
let OP_f32x4_extract_lane: Op = 82;
let OP_i32x4_add: Op = 83;
let OP_i32x4_sub: Op = 84;
let OP_i32x4_mul: Op = 85;
let OP_v128_and: Op = 86;
let OP_v128_or: Op = 87;
let OP_v128_xor: Op = 88;
let OP_f32x4_abs: Op = 89;
let OP_f32x4_neg: Op = 90;
let OP_f32x4_ceil: Op = 91;
let OP_f32x4_floor: Op = 92;
let OP_f32x4_trunc: Op = 93;
let OP_f32x4_sqrt: Op = 94;
let OP_f32x4_add: Op = 95;
let OP_f32x4_sub: Op = 96;
let OP_f32x4_mul: Op = 97;
let OP_f32x4_div: Op = 98;
let OP_f32x4_convert_i32x4_u: Op = 99;
let OP_i32x4_trunc_sat_f32x4_u: Op = 100;
let OP_f32x4_convert_i32x4_s: Op = 101;
let OP_i32x4_trunc_sat_f32x4_s: Op = 102;
let OP_f32x4_replace_lane: Op = 103;
let OP_i8x16_shuffle: Op = 104;
let OP_i32x4_shl: Op = 105;
let OP_i32x4_shr_s: Op = 106;
let OP_i32x4_shr_u: Op = 107;
let OP_i32x4_min_u: Op = 108;
let OP_i32x4_max_u: Op = 109;
let OP_f32x4_pmin: Op = 110;
let OP_f32x4_pmax: Op = 111;
let OP_i32x4_eq: Op = 112;
let OP_i32x4_ne: Op = 113;
let OP_i32x4_lt_u: Op = 114;
let OP_i32x4_gt_u: Op = 115;
let OP_i32x4_le_u: Op = 116;
let OP_i32x4_ge_u: Op = 117;
let OP_f32x4_eq: Op = 118;
let OP_f32x4_ne: Op = 119;
let OP_f32x4_lt: Op = 120;
let OP_f32x4_gt: Op = 121;
let OP_f32x4_le: Op = 122;
let OP_f32x4_ge: Op = 123;
let OP_v128_not: Op = 124;
let OP_v128_andnot: Op = 125;
let OP_v128_bitselect: Op = 126;
let OP_v128_any_true: Op = 127;
let OP_i32x4_all_true: Op = 128;
let OP_f32x4_relaxed_madd: Op = 129;
let OP_f32x4_relaxed_nmadd: Op = 130;
let OP_ownership: Op = 131;
let OP_wide_layouts: Op = 132;
let OP_resource_retire: Op = 133;
let OP_i32_select: Op = 134;

// Table slices are IDs, never pointers into a growing allocation.
struct Range { start: i64 = 0, len: i64 = 0 }
type FunctionId = u32;
type LocalId = u32;
type SignatureId = u32;
type TableKind = u8;
let TABLE_unknown: TableKind = 0;
let TABLE_callable: TableKind = 1;
struct Instruction {
    operand: u32 = 0, op: Op = OP_nop,
    table_reference: bool = false, table_kind: TableKind = TABLE_unknown,
    origin: u32 = 0,
}
fn instruction(op: Op, operand: u32 = 0) -> Instruction { Instruction { operand: operand, op: op } }
fn callee(value: Instruction) -> FunctionId { assert(value.op == OP_call); return value.operand; }
fn local(value: Instruction) -> LocalId {
    assert(value.op == OP_local_get || value.op == OP_local_set || value.op == OP_local_tee);
    return value.operand;
}
fn signatureId(value: Instruction) -> SignatureId { assert(value.op == OP_call_indirect); return value.operand; }
fn packed(value: Instruction) -> u64 {
    assert(value.origin < 2097152 && value.table_kind < 4);
    var result = value.operand as u64 | (value.op as u64 << 32) | (value.table_kind as u64 << 41) | (value.origin as u64 << 43);
    if value.table_reference { result |= 1 as u64 << 40; }
    return result;
}
fn unpackInstruction(value: u64) -> Instruction {
    return Instruction { operand: value as! u32, op: (value >> 32) as! u8,
        table_reference: (value & (1 as u64 << 40)) != 0, table_kind: ((value >> 41) & 3) as u8,
        origin: (value >> 43) as u32 , ..};
}

let words_per_chunk: i64 = 13;
let max_annotations: i64 = 17;
type OwnershipKind = u8;
let OWN_words: OwnershipKind = 0;
let OWN_rest: OwnershipKind = 1;
let OWN_scope: OwnershipKind = 2;
let OWN_call_result: OwnershipKind = 3;
struct Ownership { kind: OwnershipKind = OWN_words, chunk: u8 = 0, roles: u32 = 0 }
fn pack(value: Ownership) -> u32 {
    assert(value.kind < 4 && value.chunk < 16 && value.roles < 67108864);
    return value.kind as u32 | (value.chunk as u32 << 2) | (value.roles << 6);
}
fn ownership(value: u32) -> Ownership {
    return Ownership { kind: (value & 3) as u8, chunk: ((value >> 2) & 15) as u8, roles: value >> 6 , ..};
}
fn relocated(value: Ownership, base: u32) -> Ownership {
    var result = value;
    if value.kind == OWN_rest && value.chunk == 8 { result.roles += base; return result; }
    if value.kind != OWN_scope { return result; }
    if value.chunk == 2 || value.chunk == 3 || value.chunk == 5 || value.chunk == 6 { result.roles += base; }
    if value.chunk == 4 { result.roles = (value.roles & 8191) + base + ((value.roles >> 13) + base) * 8192; }
    return result;
}
fn ownershipRole(value: Ownership, index: i64) -> Role { return ((value.roles >> (index * 2)) & 3) as u8; }
fn explicitWords(value: Ownership) -> i64 { value.roles >> 2 }
fn wordRole(run: const Instruction[:], word: i64) -> Role {
    if run.len == 0 { return ROLE_unknown; }
    let terminator = ownership(run[run.len - 1].operand);
    if terminator.kind != OWN_rest { return ROLE_unknown; }
    if word >= explicitWords(terminator) { return ownershipRole(terminator, 0); }
    for inst in run[..run.len - 1] {
        let annotation = ownership(inst.operand);
        let first = annotation.chunk * words_per_chunk;
        if annotation.kind == OWN_words && word >= first && word < first + words_per_chunk { return ownershipRole(annotation, word - first); }
    }
    return ROLE_unknown;
}
fn callResult(value: Role) -> Instruction {
    return instruction(OP_ownership, pack(Ownership { kind: OWN_call_result, roles: value , ..}));
}
fn indirectResult(instructions: const Instruction[:], at: i64) -> Role {
    if at == 0 || at >= instructions.len || instructions[at].op != OP_call_indirect || instructions[at - 1].op != OP_ownership { return ROLE_unknown; }
    let annotation = ownership(instructions[at - 1].operand);
    if annotation.kind != OWN_call_result || annotation.chunk != 0 || annotation.roles > ROLE_value { return ROLE_unknown; }
    return annotation.roles as Role;
}
fn annotations(words: const Role[:], rest: Role, out: Instruction[17]&) -> i64 {
    let chunks = (words.len + words_per_chunk - 1) / words_per_chunk;
    var count = 0;
    var limit = chunks; if limit > 16 { limit = 16; }
    for chunk in 0..limit {
        let start = chunk * words_per_chunk;
        var length = words.len - start; if length > words_per_chunk { length = words_per_chunk; }
        var roles: u32 = 0;
        for index in 0..length { roles |= words[start + index] as u32 << (index * 2); }
        out[count] = instruction(OP_ownership, pack(Ownership { kind: OWN_words, chunk: chunk as u8, roles: roles , ..}));
        count++;
    }
    var explicit = words.len; if explicit > 16 * words_per_chunk { explicit = 16 * words_per_chunk; }
    var remaining = rest; if chunks > 16 { remaining = ROLE_unknown; }
    out[count] = instruction(OP_ownership, pack(Ownership { kind: OWN_rest, roles: (explicit as u32 << 2) | remaining , ..}));
    return count + 1;
}
fn allocationAnnotations(instructions: const Instruction[:], at: i64) -> const Instruction[:] {
    if at < 2 || at > instructions.len || instructions[at - 1].op != OP_i32_const { return instructions[..0]; }
    let end = at - 1;
    if instructions[end - 1].op != OP_ownership { return instructions[..0]; }
    let terminator = ownership(instructions[end - 1].operand);
    if terminator.kind != OWN_rest || terminator.chunk != 0 { return instructions[..0]; }
    var start = end - 1;
    if start == 0 || instructions[start - 1].op != OP_ownership { return instructions[start..end]; }
    let highest = ownership(instructions[start - 1].operand);
    if highest.kind != OWN_words { return instructions[start..end]; }
    var chunk = highest.chunk;
    loop {
        if start == 0 || instructions[start - 1].op != OP_ownership { return instructions[..0]; }
        let annotation = ownership(instructions[start - 1].operand);
        if annotation.kind != OWN_words || annotation.chunk != chunk { return instructions[..0]; }
        start--;
        if chunk == 0 { return instructions[start..end]; }
        chunk--;
    }
}
fn staticConstructor(instructions: const Instruction[:], at: i64) -> u32, bool {
    if at < 4 || at >= instructions.len || instructions[at].op != OP_i32_const || instructions[at].table_reference { return 0, false; }
    let run = instructions[at - 4..at];
    for inst in run { if inst.op != OP_ownership { return 0, false; } }
    let low = ownership(run[0].operand); let high = ownership(run[1].operand);
    let words = ownership(run[2].operand); let rest = ownership(run[3].operand);
    if low.kind != OWN_words || low.chunk != 14 || high.kind != OWN_words || high.chunk != 15 || high.roles >= 64 ||
       words.kind != OWN_words || words.chunk != 0 || words.roles != ROLE_scalar + ROLE_reference as u32 * 4 ||
       rest.kind != OWN_rest || rest.chunk != 15 || rest.roles != 8 { return 0, false; }
    return low.roles | (high.roles << 26), true;
}
fn codeLength(instructions: const Instruction[:]) -> i64 {
    var count = 0; for inst in instructions { if inst.op != OP_ownership { count++; } } return count;
}
struct Signature { parameters: Range, result: ValueType = VT_none }
let unknown_provider: u8 = 255;
let no_provider: u8 = 254;
struct Function {
    parameters: Range, result: ValueType = VT_none, result_role: Role = ROLE_unknown,
    entry: bool = false, provider_parameter: u8 = unknown_provider,
    callable_layout: u32 = 0, signature: u32 = 0, parameter_roles: u64 = 0,
    annotations: u32 = 0, locals: Range, instructions: Range,
    // Detached views borrow source bodies until their first typed mutation.
    // These fields are native ownership metadata, excluded from every wire view.
    borrowed_body: bool = false,borrowed_locals: const ValueType[:] = [],borrowed_instructions: const Instruction[:] = [],
}
fn codeLength(function: Function) -> i64 { function.instructions.len - function.annotations }
fn parameterRole(function: Function, index: i64) -> Role {
    if index >= 32 { return ROLE_unknown; }
    return ((function.parameter_roles >> (index * 2)) & 3) as Role;
}
fn validProviderParameter<M>(module: M&, function: Function) -> bool {
    let index = function.provider_parameter;
    if index == unknown_provider || index == no_provider { return true; }
    return index < function.parameters.len && module.types[function.parameters.start + index] == VT_i32 && parameterRole(function, index) == ROLE_reference;
}
fn packParameterRoles(roles: const Role[:]) -> u64 {
    var result: u64 = 0;
    var count = roles.len; if count > 32 { count = 32; }
    for index in 0..count { result |= roles[index] as u64 << (index * 2); }
    return result;
}
struct Body { locals: Range, instructions: Range }
struct BodyBuffer { locals: ValueType[>..<]&, instructions: Instruction[>..<]& }
fn emit(body: BodyBuffer&, op: Op, operand: u32 = 0) { body.instructions.push(instruction(op, operand)); }

type Effect = u8;
let EFFECT_pure: Effect = 0;
let EFFECT_local: Effect = 1;
let EFFECT_global: Effect = 2;
let EFFECT_read: Effect = 3;
let EFFECT_write: Effect = 4;
let EFFECT_memory: Effect = 5;
let EFFECT_host: Effect = 6;
let EFFECT_call: Effect = 7;
let EFFECT_control: Effect = 8;
let EFFECT_trap: Effect = 9;
struct Contract {
    inputs: ValueType[3] = [VT_none, VT_none, VT_none], arity: i64 = 0,
    result: ValueType = VT_none, effect: Effect = EFFECT_pure,
    bytes: u8 = 0, may_trap: bool = false,
}
fn signature(inputs: const ValueType[:], result: ValueType, effect: Effect) -> Contract {
    var value = Contract { arity: inputs.len, result: result, effect: effect , ..};
    for ty, index in inputs { value.inputs[index] = ty; }
    return value;
}
fn memory(value: ValueType, store: bool) -> Contract {
    var result = Contract { inputs: [VT_i32, VT_none, VT_none], arity: 1, result: value,
        effect: EFFECT_read, bytes: 4, may_trap: true , ..};
    if store { result.inputs[1] = value; result.arity = 2; result.result = VT_none; result.effect = EFFECT_write; }
    if value == VT_v128 { result.bytes = 16; }
    return result;
}
fn fixed(op: Op) -> Contract {
    if op == OP_unreachable_ { return Contract { effect: EFFECT_trap, may_trap: true , ..}; }
    if op == OP_nop || op == OP_ownership { return Contract {..}; }
    if op == OP_resource_retire { return Contract { effect: EFFECT_host, may_trap: true , ..}; }
    if op == OP_block || op == OP_loop || op == OP_else_ || op == OP_end || op == OP_br || op == OP_return_ { return Contract { effect: EFFECT_control , ..}; }
    if op == OP_if_ || op == OP_br_if { return signature([VT_i32], VT_none, EFFECT_control); }
    if op == OP_call || op == OP_call_import || op == OP_call_indirect { return Contract { effect: EFFECT_call, may_trap: true , ..}; }
    if op == OP_local_get { return Contract { effect: EFFECT_local , ..}; }
    if op == OP_global_get { return Contract { effect: EFFECT_global , ..}; }
    if op == OP_local_set || op == OP_local_tee { return Contract { arity: 1, effect: EFFECT_local , ..}; }
    if op == OP_global_set { return Contract { arity: 1, effect: EFFECT_global , ..}; }
    if op == OP_drop { return Contract { arity: 1 , ..}; }
    if op == OP_host_ref_get { return Contract { inputs: [VT_i32, VT_none, VT_none], arity: 1, result: VT_externref, effect: EFFECT_host, may_trap: true , ..}; }
    if op == OP_host_ref_set { return Contract { inputs: [VT_i32, VT_externref, VT_none], arity: 2, effect: EFFECT_host, may_trap: true , ..}; }
    if op == OP_host_ref_grow { return signature([VT_externref, VT_i32], VT_i32, EFFECT_host); }
    if op == OP_host_ref_size { return signature([], VT_i32, EFFECT_host); }
    if op == OP_host_ref_null { return signature([], VT_externref, EFFECT_pure); }
    if op == OP_host_ref_is_null { return signature([VT_externref], VT_i32, EFFECT_pure); }
    if op == OP_i32_load { return memory(VT_i32, false); }
    if op == OP_f32_load { return memory(VT_f32, false); }
    if op == OP_v128_load { return memory(VT_v128, false); }
    if op == OP_i32_store { return memory(VT_i32, true); }
    if op == OP_f32_store { return memory(VT_f32, true); }
    if op == OP_v128_store { return memory(VT_v128, true); }
    if op == OP_memory_size { return signature([], VT_i32, EFFECT_memory); }
    if op == OP_memory_grow { return signature([VT_i32], VT_i32, EFFECT_memory); }
    if op == OP_memory_copy || op == OP_memory_fill { return Contract { inputs: [VT_i32, VT_i32, VT_i32], arity: 3, effect: EFFECT_write, may_trap: true , ..}; }
    if op == OP_i32_const || op == OP_wide_layouts { return signature([], VT_i32, EFFECT_pure); }
    if op == OP_f32_const { return signature([], VT_f32, EFFECT_pure); }
    if op == OP_i32_eqz || op == OP_i32_clz || op == OP_i32_ctz { return signature([VT_i32], VT_i32, EFFECT_pure); }
    if op == OP_i32_select { return signature([VT_i32, VT_i32, VT_i32], VT_i32, EFFECT_pure); }
    if op == OP_i32_eq || op == OP_i32_ne || op == OP_i32_lt_u || op == OP_i32_gt_u || op == OP_i32_le_u || op == OP_i32_ge_u ||
       op == OP_i32_add || op == OP_i32_sub || op == OP_i32_mul || op == OP_i32_and || op == OP_i32_or || op == OP_i32_xor || op == OP_i32_shl || op == OP_i32_shr_u {
        return signature([VT_i32, VT_i32], VT_i32, EFFECT_pure);
    }
    if op == OP_i32_div_u || op == OP_i32_rem_u { return Contract { inputs: [VT_i32, VT_i32, VT_none], arity: 2, result: VT_i32, may_trap: true , ..}; }
    if op == OP_f32_eq || op == OP_f32_ne || op == OP_f32_lt || op == OP_f32_gt || op == OP_f32_le || op == OP_f32_ge { return signature([VT_f32, VT_f32], VT_i32, EFFECT_pure); }
    if op == OP_f32_add || op == OP_f32_sub || op == OP_f32_mul || op == OP_f32_div || op == OP_f32_min || op == OP_f32_max { return signature([VT_f32, VT_f32], VT_f32, EFFECT_pure); }
    if op == OP_f32_abs || op == OP_f32_neg || op == OP_f32_ceil || op == OP_f32_floor || op == OP_f32_trunc || op == OP_f32_sqrt { return signature([VT_f32], VT_f32, EFFECT_pure); }
    if op == OP_i32_reinterpret_f32 || op == OP_i32_trunc_sat_f32_u { return signature([VT_f32], VT_i32, EFFECT_pure); }
    if op == OP_f32_reinterpret_i32 || op == OP_f32_convert_i32_u { return signature([VT_i32], VT_f32, EFFECT_pure); }
    if op == OP_i32x4_splat { return signature([VT_i32], VT_v128, EFFECT_pure); }
    if op == OP_f32x4_splat { return signature([VT_f32], VT_v128, EFFECT_pure); }
    if op == OP_i32x4_replace_lane || op == OP_i32x4_shl || op == OP_i32x4_shr_s || op == OP_i32x4_shr_u { return signature([VT_v128, VT_i32], VT_v128, EFFECT_pure); }
    if op == OP_f32x4_replace_lane { return signature([VT_v128, VT_f32], VT_v128, EFFECT_pure); }
    if op == OP_i32x4_extract_lane || op == OP_v128_any_true || op == OP_i32x4_all_true { return signature([VT_v128], VT_i32, EFFECT_pure); }
    if op == OP_f32x4_extract_lane { return signature([VT_v128], VT_f32, EFFECT_pure); }
    if op == OP_f32x4_abs || op == OP_f32x4_neg || op == OP_f32x4_ceil || op == OP_f32x4_floor || op == OP_f32x4_trunc || op == OP_f32x4_sqrt ||
       op == OP_f32x4_convert_i32x4_u || op == OP_i32x4_trunc_sat_f32x4_u || op == OP_f32x4_convert_i32x4_s || op == OP_i32x4_trunc_sat_f32x4_s || op == OP_v128_not { return signature([VT_v128], VT_v128, EFFECT_pure); }
    if op == OP_v128_bitselect || op == OP_f32x4_relaxed_madd || op == OP_f32x4_relaxed_nmadd { return signature([VT_v128, VT_v128, VT_v128], VT_v128, EFFECT_pure); }
    assert(op == OP_i32x4_add || op == OP_i32x4_sub || op == OP_i32x4_mul || op == OP_v128_and || op == OP_v128_or || op == OP_v128_xor ||
        op == OP_f32x4_add || op == OP_f32x4_sub || op == OP_f32x4_mul || op == OP_f32x4_div || op == OP_i8x16_shuffle || op == OP_i32x4_min_u || op == OP_i32x4_max_u ||
        op == OP_f32x4_pmin || op == OP_f32x4_pmax || op == OP_i32x4_eq || op == OP_i32x4_ne || op == OP_i32x4_lt_u || op == OP_i32x4_gt_u || op == OP_i32x4_le_u || op == OP_i32x4_ge_u ||
        op == OP_f32x4_eq || op == OP_f32x4_ne || op == OP_f32x4_lt || op == OP_f32x4_gt || op == OP_f32x4_le || op == OP_f32x4_ge || op == OP_v128_andnot);
    return signature([VT_v128, VT_v128], VT_v128, EFFECT_pure);
}

type CallOwnership = u8;
let CALL_unknown: CallOwnership = 0;
let CALL_allocate: CallOwnership = 1;
let CALL_allocate_scalar: CallOwnership = 2;
let CALL_allocate_typed: CallOwnership = 3;
let CALL_allocate_shaped: CallOwnership = 4;
let CALL_allocate_cohort: CallOwnership = 5;
let CALL_allocate_region: CallOwnership = 6;
let CALL_borrow_region: CallOwnership = 7;
let CALL_release: CallOwnership = 8;
let CALL_collect: CallOwnership = 9;
struct Call { parameters: Range, result: ValueType, selector: bool = false, ownership: CallOwnership = CALL_unknown }
fn call<M>(module: M&, inst: Instruction) -> Call {
    if inst.op == OP_call {
        let function = module.functions[callee(inst)];
        var result = Call { parameters: function.parameters, result: function.result , ..};
        if module.arena.present {
            let arena = module.arena.value;
            if inst.operand == arena.allocate { result.ownership = CALL_allocate; }
            if inst.operand == arena.allocate_scalar { result.ownership = CALL_allocate_scalar; }
            if inst.operand == arena.allocate_typed || inst.operand == arena.root_allocate { result.ownership = CALL_allocate_typed; }
            if inst.operand == arena.allocate_shaped || inst.operand == arena.root_allocate_shaped { result.ownership = CALL_allocate_shaped; }
            if inst.operand == arena.recycle { result.ownership = CALL_release; }
            if inst.operand == arena.reset || inst.operand == arena.cycle_collect || inst.operand == arena.cycle_safe { result.ownership = CALL_collect; }
        }
        if module.fixture_helpers_present {
            for helper in module.fixture_helpers { if inst.operand == helper { result.ownership = CALL_collect; } }
        }
        if module.regions.present {
            if inst.operand == module.regions.value.runtime.frame_allocate { result.ownership = CALL_allocate_region; }
            if inst.operand == module.regions.value.runtime.member_at { result.ownership = CALL_borrow_region; }
        }
        if module.cohorts.present && inst.operand == module.cohorts.value.allocate { result.ownership = CALL_allocate_cohort; }
        return result;
    }
    assert(inst.op == OP_call_indirect || inst.op == OP_call_import);
    var id = inst.operand;
    if inst.op == OP_call_import { id = module.imports[inst.operand].signature; }
    let callee = module.signatures[id];
    return Call { parameters: callee.parameters, result: callee.result, selector: inst.op == OP_call_indirect , ..};
}
fn contract<M>(module: M&, function: Function, inst: Instruction) -> Contract {
    var result = fixed(inst.op);
    if inst.op == OP_call || inst.op == OP_call_import || inst.op == OP_call_indirect {
        let callee = call(module, inst); result.arity = callee.parameters.len; if callee.selector { result.arity++; } result.result = callee.result;
    } else if inst.op == OP_local_get || inst.op == OP_local_set || inst.op == OP_local_tee {
        let id = local(inst); var ty: ValueType = VT_none;
        if id < function.parameters.len { ty = module.types[function.parameters.start + id]; }
        else { ty = module.types[function.locals.start + id - function.parameters.len]; }
        if inst.op != OP_local_get { result.inputs[0] = ty; }
        if inst.op != OP_local_set { result.result = ty; }
    } else if inst.op == OP_global_get || inst.op == OP_global_set {
        let ty = machine(module.globals[inst.operand].scalar);
        if inst.op == OP_global_get { result.result = ty; } else { result.inputs[0] = ty; }
    } else if inst.op == OP_return_ {
        result.inputs[0] = function.result; result.arity = 0; if function.result != VT_none { result.arity = 1; }
    }
    return result;
}
fn lift(op: Op) -> Op, bool {
    if op == OP_i32_add { return OP_i32x4_add, true; }
    if op == OP_i32_sub { return OP_i32x4_sub, true; }
    if op == OP_i32_mul { return OP_i32x4_mul, true; }
    if op == OP_i32_and { return OP_v128_and, true; }
    if op == OP_i32_or { return OP_v128_or, true; }
    if op == OP_i32_xor { return OP_v128_xor, true; }
    if op == OP_f32_abs { return OP_f32x4_abs, true; }
    if op == OP_f32_neg { return OP_f32x4_neg, true; }
    if op == OP_f32_ceil { return OP_f32x4_ceil, true; }
    if op == OP_f32_floor { return OP_f32x4_floor, true; }
    if op == OP_f32_trunc { return OP_f32x4_trunc, true; }
    if op == OP_f32_sqrt { return OP_f32x4_sqrt, true; }
    if op == OP_f32_add { return OP_f32x4_add, true; }
    if op == OP_f32_sub { return OP_f32x4_sub, true; }
    if op == OP_f32_mul { return OP_f32x4_mul, true; }
    if op == OP_f32_div { return OP_f32x4_div, true; }
    if op == OP_f32_convert_i32_u { return OP_f32x4_convert_i32x4_u, true; }
    if op == OP_i32_trunc_sat_f32_u { return OP_i32x4_trunc_sat_f32x4_u, true; }
    return OP_nop, false;
}
fn marker(chunk: u8, roles: u32) -> Instruction { instruction(OP_ownership, pack(Ownership { kind: OWN_rest, chunk: chunk, roles: roles , ..})) }
fn nonzeroRead() -> Instruction { marker(14, 1) }
fn hasNonzeroRead(code: const Instruction[:], at: i64) -> bool {
    return at != 0 && at < code.len && (code[at].op == OP_i32_load || code[at].op == OP_f32_load) && code[at - 1].op == OP_ownership && code[at - 1].operand == nonzeroRead().operand;
}
fn journalCarrier() -> Instruction { marker(13, 1) }
fn hasJournalCarrier(code: const Instruction[:], at: i64) -> bool {
    let run = allocationAnnotations(code, at); if run.len == 0 || at < run.len + 2 { return false; }
    let before = code[at - run.len - 2]; return before.op == OP_ownership && before.operand == journalCarrier().operand;
}
fn selfIdentityStore() -> Instruction { marker(11, 1) }
fn hasSelfIdentityStore(code: const Instruction[:], at: i64) -> bool {
    return at != 0 && at < code.len && code[at].op == OP_i32_store && code[at - 1].op == OP_ownership && code[at - 1].operand == selfIdentityStore().operand;
}
fn immortalReference() -> Instruction { marker(12, 1) }
fn hasImmortalReference(code: const Instruction[:], at: i64) -> bool {
    return at != 0 && at < code.len && code[at].op == OP_i32_const && !code[at].table_reference && code[at - 1].op == OP_ownership && code[at - 1].operand == immortalReference().operand;
}
fn scalarStore(bytes: u32) -> Instruction { marker(10, bytes) }
fn hasScalarStore(code: const Instruction[:], at: i64) -> bool {
    if at == 0 || at >= code.len { return false; }
    let op = code[at].op; if op != OP_i32_store && op != OP_f32_store && op != OP_v128_store { return false; }
    if code[at].operand % 4 != 0 { return false; }
    return code[at - 1].op == OP_ownership && code[at - 1].operand == scalarStore(fixed(op).bytes).operand;
}
fn callableCodeRead(ty: u32) -> Instruction { marker(7, ty) }
fn callableCodeLayout(code: const Instruction[:], at: i64) -> u32, bool {
    if at == 0 || at >= code.len || code[at].op != OP_i32_load || code[at].operand != 0 || code[at - 1].op != OP_ownership { return 0, false; }
    let annotation = ownership(code[at - 1].operand);
    if annotation.kind != OWN_rest || annotation.chunk != 7 || annotation.roles == 0 { return 0, false; }
    return annotation.roles, true;
}

let op_names = [
    "unreachable_",
    "nop",
    "block",
    "loop",
    "if_",
    "else_",
    "end",
    "br",
    "br_if",
    "return_",
    "call",
    "call_import",
    "call_indirect",
    "host_ref_get",
    "host_ref_set",
    "host_ref_size",
    "host_ref_grow",
    "host_ref_null",
    "host_ref_is_null",
    "drop",
    "local_get",
    "local_set",
    "local_tee",
    "global_get",
    "global_set",
    "i32_load",
    "f32_load",
    "i32_store",
    "f32_store",
    "memory_size",
    "memory_grow",
    "memory_copy",
    "memory_fill",
    "i32_reinterpret_f32",
    "f32_reinterpret_i32",
    "i32_const",
    "f32_const",
    "i32_eqz",
    "i32_eq",
    "i32_ne",
    "i32_lt_u",
    "i32_gt_u",
    "i32_le_u",
    "i32_ge_u",
    "f32_eq",
    "f32_ne",
    "f32_lt",
    "f32_gt",
    "f32_le",
    "f32_ge",
    "i32_add",
    "i32_sub",
    "i32_mul",
    "i32_div_u",
    "i32_rem_u",
    "i32_and",
    "i32_or",
    "i32_xor",
    "i32_shl",
    "i32_shr_u",
    "i32_clz",
    "i32_ctz",
    "f32_abs",
    "f32_neg",
    "f32_ceil",
    "f32_floor",
    "f32_trunc",
    "f32_sqrt",
    "f32_add",
    "f32_sub",
    "f32_mul",
    "f32_div",
    "f32_min",
    "f32_max",
    "i32_trunc_sat_f32_u",
    "f32_convert_i32_u",
    "v128_load",
    "v128_store",
    "i32x4_splat",
    "f32x4_splat",
    "i32x4_replace_lane",
    "i32x4_extract_lane",
    "f32x4_extract_lane",
    "i32x4_add",
    "i32x4_sub",
    "i32x4_mul",
    "v128_and",
    "v128_or",
    "v128_xor",
    "f32x4_abs",
    "f32x4_neg",
    "f32x4_ceil",
    "f32x4_floor",
    "f32x4_trunc",
    "f32x4_sqrt",
    "f32x4_add",
    "f32x4_sub",
    "f32x4_mul",
    "f32x4_div",
    "f32x4_convert_i32x4_u",
    "i32x4_trunc_sat_f32x4_u",
    "f32x4_convert_i32x4_s",
    "i32x4_trunc_sat_f32x4_s",
    "f32x4_replace_lane",
    "i8x16_shuffle",
    "i32x4_shl",
    "i32x4_shr_s",
    "i32x4_shr_u",
    "i32x4_min_u",
    "i32x4_max_u",
    "f32x4_pmin",
    "f32x4_pmax",
    "i32x4_eq",
    "i32x4_ne",
    "i32x4_lt_u",
    "i32x4_gt_u",
    "i32x4_le_u",
    "i32x4_ge_u",
    "f32x4_eq",
    "f32x4_ne",
    "f32x4_lt",
    "f32x4_gt",
    "f32x4_le",
    "f32x4_ge",
    "v128_not",
    "v128_andnot",
    "v128_bitselect",
    "v128_any_true",
    "i32x4_all_true",
    "f32x4_relaxed_madd",
    "f32x4_relaxed_nmadd",
    "ownership",
    "wide_layouts",
    "resource_retire",
    "i32_select",
];
fn opName(op: Op) -> const u8[:] { assert(op < op_names.len); return op_names[op]; }

// Detached optimizer artifacts own concrete typed runs rather than module ranges.
struct DetachedBody { locals: ValueType[:] = [],instructions: Instruction[:] = [] }
struct DetachedFunction {
    parameters: ValueType[:] = [],result: ValueType = VT_none,result_role: Role = ROLE_unknown,entry: bool = false,provider_parameter: u8 = unknown_provider,
    callable_layout: u32 = 0,signature: u32 = 0,parameter_roles: u64 = 0,annotations: u32 = 0,locals: ValueType[:] = [],instructions: Instruction[:] = [],
}
reusable[] var detached_type_runs: ValueType[>..] = [];
reusable[] var detached_instruction_runs: Instruction[>..] = [];
fn cloneBody(locals: const ValueType[:],instructions: const Instruction[:]) -> DetachedBody,blot_error::Error { let local_copy = detached_type_runs.alloc_slice(locals.len); for value,index in locals { local_copy[index] = value; } let code_copy = detached_instruction_runs.alloc_slice(instructions.len); for value,index in instructions { code_copy[index] = value; } return DetachedBody { locals: local_copy,instructions: code_copy,..},blot_error::Error.none; }
fn cloneBody(body: DetachedBody) -> DetachedBody,blot_error::Error { cloneBody(body.locals,body.instructions) }
fn deinit(body: DetachedBody&) { if body.locals.len != 0 { detached_type_runs.free_slice(body.locals); } if body.instructions.len != 0 { detached_instruction_runs.free_slice(body.instructions); } body = DetachedBody {..}; }
fn cloneFunction(source: Function,parameters: const ValueType[:],locals: const ValueType[:],instructions: const Instruction[:]) -> DetachedFunction,blot_error::Error { let body,error = cloneBody(locals,instructions); if error != blot_error::Error.none { return DetachedFunction {..},error; } let owned = detached_type_runs.alloc_slice(parameters.len); for value,index in parameters { owned[index] = value; } return DetachedFunction { parameters: owned,result: source.result,result_role: source.result_role,entry: source.entry,provider_parameter: source.provider_parameter,callable_layout: source.callable_layout,signature: source.signature,parameter_roles: source.parameter_roles,annotations: source.annotations,locals: body.locals,instructions: body.instructions,..},blot_error::Error.none; }
fn cloneFunction(source: DetachedFunction) -> DetachedFunction,blot_error::Error { let header = Function { result: source.result,result_role: source.result_role,entry: source.entry,provider_parameter: source.provider_parameter,callable_layout: source.callable_layout,signature: source.signature,parameter_roles: source.parameter_roles,annotations: source.annotations,..}; return cloneFunction(header,source.parameters,source.locals,source.instructions); }
fn deinit(source: DetachedFunction&) { if source.parameters.len != 0 { detached_type_runs.free_slice(source.parameters); } var body = DetachedBody { locals: source.locals,instructions: source.instructions,..}; body.deinit(); source = DetachedFunction {..}; }
fn parameterRole(source: DetachedFunction,index: i64) -> Role { if index >= 32 { return ROLE_unknown; } return ((source.parameter_roles >> (index * 2)) & 3) as Role; }
fn codeLength(source: DetachedFunction) -> i64 { source.instructions.len - source.annotations }
