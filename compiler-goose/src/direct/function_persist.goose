// 100% iterative two-phase persistent state staging for `#kernel` prepared
// contexts and `#process` state (tasks/CONCURRENCY_VNEXT.md §4.2.2 item 5).
// Uses O(1) Wasm call stack via heap-backed scratch vectors & O(1) open-addressed
// hash maps, guarantees zero persistent mutations in Phase 1, and commits
// atomically in Phase 2 with explicit temp-slot detach ONLY for transferred
// StealHeap/CopiedHeap/new_block_pins/ledger/reply backings (leaving Empty temp
// slots intact so releaseEntry() frees any retained heap capacity).
namespace blot_direct_function;
import .function;

struct PersistRoot {
    state_ty: Ty = 0,
    holds_mem: bool = false,
    state_globals_start: u32 = 0,
    state_globals_len: u32 = 0,
    status_global: u32 = 0,
    live_owners_ptr: u32 = 0,
    live_owners_len: u32 = 0,
    live_owners_cap: u32 = 0,
    live_blocks_ptr: u32 = 0,
    live_blocks_len: u32 = 0,
    live_blocks_cap: u32 = 0,
}

fn createPersistRoot(g: Generator&, state_ty: Ty) -> PersistRoot, Error {
    let layout, lerr = g.types.layout(state_ty);
    if lerr != blot_direct_types::Error.none { return PersistRoot {}, lerr; }
    let holds, herr = g.holdsMemory(state_ty);
    if herr != blot_direct_types::Error.none { return PersistRoot {}, herr; }
    let start = g.s.words.len as u32;
    for wt in layout {
        let gid = g.module.addGlobal(wt, true, 0);
        g.s.words.push(gid);
    }
    let status_g = g.module.addGlobal(VT_i32, true, 0);
    var root = PersistRoot {
        state_ty: state_ty,
        holds_mem: holds,
        state_globals_start: start,
        state_globals_len: layout.len as u32,
        status_global: status_g,
    };
    if holds {
        root.live_owners_ptr = g.module.addGlobal(VT_i32, true, 0);
        root.live_owners_len = g.module.addGlobal(VT_i32, true, 0);
        root.live_owners_cap = g.module.addGlobal(VT_i32, true, 0);
        root.live_blocks_ptr = g.module.addGlobal(VT_i32, true, 0);
        root.live_blocks_len = g.module.addGlobal(VT_i32, true, 0);
        root.live_blocks_cap = g.module.addGlobal(VT_i32, true, 0);
    }
    return root, blot_direct_types::Error.none;
}

fn loadPersistRootVal(g: Generator&, f: Fn&, root: PersistRoot) -> Val, Error {
    let val, ferr = fresh(g, f, root.state_ty, 0);
    if ferr != blot_direct_types::Error.none { return neverVal(), ferr; }
    for wi in 0..(root.state_globals_len as i64) {
        let gid = g.s.words[root.state_globals_start + wi];
        gget(g, gid);
        lset(g, w(g, val, wi));
    }
    return val, blot_direct_types::Error.none;
}

fn storePersistRootVal(g: Generator&, f: const Fn&, root: PersistRoot, val: Val) {
    for wi in 0..(root.state_globals_len as i64) {
        let gid = g.s.words[root.state_globals_start + wi];
        lget(g, w(g, val, wi));
        gset(g, gid);
    }
}

fn zeroPersistRootGlobals(g: Generator&, root: PersistRoot) -> Error {
    let layout, lerr = g.types.layout(root.state_ty);
    if lerr != blot_direct_types::Error.none { return lerr; }
    for wi in 0..(root.state_globals_len as i64) {
        let gid = g.s.words[root.state_globals_start + wi];
        let wt = layout[wi];
        if wt == VT_f32 { f32Const(g, 0); }
        else if wt == VT_v128 {
            op(g, OP_prefix_fd);
            uleb(g, 12);
            for _ in 0..16 { op(g, 0); }
        } else { i32Const(g, 0); }
        gset(g, gid);
    }
    return blot_direct_types::Error.none;
}

// Emits `blot:kernel_clear:<name>` body: idempotent on status == 0; else sets 2,
// frees all live_owners & live_blocks & ledgers, zeroes globals, sets 0, returns 0.
fn emitClearRoot(g: Generator&, f: Fn&, root: PersistRoot) -> Error {
    let rt = g.runtime_();
    gget(g, root.status_global);
    op(g, OP_i32_eqz);
    let empty_if = open(g, f, OP_if_);
    i32Const(g, 0);
    op(g, OP_return_);
    close(g, f);
    i32Const(g, 2);
    gset(g, root.status_global);
    if root.holds_mem {
        let i = local32(g, f);
        let ptr = local32(g, f);
        let len = local32(g, f);
        let cap = local32(g, f);
        // Free live_owners.
        gget(g, root.live_owners_ptr);
        lset(g, ptr);
        gget(g, root.live_owners_len);
        lset(g, len);
        gget(g, root.live_owners_cap);
        lset(g, cap);
        i32Const(g, 0);
        lset(g, i);
        let ob = open(g, f, OP_block);
        let ol = open(g, f, OP_loop);
        lget(g, i);
        lget(g, len);
        op(g, OP_i32_ge_u);
        br(g, f, OP_br_if, ob);
        let cell = local32(g, f);
        lget(g, ptr);
        lget(g, i);
        i32Const(g, 3);
        op(g, OP_i32_shl);
        op(g, OP_i32_add);
        ltee(g, cell);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);
        lget(g, cell);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, 4);
        callf(g, rt.free_persistent);
        lget(g, i);
        i32Const(g, 1);
        op(g, OP_i32_add);
        lset(g, i);
        br(g, f, OP_br, ol);
        close(g, f);
        close(g, f);
        lget(g, cap);
        let oc_if = open(g, f, OP_if_);
        lget(g, ptr);
        lget(g, cap);
        callf(g, rt.heap_free);
        close(g, f);
        // Free live_blocks.
        gget(g, root.live_blocks_ptr);
        lset(g, ptr);
        gget(g, root.live_blocks_len);
        lset(g, len);
        gget(g, root.live_blocks_cap);
        lset(g, cap);
        i32Const(g, 0);
        lset(g, i);
        let bb = open(g, f, OP_block);
        let bl = open(g, f, OP_loop);
        lget(g, i);
        lget(g, len);
        op(g, OP_i32_ge_u);
        br(g, f, OP_br_if, bb);
        let bcell = local32(g, f);
        lget(g, ptr);
        lget(g, i);
        i32Const(g, 4);
        op(g, OP_i32_shl);
        op(g, OP_i32_add);
        ltee(g, bcell);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);
        lget(g, bcell);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, 12);
        callf(g, rt.heap_free);
        lget(g, i);
        i32Const(g, 1);
        op(g, OP_i32_add);
        lset(g, i);
        br(g, f, OP_br, bl);
        close(g, f);
        close(g, f);
        lget(g, cap);
        let bc_if = open(g, f, OP_if_);
        lget(g, ptr);
        lget(g, cap);
        callf(g, rt.heap_free);
        close(g, f);
        i32Const(g, 0); gset(g, root.live_owners_ptr);
        i32Const(g, 0); gset(g, root.live_owners_len);
        i32Const(g, 0); gset(g, root.live_owners_cap);
        i32Const(g, 0); gset(g, root.live_blocks_ptr);
        i32Const(g, 0); gset(g, root.live_blocks_len);
        i32Const(g, 0); gset(g, root.live_blocks_cap);
    }
    let zerr = zeroPersistRootGlobals(g, root);
    if zerr != blot_direct_types::Error.none { return zerr; }
    i32Const(g, 0);
    gset(g, root.status_global);
    return blot_direct_types::Error.none;
}

// Collect all memory-holding `Ty`s reachable from `root_ty` for flat iterative dispatch.
fn findCollectedTy(tys: const Ty[:], ty: Ty) -> i64 {
    for t, i in tys { if t == ty { return i; } }
    return -1;
}

