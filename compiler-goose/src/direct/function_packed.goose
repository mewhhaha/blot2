// Packed sequential arrays (`%[T]` / `Tag.packed`) for the direct Wasm backend.
// Register layout is always `(slot, gen)` (2 x VT_i32). Physically lowers to:
//   1. PACKED_SPLIT_SUM: header owner holding `(sub_slot, sub_gen)` pairs for
//      stream 0 = dense U8 variant tags + streams 1..S-1 = contiguous inline
//      (un-outlined) payload arrays for each non-empty variant.
//   2. PACKED_SOA: header owner holding `(sub_slot, sub_gen)` pairs for one
//      contiguous column stream per non-zero-byte field/item.
//   3. PACKED_FLAT: single contiguous buffer `(slot, gen)` walked by raw cursor.
namespace blot_direct_function;
import .function;

let PACKED_FLAT: u32 = 0;
let PACKED_SOA: u32 = 1;
let PACKED_SPLIT_SUM: u32 = 2;

struct PackedPlan {
    mode: u32 = 0,
    elem_ty: Ty = 0,
    soa_is_nominal: bool = false,
    soa_nominal_tag: u32 = 0,
    soa_inner_ty: Ty = 0,
    soa_is_record: bool = false,
    soa_field_count: i64 = 0,
    soa_field_stream: i64[16] = [-1; 16],
    soa_field_ty: Ty[16] = [0; 16],
    variant_count: i64 = 0,
    variant_stream: i64[256] = [-1; 256],
    stream_count: i64 = 0,
    stream_ty: Ty[16] = [0; 16],
    stream_stride: u32[16] = [0; 16],
}

// Active virtual SoA field bindings during a touched-column `for p in packed:` loop.
var soa_loop_depth: i64 = 0;
var soa_loop_binding: u32[8] = [0; 8];
var soa_loop_ty: Ty[8] = [0; 8];
var soa_loop_inner_ty: Ty[8] = [0; 8];
var soa_loop_is_record: bool[8] = [false; 8];
var soa_loop_field_loaded: bool[128] = [false; 128];
var soa_loop_field_start: u32[128] = [0; 128];
var soa_loop_field_len: u32[128] = [0; 128];
var soa_loop_field_ty: Ty[128] = [0; 128];

// Active fused `for ev in packed:` + `case ev of ...` split-stream dispatch state.
var split_sum_depth: i64 = 0;
var split_sum_binding: u32[4] = [0; 4];
var split_sum_ty: Ty[4] = [0; 4];
var split_sum_ci_loc: u32[4] = [0; 4];
var split_sum_needed_lo: u64[4] = [0; 4];
var split_sum_cur_ptrs: u32[64] = [0; 64]; // [depth * 16 + s]
var split_sum_stream_stride: u32[64] = [0; 64]; // [depth * 16 + s]
var split_sum_variant_stream: i64[256] = [-1; 256]; // [depth * 64 + ci] (fused supports <= 64 variants)

fn computeSoaPlan(g: Generator&, f: const Fn&, elem_ty: Ty, inner_ty: Ty, is_nominal: bool, nom_tag: u32, id: u32) -> PackedPlan, bool, Error {
    var plan = PackedPlan {
        mode: PACKED_FLAT,
        elem_ty: elem_ty,
        soa_is_nominal: is_nominal,
        soa_nominal_tag: nom_tag,
        soa_inner_ty: inner_ty,
        ..
    };
    let in_node = g.types.node(inner_ty);
    let is_rec = in_node.tag == blot_direct_types::Tag.record;
    let is_tup = in_node.tag == blot_direct_types::Tag.tuple;
    if !is_rec && !is_tup { return plan, false, blot_direct_types::Error.none; }
    let count = in_node.b as i64;
    if count < 2 || count > 16 { return plan, false, blot_direct_types::Error.none; }
    plan.soa_is_record = is_rec;
    plan.soa_field_count = count;
    var s_idx: i64 = 0;
    for fi in 0..count {
        let fty = if is_rec { g.types.recordField(inner_ty, fi).ty } else { g.types.words[in_node.a + fi] };
        plan.soa_field_ty[fi] = fty;
        let fbytes, berr = flatBytes(g, f, fty, id);
        if berr != blot_direct_types::Error.none { return plan, false, berr; }
        if fbytes == 0 {
            plan.soa_field_stream[fi] = -1;
        } else {
            plan.soa_field_stream[fi] = s_idx;
            plan.stream_ty[s_idx] = fty;
            plan.stream_stride[s_idx] = fbytes;
            s_idx += 1;
        }
    }
    if s_idx < 2 { return PackedPlan { mode: PACKED_FLAT, elem_ty: elem_ty, .. }, false, blot_direct_types::Error.none; }
    plan.mode = PACKED_SOA;
    plan.stream_count = s_idx;
    return plan, true, blot_direct_types::Error.none;
}

fn computePackedPlan(g: Generator&, f: const Fn&, elem_ty: Ty, id: u32) -> PackedPlan, Error {
    var flat_plan = PackedPlan { mode: PACKED_FLAT, elem_ty: elem_ty, .. };
    let is_rec, rerr = g.types.isRecursive(elem_ty);
    if rerr != blot_direct_types::Error.none { return flat_plan, g.typeFailure(g.units[f.unit - 1], id); }
    if is_rec { return flat_plan, blot_direct_types::Error.none; }
    let n = g.types.node(elem_ty);
    if n.tag == blot_direct_types::Tag.nominal {
        let cases, cerr = g.types.variants(elem_ty);
        if cerr != blot_direct_types::Error.none { return flat_plan, g.typeFailure(g.units[f.unit - 1], id); }
        if cases.len >= 2 && cases.len <= 256 {
            var plan = PackedPlan {
                mode: PACKED_SPLIT_SUM,
                elem_ty: elem_ty,
                variant_count: cases.len as i64,
                ..
            };
            plan.stream_ty[0] = blot_direct_types::u8_;
            plan.stream_stride[0] = 1;
            var s_idx: i64 = 1;
            for ci in 0..(cases.len as i64) {
                let pty = g.types.variant_payloads[cases.payloads + ci];
                let pbytes, berr = flatBytes(g, f, pty, id);
                if berr != blot_direct_types::Error.none { return flat_plan, berr; }
                if pbytes == 0 {
                    plan.variant_stream[ci] = -1;
                } else {
                    if s_idx >= 16 { return flat_plan, blot_direct_types::Error.none; }
                    plan.variant_stream[ci] = s_idx;
                    plan.stream_ty[s_idx] = pty;
                    plan.stream_stride[s_idx] = pbytes;
                    s_idx += 1;
                }
            }
            if s_idx >= 2 {
                plan.stream_count = s_idx;
                return plan, blot_direct_types::Error.none;
            }
            return flat_plan, blot_direct_types::Error.none;
        }
        if cases.len == 1 {
            let pty = g.types.variant_payloads[cases.payloads];
            let prec, prerr = g.types.isRecursive(pty);
            if prerr != blot_direct_types::Error.none { return flat_plan, g.typeFailure(g.units[f.unit - 1], id); }
            if !prec {
                let vtag = g.types.variant_tags[cases.tags];
                let soa, ok, serr = computeSoaPlan(g, f, elem_ty, pty, true, vtag, id);
                if serr != blot_direct_types::Error.none { return flat_plan, serr; }
                if ok { return soa, blot_direct_types::Error.none; }
            }
        }
        return flat_plan, blot_direct_types::Error.none;
    }
    if n.tag == blot_direct_types::Tag.record || n.tag == blot_direct_types::Tag.tuple {
        let soa, ok, serr = computeSoaPlan(g, f, elem_ty, elem_ty, false, 0, id);
        if serr != blot_direct_types::Error.none { return flat_plan, serr; }
        if ok { return soa, blot_direct_types::Error.none; }
    }
    return flat_plan, blot_direct_types::Error.none;
}

// Checks header handle is live and not a deeply-immutable static const pool.
// Returns (h_entry, h_base, h_len).
fn emitCheckPackedHeaderMutable(g: Generator&, f: Fn&, container: Val) -> u32, u32, u32 {
    let rt = g.runtime_();
    let h_entry = local32(g, f);
    let h_base = local32(g, f);
    let h_len = local32(g, f);
    lget(g, w(g, container, 0));
    lget(g, w(g, container, 1));
    callf(g, rt.check);
    ltee(g, h_entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_capacity);
    i32Const(g, blot_direct_runtime::static_pool_flag);
    op(g, OP_i32_and);
    trap(g, f);
    lget(g, h_entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
    lset(g, h_base);
    lget(g, h_entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
    lset(g, h_len);
    return h_entry, h_base, h_len;
}

// Loads `(sub_slot, sub_gen)` of stream `s` from header buffer `h_base`.
fn emitLoadPackedSubHandle(g: Generator&, f: const Fn&, h_base: u32, s: i64) -> u32, u32 {
    let off = (s as u32) * 8;
    let sub_slot = local32(g, f);
    let sub_gen = local32(g, f);
    lget(g, h_base);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, off);
    lset(g, sub_slot);
    lget(g, h_base);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, off + 4);
    lset(g, sub_gen);
    return sub_slot, sub_gen;
}

fn emitLoadPackedSubBase(g: Generator&, f: Fn&, h_base: u32, s: i64) -> u32 {
    let sub_slot, sub_gen = emitLoadPackedSubHandle(g, f, h_base, s);
    let sub_base = local32(g, f);
    lget(g, sub_slot);
    lget(g, sub_gen);
    callf(g, g.runtime_().check);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
    lset(g, sub_base);
    return sub_base;
}

fn emitPackedCreateSub(g: Generator&, f: Fn&, cap_local: u32, has_cap: bool, step: u32) -> u32, u32 {
    let rt = g.runtime_();
    let sub_slot = local32(g, f);
    let sub_gen = local32(g, f);
    if !has_cap {
        i32Const(g, 0);
        i32Const(g, step);
        i32Const(g, 0);
        callf(g, rt.create);
        lset(g, sub_gen);
        lset(g, sub_slot);
        return sub_slot, sub_gen;
    }
    lget(g, cap_local);
    i32Const(g, 0x04000000);
    op(g, OP_i32_gt_u);
    trap(g, f);
    if step != 0 {
        lget(g, cap_local);
        i32Const(g, blot_direct_runtime::capacity_mask / step);
        op(g, OP_i32_gt_u);
        trap(g, f);
    }
    let bytes = emitScaledBytes(g, f, cap_local, step);
    lget(g, bytes);
    let nz = open(g, f, OP_if_);
    if f.inline_depth == 0 && f.loop_depth == 0 {
        lget(g, bytes);
        callf(g, rt.stack);
        i32Const(g, 0);
        lget(g, bytes);
        callf(g, rt.open);
        lset(g, sub_gen);
        lset(g, sub_slot);
    } else {
        lget(g, bytes);
        i32Const(g, 4194304);
        op(g, OP_i32_gt_u);
        let lg = open(g, f, OP_if_);
        lget(g, bytes);
        callf(g, rt.stack);
        i32Const(g, 0);
        lget(g, bytes);
        callf(g, rt.open);
        lset(g, sub_gen);
        lset(g, sub_slot);
        popCheckedArraysAt(f, lg);
        op(g, OP_else_);
        lget(g, bytes);
        i32Const(g, 0);
        callf(g, rt.open_heap);
        op(g, OP_drop);
        op(g, OP_drop);
        lset(g, sub_gen);
        lset(g, sub_slot);
        close(g, f);
    }
    popCheckedArraysAt(f, nz);
    op(g, OP_else_);
    i32Const(g, 0);
    i32Const(g, step);
    i32Const(g, 0);
    callf(g, rt.create);
    lset(g, sub_gen);
    lset(g, sub_slot);
    close(g, f);
    return sub_slot, sub_gen;
}

