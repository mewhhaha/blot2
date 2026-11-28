// Packed sequential arrays (`%[T]` / `Tag.packed`) for the direct Wasm backend.
// Register layout is always `(slot, gen)` (2 x VT_i32). Physically lowers to:
//   1. PACKED_SPLIT_SUM: header owner holding `(sub_slot, sub_gen)` pairs for
//      stream 0 = dense U8 variant tags + streams 1..S-1 = contiguous inline
//      (un-outlined) payload arrays for each non-empty variant.
//   2. PACKED_SOA: header owner holding `(sub_slot, sub_gen)` pairs for one
//      contiguous column stream per non-zero-byte field/item.
//   3. PACKED_FLAT: single contiguous buffer `(slot, gen)` walked by raw cursor.
namespace squid_direct_function;
import .function;

let PACKED_FLAT: u32 = 0;
let PACKED_SOA: u32 = 1;
let PACKED_SPLIT_SUM: u32 = 2;

// PACKED_SOA header layout (16-byte aligned):
//   +0:            cached `elem_cap: u32` guaranteed across all S columns
//   +16:           S * 8 bytes of `(sub_slot, sub_gen)` handles
//   +16 + S * 8:   S * 4 bytes of cached `col_base[s]: u32` direct data pointers
// PACKED_SPLIT_SUM header layout (16-byte aligned):
//   +0:            S * 8 bytes of `(sub_slot, sub_gen)` handles
//   +S * 8:        S * 4 bytes of cached `stream_base[s]: u32` direct data pointers
//   +S * 12:       S * 4 bytes of cached `stream_len[s]: u32` (stream 0 mirrors header len)
//   +S * 16:       S * 4 bytes of cached `stream_cap[s]: u32` (in elements)
let PACKED_SOA_HDR_CAP: u32 = 0;
let PACKED_SOA_HDR_SUBS: u32 = 16;

fn packedSubOff(plan: const PackedPlan&, s: i64) -> u32 {
    if plan.mode == PACKED_SOA { return PACKED_SOA_HDR_SUBS + (s as u32) * 8; }
    return (s as u32) * 8;
}

fn packedSoaColBaseOff(plan: const PackedPlan&, s: i64) -> u32 {
    return PACKED_SOA_HDR_SUBS + (plan.stream_count as u32) * 8 + (s as u32) * 4;
}

fn packedSplitBaseOff(plan: const PackedPlan&, s: i64) -> u32 {
    return (plan.stream_count as u32) * 8 + (s as u32) * 4;
}

fn packedSplitLenOff(plan: const PackedPlan&, s: i64) -> u32 {
    return (plan.stream_count as u32) * 12 + (s as u32) * 4;
}

fn packedSplitCapOff(plan: const PackedPlan&, s: i64) -> u32 {
    return (plan.stream_count as u32) * 16 + (s as u32) * 4;
}

fn packedHeaderBytes(plan: const PackedPlan&) -> u32 {
    if plan.mode == PACKED_SOA {
        return (PACKED_SOA_HDR_SUBS + (plan.stream_count as u32) * 12 + 15) & 0xfffffff0;
    }
    return ((plan.stream_count as u32) * 20 + 15) & 0xfffffff0;
}

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
    let is_rec = in_node.tag == squid_direct_types::Tag.record;
    let is_tup = in_node.tag == squid_direct_types::Tag.tuple;
    if !is_rec && !is_tup { return plan, false, squid_direct_types::Error.none; }
    let count = in_node.b as i64;
    if count < 2 || count > 16 { return plan, false, squid_direct_types::Error.none; }
    plan.soa_is_record = is_rec;
    plan.soa_field_count = count;
    var s_idx: i64 = 0;
    for fi in 0..count {
        let fty = if is_rec { g.types.recordField(inner_ty, fi).ty } else { g.types.words[in_node.a + fi] };
        plan.soa_field_ty[fi] = fty;
        let fbytes, berr = flatBytes(g, f, fty, id);
        if berr != squid_direct_types::Error.none { return plan, false, berr; }
        if fbytes == 0 {
            plan.soa_field_stream[fi] = -1;
        } else {
            plan.soa_field_stream[fi] = s_idx;
            plan.stream_ty[s_idx] = fty;
            plan.stream_stride[s_idx] = fbytes;
            s_idx += 1;
        }
    }
    if s_idx < 2 { return PackedPlan { mode: PACKED_FLAT, elem_ty: elem_ty, .. }, false, squid_direct_types::Error.none; }
    plan.mode = PACKED_SOA;
    plan.stream_count = s_idx;
    return plan, true, squid_direct_types::Error.none;
}

fn computePackedPlan(g: Generator&, f: const Fn&, elem_ty: Ty, id: u32) -> PackedPlan, Error {
    var flat_plan = PackedPlan { mode: PACKED_FLAT, elem_ty: elem_ty, .. };
    let is_rec, rerr = g.types.isRecursive(elem_ty);
    if rerr != squid_direct_types::Error.none { return flat_plan, g.typeFailure(g.units[f.unit - 1], id); }
    if is_rec { return flat_plan, squid_direct_types::Error.none; }
    let n = g.types.node(elem_ty);
    if n.tag == squid_direct_types::Tag.nominal {
        let cases, cerr = g.types.variants(elem_ty);
        if cerr != squid_direct_types::Error.none { return flat_plan, g.typeFailure(g.units[f.unit - 1], id); }
        if cases.len >= 2 && cases.len <= 256 {
            var plan = PackedPlan {
                mode: PACKED_SPLIT_SUM,
                elem_ty: elem_ty,
                variant_count: cases.len as i64,
                ..
            };
            plan.stream_ty[0] = squid_direct_types::u8_;
            plan.stream_stride[0] = 1;
            var s_idx: i64 = 1;
            for ci in 0..(cases.len as i64) {
                let pty = g.types.variant_payloads[cases.payloads + ci];
                let pbytes, berr = flatBytes(g, f, pty, id);
                if berr != squid_direct_types::Error.none { return flat_plan, berr; }
                if pbytes == 0 {
                    plan.variant_stream[ci] = -1;
                } else {
                    if s_idx >= 16 { return flat_plan, squid_direct_types::Error.none; }
                    plan.variant_stream[ci] = s_idx;
                    plan.stream_ty[s_idx] = pty;
                    plan.stream_stride[s_idx] = pbytes;
                    s_idx += 1;
                }
            }
            if s_idx >= 2 {
                plan.stream_count = s_idx;
                return plan, squid_direct_types::Error.none;
            }
            return flat_plan, squid_direct_types::Error.none;
        }
        if cases.len == 1 {
            let pty = g.types.variant_payloads[cases.payloads];
            let prec, prerr = g.types.isRecursive(pty);
            if prerr != squid_direct_types::Error.none { return flat_plan, g.typeFailure(g.units[f.unit - 1], id); }
            if !prec {
                let vtag = g.types.variant_tags[cases.tags];
                let soa, ok, serr = computeSoaPlan(g, f, elem_ty, pty, true, vtag, id);
                if serr != squid_direct_types::Error.none { return flat_plan, serr; }
                if ok { return soa, squid_direct_types::Error.none; }
            }
        }
        return flat_plan, squid_direct_types::Error.none;
    }
    if n.tag == squid_direct_types::Tag.record || n.tag == squid_direct_types::Tag.tuple {
        let soa, ok, serr = computeSoaPlan(g, f, elem_ty, elem_ty, false, 0, id);
        if serr != squid_direct_types::Error.none { return flat_plan, serr; }
        if ok { return soa, squid_direct_types::Error.none; }
    }
    return flat_plan, squid_direct_types::Error.none;
}

// Checks header handle is live and not a deeply-immutable static const pool.
// Returns (h_entry, h_base, h_len). Hoists `rt.check` via `ensureCheckedGrow`.
fn emitCheckPackedHeaderMutable(g: Generator&, f: Fn&, container: Val) -> u32, u32, u32 {
    let h_entry = ensureCheckedGrow(g, f, container);
    if !knownMutable(g, f, container) {
        lget(g, h_entry);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_capacity);
        i32Const(g, squid_direct_runtime::static_pool_flag);
        op(g, OP_i32_and);
        trap(g, f);
    }
    let h_base = local32(g, f);
    let h_len = local32(g, f);
    lget(g, h_entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base);
    lset(g, h_base);
    lget(g, h_entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    lset(g, h_len);
    return h_entry, h_base, h_len;
}

// Direct 2-level owner-table entry lookup for a private live sub-stream slot (zero calls).
fn emitPackedSubEntryAddr(g: Generator&, f: const Fn&, sub_slot: u32) -> u32 {
    let sub_entry = local32(g, f);
    lget(g, sub_slot);
    i32Const(g, 8);
    op(g, OP_i32_shr_u);
    i32Const(g, 2);
    op(g, OP_i32_shl);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, g.runtime_().layout.owner_table);
    lget(g, sub_slot);
    i32Const(g, 255);
    op(g, OP_i32_and);
    i32Const(g, 4);
    op(g, OP_i32_shl);
    op(g, OP_i32_add);
    lset(g, sub_entry);
    return sub_entry;
}

// Inline fast-path push onto private sub-stream `s` of a live mutable packed header.
// Avoids `rt.check` + `rt.push` call overhead whenever capacity suffices (`!rt.has_fork`).
fn emitPackedSubPushFast(g: Generator&, f: Fn&, h_base: u32, s: i64, step: u32) -> u32, u32 {
    let rt = g.runtime_();
    let off = (s as u32) * 8;
    let sub_slot = local32(g, f);
    let addr = local32(g, f);
    lget(g, h_base);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, off);
    lset(g, sub_slot);
    if !rt.has_fork && step > 0 && step <= 65536 {
        let sub_entry = emitPackedSubEntryAddr(g, f, sub_slot);
        let slen = local32(g, f);
        let next_len = local32(g, f);
        lget(g, sub_entry);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
        ltee(g, slen);
        i32Const(g, 1);
        op(g, OP_i32_add);
        lset(g, next_len);
        let need = emitScaledBytes(g, f, next_len, step);
        lget(g, sub_entry);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_capacity);
        i32Const(g, squid_direct_runtime::capacity_mask);
        op(g, OP_i32_and);
        lget(g, need);
        op(g, OP_i32_ge_u);
        let fast = open(g, f, OP_if_);
        lget(g, sub_entry);
        lget(g, next_len);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
        let sbase = local32(g, f);
        lget(g, sub_entry);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base);
        lset(g, sbase);
        let fast_addr = emitOffsetAddress(g, f, sbase, slen, step);
        lget(g, fast_addr);
        lset(g, addr);
        popCheckedArraysAt(f, fast);
        op(g, OP_else_);
        lget(g, sub_slot);
        lget(g, h_base);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, off + 4);
        i32Const(g, step);
        callf(g, rt.push);
        lset(g, addr);
        close(g, f);
    } else {
        lget(g, sub_slot);
        lget(g, h_base);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, off + 4);
        i32Const(g, step);
        callf(g, rt.push);
        lset(g, addr);
    }
    return sub_slot, addr;
}

// Syncs `sub_entry.entry_length = h_len` for all PACKED_SOA sub-slots before slow-path
// `rt.reserve`, `rt.copy`, or `rt.persist` (fast-path push updates only header `entry_length`).
fn emitPackedSoaSyncSubLens(g: Generator&, f: const Fn&, plan: const PackedPlan&, h_base: u32, h_len: u32) {
    for s in 0..plan.stream_count {
        let off = packedSubOff(plan, s);
        let sub_slot = local32(g, f);
        lget(g, h_base);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, off);
        lset(g, sub_slot);
        let sub_entry = emitPackedSubEntryAddr(g, f, sub_slot);
        lget(g, sub_entry);
        lget(g, h_len);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    }
}

// Refreshes PACKED_SOA header `elem_cap` and cached `col_base[0..S-1]` direct pointers.
fn emitPackedSoaRefreshCache(g: Generator&, f: const Fn&, plan: const PackedPlan&, h_base: u32, cap_local: u32) {
    lget(g, h_base);
    lget(g, cap_local);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, PACKED_SOA_HDR_CAP);
    for s in 0..plan.stream_count {
        let off = packedSubOff(plan, s);
        let sub_slot = local32(g, f);
        lget(g, h_base);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, off);
        lset(g, sub_slot);
        let sub_entry = emitPackedSubEntryAddr(g, f, sub_slot);
        lget(g, h_base);
        lget(g, sub_entry);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, packedSoaColBaseOff(plan, s));
    }
}

// Syncs `sub_entry.entry_length` for all PACKED_SPLIT_SUM sub-slots before slow-path
// `rt.pop`, `rt.copy`, `rt.persist`, or `extend`.
fn emitPackedSplitSyncSubLens(g: Generator&, f: const Fn&, plan: const PackedPlan&, h_base: u32, h_len: u32) {
    for s in 0..plan.stream_count {
        let off = packedSubOff(plan, s);
        let sub_slot = local32(g, f);
        lget(g, h_base);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, off);
        lset(g, sub_slot);
        let sub_entry = emitPackedSubEntryAddr(g, f, sub_slot);
        lget(g, sub_entry);
        if s == 0 {
            lget(g, h_len);
        } else {
            lget(g, h_base);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, packedSplitLenOff(plan, s));
        }
        op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    }
}

