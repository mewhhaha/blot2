// Scalar and lane arithmetic, logic and conditionals of the direct backend's
// function emitter (compiler/src/direct/function.zig).
namespace squid_direct_function;
import .function;
type Op = squid_check_core::Op;

fn opName(value: Op) -> Chars {
    match value { const for <N, V> in variants<squid_check_core::Op> { V => { return N; }, } }
}
fn isScalarTag(tag: squid_direct_types::Tag) -> bool {
    match tag {
        u8_, i32_, u32_, i64_, u64_, f32_, f64_, boolean => { return true; },
        _ => { return false; },
    }
}
fn isComparisonOp(op_: Op) -> bool {
    return op_ == squid_check_core::Op.equal || op_ == squid_check_core::Op.not_equal || op_ == squid_check_core::Op.less || op_ == squid_check_core::Op.less_equal || op_ == squid_check_core::Op.greater || op_ == squid_check_core::Op.greater_equal;
}
fn isCanonicalF32Op(op_: Op) -> bool {
    return op_ == squid_check_core::Op.add || op_ == squid_check_core::Op.sub || op_ == squid_check_core::Op.mul || op_ == squid_check_core::Op.div || op_ == squid_check_core::Op.sqrt || op_ == squid_check_core::Op.floor || op_ == squid_check_core::Op.ceil || op_ == squid_check_core::Op.trunc;
}
fn isCanonicalF32Consumer(op_: Op) -> bool {
    return isCanonicalF32Op(op_) || isComparisonOp(op_) || op_ == squid_check_core::Op.convert_f32_u32 || op_ == squid_check_core::Op.convert_f32_i32 || op_ == squid_check_core::Op.numeric_convert;
}
fn canonicalV128Producer(op_: Op) -> bool {
    return isCanonicalF32Op(op_) || op_ == squid_check_core::Op.relaxed_madd || op_ == squid_check_core::Op.relaxed_nmadd;
}
fn isF32x4CoreExpr(m: const Module&, id: u32) -> bool {
    let ty = m.types.node(m.typeOf(id));
    if ty.tag != squid_check_types::Tag.product || ty.b != 4 { return false; }
    for lane in 0..4 {
        if m.types.extra[ty.a + lane] != squid_check_types::f32_type { return false; }
    }
    return true;
}
fn isF64x2CoreExpr(m: const Module&, id: u32) -> bool {
    let ty = m.types.node(m.typeOf(id));
    if ty.tag != squid_check_types::Tag.product || ty.b != 2 { return false; }
    return m.types.extra[ty.a] == squid_check_types::f64_type && m.types.extra[ty.a + 1] == squid_check_types::f64_type;
}
fn canonicalizeF32Stack(g: Generator&, f: const Fn&) {
    if !g.s.float_bits_observable { return; }
    let tmp = local(g, f, VT_f32);
    ltee(g, tmp);
    f32Const(g, 0x7fc00000);
    lget(g, tmp);
    lget(g, tmp);
    op(g, OP_f32_eq);
    op(g, OP_select);
}
fn isF32CoreExpr(g: Generator&, f: const Fn&, m: const Module&, expr_id: u32) -> bool {
    if expr_id == 0 { return false; }
    let raw = m.typeOf(expr_id);
    if raw == squid_check_types::f32_type { return true; }
    if raw <= squid_check_types::never { return false; }
    let ty, err = g.types.lower(m, raw, f.env);
    if err != squid_direct_types::Error.none { g.dropFailure(); return false; }
    return tagOf(g, ty) == squid_direct_types::Tag.f32_;
}
fn isFloatCoreExpr(g: Generator&, f: const Fn&, m: const Module&, expr_id: u32) -> bool {
    if expr_id == 0 { return false; }
    let raw = m.typeOf(expr_id);
    if raw == squid_check_types::f32_type || raw == squid_check_types::f64_type { return true; }
    if raw <= squid_check_types::never { return false; }
    let ty, err = g.types.lower(m, raw, f.env);
    if err != squid_direct_types::Error.none { g.dropFailure(); return false; }
    let tag = tagOf(g, ty);
    return tag == squid_direct_types::Tag.f32_ || tag == squid_direct_types::Tag.f64_;
}
// Proves `expr_id` evaluates to a finite non-NaN F32 with |x| <= 2^33.
// Closed under int->f32 conversions, small finite literals, neg/abs, and
// multiplication by finite constants with |c| <= 1.0, so any add/sub/mul
// of two bounded-finite operands has |res| <= 2^66 < FLT_MAX (never Inf/NaN).
recursive fn isBoundedFiniteF32(g: const Generator&, f: const Fn&, m: const Module&, id: u32, depth: i64 = 0) -> bool {
    if id == 0 || depth > 8 { return false; }
    let n = m.node(id);
    match n.tag {
        constant => {
            return (n.a & 0x7f800000) < 0x50000000;
        },
        reference => {
            let b = localRef(m, id);
            return b != 0 && hasFiniteF32(f, b);
        },
        scalar => {
            match n.op {
                convert_u32_f32, convert_i32_f32 => { return true; },
                neg, abs => { return isBoundedFiniteF32(g, f, m, n.a, depth + 1); },
                mul => {
                    let an = m.node(n.a);
                    let bn = m.node(n.b);
                    if bn.tag == squid_check_core::Tag.constant && (bn.a & 0x7fffffff) <= 0x3f800000 &&
                        isBoundedFiniteF32(g, f, m, n.a, depth + 1) { return true; }
                    if an.tag == squid_check_core::Tag.constant && (an.a & 0x7fffffff) <= 0x3f800000 &&
                        isBoundedFiniteF32(g, f, m, n.b, depth + 1) { return true; }
                    return false;
                },
                _ => { return false; },
            }
        },
        associated => {
            return n.op == squid_check_core::Op.convert_u32_f32 || n.op == squid_check_core::Op.convert_i32_f32;
        },
        call => {
            let target = g.resolve(m, m.call(id).target);
            if !g.hasUnit(target.unit) { return false; }
            let tm .= g.units[target.unit - 1];
            let pnode, has_alias = primitiveAlias(tm, target.binding);
            if !has_alias { return false; }
            let pop = tm.primitive(pnode).op;
            return pop == squid_check_core::Op.convert_u32_f32 || pop == squid_check_core::Op.convert_i32_f32;
        },
        _ => { return false; },
    }
}
fn isCoreScalar(m: const Module&, id: u32) -> bool {
    if id == 0 { return false; }
    let tag = m.types.node(m.typeOf(id)).tag;
    return squid_check_types::isNumeric(tag) || tag == squid_check_types::Tag.boolean;
}