fn emitPackedWithCapacity(g: Generator&, f: Fn&, ty: Ty, cap_local: u32, has_cap: bool, id: u32) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, ty, id);
    if eerr != blot_direct_types::Error.none { return neverVal(), eerr; }
    let plan, perr = computePackedPlan(g, f, elem_ty, id);
    if perr != blot_direct_types::Error.none { return neverVal(), perr; }
    let rt = g.runtime_();
    noteAllocation(f);
    if plan.mode == PACKED_FLAT {
        let step, serr = stride(g, f, elem_ty, id);
        if serr != blot_direct_types::Error.none { return neverVal(), serr; }
        let slot, gen = emitPackedCreateSub(g, f, cap_local, has_cap, step);
        let handle = valOf2(g, ty, slot, gen);
        recordMutable(g, f, handle);
        return handle, blot_direct_types::Error.none;
    }
    let header_bytes = (plan.stream_count as u32) * 8;
    let h_base = local32(g, f);
    i32Const(g, header_bytes);
    callf(g, rt.stack);
    lset(g, h_base);
    for s in 0..plan.stream_count {
        let use_cap = has_cap && (plan.mode == PACKED_SOA || s == 0);
        let sub_slot, sub_gen = emitPackedCreateSub(g, f, cap_local, use_cap, plan.stream_stride[s]);
        let off = (s as u32) * 8;
        lget(g, h_base);
        lget(g, sub_slot);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, off);
        lget(g, h_base);
        lget(g, sub_gen);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, off + 4);
    }
    lget(g, h_base);
    i32Const(g, 0);
    i32Const(g, header_bytes);
    callf(g, rt.open);
    let handle, herr = pop(g, f, ty, id);
    if herr != blot_direct_types::Error.none { return handle, herr; }
    recordMutable(g, f, handle);
    return handle, blot_direct_types::Error.none;
}

// Assemble a concrete SoA element value (record, tuple, or single-ctor nominal) from field Vals.
fn assembleSoaVal(g: Generator&, f: Fn&, plan: const PackedPlan&, field_vals: Vals, id: u32) -> Val, Error {
    let inner_ty = plan.soa_inner_ty;
    let boxed, berr = isBoxed(g, f, inner_ty, id);
    if berr != blot_direct_types::Error.none { return neverVal(), berr; }
    var inner_val = neverVal();
    if boxed {
        let blk, bkerr = newBlock(g, f, inner_ty, id);
        if bkerr != blot_direct_types::Error.none { return neverVal(), bkerr; }
        for fi in 0..plan.soa_field_count {
            let fv = g.s.vals[field_vals.start + fi];
            let off = if plan.soa_is_record {
                let fo, ferr = fieldOffset(g, f, inner_ty, fi, id);
                if ferr != blot_direct_types::Error.none { return neverVal(), ferr; }
                fo
            } else {
                let io, ierr = itemOffset(g, f, inner_ty, fi, id);
                if ierr != blot_direct_types::Error.none { return neverVal(), ierr; }
                io
            };
            let werr = writeFlat(g, f, blk, off, fv, id);
            if werr != blot_direct_types::Error.none { return neverVal(), werr; }
        }
        inner_val = valOf1(g, inner_ty, blk);
    } else {
        let s .= g.s;
        let mark = s.scratch.len;
        for fi in 0..plan.soa_field_count {
            let fv = g.s.vals[field_vals.start + fi];
            for wi in 0..(fv.len as i64) { s.scratch.push(g.s.words[fv.start + wi]); }
        }
        let start = g.s.words.len as u32;
        let wlen = (s.scratch.len - mark) as u32;
        for at in mark..s.scratch.len { let word = s.scratch[at]; g.s.words.push(word); }
        s.scratch.resize(mark);
        inner_val = Val { inner_ty, start, wlen };
    }
    if plan.soa_is_nominal {
        return wrapVariant(g, f, plan.elem_ty, plan.soa_nominal_tag, inner_val, id);
    }
    return inner_val, blot_direct_types::Error.none;
}

fn emitPackedPushVal(g: Generator&, f: Fn&, container: Val, value: Val, id: u32, selective: bool = false) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, container.ty, id);
    if eerr != blot_direct_types::Error.none { return neverVal(), eerr; }
    let plan, perr = computePackedPlan(g, f, elem_ty, id);
    if perr != blot_direct_types::Error.none { return neverVal(), perr; }
    let rt = g.runtime_();
    if plan.mode == PACKED_FLAT {
        let step, serr = stride(g, f, elem_ty, id);
        if serr != blot_direct_types::Error.none { return neverVal(), serr; }
        let address = local32(g, f);
        lget(g, w(g, container, 0));
        lget(g, w(g, container, 1));
        i32Const(g, step);
        callf(g, rt.push);
        lset(g, address);
        let noted = noteStoreToSlot(g, f, w(g, container, 0), value);
        if noted != blot_direct_types::Error.none { return neverVal(), noted; }
        if rt.has_fork { recordBeforeWrite(g, f, w(g, container, 0), address, 0, step); }
        let werr = writeElement(g, f, address, 0, value, id);
        if werr != blot_direct_types::Error.none { return neverVal(), werr; }
        if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
        return container, blot_direct_types::Error.none;
    }
    let h_entry, h_base, h_len = emitCheckPackedHeaderMutable(g, f, container);
    if plan.mode == PACKED_SOA {
        var inner_val = value;
        if plan.soa_is_nominal {
            let uw, uerr = unwrapVariant(g, f, value, plan.soa_nominal_tag, id);
            if uerr != blot_direct_types::Error.none { return neverVal(), uerr; }
            inner_val = uw;
        }
        for fi in 0..plan.soa_field_count {
            let s = plan.soa_field_stream[fi];
            if s < 0 { continue; }
            let fval = if plan.soa_is_record {
                let fv, ferr = recordField(g, f, inner_val, fi, id);
                if ferr != blot_direct_types::Error.none { return neverVal(), ferr; }
                fv
            } else {
                let iv, ierr = tupleItem(g, f, inner_val, fi, id);
                if ierr != blot_direct_types::Error.none { return neverVal(), ierr; }
                iv
            };
            let sub_slot, sub_gen = emitLoadPackedSubHandle(g, f, h_base, s);
            let step = plan.stream_stride[s];
            let addr = local32(g, f);
            lget(g, sub_slot);
            lget(g, sub_gen);
            i32Const(g, step);
            callf(g, rt.push);
            lset(g, addr);
            let noted = noteStoreToSlot(g, f, sub_slot, fval);
            if noted != blot_direct_types::Error.none { return neverVal(), noted; }
            if rt.has_fork { recordBeforeWrite(g, f, sub_slot, addr, 0, step); }
            let werr = writeElement(g, f, addr, 0, fval, id);
            if werr != blot_direct_types::Error.none { return neverVal(), werr; }
        }
        if rt.has_fork {
            recordBeforeWrite(g, f, w(g, container, 0), h_entry, blot_direct_runtime::entry_length, 4);
        }
        lget(g, h_entry);
        lget(g, h_len);
        i32Const(g, 1);
        op(g, OP_i32_add);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
        if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
        return container, blot_direct_types::Error.none;
    }
    // PACKED_SPLIT_SUM
    let cases, cerr = g.types.variants(elem_ty);
    if cerr != blot_direct_types::Error.none { return neverVal(), g.typeFailure(g.units[f.unit - 1], id); }
    let tag_loc = local32(g, f);
    let terr = emitValueTag(g, f, value, id);
    if terr != blot_direct_types::Error.none { return neverVal(), terr; }
    lset(g, tag_loc);
    let t_slot, t_gen = emitLoadPackedSubHandle(g, f, h_base, 0);
    let t_addr = local32(g, f);
    lget(g, t_slot);
    lget(g, t_gen);
    i32Const(g, 1);
    callf(g, rt.push);
    lset(g, t_addr);
    if rt.has_fork { recordBeforeWrite(g, f, t_slot, t_addr, 0, 1); }
    let done = open(g, f, OP_block);
    for ci in 0..plan.variant_count {
        let vtag = g.types.variant_tags[cases.tags + ci];
        let next = open(g, f, OP_block);
        lget(g, tag_loc);
        i32Const(g, vtag);
        op(g, OP_i32_ne);
        br(g, f, OP_br_if, next);
        lget(g, t_addr);
        i32Const(g, ci as u32);
        op(g, OP_i32_store8); uleb(g, 0); uleb(g, 0);
        let s = plan.variant_stream[ci];
        if s >= 0 {
            let payload, uerr = unwrapVariant(g, f, value, vtag, id);
            if uerr != blot_direct_types::Error.none { return neverVal(), uerr; }
            let p_slot, p_gen = emitLoadPackedSubHandle(g, f, h_base, s);
            let step = plan.stream_stride[s];
            let p_addr = local32(g, f);
            lget(g, p_slot);
            lget(g, p_gen);
            i32Const(g, step);
            callf(g, rt.push);
            lset(g, p_addr);
            let noted = noteStoreToSlot(g, f, p_slot, payload);
            if noted != blot_direct_types::Error.none { return neverVal(), noted; }
            if rt.has_fork { recordBeforeWrite(g, f, p_slot, p_addr, 0, step); }
            let werr = writeElement(g, f, p_addr, 0, payload, id);
            if werr != blot_direct_types::Error.none { return neverVal(), werr; }
        }
        br(g, f, OP_br, done);
        close(g, f);
    }
    op(g, OP_unreachable_);
    close(g, f);
    if rt.has_fork {
        recordBeforeWrite(g, f, w(g, container, 0), h_entry, blot_direct_runtime::entry_length, 4);
    }
    lget(g, h_entry);
    lget(g, h_len);
    i32Const(g, 1);
    op(g, OP_i32_add);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
    if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
    return container, blot_direct_types::Error.none;
}

fn emitPackedFromValues(g: Generator&, f: Fn&, ty: Ty, values: Vals, id: u32) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, ty, id);
    if eerr != blot_direct_types::Error.none { return neverVal(), eerr; }
    let plan, perr = computePackedPlan(g, f, elem_ty, id);
    if perr != blot_direct_types::Error.none { return neverVal(), perr; }
    let cap = constLocal(g, f, values.len);
    recordConstU32(f, cap, values.len);
    if plan.mode == PACKED_FLAT {
        if values.len == 0 { return emitPackedWithCapacity(g, f, ty, cap, false, id); }
        let rt = g.runtime_();
        noteAllocation(f);
        let step, serr = stride(g, f, elem_ty, id);
        if serr != blot_direct_types::Error.none { return neverVal(), serr; }
        let bytes = emitScaledBytes(g, f, cap, step);
        let base = local32(g, f);
        lget(g, bytes);
        callf(g, rt.stack);
        lset(g, base);
        lget(g, base);
        lget(g, cap);
        lget(g, bytes);
        callf(g, rt.open);
        let handle, herr = pop(g, f, ty, id);
        if herr != blot_direct_types::Error.none { return handle, herr; }
        recordMutable(g, f, handle);
        recordCheckedArray(f, w(g, handle, 0), w(g, handle, 1), base, cap);
        for idx in 0..(values.len as i64) {
            let v = g.s.vals[values.start + idx];
            let noted = noteStoreToSlot(g, f, w(g, handle, 0), v);
            if noted != blot_direct_types::Error.none { return neverVal(), noted; }
            let werr = writeElement(g, f, base, (idx as u32) * step, v, id);
            if werr != blot_direct_types::Error.none { return neverVal(), werr; }
        }
        return handle, blot_direct_types::Error.none;
    }
    let handle, herr = emitPackedWithCapacity(g, f, ty, cap, values.len > 0, id);
    if herr != blot_direct_types::Error.none { return handle, herr; }
    for idx in 0..(values.len as i64) {
        let _, perr2 = emitPackedPushVal(g, f, handle, g.s.vals[values.start + idx], id, true);
        if perr2 != blot_direct_types::Error.none { return neverVal(), perr2; }
    }
    return handle, blot_direct_types::Error.none;
}

