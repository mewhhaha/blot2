// Design H: Reversible Generative SIMD-RRB Sequence (`~[T]` / `Tag.seq`) for the direct Wasm backend.
// Register layout is always `(slot, gen)` (2 x VT_i32), where `entry.base` points to a
// 48-byte 16-byte-aligned `SeqHeader` and `entry.length` mirrors `total_len`.
//
// Core invariants:
//   - 16-way branchless Wasm v128 SIMD prefix-routed counted RRB internal nodes (144 B).
//   - 6 tagged leaf flavors (all 16-byte aligned; `total_len` uniformly at offset +8):
//       1 = LEAF_FLAT       (contiguous inline C-element slab)
//       2 = LEAF_PACKED_SUM (split-stream sum leaf: 32 inline u8 tags + lazy sub-buffers + SIMD tag rank)
//       3 = LEAF_PACKED_SOA (inline column-major SoA leaf)
//       4 = LEAF_SPAN       (O(1) zero-copy slice into immutable frozen `*#[T]` buffer)
//       5 = LEAF_REPEAT     (O(1) repeated value of arbitrary length)
//       6 = LEAF_RAMP       (O(1) arithmetic progression `start + i * step` for U32)
//   - O(1) whole-sequence `reverse` via `root_rev ^= 1` (edge low bit = per-node rev bit).
//   - Readable inline FocusGap buffer (zipper-in-a-handle): O(1) cursor-local push/pop/
//     push_front/pop_front/insert/remove/get/set; readable when frozen (O(1) freeze & copy).
//   - Lazy 16-byte-aligned bump slab freed at invocation exit (zero owner slots per tree node,
//     zero Wasm overhead for programs that do not use `~[T]`).
//   - O(1) persistent `fork` rollback via monotonic `seq_min_mutable_epoch` bumped on fork entry.
namespace squid_direct_function;
import .function;

let OP_i32_ctz = squid_direct_writer::OP_i32_ctz;
let OP_i32_popcnt = squid_direct_writer::OP_i32_popcnt;

let SEQ_KIND_INTERNAL: u32 = 0;
let SEQ_KIND_FLAT: u32 = 1;
let SEQ_KIND_PACKED_SUM: u32 = 2;
let SEQ_KIND_PACKED_SOA: u32 = 3;
let SEQ_KIND_SPAN: u32 = 4;
let SEQ_KIND_REPEAT: u32 = 5;
let SEQ_KIND_RAMP: u32 = 6;

// SeqHeader (48 bytes, 16-byte aligned)
let SEQ_HDR_BYTES: u32 = 48;
let SEQ_HDR_ROOT: u32 = 0;
let SEQ_HDR_LEN: u32 = 4;
let SEQ_HDR_EPOCH: u32 = 8;
let SEQ_HDR_REV: u32 = 12;
let SEQ_HDR_FOCUS: u32 = 16;
let SEQ_HDR_FSTART: u32 = 20;
let SEQ_HDR_FOLDLEN: u32 = 24;
let SEQ_HDR_FAST_APPEND_EP: u32 = 28;
let SEQ_HDR_FAST_PREPEND_EP: u32 = 32;

// NODE_INTERNAL (144 bytes, 16-byte aligned)
let SEQ_NODE_BYTES: u32 = 144;
let SEQ_NODE_META: u32 = 0;
let SEQ_NODE_EPOCH: u32 = 4;
let SEQ_NODE_LEN: u32 = 8;
let SEQ_NODE_PREFIXES: u32 = 16;
let SEQ_NODE_CHILDREN: u32 = 80;

// FocusGap (16 + C * elem_bytes, 16-byte aligned)
let SEQ_FOC_EPOCH: u32 = 0;
let SEQ_FOC_GSTART: u32 = 4;
let SEQ_FOC_GEND: u32 = 8;
let SEQ_FOC_CAP: u32 = 12;
let SEQ_FOC_DATA: u32 = 16;

// Common leaf header
let SEQ_LEAF_META: u32 = 0;
let SEQ_LEAF_EPOCH: u32 = 4;
let SEQ_LEAF_LEN: u32 = 8;
let SEQ_LEAF_DATA: u32 = 16;

// LEAF_PACKED_SUM offsets (C = 32)
let SEQ_SUM_TAGS: u32 = 16;
let SEQ_SUM_SUB_PTRS: u32 = 48;

// LEAF_SPAN offsets (32 bytes)
let SEQ_SPAN_BYTES: u32 = 32;
let SEQ_SPAN_PTR: u32 = 16;
let SEQ_SPAN_SLOT: u32 = 20;
let SEQ_SPAN_GEN: u32 = 24;

// LEAF_RAMP offsets (32 bytes aligned)
let SEQ_RAMP_BYTES: u32 = 32;
let SEQ_RAMP_START: u32 = 16;
let SEQ_RAMP_STEP: u32 = 20;

struct SeqPlan {
    elem_ty: Ty = 0,
    elem_bytes: u32 = 0,
    leaf_cap: u32 = 32,
    leaf_kind: u32 = 1,
    packed: PackedPlan = PackedPlan {},
    soa_col_off: u32[16] = [0; 16],
    soa_leaf_bytes: u32 = 0,
    sum_leaf_bytes: u32 = 0,
    sum_sub_lens_off: u32 = 0,
    sum_sub_caps_off: u32 = 0,
    flat_leaf_bytes: u32 = 0,
    focus_bytes: u32 = 0,
}

fn align16(v: u32) -> u32 { return (v + 15) & 0xfffffff0; }
fn align4(v: u32) -> u32 { return (v + 3) & 0xfffffffc; }

fn computeSeqPlan(g: Generator&, f: const Fn&, elem_ty: Ty, id: u32) -> SeqPlan, Error {
    let eb, eberr = flatBytes(g, f, elem_ty, id);
    if eberr != squid_direct_types::Error.none { return SeqPlan {}, eberr; }
    let packed, perr = computePackedPlan(g, f, elem_ty, id);
    if perr != squid_direct_types::Error.none { return SeqPlan {}, perr; }
    var sp = SeqPlan {
        elem_ty: elem_ty,
        elem_bytes: eb,
        packed: packed,
        ..
    };
    if packed.mode == PACKED_SPLIT_SUM {
        sp.leaf_cap = 32;
        sp.leaf_kind = SEQ_KIND_PACKED_SUM;
        let k = (packed.stream_count - 1) as u32;
        sp.sum_sub_lens_off = SEQ_SUM_SUB_PTRS + k * 4;
        sp.sum_sub_caps_off = sp.sum_sub_lens_off + k;
        sp.sum_leaf_bytes = align16(sp.sum_sub_caps_off + k);
    } else if packed.mode == PACKED_SOA {
        sp.leaf_cap = if eb <= 128 { 128 } else { 32 };
        sp.leaf_kind = SEQ_KIND_PACKED_SOA;
        var off: u32 = 16;
        for s in 0..packed.stream_count {
            off = align4(off);
            sp.soa_col_off[s] = off;
            off += sp.leaf_cap * packed.stream_stride[s];
        }
        sp.soa_leaf_bytes = align16(off);
    } else {
        sp.leaf_cap = if eb <= 4 { 256 } else if eb <= 16 { 64 } else { 32 };
        sp.leaf_kind = SEQ_KIND_FLAT;
    }
    sp.flat_leaf_bytes = align16(16 + sp.leaf_cap * eb);
    sp.focus_bytes = align16(16 + sp.leaf_cap * eb);
    return sp, squid_direct_types::Error.none;
}

// Helper emission convenience for pushing/popping arbitrary Val words.
fn seqPushVal(g: Generator&, val: Val) {
    for i in 0..(val.len as i64) { lget(g, w(g, val, i)); }
}
fn seqValFromParams(g: Generator&, f: Fn&, ty: Ty, id: u32) -> Val, Error {
    let lay, lerr = g.types.layout(ty);
    if lerr != squid_direct_types::Error.none { return neverVal(), g.typeFailure(g.units[f.unit - 1], id); }
    let start = g.s.words.len as u32;
    for wt in lay { g.s.words.push(local(g, f, wt)); }
    return Val { ty, start, lay.len as u32 }, squid_direct_types::Error.none;
}

// ---- Lazy Seq runtime: globals, 16-byte-aligned bump slab, release, SIMD routing ----

fn ensureSeqRuntime(g: Generator&) -> Error {
    if g.s.seq_rt_ready { return squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return squid_direct_types::Error.unsupported; }
    let rt = g.runtime_();
    g.s.seq_slab_head = g.module.addGlobal(VT_i32, true, 0);
    g.s.seq_bump_ptr = g.module.addGlobal(VT_i32, true, 0);
    g.s.seq_bump_end = g.module.addGlobal(VT_i32, true, 0);
    g.s.seq_epoch = g.module.addGlobal(VT_i32, true, 1);
    g.s.seq_min_mutable_epoch = g.module.addGlobal(VT_i32, true, 1);

    let alloc_fn = g.module.addFunction(g.module.signature([VT_i32], [VT_i32]));
    let release_fn = g.module.addFunction(g.module.signature([], []));
    let simd_fn = g.module.addFunction(g.module.signature([VT_i32, VT_i32], [VT_i32]));
    g.s.seq_alloc_fn = alloc_fn;
    g.s.seq_release_fn = release_fn;
    g.s.seq_simd_find_fn = simd_fn;
    g.s.seq_rt_ready = true;

    let s .= g.s;
    let code_mark = s.code.len;
    let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len;
    let labels_mark = s.labels.len;
    let handles_mark = s.handles.len;
    let handle_cells_mark = s.handle_cells_len;

    // 1. seq_alloc(bytes) -> 16-byte-aligned ptr
    {
        var nf = newFn(g, 1, 0);
        let p_bytes = local(g, nf, VT_i32);
        nf.parameter_words = 1;
        let sz = local32(g, nf);
        let ptr = local32(g, nf);
        let nxt = local32(g, nf);
        let req = local32(g, nf);
        let cbase = local32(g, nf);
        let csize = local32(g, nf);
        // sz = max(16, (bytes + 15) & ~15)
        lget(g, p_bytes);
        i32Const(g, 15);
        op(g, OP_i32_add);
        i32Const(g, 0xfffffff0);
        op(g, OP_i32_and);
        ltee(g, sz);
        op(g, OP_i32_eqz);
        let zif = open(g, nf, OP_if_);
        i32Const(g, 16);
        lset(g, sz);
        close(g, nf);
        // fast path: bump_ptr + sz <= bump_end (and no wrap)
        gget(g, g.s.seq_bump_ptr);
        ltee(g, ptr);
        lget(g, sz);
        op(g, OP_i32_add);
        ltee(g, nxt);
        lget(g, ptr);
        op(g, OP_i32_ge_u);
        lget(g, nxt);
        gget(g, g.s.seq_bump_end);
        op(g, OP_i32_le_u);
        op(g, OP_i32_and);
        let fast = open(g, nf, OP_if_);
        lget(g, nxt);
        gset(g, g.s.seq_bump_ptr);
        lget(g, ptr);
        op(g, OP_return_);
        close(g, nf);
        // slow path: allocate chunk >= 32768 via rt.heap_alloc
        lget(g, sz);
        i32Const(g, 16);
        op(g, OP_i32_add);
        ltee(g, req);
        i32Const(g, 32768);
        lget(g, req);
        i32Const(g, 32768);
        op(g, OP_i32_gt_u);
        op(g, OP_select);
        callf(g, rt.heap_alloc);
        lset(g, csize);
        lset(g, cbase);
        // Link chunk header: +0 = prev head, +4 = actual csize
        lget(g, cbase);
        gget(g, g.s.seq_slab_head);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
        lget(g, cbase);
        lget(g, csize);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, 4);
        lget(g, cbase);
        gset(g, g.s.seq_slab_head);
        lget(g, cbase);
        i32Const(g, 16);
        op(g, OP_i32_add);
        lset(g, ptr);
        lget(g, ptr);
        lget(g, sz);
        op(g, OP_i32_add);
        gset(g, g.s.seq_bump_ptr);
        lget(g, cbase);
        lget(g, csize);
        op(g, OP_i32_add);
        gset(g, g.s.seq_bump_end);
        lget(g, ptr);
        op(g, OP_end);
        finishWith(g, alloc_fn, nf, false, 0, 0, 0);
        squid_direct_relocations::rewind(sites_mark);
        s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    }

    // 2. seq_release_slabs() -> void
    {
        var nf = newFn(g, 1, 0);
        let cur = local32(g, nf);
        let nxt = local32(g, nf);
        let sz = local32(g, nf);
        gget(g, g.s.seq_slab_head);
        lset(g, cur);
        i32Const(g, 0); gset(g, g.s.seq_slab_head);
        i32Const(g, 0); gset(g, g.s.seq_bump_ptr);
        i32Const(g, 0); gset(g, g.s.seq_bump_end);
        i32Const(g, 1); gset(g, g.s.seq_epoch);
        i32Const(g, 1); gset(g, g.s.seq_min_mutable_epoch);
        let exit = open(g, nf, OP_block);
        let lp = open(g, nf, OP_loop);
        lget(g, cur);
        op(g, OP_i32_eqz);
        br(g, nf, OP_br_if, exit);
        lget(g, cur);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);
        lset(g, nxt);
        lget(g, cur);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, 4);
        lset(g, sz);
        lget(g, cur);
        lget(g, sz);
        callf(g, rt.heap_free);
        lget(g, nxt);
        lset(g, cur);
        br(g, nf, OP_br, lp);
        close(g, nf);
        close(g, nf);
        op(g, OP_end);
        finishWith(g, release_fn, nf, false, 0, 0, 0);
        squid_direct_relocations::rewind(sites_mark);
        s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    }

    // 3. seq_simd_find(node_ptr, p) -> j (branchless 16-way v128 prefix search!)
    {
        var nf = newFn(g, 1, 0);
        let node_ptr = local(g, nf, VT_i32);
        let p = local(g, nf, VT_i32);
        nf.parameter_words = 2;
        let vp = local(g, nf, VT_v128);
        let mask = local32(g, nf);
        lget(g, p);
        op(g, OP_prefix_fd); uleb(g, SIMD_i32x4_splat);
        lset(g, vp);
        // lanes 0..3
        lget(g, node_ptr);
        op(g, OP_prefix_fd); uleb(g, SIMD_v128_load); uleb(g, 4); uleb(g, SEQ_NODE_PREFIXES);
        lget(g, vp);
        op(g, OP_prefix_fd); uleb(g, SIMD_i32x4_gt_u);
        op(g, OP_prefix_fd); uleb(g, SIMD_i32x4_bitmask);
        lset(g, mask);
        // lanes 4..7
        lget(g, node_ptr);
        op(g, OP_prefix_fd); uleb(g, SIMD_v128_load); uleb(g, 4); uleb(g, SEQ_NODE_PREFIXES + 16);
        lget(g, vp);
        op(g, OP_prefix_fd); uleb(g, SIMD_i32x4_gt_u);
        op(g, OP_prefix_fd); uleb(g, SIMD_i32x4_bitmask);
        i32Const(g, 4); op(g, OP_i32_shl);
        lget(g, mask); op(g, OP_i32_or); lset(g, mask);
        // lanes 8..11
        lget(g, node_ptr);
        op(g, OP_prefix_fd); uleb(g, SIMD_v128_load); uleb(g, 4); uleb(g, SEQ_NODE_PREFIXES + 32);
        lget(g, vp);
        op(g, OP_prefix_fd); uleb(g, SIMD_i32x4_gt_u);
        op(g, OP_prefix_fd); uleb(g, SIMD_i32x4_bitmask);
        i32Const(g, 8); op(g, OP_i32_shl);
        lget(g, mask); op(g, OP_i32_or); lset(g, mask);
        // lanes 12..15
        lget(g, node_ptr);
        op(g, OP_prefix_fd); uleb(g, SIMD_v128_load); uleb(g, 4); uleb(g, SEQ_NODE_PREFIXES + 48);
        lget(g, vp);
        op(g, OP_prefix_fd); uleb(g, SIMD_i32x4_gt_u);
        op(g, OP_prefix_fd); uleb(g, SIMD_i32x4_bitmask);
        i32Const(g, 12); op(g, OP_i32_shl);
        lget(g, mask); op(g, OP_i32_or);
        op(g, OP_i32_ctz);
        op(g, OP_end);
        finishWith(g, simd_fn, nf, false, 0, 0, 0);
        squid_direct_relocations::rewind(sites_mark);
        s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    }
    return squid_direct_types::Error.none;
}

fn emitSeqSimdFindInline(g: Generator&, nf: const Fn&, node_ptr: u32, p: u32, vp: u32, mask: u32) {
    lget(g, p);
    op(g, OP_prefix_fd); uleb(g, SIMD_i32x4_splat);
    lset(g, vp);
    // lanes 0..3
    lget(g, node_ptr);
    op(g, OP_prefix_fd); uleb(g, SIMD_v128_load); uleb(g, 4); uleb(g, SEQ_NODE_PREFIXES);
    lget(g, vp);
    op(g, OP_prefix_fd); uleb(g, SIMD_i32x4_gt_u);
    op(g, OP_prefix_fd); uleb(g, SIMD_i32x4_bitmask);
    lset(g, mask);
    // lanes 4..7
    lget(g, node_ptr);
    op(g, OP_prefix_fd); uleb(g, SIMD_v128_load); uleb(g, 4); uleb(g, SEQ_NODE_PREFIXES + 16);
    lget(g, vp);
    op(g, OP_prefix_fd); uleb(g, SIMD_i32x4_gt_u);
    op(g, OP_prefix_fd); uleb(g, SIMD_i32x4_bitmask);
    i32Const(g, 4); op(g, OP_i32_shl);
    lget(g, mask); op(g, OP_i32_or); lset(g, mask);
    // lanes 8..11
    lget(g, node_ptr);
    op(g, OP_prefix_fd); uleb(g, SIMD_v128_load); uleb(g, 4); uleb(g, SEQ_NODE_PREFIXES + 32);
    lget(g, vp);
    op(g, OP_prefix_fd); uleb(g, SIMD_i32x4_gt_u);
    op(g, OP_prefix_fd); uleb(g, SIMD_i32x4_bitmask);
    i32Const(g, 8); op(g, OP_i32_shl);
    lget(g, mask); op(g, OP_i32_or); lset(g, mask);
    // lanes 12..15
    lget(g, node_ptr);
    op(g, OP_prefix_fd); uleb(g, SIMD_v128_load); uleb(g, 4); uleb(g, SEQ_NODE_PREFIXES + 48);
    lget(g, vp);
    op(g, OP_prefix_fd); uleb(g, SIMD_i32x4_gt_u);
    op(g, OP_prefix_fd); uleb(g, SIMD_i32x4_bitmask);
    i32Const(g, 12); op(g, OP_i32_shl);
    lget(g, mask); op(g, OP_i32_or);
    op(g, OP_i32_ctz);
}

fn emitSeqForkBump(g: Generator&) -> Error {
    if !g.types.has_seq_type { return squid_direct_types::Error.none; }
    let err = ensureSeqRuntime(g);
    if err != squid_direct_types::Error.none { return err; }
    gget(g, g.s.seq_epoch);
    i32Const(g, 1);
    op(g, OP_i32_add);
    gset(g, g.s.seq_epoch);
    gget(g, g.s.seq_epoch);
    gset(g, g.s.seq_min_mutable_epoch);
    return squid_direct_types::Error.none;
}

fn emitSeqReleaseCall(g: Generator&) {
    if !g.s.seq_rt_ready { return; }
    callf(g, g.s.seq_release_fn);
}

// ---- Shared type-independent internal-node & header helpers ----

fn ensureSeqNextEpoch(g: Generator&) -> u32, Error {
    let err = ensureSeqRuntime(g);
    if err != squid_direct_types::Error.none { return 0, err; }
    let key = squid_direct_emit::key64(0xffffffff, 108);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([], [VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let ep = local32(g, nf);
    gget(g, g.s.seq_epoch);
    i32Const(g, 1);
    op(g, OP_i32_add);
    ltee(g, ep);
    gset(g, g.s.seq_epoch);
    lget(g, ep);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

fn ensureSeqRebuildPrefixes(g: Generator&) -> u32, Error {
    let err = ensureSeqRuntime(g);
    if err != squid_direct_types::Error.none { return 0, err; }
    let key = squid_direct_emit::key64(0xffffffff, 100);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32], []));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let node = local(g, nf, VT_i32);
    nf.parameter_words = 1;
    let meta = local32(g, nf);
    let count = local32(g, nf);
    let acc = local32(g, nf);
    let i = local32(g, nf);
    let clen = local32(g, nf);
    let c0_len = local32(g, nf);
    let uniform = local32(g, nf);
    let sh = local32(g, nf);
    lget(g, node); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_META); ltee(g, meta);
    i32Const(g, 8); op(g, OP_i32_shr_u);
    i32Const(g, 255); op(g, OP_i32_and);
    lset(g, count);
    i32Const(g, 0); lset(g, acc);
    i32Const(g, 0); lset(g, i);
    i32Const(g, 0); lset(g, c0_len);
    lget(g, count); i32Const(g, 2); op(g, OP_i32_ge_u); lset(g, uniform);
    let b1 = open(g, nf, OP_block);
    let l1 = open(g, nf, OP_loop);
    lget(g, i); lget(g, count); op(g, OP_i32_ge_u); br(g, nf, OP_br_if, b1);
    lget(g, node); lget(g, i); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    i32Const(g, 0xfffffffe); op(g, OP_i32_and);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_LEN);
    ltee(g, clen);
    lget(g, acc); op(g, OP_i32_add); lset(g, acc);
    lget(g, node); lget(g, i); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    lget(g, acc);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_PREFIXES);
    lget(g, i); op(g, OP_i32_eqz);
    let is_first = open(g, nf, OP_if_);
    lget(g, clen); lset(g, c0_len);
    lget(g, uniform);
    lget(g, clen); i32Const(g, 2); op(g, OP_i32_ge_u); op(g, OP_i32_and);
    lget(g, clen); lget(g, clen); i32Const(g, 1); op(g, OP_i32_sub); op(g, OP_i32_and); op(g, OP_i32_eqz); op(g, OP_i32_and);
    lset(g, uniform);
    op(g, OP_else_);
    lget(g, i); i32Const(g, 1); op(g, OP_i32_add); lget(g, count); op(g, OP_i32_lt_u);
    let not_last = open(g, nf, OP_if_);
    lget(g, uniform); lget(g, clen); lget(g, c0_len); op(g, OP_i32_eq); op(g, OP_i32_and); lset(g, uniform);
    op(g, OP_else_);
    lget(g, uniform); lget(g, clen); lget(g, c0_len); op(g, OP_i32_le_u); op(g, OP_i32_and); lset(g, uniform);
    close(g, nf);
    close(g, nf);
    lget(g, i); i32Const(g, 1); op(g, OP_i32_add); lset(g, i);
    br(g, nf, OP_br, l1);
    close(g, nf); close(g, nf);
    lget(g, node); lget(g, acc); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_LEN);
    // Pack dense radix shift (1..30) into bits 24..30 of SEQ_NODE_META when uniform power-of-2 children!
    lget(g, c0_len); op(g, OP_i32_ctz);
    i32Const(g, 0);
    lget(g, uniform);
    op(g, OP_select);
    lset(g, sh);
    lget(g, node);
    lget(g, meta); i32Const(g, 0x00ffffff); op(g, OP_i32_and);
    lget(g, sh); i32Const(g, 24); op(g, OP_i32_shl); op(g, OP_i32_or);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_META);
    // Fill inactive lanes count..15 with 0xffffffff
    let b2 = open(g, nf, OP_block);
    let l2 = open(g, nf, OP_loop);
    lget(g, i); i32Const(g, 16); op(g, OP_i32_ge_u); br(g, nf, OP_br_if, b2);
    lget(g, node); lget(g, i); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    i32Const(g, 0xffffffff);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_PREFIXES);
    lget(g, i); i32Const(g, 1); op(g, OP_i32_add); lset(g, i);
    br(g, nf, OP_br, l2);
    close(g, nf); close(g, nf);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

fn ensureSeqNodeNew2(g: Generator&) -> u32, Error {
    let rebuild_fn, rerr = ensureSeqRebuildPrefixes(g);
    if rerr != squid_direct_types::Error.none { return 0, rerr; }
    let key = squid_direct_emit::key64(0xffffffff, 101);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32, VT_i32, VT_i32], [VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let c0 = local(g, nf, VT_i32);
    let c1 = local(g, nf, VT_i32);
    let height = local(g, nf, VT_i32);
    let epoch = local(g, nf, VT_i32);
    nf.parameter_words = 4;
    let node = local32(g, nf);
    i32Const(g, SEQ_NODE_BYTES);
    callf(g, g.s.seq_alloc_fn);
    ltee(g, node);
    // meta = (2 << 8) | (height << 16)
    i32Const(g, 512);
    lget(g, height); i32Const(g, 16); op(g, OP_i32_shl); op(g, OP_i32_or);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_META);
    lget(g, node); lget(g, epoch); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_EPOCH);
    lget(g, node); lget(g, c0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    lget(g, node); lget(g, c1); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN + 4);
    lget(g, node); callf(g, rebuild_fn);
    lget(g, node);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

fn ensureSeqNodeClone(g: Generator&) -> u32, Error {
    let err = ensureSeqRuntime(g);
    if err != squid_direct_types::Error.none { return 0, err; }
    let key = squid_direct_emit::key64(0xffffffff, 102);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32], [VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let src = local(g, nf, VT_i32);
    let epoch = local(g, nf, VT_i32);
    nf.parameter_words = 2;
    let dst = local32(g, nf);
    i32Const(g, SEQ_NODE_BYTES);
    callf(g, g.s.seq_alloc_fn);
    ltee(g, dst);
    lget(g, src);
    i32Const(g, SEQ_NODE_BYTES);
    memoryCopyOp(g);
    lget(g, dst); lget(g, epoch); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_EPOCH);
    lget(g, dst);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

fn ensureSeqNodeUnrev(g: Generator&) -> u32, Error {
    let rebuild_fn, rerr = ensureSeqRebuildPrefixes(g);
    if rerr != squid_direct_types::Error.none { return 0, rerr; }
    let key = squid_direct_emit::key64(0xffffffff, 103);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32], [VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let edge = local(g, nf, VT_i32);
    let epoch = local(g, nf, VT_i32);
    nf.parameter_words = 2;
    let ptr = local32(g, nf);
    let dst = local32(g, nf);
    let meta = local32(g, nf);
    let count = local32(g, nf);
    let i = local32(g, nf);
    lget(g, edge); i32Const(g, 1); op(g, OP_i32_and);
    op(g, OP_i32_eqz);
    let no_rev = open(g, nf, OP_if_);
    lget(g, edge); op(g, OP_return_);
    close(g, nf);
    lget(g, edge); i32Const(g, 0xfffffffe); op(g, OP_i32_and); lset(g, ptr);
    lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_META); ltee(g, meta);
    i32Const(g, 8); op(g, OP_i32_shr_u); i32Const(g, 255); op(g, OP_i32_and); lset(g, count);
    i32Const(g, SEQ_NODE_BYTES); callf(g, g.s.seq_alloc_fn); lset(g, dst);
    lget(g, dst); lget(g, meta); i32Const(g, 0x00ffffff); op(g, OP_i32_and); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_META);
    lget(g, dst); lget(g, epoch); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_EPOCH);
    i32Const(g, 0); lset(g, i);
    let b1 = open(g, nf, OP_block);
    let l1 = open(g, nf, OP_loop);
    lget(g, i); lget(g, count); op(g, OP_i32_ge_u); br(g, nf, OP_br_if, b1);
    lget(g, dst); lget(g, i); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    lget(g, ptr);
    lget(g, count); i32Const(g, 1); op(g, OP_i32_sub); lget(g, i); op(g, OP_i32_sub);
    i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    i32Const(g, 1); op(g, OP_i32_xor);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    lget(g, i); i32Const(g, 1); op(g, OP_i32_add); lset(g, i);
    br(g, nf, OP_br, l1);
    close(g, nf); close(g, nf);
    lget(g, dst); callf(g, rebuild_fn);
    lget(g, dst);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// Slices an un-reversed internal node's children[start..end]. Returns 0 if empty,
// the single child edge if count == 1 (automatic height collapse!), or a fresh node.
fn ensureSeqNodeSlice(g: Generator&) -> u32, Error {
    let rebuild_fn, rerr = ensureSeqRebuildPrefixes(g);
    if rerr != squid_direct_types::Error.none { return 0, rerr; }
    let key = squid_direct_emit::key64(0xffffffff, 104);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32, VT_i32, VT_i32], [VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let node = local(g, nf, VT_i32);
    let start = local(g, nf, VT_i32);
    let end = local(g, nf, VT_i32);
    let epoch = local(g, nf, VT_i32);
    nf.parameter_words = 4;
    let cnt = local32(g, nf);
    let dst = local32(g, nf);
    let height = local32(g, nf);
    lget(g, end); lget(g, start); op(g, OP_i32_le_u);
    let zif = open(g, nf, OP_if_);
    i32Const(g, 0); op(g, OP_return_);
    close(g, nf);
    lget(g, end); lget(g, start); op(g, OP_i32_sub); ltee(g, cnt);
    i32Const(g, 1); op(g, OP_i32_eq);
    let oif = open(g, nf, OP_if_);
    lget(g, node); lget(g, start); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    op(g, OP_return_);
    close(g, nf);
    lget(g, node); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_META);
    i32Const(g, 0x00ff0000); op(g, OP_i32_and); lset(g, height);
    i32Const(g, SEQ_NODE_BYTES); callf(g, g.s.seq_alloc_fn); lset(g, dst);
    lget(g, dst);
    lget(g, cnt); i32Const(g, 8); op(g, OP_i32_shl); lget(g, height); op(g, OP_i32_or);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_META);
    lget(g, dst); lget(g, epoch); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_EPOCH);
    lget(g, dst); i32Const(g, SEQ_NODE_CHILDREN); op(g, OP_i32_add);
    lget(g, node); i32Const(g, SEQ_NODE_CHILDREN); op(g, OP_i32_add);
    lget(g, start); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    lget(g, cnt); i32Const(g, 2); op(g, OP_i32_shl);
    memoryCopyOp(g);
    lget(g, dst); callf(g, rebuild_fn);
    lget(g, dst);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

fn ensureSeqHdrOpen(g: Generator&) -> u32, Error {
    let err = ensureSeqRuntime(g);
    if err != squid_direct_types::Error.none { return 0, err; }
    let key = squid_direct_emit::key64(0xffffffff, 105);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32, VT_i32, VT_i32], [VT_i32, VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let rt = g.runtime_();
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let root_edge = local(g, nf, VT_i32);
    let total_len = local(g, nf, VT_i32);
    let root_rev = local(g, nf, VT_i32);
    let epoch = local(g, nf, VT_i32);
    nf.parameter_words = 4;
    let hdr = local32(g, nf);
    i32Const(g, SEQ_HDR_BYTES); callf(g, g.s.seq_alloc_fn); ltee(g, hdr);
    i32Const(g, 0); i32Const(g, SEQ_HDR_BYTES); memoryFillOp(g);
    lget(g, hdr); lget(g, root_edge); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_ROOT);
    lget(g, hdr); lget(g, total_len); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_LEN);
    lget(g, hdr); lget(g, epoch); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_EPOCH);
    lget(g, hdr); lget(g, root_rev); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_REV);
    lget(g, hdr);
    lget(g, total_len);
    i32Const(g, SEQ_HDR_BYTES);
    callf(g, rt.open);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// O(1) persistent copy / reverse: marks source shared (unlogged so fork rollback never restores stale owner_epoch!),
// clones 48-byte SeqHeader with fresh epoch and root_rev ^= flip_rev.
fn ensureSeqHdrCloneShared(g: Generator&) -> u32, Error {
    let ep_fn, eerr = ensureSeqNextEpoch(g);
    if eerr != squid_direct_types::Error.none { return 0, eerr; }
    let key = squid_direct_emit::key64(0xffffffff, 106);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32, VT_i32], [VT_i32, VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let rt = g.runtime_();
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let slot = local(g, nf, VT_i32);
    let gen = local(g, nf, VT_i32);
    let flip = local(g, nf, VT_i32);
    nf.parameter_words = 3;
    let src_hdr = local32(g, nf);
    let dst_hdr = local32(g, nf);
    let len = local32(g, nf);
    lget(g, slot); lget(g, gen); callf(g, rt.check);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base);
    lset(g, src_hdr);
    // Mark source shared (unlogged write to owner_epoch/fast_epochs = 0 -> safe even across fork!).
    lget(g, src_hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_EPOCH);
    lget(g, src_hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_APPEND_EP);
    lget(g, src_hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_PREPEND_EP);
    i32Const(g, SEQ_HDR_BYTES); callf(g, g.s.seq_alloc_fn); ltee(g, dst_hdr);
    lget(g, src_hdr); i32Const(g, SEQ_HDR_BYTES); memoryCopyOp(g);
    lget(g, dst_hdr); callf(g, ep_fn); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_EPOCH);
    lget(g, dst_hdr);
    lget(g, dst_hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_REV);
    lget(g, flip); op(g, OP_i32_xor);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_REV);
    lget(g, dst_hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_LEN); lset(g, len);
    lget(g, dst_hdr); lget(g, len); i32Const(g, SEQ_HDR_BYTES);
    callf(g, rt.open);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// seq_ensure_writable(slot, gen) -> (entry, hdr, epoch):
// Checks liveness & mutability; if hdr.owner_epoch < seq_min_mutable_epoch, logs 48B hdr + entry.length
// under active fork and assigns a fresh writable epoch.
fn ensureSeqWritable(g: Generator&) -> u32, Error {
    let ep_fn, eerr = ensureSeqNextEpoch(g);
    if eerr != squid_direct_types::Error.none { return 0, eerr; }
    let key = squid_direct_emit::key64(0xffffffff, 109);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32], [VT_i32, VT_i32, VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let rt = g.runtime_();
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let slot = local(g, nf, VT_i32);
    let gen = local(g, nf, VT_i32);
    nf.parameter_words = 2;
    let entry = local32(g, nf);
    let hdr = local32(g, nf);
    let ep = local32(g, nf);
    lget(g, slot); lget(g, gen); callf(g, rt.check); ltee(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_capacity);
    i32Const(g, squid_direct_runtime::static_pool_flag); op(g, OP_i32_and);
    trap(g, nf);
    lget(g, entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base); lset(g, hdr);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_EPOCH); ltee(g, ep);
    gget(g, g.s.seq_min_mutable_epoch);
    op(g, OP_i32_lt_u);
    let need_ep = open(g, nf, OP_if_);
    if rt.has_fork {
        recordBeforeWrite(g, nf, slot, hdr, 0, SEQ_HDR_BYTES);
        recordBeforeWrite(g, nf, slot, entry, squid_direct_runtime::entry_length, 4);
    }
    callf(g, ep_fn); lset(g, ep);
    lget(g, hdr); lget(g, ep); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_EPOCH);
    close(g, nf);
    lget(g, entry); lget(g, hdr); lget(g, ep);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// seq_iter_next_leaf(stack_mem, sp) -> (new_sp, leaf_edge):
