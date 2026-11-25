// Physical-stride recursive FlatNumeric pack/unpack, `@flat.encode`/`@flat.decode`,
// `#kernel` & `#process` ABI 8 wrappers, and `blot:kernels`/`blot:processes`
// v1 custom sections (tasks/CONCURRENCY_VNEXT.md §3.1, §3.2, §4.2.3).
namespace blot_direct_function;
import .function;

struct CoreSubstEntry {
    def_unit: u32 = 0,
    var_id: TId = 0,
    arg_unit: u32 = 0,
    arg_id: TId = 0,
}

fn lookupCoreSubst(subst: const CoreSubstEntry[:], unit: u32, var_id: TId) -> u32, TId, bool {
    var i = subst.len;
    while i > 0 {
        i -= 1;
        if subst[i].def_unit == unit && subst[i].var_id == var_id {
            return subst[i].arg_unit, subst[i].arg_id, true;
        }
    }
    return 0, 0, false;
}

fn unwrapCoreFlatType(g: const Generator&, unit: u32, tid: TId, subst: const CoreSubstEntry[:]) -> u32, TId {
    var cu = unit;
    var ct = tid;
    for _ in 0..32 {
        if !g.hasUnit(cu) || ct == 0 { return cu, ct; }
        let cm .= g.units[cu - 1];
        if (ct as i64) >= cm.types.nodes.len { return cu, ct; }
        let cn = cm.types.node(ct);
        if cn.tag == blot_check_types::Tag.usage || cn.tag == blot_check_types::Tag.forall {
            ct = cn.a;
            continue;
        }
        if cn.tag == blot_check_types::Tag.variable {
            let nu, nt, ok = lookupCoreSubst(subst, cu, ct);
            if ok { cu = nu; ct = nt; continue; }
        }
        return cu, ct;
    }
    return cu, ct;
}

fn findNominalDeclInUnit(m: const Module&, identity: blot_check_types::NominalIdentity) -> i64 {
    for i in 1..m.nominals.len {
        if m.nominals[i].identity == identity { return i; }
    }
    return -1;
}

fn findCoreRecordFieldByName(g: const Generator&, cm: const Module&, rec_node: blot_check_types::Node, target_name_id: u32) -> TId, bool {
    let want = g.types.spelling(target_name_id);
    for i in 0..(rec_node.b as i64) {
        let cf = cm.types.recordField(rec_node, i);
        let sp = cm.fieldSpelling(cf.name);
        if sp.present && sp.value == want { return cf.ty, true; }
    }
    return 0, false;
}

// Compute canonical FlatNumeric word count for a concrete (unit, core_tid) / Ty pair.
// Returns (words, ok). Supports U32, F32, Bool, tuples, closed records, #[K; E], and
// single-constructor non-opaque nominals; also falls back to direct `Ty` when `core_tid`
// is an uninstantiated generic variable with no `#[K; E]` array.
recursive fn flatNumericWordCount(
    g: Generator&,
    unit: u32,
    core_tid: TId,
    ty: Ty,
    subst: CoreSubstEntry[>..]&,
    depth: i64
) -> u32, bool {
    if depth > 64 { return 0, false; }
    let cu, ct = unwrapCoreFlatType(g, unit, core_tid, subst[..]);
    let tn = g.types.node(ty);
    match tn.tag {
        u32_, f32_, boolean => { return 1, true; },
        tuple => {
            var total: u64 = 0;
            var has_core = false;
            var core_start: u32 = 0;
            if g.hasUnit(cu) && ct != 0 && (ct as i64) < g.units[cu - 1].types.nodes.len {
                let cn = g.units[cu - 1].types.node(ct);
                if cn.tag == blot_check_types::Tag.product && cn.b == tn.b {
                    has_core = true;
                    core_start = cn.a;
                }
            }
            for i in 0..(tn.b as i64) {
                var child_ct: TId = 0;
                if has_core { child_ct = g.units[cu - 1].types.list(blot_check_types::List { core_start, tn.b })[i]; }
                let w, ok = flatNumericWordCount(g, cu, child_ct, g.types.words[tn.a + i], subst, depth + 1);
                if !ok { return 0, false; }
                total += w as u64;
                if total > blot_check_wire_schema::MAX_WIRE_WORDS { return 0, false; }
            }
            return total as u32, total > 0;
        },
        record => {
            var total: u64 = 0;
            var has_core = false;
            var cn = blot_check_types::Node { tag: blot_check_types::Tag.unit, .. };
            if g.hasUnit(cu) && ct != 0 && (ct as i64) < g.units[cu - 1].types.nodes.len {
                cn = g.units[cu - 1].types.node(ct);
                if cn.tag == blot_check_types::Tag.record && cn.b == tn.b { has_core = true; }
            }
            for i in 0..(tn.b as i64) {
                let df = g.types.recordField(ty, i);
                var child_ct: TId = 0;
                if has_core {
                    let found_ct, ok = findCoreRecordFieldByName(g, g.units[cu - 1], cn, df.name);
                    if ok { child_ct = found_ct; }
                }
                let w, ok = flatNumericWordCount(g, cu, child_ct, df.ty, subst, depth + 1);
                if !ok { return 0, false; }
                total += w as u64;
                if total > blot_check_wire_schema::MAX_WIRE_WORDS { return 0, false; }
            }
            return total as u32, total > 0;
        },
        array => {
            // Sized array #[K; E] requires exact K from Core TId.
            if !g.hasUnit(cu) || ct == 0 || (ct as i64) >= g.units[cu - 1].types.nodes.len { return 0, false; }
            let cm .= g.units[cu - 1];
            let sinfo = blot_check_storage_types::info(cm.types, ct);
            if !sinfo.present || sinfo.value.kind != blot_check_storage_types::sized_array { return 0, false; }
            let len_opt = blot_check_storage_types::lengthOf(cm.types, ct);
            if !len_opt.present { return 0, false; }
            let lnode = cm.types.node(len_opt.value);
            if lnode.tag != blot_check_types::Tag.nominal || !blot_check_storage_types::isLengthLiteral(lnode.a, lnode.b) { return 0, false; }
            let k = blot_check_storage_types::lengthLiteralValue(lnode.b) as u64;
            if k == 0 { return 0, false; }
            let elem_w, ok = flatNumericWordCount(g, cu, sinfo.value.element, tn.a, subst, depth + 1);
            if !ok || elem_w == 0 { return 0, false; }
            if (elem_w as u64) > blot_check_wire_schema::MAX_WIRE_WORDS / k { return 0, false; }
            return ((elem_w as u64) * k) as u32, true;
        },
        nominal => {
            let ident = g.types.nominalIdentity(ty);
            if !g.hasUnit(ident.unit) { return 0, false; }
            let dm .= g.units[ident.unit - 1];
            let nidx = findNominalDeclInUnit(dm, ident);
            if nidx < 0 || dm.nominals[nidx].is_opaque { return 0, false; }
            let ctors = dm.nominalConstructors(nidx as u32);
            if ctors.len != 1 { return 0, false; }
            let ctor = dm.constructor(ctors[0]);
            if ctor.payload == 0 { return 0, false; }
            let cases, cerr = g.types.variants(ty);
            if cerr != blot_direct_types::Error.none || cases.len != 1 { return 0, false; }
            let smark = subst.len;
            if g.hasUnit(cu) && ct != 0 && (ct as i64) < g.units[cu - 1].types.nodes.len {
                let cm .= g.units[cu - 1];
                let cn = cm.types.node(ct);
                if cn.tag == blot_check_types::Tag.nominal {
                    let args = cm.types.nominalArguments(cn);
                    let vars = dm.types.list(dm.nominals[nidx].variables);
                    if vars.len == args.len {
                        for vi in 0..vars.len {
                            let au, at = unwrapCoreFlatType(g, cu, args[vi], subst[..]);
                            subst.push(CoreSubstEntry { def_unit: ident.unit, var_id: vars[vi], arg_unit: au, arg_id: at });
                        }
                    }
                }
            }
            let w, ok = flatNumericWordCount(g, ident.unit, ctor.payload, g.types.variant_payloads[cases.payloads], subst, depth + 1);
            subst.resize(smark);
            return w, ok;
        },
        _ => { return 0, false; },
    }
}