fn emitPackedPopVal(g: Generator&, f: Fn&, container: Val, ty: Ty, id: u32, selective: bool = false) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, container.ty, id);
    if eerr != blot_direct_types::Error.none { return neverVal(), eerr; }
    let plan, perr = computePackedPlan(g, f, elem_ty, id);
    if perr != blot_direct_types::Error.none { return neverVal(), perr; }
    let rt = g.runtime_();
    if plan.mode == PACKED_FLAT {
        let step, serr = stride(g, f, elem_ty, id);
        if serr != blot_direct_types::Error.none { return neverVal(), serr; }
        let address = local32(g, f);
        lget(g, w(g, container, 0));
        lget(g, w(g, container, 1));
        i32Const(g, step);
        callf(g, rt.pop);
        lset(g, address);
        if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
        return loadElement(g, f, address, 0, ty, id);
    }
    let h_entry, h_base, h_len = emitCheckPackedHeaderMutable(g, f, container);
    lget(g, h_len);
    op(g, OP_i32_eqz);
    trap(g, f);
    if plan.mode == PACKED_SOA {
        let field_vals = g.reserveVals(plan.soa_field_count);
        for fi in 0..plan.soa_field_count {
            let s = plan.soa_field_stream[fi];
            let fty = plan.soa_field_ty[fi];
            if s < 0 {
                g.s.vals[field_vals.start + fi] = Val { fty, 0, 0 };
                continue;
            }
            let sub_slot, sub_gen = emitLoadPackedSubHandle(g, f, h_base, s);
            let step = plan.stream_stride[s];
            let addr = local32(g, f);
            lget(g, sub_slot);
            lget(g, sub_gen);
            i32Const(g, step);
            callf(g, rt.pop);
            lset(g, addr);
            let fval, lerr = loadElement(g, f, addr, 0, fty, id);
            if lerr != blot_direct_types::Error.none { return neverVal(), lerr; }
            g.s.vals[field_vals.start + fi] = fval;
        }
        if rt.has_fork {
            recordBeforeWrite(g, f, w(g, container, 0), h_entry, blot_direct_runtime::entry_length, 4);
        }
        lget(g, h_entry);
        lget(g, h_len);
        i32Const(g, 1);
        op(g, OP_i32_sub);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
        if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
        return assembleSoaVal(g, f, plan, field_vals, id);
    }
    // PACKED_SPLIT_SUM
    let cases, cerr = g.types.variants(elem_ty);
    if cerr != blot_direct_types::Error.none { return neverVal(), g.typeFailure(g.units[f.unit - 1], id); }
    let t_slot, t_gen = emitLoadPackedSubHandle(g, f, h_base, 0);
    let t_addr = local32(g, f);
    let ci_loc = local32(g, f);
    lget(g, t_slot);
    lget(g, t_gen);
    i32Const(g, 1);
    callf(g, rt.pop);
    ltee(g, t_addr);
    op(g, OP_i32_load8_u); uleb(g, 0); uleb(g, 0);
    lset(g, ci_loc);
    if rt.has_fork {
        recordBeforeWrite(g, f, w(g, container, 0), h_entry, blot_direct_runtime::entry_length, 4);
    }
    lget(g, h_entry);
    lget(g, h_len);
    i32Const(g, 1);
    op(g, OP_i32_sub);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
    let result, rerr = fresh(g, f, ty, id);
    if rerr != blot_direct_types::Error.none { return result, rerr; }
    let done = open(g, f, OP_block);
    for ci in 0..plan.variant_count {
        let vtag = g.types.variant_tags[cases.tags + ci];
        let pty = g.types.variant_payloads[cases.payloads + ci];
        let next = open(g, f, OP_block);
        lget(g, ci_loc);
        i32Const(g, ci as u32);
        op(g, OP_i32_ne);
        br(g, f, OP_br_if, next);
        let s = plan.variant_stream[ci];
        var payload = Val { pty, 0, 0 };
        if s >= 0 {
            let p_slot, p_gen = emitLoadPackedSubHandle(g, f, h_base, s);
            let step = plan.stream_stride[s];
            let p_addr = local32(g, f);
            lget(g, p_slot);
            lget(g, p_gen);
            i32Const(g, step);
            callf(g, rt.pop);
            lset(g, p_addr);
            let loaded, lerr = loadElement(g, f, p_addr, 0, pty, id);
            if lerr != blot_direct_types::Error.none { return neverVal(), lerr; }
            payload = loaded;
        }
        let wrapped, werr = wrapVariant(g, f, elem_ty, vtag, payload, id);
        if werr != blot_direct_types::Error.none { return neverVal(), werr; }
        let cperr = copy(g, f, wrapped, result, id);
        if cperr != blot_direct_types::Error.none { return neverVal(), cperr; }
        br(g, f, OP_br, done);
        close(g, f);
    }
    op(g, OP_unreachable_);
    close(g, f);
    if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
    return result, blot_direct_types::Error.none;
}

fn emitPackedReserve(g: Generator&, f: Fn&, container: Val, additional: u32, id: u32, selective: bool = false) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, container.ty, id);
    if eerr != blot_direct_types::Error.none { return neverVal(), eerr; }
    let plan, perr = computePackedPlan(g, f, elem_ty, id);
    if perr != blot_direct_types::Error.none { return neverVal(), perr; }
    let rt = g.runtime_();
    if plan.mode == PACKED_FLAT {
        let step, serr = stride(g, f, elem_ty, id);
        if serr != blot_direct_types::Error.none { return neverVal(), serr; }
        let cur_len, lerr = lengthOf(g, f, container, id);
        if lerr != blot_direct_types::Error.none { return neverVal(), lerr; }
        let need = local32(g, f);
        lget(g, cur_len);
        lget(g, additional);
        op(g, OP_i32_add);
        ltee(g, need);
        lget(g, cur_len);
        op(g, OP_i32_lt_u);
        trap(g, f);
        lget(g, w(g, container, 0));
        lget(g, w(g, container, 1));
        lget(g, need);
        i32Const(g, step);
        callf(g, rt.reserve);
        if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
        return container, blot_direct_types::Error.none;
    }
    let _, h_base, h_len = emitCheckPackedHeaderMutable(g, f, container);
    let need = local32(g, f);
    lget(g, h_len);
    lget(g, additional);
    op(g, OP_i32_add);
    ltee(g, need);
    lget(g, h_len);
    op(g, OP_i32_lt_u);
    trap(g, f);
    let limit = if plan.mode == PACKED_SOA { plan.stream_count } else { 1 };
    for s in 0..limit {
        let sub_slot, sub_gen = emitLoadPackedSubHandle(g, f, h_base, s);
        lget(g, sub_slot);
        lget(g, sub_gen);
        lget(g, need);
        i32Const(g, plan.stream_stride[s]);
        callf(g, rt.reserve);
    }
    if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
    return container, blot_direct_types::Error.none;
}

// Helper: reconstruct one element of `src` (packed multi-stream) at cursors `cur_ptrs` and advance them.
fn emitPackedDecodeStep(g: Generator&, f: Fn&, plan: const PackedPlan&, cur_ptrs: const u32[:], tags_base: u32, idx_local: u32, id: u32) -> Val, Error {
    if plan.mode == PACKED_SOA {
        let field_vals = g.reserveVals(plan.soa_field_count);
        for fi in 0..plan.soa_field_count {
            let s = plan.soa_field_stream[fi];
            let fty = plan.soa_field_ty[fi];
            if s < 0 {
                g.s.vals[field_vals.start + fi] = Val { fty, 0, 0 };
                continue;
            }
            let fv, lerr = loadElement(g, f, cur_ptrs[s], 0, fty, id);
            if lerr != blot_direct_types::Error.none { return neverVal(), lerr; }
            lget(g, cur_ptrs[s]);
            i32Const(g, plan.stream_stride[s]);
            op(g, OP_i32_add);
            lset(g, cur_ptrs[s]);
            g.s.vals[field_vals.start + fi] = fv;
        }
        return assembleSoaVal(g, f, plan, field_vals, id);
    }
    // PACKED_SPLIT_SUM
    let cases, cerr = g.types.variants(plan.elem_ty);
    if cerr != blot_direct_types::Error.none { return neverVal(), g.typeFailure(g.units[f.unit - 1], id); }
    let ci_loc = local32(g, f);
    lget(g, tags_base);
    lget(g, idx_local);
    op(g, OP_i32_add);
    op(g, OP_i32_load8_u); uleb(g, 0); uleb(g, 0);
    lset(g, ci_loc);
    let result, rerr = fresh(g, f, plan.elem_ty, id);
    if rerr != blot_direct_types::Error.none { return result, rerr; }
    let done = open(g, f, OP_block);
    for ci in 0..plan.variant_count {
        let vtag = g.types.variant_tags[cases.tags + ci];
        let pty = g.types.variant_payloads[cases.payloads + ci];
        let next = open(g, f, OP_block);
        lget(g, ci_loc);
        i32Const(g, ci as u32);
        op(g, OP_i32_ne);
        br(g, f, OP_br_if, next);
        let s = plan.variant_stream[ci];
        var payload = Val { pty, 0, 0 };
        if s >= 0 {
            let loaded, lerr = loadElement(g, f, cur_ptrs[s], 0, pty, id);
            if lerr != blot_direct_types::Error.none { return neverVal(), lerr; }
            lget(g, cur_ptrs[s]);
            i32Const(g, plan.stream_stride[s]);
            op(g, OP_i32_add);
            lset(g, cur_ptrs[s]);
            payload = loaded;
        }
        let wrapped, werr = wrapVariant(g, f, plan.elem_ty, vtag, payload, id);
        if werr != blot_direct_types::Error.none { return neverVal(), werr; }
        let cperr = copy(g, f, wrapped, result, id);
        if cperr != blot_direct_types::Error.none { return neverVal(), cperr; }
        br(g, f, OP_br, done);
        close(g, f);
    }
    op(g, OP_unreachable_);
    close(g, f);
    return result, blot_direct_types::Error.none;
}