// Advances an explicit 8-level traversal stack to the next leaf edge (with propagated rev bit).
fn ensureSeqIterNextLeaf(g: Generator&) -> u32, Error {
    let err = ensureSeqRuntime(g);
    if err != squid_direct_types::Error.none { return 0, err; }
    let key = squid_direct_emit::key64(0xffffffff, 107);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32], [VT_i32, VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let stack = local(g, nf, VT_i32);
    let sp = local(g, nf, VT_i32);
    nf.parameter_words = 2;
    let frame = local32(g, nf);
    let edge = local32(g, nf);
    let pos = local32(g, nf);
    let ptr = local32(g, nf);
    let rev = local32(g, nf);
    let meta = local32(g, nf);
    let count = local32(g, nf);
    let phys_j = local32(g, nf);
    let child = local32(g, nf);
    let lp = open(g, nf, OP_loop);
    lget(g, sp); op(g, OP_i32_eqz);
    let empty_if = open(g, nf, OP_if_);
    i32Const(g, 0); i32Const(g, 0); op(g, OP_return_);
    close(g, nf);
    lget(g, stack); lget(g, sp); i32Const(g, 1); op(g, OP_i32_sub);
    i32Const(g, 3); op(g, OP_i32_shl); op(g, OP_i32_add); ltee(g, frame);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, 0); ltee(g, edge);
    i32Const(g, 0xfffffffe); op(g, OP_i32_and); lset(g, ptr);
    lget(g, edge); i32Const(g, 1); op(g, OP_i32_and); lset(g, rev);
    lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_META); ltee(g, meta);
    i32Const(g, 15); op(g, OP_i32_and);
    lget(g, meta); i32Const(g, 16); op(g, OP_i32_shr_u); i32Const(g, 255); op(g, OP_i32_and); i32Const(g, 1); op(g, OP_i32_eq);
    op(g, OP_i32_or);
    let is_leaf = open(g, nf, OP_if_);
    lget(g, sp); i32Const(g, 1); op(g, OP_i32_sub);
    lget(g, edge);
    op(g, OP_return_);
    close(g, nf);
    // Internal node
    lget(g, frame); op(g, OP_i32_load); uleb(g, 2); uleb(g, 4); lset(g, pos);
    lget(g, meta); i32Const(g, 8); op(g, OP_i32_shr_u); i32Const(g, 255); op(g, OP_i32_and); lset(g, count);
    lget(g, pos); lget(g, count); op(g, OP_i32_ge_u);
    let done_node = open(g, nf, OP_if_);
    lget(g, sp); i32Const(g, 1); op(g, OP_i32_sub); lset(g, sp);
    br(g, nf, OP_br, lp);
    close(g, nf);
    // Advance parent frame pos
    lget(g, frame); lget(g, pos); i32Const(g, 1); op(g, OP_i32_add); op(g, OP_i32_store); uleb(g, 2); uleb(g, 4);
    // phys_j = rev ? (count - 1 - pos) : pos
    lget(g, count); i32Const(g, 1); op(g, OP_i32_sub); lget(g, pos); op(g, OP_i32_sub);
    lget(g, pos);
    lget(g, rev);
    op(g, OP_select);
    lset(g, phys_j);
    lget(g, ptr); lget(g, phys_j); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    lget(g, rev); op(g, OP_i32_xor); lset(g, child);
    // Push child onto stack
    lget(g, stack); lget(g, sp); i32Const(g, 3); op(g, OP_i32_shl); op(g, OP_i32_add); ltee(g, frame);
    lget(g, child); op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
    lget(g, frame); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, 4);
    lget(g, sp); i32Const(g, 1); op(g, OP_i32_add); lset(g, sp);
    br(g, nf, OP_br, lp);
    close(g, nf);
    i32Const(g, 0); i32Const(g, 0);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// ---- Per-element-type leaf helpers (Flat, Packed-Sum with SIMD rank, Packed-SoA, Span, Repeat, Ramp) ----

// Emit SIMD tag rank: #{u < p : tags[u] == ci} for p in 0..31 on LEAF_PACKED_SUM at `leaf_ptr`.
fn emitSeqSumRank(g: Generator&, f: Fn&, leaf_ptr: u32, ci_loc: u32, p_loc: u32) -> u32 {
    let vci = local(g, f, VT_v128);
    let mlo = local32(g, f);
    let rank = local32(g, f);
    lget(g, ci_loc);
    op(g, OP_prefix_fd); uleb(g, SIMD_i8x16_splat);
    lset(g, vci);
    lget(g, leaf_ptr);
    op(g, OP_prefix_fd); uleb(g, SIMD_v128_load); uleb(g, 4); uleb(g, SEQ_SUM_TAGS);
    lget(g, vci);
    op(g, OP_prefix_fd); uleb(g, SIMD_i8x16_eq);
    op(g, OP_prefix_fd); uleb(g, SIMD_i8x16_bitmask);
    lset(g, mlo);
    lget(g, leaf_ptr);
    op(g, OP_prefix_fd); uleb(g, SIMD_v128_load); uleb(g, 4); uleb(g, SEQ_SUM_TAGS + 16);
    lget(g, vci);
    op(g, OP_prefix_fd); uleb(g, SIMD_i8x16_eq);
    op(g, OP_prefix_fd); uleb(g, SIMD_i8x16_bitmask);
    i32Const(g, 16); op(g, OP_i32_shl);
    lget(g, mlo); op(g, OP_i32_or);
    i32Const(g, 1); lget(g, p_loc); op(g, OP_i32_shl); i32Const(g, 1); op(g, OP_i32_sub);
    op(g, OP_i32_and);
    op(g, OP_i32_popcnt);
    lset(g, rank);
    return rank;
}

// Ensure sub-buffer for stream `s` (1..S-1, si = s-1) has capacity > sub_len (lazy 2->4->8->16->32).
fn emitSeqSumEnsureCap(g: Generator&, f: Fn&, leaf_ptr: u32, sp: const SeqPlan&, s: i64) -> u32, u32 {
    let si = (s - 1) as u32;
    let step = sp.packed.stream_stride[s];
    let sub_ptr = local32(g, f);
    let sub_len = local32(g, f);
    let sub_cap = local32(g, f);
    let new_cap = local32(g, f);
    let new_ptr = local32(g, f);
    lget(g, leaf_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_SUM_SUB_PTRS + si * 4); lset(g, sub_ptr);
    lget(g, leaf_ptr); op(g, OP_i32_load8_u); uleb(g, 0); uleb(g, sp.sum_sub_lens_off + si); lset(g, sub_len);
    lget(g, leaf_ptr); op(g, OP_i32_load8_u); uleb(g, 0); uleb(g, sp.sum_sub_caps_off + si); lset(g, sub_cap);
    lget(g, sub_len); lget(g, sub_cap); op(g, OP_i32_ge_u);
    let grow = open(g, f, OP_if_);
    lget(g, sub_cap); i32Const(g, 1); op(g, OP_i32_shl);
    i32Const(g, 2);
    lget(g, sub_cap);
    op(g, OP_select);
    ltee(g, new_cap);
    i32Const(g, 32); op(g, OP_i32_gt_u);
    let cap32 = open(g, f, OP_if_);
    i32Const(g, 32); lset(g, new_cap);
    close(g, f);
    let alloc_b = emitScaledBytes(g, f, new_cap, step);
    lget(g, alloc_b); callf(g, g.s.seq_alloc_fn); lset(g, new_ptr);
    lget(g, sub_len);
    let has_old = open(g, f, OP_if_);
    let copy_b = emitScaledBytes(g, f, sub_len, step);
    lget(g, new_ptr); lget(g, sub_ptr); lget(g, copy_b); memoryCopyOp(g);
    close(g, f);
    lget(g, new_ptr); lset(g, sub_ptr);
    lget(g, leaf_ptr); lget(g, new_ptr); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_SUM_SUB_PTRS + si * 4);
    lget(g, leaf_ptr); lget(g, new_cap); op(g, OP_i32_store8); uleb(g, 0); uleb(g, sp.sum_sub_caps_off + si);
    close(g, f);
    return sub_ptr, sub_len;
}

// Kind 1: seq_leaf_create(epoch) -> leaf_ptr
fn ensureSeqLeafCreate(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let err = ensureSeqRuntime(g);
    if err != squid_direct_types::Error.none { return 0, err; }
    let key = squid_direct_emit::key64(sp.elem_ty, 1);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32], [VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let epoch = local(g, nf, VT_i32);
    nf.parameter_words = 1;
    let leaf = local32(g, nf);
    var alloc_bytes = sp.flat_leaf_bytes;
    if sp.leaf_kind == SEQ_KIND_PACKED_SUM { alloc_bytes = sp.sum_leaf_bytes; }
    else if sp.leaf_kind == SEQ_KIND_PACKED_SOA { alloc_bytes = sp.soa_leaf_bytes; }
    i32Const(g, alloc_bytes); callf(g, g.s.seq_alloc_fn); lset(g, leaf);
    if sp.leaf_kind == SEQ_KIND_PACKED_SUM {
        lget(g, leaf); i32Const(g, 0); i32Const(g, sp.sum_leaf_bytes); memoryFillOp(g);
        lget(g, leaf); i32Const(g, SEQ_SUM_TAGS); op(g, OP_i32_add);
        i32Const(g, 0xff); i32Const(g, 32); memoryFillOp(g);
    }
    lget(g, leaf); i32Const(g, sp.leaf_kind); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_META);
    lget(g, leaf); lget(g, epoch); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_EPOCH);
    lget(g, leaf); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
    lget(g, leaf);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// Kind 2: seq_leaf_clone(leaf_ptr, epoch) -> new_leaf_ptr (canonical leaves only)
fn ensureSeqLeafClone(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let err = ensureSeqRuntime(g);
    if err != squid_direct_types::Error.none { return 0, err; }
    let key = squid_direct_emit::key64(sp.elem_ty, 2);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32], [VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let src = local(g, nf, VT_i32);
    let epoch = local(g, nf, VT_i32);
    nf.parameter_words = 2;
    let dst = local32(g, nf);
    var alloc_bytes = sp.flat_leaf_bytes;
    if sp.leaf_kind == SEQ_KIND_PACKED_SUM { alloc_bytes = sp.sum_leaf_bytes; }
    else if sp.leaf_kind == SEQ_KIND_PACKED_SOA { alloc_bytes = sp.soa_leaf_bytes; }
    i32Const(g, alloc_bytes); callf(g, g.s.seq_alloc_fn); ltee(g, dst);
    lget(g, src); i32Const(g, alloc_bytes); memoryCopyOp(g);
    lget(g, dst); lget(g, epoch); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_EPOCH);
    if sp.leaf_kind == SEQ_KIND_PACKED_SUM {
        for st in 1..sp.packed.stream_count {
            let si = (st - 1) as u32;
            let step = sp.packed.stream_stride[st];
            let old_p = local32(g, nf);
            let old_c = local32(g, nf);
            let new_p = local32(g, nf);
            lget(g, src); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_SUM_SUB_PTRS + si * 4); ltee(g, old_p);
            let nz = open(g, nf, OP_if_);
            lget(g, src); op(g, OP_i32_load8_u); uleb(g, 0); uleb(g, sp.sum_sub_caps_off + si); lset(g, old_c);
            let cbytes = emitScaledBytes(g, nf, old_c, step);
            lget(g, cbytes); callf(g, g.s.seq_alloc_fn); ltee(g, new_p);
            lget(g, old_p); lget(g, cbytes); memoryCopyOp(g);
            lget(g, dst); lget(g, new_p); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_SUM_SUB_PTRS + si * 4);
            close(g, nf);
        }
    }
    lget(g, dst);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// Kind 3: seq_leaf_get(leaf_edge, p) -> val... (ALL 6 leaf flavors + reversal bit!)
fn ensureSeqLeafGet(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let err = ensureSeqRuntime(g);
    if err != squid_direct_types::Error.none { return 0, err; }
    let key = squid_direct_emit::key64(sp.elem_ty, 3);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let lay, lerr = g.types.layout(sp.elem_ty);
    if lerr != squid_direct_types::Error.none { return 0, lerr; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32], lay));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let edge = local(g, nf, VT_i32);
    let p_in = local(g, nf, VT_i32);
    nf.parameter_words = 2;
    let ptr = local32(g, nf);
    let len = local32(g, nf);
    let kind = local32(g, nf);
    let p = local32(g, nf);
    lget(g, edge); i32Const(g, 0xfffffffe); op(g, OP_i32_and); lset(g, ptr);
    lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_LEAF_LEN); lset(g, len);
    lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_LEAF_META); i32Const(g, 15); op(g, OP_i32_and); lset(g, kind);
    // p = (edge & 1) ? (len - 1 - p_in) : p_in
    lget(g, len); i32Const(g, 1); op(g, OP_i32_sub); lget(g, p_in); op(g, OP_i32_sub);
    lget(g, p_in);
    lget(g, edge); i32Const(g, 1); op(g, OP_i32_and);
    op(g, OP_select);
    lset(g, p);

    // Canonical leaf flavor for this elem_ty
    lget(g, kind); i32Const(g, sp.leaf_kind); op(g, OP_i32_eq);
    let canon_if = open(g, nf, OP_if_);
    if sp.leaf_kind == SEQ_KIND_FLAT {
        if sp.elem_bytes == 0 {
            op(g, OP_return_);
        } else {
            let base = local32(g, nf);
            lget(g, ptr); i32Const(g, SEQ_LEAF_DATA); op(g, OP_i32_add); lset(g, base);
            let addr = emitOffsetAddress(g, nf, base, p, sp.elem_bytes);
            let loaded, err2 = loadElement(g, nf, addr, 0, sp.elem_ty, 0);
            if err2 != squid_direct_types::Error.none {
                squid_direct_relocations::rewind(sites_mark);
                s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                return 0, err2;
            }
            seqPushVal(g, loaded);
            op(g, OP_return_);
        }
    } else if sp.leaf_kind == SEQ_KIND_PACKED_SOA {
        let fvals = g.reserveVals(sp.packed.soa_field_count);
        for fi in 0..sp.packed.soa_field_count {
            let st = sp.packed.soa_field_stream[fi];
            let fty = sp.packed.soa_field_ty[fi];
            if st < 0 {
                g.s.vals[fvals.start + fi] = Val { fty, 0, 0 };
            } else {
                let col_base = local32(g, nf);
                lget(g, ptr); i32Const(g, sp.soa_col_off[st]); op(g, OP_i32_add); lset(g, col_base);
                let addr = emitOffsetAddress(g, nf, col_base, p, sp.packed.stream_stride[st]);
                let loaded, err2 = loadElement(g, nf, addr, 0, fty, 0);
                if err2 != squid_direct_types::Error.none {
                    squid_direct_relocations::rewind(sites_mark);
                    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                    return 0, err2;
                }
                g.s.vals[fvals.start + fi] = loaded;
            }
        }
        let assembled, aerr = assembleSoaVal(g, nf, sp.packed, fvals, 0);
        if aerr != squid_direct_types::Error.none {
            squid_direct_relocations::rewind(sites_mark);
            s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
            return 0, aerr;
        }
        seqPushVal(g, assembled);
        op(g, OP_return_);
    } else {
        // SEQ_KIND_PACKED_SUM: load ci = tags[p], compute SIMD rank, decode variant!
        let cases, cerr = g.types.variants(sp.elem_ty);
        if cerr != squid_direct_types::Error.none {
            squid_direct_relocations::rewind(sites_mark);
            s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
            return 0, cerr;
        }
        let ci_loc = local32(g, nf);
        lget(g, ptr); lget(g, p); op(g, OP_i32_add);
        op(g, OP_i32_load8_u); uleb(g, 0); uleb(g, SEQ_SUM_TAGS);
        lset(g, ci_loc);
        for ci in 0..(cases.len as i64) {
            let vtag = g.types.variant_tags[cases.tags + ci];
            let pty = g.types.variant_payloads[cases.payloads + ci];
            let st = sp.packed.variant_stream[ci];
            lget(g, ci_loc); i32Const(g, ci as u32); op(g, OP_i32_eq);
            let arm = open(g, nf, OP_if_);
            var payload = Val { pty, 0, 0 };
            if st >= 1 {
                let rank = emitSeqSumRank(g, nf, ptr, ci_loc, p);
                let sub_base = local32(g, nf);
                lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_SUM_SUB_PTRS + ((st - 1) as u32) * 4);
                lset(g, sub_base);
                let addr = emitOffsetAddress(g, nf, sub_base, rank, sp.packed.stream_stride[st]);
                let loaded, err2 = loadElement(g, nf, addr, 0, pty, 0);
                if err2 != squid_direct_types::Error.none {
                    squid_direct_relocations::rewind(sites_mark);
                    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                    return 0, err2;
                }
                payload = loaded;
            }
            let wrapped, werr = wrapVariant(g, nf, sp.elem_ty, vtag, payload, 0);
            if werr != squid_direct_types::Error.none {
                squid_direct_relocations::rewind(sites_mark);
                s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                return 0, werr;
            }
            seqPushVal(g, wrapped);
            op(g, OP_return_);
            close(g, nf);
        }
        op(g, OP_unreachable_);
    }
    close(g, nf);

    // LEAF_SPAN (kind == 4)
    lget(g, kind); i32Const(g, SEQ_KIND_SPAN); op(g, OP_i32_eq);
    let span_if = open(g, nf, OP_if_);
    if sp.elem_bytes == 0 {
        op(g, OP_return_);
    } else {
        let sbase = local32(g, nf);
        lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_SPAN_PTR); lset(g, sbase);
        let addr = emitOffsetAddress(g, nf, sbase, p, sp.elem_bytes);
        let loaded, err2 = loadElement(g, nf, addr, 0, sp.elem_ty, 0);
        if err2 != squid_direct_types::Error.none {
            squid_direct_relocations::rewind(sites_mark);
            s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
            return 0, err2;
        }
        seqPushVal(g, loaded);
        op(g, OP_return_);
    }
    close(g, nf);

    // LEAF_REPEAT (kind == 5)
    lget(g, kind); i32Const(g, SEQ_KIND_REPEAT); op(g, OP_i32_eq);
    let rep_if = open(g, nf, OP_if_);
    if sp.elem_bytes == 0 {
        op(g, OP_return_);
    } else {
        let rbase = local32(g, nf);
        lget(g, ptr); i32Const(g, SEQ_LEAF_DATA); op(g, OP_i32_add); lset(g, rbase);
        let loaded, err2 = loadElement(g, nf, rbase, 0, sp.elem_ty, 0);
        if err2 != squid_direct_types::Error.none {
            squid_direct_relocations::rewind(sites_mark);
            s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
            return 0, err2;
        }
        seqPushVal(g, loaded);
        op(g, OP_return_);
    }
    close(g, nf);

    // LEAF_RAMP (kind == 6, U32 only)
    if sp.elem_ty == squid_direct_types::u32_ {
        lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_RAMP_START);
        lget(g, p);
        lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_RAMP_STEP);
        op(g, OP_i32_mul);
        op(g, OP_i32_add);
        op(g, OP_return_);
    }
    op(g, OP_unreachable_);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// Kind 4: seq_leaf_append_one(leaf_ptr, val...) -> void (mutable non-full canonical leaf)
fn ensureSeqLeafAppendOne(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let err = ensureSeqRuntime(g);
    if err != squid_direct_types::Error.none { return 0, err; }
    let key = squid_direct_emit::key64(sp.elem_ty, 4);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let lay, lerr = g.types.layout(sp.elem_ty);
    if lerr != squid_direct_types::Error.none { return 0, lerr; }
    var ptypes: ValType[>..] = [VT_i32];
    for wt in lay { ptypes.push(wt); }
    let fn_id = g.module.addFunction(g.module.signature(ptypes[..], []));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let leaf = local(g, nf, VT_i32);
    let val, verr = seqValFromParams(g, nf, sp.elem_ty, 0);
    if verr != squid_direct_types::Error.none {
        squid_direct_relocations::rewind(sites_mark);
        s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
        return 0, verr;
    }
    nf.parameter_words = (1 + lay.len) as u32;
    let idx = local32(g, nf);
    let nlen = local32(g, nf);
    lget(g, leaf); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_LEAF_LEN); lset(g, idx);
    if sp.leaf_kind == SEQ_KIND_FLAT {
        if sp.elem_bytes != 0 {
            let base = local32(g, nf);
            lget(g, leaf); i32Const(g, SEQ_LEAF_DATA); op(g, OP_i32_add); lset(g, base);
            let addr = emitOffsetAddress(g, nf, base, idx, sp.elem_bytes);
            let werr = writeElement(g, nf, addr, 0, val, 0);
            if werr != squid_direct_types::Error.none {
                squid_direct_relocations::rewind(sites_mark);
                s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                return 0, werr;
            }
        }
    } else if sp.leaf_kind == SEQ_KIND_PACKED_SOA {
        var inner_val = val;
        if sp.packed.soa_is_nominal {
            let uw, uerr = unwrapVariant(g, nf, val, sp.packed.soa_nominal_tag, 0);
            if uerr != squid_direct_types::Error.none {
                squid_direct_relocations::rewind(sites_mark);
                s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                return 0, uerr;
            }
            inner_val = uw;
        }
        for fi in 0..sp.packed.soa_field_count {
            let st = sp.packed.soa_field_stream[fi];
            if st < 0 { continue; }
            var fv = neverVal();
            if sp.packed.soa_is_record {
                let got, gerr = recordField(g, nf, inner_val, fi, 0);
                if gerr != squid_direct_types::Error.none {
                    squid_direct_relocations::rewind(sites_mark);
                    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                    return 0, gerr;
                }
                fv = got;
            } else {
                let got, gerr = tupleItem(g, nf, inner_val, fi, 0);
                if gerr != squid_direct_types::Error.none {
                    squid_direct_relocations::rewind(sites_mark);
                    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                    return 0, gerr;
                }
                fv = got;
            }
            let cbase = local32(g, nf);
            lget(g, leaf); i32Const(g, sp.soa_col_off[st]); op(g, OP_i32_add); lset(g, cbase);
            let addr = emitOffsetAddress(g, nf, cbase, idx, sp.packed.stream_stride[st]);
            let werr = writeElement(g, nf, addr, 0, fv, 0);
            if werr != squid_direct_types::Error.none {
                squid_direct_relocations::rewind(sites_mark);
                s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                return 0, werr;
            }
        }
    } else {
        // SEQ_KIND_PACKED_SUM
        let cases, cerr = g.types.variants(sp.elem_ty);
        if cerr != squid_direct_types::Error.none {
            squid_direct_relocations::rewind(sites_mark);
            s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
            return 0, cerr;
        }
        let vtag_loc = local32(g, nf);
        let terr = emitValueTag(g, nf, val, 0);
        if terr != squid_direct_types::Error.none {
            squid_direct_relocations::rewind(sites_mark);
            s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
            return 0, terr;
        }
        lset(g, vtag_loc);
        let done = open(g, nf, OP_block);
        for ci in 0..(cases.len as i64) {
            let vtag = g.types.variant_tags[cases.tags + ci];
            let st = sp.packed.variant_stream[ci];
            lget(g, vtag_loc); i32Const(g, vtag); op(g, OP_i32_eq);
            let arm = open(g, nf, OP_if_);
            lget(g, leaf); lget(g, idx); op(g, OP_i32_add);
            i32Const(g, ci as u32);
            op(g, OP_i32_store8); uleb(g, 0); uleb(g, SEQ_SUM_TAGS);
            if st >= 1 {
                let si = (st - 1) as u32;
                let sub_ptr, sub_len = emitSeqSumEnsureCap(g, nf, leaf, sp, st);
                let addr = emitOffsetAddress(g, nf, sub_ptr, sub_len, sp.packed.stream_stride[st]);
                let uw, uerr = unwrapVariant(g, nf, val, vtag, 0);
                if uerr != squid_direct_types::Error.none {
                    squid_direct_relocations::rewind(sites_mark);
                    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                    return 0, uerr;
                }
                let werr = writeElement(g, nf, addr, 0, uw, 0);
                if werr != squid_direct_types::Error.none {
                    squid_direct_relocations::rewind(sites_mark);
                    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                    return 0, werr;
                }
                lget(g, leaf); lget(g, sub_len); i32Const(g, 1); op(g, OP_i32_add);
                op(g, OP_i32_store8); uleb(g, 0); uleb(g, sp.sum_sub_lens_off + si);
            }
            br(g, nf, OP_br, done);
            close(g, nf);
        }
        close(g, nf);
    }
    lget(g, idx); i32Const(g, 1); op(g, OP_i32_add); lset(g, nlen);
    lget(g, leaf); lget(g, nlen); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// Kind 5: seq_leaf_set_canon(leaf_edge, p, val..., epoch) -> new_edge (canonical leaves kind <= 3 only)
fn ensureSeqLeafSetCanon(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let clone_fn, cerr = ensureSeqLeafClone(g, sp);
    if cerr != squid_direct_types::Error.none { return 0, cerr; }
    let key = squid_direct_emit::key64(sp.elem_ty, 5);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let lay, lerr = g.types.layout(sp.elem_ty);
    if lerr != squid_direct_types::Error.none { return 0, lerr; }
    var ptypes: ValType[>..] = [VT_i32, VT_i32];
    for wt in lay { ptypes.push(wt); }
    ptypes.push(VT_i32);
    let fn_id = g.module.addFunction(g.module.signature(ptypes[..], [VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let edge = local(g, nf, VT_i32);
    let p_in = local(g, nf, VT_i32);
    let val, verr = seqValFromParams(g, nf, sp.elem_ty, 0);
    if verr != squid_direct_types::Error.none {
        squid_direct_relocations::rewind(sites_mark);
        s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
        return 0, verr;
    }
    let epoch = local(g, nf, VT_i32);
    nf.parameter_words = (3 + lay.len) as u32;
    let ptr = local32(g, nf);
    let rev = local32(g, nf);
    let len = local32(g, nf);
    let p = local32(g, nf);
    lget(g, edge); i32Const(g, 0xfffffffe); op(g, OP_i32_and); lset(g, ptr);
    lget(g, edge); i32Const(g, 1); op(g, OP_i32_and); lset(g, rev);
    lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_LEAF_LEN); lset(g, len);
    lget(g, len); i32Const(g, 1); op(g, OP_i32_sub); lget(g, p_in); op(g, OP_i32_sub);
    lget(g, p_in); lget(g, rev); op(g, OP_select); lset(g, p);
    // CoW clone if leaf.epoch != epoch
    lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_LEAF_EPOCH);
    lget(g, epoch); op(g, OP_i32_ne);
    let cow = open(g, nf, OP_if_);
    lget(g, ptr); lget(g, epoch); callf(g, clone_fn); lset(g, ptr);
    close(g, nf);

    if sp.leaf_kind == SEQ_KIND_FLAT {
        if sp.elem_bytes != 0 {
            let base = local32(g, nf);
            lget(g, ptr); i32Const(g, SEQ_LEAF_DATA); op(g, OP_i32_add); lset(g, base);
            let addr = emitOffsetAddress(g, nf, base, p, sp.elem_bytes);
            let werr = writeElement(g, nf, addr, 0, val, 0);
            if werr != squid_direct_types::Error.none {
                squid_direct_relocations::rewind(sites_mark);
                s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                return 0, werr;
            }
        }
    } else if sp.leaf_kind == SEQ_KIND_PACKED_SOA {
        var inner_val = val;
        if sp.packed.soa_is_nominal {
            let uw, uerr = unwrapVariant(g, nf, val, sp.packed.soa_nominal_tag, 0);
            if uerr != squid_direct_types::Error.none {
                squid_direct_relocations::rewind(sites_mark);
                s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                return 0, uerr;
            }
            inner_val = uw;
        }
        for fi in 0..sp.packed.soa_field_count {
            let st = sp.packed.soa_field_stream[fi];
            if st < 0 { continue; }
            var fv = neverVal();
            if sp.packed.soa_is_record {
                let got, gerr = recordField(g, nf, inner_val, fi, 0);
                if gerr != squid_direct_types::Error.none {
                    squid_direct_relocations::rewind(sites_mark);
                    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                    return 0, gerr;
                }
                fv = got;
            } else {
                let got, gerr = tupleItem(g, nf, inner_val, fi, 0);
                if gerr != squid_direct_types::Error.none {
                    squid_direct_relocations::rewind(sites_mark);
                    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                    return 0, gerr;
                }
                fv = got;
            }
            let cbase = local32(g, nf);
            lget(g, ptr); i32Const(g, sp.soa_col_off[st]); op(g, OP_i32_add); lset(g, cbase);
            let addr = emitOffsetAddress(g, nf, cbase, p, sp.packed.stream_stride[st]);
            let werr = writeElement(g, nf, addr, 0, fv, 0);
            if werr != squid_direct_types::Error.none {
                squid_direct_relocations::rewind(sites_mark);
                s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                return 0, werr;
            }
        }
    } else {
        // SEQ_KIND_PACKED_SUM: update old/new variant payload using SIMD rank!
        let cases, cerr2 = g.types.variants(sp.elem_ty);
        if cerr2 != squid_direct_types::Error.none {
            squid_direct_relocations::rewind(sites_mark);
            s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
            return 0, cerr2;
        }
        let old_ci = local32(g, nf);
        let new_ci = local32(g, nf);
        let vtag_loc = local32(g, nf);
        lget(g, ptr); lget(g, p); op(g, OP_i32_add);
        op(g, OP_i32_load8_u); uleb(g, 0); uleb(g, SEQ_SUM_TAGS); lset(g, old_ci);
        let terr = emitValueTag(g, nf, val, 0);
        if terr != squid_direct_types::Error.none {
            squid_direct_relocations::rewind(sites_mark);
            s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
            return 0, terr;
        }
        lset(g, vtag_loc);
        // Determine new_ci
        for ci in 0..(cases.len as i64) {
            let vtag = g.types.variant_tags[cases.tags + ci];
            lget(g, vtag_loc); i32Const(g, vtag); op(g, OP_i32_eq);
            let mif = open(g, nf, OP_if_);
            i32Const(g, ci as u32); lset(g, new_ci);
            close(g, nf);
        }
        lget(g, old_ci); lget(g, new_ci); op(g, OP_i32_eq);
        let same_ci = open(g, nf, OP_if_);
        // Same variant: overwrite payload in place at SIMD rank!
        for ci in 0..(cases.len as i64) {
            let st = sp.packed.variant_stream[ci];
            if st < 1 { continue; }
            let vtag = g.types.variant_tags[cases.tags + ci];
            lget(g, new_ci); i32Const(g, ci as u32); op(g, OP_i32_eq);
            let arm = open(g, nf, OP_if_);
            let rank = emitSeqSumRank(g, nf, ptr, new_ci, p);
            let sub_base = local32(g, nf);
            lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_SUM_SUB_PTRS + ((st - 1) as u32) * 4); lset(g, sub_base);
            let addr = emitOffsetAddress(g, nf, sub_base, rank, sp.packed.stream_stride[st]);
            let uw, uerr = unwrapVariant(g, nf, val, vtag, 0);
            if uerr != squid_direct_types::Error.none {
                squid_direct_relocations::rewind(sites_mark);
                s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                return 0, uerr;
            }
            let werr = writeElement(g, nf, addr, 0, uw, 0);
            if werr != squid_direct_types::Error.none {
                squid_direct_relocations::rewind(sites_mark);
                s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                return 0, werr;
            }
            close(g, nf);
        }
        op(g, OP_else_);
        // Different variant: remove from old_ci sub-buffer, insert into new_ci sub-buffer, update tags[p]
        for ci in 0..(cases.len as i64) {
            let st = sp.packed.variant_stream[ci];
            if st < 1 { continue; }
            let si = (st - 1) as u32;
            let step = sp.packed.stream_stride[st];
            lget(g, old_ci); i32Const(g, ci as u32); op(g, OP_i32_eq);
            let arm = open(g, nf, OP_if_);
            let r_old = emitSeqSumRank(g, nf, ptr, old_ci, p);
            let sub_base = local32(g, nf);
            let sub_len = local32(g, nf);
            let tail = local32(g, nf);
            lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_SUM_SUB_PTRS + si * 4); lset(g, sub_base);
            lget(g, ptr); op(g, OP_i32_load8_u); uleb(g, 0); uleb(g, sp.sum_sub_lens_off + si); lset(g, sub_len);
            lget(g, sub_len); i32Const(g, 1); op(g, OP_i32_sub); lset(g, sub_len);
            lget(g, sub_len); lget(g, r_old); op(g, OP_i32_sub); ltee(g, tail);
            let mv = open(g, nf, OP_if_);
            let dst_a = emitOffsetAddress(g, nf, sub_base, r_old, step);
            let src_a = local32(g, nf);
            lget(g, dst_a); i32Const(g, step); op(g, OP_i32_add); lset(g, src_a);
            let mbytes = emitScaledBytes(g, nf, tail, step);
            lget(g, dst_a); lget(g, src_a); lget(g, mbytes); memoryCopyOp(g);
            close(g, nf);
            lget(g, ptr); lget(g, sub_len); op(g, OP_i32_store8); uleb(g, 0); uleb(g, sp.sum_sub_lens_off + si);
            close(g, nf);
        }
        for ci in 0..(cases.len as i64) {
            let st = sp.packed.variant_stream[ci];
            if st < 1 { continue; }
            let si = (st - 1) as u32;
            let step = sp.packed.stream_stride[st];
            let vtag = g.types.variant_tags[cases.tags + ci];
            lget(g, new_ci); i32Const(g, ci as u32); op(g, OP_i32_eq);
            let arm = open(g, nf, OP_if_);
            let r_new = emitSeqSumRank(g, nf, ptr, new_ci, p);
            let sub_base, sub_len = emitSeqSumEnsureCap(g, nf, ptr, sp, st);
            let tail = local32(g, nf);
            let src_a = emitOffsetAddress(g, nf, sub_base, r_new, step);
            lget(g, sub_len); lget(g, r_new); op(g, OP_i32_sub); ltee(g, tail);
            let mv = open(g, nf, OP_if_);
            let dst_a = local32(g, nf);
            lget(g, src_a); i32Const(g, step); op(g, OP_i32_add); lset(g, dst_a);
            let mbytes = emitScaledBytes(g, nf, tail, step);
            lget(g, dst_a); lget(g, src_a); lget(g, mbytes); memoryCopyOp(g);
            close(g, nf);
            let uw, uerr = unwrapVariant(g, nf, val, vtag, 0);
            if uerr != squid_direct_types::Error.none {
                squid_direct_relocations::rewind(sites_mark);
                s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                return 0, uerr;
            }
            let werr = writeElement(g, nf, src_a, 0, uw, 0);
            if werr != squid_direct_types::Error.none {
                squid_direct_relocations::rewind(sites_mark);
                s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                return 0, werr;
            }
            lget(g, ptr); lget(g, sub_len); i32Const(g, 1); op(g, OP_i32_add);
            op(g, OP_i32_store8); uleb(g, 0); uleb(g, sp.sum_sub_lens_off + si);
            close(g, nf);
        }
        lget(g, ptr); lget(g, p); op(g, OP_i32_add); lget(g, new_ci);
        op(g, OP_i32_store8); uleb(g, 0); uleb(g, SEQ_SUM_TAGS);
        close(g, nf);
    }
    lget(g, ptr); lget(g, rev); op(g, OP_i32_or);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// Kind 6: seq_leaf_merge(a_edge, b_edge, epoch) -> merged_leaf_ptr (two canonical leaves, len_a + len_b <= C)