// Recursively packs `val` of FlatNumeric type `ty` into linear memory starting at `dst_cursor`,
// advancing `dst_cursor` by `words * 4` bytes. Uses physical element `stride(E)` for `#[K; E]`
// and handles boxed >16-word structs seamlessly via `readFlat`/`recordField`/`tupleItem`.
recursive fn emitPackFlatNumeric(
    g: Generator&,
    f: Fn&,
    unit: u32,
    core_tid: TId,
    ty: Ty,
    val: Val,
    dst_cursor: u32,
    subst: CoreSubstEntry[>..]&,
    id: u32,
    depth: i64
) -> Error {
    if depth > 64 { return g.fail(g.units[f.unit - 1], id, "FlatNumeric pack depth limit"); }
    let cu, ct = unwrapCoreFlatType(g, unit, core_tid, subst[..]);
    let tn = g.types.node(ty);
    match tn.tag {
        u32_, boolean => {
            lget(g, dst_cursor);
            lget(g, w(g, val, 0));
            op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
            lget(g, dst_cursor);
            i32Const(g, 4);
            op(g, OP_i32_add);
            lset(g, dst_cursor);
            return blot_direct_types::Error.none;
        },
        f32_ => {
            lget(g, dst_cursor);
            lget(g, w(g, val, 0));
            op(g, OP_f32_store); uleb(g, 2); uleb(g, 0);
            lget(g, dst_cursor);
            i32Const(g, 4);
            op(g, OP_i32_add);
            lset(g, dst_cursor);
            return blot_direct_types::Error.none;
        },
        tuple => {
            var has_core = false;
            var core_start: u32 = 0;
            if g.hasUnit(cu) && ct != 0 && (ct as i64) < g.units[cu - 1].types.nodes.len {
                let cn = g.units[cu - 1].types.node(ct);
                if cn.tag == blot_check_types::Tag.product && cn.b == tn.b {
                    has_core = true;
                    core_start = cn.a;
                }
            }
            for i in 0..(tn.b as i64) {
                var child_ct: TId = 0;
                if has_core { child_ct = g.units[cu - 1].types.list(blot_check_types::List { core_start, tn.b })[i]; }
                let item, ierr = tupleItem(g, f, val, i, id);
                if ierr != blot_direct_types::Error.none { return ierr; }
                let perr = emitPackFlatNumeric(g, f, cu, child_ct, g.types.words[tn.a + i], item, dst_cursor, subst, id, depth + 1);
                if perr != blot_direct_types::Error.none { return perr; }
            }
            return blot_direct_types::Error.none;
        },
        record => {
            var has_core = false;
            var cn = blot_check_types::Node { tag: blot_check_types::Tag.unit, .. };
            if g.hasUnit(cu) && ct != 0 && (ct as i64) < g.units[cu - 1].types.nodes.len {
                cn = g.units[cu - 1].types.node(ct);
                if cn.tag == blot_check_types::Tag.record && cn.b == tn.b { has_core = true; }
            }
            for i in 0..(tn.b as i64) {
                let df = g.types.recordField(ty, i);
                var child_ct: TId = 0;
                if has_core {
                    let found_ct, ok = findCoreRecordFieldByName(g, g.units[cu - 1], cn, df.name);
                    if ok { child_ct = found_ct; }
                }
                let fv, ferr = recordField(g, f, val, i, id);
                if ferr != blot_direct_types::Error.none { return ferr; }
                let perr = emitPackFlatNumeric(g, f, cu, child_ct, df.ty, fv, dst_cursor, subst, id, depth + 1);
                if perr != blot_direct_types::Error.none { return perr; }
            }
            return blot_direct_types::Error.none;
        },
        array => {
            if !g.hasUnit(cu) || ct == 0 || (ct as i64) >= g.units[cu - 1].types.nodes.len {
                return g.failCode(g.units[f.unit - 1], id, blot_check_diagnostic_code::Code.kernel_type, "FlatNumeric pack requires sized #[K; E] array");
            }
            let cm .= g.units[cu - 1];
            let sinfo = blot_check_storage_types::info(cm.types, ct);
            if !sinfo.present || sinfo.value.kind != blot_check_storage_types::sized_array {
                return g.failCode(g.units[f.unit - 1], id, blot_check_diagnostic_code::Code.kernel_type, "FlatNumeric pack requires sized #[K; E] array");
            }
            let len_opt = blot_check_storage_types::lengthOf(cm.types, ct);
            if !len_opt.present { return g.fail(g.units[f.unit - 1], id, "sized array length missing"); }
            let lnode = cm.types.node(len_opt.value);
            let k = blot_check_storage_types::lengthLiteralValue(lnode.b);
            let elem_ty = tn.a;
            let elem_step, serr = stride(g, f, elem_ty, id);
            if serr != blot_direct_types::Error.none { return serr; }
            if (k as u64) * (elem_step as u64) > 0x0fffffff {
                return g.failCode(g.units[f.unit - 1], id, blot_check_diagnostic_code::Code.kernel_type, "sized array byte extent overflows arena");
            }
            let rt = g.runtime_();
            let entry = local32(g, f);
            let src_base = local32(g, f);
            lget(g, w(g, val, 0));
            lget(g, w(g, val, 1));
            callf(g, rt.check);
            ltee(g, entry);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
            i32Const(g, k);
            op(g, OP_i32_ne);
            trap(g, f);
            lget(g, entry);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
            lset(g, src_base);
            let etag = tagOf(g, elem_ty);
            if etag == blot_direct_types::Tag.u32_ || etag == blot_direct_types::Tag.f32_ {
                lget(g, dst_cursor);
                lget(g, src_base);
                i32Const(g, k * 4);
                memoryCopyOp(g);
                lget(g, dst_cursor);
                i32Const(g, k * 4);
                op(g, OP_i32_add);
                lset(g, dst_cursor);
                return blot_direct_types::Error.none;
            }
            // General physical-stride element loop (handles #[K; Bool], #[3; Big20Word], #[2; #[3; U32]], tuples, records).
            let idx = constLocal(g, f, 0);
            let elem_addr = local32(g, f);
            let exit = open(g, f, OP_block);
            let top = open(g, f, OP_loop);
            lget(g, idx);
            i32Const(g, k);
            op(g, OP_i32_ge_u);
            br(g, f, OP_br_if, exit);
            lget(g, src_base);
            lget(g, idx);
            i32Const(g, elem_step);
            op(g, OP_i32_mul);
            op(g, OP_i32_add);
            lset(g, elem_addr);
            let elem_val, rerr = loadElement(g, f, elem_addr, 0, elem_ty, id);
            if rerr != blot_direct_types::Error.none { return rerr; }
            let perr = emitPackFlatNumeric(g, f, cu, sinfo.value.element, elem_ty, elem_val, dst_cursor, subst, id, depth + 1);
            if perr != blot_direct_types::Error.none { return perr; }
            lget(g, idx);
            i32Const(g, 1);
            op(g, OP_i32_add);
            lset(g, idx);
            br(g, f, OP_br, top);
            close(g, f);
            close(g, f);
            return blot_direct_types::Error.none;
        },
        nominal => {
            let ident = g.types.nominalIdentity(ty);
            let dm .= g.units[ident.unit - 1];
            let nidx = findNominalDeclInUnit(dm, ident);
            let ctors = dm.nominalConstructors(nidx as u32);
            let ctor = dm.constructor(ctors[0]);
            let cases, cerr = g.types.variants(ty);
            if cerr != blot_direct_types::Error.none { return cerr; }
            let unwrapped, uerr = unwrapVariant(g, f, val, g.types.variant_tags[cases.tags], id);
            if uerr != blot_direct_types::Error.none { return uerr; }
            let smark = subst.len;
            if g.hasUnit(cu) && ct != 0 && (ct as i64) < g.units[cu - 1].types.nodes.len {
                let cm .= g.units[cu - 1];
                let cn = cm.types.node(ct);
                if cn.tag == blot_check_types::Tag.nominal {
                    let args = cm.types.nominalArguments(cn);
                    let vars = dm.types.list(dm.nominals[nidx].variables);
                    if vars.len == args.len {
                        for vi in 0..vars.len {
                            let au, at = unwrapCoreFlatType(g, cu, args[vi], subst[..]);
                            subst.push(CoreSubstEntry { def_unit: ident.unit, var_id: vars[vi], arg_unit: au, arg_id: at });
                        }
                    }
                }
            }
            let perr = emitPackFlatNumeric(g, f, ident.unit, ctor.payload, g.types.variant_payloads[cases.payloads], unwrapped, dst_cursor, subst, id, depth + 1);
            subst.resize(smark);
            return perr;
        },
        _ => {
            return g.failCode(g.units[f.unit - 1], id, blot_check_diagnostic_code::Code.kernel_type, "unsupported FlatNumeric pack type");
        },
    }
}