// Helper: copy flat/bulk bytes from `src` (array/view/flat-packed) into `dst` (array/flat-packed).
fn emitFlatBulkExtend(g: Generator&, f: Fn&, dst: Val, src: Val, elem_ty: Ty, id: u32, selective: bool) -> Val, Error {
    let step, sterr = stride(g, f, elem_ty, id);
    if sterr != blot_direct_types::Error.none { return neverVal(), sterr; }
    let src_len, slerr = lengthOf(g, f, src, id);
    if slerr != blot_direct_types::Error.none { return neverVal(), slerr; }
    let dst_len, dlerr = lengthOf(g, f, dst, id);
    if dlerr != blot_direct_types::Error.none { return neverVal(), dlerr; }
    let next_len = local32(g, f);
    lget(g, dst_len);
    lget(g, src_len);
    op(g, OP_i32_add);
    ltee(g, next_len);
    lget(g, dst_len);
    op(g, OP_i32_lt_u);
    trap(g, f);
    let rt = g.runtime_();
    lget(g, w(g, dst, 0));
    lget(g, w(g, dst, 1));
    lget(g, next_len);
    i32Const(g, step);
    callf(g, rt.reserve);
    let non_empty = open(g, f, OP_block);
    lget(g, src_len);
    op(g, OP_i32_eqz);
    opIndex(g, OP_br_if, 0);
    let dst_entry = local32(g, f);
    lget(g, w(g, dst, 0));
    lget(g, w(g, dst, 1));
    callf(g, rt.check);
    lset(g, dst_entry);
    let dst_base = local32(g, f);
    lget(g, dst_entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
    lset(g, dst_base);
    let dst_ptr = emitOffsetAddress(g, f, dst_base, dst_len, step);
    var src_ptr: u32 = 0;
    if tagOf(g, src.ty) == blot_direct_types::Tag.view {
        let cv = findCheckedView(f, w(g, src, 0), w(g, src, 1), w(g, src, 2), w(g, src, 3));
        if cv >= 0 { src_ptr = f.checked_views[cv].base; }
        else { src_ptr = emitOffsetAddress(g, f, baseOf(g, f, src), w(g, src, 2), step); }
    } else {
        src_ptr = baseOf(g, f, src);
    }
    let copy_bytes = emitScaledBytes(g, f, src_len, step);
    if rt.has_fork {
        recordBeforeWrite(g, f, w(g, dst, 0), dst_entry, blot_direct_runtime::entry_length, 4);
    }
    lget(g, dst_ptr);
    lget(g, src_ptr);
    lget(g, copy_bytes);
    memoryCopyOp(g);
    lget(g, dst_entry);
    lget(g, next_len);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
    close(g, f);
    if selective { invalidateCheckedOwner(g, f, dst); } else { invalidateCheckedContainers(f); }
    return dst, blot_direct_types::Error.none;
}

// Handles `extend` whenever `dst` OR `src` is `Tag.packed`.
fn emitPackedExtend(g: Generator&, f: Fn&, dst: Val, src: Val, src_core_ty: TId, id: u32, selective: bool = false) -> Val, Error {
    let dst_is_packed = tagOf(g, dst.ty) == blot_direct_types::Tag.packed;
    let src_is_packed = tagOf(g, src.ty) == blot_direct_types::Tag.packed;
    let elem_ty, eerr = elementOf(g, f, dst.ty, id);
    if eerr != blot_direct_types::Error.none { return neverVal(), eerr; }
    let plan, perr = computePackedPlan(g, f, elem_ty, id);
    if perr != blot_direct_types::Error.none { return neverVal(), perr; }
    let holds = holdsContainer(g, elem_ty, 0);
    let rt = g.runtime_();

    // Case 1: PACKED_FLAT without inner containers -> bulk memory.copy in all directions!
    if plan.mode == PACKED_FLAT && !holds {
        return emitFlatBulkExtend(g, f, dst, src, elem_ty, id, selective);
    }

    // Case 2: packed-to-packed multi-stream without inner containers -> bulk per-stream memory.copy!
    if dst_is_packed && src_is_packed && plan.mode != PACKED_FLAT && !holds {
        let dst_h_entry, dst_h_base, dst_h_len = emitCheckPackedHeaderMutable(g, f, dst);
        let src_h_base, src_h_len = ensureCheckedArray(g, f, src);
        let next_h_len = local32(g, f);
        lget(g, dst_h_len);
        lget(g, src_h_len);
        op(g, OP_i32_add);
        ltee(g, next_h_len);
        lget(g, dst_h_len);
        op(g, OP_i32_lt_u);
        trap(g, f);
        let non_empty = open(g, f, OP_block);
        lget(g, src_h_len);
        op(g, OP_i32_eqz);
        opIndex(g, OP_br_if, 0);
        for s in 0..plan.stream_count {
            let step = plan.stream_stride[s];
            let ds_slot, ds_gen = emitLoadPackedSubHandle(g, f, dst_h_base, s);
            let ss_slot, ss_gen = emitLoadPackedSubHandle(g, f, src_h_base, s);
            let ds_entry = local32(g, f);
            let ss_entry = local32(g, f);
            let ds_len = local32(g, f);
            let ss_len = local32(g, f);
            let next_sub = local32(g, f);
            lget(g, ds_slot); lget(g, ds_gen); callf(g, rt.check); ltee(g, ds_entry);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length); lset(g, ds_len);
            lget(g, ss_slot); lget(g, ss_gen); callf(g, rt.check); ltee(g, ss_entry);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length); lset(g, ss_len);
            let sub_ne = open(g, f, OP_block);
            lget(g, ss_len);
            op(g, OP_i32_eqz);
            opIndex(g, OP_br_if, 0);
            lget(g, ds_len); lget(g, ss_len); op(g, OP_i32_add); ltee(g, next_sub);
            lget(g, ds_len); op(g, OP_i32_lt_u); trap(g, f);
            lget(g, ds_slot); lget(g, ds_gen); lget(g, next_sub); i32Const(g, step); callf(g, rt.reserve);
            let ds_base = local32(g, f);
            let ss_base = local32(g, f);
            lget(g, ds_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base); lset(g, ds_base);
            lget(g, ss_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base); lset(g, ss_base);
            let dst_ptr = emitOffsetAddress(g, f, ds_base, ds_len, step);
            let copy_bytes = emitScaledBytes(g, f, ss_len, step);
            if rt.has_fork {
                recordBeforeWrite(g, f, ds_slot, ds_entry, blot_direct_runtime::entry_length, 4);
            }
            lget(g, dst_ptr);
            lget(g, ss_base);
            lget(g, copy_bytes);
            memoryCopyOp(g);
            lget(g, ds_entry);
            lget(g, next_sub);
            op(g, OP_i32_store); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
            close(g, f);
        }
        if rt.has_fork {
            recordBeforeWrite(g, f, w(g, dst, 0), dst_h_entry, blot_direct_runtime::entry_length, 4);
        }
        lget(g, dst_h_entry);
        lget(g, next_h_len);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
        close(g, f);
        if selective { invalidateCheckedOwner(g, f, dst); } else { invalidateCheckedContainers(f); }
        return dst, blot_direct_types::Error.none;
    }

    // General element-by-element loop (handles cross-kind array <-> packed and nested containers).
    let src_len, slerr = lengthOf(g, f, src, id);
    if slerr != blot_direct_types::Error.none { return neverVal(), slerr; }
    if dst_is_packed {
        let _, rerr = emitPackedReserve(g, f, dst, src_len, id, selective);
        if rerr != blot_direct_types::Error.none { return neverVal(), rerr; }
    } else {
        let dst_len, dlerr = lengthOf(g, f, dst, id);
        if dlerr != blot_direct_types::Error.none { return neverVal(), dlerr; }
        let step, sterr = stride(g, f, elem_ty, id);
        if sterr != blot_direct_types::Error.none { return neverVal(), sterr; }
        let need = local32(g, f);
        lget(g, dst_len); lget(g, src_len); op(g, OP_i32_add); ltee(g, need);
        lget(g, dst_len); op(g, OP_i32_lt_u); trap(g, f);
        lget(g, w(g, dst, 0)); lget(g, w(g, dst, 1)); lget(g, need); i32Const(g, step); callf(g, rt.reserve);
    }

    if src_is_packed && plan.mode != PACKED_FLAT {
        let src_h_base, _ = ensureCheckedArray(g, f, src);
        var cur_ptrs: u32[16] = [0; 16];
        var tags_base: u32 = 0;
        if plan.mode == PACKED_SPLIT_SUM {
            tags_base = emitLoadPackedSubBase(g, f, src_h_base, 0);
            for s in 1..plan.stream_count { cur_ptrs[s] = emitLoadPackedSubBase(g, f, src_h_base, s); }
        } else {
            for s in 0..plan.stream_count { cur_ptrs[s] = emitLoadPackedSubBase(g, f, src_h_base, s); }
        }
        let idx = constLocal(g, f, 0);
        let exit = open(g, f, OP_block);
        let top = open(g, f, OP_loop);
        lget(g, idx); lget(g, src_len); op(g, OP_i32_ge_u); br(g, f, OP_br_if, exit);
        let decoded, derr = emitPackedDecodeStep(g, f, plan, cur_ptrs[..], tags_base, idx, id);
        if derr != blot_direct_types::Error.none { return neverVal(), derr; }
        var to_push = decoded;
        if holds {
            let copied, cerr = deepCopyValue(g, f, decoded, elem_ty, id, 0);
            if cerr != blot_direct_types::Error.none { return neverVal(), cerr; }
            to_push = copied;
        }
        if dst_is_packed {
            let _, perr2 = emitPackedPushVal(g, f, dst, to_push, id, selective);
            if perr2 != blot_direct_types::Error.none { return neverVal(), perr2; }
        } else {
            let _, perr2 = emitStoragePushVal(g, f, dst, to_push, id, selective);
            if perr2 != blot_direct_types::Error.none { return neverVal(), perr2; }
        }
        lget(g, idx); i32Const(g, 1); op(g, OP_i32_add); lset(g, idx);
        br(g, f, OP_br, top);
        close(g, f);
        close(g, f);
    } else {
        // Source is Tag.array, Tag.view, or PACKED_FLAT.
        let step, sterr = stride(g, f, elem_ty, id);
        if sterr != blot_direct_types::Error.none { return neverVal(), sterr; }
        let idx = constLocal(g, f, 0);
        let exit = open(g, f, OP_block);
        let top = open(g, f, OP_loop);
        lget(g, idx); lget(g, src_len); op(g, OP_i32_ge_u); br(g, f, OP_br_if, exit);
        var elem_val = neverVal();
        if src_is_packed {
            let src_base, _ = ensureCheckedArray(g, f, src);
            let src_addr = emitOffsetAddress(g, f, src_base, idx, step);
            let loaded, lerr = loadElement(g, f, src_addr, 0, elem_ty, id);
            if lerr != blot_direct_types::Error.none { return neverVal(), lerr; }
            elem_val = loaded;
        } else {
            let loaded, rerr = readElement(g, f, src, idx, id, src_core_ty, false);
            if rerr != blot_direct_types::Error.none { return neverVal(), rerr; }
            elem_val = loaded;
        }
        var to_push = elem_val;
        if holds {
            let copied, cerr = deepCopyValue(g, f, elem_val, elem_ty, id, 0);
            if cerr != blot_direct_types::Error.none { return neverVal(), cerr; }
            to_push = copied;
        }
        if dst_is_packed {
            let _, perr2 = emitPackedPushVal(g, f, dst, to_push, id, selective);
            if perr2 != blot_direct_types::Error.none { return neverVal(), perr2; }
        } else {
            let _, perr2 = emitStoragePushVal(g, f, dst, to_push, id, selective);
            if perr2 != blot_direct_types::Error.none { return neverVal(), perr2; }
        }
        lget(g, idx); i32Const(g, 1); op(g, OP_i32_add); lset(g, idx);
        br(g, f, OP_br, top);
        close(g, f);
        close(g, f);
    }
    if selective { invalidateCheckedOwner(g, f, dst); } else { invalidateCheckedContainers(f); }
    return dst, blot_direct_types::Error.none;
}