fn ensureSeqLeafMerge(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let create_fn, crerr = ensureSeqLeafCreate(g, sp);
    if crerr != squid_direct_types::Error.none { return 0, crerr; }
    let get_fn, gerr = ensureSeqLeafGet(g, sp);
    if gerr != squid_direct_types::Error.none { return 0, gerr; }
    let app_fn, aerr = ensureSeqLeafAppendOne(g, sp);
    if aerr != squid_direct_types::Error.none { return 0, aerr; }
    let key = squid_direct_emit::key64(sp.elem_ty, 6);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32, VT_i32], [VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let a_edge = local(g, nf, VT_i32);
    let b_edge = local(g, nf, VT_i32);
    let epoch = local(g, nf, VT_i32);
    nf.parameter_words = 3;
    let out = local32(g, nf);
    let la = local32(g, nf);
    let lb = local32(g, nf);
    let i = local32(g, nf);
    lget(g, a_edge); i32Const(g, 0xfffffffe); op(g, OP_i32_and); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_LEAF_LEN); lset(g, la);
    lget(g, b_edge); i32Const(g, 0xfffffffe); op(g, OP_i32_and); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_LEAF_LEN); lset(g, lb);
    lget(g, epoch); callf(g, create_fn); lset(g, out);
    // Fast bulk memcpy when LEAF_FLAT and both unreversed
    if sp.leaf_kind == SEQ_KIND_FLAT && sp.elem_bytes != 0 {
        lget(g, a_edge); lget(g, b_edge); op(g, OP_i32_or); i32Const(g, 1); op(g, OP_i32_and);
        op(g, OP_i32_eqz);
        let fast = open(g, nf, OP_if_);
        let ba = emitScaledBytes(g, nf, la, sp.elem_bytes);
        let bb = emitScaledBytes(g, nf, lb, sp.elem_bytes);
        let tot = local32(g, nf);
        lget(g, out); i32Const(g, SEQ_LEAF_DATA); op(g, OP_i32_add);
        lget(g, a_edge); i32Const(g, SEQ_LEAF_DATA); op(g, OP_i32_add);
        lget(g, ba); memoryCopyOp(g);
        lget(g, out); i32Const(g, SEQ_LEAF_DATA); op(g, OP_i32_add); lget(g, ba); op(g, OP_i32_add);
        lget(g, b_edge); i32Const(g, SEQ_LEAF_DATA); op(g, OP_i32_add);
        lget(g, bb); memoryCopyOp(g);
        lget(g, la); lget(g, lb); op(g, OP_i32_add); lset(g, tot);
        lget(g, out); lget(g, tot); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
        lget(g, out); op(g, OP_return_);
        close(g, nf);
    }
    i32Const(g, 0); lset(g, i);
    let b1 = open(g, nf, OP_block); let l1 = open(g, nf, OP_loop);
    lget(g, i); lget(g, la); op(g, OP_i32_ge_u); br(g, nf, OP_br_if, b1);
    lget(g, out); lget(g, a_edge); lget(g, i); callf(g, get_fn); callf(g, app_fn);
    lget(g, i); i32Const(g, 1); op(g, OP_i32_add); lset(g, i);
    br(g, nf, OP_br, l1);
    close(g, nf); close(g, nf);
    i32Const(g, 0); lset(g, i);
    let b2 = open(g, nf, OP_block); let l2 = open(g, nf, OP_loop);
    lget(g, i); lget(g, lb); op(g, OP_i32_ge_u); br(g, nf, OP_br_if, b2);
    lget(g, out); lget(g, b_edge); lget(g, i); callf(g, get_fn); callf(g, app_fn);
    lget(g, i); i32Const(g, 1); op(g, OP_i32_add); lset(g, i);
    br(g, nf, OP_br, l2);
    close(g, nf); close(g, nf);
    lget(g, out);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// Kind 7: seq_leaf_split(leaf_edge, k, epoch) -> (left_edge, right_edge)
// O(1) on LEAF_SPAN, LEAF_REPEAT, LEAF_RAMP! Exact split on canonical leaves!
fn ensureSeqLeafSplit(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let create_fn, crerr = ensureSeqLeafCreate(g, sp);
    if crerr != squid_direct_types::Error.none { return 0, crerr; }
    let get_fn, gerr = ensureSeqLeafGet(g, sp);
    if gerr != squid_direct_types::Error.none { return 0, gerr; }
    let app_fn, aerr = ensureSeqLeafAppendOne(g, sp);
    if aerr != squid_direct_types::Error.none { return 0, aerr; }
    let key = squid_direct_emit::key64(sp.elem_ty, 7);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32, VT_i32], [VT_i32, VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let edge = local(g, nf, VT_i32);
    let k = local(g, nf, VT_i32);
    let epoch = local(g, nf, VT_i32);
    nf.parameter_words = 3;
    let ptr = local32(g, nf);
    let len = local32(g, nf);
    let kind = local32(g, nf);
    let lout = local32(g, nf);
    let rout = local32(g, nf);
    let i = local32(g, nf);
    lget(g, k); op(g, OP_i32_eqz);
    let k0 = open(g, nf, OP_if_);
    i32Const(g, 0); lget(g, edge); op(g, OP_return_);
    close(g, nf);
    lget(g, edge); i32Const(g, 0xfffffffe); op(g, OP_i32_and); lset(g, ptr);
    lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_LEAF_LEN); lset(g, len);
    lget(g, k); lget(g, len); op(g, OP_i32_ge_u);
    let kn = open(g, nf, OP_if_);
    lget(g, edge); i32Const(g, 0); op(g, OP_return_);
    close(g, nf);
    // If rev == 1: split unreversed at len - k, then swap & flip both halves!
    lget(g, edge); i32Const(g, 1); op(g, OP_i32_and);
    let rev_if = open(g, nf, OP_if_);
    lget(g, ptr); lget(g, len); lget(g, k); op(g, OP_i32_sub); lget(g, epoch);
    callf(g, fn_id);
    lset(g, rout); lset(g, lout);
    lget(g, rout); i32Const(g, 1); op(g, OP_i32_xor);
    lget(g, lout); i32Const(g, 1); op(g, OP_i32_xor);
    op(g, OP_return_);
    close(g, nf);

    lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_LEAF_META); i32Const(g, 15); op(g, OP_i32_and); lset(g, kind);

    // LEAF_SPAN: O(1) two 32-byte spans!
    lget(g, kind); i32Const(g, SEQ_KIND_SPAN); op(g, OP_i32_eq);
    let span_if = open(g, nf, OP_if_);
    let sptr = local32(g, nf);
    let sslot = local32(g, nf);
    let sgen = local32(g, nf);
    lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_SPAN_PTR); lset(g, sptr);
    lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_SPAN_SLOT); lset(g, sslot);
    lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_SPAN_GEN); lset(g, sgen);
    i32Const(g, SEQ_SPAN_BYTES); callf(g, g.s.seq_alloc_fn); lset(g, lout);
    lget(g, lout); i32Const(g, SEQ_KIND_SPAN); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_META);
    lget(g, lout); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_EPOCH);
    lget(g, lout); lget(g, k); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
    lget(g, lout); lget(g, sptr); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_SPAN_PTR);
    lget(g, lout); lget(g, sslot); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_SPAN_SLOT);
    lget(g, lout); lget(g, sgen); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_SPAN_GEN);
    i32Const(g, SEQ_SPAN_BYTES); callf(g, g.s.seq_alloc_fn); lset(g, rout);
    lget(g, rout); i32Const(g, SEQ_KIND_SPAN); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_META);
    lget(g, rout); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_EPOCH);
    lget(g, rout); lget(g, len); lget(g, k); op(g, OP_i32_sub); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
    let rptr = if sp.elem_bytes == 0 { sptr } else { emitOffsetAddress(g, nf, sptr, k, sp.elem_bytes) };
    lget(g, rout); lget(g, rptr); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_SPAN_PTR);
    lget(g, rout); lget(g, sslot); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_SPAN_SLOT);
    lget(g, rout); lget(g, sgen); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_SPAN_GEN);
    lget(g, lout); lget(g, rout); op(g, OP_return_);
    close(g, nf);

    // LEAF_REPEAT: O(1) two repeat descriptors!
    lget(g, kind); i32Const(g, SEQ_KIND_REPEAT); op(g, OP_i32_eq);
    let rep_if = open(g, nf, OP_if_);
    let rbytes = align16(16 + sp.elem_bytes);
    i32Const(g, rbytes); callf(g, g.s.seq_alloc_fn); ltee(g, lout);
    lget(g, ptr); i32Const(g, rbytes); memoryCopyOp(g);
    lget(g, lout); lget(g, k); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
    i32Const(g, rbytes); callf(g, g.s.seq_alloc_fn); ltee(g, rout);
    lget(g, ptr); i32Const(g, rbytes); memoryCopyOp(g);
    lget(g, rout); lget(g, len); lget(g, k); op(g, OP_i32_sub); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
    lget(g, lout); lget(g, rout); op(g, OP_return_);
    close(g, nf);

    // LEAF_RAMP: O(1) two 32-byte ramp descriptors!
    if sp.elem_ty == squid_direct_types::u32_ {
        lget(g, kind); i32Const(g, SEQ_KIND_RAMP); op(g, OP_i32_eq);
        let ramp_if = open(g, nf, OP_if_);
        let rstart = local32(g, nf);
        let rstep = local32(g, nf);
        lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_RAMP_START); lset(g, rstart);
        lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_RAMP_STEP); lset(g, rstep);
        i32Const(g, SEQ_RAMP_BYTES); callf(g, g.s.seq_alloc_fn); lset(g, lout);
        lget(g, lout); i32Const(g, SEQ_KIND_RAMP); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_META);
        lget(g, lout); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_EPOCH);
        lget(g, lout); lget(g, k); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
        lget(g, lout); lget(g, rstart); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_RAMP_START);
        lget(g, lout); lget(g, rstep); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_RAMP_STEP);
        i32Const(g, SEQ_RAMP_BYTES); callf(g, g.s.seq_alloc_fn); lset(g, rout);
        lget(g, rout); i32Const(g, SEQ_KIND_RAMP); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_META);
        lget(g, rout); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_EPOCH);
        lget(g, rout); lget(g, len); lget(g, k); op(g, OP_i32_sub); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
        lget(g, rout); lget(g, rstart); lget(g, k); lget(g, rstep); op(g, OP_i32_mul); op(g, OP_i32_add);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_RAMP_START);
        lget(g, rout); lget(g, rstep); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_RAMP_STEP);
        lget(g, lout); lget(g, rout); op(g, OP_return_);
        close(g, nf);
    }

    // Canonical leaf split
    lget(g, epoch); callf(g, create_fn); lset(g, lout);
    lget(g, epoch); callf(g, create_fn); lset(g, rout);
    if sp.leaf_kind == SEQ_KIND_FLAT && sp.elem_bytes != 0 {
        let bl = emitScaledBytes(g, nf, k, sp.elem_bytes);
        let rcnt = local32(g, nf);
        lget(g, len); lget(g, k); op(g, OP_i32_sub); lset(g, rcnt);
        let br_b = emitScaledBytes(g, nf, rcnt, sp.elem_bytes);
        lget(g, lout); i32Const(g, SEQ_LEAF_DATA); op(g, OP_i32_add);
        lget(g, ptr); i32Const(g, SEQ_LEAF_DATA); op(g, OP_i32_add);
        lget(g, bl); memoryCopyOp(g);
        lget(g, lout); lget(g, k); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
        lget(g, rout); i32Const(g, SEQ_LEAF_DATA); op(g, OP_i32_add);
        lget(g, ptr); i32Const(g, SEQ_LEAF_DATA); op(g, OP_i32_add); lget(g, bl); op(g, OP_i32_add);
        lget(g, br_b); memoryCopyOp(g);
        lget(g, rout); lget(g, rcnt); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
        lget(g, lout); lget(g, rout); op(g, OP_return_);
    } else {
        i32Const(g, 0); lset(g, i);
        let b1 = open(g, nf, OP_block); let l1 = open(g, nf, OP_loop);
        lget(g, i); lget(g, k); op(g, OP_i32_ge_u); br(g, nf, OP_br_if, b1);
        lget(g, lout); lget(g, ptr); lget(g, i); callf(g, get_fn); callf(g, app_fn);
        lget(g, i); i32Const(g, 1); op(g, OP_i32_add); lset(g, i);
        br(g, nf, OP_br, l1);
        close(g, nf); close(g, nf);
        let b2 = open(g, nf, OP_block); let l2 = open(g, nf, OP_loop);
        lget(g, i); lget(g, len); op(g, OP_i32_ge_u); br(g, nf, OP_br_if, b2);
        lget(g, rout); lget(g, ptr); lget(g, i); callf(g, get_fn); callf(g, app_fn);
        lget(g, i); i32Const(g, 1); op(g, OP_i32_add); lset(g, i);
        br(g, nf, OP_br, l2);
        close(g, nf); close(g, nf);
        lget(g, lout); lget(g, rout);
    }
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// Kind 21: seq_leaf_unrev_sum(leaf_ptr, epoch) -> forward LEAF_PACKED_SUM (used by reversed fused loops)
fn ensureSeqLeafUnrevSum(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let create_fn, crerr = ensureSeqLeafCreate(g, sp);
    if crerr != squid_direct_types::Error.none { return 0, crerr; }
    let get_fn, gerr = ensureSeqLeafGet(g, sp);
    if gerr != squid_direct_types::Error.none { return 0, gerr; }
    let app_fn, aerr = ensureSeqLeafAppendOne(g, sp);
    if aerr != squid_direct_types::Error.none { return 0, aerr; }
    let key = squid_direct_emit::key64(sp.elem_ty, 21);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32], [VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let edge = local(g, nf, VT_i32);
    let epoch = local(g, nf, VT_i32);
    nf.parameter_words = 2;
    let out = local32(g, nf);
    let len = local32(g, nf);
    let i = local32(g, nf);
    lget(g, edge); i32Const(g, 0xfffffffe); op(g, OP_i32_and); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_LEAF_LEN); lset(g, len);
    lget(g, epoch); callf(g, create_fn); lset(g, out);
    i32Const(g, 0); lset(g, i);
    let b1 = open(g, nf, OP_block); let l1 = open(g, nf, OP_loop);
    lget(g, i); lget(g, len); op(g, OP_i32_ge_u); br(g, nf, OP_br_if, b1);
    lget(g, out); lget(g, edge); lget(g, i); callf(g, get_fn); callf(g, app_fn);
    lget(g, i); i32Const(g, 1); op(g, OP_i32_add); lset(g, i);
    br(g, nf, OP_br, l1);
    close(g, nf); close(g, nf);
    lget(g, out);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// ---- Tree operations (SIMD-routed get, balanced RRB concat, split, CoW set) ----

// Kind 8: seq_tree_get(edge, i) -> val...
fn ensureSeqTreeGet(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let leaf_get_fn, lgerr = ensureSeqLeafGet(g, sp);
    if lgerr != squid_direct_types::Error.none { return 0, lgerr; }
    let key = squid_direct_emit::key64(sp.elem_ty, 8);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let lay, lerr = g.types.layout(sp.elem_ty);
    if lerr != squid_direct_types::Error.none { return 0, lerr; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32], lay));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let edge = local(g, nf, VT_i32);
    let idx = local(g, nf, VT_i32);
    nf.parameter_words = 2;
    let ptr = local32(g, nf);
    let meta = local32(g, nf);
    let sh = local32(g, nf);
    let len = local32(g, nf);
    let p = local32(g, nf);
    let j = local32(g, nf);
    let prev = local32(g, nf);
    let lp = open(g, nf, OP_loop);
    lget(g, edge); i32Const(g, 0xfffffffe); op(g, OP_i32_and); ltee(g, ptr);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_META); ltee(g, meta);
    i32Const(g, 15); op(g, OP_i32_and);
    let is_leaf = open(g, nf, OP_if_);
    lget(g, edge); lget(g, idx); callf(g, leaf_get_fn); op(g, OP_return_);
    close(g, nf);
    // Dense radix-16 fast path when unreversed & radix_shift != 0 (zero prefix load, zero SIMD!)
    lget(g, meta); i32Const(g, 24); op(g, OP_i32_shr_u); ltee(g, sh);
    lget(g, edge); i32Const(g, 1); op(g, OP_i32_and); op(g, OP_i32_eqz);
    op(g, OP_i32_and);
    let fast_radix = open(g, nf, OP_if_);
    lget(g, idx); lget(g, sh); op(g, OP_i32_shr_u); lset(g, j);
    lget(g, idx); lget(g, j); lget(g, sh); op(g, OP_i32_shl); op(g, OP_i32_sub); lset(g, idx);
    lget(g, ptr); lget(g, j); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    lset(g, edge);
    br(g, nf, OP_br, lp);
    close(g, nf);
    // Reversed or relaxed internal node
    lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_LEN); lset(g, len);
    lget(g, len); i32Const(g, 1); op(g, OP_i32_sub); lget(g, idx); op(g, OP_i32_sub);
    lget(g, idx);
    lget(g, edge); i32Const(g, 1); op(g, OP_i32_and);
    op(g, OP_select);
    lset(g, p);
    lget(g, sh);
    let rev_radix = open(g, nf, OP_if_);
    lget(g, p); lget(g, sh); op(g, OP_i32_shr_u); lset(g, j);
    lget(g, p); lget(g, j); lget(g, sh); op(g, OP_i32_shl); op(g, OP_i32_sub); lset(g, idx);
    op(g, OP_else_);
    lget(g, ptr); lget(g, p); callf(g, g.s.seq_simd_find_fn); ltee(g, j);
    let has_prev = open(g, nf, OP_if_);
    lget(g, ptr); lget(g, j); i32Const(g, 1); op(g, OP_i32_sub); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_PREFIXES);
    lset(g, prev);
    op(g, OP_else_);
    i32Const(g, 0); lset(g, prev);
    close(g, nf);
    lget(g, p); lget(g, prev); op(g, OP_i32_sub); lset(g, idx);
    close(g, nf);
    lget(g, ptr); lget(g, j); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    lset(g, edge);
    br(g, nf, OP_br, lp);
    close(g, nf);
    op(g, OP_unreachable_);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// Kind 9: seq_tree_concat_inner(a_edge, b_edge, epoch) -> (r1, r2)
// Returns 1 or 2 nodes of height max(height(a), height(b)), merging underfull canonical leaves
// and compacting adjacent internal nodes cleanly.
fn ensureSeqTreeConcatInner(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let rebuild_fn, rerr = ensureSeqRebuildPrefixes(g);
    if rerr != squid_direct_types::Error.none { return 0, rerr; }
    let clone_node_fn, cnerr = ensureSeqNodeClone(g);
    if cnerr != squid_direct_types::Error.none { return 0, cnerr; }
    let unrev_fn, uerr = ensureSeqNodeUnrev(g);
    if uerr != squid_direct_types::Error.none { return 0, uerr; }
    let merge_leaf_fn, mlerr = ensureSeqLeafMerge(g, sp);
    if mlerr != squid_direct_types::Error.none { return 0, mlerr; }
    let key = squid_direct_emit::key64(sp.elem_ty, 9);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32, VT_i32], [VT_i32, VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let rt = g.runtime_();
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let a = local(g, nf, VT_i32);
    let b = local(g, nf, VT_i32);
    let epoch = local(g, nf, VT_i32);
    nf.parameter_words = 3;
    let pa = local32(g, nf); let pb = local32(g, nf);
    let ma = local32(g, nf); let mb = local32(g, nf);
    let ha = local32(g, nf); let hb = local32(g, nf);
    let ka = local32(g, nf); let kb = local32(g, nf);
    let na = local32(g, nf); let nb = local32(g, nf);
    let m1 = local32(g, nf); let m2 = local32(g, nf);
    let buf = local32(g, nf);
    let tot = local32(g, nf);
    let n1 = local32(g, nf); let n2 = local32(g, nf);
    let left_k = local32(g, nf); let right_k = local32(g, nf);
    let h_out = local32(g, nf);
    let smark = local32(g, nf);
    let reuse_node = constLocal(g, nf, 0);

    lget(g, a); i32Const(g, 0xfffffffe); op(g, OP_i32_and); ltee(g, pa);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_META); ltee(g, ma);
    i32Const(g, 16); op(g, OP_i32_shr_u); i32Const(g, 255); op(g, OP_i32_and); lset(g, ha);
    lget(g, b); i32Const(g, 0xfffffffe); op(g, OP_i32_and); ltee(g, pb);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_META); ltee(g, mb);
    i32Const(g, 16); op(g, OP_i32_shr_u); i32Const(g, 255); op(g, OP_i32_and); lset(g, hb);

    // Base: ha == 0 && hb == 0 (both leaves)
    lget(g, ha); lget(g, hb); op(g, OP_i32_or); op(g, OP_i32_eqz);
    let both_leaves = open(g, nf, OP_if_);
    lget(g, ma); i32Const(g, 15); op(g, OP_i32_and); lset(g, ka);
    lget(g, mb); i32Const(g, 15); op(g, OP_i32_and); lset(g, kb);
    // Coalesce two canonical leaves if len_a + len_b <= leaf_cap (anti-fragmentation!)
    lget(g, ka); i32Const(g, sp.leaf_kind); op(g, OP_i32_eq);
    lget(g, kb); i32Const(g, sp.leaf_kind); op(g, OP_i32_eq);
    op(g, OP_i32_and);
    lget(g, pa); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
    lget(g, pb); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
    op(g, OP_i32_add);
    i32Const(g, sp.leaf_cap); op(g, OP_i32_le_u);
    op(g, OP_i32_and);
    let can_merge = open(g, nf, OP_if_);
    lget(g, a); lget(g, b); lget(g, epoch); callf(g, merge_leaf_fn);
    i32Const(g, 0);
    op(g, OP_return_);
    close(g, nf);
    // Otherwise return (a, b) as two height-0 siblings
    lget(g, a); lget(g, b); op(g, OP_return_);
    close(g, nf);

    // Allocate temporary 128-byte (32-child) merge buffer on stack (rewound before returning!)
    gget(g, rt.stack_pointer); lset(g, smark);
    i32Const(g, 128); callf(g, rt.stack); lset(g, buf);
    i32Const(g, 0); lset(g, tot);

    // Case ha > hb
    lget(g, ha); lget(g, hb); op(g, OP_i32_gt_u);
    let gt_if = open(g, nf, OP_if_);
    lget(g, ha); lset(g, h_out);
    lget(g, a); lget(g, epoch); callf(g, unrev_fn); lset(g, pa);
    lget(g, pa); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_EPOCH); lget(g, epoch); op(g, OP_i32_eq);
    let rn_gt = open(g, nf, OP_if_); lget(g, pa); lset(g, reuse_node); close(g, nf);
    lget(g, pa); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_META);
    i32Const(g, 8); op(g, OP_i32_shr_u); i32Const(g, 255); op(g, OP_i32_and); lset(g, na);
    lget(g, pa); lget(g, na); i32Const(g, 1); op(g, OP_i32_sub); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    lget(g, b); lget(g, epoch); callf(g, fn_id);
    lset(g, m2); lset(g, m1);
    // Copy a.children[0..na-1] into buf
    lget(g, na); i32Const(g, 1); op(g, OP_i32_sub); ltee(g, tot);
    let cpy_a = open(g, nf, OP_if_);
    lget(g, buf);
    lget(g, pa); i32Const(g, SEQ_NODE_CHILDREN); op(g, OP_i32_add);
    lget(g, tot); i32Const(g, 2); op(g, OP_i32_shl);
    memoryCopyOp(g);
    close(g, nf);
    lget(g, buf); lget(g, tot); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    lget(g, m1); op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
    lget(g, tot); i32Const(g, 1); op(g, OP_i32_add); lset(g, tot);
    lget(g, m2);
    let has_m2a = open(g, nf, OP_if_);
    lget(g, buf); lget(g, tot); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    lget(g, m2); op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
    lget(g, tot); i32Const(g, 1); op(g, OP_i32_add); lset(g, tot);
    close(g, nf);
    op(g, OP_else_);

    // Case ha < hb
    lget(g, ha); lget(g, hb); op(g, OP_i32_lt_u);
    let lt_if = open(g, nf, OP_if_);
    lget(g, hb); lset(g, h_out);
    lget(g, b); lget(g, epoch); callf(g, unrev_fn); lset(g, pb);
    lget(g, pb); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_EPOCH); lget(g, epoch); op(g, OP_i32_eq);
    let rn_lt = open(g, nf, OP_if_); lget(g, pb); lset(g, reuse_node); close(g, nf);
    lget(g, pb); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_META);
    i32Const(g, 8); op(g, OP_i32_shr_u); i32Const(g, 255); op(g, OP_i32_and); lset(g, nb);
    lget(g, a);
    lget(g, pb); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    lget(g, epoch); callf(g, fn_id);
    lset(g, m2); lset(g, m1);
    lget(g, buf); lget(g, m1); op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
    i32Const(g, 1); lset(g, tot);
    lget(g, m2);
    let has_m2b = open(g, nf, OP_if_);
    lget(g, buf); lget(g, m2); op(g, OP_i32_store); uleb(g, 2); uleb(g, 4);
    i32Const(g, 2); lset(g, tot);
    close(g, nf);
    lget(g, nb); i32Const(g, 1); op(g, OP_i32_sub);
    let cpy_b = open(g, nf, OP_if_);
    lget(g, buf); lget(g, tot); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    lget(g, pb); i32Const(g, SEQ_NODE_CHILDREN + 4); op(g, OP_i32_add);
    lget(g, nb); i32Const(g, 1); op(g, OP_i32_sub); i32Const(g, 2); op(g, OP_i32_shl);
    memoryCopyOp(g);
    lget(g, tot); lget(g, nb); i32Const(g, 1); op(g, OP_i32_sub); op(g, OP_i32_add); lset(g, tot);
    close(g, nf);
    op(g, OP_else_);

    // Case ha == hb > 0
    lget(g, ha); lset(g, h_out);
    lget(g, a); lget(g, epoch); callf(g, unrev_fn); lset(g, pa);
    lget(g, b); lget(g, epoch); callf(g, unrev_fn); lset(g, pb);
    lget(g, pa); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_EPOCH); lget(g, epoch); op(g, OP_i32_eq);
    lget(g, pa); lget(g, pb); op(g, OP_i32_ne); op(g, OP_i32_and);
    let rn_eq = open(g, nf, OP_if_); lget(g, pa); lset(g, reuse_node); close(g, nf);
    lget(g, pa); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_META);
    i32Const(g, 8); op(g, OP_i32_shr_u); i32Const(g, 255); op(g, OP_i32_and); lset(g, na);
    lget(g, pb); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_META);
    i32Const(g, 8); op(g, OP_i32_shr_u); i32Const(g, 255); op(g, OP_i32_and); lset(g, nb);
    // Recursively merge boundary pair (a.last, b.first)
    lget(g, pa); lget(g, na); i32Const(g, 1); op(g, OP_i32_sub); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    lget(g, pb); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    lget(g, epoch); callf(g, fn_id);
    lset(g, m2); lset(g, m1);
    lget(g, na); i32Const(g, 1); op(g, OP_i32_sub); ltee(g, tot);
    let cpy_eq_a = open(g, nf, OP_if_);
    lget(g, buf);
    lget(g, pa); i32Const(g, SEQ_NODE_CHILDREN); op(g, OP_i32_add);
    lget(g, tot); i32Const(g, 2); op(g, OP_i32_shl);
    memoryCopyOp(g);
    close(g, nf);
    lget(g, buf); lget(g, tot); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    lget(g, m1); op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
    lget(g, tot); i32Const(g, 1); op(g, OP_i32_add); lset(g, tot);
    lget(g, m2);
    let has_m2eq = open(g, nf, OP_if_);
    lget(g, buf); lget(g, tot); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    lget(g, m2); op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
    lget(g, tot); i32Const(g, 1); op(g, OP_i32_add); lset(g, tot);
    close(g, nf);
    lget(g, nb); i32Const(g, 1); op(g, OP_i32_sub);
    let cpy_eq_b = open(g, nf, OP_if_);
    lget(g, buf); lget(g, tot); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    lget(g, pb); i32Const(g, SEQ_NODE_CHILDREN + 4); op(g, OP_i32_add);
    lget(g, nb); i32Const(g, 1); op(g, OP_i32_sub); i32Const(g, 2); op(g, OP_i32_shl);
    memoryCopyOp(g);
    lget(g, tot); lget(g, nb); i32Const(g, 1); op(g, OP_i32_sub); op(g, OP_i32_add); lset(g, tot);
    close(g, nf);
    close(g, nf);
    close(g, nf);

    // Pack `tot` children from `buf` into 1 node (if tot <= 16) or 2 balanced nodes (if tot > 16).
    lget(g, tot); i32Const(g, 16); op(g, OP_i32_le_u);
    let fits_one = open(g, nf, OP_if_);
    lget(g, reuse_node);
    let do_reuse = open(g, nf, OP_if_);
    lget(g, reuse_node); lset(g, n1);
    op(g, OP_else_);
    i32Const(g, SEQ_NODE_BYTES); callf(g, g.s.seq_alloc_fn); lset(g, n1);
    close(g, nf);
    lget(g, n1); lget(g, tot); i32Const(g, 8); op(g, OP_i32_shl);
    lget(g, h_out); i32Const(g, 16); op(g, OP_i32_shl); op(g, OP_i32_or);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_META);
    lget(g, n1); lget(g, epoch); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_EPOCH);
    lget(g, n1); i32Const(g, SEQ_NODE_CHILDREN); op(g, OP_i32_add);
    lget(g, buf); lget(g, tot); i32Const(g, 2); op(g, OP_i32_shl); memoryCopyOp(g);
    lget(g, n1); callf(g, rebuild_fn);
    lget(g, smark); callf(g, rt.rewind_stack);
    lget(g, n1); i32Const(g, 0); op(g, OP_return_);
    close(g, nf);

    // Split across two height-`h_out` nodes: left_k = tot / 2, right_k = tot - left_k
    lget(g, tot); i32Const(g, 1); op(g, OP_i32_shr_u); lset(g, left_k);
    lget(g, tot); lget(g, left_k); op(g, OP_i32_sub); lset(g, right_k);
    i32Const(g, SEQ_NODE_BYTES); callf(g, g.s.seq_alloc_fn); lset(g, n1);
    lget(g, n1); lget(g, left_k); i32Const(g, 8); op(g, OP_i32_shl);
    lget(g, h_out); i32Const(g, 16); op(g, OP_i32_shl); op(g, OP_i32_or);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_META);
    lget(g, n1); lget(g, epoch); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_EPOCH);
    lget(g, n1); i32Const(g, SEQ_NODE_CHILDREN); op(g, OP_i32_add);
    lget(g, buf); lget(g, left_k); i32Const(g, 2); op(g, OP_i32_shl); memoryCopyOp(g);
    lget(g, n1); callf(g, rebuild_fn);
    i32Const(g, SEQ_NODE_BYTES); callf(g, g.s.seq_alloc_fn); lset(g, n2);
    lget(g, n2); lget(g, right_k); i32Const(g, 8); op(g, OP_i32_shl);
    lget(g, h_out); i32Const(g, 16); op(g, OP_i32_shl); op(g, OP_i32_or);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_META);
    lget(g, n2); lget(g, epoch); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_EPOCH);
    lget(g, n2); i32Const(g, SEQ_NODE_CHILDREN); op(g, OP_i32_add);
    lget(g, buf); lget(g, left_k); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    lget(g, right_k); i32Const(g, 2); op(g, OP_i32_shl); memoryCopyOp(g);
    lget(g, n2); callf(g, rebuild_fn);
    lget(g, smark); callf(g, rt.rewind_stack);
    lget(g, n1); lget(g, n2);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// Kind 10: seq_tree_concat(a_edge, b_edge, epoch) -> merged_edge
fn ensureSeqTreeConcat(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let inner_fn, ierr = ensureSeqTreeConcatInner(g, sp);
    if ierr != squid_direct_types::Error.none { return 0, ierr; }
    let new2_fn, nerr = ensureSeqNodeNew2(g);
    if nerr != squid_direct_types::Error.none { return 0, nerr; }
    let key = squid_direct_emit::key64(sp.elem_ty, 10);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32, VT_i32], [VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let a = local(g, nf, VT_i32);
    let b = local(g, nf, VT_i32);
    let epoch = local(g, nf, VT_i32);
    nf.parameter_words = 3;
    let r1 = local32(g, nf);
    let r2 = local32(g, nf);
    let h = local32(g, nf);
    lget(g, a); op(g, OP_i32_eqz);
    let a0 = open(g, nf, OP_if_); lget(g, b); op(g, OP_return_); close(g, nf);
    lget(g, b); op(g, OP_i32_eqz);
    let b0 = open(g, nf, OP_if_); lget(g, a); op(g, OP_return_); close(g, nf);
    lget(g, a); lget(g, b); lget(g, epoch); callf(g, inner_fn);
    lset(g, r2); lset(g, r1);
    lget(g, r2); op(g, OP_i32_eqz);
    let one = open(g, nf, OP_if_); lget(g, r1); op(g, OP_return_); close(g, nf);
    lget(g, r1); i32Const(g, 0xfffffffe); op(g, OP_i32_and);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_META);
    i32Const(g, 16); op(g, OP_i32_shr_u); i32Const(g, 255); op(g, OP_i32_and);
    i32Const(g, 1); op(g, OP_i32_add); lset(g, h);
    lget(g, r1); lget(g, r2); lget(g, h); lget(g, epoch); callf(g, new2_fn);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// Kind 11: seq_tree_split(edge, k, epoch) -> (left_edge, right_edge)