// A scalar literal can stay as a typed operand until its consumer needs it.
recursive fn canonicalizeF64Stack(g: Generator&, f: const Fn&) {
    if !g.s.float_bits_observable { return; }
    let tmp = local(g, f, VT_f64);
    ltee(g, tmp);
    f64Const(g, 0, 0x7ff80000);
    lget(g, tmp);
    lget(g, tmp);
    op(g, OP_f64_eq);
    op(g, OP_select);
}
fn maskU8(g: Generator&) {
    i32Const(g, 255);
    op(g, OP_i32_and);
}
fn signedAbs(g: Generator&, f: const Fn&, wide: bool) {
    let value = local(g, f, if wide { VT_i64 } else { VT_i32 });
    lset(g, value);
    if wide { i64Const(g, 0); } else { i32Const(g, 0); }
    lget(g, value);
    op(g, if wide { OP_i64_sub } else { OP_i32_sub });
    lget(g, value);
    lget(g, value);
    if wide { i64Const(g, 0); } else { i32Const(g, 0); }
    op(g, if wide { OP_i64_lt_s } else { OP_i32_lt_s });
    op(g, OP_select);
}
fn scalarI64(g: Generator&, f: const Fn&, operation: Op, signed: bool, id: u32) -> Error {
    var code: u8 = 0;
    match operation {
        add => { code = OP_i64_add; },
        sub => { code = OP_i64_sub; },
        mul => { code = OP_i64_mul; },
        equal => { code = OP_i64_eq; },
        not_equal => { code = OP_i64_ne; },
        bit_and => { code = OP_i64_and; },
        bit_or => { code = OP_i64_or; },
        bit_xor => { code = OP_i64_xor; },
        shift_left => { code = OP_i64_shl; },
        from_bits => { code = OP_f64_reinterpret_i64; },
        div => { code = if signed { OP_i64_div_s } else { OP_i64_div_u }; },
        rem => { code = if signed { OP_i64_rem_s } else { OP_i64_rem_u }; },
        less => { code = if signed { OP_i64_lt_s } else { OP_i64_lt_u }; },
        less_equal => { code = if signed { OP_i64_le_s } else { OP_i64_le_u }; },
        greater => { code = if signed { OP_i64_gt_s } else { OP_i64_gt_u }; },
        greater_equal => { code = if signed { OP_i64_ge_s } else { OP_i64_ge_u }; },
        shift_right => { code = if signed { OP_i64_shr_s } else { OP_i64_shr_u }; },
        bit_not => { i64Const(g, -1); code = OP_i64_xor; },
        neg => {
            let value = local(g, f, VT_i64);
            lset(g, value);
            i64Const(g, 0);
            lget(g, value);
            code = OP_i64_sub;
        },
        abs => {
            if signed { signedAbs(g, f, true); }
            return squid_direct_types::Error.none;
        },
        mul_wide => {
            let bv = local(g, f, VT_i64);
            let av = local(g, f, VT_i64);
            lset(g, bv);
            lset(g, av);
            // Push lo first, then hi on top so `pop` unpacks (lo, hi).
            lget(g, av);
            lget(g, bv);
            op(g, OP_i64_mul);
            let b_lo = local(g, f, VT_i64);
            let b_hi = local(g, f, VT_i64);
            lget(g, bv);
            i64Const(g, 0xffffffff);
            op(g, OP_i64_and);
            lset(g, b_lo);
            lget(g, bv);
            i64Const(g, 32);
            op(g, OP_i64_shr_u);
            lset(g, b_hi);
            emitMulHi64(g, f, av, b_lo as u64, b_hi as u64, true);
            return squid_direct_types::Error.none;
        },
        _ => { return g.fail(g.units[f.unit - 1], id, "unsupported 64-bit integer operation"); },
    }
    op(g, code);
    return squid_direct_types::Error.none;
}
fn scalarF64(g: Generator&, f: const Fn&, operation: Op, id: u32, canonicalize: bool = true) -> Error {
    var code: u8 = 0;
    match operation {
        add => { code = OP_f64_add; },
        sub => { code = OP_f64_sub; },
        mul => { code = OP_f64_mul; },
        div => { code = OP_f64_div; },
        abs => { code = OP_f64_abs; },
        neg => { code = OP_f64_neg; },
        sqrt => { code = OP_f64_sqrt; },
        floor => { code = OP_f64_floor; },
        ceil => { code = OP_f64_ceil; },
        trunc => { code = OP_f64_trunc; },
        equal => { code = OP_f64_eq; },
        not_equal => { code = OP_f64_ne; },
        less => { code = OP_f64_lt; },
        less_equal => { code = OP_f64_le; },
        greater => { code = OP_f64_gt; },
        greater_equal => { code = OP_f64_ge; },
        min => { code = OP_f64_min; },
        max => { code = OP_f64_max; },
        bits => { code = OP_i64_reinterpret_f64; },
        _ => { return g.fail(g.units[f.unit - 1], id, "unsupported F64 operation"); },
    }
    op(g, code);
    if canonicalize && (isCanonicalF32Op(operation) || operation == squid_check_core::Op.min || operation == squid_check_core::Op.max) { canonicalizeF64Stack(g, f); }
    return squid_direct_types::Error.none;
}
fn convertScalar(g: Generator&, f: const Fn&, input: Ty, output: Ty, id: u32) -> Error {
    if input == output { return squid_direct_types::Error.none; }
    let src = tagOf(g, input);
    let dst = tagOf(g, output);
    if !isScalarTag(src) || !isScalarTag(dst) {
        return g.fail(g.units[f.unit - 1], id, "conversion requires concrete numeric types");
    }
    let src_float = src == squid_direct_types::Tag.f32_ || src == squid_direct_types::Tag.f64_;
    let dst_float = dst == squid_direct_types::Tag.f32_ || dst == squid_direct_types::Tag.f64_;
    let src_wide = src == squid_direct_types::Tag.i64_ || src == squid_direct_types::Tag.u64_;
    let dst_wide = dst == squid_direct_types::Tag.i64_ || dst == squid_direct_types::Tag.u64_;
    let src_signed = src == squid_direct_types::Tag.i32_ || src == squid_direct_types::Tag.i64_;
    let dst_signed = dst == squid_direct_types::Tag.i32_ || dst == squid_direct_types::Tag.i64_;
    if src_float && dst_float {
        if dst == squid_direct_types::Tag.f64_ {
            op(g, OP_f64_promote_f32);
            canonicalizeF64Stack(g, f);
        } else {
            op(g, OP_f32_demote_f64);
            canonicalizeF32Stack(g, f);
        }
    } else if src_float {
        // 0..7 are trunc_sat: result width, input width, then signedness.
        var subop: u32 = 0;
        if dst_wide { subop += 4; }
        if src == squid_direct_types::Tag.f64_ { subop += 2; }
        if !dst_signed { subop += 1; }
        op(g, OP_prefix_fc);
        uleb(g, subop);
        if dst == squid_direct_types::Tag.u8_ {
            let value = local32(g, f);
            ltee(g, value);
            i32Const(g, 255);
            lget(g, value);
            i32Const(g, 255);
            op(g, OP_i32_le_u);
            op(g, OP_select);
        }
    } else if dst_float {
        var code = if dst == squid_direct_types::Tag.f32_ { OP_f32_convert_i32_s } else { OP_f64_convert_i32_s };
        if src_wide { code += 2; }
        if !src_signed { code += 1; }
        op(g, code);
    } else {
        if src_wide && !dst_wide { op(g, OP_i32_wrap_i64); }
        if !src_wide && dst_wide { op(g, if src_signed { OP_i64_extend_i32_s } else { OP_i64_extend_i32_u }); }
        if dst == squid_direct_types::Tag.u8_ { maskU8(g); }
    }
    return squid_direct_types::Error.none;
}

fn scalarOperand(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    if m.node(id).tag == squid_check_core::Tag.constant && isCoreScalar(m, id) {
        let ty, error = typeOf(g, f, id);
        return Val { ty: ty }, error;
    }
    return expr(g, f, id);
}
fn pushScalarOperand(g: Generator&, f: const Fn&, id: u32, value: Val) {
    if value.len != 0 || !isScalarTag(tagOf(g, value.ty)) { push(g, value); return; }
    let m .= g.units[f.unit - 1];
    squid_direct_relocations::operand(m.unit, id, g.s.code.len);
    let n = m.node(id);
    pushConstant(g, value.ty, n.a, n.b);
}
fn u32OperandConstant(g: const Generator&, f: const Fn&, id: u32, value: Val) -> ConstU32, bool {
    if value.len == 0 {
        let m .= g.units[f.unit - 1];
        return ConstU32 { value: m.node(id).a, unit: m.unit, node: id }, true;
    }
    return constU32(f, w(g, value, 0));
}
fn floorLog2U32(value: u32) -> u32 {
    var bits = value;
    var log: u32 = 0;
    while bits > 1 { bits >>= 1; log += 1; }
    return log;
}

// The rounded-up reciprocal at 32 + ceil(log2(d)) has an error strictly
// below 1/d for every U32 dividend. Subtract the implicit high word before
// multiplying, so both the reciprocal construction and product fit in u64.
fn reciprocalLow(d: u64, shift: u32) -> u64 {
    return (((((1 as u64) << shift) - d) << 32) + (d - 1)) / d;
}
fn emitReciprocalQuotient(g: Generator&, f: const Fn&, left_id: u32, left: Val, multiplier: u64, shift: u32, add: bool, runtime: bool) {
    pushScalarOperand(g, f, left_id, left);
    op(g, OP_i64_extend_i32_u);
    if runtime { lget(g, multiplier as u32); } else { i64Const(g, multiplier as i64); }
    op(g, OP_i64_mul);
    if add {
        i64Const(g, 32);
        op(g, OP_i64_shr_u);
        pushScalarOperand(g, f, left_id, left);
        op(g, OP_i64_extend_i32_u);
        op(g, OP_i64_add);
    }
    if runtime { lget(g, shift); } else { i64Const(g, shift); }
    op(g, OP_i64_shr_u);
    op(g, OP_i32_wrap_i64);
}