// Refreshes PACKED_SPLIT_SUM header cached `stream_base[s]`, `stream_len[s]`, and `stream_cap[s]`.
fn emitPackedSplitRefreshAll(g: Generator&, f: const Fn&, plan: const PackedPlan&, h_base: u32, zero_caps: bool) {
    for s in 0..plan.stream_count {
        let off = packedSubOff(plan, s);
        let sub_slot = local32(g, f);
        lget(g, h_base);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, off);
        lset(g, sub_slot);
        let sub_entry = emitPackedSubEntryAddr(g, f, sub_slot);
        lget(g, h_base);
        lget(g, sub_entry);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, packedSplitBaseOff(plan, s));
        lget(g, h_base);
        lget(g, sub_entry);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, packedSplitLenOff(plan, s));
        lget(g, h_base);
        if zero_caps {
            i32Const(g, 0);
        } else {
            let step = plan.stream_stride[s];
            lget(g, sub_entry);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_capacity);
            i32Const(g, squid_direct_runtime::capacity_mask);
            op(g, OP_i32_and);
            if step > 1 {
                i32Const(g, step);
                op(g, squid_direct_writer::OP_i32_div_u);
            }
        }
        op(g, OP_i32_store); uleb(g, 2); uleb(g, packedSplitCapOff(plan, s));
    }
}

// Header-cached zero-lookup push onto PACKED_SPLIT_SUM stream `s` (`!rt.has_fork` only).
// Reads `stream_cap[s]`/`stream_base[s]` directly from header; syncs + grows only on rare cap miss.
fn emitPackedSplitStreamPushCached(
    g: Generator&,
    f: Fn&,
    plan: const PackedPlan&,
    h_base: u32,
    s: i64,
    cur_len: u32,
    step: u32,
) -> u32 {
    let rt = g.runtime_();
    let cur_cap = local32(g, f);
    let next_len = local32(g, f);
    lget(g, cur_len);
    i32Const(g, 1);
    op(g, OP_i32_add);
    ltee(g, next_len);
    lget(g, h_base);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, packedSplitCapOff(plan, s));
    ltee(g, cur_cap);
    op(g, OP_i32_gt_u);
    let need_grow = open(g, f, OP_if_);
    let min_cap: u32 = if s == 0 { 16 } else { 8 };
    let new_cap = local32(g, f);
    lget(g, cur_cap); i32Const(g, 1); op(g, OP_i32_shl);
    i32Const(g, min_cap);
    lget(g, cur_cap); i32Const(g, min_cap >> 1); op(g, OP_i32_ge_u);
    op(g, OP_select);
    ltee(g, new_cap);
    lget(g, next_len); op(g, OP_i32_lt_u);
    let fix_c = open(g, f, OP_if_);
    lget(g, next_len); lset(g, new_cap);
    close(g, f);
    let sub_slot, sub_gen = emitLoadPackedSubHandle(g, f, plan, h_base, s);
    let sub_entry = emitPackedSubEntryAddr(g, f, sub_slot);
    lget(g, sub_entry); lget(g, cur_len); op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    lget(g, sub_slot); lget(g, sub_gen); lget(g, new_cap); i32Const(g, step); callf(g, rt.reserve);
    lget(g, h_base);
    lget(g, sub_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, packedSplitBaseOff(plan, s));
    lget(g, h_base); lget(g, new_cap); op(g, OP_i32_store); uleb(g, 2); uleb(g, packedSplitCapOff(plan, s));
    popCheckedArraysAt(f, need_grow);
    close(g, f);
    if s >= 1 {
        lget(g, h_base); lget(g, next_len); op(g, OP_i32_store); uleb(g, 2); uleb(g, packedSplitLenOff(plan, s));
    }
    let sbase = local32(g, f);
    lget(g, h_base); op(g, OP_i32_load); uleb(g, 2); uleb(g, packedSplitBaseOff(plan, s)); lset(g, sbase);
    return emitOffsetAddress(g, f, sbase, cur_len, step);
}

// Loads `(sub_slot, sub_gen)` of stream `s` from header buffer `h_base`.
fn emitLoadPackedSubHandle(g: Generator&, f: const Fn&, plan: const PackedPlan&, h_base: u32, s: i64) -> u32, u32 {
    let off = packedSubOff(plan, s);
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

fn emitLoadPackedSubBase(g: Generator&, f: Fn&, plan: const PackedPlan&, h_base: u32, s: i64) -> u32 {
    let sub_base = local32(g, f);
    if !g.runtime_().has_fork {
        if plan.mode == PACKED_SOA {
            lget(g, h_base);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, packedSoaColBaseOff(plan, s));
            lset(g, sub_base);
            return sub_base;
        }
        if plan.mode == PACKED_SPLIT_SUM {
            lget(g, h_base);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, packedSplitBaseOff(plan, s));
            lset(g, sub_base);
            return sub_base;
        }
    }
    let off = packedSubOff(plan, s);
    let sub_slot = local32(g, f);
    lget(g, h_base);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, off);
    lset(g, sub_slot);
    let sub_entry = emitPackedSubEntryAddr(g, f, sub_slot);
    lget(g, sub_entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base);
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
        i32Const(g, squid_direct_runtime::capacity_mask / step);
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
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let plan, perr = computePackedPlan(g, f, elem_ty, id);
    if perr != squid_direct_types::Error.none { return neverVal(), perr; }
    let rt = g.runtime_();
    noteAllocation(f);
    if plan.mode == PACKED_FLAT {
        let step, serr = stride(g, f, elem_ty, id);
        if serr != squid_direct_types::Error.none { return neverVal(), serr; }
        let slot, gen = emitPackedCreateSub(g, f, cap_local, has_cap, step);
        let handle = valOf2(g, ty, slot, gen);
        recordMutable(g, f, handle);
        return handle, squid_direct_types::Error.none;
    }
    let header_bytes = packedHeaderBytes(plan);
    let h_base = local32(g, f);
    i32Const(g, header_bytes);
    callf(g, rt.stack);
    lset(g, h_base);
    for s in 0..plan.stream_count {
        let use_cap = has_cap && (plan.mode == PACKED_SOA || s == 0);
        let sub_slot, sub_gen = emitPackedCreateSub(g, f, cap_local, use_cap, plan.stream_stride[s]);
        let off = packedSubOff(plan, s);
        lget(g, h_base);
        lget(g, sub_slot);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, off);
        lget(g, h_base);
        lget(g, sub_gen);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, off + 4);
    }
    if plan.mode == PACKED_SOA {
        let init_cap = if has_cap { cap_local } else { constLocal(g, f, 0) };
        emitPackedSoaRefreshCache(g, f, plan, h_base, init_cap);
    } else if plan.mode == PACKED_SPLIT_SUM {
        for s in 0..plan.stream_count {
            let off = packedSubOff(plan, s);
            let sub_slot = local32(g, f);
            lget(g, h_base); op(g, OP_i32_load); uleb(g, 2); uleb(g, off); lset(g, sub_slot);
            let sub_entry = emitPackedSubEntryAddr(g, f, sub_slot);
            lget(g, h_base);
            lget(g, sub_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base);
            op(g, OP_i32_store); uleb(g, 2); uleb(g, packedSplitBaseOff(plan, s));
            lget(g, h_base); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, packedSplitLenOff(plan, s));
            lget(g, h_base);
            if s == 0 && has_cap { lget(g, cap_local); } else { i32Const(g, 0); }
            op(g, OP_i32_store); uleb(g, 2); uleb(g, packedSplitCapOff(plan, s));
        }
    }
    lget(g, h_base);
    i32Const(g, 0);
    i32Const(g, header_bytes);
    callf(g, rt.open);
    let handle, herr = pop(g, f, ty, id);
    if herr != squid_direct_types::Error.none { return handle, herr; }
    recordMutable(g, f, handle);
    return handle, squid_direct_types::Error.none;
}