fn ensureSeqTreeSplit(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let leaf_split_fn, lserr = ensureSeqLeafSplit(g, sp);
    if lserr != squid_direct_types::Error.none { return 0, lserr; }
    let concat_fn, cerr = ensureSeqTreeConcat(g, sp);
    if cerr != squid_direct_types::Error.none { return 0, cerr; }
    let slice_fn, slerr = ensureSeqNodeSlice(g);
    if slerr != squid_direct_types::Error.none { return 0, slerr; }
    let key = squid_direct_emit::key64(sp.elem_ty, 11);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32, VT_i32], [VT_i32, VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let edge = local(g, nf, VT_i32);
    let k = local(g, nf, VT_i32);
    let epoch = local(g, nf, VT_i32);
    nf.parameter_words = 3;
    let ptr = local32(g, nf);
    let len = local32(g, nf);
    let meta = local32(g, nf);
    let count = local32(g, nf);
    let j = local32(g, nf);
    let prev = local32(g, nf);
    let u = local32(g, nf);
    let mid_l = local32(g, nf);
    let mid_r = local32(g, nf);
    let lpre = local32(g, nf);
    let rsuf = local32(g, nf);

    lget(g, edge); op(g, OP_i32_eqz);
    let e0 = open(g, nf, OP_if_); i32Const(g, 0); i32Const(g, 0); op(g, OP_return_); close(g, nf);
    lget(g, k); op(g, OP_i32_eqz);
    let k0 = open(g, nf, OP_if_); i32Const(g, 0); lget(g, edge); op(g, OP_return_); close(g, nf);
    lget(g, edge); i32Const(g, 0xfffffffe); op(g, OP_i32_and); lset(g, ptr);
    lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_LEN); lset(g, len);
    lget(g, k); lget(g, len); op(g, OP_i32_ge_u);
    let kn = open(g, nf, OP_if_); lget(g, edge); i32Const(g, 0); op(g, OP_return_); close(g, nf);

    // Reversal rule: split(rev(S), k) = (rev(R), rev(L)) where (L, R) = split(S, N - k)!
    lget(g, edge); i32Const(g, 1); op(g, OP_i32_and);
    let rev_if = open(g, nf, OP_if_);
    lget(g, ptr); lget(g, len); lget(g, k); op(g, OP_i32_sub); lget(g, epoch);
    callf(g, fn_id);
    lset(g, mid_r); lset(g, mid_l);
    lget(g, mid_r); i32Const(g, 1); op(g, OP_i32_xor);
    i32Const(g, 0);
    lget(g, mid_r);
    op(g, OP_select);
    lget(g, mid_l); i32Const(g, 1); op(g, OP_i32_xor);
    i32Const(g, 0);
    lget(g, mid_l);
    op(g, OP_select);
    op(g, OP_return_);
    close(g, nf);

    // Leaf?
    lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_META); ltee(g, meta);
    i32Const(g, 15); op(g, OP_i32_and);
    let leaf_if = open(g, nf, OP_if_);
    lget(g, ptr); lget(g, k); lget(g, epoch); callf(g, leaf_split_fn); op(g, OP_return_);
    close(g, nf);

    // Internal node (unreversed): SIMD find first j with prefixes[j] > k
    lget(g, meta); i32Const(g, 8); op(g, OP_i32_shr_u); i32Const(g, 255); op(g, OP_i32_and); lset(g, count);
    lget(g, ptr); lget(g, k); callf(g, g.s.seq_simd_find_fn); ltee(g, j);
    let hp = open(g, nf, OP_if_);
    lget(g, ptr); lget(g, j); i32Const(g, 1); op(g, OP_i32_sub); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_PREFIXES); lset(g, prev);
    op(g, OP_else_);
    i32Const(g, 0); lset(g, prev);
    close(g, nf);
    lget(g, k); lget(g, prev); op(g, OP_i32_sub); lset(g, u);
    lget(g, ptr); lget(g, j); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    lget(g, u); lget(g, epoch); callf(g, fn_id);
    lset(g, mid_r); lset(g, mid_l);
    lget(g, ptr); i32Const(g, 0); lget(g, j); lget(g, epoch); callf(g, slice_fn); lset(g, lpre);
    lget(g, ptr); lget(g, j); i32Const(g, 1); op(g, OP_i32_add); lget(g, count); lget(g, epoch); callf(g, slice_fn); lset(g, rsuf);
    lget(g, lpre); lget(g, mid_l); lget(g, epoch); callf(g, concat_fn);
    lget(g, mid_r); lget(g, rsuf); lget(g, epoch); callf(g, concat_fn);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// Kind 12: seq_tree_set_fast(edge, i, val..., epoch) -> new_edge (0 if landed on generative/span leaf)
fn ensureSeqTreeSetFast(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let clone_node_fn, cnerr = ensureSeqNodeClone(g);
    if cnerr != squid_direct_types::Error.none { return 0, cnerr; }
    let leaf_set_fn, lserr = ensureSeqLeafSetCanon(g, sp);
    if lserr != squid_direct_types::Error.none { return 0, lserr; }
    let key = squid_direct_emit::key64(sp.elem_ty, 12);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let lay, lerr = g.types.layout(sp.elem_ty);
    if lerr != squid_direct_types::Error.none { return 0, lerr; }
    var ptypes: ValType[>..] = [VT_i32, VT_i32];
    for wt in lay { ptypes.push(wt); }
    ptypes.push(VT_i32);
    let fn_id = g.module.addFunction(g.module.signature(ptypes[..], [VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let edge = local(g, nf, VT_i32);
    let idx = local(g, nf, VT_i32);
    let val, verr = seqValFromParams(g, nf, sp.elem_ty, 0);
    if verr != squid_direct_types::Error.none {
        squid_direct_relocations::rewind(sites_mark);
        s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
        return 0, verr;
    }
    let epoch = local(g, nf, VT_i32);
    nf.parameter_words = (3 + lay.len) as u32;
    let ptr = local32(g, nf);
    let rev = local32(g, nf);
    let meta = local32(g, nf);
    let kind = local32(g, nf);
    let sh = local32(g, nf);
    let p = local32(g, nf);
    let j = local32(g, nf);
    let prev = local32(g, nf);
    let sub_i = local32(g, nf);
    let old_ch = local32(g, nf);
    let new_ch = local32(g, nf);
    lget(g, edge); i32Const(g, 0xfffffffe); op(g, OP_i32_and); lset(g, ptr);
    lget(g, edge); i32Const(g, 1); op(g, OP_i32_and); lset(g, rev);
    lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_META); ltee(g, meta);
    i32Const(g, 15); op(g, OP_i32_and); ltee(g, kind);
    let is_leaf = open(g, nf, OP_if_);
    lget(g, kind); i32Const(g, sp.leaf_kind); op(g, OP_i32_eq);
    let is_canon = open(g, nf, OP_if_);
    lget(g, edge); lget(g, idx); seqPushVal(g, val); lget(g, epoch); callf(g, leaf_set_fn);
    op(g, OP_return_);
    close(g, nf);
    i32Const(g, 0); op(g, OP_return_);
    close(g, nf);
    // Internal node: mirror if rev, then use dense radix shift when available!
    lget(g, rev);
    let is_rev = open(g, nf, OP_if_);
    lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_LEN);
    i32Const(g, 1); op(g, OP_i32_sub); lget(g, idx); op(g, OP_i32_sub); lset(g, p);
    op(g, OP_else_);
    lget(g, idx); lset(g, p);
    close(g, nf);
    lget(g, meta); i32Const(g, 24); op(g, OP_i32_shr_u); ltee(g, sh);
    let has_sh = open(g, nf, OP_if_);
    lget(g, p); lget(g, sh); op(g, OP_i32_shr_u); lset(g, j);
    lget(g, p); lget(g, j); lget(g, sh); op(g, OP_i32_shl); op(g, OP_i32_sub); lset(g, sub_i);
    op(g, OP_else_);
    lget(g, ptr); lget(g, p); callf(g, g.s.seq_simd_find_fn); ltee(g, j);
    let hp = open(g, nf, OP_if_);
    lget(g, ptr); lget(g, j); i32Const(g, 1); op(g, OP_i32_sub); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_PREFIXES); lset(g, prev);
    op(g, OP_else_);
    i32Const(g, 0); lset(g, prev);
    close(g, nf);
    lget(g, p); lget(g, prev); op(g, OP_i32_sub); lset(g, sub_i);
    close(g, nf);
    lget(g, ptr); lget(g, j); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN); lset(g, old_ch);
    lget(g, old_ch); lget(g, sub_i); seqPushVal(g, val); lget(g, epoch);
    callf(g, fn_id);
    ltee(g, new_ch);
    op(g, OP_i32_eqz);
    let fallback = open(g, nf, OP_if_); i32Const(g, 0); op(g, OP_return_); close(g, nf);
    // Update child pointer (CoW node if epoch differs)
    lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_EPOCH); lget(g, epoch); op(g, OP_i32_ne);
    let cow = open(g, nf, OP_if_);
    lget(g, ptr); lget(g, epoch); callf(g, clone_node_fn); lset(g, ptr);
    close(g, nf);
    lget(g, ptr); lget(g, j); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    lget(g, new_ch); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    lget(g, ptr); lget(g, rev); op(g, OP_i32_or);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// Kind 13: seq_tree_set(edge, i, val..., epoch) -> new_edge
fn ensureSeqTreeSet(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let fast_fn, ferr = ensureSeqTreeSetFast(g, sp);
    if ferr != squid_direct_types::Error.none { return 0, ferr; }
    let split_fn, serr = ensureSeqTreeSplit(g, sp);
    if serr != squid_direct_types::Error.none { return 0, serr; }
    let concat_fn, cerr = ensureSeqTreeConcat(g, sp);
    if cerr != squid_direct_types::Error.none { return 0, cerr; }
    let create_fn, crerr = ensureSeqLeafCreate(g, sp);
    if crerr != squid_direct_types::Error.none { return 0, crerr; }
    let app_fn, aerr = ensureSeqLeafAppendOne(g, sp);
    if aerr != squid_direct_types::Error.none { return 0, aerr; }
    let key = squid_direct_emit::key64(sp.elem_ty, 13);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let lay, lerr = g.types.layout(sp.elem_ty);
    if lerr != squid_direct_types::Error.none { return 0, lerr; }
    var ptypes: ValType[>..] = [VT_i32, VT_i32];
    for wt in lay { ptypes.push(wt); }
    ptypes.push(VT_i32);
    let fn_id = g.module.addFunction(g.module.signature(ptypes[..], [VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let edge = local(g, nf, VT_i32);
    let idx = local(g, nf, VT_i32);
    let val, verr = seqValFromParams(g, nf, sp.elem_ty, 0);
    if verr != squid_direct_types::Error.none {
        squid_direct_relocations::rewind(sites_mark);
        s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
        return 0, verr;
    }
    let epoch = local(g, nf, VT_i32);
    nf.parameter_words = (3 + lay.len) as u32;
    let res = local32(g, nf);
    let left = local32(g, nf);
    let rest = local32(g, nf);
    let right = local32(g, nf);
    let single = local32(g, nf);
    lget(g, edge); lget(g, idx); seqPushVal(g, val); lget(g, epoch); callf(g, fast_fn);
    ltee(g, res);
    let ok = open(g, nf, OP_if_); lget(g, res); op(g, OP_return_); close(g, nf);
    // Fallback for generative/span leaf: split at idx, drop 1, concat(left, [val], right)!
    lget(g, edge); lget(g, idx); lget(g, epoch); callf(g, split_fn);
    lset(g, rest); lset(g, left);
    lget(g, rest); i32Const(g, 1); lget(g, epoch); callf(g, split_fn);
    lset(g, right); op(g, OP_drop);
    lget(g, epoch); callf(g, create_fn); lset(g, single);
    lget(g, single); seqPushVal(g, val); callf(g, app_fn);
    lget(g, left); lget(g, single); lget(g, epoch); callf(g, concat_fn);
    lget(g, right); lget(g, epoch); callf(g, concat_fn);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// ---- Readable FocusGap helpers ----

// Inline helper: emit gap movement on mutable `focus_ptr` to logical position `target` (0 <= target <= live_len).
fn emitSeqFocusMoveGap(g: Generator&, f: Fn&, sp: const SeqPlan&, focus: u32, target: u32) {
    let gs = local32(g, f);
    let ge = local32(g, f);
    let glen = local32(g, f);
    let delta = local32(g, f);
    lget(g, focus); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_GSTART); lset(g, gs);
    lget(g, target); lget(g, gs); op(g, OP_i32_eq);
    let same = open(g, f, OP_if_);
    op(g, OP_else_);
    lget(g, focus); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_GEND); lset(g, ge);
    lget(g, ge); lget(g, gs); op(g, OP_i32_sub); lset(g, glen);
    lget(g, target); lget(g, gs); op(g, OP_i32_lt_u);
    let left_if = open(g, f, OP_if_);
    // Shift [target .. gs) right by glen -> to [target + glen .. ge)
    if sp.elem_bytes != 0 {
        lget(g, gs); lget(g, target); op(g, OP_i32_sub); lset(g, delta);
        let dbase = local32(g, f);
        lget(g, focus); i32Const(g, SEQ_FOC_DATA); op(g, OP_i32_add); lset(g, dbase);
        let dst_idx = local32(g, f);
        lget(g, target); lget(g, glen); op(g, OP_i32_add); lset(g, dst_idx);
        let dst_a = emitOffsetAddress(g, f, dbase, dst_idx, sp.elem_bytes);
        let src_a = emitOffsetAddress(g, f, dbase, target, sp.elem_bytes);
        let bytes = emitScaledBytes(g, f, delta, sp.elem_bytes);
        lget(g, dst_a); lget(g, src_a); lget(g, bytes); memoryCopyOp(g);
    }
    op(g, OP_else_);
    // Shift [ge .. ge + (target - gs)) left -> to [gs .. target)
    if sp.elem_bytes != 0 {
        lget(g, target); lget(g, gs); op(g, OP_i32_sub); lset(g, delta);
        let dbase = local32(g, f);
        lget(g, focus); i32Const(g, SEQ_FOC_DATA); op(g, OP_i32_add); lset(g, dbase);
        let dst_a = emitOffsetAddress(g, f, dbase, gs, sp.elem_bytes);
        let src_a = emitOffsetAddress(g, f, dbase, ge, sp.elem_bytes);
        let bytes = emitScaledBytes(g, f, delta, sp.elem_bytes);
        lget(g, dst_a); lget(g, src_a); lget(g, bytes); memoryCopyOp(g);
    }
    close(g, f);
    lget(g, focus); lget(g, target); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_FOC_GSTART);
    lget(g, focus); lget(g, target); lget(g, glen); op(g, OP_i32_add);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_FOC_GEND);
    close(g, f);
}

// Kind 14: seq_focus_to_leaf(focus_ptr, epoch) -> leaf_ptr (0 if live_len == 0)
fn ensureSeqFocusToLeaf(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let create_fn, crerr = ensureSeqLeafCreate(g, sp);
    if crerr != squid_direct_types::Error.none { return 0, crerr; }
    let key = squid_direct_emit::key64(sp.elem_ty, 14);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32], [VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let focus = local(g, nf, VT_i32);
    let epoch = local(g, nf, VT_i32);
    nf.parameter_words = 2;
    let gs = local32(g, nf);
    let ge = local32(g, nf);
    let cap = local32(g, nf);
    let live = local32(g, nf);
    let out = local32(g, nf);
    let dbase = local32(g, nf);
    let i = local32(g, nf);
    lget(g, focus); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_GSTART); lset(g, gs);
    lget(g, focus); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_GEND); lset(g, ge);
    lget(g, focus); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_CAP); lset(g, cap);
    lget(g, cap); lget(g, ge); lget(g, gs); op(g, OP_i32_sub); op(g, OP_i32_sub); ltee(g, live);
    op(g, OP_i32_eqz);
    let zif = open(g, nf, OP_if_); i32Const(g, 0); op(g, OP_return_); close(g, nf);
    lget(g, epoch); callf(g, create_fn); lset(g, out);
    lget(g, focus); i32Const(g, SEQ_FOC_DATA); op(g, OP_i32_add); lset(g, dbase);
    if sp.leaf_kind == SEQ_KIND_FLAT {
        if sp.elem_bytes != 0 {
            let bl = emitScaledBytes(g, nf, gs, sp.elem_bytes);
            let rcnt = local32(g, nf);
            lget(g, cap); lget(g, ge); op(g, OP_i32_sub); lset(g, rcnt);
            let br_b = emitScaledBytes(g, nf, rcnt, sp.elem_bytes);
            lget(g, gs);
            let has_l = open(g, nf, OP_if_);
            lget(g, out); i32Const(g, SEQ_LEAF_DATA); op(g, OP_i32_add);
            lget(g, dbase); lget(g, bl); memoryCopyOp(g);
            close(g, nf);
            lget(g, rcnt);
            let has_r = open(g, nf, OP_if_);
            let rsrc = emitOffsetAddress(g, nf, dbase, ge, sp.elem_bytes);
            lget(g, out); i32Const(g, SEQ_LEAF_DATA); op(g, OP_i32_add); lget(g, bl); op(g, OP_i32_add);
            lget(g, rsrc); lget(g, br_b); memoryCopyOp(g);
            close(g, nf);
        }
        lget(g, out); lget(g, live); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
    } else if sp.leaf_kind == SEQ_KIND_PACKED_SOA {
        // Inline SoA transpose directly into column pointers (zero per-element calls!).
        var col_ptrs: u32[16] = [0; 16];
        for st in 0..sp.packed.stream_count {
            col_ptrs[st] = local32(g, nf);
            lget(g, out); i32Const(g, sp.soa_col_off[st]); op(g, OP_i32_add); lset(g, col_ptrs[st]);
        }
        let gap_len = local32(g, nf);
        let phys = local32(g, nf);
        lget(g, ge); lget(g, gs); op(g, OP_i32_sub); lset(g, gap_len);
        i32Const(g, 0); lset(g, i);
        let b1 = open(g, nf, OP_block); let l1 = open(g, nf, OP_loop);
        lget(g, i); lget(g, live); op(g, OP_i32_ge_u); br(g, nf, OP_br_if, b1);
        lget(g, i);
        lget(g, i); lget(g, gap_len); op(g, OP_i32_add);
        lget(g, i); lget(g, gs); op(g, OP_i32_lt_u);
        op(g, OP_select); lset(g, phys);
        let a1 = emitOffsetAddress(g, nf, dbase, phys, sp.elem_bytes);
        let v1, err1 = readFlat(g, nf, a1, 0, sp.elem_ty, 0);
        if err1 != squid_direct_types::Error.none {
            squid_direct_relocations::rewind(sites_mark);
            s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
            return 0, err1;
        }
        var inner_val = v1;
        if sp.packed.soa_is_nominal {
            let uw, uerr = unwrapVariant(g, nf, v1, sp.packed.soa_nominal_tag, 0);
            if uerr != squid_direct_types::Error.none {
                squid_direct_relocations::rewind(sites_mark);
                s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                return 0, uerr;
            }
            inner_val = uw;
        }
        for fi in 0..sp.packed.soa_field_count {
            let st = sp.packed.soa_field_stream[fi];
            if st < 0 { continue; }
            var fv = neverVal();
            if sp.packed.soa_is_record {
                let got, gerr = recordField(g, nf, inner_val, fi, 0);
                if gerr != squid_direct_types::Error.none {
                    squid_direct_relocations::rewind(sites_mark);
                    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                    return 0, gerr;
                }
                fv = got;
            } else {
                let got, gerr = tupleItem(g, nf, inner_val, fi, 0);
                if gerr != squid_direct_types::Error.none {
                    squid_direct_relocations::rewind(sites_mark);
                    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                    return 0, gerr;
                }
                fv = got;
            }
            let werr = writeElement(g, nf, col_ptrs[st], 0, fv, 0);
            if werr != squid_direct_types::Error.none {
                squid_direct_relocations::rewind(sites_mark);
                s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                return 0, werr;
            }
            lget(g, col_ptrs[st]); i32Const(g, sp.packed.stream_stride[st]); op(g, OP_i32_add); lset(g, col_ptrs[st]);
        }
        lget(g, i); i32Const(g, 1); op(g, OP_i32_add); lset(g, i);
        br(g, nf, OP_br, l1);
        close(g, nf); close(g, nf);
        lget(g, out); lget(g, live); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
    } else {
        // Inline SEQ_KIND_PACKED_SUM packing with in-register sub-stream pointers/lens/caps (zero app_fn calls!).
        let cases, cerr = g.types.variants(sp.elem_ty);
        if cerr != squid_direct_types::Error.none {
            squid_direct_relocations::rewind(sites_mark);
            s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
            return 0, cerr;
        }
        var sub_ptrs: u32[16] = [0; 16];
        var sub_lens: u32[16] = [0; 16];
        var sub_caps: u32[16] = [0; 16];
        for st in 1..sp.packed.stream_count {
            let si = st - 1;
            sub_ptrs[si] = constLocal(g, nf, 0);
            sub_lens[si] = constLocal(g, nf, 0);
            sub_caps[si] = constLocal(g, nf, 0);
        }
        let gap_len = local32(g, nf);
        let phys = local32(g, nf);
        let vtag_loc = local32(g, nf);
        let tags_dst = local32(g, nf);
        lget(g, ge); lget(g, gs); op(g, OP_i32_sub); lset(g, gap_len);
        lget(g, out); i32Const(g, SEQ_SUM_TAGS); op(g, OP_i32_add); lset(g, tags_dst);
        i32Const(g, 0); lset(g, i);
        let b1 = open(g, nf, OP_block); let l1 = open(g, nf, OP_loop);
        lget(g, i); lget(g, live); op(g, OP_i32_ge_u); br(g, nf, OP_br_if, b1);
        lget(g, i);
        lget(g, i); lget(g, gap_len); op(g, OP_i32_add);
        lget(g, i); lget(g, gs); op(g, OP_i32_lt_u);
        op(g, OP_select); lset(g, phys);
        let a1 = emitOffsetAddress(g, nf, dbase, phys, sp.elem_bytes);
        let v1, err1 = readFlat(g, nf, a1, 0, sp.elem_ty, 0);
        if err1 != squid_direct_types::Error.none {
            squid_direct_relocations::rewind(sites_mark);
            s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
            return 0, err1;
        }
        let terr = emitValueTag(g, nf, v1, 0);
        if terr != squid_direct_types::Error.none {
            squid_direct_relocations::rewind(sites_mark);
            s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
            return 0, terr;
        }
        lset(g, vtag_loc);
        let done_v = open(g, nf, OP_block);
        for ci in 0..(cases.len as i64) {
            let vtag = g.types.variant_tags[cases.tags + ci];
            let st = sp.packed.variant_stream[ci];
            lget(g, vtag_loc); i32Const(g, vtag); op(g, OP_i32_eq);
            let arm = open(g, nf, OP_if_);
            lget(g, tags_dst); lget(g, i); op(g, OP_i32_add);
            i32Const(g, ci as u32);
            op(g, OP_i32_store8); uleb(g, 0); uleb(g, 0);
            if st >= 1 {
                let si = st - 1;
                let step = sp.packed.stream_stride[st];
                lget(g, sub_lens[si]); lget(g, sub_caps[si]); op(g, OP_i32_ge_u);
                let grow = open(g, nf, OP_if_);
                let ncap = local32(g, nf);
                let nptr = local32(g, nf);
                lget(g, sub_caps[si]); i32Const(g, 1); op(g, OP_i32_shl);
                i32Const(g, 2);
                lget(g, sub_caps[si]);
                op(g, OP_select);
                ltee(g, ncap);
                i32Const(g, 32); op(g, OP_i32_gt_u);
                let c32 = open(g, nf, OP_if_); i32Const(g, 32); lset(g, ncap); close(g, nf);
                let ab = emitScaledBytes(g, nf, ncap, step);
                lget(g, ab); callf(g, g.s.seq_alloc_fn); lset(g, nptr);
                lget(g, sub_lens[si]);
                let ho = open(g, nf, OP_if_);
                let cb = emitScaledBytes(g, nf, sub_lens[si], step);
                lget(g, nptr); lget(g, sub_ptrs[si]); lget(g, cb); memoryCopyOp(g);
                close(g, nf);
                lget(g, nptr); lset(g, sub_ptrs[si]);
                lget(g, ncap); lset(g, sub_caps[si]);
                close(g, nf);
                let paddr = emitOffsetAddress(g, nf, sub_ptrs[si], sub_lens[si], step);
                let uw, uerr = unwrapVariant(g, nf, v1, vtag, 0);
                if uerr != squid_direct_types::Error.none {
                    squid_direct_relocations::rewind(sites_mark);
                    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                    return 0, uerr;
                }
                let werr = writeElement(g, nf, paddr, 0, uw, 0);
                if werr != squid_direct_types::Error.none {
                    squid_direct_relocations::rewind(sites_mark);
                    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                    return 0, werr;
                }
                lget(g, sub_lens[si]); i32Const(g, 1); op(g, OP_i32_add); lset(g, sub_lens[si]);
            }
            br(g, nf, OP_br, done_v);
            close(g, nf);
        }
        close(g, nf);
        lget(g, i); i32Const(g, 1); op(g, OP_i32_add); lset(g, i);
        br(g, nf, OP_br, l1);
        close(g, nf); close(g, nf);
        for st in 1..sp.packed.stream_count {
            let si = st - 1;
            let siu = si as u32;
            lget(g, out); lget(g, sub_ptrs[si]); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_SUM_SUB_PTRS + siu * 4);
            lget(g, out); lget(g, sub_lens[si]); op(g, OP_i32_store8); uleb(g, 0); uleb(g, sp.sum_sub_lens_off + siu);
            lget(g, out); lget(g, sub_caps[si]); op(g, OP_i32_store8); uleb(g, 0); uleb(g, sp.sum_sub_caps_off + siu);
        }
        lget(g, out); lget(g, live); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
    }
    lget(g, out);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// Kind 15: seq_normalized_root(hdr_ptr, epoch) -> root_edge (with root_rev applied & focus merged; non-destructive!)
fn ensureSeqNormalizedRoot(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let f2l_fn, ferr = ensureSeqFocusToLeaf(g, sp);
    if ferr != squid_direct_types::Error.none { return 0, ferr; }
    let split_fn, serr = ensureSeqTreeSplit(g, sp);
    if serr != squid_direct_types::Error.none { return 0, serr; }
    let concat_fn, cerr = ensureSeqTreeConcat(g, sp);
    if cerr != squid_direct_types::Error.none { return 0, cerr; }
    let key = squid_direct_emit::key64(sp.elem_ty, 15);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32], [VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let hdr = local(g, nf, VT_i32);
    let epoch = local(g, nf, VT_i32);
    nf.parameter_words = 2;
    let root = local32(g, nf);
    let rev = local32(g, nf);
    let foc = local32(g, nf);
    let fstart = local32(g, nf);
    let fold = local32(g, nf);
    let fleaf = local32(g, nf);
    let left = local32(g, nf);
    let rest = local32(g, nf);
    let right = local32(g, nf);
    let merged = local32(g, nf);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_ROOT); lset(g, root);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_REV); lset(g, rev);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FOCUS); ltee(g, foc);
    op(g, OP_i32_eqz);
    let no_foc = open(g, nf, OP_if_);
    lget(g, root); lget(g, rev); op(g, OP_i32_xor);
    i32Const(g, 0);
    lget(g, root);
    op(g, OP_select);
    op(g, OP_return_);
    close(g, nf);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FSTART); lset(g, fstart);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FOLDLEN); lset(g, fold);
    lget(g, foc); lget(g, epoch); callf(g, f2l_fn); lset(g, fleaf);
    lget(g, root); lget(g, fstart); lget(g, epoch); callf(g, split_fn);
    lset(g, rest); lset(g, left);
    lget(g, fold);
    let has_old = open(g, nf, OP_if_);
    lget(g, rest); lget(g, fold); lget(g, epoch); callf(g, split_fn);
    lset(g, right); op(g, OP_drop);
    op(g, OP_else_);
    lget(g, rest); lset(g, right);
    close(g, nf);
    lget(g, left); lget(g, fleaf); lget(g, epoch); callf(g, concat_fn);
    lget(g, right); lget(g, epoch); callf(g, concat_fn);
    lset(g, merged);
    lget(g, merged); lget(g, rev); op(g, OP_i32_xor);
    i32Const(g, 0);
    lget(g, merged);
    op(g, OP_select);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// Type-independent O(1)-amortized in-place right-spine leaf append:
