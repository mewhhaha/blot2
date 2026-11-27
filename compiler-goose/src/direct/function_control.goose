// Conditionals, blocks, matches and loops of the direct backend's function
// emitter (compiler/src/direct/function.zig).
namespace squid_direct_function;
import .function;

// `count` empty result slots; the first one's index.
fn newSlots(g: Generator&, count: i64) -> u32 {
    let first = g.s.slots.len as u32;
    for at in 0..count { g.s.slots.push(squid_direct_emit::Slot {}); }
    return first;
}
fn resolveBoundLocal(g: Generator&, f: const Fn&, m: const Module&, node_id: u32) -> u32, bool {
    let b = localRef(m, node_id);
    if b != 0 {
        let _, is_cell = withCellType(g, f, b);
        if !is_cell {
            let v, ok = bindGet(g, f, b);
            if ok && tagOf(g, v.ty) == squid_direct_types::Tag.u32_ {
                return w(g, v, 0), true;
            }
        }
    }
    let n = m.node(node_id);
    var owner: u32 = 0;
    if n.tag == squid_check_core::Tag.project {
        let spelling = m.fieldSpelling(m.projection(n.b).field);
        if spelling.present && spelling.value == "length" {
            owner = localRef(m, n.a);
        }
    } else {
        owner = lengthReceiver(m, node_id);
    }
    if owner != 0 {
        let _, is_cell = withCellType(g, f, owner);
        if !is_cell {
            let hv, hok = bindGet(g, f, owner);
            if hok && tagOf(g, hv.ty) == squid_direct_types::Tag.array {
                let ca = findCheckedArray(f, w(g, hv, 0), w(g, hv, 1));
                if ca >= 0 {
                    return f.checked_arrays[ca].length, true;
                }
            }
        }
    }
    return 0, false;
}
fn resolveBoundSizedLength(m: const Module&, node_id: u32) -> TId {
    let n = m.node(node_id);
    if n.tag == squid_check_core::Tag.project {
        let spelling = m.fieldSpelling(m.projection(n.b).field);
        if spelling.present && spelling.value == "length" {
            return coreSizedLength(m, m.typeOf(n.a));
        }
    }
    if lengthReceiver(m, node_id) != 0 {
        let args = m.children(node_id);
        if args.len == 1 { return coreSizedLength(m, m.typeOf(args[0])); }
    }
    return 0;
}
recursive fn recordCondBounds(g: Generator&, f: Fn&, m: const Module&, cond_id: u32, invert: bool, depth: i64 = 0) {
    if cond_id == 0 || depth > 8 { return; }
    let cond = m.node(cond_id);
    if cond.tag == squid_check_core::Tag.logical {
        if !invert && cond.op == squid_check_core::Op.and_ {
            recordCondBounds(g, f, m, cond.a, false, depth + 1);
            recordCondBounds(g, f, m, cond.b, false, depth + 1);
        } else if invert && cond.op == squid_check_core::Op.or_ {
            recordCondBounds(g, f, m, cond.a, true, depth + 1);
            recordCondBounds(g, f, m, cond.b, true, depth + 1);
        }
        return;
    }
    if cond.tag == squid_check_core::Tag.scalar {
        var idx_node: u32 = 0;
        var bnd_node: u32 = 0;
        if !invert && cond.op == squid_check_core::Op.less {
            idx_node = cond.a; bnd_node = cond.b;
        } else if !invert && cond.op == squid_check_core::Op.greater {
            idx_node = cond.b; bnd_node = cond.a;
        } else if invert && cond.op == squid_check_core::Op.greater_equal {
            idx_node = cond.a; bnd_node = cond.b;
        } else if invert && cond.op == squid_check_core::Op.less_equal {
            idx_node = cond.b; bnd_node = cond.a;
        } else {
            return;
        }
        let idx_b = localRef(m, idx_node);
        if idx_b == 0 { return; }
        let _, ic = withCellType(g, f, idx_b);
        if ic { return; }
        let iv, iok = bindGet(g, f, idx_b);
        if !iok || tagOf(g, iv.ty) != squid_direct_types::Tag.u32_ { return; }
        let bnd_loc, bok = resolveBoundLocal(g, f, m, bnd_node);
        let sized_len_ty = resolveBoundSizedLength(m, bnd_node);
        if bok {
            recordCheckedBoundSized(f, w(g, iv, 0), bnd_loc, sized_len_ty);
        } else if sized_len_ty != 0 {
            recordCheckedBoundSized(f, w(g, iv, 0), 0xffffffff, sized_len_ty);
        }
    }
}
fn isPureSelectOp(op_: Op) -> bool {
    match op_ {
        add, sub, mul, equal, not_equal, less, less_equal, greater, greater_equal,
        bit_and, bit_or, bit_xor, shift_left, shift_right, shift_right_signed,
        neg, abs, ceil, floor, trunc, sqrt, min, max,
        convert_u32_f32, convert_f32_u32, convert_f32_i32, convert_i32_f32,
        numeric_convert, bits, from_bits,
        bit_andnot, bit_not, not_ => { return true; },
        _ => { return false; },
    }
}
// True when `id` is a `Tag.project` method on a concrete numeric/boolean scalar
// that resolves directly to a unary scalar primitive (e.g. `.to_u32`, `.to_u8`,
// `.to_u64`, `.to_i64`, `.to_f32`, `.to_f64`, `.abs`). Such projections never
// allocate, never mutate memory, and never resize storage.
fn isPureScalarProject(g: const Generator&, m: const Module&, id: u32) -> bool {
    let n = m.node(id);
    if n.tag != squid_check_core::Tag.project { return false; }
    let proj = m.projection(n.b);
    if m.projectionVariants(n.b).len != 0 { return false; }
    let receiver_node = m.types.node(m.typeOf(n.a));
    if !squid_check_types::isNumeric(receiver_node.tag) && receiver_node.tag != squid_check_types::Tag.boolean {
        return false;
    }
    let ident = squid_check_types::receiverIdentity(receiver_node);
    if !ident.present { return false; }
    let target, has_target = g.dispatchTarget(m, ident.value, proj.field, squid_check_types::Operator.none);
    if !has_target || !g.hasUnit(target.unit) { return false; }
    let tm .= g.units[target.unit - 1];
    let alias, is_prim = primitiveAlias(tm, target.binding);
    if !is_prim { return false; }
    let p = tm.primitive(alias);
    return p.kind == squid_check_core::PrimitiveKind.scalar && p.arity == 1;
}
recursive fn isPureSelectExpr(g: const Generator&, f: const Fn&, m: const Module&, id: u32, budget: i64&) -> bool {
    if id == 0 { return true; }
    if budget <= 0 { return false; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        constant => { return true; },
        reference => {
            let b = localRef(m, id);
            if b == 0 { return false; }
            let _, is_cell = withCellType(g, f, b);
            return !is_cell;
        },
        scalar => {
            if !isPureSelectOp(n.op) { return false; }
            return isPureSelectExpr(g, f, m, n.a, budget) && isPureSelectExpr(g, f, m, n.b, budget);
        },
        project => {
            if !isPureScalarProject(g, m, id) { return false; }
            return isPureSelectExpr(g, f, m, n.a, budget);
        },
        bind => {
            if n.c >= 2 || m.binding(n.a).scheme.variables.len != 0 { return false; }
            return isPureSelectExpr(g, f, m, n.b, budget);
        },
        suite, block_ => {
            for child in m.children(id) {
                if !isPureSelectExpr(g, f, m, child, budget) { return false; }
            }
            return true;
        },
        _ => { return false; },
    }
}
fn tryIfSelectConvert(g: Generator&, f: Fn&, id: u32) -> Val, bool, Error {
    var cond_id: u32 = 0;
    var then_id: u32 = 0;
    var else_id: u32 = 0;
    var is_stmt = false;
    var merge_count: i64 = 0;
    var m_then: u32[4] = [0; 4];
    var m_else: u32[4] = [0; 4];
    var m_res: u32[4] = [0; 4];
    var eligible = false;
    {
        let m .= g.units[f.unit - 1];
        let n = m.node(id);
        cond_id = n.a;
        then_id = n.b;
        else_id = n.c;
        is_stmt = n.tag == squid_check_core::Tag.if_stmt;
        let merges = m.branchMerges(id);
        if is_stmt && else_id == 0 && merges.len >= 1 && merges.len <= 4 {
            var budget: i64 = 24;
            if isPureSelectExpr(g, f, m, then_id, budget) {
                var all_ok = true;
                for merge, at in merges {
                    let _, ct = withCellType(g, f, merge.then_binding);
                    let _, ce = withCellType(g, f, merge.else_binding);
                    if ct || ce { all_ok = false; break; }
                    let ev, eok = bindGet(g, f, merge.else_binding);
                    if !eok || ev.len != 1 || !isScalarTag(tagOf(g, ev.ty)) { all_ok = false; break; }
                    m_then[at] = merge.then_binding;
                    m_else[at] = merge.else_binding;
                    m_res[at] = merge.result;
                }
                if all_ok {
                    merge_count = merges.len;
                    eligible = true;
                }
            }
        } else if !is_stmt && else_id != 0 && merges.len == 0 {
            var b1: i64 = 12;
            var b2: i64 = 12;
            if isPureSelectExpr(g, f, m, then_id, b1) && isPureSelectExpr(g, f, m, else_id, b2) {
                let rty, rerr = g.types.lower(m, m.typeOf(id), f.env);
                if rerr == squid_direct_types::Error.none && isScalarTag(tagOf(g, rty)) {
                    eligible = true;
                } else if rerr != squid_direct_types::Error.none {
                    g.dropFailure();
                }
            }
        }
    }
    if !eligible { return neverVal(), false, squid_direct_types::Error.none; }
    let condition, cerr = expr(g, f, cond_id);
    if cerr != squid_direct_types::Error.none { return condition, true, cerr; }
    if is_stmt {
        let then_val, terr = stmt(g, f, then_id);
        if terr != squid_direct_types::Error.none { return then_val, true, terr; }
        for at in 0..merge_count {
            let tv, tok = bindGet(g, f, m_then[at]);
            let ev, eok = bindGet(g, f, m_else[at]);
            assert(tok && eok && tv.len == 1 && ev.len == 1);
            let out_loc = local(g, f, localKindForScalar(g, ev.ty));
            lget(g, w(g, tv, 0));
            lget(g, w(g, ev, 0));
            lget(g, w(g, condition, 0));
            op(g, OP_select);
            lset(g, out_loc);
            bindPut(g, f, m_res[at], valOf1(g, ev.ty, out_loc));
        }
        return unitVal(), true, squid_direct_types::Error.none;
    }
    let tv, terr = expr(g, f, then_id);
    if terr != squid_direct_types::Error.none { return tv, true, terr; }
    let ev, eerr = expr(g, f, else_id);
    if eerr != squid_direct_types::Error.none { return ev, true, eerr; }
    let out_loc = local(g, f, localKindForScalar(g, tv.ty));
    lget(g, w(g, tv, 0));
    lget(g, w(g, ev, 0));
    lget(g, w(g, condition, 0));
    op(g, OP_select);
    lset(g, out_loc);
    return valOf1(g, tv.ty, out_loc), true, squid_direct_types::Error.none;
}
// 5A: Short-circuit `if (a or b): break` without materializing a temporary Bool local.
fn tryIfShortCircuitBreak(g: Generator&, f: Fn&, id: u32) -> Val, bool, Error {
    var lhs_id: u32 = 0;
    var rhs_id: u32 = 0;
    var body_id: u32 = 0;
    var cond_id: u32 = 0;
    {
        let m .= g.units[f.unit - 1];
        let n = m.node(id);
        if n.tag != squid_check_core::Tag.if_stmt || n.c != 0 || m.branchMerges(id).len != 0 {
            return neverVal(), false, squid_direct_types::Error.none;
        }
        if !isBreakBody(m, n.b) { return neverVal(), false, squid_direct_types::Error.none; }
        let cn = m.node(n.a);
        if cn.tag != squid_check_core::Tag.logical || cn.op != squid_check_core::Op.or_ {
            return neverVal(), false, squid_direct_types::Error.none;
        }
        cond_id = n.a;
        lhs_id = cn.a;
        rhs_id = cn.b;
        body_id = n.b;
    }
    var saved_ce: CheckedElem[8] = [CheckedElem {}; 8];
    let saved_ce_len = f.checked_elems_len;
    for ci in 0..saved_ce_len { saved_ce[ci] = f.checked_elems[ci]; }

    let lv, lerr = expr(g, f, lhs_id);
    if lerr != squid_direct_types::Error.none { return lv, true, lerr; }
    push(g, lv);
    let if1 = open(g, f, OP_if_);
    let _, b1err = stmt(g, f, body_id);
    if b1err != squid_direct_types::Error.none { return neverVal(), true, b1err; }
    popCheckedArraysAt(f, if1);
    close(g, f);
    f.checked_elems_len = saved_ce_len;
    for ci in 0..saved_ce_len { f.checked_elems[ci] = saved_ce[ci]; }
    recordCondBounds(g, f, g.units[f.unit - 1], lhs_id, true);

    let rv, rerr = expr(g, f, rhs_id);
    if rerr != squid_direct_types::Error.none { return rv, true, rerr; }
    push(g, rv);
    let if2 = open(g, f, OP_if_);
    let _, b2err = stmt(g, f, body_id);
    if b2err != squid_direct_types::Error.none { return neverVal(), true, b2err; }
    popCheckedArraysAt(f, if2);
    close(g, f);
    f.checked_elems_len = saved_ce_len;
    for ci in 0..saved_ce_len { f.checked_elems[ci] = saved_ce[ci]; }
    recordCondBounds(g, f, g.units[f.unit - 1], cond_id, true);
    return unitVal(), true, squid_direct_types::Error.none;
}

// 5A: Collect unconditional `arr[idx]` reads inside a pure comparison condition.
recursive fn collectUncondCondReads(
    m: const Module&,
    id: u32,
    arr_out: u32[4]&,
    idx_out: u32[4]&,
    len: i64&,
    depth: i64,
) {
    if id == 0 || depth > 8 || len >= 4 { return; }
    let ok, arr_n, idx_n = matchArrayGet(m, id);
    if ok {
        let ab = localRef(m, arr_n);
        let ib = localRef(m, idx_n);
        if ab != 0 && ib != 0 {
            arr_out[len] = ab;
            idx_out[len] = ib;
            len += 1;
        }
        return;
    }
    let n = m.node(id);
    if n.tag == squid_check_core::Tag.scalar || (n.tag == squid_check_core::Tag.associated && n.op != squid_check_core::Op.none) {
        collectUncondCondReads(m, n.a, arr_out, idx_out, len, depth + 1);
        collectUncondCondReads(m, n.b, arr_out, idx_out, len, depth + 1);
    }
}
fn isCondCachedRead(m: const Module&, id: u32, cond_arrs: const u32[4]&, cond_idxs: const u32[4]&, cond_len: i64) -> bool {
    let ok, arr_n, idx_n = matchArrayGet(m, id);
    if !ok { return false; }
    let ab = localRef(m, arr_n);
    let ib = localRef(m, idx_n);
    if ab == 0 || ib == 0 { return false; }
    for i in 0..cond_len {
        if cond_arrs[i] == ab && cond_idxs[i] == ib { return true; }
    }
    return false;
}
fn matchBranchIndexedStore(
    g: const Generator&,
    f: const Fn&,
    m: const Module&,
    body_id: u32,
    cond_arrs: const u32[4]&,
    cond_idxs: const u32[4]&,
    cond_len: i64,
    rest_out: u32[4]&,
    rest_len: i64&,
) -> bool, u32, u32, u32, u32, u32 {
    if body_id == 0 { return false, 0, 0, 0, 0, 0; }
    var stmts: u32[5] = [0; 5];
    var slen: i64 = 0;
    let bn = m.node(body_id);
    if bn.tag == squid_check_core::Tag.suite || bn.tag == squid_check_core::Tag.block_ {
        let ch = m.children(body_id);
        if ch.len == 0 || ch.len > 5 { return false, 0, 0, 0, 0, 0; }
        for i in 0..ch.len { stmts[i] = ch[i]; }
        slen = ch.len;
    } else {
        stmts[0] = body_id;
        slen = 1;
    }
    var upd_id: u32 = 0;
    var upd_bind_b: u32 = 0;
    let s0 = m.node(stmts[0]);
    if s0.tag == squid_check_core::Tag.update {
        upd_id = stmts[0];
    } else if s0.tag == squid_check_core::Tag.bind && s0.c < 2 && m.node(s0.b).tag == squid_check_core::Tag.update {
        upd_id = s0.b;
        upd_bind_b = s0.a;
    } else {
        return false, 0, 0, 0, 0, 0;
    }
    let uinfo = m.updateInfo(upd_id);
    let sels = m.updateSelectors(upd_id);
    if sels.len != 1 || sels[0].kind != squid_check_core::UpdateKind.index { return false, 0, 0, 0, 0, 0; }
    if uinfo.self_binding != 0 && uses(g, f, uinfo.self_binding) != 0 { return false, 0, 0, 0, 0, 0; }
    let dst_b = localRef(m, uinfo.root);
    let idx_b = localRef(m, sels[0].index);
    if dst_b == 0 || idx_b == 0 { return false, 0, 0, 0, 0, 0; }
    var val_ok = isCondCachedRead(m, uinfo.value, cond_arrs, cond_idxs, cond_len);
    if !val_ok {
        var vb: i64 = 12;
        val_ok = isPureSelectExpr(g, f, m, uinfo.value, vb);
    }
    if !val_ok { return false, 0, 0, 0, 0, 0; }
    rest_len = 0;
    for i in 1..slen {
        var rb: i64 = 16;
        if !isPureSelectExpr(g, f, m, stmts[i], rb) { return false, 0, 0, 0, 0, 0; }
        rest_out[rest_len] = stmts[i];
        rest_len += 1;
    }
    return true, dst_b, idx_b, uinfo.value, upd_bind_b, uinfo.root;
}
// 5A: Branchless `select` (`cmov`) conversion for same-target scalar indexed updates:
//   if cond: dst[k] := a; i += 1  else:  dst[k] := b; j += 1
fn tryIfBranchlessStore(g: Generator&, f: Fn&, id: u32) -> Val, bool, Error {
    if g.runtime_().has_fork { return neverVal(), false, squid_direct_types::Error.none; }
    var cond_id: u32 = 0;
    var dst_b: u32 = 0;
    var dst_root_node: u32 = 0;
    var idx_b: u32 = 0;
    var t_val_node: u32 = 0;
    var e_val_node: u32 = 0;
    var t_rest: u32[4] = [0; 4];
    var t_rest_len: i64 = 0;
    var e_rest: u32[4] = [0; 4];
    var e_rest_len: i64 = 0;
    var merge_count: i64 = 0;
    var m_then: u32[6] = [0; 6];
    var m_else: u32[6] = [0; 6];
    var m_res: u32[6] = [0; 6];
    var m_is_dst: bool[6] = [false; 6];
    var eligible = false;
    {
        let m .= g.units[f.unit - 1];
        let n = m.node(id);
        if n.tag != squid_check_core::Tag.if_stmt || n.c == 0 {
            return neverVal(), false, squid_direct_types::Error.none;
        }
        let merges = m.branchMerges(id);
        if merges.len == 0 || merges.len > 6 {
            return neverVal(), false, squid_direct_types::Error.none;
        }
        var cond_arrs: u32[4] = [0; 4];
        var cond_idxs: u32[4] = [0; 4];
        var cond_len: i64 = 0;
        collectUncondCondReads(m, n.a, cond_arrs, cond_idxs, cond_len, 0);
        let tok, t_dst, t_idx, t_val, t_ub, t_root = matchBranchIndexedStore(g, f, m, n.b, cond_arrs, cond_idxs, cond_len, t_rest, t_rest_len);
        if !tok { return neverVal(), false, squid_direct_types::Error.none; }
        let eok, e_dst, e_idx, e_val, e_ub, _ = matchBranchIndexedStore(g, f, m, n.c, cond_arrs, cond_idxs, cond_len, e_rest, e_rest_len);
        if !eok || t_dst != e_dst || t_idx != e_idx { return neverVal(), false, squid_direct_types::Error.none; }
        let dv, dok = bindGet(g, f, t_dst);
        let iv, iok = bindGet(g, f, t_idx);
        if !dok || !iok || tagOf(g, dv.ty) != squid_direct_types::Tag.array || tagOf(g, iv.ty) != squid_direct_types::Tag.u32_ {
            return neverVal(), false, squid_direct_types::Error.none;
        }
        let elem_tag = tagOf(g, g.types.node(dv.ty).a);
        if !isScalarTag(elem_tag) { return neverVal(), false, squid_direct_types::Error.none; }
        var all_ok = true;
        for merge, at in merges {
            let _, ct = withCellType(g, f, merge.then_binding);
            let _, ce = withCellType(g, f, merge.else_binding);
            if ct || ce { all_ok = false; break; }
            let is_t_dst = merge.then_binding == t_dst || (t_ub != 0 && merge.then_binding == t_ub);
            let is_e_dst = merge.else_binding == e_dst || (e_ub != 0 && merge.else_binding == e_ub);
            if is_t_dst && is_e_dst {
                m_is_dst[at] = true;
            } else {
                let mty = m.types.node(m.binding(merge.result).ty).tag;
                if mty != squid_check_types::Tag.unsigned32 && mty != squid_check_types::Tag.floating32 && mty != squid_check_types::Tag.boolean {
                    all_ok = false;
                    break;
                }
                m_is_dst[at] = false;
            }
            m_then[at] = merge.then_binding;
            m_else[at] = merge.else_binding;
            m_res[at] = merge.result;
        }
        if !all_ok { return neverVal(), false, squid_direct_types::Error.none; }
        cond_id = n.a;
        dst_b = t_dst;
        dst_root_node = t_root;
        idx_b = t_idx;
        t_val_node = t_val;
        e_val_node = e_val;
        merge_count = merges.len;
        eligible = true;
    }
    if !eligible { return neverVal(), false, squid_direct_types::Error.none; }

    let condition, cerr = expr(g, f, cond_id);
    if cerr != squid_direct_types::Error.none { return condition, true, cerr; }
    let vt, vterr = expr(g, f, t_val_node);
    if vterr != squid_direct_types::Error.none { return vt, true, vterr; }
    let ve, veerr = expr(g, f, e_val_node);
    if veerr != squid_direct_types::Error.none { return ve, true, veerr; }

    let dst_val, _ = bindGet(g, f, dst_b);
    let idx_val, _ = bindGet(g, f, idx_b);
    let elem_ty = g.types.node(dst_val.ty).a;
    let sel_loc = local(g, f, localKindForScalar(g, elem_ty));
    lget(g, w(g, vt, 0));
    lget(g, w(g, ve, 0));
    lget(g, w(g, condition, 0));
    op(g, OP_select);
    lset(g, sel_loc);

    let addr, aerr = elementAddress(g, f, dst_val, w(g, idx_val, 0), id, g.units[f.unit - 1].typeOf(dst_root_node));
    if aerr != squid_direct_types::Error.none { return neverVal(), true, aerr; }
    let werr = writeElement(g, f, addr, 0, valOf1(g, elem_ty, sel_loc), id);
    if werr != squid_direct_types::Error.none { return neverVal(), true, werr; }
    f.checked_elems_len = 0;

    for i in 0..t_rest_len {
        let _, serr = stmt(g, f, t_rest[i]);
        if serr != squid_direct_types::Error.none { return neverVal(), true, serr; }
    }
    for i in 0..e_rest_len {
        let _, serr = stmt(g, f, e_rest[i]);
        if serr != squid_direct_types::Error.none { return neverVal(), true, serr; }
    }
    for at in 0..merge_count {
        if m_is_dst[at] {
            bindPut(g, f, m_res[at], dst_val);
        } else {
            let tv, tok = bindGet(g, f, m_then[at]);
            let ev, eok = bindGet(g, f, m_else[at]);
            assert(tok && eok && tv.len == 1 && ev.len == 1);
            let out_loc = local(g, f, localKindForScalar(g, ev.ty));
            lget(g, w(g, tv, 0));
            lget(g, w(g, ev, 0));
            lget(g, w(g, condition, 0));
            op(g, OP_select);
            lset(g, out_loc);
            bindPut(g, f, m_res[at], valOf1(g, ev.ty, out_loc));
        }
    }
    return unitVal(), true, squid_direct_types::Error.none;
}

recursive fn pushCondition(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    if n.tag == squid_check_core::Tag.scalar && isComparisonOp(n.op) &&
        isCoreScalar(m, n.a) && isCoreScalar(m, n.b) {
        return scalar(g, f, id, false, true);
    }
    let value, error = expr(g, f, id);
    if error == squid_direct_types::Error.none { push(g, value); }
    return value, error;
}

recursive fn ifNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let sc_val, sc_done, sc_err = tryIfShortCircuitBreak(g, f, id);
    if sc_err != squid_direct_types::Error.none { return sc_val, sc_err; }
    if sc_done { return sc_val, squid_direct_types::Error.none; }
    let sel_val, converted, sel_err = tryIfSelectConvert(g, f, id);
    if sel_err != squid_direct_types::Error.none { return sel_val, sel_err; }
    if converted { return sel_val, squid_direct_types::Error.none; }
    let bs_val, bs_done, bs_err = tryIfBranchlessStore(g, f, id);
    if bs_err != squid_direct_types::Error.none { return bs_val, bs_err; }
    if bs_done { return bs_val, squid_direct_types::Error.none; }
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let result = g.newSlot();
    let merges = m.branchMerges(id);
    let merged = newSlots(g, merges.len);
    let condition, error = pushCondition(g, f, n.a);
    if error != squid_direct_types::Error.none { return condition, error; }
    let incoming_arrays = f.checked_arrays;
    let incoming_arrays_len = f.checked_arrays_len;
    var saved_ce: CheckedElem[8] = [CheckedElem {}; 8];
    let saved_ce_len = f.checked_elems_len;
    for ci in 0..saved_ce_len { saved_ce[ci] = f.checked_elems[ci]; }
    var m_t_ca_base: u32[16] = [0; 16];
    var m_t_ca_len: u32[16] = [0; 16];
    var m_t_ca_ok: bool[16] = [false; 16];
    var m_t_cg_entry: u32[16] = [0; 16];
    var m_t_cg_ok: bool[16] = [false; 16];
    var m_t_wr_base: u32[16] = [0; 16];
    var m_t_wr_len: u32[16] = [0; 16];
    var m_t_wr_ok: bool[16] = [false; 16];
    var m_t_wm_entry: u32[16] = [0; 16];
    var m_t_wm_ok: bool[16] = [false; 16];
    var m_e_ca_base: u32[16] = [0; 16];
    var m_e_ca_len: u32[16] = [0; 16];
    var m_e_ca_ok: bool[16] = [false; 16];
    var m_e_cg_entry: u32[16] = [0; 16];
    var m_e_cg_ok: bool[16] = [false; 16];
    var m_e_wr_base: u32[16] = [0; 16];
    var m_e_wr_len: u32[16] = [0; 16];
    var m_e_wr_ok: bool[16] = [false; 16];
    var m_e_wm_entry: u32[16] = [0; 16];
    var m_e_wm_ok: bool[16] = [false; 16];
    let if_locals_mark = localCount(g, f);
    let opened = open(g, f, OP_if_);
    recordCondBounds(g, f, g.units[f.unit - 1], n.a, false);
    let then, error = stmt(g, f, n.b);
    if error != squid_direct_types::Error.none { return then, error; }
    let then_diverges = then.ty == squid_direct_types::never;
    var falls = !then_diverges;
    if falls {
        if n.tag == squid_check_core::Tag.if_value {
            let delivered = deliver(g, f, then, result, id);
            if delivered != squid_direct_types::Error.none { return neverVal(), delivered; }
        }
        for merge, at in merges {
            let value, present = bindGet(g, f, merge.then_binding);
            if present {
                let delivered = deliver(g, f, value, merged + (at as u32), id);
                if delivered != squid_direct_types::Error.none { return neverVal(), delivered; }
                if at < 16 && isMutableOwnerTag(tagOf(g, value.ty)) {
                    let s0 = w(g, value, 0);
                    let s1 = w(g, value, 1);
                    let ca = findCheckedArray(f, s0, s1);
                    if ca >= 0 { m_t_ca_ok[at] = true; m_t_ca_base[at] = f.checked_arrays[ca].base; m_t_ca_len[at] = f.checked_arrays[ca].length; }
                    let cg = findCheckedGrow(f, s0, s1);
                    if cg >= 0 { m_t_cg_ok[at] = true; m_t_cg_entry[at] = f.checked_grows[cg].entry; }
                    let wr = findWorkerR(f, s0, s1);
                    if wr >= 0 { m_t_wr_ok[at] = true; m_t_wr_base[at] = f.worker_r[wr].base; m_t_wr_len[at] = f.worker_r[wr].length; }
                    let wm = findWorkerM(f, s0, s1);
                    if wm >= 0 { m_t_wm_ok[at] = true; m_t_wm_entry[at] = f.worker_m[wm].entry; }
                }
            }
        }
    }
    popCheckedArraysAt(f, opened);
    let then_arrays = f.checked_arrays;
    let then_arrays_len = f.checked_arrays_len;
    // The else arm starts from the same dominating descriptors as the then
    // arm. Keep only descriptors valid on every continuing path at the join.
    f.checked_arrays = incoming_arrays;
    f.checked_arrays_len = incoming_arrays_len;
    f.checked_elems_len = saved_ce_len;
    for ci in 0..saved_ce_len { f.checked_elems[ci] = saved_ce[ci]; }
    op(g, OP_else_);
    var else_falls = false;
    var else_mutable = false;
    if n.c != 0 {
        recordCondBounds(g, f, g.units[f.unit - 1], n.a, true);
        let otherwise, error = stmt(g, f, n.c);
        if error != squid_direct_types::Error.none { return otherwise, error; }
        if otherwise.ty != squid_direct_types::never {
            else_falls = true;
            else_mutable = knownMutable(g, f, otherwise);
            falls = true;
            if n.tag == squid_check_core::Tag.if_value {
                let delivered = deliver(g, f, otherwise, result, id);
                if delivered != squid_direct_types::Error.none { return neverVal(), delivered; }
            }
            for merge, at in merges {
                let value, present = bindGet(g, f, merge.else_binding);
                if present {
                    let delivered = deliver(g, f, value, merged + (at as u32), id);
                    if delivered != squid_direct_types::Error.none { return neverVal(), delivered; }
                    if at < 16 && isMutableOwnerTag(tagOf(g, value.ty)) {
                        let s0 = w(g, value, 0);
                        let s1 = w(g, value, 1);
                        let ca = findCheckedArray(f, s0, s1);
                        if ca >= 0 { m_e_ca_ok[at] = true; m_e_ca_base[at] = f.checked_arrays[ca].base; m_e_ca_len[at] = f.checked_arrays[ca].length; }
                        let cg = findCheckedGrow(f, s0, s1);
                        if cg >= 0 { m_e_cg_ok[at] = true; m_e_cg_entry[at] = f.checked_grows[cg].entry; }
                        let wr = findWorkerR(f, s0, s1);
                        if wr >= 0 { m_e_wr_ok[at] = true; m_e_wr_base[at] = f.worker_r[wr].base; m_e_wr_len[at] = f.worker_r[wr].length; }
                        let wm = findWorkerM(f, s0, s1);
                        if wm >= 0 { m_e_wm_ok[at] = true; m_e_wm_entry[at] = f.worker_m[wm].entry; }
                    }
                }
            }
        }
    } else {
        else_falls = true;
        falls = true;
        for merge, at in merges {
            let value, present = bindGet(g, f, merge.else_binding);
            if present {
                let delivered = deliver(g, f, value, merged + (at as u32), id);
                if delivered != squid_direct_types::Error.none { return neverVal(), delivered; }
                if at < 16 && isMutableOwnerTag(tagOf(g, value.ty)) {
                    let s0 = w(g, value, 0);
                    let s1 = w(g, value, 1);
                    let ca = findCheckedArray(f, s0, s1);
                    if ca >= 0 { m_e_ca_ok[at] = true; m_e_ca_base[at] = f.checked_arrays[ca].base; m_e_ca_len[at] = f.checked_arrays[ca].length; }
                    let cg = findCheckedGrow(f, s0, s1);
                    if cg >= 0 { m_e_cg_ok[at] = true; m_e_cg_entry[at] = f.checked_grows[cg].entry; }
                    let wr = findWorkerR(f, s0, s1);
                    if wr >= 0 { m_e_wr_ok[at] = true; m_e_wr_base[at] = f.worker_r[wr].base; m_e_wr_len[at] = f.worker_r[wr].length; }
                    let wm = findWorkerM(f, s0, s1);
                    if wm >= 0 { m_e_wm_ok[at] = true; m_e_wm_entry[at] = f.worker_m[wm].entry; }
                }
            }
        }
    }
    close(g, f);
    if !else_falls {
        f.checked_arrays = then_arrays;
        f.checked_arrays_len = then_arrays_len;
    } else if !then_diverges {
        var out: i64 = 0;
        for at in 0..f.checked_arrays_len {
            let right = f.checked_arrays[at];
            for left in then_arrays[..then_arrays_len] {
                if left.slot == right.slot && left.generation == right.generation &&
                    left.base == right.base && left.length == right.length {
                    f.checked_arrays[out] = right;
                    out += 1;
                    break;
                }
            }
        }
        f.checked_arrays_len = out;
    }
    let result_slot = g.s.slots[result];
    if result_slot.present && (then_diverges || knownMutable(g, f, then)) && (!else_falls || else_mutable) {
        recordMutable(g, f, result_slot.value);
    }
    propagateSlotMask(g, f, result, if_locals_mark);
    if n.c == 0 && then_diverges {
        f.checked_elems_len = saved_ce_len;
        for ci in 0..saved_ce_len { f.checked_elems[ci] = saved_ce[ci]; }
    } else {
        f.checked_elems_len = 0;
    }
    if n.tag == squid_check_core::Tag.if_stmt && n.c == 0 && then_diverges {
        recordCondBounds(g, f, g.units[f.unit - 1], n.a, true);
    }
    for merge, at in merges {
        let slot = g.s.slots[merged + at];
        if slot.present {
            var bound_val = slot.value;
            var reused_same = false;
            if isMutableOwnerTag(tagOf(g, slot.value.ty)) && !then_diverges && else_falls && at < 16 {
                let tv, tok = bindGet(g, f, merge.then_binding);
                let ev, eok = bindGet(g, f, merge.else_binding);
                if tok && eok && sameWords(g, tv, ev) && tv.ty == slot.value.ty &&
                    m_t_ca_ok[at] && m_e_ca_ok[at] && m_t_ca_base[at] == m_e_ca_base[at] && m_t_ca_len[at] == m_e_ca_len[at] {
                    bound_val = tv;
                    reused_same = true;
                }
            }
            bindPut(g, f, merge.result, bound_val);
            propagateSlotMask(g, f, merged + (at as u32), if_locals_mark);
            if isMutableOwnerTag(tagOf(g, bound_val.ty)) {
                var mutable_merge = true;
                if !then_diverges {
                    let tv, tok = bindGet(g, f, merge.then_binding);
                    mutable_merge = mutable_merge && tok && knownMutable(g, f, tv);
                }
                if else_falls {
                    let ev, eok = bindGet(g, f, merge.else_binding);
                    mutable_merge = mutable_merge && eok && knownMutable(g, f, ev);
                }
                if mutable_merge { recordMutable(g, f, bound_val); }
                if at < 16 && !reused_same {
                    let s0 = w(g, bound_val, 0);
                    let s1 = w(g, bound_val, 1);
                    if !then_diverges && else_falls {
                        if m_t_ca_ok[at] && m_e_ca_ok[at] && m_t_ca_base[at] == m_e_ca_base[at] && m_t_ca_len[at] == m_e_ca_len[at] {
                            recordCheckedArray(f, s0, s1, m_t_ca_base[at], m_t_ca_len[at]);
                        }
                        if m_t_cg_ok[at] && m_e_cg_ok[at] && m_t_cg_entry[at] == m_e_cg_entry[at] {
                            recordCheckedGrow(f, s0, s1, m_t_cg_entry[at]);
                        }
                        if m_t_wr_ok[at] && m_e_wr_ok[at] && m_t_wr_base[at] == m_e_wr_base[at] && m_t_wr_len[at] == m_e_wr_len[at] {
                            recordWorkerR(f, s0, s1, m_t_wr_base[at], m_t_wr_len[at]);
                        }
                        if m_t_wm_ok[at] && m_e_wm_ok[at] && m_t_wm_entry[at] == m_e_wm_entry[at] {
                            recordWorkerM(f, s0, s1, m_t_wm_entry[at]);
                        }
                    } else if !then_diverges {
                        if m_t_ca_ok[at] { recordCheckedArray(f, s0, s1, m_t_ca_base[at], m_t_ca_len[at]); }
                        if m_t_cg_ok[at] { recordCheckedGrow(f, s0, s1, m_t_cg_entry[at]); }
                        if m_t_wr_ok[at] { recordWorkerR(f, s0, s1, m_t_wr_base[at], m_t_wr_len[at]); }
                        if m_t_wm_ok[at] { recordWorkerM(f, s0, s1, m_t_wm_entry[at]); }
                    } else if else_falls {
                        if m_e_ca_ok[at] { recordCheckedArray(f, s0, s1, m_e_ca_base[at], m_e_ca_len[at]); }
                        if m_e_cg_ok[at] { recordCheckedGrow(f, s0, s1, m_e_cg_entry[at]); }
                        if m_e_wr_ok[at] { recordWorkerR(f, s0, s1, m_e_wr_base[at], m_e_wr_len[at]); }
                        if m_e_wm_ok[at] { recordWorkerM(f, s0, s1, m_e_wm_entry[at]); }
                    }
                }
                var uo_ok = true;
                if !then_diverges {
                    let tb = merge.then_binding;
                    if tb == 0 || !isUniqueOwned(g, f, tb) || ownedRefUses(g, f, tb) != 0 || ownedFlowUses(g, f, tb) != 1 || bindingCaptured(g, f, tb) {
                        uo_ok = false;
                    }
                }
                if else_falls {
                    let eb = merge.else_binding;
                    if eb == 0 || !isUniqueOwned(g, f, eb) || ownedRefUses(g, f, eb) != 0 || ownedFlowUses(g, f, eb) != 1 || bindingCaptured(g, f, eb) {
                        uo_ok = false;
                    }
                }
                if uo_ok && (!then_diverges || else_falls) {
                    squid_support_zigmap::put(g.s.map_pool, f.unique_owned, merge.result, f.loop_depth + 1);
                }
            }
            let ct1, ok1 = withCellType(g, f, merge.then_binding);
            if ok1 { squid_support_zigmap::put(g.s.map_pool, f.with_cells, merge.result, ct1); }
            else {
                let ct2, ok2 = withCellType(g, f, merge.else_binding);
                if ok2 { squid_support_zigmap::put(g.s.map_pool, f.with_cells, merge.result, ct2); }
            }
        }
    }
    if !falls { return neverVal(), squid_direct_types::Error.none; }
    if n.tag == squid_check_core::Tag.if_stmt { return unitVal(), squid_direct_types::Error.none; }
    if g.s.slots[result].present { return g.s.slots[result].value, squid_direct_types::Error.none; }
    return neverVal(), squid_direct_types::Error.none;
}

// Only visit a block whose value is returned by the function itself. Once a
// return starts, another block's continuation cannot run before the exit.
fn scratchBody(m: const Module&, root: u32) -> u32 {
    var current = root;
    for step in 0..8 {
        let node = m.node(current);
        if node.tag == squid_check_core::Tag.return_ { current = node.a; continue; }
        if node.tag != squid_check_core::Tag.block_ { return 0; }
        if node.b != 1 { return current; }
        let only = m.children(current)[0];
        if m.node(only).tag != squid_check_core::Tag.return_ { return 0; }
        current = only;
    }
    return 0;
}

// The block ends by returning scalar reads from freshly produced storage.
// The array literal commits the result after those reads finish.
fn scratchLiteral(g: Generator&, f: Fn&, tail: const u32[:]) -> u32 {
    let m .= g.units[f.unit - 1];
    let producer = m.node(tail[0]);
    if producer.tag != squid_check_core::Tag.bind || producer.c != 0 { return 0; }
    let init = m.node(producer.b);
    if init.tag != squid_check_core::Tag.array_op { return 0; }
    let operation = m.arrayOperation(producer.b);
    if operation != squid_backend_collection_ops::Op.generate && operation != squid_backend_collection_ops::Op.fill { return 0; }
    let shape = m.types.node(init.ty);
    if shape.tag != squid_check_types::Tag.array || !scratchScalarType(m, shape.a) { return 0; }
    let next = m.node(tail[1]);
    var literal: u32 = 0;
    if tail.len == 2 && next.tag == squid_check_core::Tag.return_ { literal = next.a; }
    else if tail.len == 3 && next.tag == squid_check_core::Tag.bind && m.node(next.b).tag == squid_check_core::Tag.update {
        let returned = m.node(tail[2]);
        if returned.tag != squid_check_core::Tag.return_ || localRef(m, returned.a) != next.a { return 0; }
        let update = m.updateInfo(next.b);
        if !scratchFieldUpdate(m, update, next.b) { return 0; }
        let root = localRef(m, update.root);
        if root == 0 || root == producer.a { return 0; }
        let value, found = bindGet(g, f, root);
        // A structural record reaches the replacement once. A sum can
        // emit the replacement separately in several branches.
        if !found || tagOf(g, value.ty) != squid_direct_types::Tag.record { return 0; }
        literal = update.value;
    } else { return 0; }
    if m.node(literal).tag != squid_check_core::Tag.array { return 0; }
    var reads = false;
    for element in m.children(literal) {
        if !scratchScalar(g, f, m, element, producer.a, 0, reads, 0) { return 0; }
    }
    if !reads { return 0; }
    let arguments = m.children(producer.b);
    var ignored = false;
    if arguments.len != 2 || !scratchScalar(g, f, m, arguments[0], 0, 0, ignored, 0) { return 0; }
    if operation == squid_backend_collection_ops::Op.fill {
        if !scratchScalar(g, f, m, arguments[1], 0, 0, ignored, 0) { return 0; }
    } else {
        let mapper = arguments[1];
        if m.node(mapper).tag != squid_check_core::Tag.closure { return 0; }
        let info = m.closure(mapper);
        if !scratchScalarType(m, info.parameter.ty) { return 0; }
        for capture in m.closureCaptures(mapper) {
            let value, found = bindGet(g, f, capture);
            if !found || !isScalarTag(tagOf(g, value.ty)) { return 0; }
        }
        if !scratchScalar(g, f, m, scratchReturned(m, info.body), 0, info.parameter.binding, ignored, 0) { return 0; }
    }
    if scratchEscapes(m, producer.a) { return 0; }
    return literal;
}

fn localRef(m: const Module&, id: u32) -> u32 {
    if m.node(id).tag != squid_check_core::Tag.reference { return 0; }
    let ref = m.reference(id);
    if ref.unit != 0 && ref.unit != m.unit { return 0; }
    return ref.binding;
}

fn scratchFieldUpdate(m: const Module&, update: squid_check_core::UpdateInfo, id: u32) -> bool {
    let selectors = m.updateSelectors(id);
    if selectors.len == 0 { return update.path.len == 1; }
    return selectors.len == 1 && selectors[0].kind == squid_check_core::UpdateKind.field;
}

// A block-local binding cannot outlive its terminal return. Reject synthetic
// bindings that could be transported separately from that return value.
fn scratchEscapes(m: const Module&, binding: u32) -> bool {
    for closure in m.closures {
        for capture in m.extra[closure.captures.start..closure.captures.start + closure.captures.len] {
            if capture == binding { return true; }
        }
    }
    for carry in m.loop_carries {
        if carry.incoming == binding || carry.iteration == binding || carry.backedge == binding || carry.outgoing == binding { return true; }
    }
    for merge in m.merges {
        if merge.result == binding || merge.then_binding == binding || merge.else_binding == binding { return true; }
    }
    return false;
}

fn scratchScalarType(m: const Module&, ty: u32) -> bool {
    let tag = m.types.node(ty).tag;
    return tag == squid_check_types::Tag.unsigned32 || tag == squid_check_types::Tag.floating32 || tag == squid_check_types::Tag.boolean;
}

fn scratchReturned(m: const Module&, id: u32) -> u32 {
    var current = id;
    for step in 0..8 {
        let n = m.node(current);
        if n.tag == squid_check_core::Tag.return_ { current = n.a; }
        else if n.tag == squid_check_core::Tag.block_ && n.b == 1 { current = m.children(current)[0]; }
        else { break; }
    }
    return current;
}

// Use the same scalar forwarding shape as call emission. Such a call
// reads only its proved scalar operands and has no storage operation.
fn scratchScalarCallee(g: const Generator&, m: const Module&, call: squid_check_core::Call) -> bool {
    let target = g.resolve(m, call.target);
    if !g.hasUnit(target.unit) { return false; }
    let owner .= g.units[target.unit - 1];
    let alias, present = primitiveAlias(owner, target.binding);
    if present {
        let primitive = owner.primitive(alias);
        return primitive.kind == squid_check_core::PrimitiveKind.scalar && primitive.arity == call.arguments.len;
    }
    let body .= owner.body(target.binding);
    if !body || !body.is_function { return false; }
    let parameters = owner.bodyParameters(body);
    if parameters.len != call.arguments.len { return false; }
    let node = owner.node(scratchReturned(owner, body.root));
    if node.tag != squid_check_core::Tag.associated || node.op == squid_check_core::Op.none { return false; }
    for operand in [node.a, node.b] {
        if operand == 0 { continue; }
        if owner.node(operand).tag != squid_check_core::Tag.reference { return false; }
        let ref = owner.reference(operand);
        if ref.unit != 0 && ref.unit != owner.unit { return false; }
        var found = false;
        for parameter in parameters {
            if parameter.binding == ref.binding { found = true; break; }
        }
        if !found { return false; }
    }
    return node.a != 0;
}
recursive fn scratchScalar(g: Generator&, f: Fn&, m: const Module&, id: u32, binding: u32, parameter: u32, reads: bool&, depth: i64) -> bool {
    if depth >= 32 || !scratchScalarType(m, m.typeOf(id)) { return false; }
    let n = m.node(id);
    match n.tag {
        constant => { return true; },
        reference => {
            let local = localRef(m, id);
            if local == 0 { return false; }
            if local == parameter { return true; }
            let value, found = bindGet(g, f, local);
            return found && isScalarTag(tagOf(g, value.ty));
        },
        scalar, associated, logical => {
            if n.tag == squid_check_core::Tag.associated && n.op == squid_check_core::Op.none { return false; }
            return scratchScalar(g, f, m, n.a, binding, parameter, reads, depth + 1) &&
                (n.b == 0 || scratchScalar(g, f, m, n.b, binding, parameter, reads, depth + 1));
        },
        call => {
            let call = m.call(id);
            if !scratchScalarCallee(g, m, call) { return false; }
            for arg in call.arguments {
                if !scratchScalar(g, f, m, arg, binding, parameter, reads, depth + 1) { return false; }
            }
            return true;
        },
        array_op => {
            if binding == 0 { return false; }
            let op = m.arrayOperation(id);
            if op != squid_backend_collection_ops::Op.get && op != squid_backend_collection_ops::Op.length { return false; }
            let args = m.children(id);
            if args.len == 0 || localRef(m, args[0]) != binding { return false; }
            reads = true;
            return args.len == 1 || scratchScalar(g, f, m, args[1], binding, parameter, reads, depth + 1);
        },
        _ => { return false; },
    }
}

fn markScratchPair(g: Generator&, f: Fn&, contents: const u32[:], at: i64) {
    let remaining = contents.len - at;
    if f.scratch_cut.target != 0 || remaining < 2 || remaining > 3 { return; }
    let target = scratchLiteral(g, f, contents[at..]);
    if target == 0 { return; }
    let owner = local32(g, f);
    let stack = local32(g, f);
    markInto(g, g.s.code, owner, stack);
    f.scratch_cut = ScratchCut { target, owner, stack };
}

// 7B: Dead `@array.fill` zero/constant-init elision.
// Detects `let arr = @array.fill count val` immediately followed (modulo pure non-reading scalar/fill
// bindings) by a straight-line `for i in 0 .. count:` loop that unconditionally overwrites `arr[i]`
// for every element without reading `arr` or calling arbitrary functions.
recursive fn deadFillExprUsesOrCalls(g: Generator&, m: const Module&, id: u32, b1: u32, b2: u32, b3: u32, budget: i64&) -> bool {
    if id == 0 { return false; }
    if budget <= 0 { return true; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        constant => { return false; },
        reference => {
            let b = localRef(m, id);
            return b != 0 && (b == b1 || b == b2 || b == b3);
        },
        scalar, associated => {
            return deadFillExprUsesOrCalls(g, m, n.a, b1, b2, b3, budget) ||
                deadFillExprUsesOrCalls(g, m, n.b, b1, b2, b3, budget);
        },
        logical => {
            return deadFillExprUsesOrCalls(g, m, n.a, b1, b2, b3, budget) ||
                deadFillExprUsesOrCalls(g, m, n.b, b1, b2, b3, budget);
        },
        project => {
            if !isPureScalarProject(g, m, id) { return true; }
            return deadFillExprUsesOrCalls(g, m, n.a, b1, b2, b3, budget);
        },
        call => {
            let info = m.call(id);
            let target = recordAliasChain(g, g.resolve(m, info.target));
            if !g.hasUnit(target.unit) { return true; }
            let tm .= g.units[target.unit - 1];
            let _, has_alias = primitiveAlias(tm, target.binding);
            if !has_alias { return true; }
            for arg in m.call(id).arguments {
                if deadFillExprUsesOrCalls(g, m, arg, b1, b2, b3, budget) { return true; }
            }
            return false;
        },
        array_op => {
            if m.arrayOperation(id) != squid_backend_collection_ops::Op.fill { return true; }
            for ch in m.children(id) {
                if deadFillExprUsesOrCalls(g, m, ch, b1, b2, b3, budget) { return true; }
            }
            return false;
        },
        _ => { return true; },
    }
}
fn sameCountExpr(m: const Module&, a: u32, b: u32) -> bool {
    if a == 0 || b == 0 { return false; }
    let la = localRef(m, a);
    let lb = localRef(m, b);
    if la != 0 && la == lb { return true; }
    let na = m.node(a);
    let nb = m.node(b);
    return na.tag == squid_check_core::Tag.constant && nb.tag == squid_check_core::Tag.constant && na.a == nb.a;
}
recursive fn collectDirectArrayAliases(
    g: const Generator&,
    m: const Module&,
    id: u32,
    b_set: u32[16]&,
    b_len: i64&,
    changed: bool&,
    ok: bool&,
    budget: i64&,
) {
    if id == 0 || !ok { return; }
    if budget <= 0 { ok = false; return; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        suite, block_, product, record, array, array_op, storage, break_ => {
            for ch in m.children(id) { collectDirectArrayAliases(g, m, ch, b_set, b_len, changed, ok, budget); }
        },
        bind => {
            collectDirectArrayAliases(g, m, n.b, b_set, b_len, changed, ok, budget);
            if !ok { return; }
            if n.c < 2 && n.b != 0 {
                let rn = m.node(n.b);
                var from_b: u32 = 0;
                if rn.tag == squid_check_core::Tag.reference {
                    from_b = localRef(m, n.b);
                } else if rn.tag == squid_check_core::Tag.update {
                    let uinfo = m.updateInfo(n.b);
                    let sels = m.updateSelectors(n.b);
                    if sels.len == 1 && sels[0].kind == squid_check_core::UpdateKind.index {
                        from_b = localRef(m, uinfo.root);
                    }
                }
                if from_b != 0 {
                    var in_set = false;
                    for i in 0..b_len { if b_set[i] == from_b { in_set = true; break; } }
                    if in_set {
                        var already = false;
                        for i in 0..b_len { if b_set[i] == n.a { already = true; break; } }
                        if !already {
                            if b_len >= 16 { ok = false; return; }
                            b_set[b_len] = n.a;
                            b_len += 1;
                            changed = true;
                        }
                    }
                }
            }
        },
        loop_ => {
            let linfo = m.loopInfo(id);
            collectDirectArrayAliases(g, m, linfo.first, b_set, b_len, changed, ok, budget);
            collectDirectArrayAliases(g, m, linfo.end, b_set, b_len, changed, ok, budget);
            for carry, ci in m.loopCarries(id) {
                var in_set = false;
                for i in 0..b_len { if b_set[i] == carry.incoming { in_set = true; break; } }
                if in_set {
                    var cb: i64 = 512;
                    if !carryStaysInPlace(g, m, id, ci, carry.iteration, carry.backedge, cb) {
                        ok = false;
                        return;
                    }
                    for target_b in [carry.iteration, carry.outgoing] {
                        if target_b == 0 { continue; }
                        var already = false;
                        for i in 0..b_len { if b_set[i] == target_b { already = true; break; } }
                        if !already {
                            if b_len >= 16 { ok = false; return; }
                            b_set[b_len] = target_b;
                            b_len += 1;
                            changed = true;
                        }
                    }
                }
            }
            collectDirectArrayAliases(g, m, linfo.body, b_set, b_len, changed, ok, budget);
        },
        if_stmt, if_value => {
            collectDirectArrayAliases(g, m, n.a, b_set, b_len, changed, ok, budget);
            collectDirectArrayAliases(g, m, n.b, b_set, b_len, changed, ok, budget);
            collectDirectArrayAliases(g, m, n.c, b_set, b_len, changed, ok, budget);
        },
        match_ => {
            for inp in m.matchInputs(id) { collectDirectArrayAliases(g, m, inp, b_set, b_len, changed, ok, budget); }
            for arm in m.matchArms(id) {
                collectDirectArrayAliases(g, m, arm.guard_, b_set, b_len, changed, ok, budget);
                collectDirectArrayAliases(g, m, arm.body, b_set, b_len, changed, ok, budget);
            }
        },
        update => {
            let uinfo = m.updateInfo(id);
            collectDirectArrayAliases(g, m, uinfo.root, b_set, b_len, changed, ok, budget);
            for sel in m.updateSelectors(id) {
                if sel.kind == squid_check_core::UpdateKind.index {
                    collectDirectArrayAliases(g, m, sel.index, b_set, b_len, changed, ok, budget);
                }
            }
            collectDirectArrayAliases(g, m, uinfo.value, b_set, b_len, changed, ok, budget);
        },
        scalar, logical, apply, associated => {
            collectDirectArrayAliases(g, m, n.a, b_set, b_len, changed, ok, budget);
            collectDirectArrayAliases(g, m, n.b, b_set, b_len, changed, ok, budget);
        },
        call => {
            for arg in m.call(id).arguments { collectDirectArrayAliases(g, m, arg, b_set, b_len, changed, ok, budget); }
        },
        return_, project, result_associated, fork_ => {
            collectDirectArrayAliases(g, m, n.a, b_set, b_len, changed, ok, budget);
        },
        construct => {
            collectDirectArrayAliases(g, m, n.b, b_set, b_len, changed, ok, budget);
        },
        pattern_bind => {
            collectDirectArrayAliases(g, m, n.b, b_set, b_len, changed, ok, budget);
            collectDirectArrayAliases(g, m, n.c, b_set, b_len, changed, ok, budget);
        },
        spark => {
            let sinfo = m.sparkInfo(id);
            collectDirectArrayAliases(g, m, sinfo.source, b_set, b_len, changed, ok, budget);
            collectDirectArrayAliases(g, m, sinfo.end, b_set, b_len, changed, ok, budget);
            collectDirectArrayAliases(g, m, sinfo.body, b_set, b_len, changed, ok, budget);
        },
        _ => {},
    }
}

fn inDirectSet(b_set: const u32[16]&, b_len: i64, b: u32) -> bool {
    if b == 0 { return false; }
    for i in 0..b_len { if b_set[i] == b { return true; } }
    return false;
}

recursive fn checkDirectArrayUses(
    m: const Module&,
    id: u32,
    b_set: const u32[16]&,
    b_len: i64,
    budget: i64&,
    saw_decl: bool&,
    needs_addr: bool&,
) -> bool {
    if id == 0 { return true; }
    if budget <= 0 { return false; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        constant, panic, primitive_function, constructor_function, operation_value, comptime_meta => { return true; },
        reference => { return !inDirectSet(b_set, b_len, localRef(m, id)); },
        array_op => {
            let op = m.arrayOperation(id);
            let ch = m.children(id);
            if (op == squid_backend_collection_ops::Op.length || op == squid_backend_collection_ops::Op.get) &&
                ch.len >= 1 && inDirectSet(b_set, b_len, localRef(m, ch[0])) {
                for ci in 1..ch.len {
                    if !checkDirectArrayUses(m, ch[ci], b_set, b_len, budget, saw_decl, needs_addr) { return false; }
                }
                return true;
            }
            for ch_id in ch {
                if !checkDirectArrayUses(m, ch_id, b_set, b_len, budget, saw_decl, needs_addr) { return false; }
            }
            return true;
        },
        storage => {
            let op_k, ok = squid_check_storage_ops::opFromCode(n.c);
            let ch = m.children(id);
            if ok == squid_error::Error.none &&
                (op_k == squid_check_storage_ops::Op.length || op_k == squid_check_storage_ops::Op.read) &&
                ch.len >= 1 && inDirectSet(b_set, b_len, localRef(m, ch[0])) {
                for ci in 1..ch.len {
                    if !checkDirectArrayUses(m, ch[ci], b_set, b_len, budget, saw_decl, needs_addr) { return false; }
                }
                return true;
            }
            for ch_id in ch {
                if !checkDirectArrayUses(m, ch_id, b_set, b_len, budget, saw_decl, needs_addr) { return false; }
            }
            return true;
        },
        bind => {
            if n.c >= 2 {
                if inDirectSet(b_set, b_len, n.a) || inDirectSet(b_set, b_len, n.c - 2) { return false; }
                return checkDirectArrayUses(m, n.b, b_set, b_len, budget, saw_decl, needs_addr);
            }
            if n.a == b_set[0] { saw_decl = true; }
            if n.b != 0 && inDirectSet(b_set, b_len, n.a) {
                let rn = m.node(n.b);
                if rn.tag == squid_check_core::Tag.reference && inDirectSet(b_set, b_len, localRef(m, n.b)) {
                    return true;
                }
                if rn.tag == squid_check_core::Tag.update {
                    let uinfo = m.updateInfo(n.b);
                    let sels = m.updateSelectors(n.b);
                    if sels.len == 1 && sels[0].kind == squid_check_core::UpdateKind.index &&
                        inDirectSet(b_set, b_len, localRef(m, uinfo.root)) {
                        return checkDirectArrayUses(m, sels[0].index, b_set, b_len, budget, saw_decl, needs_addr) &&
                            checkDirectArrayUses(m, uinfo.value, b_set, b_len, budget, saw_decl, needs_addr);
                    }
                }
            }
            return checkDirectArrayUses(m, n.b, b_set, b_len, budget, saw_decl, needs_addr);
        },
        suite, block_, product, record, array => {
            for ch in m.children(id) {
                if !checkDirectArrayUses(m, ch, b_set, b_len, budget, saw_decl, needs_addr) { return false; }
            }
            return true;
        },
        if_stmt, if_value => {
            for merge in m.branchMerges(id) {
                if inDirectSet(b_set, b_len, merge.then_binding) ||
                    inDirectSet(b_set, b_len, merge.else_binding) ||
                    inDirectSet(b_set, b_len, merge.result) { return false; }
            }
            return checkDirectArrayUses(m, n.a, b_set, b_len, budget, saw_decl, needs_addr) &&
                checkDirectArrayUses(m, n.b, b_set, b_len, budget, saw_decl, needs_addr) &&
                checkDirectArrayUses(m, n.c, b_set, b_len, budget, saw_decl, needs_addr);
        },
        match_ => {
            for merge in m.branchMerges(id) {
                if inDirectSet(b_set, b_len, merge.then_binding) ||
                    inDirectSet(b_set, b_len, merge.else_binding) ||
                    inDirectSet(b_set, b_len, merge.result) { return false; }
            }
            for inp in m.matchInputs(id) {
                if !checkDirectArrayUses(m, inp, b_set, b_len, budget, saw_decl, needs_addr) { return false; }
            }
            for arm in m.matchArms(id) {
                if !checkDirectArrayUses(m, arm.guard_, b_set, b_len, budget, saw_decl, needs_addr) ||
                    !checkDirectArrayUses(m, arm.body, b_set, b_len, budget, saw_decl, needs_addr) { return false; }
            }
            return true;
        },
        loop_ => {
            let linfo = m.loopInfo(id);
            if !checkDirectArrayUses(m, linfo.first, b_set, b_len, budget, saw_decl, needs_addr) ||
                !checkDirectArrayUses(m, linfo.end, b_set, b_len, budget, saw_decl, needs_addr) { return false; }
            for carry in m.loopCarries(id) {
                let inc_in = inDirectSet(b_set, b_len, carry.incoming);
                let back_in = inDirectSet(b_set, b_len, carry.backedge);
                if inc_in || back_in {
                    if !inc_in || !inDirectSet(b_set, b_len, carry.iteration) { return false; }
                    if carry.backedge != 0 && !back_in { return false; }
                }
            }
            return checkDirectArrayUses(m, linfo.body, b_set, b_len, budget, saw_decl, needs_addr);
        },
        break_ => {
            let vals = m.breakValues(id);
            if n.a != 0 && m.node(n.a).tag == squid_check_core::Tag.loop_ {
                let carries = m.loopCarries(n.a);
                for ch, ci in vals {
                    let vb = localRef(m, ch);
                    if vb != 0 && inDirectSet(b_set, b_len, vb) {
                        if ci >= carries.len || !inDirectSet(b_set, b_len, carries[ci].iteration) { return false; }
                    } else if !checkDirectArrayUses(m, ch, b_set, b_len, budget, saw_decl, needs_addr) {
                        return false;
                    }
                }
                return true;
            }
            for ch in vals {
                if !checkDirectArrayUses(m, ch, b_set, b_len, budget, saw_decl, needs_addr) { return false; }
            }
            return true;
        },
        update => {
            let uinfo = m.updateInfo(id);
            if !checkDirectArrayUses(m, uinfo.root, b_set, b_len, budget, saw_decl, needs_addr) { return false; }
            for sel in m.updateSelectors(id) {
                if sel.kind == squid_check_core::UpdateKind.index && !checkDirectArrayUses(m, sel.index, b_set, b_len, budget, saw_decl, needs_addr) { return false; }
            }
            return checkDirectArrayUses(m, uinfo.value, b_set, b_len, budget, saw_decl, needs_addr);
        },
        scalar, logical, apply, associated => {
            return checkDirectArrayUses(m, n.a, b_set, b_len, budget, saw_decl, needs_addr) &&
                checkDirectArrayUses(m, n.b, b_set, b_len, budget, saw_decl, needs_addr);
        },
        call => {
            for arg in m.call(id).arguments {
                if !checkDirectArrayUses(m, arg, b_set, b_len, budget, saw_decl, needs_addr) { return false; }
            }
            return true;
        },
        return_, project, result_associated, fork_ => {
            return checkDirectArrayUses(m, n.a, b_set, b_len, budget, saw_decl, needs_addr);
        },
        construct => {
            return checkDirectArrayUses(m, n.b, b_set, b_len, budget, saw_decl, needs_addr);
        },
        pattern_bind => {
            return checkDirectArrayUses(m, n.b, b_set, b_len, budget, saw_decl, needs_addr) &&
                checkDirectArrayUses(m, n.c, b_set, b_len, budget, saw_decl, needs_addr);
        },
        closure => {
            for cap in m.closureCaptures(id) {
                if inDirectSet(b_set, b_len, cap) { return false; }
            }
            return true;
        },
        spark => {
            needs_addr = true;
            let sinfo = m.sparkInfo(id);
            return checkDirectArrayUses(m, sinfo.source, b_set, b_len, budget, saw_decl, needs_addr) &&
                checkDirectArrayUses(m, sinfo.end, b_set, b_len, budget, saw_decl, needs_addr) &&
                checkDirectArrayUses(m, sinfo.body, b_set, b_len, budget, saw_decl, needs_addr);
        },
        _ => { return false; },
    }
}

fn isDirectLocalArrayBinding(g: Generator&, f: const Fn&, m: const Module&, body_root: u32, binding: u32, needs_addr: bool&) -> bool {
    var b_set: u32[16] = [0; 16];
    b_set[0] = binding;
    var b_len: i64 = 1;
    var ok = true;
    var changed = true;
    var iter: i64 = 0;
    while changed && ok && iter < 8 {
        changed = false;
        var abudget: i64 = 1024;
        collectDirectArrayAliases(g, m, body_root, b_set, b_len, changed, ok, abudget);
        iter += 1;
    }
    if !ok { return false; }
    for i in 0..b_len {
        if bindingCaptured(g, f, b_set[i]) { return false; }
    }
    var cbudget: i64 = 1024;
    var saw_decl = false;
    needs_addr = false;
    return checkDirectArrayUses(m, body_root, b_set, b_len, cbudget, saw_decl, needs_addr) && saw_decl;
}

fn scanDeadFills(g: Generator&, f: Fn&, m: const Module&, children: const u32[:]) {
    if g.runtime_().has_fork || f.tco_inhibit != 0 || children.len < 2 || f.skip_fill_len >= 8 { return; }
    for k in 0..(children.len - 1) {
        if f.skip_fill_len >= 8 { return; }
        let cn = m.node(children[k]);
        if cn.tag != squid_check_core::Tag.bind || cn.c >= 2 { continue; }
        let fill_id = cn.b;
        let fn_ = m.node(fill_id);
        if fn_.tag != squid_check_core::Tag.array_op || m.arrayOperation(fill_id) != squid_backend_collection_ops::Op.fill {
            continue;
        }
        let fch = m.children(fill_id);
        if fch.len < 2 { continue; }
        let fill_b = cn.a;
        let count_node = fch[0];
        let count_b = localRef(m, count_node);
        let fill_ty = m.types.node(m.binding(fill_b).ty);
        if fill_ty.tag != squid_check_types::Tag.array { continue; }
        let etag = m.types.node(fill_ty.a).tag;
        if !squid_check_types::isNumeric(etag) && etag != squid_check_types::Tag.boolean {
            continue;
        }
        for j in (k + 1)..children.len {
            let jn = m.node(children[j]);
            if jn.tag == squid_check_core::Tag.loop_ {
                let linfo = m.loopInfo(children[j]);
                if linfo.kind != squid_check_core::LoopKind.range || linfo.pattern == 0 || linfo.body == 0 { break; }
                let first_n = m.node(linfo.first);
                if first_n.tag != squid_check_core::Tag.constant || first_n.a != 0 { break; }
                if !sameCountExpr(m, count_node, linfo.end) { break; }
                let pat = m.pattern(linfo.pattern);
                if pat.tag != squid_check_core::PatternTag.bind { break; }
                let iter_b = pat.a;
                var iter_arr_b: u32 = 0;
                for carry in m.loopCarries(children[j]) {
                    if carry.incoming == fill_b { iter_arr_b = carry.iteration; break; }
                }
                if iter_arr_b == 0 { break; }
                var stmts: u32[16] = [0; 16];
                var stmts_len: i64 = 0;
                let lbn = m.node(linfo.body);
                if lbn.tag == squid_check_core::Tag.suite || lbn.tag == squid_check_core::Tag.block_ {
                    let bch = m.children(linfo.body);
                    if bch.len == 0 || bch.len > 16 { break; }
                    for si in 0..bch.len { stmts[si] = bch[si]; }
                    stmts_len = bch.len;
                } else {
                    stmts[0] = linfo.body;
                    stmts_len = 1;
                }
                var wrote_full = false;
                var safe = true;
                var upd_res_b: u32 = 0;
                var budget: i64 = 128;
                for si in 0..stmts_len {
                    let sn = m.node(stmts[si]);
                    var upd_id: u32 = 0;
                    var bind_out: u32 = 0;
                    if sn.tag == squid_check_core::Tag.update {
                        upd_id = stmts[si];
                    } else if sn.tag == squid_check_core::Tag.bind && sn.c < 2 && m.node(sn.b).tag == squid_check_core::Tag.update {
                        upd_id = sn.b;
                        bind_out = sn.a;
                    }
                    if upd_id != 0 {
                        let uinfo = m.updateInfo(upd_id);
                        let sels = m.updateSelectors(upd_id);
                        if sels.len != 1 || sels[0].kind != squid_check_core::UpdateKind.index { safe = false; break; }
                        let root_b = localRef(m, uinfo.root);
                        if root_b == iter_arr_b || root_b == fill_b || (upd_res_b != 0 && root_b == upd_res_b) {
                            if localRef(m, sels[0].index) != iter_b { safe = false; break; }
                            if uinfo.self_binding != 0 && uses(g, f, uinfo.self_binding) != 0 { safe = false; break; }
                            if deadFillExprUsesOrCalls(g, m, uinfo.value, fill_b, iter_arr_b, upd_res_b, budget) { safe = false; break; }
                            wrote_full = true;
                            if bind_out != 0 { upd_res_b = bind_out; }
                        } else {
                            if deadFillExprUsesOrCalls(g, m, sels[0].index, fill_b, iter_arr_b, upd_res_b, budget) ||
                                deadFillExprUsesOrCalls(g, m, uinfo.value, fill_b, iter_arr_b, upd_res_b, budget) {
                                safe = false; break;
                            }
                        }
                    } else if sn.tag == squid_check_core::Tag.bind && sn.c < 2 {
                        if deadFillExprUsesOrCalls(g, m, sn.b, fill_b, iter_arr_b, upd_res_b, budget) { safe = false; break; }
                    } else {
                        safe = false; break;
                    }
                }
                if safe && wrote_full {
                    recordSkipFillNode(f, fill_id);
                }
                break;
            }
            if jn.tag == squid_check_core::Tag.bind && jn.c < 2 {
                if count_b != 0 && jn.a == count_b { break; }
                var budget: i64 = 64;
                if deadFillExprUsesOrCalls(g, m, jn.b, fill_b, 0, 0, budget) { break; }
                continue;
            }
            break;
        }
    }
}
recursive fn block_(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let result = g.newSlot();
    let block_locals_mark = localCount(g, f);
    let depth = open(g, f, OP_block);
    let s .= g.s;
    let mark = s.labels.len;
    s.labels.push(squid_direct_emit::Label { target: id, depth: depth, result: result });
    var last = unitVal();
    let children = m.children(id);
    let saved = f.scratch_cut;
    let saved_skip = f.skip_fill_len;
    scanDeadFills(g, f, m, children);
    for child, at in children {
        // Statements after one that always diverges are unreachable.
        if last.ty == squid_direct_types::never { break; }
        if id == f.scratch_body { markScratchPair(g, f, children, at); }
        let value, error = stmt(g, f, child);
        if error != squid_direct_types::Error.none { f.skip_fill_len = saved_skip; f.scratch_cut = saved; s.labels.resize(mark); return value, error; }
        last = value;
    }
    f.skip_fill_len = saved_skip;
    f.scratch_cut = saved;
    let builder = findComptimeBlock(f, id);
    if builder >= 0 && last.ty != squid_direct_types::never {
        let frame = f.comptime_frames[builder];
        if frame.field_ty != squid_direct_types::unit {
            return neverVal(), g.fail(m, id, "#fields builder falls through for a non-Unit field");
        }
        let carry_node = m.node(frame.loop_node);
        let start = m.extra[carry_node.c];
        let len = m.extra[carry_node.c + 1];
        for carry, at in m.loop_carries[start..start + len] {
            let error = deliverComptimeCarry(g, f, carry.backedge, frame.carry_slots.start + at, id);
            if error != squid_direct_types::Error.none { return neverVal(), error; }
        }
        let error = deliver(g, f, unitVal(), result, id);
        if error != squid_direct_types::Error.none { return neverVal(), error; }
    }
    s.labels.resize(mark);
    close(g, f);
    if g.s.slots[result].present {
        propagateSlotMask(g, f, result, block_locals_mark);
        return g.s.slots[result].value, squid_direct_types::Error.none;
    }
    // A Unit block may fall through its end.
    if last.ty != squid_direct_types::never && m.typeOf(id) == squid_check_types::unit { return unitVal(), squid_direct_types::Error.none; }
    return neverVal(), squid_direct_types::Error.none;
}
recursive fn forkNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let rt = g.runtime_();
    let saved_mark = local32(g, f);
    let saved_undo = local32(g, f);
    gget(g, rt.fork_owner_mark);
    lset(g, saved_mark);
    gget(g, rt.undo_sp);
    lset(g, saved_undo);
    gget(g, rt.owner_top);
    gset(g, rt.fork_owner_mark);
    gget(g, rt.fork_depth);
    i32Const(g, 1);
    op(g, OP_i32_add);
    gset(g, rt.fork_depth);
    let sb_err = emitSeqForkBump(g);
    if sb_err != squid_direct_types::Error.none { return neverVal(), sb_err; }
    f.tco_inhibit += 1;
    let result, error = block_(g, f, n.a);
    f.tco_inhibit -= 1;
    if error != squid_direct_types::Error.none { return result, error; }
    gget(g, rt.fork_depth);
    i32Const(g, 1);
    op(g, OP_i32_sub);
    gset(g, rt.fork_depth);
    lget(g, saved_undo);
    callf(g, rt.undo_rewind);
    lget(g, saved_mark);
    gset(g, rt.fork_owner_mark);
    return result, squid_direct_types::Error.none;
}

fn findComptimeBlock(f: const Fn&, block_: u32) -> i64 {
    if block_ == 0 { return -1; }
    var i = f.comptime_len;
    while i > 0 {
        i -= 1;
        let frame = f.comptime_frames[i];
        if frame.serial == f.serial && frame.block_ == block_ { return i; }
    }
    return -1;
}

fn findComptimeFrame(f: const Fn&, binder: u32) -> i64 {
    var i = f.comptime_len;
    while i > 0 {
        i -= 1;
        if f.comptime_frames[i].serial == f.serial && f.comptime_frames[i].binder == binder { return i; }
    }
    return -1;
}

fn recordProjVar(vars: u32[64]&, count: i64&, ty: TId) {
    if ty == 0 || count >= 64 { return; }
    for i in 0..count { if vars[i] == ty { return; } }
    vars[count] = ty;
    count += 1;
}

recursive fn collectComptimeProjectVars(m: const Module&, id: u32, binder: u32, vars: u32[64]&, count: i64&, depth: i64) {
    if id == 0 || depth >= 128 { return; }
    let n = m.node(id);
    match n.tag {
        comptime_meta => {
            if n.c == 0 {
                if n.b == binder && m.types.node(n.ty).tag == squid_check_types::Tag.variable {
                    recordProjVar(vars, count, n.ty);
                }
                collectComptimeProjectVars(m, n.a, binder, vars, count, depth + 1);
            } else if n.c == 10 && n.a == binder && m.types.node(n.ty).tag == squid_check_types::Tag.variable {
                recordProjVar(vars, count, n.ty);
            } else if n.c == 8 || n.c == 9 {
                collectComptimeProjectVars(m, n.b, binder, vars, count, depth + 1);
            }
        },
        comptime_for => {
            if n.a != binder { collectComptimeProjectVars(m, n.b, binder, vars, count, depth + 1); }
        },
        comptime_if, if_value, if_stmt, state_provider => {
            collectComptimeProjectVars(m, n.a, binder, vars, count, depth + 1);
            collectComptimeProjectVars(m, n.b, binder, vars, count, depth + 1);
            collectComptimeProjectVars(m, n.c, binder, vars, count, depth + 1);
        },
        suite, block_, product, record, array, array_op, storage => {
            for child in m.children(id) { collectComptimeProjectVars(m, child, binder, vars, count, depth + 1); }
        },
        call, contract_method, break_ => {
            for child in m.extra[n.b..n.b + n.c] { collectComptimeProjectVars(m, child, binder, vars, count, depth + 1); }
        },
        with_handle => {
            for child in m.extra[n.b..n.b + n.c] { collectComptimeProjectVars(m, child, binder, vars, count, depth + 1); }
            collectComptimeProjectVars(m, n.a, binder, vars, count, depth + 1);
        },
        bind, construct => { collectComptimeProjectVars(m, n.b, binder, vars, count, depth + 1); },
        return_, project, result_associated, fork_ => {
            collectComptimeProjectVars(m, n.a, binder, vars, count, depth + 1);
        },
        scalar, logical, apply, associated, type_same, effect_provider, handle, staging => {
            collectComptimeProjectVars(m, n.a, binder, vars, count, depth + 1);
            collectComptimeProjectVars(m, n.b, binder, vars, count, depth + 1);
        },
        pattern_bind => {
            collectComptimeProjectVars(m, n.b, binder, vars, count, depth + 1);
            collectComptimeProjectVars(m, n.c, binder, vars, count, depth + 1);
        },
        update => {
            let u = m.updateInfo(id);
            collectComptimeProjectVars(m, u.root, binder, vars, count, depth + 1);
            for step in m.updateSelectors(id) {
                if step.kind == squid_check_core::UpdateKind.comptime_field && step.projection == binder &&
                    m.types.node(step.result_type).tag == squid_check_types::Tag.variable {
                    recordProjVar(vars, count, step.result_type);
                } else if step.kind == squid_check_core::UpdateKind.index {
                    collectComptimeProjectVars(m, step.index, binder, vars, count, depth + 1);
                }
            }
            collectComptimeProjectVars(m, u.value, binder, vars, count, depth + 1);
        },
        loop_ => {
            let info = m.loopInfo(id);
            collectComptimeProjectVars(m, info.first, binder, vars, count, depth + 1);
            collectComptimeProjectVars(m, info.end, binder, vars, count, depth + 1);
            collectComptimeProjectVars(m, info.body, binder, vars, count, depth + 1);
        },
        match_ => {
            for inp in m.matchInputs(id) { collectComptimeProjectVars(m, inp, binder, vars, count, depth + 1); }
            for arm in m.matchArms(id) {
                collectComptimeProjectVars(m, arm.guard_, binder, vars, count, depth + 1);
                collectComptimeProjectVars(m, arm.body, binder, vars, count, depth + 1);
            }
        },
        closure => { collectComptimeProjectVars(m, m.closure(id).body, binder, vars, count, depth + 1); },
        spark => {
            let sinfo = m.sparkInfo(id);
            collectComptimeProjectVars(m, sinfo.source, binder, vars, count, depth + 1);
            collectComptimeProjectVars(m, sinfo.end, binder, vars, count, depth + 1);
            collectComptimeProjectVars(m, sinfo.body, binder, vars, count, depth + 1);
        },
        _ => {},
    }
}

fn comptimeFieldPos(g: Generator&, record_ty: Ty, nom_unit: u32, nom_decl: u32, fi: i64, field_count: i64) -> i64 {
    if nom_unit != 0 && g.hasUnit(nom_unit) {
        let owner .= g.units[nom_unit - 1];
        let ordinal, oerr = g.types.nominalOrdinal(owner, squid_check_types::NominalIdentity { nom_unit, nom_decl });
        if oerr == squid_direct_types::Error.none {
            let ctors = owner.nominalConstructors(ordinal);
            if ctors.len == 1 {
                let declared_payload = owner.constructor(ctors[0]).payload;
                if declared_payload != 0 && owner.types.node(declared_payload).tag == squid_check_types::Tag.record {
                    let dshape = owner.types.node(declared_payload);
                    if (dshape.b as i64) == field_count {
                        let dfield = owner.types.recordField(dshape, fi);
                        let fname, has_fname = g.types.fieldNameOf(owner, dfield.name, true);
                        if has_fname {
                            let pos = g.types.findField(record_ty, fname);
                            if pos >= 0 { return pos; }
                        }
                    }
                }
            }
        }
    }
    return fi;
}
recursive fn comptimeForNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let cstart = m.extra[n.c];
    let clen = m.extra[n.c + 1];
    let mode = m.extra[n.c + 2];
    let carries = m.loop_carries[cstart..cstart + clen];
    let target_ty, terr = lower(g, f, m.binding(n.a).ty, id);
    if terr != squid_direct_types::Error.none { return neverVal(), terr; }
    let current = g.reserveVals(carries.len);
    for carry, at in carries {
        let value, present, rerr = readBindingVal(g, f, carry.incoming, id);
        if rerr != squid_direct_types::Error.none { return neverVal(), rerr; }
        if !present { return neverVal(), g.fail(m, id, "#for carry without an incoming value"); }
        g.s.vals[current.start + at] = value;
    }
    var proj_vars: u32[64] = [0; 64];
    var proj_var_len: i64 = 0;
    let builder = mode == 2;
    if mode != 1 {
        if builder && m.types.node(m.typeOf(n.b)).tag == squid_check_types::Tag.variable {
            recordProjVar(proj_vars, proj_var_len, m.typeOf(n.b));
        }
        collectComptimeProjectVars(m, n.b, n.a, proj_vars, proj_var_len, 0);
    }
    let saved_env = f.env;
    if mode != 1 {
        var record_ty: Ty = 0;
        var nom_unit: u32 = 0;
        var nom_decl: u32 = 0;
        var ctor_tag: u32 = 0;
        if tagOf(g, target_ty) == squid_direct_types::Tag.record {
            record_ty = target_ty;
        } else if tagOf(g, target_ty) == squid_direct_types::Tag.nominal {
            if isOpaqueOutsideUnit(g, m, target_ty) {
                return neverVal(), g.failCode(m, id, squid_check_diagnostic_code::Code.type_mismatch, "opaque type representation cannot be reflected outside its defining module");
            }
            let nom_id = g.types.nominalIdentity(target_ty);
            nom_unit = nom_id.unit;
            nom_decl = nom_id.decl;
            let cases, verr = g.types.variants(target_ty);
            if verr != squid_direct_types::Error.none { return neverVal(), g.typeFailure(m, id); }
            if cases.len != 1 { return neverVal(), g.fail(m, id, "#fields requires a single-constructor data type"); }
            ctor_tag = g.types.variant_tags[cases.tags];
            let payload = g.types.variant_payloads[cases.payloads];
            if payload != squid_direct_types::unit {
                if tagOf(g, payload) != squid_direct_types::Tag.record { return neverVal(), g.fail(m, id, "#fields requires a record payload"); }
                record_ty = payload;
            }
        } else {
            return neverVal(), g.fail(m, id, "#fields requires a record or single-constructor data type");
        }
        var field_count: i64 = 0;
        if record_ty != 0 { field_count = g.types.node(record_ty).b as i64; }
        var field_vals = Vals {};
        if builder { field_vals = g.reserveVals(field_count); }
        f.loop_depth += 1;
        for fi in 0..field_count {
            let pos = comptimeFieldPos(g, record_ty, nom_unit, nom_decl, fi, field_count);
            let fld = g.types.recordField(record_ty, pos);
            f.env = saved_env;
            for pi in 0..proj_var_len { g.types.envPut(f.env, f.unit, proj_vars[pi], fld.ty); }
            for carry, at in carries { bindPut(g, f, carry.iteration, g.s.vals[current.start + at]); }
            if f.comptime_len >= 16 { f.loop_depth -= 1; f.env = saved_env; return neverVal(), g.fail(m, id, "#for nesting limit exceeded"); }
            var carry_slots = Vals {};
            var block_: u32 = 0;
            if builder {
                block_ = n.b;
                carry_slots = g.reserveVals(carries.len);
                for carry, at in carries {
                    let slot, error = fresh(g, f, g.s.vals[current.start + at].ty, id);
                    if error != squid_direct_types::Error.none { f.loop_depth -= 1; f.env = saved_env; return slot, error; }
                    g.s.vals[carry_slots.start + at] = slot;
                }
            }
            f.comptime_frames[f.comptime_len] = ComptimeFrame {
                binder: n.a, is_variants: false, target_ty: target_ty,
                nominal_unit: nom_unit, nominal_decl: nom_decl,
                index: fi as u32, ctor_tag: ctor_tag, name_id: fld.name, field_ty: fld.ty,
                serial: f.serial, block_: block_, loop_node: id, carry_slots: carry_slots,
            };
            f.comptime_len += 1;
            let iter_val, ierr = stmt(g, f, n.b);
            f.comptime_len -= 1;
            if ierr != squid_direct_types::Error.none { f.loop_depth -= 1; f.env = saved_env; return iter_val, ierr; }
            if iter_val.ty == squid_direct_types::never { f.loop_depth -= 1; f.env = saved_env; return neverVal(), squid_direct_types::Error.none; }
            if builder {
                g.s.vals[field_vals.start + pos] = iter_val;
                for at in 0..carries.len { g.s.vals[current.start + at] = g.s.vals[carry_slots.start + at]; }
                continue;
            }
            for carry, at in carries {
                let bv, ok, berr = readBindingVal(g, f, carry.backedge, id);
                if berr != squid_direct_types::Error.none { f.loop_depth -= 1; f.env = saved_env; return neverVal(), berr; }
                if ok { g.s.vals[current.start + at] = bv; }
            }
        }
        f.loop_depth -= 1;
        f.env = saved_env;
        if builder {
            for carry, at in carries { bindPut(g, f, carry.outgoing, g.s.vals[current.start + at]); }
            var payload = unitVal();
            if record_ty != 0 {
                let value, error = packProduct(g, f, id, record_ty, field_vals);
                if error != squid_direct_types::Error.none { return value, error; }
                payload = value;
            }
            if nom_unit != 0 { return wrapVariant(g, f, target_ty, ctor_tag, payload, id); }
            return payload, squid_direct_types::Error.none;
        }
    } else {
        if tagOf(g, target_ty) != squid_direct_types::Tag.nominal { return neverVal(), g.fail(m, id, "#variants requires a nominal data type"); }
        if isOpaqueOutsideUnit(g, m, target_ty) {
            return neverVal(), g.failCode(m, id, squid_check_diagnostic_code::Code.type_mismatch, "opaque type representation cannot be reflected outside its defining module");
        }
        let nom_id = g.types.nominalIdentity(target_ty);
        if !g.hasUnit(nom_id.unit) { return neverVal(), g.fail(m, id, "#variants defining unit missing"); }
        let owner .= g.units[nom_id.unit - 1];
        let ordinal, oerr = g.types.nominalOrdinal(owner, nom_id);
        if oerr != squid_direct_types::Error.none { return neverVal(), g.typeFailure(m, id); }
        let ctors = owner.nominalConstructors(ordinal);
        f.loop_depth += 1;
        for ctor_idx, ci in ctors {
            let ctor = owner.constructor(ctor_idx);
            var name_id: u32 = 0;
            let sp = owner.fieldSpelling(ctor.name);
            if sp.present { name_id = g.types.fieldName(sp.value); }
            for carry, at in carries { bindPut(g, f, carry.iteration, g.s.vals[current.start + at]); }
            if f.comptime_len >= 16 { f.loop_depth -= 1; return neverVal(), g.fail(m, id, "#for nesting limit exceeded"); }
            f.comptime_frames[f.comptime_len] = ComptimeFrame {
                binder: n.a, is_variants: true, target_ty: target_ty,
                nominal_unit: nom_id.unit, nominal_decl: nom_id.decl,
                index: ci as u32, ctor_tag: ctor.tag, name_id: name_id, field_ty: 0, serial: f.serial,
            };
            f.comptime_len += 1;
            let iter_val, ierr = stmt(g, f, n.b);
            f.comptime_len -= 1;
            if ierr != squid_direct_types::Error.none { f.loop_depth -= 1; return iter_val, ierr; }
            if iter_val.ty == squid_direct_types::never { f.loop_depth -= 1; return neverVal(), squid_direct_types::Error.none; }
            for carry, at in carries {
                let bv, ok, berr = readBindingVal(g, f, carry.backedge, id);
                if berr != squid_direct_types::Error.none { f.loop_depth -= 1; return neverVal(), berr; }
                if ok { g.s.vals[current.start + at] = bv; }
            }
        }
        f.loop_depth -= 1;
    }
    for carry, at in carries { bindPut(g, f, carry.outgoing, g.s.vals[current.start + at]); }
    return unitVal(), squid_direct_types::Error.none;
}

recursive fn comptimeIfNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    var s = Stage {..};
    let cond = evaluateStage(g, f, s, m, n.a, 0, 0);
    let failed = stageFailureText(s);
    squid_support_pooled_buffer::deinit(s.functions, stage_function_runs);
    squid_support_pooled_buffer::deinit(s.parts, part_runs);
    squid_support_pooled_buffer::deinit(s.aggregates, aggregate_runs);
    squid_support_pooled_buffer::deinit(s.bindings, binding_runs);
    if failed.len != 0 { return neverVal(), g.fail(m, n.a, failed); }
    let taken = cond.bits != 0;
    var branch = n.c;
    if taken { branch = n.b; }
    if branch != 0 {
        let res, err = stmt(g, f, branch);
        if err != squid_direct_types::Error.none { return res, err; }
        if res.ty == squid_direct_types::never { return neverVal(), squid_direct_types::Error.none; }
    }
    for merge in m.branchMerges(id) {
        var from_b = merge.else_binding;
        if taken { from_b = merge.then_binding; }
        let val, present = bindGet(g, f, from_b);
        if present { bindPut(g, f, merge.result, val); }
    }
    return unitVal(), squid_direct_types::Error.none;
}

recursive fn comptimeMetaNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    if n.c == 0 {
        let fidx = findComptimeFrame(f, n.b);
        if fidx < 0 { return neverVal(), g.fail(m, id, "comptime field projection outside #for"); }
        let cf = f.comptime_frames[fidx];
        let val, err = expr(g, f, n.a);
        if err != squid_direct_types::Error.none { return val, err; }
        var rec = val;
        if tagOf(g, val.ty) == squid_direct_types::Tag.nominal {
            if isOpaqueOutsideUnit(g, m, val.ty) {
                return neverVal(), g.failCode(m, id, squid_check_diagnostic_code::Code.type_mismatch, "opaque type representation cannot be reflected outside its defining module");
            }
            let cases, verr = g.types.variants(val.ty);
            if verr != squid_direct_types::Error.none { return neverVal(), g.typeFailure(m, id); }
            if cases.len != 1 { return neverVal(), g.fail(m, id, "val.(field) requires a single-constructor data type"); }
            let unwrapped, uerr = unwrapVariant(g, f, val, g.types.variant_tags[cases.tags], id);
            if uerr != squid_direct_types::Error.none { return neverVal(), uerr; }
            rec = unwrapped;
        }
        let pos = g.types.findField(rec.ty, cf.name_id);
        if pos < 0 { return neverVal(), g.fail(m, id, "comptime projected field missing"); }
        if !matchesComptimeFieldType(g, f, m, n.ty, cf.field_ty) {
            return neverVal(), g.fail(m, id, "comptime projection has the wrong field type");
        }
        return recordField(g, f, rec, pos, id);
    }
    if n.c == 1 {
        let fidx = findComptimeFrame(f, n.a);
        if fidx < 0 { return neverVal(), g.fail(m, id, "comptime .name outside #for"); }
        let arr_ty, terr = typeOf(g, f, id);
        if terr != squid_direct_types::Error.none { return neverVal(), terr; }
        let text = g.types.spelling(f.comptime_frames[fidx].name_id);
        var cp_count: i64 = 0;
        var p: i64 = 0;
        while p < text.len { let _, next = utf8Next(text, p); cp_count += 1; p = next; }
        let vals = g.reserveVals(cp_count);
        p = 0;
        var idx: i64 = 0;
        while p < text.len {
            let cp, next = utf8Next(text, p);
            g.s.vals[vals.start + idx] = valOf1(g, squid_direct_types::u32_, constLocal(g, f, cp));
            idx += 1;
            p = next;
        }
        return arrayFromValues(g, f, arr_ty, vals, id);
    }
    if n.c == 10 { return comptimeDefaultNode(g, f, id); }
    var s = Stage {..};
    let v = evalComptimeMetaStage(g, f, s, m, id, 0, 0);
    var result = neverVal();
    var error = squid_direct_types::Error.none;
    let failed = stageFailureText(s);
    if failed.len != 0 { error = g.fail(m, id, failed); }
    else {
        let ty, lerr = typeOf(g, f, id);
        error = lerr;
        if error == squid_direct_types::Error.none {
            var remaining: i64 = 65536;
            result, error = emitStageValue(g, f, s, v, ty, id, remaining, 0);
        }
    }
    squid_support_pooled_buffer::deinit(s.functions, stage_function_runs);
    squid_support_pooled_buffer::deinit(s.parts, part_runs);
    squid_support_pooled_buffer::deinit(s.aggregates, aggregate_runs);
    squid_support_pooled_buffer::deinit(s.bindings, binding_runs);
    return result, error;
}
// Any concrete constraints inferred for a reflection site must agree with
// the type of the field selected by this iteration.
fn matchesComptimeFieldType(g: Generator&, f: const Fn&, m: const Module&, expected: TId, actual: Ty) -> bool {
    let ty, error = g.types.lower(m, expected, f.env);
    return error != squid_direct_types::Error.none || ty == actual;
}

recursive fn bindRigidInType(g: Generator&, f: Fn&, owner_unit: u32, tid: TId, nom_args: const Ty[:], depth: i64) {
    if tid <= squid_check_types::never || depth > 64 { return; }
    let tn = g.units[owner_unit - 1].types.node(tid);
    match tn.tag {
        rigid => {
            if tn.c == 0 && (tn.b as i64) < nom_args.len {
                g.types.envPut(f.env, owner_unit, tid, nom_args[tn.b]);
            }
        },
        usage, forall, array => { bindRigidInType(g, f, owner_unit, tn.a, nom_args, depth + 1); },
        function => {
            bindRigidInType(g, f, owner_unit, tn.a, nom_args, depth + 1);
            bindRigidInType(g, f, owner_unit, tn.b, nom_args, depth + 1);
        },
        product => {
            let count = tn.b as i64;
            for at in 0..count {
                let child = g.units[owner_unit - 1].types.extra[tn.a + at];
                bindRigidInType(g, f, owner_unit, child, nom_args, depth + 1);
            }
        },
        record => {
            for fi in 0..(tn.b as i64) {
                let fty = g.units[owner_unit - 1].types.recordField(tn, fi).ty;
                bindRigidInType(g, f, owner_unit, fty, nom_args, depth + 1);
            }
        },
        nominal => {
            let count = g.units[owner_unit - 1].types.nominalArguments(tn).len;
            for ai in 0..count {
                let arg = g.units[owner_unit - 1].types.nominalArguments(tn)[ai];
                bindRigidInType(g, f, owner_unit, arg, nom_args, depth + 1);
            }
        },
        _ => {},
    }
}
recursive fn bindRigidInNode(g: Generator&, f: Fn&, owner_unit: u32, id: u32, nom_args: const Ty[:], depth: i64) {
    if id == 0 || depth > 64 { return; }
    let n = g.units[owner_unit - 1].node(id);
    if n.ty != 0 { bindRigidInType(g, f, owner_unit, n.ty, nom_args, 0); }
    match n.tag {
        suite, block_, product, record, array, array_op, storage, break_ => {
            let ch_len = g.units[owner_unit - 1].children(id).len;
            for ci in 0..ch_len {
                let ch = g.units[owner_unit - 1].children(id)[ci];
                bindRigidInNode(g, f, owner_unit, ch, nom_args, depth + 1);
            }
        },
        bind => {
            let bty = g.units[owner_unit - 1].binding(n.a).ty;
            bindRigidInType(g, f, owner_unit, bty, nom_args, 0);
            bindRigidInNode(g, f, owner_unit, n.b, nom_args, depth + 1);
        },
        construct => { bindRigidInNode(g, f, owner_unit, n.b, nom_args, depth + 1); },
        return_, project, result_associated, fork_, flat_op => { bindRigidInNode(g, f, owner_unit, n.a, nom_args, depth + 1); },
        scalar, logical, apply, associated => {
            bindRigidInNode(g, f, owner_unit, n.a, nom_args, depth + 1);
            bindRigidInNode(g, f, owner_unit, n.b, nom_args, depth + 1);
        },
        if_stmt, if_value, comptime_if => {
            bindRigidInNode(g, f, owner_unit, n.a, nom_args, depth + 1);
            bindRigidInNode(g, f, owner_unit, n.b, nom_args, depth + 1);
            bindRigidInNode(g, f, owner_unit, n.c, nom_args, depth + 1);
        },
        call => {
            let ac = g.units[owner_unit - 1].call(id).arguments.len;
            for ai in 0..ac {
                let arg = g.units[owner_unit - 1].call(id).arguments[ai];
                bindRigidInNode(g, f, owner_unit, arg, nom_args, depth + 1);
            }
        },
        closure => {
            let body_id = g.units[owner_unit - 1].closure(id).body;
            bindRigidInNode(g, f, owner_unit, body_id, nom_args, depth + 1);
        },
        match_ => {
            let ic = g.units[owner_unit - 1].matchInputs(id).len;
            for ii in 0..ic {
                let inp = g.units[owner_unit - 1].matchInputs(id)[ii];
                bindRigidInNode(g, f, owner_unit, inp, nom_args, depth + 1);
            }
            let ac = g.units[owner_unit - 1].matchArms(id).len;
            for ai in 0..ac {
                let arm = g.units[owner_unit - 1].matchArms(id)[ai];
                bindRigidInNode(g, f, owner_unit, arm.guard_, nom_args, depth + 1);
                bindRigidInNode(g, f, owner_unit, arm.body, nom_args, depth + 1);
            }
        },
        loop_ => {
            let linfo = g.units[owner_unit - 1].loopInfo(id);
            bindRigidInNode(g, f, owner_unit, linfo.first, nom_args, depth + 1);
            bindRigidInNode(g, f, owner_unit, linfo.end, nom_args, depth + 1);
            bindRigidInNode(g, f, owner_unit, linfo.body, nom_args, depth + 1);
        },
        spark => {
            let sinfo = g.units[owner_unit - 1].sparkInfo(id);
            bindRigidInNode(g, f, owner_unit, sinfo.source, nom_args, depth + 1);
            bindRigidInNode(g, f, owner_unit, sinfo.end, nom_args, depth + 1);
            bindRigidInNode(g, f, owner_unit, sinfo.body, nom_args, depth + 1);
        },
        update => {
            let uinfo = g.units[owner_unit - 1].updateInfo(id);
            bindRigidInNode(g, f, owner_unit, uinfo.root, nom_args, depth + 1);
            bindRigidInNode(g, f, owner_unit, uinfo.value, nom_args, depth + 1);
            let sc = g.units[owner_unit - 1].updateSelectors(id).len;
            for si in 0..sc {
                let sel = g.units[owner_unit - 1].updateSelectors(id)[si];
                if sel.kind == squid_check_core::UpdateKind.index {
                    bindRigidInNode(g, f, owner_unit, sel.index, nom_args, depth + 1);
                }
            }
        },
        _ => {},
    }
}

recursive fn comptimeDefaultNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let index = findComptimeFrame(f, n.a);
    if index < 0 { return neverVal(), g.fail(m, id, "comptime field default outside #for"); }
    let frame = f.comptime_frames[index];
    let owner_unit = frame.nominal_unit;
    if owner_unit != 0 && g.hasUnit(owner_unit) {
        let owner .= g.units[owner_unit - 1];
        let value_node = comptimeFieldDefault(g, frame, owner);
        if value_node != 0 {
            g.recordStagedDepUnit(owner_unit);
            if !matchesComptimeFieldType(g, f, m, n.ty, frame.field_ty) {
                return neverVal(), g.fail(m, id, "comptime default has the wrong field type");
            }
            let unit = f.unit;
            let env = f.env;
            let serial = f.serial;
            let bindings = f.bindings;
            let with_cells = f.with_cells;
            g.s.serial += 1;
            f.serial = g.s.serial;
            f.bindings = squid_support_zigmap::Map {};
            f.with_cells = squid_support_zigmap::Map {};
            f.unit = owner_unit;
            if tagOf(g, frame.target_ty) == squid_direct_types::Tag.nominal {
                var arg_buf: Ty[32] = [0; 32];
                var arg_len: i64 = 0;
                {
                    let raw_args = g.types.nominalArguments(frame.target_ty);
                    for ai in 0..min(raw_args.len, 32) { arg_buf[ai] = raw_args[ai]; arg_len += 1; }
                }
                if arg_len > 0 {
                    let ordinal, oerr = g.types.nominalOrdinal(owner, squid_check_types::NominalIdentity { owner_unit, frame.nominal_decl });
                    if oerr == squid_direct_types::Error.none {
                        let nvars = owner.types.list(owner.nominal(ordinal).variables);
                        for vi in 0..min(nvars.len, arg_len) {
                            g.types.envPut(f.env, owner_unit, nvars[vi], arg_buf[vi]);
                        }
                    }
                    bindRigidInNode(g, f, owner_unit, value_node, arg_buf[..arg_len], 0);
                }
            }
            refine(g, f, owner.typeOf(value_node), frame.field_ty);
            let value, error = stmt(g, f, value_node);
            f.unit = unit;
            f.serial = serial;
            f.bindings = bindings;
            f.with_cells = with_cells;
            f.env = env;
            if error != squid_direct_types::Error.none || value.ty == squid_direct_types::never { return value, error; }
            if value.ty != frame.field_ty { return neverVal(), g.fail(m, id, "comptime default has the wrong field type"); }
            return value, squid_direct_types::Error.none;
        }
    }
    return neverVal(), g.fail(m, id, "comptime field has no default value");
}

fn deliverComptimeCarry(g: Generator&, f: Fn&, binding: u32, slot: i64, id: u32) -> Error {
    let value, present, error = readBindingVal(g, f, binding, id);
    if error != squid_direct_types::Error.none { return error; }
    if !present { return g.fail(g.units[f.unit - 1], id, "#for carry without a value at field exit"); }
    let dest = g.s.vals[slot];
    if value.ty != dest.ty { return g.fail(g.units[f.unit - 1], id, "#for carry changes type at field exit"); }
    return copy(g, f, value, dest, id);
}

// Copies `value` into a lazily allocated result slot.
fn deliver(g: Generator&, f: const Fn&, value: Val, slot: u32, id: u32) -> Error {
    if value.ty == squid_direct_types::never { return squid_direct_types::Error.none; }
    if !g.s.slots[slot].present {
        let made, error = fresh(g, f, value.ty, id);
        if error != squid_direct_types::Error.none { return error; }
        g.s.slots[slot] = squid_direct_emit::Slot { true, made, 0, Val {} };
    }
    let sl .= g.s.slots[slot];
    let first_delivery = sl.deliver_count == 0;
    sl.deliver_count += 1;
    sl.last_src = value;
    if value.len == 1 && value.ty == squid_direct_types::u32_ {
        let cm = findCheckedMask(f, w(g, value, 0));
        if first_delivery {
            if cm >= 0 {
                let me = f.checked_masks[cm];
                sl.mask_valid = true;
                sl.mask_local = me.max_local;
                sl.mask_const = me.max_const;
                sl.mask_has_const = me.has_const;
                if me.max_local != 0xffffffff {
                    for ci in 0..f.checked_arrays_len {
                        let clen = f.checked_arrays[ci].length;
                        if findCheckedBound(f, me.max_local, clen) >= 0 {
                            sl.bound_valid = true;
                            sl.bound_len = clen;
                            break;
                        }
                    }
                }
            }
        } else if sl.mask_valid {
            if cm < 0 {
                sl.mask_valid = false;
                sl.bound_valid = false;
            } else {
                let me = f.checked_masks[cm];
                let keep_loc = if sl.mask_local != 0xffffffff && sl.mask_local == me.max_local { sl.mask_local } else { 0xffffffff };
                let keep_const = sl.mask_has_const && me.has_const;
                if keep_const && me.max_const > sl.mask_const { sl.mask_const = me.max_const; }
                sl.mask_local = keep_loc;
                sl.mask_has_const = keep_const;
                sl.mask_valid = (keep_loc != 0xffffffff) || keep_const;
                if sl.bound_valid && (keep_loc == 0xffffffff || findCheckedBound(f, keep_loc, sl.bound_len) < 0) {
                    sl.bound_valid = false;
                }
            }
        }
    } else {
        sl.mask_valid = false;
        sl.bound_valid = false;
    }
    return copy(g, f, value, g.s.slots[slot].value, id);
}

fn propagateSlotMask(g: const Generator&, f: Fn&, slot: u32, locals_mark: u32) {
    let sl = g.s.slots[slot];
    if !sl.present || !sl.mask_valid || sl.value.len != 1 || sl.value.ty != squid_direct_types::u32_ { return; }
    let loc_ok = sl.mask_local != 0xffffffff && sl.mask_local < locals_mark;
    if !loc_ok && !sl.mask_has_const { return; }
    let mloc = if loc_ok { sl.mask_local } else { 0xffffffff };
    recordCheckedMask(f, w(g, sl.value, 0), mloc, sl.mask_const, sl.mask_has_const);
    if loc_ok && sl.bound_valid && sl.bound_len != 0xffffffff && sl.bound_len < locals_mark {
        recordCheckedBound(f, mloc, sl.bound_len);
    }
}

// Locate the target once and check for scopes that release memory on exit.
fn returnTarget(g: const Generator&, f: const Fn&, target: u32) -> i64, bool {
    var at = g.s.labels.len;
    var releases = false;
    while at > f.labels_base {
        at -= 1;
        let label = g.s.labels[at];
        if label.kind == squid_direct_emit::LabelKind.loop_ {
            releases = releases || label.has_release;
        } else if label.target == target || label.kind == squid_direct_emit::LabelKind.function {
            return at, releases;
        }
    }
    return -1, releases;
}

recursive fn returnNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let at, releases = returnTarget(g, f, n.b);
    let fn_exit = at >= 0 && (g.s.labels[at].kind == squid_direct_emit::LabelKind.function ||
        (at == f.labels_base + 1 && f.fn_return_block != 0 && n.b == f.fn_return_block));
    let clean = fn_exit && !releases && f.tco_inhibit == 0 && f.handles_len == 0 && f.scratch_cut.target == 0;
    let prev_tail = f.tail_call_node;
    var value_node = n.a;
    if clean && n.a != 0 {
        let value = m.node(n.a);
        if f.assoc_tco_local != 0xffffffff && value.tag == squid_check_core::Tag.scalar &&
            associativeIntOpcode(value.op, f.assoc_tco_ty) == f.assoc_tco_opcode &&
            isExactSelfCall(g, m, value.b, BindingRef { f.unit, g.s.instances[f.instance_id].key.id }, f.self_tco_inputs.len as i64) {
            var machine = value.op;
            if value.c == 1 {
                let resolved, error = scalarMember(g, f, m, f.assoc_tco_ty, 0, value.op, n.a);
                if error != squid_direct_types::Error.none { return neverVal(), error; }
                machine = resolved;
            }
            if associativeIntOpcode(machine, f.assoc_tco_ty) == f.assoc_tco_opcode {
                let left, error = stmt(g, f, value.a);
                if error != squid_direct_types::Error.none || left.ty == squid_direct_types::never { return left, error; }
                lget(g, f.assoc_tco_local);
                push(g, left);
                op(g, f.assoc_tco_opcode);
                lset(g, f.assoc_tco_local);
                value_node = value.b;
            }
        }
        let value_tag = m.node(value_node).tag;
        if (f.self_tco_loop != 0xffffffff || squid_direct_writer::tailCallsEnabled()) &&
            (value_tag == squid_check_core::Tag.call || (value_tag == squid_check_core::Tag.apply && squid_direct_writer::tailCallsEnabled())) {
            f.tail_call_node = value_node;
        }
    }
    let value, error = stmt(g, f, value_node);
    f.tail_call_node = prev_tail;
    if error != squid_direct_types::Error.none { return value, error; }
    if value.ty == squid_direct_types::never { return neverVal(), squid_direct_types::Error.none; }
    if clean && f.direct_returns && !f.allocates && value.ty == g.s.instances[f.instance_id].result &&
        (f.self_tco_loop == 0xffffffff || f.assoc_tco_local != 0xffffffff) {
        if f.assoc_tco_local != 0xffffffff {
            lget(g, f.assoc_tco_local);
            push(g, value);
            op(g, f.assoc_tco_opcode);
        } else if f.worker_spec >= 0 {
            pushWorkerResult(g, f, value);
        } else { push(g, value); }
        op(g, OP_return_);
        return neverVal(), squid_direct_types::Error.none;
    }
    let builder = findComptimeBlock(f, n.b);
    if builder >= 0 {
        let frame = f.comptime_frames[builder];
        if value.ty != frame.field_ty { return neverVal(), g.fail(m, id, "#fields builder value has the wrong field type"); }
        for merge, at in m.branchMerges(id) {
            let error = deliverComptimeCarry(g, f, merge.then_binding, frame.carry_slots.start + at, id);
            if error != squid_direct_types::Error.none { return neverVal(), error; }
        }
    }
    if at >= 0 {
        let label = g.s.labels[at];
        let delivered = deliver(g, f, value, label.result, id);
        if delivered != squid_direct_types::Error.none { return neverVal(), delivered; }
        // Merge saved escape marks for every enclosing releasing loop left by this return.
        var lk = g.s.labels.len;
        while lk > at + 1 {
            lk -= 1;
            if g.s.labels[lk].kind == squid_direct_emit::LabelKind.loop_ && g.s.labels[lk].has_release {
                g.s.labels[lk].used = true;
                emitMergeEscapeMinCurrent(g, f, g.s.labels[lk].saved_esc);
            }
        }
        let left = leaveHandles(g, f, label.depth);
        if left != squid_direct_types::Error.none { return neverVal(), left; }
        br(g, f, OP_br, label.depth);
        return neverVal(), squid_direct_types::Error.none;
    }
    return neverVal(), g.fail(g.units[f.unit - 1], id, "return outside its block");
}

fn sameWords(g: const Generator&, left: Val, right: Val) -> bool {
    if left.len != right.len { return false; }
    for at in 0..(left.len as i64) { if g.s.words[left.start + at] != g.s.words[right.start + at] { return false; } }
    return true;
}
fn resolveLazyVariantArrayRead(g: Generator&, f: const Fn&, m: const Module&, input_id: u32) -> u32, u32, BindingRef, bool {
    let n = m.node(input_id);
    if n.tag == squid_check_core::Tag.array_op && m.arrayOperation(input_id) == squid_backend_collection_ops::Op.get {
        let ch = m.children(input_id);
        if ch.len == 2 && m.types.node(m.typeOf(ch[0])).tag == squid_check_types::Tag.array {
            return ch[0], ch[1], BindingRef { 0, 0 }, true;
        }
    } else if n.tag == squid_check_core::Tag.storage {
        let op_kind, ok = squid_check_storage_ops::opFromCode(n.c);
        let ch = m.children(input_id);
        if ok == squid_error::Error.none && op_kind == squid_check_storage_ops::Op.read && ch.len == 2 &&
            m.types.node(m.typeOf(ch[0])).tag == squid_check_types::Tag.array {
            return ch[0], ch[1], BindingRef { 0, 0 }, true;
        }
    } else if n.tag == squid_check_core::Tag.apply && m.node(n.a).tag == squid_check_core::Tag.project {
        let proj_n = m.node(n.a);
        let sp = m.fieldSpelling(m.projection(proj_n.b).field);
        if sp.present && sp.value == "at" && m.types.node(m.typeOf(proj_n.a)).tag == squid_check_types::Tag.array {
            let recv_ty, rerr = g.types.lower(m, m.typeOf(proj_n.a), f.env);
            if rerr == squid_direct_types::Error.none && tagOf(g, recv_ty) == squid_direct_types::Tag.array {
                let identity, has_id = g.receiverIdentity(recv_ty);
                if has_id {
                    let target, has_t = g.dispatchTarget(m, identity, m.projection(proj_n.b).field, squid_check_types::Operator.none);
                    if has_t && g.hasUnit(target.unit) {
                        let tm .= g.units[target.unit - 1];
                        let body .= tm.body(target.binding);
                        if body && body.is_function {
                            let params = tm.bodyParameters(body);
                            let inner = scratchReturned(tm, unwrapSingleBody(tm, body.root));
                            if params.len == 2 && inner != 0 {
                                let in_n = tm.node(inner);
                                if in_n.tag == squid_check_core::Tag.array_op && tm.arrayOperation(inner) == squid_backend_collection_ops::Op.get {
                                    let ich = tm.children(inner);
                                    if ich.len == 2 && localRef(tm, ich[0]) == params[0].binding && localRef(tm, ich[1]) == params[1].binding {
                                        return proj_n.a, n.b, target, true;
                                    }
                                } else if in_n.tag == squid_check_core::Tag.storage {
                                    let op_k, ok = squid_check_storage_ops::opFromCode(in_n.c);
                                    let ich = tm.children(inner);
                                    if ok == squid_error::Error.none && op_k == squid_check_storage_ops::Op.read &&
                                        ich.len == 2 && localRef(tm, ich[0]) == params[0].binding && localRef(tm, ich[1]) == params[1].binding {
                                        return proj_n.a, n.b, target, true;
                                    }
                                }
                            }
                        }
                    }
                }
            } else if rerr != squid_direct_types::Error.none {
                g.dropFailure();
            }
        }
    }
    return 0, 0, BindingRef { 0, 0 }, false;
}
// 5B-1: Extract 3 F32 field pattern bindings mapped to physical layout slots 0..2
// from `$Some ($Pos { x, y, z })`-shaped single-constructor record patterns.
fn extract3F32PayloadPat(
    g: Generator&,
    m: const Module&,
    subpat: u32,
    payload_ty: Ty,
    out_bs: u32[3]&,
) -> bool {
    if subpat == 0 { return false; }
    var rec_ty = payload_ty;
    var pat_id = subpat;
    if tagOf(g, payload_ty) == squid_direct_types::Tag.nominal {
        let cases, cerr = g.types.variants(payload_ty);
        if cerr != squid_direct_types::Error.none || cases.len != 1 { return false; }
        let p = m.pattern(pat_id);
        if p.tag != squid_check_core::PatternTag.constructor { return false; }
        if m.constructor(p.a).tag != g.types.variant_tags[cases.tags] { return false; }
        rec_ty = g.types.variant_payloads[cases.payloads];
        pat_id = p.b;
    }
    if tagOf(g, rec_ty) != squid_direct_types::Tag.record || g.types.node(rec_ty).b != 3 { return false; }
    let layout, lerr = g.types.layout(rec_ty);
    if lerr != squid_direct_types::Error.none || layout.len != 3 { return false; }
    if layout[0] != VT_f32 || layout[1] != VT_f32 || layout[2] != VT_f32 { return false; }
    let rp = m.pattern(pat_id);
    var prod_id: u32 = 0;
    if rp.tag == squid_check_core::PatternTag.record_payload {
        if m.pattern(rp.b).tag != squid_check_core::PatternTag.product { return false; }
        prod_id = rp.b;
    } else if rp.tag == squid_check_core::PatternTag.product {
        prod_id = pat_id;
    } else {
        return false;
    }
    let storage = m.types.node(rp.ty);
    if storage.tag != squid_check_types::Tag.record || storage.b != 3 { return false; }
    let ch = m.patternChildren(prod_id);
    if ch.len != 3 { return false; }
    var seen: bool[3] = [false; 3];
    for idx in 0..3 {
        let cp = m.pattern(ch[idx]);
        if cp.tag != squid_check_core::PatternTag.bind { return false; }
        let fsp = m.fieldSpelling(m.types.recordField(storage, idx).name);
        if !fsp.present { return false; }
        let slot = g.types.findField(rec_ty, g.types.fieldName(fsp.value));
        if slot < 0 || slot >= 3 || seen[slot] { return false; }
        seen[slot] = true;
        out_bs[slot] = cp.a;
    }
    return seen[0] && seen[1] && seen[2];
}
fn isNoopWildcardArm(m: const Module&, arm: squid_check_core::MatchArm) -> bool {
    if arm.guard_ != 0 { return false; }
    let rows = m.armRows(arm);
    if rows.len != 1 { return false; }
    let pats = m.rowPatterns(rows[0]);
    if pats.len != 1 || m.pattern(pats[0]).tag != squid_check_core::PatternTag.wildcard { return false; }
    if arm.body == 0 { return true; }
    let bn = m.node(arm.body);
    return bn.tag == squid_check_core::Tag.constant ||
        ((bn.tag == squid_check_core::Tag.suite || bn.tag == squid_check_core::Tag.block_ || bn.tag == squid_check_core::Tag.product) && bn.b == 0);
}
fn match3F32CtorExpr(
    g: Generator&,
    m: const Module&,
    val_id: u32,
    outer_ty: Ty,
    payload_ty: Ty,
    p_bs: const u32[3]&,
    v_bs: const u32[3]&,
) -> bool, Op {
    let vn = m.node(val_id);
    if vn.tag != squid_check_core::Tag.construct || m.constructor(vn.a).tag != 0 { return false, squid_check_core::Op.none; }
    var inner_id = vn.b;
    var rec_ty = payload_ty;
    var decl_storage_tid: TId = 0;
    if tagOf(g, payload_ty) == squid_direct_types::Tag.nominal {
        let cases, cerr = g.types.variants(payload_ty);
        if cerr != squid_direct_types::Error.none || cases.len != 1 { return false, squid_check_core::Op.none; }
        let in_n = m.node(inner_id);
        if in_n.tag != squid_check_core::Tag.construct { return false, squid_check_core::Op.none; }
        let ctor = m.constructor(in_n.a);
        if ctor.tag != g.types.variant_tags[cases.tags] { return false, squid_check_core::Op.none; }
        rec_ty = g.types.variant_payloads[cases.payloads];
        if ctor.payload != 0 {
            let dn = m.types.node(ctor.payload);
            if dn.tag == squid_check_types::Tag.record && dn.b == 3 {
                decl_storage_tid = ctor.payload;
            }
        }
        inner_id = in_n.b;
    }
    if tagOf(g, rec_ty) != squid_direct_types::Tag.record || g.types.node(rec_ty).b != 3 { return false, squid_check_core::Op.none; }
    let rn = m.node(inner_id);
    if rn.tag != squid_check_core::Tag.record && rn.tag != squid_check_core::Tag.product { return false, squid_check_core::Op.none; }
    let ch = m.children(inner_id);
    if ch.len != 3 { return false, squid_check_core::Op.none; }
    var storage_tid: TId = 0;
    if rn.tag == squid_check_core::Tag.record {
        storage_tid = m.typeOf(inner_id);
        let sn = m.types.node(storage_tid);
        if sn.tag != squid_check_types::Tag.record || sn.b != 3 { return false, squid_check_core::Op.none; }
    } else {
        if decl_storage_tid == 0 { return false, squid_check_core::Op.none; }
        storage_tid = decl_storage_tid;
    }
    let storage = m.types.node(storage_tid);
    var lane_exprs: u32[3] = [0; 3];
    var seen: bool[3] = [false; 3];
    for idx in 0..3 {
        var dest = idx;
        if rn.tag == squid_check_core::Tag.record {
            dest = m.recordDestinations(inner_id)[idx] as i64;
            if dest < 0 || dest >= 3 { return false, squid_check_core::Op.none; }
        }
        let fsp = m.fieldSpelling(m.types.recordField(storage, dest).name);
        if !fsp.present { return false, squid_check_core::Op.none; }
        let slot = g.types.findField(rec_ty, g.types.fieldName(fsp.value));
        if slot < 0 || slot >= 3 || seen[slot] { return false, squid_check_core::Op.none; }
        seen[slot] = true;
        lane_exprs[slot] = ch[idx];
    }
    if !seen[0] || !seen[1] || !seen[2] { return false, squid_check_core::Op.none; }
    var want_op = squid_check_core::Op.none;
    for slot in 0..3 {
        let en = m.node(lane_exprs[slot]);
        if en.tag != squid_check_core::Tag.scalar && !(en.tag == squid_check_core::Tag.associated && en.op != squid_check_core::Op.none) {
            return false, squid_check_core::Op.none;
        }
        if en.op != squid_check_core::Op.add && en.op != squid_check_core::Op.sub { return false, squid_check_core::Op.none; }
        if want_op == squid_check_core::Op.none { want_op = en.op; }
        else if en.op != want_op { return false, squid_check_core::Op.none; }
        let la = localRef(m, en.a);
        let lb = localRef(m, en.b);
        let exact = la == p_bs[slot] && lb == v_bs[slot];
        let comm = want_op == squid_check_core::Op.add && la == v_bs[slot] && lb == p_bs[slot];
        if !exact && !comm { return false, squid_check_core::Op.none; }
    }
    return want_op != squid_check_core::Op.none, want_op;
}
struct Vec3MaybeMatch {
    pos_b: u32 = 0,
    vel_b: u32 = 0,
    idx_b: u32 = 0,
    pos_arr_node: u32 = 0,
    pos_idx_node: u32 = 0,
    pos_input_id: u32 = 0,
    pos_inlined: BindingRef = BindingRef { 0, 0 },
    vel_arr_node: u32 = 0,
    vel_idx_node: u32 = 0,
    vel_input_id: u32 = 0,
    vel_inlined: BindingRef = BindingRef { 0, 0 },
    vec_op: squid_check_core::Op = squid_check_core::Op.none,
    merge_count: i64 = 0,
    merge_res: u32[2] = [0; 2],
}
fn matchVec3MaybeSimdUpdate(
    g: Generator&,
    f: Fn&,
    m: const Module&,
    id: u32,
    pos_arr_node: u32,
    pos_idx_node: u32,
    pos_input_id: u32,
    pos_inlined: BindingRef,
    pos_elem_ty: Ty,
    out: Vec3MaybeMatch&,
) -> bool {
    let info = m.matchInfo(id);
    if !info.statement { return false; }
    let arms = m.matchArms(id);
    if arms.len != 2 || arms[0].guard_ != 0 || !isNoopWildcardArm(m, arms[1]) { return false; }
    let pos_b = localRef(m, pos_arr_node);
    let idx_b = localRef(m, pos_idx_node);
    if pos_b == 0 || idx_b == 0 { return false; }
    let pos_step, pserr = stride(g, f, pos_elem_ty, id);
    if pserr != squid_direct_types::Error.none || pos_step != 16 { return false; }
    let p_cases, pcerr = g.types.variants(pos_elem_ty);
    if pcerr != squid_direct_types::Error.none || p_cases.len <= 1 { return false; }
    let p_vpos, pvperr = variantPosition(g, f, p_cases, 0, id);
    if pvperr != squid_direct_types::Error.none { return false; }
    let p_payload_ty = g.types.variant_payloads[p_cases.payloads + p_vpos];
    let p_rows = m.armRows(arms[0]);
    if p_rows.len != 1 || m.rowPatterns(p_rows[0]).len != 1 { return false; }
    let p_pat = m.pattern(m.rowPatterns(p_rows[0])[0]);
    if p_pat.tag != squid_check_core::PatternTag.constructor || m.constructor(p_pat.a).tag != 0 { return false; }
    var p_bs: u32[3] = [0; 3];
    if !extract3F32PayloadPat(g, m, p_pat.b, p_payload_ty, p_bs) { return false; }

    let inner_id = unwrapSingleBody(m, arms[0].body);
    if inner_id == 0 || m.node(inner_id).tag != squid_check_core::Tag.match_ { return false; }
    let inner_info = m.matchInfo(inner_id);
    let inner_inputs = m.matchInputs(inner_id);
    let inner_arms = m.matchArms(inner_id);
    if !inner_info.statement || inner_inputs.len != 1 || inner_arms.len != 2 ||
        inner_arms[0].guard_ != 0 || !isNoopWildcardArm(m, inner_arms[1]) { return false; }
    let v_arr_n, v_idx_n, v_inl, v_ok = resolveLazyVariantArrayRead(g, f, m, inner_inputs[0]);
    if !v_ok || localRef(m, v_idx_n) != idx_b { return false; }
    let vel_b = localRef(m, v_arr_n);
    if vel_b == 0 { return false; }
    let vel_elem_ty, vierr = g.types.lower(m, m.typeOf(inner_inputs[0]), f.env);
    if vierr != squid_direct_types::Error.none { g.dropFailure(); return false; }
    if tagOf(g, vel_elem_ty) != squid_direct_types::Tag.nominal { return false; }
    let v_boxed, vberr = isBoxed(g, f, vel_elem_ty, inner_id);
    let v_step, vserr = stride(g, f, vel_elem_ty, inner_id);
    if vberr != squid_direct_types::Error.none || v_boxed || vserr != squid_direct_types::Error.none || v_step != 16 {
        return false;
    }
    let v_cases, vcerr = g.types.variants(vel_elem_ty);
    if vcerr != squid_direct_types::Error.none || v_cases.len <= 1 { return false; }
    let v_vpos, vvperr = variantPosition(g, f, v_cases, 0, inner_id);
    if vvperr != squid_direct_types::Error.none { return false; }
    let v_payload_ty = g.types.variant_payloads[v_cases.payloads + v_vpos];
    let v_rows = m.armRows(inner_arms[0]);
    if v_rows.len != 1 || m.rowPatterns(v_rows[0]).len != 1 { return false; }
    let v_pat = m.pattern(m.rowPatterns(v_rows[0])[0]);
    if v_pat.tag != squid_check_core::PatternTag.constructor || m.constructor(v_pat.a).tag != 0 { return false; }
    var v_bs: u32[3] = [0; 3];
    if !extract3F32PayloadPat(g, m, v_pat.b, v_payload_ty, v_bs) { return false; }

    let body_stmt = unwrapSingleBody(m, inner_arms[0].body);
    if body_stmt == 0 { return false; }
    var upd_id: u32 = 0;
    var upd_bind_b: u32 = 0;
    let bsn = m.node(body_stmt);
    if bsn.tag == squid_check_core::Tag.update { upd_id = body_stmt; }
    else if bsn.tag == squid_check_core::Tag.bind && bsn.c < 2 && m.node(bsn.b).tag == squid_check_core::Tag.update {
        upd_id = bsn.b;
        upd_bind_b = bsn.a;
    } else { return false; }
    let uinfo = m.updateInfo(upd_id);
    let sels = m.updateSelectors(upd_id);
    if sels.len != 1 || sels[0].kind != squid_check_core::UpdateKind.index { return false; }
    if localRef(m, uinfo.root) != pos_b || localRef(m, sels[0].index) != idx_b { return false; }
    if uinfo.self_binding != 0 && uses(g, f, uinfo.self_binding) != 0 { return false; }
    let op_ok, found_op = match3F32CtorExpr(g, m, uinfo.value, pos_elem_ty, p_payload_ty, p_bs, v_bs);
    if !op_ok { return false; }

    let imerges = m.branchMerges(inner_id);
    if imerges.len > 1 { return false; }
    var inner_pos_res: u32 = 0;
    for im in imerges {
        let t_ok = im.then_binding == pos_b || (upd_bind_b != 0 && im.then_binding == upd_bind_b);
        if !t_ok || im.else_binding != pos_b { return false; }
        inner_pos_res = im.result;
    }
    let omerges = m.branchMerges(id);
    if omerges.len > 2 { return false; }
    for om, oi in omerges {
        let t_ok = om.then_binding == pos_b || (inner_pos_res != 0 && om.then_binding == inner_pos_res) || (upd_bind_b != 0 && om.then_binding == upd_bind_b);
        if !t_ok || om.else_binding != pos_b { return false; }
        out.merge_res[oi] = om.result;
    }
    out.pos_b = pos_b;
    out.vel_b = vel_b;
    out.idx_b = idx_b;
    out.pos_arr_node = pos_arr_node;
    out.pos_idx_node = pos_idx_node;
    out.pos_input_id = pos_input_id;
    out.pos_inlined = pos_inlined;
    out.vel_arr_node = v_arr_n;
    out.vel_idx_node = v_idx_n;
    out.vel_input_id = inner_inputs[0];
    out.vel_inlined = v_inl;
    out.vec_op = found_op;
    out.merge_count = omerges.len;
    return true;
}
// 5B-1: Intra-element v128 SIMD for 16-byte `Maybe Vec3` updates:
//   if let $Some ($Pos { x, y, z }) = pos[idx]:
//     if let $Some ($Vel { vx, vy, vz }) = vel[idx]:
//       pos[idx] := $Some ($Pos { x: x +- vx, y: y +- vy, z: z +- vz })
// Since tag($Some) == 0 == IEEE-754 +0.0, `+0.0 +- +0.0 == +0.0 == 0x00000000`,
// collapsing 11 scalar mem/FP ops to 2 v128.load + 1 f32x4.{add,sub} + 1 v128.store.
fn tryEmitVec3MaybeSimdUpdate(
    g: Generator&,
    f: Fn&,
    id: u32,
    pos_arr_node: u32,
    pos_idx_node: u32,
    pos_input_id: u32,
    pos_inlined: BindingRef,
    pos_elem_ty: Ty,
) -> Val, bool, Error {
    if g.runtime_().has_fork { return neverVal(), false, squid_direct_types::Error.none; }
    var vm = Vec3MaybeMatch {};
    var matched = false;
    {
        let m .= g.units[f.unit - 1];
        matched = matchVec3MaybeSimdUpdate(g, f, m, id, pos_arr_node, pos_idx_node, pos_input_id, pos_inlined, pos_elem_ty, vm);
    }
    if !matched { return neverVal(), false, squid_direct_types::Error.none; }

    if vm.pos_inlined.binding != 0 { g.recordInlined(vm.pos_inlined.unit, vm.pos_inlined.binding); }
    if vm.vel_inlined.binding != 0 { g.recordInlined(vm.vel_inlined.unit, vm.vel_inlined.binding); }

    let pos_val, perr = expr(g, f, vm.pos_arr_node);
    if perr != squid_direct_types::Error.none { return pos_val, true, perr; }
    let idx_val, ierr = expr(g, f, vm.pos_idx_node);
    if ierr != squid_direct_types::Error.none { return idx_val, true, ierr; }
    let idx_loc, slerr = scalarLocal(g, f, idx_val, vm.pos_input_id);
    if slerr != squid_direct_types::Error.none { return neverVal(), true, slerr; }

    let pos_addr, paerr = elementAddress(g, f, pos_val, idx_loc, vm.pos_input_id, g.units[f.unit - 1].typeOf(vm.pos_arr_node), true);
    if paerr != squid_direct_types::Error.none { return neverVal(), true, paerr; }

    let pv = local(g, f, VT_v128);
    lget(g, pos_addr);
    simdMemOp(g, SIMD_v128_load, 2, 0);
    ltee(g, pv);
    simdLaneOp(g, SIMD_i32x4_extract_lane, 0);
    op(g, OP_i32_eqz);
    let p_if = open(g, f, OP_if_);

    let vel_val, verr = expr(g, f, vm.vel_arr_node);
    if verr != squid_direct_types::Error.none { return vel_val, true, verr; }
    let vel_addr, vaerr = elementAddress(g, f, vel_val, idx_loc, vm.vel_input_id, g.units[f.unit - 1].typeOf(vm.vel_arr_node), true);
    if vaerr != squid_direct_types::Error.none { return neverVal(), true, vaerr; }

    let vv = local(g, f, VT_v128);
    lget(g, vel_addr);
    simdMemOp(g, SIMD_v128_load, 2, 0);
    ltee(g, vv);
    simdLaneOp(g, SIMD_i32x4_extract_lane, 0);
    op(g, OP_i32_eqz);
    let v_if = open(g, f, OP_if_);

    lget(g, pos_addr);
    lget(g, pv);
    lget(g, vv);
    if vm.vec_op == squid_check_core::Op.add { simdOp(g, SIMD_f32x4_add); }
    else { simdOp(g, SIMD_f32x4_sub); }
    if !f.defer_f32_nan { canonicalizeF32x4(g, f, 0xffffffff); }
    simdMemOp(g, SIMD_v128_store, 2, 0);

    popCheckedArraysAt(f, v_if);
    close(g, f);
    popCheckedArraysAt(f, p_if);
    close(g, f);
    f.checked_elems_len = 0;

    for mi in 0..vm.merge_count { bindPut(g, f, vm.merge_res[mi], pos_val); }
    return unitVal(), true, squid_direct_types::Error.none;
}

// 6A: 4x unrolled coalesced `v128` loop for 16-byte `Maybe Vec3` updates:
//   Shape 1 (contiguous pool): descending `48,32,16,0` loads/stores (4x fewer wtime
//   bounds checks) + single `v128.or` + `extract_lane 0` branch across all 4 entities!
//   Shape 2 (indirect `let id = ids[k]`): 4x descending `ids` loads (`12,8,4,0`) +
//   single combined `(pv|vv)` tag check per entity (or 4-way coalesced when pre-scanned
//   `indirect_bound_distinct_local` proves all target IDs are strictly increasing & pos != vel).
fn emitVec3SimdAddSub(g: Generator&, f: Fn&, vec_op: squid_check_core::Op, nan_v: u32) {
    if vec_op == squid_check_core::Op.add { simdOp(g, SIMD_f32x4_add); }
    else { simdOp(g, SIMD_f32x4_sub); }
    if !f.defer_f32_nan { canonicalizeF32x4(g, f, nan_v); }
}
fn tryEmitVec3MaybeLoop4x(
    g: Generator&,
    f: Fn&,
    loop_id: u32,
    info: squid_check_core::LoopInfo,
    carry_in_place: const bool[64]&,
    index: u32,
    end_local: u32,
) -> Error {
    if g.runtime_().has_fork || info.kind != squid_check_core::LoopKind.range || info.pattern == 0 || info.body == 0 {
        return squid_direct_types::Error.none;
    }
    var vm = Vec3MaybeMatch {};
    var is_indirect = false;
    var ids_arr_b: u32 = 0;
    var ind_id_b: u32 = 0;
    var matched = false;
    {
        let m .= g.units[f.unit - 1];
        let pat = m.pattern(info.pattern);
        if pat.tag != squid_check_core::PatternTag.bind { return squid_direct_types::Error.none; }
        let iter_b = pat.a;

        let carries = m.loopCarries(loop_id);
        if carries.len > 64 { return squid_direct_types::Error.none; }
        for ci in 0..carries.len { if !carry_in_place[ci] { return squid_direct_types::Error.none; } }

        var match_id: u32 = 0;
        var target_idx_b: u32 = iter_b;
        let single = unwrapSingleBody(m, info.body);
        if single != 0 && m.node(single).tag == squid_check_core::Tag.match_ {
            match_id = single;
        } else {
            let bn = m.node(info.body);
            if bn.tag == squid_check_core::Tag.suite || bn.tag == squid_check_core::Tag.block_ {
                let ch = m.children(info.body);
                if ch.len == 2 {
                    let s0 = m.node(ch[0]);
                    if s0.tag == squid_check_core::Tag.bind && s0.c < 2 && m.node(ch[1]).tag == squid_check_core::Tag.match_ {
                        let gok, ia_n, ip_n = matchArrayGet(m, s0.b);
                        if gok && localRef(m, ip_n) == iter_b {
                            let iab = localRef(m, ia_n);
                            if iab != 0 {
                                let iav, iaok = bindGet(g, f, iab);
                                if iaok && tagOf(g, iav.ty) == squid_direct_types::Tag.array &&
                                    tagOf(g, g.types.node(iav.ty).a) == squid_direct_types::Tag.u32_ {
                                    is_indirect = true;
                                    ids_arr_b = iab;
                                    ind_id_b = s0.a;
                                    target_idx_b = s0.a;
                                    match_id = ch[1];
                                }
                            }
                        }
                    }
                }
            }
        }
        if match_id == 0 { return squid_direct_types::Error.none; }
        let inputs = m.matchInputs(match_id);
        if inputs.len != 1 { return squid_direct_types::Error.none; }
        let p_arr_n, p_idx_n, p_inl, p_ok = resolveLazyVariantArrayRead(g, f, m, inputs[0]);
        if !p_ok || localRef(m, p_idx_n) != target_idx_b { return squid_direct_types::Error.none; }
        let p_elem_ty, pierr = g.types.lower(m, m.typeOf(inputs[0]), f.env);
        if pierr != squid_direct_types::Error.none { g.dropFailure(); return squid_direct_types::Error.none; }
        if tagOf(g, p_elem_ty) != squid_direct_types::Tag.nominal { return squid_direct_types::Error.none; }
        let p_boxed, pberr = isBoxed(g, f, p_elem_ty, match_id);
        if pberr != squid_direct_types::Error.none || p_boxed { return squid_direct_types::Error.none; }
        if !matchVec3MaybeSimdUpdate(g, f, m, match_id, p_arr_n, p_idx_n, inputs[0], p_inl, p_elem_ty, vm) {
            return squid_direct_types::Error.none;
        }
        // Ensure `pos` and `vel` are bound in `f` as arrays (resolving outer loop carries).
        let pv, pok = bindGet(g, f, vm.pos_b);
        let vv, vok = bindGet(g, f, vm.vel_b);
        if !pok || !vok || tagOf(g, pv.ty) != squid_direct_types::Tag.array || tagOf(g, vv.ty) != squid_direct_types::Tag.array {
            return squid_direct_types::Error.none;
        }
        matched = true;
    }
    if !matched { return squid_direct_types::Error.none; }

    if vm.pos_inlined.binding != 0 { g.recordInlined(vm.pos_inlined.unit, vm.pos_inlined.binding); }
    if vm.vel_inlined.binding != 0 { g.recordInlined(vm.vel_inlined.unit, vm.vel_inlined.binding); }

    let pos_val, _ = bindGet(g, f, vm.pos_b);
    let vel_val, _ = bindGet(g, f, vm.vel_b);
    let pos_base, pos_len = ensureCheckedArray(g, f, pos_val);
    let vel_base, vel_len = ensureCheckedArray(g, f, vel_val);

    let n4 = local32(g, f);
    lget(g, end_local); lget(g, index); op(g, OP_i32_gt_u);
    let cnt_if = open(g, f, OP_if_);
    lget(g, end_local); lget(g, index); op(g, OP_i32_sub);
    i32Const(g, 0xfffffffc); op(g, OP_i32_and); lset(g, n4);
    popCheckedArraysAt(f, cnt_if);
    op(g, OP_else_);
    i32Const(g, 0); lset(g, n4);
    close(g, f);

    var nan_v: u32 = 0xffffffff;
    if !f.defer_f32_nan {
        nan_v = local(g, f, VT_v128);
        v128Const4(g, 0x7fc00000);
        lset(g, nan_v);
    }

    if !is_indirect {
        // Shape 1: Contiguous 4x coalesced `Maybe Vec3` loop (descending 48,32,16,0).
        lget(g, n4); i32Const(g, 0); op(g, OP_i32_gt_u);
        lget(g, end_local); lget(g, pos_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
        lget(g, end_local); lget(g, vel_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
        let run_if = open(g, f, OP_if_);

        let p_ptr = local32(g, f);
        lget(g, pos_base); lget(g, index); i32Const(g, 4); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, p_ptr);
        let v_ptr = local32(g, f);
        lget(g, vel_base); lget(g, index); i32Const(g, 4); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, v_ptr);
        let rem = local32(g, f);
        lget(g, n4); lset(g, rem);

        var pv: u32[4] = [0; 4];
        var vv: u32[4] = [0; 4];
        for s in 0..4 {
            pv[s] = local(g, f, VT_v128);
            vv[s] = local(g, f, VT_v128);
        }

        let l_exit = open(g, f, OP_block);
        let l_top = open(g, f, OP_loop);
        lget(g, rem); op(g, OP_i32_eqz); br(g, f, OP_br_if, l_exit);

        // Descending loads (48, 32, 16, 0) => 1 wtime bounds check per 4 entities on pos & vel!
        lget(g, p_ptr); simdMemOp(g, SIMD_v128_load, 2, 48); lset(g, pv[3]);
        lget(g, p_ptr); simdMemOp(g, SIMD_v128_load, 2, 32); lset(g, pv[2]);
        lget(g, p_ptr); simdMemOp(g, SIMD_v128_load, 2, 16); lset(g, pv[1]);
        lget(g, p_ptr); simdMemOp(g, SIMD_v128_load, 2, 0);  lset(g, pv[0]);

        lget(g, v_ptr); simdMemOp(g, SIMD_v128_load, 2, 48); lset(g, vv[3]);
        lget(g, v_ptr); simdMemOp(g, SIMD_v128_load, 2, 32); lset(g, vv[2]);
        lget(g, v_ptr); simdMemOp(g, SIMD_v128_load, 2, 16); lset(g, vv[1]);
        lget(g, v_ptr); simdMemOp(g, SIMD_v128_load, 2, 0);  lset(g, vv[0]);

        // Coalesce all 8 lane-0 tags via v128.or => ONE movd + ONE branch for 4 entities!
        lget(g, pv[0]); lget(g, vv[0]); simdOp(g, SIMD_v128_or);
        lget(g, pv[1]); lget(g, vv[1]); simdOp(g, SIMD_v128_or); simdOp(g, SIMD_v128_or);
        lget(g, pv[2]); lget(g, vv[2]); simdOp(g, SIMD_v128_or);
        lget(g, pv[3]); lget(g, vv[3]); simdOp(g, SIMD_v128_or); simdOp(g, SIMD_v128_or);
        simdOp(g, SIMD_v128_or);
        simdLaneOp(g, SIMD_i32x4_extract_lane, 0);
        op(g, OP_i32_eqz);
        let all_if = open(g, f, OP_if_);
        for ustep in 0..4 {
            let s = 3 - ustep;
            lget(g, p_ptr);
            lget(g, pv[s]);
            lget(g, vv[s]);
            emitVec3SimdAddSub(g, f, vm.vec_op, nan_v);
            simdMemOp(g, SIMD_v128_store, 2, (s as u32) * 16);
        }
        popCheckedArraysAt(f, all_if);
        op(g, OP_else_);
        for ustep in 0..4 {
            let s = 3 - ustep;
            lget(g, pv[s]); lget(g, vv[s]); simdOp(g, SIMD_v128_or);
            simdLaneOp(g, SIMD_i32x4_extract_lane, 0);
            op(g, OP_i32_eqz);
            let s_if = open(g, f, OP_if_);
            lget(g, p_ptr);
            lget(g, pv[s]);
            lget(g, vv[s]);
            emitVec3SimdAddSub(g, f, vm.vec_op, nan_v);
            simdMemOp(g, SIMD_v128_store, 2, (s as u32) * 16);
            popCheckedArraysAt(f, s_if);
            close(g, f);
        }
        close(g, f);

        lget(g, p_ptr); i32Const(g, 64); op(g, OP_i32_add); lset(g, p_ptr);
        lget(g, v_ptr); i32Const(g, 64); op(g, OP_i32_add); lset(g, v_ptr);
        lget(g, rem); i32Const(g, 4); op(g, OP_i32_sub); lset(g, rem);
        br(g, f, OP_br, l_top);
        close(g, f);
        close(g, f);

        lget(g, index); lget(g, n4); op(g, OP_i32_add); lset(g, index);
        popCheckedArraysAt(f, run_if);
        close(g, f);
        f.checked_elems_len = 0;
        return squid_direct_types::Error.none;
    }

    // Shape 2: Indirect `let id = ids[k]` 4x coalesced `Maybe Vec3` loop!
    // Only fires when pre-scanned `5B-2` already proved every `ids[k] < min(pos_len, vel_len)`!
    if f.indirect_bound_binding != ind_id_b || f.indirect_bound_len == 0 {
        return squid_direct_types::Error.none;
    }
    if !(f.indirect_bound_len == pos_len || findCheckedLe(f, f.indirect_bound_len, pos_len) >= 0) ||
        !(f.indirect_bound_len == vel_len || findCheckedLe(f, f.indirect_bound_len, vel_len) >= 0) {
        return squid_direct_types::Error.none;
    }

    let ids_val, _ = bindGet(g, f, ids_arr_b);
    let ids_base, ids_len = ensureCheckedArray(g, f, ids_val);

    lget(g, n4); i32Const(g, 0); op(g, OP_i32_gt_u);
    lget(g, end_local); lget(g, ids_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
    let run_if = open(g, f, OP_if_);

    let ids_ptr = local32(g, f);
    lget(g, ids_base); lget(g, index); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, ids_ptr);
    let rem = local32(g, f);
    lget(g, n4); lset(g, rem);

    var id_l: u32[4] = [0; 4];
    var pa_l: u32[4] = [0; 4];
    var va_l: u32[4] = [0; 4];
    var pv_l: u32[4] = [0; 4];
    var vv_l: u32[4] = [0; 4];
    for s in 0..4 {
        id_l[s] = local32(g, f);
        pa_l[s] = local32(g, f);
        va_l[s] = local32(g, f);
        pv_l[s] = local(g, f, VT_v128);
        vv_l[s] = local(g, f, VT_v128);
    }

    // Tiered fast paths based on pre-scanned `ids` monotonicity:
    //   2 => contiguous `ids[k] == ids[0] + k` -> ZERO `ids[]` loads, 4x descending contiguous `v128` (1 bounds check / 4 entities!)
    //   1 (and pos_base != vel_base) => strictly increasing distinct IDs -> 4-way pipelined gather/scatter with 1 coalesced branch / 4 entities!
    //   else => sequential-per-entity 4x unrolled indirect loop (safe even for duplicate IDs and pos == vel!).
    var can_contig = false;
    var can_pipe = false;
    if f.indirect_bound_distinct_local != 0xffffffff {
        can_contig = true;
        lget(g, f.indirect_bound_distinct_local);
        i32Const(g, 2);
        op(g, OP_i32_eq);
        let contig_if = open(g, f, OP_if_);

        let base_off = local32(g, f);
        lget(g, ids_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);
        i32Const(g, 4); op(g, OP_i32_shl); lset(g, base_off);
        let cp_ptr = local32(g, f);
        lget(g, pos_base); lget(g, base_off); op(g, OP_i32_add); lset(g, cp_ptr);
        let cv_ptr = local32(g, f);
        lget(g, vel_base); lget(g, base_off); op(g, OP_i32_add); lset(g, cv_ptr);

        let c_exit = open(g, f, OP_block);
        let c_top = open(g, f, OP_loop);
        lget(g, rem); op(g, OP_i32_eqz); br(g, f, OP_br_if, c_exit);

        var s: i64 = 4;
        while s > 0 {
            s -= 1;
            let off = (s as u32) * 16;
            lget(g, cp_ptr); simdMemOp(g, SIMD_v128_load, 2, off); lset(g, pv_l[s]);
            lget(g, cv_ptr); simdMemOp(g, SIMD_v128_load, 2, off); lset(g, vv_l[s]);
        }
        lget(g, pv_l[0]); lget(g, vv_l[0]); simdOp(g, SIMD_v128_or);
        lget(g, pv_l[1]); lget(g, vv_l[1]); simdOp(g, SIMD_v128_or); simdOp(g, SIMD_v128_or);
        lget(g, pv_l[2]); lget(g, vv_l[2]); simdOp(g, SIMD_v128_or);
        lget(g, pv_l[3]); lget(g, vv_l[3]); simdOp(g, SIMD_v128_or); simdOp(g, SIMD_v128_or);
        simdOp(g, SIMD_v128_or);
        simdLaneOp(g, SIMD_i32x4_extract_lane, 0);
        op(g, OP_i32_eqz);
        let call_if = open(g, f, OP_if_);
        s = 4;
        while s > 0 {
            s -= 1;
            lget(g, cp_ptr); lget(g, pv_l[s]); lget(g, vv_l[s]);
            emitVec3SimdAddSub(g, f, vm.vec_op, nan_v);
            simdMemOp(g, SIMD_v128_store, 2, (s as u32) * 16);
        }
        popCheckedArraysAt(f, call_if);
        op(g, OP_else_);
        s = 4;
        while s > 0 {
            s -= 1;
            lget(g, pv_l[s]); lget(g, vv_l[s]); simdOp(g, SIMD_v128_or);
            simdLaneOp(g, SIMD_i32x4_extract_lane, 0);
            op(g, OP_i32_eqz);
            let cs_if = open(g, f, OP_if_);
            lget(g, cp_ptr); lget(g, pv_l[s]); lget(g, vv_l[s]);
            emitVec3SimdAddSub(g, f, vm.vec_op, nan_v);
            simdMemOp(g, SIMD_v128_store, 2, (s as u32) * 16);
            popCheckedArraysAt(f, cs_if);
            close(g, f);
        }
        close(g, f);

        lget(g, cp_ptr); i32Const(g, 64); op(g, OP_i32_add); lset(g, cp_ptr);
        lget(g, cv_ptr); i32Const(g, 64); op(g, OP_i32_add); lset(g, cv_ptr);
        lget(g, rem); i32Const(g, 4); op(g, OP_i32_sub); lset(g, rem);
        br(g, f, OP_br, c_top);
        close(g, f);
        close(g, f);

        popCheckedArraysAt(f, contig_if);
        op(g, OP_else_);

        can_pipe = true;
        lget(g, f.indirect_bound_distinct_local);
        i32Const(g, 1);
        op(g, OP_i32_eq);
        lget(g, pos_base); lget(g, vel_base); op(g, OP_i32_ne);
        op(g, OP_i32_and);
        let pipe_if = open(g, f, OP_if_);

        let p_exit = open(g, f, OP_block);
        let p_top = open(g, f, OP_loop);
        lget(g, rem); op(g, OP_i32_eqz); br(g, f, OP_br_if, p_exit);

        // Descending `ids` loads (12, 8, 4, 0) => 1 wtime bounds check per 4 IDs!
        lget(g, ids_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, 12); i32Const(g, 4); op(g, OP_i32_shl); lset(g, id_l[3]);
        lget(g, ids_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, 8);  i32Const(g, 4); op(g, OP_i32_shl); lset(g, id_l[2]);
        lget(g, ids_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, 4);  i32Const(g, 4); op(g, OP_i32_shl); lset(g, id_l[1]);
        lget(g, ids_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);  i32Const(g, 4); op(g, OP_i32_shl); lset(g, id_l[0]);

        for s in 0..4 {
            lget(g, pos_base); lget(g, id_l[s]); op(g, OP_i32_add); ltee(g, pa_l[s]);
            simdMemOp(g, SIMD_v128_load, 2, 0); lset(g, pv_l[s]);
            lget(g, vel_base); lget(g, id_l[s]); op(g, OP_i32_add);
            simdMemOp(g, SIMD_v128_load, 2, 0); lset(g, vv_l[s]);
        }

        // ONE combined tag check across all 4 entities!
        lget(g, pv_l[0]); lget(g, vv_l[0]); simdOp(g, SIMD_v128_or);
        lget(g, pv_l[1]); lget(g, vv_l[1]); simdOp(g, SIMD_v128_or); simdOp(g, SIMD_v128_or);
        lget(g, pv_l[2]); lget(g, vv_l[2]); simdOp(g, SIMD_v128_or);
        lget(g, pv_l[3]); lget(g, vv_l[3]); simdOp(g, SIMD_v128_or); simdOp(g, SIMD_v128_or);
        simdOp(g, SIMD_v128_or);
        simdLaneOp(g, SIMD_i32x4_extract_lane, 0);
        op(g, OP_i32_eqz);
        let all_if = open(g, f, OP_if_);
        for s in 0..4 {
            lget(g, pa_l[s]); lget(g, pv_l[s]); lget(g, vv_l[s]);
            emitVec3SimdAddSub(g, f, vm.vec_op, nan_v);
            simdMemOp(g, SIMD_v128_store, 2, 0);
        }
        popCheckedArraysAt(f, all_if);
        op(g, OP_else_);
        for s in 0..4 {
            lget(g, pv_l[s]); lget(g, vv_l[s]); simdOp(g, SIMD_v128_or);
            simdLaneOp(g, SIMD_i32x4_extract_lane, 0);
            op(g, OP_i32_eqz);
            let s_if = open(g, f, OP_if_);
            lget(g, pa_l[s]); lget(g, pv_l[s]); lget(g, vv_l[s]);
            emitVec3SimdAddSub(g, f, vm.vec_op, nan_v);
            simdMemOp(g, SIMD_v128_store, 2, 0);
            popCheckedArraysAt(f, s_if);
            close(g, f);
        }
        close(g, f);

        lget(g, ids_ptr); i32Const(g, 16); op(g, OP_i32_add); lset(g, ids_ptr);
        lget(g, rem); i32Const(g, 4); op(g, OP_i32_sub); lset(g, rem);
        br(g, f, OP_br, p_top);
        close(g, f);
        close(g, f);

        popCheckedArraysAt(f, pipe_if);
        op(g, OP_else_);
    }

    // Sequential-per-entity 4x unrolled indirect loop (safe even for duplicate IDs and pos == vel!).
    let s_exit = open(g, f, OP_block);
    let s_top = open(g, f, OP_loop);
    lget(g, rem); op(g, OP_i32_eqz); br(g, f, OP_br_if, s_exit);

    lget(g, ids_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, 12); i32Const(g, 4); op(g, OP_i32_shl); lset(g, id_l[3]);
    lget(g, ids_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, 8);  i32Const(g, 4); op(g, OP_i32_shl); lset(g, id_l[2]);
    lget(g, ids_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, 4);  i32Const(g, 4); op(g, OP_i32_shl); lset(g, id_l[1]);
    lget(g, ids_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);  i32Const(g, 4); op(g, OP_i32_shl); lset(g, id_l[0]);

    for s in 0..4 {
        lget(g, pos_base); lget(g, id_l[s]); op(g, OP_i32_add); ltee(g, pa_l[0]);
        simdMemOp(g, SIMD_v128_load, 2, 0); lset(g, pv_l[0]);
        lget(g, vel_base); lget(g, id_l[s]); op(g, OP_i32_add);
        simdMemOp(g, SIMD_v128_load, 2, 0); lset(g, vv_l[0]);
        lget(g, pv_l[0]); lget(g, vv_l[0]); simdOp(g, SIMD_v128_or);
        simdLaneOp(g, SIMD_i32x4_extract_lane, 0);
        op(g, OP_i32_eqz);
        let u_if = open(g, f, OP_if_);
        lget(g, pa_l[0]); lget(g, pv_l[0]); lget(g, vv_l[0]);
        emitVec3SimdAddSub(g, f, vm.vec_op, nan_v);
        simdMemOp(g, SIMD_v128_store, 2, 0);
        popCheckedArraysAt(f, u_if);
        close(g, f);
    }

    lget(g, ids_ptr); i32Const(g, 16); op(g, OP_i32_add); lset(g, ids_ptr);
    lget(g, rem); i32Const(g, 4); op(g, OP_i32_sub); lset(g, rem);
    br(g, f, OP_br, s_top);
    close(g, f);
    close(g, f);

    if can_pipe { close(g, f); }
    if can_contig { close(g, f); }

    lget(g, index); lget(g, n4); op(g, OP_i32_add); lset(g, index);
    popCheckedArraysAt(f, run_if);
    close(g, f);
    f.checked_elems_len = 0;
    return squid_direct_types::Error.none;
}

recursive fn isIrrefutableSubpat(m: const Module&, pat_id: u32, depth: i64 = 0) -> bool {
    if pat_id == 0 { return true; }
    if depth >= 16 { return false; }
    let pat = m.pattern(pat_id);
    match pat.tag {
        wildcard, bind => { return true; },
        product => {
            for ch in m.patternChildren(pat_id) {
                if !isIrrefutableSubpat(m, ch, depth + 1) { return false; }
            }
            return true;
        },
        record_payload => { return isIrrefutableSubpat(m, pat.b, depth + 1); },
        _ => { return false; },
    }
}

recursive fn match_(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let split_val, did_split, split_err = tryEmitSplitSumMatch(g, f, id);
    if split_err != squid_direct_types::Error.none { return split_val, split_err; }
    if did_split { return split_val, squid_direct_types::Error.none; }
    // Lazy variant payload fast path: when matching an unboxed multi-constructor
    // nominal directly from a `Tag.array` element read (`pos[i]`, `pool.at id`),
    // load ONLY the 4-byte tag before branching and load payload words only inside
    // matching non-wildcard constructor arms.
    var lazy_arr_node: u32 = 0;
    var lazy_idx_node: u32 = 0;
    var lazy_input_id: u32 = 0;
    var lazy_inlined = BindingRef { 0, 0 };
    var lazy_input_ty: Ty = 0;
    var use_lazy_variant = false;
    {
        let m .= g.units[f.unit - 1];
        let inputs = m.matchInputs(id);
        if inputs.len == 1 {
            let arr_n, idx_n, inl_t, ok = resolveLazyVariantArrayRead(g, f, m, inputs[0]);
            if ok {
                let in_ty, ierr = g.types.lower(m, m.typeOf(inputs[0]), f.env);
                if ierr == squid_direct_types::Error.none && tagOf(g, in_ty) == squid_direct_types::Tag.nominal {
                    let boxed, berr = isBoxed(g, f, in_ty, id);
                    let is_niche, _, _, _, nerr = g.types.nullableNiche(in_ty);
                    let cases, cerr = g.types.variants(in_ty);
                    if berr == squid_direct_types::Error.none && !boxed && nerr == squid_direct_types::Error.none && !is_niche && cerr == squid_direct_types::Error.none && cases.len > 1 {
                        var arms_ok = true;
                        for arm in m.matchArms(id) {
                            let rows = m.armRows(arm);
                            if rows.len != 1 { arms_ok = false; break; }
                            let pats = m.rowPatterns(rows[0]);
                            if pats.len != 1 { arms_ok = false; break; }
                            let ptag = m.pattern(pats[0]).tag;
                            if ptag != squid_check_core::PatternTag.wildcard && ptag != squid_check_core::PatternTag.constructor {
                                arms_ok = false;
                                break;
                            }
                        }
                        if arms_ok {
                            lazy_arr_node = arr_n;
                            lazy_idx_node = idx_n;
                            lazy_input_id = inputs[0];
                            lazy_inlined = inl_t;
                            lazy_input_ty = in_ty;
                            use_lazy_variant = true;
                        }
                    }
                } else if ierr != squid_direct_types::Error.none {
                    g.dropFailure();
                }
            }
        }
    }
    if use_lazy_variant {
        let v3_val, v3_done, v3_err = tryEmitVec3MaybeSimdUpdate(g, f, id, lazy_arr_node, lazy_idx_node, lazy_input_id, lazy_inlined, lazy_input_ty);
        if v3_err != squid_direct_types::Error.none { return v3_val, v3_err; }
        if v3_done { return v3_val, squid_direct_types::Error.none; }
        if lazy_inlined.binding != 0 { g.recordInlined(lazy_inlined.unit, lazy_inlined.binding); }
        let arr_val, aerr = expr(g, f, lazy_arr_node);
        if aerr != squid_direct_types::Error.none { return arr_val, aerr; }
        let pos_val, perr = expr(g, f, lazy_idx_node);
        if perr != squid_direct_types::Error.none { return pos_val, perr; }
        let idx_local, serr = scalarLocal(g, f, pos_val, lazy_input_id);
        if serr != squid_direct_types::Error.none { return neverVal(), serr; }
        let elem_addr, eerr = elementAddress(g, f, arr_val, idx_local, lazy_input_id, g.units[f.unit - 1].typeOf(lazy_arr_node), true);
        if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
        let _, lazy_payload_off, lp_err = g.types.sumTagInfo(lazy_input_ty);
        if lp_err != squid_direct_types::Error.none { return neverVal(), g.typeFailure(g.units[f.unit - 1], id); }
        let tag_local = local32(g, f);
        lget(g, elem_addr);
        let tlerr = emitTagLoad(g, lazy_input_ty, 0);
        if tlerr != squid_direct_types::Error.none { return neverVal(), g.typeFailure(g.units[f.unit - 1], id); }
        lset(g, tag_local);

        let info = g.units[f.unit - 1].matchInfo(id);
        let merges_len = g.units[f.unit - 1].branchMerges(id).len;
        let result = g.newSlot();
        let merged = newSlots(g, merges_len);
        var falls = false;
        let done = open(g, f, OP_block);
        let arms_len = g.units[f.unit - 1].matchArms(id).len;
        let cases, verr = g.types.variants(lazy_input_ty);
        if verr != squid_direct_types::Error.none { return neverVal(), g.typeFailure(g.units[f.unit - 1], id); }
        // Dense constructor tag jump table (`br_table`) when >= 3 unguarded arms have irrefutable subpatterns.
        var use_br_table = arms_len >= 3 && arms_len <= 64 && merges_len == 0;
        var tbl_arm: i64[64] = [-1; 64];
        var tbl_max: u32 = 0;
        var tbl_wild: i64 = -1;
        if use_br_table {
            let pm .= g.units[f.unit - 1];
            for ai in 0..arms_len {
                let arm = pm.matchArms(id)[ai];
                if arm.guard_ != 0 { use_br_table = false; break; }
                let pat = pm.pattern(pm.rowPatterns(pm.armRows(arm)[0])[0]);
                if pat.tag == squid_check_core::PatternTag.wildcard {
                    if tbl_wild < 0 && ai == arms_len - 1 { tbl_wild = ai; }
                    else { use_br_table = false; break; }
                } else if pat.tag == squid_check_core::PatternTag.constructor {
                    if !isIrrefutableSubpat(pm, pat.b) { use_br_table = false; break; }
                    let ctag = pm.constructor(pat.a).tag;
                    if ctag >= 64 { use_br_table = false; break; }
                    if tbl_arm[ctag] < 0 { tbl_arm[ctag] = ai; }
                    if ctag > tbl_max { tbl_max = ctag; }
                } else {
                    use_br_table = false;
                    break;
                }
            }
        }
        if use_br_table {
            let span = (tbl_max + 1) as i64;
            var trap_blk: u32 = 0;
            if tbl_wild < 0 { trap_blk = open(g, f, OP_block); }
            var arm_blks: u32[64] = [0; 64];
            var bi = arms_len;
            while bi > 0 {
                bi -= 1;
                arm_blks[bi] = open(g, f, OP_block);
            }
            lget(g, tag_local);
            op(g, OP_br_table);
            uleb(g, span as u32);
            let default_depth = if tbl_wild >= 0 { f.depth - arm_blks[tbl_wild] } else { f.depth - trap_blk };
            for ti in 0..span {
                let target_arm = tbl_arm[ti];
                if target_arm >= 0 { uleb(g, f.depth - arm_blks[target_arm]); }
                else { uleb(g, default_depth); }
            }
            uleb(g, default_depth);
            for arm_index in 0..arms_len {
                close(g, f);
                var pat_tag = squid_check_core::PatternTag.wildcard;
                var ctor_tag: u32 = 0;
                var subpat: u32 = 0;
                var subpat_is_wild = true;
                var body_id: u32 = 0;
                {
                    let pm .= g.units[f.unit - 1];
                    let arm = pm.matchArms(id)[arm_index];
                    body_id = arm.body;
                    let pat = pm.pattern(pm.rowPatterns(pm.armRows(arm)[0])[0]);
                    pat_tag = pat.tag;
                    if pat_tag == squid_check_core::PatternTag.constructor {
                        ctor_tag = pm.constructor(pat.a).tag;
                        subpat = pat.b;
                        if subpat != 0 && pm.pattern(subpat).tag != squid_check_core::PatternTag.wildcard {
                            subpat_is_wild = false;
                        }
                    }
                }
                var saved_tag_idx: i64 = -1;
                var saved_tag_prev: u32 = 0xffffffff;
                if pat_tag == squid_check_core::PatternTag.constructor {
                    if tagOf(g, arr_val.ty) == squid_direct_types::Tag.array {
                        let elem_step, sterr = stride(g, f, lazy_input_ty, id);
                        if sterr == squid_direct_types::Error.none {
                            let tidx, tprev = recordCheckedElemTag(f, w(g, arr_val, 0), w(g, arr_val, 1), idx_local, elem_step, ctor_tag);
                            saved_tag_idx = tidx;
                            saved_tag_prev = tprev;
                        }
                    }
                    if !subpat_is_wild {
                        let vpos, vperr = variantPosition(g, f, cases, ctor_tag, id);
                        if vperr != squid_direct_types::Error.none { return neverVal(), vperr; }
                        let payload_ty = g.types.variant_payloads[cases.payloads + vpos];
                        let is_out, voerr = g.types.variantOutlined(lazy_input_ty, vpos);
                        if voerr != squid_direct_types::Error.none { return neverVal(), g.typeFailure(g.units[f.unit - 1], id); }
                        var payload_val = neverVal();
                        if is_out {
                            let ptr = local32(g, f);
                            lget(g, elem_addr);
                            op(g, OP_i32_load); uleb(g, 2); uleb(g, lazy_payload_off);
                            lset(g, ptr);
                            let loaded, lerr = readOutlinedPayload(g, f, ptr, payload_ty, id);
                            if lerr != squid_direct_types::Error.none { return neverVal(), lerr; }
                            payload_val = loaded;
                        } else {
                            let loaded, lerr = loadAt(g, f, elem_addr, lazy_payload_off, payload_ty, id);
                            if lerr != squid_direct_types::Error.none { return neverVal(), lerr; }
                            payload_val = loaded;
                        }
                        let tested = test_(g, f, subpat, payload_val, false, 0, id);
                        if tested != squid_direct_types::Error.none { return neverVal(), tested; }
                    }
                }
                let body, berr = stmt(g, f, body_id);
                if saved_tag_idx >= 0 && saved_tag_idx < f.checked_elems_len {
                    f.checked_elems[saved_tag_idx].known_tag = saved_tag_prev;
                }
                if berr != squid_direct_types::Error.none { return body, berr; }
                if body.ty != squid_direct_types::never {
                    falls = true;
                    if !info.statement {
                        let delivered = deliver(g, f, body, result, id);
                        if delivered != squid_direct_types::Error.none { return neverVal(), delivered; }
                    }
                }
                br(g, f, OP_br, done);
            }
            if tbl_wild < 0 {
                close(g, f);
                op(g, OP_unreachable_);
            }
            close(g, f);
            if !falls { return neverVal(), squid_direct_types::Error.none; }
            if info.statement { return unitVal(), squid_direct_types::Error.none; }
            if g.s.slots[result].present { return g.s.slots[result].value, squid_direct_types::Error.none; }
            return neverVal(), squid_direct_types::Error.none;
        }
        for arm_index in 0..arms_len {
            let next = open(g, f, OP_block);
            var pat_tag = squid_check_core::PatternTag.wildcard;
            var ctor_tag: u32 = 0;
            var subpat: u32 = 0;
            var subpat_is_wild = true;
            var guard_id: u32 = 0;
            var body_id: u32 = 0;
            {
                let pm .= g.units[f.unit - 1];
                let arm = pm.matchArms(id)[arm_index];
                guard_id = arm.guard_;
                body_id = arm.body;
                let pat = pm.pattern(pm.rowPatterns(pm.armRows(arm)[0])[0]);
                pat_tag = pat.tag;
                if pat_tag == squid_check_core::PatternTag.constructor {
                    ctor_tag = pm.constructor(pat.a).tag;
                    subpat = pat.b;
                    if subpat != 0 && pm.pattern(subpat).tag != squid_check_core::PatternTag.wildcard {
                        subpat_is_wild = false;
                    }
                }
            }
            var saved_tag_idx: i64 = -1;
            var saved_tag_prev: u32 = 0xffffffff;
            if pat_tag == squid_check_core::PatternTag.constructor {
                lget(g, tag_local);
                i32Const(g, ctor_tag);
                op(g, OP_i32_ne);
                failIf(g, f, true, next);
                if tagOf(g, arr_val.ty) == squid_direct_types::Tag.array {
                    let elem_step, sterr = stride(g, f, lazy_input_ty, id);
                    if sterr == squid_direct_types::Error.none {
                        let tidx, tprev = recordCheckedElemTag(f, w(g, arr_val, 0), w(g, arr_val, 1), idx_local, elem_step, ctor_tag);
                        saved_tag_idx = tidx;
                        saved_tag_prev = tprev;
                    }
                }
                if !subpat_is_wild {
                    let vpos, vperr = variantPosition(g, f, cases, ctor_tag, id);
                    if vperr != squid_direct_types::Error.none { return neverVal(), vperr; }
                    let payload_ty = g.types.variant_payloads[cases.payloads + vpos];
                    let is_out, voerr = g.types.variantOutlined(lazy_input_ty, vpos);
                    if voerr != squid_direct_types::Error.none { return neverVal(), g.typeFailure(g.units[f.unit - 1], id); }
                    var payload_val = neverVal();
                    if is_out {
                        let ptr = local32(g, f);
                        lget(g, elem_addr);
                        op(g, OP_i32_load); uleb(g, 2); uleb(g, lazy_payload_off);
                        lset(g, ptr);
                        let loaded, lerr = readOutlinedPayload(g, f, ptr, payload_ty, id);
                        if lerr != squid_direct_types::Error.none { return neverVal(), lerr; }
                        payload_val = loaded;
                    } else {
                        let loaded, lerr = loadAt(g, f, elem_addr, lazy_payload_off, payload_ty, id);
                        if lerr != squid_direct_types::Error.none { return neverVal(), lerr; }
                        payload_val = loaded;
                    }
                    let tested = test_(g, f, subpat, payload_val, true, next, id);
                    if tested != squid_direct_types::Error.none { return neverVal(), tested; }
                }
            }
            if guard_id != 0 {
                let guard_value, gerr = expr(g, f, guard_id);
                if gerr != squid_direct_types::Error.none { return guard_value, gerr; }
                push(g, guard_value);
                op(g, OP_i32_eqz);
                br(g, f, OP_br_if, next);
            }
            let body, berr = stmt(g, f, body_id);
            if saved_tag_idx >= 0 && saved_tag_idx < f.checked_elems_len {
                f.checked_elems[saved_tag_idx].known_tag = saved_tag_prev;
            }
            if berr != squid_direct_types::Error.none { return body, berr; }
            if body.ty != squid_direct_types::never {
                falls = true;
                if !info.statement {
                    let delivered = deliver(g, f, body, result, id);
                    if delivered != squid_direct_types::Error.none { return neverVal(), delivered; }
                }
                if merges_len != 0 && arm_index < 2 {
                    for at in 0..merges_len {
                        let merge = g.units[f.unit - 1].branchMerges(id)[at];
                        var binding = merge.else_binding;
                        if arm_index == 0 { binding = merge.then_binding; }
                        let value, present = bindGet(g, f, binding);
                        if present {
                            let delivered = deliver(g, f, value, merged + (at as u32), id);
                            if delivered != squid_direct_types::Error.none { return neverVal(), delivered; }
                        }
                    }
                }
            }
            br(g, f, OP_br, done);
            close(g, f);
        }
        op(g, OP_unreachable_);
        close(g, f);
        let pm .= g.units[f.unit - 1];
        for merge, at in pm.branchMerges(id) {
            let slot = g.s.slots[merged + at];
            if slot.present {
                bindPut(g, f, merge.result, slot.value);
                let ct1, ok1 = withCellType(g, f, merge.then_binding);
                if ok1 { squid_support_zigmap::put(g.s.map_pool, f.with_cells, merge.result, ct1); }
                else {
                    let ct2, ok2 = withCellType(g, f, merge.else_binding);
                    if ok2 { squid_support_zigmap::put(g.s.map_pool, f.with_cells, merge.result, ct2); }
                }
            }
        }
        if !falls { return neverVal(), squid_direct_types::Error.none; }
        if info.statement { return unitVal(), squid_direct_types::Error.none; }
        if g.s.slots[result].present { return g.s.slots[result].value, squid_direct_types::Error.none; }
        return neverVal(), squid_direct_types::Error.none;
    }
    let m .= g.units[f.unit - 1];
    let info = m.matchInfo(id);
    let inputs = m.matchInputs(id);
    let values = g.reserveVals(inputs.len);
    for input, at in inputs {
        let value, error = expr(g, f, input);
        if error != squid_direct_types::Error.none { return value, error; }
        g.s.vals[values.start + at] = value;
    }
    let merges = m.branchMerges(id);
    if inputs.len == 1 && merges.len == 0 {
        let input_val = g.s.vals[values.start];
        if input_val.len == 1 && tagOf(g, input_val.ty) == squid_direct_types::Tag.nominal {
            let known_tag, has_known = findConstTag(f, w(g, input_val, 0));
            if has_known {
                let boxed, berr = isBoxed(g, f, input_val.ty, id);
                let is_niche, _, _, _, nerr = g.types.nullableNiche(input_val.ty);
                let cases, cerr = g.types.variants(input_val.ty);
                if berr == squid_direct_types::Error.none && !boxed && nerr == squid_direct_types::Error.none && !is_niche && cerr == squid_direct_types::Error.none && cases.len > 1 {
                    let arms = m.matchArms(id);
                    var matched_arm: i64 = -1;
                    var matched_bind: u32 = 0;
                    var can_fold = true;
                    for arm, arm_index in arms {
                        if arm.guard_ != 0 { can_fold = false; break; }
                        let rows = m.armRows(arm);
                        var row_hit = false;
                        for row in rows {
                            let patterns = m.rowPatterns(row);
                            if patterns.len != 1 { can_fold = false; break; }
                            let pat = m.pattern(patterns[0]);
                            match pat.tag {
                                wildcard => { row_hit = true; break; },
                                bind => { row_hit = true; matched_bind = pat.a; break; },
                                constructor => {
                                    if pat.b != 0 { can_fold = false; break; }
                                    if m.constructor(pat.a).tag == known_tag { row_hit = true; break; }
                                },
                                _ => { can_fold = false; break; },
                            }
                        }
                        if !can_fold { break; }
                        if row_hit { matched_arm = arm_index; break; }
                    }
                    if can_fold && matched_arm >= 0 {
                        if matched_bind != 0 {
                            refine(g, f, m.binding(matched_bind).ty, input_val.ty);
                            bindPut(g, f, matched_bind, input_val);
                        }
                        let arm_body = arms[matched_arm].body;
                        let body_val, berr2 = stmt(g, f, arm_body);
                        if berr2 != squid_direct_types::Error.none { return body_val, berr2; }
                        if body_val.ty == squid_direct_types::never { return neverVal(), squid_direct_types::Error.none; }
                        if info.statement { return unitVal(), squid_direct_types::Error.none; }
                        return body_val, squid_direct_types::Error.none;
                    }
                }
            }
        }
    }
    let result = g.newSlot();
    let merged = newSlots(g, merges.len);
    var falls = false;
    let done = open(g, f, OP_block);
    let arms = m.matchArms(id);
    var fbip_block: u32 = 0;
    var fbip_ty: Ty = 0;
    if inputs.len == 1 && !g.runtime_().has_fork {
        let matched_binding = localRef(m, inputs[0]);
        if matched_binding != 0 && isUniqueBoxed(g, f, matched_binding) && uses(g, f, matched_binding) == 1 && !bindingCaptured(g, f, matched_binding) {
            let input_val = g.s.vals[values.start];
            let boxed, berr = isBoxed(g, f, input_val.ty, id);
            if berr == squid_direct_types::Error.none && boxed && input_val.len == 1 {
                fbip_block = w(g, input_val, 0);
                fbip_ty = input_val.ty;
            }
        }
    }
    // Dense jump table (`br_table`) for general single-input matches over
    // dense integer literals (U32/U8/I32) or dense constructor tags (>= 3 arms, span <= 64).
    if inputs.len == 1 && merges.len == 0 && arms.len >= 3 && arms.len <= 64 && fbip_block == 0 {
        let in_val = g.s.vals[values.start];
        let in_tag = tagOf(g, in_val.ty);
        let is_int_switch = in_tag == squid_direct_types::Tag.u32_ || in_tag == squid_direct_types::Tag.u8_ || in_tag == squid_direct_types::Tag.i32_;
        var is_nom_switch = false;
        var nom_boxed = false;
        if in_tag == squid_direct_types::Tag.nominal {
            let nb, nberr = isBoxed(g, f, in_val.ty, id);
            let nc, ncerr = g.types.variants(in_val.ty);
            if nberr == squid_direct_types::Error.none && ncerr == squid_direct_types::Error.none && nc.len > 1 {
                is_nom_switch = true;
                nom_boxed = nb;
            }
        }
        if is_int_switch || is_nom_switch {
            var sw_ok = true;
            var sw_min: u32 = 0xffffffff;
            var sw_max: u32 = 0;
            var sw_wild: i64 = -1;
            var sw_wild_bind: u32 = 0;
            for arm, ai in arms {
                if arm.guard_ != 0 { sw_ok = false; break; }
                let rows = m.armRows(arm);
                for row in rows {
                    let pats = m.rowPatterns(row);
                    if pats.len != 1 { sw_ok = false; break; }
                    let pat = m.pattern(pats[0]);
                    if pat.tag == squid_check_core::PatternTag.wildcard || pat.tag == squid_check_core::PatternTag.bind {
                        if rows.len != 1 || sw_wild >= 0 || ai != arms.len - 1 { sw_ok = false; break; }
                        sw_wild = ai;
                        if pat.tag == squid_check_core::PatternTag.bind { sw_wild_bind = pat.a; }
                    } else if is_int_switch && pat.tag == squid_check_core::PatternTag.constant {
                        if pat.a < sw_min { sw_min = pat.a; }
                        if pat.a > sw_max { sw_max = pat.a; }
                    } else if is_nom_switch && pat.tag == squid_check_core::PatternTag.constructor {
                        if rows.len != 1 || !isIrrefutableSubpat(m, pat.b) { sw_ok = false; break; }
                        let ctag = m.constructor(pat.a).tag;
                        if ctag < sw_min { sw_min = ctag; }
                        if ctag > sw_max { sw_max = ctag; }
                    } else {
                        sw_ok = false;
                        break;
                    }
                }
                if !sw_ok { break; }
            }
            if sw_ok && sw_min <= sw_max && (sw_max - sw_min) < 64 {
                let span = (sw_max - sw_min + 1) as i64;
                var tbl_arm: i64[64] = [-1; 64];
                for arm, ai in arms {
                    for row in m.armRows(arm) {
                        let pat = m.pattern(m.rowPatterns(row)[0]);
                        if is_int_switch && pat.tag == squid_check_core::PatternTag.constant {
                            let idx = (pat.a - sw_min) as i64;
                            if tbl_arm[idx] < 0 { tbl_arm[idx] = ai; }
                        } else if is_nom_switch && pat.tag == squid_check_core::PatternTag.constructor {
                            let idx = (m.constructor(pat.a).tag - sw_min) as i64;
                            if tbl_arm[idx] < 0 { tbl_arm[idx] = ai; }
                        }
                    }
                }
                var trap_blk: u32 = 0;
                if sw_wild < 0 { trap_blk = open(g, f, OP_block); }
                var arm_blks: u32[64] = [0; 64];
                var bi = arms.len;
                while bi > 0 {
                    bi -= 1;
                    arm_blks[bi] = open(g, f, OP_block);
                }
                if is_nom_switch {
                    let terr = emitValueTag(g, f, in_val, id);
                    if terr != squid_direct_types::Error.none { return neverVal(), terr; }
                } else {
                    lget(g, w(g, in_val, 0));
                }
                if sw_min != 0 {
                    i32Const(g, sw_min);
                    op(g, OP_i32_sub);
                }
                op(g, OP_br_table);
                uleb(g, span as u32);
                let default_depth = if sw_wild >= 0 { f.depth - arm_blks[sw_wild] } else { f.depth - trap_blk };
                for ti in 0..span {
                    let ta = tbl_arm[ti];
                    if ta >= 0 { uleb(g, f.depth - arm_blks[ta]); }
                    else { uleb(g, default_depth); }
                }
                uleb(g, default_depth);
                for arm, ai in arms {
                    close(g, f);
                    let saved_b = squid_support_zigmap::clone(g.s.map_pool, f.bindings);
                    if ai == sw_wild {
                        if sw_wild_bind != 0 {
                            refine(g, f, m.binding(sw_wild_bind).ty, in_val.ty);
                            bindPut(g, f, sw_wild_bind, in_val);
                        }
                    } else if is_nom_switch {
                        let pat = m.pattern(m.rowPatterns(m.armRows(arm)[0])[0]);
                        if pat.b != 0 && m.pattern(pat.b).tag != squid_check_core::PatternTag.wildcard {
                            let ctag = m.constructor(pat.a).tag;
                            let payload, uerr = unwrapVariant(g, f, in_val, ctag, id);
                            if uerr != squid_direct_types::Error.none { f.bindings = saved_b; return neverVal(), uerr; }
                            let tested = test_(g, f, pat.b, payload, false, 0, id);
                            if tested != squid_direct_types::Error.none { f.bindings = saved_b; return neverVal(), tested; }
                        }
                    }
                    let body, berr = stmt(g, f, arm.body);
                    f.bindings = saved_b;
                    if berr != squid_direct_types::Error.none { return body, berr; }
                    if body.ty != squid_direct_types::never {
                        falls = true;
                        if !info.statement {
                            let delivered = deliver(g, f, body, result, id);
                            if delivered != squid_direct_types::Error.none { return neverVal(), delivered; }
                        }
                    }
                    br(g, f, OP_br, done);
                }
                if sw_wild < 0 {
                    close(g, f);
                    op(g, OP_unreachable_);
                }
                close(g, f);
                if !falls { return neverVal(), squid_direct_types::Error.none; }
                if info.statement { return unitVal(), squid_direct_types::Error.none; }
                if g.s.slots[result].present { return g.s.slots[result].value, squid_direct_types::Error.none; }
                return neverVal(), squid_direct_types::Error.none;
            }
        }
    }
    for arm, arm_index in arms {
        let rows = m.armRows(arm);
        let next = open(g, f, OP_block);
        if rows.len == 1 {
            let patterns = m.rowPatterns(rows[0]);
            for pattern, at in patterns {
                let tested = test_(g, f, pattern, g.s.vals[values.start + at], true, next, id);
                if tested != squid_direct_types::Error.none { return neverVal(), tested; }
            }
        } else {
            // Alternatives bind the same names; later rows copy into the first row's locals.
            let matched = open(g, f, OP_block);
            var first = squid_support_zigmap::Map {};
            for row, row_index in rows {
                let row_fail = open(g, f, OP_block);
                let before = squid_support_zigmap::clone(g.s.map_pool, f.bindings);
                let patterns = m.rowPatterns(row);
                for pattern, at in patterns {
                    let tested = test_(g, f, pattern, g.s.vals[values.start + at], true, row_fail, id);
                    if tested != squid_direct_types::Error.none { return neverVal(), tested; }
                }
                if row_index == 0 {
                    // Zig walks its hash map here; the table keeps its order.
                    let table = f.bindings;
                    for slot in 0..(table.capacity as i64) {
                        if !squid_support_zigmap::used(g.s.map_pool, table, slot as u32) { continue; }
                        let key = squid_support_zigmap::keyAt(g.s.map_pool, table, slot as u32);
                        let entry = g.s.vals[squid_support_zigmap::valueAt(g.s.map_pool, table, slot as u32)];
                        let prior_at, has_prior = squid_support_zigmap::get(g.s.map_pool, before, key);
                        if has_prior && sameWords(g, g.s.vals[prior_at], entry) { continue; }
                        let owned, error = fresh(g, f, entry.ty, id);
                        if error != squid_direct_types::Error.none { return neverVal(), error; }
                        let copied = copy(g, f, entry, owned, id);
                        if copied != squid_direct_types::Error.none { return neverVal(), copied; }
                        g.s.vals.push(owned);
                        squid_support_zigmap::put(g.s.map_pool, first, key, (g.s.vals.len - 1) as u32);
                    }
                } else {
                    // Every name the first row binds: a later row's payload
                    // may sit in the same locals as the first row's.
                    for slot in 0..(first.capacity as i64) {
                        if !squid_support_zigmap::used(g.s.map_pool, first, slot as u32) { continue; }
                        let key = squid_support_zigmap::keyAt(g.s.map_pool, first, slot as u32);
                        let target = g.s.vals[squid_support_zigmap::valueAt(g.s.map_pool, first, slot as u32)];
                        let value, present = bindGet(g, f, key);
                        if present {
                            let copied = copy(g, f, value, target, id);
                            if copied != squid_direct_types::Error.none { return neverVal(), copied; }
                            invalidateCheckedArrayVal(g, f, target);
                        }
                    }
                }
                br(g, f, OP_br, matched);
                close(g, f);
            }
            br(g, f, OP_br, next);
            close(g, f);
            for slot in 0..(first.capacity as i64) {
                if !squid_support_zigmap::used(g.s.map_pool, first, slot as u32) { continue; }
                let key = squid_support_zigmap::keyAt(g.s.map_pool, first, slot as u32);
                bindPut(g, f, key, g.s.vals[squid_support_zigmap::valueAt(g.s.map_pool, first, slot as u32)]);
            }
        }
        if arm.guard_ != 0 {
            let guard_value, error = expr(g, f, arm.guard_);
            if error != squid_direct_types::Error.none { return guard_value, error; }
            push(g, guard_value);
            op(g, OP_i32_eqz);
            br(g, f, OP_br_if, next);
        }
        let prev_reuse_nodes = f.reuse_nodes;
        let prev_reuse_nodes_len = f.reuse_nodes_len;
        let prev_reuse_block = f.reuse_block;
        let prev_reuse_ty = f.reuse_ty;
        if fbip_block != 0 {
            var fbip_safe = true;
            var pat_binds: u32[32] = [0; 32];
            var pat_len: i64 = 0;
            var has_root_bind = false;
            var pat_overflow = false;
            for row in rows {
                for pat_id in m.rowPatterns(row) {
                    collectPatternBindings(m, pat_id, true, pat_binds, pat_len, has_root_bind, pat_overflow, 0);
                }
            }
            if has_root_bind || pat_overflow {
                fbip_safe = false;
            } else {
                for pbi in 0..pat_len {
                    let pb = pat_binds[pbi];
                    let pval, pok = bindGet(g, f, pb);
                    if !pok { continue; }
                    let is_cb, cberr = copiedBox(g, f, pval.ty, id);
                    if cberr != squid_direct_types::Error.none || is_cb {
                        if bindingCaptured(g, f, pb) ||
                            (arm.guard_ != 0 && nodeReadsBinding(m, arm.guard_, pb, 0)) ||
                            hasPreTailBindingUse(m, arm.body, info.statement, pb, 0) {
                            fbip_safe = false;
                            break;
                        }
                    }
                }
            }
            var targets: u32[4] = [0; 4];
            var target_len: i64 = 0;
            if fbip_safe && collectTailConstructs(m, arm.body, info.statement, targets, target_len) && target_len > 0 {
                f.reuse_nodes = targets;
                f.reuse_nodes_len = target_len;
                f.reuse_block = fbip_block;
                f.reuse_ty = fbip_ty;
            }
        }
        let body, error = stmt(g, f, arm.body);
        f.reuse_nodes = prev_reuse_nodes;
        f.reuse_nodes_len = prev_reuse_nodes_len;
        f.reuse_block = prev_reuse_block;
        f.reuse_ty = prev_reuse_ty;
        if error != squid_direct_types::Error.none { return body, error; }
        if body.ty != squid_direct_types::never {
            falls = true;
            if !info.statement {
                let delivered = deliver(g, f, body, result, id);
                if delivered != squid_direct_types::Error.none { return neverVal(), delivered; }
            }
            // A two-arm statement match carries rebindings like an if.
            if merges.len != 0 && arm_index < 2 {
                for merge, at in merges {
                    var binding = merge.else_binding;
                    if arm_index == 0 { binding = merge.then_binding; }
                    let value, present = bindGet(g, f, binding);
                    if present {
                        let delivered = deliver(g, f, value, merged + (at as u32), id);
                        if delivered != squid_direct_types::Error.none { return neverVal(), delivered; }
                    }
                }
            }
        }
        br(g, f, OP_br, done);
        close(g, f);
    }
    op(g, OP_unreachable_);
    close(g, f);
    for merge, at in merges {
        let slot = g.s.slots[merged + at];
        if slot.present {
            bindPut(g, f, merge.result, slot.value);
            if tagOf(g, slot.value.ty) == squid_direct_types::Tag.array {
                let tv, tok = bindGet(g, f, merge.then_binding);
                let ev, eok = bindGet(g, f, merge.else_binding);
                if tok && eok && knownMutable(g, f, tv) && knownMutable(g, f, ev) {
                    recordMutable(g, f, slot.value);
                }
                if tok && eok && tagOf(g, tv.ty) == squid_direct_types::Tag.array && tagOf(g, ev.ty) == squid_direct_types::Tag.array {
                    let s0 = w(g, slot.value, 0);
                    let s1 = w(g, slot.value, 1);
                    let wr_t = findWorkerR(f, w(g, tv, 0), w(g, tv, 1));
                    let wr_e = findWorkerR(f, w(g, ev, 0), w(g, ev, 1));
                    if wr_t >= 0 && wr_e >= 0 && f.worker_r[wr_t].base == f.worker_r[wr_e].base && f.worker_r[wr_t].length == f.worker_r[wr_e].length {
                        recordWorkerR(f, s0, s1, f.worker_r[wr_t].base, f.worker_r[wr_t].length);
                    }
                    let wm_t = findWorkerM(f, w(g, tv, 0), w(g, tv, 1));
                    let wm_e = findWorkerM(f, w(g, ev, 0), w(g, ev, 1));
                    if wm_t >= 0 && wm_e >= 0 && f.worker_m[wm_t].entry == f.worker_m[wm_e].entry {
                        recordWorkerM(f, s0, s1, f.worker_m[wm_t].entry);
                    }
                }
                let tb = merge.then_binding;
                let eb = merge.else_binding;
                if tb != 0 && eb != 0 &&
                    isUniqueOwned(g, f, tb) && ownedRefUses(g, f, tb) == 0 && ownedFlowUses(g, f, tb) == 1 && !bindingCaptured(g, f, tb) &&
                    isUniqueOwned(g, f, eb) && ownedRefUses(g, f, eb) == 0 && ownedFlowUses(g, f, eb) == 1 && !bindingCaptured(g, f, eb) {
                    squid_support_zigmap::put(g.s.map_pool, f.unique_owned, merge.result, f.loop_depth + 1);
                }
            }
            let ct1, ok1 = withCellType(g, f, merge.then_binding);
            if ok1 { squid_support_zigmap::put(g.s.map_pool, f.with_cells, merge.result, ct1); }
            else {
                let ct2, ok2 = withCellType(g, f, merge.else_binding);
                if ok2 { squid_support_zigmap::put(g.s.map_pool, f.with_cells, merge.result, ct2); }
            }
        }
    }
    if !falls { return neverVal(), squid_direct_types::Error.none; }
    if info.statement { return unitVal(), squid_direct_types::Error.none; }
    if g.s.slots[result].present { return g.s.slots[result].value, squid_direct_types::Error.none; }
    return neverVal(), squid_direct_types::Error.none;
}

// Tests `pattern` against `value`, branching to `fail` (a Wasm depth) on
// mismatch, and binds its names. Without `has_fail` a mismatch traps.
recursive fn test_(g: Generator&, f: Fn&, pattern_id: u32, value: Val, has_fail: bool, fail: u32, id: u32) -> Error {
    let m .= g.units[f.unit - 1];
    let pattern = m.pattern(pattern_id);
    if value.ty == squid_direct_types::never { return squid_direct_types::Error.none; }
    match pattern.tag {
        wildcard => {},
        bind => {
            refine(g, f, m.binding(pattern.a).ty, value.ty);
            bindPut(g, f, pattern.a, value);
        },
        constant, value => {
            let tag = g.types.node(value.ty).tag;
            // Unit has one value: its pattern always matches.
            if tag == squid_direct_types::Tag.unit {
                if pattern.tag == squid_check_core::PatternTag.value {
                    let ignored, error = expr(g, f, pattern.a);
                    if error != squid_direct_types::Error.none { return error; }
                }
                return squid_direct_types::Error.none;
            }
            push(g, value);
            if pattern.tag == squid_check_core::PatternTag.constant {
                pushConstant(g, value.ty, pattern.a, pattern.b);
            } else {
                let expected, error = expr(g, f, pattern.a);
                if error != squid_direct_types::Error.none { return error; }
                push(g, expected);
            }
            match tag {
                f32_ => { op(g, OP_f32_ne); },
                f64_ => { op(g, OP_f64_ne); },
                u64_, i64_ => { op(g, OP_i64_ne); },
                _ => { op(g, OP_i32_ne); },
            }
            failIf(g, f, has_fail, fail);
        },
        product => {
            let children = m.patternChildren(pattern_id);
            let shape = g.types.node(value.ty);
            match shape.tag {
                tuple => {
                    for child, index in children {
                        let item, error = tupleItem(g, f, value, index, id);
                        if error != squid_direct_types::Error.none { return error; }
                        let tested = test_(g, f, child, item, has_fail, fail, id);
                        if tested != squid_direct_types::Error.none { return tested; }
                    }
                },
                unit => {},
                // Children follow the pattern's Core record type order.
                record => { return recordPattern(g, f, pattern_id, false, m.types.node(pattern.ty), value, has_fail, fail, id); },
                _ => {
                    g.failOpen(m, id);
                    g.put("product pattern on a ");
                    g.put(squid_direct_types::tagName(shape.tag));
                    return g.failClose();
                },
            }
        },
        constructor => {
            let constructor = m.constructor(pattern.a);
            let cases, error = g.types.variants(value.ty);
            if error != squid_direct_types::Error.none { return g.typeFailure(m, id); }
            if cases.len > 1 {
                let is_niche, null_tag, some_tag, _, nerr = g.types.nullableNiche(value.ty);
                if nerr != squid_direct_types::Error.none { return g.typeFailure(m, id); }
                if is_niche {
                    lget(g, w(g, value, 0));
                    if constructor.tag == some_tag {
                        op(g, OP_i32_eqz);
                    }
                    failIf(g, f, has_fail, fail);
                } else {
                    lget(g, w(g, value, 0));
                    // A boxed value's tag is the first word of its block.
                    let boxed, error = isBoxed(g, f, value.ty, id);
                    if error != squid_direct_types::Error.none { return error; }
                    if boxed {
                        let tlerr = emitTagLoad(g, value.ty, 0);
                        if tlerr != squid_direct_types::Error.none { return g.typeFailure(m, id); }
                    }
                    i32Const(g, constructor.tag);
                    op(g, OP_i32_ne);
                    failIf(g, f, has_fail, fail);
                }
            }
            if pattern.b != 0 {
                let payload, error = unwrapVariant(g, f, value, constructor.tag, id);
                if error != squid_direct_types::Error.none { return error; }
                return test_(g, f, pattern.b, payload, has_fail, fail, id);
            }
        },
        record_payload => {
            if g.types.node(value.ty).tag != squid_direct_types::Tag.record { return g.fail(m, id, "record pattern on a non-record"); }
            // One pattern for a wider record binds the whole payload as a
            // tuple in declared field order.
            let storage = m.types.node(pattern.ty);
            if m.pattern(pattern.b).tag != squid_check_core::PatternTag.product && storage.tag == squid_check_types::Tag.record && storage.b > 1 {
                let declared, error = declaredTuple(g, f, storage, value, id);
                if error != squid_direct_types::Error.none { return error; }
                return test_(g, f, pattern.b, declared, has_fail, fail, id);
            }
            // A one-field record's child is always that field's own pattern
            // (even when that pattern is a tuple product pattern).
            if storage.tag == squid_check_types::Tag.record && storage.b == 1 {
                return recordPattern(g, f, pattern.b, true, storage, value, has_fail, fail, id);
            }
            if m.pattern(pattern.b).tag == squid_check_core::PatternTag.product { return recordPattern(g, f, pattern.b, false, storage, value, has_fail, fail, id); }
            return recordPattern(g, f, pattern.b, true, storage, value, has_fail, fail, id);
        },
        invalid => { return g.fail(m, id, "invalid pattern"); },
    }
    return squid_direct_types::Error.none;
}
// The fields of record `value` as a tuple in the declared order of the Core
// record type `storage`.
fn declaredTuple(g: Generator&, f: Fn&, storage: squid_check_types::Node, value: Val, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    var items: Ty[>..<] = [];
    var collected: u32[>..<] = [];
    for index in 0..(storage.b as i64) {
        let field = m.types.recordField(storage, index);
        let fname, has_fname = g.types.fieldNameOf(m, field.name, true);
        if !has_fname { return neverVal(), g.fail(m, id, "record pattern field without a spelling"); }
        let position = g.types.findField(value.ty, fname);
        if position < 0 { return neverVal(), g.fail(m, id, "record pattern field missing"); }
        let part, error = recordField(g, f, value, position, id);
        if error != squid_direct_types::Error.none { return neverVal(), error; }
        items.push(part.ty);
        for at in 0..(part.len as i64) { collected.push(g.s.words[part.start + at]); }
    }
    let ty, error = g.types.tuple(items[..]);
    if error != squid_direct_types::Error.none { return neverVal(), error; }
    let words = g.saveWords(collected[..]);
    return Val { ty, words.start, words.len }, squid_direct_types::Error.none;
}
// Child `i` matches field `i` of the Core record type `storage`. The children
// are those of product pattern `pattern_id`, or that pattern alone (`single`).
recursive fn recordPattern(g: Generator&, f: Fn&, pattern_id: u32, single: bool, storage: squid_check_types::Node, value: Val, has_fail: bool, fail: u32, id: u32) -> Error {
    let m .= g.units[f.unit - 1];
    var count: i64 = 1;
    if !single { count = m.patternChildren(pattern_id).len; }
    if storage.tag != squid_check_types::Tag.record || storage.b < count { return g.fail(m, id, "record pattern without a record type"); }
    for index in 0..count {
        var child = pattern_id;
        if !single { child = m.patternChildren(pattern_id)[index]; }
        let field = m.types.recordField(storage, index);
        let fname, has_fname = g.types.fieldNameOf(m, field.name, true);
        if !has_fname { return g.fail(m, id, "record pattern field without a spelling"); }
        let position = g.types.findField(value.ty, fname);
        if position < 0 { return g.fail(m, id, "record pattern field missing"); }
        let part, error = recordField(g, f, value, position, id);
        if error != squid_direct_types::Error.none { return error; }
        let tested = test_(g, f, child, part, has_fail, fail, id);
        if tested != squid_direct_types::Error.none { return tested; }
    }
    return squid_direct_types::Error.none;
}
fn failIf(g: Generator&, f: Fn&, has_fail: bool, fail: u32) {
    if has_fail { br(g, f, OP_br_if, fail); return; }
    let opened = open(g, f, OP_if_);
    op(g, OP_unreachable_);
    close(g, f);
}

fn hasWord(g: const Generator&, value: Val, wanted: u32) -> bool {
    for at in 0..(value.len as i64) { if g.s.words[value.start + at] == wanted { return true; } }
    return false;
}
// Copies `values` into `targets` through temporaries, so a value may read a
// target that an earlier assignment already overwrote.
fn assign(g: Generator&, f: Fn&, values: Vals, targets: Vals, id: u32) -> Error {
    let staged = g.reserveVals(values.len);
    for at in 0..(values.len as i64) {
        let value = g.s.vals[values.start + at];
        let target = g.s.vals[targets.start + at];
        g.s.vals[staged.start + at] = value;
        if value.ty == squid_direct_types::never || sameWords(g, value, target) { continue; }
        for other_at in 0..(targets.len as i64) {
            let other = g.s.vals[targets.start + other_at];
            // Zig's `break` leaves only the scan of this target's words.
            for word_at in 0..(other.len as i64) {
                if hasWord(g, value, g.s.words[other.start + word_at]) {
                    let made, error = fresh(g, f, target.ty, id);
                    if error != squid_direct_types::Error.none { return error; }
                    g.s.vals[staged.start + at] = made;
                    let copied = copy(g, f, value, made, id);
                    if copied != squid_direct_types::Error.none { return copied; }
                    break;
                }
            }
        }
    }
    for at in 0..(values.len as i64) {
        let staged_val = g.s.vals[staged.start + at];
        let target = g.s.vals[targets.start + at];
        if sameWords(g, staged_val, target) { continue; }
        let src_mutable = knownMutable(g, f, staged_val);
        let copied = copy(g, f, staged_val, target, id);
        if copied != squid_direct_types::Error.none { return copied; }
        invalidateCheckedArrayVal(g, f, target);
        if src_mutable { recordMutable(g, f, target); }
    }
    return squid_direct_types::Error.none;
}
// assign, but a boxed carry's new value is copied into its slot.
// `unchanged` is a local to leave 1 in when every boxed carry has the words
// its slot already held, and 0 otherwise (0xffffffff: nobody asks).
// A word that differs still counts as unchanged when it cannot be an address
// in the iteration's own memory: it is below both of the iteration's marks
// (`owner_mark`, `stack_mark`), as a count or an older address is.
fn assignCarries(g: Generator&, f: Fn&, values: Vals, targets: Vals, slots: Words, unchanged: u32, owner_mark: u32, stack_mark: u32, id: u32) -> Error {
    let plain_values = g.reserveVals(values.len);
    let plain_targets = g.reserveVals(values.len);
    var plain: u32 = 0;
    if unchanged != 0xffffffff {
        i32Const(g, 1);
        lset(g, unchanged);
    }
    for at in 0..(values.len as i64) {
        let value = g.s.vals[values.start + at];
        let target = g.s.vals[targets.start + at];
        if g.s.words[slots.start + at] == 0 {
            g.s.vals[plain_values.start + plain] = value;
            g.s.vals[plain_targets.start + plain] = target;
            plain += 1;
            continue;
        }
        if value.ty == squid_direct_types::never || w(g, value, 0) == w(g, target, 0) { continue; }
        let bytes, error = blockBytes(g, f, value.ty, id);
        if error != squid_direct_types::Error.none { return error; }
        if unchanged == 0xffffffff {
            memoryCopy(g, w(g, target, 0), 0, w(g, value, 0), bytes);
            continue;
        }
        // The same block needs no copy; another one is compared word by
        // word, then copied.
        lget(g, w(g, value, 0));
        lget(g, w(g, target, 0));
        op(g, OP_i32_ne);
        let differs = open(g, f, OP_if_);
        let cursor = local32(g, f);
        i32Const(g, 0);
        lset(g, cursor);
        let scan_bytes = bytes & ~3;
        let done = open(g, f, OP_block);
        let again = open(g, f, OP_loop);
        lget(g, cursor);
        i32Const(g, scan_bytes);
        op(g, OP_i32_ge_u);
        br(g, f, OP_br_if, done);
        lget(g, w(g, target, 0));
        lget(g, cursor);
        op(g, OP_i32_add);
        op(g, OP_i32_load);
        uleb(g, 2);
        uleb(g, 0);
        lget(g, w(g, value, 0));
        lget(g, cursor);
        op(g, OP_i32_add);
        op(g, OP_i32_load);
        uleb(g, 2);
        uleb(g, 0);
        op(g, OP_i32_ne);
        let found = open(g, f, OP_if_);
        for mark in [owner_mark, stack_mark] {
            lget(g, w(g, value, 0));
            lget(g, cursor);
            op(g, OP_i32_add);
            op(g, OP_i32_load);
            uleb(g, 2);
            uleb(g, 0);
            lget(g, mark);
            op(g, OP_i32_ge_u);
            let inside = open(g, f, OP_if_);
            i32Const(g, 0);
            lset(g, unchanged);
            br(g, f, OP_br, done);
            close(g, f);
        }
        close(g, f);
        lget(g, cursor);
        i32Const(g, 4);
        op(g, OP_i32_add);
        lset(g, cursor);
        br(g, f, OP_br, again);
        close(g, f);
        close(g, f);
        memoryCopy(g, w(g, target, 0), 0, w(g, value, 0), bytes);
        close(g, f);
    }
    return assign(g, f, Vals { plain_values.start, plain }, Vals { plain_targets.start, plain }, id);
}
// Speculatively validates a View handle and computes its shifted base address
// without trapping; returns 0 in `vbase` when the view is stale, out-of-bounds,
// or (if `require_immutable`) backed by mutable growable storage.
fn tryHoistViewBase(g: Generator&, f: Fn&, vslot: u32, vgen: u32, vstart: u32, vlen: u32, step: u32, require_immutable: bool) -> u32 {
    let rt = g.runtime_();
    let vbase = constLocal(g, f, 0);
    lget(g, vslot);
    i32Const(g, 0);
    op(g, OP_i32_ne);
    lget(g, vslot);
    i32Const(g, rt.layout.owner_capacity);
    op(g, OP_i32_lt_u);
    op(g, OP_i32_and);
    let slot_ok = open(g, f, OP_if_);
    let block_ptr = local32(g, f);
    lget(g, vslot);
    i32Const(g, 8);
    op(g, OP_i32_shr_u);
    i32Const(g, 2);
    op(g, OP_i32_shl);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, rt.layout.owner_table);
    ltee(g, block_ptr);
    let block_ok = open(g, f, OP_if_);
    let entry = local32(g, f);
    lget(g, block_ptr);
    lget(g, vslot);
    i32Const(g, 255);
    op(g, OP_i32_and);
    i32Const(g, 4);
    op(g, OP_i32_shl);
    op(g, OP_i32_add);
    ltee(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_generation);
    lget(g, vgen);
    op(g, OP_i32_eq);
    let gen_ok = open(g, f, OP_if_);
    let end_pos = local32(g, f);
    lget(g, vstart);
    lget(g, vlen);
    op(g, OP_i32_add);
    ltee(g, end_pos);
    lget(g, vstart);
    op(g, OP_i32_ge_u);
    lget(g, end_pos);
    lget(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    op(g, OP_i32_le_u);
    op(g, OP_i32_and);
    if require_immutable {
        lget(g, entry);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_capacity);
        i32Const(g, squid_direct_runtime::static_pool_flag);
        op(g, OP_i32_and);
        i32Const(g, 0);
        op(g, OP_i32_ne);
        op(g, OP_i32_and);
    }
    let bounds_ok = open(g, f, OP_if_);
    let elem_base = local32(g, f);
    lget(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base);
    lset(g, elem_base);
    let shifted = emitOffsetAddress(g, f, elem_base, vstart, step);
    lget(g, shifted);
    lset(g, vbase);
    close(g, f);
    close(g, f);
    close(g, f);
    close(g, f);
    return vbase;
}

// A prelude member can be replaced. Recognize its actual one-argument body
// instead of assuming a member spelled "length" has the standard semantics.
fn lengthReceiver(m: const Module&, id: u32) -> u32 {
    let n = m.node(id);
    if n.tag == squid_check_core::Tag.array_op {
        if m.arrayOperation(id) != squid_backend_collection_ops::Op.length { return 0; }
    } else if n.tag != squid_check_core::Tag.storage || n.c != squid_check_storage_ops::opCode(squid_check_storage_ops::Op.length) {
        return 0;
    }
    let args = m.children(id);
    if args.len != 1 { return 0; }
    return localRef(m, args[0]);
}

fn coreSizedLength(m: const Module&, ty: TId) -> TId {
    if ty == 0 || ty >= m.types.nodes.len { return 0; }
    var cursor = ty;
    for step in 0..8 {
        let n = m.types.node(cursor);
        if n.tag == squid_check_types::Tag.usage { cursor = n.a; continue; }
        let inner = squid_check_storage_types::sharedInner(m.types, cursor);
        if inner.present { cursor = inner.value; continue; }
        break;
    }
    let info = squid_check_storage_types::info(m.types, cursor);
    if !info.present || info.value.kind != squid_check_storage_types::sized_array { return 0; }
    let len = squid_check_storage_types::lengthOf(m.types, cursor);
    if !len.present { return 0; }
    return len.value;
}
fn sameSizedLength(m: const Module&, a: TId, b: TId) -> bool {
    if a == 0 || b == 0 { return false; }
    if a == b { return true; }
    let na = m.types.node(a);
    let nb = m.types.node(b);
    if na.tag == squid_check_types::Tag.nominal && nb.tag == squid_check_types::Tag.nominal &&
        squid_check_storage_types::isLengthLiteral(na.a, na.b) &&
        squid_check_storage_types::isLengthLiteral(nb.a, nb.b) {
        return na.b == nb.b;
    }
    return false;
}
fn rangeSizedLength(g: Generator&, f: Fn&, info: squid_check_core::LoopInfo) -> TId {
    let m .= g.units[f.unit - 1];
    if info.first == 0 || info.end == 0 { return 0; }
    let first_node = m.node(info.first);
    if first_node.tag != squid_check_core::Tag.constant || first_node.a != 0 { return 0; }
    let n = m.node(info.end);
    var receiver: u32 = 0;
    if n.tag == squid_check_core::Tag.project {
        receiver = n.a;
        let owner = localRef(m, receiver);
        if owner == 0 { return 0; }
        let handle, found = bindGet(g, f, owner);
        if !found || tagOf(g, handle.ty) != squid_direct_types::Tag.array { return 0; }
        let identity, present = g.receiverIdentity(handle.ty);
        if !present { return 0; }
        let target, exists = g.dispatchTarget(m, identity, m.projection(n.b).field, squid_check_types::Operator.none);
        if !exists || !g.hasUnit(target.unit) { return 0; }
        let unit .= g.units[target.unit - 1];
        let body .= unit.body(target.binding);
        if !body || !body.is_function { return 0; }
        let params = unit.bodyParameters(body);
        if params.len != 1 || lengthReceiver(unit, scratchReturned(unit, body.root)) != params[0].binding { return 0; }
        g.recordInlined(target.unit, target.binding);
    } else {
        if lengthReceiver(m, info.end) == 0 { return 0; }
        let args = m.children(info.end);
        if args.len != 1 { return 0; }
        receiver = args[0];
    }
    return coreSizedLength(m, m.typeOf(receiver));
}

// Conservative check that a loop body cannot grow, shrink, or move a live
// View's backing owner (allows reads, writes, branches, exits, and proved
// scalar calls; rejects storage growth/shrink and opaque calls).
recursive fn noStorageResize(g: const Generator&, m: const Module&, id: u32, left: i64&) -> bool {
    if id == 0 { return true; }
    if left <= 0 { return false; }
    left -= 1;
    let n = m.node(id);
    match n.tag {
        suite, block_, product, record, array => {
            for child in m.children(id) {
                if !noStorageResize(g, m, child, left) { return false; }
            }
            return true;
        },
        construct => { return noStorageResize(g, m, n.b, left); },
        bind => { return noStorageResize(g, m, n.b, left); },
        return_ => { return noStorageResize(g, m, n.a, left); },
        break_ => {
            for child in m.children(id) {
                if !noStorageResize(g, m, child, left) { return false; }
            }
            return true;
        },
        if_value, if_stmt => {
            return noStorageResize(g, m, n.a, left) &&
                noStorageResize(g, m, n.b, left) &&
                noStorageResize(g, m, n.c, left);
        },
        match_ => {
            for inp in m.matchInputs(id) {
                if !noStorageResize(g, m, inp, left) { return false; }
            }
            for arm in m.matchArms(id) {
                if !noStorageResize(g, m, arm.guard_, left) || !noStorageResize(g, m, arm.body, left) { return false; }
            }
            return true;
        },
        loop_ => {
            let linfo = m.loopInfo(id);
            return noStorageResize(g, m, linfo.first, left) &&
                noStorageResize(g, m, linfo.end, left) &&
                noStorageResize(g, m, linfo.body, left);
        },
        pattern_bind => {
            return noStorageResize(g, m, n.b, left) && noStorageResize(g, m, n.c, left);
        },
        update => {
            let change = m.updateInfo(id);
            if !noStorageResize(g, m, change.root, left) || !noStorageResize(g, m, change.value, left) { return false; }
            for sel in m.updateSelectors(id) {
                if sel.kind == squid_check_core::UpdateKind.index && !noStorageResize(g, m, sel.index, left) { return false; }
            }
            return true;
        },
        constant, reference, panic => { return true; },
        project => {
            if isPureScalarProject(g, m, id) { return noStorageResize(g, m, n.a, left); }
            let proj = m.projection(n.b);
            let variants = m.projectionVariants(n.b);
            if variants.len != 0 { return noStorageResize(g, m, n.a, left); }
            let receiver_ty = m.types.node(m.typeOf(n.a)).tag;
            if receiver_ty == squid_check_types::Tag.record || receiver_ty == squid_check_types::Tag.product {
                return noStorageResize(g, m, n.a, left);
            }
            // Allow standard `.length` / `.view` projection checks conservatively by
            // inspecting `n.a` only when it's a known pure length call.
            let receiver_local = localRef(m, n.a);
            if receiver_local != 0 {
                let spelling = m.fieldSpelling(proj.field);
                if spelling.present && spelling.value == "length" { return true; }
            }
            return false;
        },
        scalar, associated, logical => {
            if n.tag == squid_check_core::Tag.associated && n.op == squid_check_core::Op.none { return false; }
            return noStorageResize(g, m, n.a, left) && noStorageResize(g, m, n.b, left);
        },
        call => {
            let call = m.call(id);
            for arg in call.arguments {
                if !noStorageResize(g, m, arg, left) { return false; }
            }
            if scratchScalarCallee(g, m, call) { return true; }
            let target = g.resolve(m, call.target);
            if !g.hasUnit(target.unit) { return false; }
            let tm .= g.units[target.unit - 1];
            let body .= tm.body(target.binding);
            if !body || !body.is_function || body.exported { return false; }
            if tm.bodyParameters(body).len != call.arguments.len { return false; }
            return noStorageResize(g, tm, body.root, left);
        },
        apply => {
            // Allow `arr.at idx` (method call forwarding to array get/storage read).
            if m.node(n.a).tag == squid_check_core::Tag.project {
                let sp = m.fieldSpelling(m.projection(m.node(n.a).b).field);
                if sp.present && sp.value == "at" {
                    return noStorageResize(g, m, m.node(n.a).a, left) && noStorageResize(g, m, n.b, left);
                }
            }
            return false;
        },
        array_op => {
            match m.arrayOperation(id) {
                length, get, simd_load, simd_store, simd_load_u8x16, simd_store_u8x16, simd_load_f64x2, simd_store_f64x2 => {
                    for child in m.children(id) {
                        if !noStorageResize(g, m, child, left) { return false; }
                    }
                    return true;
                },
                _ => { return false; },
            }
        },
        storage => {
            let op_kind, ok = squid_check_storage_ops::opFromCode(n.c);
            if ok != squid_error::Error.none { return false; }
            match op_kind {
                length, read, view => {
                    for child in m.children(id) {
                        if !noStorageResize(g, m, child, left) { return false; }
                    }
                    return true;
                },
                _ => { return false; },
            }
        },
        spark => {
            let sinfo = m.sparkInfo(id);
            return noStorageResize(g, m, sinfo.source, left) &&
                noStorageResize(g, m, sinfo.end, left) &&
                noStorageResize(g, m, sinfo.body, left);
        },
        _ => { return false; },
    }
}
fn inResizedSet(set: const u32[16]&, len: i64, b: u32) -> bool {
    for i in 0..len { if set[i] == b { return true; } }
    return false;
}
fn addResizedSet(set: u32[16]&, len: i64&, b: u32) -> bool {
    if b == 0 { return false; }
    if inResizedSet(set, len, b) { return true; }
    if len >= 16 { return false; }
    set[len] = b;
    len += 1;
    return true;
}
fn addResizedSetTracked(set: u32[16]&, len: i64&, b: u32, changed: bool&) -> bool {
    if b == 0 { return true; }
    if inResizedSet(set, len, b) { return true; }
    if len >= 16 { return false; }
    set[len] = b;
    len += 1;
    changed = true;
    return true;
}
recursive fn patternContainsResized(m: const Module&, pid: u32, resized: const u32[16]&, resized_len: i64) -> bool {
    if pid == 0 { return false; }
    let pat = m.pattern(pid);
    match pat.tag {
        bind => { return inResizedSet(resized, resized_len, pat.a); },
        constructor => { return patternContainsResized(m, pat.b, resized, resized_len); },
        product => {
            for ch in m.patternChildren(pid) {
                if patternContainsResized(m, ch, resized, resized_len) { return true; }
            }
            return false;
        },
        _ => { return false; },
    }
}
// Propagates resized-array status across all SSA handle-preserving aliases
// (bind of reference/update, nested loop carries, and if/match branch merges).
// Returns false conservatively if a resized binding originates from an untracked
// expression shape or overflows the 16-entry set.
fn resizedRhsOrigin(g: const Generator&, m: const Module&, id: u32) -> u32, bool {
    var cur = id;
    for step in 0..8 {
        if cur == 0 { return 0, false; }
        let n = m.node(cur);
        match n.tag {
            reference => {
                let rb = localRef(m, cur);
                return rb, rb != 0;
            },
            update => {
                let rb = localRef(m, m.updateInfo(cur).root);
                return rb, rb != 0;
            },
            array => { return 0, true; },
            storage => {
                let op_kind, ok = squid_check_storage_ops::opFromCode(n.c);
                if ok != squid_error::Error.none { return 0, false; }
                if op_kind == squid_check_storage_ops::Op.with_capacity || op_kind == squid_check_storage_ops::Op.copy { return 0, true; }
                let ch = m.children(cur);
                if ch.len > 0 && (op_kind == squid_check_storage_ops::Op.push || op_kind == squid_check_storage_ops::Op.reserve || op_kind == squid_check_storage_ops::Op.extend) {
                    let rb = localRef(m, ch[0]);
                    return rb, rb != 0;
                }
                return 0, false;
            },
            apply => {
                if m.node(n.a).tag == squid_check_core::Tag.project {
                    let proj_n = m.node(n.a);
                    let sp = m.fieldSpelling(m.projection(proj_n.b).field);
                    if sp.present && (sp.value == "push" || sp.value == "reserve" || sp.value == "extend") {
                        let rb = localRef(m, proj_n.a);
                        return rb, rb != 0;
                    }
                }
                return 0, false;
            },
            call => {
                let info = m.call(cur);
                let target = g.resolve(m, info.target);
                if g.hasUnit(target.unit) {
                    let tm .= g.units[target.unit - 1];
                    let tbody .= tm.body(target.binding);
                    if tbody && tbody.is_function && !tbody.exported {
                        let params = tm.bodyParameters(tbody);
                        if params.len == info.arguments.len {
                            let own_mask = tm.binding(tbody.binding).capability_parameters.own;
                            var matched: u32 = 0;
                            var count: i64 = 0;
                            for arg, ai in info.arguments {
                                if ai < 64 && ((own_mask >> (ai as u64)) & 1) != 0 {
                                    let ab = localRef(m, arg);
                                    if ab != 0 && calleeReturnsParamHandle(g, tm, tbody.root, params[ai].binding, 0) {
                                        matched = ab;
                                        count += 1;
                                    }
                                }
                            }
                            if count == 1 { return matched, true; }
                        }
                    }
                }
                return 0, false;
            },
            return_ => { cur = n.a; },
            block_, suite => {
                let ch = m.children(cur);
                if ch.len == 0 { return 0, false; }
                for ci in 0..(ch.len - 1) {
                    if m.node(ch[ci]).tag != squid_check_core::Tag.bind { return 0, false; }
                }
                cur = ch[ch.len - 1];
            },
            _ => { return 0, false; },
        }
    }
    return 0, false;
}
recursive fn propagateResizedAliases(g: const Generator&, m: const Module&, id: u32, resized: u32[16]&, resized_len: i64&, changed: bool&, left: i64&) -> bool {
    if id == 0 { return true; }
    if left <= 0 { return false; }
    left -= 1;
    let n = m.node(id);
    match n.tag {
        suite, block_ => {
            for child in m.children(id) {
                if !propagateResizedAliases(g, m, child, resized, resized_len, changed, left) { return false; }
            }
            return true;
        },
        bind => {
            if inResizedSet(resized, resized_len, n.a) {
                let rb, ok = resizedRhsOrigin(g, m, n.b);
                if !ok { return false; }
                if rb != 0 && !addResizedSetTracked(resized, resized_len, rb, changed) { return false; }
            }
            return propagateResizedAliases(g, m, n.b, resized, resized_len, changed, left);
        },
        pattern_bind => {
            if patternContainsResized(m, n.a, resized, resized_len) { return false; }
            return propagateResizedAliases(g, m, n.b, resized, resized_len, changed, left) &&
                propagateResizedAliases(g, m, n.c, resized, resized_len, changed, left);
        },
        if_value, if_stmt => {
            for mg in m.branchMerges(id) {
                if inResizedSet(resized, resized_len, mg.result) ||
                    inResizedSet(resized, resized_len, mg.then_binding) ||
                    inResizedSet(resized, resized_len, mg.else_binding) {
                    if !addResizedSetTracked(resized, resized_len, mg.result, changed) ||
                        !addResizedSetTracked(resized, resized_len, mg.then_binding, changed) ||
                        !addResizedSetTracked(resized, resized_len, mg.else_binding, changed) {
                        return false;
                    }
                }
            }
            return propagateResizedAliases(g, m, n.a, resized, resized_len, changed, left) &&
                propagateResizedAliases(g, m, n.b, resized, resized_len, changed, left) &&
                propagateResizedAliases(g, m, n.c, resized, resized_len, changed, left);
        },
        match_ => {
            for mg in m.branchMerges(id) {
                if inResizedSet(resized, resized_len, mg.result) ||
                    inResizedSet(resized, resized_len, mg.then_binding) ||
                    inResizedSet(resized, resized_len, mg.else_binding) {
                    if !addResizedSetTracked(resized, resized_len, mg.result, changed) ||
                        !addResizedSetTracked(resized, resized_len, mg.then_binding, changed) ||
                        !addResizedSetTracked(resized, resized_len, mg.else_binding, changed) {
                        return false;
                    }
                }
            }
            for inp in m.matchInputs(id) {
                if !propagateResizedAliases(g, m, inp, resized, resized_len, changed, left) { return false; }
            }
            for arm in m.matchArms(id) {
                for row in m.armRows(arm) {
                    for pat in m.rowPatterns(row) {
                        if patternContainsResized(m, pat, resized, resized_len) { return false; }
                    }
                }
                if !propagateResizedAliases(g, m, arm.guard_, resized, resized_len, changed, left) ||
                    !propagateResizedAliases(g, m, arm.body, resized, resized_len, changed, left) {
                    return false;
                }
            }
            return true;
        },
        loop_ => {
            for ic in m.loopCarries(id) {
                if inResizedSet(resized, resized_len, ic.incoming) ||
                    inResizedSet(resized, resized_len, ic.iteration) ||
                    inResizedSet(resized, resized_len, ic.backedge) ||
                    inResizedSet(resized, resized_len, ic.outgoing) {
                    if !addResizedSetTracked(resized, resized_len, ic.incoming, changed) ||
                        !addResizedSetTracked(resized, resized_len, ic.iteration, changed) ||
                        !addResizedSetTracked(resized, resized_len, ic.backedge, changed) ||
                        !addResizedSetTracked(resized, resized_len, ic.outgoing, changed) {
                        return false;
                    }
                }
            }
            let linfo = m.loopInfo(id);
            return propagateResizedAliases(g, m, linfo.first, resized, resized_len, changed, left) &&
                propagateResizedAliases(g, m, linfo.end, resized, resized_len, changed, left) &&
                propagateResizedAliases(g, m, linfo.body, resized, resized_len, changed, left);
        },
        _ => { return true; },
    }
}
// Selective loop-resize scan: returns `true` when `id` contains no opaque
// non-inlined resizing calls or untracked field-array resizes, collecting into
// `resized` every direct local `Tag.array` binding that may be pushed/popped/truncated.
recursive fn scanLoopResize(g: const Generator&, m: const Module&, id: u32, resized: u32[16]&, resized_len: i64&, left: i64&) -> bool {
    if id == 0 { return true; }
    if left <= 0 { return false; }
    left -= 1;
    let n = m.node(id);
    match n.tag {
        constant, reference, panic => { return true; },
        suite, block_, product, record, array, break_ => {
            for child in m.children(id) {
                if !scanLoopResize(g, m, child, resized, resized_len, left) { return false; }
            }
            return true;
        },
        bind => { return scanLoopResize(g, m, n.b, resized, resized_len, left); },
        construct => { return scanLoopResize(g, m, n.b, resized, resized_len, left); },
        return_ => { return scanLoopResize(g, m, n.a, resized, resized_len, left); },
        if_value, if_stmt => {
            return scanLoopResize(g, m, n.a, resized, resized_len, left) &&
                scanLoopResize(g, m, n.b, resized, resized_len, left) &&
                scanLoopResize(g, m, n.c, resized, resized_len, left);
        },
        match_ => {
            for inp in m.matchInputs(id) {
                if !scanLoopResize(g, m, inp, resized, resized_len, left) { return false; }
            }
            for arm in m.matchArms(id) {
                if !scanLoopResize(g, m, arm.guard_, resized, resized_len, left) ||
                    !scanLoopResize(g, m, arm.body, resized, resized_len, left) { return false; }
            }
            return true;
        },
        loop_ => {
            let linfo = m.loopInfo(id);
            return scanLoopResize(g, m, linfo.first, resized, resized_len, left) &&
                scanLoopResize(g, m, linfo.end, resized, resized_len, left) &&
                scanLoopResize(g, m, linfo.body, resized, resized_len, left);
        },
        pattern_bind => {
            return scanLoopResize(g, m, n.b, resized, resized_len, left) &&
                scanLoopResize(g, m, n.c, resized, resized_len, left);
        },
        update => {
            let change = m.updateInfo(id);
            if !scanLoopResize(g, m, change.root, resized, resized_len, left) ||
                !scanLoopResize(g, m, change.value, resized, resized_len, left) { return false; }
            for sel in m.updateSelectors(id) {
                if sel.kind == squid_check_core::UpdateKind.index && !scanLoopResize(g, m, sel.index, resized, resized_len, left) { return false; }
            }
            return true;
        },
        project => {
            if isPureScalarProject(g, m, id) { return scanLoopResize(g, m, n.a, resized, resized_len, left); }
            let proj = m.projection(n.b);
            let variants = m.projectionVariants(n.b);
            if variants.len != 0 { return scanLoopResize(g, m, n.a, resized, resized_len, left); }
            let receiver_ty = m.types.node(m.typeOf(n.a)).tag;
            if receiver_ty == squid_check_types::Tag.record || receiver_ty == squid_check_types::Tag.product {
                return scanLoopResize(g, m, n.a, resized, resized_len, left);
            }
            let receiver_local = localRef(m, n.a);
            if receiver_local != 0 {
                let spelling = m.fieldSpelling(proj.field);
                if spelling.present && spelling.value == "length" { return true; }
            }
            return false;
        },
        scalar, associated, logical => {
            if n.tag == squid_check_core::Tag.associated && n.op == squid_check_core::Op.none { return false; }
            return scanLoopResize(g, m, n.a, resized, resized_len, left) &&
                scanLoopResize(g, m, n.b, resized, resized_len, left);
        },
        array_op => {
            match m.arrayOperation(id) {
                length, get => {
                    for child in m.children(id) {
                        if !scanLoopResize(g, m, child, resized, resized_len, left) { return false; }
                    }
                    return true;
                },
                _ => { return false; },
            }
        },
        storage => {
            let op_kind, ok = squid_check_storage_ops::opFromCode(n.c);
            if ok != squid_error::Error.none { return false; }
            let ch = m.children(id);
            match op_kind {
                length, read, view => {
                    for child in ch {
                        if !scanLoopResize(g, m, child, resized, resized_len, left) { return false; }
                    }
                    return true;
                },
                push, pop, truncate, reserve, extend, push_front, pop_front, insert, remove => {
                    if ch.len == 0 { return false; }
                    let target_b = localRef(m, ch[0]);
                    let ttag = m.types.node(m.typeOf(ch[0])).tag;
                    if target_b == 0 || (ttag != squid_check_types::Tag.array && ttag != squid_check_types::Tag.packed && ttag != squid_check_types::Tag.seq) { return false; }
                    if !addResizedSet(resized, resized_len, target_b) { return false; }
                    for child in ch {
                        if !scanLoopResize(g, m, child, resized, resized_len, left) { return false; }
                    }
                    return true;
                },
                _ => { return false; },
            }
        },
        spark => {
            let sinfo = m.sparkInfo(id);
            return scanLoopResize(g, m, sinfo.source, resized, resized_len, left) &&
                scanLoopResize(g, m, sinfo.end, resized, resized_len, left) &&
                scanLoopResize(g, m, sinfo.body, resized, resized_len, left);
        },
        call => {
            let call = m.call(id);
            for arg in call.arguments {
                if !scanLoopResize(g, m, arg, resized, resized_len, left) { return false; }
            }
            if scratchScalarCallee(g, m, call) { return true; }
            let target = g.resolve(m, call.target);
            if !g.hasUnit(target.unit) { return false; }
            let tm .= g.units[target.unit - 1];
            let body .= tm.body(target.binding);
            if !body || !body.is_function || body.exported { return false; }
            let params = tm.bodyParameters(body);
            if params.len != call.arguments.len { return false; }
            var ibudget: i64 = 256;
            if !canInlineBody(g, tm, body.root, target, ibudget) { return false; }
            var cbudget: i64 = 512;
            if noStorageResize(g, tm, body.root, cbudget) { return true; }
            // Callee has no effects/closures and may only resize its `own` parameters.
            let own_mask = tm.binding(body.binding).capability_parameters.own;
            for pi in 0..params.len {
                if pi >= 64 { return false; }
                if (own_mask & ((1 as u64) << (pi as u64))) != 0 {
                    let arg_id = call.arguments[pi];
                    let arg_b = localRef(m, arg_id);
                    let atag = m.types.node(m.typeOf(arg_id)).tag;
                    if arg_b == 0 || (atag != squid_check_types::Tag.array && atag != squid_check_types::Tag.packed && atag != squid_check_types::Tag.seq) { return false; }
                    if !addResizedSet(resized, resized_len, arg_b) { return false; }
                }
            }
            return true;
        },
        apply => {
            if m.node(n.a).tag == squid_check_core::Tag.project {
                let proj_n = m.node(n.a);
                let sp = m.fieldSpelling(m.projection(proj_n.b).field);
                if sp.present {
                    if sp.value == "at" {
                        return scanLoopResize(g, m, proj_n.a, resized, resized_len, left) &&
                            scanLoopResize(g, m, n.b, resized, resized_len, left);
                    }
                    let ptag = m.types.node(m.typeOf(proj_n.a)).tag;
                    if (sp.value == "push" || sp.value == "pop" || sp.value == "truncate" || sp.value == "reserve" || sp.value == "extend" || sp.value == "push_front" || sp.value == "pop_front" || sp.value == "insert" || sp.value == "remove") &&
                        (ptag == squid_check_types::Tag.array || ptag == squid_check_types::Tag.packed || ptag == squid_check_types::Tag.seq) {
                        let target_b = localRef(m, proj_n.a);
                        if target_b == 0 { return false; }
                        if !addResizedSet(resized, resized_len, target_b) { return false; }
                        return scanLoopResize(g, m, proj_n.a, resized, resized_len, left) &&
                            scanLoopResize(g, m, n.b, resized, resized_len, left);
                    }
                }
            }
            return false;
        },
        _ => { return false; },
    }
}
recursive fn collectLoopReadArrays(m: const Module&, id: u32, out: u32[4]&, out_len: i64&, budget: i64&) {
    if id == 0 || budget <= 0 || out_len >= 4 { return; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        array_op => {
            let op = m.arrayOperation(id);
            let ch = m.children(id);
            if (op == squid_backend_collection_ops::Op.get || op == squid_backend_collection_ops::Op.length) && ch.len > 0 {
                let b = localRef(m, ch[0]);
                let ctag = m.types.node(m.typeOf(ch[0])).tag;
                if b != 0 && (ctag == squid_check_types::Tag.array || ctag == squid_check_types::Tag.seq) {
                    var seen = false;
                    for i in 0..out_len { if out[i] == b { seen = true; break; } }
                    if !seen && out_len < 4 { out[out_len] = b; out_len += 1; }
                }
            }
            for c in ch { collectLoopReadArrays(m, c, out, out_len, budget); }
        },
        storage => {
            let op_k, ok = squid_check_storage_ops::opFromCode(n.c);
            let ch = m.children(id);
            if ok == squid_error::Error.none &&
                (op_k == squid_check_storage_ops::Op.read || op_k == squid_check_storage_ops::Op.length || op_k == squid_check_storage_ops::Op.view) &&
                ch.len > 0 {
                let b = localRef(m, ch[0]);
                let ctag = m.types.node(m.typeOf(ch[0])).tag;
                if b != 0 && (ctag == squid_check_types::Tag.array || ctag == squid_check_types::Tag.seq) {
                    var seen = false;
                    for i in 0..out_len { if out[i] == b { seen = true; break; } }
                    if !seen && out_len < 4 { out[out_len] = b; out_len += 1; }
                }
            }
            for c in ch { collectLoopReadArrays(m, c, out, out_len, budget); }
        },
        suite, block_, product, record, array, break_ => {
            for c in m.children(id) { collectLoopReadArrays(m, c, out, out_len, budget); }
        },
        bind, construct => { collectLoopReadArrays(m, n.b, out, out_len, budget); },
        return_, project => { collectLoopReadArrays(m, n.a, out, out_len, budget); },
        scalar, logical, associated, apply => {
            collectLoopReadArrays(m, n.a, out, out_len, budget);
            collectLoopReadArrays(m, n.b, out, out_len, budget);
        },
        pattern_bind => {
            collectLoopReadArrays(m, n.b, out, out_len, budget);
            collectLoopReadArrays(m, n.c, out, out_len, budget);
        },
        if_stmt, if_value => {
            collectLoopReadArrays(m, n.a, out, out_len, budget);
            collectLoopReadArrays(m, n.b, out, out_len, budget);
            collectLoopReadArrays(m, n.c, out, out_len, budget);
        },
        match_ => {
            for inp in m.matchInputs(id) { collectLoopReadArrays(m, inp, out, out_len, budget); }
            for arm in m.matchArms(id) {
                collectLoopReadArrays(m, arm.guard_, out, out_len, budget);
                collectLoopReadArrays(m, arm.body, out, out_len, budget);
            }
        },
        call => {
            for arg in m.call(id).arguments { collectLoopReadArrays(m, arg, out, out_len, budget); }
        },
        update => {
            let u = m.updateInfo(id);
            collectLoopReadArrays(m, u.root, out, out_len, budget);
            collectLoopReadArrays(m, u.value, out, out_len, budget);
            for sel in m.updateSelectors(id) {
                if sel.kind == squid_check_core::UpdateKind.index { collectLoopReadArrays(m, sel.index, out, out_len, budget); }
            }
        },
        loop_ => {
            let linfo = m.loopInfo(id);
            collectLoopReadArrays(m, linfo.first, out, out_len, budget);
            collectLoopReadArrays(m, linfo.end, out, out_len, budget);
            collectLoopReadArrays(m, linfo.body, out, out_len, budget);
        },
        _ => {},
    }
}

fn bindingResizedInLoop(m: const Module&, loop_id: u32, b: u32, resized: const u32[16]&, resized_len: i64) -> bool {
    if inResizedSet(resized, resized_len, b) { return true; }
    for carry in m.loopCarries(loop_id) {
        if carry.incoming == b || carry.iteration == b || carry.backedge == b || carry.outgoing == b {
            if inResizedSet(resized, resized_len, carry.incoming) ||
                inResizedSet(resized, resized_len, carry.iteration) ||
                inResizedSet(resized, resized_len, carry.backedge) ||
                inResizedSet(resized, resized_len, carry.outgoing) {
                return true;
            }
        }
    }
    return false;
}
fn rangeOwner(g: Generator&, f: Fn&, id: u32, info: squid_check_core::LoopInfo, selective_resize: bool, resized: const u32[16]&, resized_len: i64) -> Val, bool {
    let m .= g.units[f.unit - 1];
    if info.pattern == 0 { return neverVal(), false; }
    let pattern = m.pattern(info.pattern);
    if pattern.tag != squid_check_core::PatternTag.bind { return neverVal(), false; }
    let n = m.node(info.end);
    var owner: u32 = 0;
    if n.tag == squid_check_core::Tag.project { owner = localRef(m, n.a); }
    else { owner = lengthReceiver(m, info.end); }
    if owner == 0 { return neverVal(), false; }
    let da_owner = findDirectArray(f, owner);
    if da_owner >= 0 && f.direct_arrays[da_owner].scalar_packed { return neverVal(), false; }
    let handle, found = bindGet(g, f, owner);
    if !found { return neverVal(), false; }
    let tag = tagOf(g, handle.ty);
    if tag != squid_direct_types::Tag.array && tag != squid_direct_types::Tag.view { return neverVal(), false; }
    if n.tag == squid_check_core::Tag.project {
        let identity, present = g.receiverIdentity(handle.ty);
        if !present { return neverVal(), false; }
        let target, exists = g.dispatchTarget(m, identity, m.projection(n.b).field, squid_check_types::Operator.none);
        if !exists || !g.hasUnit(target.unit) { return neverVal(), false; }
        let unit .= g.units[target.unit - 1];
        let body .= unit.body(target.binding);
        if !body || !body.is_function { return neverVal(), false; }
        let params = unit.bodyParameters(body);
        if params.len != 1 || lengthReceiver(unit, scratchReturned(unit, body.root)) != params[0].binding { return neverVal(), false; }
        g.recordInlined(target.unit, target.binding);
    }
    if tag == squid_direct_types::Tag.view {
        var budget: i64 = 256;
        if !noStorageResize(g, m, info.body, budget) { return neverVal(), false; }
        return handle, true;
    }
    var receiver_node: u32 = info.end;
    if n.tag == squid_check_core::Tag.project { receiver_node = n.a; }
    else { receiver_node = m.children(info.end)[0]; }
    if coreSizedLength(m, m.typeOf(receiver_node)) == 0 {
        if !selective_resize {
            var budget: i64 = 256;
            if !noStorageResize(g, m, info.body, budget) { return neverVal(), false; }
        } else if bindingResizedInLoop(m, id, owner, resized, resized_len) {
            return neverVal(), false;
        }
    }
    return handle, false;
}
fn inBindingSet(set: const u32[64]&, len: i64, b: u32) -> bool {
    for i in 0..len { if set[i] == b { return true; } }
    return false;
}
fn addBindingSet(set: u32[64]&, len: i64&, b: u32) {
    if b == 0 || inBindingSet(set, len, b) || len >= 64 { return; }
    set[len] = b;
    len += 1;
}
recursive fn scanCalleePreserves(
    g: const Generator&,
    m: const Module&,
    id: u32,
    same: u32[64]&,
    same_len: i64&,
    budget: i64&,
    call_depth: i64,
    saw_return: bool&,
    ret_pos: i64 = -1,
) -> bool {
    if id == 0 { return true; }
    if budget <= 0 { return false; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        suite, block_ => {
            for child in m.children(id) {
                if !scanCalleePreserves(g, m, child, same, same_len, budget, call_depth, saw_return, ret_pos) { return false; }
            }
            return true;
        },
        bind => {
            if !scanCalleePreserves(g, m, n.b, same, same_len, budget, call_depth, saw_return, ret_pos) { return false; }
            if n.c < 2 && exprPreservesHandle(g, m, n.b, same, same_len, 0, true, call_depth) {
                addBindingSet(same, same_len, n.a);
            }
            return true;
        },
        if_stmt, if_value => {
            if !scanCalleePreserves(g, m, n.a, same, same_len, budget, call_depth, saw_return, ret_pos) ||
                !scanCalleePreserves(g, m, n.b, same, same_len, budget, call_depth, saw_return, ret_pos) ||
                !scanCalleePreserves(g, m, n.c, same, same_len, budget, call_depth, saw_return, ret_pos) { return false; }
            for merge in m.branchMerges(id) {
                if inBindingSet(same, same_len, merge.then_binding) && inBindingSet(same, same_len, merge.else_binding) {
                    addBindingSet(same, same_len, merge.result);
                }
            }
            return true;
        },
        match_ => {
            for inp in m.matchInputs(id) {
                if !scanCalleePreserves(g, m, inp, same, same_len, budget, call_depth, saw_return, ret_pos) { return false; }
            }
            for arm in m.matchArms(id) {
                if !scanCalleePreserves(g, m, arm.guard_, same, same_len, budget, call_depth, saw_return, ret_pos) ||
                    !scanCalleePreserves(g, m, arm.body, same, same_len, budget, call_depth, saw_return, ret_pos) { return false; }
            }
            for merge in m.branchMerges(id) {
                if inBindingSet(same, same_len, merge.then_binding) && inBindingSet(same, same_len, merge.else_binding) {
                    addBindingSet(same, same_len, merge.result);
                }
            }
            return true;
        },
        loop_ => {
            let ninfo = m.loopInfo(id);
            if !scanCalleePreserves(g, m, ninfo.first, same, same_len, budget, call_depth, saw_return, ret_pos) ||
                !scanCalleePreserves(g, m, ninfo.end, same, same_len, budget, call_depth, saw_return, ret_pos) { return false; }
            for nc, nc_at in m.loopCarries(id) {
                if inBindingSet(same, same_len, nc.incoming) {
                    if carryStaysInPlace(g, m, id, nc_at, nc.iteration, nc.backedge, budget, call_depth) {
                        addBindingSet(same, same_len, nc.iteration);
                        addBindingSet(same, same_len, nc.outgoing);
                    }
                }
            }
            return scanCalleePreserves(g, m, ninfo.body, same, same_len, budget, call_depth, saw_return, ret_pos);
        },
        return_ => {
            if n.a != 0 {
                let rn = m.node(n.a);
                if rn.tag == squid_check_core::Tag.suite || rn.tag == squid_check_core::Tag.block_ {
                    return scanCalleePreserves(g, m, n.a, same, same_len, budget, call_depth, saw_return, ret_pos);
                }
            }
            saw_return = true;
            return exprPreservesAt(g, m, n.a, same, same_len, ret_pos, 0, true, call_depth);
        },
        pattern_bind => {
            if !scanCalleePreserves(g, m, n.b, same, same_len, budget, call_depth, saw_return, ret_pos) { return false; }
            propagatePatternTuplePreserve(g, m, n.a, n.b, same, same_len, call_depth);
            return scanCalleePreserves(g, m, n.c, same, same_len, budget, call_depth, saw_return, ret_pos);
        },
        break_, constant, reference, panic, scalar, associated, logical, array_op, storage, update, call, apply, product, record, construct, project, result_associated => {
            return true;
        },
        _ => { return false; },
    }
}
fn exprPreservesAt(
    g: const Generator&,
    m: const Module&,
    id: u32,
    same: const u32[64]&,
    same_len: i64,
    ret_pos: i64,
    depth: i64,
    allow_calls: bool,
    call_depth: i64,
) -> bool {
    if id == 0 { return false; }
    if ret_pos < 0 {
        return exprPreservesHandle(g, m, id, same, same_len, depth, allow_calls, call_depth);
    }
    let n = m.node(id);
    if n.tag == squid_check_core::Tag.product {
        let ch = m.children(id);
        return ret_pos < ch.len && exprPreservesHandle(g, m, ch[ret_pos], same, same_len, depth + 1, allow_calls, call_depth);
    }
    return false;
}
fn propagatePatternTuplePreserve(
    g: const Generator&,
    m: const Module&,
    pat_id: u32,
    rhs_id: u32,
    same: u32[64]&,
    same_len: i64&,
    call_depth: i64,
) {
    if pat_id == 0 || rhs_id == 0 || call_depth >= 2 { return; }
    let pat = m.pattern(pat_id);
    if pat.tag != squid_check_core::PatternTag.product { return; }
    let rhs_n = m.node(rhs_id);
    if rhs_n.tag != squid_check_core::Tag.call { return; }
    let info = m.call(rhs_id);
    let target = g.resolve(m, info.target);
    if !g.hasUnit(target.unit) { return; }
    let tm .= g.units[target.unit - 1];
    let body .= tm.body(target.binding);
    if !body || !body.is_function || body.exported { return; }
    let params = tm.bodyParameters(body);
    if params.len != info.arguments.len { return; }
    let pchildren = m.patternChildren(pat_id);
    for arg, ai in info.arguments {
        if exprPreservesHandle(g, m, arg, same, same_len, 0, false, call_depth) {
            for pc, pi in pchildren {
                if m.pattern(pc).tag == squid_check_core::PatternTag.bind {
                    if calleeReturnsParamAt(g, tm, body.root, params[ai].binding, pi, call_depth + 1) {
                        addBindingSet(same, same_len, m.pattern(pc).a);
                    }
                }
            }
        }
    }
}
recursive fn nodeAlwaysReturns(m: const Module&, id: u32, depth: i64) -> bool {
    if id == 0 || depth > 12 { return false; }
    let n = m.node(id);
    match n.tag {
        return_, panic => { return true; },
        suite, block_ => {
            for c in m.children(id) {
                if nodeAlwaysReturns(m, c, depth + 1) { return true; }
            }
            return false;
        },
        if_stmt, if_value => {
            return n.c != 0 && nodeAlwaysReturns(m, n.b, depth + 1) && nodeAlwaysReturns(m, n.c, depth + 1);
        },
        _ => { return false; },
    }
}
recursive fn calleeReturnsParamAt(g: const Generator&, m: const Module&, body_root: u32, param_b: u32, ret_pos: i64, call_depth: i64) -> bool {
    var same: u32[64] = [0; 64];
    var same_len: i64 = 0;
    addBindingSet(same, same_len, param_b);
    var budget: i64 = 1024;
    var saw_return = false;
    if !scanCalleePreserves(g, m, body_root, same, same_len, budget, call_depth, saw_return, ret_pos) { return false; }
    if saw_return {
        return nodeAlwaysReturns(m, body_root, 0);
    }
    return exprPreservesAt(g, m, body_root, same, same_len, ret_pos, 0, true, call_depth);
}
recursive fn calleeReturnsParamHandle(g: const Generator&, m: const Module&, body_root: u32, param_b: u32, call_depth: i64) -> bool {
    return calleeReturnsParamAt(g, m, body_root, param_b, -1, call_depth);
}
recursive fn exprPreservesHandle(
    g: const Generator&,
    m: const Module&,
    id: u32,
    same: const u32[64]&,
    same_len: i64,
    depth: i64,
    allow_calls: bool = false,
    call_depth: i64 = 0,
) -> bool {
    if id == 0 || depth >= 32 { return false; }
    let n = m.node(id);
    match n.tag {
        reference => {
            let b = localRef(m, id);
            return b != 0 && inBindingSet(same, same_len, b);
        },
        update => {
            let info = m.updateInfo(id);
            let sels = m.updateSelectors(id);
            return sels.len > 0 && sels[0].kind == squid_check_core::UpdateKind.index &&
                exprPreservesHandle(g, m, info.root, same, same_len, depth + 1, allow_calls, call_depth);
        },
        array_op => {
            let aop = m.arrayOperation(id);
            if aop != squid_backend_collection_ops::Op.simd_store && aop != squid_backend_collection_ops::Op.simd_store_u8x16 && aop != squid_backend_collection_ops::Op.simd_store_f64x2 { return false; }
            let ch = m.children(id);
            return ch.len > 0 && exprPreservesHandle(g, m, ch[0], same, same_len, depth + 1, allow_calls, call_depth);
        },
        storage => {
            let op_kind, ok = squid_check_storage_ops::opFromCode(n.c);
            if ok != squid_error::Error.none || (op_kind != squid_check_storage_ops::Op.push && op_kind != squid_check_storage_ops::Op.reserve && op_kind != squid_check_storage_ops::Op.extend && op_kind != squid_check_storage_ops::Op.push_front && op_kind != squid_check_storage_ops::Op.insert) { return false; }
            let ch = m.children(id);
            return ch.len > 0 && exprPreservesHandle(g, m, ch[0], same, same_len, depth + 1, allow_calls, call_depth);
        },
        return_ => {
            return exprPreservesHandle(g, m, n.a, same, same_len, depth + 1, allow_calls, call_depth);
        },
        block_, suite => {
            let ch = m.children(id);
            if ch.len == 0 { return false; }
            for ci in 0..(ch.len - 1) {
                if m.node(ch[ci]).tag != squid_check_core::Tag.bind { return false; }
            }
            return exprPreservesHandle(g, m, ch[ch.len - 1], same, same_len, depth + 1, allow_calls, call_depth);
        },
        call => {
            if !allow_calls || call_depth >= 2 { return false; }
            let info = m.call(id);
            let target = g.resolve(m, info.target);
            if !g.hasUnit(target.unit) { return false; }
            let tm .= g.units[target.unit - 1];
            let body .= tm.body(target.binding);
            if !body || !body.is_function || body.exported { return false; }
            let params = tm.bodyParameters(body);
            if params.len != info.arguments.len { return false; }
            for arg, ai in info.arguments {
                if exprPreservesHandle(g, m, arg, same, same_len, depth + 1, false, call_depth) {
                    if calleeReturnsParamHandle(g, tm, body.root, params[ai].binding, call_depth + 1) {
                        return true;
                    }
                }
            }
            return false;
        },
        apply => {
            if m.node(n.a).tag == squid_check_core::Tag.project {
                let proj_n = m.node(n.a);
                let sp = m.fieldSpelling(m.projection(proj_n.b).field);
                let ptag = m.types.node(m.typeOf(proj_n.a)).tag;
                if sp.present && (sp.value == "push" || sp.value == "reserve" || sp.value == "extend" || sp.value == "push_front" || sp.value == "insert") &&
                    (ptag == squid_check_types::Tag.array || ptag == squid_check_types::Tag.packed || ptag == squid_check_types::Tag.seq) {
                    return exprPreservesHandle(g, m, proj_n.a, same, same_len, depth + 1, allow_calls, call_depth);
                }
            }
            return false;
        },
        _ => { return false; },
    }
}
recursive fn carryStaysInPlace(
    g: const Generator&,
    m: const Module&,
    loop_id: u32,
    carry_at: i64,
    iter_binding: u32,
    backedge_binding: u32,
    budget: i64&,
    call_depth: i64 = 0,
) -> bool {
    var same: u32[64] = [0; 64];
    var same_len: i64 = 0;
    addBindingSet(same, same_len, iter_binding);
    if !scanCarryInPlace(g, m, loop_id, carry_at, m.loopInfo(loop_id).body, same, same_len, budget, call_depth) { return false; }
    return backedge_binding == 0 || inBindingSet(same, same_len, backedge_binding);
}
recursive fn scanCarryInPlace(
    g: const Generator&,
    m: const Module&,
    loop_id: u32,
    carry_at: i64,
    id: u32,
    same: u32[64]&,
    same_len: i64&,
    budget: i64&,
    call_depth: i64 = 0,
) -> bool {
    if id == 0 { return true; }
    if budget <= 0 { return false; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        suite, block_ => {
            for child in m.children(id) {
                if !scanCarryInPlace(g, m, loop_id, carry_at, child, same, same_len, budget, call_depth) { return false; }
            }
            return true;
        },
        bind => {
            if !scanCarryInPlace(g, m, loop_id, carry_at, n.b, same, same_len, budget, call_depth) { return false; }
            if exprPreservesHandle(g, m, n.b, same, same_len, 0, true, call_depth) { addBindingSet(same, same_len, n.a); }
            return true;
        },
        if_stmt, if_value => {
            if !scanCarryInPlace(g, m, loop_id, carry_at, n.a, same, same_len, budget, call_depth) ||
                !scanCarryInPlace(g, m, loop_id, carry_at, n.b, same, same_len, budget, call_depth) ||
                !scanCarryInPlace(g, m, loop_id, carry_at, n.c, same, same_len, budget, call_depth) { return false; }
            for merge in m.branchMerges(id) {
                if inBindingSet(same, same_len, merge.then_binding) && inBindingSet(same, same_len, merge.else_binding) {
                    addBindingSet(same, same_len, merge.result);
                }
            }
            return true;
        },
        match_ => {
            for inp in m.matchInputs(id) {
                if !scanCarryInPlace(g, m, loop_id, carry_at, inp, same, same_len, budget, call_depth) { return false; }
            }
            for arm in m.matchArms(id) {
                if !scanCarryInPlace(g, m, loop_id, carry_at, arm.guard_, same, same_len, budget, call_depth) ||
                    !scanCarryInPlace(g, m, loop_id, carry_at, arm.body, same, same_len, budget, call_depth) { return false; }
            }
            for merge in m.branchMerges(id) {
                if inBindingSet(same, same_len, merge.then_binding) && inBindingSet(same, same_len, merge.else_binding) {
                    addBindingSet(same, same_len, merge.result);
                }
            }
            return true;
        },
        loop_ => {
            let ninfo = m.loopInfo(id);
            if !scanCarryInPlace(g, m, loop_id, carry_at, ninfo.first, same, same_len, budget, call_depth) ||
                !scanCarryInPlace(g, m, loop_id, carry_at, ninfo.end, same, same_len, budget, call_depth) { return false; }
            let ncarries = m.loopCarries(id);
            for nc, nc_at in ncarries {
                if inBindingSet(same, same_len, nc.incoming) {
                    if carryStaysInPlace(g, m, id, nc_at, nc.iteration, nc.backedge, budget, call_depth) {
                        addBindingSet(same, same_len, nc.iteration);
                        addBindingSet(same, same_len, nc.outgoing);
                    }
                }
            }
            return scanCarryInPlace(g, m, loop_id, carry_at, ninfo.body, same, same_len, budget, call_depth);
        },
        break_ => {
            let vals = m.breakValues(id);
            for child in vals {
                if !scanCarryInPlace(g, m, loop_id, carry_at, child, same, same_len, budget, call_depth) { return false; }
            }
            if n.a == loop_id {
                if carry_at >= vals.len || !exprPreservesHandle(g, m, vals[carry_at], same, same_len, 0, true, call_depth) { return false; }
            }
            return true;
        },
        pattern_bind => {
            return scanCarryInPlace(g, m, loop_id, carry_at, n.b, same, same_len, budget, call_depth) &&
                scanCarryInPlace(g, m, loop_id, carry_at, n.c, same, same_len, budget, call_depth);
        },
        update => {
            let info = m.updateInfo(id);
            if !scanCarryInPlace(g, m, loop_id, carry_at, info.root, same, same_len, budget, call_depth) ||
                !scanCarryInPlace(g, m, loop_id, carry_at, info.value, same, same_len, budget, call_depth) { return false; }
            for sel in m.updateSelectors(id) {
                if sel.kind == squid_check_core::UpdateKind.index && !scanCarryInPlace(g, m, loop_id, carry_at, sel.index, same, same_len, budget, call_depth) { return false; }
            }
            return true;
        },
        call => {
            for arg in m.call(id).arguments {
                if !scanCarryInPlace(g, m, loop_id, carry_at, arg, same, same_len, budget, call_depth) { return false; }
            }
            return true;
        },
        product, record, array, array_op, storage => {
            for child in m.children(id) {
                if !scanCarryInPlace(g, m, loop_id, carry_at, child, same, same_len, budget, call_depth) { return false; }
            }
            return true;
        },
        construct => { return scanCarryInPlace(g, m, loop_id, carry_at, n.b, same, same_len, budget, call_depth); },
        return_, project, result_associated, fork_ => { return scanCarryInPlace(g, m, loop_id, carry_at, n.a, same, same_len, budget, call_depth); },
        scalar, associated, logical, apply => {
            return scanCarryInPlace(g, m, loop_id, carry_at, n.a, same, same_len, budget, call_depth) &&
                scanCarryInPlace(g, m, loop_id, carry_at, n.b, same, same_len, budget, call_depth);
        },
        constant, reference, panic, closure => { return true; },
        _ => { return false; },
    }
}
fn unwrapSingleBody(m: const Module&, id: u32) -> u32 {
    var cur = id;
    for step in 0..8 {
        if cur == 0 { return 0; }
        let n = m.node(cur);
        if (n.tag == squid_check_core::Tag.suite || n.tag == squid_check_core::Tag.block_) && n.b == 1 {
            cur = m.children(cur)[0];
        } else { break; }
    }
    return cur;
}

fn isTwoParamPushForwarder(tm: const Module&, body: const squid_check_core::Body&) -> bool {
    if !body.is_function { return false; }
    let params = tm.bodyParameters(body);
    if params.len != 2 { return false; }
    let inner = scratchReturned(tm, unwrapSingleBody(tm, body.root));
    if inner == 0 { return false; }
    let n = tm.node(inner);
    if n.tag != squid_check_core::Tag.storage { return false; }
    let op_kind, ok = squid_check_storage_ops::opFromCode(n.c);
    if ok != squid_error::Error.none || op_kind != squid_check_storage_ops::Op.push { return false; }
    let ch = tm.children(inner);
    return ch.len == 2 && localRef(tm, ch[0]) == params[0].binding && localRef(tm, ch[1]) == params[1].binding;
}

// Recognize `for item in src: dest := self.push item` (or `dest := @storage.push self item`
// or bare `@storage.push dest item` / `dest.push item`) with plain non-boxed elements,
// emitting a single ensure + `memory.copy`.
recursive fn tryBulkPushLoop(g: Generator&, f: Fn&, id: u32, info: squid_check_core::LoopInfo) -> bool, Error {
    if g.runtime_().has_fork { return false, squid_direct_types::Error.none; }
    if info.kind != squid_check_core::LoopKind.array || info.carries.len > 1 || info.pattern == 0 {
        return false, squid_direct_types::Error.none;
    }
    var dest = neverVal();
    var method_target = BindingRef { 0, 0 };
    var step: u32 = 0;
    var stag = squid_direct_types::Tag.unit;
    var carry_incoming: u32 = 0;
    var carry_outgoing: u32 = 0;
    {
        let m .= g.units[f.unit - 1];
        let pat = m.pattern(info.pattern);
        if pat.tag != squid_check_core::PatternTag.bind { return false, squid_direct_types::Error.none; }
        let item_binding = pat.a;
        var body_node = unwrapSingleBody(m, info.body);
        if body_node == 0 { return false, squid_direct_types::Error.none; }
        var carry_iter: u32 = 0;
        if info.carries.len == 1 {
            let carry = m.loopCarries(id)[0];
            let bnode = m.node(body_node);
            if bnode.tag != squid_check_core::Tag.bind || bnode.c >= 2 || bnode.a != carry.backedge {
                return false, squid_direct_types::Error.none;
            }
            carry_incoming = carry.incoming;
            carry_iter = carry.iteration;
            carry_outgoing = carry.outgoing;
            body_node = bnode.b;
        }
        let bn = m.node(body_node);
        var dest_binding: u32 = 0;
        if bn.tag == squid_check_core::Tag.storage {
            let op_kind, ok = squid_check_storage_ops::opFromCode(bn.c);
            if ok != squid_error::Error.none || op_kind != squid_check_storage_ops::Op.push {
                return false, squid_direct_types::Error.none;
            }
            let ch = m.children(body_node);
            if ch.len != 2 || localRef(m, ch[1]) != item_binding { return false, squid_direct_types::Error.none; }
            dest_binding = localRef(m, ch[0]);
        } else if bn.tag == squid_check_core::Tag.apply {
            if localRef(m, bn.b) != item_binding || m.node(bn.a).tag != squid_check_core::Tag.project {
                return false, squid_direct_types::Error.none;
            }
            let proj = m.node(bn.a);
            dest_binding = localRef(m, proj.a);
            if dest_binding == 0 { return false, squid_direct_types::Error.none; }
            var lookup_binding = dest_binding;
            if carry_iter != 0 {
                if dest_binding != carry_iter { return false, squid_direct_types::Error.none; }
                lookup_binding = carry_incoming;
            }
            let dest_check, has_dest = bindGet(g, f, lookup_binding);
            if !has_dest || tagOf(g, dest_check.ty) != squid_direct_types::Tag.array {
                return false, squid_direct_types::Error.none;
            }
            let identity, has_id = g.receiverIdentity(dest_check.ty);
            if !has_id { return false, squid_direct_types::Error.none; }
            let target, has_target = g.dispatchTarget(m, identity, m.projection(proj.b).field, squid_check_types::Operator.none);
            if !has_target || !g.hasUnit(target.unit) { return false, squid_direct_types::Error.none; }
            let tm .= g.units[target.unit - 1];
            let tbody .= tm.body(target.binding);
            if !tbody || !isTwoParamPushForwarder(tm, tbody) { return false, squid_direct_types::Error.none; }
            method_target = target;
        } else if bn.tag == squid_check_core::Tag.call {
            let cinfo = m.call(body_node);
            if cinfo.arguments.len != 2 || localRef(m, cinfo.arguments[1]) != item_binding {
                return false, squid_direct_types::Error.none;
            }
            let target = g.resolve(m, cinfo.target);
            if !g.hasUnit(target.unit) { return false, squid_direct_types::Error.none; }
            let tm .= g.units[target.unit - 1];
            let tbody .= tm.body(target.binding);
            if !tbody || !isTwoParamPushForwarder(tm, tbody) { return false, squid_direct_types::Error.none; }
            dest_binding = localRef(m, cinfo.arguments[0]);
            method_target = target;
        } else {
            return false, squid_direct_types::Error.none;
        }
        if carry_iter != 0 {
            if dest_binding != carry_iter { return false, squid_direct_types::Error.none; }
            dest_binding = carry_incoming;
        }
        if dest_binding == 0 || dest_binding == item_binding || dest_binding == localRef(m, info.first) { return false, squid_direct_types::Error.none; }
        let found_dest, has_dest = bindGet(g, f, dest_binding);
        if !has_dest { return false, squid_direct_types::Error.none; }
        dest = found_dest;
        let dtag = tagOf(g, dest.ty);
        if dtag != squid_direct_types::Tag.array {
            return false, squid_direct_types::Error.none;
        }
        let elem, elem_err = elementOf(g, f, dest.ty, id);
        if elem_err != squid_direct_types::Error.none { return false, squid_direct_types::Error.none; }
        let holds, herr = g.contentsHoldMemory(elem);
        if herr != squid_direct_types::Error.none || holds { return false, squid_direct_types::Error.none; }
        let boxed, berr = isBoxed(g, f, elem, id);
        if berr != squid_direct_types::Error.none || boxed { return false, squid_direct_types::Error.none; }
        let got_step, serr = stride(g, f, elem, id);
        if serr != squid_direct_types::Error.none || got_step == 0 || got_step > 65536 { return false, squid_direct_types::Error.none; }
        step = got_step;

        // Verify source Core type lowers to a contiguous container of the exact same element type.
        let src_ty, sty_err = g.types.lower(m, m.typeOf(info.first), f.env);
        if sty_err != squid_direct_types::Error.none { return false, squid_direct_types::Error.none; }
        stag = tagOf(g, src_ty);
        if stag != squid_direct_types::Tag.array && stag != squid_direct_types::Tag.view {
            return false, squid_direct_types::Error.none;
        }
        if g.types.node(src_ty).a != elem { return false, squid_direct_types::Error.none; }
    }

    if method_target.unit != 0 { g.recordInlined(method_target.unit, method_target.binding); }
    let source, eval_err = expr(g, f, info.first);
    if eval_err != squid_direct_types::Error.none { return false, eval_err; }
    let count, lerr = lengthOf(g, f, source, id);
    if lerr != squid_direct_types::Error.none { return false, lerr; }

    let rt = g.runtime_();
    lget(g, count);
    let non_empty = open(g, f, OP_if_);
    let entry = ensureCheckedGrow(g, f, dest);
    let cap = local32(g, f);
    lget(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_capacity);
    ltee(g, cap);
    i32Const(g, squid_direct_runtime::static_pool_flag);
    op(g, OP_i32_and);
    trap(g, f);
    let old_len = local32(g, f);
    let new_len = local32(g, f);
    lget(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    ltee(g, old_len);
    lget(g, count);
    op(g, OP_i32_add);
    ltee(g, new_len);
    lget(g, old_len);
    op(g, OP_i32_lt_u);
    let max_count = (rt.layout.heap_end - rt.layout.heap_base) / step;
    lget(g, new_len);
    i32Const(g, max_count);
    op(g, OP_i32_gt_u);
    op(g, OP_i32_or);
    trap(g, f);
    let need = emitScaledBytes(g, f, new_len, step);
    let cap_bytes = local32(g, f);
    lget(g, cap);
    i32Const(g, squid_direct_runtime::capacity_mask);
    op(g, OP_i32_and);
    lset(g, cap_bytes);
    lget(g, need);
    lget(g, cap_bytes);
    op(g, OP_i32_gt_u);
    let grow_if = open(g, f, OP_if_);
    let doubled = local32(g, f);
    lget(g, cap_bytes);
    i32Const(g, 1);
    op(g, OP_i32_shl);
    lset(g, doubled);
    lget(g, need);
    lget(g, doubled);
    lget(g, need);
    lget(g, doubled);
    op(g, OP_i32_gt_u);
    op(g, OP_select);
    callf(g, rt.heap_alloc);
    let fresh_size = local32(g, f);
    let fresh_base = local32(g, f);
    lset(g, fresh_size);
    lset(g, fresh_base);
    let old_base = local32(g, f);
    lget(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base);
    lset(g, old_base);
    let old_bytes = emitScaledBytes(g, f, old_len, step);
    lget(g, fresh_base);
    lget(g, old_base);
    lget(g, old_bytes);
    memoryCopyOp(g);
    lget(g, cap);
    i32Const(g, squid_direct_runtime::heap_flag);
    op(g, OP_i32_and);
    i32Const(g, 0);
    op(g, OP_i32_ne);
    lget(g, cap_bytes);
    i32Const(g, 0);
    op(g, OP_i32_ne);
    op(g, OP_i32_and);
    let free_if = open(g, f, OP_if_);
    lget(g, old_base);
    lget(g, cap_bytes);
    callf(g, rt.heap_free);
    close(g, f);
    lget(g, entry);
    lget(g, fresh_base);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base);
    lget(g, entry);
    lget(g, fresh_size);
    i32Const(g, squid_direct_runtime::heap_flag | squid_direct_runtime::live_flag);
    op(g, OP_i32_or);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_capacity);
    close(g, f);

    // Resolve source base address after any growth of `dest`.
    invalidateCheckedContainers(f);
    var src_base: u32 = 0;
    if stag == squid_direct_types::Tag.array {
        let base, _ = ensureCheckedArray(g, f, source);
        src_base = base;
    } else if stag == squid_direct_types::Tag.view {
        let vslot = w(g, source, 0);
        let vgen = w(g, source, 1);
        let vstart = w(g, source, 2);
        let vlen = w(g, source, 3);
        let cv = findCheckedView(f, vslot, vgen, vstart, vlen);
        if cv >= 0 {
            src_base = f.checked_views[cv].base;
        } else {
            let src_entry = local32(g, f);
            lget(g, vslot);
            lget(g, vgen);
            callf(g, rt.check);
            lset(g, src_entry);
            let vend = local32(g, f);
            lget(g, vstart);
            lget(g, vlen);
            op(g, OP_i32_add);
            ltee(g, vend);
            lget(g, vstart);
            op(g, OP_i32_lt_u);
            lget(g, vend);
            lget(g, src_entry);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
            op(g, OP_i32_gt_u);
            op(g, OP_i32_or);
            trap(g, f);
            let raw_base = local32(g, f);
            lget(g, src_entry);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base);
            lset(g, raw_base);
            src_base = emitOffsetAddress(g, f, raw_base, vstart, step);
        }
    } else {
        let src_entry = ensureCheckedGrow(g, f, source);
        src_base = local32(g, f);
        lget(g, src_entry);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base);
        lset(g, src_base);
    }

    let dst_base = local32(g, f);
    lget(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base);
    lset(g, dst_base);
    let dst_addr = emitOffsetAddress(g, f, dst_base, old_len, step);
    let copy_bytes = emitScaledBytes(g, f, count, step);
    lget(g, dst_addr);
    lget(g, src_base);
    lget(g, copy_bytes);
    memoryCopyOp(g);
    lget(g, entry);
    lget(g, new_len);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    close(g, f);
    if carry_outgoing != 0 {
        bindPut(g, f, carry_outgoing, dest);
        if isUniqueOwned(g, f, carry_incoming) {
            squid_support_zigmap::put(g.s.map_pool, f.unique_owned, carry_outgoing, f.loop_depth + 1);
        }
    }
    return true, squid_direct_types::Error.none;
}

recursive fn countBodyNodes(m: const Module&, id: u32, budget: i64&) -> bool {
    if id == 0 { return true; }
    if budget <= 0 { return false; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        suite, block_, product, record, array, array_op, storage => {
            for c in m.children(id) { if !countBodyNodes(m, c, budget) { return false; } }
            return true;
        },
        call, break_ => {
            for c in m.children(id) { if !countBodyNodes(m, c, budget) { return false; } }
            return true;
        },
        bind, construct => { return countBodyNodes(m, n.b, budget); },
        pattern_bind => { return countBodyNodes(m, n.b, budget) && countBodyNodes(m, n.c, budget); },
        return_, project, result_associated => { return countBodyNodes(m, n.a, budget); },
        scalar, logical, associated, apply => { return countBodyNodes(m, n.a, budget) && countBodyNodes(m, n.b, budget); },
        if_value, if_stmt => { return countBodyNodes(m, n.a, budget) && countBodyNodes(m, n.b, budget) && countBodyNodes(m, n.c, budget); },
        update => {
            let u = m.updateInfo(id);
            if !countBodyNodes(m, u.root, budget) || !countBodyNodes(m, u.value, budget) { return false; }
            for s in m.updateSelectors(id) { if s.kind == squid_check_core::UpdateKind.index && !countBodyNodes(m, s.index, budget) { return false; } }
            return true;
        },
        match_ => {
            for inp in m.matchInputs(id) { if !countBodyNodes(m, inp, budget) { return false; } }
            for arm in m.matchArms(id) { if !countBodyNodes(m, arm.guard_, budget) || !countBodyNodes(m, arm.body, budget) { return false; } }
            return true;
        },
        constant, reference, panic => { return true; },
        _ => { return false; },
    }
}

// Unroll `for x in const_array:` over small (1..4) compile-time scalar/enum
// constant arrays so `pool()` + `rt.check()` disappear and Cranelift can
// constant-fold match dispatch on the iteration element.
recursive fn tryUnrollConstArrayLoop(g: Generator&, f: Fn&, id: u32, info: squid_check_core::LoopInfo, iteration: Vals, outgoing: Vals, slots: Words) -> bool, Error {
    if g.runtime_().has_fork { return false, squid_direct_types::Error.none; }
    if info.kind != squid_check_core::LoopKind.array { return false, squid_direct_types::Error.none; }
    var target = BindingRef { 0, 0 };
    var elem_count: i64 = 0;
    var elem_is_const: bool[4] = [false; 4];
    var elem_nodes: u32[4] = [0; 4];
    var elem_vals: u32[4] = [0; 4];
    var elem_ty: Ty = 0;
    {
        let m .= g.units[f.unit - 1];
        if m.node(info.first).tag != squid_check_core::Tag.reference { return false, squid_direct_types::Error.none; }
        target = g.resolve(m, m.reference(info.first));
        if !g.hasUnit(target.unit) { return false, squid_direct_types::Error.none; }
        let tm .= g.units[target.unit - 1];
        let cbody .= tm.body(target.binding);
        if !cbody || cbody.is_function || tm.node(cbody.root).tag != squid_check_core::Tag.array {
            return false, squid_direct_types::Error.none;
        }
        let elems = tm.children(cbody.root);
        if elems.len == 0 || elems.len > 4 { return false, squid_direct_types::Error.none; }
        for el, ei in elems {
            let en = tm.node(el);
            if en.tag == squid_check_core::Tag.constant {
                elem_is_const[ei] = true;
                elem_nodes[ei] = el;
                elem_vals[ei] = en.a;
            } else if en.tag == squid_check_core::Tag.construct && en.b == 0 {
                elem_is_const[ei] = false;
                elem_nodes[ei] = el;
                elem_vals[ei] = tm.constructor(en.a).tag;
            } else {
                return false, squid_direct_types::Error.none;
            }
        }
        elem_count = elems.len;
        let arr_ty, ty_err = g.types.lower(m, m.typeOf(info.first), f.env);
        if ty_err != squid_direct_types::Error.none || tagOf(g, arr_ty) != squid_direct_types::Tag.array {
            return false, squid_direct_types::Error.none;
        }
        elem_ty = g.types.node(arr_ty).a;
        let boxed, berr = isBoxed(g, f, elem_ty, id);
        if berr != squid_direct_types::Error.none || boxed { return false, squid_direct_types::Error.none; }
        let width, werr = layoutLen(g, f, elem_ty, id);
        if werr != squid_direct_types::Error.none || width != 1 { return false, squid_direct_types::Error.none; }
        let carries = m.loopCarries(id);
        for at in 0..carries.len {
            if g.s.words[slots.start + at] != 0 { return false, squid_direct_types::Error.none; }
        }
        var budget: i64 = 64;
        if !countBodyNodes(m, info.body, budget) { return false, squid_direct_types::Error.none; }
    }

    g.recordInlined(target.unit, target.binding);
    let exit = open(g, f, OP_block);
    let unused = g.newSlot();
    for ei in 0..elem_count {
        let iter_done = open(g, f, OP_block);
        var item = neverVal();
        if elem_is_const[ei] {
            let loc = local(g, f, localKindForScalar(g, elem_ty));
            if tagOf(g, elem_ty) == squid_direct_types::Tag.f32_ {
                squid_direct_relocations::operand(target.unit, elem_nodes[ei], g.s.code.len);
                f32Const(g, elem_vals[ei]);
            } else {
                squid_direct_relocations::operand(target.unit, elem_nodes[ei], g.s.code.len);
                i32Const(g, elem_vals[ei]);
            }
            lset(g, loc);
            item = valOf1(g, elem_ty, loc);
        } else {
            let loc = constLocal(g, f, elem_vals[ei]);
            recordConstTag(f, loc, elem_vals[ei]);
            item = valOf1(g, elem_ty, loc);
        }
        if info.pattern != 0 {
            let tested = test_(g, f, info.pattern, item, false, 0, id);
            if tested != squid_direct_types::Error.none { return false, tested; }
        }
        let s .= g.s;
        let labels_mark = s.labels.len;
        s.labels.push(squid_direct_emit::Label { target: id, depth: exit, result: unused, kind: squid_direct_emit::LabelKind.loop_, top: iter_done, iteration: iteration, outgoing: outgoing, unchanged: 0xffffffff, has_release: false, release_owner: 0, release_stack: 0, allocations: f.allocations, slots: slots, saved_esc: 0, guards: Words {} });
        let body_val, body_err = stmt(g, f, info.body);
        s.labels.resize(labels_mark);
        if body_err != squid_direct_types::Error.none { return false, body_err; }
        if body_val.ty != squid_direct_types::never {
            let carry_len = g.units[f.unit - 1].loopCarries(id).len;
            let backedge = g.reserveVals(carry_len);
            for at in 0..carry_len {
                let carry_be = g.units[f.unit - 1].loopCarries(id)[at].backedge;
                let value, present, rerr = readBindingVal(g, f, carry_be, id);
                if rerr != squid_direct_types::Error.none { return false, rerr; }
                if !present { return false, g.fail(g.units[f.unit - 1], id, "loop carry without a backedge value"); }
                g.s.vals[backedge.start + at] = value;
            }
            let assigned = assignCarries(g, f, backedge, iteration, slots, 0xffffffff, 0, 0, id);
            if assigned != squid_direct_types::Error.none { return false, assigned; }
        }
        close(g, f);
    }
    let final_assign = assign(g, f, iteration, outgoing, id);
    if final_assign != squid_direct_types::Error.none { return false, final_assign; }
    close(g, f);
    let carry_len = g.units[f.unit - 1].loopCarries(id).len;
    for at in 0..carry_len {
        let carry_out = g.units[f.unit - 1].loopCarries(id)[at].outgoing;
        bindPut(g, f, carry_out, g.s.vals[outgoing.start + at]);
    }
    return true, squid_direct_types::Error.none;
}

// Conservative pre-check: true only when `ty_id` lowers to an unboxed type
// (never allocates scope memory on construct/load/carry).
fn coreTypeUnboxed(g: Generator&, f: const Fn&, m: const Module&, tid: TId) -> bool {
    if tid == 0 { return false; }
    let ty, err = g.types.lower(m, tid, f.env);
    if err != squid_direct_types::Error.none { return false; }
    let boxed, berr = g.types.boxed(ty);
    if berr != squid_direct_types::Error.none || boxed { return false; }
    return true;
}

// Conservative pre-check: true only when evaluating `id` cannot allocate any
// scope memory or owners (allows skipping per-iteration release marks and
// `escape_min_slot` churn on non-allocating loops).
recursive fn bodyNoAlloc(g: Generator&, f: const Fn&, m: const Module&, id: u32, left: i64&, call_depth: i64 = 0) -> bool {
    if id == 0 { return true; }
    if left <= 0 { return false; }
    left -= 1;
    let n = m.node(id);
    match n.tag {
        constant, panic => { return true; },
        reference => {
            if call_depth == 0 { return true; }
            let ref = m.reference(id);
            if ref.unit == 0 || ref.unit == m.unit {
                let kind = m.binding(ref.binding).kind;
                if kind == squid_reuse_principal_interface::Kind.local || kind == squid_reuse_principal_interface::Kind.parameter { return true; }
            }
            return isCoreScalar(m, id);
        },
        suite, block_ => {
            for child in m.children(id) {
                if !bodyNoAlloc(g, f, m, child, left, call_depth) { return false; }
            }
            return true;
        },
        bind => { return bodyNoAlloc(g, f, m, n.b, left, call_depth); },
        return_ => { return bodyNoAlloc(g, f, m, n.a, left, call_depth); },
        break_ => {
            for child in m.children(id) {
                if !bodyNoAlloc(g, f, m, child, left, call_depth) { return false; }
            }
            return true;
        },
        if_value, if_stmt => {
            return bodyNoAlloc(g, f, m, n.a, left, call_depth) &&
                bodyNoAlloc(g, f, m, n.b, left, call_depth) &&
                bodyNoAlloc(g, f, m, n.c, left, call_depth);
        },
        match_ => {
            for inp in m.matchInputs(id) {
                if !bodyNoAlloc(g, f, m, inp, left, call_depth) { return false; }
            }
            for arm in m.matchArms(id) {
                if !bodyNoAlloc(g, f, m, arm.guard_, left, call_depth) || !bodyNoAlloc(g, f, m, arm.body, left, call_depth) { return false; }
            }
            return true;
        },
        pattern_bind => {
            return bodyNoAlloc(g, f, m, n.b, left, call_depth) && bodyNoAlloc(g, f, m, n.c, left, call_depth);
        },
        loop_ => {
            let linfo = m.loopInfo(id);
            if linfo.kind == squid_check_core::LoopKind.array {
                // Element loads of a copiedBox array allocate a fresh block.
                let src_ty_id = m.typeOf(linfo.first);
                if src_ty_id == 0 { return false; }
                let src_ty, serr = g.types.lower(m, src_ty_id, f.env);
                if serr != squid_direct_types::Error.none { return false; }
                match tagOf(g, src_ty) {
                    array, view => {
                        let elem_boxed, eberr = g.types.boxed(g.types.node(src_ty).a);
                        if eberr != squid_direct_types::Error.none || elem_boxed { return false; }
                    },
                    _ => { return false; },
                }
            }
            for carry in m.loopCarries(id) {
                let cty = m.binding(carry.incoming).ty;
                if !coreTypeUnboxed(g, f, m, cty) { return false; }
            }
            return bodyNoAlloc(g, f, m, linfo.first, left, call_depth) &&
                bodyNoAlloc(g, f, m, linfo.end, left, call_depth) &&
                bodyNoAlloc(g, f, m, linfo.body, left, call_depth);
        },
        construct => {
            return coreTypeUnboxed(g, f, m, m.typeOf(id)) && bodyNoAlloc(g, f, m, n.b, left, call_depth);
        },
        product, record => {
            if !coreTypeUnboxed(g, f, m, m.typeOf(id)) { return false; }
            for child in m.children(id) {
                if !bodyNoAlloc(g, f, m, child, left, call_depth) { return false; }
            }
            return true;
        },
        update => {
            let change = m.updateInfo(id);
            let sels = m.updateSelectors(id);
            if sels.len == 0 || sels[0].kind != squid_check_core::UpdateKind.index { return false; }
            if !coreTypeUnboxed(g, f, m, m.typeOf(change.value)) { return false; }
            if !bodyNoAlloc(g, f, m, change.root, left, call_depth) || !bodyNoAlloc(g, f, m, change.value, left, call_depth) { return false; }
            for sel in sels {
                if sel.kind == squid_check_core::UpdateKind.index && !bodyNoAlloc(g, f, m, sel.index, left, call_depth) { return false; }
            }
            return true;
        },
        project => {
            if isPureScalarProject(g, m, id) { return bodyNoAlloc(g, f, m, n.a, left, call_depth); }
            let proj = m.projection(n.b);
            let variants = m.projectionVariants(n.b);
            if variants.len != 0 { return coreTypeUnboxed(g, f, m, m.typeOf(id)) && bodyNoAlloc(g, f, m, n.a, left, call_depth); }
            let receiver_ty = m.types.node(m.typeOf(n.a)).tag;
            if receiver_ty == squid_check_types::Tag.record || receiver_ty == squid_check_types::Tag.product {
                return coreTypeUnboxed(g, f, m, m.typeOf(id)) && bodyNoAlloc(g, f, m, n.a, left, call_depth);
            }
            let receiver_local = localRef(m, n.a);
            if receiver_local != 0 {
                let spelling = m.fieldSpelling(proj.field);
                if spelling.present && spelling.value == "length" { return true; }
            }
            return false;
        },
        scalar, associated, logical => {
            if n.tag == squid_check_core::Tag.associated && n.op == squid_check_core::Op.none { return false; }
            return bodyNoAlloc(g, f, m, n.a, left, call_depth) && bodyNoAlloc(g, f, m, n.b, left, call_depth);
        },
        call => {
            let call = m.call(id);
            var callee_ok = scratchScalarCallee(g, m, call);
            if !callee_ok && call_depth < 2 {
                let target = g.resolve(m, call.target);
                if g.hasUnit(target.unit) {
                    let tm .= g.units[target.unit - 1];
                    let tbody .= tm.body(target.binding);
                    if tbody && tbody.is_function && !tbody.exported && tbody.scheme.variables.len == 0 && tm.bodyParameters(tbody).len == call.arguments.len {
                        let cf = Fn { unit: target.unit, .. };
                        callee_ok = bodyNoAlloc(g, cf, tm, tbody.root, left, call_depth + 1);
                    }
                }
            }
            if !callee_ok { return false; }
            for arg in call.arguments {
                if !bodyNoAlloc(g, f, m, arg, left, call_depth) { return false; }
            }
            return true;
        },
        array_op => {
            match m.arrayOperation(id) {
                length => {
                    for child in m.children(id) {
                        if !bodyNoAlloc(g, f, m, child, left, call_depth) { return false; }
                    }
                    return true;
                },
                get => {
                    if !coreTypeUnboxed(g, f, m, m.typeOf(id)) { return false; }
                    for child in m.children(id) {
                        if !bodyNoAlloc(g, f, m, child, left, call_depth) { return false; }
                    }
                    return true;
                },
                _ => { return false; },
            }
        },
        storage => {
            let op_kind, ok = squid_check_storage_ops::opFromCode(n.c);
            if ok != squid_error::Error.none { return false; }
            match op_kind {
                length => {
                    for child in m.children(id) {
                        if !bodyNoAlloc(g, f, m, child, left, call_depth) { return false; }
                    }
                    return true;
                },
                read => {
                    if !coreTypeUnboxed(g, f, m, m.typeOf(id)) { return false; }
                    for child in m.children(id) {
                        if !bodyNoAlloc(g, f, m, child, left, call_depth) { return false; }
                    }
                    return true;
                },
                _ => { return false; },
            }
        },
        _ => { return false; },
    }
}

// Collect local array bindings accessed inside `id` (following nested in-place
// loop carries back to their outer incoming binding) so `loop_` can pre-hoist
// their `ensureCheckedArray` checks once before `OP_loop`.
fn addHoistCandidate(out: u32[8]&, len: i64&, b: u32) {
    if b == 0 || len >= 8 { return; }
    for i in 0..len { if out[i] == b { return; } }
    out[len] = b;
    len += 1;
}
fn addLoopArrayCandidate(out: u32[16]&, len: i64&, b: u32) {
    if b == 0 || len >= 16 { return; }
    for i in 0..len { if out[i] == b { return; } }
    out[len] = b;
    len += 1;
}
recursive fn collectLoopArrayUses(m: const Module&, id: u32, out: u32[16]&, len: i64&, left: i64&) {
    if id == 0 || left <= 0 || len >= 16 { return; }
    left -= 1;
    let n = m.node(id);
    match n.tag {
        suite, block_, product, record, array, break_ => {
            for child in m.children(id) { collectLoopArrayUses(m, child, out, len, left); }
        },
        construct, bind => { collectLoopArrayUses(m, n.b, out, len, left); },
        return_, project => { collectLoopArrayUses(m, n.a, out, len, left); },
        if_value, if_stmt => {
            collectLoopArrayUses(m, n.a, out, len, left);
            collectLoopArrayUses(m, n.b, out, len, left);
            collectLoopArrayUses(m, n.c, out, len, left);
        },
        match_ => {
            for inp in m.matchInputs(id) { collectLoopArrayUses(m, inp, out, len, left); }
            for arm in m.matchArms(id) {
                collectLoopArrayUses(m, arm.guard_, out, len, left);
                collectLoopArrayUses(m, arm.body, out, len, left);
            }
        },
        pattern_bind => {
            collectLoopArrayUses(m, n.b, out, len, left);
            collectLoopArrayUses(m, n.c, out, len, left);
        },
        loop_ => {
            let linfo = m.loopInfo(id);
            collectLoopArrayUses(m, linfo.first, out, len, left);
            collectLoopArrayUses(m, linfo.end, out, len, left);
            for nc in m.loopCarries(id) { addLoopArrayCandidate(out, len, nc.incoming); }
            collectLoopArrayUses(m, linfo.body, out, len, left);
        },
        update => {
            let change = m.updateInfo(id);
            let sels = m.updateSelectors(id);
            if sels.len > 0 && sels[0].kind == squid_check_core::UpdateKind.index {
                addLoopArrayCandidate(out, len, localRef(m, change.root));
            }
            collectLoopArrayUses(m, change.root, out, len, left);
            collectLoopArrayUses(m, change.value, out, len, left);
            for sel in sels {
                if sel.kind == squid_check_core::UpdateKind.index {
                    collectLoopArrayUses(m, sel.index, out, len, left);
                }
            }
        },
        array_op => {
            let ch = m.children(id);
            match m.arrayOperation(id) {
                get, length => {
                    if ch.len > 0 { addLoopArrayCandidate(out, len, localRef(m, ch[0])); }
                },
                _ => {},
            }
            for child in ch { collectLoopArrayUses(m, child, out, len, left); }
        },
        storage => {
            let ch = m.children(id);
            let op_kind, ok = squid_check_storage_ops::opFromCode(n.c);
            if ok == squid_error::Error.none {
                match op_kind {
                    read, length, push, pop, truncate, reserve, extend, push_front, pop_front, insert, remove => {
                        if ch.len > 0 { addLoopArrayCandidate(out, len, localRef(m, ch[0])); }
                    },
                    _ => {},
                }
            }
            for child in ch { collectLoopArrayUses(m, child, out, len, left); }
        },
        scalar, associated, logical => {
            collectLoopArrayUses(m, n.a, out, len, left);
            collectLoopArrayUses(m, n.b, out, len, left);
        },
        call => {
            for arg in m.call(id).arguments {
                let atag = m.types.node(m.typeOf(arg)).tag;
                if atag == squid_check_types::Tag.array || atag == squid_check_types::Tag.usage {
                    addLoopArrayCandidate(out, len, localRef(m, arg));
                }
                collectLoopArrayUses(m, arg, out, len, left);
            }
        },
        apply => {
            if m.node(n.a).tag == squid_check_core::Tag.project {
                let proj_n = m.node(n.a);
                let sp = m.fieldSpelling(m.projection(proj_n.b).field);
                if sp.present && (sp.value == "at" || sp.value == "push" || sp.value == "pop" || sp.value == "truncate" || sp.value == "reserve" || sp.value == "extend") &&
                    m.types.node(m.typeOf(proj_n.a)).tag == squid_check_types::Tag.array {
                    addLoopArrayCandidate(out, len, localRef(m, proj_n.a));
                }
            }
            collectLoopArrayUses(m, n.a, out, len, left);
            collectLoopArrayUses(m, n.b, out, len, left);
        },
        spark => {
            let sinfo = m.sparkInfo(id);
            collectLoopArrayUses(m, sinfo.source, out, len, left);
            collectLoopArrayUses(m, sinfo.end, out, len, left);
            collectLoopArrayUses(m, sinfo.body, out, len, left);
        },
        _ => {},
    }
}

fn localKindForScalar(g: const Generator&, ty: Ty) -> ValType {
    match tagOf(g, ty) {
        f32_ => { return VT_f32; },
        f64_ => { return VT_f64; },
        u64_, i64_ => { return VT_i64; },
        _ => { return VT_i32; },
    }
}

fn returnedFreshArrayExpr(m: const Module&, id: u32) -> u32 {
    var cur = id;
    for step in 0..8 {
        if cur == 0 { return 0; }
        let n = m.node(cur);
        if n.tag == squid_check_core::Tag.return_ {
            cur = n.a;
        } else if (n.tag == squid_check_core::Tag.block_ || n.tag == squid_check_core::Tag.suite) && n.b > 0 {
            let ch = m.children(cur);
            for i in 0..(ch.len - 1) {
                let cn = m.node(ch[i]);
                if cn.tag != squid_check_core::Tag.bind || cn.c >= 2 { return 0; }
            }
            cur = ch[ch.len - 1];
        } else {
            break;
        }
    }
    return cur;
}
recursive fn isFreshOwnedArrayNode(g: const Generator&, m: const Module&, id: u32, depth: i64 = 0) -> bool {
    if id == 0 { return false; }
    let n = m.node(id);
    match n.tag {
        array, spark => { return true; },
        array_op => {
            match m.arrayOperation(id) {
                fill, generate, slice, append, prepend, concat, flatten => { return true; },
                _ => { return false; },
            }
        },
        storage => {
            let op_kind, ok = squid_check_storage_ops::opFromCode(n.c);
            if ok != squid_error::Error.none { return false; }
            if op_kind == squid_check_storage_ops::Op.copy { return true; }
            if op_kind == squid_check_storage_ops::Op.push {
                let ch = m.children(id);
                return ch.len == 2 && isFreshOwnedArrayNode(g, m, ch[0], depth + 1);
            }
            return false;
        },
        call => {
            if depth > 0 { return false; }
            let target = g.resolve(m, m.call(id).target);
            if !g.hasUnit(target.unit) { return false; }
            let tm .= g.units[target.unit - 1];
            let tbody .= tm.body(target.binding);
            if !tbody || !tbody.is_function || tbody.exported { return false; }
            let ret = returnedFreshArrayExpr(tm, tbody.root);
            return isFreshOwnedArrayNode(g, tm, ret, depth + 1);
        },
        _ => { return false; },
    }
}
recursive fn scanCarryUniqueOwned(
    g: Generator&,
    f: Fn&,
    m: const Module&,
    loop_id: u32,
    carry_at: i64,
    id: u32,
    owned: u32[64]&,
    owned_len: i64&,
    budget: i64&,
) -> bool {
    if id == 0 { return true; }
    if budget <= 0 { return false; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        suite, block_ => {
            for child in m.children(id) {
                if !scanCarryUniqueOwned(g, f, m, loop_id, carry_at, child, owned, owned_len, budget) { return false; }
            }
            return true;
        },
        bind => {
            if !scanCarryUniqueOwned(g, f, m, loop_id, carry_at, n.b, owned, owned_len, budget) { return false; }
            if n.c < 2 && (isFreshOwnedArrayNode(g, m, n.b, 0) || exprPreservesHandle(g, m, n.b, owned, owned_len, 0, false, 0)) {
                addBindingSet(owned, owned_len, n.a);
            }
            return true;
        },
        if_stmt, if_value => {
            if !scanCarryUniqueOwned(g, f, m, loop_id, carry_at, n.a, owned, owned_len, budget) ||
                !scanCarryUniqueOwned(g, f, m, loop_id, carry_at, n.b, owned, owned_len, budget) ||
                !scanCarryUniqueOwned(g, f, m, loop_id, carry_at, n.c, owned, owned_len, budget) { return false; }
            for merge in m.branchMerges(id) {
                if inBindingSet(owned, owned_len, merge.then_binding) && inBindingSet(owned, owned_len, merge.else_binding) {
                    addBindingSet(owned, owned_len, merge.result);
                }
            }
            return true;
        },
        match_ => {
            for inp in m.matchInputs(id) {
                if !scanCarryUniqueOwned(g, f, m, loop_id, carry_at, inp, owned, owned_len, budget) { return false; }
            }
            for arm in m.matchArms(id) {
                if !scanCarryUniqueOwned(g, f, m, loop_id, carry_at, arm.guard_, owned, owned_len, budget) ||
                    !scanCarryUniqueOwned(g, f, m, loop_id, carry_at, arm.body, owned, owned_len, budget) { return false; }
            }
            for merge in m.branchMerges(id) {
                if inBindingSet(owned, owned_len, merge.then_binding) && inBindingSet(owned, owned_len, merge.else_binding) {
                    addBindingSet(owned, owned_len, merge.result);
                }
            }
            return true;
        },
        loop_ => {
            let ninfo = m.loopInfo(id);
            if !scanCarryUniqueOwned(g, f, m, loop_id, carry_at, ninfo.first, owned, owned_len, budget) ||
                !scanCarryUniqueOwned(g, f, m, loop_id, carry_at, ninfo.end, owned, owned_len, budget) { return false; }
            for nc, nc_at in m.loopCarries(id) {
                if inBindingSet(owned, owned_len, nc.incoming) &&
                    ownedRefUses(g, f, nc.incoming) == 0 && ownedFlowUses(g, f, nc.incoming) == 1 &&
                    carryBackedgeIsUniqueOwned(g, f, m, id, nc_at, nc.iteration, nc.backedge, budget) {
                    addBindingSet(owned, owned_len, nc.outgoing);
                }
            }
            return scanCarryUniqueOwned(g, f, m, loop_id, carry_at, ninfo.body, owned, owned_len, budget);
        },
        break_ => {
            let vals = m.breakValues(id);
            for child in vals {
                if !scanCarryUniqueOwned(g, f, m, loop_id, carry_at, child, owned, owned_len, budget) { return false; }
            }
            if n.a == loop_id {
                if carry_at >= vals.len { return false; }
                let cv = vals[carry_at];
                if !isFreshOwnedArrayNode(g, m, cv, 0) {
                    let cb = localRef(m, cv);
                    if cb == 0 || !inBindingSet(owned, owned_len, cb) || ownedTotalUses(g, f, cb) != 1 { return false; }
                }
            }
            return true;
        },
        pattern_bind => {
            return scanCarryUniqueOwned(g, f, m, loop_id, carry_at, n.b, owned, owned_len, budget) &&
                scanCarryUniqueOwned(g, f, m, loop_id, carry_at, n.c, owned, owned_len, budget);
        },
        constant, reference, panic, spark, array, array_op, storage, scalar, associated, logical, call, apply, update, product, record, construct, project, return_, result_associated, closure => {
            return true;
        },
        _ => { return false; },
    }
}
recursive fn carryBackedgeIsUniqueOwned(
    g: Generator&,
    f: Fn&,
    m: const Module&,
    loop_id: u32,
    carry_at: i64,
    iter_binding: u32,
    backedge_binding: u32,
    budget: i64&,
) -> bool {
    var owned: u32[64] = [0; 64];
    var owned_len: i64 = 0;
    addBindingSet(owned, owned_len, iter_binding);
    if !scanCarryUniqueOwned(g, f, m, loop_id, carry_at, m.loopInfo(loop_id).body, owned, owned_len, budget) { return false; }
    if backedge_binding == 0 { return true; }
    if !inBindingSet(owned, owned_len, backedge_binding) { return false; }
    if backedge_binding != iter_binding {
        if ownedRefUses(g, f, backedge_binding) != 0 || ownedFlowUses(g, f, backedge_binding) != 1 || bindingCaptured(g, f, backedge_binding) {
            return false;
        }
    }
    return true;
}

recursive fn collectPatternBindings(
    m: const Module&,
    pat_id: u32,
    is_root: bool,
    out: u32[32]&,
    out_len: i64&,
    has_root_bind: bool&,
    overflow: bool&,
    depth: i64,
) {
    if pat_id == 0 || overflow { return; }
    if depth > 32 { overflow = true; return; }
    let pat = m.pattern(pat_id);
    match pat.tag {
        bind => {
            if is_root { has_root_bind = true; }
            if pat.a != 0 {
                var dup = false;
                for i in 0..out_len { if out[i] == pat.a { dup = true; break; } }
                if !dup {
                    if out_len >= 32 { overflow = true; return; }
                    out[out_len] = pat.a;
                    out_len += 1;
                }
            }
        },
        constructor, record_payload => {
            if pat.b != 0 { collectPatternBindings(m, pat.b, false, out, out_len, has_root_bind, overflow, depth + 1); }
        },
        product => {
            for child in m.patternChildren(pat_id) {
                collectPatternBindings(m, child, false, out, out_len, has_root_bind, overflow, depth + 1);
            }
        },
        invalid, wildcard, constant, value => {},
    }
}
recursive fn hasPreTailBindingUse(
    m: const Module&,
    id: u32,
    allow_bind: bool,
    binding: u32,
    depth: i64,
) -> bool {
    if id == 0 || binding == 0 { return false; }
    if depth > 16 { return true; }
    let n = m.node(id);
    match n.tag {
        construct => { return false; },
        suite => {
            let items = m.children(id);
            if items.len == 0 { return false; }
            for i in 0..items.len - 1 {
                if nodeReadsBinding(m, items[i], binding, 0) { return true; }
            }
            return hasPreTailBindingUse(m, items[items.len - 1], allow_bind, binding, depth + 1);
        },
        block_ => {
            let items = m.children(id);
            if items.len == 0 { return false; }
            for i in 0..items.len - 1 {
                if nodeReadsBinding(m, items[i], binding, 0) { return true; }
            }
            let ln = m.node(items[items.len - 1]);
            if ln.tag == squid_check_core::Tag.return_ && ln.b == id && ln.a != 0 {
                return hasPreTailBindingUse(m, ln.a, false, binding, depth + 1);
            }
            return nodeReadsBinding(m, items[items.len - 1], binding, 0);
        },
        return_ => { return hasPreTailBindingUse(m, n.a, false, binding, depth + 1); },
        bind => {
            if allow_bind && n.c < 2 && n.b != 0 {
                return hasPreTailBindingUse(m, n.b, false, binding, depth + 1);
            }
            return nodeReadsBinding(m, n.b, binding, 0);
        },
        if_value => {
            if nodeReadsBinding(m, n.a, binding, 0) { return true; }
            return hasPreTailBindingUse(m, n.b, false, binding, depth + 1) ||
                hasPreTailBindingUse(m, n.c, false, binding, depth + 1);
        },
        if_stmt => {
            if nodeReadsBinding(m, n.a, binding, 0) { return true; }
            if !allow_bind { return nodeReadsBinding(m, n.b, binding, 0) || nodeReadsBinding(m, n.c, binding, 0); }
            if hasPreTailBindingUse(m, n.b, true, binding, depth + 1) { return true; }
            if n.c != 0 { return hasPreTailBindingUse(m, n.c, true, binding, depth + 1); }
            return false;
        },
        _ => { return nodeReadsBinding(m, id, binding, 0); },
    }
}

recursive fn scanCarryUniqueBoxed(
    g: Generator&,
    f: Fn&,
    m: const Module&,
    loop_id: u32,
    carry_at: i64,
    iter_binding: u32,
    id: u32,
    boxed_set: u32[64]&,
    boxed_len: i64&,
    budget: i64&,
) -> bool {
    if id == 0 { return true; }
    if budget <= 0 { return false; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        suite, block_ => {
            for child in m.children(id) {
                if !scanCarryUniqueBoxed(g, f, m, loop_id, carry_at, iter_binding, child, boxed_set, boxed_len, budget) { return false; }
            }
            return true;
        },
        bind => {
            if !scanCarryUniqueBoxed(g, f, m, loop_id, carry_at, iter_binding, n.b, boxed_set, boxed_len, budget) { return false; }
            if n.c < 2 {
                if isFreshBoxedNode(m, n.b, 0) {
                    addBindingSet(boxed_set, boxed_len, n.a);
                } else {
                    let rb = localRef(m, n.b);
                    if rb != 0 && inBindingSet(boxed_set, boxed_len, rb) && uses(g, f, rb) == 1 && !bindingCaptured(g, f, rb) {
                        addBindingSet(boxed_set, boxed_len, n.a);
                    }
                }
            }
            return true;
        },
        if_stmt, if_value => {
            if !scanCarryUniqueBoxed(g, f, m, loop_id, carry_at, iter_binding, n.a, boxed_set, boxed_len, budget) ||
                !scanCarryUniqueBoxed(g, f, m, loop_id, carry_at, iter_binding, n.b, boxed_set, boxed_len, budget) ||
                !scanCarryUniqueBoxed(g, f, m, loop_id, carry_at, iter_binding, n.c, boxed_set, boxed_len, budget) { return false; }
            for merge in m.branchMerges(id) {
                if inBindingSet(boxed_set, boxed_len, merge.then_binding) && inBindingSet(boxed_set, boxed_len, merge.else_binding) {
                    addBindingSet(boxed_set, boxed_len, merge.result);
                }
            }
            return true;
        },
        match_ => {
            for inp in m.matchInputs(id) {
                if !scanCarryUniqueBoxed(g, f, m, loop_id, carry_at, iter_binding, inp, boxed_set, boxed_len, budget) { return false; }
            }
            for arm in m.matchArms(id) {
                if !scanCarryUniqueBoxed(g, f, m, loop_id, carry_at, iter_binding, arm.guard_, boxed_set, boxed_len, budget) ||
                    !scanCarryUniqueBoxed(g, f, m, loop_id, carry_at, iter_binding, arm.body, boxed_set, boxed_len, budget) { return false; }
            }
            for merge in m.branchMerges(id) {
                if inBindingSet(boxed_set, boxed_len, merge.then_binding) && inBindingSet(boxed_set, boxed_len, merge.else_binding) {
                    addBindingSet(boxed_set, boxed_len, merge.result);
                }
            }
            return true;
        },
        loop_ => {
            let ninfo = m.loopInfo(id);
            if !scanCarryUniqueBoxed(g, f, m, loop_id, carry_at, iter_binding, ninfo.first, boxed_set, boxed_len, budget) ||
                !scanCarryUniqueBoxed(g, f, m, loop_id, carry_at, iter_binding, ninfo.end, boxed_set, boxed_len, budget) { return false; }
            for nc, nc_at in m.loopCarries(id) {
                if inBindingSet(boxed_set, boxed_len, nc.incoming) &&
                    uses(g, f, nc.incoming) == 1 && !bindingCaptured(g, f, nc.incoming) &&
                    carryBackedgeIsUniqueBoxed(g, f, m, id, nc_at, nc.iteration, nc.backedge, budget) {
                    addBindingSet(boxed_set, boxed_len, nc.outgoing);
                }
            }
            return scanCarryUniqueBoxed(g, f, m, loop_id, carry_at, iter_binding, ninfo.body, boxed_set, boxed_len, budget);
        },
        break_ => {
            let vals = m.breakValues(id);
            for child in vals {
                if !scanCarryUniqueBoxed(g, f, m, loop_id, carry_at, iter_binding, child, boxed_set, boxed_len, budget) { return false; }
            }
            if n.a == loop_id && n.op == squid_check_core::Op.continue_ {
                if carry_at >= vals.len { return false; }
                let cv = vals[carry_at];
                if !isFreshBoxedNode(m, cv, 0) {
                    let cb = localRef(m, cv);
                    if cb == 0 || !inBindingSet(boxed_set, boxed_len, cb) || bindingCaptured(g, f, cb) { return false; }
                    if cb == iter_binding {
                        if uses(g, f, cb) > 1 { return false; }
                    } else if uses(g, f, cb) != 0 {
                        return false;
                    }
                }
            }
            return true;
        },
        pattern_bind => {
            return scanCarryUniqueBoxed(g, f, m, loop_id, carry_at, iter_binding, n.b, boxed_set, boxed_len, budget) &&
                scanCarryUniqueBoxed(g, f, m, loop_id, carry_at, iter_binding, n.c, boxed_set, boxed_len, budget);
        },
        constant, reference, panic, spark, array, array_op, storage, scalar, associated, logical, call, apply, update, product, record, construct, project, return_, result_associated, closure => {
            return true;
        },
        _ => { return false; },
    }
}
recursive fn carryBackedgeIsUniqueBoxed(
    g: Generator&,
    f: Fn&,
    m: const Module&,
    loop_id: u32,
    carry_at: i64,
    iter_binding: u32,
    backedge_binding: u32,
    budget: i64&,
) -> bool {
    var boxed_set: u32[64] = [0; 64];
    var boxed_len: i64 = 0;
    addBindingSet(boxed_set, boxed_len, iter_binding);
    if !scanCarryUniqueBoxed(g, f, m, loop_id, carry_at, iter_binding, m.loopInfo(loop_id).body, boxed_set, boxed_len, budget) { return false; }
    if backedge_binding == 0 { return true; }
    if !inBindingSet(boxed_set, boxed_len, backedge_binding) { return false; }
    if backedge_binding != iter_binding {
        if uses(g, f, backedge_binding) != 1 || bindingCaptured(g, f, backedge_binding) {
            return false;
        }
    }
    return true;
}

recursive fn markUnpatchableExprConstants(m: const Module&, id: u32, depth: i64) {
    if id == 0 || depth >= 64 { return; }
    let n = m.node(id);
    match n.tag {
        constant => { squid_direct_relocations::unpatchableOperand(m.unit, id); },
        scalar, associated, logical, apply => {
            markUnpatchableExprConstants(m, n.a, depth + 1);
            markUnpatchableExprConstants(m, n.b, depth + 1);
        },
        suite, block_, product, record, array, array_op, storage, break_ => {
            for ch in m.children(id) { markUnpatchableExprConstants(m, ch, depth + 1); }
        },
        bind, construct => { markUnpatchableExprConstants(m, n.b, depth + 1); },
        return_, project, result_associated, fork_, flat_op => { markUnpatchableExprConstants(m, n.a, depth + 1); },
        if_stmt, if_value => {
            markUnpatchableExprConstants(m, n.a, depth + 1);
            markUnpatchableExprConstants(m, n.b, depth + 1);
            markUnpatchableExprConstants(m, n.c, depth + 1);
        },
        call => {
            for arg in m.call(id).arguments { markUnpatchableExprConstants(m, arg, depth + 1); }
        },
        update => {
            let uinfo = m.updateInfo(id);
            markUnpatchableExprConstants(m, uinfo.root, depth + 1);
            markUnpatchableExprConstants(m, uinfo.value, depth + 1);
            for sel in m.updateSelectors(id) {
                if sel.kind == squid_check_core::UpdateKind.index {
                    markUnpatchableExprConstants(m, sel.index, depth + 1);
                }
            }
        },
        spark => {
            let sinfo = m.sparkInfo(id);
            markUnpatchableExprConstants(m, sinfo.source, depth + 1);
            markUnpatchableExprConstants(m, sinfo.end, depth + 1);
            markUnpatchableExprConstants(m, sinfo.body, depth + 1);
        },
        _ => {},
    }
}

fn isPureU32Op(op_: Op) -> bool {
    match op_ {
        add, sub, mul, bit_and, bit_or, bit_xor, shift_left, shift_right, shift_right_signed, bit_andnot, bit_not, neg => { return true; },
        _ => { return false; },
    }
}
recursive fn isPureU32Expr(g: const Generator&, f: const Fn&, m: const Module&, id: u32, forbid_binding: u32, budget: i64&) -> bool {
    if id == 0 { return true; }
    if budget <= 0 { return false; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        constant => { return m.types.node(m.typeOf(id)).tag == squid_check_types::Tag.unsigned32; },
        reference => {
            let b = localRef(m, id);
            if b == 0 || b == forbid_binding { return false; }
            let _, is_cell = withCellType(g, f, b);
            return !is_cell && m.types.node(m.typeOf(id)).tag == squid_check_types::Tag.unsigned32;
        },
        scalar => {
            if !isPureU32Op(n.op) || m.types.node(m.typeOf(id)).tag != squid_check_types::Tag.unsigned32 { return false; }
            return isPureU32Expr(g, f, m, n.a, forbid_binding, budget) &&
                isPureU32Expr(g, f, m, n.b, forbid_binding, budget);
        },
        _ => { return false; },
    }
}
recursive fn matchAffineU32Step(m: const Module&, expr_id: u32, target_iter: u32) -> bool, u32, u32 {
    if expr_id == 0 { return false, 0, 0; }
    let n = m.node(expr_id);
    if n.tag != squid_check_core::Tag.scalar { return false, 0, 0; }
    if n.op == squid_check_core::Op.add {
        let an = m.node(n.a);
        let bn = m.node(n.b);
        if bn.tag == squid_check_core::Tag.constant {
            let ok, a_mul, _ = matchAffineU32Step(m, n.a, target_iter);
            if ok { return true, a_mul, bn.a; }
        }
        if an.tag == squid_check_core::Tag.constant {
            let ok, a_mul, _ = matchAffineU32Step(m, n.b, target_iter);
            if ok { return true, a_mul, an.a; }
        }
        return false, 0, 0;
    }
    if n.op == squid_check_core::Op.mul {
        let an = m.node(n.a);
        let bn = m.node(n.b);
        if localRef(m, n.a) == target_iter && bn.tag == squid_check_core::Tag.constant {
            return true, bn.a, 0;
        }
        if localRef(m, n.b) == target_iter && an.tag == squid_check_core::Tag.constant {
            return true, an.a, 0;
        }
    }
    return false, 0, 0;
}
// 5F: Algebraically vectorize (16-wide 4x v128 SIMD for associative single-accumulator
// LCG recurrences like `s := s * A + C; acc := acc ^ (s >> 16)`) or 8x unroll pure
// counted U32 loops containing an affine LCG recurrence `s := s * A + C` (exact mod 2^32).
fn matchAffineTermOp(m: const Module&, id: u32, s_back: u32) -> bool, squid_check_core::Op, u32 {
    if id == 0 { return false, squid_check_core::Op.none, 0; }
    if localRef(m, id) == s_back { return true, squid_check_core::Op.none, 0; }
    let n = m.node(id);
    if n.tag != squid_check_core::Tag.scalar && !(n.tag == squid_check_core::Tag.associated && n.op != squid_check_core::Op.none) {
        return false, squid_check_core::Op.none, 0;
    }
    match n.op {
        shift_right, shift_right_signed, shift_left => {
            if localRef(m, n.a) == s_back && m.node(n.b).tag == squid_check_core::Tag.constant {
                return true, n.op, m.node(n.b).a;
            }
            return false, squid_check_core::Op.none, 0;
        },
        bit_and, bit_or, bit_xor => {
            if localRef(m, n.a) == s_back && m.node(n.b).tag == squid_check_core::Tag.constant {
                return true, n.op, m.node(n.b).a;
            }
            if localRef(m, n.b) == s_back && m.node(n.a).tag == squid_check_core::Tag.constant {
                return true, n.op, m.node(n.a).a;
            }
            return false, squid_check_core::Op.none, 0;
        },
        _ => { return false, squid_check_core::Op.none, 0; },
    }
}
fn emitAffineVecTerm(g: Generator&, vs: u32, term_op: squid_check_core::Op, term_const: u32, v_mask: u32) {
    lget(g, vs);
    match term_op {
        none => {},
        shift_right => { i32Const(g, term_const); simdOp(g, SIMD_i32x4_shr_u); },
        shift_right_signed => { i32Const(g, term_const); simdOp(g, SIMD_i32x4_shr_s); },
        shift_left => { i32Const(g, term_const); simdOp(g, SIMD_i32x4_shl); },
        bit_and => { lget(g, v_mask); simdOp(g, SIMD_v128_and); },
        bit_or => { lget(g, v_mask); simdOp(g, SIMD_v128_or); },
        bit_xor => { lget(g, v_mask); simdOp(g, SIMD_v128_xor); },
        _ => {},
    }
}
fn tryEmitAffineUnrollLoop(
    g: Generator&,
    f: Fn&,
    loop_id: u32,
    info: squid_check_core::LoopInfo,
    iteration: Vals,
    index: u32,
    end_local: u32,
) -> Error {
    var stmts: u32[8] = [0; 8];
    var stmts_len: i64 = 0;
    var carry_count: i64 = 0;
    var carry_iter: u32[4] = [0; 4];
    var carry_back: u32[4] = [0; 4];
    var affine_carry: i64 = -1;
    var affine_stmt: i64 = -1;
    var a1: u32 = 0;
    var c1: u32 = 0;
    var start_is_zero = false;
    var simd_acc_ok = false;
    var acc_carry: i64 = -1;
    var acc_is_xor = false;
    var term_op = squid_check_core::Op.none;
    var term_const: u32 = 0;
    var matched = false;
    {
        let m .= g.units[f.unit - 1];
        if info.kind != squid_check_core::LoopKind.range || info.body == 0 { return squid_direct_types::Error.none; }
        if info.pattern != 0 {
            let pat = m.pattern(info.pattern);
            if pat.tag == squid_check_core::PatternTag.bind {
                if uses(g, f, pat.a) != 0 { return squid_direct_types::Error.none; }
            } else if pat.tag != squid_check_core::PatternTag.wildcard {
                return squid_direct_types::Error.none;
            }
        }
        let carries = m.loopCarries(loop_id);
        if carries.len == 0 || carries.len > 4 { return squid_direct_types::Error.none; }
        for carry, ci in carries {
            if carry.backedge == 0 { return squid_direct_types::Error.none; }
            let iv = g.s.vals[iteration.start + ci];
            if iv.len != 1 || tagOf(g, iv.ty) != squid_direct_types::Tag.u32_ { return squid_direct_types::Error.none; }
            carry_iter[ci] = carry.iteration;
            carry_back[ci] = carry.backedge;
        }
        carry_count = carries.len;
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
        var affine_rhs_id: u32 = 0;
        var acc_term_node: u32 = 0;
        for si in 0..stmts_len {
            let sn = m.node(stmts[si]);
            if sn.tag != squid_check_core::Tag.bind || sn.c >= 2 || m.binding(sn.a).scheme.variables.len != 0 {
                return squid_direct_types::Error.none;
            }
            if affine_carry < 0 {
                for ci in 0..carry_count {
                    if sn.a == carry_back[ci] {
                        let ok, ma, mc = matchAffineU32Step(m, sn.b, carry_iter[ci]);
                        if ok {
                            affine_carry = ci;
                            affine_stmt = si;
                            affine_rhs_id = sn.b;
                            a1 = ma;
                            c1 = mc;
                            break;
                        }
                    }
                }
            }
        }
        if affine_carry < 0 { return squid_direct_types::Error.none; }
        // Verify every other statement is pure U32 and does not read the old affine carry.
        for si in 0..stmts_len {
            if si == affine_stmt { continue; }
            let sn = m.node(stmts[si]);
            var b: i64 = 32;
            if !isPureU32Expr(g, f, m, sn.b, carry_iter[affine_carry], b) {
                return squid_direct_types::Error.none;
            }
        }
        // Detect single associative accumulator `acc := acc (^|+) term(s_new)` for 16-wide v128 SIMD!
        if !g.runtime_().has_fork && carry_count == 2 && stmts_len == 2 {
            let oc = 1 - affine_carry;
            let os = 1 - affine_stmt;
            let osn = m.node(stmts[os]);
            if osn.a == carry_back[oc] {
                let r = m.node(osn.b);
                let is_op = r.tag == squid_check_core::Tag.scalar || (r.tag == squid_check_core::Tag.associated && r.op != squid_check_core::Op.none);
                if is_op && (r.op == squid_check_core::Op.bit_xor || r.op == squid_check_core::Op.add) {
                    var term_node: u32 = 0;
                    if localRef(m, r.a) == carry_iter[oc] { term_node = r.b; }
                    else if localRef(m, r.b) == carry_iter[oc] { term_node = r.a; }
                    let tok, top, tconst = matchAffineTermOp(m, term_node, carry_back[affine_carry]);
                    if tok {
                        simd_acc_ok = true;
                        acc_carry = oc;
                        acc_is_xor = r.op == squid_check_core::Op.bit_xor;
                        acc_term_node = term_node;
                        term_op = top;
                        term_const = tconst;
                    }
                }
            }
        }
        start_is_zero = m.node(info.first).tag == squid_check_core::Tag.constant && m.node(info.first).a == 0;
        matched = true;
        markUnpatchableExprConstants(m, affine_rhs_id, 0);
        if simd_acc_ok {
            markUnpatchableExprConstants(m, acc_term_node, 0);
            if start_is_zero { squid_direct_relocations::unpatchableOperand(m.unit, info.first); }
        }
    }
    if !matched { return squid_direct_types::Error.none; }

    let affine_loc = w(g, g.s.vals[iteration.start + affine_carry], 0);

    // Fast path: 16-wide (4 x v128) SIMD LCG recurrence!
    if simd_acc_ok {
        var ak16: u32[16] = [0; 16];
        var ck16: u32[16] = [0; 16];
        ak16[0] = a1;
        ck16[0] = c1;
        for k in 1..16 {
            ak16[k] = ak16[k - 1] * a1;
            ck16[k] = ck16[k - 1] * a1 + c1;
        }
        let n16 = local32(g, f);
        if start_is_zero {
            lget(g, end_local);
            i32Const(g, 0xfffffff0);
            op(g, OP_i32_and);
            lset(g, n16);
        } else {
            lget(g, end_local);
            lget(g, index);
            op(g, OP_i32_gt_u);
            let cif = open(g, f, OP_if_);
            lget(g, end_local);
            lget(g, index);
            op(g, OP_i32_sub);
            i32Const(g, 0xfffffff0);
            op(g, OP_i32_and);
            lset(g, n16);
            popCheckedArraysAt(f, cif);
            op(g, OP_else_);
            i32Const(g, 0);
            lset(g, n16);
            close(g, f);
        }

        lget(g, n16);
        i32Const(g, 0);
        op(g, OP_i32_gt_u);
        let run_if = open(g, f, OP_if_);

        let vs0 = local(g, f, VT_v128);
        let vs1 = local(g, f, VT_v128);
        let vs2 = local(g, f, VT_v128);
        let vs3 = local(g, f, VT_v128);
        let vA4 = local(g, f, VT_v128);
        let vC4 = local(g, f, VT_v128);
        let vA16 = local(g, f, VT_v128);
        let vC16 = local(g, f, VT_v128);
        let vacc0 = local(g, f, VT_v128);
        let vacc1 = local(g, f, VT_v128);
        var v_mask: u32 = 0;
        if term_op == squid_check_core::Op.bit_and || term_op == squid_check_core::Op.bit_or || term_op == squid_check_core::Op.bit_xor {
            v_mask = local(g, f, VT_v128);
            v128Const4(g, term_const);
            lset(g, v_mask);
        }

        // Seed vs0 = [s1, s2, s3, s4], vs1 = [s5..s8], vs2 = [s9..s12], vs3 = [s13..s16]
        lget(g, affine_loc);
        simdOp(g, SIMD_i32x4_splat);
        v128ConstWords(g, ak16[0], ak16[1], ak16[2], ak16[3]);
        simdOp(g, SIMD_i32x4_mul);
        v128ConstWords(g, ck16[0], ck16[1], ck16[2], ck16[3]);
        simdOp(g, SIMD_i32x4_add);
        lset(g, vs0);

        v128Const4(g, ak16[3]); lset(g, vA4);
        v128Const4(g, ck16[3]); lset(g, vC4);
        lget(g, vs0); lget(g, vA4); simdOp(g, SIMD_i32x4_mul); lget(g, vC4); simdOp(g, SIMD_i32x4_add); lset(g, vs1);
        lget(g, vs1); lget(g, vA4); simdOp(g, SIMD_i32x4_mul); lget(g, vC4); simdOp(g, SIMD_i32x4_add); lset(g, vs2);
        lget(g, vs2); lget(g, vA4); simdOp(g, SIMD_i32x4_mul); lget(g, vC4); simdOp(g, SIMD_i32x4_add); lset(g, vs3);

        v128Const4(g, ak16[15]); lset(g, vA16);
        v128Const4(g, ck16[15]); lset(g, vC16);
        v128Const4(g, 0); lset(g, vacc0);
        v128Const4(g, 0); lset(g, vacc1);

        var v_acc_op = SIMD_i32x4_add;
        var s_acc_op = OP_i32_add;
        if acc_is_xor {
            v_acc_op = SIMD_v128_xor;
            s_acc_op = OP_i32_xor;
        }
        let rem = local32(g, f);
        lget(g, n16);
        lset(g, rem);

        let s_exit = open(g, f, OP_block);
        let s_top = open(g, f, OP_loop);

        lget(g, vacc0); emitAffineVecTerm(g, vs0, term_op, term_const, v_mask); simdOp(g, v_acc_op);
        emitAffineVecTerm(g, vs2, term_op, term_const, v_mask); simdOp(g, v_acc_op);
        lset(g, vacc0);

        lget(g, vacc1); emitAffineVecTerm(g, vs1, term_op, term_const, v_mask); simdOp(g, v_acc_op);
        emitAffineVecTerm(g, vs3, term_op, term_const, v_mask); simdOp(g, v_acc_op);
        lset(g, vacc1);

        lget(g, rem);
        i32Const(g, 16);
        op(g, OP_i32_sub);
        ltee(g, rem);
        op(g, OP_i32_eqz);
        br(g, f, OP_br_if, s_exit);

        lget(g, vs0); lget(g, vA16); simdOp(g, SIMD_i32x4_mul); lget(g, vC16); simdOp(g, SIMD_i32x4_add); lset(g, vs0);
        lget(g, vs1); lget(g, vA16); simdOp(g, SIMD_i32x4_mul); lget(g, vC16); simdOp(g, SIMD_i32x4_add); lset(g, vs1);
        lget(g, vs2); lget(g, vA16); simdOp(g, SIMD_i32x4_mul); lget(g, vC16); simdOp(g, SIMD_i32x4_add); lset(g, vs2);
        lget(g, vs3); lget(g, vA16); simdOp(g, SIMD_i32x4_mul); lget(g, vC16); simdOp(g, SIMD_i32x4_add); lset(g, vs3);
        br(g, f, OP_br, s_top);
        close(g, f);
        close(g, f);

        // On exit, lane 3 of vs3 holds exact state s_{n16}!
        lget(g, vs3);
        simdLaneOp(g, SIMD_i32x4_extract_lane, 3);
        lset(g, affine_loc);

        // Horizontal reduction of vacc0 (op) vacc1 into acc_loc!
        let vtot = local(g, f, VT_v128);
        lget(g, vacc0);
        lget(g, vacc1);
        simdOp(g, v_acc_op);
        lset(g, vtot);

        let acc_loc = w(g, g.s.vals[iteration.start + acc_carry], 0);
        lget(g, acc_loc);
        for lane in 0..4 {
            lget(g, vtot);
            simdLaneOp(g, SIMD_i32x4_extract_lane, lane as u8);
            op(g, s_acc_op);
        }
        lset(g, acc_loc);

        lget(g, index);
        lget(g, n16);
        op(g, OP_i32_add);
        lset(g, index);

        popCheckedArraysAt(f, run_if);
        close(g, f);
        return squid_direct_types::Error.none;
    }

    // General path: 8x scalar parallel-power affine unrolling.
    var ak: u32[8] = [0; 8];
    var ck: u32[8] = [0; 8];
    ak[0] = a1;
    ck[0] = c1;
    for k in 1..8 {
        ak[k] = ak[k - 1] * a1;
        ck[k] = ck[k - 1] * a1 + c1;
    }

    var unroll_end: u32 = 0;
    if start_is_zero {
        unroll_end = local32(g, f);
        lget(g, end_local);
        i32Const(g, 0xfffffff8);
        op(g, OP_i32_and);
        lset(g, unroll_end);
    } else {
        let count = local32(g, f);
        lget(g, end_local);
        lget(g, index);
        op(g, OP_i32_gt_u);
        let cif = open(g, f, OP_if_);
        lget(g, end_local);
        lget(g, index);
        op(g, OP_i32_sub);
        lset(g, count);
        popCheckedArraysAt(f, cif);
        op(g, OP_else_);
        i32Const(g, 0);
        lset(g, count);
        close(g, f);
        unroll_end = local32(g, f);
        lget(g, index);
        lget(g, count);
        i32Const(g, 0xfffffff8);
        op(g, OP_i32_and);
        op(g, OP_i32_add);
        lset(g, unroll_end);
    }

    let base_s = local32(g, f);
    let s_cur = local32(g, f);

    let u_exit = open(g, f, OP_block);
    let u_top = open(g, f, OP_loop);
    lget(g, index);
    lget(g, unroll_end);
    op(g, OP_i32_ge_u);
    br(g, f, OP_br_if, u_exit);

    lget(g, affine_loc);
    lset(g, base_s);

    for step in 0..8 {
        lget(g, base_s);
        i32Const(g, ak[step]);
        op(g, OP_i32_mul);
        if ck[step] != 0 {
            i32Const(g, ck[step]);
            op(g, OP_i32_add);
        }
        lset(g, s_cur);
        bindPut(g, f, carry_back[affine_carry], valOf1(g, squid_direct_types::u32_, s_cur));
        for si in 0..stmts_len {
            if si == affine_stmt { continue; }
            let _, serr = stmt(g, f, stmts[si]);
            if serr != squid_direct_types::Error.none { return serr; }
        }
        for ci in 0..carry_count {
            if ci == affine_carry { continue; }
            let bv, bok = bindGet(g, f, carry_back[ci]);
            assert(bok && bv.len == 1);
            lget(g, w(g, bv, 0));
            lset(g, w(g, g.s.vals[iteration.start + ci], 0));
            bindPut(g, f, carry_iter[ci], g.s.vals[iteration.start + ci]);
        }
    }
    lget(g, s_cur);
    lset(g, affine_loc);

    lget(g, index);
    i32Const(g, 8);
    op(g, OP_i32_add);
    lset(g, index);
    br(g, f, OP_br, u_top);
    close(g, f);
    close(g, f);

    return squid_direct_types::Error.none;
}
// 4A: Deferred NaN canonicalization check for pure-FP counted outer loops.
recursive fn tyHasF32(m: const Module&, tid: TId, depth: i64 = 0) -> bool {
    if tid == 0 || depth > 8 { return false; }
    let tn = m.types.node(tid);
    match tn.tag {
        floating32 => { return true; },
        array => { return tyHasF32(m, tn.a, depth + 1); },
        product => {
            for item in m.types.list(squid_check_types::List { tn.a, tn.b }) {
                if tyHasF32(m, item, depth + 1) { return true; }
            }
            return false;
        },
        record => {
            for idx in 0..(tn.b as i64) {
                if tyHasF32(m, m.types.recordField(tn, idx).ty, depth + 1) { return true; }
            }
            return false;
        },
        nominal => { return true; },
        _ => { return false; },
    }
}
recursive fn tyHasU32(m: const Module&, tid: TId, depth: i64) -> bool {
    if tid == 0 || depth > 16 { return true; }
    let tn = m.types.node(tid);
    match tn.tag {
        unsigned32 => { return true; },
        floating32, boolean, unit, never => { return false; },
        usage, forall => { return tyHasU32(m, tn.a, depth + 1); },
        array => { return tyHasU32(m, tn.a, depth + 1); },
        product => {
            for child in m.types.list(squid_check_types::List { tn.a, tn.b }) {
                if tyHasU32(m, child, depth + 1) { return true; }
            }
            return false;
        },
        record => {
            for fi in 0..(tn.b as i64) {
                if tyHasU32(m, m.types.recordField(tn, fi).ty, depth + 1) { return true; }
            }
            return false;
        },
        nominal => { return true; },
        _ => { return true; },
    }
}
struct DeferLoopContext {
    outer_carries: u32[16] = [0; 16],
    outer_carry_backs: u32[16] = [0; 16],
    outer_carries_len: i64 = 0,
    local_b: u32[64] = [0; 64],
    local_rhs: u32[64] = [0; 64],
    local_len: i64 = 0,
    inner_vars: u32[8] = [0; 8],
    inner_len: i64 = 0,
    mutates_u32: bool = false,
}
fn deferIsOuterCarry(ctx: const DeferLoopContext&, b: u32) -> bool {
    for i in 0..ctx.outer_carries_len { if ctx.outer_carries[i] == b { return true; } }
    return false;
}
fn deferIsOuterCarryBack(ctx: const DeferLoopContext&, b: u32) -> bool {
    for i in 0..ctx.outer_carries_len { if ctx.outer_carry_backs[i] == b && b != 0 { return true; } }
    return false;
}
fn deferIsInnerVar(ctx: const DeferLoopContext&, b: u32) -> bool {
    for i in 0..ctx.inner_len { if ctx.inner_vars[i] == b { return true; } }
    return false;
}
fn deferFindLocalRhs(ctx: const DeferLoopContext&, b: u32) -> u32, bool {
    for i in 0..ctx.local_len { if ctx.local_b[i] == b { return ctx.local_rhs[i], true; } }
    return 0, false;
}
fn deferIsOuterImmutableBinding(ctx: const DeferLoopContext&, b: u32) -> bool {
    if b == 0 { return true; }
    if deferIsOuterCarry(ctx, b) || deferIsInnerVar(ctx, b) { return false; }
    let _, is_loc = deferFindLocalRhs(ctx, b);
    return !is_loc;
}
recursive fn scanDeferLoopDefs(m: const Module&, id: u32, ctx: DeferLoopContext&, budget: i64&) -> bool {
    if id == 0 { return true; }
    if budget <= 0 { return false; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        constant, reference => { return true; },
        suite, block_, product, record, array_op, storage => {
            for ch in m.children(id) { if !scanDeferLoopDefs(m, ch, ctx, budget) { return false; } }
            return true;
        },
        bind => {
            if n.c >= 2 { return false; }
            if ctx.local_len >= 64 { return false; }
            ctx.local_b[ctx.local_len] = n.a;
            ctx.local_rhs[ctx.local_len] = n.b;
            ctx.local_len += 1;
            return scanDeferLoopDefs(m, n.b, ctx, budget);
        },
        construct => { return scanDeferLoopDefs(m, n.b, ctx, budget); },
        project, return_ => { return scanDeferLoopDefs(m, n.a, ctx, budget); },
        scalar, associated, apply => {
            return scanDeferLoopDefs(m, n.a, ctx, budget) && scanDeferLoopDefs(m, n.b, ctx, budget);
        },
        spark => {
            let sinfo = m.sparkInfo(id);
            return scanDeferLoopDefs(m, sinfo.source, ctx, budget) &&
                scanDeferLoopDefs(m, sinfo.end, ctx, budget) &&
                scanDeferLoopDefs(m, sinfo.body, ctx, budget);
        },
        update => {
            let uinfo = m.updateInfo(id);
            if tyHasU32(m, m.typeOf(uinfo.value), 0) { ctx.mutates_u32 = true; }
            if !scanDeferLoopDefs(m, uinfo.root, ctx, budget) || !scanDeferLoopDefs(m, uinfo.value, ctx, budget) { return false; }
            for sel in m.updateSelectors(id) {
                if sel.kind == squid_check_core::UpdateKind.index && !scanDeferLoopDefs(m, sel.index, ctx, budget) { return false; }
            }
            return true;
        },
        loop_ => {
            let linfo = m.loopInfo(id);
            if linfo.kind != squid_check_core::LoopKind.range || linfo.carries.len != 0 { return false; }
            if linfo.pattern != 0 {
                let pat = m.pattern(linfo.pattern);
                if pat.tag == squid_check_core::PatternTag.bind && pat.a != 0 {
                    if ctx.inner_len >= 8 { return false; }
                    ctx.inner_vars[ctx.inner_len] = pat.a;
                    ctx.inner_len += 1;
                } else if pat.tag != squid_check_core::PatternTag.wildcard {
                    return false;
                }
            }
            return scanDeferLoopDefs(m, linfo.first, ctx, budget) &&
                scanDeferLoopDefs(m, linfo.end, ctx, budget) &&
                scanDeferLoopDefs(m, linfo.body, ctx, budget);
        },
        match_ => {
            for inp in m.matchInputs(id) { if !scanDeferLoopDefs(m, inp, ctx, budget) { return false; } }
            for arm in m.matchArms(id) {
                if !scanDeferLoopDefs(m, arm.body, ctx, budget) { return false; }
            }
            return true;
        },
        call => {
            for arg in m.call(id).arguments { if !scanDeferLoopDefs(m, arg, ctx, budget) { return false; } }
            return true;
        },
        _ => { return false; },
    }
}
recursive fn isDeferInvariantIndex(m: const Module&, ctx: const DeferLoopContext&, id: u32, depth: i64) -> bool {
    if id == 0 || depth > 16 { return false; }
    let n = m.node(id);
    match n.tag {
        constant => { return true; },
        reference => {
            let b = localRef(m, id);
            if b == 0 { return true; }
            if deferIsInnerVar(ctx, b) { return true; }
            if deferIsOuterCarry(ctx, b) { return false; }
            let rhs, is_loc = deferFindLocalRhs(ctx, b);
            if is_loc { return isDeferInvariantIndex(m, ctx, rhs, depth + 1); }
            return true;
        },
        scalar, associated => {
            if n.tag == squid_check_core::Tag.associated && n.op == squid_check_core::Op.none { return false; }
            match n.op {
                add, sub, mul, div, rem, bit_and, bit_or, bit_xor, shift_left, shift_right => {},
                _ => { return false; },
            }
            if m.types.node(m.typeOf(id)).tag != squid_check_types::Tag.unsigned32 { return false; }
            if n.a != 0 && m.types.node(m.typeOf(n.a)).tag != squid_check_types::Tag.unsigned32 { return false; }
            if n.b != 0 && m.types.node(m.typeOf(n.b)).tag != squid_check_types::Tag.unsigned32 { return false; }
            return isDeferInvariantIndex(m, ctx, n.a, depth + 1) &&
                (n.b == 0 || isDeferInvariantIndex(m, ctx, n.b, depth + 1));
        },
        array_op => {
            let op_k = m.arrayOperation(id);
            let ch = m.children(id);
            if op_k == squid_backend_collection_ops::Op.length && ch.len == 1 {
                let b = localRef(m, ch[0]);
                return m.node(ch[0]).tag == squid_check_core::Tag.reference && deferIsOuterImmutableBinding(ctx, b);
            }
            if op_k == squid_backend_collection_ops::Op.get && ch.len == 2 && !ctx.mutates_u32 {
                let b = localRef(m, ch[0]);
                return m.node(ch[0]).tag == squid_check_core::Tag.reference &&
                    deferIsOuterImmutableBinding(ctx, b) &&
                    isDeferInvariantIndex(m, ctx, ch[1], depth + 1);
            }
            return false;
        },
        storage => {
            let op_k, ok = squid_check_storage_ops::opFromCode(n.c);
            if ok != squid_error::Error.none { return false; }
            let ch = m.children(id);
            if op_k == squid_check_storage_ops::Op.length && ch.len == 1 {
                let b = localRef(m, ch[0]);
                return m.node(ch[0]).tag == squid_check_core::Tag.reference && deferIsOuterImmutableBinding(ctx, b);
            }
            if op_k == squid_check_storage_ops::Op.read && ch.len == 2 && !ctx.mutates_u32 {
                let b = localRef(m, ch[0]);
                return m.node(ch[0]).tag == squid_check_core::Tag.reference &&
                    deferIsOuterImmutableBinding(ctx, b) &&
                    isDeferInvariantIndex(m, ctx, ch[1], depth + 1);
            }
            return false;
        },
        apply => {
            if !ctx.mutates_u32 && m.node(n.a).tag == squid_check_core::Tag.project {
                let sp = m.fieldSpelling(m.projection(m.node(n.a).b).field);
                if sp.present && sp.value == "at" {
                    let arr_node = m.node(n.a).a;
                    let b = localRef(m, arr_node);
                    return m.node(arr_node).tag == squid_check_core::Tag.reference &&
                        deferIsOuterImmutableBinding(ctx, b) &&
                        isDeferInvariantIndex(m, ctx, n.b, depth + 1);
                }
            }
            return false;
        },
        project => {
            let sp = m.fieldSpelling(m.projection(n.b).field);
            if sp.present && sp.value == "length" {
                let b = localRef(m, n.a);
                return m.node(n.a).tag == squid_check_core::Tag.reference && deferIsOuterImmutableBinding(ctx, b);
            }
            return !ctx.mutates_u32 && isDeferInvariantIndex(m, ctx, n.a, depth + 1);
        },
        _ => { return false; },
    }
}
recursive fn isDeferInvariantRead(m: const Module&, ctx: const DeferLoopContext&, id: u32, depth: i64) -> bool {
    if id == 0 || depth > 8 { return false; }
    let n = m.node(id);
    match n.tag {
        reference => {
            let b = localRef(m, id);
            if b == 0 { return true; }
            let rhs, is_loc = deferFindLocalRhs(ctx, b);
            if is_loc { return isDeferInvariantRead(m, ctx, rhs, depth + 1); }
            return deferIsOuterImmutableBinding(ctx, b);
        },
        array_op => {
            let ch = m.children(id);
            if m.arrayOperation(id) != squid_backend_collection_ops::Op.get || ch.len != 2 { return false; }
            let b = localRef(m, ch[0]);
            return m.node(ch[0]).tag == squid_check_core::Tag.reference &&
                (deferIsOuterImmutableBinding(ctx, b) || deferIsOuterCarry(ctx, b)) &&
                isDeferInvariantIndex(m, ctx, ch[1], 0);
        },
        storage => {
            let op_k, ok = squid_check_storage_ops::opFromCode(n.c);
            let ch = m.children(id);
            if ok != squid_error::Error.none || op_k != squid_check_storage_ops::Op.read || ch.len != 2 { return false; }
            let b = localRef(m, ch[0]);
            return m.node(ch[0]).tag == squid_check_core::Tag.reference &&
                (deferIsOuterImmutableBinding(ctx, b) || deferIsOuterCarry(ctx, b)) &&
                isDeferInvariantIndex(m, ctx, ch[1], 0);
        },
        apply => {
            if m.node(n.a).tag == squid_check_core::Tag.project {
                let sp = m.fieldSpelling(m.projection(m.node(n.a).b).field);
                if sp.present && sp.value == "at" {
                    let arr_node = m.node(n.a).a;
                    let b = localRef(m, arr_node);
                    return m.node(arr_node).tag == squid_check_core::Tag.reference &&
                        (deferIsOuterImmutableBinding(ctx, b) || deferIsOuterCarry(ctx, b)) &&
                        isDeferInvariantIndex(m, ctx, n.b, 0);
                }
            }
            return false;
        },
        _ => { return false; },
    }
}
recursive fn bodyValidDeferF32Nan(
    g: const Generator&,
    m: const Module&,
    ctx: const DeferLoopContext&,
    id: u32,
    required_ctor: u32,
    allow_carry_spark: bool,
    top_level: bool,
    has_f32_write: bool&,
    budget: i64&,
    inline_depth: i64,
) -> bool {
    if id == 0 { return true; }
    if budget <= 0 { return false; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        constant, reference => { return true; },
        suite, block_ => {
            for ch in m.children(id) {
                if !bodyValidDeferF32Nan(g, m, ctx, ch, required_ctor, false, top_level && n.tag == squid_check_core::Tag.suite, has_f32_write, budget, inline_depth) { return false; }
            }
            return true;
        },
        product, record => {
            for ch in m.children(id) {
                if !bodyValidDeferF32Nan(g, m, ctx, ch, required_ctor, false, false, has_f32_write, budget, inline_depth) { return false; }
            }
            return true;
        },
        bind => {
            if n.c >= 2 { return false; }
            let carry_spark_ok = top_level && required_ctor == 0xffffffff && deferIsOuterCarryBack(ctx, n.a);
            return bodyValidDeferF32Nan(g, m, ctx, n.b, required_ctor, carry_spark_ok, false, has_f32_write, budget, inline_depth);
        },
        construct => {
            return bodyValidDeferF32Nan(g, m, ctx, n.b, required_ctor, false, false, has_f32_write, budget, inline_depth);
        },
        project => {
            let sp = m.fieldSpelling(m.projection(n.b).field);
            if sp.present && sp.value == "to_bits" { return false; }
            return bodyValidDeferF32Nan(g, m, ctx, n.a, required_ctor, false, false, has_f32_write, budget, inline_depth);
        },
        scalar, associated => {
            if n.op == squid_check_core::Op.bits || n.op == squid_check_core::Op.from_bits { return false; }
            if n.tag == squid_check_core::Tag.associated && n.op == squid_check_core::Op.none { return false; }
            return bodyValidDeferF32Nan(g, m, ctx, n.a, required_ctor, false, false, has_f32_write, budget, inline_depth) &&
                bodyValidDeferF32Nan(g, m, ctx, n.b, required_ctor, false, false, has_f32_write, budget, inline_depth);
        },
        array_op => {
            let op_k = m.arrayOperation(id);
            if op_k != squid_backend_collection_ops::Op.length && op_k != squid_backend_collection_ops::Op.get { return false; }
            for ch in m.children(id) {
                if !bodyValidDeferF32Nan(g, m, ctx, ch, required_ctor, false, false, has_f32_write, budget, inline_depth) { return false; }
            }
            return true;
        },
        storage => {
            let op_k, ok = squid_check_storage_ops::opFromCode(n.c);
            if ok != squid_error::Error.none { return false; }
            if op_k != squid_check_storage_ops::Op.length && op_k != squid_check_storage_ops::Op.read { return false; }
            for ch in m.children(id) {
                if !bodyValidDeferF32Nan(g, m, ctx, ch, required_ctor, false, false, has_f32_write, budget, inline_depth) { return false; }
            }
            return true;
        },
        apply => {
            if m.node(n.a).tag == squid_check_core::Tag.project {
                let sp = m.fieldSpelling(m.projection(m.node(n.a).b).field);
                if sp.present && sp.value == "at" {
                    return bodyValidDeferF32Nan(g, m, ctx, m.node(n.a).a, 0xffffffff, false, false, has_f32_write, budget, inline_depth) &&
                        bodyValidDeferF32Nan(g, m, ctx, n.b, 0xffffffff, false, false, has_f32_write, budget, inline_depth);
                }
            }
            return false;
        },
        spark => {
            // Only allow `spark` when it directly replaces an outer loop carry
            // at the top level of the loop body over an iteration-invariant extent.
            if !allow_carry_spark { return false; }
            let sinfo = m.sparkInfo(id);
            if sinfo.is_range {
                if !isDeferInvariantIndex(m, ctx, sinfo.source, 0) || !isDeferInvariantIndex(m, ctx, sinfo.end, 0) {
                    return false;
                }
            } else {
                let sb = localRef(m, sinfo.source);
                if m.node(sinfo.source).tag != squid_check_core::Tag.reference ||
                    !(deferIsOuterImmutableBinding(ctx, sb) || deferIsOuterCarry(ctx, sb)) {
                    return false;
                }
            }
            let res_tn = m.types.node(m.typeOf(id));
            if res_tn.tag == squid_check_types::Tag.array && m.types.node(res_tn.a).tag == squid_check_types::Tag.floating32 {
                has_f32_write = true;
            }
            return bodyValidDeferF32Nan(g, m, ctx, sinfo.source, 0xffffffff, false, false, has_f32_write, budget, inline_depth) &&
                bodyValidDeferF32Nan(g, m, ctx, sinfo.end, 0xffffffff, false, false, has_f32_write, budget, inline_depth) &&
                bodyValidDeferF32Nan(g, m, ctx, sinfo.body, 0xffffffff, false, false, has_f32_write, budget, inline_depth);
        },
        update => {
            let uinfo = m.updateInfo(id);
            let sels = m.updateSelectors(id);
            if sels.len == 0 || sels[0].kind != squid_check_core::UpdateKind.index { return false; }
            // Root must be an outer-scope binding or outer loop carry (never a loop-local array).
            let root_b = localRef(m, uinfo.root);
            if m.node(uinfo.root).tag != squid_check_core::Tag.reference ||
                !(deferIsOuterImmutableBinding(ctx, root_b) || deferIsOuterCarry(ctx, root_b)) {
                return false;
            }
            if required_ctor != 0xffffffff {
                // Inside a variant-tag match arm, writes to a multi-constructor element
                // must construct the exact same nominal+constructor tag so the set of updated slots
                // is strictly monotone across every iteration.
                let vn = m.node(uinfo.value);
                if vn.tag != squid_check_core::Tag.construct { return false; }
                let rc = m.constructor(required_ctor);
                let vc = m.constructor(vn.a);
                if vc.nominal != rc.nominal || vc.tag != rc.tag { return false; }
            }
            if tyHasF32(m, m.typeOf(uinfo.value)) { has_f32_write = true; }
            if !bodyValidDeferF32Nan(g, m, ctx, uinfo.root, required_ctor, false, false, has_f32_write, budget, inline_depth) ||
                !bodyValidDeferF32Nan(g, m, ctx, uinfo.value, required_ctor, false, false, has_f32_write, budget, inline_depth) { return false; }
            for sel in sels {
                if sel.kind == squid_check_core::UpdateKind.index {
                    if !isDeferInvariantIndex(m, ctx, sel.index, 0) { return false; }
                    if !bodyValidDeferF32Nan(g, m, ctx, sel.index, 0xffffffff, false, false, has_f32_write, budget, inline_depth) { return false; }
                }
            }
            return true;
        },
        loop_ => {
            let linfo = m.loopInfo(id);
            if linfo.kind != squid_check_core::LoopKind.range || linfo.carries.len != 0 { return false; }
            if !isDeferInvariantIndex(m, ctx, linfo.first, 0) || !isDeferInvariantIndex(m, ctx, linfo.end, 0) { return false; }
            return bodyValidDeferF32Nan(g, m, ctx, linfo.first, 0xffffffff, false, false, has_f32_write, budget, inline_depth) &&
                bodyValidDeferF32Nan(g, m, ctx, linfo.end, 0xffffffff, false, false, has_f32_write, budget, inline_depth) &&
                bodyValidDeferF32Nan(g, m, ctx, linfo.body, required_ctor, false, false, has_f32_write, budget, inline_depth);
        },
        match_ => {
            let inputs = m.matchInputs(id);
            if inputs.len != 1 { return false; }
            if !isDeferInvariantRead(m, ctx, inputs[0], 0) { return false; }
            if !bodyValidDeferF32Nan(g, m, ctx, inputs[0], 0xffffffff, false, false, has_f32_write, budget, inline_depth) { return false; }
            let arms = m.matchArms(id);
            var ctor_arms: i64 = 0;
            for arm in arms {
                if arm.guard_ != 0 { return false; }
                let rows = m.armRows(arm);
                if rows.len != 1 { return false; }
                let pats = m.rowPatterns(rows[0]);
                if pats.len != 1 { return false; }
                let pat = m.pattern(pats[0]);
                if pat.tag == squid_check_core::PatternTag.wildcard {
                    // Wildcard arm must be a no-op (absent, unit constant, or empty suite/block) so nothing diverges.
                    if arm.body != 0 {
                        let bn = m.node(arm.body);
                        if bn.tag != squid_check_core::Tag.constant &&
                            !((bn.tag == squid_check_core::Tag.suite || bn.tag == squid_check_core::Tag.block_) && bn.b == 0) {
                            return false;
                        }
                    }
                } else if pat.tag == squid_check_core::PatternTag.constructor {
                    ctor_arms += 1;
                    if ctor_arms > 1 { return false; }
                    var arm_req = required_ctor;
                    if arm_req == 0xffffffff {
                        arm_req = pat.a;
                    } else {
                        let rc = m.constructor(arm_req);
                        let pc = m.constructor(pat.a);
                        if pc.nominal != rc.nominal || pc.tag != rc.tag { return false; }
                    }
                    if !bodyValidDeferF32Nan(g, m, ctx, arm.body, arm_req, false, false, has_f32_write, budget, inline_depth) { return false; }
                } else {
                    return false;
                }
            }
            return true;
        },
        call => {
            let cinfo = m.call(id);
            for arg in cinfo.arguments {
                if !bodyValidDeferF32Nan(g, m, ctx, arg, 0xffffffff, false, false, has_f32_write, budget, inline_depth) { return false; }
            }
            if scratchScalarCallee(g, m, cinfo) { return true; }
            if inline_depth >= 1 { return false; }
            let target = g.resolve(m, cinfo.target);
            if !g.hasUnit(target.unit) { return false; }
            let tm .= g.units[target.unit - 1];
            let tbody .= tm.body(target.binding);
            if !tbody || !tbody.is_function || tbody.exported || tbody.scheme.obligations.len != 0 { return false; }
            var ibudget: i64 = 48;
            if !canInlineBody(g, tm, tbody.root, target, ibudget) { return false; }
            let ret_expr = scratchReturned(tm, tbody.root);
            var inline_ctx = DeferLoopContext {};
            return bodyValidDeferF32Nan(g, tm, inline_ctx, ret_expr, 0xffffffff, false, false, has_f32_write, budget, inline_depth + 1);
        },
        return_ => {
            if inline_depth == 0 { return false; }
            return bodyValidDeferF32Nan(g, m, ctx, n.a, 0xffffffff, false, false, has_f32_write, budget, inline_depth);
        },
        _ => { return false; },
    }
}
fn isCanonicalFloatRhs(m: const Module&, id: u32) -> bool {
    if id == 0 { return false; }
    let n = m.node(id);
    if n.tag != squid_check_core::Tag.scalar && n.tag != squid_check_core::Tag.associated { return false; }
    if n.op == squid_check_core::Op.none || !isCanonicalF32Op(n.op) { return false; }
    let t = m.types.node(m.typeOf(n.a)).tag;
    return t == squid_check_types::Tag.floating32 || t == squid_check_types::Tag.floating64;
}
recursive fn scanScalarFloatDeferBody(
    g: const Generator&,
    m: const Module&,
    id: u32,
    top_level: bool,
    carry_backs: const u32[48]&,
    carry_seen: bool[48]&,
    carry_len: i64,
    budget: i64&,
) -> bool {
    if id == 0 { return true; }
    if budget <= 0 { return false; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        constant, reference => { return true; },
        suite, block_ => {
            for child in m.children(id) {
                if !scanScalarFloatDeferBody(g, m, child, top_level, carry_backs, carry_seen, carry_len, budget) { return false; }
            }
            return true;
        },
        bind => {
            if n.c >= 2 { return false; }
            if !scanScalarFloatDeferBody(g, m, n.b, false, carry_backs, carry_seen, carry_len, budget) { return false; }
            if top_level {
                for ci in 0..carry_len {
                    if carry_backs[ci] == n.a {
                        if !isCanonicalFloatRhs(m, n.b) { return false; }
                        carry_seen[ci] = true;
                    }
                }
            }
            return true;
        },
        pattern_bind => {
            if n.c != 0 { return false; }
            return scanScalarFloatDeferBody(g, m, n.b, false, carry_backs, carry_seen, carry_len, budget);
        },
        product => {
            for child in m.children(id) {
                if !scanScalarFloatDeferBody(g, m, child, false, carry_backs, carry_seen, carry_len, budget) { return false; }
            }
            return true;
        },
        scalar => {
            let t = m.types.node(m.typeOf(n.a)).tag;
            let is_f = t == squid_check_types::Tag.floating32 || t == squid_check_types::Tag.floating64;
            let is_v = isF32x4CoreExpr(m, n.a) || isF64x2CoreExpr(m, n.a);
            let ok = (is_f && isCanonicalF32Consumer(n.op)) || (is_v && (isCanonicalF32Consumer(n.op) || canonicalV128Producer(n.op)));
            if !ok { return false; }
            return scanScalarFloatDeferBody(g, m, n.a, false, carry_backs, carry_seen, carry_len, budget) &&
                (n.b == 0 || scanScalarFloatDeferBody(g, m, n.b, false, carry_backs, carry_seen, carry_len, budget));
        },
        associated => {
            let t = m.types.node(m.typeOf(n.a)).tag;
            let is_f = t == squid_check_types::Tag.floating32 || t == squid_check_types::Tag.floating64;
            if n.op == squid_check_core::Op.none || !is_f || !isCanonicalF32Consumer(n.op) { return false; }
            return scanScalarFloatDeferBody(g, m, n.a, false, carry_backs, carry_seen, carry_len, budget) &&
                (n.b == 0 || scanScalarFloatDeferBody(g, m, n.b, false, carry_backs, carry_seen, carry_len, budget));
        },
        call => {
            if !callIsCanonicalFloatConsumer(g, m, id, true) { return false; }
            for arg in m.call(id).arguments {
                if !scanScalarFloatDeferBody(g, m, arg, false, carry_backs, carry_seen, carry_len, budget) { return false; }
            }
            return true;
        },
        _ => { return false; },
    }
}
fn canDeferScalarFloatLoop(g: const Generator&, f: const Fn&, m: const Module&, loop_id: u32, info: squid_check_core::LoopInfo) -> bool {
    if info.kind != squid_check_core::LoopKind.range || info.body == 0 { return false; }
    if info.pattern != 0 && m.pattern(info.pattern).tag != squid_check_core::PatternTag.wildcard { return false; }
    let carries = m.loopCarries(loop_id);
    if carries.len == 0 || carries.len > 48 { return false; }
    var carry_backs: u32[48] = [0; 48];
    var carry_seen: bool[48] = [false; 48];
    for carry, ci in carries {
        let cv, cok = bindGet(g, f, carry.iteration);
        if !cok { return false; }
        let tag = tagOf(g, cv.ty);
        if tag != squid_direct_types::Tag.f32_ && tag != squid_direct_types::Tag.f64_ { return false; }
        carry_backs[ci] = carry.backedge;
    }
    var budget: i64 = 2048;
    if !scanScalarFloatDeferBody(g, m, info.body, true, carry_backs, carry_seen, carries.len, budget) { return false; }
    for ci in 0..carries.len {
        if !carry_seen[ci] { return false; }
    }
    return true;
}
fn canDeferLoopF32Nan(g: const Generator&, f: const Fn&, m: const Module&, loop_id: u32, info: squid_check_core::LoopInfo) -> bool {
    if canDeferScalarFloatLoop(g, f, m, loop_id, info) { return true; }
    if info.kind != squid_check_core::LoopKind.range || info.body == 0 { return false; }
    if info.pattern != 0 && m.pattern(info.pattern).tag != squid_check_core::PatternTag.wildcard { return false; }
    let carries = m.loopCarries(loop_id);
    if carries.len > 16 { return false; }
    var ctx = DeferLoopContext {};
    for carry, ci in carries {
        let cv, cok = bindGet(g, f, carry.iteration);
        if !cok || tagOf(g, cv.ty) != squid_direct_types::Tag.array { return false; }
        ctx.outer_carries[ci] = carry.iteration;
        ctx.outer_carry_backs[ci] = carry.backedge;
        ctx.outer_carries_len += 1;
    }
    var scan_budget: i64 = 160;
    if !scanDeferLoopDefs(m, info.body, ctx, scan_budget) { return false; }
    var has_f32_write = false;
    var budget: i64 = 160;
    if !bodyValidDeferF32Nan(g, m, ctx, info.body, 0xffffffff, false, true, has_f32_write, budget, 0) { return false; }
    return has_f32_write;
}

// 4B-2: Pre-loop `CheckedLe` bounds hoisting helpers.
recursive fn countLoopBodyNodes(m: const Module&, id: u32, count: i64&, limit: i64) -> bool {
    if id == 0 { return true; }
    count += 1;
    if count > limit { return false; }
    let n = m.node(id);
    match n.tag {
        suite, block_, product, record, array, array_op, storage => {
            for ch in m.children(id) { if !countLoopBodyNodes(m, ch, count, limit) { return false; } }
            return true;
        },
        bind, construct => { return countLoopBodyNodes(m, n.b, count, limit); },
        return_, project, result_associated => { return countLoopBodyNodes(m, n.a, count, limit); },
        scalar, associated, logical, apply => {
            return countLoopBodyNodes(m, n.a, count, limit) && countLoopBodyNodes(m, n.b, count, limit);
        },
        if_value, if_stmt => {
            return countLoopBodyNodes(m, n.a, count, limit) && countLoopBodyNodes(m, n.b, count, limit) && countLoopBodyNodes(m, n.c, count, limit);
        },
        match_ => {
            for inp in m.matchInputs(id) { if !countLoopBodyNodes(m, inp, count, limit) { return false; } }
            for arm in m.matchArms(id) {
                if !countLoopBodyNodes(m, arm.guard_, count, limit) || !countLoopBodyNodes(m, arm.body, count, limit) { return false; }
            }
            return true;
        },
        update => {
            let uinfo = m.updateInfo(id);
            if !countLoopBodyNodes(m, uinfo.root, count, limit) || !countLoopBodyNodes(m, uinfo.value, count, limit) { return false; }
            for sel in m.updateSelectors(id) {
                if sel.kind == squid_check_core::UpdateKind.index && !countLoopBodyNodes(m, sel.index, count, limit) { return false; }
            }
            return true;
        },
        call => {
            for arg in m.call(id).arguments { if !countLoopBodyNodes(m, arg, count, limit) { return false; } }
            return true;
        },
        loop_, spark => { return false; },
        _ => { return true; },
    }
}
recursive fn collectIndexedByVar(m: const Module&, id: u32, idx_b: u32, out: u32[8]&, len: i64&, left: i64&) {
    if id == 0 || left <= 0 || len >= 8 { return; }
    left -= 1;
    let n = m.node(id);
    match n.tag {
        array_op => {
            let ch = m.children(id);
            if m.arrayOperation(id) == squid_backend_collection_ops::Op.get && ch.len == 2 && localRef(m, ch[1]) == idx_b {
                addHoistCandidate(out, len, localRef(m, ch[0]));
            }
            for child in ch { collectIndexedByVar(m, child, idx_b, out, len, left); }
        },
        storage => {
            let ch = m.children(id);
            let op_k, ok = squid_check_storage_ops::opFromCode(n.c);
            if ok == squid_error::Error.none && op_k == squid_check_storage_ops::Op.read && ch.len == 2 && localRef(m, ch[1]) == idx_b {
                addHoistCandidate(out, len, localRef(m, ch[0]));
            }
            for child in ch { collectIndexedByVar(m, child, idx_b, out, len, left); }
        },
        apply => {
            if m.node(n.a).tag == squid_check_core::Tag.project {
                let sp = m.fieldSpelling(m.projection(m.node(n.a).b).field);
                if sp.present && sp.value == "at" && localRef(m, n.b) == idx_b {
                    addHoistCandidate(out, len, localRef(m, m.node(n.a).a));
                }
            }
            collectIndexedByVar(m, n.a, idx_b, out, len, left);
            collectIndexedByVar(m, n.b, idx_b, out, len, left);
        },
        update => {
            let uinfo = m.updateInfo(id);
            let sels = m.updateSelectors(id);
            if sels.len > 0 && sels[0].kind == squid_check_core::UpdateKind.index && localRef(m, sels[0].index) == idx_b {
                addHoistCandidate(out, len, localRef(m, uinfo.root));
            }
            collectIndexedByVar(m, uinfo.root, idx_b, out, len, left);
            collectIndexedByVar(m, uinfo.value, idx_b, out, len, left);
            for sel in sels {
                if sel.kind == squid_check_core::UpdateKind.index { collectIndexedByVar(m, sel.index, idx_b, out, len, left); }
            }
        },
        suite, block_, product, record, array => {
            for ch in m.children(id) { collectIndexedByVar(m, ch, idx_b, out, len, left); }
        },
        bind, construct => { collectIndexedByVar(m, n.b, idx_b, out, len, left); },
        return_, project, result_associated => { collectIndexedByVar(m, n.a, idx_b, out, len, left); },
        scalar, associated, logical => {
            collectIndexedByVar(m, n.a, idx_b, out, len, left);
            collectIndexedByVar(m, n.b, idx_b, out, len, left);
        },
        if_value, if_stmt => {
            collectIndexedByVar(m, n.a, idx_b, out, len, left);
            collectIndexedByVar(m, n.b, idx_b, out, len, left);
            collectIndexedByVar(m, n.c, idx_b, out, len, left);
        },
        match_ => {
            for inp in m.matchInputs(id) { collectIndexedByVar(m, inp, idx_b, out, len, left); }
            for arm in m.matchArms(id) {
                collectIndexedByVar(m, arm.guard_, idx_b, out, len, left);
                collectIndexedByVar(m, arm.body, idx_b, out, len, left);
            }
        },
        call => {
            for arg in m.call(id).arguments { collectIndexedByVar(m, arg, idx_b, out, len, left); }
        },
        _ => {},
    }
}
fn addLePair(le_a: u32[4]&, le_b: u32[4]&, count: i64&, a: u32, b: u32) {
    if a == b || count >= 4 { return; }
    for i in 0..count { if le_a[i] == a && le_b[i] == b { return; } }
    le_a[count] = a;
    le_b[count] = b;
    count += 1;
}
fn isBreakBody(m: const Module&, id: u32) -> bool {
    var cur = id;
    for step in 0..4 {
        let n = m.node(cur);
        if n.tag == squid_check_core::Tag.break_ { return true; }
        if (n.tag == squid_check_core::Tag.suite || n.tag == squid_check_core::Tag.block_) && n.b == 1 {
            cur = m.children(cur)[0];
        } else { break; }
    }
    return false;
}
recursive fn extractOrExitUpperBounds(
    g: const Generator&,
    f: const Fn&,
    m: const Module&,
    loop_id: u32,
    cond_id: u32,
    idx_out: u32[4]&,
    lim_out: u32[4]&,
    out_len: i64&,
    depth: i64,
) {
    if cond_id == 0 || depth > 4 || out_len >= 4 { return; }
    let cn = m.node(cond_id);
    if cn.tag == squid_check_core::Tag.logical && cn.op == squid_check_core::Op.or_ {
        extractOrExitUpperBounds(g, f, m, loop_id, cn.a, idx_out, lim_out, out_len, depth + 1);
        extractOrExitUpperBounds(g, f, m, loop_id, cn.b, idx_out, lim_out, out_len, depth + 1);
        return;
    }
    if cn.tag == squid_check_core::Tag.scalar || (cn.tag == squid_check_core::Tag.associated && cn.op != squid_check_core::Op.none) {
        var ib: u32 = 0;
        var lb: u32 = 0;
        if cn.op == squid_check_core::Op.greater_equal {
            ib = localRef(m, cn.a);
            lb = localRef(m, cn.b);
        } else if cn.op == squid_check_core::Op.less_equal {
            ib = localRef(m, cn.b);
            lb = localRef(m, cn.a);
        }
        if ib == 0 || lb == 0 { return; }
        // `lb` must be loop-invariant (not a carry of this loop) and already bound as U32.
        for carry in m.loopCarries(loop_id) {
            if carry.iteration == lb || carry.backedge == lb { return; }
        }
        let lv, lok = bindGet(g, f, lb);
        if !lok || tagOf(g, lv.ty) != squid_direct_types::Tag.u32_ { return; }
        idx_out[out_len] = ib;
        lim_out[out_len] = w(g, lv, 0);
        out_len += 1;
    }
}
recursive fn matchAffineIndexExpr(g: const Generator&, f: const Fn&, m: const Module&, idx_node: u32, idx_b: u32) -> bool, u32, u32 {
    if idx_node == 0 { return false, 0xffffffff, 0; }
    let n = m.node(idx_node);
    if n.tag != squid_check_core::Tag.scalar || n.op != squid_check_core::Op.add ||
        m.types.node(m.typeOf(idx_node)).tag != squid_check_types::Tag.unsigned32 {
        return false, 0xffffffff, 0;
    }
    // Check `idx + c` or `c + idx` (1 <= c <= 4)
    let an = m.node(n.a);
    let bn = m.node(n.b);
    if bn.tag == squid_check_core::Tag.constant && bn.a >= 1 && bn.a <= 4 {
        if localRef(m, n.a) == idx_b { return true, 0xffffffff, bn.a; }
        // `(base + idx) + c`
        let ok2, base2, c2 = matchAffineIndexExpr(g, f, m, n.a, idx_b);
        if ok2 && c2 + bn.a <= 4 { return true, base2, c2 + bn.a; }
    }
    if an.tag == squid_check_core::Tag.constant && an.a >= 1 && an.a <= 4 {
        if localRef(m, n.b) == idx_b { return true, 0xffffffff, an.a; }
        let ok2, base2, c2 = matchAffineIndexExpr(g, f, m, n.b, idx_b);
        if ok2 && c2 + an.a <= 4 { return true, base2, c2 + an.a; }
    }
    // Check `base + idx` or `idx + base` where `base` is an already-bound U32 local
    var base_b: u32 = 0;
    if localRef(m, n.b) == idx_b { base_b = localRef(m, n.a); }
    else if localRef(m, n.a) == idx_b { base_b = localRef(m, n.b); }
    if base_b != 0 && base_b != idx_b {
        let _, ic = withCellType(g, f, base_b);
        let bv, bok = bindGet(g, f, base_b);
        if !ic && bok && bv.ty == squid_direct_types::u32_ {
            return true, w(g, bv, 0), 0;
        }
    }
    return false, 0xffffffff, 0;
}

fn matchMaskLocal(g: const Generator&, f: const Fn&, m: const Module&, idx_node: u32) -> u32 {
    if idx_node == 0 { return 0xffffffff; }
    let n = m.node(idx_node);
    if (n.tag == squid_check_core::Tag.scalar || (n.tag == squid_check_core::Tag.associated && n.op != squid_check_core::Op.none)) &&
        n.op == squid_check_core::Op.bit_and &&
        m.types.node(m.typeOf(idx_node)).tag == squid_check_types::Tag.unsigned32 {
        let rb = localRef(m, n.b);
        if rb != 0 {
            let _, ic = withCellType(g, f, rb);
            let rv, rok = bindGet(g, f, rb);
            if !ic && rok && rv.ty == squid_direct_types::u32_ { return w(g, rv, 0); }
        }
        let lb = localRef(m, n.a);
        if lb != 0 {
            let _, ic = withCellType(g, f, lb);
            let lv, lok = bindGet(g, f, lb);
            if !ic && lok && lv.ty == squid_direct_types::u32_ { return w(g, lv, 0); }
        }
    }
    let ib = localRef(m, idx_node);
    if ib != 0 {
        let iv, iok = bindGet(g, f, ib);
        if iok && iv.len == 1 && iv.ty == squid_direct_types::u32_ {
            let cm = findCheckedMask(f, w(g, iv, 0));
            if cm >= 0 && f.checked_masks[cm].max_local != 0xffffffff {
                return f.checked_masks[cm].max_local;
            }
        }
    }
    return 0xffffffff;
}

// True when `expr_id` in `m` is `(...) & mask` where `mask` resolves to `mask_loc`.
fn exprMaskedByLocal(g: const Generator&, f: const Fn&, m: const Module&, expr_id: u32, mask_loc: u32) -> bool {
    if expr_id == 0 { return false; }
    let n = m.node(expr_id);
    if (n.tag == squid_check_core::Tag.scalar || (n.tag == squid_check_core::Tag.associated && n.op != squid_check_core::Op.none)) &&
        n.op == squid_check_core::Op.bit_and &&
        m.types.node(m.typeOf(expr_id)).tag == squid_check_types::Tag.unsigned32 {
        let rb = localRef(m, n.b);
        if rb != 0 {
            let rv, rok = bindGet(g, f, rb);
            if rok && rv.len == 1 && rv.ty == squid_direct_types::u32_ && w(g, rv, 0) == mask_loc { return true; }
        }
        let lb = localRef(m, n.a);
        if lb != 0 {
            let lv, lok = bindGet(g, f, lb);
            if lok && lv.len == 1 && lv.ty == squid_direct_types::u32_ && w(g, lv, 0) == mask_loc { return true; }
        }
    }
    return false;
}

// Finds the defining RHS or branch merge of `target_b` inside `id`, verifying that
// every reaching definition of `target_b` is either in `ok_bs` or masked by `mask_loc`.
recursive fn scanBindingMaskProof(
    g: const Generator&,
    f: const Fn&,
    m: const Module&,
    body_root: u32,
    id: u32,
    target_b: u32,
    mask_loc: u32,
    ok_bs: const u32[8]&,
    ok_len: i64,
    found: bool&,
    valid: bool&,
    depth: i64,
) {
    if id == 0 || !valid || depth > 16 { return; }
    let n = m.node(id);
    match n.tag {
        suite, block_ => {
            for ch in m.children(id) {
                scanBindingMaskProof(g, f, m, body_root, ch, target_b, mask_loc, ok_bs, ok_len, found, valid, depth + 1);
            }
        },
        bind => {
            if n.a == target_b {
                found = true;
                if n.c >= 2 { valid = false; return; }
                if exprMaskedByLocal(g, f, m, n.b, mask_loc) { return; }
                let rb = localRef(m, n.b);
                if rb != 0 {
                    for oi in 0..ok_len { if ok_bs[oi] == rb { return; } }
                    let rv, rok = bindGet(g, f, rb);
                    if rok && rv.len == 1 && rv.ty == squid_direct_types::u32_ {
                        let cm = findCheckedMask(f, w(g, rv, 0));
                        if cm >= 0 && f.checked_masks[cm].max_local == mask_loc { return; }
                    }
                }
                valid = false;
                return;
            }
            scanBindingMaskProof(g, f, m, body_root, n.b, target_b, mask_loc, ok_bs, ok_len, found, valid, depth + 1);
        },
        if_stmt, if_value => {
            for merge in m.branchMerges(id) {
                if merge.result == target_b {
                    found = true;
                    var tb_ok = false;
                    var eb_ok = false;
                    for oi in 0..ok_len {
                        if ok_bs[oi] == merge.then_binding { tb_ok = true; }
                        if ok_bs[oi] == merge.else_binding { eb_ok = true; }
                    }
                    if !tb_ok {
                        var f2 = false; var v2 = true;
                        scanBindingMaskProof(g, f, m, body_root, body_root, merge.then_binding, mask_loc, ok_bs, ok_len, f2, v2, depth + 1);
                        tb_ok = f2 && v2;
                    }
                    if !eb_ok {
                        var f3 = false; var v3 = true;
                        scanBindingMaskProof(g, f, m, body_root, body_root, merge.else_binding, mask_loc, ok_bs, ok_len, f3, v3, depth + 1);
                        eb_ok = f3 && v3;
                    }
                    if !tb_ok || !eb_ok { valid = false; }
                    return;
                }
            }
            scanBindingMaskProof(g, f, m, body_root, n.b, target_b, mask_loc, ok_bs, ok_len, found, valid, depth + 1);
            scanBindingMaskProof(g, f, m, body_root, n.c, target_b, mask_loc, ok_bs, ok_len, found, valid, depth + 1);
        },
        match_ => {
            for merge in m.branchMerges(id) {
                if merge.result == target_b { valid = false; found = true; return; }
            }
            for arm in m.matchArms(id) {
                scanBindingMaskProof(g, f, m, body_root, arm.body, target_b, mask_loc, ok_bs, ok_len, found, valid, depth + 1);
            }
        },
        _ => {},
    }
}

fn matchVarMinusConstOne(m: const Module&, expr_id: u32, var_b: u32) -> bool {
    let n = m.node(expr_id);
    if (n.tag != squid_check_core::Tag.scalar && !(n.tag == squid_check_core::Tag.associated && n.op != squid_check_core::Op.none)) ||
        n.op != squid_check_core::Op.sub { return false; }
    return localRef(m, n.a) == var_b && m.node(n.b).tag == squid_check_core::Tag.constant && m.node(n.b).a == 1;
}

recursive fn findSingleBindRhs(m: const Module&, id: u32, target_b: u32, depth: i64) -> u32 {
    if id == 0 || depth > 12 { return 0; }
    let n = m.node(id);
    match n.tag {
        suite, block_ => {
            for ch in m.children(id) {
                let r = findSingleBindRhs(m, ch, target_b, depth + 1);
                if r != 0 { return r; }
            }
            return 0;
        },
        bind => {
            if n.a == target_b && n.c < 2 { return n.b; }
            return findSingleBindRhs(m, n.b, target_b, depth + 1);
        },
        _ => { return 0; },
    }
}

// True when `arr_b` is unconditionally indexed at the entry of `body_id` before any
// `if`, `break`, `return`, or loop (e.g. `let s = slots[idx]` or `j := ...; let s = slots[j]`).
fn loopUnconditionallyIndexesArr(m: const Module&, body_id: u32, arr_b: u32) -> bool {
    let bn = m.node(body_id);
    if bn.tag != squid_check_core::Tag.suite && bn.tag != squid_check_core::Tag.block_ { return false; }
    let ch = m.children(body_id);
    let limit = if ch.len < 3 { ch.len } else { 3 };
    for i in 0..limit {
        let sn = m.node(ch[i]);
        if sn.tag == squid_check_core::Tag.bind && sn.c < 2 {
            let rn = m.node(sn.b);
            if rn.tag == squid_check_core::Tag.array_op && m.arrayOperation(sn.b) == squid_backend_collection_ops::Op.get {
                let ach = m.children(sn.b);
                if ach.len == 2 && localRef(m, ach[0]) == arr_b { return true; }
            } else if rn.tag == squid_check_core::Tag.storage {
                let op_k, ok = squid_check_storage_ops::opFromCode(rn.c);
                let ach = m.children(sn.b);
                if ok == squid_error::Error.none && op_k == squid_check_storage_ops::Op.read && ach.len == 2 && localRef(m, ach[0]) == arr_b { return true; }
            } else if rn.tag == squid_check_core::Tag.scalar || (rn.tag == squid_check_core::Tag.associated && rn.op != squid_check_core::Op.none) ||
                rn.tag == squid_check_core::Tag.constant || rn.tag == squid_check_core::Tag.reference {
                continue;
            } else {
                return false;
            }
        } else if sn.tag == squid_check_core::Tag.pattern_bind {
            let rn = m.node(sn.b);
            if rn.tag == squid_check_core::Tag.array_op && m.arrayOperation(sn.b) == squid_backend_collection_ops::Op.get {
                let ach = m.children(sn.b);
                if ach.len == 2 && localRef(m, ach[0]) == arr_b { return true; }
            } else if rn.tag == squid_check_core::Tag.storage {
                let op_k, ok = squid_check_storage_ops::opFromCode(rn.c);
                let ach = m.children(sn.b);
                if ok == squid_error::Error.none && op_k == squid_check_storage_ops::Op.read && ach.len == 2 && localRef(m, ach[0]) == arr_b { return true; }
            }
            return false;
        } else {
            return false;
        }
    }
    return false;
}

fn addAffineTriplet(
    aff_base: u32[4]&,
    aff_c: u32[4]&,
    aff_len: u32[4]&,
    aff_count: i64&,
    base: u32,
    c: u32,
    clen: u32,
) {
    for i in 0..aff_count {
        if aff_base[i] == base && aff_len[i] == clen {
            if c > aff_c[i] { aff_c[i] = c; }
            return;
        }
    }
    if aff_count >= 4 { return; }
    aff_base[aff_count] = base;
    aff_c[aff_count] = c;
    aff_len[aff_count] = clen;
    aff_count += 1;
}

recursive fn collectAffineAndMaskBounds(
    g: const Generator&,
    f: const Fn&,
    m: const Module&,
    id: u32,
    idx_b: u32,
    end_local: u32,
    lt_a: u32[4]&,
    lt_b: u32[4]&,
    lt_count: i64&,
    aff_base: u32[4]&,
    aff_c: u32[4]&,
    aff_len: u32[4]&,
    aff_count: i64&,
    left: i64&,
) {
    if id == 0 || left <= 0 { return; }
    left -= 1;
    let n = m.node(id);
    var arr_b: u32 = 0;
    var idx_n: u32 = 0;
    if n.tag == squid_check_core::Tag.array_op && m.arrayOperation(id) == squid_backend_collection_ops::Op.get {
        let ch = m.children(id);
        if ch.len == 2 { arr_b = localRef(m, ch[0]); idx_n = ch[1]; }
    } else if n.tag == squid_check_core::Tag.storage {
        let op_k, ok = squid_check_storage_ops::opFromCode(n.c);
        if ok == squid_error::Error.none && op_k == squid_check_storage_ops::Op.read {
            let ch = m.children(id);
            if ch.len == 2 { arr_b = localRef(m, ch[0]); idx_n = ch[1]; }
        }
    } else if n.tag == squid_check_core::Tag.update {
        let uinfo = m.updateInfo(id);
        let sels = m.updateSelectors(id);
        if sels.len > 0 && sels[0].kind == squid_check_core::UpdateKind.index {
            arr_b = localRef(m, uinfo.root);
            idx_n = sels[0].index;
        }
    }
    if arr_b != 0 && idx_n != 0 {
        let av, aok = bindGet(g, f, arr_b);
        if aok && tagOf(g, av.ty) == squid_direct_types::Tag.array {
            let ca = findCheckedArray(f, w(g, av, 0), w(g, av, 1));
            if ca >= 0 {
                let clen = f.checked_arrays[ca].length;
                if idx_b != 0 && end_local != 0xffffffff {
                    let is_aff, base_loc, c_val = matchAffineIndexExpr(g, f, m, idx_n, idx_b);
                    if is_aff {
                        if base_loc == 0xffffffff && c_val == 1 {
                            if findCheckedBound(f, end_local, clen) < 0 {
                                addLePair(lt_a, lt_b, lt_count, end_local, clen);
                            }
                        } else if findCheckedAffine(f, base_loc, end_local, c_val, clen) < 0 {
                            addAffineTriplet(aff_base, aff_c, aff_len, aff_count, base_loc, c_val, clen);
                        }
                    }
                }
                let mask_loc = matchMaskLocal(g, f, m, idx_n);
                if mask_loc != 0xffffffff && findCheckedBound(f, mask_loc, clen) < 0 {
                    addLePair(lt_a, lt_b, lt_count, mask_loc, clen);
                }
            }
        }
    }
    match n.tag {
        suite, block_, product, record, array, array_op, storage => {
            for ch in m.children(id) { collectAffineAndMaskBounds(g, f, m, ch, idx_b, end_local, lt_a, lt_b, lt_count, aff_base, aff_c, aff_len, aff_count, left); }
        },
        bind, construct => { collectAffineAndMaskBounds(g, f, m, n.b, idx_b, end_local, lt_a, lt_b, lt_count, aff_base, aff_c, aff_len, aff_count, left); },
        pattern_bind => {
            collectAffineAndMaskBounds(g, f, m, n.b, idx_b, end_local, lt_a, lt_b, lt_count, aff_base, aff_c, aff_len, aff_count, left);
            collectAffineAndMaskBounds(g, f, m, n.c, idx_b, end_local, lt_a, lt_b, lt_count, aff_base, aff_c, aff_len, aff_count, left);
        },
        return_, project, result_associated => { collectAffineAndMaskBounds(g, f, m, n.a, idx_b, end_local, lt_a, lt_b, lt_count, aff_base, aff_c, aff_len, aff_count, left); },
        scalar, associated, logical, apply => {
            collectAffineAndMaskBounds(g, f, m, n.a, idx_b, end_local, lt_a, lt_b, lt_count, aff_base, aff_c, aff_len, aff_count, left);
            collectAffineAndMaskBounds(g, f, m, n.b, idx_b, end_local, lt_a, lt_b, lt_count, aff_base, aff_c, aff_len, aff_count, left);
        },
        if_value, if_stmt => {
            collectAffineAndMaskBounds(g, f, m, n.a, idx_b, end_local, lt_a, lt_b, lt_count, aff_base, aff_c, aff_len, aff_count, left);
            collectAffineAndMaskBounds(g, f, m, n.b, idx_b, end_local, lt_a, lt_b, lt_count, aff_base, aff_c, aff_len, aff_count, left);
            collectAffineAndMaskBounds(g, f, m, n.c, idx_b, end_local, lt_a, lt_b, lt_count, aff_base, aff_c, aff_len, aff_count, left);
        },
        update => {
            let uinfo = m.updateInfo(id);
            collectAffineAndMaskBounds(g, f, m, uinfo.value, idx_b, end_local, lt_a, lt_b, lt_count, aff_base, aff_c, aff_len, aff_count, left);
            for sel in m.updateSelectors(id) {
                if sel.kind == squid_check_core::UpdateKind.index {
                    collectAffineAndMaskBounds(g, f, m, sel.index, idx_b, end_local, lt_a, lt_b, lt_count, aff_base, aff_c, aff_len, aff_count, left);
                }
            }
        },
        match_ => {
            for inp in m.matchInputs(id) { collectAffineAndMaskBounds(g, f, m, inp, idx_b, end_local, lt_a, lt_b, lt_count, aff_base, aff_c, aff_len, aff_count, left); }
            for arm in m.matchArms(id) {
                collectAffineAndMaskBounds(g, f, m, arm.guard_, idx_b, end_local, lt_a, lt_b, lt_count, aff_base, aff_c, aff_len, aff_count, left);
                collectAffineAndMaskBounds(g, f, m, arm.body, idx_b, end_local, lt_a, lt_b, lt_count, aff_base, aff_c, aff_len, aff_count, left);
            }
        },
        call => {
            for arg in m.call(id).arguments { collectAffineAndMaskBounds(g, f, m, arg, idx_b, end_local, lt_a, lt_b, lt_count, aff_base, aff_c, aff_len, aff_count, left); }
        },
        _ => {},
    }
}

fn collectLoopPreBounds(
    g: const Generator&,
    f: const Fn&,
    m: const Module&,
    loop_id: u32,
    info: squid_check_core::LoopInfo,
    range: CheckedRange,
    le_a: u32[4]&,
    le_b: u32[4]&,
    le_count: i64&,
    lt_a: u32[4]&,
    lt_b: u32[4]&,
    lt_count: i64&,
    aff_base: u32[4]&,
    aff_c: u32[4]&,
    aff_len: u32[4]&,
    aff_count: i64&,
    extra_bnd_a: u32[8]&,
    extra_bnd_b: u32[8]&,
    extra_bnd_count: i64&,
    max_nodes: i64 = 144,
) {
    var nodes: i64 = 0;
    if !countLoopBodyNodes(m, info.body, nodes, max_nodes) { return; }
    if info.kind == squid_check_core::LoopKind.range && range.end_local != 0xffffffff && info.pattern != 0 {
        let pat = m.pattern(info.pattern);
        if pat.tag != squid_check_core::PatternTag.bind { return; }
        var arr_bs: u32[8] = [0; 8];
        var arr_len: i64 = 0;
        var bud: i64 = 128;
        collectIndexedByVar(m, info.body, pat.a, arr_bs, arr_len, bud);
        for ai in 0..arr_len {
            let av, aok = bindGet(g, f, arr_bs[ai]);
            if !aok || tagOf(g, av.ty) != squid_direct_types::Tag.array { continue; }
            let ca = findCheckedArray(f, w(g, av, 0), w(g, av, 1));
            if ca < 0 { continue; }
            let clen = f.checked_arrays[ca].length;
            if clen == range.end_local || findCheckedLe(f, range.end_local, clen) >= 0 { continue; }
            addLePair(le_a, le_b, le_count, range.end_local, clen);
        }
        var abud: i64 = 128;
        collectAffineAndMaskBounds(g, f, m, info.body, pat.a, range.end_local, lt_a, lt_b, lt_count, aff_base, aff_c, aff_len, aff_count, abud);
        return;
    }
    if info.kind == squid_check_core::LoopKind.forever {
        var abud: i64 = 160;
        collectAffineAndMaskBounds(g, f, m, info.body, 0, 0xffffffff, lt_a, lt_b, lt_count, aff_base, aff_c, aff_len, aff_count, abud);
        let bn = m.node(info.body);
        if bn.tag != squid_check_core::Tag.suite && bn.tag != squid_check_core::Tag.block_ { return; }
        let ch = m.children(info.body);
        if ch.len == 0 { return; }
        let first_n = m.node(ch[0]);
        if first_n.tag != squid_check_core::Tag.if_stmt || first_n.c != 0 || !isBreakBody(m, first_n.b) { return; }
        var idx_bs: u32[4] = [0; 4];
        var lim_locs: u32[4] = [0; 4];
        var gb_len: i64 = 0;
        extractOrExitUpperBounds(g, f, m, loop_id, first_n.a, idx_bs, lim_locs, gb_len, 0);
        for gi in 0..gb_len {
            var arr_bs: u32[8] = [0; 8];
            var arr_len: i64 = 0;
            var bud: i64 = 128;
            collectIndexedByVar(m, info.body, idx_bs[gi], arr_bs, arr_len, bud);
            for ai in 0..arr_len {
                let av, aok = bindGet(g, f, arr_bs[ai]);
                if !aok || tagOf(g, av.ty) != squid_direct_types::Tag.array { continue; }
                let ca = findCheckedArray(f, w(g, av, 0), w(g, av, 1));
                if ca < 0 { continue; }
                let clen = f.checked_arrays[ca].length;
                if clen == lim_locs[gi] || findCheckedLe(f, lim_locs[gi], clen) >= 0 { continue; }
                addLePair(le_a, le_b, le_count, lim_locs[gi], clen);
            }
        }
        // Converging 2-pointer BCE: `if lo >= hi: break; ... lo := lo + 1; hi := hi - 1`.
        // Inside the loop `0 <= lo < hi <= hi_init`, so checking `hi_init < arr.length`
        // once before the loop proves both `arr[lo]` and `arr[hi]` in-bounds.
        let cn = m.node(first_n.a);
        if (cn.tag == squid_check_core::Tag.scalar || (cn.tag == squid_check_core::Tag.associated && cn.op != squid_check_core::Op.none)) &&
            (cn.op == squid_check_core::Op.greater_equal || cn.op == squid_check_core::Op.less_equal) {
            var lo_b: u32 = 0;
            var hi_b: u32 = 0;
            if cn.op == squid_check_core::Op.greater_equal { lo_b = localRef(m, cn.a); hi_b = localRef(m, cn.b); }
            else { lo_b = localRef(m, cn.b); hi_b = localRef(m, cn.a); }
            if lo_b != 0 && hi_b != 0 && lo_b != hi_b {
                let carries = m.loopCarries(loop_id);
                var lo_ci: i64 = -1;
                var hi_ci: i64 = -1;
                for carry, ci in carries {
                    if carry.iteration == lo_b { lo_ci = ci; }
                    if carry.iteration == hi_b { hi_ci = ci; }
                }
                if lo_ci >= 0 && hi_ci >= 0 {
                    let lo_rhs = findSingleBindRhs(m, info.body, carries[lo_ci].backedge, 0);
                    let hi_rhs = findSingleBindRhs(m, info.body, carries[hi_ci].backedge, 0);
                    if lo_rhs != 0 && hi_rhs != 0 && matchVarPlusConstOne(m, lo_rhs, lo_b) && matchVarMinusConstOne(m, hi_rhs, hi_b) {
                        let lo_v, lo_ok = bindGet(g, f, lo_b);
                        let hi_v, hi_ok = bindGet(g, f, hi_b);
                        if lo_ok && hi_ok && lo_v.ty == squid_direct_types::u32_ && hi_v.ty == squid_direct_types::u32_ {
                            var arr_bs: u32[8] = [0; 8];
                            var arr_len: i64 = 0;
                            var bud1: i64 = 128;
                            collectIndexedByVar(m, info.body, lo_b, arr_bs, arr_len, bud1);
                            var bud2: i64 = 128;
                            collectIndexedByVar(m, info.body, hi_b, arr_bs, arr_len, bud2);
                            let lo_loc = w(g, lo_v, 0);
                            let hi_loc = w(g, hi_v, 0);
                            for ai in 0..arr_len {
                                let av, aok = bindGet(g, f, arr_bs[ai]);
                                if !aok || tagOf(g, av.ty) != squid_direct_types::Tag.array { continue; }
                                let ca = findCheckedArray(f, w(g, av, 0), w(g, av, 1));
                                if ca < 0 { continue; }
                                let clen = f.checked_arrays[ca].length;
                                addLePair(lt_a, lt_b, lt_count, hi_loc, clen);
                                if extra_bnd_count + 2 <= 8 {
                                    extra_bnd_a[extra_bnd_count] = lo_loc;
                                    extra_bnd_b[extra_bnd_count] = clen;
                                    extra_bnd_count += 1;
                                    extra_bnd_a[extra_bnd_count] = hi_loc;
                                    extra_bnd_b[extra_bnd_count] = clen;
                                    extra_bnd_count += 1;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// 4E-2: Detect small pure-scalar `for ever` loops (e.g. Mandelbrot escape loop) eligible for 2x unroll.
recursive fn scanPureScalarForever(g: const Generator&, m: const Module&, id: u32, has_break: bool&, budget: i64&) -> bool {
    if id == 0 { return true; }
    if budget <= 0 { return false; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        constant, reference => { return true; },
        break_ => { has_break = true; return true; },
        suite, block_ => {
            for ch in m.children(id) {
                if !scanPureScalarForever(g, m, ch, has_break, budget) { return false; }
            }
            return true;
        },
        bind => {
            if n.c >= 2 || m.binding(n.a).scheme.variables.len != 0 { return false; }
            return scanPureScalarForever(g, m, n.b, has_break, budget);
        },
        scalar, associated, logical => {
            if n.tag == squid_check_core::Tag.associated && n.op == squid_check_core::Op.none { return false; }
            return scanPureScalarForever(g, m, n.a, has_break, budget) &&
                scanPureScalarForever(g, m, n.b, has_break, budget);
        },
        if_stmt, if_value => {
            return scanPureScalarForever(g, m, n.a, has_break, budget) &&
                scanPureScalarForever(g, m, n.b, has_break, budget) &&
                scanPureScalarForever(g, m, n.c, has_break, budget);
        },
        call => {
            let cinfo = m.call(id);
            if !scratchScalarCallee(g, m, cinfo) { return false; }
            for arg in cinfo.arguments {
                if !scanPureScalarForever(g, m, arg, has_break, budget) { return false; }
            }
            return true;
        },
        _ => { return false; },
    }
}
fn isPureScalarForeverBody(g: const Generator&, m: const Module&, body: u32) -> bool {
    var has_break = false;
    var budget: i64 = 44;
    return scanPureScalarForever(g, m, body, has_break, budget) && has_break;
}

// 5A: Contiguous `memory.copy` fast path for `for ever` copy-tail loops:
//   for ever:
//     if i >= lim: break
//     dst[k] := src[i]
//     i := i + 1
//     k := k + 1
fn matchVarPlusConstOne(m: const Module&, expr_id: u32, var_b: u32) -> bool {
    let n = m.node(expr_id);
    if (n.tag != squid_check_core::Tag.scalar && !(n.tag == squid_check_core::Tag.associated && n.op != squid_check_core::Op.none)) ||
        n.op != squid_check_core::Op.add { return false; }
    if localRef(m, n.a) == var_b && m.node(n.b).tag == squid_check_core::Tag.constant && m.node(n.b).a == 1 { return true; }
    if localRef(m, n.b) == var_b && m.node(n.a).tag == squid_check_core::Tag.constant && m.node(n.a).a == 1 { return true; }
    return false;
}
fn tryEmitCopyTailLoop(
    g: Generator&,
    f: Fn&,
    loop_id: u32,
    info: squid_check_core::LoopInfo,
    iteration: Vals,
    carry_in_place: const bool[64]&,
) -> bool, Error {
    if g.runtime_().has_fork || info.kind != squid_check_core::LoopKind.forever || info.body == 0 {
        return false, squid_direct_types::Error.none;
    }
    var i_ci: i64 = -1;
    var k_ci: i64 = -1;
    var lim_id: u32 = 0;
    var src_b: u32 = 0;
    var dst_b: u32 = 0;
    var elem_tag = squid_direct_types::Tag.unit;
    var matched = false;
    {
        let m .= g.units[f.unit - 1];
        let carries = m.loopCarries(loop_id);
        if carries.len < 2 || carries.len > 64 { return false, squid_direct_types::Error.none; }
        var u32_cis: i64[2] = [-1; 2];
        var u32_count: i64 = 0;
        for carry, ci in carries {
            if !carry_in_place[ci] {
                if u32_count >= 2 { return false, squid_direct_types::Error.none; }
                let iv = g.s.vals[iteration.start + ci];
                if iv.len != 1 || tagOf(g, iv.ty) != squid_direct_types::Tag.u32_ { return false, squid_direct_types::Error.none; }
                u32_cis[u32_count] = ci;
                u32_count += 1;
            }
        }
        if u32_count != 2 { return false, squid_direct_types::Error.none; }

        let bn = m.node(info.body);
        if bn.tag != squid_check_core::Tag.suite && bn.tag != squid_check_core::Tag.block_ { return false, squid_direct_types::Error.none; }
        let ch = m.children(info.body);
        if ch.len != 4 { return false, squid_direct_types::Error.none; }

        // Stmt 0: `if i >= lim: break`
        let s0 = m.node(ch[0]);
        if s0.tag != squid_check_core::Tag.if_stmt || s0.c != 0 || !isBreakBody(m, s0.b) { return false, squid_direct_types::Error.none; }
        let cn = m.node(s0.a);
        if cn.tag != squid_check_core::Tag.scalar && !(cn.tag == squid_check_core::Tag.associated && cn.op != squid_check_core::Op.none) {
            return false, squid_direct_types::Error.none;
        }
        var guard_var_b: u32 = 0;
        if cn.op == squid_check_core::Op.greater_equal {
            guard_var_b = localRef(m, cn.a);
            lim_id = cn.b;
        } else if cn.op == squid_check_core::Op.less_equal {
            guard_var_b = localRef(m, cn.b);
            lim_id = cn.a;
        } else {
            return false, squid_direct_types::Error.none;
        }
        if guard_var_b == carries[u32_cis[0]].iteration {
            i_ci = u32_cis[0];
            k_ci = u32_cis[1];
        } else if guard_var_b == carries[u32_cis[1]].iteration {
            i_ci = u32_cis[1];
            k_ci = u32_cis[0];
        } else {
            return false, squid_direct_types::Error.none;
        }
        let i_iter = carries[i_ci].iteration;
        let k_iter = carries[k_ci].iteration;
        let lim_ref = localRef(m, lim_id);
        if lim_ref == 0 && m.node(lim_id).tag != squid_check_core::Tag.constant { return false, squid_direct_types::Error.none; }
        if lim_ref == i_iter || lim_ref == k_iter { return false, squid_direct_types::Error.none; }

        // Stmt 1: `dst[k] := src[i]`
        var upd_id: u32 = 0;
        let s1 = m.node(ch[1]);
        if s1.tag == squid_check_core::Tag.update { upd_id = ch[1]; }
        else if s1.tag == squid_check_core::Tag.bind && s1.c < 2 && m.node(s1.b).tag == squid_check_core::Tag.update { upd_id = s1.b; }
        else { return false, squid_direct_types::Error.none; }
        let uinfo = m.updateInfo(upd_id);
        let sels = m.updateSelectors(upd_id);
        if sels.len != 1 || sels[0].kind != squid_check_core::UpdateKind.index || localRef(m, sels[0].index) != k_iter {
            return false, squid_direct_types::Error.none;
        }
        if uinfo.self_binding != 0 && uses(g, f, uinfo.self_binding) != 0 { return false, squid_direct_types::Error.none; }
        dst_b = localRef(m, uinfo.root);
        let gok, src_n, src_idx_n = matchArrayGet(m, uinfo.value);
        if !gok || localRef(m, src_idx_n) != i_iter { return false, squid_direct_types::Error.none; }
        src_b = localRef(m, src_n);
        if src_b == 0 || dst_b == 0 { return false, squid_direct_types::Error.none; }

        // Stmts 2 & 3: `i_back := i + 1` and `k_back := k + 1` in either order.
        let i_back = carries[i_ci].backedge;
        let k_back = carries[k_ci].backedge;
        var saw_i = false;
        var saw_k = false;
        for si in 2..4 {
            let sn = m.node(ch[si]);
            if sn.tag != squid_check_core::Tag.bind || sn.c >= 2 { return false, squid_direct_types::Error.none; }
            if sn.a == i_back && matchVarPlusConstOne(m, sn.b, i_iter) { saw_i = true; }
            else if sn.a == k_back && matchVarPlusConstOne(m, sn.b, k_iter) { saw_k = true; }
            else { return false, squid_direct_types::Error.none; }
        }
        if !saw_i || !saw_k { return false, squid_direct_types::Error.none; }

        let sv, sok = bindGet(g, f, src_b);
        let dv, dok = bindGet(g, f, dst_b);
        if !sok || !dok || tagOf(g, sv.ty) != squid_direct_types::Tag.array || tagOf(g, dv.ty) != squid_direct_types::Tag.array {
            return false, squid_direct_types::Error.none;
        }
        let sda = findDirectArrayBySlot(f, w(g, sv, 0));
        let dda = findDirectArrayBySlot(f, w(g, dv, 0));
        if (sda >= 0 && f.direct_arrays[sda].scalar_packed) || (dda >= 0 && f.direct_arrays[dda].scalar_packed) {
            return false, squid_direct_types::Error.none;
        }
        let s_et = tagOf(g, g.types.node(sv.ty).a);
        let d_et = tagOf(g, g.types.node(dv.ty).a);
        if s_et != d_et || !isScalarTag(s_et) { return false, squid_direct_types::Error.none; }
        elem_tag = s_et;
        matched = true;
    }
    if !matched { return false, squid_direct_types::Error.none; }

    let sv, _ = bindGet(g, f, src_b);
    let dv, _ = bindGet(g, f, dst_b);
    let src_base, src_len = ensureCheckedArray(g, f, sv);
    let dst_base, dst_len = ensureCheckedArray(g, f, dv);
    let lim_v, lerr = expr(g, f, lim_id);
    if lerr != squid_direct_types::Error.none { return false, lerr; }
    let lim_loc = w(g, lim_v, 0);
    let i_loc = w(g, g.s.vals[iteration.start + i_ci], 0);
    let k_loc = w(g, g.s.vals[iteration.start + k_ci], 0);

    // Guard: i < lim && lim <= src_len
    lget(g, i_loc); lget(g, lim_loc); op(g, OP_i32_lt_u);
    lget(g, lim_loc); lget(g, src_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
    let g1 = open(g, f, OP_if_);

    let count = local32(g, f);
    lget(g, lim_loc); lget(g, i_loc); op(g, OP_i32_sub); lset(g, count);
    let k_end = local32(g, f);
    lget(g, k_loc); lget(g, count); op(g, OP_i32_add); lset(g, k_end);

    let bytes = local32(g, f);
    let elem_kind = localKindForScalar(g, g.types.node(sv.ty).a);
    let shift = if squid_direct_writer::wordBytes(elem_kind) == 8 { 3 as u32 } else { 2 as u32 };
    lget(g, count);
    if !byteElement(elem_tag) { i32Const(g, shift); op(g, OP_i32_shl); }
    lset(g, bytes);

    let src_ptr = local32(g, f);
    lget(g, src_base); lget(g, i_loc);
    if !byteElement(elem_tag) { i32Const(g, shift); op(g, OP_i32_shl); }
    op(g, OP_i32_add); lset(g, src_ptr);

    let dst_ptr = local32(g, f);
    lget(g, dst_base); lget(g, k_loc);
    if !byteElement(elem_tag) { i32Const(g, shift); op(g, OP_i32_shl); }
    op(g, OP_i32_add); lset(g, dst_ptr);

    let src_end = local32(g, f);
    lget(g, src_ptr); lget(g, bytes); op(g, OP_i32_add); lset(g, src_end);
    let dst_end = local32(g, f);
    lget(g, dst_ptr); lget(g, bytes); op(g, OP_i32_add); lset(g, dst_end);

    // Inner guard: k_end >= k && k_end <= dst_len && (dst_end <= src_ptr || src_end <= dst_ptr)
    lget(g, k_end); lget(g, k_loc); op(g, OP_i32_ge_u);
    lget(g, k_end); lget(g, dst_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, dst_end); lget(g, src_ptr); op(g, OP_i32_le_u);
    lget(g, src_end); lget(g, dst_ptr); op(g, OP_i32_le_u);
    op(g, OP_i32_or); op(g, OP_i32_and);
    let g2 = open(g, f, OP_if_);

    lget(g, dst_ptr);
    lget(g, src_ptr);
    lget(g, bytes);
    memoryCopyOp(g);
    lget(g, lim_loc);
    lset(g, i_loc);
    lget(g, k_end);
    lset(g, k_loc);

    popCheckedArraysAt(f, g2);
    close(g, f);
    popCheckedArraysAt(f, g1);
    close(g, f);
    f.checked_elems_len = 0;
    return true, squid_direct_types::Error.none;
}

// 5A: Prove `k < dst_len` across a 2-way merge loop via invariant `k + (mid - i) + (hi - j) <= dst_len`.
fn matchBindPlusOneInBody(m: const Module&, body_id: u32, target_b: u32, src_b: u32) -> bool {
    if body_id == 0 { return false; }
    let bn = m.node(body_id);
    if bn.tag == squid_check_core::Tag.bind && bn.c < 2 && bn.a == target_b {
        return matchVarPlusConstOne(m, bn.b, src_b);
    }
    if bn.tag == squid_check_core::Tag.suite || bn.tag == squid_check_core::Tag.block_ {
        for ch in m.children(body_id) {
            let cn = m.node(ch);
            if cn.tag == squid_check_core::Tag.bind && cn.c < 2 && cn.a == target_b {
                return matchVarPlusConstOne(m, cn.b, src_b);
            }
        }
    }
    return false;
}
fn tryEmitFastMergeLoop(
    g: Generator&,
    f: Fn&,
    id: u32,
    info: squid_check_core::LoopInfo,
    iteration: Vals,
    outgoing: Vals,
    slots: Words,
    range: CheckedRange,
    carry_in_place: const bool[64]&,
) -> bool, Error {
    if g.runtime_().has_fork || f.in_specialized_loop || info.kind != squid_check_core::LoopKind.forever || info.body == 0 {
        return false, squid_direct_types::Error.none;
    }
    var i_ci: i64 = -1;
    var j_ci: i64 = -1;
    var k_ci: i64 = -1;
    var mid_loc: u32 = 0;
    var hi_loc: u32 = 0;
    var src_len: u32 = 0;
    var dst_len: u32 = 0;
    var src_base: u32 = 0;
    var dst_base: u32 = 0;
    var fast_ptr_merge = false;
    var fast_merge_signed = false;
    var fast_merge_op = squid_check_core::Op.less_equal;
    var matched = false;
    {
        let m .= g.units[f.unit - 1];
        let bn = m.node(info.body);
        if bn.tag != squid_check_core::Tag.suite && bn.tag != squid_check_core::Tag.block_ { return false, squid_direct_types::Error.none; }
        let ch = m.children(info.body);
        if ch.len != 3 { return false, squid_direct_types::Error.none; }
        let s0 = m.node(ch[0]);
        if s0.tag != squid_check_core::Tag.if_stmt || s0.c != 0 || !isBreakBody(m, s0.b) { return false, squid_direct_types::Error.none; }
        var idx_bs: u32[4] = [0; 4];
        var lim_locs: u32[4] = [0; 4];
        var gb_len: i64 = 0;
        extractOrExitUpperBounds(g, f, m, id, s0.a, idx_bs, lim_locs, gb_len, 0);
        if gb_len != 2 || idx_bs[0] == idx_bs[1] { return false, squid_direct_types::Error.none; }

        let carries = m.loopCarries(id);
        if carries.len < 3 || carries.len > 64 { return false, squid_direct_types::Error.none; }
        for carry, ci in carries {
            if carry.iteration == idx_bs[0] { i_ci = ci; }
            else if carry.iteration == idx_bs[1] { j_ci = ci; }
            else if !carry_in_place[ci] {
                if k_ci >= 0 { return false, squid_direct_types::Error.none; }
                let iv = g.s.vals[iteration.start + ci];
                if iv.len != 1 || tagOf(g, iv.ty) != squid_direct_types::Tag.u32_ { return false, squid_direct_types::Error.none; }
                k_ci = ci;
            }
        }
        if i_ci < 0 || j_ci < 0 || k_ci < 0 { return false, squid_direct_types::Error.none; }
        let i_iter = carries[i_ci].iteration;
        let j_iter = carries[j_ci].iteration;
        let k_iter = carries[k_ci].iteration;
        let k_back = carries[k_ci].backedge;

        // Stmt 2: `k_back := k + 1`
        let s2 = m.node(ch[2]);
        if s2.tag != squid_check_core::Tag.bind || s2.c >= 2 || s2.a != k_back || !matchVarPlusConstOne(m, s2.b, k_iter) {
            return false, squid_direct_types::Error.none;
        }

        // Stmt 1: `if cond: ... i += 1 else: ... j += 1` (not touching k)
        let s1 = m.node(ch[1]);
        if s1.tag != squid_check_core::Tag.if_stmt || s1.c == 0 { return false, squid_direct_types::Error.none; }
        var i_adv_t = false;
        var j_adv_e = false;
        var i_adv_e = false;
        var j_adv_t = false;
        for merge in m.branchMerges(ch[1]) {
            if merge.result == k_back || merge.then_binding == k_iter || merge.else_binding == k_iter {
                return false, squid_direct_types::Error.none;
            }
            if merge.result == carries[i_ci].backedge {
                if matchBindPlusOneInBody(m, s1.b, merge.then_binding, i_iter) && merge.else_binding == i_iter { i_adv_t = true; }
                else if merge.then_binding == i_iter && matchBindPlusOneInBody(m, s1.c, merge.else_binding, i_iter) { i_adv_e = true; }
                else { return false, squid_direct_types::Error.none; }
            }
            if merge.result == carries[j_ci].backedge {
                if merge.then_binding == j_iter && matchBindPlusOneInBody(m, s1.c, merge.else_binding, j_iter) { j_adv_e = true; }
                else if matchBindPlusOneInBody(m, s1.b, merge.then_binding, j_iter) && merge.else_binding == j_iter { j_adv_t = true; }
                else { return false, squid_direct_types::Error.none; }
            }
        }
        if !((i_adv_t && j_adv_e) || (i_adv_e && j_adv_t)) { return false, squid_direct_types::Error.none; }

        // Resolve CheckedArray lengths for arrays indexed by i/j (src) and k (dst).
        var src_arrs: u32[8] = [0; 8];
        var src_len_c: i64 = 0;
        var b1: i64 = 128;
        collectIndexedByVar(m, ch[1], i_iter, src_arrs, src_len_c, b1);
        collectIndexedByVar(m, ch[1], j_iter, src_arrs, src_len_c, b1);
        var dst_arrs: u32[8] = [0; 8];
        var dst_len_c: i64 = 0;
        var b2: i64 = 128;
        collectIndexedByVar(m, ch[1], k_iter, dst_arrs, dst_len_c, b2);
        if src_len_c != 1 || dst_len_c != 1 { return false, squid_direct_types::Error.none; }
        let sv, sok = bindGet(g, f, src_arrs[0]);
        let dv, dok = bindGet(g, f, dst_arrs[0]);
        if !sok || !dok || tagOf(g, sv.ty) != squid_direct_types::Tag.array || tagOf(g, dv.ty) != squid_direct_types::Tag.array {
            return false, squid_direct_types::Error.none;
        }
        let sca = findCheckedArray(f, w(g, sv, 0), w(g, sv, 1));
        let dca = findCheckedArray(f, w(g, dv, 0), w(g, dv, 1));
        if sca < 0 || dca < 0 { return false, squid_direct_types::Error.none; }
        mid_loc = lim_locs[0];
        hi_loc = lim_locs[1];
        src_len = f.checked_arrays[sca].length;
        dst_len = f.checked_arrays[dca].length;
        src_base = f.checked_arrays[sca].base;
        dst_base = f.checked_arrays[dca].base;
        // 7D: Also check if `ch[1]` is the classic 2-way 32-bit integer comparison merge
        // (`if src[i] (<=|<|>=|>) src[j]: dst[k] := src[i]; i += 1 else: dst[k] := src[j]; j += 1`)
        // so we can emit a zero-shift 2x-unrolled byte-pointer branchless loop!
        if i_adv_t && j_adv_e &&
            tagOf(g, g.types.node(sv.ty).a) == squid_direct_types::Tag.u32_ &&
            tagOf(g, g.types.node(dv.ty).a) == squid_direct_types::Tag.u32_ {
            let cond = m.node(s1.a);
            let is_cmp = (cond.tag == squid_check_core::Tag.scalar || (cond.tag == squid_check_core::Tag.associated && cond.op != squid_check_core::Op.none)) &&
                (cond.op == squid_check_core::Op.less || cond.op == squid_check_core::Op.less_equal ||
                 cond.op == squid_check_core::Op.greater || cond.op == squid_check_core::Op.greater_equal);
            let cmp_ty = m.types.node(m.typeOf(cond.a)).tag;
            if is_cmp && cmp_ty == squid_check_types::Tag.unsigned32 {
                let la_ok, la_a, la_i = matchArrayGet(m, cond.a);
                let lb_ok, lb_a, lb_i = matchArrayGet(m, cond.b);
                var cmp_valid = false;
                var raw_op = cond.op;
                if la_ok && lb_ok && localRef(m, la_a) == src_arrs[0] && localRef(m, lb_a) == src_arrs[0] {
                    if localRef(m, la_i) == i_iter && localRef(m, lb_i) == j_iter {
                        cmp_valid = true;
                    } else if localRef(m, la_i) == j_iter && localRef(m, lb_i) == i_iter {
                        cmp_valid = true;
                        if raw_op == squid_check_core::Op.less { raw_op = squid_check_core::Op.greater; }
                        else if raw_op == squid_check_core::Op.less_equal { raw_op = squid_check_core::Op.greater_equal; }
                        else if raw_op == squid_check_core::Op.greater { raw_op = squid_check_core::Op.less; }
                        else { raw_op = squid_check_core::Op.less_equal; }
                    }
                }
                if cmp_valid {
                    // Verify then writes src[i] to dst[k] and else writes src[j] to dst[k], with only 2 stmts each.
                    var t_ok = false;
                    var e_ok = false;
                    let tbn = m.node(s1.b);
                    let ebn = m.node(s1.c);
                    if (tbn.tag == squid_check_core::Tag.suite || tbn.tag == squid_check_core::Tag.block_) &&
                        (ebn.tag == squid_check_core::Tag.suite || ebn.tag == squid_check_core::Tag.block_) {
                        let tch = m.children(s1.b);
                        let ech = m.children(s1.c);
                        if tch.len == 2 && ech.len == 2 {
                            var t_wrote = false; var t_inc = false;
                            for ts in tch {
                                let tsn = m.node(ts);
                                var uid: u32 = 0;
                                if tsn.tag == squid_check_core::Tag.update { uid = ts; }
                                else if tsn.tag == squid_check_core::Tag.bind && tsn.c < 2 && m.node(tsn.b).tag == squid_check_core::Tag.update { uid = tsn.b; }
                                if uid != 0 {
                                    let ui = m.updateInfo(uid);
                                    let ss = m.updateSelectors(uid);
                                    let vok, va, vi = matchArrayGet(m, ui.value);
                                    if ss.len == 1 && ss[0].kind == squid_check_core::UpdateKind.index &&
                                        localRef(m, ui.root) == dst_arrs[0] && localRef(m, ss[0].index) == k_iter &&
                                        (ui.self_binding == 0 || uses(g, f, ui.self_binding) == 0) &&
                                        vok && localRef(m, va) == src_arrs[0] && localRef(m, vi) == i_iter {
                                        t_wrote = true;
                                    }
                                } else if tsn.tag == squid_check_core::Tag.bind && tsn.c < 2 && matchVarPlusConstOne(m, tsn.b, i_iter) {
                                    t_inc = true;
                                }
                            }
                            var e_wrote = false; var e_inc = false;
                            for es in ech {
                                let esn = m.node(es);
                                var uid: u32 = 0;
                                if esn.tag == squid_check_core::Tag.update { uid = es; }
                                else if esn.tag == squid_check_core::Tag.bind && esn.c < 2 && m.node(esn.b).tag == squid_check_core::Tag.update { uid = esn.b; }
                                if uid != 0 {
                                    let ui = m.updateInfo(uid);
                                    let ss = m.updateSelectors(uid);
                                    let vok, va, vi = matchArrayGet(m, ui.value);
                                    if ss.len == 1 && ss[0].kind == squid_check_core::UpdateKind.index &&
                                        localRef(m, ui.root) == dst_arrs[0] && localRef(m, ss[0].index) == k_iter &&
                                        (ui.self_binding == 0 || uses(g, f, ui.self_binding) == 0) &&
                                        vok && localRef(m, va) == src_arrs[0] && localRef(m, vi) == j_iter {
                                        e_wrote = true;
                                    }
                                } else if esn.tag == squid_check_core::Tag.bind && esn.c < 2 && matchVarPlusConstOne(m, esn.b, j_iter) {
                                    e_inc = true;
                                }
                            }
                            t_ok = t_wrote && t_inc;
                            e_ok = e_wrote && e_inc;
                        }
                    }
                    if t_ok && e_ok {
                        fast_ptr_merge = true;
                        fast_merge_signed = false;
                        fast_merge_op = raw_op;
                    }
                }
            }
        }
        matched = true;
    }
    if !matched { return false, squid_direct_types::Error.none; }

    let i_loc = w(g, g.s.vals[iteration.start + i_ci], 0);
    let j_loc = w(g, g.s.vals[iteration.start + j_ci], 0);
    let k_loc = w(g, g.s.vals[iteration.start + k_ci], 0);

    let rem_i = local32(g, f);
    lget(g, mid_loc); lget(g, i_loc); op(g, OP_i32_sub); lset(g, rem_i);
    let rem_j = local32(g, f);
    lget(g, hi_loc); lget(g, j_loc); op(g, OP_i32_sub); lset(g, rem_j);
    let rem = local32(g, f);
    lget(g, rem_i); lget(g, rem_j); op(g, OP_i32_add); lset(g, rem);
    let max_k = local32(g, f);
    lget(g, k_loc); lget(g, rem); op(g, OP_i32_add); lset(g, max_k);

    lget(g, i_loc); lget(g, mid_loc); op(g, OP_i32_le_u);
    lget(g, j_loc); lget(g, hi_loc); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, mid_loc); lget(g, src_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, hi_loc); lget(g, src_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, rem); lget(g, rem_i); op(g, OP_i32_ge_u); op(g, OP_i32_and);
    lget(g, max_k); lget(g, k_loc); op(g, OP_i32_ge_u); op(g, OP_i32_and);
    lget(g, max_k); lget(g, dst_len); op(g, OP_i32_le_u); op(g, OP_i32_and);

    let prev_spec = f.in_specialized_loop;
    f.in_specialized_loop = true;
    let spec_if = open(g, f, OP_if_);
    if fast_ptr_merge {
        let src_end_b = local32(g, f);
        lget(g, src_base); lget(g, src_len); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, src_end_b);
        let dst_end_b = local32(g, f);
        lget(g, dst_base); lget(g, dst_len); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, dst_end_b);
        lget(g, dst_end_b); lget(g, src_base); op(g, OP_i32_le_u);
        lget(g, src_end_b); lget(g, dst_base); op(g, OP_i32_le_u);
        op(g, OP_i32_or);
        lget(g, src_end_b); lget(g, src_base); op(g, OP_i32_ge_u); op(g, OP_i32_and);
        lget(g, dst_end_b); lget(g, dst_base); op(g, OP_i32_ge_u); op(g, OP_i32_and);
        let disj_if = open(g, f, OP_if_);
        let pi = local32(g, f);
        let pj = local32(g, f);
        let pk = local32(g, f);
        let p_mid = local32(g, f);
        let p_hi = local32(g, f);
        let vi = local32(g, f);
        let vj = local32(g, f);
        let cmp = local32(g, f);
        let v0 = local32(g, f);
        let v1 = local32(g, f);
        lget(g, src_base); lget(g, i_loc); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, pi);
        lget(g, src_base); lget(g, j_loc); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, pj);
        lget(g, dst_base); lget(g, k_loc); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, pk);
        lget(g, src_base); lget(g, mid_loc); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, p_mid);
        lget(g, src_base); lget(g, hi_loc); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, p_hi);
        var cmp_wop: u8 = OP_i32_le_u;
        if fast_merge_signed {
            if fast_merge_op == squid_check_core::Op.less { cmp_wop = OP_i32_lt_s; }
            else if fast_merge_op == squid_check_core::Op.less_equal { cmp_wop = OP_i32_le_s; }
            else if fast_merge_op == squid_check_core::Op.greater { cmp_wop = OP_i32_gt_s; }
            else { cmp_wop = OP_i32_ge_s; }
        } else {
            if fast_merge_op == squid_check_core::Op.less { cmp_wop = OP_i32_lt_u; }
            else if fast_merge_op == squid_check_core::Op.less_equal { cmp_wop = OP_i32_le_u; }
            else if fast_merge_op == squid_check_core::Op.greater { cmp_wop = OP_i32_gt_u; }
            else { cmp_wop = OP_i32_ge_u; }
        }
        // 2x unrolled byte-pointer branchless loop (descending pk+4, pk+0 stores => 1 wtime store check / 2 elems!)
        let m2_exit = open(g, f, OP_block);
        let m2_top = open(g, f, OP_loop);
        lget(g, p_mid); lget(g, pi); op(g, OP_i32_sub); i32Const(g, 8); op(g, OP_i32_lt_u);
        lget(g, p_hi); lget(g, pj); op(g, OP_i32_sub); i32Const(g, 8); op(g, OP_i32_lt_u);
        op(g, OP_i32_or);
        br(g, f, OP_br_if, m2_exit);
        // Step 0
        lget(g, pi); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0); ltee(g, vi);
        lget(g, pj); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0); ltee(g, vj);
        op(g, cmp_wop); lset(g, cmp);
        lget(g, vi); lget(g, vj); lget(g, cmp); op(g, OP_select); lset(g, v0);
        lget(g, pi); i32Const(g, 4); op(g, OP_i32_add); lget(g, pi); lget(g, cmp); op(g, OP_select); lset(g, pi);
        lget(g, pj); lget(g, pj); i32Const(g, 4); op(g, OP_i32_add); lget(g, cmp); op(g, OP_select); lset(g, pj);
        // Step 1
        lget(g, pi); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0); ltee(g, vi);
        lget(g, pj); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0); ltee(g, vj);
        op(g, cmp_wop); lset(g, cmp);
        lget(g, vi); lget(g, vj); lget(g, cmp); op(g, OP_select); lset(g, v1);
        lget(g, pi); i32Const(g, 4); op(g, OP_i32_add); lget(g, pi); lget(g, cmp); op(g, OP_select); lset(g, pi);
        lget(g, pj); lget(g, pj); i32Const(g, 4); op(g, OP_i32_add); lget(g, cmp); op(g, OP_select); lset(g, pj);
        // Descending stores +4, +0
        lget(g, pk); lget(g, v1); op(g, OP_i32_store); uleb(g, 2); uleb(g, 4);
        lget(g, pk); lget(g, v0); op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
        lget(g, pk); i32Const(g, 8); op(g, OP_i32_add); lset(g, pk);
        br(g, f, OP_br, m2_top);
        close(g, f);
        close(g, f);
        // 1x byte-pointer tail loop
        let m1_exit = open(g, f, OP_block);
        let m1_top = open(g, f, OP_loop);
        lget(g, pi); lget(g, p_mid); op(g, OP_i32_ge_u);
        lget(g, pj); lget(g, p_hi); op(g, OP_i32_ge_u);
        op(g, OP_i32_or);
        br(g, f, OP_br_if, m1_exit);
        lget(g, pi); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0); ltee(g, vi);
        lget(g, pj); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0); ltee(g, vj);
        op(g, cmp_wop); lset(g, cmp);
        lget(g, pk); lget(g, vi); lget(g, vj); lget(g, cmp); op(g, OP_select); op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
        lget(g, pi); i32Const(g, 4); op(g, OP_i32_add); lget(g, pi); lget(g, cmp); op(g, OP_select); lset(g, pi);
        lget(g, pj); lget(g, pj); i32Const(g, 4); op(g, OP_i32_add); lget(g, cmp); op(g, OP_select); lset(g, pj);
        lget(g, pk); i32Const(g, 4); op(g, OP_i32_add); lset(g, pk);
        br(g, f, OP_br, m1_top);
        close(g, f);
        close(g, f);
        lget(g, pi); lget(g, src_base); op(g, OP_i32_sub); i32Const(g, 2); op(g, OP_i32_shr_u); lset(g, i_loc);
        lget(g, pj); lget(g, src_base); op(g, OP_i32_sub); i32Const(g, 2); op(g, OP_i32_shr_u); lset(g, j_loc);
        lget(g, pk); lget(g, dst_base); op(g, OP_i32_sub); i32Const(g, 2); op(g, OP_i32_shr_u); lset(g, k_loc);
        let aerr = assign(g, f, iteration, outgoing, id);
        if aerr != squid_direct_types::Error.none { f.in_specialized_loop = prev_spec; return false, aerr; }
        popCheckedArraysAt(f, disj_if);
        op(g, OP_else_);
        recordCheckedLe(f, mid_loc, src_len);
        recordCheckedLe(f, hi_loc, src_len);
        recordCheckedBound(f, k_loc, dst_len);
        let ferr = emitLoopCore(g, f, id, info, iteration, outgoing, slots, false, 0, 0, false, neverVal(), 0xffffffff, range, false);
        if ferr != squid_direct_types::Error.none { f.in_specialized_loop = prev_spec; return false, ferr; }
        close(g, f);
    } else {
        recordCheckedLe(f, mid_loc, src_len);
        recordCheckedLe(f, hi_loc, src_len);
        recordCheckedBound(f, k_loc, dst_len);
        let ferr = emitLoopCore(g, f, id, info, iteration, outgoing, slots, false, 0, 0, false, neverVal(), 0xffffffff, range, false);
        if ferr != squid_direct_types::Error.none { f.in_specialized_loop = prev_spec; return false, ferr; }
    }
    popCheckedArraysAt(f, spec_if);
    op(g, OP_else_);
    let serr = emitLoopCore(g, f, id, info, iteration, outgoing, slots, false, 0, 0, false, neverVal(), 0xffffffff, range, false);
    f.in_specialized_loop = prev_spec;
    if serr != squid_direct_types::Error.none { return false, serr; }
    close(g, f);
    return true, squid_direct_types::Error.none;
}

// 5B-2: Pre-loop indirect-index bounds validation for outer counted loops
// (`for _ in 0..N: for k in 0..m: let id = idx_arr[k]; ... A[id] ...`):
// Scans `idx_arr[0..m]` ONCE before the outer loop to verify every `id < min(A_r.len)`.
fn tryMatchIndirectIndexScan(
    g: const Generator&,
    f: const Fn&,
    m: const Module&,
    outer_body: u32,
    target_lens: u32[4]&,
    target_len_count: i64&,
) -> bool, u32, u32, u32 {
    let inner_id = unwrapSingleBody(m, outer_body);
    if inner_id == 0 || m.node(inner_id).tag != squid_check_core::Tag.loop_ { return false, 0, 0, 0; }
    let inner = m.loopInfo(inner_id);
    if inner.kind != squid_check_core::LoopKind.range || inner.pattern == 0 || inner.body == 0 { return false, 0, 0, 0; }
    if m.node(inner.first).tag != squid_check_core::Tag.constant || m.node(inner.first).a != 0 { return false, 0, 0, 0; }
    let pat = m.pattern(inner.pattern);
    if pat.tag != squid_check_core::PatternTag.bind { return false, 0, 0, 0; }
    let k_b = pat.a;

    let ibn = m.node(inner.body);
    if ibn.tag != squid_check_core::Tag.suite && ibn.tag != squid_check_core::Tag.block_ { return false, 0, 0, 0; }
    let ich = m.children(inner.body);
    if ich.len < 2 { return false, 0, 0, 0; }
    let s0 = m.node(ich[0]);
    if s0.tag != squid_check_core::Tag.bind || s0.c >= 2 { return false, 0, 0, 0; }
    let id_b = s0.a;
    let gok, idx_arr_n, idx_pos_n = matchArrayGet(m, s0.b);
    if !gok || localRef(m, idx_pos_n) != k_b { return false, 0, 0, 0; }
    let idx_arr_b = localRef(m, idx_arr_n);
    if idx_arr_b == 0 { return false, 0, 0, 0; }
    // Ensure idx_arr is a CheckedArray of U32 and NOT mutated in inner loop carries.
    for ic in m.loopCarries(inner_id) {
        if ic.incoming == idx_arr_b || ic.iteration == idx_arr_b { return false, 0, 0, 0; }
    }
    let idx_v, idx_ok = bindGet(g, f, idx_arr_b);
    if !idx_ok || tagOf(g, idx_v.ty) != squid_direct_types::Tag.array || tagOf(g, g.types.node(idx_v.ty).a) != squid_direct_types::Tag.u32_ {
        return false, 0, 0, 0;
    }
    if findCheckedArray(f, w(g, idx_v, 0), w(g, idx_v, 1)) < 0 { return false, 0, 0, 0; }
    if localRef(m, inner.end) == 0 && m.node(inner.end).tag != squid_check_core::Tag.constant { return false, 0, 0, 0; }

    var arr_bs: u32[8] = [0; 8];
    var arr_len: i64 = 0;
    var bud: i64 = 128;
    for si in 1..ich.len {
        collectIndexedByVar(m, ich[si], id_b, arr_bs, arr_len, bud);
    }
    target_len_count = 0;
    for ai in 0..arr_len {
        let ab = resolveInnerCarry(m, inner_id, arr_bs[ai]);
        let av, aok = bindGet(g, f, ab);
        if !aok || tagOf(g, av.ty) != squid_direct_types::Tag.array { continue; }
        let ca = findCheckedArray(f, w(g, av, 0), w(g, av, 1));
        if ca < 0 { continue; }
        let clen = f.checked_arrays[ca].length;
        var dup = false;
        for ti in 0..target_len_count { if target_lens[ti] == clen { dup = true; break; } }
        if !dup && target_len_count < 4 {
            target_lens[target_len_count] = clen;
            target_len_count += 1;
        }
    }
    if target_len_count == 0 { return false, 0, 0, 0; }
    return true, idx_arr_b, inner.end, id_b;
}

// 4E-3: 4x unrolled strided scalar array-fill `for ever` loop (e.g. prime_sieve marking loop):
//   for ever:
//     if m >= limit: break
//     arr[m] := inv_scalar
//     m := m + stride
fn tryEmitStridedFillLoop(
    g: Generator&,
    f: Fn&,
    loop_id: u32,
    info: squid_check_core::LoopInfo,
    iteration: Vals,
    carry_in_place: const bool[64]&,
) -> Error {
    if g.runtime_().has_fork || info.kind != squid_check_core::LoopKind.forever || info.body == 0 {
        return squid_direct_types::Error.none;
    }
    var m_carry_idx: i64 = -1;
    var m_iter_b: u32 = 0;
    var limit_id: u32 = 0;
    var arr_b: u32 = 0;
    var fill_val_id: u32 = 0;
    var stride_id: u32 = 0;
    var elem_tag = squid_direct_types::Tag.unit;
    var matched = false;
    {
        let m .= g.units[f.unit - 1];
        let carries = m.loopCarries(loop_id);
        if carries.len == 0 || carries.len > 64 { return squid_direct_types::Error.none; }
        for carry, ci in carries {
            if !carry_in_place[ci] {
                if m_carry_idx >= 0 { return squid_direct_types::Error.none; }
                if m.types.node(m.binding(carry.iteration).ty).tag != squid_check_types::Tag.unsigned32 {
                    return squid_direct_types::Error.none;
                }
                m_carry_idx = ci;
                m_iter_b = carry.iteration;
            }
        }
        if m_carry_idx < 0 { return squid_direct_types::Error.none; }
        let m_back_b = carries[m_carry_idx].backedge;

        let bn = m.node(info.body);
        if bn.tag != squid_check_core::Tag.suite && bn.tag != squid_check_core::Tag.block_ { return squid_direct_types::Error.none; }
        let ch = m.children(info.body);
        if ch.len != 3 { return squid_direct_types::Error.none; }

        // Stmt 0: `if m >= limit: break`
        let s0 = m.node(ch[0]);
        if s0.tag != squid_check_core::Tag.if_stmt || s0.c != 0 || !isBreakBody(m, s0.b) { return squid_direct_types::Error.none; }
        let cn = m.node(s0.a);
        if cn.tag != squid_check_core::Tag.scalar && !(cn.tag == squid_check_core::Tag.associated && cn.op != squid_check_core::Op.none) {
            return squid_direct_types::Error.none;
        }
        if cn.op == squid_check_core::Op.greater_equal && localRef(m, cn.a) == m_iter_b {
            limit_id = cn.b;
        } else if cn.op == squid_check_core::Op.less_equal && localRef(m, cn.b) == m_iter_b {
            limit_id = cn.a;
        } else {
            return squid_direct_types::Error.none;
        }
        let lim_ref = localRef(m, limit_id);
        if lim_ref == 0 && m.node(limit_id).tag != squid_check_core::Tag.constant { return squid_direct_types::Error.none; }
        if lim_ref == m_iter_b { return squid_direct_types::Error.none; }

        // Stmt 1: `arr[m] := inv_scalar`
        var upd_id: u32 = 0;
        let s1 = m.node(ch[1]);
        if s1.tag == squid_check_core::Tag.update { upd_id = ch[1]; }
        else if s1.tag == squid_check_core::Tag.bind && s1.c < 2 && m.node(s1.b).tag == squid_check_core::Tag.update { upd_id = s1.b; }
        else { return squid_direct_types::Error.none; }
        let uinfo = m.updateInfo(upd_id);
        let sels = m.updateSelectors(upd_id);
        if sels.len != 1 || sels[0].kind != squid_check_core::UpdateKind.index || localRef(m, sels[0].index) != m_iter_b {
            return squid_direct_types::Error.none;
        }
        if uinfo.self_binding != 0 && uses(g, f, uinfo.self_binding) != 0 { return squid_direct_types::Error.none; }
        arr_b = localRef(m, uinfo.root);
        if arr_b == 0 { return squid_direct_types::Error.none; }
        let vn = m.node(uinfo.value);
        let vref = localRef(m, uinfo.value);
        if vn.tag != squid_check_core::Tag.constant && (vref == 0 || vref == m_iter_b) { return squid_direct_types::Error.none; }
        fill_val_id = uinfo.value;

        // Stmt 2: `m_back := m + stride`
        let s2 = m.node(ch[2]);
        if s2.tag != squid_check_core::Tag.bind || s2.a != m_back_b || s2.c >= 2 { return squid_direct_types::Error.none; }
        let sn = m.node(s2.b);
        if sn.tag != squid_check_core::Tag.scalar && !(sn.tag == squid_check_core::Tag.associated && sn.op != squid_check_core::Op.none) {
            return squid_direct_types::Error.none;
        }
        if sn.op != squid_check_core::Op.add { return squid_direct_types::Error.none; }
        if localRef(m, sn.a) == m_iter_b { stride_id = sn.b; }
        else if localRef(m, sn.b) == m_iter_b { stride_id = sn.a; }
        else { return squid_direct_types::Error.none; }
        let sref = localRef(m, stride_id);
        if sref == 0 && m.node(stride_id).tag != squid_check_core::Tag.constant { return squid_direct_types::Error.none; }
        if sref == m_iter_b { return squid_direct_types::Error.none; }

        let av, aok = bindGet(g, f, arr_b);
        if !aok || tagOf(g, av.ty) != squid_direct_types::Tag.array { return squid_direct_types::Error.none; }
        let ada = findDirectArrayBySlot(f, w(g, av, 0));
        if ada >= 0 && f.direct_arrays[ada].scalar_packed { return squid_direct_types::Error.none; }
        elem_tag = tagOf(g, g.types.node(av.ty).a);
        if elem_tag != squid_direct_types::Tag.boolean && elem_tag != squid_direct_types::Tag.u32_ && elem_tag != squid_direct_types::Tag.f32_ {
            return squid_direct_types::Error.none;
        }
        matched = true;
    }
    if !matched { return squid_direct_types::Error.none; }

    let av, _ = bindGet(g, f, arr_b);
    let arr_base, arr_len = ensureCheckedArray(g, f, av);
    let lim_v, lerr = expr(g, f, limit_id);
    if lerr != squid_direct_types::Error.none { return lerr; }
    let stride_v, serr = expr(g, f, stride_id);
    if serr != squid_direct_types::Error.none { return serr; }
    let fill_v, ferr = expr(g, f, fill_val_id);
    if ferr != squid_direct_types::Error.none { return ferr; }

    let m_loc = w(g, g.s.vals[iteration.start + m_carry_idx], 0);
    let lim_loc = w(g, lim_v, 0);
    let stride_loc = w(g, stride_v, 0);
    let val_loc = w(g, fill_v, 0);

    // Guard: limit <= arr_len && stride > 0 && stride <= (limit >> 2)
    lget(g, lim_loc);
    lget(g, arr_len);
    op(g, OP_i32_le_u);
    lget(g, stride_loc);
    i32Const(g, 0);
    op(g, OP_i32_gt_u);
    op(g, OP_i32_and);
    lget(g, stride_loc);
    lget(g, lim_loc);
    i32Const(g, 2);
    op(g, OP_i32_shr_u);
    op(g, OP_i32_le_u);
    op(g, OP_i32_and);
    let guard_if = open(g, f, OP_if_);

    let fast_lim = local32(g, f);
    lget(g, lim_loc);
    lget(g, stride_loc);
    i32Const(g, 3);
    op(g, OP_i32_mul);
    op(g, OP_i32_sub);
    lset(g, fast_lim);

    let step_bytes = local32(g, f);
    lget(g, stride_loc);
    if elem_tag != squid_direct_types::Tag.boolean {
        i32Const(g, 2);
        op(g, OP_i32_shl);
    }
    lset(g, step_bytes);

    let step4 = local32(g, f);
    lget(g, stride_loc);
    i32Const(g, 2);
    op(g, OP_i32_shl);
    lset(g, step4);

    let ptr = local32(g, f);
    lget(g, arr_base);
    lget(g, m_loc);
    if elem_tag != squid_direct_types::Tag.boolean {
        i32Const(g, 2);
        op(g, OP_i32_shl);
    }
    op(g, OP_i32_add);
    lset(g, ptr);

    let u_exit = open(g, f, OP_block);
    let u_top = open(g, f, OP_loop);
    lget(g, m_loc);
    lget(g, fast_lim);
    op(g, OP_i32_ge_u);
    br(g, f, OP_br_if, u_exit);

    for step in 0..4 {
        lget(g, ptr);
        lget(g, val_loc);
        if elem_tag == squid_direct_types::Tag.boolean {
            op(g, OP_i32_store8); uleb(g, 0); uleb(g, 0);
        } else if elem_tag == squid_direct_types::Tag.f32_ {
            op(g, OP_f32_store); uleb(g, 2); uleb(g, 0);
        } else {
            op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
        }
        lget(g, ptr);
        lget(g, step_bytes);
        op(g, OP_i32_add);
        lset(g, ptr);
    }
    lget(g, m_loc);
    lget(g, step4);
    op(g, OP_i32_add);
    lset(g, m_loc);
    br(g, f, OP_br, u_top);
    close(g, f);
    close(g, f);
    close(g, f);
    f.checked_elems_len = 0;
    return squid_direct_types::Error.none;
}

// 4C: Register-blocked 4x v128 (16-float) outer-k accumulation for matrix-multiply loops:
//   for k in 0 .. n:
//     let aik = a[a_off + k]
//     let k_off = k * b_stride
//     for col in 0 .. m:
//       [let dst = c_off + col]
//       c[c_off + col] := c[c_off + col] + aik * b[k_off + col]
// Interchanges outer `col` (step 16) with inner `k` (0..n), keeping 4x v128 accumulators
// in registers across all `k` with 100% bit-identical IEEE-754 addition order and single
// post-`k` canonicalization to 0x7fc00000.
fn matchSumWithVar(m: const Module&, id: u32, var_b: u32) -> bool, u32 {
    if localRef(m, id) == var_b { return true, 0; }
    let n = m.node(id);
    if (n.tag == squid_check_core::Tag.scalar || (n.tag == squid_check_core::Tag.associated && n.op != squid_check_core::Op.none)) &&
        n.op == squid_check_core::Op.add {
        if localRef(m, n.a) == var_b { return true, n.b; }
        if localRef(m, n.b) == var_b { return true, n.a; }
    }
    return false, 0;
}
fn matchMulWithVar(m: const Module&, id: u32, var_b: u32) -> bool, u32 {
    let n = m.node(id);
    if (n.tag == squid_check_core::Tag.scalar || (n.tag == squid_check_core::Tag.associated && n.op != squid_check_core::Op.none)) &&
        n.op == squid_check_core::Op.mul {
        if localRef(m, n.a) == var_b { return true, n.b; }
        if localRef(m, n.b) == var_b { return true, n.a; }
    }
    return false, 0;
}
fn matchArrayGet(m: const Module&, id: u32) -> bool, u32, u32 {
    let n = m.node(id);
    if n.tag == squid_check_core::Tag.array_op && m.arrayOperation(id) == squid_backend_collection_ops::Op.get {
        let ch = m.children(id);
        if ch.len == 2 { return true, ch[0], ch[1]; }
    } else if n.tag == squid_check_core::Tag.storage {
        let op_k, ok = squid_check_storage_ops::opFromCode(n.c);
        if ok == squid_error::Error.none && op_k == squid_check_storage_ops::Op.read {
            let ch = m.children(id);
            if ch.len == 2 { return true, ch[0], ch[1]; }
        }
    }
    return false, 0, 0;
}
fn resolveInnerCarry(m: const Module&, inner_loop: u32, b: u32) -> u32 {
    for c in m.loopCarries(inner_loop) {
        if c.iteration == b { return c.incoming; }
    }
    return b;
}
struct MatmulKMatch {
    a_b: u32 = 0,
    b_b: u32 = 0,
    c_b: u32 = 0,
    a_off_id: u32 = 0,
    b_stride_id: u32 = 0,
    c_off_id: u32 = 0,
    m_end_id: u32 = 0,
}
fn matchMatmulKLoop(
    g: const Generator&,
    f: const Fn&,
    m: const Module&,
    k_loop_id: u32,
    k_info: squid_check_core::LoopInfo,
    resolve_k_carries: bool,
    out: MatmulKMatch&,
) -> bool {
    if k_info.kind != squid_check_core::LoopKind.range || k_info.pattern == 0 || k_info.body == 0 { return false; }
    if m.node(k_info.first).tag != squid_check_core::Tag.constant || m.node(k_info.first).a != 0 { return false; }
    let pat = m.pattern(k_info.pattern);
    if pat.tag != squid_check_core::PatternTag.bind { return false; }
    let k_b = pat.a;

    if resolve_k_carries {
        let kcarries = m.loopCarries(k_loop_id);
        if kcarries.len > 64 { return false; }
        for kc, kci in kcarries {
            let kv, kok = bindGet(g, f, kc.incoming);
            if !kok || tagOf(g, kv.ty) != squid_direct_types::Tag.array { return false; }
            var cb: i64 = 256;
            if !carryStaysInPlace(g, m, k_loop_id, kci, kc.iteration, kc.backedge, cb) { return false; }
        }
    }

    let bn = m.node(k_info.body);
    if bn.tag != squid_check_core::Tag.suite && bn.tag != squid_check_core::Tag.block_ { return false; }
    let ch = m.children(k_info.body);
    if ch.len != 3 { return false; }

    // Stmt 0: `let aik = a[a_off + k]`
    let s0 = m.node(ch[0]);
    if s0.tag != squid_check_core::Tag.bind || s0.c >= 2 { return false; }
    let aik_b = s0.a;
    let g0_ok, a_node, a_idx = matchArrayGet(m, s0.b);
    if !g0_ok { return false; }
    var a_b = localRef(m, a_node);
    if resolve_k_carries { a_b = resolveInnerCarry(m, k_loop_id, a_b); }
    let a_ok, a_off = matchSumWithVar(m, a_idx, k_b);
    if a_b == 0 || !a_ok { return false; }
    if a_off != 0 && localRef(m, a_off) == 0 && m.node(a_off).tag != squid_check_core::Tag.constant { return false; }

    // Stmt 1: `let k_off = k * b_stride`
    let s1 = m.node(ch[1]);
    if s1.tag != squid_check_core::Tag.bind || s1.c >= 2 { return false; }
    let k_off_b = s1.a;
    let mul_ok, b_str = matchMulWithVar(m, s1.b, k_b);
    if !mul_ok || b_str == 0 { return false; }
    if localRef(m, b_str) == 0 && m.node(b_str).tag != squid_check_core::Tag.constant { return false; }

    // Stmt 2: `for col in 0 .. m:`
    let col_loop = ch[2];
    if m.node(col_loop).tag != squid_check_core::Tag.loop_ { return false; }
    let col_info = m.loopInfo(col_loop);
    if col_info.kind != squid_check_core::LoopKind.range || col_info.pattern == 0 || col_info.body == 0 { return false; }
    if m.node(col_info.first).tag != squid_check_core::Tag.constant || m.node(col_info.first).a != 0 { return false; }
    let col_pat = m.pattern(col_info.pattern);
    if col_pat.tag != squid_check_core::PatternTag.bind { return false; }
    let col_b = col_pat.a;
    let m_end_id = col_info.end;
    if localRef(m, m_end_id) == 0 && m.node(m_end_id).tag != squid_check_core::Tag.constant { return false; }

    // Inner body: `[let dst = c_off + col] ; c[dst] := c[dst] + aik * b[k_off + col]`
    var inner_stmts: u32[2] = [0; 2];
    var inner_len: i64 = 0;
    let ibn = m.node(col_info.body);
    if ibn.tag == squid_check_core::Tag.suite || ibn.tag == squid_check_core::Tag.block_ {
        let ich = m.children(col_info.body);
        if ich.len == 0 || ich.len > 2 { return false; }
        for ii in 0..ich.len { inner_stmts[ii] = ich[ii]; }
        inner_len = ich.len;
    } else {
        inner_stmts[0] = col_info.body;
        inner_len = 1;
    }
    var dst_alias_b: u32 = 0;
    var dst_alias_off: u32 = 0;
    if inner_len == 2 {
        let d0 = m.node(inner_stmts[0]);
        if d0.tag != squid_check_core::Tag.bind || d0.c >= 2 { return false; }
        let dok, doff = matchSumWithVar(m, d0.b, col_b);
        if !dok { return false; }
        dst_alias_b = d0.a;
        dst_alias_off = doff;
    }
    let last_id = inner_stmts[inner_len - 1];
    let last_n = m.node(last_id);
    var upd_id: u32 = 0;
    if last_n.tag == squid_check_core::Tag.update { upd_id = last_id; }
    else if last_n.tag == squid_check_core::Tag.bind && last_n.c < 2 && m.node(last_n.b).tag == squid_check_core::Tag.update { upd_id = last_n.b; }
    else { return false; }

    let uinfo = m.updateInfo(upd_id);
    let sels = m.updateSelectors(upd_id);
    if sels.len != 1 || sels[0].kind != squid_check_core::UpdateKind.index { return false; }
    let raw_c_b = localRef(m, uinfo.root);
    if raw_c_b == 0 { return false; }
    var c_b = resolveInnerCarry(m, col_loop, raw_c_b);
    if resolve_k_carries { c_b = resolveInnerCarry(m, k_loop_id, c_b); }

    var c_idx_ok = false;
    var c_off_id: u32 = 0;
    if dst_alias_b != 0 && localRef(m, sels[0].index) == dst_alias_b {
        c_idx_ok = true;
        c_off_id = dst_alias_off;
    } else {
        let cok, coff = matchSumWithVar(m, sels[0].index, col_b);
        c_idx_ok = cok;
        c_off_id = coff;
    }
    if !c_idx_ok { return false; }
    if c_off_id != 0 && localRef(m, c_off_id) == 0 && m.node(c_off_id).tag != squid_check_core::Tag.constant { return false; }

    let rn = m.node(uinfo.value);
    if (rn.tag != squid_check_core::Tag.scalar && !(rn.tag == squid_check_core::Tag.associated && rn.op != squid_check_core::Op.none)) ||
        rn.op != squid_check_core::Op.add {
        return false;
    }
    var mul_node: u32 = 0;
    let self_b = uinfo.self_binding;
    if self_b != 0 && localRef(m, rn.a) == self_b {
        mul_node = rn.b;
    } else if self_b != 0 && localRef(m, rn.b) == self_b {
        mul_node = rn.a;
    } else {
        if self_b != 0 && uses(g, f, self_b) != 0 { return false; }
        let ra_get, _ra1, _ra2 = matchArrayGet(m, rn.a);
        let rb_get, _rb1, _rb2 = matchArrayGet(m, rn.b);
        var c_read_node: u32 = 0;
        if ra_get { c_read_node = rn.a; mul_node = rn.b; }
        else if rb_get { c_read_node = rn.b; mul_node = rn.a; }
        else { return false; }

        let cr_ok, cr_arr, cr_idx = matchArrayGet(m, c_read_node);
        if !cr_ok { return false; }
        var cr_cb = resolveInnerCarry(m, col_loop, localRef(m, cr_arr));
        if resolve_k_carries { cr_cb = resolveInnerCarry(m, k_loop_id, cr_cb); }
        if cr_cb != c_b { return false; }
        if dst_alias_b == 0 || localRef(m, cr_idx) != dst_alias_b {
            let crok, croff = matchSumWithVar(m, cr_idx, col_b);
            if !crok || !sameOffsetExpr(m, croff, c_off_id) { return false; }
        }
    }

    let mn = m.node(mul_node);
    if (mn.tag != squid_check_core::Tag.scalar && !(mn.tag == squid_check_core::Tag.associated && mn.op != squid_check_core::Op.none)) ||
        mn.op != squid_check_core::Op.mul {
        return false;
    }
    var b_read_node: u32 = 0;
    if localRef(m, mn.a) == aik_b { b_read_node = mn.b; }
    else if localRef(m, mn.b) == aik_b { b_read_node = mn.a; }
    else { return false; }

    let br_ok, br_arr, br_idx = matchArrayGet(m, b_read_node);
    if !br_ok { return false; }
    var b_b = resolveInnerCarry(m, col_loop, localRef(m, br_arr));
    if resolve_k_carries { b_b = resolveInnerCarry(m, k_loop_id, b_b); }
    if b_b == 0 { return false; }
    let brok, broff = matchSumWithVar(m, br_idx, col_b);
    if !brok || localRef(m, broff) != k_off_b { return false; }

    let av, aok2 = bindGet(g, f, a_b);
    let bv, bok2 = bindGet(g, f, b_b);
    let cv, cok2 = bindGet(g, f, c_b);
    if !aok2 || !bok2 || !cok2 { return false; }
    if tagOf(g, av.ty) != squid_direct_types::Tag.array || tagOf(g, bv.ty) != squid_direct_types::Tag.array || tagOf(g, cv.ty) != squid_direct_types::Tag.array {
        return false;
    }
    if tagOf(g, g.types.node(av.ty).a) != squid_direct_types::Tag.f32_ ||
        tagOf(g, g.types.node(bv.ty).a) != squid_direct_types::Tag.f32_ ||
        tagOf(g, g.types.node(cv.ty).a) != squid_direct_types::Tag.f32_ {
        return false;
    }
    out.a_b = a_b;
    out.b_b = b_b;
    out.c_b = c_b;
    out.a_off_id = a_off;
    out.b_stride_id = b_str;
    out.c_off_id = c_off_id;
    out.m_end_id = m_end_id;
    return true;
}
// Accumulates `acc += va * vb` using Wasm 3.0 `f32x4.relaxed_madd` under `--relaxed-simd`
// or deterministic `f32x4.mul` + `f32x4.add` by default.
fn emitMatmulMulAdd(g: Generator&, va_loc: u32, vb_loc: u32, acc_loc: u32) {
    if squid_direct_writer::relaxedSimdEnabled() {
        lget(g, va_loc);
        lget(g, vb_loc);
        lget(g, acc_loc);
        simdOp(g, SIMD_f32x4_relaxed_madd);
    } else {
        lget(g, acc_loc);
        lget(g, va_loc);
        lget(g, vb_loc);
        simdOp(g, SIMD_f32x4_mul);
        simdOp(g, SIMD_f32x4_add);
    }
    lset(g, acc_loc);
}

fn emitMatmulLoadMulAdd(g: Generator&, va_loc: u32, b_ptr: u32, b_off: u32, acc_loc: u32) {
    if squid_direct_writer::relaxedSimdEnabled() {
        lget(g, va_loc);
        lget(g, b_ptr);
        simdMemOp(g, SIMD_v128_load, 2, b_off);
        lget(g, acc_loc);
        simdOp(g, SIMD_f32x4_relaxed_madd);
    } else {
        lget(g, acc_loc);
        lget(g, va_loc);
        lget(g, b_ptr);
        simdMemOp(g, SIMD_v128_load, 2, b_off);
        simdOp(g, SIMD_f32x4_mul);
        simdOp(g, SIMD_f32x4_add);
    }
    lset(g, acc_loc);
}

fn tryEmitBlockedMatmulKLoop(
    g: Generator&,
    f: Fn&,
    loop_id: u32,
    info: squid_check_core::LoopInfo,
    carry_in_place: const bool[64]&,
    index: u32,
    end_local: u32,
) -> Error {
    if g.runtime_().has_fork || info.kind != squid_check_core::LoopKind.range || info.pattern == 0 || info.body == 0 {
        return squid_direct_types::Error.none;
    }
    var km = MatmulKMatch {};
    var matched = false;
    {
        let m .= g.units[f.unit - 1];
        let carries = m.loopCarries(loop_id);
        if carries.len > 64 { return squid_direct_types::Error.none; }
        for ci in 0..carries.len { if !carry_in_place[ci] { return squid_direct_types::Error.none; } }
        matched = matchMatmulKLoop(g, f, m, loop_id, info, false, km);
    }
    if !matched { return squid_direct_types::Error.none; }
    let a_b = km.a_b;
    let b_b = km.b_b;
    let c_b = km.c_b;
    let a_off_id = km.a_off_id;
    let b_stride_id = km.b_stride_id;
    let c_off_id = km.c_off_id;
    let m_end_id = km.m_end_id;

    let av, _ = bindGet(g, f, a_b);
    let bv, _ = bindGet(g, f, b_b);
    let cv, _ = bindGet(g, f, c_b);
    let a_base, a_len = ensureCheckedArray(g, f, av);
    let b_base, b_len = ensureCheckedArray(g, f, bv);
    let c_base, c_len = ensureCheckedArray(g, f, cv);

    let m_val, merr = expr(g, f, m_end_id);
    if merr != squid_direct_types::Error.none { return merr; }
    let b_str_val, bserr = expr(g, f, b_stride_id);
    if bserr != squid_direct_types::Error.none { return bserr; }
    let m_loc = w(g, m_val, 0);
    let b_str_loc = w(g, b_str_val, 0);

    var a_off_loc: u32 = 0;
    if a_off_id != 0 {
        let v, e = expr(g, f, a_off_id);
        if e != squid_direct_types::Error.none { return e; }
        a_off_loc = w(g, v, 0);
    } else {
        a_off_loc = constLocal(g, f, 0);
    }
    var c_off_loc: u32 = 0;
    if c_off_id != 0 {
        let v, e = expr(g, f, c_off_id);
        if e != squid_direct_types::Error.none { return e; }
        c_off_loc = w(g, v, 0);
    } else {
        c_off_loc = constLocal(g, f, 0);
    }

    // Runtime safety guard:
    // n > 0 && n <= 4096 && m >= 16 && m <= 4096 && b_stride <= 4096
    // && a_off + n >= a_off && a_off + n <= a_len
    // && c_off + m >= c_off && c_off + m <= c_len
    // && (n - 1) * b_stride + m <= b_len
    // && c disjoint from a and b (slot_c != slot_a && slot_c != slot_b; conservatively check byte range disjointness!)
    let n_loc = end_local;
    let a_end = local32(g, f);
    lget(g, a_off_loc); lget(g, n_loc); op(g, OP_i32_add); lset(g, a_end);
    let c_end = local32(g, f);
    lget(g, c_off_loc); lget(g, m_loc); op(g, OP_i32_add); lset(g, c_end);

    let a_ptr = local32(g, f);
    lget(g, a_base); lget(g, a_off_loc); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, a_ptr);
    let c_ptr = local32(g, f);
    lget(g, c_base); lget(g, c_off_loc); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, c_ptr);

    let b_need = local32(g, f);
    lget(g, n_loc); i32Const(g, 1); op(g, OP_i32_sub);
    lget(g, b_str_loc); op(g, OP_i32_mul);
    lget(g, m_loc); op(g, OP_i32_add); lset(g, b_need);

    let a_byte_end = local32(g, f);
    lget(g, a_ptr); lget(g, n_loc); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, a_byte_end);
    let b_byte_end = local32(g, f);
    lget(g, b_base); lget(g, b_need); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, b_byte_end);
    let c_byte_end = local32(g, f);
    lget(g, c_ptr); lget(g, m_loc); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, c_byte_end);

    // Build safety predicate
    lget(g, n_loc); i32Const(g, 0); op(g, OP_i32_gt_u);
    lget(g, n_loc); i32Const(g, 4096); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, m_loc); i32Const(g, 16); op(g, OP_i32_ge_u); op(g, OP_i32_and);
    lget(g, m_loc); i32Const(g, 4096); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, b_str_loc); i32Const(g, 4096); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, a_end); lget(g, a_off_loc); op(g, OP_i32_ge_u); op(g, OP_i32_and);
    lget(g, a_end); lget(g, a_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, c_end); lget(g, c_off_loc); op(g, OP_i32_ge_u); op(g, OP_i32_and);
    lget(g, c_end); lget(g, c_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, b_need); lget(g, b_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
    // Disjoint(c, a): c_byte_end <= a_ptr || a_byte_end <= c_ptr
    lget(g, c_byte_end); lget(g, a_ptr); op(g, OP_i32_le_u);
    lget(g, a_byte_end); lget(g, c_ptr); op(g, OP_i32_le_u);
    op(g, OP_i32_or); op(g, OP_i32_and);
    // Disjoint(c, b): c_byte_end <= b_base || b_byte_end <= c_ptr
    lget(g, c_byte_end); lget(g, b_base); op(g, OP_i32_le_u);
    lget(g, b_byte_end); lget(g, c_ptr); op(g, OP_i32_le_u);
    op(g, OP_i32_or); op(g, OP_i32_and);

    let guard_if = open(g, f, OP_if_);

    let stride_bytes = local32(g, f);
    lget(g, b_str_loc); i32Const(g, 2); op(g, OP_i32_shl); lset(g, stride_bytes);
    let m_tile = local32(g, f);
    lget(g, m_loc); i32Const(g, 0xfffffff0); op(g, OP_i32_and); lset(g, m_tile);
    var nan_v: u32 = 0;
    if !f.defer_f32_nan {
        nan_v = local(g, f, VT_v128);
        v128Const4(g, 0x7fc00000);
        lset(g, nan_v);
    }

    let col_i = constLocal(g, f, 0);
    let col_byte = constLocal(g, f, 0);
    let c_tile = local32(g, f);
    let a_cur = local32(g, f);
    let b_cur = local32(g, f);
    let k_i = local32(g, f);
    let va = local(g, f, VT_v128);
    let acc0 = local(g, f, VT_v128);
    let acc1 = local(g, f, VT_v128);
    let acc2 = local(g, f, VT_v128);
    let acc3 = local(g, f, VT_v128);

    // Outer tile loop: 16 columns per tile (4 x v128 held in XMM registers across all k!)
    let tile_exit = open(g, f, OP_block);
    let tile_top = open(g, f, OP_loop);
    lget(g, col_i); lget(g, m_tile); op(g, OP_i32_ge_u); br(g, f, OP_br_if, tile_exit);

    lget(g, c_ptr); lget(g, col_byte); op(g, OP_i32_add); lset(g, c_tile);
    // Load acc3..acc0 in descending offset order (48, 32, 16, 0) for single BCE check!
    lget(g, c_tile); simdMemOp(g, SIMD_v128_load, 2, 48); lset(g, acc3);
    lget(g, c_tile); simdMemOp(g, SIMD_v128_load, 2, 32); lset(g, acc2);
    lget(g, c_tile); simdMemOp(g, SIMD_v128_load, 2, 16); lset(g, acc1);
    lget(g, c_tile); simdMemOp(g, SIMD_v128_load, 2, 0); lset(g, acc0);

    lget(g, a_ptr); lset(g, a_cur);
    lget(g, b_base); lget(g, col_byte); op(g, OP_i32_add); lset(g, b_cur);
    i32Const(g, 0); lset(g, k_i);

    let k_exit = open(g, f, OP_block);
    let k_top = open(g, f, OP_loop);
    lget(g, k_i); lget(g, n_loc); op(g, OP_i32_ge_u); br(g, f, OP_br_if, k_exit);

    lget(g, a_cur); simdMemOp(g, SIMD_v128_load32_splat, 2, 0); lset(g, va);

    // Descending offsets 48, 32, 16, 0 on b_cur => 1 software bounds check per k!
    emitMatmulLoadMulAdd(g, va, b_cur, 48, acc3);
    emitMatmulLoadMulAdd(g, va, b_cur, 32, acc2);
    emitMatmulLoadMulAdd(g, va, b_cur, 16, acc1);
    emitMatmulLoadMulAdd(g, va, b_cur, 0, acc0);

    lget(g, a_cur); i32Const(g, 4); op(g, OP_i32_add); lset(g, a_cur);
    lget(g, b_cur); lget(g, stride_bytes); op(g, OP_i32_add); lset(g, b_cur);
    lget(g, k_i); i32Const(g, 1); op(g, OP_i32_add); lset(g, k_i);
    br(g, f, OP_br, k_top);
    close(g, f);
    close(g, f);

    // Store acc3..acc0 ONCE with canonical 0x7fc00000 NaN check!
    lget(g, c_tile); lget(g, acc3); if !f.defer_f32_nan { canonicalizeF32x4(g, f, nan_v); } simdMemOp(g, SIMD_v128_store, 2, 48);
    lget(g, c_tile); lget(g, acc2); if !f.defer_f32_nan { canonicalizeF32x4(g, f, nan_v); } simdMemOp(g, SIMD_v128_store, 2, 32);
    lget(g, c_tile); lget(g, acc1); if !f.defer_f32_nan { canonicalizeF32x4(g, f, nan_v); } simdMemOp(g, SIMD_v128_store, 2, 16);
    lget(g, c_tile); lget(g, acc0); if !f.defer_f32_nan { canonicalizeF32x4(g, f, nan_v); } simdMemOp(g, SIMD_v128_store, 2, 0);

    lget(g, col_i); i32Const(g, 16); op(g, OP_i32_add); lset(g, col_i);
    lget(g, col_byte); i32Const(g, 64); op(g, OP_i32_add); lset(g, col_byte);
    br(g, f, OP_br, tile_top);
    close(g, f);
    close(g, f);

    // Scalar column tail for any remaining `m % 16` columns (preserves exact k-order F32 sum!).
    let sacc = local(g, f, VT_f32);
    let tail_exit = open(g, f, OP_block);
    let tail_top = open(g, f, OP_loop);
    lget(g, col_i); lget(g, m_loc); op(g, OP_i32_ge_u); br(g, f, OP_br_if, tail_exit);

    lget(g, c_ptr); lget(g, col_byte); op(g, OP_i32_add); lset(g, c_tile);
    lget(g, c_tile); op(g, OP_f32_load); uleb(g, 2); uleb(g, 0); lset(g, sacc);
    lget(g, a_ptr); lset(g, a_cur);
    lget(g, b_base); lget(g, col_byte); op(g, OP_i32_add); lset(g, b_cur);
    i32Const(g, 0); lset(g, k_i);

    let tk_exit = open(g, f, OP_block);
    let tk_top = open(g, f, OP_loop);
    lget(g, k_i); lget(g, n_loc); op(g, OP_i32_ge_u); br(g, f, OP_br_if, tk_exit);
    lget(g, sacc);
    lget(g, a_cur); op(g, OP_f32_load); uleb(g, 2); uleb(g, 0);
    lget(g, b_cur); op(g, OP_f32_load); uleb(g, 2); uleb(g, 0);
    op(g, OP_f32_mul); op(g, OP_f32_add); lset(g, sacc);
    lget(g, a_cur); i32Const(g, 4); op(g, OP_i32_add); lset(g, a_cur);
    lget(g, b_cur); lget(g, stride_bytes); op(g, OP_i32_add); lset(g, b_cur);
    lget(g, k_i); i32Const(g, 1); op(g, OP_i32_add); lset(g, k_i);
    br(g, f, OP_br, tk_top);
    close(g, f);
    close(g, f);

    lget(g, c_tile);
    lget(g, sacc);
    if !f.defer_f32_nan { canonicalizeF32Stack(g, f); }
    op(g, OP_f32_store); uleb(g, 2); uleb(g, 0);

    lget(g, col_i); i32Const(g, 1); op(g, OP_i32_add); lset(g, col_i);
    lget(g, col_byte); i32Const(g, 4); op(g, OP_i32_add); lset(g, col_byte);
    br(g, f, OP_br, tail_top);
    close(g, f);
    close(g, f);

    // All `0..n` iterations completed: advance `index = n_loc` so original loop exits immediately!
    lget(g, n_loc);
    lset(g, index);
    close(g, f);
    f.checked_elems_len = 0;
    return squid_direct_types::Error.none;
}

// 5C: 2-row x 16-col (8 x v128 accumulators) register-blocked outer-`row` matmul loop:
//   for row in 0 .. rows:
//     let row_off = row * stride       (or separate row_off_a = row * a_stride, row_off_c = row * c_stride)
//     for k in 0 .. n:
//       let aik = a[row_off + k]
//       let k_off = k * b_stride
//       for col in 0 .. m:
//         c[row_off + col] := c[row_off + col] + aik * b[k_off + col]
// Halves `b` loads & bounds checks (1 shared check per 8 FMA-style pairs across 2 rows) and
// advances `index = rows & ~1` so any odd final row falls through cleanly to 4C.
fn tryEmitBlockedMatmulRowLoop(
    g: Generator&,
    f: Fn&,
    loop_id: u32,
    info: squid_check_core::LoopInfo,
    carry_in_place: const bool[64]&,
    index: u32,
    end_local: u32,
) -> Error {
    if g.runtime_().has_fork || info.kind != squid_check_core::LoopKind.range || info.pattern == 0 || info.body == 0 {
        return squid_direct_types::Error.none;
    }
    var km = MatmulKMatch {};
    var a_stride_id: u32 = 0;
    var c_stride_id: u32 = 0;
    var n_end_id: u32 = 0;
    var matched = false;
    {
        let m .= g.units[f.unit - 1];
        if m.node(info.first).tag != squid_check_core::Tag.constant || m.node(info.first).a != 0 {
            return squid_direct_types::Error.none;
        }
        let pat = m.pattern(info.pattern);
        if pat.tag != squid_check_core::PatternTag.bind { return squid_direct_types::Error.none; }
        let row_b = pat.a;

        let carries = m.loopCarries(loop_id);
        if carries.len > 64 { return squid_direct_types::Error.none; }
        for ci in 0..carries.len { if !carry_in_place[ci] { return squid_direct_types::Error.none; } }

        let bn = m.node(info.body);
        if bn.tag != squid_check_core::Tag.suite && bn.tag != squid_check_core::Tag.block_ {
            return squid_direct_types::Error.none;
        }
        let ch = m.children(info.body);
        if ch.len != 2 && ch.len != 3 { return squid_direct_types::Error.none; }

        var off_bs: u32[2] = [0; 2];
        var off_strides: u32[2] = [0; 2];
        let off_count = ch.len - 1;
        for oi in 0..off_count {
            let sn = m.node(ch[oi]);
            if sn.tag != squid_check_core::Tag.bind || sn.c >= 2 { return squid_direct_types::Error.none; }
            let mok, str_id = matchMulWithVar(m, sn.b, row_b);
            if !mok || str_id == 0 { return squid_direct_types::Error.none; }
            let sref = localRef(m, str_id);
            if sref == 0 && m.node(str_id).tag != squid_check_core::Tag.constant { return squid_direct_types::Error.none; }
            if sref == row_b { return squid_direct_types::Error.none; }
            off_bs[oi] = sn.a;
            off_strides[oi] = str_id;
        }

        let k_loop_id = ch[off_count];
        if m.node(k_loop_id).tag != squid_check_core::Tag.loop_ { return squid_direct_types::Error.none; }
        let k_info = m.loopInfo(k_loop_id);
        if !matchMatmulKLoop(g, f, m, k_loop_id, k_info, true, km) { return squid_direct_types::Error.none; }

        n_end_id = k_info.end;
        let nref = localRef(m, n_end_id);
        if nref == 0 && m.node(n_end_id).tag != squid_check_core::Tag.constant { return squid_direct_types::Error.none; }
        if nref == row_b { return squid_direct_types::Error.none; }

        let a_off_ref = localRef(m, km.a_off_id);
        let c_off_ref = localRef(m, km.c_off_id);
        for oi in 0..off_count {
            if a_off_ref != 0 && a_off_ref == off_bs[oi] { a_stride_id = off_strides[oi]; }
            if c_off_ref != 0 && c_off_ref == off_bs[oi] { c_stride_id = off_strides[oi]; }
            if nref == off_bs[oi] || localRef(m, km.b_stride_id) == off_bs[oi] || localRef(m, km.m_end_id) == off_bs[oi] {
                return squid_direct_types::Error.none;
            }
        }
        if a_stride_id == 0 || c_stride_id == 0 { return squid_direct_types::Error.none; }
        if localRef(m, km.b_stride_id) == row_b || localRef(m, km.m_end_id) == row_b {
            return squid_direct_types::Error.none;
        }
        matched = true;
    }
    if !matched { return squid_direct_types::Error.none; }

    let av, _ = bindGet(g, f, km.a_b);
    let bv, _ = bindGet(g, f, km.b_b);
    let cv, _ = bindGet(g, f, km.c_b);
    let a_base, a_len = ensureCheckedArray(g, f, av);
    let b_base, b_len = ensureCheckedArray(g, f, bv);
    let c_base, c_len = ensureCheckedArray(g, f, cv);

    let n_val, nerr = expr(g, f, n_end_id);
    if nerr != squid_direct_types::Error.none { return nerr; }
    let m_val, merr = expr(g, f, km.m_end_id);
    if merr != squid_direct_types::Error.none { return merr; }
    let a_str_val, aserr = expr(g, f, a_stride_id);
    if aserr != squid_direct_types::Error.none { return aserr; }
    let b_str_val, bserr = expr(g, f, km.b_stride_id);
    if bserr != squid_direct_types::Error.none { return bserr; }
    let c_str_val, cserr = expr(g, f, c_stride_id);
    if cserr != squid_direct_types::Error.none { return cserr; }

    let rows_loc = end_local;
    let n_loc = w(g, n_val, 0);
    let m_loc = w(g, m_val, 0);
    let a_str_loc = w(g, a_str_val, 0);
    let b_str_loc = w(g, b_str_val, 0);
    let c_str_loc = w(g, c_str_val, 0);

    let a_str_bytes = local32(g, f);
    lget(g, a_str_loc); i32Const(g, 2); op(g, OP_i32_shl); lset(g, a_str_bytes);
    let b_str_bytes = local32(g, f);
    lget(g, b_str_loc); i32Const(g, 2); op(g, OP_i32_shl); lset(g, b_str_bytes);
    let c_str_bytes = local32(g, f);
    lget(g, c_str_loc); i32Const(g, 2); op(g, OP_i32_shl); lset(g, c_str_bytes);

    let b_need = local32(g, f);
    lget(g, n_loc); i32Const(g, 1); op(g, OP_i32_sub); lget(g, b_str_loc); op(g, OP_i32_mul);
    lget(g, m_loc); op(g, OP_i32_add); lset(g, b_need);
    let b_byte_end = local32(g, f);
    lget(g, b_base); lget(g, b_need); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, b_byte_end);

    var nan_v: u32 = 0xffffffff;
    if !f.defer_f32_nan {
        nan_v = local(g, f, VT_v128);
        v128Const4(g, 0x7fc00000);
        lset(g, nan_v);
    }

    // 6B-1 Fast Path A: 4-row x 8-col (8 x v128 accumulators) + 2x k-unrolling!
    // Shares each b[k, col+16..0] across 4 rows (halving b loads & wtime checks vs 5C)
    // and coalesces pairs of a[r, k+1..k] loads with descending offsets (4, 0).
    let rows_4 = local32(g, f);
    lget(g, rows_loc); i32Const(g, 0xfffffffc); op(g, OP_i32_and); lset(g, rows_4);
    let a_need4 = local32(g, f);
    lget(g, rows_4); i32Const(g, 1); op(g, OP_i32_sub); lget(g, a_str_loc); op(g, OP_i32_mul);
    lget(g, n_loc); op(g, OP_i32_add); lset(g, a_need4);
    let c_need4 = local32(g, f);
    lget(g, rows_4); i32Const(g, 1); op(g, OP_i32_sub); lget(g, c_str_loc); op(g, OP_i32_mul);
    lget(g, m_loc); op(g, OP_i32_add); lset(g, c_need4);
    let a4_byte_end = local32(g, f);
    lget(g, a_base); lget(g, a_need4); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, a4_byte_end);
    let c4_byte_end = local32(g, f);
    lget(g, c_base); lget(g, c_need4); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, c4_byte_end);

    lget(g, rows_loc); i32Const(g, 4); op(g, OP_i32_ge_u);
    lget(g, rows_loc); i32Const(g, 4096); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, n_loc); i32Const(g, 0); op(g, OP_i32_gt_u); op(g, OP_i32_and);
    lget(g, n_loc); i32Const(g, 4096); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, m_loc); i32Const(g, 8); op(g, OP_i32_ge_u); op(g, OP_i32_and);
    lget(g, m_loc); i32Const(g, 4096); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, a_str_loc); i32Const(g, 4096); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, b_str_loc); i32Const(g, 4096); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, c_str_loc); i32Const(g, 4096); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, c_str_loc); lget(g, m_loc); op(g, OP_i32_ge_u); op(g, OP_i32_and);
    lget(g, a_need4); lget(g, a_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, b_need); lget(g, b_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, c_need4); lget(g, c_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, c4_byte_end); lget(g, a_base); op(g, OP_i32_le_u);
    lget(g, a4_byte_end); lget(g, c_base); op(g, OP_i32_le_u);
    op(g, OP_i32_or); op(g, OP_i32_and);
    lget(g, c4_byte_end); lget(g, b_base); op(g, OP_i32_le_u);
    lget(g, b_byte_end); lget(g, c_base); op(g, OP_i32_le_u);
    op(g, OP_i32_or); op(g, OP_i32_and);

    let g4_if = open(g, f, OP_if_);
    let a_str4_bytes = local32(g, f);
    lget(g, a_str_bytes); i32Const(g, 2); op(g, OP_i32_shl); lset(g, a_str4_bytes);
    let c_str4_bytes = local32(g, f);
    lget(g, c_str_bytes); i32Const(g, 2); op(g, OP_i32_shl); lset(g, c_str4_bytes);
    let m_tile8 = local32(g, f);
    lget(g, m_loc); i32Const(g, 0xfffffff8); op(g, OP_i32_and); lset(g, m_tile8);
    let n_q4 = local32(g, f);
    lget(g, n_loc); i32Const(g, 0xfffffffc); op(g, OP_i32_and); lset(g, n_q4);

    let r4_i = constLocal(g, f, 0);
    var ar4: u32[4] = [0; 4];
    var cr4: u32[4] = [0; 4];
    var ac4: u32[4] = [0; 4];
    var ct4: u32[4] = [0; 4];
    var acc4_0: u32[4] = [0; 4];
    var acc4_1: u32[4] = [0; 4];
    var sc4: u32[4] = [0; 4];
    var a3_bits: u32[4] = [0; 4];
    for r in 0..4 {
        ar4[r] = local32(g, f);
        cr4[r] = local32(g, f);
        ac4[r] = local32(g, f);
        ct4[r] = local32(g, f);
        acc4_0[r] = local(g, f, VT_v128);
        acc4_1[r] = local(g, f, VT_v128);
        sc4[r] = local(g, f, VT_f32);
        a3_bits[r] = local32(g, f);
    }
    lget(g, a_base); lset(g, ar4[0]);
    lget(g, c_base); lset(g, cr4[0]);
    let col4_i = local32(g, f);
    let col4_byte = local32(g, f);
    let b4_cur = local32(g, f);
    let k4_i = local32(g, f);
    let va4 = local(g, f, VT_v128);
    let vb4_0 = local(g, f, VT_v128);
    let vb4_1 = local(g, f, VT_v128);
    let sb4 = local(g, f, VT_f32);

    let r4_exit = open(g, f, OP_block);
    let r4_top = open(g, f, OP_loop);
    lget(g, r4_i); lget(g, rows_4); op(g, OP_i32_ge_u); br(g, f, OP_br_if, r4_exit);

    for r in 1..4 {
        lget(g, ar4[r - 1]); lget(g, a_str_bytes); op(g, OP_i32_add); lset(g, ar4[r]);
        lget(g, cr4[r - 1]); lget(g, c_str_bytes); op(g, OP_i32_add); lset(g, cr4[r]);
    }
    i32Const(g, 0); lset(g, col4_i);
    i32Const(g, 0); lset(g, col4_byte);

    let t4_exit = open(g, f, OP_block);
    let t4_top = open(g, f, OP_loop);
    lget(g, col4_i); lget(g, m_tile8); op(g, OP_i32_ge_u); br(g, f, OP_br_if, t4_exit);

    for r in 0..4 {
        lget(g, cr4[r]); lget(g, col4_byte); op(g, OP_i32_add); ltee(g, ct4[r]);
        simdMemOp(g, SIMD_v128_load, 2, 16); lset(g, acc4_1[r]);
        lget(g, ct4[r]); simdMemOp(g, SIMD_v128_load, 2, 0); lset(g, acc4_0[r]);
        lget(g, ar4[r]); lset(g, ac4[r]);
    }
    lget(g, b_base); lget(g, col4_byte); op(g, OP_i32_add); lset(g, b4_cur);
    i32Const(g, 0); lset(g, k4_i);

    // 7E: Zero-spill 4x-unrolled k loop (11 live XMMs <= 14 -> zero spills!).
    // Pre-loading a[r, k+3] (+12) into GP i32 locals proves ac4[r]+16 once per 4 k-steps
    // for dominator BCE, eliminating 75% of software bounds checks on `a` with zero XMM cost!
    let k4_exit = open(g, f, OP_block);
    let k4_top = open(g, f, OP_loop);
    lget(g, k4_i); lget(g, n_q4); op(g, OP_i32_ge_u); br(g, f, OP_br_if, k4_exit);

    for r in 0..4 {
        lget(g, ac4[r]); op(g, OP_i32_load); uleb(g, 2); uleb(g, 12); lset(g, a3_bits[r]);
    }
    for ks in 0..4 {
        lget(g, b4_cur); simdMemOp(g, SIMD_v128_load, 2, 16); lset(g, vb4_1);
        lget(g, b4_cur); simdMemOp(g, SIMD_v128_load, 2, 0);  lset(g, vb4_0);
        for r in 0..4 {
            if ks < 3 {
                lget(g, ac4[r]); simdMemOp(g, SIMD_v128_load32_splat, 2, (ks as u32) * 4); lset(g, va4);
            } else {
                lget(g, a3_bits[r]); simdOp(g, SIMD_i32x4_splat); lset(g, va4);
            }
            emitMatmulMulAdd(g, va4, vb4_1, acc4_1[r]);
            emitMatmulMulAdd(g, va4, vb4_0, acc4_0[r]);
        }
        lget(g, b4_cur); lget(g, b_str_bytes); op(g, OP_i32_add); lset(g, b4_cur);
    }
    for r in 0..4 {
        lget(g, ac4[r]); i32Const(g, 16); op(g, OP_i32_add); lset(g, ac4[r]);
    }
    lget(g, k4_i); i32Const(g, 4); op(g, OP_i32_add); lset(g, k4_i);
    br(g, f, OP_br, k4_top);
    close(g, f);
    close(g, f);

    // Remainder k tail (0..3 iterations)
    let k4t_exit = open(g, f, OP_block);
    let k4t_top = open(g, f, OP_loop);
    lget(g, k4_i); lget(g, n_loc); op(g, OP_i32_ge_u); br(g, f, OP_br_if, k4t_exit);
    lget(g, b4_cur); simdMemOp(g, SIMD_v128_load, 2, 16); lset(g, vb4_1);
    lget(g, b4_cur); simdMemOp(g, SIMD_v128_load, 2, 0);  lset(g, vb4_0);
    for r in 0..4 {
        lget(g, ac4[r]); simdMemOp(g, SIMD_v128_load32_splat, 2, 0); lset(g, va4);
        emitMatmulMulAdd(g, va4, vb4_1, acc4_1[r]);
        emitMatmulMulAdd(g, va4, vb4_0, acc4_0[r]);
        lget(g, ac4[r]); i32Const(g, 4); op(g, OP_i32_add); lset(g, ac4[r]);
    }
    lget(g, b4_cur); lget(g, b_str_bytes); op(g, OP_i32_add); lset(g, b4_cur);
    lget(g, k4_i); i32Const(g, 1); op(g, OP_i32_add); lset(g, k4_i);
    br(g, f, OP_br, k4t_top);
    close(g, f);
    close(g, f);

    // Store all 4 rows in descending offset order (16, 0) with canonical NaN check!
    for r in 0..4 {
        lget(g, ct4[r]); lget(g, acc4_1[r]); if !f.defer_f32_nan { canonicalizeF32x4(g, f, nan_v); } simdMemOp(g, SIMD_v128_store, 2, 16);
        lget(g, ct4[r]); lget(g, acc4_0[r]); if !f.defer_f32_nan { canonicalizeF32x4(g, f, nan_v); } simdMemOp(g, SIMD_v128_store, 2, 0);
    }

    lget(g, col4_i); i32Const(g, 8); op(g, OP_i32_add); lset(g, col4_i);
    lget(g, col4_byte); i32Const(g, 32); op(g, OP_i32_add); lset(g, col4_byte);
    br(g, f, OP_br, t4_top);
    close(g, f);
    close(g, f);

    // 4-row scalar column tail for `m % 8 != 0`:
    let st4_exit = open(g, f, OP_block);
    let st4_top = open(g, f, OP_loop);
    lget(g, col4_i); lget(g, m_loc); op(g, OP_i32_ge_u); br(g, f, OP_br_if, st4_exit);
    for r in 0..4 {
        lget(g, cr4[r]); lget(g, col4_byte); op(g, OP_i32_add); ltee(g, ct4[r]);
        op(g, OP_f32_load); uleb(g, 2); uleb(g, 0); lset(g, sc4[r]);
        lget(g, ar4[r]); lset(g, ac4[r]);
    }
    lget(g, b_base); lget(g, col4_byte); op(g, OP_i32_add); lset(g, b4_cur);
    i32Const(g, 0); lset(g, k4_i);
    let tk4_exit = open(g, f, OP_block);
    let tk4_top = open(g, f, OP_loop);
    lget(g, k4_i); lget(g, n_loc); op(g, OP_i32_ge_u); br(g, f, OP_br_if, tk4_exit);
    lget(g, b4_cur); op(g, OP_f32_load); uleb(g, 2); uleb(g, 0); lset(g, sb4);
    for r in 0..4 {
        lget(g, sc4[r]); lget(g, ac4[r]); op(g, OP_f32_load); uleb(g, 2); uleb(g, 0); lget(g, sb4); op(g, OP_f32_mul); op(g, OP_f32_add); lset(g, sc4[r]);
        lget(g, ac4[r]); i32Const(g, 4); op(g, OP_i32_add); lset(g, ac4[r]);
    }
    lget(g, b4_cur); lget(g, b_str_bytes); op(g, OP_i32_add); lset(g, b4_cur);
    lget(g, k4_i); i32Const(g, 1); op(g, OP_i32_add); lset(g, k4_i);
    br(g, f, OP_br, tk4_top);
    close(g, f);
    close(g, f);
    for r in 0..4 {
        lget(g, ct4[r]); lget(g, sc4[r]); if !f.defer_f32_nan { canonicalizeF32Stack(g, f); } op(g, OP_f32_store); uleb(g, 2); uleb(g, 0);
    }
    lget(g, col4_i); i32Const(g, 1); op(g, OP_i32_add); lset(g, col4_i);
    lget(g, col4_byte); i32Const(g, 4); op(g, OP_i32_add); lset(g, col4_byte);
    br(g, f, OP_br, st4_top);
    close(g, f);
    close(g, f);

    lget(g, ar4[0]); lget(g, a_str4_bytes); op(g, OP_i32_add); lset(g, ar4[0]);
    lget(g, cr4[0]); lget(g, c_str4_bytes); op(g, OP_i32_add); lset(g, cr4[0]);
    lget(g, r4_i); i32Const(g, 4); op(g, OP_i32_add); lset(g, r4_i);
    br(g, f, OP_br, r4_top);
    close(g, f);
    close(g, f);

    lget(g, rows_4);
    lset(g, index);
    popCheckedArraysAt(f, g4_if);
    op(g, OP_else_);

    // 5C Fast Path B: 2-row x 16-col (for rows == 2..3 or fallback when 4-row guard skipped)
    let rows_even = local32(g, f);
    lget(g, rows_loc); i32Const(g, 0xfffffffe); op(g, OP_i32_and); lset(g, rows_even);

    // Need counts (overflow-free when rows, n, m, strides <= 4096 and rows_even >= 2, n >= 1):
    let a_need = local32(g, f);
    lget(g, rows_even); i32Const(g, 1); op(g, OP_i32_sub); lget(g, a_str_loc); op(g, OP_i32_mul);
    lget(g, n_loc); op(g, OP_i32_add); lset(g, a_need);

    let c_need = local32(g, f);
    lget(g, rows_even); i32Const(g, 1); op(g, OP_i32_sub); lget(g, c_str_loc); op(g, OP_i32_mul);
    lget(g, m_loc); op(g, OP_i32_add); lset(g, c_need);

    let a_byte_end = local32(g, f);
    lget(g, a_base); lget(g, a_need); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, a_byte_end);
    let c_byte_end = local32(g, f);
    lget(g, c_base); lget(g, c_need); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, c_byte_end);

    // Safety guard:
    // rows >= 2 && rows <= 4096 && n > 0 && n <= 4096 && m >= 16 && m <= 4096
    // && a_str <= 4096 && b_str <= 4096 && c_str <= 4096 && c_str >= m (non-overlapping C rows!)
    // && a_need <= a_len && b_need <= b_len && c_need <= c_len
    // && disjoint(c, a) && disjoint(c, b)
    lget(g, rows_loc); i32Const(g, 2); op(g, OP_i32_ge_u);
    lget(g, rows_loc); i32Const(g, 4096); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, n_loc); i32Const(g, 0); op(g, OP_i32_gt_u); op(g, OP_i32_and);
    lget(g, n_loc); i32Const(g, 4096); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, m_loc); i32Const(g, 16); op(g, OP_i32_ge_u); op(g, OP_i32_and);
    lget(g, m_loc); i32Const(g, 4096); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, a_str_loc); i32Const(g, 4096); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, b_str_loc); i32Const(g, 4096); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, c_str_loc); i32Const(g, 4096); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, c_str_loc); lget(g, m_loc); op(g, OP_i32_ge_u); op(g, OP_i32_and);
    lget(g, a_need); lget(g, a_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, b_need); lget(g, b_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, c_need); lget(g, c_len); op(g, OP_i32_le_u); op(g, OP_i32_and);
    lget(g, c_byte_end); lget(g, a_base); op(g, OP_i32_le_u);
    lget(g, a_byte_end); lget(g, c_base); op(g, OP_i32_le_u);
    op(g, OP_i32_or); op(g, OP_i32_and);
    lget(g, c_byte_end); lget(g, b_base); op(g, OP_i32_le_u);
    lget(g, b_byte_end); lget(g, c_base); op(g, OP_i32_le_u);
    op(g, OP_i32_or); op(g, OP_i32_and);

    let guard_if = open(g, f, OP_if_);

    let a_str2_bytes = local32(g, f);
    lget(g, a_str_bytes); i32Const(g, 1); op(g, OP_i32_shl); lset(g, a_str2_bytes);
    let c_str2_bytes = local32(g, f);
    lget(g, c_str_bytes); i32Const(g, 1); op(g, OP_i32_shl); lset(g, c_str2_bytes);

    let m_tile = local32(g, f);
    lget(g, m_loc); i32Const(g, 0xfffffff0); op(g, OP_i32_and); lset(g, m_tile);

    let row_i = constLocal(g, f, 0);
    let a_row0 = local32(g, f); lget(g, a_base); lset(g, a_row0);
    let a_row1 = local32(g, f);
    let c_row0 = local32(g, f); lget(g, c_base); lset(g, c_row0);
    let c_row1 = local32(g, f);
    let col_i = local32(g, f);
    let col_byte = local32(g, f);
    let c_tile0 = local32(g, f);
    let c_tile1 = local32(g, f);
    let a0_cur = local32(g, f);
    let a1_cur = local32(g, f);
    let b_cur = local32(g, f);
    let k_i = local32(g, f);
    let va0 = local(g, f, VT_v128);
    let va1 = local(g, f, VT_v128);
    let vb = local(g, f, VT_v128);
    let r0_0 = local(g, f, VT_v128);
    let r0_1 = local(g, f, VT_v128);
    let r0_2 = local(g, f, VT_v128);
    let r0_3 = local(g, f, VT_v128);
    let r1_0 = local(g, f, VT_v128);
    let r1_1 = local(g, f, VT_v128);
    let r1_2 = local(g, f, VT_v128);
    let r1_3 = local(g, f, VT_v128);
    let sacc0 = local(g, f, VT_f32);
    let sacc1 = local(g, f, VT_f32);
    let sb = local(g, f, VT_f32);

    // Outer 2-row loop: row = 0, 2, ..., rows_even - 2
    let r_exit = open(g, f, OP_block);
    let r_top = open(g, f, OP_loop);
    lget(g, row_i); lget(g, rows_even); op(g, OP_i32_ge_u); br(g, f, OP_br_if, r_exit);

    lget(g, a_row0); lget(g, a_str_bytes); op(g, OP_i32_add); lset(g, a_row1);
    lget(g, c_row0); lget(g, c_str_bytes); op(g, OP_i32_add); lset(g, c_row1);

    i32Const(g, 0); lset(g, col_i);
    i32Const(g, 0); lset(g, col_byte);

    // 16-column tile loop (8 x v128 accumulators held in XMM registers across all k!)
    let tile_exit = open(g, f, OP_block);
    let tile_top = open(g, f, OP_loop);
    lget(g, col_i); lget(g, m_tile); op(g, OP_i32_ge_u); br(g, f, OP_br_if, tile_exit);

    lget(g, c_row0); lget(g, col_byte); op(g, OP_i32_add); lset(g, c_tile0);
    lget(g, c_row1); lget(g, col_byte); op(g, OP_i32_add); lset(g, c_tile1);

    // Descending offset loads (48, 32, 16, 0) for single BCE check per row!
    lget(g, c_tile0); simdMemOp(g, SIMD_v128_load, 2, 48); lset(g, r0_3);
    lget(g, c_tile0); simdMemOp(g, SIMD_v128_load, 2, 32); lset(g, r0_2);
    lget(g, c_tile0); simdMemOp(g, SIMD_v128_load, 2, 16); lset(g, r0_1);
    lget(g, c_tile0); simdMemOp(g, SIMD_v128_load, 2, 0); lset(g, r0_0);

    lget(g, c_tile1); simdMemOp(g, SIMD_v128_load, 2, 48); lset(g, r1_3);
    lget(g, c_tile1); simdMemOp(g, SIMD_v128_load, 2, 32); lset(g, r1_2);
    lget(g, c_tile1); simdMemOp(g, SIMD_v128_load, 2, 16); lset(g, r1_1);
    lget(g, c_tile1); simdMemOp(g, SIMD_v128_load, 2, 0); lset(g, r1_0);

    lget(g, a_row0); lset(g, a0_cur);
    lget(g, a_row1); lset(g, a1_cur);
    lget(g, b_base); lget(g, col_byte); op(g, OP_i32_add); lset(g, b_cur);
    i32Const(g, 0); lset(g, k_i);

    let k_exit = open(g, f, OP_block);
    let k_top = open(g, f, OP_loop);
    lget(g, k_i); lget(g, n_loc); op(g, OP_i32_ge_u); br(g, f, OP_br_if, k_exit);

    lget(g, a0_cur); simdMemOp(g, SIMD_v128_load32_splat, 2, 0); lset(g, va0);
    lget(g, a1_cur); simdMemOp(g, SIMD_v128_load32_splat, 2, 0); lset(g, va1);

    // Load b[k, col+48..0] ONCE in descending order and update BOTH rows (8 v128 mul+adds)!
    lget(g, b_cur); simdMemOp(g, SIMD_v128_load, 2, 48); lset(g, vb);
    emitMatmulMulAdd(g, va0, vb, r0_3);
    emitMatmulMulAdd(g, va1, vb, r1_3);

    lget(g, b_cur); simdMemOp(g, SIMD_v128_load, 2, 32); lset(g, vb);
    emitMatmulMulAdd(g, va0, vb, r0_2);
    emitMatmulMulAdd(g, va1, vb, r1_2);

    lget(g, b_cur); simdMemOp(g, SIMD_v128_load, 2, 16); lset(g, vb);
    emitMatmulMulAdd(g, va0, vb, r0_1);
    emitMatmulMulAdd(g, va1, vb, r1_1);

    lget(g, b_cur); simdMemOp(g, SIMD_v128_load, 2, 0); lset(g, vb);
    emitMatmulMulAdd(g, va0, vb, r0_0);
    emitMatmulMulAdd(g, va1, vb, r1_0);

    lget(g, a0_cur); i32Const(g, 4); op(g, OP_i32_add); lset(g, a0_cur);
    lget(g, a1_cur); i32Const(g, 4); op(g, OP_i32_add); lset(g, a1_cur);
    lget(g, b_cur); lget(g, b_str_bytes); op(g, OP_i32_add); lset(g, b_cur);
    lget(g, k_i); i32Const(g, 1); op(g, OP_i32_add); lset(g, k_i);
    br(g, f, OP_br, k_top);
    close(g, f);
    close(g, f);

    lget(g, c_tile0); lget(g, r0_3); if !f.defer_f32_nan { canonicalizeF32x4(g, f, nan_v); } simdMemOp(g, SIMD_v128_store, 2, 48);
    lget(g, c_tile0); lget(g, r0_2); if !f.defer_f32_nan { canonicalizeF32x4(g, f, nan_v); } simdMemOp(g, SIMD_v128_store, 2, 32);
    lget(g, c_tile0); lget(g, r0_1); if !f.defer_f32_nan { canonicalizeF32x4(g, f, nan_v); } simdMemOp(g, SIMD_v128_store, 2, 16);
    lget(g, c_tile0); lget(g, r0_0); if !f.defer_f32_nan { canonicalizeF32x4(g, f, nan_v); } simdMemOp(g, SIMD_v128_store, 2, 0);

    lget(g, c_tile1); lget(g, r1_3); if !f.defer_f32_nan { canonicalizeF32x4(g, f, nan_v); } simdMemOp(g, SIMD_v128_store, 2, 48);
    lget(g, c_tile1); lget(g, r1_2); if !f.defer_f32_nan { canonicalizeF32x4(g, f, nan_v); } simdMemOp(g, SIMD_v128_store, 2, 32);
    lget(g, c_tile1); lget(g, r1_1); if !f.defer_f32_nan { canonicalizeF32x4(g, f, nan_v); } simdMemOp(g, SIMD_v128_store, 2, 16);
    lget(g, c_tile1); lget(g, r1_0); if !f.defer_f32_nan { canonicalizeF32x4(g, f, nan_v); } simdMemOp(g, SIMD_v128_store, 2, 0);

    lget(g, col_i); i32Const(g, 16); op(g, OP_i32_add); lset(g, col_i);
    lget(g, col_byte); i32Const(g, 64); op(g, OP_i32_add); lset(g, col_byte);
    br(g, f, OP_br, tile_top);
    close(g, f);
    close(g, f);

    // 2-row scalar column tail for any remaining `m % 16` columns:
    let tail_exit = open(g, f, OP_block);
    let tail_top = open(g, f, OP_loop);
    lget(g, col_i); lget(g, m_loc); op(g, OP_i32_ge_u); br(g, f, OP_br_if, tail_exit);

    lget(g, c_row0); lget(g, col_byte); op(g, OP_i32_add); lset(g, c_tile0);
    lget(g, c_row1); lget(g, col_byte); op(g, OP_i32_add); lset(g, c_tile1);
    lget(g, c_tile0); op(g, OP_f32_load); uleb(g, 2); uleb(g, 0); lset(g, sacc0);
    lget(g, c_tile1); op(g, OP_f32_load); uleb(g, 2); uleb(g, 0); lset(g, sacc1);

    lget(g, a_row0); lset(g, a0_cur);
    lget(g, a_row1); lset(g, a1_cur);
    lget(g, b_base); lget(g, col_byte); op(g, OP_i32_add); lset(g, b_cur);
    i32Const(g, 0); lset(g, k_i);

    let tk_exit = open(g, f, OP_block);
    let tk_top = open(g, f, OP_loop);
    lget(g, k_i); lget(g, n_loc); op(g, OP_i32_ge_u); br(g, f, OP_br_if, tk_exit);
    lget(g, b_cur); op(g, OP_f32_load); uleb(g, 2); uleb(g, 0); lset(g, sb);
    lget(g, sacc0); lget(g, a0_cur); op(g, OP_f32_load); uleb(g, 2); uleb(g, 0); lget(g, sb); op(g, OP_f32_mul); op(g, OP_f32_add); lset(g, sacc0);
    lget(g, sacc1); lget(g, a1_cur); op(g, OP_f32_load); uleb(g, 2); uleb(g, 0); lget(g, sb); op(g, OP_f32_mul); op(g, OP_f32_add); lset(g, sacc1);
    lget(g, a0_cur); i32Const(g, 4); op(g, OP_i32_add); lset(g, a0_cur);
    lget(g, a1_cur); i32Const(g, 4); op(g, OP_i32_add); lset(g, a1_cur);
    lget(g, b_cur); lget(g, b_str_bytes); op(g, OP_i32_add); lset(g, b_cur);
    lget(g, k_i); i32Const(g, 1); op(g, OP_i32_add); lset(g, k_i);
    br(g, f, OP_br, tk_top);
    close(g, f);
    close(g, f);

    lget(g, c_tile0); lget(g, sacc0); if !f.defer_f32_nan { canonicalizeF32Stack(g, f); } op(g, OP_f32_store); uleb(g, 2); uleb(g, 0);
    lget(g, c_tile1); lget(g, sacc1); if !f.defer_f32_nan { canonicalizeF32Stack(g, f); } op(g, OP_f32_store); uleb(g, 2); uleb(g, 0);

    lget(g, col_i); i32Const(g, 1); op(g, OP_i32_add); lset(g, col_i);
    lget(g, col_byte); i32Const(g, 4); op(g, OP_i32_add); lset(g, col_byte);
    br(g, f, OP_br, tail_top);
    close(g, f);
    close(g, f);

    lget(g, a_row0); lget(g, a_str2_bytes); op(g, OP_i32_add); lset(g, a_row0);
    lget(g, c_row0); lget(g, c_str2_bytes); op(g, OP_i32_add); lset(g, c_row0);
    lget(g, row_i); i32Const(g, 2); op(g, OP_i32_add); lset(g, row_i);
    br(g, f, OP_br, r_top);
    close(g, f);
    close(g, f);

    // Advance outer `index = rows_even` so any odd final row falls through cleanly to 4C!
    lget(g, rows_even);
    lset(g, index);
    close(g, f);
    close(g, f);
    f.checked_elems_len = 0;
    return squid_direct_types::Error.none;
}

fn invariantDivisor(g: const Generator&, f: const Fn&, m: const Module&, id: u32, input_locals: u32) -> u32 {
    let n = m.node(id);
    if n.tag != squid_check_core::Tag.scalar || (n.op != squid_check_core::Op.div && n.op != squid_check_core::Op.rem) ||
        m.types.node(m.typeOf(n.b)).tag != squid_check_types::Tag.unsigned32 {
        return 0xffffffff;
    }
    let binding = localRef(m, n.b);
    let value, found = bindGet(g, f, binding);
    let _, is_cell = withCellType(g, f, binding);
    if !found || is_cell || value.ty != squid_direct_types::u32_ { return 0xffffffff; }
    let divisor = w(g, value, 0);
    let _, constant = constU32(f, divisor);
    if divisor >= input_locals || constant { return 0xffffffff; }
    return divisor;
}

// Find a division that is guaranteed to execute before any possible trap,
// effect, or early exit on the first iteration. Stop at control flow and
// opaque expressions. The boolean means the prefix was entirely safe.
recursive fn firstLoopDivision(g: Generator&, f: const Fn&, m: const Module&, id: u32, input_locals: u32, budget: i64&) -> u32, bool {
    if id == 0 { return 0, true; }
    if budget <= 0 { return 0, false; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        constant => { return 0, true; },
        reference => {
            let binding = localRef(m, id);
            if binding == 0 { return 0, false; }
            let kind = m.binding(binding).kind;
            let _, is_cell = withCellType(g, f, binding);
            return 0, !is_cell && (kind == squid_reuse_principal_interface::Kind.local ||
                kind == squid_reuse_principal_interface::Kind.parameter);
        },
        scalar => {
            if !isCoreScalar(m, n.a) || (n.b != 0 && !isCoreScalar(m, n.b)) { return 0, false; }
            let lhs, lhs_safe = firstLoopDivision(g, f, m, n.a, input_locals, budget);
            if lhs != 0 || !lhs_safe { return lhs, lhs_safe; }
            let rhs, rhs_safe = firstLoopDivision(g, f, m, n.b, input_locals, budget);
            if rhs != 0 || !rhs_safe { return rhs, rhs_safe; }
            let divisor = invariantDivisor(g, f, m, id, input_locals);
            var machine = n.op;
            if n.c == 1 {
                // Only U32 scalar operators have a known trap classification here.
                if m.types.node(m.typeOf(n.a)).tag != squid_check_types::Tag.unsigned32 { return 0, false; }
                let resolved, error = scalarMember(g, f, m, squid_direct_types::u32_, 0, n.op, id);
                if error != squid_direct_types::Error.none { return 0, false; }
                machine = resolved;
            }
            if machine == squid_check_core::Op.div || machine == squid_check_core::Op.rem {
                if divisor != 0xffffffff { return id, false; }
                return 0, false;
            }
            return 0, isPureU32Op(machine) || isComparisonOp(machine);
        },
        bind => {
            if n.c < 2 { return firstLoopDivision(g, f, m, n.b, input_locals, budget); }
            return 0, false;
        },
        suite, block_ => {
            for child in m.children(id) {
                let div, safe = firstLoopDivision(g, f, m, child, input_locals, budget);
                if div != 0 || !safe { return div, safe; }
            }
            return 0, true;
        },
        _ => { return 0, false; },
    }
}

fn emitLoopReciprocal(g: Generator&, f: Fn&, divisor: u32, mandatory: bool, index: u32, end: u32) {
    for at in 0..f.loop_reciprocals_len {
        if f.loop_reciprocals[at].divisor == divisor { return; }
    }
    if f.loop_reciprocals_len >= 8 { return; }

    let d = local(g, f, VT_i64);
    let multiplier = local(g, f, VT_i64);
    let shift = local(g, f, VT_i64);
    lget(g, divisor);
    let nonzero = open(g, f, OP_if_);
    lget(g, divisor);
    op(g, OP_i64_extend_i32_u);
    lset(g, d);
    // s = ceil(log2(d)), including zero for d == 1 and 32 for large d.
    i64Const(g, 64);
    lget(g, d);
    i64Const(g, 1);
    op(g, OP_i64_sub);
    op(g, OP_i64_clz);
    op(g, OP_i64_sub);
    lset(g, shift);
    // m = ceil(((2^s - d) * 2^32) / d).
    i64Const(g, 1);
    lget(g, shift);
    op(g, OP_i64_shl);
    lget(g, d);
    op(g, OP_i64_sub);
    i64Const(g, 32);
    op(g, OP_i64_shl);
    lget(g, d);
    op(g, OP_i64_add);
    i64Const(g, 1);
    op(g, OP_i64_sub);
    lget(g, d);
    op(g, OP_i64_div_u);
    lset(g, multiplier);
    if mandatory {
        op(g, OP_else_);
        if index == 0xffffffff { op(g, OP_unreachable_); }
        else {
            lget(g, index);
            lget(g, end);
            op(g, OP_i32_lt_u);
            trap(g, f);
        }
    }
    close(g, f);
    f.loop_reciprocals[f.loop_reciprocals_len] = LoopReciprocal { divisor, multiplier, shift, !mandatory };
    f.loop_reciprocals_len += 1;
}

fn emitLoopReciprocalU64(g: Generator&, f: Fn&, divisor: u32, from_u32: bool) {
    for at in 0..f.loop_reciprocals_u64_len {
        let e = f.loop_reciprocals_u64[at];
        if e.divisor == divisor && e.from_u32 == from_u32 { return; }
    }
    if f.loop_reciprocals_u64_len >= 8 { return; }
    let d = local(g, f, VT_i64);
    let m_lo = local(g, f, VT_i64);
    let m_hi = local(g, f, VT_i64);
    let sh1 = local(g, f, VT_i64);
    let sh2 = local(g, f, VT_i64);
    let s_loc = local(g, f, VT_i64);
    let rem = local(g, f, VT_i64);
    let m_low = local(g, f, VT_i64);
    let cnt = local32(g, f);
    let carry = local(g, f, VT_i64);
    let rem2 = local(g, f, VT_i64);
    lget(g, divisor);
    if from_u32 { op(g, OP_i64_extend_i32_u); }
    ltee(g, d);
    i64Const(g, 1);
    op(g, OP_i64_gt_u);
    let gt1 = open(g, f, OP_if_);
    // s = 64 - clz(d - 1); sh1 = 1; sh2 = s - 1
    i64Const(g, 64);
    lget(g, d);
    i64Const(g, 1);
    op(g, OP_i64_sub);
    op(g, OP_i64_clz);
    op(g, OP_i64_sub);
    ltee(g, s_loc);
    i64Const(g, 1);
    op(g, OP_i64_sub);
    lset(g, sh2);
    i64Const(g, 1);
    lset(g, sh1);
    // rem = ((1 << s) - d) mod 2^64 (for s == 64, 0 - d)
    lget(g, s_loc);
    i64Const(g, 64);
    op(g, OP_i64_eq);
    let s64 = open(g, f, OP_if_);
    i64Const(g, 0);
    lget(g, d);
    op(g, OP_i64_sub);
    lset(g, rem);
    op(g, OP_else_);
    i64Const(g, 1);
    lget(g, s_loc);
    op(g, OP_i64_shl);
    lget(g, d);
    op(g, OP_i64_sub);
    lset(g, rem);
    close(g, f);
    lget(g, rem);
    i64Const(g, 0);
    op(g, OP_i64_ne);
    let nonpow2 = open(g, f, OP_if_);
    i64Const(g, 0);
    lset(g, m_low);
    i32Const(g, 64);
    lset(g, cnt);
    let lp_exit = open(g, f, OP_block);
    let lp_top = open(g, f, OP_loop);
    lget(g, cnt);
    op(g, OP_i32_eqz);
    br(g, f, OP_br_if, lp_exit);
    lget(g, rem);
    i64Const(g, 63);
    op(g, OP_i64_shr_u);
    lset(g, carry);
    lget(g, rem);
    i64Const(g, 1);
    op(g, OP_i64_shl);
    lset(g, rem2);
    lget(g, m_low);
    i64Const(g, 1);
    op(g, OP_i64_shl);
    lset(g, m_low);
    lget(g, carry);
    i64Const(g, 0);
    op(g, OP_i64_ne);
    lget(g, rem2);
    lget(g, d);
    op(g, OP_i64_ge_u);
    op(g, OP_i32_or);
    let sub_if = open(g, f, OP_if_);
    lget(g, rem2);
    lget(g, d);
    op(g, OP_i64_sub);
    lset(g, rem);
    lget(g, m_low);
    i64Const(g, 1);
    op(g, OP_i64_or);
    lset(g, m_low);
    op(g, OP_else_);
    lget(g, rem2);
    lset(g, rem);
    close(g, f);
    lget(g, cnt);
    i32Const(g, 1);
    op(g, OP_i32_sub);
    lset(g, cnt);
    br(g, f, OP_br, lp_top);
    close(g, f);
    close(g, f);
    lget(g, m_low);
    i64Const(g, 1);
    op(g, OP_i64_add);
    ltee(g, m_low);
    i64Const(g, 0xffffffff);
    op(g, OP_i64_and);
    lset(g, m_lo);
    lget(g, m_low);
    i64Const(g, 32);
    op(g, OP_i64_shr_u);
    lset(g, m_hi);
    close(g, f);
    close(g, f);
    f.loop_reciprocals_u64[f.loop_reciprocals_u64_len] = LoopReciprocalU64 { divisor, from_u32, m_lo, m_hi, sh1, sh2, true };
    f.loop_reciprocals_u64_len += 1;
}

fn invariantU64DivisorExpr(g: const Generator&, f: const Fn&, m: const Module&, node_id: u32, input_locals: u32) -> u32, bool {
    if node_id == 0 { return 0xffffffff, false; }
    let b = localRef(m, node_id);
    if b != 0 {
        let value, found = bindGet(g, f, b);
        let _, is_cell = withCellType(g, f, b);
        if found && !is_cell && value.ty == squid_direct_types::u64_ {
            let loc = w(g, value, 0);
            let _, is_c = constU64(f, loc);
            if loc < input_locals && !is_c { return loc, false; }
        }
        return 0xffffffff, false;
    }
    let n = m.node(node_id);
    // Match `u32_var.to_u64` (project/call/associated/scalar convert).
    var src_u32: u32 = 0;
    if n.tag == squid_check_core::Tag.scalar && n.op == squid_check_core::Op.numeric_convert {
        src_u32 = n.a;
    } else if n.tag == squid_check_core::Tag.project {
        let sp = m.fieldSpelling(m.projection(n.b).field);
        if sp.present && sp.value == "to_u64" { src_u32 = n.a; }
    } else if n.tag == squid_check_core::Tag.associated && n.op == squid_check_core::Op.numeric_convert {
        src_u32 = n.a;
    } else if n.tag == squid_check_core::Tag.call {
        let ci = m.call(node_id);
        if ci.arguments.len == 1 { src_u32 = ci.arguments[0]; }
    }
    if src_u32 != 0 {
        let sb = localRef(m, src_u32);
        if sb != 0 {
            let value, found = bindGet(g, f, sb);
            let _, is_cell = withCellType(g, f, sb);
            if found && !is_cell && value.ty == squid_direct_types::u32_ {
                let loc = w(g, value, 0);
                let _, is_c = constU32(f, loc);
                if loc < input_locals && !is_c { return loc, true; }
            }
        }
    }
    return 0xffffffff, false;
}

recursive fn calleeUsesParamAsU64Divisor(m: const Module&, id: u32, param_b: u32, depth: i64 = 0) -> bool {
    if id == 0 || depth > 16 { return false; }
    let n = m.node(id);
    match n.tag {
        scalar => {
            if (n.op == squid_check_core::Op.div || n.op == squid_check_core::Op.rem) &&
                m.types.node(m.typeOf(n.b)).tag == squid_check_types::Tag.unsigned64 {
                if localRef(m, n.b) == param_b { return true; }
                let bn = m.node(n.b);
                if bn.tag == squid_check_core::Tag.project && localRef(m, bn.a) == param_b {
                    let sp = m.fieldSpelling(m.projection(bn.b).field);
                    if sp.present && sp.value == "to_u64" { return true; }
                } else if (bn.tag == squid_check_core::Tag.scalar || bn.tag == squid_check_core::Tag.associated) &&
                    bn.op == squid_check_core::Op.numeric_convert && localRef(m, bn.a) == param_b {
                    return true;
                }
            }
            return calleeUsesParamAsU64Divisor(m, n.a, param_b, depth + 1) || calleeUsesParamAsU64Divisor(m, n.b, param_b, depth + 1);
        },
        suite, block_, product, record => {
            for ch in m.children(id) { if calleeUsesParamAsU64Divisor(m, ch, param_b, depth + 1) { return true; } }
            return false;
        },
        bind, construct => { return calleeUsesParamAsU64Divisor(m, n.b, param_b, depth + 1); },
        return_, project, associated => { return calleeUsesParamAsU64Divisor(m, n.a, param_b, depth + 1); },
        if_stmt, if_value => {
            return calleeUsesParamAsU64Divisor(m, n.a, param_b, depth + 1) ||
                calleeUsesParamAsU64Divisor(m, n.b, param_b, depth + 1) ||
                calleeUsesParamAsU64Divisor(m, n.c, param_b, depth + 1);
        },
        _ => { return false; },
    }
}

// Bindings in the body, the iterator and changing carries have no stable
// local at the preheader. Nested loops scan their own scope.
recursive fn collectLoopReciprocals(g: Generator&, f: Fn&, id: u32, input_locals: u32, mandatory: u32, index: u32, end: u32, budget: i64&) {
    if id == 0 || budget <= 0 || (f.loop_reciprocals_len >= 8 && f.loop_reciprocals_u64_len >= 8) { return; }
    budget -= 1;
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    match n.tag {
        scalar, associated, logical => {
            let divisor = invariantDivisor(g, f, m, id, input_locals);
            if divisor != 0xffffffff { emitLoopReciprocal(g, f, divisor, divisor == mandatory, index, end); }
            collectLoopReciprocals(g, f, n.a, input_locals, mandatory, index, end, budget);
            collectLoopReciprocals(g, f, n.b, input_locals, mandatory, index, end, budget);
        },
        suite, block_, product, record, array, array_op, storage, break_ => {
            for child in m.children(id) { collectLoopReciprocals(g, f, child, input_locals, mandatory, index, end, budget); }
        },
        bind, construct => { collectLoopReciprocals(g, f, n.b, input_locals, mandatory, index, end, budget); },
        return_, project => { collectLoopReciprocals(g, f, n.a, input_locals, mandatory, index, end, budget); },
        if_stmt, if_value, pattern_bind => {
            if n.tag != squid_check_core::Tag.pattern_bind { collectLoopReciprocals(g, f, n.a, input_locals, mandatory, index, end, budget); }
            collectLoopReciprocals(g, f, n.b, input_locals, mandatory, index, end, budget);
            collectLoopReciprocals(g, f, n.c, input_locals, mandatory, index, end, budget);
        },
        call => {
            let ci = m.call(id);
            for arg in ci.arguments { collectLoopReciprocals(g, f, arg, input_locals, mandatory, index, end, budget); }
        },
        match_ => {
            for input in m.matchInputs(id) { collectLoopReciprocals(g, f, input, input_locals, mandatory, index, end, budget); }
            for arm in m.matchArms(id) {
                collectLoopReciprocals(g, f, arm.guard_, input_locals, mandatory, index, end, budget);
                collectLoopReciprocals(g, f, arm.body, input_locals, mandatory, index, end, budget);
            }
        },
        update => {
            let info = m.updateInfo(id);
            collectLoopReciprocals(g, f, info.root, input_locals, mandatory, index, end, budget);
            for selector in m.updateSelectors(id) {
                if selector.kind == squid_check_core::UpdateKind.index {
                    collectLoopReciprocals(g, f, selector.index, input_locals, mandatory, index, end, budget);
                }
            }
            collectLoopReciprocals(g, f, info.value, input_locals, mandatory, index, end, budget);
        },
        _ => {},
    }
}

recursive fn emitLoopCore(
    g: Generator&,
    f: Fn&,
    id: u32,
    info: squid_check_core::LoopInfo,
    iteration: Vals,
    outgoing: Vals,
    slots: Words,
    has_index: bool,
    index: u32,
    end_loc: u32,
    has_source: bool,
    source: Val,
    source_view_base: u32,
    range_in: CheckedRange,
    unroll2: bool,
    input_locals: u32 = 0,
) -> Error {
    let m .= g.units[f.unit - 1];
    if has_source && tagOf(g, source.ty) == squid_direct_types::Tag.packed {
        return emitPackedLoopCore(g, f, id, info, iteration, outgoing, slots, index, end_loc, source);
    }
    if has_source && tagOf(g, source.ty) == squid_direct_types::Tag.seq {
        return emitSeqLoopCore(g, f, id, info, iteration, outgoing, slots, index, end_loc, source);
    }
    let carries = m.loopCarries(id);
    var range = range_in;
    if has_index { range.end_local = end_loc; }
    let reciprocal_mark = f.loop_reciprocals_len;
    let reciprocal_u64_mark = f.loop_reciprocals_u64_len;
    if input_locals != 0 && !has_source {
        var prefix_budget: i64 = 32;
        var mandatory: u32 = 0xffffffff;
        if info.pattern == 0 || m.pattern(info.pattern).tag == squid_check_core::PatternTag.bind {
            let first, _ = firstLoopDivision(g, f, m, info.body, input_locals, prefix_budget);
            var allocation_budget: i64 = 256;
            if first != 0 && bodyNoAlloc(g, f, m, info.body, allocation_budget) {
                mandatory = invariantDivisor(g, f, m, first, input_locals);
            }
        }
        var budget: i64 = 256;
        collectLoopReciprocals(g, f, info.body, input_locals, mandatory, if has_index { index } else { 0xffffffff }, end_loc, budget);
    }
    let exit = open(g, f, OP_block);
    let top = open(g, f, OP_loop);
    f.checked_elems_len = 0;
    if has_index {
        lget(g, index);
        lget(g, end_loc);
        op(g, OP_i32_ge_u);
        let opened = open(g, f, OP_if_);
        let assigned = assign(g, f, iteration, outgoing, id);
        if assigned != squid_direct_types::Error.none { f.loop_reciprocals_len = reciprocal_mark; f.loop_reciprocals_u64_len = reciprocal_u64_mark; return assigned; }
        br(g, f, OP_br, exit);
        close(g, f);
        let current = local32(g, f);
        range.index = current;
        lget(g, index);
        lset(g, current);
        lget(g, index);
        i32Const(g, 1);
        op(g, OP_i32_add);
        lset(g, index);
        var item = neverVal();
        if has_source {
            if source_view_base != 0xffffffff {
                let element, elem_err = elementOf(g, f, source.ty, id);
                if elem_err != squid_direct_types::Error.none { f.loop_reciprocals_len = reciprocal_mark; f.loop_reciprocals_u64_len = reciprocal_u64_mark; return elem_err; }
                let step, step_err = stride(g, f, element, id);
                if step_err != squid_direct_types::Error.none { f.loop_reciprocals_len = reciprocal_mark; f.loop_reciprocals_u64_len = reciprocal_u64_mark; return step_err; }
                let addr = local32(g, f);
                lget(g, source_view_base);
                let fast = open(g, f, OP_if_);
                let fast_addr = emitOffsetAddress(g, f, source_view_base, current, step);
                lget(g, fast_addr);
                lset(g, addr);
                popCheckedArraysAt(f, fast);
                op(g, OP_else_);
                let slow_addr, slow_err = elementAddress(g, f, source, current, id);
                if slow_err != squid_direct_types::Error.none { f.loop_reciprocals_len = reciprocal_mark; f.loop_reciprocals_u64_len = reciprocal_u64_mark; return slow_err; }
                lget(g, slow_addr);
                lset(g, addr);
                close(g, f);
                let loaded, lerr = loadElement(g, f, addr, 0, element, id);
                if lerr != squid_direct_types::Error.none { f.loop_reciprocals_len = reciprocal_mark; f.loop_reciprocals_u64_len = reciprocal_u64_mark; return lerr; }
                item = loaded;
            } else {
                let previous_range = f.checked_range;
                f.checked_range = range;
                let element, error = readElement(g, f, source, current, id);
                f.checked_range = previous_range;
                if error != squid_direct_types::Error.none { f.loop_reciprocals_len = reciprocal_mark; f.loop_reciprocals_u64_len = reciprocal_u64_mark; return error; }
                item = element;
            }
        } else { item = valOf1(g, squid_direct_types::u32_, current); }
        if info.pattern != 0 {
            let tested = test_(g, f, info.pattern, item, false, 0, id);
            if tested != squid_direct_types::Error.none { f.loop_reciprocals_len = reciprocal_mark; f.loop_reciprocals_u64_len = reciprocal_u64_mark; return tested; }
        }
    }
    var release = true;
    let s .= g.s;
    let scratch_mark = s.scratch.len;
    var boxed_carries = false;
    for at in 0..carries.len {
        if g.s.words[slots.start + at] != 0 { boxed_carries = true; continue; }
        let value = g.s.vals[iteration.start + at];
        let safe, error = ownerSlots(g, value.ty, value.start);
        if error != squid_direct_types::Error.none { s.scratch.resize(scratch_mark); f.loop_reciprocals_len = reciprocal_mark; f.loop_reciprocals_u64_len = reciprocal_u64_mark; return error; }
        if !safe { release = false; }
    }
    if release {
        if f.worker_spec >= 0 && g.s.worker_specs[f.worker_spec].no_scope_alloc {
            release = false;
        } else {
            var no_alloc_budget: i64 = 512;
            if bodyNoAlloc(g, f, m, info.body, no_alloc_budget) {
                release = false;
            }
        }
    }
    var unchanged: u32 = 0xffffffff;
    if release && boxed_carries { unchanged = local32(g, f); }
    let guards = Words { g.s.words.len as u32, (s.scratch.len - scratch_mark) as u32 };
    for at in scratch_mark..s.scratch.len { let slot = s.scratch[at]; g.s.words.push(slot); }
    s.scratch.resize(scratch_mark);
    let owner_mark = local32(g, f);
    let stack_mark = local32(g, f);
    let saved_esc = local32(g, f);
    let mark_at = s.code.len;
    let allocations = f.allocations;
    let stores = f.memory_stores;
    let unused = g.newSlot();
    let labels_mark = s.labels.len;
    s.labels.push(squid_direct_emit::Label { target: id, depth: exit, result: unused, kind: squid_direct_emit::LabelKind.loop_, top: top, iteration: iteration, outgoing: outgoing, unchanged: unchanged, has_release: release, release_owner: owner_mark, release_stack: stack_mark, allocations: allocations, slots: slots, saved_esc: saved_esc, guards: guards });
    let previous_range = f.checked_range;
    f.checked_range = range;
    f.loop_depth += 1;
    let body, error = stmt(g, f, info.body);
    f.checked_range = previous_range;
    if error != squid_direct_types::Error.none {
        f.loop_depth -= 1;
        s.labels.resize(labels_mark);
        f.loop_reciprocals_len = reciprocal_mark; f.loop_reciprocals_u64_len = reciprocal_u64_mark; return error;
    }
    let do_unroll2 = unroll2 && !release && !has_index && body.ty != squid_direct_types::never;
    if body.ty != squid_direct_types::never {
        let backedge = g.reserveVals(carries.len);
        for carry, at in carries {
            let value, present, rerr = readBindingVal(g, f, carry.backedge, id);
            if rerr != squid_direct_types::Error.none { f.loop_depth -= 1; s.labels.resize(labels_mark); f.loop_reciprocals_len = reciprocal_mark; f.loop_reciprocals_u64_len = reciprocal_u64_mark; return rerr; }
            if !present { f.loop_depth -= 1; s.labels.resize(labels_mark); f.loop_reciprocals_len = reciprocal_mark; f.loop_reciprocals_u64_len = reciprocal_u64_mark; return g.fail(m, id, "loop carry without a backedge value"); }
            g.s.vals[backedge.start + at] = value;
        }
        let assigned = assignCarries(g, f, backedge, iteration, slots, unchanged, owner_mark, stack_mark, id);
        if assigned != squid_direct_types::Error.none { f.loop_depth -= 1; s.labels.resize(labels_mark); f.loop_reciprocals_len = reciprocal_mark; f.loop_reciprocals_u64_len = reciprocal_u64_mark; return assigned; }
        if do_unroll2 {
            f.checked_elems_len = 0;
            f.checked_bounds_len = 0;
            let body2, err2 = stmt(g, f, info.body);
            if err2 != squid_direct_types::Error.none { f.loop_depth -= 1; s.labels.resize(labels_mark); f.loop_reciprocals_len = reciprocal_mark; f.loop_reciprocals_u64_len = reciprocal_u64_mark; return err2; }
            if body2.ty != squid_direct_types::never {
                let backedge2 = g.reserveVals(carries.len);
                for carry, at in carries {
                    let value, present, rerr = readBindingVal(g, f, carry.backedge, id);
                    if rerr != squid_direct_types::Error.none { f.loop_depth -= 1; s.labels.resize(labels_mark); f.loop_reciprocals_len = reciprocal_mark; f.loop_reciprocals_u64_len = reciprocal_u64_mark; return rerr; }
                    if !present { f.loop_depth -= 1; s.labels.resize(labels_mark); f.loop_reciprocals_len = reciprocal_mark; f.loop_reciprocals_u64_len = reciprocal_u64_mark; return g.fail(m, id, "loop carry without a backedge value"); }
                    g.s.vals[backedge2.start + at] = value;
                }
                let assigned2 = assignCarries(g, f, backedge2, iteration, slots, unchanged, owner_mark, stack_mark, id);
                if assigned2 != squid_direct_types::Error.none { f.loop_depth -= 1; s.labels.resize(labels_mark); f.loop_reciprocals_len = reciprocal_mark; f.loop_reciprocals_u64_len = reciprocal_u64_mark; return assigned2; }
                br(g, f, OP_br, top);
            }
        } else {
            let label = s.labels[labels_mark];
            if label.has_release && (f.allocations != allocations || label.used) {
                let iter_esc = local32(g, f);
                gget(g, g.runtime_().escape_min_slot);
                lset(g, iter_esc);
                if f.allocations != allocations && f.memory_stores == stores {
                    releaseIteration(g, f, label, iter_esc);
                }
                emitMergeEscapeMin(g, f, iter_esc, label.saved_esc);
            }
            br(g, f, OP_br, top);
        }
    }
    f.loop_depth -= 1;
    f.loop_reciprocals_len = reciprocal_mark; f.loop_reciprocals_u64_len = reciprocal_u64_mark;
    let label_final = s.labels[labels_mark];
    s.labels.resize(labels_mark);
    if release && (f.allocations != allocations || label_final.used) {
        var prefix: u8[>..<] = [];
        markInto(g, prefix, owner_mark, stack_mark);
        let esc_global = g.runtime_().escape_min_slot;
        prefix.push(OP_global_get);
        squid_direct_writer::uleb(prefix, esc_global);
        prefix.push(OP_local_set);
        squid_direct_writer::uleb(prefix, saved_esc);
        prefix.push(OP_i32_const);
        squid_direct_writer::sleb(prefix, -1);
        prefix.push(OP_global_set);
        squid_direct_writer::uleb(prefix, esc_global);
        squid_direct_relocations::insert(f.sites_base,mark_at,prefix.len);
        if g.s.parallel_readonly { squid_direct_emit::shiftParallelPatches(mark_at, prefix.len); }
        let old_len = s.code.len;
        for byte in prefix { s.code.push(byte); }
        var at = old_len;
        while at > mark_at {
            at -= 1;
            s.code[at + prefix.len] = s.code[at];
        }
        for byte, offset in prefix { s.code[mark_at + offset] = byte; }
    }
    close(g, f);
    close(g, f);
    return squid_direct_types::Error.none;
}
recursive fn loop_(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let info = g.units[f.unit - 1].loopInfo(id);
    if info.kind == squid_check_core::LoopKind.array && info.carries.len == 0 {
        let bulk_done, bulk_err = tryBulkPushLoop(g, f, id, info);
        if bulk_err != squid_direct_types::Error.none { return neverVal(), bulk_err; }
        if bulk_done { return unitVal(), squid_direct_types::Error.none; }
    }
    let input_locals = localCount(g, f);
    var iteration = Vals {};
    var outgoing = Vals {};
    var slots = Words {};
    var carry_in_place: bool[64] = [false; 64];
    var carry_mask_ok: bool[64] = [false; 64];
    var carry_mask_loc: u32[64] = [0xffffffff; 64];
    {
        let m .= g.units[f.unit - 1];
        let carries = m.loopCarries(id);
        let incoming = g.reserveVals(carries.len);
        for carry, at in carries {
            let value, present, rerr = readBindingVal(g, f, carry.incoming, id);
            if rerr != squid_direct_types::Error.none { return neverVal(), rerr; }
            if !present { return neverVal(), g.fail(m, id, "loop carry without an incoming value"); }
            g.s.vals[incoming.start + at] = value;
        }
        iteration = g.reserveVals(carries.len);
        outgoing = g.reserveVals(carries.len);
        // A boxed carry lives in a slot reserved before the loop, so each
        // iteration can release what it allocated.
        slots = Words { g.s.words.len as u32, carries.len as u32 };
        for carry in carries { g.s.words.push(0); }
        for at in 0..carries.len {
            let value = g.s.vals[incoming.start + at];
            let held, error = copiedBox(g, f, value.ty, id);
            if error != squid_direct_types::Error.none { return neverVal(), error; }
            let ctag = tagOf(g, value.ty);
            var in_place = false;
            if !held && isMutableOwnerTag(ctag) {
                if findWorkerR(f, w(g, value, 0), w(g, value, 1)) >= 0 ||
                    findWorkerM(f, w(g, value, 0), w(g, value, 1)) >= 0 {
                    in_place = true;
                } else {
                    var cbudget: i64 = 2048;
                    in_place = carryStaysInPlace(g, m, id, at, carries[at].iteration, carries[at].backedge, cbudget);
                }
            }
            if in_place {
                if at < 64 { carry_in_place[at] = true; }
                g.s.vals[iteration.start + at] = value;
                g.s.vals[outgoing.start + at] = value;
                continue;
            }
            if held {
                g.s.words[slots.start + at] = 1;
                let reserved, error = newBlock(g, f, value.ty, id);
                if error != squid_direct_types::Error.none { return neverVal(), error; }
                g.s.vals[iteration.start + at] = valOf1(g, value.ty, reserved);
            } else {
                let current, error = fresh(g, f, value.ty, id);
                if error != squid_direct_types::Error.none { return neverVal(), error; }
                g.s.vals[iteration.start + at] = current;
            }
            let after, error = fresh(g, f, value.ty, id);
            if error != squid_direct_types::Error.none { return neverVal(), error; }
            g.s.vals[outgoing.start + at] = after;
        }
        let assigned = assignCarries(g, f, incoming, iteration, slots, 0xffffffff, 0, 0, id);
        if assigned != squid_direct_types::Error.none { return neverVal(), assigned; }
        for carry, at in carries {
            bindPut(g, f, carry.iteration, g.s.vals[iteration.start + at]);
            if at < 64 && carry_in_place[at] {
                let da_idx = findDirectArray(f, carry.incoming);
                if da_idx >= 0 {
                    let da = f.direct_arrays[da_idx];
                    recordDirectArray(f, carry.iteration, da.slot_local, da.base, da.len_local, da.length, da.elem_ty, da.step, da.scalar_packed, da.pack_lo, da.pack_hi);
                }
            }
            // A copiedBox carry lives in a fresh loop-reserved block copied on
            // entry and backedge, so carry.iteration is always exclusively owned
            // for in-place FBIP when its sole read is a match/update.
            if g.s.words[slots.start + at] != 0 {
                squid_support_zigmap::put(g.s.map_pool, f.unique_boxed, carry.iteration, f.loop_depth + 2);
            } else if isUniqueBoxed(g, f, carry.incoming) && uses(g, f, carry.incoming) == 1 && !bindingCaptured(g, f, carry.incoming) {
                var bbudget: i64 = 256;
                if carryBackedgeIsUniqueBoxed(g, f, m, id, at, carry.iteration, carry.backedge, bbudget) {
                    squid_support_zigmap::put(g.s.map_pool, f.unique_boxed, carry.iteration, f.loop_depth + 2);
                }
            }
            if tagOf(g, g.s.vals[iteration.start + at].ty) == squid_direct_types::Tag.array &&
                isUniqueOwned(g, f, carry.incoming) &&
                ownedRefUses(g, f, carry.incoming) == 0 &&
                ownedFlowUses(g, f, carry.incoming) == 1 &&
                !bindingCaptured(g, f, carry.incoming) {
                var ubudget: i64 = 256;
                if carryBackedgeIsUniqueOwned(g, f, m, id, at, carry.iteration, carry.backedge, ubudget) {
                    squid_support_zigmap::put(g.s.map_pool, f.unique_owned, carry.iteration, f.loop_depth + 2);
                }
            }
        }
        // Propagate loop-invariant CheckedMask facts across U32 loop carries
        // (e.g. open-addressed probe `idx := (idx + 1) & mask` and backward-shift `j`/`i`).
        for pass in 0..2 {
            var ok_bs: u32[8] = [0; 8];
            for carry, at in carries {
                if at >= 64 || carry_in_place[at] || carry_mask_ok[at] { continue; }
                let inv = g.s.vals[incoming.start + at];
                let itv = g.s.vals[iteration.start + at];
                if inv.len != 1 || inv.ty != squid_direct_types::u32_ || itv.len != 1 { continue; }
                let cm = findCheckedMask(f, w(g, inv, 0));
                if cm < 0 { continue; }
                let mloc = f.checked_masks[cm].max_local;
                if mloc == 0xffffffff { continue; }
                var mloc_carried = false;
                for ci in 0..carries.len {
                    if hasWord(g, g.s.vals[iteration.start + ci], mloc) { mloc_carried = true; break; }
                }
                if mloc_carried { continue; }
                var ok_len: i64 = 0;
                ok_bs[ok_len] = carry.iteration; ok_len += 1;
                for ci in 0..carries.len {
                    if ci < 64 && carry_mask_ok[ci] && carry_mask_loc[ci] == mloc && ok_len < 8 {
                        ok_bs[ok_len] = carries[ci].iteration;
                        ok_len += 1;
                    }
                }
                var found = false;
                var valid = true;
                if carry.backedge == carry.iteration {
                    found = true;
                } else {
                    scanBindingMaskProof(g, f, m, info.body, info.body, carry.backedge, mloc, ok_bs, ok_len, found, valid, 0);
                }
                if found && valid {
                    carry_mask_ok[at] = true;
                    carry_mask_loc[at] = mloc;
                    recordCheckedMask(f, w(g, itv, 0), mloc, 0, false);
                }
            }
        }
    }
    if info.kind == squid_check_core::LoopKind.array {
        let unrolled, uerr = tryUnrollConstArrayLoop(g, f, id, info, iteration, outgoing, slots);
        if uerr != squid_direct_types::Error.none { return neverVal(), uerr; }
        if unrolled { return unitVal(), squid_direct_types::Error.none; }
    }
    let m .= g.units[f.unit - 1];
    let carries = m.loopCarries(id);
    var has_index = false;
    var index: u32 = 0;
    var end = neverVal();
    var has_source = false;
    var source = neverVal();
    var source_view_base: u32 = 0xffffffff;
    var range = CheckedRange {};
    var body_no_resize_budget: i64 = 2048;
    let body_no_resize = noStorageResize(g, m, info.body, body_no_resize_budget);
    var resized_bindings: u32[16] = [0; 16];
    var resized_len: i64 = 0;
    var selective_resize = body_no_resize;
    if !body_no_resize {
        var sel_budget: i64 = 2048;
        selective_resize = scanLoopResize(g, m, info.body, resized_bindings, resized_len, sel_budget);
        if selective_resize && resized_len > 0 {
            var prop_iter: i64 = 0;
            var prop_changed = true;
            while prop_changed && selective_resize && prop_iter < 16 {
                prop_changed = false;
                var pbudget: i64 = 2048;
                selective_resize = propagateResizedAliases(g, m, info.body, resized_bindings, resized_len, prop_changed, pbudget);
                if selective_resize {
                    for carry in carries {
                        if inResizedSet(resized_bindings, resized_len, carry.incoming) ||
                            inResizedSet(resized_bindings, resized_len, carry.iteration) ||
                            inResizedSet(resized_bindings, resized_len, carry.backedge) ||
                            inResizedSet(resized_bindings, resized_len, carry.outgoing) {
                            if !addResizedSetTracked(resized_bindings, resized_len, carry.incoming, prop_changed) ||
                                !addResizedSetTracked(resized_bindings, resized_len, carry.iteration, prop_changed) ||
                                !addResizedSetTracked(resized_bindings, resized_len, carry.backedge, prop_changed) ||
                                !addResizedSetTracked(resized_bindings, resized_len, carry.outgoing, prop_changed) {
                                selective_resize = false;
                                break;
                            }
                        }
                    }
                }
                prop_iter += 1;
            }
            if prop_changed { selective_resize = false; }
        }
        if selective_resize {
            for ri in 0..resized_len {
                let rv, rok = bindGet(g, f, resized_bindings[ri]);
                if rok && (tagOf(g, rv.ty) == squid_direct_types::Tag.array || tagOf(g, rv.ty) == squid_direct_types::Tag.packed || tagOf(g, rv.ty) == squid_direct_types::Tag.seq) {
                    invalidateCheckedOwner(g, f, rv);
                }
            }
            for carry, ci in carries {
                if bindingResizedInLoop(m, id, carry.iteration, resized_bindings, resized_len) {
                    let iv = g.s.vals[iteration.start + ci];
                    if tagOf(g, iv.ty) == squid_direct_types::Tag.array || tagOf(g, iv.ty) == squid_direct_types::Tag.packed || tagOf(g, iv.ty) == squid_direct_types::Tag.seq {
                        invalidateCheckedOwner(g, f, iv);
                    }
                    let inv, inok = bindGet(g, f, carry.incoming);
                    if inok && (tagOf(g, inv.ty) == squid_direct_types::Tag.array || tagOf(g, inv.ty) == squid_direct_types::Tag.packed || tagOf(g, inv.ty) == squid_direct_types::Tag.seq) {
                        invalidateCheckedOwner(g, f, inv);
                    }
                }
            }
            f.checked_views_len = 0;
            f.checked_elems_len = 0;
        } else {
            invalidateCheckedContainers(f);
        }
    }
    // An opaque body may write local slots on a handler exit. Treat
    // pre-loop facts as unknown on the backedge if the walk cannot rule it out.
    let reciprocal_inputs = if selective_resize { input_locals } else { 0 };
    if !selective_resize {
        f.const_u32_len = 0;
        // A handle's non-static status (`slot < persistent_split`) is invariant
        // as long as its (slot, gen) locals are not overwritten by a non-in-place
        // loop carry; drop only entries belonging to non-in-place carries.
        if carries.len > 64 {
            f.known_mutable_len = 0;
        } else if f.known_mutable_len != 0 {
            var kept: i64 = 0;
            for at in 0..f.known_mutable_len {
                let fact = f.known_mutable[at];
                var clobbered = false;
                for ci in 0..carries.len {
                    if carry_in_place[ci] { continue; }
                    let iv = g.s.vals[iteration.start + ci];
                    let ov = g.s.vals[outgoing.start + ci];
                    if hasWord(g, iv, fact.slot) || hasWord(g, iv, fact.generation) ||
                        hasWord(g, ov, fact.slot) || hasWord(g, ov, fact.generation) {
                        clobbered = true;
                        break;
                    }
                }
                if !clobbered {
                    f.known_mutable[kept] = fact;
                    kept += 1;
                }
            }
            f.known_mutable_len = kept;
        }
    }
    // Hoist pre-loop owner-table checks for guaranteed-live (`knownMutable`) arrays:
    // - `ensureCheckedGrow` for in-place carried arrays resized inside the loop, so
    //   every `push`/`extend`/`extend_view` inside the loop skips `runtime.check`.
    // - `ensureCheckedArray` for non-resized arrays read inside a `selective_resize` loop.
    if !g.runtime_().has_fork {
        for carry, ci in carries {
            if ci >= 64 || !carry_in_place[ci] { continue; }
            if findDirectArray(f, carry.incoming) >= 0 { continue; }
            let iv = g.s.vals[iteration.start + ci];
            if !isMutableOwnerTag(tagOf(g, iv.ty)) || !knownMutable(g, f, iv) { continue; }
            let s0 = w(g, iv, 0);
            let s1 = w(g, iv, 1);
            if findWorkerM(f, s0, s1) >= 0 || findWorkerR(f, s0, s1) >= 0 { continue; }
            if !body_no_resize && (!selective_resize || bindingResizedInLoop(m, id, carry.iteration, resized_bindings, resized_len)) {
                if findCheckedGrow(f, s0, s1) < 0 {
                    let _ = ensureCheckedGrow(g, f, iv);
                }
            } else if findCheckedArray(f, s0, s1) < 0 {
                let _, _ = ensureCheckedArray(g, f, iv);
            }
        }
        if selective_resize {
            var read_arrs: u32[4] = [0; 4];
            var read_len: i64 = 0;
            var rbud: i64 = 512;
            collectLoopReadArrays(m, info.body, read_arrs, read_len, rbud);
            for ri in 0..read_len {
                let rb = read_arrs[ri];
                if findDirectArray(f, rb) >= 0 { continue; }
                if bindingResizedInLoop(m, id, rb, resized_bindings, resized_len) { continue; }
                var is_mut_carry = false;
                for carry, ci in carries {
                    if (ci >= 64 || !carry_in_place[ci]) && (carry.iteration == rb || carry.backedge == rb) {
                        is_mut_carry = true;
                        break;
                    }
                }
                if is_mut_carry { continue; }
                let rv, rok = bindGet(g, f, rb);
                if !rok || !(tagOf(g, rv.ty) == squid_direct_types::Tag.array || tagOf(g, rv.ty) == squid_direct_types::Tag.seq) || !knownMutable(g, f, rv) { continue; }
                let s0 = w(g, rv, 0);
                let s1 = w(g, rv, 1);
                for ci in 0..carries.len {
                    if ci < 64 && carry_in_place[ci] { continue; }
                    let iv = g.s.vals[iteration.start + ci];
                    if hasWord(g, iv, s0) || hasWord(g, iv, s1) { is_mut_carry = true; break; }
                }
                if is_mut_carry { continue; }
                if findWorkerR(f, s0, s1) >= 0 || findCheckedArray(f, s0, s1) >= 0 { continue; }
                let _, _ = ensureCheckedArray(g, f, rv);
            }
        }
    }
    match info.kind {
        forever => {},
        range => {
            has_index = true;
            index = local32(g, f);
            let first, error = expr(g, f, info.first);
            if error != squid_direct_types::Error.none { return first, error; }
            let copied = copy(g, f, first, valOf1(g, squid_direct_types::u32_, index), id);
            if copied != squid_direct_types::Error.none { return neverVal(), copied; }
            let handle, is_view = rangeOwner(g, f, id, info, selective_resize, resized_bindings, resized_len);
            if handle.ty != squid_direct_types::never && !is_view {
                let base, len = ensureCheckedArray(g, f, handle);
                end = valOf1(g, squid_direct_types::u32_, len);
                range.slot = w(g, handle, 0);
                range.generation = w(g, handle, 1);
                range.base = base;
                range.end_local = len;
            } else if handle.ty != squid_direct_types::never && is_view {
                let vslot = w(g, handle, 0);
                let vgen = w(g, handle, 1);
                let vstart = w(g, handle, 2);
                let vlen = w(g, handle, 3);
                end = valOf1(g, squid_direct_types::u32_, vlen);
                let element, elem_err = elementOf(g, f, handle.ty, id);
                if elem_err != squid_direct_types::Error.none { return neverVal(), elem_err; }
                let step, step_err = stride(g, f, element, id);
                if step_err != squid_direct_types::Error.none { return neverVal(), step_err; }
                let cv = findCheckedView(f, vslot, vgen, vstart, vlen);
                if cv >= 0 {
                    range.base = f.checked_views[cv].base;
                    range.trusted_view = true;
                } else {
                    range.base = tryHoistViewBase(g, f, vslot, vgen, vstart, vlen, step, false);
                }
                range.slot = vslot;
                range.generation = vgen;
                range.end_local = vlen;
                range.is_view = true;
                range.view_start = vstart;
            } else {
                let last, error = expr(g, f, info.end);
                if error != squid_direct_types::Error.none { return last, error; }
                let end_ref = localRef(m, info.end);
                var reuse_end = false;
                if end_ref != 0 {
                    let _, is_cell = withCellType(g, f, end_ref);
                    if !is_cell {
                        reuse_end = true;
                        for carry in carries {
                            if carry.incoming == end_ref || carry.iteration == end_ref {
                                reuse_end = false;
                                break;
                            }
                        }
                    }
                }
                if reuse_end {
                    end = last;
                    range.end_local = w(g, last, 0);
                } else {
                    let limit, error = fresh(g, f, squid_direct_types::u32_, id);
                    if error != squid_direct_types::Error.none { return neverVal(), error; }
                    end = limit;
                    let copied = copy(g, f, last, end, id);
                    if copied != squid_direct_types::Error.none { return neverVal(), copied; }
                    let fact, known = constU32(f, w(g, last, 0));
                    if known { recordConstU32(f, w(g, end, 0), fact.value, fact.unit, fact.node); }
                }
            }
            range.length_ty = rangeSizedLength(g, f, info);
        },
        array => {
            let container, error = expr(g, f, info.first);
            if error != squid_direct_types::Error.none { return container, error; }
            has_source = true;
            source = container;
            has_index = true;
            index = constLocal(g, f, 0);
            let length, error = lengthOf(g, f, source, id);
            if error != squid_direct_types::Error.none { return neverVal(), error; }
            end = valOf1(g, squid_direct_types::u32_, length);
            if tagOf(g, source.ty) == squid_direct_types::Tag.array {
                let base, len = ensureCheckedArray(g, f, source);
                range.slot = w(g, source, 0);
                range.generation = w(g, source, 1);
                range.base = base;
                range.end_local = len;
            } else if tagOf(g, source.ty) == squid_direct_types::Tag.view {
                let vslot = w(g, source, 0);
                let vgen = w(g, source, 1);
                let vstart = w(g, source, 2);
                let vlen = w(g, source, 3);
                let element, elem_err = elementOf(g, f, source.ty, id);
                if elem_err != squid_direct_types::Error.none { return neverVal(), elem_err; }
                let step, step_err = stride(g, f, element, id);
                if step_err != squid_direct_types::Error.none { return neverVal(), step_err; }
                let cv = findCheckedView(f, vslot, vgen, vstart, vlen);
                if cv >= 0 {
                    range.slot = vslot;
                    range.generation = vgen;
                    range.base = f.checked_views[cv].base;
                    range.end_local = vlen;
                    range.is_view = true;
                    range.trusted_view = true;
                    range.view_start = vstart;
                } else {
                    var budget: i64 = 256;
                    let static_safe = noStorageResize(g, m, info.body, budget);
                    let vbase = tryHoistViewBase(g, f, vslot, vgen, vstart, vlen, step, !static_safe);
                    source_view_base = vbase;
                }
            }
        },
    }
    if selective_resize && f.checked_arrays_len < 14 {
        var hoist_ids: u32[16] = [0; 16];
        var hoist_len: i64 = 0;
        var hoist_budget: i64 = 2048;
        collectLoopArrayUses(m, info.body, hoist_ids, hoist_len, hoist_budget);
        for hi in 0..hoist_len {
            let b = hoist_ids[hi];
            var mutating_carry = false;
            for carry, ci in carries {
                if carry.iteration == b && (ci >= 64 || !carry_in_place[ci]) {
                    mutating_carry = true;
                    break;
                }
            }
            if mutating_carry { continue; }
            let val, found = bindGet(g, f, b);
            if !found || !isMutableOwnerTag(tagOf(g, val.ty)) { continue; }
            if findDirectArray(f, b) >= 0 || findDirectArrayBySlot(f, w(g, val, 0)) >= 0 { continue; }
            if bindingResizedInLoop(m, id, b, resized_bindings, resized_len) {
                if f.checked_grows_len < 8 {
                    let _ = ensureCheckedGrow(g, f, val);
                }
                continue;
            }
            if f.checked_arrays_len >= 14 { continue; }
            if findCheckedArray(f, w(g, val, 0), w(g, val, 1)) >= 0 { continue; }
            let _ec1, _ec2 = ensureCheckedArray(g, f, val);
        }
        // Also hoist in-place array carries directly (a `self`-rebinding like
        // `arr := self.push x` references the inner synthetic `self` binding
        // rather than `carry.iteration`, so `collectLoopArrayUses` won't find
        // `carry.iteration` by binding ID before the body is emitted).
        for carry, ci in carries {
            if ci >= 64 || !carry_in_place[ci] { continue; }
            let iv = g.s.vals[iteration.start + ci];
            if !isMutableOwnerTag(tagOf(g, iv.ty)) { continue; }
            if findDirectArray(f, carry.incoming) >= 0 || findDirectArrayBySlot(f, w(g, iv, 0)) >= 0 { continue; }
            if bindingResizedInLoop(m, id, carry.iteration, resized_bindings, resized_len) {
                if f.checked_grows_len < 8 {
                    let _ = ensureCheckedGrow(g, f, iv);
                }
            } else if f.checked_arrays_len < 14 && findCheckedArray(f, w(g, iv, 0), w(g, iv, 1)) < 0 {
                let _ec1, _ec2 = ensureCheckedArray(g, f, iv);
            }
        }
    }
    if body_no_resize && info.kind == squid_check_core::LoopKind.range {
        let matmul2_err = tryEmitBlockedMatmulRowLoop(g, f, id, info, carry_in_place, index, w(g, end, 0));
        if matmul2_err != squid_direct_types::Error.none { return neverVal(), matmul2_err; }
        let matmul_err = tryEmitBlockedMatmulKLoop(g, f, id, info, carry_in_place, index, w(g, end, 0));
        if matmul_err != squid_direct_types::Error.none { return neverVal(), matmul_err; }
        let v3_err = tryEmitVec3MaybeLoop4x(g, f, id, info, carry_in_place, index, w(g, end, 0));
        if v3_err != squid_direct_types::Error.none { return neverVal(), v3_err; }
        let aos_err = tryEmitAosF32RecordLoop(g, f, id, info, carry_in_place, index, w(g, end, 0));
        if aos_err != squid_direct_types::Error.none { return neverVal(), aos_err; }
        let vec_err = tryEmitVectorForLoop(g, f, id, info, carry_in_place, index, w(g, end, 0));
        if vec_err != squid_direct_types::Error.none { return neverVal(), vec_err; }
        let ainit_err = tryEmitAffineInitLoop(g, f, id, info, iteration, carry_in_place, index, w(g, end, 0));
        if ainit_err != squid_direct_types::Error.none { return neverVal(), ainit_err; }
        let red_err = tryEmitVectorReductionLoop(g, f, id, info, iteration, carry_in_place, index, w(g, end, 0));
        if red_err != squid_direct_types::Error.none { return neverVal(), red_err; }
        let v3r_err = tryEmitVec3MaybeReductionLoop(g, f, id, info, iteration, carry_in_place, index, w(g, end, 0));
        if v3r_err != squid_direct_types::Error.none { return neverVal(), v3r_err; }
        let esc_err = tryEmitVectorEscapeLoop(g, f, id, info, iteration, carry_in_place, index, w(g, end, 0));
        if esc_err != squid_direct_types::Error.none { return neverVal(), esc_err; }
        let aff_err = tryEmitAffineUnrollLoop(g, f, id, info, iteration, index, w(g, end, 0));
        if aff_err != squid_direct_types::Error.none { return neverVal(), aff_err; }
    }
    var copy_tail_done = false;
    if body_no_resize && info.kind == squid_check_core::LoopKind.forever {
        let sf_err = tryEmitStridedFillLoop(g, f, id, info, iteration, carry_in_place);
        if sf_err != squid_direct_types::Error.none { return neverVal(), sf_err; }
        let ct_done, ct_err = tryEmitCopyTailLoop(g, f, id, info, iteration, carry_in_place);
        if ct_err != squid_direct_types::Error.none { return neverVal(), ct_err; }
        copy_tail_done = ct_done;
    }
    // Preserve CheckedArray entries for non-resizing in-place carries across OP_loop
    // (assignCarries at the loop backedge writes to the same handle locals and would
    // otherwise clear pre-loop CheckedArray descriptors after loop exit).
    var saved_ca_slot: u32[16] = [0; 16];
    var saved_ca_gen: u32[16] = [0; 16];
    var saved_ca_base: u32[16] = [0; 16];
    var saved_ca_len: u32[16] = [0; 16];
    var saved_ca_depth: u32[16] = [0; 16];
    var saved_ca_count: i64 = 0;
    if selective_resize {
        for at in 0..carries.len {
            if at >= 64 || !carry_in_place[at] || saved_ca_count >= 16 { continue; }
            if bindingResizedInLoop(m, id, carries[at].iteration, resized_bindings, resized_len) { continue; }
            let ov = g.s.vals[outgoing.start + at];
            if !isMutableOwnerTag(tagOf(g, ov.ty)) { continue; }
            let ca = findCheckedArray(f, w(g, ov, 0), w(g, ov, 1));
            if ca >= 0 {
                saved_ca_slot[saved_ca_count] = w(g, ov, 0);
                saved_ca_gen[saved_ca_count] = w(g, ov, 1);
                saved_ca_base[saved_ca_count] = f.checked_arrays[ca].base;
                saved_ca_len[saved_ca_count] = f.checked_arrays[ca].length;
                saved_ca_depth[saved_ca_count] = f.checked_arrays[ca].depth;
                saved_ca_count += 1;
            }
        }
    }

    // 4A: Deferred NaN canonicalization on pure-FP counted loops (`0..end-1` fast, final iter canonical).
    var emitted_loop = false;
    if body_no_resize && !f.defer_f32_nan && !g.runtime_().has_fork && info.kind == squid_check_core::LoopKind.range &&
        canDeferLoopF32Nan(g, f, g.units[f.unit - 1], id, info) {
        let end_loc = w(g, end, 0);
        let fast_end = local32(g, f);
        lget(g, end_loc);
        lget(g, index);
        op(g, OP_i32_gt_u);
        let fe_if = open(g, f, OP_if_);
        lget(g, end_loc);
        i32Const(g, 1);
        op(g, OP_i32_sub);
        lset(g, fast_end);
        popCheckedArraysAt(f, fe_if);
        op(g, OP_else_);
        lget(g, index);
        lset(g, fast_end);
        close(g, f);

        f.defer_f32_nan = true;
        var ind_lens: u32[4] = [0; 4];
        var ind_len_count: i64 = 0;
        let has_ind, ind_arr_b, ind_m_node, ind_id_b = tryMatchIndirectIndexScan(g, f, g.units[f.unit - 1], info.body, ind_lens, ind_len_count);
        if has_ind && !f.in_specialized_loop {
            let ind_av, _ = bindGet(g, f, ind_arr_b);
            let ind_ca = findCheckedArray(f, w(g, ind_av, 0), w(g, ind_av, 1));
            let ind_base = f.checked_arrays[ind_ca].base;
            let ind_arr_len = f.checked_arrays[ind_ca].length;
            let ind_mv, imerr = expr(g, f, ind_m_node);
            if imerr != squid_direct_types::Error.none { f.defer_f32_nan = false; return neverVal(), imerr; }
            let ind_m = w(g, ind_mv, 0);
            let min_len = local32(g, f);
            lget(g, ind_lens[0]);
            lset(g, min_len);
            for ti in 1..ind_len_count {
                lget(g, min_len);
                lget(g, ind_lens[ti]);
                lget(g, min_len);
                lget(g, ind_lens[ti]);
                op(g, OP_i32_lt_u);
                op(g, OP_select);
                lset(g, min_len);
            }
            let all_ok = constLocal(g, f, 0);
            // 0 = unsorted/duplicate, 1 = strictly increasing (distinct), 2 = strictly contiguous (ids[k] == ids[0] + k)
            let all_distinct = constLocal(g, f, 0);
            let prev_id = constLocal(g, f, 0);
            let cur_id = local32(g, f);
            lget(g, ind_m);
            lget(g, ind_arr_len);
            op(g, OP_i32_le_u);
            let scan_if = open(g, f, OP_if_);
            i32Const(g, 1);
            lset(g, all_ok);
            i32Const(g, 2);
            lset(g, all_distinct);
            let scan_k = constLocal(g, f, 0);
            let s_exit = open(g, f, OP_block);
            let s_top = open(g, f, OP_loop);
            lget(g, scan_k);
            lget(g, ind_m);
            op(g, OP_i32_ge_u);
            br(g, f, OP_br_if, s_exit);
            lget(g, ind_base);
            lget(g, scan_k);
            i32Const(g, 2);
            op(g, OP_i32_shl);
            op(g, OP_i32_add);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);
            ltee(g, cur_id);
            lget(g, min_len);
            op(g, OP_i32_ge_u);
            let bad_if = open(g, f, OP_if_);
            i32Const(g, 0);
            lset(g, all_ok);
            i32Const(g, 0);
            lset(g, all_distinct);
            br(g, f, OP_br, s_exit);
            close(g, f);
            // Classify monotonicity for 6A Shape 2:
            // - if cur_id <= prev_id => 0 (unsorted/duplicate)
            // - else if cur_id - prev_id != 1 => demote 2 -> 1 (strictly increasing, non-contiguous)
            lget(g, scan_k);
            i32Const(g, 0);
            op(g, OP_i32_gt_u);
            let cmp_if = open(g, f, OP_if_);
            lget(g, cur_id);
            lget(g, prev_id);
            op(g, OP_i32_le_u);
            let dup_if = open(g, f, OP_if_);
            i32Const(g, 0);
            lset(g, all_distinct);
            popCheckedArraysAt(f, dup_if);
            op(g, OP_else_);
            lget(g, cur_id);
            lget(g, prev_id);
            op(g, OP_i32_sub);
            i32Const(g, 1);
            op(g, OP_i32_ne);
            lget(g, all_distinct);
            i32Const(g, 2);
            op(g, OP_i32_eq);
            op(g, OP_i32_and);
            let gap_if = open(g, f, OP_if_);
            i32Const(g, 1);
            lset(g, all_distinct);
            close(g, f);
            close(g, f);
            close(g, f);
            lget(g, cur_id);
            lset(g, prev_id);
            lget(g, scan_k);
            i32Const(g, 1);
            op(g, OP_i32_add);
            lset(g, scan_k);
            br(g, f, OP_br, s_top);
            close(g, f);
            close(g, f);
            popCheckedArraysAt(f, scan_if);
            close(g, f);

            let prev_spec = f.in_specialized_loop;
            let prev_ib = f.indirect_bound_binding;
            let prev_il = f.indirect_bound_len;
            let prev_id_loc = f.indirect_bound_distinct_local;
            f.in_specialized_loop = true;
            lget(g, all_ok);
            let ind_if = open(g, f, OP_if_);
            for ti in 0..ind_len_count { recordCheckedLe(f, min_len, ind_lens[ti]); }
            f.indirect_bound_binding = ind_id_b;
            f.indirect_bound_len = min_len;
            f.indirect_bound_distinct_local = all_distinct;
            let err1a = emitLoopCore(g, f, id, info, iteration, outgoing, slots, has_index, index, fast_end, has_source, source, source_view_base, range, false, reciprocal_inputs);
            f.indirect_bound_binding = prev_ib;
            f.indirect_bound_len = prev_il;
            f.indirect_bound_distinct_local = prev_id_loc;
            if err1a != squid_direct_types::Error.none { f.in_specialized_loop = prev_spec; f.defer_f32_nan = false; return neverVal(), err1a; }
            popCheckedArraysAt(f, ind_if);
            op(g, OP_else_);
            let err1b = emitLoopCore(g, f, id, info, iteration, outgoing, slots, has_index, index, fast_end, has_source, source, source_view_base, range, false, reciprocal_inputs);
            f.in_specialized_loop = prev_spec;
            if err1b != squid_direct_types::Error.none { f.defer_f32_nan = false; return neverVal(), err1b; }
            close(g, f);
        } else {
            let err1 = emitLoopCore(g, f, id, info, iteration, outgoing, slots, has_index, index, fast_end, has_source, source, source_view_base, range, false, reciprocal_inputs);
            if err1 != squid_direct_types::Error.none { f.defer_f32_nan = false; return neverVal(), err1; }
        }
        f.defer_f32_nan = false;
        let err2 = emitLoopCore(g, f, id, info, iteration, outgoing, slots, has_index, index, end_loc, has_source, source, source_view_base, range, false, reciprocal_inputs);
        if err2 != squid_direct_types::Error.none { return neverVal(), err2; }
        emitted_loop = true;
    }

    // 5A: 2-way merge loop with invariant `k < dst_len` + `mid, hi <= src_len` bounds hoisting.
    if !emitted_loop && body_no_resize && info.kind == squid_check_core::LoopKind.forever && !copy_tail_done {
        let fm_done, fm_err = tryEmitFastMergeLoop(g, f, id, info, iteration, outgoing, slots, range, carry_in_place);
        if fm_err != squid_direct_types::Error.none { return neverVal(), fm_err; }
        if fm_done { emitted_loop = true; }
    }

    // 4B-2: Pre-loop `CheckedLe` / masked / affine / converging-2ptr bounds hoisting.
    if !emitted_loop && body_no_resize && !g.runtime_().has_fork && !f.in_specialized_loop && f.spec_loop_depth < 2 && !copy_tail_done {
        var le_a: u32[4] = [0; 4];
        var le_b: u32[4] = [0; 4];
        var le_count: i64 = 0;
        var lt_a: u32[4] = [0; 4];
        var lt_b: u32[4] = [0; 4];
        var lt_count: i64 = 0;
        var aff_base: u32[4] = [0; 4];
        var aff_c: u32[4] = [0; 4];
        var aff_len: u32[4] = [0; 4];
        var aff_count: i64 = 0;
        var extra_bnd_a: u32[8] = [0; 8];
        var extra_bnd_b: u32[8] = [0; 8];
        var extra_bnd_count: i64 = 0;
        let max_pre_nodes: i64 = if f.spec_loop_depth == 0 { 144 } else { 48 };
        collectLoopPreBounds(g, f, g.units[f.unit - 1], id, info, range, le_a, le_b, le_count, lt_a, lt_b, lt_count, aff_base, aff_c, aff_len, aff_count, extra_bnd_a, extra_bnd_b, extra_bnd_count, max_pre_nodes);
        // Zero-duplication proof for `mask == arr.len - 1` when `arr` is unconditionally
        // indexed at entry of a `for ever` loop: `if arr.len == 0 { trap }` proves `mask < arr.len`!
        if info.kind == squid_check_core::LoopKind.forever && lt_count > 0 && extra_bnd_count == 0 {
            var kept_lt: i64 = 0;
            for li in 0..lt_count {
                let mloc = lt_a[li];
                let clen = lt_b[li];
                var proved = false;
                if findCheckedSub1(f, mloc, clen) >= 0 {
                    // Find which array binding owns `clen` and check unconditional indexing at loop entry.
                    for ca_i in 0..f.checked_arrays_len {
                        let cae = f.checked_arrays[ca_i];
                        if cae.length != clen { continue; }
                        let mm .= g.units[f.unit - 1];
                        // Check if any array indexed at loop entry maps to (cae.slot, cae.generation).
                        let bn = mm.node(info.body);
                        if bn.tag == squid_check_core::Tag.suite || bn.tag == squid_check_core::Tag.block_ {
                            let ch = mm.children(info.body);
                            let lim = if ch.len < 3 { ch.len } else { 3 };
                            for si in 0..lim {
                                let sn = mm.node(ch[si]);
                                var ab: u32 = 0;
                                if (sn.tag == squid_check_core::Tag.bind && sn.c < 2) || sn.tag == squid_check_core::Tag.pattern_bind {
                                    let rn = mm.node(sn.b);
                                    if rn.tag == squid_check_core::Tag.array_op && mm.arrayOperation(sn.b) == squid_backend_collection_ops::Op.get {
                                        let ach = mm.children(sn.b);
                                        if ach.len == 2 { ab = localRef(mm, ach[0]); }
                                    } else if rn.tag == squid_check_core::Tag.storage {
                                        let op_k, ok = squid_check_storage_ops::opFromCode(rn.c);
                                        let ach = mm.children(sn.b);
                                        if ok == squid_error::Error.none && op_k == squid_check_storage_ops::Op.read && ach.len == 2 { ab = localRef(mm, ach[0]); }
                                    }
                                }
                                if ab != 0 && loopUnconditionallyIndexesArr(mm, info.body, ab) {
                                    let av, aok = bindGet(g, f, ab);
                                    if aok && tagOf(g, av.ty) == squid_direct_types::Tag.array &&
                                        w(g, av, 0) == cae.slot && w(g, av, 1) == cae.generation {
                                        lget(g, clen);
                                        op(g, OP_i32_eqz);
                                        trapBounds(g, f, id);
                                        recordCheckedBound(f, mloc, clen);
                                        proved = true;
                                        break;
                                    }
                                }
                            }
                        }
                        if proved { break; }
                    }
                }
                if !proved {
                    lt_a[kept_lt] = mloc;
                    lt_b[kept_lt] = clen;
                    kept_lt += 1;
                }
            }
            lt_count = kept_lt;
        }
        if le_count > 0 || lt_count > 0 || aff_count > 0 {
            var cond_emitted = false;
            for li in 0..le_count {
                lget(g, le_a[li]);
                lget(g, le_b[li]);
                op(g, OP_i32_le_u);
                if cond_emitted { op(g, OP_i32_and); }
                cond_emitted = true;
            }
            for li in 0..lt_count {
                lget(g, lt_a[li]);
                lget(g, lt_b[li]);
                op(g, OP_i32_lt_u);
                if cond_emitted { op(g, OP_i32_and); }
                cond_emitted = true;
            }
            var prev_aff_clen: u32 = 0xffffffff;
            var prev_aff_rem: u32 = 0;
            for ai in 0..aff_count {
                // Overflow-free check: end <= clen && (cv == 0 || cv <= clen - end) && base <= (clen - end - cv).
                let clen = aff_len[ai];
                let end_l = range.end_local;
                let cv = aff_c[ai];
                var rem1: u32 = 0;
                if clen == prev_aff_clen {
                    rem1 = prev_aff_rem;
                } else {
                    lget(g, end_l);
                    lget(g, clen);
                    op(g, OP_i32_le_u);
                    if cond_emitted { op(g, OP_i32_and); }
                    cond_emitted = true;
                    rem1 = local32(g, f);
                    lget(g, clen);
                    lget(g, end_l);
                    op(g, OP_i32_sub);
                    lset(g, rem1);
                    prev_aff_clen = clen;
                    prev_aff_rem = rem1;
                }
                if cv != 0 {
                    lget(g, rem1);
                    i32Const(g, cv);
                    op(g, OP_i32_ge_u);
                    op(g, OP_i32_and);
                }
                if aff_base[ai] != 0xffffffff {
                    lget(g, aff_base[ai]);
                    lget(g, rem1);
                    if cv != 0 {
                        i32Const(g, cv);
                        op(g, OP_i32_sub);
                    }
                    op(g, OP_i32_le_u);
                    op(g, OP_i32_and);
                }
            }
            let prev_spec_depth = f.spec_loop_depth;
            f.spec_loop_depth = prev_spec_depth + 1;
            var end_loc: u32 = 0;
            if has_index { end_loc = w(g, end, 0); }
            let spec_if = open(g, f, OP_if_);
            for li in 0..le_count { recordCheckedLe(f, le_a[li], le_b[li]); }
            for li in 0..lt_count { recordCheckedBound(f, lt_a[li], lt_b[li]); }
            for ei in 0..extra_bnd_count { recordCheckedBound(f, extra_bnd_a[ei], extra_bnd_b[ei]); }
            for ai in 0..aff_count { recordCheckedAffine(f, aff_base[ai], range.end_local, aff_c[ai], aff_len[ai]); }
            let ferr = emitLoopCore(g, f, id, info, iteration, outgoing, slots, has_index, index, end_loc, has_source, source, source_view_base, range, false, reciprocal_inputs);
            if ferr != squid_direct_types::Error.none { f.spec_loop_depth = prev_spec_depth; return neverVal(), ferr; }
            popCheckedArraysAt(f, spec_if);
            op(g, OP_else_);
            let serr = emitLoopCore(g, f, id, info, iteration, outgoing, slots, has_index, index, end_loc, has_source, source, source_view_base, range, false, reciprocal_inputs);
            f.spec_loop_depth = prev_spec_depth;
            if serr != squid_direct_types::Error.none { return neverVal(), serr; }
            close(g, f);
            emitted_loop = true;
        }
    }

    if !emitted_loop {
        var end_loc: u32 = 0;
        if has_index { end_loc = w(g, end, 0); }
        var do_unroll2 = false;
        if body_no_resize && !g.runtime_().has_fork && !f.in_specialized_loop && info.kind == squid_check_core::LoopKind.forever && !has_index {
            do_unroll2 = isPureScalarForeverBody(g, g.units[f.unit - 1], info.body);
        }
        let cerr = emitLoopCore(g, f, id, info, iteration, outgoing, slots, has_index, index, end_loc, has_source, source, source_view_base, range, do_unroll2, reciprocal_inputs);
        if cerr != squid_direct_types::Error.none { return neverVal(), cerr; }
    }
    for sci in 0..saved_ca_count {
        recordCheckedArrayAtDepth(f, saved_ca_slot[sci], saved_ca_gen[sci], saved_ca_base[sci], saved_ca_len[sci], saved_ca_depth[sci]);
    }
    for carry, at in carries {
        let ov = g.s.vals[outgoing.start + at];
        bindPut(g, f, carry.outgoing, ov);
        if ov.len == 1 && ov.ty == squid_direct_types::u32_ {
            if at < 64 && carry_mask_ok[at] {
                recordCheckedMask(f, w(g, ov, 0), carry_mask_loc[at], 0, false);
            } else {
                let iv = g.s.vals[iteration.start + at];
                let cm = findCheckedMask(f, w(g, iv, 0));
                if cm >= 0 {
                    let me = f.checked_masks[cm];
                    recordCheckedMask(f, w(g, ov, 0), me.max_local, me.max_const, me.has_const);
                }
            }
        }
        if at < 64 && carry_in_place[at] {
            let da_idx = findDirectArray(f, carry.incoming);
            if da_idx >= 0 {
                let da = f.direct_arrays[da_idx];
                recordDirectArray(f, carry.outgoing, da.slot_local, da.base, da.len_local, da.length, da.elem_ty, da.step, da.scalar_packed, da.pack_lo, da.pack_hi);
            }
        }
        if isUniqueOwnedAt(g, f, carry.iteration, f.loop_depth + 1) {
            var others_in_place = true;
            for oi in 0..carries.len {
                if oi != at && tagOf(g, g.s.vals[outgoing.start + oi].ty) == squid_direct_types::Tag.array {
                    if oi >= 64 || !carry_in_place[oi] { others_in_place = false; break; }
                }
            }
            if others_in_place {
                squid_support_zigmap::put(g.s.map_pool, f.unique_owned, carry.outgoing, f.loop_depth + 1);
            }
        }
    }
    if info.kind == squid_check_core::LoopKind.forever && !info.can_exit { return neverVal(), squid_direct_types::Error.none; }
    return unitVal(), squid_direct_types::Error.none;
}
// Merges `min_u(cur_esc, saved_esc)` back into `rt.escape_min_slot`.
fn emitMergeEscapeMin(g: Generator&, f: Fn&, cur_esc: u32, saved_esc: u32) {
    let rt = g.runtime_();
    lget(g, cur_esc);
    lget(g, saved_esc);
    lget(g, cur_esc);
    lget(g, saved_esc);
    op(g, OP_i32_lt_u);
    op(g, OP_select);
    gset(g, rt.escape_min_slot);
}
fn emitMergeEscapeMinCurrent(g: Generator&, f: Fn&, saved_esc: u32) {
    let cur_esc = local32(g, f);
    gget(g, g.runtime_().escape_min_slot);
    lset(g, cur_esc);
    emitMergeEscapeMin(g, f, cur_esc, saved_esc);
}
// Records a store into an untracked cell/effect, conservatively escaping to age 0.
fn noteStore(g: Generator&, f: Fn&, value: Val) -> Error {
    if value.ty == squid_direct_types::never { return squid_direct_types::Error.none; }
    let holds, error = g.contentsHoldMemory(value.ty);
    if error != squid_direct_types::Error.none { return error; }
    if holds {
        f.memory_stores += 1;
        i32Const(g, 0);
        gset(g, g.runtime_().escape_min_slot);
    }
    return squid_direct_types::Error.none;
}
// Collect byte offsets of plain-element owner/view handles inside the flat memory
// layout of a non-recursive copied-box value (`copiedBox == true`). Returns `false`
// if any memory-holding part is recursive, nested-owner, closure, multi-variant sum,
// or exceeds the fixed 16-slot buffer.
recursive fn collectFlatPlainOwnerOffsets(g: Generator&, ty: Ty, base_off: u32, out: u32[16]&, out_len: i64&) -> bool, Error {
    let holds, error = g.contentsHoldMemory(ty);
    if error != squid_direct_types::Error.none { return false, error; }
    if !holds { return true, squid_direct_types::Error.none; }
    let rec, rerr = g.types.isRecursive(ty);
    if rerr != squid_direct_types::Error.none { return false, rerr; }
    if rec { return false, squid_direct_types::Error.none; }
    let n = g.types.node(ty);
    match n.tag {
        array, packed, seq, view, ref, link => {
            let elem_holds, herr = g.contentsHoldMemory(n.a);
            if herr != squid_direct_types::Error.none { return false, herr; }
            if elem_holds || out_len >= 16 { return false, squid_direct_types::Error.none; }
            out[out_len] = base_off;
            out_len += 1;
            return true, squid_direct_types::Error.none;
        },
        tuple => {
            for index in 0..(n.b as i64) {
                let item = g.types.words[n.a + index];
                let ioff, ierr = g.types.tupleItemByteOffset(ty, index);
                if ierr != squid_direct_types::Error.none { return false, ierr; }
                let ok, oerr = collectFlatPlainOwnerOffsets(g, item, base_off + ioff, out, out_len);
                if oerr != squid_direct_types::Error.none { return false, oerr; }
                if !ok { return false, squid_direct_types::Error.none; }
            }
            return true, squid_direct_types::Error.none;
        },
        record => {
            for index in 0..(n.b as i64) {
                let field = g.types.recordField(ty, index).ty;
                let foff, ferr = g.types.recordFieldByteOffset(ty, index);
                if ferr != squid_direct_types::Error.none { return false, ferr; }
                let ok, oerr = collectFlatPlainOwnerOffsets(g, field, base_off + foff, out, out_len);
                if oerr != squid_direct_types::Error.none { return false, oerr; }
                if !ok { return false, squid_direct_types::Error.none; }
            }
            return true, squid_direct_types::Error.none;
        },
        nominal => {
            let cases, verr = g.types.variants(ty);
            if verr != squid_direct_types::Error.none { return false, verr; }
            if cases.len != 1 { return false, squid_direct_types::Error.none; }
            let payload = g.types.variant_payloads[cases.payloads];
            return collectFlatPlainOwnerOffsets(g, payload, base_off, out, out_len);
        },
        _ => { return false, squid_direct_types::Error.none; },
    }
}
// Collect owner-slot locals of plain-element owner/view handles inside an unboxed Val.
recursive fn collectRegPlainOwnerSlots(g: Generator&, ty: Ty, words: u32, out: u32[16]&, out_len: i64&) -> bool, Error {
    let holds, error = g.contentsHoldMemory(ty);
    if error != squid_direct_types::Error.none { return false, error; }
    if !holds { return true, squid_direct_types::Error.none; }
    let boxed, berr = g.types.boxed(ty);
    if berr != squid_direct_types::Error.none { return false, berr; }
    if boxed { return false, squid_direct_types::Error.none; }
    let n = g.types.node(ty);
    match n.tag {
        array, packed, seq, view, ref, link => {
            let elem_holds, herr = g.contentsHoldMemory(n.a);
            if herr != squid_direct_types::Error.none { return false, herr; }
            if elem_holds || out_len >= 16 { return false, squid_direct_types::Error.none; }
            out[out_len] = g.s.words[words];
            out_len += 1;
            return true, squid_direct_types::Error.none;
        },
        tuple => {
            var at: u32 = 0;
            for index in 0..(n.b as i64) {
                let item = g.types.words[n.a + index];
                let layout, lerr = g.types.layout(item);
                if lerr != squid_direct_types::Error.none { return false, lerr; }
                let width = layout.len as u32;
                let ok, oerr = collectRegPlainOwnerSlots(g, item, words + at, out, out_len);
                if oerr != squid_direct_types::Error.none { return false, oerr; }
                if !ok { return false, squid_direct_types::Error.none; }
                at += width;
            }
            return true, squid_direct_types::Error.none;
        },
        record => {
            var at: u32 = 0;
            for index in 0..(n.b as i64) {
                let field = g.types.recordField(ty, index).ty;
                let layout, lerr = g.types.layout(field);
                if lerr != squid_direct_types::Error.none { return false, lerr; }
                let width = layout.len as u32;
                let ok, oerr = collectRegPlainOwnerSlots(g, field, words + at, out, out_len);
                if oerr != squid_direct_types::Error.none { return false, oerr; }
                if !ok { return false, squid_direct_types::Error.none; }
                at += width;
            }
            return true, squid_direct_types::Error.none;
        },
        nominal => {
            let cases, verr = g.types.variants(ty);
            if verr != squid_direct_types::Error.none { return false, verr; }
            if cases.len != 1 { return false, squid_direct_types::Error.none; }
            let payload = g.types.variant_payloads[cases.payloads];
            return collectRegPlainOwnerSlots(g, payload, words, out, out_len);
        },
        _ => { return false, squid_direct_types::Error.none; },
    }
}
// Records a store into the owner at `dst_slot`, propagating normalized age into `rt.escape_min_slot`.
// When `value` is a non-recursive flat value whose only memory-holding leaves are plain-element
// owners/views (such as `render.Draw` holding static `&no_extra[0..0]`), only a leaf temporary
// handle strictly newer than `dst_slot` (`src_slot < persistent_split && age < src_slot`) can
// escape and disable enclosing scope releases.
fn noteStoreToSlot(g: Generator&, f: Fn&, dst_slot: u32, value: Val) -> Error {
    if value.ty == squid_direct_types::never { return squid_direct_types::Error.none; }
    let holds, error = g.contentsHoldMemory(value.ty);
    if error != squid_direct_types::Error.none { return error; }
    if !holds { return squid_direct_types::Error.none; }
    let rt = g.runtime_();
    let age = local32(g, f);
    i32Const(g, 0);
    lget(g, dst_slot);
    lget(g, dst_slot);
    i32Const(g, rt.layout.persistent_split);
    op(g, OP_i32_ge_u);
    op(g, OP_select);
    lset(g, age);
    let boxed, berr = g.types.boxed(value.ty);
    if berr != squid_direct_types::Error.none { return berr; }
    let rec, rerr = g.types.isRecursive(value.ty);
    if rerr != squid_direct_types::Error.none { return rerr; }
    var items: u32[16] = [0; 16];
    var count: i64 = 0;
    if boxed && !rec {
        let ok, cerr = collectFlatPlainOwnerOffsets(g, value.ty, 0, items, count);
        if cerr != squid_direct_types::Error.none { return cerr; }
        if ok {
            if count > 0 {
                let src_slot = local32(g, f);
                for i in 0..count {
                    let off = items[i];
                    lget(g, w(g, value, 0));
                    op(g, OP_i32_load); uleb(g, 2); uleb(g, off);
                    ltee(g, src_slot);
                    i32Const(g, rt.layout.persistent_split);
                    op(g, OP_i32_lt_u);
                    lget(g, age);
                    lget(g, src_slot);
                    op(g, OP_i32_lt_u);
                    op(g, OP_i32_and);
                    let esc_if = open(g, f, OP_if_);
                    emitMergeEscapeMinCurrent(g, f, age);
                    close(g, f);
                }
            }
            return squid_direct_types::Error.none;
        }
    } else if !boxed {
        let ok, cerr = collectRegPlainOwnerSlots(g, value.ty, value.start, items, count);
        if cerr != squid_direct_types::Error.none { return cerr; }
        if ok {
            if count > 0 {
                for i in 0..count {
                    let src_slot = items[i];
                    lget(g, src_slot);
                    i32Const(g, rt.layout.persistent_split);
                    op(g, OP_i32_lt_u);
                    lget(g, age);
                    lget(g, src_slot);
                    op(g, OP_i32_lt_u);
                    op(g, OP_i32_and);
                    let esc_if = open(g, f, OP_if_);
                    emitMergeEscapeMinCurrent(g, f, age);
                    close(g, f);
                }
            }
            return squid_direct_types::Error.none;
        }
    }
    emitMergeEscapeMinCurrent(g, f, age);
    return squid_direct_types::Error.none;
}
// Releases an iteration's allocations when no inter-procedural store escaped past
// `label.release_owner` and every carried owner predates the iteration.
fn releaseIteration(g: Generator&, f: Fn&, label: squid_direct_emit::Label, iter_esc: u32) {
    lget(g, iter_esc);
    lget(g, label.release_owner);
    op(g, OP_i32_ge_u);
    if label.unchanged != 0xffffffff {
        lget(g, label.unchanged);
        op(g, OP_i32_and);
    }
    for at in 0..(label.guards.len as i64) {
        lget(g, g.s.words[label.guards.start + at]);
        lget(g, label.release_owner);
        op(g, OP_i32_lt_u);
        op(g, OP_i32_and);
    }
    op(g, OP_if_);
    op(g, 0x40);
    f.depth += 1;
    releaseTo(g, label.release_owner, label.release_stack);
    close(g, f);
}
// Pushes on the scratch stack the owner-slot locals of a carried value of
// `ty` whose words start at `words` in the word pool, and returns whether
// releasing around it can be made safe: plain values and owners of plain
// elements qualify; closures and memory-holding sums do not.
recursive fn ownerSlots(g: Generator&, ty: Ty, words: u32) -> bool, Error {
    let holds, error = g.contentsHoldMemory(ty);
    if error != squid_direct_types::Error.none { return false, error; }
    if !holds { return true, squid_direct_types::Error.none; }
    // A boxed carry is copied into its reserved slot; owners inside it are
    // not checked word by word.
    let boxed, error = g.types.boxed(ty);
    if error != squid_direct_types::Error.none { return false, error; }
    if boxed { return false, squid_direct_types::Error.none; }
    let n = g.types.node(ty);
    match n.tag {
        array, packed, seq, view, ref, link => {
            let element_holds, error = g.contentsHoldMemory(n.a);
            if error != squid_direct_types::Error.none { return false, error; }
            if element_holds { return false, squid_direct_types::Error.none; }
            let slot = g.s.words[words];
            g.s.scratch.push(slot);
            return true, squid_direct_types::Error.none;
        },
        tuple => {
            var at: u32 = 0;
            for index in 0..(n.b as i64) {
                let item = g.types.tupleItems(ty)[index];
                let layout, error = g.types.layout(item);
                if error != squid_direct_types::Error.none { return false, error; }
                let width = layout.len as u32;
                let safe, error = ownerSlots(g, item, words + at);
                if error != squid_direct_types::Error.none { return false, error; }
                if !safe { return false, squid_direct_types::Error.none; }
                at += width;
            }
            return true, squid_direct_types::Error.none;
        },
        record => {
            var at: u32 = 0;
            for index in 0..(n.b as i64) {
                let field = g.types.recordField(ty, index).ty;
                let layout, error = g.types.layout(field);
                if error != squid_direct_types::Error.none { return false, error; }
                let width = layout.len as u32;
                let safe, error = ownerSlots(g, field, words + at);
                if error != squid_direct_types::Error.none { return false, error; }
                if !safe { return false, squid_direct_types::Error.none; }
                at += width;
            }
            return true, squid_direct_types::Error.none;
        },
        _ => { return false, squid_direct_types::Error.none; },
    }
}
recursive fn breakNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    var at = g.s.labels.len;
    while at != f.labels_base {
        at -= 1;
        let label = g.s.labels[at];
        if label.target != n.a || label.kind != squid_direct_emit::LabelKind.loop_ { continue; }
        let left = leaveHandles(g, f, label.depth);
        if left != squid_direct_types::Error.none { return neverVal(), left; }
        let count = g.units[f.unit - 1].breakValues(id).len;
        if count != (label.iteration.len as i64) { return neverVal(), g.fail(g.units[f.unit - 1], id, "break carries the wrong number of values"); }
        let values = g.reserveVals(count);
        for vi in 0..count {
            let child = g.units[f.unit - 1].breakValues(id)[vi];
            let value, error = expr(g, f, child);
            if error != squid_direct_types::Error.none { return value, error; }
            g.s.vals[values.start + vi] = value;
        }
        // Merge saved escape marks for every inner releasing loop strictly inside `at`.
        var lk = g.s.labels.len;
        while lk > at + 1 {
            lk -= 1;
            if g.s.labels[lk].kind == squid_direct_emit::LabelKind.loop_ && g.s.labels[lk].has_release {
                g.s.labels[lk].used = true;
                emitMergeEscapeMinCurrent(g, f, g.s.labels[lk].saved_esc);
            }
        }
        if n.op == squid_check_core::Op.continue_ {
            let assigned = assignCarries(g, f, values, label.iteration, label.slots, label.unchanged, label.release_owner, label.release_stack, id);
            if assigned != squid_direct_types::Error.none { return neverVal(), assigned; }
            if label.has_release {
                g.s.labels[at].used = true;
                let iter_esc = local32(g, f);
                gget(g, g.runtime_().escape_min_slot);
                lset(g, iter_esc);
                if f.allocations != label.allocations {
                    releaseIteration(g, f, label, iter_esc);
                }
                emitMergeEscapeMin(g, f, iter_esc, label.saved_esc);
            }
            br(g, f, OP_br, label.top);
        } else {
            let assigned = assign(g, f, values, label.outgoing, id);
            if assigned != squid_direct_types::Error.none { return neverVal(), assigned; }
            if label.has_release {
                g.s.labels[at].used = true;
                emitMergeEscapeMinCurrent(g, f, label.saved_esc);
            }
            br(g, f, OP_br, label.depth);
        }
        return neverVal(), squid_direct_types::Error.none;
    }
    return neverVal(), g.fail(m, id, "break outside its loop");
}

recursive fn collectOwnedPatternBindings(m: const Module&, pattern_id: u32, out: u32[32]&, len: i64&) -> bool {
    if pattern_id == 0 { return true; }
    let pat = m.pattern(pattern_id);
    match pat.tag {
        wildcard => { return true; },
        bind => {
            if len >= 32 { return false; }
            for i in 0..len { if out[i] == pat.a { return false; } }
            out[len] = pat.a;
            len += 1;
            return true;
        },
        product => {
            for child in m.patternChildren(pattern_id) {
                if !collectOwnedPatternBindings(m, child, out, len) { return false; }
            }
            return true;
        },
        constructor, record_payload => {
            return collectOwnedPatternBindings(m, pat.b, out, len);
        },
        _ => { return false; },
    }
}

recursive fn patternBind(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let n = g.units[f.unit - 1].node(id);
    if n.c == 0 {
        let pm .= g.units[f.unit - 1];
        if isF64x2CoreExpr(pm, n.b) || isF32x4CoreExpr(pm, n.b) {
            let pat = pm.pattern(n.a);
            if pat.tag == squid_check_core::PatternTag.product {
                var all_ignore = true;
                for child in pm.patternChildren(n.a) {
                    let cp = pm.pattern(child);
                    if cp.tag == squid_check_core::PatternTag.wildcard { continue; }
                    if cp.tag != squid_check_core::PatternTag.bind || !bindingIgnoresNanPayload(g, f, cp.a) {
                        all_ignore = false;
                        break;
                    }
                }
                if all_ignore { f.elide_f32_nan_node = n.b; }
            }
        }
    }
    let value, error = expr(g, f, n.b);
    f.elide_f32_nan_node = 0;
    if error != squid_direct_types::Error.none { return value, error; }
    if n.c == 0 {
        let tested = test_(g, f, n.a, value, false, 0, id);
        if tested != squid_direct_types::Error.none { return neverVal(), tested; }
        let pm .= g.units[f.unit - 1];
        let src_b = localRef(pm, n.b);
        if src_b != 0 && isUniqueOwned(g, f, src_b) && ownedTotalUses(g, f, src_b) == 1 && !bindingCaptured(g, f, src_b) {
            var bound_ids: u32[32] = [0; 32];
            var bound_len: i64 = 0;
            if collectOwnedPatternBindings(pm, n.a, bound_ids, bound_len) {
                for bi in 0..bound_len {
                    squid_support_zigmap::put(g.s.map_pool, f.unique_owned, bound_ids[bi], f.loop_depth + 1);
                }
            }
        }
        return unitVal(), squid_direct_types::Error.none;
    }
    let ok = open(g, f, OP_block);
    let failed = open(g, f, OP_block);
    let tested = test_(g, f, n.a, value, true, failed, id);
    if tested != squid_direct_types::Error.none { return neverVal(), tested; }
    br(g, f, OP_br, ok);
    close(g, f);
    let otherwise, error = stmt(g, f, n.c);
    if error != squid_direct_types::Error.none { return otherwise, error; }
    op(g, OP_unreachable_);
    close(g, f);
    return unitVal(), squid_direct_types::Error.none;
}

recursive fn collectSparkCandReads(m: const Module&, id: u32, iter_b: u32, out: u32[8]&, len: i64&, left: i64&) {
    if id == 0 || left <= 0 || len >= 8 { return; }
    left -= 1;
    let n = m.node(id);
    match n.tag {
        array_op => {
            let ch = m.children(id);
            if m.arrayOperation(id) == squid_backend_collection_ops::Op.get && ch.len == 2 {
                if localRef(m, ch[1]) == iter_b { addHoistCandidate(out, len, localRef(m, ch[0])); }
            }
            for child in ch { collectSparkCandReads(m, child, iter_b, out, len, left); }
        },
        storage => {
            let ch = m.children(id);
            let op_kind, ok = squid_check_storage_ops::opFromCode(n.c);
            if ok == squid_error::Error.none && op_kind == squid_check_storage_ops::Op.read && ch.len == 2 {
                if localRef(m, ch[1]) == iter_b { addHoistCandidate(out, len, localRef(m, ch[0])); }
            }
            for child in ch { collectSparkCandReads(m, child, iter_b, out, len, left); }
        },
        suite, block_, product, record, array => {
            for child in m.children(id) { collectSparkCandReads(m, child, iter_b, out, len, left); }
        },
        bind, construct => { collectSparkCandReads(m, n.b, iter_b, out, len, left); },
        return_, project, result_associated => { collectSparkCandReads(m, n.a, iter_b, out, len, left); },
        scalar, associated, logical, apply => {
            collectSparkCandReads(m, n.a, iter_b, out, len, left);
            collectSparkCandReads(m, n.b, iter_b, out, len, left);
        },
        if_value, if_stmt => {
            collectSparkCandReads(m, n.a, iter_b, out, len, left);
            collectSparkCandReads(m, n.b, iter_b, out, len, left);
            collectSparkCandReads(m, n.c, iter_b, out, len, left);
        },
        call => {
            for arg in m.call(id).arguments { collectSparkCandReads(m, arg, iter_b, out, len, left); }
        },
        _ => {},
    }
}
recursive fn countSparkCandRefs(
    m: const Module&,
    id: u32,
    cand_b: u32,
    iter_b: u32,
    valid: u32&,
    other: u32&,
    left: i64&,
) -> bool {
    if id == 0 { return true; }
    if left <= 0 { return false; }
    left -= 1;
    let n = m.node(id);
    match n.tag {
        constant, panic => { return true; },
        reference => {
            if localRef(m, id) == cand_b { other += 1; }
            return true;
        },
        array_op => {
            let ch = m.children(id);
            let op_k = m.arrayOperation(id);
            if op_k == squid_backend_collection_ops::Op.get && ch.len == 2 &&
                localRef(m, ch[0]) == cand_b && localRef(m, ch[1]) == iter_b {
                valid += 1;
                return true;
            }
            if op_k == squid_backend_collection_ops::Op.length && ch.len == 1 && localRef(m, ch[0]) == cand_b {
                return true;
            }
            for child in ch { if !countSparkCandRefs(m, child, cand_b, iter_b, valid, other, left) { return false; } }
            return true;
        },
        storage => {
            let ch = m.children(id);
            let op_kind, ok = squid_check_storage_ops::opFromCode(n.c);
            if ok == squid_error::Error.none && op_kind == squid_check_storage_ops::Op.read && ch.len == 2 &&
                localRef(m, ch[0]) == cand_b && localRef(m, ch[1]) == iter_b {
                valid += 1;
                return true;
            }
            if ok == squid_error::Error.none && op_kind == squid_check_storage_ops::Op.length && ch.len == 1 && localRef(m, ch[0]) == cand_b {
                return true;
            }
            for child in ch { if !countSparkCandRefs(m, child, cand_b, iter_b, valid, other, left) { return false; } }
            return true;
        },
        project => {
            let proj = m.projection(n.b);
            if m.projectionVariants(n.b).len == 0 && proj.field != 0 {
                let sp = m.fieldSpelling(proj.field);
                if sp.present && sp.value == "length" && localRef(m, n.a) == cand_b { return true; }
            }
            return countSparkCandRefs(m, n.a, cand_b, iter_b, valid, other, left);
        },
        suite, block_, product, record, array => {
            for child in m.children(id) { if !countSparkCandRefs(m, child, cand_b, iter_b, valid, other, left) { return false; } }
            return true;
        },
        bind, construct => { return countSparkCandRefs(m, n.b, cand_b, iter_b, valid, other, left); },
        pattern_bind => {
            return countSparkCandRefs(m, n.b, cand_b, iter_b, valid, other, left) &&
                countSparkCandRefs(m, n.c, cand_b, iter_b, valid, other, left);
        },
        return_, result_associated => { return countSparkCandRefs(m, n.a, cand_b, iter_b, valid, other, left); },
        scalar, associated, logical, apply => {
            return countSparkCandRefs(m, n.a, cand_b, iter_b, valid, other, left) &&
                countSparkCandRefs(m, n.b, cand_b, iter_b, valid, other, left);
        },
        if_value, if_stmt => {
            return countSparkCandRefs(m, n.a, cand_b, iter_b, valid, other, left) &&
                countSparkCandRefs(m, n.b, cand_b, iter_b, valid, other, left) &&
                countSparkCandRefs(m, n.c, cand_b, iter_b, valid, other, left);
        },
        call => {
            for arg in m.call(id).arguments {
                if !countSparkCandRefs(m, arg, cand_b, iter_b, valid, other, left) { return false; }
            }
            return true;
        },
        _ => { return false; },
    }
}
fn findSparkReuseCandidate(g: Generator&, f: Fn&, m: const Module&, info: squid_check_core::SparkInfo, out_ty: Ty, elem_ty: Ty) -> u32 {
    if g.runtime_().has_fork { return 0; }
    if tagOf(g, out_ty) != squid_direct_types::Tag.array || !isScalarTag(tagOf(g, elem_ty)) { return 0; }
    if !info.is_range {
        let cand_b = localRef(m, info.source);
        if cand_b == 0 || !isUniqueOwned(g, f, cand_b) || bindingCaptured(g, f, cand_b) { return 0; }
        if ownedRefUses(g, f, cand_b) != 1 || ownedFlowUses(g, f, cand_b) != 0 { return 0; }
        let _, is_cell = withCellType(g, f, cand_b);
        if is_cell { return 0; }
        let val, ok = bindGet(g, f, cand_b);
        if ok && val.ty == out_ty { return cand_b; }
        return 0;
    }
    if info.pattern == 0 || m.pattern(info.pattern).tag != squid_check_core::PatternTag.bind { return 0; }
    let iter_b = m.pattern(info.pattern).a;
    var cands: u32[8] = [0; 8];
    var cands_len: i64 = 0;
    var cbudget: i64 = 256;
    collectSparkCandReads(m, info.body, iter_b, cands, cands_len, cbudget);
    for ci in 0..cands_len {
        let cand_b = cands[ci];
        if !isUniqueOwned(g, f, cand_b) || bindingCaptured(g, f, cand_b) { continue; }
        if ownedFlowUses(g, f, cand_b) != 0 { continue; }
        let total_refs = ownedRefUses(g, f, cand_b);
        if total_refs == 0 || total_refs == 0xffffffff { continue; }
        let _, is_cell = withCellType(g, f, cand_b);
        if is_cell { continue; }
        let val, ok = bindGet(g, f, cand_b);
        if !ok || val.ty != out_ty { continue; }
        var valid: u32 = 0;
        var other: u32 = 0;
        var rbudget: i64 = 256;
        if countSparkCandRefs(m, info.body, cand_b, iter_b, valid, other, rbudget) && other == 0 && valid == total_refs {
            return cand_b;
        }
    }
    return 0;
}

// Synchronous ordered data-parallel array map `spark #[body | pat <- source]`.
// Phase 1 emits an escape-safe preallocated direct loop; Phase 2 adds 4-wide
// Wasm SIMD (`v128`) vectorization ahead of this scalar fallback.
recursive fn inferSparkBodyTy(
    g: Generator&,
    f: const Fn&,
    m: const Module&,
    id: u32,
    pat_binding: u32,
    pat_ty: Ty,
    depth: i64,
) -> Ty, bool {
    if id == 0 || depth > 32 { return 0, false; }
    let direct, derr = g.types.lower(m, m.typeOf(id), f.env);
    if derr == squid_direct_types::Error.none { return direct, true; }
    let n = m.node(id);
    match n.tag {
        reference => {
            let r = m.reference(id);
            if r.unit == 0 && pat_binding != 0 && r.binding == pat_binding { return pat_ty, true; }
            return 0, false;
        },
        comptime_meta => {
            if n.c == 0 {
                let fidx = findComptimeFrame(f, n.b);
                if fidx >= 0 { return f.comptime_frames[fidx].field_ty, true; }
            } else if n.c == 10 {
                let fidx = findComptimeFrame(f, n.a);
                if fidx >= 0 { return f.comptime_frames[fidx].field_ty, true; }
            } else if n.c == 2 || n.c == 4 || n.c == 7 {
                return squid_direct_types::u32_, true;
            } else if n.c == 3 || n.c == 5 || n.c == 6 || n.c == 8 || n.c == 9 {
                return squid_direct_types::boolean, true;
            }
            return 0, false;
        },
        scalar, associated => {
            let lty, lok = inferSparkBodyTy(g, f, m, n.a, pat_binding, pat_ty, depth + 1);
            if lok && n.op != squid_check_core::Op.none && isScalarTag(tagOf(g, lty)) {
                return scalarResult(n.op, lty), true;
            }
            if lok && n.tag == squid_check_core::Tag.associated {
                let id_opt, has_id = g.receiverIdentity(lty);
                if has_id {
                    let target, has_target = g.dispatchTarget(m, id_opt, n.c, squid_check_types::Operator.none);
                    if has_target && g.hasUnit(target.unit) {
                        let tm .= g.units[target.unit - 1];
                        let tb = tm.binding(target.binding);
                        let tnode = tm.types.node(tb.ty);
                        if tnode.tag == squid_check_types::Tag.function {
                            var rtid = tnode.b;
                            if n.b != 0 && tm.types.node(rtid).tag == squid_check_types::Tag.function {
                                rtid = tm.types.node(rtid).b;
                            }
                            let rty, rerr = g.types.lower(tm, rtid, Env {});
                            if rerr == squid_direct_types::Error.none { return rty, true; }
                        }
                    }
                }
            }
            return 0, false;
        },
        logical => { return squid_direct_types::boolean, true; },
        if_value => {
            let tty, tok = inferSparkBodyTy(g, f, m, n.b, pat_binding, pat_ty, depth + 1);
            if tok { return tty, true; }
            return inferSparkBodyTy(g, f, m, n.c, pat_binding, pat_ty, depth + 1);
        },
        return_ => { return inferSparkBodyTy(g, f, m, n.a, pat_binding, pat_ty, depth + 1); },
        block_, suite => {
            let ch = m.children(id);
            if ch.len > 0 { return inferSparkBodyTy(g, f, m, ch[ch.len - 1], pat_binding, pat_ty, depth + 1); }
            return 0, false;
        },
        _ => { return 0, false; },
    }
}

recursive fn sparkNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let info = m.sparkInfo(id);
    var start_local: u32 = 0;
    var count: u32 = 0;
    var source_val = neverVal();
    if info.is_range {
        let s_val, s_err = expr(g, f, info.source);
        if s_err != squid_direct_types::Error.none { return s_val, s_err; }
        let s_loc, sl_err = scalarLocal(g, f, s_val, id);
        if sl_err != squid_direct_types::Error.none { return neverVal(), sl_err; }
        start_local = s_loc;
        let e_val, e_err = expr(g, f, info.end);
        if e_err != squid_direct_types::Error.none { return e_val, e_err; }
        let e_loc, el_err = scalarLocal(g, f, e_val, id);
        if el_err != squid_direct_types::Error.none { return neverVal(), el_err; }
        count = local32(g, f);
        lget(g, e_loc);
        lget(g, start_local);
        op(g, OP_i32_gt_u);
        let cmp_if = open(g, f, OP_if_);
        lget(g, e_loc);
        lget(g, start_local);
        op(g, OP_i32_sub);
        lset(g, count);
        popCheckedArraysAt(f, cmp_if);
        op(g, OP_else_);
        i32Const(g, 0);
        lset(g, count);
        close(g, f);
    } else {
        let c_val, c_err = expr(g, f, info.source);
        if c_err != squid_direct_types::Error.none { return c_val, c_err; }
        source_val = c_val;
        let len_loc, len_err = lengthOf(g, f, source_val, id);
        if len_err != squid_direct_types::Error.none { return neverVal(), len_err; }
        count = len_loc;
    }

    var out_ty: Ty = 0;
    let strict_out, strict_err = g.types.lower(g.units[f.unit - 1], g.units[f.unit - 1].typeOf(id), f.env);
    if strict_err == squid_direct_types::Error.none {
        out_ty = strict_out;
    } else {
        // Unresolved element type variable (e.g. deferred comptime `p.(f) + i` inside `#for`):
        // infer the concrete element type purely from the body without emitting or rewinding code.
        var probe_item_ty = squid_direct_types::u32_;
        if !info.is_range {
            let pit, pierr = elementOf(g, f, source_val.ty, id);
            if pierr != squid_direct_types::Error.none { return neverVal(), pierr; }
            probe_item_ty = pit;
        }
        var pat_b: u32 = 0;
        if info.pattern != 0 && g.units[f.unit - 1].pattern(info.pattern).tag == squid_check_core::PatternTag.bind {
            pat_b = g.units[f.unit - 1].pattern(info.pattern).a;
        }
        let probed_ty, probed_ok = inferSparkBodyTy(g, f, g.units[f.unit - 1], info.body, pat_b, probe_item_ty, 0);
        if probed_ok && probed_ty != 0 {
            let built, ierr = g.types.intern(squid_direct_types::Tag.array, [probed_ty]);
            if ierr != squid_direct_types::Error.none { return neverVal(), ierr; }
            refine(g, f, g.units[f.unit - 1].typeOf(id), built);
            out_ty = built;
        } else {
            let fallback_ty, ty_err = typeOf(g, f, id);
            if ty_err != squid_direct_types::Error.none { return neverVal(), ty_err; }
            out_ty = fallback_ty;
        }
    }
    let elem_ty, elem_err = elementOf(g, f, out_ty, id);
    if elem_err != squid_direct_types::Error.none { return neverVal(), elem_err; }
    let step, step_err = stride(g, f, elem_ty, id);
    if step_err != squid_direct_types::Error.none { return neverVal(), step_err; }
    let elem_holds, hold_err = g.contentsHoldMemory(elem_ty);
    if hold_err != squid_direct_types::Error.none { return neverVal(), hold_err; }

    let reuse_cand = findSparkReuseCandidate(g, f, g.units[f.unit - 1], info, out_ty, elem_ty);
    var handle = neverVal();
    var base: u32 = 0;
    if reuse_cand != 0 && !info.is_range {
        let src_base, _ = ensureCheckedArray(g, f, source_val);
        handle = source_val;
        base = src_base;
    } else if reuse_cand != 0 && info.is_range {
        let cand_val, _ = bindGet(g, f, reuse_cand);
        let cand_base, cand_len = ensureCheckedArray(g, f, cand_val);
        let made_handle, herr = fresh(g, f, out_ty, id);
        if herr != squid_direct_types::Error.none { return neverVal(), herr; }
        let made_base = local32(g, f);
        lget(g, start_local);
        op(g, OP_i32_eqz);
        lget(g, count);
        lget(g, cand_len);
        op(g, OP_i32_eq);
        op(g, OP_i32_and);
        let reuse_if = open(g, f, OP_if_);
        let cp1_err = copy(g, f, cand_val, made_handle, id);
        if cp1_err != squid_direct_types::Error.none { return neverVal(), cp1_err; }
        lget(g, cand_base);
        lset(g, made_base);
        popCheckedArraysAt(f, reuse_if);
        op(g, OP_else_);
        let alloc_handle, alloc_base, aerr = createUninit(g, f, out_ty, count, id);
        if aerr != squid_direct_types::Error.none { return alloc_handle, aerr; }
        let cp2_err = copy(g, f, alloc_handle, made_handle, id);
        if cp2_err != squid_direct_types::Error.none { return neverVal(), cp2_err; }
        lget(g, alloc_base);
        lset(g, made_base);
        close(g, f);
        handle = made_handle;
        base = made_base;
    } else {
        let alloc_handle, alloc_base, alloc_err = createUninit(g, f, out_ty, count, id);
        if alloc_err != squid_direct_types::Error.none { return alloc_handle, alloc_err; }
        handle = alloc_handle;
        base = alloc_base;
    }

    let vectorized, vec_index, vec_err = tryEmitVectorSpark(g, f, id, out_ty, elem_ty, start_local, source_val, count, base);
    if vec_err != squid_direct_types::Error.none { return neverVal(), vec_err; }

    var index: u32 = 0;
    if vectorized {
        index = vec_index;
    } else {
        g.s.sparks_scalar_fallback += 1;
        index = constLocal(g, f, 0);
    }
    let exit = open(g, f, OP_block);
    let top = open(g, f, OP_loop);
    f.checked_elems_len = 0;
    lget(g, index);
    lget(g, count);
    op(g, OP_i32_ge_u);
    br(g, f, OP_br_if, exit);

    let owner_mark = local32(g, f);
    let stack_mark = local32(g, f);
    let saved_esc = local32(g, f);
    let mark_at = g.s.code.len;
    let allocs_before = f.allocations;
    let stores_before = f.memory_stores;

    var item = neverVal();
    if info.is_range {
        let cur = local32(g, f);
        lget(g, start_local);
        lget(g, index);
        op(g, OP_i32_add);
        lset(g, cur);
        item = valOf1(g, squid_direct_types::u32_, cur);
    } else {
        let loaded, lerr = readElement(g, f, source_val, index, id, g.units[f.unit - 1].typeOf(info.source), false);
        if lerr != squid_direct_types::Error.none { return neverVal(), lerr; }
        item = loaded;
    }

    let saved_bindings = squid_support_zigmap::clone(g.s.map_pool, f.bindings);
    let tested = test_(g, f, info.pattern, item, false, 0, id);
    if tested != squid_direct_types::Error.none {
        f.bindings = saved_bindings;
        return neverVal(), tested;
    }
    f.loop_depth += 1;
    let val, verr = stmt(g, f, info.body);
    f.loop_depth -= 1;
    f.bindings = saved_bindings;
    if verr != squid_direct_types::Error.none { return val, verr; }

    if val.ty != squid_direct_types::never {
        let dst_addr = emitOffsetAddress(g, f, base, index, step);
        let written = writeElement(g, f, dst_addr, 0, val, id);
        if written != squid_direct_types::Error.none { return neverVal(), written; }
        // Escape-safe per-iteration scratch release: only release when output
        // elements cannot hold scope memory and no store escaped past owner_mark.
        let release_ok = !elem_holds && f.memory_stores == stores_before && f.allocations != allocs_before;
        if release_ok {
            let iter_esc = local32(g, f);
            gget(g, g.runtime_().escape_min_slot);
            ltee(g, iter_esc);
            lget(g, owner_mark);
            op(g, OP_i32_ge_u);
            let rel_if = open(g, f, OP_if_);
            releaseTo(g, owner_mark, stack_mark);
            close(g, f);
            emitMergeEscapeMin(g, f, iter_esc, saved_esc);
            var prefix: u8[>..<] = [];
            markInto(g, prefix, owner_mark, stack_mark);
            let esc_global = g.runtime_().escape_min_slot;
            prefix.push(OP_global_get);
            squid_direct_writer::uleb(prefix, esc_global);
            prefix.push(OP_local_set);
            squid_direct_writer::uleb(prefix, saved_esc);
            prefix.push(OP_i32_const);
            squid_direct_writer::sleb(prefix, -1);
            prefix.push(OP_global_set);
            squid_direct_writer::uleb(prefix, esc_global);
            squid_direct_relocations::insert(f.sites_base, mark_at, prefix.len);
            if g.s.parallel_readonly { squid_direct_emit::shiftParallelPatches(mark_at, prefix.len); }
            let old_len = g.s.code.len;
            for byte in prefix { g.s.code.push(byte); }
            var at = old_len;
            while at > mark_at {
                at -= 1;
                g.s.code[at + prefix.len] = g.s.code[at];
            }
            for byte, offset in prefix { g.s.code[mark_at + offset] = byte; }
        }
        lget(g, index);
        i32Const(g, 1);
        op(g, OP_i32_add);
        lset(g, index);
        br(g, f, OP_br, top);
    }
    close(g, f);
    close(g, f);
    return handle, squid_direct_types::Error.none;
}

recursive fn flatOpNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    if n.c == squid_check_core::flat_op_kernel_handle {
        let kidx = n.a;
        if (kidx as i64) >= g.s.kernels.len {
            return neverVal(), g.fail(m, id, "unknown kernel declaration index");
        }
        let kinfo = g.s.kernels[kidx];
        let ty, ty_err = typeOf(g, f, id);
        if ty_err != squid_direct_types::Error.none { return neverVal(), ty_err; }
        let w0 = constLocal(g, f, kidx);
        let w1 = constLocal(g, f, (kinfo.binding_hash & 0xffffffff) as u32);
        let w2 = constLocal(g, f, (kinfo.binding_hash >> 32) as u32);
        let w3 = constLocal(g, f, (kinfo.ctx_schema.schema_hash & 0xffffffff) as u32);
        let w4 = constLocal(g, f, (kinfo.ctx_schema.schema_hash >> 32) as u32);
        let w5 = constLocal(g, f, (kinfo.io_schema_hash & 0xffffffff) as u32);
        let w6 = constLocal(g, f, (kinfo.io_schema_hash >> 32) as u32);
        let boxed, berr = isBoxed(g, f, ty, id);
        if berr != squid_direct_types::Error.none { return neverVal(), berr; }
        if boxed {
            let blk, merr = newBlock(g, f, ty, id);
            if merr != squid_direct_types::Error.none { return neverVal(), merr; }
            let vals: u32[7] = [w0, w1, w2, w3, w4, w5, w6];
            for wi in 0..7 {
                lget(g, blk);
                lget(g, vals[wi]);
                op(g, OP_i32_store);
                uleb(g, 2);
                uleb(g, (wi * 4) as u32);
            }
            return valOf1(g, ty, blk), squid_direct_types::Error.none;
        }
        let words = g.saveWords([w0, w1, w2, w3, w4, w5, w6]);
        return Val { ty, words.start, words.len }, squid_direct_types::Error.none;
    }
    if n.c == squid_check_core::flat_op_process_handle {
        let pidx = n.a;
        if (pidx as i64) >= g.s.processes.len {
            return neverVal(), g.fail(m, id, "unknown process declaration index");
        }
        let pinfo = g.s.processes[pidx];
        let ty, ty_err = typeOf(g, f, id);
        if ty_err != squid_direct_types::Error.none { return neverVal(), ty_err; }
        let w0 = constLocal(g, f, pidx);
        let w1 = constLocal(g, f, (pinfo.binding_hash & 0xffffffff) as u32);
        let w2 = constLocal(g, f, (pinfo.binding_hash >> 32) as u32);
        let boxed, berr = isBoxed(g, f, ty, id);
        if berr != squid_direct_types::Error.none { return neverVal(), berr; }
        if boxed {
            let blk, merr = newBlock(g, f, ty, id);
            if merr != squid_direct_types::Error.none { return neverVal(), merr; }
            let vals: u32[3] = [w0, w1, w2];
            for wi in 0..3 {
                lget(g, blk);
                lget(g, vals[wi]);
                op(g, OP_i32_store);
                uleb(g, 2);
                uleb(g, (wi * 4) as u32);
            }
            return valOf1(g, ty, blk), squid_direct_types::Error.none;
        }
        let words = g.saveWords([w0, w1, w2]);
        return Val { ty, words.start, words.len }, squid_direct_types::Error.none;
    }
    if n.c == squid_check_core::flat_op_kernel_id || n.c == squid_check_core::flat_op_process_id {
        let kval, kerr = expr(g, f, n.a);
        if kerr != squid_direct_types::Error.none { return kval, kerr; }
        let boxed, berr = isBoxed(g, f, kval.ty, id);
        if berr != squid_direct_types::Error.none { return neverVal(), berr; }
        if boxed {
            let res = local32(g, f);
            lget(g, w(g, kval, 0));
            op(g, OP_i32_load);
            uleb(g, 2);
            uleb(g, 0);
            lset(g, res);
            return valOf1(g, squid_direct_types::u32_, res), squid_direct_types::Error.none;
        }
        return valOf1(g, squid_direct_types::u32_, w(g, kval, 0)), squid_direct_types::Error.none;
    }
    if n.c == squid_check_core::flat_op_kernel_binding_hash || n.c == squid_check_core::flat_op_kernel_ctx_hash || n.c == squid_check_core::flat_op_kernel_io_hash || n.c == squid_check_core::flat_op_process_binding_hash {
        let kval, kerr = expr(g, f, n.a);
        if kerr != squid_direct_types::Error.none { return kval, kerr; }
        let ty, ty_err = typeOf(g, f, id);
        if ty_err != squid_direct_types::Error.none { return neverVal(), ty_err; }
        var word_base: i64 = 1;
        if n.c == squid_check_core::flat_op_kernel_ctx_hash { word_base = 3; }
        else if n.c == squid_check_core::flat_op_kernel_io_hash { word_base = 5; }
        let boxed, berr = isBoxed(g, f, kval.ty, id);
        if berr != squid_direct_types::Error.none { return neverVal(), berr; }
        var lo: u32 = 0;
        var hi: u32 = 0;
        if boxed {
            lo = local32(g, f);
            lget(g, w(g, kval, 0));
            op(g, OP_i32_load);
            uleb(g, 2);
            uleb(g, (word_base * 4) as u32);
            lset(g, lo);
            hi = local32(g, f);
            lget(g, w(g, kval, 0));
            op(g, OP_i32_load);
            uleb(g, 2);
            uleb(g, ((word_base + 1) * 4) as u32);
            lset(g, hi);
        } else {
            lo = w(g, kval, word_base);
            hi = w(g, kval, word_base + 1);
        }
        let words = g.saveWords([lo, hi]);
        return Val { ty, words.start, words.len }, squid_direct_types::Error.none;
    }
    if n.c == squid_check_core::flat_op_schema_hash {
        let ignored, aerr = expr(g, f, n.a);
        if aerr != squid_direct_types::Error.none { return ignored, aerr; }
        let ty, ty_err = typeOf(g, f, id);
        if ty_err != squid_direct_types::Error.none { return neverVal(), ty_err; }
        let h, ok = squid_check_wire_schema::computeSchemaHash(g.units, f.unit, n.b);
        if !ok {
            return neverVal(), g.failCode(m, id, squid_check_diagnostic_code::Code.kernel_type, "@flat.schema_hash requires a closed FlatNumeric, Unit, #[U32], or #[F32] type");
        }
        let lo = constLocal(g, f, (h & 0xffffffff) as u32);
        let hi = constLocal(g, f, (h >> 32) as u32);
        let words = g.saveWords([lo, hi]);
        return Val { ty, words.start, words.len }, squid_direct_types::Error.none;
    }
    if n.c == squid_check_core::flat_op_encode {
        let arg_val, aerr = expr(g, f, n.a);
        if aerr != squid_direct_types::Error.none { return arg_val, aerr; }
        let out_ty, ty_err = typeOf(g, f, id);
        if ty_err != squid_direct_types::Error.none { return neverVal(), ty_err; }
        return emitFlatEncodeVal(g, f, arg_val, n.b, out_ty, id);
    }
    if n.c == squid_check_core::flat_op_decode {
        let src_val, serr = expr(g, f, n.a);
        if serr != squid_direct_types::Error.none { return src_val, serr; }
        let maybe_ty, ty_err = typeOf(g, f, id);
        if ty_err != squid_direct_types::Error.none { return neverVal(), ty_err; }
        return emitFlatDecodeVal(g, f, src_val, m.typeOf(id), maybe_ty, id);
    }
    if n.c == squid_check_core::flat_op_encode_wire {
        let arg_val, aerr = expr(g, f, n.a);
        if aerr != squid_direct_types::Error.none { return arg_val, aerr; }
        let out_ty, ty_err = typeOf(g, f, id);
        if ty_err != squid_direct_types::Error.none { return neverVal(), ty_err; }
        return emitFlatEncodeWireVal(g, f, arg_val, n.b, out_ty, id);
    }
    if n.c == squid_check_core::flat_op_decode_wire {
        let src_val, serr = expr(g, f, n.a);
        if serr != squid_direct_types::Error.none { return src_val, serr; }
        let maybe_ty, ty_err = typeOf(g, f, id);
        if ty_err != squid_direct_types::Error.none { return neverVal(), ty_err; }
        return emitFlatDecodeWireVal(g, f, src_val, m.typeOf(id), maybe_ty, id);
    }
    if n.c == squid_check_core::flat_op_encode_batch {
        let arg_val, aerr = expr(g, f, n.a);
        if aerr != squid_direct_types::Error.none { return arg_val, aerr; }
        let out_ty, ty_err = typeOf(g, f, id);
        if ty_err != squid_direct_types::Error.none { return neverVal(), ty_err; }
        return emitFlatEncodeBatchVal(g, f, arg_val, n.b, out_ty, id);
    }
    if n.c == squid_check_core::flat_op_decode_batch {
        let src_val, serr = expr(g, f, n.a);
        if serr != squid_direct_types::Error.none { return src_val, serr; }
        let maybe_ty, ty_err = typeOf(g, f, id);
        if ty_err != squid_direct_types::Error.none { return neverVal(), ty_err; }
        return emitFlatDecodeBatchVal(g, f, src_val, m.typeOf(id), maybe_ty, id);
    }
    return neverVal(), g.fail(m, id, "unknown @flat intrinsic");
}