recursive fn emitPackedDeepCopy(g: Generator&, f: Fn&, value: Val, ty: Ty, id: u32, depth: i64) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, ty, id);
    if eerr != blot_direct_types::Error.none { return neverVal(), eerr; }
    let plan, perr = computePackedPlan(g, f, elem_ty, id);
    if perr != blot_direct_types::Error.none { return neverVal(), perr; }
    let holds = holdsContainer(g, elem_ty, 0);
    let rt = g.runtime_();
    noteAllocation(f);

    if plan.mode == PACKED_FLAT {
        let step, sterr = stride(g, f, elem_ty, id);
        if sterr != blot_direct_types::Error.none { return neverVal(), sterr; }
        if !holds {
            lget(g, w(g, value, 0));
            lget(g, w(g, value, 1));
            i32Const(g, step);
            i32Const(g, 0);
            callf(g, rt.copy);
            let handle, herr = pop(g, f, ty, id);
            if herr != blot_direct_types::Error.none { return handle, herr; }
            recordMutable(g, f, handle);
            return handle, blot_direct_types::Error.none;
        }
        let src_base, length = ensureCheckedArray(g, f, value);
        let dst, derr = emitPackedWithCapacity(g, f, ty, length, true, id);
        if derr != blot_direct_types::Error.none { return dst, derr; }
        let idx = constLocal(g, f, 0);
        let exit = open(g, f, OP_block);
        let top = open(g, f, OP_loop);
        lget(g, idx); lget(g, length); op(g, OP_i32_ge_u); br(g, f, OP_br_if, exit);
        let src_addr = emitOffsetAddress(g, f, src_base, idx, step);
        let elem_val, lerr = loadElement(g, f, src_addr, 0, elem_ty, id);
        if lerr != blot_direct_types::Error.none { return neverVal(), lerr; }
        let copied, cerr = deepCopyValue(g, f, elem_val, elem_ty, id, depth + 1);
        if cerr != blot_direct_types::Error.none { return neverVal(), cerr; }
        let _, perr2 = emitPackedPushVal(g, f, dst, copied, id, true);
        if perr2 != blot_direct_types::Error.none { return neverVal(), perr2; }
        lget(g, idx); i32Const(g, 1); op(g, OP_i32_add); lset(g, idx);
        br(g, f, OP_br, top);
        close(g, f);
        close(g, f);
        return dst, blot_direct_types::Error.none;
    }

    let src_h_base, length = ensureCheckedArray(g, f, value);
    if !holds {
        let header_bytes = (plan.stream_count as u32) * 8;
        let new_h_base = local32(g, f);
        i32Const(g, header_bytes);
        callf(g, rt.stack);
        lset(g, new_h_base);
        for s in 0..plan.stream_count {
            let sub_slot, sub_gen = emitLoadPackedSubHandle(g, f, src_h_base, s);
            let ns = local32(g, f);
            let ng = local32(g, f);
            lget(g, sub_slot);
            lget(g, sub_gen);
            i32Const(g, plan.stream_stride[s]);
            i32Const(g, 0);
            callf(g, rt.copy);
            lset(g, ng);
            lset(g, ns);
            let off = (s as u32) * 8;
            lget(g, new_h_base); lget(g, ns); op(g, OP_i32_store); uleb(g, 2); uleb(g, off);
            lget(g, new_h_base); lget(g, ng); op(g, OP_i32_store); uleb(g, 2); uleb(g, off + 4);
        }
        lget(g, new_h_base);
        lget(g, length);
        i32Const(g, header_bytes);
        callf(g, rt.open);
        let handle, herr = pop(g, f, ty, id);
        if herr != blot_direct_types::Error.none { return handle, herr; }
        recordMutable(g, f, handle);
        return handle, blot_direct_types::Error.none;
    }

    let dst, derr = emitPackedWithCapacity(g, f, ty, length, true, id);
    if derr != blot_direct_types::Error.none { return dst, derr; }
    var cur_ptrs: u32[16] = [0; 16];
    var tags_base: u32 = 0;
    if plan.mode == PACKED_SPLIT_SUM {
        tags_base = emitLoadPackedSubBase(g, f, src_h_base, 0);
        for s in 1..plan.stream_count { cur_ptrs[s] = emitLoadPackedSubBase(g, f, src_h_base, s); }
    } else {
        for s in 0..plan.stream_count { cur_ptrs[s] = emitLoadPackedSubBase(g, f, src_h_base, s); }
    }
    let idx = constLocal(g, f, 0);
    let exit = open(g, f, OP_block);
    let top = open(g, f, OP_loop);
    lget(g, idx); lget(g, length); op(g, OP_i32_ge_u); br(g, f, OP_br_if, exit);
    let decoded, decerr = emitPackedDecodeStep(g, f, plan, cur_ptrs[..], tags_base, idx, id);
    if decerr != blot_direct_types::Error.none { return neverVal(), decerr; }
    let copied, cerr = deepCopyValue(g, f, decoded, elem_ty, id, depth + 1);
    if cerr != blot_direct_types::Error.none { return neverVal(), cerr; }
    let _, perr2 = emitPackedPushVal(g, f, dst, copied, id, true);
    if perr2 != blot_direct_types::Error.none { return neverVal(), perr2; }
    lget(g, idx); i32Const(g, 1); op(g, OP_i32_add); lset(g, idx);
    br(g, f, OP_br, top);
    close(g, f);
    close(g, f);
    return dst, blot_direct_types::Error.none;
}

// Persists a packed container into deeply-immutable static const pool slots (mode = 2).
recursive fn emitPackedPersist(g: Generator&, f: Fn&, src_slot: u32, src_gen: u32, ty: Ty, id: u32, depth: i64) -> u32, u32, Error {
    let elem_ty, eerr = elementOf(g, f, ty, id);
    if eerr != blot_direct_types::Error.none { return 0, 0, eerr; }
    let plan, perr = computePackedPlan(g, f, elem_ty, id);
    if perr != blot_direct_types::Error.none { return 0, 0, perr; }
    let rt = g.runtime_();
    if plan.mode == PACKED_FLAT {
        let step, serr = stride(g, f, elem_ty, id);
        if serr != blot_direct_types::Error.none { return 0, 0, serr; }
        let p_slot = local32(g, f);
        let p_gen = local32(g, f);
        lget(g, src_slot);
        lget(g, src_gen);
        i32Const(g, step);
        i32Const(g, 2);
        callf(g, rt.persist);
        lset(g, p_gen);
        lset(g, p_slot);
        let elem_holds, eherr = g.contentsHoldMemory(elem_ty);
        if eherr != blot_direct_types::Error.none { return 0, 0, eherr; }
        if elem_holds {
            let aerr = persistArrayElements(g, f, p_slot, p_gen, elem_ty, step, id, depth + 1);
            if aerr != blot_direct_types::Error.none { return 0, 0, aerr; }
        }
        return p_slot, p_gen, blot_direct_types::Error.none;
    }
    let h_entry = local32(g, f);
    let h_base = local32(g, f);
    let h_len = local32(g, f);
    lget(g, src_slot); lget(g, src_gen); callf(g, rt.check); ltee(g, h_entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base); lset(g, h_base);
    lget(g, h_entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length); lset(g, h_len);
    let header_bytes = (plan.stream_count as u32) * 8;
    let p_h_base = local32(g, f);
    i32Const(g, header_bytes);
    callf(g, rt.alloc_persistent);
    lset(g, p_h_base);
    for s in 0..plan.stream_count {
        let sub_slot, sub_gen = emitLoadPackedSubHandle(g, f, h_base, s);
        let ps = local32(g, f);
        let pg = local32(g, f);
        lget(g, sub_slot);
        lget(g, sub_gen);
        i32Const(g, plan.stream_stride[s]);
        i32Const(g, 2);
        callf(g, rt.persist);
        lset(g, pg);
        lset(g, ps);
        let off = (s as u32) * 8;
        lget(g, p_h_base); lget(g, ps); op(g, OP_i32_store); uleb(g, 2); uleb(g, off);
        lget(g, p_h_base); lget(g, pg); op(g, OP_i32_store); uleb(g, 2); uleb(g, off + 4);
        let sholds, sherr = g.contentsHoldMemory(plan.stream_ty[s]);
        if sherr != blot_direct_types::Error.none { return 0, 0, sherr; }
        if sholds {
            let aerr = persistArrayElements(g, f, ps, pg, plan.stream_ty[s], plan.stream_stride[s], id, depth + 1);
            if aerr != blot_direct_types::Error.none { return 0, 0, aerr; }
        }
    }
    let p_slot = local32(g, f);
    let p_gen = local32(g, f);
    lget(g, p_h_base);
    lget(g, h_len);
    i32Const(g, header_bytes | blot_direct_runtime::static_pool_flag);
    callf(g, rt.open_persistent);
    lset(g, p_gen);
    lset(g, p_slot);
    return p_slot, p_gen, blot_direct_types::Error.none;
}

// ---- Touched-column analysis for PACKED_SOA `for p in packed:` loops ----

// Checks whether every reference to `binding` inside `node_id` is a direct
// field projection (no whole-value uses). Populates bitmask of accessed fields.
recursive fn analyzeSoaBodyUses(
    g: Generator&,
    m: const Module&,
    node_id: u32,
    binding: u32,
    plan: const PackedPlan&,
    used_fields: u32&,
    budget: i64&,
) -> bool {
    if node_id == 0 { return true; }
    if budget <= 0 { return false; }
    budget -= 1;
    let n = m.node(node_id);
    match n.tag {
        reference => {
            if localRef(m, node_id) == binding { return false; }
            return true;
        },
        project => {
            if localRef(m, n.a) == binding {
                if !plan.soa_is_record { return false; }
                let proj = m.projection(n.b);
                if m.projectionVariants(n.b).len != 0 { return false; }
                let sp = m.fieldSpelling(proj.field);
                if !sp.present { return false; }
                let fname = g.types.fieldName(sp.value);
                let pos = g.types.findField(plan.soa_inner_ty, fname);
                if pos < 0 || pos >= 16 { return false; }
                used_fields |= (1 as u32) << (pos as u32);
                return true;
            }
            return analyzeSoaBodyUses(g, m, n.a, binding, plan, used_fields, budget);
        },
        constant, constructor_function, associated, primitive_function, operation_value, type_constructor, break_ => { return true; },
        bind => { return analyzeSoaBodyUses(g, m, n.b, binding, plan, used_fields, budget); },
        pattern_bind => {
            return analyzeSoaBodyUses(g, m, n.b, binding, plan, used_fields, budget) &&
                   analyzeSoaBodyUses(g, m, n.c, binding, plan, used_fields, budget);
        },
        suite, block_, product, record, array, array_op, storage, call => {
            for ch in m.children(node_id) {
                if !analyzeSoaBodyUses(g, m, ch, binding, plan, used_fields, budget) { return false; }
            }
            return true;
        },
        scalar, logical, apply => {
            return analyzeSoaBodyUses(g, m, n.a, binding, plan, used_fields, budget) &&
                   analyzeSoaBodyUses(g, m, n.b, binding, plan, used_fields, budget);
        },
        if_value, if_stmt => {
            return analyzeSoaBodyUses(g, m, n.a, binding, plan, used_fields, budget) &&
                   analyzeSoaBodyUses(g, m, n.b, binding, plan, used_fields, budget) &&
                   analyzeSoaBodyUses(g, m, n.c, binding, plan, used_fields, budget);
        },
        construct => { return analyzeSoaBodyUses(g, m, n.b, binding, plan, used_fields, budget); },
        return_ => { return analyzeSoaBodyUses(g, m, n.a, binding, plan, used_fields, budget); },
        match_ => {
            for inp in m.matchInputs(node_id) {
                if !analyzeSoaBodyUses(g, m, inp, binding, plan, used_fields, budget) { return false; }
            }
            for arm in m.matchArms(node_id) {
                if !analyzeSoaBodyUses(g, m, arm.guard_, binding, plan, used_fields, budget) { return false; }
                if !analyzeSoaBodyUses(g, m, arm.body, binding, plan, used_fields, budget) { return false; }
            }
            return true;
        },
        loop_ => {
            let linfo = m.loopInfo(node_id);
            return analyzeSoaBodyUses(g, m, linfo.first, binding, plan, used_fields, budget) &&
                   analyzeSoaBodyUses(g, m, linfo.end, binding, plan, used_fields, budget) &&
                   analyzeSoaBodyUses(g, m, linfo.body, binding, plan, used_fields, budget);
        },
        update => {
            let uinfo = m.updateInfo(node_id);
            if localRef(m, uinfo.root) == binding { return false; }
            if !analyzeSoaBodyUses(g, m, uinfo.root, binding, plan, used_fields, budget) { return false; }
            for sel in m.updateSelectors(node_id) {
                if sel.kind == blot_check_core::UpdateKind.index && !analyzeSoaBodyUses(g, m, sel.index, binding, plan, used_fields, budget) {
                    return false;
                }
            }
            return analyzeSoaBodyUses(g, m, uinfo.value, binding, plan, used_fields, budget);
        },
        _ => { return false; },
    }
}