// seq_tree_push_leaf(root, fleaf, epoch) -> root (or 0 to fall back to concat_fn).
// Handles 15/16 of sequential append flushes with zero allocations, zero stack traffic,
// zero memory.copy, and exact radix_shift preservation!
fn ensureSeqTreePushLeaf(g: Generator&) -> u32, Error {
    let new2_fn, n2err = ensureSeqNodeNew2(g);
    if n2err != squid_direct_types::Error.none { return 0, n2err; }
    let key = squid_direct_emit::key64(0xffffffff, 110);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32, VT_i32], [VT_i32]));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let root = local(g, nf, VT_i32);
    let fleaf = local(g, nf, VT_i32);
    let epoch = local(g, nf, VT_i32);
    nf.parameter_words = 3;
    let flen = local32(g, nf);
    let cur = local32(g, nf);
    let meta = local32(g, nf);
    let cnt = local32(g, nf);
    let h = local32(g, nf);
    let old_len = local32(g, nf);
    let new_len = local32(g, nf);
    let sh = local32(g, nf);
    let c0 = local32(g, nf);
    let prev_last = local32(g, nf);
    let unit = local32(g, nf);
    let carry = local32(g, nf);
    let nn = local32(g, nf);
    let lvl = local32(g, nf);
    let a_cur = local32(g, nf);
    let bump_n = local32(g, nf);
    let anc0 = constLocal(g, nf, 0);
    let anc1 = constLocal(g, nf, 0);
    let anc2 = constLocal(g, nf, 0);
    let anc3 = constLocal(g, nf, 0);
    let depth = constLocal(g, nf, 0);
    lget(g, fleaf); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_LEAF_LEN); lset(g, flen);
    lget(g, root); lset(g, cur);
    let do_bump = open(g, nf, OP_block);
    let lp = open(g, nf, OP_loop);
    // Reject reversed node, leaf root, or shared epoch
    lget(g, cur); i32Const(g, 1); op(g, OP_i32_and);
    let is_rev = open(g, nf, OP_if_); i32Const(g, 0); op(g, OP_return_); close(g, nf);
    lget(g, cur); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_META); ltee(g, meta);
    i32Const(g, 15); op(g, OP_i32_and);
    let is_leaf = open(g, nf, OP_if_); i32Const(g, 0); op(g, OP_return_); close(g, nf);
    lget(g, cur); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_EPOCH); lget(g, epoch); op(g, OP_i32_ne);
    let is_shared = open(g, nf, OP_if_); i32Const(g, 0); op(g, OP_return_); close(g, nf);
    lget(g, meta); i32Const(g, 8); op(g, OP_i32_shr_u); i32Const(g, 255); op(g, OP_i32_and); lset(g, cnt);
    lget(g, meta); i32Const(g, 16); op(g, OP_i32_shr_u); i32Const(g, 255); op(g, OP_i32_and); lset(g, h);
    lget(g, h); i32Const(g, 1); op(g, OP_i32_eq);
    let is_h1 = open(g, nf, OP_if_);
    lget(g, cnt); i32Const(g, 16); op(g, OP_i32_lt_u);
    let has_room = open(g, nf, OP_if_);
    // Fast path (15/16 of flushes): append fleaf directly into cur.children[cnt]!
    lget(g, cur); lget(g, cnt); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    lget(g, fleaf); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    lget(g, cur); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_LEN); ltee(g, old_len);
    lget(g, flen); op(g, OP_i32_add); lset(g, new_len);
    lget(g, cur); lget(g, cnt); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    lget(g, new_len); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_PREFIXES);
    lget(g, cur); lget(g, new_len); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_LEN);
    lget(g, meta); i32Const(g, 24); op(g, OP_i32_shr_u); lset(g, sh);
    lget(g, cnt); i32Const(g, 1); op(g, OP_i32_eq);
    let was_one = open(g, nf, OP_if_);
    lget(g, cur); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_PREFIXES); lset(g, c0);
    lget(g, c0); op(g, OP_i32_ctz);
    i32Const(g, 0);
    lget(g, c0); i32Const(g, 2); op(g, OP_i32_ge_u);
    lget(g, c0); lget(g, c0); i32Const(g, 1); op(g, OP_i32_sub); op(g, OP_i32_and); op(g, OP_i32_eqz); op(g, OP_i32_and);
    lget(g, flen); lget(g, c0); op(g, OP_i32_le_u); op(g, OP_i32_and);
    op(g, OP_select); lset(g, sh);
    op(g, OP_else_);
    lget(g, sh);
    let had_sh = open(g, nf, OP_if_);
    lget(g, old_len);
    lget(g, cur); lget(g, cnt); i32Const(g, 2); op(g, OP_i32_sub); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_PREFIXES);
    op(g, OP_i32_sub); lset(g, prev_last);
    i32Const(g, 1); lget(g, sh); op(g, OP_i32_shl); lset(g, unit);
    lget(g, prev_last); lget(g, unit); op(g, OP_i32_ne);
    lget(g, flen); lget(g, unit); op(g, OP_i32_gt_u); op(g, OP_i32_or);
    let clr_sh = open(g, nf, OP_if_); i32Const(g, 0); lset(g, sh); close(g, nf);
    close(g, nf);
    close(g, nf);
    lget(g, cur);
    lget(g, cnt); i32Const(g, 1); op(g, OP_i32_add); i32Const(g, 8); op(g, OP_i32_shl);
    i32Const(g, 1 << 16); op(g, OP_i32_or);
    lget(g, sh); i32Const(g, 24); op(g, OP_i32_shl); op(g, OP_i32_or);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_META);
    lget(g, depth); lset(g, bump_n);
    br(g, nf, OP_br, do_bump);
    close(g, nf);
    // Dense 16+1 carry propagation (1/16 of flushes): keeps EVERY internal node full 16-way
    // and preserves exact power-of-2 radix_shift at EVERY tree level!
    i32Const(g, SEQ_NODE_BYTES); callf(g, g.s.seq_alloc_fn); lset(g, carry);
    lget(g, carry); i32Const(g, (1 << 8) | (1 << 16)); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_META);
    lget(g, carry); lget(g, epoch); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_EPOCH);
    lget(g, carry); lget(g, flen); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_LEN);
    lget(g, carry); lget(g, fleaf); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    lget(g, carry); lget(g, flen); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_PREFIXES);
    lget(g, carry); i32Const(g, SEQ_NODE_PREFIXES + 4); op(g, OP_i32_add);
    i32Const(g, 0xff); i32Const(g, 60); memoryFillOp(g);
    lget(g, depth); lset(g, lvl);
    let prop_done = open(g, nf, OP_block);
    let prop_lp = open(g, nf, OP_loop);
    lget(g, lvl); op(g, OP_i32_eqz); br(g, nf, OP_br_if, prop_done);
    lget(g, lvl); i32Const(g, 1); op(g, OP_i32_sub); lset(g, lvl);
    lget(g, anc0); lset(g, a_cur);
    lget(g, lvl); i32Const(g, 1); op(g, OP_i32_eq); let l1 = open(g, nf, OP_if_); lget(g, anc1); lset(g, a_cur); close(g, nf);
    lget(g, lvl); i32Const(g, 2); op(g, OP_i32_eq); let l2 = open(g, nf, OP_if_); lget(g, anc2); lset(g, a_cur); close(g, nf);
    lget(g, lvl); i32Const(g, 3); op(g, OP_i32_eq); let l3 = open(g, nf, OP_if_); lget(g, anc3); lset(g, a_cur); close(g, nf);
    lget(g, a_cur); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_META); ltee(g, meta);
    i32Const(g, 8); op(g, OP_i32_shr_u); i32Const(g, 255); op(g, OP_i32_and); lset(g, cnt);
    lget(g, meta); i32Const(g, 16); op(g, OP_i32_shr_u); i32Const(g, 255); op(g, OP_i32_and); lset(g, h);
    lget(g, cnt); i32Const(g, 16); op(g, OP_i32_lt_u);
    let a_room = open(g, nf, OP_if_);
    lget(g, a_cur); lget(g, cnt); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    lget(g, carry); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    lget(g, a_cur); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_LEN); ltee(g, old_len);
    lget(g, flen); op(g, OP_i32_add); lset(g, new_len);
    lget(g, a_cur); lget(g, cnt); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    lget(g, new_len); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_PREFIXES);
    lget(g, a_cur); lget(g, new_len); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_LEN);
    lget(g, meta); i32Const(g, 24); op(g, OP_i32_shr_u); lset(g, sh);
    lget(g, cnt); i32Const(g, 1); op(g, OP_i32_eq);
    let a_was_one = open(g, nf, OP_if_);
    lget(g, a_cur); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_PREFIXES); lset(g, c0);
    lget(g, c0); op(g, OP_i32_ctz);
    i32Const(g, 0);
    lget(g, c0); i32Const(g, 2); op(g, OP_i32_ge_u);
    lget(g, c0); lget(g, c0); i32Const(g, 1); op(g, OP_i32_sub); op(g, OP_i32_and); op(g, OP_i32_eqz); op(g, OP_i32_and);
    lget(g, flen); lget(g, c0); op(g, OP_i32_le_u); op(g, OP_i32_and);
    op(g, OP_select); lset(g, sh);
    op(g, OP_else_);
    lget(g, sh);
    let a_had_sh = open(g, nf, OP_if_);
    lget(g, old_len);
    lget(g, a_cur); lget(g, cnt); i32Const(g, 2); op(g, OP_i32_sub); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_PREFIXES);
    op(g, OP_i32_sub); lset(g, prev_last);
    i32Const(g, 1); lget(g, sh); op(g, OP_i32_shl); lset(g, unit);
    lget(g, prev_last); lget(g, unit); op(g, OP_i32_ne);
    lget(g, flen); lget(g, unit); op(g, OP_i32_gt_u); op(g, OP_i32_or);
    let a_clr = open(g, nf, OP_if_); i32Const(g, 0); lset(g, sh); close(g, nf);
    close(g, nf);
    close(g, nf);
    lget(g, a_cur);
    lget(g, cnt); i32Const(g, 1); op(g, OP_i32_add); i32Const(g, 8); op(g, OP_i32_shl);
    lget(g, h); i32Const(g, 16); op(g, OP_i32_shl); op(g, OP_i32_or);
    lget(g, sh); i32Const(g, 24); op(g, OP_i32_shl); op(g, OP_i32_or);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_META);
    lget(g, lvl); lset(g, bump_n);
    br(g, nf, OP_br, do_bump);
    close(g, nf);
    // Ancestor also full: wrap carry in 1-child node of height `h` and continue up!
    i32Const(g, SEQ_NODE_BYTES); callf(g, g.s.seq_alloc_fn); lset(g, nn);
    lget(g, nn); i32Const(g, 1 << 8); lget(g, h); i32Const(g, 16); op(g, OP_i32_shl); op(g, OP_i32_or);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_META);
    lget(g, nn); lget(g, epoch); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_EPOCH);
    lget(g, nn); lget(g, flen); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_LEN);
    lget(g, nn); lget(g, carry); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    lget(g, nn); lget(g, flen); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_PREFIXES);
    lget(g, nn); i32Const(g, SEQ_NODE_PREFIXES + 4); op(g, OP_i32_add);
    i32Const(g, 0xff); i32Const(g, 60); memoryFillOp(g);
    lget(g, nn); lset(g, carry);
    br(g, nf, OP_br, prop_lp);
    close(g, nf); close(g, nf);
    // Root itself was full: grow tree height by 1 with [root, carry]!
    lget(g, root); lget(g, carry);
    lget(g, root); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_META);
    i32Const(g, 16); op(g, OP_i32_shr_u); i32Const(g, 255); op(g, OP_i32_and);
    i32Const(g, 1); op(g, OP_i32_add);
    lget(g, epoch); callf(g, new2_fn);
    op(g, OP_return_);
    close(g, nf);
    // Record ancestor and descend rightmost child
    lget(g, depth); i32Const(g, 4); op(g, OP_i32_ge_u);
    let too_deep = open(g, nf, OP_if_); i32Const(g, 0); op(g, OP_return_); close(g, nf);
    lget(g, depth); i32Const(g, 0); op(g, OP_i32_eq); let d0 = open(g, nf, OP_if_); lget(g, cur); lset(g, anc0); close(g, nf);
    lget(g, depth); i32Const(g, 1); op(g, OP_i32_eq); let d1 = open(g, nf, OP_if_); lget(g, cur); lset(g, anc1); close(g, nf);
    lget(g, depth); i32Const(g, 2); op(g, OP_i32_eq); let d2 = open(g, nf, OP_if_); lget(g, cur); lset(g, anc2); close(g, nf);
    lget(g, depth); i32Const(g, 3); op(g, OP_i32_eq); let d3 = open(g, nf, OP_if_); lget(g, cur); lset(g, anc3); close(g, nf);
    lget(g, depth); i32Const(g, 1); op(g, OP_i32_add); lset(g, depth);
    lget(g, cur); lget(g, cnt); i32Const(g, 1); op(g, OP_i32_sub); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN); lset(g, cur);
    br(g, nf, OP_br, lp);
    close(g, nf);
    i32Const(g, 0); op(g, OP_return_);
    close(g, nf);
    // Bump len & last prefix (and verify radix_shift) on ancestors 0..bump_n-1!
    let ancs: u32[4] = [anc0, anc1, anc2, anc3];
    for ai in 0..4 {
        let a_loc = ancs[ai];
        lget(g, bump_n); i32Const(g, (ai + 1) as u32); op(g, OP_i32_ge_u);
        let has_a = open(g, nf, OP_if_);
        let ameta = local32(g, nf);
        let alast = local32(g, nf);
        let alen = local32(g, nf);
        let ash = local32(g, nf);
        let aprev = local32(g, nf);
        lget(g, a_loc); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_META); ltee(g, ameta);
        i32Const(g, 8); op(g, OP_i32_shr_u); i32Const(g, 255); op(g, OP_i32_and);
        i32Const(g, 1); op(g, OP_i32_sub); lset(g, alast);
        lget(g, a_loc); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_LEN);
        lget(g, flen); op(g, OP_i32_add); lset(g, alen);
        lget(g, a_loc); lget(g, alen); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_LEN);
        lget(g, a_loc); lget(g, alast); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
        lget(g, alen); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_PREFIXES);
        lget(g, ameta); i32Const(g, 24); op(g, OP_i32_shr_u); ltee(g, ash);
        let has_ash = open(g, nf, OP_if_);
        lget(g, alast);
        let has_ap = open(g, nf, OP_if_);
        lget(g, a_loc); lget(g, alast); i32Const(g, 1); op(g, OP_i32_sub); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_PREFIXES); lset(g, aprev);
        op(g, OP_else_);
        i32Const(g, 0); lset(g, aprev);
        close(g, nf);
        lget(g, alen); lget(g, aprev); op(g, OP_i32_sub);
        i32Const(g, 1); lget(g, ash); op(g, OP_i32_shl);
        op(g, OP_i32_gt_u);
        let clr_a = open(g, nf, OP_if_);
        lget(g, a_loc); lget(g, ameta); i32Const(g, 0x00ffffff); op(g, OP_i32_and);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_NODE_META);
        close(g, nf);
        close(g, nf);
        close(g, nf);
    }
    lget(g, root);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// Kind 16: seq_flush_focus(hdr_ptr, epoch) -> void (mutates hdr in base frame, keeping hdr.root_rev!)
fn ensureSeqFlushFocus(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let f2l_fn, ferr = ensureSeqFocusToLeaf(g, sp);
    if ferr != squid_direct_types::Error.none { return 0, ferr; }
    let split_fn, serr = ensureSeqTreeSplit(g, sp);
    if serr != squid_direct_types::Error.none { return 0, serr; }
    let concat_fn, cerr = ensureSeqTreeConcat(g, sp);
    if cerr != squid_direct_types::Error.none { return 0, cerr; }
    let push_leaf_fn, plerr = ensureSeqTreePushLeaf(g);
    if plerr != squid_direct_types::Error.none { return 0, plerr; }
    let key = squid_direct_emit::key64(sp.elem_ty, 16);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32], []));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let hdr = local(g, nf, VT_i32);
    let epoch = local(g, nf, VT_i32);
    nf.parameter_words = 2;
    let foc = local32(g, nf);
    let root = local32(g, nf);
    let fstart = local32(g, nf);
    let fold = local32(g, nf);
    let fleaf = local32(g, nf);
    let left = local32(g, nf);
    let rest = local32(g, nf);
    let right = local32(g, nf);
    let merged = local32(g, nf);
    let fast_r = local32(g, nf);
    lget(g, hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_APPEND_EP);
    lget(g, hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_PREPEND_EP);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FOCUS); ltee(g, foc);
    op(g, OP_i32_eqz);
    let zif = open(g, nf, OP_if_); op(g, OP_return_); close(g, nf);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_ROOT); lset(g, root);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FSTART); lset(g, fstart);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FOLDLEN); lset(g, fold);
    lget(g, foc); lget(g, epoch); callf(g, f2l_fn); lset(g, fleaf);
    // Fast right-end append path (skips split_fn and 15/16 of concat_fn calls!)
    lget(g, root); op(g, OP_i32_eqz);
    let empty_root = open(g, nf, OP_if_);
    lget(g, fleaf); lset(g, merged);
    op(g, OP_else_);
    lget(g, fold); op(g, OP_i32_eqz);
    lget(g, fleaf); i32Const(g, 0); op(g, OP_i32_ne); op(g, OP_i32_and);
    lget(g, fstart);
    lget(g, root); i32Const(g, 0xfffffffe); op(g, OP_i32_and); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_LEN);
    op(g, OP_i32_eq); op(g, OP_i32_and);
    let right_end = open(g, nf, OP_if_);
    lget(g, root); lget(g, fleaf); lget(g, epoch); callf(g, push_leaf_fn); ltee(g, fast_r);
    let did_fast = open(g, nf, OP_if_);
    lget(g, fast_r); lset(g, merged);
    op(g, OP_else_);
    lget(g, root); lget(g, fleaf); lget(g, epoch); callf(g, concat_fn); lset(g, merged);
    close(g, nf);
    op(g, OP_else_);
    lget(g, root); lget(g, fstart); lget(g, epoch); callf(g, split_fn);
    lset(g, rest); lset(g, left);
    lget(g, fold);
    let has_old = open(g, nf, OP_if_);
    lget(g, rest); lget(g, fold); lget(g, epoch); callf(g, split_fn);
    lset(g, right); op(g, OP_drop);
    op(g, OP_else_);
    lget(g, rest); lset(g, right);
    close(g, nf);
    lget(g, left); lget(g, fleaf); lget(g, epoch); callf(g, concat_fn);
    lget(g, right); lget(g, epoch); callf(g, concat_fn);
    lset(g, merged);
    close(g, nf);
    close(g, nf);
    lget(g, hdr); lget(g, merged); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_ROOT);
    lget(g, hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FOCUS);
    lget(g, hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FSTART);
    lget(g, hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FOLDLEN);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// ---- Header-level entry helpers: get, set, insert (push/push_front/insert), remove (pop/pop_front/remove) ----

// Kind 17: seq_hdr_get(hdr, idx) -> val...
// Flattened single-call lookup: caller hoists `rt.check` via `ensureCheckedArray`,
// and tree descent + v128 SIMD routing + FLAT/SPAN/RAMP leaf reads run inline with zero inner calls!
fn ensureSeqHdrGet(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let leaf_get_fn, lgerr = ensureSeqLeafGet(g, sp);
    if lgerr != squid_direct_types::Error.none { return 0, lgerr; }
    let key = squid_direct_emit::key64(sp.elem_ty, 17);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let lay, lerr = g.types.layout(sp.elem_ty);
    if lerr != squid_direct_types::Error.none { return 0, lerr; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32], lay));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let hdr = local(g, nf, VT_i32);
    let idx = local(g, nf, VT_i32);
    nf.parameter_words = 2;
    let total = local32(g, nf);
    let rev = local32(g, nf);
    let p = local32(g, nf);
    let foc = local32(g, nf);
    let fstart = local32(g, nf);
    let flive = local32(g, nf);
    let fold = local32(g, nf);
    let gs = local32(g, nf);
    let ge = local32(g, nf);
    let k = local32(g, nf);
    let phys = local32(g, nf);
    let edge = local32(g, nf);
    let ptr = local32(g, nf);
    let meta = local32(g, nf);
    let kind = local32(g, nf);
    let sh = local32(g, nf);
    let nlen = local32(g, nf);
    let np = local32(g, nf);
    let j = local32(g, nf);
    let prev = local32(g, nf);
    let vp = local(g, nf, VT_v128);
    let mask = local32(g, nf);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_LEN); lset(g, total);
    lget(g, idx); lget(g, total); op(g, OP_i32_ge_u); trap(g, nf);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_REV); lset(g, rev);
    lget(g, total); i32Const(g, 1); op(g, OP_i32_sub); lget(g, idx); op(g, OP_i32_sub);
    lget(g, idx); lget(g, rev); op(g, OP_select); lset(g, p);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FOCUS); ltee(g, foc);
    let has_foc = open(g, nf, OP_if_);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FSTART); lset(g, fstart);
    lget(g, p); lget(g, fstart); op(g, OP_i32_ge_u);
    let ge_start = open(g, nf, OP_if_);
    lget(g, foc); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_GSTART); lset(g, gs);
    lget(g, foc); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_GEND); lset(g, ge);
    lget(g, foc); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_CAP);
    lget(g, ge); lget(g, gs); op(g, OP_i32_sub); op(g, OP_i32_sub); lset(g, flive);
    lget(g, p); lget(g, fstart); op(g, OP_i32_sub); ltee(g, k);
    lget(g, flive); op(g, OP_i32_lt_u);
    let in_foc = open(g, nf, OP_if_);
    // O(1) direct readable FocusGap hit (even when frozen)!
    if sp.elem_bytes == 0 {
        op(g, OP_return_);
    } else {
        lget(g, k);
        lget(g, k); lget(g, ge); lget(g, gs); op(g, OP_i32_sub); op(g, OP_i32_add);
        lget(g, k); lget(g, gs); op(g, OP_i32_lt_u);
        op(g, OP_select); lset(g, phys);
        let dbase = local32(g, nf);
        lget(g, foc); i32Const(g, SEQ_FOC_DATA); op(g, OP_i32_add); lset(g, dbase);
        let addr = emitOffsetAddress(g, nf, dbase, phys, sp.elem_bytes);
        let loaded, err2 = loadElement(g, nf, addr, 0, sp.elem_ty, 0);
        if err2 != squid_direct_types::Error.none {
            squid_direct_relocations::rewind(sites_mark);
            s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
            return 0, err2;
        }
        seqPushVal(g, loaded);
        op(g, OP_return_);
    }
    close(g, nf);
    // p >= fstart + flive -> translate into tree coordinate: p = p - flive + fold
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FOLDLEN); lset(g, fold);
    lget(g, p); lget(g, flive); op(g, OP_i32_sub); lget(g, fold); op(g, OP_i32_add); lset(g, p);
    close(g, nf);
    close(g, nf);
    // Inline tree descent + dense radix-16 fast path + v128 SIMD fallback + FLAT/SPAN/RAMP leaf reads!
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_ROOT); lset(g, edge);
    let lp = open(g, nf, OP_loop);
    lget(g, edge); i32Const(g, 0xfffffffe); op(g, OP_i32_and); ltee(g, ptr);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_META); ltee(g, meta);
    i32Const(g, 15); op(g, OP_i32_and); ltee(g, kind);
    let is_leaf = open(g, nf, OP_if_);
    if sp.elem_bytes == 0 {
        op(g, OP_return_);
    } else {
        lget(g, kind); i32Const(g, SEQ_KIND_FLAT); op(g, OP_i32_eq);
        let is_flat = open(g, nf, OP_if_);
        let lpos = local32(g, nf);
        lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
        i32Const(g, 1); op(g, OP_i32_sub); lget(g, p); op(g, OP_i32_sub);
        lget(g, p);
        lget(g, edge); i32Const(g, 1); op(g, OP_i32_and);
        op(g, OP_select); lset(g, lpos);
        let lbase = local32(g, nf);
        lget(g, ptr); i32Const(g, SEQ_LEAF_DATA); op(g, OP_i32_add); lset(g, lbase);
        let laddr = emitOffsetAddress(g, nf, lbase, lpos, sp.elem_bytes);
        let loaded_f, ferr2 = loadElement(g, nf, laddr, 0, sp.elem_ty, 0);
        if ferr2 != squid_direct_types::Error.none {
            squid_direct_relocations::rewind(sites_mark);
            s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
            return 0, ferr2;
        }
        seqPushVal(g, loaded_f);
        op(g, OP_return_);
        close(g, nf);
        lget(g, kind); i32Const(g, SEQ_KIND_SPAN); op(g, OP_i32_eq);
        let is_span = open(g, nf, OP_if_);
        let spos = local32(g, nf);
        lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
        i32Const(g, 1); op(g, OP_i32_sub); lget(g, p); op(g, OP_i32_sub);
        lget(g, p);
        lget(g, edge); i32Const(g, 1); op(g, OP_i32_and);
        op(g, OP_select); lset(g, spos);
        let sbase = local32(g, nf);
        lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_SPAN_PTR); lset(g, sbase);
        let saddr = emitOffsetAddress(g, nf, sbase, spos, sp.elem_bytes);
        let loaded_s, serr2 = loadElement(g, nf, saddr, 0, sp.elem_ty, 0);
        if serr2 != squid_direct_types::Error.none {
            squid_direct_relocations::rewind(sites_mark);
            s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
            return 0, serr2;
        }
        seqPushVal(g, loaded_s);
        op(g, OP_return_);
        close(g, nf);
        if sp.elem_ty == squid_direct_types::u32_ {
            lget(g, kind); i32Const(g, SEQ_KIND_RAMP); op(g, OP_i32_eq);
            let is_ramp = open(g, nf, OP_if_);
            let rpos = local32(g, nf);
            lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
            i32Const(g, 1); op(g, OP_i32_sub); lget(g, p); op(g, OP_i32_sub);
            lget(g, p);
            lget(g, edge); i32Const(g, 1); op(g, OP_i32_and);
            op(g, OP_select); lset(g, rpos);
            lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_RAMP_START);
            lget(g, rpos);
            lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_RAMP_STEP);
            op(g, OP_i32_mul); op(g, OP_i32_add);
            op(g, OP_return_);
            close(g, nf);
        }
        lget(g, edge); lget(g, p); callf(g, leaf_get_fn); op(g, OP_return_);
    }
    close(g, nf);
    // Dense radix-16 fast path: zero node.len load, zero prefixes cache line, zero SIMD!
    lget(g, meta); i32Const(g, 24); op(g, OP_i32_shr_u); ltee(g, sh);
    lget(g, edge); i32Const(g, 1); op(g, OP_i32_and); op(g, OP_i32_eqz);
    op(g, OP_i32_and);
    let fast_radix = open(g, nf, OP_if_);
    lget(g, p); lget(g, sh); op(g, OP_i32_shr_u); lset(g, j);
    lget(g, p); lget(g, j); lget(g, sh); op(g, OP_i32_shl); op(g, OP_i32_sub); lset(g, p);
    lget(g, ptr); lget(g, j); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    lset(g, edge);
    br(g, nf, OP_br, lp);
    close(g, nf);
    // Reversed or relaxed internal node
    lget(g, ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_LEN); lset(g, nlen);
    lget(g, nlen); i32Const(g, 1); op(g, OP_i32_sub); lget(g, p); op(g, OP_i32_sub);
    lget(g, p);
    lget(g, edge); i32Const(g, 1); op(g, OP_i32_and);
    op(g, OP_select);
    lset(g, np);
    lget(g, sh);
    let rev_radix = open(g, nf, OP_if_);
    lget(g, np); lget(g, sh); op(g, OP_i32_shr_u); lset(g, j);
    lget(g, np); lget(g, j); lget(g, sh); op(g, OP_i32_shl); op(g, OP_i32_sub); lset(g, p);
    op(g, OP_else_);
    emitSeqSimdFindInline(g, nf, ptr, np, vp, mask); ltee(g, j);
    let has_prev = open(g, nf, OP_if_);
    lget(g, ptr); lget(g, j); i32Const(g, 1); op(g, OP_i32_sub); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_PREFIXES);
    lset(g, prev);
    op(g, OP_else_);
    i32Const(g, 0); lset(g, prev);
    close(g, nf);
    lget(g, np); lget(g, prev); op(g, OP_i32_sub); lset(g, p);
    close(g, nf);
    lget(g, ptr); lget(g, j); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    lset(g, edge);
    br(g, nf, OP_br, lp);
    close(g, nf);
    op(g, OP_unreachable_);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// Kind 18: seq_hdr_set(slot, gen, idx, val...) -> void
fn ensureSeqHdrSet(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let wr_fn, werr = ensureSeqWritable(g);
    if werr != squid_direct_types::Error.none { return 0, werr; }
    let tset_fn, tserr = ensureSeqTreeSet(g, sp);
    if tserr != squid_direct_types::Error.none { return 0, tserr; }
    let key = squid_direct_emit::key64(sp.elem_ty, 18);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let lay, lerr = g.types.layout(sp.elem_ty);
    if lerr != squid_direct_types::Error.none { return 0, lerr; }
    var ptypes: ValType[>..] = [VT_i32, VT_i32, VT_i32];
    for wt in lay { ptypes.push(wt); }
    let fn_id = g.module.addFunction(g.module.signature(ptypes[..], []));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let slot = local(g, nf, VT_i32);
    let gen = local(g, nf, VT_i32);
    let idx = local(g, nf, VT_i32);
    let val, verr = seqValFromParams(g, nf, sp.elem_ty, 0);
    if verr != squid_direct_types::Error.none {
        squid_direct_relocations::rewind(sites_mark);
        s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
        return 0, verr;
    }
    nf.parameter_words = (3 + lay.len) as u32;
    let entry = local32(g, nf);
    let hdr = local32(g, nf);
    let epoch = local32(g, nf);
    let total = local32(g, nf);
    let rev = local32(g, nf);
    let p = local32(g, nf);
    let foc = local32(g, nf);
    let fstart = local32(g, nf);
    let flive = local32(g, nf);
    let fold = local32(g, nf);
    let gs = local32(g, nf);
    let ge = local32(g, nf);
    let k = local32(g, nf);
    let phys = local32(g, nf);
    lget(g, slot); lget(g, gen); callf(g, wr_fn);
    lset(g, epoch); lset(g, hdr); lset(g, entry);
    lget(g, hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_APPEND_EP);
    lget(g, hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_PREPEND_EP);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_LEN); lset(g, total);
    lget(g, idx); lget(g, total); op(g, OP_i32_ge_u); trap(g, nf);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_REV); lset(g, rev);
    lget(g, total); i32Const(g, 1); op(g, OP_i32_sub); lget(g, idx); op(g, OP_i32_sub);
    lget(g, idx); lget(g, rev); op(g, OP_select); lset(g, p);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FOCUS); ltee(g, foc);
    let has_foc = open(g, nf, OP_if_);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FSTART); lset(g, fstart);
    lget(g, p); lget(g, fstart); op(g, OP_i32_ge_u);
    let ge_start = open(g, nf, OP_if_);
    lget(g, foc); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_GSTART); lset(g, gs);
    lget(g, foc); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_GEND); lset(g, ge);
    lget(g, foc); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_CAP);
    lget(g, ge); lget(g, gs); op(g, OP_i32_sub); op(g, OP_i32_sub); lset(g, flive);
    lget(g, p); lget(g, fstart); op(g, OP_i32_sub); ltee(g, k);
    lget(g, flive); op(g, OP_i32_lt_u);
    let in_foc = open(g, nf, OP_if_);
    // CoW-clone FocusGap if foc.epoch != epoch
    lget(g, foc); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_EPOCH); lget(g, epoch); op(g, OP_i32_ne);
    let cow_f = open(g, nf, OP_if_);
    let nfoc = local32(g, nf);
    i32Const(g, sp.focus_bytes); callf(g, g.s.seq_alloc_fn); ltee(g, nfoc);
    lget(g, foc); i32Const(g, sp.focus_bytes); memoryCopyOp(g);
    lget(g, nfoc); lget(g, epoch); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_FOC_EPOCH);
    lget(g, hdr); lget(g, nfoc); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FOCUS);
    lget(g, nfoc); lset(g, foc);
    close(g, nf);
    if sp.elem_bytes != 0 {
        lget(g, k);
        lget(g, k); lget(g, ge); lget(g, gs); op(g, OP_i32_sub); op(g, OP_i32_add);
        lget(g, k); lget(g, gs); op(g, OP_i32_lt_u);
        op(g, OP_select); lset(g, phys);
        let dbase = local32(g, nf);
        lget(g, foc); i32Const(g, SEQ_FOC_DATA); op(g, OP_i32_add); lset(g, dbase);
        let addr = emitOffsetAddress(g, nf, dbase, phys, sp.elem_bytes);
        let werr2 = writeElement(g, nf, addr, 0, val, 0);
        if werr2 != squid_direct_types::Error.none {
            squid_direct_relocations::rewind(sites_mark);
            s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
            return 0, werr2;
        }
    }
    op(g, OP_return_);
    close(g, nf);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FOLDLEN); lset(g, fold);
    lget(g, p); lget(g, flive); op(g, OP_i32_sub); lget(g, fold); op(g, OP_i32_add); lset(g, p);
    close(g, nf);
    close(g, nf);
    lget(g, hdr);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_ROOT);
    lget(g, p); seqPushVal(g, val); lget(g, epoch); callf(g, tset_fn);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_ROOT);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// Kind 19: seq_hdr_insert(slot, gen, idx, val...) -> void (unified O(1)-focus push / push_front / insert!)
fn ensureSeqHdrInsert(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let wr_fn, werr = ensureSeqWritable(g);
    if werr != squid_direct_types::Error.none { return 0, werr; }
    let flush_fn, ferr = ensureSeqFlushFocus(g, sp);
    if ferr != squid_direct_types::Error.none { return 0, ferr; }
    let key = squid_direct_emit::key64(sp.elem_ty, 19);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let lay, lerr = g.types.layout(sp.elem_ty);
    if lerr != squid_direct_types::Error.none { return 0, lerr; }
    var ptypes: ValType[>..] = [VT_i32, VT_i32, VT_i32];
    for wt in lay { ptypes.push(wt); }
    let fn_id = g.module.addFunction(g.module.signature(ptypes[..], []));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let slot = local(g, nf, VT_i32);
    let gen = local(g, nf, VT_i32);
    let idx = local(g, nf, VT_i32);
    let val, verr = seqValFromParams(g, nf, sp.elem_ty, 0);
    if verr != squid_direct_types::Error.none {
        squid_direct_relocations::rewind(sites_mark);
        s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
        return 0, verr;
    }
    nf.parameter_words = (3 + lay.len) as u32;
    let entry = local32(g, nf);
    let hdr = local32(g, nf);
    let epoch = local32(g, nf);
    let total = local32(g, nf);
    let rev = local32(g, nf);
    let cut = local32(g, nf);
    let foc = local32(g, nf);
    let fstart = local32(g, nf);
    let gs = local32(g, nf);
    let ge = local32(g, nf);
    let flive = local32(g, nf);
    let target = local32(g, nf);
    let ntotal = local32(g, nf);
    lget(g, slot); lget(g, gen); callf(g, wr_fn);
    lset(g, epoch); lset(g, hdr); lset(g, entry);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_LEN); lset(g, total);
    lget(g, idx); lget(g, total); op(g, OP_i32_gt_u); trap(g, nf);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_REV); lset(g, rev);
    // cut in unreversed base frame: rev ? (total - idx) : idx
    lget(g, total); lget(g, idx); op(g, OP_i32_sub);
    lget(g, idx); lget(g, rev); op(g, OP_select); lset(g, cut);
    // Check if existing focus can absorb this insert in O(1)!
    let need_new = local32(g, nf);
    i32Const(g, 1); lset(g, need_new);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FOCUS); ltee(g, foc);
    let has_foc = open(g, nf, OP_if_);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FSTART); lset(g, fstart);
    lget(g, foc); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_GSTART); lset(g, gs);
    lget(g, foc); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_GEND); lset(g, ge);
    i32Const(g, sp.leaf_cap); lget(g, ge); lget(g, gs); op(g, OP_i32_sub); op(g, OP_i32_sub); lset(g, flive);
    lget(g, flive); i32Const(g, sp.leaf_cap); op(g, OP_i32_lt_u);
    lget(g, cut); lget(g, fstart); op(g, OP_i32_ge_u); op(g, OP_i32_and);
    lget(g, cut); lget(g, fstart); lget(g, flive); op(g, OP_i32_add); op(g, OP_i32_le_u); op(g, OP_i32_and);
    let hit = open(g, nf, OP_if_);
    i32Const(g, 0); lset(g, need_new);
    // CoW-clone FocusGap if foc.epoch != epoch
    lget(g, foc); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_EPOCH); lget(g, epoch); op(g, OP_i32_ne);
    let cow_f = open(g, nf, OP_if_);
    let nfoc = local32(g, nf);
    i32Const(g, sp.focus_bytes); callf(g, g.s.seq_alloc_fn); ltee(g, nfoc);
    lget(g, foc); i32Const(g, sp.focus_bytes); memoryCopyOp(g);
    lget(g, nfoc); lget(g, epoch); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_FOC_EPOCH);
    lget(g, hdr); lget(g, nfoc); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FOCUS);
    lget(g, nfoc); lset(g, foc);
    close(g, nf);
    lget(g, cut); lget(g, fstart); op(g, OP_i32_sub); lset(g, target);
    emitSeqFocusMoveGap(g, nf, sp, foc, target);
    close(g, nf);
    close(g, nf);

    lget(g, need_new);
    let open_new = open(g, nf, OP_if_);
    let old_foc = local32(g, nf);
    lget(g, foc); lset(g, old_foc);
    lget(g, old_foc);
    let do_flush = open(g, nf, OP_if_);
    lget(g, hdr); lget(g, epoch); callf(g, flush_fn);
    close(g, nf);
    // Reuse exclusively-owned FocusGap in place after flushing its contents into a leaf!
    let reused_foc = local32(g, nf);
    i32Const(g, 0); lset(g, reused_foc);
    lget(g, old_foc);
    let chk_reuse = open(g, nf, OP_if_);
    lget(g, old_foc); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_EPOCH); lget(g, epoch); op(g, OP_i32_eq);
    let can_reuse = open(g, nf, OP_if_);
    lget(g, old_foc); lset(g, foc);
    i32Const(g, 1); lset(g, reused_foc);
    close(g, nf);
    close(g, nf);
    lget(g, reused_foc); op(g, OP_i32_eqz);
    let alloc_foc = open(g, nf, OP_if_);
    i32Const(g, sp.focus_bytes); callf(g, g.s.seq_alloc_fn); lset(g, foc);
    close(g, nf);
    lget(g, foc); lget(g, epoch); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_FOC_EPOCH);
    lget(g, foc); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_FOC_GSTART);
    lget(g, foc); i32Const(g, sp.leaf_cap); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_FOC_GEND);
    lget(g, foc); i32Const(g, sp.leaf_cap); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_FOC_CAP);
    lget(g, hdr); lget(g, foc); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FOCUS);
    lget(g, hdr); lget(g, cut); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FSTART);
    lget(g, hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FOLDLEN);
    close(g, nf);

    // Head-prepend fast layout: when inserting at cut == 0 of a non-empty seq with gap at 0,
    // write into `ge - 1` and decrement `ge` so subsequent `push_front`s stay shift-free at gs == 0!
    lget(g, foc); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_GSTART); lset(g, gs);
    lget(g, foc); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_GEND); lset(g, ge);
    lget(g, cut); op(g, OP_i32_eqz);
    lget(g, total); i32Const(g, 0); op(g, OP_i32_gt_u); op(g, OP_i32_and);
    lget(g, gs); op(g, OP_i32_eqz); op(g, OP_i32_and);
    lget(g, ge); i32Const(g, 0); op(g, OP_i32_gt_u); op(g, OP_i32_and);
    let prepend_end = open(g, nf, OP_if_);
    lget(g, ge); i32Const(g, 1); op(g, OP_i32_sub); lset(g, ge);
    if sp.elem_bytes != 0 {
        let dbase = local32(g, nf);
        lget(g, foc); i32Const(g, SEQ_FOC_DATA); op(g, OP_i32_add); lset(g, dbase);
        let addr = emitOffsetAddress(g, nf, dbase, ge, sp.elem_bytes);
        let werr2 = writeElement(g, nf, addr, 0, val, 0);
        if werr2 != squid_direct_types::Error.none {
            squid_direct_relocations::rewind(sites_mark);
            s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
            return 0, werr2;
        }
    }
    lget(g, foc); lget(g, ge); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_FOC_GEND);
    op(g, OP_else_);
    if sp.elem_bytes != 0 {
        let dbase = local32(g, nf);
        lget(g, foc); i32Const(g, SEQ_FOC_DATA); op(g, OP_i32_add); lset(g, dbase);
        let addr = emitOffsetAddress(g, nf, dbase, gs, sp.elem_bytes);
        let werr2 = writeElement(g, nf, addr, 0, val, 0);
        if werr2 != squid_direct_types::Error.none {
            squid_direct_relocations::rewind(sites_mark);
            s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
            return 0, werr2;
        }
    }
    lget(g, gs); i32Const(g, 1); op(g, OP_i32_add); lset(g, gs);
    lget(g, foc); lget(g, gs); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_FOC_GSTART);
    close(g, nf);
    lget(g, total); i32Const(g, 1); op(g, OP_i32_add); lset(g, ntotal);
    lget(g, hdr); lget(g, ntotal); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_LEN);
    lget(g, entry); lget(g, ntotal); op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    // Arm fast-append / fast-prepend cached epochs in SeqHeader for O(1) inline push/push_front/pop_front!
    let cur_fstart = local32(g, nf);
    let cur_fold = local32(g, nf);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FSTART); lset(g, cur_fstart);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FOLDLEN); lset(g, cur_fold);
    lget(g, hdr);
    lget(g, epoch); i32Const(g, 0);
    lget(g, rev); op(g, OP_i32_eqz);
    lget(g, cur_fold); op(g, OP_i32_eqz); op(g, OP_i32_and);
    lget(g, ge); i32Const(g, sp.leaf_cap); op(g, OP_i32_eq); op(g, OP_i32_and);
    lget(g, cur_fstart); lget(g, gs); op(g, OP_i32_add); lget(g, ntotal); op(g, OP_i32_eq); op(g, OP_i32_and);
    op(g, OP_select);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_APPEND_EP);
    lget(g, hdr);
    lget(g, epoch); i32Const(g, 0);
    lget(g, rev); op(g, OP_i32_eqz);
    lget(g, cur_fold); op(g, OP_i32_eqz); op(g, OP_i32_and);
    lget(g, cur_fstart); op(g, OP_i32_eqz); op(g, OP_i32_and);
    lget(g, gs); op(g, OP_i32_eqz); op(g, OP_i32_and);
    op(g, OP_select);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_PREPEND_EP);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// Kind 20: seq_hdr_remove(slot, gen, idx) -> val... (unified O(1)-focus/shadow pop / pop_front / remove!)