fn emitU32StrengthReduction(g: Generator&, f: Fn&, machine: Op, left_id: u32, left: Val, right_id: u32, right: Val) -> bool {
    if machine != squid_check_core::Op.mul && machine != squid_check_core::Op.div && machine != squid_check_core::Op.rem { return false; }
    let rhs, rhs_known = u32OperandConstant(g, f, right_id, right);
    if machine == squid_check_core::Op.mul {
        var input = left;
        var input_id = left_id;
        var factor = rhs;
        if !rhs_known || (rhs.value != 0 && (rhs.value & (rhs.value - 1)) != 0) {
            let lhs, lhs_known = u32OperandConstant(g, f, left_id, left);
            if !lhs_known || (lhs.value != 0 && (lhs.value & (lhs.value - 1)) != 0) { return false; }
            factor = lhs;
            input = right;
            input_id = right_id;
        }
        useConstU32(factor);
        if factor.value == 0 { i32Const(g, 0); }
        else {
            pushScalarOperand(g, f, input_id, input);
            if factor.value > 1 {
                i32Const(g, floorLog2U32(factor.value));
                op(g, OP_i32_shl);
            }
        }
        return true;
    }
    let remainder = machine == squid_check_core::Op.rem;
    if rhs_known {
        let d = rhs.value;
        // Keep the native divide-by-zero instruction and its trap.
        if d == 0 { return false; }
        useConstU32(rhs);
        if d == 1 {
            if remainder { i32Const(g, 0); } else { pushScalarOperand(g, f, left_id, left); }
            return true;
        }
        let log = floorLog2U32(d);
        if (d & (d - 1)) == 0 {
            pushScalarOperand(g, f, left_id, left);
            if remainder { i32Const(g, d - 1); op(g, OP_i32_and); }
            else { i32Const(g, log); op(g, OP_i32_shr_u); }
            return true;
        }
        if remainder { pushScalarOperand(g, f, left_id, left); }
        let scale = (1 as u64) << (32 + log);
        let d64 = d as u64;
        let rounding = d64 - scale % d64;
        if rounding <= ((1 as u64) << log) {
            // This smaller reciprocal also has error below 1/d.
            emitReciprocalQuotient(g, f, left_id, left, scale / d64 + 1, 32 + log, false, false);
        } else {
            let shift = log + 1;
            emitReciprocalQuotient(g, f, left_id, left, reciprocalLow(d64, shift), shift, true, false);
        }
        if remainder { i32Const(g, d); op(g, OP_i32_mul); op(g, OP_i32_sub); }
        return true;
    }
    let divisor = w(g, right, 0);
    for at in 0..f.loop_reciprocals_len {
        let reciprocal = f.loop_reciprocals[at];
        if reciprocal.divisor != divisor { continue; }
        // Without an unconditional, trap-free prefix, defer a zero
        // divisor trap to the operation that actually executes.
        if reciprocal.check_at_use {
            lget(g, divisor);
            op(g, OP_i32_eqz);
            trap(g, f);
        }
        if remainder { pushScalarOperand(g, f, left_id, left); }
        emitReciprocalQuotient(g, f, left_id, left, reciprocal.multiplier, reciprocal.shift, true, true);
        if remainder { lget(g, divisor); op(g, OP_i32_mul); op(g, OP_i32_sub); }
        return true;
    }
    return false;
}

fn floorLog2U64(value: u64) -> u64 {
    var bits = value;
    var log: u64 = 0;
    while bits > 1 { bits >>= 1; log += 1; }
    return log;
}
fn u64OperandConstant(g: const Generator&, f: const Fn&, id: u32, value: Val) -> ConstU64, bool {
    if value.len == 0 {
        let m .= g.units[f.unit - 1];
        let n = m.node(id);
        return ConstU64 { value: (n.a as u64) | ((n.b as u64) << 32), unit: m.unit, node: id }, true;
    }
    return constU64(f, w(g, value, 0));
}
// Exact Granlund-Montgomery 64-bit unsigned division parameters for non-pow2 d >= 2.
// Returns (multiplier, shift, add):
//   if !add: q = mulhi64(x, m) >> shift
//   if  add: t = mulhi64(x, m); q = (((x - t) >> 1) + t) >> shift
fn u64DivParams(d: u64) -> u64, u64, bool {
    let log = floorLog2U64(d);
    var rem: u64 = (1 as u64) << log;
    var q_log: u64 = 0;
    for _ in 0..64 {
        let carry = rem >> 63;
        let rem2 = rem << 1;
        q_log <<= 1;
        if carry != 0 || rem2 >= d {
            rem = rem2 - d;
            q_log |= 1;
        } else {
            rem = rem2;
        }
    }
    let rounding = d - rem;
    if rounding <= ((1 as u64) << log) {
        return q_log + 1, log, false;
    }
    var rem_a: u64 = 0;
    if log == 63 { rem_a = (0 as u64) - d; } else { rem_a = ((1 as u64) << (log + 1)) - d; }
    var m_low: u64 = 0;
    for _ in 0..64 {
        let carry = rem_a >> 63;
        let rem2 = rem_a << 1;
        m_low <<= 1;
        if carry != 0 || rem2 >= d {
            rem_a = rem2 - d;
            m_low |= 1;
        } else {
            rem_a = rem2;
        }
    }
    return m_low + 1, log, true;
}
// Pushes upper 64 bits of (xv * ((m_hi << 32) | m_lo)) onto the stack.
// When `runtime` is true, `m_lo_arg`/`m_hi_arg` are VT_i64 local indices holding 32-bit halves;
// otherwise they are 32-bit half constants.
fn emitMulHi64(g: Generator&, f: const Fn&, xv: u32, m_lo_arg: u64, m_hi_arg: u64, runtime: bool) {
    let x_lo = local(g, f, VT_i64);
    let x_hi = local(g, f, VT_i64);
    let p1 = local(g, f, VT_i64);
    let p2 = local(g, f, VT_i64);
    lget(g, xv);
    i64Const(g, 0xffffffff);
    op(g, OP_i64_and);
    lset(g, x_lo);
    lget(g, xv);
    i64Const(g, 32);
    op(g, OP_i64_shr_u);
    lset(g, x_hi);
    // p1 = x_lo * m_hi
    lget(g, x_lo);
    if runtime { lget(g, m_hi_arg as u32); } else { i64Const(g, m_hi_arg as! i64); }
    op(g, OP_i64_mul);
    lset(g, p1);
    // p2 = x_hi * m_lo
    lget(g, x_hi);
    if runtime { lget(g, m_lo_arg as u32); } else { i64Const(g, m_lo_arg as! i64); }
    op(g, OP_i64_mul);
    lset(g, p2);
    // mid = ((x_lo * m_lo) >> 32) + (p1 & 0xffffffff) + (p2 & 0xffffffff)
    lget(g, x_lo);
    if runtime { lget(g, m_lo_arg as u32); } else { i64Const(g, m_lo_arg as! i64); }
    op(g, OP_i64_mul);
    i64Const(g, 32);
    op(g, OP_i64_shr_u);
    lget(g, p1);
    i64Const(g, 0xffffffff);
    op(g, OP_i64_and);
    op(g, OP_i64_add);
    lget(g, p2);
    i64Const(g, 0xffffffff);
    op(g, OP_i64_and);
    op(g, OP_i64_add);
    i64Const(g, 32);
    op(g, OP_i64_shr_u);
    // + (p1 >> 32) + (p2 >> 32) + (x_hi * m_hi)
    lget(g, p1);
    i64Const(g, 32);
    op(g, OP_i64_shr_u);
    op(g, OP_i64_add);
    lget(g, p2);
    i64Const(g, 32);
    op(g, OP_i64_shr_u);
    op(g, OP_i64_add);
    lget(g, x_hi);
    if runtime { lget(g, m_hi_arg as u32); } else { i64Const(g, m_hi_arg as! i64); }
    op(g, OP_i64_mul);
    op(g, OP_i64_add);
}
fn emitU64StrengthReduction(g: Generator&, f: Fn&, machine: Op, left_id: u32, left: Val, right_id: u32, right: Val) -> bool {
    if machine != squid_check_core::Op.mul && machine != squid_check_core::Op.div && machine != squid_check_core::Op.rem { return false; }
    let rhs, rhs_known = u64OperandConstant(g, f, right_id, right);
    if machine == squid_check_core::Op.mul {
        var input = left;
        var input_id = left_id;
        var factor = rhs;
        if !rhs_known || (rhs.value != 0 && (rhs.value & (rhs.value - 1)) != 0) {
            let lhs, lhs_known = u64OperandConstant(g, f, left_id, left);
            if !lhs_known || (lhs.value != 0 && (lhs.value & (lhs.value - 1)) != 0) { return false; }
            factor = lhs;
            input = right;
            input_id = right_id;
        }
        useConstU64(factor);
        if factor.value == 0 { i64Const(g, 0); }
        else {
            pushScalarOperand(g, f, input_id, input);
            if factor.value > 1 {
                i64Const(g, floorLog2U64(factor.value) as! i64);
                op(g, OP_i64_shl);
            }
        }
        return true;
    }
    let remainder = machine == squid_check_core::Op.rem;
    if rhs_known {
        let d = rhs.value;
        if d == 0 { return false; }
        useConstU64(rhs);
        if d == 1 {
            if remainder { i64Const(g, 0); } else { pushScalarOperand(g, f, left_id, left); }
            return true;
        }
        if (d & (d - 1)) == 0 {
            pushScalarOperand(g, f, left_id, left);
            if remainder {
                i64Const(g, (d - 1) as! i64);
                op(g, OP_i64_and);
            } else {
                i64Const(g, floorLog2U64(d) as! i64);
                op(g, OP_i64_shr_u);
            }
            return true;
        }
        // Non-power-of-two 64-bit divisors stay on native i64.div_u / i64.rem_u:
        // Wasm32 lacks a 64x64->128 multiply, and emulating mulhi64 in software
        // (~30 Wasm ops) is ~45% slower than hardware divq on x86-64.
        return false;
    }
    return false;
}