// Assemble a concrete SoA element value (record, tuple, or single-ctor nominal) from field Vals.
fn assembleSoaVal(g: Generator&, f: Fn&, plan: const PackedPlan&, field_vals: Vals, id: u32) -> Val, Error {
    let inner_ty = plan.soa_inner_ty;
    let boxed, berr = isBoxed(g, f, inner_ty, id);
    if berr != squid_direct_types::Error.none { return neverVal(), berr; }
    var inner_val = neverVal();
    if boxed {
        let blk, bkerr = newBlock(g, f, inner_ty, id);
        if bkerr != squid_direct_types::Error.none { return neverVal(), bkerr; }
        for fi in 0..plan.soa_field_count {
            let fv = g.s.vals[field_vals.start + fi];
            let off = if plan.soa_is_record {
                let fo, ferr = fieldOffset(g, f, inner_ty, fi, id);
                if ferr != squid_direct_types::Error.none { return neverVal(), ferr; }
                fo
            } else {
                let io, ierr = itemOffset(g, f, inner_ty, fi, id);
                if ierr != squid_direct_types::Error.none { return neverVal(), ierr; }
                io
            };
            let werr = writeFlat(g, f, blk, off, fv, id);
            if werr != squid_direct_types::Error.none { return neverVal(), werr; }
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
    return inner_val, squid_direct_types::Error.none;
}

fn emitPackedPushVal(g: Generator&, f: Fn&, container: Val, value: Val, id: u32, selective: bool = false) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, container.ty, id);
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let plan, perr = computePackedPlan(g, f, elem_ty, id);
    if perr != squid_direct_types::Error.none { return neverVal(), perr; }
    let rt = g.runtime_();
    if plan.mode == PACKED_FLAT {
        let step, serr = stride(g, f, elem_ty, id);
        if serr != squid_direct_types::Error.none { return neverVal(), serr; }
        let address = local32(g, f);
        if !rt.has_fork && step > 0 && step <= 65536 {
            let entry = ensureCheckedGrow(g, f, container);
            let len = local32(g, f);
            let next_len = local32(g, f);
            lget(g, entry);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
            ltee(g, len);
            i32Const(g, 1);
            op(g, OP_i32_add);
            lset(g, next_len);
            let need = emitScaledBytes(g, f, next_len, step);
            let cap = local32(g, f);
            lget(g, entry);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_capacity);
            if knownMutable(g, f, container) {
                i32Const(g, squid_direct_runtime::capacity_mask);
                op(g, OP_i32_and);
                lget(g, need);
                op(g, OP_i32_ge_u);
            } else {
                ltee(g, cap);
                i32Const(g, squid_direct_runtime::flag_mask ^ squid_direct_runtime::heap_flag);
                op(g, OP_i32_and);
                i32Const(g, squid_direct_runtime::live_flag);
                op(g, OP_i32_eq);
                lget(g, need);
                lget(g, cap);
                i32Const(g, squid_direct_runtime::capacity_mask);
                op(g, OP_i32_and);
                op(g, OP_i32_le_u);
                op(g, OP_i32_and);
            }
            let fast = open(g, f, OP_if_);
            lget(g, entry);
            lget(g, next_len);
            op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
            let elem_base = local32(g, f);
            lget(g, entry);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base);
            lset(g, elem_base);
            let fast_addr = emitOffsetAddress(g, f, elem_base, len, step);
            lget(g, fast_addr);
            lset(g, address);
            popCheckedArraysAt(f, fast);
            op(g, OP_else_);
            lget(g, w(g, container, 0));
            lget(g, w(g, container, 1));
            i32Const(g, step);
            callf(g, rt.push);
            lset(g, address);
            close(g, f);
        } else {
            lget(g, w(g, container, 0));
            lget(g, w(g, container, 1));
            i32Const(g, step);
            callf(g, rt.push);
            lset(g, address);
        }
        let noted = noteStoreToSlot(g, f, w(g, container, 0), value);
        if noted != squid_direct_types::Error.none { return neverVal(), noted; }
        if rt.has_fork { recordBeforeWrite(g, f, w(g, container, 0), address, 0, step); }
        let werr = writeElement(g, f, address, 0, value, id);
        if werr != squid_direct_types::Error.none { return neverVal(), werr; }
        if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
        return container, squid_direct_types::Error.none;
    }
    let h_entry, h_base, h_len = emitCheckPackedHeaderMutable(g, f, container);
    if plan.mode == PACKED_SOA {
        var inner_val = value;
        if plan.soa_is_nominal {
            let uw, uerr = unwrapVariant(g, f, value, plan.soa_nominal_tag, id);
            if uerr != squid_direct_types::Error.none { return neverVal(), uerr; }
            inner_val = uw;
        }
        if !rt.has_fork {
            let next_len = local32(g, f);
            let cur_cap = local32(g, f);
            lget(g, h_len);
            i32Const(g, 1);
            op(g, OP_i32_add);
            ltee(g, next_len);
            lget(g, h_base);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, PACKED_SOA_HDR_CAP);
            ltee(g, cur_cap);
            op(g, OP_i32_gt_u);
            let need_grow = open(g, f, OP_if_);
            // Rare slow path: sync all column lengths, grow all S columns together, refresh cached bases.
            emitPackedSoaSyncSubLens(g, f, plan, h_base, h_len);
            let new_cap = local32(g, f);
            lget(g, cur_cap);
            i32Const(g, 1);
            op(g, OP_i32_shl);
            i32Const(g, 16);
            lget(g, cur_cap);
            i32Const(g, 8);
            op(g, OP_i32_ge_u);
            op(g, OP_select);
            ltee(g, new_cap);
            lget(g, next_len);
            op(g, OP_i32_lt_u);
            let fix_cap = open(g, f, OP_if_);
            lget(g, next_len);
            lset(g, new_cap);
            close(g, f);
            for s in 0..plan.stream_count {
                let sub_slot, sub_gen = emitLoadPackedSubHandle(g, f, plan, h_base, s);
                lget(g, sub_slot);
                lget(g, sub_gen);
                lget(g, new_cap);
                i32Const(g, plan.stream_stride[s]);
                callf(g, rt.reserve);
            }
            emitPackedSoaRefreshCache(g, f, plan, h_base, new_cap);
            popCheckedArraysAt(f, need_grow);
            close(g, f);
            // Single-check fast path: write each field straight to cached `col_base[s] + h_len * step`!
            for fi in 0..plan.soa_field_count {
                let s = plan.soa_field_stream[fi];
                if s < 0 { continue; }
                let fval = if plan.soa_is_record {
                    let fv, ferr = recordField(g, f, inner_val, fi, id);
                    if ferr != squid_direct_types::Error.none { return neverVal(), ferr; }
                    fv
                } else {
                    let iv, ierr = tupleItem(g, f, inner_val, fi, id);
                    if ierr != squid_direct_types::Error.none { return neverVal(), ierr; }
                    iv
                };
                let step = plan.stream_stride[s];
                let col_base = local32(g, f);
                lget(g, h_base);
                op(g, OP_i32_load); uleb(g, 2); uleb(g, packedSoaColBaseOff(plan, s));
                lset(g, col_base);
                let addr = emitOffsetAddress(g, f, col_base, h_len, step);
                if holdsContainer(g, fval.ty, 0) {
                    let sub_slot = local32(g, f);
                    lget(g, h_base);
                    op(g, OP_i32_load); uleb(g, 2); uleb(g, packedSubOff(plan, s));
                    lset(g, sub_slot);
                    let noted = noteStoreToSlot(g, f, sub_slot, fval);
                    if noted != squid_direct_types::Error.none { return neverVal(), noted; }
                }
                let werr = writeElement(g, f, addr, 0, fval, id);
                if werr != squid_direct_types::Error.none { return neverVal(), werr; }
            }
            lget(g, h_entry);
            lget(g, next_len);
            op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
            if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
            return container, squid_direct_types::Error.none;
        }
        for fi in 0..plan.soa_field_count {
            let s = plan.soa_field_stream[fi];
            if s < 0 { continue; }
            let fval = if plan.soa_is_record {
                let fv, ferr = recordField(g, f, inner_val, fi, id);
                if ferr != squid_direct_types::Error.none { return neverVal(), ferr; }
                fv
            } else {
                let iv, ierr = tupleItem(g, f, inner_val, fi, id);
                if ierr != squid_direct_types::Error.none { return neverVal(), ierr; }
                iv
            };
            let step = plan.stream_stride[s];
            let sub_slot, sub_gen = emitLoadPackedSubHandle(g, f, plan, h_base, s);
            let addr = local32(g, f);
            lget(g, sub_slot);
            lget(g, sub_gen);
            i32Const(g, step);
            callf(g, rt.push);
            lset(g, addr);
            let noted = noteStoreToSlot(g, f, sub_slot, fval);
            if noted != squid_direct_types::Error.none { return neverVal(), noted; }
            recordBeforeWrite(g, f, sub_slot, addr, 0, step);
            let werr = writeElement(g, f, addr, 0, fval, id);
            if werr != squid_direct_types::Error.none { return neverVal(), werr; }
        }
        recordBeforeWrite(g, f, w(g, container, 0), h_entry, squid_direct_runtime::entry_length, 4);
        lget(g, h_entry);
        lget(g, h_len);
        i32Const(g, 1);
        op(g, OP_i32_add);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
        if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
        return container, squid_direct_types::Error.none;
    }
    // PACKED_SPLIT_SUM
    let cases, cerr = g.types.variants(elem_ty);
    if cerr != squid_direct_types::Error.none { return neverVal(), g.typeFailure(g.units[f.unit - 1], id); }
    let tag_loc = local32(g, f);
    let terr = emitValueTag(g, f, value, id);
    if terr != squid_direct_types::Error.none { return neverVal(), terr; }
    lset(g, tag_loc);
    if !rt.has_fork {
        // Zero-lookup header-cached fast path (with dense `br_table` dispatch when >= 3 variants).
        let t_addr = emitPackedSplitStreamPushCached(g, f, plan, h_base, 0, h_len, 1);
        var dense_tags = plan.variant_count >= 3 && plan.variant_count <= 64;
        if dense_tags {
            for ci in 0..plan.variant_count {
                if g.types.variant_tags[cases.tags + ci] != (ci as u32) { dense_tags = false; break; }
            }
        }
        let done = open(g, f, OP_block);
        if dense_tags {
            let nvar = plan.variant_count;
            for _ in 0..(nvar + 1) { let _ = open(g, f, OP_block); }
            lget(g, tag_loc);
            op(g, OP_br_table);
            uleb(g, nvar as u32);
            for ci in 0..nvar { uleb(g, ci as u32); }
            uleb(g, nvar as u32);
            for ci in 0..nvar {
                close(g, f);
                let vtag = g.types.variant_tags[cases.tags + ci];
                lget(g, t_addr); i32Const(g, ci as u32); op(g, OP_i32_store8); uleb(g, 0); uleb(g, 0);
                let s = plan.variant_stream[ci];
                if s >= 0 {
                    let payload, uerr = unwrapVariant(g, f, value, vtag, id);
                    if uerr != squid_direct_types::Error.none { return neverVal(), uerr; }
                    let step = plan.stream_stride[s];
                    let slen = local32(g, f);
                    lget(g, h_base); op(g, OP_i32_load); uleb(g, 2); uleb(g, packedSplitLenOff(plan, s)); lset(g, slen);
                    let p_addr = emitPackedSplitStreamPushCached(g, f, plan, h_base, s, slen, step);
                    if holdsContainer(g, payload.ty, 0) {
                        let p_slot = local32(g, f);
                        lget(g, h_base); op(g, OP_i32_load); uleb(g, 2); uleb(g, packedSubOff(plan, s)); lset(g, p_slot);
                        let noted = noteStoreToSlot(g, f, p_slot, payload);
                        if noted != squid_direct_types::Error.none { return neverVal(), noted; }
                    }
                    let werr = writeElement(g, f, p_addr, 0, payload, id);
                    if werr != squid_direct_types::Error.none { return neverVal(), werr; }
                }
                br(g, f, OP_br, done);
            }
            close(g, f);
            op(g, OP_unreachable_);
        } else {
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
                    if uerr != squid_direct_types::Error.none { return neverVal(), uerr; }
                    let step = plan.stream_stride[s];
                    let slen = local32(g, f);
                    lget(g, h_base); op(g, OP_i32_load); uleb(g, 2); uleb(g, packedSplitLenOff(plan, s)); lset(g, slen);
                    let p_addr = emitPackedSplitStreamPushCached(g, f, plan, h_base, s, slen, step);
                    if holdsContainer(g, payload.ty, 0) {
                        let p_slot = local32(g, f);
                        lget(g, h_base); op(g, OP_i32_load); uleb(g, 2); uleb(g, packedSubOff(plan, s)); lset(g, p_slot);
                        let noted = noteStoreToSlot(g, f, p_slot, payload);
                        if noted != squid_direct_types::Error.none { return neverVal(), noted; }
                    }
                    let werr = writeElement(g, f, p_addr, 0, payload, id);
                    if werr != squid_direct_types::Error.none { return neverVal(), werr; }
                }
                br(g, f, OP_br, done);
                close(g, f);
            }
            op(g, OP_unreachable_);
        }
        close(g, f);
        lget(g, h_entry);
        lget(g, h_len);
        i32Const(g, 1);
        op(g, OP_i32_add);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
        if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
        return container, squid_direct_types::Error.none;
    }
    let t_slot, t_addr = emitPackedSubPushFast(g, f, h_base, 0, 1);
    recordBeforeWrite(g, f, t_slot, t_addr, 0, 1);
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
            if uerr != squid_direct_types::Error.none { return neverVal(), uerr; }
            let step = plan.stream_stride[s];
            let p_slot, p_addr = emitPackedSubPushFast(g, f, h_base, s, step);
            let noted = noteStoreToSlot(g, f, p_slot, payload);
            if noted != squid_direct_types::Error.none { return neverVal(), noted; }
            recordBeforeWrite(g, f, p_slot, p_addr, 0, step);
            let werr = writeElement(g, f, p_addr, 0, payload, id);
            if werr != squid_direct_types::Error.none { return neverVal(), werr; }
        }
        br(g, f, OP_br, done);
        close(g, f);
    }
    op(g, OP_unreachable_);
    close(g, f);
    recordBeforeWrite(g, f, w(g, container, 0), h_entry, squid_direct_runtime::entry_length, 4);
    lget(g, h_entry);
    lget(g, h_len);
    i32Const(g, 1);
    op(g, OP_i32_add);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
    return container, squid_direct_types::Error.none;
}

fn emitPackedFromValues(g: Generator&, f: Fn&, ty: Ty, values: Vals, id: u32) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, ty, id);
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let plan, perr = computePackedPlan(g, f, elem_ty, id);
    if perr != squid_direct_types::Error.none { return neverVal(), perr; }
    let cap = constLocal(g, f, values.len);
    recordConstU32(f, cap, values.len);
    if plan.mode == PACKED_FLAT {
        if values.len == 0 { return emitPackedWithCapacity(g, f, ty, cap, false, id); }
        let rt = g.runtime_();
        noteAllocation(f);
        let step, serr = stride(g, f, elem_ty, id);
        if serr != squid_direct_types::Error.none { return neverVal(), serr; }
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
        if herr != squid_direct_types::Error.none { return handle, herr; }
        recordMutable(g, f, handle);
        recordCheckedArray(f, w(g, handle, 0), w(g, handle, 1), base, cap);
        for idx in 0..(values.len as i64) {
            let v = g.s.vals[values.start + idx];
            let noted = noteStoreToSlot(g, f, w(g, handle, 0), v);
            if noted != squid_direct_types::Error.none { return neverVal(), noted; }
            let werr = writeElement(g, f, base, (idx as u32) * step, v, id);
            if werr != squid_direct_types::Error.none { return neverVal(), werr; }
        }
        return handle, squid_direct_types::Error.none;
    }
    let handle, herr = emitPackedWithCapacity(g, f, ty, cap, values.len > 0, id);
    if herr != squid_direct_types::Error.none { return handle, herr; }
    for idx in 0..(values.len as i64) {
        let _, perr2 = emitPackedPushVal(g, f, handle, g.s.vals[values.start + idx], id, true);
        if perr2 != squid_direct_types::Error.none { return neverVal(), perr2; }
    }
    return handle, squid_direct_types::Error.none;
}

fn emitPackedPopVal(g: Generator&, f: Fn&, container: Val, ty: Ty, id: u32, selective: bool = false) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, container.ty, id);
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let plan, perr = computePackedPlan(g, f, elem_ty, id);
    if perr != squid_direct_types::Error.none { return neverVal(), perr; }
    let rt = g.runtime_();
    if plan.mode == PACKED_FLAT {
        let step, serr = stride(g, f, elem_ty, id);
        if serr != squid_direct_types::Error.none { return neverVal(), serr; }
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
        let new_len = local32(g, f);
        lget(g, h_len);
        i32Const(g, 1);
        op(g, OP_i32_sub);
        lset(g, new_len);
        let field_vals = g.reserveVals(plan.soa_field_count);
        for fi in 0..plan.soa_field_count {
            let s = plan.soa_field_stream[fi];
            let fty = plan.soa_field_ty[fi];
            if s < 0 {
                g.s.vals[field_vals.start + fi] = Val { fty, 0, 0 };
                continue;
            }
            let step = plan.stream_stride[s];
            let addr = local32(g, f);
            if !rt.has_fork {
                let col_base = local32(g, f);
                lget(g, h_base);
                op(g, OP_i32_load); uleb(g, 2); uleb(g, packedSoaColBaseOff(plan, s));
                lset(g, col_base);
                let a = emitOffsetAddress(g, f, col_base, new_len, step);
                lget(g, a);
                lset(g, addr);
            } else {
                let sub_slot, sub_gen = emitLoadPackedSubHandle(g, f, plan, h_base, s);
                lget(g, sub_slot);
                lget(g, sub_gen);
                i32Const(g, step);
                callf(g, rt.pop);
                lset(g, addr);
            }
            let fval, lerr = loadElement(g, f, addr, 0, fty, id);
            if lerr != squid_direct_types::Error.none { return neverVal(), lerr; }
            g.s.vals[field_vals.start + fi] = fval;
        }
        if rt.has_fork {
            recordBeforeWrite(g, f, w(g, container, 0), h_entry, squid_direct_runtime::entry_length, 4);
        }
        lget(g, h_entry);
        lget(g, new_len);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
        if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
        return assembleSoaVal(g, f, plan, field_vals, id);
    }
    // PACKED_SPLIT_SUM
    let cases, cerr = g.types.variants(elem_ty);
    if cerr != squid_direct_types::Error.none { return neverVal(), g.typeFailure(g.units[f.unit - 1], id); }
    if !rt.has_fork {
        emitPackedSplitSyncSubLens(g, f, plan, h_base, h_len);
    }
    let t_slot, t_gen = emitLoadPackedSubHandle(g, f, plan, h_base, 0);
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
        recordBeforeWrite(g, f, w(g, container, 0), h_entry, squid_direct_runtime::entry_length, 4);
    }
    lget(g, h_entry);
    lget(g, h_len);
    i32Const(g, 1);
    op(g, OP_i32_sub);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    let result, rerr = fresh(g, f, ty, id);
    if rerr != squid_direct_types::Error.none { return result, rerr; }
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
            let p_slot, p_gen = emitLoadPackedSubHandle(g, f, plan, h_base, s);
            let step = plan.stream_stride[s];
            let p_addr = local32(g, f);
            lget(g, p_slot);
            lget(g, p_gen);
            i32Const(g, step);
            callf(g, rt.pop);
            lset(g, p_addr);
            if !rt.has_fork {
                let p_entry = emitPackedSubEntryAddr(g, f, p_slot);
                lget(g, h_base);
                lget(g, p_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
                op(g, OP_i32_store); uleb(g, 2); uleb(g, packedSplitLenOff(plan, s));
            }
            let loaded, lerr = loadElement(g, f, p_addr, 0, pty, id);
            if lerr != squid_direct_types::Error.none { return neverVal(), lerr; }
            payload = loaded;
        }
        let wrapped, werr = wrapVariant(g, f, elem_ty, vtag, payload, id);
        if werr != squid_direct_types::Error.none { return neverVal(), werr; }
        let cperr = copy(g, f, wrapped, result, id);
        if cperr != squid_direct_types::Error.none { return neverVal(), cperr; }
        br(g, f, OP_br, done);
        close(g, f);
    }
    op(g, OP_unreachable_);
    close(g, f);
    if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
    return result, squid_direct_types::Error.none;
}