fn ensureSeqHdrRemove(g: Generator&, sp: const SeqPlan&) -> u32, Error {
    let wr_fn, werr = ensureSeqWritable(g);
    if werr != squid_direct_types::Error.none { return 0, werr; }
    let flush_fn, ferr = ensureSeqFlushFocus(g, sp);
    if ferr != squid_direct_types::Error.none { return 0, ferr; }
    let tget_fn, tgerr = ensureSeqTreeGet(g, sp);
    if tgerr != squid_direct_types::Error.none { return 0, tgerr; }
    let key = squid_direct_emit::key64(sp.elem_ty, 20);
    let existing, found = g.s.seq_helpers.get(key);
    if found { return existing, squid_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, squid_direct_types::Error.unsupported; }
    let lay, lerr = g.types.layout(sp.elem_ty);
    if lerr != squid_direct_types::Error.none { return 0, lerr; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32, VT_i32], lay));
    g.s.seq_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len; let sites_mark = squid_direct_relocations::mark();
    let locals_mark = s.locals.len; let labels_mark = s.labels.len; let handles_mark = s.handles.len; let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let slot = local(g, nf, VT_i32);
    let gen = local(g, nf, VT_i32);
    let idx = local(g, nf, VT_i32);
    nf.parameter_words = 3;
    let entry = local32(g, nf);
    let hdr = local32(g, nf);
    let epoch = local32(g, nf);
    let total = local32(g, nf);
    let rev = local32(g, nf);
    let p = local32(g, nf);
    let foc = local32(g, nf);
    let fstart = local32(g, nf);
    let fold = local32(g, nf);
    let gs = local32(g, nf);
    let ge = local32(g, nf);
    let flive = local32(g, nf);
    let k = local32(g, nf);
    let ntotal = local32(g, nf);
    let root = local32(g, nf);
    let tlen = local32(g, nf);
    let res_val, rverr = fresh(g, nf, sp.elem_ty, 0);
    if rverr != squid_direct_types::Error.none {
        squid_direct_relocations::rewind(sites_mark);
        s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
        return 0, rverr;
    }
    lget(g, slot); lget(g, gen); callf(g, wr_fn);
    lset(g, epoch); lset(g, hdr); lset(g, entry);
    lget(g, hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_APPEND_EP);
    lget(g, hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_PREPEND_EP);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_LEN); lset(g, total);
    lget(g, idx); lget(g, total); op(g, OP_i32_ge_u); trap(g, nf);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_REV); lset(g, rev);
    lget(g, total); i32Const(g, 1); op(g, OP_i32_sub); lget(g, idx); op(g, OP_i32_sub);
    lget(g, idx); lget(g, rev); op(g, OP_select); lset(g, p);
    lget(g, total); i32Const(g, 1); op(g, OP_i32_sub); lset(g, ntotal);

    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FOCUS); ltee(g, foc);
    let has_foc = open(g, nf, OP_if_);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FSTART); lset(g, fstart);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FOLDLEN); lset(g, fold);
    lget(g, foc); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_GSTART); lset(g, gs);
    lget(g, foc); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_GEND); lset(g, ge);
    i32Const(g, sp.leaf_cap); lget(g, ge); lget(g, gs); op(g, OP_i32_sub); op(g, OP_i32_sub); lset(g, flive);

    // Case 1: p inside active FocusGap [fstart .. fstart + flive) -> O(1) delete from gap!
    lget(g, p); lget(g, fstart); op(g, OP_i32_ge_u);
    lget(g, p); lget(g, fstart); lget(g, flive); op(g, OP_i32_add); op(g, OP_i32_lt_u);
    op(g, OP_i32_and);
    let in_foc = open(g, nf, OP_if_);
    lget(g, foc); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_EPOCH); lget(g, epoch); op(g, OP_i32_ne);
    let cow_f = open(g, nf, OP_if_);
    let nfoc = local32(g, nf);
    i32Const(g, sp.focus_bytes); callf(g, g.s.seq_alloc_fn); ltee(g, nfoc);
    lget(g, foc); i32Const(g, sp.focus_bytes); memoryCopyOp(g);
    lget(g, nfoc); lget(g, epoch); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_FOC_EPOCH);
    lget(g, hdr); lget(g, nfoc); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FOCUS);
    lget(g, nfoc); lset(g, foc);
    close(g, nf);
    lget(g, p); lget(g, fstart); op(g, OP_i32_sub); lset(g, k);
    emitSeqFocusMoveGap(g, nf, sp, foc, k);
    // Element to remove is now right at gap_end!
    lget(g, foc); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_GEND); lset(g, ge);
    if sp.elem_bytes != 0 {
        let dbase = local32(g, nf);
        lget(g, foc); i32Const(g, SEQ_FOC_DATA); op(g, OP_i32_add); lset(g, dbase);
        let addr = emitOffsetAddress(g, nf, dbase, ge, sp.elem_bytes);
        let loaded, lerr2 = loadElement(g, nf, addr, 0, sp.elem_ty, 0);
        if lerr2 != squid_direct_types::Error.none {
            squid_direct_relocations::rewind(sites_mark);
            s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
            return 0, lerr2;
        }
        let _ = copy(g, nf, loaded, res_val, 0);
    }
    lget(g, foc); lget(g, ge); i32Const(g, 1); op(g, OP_i32_add); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_FOC_GEND);
    lget(g, hdr); lget(g, ntotal); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_LEN);
    lget(g, entry); lget(g, ntotal); op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    seqPushVal(g, res_val); op(g, OP_return_);
    close(g, nf);

    // Case 2: p == fstart + flive (forward-delete right after focus!) and fold < leaf_cap
    lget(g, p); lget(g, fstart); lget(g, flive); op(g, OP_i32_add); op(g, OP_i32_eq);
    lget(g, fold); i32Const(g, sp.leaf_cap); op(g, OP_i32_lt_u); op(g, OP_i32_and);
    let fwd_del = open(g, nf, OP_if_);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_ROOT); lset(g, root);
    lget(g, root); lget(g, fstart); lget(g, fold); op(g, OP_i32_add); callf(g, tget_fn);
    let loaded_f, lferr = pop(g, nf, sp.elem_ty, 0);
    if lferr != squid_direct_types::Error.none {
        squid_direct_relocations::rewind(sites_mark);
        s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
        return 0, lferr;
    }
    let _ = copy(g, nf, loaded_f, res_val, 0);
    lget(g, hdr); lget(g, fold); i32Const(g, 1); op(g, OP_i32_add); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FOLDLEN);
    lget(g, hdr); lget(g, ntotal); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_LEN);
    lget(g, entry); lget(g, ntotal); op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    seqPushVal(g, res_val); op(g, OP_return_);
    close(g, nf);

    // Case 3: p + 1 == fstart (backspace right before focus!) and fold < leaf_cap
    lget(g, p); i32Const(g, 1); op(g, OP_i32_add); lget(g, fstart); op(g, OP_i32_eq);
    lget(g, fold); i32Const(g, sp.leaf_cap); op(g, OP_i32_lt_u); op(g, OP_i32_and);
    let bk_del = open(g, nf, OP_if_);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_ROOT); lset(g, root);
    lget(g, root); lget(g, p); callf(g, tget_fn);
    let loaded_b, lberr = pop(g, nf, sp.elem_ty, 0);
    if lberr != squid_direct_types::Error.none {
        squid_direct_relocations::rewind(sites_mark);
        s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
        return 0, lberr;
    }
    let _ = copy(g, nf, loaded_b, res_val, 0);
    lget(g, hdr); lget(g, p); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FSTART);
    lget(g, hdr); lget(g, fold); i32Const(g, 1); op(g, OP_i32_add); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FOLDLEN);
    lget(g, hdr); lget(g, ntotal); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_LEN);
    lget(g, entry); lget(g, ntotal); op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    seqPushVal(g, res_val); op(g, OP_return_);
    close(g, nf);

    // Otherwise flush old focus before opening shadow focus at p
    lget(g, hdr); lget(g, epoch); callf(g, flush_fn);
    close(g, nf);

    // Read element p from tree, then open empty shadow FocusGap at (fstart = p, fold = 1)!
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_ROOT); lset(g, root);
    lget(g, root); lget(g, p); callf(g, tget_fn);
    let loaded_t, lterr = pop(g, nf, sp.elem_ty, 0);
    if lterr != squid_direct_types::Error.none {
        squid_direct_relocations::rewind(sites_mark);
        s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
        return 0, lterr;
    }
    let _ = copy(g, nf, loaded_t, res_val, 0);
    // If sequence just became empty, clear root & focus directly!
    lget(g, ntotal); op(g, OP_i32_eqz);
    let now_empty = open(g, nf, OP_if_);
    lget(g, hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_ROOT);
    lget(g, hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FOCUS);
    lget(g, hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FSTART);
    lget(g, hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FOLDLEN);
    op(g, OP_else_);
    i32Const(g, sp.focus_bytes); callf(g, g.s.seq_alloc_fn); lset(g, foc);
    lget(g, foc); lget(g, epoch); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_FOC_EPOCH);
    lget(g, foc); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_FOC_GSTART);
    lget(g, foc); i32Const(g, sp.leaf_cap); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_FOC_GEND);
    lget(g, foc); i32Const(g, sp.leaf_cap); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_FOC_CAP);
    lget(g, hdr); lget(g, foc); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FOCUS);
    lget(g, hdr); lget(g, p); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FSTART);
    lget(g, hdr); i32Const(g, 1); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FOLDLEN);
    close(g, nf);
    lget(g, hdr); lget(g, ntotal); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_LEN);
    lget(g, entry); lget(g, ntotal); op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    seqPushVal(g, res_val);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    squid_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
    return fn_id, squid_direct_types::Error.none;
}

// ---- Public emitters called by storageOp / data / calls / control ----

fn emitSeqEmpty(g: Generator&, f: Fn&, ty: Ty, id: u32) -> Val, Error {
    let ep_fn, eerr = ensureSeqNextEpoch(g);
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let open_fn, oerr = ensureSeqHdrOpen(g);
    if oerr != squid_direct_types::Error.none { return neverVal(), oerr; }
    noteAllocation(f);
    i32Const(g, 0);
    i32Const(g, 0);
    i32Const(g, 0);
    callf(g, ep_fn);
    callf(g, open_fn);
    let handle, perr = pop(g, f, ty, id);
    if perr != squid_direct_types::Error.none { return handle, perr; }
    recordMutable(g, f, handle);
    return handle, squid_direct_types::Error.none;
}

fn emitSeqFromValues(g: Generator&, f: Fn&, ty: Ty, values: Vals, id: u32) -> Val, Error {
    let handle, herr = emitSeqEmpty(g, f, ty, id);
    if herr != squid_direct_types::Error.none { return handle, herr; }
    if values.len == 0 { return handle, squid_direct_types::Error.none; }
    let elem_ty, eerr = elementOf(g, f, ty, id);
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let sp, sperr = computeSeqPlan(g, f, elem_ty, id);
    if sperr != squid_direct_types::Error.none { return neverVal(), sperr; }
    let ins_fn, ierr = ensureSeqHdrInsert(g, sp);
    if ierr != squid_direct_types::Error.none { return neverVal(), ierr; }
    for idx in 0..(values.len as i64) {
        let v = g.s.vals[values.start + idx];
        let noted = noteStoreToSlot(g, f, w(g, handle, 0), v);
        if noted != squid_direct_types::Error.none { return neverVal(), noted; }
        lget(g, w(g, handle, 0));
        lget(g, w(g, handle, 1));
        i32Const(g, idx as u32);
        seqPushVal(g, v);
        callf(g, ins_fn);
    }
    invalidateCheckedOwner(g, f, handle);
    return handle, squid_direct_types::Error.none;
}

fn emitSeqReadVal(g: Generator&, f: Fn&, container: Val, index: u32, id: u32) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, container.ty, id);
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let sp, sperr = computeSeqPlan(g, f, elem_ty, id);
    if sperr != squid_direct_types::Error.none { return neverVal(), sperr; }
    let get_fn, gerr = ensureSeqHdrGet(g, sp);
    if gerr != squid_direct_types::Error.none { return neverVal(), gerr; }
    let hdr_base, _ = ensureCheckedArray(g, f, container);
    lget(g, hdr_base);
    lget(g, index);
    callf(g, get_fn);
    return pop(g, f, elem_ty, id);
}

fn emitSeqSetVal(g: Generator&, f: Fn&, container: Val, index: u32, value: Val, id: u32) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, container.ty, id);
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let sp, sperr = computeSeqPlan(g, f, elem_ty, id);
    if sperr != squid_direct_types::Error.none { return neverVal(), sperr; }
    let set_fn, serr = ensureSeqHdrSet(g, sp);
    if serr != squid_direct_types::Error.none { return neverVal(), serr; }
    let noted = noteStoreToSlot(g, f, w(g, container, 0), value);
    if noted != squid_direct_types::Error.none { return neverVal(), noted; }
    lget(g, w(g, container, 0));
    lget(g, w(g, container, 1));
    lget(g, index);
    seqPushVal(g, value);
    callf(g, set_fn);
    invalidateCheckedContainers(f);
    return container, squid_direct_types::Error.none;
}

recursive fn emitSeqIndexedUpdate(g: Generator&, f: Fn&, id: u32, container: Val, at: i64) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let info = m.updateInfo(id);
    let selectors = m.updateSelectors(id);
    let pos_val, perr = expr(g, f, selectors[at].index);
    if perr != squid_direct_types::Error.none { return pos_val, perr; }
    let index, ierr = scalarLocal(g, f, pos_val, id);
    if ierr != squid_direct_types::Error.none { return neverVal(), ierr; }
    if at + 1 < selectors.len && selectors[at + 1].kind == squid_check_core::UpdateKind.index {
        let inner, rerr = emitSeqReadVal(g, f, container, index, id);
        if rerr != squid_direct_types::Error.none { return neverVal(), rerr; }
        let _, uerr = indexedUpdate(g, f, id, inner, at + 1);
        if uerr != squid_direct_types::Error.none { return neverVal(), uerr; }
        return container, squid_direct_types::Error.none;
    }
    var replacement = neverVal();
    if at + 1 == selectors.len {
        if info.self_binding != 0 && uses(g, f, info.self_binding) != 0 {
            let old, rerr = emitSeqReadVal(g, f, container, index, id);
            if rerr != squid_direct_types::Error.none { return neverVal(), rerr; }
            bindPut(g, f, info.self_binding, old);
        }
        let val, verr = stmt(g, f, info.value);
        if verr != squid_direct_types::Error.none { return val, verr; }
        if val.ty == squid_direct_types::never { return val, squid_direct_types::Error.none; }
        replacement = val;
    } else {
        let old, rerr = emitSeqReadVal(g, f, container, index, id);
        if rerr != squid_direct_types::Error.none { return neverVal(), rerr; }
        let updated, uerr = updateAt(g, f, id, old, at + 1);
        if uerr != squid_direct_types::Error.none { return updated, uerr; }
        if updated.ty == squid_direct_types::never { return updated, squid_direct_types::Error.none; }
        replacement = updated;
    }
    return emitSeqSetVal(g, f, container, index, replacement, id);
}

fn emitSeqPushVal(g: Generator&, f: Fn&, container: Val, value: Val, id: u32, selective: bool = false) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, container.ty, id);
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let sp, sperr = computeSeqPlan(g, f, elem_ty, id);
    if sperr != squid_direct_types::Error.none { return neverVal(), sperr; }
    let ins_fn, ierr = ensureSeqHdrInsert(g, sp);
    if ierr != squid_direct_types::Error.none { return neverVal(), ierr; }
    let noted = noteStoreToSlot(g, f, w(g, container, 0), value);
    if noted != squid_direct_types::Error.none { return neverVal(), noted; }
    let entry = ensureCheckedGrow(g, f, container);
    let hdr = local32(g, f);
    let total = local32(g, f);
    let foc = local32(g, f);
    let gs = local32(g, f);
    lget(g, entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base); lset(g, hdr);
    let push_done = open(g, f, OP_block);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FAST_APPEND_EP);
    gget(g, g.s.seq_min_mutable_epoch); op(g, OP_i32_ge_u);
    let ep_ok = open(g, f, OP_if_);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FOCUS); ltee(g, foc);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_GSTART); ltee(g, gs);
    i32Const(g, sp.leaf_cap); op(g, OP_i32_lt_u);
    let do_fast = open(g, f, OP_if_);
    if sp.elem_bytes != 0 {
        let dbase = local32(g, f);
        lget(g, foc); i32Const(g, SEQ_FOC_DATA); op(g, OP_i32_add); lset(g, dbase);
        let addr = emitOffsetAddress(g, f, dbase, gs, sp.elem_bytes);
        let werr = writeElement(g, f, addr, 0, value, id);
        if werr != squid_direct_types::Error.none { return neverVal(), werr; }
    }
    lget(g, foc); lget(g, gs); i32Const(g, 1); op(g, OP_i32_add);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_FOC_GSTART);
    let ntotal = local32(g, f);
    lget(g, entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    i32Const(g, 1); op(g, OP_i32_add); lset(g, ntotal);
    lget(g, hdr); lget(g, ntotal); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_LEN);
    lget(g, entry); lget(g, ntotal); op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    br(g, f, OP_br, push_done);
    close(g, f);
    close(g, f);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_LEN); lset(g, total);
    lget(g, w(g, container, 0));
    lget(g, w(g, container, 1));
    lget(g, total);
    seqPushVal(g, value);
    callf(g, ins_fn);
    close(g, f);
    if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
    return container, squid_direct_types::Error.none;
}

fn emitSeqPushFrontVal(g: Generator&, f: Fn&, container: Val, value: Val, id: u32, selective: bool = false) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, container.ty, id);
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let sp, sperr = computeSeqPlan(g, f, elem_ty, id);
    if sperr != squid_direct_types::Error.none { return neverVal(), sperr; }
    let ins_fn, ierr = ensureSeqHdrInsert(g, sp);
    if ierr != squid_direct_types::Error.none { return neverVal(), ierr; }
    let noted = noteStoreToSlot(g, f, w(g, container, 0), value);
    if noted != squid_direct_types::Error.none { return neverVal(), noted; }
    let entry = ensureCheckedGrow(g, f, container);
    let hdr = local32(g, f);
    let foc = local32(g, f);
    let ge = local32(g, f);
    let fast_done = constLocal(g, f, 0);
    lget(g, entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base); lset(g, hdr);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FAST_PREPEND_EP);
    gget(g, g.s.seq_min_mutable_epoch); op(g, OP_i32_ge_u);
    let ep_ok = open(g, f, OP_if_);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FOCUS); ltee(g, foc);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_GEND); ltee(g, ge);
    i32Const(g, 0); op(g, OP_i32_gt_u);
    let do_fast = open(g, f, OP_if_);
    lget(g, ge); i32Const(g, 1); op(g, OP_i32_sub); lset(g, ge);
    if sp.elem_bytes != 0 {
        let dbase = local32(g, f);
        lget(g, foc); i32Const(g, SEQ_FOC_DATA); op(g, OP_i32_add); lset(g, dbase);
        let addr = emitOffsetAddress(g, f, dbase, ge, sp.elem_bytes);
        let werr = writeElement(g, f, addr, 0, value, id);
        if werr != squid_direct_types::Error.none { return neverVal(), werr; }
    }
    lget(g, foc); lget(g, ge); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_FOC_GEND);
    let ntotal = local32(g, f);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_LEN);
    i32Const(g, 1); op(g, OP_i32_add); lset(g, ntotal);
    lget(g, hdr); lget(g, ntotal); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_LEN);
    lget(g, entry); lget(g, ntotal); op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    i32Const(g, 1); lset(g, fast_done);
    close(g, f);
    close(g, f);
    lget(g, fast_done); op(g, OP_i32_eqz);
    let slow = open(g, f, OP_if_);
    lget(g, w(g, container, 0));
    lget(g, w(g, container, 1));
    i32Const(g, 0);
    seqPushVal(g, value);
    callf(g, ins_fn);
    close(g, f);
    if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
    return container, squid_direct_types::Error.none;
}

fn emitSeqInsertVal(g: Generator&, f: Fn&, container: Val, index: u32, value: Val, id: u32, selective: bool = false) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, container.ty, id);
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let sp, sperr = computeSeqPlan(g, f, elem_ty, id);
    if sperr != squid_direct_types::Error.none { return neverVal(), sperr; }
    let ins_fn, ierr = ensureSeqHdrInsert(g, sp);
    if ierr != squid_direct_types::Error.none { return neverVal(), ierr; }
    let noted = noteStoreToSlot(g, f, w(g, container, 0), value);
    if noted != squid_direct_types::Error.none { return neverVal(), noted; }
    lget(g, w(g, container, 0));
    lget(g, w(g, container, 1));
    lget(g, index);
    seqPushVal(g, value);
    callf(g, ins_fn);
    if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
    return container, squid_direct_types::Error.none;
}

fn emitSeqPopVal(g: Generator&, f: Fn&, container: Val, ty: Ty, id: u32, selective: bool = false) -> Val, Error {
    let len, lerr = lengthOf(g, f, container, id);
    if lerr != squid_direct_types::Error.none { return neverVal(), lerr; }
    lget(g, len); op(g, OP_i32_eqz); trap(g, f);
    let last = local32(g, f);
    lget(g, len); i32Const(g, 1); op(g, OP_i32_sub); lset(g, last);
    return emitSeqRemoveVal(g, f, container, last, ty, id, selective);
}

fn emitSeqPopFrontVal(g: Generator&, f: Fn&, container: Val, ty: Ty, id: u32, selective: bool = false) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, container.ty, id);
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let sp, sperr = computeSeqPlan(g, f, elem_ty, id);
    if sperr != squid_direct_types::Error.none { return neverVal(), sperr; }
    let rem_fn, rerr = ensureSeqHdrRemove(g, sp);
    if rerr != squid_direct_types::Error.none { return neverVal(), rerr; }
    let out, oerr = fresh(g, f, ty, id);
    if oerr != squid_direct_types::Error.none { return out, oerr; }
    let entry = ensureCheckedGrow(g, f, container);
    let hdr = local32(g, f);
    let foc = local32(g, f);
    let ge = local32(g, f);
    let fast_done = constLocal(g, f, 0);
    lget(g, entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base); lset(g, hdr);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FAST_PREPEND_EP);
    gget(g, g.s.seq_min_mutable_epoch); op(g, OP_i32_ge_u);
    let ep_ok = open(g, f, OP_if_);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FOCUS); ltee(g, foc);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_FOC_GEND); ltee(g, ge);
    i32Const(g, sp.leaf_cap); op(g, OP_i32_lt_u);
    let do_fast = open(g, f, OP_if_);
    if sp.elem_bytes != 0 {
        let dbase = local32(g, f);
        lget(g, foc); i32Const(g, SEQ_FOC_DATA); op(g, OP_i32_add); lset(g, dbase);
        let addr = emitOffsetAddress(g, f, dbase, ge, sp.elem_bytes);
        let loaded, lerr = loadElement(g, f, addr, 0, ty, id);
        if lerr != squid_direct_types::Error.none { return neverVal(), lerr; }
        let _ = copy(g, f, loaded, out, id);
    }
    lget(g, foc); lget(g, ge); i32Const(g, 1); op(g, OP_i32_add);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_FOC_GEND);
    let ntotal = local32(g, f);
    lget(g, hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_LEN);
    i32Const(g, 1); op(g, OP_i32_sub); lset(g, ntotal);
    lget(g, hdr); lget(g, ntotal); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_LEN);
    lget(g, entry); lget(g, ntotal); op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
    i32Const(g, 1); lset(g, fast_done);
    close(g, f);
    close(g, f);
    lget(g, fast_done); op(g, OP_i32_eqz);
    let slow = open(g, f, OP_if_);
    lget(g, w(g, container, 0));
    lget(g, w(g, container, 1));
    i32Const(g, 0);
    callf(g, rem_fn);
    let val, perr = pop(g, f, ty, id);
    if perr != squid_direct_types::Error.none { return val, perr; }
    let _ = copy(g, f, val, out, id);
    close(g, f);
    if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
    return out, squid_direct_types::Error.none;
}

fn emitSeqRemoveVal(g: Generator&, f: Fn&, container: Val, index: u32, ty: Ty, id: u32, selective: bool = false) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, container.ty, id);
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let sp, sperr = computeSeqPlan(g, f, elem_ty, id);
    if sperr != squid_direct_types::Error.none { return neverVal(), sperr; }
    let rem_fn, rerr = ensureSeqHdrRemove(g, sp);
    if rerr != squid_direct_types::Error.none { return neverVal(), rerr; }
    lget(g, w(g, container, 0));
    lget(g, w(g, container, 1));
    lget(g, index);
    callf(g, rem_fn);
    let val, perr = pop(g, f, ty, id);
    if perr != squid_direct_types::Error.none { return val, perr; }
    if selective { invalidateCheckedOwner(g, f, container); } else { invalidateCheckedContainers(f); }
    return val, squid_direct_types::Error.none;
}

// O(1) persistent copy (48 bytes, zero focus flush!)
fn emitSeqCopyVal(g: Generator&, f: Fn&, container: Val, ty: Ty, id: u32) -> Val, Error {
    let clone_fn, cerr = ensureSeqHdrCloneShared(g);
    if cerr != squid_direct_types::Error.none { return neverVal(), cerr; }
    noteAllocation(f);
    lget(g, w(g, container, 0));
    lget(g, w(g, container, 1));
    i32Const(g, 0);
    callf(g, clone_fn);
    let handle, perr = pop(g, f, ty, id);
    if perr != squid_direct_types::Error.none { return handle, perr; }
    recordMutable(g, f, handle);
    return handle, squid_direct_types::Error.none;
}

// O(1) persistent reverse (48 bytes, zero focus flush, flips root_rev ^= 1!)
fn emitSeqReverseVal(g: Generator&, f: Fn&, container: Val, ty: Ty, id: u32) -> Val, Error {
    let clone_fn, cerr = ensureSeqHdrCloneShared(g);
    if cerr != squid_direct_types::Error.none { return neverVal(), cerr; }
    noteAllocation(f);
    lget(g, w(g, container, 0));
    lget(g, w(g, container, 1));
    i32Const(g, 1);
    callf(g, clone_fn);
    let handle, perr = pop(g, f, ty, id);
    if perr != squid_direct_types::Error.none { return handle, perr; }
    recordMutable(g, f, handle);
    return handle, squid_direct_types::Error.none;
}

// O(log_16 m) split (O(1) on LEAF_SPAN / LEAF_REPEAT / LEAF_RAMP!) -> (~[T], ~[T])
fn emitSeqSplitVal(g: Generator&, f: Fn&, container: Val, index: u32, ty: Ty, id: u32) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, container.ty, id);
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let sp, sperr = computeSeqPlan(g, f, elem_ty, id);
    if sperr != squid_direct_types::Error.none { return neverVal(), sperr; }
    let ep_fn, eperr = ensureSeqNextEpoch(g);
    if eperr != squid_direct_types::Error.none { return neverVal(), eperr; }
    let norm_fn, nerr = ensureSeqNormalizedRoot(g, sp);
    if nerr != squid_direct_types::Error.none { return neverVal(), nerr; }
    let split_fn, serr = ensureSeqTreeSplit(g, sp);
    if serr != squid_direct_types::Error.none { return neverVal(), serr; }
    let open_fn, oerr = ensureSeqHdrOpen(g);
    if oerr != squid_direct_types::Error.none { return neverVal(), oerr; }
    noteAllocation(f);
    let rt = g.runtime_();
    let src_hdr = local32(g, f);
    let total = local32(g, f);
    let ep = local32(g, f);
    let root = local32(g, f);
    let l_edge = local32(g, f);
    let r_edge = local32(g, f);
    let l_len = local32(g, f);
    let r_len = local32(g, f);
    lget(g, w(g, container, 0)); lget(g, w(g, container, 1)); callf(g, rt.check);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base); lset(g, src_hdr);
    lget(g, src_hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_LEN); lset(g, total);
    lget(g, index); lget(g, total); op(g, OP_i32_gt_u); trap(g, f);
    // Mark source shared (unlogged)
    lget(g, src_hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_EPOCH);
    lget(g, src_hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_APPEND_EP);
    lget(g, src_hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_PREPEND_EP);
    callf(g, ep_fn); lset(g, ep);
    lget(g, src_hdr); lget(g, ep); callf(g, norm_fn); lset(g, root);
    lget(g, root); lget(g, index); lget(g, ep); callf(g, split_fn);
    lset(g, r_edge); lset(g, l_edge);
    lget(g, index); lset(g, l_len);
    lget(g, total); lget(g, index); op(g, OP_i32_sub); lset(g, r_len);
    let seq_ty = g.types.words[g.types.node(ty).a];
    lget(g, l_edge); lget(g, l_len); i32Const(g, 0); callf(g, ep_fn); callf(g, open_fn);
    let left_val, lv_err = pop(g, f, seq_ty, id);
    if lv_err != squid_direct_types::Error.none { return neverVal(), lv_err; }
    lget(g, r_edge); lget(g, r_len); i32Const(g, 0); callf(g, ep_fn); callf(g, open_fn);
    let right_val, rv_err = pop(g, f, seq_ty, id);
    if rv_err != squid_direct_types::Error.none { return neverVal(), rv_err; }
    let s .= g.s;
    let start = s.words.len as u32;
    s.words.push(w(g, left_val, 0));
    s.words.push(w(g, left_val, 1));
    s.words.push(w(g, right_val, 0));
    s.words.push(w(g, right_val, 1));
    return Val { ty, start, 4 }, squid_direct_types::Error.none;
}

// O(log_16 m) non-destructive persistent concat!
fn emitSeqConcatVal(g: Generator&, f: Fn&, left: Val, right: Val, ty: Ty, id: u32) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, ty, id);
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let sp, sperr = computeSeqPlan(g, f, elem_ty, id);
    if sperr != squid_direct_types::Error.none { return neverVal(), sperr; }
    let ep_fn, eperr = ensureSeqNextEpoch(g);
    if eperr != squid_direct_types::Error.none { return neverVal(), eperr; }
    let norm_fn, nerr = ensureSeqNormalizedRoot(g, sp);
    if nerr != squid_direct_types::Error.none { return neverVal(), nerr; }
    let concat_fn, cerr = ensureSeqTreeConcat(g, sp);
    if cerr != squid_direct_types::Error.none { return neverVal(), cerr; }
    let open_fn, oerr = ensureSeqHdrOpen(g);
    if oerr != squid_direct_types::Error.none { return neverVal(), oerr; }
    noteAllocation(f);
    let rt = g.runtime_();
    let ha = local32(g, f); let hb = local32(g, f);
    let la = local32(g, f); let lb = local32(g, f);
    let tot = local32(g, f);
    let ep = local32(g, f);
    let ra = local32(g, f); let rb = local32(g, f);
    let merged = local32(g, f);
    lget(g, w(g, left, 0)); lget(g, w(g, left, 1)); callf(g, rt.check);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base); lset(g, ha);
    lget(g, w(g, right, 0)); lget(g, w(g, right, 1)); callf(g, rt.check);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base); lset(g, hb);
    lget(g, ha); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_LEN); lset(g, la);
    lget(g, hb); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_LEN); lset(g, lb);
    lget(g, la); lget(g, lb); op(g, OP_i32_add); ltee(g, tot);
    lget(g, la); op(g, OP_i32_lt_u); trap(g, f);
    lget(g, ha); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_EPOCH);
    lget(g, ha); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_APPEND_EP);
    lget(g, ha); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_PREPEND_EP);
    lget(g, hb); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_EPOCH);
    lget(g, hb); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_APPEND_EP);
    lget(g, hb); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_PREPEND_EP);
    callf(g, ep_fn); lset(g, ep);
    lget(g, ha); lget(g, ep); callf(g, norm_fn); lset(g, ra);
    lget(g, hb); lget(g, ep); callf(g, norm_fn); lset(g, rb);
    lget(g, ra); lget(g, rb); lget(g, ep); callf(g, concat_fn); lset(g, merged);
    lget(g, merged); lget(g, tot); i32Const(g, 0); callf(g, ep_fn); callf(g, open_fn);
    let handle, perr = pop(g, f, ty, id);
    if perr != squid_direct_types::Error.none { return handle, perr; }
    recordMutable(g, f, handle);
    return handle, squid_direct_types::Error.none;
}

