// 4-wide Wasm SIMD (`v128`) auto-vectorization for `spark #[body | pat <- source]`.
// Preserves exact wrapping U32 arithmetic, uniform producer-site 0x7fc00000 NaN
// canonicalization, Bool mask normalization, trap-order equivalence, and scalar
// tail / fallback execution.
namespace blot_direct_function;
import .function;
import direct.relocations;

// WebAssembly 1.0 SIMD (0xfd prefix) sub-opcodes.
let SIMD_v128_load: u32 = 0;
let SIMD_v128_store: u32 = 11;
let SIMD_v128_const: u32 = 12;
let SIMD_i32x4_splat: u32 = 17;
let SIMD_f32x4_splat: u32 = 19;
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
let SIMD_v128_not: u32 = 77;
let SIMD_v128_and: u32 = 78;
let SIMD_v128_andnot: u32 = 79;
let SIMD_v128_or: u32 = 80;
let SIMD_v128_xor: u32 = 81;
let SIMD_v128_bitselect: u32 = 82;
let SIMD_v128_store32_lane: u32 = 90;
let SIMD_v128_load32_zero: u32 = 92;
let SIMD_i8x16_narrow_i16x8_u: u32 = 102;
let SIMD_f32x4_ceil: u32 = 103;
let SIMD_f32x4_floor: u32 = 104;
let SIMD_f32x4_trunc: u32 = 105;
let SIMD_i16x8_narrow_i32x4_u: u32 = 134;
let SIMD_i16x8_extend_low_i8x16_u: u32 = 137;
let SIMD_i32x4_neg: u32 = 161;
let SIMD_i32x4_extend_low_i16x8_u: u32 = 169;
let SIMD_i32x4_shl: u32 = 171;
let SIMD_i32x4_shr_s: u32 = 172;
let SIMD_i32x4_shr_u: u32 = 173;
let SIMD_i32x4_add: u32 = 174;
let SIMD_i32x4_sub: u32 = 177;
let SIMD_i32x4_mul: u32 = 181;
let SIMD_f32x4_abs: u32 = 224;
let SIMD_f32x4_neg: u32 = 225;
let SIMD_f32x4_sqrt: u32 = 227;
let SIMD_f32x4_add: u32 = 228;
let SIMD_f32x4_sub: u32 = 229;
let SIMD_f32x4_mul: u32 = 230;
let SIMD_f32x4_div: u32 = 231;
let SIMD_i32x4_trunc_sat_f32x4_s: u32 = 248;
let SIMD_i32x4_trunc_sat_f32x4_u: u32 = 249;
let SIMD_f32x4_convert_i32x4_s: u32 = 250;
let SIMD_f32x4_convert_i32x4_u: u32 = 251;

fn simdOp(g: Generator&, sub: u32) {
    op(g, OP_prefix_fd);
    uleb(g, sub);
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
    blot_direct_writer::word(g.s.code, w0);
    blot_direct_writer::word(g.s.code, w1);
    blot_direct_writer::word(g.s.code, w2);
    blot_direct_writer::word(g.s.code, w3);
}
fn v128Const4(g: Generator&, word: u32) {
    v128ConstWords(g, word, word, word, word);
}
// Canonicalize all NaN lanes of an F32x4 vector on top of the stack to 0x7fc00000.
fn canonicalizeF32x4(g: Generator&, f: const Fn&, nan_vlocal: u32) {
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

// Local binding inside the vectorized spark body (or an inlined leaf helper).
struct SparkVecLocal {
    unit: u32 = 0,
    binding: u32 = 0,
    tag: blot_direct_types::Tag = blot_direct_types::Tag.unit,
    vlocal: u32 = 0,
    is_mask: bool = false,
    invariant: bool = false,
    scalar_local: u32 = 0xffffffff,
}

// Range-affine contiguous stream `arr[i]` or `arr[offset + i]`.
struct SparkAffineStream {
    unit: u32 = 0,
    node_id: u32 = 0,
    arr_id: u32 = 0,
    offset_id: u32 = 0,
    arr_ty: Ty = 0,
    elem_tag: blot_direct_types::Tag = blot_direct_types::Tag.unit,
    ptr_local: u32 = 0,
}

// Pre-hoisted outer scalar capture / constant / invariant expression.
struct SparkHoistedScalar {
    unit: u32 = 0,
    node_id: u32 = 0,
    tag: blot_direct_types::Tag = blot_direct_types::Tag.unit,
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
    iter_tag: blot_direct_types::Tag = blot_direct_types::Tag.unit,
    out_tag: blot_direct_types::Tag = blot_direct_types::Tag.unit,
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
fn isContiguousScalarContainer(g: const Generator&, ty: Ty) -> blot_direct_types::Tag, bool {
    let n = g.types.node(ty);
    if n.tag != blot_direct_types::Tag.array && n.tag != blot_direct_types::Tag.view {
        return blot_direct_types::Tag.unit, false;
    }
    let elem = g.types.node(n.a).tag;
    if isScalarTag(elem) { return elem, true; }
    return blot_direct_types::Tag.unit, false;
}
fn lowerInEnv(g: Generator&, m: const Module&, tid: TId, env: const Env&) -> Ty, bool {
    let lowered, err = g.types.lower(m, tid, env);
    if err != blot_direct_types::Error.none { g.dropFailure(); return 0, false; }
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
    want_tag: blot_direct_types::Tag,
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
            return rn.tag == blot_check_core::Tag.constant;
        },
        scalar => {
            if n.c != 0 { return false; }
            if want_tag != blot_direct_types::Tag.u32_ { return false; }
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
            blot_direct_relocations::unpatchableOperand(m.unit, id);
            return constLocal(g, f, n.a), blot_direct_types::Error.none;
        },
        reference => {
            let ref = m.reference(id);
            if ref.unit == 0 || ref.unit == m.unit {
                let vidx = findVecLocal(plan, m.unit, ref.binding);
                if vidx >= 0 {
                    assert(plan.locals[vidx].scalar_local != 0xffffffff);
                    return plan.locals[vidx].scalar_local, blot_direct_types::Error.none;
                }
                if m.unit == f.unit {
                    let bound, present = bindGet(g, f, ref.binding);
                    if present { return w(g, bound, 0), blot_direct_types::Error.none; }
                }
            }
            let target = g.resolve(m, ref);
            let tm .= g.units[target.unit - 1];
            let body .= tm.body(target.binding);
            assert(body);
            g.recordInlined(target.unit, target.binding);
            blot_direct_relocations::unpatchableOperand(target.unit, body.root);
            return constLocal(g, f, tm.node(body.root).a), blot_direct_types::Error.none;
        },
        scalar => {
            let lhs, lerr = emitInvariantU32(g, f, plan, m, env, n.a);
            if lerr != blot_direct_types::Error.none { return 0, lerr; }
            var rhs: u32 = 0;
            if n.b != 0 {
                let r, rerr = emitInvariantU32(g, f, plan, m, env, n.b);
                if rerr != blot_direct_types::Error.none { return 0, rerr; }
                rhs = r;
            }
            lget(g, lhs);
            if n.b != 0 { lget(g, rhs); }
            let serr = scalarOp(g, f, n.op, blot_direct_types::u32_, id, false);
            if serr != blot_direct_types::Error.none { return 0, serr; }
            let dst = local32(g, f);
            lset(g, dst);
            return dst, blot_direct_types::Error.none;
        },
        _ => { return 0, g.fail(m, id, "unexpected invariant scalar expression in SIMD spark"); },
    }
}