recursive fn collectPersistTys(g: Generator&, ty: Ty, out: Ty[>..]&, depth: i64) -> Error {
    if depth > 64 { return blot_direct_types::Error.none; }
    let holds, herr = g.holdsMemory(ty);
    if herr != blot_direct_types::Error.none { return herr; }
    let cholds, cherr = g.contentsHoldMemory(ty);
    if cherr != blot_direct_types::Error.none { return cherr; }
    if !holds && !cholds { return blot_direct_types::Error.none; }
    if findCollectedTy(out[..], ty) >= 0 { return blot_direct_types::Error.none; }
    out.push(ty);
    let n = g.types.node(ty);
    match n.tag {
        array => {
            return collectPersistTys(g, n.a, out, depth + 1);
        },
        tuple => {
            for at in 0..(n.b as i64) {
                let err = collectPersistTys(g, g.types.words[n.a + at], out, depth + 1);
                if err != blot_direct_types::Error.none { return err; }
            }
            return blot_direct_types::Error.none;
        },
        record => {
            for idx in 0..(n.b as i64) {
                let err = collectPersistTys(g, g.types.recordField(ty, idx).ty, out, depth + 1);
                if err != blot_direct_types::Error.none { return err; }
            }
            return blot_direct_types::Error.none;
        },
        nominal => {
            let cases, cerr = g.types.variants(ty);
            if cerr != blot_direct_types::Error.none { return cerr; }
            for ci in 0..(cases.len as i64) {
                let err = collectPersistTys(g, g.types.variant_payloads[cases.payloads + ci], out, depth + 1);
                if err != blot_direct_types::Error.none { return err; }
            }
            return blot_direct_types::Error.none;
        },
        _ => { return blot_direct_types::Error.none; },
    }
}

// Helper: load owner entry address for a known valid temp slot into `entry_local`.
fn emitLoadTempEntry(g: Generator&, slot_local: u32, entry_local: u32) {
    let ot = g.runtime_().layout.owner_table;
    lget(g, slot_local);
    i32Const(g, 8);
    op(g, OP_i32_shr_u);
    i32Const(g, 2);
    op(g, OP_i32_shl);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, ot);
    lget(g, slot_local);
    i32Const(g, 255);
    op(g, OP_i32_and);
    i32Const(g, 4);
    op(g, OP_i32_shl);
    op(g, OP_i32_add);
    lset(g, entry_local);
}

// Helper: push a 16-byte worklist entry `(kind, a, b, compact_ty)`.
fn emitPushWork(g: Generator&, work_slot: u32, kind: u32, a_loc: u32, b_loc: u32, cty_id: u32, dst_tmp: u32) {
    let rt = g.runtime_();
    lget(g, work_slot);
    i32Const(g, 16);
    callf(g, rt.scratch_push);
    ltee(g, dst_tmp);
    i32Const(g, kind);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
    lget(g, dst_tmp);
    lget(g, a_loc);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, 4);
    lget(g, dst_tmp);
    lget(g, b_loc);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, 8);
    lget(g, dst_tmp);
    i32Const(g, cty_id);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, 12);
}

// Helper: push an 8-byte fixup `(patch_addr, val)` onto a fixup vector.
fn emitPushFixup(g: Generator&, vec_slot: u32, addr_loc: u32, val_loc: u32, dst_tmp: u32) {
    let rt = g.runtime_();
    lget(g, vec_slot);
    i32Const(g, 8);
    callf(g, rt.scratch_push);
    ltee(g, dst_tmp);
    lget(g, addr_loc);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
    lget(g, dst_tmp);
    lget(g, val_loc);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, 4);
}

// Emits a child field push from flat container at `base_addr + offset`.
fn emitPushFlatChild(g: Generator&, f: Fn&, work_slot: u32, base_addr: u32, offset: u32, child_ty: Ty, tys: const Ty[:], tmp_a: u32, tmp_b: u32, dst_tmp: u32) -> Error {
    let cidx = findCollectedTy(tys, child_ty);
    if cidx < 0 { return blot_direct_types::Error.none; }
    let is_rec, rerr = g.types.isRecursive(child_ty);
    if rerr != blot_direct_types::Error.none { return rerr; }
    lget(g, base_addr);
    if offset != 0 {
        i32Const(g, offset);
        op(g, OP_i32_add);
    }
    lset(g, tmp_a);
    if is_rec {
        lget(g, tmp_a);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);
        lset(g, tmp_b);
        emitPushWork(g, work_slot, 1, tmp_a, tmp_b, cidx as u32, dst_tmp);
    } else {
        i32Const(g, 0);
        lset(g, tmp_b);
        emitPushWork(g, work_slot, 0, tmp_a, tmp_b, cidx as u32, dst_tmp);
    }
    return blot_direct_types::Error.none;
}