// Intercepts `p.field` inside a touched-column SoA `for p in packed:` loop.
fn tryProjectSoaLoopField(g: Generator&, f: const Fn&, id: u32) -> Val, bool, Error {
    if soa_loop_depth == 0 { return neverVal(), false, blot_direct_types::Error.none; }
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let b = localRef(m, n.a);
    if b == 0 { return neverVal(), false, blot_direct_types::Error.none; }
    var d = soa_loop_depth - 1;
    while d >= 0 {
        if soa_loop_binding[d] == b {
            if !soa_loop_is_record[d] { return neverVal(), false, blot_direct_types::Error.none; }
            let proj = m.projection(n.b);
            if m.projectionVariants(n.b).len != 0 { return neverVal(), false, blot_direct_types::Error.none; }
            let sp = m.fieldSpelling(proj.field);
            if !sp.present { return neverVal(), false, blot_direct_types::Error.none; }
            let fname = g.types.fieldName(sp.value);
            let pos = g.types.findField(soa_loop_inner_ty[d], fname);
            if pos < 0 || pos >= 16 { return neverVal(), false, blot_direct_types::Error.none; }
            let slot = d * 16 + pos;
            if !soa_loop_field_loaded[slot] { return neverVal(), false, blot_direct_types::Error.none; }
            return Val { soa_loop_field_ty[slot], soa_loop_field_start[slot], soa_loop_field_len[slot] }, true, blot_direct_types::Error.none;
        }
        d -= 1;
    }
    return neverVal(), false, blot_direct_types::Error.none;
}

// Checks whether a destructuring pattern directly unpacks `plan`'s SoA record/tuple
// (with optional single-ctor nominal wrapper) and returns per-field sub-patterns.
fn matchSoaDestructurePattern(
    g: Generator&,
    m: const Module&,
    pat_id: u32,
    plan: const PackedPlan&,
    field_pats: u32[16]&,
    used_fields: u32&,
) -> bool {
    if pat_id == 0 { return false; }
    for i in 0..16 { field_pats[i] = 0; }
    used_fields = 0;
    var inner_pat = pat_id;
    if plan.soa_is_nominal {
        let pn = m.pattern(pat_id);
        if pn.tag != blot_check_core::PatternTag.constructor { return false; }
        if pn.b == 0 { return false; }
        inner_pat = pn.b;
    }
    let ip = m.pattern(inner_pat);
    if !plan.soa_is_record {
        if ip.tag != blot_check_core::PatternTag.product { return false; }
        let children = m.patternChildren(inner_pat);
        if children.len != plan.soa_field_count { return false; }
        for ch, idx in children {
            if m.pattern(ch).tag != blot_check_core::PatternTag.wildcard {
                field_pats[idx] = ch;
                used_fields |= (1 as u32) << (idx as u32);
            }
        }
        return true;
    }
    // Record destructuring (`PatternTag.record_payload` or `PatternTag.product` with record pattern type).
    if ip.tag == blot_check_core::PatternTag.record_payload {
        let rec_ty_node = m.types.node(ip.ty);
        if rec_ty_node.tag != blot_check_types::Tag.record { return false; }
        let inner_prod = ip.b;
        let children = m.patternChildren(inner_prod);
        if children.len != (rec_ty_node.b as i64) { return false; }
        for ch, idx in children {
            if m.pattern(ch).tag == blot_check_core::PatternTag.wildcard { continue; }
            let rf = m.types.recordField(rec_ty_node, idx);
            let sp = m.fieldSpelling(rf.name);
            if !sp.present { return false; }
            let fname = g.types.fieldName(sp.value);
            let pos = g.types.findField(plan.soa_inner_ty, fname);
            if pos < 0 || pos >= 16 { return false; }
            field_pats[pos] = ch;
            used_fields |= (1 as u32) << (pos as u32);
        }
        return true;
    }
    if ip.tag == blot_check_core::PatternTag.product {
        let rec_ty_node = m.types.node(ip.ty);
        if rec_ty_node.tag != blot_check_types::Tag.record { return false; }
        let children = m.patternChildren(inner_pat);
        if children.len != (rec_ty_node.b as i64) { return false; }
        for ch, idx in children {
            if m.pattern(ch).tag == blot_check_core::PatternTag.wildcard { continue; }
            let rf = m.types.recordField(rec_ty_node, idx);
            let sp = m.fieldSpelling(rf.name);
            if !sp.present { return false; }
            let fname = g.types.fieldName(sp.value);
            let pos = g.types.findField(plan.soa_inner_ty, fname);
            if pos < 0 || pos >= 16 { return false; }
            field_pats[pos] = ch;
            used_fields |= (1 as u32) << (pos as u32);
        }
        return true;
    }
    return false;
}

// ---- Fused `for ev in packed:` + `case ev of ...` analysis & dispatch ----

// Verifies that `node_id` does not reference `binding` anywhere.
recursive fn bodyDoesNotMention(m: const Module&, node_id: u32, binding: u32, budget: i64&) -> bool {
    if node_id == 0 { return true; }
    if budget <= 0 { return false; }
    budget -= 1;
    let n = m.node(node_id);
    match n.tag {
        reference => { return localRef(m, node_id) != binding; },
        constant, constructor_function, associated, primitive_function, operation_value, type_constructor, break_ => { return true; },
        project, return_ => { return bodyDoesNotMention(m, n.a, binding, budget); },
        bind, construct => { return bodyDoesNotMention(m, n.b, binding, budget); },
        pattern_bind => { return bodyDoesNotMention(m, n.b, binding, budget) && bodyDoesNotMention(m, n.c, binding, budget); },
        scalar, logical, apply => { return bodyDoesNotMention(m, n.a, binding, budget) && bodyDoesNotMention(m, n.b, binding, budget); },
        if_value, if_stmt => {
            return bodyDoesNotMention(m, n.a, binding, budget) &&
                   bodyDoesNotMention(m, n.b, binding, budget) &&
                   bodyDoesNotMention(m, n.c, binding, budget);
        },
        suite, block_, product, record, array, array_op, storage, call => {
            for ch in m.children(node_id) { if !bodyDoesNotMention(m, ch, binding, budget) { return false; } }
            return true;
        },
        match_ => {
            for inp in m.matchInputs(node_id) { if !bodyDoesNotMention(m, inp, binding, budget) { return false; } }
            for arm in m.matchArms(node_id) {
                if !bodyDoesNotMention(m, arm.guard_, binding, budget) { return false; }
                if !bodyDoesNotMention(m, arm.body, binding, budget) { return false; }
            }
            return true;
        },
        loop_ => {
            let linfo = m.loopInfo(node_id);
            return bodyDoesNotMention(m, linfo.first, binding, budget) &&
                   bodyDoesNotMention(m, linfo.end, binding, budget) &&
                   bodyDoesNotMention(m, linfo.body, binding, budget);
        },
        update => {
            let uinfo = m.updateInfo(node_id);
            if !bodyDoesNotMention(m, uinfo.root, binding, budget) { return false; }
            for sel in m.updateSelectors(node_id) {
                if sel.kind == blot_check_core::UpdateKind.index && !bodyDoesNotMention(m, sel.index, binding, budget) { return false; }
            }
            return bodyDoesNotMention(m, uinfo.value, binding, budget);
        },
        _ => { return false; },
    }
}

// Recursively verifies a `Tag.match_` (or binary `caseLevel` chain of `Tag.match_`s)
// on `binding` for fused split-stream dispatch, computing `needed_mask` (bits for
// variants whose payloads are bound) and ensuring every variant's payload is loaded at most once.
recursive fn analyzeSplitSumMatchChain(
    g: Generator&,
    m: const Module&,
    match_id: u32,
    binding: u32,
    elem_ty: Ty,
    cases: blot_direct_types::Variants,
    needed_mask: u64&,
    seen_ctor_mask: u64&,
    depth: i64,
) -> bool {
    if depth > 64 || match_id == 0 { return false; }
    let n = m.node(match_id);
    if n.tag != blot_check_core::Tag.match_ { return false; }
    let inputs = m.matchInputs(match_id);
    if inputs.len != 1 || localRef(m, inputs[0]) != binding { return false; }
    let arms = m.matchArms(match_id);
    var saw_wild = false;
    for arm, arm_idx in arms {
        if arm.guard_ != 0 { return false; }
        let rows = m.armRows(arm);
        if rows.len != 1 { return false; }
        let pats = m.rowPatterns(rows[0]);
        if pats.len != 1 { return false; }
        let pat = m.pattern(pats[0]);
        if pat.tag == blot_check_core::PatternTag.constructor {
            if saw_wild { return false; }
            let ctag = m.constructor(pat.a).tag;
            var ci: i64 = -1;
            for pos in 0..(cases.len as i64) {
                if g.types.variant_tags[cases.tags + pos] == ctag { ci = pos; break; }
            }
            if ci < 0 || ci >= 64 { return false; }
            let bit = (1 as u64) << (ci as u64);
            if (seen_ctor_mask & bit) != 0 { return false; }
            seen_ctor_mask |= bit;
            if pat.b != 0 && m.pattern(pat.b).tag != blot_check_core::PatternTag.wildcard {
                needed_mask |= bit;
            }
            var budget: i64 = 512;
            if !bodyDoesNotMention(m, arm.body, binding, budget) { return false; }
        } else if pat.tag == blot_check_core::PatternTag.wildcard || pat.tag == blot_check_core::PatternTag.bind {
            saw_wild = true;
            // For a `caseLevel` binary chain, the fallback arm may bind `binding` to an alias
            // or directly contain a nested `Tag.match_` on `binding`.
            var next_binding = binding;
            if pat.tag == blot_check_core::PatternTag.bind { next_binding = pat.a; }
            let sub = unwrapSingleMatchNode(m, arm.body);
            if sub != 0 && m.matchInputs(sub).len == 1 && localRef(m, m.matchInputs(sub)[0]) == next_binding {
                if !analyzeSplitSumMatchChain(g, m, sub, next_binding, elem_ty, cases, needed_mask, seen_ctor_mask, depth + 1) {
                    return false;
                }
            } else {
                if pat.tag == blot_check_core::PatternTag.bind { return false; }
                var budget: i64 = 512;
                if !bodyDoesNotMention(m, arm.body, binding, budget) { return false; }
            }
        } else {
            return false;
        }
    }
    return true;
}

fn unwrapSingleMatchNode(m: const Module&, body_id: u32) -> u32 {
    if body_id == 0 { return 0; }
    var cur = body_id;
    for _ in 0..4 {
        let n = m.node(cur);
        if n.tag == blot_check_core::Tag.match_ { return cur; }
        if n.tag == blot_check_core::Tag.suite || n.tag == blot_check_core::Tag.block_ {
            let ch = m.children(cur);
            if ch.len == 1 { cur = ch[0]; continue; }
            return 0;
        }
        return 0;
    }
    return 0;
}

recursive fn packedPatternIrrefutable(m: const Module&, pat_id: u32) -> bool {
    if pat_id == 0 { return true; }
    let p = m.pattern(pat_id);
    match p.tag {
        wildcard, bind => { return true; },
        product => {
            for ch in m.patternChildren(pat_id) {
                if !packedPatternIrrefutable(m, ch) { return false; }
            }
            return true;
        },
        record_payload => { return packedPatternIrrefutable(m, p.b); },
        _ => { return false; },
    }
}