fn emitPackedReserve(g: Generator&, f: Fn&, container: Val, additional: u32, id: u32, selective: bool = false) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, container.ty, id);
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let plan, perr = computePackedPlan(g, f, elem_ty, id);
    if perr != squid_direct_types::Error.none { return neverVal(), perr; }
    let rt = g.runtime_();
    if plan.mode == PACKED_FLAT {
        let step, serr = stride(g, f, elem_ty, id);
        if serr != squid_direct_types::Error.none { return neverVal(), serr; }
        let cur_len, lerr = lengthOf(g, f, container, id);
        if lerr != squid_direct_types::Error.none { return neverVal(), lerr; }
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
        return container, squid_direct_types::Error.none;
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
    if plan.mode == PACKED_SOA && !rt.has_fork {
        lget(g, need);
        lget(g, h_base);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, PACKED_SOA_HDR_CAP);
        op(g, OP_i32_gt_u);
        let need_r = open(g, f, OP_if_);
        emitPackedSoaSyncSubLens(g, f, plan, h_base, h_len);
        for s in 0..plan.stream_count {
            let sub_slot, sub_gen = emitLoadPackedSubHandle(g, f, plan, h_base, s);
            lget(g, sub_slot);
            lget(g, sub_gen);
            lget(g, need);
            i32Const(g, plan.stream_stride[s]);
            callf(g, rt.reserve);
        }
        emitPackedSoaRefreshCache(g, f, plan, h_base, need);
        close(g, f);
    } else if plan.mode == PACKED_SPLIT_SUM && !rt.has_fork {
        lget(g, need);
        lget(g, h_base);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, packedSplitCapOff(plan, 0));
        op(g, OP_i32_gt_u);
        let need_r = open(g, f, OP_if_);
        let sub_slot, sub_gen = emitLoadPackedSubHandle(g, f, plan, h_base, 0);
        let sub_entry = emitPackedSubEntryAddr(g, f, sub_slot);
        lget(g, sub_entry); lget(g, h_len); op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
        lget(g, sub_slot); lget(g, sub_gen); lget(g, need); i32Const(g, 1); callf(g, rt.reserve);
        lget(g, h_base);
        lget(g, sub_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, packedSplitBaseOff(plan, 0));
        lget(g, h_base); lget(g, need); op(g, OP_i32_store); uleb(g, 2); uleb(g, packedSplitCapOff(plan, 0));
        close(g, f);
    } else {
        let limit = if plan.mode == PACKED_SOA { plan.stream_count } else { 1 };
        for s in 0..limit {
            let sub_slot, sub_gen = emitLoadPackedSubHandle(g, f, plan, h_base, s);
            lget(g, sub_slot);
            lget(g, sub_gen);
            lget(g, need);
            i32Const(g, plan.stream_stride[s]);
            callf(g, rt.reserve);
        }
    }
    if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
    return container, squid_direct_types::Error.none;
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
            if lerr != squid_direct_types::Error.none { return neverVal(), lerr; }
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
    if cerr != squid_direct_types::Error.none { return neverVal(), g.typeFailure(g.units[f.unit - 1], id); }
    let ci_loc = local32(g, f);
    lget(g, tags_base);
    lget(g, idx_local);
    op(g, OP_i32_add);
    op(g, OP_i32_load8_u); uleb(g, 0); uleb(g, 0);
    lset(g, ci_loc);
    let result, rerr = fresh(g, f, plan.elem_ty, id);
    if rerr != squid_direct_types::Error.none { return result, rerr; }
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
            if lerr != squid_direct_types::Error.none { return neverVal(), lerr; }
            lget(g, cur_ptrs[s]);
            i32Const(g, plan.stream_stride[s]);
            op(g, OP_i32_add);
            lset(g, cur_ptrs[s]);
            payload = loaded;
        }
        let wrapped, werr = wrapVariant(g, f, plan.elem_ty, vtag, payload, id);
        if werr != squid_direct_types::Error.none { return neverVal(), werr; }
        let cperr = copy(g, f, wrapped, result, id);
        if cperr != squid_direct_types::Error.none { return neverVal(), cperr; }
        br(g, f, OP_br, done);
        close(g, f);
    }
    op(g, OP_unreachable_);
    close(g, f);
    return result, squid_direct_types::Error.none;
}

// Helper: copy flat/bulk bytes from `src` (array/view/flat-packed) into `dst` (array/flat-packed).
fn emitFlatBulkExtend(g: Generator&, f: Fn&, dst: Val, src: Val, elem_ty: Ty, id: u32, selective: bool) -> Val, Error {
    let step, sterr = stride(g, f, elem_ty, id);
    if sterr != squid_direct_types::Error.none { return neverVal(), sterr; }
    let src_len, slerr = lengthOf(g, f, src, id);
    if slerr != squid_direct_types::Error.none { return neverVal(), slerr; }
    let dst_len, dlerr = lengthOf(g, f, dst, id);
    if dlerr != squid_direct_types::Error.none { return neverVal(), dlerr; }
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
    op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base);
    lset(g, dst_base);
    let dst_ptr = emitOffsetAddress(g, f, dst_base, dst_len, step);
    var src_ptr: u32 = 0;
    if tagOf(g, src.ty) == squid_direct_types::Tag.view {
        let cv = findCheckedView(f, w(g, src, 0), w(g, src, 1), w(g, src, 2), w(g, src, 3));
        if cv >= 0 { src_ptr = f.checked_views[cv].base; }
        else { src_ptr = emitOffsetAddress(g, f, baseOf(g, f, src), w(g, src, 2), step); }
    } else {
        src_ptr = baseOf(g, f, src);
    }
    let copy_bytes = emitScaledBytes(g, f, src_len, step);
    if rt.has_fork {
        recordBeforeWrite(g, f, w(g, dst, 0), dst_entry, squid_direct_runtime::entry_length, 4);
    }
    lget(g, dst_ptr);
    lget(g, src_ptr);
    lget(g, copy_bytes);
    memoryCopyOp(g);
    lget(g, dst_entry);
    lget(g, next_len);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    close(g, f);
    if selective { invalidateCheckedOwner(g, f, dst); } else { invalidateCheckedContainers(f); }
    return dst, squid_direct_types::Error.none;
}

// Handles `extend` whenever `dst` OR `src` is `Tag.packed`.
fn emitPackedExtend(g: Generator&, f: Fn&, dst: Val, src: Val, src_core_ty: TId, id: u32, selective: bool = false) -> Val, Error {
    let dst_is_packed = tagOf(g, dst.ty) == squid_direct_types::Tag.packed;
    let src_is_packed = tagOf(g, src.ty) == squid_direct_types::Tag.packed;
    let elem_ty, eerr = elementOf(g, f, dst.ty, id);
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let plan, perr = computePackedPlan(g, f, elem_ty, id);
    if perr != squid_direct_types::Error.none { return neverVal(), perr; }
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
        if plan.mode == PACKED_SOA && !rt.has_fork {
            emitPackedSoaSyncSubLens(g, f, plan, dst_h_base, dst_h_len);
            emitPackedSoaSyncSubLens(g, f, plan, src_h_base, src_h_len);
        } else if plan.mode == PACKED_SPLIT_SUM && !rt.has_fork {
            emitPackedSplitSyncSubLens(g, f, plan, dst_h_base, dst_h_len);
            emitPackedSplitSyncSubLens(g, f, plan, src_h_base, src_h_len);
        }
        for s in 0..plan.stream_count {
            let step = plan.stream_stride[s];
            let ds_slot, ds_gen = emitLoadPackedSubHandle(g, f, plan, dst_h_base, s);
            let ss_slot, ss_gen = emitLoadPackedSubHandle(g, f, plan, src_h_base, s);
            let ds_entry = local32(g, f);
            let ss_entry = local32(g, f);
            let ds_len = local32(g, f);
            let ss_len = local32(g, f);
            let next_sub = local32(g, f);
            lget(g, ds_slot); lget(g, ds_gen); callf(g, rt.check); ltee(g, ds_entry);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length); lset(g, ds_len);
            lget(g, ss_slot); lget(g, ss_gen); callf(g, rt.check); ltee(g, ss_entry);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length); lset(g, ss_len);
            let sub_ne = open(g, f, OP_block);
            lget(g, ss_len);
            op(g, OP_i32_eqz);
            opIndex(g, OP_br_if, 0);
            lget(g, ds_len); lget(g, ss_len); op(g, OP_i32_add); ltee(g, next_sub);
            lget(g, ds_len); op(g, OP_i32_lt_u); trap(g, f);
            lget(g, ds_slot); lget(g, ds_gen); lget(g, next_sub); i32Const(g, step); callf(g, rt.reserve);
            let ds_base = local32(g, f);
            let ss_base = local32(g, f);
            lget(g, ds_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base); lset(g, ds_base);
            lget(g, ss_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base); lset(g, ss_base);
            let dst_ptr = emitOffsetAddress(g, f, ds_base, ds_len, step);
            let copy_bytes = emitScaledBytes(g, f, ss_len, step);
            if rt.has_fork {
                recordBeforeWrite(g, f, ds_slot, ds_entry, squid_direct_runtime::entry_length, 4);
            }
            lget(g, dst_ptr);
            lget(g, ss_base);
            lget(g, copy_bytes);
            memoryCopyOp(g);
            lget(g, ds_entry);
            lget(g, next_sub);
            op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
            close(g, f);
        }
        if plan.mode == PACKED_SOA && !rt.has_fork {
            let cur_cap = local32(g, f);
            let final_cap = local32(g, f);
            lget(g, dst_h_base);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, PACKED_SOA_HDR_CAP);
            ltee(g, cur_cap);
            lget(g, next_h_len);
            lget(g, cur_cap);
            lget(g, next_h_len);
            op(g, OP_i32_ge_u);
            op(g, OP_select);
            lset(g, final_cap);
            emitPackedSoaRefreshCache(g, f, plan, dst_h_base, final_cap);
        } else if plan.mode == PACKED_SPLIT_SUM && !rt.has_fork {
            emitPackedSplitRefreshAll(g, f, plan, dst_h_base, false);
        }
        if rt.has_fork {
            recordBeforeWrite(g, f, w(g, dst, 0), dst_h_entry, squid_direct_runtime::entry_length, 4);
        }
        lget(g, dst_h_entry);
        lget(g, next_h_len);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
        close(g, f);
        if selective { invalidateCheckedOwner(g, f, dst); } else { invalidateCheckedContainers(f); }
        return dst, squid_direct_types::Error.none;
    }

    // General element-by-element loop (handles cross-kind array <-> packed and nested containers).
    let src_len, slerr = lengthOf(g, f, src, id);
    if slerr != squid_direct_types::Error.none { return neverVal(), slerr; }
    if dst_is_packed {
        let _, rerr = emitPackedReserve(g, f, dst, src_len, id, selective);
        if rerr != squid_direct_types::Error.none { return neverVal(), rerr; }
    } else {
        let dst_len, dlerr = lengthOf(g, f, dst, id);
        if dlerr != squid_direct_types::Error.none { return neverVal(), dlerr; }
        let step, sterr = stride(g, f, elem_ty, id);
        if sterr != squid_direct_types::Error.none { return neverVal(), sterr; }
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
            tags_base = emitLoadPackedSubBase(g, f, plan, src_h_base, 0);
            for s in 1..plan.stream_count { cur_ptrs[s] = emitLoadPackedSubBase(g, f, plan, src_h_base, s); }
        } else {
            for s in 0..plan.stream_count { cur_ptrs[s] = emitLoadPackedSubBase(g, f, plan, src_h_base, s); }
        }
        let idx = constLocal(g, f, 0);
        let exit = open(g, f, OP_block);
        let top = open(g, f, OP_loop);
        lget(g, idx); lget(g, src_len); op(g, OP_i32_ge_u); br(g, f, OP_br_if, exit);
        let decoded, derr = emitPackedDecodeStep(g, f, plan, cur_ptrs[..], tags_base, idx, id);
        if derr != squid_direct_types::Error.none { return neverVal(), derr; }
        var to_push = decoded;
        if holds {
            let copied, cerr = deepCopyValue(g, f, decoded, elem_ty, id, 0);
            if cerr != squid_direct_types::Error.none { return neverVal(), cerr; }
            to_push = copied;
        }
        if dst_is_packed {
            let _, perr2 = emitPackedPushVal(g, f, dst, to_push, id, selective);
            if perr2 != squid_direct_types::Error.none { return neverVal(), perr2; }
        } else {
            let _, perr2 = emitStoragePushVal(g, f, dst, to_push, id, selective);
            if perr2 != squid_direct_types::Error.none { return neverVal(), perr2; }
        }
        lget(g, idx); i32Const(g, 1); op(g, OP_i32_add); lset(g, idx);
        br(g, f, OP_br, top);
        close(g, f);
        close(g, f);
    } else {
        // Source is Tag.array, Tag.view, or PACKED_FLAT.
        let step, sterr = stride(g, f, elem_ty, id);
        if sterr != squid_direct_types::Error.none { return neverVal(), sterr; }
        let idx = constLocal(g, f, 0);
        let exit = open(g, f, OP_block);
        let top = open(g, f, OP_loop);
        lget(g, idx); lget(g, src_len); op(g, OP_i32_ge_u); br(g, f, OP_br_if, exit);
        var elem_val = neverVal();
        if src_is_packed {
            let src_base, _ = ensureCheckedArray(g, f, src);
            let src_addr = emitOffsetAddress(g, f, src_base, idx, step);
            let loaded, lerr = loadElement(g, f, src_addr, 0, elem_ty, id);
            if lerr != squid_direct_types::Error.none { return neverVal(), lerr; }
            elem_val = loaded;
        } else {
            let loaded, rerr = readElement(g, f, src, idx, id, src_core_ty, false);
            if rerr != squid_direct_types::Error.none { return neverVal(), rerr; }
            elem_val = loaded;
        }
        var to_push = elem_val;
        if holds {
            let copied, cerr = deepCopyValue(g, f, elem_val, elem_ty, id, 0);
            if cerr != squid_direct_types::Error.none { return neverVal(), cerr; }
            to_push = copied;
        }
        if dst_is_packed {
            let _, perr2 = emitPackedPushVal(g, f, dst, to_push, id, selective);
            if perr2 != squid_direct_types::Error.none { return neverVal(), perr2; }
        } else {
            let _, perr2 = emitStoragePushVal(g, f, dst, to_push, id, selective);
            if perr2 != squid_direct_types::Error.none { return neverVal(), perr2; }
        }
        lget(g, idx); i32Const(g, 1); op(g, OP_i32_add); lset(g, idx);
        br(g, f, OP_br, top);
        close(g, f);
        close(g, f);
    }
    if selective { invalidateCheckedOwner(g, f, dst); } else { invalidateCheckedContainers(f); }
    return dst, squid_direct_types::Error.none;
}