fn emitCommitReplyPin(
    g: Generator&,
    f: Fn&,
    has_reply_pin: bool,
    reply_pin_slot: u32,
    reply_base: u32,
    reply_cap: u32,
    reply_bytes: u32,
) {
    if !has_reply_pin { return; }
    let rt = g.runtime_();
    lget(g, reply_pin_slot);
    callf(g, rt.detach_temp_slot);
    gget(g, rt.transport_cap);
    let old_t = open(g, f, OP_if_);
    gget(g, rt.transport_base);
    gget(g, rt.transport_cap);
    callf(g, rt.free_transport);
    close(g, f);
    lget(g, reply_base);
    gset(g, rt.transport_base);
    lget(g, reply_cap);
    gset(g, rt.transport_cap);
    lget(g, reply_base);
    lget(g, reply_bytes);
    op(g, OP_i32_add);
    gset(g, rt.transport_top);
}
// Collect flat byte offsets of every plain-element `Tag.array` handle inside a
// non-recursive boxed root (e.g. EcsWorld). Returns false if any nested-owner
// array, multi-variant sum, view/ref/link, closure, or >32 owners exist.
recursive fn collectPersistFlatArrayOffsets(g: Generator&, ty: Ty, base_off: u32, out: u32[32]&, out_len: i64&) -> bool, Error {
    let holds, error = g.contentsHoldMemory(ty);
    if error != blot_direct_types::Error.none { return false, error; }
    if !holds { return true, blot_direct_types::Error.none; }
    let rec, rerr = g.types.isRecursive(ty);
    if rerr != blot_direct_types::Error.none { return false, rerr; }
    if rec { return false, blot_direct_types::Error.none; }
    let n = g.types.node(ty);
    match n.tag {
        array => {
            let elem_holds, herr = g.contentsHoldMemory(n.a);
            if herr != blot_direct_types::Error.none { return false, herr; }
            if elem_holds || out_len >= 32 { return false, blot_direct_types::Error.none; }
            out[out_len] = base_off;
            out_len += 1;
            return true, blot_direct_types::Error.none;
        },
        tuple => {
            var off = base_off;
            for index in 0..(n.b as i64) {
                let item = g.types.words[n.a + index];
                let ok, oerr = collectPersistFlatArrayOffsets(g, item, off, out, out_len);
                if oerr != blot_direct_types::Error.none { return false, oerr; }
                if !ok { return false, blot_direct_types::Error.none; }
                let bytes, berr = g.types.flatBytes(item);
                if berr != blot_direct_types::Error.none { return false, berr; }
                off += bytes;
            }
            return true, blot_direct_types::Error.none;
        },
        record => {
            var off = base_off;
            for index in 0..(n.b as i64) {
                let field = g.types.recordField(ty, index).ty;
                let ok, oerr = collectPersistFlatArrayOffsets(g, field, off, out, out_len);
                if oerr != blot_direct_types::Error.none { return false, oerr; }
                if !ok { return false, blot_direct_types::Error.none; }
                let bytes, berr = g.types.flatBytes(field);
                if berr != blot_direct_types::Error.none { return false, berr; }
                off += bytes;
            }
            return true, blot_direct_types::Error.none;
        },
        nominal => {
            let cases, verr = g.types.variants(ty);
            if verr != blot_direct_types::Error.none { return false, verr; }
            if cases.len != 1 { return false, blot_direct_types::Error.none; }
            let payload = g.types.variant_payloads[cases.payloads];
            return collectPersistFlatArrayOffsets(g, payload, base_off, out, out_len);
        },
        _ => { return false, blot_direct_types::Error.none; },
    }
}
// Collect word indices of every plain-element `Tag.array` handle inside an
// unboxed root (e.g. SoaWorld).
recursive fn collectPersistRegArrayWords(g: Generator&, ty: Ty, base_word: u32, out: u32[32]&, out_len: i64&) -> bool, Error {
    let holds, error = g.contentsHoldMemory(ty);
    if error != blot_direct_types::Error.none { return false, error; }
    if !holds { return true, blot_direct_types::Error.none; }
    let boxed, berr = g.types.boxed(ty);
    if berr != blot_direct_types::Error.none { return false, berr; }
    if boxed { return false, blot_direct_types::Error.none; }
    let n = g.types.node(ty);
    match n.tag {
        array => {
            let elem_holds, herr = g.contentsHoldMemory(n.a);
            if herr != blot_direct_types::Error.none { return false, herr; }
            if elem_holds || out_len >= 32 { return false, blot_direct_types::Error.none; }
            out[out_len] = base_word;
            out_len += 1;
            return true, blot_direct_types::Error.none;
        },
        tuple => {
            var cur = base_word;
            for index in 0..(n.b as i64) {
                let item = g.types.words[n.a + index];
                let ok, oerr = collectPersistRegArrayWords(g, item, cur, out, out_len);
                if oerr != blot_direct_types::Error.none { return false, oerr; }
                if !ok { return false, blot_direct_types::Error.none; }
                let layout, lerr = g.types.layout(item);
                if lerr != blot_direct_types::Error.none { return false, lerr; }
                cur += layout.len as u32;
            }
            return true, blot_direct_types::Error.none;
        },
        record => {
            var cur = base_word;
            for index in 0..(n.b as i64) {
                let field = g.types.recordField(ty, index).ty;
                let ok, oerr = collectPersistRegArrayWords(g, field, cur, out, out_len);
                if oerr != blot_direct_types::Error.none { return false, oerr; }
                if !ok { return false, blot_direct_types::Error.none; }
                let layout, lerr = g.types.layout(field);
                if lerr != blot_direct_types::Error.none { return false, lerr; }
                cur += layout.len as u32;
            }
            return true, blot_direct_types::Error.none;
        },
        nominal => {
            let cases, verr = g.types.variants(ty);
            if verr != blot_direct_types::Error.none { return false, verr; }
            if cases.len != 1 { return false, blot_direct_types::Error.none; }
            let payload = g.types.variant_payloads[cases.payloads];
            return collectPersistRegArrayWords(g, payload, base_word, out, out_len);
        },
        _ => { return false, blot_direct_types::Error.none; },
    }
}
// Emits complete 100% iterative two-phase staging for `root` given `next_val`.
// When `has_reply_pin` is true (proc_step array/multi-word reply), commits the
// transport-pinned reply buffer into `rt.transport_*` during Phase 2 before `releaseEntry()`.
// When `is_step` is true and every plain-element array handle in `next_val` matches
// the already-committed persistent root handle set unchanged, commits in O(fields)
// with zero scratch vector / hashmap allocations.
// Ends with `releaseEntry(g)` while `status == 2` and sets `status = 1` as final step.
fn emitStageRoot(
    g: Generator&,
    f: Fn&,
    root: PersistRoot,
    next_val: Val,
    has_reply_pin: bool,
    reply_pin_slot: u32,
    reply_base: u32,
    reply_cap: u32,
    reply_bytes: u32,
    is_step: bool = false,
) -> Error {
    let rt = g.runtime_();
    // Fast path: pure scalar state with zero memory ownership.
    if !root.holds_mem {
        i32Const(g, 2);
        gset(g, root.status_global);
        emitCommitReplyPin(g, f, has_reply_pin, reply_pin_slot, reply_base, reply_cap, reply_bytes);
        storePersistRootVal(g, f, root, next_val);
        releaseEntry(g);
        i32Const(g, 1);
        gset(g, root.status_global);
        return blot_direct_types::Error.none;
    }

    // Zero-allocation fast-path commit for `blot:proc_step` when every plain-element
    // array handle in `next_val` is bit-identical to the currently committed persistent root!
    var has_fast_branch = false;
    if is_step {
        let root_boxed, rberr = isBoxed(g, f, root.state_ty, 0);
        if rberr != blot_direct_types::Error.none { return rberr; }
        if !root_boxed {
            var owner_words: u32[32] = [0; 32];
            var owner_count: i64 = 0;
            let fok, ferr = collectPersistRegArrayWords(g, root.state_ty, 0, owner_words, owner_count);
            if ferr != blot_direct_types::Error.none { return ferr; }
            if fok && owner_count > 0 {
                let fast_ok = local32(g, f);
                gget(g, root.live_blocks_len);
                op(g, OP_i32_eqz);
                lset(g, fast_ok);
                for oi in 0..owner_count {
                    let wi = owner_words[oi] as i64;
                    lget(g, fast_ok);
                    lget(g, w(g, next_val, wi));
                    gget(g, g.s.words[root.state_globals_start + wi]);
                    op(g, OP_i32_eq);
                    op(g, OP_i32_and);
                    lget(g, w(g, next_val, wi + 1));
                    gget(g, g.s.words[root.state_globals_start + wi + 1]);
                    op(g, OP_i32_eq);
                    op(g, OP_i32_and);
                    lset(g, fast_ok);
                }
                lget(g, fast_ok);
                let fast_if = open(g, f, OP_if_);
                emitCommitReplyPin(g, f, has_reply_pin, reply_pin_slot, reply_base, reply_cap, reply_bytes);
                storePersistRootVal(g, f, root, next_val);
                releaseEntry(g);
                i32Const(g, 1);
                gset(g, root.status_global);
                popCheckedArraysAt(f, fast_if);
                op(g, OP_else_);
                has_fast_branch = true;
            }
        } else {
            var owner_offs: u32[32] = [0; 32];
            var owner_count: i64 = 0;
            let fok, ferr = collectPersistFlatArrayOffsets(g, root.state_ty, 0, owner_offs, owner_count);
            if ferr != blot_direct_types::Error.none { return ferr; }
            if fok && owner_count > 0 && root.state_globals_len == 1 {
                let logical_bytes, berr = blockBytes(g, f, root.state_ty, 0);
                if berr != blot_direct_types::Error.none { return berr; }
                let old_ptr = local32(g, f);
                let new_ptr = w(g, next_val, 0);
                gget(g, g.s.words[root.state_globals_start]);
                lset(g, old_ptr);
                let fast_ok = local32(g, f);
                gget(g, root.live_blocks_len);
                i32Const(g, 1);
                op(g, OP_i32_eq);
                lget(g, old_ptr);
                i32Const(g, 0);
                op(g, OP_i32_ne);
                op(g, OP_i32_and);
                lget(g, new_ptr);
                i32Const(g, 0);
                op(g, OP_i32_ne);
                op(g, OP_i32_and);
                ltee(g, fast_ok);
                let chk_if = open(g, f, OP_if_);
                for oi in 0..owner_count {
                    let off = owner_offs[oi];
                    lget(g, fast_ok);
                    lget(g, new_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, off);
                    lget(g, old_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, off);
                    op(g, OP_i32_eq);
                    op(g, OP_i32_and);
                    lget(g, new_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, off + 4);
                    lget(g, old_ptr); op(g, OP_i32_load); uleb(g, 2); uleb(g, off + 4);
                    op(g, OP_i32_eq);
                    op(g, OP_i32_and);
                    lset(g, fast_ok);
                }
                close(g, f);
                lget(g, fast_ok);
                let fast_if = open(g, f, OP_if_);
                lget(g, new_ptr);
                lget(g, old_ptr);
                op(g, OP_i32_ne);
                let cp_if = open(g, f, OP_if_);
                memoryCopy(g, old_ptr, 0, new_ptr, logical_bytes);
                close(g, f);
                emitCommitReplyPin(g, f, has_reply_pin, reply_pin_slot, reply_base, reply_cap, reply_bytes);
                releaseEntry(g);
                i32Const(g, 1);
                gset(g, root.status_global);
                popCheckedArraysAt(f, fast_if);
                op(g, OP_else_);
                has_fast_branch = true;
            }
        }
    }

    // Collect every memory-holding Ty reachable from root.state_ty.
    var tys: Ty[>..] = [];
    let cerr = collectPersistTys(g, root.state_ty, tys, 0);
    if cerr != blot_direct_types::Error.none { return cerr; }
    assert(tys.len > 0 && tys[0] == root.state_ty);

    // Compute root shadow buffer byte size.
    let layout, lerr = g.types.layout(root.state_ty);
    if lerr != blot_direct_types::Error.none { return lerr; }
    var root_bytes: u32 = 0;
    for wt in layout { root_bytes += wordBytes(wt); }
    var root_alloc_bytes = root_bytes;
    if root_alloc_bytes < 16 { root_alloc_bytes = 16; }

    // === PHASE 1: 100% iterative packing, traversal & fixup preflight (ZERO persistent mutation!) ===
    let root_buf = local32(g, f);
    i32Const(g, root_alloc_bytes);
    i32Const(g, 0);
    callf(g, rt.open_heap);
    op(g, OP_drop);
    lset(g, root_buf);
    op(g, OP_drop);
    op(g, OP_drop);
    storeAt(g, f, root_buf, 0, next_val);

    // Open all heap-backed scratch tables & hash maps (automatically freed by releaseEntry on trap!).
    let work_slot = local32(g, f);
    let steal_slot = local32(g, f);
    let ret_owners_slot = local32(g, f);
    let ret_blocks_slot = local32(g, f);
    let new_blocks_slot = local32(g, f);
    let owner_fix_slot = local32(g, f);
    let box_fix_slot = local32(g, f);
    let old_owners_map = local32(g, f);
    let old_blocks_map = local32(g, f);
    let ret_owners_map = local32(g, f);
    let ret_blocks_map = local32(g, f);
    let temp_owner_map = local32(g, f);
    let visited_block_map = local32(g, f);

    i32Const(g, 256); callf(g, rt.open_vec); lset(g, work_slot);
    i32Const(g, 256); callf(g, rt.open_vec); lset(g, steal_slot);
    i32Const(g, 128); callf(g, rt.open_vec); lset(g, ret_owners_slot);
    i32Const(g, 128); callf(g, rt.open_vec); lset(g, ret_blocks_slot);
    i32Const(g, 128); callf(g, rt.open_vec); lset(g, new_blocks_slot);
    i32Const(g, 128); callf(g, rt.open_vec); lset(g, owner_fix_slot);
    i32Const(g, 128); callf(g, rt.open_vec); lset(g, box_fix_slot);
    callf(g, rt.open_hmap); lset(g, old_owners_map);
    callf(g, rt.open_hmap); lset(g, old_blocks_map);
    callf(g, rt.open_hmap); lset(g, ret_owners_map);
    callf(g, rt.open_hmap); lset(g, ret_blocks_map);
    callf(g, rt.open_hmap); lset(g, temp_owner_map);
    callf(g, rt.open_hmap); lset(g, visited_block_map);

    // Populate old_owners_map & old_blocks_map in O(N) for O(1) membership checks.
    let li = local32(g, f);
    let lptr = local32(g, f);
    let llen = local32(g, f);
    let lcell = local32(g, f);
    gget(g, root.live_owners_ptr); lset(g, lptr);
    gget(g, root.live_owners_len); lset(g, llen);
    i32Const(g, 0); lset(g, li);
    {
        let blk_end = open(g, f, OP_block);
        let lp = open(g, f, OP_loop);
        lget(g, li); lget(g, llen); op(g, OP_i32_ge_u); br(g, f, OP_br_if, blk_end);
        lget(g, lptr); lget(g, li); i32Const(g, 3); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, lcell);
        lget(g, old_owners_map);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 4);
        i32Const(g, 0);
        i32Const(g, 1);
        callf(g, rt.hmap_put);
        lget(g, li); i32Const(g, 1); op(g, OP_i32_add); lset(g, li);
        br(g, f, OP_br, lp);
        close(g, f);
        close(g, f);
    }
    gget(g, root.live_blocks_ptr); lset(g, lptr);
    gget(g, root.live_blocks_len); lset(g, llen);
    i32Const(g, 0); lset(g, li);
    {
        let blk_end = open(g, f, OP_block);
        let lp = open(g, f, OP_loop);
        lget(g, li); lget(g, llen); op(g, OP_i32_ge_u); br(g, f, OP_br_if, blk_end);
        lget(g, lptr); lget(g, li); i32Const(g, 4); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, lcell);
        lget(g, old_blocks_map);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 4);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 8);
        lget(g, li);
        callf(g, rt.hmap_put);
        lget(g, li); i32Const(g, 1); op(g, OP_i32_add); lset(g, li);
        br(g, f, OP_br, lp);
        close(g, f);
        close(g, f);
    }

    // Seed initial worklist item from root_buf.
    let tmp_a = local32(g, f);
    let tmp_b = local32(g, f);
    let dst_tmp = local32(g, f);
    let root_boxed, rberr = isBoxed(g, f, root.state_ty, 0);
    if rberr != blot_direct_types::Error.none { return rberr; }
    if root_boxed {
        lget(g, root_buf); lset(g, tmp_a);
        lget(g, root_buf); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0); lset(g, tmp_b);
        emitPushWork(g, work_slot, 1, tmp_a, tmp_b, 0, dst_tmp);
    } else {
        lget(g, root_buf); lset(g, tmp_a);
        i32Const(g, 0); lset(g, tmp_b);
        emitPushWork(g, work_slot, 0, tmp_a, tmp_b, 0, dst_tmp);
    }

    // Locals for the single flat iterative worklist loop.
    let w_entry = local32(g, f);
    let w_len = local32(g, f);
    let w_cell = local32(g, f);
    let w_kind = local32(g, f);
    let w_a = local32(g, f);
    let w_b = local32(g, f);
    let w_ty = local32(g, f);
    let o_slot = local32(g, f);
    let o_gen = local32(g, f);
    let o_entry = local32(g, f);
    let o_base = local32(g, f);
    let o_len = local32(g, f);
    let o_cap = local32(g, f);
    let m_val = local32(g, f);
    let m_found = local32(g, f);
    let steal_idx = local32(g, f);
    let pin_slot = local32(g, f);
    let dst_base = local32(g, f);
    let dst_cap = local32(g, f);
    let elem_i = local32(g, f);
    let elem_addr = local32(g, f);
    let vtag_loc = local32(g, f);
    let box_ok = local32(g, f);
    let box_end = local32(g, f);

    // Main iterative worklist loop (`while worklist.len > 0`).
    {
        let w_exit = open(g, f, OP_block);
        let w_loop = open(g, f, OP_loop);
        emitLoadTempEntry(g, work_slot, w_entry);
        lget(g, w_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
        ltee(g, w_len);
        op(g, OP_i32_eqz);
        br(g, f, OP_br_if, w_exit);
        // Pop last work item.
        lget(g, w_len); i32Const(g, 1); op(g, OP_i32_sub); lset(g, w_len);
        lget(g, w_entry); lget(g, w_len); op(g, OP_i32_store); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
        lget(g, w_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
        lget(g, w_len); i32Const(g, 4); op(g, OP_i32_shl); op(g, OP_i32_add);
        ltee(g, w_cell);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, 0); lset(g, w_kind);
        lget(g, w_cell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 4); lset(g, w_a);
        lget(g, w_cell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 8); lset(g, w_b);
        lget(g, w_cell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 12); lset(g, w_ty);

        lget(g, w_kind);
        op(g, OP_i32_eqz);
        let kind_if = open(g, f, OP_if_);
        // --- kind == 0: InlineRow { addr = w_a, compact_ty = w_ty } ---
        for t, ti in tys {
            lget(g, w_ty);
            i32Const(g, ti as u32);
            op(g, OP_i32_eq);
            let t_if = open(g, f, OP_if_);
            let tn = g.types.node(t);
            match tn.tag {
                array => {
                    let elem_ty = tn.a;
                    let elem_step, serr = stride(g, f, elem_ty, 0);
                    if serr != blot_direct_types::Error.none { return serr; }
                    let elem_cidx = findCollectedTy(tys[..], elem_ty);
                    // Read (slot, gen) at w_a and check handle.
                    lget(g, w_a); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0); lset(g, o_slot);
                    lget(g, w_a); op(g, OP_i32_load); uleb(g, 2); uleb(g, 4); lset(g, o_gen);
                    lget(g, o_slot); lget(g, o_gen); callf(g, rt.check); ltee(g, o_entry);
                    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base); lset(g, o_base);
                    lget(g, o_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length); lset(g, o_len);
                    lget(g, o_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_capacity); lset(g, o_cap);

                    // Branch: persistent (>= persistent_split) vs temporary (< persistent_split).
                    lget(g, o_slot);
                    i32Const(g, rt.layout.persistent_split);
                    op(g, OP_i32_ge_u);
                    let p_if = open(g, f, OP_if_);
                    // Persistent owner: skip static_pool_flag, else verify in old_owners_map and retain.
                    lget(g, o_cap);
                    i32Const(g, blot_direct_runtime::static_pool_flag);
                    op(g, OP_i32_and);
                    op(g, OP_i32_eqz);
                    let non_static_if = open(g, f, OP_if_);
                    lget(g, old_owners_map); lget(g, o_slot); lget(g, o_gen); i32Const(g, 0);
                    callf(g, rt.hmap_get);
                    lset(g, m_found); op(g, OP_drop);
                    lget(g, m_found); op(g, OP_i32_eqz); trap(g, f);
                    lget(g, ret_owners_map); lget(g, o_slot); lget(g, o_gen); i32Const(g, 0);
                    callf(g, rt.hmap_get);
                    lset(g, m_found); op(g, OP_drop);
                    lget(g, m_found); op(g, OP_i32_eqz);
                    let first_ret_if = open(g, f, OP_if_);
                    lget(g, ret_owners_map); lget(g, o_slot); lget(g, o_gen); i32Const(g, 0); i32Const(g, 1);
                    callf(g, rt.hmap_put);
                    emitPushFixup(g, ret_owners_slot, o_slot, o_gen, dst_tmp);
                    if elem_cidx >= 0 {
                        // Traverse retained persistent elements IN PLACE (Phase 1 never writes; fixups queue!).
                        i32Const(g, 0); lset(g, elem_i);
                        let eb = open(g, f, OP_block);
                        let el = open(g, f, OP_loop);
                        lget(g, elem_i); lget(g, o_len); op(g, OP_i32_ge_u); br(g, f, OP_br_if, eb);
                        lget(g, o_base); lget(g, elem_i); i32Const(g, elem_step); op(g, OP_i32_mul); op(g, OP_i32_add); lset(g, elem_addr);
                        let perr = emitPushFlatChild(g, f, work_slot, elem_addr, 0, elem_ty, tys[..], tmp_a, tmp_b, dst_tmp);
                        if perr != blot_direct_types::Error.none { return perr; }
                        lget(g, elem_i); i32Const(g, 1); op(g, OP_i32_add); lset(g, elem_i);
                        br(g, f, OP_br, el);
                        close(g, f);
                        close(g, f);
                    }
                    close(g, f); // first_ret_if
                    close(g, f); // non_static_if
                    op(g, OP_else_);
                    // Temporary owner: DAG-dedup in temp_owner_map.
                    lget(g, temp_owner_map); lget(g, o_slot); i32Const(g, 0); i32Const(g, 0);
                    callf(g, rt.hmap_get);
                    lset(g, m_found); lset(g, m_val);
                    lget(g, m_found);
                    let seen_t_if = open(g, f, OP_if_);
                    lget(g, m_val); i32Const(g, 1); op(g, OP_i32_sub); lset(g, steal_idx);
                    emitPushFixup(g, owner_fix_slot, w_a, steal_idx, dst_tmp);
                    op(g, OP_else_);
                    // New temp owner: allocate next steal_idx.
                    emitLoadTempEntry(g, steal_slot, dst_tmp);
                    lget(g, dst_tmp); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length); lset(g, steal_idx);
                    lget(g, temp_owner_map); lget(g, o_slot); i32Const(g, 0); i32Const(g, 0);
                    lget(g, steal_idx); i32Const(g, 1); op(g, OP_i32_add);
                    callf(g, rt.hmap_put);
                    emitPushFixup(g, owner_fix_slot, w_a, steal_idx, dst_tmp);
                    // Classify: Empty (len == 0) vs StealHeap (heap_flag != 0) vs CopiedHeap (stack/transport).
                    lget(g, o_len); op(g, OP_i32_eqz);
                    let empty_o_if = open(g, f, OP_if_);
                    // Empty: steal_kind = 0, src_slot = o_slot (NOT detached in Phase 2!).
                    lget(g, steal_slot); i32Const(g, 32); callf(g, rt.scratch_push); lset(g, dst_tmp);
                    lget(g, dst_tmp); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
                    lget(g, dst_tmp); lget(g, o_slot); op(g, OP_i32_store); uleb(g, 2); uleb(g, 4);
                    lget(g, dst_tmp); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, 8);
                    lget(g, dst_tmp); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, 12);
                    lget(g, dst_tmp); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, 16);
                    lget(g, dst_tmp); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, 20);
                    op(g, OP_else_);
                    lget(g, o_cap); i32Const(g, blot_direct_runtime::heap_flag); op(g, OP_i32_and);
                    let heap_o_if = open(g, f, OP_if_);
                    // StealHeap: steal_kind = 1, src_slot = o_slot, dst_base = o_base.
                    lget(g, steal_slot); i32Const(g, 32); callf(g, rt.scratch_push); lset(g, dst_tmp);
                    lget(g, dst_tmp); i32Const(g, 1); op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
                    lget(g, dst_tmp); lget(g, o_slot); op(g, OP_i32_store); uleb(g, 2); uleb(g, 4);
                    lget(g, dst_tmp); lget(g, o_base); op(g, OP_i32_store); uleb(g, 2); uleb(g, 8);
                    lget(g, dst_tmp); lget(g, o_len); op(g, OP_i32_store); uleb(g, 2); uleb(g, 12);
                    lget(g, dst_tmp); lget(g, o_cap); i32Const(g, blot_direct_runtime::capacity_mask); op(g, OP_i32_and); op(g, OP_i32_store); uleb(g, 2); uleb(g, 16);
                    lget(g, dst_tmp); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, 20);
                    lget(g, o_base); lset(g, dst_base);
                    op(g, OP_else_);
                    // CopiedHeap: allocate via rt.open_heap, copy raw bytes, queue steal_kind = 2 with pin_slot!
                    let copy_bytes = emitScaledBytes(g, f, o_len, elem_step);
                    lget(g, copy_bytes); lget(g, o_len); callf(g, rt.open_heap);
                    lset(g, dst_cap); lset(g, dst_base); op(g, OP_drop); lset(g, pin_slot);
                    lget(g, dst_base); lget(g, o_base); lget(g, copy_bytes); memoryCopyOp(g);
                    lget(g, steal_slot); i32Const(g, 32); callf(g, rt.scratch_push); lset(g, dst_tmp);
                    lget(g, dst_tmp); i32Const(g, 2); op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
                    lget(g, dst_tmp); lget(g, pin_slot); op(g, OP_i32_store); uleb(g, 2); uleb(g, 4);
                    lget(g, dst_tmp); lget(g, dst_base); op(g, OP_i32_store); uleb(g, 2); uleb(g, 8);
                    lget(g, dst_tmp); lget(g, o_len); op(g, OP_i32_store); uleb(g, 2); uleb(g, 12);
                    lget(g, dst_tmp); lget(g, dst_cap); op(g, OP_i32_store); uleb(g, 2); uleb(g, 16);
                    lget(g, dst_tmp); i32Const(g, 0); op(g, OP_i32_store); uleb(g, 2); uleb(g, 20);
                    close(g, f); // heap_o_if
                    if elem_cidx >= 0 {
                        // Push InlineRow strictly targeting destination buffer `dst_base`!
                        i32Const(g, 0); lset(g, elem_i);
                        let eb2 = open(g, f, OP_block);
                        let el2 = open(g, f, OP_loop);
                        lget(g, elem_i); lget(g, o_len); op(g, OP_i32_ge_u); br(g, f, OP_br_if, eb2);
                        lget(g, dst_base); lget(g, elem_i); i32Const(g, elem_step); op(g, OP_i32_mul); op(g, OP_i32_add); lset(g, elem_addr);
                        let perr = emitPushFlatChild(g, f, work_slot, elem_addr, 0, elem_ty, tys[..], tmp_a, tmp_b, dst_tmp);
                        if perr != blot_direct_types::Error.none { return perr; }
                        lget(g, elem_i); i32Const(g, 1); op(g, OP_i32_add); lset(g, elem_i);
                        br(g, f, OP_br, el2);
                        close(g, f);
                        close(g, f);
                    }
                    close(g, f); // empty_o_if
                    close(g, f); // seen_t_if
                    close(g, f); // p_if
                },
                tuple => {
                    var off: u32 = 0;
                    for at in 0..(tn.b as i64) {
                        let item_ty = g.types.words[tn.a + at];
                        let perr = emitPushFlatChild(g, f, work_slot, w_a, off, item_ty, tys[..], tmp_a, tmp_b, dst_tmp);
                        if perr != blot_direct_types::Error.none { return perr; }
                        let fb, ferr = flatBytes(g, f, item_ty, 0);
                        if ferr != blot_direct_types::Error.none { return ferr; }
                        off += fb;
                    }
                },
                record => {
                    var off: u32 = 0;
                    for idx in 0..(tn.b as i64) {
                        let field_ty = g.types.recordField(t, idx).ty;
                        let perr = emitPushFlatChild(g, f, work_slot, w_a, off, field_ty, tys[..], tmp_a, tmp_b, dst_tmp);
                        if perr != blot_direct_types::Error.none { return perr; }
                        let fb, ferr = flatBytes(g, f, field_ty, 0);
                        if ferr != blot_direct_types::Error.none { return ferr; }
                        off += fb;
                    }
                },
                nominal => {
                    let cases, cerr = g.types.variants(t);
                    if cerr != blot_direct_types::Error.none { return cerr; }
                    if cases.len == 1 {
                        let perr = emitPushFlatChild(g, f, work_slot, w_a, 0, g.types.variant_payloads[cases.payloads], tys[..], tmp_a, tmp_b, dst_tmp);
                        if perr != blot_direct_types::Error.none { return perr; }
                    } else if cases.len > 1 {
                        lget(g, w_a); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0); lset(g, vtag_loc);
                        for ci in 0..(cases.len as i64) {
                            let pty = g.types.variant_payloads[cases.payloads + ci];
                            if findCollectedTy(tys[..], pty) < 0 { continue; }
                            lget(g, vtag_loc);
                            i32Const(g, g.types.variant_tags[cases.tags + ci]);
                            op(g, OP_i32_eq);
                            let cif = open(g, f, OP_if_);
                            let perr = emitPushFlatChild(g, f, work_slot, w_a, 4, pty, tys[..], tmp_a, tmp_b, dst_tmp);
                            if perr != blot_direct_types::Error.none { return perr; }
                            close(g, f);
                        }
                    }
                },
                _ => {},
            }
            close(g, f); // t_if
        }
        op(g, OP_else_);
        // --- kind == 1: BoxPtr { patch_addr = w_a, ptr = w_b, compact_ty = w_ty } ---
        for t, ti in tys {
            let t_boxed, tberr = isBoxed(g, f, t, 0);
            if tberr != blot_direct_types::Error.none { return tberr; }
            if !t_boxed { continue; }
            let is_rec, rerr = g.types.isRecursive(t);
            if rerr != blot_direct_types::Error.none { return rerr; }
            let logical_bytes, berr = blockBytes(g, f, t, 0);
            if berr != blot_direct_types::Error.none { return berr; }
            lget(g, w_ty);
            i32Const(g, ti as u32);
            op(g, OP_i32_eq);
            let b_if = open(g, f, OP_if_);
            // Guard against null pointer (trap if ptr == 0).
            lget(g, w_b); op(g, OP_i32_eqz); trap(g, f);
            // Step 0: visited_block_map lookup by (ptr, logical_bytes, ty_id).
            lget(g, visited_block_map); lget(g, w_b); i32Const(g, logical_bytes); i32Const(g, t);
            callf(g, rt.hmap_get);
            lset(g, m_found); lset(g, m_val);
            lget(g, m_found);
            let vis_if = open(g, f, OP_if_);
            lget(g, m_val); lget(g, w_b); op(g, OP_i32_ne);
            let fix_if = open(g, f, OP_if_);
            emitPushFixup(g, box_fix_slot, w_a, m_val, dst_tmp);
            close(g, f);
            op(g, OP_else_);
            // Step 1: exact (ptr, logical_bytes, ty_id) match in static_blocks.
            i32Const(g, 0); lset(g, box_ok);
            gget(g, rt.static_blocks_ptr); lset(g, lptr);
            gget(g, rt.static_blocks_len); lset(g, llen);
            i32Const(g, 0); lset(g, li);
            {
                let sb = open(g, f, OP_block);
                let sl = open(g, f, OP_loop);
                lget(g, li); lget(g, llen); op(g, OP_i32_ge_u); br(g, f, OP_br_if, sb);
                lget(g, lptr); lget(g, li); i32Const(g, 12); op(g, OP_i32_mul); op(g, OP_i32_add); lset(g, lcell);
                lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0); lget(g, w_b); op(g, OP_i32_eq);
                lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 4); i32Const(g, logical_bytes); op(g, OP_i32_eq); op(g, OP_i32_and);
                lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 8); i32Const(g, t); op(g, OP_i32_eq); op(g, OP_i32_and);
                let sm = open(g, f, OP_if_);
                i32Const(g, 1); lset(g, box_ok);
                br(g, f, OP_br, sb);
                close(g, f);
                lget(g, li); i32Const(g, 1); op(g, OP_i32_add); lset(g, li);
                br(g, f, OP_br, sl);
                close(g, f);
                close(g, f);
            }
            lget(g, box_ok);
            let s_hit = open(g, f, OP_if_);
            lget(g, visited_block_map); lget(g, w_b); i32Const(g, logical_bytes); i32Const(g, t); lget(g, w_b);
            callf(g, rt.hmap_put);
            op(g, OP_else_);
            // Step 2: exact (ptr, logical_bytes, ty_id) match in old_blocks_map (BOTH recursive AND wide copiedBox!).
            lget(g, old_blocks_map); lget(g, w_b); i32Const(g, logical_bytes); i32Const(g, t);
            callf(g, rt.hmap_get);
            lset(g, m_found); lset(g, m_val);
            lget(g, m_found);
            let old_hit = open(g, f, OP_if_);
            lget(g, visited_block_map); lget(g, w_b); i32Const(g, logical_bytes); i32Const(g, t); lget(g, w_b);
            callf(g, rt.hmap_put);
            lget(g, ret_blocks_map); lget(g, w_b); i32Const(g, logical_bytes); i32Const(g, t);
            callf(g, rt.hmap_get);
            lset(g, m_found); op(g, OP_drop);
            lget(g, m_found); op(g, OP_i32_eqz);
            let first_rb = open(g, f, OP_if_);
            lget(g, ret_blocks_map); lget(g, w_b); i32Const(g, logical_bytes); i32Const(g, t); i32Const(g, 1);
            callf(g, rt.hmap_put);
            // Copy exact 4-word (addr, logical_bytes, ty_id, actual_cap) entry from old_blocks[m_val].
            gget(g, root.live_blocks_ptr); lget(g, m_val); i32Const(g, 4); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, lcell);
            lget(g, ret_blocks_slot); i32Const(g, 16); callf(g, rt.scratch_push); lset(g, dst_tmp);
            lget(g, dst_tmp); lget(g, lcell); i32Const(g, 16); memoryCopyOp(g);
            // Push InlineRow { ptr, compact_ty } so nested owners/boxes inside retained wide/recursive boxes stay retained!
            i32Const(g, 0); lset(g, tmp_b);
            emitPushWork(g, work_slot, 0, w_b, tmp_b, ti as u32, dst_tmp);
            close(g, f); // first_rb
            op(g, OP_else_);
            // Step 3: Validate full range [ptr, ptr + logical_bytes) and copy onto rt.heap.
            lget(g, w_b); i32Const(g, logical_bytes); op(g, OP_i32_add); ltee(g, box_end);
            lget(g, w_b); op(g, OP_i32_lt_u); trap(g, f);
            lget(g, w_b); i32Const(g, logical_bytes); callf(g, rt.is_stack_range); lset(g, box_ok);
            if !is_rec {
                // Non-recursive copiedBox may also be an interior projection of old_blocks or static_blocks!
                lget(g, box_ok); op(g, OP_i32_eqz);
                let chk_old = open(g, f, OP_if_);
                gget(g, root.live_blocks_ptr); lset(g, lptr);
                gget(g, root.live_blocks_len); lset(g, llen);
                i32Const(g, 0); lset(g, li);
                let ob2 = open(g, f, OP_block);
                let ol2 = open(g, f, OP_loop);
                lget(g, li); lget(g, llen); op(g, OP_i32_ge_u); br(g, f, OP_br_if, ob2);
                lget(g, lptr); lget(g, li); i32Const(g, 4); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, lcell);
                lget(g, w_b); lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0); op(g, OP_i32_ge_u);
                lget(g, box_end);
                lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);
                lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 4);
                op(g, OP_i32_add);
                op(g, OP_i32_le_u);
                op(g, OP_i32_and);
                let om = open(g, f, OP_if_);
                i32Const(g, 1); lset(g, box_ok);
                br(g, f, OP_br, ob2);
                close(g, f);
                lget(g, li); i32Const(g, 1); op(g, OP_i32_add); lset(g, li);
                br(g, f, OP_br, ol2);
                close(g, f);
                close(g, f);
                close(g, f); // chk_old
                lget(g, box_ok); op(g, OP_i32_eqz);
                let chk_st = open(g, f, OP_if_);
                gget(g, rt.static_blocks_ptr); lset(g, lptr);
                gget(g, rt.static_blocks_len); lset(g, llen);
                i32Const(g, 0); lset(g, li);
                let sb2 = open(g, f, OP_block);
                let sl2 = open(g, f, OP_loop);
                lget(g, li); lget(g, llen); op(g, OP_i32_ge_u); br(g, f, OP_br_if, sb2);
                lget(g, lptr); lget(g, li); i32Const(g, 12); op(g, OP_i32_mul); op(g, OP_i32_add); lset(g, lcell);
                lget(g, w_b); lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0); op(g, OP_i32_ge_u);
                lget(g, box_end);
                lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);
                lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 4);
                op(g, OP_i32_add);
                op(g, OP_i32_le_u);
                op(g, OP_i32_and);
                let sm2 = open(g, f, OP_if_);
                i32Const(g, 1); lset(g, box_ok);
                br(g, f, OP_br, sb2);
                close(g, f);
                lget(g, li); i32Const(g, 1); op(g, OP_i32_add); lset(g, li);
                br(g, f, OP_br, sl2);
                close(g, f);
                close(g, f);
                close(g, f); // chk_st
            }
            lget(g, box_ok); op(g, OP_i32_eqz); trap(g, f);
            // Allocate fresh heap block via rt.open_heap, copy, record in new_block_pins, push InlineRow { dst_base }.
            i32Const(g, logical_bytes); i32Const(g, 0); callf(g, rt.open_heap);
            lset(g, dst_cap); lset(g, dst_base); op(g, OP_drop); lset(g, pin_slot);
            lget(g, dst_base); lget(g, w_b); i32Const(g, logical_bytes); memoryCopyOp(g);
            lget(g, new_blocks_slot); i32Const(g, 20); callf(g, rt.scratch_push); lset(g, dst_tmp);
            lget(g, dst_tmp); lget(g, pin_slot); op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
            lget(g, dst_tmp); lget(g, dst_base); op(g, OP_i32_store); uleb(g, 2); uleb(g, 4);
            lget(g, dst_tmp); i32Const(g, logical_bytes); op(g, OP_i32_store); uleb(g, 2); uleb(g, 8);
            lget(g, dst_tmp); i32Const(g, t); op(g, OP_i32_store); uleb(g, 2); uleb(g, 12);
            lget(g, dst_tmp); lget(g, dst_cap); op(g, OP_i32_store); uleb(g, 2); uleb(g, 16);
            lget(g, visited_block_map); lget(g, w_b); i32Const(g, logical_bytes); i32Const(g, t); lget(g, dst_base);
            callf(g, rt.hmap_put);
            emitPushFixup(g, box_fix_slot, w_a, dst_base, dst_tmp);
            i32Const(g, 0); lset(g, tmp_b);
            emitPushWork(g, work_slot, 0, dst_base, tmp_b, ti as u32, dst_tmp);
            close(g, f); // old_hit
            close(g, f); // s_hit
            close(g, f); // vis_if
            close(g, f); // b_if
        }
        close(g, f); // kind_if
        br(g, f, OP_br, w_loop);
        close(g, f);
        close(g, f);
    }

    // Phase 1 preflight: allocate exact-sized next_owners & next_blocks ledgers + ensure_persistent_slots!
    let ret_o_len = local32(g, f);
    let steal_len = local32(g, f);
    let total_o = local32(g, f);
    let next_o_slot = local32(g, f);
    let next_o_ptr = local32(g, f);
    let next_o_cap = local32(g, f);
    let ret_b_len = local32(g, f);
    let new_b_len = local32(g, f);
    let total_b = local32(g, f);
    let next_b_slot = local32(g, f);
    let next_b_ptr = local32(g, f);
    let next_b_cap = local32(g, f);

    emitLoadTempEntry(g, ret_owners_slot, w_entry);
    lget(g, w_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length); lset(g, ret_o_len);
    emitLoadTempEntry(g, steal_slot, w_entry);
    lget(g, w_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length); lset(g, steal_len);
    lget(g, ret_o_len); lget(g, steal_len); op(g, OP_i32_add); lset(g, total_o);
    i32Const(g, 0); lset(g, next_o_slot);
    i32Const(g, 0); lset(g, next_o_ptr);
    i32Const(g, 0); lset(g, next_o_cap);
    lget(g, total_o);
    {
        let alloc_o = open(g, f, OP_if_);
        lget(g, total_o); i32Const(g, 3); op(g, OP_i32_shl); i32Const(g, 0);
        callf(g, rt.open_heap);
        lset(g, next_o_cap); lset(g, next_o_ptr); op(g, OP_drop); lset(g, next_o_slot);
        close(g, f);
    }

    emitLoadTempEntry(g, ret_blocks_slot, w_entry);
    lget(g, w_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length); lset(g, ret_b_len);
    emitLoadTempEntry(g, new_blocks_slot, w_entry);
    lget(g, w_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length); lset(g, new_b_len);
    lget(g, ret_b_len); lget(g, new_b_len); op(g, OP_i32_add); lset(g, total_b);
    i32Const(g, 0); lset(g, next_b_slot);
    i32Const(g, 0); lset(g, next_b_ptr);
    i32Const(g, 0); lset(g, next_b_cap);
    lget(g, total_b);
    {
        let alloc_b = open(g, f, OP_if_);
        lget(g, total_b); i32Const(g, 4); op(g, OP_i32_shl); i32Const(g, 0);
        callf(g, rt.open_heap);
        lset(g, next_b_cap); lset(g, next_b_ptr); op(g, OP_drop); lset(g, next_b_slot);
        close(g, f);
    }

    lget(g, steal_len);
    callf(g, rt.ensure_persistent_slots);

    // === PHASE 2: 100% flat iterative trap-free commit epilogue ===
    i32Const(g, 2);
    gset(g, root.status_global);

    // 1. Open persistent slots for every entry in steal_list; detach ONLY StealHeap (1) and CopiedHeap (2)!
    emitLoadTempEntry(g, steal_slot, w_entry);
    lget(g, w_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base); lset(g, lptr);
    i32Const(g, 0); lset(g, li);
    {
        let sb = open(g, f, OP_block);
        let sl = open(g, f, OP_loop);
        lget(g, li); lget(g, steal_len); op(g, OP_i32_ge_u); br(g, f, OP_br_if, sb);
        lget(g, lptr); lget(g, li); i32Const(g, 5); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, lcell);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0); // steal_kind
        op(g, OP_i32_eqz);
        let is_emp = open(g, f, OP_if_);
        // Empty: open persistent (0, 0, frozen | live_flag) and DO NOT detach src_slot!
        i32Const(g, 0);
        i32Const(g, 0);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 20);
        i32Const(g, blot_direct_runtime::live_flag);
        op(g, OP_i32_or);
        callf(g, rt.open_persistent);
        lset(g, o_gen); lset(g, o_slot);
        op(g, OP_else_);
        // StealHeap or CopiedHeap: open persistent with heap backing AND detach src_slot immediately!
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 8);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 12);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 16);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 20);
        op(g, OP_i32_or);
        i32Const(g, blot_direct_runtime::heap_flag | blot_direct_runtime::live_flag);
        op(g, OP_i32_or);
        callf(g, rt.open_persistent);
        lset(g, o_gen); lset(g, o_slot);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 4);
        callf(g, rt.detach_temp_slot);
        close(g, f); // is_emp
        lget(g, lcell); lget(g, o_slot); op(g, OP_i32_store); uleb(g, 2); uleb(g, 24);
        lget(g, lcell); lget(g, o_gen); op(g, OP_i32_store); uleb(g, 2); uleb(g, 28);
        lget(g, li); i32Const(g, 1); op(g, OP_i32_add); lset(g, li);
        br(g, f, OP_br, sl);
        close(g, f);
        close(g, f);
    }

    // 2. Detach every new_block_pins pin slot.
    emitLoadTempEntry(g, new_blocks_slot, w_entry);
    lget(g, w_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base); lset(g, lptr);
    i32Const(g, 0); lset(g, li);
    {
        let nb = open(g, f, OP_block);
        let nl = open(g, f, OP_loop);
        lget(g, li); lget(g, new_b_len); op(g, OP_i32_ge_u); br(g, f, OP_br_if, nb);
        lget(g, lptr); lget(g, li); i32Const(g, 20); op(g, OP_i32_mul); op(g, OP_i32_add);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);
        callf(g, rt.detach_temp_slot);
        lget(g, li); i32Const(g, 1); op(g, OP_i32_add); lset(g, li);
        br(g, f, OP_br, nl);
        close(g, f);
        close(g, f);
    }

    // 3. Apply box_fixups.
    emitLoadTempEntry(g, box_fix_slot, w_entry);
    lget(g, w_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base); lset(g, lptr);
    lget(g, w_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length); lset(g, llen);
    i32Const(g, 0); lset(g, li);
    {
        let fb = open(g, f, OP_block);
        let fl = open(g, f, OP_loop);
        lget(g, li); lget(g, llen); op(g, OP_i32_ge_u); br(g, f, OP_br_if, fb);
        lget(g, lptr); lget(g, li); i32Const(g, 3); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, lcell);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 4);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
        lget(g, li); i32Const(g, 1); op(g, OP_i32_add); lset(g, li);
        br(g, f, OP_br, fl);
        close(g, f);
        close(g, f);
    }

    // 4. Apply owner_fixups.
    emitLoadTempEntry(g, steal_slot, w_entry);
    lget(g, w_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base); lset(g, o_base);
    emitLoadTempEntry(g, owner_fix_slot, w_entry);
    lget(g, w_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base); lset(g, lptr);
    lget(g, w_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length); lset(g, llen);
    i32Const(g, 0); lset(g, li);
    {
        let fb = open(g, f, OP_block);
        let fl = open(g, f, OP_loop);
        lget(g, li); lget(g, llen); op(g, OP_i32_ge_u); br(g, f, OP_br_if, fb);
        lget(g, lptr); lget(g, li); i32Const(g, 3); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, lcell);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0); lset(g, dst_tmp); // patch_addr
        lget(g, o_base);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 4); // steal_idx
        i32Const(g, 5); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, w_cell);
        lget(g, dst_tmp); lget(g, w_cell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 24); op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
        lget(g, dst_tmp); lget(g, w_cell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 28); op(g, OP_i32_store); uleb(g, 2); uleb(g, 4);
        lget(g, li); i32Const(g, 1); op(g, OP_i32_add); lset(g, li);
        br(g, f, OP_br, fl);
        close(g, f);
        close(g, f);
    }

    // 5. Fill next_owners & detach next_o_slot.
    lget(g, ret_o_len);
    {
        let cp_ro = open(g, f, OP_if_);
        emitLoadTempEntry(g, ret_owners_slot, w_entry);
        lget(g, next_o_ptr);
        lget(g, w_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
        lget(g, ret_o_len); i32Const(g, 3); op(g, OP_i32_shl);
        memoryCopyOp(g);
        close(g, f);
    }
    i32Const(g, 0); lset(g, li);
    {
        let fb = open(g, f, OP_block);
        let fl = open(g, f, OP_loop);
        lget(g, li); lget(g, steal_len); op(g, OP_i32_ge_u); br(g, f, OP_br_if, fb);
        lget(g, o_base); lget(g, li); i32Const(g, 5); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, lcell);
        lget(g, next_o_ptr); lget(g, ret_o_len); lget(g, li); op(g, OP_i32_add); i32Const(g, 3); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, dst_tmp);
        lget(g, dst_tmp); lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 24); op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
        lget(g, dst_tmp); lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 28); op(g, OP_i32_store); uleb(g, 2); uleb(g, 4);
        lget(g, li); i32Const(g, 1); op(g, OP_i32_add); lset(g, li);
        br(g, f, OP_br, fl);
        close(g, f);
        close(g, f);
    }
    lget(g, next_o_slot);
    {
        let dt = open(g, f, OP_if_);
        lget(g, next_o_slot); callf(g, rt.detach_temp_slot);
        close(g, f);
    }

    // 6. Fill next_blocks & detach next_b_slot.
    lget(g, ret_b_len);
    {
        let cp_rb = open(g, f, OP_if_);
        emitLoadTempEntry(g, ret_blocks_slot, w_entry);
        lget(g, next_b_ptr);
        lget(g, w_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
        lget(g, ret_b_len); i32Const(g, 4); op(g, OP_i32_shl);
        memoryCopyOp(g);
        close(g, f);
    }
    emitLoadTempEntry(g, new_blocks_slot, w_entry);
    lget(g, w_entry); op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base); lset(g, lptr);
    i32Const(g, 0); lset(g, li);
    {
        let fb = open(g, f, OP_block);
        let fl = open(g, f, OP_loop);
        lget(g, li); lget(g, new_b_len); op(g, OP_i32_ge_u); br(g, f, OP_br_if, fb);
        lget(g, lptr); lget(g, li); i32Const(g, 20); op(g, OP_i32_mul); op(g, OP_i32_add); lset(g, lcell);
        lget(g, next_b_ptr); lget(g, ret_b_len); lget(g, li); op(g, OP_i32_add); i32Const(g, 4); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, dst_tmp);
        // Copy 16 bytes (new_ptr, logical_bytes, ty_id, new_cap) starting at lcell + 4!
        lget(g, dst_tmp); lget(g, lcell); i32Const(g, 4); op(g, OP_i32_add); i32Const(g, 16); memoryCopyOp(g);
        lget(g, li); i32Const(g, 1); op(g, OP_i32_add); lset(g, li);
        br(g, f, OP_br, fl);
        close(g, f);
        close(g, f);
    }
    lget(g, next_b_slot);
    {
        let dt = open(g, f, OP_if_);
        lget(g, next_b_slot); callf(g, rt.detach_temp_slot);
        close(g, f);
    }

    // 7. Commit transport-pinned reply (if proc_step multi-word/array reply).
    if has_reply_pin {
        lget(g, reply_pin_slot); callf(g, rt.detach_temp_slot);
        gget(g, rt.transport_cap);
        let old_t = open(g, f, OP_if_);
        gget(g, rt.transport_base);
        gget(g, rt.transport_cap);
        callf(g, rt.free_transport);
        close(g, f);
        lget(g, reply_base); gset(g, rt.transport_base);
        lget(g, reply_cap); gset(g, rt.transport_cap);
        lget(g, reply_base); lget(g, reply_bytes); op(g, OP_i32_add); gset(g, rt.transport_top);
    }

    // 8. Free old_owners \ retained_owners via free_persistent + old_owners ledger.
    gget(g, root.live_owners_ptr); lset(g, lptr);
    gget(g, root.live_owners_len); lset(g, llen);
    i32Const(g, 0); lset(g, li);
    {
        let fb = open(g, f, OP_block);
        let fl = open(g, f, OP_loop);
        lget(g, li); lget(g, llen); op(g, OP_i32_ge_u); br(g, f, OP_br_if, fb);
        lget(g, lptr); lget(g, li); i32Const(g, 3); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, lcell);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0); lset(g, o_slot);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 4); lset(g, o_gen);
        lget(g, ret_owners_map); lget(g, o_slot); lget(g, o_gen); i32Const(g, 0);
        callf(g, rt.hmap_get);
        lset(g, m_found); op(g, OP_drop);
        lget(g, m_found); op(g, OP_i32_eqz);
        let drop_o = open(g, f, OP_if_);
        lget(g, o_slot); lget(g, o_gen); callf(g, rt.free_persistent);
        close(g, f);
        lget(g, li); i32Const(g, 1); op(g, OP_i32_add); lset(g, li);
        br(g, f, OP_br, fl);
        close(g, f);
        close(g, f);
    }
    gget(g, root.live_owners_cap);
    {
        let fr = open(g, f, OP_if_);
        gget(g, root.live_owners_ptr); gget(g, root.live_owners_cap); callf(g, rt.heap_free);
        close(g, f);
    }

    // 9. Free old_blocks \ retained_blocks via heap_free(addr, actual_cap) + old_blocks ledger.
    gget(g, root.live_blocks_ptr); lset(g, lptr);
    gget(g, root.live_blocks_len); lset(g, llen);
    i32Const(g, 0); lset(g, li);
    {
        let fb = open(g, f, OP_block);
        let fl = open(g, f, OP_loop);
        lget(g, li); lget(g, llen); op(g, OP_i32_ge_u); br(g, f, OP_br_if, fb);
        lget(g, lptr); lget(g, li); i32Const(g, 4); op(g, OP_i32_shl); op(g, OP_i32_add); lset(g, lcell);
        lget(g, ret_blocks_map);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 4);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 8);
        callf(g, rt.hmap_get);
        lset(g, m_found); op(g, OP_drop);
        lget(g, m_found); op(g, OP_i32_eqz);
        let drop_b = open(g, f, OP_if_);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);
        lget(g, lcell); op(g, OP_i32_load); uleb(g, 2); uleb(g, 12);
        callf(g, rt.heap_free);
        close(g, f);
        lget(g, li); i32Const(g, 1); op(g, OP_i32_add); lset(g, li);
        br(g, f, OP_br, fl);
        close(g, f);
        close(g, f);
    }
    gget(g, root.live_blocks_cap);
    {
        let fr = open(g, f, OP_if_);
        gget(g, root.live_blocks_ptr); gget(g, root.live_blocks_cap); callf(g, rt.heap_free);
        close(g, f);
    }

    // 10. Commit new ledgers & final patched state globals from root_buf.
    lget(g, next_o_ptr); gset(g, root.live_owners_ptr);
    lget(g, total_o); gset(g, root.live_owners_len);
    lget(g, next_o_cap); gset(g, root.live_owners_cap);
    lget(g, next_b_ptr); gset(g, root.live_blocks_ptr);
    lget(g, total_b); gset(g, root.live_blocks_len);
    lget(g, next_b_cap); gset(g, root.live_blocks_cap);

    let committed_val, lverr = loadAt(g, f, root_buf, 0, root.state_ty, 0);
    if lverr != blot_direct_types::Error.none { return lverr; }
    storePersistRootVal(g, f, root, committed_val);

    // 11. Release all temporary scratch slots & stack while status == 2, then publish status = 1!
    releaseEntry(g);
    i32Const(g, 1);
    gset(g, root.status_global);
    if has_fast_branch { close(g, f); }
    return blot_direct_types::Error.none;
}
