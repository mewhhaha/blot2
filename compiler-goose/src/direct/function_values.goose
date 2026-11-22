// Scalar and lane arithmetic, logic and conditionals of the direct backend's
// function emitter (compiler/src/direct/function.zig).
namespace blot_direct_function;
import .function;
type Op = blot_check_core::Op;

fn opName(value: Op) -> Chars {
    match value { const for <N, V> in variants<blot_check_core::Op> { V => { return N; }, } }
}
fn isScalarTag(tag: blot_direct_types::Tag) -> bool {
    return tag == blot_direct_types::Tag.u32_ || tag == blot_direct_types::Tag.f32_ || tag == blot_direct_types::Tag.boolean;
}
recursive fn scalar(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let left, error = expr(g, f, n.a);
    if error != blot_direct_types::Error.none { return left, error; }
    var has_right = false;
    var right = neverVal();
    if n.b != 0 {
        let value, error = expr(g, f, n.b);
        if error != blot_direct_types::Error.none { return value, error; }
        has_right = true;
        right = value;
    }
    var tag = tagOf(g, left.ty);
    var operand_left = left;
    var operand_right = right;
    // Opaque wrappers of a scalar are erased at run time.
    if tag == blot_direct_types::Tag.nominal {
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
        let emitted = scalarOp(g, f, n.op, operand_left.ty, id);
        if emitted != blot_direct_types::Error.none { return neverVal(), emitted; }
        let result, error = typeOf(g, f, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        return pop(g, f, result, id);
    }
    if n.c == 1 && !isScalarTag(tag) && tag != blot_direct_types::Tag.tuple {
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
            g.put(blot_direct_types::tagName(tag));
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
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        let rest, error = restType(g, f, callee, arguments.len, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        return callTarget(g, f, target, arguments, callee, rest, id);
    }
    let result, error = typeOf(g, f, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    if tag == blot_direct_types::Tag.tuple { return lanes(g, f, n.op, left, has_right, right, result, id); }
    // Machine operations take operands of one type; the checker should reject
    // a mix, so never emit one.
    if has_right && right.ty != left.ty {
        g.failOpenCode(m, id, blot_check_diagnostic_code::Code.type_mismatch);
        g.put(opName(n.op));
        g.put(" applied to a ");
        g.put(blot_direct_types::tagName(tagOf(g, left.ty)));
        g.put(" and a ");
        g.put(blot_direct_types::tagName(tagOf(g, right.ty)));
        return neverVal(), g.failClose();
    }
    var machine = n.op;
    if n.c == 1 {
        let member, error = scalarMember(g, f, m, left.ty, 0, n.op, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        machine = member;
    }
    push(g, left);
    if has_right { push(g, right); }
    let emitted = scalarOp(g, f, machine, left.ty, id);
    if emitted != blot_direct_types::Error.none { return neverVal(), emitted; }
    return pop(g, f, result, id);
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
    if !has_identity { return standard, blot_direct_types::Error.none; }
    var operator = blot_check_types::Operator.none;
    if member == 0 {
        let found, has_operator = operatorOf(standard);
        if !has_operator { return standard, blot_direct_types::Error.none; }
        operator = found;
    }
    let target, has_target = g.dispatchTarget(catalog, identity, member, operator);
    if !has_target {
        g.failOpenCode(g.units[f.unit - 1], id, blot_check_diagnostic_code::Code.missing_associated);
        g.put(blot_direct_types::tagName(tagOf(g, receiver)));
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
    if !g.hasUnit(target.unit) { return standard, blot_direct_types::Error.none; }
    let defining .= g.units[target.unit - 1];
    let alias, has_alias = primitiveAlias(defining, target.binding);
    if !has_alias { return standard, blot_direct_types::Error.none; }
    g.recordInlined(target.unit, target.binding);
    let primitive = defining.primitive(alias);
    if primitive.kind == blot_check_core::PrimitiveKind.scalar && primitive.op != blot_check_core::Op.none { return primitive.op, blot_direct_types::Error.none; }
    return standard, blot_direct_types::Error.none;
}
// The scalar payload of a single-constructor value, if it has one.
fn scalarPayload(g: Generator&, value: Val) -> Val, bool {
    if tagOf(g, value.ty) != blot_direct_types::Tag.nominal { return value, false; }
    let cases, error = g.types.variants(value.ty);
    if error != blot_direct_types::Error.none { return value, false; }
    if cases.len != 1 { return value, false; }
    let payload = g.types.variant_payloads[cases.payloads];
    if !isScalarTag(tagOf(g, payload)) { return value, false; }
    return Val { payload, value.start, value.len }, true;
}
// Four-lane operations on (U32|F32)x4 products, one lane at a time.
fn lanes(g: Generator&, f: Fn&, op_: Op, left: Val, has_right: bool, right: Val, result_ty: Ty, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let shape = g.types.node(left.ty);
    if shape.b != 4 {
        g.failOpen(m, id);
        g.put("lane operation on a ");
        g.putNumber(shape.b);
        g.put("-tuple");
        return neverVal(), g.failClose();
    }
    let lane = g.types.words[shape.a];
    let float = tagOf(g, lane) == blot_direct_types::Tag.f32_;
    let result, error = fresh(g, f, result_ty, id);
    if error != blot_direct_types::Error.none { return result, error; }
    match op_ {
        any_true, all_true => {
            i32Const(g, boolWord(op_ == blot_check_core::Op.all_true));
            for index in 0..(left.len as i64) {
                lget(g, w(g, left, index));
                i32Const(g, 0);
                op(g, OP_i32_ne);
                if op_ == blot_check_core::Op.all_true { op(g, OP_i32_and); } else { op(g, OP_i32_or); }
            }
            lset(g, w(g, result, 0));
            return result, blot_direct_types::Error.none;
        },
        select => {
            // mask selects bits of the first product, the rest from the second.
            if !has_right { return neverVal(), g.fail(m, id, "select without operands"); }
            for index in 0..4 {
                let mask = w(g, left, index);
                let yes = w(g, right, index);
                let no = w(g, right, index + 4);
                let is_float = localType(g, f, yes) == VT_f32;
                lget(g, yes);
                if is_float { op(g, OP_i32_reinterpret_f32); }
                lget(g, mask);
                op(g, OP_i32_and);
                lget(g, no);
                if is_float { op(g, OP_i32_reinterpret_f32); }
                lget(g, mask);
                i32Const(g, 0xffffffff);
                op(g, OP_i32_xor);
                op(g, OP_i32_and);
                op(g, OP_i32_or);
                if is_float { op(g, OP_f32_reinterpret_i32); }
                lset(g, w(g, result, index));
            }
            return result, blot_direct_types::Error.none;
        },
        relaxed_madd, relaxed_nmadd => {
            // left * b + c (nmadd: c - left * b), with (b, c) the right pair.
            if !has_right { return neverVal(), g.fail(m, id, "multiply-add without operands"); }
            if right.len != 8 {
                g.failOpen(m, id);
                g.put("multiply-add with a ");
                g.putNumber(right.len);
                g.put("-word operand");
                return neverVal(), g.failClose();
            }
            for index in 0..4 {
                if op_ == blot_check_core::Op.relaxed_nmadd { lget(g, w(g, right, index + 4)); }
                lget(g, w(g, left, index));
                lget(g, w(g, right, index));
                let multiplied = scalarOp(g, f, blot_check_core::Op.mul, lane, id);
                if multiplied != blot_direct_types::Error.none { return neverVal(), multiplied; }
                if op_ == blot_check_core::Op.relaxed_madd {
                    lget(g, w(g, right, index + 4));
                    let added = scalarOp(g, f, blot_check_core::Op.add, lane, id);
                    if added != blot_direct_types::Error.none { return neverVal(), added; }
                } else {
                    let subtracted = scalarOp(g, f, blot_check_core::Op.sub, lane, id);
                    if subtracted != blot_direct_types::Error.none { return neverVal(), subtracted; }
                }
                lset(g, w(g, result, index));
            }
            return result, blot_direct_types::Error.none;
        },
        shuffle, swizzle, broadcast => {
            // Lane selectors index the candidate words: shuffle's two products
            // (0-3, 4-7), swizzle's one, broadcast's one lane.
            if !has_right {
                g.failOpen(m, id);
                g.put(opName(op_));
                g.put(" without operands");
                return neverVal(), g.failClose();
            }
            var candidates = right;
            if op_ == blot_check_core::Op.broadcast { candidates = left; }
            for index in 0..4 {
                var selector = w(g, left, index);
                if op_ == blot_check_core::Op.broadcast { selector = w(g, right, 0); }
                lget(g, w(g, candidates, 0));
                for position in 1..(candidates.len as i64) {
                    let candidate = w(g, candidates, position);
                    let value = local(g, f, localType(g, f, candidate));
                    lset(g, value);
                    lget(g, candidate);
                    lget(g, value);
                    lget(g, selector);
                    i32Const(g, position as u32);
                    op(g, OP_i32_eq);
                    op(g, OP_select);
                }
                lset(g, w(g, result, index));
            }
            return result, blot_direct_types::Error.none;
        },
        _ => {},
    }
    // A scalar right operand (a shift count) applies to every lane.
    var right_words: u32[4] = [0; 4];
    if has_right {
        if right.len == 1 { for index in 0..4 { right_words[index] = w(g, right, 0); } }
        else {
            if right.len != 4 {
                g.failOpen(m, id);
                g.put("lane operation with a ");
                g.putNumber(right.len);
                g.put("-word right operand");
                return neverVal(), g.failClose();
            }
            for index in 0..4 { right_words[index] = w(g, right, index); }
        }
    }
    for index in 0..4 {
        match op_ {
            bits, from_bits => {
                lget(g, w(g, left, index));
                if op_ == blot_check_core::Op.bits { op(g, OP_i32_reinterpret_f32); } else { op(g, OP_f32_reinterpret_i32); }
            },
            min, max => {
                // The prelude's `if a < b then a else b`, NaN and zero signs included.
                if !has_right { return neverVal(), g.fail(m, id, "lane operation without a right operand"); }
                let r = right_words[index];
                lget(g, w(g, left, index));
                lget(g, r);
                lget(g, w(g, left, index));
                lget(g, r);
                if float { if op_ == blot_check_core::Op.min { op(g, OP_f32_lt); } else { op(g, OP_f32_gt); } }
                else { if op_ == blot_check_core::Op.min { op(g, OP_i32_lt_u); } else { op(g, OP_i32_gt_u); } }
                op(g, OP_select);
            },
            equal, not_equal, less, less_equal, greater, greater_equal => {
                if !has_right { return neverVal(), g.fail(m, id, "comparison without a right operand"); }
                let r = right_words[index];
                // A lane mask: all ones where the comparison holds.
                i32Const(g, 0);
                lget(g, w(g, left, index));
                lget(g, r);
                let compared = scalarOp(g, f, op_, lane, id);
                if compared != blot_direct_types::Error.none { return neverVal(), compared; }
                op(g, OP_i32_sub);
            },
            _ => {
                lget(g, w(g, left, index));
                if has_right { lget(g, right_words[index]); }
                let applied = scalarOp(g, f, op_, lane, id);
                if applied != blot_direct_types::Error.none { return neverVal(), applied; }
            },
        }
        lset(g, w(g, result, index));
    }
    return result, blot_direct_types::Error.none;
}
// Emits the machine operation for `op` on operands already on the stack.
fn scalarOp(g: Generator&, f: const Fn&, op_: Op, operand: Ty, id: u32) -> Error {
    let m .= g.units[f.unit - 1];
    let tag = g.types.node(operand).tag;
    let float = tag == blot_direct_types::Tag.f32_;
    if !isScalarTag(tag) {
        g.failOpen(m, id);
        g.put(opName(op_));
        g.put(" on a ");
        g.put(blot_direct_types::tagName(tag));
        g.put(" operand at a ");
        g.put(blot_direct_emit::nodeTagName(m.node(id).tag));
        g.put(" node");
        return g.failClose();
    }
    var code: u8 = 0;
    match op_ {
        add => { if float { code = OP_f32_add; } else { code = OP_i32_add; } },
        sub => { if float { code = OP_f32_sub; } else { code = OP_i32_sub; } },
        mul => { if float { code = OP_f32_mul; } else { code = OP_i32_mul; } },
        div => { if float { code = OP_f32_div; } else { code = OP_i32_div_u; } },
        rem => { if float { return g.fail(m, id, "F32 remainder"); } code = OP_i32_rem_u; },
        equal => { if float { code = OP_f32_eq; } else { code = OP_i32_eq; } },
        not_equal => { if float { code = OP_f32_ne; } else { code = OP_i32_ne; } },
        less => { if float { code = OP_f32_lt; } else { code = OP_i32_lt_u; } },
        less_equal => { if float { code = OP_f32_le; } else { code = OP_i32_le_u; } },
        greater => { if float { code = OP_f32_gt; } else { code = OP_i32_gt_u; } },
        greater_equal => { if float { code = OP_f32_ge; } else { code = OP_i32_ge_u; } },
        bit_and => { code = OP_i32_and; },
        bit_or => { code = OP_i32_or; },
        bit_xor => { code = OP_i32_xor; },
        shift_left => { code = OP_i32_shl; },
        shift_right => { code = OP_i32_shr_u; },
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
                return blot_direct_types::Error.none;
            }
        },
        abs => { if float { code = OP_f32_abs; } else { return blot_direct_types::Error.none; } },
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
            return blot_direct_types::Error.none;
        },
        convert_f32_i32 => {
            op(g, OP_prefix_fc);
            uleb(g, 0); // i32.trunc_sat_f32_s
            return blot_direct_types::Error.none;
        },
        convert_i32_f32 => { code = OP_f32_convert_i32_s; },
        bit_andnot => {
            // left & ~right, both already on the stack.
            i32Const(g, 0xffffffff);
            op(g, OP_i32_xor);
            op(g, OP_i32_and);
            return blot_direct_types::Error.none;
        },
        bit_not => {
            i32Const(g, 0xffffffff);
            op(g, OP_i32_xor);
            return blot_direct_types::Error.none;
        },
        not_ => { code = OP_i32_eqz; },
        _ => {
            g.failOpen(m, id);
            g.put("scalar operation ");
            g.put(opName(op_));
            return g.failClose();
        },
    }
    op(g, code);
    return blot_direct_types::Error.none;
}

recursive fn logical(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let n = g.units[f.unit - 1].node(id);
    let result, error = fresh(g, f, blot_direct_types::boolean, id);
    if error != blot_direct_types::Error.none { return result, error; }
    let left, error = expr(g, f, n.a);
    if error != blot_direct_types::Error.none { return left, error; }
    push(g, left);
    // The right operand runs only on one branch, so it may diverge there
    // without making the whole expression diverge.
    if n.op == blot_check_core::Op.and_ {
        let opened = open(g, f, OP_if_);
        let right, error = stmt(g, f, n.b);
        if error != blot_direct_types::Error.none { return right, error; }
        if right.ty != blot_direct_types::never {
            let copied = copy(g, f, right, result, id);
            if copied != blot_direct_types::Error.none { return neverVal(), copied; }
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
        let right, error = stmt(g, f, n.b);
        if error != blot_direct_types::Error.none { return right, error; }
        if right.ty != blot_direct_types::never {
            let copied = copy(g, f, right, result, id);
            if copied != blot_direct_types::Error.none { return neverVal(), copied; }
        }
    }
    close(g, f);
    return result, blot_direct_types::Error.none;
}