recursive fn scalar(g: Generator&, f: Fn&, id: u32, elide_nan: bool = false, stack_result: bool = false) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    // Peephole-elide NaN canonicalization on direct F32/F64 operands ONLY when this
    // operation itself canonicalizes or ignores NaN payloads (arithmetic/rounding,
    // float comparisons, float->int trunc_sat / float->float conversions).
    let scalar_children = isCanonicalF32Consumer(n.op) && isFloatCoreExpr(g, f, m, n.a);
    let vector_children = (isCanonicalF32Consumer(n.op) || canonicalV128Producer(n.op)) && (isF32x4CoreExpr(m, n.a) || isF64x2CoreExpr(m, n.a));
    let elide_children = scalar_children || vector_children;
    if elide_children { f.elide_f32_nan_node = n.a; }
    let left, error = scalarOperand(g, f, n.a);
    f.elide_f32_nan_node = 0;
    if error != squid_direct_types::Error.none { return left, error; }
    var has_right = false;
    var right = neverVal();
    if n.b != 0 {
        if elide_children { f.elide_f32_nan_node = n.b; }
        var value = neverVal();
        var error = squid_direct_types::Error.none;
        if isScalarTag(tagOf(g, left.ty)) { value, error = scalarOperand(g, f, n.b); }
        else { value, error = expr(g, f, n.b); }
        f.elide_f32_nan_node = 0;
        if error != squid_direct_types::Error.none { return value, error; }
        has_right = true;
        right = value;
    }
    var tag = tagOf(g, left.ty);
    var operand_left = left;
    var operand_right = right;
    // Opaque wrappers of a scalar are erased at run time.
    if tag == squid_direct_types::Tag.nominal {
        let inner, has_inner = scalarPayload(g, left);
        if has_inner {
            var dispatch = false;
            if n.c == 1 {
                let identity, has_identity = g.receiverIdentity(left.ty);
                assert(has_identity);
                let operator, has_operator = operatorOf(n.op);
                let target, has_target = g.dispatchTarget(m, identity, 0, operator);
                dispatch = has_target;
            }
            if !dispatch {
                operand_left = inner;
                if has_right {
                    let right_inner, has_right_inner = scalarPayload(g, right);
                    if has_right_inner { operand_right = right_inner; }
                }
                tag = tagOf(g, inner.ty);
            }
        }
    }
    if isScalarTag(tag) && operand_left.ty != left.ty {
        push(g, operand_left);
        if has_right { push(g, operand_right); }
        let emitted = scalarOp(g, f, n.op, operand_left.ty, id, !elide_nan);
        if emitted != squid_direct_types::Error.none { return neverVal(), emitted; }
        var result: Ty = 0;
        if n.c == 1 {
            if isComparisonOp(n.op) { result = squid_direct_types::boolean; } else { result = left.ty; }
        } else {
            let lowered, error = typeOf(g, f, id);
            if error != squid_direct_types::Error.none { return neverVal(), error; }
            result = lowered;
        }
        return pop(g, f, result, id);
    }
    if n.c == 1 && !isScalarTag(tag) && tag != squid_direct_types::Tag.tuple {
        // Operator dispatch: the operand type's associated operator member.
        let operator, has_operator = operatorOf(n.op);
        if !has_operator {
            g.failOpen(m, id);
            g.put(opName(n.op));
            g.put(" has no associated operator");
            return neverVal(), g.failClose();
        }
        let identity, has_identity = g.receiverIdentity(left.ty);
        if !has_identity {
            g.failOpen(m, id);
            g.put(opName(n.op));
            g.put(" on a ");
            g.put(squid_direct_types::tagName(tag));
            return neverVal(), g.failClose();
        }
        let target, has_target = g.dispatchTarget(m, identity, 0, operator);
        if !has_target {
            g.failOpen(m, id);
            g.put("no ");
            g.put(opName(n.op));
            g.put(" operator for this type");
            return neverVal(), g.failClose();
        }
        var arguments = g.saveVals([left]);
        if has_right { arguments = g.saveVals([left, right]); }
        let callee, error = calleeOf(g, f, target, arguments, id);
        if error != squid_direct_types::Error.none { return neverVal(), error; }
        let rest, error = restType(g, f, callee, arguments.len, id);
        if error != squid_direct_types::Error.none { return neverVal(), error; }
        return callTarget(g, f, target, arguments, callee, rest, id);
    }
    var result: Ty = 0;
    if n.c == 1 && isScalarTag(tag) {
        if isComparisonOp(n.op) { result = squid_direct_types::boolean; } else { result = left.ty; }
    } else {
        let lowered, error = typeOf(g, f, id);
        if error != squid_direct_types::Error.none { return neverVal(), error; }
        result = lowered;
    }
    if n.op == squid_check_core::Op.i8x16_splat {
        pushScalarOperand(g, f, n.a, left);
        simdOp(g, SIMD_i8x16_splat);
        return popV128(g, f, result), squid_direct_types::Error.none;
    }
    if n.op == squid_check_core::Op.i16x8_splat {
        pushScalarOperand(g, f, n.a, left);
        simdOp(g, SIMD_i16x8_splat);
        return popV128(g, f, result), squid_direct_types::Error.none;
    }
    if tag == squid_direct_types::Tag.tuple {
        let selectors = laneSelectorOperand(n.op, n.a, n.b);
        return lanes(g, f, n.op, left, right, result, id, elide_nan, selectors);
    }
    // Machine operations take operands of one type; the checker should reject
    // a mix, so never emit one.
    if has_right && right.ty != left.ty {
        g.failOpenCode(m, id, squid_check_diagnostic_code::Code.type_mismatch);
        g.put(opName(n.op));
        g.put(" applied to a ");
        g.put(squid_direct_types::tagName(tagOf(g, left.ty)));
        g.put(" and a ");
        g.put(squid_direct_types::tagName(tagOf(g, right.ty)));
        return neverVal(), g.failClose();
    }
    var machine = n.op;
    if n.c == 1 {
        let member, error = scalarMember(g, f, m, left.ty, 0, n.op, id);
        if error != squid_direct_types::Error.none { return neverVal(), error; }
        machine = member;
    }
    var skip_nan = elide_nan;
    if !skip_nan && f.defer_f32_nan && (tagOf(g, left.ty) == squid_direct_types::Tag.f32_ || tagOf(g, left.ty) == squid_direct_types::Tag.f64_) && isCanonicalF32Op(machine) {
        skip_nan = true;
    }
    if !skip_nan && tagOf(g, left.ty) == squid_direct_types::Tag.f32_ && has_right &&
        (machine == squid_check_core::Op.add || machine == squid_check_core::Op.sub || machine == squid_check_core::Op.mul) &&
        isBoundedFiniteF32(g, f, m, n.a) && isBoundedFiniteF32(g, f, m, n.b) {
        skip_nan = true;
    }
    // Strength-reduce exact IEEE-754 `2.0 * x` / `x * 2.0` to `x + x` (bit-identical for all F32 values).
    if tagOf(g, left.ty) == squid_direct_types::Tag.f32_ && has_right && machine == squid_check_core::Op.mul {
        let na = m.node(n.a);
        let nb = m.node(n.b);
        if na.tag == squid_check_core::Tag.constant && na.a == 0x40000000 {
            squid_direct_relocations::unpatchableOperand(m.unit, n.a);
            pushScalarOperand(g, f, n.b, right);
            pushScalarOperand(g, f, n.b, right);
            let emitted = scalarOp(g, f, squid_check_core::Op.add, left.ty, id, !skip_nan);
            if emitted != squid_direct_types::Error.none { return neverVal(), emitted; }
            return pop(g, f, result, id);
        }
        if nb.tag == squid_check_core::Tag.constant && nb.a == 0x40000000 {
            squid_direct_relocations::unpatchableOperand(m.unit, n.b);
            pushScalarOperand(g, f, n.a, left);
            pushScalarOperand(g, f, n.a, left);
            let emitted = scalarOp(g, f, squid_check_core::Op.add, left.ty, id, !skip_nan);
            if emitted != squid_direct_types::Error.none { return neverVal(), emitted; }
            return pop(g, f, result, id);
        }
    }
    if has_right && left.ty == squid_direct_types::u32_ &&
        emitU32StrengthReduction(g, f, machine, n.a, left, n.b, right) {
        return pop(g, f, result, id);
    }
    if has_right && left.ty == squid_direct_types::u64_ &&
        emitU64StrengthReduction(g, f, machine, n.a, left, n.b, right) {
        return pop(g, f, result, id);
    }
    pushScalarOperand(g, f, n.a, left);
    if has_right { pushScalarOperand(g, f, n.b, right); }
    let emitted = scalarOp(g, f, machine, left.ty, id, !skip_nan, result);
    if emitted != squid_direct_types::Error.none { return neverVal(), emitted; }
    if stack_result { return Val { ty: result }, squid_direct_types::Error.none; }
    let popped, perr = pop(g, f, result, id);
    if perr != squid_direct_types::Error.none { return popped, perr; }
    if machine == squid_check_core::Op.numeric_convert && left.ty == squid_direct_types::u32_ && result == squid_direct_types::u64_ {
        let cf, known = u32OperandConstant(g, f, n.a, left);
        if known { recordConstU64(f, w(g, popped, 0), cf.value as u64, cf.unit, cf.node); }
        else if left.len == 1 { recordExtU32U64(f, w(g, popped, 0), w(g, left, 0)); }
    } else if has_right && result == squid_direct_types::u32_ && left.ty == squid_direct_types::u32_ {
        if machine == squid_check_core::Op.bit_and {
            let rc, rk = u32OperandConstant(g, f, n.b, right);
            if rk {
                recordCheckedMask(f, w(g, popped, 0), if right.len == 1 { w(g, right, 0) } else { 0xffffffff }, rc.value, true);
            } else if right.len == 1 {
                recordCheckedMask(f, w(g, popped, 0), w(g, right, 0), 0, false);
            } else {
                let lc, lk = u32OperandConstant(g, f, n.a, left);
                if lk { recordCheckedMask(f, w(g, popped, 0), if left.len == 1 { w(g, left, 0) } else { 0xffffffff }, lc.value, true); }
                else if left.len == 1 { recordCheckedMask(f, w(g, popped, 0), w(g, left, 0), 0, false); }
            }
        } else if machine == squid_check_core::Op.add {
            let rc, rk = u32OperandConstant(g, f, n.b, right);
            let lc, lk = u32OperandConstant(g, f, n.a, left);
            if rk && rc.value >= 1 && rc.value <= 4 && left.len == 1 {
                let ll = w(g, left, 0);
                let prev = findCheckedAdd(f, ll);
                if prev >= 0 && f.checked_adds[prev].c + rc.value <= 4 {
                    recordCheckedAdd(f, w(g, popped, 0), f.checked_adds[prev].base, f.checked_adds[prev].idx, f.checked_adds[prev].c + rc.value);
                } else {
                    recordCheckedAdd(f, w(g, popped, 0), 0xffffffff, ll, rc.value);
                }
            } else if lk && lc.value >= 1 && lc.value <= 4 && right.len == 1 {
                let rl = w(g, right, 0);
                let prev = findCheckedAdd(f, rl);
                if prev >= 0 && f.checked_adds[prev].c + lc.value <= 4 {
                    recordCheckedAdd(f, w(g, popped, 0), f.checked_adds[prev].base, f.checked_adds[prev].idx, f.checked_adds[prev].c + lc.value);
                } else {
                    recordCheckedAdd(f, w(g, popped, 0), 0xffffffff, rl, lc.value);
                }
            } else if !rk && !lk && left.len == 1 && right.len == 1 && !f.checked_range.is_view && f.checked_range.end_local != 0xffffffff {
                let ll = w(g, left, 0);
                let rl = w(g, right, 0);
                if rl == f.checked_range.index {
                    recordCheckedAdd(f, w(g, popped, 0), ll, rl, 0);
                } else if ll == f.checked_range.index {
                    recordCheckedAdd(f, w(g, popped, 0), rl, ll, 0);
                }
            }
        } else if machine == squid_check_core::Op.sub {
            let rc, rk = u32OperandConstant(g, f, n.b, right);
            if rk && rc.value == 1 && left.len == 1 {
                recordCheckedSub1(f, w(g, popped, 0), w(g, left, 0));
            }
        }
    }
    return popped, squid_direct_types::Error.none;
}
// `calleeFromArguments` for values: the callee's type from argument types.
fn calleeOf(g: Generator&, f: const Fn&, target: BindingRef, arguments: Vals, id: u32) -> Ty, Error {
    let types = Tys { g.s.tys.len as u32, arguments.len };
    for at in 0..(arguments.len as i64) { g.s.tys.push(g.s.vals[arguments.start + at].ty); }
    return g.calleeFromArguments(target, types, g.units[f.unit - 1], id, evidenceContext(g, f, target, id));
}
// The machine operation an operator or member `member` (a symbol, or zero to
// look up `op`'s operator) applies to a U32, F32 or Bool receiver. The
// receiver's type must have the member; one that aliases a primitive applies
// that primitive. Function members stand for the machine operation until
// traits replace this dispatch (tasks/LANGUAGE_COHERENCE.md C).
// `catalog` is the module whose associated members the operator sees; `id` in
// this function's module is where a missing member is reported.
fn scalarMember(g: Generator&, f: const Fn&, catalog: const Module&, receiver: Ty, member: u32, standard: Op, id: u32) -> Op, Error {
    let identity, has_identity = g.receiverIdentity(receiver);
    if !has_identity { return standard, squid_direct_types::Error.none; }
    var operator = squid_check_types::Operator.none;
    if member == 0 {
        let found, has_operator = operatorOf(standard);
        if !has_operator { return standard, squid_direct_types::Error.none; }
        operator = found;
    }
    let target, has_target = g.dispatchTarget(catalog, identity, member, operator);
    if !has_target {
        if member == 0 { return standard, squid_direct_types::Error.none; }
        g.failOpenCode(g.units[f.unit - 1], id, squid_check_diagnostic_code::Code.missing_associated);
        g.put(squid_direct_types::tagName(tagOf(g, receiver)));
        g.put(" has no `");
        var named = false;
        if member != 0 {
            let spelling = catalog.fieldSpelling(member);
            if spelling.present { g.put(spelling.value); named = true; }
        }
        if !named { g.put(opName(standard)); }
        g.put("` member");
        return standard, g.failClose();
    }
    if !g.hasUnit(target.unit) { return standard, squid_direct_types::Error.none; }
    let defining .= g.units[target.unit - 1];
    let alias, has_alias = primitiveAlias(defining, target.binding);
    if !has_alias { return standard, squid_direct_types::Error.none; }
    g.recordInlined(target.unit, target.binding);
    let primitive = defining.primitive(alias);
    if primitive.kind == squid_check_core::PrimitiveKind.scalar && primitive.op != squid_check_core::Op.none { return primitive.op, squid_direct_types::Error.none; }
    return standard, squid_direct_types::Error.none;
}
// The scalar payload of a single-constructor value, if it has one.
fn scalarPayload(g: Generator&, value: Val) -> Val, bool {
    if tagOf(g, value.ty) != squid_direct_types::Tag.nominal { return value, false; }
    let cases, error = g.types.variants(value.ty);
    if error != squid_direct_types::Error.none { return value, false; }
    if cases.len != 1 { return value, false; }
    let payload = g.types.variant_payloads[cases.payloads];
    if !isScalarTag(tagOf(g, payload)) { return value, false; }
    return Val { payload, value.start, value.len }, true;
}
// The shadow's scalar locals are private to this immutable vector result.
// Branch joins and loop carries still copy through the ordinary tuple layout.
fn shadowV128(g: Generator&, f: const Fn&, ty: Ty, vloc: u32) -> Val {
    let n = g.types.node(ty);
    let elem = g.types.words[n.a];
    let is_wide = n.b == 2;
    let is_float = elem == squid_direct_types::f32_ || elem == squid_direct_types::f64_;
    var kind = VT_i32;
    if is_wide {
        kind = if is_float { VT_f64 } else { VT_i64 };
    } else if is_float {
        kind = VT_f32;
    }
    let count: u32 = if is_wide { 2 } else { 4 };
    let start = g.s.words.len as u32;
    let w0 = local(g, f, kind);
    let key = shadow_word_bit | ((g.s.v128_shadows.len as u32) << 2);
    g.s.v128_shadows.push(squid_direct_emit::V128Shadow { w0, vloc, is_float, is_wide, f.depth, .. });
    g.s.words.push(key);
    for lane in 1..(count as i64) {
        let _ = local(g, f, kind);
        g.s.words.push(key + (lane as u32));
    }
    return Val { ty, start, count };
}
fn popV128(g: Generator&, f: const Fn&, ty: Ty) -> Val {
    let vloc = local(g, f, VT_v128);
    lset(g, vloc);
    return shadowV128(g, f, ty, vloc);
}
fn ensureV128(g: Generator&, f: const Fn&, value: Val) -> u32 {
    if value.len == 2 {
        let first = w(g, value, 0);
        let second = w(g, value, 1);
        if isShadowWord(first) && (first & 3) == 0 && second == first + 1 {
            let at = shadowIndex(first);
            let shadow = g.s.v128_shadows[at];
            assert(at >= f.shadows_base && shadow.depth <= f.depth && shadow.is_wide);
            return shadow.vloc;
        }
        let float = localType(g, f, first) == VT_f64;
        lget(g, first);
        if float { simdOp(g, SIMD_f64x2_splat); } else { simdOp(g, SIMD_i64x2_splat); }
        if second != first {
            lget(g, second);
            simdLaneOp(g, if float { SIMD_f64x2_replace_lane } else { SIMD_i64x2_replace_lane }, 1);
        }
        let vloc = local(g, f, VT_v128);
        lset(g, vloc);
        return vloc;
    }
    let first = w(g, value, 0);
    let second = w(g, value, 1);
    let third = w(g, value, 2);
    let fourth = w(g, value, 3);
    if isShadowWord(first) && (first & 3) == 0 &&
        second == first + 1 && third == first + 2 && fourth == first + 3 {
        let at = shadowIndex(first);
        let shadow = g.s.v128_shadows[at];
        assert(at >= f.shadows_base && shadow.depth <= f.depth);
        return shadow.vloc;
    }
    let float = localType(g, f, first) == VT_f32;
    lget(g, first);
    if float { simdOp(g, SIMD_f32x4_splat); } else { simdOp(g, SIMD_i32x4_splat); }
    if second != first || third != first || fourth != first {
        var replace = SIMD_i32x4_replace_lane;
        if float { replace = SIMD_f32x4_replace_lane; }
        for lane in 1..4 {
            let word = w(g, value, lane);
            if word == first { continue; }
            lget(g, word);
            simdLaneOp(g, replace, lane as u8);
        }
    }
    let vloc = local(g, f, VT_v128);
    lset(g, vloc);
    return vloc;
}