// Recursively unpacks a FlatNumeric value from linear memory at `src_cursor` (advancing `src_cursor`).
// - `allow_zero_copy`: true ONLY for read-only kernel/process input wrappers (NEVER `@flat.decode`!),
//   used strictly for `#[K; U32]` and `#[K; F32]`.
// - `trap_on_bad_bool`: true in ABI wrappers (traps if word > 1); false in `@flat.decode`
//   (sets `bad_bool_local = 1` so `@flat.decode` returns `$Nothing`).
recursive fn emitUnpackFlatNumeric(
    g: Generator&,
    f: Fn&,
    unit: u32,
    core_tid: TId,
    ty: Ty,
    src_cursor: u32,
    allow_zero_copy: bool,
    trap_on_bad_bool: bool,
    bad_bool_local: u32,
    subst: CoreSubstEntry[>..]&,
    id: u32,
    depth: i64
) -> Val, Error {
    if depth > 64 { return neverVal(), g.fail(g.units[f.unit - 1], id, "FlatNumeric unpack depth limit"); }
    let cu, ct = unwrapCoreFlatType(g, unit, core_tid, subst[..]);
    let tn = g.types.node(ty);
    match tn.tag {
        u32_ => {
            let res = local32(g, f);
            lget(g, src_cursor);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);
            lset(g, res);
            lget(g, src_cursor); i32Const(g, 4); op(g, OP_i32_add); lset(g, src_cursor);
            return valOf1(g, ty, res), blot_direct_types::Error.none;
        },
        f32_ => {
            let res = local(g, f, VT_f32);
            lget(g, src_cursor);
            op(g, OP_f32_load); uleb(g, 2); uleb(g, 0);
            lset(g, res);
            lget(g, src_cursor); i32Const(g, 4); op(g, OP_i32_add); lset(g, src_cursor);
            return valOf1(g, ty, res), blot_direct_types::Error.none;
        },
        boolean => {
            let res = local32(g, f);
            lget(g, src_cursor);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);
            ltee(g, res);
            i32Const(g, 1);
            op(g, OP_i32_gt_u);
            if trap_on_bad_bool {
                trap(g, f);
            } else {
                let bad_if = open(g, f, OP_if_);
                i32Const(g, 1);
                lset(g, bad_bool_local);
                i32Const(g, 0);
                lset(g, res);
                close(g, f);
            }
            lget(g, src_cursor); i32Const(g, 4); op(g, OP_i32_add); lset(g, src_cursor);
            return valOf1(g, ty, res), blot_direct_types::Error.none;
        },
        tuple => {
            var has_core = false;
            var core_start: u32 = 0;
            if g.hasUnit(cu) && ct != 0 && (ct as i64) < g.units[cu - 1].types.nodes.len {
                let cn = g.units[cu - 1].types.node(ct);
                if cn.tag == blot_check_types::Tag.product && cn.b == tn.b {
                    has_core = true;
                    core_start = cn.a;
                }
            }
            let boxed, berr = isBoxed(g, f, ty, id);
            if berr != blot_direct_types::Error.none { return neverVal(), berr; }
            if boxed {
                let blk, merr = newBlock(g, f, ty, id);
                if merr != blot_direct_types::Error.none { return neverVal(), merr; }
                for i in 0..(tn.b as i64) {
                    var child_ct: TId = 0;
                    if has_core { child_ct = g.units[cu - 1].types.list(blot_check_types::List { core_start, tn.b })[i]; }
                    let item_ty = g.types.words[tn.a + i];
                    let item, ierr = emitUnpackFlatNumeric(g, f, cu, child_ct, item_ty, src_cursor, allow_zero_copy, trap_on_bad_bool, bad_bool_local, subst, id, depth + 1);
                    if ierr != blot_direct_types::Error.none { return neverVal(), ierr; }
                    let off, oerr = itemOffset(g, f, ty, i, id);
                    if oerr != blot_direct_types::Error.none { return neverVal(), oerr; }
                    let werr = writeFlat(g, f, blk, off, item, id);
                    if werr != blot_direct_types::Error.none { return neverVal(), werr; }
                }
                return valOf1(g, ty, blk), blot_direct_types::Error.none;
            }
            let vals = g.reserveVals(tn.b as i64);
            for i in 0..(tn.b as i64) {
                var child_ct: TId = 0;
                if has_core { child_ct = g.units[cu - 1].types.list(blot_check_types::List { core_start, tn.b })[i]; }
                let item_ty = g.types.words[tn.a + i];
                let item, ierr = emitUnpackFlatNumeric(g, f, cu, child_ct, item_ty, src_cursor, allow_zero_copy, trap_on_bad_bool, bad_bool_local, subst, id, depth + 1);
                if ierr != blot_direct_types::Error.none { return neverVal(), ierr; }
                g.s.vals[vals.start + i] = item;
            }
            let start_w = g.s.words.len as u32;
            for i in 0..(tn.b as i64) {
                let item = g.s.vals[vals.start + i];
                for wi in 0..(item.len as i64) { let lw = g.s.words[item.start + wi]; g.s.words.push(lw); }
            }
            return Val { ty, start_w, (g.s.words.len as u32) - start_w }, blot_direct_types::Error.none;
        },
        record => {
            var has_core = false;
            var cn = blot_check_types::Node { tag: blot_check_types::Tag.unit, .. };
            if g.hasUnit(cu) && ct != 0 && (ct as i64) < g.units[cu - 1].types.nodes.len {
                cn = g.units[cu - 1].types.node(ct);
                if cn.tag == blot_check_types::Tag.record && cn.b == tn.b { has_core = true; }
            }
            let boxed, berr = isBoxed(g, f, ty, id);
            if berr != blot_direct_types::Error.none { return neverVal(), berr; }
            if boxed {
                let blk, merr = newBlock(g, f, ty, id);
                if merr != blot_direct_types::Error.none { return neverVal(), merr; }
                for i in 0..(tn.b as i64) {
                    let df = g.types.recordField(ty, i);
                    var child_ct: TId = 0;
                    if has_core {
                        let found_ct, ok = findCoreRecordFieldByName(g, g.units[cu - 1], cn, df.name);
                        if ok { child_ct = found_ct; }
                    }
                    let fv, ferr = emitUnpackFlatNumeric(g, f, cu, child_ct, df.ty, src_cursor, allow_zero_copy, trap_on_bad_bool, bad_bool_local, subst, id, depth + 1);
                    if ferr != blot_direct_types::Error.none { return neverVal(), ferr; }
                    let off, oerr = fieldOffset(g, f, ty, i, id);
                    if oerr != blot_direct_types::Error.none { return neverVal(), oerr; }
                    let werr = writeFlat(g, f, blk, off, fv, id);
                    if werr != blot_direct_types::Error.none { return neverVal(), werr; }
                }
                return valOf1(g, ty, blk), blot_direct_types::Error.none;
            }
            let vals = g.reserveVals(tn.b as i64);
            for i in 0..(tn.b as i64) {
                let df = g.types.recordField(ty, i);
                var child_ct: TId = 0;
                if has_core {
                    let found_ct, ok = findCoreRecordFieldByName(g, g.units[cu - 1], cn, df.name);
                    if ok { child_ct = found_ct; }
                }
                let fv, ferr = emitUnpackFlatNumeric(g, f, cu, child_ct, df.ty, src_cursor, allow_zero_copy, trap_on_bad_bool, bad_bool_local, subst, id, depth + 1);
                if ferr != blot_direct_types::Error.none { return neverVal(), ferr; }
                g.s.vals[vals.start + i] = fv;
            }
            let start_w = g.s.words.len as u32;
            for i in 0..(tn.b as i64) {
                let fv = g.s.vals[vals.start + i];
                for wi in 0..(fv.len as i64) { let lw = g.s.words[fv.start + wi]; g.s.words.push(lw); }
            }
            return Val { ty, start_w, (g.s.words.len as u32) - start_w }, blot_direct_types::Error.none;
        },
        array => {
            if !g.hasUnit(cu) || ct == 0 || (ct as i64) >= g.units[cu - 1].types.nodes.len {
                return neverVal(), g.failCode(g.units[f.unit - 1], id, blot_check_diagnostic_code::Code.kernel_type, "FlatNumeric unpack requires sized #[K; E] array");
            }
            let cm .= g.units[cu - 1];
            let sinfo = blot_check_storage_types::info(cm.types, ct);
            if !sinfo.present || sinfo.value.kind != blot_check_storage_types::sized_array {
                return neverVal(), g.failCode(g.units[f.unit - 1], id, blot_check_diagnostic_code::Code.kernel_type, "FlatNumeric unpack requires sized #[K; E] array");
            }
            let len_opt = blot_check_storage_types::lengthOf(cm.types, ct);
            if !len_opt.present { return neverVal(), g.fail(g.units[f.unit - 1], id, "sized array length missing"); }
            let lnode = cm.types.node(len_opt.value);
            let k = blot_check_storage_types::lengthLiteralValue(lnode.b);
            let elem_ty = tn.a;
            let elem_step, serr = stride(g, f, elem_ty, id);
            if serr != blot_direct_types::Error.none { return neverVal(), serr; }
            if (k as u64) * (elem_step as u64) > 0x0fffffff {
                return neverVal(), g.failCode(g.units[f.unit - 1], id, blot_check_diagnostic_code::Code.kernel_type, "sized array byte extent overflows arena");
            }
            let etag = tagOf(g, elem_ty);
            // Read-only zero-copy ONLY when `allow_zero_copy && E in {U32, F32}`.
            if allow_zero_copy && (etag == blot_direct_types::Tag.u32_ || etag == blot_direct_types::Tag.f32_) {
                noteAllocation(f);
                let rt = g.runtime_();
                lget(g, src_cursor);
                i32Const(g, k);
                i32Const(g, k * 4);
                callf(g, rt.open);
                let handle, perr = pop(g, f, ty, id);
                if perr != blot_direct_types::Error.none { return neverVal(), perr; }
                lget(g, src_cursor);
                i32Const(g, k * 4);
                op(g, OP_i32_add);
                lset(g, src_cursor);
                return handle, blot_direct_types::Error.none;
            }
            // Fresh independent owner allocated on stack.
            let k_loc = constLocal(g, f, k);
            let handle, dst_base, cerr = createUninit(g, f, ty, k_loc, id);
            if cerr != blot_direct_types::Error.none { return neverVal(), cerr; }
            if etag == blot_direct_types::Tag.u32_ || etag == blot_direct_types::Tag.f32_ {
                lget(g, dst_base);
                lget(g, src_cursor);
                i32Const(g, k * 4);
                memoryCopyOp(g);
                lget(g, src_cursor);
                i32Const(g, k * 4);
                op(g, OP_i32_add);
                lset(g, src_cursor);
                return handle, blot_direct_types::Error.none;
            }
            let idx = constLocal(g, f, 0);
            let dst_addr = local32(g, f);
            let exit = open(g, f, OP_block);
            let top = open(g, f, OP_loop);
            lget(g, idx);
            i32Const(g, k);
            op(g, OP_i32_ge_u);
            br(g, f, OP_br_if, exit);
            let elem_val, uerr = emitUnpackFlatNumeric(g, f, cu, sinfo.value.element, elem_ty, src_cursor, allow_zero_copy, trap_on_bad_bool, bad_bool_local, subst, id, depth + 1);
            if uerr != blot_direct_types::Error.none { return neverVal(), uerr; }
            lget(g, dst_base);
            lget(g, idx);
            i32Const(g, elem_step);
            op(g, OP_i32_mul);
            op(g, OP_i32_add);
            lset(g, dst_addr);
            let werr = writeElement(g, f, dst_addr, 0, elem_val, id);
            if werr != blot_direct_types::Error.none { return neverVal(), werr; }
            lget(g, idx);
            i32Const(g, 1);
            op(g, OP_i32_add);
            lset(g, idx);
            br(g, f, OP_br, top);
            close(g, f);
            close(g, f);
            return handle, blot_direct_types::Error.none;
        },
        nominal => {
            let ident = g.types.nominalIdentity(ty);
            let dm .= g.units[ident.unit - 1];
            let nidx = findNominalDeclInUnit(dm, ident);
            let ctors = dm.nominalConstructors(nidx as u32);
            let ctor = dm.constructor(ctors[0]);
            let cases, cerr = g.types.variants(ty);
            if cerr != blot_direct_types::Error.none { return neverVal(), cerr; }
            let smark = subst.len;
            if g.hasUnit(cu) && ct != 0 && (ct as i64) < g.units[cu - 1].types.nodes.len {
                let cm .= g.units[cu - 1];
                let cn = cm.types.node(ct);
                if cn.tag == blot_check_types::Tag.nominal {
                    let args = cm.types.nominalArguments(cn);
                    let vars = dm.types.list(dm.nominals[nidx].variables);
                    if vars.len == args.len {
                        for vi in 0..vars.len {
                            let au, at = unwrapCoreFlatType(g, cu, args[vi], subst[..]);
                            subst.push(CoreSubstEntry { def_unit: ident.unit, var_id: vars[vi], arg_unit: au, arg_id: at });
                        }
                    }
                }
            }
            let payload_val, perr = emitUnpackFlatNumeric(g, f, ident.unit, ctor.payload, g.types.variant_payloads[cases.payloads], src_cursor, allow_zero_copy, trap_on_bad_bool, bad_bool_local, subst, id, depth + 1);
            subst.resize(smark);
            if perr != blot_direct_types::Error.none { return neverVal(), perr; }
            return wrapVariant(g, f, ty, g.types.variant_tags[cases.tags], payload_val, id);
        },
        _ => {
            return neverVal(), g.failCode(g.units[f.unit - 1], id, blot_check_diagnostic_code::Code.kernel_type, "unsupported FlatNumeric unpack type");
        },
    }
}