// Intercepts `Tag.match_` on the active fused split-stream loop variable.
recursive fn tryEmitSplitSumMatch(g: Generator&, f: Fn&, id: u32) -> Val, bool, Error {
    if split_sum_depth == 0 { return neverVal(), false, blot_direct_types::Error.none; }
    let m .= g.units[f.unit - 1];
    let inputs = m.matchInputs(id);
    if inputs.len != 1 { return neverVal(), false, blot_direct_types::Error.none; }
    let in_b = localRef(m, inputs[0]);
    if in_b == 0 { return neverVal(), false, blot_direct_types::Error.none; }
    var d = split_sum_depth - 1;
    while d >= 0 {
        if split_sum_binding[d] == in_b { break; }
        d -= 1;
    }
    if d < 0 { return neverVal(), false, blot_direct_types::Error.none; }

    let elem_ty = split_sum_ty[d];
    let ci_loc = split_sum_ci_loc[d];
    let cases, cerr = g.types.variants(elem_ty);
    if cerr != blot_direct_types::Error.none { return neverVal(), false, g.typeFailure(m, id); }
    let info = m.matchInfo(id);
    let merges_len = m.branchMerges(id).len;
    let arms_len = m.matchArms(id).len;
    let result = g.newSlot();
    let merged = newSlots(g, merges_len);
    var falls = false;
    let done = open(g, f, OP_block);

    // Dense `br_table` on `ci_loc` when >= 3 arms and no branchMerges.
    var use_br_table = arms_len >= 3 && arms_len <= 64 && merges_len == 0 && (cases.len as i64) <= 64;
    var tbl_arm: i64[64] = [-1; 64];
    var tbl_wild: i64 = -1;
    if use_br_table {
        for ai in 0..arms_len {
            let pm .= g.units[f.unit - 1];
            let arm = pm.matchArms(id)[ai];
            let pat = pm.pattern(pm.rowPatterns(pm.armRows(arm)[0])[0]);
            if pat.tag == blot_check_core::PatternTag.wildcard {
                tbl_wild = ai;
                break;
            } else if pat.tag == blot_check_core::PatternTag.constructor {
                let ctag = pm.constructor(pat.a).tag;
                var ci: i64 = -1;
                for pos in 0..(cases.len as i64) {
                    if g.types.variant_tags[cases.tags + pos] == ctag { ci = pos; break; }
                }
                if ci < 0 || ci >= 64 || tbl_arm[ci] >= 0 { use_br_table = false; break; }
                if pat.b != 0 && !packedPatternIrrefutable(pm, pat.b) { use_br_table = false; break; }
                tbl_arm[ci] = ai;
            } else {
                use_br_table = false;
                break;
            }
        }
    }

    if use_br_table {
        let num_arms = if tbl_wild >= 0 { tbl_wild + 1 } else { arms_len };
        let default_rel: u32 = if tbl_wild >= 0 { tbl_wild as u32 } else { num_arms as u32 };
        let open_blocks = if tbl_wild >= 0 { num_arms } else { num_arms + 1 };
        for _ in 0..open_blocks { let _ = open(g, f, OP_block); }
        lget(g, ci_loc);
        op(g, OP_br_table);
        uleb(g, cases.len);
        for ci in 0..(cases.len as i64) {
            if tbl_arm[ci] >= 0 { uleb(g, tbl_arm[ci] as u32); } else { uleb(g, default_rel); }
        }
        uleb(g, default_rel);
        for ai in 0..num_arms {
            close(g, f);
            var pat_tag = blot_check_core::PatternTag.wildcard;
            var ctor_tag: u32 = 0;
            var subpat: u32 = 0;
            var body_id: u32 = 0;
            {
                let pm .= g.units[f.unit - 1];
                let arm = pm.matchArms(id)[ai];
                body_id = arm.body;
                let pat = pm.pattern(pm.rowPatterns(pm.armRows(arm)[0])[0]);
                pat_tag = pat.tag;
                if pat_tag == blot_check_core::PatternTag.constructor {
                    ctor_tag = pm.constructor(pat.a).tag;
                    subpat = pat.b;
                }
            }
            if pat_tag == blot_check_core::PatternTag.constructor && subpat != 0 && g.units[f.unit - 1].pattern(subpat).tag != blot_check_core::PatternTag.wildcard {
                let ci, cierr = variantPosition(g, f, cases, ctor_tag, id);
                if cierr != blot_direct_types::Error.none { return neverVal(), false, cierr; }
                let s = split_sum_variant_stream[d * 64 + ci];
                let pty = g.types.variant_payloads[cases.payloads + ci];
                var payload_val = Val { pty, 0, 0 };
                if s >= 0 {
                    let cur_ptr = split_sum_cur_ptrs[d * 16 + s];
                    let step = split_sum_stream_stride[d * 16 + s];
                    let loaded, lerr = loadElement(g, f, cur_ptr, 0, pty, id);
                    if lerr != blot_direct_types::Error.none { return neverVal(), false, lerr; }
                    lget(g, cur_ptr);
                    i32Const(g, step);
                    op(g, OP_i32_add);
                    lset(g, cur_ptr);
                    payload_val = loaded;
                }
                let terr = test_(g, f, subpat, payload_val, false, 0, id);
                if terr != blot_direct_types::Error.none { return neverVal(), false, terr; }
            }
            let body, berr = stmt(g, f, body_id);
            if berr != blot_direct_types::Error.none { return body, false, berr; }
            if body.ty != blot_direct_types::never {
                falls = true;
                if !info.statement {
                    let derr = deliver(g, f, body, result, id);
                    if derr != blot_direct_types::Error.none { return neverVal(), false, derr; }
                }
            }
            br(g, f, OP_br, done);
        }
        if tbl_wild < 0 {
            close(g, f);
            op(g, OP_unreachable_);
        }
        close(g, f);
        if !falls { return neverVal(), true, blot_direct_types::Error.none; }
        if info.statement { return unitVal(), true, blot_direct_types::Error.none; }
        if g.s.slots[result].present { return g.s.slots[result].value, true, blot_direct_types::Error.none; }
        return neverVal(), true, blot_direct_types::Error.none;
    }

    // Sequential arm dispatch (also handles `caseLevel` binary chains with branchMerges!).
    for arm_index in 0..arms_len {
        let next = open(g, f, OP_block);
        var pat_tag = blot_check_core::PatternTag.wildcard;
        var pat_bind_id: u32 = 0;
        var ctor_tag: u32 = 0;
        var subpat: u32 = 0;
        var body_id: u32 = 0;
        {
            let pm .= g.units[f.unit - 1];
            let arm = pm.matchArms(id)[arm_index];
            body_id = arm.body;
            let pat = pm.pattern(pm.rowPatterns(pm.armRows(arm)[0])[0]);
            pat_tag = pat.tag;
            if pat_tag == blot_check_core::PatternTag.bind { pat_bind_id = pat.a; }
            if pat_tag == blot_check_core::PatternTag.constructor {
                ctor_tag = pm.constructor(pat.a).tag;
                subpat = pat.b;
            }
        }
        var saved_bind = split_sum_binding[d];
        if pat_tag == blot_check_core::PatternTag.constructor {
            let ci, cierr = variantPosition(g, f, cases, ctor_tag, id);
            if cierr != blot_direct_types::Error.none { return neverVal(), false, cierr; }
            lget(g, ci_loc);
            i32Const(g, ci as u32);
            op(g, OP_i32_ne);
            failIf(g, f, true, next);
            if subpat != 0 && g.units[f.unit - 1].pattern(subpat).tag != blot_check_core::PatternTag.wildcard {
                let s = split_sum_variant_stream[d * 64 + ci];
                let pty = g.types.variant_payloads[cases.payloads + ci];
                var payload_val = Val { pty, 0, 0 };
                if s >= 0 {
                    let cur_ptr = split_sum_cur_ptrs[d * 16 + s];
                    let step = split_sum_stream_stride[d * 16 + s];
                    let loaded, lerr = loadElement(g, f, cur_ptr, 0, pty, id);
                    if lerr != blot_direct_types::Error.none { return neverVal(), false, lerr; }
                    lget(g, cur_ptr);
                    i32Const(g, step);
                    op(g, OP_i32_add);
                    lset(g, cur_ptr);
                    payload_val = loaded;
                }
                let terr = test_(g, f, subpat, payload_val, true, next, id);
                if terr != blot_direct_types::Error.none { return neverVal(), false, terr; }
            }
        } else if pat_tag == blot_check_core::PatternTag.bind {
            split_sum_binding[d] = pat_bind_id;
        }
        let body, berr = stmt(g, f, body_id);
        split_sum_binding[d] = saved_bind;
        if berr != blot_direct_types::Error.none { return body, false, berr; }
        if body.ty != blot_direct_types::never {
            falls = true;
            if !info.statement {
                let derr = deliver(g, f, body, result, id);
                if derr != blot_direct_types::Error.none { return neverVal(), false, derr; }
            }
            if merges_len != 0 && arm_index < 2 {
                for at in 0..merges_len {
                    let merge = g.units[f.unit - 1].branchMerges(id)[at];
                    let binding = if arm_index == 0 { merge.then_binding } else { merge.else_binding };
                    let value, present = bindGet(g, f, binding);
                    if present {
                        let derr = deliver(g, f, value, merged + (at as u32), id);
                        if derr != blot_direct_types::Error.none { return neverVal(), false, derr; }
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
            if ok1 { blot_support_zigmap::put(g.s.map_pool, f.with_cells, merge.result, ct1); }
            else {
                let ct2, ok2 = withCellType(g, f, merge.else_binding);
                if ok2 { blot_support_zigmap::put(g.s.map_pool, f.with_cells, merge.result, ct2); }
            }
        }
    }
    if !falls { return neverVal(), true, blot_direct_types::Error.none; }
    if info.statement { return unitVal(), true, blot_direct_types::Error.none; }
    if g.s.slots[result].present { return g.s.slots[result].value, true, blot_direct_types::Error.none; }
    return neverVal(), true, blot_direct_types::Error.none;
}

// ---- Packed `for` loop emitter (Flat cursor / SoA columns / Split-stream sums) ----

recursive fn emitPackedLoopCore(
    g: Generator&,
    f: Fn&,
    id: u32,
    info: blot_check_core::LoopInfo,
    iteration: Vals,
    outgoing: Vals,
    slots: Words,
    index: u32,
    end_loc: u32,
    source: Val,
) -> Error {
    let m .= g.units[f.unit - 1];
    let carries = m.loopCarries(id);
    let elem_ty, eerr = elementOf(g, f, source.ty, id);
    if eerr != blot_direct_types::Error.none { return eerr; }
    let plan, perr = computePackedPlan(g, f, elem_ty, id);
    if perr != blot_direct_types::Error.none { return perr; }

    // Hoist bases/cursors ONCE before OP_loop!
    let base, _ = ensureCheckedArray(g, f, source);
    var flat_cur: u32 = 0;
    var flat_step: u32 = 0;
    var cur_ptrs: u32[16] = [0; 16];
    var tags_base: u32 = 0;

    // Mode-specific static analysis before emitting the loop.
    var soa_virtual = false;
    var soa_destruct = false;
    var soa_used_fields: u32 = 0;
    var soa_bind_id: u32 = 0;
    var soa_field_pats: u32[16] = [0; 16];

    var split_fused = false;
    var split_bind_id: u32 = 0;
    var split_needed_mask: u64 = 0;

    if plan.mode == PACKED_FLAT {
        let st, sterr = stride(g, f, elem_ty, id);
        if sterr != blot_direct_types::Error.none { return sterr; }
        flat_step = st;
        flat_cur = local32(g, f);
        lget(g, base);
        lset(g, flat_cur);
    } else if plan.mode == PACKED_SOA {
        if info.pattern != 0 {
            let pnode = m.pattern(info.pattern);
            if pnode.tag == blot_check_core::PatternTag.bind && plan.soa_is_record && soa_loop_depth < 8 {
                var budget: i64 = 1024;
                var uf: u32 = 0;
                if analyzeSoaBodyUses(g, m, info.body, pnode.a, plan, uf, budget) {
                    soa_virtual = true;
                    soa_bind_id = pnode.a;
                    soa_used_fields = uf;
                }
            } else if matchSoaDestructurePattern(g, m, info.pattern, plan, soa_field_pats, soa_used_fields) {
                soa_destruct = true;
            }
        }
        if soa_virtual || soa_destruct {
            for fi in 0..plan.soa_field_count {
                let s = plan.soa_field_stream[fi];
                if s >= 0 && ((soa_used_fields >> (fi as u32)) & 1) != 0 {
                    cur_ptrs[s] = emitLoadPackedSubBase(g, f, base, s);
                }
            }
        } else {
            for s in 0..plan.stream_count {
                cur_ptrs[s] = emitLoadPackedSubBase(g, f, base, s);
            }
        }
    } else {
        // PACKED_SPLIT_SUM
        tags_base = emitLoadPackedSubBase(g, f, base, 0);
        if info.pattern != 0 && m.pattern(info.pattern).tag == blot_check_core::PatternTag.bind && split_sum_depth < 4 && plan.variant_count <= 64 {
            let ev_b = m.pattern(info.pattern).a;
            let match_root = unwrapSingleMatchNode(m, info.body);
            if match_root != 0 {
                let cases, cerr = g.types.variants(elem_ty);
                if cerr == blot_direct_types::Error.none {
                    var nmask: u64 = 0;
                    var smask: u64 = 0;
                    if analyzeSplitSumMatchChain(g, m, match_root, ev_b, elem_ty, cases, nmask, smask, 0) {
                        split_fused = true;
                        split_bind_id = ev_b;
                        split_needed_mask = nmask;
                    }
                }
            }
        }
        if split_fused {
            for ci in 0..plan.variant_count {
                let s = plan.variant_stream[ci];
                if s >= 0 && ((split_needed_mask >> (ci as u64)) & 1) != 0 {
                    cur_ptrs[s] = emitLoadPackedSubBase(g, f, base, s);
                }
            }
        } else {
            for s in 1..plan.stream_count {
                cur_ptrs[s] = emitLoadPackedSubBase(g, f, base, s);
            }
        }
    }

    // Check per-iteration scratch release eligibility (same rules as emitLoopCore).
    var release = true;
    var boxed_carries = false;
    var guards = Words { 0, 0 };
    {
        let s_state .= g.s;
        let scratch_mark = s_state.scratch.len;
        for at in 0..carries.len {
            if g.s.words[slots.start + at] != 0 { boxed_carries = true; continue; }
            let value = g.s.vals[iteration.start + at];
            let safe, oerr = ownerSlots(g, value.ty, value.start);
            if oerr != blot_direct_types::Error.none { s_state.scratch.resize(scratch_mark); return oerr; }
            if !safe { release = false; }
        }
        if release {
            var no_alloc_budget: i64 = 512;
            if bodyNoAlloc(g, f, m, info.body, no_alloc_budget) { release = false; }
        }
        guards = Words { g.s.words.len as u32, (s_state.scratch.len - scratch_mark) as u32 };
        for at in scratch_mark..s_state.scratch.len { let slot = s_state.scratch[at]; g.s.words.push(slot); }
        s_state.scratch.resize(scratch_mark);
    }

    let exit = open(g, f, OP_block);
    let top = open(g, f, OP_loop);
    f.checked_elems_len = 0;
    lget(g, index);
    lget(g, end_loc);
    op(g, OP_i32_ge_u);
    let done_if = open(g, f, OP_if_);
    let assigned = assign(g, f, iteration, outgoing, id);
    if assigned != blot_direct_types::Error.none { return assigned; }
    br(g, f, OP_br, exit);
    close(g, f);

    let current = local32(g, f);
    lget(g, index);
    lset(g, current);
    lget(g, index);
    i32Const(g, 1);
    op(g, OP_i32_add);
    lset(g, index);

    // Emit per-iteration scratch marks before decoding/running the body.
    var release_owner: u32 = 0;
    var release_stack: u32 = 0;
    var saved_escape: u32 = 0;
    var unchanged: u32 = 0xffffffff;
    if release {
        release_owner = local32(g, f);
        release_stack = local32(g, f);
        saved_escape = local32(g, f);
        if boxed_carries { unchanged = local32(g, f); }
        markInto(g, g.s.code, release_owner, release_stack);
        gget(g, g.runtime_().escape_min_slot);
        lset(g, saved_escape);
        i32Const(g, 0xffffffff);
        gset(g, g.runtime_().escape_min_slot);
    }

    // Load element / push virtual state according to mode.
    var pushed_soa_frame = false;
    var pushed_split_frame = false;
    if plan.mode == PACKED_FLAT {
        let item, lerr = loadElement(g, f, flat_cur, 0, elem_ty, id);
        if lerr != blot_direct_types::Error.none { return lerr; }
        lget(g, flat_cur);
        i32Const(g, flat_step);
        op(g, OP_i32_add);
        lset(g, flat_cur);
        if info.pattern != 0 {
            let terr = test_(g, f, info.pattern, item, false, 0, id);
            if terr != blot_direct_types::Error.none { return terr; }
        }
    } else if plan.mode == PACKED_SOA {
        if soa_virtual {
            let d = soa_loop_depth;
            soa_loop_binding[d] = soa_bind_id;
            soa_loop_ty[d] = elem_ty;
            soa_loop_inner_ty[d] = plan.soa_inner_ty;
            soa_loop_is_record[d] = plan.soa_is_record;
            for fi in 0..16 { soa_loop_field_loaded[d * 16 + fi] = false; }
            for fi in 0..plan.soa_field_count {
                if ((soa_used_fields >> (fi as u32)) & 1) == 0 { continue; }
                let s = plan.soa_field_stream[fi];
                let fty = plan.soa_field_ty[fi];
                var fv = Val { fty, 0, 0 };
                if s >= 0 {
                    let loaded, lerr = loadElement(g, f, cur_ptrs[s], 0, fty, id);
                    if lerr != blot_direct_types::Error.none { return lerr; }
                    lget(g, cur_ptrs[s]);
                    i32Const(g, plan.stream_stride[s]);
                    op(g, OP_i32_add);
                    lset(g, cur_ptrs[s]);
                    fv = loaded;
                }
                let slot = d * 16 + fi;
                soa_loop_field_loaded[slot] = true;
                soa_loop_field_start[slot] = fv.start;
                soa_loop_field_len[slot] = fv.len;
                soa_loop_field_ty[slot] = fv.ty;
            }
            soa_loop_depth += 1;
            pushed_soa_frame = true;
        } else if soa_destruct {
            for fi in 0..plan.soa_field_count {
                if ((soa_used_fields >> (fi as u32)) & 1) == 0 { continue; }
                let s = plan.soa_field_stream[fi];
                let fty = plan.soa_field_ty[fi];
                var fv = Val { fty, 0, 0 };
                if s >= 0 {
                    let loaded, lerr = loadElement(g, f, cur_ptrs[s], 0, fty, id);
                    if lerr != blot_direct_types::Error.none { return lerr; }
                    lget(g, cur_ptrs[s]);
                    i32Const(g, plan.stream_stride[s]);
                    op(g, OP_i32_add);
                    lset(g, cur_ptrs[s]);
                    fv = loaded;
                }
                let terr = test_(g, f, soa_field_pats[fi], fv, false, 0, id);
                if terr != blot_direct_types::Error.none { return terr; }
            }
        } else {
            let item, derr = emitPackedDecodeStep(g, f, plan, cur_ptrs[..], 0, current, id);
            if derr != blot_direct_types::Error.none { return derr; }
            if info.pattern != 0 {
                let terr = test_(g, f, info.pattern, item, false, 0, id);
                if terr != blot_direct_types::Error.none { return terr; }
            }
        }
    } else {
        // PACKED_SPLIT_SUM
        if split_fused {
            let ci_loc = local32(g, f);
            lget(g, tags_base);
            lget(g, current);
            op(g, OP_i32_add);
            op(g, OP_i32_load8_u); uleb(g, 0); uleb(g, 0);
            lset(g, ci_loc);
            let d = split_sum_depth;
            split_sum_binding[d] = split_bind_id;
            split_sum_ty[d] = elem_ty;
            split_sum_ci_loc[d] = ci_loc;
            split_sum_needed_lo[d] = split_needed_mask;
            for s in 0..16 {
                split_sum_cur_ptrs[d * 16 + s] = cur_ptrs[s];
                split_sum_stream_stride[d * 16 + s] = plan.stream_stride[s];
            }
            for ci in 0..64 {
                split_sum_variant_stream[d * 64 + ci] = if ci < plan.variant_count { plan.variant_stream[ci] } else { -1 };
            }
            split_sum_depth += 1;
            pushed_split_frame = true;
        } else {
            let item, derr = emitPackedDecodeStep(g, f, plan, cur_ptrs[..], tags_base, current, id);
            if derr != blot_direct_types::Error.none { return derr; }
            if info.pattern != 0 {
                let terr = test_(g, f, info.pattern, item, false, 0, id);
                if terr != blot_direct_types::Error.none { return terr; }
            }
        }
    }

    let allocations = f.allocations;
    let stores = f.memory_stores;
    let unused = g.newSlot();
    let s_lbl .= g.s;
    let labels_mark = s_lbl.labels.len;
    s_lbl.labels.push(blot_direct_emit::Label {
        target: id,
        depth: exit,
        result: unused,
        kind: blot_direct_emit::LabelKind.loop_,
        top: top,
        iteration: iteration,
        outgoing: outgoing,
        unchanged: unchanged,
        has_release: release,
        release_owner: release_owner,
        release_stack: release_stack,
        allocations: allocations,
        slots: slots,
        saved_esc: saved_escape,
        guards: guards,
    });
    f.loop_depth += 1;
    let body, error = stmt(g, f, info.body);
    if pushed_soa_frame { soa_loop_depth -= 1; }
    if pushed_split_frame { split_sum_depth -= 1; }
    if error != blot_direct_types::Error.none {
        f.loop_depth -= 1;
        s_lbl.labels.resize(labels_mark);
        return error;
    }

    if body.ty != blot_direct_types::never {
        let backedge = g.reserveVals(carries.len);
        for carry, at in carries {
            let value, present, rerr = readBindingVal(g, f, carry.backedge, id);
            if rerr != blot_direct_types::Error.none { f.loop_depth -= 1; s_lbl.labels.resize(labels_mark); return rerr; }
            if !present { f.loop_depth -= 1; s_lbl.labels.resize(labels_mark); return g.fail(m, id, "loop carry without a backedge value"); }
            g.s.vals[backedge.start + at] = value;
        }
        let assigned_c = assignCarries(g, f, backedge, iteration, slots, unchanged, release_owner, release_stack, id);
        if assigned_c != blot_direct_types::Error.none { f.loop_depth -= 1; s_lbl.labels.resize(labels_mark); return assigned_c; }
        let label = s_lbl.labels[labels_mark];
        if label.has_release {
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
    f.loop_depth -= 1;
    s_lbl.labels.resize(labels_mark);
    close(g, f);
    close(g, f);
    return blot_direct_types::Error.none;
}
