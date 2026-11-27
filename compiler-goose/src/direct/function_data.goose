// Records, updates, products, constructors and projections of the direct
// backend's function emitter (compiler/src/direct/function.zig).
namespace blot_direct_function;
import .function;

// `@type.result "member" value`: dispatch on the expected result type.
recursive fn resultAssociated(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let value, error = expr(g, f, n.a);
    if error != blot_direct_types::Error.none { return value, error; }
    let result, error = typeOf(g, f, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let identity, has_identity = g.receiverIdentity(result);
    if !has_identity {
        g.failOpen(m, id);
        g.put("result member on a ");
        g.put(blot_direct_types::tagName(tagOf(g, result)));
        return neverVal(), g.failClose();
    }
    let target, has_target = g.dispatchTarget(m, identity, n.b, blot_check_types::Operator.none);
    if !has_target { return neverVal(), g.fail(m, id, "no result member for this type"); }
    let arguments = g.saveVals([value]);
    let callee, error = g.types.function(value.ty, result);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    return callTarget(g, f, target, arguments, callee, result, id);
}

// `root` with the field path of an update replaced by its new value.
recursive fn update(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let info = m.updateInfo(id);
    let root_da_idx = findDirectArray(f, localRef(m, info.root));
    if root_da_idx >= 0 {
        let selectors = m.updateSelectors(id);
        if selectors.len == 1 && selectors[0].kind == blot_check_core::UpdateKind.index {
            let da = f.direct_arrays[root_da_idx];
            let pos_val, perr = expr(g, f, selectors[0].index);
            if perr != blot_direct_types::Error.none { return pos_val, perr; }
            let idx_loc, ierr = scalarLocal(g, f, pos_val, id);
            if ierr != blot_direct_types::Error.none { return neverVal(), ierr; }
            if da.scalar_packed {
                if info.self_binding != 0 && uses(g, f, info.self_binding) != 0 {
                    let old, lerr = emitDirectArrayRead(g, f, da, idx_loc, id);
                    if lerr != blot_direct_types::Error.none { return neverVal(), lerr; }
                    bindPut(g, f, info.self_binding, old);
                }
                let replacement, rerr = stmt(g, f, info.value);
                if rerr != blot_direct_types::Error.none { return replacement, rerr; }
                if replacement.ty == blot_direct_types::never { return replacement, blot_direct_types::Error.none; }
                let werr = emitDirectArrayWrite(g, f, da, idx_loc, replacement, id);
                if werr != blot_direct_types::Error.none { return neverVal(), werr; }
            } else {
                let addr = directArrayAddress(g, f, da, idx_loc, id);
                if info.self_binding != 0 && uses(g, f, info.self_binding) != 0 {
                    let old, lerr = loadElement(g, f, addr, 0, da.elem_ty, id);
                    if lerr != blot_direct_types::Error.none { return neverVal(), lerr; }
                    bindPut(g, f, info.self_binding, old);
                }
                let replacement, rerr = stmt(g, f, info.value);
                if rerr != blot_direct_types::Error.none { return replacement, rerr; }
                if replacement.ty == blot_direct_types::never { return replacement, blot_direct_types::Error.none; }
                let werr = writeElement(g, f, addr, 0, replacement, id);
                if werr != blot_direct_types::Error.none { return neverVal(), werr; }
            }
            let bound, _ = bindGet(g, f, da.binding);
            return bound, blot_direct_types::Error.none;
        }
    }
    let root, error = expr(g, f, info.root);
    if error != blot_direct_types::Error.none { return root, error; }
    let prev_reuse_nodes = f.reuse_nodes;
    let prev_reuse_nodes_len = f.reuse_nodes_len;
    let prev_reuse_block = f.reuse_block;
    let prev_reuse_ty = f.reuse_ty;
    if !g.runtime_().has_fork {
        let root_binding = localRef(m, info.root);
        if root_binding != 0 && isUniqueBoxed(g, f, root_binding) && !bindingCaptured(g, f, root_binding) {
            let ucnt = uses(g, f, root_binding);
            var can_reuse = ucnt == 1;
            if !can_reuse && ucnt > 1 && ucnt <= 32 {
                let base = ensureLocalRefs(g, m);
                var cur = g.s.local_refs_head[(base as i64) + (root_binding as i64)];
                can_reuse = true;
                while cur != 0 {
                    let rnode = g.s.local_refs_node[(cur - 1) as i64];
                    cur = g.s.local_refs_next[(cur - 1) as i64];
                    if rnode != info.root {
                        let _, ok = blot_support_zigmap::get(g.s.map_pool, f.unique_boxed_safe_refs, rnode);
                        if !ok { can_reuse = false; break; }
                    }
                }
            }
            if can_reuse {
                let boxed, berr = isBoxed(g, f, root.ty, id);
                if berr == blot_direct_types::Error.none && boxed && root.len == 1 {
                    f.reuse_nodes = [id, 0, 0, 0];
                    f.reuse_nodes_len = 1;
                    f.reuse_block = w(g, root, 0);
                    f.reuse_ty = root.ty;
                }
            }
        }
    }
    let result, uerr = updateAt(g, f, id, root, 0);
    f.reuse_nodes = prev_reuse_nodes;
    f.reuse_nodes_len = prev_reuse_nodes_len;
    f.reuse_block = prev_reuse_block;
    f.reuse_ty = prev_reuse_ty;
    return result, uerr;
}
// `container[index].fields... := value` writes the selected place through the
// owner and leaves the handle unchanged.
recursive fn indexedUpdate(g: Generator&, f: Fn&, id: u32, container: Val, at: i64) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let info = m.updateInfo(id);
    let selectors = m.updateSelectors(id);
    if tagOf(g, container.ty) == blot_direct_types::Tag.view {
        return neverVal(), g.fail(m, id, "Cannot write through a borrowed slice");
    }
    let position_value, error = expr(g, f, selectors[at].index);
    if error != blot_direct_types::Error.none { return position_value, error; }
    let index, error = scalarLocal(g, f, position_value, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    var container_core_ty = selectors[at].source_type;
    if at == 0 { container_core_ty = m.typeOf(info.root); }
    let address, error = elementAddress(g, f, container, index, id, container_core_ty, true);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    checkMutableOwner(g, f, container);
    var ty, error = elementOf(g, f, container.ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    var offset: u32 = 0;
    for position_ in at + 1..selectors.len {
        let step = selectors[position_];
        if step.kind == blot_check_core::UpdateKind.index {
            // The place holds an owner: the write goes through it, so the
            // handle stored here is unchanged.
            var inner = neverVal();
            if offset == 0 {
                let loaded, error = loadElement(g, f, address, 0, ty, id);
                if error != blot_direct_types::Error.none { return neverVal(), error; }
                inner = loaded;
            } else {
                let loaded, error = loadAt(g, f, address, offset, ty, id);
                if error != blot_direct_types::Error.none { return neverVal(), error; }
                inner = loaded;
            }
            match tagOf(g, ty) {
                array, view => {},
                _ => {
                    g.failOpen(m, id);
                    g.put("indexed update of a ");
                    g.put(blot_direct_types::tagName(tagOf(g, ty)));
                    return neverVal(), g.failClose();
                },
            }
            let ignored, error = indexedUpdate(g, f, id, inner, position_);
            if error != blot_direct_types::Error.none { return ignored, error; }
            return container, blot_direct_types::Error.none;
        }
        let name, has_name = updateFieldName(g, f, m, step);
        if !has_name { return neverVal(), g.fail(m, id, "updated field without a spelling"); }
        var record = ty;
        if tagOf(g, ty) == blot_direct_types::Tag.nominal {
            let cases, error = g.types.variants(ty);
            if error != blot_direct_types::Error.none { return neverVal(), g.typeFailure(m, id); }
            if cases.len != 1 { return neverVal(), g.fail(m, id, "update of a multi-constructor element"); }
            record = g.types.variant_payloads[cases.payloads];
        }
        let position = g.types.findField(record, name);
        if position < 0 { return neverVal(), g.fail(m, id, "updated field missing"); }
        let foff, foff_err = fieldOffset(g, f, record, position, id);
        if foff_err != blot_direct_types::Error.none { return neverVal(), foff_err; }
        offset += foff;
        ty = g.types.recordField(record, position).ty;
        if step.kind == blot_check_core::UpdateKind.comptime_field &&
            !matchesComptimeFieldType(g, f, m, step.result_type, ty) {
            return neverVal(), g.fail(m, id, "comptime update has the wrong field type");
        }
    }
    let whole_element = selectors.len == at + 1;
    if info.self_binding != 0 && uses(g, f, info.self_binding) != 0 {
        var old = neverVal();
        if whole_element {
            let loaded, error = loadElement(g, f, address, 0, ty, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            old = loaded;
        } else {
            let boxed_sub, berr = copiedBox(g, f, ty, id);
            if berr != blot_direct_types::Error.none { return neverVal(), berr; }
            if boxed_sub {
                var sub_addr = address;
                if offset != 0 {
                    sub_addr = local32(g, f);
                    lget(g, address);
                    i32Const(g, offset);
                    op(g, OP_i32_add);
                    lset(g, sub_addr);
                }
                let loaded, error = loadElement(g, f, sub_addr, 0, ty, id);
                if error != blot_direct_types::Error.none { return neverVal(), error; }
                old = loaded;
            } else {
                let loaded, error = loadAt(g, f, address, offset, ty, id);
                if error != blot_direct_types::Error.none { return neverVal(), error; }
                old = loaded;
            }
        }
        bindPut(g, f, info.self_binding, old);
    }
    let replacement, error = stmt(g, f, info.value);
    if error != blot_direct_types::Error.none { return replacement, error; }
    if replacement.ty == blot_direct_types::never { return replacement, blot_direct_types::Error.none; }
    if replacement.ty != ty && reflectiveUpdate(selectors) {
        return neverVal(), g.fail(m, id, "comptime update changes the selected field's type");
    }
    let noted = noteStoreToSlot(g, f, w(g, container, 0), replacement);
    if noted != blot_direct_types::Error.none { return neverVal(), noted; }
    // Only when `info.value` cannot resize storage (compile-time fixed-length
    // `#[N; T]` or proved `noStorageResize` RHS) can we reuse the element
    // address computed before `info.value`.
    var target = address;
    var rhs_budget: i64 = 128;
    let rhs_safe = tagOf(g, container.ty) == blot_direct_types::Tag.array &&
        (coreSizedLength(m, container_core_ty) != 0 || noStorageResize(g, m, info.value, rhs_budget));
    if !rhs_safe {
        let recomputed, error = elementAddress(g, f, container, index, id, container_core_ty);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        target = recomputed;
    }
    if g.runtime_().has_fork {
        var bytes: u32 = 0;
        if whole_element && byteElement(tagOf(g, replacement.ty)) {
            bytes = 1;
        } else {
            let fb, berr = flatBytes(g, f, replacement.ty, id);
            if berr != blot_direct_types::Error.none { return neverVal(), berr; }
            bytes = fb;
        }
        recordBeforeWrite(g, f, w(g, container, 0), target, offset, bytes);
    }
    var written = blot_direct_types::Error.none;
    if whole_element {
        var skipped_tag = false;
        if !g.runtime_().has_fork && tagOf(g, container.ty) == blot_direct_types::Tag.array &&
            tagOf(g, replacement.ty) == blot_direct_types::Tag.nominal && replacement.len > 1 {
            let boxed_r, berr = isBoxed(g, f, replacement.ty, id);
            let cases_r, cerr = g.types.variants(replacement.ty);
            if berr == blot_direct_types::Error.none && !boxed_r && cerr == blot_direct_types::Error.none && cases_r.len > 1 {
                let elem_step, serr = stride(g, f, replacement.ty, id);
                if serr == blot_direct_types::Error.none {
                    let ce = findCheckedElem(f, w(g, container, 0), w(g, container, 1), index, elem_step);
                    if ce >= 0 && f.checked_elems[ce].known_tag != 0xffffffff {
                        let new_tag, has_nt = findConstTag(f, w(g, replacement, 0));
                        if has_nt && new_tag == f.checked_elems[ce].known_tag {
                            let payload_val = Val { replacement.ty, replacement.start + 1, replacement.len - 1 };
                            storeAt(g, f, target, 4, payload_val);
                            skipped_tag = true;
                        }
                    }
                }
            }
        }
        if !skipped_tag {
            written = writeElement(g, f, target, 0, replacement, id);
        }
    } else {
        written = writeFlatPack(g, f, target, offset, replacement, id);
    }
    if written != blot_direct_types::Error.none { return neverVal(), written; }
    // Any element mutation invalidates cached scalar element values.
    f.checked_elems_len = 0;
    return container, blot_direct_types::Error.none;
}
fn byteWidth(g: Generator&, f: const Fn&, ty: Ty, id: u32) -> u32, Error { return flatBytes(g, f, ty, id); }
// A boxed record (or one-constructor wrapper of one) with field `name`
// replaced: a fresh copy of the block, then the field written.
recursive fn updateBoxed(g: Generator&, f: Fn&, id: u32, value: Val, name: u32, at: i64) -> Val, Error {
    let m .= g.units[f.unit - 1];
    var record_ty = value.ty;
    if tagOf(g, value.ty) == blot_direct_types::Tag.nominal {
        let cases, error = g.types.variants(value.ty);
        if error != blot_direct_types::Error.none { return neverVal(), g.typeFailure(m, id); }
        if cases.len != 1 { return updateBoxedShared(g, f, id, value, cases, name, at); }
        record_ty = g.types.variant_payloads[cases.payloads];
    }
    if tagOf(g, record_ty) != blot_direct_types::Tag.record {
        g.failOpen(m, id);
        g.put("update of a boxed ");
        g.put(blot_direct_types::tagName(tagOf(g, record_ty)));
        return neverVal(), g.failClose();
    }
    let position = g.types.findField(record_ty, name);
    if position < 0 { return neverVal(), g.fail(m, id, "updated field missing"); }
    // A one-constructor wrapper's payload starts at its block's start.
    let offset, error = fieldOffset(g, f, record_ty, position, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let field_ty = g.types.recordField(record_ty, position).ty;
    let old, error = readFlat(g, f, w(g, value, 0), offset, field_ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let replacement, error = updateAt(g, f, id, old, at + 1);
    if error != blot_direct_types::Error.none { return replacement, error; }
    if replacement.ty == blot_direct_types::never { return replacement, blot_direct_types::Error.none; }
    if replacement.ty != field_ty { return neverVal(), g.fail(m, id, "an update that changes a boxed field's type"); }
    // A write through an owner inside the field leaves the field's words
    // as they were: the record is the same block.
    if replacement.len == old.len {
        var same = true;
        for index in 0..(old.len as i64) { if g.s.words[replacement.start + index] != g.s.words[old.start + index] { same = false; } }
        if same {
            if f.reuse_block == w(g, value, 0) && f.reuse_ty == value.ty && consumeReuseNode(f, id) {
                f.reuse_block = 0;
            } else {
                f.boxed_noop_alias = true;
            }
            return value, blot_direct_types::Error.none;
        }
    }
    if f.reuse_block == w(g, value, 0) && f.reuse_ty == value.ty && consumeReuseNode(f, id) {
        f.reuse_block = 0;
        let written = writeFlat(g, f, w(g, value, 0), offset, replacement, id);
        if written != blot_direct_types::Error.none { return neverVal(), written; }
        return value, blot_direct_types::Error.none;
    }
    let memory_block, error = newBlock(g, f, value.ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let bytes, error = blockBytes(g, f, value.ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    memoryCopy(g, memory_block, 0, w(g, value, 0), bytes);
    let written = writeFlat(g, f, memory_block, offset, replacement, id);
    if written != blot_direct_types::Error.none { return neverVal(), written; }
    return valOf1(g, value.ty, memory_block), blot_direct_types::Error.none;
}
// A boxed sum with field `name`, which its constructors share, replaced. The
// block starts with the tag, and the field's offset follows from it.
recursive fn updateBoxedShared(g: Generator&, f: Fn&, id: u32, value: Val, cases: blot_direct_types::Variants, name: u32, at: i64) -> Val, Error {
    let m .= g.units[f.unit - 1];
    var has_field = false;
    var field_ty: Ty = 0;
    let offset = local32(g, f);
    i32Const(g, 0);
    lset(g, offset);
    let tag = local32(g, f);
    lget(g, w(g, value, 0));
    op(g, OP_i32_load);
    uleb(g, 2);
    uleb(g, 0);
    lset(g, tag);
    for case_at in 0..(cases.len as i64) {
        let case_tag = g.types.variant_tags[cases.tags + case_at];
        let payload = g.types.variant_payloads[cases.payloads + case_at];
        if tagOf(g, payload) != blot_direct_types::Tag.record { continue; }
        let position = g.types.findField(payload, name);
        if position < 0 { continue; }
        let ty = g.types.recordField(payload, position).ty;
        if has_field && field_ty != ty { return neverVal(), g.fail(m, id, "a shared field of different types"); }
        has_field = true;
        field_ty = ty;
        lget(g, tag);
        i32Const(g, case_tag);
        op(g, OP_i32_eq);
        let opened = open(g, f, OP_if_);
        let field_offset, error = fieldOffset(g, f, payload, position, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        i32Const(g, 4 + field_offset);
        lset(g, offset);
        close(g, f);
    }
    if !has_field { return neverVal(), g.fail(m, id, "updated field missing"); }
    let ty = field_ty;
    // A constructor without the field leaves the offset at zero.
    lget(g, offset);
    op(g, OP_i32_eqz);
    trap(g, f);
    let old_address = local32(g, f);
    lget(g, w(g, value, 0));
    lget(g, offset);
    op(g, OP_i32_add);
    lset(g, old_address);
    let old, error = readFlat(g, f, old_address, 0, ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let replacement, error = updateAt(g, f, id, old, at + 1);
    if error != blot_direct_types::Error.none { return replacement, error; }
    if replacement.ty == blot_direct_types::never { return replacement, blot_direct_types::Error.none; }
    if replacement.ty != ty { return neverVal(), g.fail(m, id, "an update that changes a boxed field's type"); }
    if f.reuse_block == w(g, value, 0) && f.reuse_ty == value.ty && consumeReuseNode(f, id) {
        f.reuse_block = 0;
        let written = writeFlat(g, f, old_address, 0, replacement, id);
        if written != blot_direct_types::Error.none { return neverVal(), written; }
        return value, blot_direct_types::Error.none;
    }
    let memory_block, error = newBlock(g, f, value.ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let bytes, error = blockBytes(g, f, value.ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    memoryCopy(g, memory_block, 0, w(g, value, 0), bytes);
    let new_address = local32(g, f);
    lget(g, memory_block);
    lget(g, offset);
    op(g, OP_i32_add);
    lset(g, new_address);
    let written = writeFlat(g, f, new_address, 0, replacement, id);
    if written != blot_direct_types::Error.none { return neverVal(), written; }
    return valOf1(g, value.ty, memory_block), blot_direct_types::Error.none;
}
fn reflectiveUpdate(selectors: const blot_check_core::UpdateStep[:]) -> bool {
    for step in selectors { if step.kind == blot_check_core::UpdateKind.comptime_field { return true; } }
    return false;
}

fn updateFieldName(g: Generator&, f: const Fn&, m: const Module&, step: blot_check_core::UpdateStep) -> u32, bool {
    if step.kind == blot_check_core::UpdateKind.comptime_field {
        let index = findComptimeFrame(f, step.projection);
        if index < 0 { return 0, false; }
        return f.comptime_frames[index].name_id, true;
    }
    return g.types.fieldNameOf(m, m.projection(step.projection).field, true);
}

recursive fn updateAt(g: Generator&, f: Fn&, id: u32, value: Val, at: i64) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let info = m.updateInfo(id);
    let selectors = m.updateSelectors(id);
    let path = m.updatePath(id);
    let steps = max(selectors.len, path.len);
    if at == steps {
        bindPut(g, f, info.self_binding, value);
        if at == 0 && info.self_binding != 0 && !g.runtime_().has_fork && !bindingCaptured(g, f, info.self_binding) {
            if f.reuse_block != 0 && value.len == 1 && f.reuse_block == w(g, value, 0) && f.reuse_ty == value.ty && consumeReuseNode(f, id) {
                f.reuse_block = 0;
                blot_support_zigmap::put(g.s.map_pool, f.unique_boxed, info.self_binding, f.loop_depth + 1);
            }
            let rb = localRef(m, info.root);
            if rb != 0 && isUniqueOwned(g, f, rb) && ownedTotalUses(g, f, rb) == 1 && !bindingCaptured(g, f, rb) {
                blot_support_zigmap::put(g.s.map_pool, f.unique_owned, info.self_binding, f.loop_depth + 1);
            }
        }
        let replacement, error = stmt(g, f, info.value);
        if error != blot_direct_types::Error.none || replacement.ty == blot_direct_types::never { return replacement, error; }
        if replacement.ty != value.ty && reflectiveUpdate(selectors) {
            return neverVal(), g.fail(m, id, "comptime update changes the selected field's type");
        }
        return replacement, blot_direct_types::Error.none;
    }
    if selectors.len != 0 && selectors[at].kind == blot_check_core::UpdateKind.index { return indexedUpdate(g, f, id, value, at); }
    var step = default<blot_check_core::UpdateStep>();
    if selectors.len != 0 { step = selectors[at]; } else { step.projection = path[at]; }
    let name, has_name = updateFieldName(g, f, m, step);
    if step.kind == blot_check_core::UpdateKind.comptime_field && has_name {
        if isOpaqueOutsideUnit(g, m, value.ty) {
            return neverVal(), g.failCode(m, id, blot_check_diagnostic_code::Code.type_mismatch, "opaque type representation cannot be reflected outside its defining module");
        }
        let frame = f.comptime_frames[findComptimeFrame(f, step.projection)];
        if !matchesComptimeFieldType(g, f, m, step.result_type, frame.field_ty) {
            return neverVal(), g.fail(m, id, "comptime update has the wrong field type");
        }
    }
    if !has_name { return neverVal(), g.fail(m, id, "updated field without a spelling"); }
    let boxed, error = isBoxed(g, f, value.ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    if boxed { return updateBoxed(g, f, id, value, name, at); }
    var record = value;
    var wrapped = false;
    if g.types.node(value.ty).tag == blot_direct_types::Tag.nominal {
        let cases, error = g.types.variants(value.ty);
        if error != blot_direct_types::Error.none { return neverVal(), g.typeFailure(m, id); }
        if cases.len != 1 { return sharedFieldUpdate(g, f, id, value, cases, name, at); }
        let unwrapped, error = unwrapVariant(g, f, value, g.types.variant_tags[cases.tags], id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        record = unwrapped;
        wrapped = true;
    }
    let updated, error = updateField(g, f, id, record, name, at);
    if error != blot_direct_types::Error.none { return updated, error; }
    if updated.ty == blot_direct_types::never { return updated, blot_direct_types::Error.none; }
    if wrapped { return Val { value.ty, updated.start, updated.len }, blot_direct_types::Error.none; }
    return updated, blot_direct_types::Error.none;
}
// A field several constructors declare, updated in whichever the value holds;
// other constructors trap.
recursive fn sharedFieldUpdate(g: Generator&, f: Fn&, id: u32, value: Val, cases: blot_direct_types::Variants, name: u32, at: i64) -> Val, Error {
    let result, error = fresh(g, f, value.ty, id);
    if error != blot_direct_types::Error.none { return result, error; }
    let exit = open(g, f, OP_block);
    for case_at in 0..(cases.len as i64) {
        let tag = g.types.variant_tags[cases.tags + case_at];
        let payload_ty = g.types.variant_payloads[cases.payloads + case_at];
        if tagOf(g, payload_ty) != blot_direct_types::Tag.record || g.types.findField(payload_ty, name) < 0 { continue; }
        let next = open(g, f, OP_block);
        lget(g, w(g, value, 0));
        i32Const(g, tag);
        op(g, OP_i32_ne);
        br(g, f, OP_br_if, next);
        let unwrapped, error = unwrapVariant(g, f, value, tag, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        let updated, error = updateField(g, f, id, unwrapped, name, at);
        if error != blot_direct_types::Error.none { return updated, error; }
        if updated.ty != blot_direct_types::never {
            let wrapped, error = wrapVariant(g, f, value.ty, tag, updated, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let copied = copy(g, f, wrapped, result, id);
            if copied != blot_direct_types::Error.none { return neverVal(), copied; }
            br(g, f, OP_br, exit);
        }
        close(g, f);
    }
    op(g, OP_unreachable_);
    close(g, f);
    return result, blot_direct_types::Error.none;
}
// Record `record` with field `name` replaced by the rest of the update.
recursive fn updateField(g: Generator&, f: Fn&, id: u32, record: Val, name: u32, at: i64) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let position = g.types.findField(record.ty, name);
    if position < 0 { return neverVal(), g.fail(m, id, "updated field missing"); }
    let start, len, error = fieldSlice(g, f, record.ty, position, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let old = Val { g.types.recordField(record.ty, position).ty, record.start + start, len };
    let replacement, error = updateAt(g, f, id, old, at + 1);
    if error != blot_direct_types::Error.none { return replacement, error; }
    if replacement.ty == blot_direct_types::never { return replacement, blot_direct_types::Error.none; }
    let words_start = g.s.words.len as u32;
    for index in 0..(start as i64) { let word = g.s.words[record.start + index]; g.s.words.push(word); }
    for index in 0..(replacement.len as i64) { let word = g.s.words[replacement.start + index]; g.s.words.push(word); }
    for index in ((start + len) as i64)..(record.len as i64) { let word = g.s.words[record.start + index]; g.s.words.push(word); }
    let count = (g.s.words.len as u32) - words_start;
    var ty = record.ty;
    if replacement.ty != old.ty {
        let shape = g.types.node(record.ty);
        var fields: blot_direct_types::Field[>..<] = [];
        for index in 0..(shape.b as i64) { fields.push(g.types.recordField(record.ty, index)); }
        fields[position].ty = replacement.ty;
        let made, error = g.types.record(fields[..]);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        ty = made;
    }
    return Val { ty, words_start, count }, blot_direct_types::Error.none;
}

// Word offset and width of record field `index` of `ty`.
fn fieldSlice(g: Generator&, f: const Fn&, ty: Ty, index: i64, id: u32) -> u32, u32, Error {
    let start, width, error = g.types.recordFieldWordSlice(ty, index);
    if error != blot_direct_types::Error.none { return 0, 0, g.typeFailure(g.units[f.unit - 1], id); }
    return start, width, blot_direct_types::Error.none;
}
// A slot of `ordered` in product() that no field has filled.
let absent_ty: Ty = 0xffffffff;

recursive fn product(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let children = m.children(id);
    let values = g.reserveVals(children.len);
    for child, at in children {
        let value, error = fieldValue(g, f, child);
        if error != blot_direct_types::Error.none { return value, error; }
        g.s.vals[values.start + at] = value;
    }
    // The literal's type, or the one its fields' values give it.
    var ty, error = g.types.lower(m, m.typeOf(id), f.env);
    if error != blot_direct_types::Error.none {
        let derived, error = productType(g, f, id, values);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        ty = derived;
    }
    let shape = g.types.node(ty);
    if shape.tag == blot_direct_types::Tag.record {
        let ordered = g.reserveVals(shape.b);
        for at in 0..(shape.b as i64) { g.s.vals[ordered.start + at] = Val { ty: absent_ty }; }
        let source = m.types.node(m.typeOf(id));
        if source.tag != blot_check_types::Tag.record { return neverVal(), g.fail(m, id, "record literal without a record type"); }
        for index in 0..(values.len as i64) {
            var destination = index;
            if n.tag == blot_check_core::Tag.record { destination = m.recordDestinations(id)[index]; }
            let field = m.types.recordField(source, destination);
            let fname, has_fname = g.types.fieldNameOf(m, field.name, true);
            if !has_fname { return neverVal(), g.fail(m, id, "record field without a spelling"); }
            let position = g.types.findField(ty, fname);
            if position < 0 { return neverVal(), g.fail(m, id, "record field missing from its type"); }
            g.s.vals[ordered.start + position] = g.s.vals[values.start + index];
        }
        return packProduct(g, f, id, ty, ordered);
    }
    return packProduct(g, f, id, ty, values);
}

// `values` follows the canonical field order for records.
fn packProduct(g: Generator&, f: Fn&, id: u32, ty: Ty, values: Vals) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let shape = g.types.node(ty);
    let boxed, error = isBoxed(g, f, ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    var memory_block: u32 = 0;
    if boxed {
        let made, error = newBlock(g, f, ty, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        memory_block = made;
    }
    let s .= g.s;
    let mark = s.scratch.len;
    match shape.tag {
        unit => { return unitVal(), blot_direct_types::Error.none; },
        tuple => {
            for index in 0..(values.len as i64) {
                let value = g.s.vals[values.start + index];
                if boxed {
                    let offset, error = itemOffset(g, f, ty, index, id);
                    if error != blot_direct_types::Error.none { s.scratch.resize(mark); return neverVal(), error; }
                    let written = writeFlat(g, f, memory_block, offset, value, id);
                    if written != blot_direct_types::Error.none { s.scratch.resize(mark); return neverVal(), written; }
                } else {
                    for at in 0..(value.len as i64) { s.scratch.push(g.s.words[value.start + at]); }
                }
            }
        },
        record => {
            for index in 0..(values.len as i64) {
                let value = g.s.vals[values.start + index];
                if value.ty == absent_ty { s.scratch.resize(mark); return neverVal(), g.fail(m, id, "record literal misses a field"); }
                if boxed {
                    let offset, error = fieldOffset(g, f, ty, index, id);
                    if error != blot_direct_types::Error.none { s.scratch.resize(mark); return neverVal(), error; }
                    let written = writeFlat(g, f, memory_block, offset, value, id);
                    if written != blot_direct_types::Error.none { s.scratch.resize(mark); return neverVal(), written; }
                } else {
                    for at in 0..(value.len as i64) { s.scratch.push(g.s.words[value.start + at]); }
                }
            }
        },
        _ => {
            g.failOpen(m, id);
            g.put("product of type ");
            g.put(blot_direct_types::tagName(shape.tag));
            return neverVal(), g.failClose();
        },
    }
    if boxed { s.scratch.resize(mark); return valOf1(g, ty, memory_block), blot_direct_types::Error.none; }
    let start = g.s.words.len as u32;
    let count = (s.scratch.len - mark) as u32;
    for at in mark..s.scratch.len { let word = s.scratch[at]; g.s.words.push(word); }
    s.scratch.resize(mark);
    return Val { ty, start, count }, blot_direct_types::Error.none;
}

// A literal's field value: a reference here may be a trap closure.
recursive fn fieldValue(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let previous = f.field_value;
    f.field_value = g.units[f.unit - 1].node(id).tag == blot_check_core::Tag.reference;
    let value, error = expr(g, f, id);
    f.field_value = previous;
    return value, error;
}
fn productType(g: Generator&, f: Fn&, id: u32, values: Vals) -> Ty, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let source = m.types.node(m.typeOf(id));
    if source.tag == blot_check_types::Tag.product {
        var items: Ty[>..<] = [];
        for at in 0..(values.len as i64) { items.push(g.s.vals[values.start + at].ty); }
        return g.types.tuple(items[..]);
    }
    if source.tag != blot_check_types::Tag.record || n.tag != blot_check_core::Tag.record { return 0, g.typeFailure(m, id); }
    var fields: blot_direct_types::Field[>..<] = [];
    let destinations = m.recordDestinations(id);
    for at in 0..(values.len as i64) {
        let fname, has_fname = g.types.fieldNameOf(m, m.types.recordField(source, destinations[at]).name, true);
        if !has_fname { return 0, g.typeFailure(m, id); }
        fields.push(blot_direct_types::Field { fname, g.s.vals[values.start + at].ty });
    }
    let ty, error = g.types.record(fields[..]);
    if error != blot_direct_types::Error.none { return 0, error; }
    refine(g, f, m.typeOf(id), ty);
    return ty, blot_direct_types::Error.none;
}
recursive fn construct(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let constructor = m.constructor(n.a);
    // Positional arguments of a record-bodied constructor follow its declared
    // field order; the record itself is in canonical order.
    var declared: TId = 0;
    if constructor.payload != 0 && m.types.node(constructor.payload).tag == blot_check_types::Tag.record { declared = constructor.payload; }
    var payload = unitVal();
    if n.b != 0 {
        if declared != 0 && m.types.node(declared).b > 1 && m.node(n.b).tag == blot_check_core::Tag.product {
            let value, error = positionalRecord(g, f, n.b, declared);
            if error != blot_direct_types::Error.none { return value, error; }
            payload = value;
        } else {
            let value, error = expr(g, f, n.b);
            if error != blot_direct_types::Error.none { return value, error; }
            payload = value;
            if declared != 0 && m.types.node(declared).b == 1 {
                let field_sym = m.types.recordField(m.types.node(declared), 0).name;
                let fname, has_fname = g.types.fieldNameOf(m, field_sym, true);
                if has_fname {
                    let already_wrapped = tagOf(g, payload.ty) == blot_direct_types::Tag.record && g.types.node(payload.ty).b == 1 && g.types.findField(payload.ty, fname) == 0;
                    if !already_wrapped {
                        var one_field: blot_direct_types::Field[1] = [blot_direct_types::Field { fname, payload.ty }];
                        let rec_ty, rerr = g.types.record(one_field[..]);
                        if rerr != blot_direct_types::Error.none { return neverVal(), rerr; }
                        payload = Val { rec_ty, payload.start, payload.len };
                    }
                }
            }
        }
    }
    // The node's type, or the one the payload's value gives the nominal.
    var ty, error = g.types.lower(m, m.typeOf(id), f.env);
    if error != blot_direct_types::Error.none {
        let derived, error = constructedType(g, f, constructor, payload, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        ty = derived;
    }
    return wrapVariant(g, f, ty, constructor.tag, payload, id);
}
// A record from positional product node `id`, whose children follow the
// declared record type `declared` (Core, this unit) field by field.
recursive fn positionalRecord(g: Generator&, f: Fn&, id: u32, declared: TId) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let shape = m.types.node(declared);
    let children = m.children(id);
    if children.len != shape.b { return expr(g, f, id); }
    let parts = g.reserveVals(children.len);
    // The field name of each part, in declared order.
    let names = blot_direct_emit::Words { g.s.words.len as u32, children.len as u32 };
    for child in children { g.s.words.push(0); }
    for child, index in children {
        let part, error = expr(g, f, child);
        if error != blot_direct_types::Error.none { return part, error; }
        g.s.vals[parts.start + index] = part;
        let fname, has_fname = g.types.fieldNameOf(m, m.types.recordField(shape, index).name, true);
        if !has_fname { return neverVal(), g.fail(m, id, "record field without a spelling"); }
        g.s.words[names.start + index] = fname;
    }
    var record: Ty = 0;
    {
        // record() sorts the slice it is given; the parts keep declared order.
        var fields: blot_direct_types::Field[>..<] = [];
        for index in 0..children.len { fields.push(blot_direct_types::Field { g.s.words[names.start + index], g.s.vals[parts.start + index].ty }); }
        let made, error = g.types.record(fields[..]);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        record = made;
    }
    let start = g.s.words.len as u32;
    for position in 0..children.len {
        let name = g.types.recordField(record, position).name;
        for index in 0..children.len {
            if g.s.words[names.start + index] != name { continue; }
            let part = g.s.vals[parts.start + index];
            for at in 0..(part.len as i64) { let word = g.s.words[part.start + at]; g.s.words.push(word); }
        }
    }
    return Val { record, start, (g.s.words.len as u32) - start }, blot_direct_types::Error.none;
}
// Record `record` from `value`, a tuple whose items follow the fields of
// `declared` (a Core record type of `tm`) in declared order.
fn declaredRecord(g: Generator&, f: const Fn&, tm: const Module&, value: Val, record: Ty, declared: TId) -> Val, Error {
    let shape = tm.types.node(declared);
    let tuple = g.types.node(value.ty);
    if tuple.b != shape.b || g.types.node(record).b != shape.b {
        g.failOpen(tm, 0);
        g.put("constructor tuple of ");
        g.putNumber(tuple.b);
        g.put(" items for ");
        g.putNumber(shape.b);
        g.put(" fields");
        return neverVal(), g.failClose();
    }
    let offsets = blot_direct_emit::Words { g.s.words.len as u32, tuple.b + 1 };
    g.s.words.push(0);
    for index in 0..(tuple.b as i64) {
        let width, error = layoutLen(g, f, g.types.words[tuple.a + index], 0);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        let next = g.s.words[offsets.start + index] + width;
        g.s.words.push(next);
    }
    let decl_names = blot_direct_emit::Words { g.s.words.len as u32, shape.b };
    for candidate in 0..(shape.b as i64) {
        let fname, has_fname = g.types.fieldNameOf(tm, tm.types.recordField(shape, candidate).name, true);
        if !has_fname { return neverVal(), g.fail(tm, 0, "record field without a spelling"); }
        g.s.words.push(fname);
    }
    let start = g.s.words.len as u32;
    for position in 0..(shape.b as i64) {
        let name = g.types.recordField(record, position).name;
        var index: i64 = -1;
        for candidate in 0..(shape.b as i64) {
            if g.s.words[decl_names.start + candidate] == name { index = candidate; break; }
        }
        if index < 0 { return neverVal(), g.fail(tm, 0, "constructor field missing from its declaration"); }
        let from = g.s.words[offsets.start + index];
        let to = g.s.words[offsets.start + index + 1];
        for at in (from as i64)..(to as i64) { let word = g.s.words[value.start + at]; g.s.words.push(word); }
    }
    return Val { record, start, (g.s.words.len as u32) - start }, blot_direct_types::Error.none;
}
fn constructedType(g: Generator&, f: Fn&, constructor: blot_check_core::Constructor, payload: Val, id: u32) -> Ty, Error {
    let m .= g.units[f.unit - 1];
    let shape = m.types.node(m.typeOf(id));
    if shape.tag != blot_check_types::Tag.nominal { return 0, g.typeFailure(m, id); }
    let identity = blot_check_types::NominalIdentity { shape.a, shape.b };
    if !g.hasUnit(identity.unit) { return 0, g.typeFailure(m, id); }
    let owner .= g.units[identity.unit - 1];
    let ordinal, error = g.types.nominalOrdinal(owner, identity);
    if error != blot_direct_types::Error.none { return 0, g.typeFailure(m, id); }
    // The declaring unit's constructor of the same tag gives the payload in
    // its parameters.
    var found = false;
    var declared = constructor;
    for candidate in owner.nominalConstructors(ordinal) {
        if owner.constructor(candidate).tag == constructor.tag { declared = owner.constructor(candidate); found = true; break; }
    }
    if !found { return 0, g.typeFailure(m, id); }
    // The payload binds the constructor's scheme variables; its result type
    // in them is the nominal type.
    var env = Env {};
    if declared.payload != 0 { g.types.match_(owner, declared.payload, payload.ty, env); }
    let signature = owner.types.node(declared.scheme.root);
    var result = declared.scheme.root;
    if signature.tag == blot_check_types::Tag.function { result = signature.b; }
    let ty, error = g.types.lowerHoles(owner, result, env);
    if error != blot_direct_types::Error.none { return 0, error; }
    refine(g, f, m.typeOf(id), ty);
    // Parts the payload leaves open and no use can reach take Unit.
    if holesUnused(g, f, m.typeOf(id), 0) {
        defaultUnused(g, f, m.typeOf(id), 0);
        let defaulted, error = g.types.lower(m, m.typeOf(id), f.env);
        if error == blot_direct_types::Error.none { return defaulted, blot_direct_types::Error.none; }
    }
    return ty, blot_direct_types::Error.none;
}
fn variantPosition(g: Generator&, f: const Fn&, cases: blot_direct_types::Variants, tag: u32, id: u32) -> i64, Error {
    for position in 0..(cases.len as i64) { if g.types.variant_tags[cases.tags + position] == tag { return position, blot_direct_types::Error.none; } }
    return 0, g.fail(g.units[f.unit - 1], id, "constructor tag missing from its type");
}
fn wrapVariant(g: Generator&, f: Fn&, ty: Ty, tag: u32, payload: Val, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let cases, error = g.types.variants(ty);
    if error != blot_direct_types::Error.none { return neverVal(), g.typeFailure(m, id); }
    if payload.ty == blot_direct_types::never { return neverVal(), blot_direct_types::Error.none; }
    let boxed, error = isBoxed(g, f, ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    if boxed {
        var memory_block: u32 = 0;
        if f.reuse_block != 0 && f.reuse_ty == ty && consumeReuseNode(f, id) {
            memory_block = f.reuse_block;
        } else {
            let made, error = newBlock(g, f, ty, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            memory_block = made;
        }
        var offset: u32 = 0;
        if cases.len > 1 {
            lget(g, memory_block);
            i32Const(g, tag);
            op(g, OP_i32_store);
            uleb(g, 2);
            uleb(g, 0);
            offset = 4;
        }
        let written = writeFlat(g, f, memory_block, offset, payload, id);
        if written != blot_direct_types::Error.none { return neverVal(), written; }
        return valOf1(g, ty, memory_block), blot_direct_types::Error.none;
    }
    let position, error = variantPosition(g, f, cases, tag, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let declared = g.types.variant_payloads[cases.payloads + position];
    let declared_words, error = layoutLen(g, f, declared, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    if declared_words != payload.len {
        g.failOpen(m, id);
        g.put("constructor payload of type ");
        g.put(blot_direct_types::tagName(tagOf(g, payload.ty)));
        g.put(" (");
        g.putNumber(payload.len);
        g.put(" words) does not match its declared ");
        g.put(blot_direct_types::tagName(tagOf(g, declared)));
        g.put(" (");
        g.putNumber(declared_words);
        g.put(" words)");
        return neverVal(), g.failClose();
    }
    if cases.len == 1 { return Val { ty, payload.start, payload.len }, blot_direct_types::Error.none; }
    let result, error = fresh(g, f, ty, id);
    if error != blot_direct_types::Error.none { return result, error; }
    i32Const(g, tag);
    lset(g, w(g, result, 0));
    recordConstTag(f, w(g, result, 0), tag);
    let slots, error = g.types.layout(ty);
    if error != blot_direct_types::Error.none { return neverVal(), g.typeFailure(m, id); }
    let words, error = g.types.layout(declared);
    if error != blot_direct_types::Error.none { return neverVal(), g.typeFailure(m, id); }
    for index in 0..(payload.len as i64) {
        lget(g, w(g, payload, index));
        let src = words[index];
        let dst = slots[index + 1];
        if src != dst {
            if dst == VT_i32 {
                if src == VT_f32 { op(g, OP_i32_reinterpret_f32); }
            } else if dst == VT_i64 {
                if src == VT_f64 { op(g, OP_i64_reinterpret_f64); }
                else if src == VT_i32 { op(g, OP_i64_extend_i32_u); }
                else if src == VT_f32 { op(g, OP_i32_reinterpret_f32); op(g, OP_i64_extend_i32_u); }
            }
        }
        lset(g, w(g, result, index + 1));
    }
    return result, blot_direct_types::Error.none;
}
// The payload of `value` read as constructor `tag` (no tag check).
fn unwrapVariant(g: Generator&, f: const Fn&, value: Val, tag: u32, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let cases, error = g.types.variants(value.ty);
    if error != blot_direct_types::Error.none { return neverVal(), g.typeFailure(m, id); }
    let position, error = variantPosition(g, f, cases, tag, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let payload_ty = g.types.variant_payloads[cases.payloads + position];
    let boxed, error = isBoxed(g, f, value.ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    if boxed {
        var offset: u32 = 0;
        if cases.len > 1 { offset = 4; }
        return readFlat(g, f, w(g, value, 0), offset, payload_ty, id);
    }
    if cases.len == 1 { return Val { payload_ty, value.start, value.len }, blot_direct_types::Error.none; }
    let slots, error = g.types.layout(value.ty);
    if error != blot_direct_types::Error.none { return neverVal(), g.typeFailure(m, id); }
    let words, error = g.types.layout(payload_ty);
    if error != blot_direct_types::Error.none { return neverVal(), g.typeFailure(m, id); }
    let start = g.s.words.len as u32;
    for kind, index in words {
        let slot_kind = slots[index + 1];
        if kind == slot_kind {
            let shared = w(g, value, index + 1);
            g.s.words.push(shared);
            continue;
        }
        let made = local(g, f, kind);
        g.s.words.push(made);
        lget(g, w(g, value, index + 1));
        if slot_kind == VT_i32 {
            op(g, OP_f32_reinterpret_i32);
        } else if slot_kind == VT_i64 {
            if kind == VT_f64 { op(g, OP_f64_reinterpret_i64); }
            else if kind == VT_i32 { op(g, OP_i32_wrap_i64); }
            else if kind == VT_f32 { op(g, OP_i32_wrap_i64); op(g, OP_f32_reinterpret_i32); }
        }
        lset(g, made);
    }
    return Val { payload_ty, start, words.len as u32 }, blot_direct_types::Error.none;
}

// Resolves `project` node `id` on an already-evaluated `value`: either returns
// a data field value (`is_method = false`) or the associated method target
// (`is_method = true`) so callers like `apply` can emit a direct call without
// allocating a partial-application closure.
fn cachedProjectionFieldName(g: Generator&, m: const Module&, proj_idx: u32) -> u32 {
    let uid = (m.unit - 1) as i64;
    while g.s.proj_field_base.len < g.units.len { g.s.proj_field_base.push(0xffffffff); }
    var base = g.s.proj_field_base[uid];
    if base == 0xffffffff {
        base = g.s.proj_field_vals.len as u32;
        g.s.proj_field_base[uid] = base;
        blot_direct_types::growFill(g.s.proj_field_vals, m.projections.len);
    }
    return g.s.proj_field_vals[(base as i64) + (proj_idx as i64)];
}
fn cacheProjectionFieldName(g: Generator&, m: const Module&, proj_idx: u32, name: u32) {
    let base = g.s.proj_field_base[(m.unit - 1) as i64];
    g.s.proj_field_vals[(base as i64) + (proj_idx as i64)] = name;
}
recursive fn projectFieldOrMethod(g: Generator&, f: Fn&, id: u32, value: Val) -> Val, BindingRef, bool, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let projection = m.projection(n.b);
    let variants = m.projectionVariants(n.b);
    var name_symbol = projection.field;
    if variants.len == 1 && projection.nominal.decl == 0 && g.types.node(value.ty).tag == blot_direct_types::Tag.tuple {
        if variants[0].field >= g.types.tupleItems(value.ty).len { return neverVal(), BindingRef { 0, 0 }, false, g.fail(m, id, "tuple projection out of range"); }
        let field_val, error = tupleItem(g, f, value, variants[0].field, id);
        if error == blot_direct_types::Error.none {
            let ref_b = localRef(m, n.a);
            if ref_b != 0 && isUniqueBoxed(g, f, ref_b) {
                let is_cb, cberr = copiedBox(g, f, field_val.ty, id);
                if cberr == blot_direct_types::Error.none && !is_cb {
                    blot_support_zigmap::put(g.s.map_pool, f.unique_boxed_safe_refs, n.a, 1);
                }
            }
        }
        return field_val, BindingRef { 0, 0 }, false, error;
    }
    let nominal_field = variants.len != 0 && projection.nominal.decl != 0;
    let cached = cachedProjectionFieldName(g, m, n.b);
    if nominal_field && variants.len > 1 {
        var sym = cached;
        if sym == 0xffffffff {
            var found = false;
            for nom, ni in m.nominals {
                if !sameNominal(nom.identity, projection.nominal) { continue; }
                for ci in m.nominalConstructors(ni as u32) {
                    let constructor = m.constructors[ci];
                    if constructor.tag != variants[0].tag { continue; }
                    let payload = m.types.node(constructor.payload);
                    if payload.tag != blot_check_types::Tag.record || variants[0].field >= payload.b { return neverVal(), BindingRef { 0, 0 }, false, g.fail(m, id, "constructor field projection"); }
                    sym = m.types.recordField(payload, variants[0].field).name;
                    found = true;
                    break;
                }
                break;
            }
            if !found { return neverVal(), BindingRef { 0, 0 }, false, g.fail(m, id, "projected constructor missing from the catalog"); }
            cacheProjectionFieldName(g, m, n.b, sym);
        }
        let field_val, error = sharedField(g, f, value, n.b, sym, id);
        return field_val, BindingRef { 0, 0 }, false, error;
    }
    var name: u32 = cached;
    if name == 0xffffffff {
        if nominal_field {
            var found = false;
            for nom, ni in m.nominals {
                if !sameNominal(nom.identity, projection.nominal) { continue; }
                for ci in m.nominalConstructors(ni as u32) {
                    let constructor = m.constructors[ci];
                    if constructor.tag != variants[0].tag { continue; }
                    let payload = m.types.node(constructor.payload);
                    if payload.tag != blot_check_types::Tag.record || variants[0].field >= payload.b { return neverVal(), BindingRef { 0, 0 }, false, g.fail(m, id, "constructor field projection"); }
                    name_symbol = m.types.recordField(payload, variants[0].field).name;
                    found = true;
                    break;
                }
                break;
            }
            if !found { return neverVal(), BindingRef { 0, 0 }, false, g.fail(m, id, "projected constructor missing from the catalog"); }
        }
        let resolved_name, has_name = g.types.fieldNameOf(m, name_symbol, true);
        if !has_name { return neverVal(), BindingRef { 0, 0 }, false, g.fail(m, id, "projected field without a spelling"); }
        name = resolved_name;
        cacheProjectionFieldName(g, m, n.b, name);
    }
    var record = value;
    if g.types.node(value.ty).tag == blot_direct_types::Tag.nominal {
        let cases, error = g.types.variants(value.ty);
        if error != blot_direct_types::Error.none { return neverVal(), BindingRef { 0, 0 }, false, g.typeFailure(m, id); }
        if cases.len == 1 {
            let unwrapped, error = unwrapVariant(g, f, value, g.types.variant_tags[cases.tags], id);
            if error != blot_direct_types::Error.none { return neverVal(), BindingRef { 0, 0 }, false, error; }
            record = unwrapped;
        } else if nominal_field && variants.len == 1 {
            let unwrapped, error = unwrapVariant(g, f, value, variants[0].tag, id);
            if error != blot_direct_types::Error.none { return neverVal(), BindingRef { 0, 0 }, false, error; }
            record = unwrapped;
        }
    }
    let position = g.types.findField(record.ty, name);
    if position >= 0 {
        let field_val, error = recordField(g, f, record, position, id);
        if error == blot_direct_types::Error.none {
            let ref_b = localRef(m, n.a);
            if ref_b != 0 && isUniqueBoxed(g, f, ref_b) {
                let is_cb, cberr = copiedBox(g, f, field_val.ty, id);
                if cberr == blot_direct_types::Error.none && !is_cb {
                    blot_support_zigmap::put(g.s.map_pool, f.unique_boxed_safe_refs, n.a, 1);
                }
            }
        }
        return field_val, BindingRef { 0, 0 }, false, error;
    }
    if nominal_field { return neverVal(), BindingRef { 0, 0 }, false, g.fail(m, id, "projected field missing"); }
    if tagOf(g, value.ty) == blot_direct_types::Tag.record { return neverVal(), BindingRef { 0, 0 }, false, g.fail(m, id, "projected field missing"); }
    let identity, has_identity = g.receiverIdentity(value.ty);
    if !has_identity {
        g.failOpen(m, id);
        g.put("member of a ");
        g.put(blot_direct_types::tagName(g.types.node(value.ty).tag));
        return neverVal(), BindingRef { 0, 0 }, false, g.failClose();
    }
    var target, has_target = g.dispatchTarget(m, identity, projection.field, blot_check_types::Operator.none);
    if !has_target {
        let spelling = m.fieldSpelling(name_symbol);
        if !spelling.present { return neverVal(), BindingRef { 0, 0 }, false, g.fail(m, id, "projected field without a spelling"); }
        let want_spell = spelling.value;
        var found_trait = BindingRef { 0, 0 };
        for unit in g.units {
            for impl_ in unit.implementations {
                let head_list = unit.types.list(impl_.head);
                if head_list.len == 0 { continue; }
                var match_env = Env {};
                g.types.match_(unit, head_list[0], value.ty, match_env);
                let lowered, lerr = g.types.lower(unit, head_list[0], match_env);
                if lerr != blot_direct_types::Error.none { continue; }
                if lowered != value.ty {
                    continue;
                }
                for member in unit.implementation_members[impl_.members.start..impl_.members.start + impl_.members.len] {
                    if member.kind != blot_reuse_principal_interface::ImplementationMemberKind.value { continue; }
                    let msp = unit.fieldSpelling(member.name);
                    if !msp.present || msp.value != want_spell { continue; }
                    let cand = g.resolve(unit, BindingRef { member.target.unit, member.target.binding });
                    if found_trait.binding != 0 && found_trait != cand { return neverVal(), BindingRef { 0, 0 }, false, g.fail(m, id, "ambiguous trait member on comptime field"); }
                    found_trait = cand;
                }
            }
        }
        if found_trait.binding != 0 {
            target = found_trait;
            has_target = true;
        }
    }
    if !has_target {
        let spelling = m.fieldSpelling(name_symbol);
        g.failOpen(m, id);
        g.put("no member ");
        if spelling.present { g.put(spelling.value); }
        g.put(" for this receiver");
        return neverVal(), BindingRef { 0, 0 }, false, g.failClose();
    }
    return neverVal(), target, true, blot_direct_types::Error.none;
}
// Direct field projection from a boxed array element (`arr[i].f1.f2`) without
// stack-allocating and `memory.copy`ing the entire outer element block.
fn tryProjectBoxedArrayElement(g: Generator&, f: Fn&, id: u32) -> Val, bool, Error {
    let m .= g.units[f.unit - 1];
    var proj_nodes: u32[8] = [0; 8];
    var proj_len: i64 = 0;
    var cursor = id;
    while m.node(cursor).tag == blot_check_core::Tag.project && proj_len < 8 {
        proj_nodes[proj_len] = cursor;
        proj_len += 1;
        cursor = m.node(cursor).a;
    }
    if proj_len == 0 { return neverVal(), false, blot_direct_types::Error.none; }
    var arr_node: u32 = 0;
    var idx_node: u32 = 0;
    let cn = m.node(cursor);
    if cn.tag == blot_check_core::Tag.array_op && m.arrayOperation(cursor) == blot_backend_collection_ops::Op.get {
        let ch = m.children(cursor);
        if ch.len == 2 { arr_node = ch[0]; idx_node = ch[1]; }
    } else if cn.tag == blot_check_core::Tag.storage {
        let op_k, ok = blot_check_storage_ops::opFromCode(cn.c);
        if ok == blot_error::Error.none && op_k == blot_check_storage_ops::Op.read {
            let ch = m.children(cursor);
            if ch.len == 2 { arr_node = ch[0]; idx_node = ch[1]; }
        }
    }
    if arr_node == 0 { return neverVal(), false, blot_direct_types::Error.none; }
    let elem_ty, eerr = g.types.lower(m, m.typeOf(cursor), f.env);
    if eerr != blot_direct_types::Error.none { g.dropFailure(); return neverVal(), false, blot_direct_types::Error.none; }
    let is_cb, cberr = copiedBox(g, f, elem_ty, cursor);
    if cberr != blot_direct_types::Error.none || !is_cb { return neverVal(), false, blot_direct_types::Error.none; }
    // Verify the entire projection chain resolves purely to static record fields
    // at fixed byte offsets before emitting any code.
    var cur_ty = elem_ty;
    var total_offset: u32 = 0;
    var step = proj_len;
    while step > 0 {
        step -= 1;
        let pid = proj_nodes[step];
        let pn = m.node(pid);
        let projection = m.projection(pn.b);
        let variants = m.projectionVariants(pn.b);
        if variants.len > 1 { return neverVal(), false, blot_direct_types::Error.none; }
        if variants.len == 1 && projection.nominal.decl == 0 { return neverVal(), false, blot_direct_types::Error.none; }
        var record_ty = cur_ty;
        if tagOf(g, cur_ty) == blot_direct_types::Tag.nominal {
            let cases, cerr = g.types.variants(cur_ty);
            if cerr != blot_direct_types::Error.none || cases.len != 1 { return neverVal(), false, blot_direct_types::Error.none; }
            record_ty = g.types.variant_payloads[cases.payloads];
        }
        if tagOf(g, record_ty) != blot_direct_types::Tag.record { return neverVal(), false, blot_direct_types::Error.none; }
        var name_sym = projection.field;
        if variants.len == 1 && projection.nominal.decl != 0 {
            var found = false;
            for nom, ni in m.nominals {
                if !sameNominal(nom.identity, projection.nominal) { continue; }
                for ci in m.nominalConstructors(ni as u32) {
                    let ctor = m.constructors[ci];
                    if ctor.tag != variants[0].tag { continue; }
                    let payload = m.types.node(ctor.payload);
                    if payload.tag != blot_check_types::Tag.record || variants[0].field >= payload.b { return neverVal(), false, blot_direct_types::Error.none; }
                    name_sym = m.types.recordField(payload, variants[0].field).name;
                    found = true;
                    break;
                }
                break;
            }
            if !found { return neverVal(), false, blot_direct_types::Error.none; }
        }
        let field_name, has_name = g.types.fieldNameOf(m, name_sym, true);
        if !has_name { return neverVal(), false, blot_direct_types::Error.none; }
        let pos = g.types.findField(record_ty, field_name);
        if pos < 0 { return neverVal(), false, blot_direct_types::Error.none; }
        let foff, ferr = fieldOffset(g, f, record_ty, pos, pid);
        if ferr != blot_direct_types::Error.none { return neverVal(), false, blot_direct_types::Error.none; }
        total_offset += foff;
        cur_ty = g.types.recordField(record_ty, pos).ty;
    }
    let container, aerr = expr(g, f, arr_node);
    if aerr != blot_direct_types::Error.none { return container, true, aerr; }
    let position, perr = expr(g, f, idx_node);
    if perr != blot_direct_types::Error.none { return position, true, perr; }
    let index, serr = scalarLocal(g, f, position, cursor);
    if serr != blot_direct_types::Error.none { return neverVal(), true, serr; }
    let addr, eaddr_err = elementAddress(g, f, container, index, cursor, m.typeOf(arr_node), true);
    if eaddr_err != blot_direct_types::Error.none { return neverVal(), true, eaddr_err; }
    var target_addr = addr;
    var load_off = total_offset;
    let res_cb, rberr = copiedBox(g, f, cur_ty, id);
    if rberr != blot_direct_types::Error.none { return neverVal(), true, rberr; }
    if res_cb && load_off != 0 {
        target_addr = local32(g, f);
        lget(g, addr);
        i32Const(g, load_off);
        op(g, OP_i32_add);
        lset(g, target_addr);
        load_off = 0;
    }
    let loaded, lerr = loadElement(g, f, target_addr, load_off, cur_ty, id);
    return loaded, true, lerr;
}
recursive fn project(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let direct_val, did_direct, direct_err = tryProjectBoxedArrayElement(g, f, id);
    if direct_err != blot_direct_types::Error.none { return direct_val, direct_err; }
    if did_direct { return direct_val, blot_direct_types::Error.none; }
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    if m.node(n.a).tag == blot_check_core::Tag.reference {
        let sp = m.fieldSpelling(m.projection(n.b).field);
        if sp.present && sp.value == "length" {
            let rd, is_rd = tryResolveRodata(g, f, n.a);
            if is_rd {
                let klen = constLocal(g, f, rd.count);
                recordConstU32(f, klen, rd.count);
                return valOf1(g, blot_direct_types::u32_, klen), blot_direct_types::Error.none;
            }
        }
    }
    let value, error = expr(g, f, n.a);
    if error != blot_direct_types::Error.none { return value, error; }
    let field_val, target, is_method, error = projectFieldOrMethod(g, f, id, value);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    if !is_method { return field_val, blot_direct_types::Error.none; }
    let arguments = g.saveVals([value]);
    let callee, error = calleeOf(g, f, target, arguments, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let rest, error = restType(g, f, callee, 1, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    return callTarget(g, f, target, arguments, callee, rest, id);
}

// A field several constructors declare: select the variant by its tag and
// read the field from its payload. Other constructors trap.
fn sharedField(g: Generator&, f: Fn&, value: Val, projection: u32, field: u32, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let variants = m.projectionVariants(projection);
    let spelling = m.fieldSpelling(field);
    if !spelling.present { return neverVal(), g.fail(m, id, "projected field without a spelling"); }
    let name = g.types.fieldName(spelling.value);
    let tag = local32(g, f);
    lget(g, w(g, value, 0));
    let boxed, error = isBoxed(g, f, value.ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    if boxed { memoryOp(g, OP_i32_load, 0); }
    lset(g, tag);
    var has_result = false;
    var result = neverVal();
    let exit = open(g, f, OP_block);
    for variant in variants {
        let next = open(g, f, OP_block);
        lget(g, tag);
        i32Const(g, variant.tag);
        op(g, OP_i32_ne);
        br(g, f, OP_br_if, next);
        let payload, error = unwrapVariant(g, f, value, variant.tag, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        let position = g.types.findField(payload.ty, name);
        if position < 0 { return neverVal(), g.fail(m, id, "shared field missing from a constructor"); }
        let item, error = recordField(g, f, payload, position, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        if !has_result {
            let made, error = fresh(g, f, item.ty, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            result = made;
            has_result = true;
        }
        let copied = copy(g, f, item, result, id);
        if copied != blot_direct_types::Error.none { return neverVal(), copied; }
        br(g, f, OP_br, exit);
        close(g, f);
    }
    op(g, OP_unreachable_);
    close(g, f);
    return result, blot_direct_types::Error.none;
}

// The primitive a constant such as `const U32.add = @u32.add` names.
fn primitiveAlias(m: const Module&, binding_id: u32) -> u32, bool {
    let binding = m.binding(binding_id);
    var value = binding.initializer;
    let body .= m.body(binding_id);
    if body {
        if body.is_function { return 0, false; }
        value = body.root;
    }
    if value == 0 || m.node(value).tag != blot_check_core::Tag.primitive_function { return 0, false; }
    return value, true;
}
// The result type of a scalar operator on operands of type `operand`.
fn scalarResult(op_: blot_check_core::Op, operand: Ty) -> Ty {
    match op_ {
        equal, not_equal, less, less_equal, greater, greater_equal => { return blot_direct_types::boolean; },
        convert_u32_f32, convert_i32_f32 => { return blot_direct_types::f32_; },
        convert_f32_u32, convert_f32_i32 => { return blot_direct_types::u32_; },
        _ => { return operand; },
    }
}
fn operatorOf(op_: blot_check_core::Op) -> blot_check_types::Operator, bool {
    match op_ {
        add => { return blot_check_types::Operator.add, true; },
        sub => { return blot_check_types::Operator.sub, true; },
        mul => { return blot_check_types::Operator.mul, true; },
        div => { return blot_check_types::Operator.div, true; },
        rem => { return blot_check_types::Operator.rem, true; },
        equal => { return blot_check_types::Operator.equal, true; },
        not_equal => { return blot_check_types::Operator.not_equal, true; },
        less => { return blot_check_types::Operator.less, true; },
        less_equal => { return blot_check_types::Operator.less_equal, true; },
        greater => { return blot_check_types::Operator.greater, true; },
        greater_equal => { return blot_check_types::Operator.greater_equal, true; },
        bit_and => { return blot_check_types::Operator.bit_and, true; },
        bit_or => { return blot_check_types::Operator.bit_or, true; },
        bit_xor => { return blot_check_types::Operator.bit_xor, true; },
        shift_left => { return blot_check_types::Operator.shift_left, true; },
        shift_right => { return blot_check_types::Operator.shift_right, true; },
        _ => { return blot_check_types::Operator.none, false; },
    }
}
// Whether two catalog identities name the same nominal type.
fn sameNominal(left: blot_check_types::NominalIdentity, right: blot_check_types::NominalIdentity) -> bool {
    return left.unit == right.unit && left.decl == right.decl;
}
fn requirements(tm: const Module&, binding: u32) -> bool {
    if tm.binding(binding).scheme.obligations.len != 0 { return true; }
    let body .= tm.body(binding);
    if !body { return false; }
    return body.scheme.obligations.len != 0;
}