// Lower `@flat.encode val` -> fresh `#[U32]`.
fn emitFlatEncodeVal(g: Generator&, f: Fn&, val: Val, arg_core_ty: TId, out_ty: Ty, id: u32) -> Val, Error {
    var subst: CoreSubstEntry[>..] = [];
    let words, ok = flatNumericWordCount(g, f.unit, arg_core_ty, val.ty, subst, 0);
    if !ok {
        return neverVal(), g.failCode(g.units[f.unit - 1], id, blot_check_diagnostic_code::Code.kernel_type, "@flat.encode requires a non-zero-width closed FlatNumeric type");
    }
    let w_loc = constLocal(g, f, words);
    let handle, dst_base, cerr = createUninit(g, f, out_ty, w_loc, id);
    if cerr != blot_direct_types::Error.none { return neverVal(), cerr; }
    let dst_cursor = local32(g, f);
    lget(g, dst_base);
    lset(g, dst_cursor);
    let perr = emitPackFlatNumeric(g, f, f.unit, arg_core_ty, val.ty, val, dst_cursor, subst, id, 0);
    if perr != blot_direct_types::Error.none { return neverVal(), perr; }
    return handle, blot_direct_types::Error.none;
}

// Lower `@flat.decode src` -> `Maybe a` (validating `src.length == stride(a)` BEFORE allocating,
// fresh non-aliasing owner, returning `$Nothing` on length mismatch or non-canonical Bool > 1).
fn emitFlatDecodeVal(g: Generator&, f: Fn&, src: Val, result_core_ty: TId, maybe_ty: Ty, id: u32) -> Val, Error {
    let cases, cerr = g.types.variants(maybe_ty);
    if cerr != blot_direct_types::Error.none || cases.len != 2 {
        return neverVal(), g.failCode(g.units[f.unit - 1], id, blot_check_diagnostic_code::Code.kernel_type, "@flat.decode requires a Maybe result type");
    }
    var nothing_tag: u32 = 0;
    var some_tag: u32 = 0;
    var target_ty: Ty = 0;
    var found_some = false;
    for ci in 0..2 {
        let pty = g.types.variant_payloads[cases.payloads + ci];
        let vtag = g.types.variant_tags[cases.tags + ci];
        if pty == blot_direct_types::unit { nothing_tag = vtag; }
        else { some_tag = vtag; target_ty = pty; found_some = true; }
    }
    if !found_some {
        return neverVal(), g.failCode(g.units[f.unit - 1], id, blot_check_diagnostic_code::Code.kernel_type, "@flat.decode target type cannot be Unit");
    }
    // Extract inner Core TId `a` from `Maybe a` if available.
    var target_core_ty: TId = 0;
    if result_core_ty != 0 {
        let m .= g.units[f.unit - 1];
        var cur_rt = result_core_ty;
        for _ in 0..16 {
            if (cur_rt as i64) >= m.types.nodes.len { break; }
            let rn = m.types.node(cur_rt);
            if rn.tag == blot_check_types::Tag.usage || rn.tag == blot_check_types::Tag.forall { cur_rt = rn.a; continue; }
            if rn.tag == blot_check_types::Tag.nominal {
                let rargs = m.types.nominalArguments(rn);
                if rargs.len == 1 { target_core_ty = rargs[0]; }
            }
            break;
        }
    }
    var subst: CoreSubstEntry[>..] = [];
    let words, ok = flatNumericWordCount(g, f.unit, target_core_ty, target_ty, subst, 0);
    if !ok {
        return neverVal(), g.failCode(g.units[f.unit - 1], id, blot_check_diagnostic_code::Code.kernel_type, "@flat.decode requires a non-zero-width closed FlatNumeric target type");
    }
    let rt = g.runtime_();
    let result, rerr = fresh(g, f, maybe_ty, id);
    if rerr != blot_direct_types::Error.none { return neverVal(), rerr; }
    let src_entry = local32(g, f);
    lget(g, w(g, src, 0));
    lget(g, w(g, src, 1));
    callf(g, rt.check);
    ltee(g, src_entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
    i32Const(g, words);
    op(g, OP_i32_eq);
    let len_if = open(g, f, OP_if_);
    // Length matches: unpack into fresh non-aliasing storage checking canonical Bool words.
    let src_cursor = local32(g, f);
    let bad_bool = constLocal(g, f, 0);
    lget(g, src_entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
    lset(g, src_cursor);
    let unpacked, uerr = emitUnpackFlatNumeric(g, f, f.unit, target_core_ty, target_ty, src_cursor, false, false, bad_bool, subst, id, 0);
    if uerr != blot_direct_types::Error.none { return neverVal(), uerr; }
    lget(g, bad_bool);
    op(g, OP_i32_eqz);
    let ok_if = open(g, f, OP_if_);
    let some_v, swerr = wrapVariant(g, f, maybe_ty, some_tag, unpacked, id);
    if swerr != blot_direct_types::Error.none { return neverVal(), swerr; }
    let scerr = copy(g, f, some_v, result, id);
    if scerr != blot_direct_types::Error.none { return neverVal(), scerr; }
    popCheckedArraysAt(f, ok_if);
    op(g, OP_else_);
    let noth_v1, nwerr1 = wrapVariant(g, f, maybe_ty, nothing_tag, unitVal(), id);
    if nwerr1 != blot_direct_types::Error.none { return neverVal(), nwerr1; }
    let ncerr1 = copy(g, f, noth_v1, result, id);
    if ncerr1 != blot_direct_types::Error.none { return neverVal(), ncerr1; }
    close(g, f);
    popCheckedArraysAt(f, len_if);
    op(g, OP_else_);
    // Length mismatch BEFORE allocating target storage: return $Nothing.
    let noth_v2, nwerr2 = wrapVariant(g, f, maybe_ty, nothing_tag, unitVal(), id);
    if nwerr2 != blot_direct_types::Error.none { return neverVal(), nwerr2; }
    let ncerr2 = copy(g, f, noth_v2, result, id);
    if ncerr2 != blot_direct_types::Error.none { return neverVal(), ncerr2; }
    close(g, f);
    return result, blot_direct_types::Error.none;
}

// --- ABI 8 helpers & WireSchema custom section encoding (§3.1 & §3.2) ---

fn abiFromWireTag(wire_tag: u8) -> Abi {
    if wire_tag == blot_check_wire_schema::WIRE_TAG_UNIT { return Abi.unit; }
    if wire_tag == blot_check_wire_schema::WIRE_TAG_U32 { return Abi.u32_; }
    if wire_tag == blot_check_wire_schema::WIRE_TAG_BOOL { return Abi.bool_; }
    if wire_tag == blot_check_wire_schema::WIRE_TAG_F32 { return Abi.f32_; }
    if wire_tag == blot_check_wire_schema::WIRE_TAG_ARRAY_F32 { return Abi.array_f32; }
    return Abi.array_u32;
}

fn exportNamedEntry(
    g: Generator&,
    name: Chars,
    abi: u8[>..<]&,
    function: u32,
    param_abi: Abi,
    result_abi: Abi,
    packets: bool
) {
    g.module.exportItem(name, blot_direct_writer::EXPORT_function, function);
    blot_direct_writer::name(abi, name);
    abi.push(abiCode(param_abi));
    abi.push(abiCode(result_abi));
    if packets && !g.s.exported_storage {
        let allocate_function = g.runtime_().allocate;
        let reset = g.runtime_().reset;
        g.s.exported_storage = true;
        g.module.exportItem("blot:memory", blot_direct_writer::EXPORT_memory, 0);
        g.module.exportItem("blot:allocate", blot_direct_writer::EXPORT_function, allocate_function);
        g.module.exportItem("blot:reset", blot_direct_writer::EXPORT_function, reset);
    }
}

fn pushU64Le(out: u8[>..<]&, v: u64) {
    for i in 0..8 {
        out.push(((v >> ((i * 8) as u64)) & 0xff) as u8);
    }
}

fn encodeWireSchemaSection(out: u8[>..<]&, g: const Generator&, s: blot_check_wire_schema::WireSchema) {
    out.push(s.kind);
    out.push(s.wire_tag);
    blot_direct_writer::uleb(out, s.stride as u64);
    if s.kind == blot_check_wire_schema::SCHEMA_KIND_FLAT_FIXED {
        for i in 0..(s.tags_len as i64) {
            out.push(g.s.wire_word_tags[(s.tags_start as i64) + i]);
        }
    }
    pushU64Le(out, s.schema_hash);
}

// Unpack a single kernel context / process Config / process Cmd input parameter (local 0).
fn emitUnpackWireInput(
    g: Generator&,
    f: Fn&,
    unit: u32,
    core_tid: TId,
    ty: Ty,
    schema: blot_check_wire_schema::WireSchema,
    param_abi: Abi
) -> Val, Error {
    if schema.kind == blot_check_wire_schema::SCHEMA_KIND_UNIT {
        return unitVal(), blot_direct_types::Error.none;
    }
    if schema.kind == blot_check_wire_schema::SCHEMA_KIND_VAR_U32 || schema.kind == blot_check_wire_schema::SCHEMA_KIND_VAR_F32 {
        return fromPacket(g, f, ty, 0, true);
    }
    // SCHEMA_KIND_FLAT_FIXED: scalar wire (1 word, non-array ABI) vs packet wire (array ABI).
    var subst: CoreSubstEntry[>..] = [];
    if !isArray(param_abi) {
        let scratch = allocate(g, f, 4);
        let cursor = local32(g, f);
        lget(g, scratch);
        lget(g, 0);
        if param_abi == Abi.f32_ { op(g, OP_f32_store); } else { op(g, OP_i32_store); }
        uleb(g, 2); uleb(g, 0);
        lget(g, scratch);
        lset(g, cursor);
        return emitUnpackFlatNumeric(g, f, unit, core_tid, ty, cursor, true, true, 0, subst, 0, 0);
    }
    let rt = g.runtime_();
    let in_words = local32(g, f);
    lget(g, 0);
    callf(g, rt.packet_length);
    ltee(g, in_words);
    i32Const(g, schema.stride);
    op(g, OP_i32_ne);
    trap(g, f);
    let cursor = local32(g, f);
    lget(g, 0);
    i32Const(g, 4);
    op(g, OP_i32_add);
    lset(g, cursor);
    return emitUnpackFlatNumeric(g, f, unit, core_tid, ty, cursor, true, true, 0, subst, 0, 0);
}

// Emit all `#kernel` wrappers (`<name>`, `blot:kernel_ctx:<name>`, `blot:kernel_clear:<name>`)
// and append their entries to `abi`, returning the count of exported ABI entries added.
fn emitKernelExports(g: Generator&, m: const Module&, abi: u8[>..<]&) -> u32, Error {
    if m.kernels.len == 0 { return 0, blot_direct_types::Error.none; }
    let rt = g.runtime_();
    let max_out_words = (rt.layout.transport_end - rt.layout.transport_base - 4) / 4;
    var added: u32 = 0;

    for ki in 0..m.kernels.len {
        let decl = m.kernels[ki];
        let kinfo = g.s.kernels[ki];

        let item_ty, iterr = g.types.lower(m, decl.item_type, Env {});
        if iterr != blot_direct_types::Error.none { return 0, g.failCode(m, 0, blot_check_diagnostic_code::Code.kernel_type, "#kernel Item needs a concrete type"); }
        let out_ty, oterr = g.types.lower(m, decl.out_type, Env {});
        if oterr != blot_direct_types::Error.none { return 0, g.failCode(m, 0, blot_check_diagnostic_code::Code.kernel_type, "#kernel Out needs a concrete type"); }

        var root = PersistRoot {};
        var prepared_ty: Ty = 0;
        var run_fn_ty: Ty = 0;

        if decl.has_context {
            let ctx_ty, cterr = g.types.lower(m, decl.ctx_type, Env {});
            if cterr != blot_direct_types::Error.none { return 0, g.failCode(m, 0, blot_check_diagnostic_code::Code.kernel_type, "#kernel WireCtx needs a concrete type"); }
            let p_ty, pterr = g.types.lower(m, decl.prepared_type, Env {});
            if pterr != blot_direct_types::Error.none { return 0, g.failCode(m, 0, blot_check_diagnostic_code::Code.kernel_type, "#kernel PreparedCtx needs a concrete type"); }
            prepared_ty = p_ty;
            let created_root, rerr = createPersistRoot(g, prepared_ty);
            if rerr != blot_direct_types::Error.none { return 0, rerr; }
            root = created_root;

            let prep_fn_ty, pferr = g.types.function(ctx_ty, prepared_ty);
            if pferr != blot_direct_types::Error.none { return 0, pferr; }
            let prep_target = g.resolve(m, decl.prepare_target);
            let prep_inst, pierr = g.named(prep_target, prep_fn_ty, m, 0);
            if pierr != blot_direct_types::Error.none { return 0, pierr; }

            let inner_fn_ty, iferr = g.types.function(item_ty, out_ty);
            if iferr != blot_direct_types::Error.none { return 0, iferr; }
            let rf_ty, rferr = g.types.function(prepared_ty, inner_fn_ty);
            if rferr != blot_direct_types::Error.none { return 0, rferr; }
            run_fn_ty = rf_ty;

            // 1. Export `blot:kernel_ctx:<name>` (ctx_abi -> Unit).
            let ctx_abi = abiFromWireTag(kinfo.ctx_schema.wire_tag);
            let ctx_fn = g.module.addFunction(g.module.signature([abiMachine(ctx_abi)], [VT_i32]));
            {
                var f = newFn(g, m.unit, 0);
                let _p0 = local(g, f, abiMachine(ctx_abi));
                f.parameter_words = 1;
                resetEntry(g);
                // Do NOT modify root.status_global during prepare or Phase 1!
                let wire_ctx, uerr = emitUnpackWireInput(g, f, m.unit, decl.ctx_type, ctx_ty, kinfo.ctx_schema, ctx_abi);
                if uerr != blot_direct_types::Error.none { return 0, uerr; }
                push(g, wire_ctx);
                callf(g, g.s.instances[prep_inst].function);
                let inst_res = g.s.instances[prep_inst].result;
                if inst_res == blot_direct_types::never {
                    op(g, OP_unreachable_);
                } else {
                    let prepared_val, perr = pop(g, f, inst_res, 0);
                    if perr != blot_direct_types::Error.none { return 0, perr; }
                    let serr = emitStageRoot(g, f, root, prepared_val, false, 0, 0, 0, 0);
                    if serr != blot_direct_types::Error.none { return 0, serr; }
                    i32Const(g, 0);
                }
                op(g, OP_end);
                finish(g, ctx_fn, f);
            }
            var ctx_name: u8[>..<] = [];
            ctx_name.append("blot:kernel_ctx:");
            ctx_name.append(m.name(decl.name));
            exportNamedEntry(g, ctx_name[..], abi, ctx_fn, ctx_abi, Abi.unit, isArray(ctx_abi));
            added += 1;

            // 2. Export `blot:kernel_clear:<name>` (Unit -> Unit).
            let clear_fn = g.module.addFunction(g.module.signature([VT_i32], [VT_i32]));
            {
                var f = newFn(g, m.unit, 0);
                let _p0 = local(g, f, VT_i32);
                f.parameter_words = 1;
                resetEntry(g);
                let cerr = emitClearRoot(g, f, root);
                if cerr != blot_direct_types::Error.none { return 0, cerr; }
                i32Const(g, 0);
                op(g, OP_end);
                finish(g, clear_fn, f);
            }
            var clear_name: u8[>..<] = [];
            clear_name.append("blot:kernel_clear:");
            clear_name.append(m.name(decl.name));
            exportNamedEntry(g, clear_name[..], abi, clear_fn, Abi.unit, Abi.unit, false);
            added += 1;
        } else {
            let rf_ty, rferr = g.types.function(item_ty, out_ty);
            if rferr != blot_direct_types::Error.none { return 0, rferr; }
            run_fn_ty = rf_ty;
        }

        let run_target = g.resolve(m, decl.run_target);
        let run_inst, rierr = g.named(run_target, run_fn_ty, m, 0);
        if rierr != blot_direct_types::Error.none { return 0, rierr; }

        // 3. Export `<name>` (in_abi -> out_abi).
        let in_abi = abiFromWireTag(kinfo.in_schema.wire_tag);
        let out_abi = abiFromWireTag(kinfo.out_schema.wire_tag);
        let run_fn = g.module.addFunction(g.module.signature([VT_i32], [VT_i32]));
        {
            var f = newFn(g, m.unit, 0);
            let _p0 = local(g, f, VT_i32);
            f.parameter_words = 1;
            resetEntry(g);
            // Pre-check ctx_status == 1 EVEN for count == 0 (§4.2.3)!
            if decl.has_context {
                gget(g, root.status_global);
                i32Const(g, 1);
                op(g, OP_i32_ne);
                trap(g, f);
            }
            let in_words = local32(g, f);
            let count = local32(g, f);
            lget(g, 0);
            callf(g, rt.packet_length);
            ltee(g, in_words);
            i32Const(g, kinfo.in_schema.stride);
            op(g, OP_i32_rem_u);
            trap(g, f);
            lget(g, in_words);
            i32Const(g, kinfo.in_schema.stride);
            op(g, OP_i32_div_u);
            lset(g, count);

            var prep_val = unitVal();
            if decl.has_context {
                let pv, pverr = loadPersistRootVal(g, f, root);
                if pverr != blot_direct_types::Error.none { return 0, pverr; }
                prep_val = pv;
            }

            let src_cursor = local32(g, f);
            lget(g, 0);
            i32Const(g, 4);
            op(g, OP_i32_add);
            lset(g, src_cursor);

            var subst: CoreSubstEntry[>..] = [];
            if !kinfo.variable_output {
                // Fixed-output batch kernel: disjoint output via rt.open_transport_pin.
                let out_stride = kinfo.out_schema.stride;
                let max_count = max_out_words / out_stride;
                lget(g, count);
                i32Const(g, max_count);
                op(g, OP_i32_gt_u);
                trap(g, f);
                let out_words = local32(g, f);
                let out_bytes = local32(g, f);
                lget(g, count);
                i32Const(g, out_stride);
                op(g, OP_i32_mul);
                ltee(g, out_words);
                i32Const(g, 2);
                op(g, OP_i32_shl);
                i32Const(g, 4);
                op(g, OP_i32_add);
                lset(g, out_bytes);

                let out_pin = local32(g, f);
                let out_base = local32(g, f);
                let out_cap = local32(g, f);
                lget(g, out_bytes);
                callf(g, rt.open_transport_pin);
                lset(g, out_cap);
                lset(g, out_base);
                op(g, OP_drop);
                lset(g, out_pin);
                lget(g, out_base);
                lget(g, out_words);
                op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);

                let dst_cursor = local32(g, f);
                lget(g, out_base);
                i32Const(g, 4);
                op(g, OP_i32_add);
                lset(g, dst_cursor);

                let idx = constLocal(g, f, 0);
                let loop_om = local32(g, f);
                let loop_sm = local32(g, f);
                let loop_esc = local32(g, f);
                let exit = open(g, f, OP_block);
                let top = open(g, f, OP_loop);
                lget(g, idx);
                lget(g, count);
                op(g, OP_i32_ge_u);
                br(g, f, OP_br_if, exit);
                markInto(g, g.s.code, loop_om, loop_sm);
                gget(g, rt.escape_min_slot); lset(g, loop_esc);
                i32Const(g, 0xffffffff); gset(g, rt.escape_min_slot);
                let item_val, uerr = emitUnpackFlatNumeric(g, f, m.unit, decl.item_type, item_ty, src_cursor, true, true, 0, subst, 0, 0);
                if uerr != blot_direct_types::Error.none { return 0, uerr; }
                if decl.has_context { push(g, prep_val); }
                push(g, item_val);
                callf(g, g.s.instances[run_inst].function);
                let rres = g.s.instances[run_inst].result;
                if rres == blot_direct_types::never {
                    op(g, OP_unreachable_);
                } else {
                    let out_val, perr = pop(g, f, rres, 0);
                    if perr != blot_direct_types::Error.none { return 0, perr; }
                    let pkerr = emitPackFlatNumeric(g, f, m.unit, decl.out_type, out_ty, out_val, dst_cursor, subst, 0, 0);
                    if pkerr != blot_direct_types::Error.none { return 0, pkerr; }
                    releaseTo(g, loop_om, loop_sm);
                    lget(g, loop_esc); gset(g, rt.escape_min_slot);
                    lget(g, idx); i32Const(g, 1); op(g, OP_i32_add); lset(g, idx);
                    br(g, f, OP_br, top);
                }
                close(g, f);
                close(g, f);

                // Commit output bank via transport pool AFTER loop finishes cleanly.
                lget(g, out_pin);
                callf(g, rt.detach_temp_slot);
                gget(g, rt.transport_cap);
                let old_t = open(g, f, OP_if_);
                gget(g, rt.transport_base);
                gget(g, rt.transport_cap);
                callf(g, rt.free_transport);
                close(g, f);
                lget(g, out_base); gset(g, rt.transport_base);
                lget(g, out_cap); gset(g, rt.transport_cap);
                lget(g, out_base); lget(g, out_bytes); op(g, OP_i32_add); gset(g, rt.transport_top);
                releaseEntry(g);
                lget(g, out_base);
            } else {
                // Variable-output batch kernel: heap accumulator `acc` + transport-pool commit +
                // non-trapping `[0xffffffff]` overflow sentinel!
                let acc_slot = local32(g, f);
                let acc_gen = local32(g, f);
                i32Const(g, 1);
                i32Const(g, 4);
                i32Const(g, 1);
                callf(g, rt.create);
                lset(g, acc_gen);
                lset(g, acc_slot);

                let overflow = constLocal(g, f, 0);
                let idx = constLocal(g, f, 0);
                let loop_om = local32(g, f);
                let loop_sm = local32(g, f);
                let loop_esc = local32(g, f);
                let row_entry = local32(g, f);
                let row_len = local32(g, f);
                let row_base = local32(g, f);
                let acc_entry = local32(g, f);
                let acc_len = local32(g, f);
                let hdr_addr = local32(g, f);
                let cur_len = local32(g, f);
                let new_len = local32(g, f);
                let need = local32(g, f);
                let cap_bytes = local32(g, f);
                let dbl = local32(g, f);
                let nb = local32(g, f);
                let nc = local32(g, f);
                let ob = local32(g, f);

                let exit = open(g, f, OP_block);
                let top = open(g, f, OP_loop);
                lget(g, idx);
                lget(g, count);
                op(g, OP_i32_ge_u);
                br(g, f, OP_br_if, exit);
                markInto(g, g.s.code, loop_om, loop_sm);
                gget(g, rt.escape_min_slot); lset(g, loop_esc);
                i32Const(g, 0xffffffff); gset(g, rt.escape_min_slot);
                let item_val, uerr = emitUnpackFlatNumeric(g, f, m.unit, decl.item_type, item_ty, src_cursor, true, true, 0, subst, 0, 0);
                if uerr != blot_direct_types::Error.none { return 0, uerr; }
                if decl.has_context { push(g, prep_val); }
                push(g, item_val);
                callf(g, g.s.instances[run_inst].function);
                let rres = g.s.instances[run_inst].result;
                if rres == blot_direct_types::never {
                    op(g, OP_unreachable_);
                } else {
                    let row_val, perr = pop(g, f, rres, 0);
                    if perr != blot_direct_types::Error.none { return 0, perr; }
                    lget(g, w(g, row_val, 0));
                    lget(g, w(g, row_val, 1));
                    callf(g, rt.check);
                    ltee(g, row_entry);
                    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
                    lset(g, row_len);
                    lget(g, row_entry);
                    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
                    lset(g, row_base);

                    lget(g, acc_slot);
                    lget(g, acc_gen);
                    callf(g, rt.check);
                    ltee(g, acc_entry);
                    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
                    lset(g, acc_len);

                    // Check overflow: row_len > max_out_words || acc_len + 1 + row_len > max_out_words + 1.
                    lget(g, row_len);
                    i32Const(g, max_out_words);
                    op(g, OP_i32_gt_u);
                    lget(g, acc_len);
                    i32Const(g, 1);
                    op(g, OP_i32_add);
                    lget(g, row_len);
                    op(g, OP_i32_add);
                    i32Const(g, max_out_words + 1);
                    op(g, OP_i32_gt_u);
                    op(g, OP_i32_or);
                    let ov_if = open(g, f, OP_if_);
                    i32Const(g, 1);
                    lset(g, overflow);
                    br(g, f, OP_br, exit);
                    close(g, f);

                    // Push row length header word.
                    lget(g, acc_slot);
                    lget(g, acc_gen);
                    i32Const(g, 4);
                    callf(g, rt.push);
                    ltee(g, hdr_addr);
                    lget(g, row_len);
                    op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);

                    // Bulk-append row_len payload words onto acc.
                    lget(g, row_len);
                    let has_words = open(g, f, OP_if_);
                    lget(g, acc_slot);
                    lget(g, acc_gen);
                    callf(g, rt.check);
                    ltee(g, acc_entry);
                    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
                    ltee(g, cur_len);
                    lget(g, row_len);
                    op(g, OP_i32_add);
                    ltee(g, new_len);
                    i32Const(g, 2);
                    op(g, OP_i32_shl);
                    lset(g, need);
                    lget(g, acc_entry);
                    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_capacity);
                    i32Const(g, blot_direct_runtime::capacity_mask);
                    op(g, OP_i32_and);
                    lset(g, cap_bytes);
                    lget(g, need);
                    lget(g, cap_bytes);
                    op(g, OP_i32_gt_u);
                    let gr_if = open(g, f, OP_if_);
                    lget(g, cap_bytes); i32Const(g, 1); op(g, OP_i32_shl); lset(g, dbl);
                    lget(g, need); lget(g, dbl); lget(g, need); lget(g, dbl); op(g, OP_i32_gt_u); op(g, OP_select);
                    callf(g, rt.heap_alloc);
                    lset(g, nc); lset(g, nb);
                    lget(g, acc_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base); lset(g, ob);
                    lget(g, nb); lget(g, ob); lget(g, cur_len); i32Const(g, 2); op(g, OP_i32_shl); memoryCopyOp(g);
                    lget(g, ob); lget(g, cap_bytes); callf(g, rt.heap_free);
                    lget(g, acc_entry); lget(g, nb); op(g, OP_i32_store); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
                    lget(g, acc_entry); lget(g, nc); i32Const(g, blot_direct_runtime::heap_flag | blot_direct_runtime::live_flag); op(g, OP_i32_or); op(g, OP_i32_store); uleb(g, 2); uleb(g, blot_direct_runtime::entry_capacity);
                    close(g, f); // gr_if
                    lget(g, acc_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
                    lget(g, cur_len); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
                    lget(g, row_base);
                    lget(g, row_len); i32Const(g, 2); op(g, OP_i32_shl);
                    memoryCopyOp(g);
                    lget(g, acc_entry); lget(g, new_len); op(g, OP_i32_store); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
                    close(g, f); // has_words

                    releaseTo(g, loop_om, loop_sm);
                    lget(g, loop_esc); gset(g, rt.escape_min_slot);
                    lget(g, idx); i32Const(g, 1); op(g, OP_i32_add); lset(g, idx);
                    br(g, f, OP_br, top);
                }
                close(g, f);
                close(g, f);

                let out_pkt = local32(g, f);
                lget(g, overflow);
                let ov_out = open(g, f, OP_if_);
                // Non-trapping [0xffffffff] overflow sentinel in transport bank!
                gget(g, rt.transport_cap);
                i32Const(g, 4);
                op(g, OP_i32_lt_u);
                let need_t4 = open(g, f, OP_if_);
                let p_slot = local32(g, f);
                let p_base = local32(g, f);
                let p_cap = local32(g, f);
                i32Const(g, 4); callf(g, rt.open_transport_pin);
                lset(g, p_cap); lset(g, p_base); op(g, OP_drop); lset(g, p_slot);
                lget(g, p_slot); callf(g, rt.detach_temp_slot);
                gget(g, rt.transport_cap);
                let had_o = open(g, f, OP_if_);
                gget(g, rt.transport_base); gget(g, rt.transport_cap); callf(g, rt.free_transport);
                close(g, f);
                lget(g, p_base); gset(g, rt.transport_base);
                lget(g, p_cap); gset(g, rt.transport_cap);
                close(g, f); // need_t4
                gget(g, rt.transport_base);
                ltee(g, out_pkt);
                i32Const(g, 0xffffffff);
                op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
                lget(g, out_pkt);
                i32Const(g, 4);
                op(g, OP_i32_add);
                gset(g, rt.transport_top);
                op(g, OP_else_);
                // Normal variable output commit: copy acc into transport bank (NEVER swap heap into transport!).
                let acc_base = local32(g, f);
                let acc_bytes = local32(g, f);
                lget(g, acc_slot); lget(g, acc_gen); callf(g, rt.check); ltee(g, acc_entry);
                op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base); lset(g, acc_base);
                lget(g, acc_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length); lset(g, acc_len);
                lget(g, acc_base); lget(g, acc_len); i32Const(g, 1); op(g, OP_i32_sub);
                op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
                lget(g, acc_len); i32Const(g, 2); op(g, OP_i32_shl); ltee(g, acc_bytes);
                gget(g, rt.transport_cap);
                op(g, OP_i32_le_u);
                let fits = open(g, f, OP_if_);
                gget(g, rt.transport_base); ltee(g, out_pkt);
                lget(g, acc_base); lget(g, acc_bytes); memoryCopyOp(g);
                lget(g, out_pkt); lget(g, acc_bytes); op(g, OP_i32_add); gset(g, rt.transport_top);
                op(g, OP_else_);
                let p_slot2 = local32(g, f);
                let p_base2 = local32(g, f);
                let p_cap2 = local32(g, f);
                lget(g, acc_bytes); callf(g, rt.open_transport_pin);
                lset(g, p_cap2); lset(g, p_base2); op(g, OP_drop); lset(g, p_slot2);
                lget(g, p_base2); lget(g, acc_base); lget(g, acc_bytes); memoryCopyOp(g);
                lget(g, p_slot2); callf(g, rt.detach_temp_slot);
                gget(g, rt.transport_cap);
                let had_o2 = open(g, f, OP_if_);
                gget(g, rt.transport_base); gget(g, rt.transport_cap); callf(g, rt.free_transport);
                close(g, f);
                lget(g, p_base2); gset(g, rt.transport_base);
                lget(g, p_cap2); gset(g, rt.transport_cap);
                lget(g, p_base2); lget(g, acc_bytes); op(g, OP_i32_add); gset(g, rt.transport_top);
                lget(g, p_base2); lset(g, out_pkt);
                close(g, f); // fits
                close(g, f); // ov_out
                releaseEntry(g);
                lget(g, out_pkt);
            }
            op(g, OP_end);
            finish(g, run_fn, f);
        }
        exportNamedEntry(g, m.name(decl.name), abi, run_fn, in_abi, out_abi, true);
        added += 1;
    }

    // Emit `blot:kernels` v1 custom section (§3.2).
    var sec: u8[>..<] = [];
    blot_direct_writer::uleb(sec, 1);
    blot_direct_writer::uleb(sec, (rt.layout.transport_end - rt.layout.transport_base) as u64);
    blot_direct_writer::uleb(sec, m.kernels.len as u64);
    for ki in 0..m.kernels.len {
        let decl = m.kernels[ki];
        let kinfo = g.s.kernels[ki];
        let kname = m.name(decl.name);
        blot_direct_writer::name(sec, kname);
        sec.push(kinfo.flags);
        encodeWireSchemaSection(sec, g, kinfo.in_schema);
        encodeWireSchemaSection(sec, g, kinfo.out_schema);
        pushU64Le(sec, kinfo.io_schema_hash);
        pushU64Le(sec, kinfo.impl_hash);
        pushU64Le(sec, kinfo.binding_hash);
        if kinfo.has_context {
            encodeWireSchemaSection(sec, g, kinfo.ctx_schema);
            var ctx_name: u8[>..<] = [];
            ctx_name.append("blot:kernel_ctx:");
            ctx_name.append(kname);
            blot_direct_writer::name(sec, ctx_name[..]);
            var clear_name: u8[>..<] = [];
            clear_name.append("blot:kernel_clear:");
            clear_name.append(kname);
            blot_direct_writer::name(sec, clear_name[..]);
        }
    }
    g.module.custom("blot:kernels", sec[..]);
    return added, blot_direct_types::Error.none;
}