// O(log_16 m) non-destructive persistent slice (O(1) on SPAN / REPEAT / RAMP!)
fn emitSeqSliceVal(g: Generator&, f: Fn&, container: Val, start_idx: u32, end_idx: u32, ty: Ty, id: u32) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, ty, id);
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let sp, sperr = computeSeqPlan(g, f, elem_ty, id);
    if sperr != squid_direct_types::Error.none { return neverVal(), sperr; }
    let ep_fn, eperr = ensureSeqNextEpoch(g);
    if eperr != squid_direct_types::Error.none { return neverVal(), eperr; }
    let norm_fn, nerr = ensureSeqNormalizedRoot(g, sp);
    if nerr != squid_direct_types::Error.none { return neverVal(), nerr; }
    let split_fn, serr = ensureSeqTreeSplit(g, sp);
    if serr != squid_direct_types::Error.none { return neverVal(), serr; }
    let open_fn, oerr = ensureSeqHdrOpen(g);
    if oerr != squid_direct_types::Error.none { return neverVal(), oerr; }
    noteAllocation(f);
    let rt = g.runtime_();
    let src_hdr = local32(g, f);
    let total = local32(g, f);
    let ep = local32(g, f);
    let root = local32(g, f);
    let right = local32(g, f);
    let mid = local32(g, f);
    let slen = local32(g, f);
    lget(g, w(g, container, 0)); lget(g, w(g, container, 1)); callf(g, rt.check);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base); lset(g, src_hdr);
    lget(g, src_hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_LEN); lset(g, total);
    lget(g, start_idx); lget(g, end_idx); op(g, OP_i32_gt_u);
    lget(g, end_idx); lget(g, total); op(g, OP_i32_gt_u);
    op(g, OP_i32_or);
    trap(g, f);
    lget(g, end_idx); lget(g, start_idx); op(g, OP_i32_sub); lset(g, slen);
    lget(g, src_hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_EPOCH);
    lget(g, src_hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_APPEND_EP);
    lget(g, src_hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_PREPEND_EP);
    callf(g, ep_fn); lset(g, ep);
    lget(g, src_hdr); lget(g, ep); callf(g, norm_fn); lset(g, root);
    lget(g, root); lget(g, start_idx); lget(g, ep); callf(g, split_fn);
    lset(g, right); op(g, OP_drop);
    lget(g, right); lget(g, slen); lget(g, ep); callf(g, split_fn);
    op(g, OP_drop); lset(g, mid);
    lget(g, mid); lget(g, slen); i32Const(g, 0); callf(g, ep_fn); callf(g, open_fn);
    let handle, perr = pop(g, f, ty, id);
    if perr != squid_direct_types::Error.none { return handle, perr; }
    recordMutable(g, f, handle);
    return handle, squid_direct_types::Error.none;
}

// O(1) generative repeat: 16 + elem_bytes for ANY count!
fn emitSeqRepeatVal(g: Generator&, f: Fn&, count: u32, val: Val, ty: Ty, id: u32) -> Val, Error {
    let elem_ty, eerr = elementOf(g, f, ty, id);
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let sp, sperr = computeSeqPlan(g, f, elem_ty, id);
    if sperr != squid_direct_types::Error.none { return neverVal(), sperr; }
    let ep_fn, eperr = ensureSeqNextEpoch(g);
    if eperr != squid_direct_types::Error.none { return neverVal(), eperr; }
    let open_fn, oerr = ensureSeqHdrOpen(g);
    if oerr != squid_direct_types::Error.none { return neverVal(), oerr; }
    noteAllocation(f);
    let leaf = local32(g, f);
    i32Const(g, 0); lset(g, leaf);
    lget(g, count);
    let nz = open(g, f, OP_if_);
    let rbytes = align16(16 + sp.elem_bytes);
    i32Const(g, rbytes); callf(g, g.s.seq_alloc_fn); lset(g, leaf);
    lget(g, leaf); i32Const(g, SEQ_KIND_REPEAT); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_META);
    lget(g, leaf); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_EPOCH);
    lget(g, leaf); lget(g, count); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
    if sp.elem_bytes != 0 {
        let werr = writeElement(g, f, leaf, SEQ_LEAF_DATA, val, id);
        if werr != squid_direct_types::Error.none { return neverVal(), werr; }
    }
    close(g, f);
    lget(g, leaf); lget(g, count); i32Const(g, 0); callf(g, ep_fn); callf(g, open_fn);
    let handle, perr = pop(g, f, ty, id);
    if perr != squid_direct_types::Error.none { return handle, perr; }
    recordMutable(g, f, handle);
    let noted = noteStoreToSlot(g, f, w(g, handle, 0), val);
    if noted != squid_direct_types::Error.none { return neverVal(), noted; }
    return handle, squid_direct_types::Error.none;
}

// O(1) generative ramp: 32 bytes for 1,000,000 U32s!
fn emitSeqRampVal(g: Generator&, f: Fn&, start_v: u32, step_v: u32, count: u32, ty: Ty, id: u32) -> Val, Error {
    let ep_fn, eperr = ensureSeqNextEpoch(g);
    if eperr != squid_direct_types::Error.none { return neverVal(), eperr; }
    let open_fn, oerr = ensureSeqHdrOpen(g);
    if oerr != squid_direct_types::Error.none { return neverVal(), oerr; }
    noteAllocation(f);
    let leaf = local32(g, f);
    i32Const(g, 0); lset(g, leaf);
    lget(g, count);
    let nz = open(g, f, OP_if_);
    i32Const(g, SEQ_RAMP_BYTES); callf(g, g.s.seq_alloc_fn); lset(g, leaf);
    lget(g, leaf); i32Const(g, SEQ_KIND_RAMP); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_META);
    lget(g, leaf); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_EPOCH);
    lget(g, leaf); lget(g, count); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
    lget(g, leaf); lget(g, start_v); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_RAMP_START);
    lget(g, leaf); lget(g, step_v); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_RAMP_STEP);
    close(g, f);
    lget(g, leaf); lget(g, count); i32Const(g, 0); callf(g, ep_fn); callf(g, open_fn);
    let handle, perr = pop(g, f, ty, id);
    if perr != squid_direct_types::Error.none { return handle, perr; }
    recordMutable(g, f, handle);
    return handle, squid_direct_types::Error.none;
}

// O(1) zero-copy span wrapping an immutable frozen `*#[T]` backing array!
fn emitSeqFromFrozenVal(g: Generator&, f: Fn&, arr: Val, ty: Ty, id: u32) -> Val, Error {
    let ep_fn, eperr = ensureSeqNextEpoch(g);
    if eperr != squid_direct_types::Error.none { return neverVal(), eperr; }
    let open_fn, oerr = ensureSeqHdrOpen(g);
    if oerr != squid_direct_types::Error.none { return neverVal(), oerr; }
    noteAllocation(f);
    let base, len = ensureCheckedArray(g, f, arr);
    let leaf = local32(g, f);
    i32Const(g, 0); lset(g, leaf);
    lget(g, len);
    let nz = open(g, f, OP_if_);
    i32Const(g, SEQ_SPAN_BYTES); callf(g, g.s.seq_alloc_fn); lset(g, leaf);
    lget(g, leaf); i32Const(g, SEQ_KIND_SPAN); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_META);
    lget(g, leaf); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_EPOCH);
    lget(g, leaf); lget(g, len); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
    lget(g, leaf); lget(g, base); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_SPAN_PTR);
    lget(g, leaf); lget(g, w(g, arr, 0)); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_SPAN_SLOT);
    lget(g, leaf); lget(g, w(g, arr, 1)); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_SPAN_GEN);
    close(g, f);
    lget(g, leaf); lget(g, len); i32Const(g, 0); callf(g, ep_fn); callf(g, open_fn);
    let handle, perr = pop(g, f, ty, id);
    if perr != squid_direct_types::Error.none { return handle, perr; }
    recordMutable(g, f, handle);
    let noted = noteStoreToSlot(g, f, w(g, handle, 0), arr);
    if noted != squid_direct_types::Error.none { return neverVal(), noted; }
    return handle, squid_direct_types::Error.none;
}

// Handles `extend` whenever `dst` OR `src` is `Tag.seq`.
fn emitSeqExtend(g: Generator&, f: Fn&, dst: Val, src: Val, src_core_ty: TId, id: u32, selective: bool = false) -> Val, Error {
    let dst_is_seq = tagOf(g, dst.ty) == squid_direct_types::Tag.seq;
    let src_is_seq = tagOf(g, src.ty) == squid_direct_types::Tag.seq;
    let elem_ty, eerr = elementOf(g, f, dst.ty, id);
    if eerr != squid_direct_types::Error.none { return neverVal(), eerr; }
    let holds = holdsContainer(g, elem_ty, 0);

    // Fast O(log_16 m) in-place tree concat when BOTH dst and src are `~[T]` and !holds!
    if dst_is_seq && src_is_seq && !holds {
        let sp, sperr = computeSeqPlan(g, f, elem_ty, id);
        if sperr != squid_direct_types::Error.none { return neverVal(), sperr; }
        let wr_fn, werr = ensureSeqWritable(g);
        if werr != squid_direct_types::Error.none { return neverVal(), werr; }
        let norm_fn, nerr = ensureSeqNormalizedRoot(g, sp);
        if nerr != squid_direct_types::Error.none { return neverVal(), nerr; }
        let concat_fn, cerr = ensureSeqTreeConcat(g, sp);
        if cerr != squid_direct_types::Error.none { return neverVal(), cerr; }
        let rt = g.runtime_();
        let entry = local32(g, f);
        let dhdr = local32(g, f);
        let epoch = local32(g, f);
        let shdr = local32(g, f);
        let dlen = local32(g, f);
        let slen = local32(g, f);
        let nlen = local32(g, f);
        let droot = local32(g, f);
        let sroot = local32(g, f);
        lget(g, w(g, dst, 0)); lget(g, w(g, dst, 1)); callf(g, wr_fn);
        lset(g, epoch); lset(g, dhdr); lset(g, entry);
        lget(g, w(g, src, 0)); lget(g, w(g, src, 1)); callf(g, rt.check);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base); lset(g, shdr);
        lget(g, shdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_LEN); ltee(g, slen);
        let nz = open(g, f, OP_if_);
        lget(g, dhdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_LEN); lset(g, dlen);
        lget(g, dlen); lget(g, slen); op(g, OP_i32_add); ltee(g, nlen);
        lget(g, dlen); op(g, OP_i32_lt_u); trap(g, f);
        lget(g, shdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_EPOCH);
        lget(g, shdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_APPEND_EP);
        lget(g, shdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_PREPEND_EP);
        lget(g, dhdr); lget(g, epoch); callf(g, norm_fn); lset(g, droot);
        lget(g, shdr); lget(g, epoch); callf(g, norm_fn); lset(g, sroot);
        lget(g, dhdr); lget(g, droot); lget(g, sroot); lget(g, epoch); callf(g, concat_fn);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_ROOT);
        lget(g, dhdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_REV);
        lget(g, dhdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FOCUS);
        lget(g, dhdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FSTART);
        lget(g, dhdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FOLDLEN);
        lget(g, dhdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_APPEND_EP);
        lget(g, dhdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_FAST_PREPEND_EP);
        lget(g, dhdr); lget(g, nlen); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_LEN);
        lget(g, entry); lget(g, nlen); op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_length);
        close(g, f);
        if selective { invalidateCheckedOwner(g, f, dst); } else { invalidateCheckedContainers(f); }
        return dst, squid_direct_types::Error.none;
    }

    // General loop: src is packed (use packed cursors) or array/view/seq -> push into dst!
    let src_len, slerr = lengthOf(g, f, src, id);
    if slerr != squid_direct_types::Error.none { return neverVal(), slerr; }
    // Pre-reserve if dst is array or packed
    if !dst_is_seq && tagOf(g, dst.ty) == squid_direct_types::Tag.array {
        let step, sterr = stride(g, f, elem_ty, id);
        if sterr != squid_direct_types::Error.none { return neverVal(), sterr; }
        let dlen, dlerr = lengthOf(g, f, dst, id);
        if dlerr != squid_direct_types::Error.none { return neverVal(), dlerr; }
        let need = local32(g, f);
        lget(g, dlen); lget(g, src_len); op(g, OP_i32_add); ltee(g, need);
        lget(g, dlen); op(g, OP_i32_lt_u); trap(g, f);
        lget(g, w(g, dst, 0)); lget(g, w(g, dst, 1)); lget(g, need); i32Const(g, step);
        callf(g, g.runtime_().reserve);
        invalidateCheckedOwner(g, f, dst);
    } else if tagOf(g, dst.ty) == squid_direct_types::Tag.packed {
        let _, rerr = emitPackedReserve(g, f, dst, src_len, id, selective);
        if rerr != squid_direct_types::Error.none { return neverVal(), rerr; }
    }

    if tagOf(g, src.ty) == squid_direct_types::Tag.packed {
        let plan, perr = computePackedPlan(g, f, elem_ty, id);
        if perr != squid_direct_types::Error.none { return neverVal(), perr; }
        if plan.mode == PACKED_FLAT {
            let step, sterr = stride(g, f, elem_ty, id);
            if sterr != squid_direct_types::Error.none { return neverVal(), sterr; }
            let src_base, _ = ensureCheckedArray(g, f, src);
            let idx = constLocal(g, f, 0);
            let exit = open(g, f, OP_block); let top = open(g, f, OP_loop);
            lget(g, idx); lget(g, src_len); op(g, OP_i32_ge_u); br(g, f, OP_br_if, exit);
            let saddr = emitOffsetAddress(g, f, src_base, idx, step);
            var elem_val, lerr = loadElement(g, f, saddr, 0, elem_ty, id);
            if lerr != squid_direct_types::Error.none { return neverVal(), lerr; }
            if holds {
                let cp, cerr = deepCopyValue(g, f, elem_val, elem_ty, id, 0);
                if cerr != squid_direct_types::Error.none { return neverVal(), cerr; }
                elem_val = cp;
            }
            let _, perr2 = emitStoragePushVal(g, f, dst, elem_val, id, selective);
            if perr2 != squid_direct_types::Error.none { return neverVal(), perr2; }
            lget(g, idx); i32Const(g, 1); op(g, OP_i32_add); lset(g, idx);
            br(g, f, OP_br, top);
            close(g, f); close(g, f);
            return dst, squid_direct_types::Error.none;
        }
        // Multi-stream packed src -> decode step into dst
        let sbase, _ = ensureCheckedArray(g, f, src);
        var cur_ptrs: u32[16] = [0; 16];
        var tags_base: u32 = 0;
        if plan.mode == PACKED_SPLIT_SUM {
            tags_base = emitLoadPackedSubBase(g, f, plan, sbase, 0);
            for st in 1..plan.stream_count { cur_ptrs[st] = emitLoadPackedSubBase(g, f, plan, sbase, st); }
        } else {
            for st in 0..plan.stream_count { cur_ptrs[st] = emitLoadPackedSubBase(g, f, plan, sbase, st); }
        }
        let idx = constLocal(g, f, 0);
        let exit = open(g, f, OP_block); let top = open(g, f, OP_loop);
        lget(g, idx); lget(g, src_len); op(g, OP_i32_ge_u); br(g, f, OP_br_if, exit);
        var elem_val, derr = emitPackedDecodeStep(g, f, plan, cur_ptrs[..], tags_base, idx, id);
        if derr != squid_direct_types::Error.none { return neverVal(), derr; }
        if holds {
            let cp, cerr = deepCopyValue(g, f, elem_val, elem_ty, id, 0);
            if cerr != squid_direct_types::Error.none { return neverVal(), cerr; }
            elem_val = cp;
        }
        let _, perr2 = emitStoragePushVal(g, f, dst, elem_val, id, selective);
        if perr2 != squid_direct_types::Error.none { return neverVal(), perr2; }
        lget(g, idx); i32Const(g, 1); op(g, OP_i32_add); lset(g, idx);
        br(g, f, OP_br, top);
        close(g, f); close(g, f);
        return dst, squid_direct_types::Error.none;
    }

    // src is array / view / seq -> push each element into dst
    let idx = constLocal(g, f, 0);
    let exit = open(g, f, OP_block); let top = open(g, f, OP_loop);
    lget(g, idx); lget(g, src_len); op(g, OP_i32_ge_u); br(g, f, OP_br_if, exit);
    var elem_val, rerr = readElement(g, f, src, idx, id, src_core_ty, false);
    if rerr != squid_direct_types::Error.none { return neverVal(), rerr; }
    if holds {
        let cp, cerr = deepCopyValue(g, f, elem_val, elem_ty, id, 0);
        if cerr != squid_direct_types::Error.none { return neverVal(), cerr; }
        elem_val = cp;
    }
    let _, perr2 = emitStoragePushVal(g, f, dst, elem_val, id, selective);
    if perr2 != squid_direct_types::Error.none { return neverVal(), perr2; }
    lget(g, idx); i32Const(g, 1); op(g, OP_i32_add); lset(g, idx);
    br(g, f, OP_br, top);
    close(g, f); close(g, f);
    if selective && !dst_is_seq && tagOf(g, dst.ty) == squid_direct_types::Tag.array {
        invalidateCheckedOwner(g, f, dst);
    } else {
        invalidateCheckedContainers(f);
    }
    return dst, squid_direct_types::Error.none;
}

// ---- Module `const ~[T]` persistence (allocates into rt.alloc_persistent + rt.open_persistent) ----

fn emitSeqPersist(g: Generator&, f: Fn&, src_slot: u32, src_gen: u32, ty: Ty, id: u32, depth: i64) -> u32, u32, Error {
    let elem_ty, eerr = elementOf(g, f, ty, id);
    if eerr != squid_direct_types::Error.none { return 0, 0, eerr; }
    let sp, sperr = computeSeqPlan(g, f, elem_ty, id);
    if sperr != squid_direct_types::Error.none { return 0, 0, sperr; }
    let get_fn, gerr = ensureSeqHdrGet(g, sp);
    if gerr != squid_direct_types::Error.none { return 0, 0, gerr; }
    let rt = g.runtime_();
    let src_hdr = local32(g, f);
    let len = local32(g, f);
    let p_hdr = local32(g, f);
    let p_slot = local32(g, f);
    let p_gen = local32(g, f);
    let p_leaf = local32(g, f);
    lget(g, src_slot); lget(g, src_gen); callf(g, rt.check);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, squid_direct_runtime::entry_base); lset(g, src_hdr);
    lget(g, src_hdr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_LEN); lset(g, len);
    // Materialize a clean persistent LEAF_SPAN backed by persistent flat array of elements!
    // (100% persistent, zero slab pointers, O(1) slice/reverse/index, supports nested elem persistence!)
    i32Const(g, SEQ_HDR_BYTES); callf(g, rt.alloc_persistent); ltee(g, p_hdr);
    i32Const(g, 0); i32Const(g, SEQ_HDR_BYTES); memoryFillOp(g);
    i32Const(g, 0); lset(g, p_leaf);
    lget(g, len);
    let nz = open(g, f, OP_if_);
    let elem_step, sterr = stride(g, f, elem_ty, id);
    if sterr != squid_direct_types::Error.none { return 0, 0, sterr; }
    let dbytes = emitScaledBytes(g, f, len, elem_step);
    let p_data = local32(g, f);
    lget(g, dbytes); callf(g, rt.alloc_persistent); lset(g, p_data);
    let idx = constLocal(g, f, 0);
    let exit = open(g, f, OP_block); let top = open(g, f, OP_loop);
    lget(g, idx); lget(g, len); op(g, OP_i32_ge_u); br(g, f, OP_br_if, exit);
    lget(g, src_hdr); lget(g, idx); callf(g, get_fn);
    let ev, perr = pop(g, f, elem_ty, id);
    if perr != squid_direct_types::Error.none { return 0, 0, perr; }
    let dst_addr = emitOffsetAddress(g, f, p_data, idx, elem_step);
    let werr = writeElement(g, f, dst_addr, 0, ev, id);
    if werr != squid_direct_types::Error.none { return 0, 0, werr; }
    let elem_holds, eherr = g.contentsHoldMemory(elem_ty);
    if eherr != squid_direct_types::Error.none { return 0, 0, eherr; }
    if elem_holds {
        let pf_err = persistFlatAt(g, f, dst_addr, 0, elem_ty, id, depth + 1);
        if pf_err != squid_direct_types::Error.none { return 0, 0, pf_err; }
    }
    lget(g, idx); i32Const(g, 1); op(g, OP_i32_add); lset(g, idx);
    br(g, f, OP_br, top);
    close(g, f); close(g, f);
    i32Const(g, SEQ_SPAN_BYTES); callf(g, rt.alloc_persistent); lset(g, p_leaf);
    lget(g, p_leaf); i32Const(g, SEQ_KIND_SPAN | (1 << 24)); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_META);
    lget(g, p_leaf); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_EPOCH);
    lget(g, p_leaf); lget(g, len); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_LEAF_LEN);
    lget(g, p_leaf); lget(g, p_data); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_SPAN_PTR);
    lget(g, p_leaf); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_SPAN_SLOT);
    lget(g, p_leaf); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_SPAN_GEN);
    close(g, f);
    lget(g, p_hdr); lget(g, p_leaf); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_ROOT);
    lget(g, p_hdr); lget(g, len); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_LEN);
    lget(g, p_hdr); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, SEQ_HDR_EPOCH);
    // Open persistent owner with static_pool_flag | live_flag
    lget(g, p_hdr); lget(g, len); i32Const(g, SEQ_HDR_BYTES | squid_direct_runtime::static_pool_flag);
    callf(g, rt.open_persistent);
    lset(g, p_gen); lset(g, p_slot);
    // Mark static_pool_flag explicitly on the opened entry
    let p_entry = local32(g, f);
    lget(g, p_slot); lget(g, p_gen); callf(g, rt.check); ltee(g, p_entry);
    i32Const(g, SEQ_HDR_BYTES | squid_direct_runtime::static_pool_flag | squid_direct_runtime::live_flag);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, squid_direct_runtime::entry_capacity);
    return p_slot, p_gen, squid_direct_types::Error.none;
}

// ---- Fast 2-Level Leaf-Streaming `for x in seq:` emitter (Flat / Span / Repeat / Ramp / SoA / Fused Split-Sum!) ----
// Outer loop steps across leaves (via height-1 sibling cache or traversal stack);
// inner loop streams elements within a leaf with ZERO next_leaf_fn calls, ZERO leaf_kind branches on canonical leaves,
// and constant-stride pointer loops that match `#[T]` / `%[T]` and auto-vectorize under `wtime-aot`.

recursive fn emitSeqLoopBodyTail(
    g: Generator&,
    f: Fn&,
    id: u32,
    info: squid_check_core::LoopInfo,
    iteration: Vals,
    outgoing: Vals,
    slots: Words,
    exit: u32,
    elem_top: u32,
    release: bool,
    release_owner: u32,
    release_stack: u32,
    saved_escape: u32,
    unchanged: u32,
    guards: Words,
    pushed_soa_frame: bool,
    pushed_split_frame: bool,
) -> Error {
    let m .= g.units[f.unit - 1];
    let carries = m.loopCarries(id);
    let rt = g.runtime_();
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
        top: elem_top,
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
            gget(g, rt.escape_min_slot);
            lset(g, iter_esc);
            if f.allocations != allocations && f.memory_stores == stores {
                releaseIteration(g, f, label, iter_esc);
            }
            emitMergeEscapeMin(g, f, iter_esc, label.saved_esc);
        }
        br(g, f, OP_br, elem_top);
    }
    f.loop_depth -= 1;
    s_lbl.labels.resize(labels_mark);
    return squid_direct_types::Error.none;
}