recursive fn emitPackedDeepCopy(g: Generator&, f: Fn&, value: Val, ty: Ty, id: u32, depth: i64) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, ty, id);
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let plan, perr = computePackedPlan(g, f, elem_ty, id);
    if perr != squid_direct_types::Error.none { return neverVal(), perr; }
    let holds = holdsContainer(g, elem_ty, 0);
    let rt = g.runtime_();
    noteAllocation(f);

    if plan.mode == PACKED_FLAT {
        let step, sterr = stride(g, f, elem_ty, id);
        if sterr != squid_direct_types::Error.none { return neverVal(), sterr; }
        if !holds {
            lget(g, w(g, value, 0));
            lget(g, w(g, value, 1));
            i32Const(g, step);
            i32Const(g, 0);
            callf(g, rt.copy);
            let handle, herr = pop(g, f, ty, id);
            if herr != squid_direct_types::Error.none { return handle, herr; }
            recordMutable(g, f, handle);
            return handle, squid_direct_types::Error.none;
        }
        let src_base, length = ensureCheckedArray(g, f, value);
        let dst, derr = emitPackedWithCapacity(g, f, ty, length, true, id);
        if derr != squid_direct_types::Error.none { return dst, derr; }
        let idx = constLocal(g, f, 0);
        let exit = open(g, f, OP_block);
        let top = open(g, f, OP_loop);
        lget(g, idx); lget(g, length); op(g, OP_i32_ge_u); br(g, f, OP_br_if, exit);
        let src_addr = emitOffsetAddress(g, f, src_base, idx, step);
        let elem_val, lerr = loadElement(g, f, src_addr, 0, elem_ty, id);
        if lerr != squid_direct_types::Error.none { return neverVal(), lerr; }
        let copied, cerr = deepCopyValue(g, f, elem_val, elem_ty, id, depth + 1);
        if cerr != squid_direct_types::Error.none { return neverVal(), cerr; }
        let _, perr2 = emitPackedPushVal(g, f, dst, copied, id, true);
        if perr2 != squid_direct_types::Error.none { return neverVal(), perr2; }
        lget(g, idx); i32Const(g, 1); op(g, OP_i32_add); lset(g, idx);
        br(g, f, OP_br, top);
        close(g, f);
        close(g, f);
        return dst, squid_direct_types::Error.none;
    }

    let src_h_base, length = ensureCheckedArray(g, f, value);
    if !holds {
        if plan.mode == PACKED_SOA && !rt.has_fork {
            emitPackedSoaSyncSubLens(g, f, plan, src_h_base, length);
        } else if plan.mode == PACKED_SPLIT_SUM && !rt.has_fork {
            emitPackedSplitSyncSubLens(g, f, plan, src_h_base, length);
        }
        let header_bytes = packedHeaderBytes(plan);
        let new_h_base = local32(g, f);
        i32Const(g, header_bytes);
        callf(g, rt.stack);
        lset(g, new_h_base);
        for s in 0..plan.stream_count {
            let sub_slot, sub_gen = emitLoadPackedSubHandle(g, f, plan, src_h_base, s);
            let ns = local32(g, f);
            let ng = local32(g, f);
            lget(g, sub_slot);
            lget(g, sub_gen);
            i32Const(g, plan.stream_stride[s]);
            i32Const(g, 0);
            callf(g, rt.copy);
            lset(g, ng);
            lset(g, ns);
            let off = packedSubOff(plan, s);
            lget(g, new_h_base); lget(g, ns); op(g, OP_i32_store); uleb(g, 2); uleb(g, off);
            lget(g, new_h_base); lget(g, ng); op(g, OP_i32_store); uleb(g, 2); uleb(g, off + 4);
        }
        if plan.mode == PACKED_SOA {
            emitPackedSoaRefreshCache(g, f, plan, new_h_base, length);
        } else if plan.mode == PACKED_SPLIT_SUM {
            emitPackedSplitRefreshAll(g, f, plan, new_h_base, false);
        }
        lget(g, new_h_base);
        lget(g, length);
        i32Const(g, header_bytes);
        callf(g, rt.open);
        let handle, herr = pop(g, f, ty, id);
        if herr != squid_direct_types::Error.none { return handle, herr; }
        recordMutable(g, f, handle);
        return handle, squid_direct_types::Error.none;
    }

    let dst, derr = emitPackedWithCapacity(g, f, ty, length, true, id);
    if derr != squid_direct_types::Error.none { return dst, derr; }
    var cur_ptrs: u32[16] = [0; 16];
    var tags_base: u32 = 0;
    if plan.mode == PACKED_SPLIT_SUM {
        tags_base = emitLoadPackedSubBase(g, f, plan, src_h_base, 0);
        for s in 1..plan.stream_count { cur_ptrs[s] = emitLoadPackedSubBase(g, f, plan, src_h_base, s); }
    } else {
        for s in 0..plan.stream_count { cur_ptrs[s] = emitLoadPackedSubBase(g, f, plan, src_h_base, s); }
    }
    let idx = constLocal(g, f, 0);
    let exit = open(g, f, OP_block);
    let top = open(g, f, OP_loop);
    lget(g, idx); lget(g, length); op(g, OP_i32_ge_u); br(g, f, OP_br_if, exit);
    let decoded, decerr = emitPackedDecodeStep(g, f, plan, cur_ptrs[..], tags_base, idx, id);
    if decerr != squid_direct_types::Error.none { return neverVal(), decerr; }
    let copied, cerr = deepCopyValue(g, f, decoded, elem_ty, id, depth + 1);
    if cerr != squid_direct_types::Error.none { return neverVal(), cerr; }
    let _, perr2 = emitPackedPushVal(g, f, dst, copied, id, true);
    if perr2 != squid_direct_types::Error.none { return neverVal(), perr2; }
    lget(g, idx); i32Const(g, 1); op(g, OP_i32_add); lset(g, idx);
    br(g, f, OP_br, top);
    close(g, f);
    close(g, f);
    return dst, squid_direct_types::Error.none;
}

// Persists a packed container into deeply-immutable static const pool slots (mode = 2).
recursive fn emitPackedPersist(g: Generator&, f: Fn&, src_slot: u32, src_gen: u32, ty: Ty, id: u32, depth: i64) -> u32, u32, Error {
    let elem_ty, eerr = elementOf(g, f, ty, id);
    if eerr != squid_direct_types::Error.none { return 0, 0, eerr; }
    let plan, perr = computePackedPlan(g, f, elem_ty, id);
    if perr != squid_direct_types::Error.none { return 0, 0, perr; }
    let rt = g.runtime_();
    if plan.mode == PACKED_FLAT {
        let step, serr = stride(g, f, elem_ty, id);
        if serr != squid_direct_types::Error.none { return 0, 0, serr; }
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
        if eherr != squid_direct_types::Error.none { return 0, 0, eherr; }
        if elem_holds {
            let aerr = persistArrayElements(g, f, p_slot, p_gen, elem_ty, step, id, depth + 1);
            if aerr != squid_direct_types::Error.none { return 0, 0, aerr; }
        }
        return p_slot, p_gen, squid_direct_types::Error.none;
    }
    let h_entry = local32(g, f);
    let h_base = local32(g, f);
    let h_len = local32(g, f);
    lget(g, src_slot); lget(g, src_gen); callf(g, rt.check); ltee(g, h_entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base); lset(g, h_base);
    lget(g, h_entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length); lset(g, h_len);
    if plan.mode == PACKED_SOA && !rt.has_fork {
        emitPackedSoaSyncSubLens(g, f, plan, h_base, h_len);
    } else if plan.mode == PACKED_SPLIT_SUM && !rt.has_fork {
        emitPackedSplitSyncSubLens(g, f, plan, h_base, h_len);
    }
    let header_bytes = packedHeaderBytes(plan);
    let p_h_base = local32(g, f);
    i32Const(g, header_bytes);
    callf(g, rt.alloc_persistent);
    lset(g, p_h_base);
    for s in 0..plan.stream_count {
        let sub_slot, sub_gen = emitLoadPackedSubHandle(g, f, plan, h_base, s);
        let ps = local32(g, f);
        let pg = local32(g, f);
        lget(g, sub_slot);
        lget(g, sub_gen);
        i32Const(g, plan.stream_stride[s]);
        i32Const(g, 2);
        callf(g, rt.persist);
        lset(g, pg);
        lset(g, ps);
        let off = packedSubOff(plan, s);
        lget(g, p_h_base); lget(g, ps); op(g, OP_i32_store); uleb(g, 2); uleb(g, off);
        lget(g, p_h_base); lget(g, pg); op(g, OP_i32_store); uleb(g, 2); uleb(g, off + 4);
        let sholds, sherr = g.contentsHoldMemory(plan.stream_ty[s]);
        if sherr != squid_direct_types::Error.none { return 0, 0, sherr; }
        if sholds {
            let aerr = persistArrayElements(g, f, ps, pg, plan.stream_ty[s], plan.stream_stride[s], id, depth + 1);
            if aerr != squid_direct_types::Error.none { return 0, 0, aerr; }
        }
    }
    if plan.mode == PACKED_SOA {
        let zero_cap = constLocal(g, f, 0);
        emitPackedSoaRefreshCache(g, f, plan, p_h_base, zero_cap);
    } else if plan.mode == PACKED_SPLIT_SUM {
        emitPackedSplitRefreshAll(g, f, plan, p_h_base, true);
    }
    let p_slot = local32(g, f);
    let p_gen = local32(g, f);
    lget(g, p_h_base);
    lget(g, h_len);
    i32Const(g, header_bytes | squid_direct_runtime::static_pool_flag);
    callf(g, rt.open_persistent);
    lset(g, p_gen);
    lset(g, p_slot);
    return p_slot, p_gen, squid_direct_types::Error.none;
}