// Emit all `#process` wrappers (`blot:proc_init:<name>`, `blot:proc_step:<name>`)
// and `blot:processes` v1 custom section (§3.1, §3.2, §4.2.2 item 5).
fn emitProcessExports(g: Generator&, m: const Module&, abi: u8[>..<]&) -> u32, Error {
    if m.processes.len == 0 { return 0, blot_direct_types::Error.none; }
    let rt = g.runtime_();
    let max_out_words = (rt.layout.transport_end - rt.layout.transport_base - 4) / 4;
    var added: u32 = 0;

    for pi in 0..m.processes.len {
        let decl = m.processes[pi];
        let pinfo = g.s.processes[pi];

        let cfg_ty, cterr = g.types.lower(m, decl.config_type, Env {});
        if cterr != blot_direct_types::Error.none { return 0, g.failCode(m, 0, blot_check_diagnostic_code::Code.kernel_type, "#process Config needs a concrete type"); }
        let state_ty, sterr = g.types.lower(m, decl.state_type, Env {});
        if sterr != blot_direct_types::Error.none { return 0, g.failCode(m, 0, blot_check_diagnostic_code::Code.kernel_type, "#process State needs a concrete type"); }
        let cmd_ty, cmterr = g.types.lower(m, decl.cmd_type, Env {});
        if cmterr != blot_direct_types::Error.none { return 0, g.failCode(m, 0, blot_check_diagnostic_code::Code.kernel_type, "#process Cmd needs a concrete type"); }
        let rep_ty, rterr = g.types.lower(m, decl.reply_type, Env {});
        if rterr != blot_direct_types::Error.none { return 0, g.failCode(m, 0, blot_check_diagnostic_code::Code.kernel_type, "#process Reply needs a concrete type"); }

        let root, rerr = createPersistRoot(g, state_ty);
        if rerr != blot_direct_types::Error.none { return 0, rerr; }

        let init_fn_ty, iferr = g.types.function(cfg_ty, state_ty);
        if iferr != blot_direct_types::Error.none { return 0, iferr; }
        let init_inst, iierr = g.named(g.resolve(m, decl.init_target), init_fn_ty, m, 0);
        if iierr != blot_direct_types::Error.none { return 0, iierr; }

        let pair_ty, pterr = g.types.tuple([state_ty, rep_ty]);
        if pterr != blot_direct_types::Error.none { return 0, pterr; }
        let step_inner_ty, sierr = g.types.function(cmd_ty, pair_ty);
        if sierr != blot_direct_types::Error.none { return 0, sierr; }
        let step_fn_ty, sferr = g.types.function(state_ty, step_inner_ty);
        if sferr != blot_direct_types::Error.none { return 0, sferr; }
        let step_inst, stierr = g.named(g.resolve(m, decl.step_target), step_fn_ty, m, 0);
        if stierr != blot_direct_types::Error.none { return 0, stierr; }

        let cfg_abi = abiFromWireTag(pinfo.config_schema.wire_tag);
        let cmd_abi = abiFromWireTag(pinfo.cmd_schema.wire_tag);
        let rep_abi = abiFromWireTag(pinfo.reply_schema.wire_tag);

        // 1. Export `blot:proc_init:<name>` (cfg_abi -> Unit).
        let init_fn = g.module.addFunction(g.module.signature([abiMachine(cfg_abi)], [VT_i32]));
        {
            var f = newFn(g, m.unit, 0);
            let _p0 = local(g, f, abiMachine(cfg_abi));
            f.parameter_words = 1;
            resetEntry(g);
            // Trap if status != 0; immediately set status = 2 before init!
            gget(g, root.status_global);
            trap(g, f);
            i32Const(g, 2);
            gset(g, root.status_global);
            let cfg_val, uerr = emitUnpackWireInput(g, f, m.unit, decl.config_type, cfg_ty, pinfo.config_schema, cfg_abi);
            if uerr != blot_direct_types::Error.none { return 0, uerr; }
            push(g, cfg_val);
            callf(g, g.s.instances[init_inst].function);
            let ires = g.s.instances[init_inst].result;
            if ires == blot_direct_types::never {
                op(g, OP_unreachable_);
            } else {
                let st_val, perr = pop(g, f, ires, 0);
                if perr != blot_direct_types::Error.none { return 0, perr; }
                let serr = emitStageRoot(g, f, root, st_val, false, 0, 0, 0, 0);
                if serr != blot_direct_types::Error.none { return 0, serr; }
                i32Const(g, 0);
            }
            op(g, OP_end);
            finish(g, init_fn, f);
        }
        var init_name: u8[>..<] = [];
        init_name.append("blot:proc_init:");
        init_name.append(m.name(decl.name));
        exportNamedEntry(g, init_name[..], abi, init_fn, cfg_abi, Abi.unit, isArray(cfg_abi));
        added += 1;

        // 2. Export `blot:proc_step:<name>` (cmd_abi -> rep_abi).
        let step_fn = g.module.addFunction(g.module.signature([abiMachine(cmd_abi)], [abiMachine(rep_abi)]));
        {
            var f = newFn(g, m.unit, 0);
            let _p0 = local(g, f, abiMachine(cmd_abi));
            f.parameter_words = 1;
            resetEntry(g);
            // Trap if status != 1; immediately set status = 2 BEFORE calling step!
            gget(g, root.status_global);
            i32Const(g, 1);
            op(g, OP_i32_ne);
            trap(g, f);
            i32Const(g, 2);
            gset(g, root.status_global);
            let cmd_val, uerr = emitUnpackWireInput(g, f, m.unit, decl.cmd_type, cmd_ty, pinfo.cmd_schema, cmd_abi);
            if uerr != blot_direct_types::Error.none { return 0, uerr; }
            let cur_state, lserr = loadPersistRootVal(g, f, root);
            if lserr != blot_direct_types::Error.none { return 0, lserr; }
            push(g, cur_state);
            push(g, cmd_val);
            callf(g, g.s.instances[step_inst].function);
            let sres = g.s.instances[step_inst].result;
            if sres == blot_direct_types::never {
                op(g, OP_unreachable_);
            } else {
                let pair_val, perr = pop(g, f, sres, 0);
                if perr != blot_direct_types::Error.none { return 0, perr; }
                let next_state, nerr = tupleItem(g, f, pair_val, 0, 0);
                if nerr != blot_direct_types::Error.none { return 0, nerr; }
                let reply_val, rverr = tupleItem(g, f, pair_val, 1, 0);
                if rverr != blot_direct_types::Error.none { return 0, rverr; }

                // Pack reply in Phase 1 before staging commits persistent state!
                var has_reply_pin = false;
                var reply_pin_slot: u32 = 0;
                var reply_base: u32 = 0;
                var reply_cap: u32 = 0;
                var reply_bytes: u32 = 0;
                var scalar_reply: u32 = 0;
                var has_scalar_reply = false;
                var subst: CoreSubstEntry[>..] = [];

                if pinfo.reply_schema.kind == blot_check_wire_schema::SCHEMA_KIND_UNIT {
                    // Unit reply -> returns 0.
                } else if !isArray(rep_abi) {
                    // 1-word scalar wire (bare U32/F32/Bool OR 1-word FlatNumeric record/wrapper).
                    let scratch = allocate(g, f, 4);
                    let cursor = local32(g, f);
                    lget(g, scratch); lset(g, cursor);
                    let pkerr = emitPackFlatNumeric(g, f, m.unit, decl.reply_type, rep_ty, reply_val, cursor, subst, 0, 0);
                    if pkerr != blot_direct_types::Error.none { return 0, pkerr; }
                    scalar_reply = local(g, f, abiMachine(rep_abi));
                    lget(g, scratch);
                    if rep_abi == Abi.f32_ { op(g, OP_f32_load); } else { op(g, OP_i32_load); }
                    uleb(g, 2); uleb(g, 0);
                    lset(g, scalar_reply);
                    has_scalar_reply = true;
                } else {
                    // Array / multi-word FlatNumeric reply -> pack via rt.open_transport_pin!
                    has_reply_pin = true;
                    reply_pin_slot = local32(g, f);
                    reply_base = local32(g, f);
                    reply_cap = local32(g, f);
                    reply_bytes = local32(g, f);
                    let rep_words = local32(g, f);
                    if pinfo.reply_schema.kind == blot_check_wire_schema::SCHEMA_KIND_VAR_U32 || pinfo.reply_schema.kind == blot_check_wire_schema::SCHEMA_KIND_VAR_F32 {
                        let rlen, rlerr = lengthOf(g, f, reply_val, 0);
                        if rlerr != blot_direct_types::Error.none { return 0, rlerr; }
                        lget(g, rlen);
                        ltee(g, rep_words);
                        i32Const(g, max_out_words);
                        op(g, OP_i32_gt_u);
                        trap(g, f);
                        lget(g, rep_words); i32Const(g, 2); op(g, OP_i32_shl); i32Const(g, 4); op(g, OP_i32_add); lset(g, reply_bytes);
                        lget(g, reply_bytes); callf(g, rt.open_transport_pin);
                        lset(g, reply_cap); lset(g, reply_base); op(g, OP_drop); lset(g, reply_pin_slot);
                        lget(g, reply_base); lget(g, rep_words); op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
                        lget(g, rep_words);
                        let ne = open(g, f, OP_if_);
                        let rsrc = baseOf(g, f, reply_val);
                        lget(g, reply_base); i32Const(g, 4); op(g, OP_i32_add);
                        lget(g, rsrc);
                        lget(g, rep_words); i32Const(g, 2); op(g, OP_i32_shl);
                        memoryCopyOp(g);
                        close(g, f);
                    } else {
                        i32Const(g, pinfo.reply_schema.stride); lset(g, rep_words);
                        i32Const(g, 4 + pinfo.reply_schema.stride * 4); lset(g, reply_bytes);
                        lget(g, reply_bytes); callf(g, rt.open_transport_pin);
                        lset(g, reply_cap); lset(g, reply_base); op(g, OP_drop); lset(g, reply_pin_slot);
                        lget(g, reply_base); lget(g, rep_words); op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
                        let cursor = local32(g, f);
                        lget(g, reply_base); i32Const(g, 4); op(g, OP_i32_add); lset(g, cursor);
                        let pkerr = emitPackFlatNumeric(g, f, m.unit, decl.reply_type, rep_ty, reply_val, cursor, subst, 0, 0);
                        if pkerr != blot_direct_types::Error.none { return 0, pkerr; }
                    }
                }

                let serr = emitStageRoot(g, f, root, next_state, has_reply_pin, reply_pin_slot, reply_base, reply_cap, reply_bytes, true);
                if serr != blot_direct_types::Error.none { return 0, serr; }
                if has_reply_pin { lget(g, reply_base); }
                else if has_scalar_reply { lget(g, scalar_reply); }
                else { i32Const(g, 0); }
            }
            op(g, OP_end);
            finish(g, step_fn, f);
        }
        var step_name: u8[>..<] = [];
        step_name.append("blot:proc_step:");
        step_name.append(m.name(decl.name));
        exportNamedEntry(g, step_name[..], abi, step_fn, cmd_abi, rep_abi, isArray(cmd_abi) || isArray(rep_abi));
        added += 1;
    }

    // Emit `blot:processes` v1 custom section (§3.2).
    var sec: u8[>..<] = [];
    blot_direct_writer::uleb(sec, 1);
    blot_direct_writer::uleb(sec, (rt.layout.transport_end - rt.layout.transport_base) as u64);
    blot_direct_writer::uleb(sec, m.processes.len as u64);
    for pi in 0..m.processes.len {
        let decl = m.processes[pi];
        let pinfo = g.s.processes[pi];
        let pname = m.name(decl.name);
        blot_direct_writer::name(sec, pname);
        var init_name: u8[>..<] = [];
        init_name.append("blot:proc_init:");
        init_name.append(pname);
        blot_direct_writer::name(sec, init_name[..]);
        var step_name: u8[>..<] = [];
        step_name.append("blot:proc_step:");
        step_name.append(pname);
        blot_direct_writer::name(sec, step_name[..]);
        encodeWireSchemaSection(sec, g, pinfo.config_schema);
        encodeWireSchemaSection(sec, g, pinfo.cmd_schema);
        encodeWireSchemaSection(sec, g, pinfo.reply_schema);
    }
    g.module.custom("blot:processes", sec[..]);
    return added, blot_direct_types::Error.none;
}