recursive fn emitSeqLoopCore(
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
    let sp, sperr = computeSeqPlan(g, f, elem_ty, id);
    if sperr != squid_direct_types::Error.none { return sperr; }
    let ep_fn, eperr = ensureSeqNextEpoch(g);
    if eperr != squid_direct_types::Error.none { return eperr; }
    let flush_fn, flerr = ensureSeqFlushFocus(g, sp);
    if flerr != squid_direct_types::Error.none { return flerr; }
    let norm_fn, nerr = ensureSeqNormalizedRoot(g, sp);
    if nerr != squid_direct_types::Error.none { return nerr; }
    let next_leaf_fn, nlerr = ensureSeqIterNextLeaf(g);
    if nlerr != squid_direct_types::Error.none { return nlerr; }
    let leaf_get_fn, lgerr = ensureSeqLeafGet(g, sp);
    if lgerr != squid_direct_types::Error.none { return lgerr; }

    // Detect touched-column SoA / fused split-sum opportunities (reusing packed analyzers!).
    var soa_virtual = false;
    var soa_destruct = false;
    var soa_used_fields: u32 = 0;
    var soa_bind_id: u32 = 0;
    var soa_field_pats: u32[16] = [0; 16];
    var split_fused = false;
    var split_bind_id: u32 = 0;
    var split_needed_mask: u64 = 0;

    if sp.leaf_kind == SEQ_KIND_PACKED_SOA && info.pattern != 0 {
        let pnode = m.pattern(info.pattern);
        if pnode.tag == squid_check_core::PatternTag.bind && sp.packed.soa_is_record && soa_loop_depth < 8 {
            var budget: i64 = 1024;
            var uf: u32 = 0;
            if analyzeSoaBodyUses(g, m, info.body, pnode.a, sp.packed, uf, budget) {
                soa_virtual = true;
                soa_bind_id = pnode.a;
                soa_used_fields = uf;
            }
        } else if matchSoaDestructurePattern(g, m, info.pattern, sp.packed, soa_field_pats, soa_used_fields) {
            soa_destruct = true;
        }
    } else if sp.leaf_kind == SEQ_KIND_PACKED_SUM && info.pattern != 0 && m.pattern(info.pattern).tag == squid_check_core::PatternTag.bind && split_sum_depth < 4 && sp.packed.variant_count <= 64 {
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
                }
            }
        }
    }
    var unrev_sum_fn: u32 = 0;
    if sp.leaf_kind == SEQ_KIND_PACKED_SUM {
        let uf, uferr = ensureSeqLeafUnrevSum(g, sp);
        if uferr != squid_direct_types::Error.none { return uferr; }
        unrev_sum_fn = uf;
    }

    // Per-iteration scratch release eligibility + compact no-alloc specialization check
    var release = true;
    var boxed_carries = false;
    var guards = Words { 0, 0 };
    var body_no_alloc = false;
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
        var no_alloc_budget: i64 = 512;
        if bodyNoAlloc(g, f, m, info.body, no_alloc_budget) {
            body_no_alloc = true;
            release = false;
        }
        guards = Words { g.s.words.len as u32, (s_state.scratch.len - scratch_mark) as u32 };
        for at in scratch_mark..s_state.scratch.len { let sl = s_state.scratch[at]; g.s.words.push(sl); }
        s_state.scratch.resize(scratch_mark);
    }
    var spec_budget: i64 = 96;
    let can_spec = !release && body_no_alloc && bodyNoAlloc(g, f, m, info.body, spec_budget);

    // Initialize 64-byte traversal stack & normalized root ONCE before outer leaf loop!
    // If hdr.focus != 0 and hdr is exclusively mutable in the current epoch, flush once in place
    // so repeated outer scan passes (e.g. `for _ in 0..80:`) never re-normalize!
    let rt = g.runtime_();
    let hdr_base, _ = ensureCheckedArray(g, f, source);
    let norm_root = local32(g, f);
    lget(g, hdr_base); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_FOCUS);
    let has_foc_norm = open(g, f, OP_if_);
    let hdr_ep = local32(g, f);
    lget(g, hdr_base); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_EPOCH); ltee(g, hdr_ep);
    gget(g, g.s.seq_min_mutable_epoch); op(g, OP_i32_ge_u);
    let mut_flush = open(g, f, OP_if_);
    lget(g, hdr_base); lget(g, hdr_ep); callf(g, flush_fn);
    let fl_root = local32(g, f);
    lget(g, hdr_base); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_ROOT); ltee(g, fl_root);
    let nz_fl = open(g, f, OP_if_);
    lget(g, fl_root);
    lget(g, hdr_base); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_REV);
    op(g, OP_i32_xor);
    lset(g, norm_root);
    op(g, OP_else_);
    i32Const(g, 0); lset(g, norm_root);
    close(g, f);
    op(g, OP_else_);
    lget(g, hdr_base); callf(g, ep_fn); callf(g, norm_fn); lset(g, norm_root);
    close(g, f);
    op(g, OP_else_);
    let raw_root = local32(g, f);
    lget(g, hdr_base); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_ROOT); ltee(g, raw_root);
    let nz_root = open(g, f, OP_if_);
    lget(g, raw_root);
    lget(g, hdr_base); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_HDR_REV);
    op(g, OP_i32_xor);
    lset(g, norm_root);
    op(g, OP_else_);
    i32Const(g, 0); lset(g, norm_root);
    close(g, f);
    close(g, f);

    let stack_mem = local32(g, f);
    i32Const(g, 64); callf(g, rt.stack); lset(g, stack_mem);
    let stack_sp = constLocal(g, f, 0);
    lget(g, norm_root);
    let has_root = open(g, f, OP_if_);
    lget(g, stack_mem); lget(g, norm_root); op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
    lget(g, stack_mem); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, 4);
    i32Const(g, 1); lset(g, stack_sp);
    close(g, f);

    // Height-1 sibling-array leaf cache (eliminates 15/16 = 93.75% of next_leaf_fn calls!)
    let sib_ptr = constLocal(g, f, 0);
    let sib_i = constLocal(g, f, 0);
    let sib_count = constLocal(g, f, 0);
    let sib_rev = constLocal(g, f, 0);

    // Active leaf locals
    let leaf_edge = local32(g, f);
    let leaf_ptr = local32(g, f);
    let leaf_kind = local32(g, f);
    let leaf_rev = local32(g, f);
    let leaf_len = local32(g, f);
    let leaf_i = local32(g, f);

    // Mode-specific locals (keep register pressure minimal!)
    var cur_ptrs: u32[16] = [0; 16];
    var cur_deltas: u32[16] = [0; 16];
    var sum_tags_ptr: u32 = 0;
    let is_soa_mode = sp.leaf_kind == SEQ_KIND_PACKED_SOA && (soa_virtual || soa_destruct);
    let is_split_mode = !is_soa_mode && sp.leaf_kind == SEQ_KIND_PACKED_SUM && split_fused;
    var soa_first_st: i64 = -1;
    if is_soa_mode {
        for st in 0..sp.packed.stream_count {
            var needed = false;
            for fi in 0..sp.packed.soa_field_count {
                if sp.packed.soa_field_stream[fi] == st && ((soa_used_fields >> (fi as u32)) & 1) != 0 {
                    needed = true; break;
                }
            }
            if needed {
                cur_ptrs[st] = local32(g, f);
                cur_deltas[st] = local32(g, f);
                if soa_first_st < 0 { soa_first_st = st; }
            }
        }
    } else if sp.leaf_kind == SEQ_KIND_PACKED_SUM {
        sum_tags_ptr = local32(g, f);
        for st in 1..sp.packed.stream_count {
            var st_needed = true;
            if is_split_mode {
                st_needed = false;
                for ci in 0..sp.packed.variant_count {
                    if sp.packed.variant_stream[ci] == st && ((split_needed_mask >> (ci as u64)) & 1) != 0 {
                        st_needed = true; break;
                    }
                }
            }
            if st_needed { cur_ptrs[st] = local32(g, f); }
        }
    }

    let exit = open(g, f, OP_block);
    let leaf_top = open(g, f, OP_loop);
    f.checked_elems_len = 0;

    // Fetch next leaf_edge via sibling cache or traversal stack
    lget(g, sib_i); lget(g, sib_count); op(g, OP_i32_lt_u);
    let has_sib = open(g, f, OP_if_);
    let phys_j = local32(g, f);
    lget(g, sib_count); i32Const(g, 1); op(g, OP_i32_sub); lget(g, sib_i); op(g, OP_i32_sub);
    lget(g, sib_i);
    lget(g, sib_rev);
    op(g, OP_select);
    lset(g, phys_j);
    lget(g, sib_i); i32Const(g, 1); op(g, OP_i32_add); lset(g, sib_i);
    lget(g, sib_ptr); lget(g, phys_j); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    lget(g, sib_rev); op(g, OP_i32_xor); lset(g, leaf_edge);
    op(g, OP_else_);
    let next_edge = local32(g, f);
    lget(g, stack_mem); lget(g, stack_sp); callf(g, next_leaf_fn);
    lset(g, next_edge); lset(g, stack_sp);
    lget(g, next_edge); op(g, OP_i32_eqz);
    let done_if = open(g, f, OP_if_);
    let assigned = assign(g, f, iteration, outgoing, id);
    if assigned != squid_direct_types::Error.none { return assigned; }
    br(g, f, OP_br, exit);
    close(g, f);
    let n_ptr = local32(g, f);
    let n_meta = local32(g, f);
    lget(g, next_edge); i32Const(g, 0xfffffffe); op(g, OP_i32_and); ltee(g, n_ptr);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_META); ltee(g, n_meta);
    i32Const(g, 15); op(g, OP_i32_and); op(g, OP_i32_eqz);
    let is_h1 = open(g, f, OP_if_);
    lget(g, n_ptr); lset(g, sib_ptr);
    lget(g, next_edge); i32Const(g, 1); op(g, OP_i32_and); lset(g, sib_rev);
    lget(g, n_meta); i32Const(g, 8); op(g, OP_i32_shr_u); i32Const(g, 255); op(g, OP_i32_and); lset(g, sib_count);
    i32Const(g, 1); lset(g, sib_i);
    let p0 = local32(g, f);
    lget(g, sib_count); i32Const(g, 1); op(g, OP_i32_sub);
    i32Const(g, 0);
    lget(g, sib_rev);
    op(g, OP_select);
    lset(g, p0);
    lget(g, sib_ptr); lget(g, p0); i32Const(g, 2); op(g, OP_i32_shl); op(g, OP_i32_add);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_NODE_CHILDREN);
    lget(g, sib_rev); op(g, OP_i32_xor); lset(g, leaf_edge);
    op(g, OP_else_);
    lget(g, next_edge); lset(g, leaf_edge);
    close(g, f);
    close(g, f);

    // Unpack active leaf header; skip empty leaves
    lget(g, leaf_edge); i32Const(g, 0xfffffffe); op(g, OP_i32_and); lset(g, leaf_ptr);
    lget(g, leaf_edge); i32Const(g, 1); op(g, OP_i32_and); lset(g, leaf_rev);
    lget(g, leaf_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_LEAF_META); i32Const(g, 15); op(g, OP_i32_and); lset(g, leaf_kind);
    lget(g, leaf_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_LEAF_LEN); ltee(g, leaf_len);
    op(g, OP_i32_eqz); br(g, f, OP_br_if, leaf_top);

    // Save Fn fact caches when specializing fast vs fallback inner loops
    let saved_ca = f.checked_arrays;
    let saved_ca_len = f.checked_arrays_len;
    let saved_cg = f.checked_grows;
    let saved_cg_len = f.checked_grows_len;
    let saved_cv = f.checked_views;
    let saved_cv_len = f.checked_views_len;
    let saved_ce = f.checked_elems;
    let saved_ce_len = f.checked_elems_len;
    let saved_cb_len = f.checked_bounds_len;
    let saved_cl_len = f.checked_le_len;
    let saved_cm_len = f.checked_masks_len;
    let saved_cadd_len = f.checked_adds_len;
    let saved_caff_len = f.checked_affines_len;
    let saved_csub_len = f.checked_sub1_len;
    let saved_cu32_len = f.const_u32_len;
    let saved_cu64_len = f.const_u64_len;
    let saved_ext_len = f.ext_u32_u64_len;
    let saved_km_len = f.known_mutable_len;
    let saved_ct_len = f.const_tags_len;

    if is_soa_mode {
        // ---- Mode 1: Touched-column SoA (`LEAF_PACKED_SOA`) ----
        if can_spec {
            lget(g, leaf_kind); i32Const(g, SEQ_KIND_PACKED_SOA); op(g, OP_i32_eq);
            lget(g, leaf_rev); op(g, OP_i32_eqz);
            op(g, OP_i32_and);
            let fast_soa_if = open(g, f, OP_if_);
            // Tight forward PACKED_SOA inner loop: ZERO calls, ZERO leaf_kind branches, constant-stride pointers!
            for st in 0..sp.packed.stream_count {
                if cur_ptrs[st] == 0 { continue; }
                lget(g, leaf_ptr); i32Const(g, sp.soa_col_off[st]); op(g, OP_i32_add); lset(g, cur_ptrs[st]);
            }
            var end_ptr: u32 = 0;
            if soa_first_st >= 0 {
                end_ptr = emitOffsetAddress(g, f, cur_ptrs[soa_first_st], leaf_len, sp.packed.stream_stride[soa_first_st]);
            } else {
                i32Const(g, 0); lset(g, leaf_i);
            }
            let elem_exit = open(g, f, OP_block);
            let elem_top = open(g, f, OP_loop);
            f.checked_elems_len = 0;
            if soa_first_st >= 0 {
                lget(g, cur_ptrs[soa_first_st]); lget(g, end_ptr); op(g, OP_i32_ge_u); br(g, f, OP_br_if, elem_exit);
            } else {
                lget(g, leaf_i); lget(g, leaf_len); op(g, OP_i32_ge_u); br(g, f, OP_br_if, elem_exit);
                lget(g, leaf_i); i32Const(g, 1); op(g, OP_i32_add); lset(g, leaf_i);
            }
            var pushed_soa_fast = false;
            if soa_virtual {
                let d = soa_loop_depth;
                soa_loop_binding[d] = soa_bind_id;
                soa_loop_ty[d] = elem_ty;
                soa_loop_inner_ty[d] = sp.packed.soa_inner_ty;
                soa_loop_is_record[d] = sp.packed.soa_is_record;
                for fi in 0..16 { soa_loop_field_loaded[d * 16 + fi] = false; }
                for fi in 0..sp.packed.soa_field_count {
                    if ((soa_used_fields >> (fi as u32)) & 1) == 0 { continue; }
                    let st = sp.packed.soa_field_stream[fi];
                    let fty = sp.packed.soa_field_ty[fi];
                    var fv = Val { fty, 0, 0 };
                    if st >= 0 {
                        let loaded, lerr = loadElement(g, f, cur_ptrs[st], 0, fty, id);
                        if lerr != squid_direct_types::Error.none { return lerr; }
                        lget(g, cur_ptrs[st]); i32Const(g, sp.packed.stream_stride[st]); op(g, OP_i32_add); lset(g, cur_ptrs[st]);
                        fv = loaded;
                    }
                    let slot_i = d * 16 + fi;
                    soa_loop_field_loaded[slot_i] = true;
                    soa_loop_field_start[slot_i] = fv.start;
                    soa_loop_field_len[slot_i] = fv.len;
                    soa_loop_field_ty[slot_i] = fv.ty;
                }
                soa_loop_depth += 1;
                pushed_soa_fast = true;
            } else {
                for fi in 0..sp.packed.soa_field_count {
                    if ((soa_used_fields >> (fi as u32)) & 1) == 0 { continue; }
                    let st = sp.packed.soa_field_stream[fi];
                    let fty = sp.packed.soa_field_ty[fi];
                    var fv = Val { fty, 0, 0 };
                    if st >= 0 {
                        let loaded, lerr = loadElement(g, f, cur_ptrs[st], 0, fty, id);
                        if lerr != squid_direct_types::Error.none { return lerr; }
                        lget(g, cur_ptrs[st]); i32Const(g, sp.packed.stream_stride[st]); op(g, OP_i32_add); lset(g, cur_ptrs[st]);
                        fv = loaded;
                    }
                    let terr = test_(g, f, soa_field_pats[fi], fv, false, 0, id);
                    if terr != squid_direct_types::Error.none { return terr; }
                }
            }
            let berr = emitSeqLoopBodyTail(g, f, id, info, iteration, outgoing, slots, exit, elem_top, false, 0, 0, 0, 0xffffffff, guards, pushed_soa_fast, false);
            if berr != squid_direct_types::Error.none { return berr; }
            close(g, f);
            close(g, f);

            // Restore Fn caches before fallback branch
            f.checked_arrays = saved_ca; f.checked_arrays_len = saved_ca_len;
            f.checked_grows = saved_cg; f.checked_grows_len = saved_cg_len;
            f.checked_views = saved_cv; f.checked_views_len = saved_cv_len;
            f.checked_elems = saved_ce; f.checked_elems_len = saved_ce_len;
            f.checked_bounds_len = saved_cb_len; f.checked_le_len = saved_cl_len; f.checked_masks_len = saved_cm_len;
            f.checked_adds_len = saved_cadd_len; f.checked_affines_len = saved_caff_len; f.checked_sub1_len = saved_csub_len;
            f.const_u32_len = saved_cu32_len; f.const_u64_len = saved_cu64_len; f.ext_u32_u64_len = saved_ext_len;
            f.known_mutable_len = saved_km_len; f.const_tags_len = saved_ct_len;
            op(g, OP_else_);
        }

        // General / reversed / SPAN / REPEAT SoA inner loop
        lget(g, leaf_kind); i32Const(g, SEQ_KIND_PACKED_SOA); op(g, OP_i32_eq);
        let init_soa = open(g, f, OP_if_);
        let last_i = local32(g, f);
        lget(g, leaf_len); i32Const(g, 1); op(g, OP_i32_sub); lset(g, last_i);
        for st in 0..sp.packed.stream_count {
            if cur_ptrs[st] == 0 { continue; }
            let col_b = local32(g, f);
            lget(g, leaf_ptr); i32Const(g, sp.soa_col_off[st]); op(g, OP_i32_add); lset(g, col_b);
            let step = sp.packed.stream_stride[st];
            lget(g, leaf_rev);
            let rev_s = open(g, f, OP_if_);
            let ea = emitOffsetAddress(g, f, col_b, last_i, step);
            lget(g, ea); lset(g, cur_ptrs[st]);
            i32Const(g, 0 - step); lset(g, cur_deltas[st]);
            op(g, OP_else_);
            lget(g, col_b); lset(g, cur_ptrs[st]);
            i32Const(g, step); lset(g, cur_deltas[st]);
            close(g, f);
        }
        close(g, f);
        i32Const(g, 0); lset(g, leaf_i);
        let elem_exit = open(g, f, OP_block);
        let elem_top = open(g, f, OP_loop);
        f.checked_elems_len = 0;
        lget(g, leaf_i); lget(g, leaf_len); op(g, OP_i32_ge_u); br(g, f, OP_br_if, elem_exit);
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
            gget(g, rt.escape_min_slot); lset(g, saved_escape);
            i32Const(g, 0xffffffff); gset(g, rt.escape_min_slot);
        }
        let cur_li = local32(g, f);
        lget(g, leaf_i); lset(g, cur_li);
        lget(g, leaf_i); i32Const(g, 1); op(g, OP_i32_add); lset(g, leaf_i);
        var pushed_soa_fb = false;
        var field_locs: Val[16] = [Val {}; 16];
        for fi in 0..sp.packed.soa_field_count {
            if ((soa_used_fields >> (fi as u32)) & 1) == 0 { continue; }
            let fv, fverr = fresh(g, f, sp.packed.soa_field_ty[fi], id);
            if fverr != squid_direct_types::Error.none { return fverr; }
            field_locs[fi] = fv;
        }
        lget(g, leaf_kind); i32Const(g, SEQ_KIND_PACKED_SOA); op(g, OP_i32_eq);
        let soa_fast = open(g, f, OP_if_);
        for fi in 0..sp.packed.soa_field_count {
            if ((soa_used_fields >> (fi as u32)) & 1) == 0 { continue; }
            let st = sp.packed.soa_field_stream[fi];
            if st >= 0 {
                let loaded, lerr = loadElement(g, f, cur_ptrs[st], 0, sp.packed.soa_field_ty[fi], id);
                if lerr != squid_direct_types::Error.none { return lerr; }
                let _ = copy(g, f, loaded, field_locs[fi], id);
                lget(g, cur_ptrs[st]); lget(g, cur_deltas[st]); op(g, OP_i32_add); lset(g, cur_ptrs[st]);
            }
        }
        op(g, OP_else_);
        lget(g, leaf_edge); lget(g, cur_li); callf(g, leaf_get_fn);
        let full_v, fperr = pop(g, f, elem_ty, id);
        if fperr != squid_direct_types::Error.none { return fperr; }
        var inner_v = full_v;
        if sp.packed.soa_is_nominal {
            let uw, uerr = unwrapVariant(g, f, full_v, sp.packed.soa_nominal_tag, id);
            if uerr != squid_direct_types::Error.none { return uerr; }
            inner_v = uw;
        }
        for fi in 0..sp.packed.soa_field_count {
            if ((soa_used_fields >> (fi as u32)) & 1) == 0 { continue; }
            var fv = neverVal();
            if sp.packed.soa_is_record {
                let got, gerr = recordField(g, f, inner_v, fi, id);
                if gerr != squid_direct_types::Error.none { return gerr; }
                fv = got;
            } else {
                let got, gerr = tupleItem(g, f, inner_v, fi, id);
                if gerr != squid_direct_types::Error.none { return gerr; }
                fv = got;
            }
            let _ = copy(g, f, fv, field_locs[fi], id);
        }
        close(g, f);
        if soa_virtual {
            let d = soa_loop_depth;
            soa_loop_binding[d] = soa_bind_id;
            soa_loop_ty[d] = elem_ty;
            soa_loop_inner_ty[d] = sp.packed.soa_inner_ty;
            soa_loop_is_record[d] = sp.packed.soa_is_record;
            for fi in 0..16 { soa_loop_field_loaded[d * 16 + fi] = false; }
            for fi in 0..sp.packed.soa_field_count {
                if ((soa_used_fields >> (fi as u32)) & 1) == 0 { continue; }
                let slot_i = d * 16 + fi;
                soa_loop_field_loaded[slot_i] = true;
                soa_loop_field_start[slot_i] = field_locs[fi].start;
                soa_loop_field_len[slot_i] = field_locs[fi].len;
                soa_loop_field_ty[slot_i] = field_locs[fi].ty;
            }
            soa_loop_depth += 1;
            pushed_soa_fb = true;
        } else {
            for fi in 0..sp.packed.soa_field_count {
                if ((soa_used_fields >> (fi as u32)) & 1) == 0 { continue; }
                let terr = test_(g, f, soa_field_pats[fi], field_locs[fi], false, 0, id);
                if terr != squid_direct_types::Error.none { return terr; }
            }
        }
        let berr = emitSeqLoopBodyTail(g, f, id, info, iteration, outgoing, slots, exit, elem_top, release, release_owner, release_stack, saved_escape, unchanged, guards, pushed_soa_fb, false);
        if berr != squid_direct_types::Error.none { return berr; }
        close(g, f);
        close(g, f);

        if can_spec {
            close(g, f);
            f.checked_arrays = saved_ca; f.checked_arrays_len = saved_ca_len;
            f.checked_grows = saved_cg; f.checked_grows_len = saved_cg_len;
            f.checked_views = saved_cv; f.checked_views_len = saved_cv_len;
            f.checked_elems = saved_ce; f.checked_elems_len = saved_ce_len;
            f.checked_bounds_len = saved_cb_len; f.checked_le_len = saved_cl_len; f.checked_masks_len = saved_cm_len;
            f.checked_adds_len = saved_cadd_len; f.checked_affines_len = saved_caff_len; f.checked_sub1_len = saved_csub_len;
            f.const_u32_len = saved_cu32_len; f.const_u64_len = saved_cu64_len; f.ext_u32_u64_len = saved_ext_len;
            f.known_mutable_len = saved_km_len; f.const_tags_len = saved_ct_len;
        }
    } else if is_split_mode {
        // ---- Mode 2: Fused Split-Sum (`LEAF_PACKED_SUM`) ----
        // Un-reverse reversed PACKED_SUM leaves ONCE in the outer leaf loop so inner loop always streams forward!
        lget(g, leaf_kind); i32Const(g, SEQ_KIND_PACKED_SUM); op(g, OP_i32_eq);
        let init_sum = open(g, f, OP_if_);
        lget(g, leaf_rev);
        let rev_sum = open(g, f, OP_if_);
        lget(g, leaf_edge); callf(g, ep_fn); callf(g, unrev_sum_fn); lset(g, leaf_ptr);
        i32Const(g, 0); lset(g, leaf_rev);
        close(g, f);
        lget(g, leaf_ptr); i32Const(g, SEQ_SUM_TAGS); op(g, OP_i32_add); lset(g, sum_tags_ptr);
        for st in 1..sp.packed.stream_count {
            if cur_ptrs[st] == 0 { continue; }
            lget(g, leaf_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_SUM_SUB_PTRS + ((st - 1) as u32) * 4);
            lset(g, cur_ptrs[st]);
        }
        close(g, f);

        if can_spec {
            lget(g, leaf_kind); i32Const(g, SEQ_KIND_PACKED_SUM); op(g, OP_i32_eq);
            let fast_sum_if = open(g, f, OP_if_);
            // Tight forward PACKED_SUM inner loop: ZERO calls, ZERO leaf_kind branches, pointer-compare tags_ptr < tags_end!
            let tags_end = local32(g, f);
            lget(g, sum_tags_ptr); lget(g, leaf_len); op(g, OP_i32_add); lset(g, tags_end);
            let ci_loc = local32(g, f);
            let elem_exit = open(g, f, OP_block);
            let elem_top = open(g, f, OP_loop);
            f.checked_elems_len = 0;
            lget(g, sum_tags_ptr); lget(g, tags_end); op(g, OP_i32_ge_u); br(g, f, OP_br_if, elem_exit);
            lget(g, sum_tags_ptr); op(g, OP_i32_load8_u); uleb(g, 0); uleb(g, 0); lset(g, ci_loc);
            lget(g, sum_tags_ptr); i32Const(g, 1); op(g, OP_i32_add); lset(g, sum_tags_ptr);
            let d = split_sum_depth;
            split_sum_binding[d] = split_bind_id;
            split_sum_ty[d] = elem_ty;
            split_sum_ci_loc[d] = ci_loc;
            split_sum_needed_lo[d] = split_needed_mask;
            for st in 0..16 {
                split_sum_cur_ptrs[d * 16 + st] = cur_ptrs[st];
                split_sum_stream_stride[d * 16 + st] = sp.packed.stream_stride[st];
            }
            for ci in 0..64 {
                split_sum_variant_stream[d * 64 + ci] = if ci < sp.packed.variant_count { sp.packed.variant_stream[ci] } else { -1 };
            }
            split_sum_depth += 1;
            let berr = emitSeqLoopBodyTail(g, f, id, info, iteration, outgoing, slots, exit, elem_top, false, 0, 0, 0, 0xffffffff, guards, false, true);
            if berr != squid_direct_types::Error.none { return berr; }
            close(g, f);
            close(g, f);

            f.checked_arrays = saved_ca; f.checked_arrays_len = saved_ca_len;
            f.checked_grows = saved_cg; f.checked_grows_len = saved_cg_len;
            f.checked_views = saved_cv; f.checked_views_len = saved_cv_len;
            f.checked_elems = saved_ce; f.checked_elems_len = saved_ce_len;
            f.checked_bounds_len = saved_cb_len; f.checked_le_len = saved_cl_len; f.checked_masks_len = saved_cm_len;
            f.checked_adds_len = saved_cadd_len; f.checked_affines_len = saved_caff_len; f.checked_sub1_len = saved_csub_len;
            f.const_u32_len = saved_cu32_len; f.const_u64_len = saved_cu64_len; f.ext_u32_u64_len = saved_ext_len;
            f.known_mutable_len = saved_km_len; f.const_tags_len = saved_ct_len;
            op(g, OP_else_);
        }

        // General / non-packed (SPAN / REPEAT) sum inner loop
        var fb_slots: u32[16] = [0; 16];
        for st in 1..sp.packed.stream_count {
            if cur_ptrs[st] != 0 {
                fb_slots[st] = allocate(g, f, sp.packed.stream_stride[st]);
            }
        }
        i32Const(g, 0); lset(g, leaf_i);
        let ci_loc = local32(g, f);
        let elem_exit = open(g, f, OP_block);
        let elem_top = open(g, f, OP_loop);
        f.checked_elems_len = 0;
        lget(g, leaf_i); lget(g, leaf_len); op(g, OP_i32_ge_u); br(g, f, OP_br_if, elem_exit);
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
            gget(g, rt.escape_min_slot); lset(g, saved_escape);
            i32Const(g, 0xffffffff); gset(g, rt.escape_min_slot);
        }
        let cur_li = local32(g, f);
        lget(g, leaf_i); lset(g, cur_li);
        lget(g, leaf_i); i32Const(g, 1); op(g, OP_i32_add); lset(g, leaf_i);
        if !can_spec {
            lget(g, leaf_kind); i32Const(g, SEQ_KIND_PACKED_SUM); op(g, OP_i32_eq);
            let fast_sum = open(g, f, OP_if_);
            lget(g, sum_tags_ptr); lget(g, cur_li); op(g, OP_i32_add);
            op(g, OP_i32_load8_u); uleb(g, 0); uleb(g, 0); lset(g, ci_loc);
            op(g, OP_else_);
        }
        // Non-packed leaf (SPAN / REPEAT): decode into reusable 1-elem stack slot per needed stream
        lget(g, leaf_edge); lget(g, cur_li); callf(g, leaf_get_fn);
        let ev_fb, efberr = pop(g, f, elem_ty, id);
        if efberr != squid_direct_types::Error.none { return efberr; }
        let cases, cerr = g.types.variants(elem_ty);
        if cerr != squid_direct_types::Error.none { return cerr; }
        let vtag_fb = local32(g, f);
        let terr = emitValueTag(g, f, ev_fb, id);
        if terr != squid_direct_types::Error.none { return terr; }
        lset(g, vtag_fb);
        for ci in 0..(cases.len as i64) {
            let vtag = g.types.variant_tags[cases.tags + ci];
            let st = sp.packed.variant_stream[ci];
            lget(g, vtag_fb); i32Const(g, vtag); op(g, OP_i32_eq);
            let arm = open(g, f, OP_if_);
            i32Const(g, ci as u32); lset(g, ci_loc);
            if st >= 1 && ((split_needed_mask >> (ci as u64)) & 1) != 0 {
                let uw, uerr = unwrapVariant(g, f, ev_fb, vtag, id);
                if uerr != squid_direct_types::Error.none { return uerr; }
                let werr = writeElement(g, f, fb_slots[st], 0, uw, id);
                if werr != squid_direct_types::Error.none { return werr; }
                lget(g, fb_slots[st]); lset(g, cur_ptrs[st]);
            }
            close(g, f);
        }
        if !can_spec { close(g, f); }
        let d = split_sum_depth;
        split_sum_binding[d] = split_bind_id;
        split_sum_ty[d] = elem_ty;
        split_sum_ci_loc[d] = ci_loc;
        split_sum_needed_lo[d] = split_needed_mask;
        for st in 0..16 {
            split_sum_cur_ptrs[d * 16 + st] = cur_ptrs[st];
            split_sum_stream_stride[d * 16 + st] = sp.packed.stream_stride[st];
        }
        for ci in 0..64 {
            split_sum_variant_stream[d * 64 + ci] = if ci < sp.packed.variant_count { sp.packed.variant_stream[ci] } else { -1 };
        }
        split_sum_depth += 1;
        let berr = emitSeqLoopBodyTail(g, f, id, info, iteration, outgoing, slots, exit, elem_top, release, release_owner, release_stack, saved_escape, unchanged, guards, false, true);
        if berr != squid_direct_types::Error.none { return berr; }
        close(g, f);
        close(g, f);

        if can_spec {
            close(g, f);
            f.checked_arrays = saved_ca; f.checked_arrays_len = saved_ca_len;
            f.checked_grows = saved_cg; f.checked_grows_len = saved_cg_len;
            f.checked_views = saved_cv; f.checked_views_len = saved_cv_len;
            f.checked_elems = saved_ce; f.checked_elems_len = saved_ce_len;
            f.checked_bounds_len = saved_cb_len; f.checked_le_len = saved_cl_len; f.checked_masks_len = saved_cm_len;
            f.checked_adds_len = saved_cadd_len; f.checked_affines_len = saved_caff_len; f.checked_sub1_len = saved_csub_len;
            f.const_u32_len = saved_cu32_len; f.const_u64_len = saved_cu64_len; f.ext_u32_u64_len = saved_ext_len;
            f.known_mutable_len = saved_km_len; f.const_tags_len = saved_ct_len;
        }
    } else {
        // ---- Mode 3: General (`FLAT` / `SPAN` / `RAMP` / `REPEAT` / non-fused `PACKED_SUM` / non-virtual `PACKED_SOA`) ----
        let do_flat_spec = can_spec && sp.elem_bytes != 0;
        if do_flat_spec {
            lget(g, leaf_kind); i32Const(g, SEQ_KIND_FLAT); op(g, OP_i32_eq);
            lget(g, leaf_kind); i32Const(g, SEQ_KIND_SPAN); op(g, OP_i32_eq);
            op(g, OP_i32_or);
            lget(g, leaf_rev); op(g, OP_i32_eqz);
            op(g, OP_i32_and);
            let fast_flat_if = open(g, f, OP_if_);
            // Tight forward FLAT/SPAN inner loop: ZERO calls, ZERO leaf_kind checks, auto-vectorizable!
            let f_cur = local32(g, f);
            lget(g, leaf_kind); i32Const(g, SEQ_KIND_SPAN); op(g, OP_i32_eq);
            let is_sp = open(g, f, OP_if_);
            lget(g, leaf_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_SPAN_PTR); lset(g, f_cur);
            op(g, OP_else_);
            lget(g, leaf_ptr); i32Const(g, SEQ_LEAF_DATA); op(g, OP_i32_add); lset(g, f_cur);
            close(g, f);
            let f_end = emitOffsetAddress(g, f, f_cur, leaf_len, sp.elem_bytes);
            let elem_exit = open(g, f, OP_block);
            let elem_top = open(g, f, OP_loop);
            f.checked_elems_len = 0;
            lget(g, f_cur); lget(g, f_end); op(g, OP_i32_ge_u); br(g, f, OP_br_if, elem_exit);
            let loaded, lerr = loadElement(g, f, f_cur, 0, elem_ty, id);
            if lerr != squid_direct_types::Error.none { return lerr; }
            lget(g, f_cur); i32Const(g, sp.elem_bytes); op(g, OP_i32_add); lset(g, f_cur);
            if info.pattern != 0 {
                let terr = test_(g, f, info.pattern, loaded, false, 0, id);
                if terr != squid_direct_types::Error.none { return terr; }
            }
            let berr = emitSeqLoopBodyTail(g, f, id, info, iteration, outgoing, slots, exit, elem_top, false, 0, 0, 0, 0xffffffff, guards, false, false);
            if berr != squid_direct_types::Error.none { return berr; }
            close(g, f);
            close(g, f);

            f.checked_arrays = saved_ca; f.checked_arrays_len = saved_ca_len;
            f.checked_grows = saved_cg; f.checked_grows_len = saved_cg_len;
            f.checked_views = saved_cv; f.checked_views_len = saved_cv_len;
            f.checked_elems = saved_ce; f.checked_elems_len = saved_ce_len;
            f.checked_bounds_len = saved_cb_len; f.checked_le_len = saved_cl_len; f.checked_masks_len = saved_cm_len;
            f.checked_adds_len = saved_cadd_len; f.checked_affines_len = saved_caff_len; f.checked_sub1_len = saved_csub_len;
            f.const_u32_len = saved_cu32_len; f.const_u64_len = saved_cu64_len; f.ext_u32_u64_len = saved_ext_len;
            f.known_mutable_len = saved_km_len; f.const_tags_len = saved_ct_len;
            op(g, OP_else_);
        }

        // General / reversed / RAMP / REPEAT / non-fused SUM / non-virtual SOA inner loop
        let is_fast_flat = local32(g, f);
        let cur_ptr = local32(g, f);
        let cur_delta = local32(g, f);
        var ramp_val: u32 = 0;
        var ramp_delta: u32 = 0;
        if elem_ty == squid_direct_types::u32_ {
            ramp_val = local32(g, f);
            ramp_delta = local32(g, f);
        }
        var rep_val = neverVal();
        if sp.elem_bytes != 0 {
            let rv, rverr = fresh(g, f, elem_ty, id);
            if rverr != squid_direct_types::Error.none { return rverr; }
            rep_val = rv;
        }
        // Hoist per-leaf state ONCE before inner loop
        lget(g, leaf_kind); i32Const(g, SEQ_KIND_FLAT); op(g, OP_i32_eq);
        lget(g, leaf_kind); i32Const(g, SEQ_KIND_SPAN); op(g, OP_i32_eq);
        op(g, OP_i32_or); ltee(g, is_fast_flat);
        let init_flat = open(g, f, OP_if_);
        if sp.elem_bytes != 0 {
            let base_p = local32(g, f);
            lget(g, leaf_kind); i32Const(g, SEQ_KIND_SPAN); op(g, OP_i32_eq);
            let is_sp = open(g, f, OP_if_);
            lget(g, leaf_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_SPAN_PTR); lset(g, base_p);
            op(g, OP_else_);
            lget(g, leaf_ptr); i32Const(g, SEQ_LEAF_DATA); op(g, OP_i32_add); lset(g, base_p);
            close(g, f);
            lget(g, leaf_rev);
            let rev_f = open(g, f, OP_if_);
            let last_i = local32(g, f);
            lget(g, leaf_len); i32Const(g, 1); op(g, OP_i32_sub); lset(g, last_i);
            let end_a = emitOffsetAddress(g, f, base_p, last_i, sp.elem_bytes);
            lget(g, end_a); lset(g, cur_ptr);
            i32Const(g, 0 - sp.elem_bytes); lset(g, cur_delta);
            op(g, OP_else_);
            lget(g, base_p); lset(g, cur_ptr);
            i32Const(g, sp.elem_bytes); lset(g, cur_delta);
            close(g, f);
        }
        close(g, f);
        lget(g, leaf_kind); i32Const(g, SEQ_KIND_REPEAT); op(g, OP_i32_eq);
        let init_rep = open(g, f, OP_if_);
        if sp.elem_bytes != 0 {
            let rbase = local32(g, f);
            lget(g, leaf_ptr); i32Const(g, SEQ_LEAF_DATA); op(g, OP_i32_add); lset(g, rbase);
            let loaded_r, lrerr = loadElement(g, f, rbase, 0, elem_ty, id);
            if lrerr != squid_direct_types::Error.none { return lrerr; }
            let _ = copy(g, f, loaded_r, rep_val, id);
        }
        close(g, f);
        if elem_ty == squid_direct_types::u32_ {
            lget(g, leaf_kind); i32Const(g, SEQ_KIND_RAMP); op(g, OP_i32_eq);
            let init_ramp = open(g, f, OP_if_);
            let rs = local32(g, f);
            let rstep = local32(g, f);
            lget(g, leaf_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_RAMP_START); lset(g, rs);
            lget(g, leaf_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_RAMP_STEP); lset(g, rstep);
            lget(g, leaf_rev);
            let rev_r = open(g, f, OP_if_);
            lget(g, rs); lget(g, leaf_len); i32Const(g, 1); op(g, OP_i32_sub); lget(g, rstep); op(g, OP_i32_mul); op(g, OP_i32_add);
            lset(g, ramp_val);
            i32Const(g, 0); lget(g, rstep); op(g, OP_i32_sub); lset(g, ramp_delta);
            op(g, OP_else_);
            lget(g, rs); lset(g, ramp_val);
            lget(g, rstep); lset(g, ramp_delta);
            close(g, f);
            close(g, f);
        }
        if sp.leaf_kind == SEQ_KIND_PACKED_SUM {
            lget(g, leaf_kind); i32Const(g, SEQ_KIND_PACKED_SUM); op(g, OP_i32_eq);
            let init_sum = open(g, f, OP_if_);
            lget(g, leaf_rev);
            let rev_sum = open(g, f, OP_if_);
            lget(g, leaf_edge); callf(g, ep_fn); callf(g, unrev_sum_fn); lset(g, leaf_ptr);
            i32Const(g, 0); lset(g, leaf_rev);
            close(g, f);
            lget(g, leaf_ptr); i32Const(g, SEQ_SUM_TAGS); op(g, OP_i32_add); lset(g, sum_tags_ptr);
            for st in 1..sp.packed.stream_count {
                lget(g, leaf_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, SEQ_SUM_SUB_PTRS + ((st - 1) as u32) * 4);
                lset(g, cur_ptrs[st]);
            }
            close(g, f);
        }

        i32Const(g, 0); lset(g, leaf_i);
        let elem_exit = open(g, f, OP_block);
        let elem_top = open(g, f, OP_loop);
        f.checked_elems_len = 0;
        lget(g, leaf_i); lget(g, leaf_len); op(g, OP_i32_ge_u); br(g, f, OP_br_if, elem_exit);
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
            gget(g, rt.escape_min_slot); lset(g, saved_escape);
            i32Const(g, 0xffffffff); gset(g, rt.escape_min_slot);
        }
        let cur_li = local32(g, f);
        lget(g, leaf_i); lset(g, cur_li);
        lget(g, leaf_i); i32Const(g, 1); op(g, OP_i32_add); lset(g, leaf_i);
        let item, iferr = fresh(g, f, elem_ty, id);
        if iferr != squid_direct_types::Error.none { return iferr; }
        if sp.elem_bytes != 0 {
            lget(g, is_fast_flat);
            let f_if = open(g, f, OP_if_);
            let loaded, lerr = loadElement(g, f, cur_ptr, 0, elem_ty, id);
            if lerr != squid_direct_types::Error.none { return lerr; }
            let _ = copy(g, f, loaded, item, id);
            lget(g, cur_ptr); lget(g, cur_delta); op(g, OP_i32_add); lset(g, cur_ptr);
            op(g, OP_else_);
            let item_done = open(g, f, OP_block);
            if elem_ty == squid_direct_types::u32_ {
                lget(g, leaf_kind); i32Const(g, SEQ_KIND_RAMP); op(g, OP_i32_eq);
                let r_if = open(g, f, OP_if_);
                lget(g, ramp_val); lset(g, w(g, item, 0));
                lget(g, ramp_val); lget(g, ramp_delta); op(g, OP_i32_add); lset(g, ramp_val);
                br(g, f, OP_br, item_done);
                close(g, f);
            }
            lget(g, leaf_kind); i32Const(g, SEQ_KIND_REPEAT); op(g, OP_i32_eq);
            let rep_if = open(g, f, OP_if_);
            let _ = copy(g, f, rep_val, item, id);
            br(g, f, OP_br, item_done);
            close(g, f);
            if sp.leaf_kind == SEQ_KIND_PACKED_SUM {
                let decoded, derr = emitPackedDecodeStep(g, f, sp.packed, cur_ptrs[..], sum_tags_ptr, cur_li, id);
                if derr != squid_direct_types::Error.none { return derr; }
                let _ = copy(g, f, decoded, item, id);
                br(g, f, OP_br, item_done);
            } else {
                lget(g, leaf_edge); lget(g, cur_li); callf(g, leaf_get_fn);
                let got, gerr = pop(g, f, elem_ty, id);
                if gerr != squid_direct_types::Error.none { return gerr; }
                let _ = copy(g, f, got, item, id);
            }
            close(g, f);
            close(g, f);
        }
        if info.pattern != 0 {
            let terr = test_(g, f, info.pattern, item, false, 0, id);
            if terr != squid_direct_types::Error.none { return terr; }
        }
        let berr = emitSeqLoopBodyTail(g, f, id, info, iteration, outgoing, slots, exit, elem_top, release, release_owner, release_stack, saved_escape, unchanged, guards, false, false);
        if berr != squid_direct_types::Error.none { return berr; }
        close(g, f);
        close(g, f);

        if do_flat_spec {
            close(g, f);
            f.checked_arrays = saved_ca; f.checked_arrays_len = saved_ca_len;
            f.checked_grows = saved_cg; f.checked_grows_len = saved_cg_len;
            f.checked_views = saved_cv; f.checked_views_len = saved_cv_len;
            f.checked_elems = saved_ce; f.checked_elems_len = saved_ce_len;
            f.checked_bounds_len = saved_cb_len; f.checked_le_len = saved_cl_len; f.checked_masks_len = saved_cm_len;
            f.checked_adds_len = saved_cadd_len; f.checked_affines_len = saved_caff_len; f.checked_sub1_len = saved_csub_len;
            f.const_u32_len = saved_cu32_len; f.const_u64_len = saved_cu64_len; f.ext_u32_u64_len = saved_ext_len;
            f.known_mutable_len = saved_km_len; f.const_tags_len = saved_ct_len;
        }
    }

    br(g, f, OP_br, leaf_top);
    close(g, f);
    close(g, f);
    return squid_direct_types::Error.none;
}