fn wideLaneOpcode(op_: Op, float: bool) -> u32 {
    match op_ {
        add => { if float { return SIMD_f64x2_add; } return 0; },
        sub => { if float { return SIMD_f64x2_sub; } return 0; },
        mul => { if float { return SIMD_f64x2_mul; } return 0; },
        div => { if float { return SIMD_f64x2_div; } return 0; },
        abs => { if float { return SIMD_f64x2_abs; } return 0; },
        neg => { if float { return SIMD_f64x2_neg; } return 0; },
        ceil => { if float { return SIMD_f64x2_ceil; } return 0; },
        floor => { if float { return SIMD_f64x2_floor; } return 0; },
        trunc => { if float { return SIMD_f64x2_trunc; } return 0; },
        sqrt => { if float { return SIMD_f64x2_sqrt; } return 0; },
        min => { if float { return SIMD_f64x2_lt; } return 0; },
        max => { if float { return SIMD_f64x2_gt; } return 0; },
        equal => { if float { return SIMD_f64x2_eq; } return 0; },
        not_equal => { if float { return SIMD_f64x2_ne; } return 0; },
        less => { if float { return SIMD_f64x2_lt; } return 0; },
        less_equal => { if float { return SIMD_f64x2_le; } return 0; },
        greater => { if float { return SIMD_f64x2_gt; } return 0; },
        greater_equal => { if float { return SIMD_f64x2_ge; } return 0; },
        bit_and => { return SIMD_v128_and; },
        bit_or => { return SIMD_v128_or; },
        bit_xor => { return SIMD_v128_xor; },
        bit_not => { return SIMD_v128_not; },
        bit_andnot => { return SIMD_v128_andnot; },
        any_true => { return SIMD_v128_any_true; },
        all_true => { return SIMD_i64x2_all_true; },
        i8x16_add => { return SIMD_i8x16_add; },
        i8x16_sub => { return SIMD_i8x16_sub; },
        i8x16_min_u => { return SIMD_i8x16_min_u; },
        i8x16_max_u => { return SIMD_i8x16_max_u; },
        i8x16_eq => { return SIMD_i8x16_eq; },
        i8x16_avgr_u => { return SIMD_i8x16_avgr_u; },
        i8x16_bitmask => { return SIMD_i8x16_bitmask; },
        i8x16_narrow_u => { return SIMD_i8x16_narrow_i16x8_u; },
        i16x8_extend_low_u => { return SIMD_i16x8_extend_low_i8x16_u; },
        i16x8_extend_high_u => { return SIMD_i16x8_extend_high_i8x16_u; },
        i16x8_add => { return SIMD_i16x8_add; },
        i16x8_sub => { return SIMD_i16x8_sub; },
        i16x8_mul => { return SIMD_i16x8_mul; },
        i16x8_shl => { return SIMD_i16x8_shl; },
        i16x8_shr_u => { return SIMD_i16x8_shr_u; },
        i16x8_shr_s => { return SIMD_i16x8_shr_s; },
        i16x8_min_u => { return SIMD_i16x8_min_u; },
        i16x8_max_u => { return SIMD_i16x8_max_u; },
        _ => { return 0; },
    }
}

