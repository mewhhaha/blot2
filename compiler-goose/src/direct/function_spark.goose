// 4-wide Wasm SIMD (`v128`) auto-vectorization for `spark #[body | pat <- source]`.
// Preserves exact wrapping U32 arithmetic, uniform producer-site 0x7fc00000 NaN
// canonicalization, Bool mask normalization, trap-order equivalence, and scalar
// tail / fallback execution.
namespace squid_direct_function;
import .function;
import direct.relocations;

// WebAssembly 1.0 SIMD (0xfd prefix) sub-opcodes.
let SIMD_v128_load: u32 = 0;
let SIMD_v128_load32_splat: u32 = 9;
let SIMD_v128_store: u32 = 11;
let SIMD_v128_const: u32 = 12;
let SIMD_i8x16_shuffle: u32 = 13;
let SIMD_i8x16_splat: u32 = 15;
let SIMD_i16x8_splat: u32 = 16;
let SIMD_i32x4_splat: u32 = 17;
let SIMD_i64x2_splat: u32 = 18;
let SIMD_f32x4_splat: u32 = 19;
let SIMD_f64x2_splat: u32 = 20;
let SIMD_i32x4_extract_lane: u32 = 27;
let SIMD_i32x4_replace_lane: u32 = 28;
let SIMD_i64x2_extract_lane: u32 = 29;
let SIMD_i64x2_replace_lane: u32 = 30;
let SIMD_f32x4_extract_lane: u32 = 31;
let SIMD_f32x4_replace_lane: u32 = 32;
let SIMD_f64x2_extract_lane: u32 = 33;
let SIMD_f64x2_replace_lane: u32 = 34;
let SIMD_i8x16_eq: u32 = 35;
let SIMD_i32x4_eq: u32 = 55;
let SIMD_i32x4_ne: u32 = 56;
let SIMD_i32x4_lt_s: u32 = 57;
let SIMD_i32x4_lt_u: u32 = 58;
let SIMD_i32x4_gt_s: u32 = 59;
let SIMD_i32x4_gt_u: u32 = 60;
let SIMD_i32x4_le_s: u32 = 61;
let SIMD_i32x4_le_u: u32 = 62;
let SIMD_i32x4_ge_s: u32 = 63;
let SIMD_i32x4_ge_u: u32 = 64;
let SIMD_f32x4_eq: u32 = 65;
let SIMD_f32x4_ne: u32 = 66;
let SIMD_f32x4_lt: u32 = 67;
let SIMD_f32x4_gt: u32 = 68;
let SIMD_f32x4_le: u32 = 69;
let SIMD_f32x4_ge: u32 = 70;
let SIMD_f64x2_eq: u32 = 71;
let SIMD_f64x2_ne: u32 = 72;
let SIMD_f64x2_lt: u32 = 73;
let SIMD_f64x2_gt: u32 = 74;
let SIMD_f64x2_le: u32 = 75;
let SIMD_f64x2_ge: u32 = 76;
let SIMD_v128_not: u32 = 77;
let SIMD_v128_and: u32 = 78;
let SIMD_v128_andnot: u32 = 79;
let SIMD_v128_or: u32 = 80;
let SIMD_v128_xor: u32 = 81;
let SIMD_v128_bitselect: u32 = 82;
let SIMD_v128_any_true: u32 = 83;
let SIMD_v128_store32_lane: u32 = 90;
let SIMD_v128_load32_zero: u32 = 92;
let SIMD_i8x16_all_true: u32 = 99;
let SIMD_i8x16_bitmask: u32 = 100;
let SIMD_i8x16_narrow_i16x8_u: u32 = 102;
let SIMD_f32x4_ceil: u32 = 103;
let SIMD_f32x4_floor: u32 = 104;
let SIMD_f32x4_trunc: u32 = 105;
let SIMD_i8x16_add: u32 = 110;
let SIMD_i8x16_sub: u32 = 113;
let SIMD_f64x2_ceil: u32 = 116;
let SIMD_f64x2_floor: u32 = 117;
let SIMD_i8x16_min_u: u32 = 119;
let SIMD_i8x16_max_u: u32 = 121;
let SIMD_f64x2_trunc: u32 = 122;
let SIMD_i8x16_avgr_u: u32 = 123;
let SIMD_i16x8_narrow_i32x4_u: u32 = 134;
let SIMD_i16x8_extend_low_i8x16_u: u32 = 137;
let SIMD_i16x8_extend_high_i8x16_u: u32 = 138;
let SIMD_i16x8_shl: u32 = 139;
let SIMD_i16x8_shr_s: u32 = 140;
let SIMD_i16x8_shr_u: u32 = 141;
let SIMD_i16x8_add: u32 = 142;
let SIMD_i16x8_sub: u32 = 145;
let SIMD_i16x8_mul: u32 = 149;
let SIMD_i16x8_min_u: u32 = 151;
let SIMD_i16x8_max_u: u32 = 153;
let SIMD_i32x4_neg: u32 = 161;
let SIMD_i32x4_all_true: u32 = 163;
let SIMD_i32x4_bitmask: u32 = 164;
let SIMD_i32x4_extend_low_i16x8_u: u32 = 169;
let SIMD_i32x4_shl: u32 = 171;
let SIMD_i32x4_shr_s: u32 = 172;
let SIMD_i32x4_shr_u: u32 = 173;
let SIMD_i32x4_add: u32 = 174;
let SIMD_i32x4_sub: u32 = 177;
let SIMD_i32x4_mul: u32 = 181;
let SIMD_i32x4_min_u: u32 = 183;
let SIMD_i32x4_max_u: u32 = 185;
let SIMD_i64x2_all_true: u32 = 195;
let SIMD_i64x2_add: u32 = 206;
let SIMD_f32x4_abs: u32 = 224;
let SIMD_f32x4_neg: u32 = 225;
let SIMD_f32x4_sqrt: u32 = 227;
let SIMD_f32x4_add: u32 = 228;
let SIMD_f32x4_sub: u32 = 229;
let SIMD_f32x4_mul: u32 = 230;
let SIMD_f32x4_div: u32 = 231;
let SIMD_f64x2_abs: u32 = 236;
let SIMD_f64x2_neg: u32 = 237;
let SIMD_f64x2_sqrt: u32 = 239;
let SIMD_f64x2_add: u32 = 240;
let SIMD_f64x2_sub: u32 = 241;
let SIMD_f64x2_mul: u32 = 242;
let SIMD_f64x2_div: u32 = 243;
let SIMD_i32x4_trunc_sat_f32x4_s: u32 = 248;
let SIMD_i32x4_trunc_sat_f32x4_u: u32 = 249;
let SIMD_f32x4_convert_i32x4_s: u32 = 250;
let SIMD_f32x4_convert_i32x4_u: u32 = 251;
// Opt-in Wasm 3.0 relaxed-simd opcodes (0xfd 0x101..0x10e):
let SIMD_i32x4_relaxed_trunc_f32x4_s: u32 = 257;
let SIMD_i32x4_relaxed_trunc_f32x4_u: u32 = 258;
// relaxed_madd(a, b, c) = a * b + c; relaxed_nmadd(a, b, c) = -(a * b) + c = c - a * b.
let SIMD_f32x4_relaxed_madd: u32 = 261;
let SIMD_f32x4_relaxed_nmadd: u32 = 262;
let SIMD_f64x2_relaxed_madd: u32 = 263;
let SIMD_f64x2_relaxed_nmadd: u32 = 264;
let SIMD_f32x4_relaxed_min: u32 = 269;
let SIMD_f32x4_relaxed_max: u32 = 270;

fn simdOp(g: Generator&, sub: u32) {
    op(g, OP_prefix_fd);
    uleb(g, sub);
}
fn simdLaneOp(g: Generator&, sub: u32, lane: u8) {
    op(g, OP_prefix_fd);
    uleb(g, sub);
    op(g, lane);
}
fn simdMemOp(g: Generator&, sub: u32, align: u32, offset: u32) {
    op(g, OP_prefix_fd);
    uleb(g, sub);
    uleb(g, align);
    uleb(g, offset);
}
fn simdLaneMemOp(g: Generator&, sub: u32, align: u32, offset: u32, lane: u8) {
    op(g, OP_prefix_fd);
    uleb(g, sub);
    uleb(g, align);
    uleb(g, offset);
    op(g, lane);
}
fn emitShuffleLaneBytes(g: Generator&, lane: u32) {
    let base_b = lane * 4;
    op(g, base_b as u8);
    op(g, (base_b + 1) as u8);
    op(g, (base_b + 2) as u8);
    op(g, (base_b + 3) as u8);
}
fn emitI32x4Shuffle(g: Generator&, l0: u32, l1: u32, l2: u32, l3: u32) {
    simdOp(g, SIMD_i8x16_shuffle);
    emitShuffleLaneBytes(g, l0);
    emitShuffleLaneBytes(g, l1);
    emitShuffleLaneBytes(g, l2);
    emitShuffleLaneBytes(g, l3);
}
// Loads 4 byte-packed Bool elements [0|1] at ptr [+ idx] + mem_offset and widens to i32x4 masks [0|0xffffffff].
fn emitLoadBool4Mask(g: Generator&, ptr_local: u32, idx_local: u32, mem_offset: u32 = 0) {
    lget(g, ptr_local);
    if idx_local != 0xffffffff {
        lget(g, idx_local);
        op(g, OP_i32_add);
    }
    simdMemOp(g, SIMD_v128_load32_zero, 0, mem_offset);
    simdOp(g, SIMD_i16x8_extend_low_i8x16_u);
    simdOp(g, SIMD_i32x4_extend_low_i16x8_u);
    simdOp(g, SIMD_i32x4_neg);
}
// Expects [dst_addr, v128_mask] on stack; normalizes to [0|1] bytes and stores 4 bytes at dst_addr + mem_offset.
fn emitStoreBool4Mask(g: Generator&, f: const Fn&, mem_offset: u32 = 0) {
    v128Const4(g, 1);
    simdOp(g, SIMD_v128_and);
    let tmp = local(g, f, VT_v128);
    ltee(g, tmp);
    lget(g, tmp);
    simdOp(g, SIMD_i16x8_narrow_i32x4_u);
    ltee(g, tmp);
    lget(g, tmp);
    simdOp(g, SIMD_i8x16_narrow_i16x8_u);
    simdLaneMemOp(g, SIMD_v128_store32_lane, 0, mem_offset, 0);
}
fn v128ConstWords(g: Generator&, w0: u32, w1: u32, w2: u32, w3: u32) {
    op(g, OP_prefix_fd);
    uleb(g, SIMD_v128_const);
    squid_direct_writer::word(g.s.code, w0);
    squid_direct_writer::word(g.s.code, w1);
    squid_direct_writer::word(g.s.code, w2);
    squid_direct_writer::word(g.s.code, w3);
}
fn v128Const4(g: Generator&, word: u32) {
    v128ConstWords(g, word, word, word, word);
}
// Canonicalize all NaN lanes of an F32x4 vector on top of the stack to 0x7fc00000.
fn canonicalizeF32x4(g: Generator&, f: const Fn&, nan_vlocal: u32) {
    if !g.s.float_bits_observable { return; }
    let tmp = local(g, f, VT_v128);
    ltee(g, tmp);
    if nan_vlocal != 0xffffffff {
        lget(g, nan_vlocal);
    } else {
        v128Const4(g, 0x7fc00000);
    }
    lget(g, tmp);
    lget(g, tmp);
    simdOp(g, SIMD_f32x4_eq);
    simdOp(g, SIMD_v128_bitselect);
}
fn canonicalizeF64x2(g: Generator&, f: const Fn&) {
    if !g.s.float_bits_observable { return; }
    let tmp = local(g, f, VT_v128);
    ltee(g, tmp);
    simdOp(g, SIMD_v128_const);
    for _ in 0..2 {
        squid_direct_writer::word(g.s.code, 0);
        squid_direct_writer::word(g.s.code, 0x7ff80000);
    }
    lget(g, tmp);
    lget(g, tmp);
    simdOp(g, SIMD_f64x2_eq);
    simdOp(g, SIMD_v128_bitselect);
}

// Local binding inside the vectorized spark body (or an inlined leaf helper).
struct SparkVecLocal {
    unit: u32 = 0,
    binding: u32 = 0,
    tag: squid_direct_types::Tag = squid_direct_types::Tag.unit,
    vlocal: u32 = 0,
    is_mask: bool = false,
    invariant: bool = false,
    scalar_local: u32 = 0xffffffff,
    finite: bool = false,
}

// Range-affine contiguous stream `arr[i]` or `arr[offset + i]`.
struct SparkAffineStream {
    unit: u32 = 0,
    node_id: u32 = 0,
    arr_id: u32 = 0,
    offset_id: u32 = 0,
    arr_ty: Ty = 0,
    elem_tag: squid_direct_types::Tag = squid_direct_types::Tag.unit,
    ptr_local: u32 = 0,
}

// Pre-hoisted outer scalar capture / constant / invariant expression.
struct SparkHoistedScalar {
    unit: u32 = 0,
    node_id: u32 = 0,
    tag: squid_direct_types::Tag = squid_direct_types::Tag.unit,
    scalar_local: u32 = 0xffffffff,
    vlocal: u32 = 0xffffffff,
}

// Local range-affine index alias `let idx = offset + i` inside a spark or for-loop body.
struct SparkAffineLocal {
    binding: u32 = 0,
    offset_id: u32 = 0,
}

// Fixed-capacity analysis/emission plan (zero heap allocations, Goose §7.8 safe).
struct SparkVecPlan {
    spark_unit: u32 = 0,
    is_range: bool = false,
    iter_binding: u32 = 0,
    iter_tag: squid_direct_types::Tag = squid_direct_types::Tag.unit,
    out_tag: squid_direct_types::Tag = squid_direct_types::Tag.unit,
    budget: i64 = 128,
    locals: SparkVecLocal[64] = [SparkVecLocal {}; 64],
    locals_len: i64 = 0,
    affine_locals: SparkAffineLocal[8] = [SparkAffineLocal {}; 8],
    affine_locals_len: i64 = 0,
    streams: SparkAffineStream[16] = [SparkAffineStream {}; 16],
    streams_len: i64 = 0,
    hoisted: SparkHoistedScalar[32] = [SparkHoistedScalar {}; 32],
    hoisted_len: i64 = 0,
    index_local: u32 = 0,
    byte_off_local: u32 = 0,
    unroll_step: u32 = 0,
    iter_value_used: bool = false,
    uses_f32_canon: bool = false,
    nan_vlocal: u32 = 0xffffffff,
}

fn sameOffsetExpr(m: const Module&, a: u32, b: u32) -> bool {
    if a == b { return true; }
    if a == 0 || b == 0 { return false; }
    let la = localRef(m, a);
    let lb = localRef(m, b);
    return la != 0 && la == lb;
}

fn findHoistedScalar(plan: const SparkVecPlan&, unit: u32, binding: u32) -> i64 {
    for i in 0..plan.hoisted_len {
        if plan.hoisted[i].unit == unit && plan.hoisted[i].node_id == binding { return i; }
    }
    return -1;
}

fn findVecLocal(plan: const SparkVecPlan&, unit: u32, binding: u32) -> i64 {
    var i = plan.locals_len;
    while i > 0 {
        i -= 1;
        if plan.locals[i].unit == unit && plan.locals[i].binding == binding { return i; }
    }
    return -1;
}
fn findAffineStream(plan: const SparkVecPlan&, unit: u32, node_id: u32) -> i64 {
    for i in 0..plan.streams_len {
        if plan.streams[i].unit == unit && plan.streams[i].node_id == node_id { return i; }
    }
    return -1;
}
// Vector tracing uses the existing i32x4/f32x4 lane representations.
fn isSparkLaneTag(tag: squid_direct_types::Tag) -> bool {
    return tag == squid_direct_types::Tag.u32_ || tag == squid_direct_types::Tag.f32_ || tag == squid_direct_types::Tag.boolean;
}
fn isContiguousScalarContainer(g: const Generator&, ty: Ty) -> squid_direct_types::Tag, bool {
    let n = g.types.node(ty);
    if n.tag != squid_direct_types::Tag.array && n.tag != squid_direct_types::Tag.view {
        return squid_direct_types::Tag.unit, false;
    }
    let elem = g.types.node(n.a).tag;
    if isSparkLaneTag(elem) { return elem, true; }
    return squid_direct_types::Tag.unit, false;
}
fn lowerInEnv(g: Generator&, m: const Module&, tid: TId, env: const Env&) -> Ty, bool {
    let lowered, err = g.types.lower(m, tid, env);
    if err != squid_direct_types::Error.none { g.dropFailure(); return 0, false; }
    return lowered, true;
}

// Whether `expr_id` is a trap-free lane-invariant U32 expression (valid as a
// range-affine stream offset or lane-invariant shift count).
recursive fn isInvariantScalarExpr(
    g: Generator&,
    f: const Fn&,
    plan: const SparkVecPlan&,
    m: const Module&,
    env: const Env&,
    id: u32,
    want_tag: squid_direct_types::Tag,
    depth: i64,
) -> bool {
    if id == 0 || depth > 16 { return false; }
    let ty, ok = lowerInEnv(g, m, m.typeOf(id), env);
    if !ok || tagOf(g, ty) != want_tag { return false; }
    let n = m.node(id);
    match n.tag {
        constant => { return true; },
        reference => {
            let ref = m.reference(id);
            if ref.unit == 0 || ref.unit == m.unit {
                let vidx = findVecLocal(plan, m.unit, ref.binding);
                if vidx >= 0 {
                    return plan.locals[vidx].invariant && plan.locals[vidx].tag == want_tag;
                }
                if m.unit == f.unit {
                    let bound, present = bindGet(g, f, ref.binding);
                    if present {
                        let _, is_cell = withCellType(g, f, ref.binding);
                        return !is_cell && tagOf(g, bound.ty) == want_tag;
                    }
                }
            }
            // Non-exported module constant with Tag.constant root.
            let target = g.resolve(m, ref);
            if !g.hasUnit(target.unit) { return false; }
            let tm .= g.units[target.unit - 1];
            let body .= tm.body(target.binding);
            if !body || body.is_function || body.exported { return false; }
            if requiresEvidence(g, target) { return false; }
            let rn = tm.node(body.root);
            return rn.tag == squid_check_core::Tag.constant;
        },
        scalar => {
            if n.c != 0 { return false; }
            if want_tag != squid_direct_types::Tag.u32_ { return false; }
            match n.op {
                add, sub, mul, bit_and, bit_or, bit_xor, bit_andnot, shift_left, shift_right, shift_right_signed => {
                    return isInvariantScalarExpr(g, f, plan, m, env, n.a, want_tag, depth + 1) &&
                        isInvariantScalarExpr(g, f, plan, m, env, n.b, want_tag, depth + 1);
                },
                neg, abs, bit_not => {
                    return isInvariantScalarExpr(g, f, plan, m, env, n.a, want_tag, depth + 1);
                },
                _ => { return false; },
            }
        },
        _ => { return false; },
    }
}

// Emits a scalar i32 value for a validated invariant U32 expression (recording
// unpatchableOperand on any constant embedded in a shape/offset/shift).
recursive fn emitInvariantU32(
    g: Generator&,
    f: Fn&,
    plan: const SparkVecPlan&,
    m: const Module&,
    env: const Env&,
    id: u32,
) -> u32, Error {
    let n = m.node(id);
    match n.tag {
        constant => {
            squid_direct_relocations::unpatchableOperand(m.unit, id);
            return constLocal(g, f, n.a), squid_direct_types::Error.none;
        },
        reference => {
            let ref = m.reference(id);
            if ref.unit == 0 || ref.unit == m.unit {
                let vidx = findVecLocal(plan, m.unit, ref.binding);
                if vidx >= 0 {
                    assert(plan.locals[vidx].scalar_local != 0xffffffff);
                    return plan.locals[vidx].scalar_local, squid_direct_types::Error.none;
                }
                if m.unit == f.unit {
                    let bound, present = bindGet(g, f, ref.binding);
                    if present { return w(g, bound, 0), squid_direct_types::Error.none; }
                }
            }
            let target = g.resolve(m, ref);
            let tm .= g.units[target.unit - 1];
            let body .= tm.body(target.binding);
            assert(body);
            g.recordInlined(target.unit, target.binding);
            squid_direct_relocations::unpatchableOperand(target.unit, body.root);
            return constLocal(g, f, tm.node(body.root).a), squid_direct_types::Error.none;
        },
        scalar => {
            let lhs, lerr = emitInvariantU32(g, f, plan, m, env, n.a);
            if lerr != squid_direct_types::Error.none { return 0, lerr; }
            var rhs: u32 = 0;
            if n.b != 0 {
                let r, rerr = emitInvariantU32(g, f, plan, m, env, n.b);
                if rerr != squid_direct_types::Error.none { return 0, rerr; }
                rhs = r;
            }
            lget(g, lhs);
            if n.b != 0 { lget(g, rhs); }
            let serr = scalarOp(g, f, n.op, squid_direct_types::u32_, id, false);
            if serr != squid_direct_types::Error.none { return 0, serr; }
            let dst = local32(g, f);
            lset(g, dst);
            return dst, squid_direct_types::Error.none;
        },
        _ => { return 0, g.fail(m, id, "unexpected invariant scalar expression in SIMD spark"); },
    }
}

fn isIterBindingRef(plan: const SparkVecPlan&, m: const Module&, id: u32) -> bool {
    if id == 0 || plan.iter_binding == 0 || m.unit != plan.spark_unit { return false; }
    let n = m.node(id);
    if n.tag != squid_check_core::Tag.reference { return false; }
    let ref = m.reference(id);
    return (ref.unit == 0 || ref.unit == m.unit) && ref.binding == plan.iter_binding;
}

// Matches a range-affine index `i`, `offset + i`, or `i + offset` (range-only!).
// Returns `(matched, offset_expr_id)` where `offset_expr_id == 0` means `offset = 0`.
fn matchRangeAffineIndex(
    g: Generator&,
    f: const Fn&,
    plan: const SparkVecPlan&,
    m: const Module&,
    env: const Env&,
    idx_id: u32,
) -> bool, u32 {
    if !plan.is_range || plan.iter_binding == 0 || m.unit != plan.spark_unit { return false, 0; }
    if isIterBindingRef(plan, m, idx_id) { return true, 0; }
    let ref_b = localRef(m, idx_id);
    if ref_b != 0 {
        for ai in 0..plan.affine_locals_len {
            if plan.affine_locals[ai].binding == ref_b {
                return true, plan.affine_locals[ai].offset_id;
            }
        }
    }
    let n = m.node(idx_id);
    if (n.tag == squid_check_core::Tag.scalar || n.tag == squid_check_core::Tag.associated) && n.op == squid_check_core::Op.add {
        let ty, ok = lowerInEnv(g, m, m.typeOf(idx_id), env);
        if !ok || tagOf(g, ty) != squid_direct_types::Tag.u32_ { return false, 0; }
        if isIterBindingRef(plan, m, n.a) && isInvariantScalarExpr(g, f, plan, m, env, n.b, squid_direct_types::Tag.u32_, 0) {
            return true, n.b;
        }
        if isIterBindingRef(plan, m, n.b) && isInvariantScalarExpr(g, f, plan, m, env, n.a, squid_direct_types::Tag.u32_, 0) {
            return true, n.a;
        }
    }
    return false, 0;
}

// Checks whether an array expression `arr_id` in the spark unit is a trap-free
// outer array/view local or global pool of 4-byte scalar elements.
fn checkAffineStreamArray(
    g: Generator&,
    f: const Fn&,
    plan: const SparkVecPlan&,
    m: const Module&,
    env: const Env&,
    arr_id: u32,
) -> Ty, squid_direct_types::Tag, bool {
    if m.unit != f.unit || arr_id == 0 { return 0, squid_direct_types::Tag.unit, false; }
    let n = m.node(arr_id);
    if n.tag != squid_check_core::Tag.reference { return 0, squid_direct_types::Tag.unit, false; }
    let ref = m.reference(arr_id);
    if ref.unit == 0 || ref.unit == m.unit {
        if findVecLocal(plan, m.unit, ref.binding) >= 0 { return 0, squid_direct_types::Tag.unit, false; }
        let bound, present = bindGet(g, f, ref.binding);
        if present {
            let _, is_cell = withCellType(g, f, ref.binding);
            if is_cell { return 0, squid_direct_types::Tag.unit, false; }
            let etag, ok = isContiguousScalarContainer(g, bound.ty);
            if ok { return bound.ty, etag, true; }
            return 0, squid_direct_types::Tag.unit, false;
        }
    }
    let target = g.resolve(m, ref);
    if !g.hasUnit(target.unit) { return 0, squid_direct_types::Tag.unit, false; }
    let tm .= g.units[target.unit - 1];
    let body .= tm.body(target.binding);
    if !body || body.is_function { return 0, squid_direct_types::Tag.unit, false; }
    if requiresEvidence(g, target) { return 0, squid_direct_types::Tag.unit, false; }
    let ty, ok = lowerInEnv(g, m, m.typeOf(arr_id), env);
    if !ok { return 0, squid_direct_types::Tag.unit, false; }
    let tag = tagOf(g, ty);
    if tag != squid_direct_types::Tag.array {
        return 0, squid_direct_types::Tag.unit, false;
    }
    let etag, eok = isContiguousScalarContainer(g, ty);
    if !eok { return 0, squid_direct_types::Tag.unit, false; }
    return ty, etag, true;
}

// Resolves a scalar machine op for a Tag.scalar / Tag.associated node without emitting code.
fn resolveSparkScalarOp(
    g: Generator&,
    m: const Module&,
    op_: squid_check_core::Op,
    member: u32,
    use_dispatch: bool,
    operand_ty: Ty,
) -> squid_check_core::Op, BindingRef, bool {
    var no_ref = BindingRef { 0, 0 };
    if !use_dispatch { return op_, no_ref, true; }
    let identity, has_identity = g.receiverIdentity(operand_ty);
    if !has_identity { return op_, no_ref, true; }
    var operator = squid_check_types::Operator.none;
    if member == 0 {
        let found, has_op = operatorOf(op_);
        if !has_op { return op_, no_ref, true; }
        operator = found;
    }
    let target, has_target = g.dispatchTarget(m, identity, member, operator);
    if !has_target {
        if member == 0 { return op_, no_ref, true; }
        return squid_check_core::Op.none, no_ref, false;
    }
    if !g.hasUnit(target.unit) { return squid_check_core::Op.none, no_ref, false; }
    let defining .= g.units[target.unit - 1];
    let alias, has_alias = primitiveAlias(defining, target.binding);
    if has_alias {
        let prim = defining.primitive(alias);
        if prim.kind == squid_check_core::PrimitiveKind.scalar && prim.op != squid_check_core::Op.none {
            return prim.op, target, true;
        }
        return squid_check_core::Op.none, no_ref, false;
    }
    // Non-primitive associated function (e.g. U32.bit_not, U32.ne, F32.min): handled via call inlining!
    return squid_check_core::Op.none, target, true;
}

fn supportedSimdMachineOp(op_: squid_check_core::Op, operand_tag: squid_direct_types::Tag) -> bool {
    if operand_tag == squid_direct_types::Tag.f32_ {
        match op_ {
            add, sub, mul, div, neg, abs, sqrt, floor, ceil, trunc,
            equal, not_equal, less, less_equal, greater, greater_equal,
            min, max, bits, convert_f32_u32, convert_f32_i32 => { return true; },
            _ => { return false; },
        }
    }
    if operand_tag == squid_direct_types::Tag.u32_ {
        match op_ {
            add, sub, mul, neg, abs,
            bit_and, bit_or, bit_xor, bit_not, bit_andnot,
            shift_left, shift_right, shift_right_signed,
            equal, not_equal, less, less_equal, greater, greater_equal,
            min, max, from_bits, convert_u32_f32, convert_i32_f32 => { return true; },
            // Integer div and rem can trap on zero divisor -> scalar fallback!
            _ => { return false; },
        }
    }
    if operand_tag == squid_direct_types::Tag.boolean {
        match op_ {
            not_, equal, not_equal, less, less_equal, greater, greater_equal => { return true; },
            _ => { return false; },
        }
    }
    return false;
}

fn isShiftOp(op_: squid_check_core::Op) -> bool {
    return op_ == squid_check_core::Op.shift_left || op_ == squid_check_core::Op.shift_right || op_ == squid_check_core::Op.shift_right_signed;
}

// Follows non-function reference alias chains (`const sqrt = F32.sqrt`, etc.)
// to their underlying target binding.
fn followAliasTarget(g: const Generator&, start: BindingRef) -> BindingRef {
    var cur = start;
    for step in 0..8 {
        if !g.hasUnit(cur.unit) { return cur; }
        let tm .= g.units[cur.unit - 1];
        let body .= tm.body(cur.binding);
        if !body || body.is_function { return cur; }
        if tm.node(body.root).tag != squid_check_core::Tag.reference { return cur; }
        let next = g.resolve(tm, tm.reference(body.root));
        if next == cur { return cur; }
        cur = next;
    }
    return cur;
}

// Records `g.recordInlined` for every alias hop along `followAliasTarget`.
fn recordAliasChain(g: Generator&, start: BindingRef) -> BindingRef {
    var cur = start;
    for step in 0..8 {
        if !g.hasUnit(cur.unit) { return cur; }
        let tm .= g.units[cur.unit - 1];
        let body .= tm.body(cur.binding);
        if !body || body.is_function { return cur; }
        if tm.node(body.root).tag != squid_check_core::Tag.reference { return cur; }
        let next = g.resolve(tm, tm.reference(body.root));
        if next == cur { return cur; }
        g.recordInlined(cur.unit, cur.binding);
        cur = next;
    }
    return cur;
}

// Checks whether a call to `target` with `arg_ids` can be vectorized as either
// a primitive op or an inlined trivial pure scalar leaf function.
recursive fn checkVecCall(
    g: Generator&,
    f: const Fn&,
    plan: SparkVecPlan&,
    m: const Module&,
    env: const Env&,
    target_in: BindingRef,
    arg_ids: const u32[:],
    result_ty: Ty,
    inline_depth: i64,
    depth: i64,
) -> bool {
    let target = followAliasTarget(g, target_in);
    if !g.hasUnit(target.unit) { return false; }
    if requiresEvidence(g, target) { return false; }
    let tm .= g.units[target.unit - 1];
    let alias, has_alias = primitiveAlias(tm, target.binding);
    if has_alias {
        let prim = tm.primitive(alias);
        if prim.kind != squid_check_core::PrimitiveKind.scalar || prim.arity != arg_ids.len || arg_ids.len == 0 || arg_ids.len > 2 {
            return false;
        }
        let a0_ty, ok0 = lowerInEnv(g, m, m.typeOf(arg_ids[0]), env);
        if !ok0 { return false; }
        let a0_tag = tagOf(g, a0_ty);
        if !supportedSimdMachineOp(prim.op, a0_tag) { return false; }
        if a0_tag == squid_direct_types::Tag.f32_ && isCanonicalF32Op(prim.op) { plan.uses_f32_canon = true; }
        if !checkVecExpr(g, f, plan, m, env, arg_ids[0], inline_depth, depth + 1, false) { return false; }
        if arg_ids.len == 2 {
            if isShiftOp(prim.op) {
                return isInvariantScalarExpr(g, f, plan, m, env, arg_ids[1], squid_direct_types::Tag.u32_, 0);
            }
            let a1_ty, ok1 = lowerInEnv(g, m, m.typeOf(arg_ids[1]), env);
            if !ok1 || tagOf(g, a1_ty) != a0_tag { return false; }
            if !checkVecExpr(g, f, plan, m, env, arg_ids[1], inline_depth, depth + 1, false) { return false; }
        }
        return true;
    }
    if inline_depth >= 4 { return false; }
    let body .= tm.body(target.binding);
    if !body || !body.is_function || body.runtime { return false; }
    let params = tm.bodyParameters(body);
    if params.len != arg_ids.len || params.len == 0 || params.len > 8 { return false; }
    // Lower callee function type from concrete argument and result types.
    var arg_tys: Ty[8] = [0; 8];
    var arg_inv: bool[8] = [false; 8];
    for at in 0..arg_ids.len {
        let aty, aok = lowerInEnv(g, m, m.typeOf(arg_ids[at]), env);
        if !aok || !isSparkLaneTag(tagOf(g, aty)) { return false; }
        arg_tys[at] = aty;
        arg_inv[at] = isInvariantScalarExpr(g, f, plan, m, env, arg_ids[at], tagOf(g, aty), 0);
        if !checkVecExpr(g, f, plan, m, env, arg_ids[at], inline_depth, depth + 1, false) { return false; }
    }
    var curried_ty = result_ty;
    var at = arg_ids.len;
    while at > 0 {
        at -= 1;
        let wrapped, werr = g.types.function(arg_tys[at], curried_ty);
        if werr != squid_direct_types::Error.none { return false; }
        curried_ty = wrapped;
    }
    var sub_env = Env {};
    g.types.match_(tm, tm.binding(body.binding).ty, curried_ty, sub_env);
    if body.scheme.obligations.len != 0 {
        let solved = g.solveObligationsPublic(tm, body.scheme.obligations, sub_env);
        if solved != squid_direct_types::Error.none { g.dropFailure(); return false; }
    }
    for v in tm.types.list(body.scheme.variables) {
        let _, verr = g.types.lower(tm, v, sub_env);
        if verr != squid_direct_types::Error.none { g.dropFailure(); return false; }
    }
    let mark = plan.locals_len;
    if mark + params.len > 64 { return false; }
    for param, pi in params {
        let pty, pok = lowerInEnv(g, tm, param.ty, sub_env);
        if !pok || pty != arg_tys[pi] { plan.locals_len = mark; return false; }
        let ptag = tagOf(g, pty);
        plan.locals[plan.locals_len] = SparkVecLocal {
            unit: tm.unit,
            binding: param.binding,
            tag: ptag,
            is_mask: ptag == squid_direct_types::Tag.boolean,
            invariant: arg_inv[pi],
        };
        plan.locals_len += 1;
    }
    let ok = checkVecExpr(g, f, plan, tm, sub_env, body.root, inline_depth + 1, depth + 1, true);
    plan.locals_len = mark;
    return ok;
}

// Recursive vectorizability validator & affine-stream collector.
recursive fn checkVecExpr(
    g: Generator&,
    f: const Fn&,
    plan: SparkVecPlan&,
    m: const Module&,
    env: const Env&,
    id: u32,
    inline_depth: i64,
    depth: i64,
    allow_return: bool,
) -> bool {
    if id == 0 || depth > 48 || plan.budget <= 0 { return false; }
    plan.budget -= 1;
    let n = m.node(id);
    match n.tag {
        constant => {
            let ty, ok = lowerInEnv(g, m, m.typeOf(id), env);
            return ok && isSparkLaneTag(tagOf(g, ty));
        },
        reference => {
            let ty, ok = lowerInEnv(g, m, m.typeOf(id), env);
            if !ok || !isSparkLaneTag(tagOf(g, ty)) { return false; }
            let want_tag = tagOf(g, ty);
            let ref = m.reference(id);
            if ref.unit == 0 || ref.unit == m.unit {
                let vidx = findVecLocal(plan, m.unit, ref.binding);
                if vidx >= 0 {
                    if vidx == 0 && plan.iter_binding != 0 && m.unit == plan.spark_unit && ref.binding == plan.iter_binding {
                        plan.iter_value_used = true;
                    }
                    return plan.locals[vidx].tag == want_tag;
                }
                if m.unit == f.unit {
                    let bound, present = bindGet(g, f, ref.binding);
                    if present {
                        let _, is_cell = withCellType(g, f, ref.binding);
                        if is_cell || tagOf(g, bound.ty) != want_tag { return false; }
                        if findHoistedScalar(plan, m.unit, ref.binding) < 0 && plan.hoisted_len < 32 {
                            plan.hoisted[plan.hoisted_len] = SparkHoistedScalar {
                                unit: m.unit,
                                node_id: ref.binding,
                                tag: want_tag,
                                scalar_local: w(g, bound, 0),
                            };
                            plan.hoisted_len += 1;
                        }
                        return true;
                    }
                }
            }
            let target = g.resolve(m, ref);
            if !g.hasUnit(target.unit) { return false; }
            let tm .= g.units[target.unit - 1];
            let body .= tm.body(target.binding);
            if !body || body.is_function || body.exported || requiresEvidence(g, target) { return false; }
            return tm.node(body.root).tag == squid_check_core::Tag.constant;
        },
        scalar => {
            let res_ty, rok = lowerInEnv(g, m, m.typeOf(id), env);
            if !rok || !isSparkLaneTag(tagOf(g, res_ty)) { return false; }
            let a_ty, aok = lowerInEnv(g, m, m.typeOf(n.a), env);
            if !aok || !isSparkLaneTag(tagOf(g, a_ty)) { return false; }
            let a_tag = tagOf(g, a_ty);
            let machine, disp_target, resolved = resolveSparkScalarOp(g, m, n.op, 0, n.c == 1, a_ty);
            if !resolved { return false; }
            if machine == squid_check_core::Op.none {
                if disp_target.binding == 0 { return false; }
                if n.b != 0 {
                    var pair: u32[2] = [n.a, n.b];
                    return checkVecCall(g, f, plan, m, env, disp_target, pair[..], res_ty, inline_depth, depth + 1);
                }
                var one: u32[1] = [n.a];
                return checkVecCall(g, f, plan, m, env, disp_target, one[..], res_ty, inline_depth, depth + 1);
            }
            if !supportedSimdMachineOp(machine, a_tag) { return false; }
            if a_tag == squid_direct_types::Tag.f32_ && isCanonicalF32Op(machine) { plan.uses_f32_canon = true; }
            if !checkVecExpr(g, f, plan, m, env, n.a, inline_depth, depth + 1, false) { return false; }
            if n.b != 0 {
                if isShiftOp(machine) {
                    return isInvariantScalarExpr(g, f, plan, m, env, n.b, squid_direct_types::Tag.u32_, 0);
                }
                let b_ty, bok = lowerInEnv(g, m, m.typeOf(n.b), env);
                if !bok || tagOf(g, b_ty) != a_tag { return false; }
                if !checkVecExpr(g, f, plan, m, env, n.b, inline_depth, depth + 1, false) { return false; }
            }
            return true;
        },
        associated => {
            let res_ty, rok = lowerInEnv(g, m, m.typeOf(id), env);
            if !rok || !isSparkLaneTag(tagOf(g, res_ty)) { return false; }
            let a_ty, aok = lowerInEnv(g, m, m.typeOf(n.a), env);
            if !aok || !isSparkLaneTag(tagOf(g, a_ty)) { return false; }
            let a_tag = tagOf(g, a_ty);
            let machine, disp_target, resolved = resolveSparkScalarOp(g, m, n.op, n.c, true, a_ty);
            if !resolved { return false; }
            if machine == squid_check_core::Op.none {
                if disp_target.binding == 0 { return false; }
                if n.b != 0 {
                    var pair: u32[2] = [n.a, n.b];
                    return checkVecCall(g, f, plan, m, env, disp_target, pair[..], res_ty, inline_depth, depth + 1);
                }
                var one: u32[1] = [n.a];
                return checkVecCall(g, f, plan, m, env, disp_target, one[..], res_ty, inline_depth, depth + 1);
            }
            if !supportedSimdMachineOp(machine, a_tag) { return false; }
            if a_tag == squid_direct_types::Tag.f32_ && isCanonicalF32Op(machine) { plan.uses_f32_canon = true; }
            if !checkVecExpr(g, f, plan, m, env, n.a, inline_depth, depth + 1, false) { return false; }
            if n.b != 0 {
                if isShiftOp(machine) {
                    return isInvariantScalarExpr(g, f, plan, m, env, n.b, squid_direct_types::Tag.u32_, 0);
                }
                let b_ty, bok = lowerInEnv(g, m, m.typeOf(n.b), env);
                if !bok || tagOf(g, b_ty) != a_tag { return false; }
                if !checkVecExpr(g, f, plan, m, env, n.b, inline_depth, depth + 1, false) { return false; }
            }
            return true;
        },
        logical => {
            // Both operands must be total & trap-free so branchless v128.and / v128.or is exact.
            return checkVecExpr(g, f, plan, m, env, n.a, inline_depth, depth + 1, false) &&
                checkVecExpr(g, f, plan, m, env, n.b, inline_depth, depth + 1, false);
        },
        if_value => {
            let res_ty, rok = lowerInEnv(g, m, m.typeOf(id), env);
            if !rok || !isSparkLaneTag(tagOf(g, res_ty)) { return false; }
            let t_ty, tok = lowerInEnv(g, m, m.typeOf(n.b), env);
            let e_ty, eok = lowerInEnv(g, m, m.typeOf(n.c), env);
            if !tok || !eok || t_ty != res_ty || e_ty != res_ty { return false; }
            return checkVecExpr(g, f, plan, m, env, n.a, inline_depth, depth + 1, false) &&
                checkVecExpr(g, f, plan, m, env, n.b, inline_depth, depth + 1, false) &&
                checkVecExpr(g, f, plan, m, env, n.c, inline_depth, depth + 1, false);
        },
        return_ => {
            if !allow_return { return false; }
            return checkVecExpr(g, f, plan, m, env, n.a, inline_depth, depth + 1, false);
        },
        block_, suite => {
            let child_len = m.children(id).len;
            if child_len == 0 { return false; }
            let mark = plan.locals_len;
            var ok = true;
            for at in 0..(child_len - 1) {
                let child = m.children(id)[at];
                let cn = m.node(child);
                if cn.tag == squid_check_core::Tag.bind && cn.c == 0 && m.binding(cn.a).scheme.variables.len == 0 {
                    let bty, bok = lowerInEnv(g, m, m.typeOf(cn.b), env);
                    if !bok || !isSparkLaneTag(tagOf(g, bty)) || plan.locals_len >= 64 { ok = false; break; }
                    if !checkVecExpr(g, f, plan, m, env, cn.b, inline_depth, depth + 1, false) { ok = false; break; }
                    let btag = tagOf(g, bty);
                    let inv = isInvariantScalarExpr(g, f, plan, m, env, cn.b, btag, 0);
                    plan.locals[plan.locals_len] = SparkVecLocal {
                        unit: m.unit,
                        binding: cn.a,
                        tag: btag,
                        is_mask: btag == squid_direct_types::Tag.boolean,
                        invariant: inv,
                    };
                    plan.locals_len += 1;
                } else if cn.tag == squid_check_core::Tag.pattern_bind && cn.c == 0 {
                    let pat = m.pattern(cn.a);
                    if pat.tag != squid_check_core::PatternTag.bind && pat.tag != squid_check_core::PatternTag.wildcard { ok = false; break; }
                    let bty, bok = lowerInEnv(g, m, m.typeOf(cn.b), env);
                    if !bok || !isSparkLaneTag(tagOf(g, bty)) || plan.locals_len >= 64 { ok = false; break; }
                    if !checkVecExpr(g, f, plan, m, env, cn.b, inline_depth, depth + 1, false) { ok = false; break; }
                    if pat.tag == squid_check_core::PatternTag.bind {
                        let btag = tagOf(g, bty);
                        let inv = isInvariantScalarExpr(g, f, plan, m, env, cn.b, btag, 0);
                        plan.locals[plan.locals_len] = SparkVecLocal {
                            unit: m.unit,
                            binding: pat.a,
                            tag: btag,
                            is_mask: btag == squid_direct_types::Tag.boolean,
                            invariant: inv,
                        };
                        plan.locals_len += 1;
                    }
                } else {
                    ok = false;
                    break;
                }
            }
            if ok {
                let last = m.children(id)[child_len - 1];
                let allow_tail_ret = allow_return || n.tag == squid_check_core::Tag.block_;
                ok = checkVecExpr(g, f, plan, m, env, last, inline_depth, depth + 1, allow_tail_ret);
            }
            plan.locals_len = mark;
            return ok;
        },
        call => {
            let info = m.call(id);
            let res_ty, rok = lowerInEnv(g, m, m.typeOf(id), env);
            if !rok || !isSparkLaneTag(tagOf(g, res_ty)) { return false; }
            let target = g.resolve(m, info.target);
            return checkVecCall(g, f, plan, m, env, target, info.arguments, res_ty, inline_depth, depth + 1);
        },
        project => {
            let proj = m.projection(n.b);
            if proj.field == 0 || m.projectionVariants(n.b).len != 0 { return false; }
            let res_ty, rok = lowerInEnv(g, m, m.typeOf(id), env);
            if !rok || !isSparkLaneTag(tagOf(g, res_ty)) { return false; }
            let recv_ty, rec_ok = lowerInEnv(g, m, m.typeOf(n.a), env);
            if !rec_ok || !isSparkLaneTag(tagOf(g, recv_ty)) { return false; }
            let identity, has_ident = g.receiverIdentity(recv_ty);
            if !has_ident { return false; }
            let target, has_target = g.dispatchTarget(m, identity, proj.field, squid_check_types::Operator.none);
            if !has_target { return false; }
            var one: u32[1] = [n.a];
            return checkVecCall(g, f, plan, m, env, target, one[..], res_ty, inline_depth, depth + 1);
        },
        array_op, storage => {
            // Range-affine contiguous stream loads ONLY (`arr[i]` or `arr[offset + i]`
            // inside a range generator). Array-generator gathers fall back to scalar!
            if !plan.is_range || m.unit != plan.spark_unit { return false; }
            var is_read = false;
            if n.tag == squid_check_core::Tag.array_op {
                is_read = m.arrayOperation(id) == squid_backend_collection_ops::Op.get;
            } else {
                let sop, serr = squid_check_storage_ops::opFromCode(n.c);
                is_read = serr == squid_error::Error.none && sop == squid_check_storage_ops::Op.read;
            }
            if !is_read { return false; }
            let children = m.children(id);
            if children.len != 2 { return false; }
            let arr_ty, elem_tag, arr_ok = checkAffineStreamArray(g, f, plan, m, env, children[0]);
            if !arr_ok { return false; }
            let idx_ok, offset_id = matchRangeAffineIndex(g, f, plan, m, env, children[1]);
            if !idx_ok { return false; }
            if findAffineStream(plan, m.unit, id) < 0 {
                if plan.streams_len >= 16 { return false; }
                plan.streams[plan.streams_len] = SparkAffineStream {
                    unit: m.unit,
                    node_id: id,
                    arr_id: children[0],
                    offset_id: offset_id,
                    arr_ty: arr_ty,
                    elem_tag: elem_tag,
                };
                plan.streams_len += 1;
            }
            return true;
        },
        _ => { return false; },
    }
}

// Emits a single SIMD machine op on operands already on the Wasm operand stack
// (except shifts, which take `(v128, i32)`). Leaves the resulting `v128` on top.
fn emitSimdMachineOp(
    g: Generator&,
    f: const Fn&,
    op_: squid_check_core::Op,
    operand_tag: squid_direct_types::Tag,
    elide_nan: bool,
    nan_vlocal: u32,
) {
    if operand_tag == squid_direct_types::Tag.f32_ {
        let skip_nan = elide_nan || f.defer_f32_nan;
        match op_ {
            add => { simdOp(g, SIMD_f32x4_add); if !skip_nan { canonicalizeF32x4(g, f, nan_vlocal); } },
            sub => { simdOp(g, SIMD_f32x4_sub); if !skip_nan { canonicalizeF32x4(g, f, nan_vlocal); } },
            mul => { simdOp(g, SIMD_f32x4_mul); if !skip_nan { canonicalizeF32x4(g, f, nan_vlocal); } },
            div => { simdOp(g, SIMD_f32x4_div); if !skip_nan { canonicalizeF32x4(g, f, nan_vlocal); } },
            sqrt => { simdOp(g, SIMD_f32x4_sqrt); if !skip_nan { canonicalizeF32x4(g, f, nan_vlocal); } },
            floor => { simdOp(g, SIMD_f32x4_floor); if !skip_nan { canonicalizeF32x4(g, f, nan_vlocal); } },
            ceil => { simdOp(g, SIMD_f32x4_ceil); if !skip_nan { canonicalizeF32x4(g, f, nan_vlocal); } },
            trunc => { simdOp(g, SIMD_f32x4_trunc); if !skip_nan { canonicalizeF32x4(g, f, nan_vlocal); } },
            neg => { simdOp(g, SIMD_f32x4_neg); },
            abs => { simdOp(g, SIMD_f32x4_abs); },
            bits => {},
            convert_f32_u32 => {
                if squid_direct_writer::relaxedSimdEnabled() { simdOp(g, SIMD_i32x4_relaxed_trunc_f32x4_u); }
                else { simdOp(g, SIMD_i32x4_trunc_sat_f32x4_u); }
            },
            convert_f32_i32 => {
                if squid_direct_writer::relaxedSimdEnabled() { simdOp(g, SIMD_i32x4_relaxed_trunc_f32x4_s); }
                else { simdOp(g, SIMD_i32x4_trunc_sat_f32x4_s); }
            },
            equal => { simdOp(g, SIMD_f32x4_eq); },
            not_equal => { simdOp(g, SIMD_f32x4_ne); },
            less => { simdOp(g, SIMD_f32x4_lt); },
            less_equal => { simdOp(g, SIMD_f32x4_le); },
            greater => { simdOp(g, SIMD_f32x4_gt); },
            greater_equal => { simdOp(g, SIMD_f32x4_ge); },
            min, max => {
                if squid_direct_writer::relaxedSimdEnabled() {
                    if op_ == squid_check_core::Op.min { simdOp(g, SIMD_f32x4_relaxed_min); }
                    else { simdOp(g, SIMD_f32x4_relaxed_max); }
                } else {
                    // Match prelude `if a < b then a else b` (NaN and -0/+0 exact!).
                    let rb = local(g, f, VT_v128);
                    let la = local(g, f, VT_v128);
                    lset(g, rb);
                    lset(g, la);
                    lget(g, la);
                    lget(g, rb);
                    lget(g, la);
                    lget(g, rb);
                    if op_ == squid_check_core::Op.min { simdOp(g, SIMD_f32x4_lt); } else { simdOp(g, SIMD_f32x4_gt); }
                    simdOp(g, SIMD_v128_bitselect);
                }
            },
            _ => { abort("unsupported F32 SIMD op"); },
        }
        return;
    }
    if operand_tag == squid_direct_types::Tag.u32_ {
        match op_ {
            add => { simdOp(g, SIMD_i32x4_add); },
            sub => { simdOp(g, SIMD_i32x4_sub); },
            mul => { simdOp(g, SIMD_i32x4_mul); },
            neg => { simdOp(g, SIMD_i32x4_neg); },
            abs => {},
            bit_and => { simdOp(g, SIMD_v128_and); },
            bit_or => { simdOp(g, SIMD_v128_or); },
            bit_xor => { simdOp(g, SIMD_v128_xor); },
            bit_not => { simdOp(g, SIMD_v128_not); },
            bit_andnot => { simdOp(g, SIMD_v128_andnot); },
            shift_left => { simdOp(g, SIMD_i32x4_shl); },
            shift_right => { simdOp(g, SIMD_i32x4_shr_u); },
            shift_right_signed => { simdOp(g, SIMD_i32x4_shr_s); },
            from_bits => {},
            convert_u32_f32 => { simdOp(g, SIMD_f32x4_convert_i32x4_u); },
            convert_i32_f32 => { simdOp(g, SIMD_f32x4_convert_i32x4_s); },
            equal => { simdOp(g, SIMD_i32x4_eq); },
            not_equal => { simdOp(g, SIMD_i32x4_ne); },
            less => { simdOp(g, SIMD_i32x4_lt_u); },
            less_equal => { simdOp(g, SIMD_i32x4_le_u); },
            greater => { simdOp(g, SIMD_i32x4_gt_u); },
            greater_equal => { simdOp(g, SIMD_i32x4_ge_u); },
            min, max => {
                let rb = local(g, f, VT_v128);
                let la = local(g, f, VT_v128);
                lset(g, rb);
                lset(g, la);
                lget(g, la);
                lget(g, rb);
                lget(g, la);
                lget(g, rb);
                if op_ == squid_check_core::Op.min { simdOp(g, SIMD_i32x4_lt_u); } else { simdOp(g, SIMD_i32x4_gt_u); }
                simdOp(g, SIMD_v128_bitselect);
            },
            _ => { abort("unsupported U32 SIMD op"); },
        }
        return;
    }
    // Bool masks (0x00000000 or 0xffffffff per lane).
    match op_ {
        not_ => { simdOp(g, SIMD_v128_not); },
        equal => { simdOp(g, SIMD_i32x4_eq); },
        not_equal => { simdOp(g, SIMD_i32x4_ne); },
        less => { simdOp(g, SIMD_i32x4_lt_u); },
        less_equal => { simdOp(g, SIMD_i32x4_le_u); },
        greater => { simdOp(g, SIMD_i32x4_gt_u); },
        greater_equal => { simdOp(g, SIMD_i32x4_ge_u); },
        _ => { abort("unsupported Bool SIMD op"); },
    }
}

// Emits a vectorized call (either primitive alias or inlined scalar leaf helper),
// leaving one `v128` on top of the stack.
recursive fn emitVecCall(
    g: Generator&,
    f: Fn&,
    plan: SparkVecPlan&,
    m: const Module&,
    env: const Env&,
    target_in: BindingRef,
    arg_ids: const u32[:],
    result_ty: Ty,
    elide_nan: bool,
) -> Error {
    let target = recordAliasChain(g, target_in);
    let tm .= g.units[target.unit - 1];
    let alias, has_alias = primitiveAlias(tm, target.binding);
    if has_alias {
        g.recordInlined(target.unit, target.binding);
        let prim = tm.primitive(alias);
        let a0_ty, _ = lowerInEnv(g, m, m.typeOf(arg_ids[0]), env);
        let a0_tag = tagOf(g, a0_ty);
        let child_elide = a0_tag == squid_direct_types::Tag.f32_ && isCanonicalF32Consumer(prim.op);
        let err0 = emitVecExpr(g, f, plan, m, env, arg_ids[0], child_elide);
        if err0 != squid_direct_types::Error.none { return err0; }
        if arg_ids.len == 2 {
            if isShiftOp(prim.op) {
                let s_loc, serr = emitInvariantU32(g, f, plan, m, env, arg_ids[1]);
                if serr != squid_direct_types::Error.none { return serr; }
                lget(g, s_loc);
            } else {
                let err1 = emitVecExpr(g, f, plan, m, env, arg_ids[1], child_elide);
                if err1 != squid_direct_types::Error.none { return err1; }
            }
        }
        emitSimdMachineOp(g, f, prim.op, a0_tag, elide_nan, plan.nan_vlocal);
        return squid_direct_types::Error.none;
    }
    let body .= tm.body(target.binding);
    assert(body);
    g.recordInlined(target.unit, target.binding);
    let params = tm.bodyParameters(body);
    var arg_tys: Ty[8] = [0; 8];
    var arg_vlocals: u32[8] = [0; 8];
    var arg_inv: bool[8] = [false; 8];
    var arg_slocals: u32[8] = [0xffffffff; 8];
    for at in 0..arg_ids.len {
        let aty, _ = lowerInEnv(g, m, m.typeOf(arg_ids[at]), env);
        let atag = tagOf(g, aty);
        arg_tys[at] = aty;
        // Always canonicalize helper arguments so elision never crosses into an inlined body.
        let aerr = emitVecExpr(g, f, plan, m, env, arg_ids[at], false);
        if aerr != squid_direct_types::Error.none { return aerr; }
        let vl = local(g, f, VT_v128);
        lset(g, vl);
        arg_vlocals[at] = vl;
        if atag == squid_direct_types::Tag.u32_ && isInvariantScalarExpr(g, f, plan, m, env, arg_ids[at], squid_direct_types::Tag.u32_, 0) {
            let sl, serr = emitInvariantU32(g, f, plan, m, env, arg_ids[at]);
            if serr != squid_direct_types::Error.none { return serr; }
            arg_inv[at] = true;
            arg_slocals[at] = sl;
        }
    }
    var curried_ty = result_ty;
    var at = arg_ids.len;
    while at > 0 {
        at -= 1;
        let wrapped, werr = g.types.function(arg_tys[at], curried_ty);
        if werr != squid_direct_types::Error.none { return werr; }
        curried_ty = wrapped;
    }
    var sub_env = Env {};
    g.types.match_(tm, tm.binding(body.binding).ty, curried_ty, sub_env);
    if body.scheme.obligations.len != 0 {
        let solved = g.solveObligationsPublic(tm, body.scheme.obligations, sub_env);
        if solved != squid_direct_types::Error.none { return solved; }
    }
    let mark = plan.locals_len;
    for param, pi in params {
        let ptag = tagOf(g, arg_tys[pi]);
        plan.locals[plan.locals_len] = SparkVecLocal {
            unit: tm.unit,
            binding: param.binding,
            tag: ptag,
            vlocal: arg_vlocals[pi],
            is_mask: ptag == squid_direct_types::Tag.boolean,
            invariant: arg_inv[pi],
            scalar_local: arg_slocals[pi],
        };
        plan.locals_len += 1;
    }
    let err = emitVecExpr(g, f, plan, tm, sub_env, body.root, elide_nan);
    plan.locals_len = mark;
    return err;
}

// Matches `if a < b then a else b` (or swapped) for F32 operands so `--relaxed-simd`
// emits single-instruction `f32x4.relaxed_min` / `f32x4.relaxed_max` for `F32.min`,
// `F32.max`, `F32.clamp`, `saturate`, and explicit `if x < y then x else y` idioms.
fn sameSparkMinMaxLeaf(m: const Module&, a: u32, b: u32) -> bool {
    if a == 0 || b == 0 { return false; }
    if a == b { return true; }
    let na = m.node(a);
    let nb = m.node(b);
    if na.tag == squid_check_core::Tag.reference && nb.tag == squid_check_core::Tag.reference {
        let la = localRef(m, a);
        let lb = localRef(m, b);
        return la != 0 && la == lb;
    }
    if na.tag == squid_check_core::Tag.constant && nb.tag == squid_check_core::Tag.constant {
        return na.a == nb.a;
    }
    return false;
}

fn matchRelaxedF32MinMax(g: Generator&, m: const Module&, env: const Env&, cond_id: u32, then_id: u32, else_id: u32) -> bool, bool {
    if cond_id == 0 || then_id == 0 || else_id == 0 { return false, false; }
    let tty, tok = lowerInEnv(g, m, m.typeOf(then_id), env);
    if !tok || tagOf(g, tty) != squid_direct_types::Tag.f32_ { return false, false; }
    let cn = m.node(cond_id);
    var cmp_op = squid_check_core::Op.none;
    var cmp_a: u32 = 0;
    var cmp_b: u32 = 0;
    if (cn.tag == squid_check_core::Tag.scalar || cn.tag == squid_check_core::Tag.associated) && cn.b != 0 {
        let aty, aok = lowerInEnv(g, m, m.typeOf(cn.a), env);
        if !aok || tagOf(g, aty) != squid_direct_types::Tag.f32_ { return false, false; }
        let is_assoc = cn.tag == squid_check_core::Tag.associated;
        let use_disp = is_assoc || cn.c == 1;
        var member: u32 = 0;
        if is_assoc { member = cn.c; }
        let machine, _s1, _s2 = resolveSparkScalarOp(g, m, cn.op, member, use_disp, aty);
        cmp_op = machine;
        cmp_a = cn.a;
        cmp_b = cn.b;
    } else if cn.tag == squid_check_core::Tag.call {
        let info = m.call(cond_id);
        if info.arguments.len == 2 {
            let target = recordAliasChain(g, g.resolve(m, info.target));
            let tm .= g.units[target.unit - 1];
            let alias, has_alias = primitiveAlias(tm, target.binding);
            if has_alias {
                let pop = tm.primitive(alias).op;
                let aty, aok = lowerInEnv(g, m, m.typeOf(info.arguments[0]), env);
                if aok && tagOf(g, aty) == squid_direct_types::Tag.f32_ {
                    cmp_op = pop;
                    cmp_a = info.arguments[0];
                    cmp_b = info.arguments[1];
                }
            }
        }
    }
    if cmp_op != squid_check_core::Op.less && cmp_op != squid_check_core::Op.greater {
        return false, false;
    }
    let is_lt = cmp_op == squid_check_core::Op.less;
    if sameSparkMinMaxLeaf(m, cmp_a, then_id) && sameSparkMinMaxLeaf(m, cmp_b, else_id) {
        return true, is_lt;
    }
    if sameSparkMinMaxLeaf(m, cmp_a, else_id) && sameSparkMinMaxLeaf(m, cmp_b, then_id) {
        return true, !is_lt;
    }
    return false, false;
}

// Matches a pure vectorizable F32 multiplication `x * y` for `--relaxed-simd` FMA fusion.
fn matchVecF32Mul(g: Generator&, m: const Module&, env: const Env&, id: u32) -> bool, u32, u32 {
    if id == 0 { return false, 0, 0; }
    let n = m.node(id);
    if n.tag != squid_check_core::Tag.scalar && n.tag != squid_check_core::Tag.associated { return false, 0, 0; }
    if n.b == 0 { return false, 0, 0; }
    let a_ty, a_ok = lowerInEnv(g, m, m.typeOf(n.a), env);
    if !a_ok || tagOf(g, a_ty) != squid_direct_types::Tag.f32_ { return false, 0, 0; }
    let is_assoc = n.tag == squid_check_core::Tag.associated;
    let use_disp = is_assoc || n.c == 1;
    var member: u32 = 0;
    if is_assoc { member = n.c; }
    let machine, _s1, _s2 = resolveSparkScalarOp(g, m, n.op, member, use_disp, a_ty);
    if machine != squid_check_core::Op.mul { return false, 0, 0; }
    return true, n.a, n.b;
}

// Returns true when `id` is guaranteed finite and bounded (|x| <= 2^33) in every SIMD lane.
fn isBoundedLeafVecF32(g: Generator&, f: const Fn&, plan: const SparkVecPlan&, m: const Module&, env: const Env&, id: u32) -> bool {
    let n = m.node(id);
    if n.tag == squid_check_core::Tag.constant {
        let exp = (n.a >> 23) & 0xff;
        return exp < 157;
    }
    if n.tag == squid_check_core::Tag.reference {
        let b = localRef(m, id);
        if b != 0 {
            if hasFiniteF32(f, b) { return true; }
            let lidx = findVecLocal(plan, m.unit, b);
            if lidx >= 0 && plan.locals[lidx].finite { return true; }
        }
        return false;
    }
    if n.tag == squid_check_core::Tag.scalar || n.tag == squid_check_core::Tag.associated {
        let a_ty, _ = lowerInEnv(g, m, m.typeOf(n.a), env);
        let is_assoc = n.tag == squid_check_core::Tag.associated;
        let use_disp = is_assoc || n.c == 1;
        var member: u32 = 0;
        if is_assoc { member = n.c; }
        let machine, _s1, _s2 = resolveSparkScalarOp(g, m, n.op, member, use_disp, a_ty);
        return machine == squid_check_core::Op.convert_u32_f32 || machine == squid_check_core::Op.convert_i32_f32;
    }
    if n.tag == squid_check_core::Tag.call {
        let info = m.call(id);
        let target = recordAliasChain(g, g.resolve(m, info.target));
        let tm .= g.units[target.unit - 1];
        let alias, has_alias = primitiveAlias(tm, target.binding);
        if has_alias {
            let pop = tm.primitive(alias).op;
            return pop == squid_check_core::Op.convert_u32_f32 || pop == squid_check_core::Op.convert_i32_f32;
        }
    }
    return false;
}
// Returns true when `id` is guaranteed to evaluate to a strictly finite (non-NaN, non-Inf) F32
// small enough that combining two such values with add/sub (or two leaves with mul) cannot overflow.
fn isFiniteVecF32(g: Generator&, f: const Fn&, plan: const SparkVecPlan&, m: const Module&, env: const Env&, id: u32, allow_compound: bool) -> bool {
    if isBoundedLeafVecF32(g, f, plan, m, env, id) { return true; }
    if !allow_compound { return false; }
    let n = m.node(id);
    if (n.tag == squid_check_core::Tag.scalar || n.tag == squid_check_core::Tag.associated) && n.b != 0 {
        let a_ty, a_ok = lowerInEnv(g, m, m.typeOf(n.a), env);
        if !a_ok || tagOf(g, a_ty) != squid_direct_types::Tag.f32_ { return false; }
        let is_assoc = n.tag == squid_check_core::Tag.associated;
        let use_disp = is_assoc || n.c == 1;
        var member: u32 = 0;
        if is_assoc { member = n.c; }
        let machine, _s1, _s2 = resolveSparkScalarOp(g, m, n.op, member, use_disp, a_ty);
        if machine == squid_check_core::Op.mul || machine == squid_check_core::Op.add || machine == squid_check_core::Op.sub {
            return isBoundedLeafVecF32(g, f, plan, m, env, n.a) && isBoundedLeafVecF32(g, f, plan, m, env, n.b);
        }
    }
    return false;
}

// Emits a vectorized Core expression, leaving one `v128` value on top of the stack.
// Invariant: Bool values are ALWAYS SIMD masks (0x00000000 or 0xffffffff per lane).
recursive fn emitVecExpr(
    g: Generator&,
    f: Fn&,
    plan: SparkVecPlan&,
    m: const Module&,
    env: const Env&,
    id: u32,
    elide_nan: bool,
) -> Error {
    let n = m.node(id);
    match n.tag {
        constant => {
            squid_direct_relocations::unpatchableOperand(m.unit, id);
            let ty, _ = lowerInEnv(g, m, m.typeOf(id), env);
            if tagOf(g, ty) == squid_direct_types::Tag.boolean {
                if n.a != 0 { v128Const4(g, 0xffffffff); } else { v128Const4(g, 0); }
            } else {
                v128Const4(g, n.a);
            }
            return squid_direct_types::Error.none;
        },
        reference => {
            let ref = m.reference(id);
            if ref.unit == 0 || ref.unit == m.unit {
                let vidx = findVecLocal(plan, m.unit, ref.binding);
                if vidx >= 0 {
                    lget(g, plan.locals[vidx].vlocal);
                    return squid_direct_types::Error.none;
                }
                if m.unit == f.unit {
                    let hidx = findHoistedScalar(plan, m.unit, ref.binding);
                    if hidx >= 0 && plan.hoisted[hidx].vlocal != 0xffffffff {
                        lget(g, plan.hoisted[hidx].vlocal);
                        return squid_direct_types::Error.none;
                    }
                    let bound, present = bindGet(g, f, ref.binding);
                    if present {
                        let btag = tagOf(g, bound.ty);
                        if btag == squid_direct_types::Tag.boolean {
                            i32Const(g, 0);
                            lget(g, w(g, bound, 0));
                            op(g, OP_i32_sub);
                            simdOp(g, SIMD_i32x4_splat);
                        } else if btag == squid_direct_types::Tag.f32_ {
                            lget(g, w(g, bound, 0));
                            simdOp(g, SIMD_f32x4_splat);
                        } else {
                            lget(g, w(g, bound, 0));
                            simdOp(g, SIMD_i32x4_splat);
                        }
                        return squid_direct_types::Error.none;
                    }
                }
            }
            let target = g.resolve(m, ref);
            let tm .= g.units[target.unit - 1];
            let body .= tm.body(target.binding);
            assert(body);
            g.recordInlined(target.unit, target.binding);
            squid_direct_relocations::unpatchableOperand(target.unit, body.root);
            let rn = tm.node(body.root);
            let ty, _ = lowerInEnv(g, m, m.typeOf(id), env);
            if tagOf(g, ty) == squid_direct_types::Tag.boolean {
                if rn.a != 0 { v128Const4(g, 0xffffffff); } else { v128Const4(g, 0); }
            } else {
                v128Const4(g, rn.a);
            }
            return squid_direct_types::Error.none;
        },
        scalar, associated => {
            let res_ty, _ = lowerInEnv(g, m, m.typeOf(id), env);
            let a_ty, _ = lowerInEnv(g, m, m.typeOf(n.a), env);
            let a_tag = tagOf(g, a_ty);
            let is_assoc = n.tag == squid_check_core::Tag.associated;
            let use_disp = is_assoc || n.c == 1;
            var member: u32 = 0;
            if is_assoc { member = n.c; }
            let machine, disp_target, _ = resolveSparkScalarOp(g, m, n.op, member, use_disp, a_ty);
            if machine == squid_check_core::Op.none {
                if n.b != 0 {
                    var pair: u32[2] = [n.a, n.b];
                    return emitVecCall(g, f, plan, m, env, disp_target, pair[..], res_ty, elide_nan);
                }
                var one: u32[1] = [n.a];
                return emitVecCall(g, f, plan, m, env, disp_target, one[..], res_ty, elide_nan);
            }
            if disp_target.binding != 0 { g.recordInlined(disp_target.unit, disp_target.binding); }
            let child_elide = a_tag == squid_direct_types::Tag.f32_ && isCanonicalF32Consumer(machine);
            // Opt-in Wasm 3.0 `--relaxed-simd` FMA fusion:
            //   (x * y) + z | z + (x * y) => f32x4.relaxed_madd(x, y, z)
            //   z - (x * y)               => f32x4.relaxed_nmadd(x, y, z)
            if squid_direct_writer::relaxedSimdEnabled() && a_tag == squid_direct_types::Tag.f32_ && n.b != 0 {
                if machine == squid_check_core::Op.add {
                    let ok_a, mx, my = matchVecF32Mul(g, m, env, n.a);
                    if ok_a {
                        let e1 = emitVecExpr(g, f, plan, m, env, mx, true);
                        if e1 != squid_direct_types::Error.none { return e1; }
                        let e2 = emitVecExpr(g, f, plan, m, env, my, true);
                        if e2 != squid_direct_types::Error.none { return e2; }
                        let e3 = emitVecExpr(g, f, plan, m, env, n.b, true);
                        if e3 != squid_direct_types::Error.none { return e3; }
                        simdOp(g, SIMD_f32x4_relaxed_madd);
                        if !elide_nan && !f.defer_f32_nan { canonicalizeF32x4(g, f, plan.nan_vlocal); }
                        return squid_direct_types::Error.none;
                    }
                    let ok_b, rx, ry = matchVecF32Mul(g, m, env, n.b);
                    if ok_b {
                        let e1 = emitVecExpr(g, f, plan, m, env, rx, true);
                        if e1 != squid_direct_types::Error.none { return e1; }
                        let e2 = emitVecExpr(g, f, plan, m, env, ry, true);
                        if e2 != squid_direct_types::Error.none { return e2; }
                        let e3 = emitVecExpr(g, f, plan, m, env, n.a, true);
                        if e3 != squid_direct_types::Error.none { return e3; }
                        simdOp(g, SIMD_f32x4_relaxed_madd);
                        if !elide_nan && !f.defer_f32_nan { canonicalizeF32x4(g, f, plan.nan_vlocal); }
                        return squid_direct_types::Error.none;
                    }
                } else if machine == squid_check_core::Op.sub {
                    let ok_b, rx, ry = matchVecF32Mul(g, m, env, n.b);
                    if ok_b {
                        let e1 = emitVecExpr(g, f, plan, m, env, rx, true);
                        if e1 != squid_direct_types::Error.none { return e1; }
                        let e2 = emitVecExpr(g, f, plan, m, env, ry, true);
                        if e2 != squid_direct_types::Error.none { return e2; }
                        let e3 = emitVecExpr(g, f, plan, m, env, n.a, true);
                        if e3 != squid_direct_types::Error.none { return e3; }
                        simdOp(g, SIMD_f32x4_relaxed_nmadd);
                        if !elide_nan && !f.defer_f32_nan { canonicalizeF32x4(g, f, plan.nan_vlocal); }
                        return squid_direct_types::Error.none;
                    }
                }
            }
            // Exact IEEE-754 peephole: `2.0 * x` == `x + x` (avoids v128.const + uses addps).
            if machine == squid_check_core::Op.mul && a_tag == squid_direct_types::Tag.f32_ && n.b != 0 {
                var doubled_id: u32 = 0;
                if m.node(n.a).tag == squid_check_core::Tag.constant && m.node(n.a).a == 0x40000000 {
                    squid_direct_relocations::unpatchableOperand(m.unit, n.a);
                    doubled_id = n.b;
                } else if m.node(n.b).tag == squid_check_core::Tag.constant && m.node(n.b).a == 0x40000000 {
                    squid_direct_relocations::unpatchableOperand(m.unit, n.b);
                    doubled_id = n.a;
                }
                if doubled_id != 0 {
                    let derr = emitVecExpr(g, f, plan, m, env, doubled_id, child_elide);
                    if derr != squid_direct_types::Error.none { return derr; }
                    let dtmp = local(g, f, VT_v128);
                    ltee(g, dtmp);
                    lget(g, dtmp);
                    emitSimdMachineOp(g, f, squid_check_core::Op.add, a_tag, elide_nan, plan.nan_vlocal);
                    return squid_direct_types::Error.none;
                }
            }
            // Lower `f32x4` `>` / `>=` as operand-swapped `f32x4.lt` / `f32x4.le` (100% IEEE-754 identical,
            // including NaNs and signed zeroes, while avoiding `prep_swap` register clobbering under spill).
            if a_tag == squid_direct_types::Tag.f32_ && n.b != 0 &&
                (machine == squid_check_core::Op.greater || machine == squid_check_core::Op.greater_equal) {
                let rerr = emitVecExpr(g, f, plan, m, env, n.b, child_elide);
                if rerr != squid_direct_types::Error.none { return rerr; }
                let lerr = emitVecExpr(g, f, plan, m, env, n.a, child_elide);
                if lerr != squid_direct_types::Error.none { return lerr; }
                let swapped = if machine == squid_check_core::Op.greater {
                    squid_check_core::Op.less
                } else {
                    squid_check_core::Op.less_equal
                };
                emitSimdMachineOp(g, f, swapped, a_tag, elide_nan, plan.nan_vlocal);
                return squid_direct_types::Error.none;
            }
            let lerr = emitVecExpr(g, f, plan, m, env, n.a, child_elide);
            if lerr != squid_direct_types::Error.none { return lerr; }
            if n.b != 0 {
                if isShiftOp(machine) {
                    let s_loc, serr = emitInvariantU32(g, f, plan, m, env, n.b);
                    if serr != squid_direct_types::Error.none { return serr; }
                    lget(g, s_loc);
                } else {
                    let rerr = emitVecExpr(g, f, plan, m, env, n.b, child_elide);
                    if rerr != squid_direct_types::Error.none { return rerr; }
                }
            }
            let allow_comp = machine == squid_check_core::Op.add || machine == squid_check_core::Op.sub;
            let finite_no_nan = a_tag == squid_direct_types::Tag.f32_ && n.b != 0 &&
                (allow_comp || machine == squid_check_core::Op.mul) &&
                isFiniteVecF32(g, f, plan, m, env, n.a, allow_comp) && isFiniteVecF32(g, f, plan, m, env, n.b, allow_comp);
            emitSimdMachineOp(g, f, machine, a_tag, elide_nan || finite_no_nan, plan.nan_vlocal);
            return squid_direct_types::Error.none;
        },
        logical => {
            let lerr = emitVecExpr(g, f, plan, m, env, n.a, false);
            if lerr != squid_direct_types::Error.none { return lerr; }
            let rerr = emitVecExpr(g, f, plan, m, env, n.b, false);
            if rerr != squid_direct_types::Error.none { return rerr; }
            if n.op == squid_check_core::Op.and_ { simdOp(g, SIMD_v128_and); } else { simdOp(g, SIMD_v128_or); }
            return squid_direct_types::Error.none;
        },
        if_value => {
            if squid_direct_writer::relaxedSimdEnabled() {
                let is_mm, is_min = matchRelaxedF32MinMax(g, m, env, n.a, n.b, n.c);
                if is_mm {
                    let terr = emitVecExpr(g, f, plan, m, env, n.b, false);
                    if terr != squid_direct_types::Error.none { return terr; }
                    let eerr = emitVecExpr(g, f, plan, m, env, n.c, false);
                    if eerr != squid_direct_types::Error.none { return eerr; }
                    if is_min { simdOp(g, SIMD_f32x4_relaxed_min); }
                    else { simdOp(g, SIMD_f32x4_relaxed_max); }
                    return squid_direct_types::Error.none;
                }
            }
            // Never elide NaN canonicalization across `if`/`select`.
            let terr = emitVecExpr(g, f, plan, m, env, n.b, false);
            if terr != squid_direct_types::Error.none { return terr; }
            let eerr = emitVecExpr(g, f, plan, m, env, n.c, false);
            if eerr != squid_direct_types::Error.none { return eerr; }
            let cerr = emitVecExpr(g, f, plan, m, env, n.a, false);
            if cerr != squid_direct_types::Error.none { return cerr; }
            simdOp(g, SIMD_v128_bitselect);
            return squid_direct_types::Error.none;
        },
        return_ => {
            return emitVecExpr(g, f, plan, m, env, n.a, elide_nan);
        },
        block_, suite => {
            let child_len = m.children(id).len;
            let mark = plan.locals_len;
            for at in 0..(child_len - 1) {
                let child = m.children(id)[at];
                let cn = m.node(child);
                if cn.tag == squid_check_core::Tag.bind {
                    let bty, _ = lowerInEnv(g, m, m.typeOf(cn.b), env);
                    let btag = tagOf(g, bty);
                    // Bindings may be used by neg/abs/if/store -> never elide NaN.
                    let berr = emitVecExpr(g, f, plan, m, env, cn.b, false);
                    if berr != squid_direct_types::Error.none { plan.locals_len = mark; return berr; }
                    let vl = local(g, f, VT_v128);
                    lset(g, vl);
                    var inv = false;
                    var sl: u32 = 0xffffffff;
                    if btag == squid_direct_types::Tag.u32_ && isInvariantScalarExpr(g, f, plan, m, env, cn.b, squid_direct_types::Tag.u32_, 0) {
                        let sloc, serr = emitInvariantU32(g, f, plan, m, env, cn.b);
                        if serr != squid_direct_types::Error.none { plan.locals_len = mark; return serr; }
                        inv = true;
                        sl = sloc;
                    }
                    plan.locals[plan.locals_len] = SparkVecLocal {
                        unit: m.unit,
                        binding: cn.a,
                        tag: btag,
                        vlocal: vl,
                        is_mask: btag == squid_direct_types::Tag.boolean,
                        invariant: inv,
                        scalar_local: sl,
                    };
                    plan.locals_len += 1;
                } else {
                    let pat = m.pattern(cn.a);
                    let bty, _ = lowerInEnv(g, m, m.typeOf(cn.b), env);
                    let btag = tagOf(g, bty);
                    let berr = emitVecExpr(g, f, plan, m, env, cn.b, false);
                    if berr != squid_direct_types::Error.none { plan.locals_len = mark; return berr; }
                    if pat.tag == squid_check_core::PatternTag.bind {
                        let vl = local(g, f, VT_v128);
                        lset(g, vl);
                        var inv = false;
                        var sl: u32 = 0xffffffff;
                        if btag == squid_direct_types::Tag.u32_ && isInvariantScalarExpr(g, f, plan, m, env, cn.b, squid_direct_types::Tag.u32_, 0) {
                            let sloc, serr = emitInvariantU32(g, f, plan, m, env, cn.b);
                            if serr != squid_direct_types::Error.none { plan.locals_len = mark; return serr; }
                            inv = true;
                            sl = sloc;
                        }
                        plan.locals[plan.locals_len] = SparkVecLocal {
                            unit: m.unit,
                            binding: pat.a,
                            tag: btag,
                            vlocal: vl,
                            is_mask: btag == squid_direct_types::Tag.boolean,
                            invariant: inv,
                            scalar_local: sl,
                        };
                        plan.locals_len += 1;
                    } else {
                        op(g, OP_drop);
                    }
                }
            }
            let last_err = emitVecExpr(g, f, plan, m, env, m.children(id)[child_len - 1], elide_nan);
            plan.locals_len = mark;
            return last_err;
        },
        call => {
            let info = m.call(id);
            let res_ty, _ = lowerInEnv(g, m, m.typeOf(id), env);
            let target = g.resolve(m, info.target);
            return emitVecCall(g, f, plan, m, env, target, info.arguments, res_ty, elide_nan);
        },
        project => {
            let proj = m.projection(n.b);
            let res_ty, _ = lowerInEnv(g, m, m.typeOf(id), env);
            let recv_ty, _ = lowerInEnv(g, m, m.typeOf(n.a), env);
            let identity, _ = g.receiverIdentity(recv_ty);
            let target, _ = g.dispatchTarget(m, identity, proj.field, squid_check_types::Operator.none);
            var one: u32[1] = [n.a];
            return emitVecCall(g, f, plan, m, env, target, one[..], res_ty, elide_nan);
        },
        array_op, storage => {
            let sidx = findAffineStream(plan, m.unit, id);
            assert(sidx >= 0);
            let st = plan.streams[sidx];
            if st.elem_tag == squid_direct_types::Tag.boolean {
                // Widen 4 byte-packed [0|1] Bool elements to full SIMD lane masks [0x00000000|0xffffffff].
                emitLoadBool4Mask(g, st.ptr_local, plan.index_local, plan.unroll_step * 4);
            } else {
                lget(g, st.ptr_local);
                if plan.byte_off_local != 0xffffffff {
                    lget(g, plan.byte_off_local);
                    op(g, OP_i32_add);
                }
                simdMemOp(g, SIMD_v128_load, 2, plan.unroll_step * 16);
            }
            return squid_direct_types::Error.none;
        },
        _ => { return g.fail(m, id, "unexpected expression during SIMD spark emission"); },
    }
}

// Resolves the contiguous backing base pointer and logical element length for
// a scalar container (`array`, `grow`, `resize`, or `view`).
fn containerBaseAndLen(g: Generator&, f: Fn&, val: Val, id: u32) -> u32, u32, Error {
    let tag = tagOf(g, val.ty);
    if tag == squid_direct_types::Tag.view {
        let elem_tag = tagOf(g, g.types.node(val.ty).a);
        let backing_base = baseOf(g, f, val);
        let ptr = local32(g, f);
        lget(g, backing_base);
        lget(g, w(g, val, 2));
        if elem_tag != squid_direct_types::Tag.boolean {
            i32Const(g, 2);
            op(g, OP_i32_shl);
        }
        op(g, OP_i32_add);
        lset(g, ptr);
        return ptr, w(g, val, 3), squid_direct_types::Error.none;
    }
    if tag == squid_direct_types::Tag.array {
        let base, len = ensureCheckedArray(g, f, val);
        return base, len, squid_direct_types::Error.none;
    }
    let len, lerr = lengthOf(g, f, val, id);
    if lerr != squid_direct_types::Error.none { return 0, 0, lerr; }
    let base = baseOf(g, f, val);
    return base, len, squid_direct_types::Error.none;
}

// Entry point called by `sparkNode` after evaluating source/count and allocating
// `handle` / `out_base`. Attempts 4-wide Wasm SIMD emission for `[0 .. simd_end)`
// and returns `(vectorized, next_index_local, error)`.
// When `vectorized == true`, caller runs the scalar tail from `next_index_local..count`.
fn tryEmitVectorSpark(
    g: Generator&,
    f: Fn&,
    id: u32,
    out_ty: Ty,
    elem_ty: Ty,
    start_local: u32,
    source_val: Val,
    count: u32,
    out_base: u32,
) -> bool, u32, Error {
    let m .= g.units[f.unit - 1];
    let info = m.sparkInfo(id);
    let out_tag = tagOf(g, elem_ty);
    if !isSparkLaneTag(out_tag) { return false, 0, squid_direct_types::Error.none; }

    var iter_tag = squid_direct_types::Tag.u32_;
    if !info.is_range {
        let src_elem_tag, src_ok = isContiguousScalarContainer(g, source_val.ty);
        if !src_ok { return false, 0, squid_direct_types::Error.none; }
        iter_tag = src_elem_tag;
    }

    var iter_binding: u32 = 0;
    if info.pattern != 0 {
        let pat = m.pattern(info.pattern);
        if pat.tag == squid_check_core::PatternTag.bind {
            iter_binding = pat.a;
        } else if pat.tag != squid_check_core::PatternTag.wildcard {
            return false, 0, squid_direct_types::Error.none;
        }
    }

    var plan = SparkVecPlan {
        spark_unit: m.unit,
        is_range: info.is_range,
        iter_binding: iter_binding,
        iter_tag: iter_tag,
        out_tag: out_tag,
    };
    if iter_binding != 0 {
        plan.locals[0] = SparkVecLocal {
            unit: m.unit,
            binding: iter_binding,
            tag: iter_tag,
            is_mask: iter_tag == squid_direct_types::Tag.boolean,
            invariant: false,
        };
        plan.locals_len = 1;
    }

    if !checkVecExpr(g, f, plan, m, f.env, info.body, 0, 0, false) {
        return false, 0, squid_direct_types::Error.none;
    }

    // Vectorizable! Emit 4-wide SIMD loop + pre-loop range-affine stream guards.
    g.s.sparks_vectorized += 1;

    var src_base: u32 = 0;
    if !info.is_range {
        let sb, _, sberr = containerBaseAndLen(g, f, source_val, id);
        if sberr != squid_direct_types::Error.none { return false, 0, sberr; }
        src_base = sb;
    }

    let simd_end = local32(g, f);
    lget(g, count);
    i32Const(g, 0xfffffffc);
    op(g, OP_i32_and);
    lset(g, simd_end);

    // Pre-loop unsigned wrapping-safe proof for every range-affine stream:
    //   base_idx = offset + start >=_u offset
    //   base_idx + len >=_u base_idx
    //   base_idx + len <=_u arr.len
    // If any stream fails at runtime, set simd_end = 0 so execution falls
    // cleanly into the scalar loop preserving exact wrapping and trap order.
    let start_is_zero = info.is_range && g.units[f.unit - 1].node(info.source).tag == squid_check_core::Tag.constant && g.units[f.unit - 1].node(info.source).a == 0;
    if plan.streams_len != 0 {
        for si in 0..plan.streams_len {
            let st = plan.streams[si];
            var dup_ptr: u32 = 0xffffffff;
            for sj in 0..si {
                let prev = plan.streams[sj];
                let pm .= g.units[f.unit - 1];
                let cur_arr_b = localRef(pm, st.arr_id);
                let prev_arr_b = localRef(pm, prev.arr_id);
                if cur_arr_b != 0 && cur_arr_b == prev_arr_b && prev.elem_tag == st.elem_tag && sameOffsetExpr(pm, st.offset_id, prev.offset_id) {
                    dup_ptr = prev.ptr_local;
                    break;
                }
            }
            if dup_ptr != 0xffffffff {
                plan.streams[si].ptr_local = dup_ptr;
                continue;
            }
            let arr_val, aerr = expr(g, f, st.arr_id);
            if aerr != squid_direct_types::Error.none { return false, 0, aerr; }
            let arr_base, arr_len, blerr = containerBaseAndLen(g, f, arr_val, st.node_id);
            if blerr != squid_direct_types::Error.none { return false, 0, blerr; }

            if start_is_zero && st.offset_id == 0 {
                lget(g, count);
                lget(g, arr_len);
                op(g, OP_i32_gt_u);
                let guard_if = open(g, f, OP_if_);
                i32Const(g, 0);
                lset(g, simd_end);
                close(g, f);
                plan.streams[si].ptr_local = arr_base;
            } else {
                var offset_local: u32 = 0;
                if st.offset_id != 0 {
                    let off_loc, oerr = emitInvariantU32(g, f, plan, g.units[f.unit - 1], f.env, st.offset_id);
                    if oerr != squid_direct_types::Error.none { return false, 0, oerr; }
                    offset_local = off_loc;
                } else {
                    offset_local = constLocal(g, f, 0);
                }

                let base_idx = local32(g, f);
                lget(g, offset_local);
                lget(g, start_local);
                op(g, OP_i32_add);
                ltee(g, base_idx);

                let end_idx = local32(g, f);
                lget(g, count);
                op(g, OP_i32_add);
                lset(g, end_idx);

                // ok = (base_idx >=_u offset) & (end_idx >=_u base_idx) & (end_idx <=_u arr_len)
                lget(g, base_idx);
                lget(g, offset_local);
                op(g, OP_i32_ge_u);
                lget(g, end_idx);
                lget(g, base_idx);
                op(g, OP_i32_ge_u);
                op(g, OP_i32_and);
                lget(g, end_idx);
                lget(g, arr_len);
                op(g, OP_i32_le_u);
                op(g, OP_i32_and);
                op(g, OP_i32_eqz);
                let guard_if = open(g, f, OP_if_);
                i32Const(g, 0);
                lset(g, simd_end);
                close(g, f);

                let stream_ptr = local32(g, f);
                lget(g, arr_base);
                lget(g, base_idx);
                if st.elem_tag != squid_direct_types::Tag.boolean {
                    i32Const(g, 2);
                    op(g, OP_i32_shl);
                }
                op(g, OP_i32_add);
                lset(g, stream_ptr);
                plan.streams[si].ptr_local = stream_ptr;
            }
        }
    }

    let index = constLocal(g, f, 0);
    let byte_off = constLocal(g, f, 0);
    plan.index_local = index;
    plan.byte_off_local = byte_off;

    // Pre-splat outer loop-invariant scalar captures and canonical NaN vector once before OP_loop.
    for hi in 0..plan.hoisted_len {
        let h = plan.hoisted[hi];
        let vl = local(g, f, VT_v128);
        if h.tag == squid_direct_types::Tag.boolean {
            i32Const(g, 0);
            lget(g, h.scalar_local);
            op(g, OP_i32_sub);
            simdOp(g, SIMD_i32x4_splat);
        } else if h.tag == squid_direct_types::Tag.f32_ {
            lget(g, h.scalar_local);
            simdOp(g, SIMD_f32x4_splat);
        } else {
            lget(g, h.scalar_local);
            simdOp(g, SIMD_i32x4_splat);
        }
        lset(g, vl);
        plan.hoisted[hi].vlocal = vl;
    }
    if plan.uses_f32_canon && !f.defer_f32_nan {
        let nl = local(g, f, VT_v128);
        v128Const4(g, 0x7fc00000);
        lset(g, nl);
        plan.nan_vlocal = nl;
    }

    let need_iter_vlocal = iter_binding != 0 && plan.iter_value_used;
    var iter_vlocal: u32 = 0;
    var v4_local: u32 = 0;
    if need_iter_vlocal {
        iter_vlocal = local(g, f, VT_v128);
        plan.locals[0].vlocal = iter_vlocal;
        if info.is_range {
            lget(g, start_local);
            simdOp(g, SIMD_i32x4_splat);
            v128ConstWords(g, 0, 1, 2, 3);
            simdOp(g, SIMD_i32x4_add);
            lset(g, iter_vlocal);
            v4_local = local(g, f, VT_v128);
            v128Const4(g, 4);
            lset(g, v4_local);
        }
    }

    // 4x unrolled 16-element SIMD loop (64-byte cache line per iteration) ahead of 4-element tail.
    if plan.streams_len <= 8 && plan.budget >= 80 {
        let simd16_end = local32(g, f);
        lget(g, simd_end);
        i32Const(g, 0xfffffff0);
        op(g, OP_i32_and);
        lset(g, simd16_end);

        let cur_out = local32(g, f);
        var cur_src: u32 = 0;
        if !info.is_range && need_iter_vlocal { cur_src = local32(g, f); }
        var orig_ptrs: u32[8] = [0; 8];
        var cur_ptrs: u32[8] = [0; 8];
        for si in 0..plan.streams_len {
            orig_ptrs[si] = plan.streams[si].ptr_local;
            var reused: u32 = 0xffffffff;
            if orig_ptrs[si] == out_base && (plan.streams[si].elem_tag == squid_direct_types::Tag.boolean) == (out_tag == squid_direct_types::Tag.boolean) {
                reused = cur_out;
            } else {
                for sj in 0..si {
                    if orig_ptrs[sj] == orig_ptrs[si] && (plan.streams[sj].elem_tag == squid_direct_types::Tag.boolean) == (plan.streams[si].elem_tag == squid_direct_types::Tag.boolean) {
                        reused = cur_ptrs[sj];
                        break;
                    }
                }
            }
            if reused != 0xffffffff { cur_ptrs[si] = reused; } else { cur_ptrs[si] = local32(g, f); }
        }

        let u16_exit = open(g, f, OP_block);
        let u16_top = open(g, f, OP_loop);
        lget(g, index);
        lget(g, simd16_end);
        op(g, OP_i32_ge_u);
        br(g, f, OP_br_if, u16_exit);

        lget(g, out_base);
        if out_tag == squid_direct_types::Tag.boolean { lget(g, index); } else { lget(g, byte_off); }
        op(g, OP_i32_add);
        lset(g, cur_out);

        if !info.is_range && need_iter_vlocal {
            lget(g, src_base);
            if iter_tag == squid_direct_types::Tag.boolean { lget(g, index); } else { lget(g, byte_off); }
            op(g, OP_i32_add);
            lset(g, cur_src);
        }

        for si in 0..plan.streams_len {
            var is_dup = cur_ptrs[si] == cur_out;
            if !is_dup {
                for sj in 0..si {
                    if cur_ptrs[sj] == cur_ptrs[si] { is_dup = true; break; }
                }
            }
            if !is_dup {
                lget(g, orig_ptrs[si]);
                if plan.streams[si].elem_tag == squid_direct_types::Tag.boolean { lget(g, index); } else { lget(g, byte_off); }
                op(g, OP_i32_add);
                lset(g, cur_ptrs[si]);
            }
            plan.streams[si].ptr_local = cur_ptrs[si];
        }
        plan.index_local = 0xffffffff;
        plan.byte_off_local = 0xffffffff;

        for ustep in 0..4 {
            var step = ustep;
            if !need_iter_vlocal { step = 3 - ustep; }
            plan.unroll_step = step as u32;
            if !info.is_range && need_iter_vlocal {
                if iter_tag == squid_direct_types::Tag.boolean {
                    emitLoadBool4Mask(g, cur_src, 0xffffffff, (step as u32) * 4);
                    lset(g, iter_vlocal);
                } else {
                    lget(g, cur_src);
                    simdMemOp(g, SIMD_v128_load, 2, (step as u32) * 16);
                    lset(g, iter_vlocal);
                }
            }
            lget(g, cur_out);
            let step_err = emitVecExpr(g, f, plan, g.units[f.unit - 1], f.env, info.body, false);
            if step_err != squid_direct_types::Error.none { return false, 0, step_err; }
            if out_tag == squid_direct_types::Tag.boolean {
                emitStoreBool4Mask(g, f, (step as u32) * 4);
            } else {
                simdMemOp(g, SIMD_v128_store, 2, (step as u32) * 16);
            }
            if info.is_range && need_iter_vlocal {
                lget(g, iter_vlocal);
                lget(g, v4_local);
                simdOp(g, SIMD_i32x4_add);
                lset(g, iter_vlocal);
            }
        }

        for si in 0..plan.streams_len { plan.streams[si].ptr_local = orig_ptrs[si]; }
        plan.index_local = index;
        plan.byte_off_local = byte_off;
        plan.unroll_step = 0;

        lget(g, index);
        i32Const(g, 16);
        op(g, OP_i32_add);
        lset(g, index);

        lget(g, byte_off);
        i32Const(g, 64);
        op(g, OP_i32_add);
        lset(g, byte_off);

        br(g, f, OP_br, u16_top);
        close(g, f);
        close(g, f);
    }

    let simd_exit = open(g, f, OP_block);
    let simd_top = open(g, f, OP_loop);
    lget(g, index);
    lget(g, simd_end);
    op(g, OP_i32_ge_u);
    br(g, f, OP_br_if, simd_exit);

    if !info.is_range && need_iter_vlocal {
        if iter_tag == squid_direct_types::Tag.boolean {
            emitLoadBool4Mask(g, src_base, index, 0);
            lset(g, iter_vlocal);
        } else {
            lget(g, src_base);
            lget(g, byte_off);
            op(g, OP_i32_add);
            simdMemOp(g, SIMD_v128_load, 2, 0);
            lset(g, iter_vlocal);
        }
    }

    // Store address first on stack, then computed 4-lane vector, then store!
    lget(g, out_base);
    if out_tag == squid_direct_types::Tag.boolean {
        lget(g, index);
    } else {
        lget(g, byte_off);
    }
    op(g, OP_i32_add);

    let body_err = emitVecExpr(g, f, plan, g.units[f.unit - 1], f.env, info.body, false);
    if body_err != squid_direct_types::Error.none { return false, 0, body_err; }

    if out_tag == squid_direct_types::Tag.boolean {
        // Normalize SIMD lane masks [0x00000000|0xffffffff] -> 4 packed [0|1] bytes and store!
        emitStoreBool4Mask(g, f, 0);
    } else {
        simdMemOp(g, SIMD_v128_store, 2, 0);
    }

    // Advance index (+4), byte_off (+16), and range iter_vec (+[4,4,4,4]).
    lget(g, index);
    i32Const(g, 4);
    op(g, OP_i32_add);
    lset(g, index);

    lget(g, byte_off);
    i32Const(g, 16);
    op(g, OP_i32_add);
    lset(g, byte_off);

    if info.is_range && need_iter_vlocal {
        lget(g, iter_vlocal);
        lget(g, v4_local);
        simdOp(g, SIMD_i32x4_add);
        lset(g, iter_vlocal);
    }

    br(g, f, OP_br, simd_top);
    close(g, f);
    close(g, f);

    return true, index, squid_direct_types::Error.none;
}

// Auto-vectorizes simple in-place range `for` loops of the form:
//   for col in start .. end:
//     [let idx = off + col | let tmp = pure_vec_expr]*
//     dst[dst_off + col] := pure_vec_expr(dst[dst_off + col], src[src_off + col], ...)
// Emits a 4-wide Wasm `v128` SIMD loop ahead of the caller's scalar loop, guarded
// by runtime bounds, non-wrapping, and strict alias/disjointness checks (setting
// `simd_end = 0` on any overlap other than exact `stream_ptr == dst_ptr` so loop-
// carried dependencies like `a[i + 1] := a[i] + 1` fall cleanly to the scalar loop).
// Advances `index` by the number of elements handled in SIMD so the caller's scalar
// loop seamlessly executes any 0..3 element tail (or the full loop on guard fallback).
fn tryEmitVectorForLoop(
    g: Generator&,
    f: Fn&,
    loop_id: u32,
    info: squid_check_core::LoopInfo,
    carry_in_place: const bool[64]&,
    index: u32,
    end_local: u32,
) -> Error {
    if g.runtime_().has_fork { return squid_direct_types::Error.none; }
    if info.kind != squid_check_core::LoopKind.range || info.pattern == 0 || info.body == 0 {
        return squid_direct_types::Error.none;
    }

    var iter_binding: u32 = 0;
    var dst_count: i64 = 0;
    var dst_bs: u32[4] = [0; 4];
    var dst_vals: Val[4] = [neverVal(); 4];
    var dst_tags: squid_direct_types::Tag[4] = [squid_direct_types::Tag.unit; 4];
    var dst_offs: u32[4] = [0; 4];
    var rhs_ids: u32[4] = [0; 4];
    var lead_bind_ids: u32[8] = [0; 8];
    var lead_bind_exprs: u32[8] = [0; 8];
    var lead_bind_tags: squid_direct_types::Tag[8] = [squid_direct_types::Tag.unit; 8];
    var lead_bind_len: i64 = 0;
    var plan = SparkVecPlan {};
    var matched = false;

    {
        let m .= g.units[f.unit - 1];
        let pat = m.pattern(info.pattern);
        if pat.tag != squid_check_core::PatternTag.bind { return squid_direct_types::Error.none; }
        iter_binding = pat.a;

        let carries = m.loopCarries(loop_id);
        if carries.len > 64 { return squid_direct_types::Error.none; }
        for ci in 0..carries.len {
            if !carry_in_place[ci] { return squid_direct_types::Error.none; }
        }

        // Collect flattened top-level statements of info.body (up to 16).
        var stmts: u32[16] = [0; 16];
        var stmts_len: i64 = 0;
        let bn = m.node(info.body);
        if bn.tag == squid_check_core::Tag.suite || bn.tag == squid_check_core::Tag.block_ {
            let ch_len = m.children(info.body).len;
            if ch_len == 0 || ch_len > 16 { return squid_direct_types::Error.none; }
            for si in 0..ch_len {
                stmts[si] = m.children(info.body)[si];
            }
            stmts_len = ch_len;
        } else {
            stmts[0] = info.body;
            stmts_len = 1;
        }

        // Collect 1..4 trailing in-place indexed updates (7C-1: supports multi-array init/transform loops!).
        var upd_ids_rev: u32[4] = [0; 4];
        var first_upd_idx: i64 = stmts_len;
        while first_upd_idx > 0 && dst_count < 4 {
            let cand_id = stmts[first_upd_idx - 1];
            let cand_n = m.node(cand_id);
            var uid: u32 = 0;
            if cand_n.tag == squid_check_core::Tag.update {
                uid = cand_id;
            } else if cand_n.tag == squid_check_core::Tag.bind && cand_n.c < 2 && m.node(cand_n.b).tag == squid_check_core::Tag.update {
                uid = cand_n.b;
            }
            if uid == 0 { break; }
            upd_ids_rev[dst_count] = uid;
            dst_count += 1;
            first_upd_idx -= 1;
        }
        if dst_count == 0 { return squid_direct_types::Error.none; }

        var upd_ids: u32[4] = [0; 4];
        for u in 0..dst_count {
            let uid = upd_ids_rev[dst_count - 1 - u];
            upd_ids[u] = uid;
            let uinfo = m.updateInfo(uid);
            let sels = m.updateSelectors(uid);
            if sels.len != 1 || sels[0].kind != squid_check_core::UpdateKind.index {
                return squid_direct_types::Error.none;
            }
            if uinfo.self_binding != 0 && uses(g, f, uinfo.self_binding) != 0 {
                return squid_direct_types::Error.none;
            }
            let db = localRef(m, uinfo.root);
            if db == 0 { return squid_direct_types::Error.none; }
            for prev_u in 0..u {
                if dst_bs[prev_u] == db { return squid_direct_types::Error.none; }
            }
            let _, dst_is_cell = withCellType(g, f, db);
            if dst_is_cell { return squid_direct_types::Error.none; }
            let dv, dok = bindGet(g, f, db);
            if !dok || tagOf(g, dv.ty) != squid_direct_types::Tag.array {
                return squid_direct_types::Error.none;
            }
            let otag = tagOf(g, g.types.node(dv.ty).a);
            if otag != squid_direct_types::Tag.f32_ && otag != squid_direct_types::Tag.u32_ {
                return squid_direct_types::Error.none;
            }
            dst_bs[u] = db;
            dst_vals[u] = dv;
            dst_tags[u] = otag;
        }

        plan = SparkVecPlan {
            spark_unit: m.unit,
            is_range: true,
            iter_binding: iter_binding,
            iter_tag: squid_direct_types::Tag.u32_,
            out_tag: dst_tags[0],
        };
        plan.locals[0] = SparkVecLocal {
            unit: m.unit,
            binding: iter_binding,
            tag: squid_direct_types::Tag.u32_,
            is_mask: false,
            invariant: false,
        };
        plan.locals_len = 1;

        // Analyze leading statements (affine index aliases or pure scalar bindings).
        for si in 0..first_upd_idx {
            let cn = m.node(stmts[si]);
            if cn.tag != squid_check_core::Tag.bind || cn.c != 0 || m.binding(cn.a).scheme.variables.len != 0 {
                return squid_direct_types::Error.none;
            }
            let is_aff, aff_off = matchRangeAffineIndex(g, f, plan, m, f.env, cn.b);
            if is_aff {
                if plan.affine_locals_len >= 8 { return squid_direct_types::Error.none; }
                plan.affine_locals[plan.affine_locals_len] = SparkAffineLocal {
                    binding: cn.a,
                    offset_id: aff_off,
                };
                plan.affine_locals_len += 1;
                continue;
            }
            let bty, bok = lowerInEnv(g, m, m.typeOf(cn.b), f.env);
            if !bok || !isSparkLaneTag(tagOf(g, bty)) || plan.locals_len >= 64 || lead_bind_len >= 8 {
                return squid_direct_types::Error.none;
            }
            if !checkVecExpr(g, f, plan, m, f.env, cn.b, 0, 0, false) {
                return squid_direct_types::Error.none;
            }
            let btag = tagOf(g, bty);
            let inv = isInvariantScalarExpr(g, f, plan, m, f.env, cn.b, btag, 0);
            let fin = btag == squid_direct_types::Tag.f32_ && isBoundedLeafVecF32(g, f, plan, m, f.env, cn.b);
            plan.locals[plan.locals_len] = SparkVecLocal {
                unit: m.unit,
                binding: cn.a,
                tag: btag,
                is_mask: btag == squid_direct_types::Tag.boolean,
                invariant: inv,
                finite: fin,
            };
            plan.locals_len += 1;
            lead_bind_ids[lead_bind_len] = cn.a;
            lead_bind_exprs[lead_bind_len] = cn.b;
            lead_bind_tags[lead_bind_len] = btag;
            lead_bind_len += 1;
        }

        for u in 0..dst_count {
            let uinfo = m.updateInfo(upd_ids[u]);
            let sels = m.updateSelectors(upd_ids[u]);
            let dst_ok, d_off = matchRangeAffineIndex(g, f, plan, m, f.env, sels[0].index);
            if !dst_ok { return squid_direct_types::Error.none; }
            dst_offs[u] = d_off;

            let rhs_ty, rok = lowerInEnv(g, m, m.typeOf(uinfo.value), f.env);
            if !rok || tagOf(g, rhs_ty) != dst_tags[u] { return squid_direct_types::Error.none; }
            if !checkVecExpr(g, f, plan, m, f.env, uinfo.value, 0, 0, false) {
                return squid_direct_types::Error.none;
            }
            rhs_ids[u] = uinfo.value;
        }
        matched = true;
    }

    if !matched { return squid_direct_types::Error.none; }

    // Emit 4-wide (with 4x unrolled 16-element fast path) SIMD loop guarded by
    // bounds, non-wrapping, and strict alias/overlap safety!
    let start_is_zero = g.units[f.unit - 1].node(info.first).tag == squid_check_core::Tag.constant && g.units[f.unit - 1].node(info.first).a == 0;
    var start_local: u32 = 0;
    var count: u32 = 0;
    if start_is_zero {
        start_local = index;
        count = end_local;
    } else {
        start_local = local32(g, f);
        lget(g, index);
        lset(g, start_local);

        count = local32(g, f);
        lget(g, end_local);
        lget(g, start_local);
        op(g, OP_i32_gt_u);
        let cnt_if = open(g, f, OP_if_);
        lget(g, end_local);
        lget(g, start_local);
        op(g, OP_i32_sub);
        lset(g, count);
        popCheckedArraysAt(f, cnt_if);
        op(g, OP_else_);
        i32Const(g, 0);
        lset(g, count);
        close(g, f);
    }

    let simd_end = local32(g, f);
    lget(g, count);
    i32Const(g, 0xfffffffc);
    op(g, OP_i32_and);
    lset(g, simd_end);

    // Destination bounds and byte extents [dst_ptrs[u] .. dst_byte_ends[u]).
    var dst_ptrs: u32[4] = [0; 4];
    var dst_byte_ends: u32[4] = [0xffffffff; 4];
    for u in 0..dst_count {
        let dst_base, dst_len = ensureCheckedArray(g, f, dst_vals[u]);
        if start_is_zero && dst_offs[u] == 0 {
            lget(g, count);
            lget(g, dst_len);
            op(g, OP_i32_gt_u);
            let dst_guard = open(g, f, OP_if_);
            i32Const(g, 0);
            lset(g, simd_end);
            close(g, f);
            dst_ptrs[u] = dst_base;
        } else {
            var dst_off_local: u32 = 0;
            if dst_offs[u] != 0 {
                let off_loc, oerr = emitInvariantU32(g, f, plan, g.units[f.unit - 1], f.env, dst_offs[u]);
                if oerr != squid_direct_types::Error.none { return oerr; }
                dst_off_local = off_loc;
            } else {
                dst_off_local = constLocal(g, f, 0);
            }

            var dst_base_idx: u32 = dst_off_local;
            if !start_is_zero {
                dst_base_idx = local32(g, f);
                lget(g, dst_off_local);
                lget(g, start_local);
                op(g, OP_i32_add);
                lset(g, dst_base_idx);
            }

            let dst_end_idx = local32(g, f);
            lget(g, dst_base_idx);
            lget(g, count);
            op(g, OP_i32_add);
            lset(g, dst_end_idx);

            if !start_is_zero {
                lget(g, dst_base_idx);
                lget(g, dst_off_local);
                op(g, OP_i32_ge_u);
            }
            lget(g, dst_end_idx);
            lget(g, dst_base_idx);
            op(g, OP_i32_ge_u);
            if !start_is_zero { op(g, OP_i32_and); }
            lget(g, dst_end_idx);
            lget(g, dst_len);
            op(g, OP_i32_le_u);
            op(g, OP_i32_and);
            op(g, OP_i32_eqz);
            let dst_guard = open(g, f, OP_if_);
            i32Const(g, 0);
            lset(g, simd_end);
            close(g, f);

            let dp = local32(g, f);
            lget(g, dst_base);
            lget(g, dst_base_idx);
            i32Const(g, 2);
            op(g, OP_i32_shl);
            op(g, OP_i32_add);
            lset(g, dp);
            dst_ptrs[u] = dp;
        }
        if dst_count > 1 {
            let de = local32(g, f);
            lget(g, dst_ptrs[u]);
            lget(g, count);
            i32Const(g, 2);
            op(g, OP_i32_shl);
            op(g, OP_i32_add);
            lset(g, de);
            dst_byte_ends[u] = de;
        }
    }
    // Pairwise disjointness across multiple destination arrays (guards against aliased views/owners).
    if dst_count > 1 {
        for u in 0..dst_count {
            for v in (u + 1)..dst_count {
                lget(g, dst_byte_ends[u]); lget(g, dst_ptrs[v]); op(g, OP_i32_le_u);
                lget(g, dst_byte_ends[v]); lget(g, dst_ptrs[u]); op(g, OP_i32_le_u);
                op(g, OP_i32_or);
                op(g, OP_i32_eqz);
                let pd_guard = open(g, f, OP_if_);
                i32Const(g, 0);
                lset(g, simd_end);
                close(g, f);
            }
        }
    }

    // Every source stream must satisfy bounds + non-wrapping + overlap safety.
    for si in 0..plan.streams_len {
        let st = plan.streams[si];
        // Fast path 1 (single-dst): stream is identical to dst (e.g. `c[dst] := c[dst] + ...`)!
        {
            let pm .= g.units[f.unit - 1];
            let st_arr_b = localRef(pm, st.arr_id);
            if dst_count == 1 && st_arr_b != 0 && st_arr_b == dst_bs[0] && st.elem_tag == dst_tags[0] && sameOffsetExpr(pm, st.offset_id, dst_offs[0]) {
                plan.streams[si].ptr_local = dst_ptrs[0];
                continue;
            }
            var dup_ptr: u32 = 0xffffffff;
            for sj in 0..si {
                let prev = plan.streams[sj];
                let prev_arr_b = localRef(pm, prev.arr_id);
                if st_arr_b != 0 && st_arr_b == prev_arr_b && prev.elem_tag == st.elem_tag && sameOffsetExpr(pm, st.offset_id, prev.offset_id) {
                    dup_ptr = prev.ptr_local;
                    break;
                }
            }
            if dup_ptr != 0xffffffff {
                plan.streams[si].ptr_local = dup_ptr;
                continue;
            }
        }
        if dst_byte_ends[0] == 0xffffffff {
            dst_byte_ends[0] = local32(g, f);
            lget(g, dst_ptrs[0]);
            lget(g, count);
            i32Const(g, 2);
            op(g, OP_i32_shl);
            op(g, OP_i32_add);
            lset(g, dst_byte_ends[0]);
        }

        let arr_val, aerr = expr(g, f, st.arr_id);
        if aerr != squid_direct_types::Error.none { return aerr; }
        let arr_base, arr_len, blerr = containerBaseAndLen(g, f, arr_val, st.node_id);
        if blerr != squid_direct_types::Error.none { return blerr; }

        var stream_ptr: u32 = 0;
        var stream_byte_end: u32 = 0;
        if start_is_zero && st.offset_id == 0 {
            stream_ptr = arr_base;
            plan.streams[si].ptr_local = stream_ptr;
            stream_byte_end = local32(g, f);
            lget(g, stream_ptr);
            lget(g, count);
            if st.elem_tag != squid_direct_types::Tag.boolean {
                i32Const(g, 2);
                op(g, OP_i32_shl);
            }
            op(g, OP_i32_add);
            lset(g, stream_byte_end);
            lget(g, count);
            lget(g, arr_len);
            op(g, OP_i32_le_u);
        } else {
            var offset_local: u32 = 0;
            if st.offset_id != 0 {
                let off_loc, oerr = emitInvariantU32(g, f, plan, g.units[f.unit - 1], f.env, st.offset_id);
                if oerr != squid_direct_types::Error.none { return oerr; }
                offset_local = off_loc;
            } else {
                offset_local = constLocal(g, f, 0);
            }

            var base_idx: u32 = offset_local;
            if !start_is_zero {
                base_idx = local32(g, f);
                lget(g, offset_local);
                lget(g, start_local);
                op(g, OP_i32_add);
                lset(g, base_idx);
            }

            let end_idx = local32(g, f);
            lget(g, base_idx);
            lget(g, count);
            op(g, OP_i32_add);
            lset(g, end_idx);

            stream_ptr = local32(g, f);
            lget(g, arr_base);
            lget(g, base_idx);
            if st.elem_tag != squid_direct_types::Tag.boolean {
                i32Const(g, 2);
                op(g, OP_i32_shl);
            }
            op(g, OP_i32_add);
            lset(g, stream_ptr);
            plan.streams[si].ptr_local = stream_ptr;

            stream_byte_end = local32(g, f);
            lget(g, stream_ptr);
            lget(g, count);
            if st.elem_tag != squid_direct_types::Tag.boolean {
                i32Const(g, 2);
                op(g, OP_i32_shl);
            }
            op(g, OP_i32_add);
            lset(g, stream_byte_end);

            // bounds_ok = [base_idx >=_u offset &] (end_idx >=_u base_idx) & (end_idx <=_u arr_len)
            if !start_is_zero {
                lget(g, base_idx);
                lget(g, offset_local);
                op(g, OP_i32_ge_u);
            }
            lget(g, end_idx);
            lget(g, base_idx);
            op(g, OP_i32_ge_u);
            if !start_is_zero { op(g, OP_i32_and); }
            lget(g, end_idx);
            lget(g, arr_len);
            op(g, OP_i32_le_u);
            op(g, OP_i32_and);
        }

        // overlap_ok against every destination array
        for u in 0..dst_count {
            lget(g, stream_byte_end);
            lget(g, dst_ptrs[u]);
            op(g, OP_i32_le_u);
            lget(g, dst_byte_ends[u]);
            lget(g, stream_ptr);
            op(g, OP_i32_le_u);
            op(g, OP_i32_or);
            if dst_count == 1 && st.elem_tag != squid_direct_types::Tag.boolean {
                lget(g, stream_ptr);
                lget(g, dst_ptrs[0]);
                op(g, OP_i32_eq);
                op(g, OP_i32_or);
            }
            op(g, OP_i32_and);
        }
        op(g, OP_i32_eqz);
        let guard_if = open(g, f, OP_if_);
        i32Const(g, 0);
        lset(g, simd_end);
        close(g, f);
    }

    let k = constLocal(g, f, 0);
    let byte_off = constLocal(g, f, 0);
    plan.index_local = k;
    plan.byte_off_local = byte_off;

    // Pre-splat outer loop-invariant scalar captures and canonical NaN vector once before OP_loop.
    for hi in 0..plan.hoisted_len {
        let h = plan.hoisted[hi];
        let vl = local(g, f, VT_v128);
        if h.tag == squid_direct_types::Tag.boolean {
            i32Const(g, 0);
            lget(g, h.scalar_local);
            op(g, OP_i32_sub);
            simdOp(g, SIMD_i32x4_splat);
        } else if h.tag == squid_direct_types::Tag.f32_ {
            lget(g, h.scalar_local);
            simdOp(g, SIMD_f32x4_splat);
        } else {
            lget(g, h.scalar_local);
            simdOp(g, SIMD_i32x4_splat);
        }
        lset(g, vl);
        plan.hoisted[hi].vlocal = vl;
    }
    if plan.uses_f32_canon && !f.defer_f32_nan {
        let nl = local(g, f, VT_v128);
        v128Const4(g, 0x7fc00000);
        lset(g, nl);
        plan.nan_vlocal = nl;
    }

    let need_iter_vlocal = plan.iter_value_used;
    var iter_vlocal: u32 = 0;
    var iter_base_v: u32 = 0;
    var v4_local: u32 = 0;
    var v12_local: u32 = 0;
    var v16_local: u32 = 0;
    if need_iter_vlocal {
        iter_vlocal = local(g, f, VT_v128);
        iter_base_v = local(g, f, VT_v128);
        plan.locals[0].vlocal = iter_vlocal;
        if start_is_zero {
            v128ConstWords(g, 0, 1, 2, 3);
        } else {
            lget(g, start_local);
            simdOp(g, SIMD_i32x4_splat);
            v128ConstWords(g, 0, 1, 2, 3);
            simdOp(g, SIMD_i32x4_add);
        }
        lset(g, iter_vlocal);
        v4_local = local(g, f, VT_v128);
        v128Const4(g, 4);
        lset(g, v4_local);
        v12_local = local(g, f, VT_v128);
        v128Const4(g, 12);
        lset(g, v12_local);
        v16_local = local(g, f, VT_v128);
        v128Const4(g, 16);
        lset(g, v16_local);
    }

    // 4x unrolled 16-element SIMD loop (64-byte cache line, ALWAYS descending 48,32,16,0 offsets!)
    if plan.streams_len <= 8 && plan.budget >= 80 {
        let simd16_end = local32(g, f);
        lget(g, simd_end);
        i32Const(g, 0xfffffff0);
        op(g, OP_i32_and);
        lset(g, simd16_end);

        var cur_dsts: u32[4] = [0; 4];
        for u in 0..dst_count { cur_dsts[u] = local32(g, f); }
        var orig_ptrs: u32[8] = [0; 8];
        var cur_ptrs: u32[8] = [0; 8];
        for si in 0..plan.streams_len {
            orig_ptrs[si] = plan.streams[si].ptr_local;
            var reused: u32 = 0xffffffff;
            if dst_count == 1 && orig_ptrs[si] == dst_ptrs[0] && plan.streams[si].elem_tag != squid_direct_types::Tag.boolean {
                reused = cur_dsts[0];
            } else {
                for sj in 0..si {
                    if orig_ptrs[sj] == orig_ptrs[si] && (plan.streams[sj].elem_tag == squid_direct_types::Tag.boolean) == (plan.streams[si].elem_tag == squid_direct_types::Tag.boolean) {
                        reused = cur_ptrs[sj];
                        break;
                    }
                }
            }
            if reused != 0xffffffff { cur_ptrs[si] = reused; } else { cur_ptrs[si] = local32(g, f); }
        }

        let u16_exit = open(g, f, OP_block);
        let u16_top = open(g, f, OP_loop);
        lget(g, k);
        lget(g, simd16_end);
        op(g, OP_i32_ge_u);
        br(g, f, OP_br_if, u16_exit);

        for u in 0..dst_count {
            lget(g, dst_ptrs[u]);
            lget(g, byte_off);
            op(g, OP_i32_add);
            lset(g, cur_dsts[u]);
        }

        for si in 0..plan.streams_len {
            var is_dup = dst_count == 1 && cur_ptrs[si] == cur_dsts[0];
            if !is_dup {
                for sj in 0..si {
                    if cur_ptrs[sj] == cur_ptrs[si] { is_dup = true; break; }
                }
            }
            if !is_dup {
                lget(g, orig_ptrs[si]);
                if plan.streams[si].elem_tag == squid_direct_types::Tag.boolean { lget(g, k); } else { lget(g, byte_off); }
                op(g, OP_i32_add);
                lset(g, cur_ptrs[si]);
            }
            plan.streams[si].ptr_local = cur_ptrs[si];
        }
        plan.index_local = 0xffffffff;
        plan.byte_off_local = 0xffffffff;

        if need_iter_vlocal {
            lget(g, iter_vlocal);
            ltee(g, iter_base_v);
            lget(g, v12_local);
            simdOp(g, SIMD_i32x4_add);
            lset(g, iter_vlocal);
        }

        for ustep in 0..4 {
            let step = 3 - ustep;
            plan.unroll_step = step as u32;
            let m_step .= g.units[f.unit - 1];
            for li in 0..lead_bind_len {
                let lerr = emitVecExpr(g, f, plan, m_step, f.env, lead_bind_exprs[li], false);
                if lerr != squid_direct_types::Error.none { return lerr; }
                let vl = local(g, f, VT_v128);
                lset(g, vl);
                let lidx = findVecLocal(plan, m_step.unit, lead_bind_ids[li]);
                assert(lidx >= 0);
                plan.locals[lidx].vlocal = vl;
                if lead_bind_tags[li] == squid_direct_types::Tag.u32_ && plan.locals[lidx].invariant {
                    let sloc, serr = emitInvariantU32(g, f, plan, m_step, f.env, lead_bind_exprs[li]);
                    if serr != squid_direct_types::Error.none { return serr; }
                    plan.locals[lidx].scalar_local = sloc;
                }
            }
            for u in 0..dst_count {
                lget(g, cur_dsts[u]);
                let rhs_err = emitVecExpr(g, f, plan, m_step, f.env, rhs_ids[u], false);
                if rhs_err != squid_direct_types::Error.none { return rhs_err; }
                simdMemOp(g, SIMD_v128_store, 2, (step as u32) * 16);
            }
            if need_iter_vlocal && ustep < 3 {
                lget(g, iter_vlocal);
                lget(g, v4_local);
                simdOp(g, SIMD_i32x4_sub);
                lset(g, iter_vlocal);
            }
        }

        if need_iter_vlocal {
            lget(g, iter_base_v);
            lget(g, v16_local);
            simdOp(g, SIMD_i32x4_add);
            lset(g, iter_vlocal);
        }

        for si in 0..plan.streams_len { plan.streams[si].ptr_local = orig_ptrs[si]; }
        plan.index_local = k;
        plan.byte_off_local = byte_off;
        plan.unroll_step = 0;

        lget(g, k);
        i32Const(g, 16);
        op(g, OP_i32_add);
        lset(g, k);

        lget(g, byte_off);
        i32Const(g, 64);
        op(g, OP_i32_add);
        lset(g, byte_off);

        br(g, f, OP_br, u16_top);
        close(g, f);
        close(g, f);
    }

    let simd_exit = open(g, f, OP_block);
    let simd_top = open(g, f, OP_loop);
    lget(g, k);
    lget(g, simd_end);
    op(g, OP_i32_ge_u);
    br(g, f, OP_br_if, simd_exit);

    // Emit any leading pure vectorizable scalar bindings.
    let m_emit .= g.units[f.unit - 1];
    for li in 0..lead_bind_len {
        let lerr = emitVecExpr(g, f, plan, m_emit, f.env, lead_bind_exprs[li], false);
        if lerr != squid_direct_types::Error.none { return lerr; }
        let vl = local(g, f, VT_v128);
        lset(g, vl);
        let lidx = findVecLocal(plan, m_emit.unit, lead_bind_ids[li]);
        assert(lidx >= 0);
        plan.locals[lidx].vlocal = vl;
        if lead_bind_tags[li] == squid_direct_types::Tag.u32_ && plan.locals[lidx].invariant {
            let sloc, serr = emitInvariantU32(g, f, plan, m_emit, f.env, lead_bind_exprs[li]);
            if serr != squid_direct_types::Error.none { return serr; }
            plan.locals[lidx].scalar_local = sloc;
        }
    }

    // Store address, compute 4-wide RHS vector, v128.store for each destination!
    for u in 0..dst_count {
        lget(g, dst_ptrs[u]);
        lget(g, byte_off);
        op(g, OP_i32_add);

        let rhs_err = emitVecExpr(g, f, plan, m_emit, f.env, rhs_ids[u], false);
        if rhs_err != squid_direct_types::Error.none { return rhs_err; }

        simdMemOp(g, SIMD_v128_store, 2, 0);
    }

    lget(g, k);
    i32Const(g, 4);
    op(g, OP_i32_add);
    lset(g, k);

    lget(g, byte_off);
    i32Const(g, 16);
    op(g, OP_i32_add);
    lset(g, byte_off);

    if need_iter_vlocal {
        lget(g, iter_vlocal);
        lget(g, v4_local);
        simdOp(g, SIMD_i32x4_add);
        lset(g, iter_vlocal);
    }

    br(g, f, OP_br, simd_top);
    close(g, f);
    close(g, f);

    // Advance caller's loop `index` past the SIMD prefix so scalar tail handles [index .. end).
    lget(g, index);
    lget(g, k);
    op(g, OP_i32_add);
    lset(g, index);

    return squid_direct_types::Error.none;
}

// 5D: 16-wide Wasm `v128` SIMD reduction for counted `for i in start .. end:` loops:
//   (A) Masked `#[Bool]` reduction:
//         if flags[i]:
//           c0 := c0 (+|^) rhs0
//           [c1 := c1 (+|^) rhs1]
//       where each rhs is `i`, constant `1`, or a loop-invariant `U32`.
//   (B) Unmasked contiguous `#[U32]` reduction:
//         acc := acc (+|^) arr[i]
// Uses descending offsets (12,8,4,0 or 48,32,16,0) for 1 software bounds check per 16 elements,
// eliminates unpredictable prime/mask branches, and advances `index` past the 16-wide prefix.
fn tryEmitVectorReductionLoop(
    g: Generator&,
    f: Fn&,
    loop_id: u32,
    info: squid_check_core::LoopInfo,
    iteration: Vals,
    carry_in_place: const bool[64]&,
    index: u32,
    end_local: u32,
) -> Error {
    if g.runtime_().has_fork || info.kind != squid_check_core::LoopKind.range || info.pattern == 0 || info.body == 0 {
        return squid_direct_types::Error.none;
    }
    var is_masked = false;
    var is_f32_sum = false;
    var arr_b: u32 = 0;
    var red_count: i64 = 0;
    var red_ci: i64[2] = [0; 2];
    var red_is_xor: bool[2] = [false; 2];
    // kind: 1 = iter index `i`, 2 = const `1`, 3 = other invariant U32 expr
    var red_kind: i64[2] = [0; 2];
    var red_rhs_id: u32[2] = [0; 2];
    var matched = false;

    {
        let m .= g.units[f.unit - 1];
        let pat = m.pattern(info.pattern);
        if pat.tag != squid_check_core::PatternTag.bind { return squid_direct_types::Error.none; }
        let iter_b = pat.a;

        let carries = m.loopCarries(loop_id);
        if carries.len == 0 || carries.len > 64 { return squid_direct_types::Error.none; }
        var red_iter: u32[2] = [0; 2];
        var red_back: u32[2] = [0; 2];
        for carry, ci in carries {
            if carry_in_place[ci] { continue; }
            if red_count >= 2 || carry.backedge == 0 { return squid_direct_types::Error.none; }
            let iv = g.s.vals[iteration.start + ci];
            let itag = tagOf(g, iv.ty);
            if iv.len != 1 { return squid_direct_types::Error.none; }
            if itag == squid_direct_types::Tag.f32_ {
                if red_count > 0 || is_f32_sum { return squid_direct_types::Error.none; }
                is_f32_sum = true;
            } else if itag == squid_direct_types::Tag.u32_ {
                if is_f32_sum { return squid_direct_types::Error.none; }
            } else {
                return squid_direct_types::Error.none;
            }
            red_ci[red_count] = ci;
            red_iter[red_count] = carry.iteration;
            red_back[red_count] = carry.backedge;
            red_count += 1;
        }
        if red_count == 0 { return squid_direct_types::Error.none; }

        let body_node = unwrapSingleBody(m, info.body);
        if body_node == 0 { return squid_direct_types::Error.none; }
        let bn = m.node(body_node);

        if !is_f32_sum && bn.tag == squid_check_core::Tag.if_stmt && bn.c == 0 {
            // Variant A: masked `if flags[i]: ...`
            let gok, fa_n, fi_n = matchArrayGet(m, bn.a);
            if !gok || localRef(m, fi_n) != iter_b { return squid_direct_types::Error.none; }
            arr_b = localRef(m, fa_n);
            if arr_b == 0 { return squid_direct_types::Error.none; }
            let av, aok = bindGet(g, f, arr_b);
            if !aok || tagOf(g, av.ty) != squid_direct_types::Tag.array || tagOf(g, g.types.node(av.ty).a) != squid_direct_types::Tag.boolean {
                return squid_direct_types::Error.none;
            }

            var t_ids: u32[2] = [0; 2];
            var t_exprs: u32[2] = [0; 2];
            var t_len: i64 = 0;
            let tbn = m.node(bn.b);
            if tbn.tag == squid_check_core::Tag.suite || tbn.tag == squid_check_core::Tag.block_ {
                let tch = m.children(bn.b);
                if tch.len != red_count { return squid_direct_types::Error.none; }
                for ti in 0..tch.len {
                    let cn = m.node(tch[ti]);
                    if cn.tag != squid_check_core::Tag.bind || cn.c >= 2 { return squid_direct_types::Error.none; }
                    t_ids[ti] = cn.a;
                    t_exprs[ti] = cn.b;
                }
                t_len = tch.len;
            } else if tbn.tag == squid_check_core::Tag.bind && tbn.c < 2 && red_count == 1 {
                t_ids[0] = tbn.a;
                t_exprs[0] = tbn.b;
                t_len = 1;
            } else {
                return squid_direct_types::Error.none;
            }

            let merges = m.branchMerges(body_node);
            if merges.len != red_count { return squid_direct_types::Error.none; }
            var seen_r: bool[2] = [false; 2];
            var seen_t: bool[2] = [false; 2];
            for merge in merges {
                var r_idx: i64 = -1;
                for ri in 0..red_count {
                    if merge.result == red_back[ri] && merge.else_binding == red_iter[ri] { r_idx = ri; break; }
                }
                if r_idx < 0 || seen_r[r_idx] { return squid_direct_types::Error.none; }
                var t_idx: i64 = -1;
                for ti in 0..t_len {
                    if merge.then_binding == t_ids[ti] { t_idx = ti; break; }
                }
                if t_idx < 0 || seen_t[t_idx] { return squid_direct_types::Error.none; }
                seen_r[r_idx] = true;
                seen_t[t_idx] = true;

                let en = m.node(t_exprs[t_idx]);
                let is_op = en.tag == squid_check_core::Tag.scalar || (en.tag == squid_check_core::Tag.associated && en.op != squid_check_core::Op.none);
                if !is_op || (en.op != squid_check_core::Op.add && en.op != squid_check_core::Op.bit_xor) {
                    return squid_direct_types::Error.none;
                }
                var rhs: u32 = 0;
                if localRef(m, en.a) == red_iter[r_idx] { rhs = en.b; }
                else if localRef(m, en.b) == red_iter[r_idx] { rhs = en.a; }
                else { return squid_direct_types::Error.none; }

                red_is_xor[r_idx] = en.op == squid_check_core::Op.bit_xor;
                let rref = localRef(m, rhs);
                let rn = m.node(rhs);
                if rref == iter_b {
                    red_kind[r_idx] = 1;
                } else if rn.tag == squid_check_core::Tag.constant && rn.a == 1 && !red_is_xor[r_idx] {
                    red_kind[r_idx] = 2;
                    red_rhs_id[r_idx] = rhs;
                } else if rn.tag == squid_check_core::Tag.constant {
                    red_kind[r_idx] = 3;
                    red_rhs_id[r_idx] = rhs;
                } else if rref != 0 {
                    for ci2 in 0..red_count { if rref == red_iter[ci2] { return squid_direct_types::Error.none; } }
                    let _, is_cell = withCellType(g, f, rref);
                    if is_cell { return squid_direct_types::Error.none; }
                    red_kind[r_idx] = 3;
                    red_rhs_id[r_idx] = rhs;
                } else {
                    return squid_direct_types::Error.none;
                }
            }
            is_masked = true;
            matched = true;
        } else if bn.tag == squid_check_core::Tag.bind && bn.c < 2 && red_count == 1 && bn.a == red_back[0] {
            // Variant B: unmasked `acc := acc (+|^) arr[i]` (U32)
            // Variant C (7C-2): unmasked exact left-to-right 8x unrolled `sum := sum + arr[i]` (F32)
            let en = m.node(bn.b);
            let is_op = en.tag == squid_check_core::Tag.scalar || (en.tag == squid_check_core::Tag.associated && en.op != squid_check_core::Op.none);
            if is_f32_sum {
                if !is_op || en.op != squid_check_core::Op.add { return squid_direct_types::Error.none; }
            } else if !is_op || (en.op != squid_check_core::Op.add && en.op != squid_check_core::Op.bit_xor) {
                return squid_direct_types::Error.none;
            }
            var rhs: u32 = 0;
            if localRef(m, en.a) == red_iter[0] { rhs = en.b; }
            else if localRef(m, en.b) == red_iter[0] { rhs = en.a; }
            else { return squid_direct_types::Error.none; }
            let gok, aa_n, ai_n = matchArrayGet(m, rhs);
            if !gok || localRef(m, ai_n) != iter_b { return squid_direct_types::Error.none; }
            arr_b = localRef(m, aa_n);
            if arr_b == 0 { return squid_direct_types::Error.none; }
            let av, aok = bindGet(g, f, arr_b);
            if !aok || tagOf(g, av.ty) != squid_direct_types::Tag.array { return squid_direct_types::Error.none; }
            let etag = tagOf(g, g.types.node(av.ty).a);
            if is_f32_sum {
                if etag != squid_direct_types::Tag.f32_ { return squid_direct_types::Error.none; }
            } else if etag != squid_direct_types::Tag.u32_ {
                return squid_direct_types::Error.none;
            }
            red_is_xor[0] = en.op == squid_check_core::Op.bit_xor;
            is_masked = false;
            matched = true;
        }
    }
    if !matched { return squid_direct_types::Error.none; }
    if is_masked {
        for ri in 0..red_count {
            if red_kind[ri] == 2 { squid_direct_relocations::unpatchableOperand(g.units[f.unit - 1].unit, red_rhs_id[ri]); }
        }
    }

    let av, _ = bindGet(g, f, arr_b);
    let ada = findDirectArrayBySlot(f, w(g, av, 0));
    if ada >= 0 && f.direct_arrays[ada].scalar_packed { return squid_direct_types::Error.none; }
    let arr_base, arr_len = ensureCheckedArray(g, f, av);

    var rhs_vlocs: u32[2] = [0; 2];
    if is_masked {
        for ri in 0..red_count {
            if red_kind[ri] == 3 {
                let rv, rerr = expr(g, f, red_rhs_id[ri]);
                if rerr != squid_direct_types::Error.none { return rerr; }
                let vl = local(g, f, VT_v128);
                lget(g, w(g, rv, 0));
                simdOp(g, SIMD_i32x4_splat);
                lset(g, vl);
                rhs_vlocs[ri] = vl;
            }
        }
    }

    let simd_n = local32(g, f);
    lget(g, end_local);
    lget(g, index);
    op(g, OP_i32_gt_u);
    let cnt_if = open(g, f, OP_if_);
    lget(g, end_local);
    lget(g, index);
    op(g, OP_i32_sub);
    if is_f32_sum { i32Const(g, 0xfffffff8); } else { i32Const(g, 0xfffffff0); }
    op(g, OP_i32_and);
    lset(g, simd_n);
    popCheckedArraysAt(f, cnt_if);
    op(g, OP_else_);
    i32Const(g, 0);
    lset(g, simd_n);
    close(g, f);

    // Guard: simd_n > 0 && end_local <= arr_len (exact OOB trap order preserved in scalar fallback!)
    lget(g, simd_n);
    i32Const(g, 0);
    op(g, OP_i32_gt_u);
    lget(g, end_local);
    lget(g, arr_len);
    op(g, OP_i32_le_u);
    op(g, OP_i32_and);
    let guard_if = open(g, f, OP_if_);

    if is_f32_sum {
        // Variant C (7C-2): 8x unrolled descending-offset exact left-to-right IEEE-754 F32 sum.
        let ptr = local32(g, f);
        lget(g, arr_base);
        lget(g, index);
        i32Const(g, 2);
        op(g, OP_i32_shl);
        op(g, OP_i32_add);
        lset(g, ptr);

        let rem = local32(g, f);
        lget(g, simd_n);
        lset(g, rem);

        let cloc = w(g, g.s.vals[iteration.start + red_ci[0]], 0);
        var fl: u32[8] = [0; 8];
        for fi in 0..8 { fl[fi] = local(g, f, VT_f32); }

        let r_exit = open(g, f, OP_block);
        let r_top = open(g, f, OP_loop);
        lget(g, rem); op(g, OP_i32_eqz); br(g, f, OP_br_if, r_exit);

        // Descending f32.load 28,24,20,16,12,8,4,0 => 1 wtime bounds check per 8 floats!
        for k in 0..8 {
            let slot = 7 - k;
            lget(g, ptr);
            op(g, OP_f32_load); uleb(g, 2); uleb(g, (slot as u32) * 4);
            lset(g, fl[slot]);
        }
        lget(g, cloc);
        for slot in 0..8 {
            lget(g, fl[slot]);
            op(g, OP_f32_add);
        }
        lset(g, cloc);

        lget(g, ptr); i32Const(g, 32); op(g, OP_i32_add); lset(g, ptr);
        lget(g, rem); i32Const(g, 8); op(g, OP_i32_sub); lset(g, rem);
        br(g, f, OP_br, r_top);
        close(g, f);
        close(g, f);

        if !f.defer_f32_nan {
            lget(g, cloc);
            canonicalizeF32Stack(g, f);
            lset(g, cloc);
        }
    } else if is_masked {
        let ptr = local32(g, f);
        lget(g, arr_base);
        lget(g, index);
        op(g, OP_i32_add);
        lset(g, ptr);

        let rem = local32(g, f);
        lget(g, simd_n);
        lset(g, rem);

        var need_idx = false;
        var need_mask = false;
        var vaccs: u32[2] = [0; 2];
        for ri in 0..red_count {
            vaccs[ri] = local(g, f, VT_v128);
            v128Const4(g, 0);
            lset(g, vaccs[ri]);
            if red_kind[ri] == 1 { need_idx = true; need_mask = true; }
            else if red_kind[ri] == 3 { need_mask = true; }
        }

        var v_idx: u32[4] = [0; 4];
        var v16: u32 = 0;
        if need_idx {
            let v_start = local(g, f, VT_v128);
            lget(g, index);
            simdOp(g, SIMD_i32x4_splat);
            lset(g, v_start);
            for s in 0..4 {
                let base_w = (s as u32) * 4;
                v_idx[s] = local(g, f, VT_v128);
                lget(g, v_start);
                v128ConstWords(g, base_w, base_w + 1, base_w + 2, base_w + 3);
                simdOp(g, SIMD_i32x4_add);
                lset(g, v_idx[s]);
            }
            v16 = local(g, f, VT_v128);
            v128Const4(g, 16);
            lset(g, v16);
        }
        let w01 = local(g, f, VT_v128);
        var vmask: u32 = 0;
        if need_mask { vmask = local(g, f, VT_v128); }

        let r_exit = open(g, f, OP_block);
        let r_top = open(g, f, OP_loop);
        lget(g, rem);
        op(g, OP_i32_eqz);
        br(g, f, OP_br_if, r_exit);

        // Descending offsets 12, 8, 4, 0 => 1 software bounds check per 16 Bool elements!
        for ustep in 0..4 {
            let step = 3 - ustep;
            lget(g, ptr);
            simdMemOp(g, SIMD_v128_load32_zero, 0, (step as u32) * 4);
            simdOp(g, SIMD_i16x8_extend_low_i8x16_u);
            simdOp(g, SIMD_i32x4_extend_low_i16x8_u);
            lset(g, w01);
            if need_mask {
                lget(g, w01);
                simdOp(g, SIMD_i32x4_neg);
                lset(g, vmask);
            }
            for ri in 0..red_count {
                var vop = SIMD_i32x4_add;
                if red_is_xor[ri] { vop = SIMD_v128_xor; }
                lget(g, vaccs[ri]);
                if red_kind[ri] == 2 {
                    lget(g, w01);
                } else if red_kind[ri] == 1 {
                    lget(g, v_idx[step]);
                    lget(g, vmask);
                    simdOp(g, SIMD_v128_and);
                } else {
                    lget(g, rhs_vlocs[ri]);
                    lget(g, vmask);
                    simdOp(g, SIMD_v128_and);
                }
                simdOp(g, vop);
                lset(g, vaccs[ri]);
            }
        }

        if need_idx {
            for s in 0..4 {
                lget(g, v_idx[s]);
                lget(g, v16);
                simdOp(g, SIMD_i32x4_add);
                lset(g, v_idx[s]);
            }
        }
        lget(g, ptr); i32Const(g, 16); op(g, OP_i32_add); lset(g, ptr);
        lget(g, rem); i32Const(g, 16); op(g, OP_i32_sub); lset(g, rem);
        br(g, f, OP_br, r_top);
        close(g, f);
        close(g, f);

        for ri in 0..red_count {
            let cloc = w(g, g.s.vals[iteration.start + red_ci[ri]], 0);
            var sop = OP_i32_add;
            if red_is_xor[ri] { sop = OP_i32_xor; }
            lget(g, cloc);
            for lane in 0..4 {
                lget(g, vaccs[ri]);
                simdLaneOp(g, SIMD_i32x4_extract_lane, lane as u8);
                op(g, sop);
            }
            lset(g, cloc);
        }
    } else {
        // Variant B: unmasked 16-wide #[U32] reduction
        let ptr = local32(g, f);
        lget(g, arr_base);
        lget(g, index);
        i32Const(g, 2);
        op(g, OP_i32_shl);
        op(g, OP_i32_add);
        lset(g, ptr);

        let rem = local32(g, f);
        lget(g, simd_n);
        lset(g, rem);

        let vacc0 = local(g, f, VT_v128); v128Const4(g, 0); lset(g, vacc0);
        let vacc1 = local(g, f, VT_v128); v128Const4(g, 0); lset(g, vacc1);
        var vop = SIMD_i32x4_add;
        var sop = OP_i32_add;
        if red_is_xor[0] { vop = SIMD_v128_xor; sop = OP_i32_xor; }

        let r_exit = open(g, f, OP_block);
        let r_top = open(g, f, OP_loop);
        lget(g, rem); op(g, OP_i32_eqz); br(g, f, OP_br_if, r_exit);

        lget(g, vacc0); lget(g, ptr); simdMemOp(g, SIMD_v128_load, 2, 48); simdOp(g, vop);
        lget(g, ptr); simdMemOp(g, SIMD_v128_load, 2, 16); simdOp(g, vop); lset(g, vacc0);
        lget(g, vacc1); lget(g, ptr); simdMemOp(g, SIMD_v128_load, 2, 32); simdOp(g, vop);
        lget(g, ptr); simdMemOp(g, SIMD_v128_load, 2, 0); simdOp(g, vop); lset(g, vacc1);

        lget(g, ptr); i32Const(g, 64); op(g, OP_i32_add); lset(g, ptr);
        lget(g, rem); i32Const(g, 16); op(g, OP_i32_sub); lset(g, rem);
        br(g, f, OP_br, r_top);
        close(g, f);
        close(g, f);

        let vtot = local(g, f, VT_v128);
        lget(g, vacc0); lget(g, vacc1); simdOp(g, vop); lset(g, vtot);
        let cloc = w(g, g.s.vals[iteration.start + red_ci[0]], 0);
        lget(g, cloc);
        for lane in 0..4 {
            lget(g, vtot);
            simdLaneOp(g, SIMD_i32x4_extract_lane, lane as u8);
            op(g, sop);
        }
        lset(g, cloc);
    }

    lget(g, index);
    lget(g, simd_n);
    op(g, OP_i32_add);
    lset(g, index);

    popCheckedArraysAt(f, guard_if);
    close(g, f);
    f.checked_elems_len = 0;
    return squid_direct_types::Error.none;
}

// 7A: 4-wide branchless `v128` SIMD reduction for 16-byte `Maybe Vec3` read-only pool scans:
//   for i in start .. end:
//     if let $Some ($Pos { x, y, z }) = pos[i]:
//       sum := sum (+|^) F32.to_{u32,i32} (f_expr(x, y, z))
// Loads 4 consecutive 16-byte elements in descending order (48,32,16,0 => 1 wtime bounds check),
// performs a 4x4 SoA transpose via 8 `i8x16.shuffle`s into [vtag, vx, vy, vz], evaluates `f_expr`
// in exact IEEE-754 left-to-right `f32x4`, converts via `i32x4.trunc_sat_f32x4_{u,s}`, masks out
// `$Nothing` lanes branchlessly with `i32x4.eq(vtag, 0)`, and accumulates into `vacc`.
fn matchVec3F32ToInt(g: Generator&, m: const Module&, id: u32) -> bool, bool, u32 {
    if id == 0 { return false, false, 0; }
    let n = m.node(id);
    if n.tag == squid_check_core::Tag.scalar || (n.tag == squid_check_core::Tag.associated && n.op != squid_check_core::Op.none) {
        if n.op == squid_check_core::Op.convert_f32_u32 { return true, false, n.a; }
        if n.op == squid_check_core::Op.convert_f32_i32 { return true, true, n.a; }
    } else if n.tag == squid_check_core::Tag.call {
        let info = m.call(id);
        if info.arguments.len == 1 {
            let target = recordAliasChain(g, g.resolve(m, info.target));
            if g.hasUnit(target.unit) {
                let tm .= g.units[target.unit - 1];
                let alias, has_alias = primitiveAlias(tm, target.binding);
                if has_alias {
                    let pop = tm.primitive(alias).op;
                    if pop == squid_check_core::Op.convert_f32_u32 { return true, false, info.arguments[0]; }
                    if pop == squid_check_core::Op.convert_f32_i32 { return true, true, info.arguments[0]; }
                }
            }
        }
    }
    return false, false, 0;
}
recursive fn checkVec3F32Expr(
    g: Generator&,
    f: const Fn&,
    m: const Module&,
    id: u32,
    p_bs: const u32[3]&,
    iter_b: u32,
    sum_b: u32,
    depth: i64,
) -> bool {
    if id == 0 || depth > 12 { return false; }
    let ty, tok = lowerInEnv(g, m, m.typeOf(id), f.env);
    if !tok || tagOf(g, ty) != squid_direct_types::Tag.f32_ { return false; }
    let n = m.node(id);
    if n.tag == squid_check_core::Tag.constant { return true; }
    if n.tag == squid_check_core::Tag.reference {
        let b = localRef(m, id);
        if b == 0 || b == iter_b || b == sum_b { return false; }
        if b == p_bs[0] || b == p_bs[1] || b == p_bs[2] { return true; }
        let _, is_cell = withCellType(g, f, b);
        if is_cell { return false; }
        let bv, bok = bindGet(g, f, b);
        return bok && bv.len == 1 && tagOf(g, bv.ty) == squid_direct_types::Tag.f32_;
    }
    if n.tag == squid_check_core::Tag.scalar || (n.tag == squid_check_core::Tag.associated && n.op != squid_check_core::Op.none) {
        if n.b == 0 {
            if n.op != squid_check_core::Op.neg && n.op != squid_check_core::Op.abs && n.op != squid_check_core::Op.sqrt {
                return false;
            }
            return checkVec3F32Expr(g, f, m, n.a, p_bs, iter_b, sum_b, depth + 1);
        }
        if n.op != squid_check_core::Op.add && n.op != squid_check_core::Op.sub &&
            n.op != squid_check_core::Op.mul && n.op != squid_check_core::Op.div {
            return false;
        }
        return checkVec3F32Expr(g, f, m, n.a, p_bs, iter_b, sum_b, depth + 1) &&
            checkVec3F32Expr(g, f, m, n.b, p_bs, iter_b, sum_b, depth + 1);
    }
    return false;
}
recursive fn emitVec3F32Expr(
    g: Generator&,
    f: const Fn&,
    m: const Module&,
    id: u32,
    p_bs: const u32[3]&,
    v_xyz: const u32[3]&,
) {
    let n = m.node(id);
    if n.tag == squid_check_core::Tag.constant {
        squid_direct_relocations::unpatchableOperand(m.unit, id);
        v128Const4(g, n.a);
        return;
    }
    if n.tag == squid_check_core::Tag.reference {
        let b = localRef(m, id);
        if b == p_bs[0] { lget(g, v_xyz[0]); return; }
        if b == p_bs[1] { lget(g, v_xyz[1]); return; }
        if b == p_bs[2] { lget(g, v_xyz[2]); return; }
        let bv, _ = bindGet(g, f, b);
        lget(g, w(g, bv, 0));
        simdOp(g, SIMD_f32x4_splat);
        return;
    }
    if n.b == 0 {
        emitVec3F32Expr(g, f, m, n.a, p_bs, v_xyz);
        if n.op == squid_check_core::Op.neg { simdOp(g, SIMD_f32x4_neg); }
        else if n.op == squid_check_core::Op.abs { simdOp(g, SIMD_f32x4_abs); }
        else { simdOp(g, SIMD_f32x4_sqrt); }
        return;
    }
    if squid_direct_writer::relaxedSimdEnabled() && (n.op == squid_check_core::Op.add || n.op == squid_check_core::Op.sub) {
        if n.op == squid_check_core::Op.add {
            let lmul, lx, ly = matchVecF32Mul(g, m, f.env, n.a);
            if lmul {
                emitVec3F32Expr(g, f, m, lx, p_bs, v_xyz);
                emitVec3F32Expr(g, f, m, ly, p_bs, v_xyz);
                emitVec3F32Expr(g, f, m, n.b, p_bs, v_xyz);
                simdOp(g, SIMD_f32x4_relaxed_madd);
                return;
            }
            let rmul, rx, ry = matchVecF32Mul(g, m, f.env, n.b);
            if rmul {
                emitVec3F32Expr(g, f, m, rx, p_bs, v_xyz);
                emitVec3F32Expr(g, f, m, ry, p_bs, v_xyz);
                emitVec3F32Expr(g, f, m, n.a, p_bs, v_xyz);
                simdOp(g, SIMD_f32x4_relaxed_madd);
                return;
            }
        } else {
            let rmul, rx, ry = matchVecF32Mul(g, m, f.env, n.b);
            if rmul {
                emitVec3F32Expr(g, f, m, rx, p_bs, v_xyz);
                emitVec3F32Expr(g, f, m, ry, p_bs, v_xyz);
                emitVec3F32Expr(g, f, m, n.a, p_bs, v_xyz);
                simdOp(g, SIMD_f32x4_relaxed_nmadd);
                return;
            }
        }
    }
    emitVec3F32Expr(g, f, m, n.a, p_bs, v_xyz);
    emitVec3F32Expr(g, f, m, n.b, p_bs, v_xyz);
    if n.op == squid_check_core::Op.add { simdOp(g, SIMD_f32x4_add); }
    else if n.op == squid_check_core::Op.sub { simdOp(g, SIMD_f32x4_sub); }
    else if n.op == squid_check_core::Op.mul { simdOp(g, SIMD_f32x4_mul); }
    else { simdOp(g, SIMD_f32x4_div); }
}
fn tryEmitVec3MaybeReductionLoop(
    g: Generator&,
    f: Fn&,
    loop_id: u32,
    info: squid_check_core::LoopInfo,
    iteration: Vals,
    carry_in_place: const bool[64]&,
    index: u32,
    end_local: u32,
) -> Error {
    if g.runtime_().has_fork || info.kind != squid_check_core::LoopKind.range || info.pattern == 0 || info.body == 0 {
        return squid_direct_types::Error.none;
    }
    var arr_b: u32 = 0;
    var arr_inlined = BindingRef { 0, 0 };
    var p_bs: u32[3] = [0; 3];
    var f_expr_id: u32 = 0;
    var sum_ci: i64 = -1;
    var is_xor = false;
    var is_signed_conv = false;
    var matched = false;

    {
        let m .= g.units[f.unit - 1];
        let pat = m.pattern(info.pattern);
        if pat.tag != squid_check_core::PatternTag.bind { return squid_direct_types::Error.none; }
        let iter_b = pat.a;

        let carries = m.loopCarries(loop_id);
        if carries.len == 0 || carries.len > 64 { return squid_direct_types::Error.none; }
        var sum_iter: u32 = 0;
        var sum_back: u32 = 0;
        for carry, ci in carries {
            if carry_in_place[ci] { continue; }
            if sum_ci >= 0 || carry.backedge == 0 { return squid_direct_types::Error.none; }
            let iv = g.s.vals[iteration.start + ci];
            if iv.len != 1 || tagOf(g, iv.ty) != squid_direct_types::Tag.u32_ { return squid_direct_types::Error.none; }
            sum_ci = ci;
            sum_iter = carry.iteration;
            sum_back = carry.backedge;
        }
        if sum_ci < 0 { return squid_direct_types::Error.none; }

        let body_node = unwrapSingleBody(m, info.body);
        if body_node == 0 || m.node(body_node).tag != squid_check_core::Tag.match_ { return squid_direct_types::Error.none; }
        let minfo = m.matchInfo(body_node);
        let minputs = m.matchInputs(body_node);
        let marms = m.matchArms(body_node);
        if !minfo.statement || minputs.len != 1 || marms.len != 2 || marms[0].guard_ != 0 || !isNoopWildcardArm(m, marms[1]) {
            return squid_direct_types::Error.none;
        }
        let arr_n, idx_n, inl_ref, rok = resolveLazyVariantArrayRead(g, f, m, minputs[0]);
        if !rok || localRef(m, idx_n) != iter_b { return squid_direct_types::Error.none; }
        arr_b = localRef(m, arr_n);
        if arr_b == 0 { return squid_direct_types::Error.none; }
        let av, aok = bindGet(g, f, arr_b);
        if !aok || tagOf(g, av.ty) != squid_direct_types::Tag.array { return squid_direct_types::Error.none; }
        let elem_ty, eierr = g.types.lower(m, m.typeOf(minputs[0]), f.env);
        if eierr != squid_direct_types::Error.none { g.dropFailure(); return squid_direct_types::Error.none; }
        if tagOf(g, elem_ty) != squid_direct_types::Tag.nominal { return squid_direct_types::Error.none; }
        let boxed, berr = isBoxed(g, f, elem_ty, body_node);
        let step, serr = stride(g, f, elem_ty, body_node);
        if berr != squid_direct_types::Error.none || boxed || serr != squid_direct_types::Error.none || step != 16 {
            return squid_direct_types::Error.none;
        }
        let cases, cerr = g.types.variants(elem_ty);
        if cerr != squid_direct_types::Error.none || cases.len <= 1 { return squid_direct_types::Error.none; }
        let vpos, vperr = variantPosition(g, f, cases, 0, body_node);
        if vperr != squid_direct_types::Error.none { return squid_direct_types::Error.none; }
        let payload_ty = g.types.variant_payloads[cases.payloads + vpos];
        let rows = m.armRows(marms[0]);
        if rows.len != 1 || m.rowPatterns(rows[0]).len != 1 { return squid_direct_types::Error.none; }
        let p_pat = m.pattern(m.rowPatterns(rows[0])[0]);
        if p_pat.tag != squid_check_core::PatternTag.constructor || m.constructor(p_pat.a).tag != 0 {
            return squid_direct_types::Error.none;
        }
        if !extract3F32PayloadPat(g, m, p_pat.b, payload_ty, p_bs) { return squid_direct_types::Error.none; }

        let arm_stmt = unwrapSingleBody(m, marms[0].body);
        if arm_stmt == 0 { return squid_direct_types::Error.none; }
        let asn = m.node(arm_stmt);
        if asn.tag != squid_check_core::Tag.bind || asn.c >= 2 { return squid_direct_types::Error.none; }
        let merges = m.branchMerges(body_node);
        if merges.len != 1 || merges[0].result != sum_back || merges[0].then_binding != asn.a || merges[0].else_binding != sum_iter {
            return squid_direct_types::Error.none;
        }
        let en = m.node(asn.b);
        let is_op = en.tag == squid_check_core::Tag.scalar || (en.tag == squid_check_core::Tag.associated && en.op != squid_check_core::Op.none);
        if !is_op || (en.op != squid_check_core::Op.add && en.op != squid_check_core::Op.bit_xor) {
            return squid_direct_types::Error.none;
        }
        var rhs: u32 = 0;
        if localRef(m, en.a) == sum_iter { rhs = en.b; }
        else if localRef(m, en.b) == sum_iter { rhs = en.a; }
        else { return squid_direct_types::Error.none; }
        let cok, csigned, farg = matchVec3F32ToInt(g, m, rhs);
        if !cok || !checkVec3F32Expr(g, f, m, farg, p_bs, iter_b, sum_iter, 0) {
            return squid_direct_types::Error.none;
        }
        arr_inlined = inl_ref;
        f_expr_id = farg;
        is_xor = en.op == squid_check_core::Op.bit_xor;
        is_signed_conv = csigned;
        matched = true;
    }
    if !matched { return squid_direct_types::Error.none; }

    if arr_inlined.binding != 0 { g.recordInlined(arr_inlined.unit, arr_inlined.binding); }
    let av, _ = bindGet(g, f, arr_b);
    let ada = findDirectArrayBySlot(f, w(g, av, 0));
    if ada >= 0 && f.direct_arrays[ada].scalar_packed { return squid_direct_types::Error.none; }
    let arr_base, arr_len = ensureCheckedArray(g, f, av);

    let simd_n = local32(g, f);
    lget(g, end_local);
    lget(g, index);
    op(g, OP_i32_gt_u);
    let cnt_if = open(g, f, OP_if_);
    lget(g, end_local);
    lget(g, index);
    op(g, OP_i32_sub);
    i32Const(g, 0xfffffffc);
    op(g, OP_i32_and);
    lset(g, simd_n);
    popCheckedArraysAt(f, cnt_if);
    op(g, OP_else_);
    i32Const(g, 0);
    lset(g, simd_n);
    close(g, f);

    // Guard: simd_n > 0 && end_local <= arr_len (exact OOB trap order preserved in scalar tail!)
    lget(g, simd_n);
    i32Const(g, 0);
    op(g, OP_i32_gt_u);
    lget(g, end_local);
    lget(g, arr_len);
    op(g, OP_i32_le_u);
    op(g, OP_i32_and);
    let guard_if = open(g, f, OP_if_);

    let ptr = local32(g, f);
    lget(g, arr_base);
    lget(g, index);
    i32Const(g, 4);
    op(g, OP_i32_shl);
    op(g, OP_i32_add);
    lset(g, ptr);

    let rem = local32(g, f);
    lget(g, simd_n);
    lset(g, rem);

    let vacc = local(g, f, VT_v128); v128Const4(g, 0); lset(g, vacc);
    let vzero = local(g, f, VT_v128); v128Const4(g, 0); lset(g, vzero);
    let v0 = local(g, f, VT_v128);
    let v1 = local(g, f, VT_v128);
    let v2 = local(g, f, VT_v128);
    let v3 = local(g, f, VT_v128);
    let t01 = local(g, f, VT_v128);
    let t23 = local(g, f, VT_v128);
    let vtag = local(g, f, VT_v128);
    var v_xyz: u32[3] = [0; 3];
    v_xyz[0] = local(g, f, VT_v128);
    v_xyz[1] = local(g, f, VT_v128);
    v_xyz[2] = local(g, f, VT_v128);

    let r_exit = open(g, f, OP_block);
    let r_top = open(g, f, OP_loop);
    lget(g, rem); op(g, OP_i32_eqz); br(g, f, OP_br_if, r_exit);

    // Descending 48,32,16,0 v128.load => 1 software bounds check per 4 entities (64 bytes)!
    lget(g, ptr); simdMemOp(g, SIMD_v128_load, 2, 48); lset(g, v3);
    lget(g, ptr); simdMemOp(g, SIMD_v128_load, 2, 32); lset(g, v2);
    lget(g, ptr); simdMemOp(g, SIMD_v128_load, 2, 16); lset(g, v1);
    lget(g, ptr); simdMemOp(g, SIMD_v128_load, 2, 0);  lset(g, v0);

    // 4x4 SoA transpose via 8 shuffles (peak <= 10 live XMMs -> zero spills!):
    lget(g, v0); lget(g, v1); emitI32x4Shuffle(g, 0, 4, 1, 5); lset(g, t01);
    lget(g, v2); lget(g, v3); emitI32x4Shuffle(g, 0, 4, 1, 5); lset(g, t23);
    lget(g, t01); lget(g, t23); emitI32x4Shuffle(g, 0, 1, 4, 5); lset(g, vtag);
    lget(g, t01); lget(g, t23); emitI32x4Shuffle(g, 2, 3, 6, 7); lset(g, v_xyz[0]);

    lget(g, v0); lget(g, v1); emitI32x4Shuffle(g, 2, 6, 3, 7); lset(g, t01);
    lget(g, v2); lget(g, v3); emitI32x4Shuffle(g, 2, 6, 3, 7); lset(g, t23);
    lget(g, t01); lget(g, t23); emitI32x4Shuffle(g, 0, 1, 4, 5); lset(g, v_xyz[1]);
    lget(g, t01); lget(g, t23); emitI32x4Shuffle(g, 2, 3, 6, 7); lset(g, v_xyz[2]);

    // Evaluate F32 expression in exact AST order, convert to U32/I32, mask branchlessly by tag == 0!
    lget(g, vacc);
    emitVec3F32Expr(g, f, g.units[f.unit - 1], f_expr_id, p_bs, v_xyz);
    if squid_direct_writer::relaxedSimdEnabled() {
        if is_signed_conv { simdOp(g, SIMD_i32x4_relaxed_trunc_f32x4_s); }
        else { simdOp(g, SIMD_i32x4_relaxed_trunc_f32x4_u); }
    } else if is_signed_conv { simdOp(g, SIMD_i32x4_trunc_sat_f32x4_s); }
    else { simdOp(g, SIMD_i32x4_trunc_sat_f32x4_u); }
    lget(g, vtag);
    lget(g, vzero);
    simdOp(g, SIMD_i32x4_eq);
    simdOp(g, SIMD_v128_and);
    if is_xor { simdOp(g, SIMD_v128_xor); } else { simdOp(g, SIMD_i32x4_add); }
    lset(g, vacc);

    lget(g, ptr); i32Const(g, 64); op(g, OP_i32_add); lset(g, ptr);
    lget(g, rem); i32Const(g, 4); op(g, OP_i32_sub); lset(g, rem);
    br(g, f, OP_br, r_top);
    close(g, f);
    close(g, f);

    let cloc = w(g, g.s.vals[iteration.start + sum_ci], 0);
    var sop = OP_i32_add;
    if is_xor { sop = OP_i32_xor; }
    lget(g, cloc);
    for lane in 0..4 {
        lget(g, vacc);
        simdLaneOp(g, SIMD_i32x4_extract_lane, lane as u8);
        op(g, sop);
    }
    lset(g, cloc);

    lget(g, index);
    lget(g, simd_n);
    op(g, OP_i32_add);
    lset(g, index);

    popCheckedArraysAt(f, guard_if);
    close(g, f);
    f.checked_elems_len = 0;
    return squid_direct_types::Error.none;
}

// 5E: 4-wide `v128` outer-loop SIMD for pure escape-time accumulation loops:
//   for px in start .. end:
//     let prelude_0 = ... ; ... ; let it = 0
//     for ever:
//       if it >= limit: break
//       ...
//       if escape_cond: break
//       ...
//       it := it + 1
//     total := total + it
// Runs 4 pixels simultaneously in `v128` with monotone lane disable (`v128.andnot`),
// `v128.any_true` early exit, exact `i32x4.sub(it_v, active_v)`, and scalar tail for `< 4` pixels.
recursive fn exprHasBitsOp(m: const Module&, id: u32, budget: i64&) -> bool {
    if id == 0 { return false; }
    if budget <= 0 { return true; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        constant, reference => { return false; },
        scalar, associated => {
            if n.op == squid_check_core::Op.bits || n.op == squid_check_core::Op.from_bits { return true; }
            return exprHasBitsOp(m, n.a, budget) || exprHasBitsOp(m, n.b, budget);
        },
        logical => { return exprHasBitsOp(m, n.a, budget) || exprHasBitsOp(m, n.b, budget); },
        if_value => { return exprHasBitsOp(m, n.a, budget) || exprHasBitsOp(m, n.b, budget) || exprHasBitsOp(m, n.c, budget); },
        return_, project => { return exprHasBitsOp(m, n.a, budget); },
        bind => { return exprHasBitsOp(m, n.b, budget); },
        block_, suite => {
            for c in m.children(id) { if exprHasBitsOp(m, c, budget) { return true; } }
            return false;
        },
        call => {
            for a in m.call(id).arguments { if exprHasBitsOp(m, a, budget) { return true; } }
            return false;
        },
        _ => { return true; },
    }
}
fn tryEmitVectorEscapeLoop(
    g: Generator&,
    f: Fn&,
    loop_id: u32,
    info: squid_check_core::LoopInfo,
    iteration: Vals,
    carry_in_place: const bool[64]&,
    index: u32,
    end_local: u32,
) -> Error {
    if g.runtime_().has_fork || info.kind != squid_check_core::LoopKind.range || info.pattern == 0 || info.body == 0 {
        return squid_direct_types::Error.none;
    }

    var total_ci: i64 = -1;
    var limit_id: u32 = 0;
    var exit_cond_id: u32 = 0;
    var pre_b: u32[8] = [0; 8];
    var pre_expr: u32[8] = [0; 8];
    var pre_skip: bool[8] = [false; 8];
    var pre_len: i64 = 0;

    var ic_count: i64 = 0;
    var ic_incoming: u32[8] = [0; 8];
    var ic_iter: u32[8] = [0; 8];
    var ic_back: u32[8] = [0; 8];
    var ic_tag: squid_direct_types::Tag[8] = [squid_direct_types::Tag.unit; 8];
    var it_ci: i64 = -1;

    var pre_exit_b: u32[8] = [0; 8];
    var pre_exit_expr: u32[8] = [0; 8];
    var pre_exit_len: i64 = 0;
    var post_exit_b: u32[8] = [0; 8];
    var post_exit_expr: u32[8] = [0; 8];
    var post_exit_len: i64 = 0;

    var plan = SparkVecPlan {};
    var matched = false;

    {
        let m .= g.units[f.unit - 1];
        let pat = m.pattern(info.pattern);
        if pat.tag != squid_check_core::PatternTag.bind { return squid_direct_types::Error.none; }
        let iter_b = pat.a;

        let carries = m.loopCarries(loop_id);
        if carries.len == 0 || carries.len > 64 { return squid_direct_types::Error.none; }
        for carry, ci in carries {
            if carry_in_place[ci] { continue; }
            if total_ci >= 0 || carry.backedge == 0 { return squid_direct_types::Error.none; }
            let iv = g.s.vals[iteration.start + ci];
            if iv.len != 1 || tagOf(g, iv.ty) != squid_direct_types::Tag.u32_ { return squid_direct_types::Error.none; }
            total_ci = ci;
        }
        if total_ci < 0 { return squid_direct_types::Error.none; }
        let total_iter = carries[total_ci].iteration;
        let total_back = carries[total_ci].backedge;

        let bn = m.node(info.body);
        if bn.tag != squid_check_core::Tag.suite && bn.tag != squid_check_core::Tag.block_ {
            return squid_direct_types::Error.none;
        }
        let ch = m.children(info.body);
        if ch.len < 3 || ch.len > 10 { return squid_direct_types::Error.none; }

        let inner_idx = ch.len - 2;
        let inner_id = ch[inner_idx];
        if m.node(inner_id).tag != squid_check_core::Tag.loop_ { return squid_direct_types::Error.none; }
        let inner_info = m.loopInfo(inner_id);
        if inner_info.kind != squid_check_core::LoopKind.forever || inner_info.body == 0 {
            return squid_direct_types::Error.none;
        }

        plan = SparkVecPlan {
            spark_unit: m.unit,
            is_range: true,
            iter_binding: iter_b,
            iter_tag: squid_direct_types::Tag.u32_,
            out_tag: squid_direct_types::Tag.u32_,
            budget: 256,
        };
        plan.locals[0] = SparkVecLocal {
            unit: m.unit,
            binding: iter_b,
            tag: squid_direct_types::Tag.u32_,
            is_mask: false,
            invariant: false,
        };
        plan.locals_len = 1;

        // 1. Validate leading pure vectorizable prelude binds.
        for pi in 0..inner_idx {
            let cn = m.node(ch[pi]);
            if cn.tag != squid_check_core::Tag.bind || cn.c >= 2 || m.binding(cn.a).scheme.variables.len != 0 {
                return squid_direct_types::Error.none;
            }
            let bty, bok = lowerInEnv(g, m, m.typeOf(cn.b), f.env);
            if !bok || !isSparkLaneTag(tagOf(g, bty)) || plan.locals_len >= 64 || pre_len >= 8 {
                return squid_direct_types::Error.none;
            }
            var bb: i64 = 64;
            if exprHasBitsOp(m, cn.b, bb) { return squid_direct_types::Error.none; }
            if !checkVecExpr(g, f, plan, m, f.env, cn.b, 0, 0, false) || plan.streams_len != 0 {
                return squid_direct_types::Error.none;
            }
            let btag = tagOf(g, bty);
            pre_b[pre_len] = cn.a;
            pre_expr[pre_len] = cn.b;
            pre_len += 1;
            plan.locals[plan.locals_len] = SparkVecLocal {
                unit: m.unit,
                binding: cn.a,
                tag: btag,
                is_mask: btag == squid_direct_types::Tag.boolean,
                invariant: isInvariantScalarExpr(g, f, plan, m, f.env, cn.b, btag, 0),
            };
            plan.locals_len += 1;
        }

        // 2. Validate inner `for ever` carries: exactly one outgoing U32 counter `it` initialized to 0.
        let icarries = m.loopCarries(inner_id);
        if icarries.len == 0 || icarries.len > 8 { return squid_direct_types::Error.none; }
        ic_count = icarries.len;
        for ic, ci in icarries {
            if ic.backedge == 0 { return squid_direct_types::Error.none; }
            let cty, cok = lowerInEnv(g, m, m.binding(ic.iteration).ty, f.env);
            if !cok || !isSparkLaneTag(tagOf(g, cty)) { return squid_direct_types::Error.none; }
            let ctag = tagOf(g, cty);
            ic_incoming[ci] = ic.incoming;
            ic_iter[ci] = ic.iteration;
            ic_back[ci] = ic.backedge;
            ic_tag[ci] = ctag;
            if uses(g, f, ic.outgoing) != 0 {
                if it_ci >= 0 || ctag != squid_direct_types::Tag.u32_ { return squid_direct_types::Error.none; }
                it_ci = ci;
            }
        }
        if it_ci < 0 { return squid_direct_types::Error.none; }

        // Verify `it` is initialized to constant 0 in the prelude!
        var it_pre_idx: i64 = -1;
        var it_init_node: u32 = 0;
        for pi in 0..pre_len {
            if pre_b[pi] == ic_incoming[it_ci] {
                let en = m.node(pre_expr[pi]);
                if en.tag == squid_check_core::Tag.constant && en.a == 0 {
                    it_pre_idx = pi;
                    it_init_node = pre_expr[pi];
                    pre_skip[pi] = true;
                }
                break;
            }
        }
        if it_pre_idx < 0 { return squid_direct_types::Error.none; }

        // Register all non-`it` inner carry iterations in plan.locals (leaving `it` out so
        // checkVecExpr automatically rejects any expression reading `it` inside the escape loop!).
        for ci in 0..ic_count {
            if ci == it_ci { continue; }
            if findVecLocal(plan, m.unit, ic_incoming[ci]) < 0 {
                let bv, bok = bindGet(g, f, ic_incoming[ci]);
                if !bok || tagOf(g, bv.ty) != ic_tag[ci] { return squid_direct_types::Error.none; }
                let _, is_cell = withCellType(g, f, ic_incoming[ci]);
                if is_cell || ic_incoming[ci] == total_iter { return squid_direct_types::Error.none; }
            }
            if plan.locals_len >= 64 { return squid_direct_types::Error.none; }
            plan.locals[plan.locals_len] = SparkVecLocal {
                unit: m.unit,
                binding: ic_iter[ci],
                tag: ic_tag[ci],
                is_mask: ic_tag[ci] == squid_direct_types::Tag.boolean,
                invariant: false,
            };
            plan.locals_len += 1;
        }

        // 3. Validate inner `for ever` body:
        //    ich[0]: `if it >= limit: break`
        //    ich[1..]: pure binds + exactly 1 `if escape_cond: break` + `it := it + 1`
        let ibn = m.node(inner_info.body);
        if ibn.tag != squid_check_core::Tag.suite && ibn.tag != squid_check_core::Tag.block_ {
            return squid_direct_types::Error.none;
        }
        let ich = m.children(inner_info.body);
        if ich.len < 3 || ich.len > 16 { return squid_direct_types::Error.none; }

        let s0 = m.node(ich[0]);
        if s0.tag != squid_check_core::Tag.if_stmt || s0.c != 0 || !isBreakBody(m, s0.b) {
            return squid_direct_types::Error.none;
        }
        let c0 = m.node(s0.a);
        let c0_is_op = c0.tag == squid_check_core::Tag.scalar || (c0.tag == squid_check_core::Tag.associated && c0.op != squid_check_core::Op.none);
        if !c0_is_op { return squid_direct_types::Error.none; }
        if c0.op == squid_check_core::Op.greater_equal && localRef(m, c0.a) == ic_iter[it_ci] {
            limit_id = c0.b;
        } else if c0.op == squid_check_core::Op.less_equal && localRef(m, c0.b) == ic_iter[it_ci] {
            limit_id = c0.a;
        } else {
            return squid_direct_types::Error.none;
        }
        let lim_ref = localRef(m, limit_id);
        if lim_ref == 0 && m.node(limit_id).tag != squid_check_core::Tag.constant { return squid_direct_types::Error.none; }
        if lim_ref != 0 {
            if lim_ref == iter_b || lim_ref == total_iter || findVecLocal(plan, m.unit, lim_ref) >= 0 {
                return squid_direct_types::Error.none;
            }
            let _, is_cell = withCellType(g, f, lim_ref);
            if is_cell { return squid_direct_types::Error.none; }
        }

        var found_exit = false;
        var found_it_inc = false;
        var it_inc_node: u32 = 0;
        for si in 1..ich.len {
            let sn = m.node(ich[si]);
            if sn.tag == squid_check_core::Tag.if_stmt && sn.c == 0 && isBreakBody(m, sn.b) {
                if found_exit { return squid_direct_types::Error.none; }
                let cty, cok = lowerInEnv(g, m, m.typeOf(sn.a), f.env);
                if !cok || tagOf(g, cty) != squid_direct_types::Tag.boolean { return squid_direct_types::Error.none; }
                var bb: i64 = 64;
                if exprHasBitsOp(m, sn.a, bb) { return squid_direct_types::Error.none; }
                if !checkVecExpr(g, f, plan, m, f.env, sn.a, 0, 0, false) || plan.streams_len != 0 {
                    return squid_direct_types::Error.none;
                }
                exit_cond_id = sn.a;
                found_exit = true;
            } else if sn.tag == squid_check_core::Tag.bind && sn.c < 2 && m.binding(sn.a).scheme.variables.len == 0 {
                if sn.a == ic_back[it_ci] {
                    if !found_exit || found_it_inc || !matchVarPlusConstOne(m, sn.b, ic_iter[it_ci]) {
                        return squid_direct_types::Error.none;
                    }
                    it_inc_node = sn.b;
                    found_it_inc = true;
                } else {
                    let bty, bok = lowerInEnv(g, m, m.typeOf(sn.b), f.env);
                    if !bok || !isSparkLaneTag(tagOf(g, bty)) || plan.locals_len >= 64 { return squid_direct_types::Error.none; }
                    var bb: i64 = 64;
                    if exprHasBitsOp(m, sn.b, bb) { return squid_direct_types::Error.none; }
                    if !checkVecExpr(g, f, plan, m, f.env, sn.b, 0, 0, false) || plan.streams_len != 0 {
                        return squid_direct_types::Error.none;
                    }
                    if !found_exit {
                        if pre_exit_len >= 8 { return squid_direct_types::Error.none; }
                        pre_exit_b[pre_exit_len] = sn.a;
                        pre_exit_expr[pre_exit_len] = sn.b;
                        pre_exit_len += 1;
                    } else {
                        if post_exit_len >= 8 { return squid_direct_types::Error.none; }
                        post_exit_b[post_exit_len] = sn.a;
                        post_exit_expr[post_exit_len] = sn.b;
                        post_exit_len += 1;
                    }
                    let btag = tagOf(g, bty);
                    plan.locals[plan.locals_len] = SparkVecLocal {
                        unit: m.unit,
                        binding: sn.a,
                        tag: btag,
                        is_mask: btag == squid_direct_types::Tag.boolean,
                        invariant: false,
                    };
                    plan.locals_len += 1;
                }
            } else {
                return squid_direct_types::Error.none;
            }
        }
        if !found_exit || !found_it_inc { return squid_direct_types::Error.none; }
        for ci in 0..ic_count {
            if ci == it_ci { continue; }
            if findVecLocal(plan, m.unit, ic_back[ci]) < 0 { return squid_direct_types::Error.none; }
        }

        // 4. Validate trailing `total_back := total_iter + it_out`
        let last_n = m.node(ch[ch.len - 1]);
        if last_n.tag != squid_check_core::Tag.bind || last_n.c >= 2 || last_n.a != total_back {
            return squid_direct_types::Error.none;
        }
        let add_n = m.node(last_n.b);
        let add_is_op = add_n.tag == squid_check_core::Tag.scalar || (add_n.tag == squid_check_core::Tag.associated && add_n.op != squid_check_core::Op.none);
        if !add_is_op || add_n.op != squid_check_core::Op.add { return squid_direct_types::Error.none; }
        let it_out = icarries[it_ci].outgoing;
        let a_ref = localRef(m, add_n.a);
        let b_ref = localRef(m, add_n.b);
        if !((a_ref == total_iter && b_ref == it_out) || (a_ref == it_out && b_ref == total_iter)) {
            return squid_direct_types::Error.none;
        }

        // 5. Ensure no hoisted outer scalar is the loop-carried `total_iter`.
        for hi in 0..plan.hoisted_len {
            if plan.hoisted[hi].node_id == total_iter { return squid_direct_types::Error.none; }
        }
        squid_direct_relocations::unpatchableOperand(m.unit, it_init_node);
        markUnpatchableExprConstants(m, it_inc_node, 0);
        matched = true;
    }
    if !matched { return squid_direct_types::Error.none; }

    let lim_val, lerr = expr(g, f, limit_id);
    if lerr != squid_direct_types::Error.none { return lerr; }
    let limit_loc = w(g, lim_val, 0);

    // Pre-splat all loop-invariant outer scalars (e.g., `inv`, `ci`) ONCE before the SIMD loops!
    for hi in 0..plan.hoisted_len {
        let h = plan.hoisted[hi];
        let vl = local(g, f, VT_v128);
        if h.tag == squid_direct_types::Tag.boolean {
            i32Const(g, 0); lget(g, h.scalar_local); op(g, OP_i32_sub); simdOp(g, SIMD_i32x4_splat);
        } else if h.tag == squid_direct_types::Tag.f32_ {
            lget(g, h.scalar_local); simdOp(g, SIMD_f32x4_splat);
        } else {
            lget(g, h.scalar_local); simdOp(g, SIMD_i32x4_splat);
        }
        lset(g, vl);
        plan.hoisted[hi].vlocal = vl;
    }

    let total_loc = w(g, g.s.vals[iteration.start + total_ci], 0);
    let prev_defer = f.defer_f32_nan;
    f.defer_f32_nan = true;

    // 6C: Dual-stream 8-pixel `v128` escape loop (2 independent 4-pixel vectors in flight
    // to hide serial FP mul+add latency while keeping live XMM regs <= 14).
    if ic_count <= 4 && pre_len <= 5 {
        let simd_8 = local32(g, f);
        lget(g, end_local); lget(g, index); op(g, OP_i32_gt_u);
        let c8_if = open(g, f, OP_if_);
        lget(g, end_local); lget(g, index); op(g, OP_i32_sub);
        i32Const(g, 0xfffffff8); op(g, OP_i32_and); lset(g, simd_8);
        popCheckedArraysAt(f, c8_if);
        op(g, OP_else_);
        i32Const(g, 0); lset(g, simd_8);
        close(g, f);

        lget(g, simd_8); i32Const(g, 0); op(g, OP_i32_gt_u);
        let r8_if = open(g, f, OP_if_);

        var vlocs_a: u32[64] = [0; 64];
        var vlocs_b: u32[64] = [0; 64];
        let shared_from = plan.locals_len - (pre_exit_len + post_exit_len);
        for li in 0..plan.locals_len {
            vlocs_a[li] = local(g, f, VT_v128);
            if li < shared_from {
                vlocs_b[li] = local(g, f, VT_v128);
            } else {
                vlocs_b[li] = vlocs_a[li];
            }
        }

        lget(g, index); simdOp(g, SIMD_i32x4_splat);
        v128ConstWords(g, 0, 1, 2, 3); simdOp(g, SIMD_i32x4_add); lset(g, vlocs_a[0]);
        lget(g, index); simdOp(g, SIMD_i32x4_splat);
        v128ConstWords(g, 4, 5, 6, 7); simdOp(g, SIMD_i32x4_add); lset(g, vlocs_b[0]);

        let v8_local = local(g, f, VT_v128);
        v128Const4(g, 8); lset(g, v8_local);

        let k8_loc = constLocal(g, f, 0);
        let step8_i = local32(g, f);
        let it_a = local(g, f, VT_v128);
        let it_b = local(g, f, VT_v128);
        let act_a = local(g, f, VT_v128);
        let act_b = local(g, f, VT_v128);

        let out8_exit = open(g, f, OP_block);
        let out8_top = open(g, f, OP_loop);
        lget(g, k8_loc); lget(g, simd_8); op(g, OP_i32_ge_u); br(g, f, OP_br_if, out8_exit);

        // Emit prelude + carry init for stream A and stream B
        for st in 0..2 {
            for li in 0..plan.locals_len {
                if st == 0 { plan.locals[li].vlocal = vlocs_a[li]; }
                else { plan.locals[li].vlocal = vlocs_b[li]; }
            }
            for pi in 0..pre_len {
                if pre_skip[pi] { continue; }
                let m_e .= g.units[f.unit - 1];
                let perr = emitVecExpr(g, f, plan, m_e, f.env, pre_expr[pi], false);
                if perr != squid_direct_types::Error.none { f.defer_f32_nan = prev_defer; return perr; }
                let lidx = findVecLocal(plan, m_e.unit, pre_b[pi]);
                assert(lidx >= 0);
                lset(g, plan.locals[lidx].vlocal);
            }
            for ci in 0..ic_count {
                if ci == it_ci { continue; }
                let dst_idx = findVecLocal(plan, plan.spark_unit, ic_iter[ci]);
                assert(dst_idx >= 0);
                let src_idx = findVecLocal(plan, plan.spark_unit, ic_incoming[ci]);
                if src_idx >= 0 {
                    lget(g, plan.locals[src_idx].vlocal);
                } else {
                    let bv, _ = bindGet(g, f, ic_incoming[ci]);
                    if ic_tag[ci] == squid_direct_types::Tag.boolean {
                        i32Const(g, 0); lget(g, w(g, bv, 0)); op(g, OP_i32_sub); simdOp(g, SIMD_i32x4_splat);
                    } else if ic_tag[ci] == squid_direct_types::Tag.f32_ {
                        lget(g, w(g, bv, 0)); simdOp(g, SIMD_f32x4_splat);
                    } else {
                        lget(g, w(g, bv, 0)); simdOp(g, SIMD_i32x4_splat);
                    }
                }
                lset(g, plan.locals[dst_idx].vlocal);
            }
        }

        v128Const4(g, 0); lset(g, it_a);
        v128Const4(g, 0); lset(g, it_b);
        v128Const4(g, 0xffffffff); lset(g, act_a);
        v128Const4(g, 0xffffffff); lset(g, act_b);
        i32Const(g, 0); lset(g, step8_i);

        let in8_exit = open(g, f, OP_block);
        let in8_top = open(g, f, OP_loop);
        lget(g, step8_i); lget(g, limit_loc); op(g, OP_i32_ge_u); br(g, f, OP_br_if, in8_exit);

        // Execute stream A completely then stream B so per-step temps (zr2, zi2, nzi, ...)
        // die immediately and share registers across streams (keeping live XMM <= 14!).
        // If both streams finish on this step (act_a == 0 && act_b == 0), `it - 0 == it`
        // and the post-exit state is pure and dead after `br_if in8_exit`.
        for st in 0..2 {
            let cur_act = if st == 0 { act_a } else { act_b };
            let cur_it = if st == 0 { it_a } else { it_b };
            for li in 0..plan.locals_len {
                if st == 0 { plan.locals[li].vlocal = vlocs_a[li]; }
                else { plan.locals[li].vlocal = vlocs_b[li]; }
            }
            for bi in 0..pre_exit_len {
                let m_e .= g.units[f.unit - 1];
                let berr = emitVecExpr(g, f, plan, m_e, f.env, pre_exit_expr[bi], false);
                if berr != squid_direct_types::Error.none { f.defer_f32_nan = prev_defer; return berr; }
                let lidx = findVecLocal(plan, m_e.unit, pre_exit_b[bi]);
                assert(lidx >= 0);
                lset(g, plan.locals[lidx].vlocal);
            }
            let c_err = emitVecExpr(g, f, plan, g.units[f.unit - 1], f.env, exit_cond_id, false);
            if c_err != squid_direct_types::Error.none { f.defer_f32_nan = prev_defer; return c_err; }
            simdOp(g, SIMD_v128_not);
            lget(g, cur_act);
            simdOp(g, SIMD_v128_and);
            lset(g, cur_act);

            for bi in 0..post_exit_len {
                let m_e .= g.units[f.unit - 1];
                let berr = emitVecExpr(g, f, plan, m_e, f.env, post_exit_expr[bi], false);
                if berr != squid_direct_types::Error.none { f.defer_f32_nan = prev_defer; return berr; }
                let lidx = findVecLocal(plan, m_e.unit, post_exit_b[bi]);
                assert(lidx >= 0);
                lset(g, plan.locals[lidx].vlocal);
            }
            for ci in 0..ic_count {
                if ci == it_ci { continue; }
                let dst_idx = findVecLocal(plan, plan.spark_unit, ic_iter[ci]);
                let src_idx = findVecLocal(plan, plan.spark_unit, ic_back[ci]);
                if dst_idx >= 0 && src_idx >= 0 && dst_idx != src_idx {
                    lget(g, plan.locals[src_idx].vlocal);
                    lset(g, plan.locals[dst_idx].vlocal);
                }
            }
            lget(g, cur_it); lget(g, cur_act); simdOp(g, SIMD_i32x4_sub); lset(g, cur_it);
        }

        lget(g, act_a);
        lget(g, act_b);
        simdOp(g, SIMD_v128_or);
        simdOp(g, SIMD_v128_any_true);
        op(g, OP_i32_eqz);
        br(g, f, OP_br_if, in8_exit);

        lget(g, step8_i); i32Const(g, 1); op(g, OP_i32_add); lset(g, step8_i);
        br(g, f, OP_br, in8_top);
        close(g, f);
        close(g, f);

        // Combine it_a + it_b into 1 vector => only 4 lane extracts for 8 pixels!
        let vtot = local(g, f, VT_v128);
        lget(g, it_a); lget(g, it_b); simdOp(g, SIMD_i32x4_add); lset(g, vtot);
        lget(g, total_loc);
        for lane in 0..4 {
            lget(g, vtot);
            simdLaneOp(g, SIMD_i32x4_extract_lane, lane as u8);
            op(g, OP_i32_add);
        }
        lset(g, total_loc);

        lget(g, vlocs_a[0]); lget(g, v8_local); simdOp(g, SIMD_i32x4_add); lset(g, vlocs_a[0]);
        lget(g, vlocs_b[0]); lget(g, v8_local); simdOp(g, SIMD_i32x4_add); lset(g, vlocs_b[0]);
        lget(g, k8_loc); i32Const(g, 8); op(g, OP_i32_add); lset(g, k8_loc);
        br(g, f, OP_br, out8_top);
        close(g, f);
        close(g, f);

        lget(g, index); lget(g, simd_8); op(g, OP_i32_add); lset(g, index);
        popCheckedArraysAt(f, r8_if);
        close(g, f);
    }

    // 5E: 4-pixel `v128` loop for any remaining 4..7 pixels (or wide escape bodies).
    let simd_n = local32(g, f);
    lget(g, end_local);
    lget(g, index);
    op(g, OP_i32_gt_u);
    let cnt_if = open(g, f, OP_if_);
    lget(g, end_local);
    lget(g, index);
    op(g, OP_i32_sub);
    i32Const(g, 0xfffffffc);
    op(g, OP_i32_and);
    lset(g, simd_n);
    popCheckedArraysAt(f, cnt_if);
    op(g, OP_else_);
    i32Const(g, 0);
    lset(g, simd_n);
    close(g, f);

    lget(g, simd_n);
    i32Const(g, 0);
    op(g, OP_i32_gt_u);
    let run_if = open(g, f, OP_if_);

    // Allocate v128 locals for every entry in plan.locals!
    let iter_vlocal = local(g, f, VT_v128);
    plan.locals[0].vlocal = iter_vlocal;
    for li in 1..plan.locals_len {
        plan.locals[li].vlocal = local(g, f, VT_v128);
    }

    lget(g, index);
    simdOp(g, SIMD_i32x4_splat);
    v128ConstWords(g, 0, 1, 2, 3);
    simdOp(g, SIMD_i32x4_add);
    lset(g, iter_vlocal);

    let v4_local = local(g, f, VT_v128);
    v128Const4(g, 4);
    lset(g, v4_local);

    let k_loc = constLocal(g, f, 0);
    let step_i = local32(g, f);
    let it_v = local(g, f, VT_v128);
    let active_v = local(g, f, VT_v128);

    let out_exit = open(g, f, OP_block);
    let out_top = open(g, f, OP_loop);
    lget(g, k_loc);
    lget(g, simd_n);
    op(g, OP_i32_ge_u);
    br(g, f, OP_br_if, out_exit);

    // 1. Emit prelude binds (`cr`, `zr`, `zi`, ...).
    for pi in 0..pre_len {
        if pre_skip[pi] { continue; }
        let m_e .= g.units[f.unit - 1];
        let perr = emitVecExpr(g, f, plan, m_e, f.env, pre_expr[pi], false);
        if perr != squid_direct_types::Error.none { f.defer_f32_nan = prev_defer; return perr; }
        let lidx = findVecLocal(plan, m_e.unit, pre_b[pi]);
        assert(lidx >= 0);
        lset(g, plan.locals[lidx].vlocal);
    }

    // 2. Seed inner carry iteration vlocals from incoming values.
    for ci in 0..ic_count {
        if ci == it_ci { continue; }
        let dst_idx = findVecLocal(plan, plan.spark_unit, ic_iter[ci]);
        assert(dst_idx >= 0);
        let src_idx = findVecLocal(plan, plan.spark_unit, ic_incoming[ci]);
        if src_idx >= 0 {
            lget(g, plan.locals[src_idx].vlocal);
        } else {
            let bv, _ = bindGet(g, f, ic_incoming[ci]);
            if ic_tag[ci] == squid_direct_types::Tag.boolean {
                i32Const(g, 0); lget(g, w(g, bv, 0)); op(g, OP_i32_sub); simdOp(g, SIMD_i32x4_splat);
            } else if ic_tag[ci] == squid_direct_types::Tag.f32_ {
                lget(g, w(g, bv, 0)); simdOp(g, SIMD_f32x4_splat);
            } else {
                lget(g, w(g, bv, 0)); simdOp(g, SIMD_i32x4_splat);
            }
        }
        lset(g, plan.locals[dst_idx].vlocal);
    }

    v128Const4(g, 0); lset(g, it_v);
    v128Const4(g, 0xffffffff); lset(g, active_v);
    i32Const(g, 0); lset(g, step_i);

    // 3. 4-pixel inner escape loop!
    let in_exit = open(g, f, OP_block);
    let in_top = open(g, f, OP_loop);
    lget(g, step_i);
    lget(g, limit_loc);
    op(g, OP_i32_ge_u);
    br(g, f, OP_br_if, in_exit);

    for bi in 0..pre_exit_len {
        let m_e .= g.units[f.unit - 1];
        let berr = emitVecExpr(g, f, plan, m_e, f.env, pre_exit_expr[bi], false);
        if berr != squid_direct_types::Error.none { f.defer_f32_nan = prev_defer; return berr; }
        let lidx = findVecLocal(plan, m_e.unit, pre_exit_b[bi]);
        assert(lidx >= 0);
        lset(g, plan.locals[lidx].vlocal);
    }

    // active_v = active_v & ~escaped_v; if !any_true(active_v): break!
    let cerr = emitVecExpr(g, f, plan, g.units[f.unit - 1], f.env, exit_cond_id, false);
    if cerr != squid_direct_types::Error.none { f.defer_f32_nan = prev_defer; return cerr; }
    simdOp(g, SIMD_v128_not);
    lget(g, active_v);
    simdOp(g, SIMD_v128_and);
    ltee(g, active_v);
    simdOp(g, SIMD_v128_any_true);
    op(g, OP_i32_eqz);
    br(g, f, OP_br_if, in_exit);

    for bi in 0..post_exit_len {
        let m_e .= g.units[f.unit - 1];
        let berr = emitVecExpr(g, f, plan, m_e, f.env, post_exit_expr[bi], false);
        if berr != squid_direct_types::Error.none { f.defer_f32_nan = prev_defer; return berr; }
        let lidx = findVecLocal(plan, m_e.unit, post_exit_b[bi]);
        assert(lidx >= 0);
        lset(g, plan.locals[lidx].vlocal);
    }
    for ci in 0..ic_count {
        if ci == it_ci { continue; }
        let dst_idx = findVecLocal(plan, plan.spark_unit, ic_iter[ci]);
        let src_idx = findVecLocal(plan, plan.spark_unit, ic_back[ci]);
        if dst_idx >= 0 && src_idx >= 0 && dst_idx != src_idx {
            lget(g, plan.locals[src_idx].vlocal);
            lset(g, plan.locals[dst_idx].vlocal);
        }
    }

    // Exact per-lane increment: active_v is 0xffffffff (-1) for active lanes, 0 for escaped lanes!
    lget(g, it_v);
    lget(g, active_v);
    simdOp(g, SIMD_i32x4_sub);
    lset(g, it_v);

    lget(g, step_i);
    i32Const(g, 1);
    op(g, OP_i32_add);
    lset(g, step_i);
    br(g, f, OP_br, in_top);
    close(g, f);
    close(g, f);

    // 4. Horizontal sum of 4 lane iteration counts into `total_loc`.
    lget(g, total_loc);
    for lane in 0..4 {
        lget(g, it_v);
        simdLaneOp(g, SIMD_i32x4_extract_lane, lane as u8);
        op(g, OP_i32_add);
    }
    lset(g, total_loc);

    lget(g, iter_vlocal);
    lget(g, v4_local);
    simdOp(g, SIMD_i32x4_add);
    lset(g, iter_vlocal);

    lget(g, k_loc);
    i32Const(g, 4);
    op(g, OP_i32_add);
    lset(g, k_loc);
    br(g, f, OP_br, out_top);
    close(g, f);
    close(g, f);

    lget(g, index);
    lget(g, simd_n);
    op(g, OP_i32_add);
    lset(g, index);

    popCheckedArraysAt(f, run_if);
    close(g, f);
    f.defer_f32_nan = prev_defer;
    return squid_direct_types::Error.none;
}

// 6B-2: 4-wide `v128` SIMD for affine-LCG array-init loops:
//   for i in start .. end:
//     s := s * A + C
//     a[i] := pure_vec_expr(s)
//     [s := s * A + C
//      b[i] := pure_vec_expr(s)]
// Computes 4 consecutive LCG states (or interleaved odd/even states for 2-step init)
// in `i32x4`, evaluates the pure vectorizable store expressions, writes `v128.store`,
// extracts exact final state `s` on exit, and leaves `< 4` tail to the scalar loop.
fn tryEmitAffineInitLoop(
    g: Generator&,
    f: Fn&,
    loop_id: u32,
    info: squid_check_core::LoopInfo,
    iteration: Vals,
    carry_in_place: const bool[64]&,
    index: u32,
    end_local: u32,
) -> Error {
    if g.runtime_().has_fork || info.kind != squid_check_core::LoopKind.range || info.pattern == 0 || info.body == 0 {
        return squid_direct_types::Error.none;
    }
    var s_ci: i64 = -1;
    var k_steps: i64 = 0;
    var a1: u32 = 0;
    var c1: u32 = 0;
    var s_step_b: u32[2] = [0; 2];
    var dst_b: u32[2] = [0; 2];
    var val_id: u32[2] = [0; 2];
    var plan = SparkVecPlan {};
    var matched = false;

    {
        let m .= g.units[f.unit - 1];
        let pat = m.pattern(info.pattern);
        if pat.tag != squid_check_core::PatternTag.bind { return squid_direct_types::Error.none; }
        let iter_b = pat.a;

        let carries = m.loopCarries(loop_id);
        if carries.len == 0 || carries.len > 64 { return squid_direct_types::Error.none; }
        for carry, ci in carries {
            if carry_in_place[ci] { continue; }
            if s_ci >= 0 || carry.backedge == 0 { return squid_direct_types::Error.none; }
            let iv = g.s.vals[iteration.start + ci];
            if iv.len != 1 || tagOf(g, iv.ty) != squid_direct_types::Tag.u32_ { return squid_direct_types::Error.none; }
            s_ci = ci;
        }
        if s_ci < 0 { return squid_direct_types::Error.none; }
        let s_iter = carries[s_ci].iteration;
        let s_back = carries[s_ci].backedge;

        let bn = m.node(info.body);
        if bn.tag != squid_check_core::Tag.suite && bn.tag != squid_check_core::Tag.block_ {
            return squid_direct_types::Error.none;
        }
        let ch = m.children(info.body);
        if ch.len != 2 && ch.len != 4 { return squid_direct_types::Error.none; }
        k_steps = ch.len / 2;

        plan = SparkVecPlan {
            spark_unit: m.unit,
            is_range: true,
            iter_binding: iter_b,
            iter_tag: squid_direct_types::Tag.u32_,
            out_tag: squid_direct_types::Tag.u32_,
            budget: 128,
        };
        plan.locals[0] = SparkVecLocal {
            unit: m.unit,
            binding: iter_b,
            tag: squid_direct_types::Tag.u32_,
            is_mask: false,
            invariant: false,
        };
        plan.locals_len = 1;

        var step_expr_id: u32[2] = [0; 2];
        var cur_s = s_iter;
        for step in 0..k_steps {
            let bs = m.node(ch[step * 2]);
            if bs.tag != squid_check_core::Tag.bind || bs.c >= 2 { return squid_direct_types::Error.none; }
            let ok, ma, mc = matchAffineU32Step(m, bs.b, cur_s);
            if !ok { return squid_direct_types::Error.none; }
            step_expr_id[step] = bs.b;
            if step == 0 { a1 = ma; c1 = mc; }
            else if ma != a1 || mc != c1 { return squid_direct_types::Error.none; }
            s_step_b[step] = bs.a;
            cur_s = bs.a;
            plan.locals[plan.locals_len] = SparkVecLocal {
                unit: m.unit,
                binding: bs.a,
                tag: squid_direct_types::Tag.u32_,
                is_mask: false,
                invariant: false,
            };
            plan.locals_len += 1;

            let us = ch[step * 2 + 1];
            let un = m.node(us);
            var upd_id: u32 = 0;
            if un.tag == squid_check_core::Tag.update { upd_id = us; }
            else if un.tag == squid_check_core::Tag.bind && un.c < 2 && m.node(un.b).tag == squid_check_core::Tag.update {
                upd_id = un.b;
            } else {
                return squid_direct_types::Error.none;
            }
            let uinfo = m.updateInfo(upd_id);
            let sels = m.updateSelectors(upd_id);
            if sels.len != 1 || sels[0].kind != squid_check_core::UpdateKind.index || localRef(m, sels[0].index) != iter_b {
                return squid_direct_types::Error.none;
            }
            if uinfo.self_binding != 0 && uses(g, f, uinfo.self_binding) != 0 {
                return squid_direct_types::Error.none;
            }
            let db = localRef(m, uinfo.root);
            if db == 0 { return squid_direct_types::Error.none; }
            let dv, dok = bindGet(g, f, db);
            if !dok || tagOf(g, dv.ty) != squid_direct_types::Tag.array { return squid_direct_types::Error.none; }
            let et = tagOf(g, g.types.node(dv.ty).a);
            if et != squid_direct_types::Tag.u32_ && et != squid_direct_types::Tag.f32_ {
                return squid_direct_types::Error.none;
            }
            if !checkVecExpr(g, f, plan, m, f.env, uinfo.value, 0, 0, false) || plan.streams_len != 0 {
                return squid_direct_types::Error.none;
            }
            dst_b[step] = db;
            val_id[step] = uinfo.value;
        }
        if cur_s != s_back || plan.iter_value_used { return squid_direct_types::Error.none; }
        for hi in 0..plan.hoisted_len {
            if plan.hoisted[hi].node_id == s_iter { return squid_direct_types::Error.none; }
        }
        for step in 0..k_steps { markUnpatchableExprConstants(m, step_expr_id[step], 0); }
        matched = true;
    }
    if !matched { return squid_direct_types::Error.none; }

    var dst_base: u32[2] = [0; 2];
    var dst_len: u32[2] = [0; 2];
    for step in 0..k_steps {
        let dv, _ = bindGet(g, f, dst_b[step]);
        let db, dl = ensureCheckedArray(g, f, dv);
        dst_base[step] = db;
        dst_len[step] = dl;
    }

    let n4 = local32(g, f);
    lget(g, end_local); lget(g, index); op(g, OP_i32_gt_u);
    let cnt_if = open(g, f, OP_if_);
    lget(g, end_local); lget(g, index); op(g, OP_i32_sub);
    i32Const(g, 0xfffffffc); op(g, OP_i32_and); lset(g, n4);
    popCheckedArraysAt(f, cnt_if);
    op(g, OP_else_);
    i32Const(g, 0); lset(g, n4);
    close(g, f);

    lget(g, n4); i32Const(g, 0); op(g, OP_i32_gt_u);
    for step in 0..k_steps {
        lget(g, end_local); lget(g, dst_len[step]); op(g, OP_i32_le_u); op(g, OP_i32_and);
    }
    let run_if = open(g, f, OP_if_);

    for hi in 0..plan.hoisted_len {
        let h = plan.hoisted[hi];
        let vl = local(g, f, VT_v128);
        if h.tag == squid_direct_types::Tag.boolean {
            i32Const(g, 0); lget(g, h.scalar_local); op(g, OP_i32_sub); simdOp(g, SIMD_i32x4_splat);
        } else if h.tag == squid_direct_types::Tag.f32_ {
            lget(g, h.scalar_local); simdOp(g, SIMD_f32x4_splat);
        } else {
            lget(g, h.scalar_local); simdOp(g, SIMD_i32x4_splat);
        }
        lset(g, vl);
        plan.hoisted[hi].vlocal = vl;
    }
    if plan.uses_f32_canon && !f.defer_f32_nan {
        let nl = local(g, f, VT_v128);
        v128Const4(g, 0x7fc00000);
        lset(g, nl);
        plan.nan_vlocal = nl;
    }

    var ak: u32[8] = [0; 8];
    var ck: u32[8] = [0; 8];
    ak[0] = a1;
    ck[0] = c1;
    for k in 1..8 {
        ak[k] = ak[k - 1] * a1;
        ck[k] = ck[k - 1] * a1 + c1;
    }

    let s_loc = w(g, g.s.vals[iteration.start + s_ci], 0);
    let vs0 = local(g, f, VT_v128);
    var vs1: u32 = 0;
    let vA_step = local(g, f, VT_v128);
    let vC_step = local(g, f, VT_v128);
    var vA1: u32 = 0;
    var vC1: u32 = 0;

    if k_steps == 1 {
        lget(g, s_loc); simdOp(g, SIMD_i32x4_splat);
        v128ConstWords(g, ak[0], ak[1], ak[2], ak[3]); simdOp(g, SIMD_i32x4_mul);
        v128ConstWords(g, ck[0], ck[1], ck[2], ck[3]); simdOp(g, SIMD_i32x4_add);
        lset(g, vs0);
        v128Const4(g, ak[3]); lset(g, vA_step);
        v128Const4(g, ck[3]); lset(g, vC_step);
        plan.locals[1].vlocal = vs0;
    } else {
        vs1 = local(g, f, VT_v128);
        vA1 = local(g, f, VT_v128);
        vC1 = local(g, f, VT_v128);
        lget(g, s_loc); simdOp(g, SIMD_i32x4_splat);
        v128ConstWords(g, ak[0], ak[2], ak[4], ak[6]); simdOp(g, SIMD_i32x4_mul);
        v128ConstWords(g, ck[0], ck[2], ck[4], ck[6]); simdOp(g, SIMD_i32x4_add);
        lset(g, vs0);
        v128Const4(g, ak[0]); lset(g, vA1);
        v128Const4(g, ck[0]); lset(g, vC1);
        v128Const4(g, ak[7]); lset(g, vA_step);
        v128Const4(g, ck[7]); lset(g, vC_step);
        plan.locals[1].vlocal = vs0;
        plan.locals[2].vlocal = vs1;
    }

    var ptrs: u32[2] = [0; 2];
    for step in 0..k_steps {
        ptrs[step] = local32(g, f);
        lget(g, dst_base[step]);
        lget(g, index);
        i32Const(g, 2);
        op(g, OP_i32_shl);
        op(g, OP_i32_add);
        lset(g, ptrs[step]);
    }
    let rem = local32(g, f);
    lget(g, n4); lset(g, rem);

    let l_exit = open(g, f, OP_block);
    let l_top = open(g, f, OP_loop);

    if k_steps == 2 {
        lget(g, vs0); lget(g, vA1); simdOp(g, SIMD_i32x4_mul); lget(g, vC1); simdOp(g, SIMD_i32x4_add); lset(g, vs1);
    }
    for step in 0..k_steps {
        lget(g, ptrs[step]);
        let verr = emitVecExpr(g, f, plan, g.units[f.unit - 1], f.env, val_id[step], false);
        if verr != squid_direct_types::Error.none { return verr; }
        simdMemOp(g, SIMD_v128_store, 2, 0);
        lget(g, ptrs[step]); i32Const(g, 16); op(g, OP_i32_add); lset(g, ptrs[step]);
    }

    lget(g, rem); i32Const(g, 4); op(g, OP_i32_sub); ltee(g, rem);
    op(g, OP_i32_eqz); br(g, f, OP_br_if, l_exit);

    lget(g, vs0); lget(g, vA_step); simdOp(g, SIMD_i32x4_mul); lget(g, vC_step); simdOp(g, SIMD_i32x4_add); lset(g, vs0);
    br(g, f, OP_br, l_top);
    close(g, f);
    close(g, f);

    // Extract exact final LCG state from lane 3!
    if k_steps == 1 { lget(g, vs0); } else { lget(g, vs1); }
    simdLaneOp(g, SIMD_i32x4_extract_lane, 3);
    lset(g, s_loc);

    lget(g, index); lget(g, n4); op(g, OP_i32_add); lset(g, index);
    popCheckedArraysAt(f, run_if);
    close(g, f);
    f.checked_elems_len = 0;
    return squid_direct_types::Error.none;
}

// Generalized AoS F32 record (`#[Vec2]` 8 B / `#[Vec3]` 12 B / `#[Vec4]` 16 B, structural or single-ctor nominal,
// same-type or cross-nominal same-layout sources, direct `0..n` or `5B-2` indirect `let id = ids[k]`)
// auto-SIMD for counted range loops (`pos[i] := { x: p.x + v.x * dt, ... }`, add/sub/mul/scale/AXPY).
fn unwrapAosF32RecordType(g: Generator&, f: Fn&, elem_ty: Ty, id: u32) -> Ty, i64, bool {
    var rec_ty = elem_ty;
    var is_nom = false;
    if tagOf(g, elem_ty) == squid_direct_types::Tag.nominal {
        let boxed, berr = isBoxed(g, f, elem_ty, id);
        if berr != squid_direct_types::Error.none || boxed { return 0, 0, false; }
        let cases, cerr = g.types.variants(elem_ty);
        if cerr != squid_direct_types::Error.none || cases.len != 1 { return 0, 0, false; }
        rec_ty = g.types.variant_payloads[cases.payloads];
        is_nom = true;
    }
    if tagOf(g, rec_ty) != squid_direct_types::Tag.record { return 0, 0, false; }
    let k = g.types.node(rec_ty).b as i64;
    if k != 2 && k != 3 && k != 4 { return 0, 0, false; }
    let layout, lerr = g.types.layout(rec_ty);
    if lerr != squid_direct_types::Error.none || layout.len != k { return 0, 0, false; }
    for li in 0..k {
        if layout[li] != VT_f32 { return 0, 0, false; }
    }
    let step, serr = stride(g, f, elem_ty, id);
    if serr != squid_direct_types::Error.none || step != (k as u32) * 4 { return 0, 0, false; }
    return rec_ty, k, is_nom;
}
fn aosArrayReadAtIter(m: const Module&, id: u32, idx_b: u32) -> u32 {
    if id == 0 { return 0; }
    let n = m.node(id);
    if n.tag == squid_check_core::Tag.array_op && m.arrayOperation(id) == squid_backend_collection_ops::Op.get {
        let ch = m.children(id);
        if ch.len == 2 && localRef(m, ch[1]) == idx_b { return localRef(m, ch[0]); }
    }
    if n.tag == squid_check_core::Tag.storage {
        let sop, err = squid_check_storage_ops::opFromCode(n.c);
        if err == squid_error::Error.none && sop == squid_check_storage_ops::Op.read {
            let ch = m.children(id);
            if ch.len == 2 && localRef(m, ch[1]) == idx_b { return localRef(m, ch[0]); }
        }
    }
    return 0;
}
fn aosFieldSlot(
    g: Generator&,
    f: Fn&,
    m: const Module&,
    id: u32,
    loop_id: u32,
    k_lanes: i64,
    idx_b: u32,
    load_bs: const u32[4]&,
    load_arrs: const u32[4]&,
    load_rec_tys: const Ty[4]&,
    load_len: i64,
    pat_bs: const u32[16]&,
    pat_arrs: const u32[16]&,
    pat_slots: const i64[16]&,
    pat_len: i64,
) -> u32, i64 {
    if id == 0 { return 0, -1; }
    let n = m.node(id);
    if n.tag == squid_check_core::Tag.reference {
        let b = localRef(m, id);
        for pi in 0..pat_len {
            if pat_bs[pi] == b { return pat_arrs[pi], pat_slots[pi]; }
        }
        return 0, -1;
    }
    if n.tag != squid_check_core::Tag.project { return 0, -1; }
    let fsp = m.fieldSpelling(m.projection(n.b).field);
    if !fsp.present { return 0, -1; }
    let fname = g.types.fieldName(fsp.value);
    let direct_arr = aosArrayReadAtIter(m, n.a, idx_b);
    if direct_arr != 0 {
        let av, aok = bindGet(g, f, direct_arr);
        if !aok || tagOf(g, av.ty) != squid_direct_types::Tag.array { return 0, -1; }
        let se, seerr = elementOf(g, f, av.ty, loop_id);
        if seerr != squid_direct_types::Error.none { g.dropFailure(); return 0, -1; }
        let s_rec_ty, sk, _ = unwrapAosF32RecordType(g, f, se, loop_id);
        if sk != k_lanes { return 0, -1; }
        let slot = g.types.findField(s_rec_ty, fname);
        if slot < 0 || slot >= k_lanes { return 0, -1; }
        return direct_arr, slot;
    }
    let recv_b = localRef(m, n.a);
    if recv_b != 0 {
        for li in 0..load_len {
            if load_bs[li] == recv_b {
                let slot = g.types.findField(load_rec_tys[li], fname);
                if slot < 0 || slot >= k_lanes { return 0, -1; }
                return load_arrs[li], slot;
            }
        }
    }
    return 0, -1;
}
fn aosIsScalarF32(g: const Generator&, f: const Fn&, m: const Module&, id: u32, iter_b: u32, idx_b: u32) -> bool, bool, u32 {
    // Returns (ok, is_const, bits_or_binding)
    if id == 0 { return false, false, 0; }
    let n = m.node(id);
    if n.tag == squid_check_core::Tag.constant {
        let ty, err = g.types.lower(m, n.ty, f.env);
        if err == squid_direct_types::Error.none && tagOf(g, ty) == squid_direct_types::Tag.f32_ {
            return true, true, n.a;
        }
        return false, false, 0;
    }
    let b = localRef(m, id);
    if b != 0 && b != iter_b && b != idx_b {
        let _, is_cell = withCellType(g, f, b);
        if is_cell { return false, false, 0; }
        let v, ok = bindGet(g, f, b);
        if ok && tagOf(g, v.ty) == squid_direct_types::Tag.f32_ {
            return true, false, b;
        }
    }
    return false, false, 0;
}
fn aosMatchMulByScalar(
    g: Generator&,
    f: Fn&,
    m: const Module&,
    id: u32,
    loop_id: u32,
    k_lanes: i64,
    want_lane: i64,
    iter_b: u32,
    idx_b: u32,
    load_bs: const u32[4]&,
    load_arrs: const u32[4]&,
    load_rec_tys: const Ty[4]&,
    load_len: i64,
    pat_bs: const u32[16]&,
    pat_arrs: const u32[16]&,
    pat_slots: const i64[16]&,
    pat_len: i64,
) -> bool, u32, bool, u32 {
    if id == 0 { return false, 0, false, 0; }
    let n = m.node(id);
    if (n.tag != squid_check_core::Tag.scalar && n.tag != squid_check_core::Tag.associated) || n.op != squid_check_core::Op.mul || n.b == 0 {
        return false, 0, false, 0;
    }
    let la, lslot = aosFieldSlot(g, f, m, n.a, loop_id, k_lanes, idx_b, load_bs, load_arrs, load_rec_tys, load_len, pat_bs, pat_arrs, pat_slots, pat_len);
    let rok, rconst, rval = aosIsScalarF32(g, f, m, n.b, iter_b, idx_b);
    if la != 0 && lslot == want_lane && rok { return true, la, rconst, rval; }
    let ra, rslot = aosFieldSlot(g, f, m, n.b, loop_id, k_lanes, idx_b, load_bs, load_arrs, load_rec_tys, load_len, pat_bs, pat_arrs, pat_slots, pat_len);
    let lok, lconst, lval = aosIsScalarF32(g, f, m, n.a, iter_b, idx_b);
    if ra != 0 && rslot == want_lane && lok { return true, ra, lconst, lval; }
    return false, 0, false, 0;
}
fn aosMatchLaneExpr(
    g: Generator&,
    f: Fn&,
    m: const Module&,
    id: u32,
    loop_id: u32,
    k_lanes: i64,
    want_lane: i64,
    iter_b: u32,
    idx_b: u32,
    load_bs: const u32[4]&,
    load_arrs: const u32[4]&,
    load_rec_tys: const Ty[4]&,
    load_len: i64,
    pat_bs: const u32[16]&,
    pat_arrs: const u32[16]&,
    pat_slots: const i64[16]&,
    pat_len: i64,
) -> bool, u8, u32, u32, bool, u32 {
    // Returns (ok, mode, srcA, srcB, scale_is_const, scale_bits_or_b)
    // mode: 0=A+B, 1=A-B, 2=A*B, 3=A*s, 4=A+B*s, 5=A-B*s
    if id == 0 { return false, 0, 0, 0, false, 0; }
    let n = m.node(id);
    if (n.tag != squid_check_core::Tag.scalar && n.tag != squid_check_core::Tag.associated) || n.b == 0 {
        return false, 0, 0, 0, false, 0;
    }
    if n.op == squid_check_core::Op.add || n.op == squid_check_core::Op.sub || n.op == squid_check_core::Op.mul {
        let la, lslot = aosFieldSlot(g, f, m, n.a, loop_id, k_lanes, idx_b, load_bs, load_arrs, load_rec_tys, load_len, pat_bs, pat_arrs, pat_slots, pat_len);
        let ra, rslot = aosFieldSlot(g, f, m, n.b, loop_id, k_lanes, idx_b, load_bs, load_arrs, load_rec_tys, load_len, pat_bs, pat_arrs, pat_slots, pat_len);
        if la != 0 && lslot == want_lane && ra != 0 && rslot == want_lane {
            var mode: u8 = 0;
            if n.op == squid_check_core::Op.sub { mode = 1; }
            else if n.op == squid_check_core::Op.mul { mode = 2; }
            return true, mode, la, ra, false, 0;
        }
        if n.op == squid_check_core::Op.mul {
            let mok, ma, mc, mv = aosMatchMulByScalar(g, f, m, id, loop_id, k_lanes, want_lane, iter_b, idx_b, load_bs, load_arrs, load_rec_tys, load_len, pat_bs, pat_arrs, pat_slots, pat_len);
            if mok { return true, 3, ma, 0, mc, mv; }
        }
        if n.op == squid_check_core::Op.add {
            if la != 0 && lslot == want_lane {
                let mok, mb, mc, mv = aosMatchMulByScalar(g, f, m, n.b, loop_id, k_lanes, want_lane, iter_b, idx_b, load_bs, load_arrs, load_rec_tys, load_len, pat_bs, pat_arrs, pat_slots, pat_len);
                if mok { return true, 4, la, mb, mc, mv; }
            }
            if ra != 0 && rslot == want_lane {
                let mok, mb, mc, mv = aosMatchMulByScalar(g, f, m, n.a, loop_id, k_lanes, want_lane, iter_b, idx_b, load_bs, load_arrs, load_rec_tys, load_len, pat_bs, pat_arrs, pat_slots, pat_len);
                if mok { return true, 4, ra, mb, mc, mv; }
            }
        }
        if n.op == squid_check_core::Op.sub && la != 0 && lslot == want_lane {
            let mok, mb, mc, mv = aosMatchMulByScalar(g, f, m, n.b, loop_id, k_lanes, want_lane, iter_b, idx_b, load_bs, load_arrs, load_rec_tys, load_len, pat_bs, pat_arrs, pat_slots, pat_len);
            if mok { return true, 5, la, mb, mc, mv; }
        }
    }
    return false, 0, 0, 0, false, 0;
}
fn emitAosF32VecStripeOp(
    g: Generator&,
    f: const Fn&,
    mode: u8,
    dst_ptr: u32,
    a_ptr: u32,
    b_ptr: u32,
    v_scale: u32,
    nan_vlocal: u32,
    byte_off: u32,
) {
    lget(g, dst_ptr);
    if mode == 4 && squid_direct_writer::relaxedSimdEnabled() {
        lget(g, b_ptr); simdMemOp(g, SIMD_v128_load, 2, byte_off);
        lget(g, v_scale);
        lget(g, a_ptr); simdMemOp(g, SIMD_v128_load, 2, byte_off);
        simdOp(g, SIMD_f32x4_relaxed_madd);
    } else if mode == 5 && squid_direct_writer::relaxedSimdEnabled() {
        lget(g, b_ptr); simdMemOp(g, SIMD_v128_load, 2, byte_off);
        lget(g, v_scale);
        lget(g, a_ptr); simdMemOp(g, SIMD_v128_load, 2, byte_off);
        simdOp(g, SIMD_f32x4_relaxed_nmadd);
    } else {
        lget(g, a_ptr); simdMemOp(g, SIMD_v128_load, 2, byte_off);
        if mode == 0 {
            lget(g, b_ptr); simdMemOp(g, SIMD_v128_load, 2, byte_off);
            simdOp(g, SIMD_f32x4_add);
        } else if mode == 1 {
            lget(g, b_ptr); simdMemOp(g, SIMD_v128_load, 2, byte_off);
            simdOp(g, SIMD_f32x4_sub);
        } else if mode == 2 {
            lget(g, b_ptr); simdMemOp(g, SIMD_v128_load, 2, byte_off);
            simdOp(g, SIMD_f32x4_mul);
        } else if mode == 3 {
            lget(g, v_scale);
            simdOp(g, SIMD_f32x4_mul);
        } else {
            lget(g, b_ptr); simdMemOp(g, SIMD_v128_load, 2, byte_off);
            lget(g, v_scale);
            simdOp(g, SIMD_f32x4_mul);
            if mode == 4 { simdOp(g, SIMD_f32x4_add); } else { simdOp(g, SIMD_f32x4_sub); }
        }
    }
    if !f.defer_f32_nan { canonicalizeF32x4(g, f, nan_vlocal); }
    simdMemOp(g, SIMD_v128_store, 2, byte_off);
}
fn emitAosF32ContiguousSimd(
    g: Generator&,
    f: Fn&,
    k_lanes: i64,
    mode: u8,
    p_dst: u32,
    p_a: u32,
    p_b: u32,
    has_b: bool,
    v_scale: u32,
    nan_vlocal: u32,
    rem: u32,
) {
    if k_lanes == 3 {
        // 12-byte records: 8 elements = 96 bytes = 6 x v128 (zero shuffles!), 4 elements = 48 bytes = 3 x v128!
        let s8_exit = open(g, f, OP_block);
        let s8_top = open(g, f, OP_loop);
        lget(g, rem); i32Const(g, 8); op(g, OP_i32_lt_u);
        br(g, f, OP_br_if, s8_exit);
        emitAosF32VecStripeOp(g, f, mode, p_dst, p_a, p_b, v_scale, nan_vlocal, 80);
        emitAosF32VecStripeOp(g, f, mode, p_dst, p_a, p_b, v_scale, nan_vlocal, 64);
        emitAosF32VecStripeOp(g, f, mode, p_dst, p_a, p_b, v_scale, nan_vlocal, 48);
        emitAosF32VecStripeOp(g, f, mode, p_dst, p_a, p_b, v_scale, nan_vlocal, 32);
        emitAosF32VecStripeOp(g, f, mode, p_dst, p_a, p_b, v_scale, nan_vlocal, 16);
        emitAosF32VecStripeOp(g, f, mode, p_dst, p_a, p_b, v_scale, nan_vlocal, 0);
        lget(g, p_dst); i32Const(g, 96); op(g, OP_i32_add); lset(g, p_dst);
        lget(g, p_a); i32Const(g, 96); op(g, OP_i32_add); lset(g, p_a);
        if has_b { lget(g, p_b); i32Const(g, 96); op(g, OP_i32_add); lset(g, p_b); }
        lget(g, rem); i32Const(g, 8); op(g, OP_i32_sub); lset(g, rem);
        br(g, f, OP_br, s8_top);
        close(g, f);
        close(g, f);

        let s4_exit = open(g, f, OP_block);
        let s4_top = open(g, f, OP_loop);
        lget(g, rem); i32Const(g, 4); op(g, OP_i32_lt_u);
        br(g, f, OP_br_if, s4_exit);
        emitAosF32VecStripeOp(g, f, mode, p_dst, p_a, p_b, v_scale, nan_vlocal, 32);
        emitAosF32VecStripeOp(g, f, mode, p_dst, p_a, p_b, v_scale, nan_vlocal, 16);
        emitAosF32VecStripeOp(g, f, mode, p_dst, p_a, p_b, v_scale, nan_vlocal, 0);
        lget(g, p_dst); i32Const(g, 48); op(g, OP_i32_add); lset(g, p_dst);
        lget(g, p_a); i32Const(g, 48); op(g, OP_i32_add); lset(g, p_a);
        if has_b { lget(g, p_b); i32Const(g, 48); op(g, OP_i32_add); lset(g, p_b); }
        lget(g, rem); i32Const(g, 4); op(g, OP_i32_sub); lset(g, rem);
        br(g, f, OP_br, s4_top);
        close(g, f);
        close(g, f);
        return;
    }
    let step = (k_lanes as u32) * 4;
    let elems_per_vec: u32 = 16 / step;
    let elems_per_4x: u32 = elems_per_vec * 4;

    // 4x unrolled descending-offset (48, 32, 16, 0) 64-byte SIMD stripe loop.
    let s4_exit = open(g, f, OP_block);
    let s4_top = open(g, f, OP_loop);
    lget(g, rem); i32Const(g, elems_per_4x); op(g, OP_i32_lt_u);
    br(g, f, OP_br_if, s4_exit);
    emitAosF32VecStripeOp(g, f, mode, p_dst, p_a, p_b, v_scale, nan_vlocal, 48);
    emitAosF32VecStripeOp(g, f, mode, p_dst, p_a, p_b, v_scale, nan_vlocal, 32);
    emitAosF32VecStripeOp(g, f, mode, p_dst, p_a, p_b, v_scale, nan_vlocal, 16);
    emitAosF32VecStripeOp(g, f, mode, p_dst, p_a, p_b, v_scale, nan_vlocal, 0);
    lget(g, p_dst); i32Const(g, 64); op(g, OP_i32_add); lset(g, p_dst);
    lget(g, p_a); i32Const(g, 64); op(g, OP_i32_add); lset(g, p_a);
    if has_b { lget(g, p_b); i32Const(g, 64); op(g, OP_i32_add); lset(g, p_b); }
    lget(g, rem); i32Const(g, elems_per_4x); op(g, OP_i32_sub); lset(g, rem);
    br(g, f, OP_br, s4_top);
    close(g, f);
    close(g, f);

    // 1x v128 (16-byte) tail loop (handles remaining 1..3 Vec4s or 2..6 Vec2s).
    let s1_exit = open(g, f, OP_block);
    let s1_top = open(g, f, OP_loop);
    lget(g, rem); i32Const(g, elems_per_vec); op(g, OP_i32_lt_u);
    br(g, f, OP_br_if, s1_exit);
    emitAosF32VecStripeOp(g, f, mode, p_dst, p_a, p_b, v_scale, nan_vlocal, 0);
    lget(g, p_dst); i32Const(g, 16); op(g, OP_i32_add); lset(g, p_dst);
    lget(g, p_a); i32Const(g, 16); op(g, OP_i32_add); lset(g, p_a);
    if has_b { lget(g, p_b); i32Const(g, 16); op(g, OP_i32_add); lset(g, p_b); }
    lget(g, rem); i32Const(g, elems_per_vec); op(g, OP_i32_sub); lset(g, rem);
    br(g, f, OP_br, s1_top);
    close(g, f);
    close(g, f);
}
fn emitAosF32ScalarElemOp(
    g: Generator&,
    f: const Fn&,
    k_lanes: i64,
    mode: u8,
    dst_addr: u32,
    a_addr: u32,
    b_addr: u32,
    scale_f32: u32,
) {
    var li = k_lanes;
    while li > 0 {
        li -= 1;
        let off = (li as u32) * 4;
        lget(g, dst_addr);
        lget(g, a_addr); op(g, OP_f32_load); uleb(g, 2); uleb(g, off);
        if mode == 0 {
            lget(g, b_addr); op(g, OP_f32_load); uleb(g, 2); uleb(g, off);
            op(g, OP_f32_add);
        } else if mode == 1 {
            lget(g, b_addr); op(g, OP_f32_load); uleb(g, 2); uleb(g, off);
            op(g, squid_direct_writer::OP_f32_sub);
        } else if mode == 2 {
            lget(g, b_addr); op(g, OP_f32_load); uleb(g, 2); uleb(g, off);
            op(g, squid_direct_writer::OP_f32_mul);
        } else if mode == 3 {
            lget(g, scale_f32);
            op(g, squid_direct_writer::OP_f32_mul);
        } else {
            lget(g, b_addr); op(g, OP_f32_load); uleb(g, 2); uleb(g, off);
            lget(g, scale_f32);
            op(g, squid_direct_writer::OP_f32_mul);
            if mode == 4 { op(g, OP_f32_add); } else { op(g, squid_direct_writer::OP_f32_sub); }
        }
        if !f.defer_f32_nan { canonicalizeF32Stack(g, f); }
        op(g, squid_direct_writer::OP_f32_store); uleb(g, 2); uleb(g, off);
    }
}
fn tryEmitAosF32RecordLoop(
    g: Generator&,
    f: Fn&,
    loop_id: u32,
    info: squid_check_core::LoopInfo,
    carry_in_place: const bool[64]&,
    index: u32,
    end_local: u32,
) -> Error {
    if g.runtime_().has_fork { return squid_direct_types::Error.none; }
    if info.kind != squid_check_core::LoopKind.range || info.pattern == 0 || info.body == 0 {
        return squid_direct_types::Error.none;
    }
    var dst_b: u32 = 0;
    var dst_val = neverVal();
    var srcA_b: u32 = 0;
    var srcA_val = neverVal();
    var srcB_b: u32 = 0;
    var srcB_val = neverVal();
    var is_indirect = false;
    var ind_id_b: u32 = 0;
    var ids_arr_b: u32 = 0;
    var mode: u8 = 0;
    var scale_is_const = false;
    var scale_bits_or_b: u32 = 0;
    var k_lanes: i64 = 0;
    var matched = false;
    {
        let m .= g.units[f.unit - 1];
        let pat = m.pattern(info.pattern);
        if pat.tag != squid_check_core::PatternTag.bind { return squid_direct_types::Error.none; }
        let iter_b = pat.a;
        let carries = m.loopCarries(loop_id);
        if carries.len > 64 { return squid_direct_types::Error.none; }
        for ci in 0..carries.len {
            if !carry_in_place[ci] { return squid_direct_types::Error.none; }
        }

        var stmts: u32[8] = [0; 8];
        var stmts_len: i64 = 0;
        let bn = m.node(info.body);
        if bn.tag == squid_check_core::Tag.suite || bn.tag == squid_check_core::Tag.block_ {
            let ch = m.children(info.body);
            if ch.len == 0 || ch.len > 8 { return squid_direct_types::Error.none; }
            for si in 0..ch.len { stmts[si] = ch[si]; }
            stmts_len = ch.len;
        } else {
            stmts[0] = info.body;
            stmts_len = 1;
        }

        // Optional Shape 2 leading indirect index: `let id = ids[k]` (verified by 5B-2!).
        var idx_b = iter_b;
        var first_load_si: i64 = 0;
        if stmts_len >= 2 && f.indirect_bound_binding != 0 && f.indirect_bound_len != 0 {
            let s0 = m.node(stmts[0]);
            if s0.tag == squid_check_core::Tag.bind && s0.c < 2 && s0.a == f.indirect_bound_binding {
                let gok, ia_n, ip_n = matchArrayGet(m, s0.b);
                if gok && localRef(m, ip_n) == iter_b {
                    let iab = localRef(m, ia_n);
                    if iab != 0 {
                        let iv, iok = bindGet(g, f, iab);
                        if iok && tagOf(g, iv.ty) == squid_direct_types::Tag.array &&
                            tagOf(g, g.types.node(iv.ty).a) == squid_direct_types::Tag.u32_ {
                            is_indirect = true;
                            ind_id_b = s0.a;
                            ids_arr_b = iab;
                            idx_b = ind_id_b;
                            first_load_si = 1;
                        }
                    }
                }
            }
        }

        // Last statement must be `dst[idx_b] := <record or single-ctor record>`
        let last_id = stmts[stmts_len - 1];
        let last_n = m.node(last_id);
        var uid: u32 = 0;
        if last_n.tag == squid_check_core::Tag.update { uid = last_id; }
        else if last_n.tag == squid_check_core::Tag.bind && last_n.c < 2 && m.node(last_n.b).tag == squid_check_core::Tag.update {
            uid = last_n.b;
        }
        if uid == 0 { return squid_direct_types::Error.none; }
        let uinfo = m.updateInfo(uid);
        let sels = m.updateSelectors(uid);
        if sels.len != 1 || sels[0].kind != squid_check_core::UpdateKind.index { return squid_direct_types::Error.none; }
        if localRef(m, sels[0].index) != idx_b { return squid_direct_types::Error.none; }
        if uinfo.self_binding != 0 && uses(g, f, uinfo.self_binding) != 0 { return squid_direct_types::Error.none; }
        dst_b = localRef(m, uinfo.root);
        if dst_b == 0 { return squid_direct_types::Error.none; }
        let _, dst_cell = withCellType(g, f, dst_b);
        if dst_cell { return squid_direct_types::Error.none; }
        let dv, dok = bindGet(g, f, dst_b);
        if !dok || tagOf(g, dv.ty) != squid_direct_types::Tag.array { return squid_direct_types::Error.none; }
        dst_val = dv;
        let elem_ty, eerr = elementOf(g, f, dv.ty, loop_id);
        if eerr != squid_direct_types::Error.none { g.dropFailure(); return squid_direct_types::Error.none; }
        let rec_ty, k, is_nom = unwrapAosF32RecordType(g, f, elem_ty, loop_id);
        if k == 0 { return squid_direct_types::Error.none; }
        k_lanes = k;

        // Parse leading `let p = src[idx_b]` or `let $Vec { x, y, ... } = src[idx_b]` statements
        // (supports cross-nominal same-layout sources, e.g. `#[Pos]` + `#[Vel]`).
        var load_bs: u32[4] = [0; 4];
        var load_arrs: u32[4] = [0; 4];
        var load_rec_tys: Ty[4] = [0; 4];
        var load_len: i64 = 0;
        var pat_bs: u32[16] = [0; 16];
        var pat_arrs: u32[16] = [0; 16];
        var pat_slots: i64[16] = [0; 16];
        var pat_len: i64 = 0;
        for si in first_load_si..(stmts_len - 1) {
            let sn = m.node(stmts[si]);
            if sn.tag == squid_check_core::Tag.bind && sn.c < 2 {
                let src_arr = aosArrayReadAtIter(m, sn.b, idx_b);
                if src_arr == 0 || load_len >= 4 { return squid_direct_types::Error.none; }
                let sav, saok = bindGet(g, f, src_arr);
                if !saok || tagOf(g, sav.ty) != squid_direct_types::Tag.array { return squid_direct_types::Error.none; }
                let se, seerr = elementOf(g, f, sav.ty, loop_id);
                if seerr != squid_direct_types::Error.none { g.dropFailure(); return squid_direct_types::Error.none; }
                let s_rec_ty, sk, _ = unwrapAosF32RecordType(g, f, se, loop_id);
                if sk != k { return squid_direct_types::Error.none; }
                load_bs[load_len] = sn.a;
                load_arrs[load_len] = src_arr;
                load_rec_tys[load_len] = s_rec_ty;
                load_len += 1;
            } else if sn.tag == squid_check_core::Tag.pattern_bind && sn.c == 0 {
                let src_arr = aosArrayReadAtIter(m, sn.b, idx_b);
                if src_arr == 0 { return squid_direct_types::Error.none; }
                let sav, saok = bindGet(g, f, src_arr);
                if !saok || tagOf(g, sav.ty) != squid_direct_types::Tag.array { return squid_direct_types::Error.none; }
                let se, seerr = elementOf(g, f, sav.ty, loop_id);
                if seerr != squid_direct_types::Error.none { g.dropFailure(); return squid_direct_types::Error.none; }
                let s_rec_ty, sk, s_is_nom = unwrapAosF32RecordType(g, f, se, loop_id);
                if sk != k { return squid_direct_types::Error.none; }
                var p_id = sn.a;
                if s_is_nom {
                    let cp = m.pattern(p_id);
                    if cp.tag != squid_check_core::PatternTag.constructor { return squid_direct_types::Error.none; }
                    p_id = cp.b;
                }
                let rp = m.pattern(p_id);
                var prod_id: u32 = 0;
                if rp.tag == squid_check_core::PatternTag.record_payload && m.pattern(rp.b).tag == squid_check_core::PatternTag.product {
                    prod_id = rp.b;
                } else if rp.tag == squid_check_core::PatternTag.product {
                    prod_id = p_id;
                } else {
                    return squid_direct_types::Error.none;
                }
                let storage = m.types.node(rp.ty);
                if storage.tag != squid_check_types::Tag.record || (storage.b as i64) != k { return squid_direct_types::Error.none; }
                let pch = m.patternChildren(prod_id);
                if pch.len != k { return squid_direct_types::Error.none; }
                for pi in 0..k {
                    let cp = m.pattern(pch[pi]);
                    if cp.tag != squid_check_core::PatternTag.bind || pat_len >= 16 { return squid_direct_types::Error.none; }
                    let fsp = m.fieldSpelling(m.types.recordField(storage, pi).name);
                    if !fsp.present { return squid_direct_types::Error.none; }
                    let slot = g.types.findField(s_rec_ty, g.types.fieldName(fsp.value));
                    if slot < 0 || slot >= k { return squid_direct_types::Error.none; }
                    pat_bs[pat_len] = cp.a;
                    pat_arrs[pat_len] = src_arr;
                    pat_slots[pat_len] = slot;
                    pat_len += 1;
                }
            } else {
                return squid_direct_types::Error.none;
            }
        }

        // Unwrap RHS record (or single-ctor nominal wrapping record).
        var rec_node = uinfo.value;
        var decl_storage_tid: TId = 0;
        if is_nom {
            let vn = m.node(rec_node);
            if vn.tag != squid_check_core::Tag.construct { return squid_direct_types::Error.none; }
            let ctor = m.constructor(vn.a);
            if ctor.payload != 0 {
                let dn = m.types.node(ctor.payload);
                if dn.tag == squid_check_types::Tag.record && (dn.b as i64) == k { decl_storage_tid = ctor.payload; }
            }
            rec_node = vn.b;
        }
        let rn = m.node(rec_node);
        if rn.tag != squid_check_core::Tag.record && rn.tag != squid_check_core::Tag.product { return squid_direct_types::Error.none; }
        let rch = m.children(rec_node);
        if rch.len != k { return squid_direct_types::Error.none; }
        var storage_tid: TId = 0;
        if rn.tag == squid_check_core::Tag.record {
            storage_tid = m.typeOf(rec_node);
            let sn = m.types.node(storage_tid);
            if sn.tag != squid_check_types::Tag.record || (sn.b as i64) != k { return squid_direct_types::Error.none; }
        } else {
            if decl_storage_tid == 0 { return squid_direct_types::Error.none; }
            storage_tid = decl_storage_tid;
        }
        let storage = m.types.node(storage_tid);
        var lane_exprs: u32[4] = [0; 4];
        var seen: bool[4] = [false; 4];
        for idx in 0..k {
            var dest = idx;
            if rn.tag == squid_check_core::Tag.record {
                dest = m.recordDestinations(rec_node)[idx] as i64;
                if dest < 0 || dest >= k { return squid_direct_types::Error.none; }
            }
            let fsp = m.fieldSpelling(m.types.recordField(storage, dest).name);
            if !fsp.present { return squid_direct_types::Error.none; }
            let slot = g.types.findField(rec_ty, g.types.fieldName(fsp.value));
            if slot < 0 || slot >= k || seen[slot] { return squid_direct_types::Error.none; }
            seen[slot] = true;
            lane_exprs[slot] = rch[idx];
        }
        for lane in 0..k {
            if !seen[lane] { return squid_direct_types::Error.none; }
            let ok, lm, la, lb, lsc, lsv = aosMatchLaneExpr(g, f, m, lane_exprs[lane], loop_id, k, lane, iter_b, idx_b, load_bs, load_arrs, load_rec_tys, load_len, pat_bs, pat_arrs, pat_slots, pat_len);
            if !ok { return squid_direct_types::Error.none; }
            if lane == 0 {
                mode = lm; srcA_b = la; srcB_b = lb; scale_is_const = lsc; scale_bits_or_b = lsv;
            } else {
                if lm != mode || la != srcA_b || lb != srcB_b || lsc != scale_is_const || lsv != scale_bits_or_b {
                    return squid_direct_types::Error.none;
                }
            }
        }
        let _, a_cell = withCellType(g, f, srcA_b);
        if a_cell { return squid_direct_types::Error.none; }
        let av, aok = bindGet(g, f, srcA_b);
        if !aok || tagOf(g, av.ty) != squid_direct_types::Tag.array { return squid_direct_types::Error.none; }
        let ae, aeerr = elementOf(g, f, av.ty, loop_id);
        if aeerr != squid_direct_types::Error.none { g.dropFailure(); return squid_direct_types::Error.none; }
        let _, ak, _ = unwrapAosF32RecordType(g, f, ae, loop_id);
        if ak != k { return squid_direct_types::Error.none; }
        srcA_val = av;
        if srcB_b != 0 {
            let _, b_cell = withCellType(g, f, srcB_b);
            if b_cell { return squid_direct_types::Error.none; }
            let bv, bok = bindGet(g, f, srcB_b);
            if !bok || tagOf(g, bv.ty) != squid_direct_types::Tag.array { return squid_direct_types::Error.none; }
            let be, beerr = elementOf(g, f, bv.ty, loop_id);
            if beerr != squid_direct_types::Error.none { g.dropFailure(); return squid_direct_types::Error.none; }
            let _, bk, _ = unwrapAosF32RecordType(g, f, be, loop_id);
            if bk != k { return squid_direct_types::Error.none; }
            srcB_val = bv;
        }
        if mode >= 3 && scale_is_const {
            for lane in 0..k { markUnpatchableExprConstants(m, lane_exprs[lane], 0); }
        }
        matched = true;
    }
    if !matched { return squid_direct_types::Error.none; }

    let step = (k_lanes as u32) * 4;
    let dst_base, dst_len = ensureCheckedArray(g, f, dst_val);
    let a_base, a_len = ensureCheckedArray(g, f, srcA_val);
    var b_base: u32 = a_base;
    var b_len: u32 = a_len;
    if srcB_b != 0 {
        let bb, bl = ensureCheckedArray(g, f, srcB_val);
        b_base = bb; b_len = bl;
    }

    if is_indirect {
        // Shape 2: `let id = ids[k]` — requires 5B-2 proof that every `ids[k] < min(dst_len, a_len, b_len)`!
        if f.indirect_bound_binding != ind_id_b || f.indirect_bound_len == 0 {
            return squid_direct_types::Error.none;
        }
        if !(f.indirect_bound_len == dst_len || findCheckedLe(f, f.indirect_bound_len, dst_len) >= 0) ||
            !(f.indirect_bound_len == a_len || findCheckedLe(f, f.indirect_bound_len, a_len) >= 0) ||
            (srcB_b != 0 && !(f.indirect_bound_len == b_len || findCheckedLe(f, f.indirect_bound_len, b_len) >= 0)) {
            return squid_direct_types::Error.none;
        }
        let ids_val, _ = bindGet(g, f, ids_arr_b);
        let ids_base, ids_len = ensureCheckedArray(g, f, ids_val);

        let ok_loc = local32(g, f);
        lget(g, index); lget(g, end_local); op(g, OP_i32_lt_u);
        lget(g, end_local); lget(g, ids_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
        lget(g, dst_len); i32Const(g, 0x7fffffff / step); op(g, OP_i32_le_u); op(g, OP_i32_and);
        lget(g, a_len); i32Const(g, 0x7fffffff / step); op(g, OP_i32_le_u); op(g, OP_i32_and);
        if srcB_b != 0 {
            lget(g, b_len); i32Const(g, 0x7fffffff / step); op(g, OP_i32_le_u); op(g, OP_i32_and);
        }
        lset(g, ok_loc);

        lget(g, ok_loc);
        let run_if = open(g, f, OP_if_);

        var v_scale: u32 = 0xffffffff;
        var scale_f32: u32 = 0xffffffff;
        if mode >= 3 {
            v_scale = local(g, f, VT_v128);
            scale_f32 = local(g, f, VT_f32);
            if scale_is_const {
                v128Const4(g, scale_bits_or_b);
                ltee(g, v_scale);
                simdLaneOp(g, SIMD_f32x4_extract_lane, 0);
                lset(g, scale_f32);
            } else {
                let sv, _ = bindGet(g, f, scale_bits_or_b);
                lget(g, w(g, sv, 0));
                ltee(g, scale_f32);
                simdOp(g, SIMD_f32x4_splat);
                lset(g, v_scale);
            }
        }
        var nan_vlocal: u32 = 0xffffffff;
        if !f.defer_f32_nan {
            nan_vlocal = local(g, f, VT_v128);
            v128Const4(g, 0x7fc00000);
            lset(g, nan_vlocal);
        }

        let ids_ptr = local32(g, f);
        lget(g, ids_base); lget(g, index); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, ids_ptr);
        let count = local32(g, f);
        lget(g, end_local); lget(g, index); op(g, OP_i32_sub); lset(g, count);
        let rem = local32(g, f);
        lget(g, count); lset(g, rem);

        var has_contig = false;
        if f.indirect_bound_distinct_local != 0xffffffff {
            has_contig = true;
            let contig_ok = local32(g, f);
            lget(g, f.indirect_bound_distinct_local); i32Const(g, 2); op(g, OP_i32_eq);
            let dst_bytes = emitScaledBytes(g, f, dst_len, step);
            let dst_slot = w(g, dst_val, 0);
            let dst_gen = w(g, dst_val, 1);
            if !(w(g, srcA_val, 0) == dst_slot && w(g, srcA_val, 1) == dst_gen) {
                let a_bytes = emitScaledBytes(g, f, a_len, step);
                lget(g, a_base); lget(g, dst_base); op(g, OP_i32_eq);
                lget(g, a_base); lget(g, a_bytes); op(g, OP_i32_add); lget(g, dst_base); op(g, OP_i32_le_u); op(g, OP_i32_or);
                lget(g, dst_base); lget(g, dst_bytes); op(g, OP_i32_add); lget(g, a_base); op(g, OP_i32_le_u); op(g, OP_i32_or);
                op(g, OP_i32_and);
            }
            if srcB_b != 0 && !(w(g, srcB_val, 0) == dst_slot && w(g, srcB_val, 1) == dst_gen) {
                let b_bytes = emitScaledBytes(g, f, b_len, step);
                lget(g, b_base); lget(g, dst_base); op(g, OP_i32_eq);
                lget(g, b_base); lget(g, b_bytes); op(g, OP_i32_add); lget(g, dst_base); op(g, OP_i32_le_u); op(g, OP_i32_or);
                lget(g, dst_base); lget(g, dst_bytes); op(g, OP_i32_add); lget(g, b_base); op(g, OP_i32_le_u); op(g, OP_i32_or);
                op(g, OP_i32_and);
            }
            lset(g, contig_ok);

            lget(g, contig_ok);
            let contig_if = open(g, f, OP_if_);
            let id0 = local32(g, f);
            lget(g, ids_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0); lset(g, id0);
            let base_off = emitScaledBytes(g, f, id0, step);
            let cp_dst = local32(g, f);
            lget(g, dst_base); lget(g, base_off); op(g, OP_i32_add); lset(g, cp_dst);
            let cp_a = local32(g, f);
            lget(g, a_base); lget(g, base_off); op(g, OP_i32_add); lset(g, cp_a);
            var cp_b = cp_a;
            if srcB_b != 0 {
                cp_b = local32(g, f);
                lget(g, b_base); lget(g, base_off); op(g, OP_i32_add); lset(g, cp_b);
            }
            emitAosF32ContiguousSimd(g, f, k_lanes, mode, cp_dst, cp_a, cp_b, srcB_b != 0, v_scale, nan_vlocal, rem);
            popCheckedArraysAt(f, contig_if);
            op(g, OP_else_);
        }

        // Sparse / arbitrary IDs: 4x unrolled hoisted-bounds unchecked indirect loop
        // (sequential per-entity compute inside 4-unroll => safe even for duplicate IDs & aliasing!).
        var id_l: u32[4] = [0; 4];
        for s in 0..4 { id_l[s] = local32(g, f); }
        let da = local32(g, f);
        let aa = local32(g, f);
        let ba = local32(g, f);
        let sp_exit = open(g, f, OP_block);
        let sp_top = open(g, f, OP_loop);
        lget(g, rem); i32Const(g, 4); op(g, OP_i32_lt_u);
        br(g, f, OP_br_if, sp_exit);
        lget(g, ids_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, 12); lset(g, id_l[3]);
        lget(g, ids_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, 8);  lset(g, id_l[2]);
        lget(g, ids_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, 4);  lset(g, id_l[1]);
        lget(g, ids_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);  lset(g, id_l[0]);
        for s in 0..4 {
            let off = emitScaledBytes(g, f, id_l[s], step);
            lget(g, dst_base); lget(g, off); op(g, OP_i32_add); lset(g, da);
            lget(g, a_base); lget(g, off); op(g, OP_i32_add); lset(g, aa);
            if srcB_b != 0 {
                lget(g, b_base); lget(g, off); op(g, OP_i32_add); lset(g, ba);
            }
            emitAosF32ScalarElemOp(g, f, k_lanes, mode, da, aa, if srcB_b != 0 { ba } else { aa }, scale_f32);
        }
        lget(g, ids_ptr); i32Const(g, 16); op(g, OP_i32_add); lset(g, ids_ptr);
        lget(g, rem); i32Const(g, 4); op(g, OP_i32_sub); lset(g, rem);
        br(g, f, OP_br, sp_top);
        close(g, f);
        close(g, f);

        if has_contig { close(g, f); }

        lget(g, end_local); lget(g, rem); op(g, OP_i32_sub); lset(g, index);
        popCheckedArraysAt(f, run_if);
        close(g, f);
        f.checked_elems_len = 0;
        return squid_direct_types::Error.none;
    }

    let ok_loc = constLocal(g, f, 1);
    let count = local32(g, f);
    // Guard: index < end_local && end_local <= min(dst_len, a_len, b_len) && end_local <= 0x7fffffff / step
    lget(g, index); lget(g, end_local); op(g, OP_i32_lt_u);
    lget(g, end_local); lget(g, dst_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, end_local); lget(g, a_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
    if srcB_b != 0 {
        lget(g, end_local); lget(g, b_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
    }
    lget(g, end_local); i32Const(g, 0x7fffffff / step); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lset(g, ok_loc);

    // Disjointness guard: each source is either identical to dst or non-overlapping.
    let end_bytes = emitScaledBytes(g, f, end_local, step);
    let dst_slot = w(g, dst_val, 0);
    let dst_gen = w(g, dst_val, 1);
    if !(w(g, srcA_val, 0) == dst_slot && w(g, srcA_val, 1) == dst_gen) {
        lget(g, ok_loc);
        lget(g, a_base); lget(g, dst_base); op(g, OP_i32_eq);
        lget(g, a_base); lget(g, end_bytes); op(g, OP_i32_add); lget(g, dst_base); op(g, OP_i32_le_u); op(g, OP_i32_or);
        lget(g, dst_base); lget(g, end_bytes); op(g, OP_i32_add); lget(g, a_base); op(g, OP_i32_le_u); op(g, OP_i32_or);
        op(g, OP_i32_and);
        lset(g, ok_loc);
    }
    if srcB_b != 0 && !(w(g, srcB_val, 0) == dst_slot && w(g, srcB_val, 1) == dst_gen) {
        lget(g, ok_loc);
        lget(g, b_base); lget(g, dst_base); op(g, OP_i32_eq);
        lget(g, b_base); lget(g, end_bytes); op(g, OP_i32_add); lget(g, dst_base); op(g, OP_i32_le_u); op(g, OP_i32_or);
        lget(g, dst_base); lget(g, end_bytes); op(g, OP_i32_add); lget(g, b_base); op(g, OP_i32_le_u); op(g, OP_i32_or);
        op(g, OP_i32_and);
        lset(g, ok_loc);
    }

    lget(g, ok_loc);
    let run_if = open(g, f, OP_if_);

    var v_scale: u32 = 0xffffffff;
    if mode >= 3 {
        v_scale = local(g, f, VT_v128);
        if scale_is_const {
            v128Const4(g, scale_bits_or_b);
        } else {
            let sv, _ = bindGet(g, f, scale_bits_or_b);
            lget(g, w(g, sv, 0));
            simdOp(g, SIMD_f32x4_splat);
        }
        lset(g, v_scale);
    }
    var nan_vlocal: u32 = 0xffffffff;
    if !f.defer_f32_nan {
        nan_vlocal = local(g, f, VT_v128);
        v128Const4(g, 0x7fc00000);
        lset(g, nan_vlocal);
    }

    let start_bytes = emitScaledBytes(g, f, index, step);
    let p_dst = local32(g, f);
    lget(g, dst_base); lget(g, start_bytes); op(g, OP_i32_add); lset(g, p_dst);
    let p_a = local32(g, f);
    lget(g, a_base); lget(g, start_bytes); op(g, OP_i32_add); lset(g, p_a);
    var p_b = p_a;
    if srcB_b != 0 {
        p_b = local32(g, f);
        lget(g, b_base); lget(g, start_bytes); op(g, OP_i32_add); lset(g, p_b);
    }

    lget(g, end_local); lget(g, index); op(g, OP_i32_sub); lset(g, count);
    let rem = local32(g, f);
    lget(g, count); lset(g, rem);
    emitAosF32ContiguousSimd(g, f, k_lanes, mode, p_dst, p_a, p_b, srcB_b != 0, v_scale, nan_vlocal, rem);

    // Advance `index` to `end_local - rem`; any remaining <4 Vec3 / <2 Vec2 tail runs in scalar loop.
    lget(g, end_local); lget(g, rem); op(g, OP_i32_sub); lset(g, index);
    popCheckedArraysAt(f, run_if);
    close(g, f);
    f.checked_elems_len = 0;
    return squid_direct_types::Error.none;
}

// ---- Shared `for x in xs:` / `for { f0, f1 } in ps:` associative integer reduction (SIMD + 4x unroll) ----
// Reused across `#[T]` (Array), `%[T]` (Packed Flat & SoA), and `~[T]` (Seq Flat/Span & SoA).

struct ForInRedPlan {
    matched: bool = false,
    carry_idx: i64 = -1,
    is_xor: bool = false,
    is_i64: bool = false,
    is_record: bool = false,
    inner_ty: Ty = 0,
    inner_is_record: bool = false,
    field_count: i64 = 0,
    field_pos: i64[4] = [0; 4],
}

recursive fn matchForInRedExpr(
    g: Generator&,
    m: const Module&,
    id: u32,
    want_op: squid_check_core::Op,
    carry_iter_b: u32,
    carry_hits: i64&,
    is_record: bool,
    elem_bind: u32,
    inner_ty: Ty,
    is_nominal: bool,
    pat_bs: const u32[16]&,
    pat_pos: const i64[16]&,
    pat_len: i64,
    out_pos: i64[4]&,
    out_len: i64&,
    depth: i64,
) -> bool {
    if id == 0 || depth > 12 { return false; }
    let n = m.node(id);
    if n.tag == squid_check_core::Tag.reference {
        let b = localRef(m, id);
        if b == 0 { return false; }
        if b == carry_iter_b {
            carry_hits += 1;
            return carry_hits <= 1;
        }
        if !is_record {
            if b == elem_bind && out_len < 4 {
                out_pos[out_len] = 0;
                out_len += 1;
                return true;
            }
            return false;
        }
        for pi in 0..pat_len {
            if pat_bs[pi] == b {
                if out_len >= 4 { return false; }
                out_pos[out_len] = pat_pos[pi];
                out_len += 1;
                return true;
            }
        }
        return false;
    }
    if n.tag == squid_check_core::Tag.project && is_record && elem_bind != 0 && localRef(m, n.a) == elem_bind {
        let pos = soaProjectFieldPos(g, m, n.b, inner_ty, is_nominal);
        if pos < 0 || out_len >= 4 { return false; }
        out_pos[out_len] = pos;
        out_len += 1;
        return true;
    }
    let is_op = n.tag == squid_check_core::Tag.scalar || (n.tag == squid_check_core::Tag.associated && n.op != squid_check_core::Op.none);
    if is_op && n.op == want_op && n.b != 0 {
        return matchForInRedExpr(g, m, n.a, want_op, carry_iter_b, carry_hits, is_record, elem_bind, inner_ty, is_nominal, pat_bs, pat_pos, pat_len, out_pos, out_len, depth + 1) &&
               matchForInRedExpr(g, m, n.b, want_op, carry_iter_b, carry_hits, is_record, elem_bind, inner_ty, is_nominal, pat_bs, pat_pos, pat_len, out_pos, out_len, depth + 1);
    }
    return false;
}

fn analyzeForInRedPlan(
    g: Generator&,
    f: Fn&,
    loop_id: u32,
    info: squid_check_core::LoopInfo,
    iteration: Vals,
    slots: Words,
    elem_ty: Ty,
) -> ForInRedPlan {
    var plan = ForInRedPlan {};
    if info.kind != squid_check_core::LoopKind.array || info.pattern == 0 || info.body == 0 { return plan; }
    let m .= g.units[f.unit - 1];
    let carries = m.loopCarries(loop_id);
    if carries.len == 0 || carries.len > 64 { return plan; }

    var red_ci: i64 = -1;
    var acc_tag = squid_direct_types::Tag.unit;
    for carry, ci in carries {
        if carry.backedge == carry.iteration { continue; }
        if red_ci >= 0 || carry.backedge == 0 { return plan; }
        if g.s.words[slots.start + ci] != 0 { return plan; }
        let iv = g.s.vals[iteration.start + ci];
        if iv.len != 1 { return plan; }
        let t = tagOf(g, iv.ty);
        if t != squid_direct_types::Tag.u32_ && t != squid_direct_types::Tag.i32_ &&
            t != squid_direct_types::Tag.u64_ && t != squid_direct_types::Tag.i64_ {
            return plan;
        }
        red_ci = ci;
        acc_tag = t;
    }
    if red_ci < 0 { return plan; }
    let carry_iter_b = carries[red_ci].iteration;
    let carry_back_b = carries[red_ci].backedge;
    let is_i64 = acc_tag == squid_direct_types::Tag.u64_ || acc_tag == squid_direct_types::Tag.i64_;

    let body_node = unwrapSingleBody(m, info.body);
    if body_node == 0 { return plan; }
    let bn = m.node(body_node);
    if bn.tag != squid_check_core::Tag.bind || bn.c >= 2 || bn.a != carry_back_b { return plan; }
    let rhs_n = m.node(bn.b);
    let is_op = rhs_n.tag == squid_check_core::Tag.scalar || (rhs_n.tag == squid_check_core::Tag.associated && rhs_n.op != squid_check_core::Op.none);
    if !is_op || (rhs_n.op != squid_check_core::Op.add && rhs_n.op != squid_check_core::Op.bit_xor) { return plan; }
    let want_op = rhs_n.op;

    // Classify element & loop pattern: flat scalar vs record/tuple/single-ctor field projection or destructuring.
    var is_record = false;
    var is_nominal = false;
    var inner_ty = elem_ty;
    var inner_is_record = false;
    var elem_bind: u32 = 0;
    var pat_bs: u32[16] = [0; 16];
    var pat_pos: i64[16] = [0; 16];
    var pat_len: i64 = 0;

    let etag = tagOf(g, elem_ty);
    if etag == acc_tag {
        let pnode = m.pattern(info.pattern);
        if pnode.tag != squid_check_core::PatternTag.bind { return plan; }
        elem_bind = pnode.a;
    } else {
        let is_rec, rerr = g.types.isRecursive(elem_ty);
        if rerr != squid_direct_types::Error.none || is_rec { return plan; }
        if etag == squid_direct_types::Tag.nominal {
            let cases, cerr = g.types.variants(elem_ty);
            if cerr != squid_direct_types::Error.none || cases.len != 1 { return plan; }
            inner_ty = g.types.variant_payloads[cases.payloads];
            let prec, prerr = g.types.isRecursive(inner_ty);
            if prerr != squid_direct_types::Error.none || prec { return plan; }
            is_nominal = true;
        }
        let in_node = g.types.node(inner_ty);
        if in_node.tag == squid_direct_types::Tag.record {
            inner_is_record = true;
        } else if in_node.tag != squid_direct_types::Tag.tuple {
            return plan;
        }
        let fcount = in_node.b as i64;
        if fcount < 1 || fcount > 16 { return plan; }
        is_record = true;

        let pnode = m.pattern(info.pattern);
        if pnode.tag == squid_check_core::PatternTag.bind {
            if !inner_is_record { return plan; }
            elem_bind = pnode.a;
        } else {
            var p_cur = info.pattern;
            if is_nominal {
                if pnode.tag != squid_check_core::PatternTag.constructor || pnode.b == 0 { return plan; }
                p_cur = pnode.b;
            }
            let ip = m.pattern(p_cur);
            if !inner_is_record {
                if ip.tag != squid_check_core::PatternTag.product { return plan; }
                let ch = m.patternChildren(p_cur);
                if ch.len != fcount { return plan; }
                for c, ci in ch {
                    let cp = m.pattern(c);
                    if cp.tag == squid_check_core::PatternTag.wildcard { continue; }
                    if cp.tag != squid_check_core::PatternTag.bind || pat_len >= 16 { return plan; }
                    pat_bs[pat_len] = cp.a;
                    pat_pos[pat_len] = ci;
                    pat_len += 1;
                }
            } else {
                var prod_id: u32 = 0;
                if ip.tag == squid_check_core::PatternTag.record_payload { prod_id = ip.b; }
                else if ip.tag == squid_check_core::PatternTag.product { prod_id = p_cur; }
                else { return plan; }
                let rty = m.types.node(ip.ty);
                if rty.tag != squid_check_types::Tag.record { return plan; }
                let ch = m.patternChildren(prod_id);
                if ch.len != (rty.b as i64) { return plan; }
                for c, ci in ch {
                    let cp = m.pattern(c);
                    if cp.tag == squid_check_core::PatternTag.wildcard { continue; }
                    if cp.tag != squid_check_core::PatternTag.bind || pat_len >= 16 { return plan; }
                    let fsp = m.fieldSpelling(m.types.recordField(rty, ci).name);
                    if !fsp.present { return plan; }
                    let pos = g.types.findField(inner_ty, g.types.fieldName(fsp.value));
                    if pos < 0 || pos >= fcount { return plan; }
                    pat_bs[pat_len] = cp.a;
                    pat_pos[pat_len] = pos;
                    pat_len += 1;
                }
            }
        }
    }

    var carry_hits: i64 = 0;
    var out_pos: i64[4] = [0; 4];
    var out_len: i64 = 0;
    if !matchForInRedExpr(g, m, bn.b, want_op, carry_iter_b, carry_hits, is_record, elem_bind, inner_ty, is_nominal, pat_bs, pat_pos, pat_len, out_pos, out_len, 0) {
        return plan;
    }
    if carry_hits != 1 || out_len == 0 { return plan; }

    if is_record {
        let in_node = g.types.node(inner_ty);
        for fi in 0..out_len {
            let pos = out_pos[fi];
            let fty = if inner_is_record { g.types.recordField(inner_ty, pos).ty } else { g.types.words[in_node.a + pos] };
            if tagOf(g, fty) != acc_tag { return plan; }
        }
    }

    plan.matched = true;
    plan.carry_idx = red_ci;
    plan.is_xor = want_op == squid_check_core::Op.bit_xor;
    plan.is_i64 = is_i64;
    plan.is_record = is_record;
    plan.inner_ty = inner_ty;
    plan.inner_is_record = inner_is_record;
    plan.field_count = out_len;
    for fi in 0..out_len { plan.field_pos[fi] = out_pos[fi]; }
    return plan;
}

// Emits full 16-wide (i32) / 8-wide (i64) v128 SIMD + 4/2-wide tail + scalar tail reduction
// across `col_count` (1..4) contiguous column pointers for `count_loc` elements into `acc_loc`.
fn emitSimdColumnSum(
    g: Generator&,
    f: Fn&,
    col_starts: const u32[4]&,
    col_count: i64,
    count_loc: u32,
    acc_loc: u32,
    is_i64: bool,
    is_xor: bool,
) {
    let elem_bytes: u32 = if is_i64 { 8 } else { 4 };
    let lanes_per_vec: u32 = if is_i64 { 2 } else { 4 };
    let elems_per_4x: u32 = lanes_per_vec * 4;
    let vop: u32 = if is_xor { SIMD_v128_xor } else if is_i64 { SIMD_i64x2_add } else { SIMD_i32x4_add };
    let sop = if is_i64 {
        if is_xor { squid_direct_writer::OP_i64_xor } else { squid_direct_writer::OP_i64_add }
    } else {
        if is_xor { OP_i32_xor } else { OP_i32_add }
    };
    let load_op = if is_i64 { squid_direct_writer::OP_i64_load } else { OP_i32_load };
    let load_align: u32 = if is_i64 { 3 } else { 2 };

    var ptrs: u32[4] = [0; 4];
    for c in 0..col_count {
        ptrs[c] = local32(g, f);
        lget(g, col_starts[c]);
        lset(g, ptrs[c]);
    }
    let rem = local32(g, f);
    lget(g, count_loc);
    lset(g, rem);

    let vacc0 = local(g, f, VT_v128); v128Const4(g, 0); lset(g, vacc0);
    let vacc1 = local(g, f, VT_v128); v128Const4(g, 0); lset(g, vacc1);

    // 4x v128 (64-byte) loop with descending offsets 48, 16, 32, 0 per column
    let s4_exit = open(g, f, OP_block);
    let s4_top = open(g, f, OP_loop);
    lget(g, rem); i32Const(g, elems_per_4x); op(g, OP_i32_lt_u);
    br(g, f, OP_br_if, s4_exit);
    for c in 0..col_count {
        lget(g, vacc0); lget(g, ptrs[c]); simdMemOp(g, SIMD_v128_load, load_align, 48); simdOp(g, vop);
        lget(g, ptrs[c]); simdMemOp(g, SIMD_v128_load, load_align, 16); simdOp(g, vop); lset(g, vacc0);
        lget(g, vacc1); lget(g, ptrs[c]); simdMemOp(g, SIMD_v128_load, load_align, 32); simdOp(g, vop);
        lget(g, ptrs[c]); simdMemOp(g, SIMD_v128_load, load_align, 0); simdOp(g, vop); lset(g, vacc1);
        lget(g, ptrs[c]); i32Const(g, 64); op(g, OP_i32_add); lset(g, ptrs[c]);
    }
    lget(g, rem); i32Const(g, elems_per_4x); op(g, OP_i32_sub); lset(g, rem);
    br(g, f, OP_br, s4_top);
    close(g, f);
    close(g, f);

    // 1x v128 (16-byte) tail loop
    let s1_exit = open(g, f, OP_block);
    let s1_top = open(g, f, OP_loop);
    lget(g, rem); i32Const(g, lanes_per_vec); op(g, OP_i32_lt_u);
    br(g, f, OP_br_if, s1_exit);
    for c in 0..col_count {
        lget(g, vacc0); lget(g, ptrs[c]); simdMemOp(g, SIMD_v128_load, load_align, 0); simdOp(g, vop); lset(g, vacc0);
        lget(g, ptrs[c]); i32Const(g, 16); op(g, OP_i32_add); lset(g, ptrs[c]);
    }
    lget(g, rem); i32Const(g, lanes_per_vec); op(g, OP_i32_sub); lset(g, rem);
    br(g, f, OP_br, s1_top);
    close(g, f);
    close(g, f);

    // Horizontal reduction into acc_loc
    let vtot = local(g, f, VT_v128);
    lget(g, vacc0); lget(g, vacc1); simdOp(g, vop); lset(g, vtot);
    lget(g, acc_loc);
    if is_i64 {
        lget(g, vtot); simdLaneOp(g, SIMD_i64x2_extract_lane, 0); op(g, sop);
        lget(g, vtot); simdLaneOp(g, SIMD_i64x2_extract_lane, 1); op(g, sop);
    } else {
        for lane in 0..4 {
            lget(g, vtot); simdLaneOp(g, SIMD_i32x4_extract_lane, lane as u8); op(g, sop);
        }
    }
    lset(g, acc_loc);

    // Scalar tail (0..3 i32 or 0..1 i64)
    let t_exit = open(g, f, OP_block);
    let t_top = open(g, f, OP_loop);
    lget(g, rem); op(g, OP_i32_eqz); br(g, f, OP_br_if, t_exit);
    lget(g, acc_loc);
    for c in 0..col_count {
        lget(g, ptrs[c]); op(g, load_op); uleb(g, load_align); uleb(g, 0); op(g, sop);
        lget(g, ptrs[c]); i32Const(g, elem_bytes); op(g, OP_i32_add); lset(g, ptrs[c]);
    }
    lset(g, acc_loc);
    lget(g, rem); i32Const(g, 1); op(g, OP_i32_sub); lset(g, rem);
    br(g, f, OP_br, t_top);
    close(g, f);
    close(g, f);
}

fn tryEmitForInArrayReduction(
    g: Generator&,
    f: Fn&,
    loop_id: u32,
    info: squid_check_core::LoopInfo,
    iteration: Vals,
    slots: Words,
    index: u32,
    end_loc: u32,
    source: Val,
) -> Error {
    let elem_ty, eerr = elementOf(g, f, source.ty, loop_id);
    if eerr != squid_direct_types::Error.none { g.dropFailure(); return squid_direct_types::Error.none; }
    let plan = analyzeForInRedPlan(g, f, loop_id, info, iteration, slots, elem_ty);
    if !plan.matched { return squid_direct_types::Error.none; }
    let ada = findDirectArrayBySlot(f, w(g, source, 0));
    if ada >= 0 && f.direct_arrays[ada].scalar_packed { return squid_direct_types::Error.none; }

    let step, sterr = stride(g, f, elem_ty, loop_id);
    if sterr != squid_direct_types::Error.none || step == 0 { g.dropFailure(); return squid_direct_types::Error.none; }

    var field_offs: u32[4] = [0; 4];
    if plan.is_record {
        for fi in 0..plan.field_count {
            var off: u32 = 0;
            var oerr = squid_direct_types::Error.none;
            if plan.inner_is_record {
                let o1, e1 = fieldOffset(g, f, plan.inner_ty, plan.field_pos[fi], loop_id);
                off = o1;
                oerr = e1;
            } else {
                let o2, e2 = itemOffset(g, f, plan.inner_ty, plan.field_pos[fi], loop_id);
                off = o2;
                oerr = e2;
            }
            if oerr != squid_direct_types::Error.none { g.dropFailure(); return squid_direct_types::Error.none; }
            field_offs[fi] = off;
        }
    }

    let arr_base, arr_len = ensureCheckedArray(g, f, source);
    let acc_loc = w(g, g.s.vals[iteration.start + plan.carry_idx], 0);

    lget(g, index); lget(g, end_loc); op(g, OP_i32_lt_u);
    lget(g, end_loc); lget(g, arr_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
    let run_if = open(g, f, OP_if_);
    let count = local32(g, f);
    lget(g, end_loc); lget(g, index); op(g, OP_i32_sub); lset(g, count);
    let start_ptr = emitOffsetAddress(g, f, arr_base, index, step);

    if !plan.is_record {
        var cols: u32[4] = [start_ptr, 0, 0, 0];
        emitSimdColumnSum(g, f, cols, 1, count, acc_loc, plan.is_i64, plan.is_xor);
    } else {
        // 4x unrolled direct-offset AoS record field reduction (zero record copy, 1 bounds check / 4 records!).
        let sop = if plan.is_i64 {
            if plan.is_xor { squid_direct_writer::OP_i64_xor } else { squid_direct_writer::OP_i64_add }
        } else {
            if plan.is_xor { OP_i32_xor } else { OP_i32_add }
        };
        let load_op = if plan.is_i64 { squid_direct_writer::OP_i64_load } else { OP_i32_load };
        let load_align: u32 = if plan.is_i64 { 3 } else { 2 };
        let ptr = local32(g, f);
        lget(g, start_ptr); lset(g, ptr);
        let rem = local32(g, f);
        lget(g, count); lset(g, rem);

        let a_exit = open(g, f, OP_block);
        let a_top = open(g, f, OP_loop);
        lget(g, rem); i32Const(g, 4); op(g, OP_i32_lt_u);
        br(g, f, OP_br_if, a_exit);
        lget(g, acc_loc);
        var u: i64 = 4;
        while u > 0 {
            u -= 1;
            let base_off = (u as u32) * step;
            var fi = plan.field_count;
            while fi > 0 {
                fi -= 1;
                lget(g, ptr); op(g, load_op); uleb(g, load_align); uleb(g, base_off + field_offs[fi]);
                op(g, sop);
            }
        }
        lset(g, acc_loc);
        lget(g, ptr); i32Const(g, step * 4); op(g, OP_i32_add); lset(g, ptr);
        lget(g, rem); i32Const(g, 4); op(g, OP_i32_sub); lset(g, rem);
        br(g, f, OP_br, a_top);
        close(g, f);
        close(g, f);

        let t_exit = open(g, f, OP_block);
        let t_top = open(g, f, OP_loop);
        lget(g, rem); op(g, OP_i32_eqz); br(g, f, OP_br_if, t_exit);
        lget(g, acc_loc);
        for fi in 0..plan.field_count {
            lget(g, ptr); op(g, load_op); uleb(g, load_align); uleb(g, field_offs[fi]);
            op(g, sop);
        }
        lset(g, acc_loc);
        lget(g, ptr); i32Const(g, step); op(g, OP_i32_add); lset(g, ptr);
        lget(g, rem); i32Const(g, 1); op(g, OP_i32_sub); lset(g, rem);
        br(g, f, OP_br, t_top);
        close(g, f);
        close(g, f);
    }

    lget(g, end_loc); lset(g, index);
    popCheckedArraysAt(f, run_if);
    close(g, f);
    f.checked_elems_len = 0;
    return squid_direct_types::Error.none;
}

// ---- Fast counted range-push loops across `#[T]`, `%[T]` (Flat & SoA), and `~[T]` (Flat & SoA) ----
// Matches `for i in start..end: xs := xs.push <pure_val_expr>` (or `self.push` / `@storage.push`)
// and lowers to:
//   - `#[T]` & `%[T]` Flat: single pre-reserve + 16-wide v128 affine/const SIMD fill (or direct AoS field writes) + single entry.length update.
//   - `%[T]` SoA: single pre-reserve + per-column contiguous 64B/iter v128 SIMD affine/const fill + single entry.length update.
//   - `~[T]` Flat & SoA: direct full-leaf (`leaf_cap`) allocation + 64B/iter v128 SIMD fill + O(1) right-spine leaf append (zero FocusGap copy!).

recursive fn isPureNonTrappingPushExpr(
    g: Generator&,
    f: const Fn&,
    m: const Module&,
    id: u32,
    iter_b: u32,
    uses_iter: bool&,
    budget: i64&,
) -> bool {
    if id == 0 || budget <= 0 { return false; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        constant => { return true; },
        reference => {
            let b = localRef(m, id);
            if b == 0 { return false; }
            if iter_b != 0 && b == iter_b {
                uses_iter = true;
                return true;
            }
            let _, is_cell = withCellType(g, f, b);
            if is_cell { return false; }
            let bv, bok = bindGet(g, f, b);
            return bok && isScalarTag(tagOf(g, bv.ty));
        },
        scalar, associated => {
            if n.tag == squid_check_core::Tag.associated && n.op == squid_check_core::Op.none { return false; }
            if n.op == squid_check_core::Op.div || n.op == squid_check_core::Op.rem { return false; }
            if !isPureNonTrappingPushExpr(g, f, m, n.a, iter_b, uses_iter, budget) { return false; }
            if n.b != 0 && !isPureNonTrappingPushExpr(g, f, m, n.b, iter_b, uses_iter, budget) { return false; }
            return true;
        },
        record, product => {
            for ch in m.children(id) {
                if !isPureNonTrappingPushExpr(g, f, m, ch, iter_b, uses_iter, budget) { return false; }
            }
            return true;
        },
        _ => { return false; },
    }
}

recursive fn matchAffineI32OfIter(
    g: Generator&,
    f: const Fn&,
    m: const Module&,
    id: u32,
    iter_b: u32,
    depth: i64,
) -> bool, u32, u32 {
    if id == 0 || depth > 12 { return false, 0, 0; }
    let ty, tok = lowerInEnv(g, m, m.typeOf(id), f.env);
    if !tok { return false, 0, 0; }
    let t = tagOf(g, ty);
    if t != squid_direct_types::Tag.u32_ && t != squid_direct_types::Tag.i32_ { return false, 0, 0; }
    let n = m.node(id);
    if n.tag == squid_check_core::Tag.constant {
        return true, 0, n.a;
    }
    if n.tag == squid_check_core::Tag.reference {
        let b = localRef(m, id);
        if iter_b != 0 && b == iter_b { return true, 1, 0; }
        return false, 0, 0;
    }
    let is_op = n.tag == squid_check_core::Tag.scalar || (n.tag == squid_check_core::Tag.associated && n.op != squid_check_core::Op.none);
    if !is_op { return false, 0, 0; }
    if n.b == 0 {
        if n.op == squid_check_core::Op.neg {
            let ok, a, b = matchAffineI32OfIter(g, f, m, n.a, iter_b, depth + 1);
            if !ok { return false, 0, 0; }
            return true, 0 - a, 0 - b;
        }
        return false, 0, 0;
    }
    let ok1, a1, b1 = matchAffineI32OfIter(g, f, m, n.a, iter_b, depth + 1);
    if !ok1 { return false, 0, 0; }
    let ok2, a2, b2 = matchAffineI32OfIter(g, f, m, n.b, iter_b, depth + 1);
    if !ok2 { return false, 0, 0; }
    if n.op == squid_check_core::Op.add { return true, a1 + a2, b1 + b2; }
    if n.op == squid_check_core::Op.sub { return true, a1 - a2, b1 - b2; }
    if n.op == squid_check_core::Op.mul {
        if a1 == 0 { return true, b1 * a2, b1 * b2; }
        if a2 == 0 { return true, a1 * b2, b1 * b2; }
        return false, 0, 0;
    }
    if n.op == squid_check_core::Op.shift_left && a2 == 0 {
        let sh = b2 & 31;
        return true, a1 << sh, b1 << sh;
    }
    return false, 0, 0;
}

// Writes `count_loc` 32-bit values `a_val * (start_idx + k) + b_val` into `[dst_ptr .. dst_ptr + count_loc * 4)`
// using 16-wide (64B/iter) descending v128 stores + 4-wide tail + scalar tail.
fn emitAffineI32SimdFill(
    g: Generator&,
    f: Fn&,
    dst_ptr: u32,
    start_idx: u32,
    count_loc: u32,
    a_val: u32,
    b_val: u32,
) {
    let ptr = local32(g, f);
    lget(g, dst_ptr); lset(g, ptr);
    let rem = local32(g, f);
    lget(g, count_loc); lset(g, rem);

    let v0 = local(g, f, VT_v128);
    if a_val == 0 {
        v128Const4(g, b_val); lset(g, v0);
        let s16_exit = open(g, f, OP_block);
        let s16_top = open(g, f, OP_loop);
        lget(g, rem); i32Const(g, 16); op(g, OP_i32_lt_u); br(g, f, OP_br_if, s16_exit);
        lget(g, ptr); lget(g, v0); simdMemOp(g, SIMD_v128_store, 2, 48);
        lget(g, ptr); lget(g, v0); simdMemOp(g, SIMD_v128_store, 2, 32);
        lget(g, ptr); lget(g, v0); simdMemOp(g, SIMD_v128_store, 2, 16);
        lget(g, ptr); lget(g, v0); simdMemOp(g, SIMD_v128_store, 2, 0);
        lget(g, ptr); i32Const(g, 64); op(g, OP_i32_add); lset(g, ptr);
        lget(g, rem); i32Const(g, 16); op(g, OP_i32_sub); lset(g, rem);
        br(g, f, OP_br, s16_top);
        close(g, f); close(g, f);

        let s4_exit = open(g, f, OP_block);
        let s4_top = open(g, f, OP_loop);
        lget(g, rem); i32Const(g, 4); op(g, OP_i32_lt_u); br(g, f, OP_br_if, s4_exit);
        lget(g, ptr); lget(g, v0); simdMemOp(g, SIMD_v128_store, 2, 0);
        lget(g, ptr); i32Const(g, 16); op(g, OP_i32_add); lset(g, ptr);
        lget(g, rem); i32Const(g, 4); op(g, OP_i32_sub); lset(g, rem);
        br(g, f, OP_br, s4_top);
        close(g, f); close(g, f);

        let t_exit = open(g, f, OP_block);
        let t_top = open(g, f, OP_loop);
        lget(g, rem); op(g, OP_i32_eqz); br(g, f, OP_br_if, t_exit);
        lget(g, ptr); i32Const(g, b_val); op(g, squid_direct_writer::OP_i32_store); uleb(g, 2); uleb(g, 0);
        lget(g, ptr); i32Const(g, 4); op(g, OP_i32_add); lset(g, ptr);
        lget(g, rem); i32Const(g, 1); op(g, OP_i32_sub); lset(g, rem);
        br(g, f, OP_br, t_top);
        close(g, f); close(g, f);
        return;
    }

    let v1 = local(g, f, VT_v128);
    let v2 = local(g, f, VT_v128);
    let v3 = local(g, f, VT_v128);
    let v_base = local(g, f, VT_v128);
    let v16 = local(g, f, VT_v128);
    let v4 = local(g, f, VT_v128);

    lget(g, start_idx);
    if a_val != 1 {
        i32Const(g, a_val); op(g, squid_direct_writer::OP_i32_mul);
    }
    if b_val != 0 {
        i32Const(g, b_val); op(g, OP_i32_add);
    }
    simdOp(g, SIMD_i32x4_splat); lset(g, v_base);

    lget(g, v_base); v128ConstWords(g, 0, a_val, a_val * 2, a_val * 3); simdOp(g, SIMD_i32x4_add); lset(g, v0);
    lget(g, v_base); v128ConstWords(g, a_val * 4, a_val * 5, a_val * 6, a_val * 7); simdOp(g, SIMD_i32x4_add); lset(g, v1);
    lget(g, v_base); v128ConstWords(g, a_val * 8, a_val * 9, a_val * 10, a_val * 11); simdOp(g, SIMD_i32x4_add); lset(g, v2);
    lget(g, v_base); v128ConstWords(g, a_val * 12, a_val * 13, a_val * 14, a_val * 15); simdOp(g, SIMD_i32x4_add); lset(g, v3);
    v128Const4(g, a_val * 16); lset(g, v16);
    v128Const4(g, a_val * 4); lset(g, v4);

    let s16_exit = open(g, f, OP_block);
    let s16_top = open(g, f, OP_loop);
    lget(g, rem); i32Const(g, 16); op(g, OP_i32_lt_u); br(g, f, OP_br_if, s16_exit);
    lget(g, ptr); lget(g, v3); simdMemOp(g, SIMD_v128_store, 2, 48);
    lget(g, ptr); lget(g, v2); simdMemOp(g, SIMD_v128_store, 2, 32);
    lget(g, ptr); lget(g, v1); simdMemOp(g, SIMD_v128_store, 2, 16);
    lget(g, ptr); lget(g, v0); simdMemOp(g, SIMD_v128_store, 2, 0);
    lget(g, v0); lget(g, v16); simdOp(g, SIMD_i32x4_add); lset(g, v0);
    lget(g, v1); lget(g, v16); simdOp(g, SIMD_i32x4_add); lset(g, v1);
    lget(g, v2); lget(g, v16); simdOp(g, SIMD_i32x4_add); lset(g, v2);
    lget(g, v3); lget(g, v16); simdOp(g, SIMD_i32x4_add); lset(g, v3);
    lget(g, ptr); i32Const(g, 64); op(g, OP_i32_add); lset(g, ptr);
    lget(g, rem); i32Const(g, 16); op(g, OP_i32_sub); lset(g, rem);
    br(g, f, OP_br, s16_top);
    close(g, f); close(g, f);

    let s4_exit = open(g, f, OP_block);
    let s4_top = open(g, f, OP_loop);
    lget(g, rem); i32Const(g, 4); op(g, OP_i32_lt_u); br(g, f, OP_br_if, s4_exit);
    lget(g, ptr); lget(g, v0); simdMemOp(g, SIMD_v128_store, 2, 0);
    lget(g, v0); lget(g, v4); simdOp(g, SIMD_i32x4_add); lset(g, v0);
    lget(g, ptr); i32Const(g, 16); op(g, OP_i32_add); lset(g, ptr);
    lget(g, rem); i32Const(g, 4); op(g, OP_i32_sub); lset(g, rem);
    br(g, f, OP_br, s4_top);
    close(g, f); close(g, f);

    let cur_v = local32(g, f);
    lget(g, v0); simdLaneOp(g, SIMD_i32x4_extract_lane, 0); lset(g, cur_v);
    let t_exit = open(g, f, OP_block);
    let t_top = open(g, f, OP_loop);
    lget(g, rem); op(g, OP_i32_eqz); br(g, f, OP_br_if, t_exit);
    lget(g, ptr); lget(g, cur_v); op(g, squid_direct_writer::OP_i32_store); uleb(g, 2); uleb(g, 0);
    lget(g, cur_v); i32Const(g, a_val); op(g, OP_i32_add); lset(g, cur_v);
    lget(g, ptr); i32Const(g, 4); op(g, OP_i32_add); lset(g, ptr);
    lget(g, rem); i32Const(g, 1); op(g, OP_i32_sub); lset(g, rem);
    br(g, f, OP_br, t_top);
    close(g, f); close(g, f);
}

// Writes `count_loc` copies of a loop-invariant scalar `val` (pre-splatted in `v_splat` when != 0xffffffff)
// into `[dst_ptr .. dst_ptr + count_loc * step)`.
fn emitConstSimdFill(
    g: Generator&,
    f: Fn&,
    dst_ptr: u32,
    count_loc: u32,
    val: Val,
    v_splat: u32,
    step: u32,
    id: u32,
) -> Error {
    if step == 1 && val.len == 1 {
        lget(g, dst_ptr); lget(g, w(g, val, 0)); lget(g, count_loc); memoryFillOp(g);
        return squid_direct_types::Error.none;
    }
    let ptr = local32(g, f);
    lget(g, dst_ptr); lset(g, ptr);
    let rem = local32(g, f);
    lget(g, count_loc); lset(g, rem);

    if v_splat != 0xffffffff && (step == 4 || step == 8) {
        let lanes: u32 = if step == 4 { 4 } else { 2 };
        let lanes16: u32 = lanes * 4;
        let s16_exit = open(g, f, OP_block);
        let s16_top = open(g, f, OP_loop);
        lget(g, rem); i32Const(g, lanes16); op(g, OP_i32_lt_u); br(g, f, OP_br_if, s16_exit);
        lget(g, ptr); lget(g, v_splat); simdMemOp(g, SIMD_v128_store, 2, 48);
        lget(g, ptr); lget(g, v_splat); simdMemOp(g, SIMD_v128_store, 2, 32);
        lget(g, ptr); lget(g, v_splat); simdMemOp(g, SIMD_v128_store, 2, 16);
        lget(g, ptr); lget(g, v_splat); simdMemOp(g, SIMD_v128_store, 2, 0);
        lget(g, ptr); i32Const(g, 64); op(g, OP_i32_add); lset(g, ptr);
        lget(g, rem); i32Const(g, lanes16); op(g, OP_i32_sub); lset(g, rem);
        br(g, f, OP_br, s16_top);
        close(g, f); close(g, f);

        let s4_exit = open(g, f, OP_block);
        let s4_top = open(g, f, OP_loop);
        lget(g, rem); i32Const(g, lanes); op(g, OP_i32_lt_u); br(g, f, OP_br_if, s4_exit);
        lget(g, ptr); lget(g, v_splat); simdMemOp(g, SIMD_v128_store, 2, 0);
        lget(g, ptr); i32Const(g, 16); op(g, OP_i32_add); lset(g, ptr);
        lget(g, rem); i32Const(g, lanes); op(g, OP_i32_sub); lset(g, rem);
        br(g, f, OP_br, s4_top);
        close(g, f); close(g, f);
    }

    let t_exit = open(g, f, OP_block);
    let t_top = open(g, f, OP_loop);
    lget(g, rem); op(g, OP_i32_eqz); br(g, f, OP_br_if, t_exit);
    let werr = writeElement(g, f, ptr, 0, val, id);
    if werr != squid_direct_types::Error.none { return werr; }
    lget(g, ptr); i32Const(g, step); op(g, OP_i32_add); lset(g, ptr);
    lget(g, rem); i32Const(g, 1); op(g, OP_i32_sub); lset(g, rem);
    br(g, f, OP_br, t_top);
    close(g, f); close(g, f);
    return squid_direct_types::Error.none;
}

fn splatScalarVal(g: Generator&, f: Fn&, val: Val, step: u32) -> u32 {
    if val.len != 1 { return 0xffffffff; }
    let t = tagOf(g, val.ty);
    if step == 4 && (t == squid_direct_types::Tag.u32_ || t == squid_direct_types::Tag.i32_ || t == squid_direct_types::Tag.f32_) {
        let vl = local(g, f, VT_v128);
        lget(g, w(g, val, 0));
        if t == squid_direct_types::Tag.f32_ { simdOp(g, SIMD_f32x4_splat); } else { simdOp(g, SIMD_i32x4_splat); }
        lset(g, vl);
        return vl;
    }
    if step == 8 && (t == squid_direct_types::Tag.u64_ || t == squid_direct_types::Tag.i64_ || t == squid_direct_types::Tag.f64_) {
        let vl = local(g, f, VT_v128);
        lget(g, w(g, val, 0));
        if t == squid_direct_types::Tag.f64_ { simdOp(g, SIMD_f64x2_splat); } else { simdOp(g, SIMD_i64x2_splat); }
        lset(g, vl);
        return vl;
    }
    return 0xffffffff;
}

recursive fn emitPushColumnFill(
    g: Generator&,
    f: Fn&,
    dst_ptr: u32,
    start_idx: u32,
    count_loc: u32,
    iter_b: u32,
    col_expr_id: u32,
    is_inv: bool,
    inv_val: Val,
    inv_vsplat: u32,
    is_affine: bool,
    aff_a: u32,
    aff_b: u32,
    step: u32,
    id: u32,
) -> Error {
    if is_inv {
        return emitConstSimdFill(g, f, dst_ptr, count_loc, inv_val, inv_vsplat, step, id);
    }
    if is_affine && step == 4 {
        emitAffineI32SimdFill(g, f, dst_ptr, start_idx, count_loc, aff_a, aff_b);
        return squid_direct_types::Error.none;
    }
    let ptr = local32(g, f);
    lget(g, dst_ptr); lset(g, ptr);
    let cur_i = local32(g, f);
    lget(g, start_idx); lset(g, cur_i);
    let rem = local32(g, f);
    lget(g, count_loc); lset(g, rem);
    if iter_b != 0 { bindPut(g, f, iter_b, valOf1(g, squid_direct_types::u32_, cur_i)); }
    let t_exit = open(g, f, OP_block);
    let t_top = open(g, f, OP_loop);
    lget(g, rem); op(g, OP_i32_eqz); br(g, f, OP_br_if, t_exit);
    let ev, eerr = expr(g, f, col_expr_id);
    if eerr != squid_direct_types::Error.none { return eerr; }
    let werr = writeElement(g, f, ptr, 0, ev, id);
    if werr != squid_direct_types::Error.none { return werr; }
    lget(g, ptr); i32Const(g, step); op(g, OP_i32_add); lset(g, ptr);
    lget(g, cur_i); i32Const(g, 1); op(g, OP_i32_add); lset(g, cur_i);
    lget(g, rem); i32Const(g, 1); op(g, OP_i32_sub); lset(g, rem);
    br(g, f, OP_br, t_top);
    close(g, f); close(g, f);
    return squid_direct_types::Error.none;
}

struct FastPushPlan {
    matched: bool = false,
    iter_b: u32 = 0,
    dest: Val = Val {},
    dtag: squid_direct_types::Tag = squid_direct_types::Tag.unit,
    elem_ty: Ty = 0,
    elem_step: u32 = 0,
    val_expr_id: u32 = 0,
    method_target: BindingRef = BindingRef { 0, 0 },
    is_rec_lit: bool = false,
    rec_field_count: i64 = 0,
    rec_exprs: u32[16] = [0; 16],
    rec_offs: u32[16] = [0; 16],
    rec_steps: u32[16] = [0; 16],
    rec_is_inv: bool[16] = [false; 16],
    rec_is_aff: bool[16] = [false; 16],
    rec_aff_a: u32[16] = [0; 16],
    rec_aff_b: u32[16] = [0; 16],
    scalar_is_inv: bool = false,
    scalar_is_aff: bool = false,
    scalar_aff_a: u32 = 0,
    scalar_aff_b: u32 = 0,
}

fn analyzeFastPushRangeLoop(
    g: Generator&,
    f: Fn&,
    loop_id: u32,
    info: squid_check_core::LoopInfo,
    iteration: Vals,
    carry_in_place: const bool[64]&,
) -> FastPushPlan {
    var plan = FastPushPlan {};
    let m .= g.units[f.unit - 1];
    let pat = m.pattern(info.pattern);
    if pat.tag == squid_check_core::PatternTag.bind {
        plan.iter_b = pat.a;
    } else if pat.tag != squid_check_core::PatternTag.wildcard {
        return plan;
    }
    let carries = m.loopCarries(loop_id);
    if carries.len != 1 || !carry_in_place[0] { return plan; }
    let carry = carries[0];
    if carry.backedge == 0 { return plan; }
    plan.dest = g.s.vals[iteration.start];
    plan.dtag = tagOf(g, plan.dest.ty);
    if plan.dtag != squid_direct_types::Tag.array && plan.dtag != squid_direct_types::Tag.packed && plan.dtag != squid_direct_types::Tag.seq {
        return plan;
    }
    if findDirectArray(f, carry.incoming) >= 0 || findDirectArrayBySlot(f, w(g, plan.dest, 0)) >= 0 {
        return plan;
    }

    let body_node = unwrapSingleBody(m, info.body);
    if body_node == 0 { return plan; }
    let bnode = m.node(body_node);
    if bnode.tag != squid_check_core::Tag.bind || bnode.c >= 2 || bnode.a != carry.backedge {
        return plan;
    }
    let push_id = bnode.b;
    let bn = m.node(push_id);
    var recv_b: u32 = 0;
    if bn.tag == squid_check_core::Tag.storage {
        let op_kind, ok = squid_check_storage_ops::opFromCode(bn.c);
        if ok != squid_error::Error.none || op_kind != squid_check_storage_ops::Op.push {
            return plan;
        }
        let ch = m.children(push_id);
        if ch.len != 2 { return plan; }
        recv_b = localRef(m, ch[0]);
        plan.val_expr_id = ch[1];
    } else if bn.tag == squid_check_core::Tag.apply {
        if m.node(bn.a).tag != squid_check_core::Tag.project { return plan; }
        let proj = m.node(bn.a);
        recv_b = localRef(m, proj.a);
        if recv_b == 0 { return plan; }
        let identity, has_id = g.receiverIdentity(plan.dest.ty);
        if !has_id { return plan; }
        let target, has_target = g.dispatchTarget(m, identity, m.projection(proj.b).field, squid_check_types::Operator.none);
        if !has_target || !g.hasUnit(target.unit) { return plan; }
        let tm .= g.units[target.unit - 1];
        let tbody .= tm.body(target.binding);
        if !tbody || !isTwoParamPushForwarder(tm, tbody) { return plan; }
        plan.method_target = target;
        plan.val_expr_id = bn.b;
    } else if bn.tag == squid_check_core::Tag.call {
        let cinfo = m.call(push_id);
        if cinfo.arguments.len != 2 { return plan; }
        let target = g.resolve(m, cinfo.target);
        if !g.hasUnit(target.unit) { return plan; }
        let tm .= g.units[target.unit - 1];
        let tbody .= tm.body(target.binding);
        if !tbody || !isTwoParamPushForwarder(tm, tbody) { return plan; }
        recv_b = localRef(m, cinfo.arguments[0]);
        plan.val_expr_id = cinfo.arguments[1];
        plan.method_target = target;
    } else {
        return plan;
    }
    if recv_b != carry.iteration || plan.val_expr_id == 0 { return plan; }

    let ety, eerr = elementOf(g, f, plan.dest.ty, loop_id);
    if eerr != squid_direct_types::Error.none { g.dropFailure(); return plan; }
    plan.elem_ty = ety;
    if holdsContainer(g, ety, 0) { return plan; }
    let st, sterr = stride(g, f, ety, loop_id);
    if sterr != squid_direct_types::Error.none || st == 0 || st > 65536 {
        g.dropFailure();
        return plan;
    }
    plan.elem_step = st;

    let etag = tagOf(g, ety);
    if isScalarTag(etag) {
        var uses_it = false;
        var budget: i64 = 128;
        if !isPureNonTrappingPushExpr(g, f, m, plan.val_expr_id, plan.iter_b, uses_it, budget) {
            return plan;
        }
        plan.scalar_is_inv = !uses_it;
        if uses_it && (etag == squid_direct_types::Tag.u32_ || etag == squid_direct_types::Tag.i32_) {
            let aok, aa, ab = matchAffineI32OfIter(g, f, m, plan.val_expr_id, plan.iter_b, 0);
            if aok {
                plan.scalar_is_aff = true;
                plan.scalar_aff_a = aa;
                plan.scalar_aff_b = ab;
            }
        }
        plan.matched = true;
        return plan;
    }
    if etag != squid_direct_types::Tag.record && etag != squid_direct_types::Tag.tuple {
        return plan;
    }
    let vn = m.node(plan.val_expr_id);
    let shape = g.types.node(ety);
    let nf = shape.b as i64;
    if nf <= 0 || nf > 16 { return plan; }
    let ch = m.children(plan.val_expr_id);
    if ch.len != nf { return plan; }
    let is_rec = etag == squid_direct_types::Tag.record;
    if is_rec {
        if vn.tag != squid_check_core::Tag.record { return plan; }
        let source = m.types.node(m.typeOf(plan.val_expr_id));
        if source.tag != squid_check_types::Tag.record { return plan; }
        let dests = m.recordDestinations(plan.val_expr_id);
        for ci in 0..nf {
            let fld = m.types.recordField(source, dests[ci]);
            let fname, has_fn = g.types.fieldNameOf(m, fld.name, true);
            if !has_fn { return plan; }
            let pos = g.types.findField(ety, fname);
            if pos < 0 || pos >= nf || plan.rec_exprs[pos] != 0 { return plan; }
            plan.rec_exprs[pos] = ch[ci];
        }
    } else {
        if vn.tag != squid_check_core::Tag.product { return plan; }
        for ci in 0..nf { plan.rec_exprs[ci] = ch[ci]; }
    }
    for fi in 0..nf {
        let fty = if is_rec { g.types.recordField(ety, fi).ty } else { g.types.words[shape.a + fi] };
        let ftag = tagOf(g, fty);
        if !isScalarTag(ftag) { return plan; }
        let fstep, fserr = stride(g, f, fty, loop_id);
        if fserr != squid_direct_types::Error.none || fstep == 0 { g.dropFailure(); return plan; }
        var foff: u32 = 0;
        var foerr = squid_direct_types::Error.none;
        if is_rec {
            let fo1, fe1 = fieldOffset(g, f, ety, fi, loop_id);
            foff = fo1;
            foerr = fe1;
        } else {
            let fo2, fe2 = itemOffset(g, f, ety, fi, loop_id);
            foff = fo2;
            foerr = fe2;
        }
        if foerr != squid_direct_types::Error.none { g.dropFailure(); return plan; }
        var uses_it = false;
        var budget: i64 = 128;
        if !isPureNonTrappingPushExpr(g, f, m, plan.rec_exprs[fi], plan.iter_b, uses_it, budget) {
            return plan;
        }
        plan.rec_offs[fi] = foff;
        plan.rec_steps[fi] = fstep;
        plan.rec_is_inv[fi] = !uses_it;
        if uses_it && (ftag == squid_direct_types::Tag.u32_ || ftag == squid_direct_types::Tag.i32_) {
            let aok, aa, ab = matchAffineI32OfIter(g, f, m, plan.rec_exprs[fi], plan.iter_b, 0);
            if aok {
                plan.rec_is_aff[fi] = true;
                plan.rec_aff_a[fi] = aa;
                plan.rec_aff_b[fi] = ab;
            }
        }
    }
    plan.rec_field_count = nf;
    plan.is_rec_lit = true;
    plan.matched = true;
    return plan;
}

recursive fn emitFastPushAosRecLoop(
    g: Generator&,
    f: Fn&,
    plan: const FastPushPlan&,
    dst_ptr: u32,
    start_idx: u32,
    count_loc: u32,
    inv_vals: Vals,
    loop_id: u32,
) -> Error {
    let ptr = local32(g, f);
    lget(g, dst_ptr); lset(g, ptr);
    let cur_i = local32(g, f);
    lget(g, start_idx); lset(g, cur_i);
    let rem = local32(g, f);
    lget(g, count_loc); lset(g, rem);
    if plan.iter_b != 0 { bindPut(g, f, plan.iter_b, valOf1(g, squid_direct_types::u32_, cur_i)); }
    let r_exit = open(g, f, OP_block);
    let r_top = open(g, f, OP_loop);
    lget(g, rem); op(g, OP_i32_eqz); br(g, f, OP_br_if, r_exit);
    for fi in 0..plan.rec_field_count {
        let fv = if plan.rec_is_inv[fi] {
            g.s.vals[inv_vals.start + fi]
        } else {
            let ev, eerr = expr(g, f, plan.rec_exprs[fi]);
            if eerr != squid_direct_types::Error.none { return eerr; }
            ev
        };
        let werr = writeElement(g, f, ptr, plan.rec_offs[fi], fv, loop_id);
        if werr != squid_direct_types::Error.none { return werr; }
    }
    lget(g, ptr); i32Const(g, plan.elem_step); op(g, OP_i32_add); lset(g, ptr);
    lget(g, cur_i); i32Const(g, 1); op(g, OP_i32_add); lset(g, cur_i);
    lget(g, rem); i32Const(g, 1); op(g, OP_i32_sub); lset(g, rem);
    br(g, f, OP_br, r_top);
    close(g, f); close(g, f);
    return squid_direct_types::Error.none;
}

recursive fn emitFastPushFlatBackend(
    g: Generator&,
    f: Fn&,
    plan: const FastPushPlan&,
    loop_id: u32,
    index: u32,
    end_local: u32,
) -> Error {
    let rt = g.runtime_();
    let dest = plan.dest;
    lget(g, index); lget(g, end_local); op(g, OP_i32_lt_u);
    let run_if = open(g, f, OP_if_);
    let count = local32(g, f);
    lget(g, end_local); lget(g, index); op(g, OP_i32_sub); lset(g, count);
    let entry = ensureCheckedGrow(g, f, dest);
    let cap = local32(g, f);
    lget(g, entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_capacity); ltee(g, cap);
    i32Const(g, squid_direct_runtime::static_pool_flag); op(g, OP_i32_and); trap(g, f);
    let old_len = local32(g, f);
    let new_len = local32(g, f);
    lget(g, entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length); ltee(g, old_len);
    lget(g, count); op(g, OP_i32_add); ltee(g, new_len);
    lget(g, old_len); op(g, OP_i32_lt_u);
    let max_count = (rt.layout.heap_end - rt.layout.heap_base) / plan.elem_step;
    lget(g, new_len); i32Const(g, max_count); op(g, OP_i32_gt_u); op(g, OP_i32_or); trap(g, f);
    let need_bytes = emitScaledBytes(g, f, new_len, plan.elem_step);
    let cap_bytes = local32(g, f);
    lget(g, cap); i32Const(g, squid_direct_runtime::capacity_mask); op(g, OP_i32_and); lset(g, cap_bytes);
    lget(g, need_bytes); lget(g, cap_bytes); op(g, OP_i32_gt_u);
    let grow_if = open(g, f, OP_if_);
    lget(g, w(g, dest, 0)); lget(g, w(g, dest, 1)); lget(g, new_len); i32Const(g, plan.elem_step); callf(g, rt.reserve);
    popCheckedArraysAt(f, grow_if);
    close(g, f);

    let arr_base = local32(g, f);
    lget(g, entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base); lset(g, arr_base);
    let dst_ptr = emitOffsetAddress(g, f, arr_base, old_len, plan.elem_step);

    if !plan.is_rec_lit {
        var inv_val = neverVal();
        var inv_vsplat: u32 = 0xffffffff;
        if plan.scalar_is_inv {
            let iv, ierr = expr(g, f, plan.val_expr_id);
            if ierr != squid_direct_types::Error.none { return ierr; }
            inv_val = iv;
            inv_vsplat = splatScalarVal(g, f, iv, plan.elem_step);
        }
        let ferr = emitPushColumnFill(g, f, dst_ptr, index, count, plan.iter_b, plan.val_expr_id, plan.scalar_is_inv, inv_val, inv_vsplat, plan.scalar_is_aff, plan.scalar_aff_a, plan.scalar_aff_b, plan.elem_step, loop_id);
        if ferr != squid_direct_types::Error.none { return ferr; }
    } else {
        let inv_vals = g.reserveVals(plan.rec_field_count);
        for fi in 0..plan.rec_field_count {
            if plan.rec_is_inv[fi] {
                let fv, ferr = expr(g, f, plan.rec_exprs[fi]);
                if ferr != squid_direct_types::Error.none { return ferr; }
                g.s.vals[inv_vals.start + fi] = fv;
            }
        }
        let aerr = emitFastPushAosRecLoop(g, f, plan, dst_ptr, index, count, inv_vals, loop_id);
        if aerr != squid_direct_types::Error.none { return aerr; }
    }

    lget(g, entry); lget(g, new_len); op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    lget(g, end_local); lset(g, index);
    popCheckedArraysAt(f, run_if);
    close(g, f);
    invalidateCheckedOwner(g, f, dest);
    return squid_direct_types::Error.none;
}

recursive fn emitFastPushSoaBackend(
    g: Generator&,
    f: Fn&,
    plan: const FastPushPlan&,
    pplan: const PackedPlan&,
    loop_id: u32,
    index: u32,
    end_local: u32,
) -> Error {
    let rt = g.runtime_();
    let dest = plan.dest;
    lget(g, index); lget(g, end_local); op(g, OP_i32_lt_u);
    let run_if = open(g, f, OP_if_);
    let count = local32(g, f);
    lget(g, end_local); lget(g, index); op(g, OP_i32_sub); lset(g, count);
    let h_entry, h_base, old_len = emitCheckPackedHeaderMutable(g, f, dest);
    let new_len = local32(g, f);
    lget(g, old_len); lget(g, count); op(g, OP_i32_add); ltee(g, new_len);
    lget(g, old_len); op(g, OP_i32_lt_u); trap(g, f);
    let cur_cap = local32(g, f);
    lget(g, new_len);
    lget(g, h_base); op(g, OP_i32_load); uleb(g, 2); uleb(g, PACKED_SOA_HDR_CAP); ltee(g, cur_cap);
    op(g, OP_i32_gt_u);
    let need_grow = open(g, f, OP_if_);
    emitPackedSoaSyncSubLens(g, f, pplan, h_base, old_len);
    let new_cap = local32(g, f);
    lget(g, cur_cap); i32Const(g, 1); op(g, OP_i32_shl);
    i32Const(g, 16);
    lget(g, cur_cap); i32Const(g, 8); op(g, OP_i32_ge_u);
    op(g, OP_select);
    ltee(g, new_cap);
    lget(g, new_len); op(g, OP_i32_lt_u);
    let fix_cap = open(g, f, OP_if_);
    lget(g, new_len); lset(g, new_cap);
    close(g, f);
    for s in 0..pplan.stream_count {
        let sub_slot, sub_gen = emitLoadPackedSubHandle(g, f, pplan, h_base, s);
        lget(g, sub_slot); lget(g, sub_gen); lget(g, new_cap); i32Const(g, pplan.stream_stride[s]);
        callf(g, rt.reserve);
    }
    emitPackedSoaRefreshCache(g, f, pplan, h_base, new_cap);
    popCheckedArraysAt(f, need_grow);
    close(g, f);

    for fi in 0..pplan.soa_field_count {
        let s = pplan.soa_field_stream[fi];
        if s < 0 { continue; }
        let fstep = pplan.stream_stride[s];
        let col_base = local32(g, f);
        lget(g, h_base); op(g, OP_i32_load); uleb(g, 2); uleb(g, packedSoaColBaseOff(pplan, s)); lset(g, col_base);
        let dst_ptr = emitOffsetAddress(g, f, col_base, old_len, fstep);
        var inv_val = neverVal();
        var inv_vsplat: u32 = 0xffffffff;
        if plan.rec_is_inv[fi] {
            let fv, ferr = expr(g, f, plan.rec_exprs[fi]);
            if ferr != squid_direct_types::Error.none { return ferr; }
            inv_val = fv;
            inv_vsplat = splatScalarVal(g, f, fv, fstep);
        }
        let cerr = emitPushColumnFill(g, f, dst_ptr, index, count, plan.iter_b, plan.rec_exprs[fi], plan.rec_is_inv[fi], inv_val, inv_vsplat, plan.rec_is_aff[fi], plan.rec_aff_a[fi], plan.rec_aff_b[fi], fstep, loop_id);
        if cerr != squid_direct_types::Error.none { return cerr; }
    }

    lget(g, h_entry); lget(g, new_len); op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    lget(g, end_local); lset(g, index);
    popCheckedArraysAt(f, run_if);
    close(g, f);
    invalidateCheckedOwner(g, f, dest);
    return squid_direct_types::Error.none;
}

recursive fn emitFastPushSeqBackend(
    g: Generator&,
    f: Fn&,
    plan: const FastPushPlan&,
    splan: const SeqPlan&,
    loop_id: u32,
    index: u32,
    end_local: u32,
) -> Error {
    let wr_fn, werr = ensureSeqWritable(g);
    if werr != squid_direct_types::Error.none { return werr; }
    let flush_fn, flerr = ensureSeqFlushFocus(g, splan);
    if flerr != squid_direct_types::Error.none { return flerr; }
    let push_leaf_fn, plerr = ensureSeqTreePushLeaf(g);
    if plerr != squid_direct_types::Error.none { return plerr; }
    let concat_fn, cerr = ensureSeqTreeConcat(g, splan);
    if cerr != squid_direct_types::Error.none { return cerr; }

    let dest = plan.dest;
    let lcap = splan.leaf_cap;
    lget(g, index); lget(g, end_local); op(g, OP_i32_lt_u);
    let has_iters = open(g, f, OP_if_);
    let count = local32(g, f);
    lget(g, end_local); lget(g, index); op(g, OP_i32_sub); lset(g, count);
    lget(g, count); i32Const(g, lcap); op(g, OP_i32_ge_u);
    let big_enough = open(g, f, OP_if_);

    let entry = local32(g, f);
    let hdr = local32(g, f);
    let epoch = local32(g, f);
    lget(g, w(g, dest, 0)); lget(g, w(g, dest, 1)); callf(g, wr_fn);
    lset(g, epoch); lset(g, hdr); lset(g, entry);

    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_REV); op(g, OP_i32_eqz);
    let not_rev = open(g, f, OP_if_);

    let chunks = local32(g, f);
    lget(g, count); i32Const(g, lcap); op(g, squid_direct_writer::OP_i32_div_u); lset(g, chunks);
    let fast_n = local32(g, f);
    lget(g, chunks); i32Const(g, lcap); op(g, squid_direct_writer::OP_i32_mul); lset(g, fast_n);
    let old_len = local32(g, f);
    let new_len = local32(g, f);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_LEN); ltee(g, old_len);
    lget(g, fast_n); op(g, OP_i32_add); ltee(g, new_len);
    lget(g, old_len); op(g, OP_i32_lt_u); trap(g, f);

    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FOCUS);
    let has_foc = open(g, f, OP_if_);
    lget(g, hdr); lget(g, epoch); callf(g, flush_fn);
    popCheckedArraysAt(f, has_foc);
    close(g, f);
    lget(g, hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_APPEND_EP);
    lget(g, hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_PREPEND_EP);

    var sc_inv_val = neverVal();
    var sc_inv_vsplat: u32 = 0xffffffff;
    var rec_inv_vals = Vals {};
    var rec_inv_vsplats = Words {};
    if !plan.is_rec_lit {
        if plan.scalar_is_inv {
            let iv, ierr = expr(g, f, plan.val_expr_id);
            if ierr != squid_direct_types::Error.none { return ierr; }
            sc_inv_val = iv;
            sc_inv_vsplat = splatScalarVal(g, f, iv, plan.elem_step);
        }
    } else {
        rec_inv_vals = g.reserveVals(plan.rec_field_count);
        rec_inv_vsplats = Words { g.s.words.len as u32, plan.rec_field_count as u32 };
        for fi in 0..plan.rec_field_count { g.s.words.push(0xffffffff); }
        for fi in 0..plan.rec_field_count {
            if plan.rec_is_inv[fi] {
                let fv, ferr = expr(g, f, plan.rec_exprs[fi]);
                if ferr != squid_direct_types::Error.none { return ferr; }
                g.s.vals[rec_inv_vals.start + fi] = fv;
                g.s.words[rec_inv_vsplats.start + fi] = splatScalarVal(g, f, fv, plan.rec_steps[fi]);
            }
        }
    }

    let root = local32(g, f);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_ROOT); lset(g, root);
    let cur_i = local32(g, f);
    lget(g, index); lset(g, cur_i);
    let c_rem = local32(g, f);
    lget(g, chunks); lset(g, c_rem);
    let lcap_loc = constLocal(g, f, lcap);
    let leaf = local32(g, f);
    let fast_r = local32(g, f);
    let leaf_bytes = if splan.leaf_kind == SEQ_KIND_PACKED_SOA { splan.soa_leaf_bytes } else { splan.flat_leaf_bytes };

    let ch_exit = open(g, f, OP_block);
    let ch_top = open(g, f, OP_loop);
    lget(g, c_rem); op(g, OP_i32_eqz); br(g, f, OP_br_if, ch_exit);

    i32Const(g, leaf_bytes); callf(g, g.s.seq_alloc_fn); lset(g, leaf);
    lget(g, leaf); i32Const(g, splan.leaf_kind); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_META);
    lget(g, leaf); lget(g, epoch); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_EPOCH);
    lget(g, leaf); i32Const(g, lcap); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
    if splan.leaf_kind == SEQ_KIND_FLAT {
        lget(g, leaf); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_FOC_CAP);
        let ldata = local32(g, f);
        lget(g, leaf); i32Const(g, SEQ_LEAF_DATA); op(g, OP_i32_add); lset(g, ldata);
        if !plan.is_rec_lit {
            let ferr = emitPushColumnFill(g, f, ldata, cur_i, lcap_loc, plan.iter_b, plan.val_expr_id, plan.scalar_is_inv, sc_inv_val, sc_inv_vsplat, plan.scalar_is_aff, plan.scalar_aff_a, plan.scalar_aff_b, plan.elem_step, loop_id);
            if ferr != squid_direct_types::Error.none { return ferr; }
        } else {
            let aerr = emitFastPushAosRecLoop(g, f, plan, ldata, cur_i, lcap_loc, rec_inv_vals, loop_id);
            if aerr != squid_direct_types::Error.none { return aerr; }
        }
    } else {
        for fi in 0..splan.packed.soa_field_count {
            let s = splan.packed.soa_field_stream[fi];
            if s < 0 { continue; }
            let fstep = splan.packed.stream_stride[s];
            let col_ptr = local32(g, f);
            lget(g, leaf); i32Const(g, splan.soa_col_off[s]); op(g, OP_i32_add); lset(g, col_ptr);
            let iv = if plan.rec_is_inv[fi] { g.s.vals[rec_inv_vals.start + fi] } else { neverVal() };
            let vs = if plan.rec_is_inv[fi] { g.s.words[rec_inv_vsplats.start + fi] } else { 0xffffffff };
            let ferr = emitPushColumnFill(g, f, col_ptr, cur_i, lcap_loc, plan.iter_b, plan.rec_exprs[fi], plan.rec_is_inv[fi], iv, vs, plan.rec_is_aff[fi], plan.rec_aff_a[fi], plan.rec_aff_b[fi], fstep, loop_id);
            if ferr != squid_direct_types::Error.none { return ferr; }
        }
    }

    lget(g, root); op(g, OP_i32_eqz);
    let r_empty = open(g, f, OP_if_);
    lget(g, leaf); lset(g, root);
    popCheckedArraysAt(f, r_empty);
    op(g, OP_else_);
    lget(g, root); lget(g, leaf); lget(g, epoch); callf(g, push_leaf_fn); ltee(g, fast_r);
    let did_fast = open(g, f, OP_if_);
    lget(g, fast_r); lset(g, root);
    popCheckedArraysAt(f, did_fast);
    op(g, OP_else_);
    lget(g, root); lget(g, leaf); lget(g, epoch); callf(g, concat_fn); lset(g, root);
    close(g, f);
    close(g, f);

    lget(g, cur_i); i32Const(g, lcap); op(g, OP_i32_add); lset(g, cur_i);
    lget(g, c_rem); i32Const(g, 1); op(g, OP_i32_sub); lset(g, c_rem);
    br(g, f, OP_br, ch_top);
    close(g, f); close(g, f);

    lget(g, hdr); lget(g, root); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_ROOT);
    lget(g, hdr); lget(g, new_len); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_LEN);
    lget(g, entry); lget(g, new_len); op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    lget(g, cur_i); lset(g, index);

    popCheckedArraysAt(f, not_rev);
    close(g, f);
    popCheckedArraysAt(f, big_enough);
    close(g, f);
    popCheckedArraysAt(f, has_iters);
    close(g, f);
    invalidateCheckedOwner(g, f, dest);
    return squid_direct_types::Error.none;
}

recursive fn tryEmitFastPushRangeLoop(
    g: Generator&,
    f: Fn&,
    loop_id: u32,
    info: squid_check_core::LoopInfo,
    iteration: Vals,
    carry_in_place: const bool[64]&,
    index: u32,
    end_local: u32,
) -> Error {
    if g.runtime_().has_fork || info.kind != squid_check_core::LoopKind.range || info.pattern == 0 || info.body == 0 {
        return squid_direct_types::Error.none;
    }
    let plan = analyzeFastPushRangeLoop(g, f, loop_id, info, iteration, carry_in_place);
    if !plan.matched { return squid_direct_types::Error.none; }

    var pplan = PackedPlan {};
    var splan = SeqPlan {};
    if plan.dtag == squid_direct_types::Tag.packed {
        let pp, perr = computePackedPlan(g, f, plan.elem_ty, loop_id);
        if perr != squid_direct_types::Error.none { g.dropFailure(); return squid_direct_types::Error.none; }
        if pp.mode != PACKED_FLAT && pp.mode != PACKED_SOA { return squid_direct_types::Error.none; }
        if pp.mode == PACKED_SOA && !plan.is_rec_lit { return squid_direct_types::Error.none; }
        pplan = pp;
    } else if plan.dtag == squid_direct_types::Tag.seq {
        let sp, sperr = computeSeqPlan(g, f, plan.elem_ty, loop_id);
        if sperr != squid_direct_types::Error.none { g.dropFailure(); return squid_direct_types::Error.none; }
        if sp.leaf_kind != SEQ_KIND_FLAT && sp.leaf_kind != SEQ_KIND_PACKED_SOA { return squid_direct_types::Error.none; }
        if sp.leaf_kind == SEQ_KIND_PACKED_SOA && !plan.is_rec_lit { return squid_direct_types::Error.none; }
        splan = sp;
    }

    {
        let m .= g.units[f.unit - 1];
        if !plan.is_rec_lit && plan.scalar_is_aff {
            markUnpatchableExprConstants(m, plan.val_expr_id, 0);
        } else if plan.is_rec_lit {
            for fi in 0..plan.rec_field_count {
                if plan.rec_is_aff[fi] { markUnpatchableExprConstants(m, plan.rec_exprs[fi], 0); }
            }
        }
    }
    if plan.method_target.unit != 0 { g.recordInlined(plan.method_target.unit, plan.method_target.binding); }

    if plan.dtag == squid_direct_types::Tag.array || (plan.dtag == squid_direct_types::Tag.packed && pplan.mode == PACKED_FLAT) {
        return emitFastPushFlatBackend(g, f, plan, loop_id, index, end_local);
    }
    if plan.dtag == squid_direct_types::Tag.packed && pplan.mode == PACKED_SOA {
        return emitFastPushSoaBackend(g, f, plan, pplan, loop_id, index, end_local);
    }
    if plan.dtag == squid_direct_types::Tag.seq {
        return emitFastPushSeqBackend(g, f, plan, splan, loop_id, index, end_local);
    }
    return squid_direct_types::Error.none;
}