fn isIterBindingRef(plan: const SparkVecPlan&, m: const Module&, id: u32) -> bool {
    if id == 0 || plan.iter_binding == 0 || m.unit != plan.spark_unit { return false; }
    let n = m.node(id);
    if n.tag != blot_check_core::Tag.reference { return false; }
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
    if (n.tag == blot_check_core::Tag.scalar || n.tag == blot_check_core::Tag.associated) && n.op == blot_check_core::Op.add {
        let ty, ok = lowerInEnv(g, m, m.typeOf(idx_id), env);
        if !ok || tagOf(g, ty) != blot_direct_types::Tag.u32_ { return false, 0; }
        if isIterBindingRef(plan, m, n.a) && isInvariantScalarExpr(g, f, plan, m, env, n.b, blot_direct_types::Tag.u32_, 0) {
            return true, n.b;
        }
        if isIterBindingRef(plan, m, n.b) && isInvariantScalarExpr(g, f, plan, m, env, n.a, blot_direct_types::Tag.u32_, 0) {
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
) -> Ty, blot_direct_types::Tag, bool {
    if m.unit != f.unit || arr_id == 0 { return 0, blot_direct_types::Tag.unit, false; }
    let n = m.node(arr_id);
    if n.tag != blot_check_core::Tag.reference { return 0, blot_direct_types::Tag.unit, false; }
    let ref = m.reference(arr_id);
    if ref.unit == 0 || ref.unit == m.unit {
        if findVecLocal(plan, m.unit, ref.binding) >= 0 { return 0, blot_direct_types::Tag.unit, false; }
        let bound, present = bindGet(g, f, ref.binding);
        if present {
            let _, is_cell = withCellType(g, f, ref.binding);
            if is_cell { return 0, blot_direct_types::Tag.unit, false; }
            let etag, ok = isContiguousScalarContainer(g, bound.ty);
            if ok { return bound.ty, etag, true; }
            return 0, blot_direct_types::Tag.unit, false;
        }
    }
    let target = g.resolve(m, ref);
    if !g.hasUnit(target.unit) { return 0, blot_direct_types::Tag.unit, false; }
    let tm .= g.units[target.unit - 1];
    let body .= tm.body(target.binding);
    if !body || body.is_function { return 0, blot_direct_types::Tag.unit, false; }
    if requiresEvidence(g, target) { return 0, blot_direct_types::Tag.unit, false; }
    let ty, ok = lowerInEnv(g, m, m.typeOf(arr_id), env);
    if !ok { return 0, blot_direct_types::Tag.unit, false; }
    let tag = tagOf(g, ty);
    if tag != blot_direct_types::Tag.array {
        return 0, blot_direct_types::Tag.unit, false;
    }
    let etag, eok = isContiguousScalarContainer(g, ty);
    if !eok { return 0, blot_direct_types::Tag.unit, false; }
    return ty, etag, true;
}

// Resolves a scalar machine op for a Tag.scalar / Tag.associated node without emitting code.
fn resolveSparkScalarOp(
    g: Generator&,
    m: const Module&,
    op_: blot_check_core::Op,
    member: u32,
    use_dispatch: bool,
    operand_ty: Ty,
) -> blot_check_core::Op, BindingRef, bool {
    var no_ref = BindingRef { 0, 0 };
    if !use_dispatch { return op_, no_ref, true; }
    let identity, has_identity = g.receiverIdentity(operand_ty);
    if !has_identity { return op_, no_ref, true; }
    var operator = blot_check_types::Operator.none;
    if member == 0 {
        let found, has_op = operatorOf(op_);
        if !has_op { return op_, no_ref, true; }
        operator = found;
    }
    let target, has_target = g.dispatchTarget(m, identity, member, operator);
    if !has_target {
        if member == 0 { return op_, no_ref, true; }
        return blot_check_core::Op.none, no_ref, false;
    }
    if !g.hasUnit(target.unit) { return blot_check_core::Op.none, no_ref, false; }
    let defining .= g.units[target.unit - 1];
    let alias, has_alias = primitiveAlias(defining, target.binding);
    if has_alias {
        let prim = defining.primitive(alias);
        if prim.kind == blot_check_core::PrimitiveKind.scalar && prim.op != blot_check_core::Op.none {
            return prim.op, target, true;
        }
        return blot_check_core::Op.none, no_ref, false;
    }
    // Non-primitive associated function (e.g. U32.bit_not, U32.ne, F32.min): handled via call inlining!
    return blot_check_core::Op.none, target, true;
}

fn supportedSimdMachineOp(op_: blot_check_core::Op, operand_tag: blot_direct_types::Tag) -> bool {
    if operand_tag == blot_direct_types::Tag.f32_ {
        match op_ {
            add, sub, mul, div, neg, abs, sqrt, floor, ceil, trunc,
            equal, not_equal, less, less_equal, greater, greater_equal,
            min, max, bits, convert_f32_u32, convert_f32_i32 => { return true; },
            _ => { return false; },
        }
    }
    if operand_tag == blot_direct_types::Tag.u32_ {
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
    if operand_tag == blot_direct_types::Tag.boolean {
        match op_ {
            not_, equal, not_equal, less, less_equal, greater, greater_equal => { return true; },
            _ => { return false; },
        }
    }
    return false;
}

fn isShiftOp(op_: blot_check_core::Op) -> bool {
    return op_ == blot_check_core::Op.shift_left || op_ == blot_check_core::Op.shift_right || op_ == blot_check_core::Op.shift_right_signed;
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
        if tm.node(body.root).tag != blot_check_core::Tag.reference { return cur; }
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
        if tm.node(body.root).tag != blot_check_core::Tag.reference { return cur; }
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
        if prim.kind != blot_check_core::PrimitiveKind.scalar || prim.arity != arg_ids.len || arg_ids.len == 0 || arg_ids.len > 2 {
            return false;
        }
        let a0_ty, ok0 = lowerInEnv(g, m, m.typeOf(arg_ids[0]), env);
        if !ok0 { return false; }
        let a0_tag = tagOf(g, a0_ty);
        if !supportedSimdMachineOp(prim.op, a0_tag) { return false; }
        if a0_tag == blot_direct_types::Tag.f32_ && isCanonicalF32Op(prim.op) { plan.uses_f32_canon = true; }
        if !checkVecExpr(g, f, plan, m, env, arg_ids[0], inline_depth, depth + 1, false) { return false; }
        if arg_ids.len == 2 {
            if isShiftOp(prim.op) {
                return isInvariantScalarExpr(g, f, plan, m, env, arg_ids[1], blot_direct_types::Tag.u32_, 0);
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
        if !aok || !isScalarTag(tagOf(g, aty)) { return false; }
        arg_tys[at] = aty;
        arg_inv[at] = isInvariantScalarExpr(g, f, plan, m, env, arg_ids[at], tagOf(g, aty), 0);
        if !checkVecExpr(g, f, plan, m, env, arg_ids[at], inline_depth, depth + 1, false) { return false; }
    }
    var curried_ty = result_ty;
    var at = arg_ids.len;
    while at > 0 {
        at -= 1;
        let wrapped, werr = g.types.function(arg_tys[at], curried_ty);
        if werr != blot_direct_types::Error.none { return false; }
        curried_ty = wrapped;
    }
    var sub_env = Env {};
    g.types.match_(tm, tm.binding(body.binding).ty, curried_ty, sub_env);
    if body.scheme.obligations.len != 0 {
        let solved = g.solveObligationsPublic(tm, body.scheme.obligations, sub_env);
        if solved != blot_direct_types::Error.none { g.dropFailure(); return false; }
    }
    for v in tm.types.list(body.scheme.variables) {
        let _, verr = g.types.lower(tm, v, sub_env);
        if verr != blot_direct_types::Error.none { g.dropFailure(); return false; }
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
            is_mask: ptag == blot_direct_types::Tag.boolean,
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
            return ok && isScalarTag(tagOf(g, ty));
        },
        reference => {
            let ty, ok = lowerInEnv(g, m, m.typeOf(id), env);
            if !ok || !isScalarTag(tagOf(g, ty)) { return false; }
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
            return tm.node(body.root).tag == blot_check_core::Tag.constant;
        },
        scalar => {
            let res_ty, rok = lowerInEnv(g, m, m.typeOf(id), env);
            if !rok || !isScalarTag(tagOf(g, res_ty)) { return false; }
            let a_ty, aok = lowerInEnv(g, m, m.typeOf(n.a), env);
            if !aok || !isScalarTag(tagOf(g, a_ty)) { return false; }
            let a_tag = tagOf(g, a_ty);
            let machine, disp_target, resolved = resolveSparkScalarOp(g, m, n.op, 0, n.c == 1, a_ty);
            if !resolved { return false; }
            if machine == blot_check_core::Op.none {
                if disp_target.binding == 0 { return false; }
                if n.b != 0 {
                    var pair: u32[2] = [n.a, n.b];
                    return checkVecCall(g, f, plan, m, env, disp_target, pair[..], res_ty, inline_depth, depth + 1);
                }
                var one: u32[1] = [n.a];
                return checkVecCall(g, f, plan, m, env, disp_target, one[..], res_ty, inline_depth, depth + 1);
            }
            if !supportedSimdMachineOp(machine, a_tag) { return false; }
            if a_tag == blot_direct_types::Tag.f32_ && isCanonicalF32Op(machine) { plan.uses_f32_canon = true; }
            if !checkVecExpr(g, f, plan, m, env, n.a, inline_depth, depth + 1, false) { return false; }
            if n.b != 0 {
                if isShiftOp(machine) {
                    return isInvariantScalarExpr(g, f, plan, m, env, n.b, blot_direct_types::Tag.u32_, 0);
                }
                let b_ty, bok = lowerInEnv(g, m, m.typeOf(n.b), env);
                if !bok || tagOf(g, b_ty) != a_tag { return false; }
                if !checkVecExpr(g, f, plan, m, env, n.b, inline_depth, depth + 1, false) { return false; }
            }
            return true;
        },
        associated => {
            let res_ty, rok = lowerInEnv(g, m, m.typeOf(id), env);
            if !rok || !isScalarTag(tagOf(g, res_ty)) { return false; }
            let a_ty, aok = lowerInEnv(g, m, m.typeOf(n.a), env);
            if !aok || !isScalarTag(tagOf(g, a_ty)) { return false; }
            let a_tag = tagOf(g, a_ty);
            let machine, disp_target, resolved = resolveSparkScalarOp(g, m, n.op, n.c, true, a_ty);
            if !resolved { return false; }
            if machine == blot_check_core::Op.none {
                if disp_target.binding == 0 { return false; }
                if n.b != 0 {
                    var pair: u32[2] = [n.a, n.b];
                    return checkVecCall(g, f, plan, m, env, disp_target, pair[..], res_ty, inline_depth, depth + 1);
                }
                var one: u32[1] = [n.a];
                return checkVecCall(g, f, plan, m, env, disp_target, one[..], res_ty, inline_depth, depth + 1);
            }
            if !supportedSimdMachineOp(machine, a_tag) { return false; }
            if a_tag == blot_direct_types::Tag.f32_ && isCanonicalF32Op(machine) { plan.uses_f32_canon = true; }
            if !checkVecExpr(g, f, plan, m, env, n.a, inline_depth, depth + 1, false) { return false; }
            if n.b != 0 {
                if isShiftOp(machine) {
                    return isInvariantScalarExpr(g, f, plan, m, env, n.b, blot_direct_types::Tag.u32_, 0);
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
            if !rok || !isScalarTag(tagOf(g, res_ty)) { return false; }
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
                if cn.tag == blot_check_core::Tag.bind && cn.c == 0 && m.binding(cn.a).scheme.variables.len == 0 {
                    let bty, bok = lowerInEnv(g, m, m.typeOf(cn.b), env);
                    if !bok || !isScalarTag(tagOf(g, bty)) || plan.locals_len >= 64 { ok = false; break; }
                    if !checkVecExpr(g, f, plan, m, env, cn.b, inline_depth, depth + 1, false) { ok = false; break; }
                    let btag = tagOf(g, bty);
                    let inv = isInvariantScalarExpr(g, f, plan, m, env, cn.b, btag, 0);
                    plan.locals[plan.locals_len] = SparkVecLocal {
                        unit: m.unit,
                        binding: cn.a,
                        tag: btag,
                        is_mask: btag == blot_direct_types::Tag.boolean,
                        invariant: inv,
                    };
                    plan.locals_len += 1;
                } else if cn.tag == blot_check_core::Tag.pattern_bind && cn.c == 0 {
                    let pat = m.pattern(cn.a);
                    if pat.tag != blot_check_core::PatternTag.bind && pat.tag != blot_check_core::PatternTag.wildcard { ok = false; break; }
                    let bty, bok = lowerInEnv(g, m, m.typeOf(cn.b), env);
                    if !bok || !isScalarTag(tagOf(g, bty)) || plan.locals_len >= 64 { ok = false; break; }
                    if !checkVecExpr(g, f, plan, m, env, cn.b, inline_depth, depth + 1, false) { ok = false; break; }
                    if pat.tag == blot_check_core::PatternTag.bind {
                        let btag = tagOf(g, bty);
                        let inv = isInvariantScalarExpr(g, f, plan, m, env, cn.b, btag, 0);
                        plan.locals[plan.locals_len] = SparkVecLocal {
                            unit: m.unit,
                            binding: pat.a,
                            tag: btag,
                            is_mask: btag == blot_direct_types::Tag.boolean,
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
                let allow_tail_ret = allow_return || n.tag == blot_check_core::Tag.block_;
                ok = checkVecExpr(g, f, plan, m, env, last, inline_depth, depth + 1, allow_tail_ret);
            }
            plan.locals_len = mark;
            return ok;
        },
        call => {
            let info = m.call(id);
            let res_ty, rok = lowerInEnv(g, m, m.typeOf(id), env);
            if !rok || !isScalarTag(tagOf(g, res_ty)) { return false; }
            let target = g.resolve(m, info.target);
            return checkVecCall(g, f, plan, m, env, target, info.arguments, res_ty, inline_depth, depth + 1);
        },
        project => {
            let proj = m.projection(n.b);
            if proj.field == 0 || m.projectionVariants(n.b).len != 0 { return false; }
            let res_ty, rok = lowerInEnv(g, m, m.typeOf(id), env);
            if !rok || !isScalarTag(tagOf(g, res_ty)) { return false; }
            let recv_ty, rec_ok = lowerInEnv(g, m, m.typeOf(n.a), env);
            if !rec_ok || !isScalarTag(tagOf(g, recv_ty)) { return false; }
            let identity, has_ident = g.receiverIdentity(recv_ty);
            if !has_ident { return false; }
            let target, has_target = g.dispatchTarget(m, identity, proj.field, blot_check_types::Operator.none);
            if !has_target { return false; }
            var one: u32[1] = [n.a];
            return checkVecCall(g, f, plan, m, env, target, one[..], res_ty, inline_depth, depth + 1);
        },
        array_op, storage => {
            // Range-affine contiguous stream loads ONLY (`arr[i]` or `arr[offset + i]`
            // inside a range generator). Array-generator gathers fall back to scalar!
            if !plan.is_range || m.unit != plan.spark_unit { return false; }
            var is_read = false;
            if n.tag == blot_check_core::Tag.array_op {
                is_read = m.arrayOperation(id) == blot_backend_collection_ops::Op.get;
            } else {
                let sop, serr = blot_check_storage_ops::opFromCode(n.c);
                is_read = serr == blot_error::Error.none && sop == blot_check_storage_ops::Op.read;
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
    op_: blot_check_core::Op,
    operand_tag: blot_direct_types::Tag,
    elide_nan: bool,
    nan_vlocal: u32,
) {
    if operand_tag == blot_direct_types::Tag.f32_ {
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
            convert_f32_u32 => { simdOp(g, SIMD_i32x4_trunc_sat_f32x4_u); },
            convert_f32_i32 => { simdOp(g, SIMD_i32x4_trunc_sat_f32x4_s); },
            equal => { simdOp(g, SIMD_f32x4_eq); },
            not_equal => { simdOp(g, SIMD_f32x4_ne); },
            less => { simdOp(g, SIMD_f32x4_lt); },
            less_equal => { simdOp(g, SIMD_f32x4_le); },
            greater => { simdOp(g, SIMD_f32x4_gt); },
            greater_equal => { simdOp(g, SIMD_f32x4_ge); },
            min, max => {
                // Match prelude `if a < b then a else b` (NaN and -0/+0 exact!).
                let rb = local(g, f, VT_v128);
                let la = local(g, f, VT_v128);
                lset(g, rb);
                lset(g, la);
                lget(g, la);
                lget(g, rb);
                lget(g, la);
                lget(g, rb);
                if op_ == blot_check_core::Op.min { simdOp(g, SIMD_f32x4_lt); } else { simdOp(g, SIMD_f32x4_gt); }
                simdOp(g, SIMD_v128_bitselect);
            },
            _ => { abort("unsupported F32 SIMD op"); },
        }
        return;
    }
    if operand_tag == blot_direct_types::Tag.u32_ {
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
                if op_ == blot_check_core::Op.min { simdOp(g, SIMD_i32x4_lt_u); } else { simdOp(g, SIMD_i32x4_gt_u); }
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
        let child_elide = a0_tag == blot_direct_types::Tag.f32_ && isCanonicalF32Consumer(prim.op);
        let err0 = emitVecExpr(g, f, plan, m, env, arg_ids[0], child_elide);
        if err0 != blot_direct_types::Error.none { return err0; }
        if arg_ids.len == 2 {
            if isShiftOp(prim.op) {
                let s_loc, serr = emitInvariantU32(g, f, plan, m, env, arg_ids[1]);
                if serr != blot_direct_types::Error.none { return serr; }
                lget(g, s_loc);
            } else {
                let err1 = emitVecExpr(g, f, plan, m, env, arg_ids[1], child_elide);
                if err1 != blot_direct_types::Error.none { return err1; }
            }
        }
        emitSimdMachineOp(g, f, prim.op, a0_tag, elide_nan, plan.nan_vlocal);
        return blot_direct_types::Error.none;
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
        if aerr != blot_direct_types::Error.none { return aerr; }
        let vl = local(g, f, VT_v128);
        lset(g, vl);
        arg_vlocals[at] = vl;
        if atag == blot_direct_types::Tag.u32_ && isInvariantScalarExpr(g, f, plan, m, env, arg_ids[at], blot_direct_types::Tag.u32_, 0) {
            let sl, serr = emitInvariantU32(g, f, plan, m, env, arg_ids[at]);
            if serr != blot_direct_types::Error.none { return serr; }
            arg_inv[at] = true;
            arg_slocals[at] = sl;
        }
    }
    var curried_ty = result_ty;
    var at = arg_ids.len;
    while at > 0 {
        at -= 1;
        let wrapped, werr = g.types.function(arg_tys[at], curried_ty);
        if werr != blot_direct_types::Error.none { return werr; }
        curried_ty = wrapped;
    }
    var sub_env = Env {};
    g.types.match_(tm, tm.binding(body.binding).ty, curried_ty, sub_env);
    if body.scheme.obligations.len != 0 {
        let solved = g.solveObligationsPublic(tm, body.scheme.obligations, sub_env);
        if solved != blot_direct_types::Error.none { return solved; }
    }
    let mark = plan.locals_len;
    for param, pi in params {
        let ptag = tagOf(g, arg_tys[pi]);
        plan.locals[plan.locals_len] = SparkVecLocal {
            unit: tm.unit,
            binding: param.binding,
            tag: ptag,
            vlocal: arg_vlocals[pi],
            is_mask: ptag == blot_direct_types::Tag.boolean,
            invariant: arg_inv[pi],
            scalar_local: arg_slocals[pi],
        };
        plan.locals_len += 1;
    }
    let err = emitVecExpr(g, f, plan, tm, sub_env, body.root, elide_nan);
    plan.locals_len = mark;
    return err;
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
            blot_direct_relocations::unpatchableOperand(m.unit, id);
            let ty, _ = lowerInEnv(g, m, m.typeOf(id), env);
            if tagOf(g, ty) == blot_direct_types::Tag.boolean {
                if n.a != 0 { v128Const4(g, 0xffffffff); } else { v128Const4(g, 0); }
            } else {
                v128Const4(g, n.a);
            }
            return blot_direct_types::Error.none;
        },
        reference => {
            let ref = m.reference(id);
            if ref.unit == 0 || ref.unit == m.unit {
                let vidx = findVecLocal(plan, m.unit, ref.binding);
                if vidx >= 0 {
                    lget(g, plan.locals[vidx].vlocal);
                    return blot_direct_types::Error.none;
                }
                if m.unit == f.unit {
                    let hidx = findHoistedScalar(plan, m.unit, ref.binding);
                    if hidx >= 0 && plan.hoisted[hidx].vlocal != 0xffffffff {
                        lget(g, plan.hoisted[hidx].vlocal);
                        return blot_direct_types::Error.none;
                    }
                    let bound, present = bindGet(g, f, ref.binding);
                    if present {
                        let btag = tagOf(g, bound.ty);
                        if btag == blot_direct_types::Tag.boolean {
                            i32Const(g, 0);
                            lget(g, w(g, bound, 0));
                            op(g, OP_i32_sub);
                            simdOp(g, SIMD_i32x4_splat);
                        } else if btag == blot_direct_types::Tag.f32_ {
                            lget(g, w(g, bound, 0));
                            simdOp(g, SIMD_f32x4_splat);
                        } else {
                            lget(g, w(g, bound, 0));
                            simdOp(g, SIMD_i32x4_splat);
                        }
                        return blot_direct_types::Error.none;
                    }
                }
            }
            let target = g.resolve(m, ref);
            let tm .= g.units[target.unit - 1];
            let body .= tm.body(target.binding);
            assert(body);
            g.recordInlined(target.unit, target.binding);
            blot_direct_relocations::unpatchableOperand(target.unit, body.root);
            let rn = tm.node(body.root);
            let ty, _ = lowerInEnv(g, m, m.typeOf(id), env);
            if tagOf(g, ty) == blot_direct_types::Tag.boolean {
                if rn.a != 0 { v128Const4(g, 0xffffffff); } else { v128Const4(g, 0); }
            } else {
                v128Const4(g, rn.a);
            }
            return blot_direct_types::Error.none;
        },
        scalar, associated => {
            let res_ty, _ = lowerInEnv(g, m, m.typeOf(id), env);
            let a_ty, _ = lowerInEnv(g, m, m.typeOf(n.a), env);
            let a_tag = tagOf(g, a_ty);
            let is_assoc = n.tag == blot_check_core::Tag.associated;
            let use_disp = is_assoc || n.c == 1;
            var member: u32 = 0;
            if is_assoc { member = n.c; }
            let machine, disp_target, _ = resolveSparkScalarOp(g, m, n.op, member, use_disp, a_ty);
            if machine == blot_check_core::Op.none {
                if n.b != 0 {
                    var pair: u32[2] = [n.a, n.b];
                    return emitVecCall(g, f, plan, m, env, disp_target, pair[..], res_ty, elide_nan);
                }
                var one: u32[1] = [n.a];
                return emitVecCall(g, f, plan, m, env, disp_target, one[..], res_ty, elide_nan);
            }
            if disp_target.binding != 0 { g.recordInlined(disp_target.unit, disp_target.binding); }
            let child_elide = a_tag == blot_direct_types::Tag.f32_ && isCanonicalF32Consumer(machine);
            let lerr = emitVecExpr(g, f, plan, m, env, n.a, child_elide);
            if lerr != blot_direct_types::Error.none { return lerr; }
            if n.b != 0 {
                if isShiftOp(machine) {
                    let s_loc, serr = emitInvariantU32(g, f, plan, m, env, n.b);
                    if serr != blot_direct_types::Error.none { return serr; }
                    lget(g, s_loc);
                } else {
                    let rerr = emitVecExpr(g, f, plan, m, env, n.b, child_elide);
                    if rerr != blot_direct_types::Error.none { return rerr; }
                }
            }
            emitSimdMachineOp(g, f, machine, a_tag, elide_nan, plan.nan_vlocal);
            return blot_direct_types::Error.none;
        },
        logical => {
            let lerr = emitVecExpr(g, f, plan, m, env, n.a, false);
            if lerr != blot_direct_types::Error.none { return lerr; }
            let rerr = emitVecExpr(g, f, plan, m, env, n.b, false);
            if rerr != blot_direct_types::Error.none { return rerr; }
            if n.op == blot_check_core::Op.and_ { simdOp(g, SIMD_v128_and); } else { simdOp(g, SIMD_v128_or); }
            return blot_direct_types::Error.none;
        },
        if_value => {
            // Never elide NaN canonicalization across `if`/`select`.
            let terr = emitVecExpr(g, f, plan, m, env, n.b, false);
            if terr != blot_direct_types::Error.none { return terr; }
            let eerr = emitVecExpr(g, f, plan, m, env, n.c, false);
            if eerr != blot_direct_types::Error.none { return eerr; }
            let cerr = emitVecExpr(g, f, plan, m, env, n.a, false);
            if cerr != blot_direct_types::Error.none { return cerr; }
            simdOp(g, SIMD_v128_bitselect);
            return blot_direct_types::Error.none;
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
                if cn.tag == blot_check_core::Tag.bind {
                    let bty, _ = lowerInEnv(g, m, m.typeOf(cn.b), env);
                    let btag = tagOf(g, bty);
                    // Bindings may be used by neg/abs/if/store -> never elide NaN.
                    let berr = emitVecExpr(g, f, plan, m, env, cn.b, false);
                    if berr != blot_direct_types::Error.none { plan.locals_len = mark; return berr; }
                    let vl = local(g, f, VT_v128);
                    lset(g, vl);
                    var inv = false;
                    var sl: u32 = 0xffffffff;
                    if btag == blot_direct_types::Tag.u32_ && isInvariantScalarExpr(g, f, plan, m, env, cn.b, blot_direct_types::Tag.u32_, 0) {
                        let sloc, serr = emitInvariantU32(g, f, plan, m, env, cn.b);
                        if serr != blot_direct_types::Error.none { plan.locals_len = mark; return serr; }
                        inv = true;
                        sl = sloc;
                    }
                    plan.locals[plan.locals_len] = SparkVecLocal {
                        unit: m.unit,
                        binding: cn.a,
                        tag: btag,
                        vlocal: vl,
                        is_mask: btag == blot_direct_types::Tag.boolean,
                        invariant: inv,
                        scalar_local: sl,
                    };
                    plan.locals_len += 1;
                } else {
                    let pat = m.pattern(cn.a);
                    let bty, _ = lowerInEnv(g, m, m.typeOf(cn.b), env);
                    let btag = tagOf(g, bty);
                    let berr = emitVecExpr(g, f, plan, m, env, cn.b, false);
                    if berr != blot_direct_types::Error.none { plan.locals_len = mark; return berr; }
                    if pat.tag == blot_check_core::PatternTag.bind {
                        let vl = local(g, f, VT_v128);
                        lset(g, vl);
                        var inv = false;
                        var sl: u32 = 0xffffffff;
                        if btag == blot_direct_types::Tag.u32_ && isInvariantScalarExpr(g, f, plan, m, env, cn.b, blot_direct_types::Tag.u32_, 0) {
                            let sloc, serr = emitInvariantU32(g, f, plan, m, env, cn.b);
                            if serr != blot_direct_types::Error.none { plan.locals_len = mark; return serr; }
                            inv = true;
                            sl = sloc;
                        }
                        plan.locals[plan.locals_len] = SparkVecLocal {
                            unit: m.unit,
                            binding: pat.a,
                            tag: btag,
                            vlocal: vl,
                            is_mask: btag == blot_direct_types::Tag.boolean,
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
            let target, _ = g.dispatchTarget(m, identity, proj.field, blot_check_types::Operator.none);
            var one: u32[1] = [n.a];
            return emitVecCall(g, f, plan, m, env, target, one[..], res_ty, elide_nan);
        },
        array_op, storage => {
            let sidx = findAffineStream(plan, m.unit, id);
            assert(sidx >= 0);
            let st = plan.streams[sidx];
            if st.elem_tag == blot_direct_types::Tag.boolean {
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
            return blot_direct_types::Error.none;
        },
        _ => { return g.fail(m, id, "unexpected expression during SIMD spark emission"); },
    }
}

// Resolves the contiguous backing base pointer and logical element length for
// a scalar container (`array`, `grow`, `resize`, or `view`).
fn containerBaseAndLen(g: Generator&, f: Fn&, val: Val, id: u32) -> u32, u32, Error {
    let tag = tagOf(g, val.ty);
    if tag == blot_direct_types::Tag.view {
        let elem_tag = tagOf(g, g.types.node(val.ty).a);
        let backing_base = baseOf(g, f, val);
        let ptr = local32(g, f);
        lget(g, backing_base);
        lget(g, w(g, val, 2));
        if elem_tag != blot_direct_types::Tag.boolean {
            i32Const(g, 2);
            op(g, OP_i32_shl);
        }
        op(g, OP_i32_add);
        lset(g, ptr);
        return ptr, w(g, val, 3), blot_direct_types::Error.none;
    }
    if tag == blot_direct_types::Tag.array {
        let base, len = ensureCheckedArray(g, f, val);
        return base, len, blot_direct_types::Error.none;
    }
    let len, lerr = lengthOf(g, f, val, id);
    if lerr != blot_direct_types::Error.none { return 0, 0, lerr; }
    let base = baseOf(g, f, val);
    return base, len, blot_direct_types::Error.none;
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
    if !isScalarTag(out_tag) { return false, 0, blot_direct_types::Error.none; }

    var iter_tag = blot_direct_types::Tag.u32_;
    if !info.is_range {
        let src_elem_tag, src_ok = isContiguousScalarContainer(g, source_val.ty);
        if !src_ok { return false, 0, blot_direct_types::Error.none; }
        iter_tag = src_elem_tag;
    }

    var iter_binding: u32 = 0;
    if info.pattern != 0 {
        let pat = m.pattern(info.pattern);
        if pat.tag == blot_check_core::PatternTag.bind {
            iter_binding = pat.a;
        } else if pat.tag != blot_check_core::PatternTag.wildcard {
            return false, 0, blot_direct_types::Error.none;
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
            is_mask: iter_tag == blot_direct_types::Tag.boolean,
            invariant: false,
        };
        plan.locals_len = 1;
    }

    if !checkVecExpr(g, f, plan, m, f.env, info.body, 0, 0, false) {
        return false, 0, blot_direct_types::Error.none;
    }

    // Vectorizable! Emit 4-wide SIMD loop + pre-loop range-affine stream guards.
    g.s.sparks_vectorized += 1;

    var src_base: u32 = 0;
    if !info.is_range {
        let sb, _, sberr = containerBaseAndLen(g, f, source_val, id);
        if sberr != blot_direct_types::Error.none { return false, 0, sberr; }
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
    let start_is_zero = info.is_range && g.units[f.unit - 1].node(info.source).tag == blot_check_core::Tag.constant && g.units[f.unit - 1].node(info.source).a == 0;
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
            if aerr != blot_direct_types::Error.none { return false, 0, aerr; }
            let arr_base, arr_len, blerr = containerBaseAndLen(g, f, arr_val, st.node_id);
            if blerr != blot_direct_types::Error.none { return false, 0, blerr; }

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
                    if oerr != blot_direct_types::Error.none { return false, 0, oerr; }
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
                if st.elem_tag != blot_direct_types::Tag.boolean {
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
        if h.tag == blot_direct_types::Tag.boolean {
            i32Const(g, 0);
            lget(g, h.scalar_local);
            op(g, OP_i32_sub);
            simdOp(g, SIMD_i32x4_splat);
        } else if h.tag == blot_direct_types::Tag.f32_ {
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
            if orig_ptrs[si] == out_base && (plan.streams[si].elem_tag == blot_direct_types::Tag.boolean) == (out_tag == blot_direct_types::Tag.boolean) {
                reused = cur_out;
            } else {
                for sj in 0..si {
                    if orig_ptrs[sj] == orig_ptrs[si] && (plan.streams[sj].elem_tag == blot_direct_types::Tag.boolean) == (plan.streams[si].elem_tag == blot_direct_types::Tag.boolean) {
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
        if out_tag == blot_direct_types::Tag.boolean { lget(g, index); } else { lget(g, byte_off); }
        op(g, OP_i32_add);
        lset(g, cur_out);

        if !info.is_range && need_iter_vlocal {
            lget(g, src_base);
            if iter_tag == blot_direct_types::Tag.boolean { lget(g, index); } else { lget(g, byte_off); }
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
                if plan.streams[si].elem_tag == blot_direct_types::Tag.boolean { lget(g, index); } else { lget(g, byte_off); }
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
                if iter_tag == blot_direct_types::Tag.boolean {
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
            if step_err != blot_direct_types::Error.none { return false, 0, step_err; }
            if out_tag == blot_direct_types::Tag.boolean {
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
        if iter_tag == blot_direct_types::Tag.boolean {
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
    if out_tag == blot_direct_types::Tag.boolean {
        lget(g, index);
    } else {
        lget(g, byte_off);
    }
    op(g, OP_i32_add);

    let body_err = emitVecExpr(g, f, plan, g.units[f.unit - 1], f.env, info.body, false);
    if body_err != blot_direct_types::Error.none { return false, 0, body_err; }

    if out_tag == blot_direct_types::Tag.boolean {
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

    return true, index, blot_direct_types::Error.none;
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
    info: blot_check_core::LoopInfo,
    carry_in_place: const bool[64]&,
    index: u32,
    end_local: u32,
) -> Error {
    if g.runtime_().has_fork { return blot_direct_types::Error.none; }
    if info.kind != blot_check_core::LoopKind.range || info.pattern == 0 || info.body == 0 {
        return blot_direct_types::Error.none;
    }

    var iter_binding: u32 = 0;
    var dst_b: u32 = 0;
    var dst_val = neverVal();
    var out_tag = blot_direct_types::Tag.unit;
    var dst_off_id: u32 = 0;
    var rhs_id: u32 = 0;
    var lead_bind_ids: u32[8] = [0; 8];
    var lead_bind_exprs: u32[8] = [0; 8];
    var lead_bind_tags: blot_direct_types::Tag[8] = [blot_direct_types::Tag.unit; 8];
    var lead_bind_len: i64 = 0;
    var plan = SparkVecPlan {};
    var matched = false;

    {
        let m .= g.units[f.unit - 1];
        let pat = m.pattern(info.pattern);
        if pat.tag != blot_check_core::PatternTag.bind { return blot_direct_types::Error.none; }
        iter_binding = pat.a;

        let carries = m.loopCarries(loop_id);
        if carries.len > 64 { return blot_direct_types::Error.none; }
        for ci in 0..carries.len {
            if !carry_in_place[ci] { return blot_direct_types::Error.none; }
        }

        // Collect flattened top-level statements of info.body (up to 16).
        var stmts: u32[16] = [0; 16];
        var stmts_len: i64 = 0;
        let bn = m.node(info.body);
        if bn.tag == blot_check_core::Tag.suite || bn.tag == blot_check_core::Tag.block_ {
            let ch_len = m.children(info.body).len;
            if ch_len == 0 || ch_len > 16 { return blot_direct_types::Error.none; }
            for si in 0..ch_len {
                stmts[si] = m.children(info.body)[si];
            }
            stmts_len = ch_len;
        } else {
            stmts[0] = info.body;
            stmts_len = 1;
        }

        // Final statement must be an in-place indexed update (or `bind` wrapping one).
        let last_id = stmts[stmts_len - 1];
        let last_n = m.node(last_id);
        var update_id: u32 = 0;
        if last_n.tag == blot_check_core::Tag.update {
            update_id = last_id;
        } else if last_n.tag == blot_check_core::Tag.bind && last_n.c < 2 && m.node(last_n.b).tag == blot_check_core::Tag.update {
            update_id = last_n.b;
        } else {
            return blot_direct_types::Error.none;
        }

        let uinfo = m.updateInfo(update_id);
        let sels = m.updateSelectors(update_id);
        if sels.len != 1 || sels[0].kind != blot_check_core::UpdateKind.index {
            return blot_direct_types::Error.none;
        }
        if uinfo.self_binding != 0 && uses(g, f, uinfo.self_binding) != 0 {
            return blot_direct_types::Error.none;
        }
        dst_b = localRef(m, uinfo.root);
        if dst_b == 0 { return blot_direct_types::Error.none; }
        let _, dst_is_cell = withCellType(g, f, dst_b);
        if dst_is_cell { return blot_direct_types::Error.none; }
        let dv, dok = bindGet(g, f, dst_b);
        if !dok || tagOf(g, dv.ty) != blot_direct_types::Tag.array {
            return blot_direct_types::Error.none;
        }
        dst_val = dv;
        out_tag = tagOf(g, g.types.node(dst_val.ty).a);
        if out_tag != blot_direct_types::Tag.f32_ && out_tag != blot_direct_types::Tag.u32_ {
            return blot_direct_types::Error.none;
        }

        plan = SparkVecPlan {
            spark_unit: m.unit,
            is_range: true,
            iter_binding: iter_binding,
            iter_tag: blot_direct_types::Tag.u32_,
            out_tag: out_tag,
        };
        plan.locals[0] = SparkVecLocal {
            unit: m.unit,
            binding: iter_binding,
            tag: blot_direct_types::Tag.u32_,
            is_mask: false,
            invariant: false,
        };
        plan.locals_len = 1;

        // Analyze leading statements (affine index aliases or pure scalar bindings).
        for si in 0..(stmts_len - 1) {
            let cn = m.node(stmts[si]);
            if cn.tag != blot_check_core::Tag.bind || cn.c != 0 || m.binding(cn.a).scheme.variables.len != 0 {
                return blot_direct_types::Error.none;
            }
            let is_aff, aff_off = matchRangeAffineIndex(g, f, plan, m, f.env, cn.b);
            if is_aff {
                if plan.affine_locals_len >= 8 { return blot_direct_types::Error.none; }
                plan.affine_locals[plan.affine_locals_len] = SparkAffineLocal {
                    binding: cn.a,
                    offset_id: aff_off,
                };
                plan.affine_locals_len += 1;
                continue;
            }
            let bty, bok = lowerInEnv(g, m, m.typeOf(cn.b), f.env);
            if !bok || !isScalarTag(tagOf(g, bty)) || plan.locals_len >= 64 || lead_bind_len >= 8 {
                return blot_direct_types::Error.none;
            }
            if !checkVecExpr(g, f, plan, m, f.env, cn.b, 0, 0, false) {
                return blot_direct_types::Error.none;
            }
            let btag = tagOf(g, bty);
            let inv = isInvariantScalarExpr(g, f, plan, m, f.env, cn.b, btag, 0);
            plan.locals[plan.locals_len] = SparkVecLocal {
                unit: m.unit,
                binding: cn.a,
                tag: btag,
                is_mask: btag == blot_direct_types::Tag.boolean,
                invariant: inv,
            };
            plan.locals_len += 1;
            lead_bind_ids[lead_bind_len] = cn.a;
            lead_bind_exprs[lead_bind_len] = cn.b;
            lead_bind_tags[lead_bind_len] = btag;
            lead_bind_len += 1;
        }

        let dst_ok, d_off = matchRangeAffineIndex(g, f, plan, m, f.env, sels[0].index);
        if !dst_ok { return blot_direct_types::Error.none; }
        dst_off_id = d_off;

        let rhs_ty, rok = lowerInEnv(g, m, m.typeOf(uinfo.value), f.env);
        if !rok || tagOf(g, rhs_ty) != out_tag { return blot_direct_types::Error.none; }
        if !checkVecExpr(g, f, plan, m, f.env, uinfo.value, 0, 0, false) {
            return blot_direct_types::Error.none;
        }
        rhs_id = uinfo.value;
        matched = true;
    }

    if !matched { return blot_direct_types::Error.none; }

    // Emit 4-wide (with 4x unrolled 16-element fast path) SIMD loop guarded by
    // bounds, non-wrapping, and strict alias/overlap safety!
    let start_is_zero = g.units[f.unit - 1].node(info.first).tag == blot_check_core::Tag.constant && g.units[f.unit - 1].node(info.first).a == 0;
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

    // Destination bounds and byte extent [dst_ptr .. dst_byte_end).
    let dst_base, dst_len = ensureCheckedArray(g, f, dst_val);
    var dst_ptr: u32 = 0;
    if start_is_zero && dst_off_id == 0 {
        lget(g, count);
        lget(g, dst_len);
        op(g, OP_i32_gt_u);
        let dst_guard = open(g, f, OP_if_);
        i32Const(g, 0);
        lset(g, simd_end);
        close(g, f);
        dst_ptr = dst_base;
    } else {
        var dst_off_local: u32 = 0;
        if dst_off_id != 0 {
            let off_loc, oerr = emitInvariantU32(g, f, plan, g.units[f.unit - 1], f.env, dst_off_id);
            if oerr != blot_direct_types::Error.none { return oerr; }
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

        dst_ptr = local32(g, f);
        lget(g, dst_base);
        lget(g, dst_base_idx);
        i32Const(g, 2);
        op(g, OP_i32_shl);
        op(g, OP_i32_add);
        lset(g, dst_ptr);
    }

    var dst_byte_end: u32 = 0xffffffff;

    // Every source stream must satisfy bounds + non-wrapping + overlap safety:
    //   either (stream_ptr == dst_ptr && non-Bool) OR disjoint byte ranges.
    for si in 0..plan.streams_len {
        let st = plan.streams[si];
        // Fast path 1: stream is identical to dst (e.g. `c[dst] := c[dst] + ...`)!
        {
            let pm .= g.units[f.unit - 1];
            let st_arr_b = localRef(pm, st.arr_id);
            if st_arr_b != 0 && st_arr_b == dst_b && st.elem_tag == out_tag && sameOffsetExpr(pm, st.offset_id, dst_off_id) {
                plan.streams[si].ptr_local = dst_ptr;
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
        if dst_byte_end == 0xffffffff {
            dst_byte_end = local32(g, f);
            lget(g, dst_ptr);
            lget(g, count);
            i32Const(g, 2);
            op(g, OP_i32_shl);
            op(g, OP_i32_add);
            lset(g, dst_byte_end);
        }

        let arr_val, aerr = expr(g, f, st.arr_id);
        if aerr != blot_direct_types::Error.none { return aerr; }
        let arr_base, arr_len, blerr = containerBaseAndLen(g, f, arr_val, st.node_id);
        if blerr != blot_direct_types::Error.none { return blerr; }

        var stream_ptr: u32 = 0;
        var stream_byte_end: u32 = 0;
        if start_is_zero && st.offset_id == 0 {
            stream_ptr = arr_base;
            plan.streams[si].ptr_local = stream_ptr;
            stream_byte_end = local32(g, f);
            lget(g, stream_ptr);
            lget(g, count);
            if st.elem_tag != blot_direct_types::Tag.boolean {
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
                if oerr != blot_direct_types::Error.none { return oerr; }
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
            if st.elem_tag != blot_direct_types::Tag.boolean {
                i32Const(g, 2);
                op(g, OP_i32_shl);
            }
            op(g, OP_i32_add);
            lset(g, stream_ptr);
            plan.streams[si].ptr_local = stream_ptr;

            stream_byte_end = local32(g, f);
            lget(g, stream_ptr);
            lget(g, count);
            if st.elem_tag != blot_direct_types::Tag.boolean {
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

        // overlap_ok = (stream_byte_end <=_u dst_ptr) | (dst_byte_end <=_u stream_ptr) [| (stream_ptr == dst_ptr)]
        lget(g, stream_byte_end);
        lget(g, dst_ptr);
        op(g, OP_i32_le_u);
        lget(g, dst_byte_end);
        lget(g, stream_ptr);
        op(g, OP_i32_le_u);
        op(g, OP_i32_or);
        if st.elem_tag != blot_direct_types::Tag.boolean {
            lget(g, stream_ptr);
            lget(g, dst_ptr);
            op(g, OP_i32_eq);
            op(g, OP_i32_or);
        }
        op(g, OP_i32_and);
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
        if h.tag == blot_direct_types::Tag.boolean {
            i32Const(g, 0);
            lget(g, h.scalar_local);
            op(g, OP_i32_sub);
            simdOp(g, SIMD_i32x4_splat);
        } else if h.tag == blot_direct_types::Tag.f32_ {
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
    var v4_local: u32 = 0;
    if need_iter_vlocal {
        iter_vlocal = local(g, f, VT_v128);
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
    }

    // 4x unrolled 16-element SIMD loop (64-byte cache line per iteration) ahead of 4-element tail.
    if plan.streams_len <= 8 && plan.budget >= 80 {
        let simd16_end = local32(g, f);
        lget(g, simd_end);
        i32Const(g, 0xfffffff0);
        op(g, OP_i32_and);
        lset(g, simd16_end);

        let cur_dst = local32(g, f);
        var orig_ptrs: u32[8] = [0; 8];
        var cur_ptrs: u32[8] = [0; 8];
        for si in 0..plan.streams_len {
            orig_ptrs[si] = plan.streams[si].ptr_local;
            var reused: u32 = 0xffffffff;
            if orig_ptrs[si] == dst_ptr && plan.streams[si].elem_tag != blot_direct_types::Tag.boolean {
                reused = cur_dst;
            } else {
                for sj in 0..si {
                    if orig_ptrs[sj] == orig_ptrs[si] && (plan.streams[sj].elem_tag == blot_direct_types::Tag.boolean) == (plan.streams[si].elem_tag == blot_direct_types::Tag.boolean) {
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

        lget(g, dst_ptr);
        lget(g, byte_off);
        op(g, OP_i32_add);
        lset(g, cur_dst);

        for si in 0..plan.streams_len {
            var is_dup = cur_ptrs[si] == cur_dst;
            if !is_dup {
                for sj in 0..si {
                    if cur_ptrs[sj] == cur_ptrs[si] { is_dup = true; break; }
                }
            }
            if !is_dup {
                lget(g, orig_ptrs[si]);
                if plan.streams[si].elem_tag == blot_direct_types::Tag.boolean { lget(g, k); } else { lget(g, byte_off); }
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
            let m_step .= g.units[f.unit - 1];
            for li in 0..lead_bind_len {
                let lerr = emitVecExpr(g, f, plan, m_step, f.env, lead_bind_exprs[li], false);
                if lerr != blot_direct_types::Error.none { return lerr; }
                let vl = local(g, f, VT_v128);
                lset(g, vl);
                let lidx = findVecLocal(plan, m_step.unit, lead_bind_ids[li]);
                assert(lidx >= 0);
                plan.locals[lidx].vlocal = vl;
                if lead_bind_tags[li] == blot_direct_types::Tag.u32_ && plan.locals[lidx].invariant {
                    let sloc, serr = emitInvariantU32(g, f, plan, m_step, f.env, lead_bind_exprs[li]);
                    if serr != blot_direct_types::Error.none { return serr; }
                    plan.locals[lidx].scalar_local = sloc;
                }
            }
            lget(g, cur_dst);
            let rhs_err = emitVecExpr(g, f, plan, m_step, f.env, rhs_id, false);
            if rhs_err != blot_direct_types::Error.none { return rhs_err; }
            simdMemOp(g, SIMD_v128_store, 2, (step as u32) * 16);
            if need_iter_vlocal {
                lget(g, iter_vlocal);
                lget(g, v4_local);
                simdOp(g, SIMD_i32x4_add);
                lset(g, iter_vlocal);
            }
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
        if lerr != blot_direct_types::Error.none { return lerr; }
        let vl = local(g, f, VT_v128);
        lset(g, vl);
        let lidx = findVecLocal(plan, m_emit.unit, lead_bind_ids[li]);
        assert(lidx >= 0);
        plan.locals[lidx].vlocal = vl;
        if lead_bind_tags[li] == blot_direct_types::Tag.u32_ && plan.locals[lidx].invariant {
            let sloc, serr = emitInvariantU32(g, f, plan, m_emit, f.env, lead_bind_exprs[li]);
            if serr != blot_direct_types::Error.none { return serr; }
            plan.locals[lidx].scalar_local = sloc;
        }
    }

    // Store address, compute 4-wide RHS vector, v128.store!
    lget(g, dst_ptr);
    lget(g, byte_off);
    op(g, OP_i32_add);

    let rhs_err = emitVecExpr(g, f, plan, m_emit, f.env, rhs_id, false);
    if rhs_err != blot_direct_types::Error.none { return rhs_err; }

    simdMemOp(g, SIMD_v128_store, 2, 0);

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

    return blot_direct_types::Error.none;
}