fn laneOpcode(op_: Op, float: bool) -> u32 {
    match op_ {
        add => { if float { return SIMD_f32x4_add; } return SIMD_i32x4_add; },
        sub => { if float { return SIMD_f32x4_sub; } return SIMD_i32x4_sub; },
        mul => { if float { return SIMD_f32x4_mul; } return SIMD_i32x4_mul; },
        div => { return SIMD_f32x4_div; },
        abs => { return SIMD_f32x4_abs; },
        neg => { return SIMD_f32x4_neg; },
        ceil => { return SIMD_f32x4_ceil; },
        floor => { return SIMD_f32x4_floor; },
        trunc => { return SIMD_f32x4_trunc; },
        sqrt => { return SIMD_f32x4_sqrt; },
        min => { if float { return SIMD_f32x4_lt; } return SIMD_i32x4_min_u; },
        max => { if float { return SIMD_f32x4_gt; } return SIMD_i32x4_max_u; },
        equal => { if float { return SIMD_f32x4_eq; } return SIMD_i32x4_eq; },
        not_equal => { if float { return SIMD_f32x4_ne; } return SIMD_i32x4_ne; },
        less => { if float { return SIMD_f32x4_lt; } return SIMD_i32x4_lt_u; },
        less_equal => { if float { return SIMD_f32x4_le; } return SIMD_i32x4_le_u; },
        greater => { if float { return SIMD_f32x4_gt; } return SIMD_i32x4_gt_u; },
        greater_equal => { if float { return SIMD_f32x4_ge; } return SIMD_i32x4_ge_u; },
        bit_and => { return SIMD_v128_and; },
        bit_or => { return SIMD_v128_or; },
        bit_xor => { return SIMD_v128_xor; },
        bit_not => { return SIMD_v128_not; },
        bit_andnot => { return SIMD_v128_andnot; },
        shift_left => { return SIMD_i32x4_shl; },
        shift_right => { return SIMD_i32x4_shr_u; },
        shift_right_signed => { return SIMD_i32x4_shr_s; },
        any_true => { return SIMD_v128_any_true; },
        all_true => { return SIMD_i32x4_all_true; },
        convert_u32_f32 => { return SIMD_f32x4_convert_i32x4_u; },
        convert_i32_f32 => { return SIMD_f32x4_convert_i32x4_s; },
        convert_f32_u32 => { return SIMD_i32x4_trunc_sat_f32x4_u; },
        convert_f32_i32 => { return SIMD_i32x4_trunc_sat_f32x4_s; },
        _ => { return 0; },
    }
}
fn laneSelectorOperand(op_: Op, left: u32, right: u32) -> u32 {
    match op_ {
        broadcast => { return right; },
        shuffle, swizzle => { return left; },
        _ => { return 0; },
    }
}
fn literalLaneSelector(m: const Module&, selectors: u32, broadcast: bool, lane: i64) -> ConstU32, bool {
    if selectors == 0 { return ConstU32 {}, false; }
    var source = selectors;
    if !broadcast {
        let node = m.node(selectors);
        if node.tag != squid_check_core::Tag.product || node.b != 4 { return ConstU32 {}, false; }
        source = m.children(selectors)[lane];
    }
    let literal = m.node(source);
    if literal.tag != squid_check_core::Tag.constant { return ConstU32 {}, false; }
    return ConstU32 { value: literal.a, unit: m.unit, node: source }, true;
}
fn lanePermutation(g: Generator&, f: Fn&, op_: Op, left: Val, right: Val, result_ty: Ty, id: u32, selector_node: u32) -> Val, Error {
    let broadcast = op_ == squid_check_core::Op.broadcast;
    var selectors = left;
    var candidates = right;
    if broadcast { selectors = right; candidates = left; }

    var indices: u32[4] = [0; 4];
    var facts: ConstU32[4] = [ConstU32 {}; 4];
    var constant = true;
    for lane in 0..4 {
        var sel = 0;
        if !broadcast { sel = lane; }
        var fact, known = literalLaneSelector(g.units[f.unit - 1], selector_node, broadcast, lane);
        if !known { fact, known = constU32(f, w(g, selectors, sel)); }
        if !known { constant = false; break; }
        facts[lane] = fact;
        if fact.value < candidates.len { indices[lane] = fact.value; }
    }
    if constant {
        for fact in facts { useConstU32(fact); }
        let first = ensureV128(g, f, Val { candidates.ty, candidates.start, 4 });
        var second = first;
        if candidates.len == 8 { second = ensureV128(g, f, Val { candidates.ty, candidates.start + 4, 4 }); }
        lget(g, first);
        lget(g, second);
        emitI32x4Shuffle(g, indices[0], indices[1], indices[2], indices[3]);
        return popV128(g, f, result_ty), squid_direct_types::Error.none;
    }

    // A selector arriving via a scalar ABI boundary may have lost its
    // literal fact. Preserve the scalar fallback's lane-zero default.
    let result, error = fresh(g, f, result_ty, id);
    if error != squid_direct_types::Error.none { return result, error; }
    let chosen = local(g, f, localType(g, f, w(g, candidates, 0)));
    for lane in 0..4 {
        var sel = 0;
        if !broadcast { sel = lane; }
        let selector = w(g, selectors, sel);
        lget(g, w(g, candidates, 0));
        for position in 1..(candidates.len as i64) {
            lset(g, chosen);
            lget(g, w(g, candidates, position));
            lget(g, chosen);
            lget(g, selector);
            i32Const(g, position as u32);
            op(g, OP_i32_eq);
            op(g, OP_select);
        }
        lset(g, w(g, result, lane));
    }
    return result, squid_direct_types::Error.none;
}