// ---- Touched-column analysis for PACKED_SOA `for p in packed:` loops ----

fn soaProjectFieldPos(
    g: Generator&,
    m: const Module&,
    proj_id: u32,
    inner_ty: Ty,
    is_nominal: bool,
) -> i64 {
    let proj = m.projection(proj_id);
    let variants = m.projectionVariants(proj_id);
    var name_sym = proj.field;
    if variants.len != 0 {
        if !is_nominal || variants.len != 1 || proj.nominal.decl == 0 { return -1; }
        var found = false;
        for nom, ni in m.nominals {
            if !sameNominal(nom.identity, proj.nominal) { continue; }
            for ci in m.nominalConstructors(ni as u32) {
                let ctor = m.constructors[ci];
                if ctor.tag != variants[0].tag { continue; }
                let payload = m.types.node(ctor.payload);
                if payload.tag != squid_check_types::Tag.record || variants[0].field >= payload.b { return -1; }
                name_sym = m.types.recordField(payload, variants[0].field).name;
                found = true;
                break;
            }
            break;
        }
        if !found { return -1; }
    }
    let sp = m.fieldSpelling(name_sym);
    if !sp.present { return -1; }
    let fname = g.types.fieldName(sp.value);
    let pos = g.types.findField(inner_ty, fname);
    if pos < 0 || pos >= 16 { return -1; }
    return pos;
}

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
                let pos = soaProjectFieldPos(g, m, n.b, plan.soa_inner_ty, plan.soa_is_nominal);
                if pos < 0 { return false; }
                used_fields |= (1 as u32) << (pos as u32);
                return true;
            }
            return analyzeSoaBodyUses(g, m, n.a, binding, plan, used_fields, budget);
        },
        constant, constructor_function, primitive_function, operation_value, type_constructor => { return true; },
        break_ => {
            for ch in m.breakValues(node_id) {
                if !analyzeSoaBodyUses(g, m, ch, binding, plan, used_fields, budget) { return false; }
            }
            return true;
        },
        bind => { return analyzeSoaBodyUses(g, m, n.b, binding, plan, used_fields, budget); },
        pattern_bind => {
            return analyzeSoaBodyUses(g, m, n.b, binding, plan, used_fields, budget) &&
                   analyzeSoaBodyUses(g, m, n.c, binding, plan, used_fields, budget);
        },
        suite, block_, product, record, array, array_op, storage => {
            for ch in m.children(node_id) {
                if !analyzeSoaBodyUses(g, m, ch, binding, plan, used_fields, budget) { return false; }
            }
            return true;
        },
        call => {
            for ch in m.call(node_id).arguments {
                if !analyzeSoaBodyUses(g, m, ch, binding, plan, used_fields, budget) { return false; }
            }
            return true;
        },
        scalar, associated, logical, apply => {
            return analyzeSoaBodyUses(g, m, n.a, binding, plan, used_fields, budget) &&
                   analyzeSoaBodyUses(g, m, n.b, binding, plan, used_fields, budget);
        },
        if_value, if_stmt => {
            return analyzeSoaBodyUses(g, m, n.a, binding, plan, used_fields, budget) &&
                   analyzeSoaBodyUses(g, m, n.b, binding, plan, used_fields, budget) &&
                   analyzeSoaBodyUses(g, m, n.c, binding, plan, used_fields, budget);
        },
        construct => { return analyzeSoaBodyUses(g, m, n.b, binding, plan, used_fields, budget); },
        return_, result_associated => { return analyzeSoaBodyUses(g, m, n.a, binding, plan, used_fields, budget); },
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
                if sel.kind == squid_check_core::UpdateKind.index && !analyzeSoaBodyUses(g, m, sel.index, binding, plan, used_fields, budget) {
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
    if soa_loop_depth == 0 { return neverVal(), false, squid_direct_types::Error.none; }
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let b = localRef(m, n.a);
    if b == 0 { return neverVal(), false, squid_direct_types::Error.none; }
    var d = soa_loop_depth - 1;
    while d >= 0 {
        if soa_loop_binding[d] == b {
            if !soa_loop_is_record[d] { return neverVal(), false, squid_direct_types::Error.none; }
            let is_nom = tagOf(g, soa_loop_ty[d]) == squid_direct_types::Tag.nominal;
            let pos = soaProjectFieldPos(g, m, n.b, soa_loop_inner_ty[d], is_nom);
            if pos < 0 { return neverVal(), false, squid_direct_types::Error.none; }
            let slot = d * 16 + pos;
            if !soa_loop_field_loaded[slot] { return neverVal(), false, squid_direct_types::Error.none; }
            return Val { soa_loop_field_ty[slot], soa_loop_field_start[slot], soa_loop_field_len[slot] }, true, squid_direct_types::Error.none;
        }
        d -= 1;
    }
    return neverVal(), false, squid_direct_types::Error.none;
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
        if pn.tag != squid_check_core::PatternTag.constructor { return false; }
        if pn.b == 0 { return false; }
        inner_pat = pn.b;
    }
    let ip = m.pattern(inner_pat);
    if !plan.soa_is_record {
        if ip.tag != squid_check_core::PatternTag.product { return false; }
        let children = m.patternChildren(inner_pat);
        if children.len != plan.soa_field_count { return false; }
        for ch, idx in children {
            if m.pattern(ch).tag != squid_check_core::PatternTag.wildcard {
                field_pats[idx] = ch;
                used_fields |= (1 as u32) << (idx as u32);
            }
        }
        return true;
    }
    // Record destructuring (`PatternTag.record_payload` or `PatternTag.product` with record pattern type).
    if ip.tag == squid_check_core::PatternTag.record_payload {
        let rec_ty_node = m.types.node(ip.ty);
        if rec_ty_node.tag != squid_check_types::Tag.record { return false; }
        let inner_prod = ip.b;
        let children = m.patternChildren(inner_prod);
        if children.len != (rec_ty_node.b as i64) { return false; }
        for ch, idx in children {
            if m.pattern(ch).tag == squid_check_core::PatternTag.wildcard { continue; }
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
    if ip.tag == squid_check_core::PatternTag.product {
        let rec_ty_node = m.types.node(ip.ty);
        if rec_ty_node.tag != squid_check_types::Tag.record { return false; }
        let children = m.patternChildren(inner_pat);
        if children.len != (rec_ty_node.b as i64) { return false; }
        for ch, idx in children {
            if m.pattern(ch).tag == squid_check_core::PatternTag.wildcard { continue; }
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
                if sel.kind == squid_check_core::UpdateKind.index && !bodyDoesNotMention(m, sel.index, binding, budget) { return false; }
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
    cases: squid_direct_types::Variants,
    needed_mask: u64&,
    seen_ctor_mask: u64&,
    depth: i64,
) -> bool {
    if depth > 64 || match_id == 0 { return false; }
    let n = m.node(match_id);
    if n.tag != squid_check_core::Tag.match_ { return false; }
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
        if pat.tag == squid_check_core::PatternTag.constructor {
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
            if pat.b != 0 && m.pattern(pat.b).tag != squid_check_core::PatternTag.wildcard {
                needed_mask |= bit;
            }
            var budget: i64 = 512;
            if !bodyDoesNotMention(m, arm.body, binding, budget) { return false; }
        } else if pat.tag == squid_check_core::PatternTag.wildcard || pat.tag == squid_check_core::PatternTag.bind {
            saw_wild = true;
            // For a `caseLevel` binary chain, the fallback arm may bind `binding` to an alias
            // or directly contain a nested `Tag.match_` on `binding`.
            var next_binding = binding;
            if pat.tag == squid_check_core::PatternTag.bind { next_binding = pat.a; }
            let sub = unwrapSingleMatchNode(m, arm.body);
            if sub != 0 && m.matchInputs(sub).len == 1 && localRef(m, m.matchInputs(sub)[0]) == next_binding {
                if !analyzeSplitSumMatchChain(g, m, sub, next_binding, elem_ty, cases, needed_mask, seen_ctor_mask, depth + 1) {
                    return false;
                }
            } else {
                if pat.tag == squid_check_core::PatternTag.bind { return false; }
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
        if n.tag == squid_check_core::Tag.match_ { return cur; }
        if n.tag == squid_check_core::Tag.suite || n.tag == squid_check_core::Tag.block_ {
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

// Flattened representation of a `Tag.match_` (or binary `caseLevel` chain) on a split-sum binding.
struct FlatSplitArm {
    ci: i64 = 0,
    ctor_tag: u32 = 0,
    subpat: u32 = 0,
    body: u32 = 0,
}

struct FlatSplitChain {
    ok: bool = false,
    arm_count: i64 = 0,
    arms: FlatSplitArm[64] = [FlatSplitArm {}; 64],
    has_wild: bool = false,
    wild_body: u32 = 0,
    merges_len: i64 = 0,
    // [arm_idx * 16 + merge_at] -> binding delivering outer merge `merge_at` in flattened arm `arm_idx`
    arm_merge_bind: u32[1024] = [0; 1024],
    wild_merge_bind: u32[16] = [0; 16],
}

recursive fn collectFlatSplitChain(
    g: Generator&,
    m: const Module&,
    match_id: u32,
    binding: u32,
    cases: squid_direct_types::Variants,
    cur_merges: const u32[16]&,
    merges_len: i64,
    out: FlatSplitChain&,
    seen_mask: u64&,
    depth: i64,
) -> bool {
    if depth > 64 || match_id == 0 { return false; }
    let n = m.node(match_id);
    if n.tag != squid_check_core::Tag.match_ { return false; }
    let inputs = m.matchInputs(match_id);
    if inputs.len != 1 || localRef(m, inputs[0]) != binding { return false; }
    let arms = m.matchArms(match_id);
    let local_merges = m.branchMerges(match_id);
    if local_merges.len > 0 && arms.len > 2 { return false; }
    if depth > 0 && local_merges.len > 0 {
        for lm in local_merges {
            var tracked = false;
            for at in 0..merges_len {
                if cur_merges[at] == lm.result { tracked = true; break; }
            }
            if !tracked { return false; }
        }
    }

    var saw_wild = false;
    for arm, ai in arms {
        if arm.guard_ != 0 { return false; }
        let rows = m.armRows(arm);
        if rows.len != 1 { return false; }
        let pats = m.rowPatterns(rows[0]);
        if pats.len != 1 { return false; }
        let pat = m.pattern(pats[0]);

        // Compute the active merge bindings for this arm (ai == 0 -> then, ai == 1 -> else).
        var arm_mb: u32[16] = [0; 16];
        for at in 0..merges_len {
            var mb = cur_merges[at];
            if local_merges.len > 0 && ai < 2 {
                for lm in local_merges {
                    if lm.result == mb {
                        mb = if ai == 0 { lm.then_binding } else { lm.else_binding };
                        break;
                    }
                }
            }
            arm_mb[at] = mb;
        }

        if pat.tag == squid_check_core::PatternTag.constructor {
            if saw_wild || out.arm_count >= 64 { return false; }
            let ctag = m.constructor(pat.a).tag;
            var ci: i64 = -1;
            for pos in 0..(cases.len as i64) {
                if g.types.variant_tags[cases.tags + pos] == ctag { ci = pos; break; }
            }
            if ci < 0 || ci >= 64 { return false; }
            let bit = (1 as u64) << (ci as u64);
            if (seen_mask & bit) != 0 { return false; }
            if pat.b != 0 && !packedPatternIrrefutable(m, pat.b) { return false; }
            seen_mask |= bit;
            let slot = out.arm_count;
            out.arms[slot] = FlatSplitArm { ci: ci, ctor_tag: ctag, subpat: pat.b, body: arm.body };
            for at in 0..merges_len { out.arm_merge_bind[slot * 16 + at] = arm_mb[at]; }
            out.arm_count += 1;
        } else if pat.tag == squid_check_core::PatternTag.wildcard || pat.tag == squid_check_core::PatternTag.bind {
            saw_wild = true;
            var next_binding = binding;
            if pat.tag == squid_check_core::PatternTag.bind { next_binding = pat.a; }
            let sub = unwrapSingleMatchNode(m, arm.body);
            if sub != 0 && m.matchInputs(sub).len == 1 && localRef(m, m.matchInputs(sub)[0]) == next_binding {
                if !collectFlatSplitChain(g, m, sub, next_binding, cases, arm_mb, merges_len, out, seen_mask, depth + 1) {
                    return false;
                }
            } else {
                if pat.tag == squid_check_core::PatternTag.bind || out.has_wild { return false; }
                out.has_wild = true;
                out.wild_body = arm.body;
                for at in 0..merges_len { out.wild_merge_bind[at] = arm_mb[at]; }
            }
        } else {
            return false;
        }
    }
    return true;
}

fn flattenSplitSumMatch(
    g: Generator&,
    m: const Module&,
    id: u32,
    binding: u32,
    cases: squid_direct_types::Variants,
) -> FlatSplitChain {
    var chain = FlatSplitChain {};
    let merges = m.branchMerges(id);
    if merges.len > 16 || (cases.len as i64) > 64 { return chain; }
    chain.merges_len = merges.len;
    var init_mb: u32[16] = [0; 16];
    for merge, at in merges { init_mb[at] = merge.result; }
    var seen_mask: u64 = 0;
    if !collectFlatSplitChain(g, m, id, binding, cases, init_mb, merges.len, chain, seen_mask, 0) {
        return FlatSplitChain {};
    }
    chain.ok = true;
    return chain;
}

// 16-byte v128 uniform-tag run skip plan for dominant zero-payload variants (e.g. `$Tick => acc := self + 1`).
// Shared between `%[T]` (`PACKED_SPLIT_SUM`) and `~[T]` (`SEQ_KIND_PACKED_SUM`).
struct SplitSumHotSkipPlan {
    matched: bool = false,
    ci: u32 = 0,
    upd_count: i64 = 0,
    carry_idx: i64[4] = [0; 4],
    delta_u32: u32[4] = [0; 4],
    const_node: u32[4] = [0; 4],
}

fn analyzeSplitSumHotSkip(
    g: Generator&,
    f: const Fn&,
    loop_id: u32,
    match_root: u32,
    ev_bind: u32,
    elem_ty: Ty,
    plan: const PackedPlan&,
    iteration: Vals,
    slots: Words,
) -> SplitSumHotSkipPlan {
    var hot = SplitSumHotSkipPlan {};
    if match_root == 0 || g.runtime_().has_fork { return hot; }
    let cases, cerr = g.types.variants(elem_ty);
    if cerr != squid_direct_types::Error.none { return hot; }
    let m .= g.units[f.unit - 1];
    let chain = flattenSplitSumMatch(g, m, match_root, ev_bind, cases);
    if !chain.ok { return hot; }
    let carries = m.loopCarries(loop_id);
    if carries.len > 16 { return hot; }
    let outer_merges = m.branchMerges(match_root);

    // Search flattened arms for a zero-payload variant whose body only does constant U32/I32 carry additions.
    for ai in 0..chain.arm_count {
        let ci = chain.arms[ai].ci;
        if ci < 0 || ci >= plan.variant_count || plan.variant_stream[ci] >= 0 { continue; }
        let body_id = chain.arms[ai].body;

        // Collect all top-level statements in arm body; must be only `Tag.bind` (or unit/empty).
        var stmts: u32[8] = [0; 8];
        var slen: i64 = 0;
        var stmts_ok = true;
        if body_id != 0 {
            let bn = m.node(body_id);
            if bn.tag == squid_check_core::Tag.suite || bn.tag == squid_check_core::Tag.block_ {
                let ch = m.children(body_id);
                if ch.len > 8 { stmts_ok = false; }
                else {
                    for s_i in 0..ch.len { stmts[s_i] = ch[s_i]; }
                    slen = ch.len;
                }
            } else if bn.tag == squid_check_core::Tag.constant {
                slen = 0;
            } else {
                stmts[0] = body_id;
                slen = 1;
            }
        }
        if !stmts_ok { continue; }

        // Parse each statement: must be `bind b = carry_iter + const_u32` (or trailing unit constant).
        var def_b: u32[8] = [0; 8];
        var def_src: u32[8] = [0; 8];
        var def_delta: u32[8] = [0; 8];
        var def_cnode: u32[8] = [0; 8];
        var def_len: i64 = 0;
        for si in 0..slen {
            let sn = m.node(stmts[si]);
            if sn.tag == squid_check_core::Tag.constant && si + 1 == slen { continue; }
            if sn.tag != squid_check_core::Tag.bind || sn.c >= 2 { stmts_ok = false; break; }
            let en = m.node(sn.b);
            let is_add = (en.tag == squid_check_core::Tag.scalar || (en.tag == squid_check_core::Tag.associated && en.op != squid_check_core::Op.none)) &&
                en.op == squid_check_core::Op.add && en.b != 0;
            if !is_add { stmts_ok = false; break; }
            let la = localRef(m, en.a);
            let rb = localRef(m, en.b);
            let na = m.node(en.a);
            let nb = m.node(en.b);
            if la != 0 && nb.tag == squid_check_core::Tag.constant {
                def_b[def_len] = sn.a;
                def_src[def_len] = la;
                def_delta[def_len] = nb.a;
                def_cnode[def_len] = en.b;
                def_len += 1;
            } else if rb != 0 && na.tag == squid_check_core::Tag.constant {
                def_b[def_len] = sn.a;
                def_src[def_len] = rb;
                def_delta[def_len] = na.a;
                def_cnode[def_len] = en.a;
                def_len += 1;
            } else {
                stmts_ok = false;
                break;
            }
        }
        if !stmts_ok { continue; }

        // Verify every loop carry maps cleanly through this arm's merges.
        var cand = SplitSumHotSkipPlan { matched: true, ci: ci as u32, .. };
        var all_carries_ok = true;
        for carry, c_idx in carries {
            if carry.backedge == carry.iteration { continue; }
            var merge_at: i64 = -1;
            for om, om_i in outer_merges {
                if om.result == carry.backedge { merge_at = om_i; break; }
            }
            if merge_at < 0 { all_carries_ok = false; break; }
            let arm_b = chain.arm_merge_bind[ai * 16 + merge_at];
            if arm_b == carry.iteration { continue; }
            if g.s.words[slots.start + c_idx] != 0 { all_carries_ok = false; break; }
            let iv = g.s.vals[iteration.start + c_idx];
            let itag = tagOf(g, iv.ty);
            if iv.len != 1 || (itag != squid_direct_types::Tag.u32_ && itag != squid_direct_types::Tag.i32_) {
                all_carries_ok = false; break;
            }
            var found_def = false;
            for di in 0..def_len {
                if def_b[di] == arm_b && def_src[di] == carry.iteration {
                    if cand.upd_count >= 4 { all_carries_ok = false; break; }
                    cand.carry_idx[cand.upd_count] = c_idx;
                    cand.delta_u32[cand.upd_count] = def_delta[di];
                    cand.const_node[cand.upd_count] = def_cnode[di];
                    cand.upd_count += 1;
                    found_def = true;
                    break;
                }
            }
            if !found_def { all_carries_ok = false; break; }
        }
        if all_carries_ok {
            for ui in 0..cand.upd_count {
                squid_direct_relocations::unpatchableOperand(m.unit, cand.const_node[ui]);
            }
            return cand;
        }
    }
    return hot;
}

// Emits inner 16-byte v128 uniform-tag run skip loop (`while tags_end - tags_cur >= 16 && all16 == hot.ci`).
fn emitSplitSumHotRun16(
    g: Generator&,
    f: Fn&,
    hot: const SplitSumHotSkipPlan&,
    iteration: Vals,
    tags_cur: u32,
    tags_end: u32,
    v_hot: u32,
) {
    let run_done = open(g, f, OP_block);
    let run_lp = open(g, f, OP_loop);
    lget(g, tags_end); lget(g, tags_cur); op(g, OP_i32_sub);
    i32Const(g, 16); op(g, OP_i32_lt_u);
    br(g, f, OP_br_if, run_done);
    lget(g, tags_cur);
    simdMemOp(g, SIMD_v128_load, 0, 0);
    if hot.ci == 0 {
        simdOp(g, SIMD_v128_any_true);
        br(g, f, OP_br_if, run_done);
    } else {
        lget(g, v_hot);
        simdOp(g, SIMD_i8x16_eq);
        simdOp(g, SIMD_i8x16_all_true);
        op(g, OP_i32_eqz);
        br(g, f, OP_br_if, run_done);
    }
    for ui in 0..hot.upd_count {
        let cloc = w(g, g.s.vals[iteration.start + hot.carry_idx[ui]], 0);
        let d16: u32 = hot.delta_u32[ui] * 16;
        if d16 != 0 {
            lget(g, cloc);
            i32Const(g, d16);
            op(g, OP_i32_add);
            lset(g, cloc);
        }
    }
    lget(g, tags_cur); i32Const(g, 16); op(g, OP_i32_add); lset(g, tags_cur);
    br(g, f, OP_br, run_lp);
    close(g, f);
    close(g, f);
}

// Intercepts `Tag.match_` on the active fused split-stream loop variable.
recursive fn tryEmitSplitSumMatch(g: Generator&, f: Fn&, id: u32) -> Val, bool, Error {
    if split_sum_depth == 0 { return neverVal(), false, squid_direct_types::Error.none; }
    let m .= g.units[f.unit - 1];
    let inputs = m.matchInputs(id);
    if inputs.len != 1 { return neverVal(), false, squid_direct_types::Error.none; }
    let in_b = localRef(m, inputs[0]);
    if in_b == 0 { return neverVal(), false, squid_direct_types::Error.none; }
    var d = split_sum_depth - 1;
    while d >= 0 {
        if split_sum_binding[d] == in_b { break; }
        d -= 1;
    }
    if d < 0 { return neverVal(), false, squid_direct_types::Error.none; }

    let elem_ty = split_sum_ty[d];
    let ci_loc = split_sum_ci_loc[d];
    let cases, cerr = g.types.variants(elem_ty);
    if cerr != squid_direct_types::Error.none { return neverVal(), false, g.typeFailure(m, id); }
    let info = m.matchInfo(id);
    let merges_len = m.branchMerges(id).len;
    let arms_len = m.matchArms(id).len;
    let result = g.newSlot();
    let merged = newSlots(g, merges_len);
    var falls = false;
    let done = open(g, f, OP_block);

    // Flattened dense `OP_br_table` on `ci_loc` across `caseLevel` chains (supports branchMerges!).
    let flat = flattenSplitSumMatch(g, m, id, in_b, cases);
    let use_br_table = flat.ok && flat.arm_count >= 3 && (cases.len as i64) <= 64;

    if use_br_table {
        var tbl_arm: i64[64] = [-1; 64];
        for ai in 0..flat.arm_count { tbl_arm[flat.arms[ai].ci] = ai; }
        let num_arms = flat.arm_count + (if flat.has_wild { 1 } else { 0 });
        let default_rel: u32 = if flat.has_wild { flat.arm_count as u32 } else { num_arms as u32 };
        let open_blocks = if flat.has_wild { num_arms } else { num_arms + 1 };
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
            let is_wild_arm = flat.has_wild && ai == flat.arm_count;
            var body_id: u32 = 0;
            if is_wild_arm {
                body_id = flat.wild_body;
            } else {
                let fa = flat.arms[ai];
                body_id = fa.body;
                if fa.subpat != 0 && g.units[f.unit - 1].pattern(fa.subpat).tag != squid_check_core::PatternTag.wildcard {
                    let s = split_sum_variant_stream[d * 64 + fa.ci];
                    let pty = g.types.variant_payloads[cases.payloads + fa.ci];
                    var payload_val = Val { pty, 0, 0 };
                    if s >= 0 {
                        let cur_ptr = split_sum_cur_ptrs[d * 16 + s];
                        let step = split_sum_stream_stride[d * 16 + s];
                        let loaded, lerr = loadElement(g, f, cur_ptr, 0, pty, id);
                        if lerr != squid_direct_types::Error.none { return neverVal(), false, lerr; }
                        lget(g, cur_ptr);
                        i32Const(g, step);
                        op(g, OP_i32_add);
                        lset(g, cur_ptr);
                        payload_val = loaded;
                    }
                    let terr = test_(g, f, fa.subpat, payload_val, false, 0, id);
                    if terr != squid_direct_types::Error.none { return neverVal(), false, terr; }
                }
            }
            let body, berr = stmt(g, f, body_id);
            if berr != squid_direct_types::Error.none { return body, false, berr; }
            if body.ty != squid_direct_types::never {
                falls = true;
                if !info.statement {
                    let derr = deliver(g, f, body, result, id);
                    if derr != squid_direct_types::Error.none { return neverVal(), false, derr; }
                }
                for at in 0..merges_len {
                    let binding = if is_wild_arm { flat.wild_merge_bind[at] } else { flat.arm_merge_bind[ai * 16 + at] };
                    let value, present = bindGet(g, f, binding);
                    if present {
                        let derr = deliver(g, f, value, merged + (at as u32), id);
                        if derr != squid_direct_types::Error.none { return neverVal(), false, derr; }
                    }
                }
            }
            br(g, f, OP_br, done);
        }
        if !flat.has_wild {
            close(g, f);
            op(g, OP_unreachable_);
        }
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
        if !falls { return neverVal(), true, squid_direct_types::Error.none; }
        if info.statement { return unitVal(), true, squid_direct_types::Error.none; }
        if g.s.slots[result].present { return g.s.slots[result].value, true, squid_direct_types::Error.none; }
        return neverVal(), true, squid_direct_types::Error.none;
    }

    // Sequential arm dispatch (also handles `caseLevel` binary chains with branchMerges!).
    for arm_index in 0..arms_len {
        let next = open(g, f, OP_block);
        var pat_tag = squid_check_core::PatternTag.wildcard;
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
            if pat_tag == squid_check_core::PatternTag.bind { pat_bind_id = pat.a; }
            if pat_tag == squid_check_core::PatternTag.constructor {
                ctor_tag = pm.constructor(pat.a).tag;
                subpat = pat.b;
            }
        }
        var saved_bind = split_sum_binding[d];
        if pat_tag == squid_check_core::PatternTag.constructor {
            let ci, cierr = variantPosition(g, f, cases, ctor_tag, id);
            if cierr != squid_direct_types::Error.none { return neverVal(), false, cierr; }
            lget(g, ci_loc);
            i32Const(g, ci as u32);
            op(g, OP_i32_ne);
            failIf(g, f, true, next);
            if subpat != 0 && g.units[f.unit - 1].pattern(subpat).tag != squid_check_core::PatternTag.wildcard {
                let s = split_sum_variant_stream[d * 64 + ci];
                let pty = g.types.variant_payloads[cases.payloads + ci];
                var payload_val = Val { pty, 0, 0 };
                if s >= 0 {
                    let cur_ptr = split_sum_cur_ptrs[d * 16 + s];
                    let step = split_sum_stream_stride[d * 16 + s];
                    let loaded, lerr = loadElement(g, f, cur_ptr, 0, pty, id);
                    if lerr != squid_direct_types::Error.none { return neverVal(), false, lerr; }
                    lget(g, cur_ptr);
                    i32Const(g, step);
                    op(g, OP_i32_add);
                    lset(g, cur_ptr);
                    payload_val = loaded;
                }
                let terr = test_(g, f, subpat, payload_val, true, next, id);
                if terr != squid_direct_types::Error.none { return neverVal(), false, terr; }
            }
        } else if pat_tag == squid_check_core::PatternTag.bind {
            split_sum_binding[d] = pat_bind_id;
        }
        let body, berr = stmt(g, f, body_id);
        split_sum_binding[d] = saved_bind;
        if berr != squid_direct_types::Error.none { return body, false, berr; }
        if body.ty != squid_direct_types::never {
            falls = true;
            if !info.statement {
                let derr = deliver(g, f, body, result, id);
                if derr != squid_direct_types::Error.none { return neverVal(), false, derr; }
            }
            if merges_len != 0 && arm_index < 2 {
                for at in 0..merges_len {
                    let merge = g.units[f.unit - 1].branchMerges(id)[at];
                    let binding = if arm_index == 0 { merge.then_binding } else { merge.else_binding };
                    let value, present = bindGet(g, f, binding);
                    if present {
                        let derr = deliver(g, f, value, merged + (at as u32), id);
                        if derr != squid_direct_types::Error.none { return neverVal(), false, derr; }
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
    if !falls { return neverVal(), true, squid_direct_types::Error.none; }
    if info.statement { return unitVal(), true, squid_direct_types::Error.none; }
    if g.s.slots[result].present { return g.s.slots[result].value, true, squid_direct_types::Error.none; }
    return neverVal(), true, squid_direct_types::Error.none;
}

// ---- Packed `for` loop emitter (Flat cursor / SoA columns / Split-stream sums) ----

recursive fn emitPackedLoopCore(
    g: Generator&,
    f: Fn&,
    id: u32,
    info: squid_check_core::LoopInfo,
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
    if eerr != squid_direct_types::Error.none { return eerr; }
    let plan, perr = computePackedPlan(g, f, elem_ty, id);
    if perr != squid_direct_types::Error.none { return perr; }

    // Hoist bases/cursors ONCE before OP_loop!
    let base, _ = ensureCheckedArray(g, f, source);

    // 16-wide (i32) / 8-wide (i64) v128 SIMD fast path for associative scalar / touched-column SoA reductions!
    if !g.runtime_().has_fork && (plan.mode == PACKED_FLAT || plan.mode == PACKED_SOA) {
        let red = analyzeForInRedPlan(g, f, id, info, iteration, slots, elem_ty);
        if red.matched {
            var cols_ok = true;
            var col_starts: u32[4] = [0; 4];
            let elem_bytes: u32 = if red.is_i64 || red.is_f64 { 8 } else { 4 };
            if plan.mode == PACKED_FLAT {
                if red.is_record { cols_ok = false; }
                else { col_starts[0] = emitOffsetAddress(g, f, base, index, elem_bytes); }
            } else {
                if !red.is_record { cols_ok = false; }
                else {
                    for fi in 0..red.field_count {
                        let st = plan.soa_field_stream[red.field_pos[fi]];
                        if st < 0 { cols_ok = false; break; }
                        let cb = emitLoadPackedSubBase(g, f, plan, base, st);
                        col_starts[fi] = emitOffsetAddress(g, f, cb, index, elem_bytes);
                    }
                }
            }
            if cols_ok {
                let acc_loc = w(g, g.s.vals[iteration.start + red.carry_idx], 0);
                lget(g, index); lget(g, end_loc); op(g, OP_i32_lt_u);
                let run_if = open(g, f, OP_if_);
                let count = local32(g, f);
                lget(g, end_loc); lget(g, index); op(g, OP_i32_sub); lset(g, count);
                let col_n = if plan.mode == PACKED_FLAT { 1 } else { red.field_count };
                if red.is_float {
                    emitFloatUnrolledColumnSum(g, f, col_starts, col_n, count, acc_loc, red.is_f64);
                } else {
                    emitSimdColumnSum(g, f, col_starts, col_n, count, acc_loc, red.is_i64, red.is_xor);
                }
                popCheckedArraysAt(f, run_if);
                close(g, f);
                return assign(g, f, iteration, outgoing, id);
            }
        }
    }

    var flat_cur: u32 = 0;
    var flat_step: u32 = 0;
    var cur_ptrs: u32[16] = [0; 16];
    var tags_base: u32 = 0;
    var tags_cur: u32 = 0;
    var tags_end: u32 = 0;

    // Mode-specific static analysis before emitting the loop.
    var soa_virtual = false;
    var soa_destruct = false;
    var soa_used_fields: u32 = 0;
    var soa_bind_id: u32 = 0;
    var soa_field_pats: u32[16] = [0; 16];

    var split_fused = false;
    var split_bind_id: u32 = 0;
    var split_needed_mask: u64 = 0;
    var split_hot = SplitSumHotSkipPlan {};
    var v_hot: u32 = 0xffffffff;

    if plan.mode == PACKED_FLAT {
        let st, sterr = stride(g, f, elem_ty, id);
        if sterr != squid_direct_types::Error.none { return sterr; }
        flat_step = st;
        flat_cur = local32(g, f);
        lget(g, base);
        lset(g, flat_cur);
    } else if plan.mode == PACKED_SOA {
        if info.pattern != 0 {
            let pnode = m.pattern(info.pattern);
            if pnode.tag == squid_check_core::PatternTag.bind && plan.soa_is_record && soa_loop_depth < 8 {
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
                    cur_ptrs[s] = emitLoadPackedSubBase(g, f, plan, base, s);
                }
            }
        } else {
            for s in 0..plan.stream_count {
                cur_ptrs[s] = emitLoadPackedSubBase(g, f, plan, base, s);
            }
        }
    } else {
        // PACKED_SPLIT_SUM
        tags_base = emitLoadPackedSubBase(g, f, plan, base, 0);
        if info.pattern != 0 && m.pattern(info.pattern).tag == squid_check_core::PatternTag.bind && split_sum_depth < 4 && plan.variant_count <= 64 {
            let ev_b = m.pattern(info.pattern).a;
            let match_root = unwrapSingleMatchNode(m, info.body);
            if match_root != 0 {
                let cases, cerr = g.types.variants(elem_ty);
                if cerr == squid_direct_types::Error.none {
                    var nmask: u64 = 0;
                    var smask: u64 = 0;
                    if analyzeSplitSumMatchChain(g, m, match_root, ev_b, elem_ty, cases, nmask, smask, 0) {
                        split_fused = true;
                        split_bind_id = ev_b;
                        split_needed_mask = nmask;
                        split_hot = analyzeSplitSumHotSkip(g, f, id, match_root, ev_b, elem_ty, plan, iteration, slots);
                    }
                }
            }
        }
        if split_fused {
            tags_cur = local32(g, f);
            tags_end = local32(g, f);
            lget(g, tags_base); lget(g, index); op(g, OP_i32_add); lset(g, tags_cur);
            lget(g, tags_base); lget(g, end_loc); op(g, OP_i32_add); lset(g, tags_end);
            if split_hot.matched && split_hot.ci != 0 {
                v_hot = local(g, f, VT_v128);
                i32Const(g, split_hot.ci);
                simdOp(g, SIMD_i8x16_splat);
                lset(g, v_hot);
            }
            for ci in 0..plan.variant_count {
                let s = plan.variant_stream[ci];
                if s >= 0 && ((split_needed_mask >> (ci as u64)) & 1) != 0 {
                    cur_ptrs[s] = emitLoadPackedSubBase(g, f, plan, base, s);
                }
            }
        } else {
            for s in 1..plan.stream_count {
                cur_ptrs[s] = emitLoadPackedSubBase(g, f, plan, base, s);
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
            if oerr != squid_direct_types::Error.none { s_state.scratch.resize(scratch_mark); return oerr; }
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
    let normal_done = open(g, f, OP_block);
    let top = open(g, f, OP_loop);
    f.checked_elems_len = 0;
    let use_tags_ptr = plan.mode == PACKED_SPLIT_SUM && split_fused;
    var current: u32 = 0;
    if use_tags_ptr {
        if split_hot.matched && !release {
            emitSplitSumHotRun16(g, f, split_hot, iteration, tags_cur, tags_end, v_hot);
        }
        lget(g, tags_cur);
        lget(g, tags_end);
        op(g, OP_i32_ge_u);
        br(g, f, OP_br_if, normal_done);
    } else {
        lget(g, index);
        lget(g, end_loc);
        op(g, OP_i32_ge_u);
        br(g, f, OP_br_if, normal_done);
        current = local32(g, f);
        lget(g, index);
        lset(g, current);
        lget(g, index);
        i32Const(g, 1);
        op(g, OP_i32_add);
        lset(g, index);
    }

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
        if lerr != squid_direct_types::Error.none { return lerr; }
        lget(g, flat_cur);
        i32Const(g, flat_step);
        op(g, OP_i32_add);
        lset(g, flat_cur);
        if info.pattern != 0 {
            let terr = test_(g, f, info.pattern, item, false, 0, id);
            if terr != squid_direct_types::Error.none { return terr; }
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
                    if lerr != squid_direct_types::Error.none { return lerr; }
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
                    if lerr != squid_direct_types::Error.none { return lerr; }
                    lget(g, cur_ptrs[s]);
                    i32Const(g, plan.stream_stride[s]);
                    op(g, OP_i32_add);
                    lset(g, cur_ptrs[s]);
                    fv = loaded;
                }
                let terr = test_(g, f, soa_field_pats[fi], fv, false, 0, id);
                if terr != squid_direct_types::Error.none { return terr; }
            }
        } else {
            let item, derr = emitPackedDecodeStep(g, f, plan, cur_ptrs[..], 0, current, id);
            if derr != squid_direct_types::Error.none { return derr; }
            if info.pattern != 0 {
                let terr = test_(g, f, info.pattern, item, false, 0, id);
                if terr != squid_direct_types::Error.none { return terr; }
            }
        }
    } else {
        // PACKED_SPLIT_SUM
        if split_fused {
            let ci_loc = local32(g, f);
            lget(g, tags_cur);
            op(g, OP_i32_load8_u); uleb(g, 0); uleb(g, 0);
            lset(g, ci_loc);
            lget(g, tags_cur);
            i32Const(g, 1);
            op(g, OP_i32_add);
            lset(g, tags_cur);
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
            if derr != squid_direct_types::Error.none { return derr; }
            if info.pattern != 0 {
                let terr = test_(g, f, info.pattern, item, false, 0, id);
                if terr != squid_direct_types::Error.none { return terr; }
            }
        }
    }

    let allocations = f.allocations;
    let stores = f.memory_stores;
    let unused = g.newSlot();
    let s_lbl .= g.s;
    let labels_mark = s_lbl.labels.len;
    s_lbl.labels.push(squid_direct_emit::Label {
        target: id,
        depth: exit,
        result: unused,
        kind: squid_direct_emit::LabelKind.loop_,
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
    if error != squid_direct_types::Error.none {
        f.loop_depth -= 1;
        s_lbl.labels.resize(labels_mark);
        return error;
    }

    if body.ty != squid_direct_types::never {
        let backedge = g.reserveVals(carries.len);
        for carry, at in carries {
            let value, present, rerr = readBindingVal(g, f, carry.backedge, id);
            if rerr != squid_direct_types::Error.none { f.loop_depth -= 1; s_lbl.labels.resize(labels_mark); return rerr; }
            if !present { f.loop_depth -= 1; s_lbl.labels.resize(labels_mark); return g.fail(m, id, "loop carry without a backedge value"); }
            g.s.vals[backedge.start + at] = value;
        }
        let assigned_c = assignCarries(g, f, backedge, iteration, slots, unchanged, release_owner, release_stack, id);
        if assigned_c != squid_direct_types::Error.none { f.loop_depth -= 1; s_lbl.labels.resize(labels_mark); return assigned_c; }
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
    close(g, f); // top
    close(g, f); // normal_done
    let assigned_out = assign(g, f, iteration, outgoing, id);
    if assigned_out != squid_direct_types::Error.none { return assigned_out; }
    close(g, f); // exit
    return squid_direct_types::Error.none;
}