fn lanes(g: Generator&, f: Fn&, op_: Op, left: Val, right: Val, result_ty: Ty, id: u32, elide_nan: bool, selector_node: u32) -> Val, Error {
    if left.len == 2 {
        let a = ensureV128(g, f, left);
        if op_ == squid_check_core::Op.bits || op_ == squid_check_core::Op.from_bits {
            return shadowV128(g, f, result_ty, a), squid_direct_types::Error.none;
        }
        if right.len == 4 {
            let b = ensureV128(g, f, Val { right.ty, right.start, 2 });
            let c = ensureV128(g, f, Val { right.ty, right.start + 2, 2 });
            match op_ {
                select => {
                    lget(g, b); lget(g, c); lget(g, a);
                    simdOp(g, SIMD_v128_bitselect);
                },
                relaxed_madd, relaxed_nmadd => {
                    let neg = op_ == squid_check_core::Op.relaxed_nmadd;
                    if squid_direct_writer::relaxedSimdEnabled() {
                        lget(g, a); lget(g, b); lget(g, c);
                        if neg { simdOp(g, SIMD_f64x2_relaxed_nmadd); } else { simdOp(g, SIMD_f64x2_relaxed_madd); }
                    } else {
                        if neg { lget(g, c); }
                        lget(g, a); lget(g, b);
                        simdOp(g, SIMD_f64x2_mul);
                        if neg { simdOp(g, SIMD_f64x2_sub); } else { lget(g, c); simdOp(g, SIMD_f64x2_add); }
                    }
                },
                _ => { return neverVal(), g.fail(g.units[f.unit - 1], id, "unsupported paired wide lane operation"); },
            }
        } else {
            let float = localType(g, f, w(g, left, 0)) == VT_f64;
            let opcode = wideLaneOpcode(op_, float);
            if opcode == 0 { return neverVal(), g.fail(g.units[f.unit - 1], id, "unsupported wide lane operation"); }
            let float_minmax = float && (op_ == squid_check_core::Op.min || op_ == squid_check_core::Op.max);
            if right.len == 2 {
                let b = ensureV128(g, f, right);
                if float_minmax { lget(g, a); lget(g, b); }
                lget(g, a); lget(g, b);
            } else {
                lget(g, a);
                if right.len == 1 { lget(g, w(g, right, 0)); }
            }
            simdOp(g, opcode);
            if float_minmax { simdOp(g, SIMD_v128_bitselect); }
        }
        if op_ == squid_check_core::Op.any_true || op_ == squid_check_core::Op.all_true || op_ == squid_check_core::Op.i8x16_bitmask {
            return pop(g, f, result_ty, id);
        }
        if !elide_nan && !f.defer_f32_nan && canonicalV128Producer(op_) && localType(g, f, w(g, left, 0)) == VT_f64 {
            canonicalizeF64x2(g, f);
        }
        return popV128(g, f, result_ty), squid_direct_types::Error.none;
    }
    if left.len != 4 {
        return neverVal(), g.fail(g.units[f.unit - 1], id, "lane operation requires a four-word tuple");
    }
    if op_ == squid_check_core::Op.shuffle || op_ == squid_check_core::Op.swizzle || op_ == squid_check_core::Op.broadcast {
        return lanePermutation(g, f, op_, left, right, result_ty, id, selector_node);
    }
    let a = ensureV128(g, f, left);
    if op_ == squid_check_core::Op.bits || op_ == squid_check_core::Op.from_bits {
        return shadowV128(g, f, result_ty, a), squid_direct_types::Error.none;
    }
    if right.len == 8 {
        let b = ensureV128(g, f, Val { right.ty, right.start, 4 });
        let c = ensureV128(g, f, Val { right.ty, right.start + 4, 4 });
        match op_ {
            select => {
                // Wasm bitselect(yes, no, mask) takes yes for set mask bits.
                lget(g, b); lget(g, c); lget(g, a);
                simdOp(g, SIMD_v128_bitselect);
            },
            relaxed_madd, relaxed_nmadd => {
                let neg = op_ == squid_check_core::Op.relaxed_nmadd;
                if squid_direct_writer::relaxedSimdEnabled() {
                    lget(g, a); lget(g, b); lget(g, c);
                    if neg { simdOp(g, SIMD_f32x4_relaxed_nmadd); } else { simdOp(g, SIMD_f32x4_relaxed_madd); }
                } else {
                    if neg { lget(g, c); }
                    lget(g, a); lget(g, b);
                    simdOp(g, SIMD_f32x4_mul);
                    if neg { simdOp(g, SIMD_f32x4_sub); } else { lget(g, c); simdOp(g, SIMD_f32x4_add); }
                }
            },
            _ => { return neverVal(), g.fail(g.units[f.unit - 1], id, "unsupported paired lane operation"); },
        }
    } else {
        let float = localType(g, f, w(g, left, 0)) == VT_f32;
        let opcode = laneOpcode(op_, float);
        if opcode == 0 { return neverVal(), g.fail(g.units[f.unit - 1], id, "unsupported lane operation"); }
        let float_minmax = float && (op_ == squid_check_core::Op.min || op_ == squid_check_core::Op.max);
        if right.len == 4 {
            let b = ensureV128(g, f, right);
            if float_minmax { lget(g, a); lget(g, b); }
            lget(g, a); lget(g, b);
        } else {
            lget(g, a);
            if right.len == 1 { lget(g, w(g, right, 0)); }
        }
        simdOp(g, opcode);
        // Match `if a < b then a else b` (or >), including unordered
        // operands and ties between signed zeros. Keep the selected bits.
        if float_minmax { simdOp(g, SIMD_v128_bitselect); }
    }
    if op_ == squid_check_core::Op.any_true || op_ == squid_check_core::Op.all_true {
        return pop(g, f, result_ty, id);
    }
    if !elide_nan && !f.defer_f32_nan && canonicalV128Producer(op_) && localType(g, f, w(g, left, 0)) == VT_f32 {
        canonicalizeF32x4(g, f, 0xffffffff);
    }
    return popV128(g, f, result_ty), squid_direct_types::Error.none;
}
// Emits the machine operation for `op` on operands already on the stack.
// F32/F64 arithmetic & rounding producers (+, -, *, /, sqrt, floor, ceil, trunc)
// canonicalize NaN outputs unless `canonicalize` is false (peephole-elided into
// a canonicalizing or NaN-payload-ignoring consumer).
fn scalarOp(g: Generator&, f: const Fn&, op_: Op, operand: Ty, id: u32, canonicalize: bool = true, result: Ty = 0) -> Error {
    let m .= g.units[f.unit - 1];
    let tag = g.types.node(operand).tag;
    let float = tag == squid_direct_types::Tag.f32_;
    if !isScalarTag(tag) {
        g.failOpen(m, id);
        g.put(opName(op_));
        g.put(" on a ");
        g.put(squid_direct_types::tagName(tag));
        g.put(" operand at a ");
        g.put(squid_direct_emit::nodeTagName(m.node(id).tag));
        g.put(" node");
        return g.failClose();
    }
    if op_ == squid_check_core::Op.numeric_convert { return convertScalar(g, f, operand, result, id); }
    if tag == squid_direct_types::Tag.f64_ { return scalarF64(g, f, op_, id, canonicalize); }
    if tag == squid_direct_types::Tag.u64_ || tag == squid_direct_types::Tag.i64_ {
        return scalarI64(g, f, op_, tag == squid_direct_types::Tag.i64_, id);
    }
    let byte_ = tag == squid_direct_types::Tag.u8_;
    let signed = tag == squid_direct_types::Tag.i32_;
    if byte_ && (op_ == squid_check_core::Op.shift_left || op_ == squid_check_core::Op.shift_right) {
        i32Const(g, 7);
        op(g, OP_i32_and);
    }
    var code: u8 = 0;
    match op_ {
        add => { if float { code = OP_f32_add; } else { code = OP_i32_add; } },
        sub => { if float { code = OP_f32_sub; } else { code = OP_i32_sub; } },
        mul => { if float { code = OP_f32_mul; } else { code = OP_i32_mul; } },
        div => { if float { code = OP_f32_div; } else { code = if signed { OP_i32_div_s } else { OP_i32_div_u }; } },
        rem => { if float { return g.fail(m, id, "F32 remainder"); } code = if signed { OP_i32_rem_s } else { OP_i32_rem_u }; },
        equal => { if float { code = OP_f32_eq; } else { code = OP_i32_eq; } },
        not_equal => { if float { code = OP_f32_ne; } else { code = OP_i32_ne; } },
        less => { if float { code = OP_f32_lt; } else { code = if signed { OP_i32_lt_s } else { OP_i32_lt_u }; } },
        less_equal => { if float { code = OP_f32_le; } else { code = if signed { OP_i32_le_s } else { OP_i32_le_u }; } },
        greater => { if float { code = OP_f32_gt; } else { code = if signed { OP_i32_gt_s } else { OP_i32_gt_u }; } },
        greater_equal => { if float { code = OP_f32_ge; } else { code = if signed { OP_i32_ge_s } else { OP_i32_ge_u }; } },
        bit_and => { code = OP_i32_and; },
        bit_or => { code = OP_i32_or; },
        bit_xor => { code = OP_i32_xor; },
        shift_left => { code = OP_i32_shl; },
        shift_right => { code = if signed { OP_i32_shr_s } else { OP_i32_shr_u }; },
        shift_right_signed => { code = OP_i32_shr_s; },
        neg => {
            if float { code = OP_f32_neg; }
            else {
                // 0 - x: the operand is already on the stack.
                let value = local32(g, f);
                lset(g, value);
                i32Const(g, 0);
                lget(g, value);
                op(g, OP_i32_sub);
                return squid_direct_types::Error.none;
            }
        },
        abs => {
            if float { code = OP_f32_abs; }
            else {
                if signed { signedAbs(g, f, false); }
                return squid_direct_types::Error.none;
            }
        },
        ceil => { code = OP_f32_ceil; },
        floor => { code = OP_f32_floor; },
        trunc => { code = OP_f32_trunc; },
        sqrt => { code = OP_f32_sqrt; },
        min => { code = OP_f32_min; },
        max => { code = OP_f32_max; },
        convert_u32_f32 => { code = OP_f32_convert_i32_u; },
        convert_f32_u32 => {
            op(g, OP_prefix_fc);
            uleb(g, 1); // i32.trunc_sat_f32_u
            return squid_direct_types::Error.none;
        },
        convert_f32_i32 => {
            op(g, OP_prefix_fc);
            uleb(g, 0); // i32.trunc_sat_f32_s
            return squid_direct_types::Error.none;
        },
        convert_i32_f32 => { code = OP_f32_convert_i32_s; },
        bit_andnot => {
            // left & ~right, both already on the stack.
            i32Const(g, if byte_ { 0xff } else { 0xffffffff });
            op(g, OP_i32_xor);
            op(g, OP_i32_and);
            return squid_direct_types::Error.none;
        },
        bit_not => {
            i32Const(g, if byte_ { 0xff } else { 0xffffffff });
            op(g, OP_i32_xor);
            return squid_direct_types::Error.none;
        },
        bits => { code = OP_i32_reinterpret_f32; },
        from_bits => { code = if tag == squid_direct_types::Tag.u64_ { OP_f64_reinterpret_i64 } else { OP_f32_reinterpret_i32 }; },
        not_ => { code = OP_i32_eqz; },
        _ => {
            g.failOpen(m, id);
            g.put("scalar operation ");
            g.put(opName(op_));
            return g.failClose();
        },
    }
    op(g, code);
    if byte_ && (op_ == squid_check_core::Op.add || op_ == squid_check_core::Op.sub || op_ == squid_check_core::Op.mul || op_ == squid_check_core::Op.shift_left) { maskU8(g); }
    if float && canonicalize && isCanonicalF32Op(op_) { canonicalizeF32Stack(g, f); }
    return squid_direct_types::Error.none;
}

recursive fn logical(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let n = g.units[f.unit - 1].node(id);
    let result, error = fresh(g, f, squid_direct_types::boolean, id);
    if error != squid_direct_types::Error.none { return result, error; }
    let left, error = expr(g, f, n.a);
    if error != squid_direct_types::Error.none { return left, error; }
    push(g, left);
    // The right operand runs only on one branch, so it may diverge there
    // without making the whole expression diverge.
    if n.op == squid_check_core::Op.and_ {
        let opened = open(g, f, OP_if_);
        recordCondBounds(g, f, g.units[f.unit - 1], n.a, false);
        let right, error = stmt(g, f, n.b);
        if error != squid_direct_types::Error.none { return right, error; }
        if right.ty != squid_direct_types::never {
            let copied = copy(g, f, right, result, id);
            if copied != squid_direct_types::Error.none { return neverVal(), copied; }
        }
        popCheckedArraysAt(f, opened);
        op(g, OP_else_);
        i32Const(g, 0);
        lset(g, w(g, result, 0));
    } else {
        let opened = open(g, f, OP_if_);
        i32Const(g, 1);
        lset(g, w(g, result, 0));
        popCheckedArraysAt(f, opened);
        op(g, OP_else_);
        recordCondBounds(g, f, g.units[f.unit - 1], n.a, true);
        let right, error = stmt(g, f, n.b);
        if error != squid_direct_types::Error.none { return right, error; }
        if right.ty != squid_direct_types::never {
            let copied = copy(g, f, right, result, id);
            if copied != squid_direct_types::Error.none { return neverVal(), copied; }
        }
    }
    close(g, f);
    return result, squid_direct_types::Error.none;
}
