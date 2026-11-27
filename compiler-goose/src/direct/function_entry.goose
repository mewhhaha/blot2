// Instance bodies, exported entries and the host boundary of the direct
// backend's function emitter (compiler/src/direct/function.zig).
namespace blot_direct_function;
import .function;

// A body that begins at the top of the generator's stacks.
fn newFn(g: Generator&, unit: u32, instance_id: u32) -> Fn {
    g.s.serial += 1;
    return Fn { sites_base:blot_direct_relocations::mark(), unit: unit, instance_id: instance_id, serial: g.s.serial, handles_base: g.s.handles.len, handle_cells_base: g.s.handle_cells_len, code_base: g.s.code.len, locals_base: g.s.locals.len, shadows_base: g.s.v128_shadows.len, labels_base: g.s.labels.len };
}

// ----- host boundary -----------------------------------------------------

fn packetElemStep(tag: blot_direct_types::Tag) -> u32 {
    match tag {
        u8_ => { return 1; },
        u64_, i64_, f64_ => { return 8; },
        _ => { return 4; },
    }
}
// Reads and validates a host packet's element count against `transport_top` for
// `elem_step` bytes per element (1, 4, or 8). Uses `rt.packet_length` for 4B.
fn emitPacketLength(g: Generator&, f: Fn&, packet: u32, elem_step: u32) -> u32 {
    let rt = g.runtime_();
    let length = local32(g, f);
    if elem_step == 4 {
        lget(g, packet);
        callf(g, rt.packet_length);
        lset(g, length);
        return length;
    }
    gget(g, rt.transport_cap);
    op(g, OP_i32_eqz);
    trap(g, f);
    let end = local32(g, f);
    gget(g, rt.transport_top);
    lset(g, end);
    lget(g, end);
    i32Const(g, 4);
    op(g, OP_i32_lt_u);
    lget(g, packet);
    gget(g, rt.transport_base);
    op(g, OP_i32_lt_u);
    op(g, OP_i32_or);
    lget(g, packet);
    i32Const(g, 3);
    op(g, OP_i32_and);
    op(g, OP_i32_or);
    lget(g, packet);
    lget(g, end);
    i32Const(g, 4);
    op(g, OP_i32_sub);
    op(g, OP_i32_gt_u);
    op(g, OP_i32_or);
    trap(g, f);
    lget(g, packet);
    op(g, OP_i32_load);
    uleb(g, 2);
    uleb(g, 0);
    ltee(g, length);
    lget(g, end);
    lget(g, packet);
    op(g, OP_i32_sub);
    i32Const(g, 4);
    op(g, OP_i32_sub);
    if elem_step == 8 {
        i32Const(g, 3);
        op(g, OP_i32_shr_u);
    }
    op(g, OP_i32_gt_u);
    trap(g, f);
    return length;
}
// A fresh fixed array from the host packet at `packet` (a local). When
// `zero_copy` is true (pure non-callback entry parameter), open the transport
// slice in place; `toPacket` copies with overlap-safe `memory.copy` and skips
// zeroing so returning or aliasing the input remains sound.
fn fromPacket(g: Generator&, f: Fn&, ty: Ty, packet: u32, zero_copy: bool = false) -> Val, Error {
    let rt = g.runtime_();
    let elem_ty = g.types.node(ty).a;
    let elem_tag = tagOf(g, elem_ty);
    let is_bool_arr = elem_tag == blot_direct_types::Tag.boolean;
    let elem_step = packetElemStep(elem_tag);
    let length = emitPacketLength(g, f, packet, elem_step);
    let array_ty, error = g.types.intern(blot_direct_types::Tag.array, [elem_ty]);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    if is_bool_arr {
        let handle, base, error = createUninit(g, f, array_ty, length, 0);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        let idx = constLocal(g, f, 0);
        let src_ptr = local32(g, f);
        lget(g, packet);
        i32Const(g, 4);
        op(g, OP_i32_add);
        lset(g, src_ptr);
        let dst_ptr = local32(g, f);
        lget(g, base);
        lset(g, dst_ptr);
        let exit = open(g, f, OP_block);
        let top = open(g, f, OP_loop);
        lget(g, idx);
        lget(g, length);
        op(g, OP_i32_ge_u);
        br(g, f, OP_br_if, exit);
        lget(g, dst_ptr);
        lget(g, src_ptr);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);
        op(g, OP_i32_store8); uleb(g, 0); uleb(g, 0);
        lget(g, src_ptr); i32Const(g, 4); op(g, OP_i32_add); lset(g, src_ptr);
        lget(g, dst_ptr); i32Const(g, 1); op(g, OP_i32_add); lset(g, dst_ptr);
        lget(g, idx); i32Const(g, 1); op(g, OP_i32_add); lset(g, idx);
        br(g, f, OP_br, top);
        close(g, f);
        close(g, f);
        return Val { ty, handle.start, handle.len }, blot_direct_types::Error.none;
    }
    if zero_copy {
        let base = local32(g, f);
        lget(g, packet);
        i32Const(g, 4);
        op(g, OP_i32_add);
        lset(g, base);
        let bytes = emitScaledBytes(g, f, length, elem_step);
        lget(g, bytes);
        gget(g, rt.transport_top);
        lget(g, base);
        op(g, OP_i32_sub);
        op(g, OP_i32_gt_u);
        trap(g, f);
        lget(g, base);
        lget(g, length);
        lget(g, bytes);
        callf(g, rt.open);
        let handle, error = pop(g, f, array_ty, 0);
        if error != blot_direct_types::Error.none { return handle, error; }
        recordCheckedArray(f, w(g, handle, 0), w(g, handle, 1), base, length);
        return Val { ty, handle.start, handle.len }, blot_direct_types::Error.none;
    }
    let handle, base, error = createUninit(g, f, array_ty, length, 0);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    lget(g, base);
    lget(g, packet);
    i32Const(g, 4);
    op(g, OP_i32_add);
    lget(g, length);
    if elem_step != 1 {
        i32Const(g, elem_step);
        op(g, OP_i32_mul);
    }
    op(g, OP_prefix_fc);
    uleb(g, 10);
    op(g, 0);
    op(g, 0);
    return Val { ty, handle.start, handle.len }, blot_direct_types::Error.none;
}
fn emitCopyArrayToPacket(g: Generator&, f: Fn&, dst_packet: u32, src_base: u32, length: u32, bytes: u32, is_bool_arr: bool) {
    if !is_bool_arr {
        lget(g, dst_packet);
        i32Const(g, 4);
        op(g, OP_i32_add);
        lget(g, src_base);
        lget(g, bytes);
        op(g, OP_prefix_fc);
        uleb(g, 10);
        op(g, 0);
        op(g, 0);
        return;
    }
    let idx = constLocal(g, f, 0);
    let dst_ptr = local32(g, f);
    lget(g, dst_packet);
    i32Const(g, 4);
    op(g, OP_i32_add);
    lset(g, dst_ptr);
    let src_ptr = local32(g, f);
    lget(g, src_base);
    lset(g, src_ptr);
    let exit = open(g, f, OP_block);
    let top = open(g, f, OP_loop);
    lget(g, idx);
    lget(g, length);
    op(g, OP_i32_ge_u);
    br(g, f, OP_br_if, exit);
    lget(g, dst_ptr);
    lget(g, src_ptr);
    op(g, OP_i32_load8_u); uleb(g, 0); uleb(g, 0);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
    lget(g, dst_ptr); i32Const(g, 4); op(g, OP_i32_add); lset(g, dst_ptr);
    lget(g, src_ptr); i32Const(g, 1); op(g, OP_i32_add); lset(g, src_ptr);
    lget(g, idx); i32Const(g, 1); op(g, OP_i32_add); lset(g, idx);
    br(g, f, OP_br, top);
    close(g, f);
    close(g, f);
}
// Copies an array into a fresh host packet; returns its address local.
fn toPacket(g: Generator&, f: Fn&, value: Val, id: u32) -> u32, Error {
    let rt = g.runtime_();
    let elem_ty, eerr = elementOf(g, f, value.ty, id);
    if eerr != blot_direct_types::Error.none { return 0, eerr; }
    let elem_tag = tagOf(g, elem_ty);
    let is_bool_arr = elem_tag == blot_direct_types::Tag.boolean;
    let elem_step = packetElemStep(elem_tag);
    let length, error = lengthOf(g, f, value, id);
    if error != blot_direct_types::Error.none { return 0, error; }
    let max_elems = (rt.layout.transport_end - rt.layout.transport_base - 4) / elem_step;
    lget(g, length);
    i32Const(g, max_elems);
    op(g, OP_i32_gt_u);
    trap(g, f);
    let bytes = emitScaledBytes(g, f, length, elem_step);
    let total = local32(g, f);
    lget(g, bytes);
    if elem_step < 4 {
        i32Const(g, 7);
        op(g, OP_i32_add);
        i32Const(g, 0xfffffffc);
        op(g, OP_i32_and);
    } else {
        i32Const(g, 4);
        op(g, OP_i32_add);
    }
    lset(g, total);
    let packet = local32(g, f);
    lget(g, total);
    gget(g, rt.transport_cap);
    op(g, OP_i32_le_u);
    let fast = open(g, f, OP_if_);
    gget(g, rt.transport_base);
    ltee(g, packet);
    lget(g, total);
    op(g, OP_i32_add);
    gset(g, rt.transport_top);
    let non_empty = open(g, f, OP_block);
    lget(g, length);
    op(g, OP_i32_eqz);
    opIndex(g, OP_br_if, 0);
    let base = baseOf(g, f, value);
    emitCopyArrayToPacket(g, f, packet, base, length, bytes, is_bool_arr);
    close(g, f);
    popCheckedArraysAt(f, fast);
    op(g, OP_else_);
    let pin_slot = local32(g, f);
    let pin_gen = local32(g, f);
    let new_base = local32(g, f);
    let new_cap = local32(g, f);
    lget(g, total);
    callf(g, rt.open_transport_pin);
    lset(g, new_cap);
    lset(g, new_base);
    lset(g, pin_gen);
    lset(g, pin_slot);
    let non_empty2 = open(g, f, OP_block);
    lget(g, length);
    op(g, OP_i32_eqz);
    opIndex(g, OP_br_if, 0);
    let base2 = baseOf(g, f, value);
    emitCopyArrayToPacket(g, f, new_base, base2, length, bytes, is_bool_arr);
    close(g, f);
    lget(g, pin_slot);
    callf(g, rt.detach_temp_slot);
    gget(g, rt.transport_cap);
    let had_old = open(g, f, OP_if_);
    gget(g, rt.transport_base);
    gget(g, rt.transport_cap);
    callf(g, rt.free_transport);
    close(g, f);
    lget(g, new_base);
    gset(g, rt.transport_base);
    lget(g, new_cap);
    gset(g, rt.transport_cap);
    lget(g, new_base);
    lget(g, total);
    op(g, OP_i32_add);
    gset(g, rt.transport_top);
    lget(g, new_base);
    lset(g, packet);
    close(g, f);
    lget(g, packet);
    lget(g, length);
    op(g, OP_i32_store);
    uleb(g, 2);
    uleb(g, 0);
    return packet, blot_direct_types::Error.none;
}
// A closure calling host callback `slot` of table 1.
fn hostClosure(g: Generator&, f: Fn&, ty: Ty, first: Abi, second: Abi, slot: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let import_id = hostImport(g, first, second);
    let key = InstanceKey { kind: blot_direct_emit::InstanceKind.host, unit: f.unit, id: import_id, ty: ty };
    let arrow = g.types.node(ty);
    var instance, found = g.find(key);
    if !found {
        let parameters = g.saveTys([arrow.a]);
        let captures = g.saveTys([blot_direct_types::u32_]);
        let made, error = g.addInstanceWith(key, Env {}, parameters, arrow.b, true, captures, m, 0);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        instance = made;
    }
    let captured = constLocal(g, f, slot);
    let capture = valOf1(g, blot_direct_types::u32_, captured);
    return makeClosure(g, f, instance, ty, g.saveVals([capture]), 0);
}
// The host adapter body: converts the argument, calls the import with the
// callback's externref and converts the result.
fn hostBody(g: Generator&, f: Fn&, instance_id: u32, captures: Vals, argument: Val) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let key = g.s.instances[instance_id].key;
    let arrow = g.types.node(key.ty);
    let first, second, known = callbackAbi(g, key.ty);
    if !known { return neverVal(), g.fail(m, 0, "host callback shape"); }
    var has_packet = false;
    var packet: u32 = 0;
    if isArray(first) {
        let address, error = toPacket(g, f, argument, 0);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        has_packet = true;
        packet = address;
    }
    lget(g, w(g, g.s.vals[captures.start], 0));
    opIndex(g, OP_table_get, 1);
    if has_packet { lget(g, packet); } else if first == Abi.unit { i32Const(g, 0); } else { push(g, argument); }
    callf(g, key.id);
    if isArray(second) {
        let address = local32(g, f);
        lset(g, address);
        noteAllocation(f);
        return fromPacket(g, f, arrow.b, address);
    }
    if second == Abi.unit {
        op(g, OP_drop);
        return unitVal(), blot_direct_types::Error.none;
    }
    return pop(g, f, arrow.b, 0);
}

// ----- instances ---------------------------------------------------------

// Emits the body of instance `id`. Bodies nest (an instance emitted to learn
// its result type), so this one owns the generator's stacks from here up and
// gives them back when it ends, whether or not it succeeds.
recursive fn emitInstance(g: Generator&, id: u32) -> Error {
    let s .= g.s;
    let code_mark = s.code.len;
    let sites_mark = blot_direct_relocations::mark();
    let locals_mark = s.locals.len;
    let shadows_mark = s.v128_shadows.len;
    let labels_mark = s.labels.len;
    let handles_mark = s.handles.len;
    let handle_cells_mark = s.handle_cells_len;
    let prev_active = s.active_instance;
    let prev_dep_mark = s.dep_frame_mark;
    let dep_mark = s.dep_scratch.len;
    s.active_instance = id;
    s.dep_frame_mark = dep_mark;
    let error = emitInstanceBody(g, id);
    if error == blot_direct_types::Error.none && s.track_deps {
        let count = s.dep_scratch.len - dep_mark;
        if !s.replaying {
            let start = s.dep_list.len as u32;
            for di in 0..count { s.dep_list.push(s.dep_scratch[dep_mark + di].id); }
            s.instances[id].deps_start = start;
            s.instances[id].deps_len = count as u32;
        } else {
            let inst = s.instances[id];
            if count != (inst.deps_len as i64) {
                s.dep_match = false;
            } else {
                for di in 0..count {
                    if s.dep_list[(inst.deps_start as i64) + di] != s.dep_scratch[dep_mark + di].id {
                        s.dep_match = false;
                        break;
                    }
                }
            }
        }
    }
    s.dep_scratch.resize(dep_mark);
    s.dep_frame_mark = prev_dep_mark;
    s.active_instance = prev_active;
    blot_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark);
    s.locals.resize(locals_mark);
    s.v128_shadows.resize(shadows_mark);
    s.shadow_epoch += 1;
    s.labels.resize(labels_mark);
    s.handles.resize(handles_mark);
    s.handle_cells_len = handle_cells_mark;
    return error;
}
// True when `id` contains at least one function-level tail call targeting `target`
// with exact arity `param_count` outside `fork`/`handle`/`closure` scopes.
recursive fn hasSelfTailCall(
    g: const Generator&,
    m: const Module&,
    id: u32,
    target: BindingRef,
    param_count: i64,
    fn_ret_block: u32,
    depth: i64,
) -> bool {
    if id == 0 || depth >= 128 { return false; }
    let n = m.node(id);
    match n.tag {
        return_ => {
            if n.a == 0 { return false; }
            if (n.b == 0 || n.b == fn_ret_block) && m.node(n.a).tag == blot_check_core::Tag.call {
                let info = m.call(n.a);
                if g.resolve(m, info.target) == target && info.arguments.len == param_count { return true; }
            }
            return hasSelfTailCall(g, m, n.a, target, param_count, fn_ret_block, depth + 1);
        },
        suite, block_ => {
            for child in m.children(id) {
                if hasSelfTailCall(g, m, child, target, param_count, fn_ret_block, depth + 1) { return true; }
            }
            return false;
        },
        if_stmt, if_value => {
            return hasSelfTailCall(g, m, n.b, target, param_count, fn_ret_block, depth + 1) ||
                hasSelfTailCall(g, m, n.c, target, param_count, fn_ret_block, depth + 1);
        },
        match_ => {
            for arm in m.matchArms(id) {
                if hasSelfTailCall(g, m, arm.body, target, param_count, fn_ret_block, depth + 1) { return true; }
            }
            return false;
        },
        loop_ => {
            return hasSelfTailCall(g, m, m.loopInfo(id).body, target, param_count, fn_ret_block, depth + 1);
        },
        _ => { return false; },
    }
}

fn associativeIntOpcode(op_: Op, ty: Ty) -> u8 {
    if ty == blot_direct_types::u32_ || ty == blot_direct_types::i32_ {
        match op_ {
            add => { return OP_i32_add; },
            bit_xor => { return OP_i32_xor; },
            mul => { return OP_i32_mul; },
            _ => { return 0; },
        }
    }
    if ty == blot_direct_types::u64_ || ty == blot_direct_types::i64_ {
        match op_ {
            add => { return OP_i64_add; },
            bit_xor => { return OP_i64_xor; },
            mul => { return OP_i64_mul; },
            _ => { return 0; },
        }
    }
    return 0;
}
fn isExactSelfCall(g: const Generator&, m: const Module&, id: u32, target: BindingRef, param_count: i64) -> bool {
    if id == 0 || m.node(id).tag != blot_check_core::Tag.call { return false; }
    let info = m.call(id);
    return info.arguments.len == param_count && g.resolve(m, info.target) == target;
}

// Whitelist the whole body so advancing one recursive call in the current
// frame can't move an effect, access captures or bypass allocation cleanup.
// Extended to support read-only invariant array params and U32/I32/U64/I64
// wrapping integer accumulation (right-spine associative TCO).
recursive fn scanScalarRecursion(g: Generator&, f: const Fn&, m: const Module&, id: u32,
    target: BindingRef, param_count: i64, arr_mask: u32, param_bindings: const u32[8]&,
    ret_block: u32, res_ty: Ty, opcode: u8&, budget: i64&, depth: i64 = 0) -> bool {
    if id == 0 { return true; }
    if budget <= 0 || depth >= 128 { return false; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        constant => { return isCoreScalar(m, id); },
        reference => {
            let binding = localRef(m, id);
            if binding != 0 {
                let kind = m.binding(binding).kind;
                if kind == blot_reuse_principal_interface::Kind.local || kind == blot_reuse_principal_interface::Kind.parameter {
                    if isCoreScalar(m, id) { return true; }
                    if m.types.node(m.typeOf(id)).tag == blot_check_types::Tag.array {
                        for pi in 0..param_count {
                            if pi < 8 && ((arr_mask >> (pi as u32)) & 1) != 0 && param_bindings[pi] == binding { return true; }
                        }
                        return false;
                    }
                    return coreTypeUnboxed(g, f, m, m.typeOf(id));
                }
            }
            if isCoreScalar(m, id) {
                let target_ref = g.resolve(m, m.reference(id));
                if g.hasUnit(target_ref.unit) {
                    let tm .= g.units[target_ref.unit - 1];
                    let cb .= tm.body(target_ref.binding);
                    if cb && !cb.is_function && tm.node(cb.root).tag == blot_check_core::Tag.constant {
                        return true;
                    }
                }
            }
            return false;
        },
        scalar, logical, associated => {
            if n.tag == blot_check_core::Tag.associated && n.op == blot_check_core::Op.none { return false; }
            return isCoreScalar(m, n.a) && (n.b == 0 || isCoreScalar(m, n.b)) &&
                scanScalarRecursion(g, f, m, n.a, target, param_count, arr_mask, param_bindings, ret_block, res_ty, opcode, budget, depth + 1) &&
                scanScalarRecursion(g, f, m, n.b, target, param_count, arr_mask, param_bindings, ret_block, res_ty, opcode, budget, depth + 1);
        },
        project => {
            if isPureScalarProject(g, m, id) {
                return scanScalarRecursion(g, f, m, n.a, target, param_count, arr_mask, param_bindings, ret_block, res_ty, opcode, budget, depth + 1);
            }
            let variants = m.projectionVariants(n.b);
            let recv_tag = m.types.node(m.typeOf(n.a)).tag;
            if variants.len != 0 || recv_tag == blot_check_types::Tag.record || recv_tag == blot_check_types::Tag.product {
                return coreTypeUnboxed(g, f, m, m.typeOf(id)) &&
                    scanScalarRecursion(g, f, m, n.a, target, param_count, arr_mask, param_bindings, ret_block, res_ty, opcode, budget, depth + 1);
            }
            let sp = m.fieldSpelling(m.projection(n.b).field);
            if sp.present && sp.value == "length" {
                return scanScalarRecursion(g, f, m, n.a, target, param_count, arr_mask, param_bindings, ret_block, res_ty, opcode, budget, depth + 1);
            }
            return false;
        },
        array_op => {
            let aop = m.arrayOperation(id);
            if aop != blot_backend_collection_ops::Op.get && aop != blot_backend_collection_ops::Op.length { return false; }
            if aop == blot_backend_collection_ops::Op.get && !coreTypeUnboxed(g, f, m, m.typeOf(id)) { return false; }
            for ch in m.children(id) {
                if !scanScalarRecursion(g, f, m, ch, target, param_count, arr_mask, param_bindings, ret_block, res_ty, opcode, budget, depth + 1) { return false; }
            }
            return true;
        },
        storage => {
            let op_k, ok = blot_check_storage_ops::opFromCode(n.c);
            if ok != blot_error::Error.none || (op_k != blot_check_storage_ops::Op.read && op_k != blot_check_storage_ops::Op.length) { return false; }
            if op_k == blot_check_storage_ops::Op.read && !coreTypeUnboxed(g, f, m, m.typeOf(id)) { return false; }
            for ch in m.children(id) {
                if !scanScalarRecursion(g, f, m, ch, target, param_count, arr_mask, param_bindings, ret_block, res_ty, opcode, budget, depth + 1) { return false; }
            }
            return true;
        },
        call => {
            let info = m.call(id);
            if scratchScalarCallee(g, m, info) {
                for arg in info.arguments {
                    if !scanScalarRecursion(g, f, m, arg, target, param_count, arr_mask, param_bindings, ret_block, res_ty, opcode, budget, depth + 1) { return false; }
                }
                return true;
            }
            if !isExactSelfCall(g, m, id, target, param_count) { return false; }
            for arg, ai in info.arguments {
                if ai < 8 && ((arr_mask >> (ai as u32)) & 1) != 0 {
                    if localRef(m, arg) != param_bindings[ai] { return false; }
                } else if !scanScalarRecursion(g, f, m, arg, target, param_count, arr_mask, param_bindings, ret_block, res_ty, opcode, budget, depth + 1) { return false; }
            }
            return true;
        },
        suite, block_ => {
            for child in m.children(id) {
                if !scanScalarRecursion(g, f, m, child, target, param_count, arr_mask, param_bindings, ret_block, res_ty, opcode, budget, depth + 1) { return false; }
            }
            return true;
        },
        bind => {
            return n.c < 2 && scanScalarRecursion(g, f, m, n.b, target, param_count, arr_mask, param_bindings, ret_block, res_ty, opcode, budget, depth + 1);
        },
        pattern_bind => {
            return scanScalarRecursion(g, f, m, n.b, target, param_count, arr_mask, param_bindings, ret_block, res_ty, opcode, budget, depth + 1) &&
                scanScalarRecursion(g, f, m, n.c, target, param_count, arr_mask, param_bindings, ret_block, res_ty, opcode, budget, depth + 1);
        },
        if_stmt, if_value => {
            return scanScalarRecursion(g, f, m, n.a, target, param_count, arr_mask, param_bindings, ret_block, res_ty, opcode, budget, depth + 1) &&
                scanScalarRecursion(g, f, m, n.b, target, param_count, arr_mask, param_bindings, ret_block, res_ty, opcode, budget, depth + 1) &&
                scanScalarRecursion(g, f, m, n.c, target, param_count, arr_mask, param_bindings, ret_block, res_ty, opcode, budget, depth + 1);
        },
        match_ => {
            for inp in m.matchInputs(id) {
                if !scanScalarRecursion(g, f, m, inp, target, param_count, arr_mask, param_bindings, ret_block, res_ty, opcode, budget, depth + 1) { return false; }
            }
            for arm in m.matchArms(id) {
                if !scanScalarRecursion(g, f, m, arm.guard_, target, param_count, arr_mask, param_bindings, ret_block, res_ty, opcode, budget, depth + 1) ||
                    !scanScalarRecursion(g, f, m, arm.body, target, param_count, arr_mask, param_bindings, ret_block, res_ty, opcode, budget, depth + 1) { return false; }
            }
            return true;
        },
        return_ => {
            if n.a == 0 { return false; }
            let value = m.node(n.a);
            if opcode == 0 && (n.b == ret_block || n.b == 0) && value.tag == blot_check_core::Tag.scalar &&
                isExactSelfCall(g, m, value.b, target, param_count) {
                opcode = associativeIntOpcode(value.op, res_ty);
            }
            return scanScalarRecursion(g, f, m, n.a, target, param_count, arr_mask, param_bindings, ret_block, res_ty, opcode, budget, depth + 1);
        },
        _ => { return false; },
    }
}

// Conservative call-graph-aware check: true when evaluating `id` cannot bump
// `owner_top` or `stack_pointer` (allows `storage.push`/`reserve`/indexed
// `update` on existing owners, unboxed aggregates, and recursive calls within
// the visited SCC).
recursive fn bodyNoScopeAlloc(
    g: Generator&,
    f: const Fn&,
    m: const Module&,
    id: u32,
    visited: BindingRef[16]&,
    visited_len: i64&,
    left: i64&,
) -> bool {
    if id == 0 { return true; }
    if left <= 0 { return false; }
    left -= 1;
    let n = m.node(id);
    match n.tag {
        constant, panic => { return true; },
        reference => {
            let ref = m.reference(id);
            if ref.unit == 0 || ref.unit == m.unit {
                let kind = m.binding(ref.binding).kind;
                if kind == blot_reuse_principal_interface::Kind.local || kind == blot_reuse_principal_interface::Kind.parameter { return true; }
            }
            return isCoreScalar(m, id);
        },
        suite, block_ => {
            for child in m.children(id) {
                if !bodyNoScopeAlloc(g, f, m, child, visited, visited_len, left) { return false; }
            }
            return true;
        },
        bind => { return n.c < 2 && bodyNoScopeAlloc(g, f, m, n.b, visited, visited_len, left); },
        return_ => { return bodyNoScopeAlloc(g, f, m, n.a, visited, visited_len, left); },
        break_ => {
            for child in m.children(id) {
                if !bodyNoScopeAlloc(g, f, m, child, visited, visited_len, left) { return false; }
            }
            return true;
        },
        if_value, if_stmt => {
            return bodyNoScopeAlloc(g, f, m, n.a, visited, visited_len, left) &&
                bodyNoScopeAlloc(g, f, m, n.b, visited, visited_len, left) &&
                bodyNoScopeAlloc(g, f, m, n.c, visited, visited_len, left);
        },
        match_ => {
            for inp in m.matchInputs(id) {
                if !bodyNoScopeAlloc(g, f, m, inp, visited, visited_len, left) { return false; }
            }
            for arm in m.matchArms(id) {
                if !bodyNoScopeAlloc(g, f, m, arm.guard_, visited, visited_len, left) ||
                    !bodyNoScopeAlloc(g, f, m, arm.body, visited, visited_len, left) { return false; }
            }
            return true;
        },
        pattern_bind => {
            return bodyNoScopeAlloc(g, f, m, n.b, visited, visited_len, left) &&
                bodyNoScopeAlloc(g, f, m, n.c, visited, visited_len, left);
        },
        loop_ => {
            let linfo = m.loopInfo(id);
            if linfo.kind == blot_check_core::LoopKind.array {
                let src_ty_id = m.typeOf(linfo.first);
                if src_ty_id == 0 { return false; }
                let src_ty, serr = g.types.lower(m, src_ty_id, f.env);
                if serr != blot_direct_types::Error.none { g.dropFailure(); return false; }
                match tagOf(g, src_ty) {
                    array, view => {
                        let elem_boxed, eberr = g.types.boxed(g.types.node(src_ty).a);
                        if eberr != blot_direct_types::Error.none || elem_boxed { return false; }
                    },
                    _ => { return false; },
                }
            }
            for carry in m.loopCarries(id) {
                if !coreTypeUnboxed(g, f, m, m.binding(carry.incoming).ty) { return false; }
            }
            return bodyNoScopeAlloc(g, f, m, linfo.first, visited, visited_len, left) &&
                bodyNoScopeAlloc(g, f, m, linfo.end, visited, visited_len, left) &&
                bodyNoScopeAlloc(g, f, m, linfo.body, visited, visited_len, left);
        },
        construct => {
            return coreTypeUnboxed(g, f, m, m.typeOf(id)) && bodyNoScopeAlloc(g, f, m, n.b, visited, visited_len, left);
        },
        product, record => {
            if !coreTypeUnboxed(g, f, m, m.typeOf(id)) { return false; }
            for child in m.children(id) {
                if !bodyNoScopeAlloc(g, f, m, child, visited, visited_len, left) { return false; }
            }
            return true;
        },
        update => {
            let change = m.updateInfo(id);
            let sels = m.updateSelectors(id);
            if sels.len == 0 || sels[0].kind != blot_check_core::UpdateKind.index { return false; }
            if !coreTypeUnboxed(g, f, m, m.typeOf(change.value)) { return false; }
            if !bodyNoScopeAlloc(g, f, m, change.root, visited, visited_len, left) ||
                !bodyNoScopeAlloc(g, f, m, change.value, visited, visited_len, left) { return false; }
            for sel in sels {
                if sel.kind == blot_check_core::UpdateKind.index && !bodyNoScopeAlloc(g, f, m, sel.index, visited, visited_len, left) { return false; }
            }
            return true;
        },
        project => {
            if isPureScalarProject(g, m, id) { return bodyNoScopeAlloc(g, f, m, n.a, visited, visited_len, left); }
            let proj = m.projection(n.b);
            let variants = m.projectionVariants(n.b);
            let recv_tag = m.types.node(m.typeOf(n.a)).tag;
            if variants.len != 0 || recv_tag == blot_check_types::Tag.record || recv_tag == blot_check_types::Tag.product {
                if !coreTypeUnboxed(g, f, m, m.typeOf(id)) { return false; }
                // Direct field projection out of a boxed array element (`pool[idx].local`)
                // is emitted in-place by `tryProjectBoxedArrayElement` without boxing the element.
                let inner = m.node(n.a);
                if inner.tag == blot_check_core::Tag.array_op && m.arrayOperation(n.a) == blot_backend_collection_ops::Op.get {
                    for ch in m.children(n.a) {
                        if !bodyNoScopeAlloc(g, f, m, ch, visited, visited_len, left) { return false; }
                    }
                    return true;
                }
                if inner.tag == blot_check_core::Tag.storage {
                    let op_k, ok = blot_check_storage_ops::opFromCode(inner.c);
                    if ok == blot_error::Error.none && op_k == blot_check_storage_ops::Op.read {
                        for ch in m.children(n.a) {
                            if !bodyNoScopeAlloc(g, f, m, ch, visited, visited_len, left) { return false; }
                        }
                        return true;
                    }
                }
                return bodyNoScopeAlloc(g, f, m, n.a, visited, visited_len, left);
            }
            let sp = m.fieldSpelling(proj.field);
            if sp.present && sp.value == "length" {
                return bodyNoScopeAlloc(g, f, m, n.a, visited, visited_len, left);
            }
            return false;
        },
        scalar, associated, logical => {
            if n.tag == blot_check_core::Tag.associated && n.op == blot_check_core::Op.none { return false; }
            return bodyNoScopeAlloc(g, f, m, n.a, visited, visited_len, left) &&
                bodyNoScopeAlloc(g, f, m, n.b, visited, visited_len, left);
        },
        array_op => {
            match m.arrayOperation(id) {
                length => {
                    for child in m.children(id) {
                        if !bodyNoScopeAlloc(g, f, m, child, visited, visited_len, left) { return false; }
                    }
                    return true;
                },
                get => {
                    if !coreTypeUnboxed(g, f, m, m.typeOf(id)) { return false; }
                    for child in m.children(id) {
                        if !bodyNoScopeAlloc(g, f, m, child, visited, visited_len, left) { return false; }
                    }
                    return true;
                },
                _ => { return false; },
            }
        },
        storage => {
            let op_k, ok = blot_check_storage_ops::opFromCode(n.c);
            if ok != blot_error::Error.none { return false; }
            match op_k {
                length, view, truncate, reserve => {
                    for child in m.children(id) {
                        if !bodyNoScopeAlloc(g, f, m, child, visited, visited_len, left) { return false; }
                    }
                    return true;
                },
                read, pop => {
                    if !coreTypeUnboxed(g, f, m, m.typeOf(id)) { return false; }
                    for child in m.children(id) {
                        if !bodyNoScopeAlloc(g, f, m, child, visited, visited_len, left) { return false; }
                    }
                    return true;
                },
                push => {
                    let ch = m.children(id);
                    if ch.len != 2 || !coreTypeUnboxed(g, f, m, m.typeOf(ch[1])) { return false; }
                    return bodyNoScopeAlloc(g, f, m, ch[0], visited, visited_len, left) &&
                        bodyNoScopeAlloc(g, f, m, ch[1], visited, visited_len, left);
                },
                _ => { return false; },
            }
        },
        apply => {
            if m.node(n.a).tag == blot_check_core::Tag.project {
                let pn = m.node(n.a);
                let sp = m.fieldSpelling(m.projection(pn.b).field);
                if sp.present && m.types.node(m.typeOf(pn.a)).tag == blot_check_types::Tag.array {
                    if sp.value == "push" {
                        return coreTypeUnboxed(g, f, m, m.typeOf(n.b)) &&
                            bodyNoScopeAlloc(g, f, m, pn.a, visited, visited_len, left) &&
                            bodyNoScopeAlloc(g, f, m, n.b, visited, visited_len, left);
                    }
                    if sp.value == "at" {
                        return coreTypeUnboxed(g, f, m, m.typeOf(id)) &&
                            bodyNoScopeAlloc(g, f, m, pn.a, visited, visited_len, left) &&
                            bodyNoScopeAlloc(g, f, m, n.b, visited, visited_len, left);
                    }
                }
            }
            return false;
        },
        call => {
            let info = m.call(id);
            for arg in info.arguments {
                if !bodyNoScopeAlloc(g, f, m, arg, visited, visited_len, left) { return false; }
            }
            if scratchScalarCallee(g, m, info) { return true; }
            let target = g.resolve(m, info.target);
            for vi in 0..visited_len {
                if visited[vi] == target { return true; }
            }
            if visited_len >= 16 || !g.hasUnit(target.unit) { return false; }
            let tm .= g.units[target.unit - 1];
            let tbody .= tm.body(target.binding);
            if !tbody || !tbody.is_function || tbody.exported { return false; }
            if tm.bodyParameters(tbody).len != info.arguments.len { return false; }
            if tbody.scheme.variables.len != 0 { return false; }
            visited[visited_len] = target;
            visited_len += 1;
            var nf_env = Fn { unit: target.unit, .. };
            return bodyNoScopeAlloc(g, nf_env, tm, tbody.root, visited, visited_len, left);
        },
        _ => { return false; },
    }
}

fn pushWorkerResult(g: Generator&, f: const Fn&, value: Val) {
    let spec = g.s.worker_specs[f.worker_spec];
    if spec.drop_param == 0xff {
        push(g, value);
        return;
    }
    let dstart = spec.drop_word_start as i64;
    for at in 0..(value.len as i64) {
        if at == dstart || at == dstart + 1 { continue; }
        lget(g, w(g, value, at));
    }
}

fn popWorkerResult(g: Generator&, f: Fn&, full_ty: Ty, drop_word_start: u32, drop_handle: Val, id: u32) -> Val, Error {
    let kinds, err = g.types.layout(full_ty);
    if err != blot_direct_types::Error.none { return neverVal(), g.typeFailure(g.units[f.unit - 1], id); }
    let dstart = drop_word_start as i64;
    let start = g.s.words.len as u32;
    for kind, at in kinds {
        if at == dstart {
            g.s.words.push(w(g, drop_handle, 0));
        } else if at == dstart + 1 {
            g.s.words.push(w(g, drop_handle, 1));
        } else {
            let loc = local(g, f, kind);
            g.s.words.push(loc);
        }
    }
    var at = kinds.len;
    while at > 0 {
        at -= 1;
        if at == dstart || at == dstart + 1 { continue; }
        lset(g, g.s.words[start + at]);
    }
    return Val { full_ty, start, kinds.len as u32 }, blot_direct_types::Error.none;
}

recursive fn collectSameSigCalls(
    g: const Generator&,
    m: const Module&,
    id: u32,
    param_count: i64,
    out: u32[8]&,
    out_len: i64&,
    budget: i64&,
) {
    if id == 0 || budget <= 0 { return; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        suite, block_, product, record, array, array_op, storage, break_ => {
            for ch in m.children(id) { collectSameSigCalls(g, m, ch, param_count, out, out_len, budget); }
        },
        bind, construct => { collectSameSigCalls(g, m, n.b, param_count, out, out_len, budget); },
        return_, project, result_associated => { collectSameSigCalls(g, m, n.a, param_count, out, out_len, budget); },
        scalar, logical, associated, apply => {
            collectSameSigCalls(g, m, n.a, param_count, out, out_len, budget);
            collectSameSigCalls(g, m, n.b, param_count, out, out_len, budget);
        },
        pattern_bind => {
            collectSameSigCalls(g, m, n.b, param_count, out, out_len, budget);
            collectSameSigCalls(g, m, n.c, param_count, out, out_len, budget);
        },
        if_stmt, if_value => {
            collectSameSigCalls(g, m, n.a, param_count, out, out_len, budget);
            collectSameSigCalls(g, m, n.b, param_count, out, out_len, budget);
            collectSameSigCalls(g, m, n.c, param_count, out, out_len, budget);
        },
        match_ => {
            for inp in m.matchInputs(id) { collectSameSigCalls(g, m, inp, param_count, out, out_len, budget); }
            for arm in m.matchArms(id) {
                collectSameSigCalls(g, m, arm.guard_, param_count, out, out_len, budget);
                collectSameSigCalls(g, m, arm.body, param_count, out, out_len, budget);
            }
        },
        loop_ => {
            let linfo = m.loopInfo(id);
            collectSameSigCalls(g, m, linfo.first, param_count, out, out_len, budget);
            collectSameSigCalls(g, m, linfo.end, param_count, out, out_len, budget);
            collectSameSigCalls(g, m, linfo.body, param_count, out, out_len, budget);
        },
        update => {
            let uinfo = m.updateInfo(id);
            collectSameSigCalls(g, m, uinfo.root, param_count, out, out_len, budget);
            collectSameSigCalls(g, m, uinfo.value, param_count, out, out_len, budget);
            for sel in m.updateSelectors(id) {
                if sel.kind == blot_check_core::UpdateKind.index { collectSameSigCalls(g, m, sel.index, param_count, out, out_len, budget); }
            }
        },
        call => {
            let info = m.call(id);
            for arg in info.arguments { collectSameSigCalls(g, m, arg, param_count, out, out_len, budget); }
            let resolved = g.resolve(m, info.target);
            if resolved.unit == m.unit && info.arguments.len == param_count {
                let b .= m.body(resolved.binding);
                if b && b.is_function && !b.exported && b.scheme.variables.len == 0 && m.bodyParameters(b).len == param_count {
                    var exists = false;
                    for i in 0..out_len { if out[i] == resolved.binding { exists = true; break; } }
                    if !exists && out_len < 8 {
                        out[out_len] = resolved.binding;
                        out_len += 1;
                    }
                }
            }
        },
        _ => {},
    }
}

fn sccMemberIndex(spec: const blot_direct_emit::WorkerSpec&, target: BindingRef) -> i64 {
    if target.unit != spec.unit { return -1; }
    for si in 0..(spec.scc_len as i64) {
        if spec.scc_bindings[si] == target.binding { return si; }
    }
    return -1;
}

// Track aliases and classify every use of array parameter `pi` across one SCC member.
// `ret_pos`: -2 = unknown yet, -1 = sole return, 0..7 = tuple element index, -3 = conflict/not returned.
recursive fn scanSccParamAliases(
    g: Generator&,
    m: const Module&,
    spec: const blot_direct_emit::WorkerSpec&,
    pi: i64,
    pty: Ty,
    own_param: bool,
    id: u32,
    same: u32[64]&,
    same_len: i64&,
    changed: bool&,
    written: bool&,
    resized: bool&,
    escaped: bool&,
    ret_pos: i64&,
    budget: i64&,
) {
    if id == 0 || escaped { return; }
    if budget <= 0 { escaped = true; return; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        constant, panic => {},
        reference => {
            // Bare reference in value position escapes unless handled by parent!
            let b = localRef(m, id);
            if b != 0 && inBindingSet(same, same_len, b) { escaped = true; }
        },
        suite, block_ => {
            for ch in m.children(id) {
                scanSccParamAliases(g, m, spec, pi, pty, own_param, ch, same, same_len, changed, written, resized, escaped, ret_pos, budget);
            }
        },
        bind => {
            if n.c >= 2 {
                scanSccParamAliases(g, m, spec, pi, pty, own_param, n.b, same, same_len, changed, written, resized, escaped, ret_pos, budget);
                return;
            }
            let rhs = n.b;
            let rn = m.node(rhs);
            // Direct alias copy `let x = p`
            if rn.tag == blot_check_core::Tag.reference {
                let rb = localRef(m, rhs);
                if rb != 0 && inBindingSet(same, same_len, rb) {
                    if !inBindingSet(same, same_len, n.a) { addBindingSet(same, same_len, n.a); changed = true; }
                    return;
                }
            }
            // Indexed update `p[i] := v`
            if rn.tag == blot_check_core::Tag.update {
                let uinfo = m.updateInfo(rhs);
                let sels = m.updateSelectors(rhs);
                let rb = localRef(m, uinfo.root);
                if rb != 0 && inBindingSet(same, same_len, rb) {
                    if sels.len > 0 && sels[0].kind == blot_check_core::UpdateKind.index {
                        written = true;
                        for sel in sels {
                            if sel.kind == blot_check_core::UpdateKind.index {
                                scanSccParamAliases(g, m, spec, pi, pty, own_param, sel.index, same, same_len, changed, written, resized, escaped, ret_pos, budget);
                            }
                        }
                        scanSccParamAliases(g, m, spec, pi, pty, own_param, uinfo.value, same, same_len, changed, written, resized, escaped, ret_pos, budget);
                        if !inBindingSet(same, same_len, n.a) { addBindingSet(same, same_len, n.a); changed = true; }
                        return;
                    }
                    escaped = true;
                    return;
                }
            }
            // `@storage.push p val`
            if rn.tag == blot_check_core::Tag.storage {
                let op_k, ok = blot_check_storage_ops::opFromCode(rn.c);
                if ok == blot_error::Error.none && op_k == blot_check_storage_ops::Op.push {
                    let ch = m.children(rhs);
                    if ch.len == 2 && inBindingSet(same, same_len, localRef(m, ch[0])) {
                        written = true;
                        resized = true;
                        scanSccParamAliases(g, m, spec, pi, pty, own_param, ch[1], same, same_len, changed, written, resized, escaped, ret_pos, budget);
                        if !inBindingSet(same, same_len, n.a) { addBindingSet(same, same_len, n.a); changed = true; }
                        return;
                    }
                }
            }
            // `p.push val`
            if rn.tag == blot_check_core::Tag.apply && m.node(rn.a).tag == blot_check_core::Tag.project {
                let pn = m.node(rn.a);
                let sp = m.fieldSpelling(m.projection(pn.b).field);
                if sp.present && sp.value == "push" && inBindingSet(same, same_len, localRef(m, pn.a)) {
                    written = true;
                    resized = true;
                    scanSccParamAliases(g, m, spec, pi, pty, own_param, rn.b, same, same_len, changed, written, resized, escaped, ret_pos, budget);
                    if !inBindingSet(same, same_len, n.a) { addBindingSet(same, same_len, n.a); changed = true; }
                    return;
                }
            }
            // Sole-return SCC call `p := self_or_peer ... p ...`
            if rn.tag == blot_check_core::Tag.call {
                let info = m.call(rhs);
                let target = g.resolve(m, info.target);
                if sccMemberIndex(spec, target) >= 0 && pi < info.arguments.len && inBindingSet(same, same_len, localRef(m, info.arguments[pi])) {
                    for arg, ai in info.arguments {
                        if ai == pi { continue; }
                        scanSccParamAliases(g, m, spec, pi, pty, own_param, arg, same, same_len, changed, written, resized, escaped, ret_pos, budget);
                    }
                    if m.types.node(m.typeOf(rhs)).tag == blot_check_types::Tag.array {
                        if !inBindingSet(same, same_len, n.a) { addBindingSet(same, same_len, n.a); changed = true; }
                        return;
                    }
                    // Otherwise handled via pattern_bind or non-returning Mode R!
                    return;
                }
            }
            scanSccParamAliases(g, m, spec, pi, pty, own_param, rhs, same, same_len, changed, written, resized, escaped, ret_pos, budget);
        },
        pattern_bind => {
            let rhs = n.b;
            let rn = m.node(rhs);
            let pat = m.pattern(n.a);
            if pat.tag == blot_check_core::PatternTag.product && rn.tag == blot_check_core::Tag.call {
                let info = m.call(rhs);
                let target = g.resolve(m, info.target);
                let pchildren = m.patternChildren(n.a);
                // Tuple destructuring of an SCC call: `let (p1, l) = build_tree p (d - 1)`
                if sccMemberIndex(spec, target) >= 0 && pi < info.arguments.len && inBindingSet(same, same_len, localRef(m, info.arguments[pi])) {
                    for arg, ai in info.arguments {
                        if ai == pi { continue; }
                        scanSccParamAliases(g, m, spec, pi, pty, own_param, arg, same, same_len, changed, written, resized, escaped, ret_pos, budget);
                    }
                    // If return element `ei` has array type matching param `pi`, track it as alias (ret_pos verified at return_ sites).
                    if own_param {
                        if ret_pos >= 0 && ret_pos < pchildren.len && m.pattern(pchildren[ret_pos]).tag == blot_check_core::PatternTag.bind {
                            let nb = m.pattern(pchildren[ret_pos]).a;
                            if !inBindingSet(same, same_len, nb) { addBindingSet(same, same_len, nb); changed = true; }
                        } else if ret_pos == -2 {
                            for pc, pci in pchildren {
                                if m.pattern(pc).tag == blot_check_core::PatternTag.bind {
                                    let nb = m.pattern(pc).a;
                                    let nb_ty, nb_err = g.types.lower(m, m.binding(nb).ty, Env {});
                                    if nb_err == blot_direct_types::Error.none && nb_ty == pty {
                                        if !inBindingSet(same, same_len, nb) { addBindingSet(same, same_len, nb); changed = true; }
                                        break;
                                    } else if nb_err != blot_direct_types::Error.none {
                                        g.dropFailure();
                                    }
                                }
                            }
                        }
                    }
                    scanSccParamAliases(g, m, spec, pi, pty, own_param, n.c, same, same_len, changed, written, resized, escaped, ret_pos, budget);
                    return;
                }
                // Tuple destructuring of a small inlined helper (e.g. `let (t1, l1) = push_ch text tlen ch`)
                if g.hasUnit(target.unit) && canInlineTarget(g, target, 0) {
                    let tm .= g.units[target.unit - 1];
                    let tbody .= tm.body(target.binding);
                    if tbody && tbody.is_function && !tbody.exported && tm.bodyParameters(tbody).len == info.arguments.len {
                        let tparams = tm.bodyParameters(tbody);
                        var matched_arg: i64 = -1;
                        for arg, ai in info.arguments {
                            if inBindingSet(same, same_len, localRef(m, arg)) {
                                if matched_arg >= 0 { escaped = true; return; }
                                matched_arg = ai;
                            } else {
                                scanSccParamAliases(g, m, spec, pi, pty, own_param, arg, same, same_len, changed, written, resized, escaped, ret_pos, budget);
                            }
                        }
                        if matched_arg >= 0 {
                            var found_ret: i64 = -1;
                            for pc, pci in pchildren {
                                if m.pattern(pc).tag == blot_check_core::PatternTag.bind &&
                                    calleeReturnsParamAt(g, tm, tbody.root, tparams[matched_arg].binding, pci, 0) {
                                    found_ret = pci;
                                    let nb = m.pattern(pc).a;
                                    if !inBindingSet(same, same_len, nb) { addBindingSet(same, same_len, nb); changed = true; }
                                    break;
                                }
                            }
                            if found_ret < 0 { escaped = true; return; }
                            var hbud: i64 = 256;
                            if !noStorageResize(g, tm, tbody.root, hbud) { written = true; resized = true; }
                            else { written = true; }
                            scanSccParamAliases(g, m, spec, pi, pty, own_param, n.c, same, same_len, changed, written, resized, escaped, ret_pos, budget);
                            return;
                        }
                    }
                }
            }
            scanSccParamAliases(g, m, spec, pi, pty, own_param, n.b, same, same_len, changed, written, resized, escaped, ret_pos, budget);
            scanSccParamAliases(g, m, spec, pi, pty, own_param, n.c, same, same_len, changed, written, resized, escaped, ret_pos, budget);
        },
        if_stmt, if_value => {
            scanSccParamAliases(g, m, spec, pi, pty, own_param, n.a, same, same_len, changed, written, resized, escaped, ret_pos, budget);
            scanSccParamAliases(g, m, spec, pi, pty, own_param, n.b, same, same_len, changed, written, resized, escaped, ret_pos, budget);
            scanSccParamAliases(g, m, spec, pi, pty, own_param, n.c, same, same_len, changed, written, resized, escaped, ret_pos, budget);
            for merge in m.branchMerges(id) {
                let in_t = inBindingSet(same, same_len, merge.then_binding);
                let in_e = inBindingSet(same, same_len, merge.else_binding);
                if in_t && in_e {
                    if !inBindingSet(same, same_len, merge.result) { addBindingSet(same, same_len, merge.result); changed = true; }
                } else if in_t || in_e {
                    escaped = true;
                }
            }
        },
        match_ => {
            for inp in m.matchInputs(id) {
                scanSccParamAliases(g, m, spec, pi, pty, own_param, inp, same, same_len, changed, written, resized, escaped, ret_pos, budget);
            }
            for arm in m.matchArms(id) {
                scanSccParamAliases(g, m, spec, pi, pty, own_param, arm.guard_, same, same_len, changed, written, resized, escaped, ret_pos, budget);
                scanSccParamAliases(g, m, spec, pi, pty, own_param, arm.body, same, same_len, changed, written, resized, escaped, ret_pos, budget);
            }
            for merge in m.branchMerges(id) {
                let in_t = inBindingSet(same, same_len, merge.then_binding);
                let in_e = inBindingSet(same, same_len, merge.else_binding);
                if in_t && in_e {
                    if !inBindingSet(same, same_len, merge.result) { addBindingSet(same, same_len, merge.result); changed = true; }
                } else if in_t || in_e {
                    escaped = true;
                }
            }
        },
        loop_ => {
            let linfo = m.loopInfo(id);
            scanSccParamAliases(g, m, spec, pi, pty, own_param, linfo.first, same, same_len, changed, written, resized, escaped, ret_pos, budget);
            scanSccParamAliases(g, m, spec, pi, pty, own_param, linfo.end, same, same_len, changed, written, resized, escaped, ret_pos, budget);
            for carry in m.loopCarries(id) {
                if inBindingSet(same, same_len, carry.incoming) {
                    if !inBindingSet(same, same_len, carry.iteration) { addBindingSet(same, same_len, carry.iteration); changed = true; }
                    if carry.backedge == 0 || inBindingSet(same, same_len, carry.backedge) {
                        if carry.outgoing != 0 && !inBindingSet(same, same_len, carry.outgoing) {
                            addBindingSet(same, same_len, carry.outgoing);
                            changed = true;
                        }
                    }
                }
            }
            scanSccParamAliases(g, m, spec, pi, pty, own_param, linfo.body, same, same_len, changed, written, resized, escaped, ret_pos, budget);
            for carry in m.loopCarries(id) {
                if inBindingSet(same, same_len, carry.incoming) && carry.backedge != 0 && !inBindingSet(same, same_len, carry.backedge) {
                    // May still resolve on next fixed-point pass; caller verifies after fixpoint.
                }
            }
        },
        break_ => {
            for ch in m.children(id) {
                if inBindingSet(same, same_len, localRef(m, ch)) { continue; }
                scanSccParamAliases(g, m, spec, pi, pty, own_param, ch, same, same_len, changed, written, resized, escaped, ret_pos, budget);
            }
        },
        return_ => {
            if n.a == 0 { return; }
            let rn = m.node(n.a);
            if rn.tag == blot_check_core::Tag.suite || rn.tag == blot_check_core::Tag.block_ {
                scanSccParamAliases(g, m, spec, pi, pty, own_param, n.a, same, same_len, changed, written, resized, escaped, ret_pos, budget);
                return;
            }
            if rn.tag == blot_check_core::Tag.reference && inBindingSet(same, same_len, localRef(m, n.a)) {
                if ret_pos == -2 { ret_pos = -1; }
                else if ret_pos != -1 { ret_pos = -3; escaped = true; }
                return;
            }
            if rn.tag == blot_check_core::Tag.product {
                let ch = m.children(n.a);
                var hit: i64 = -1;
                for c, ci in ch {
                    if inBindingSet(same, same_len, localRef(m, c)) {
                        if hit >= 0 { ret_pos = -3; escaped = true; return; }
                        hit = ci;
                    } else {
                        scanSccParamAliases(g, m, spec, pi, pty, own_param, c, same, same_len, changed, written, resized, escaped, ret_pos, budget);
                    }
                }
                if hit >= 0 {
                    if ret_pos == -2 { ret_pos = hit; }
                    else if ret_pos != hit { ret_pos = -3; escaped = true; }
                    return;
                }
                return;
            }
            // Tail call to an SCC member preserves ret_pos!
            if rn.tag == blot_check_core::Tag.call {
                let info = m.call(n.a);
                let target = g.resolve(m, info.target);
                if sccMemberIndex(spec, target) >= 0 && pi < info.arguments.len && inBindingSet(same, same_len, localRef(m, info.arguments[pi])) {
                    for arg, ai in info.arguments {
                        if ai == pi { continue; }
                        scanSccParamAliases(g, m, spec, pi, pty, own_param, arg, same, same_len, changed, written, resized, escaped, ret_pos, budget);
                    }
                    return;
                }
            }
            scanSccParamAliases(g, m, spec, pi, pty, own_param, n.a, same, same_len, changed, written, resized, escaped, ret_pos, budget);
        },
        array_op => {
            let aop = m.arrayOperation(id);
            let ch = m.children(id);
            if (aop == blot_backend_collection_ops::Op.get || aop == blot_backend_collection_ops::Op.length) &&
                ch.len > 0 && inBindingSet(same, same_len, localRef(m, ch[0])) {
                for ci in 1..ch.len {
                    scanSccParamAliases(g, m, spec, pi, pty, own_param, ch[ci], same, same_len, changed, written, resized, escaped, ret_pos, budget);
                }
                return;
            }
            for c in ch { scanSccParamAliases(g, m, spec, pi, pty, own_param, c, same, same_len, changed, written, resized, escaped, ret_pos, budget); }
        },
        storage => {
            let op_k, ok = blot_check_storage_ops::opFromCode(n.c);
            let ch = m.children(id);
            if ok == blot_error::Error.none && (op_k == blot_check_storage_ops::Op.read || op_k == blot_check_storage_ops::Op.length) &&
                ch.len > 0 && inBindingSet(same, same_len, localRef(m, ch[0])) {
                for ci in 1..ch.len {
                    scanSccParamAliases(g, m, spec, pi, pty, own_param, ch[ci], same, same_len, changed, written, resized, escaped, ret_pos, budget);
                }
                return;
            }
            for c in ch { scanSccParamAliases(g, m, spec, pi, pty, own_param, c, same, same_len, changed, written, resized, escaped, ret_pos, budget); }
        },
        project => {
            let sp = m.fieldSpelling(m.projection(n.b).field);
            if sp.present && sp.value == "length" && inBindingSet(same, same_len, localRef(m, n.a)) { return; }
            scanSccParamAliases(g, m, spec, pi, pty, own_param, n.a, same, same_len, changed, written, resized, escaped, ret_pos, budget);
        },
        call => {
            let info = m.call(id);
            let target = g.resolve(m, info.target);
            if sccMemberIndex(spec, target) >= 0 && pi < info.arguments.len && inBindingSet(same, same_len, localRef(m, info.arguments[pi])) {
                for arg, ai in info.arguments {
                    if ai == pi { continue; }
                    scanSccParamAliases(g, m, spec, pi, pty, own_param, arg, same, same_len, changed, written, resized, escaped, ret_pos, budget);
                }
                return;
            }
            // Read-only non-escaping inlined helper call (e.g. `skip text tlen pos`)
            if g.hasUnit(target.unit) && canInlineTarget(g, target, 0) {
                let tm .= g.units[target.unit - 1];
                let tbody .= tm.body(target.binding);
                if tbody && tbody.is_function && !tbody.exported && tm.bodyParameters(tbody).len == info.arguments.len {
                    var nrb: i64 = 256;
                    if noStorageResize(g, tm, tbody.root, nrb) && m.types.node(m.typeOf(id)).tag != blot_check_types::Tag.array {
                        var has_alias_arg = false;
                        for arg in info.arguments {
                            if inBindingSet(same, same_len, localRef(m, arg)) { has_alias_arg = true; }
                            else { scanSccParamAliases(g, m, spec, pi, pty, own_param, arg, same, same_len, changed, written, resized, escaped, ret_pos, budget); }
                        }
                        if has_alias_arg { return; }
                    }
                }
            }
            for arg in info.arguments {
                scanSccParamAliases(g, m, spec, pi, pty, own_param, arg, same, same_len, changed, written, resized, escaped, ret_pos, budget);
            }
        },
        scalar, logical, associated, apply => {
            scanSccParamAliases(g, m, spec, pi, pty, own_param, n.a, same, same_len, changed, written, resized, escaped, ret_pos, budget);
            scanSccParamAliases(g, m, spec, pi, pty, own_param, n.b, same, same_len, changed, written, resized, escaped, ret_pos, budget);
        },
        product, record, array => {
            for c in m.children(id) { scanSccParamAliases(g, m, spec, pi, pty, own_param, c, same, same_len, changed, written, resized, escaped, ret_pos, budget); }
        },
        construct => { scanSccParamAliases(g, m, spec, pi, pty, own_param, n.b, same, same_len, changed, written, resized, escaped, ret_pos, budget); },
        update => {
            let uinfo = m.updateInfo(id);
            scanSccParamAliases(g, m, spec, pi, pty, own_param, uinfo.root, same, same_len, changed, written, resized, escaped, ret_pos, budget);
            scanSccParamAliases(g, m, spec, pi, pty, own_param, uinfo.value, same, same_len, changed, written, resized, escaped, ret_pos, budget);
            for sel in m.updateSelectors(id) {
                if sel.kind == blot_check_core::UpdateKind.index {
                    scanSccParamAliases(g, m, spec, pi, pty, own_param, sel.index, same, same_len, changed, written, resized, escaped, ret_pos, budget);
                }
            }
        },
        _ => { escaped = true; },
    }
}

recursive fn verifySccLoopBreaks(m: const Module&, loop_id: u32, carry_at: i64, id: u32, same: const u32[64]&, same_len: i64, budget: i64&) -> bool {
    if id == 0 { return true; }
    if budget <= 0 { return false; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        suite, block_, product, record, array, array_op, storage => {
            for c in m.children(id) { if !verifySccLoopBreaks(m, loop_id, carry_at, c, same, same_len, budget) { return false; } }
            return true;
        },
        bind, construct => { return verifySccLoopBreaks(m, loop_id, carry_at, n.b, same, same_len, budget); },
        return_, project => { return verifySccLoopBreaks(m, loop_id, carry_at, n.a, same, same_len, budget); },
        pattern_bind => { return verifySccLoopBreaks(m, loop_id, carry_at, n.b, same, same_len, budget) && verifySccLoopBreaks(m, loop_id, carry_at, n.c, same, same_len, budget); },
        if_stmt, if_value => {
            return verifySccLoopBreaks(m, loop_id, carry_at, n.a, same, same_len, budget) &&
                verifySccLoopBreaks(m, loop_id, carry_at, n.b, same, same_len, budget) &&
                verifySccLoopBreaks(m, loop_id, carry_at, n.c, same, same_len, budget);
        },
        match_ => {
            for arm in m.matchArms(id) { if !verifySccLoopBreaks(m, loop_id, carry_at, arm.body, same, same_len, budget) { return false; } }
            return true;
        },
        loop_ => { return verifySccLoopBreaks(m, loop_id, carry_at, m.loopInfo(id).body, same, same_len, budget); },
        break_ => {
            if n.a == loop_id {
                let vals = m.breakValues(id);
                if carry_at >= vals.len || !inBindingSet(same, same_len, localRef(m, vals[carry_at])) { return false; }
            }
            return true;
        },
        _ => { return true; },
    }
}

recursive fn verifySccParamLoopCarries(m: const Module&, id: u32, same: const u32[64]&, same_len: i64, budget: i64&) -> bool {
    if id == 0 { return true; }
    if budget <= 0 { return false; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        suite, block_, product, record, array, array_op, storage, break_ => {
            for c in m.children(id) { if !verifySccParamLoopCarries(m, c, same, same_len, budget) { return false; } }
            return true;
        },
        bind, construct => { return verifySccParamLoopCarries(m, n.b, same, same_len, budget); },
        return_, project => { return verifySccParamLoopCarries(m, n.a, same, same_len, budget); },
        pattern_bind => { return verifySccParamLoopCarries(m, n.b, same, same_len, budget) && verifySccParamLoopCarries(m, n.c, same, same_len, budget); },
        if_stmt, if_value => {
            return verifySccParamLoopCarries(m, n.a, same, same_len, budget) &&
                verifySccParamLoopCarries(m, n.b, same, same_len, budget) &&
                verifySccParamLoopCarries(m, n.c, same, same_len, budget);
        },
        match_ => {
            for arm in m.matchArms(id) { if !verifySccParamLoopCarries(m, arm.body, same, same_len, budget) { return false; } }
            return true;
        },
        loop_ => {
            for carry, ci in m.loopCarries(id) {
                if inBindingSet(same, same_len, carry.incoming) {
                    if carry.backedge != 0 && !inBindingSet(same, same_len, carry.backedge) { return false; }
                    var bbud: i64 = 512;
                    if !verifySccLoopBreaks(m, id, ci, m.loopInfo(id).body, same, same_len, bbud) { return false; }
                }
            }
            return verifySccParamLoopCarries(m, m.loopInfo(id).body, same, same_len, budget);
        },
        _ => { return true; },
    }
}

fn analyzeWorkerSCC(g: Generator&, id: u32) -> blot_direct_emit::WorkerSpec, bool {
    var spec = blot_direct_emit::WorkerSpec {};
    let inst = g.s.instances[id];
    let key = inst.key;
    if key.kind != blot_direct_emit::InstanceKind.named || inst.closure || inst.inferring || key.evidence_context != 0 {
        return spec, false;
    }
    if g.s.has_rt && g.s.rt.has_fork { return spec, false; }
    if !g.hasUnit(key.unit) { return spec, false; }
    let m .= g.units[key.unit - 1];
    let body .= m.body(key.id);
    if !body || !body.is_function || body.exported || body.scheme.variables.len != 0 { return spec, false; }
    let param_count = inst.parameters.len as i64;
    if param_count == 0 || param_count > 8 { return spec, false; }
    // Must have at least one plain-element Tag.array parameter.
    var has_arr_param = false;
    for pi in 0..param_count {
        let pty = g.s.tys[inst.parameters.start + pi];
        if tagOf(g, pty) == blot_direct_types::Tag.array {
            let elem_holds, herr = g.contentsHoldMemory(g.types.node(pty).a);
            if herr == blot_direct_types::Error.none && !elem_holds { has_arr_param = true; break; }
        }
    }
    if !has_arr_param { return spec, false; }

    // Build same-unit candidate graph of functions with matching lowered signature.
    var cands: u32[8] = [0; 8];
    cands[0] = key.id;
    var cands_len: i64 = 1;
    var adj: u8[64] = [0; 64]; // adj[a * 8 + b] == 1 iff cands[a] calls cands[b]
    var head: i64 = 0;
    while head < cands_len {
        let cur_b = cands[head];
        let cur_body .= m.body(cur_b);
        if cur_body {
            var calls: u32[8] = [0; 8];
            var calls_len: i64 = 0;
            var cbud: i64 = 512;
            collectSameSigCalls(g, m, cur_body.root, param_count, calls, calls_len, cbud);
            for ci in 0..calls_len {
                let nb = calls[ci];
                // Verify exact same lowered function type.
                let nb_ty, nerr = g.types.lower(m, m.binding(nb).ty, Env {});
                if nerr != blot_direct_types::Error.none { g.dropFailure(); continue; }
                if nb_ty != key.ty { continue; }
                var idx: i64 = -1;
                for ki in 0..cands_len { if cands[ki] == nb { idx = ki; break; } }
                if idx < 0 {
                    if cands_len >= 8 { continue; }
                    idx = cands_len;
                    cands[cands_len] = nb;
                    cands_len += 1;
                }
                adj[head * 8 + idx] = 1;
            }
        }
        head += 1;
    }
    // Transitive closure of `adj` (8x8 Warshall).
    var reach: u8[64] = adj;
    for k in 0..cands_len {
        for i in 0..cands_len {
            if reach[i * 8 + k] == 0 { continue; }
            for j in 0..cands_len {
                if reach[k * 8 + j] != 0 { reach[i * 8 + j] = 1; }
            }
        }
    }
    // Must be recursive (0 reaches 0 in >= 1 step).
    if reach[0] == 0 { return spec, false; }
    // Collect SCC of node 0 (capped at 4 members).
    spec.unit = key.unit;
    spec.param_count = param_count as u32;
    spec.scc_bindings[0] = key.id;
    spec.scc_len = 1;
    for i in 1..cands_len {
        if reach[i] != 0 && reach[i * 8] != 0 {
            if spec.scc_len >= 4 { return spec, false; }
            spec.scc_bindings[spec.scc_len] = cands[i];
            spec.scc_len += 1;
        }
    }

    // Classify each plain-element Tag.array parameter across the entire SCC.
    var any_mode = false;
    var chosen_drop: u8 = 0xff;
    var chosen_ret_pos: i64 = -2;
    for pi in 0..param_count {
        let pty = g.s.tys[inst.parameters.start + pi];
        if tagOf(g, pty) != blot_direct_types::Tag.array { continue; }
        let elem_holds, herr = g.contentsHoldMemory(g.types.node(pty).a);
        if herr != blot_direct_types::Error.none || elem_holds { continue; }
        var own_all = true;
        var written = false;
        var resized = false;
        var escaped = false;
        var ret_pos: i64 = -2;
        for si in 0..(spec.scc_len as i64) {
            let sb = spec.scc_bindings[si];
            let sb_body .= m.body(sb);
            if !sb_body { escaped = true; break; }
            let own_mask = m.binding(sb).capability_parameters.own;
            let own_param = ((own_mask >> (pi as u64)) & 1) != 0;
            if !own_param { own_all = false; }
            let sp = m.bodyParameters(sb_body)[pi].binding;
            var same: u32[64] = [0; 64];
            var same_len: i64 = 0;
            addBindingSet(same, same_len, sp);
            for iter in 0..6 {
                var changed = false;
                var bud: i64 = 1024;
                scanSccParamAliases(g, m, spec, pi, pty, own_param, sb_body.root, same, same_len, changed, written, resized, escaped, ret_pos, bud);
                if escaped || !changed { break; }
            }
            if !escaped {
                var vbud: i64 = 512;
                if !verifySccParamLoopCarries(m, sb_body.root, same, same_len, vbud) { escaped = true; }
            }
            if escaped { break; }
        }
        if escaped { continue; }
        if !written && !resized && ret_pos == -2 {
            spec.param_modes[pi] = 1; // Mode R read-only
            any_mode = true;
        } else if own_all && (ret_pos == -1 || ret_pos >= 0) && chosen_drop == 0xff {
            // Verify result layout has this exact array type at `ret_pos`.
            let res_ty = inst.result;
            var wstart: u32 = 0;
            var ret_ok = false;
            if ret_pos == -1 {
                ret_ok = res_ty == pty;
                wstart = 0;
            } else if tagOf(g, res_ty) == blot_direct_types::Tag.tuple {
                let tn = g.types.node(res_ty);
                if ret_pos < (tn.b as i64) && g.types.words[tn.a + ret_pos] == pty {
                    ret_ok = true;
                    for ei in 0..ret_pos {
                        let el, lerr = g.types.layout(g.types.words[tn.a + ei]);
                        if lerr != blot_direct_types::Error.none { ret_ok = false; break; }
                        wstart += el.len as u32;
                    }
                }
            }
            if ret_ok {
                spec.param_modes[pi] = if resized { 3 } else { 2 };
                chosen_drop = pi as u8;
                chosen_ret_pos = ret_pos;
                spec.drop_param = chosen_drop;
                spec.drop_ret_pos = chosen_ret_pos as! i8;
                spec.drop_word_start = wstart;
                any_mode = true;
            }
        }
    }
    if !any_mode { return spec, false; }

    // Check `no_scope_alloc` across the entire SCC.
    var visited: BindingRef[16] = [BindingRef { 0, 0 }; 16];
    var visited_len: i64 = 0;
    for si in 0..(spec.scc_len as i64) {
        visited[visited_len] = BindingRef { key.unit, spec.scc_bindings[si] };
        visited_len += 1;
    }
    var nsa = true;
    for si in 0..(spec.scc_len as i64) {
        let sb_body .= m.body(spec.scc_bindings[si]);
        if !sb_body { nsa = false; break; }
        var nf_chk = Fn { unit: key.unit, .. };
        var nbud: i64 = 1024;
        if !bodyNoScopeAlloc(g, nf_chk, m, sb_body.root, visited, visited_len, nbud) {
            nsa = false;
            break;
        }
    }
    spec.no_scope_alloc = nsa;
    return spec, true;
}

recursive fn countAstNodesAndLoops(m: const Module&, id: u32, count: i64&, has_loop: bool&) {
    if id == 0 || count > 96 { return; }
    count += 1;
    let n = m.node(id);
    match n.tag {
        loop_, spark => { has_loop = true; },
        suite, block_, product, record, array, array_op, storage, break_ => {
            for c in m.children(id) { countAstNodesAndLoops(m, c, count, has_loop); }
        },
        bind, construct => { countAstNodesAndLoops(m, n.b, count, has_loop); },
        return_, project => { countAstNodesAndLoops(m, n.a, count, has_loop); },
        scalar, logical, associated, apply => {
            countAstNodesAndLoops(m, n.a, count, has_loop);
            countAstNodesAndLoops(m, n.b, count, has_loop);
        },
        pattern_bind => {
            countAstNodesAndLoops(m, n.b, count, has_loop);
            countAstNodesAndLoops(m, n.c, count, has_loop);
        },
        if_stmt, if_value => {
            countAstNodesAndLoops(m, n.a, count, has_loop);
            countAstNodesAndLoops(m, n.b, count, has_loop);
            countAstNodesAndLoops(m, n.c, count, has_loop);
        },
        match_ => {
            for inp in m.matchInputs(id) { countAstNodesAndLoops(m, inp, count, has_loop); }
            for arm in m.matchArms(id) {
                countAstNodesAndLoops(m, arm.guard_, count, has_loop);
                countAstNodesAndLoops(m, arm.body, count, has_loop);
            }
        },
        call => {
            for arg in m.call(id).arguments { countAstNodesAndLoops(m, arg, count, has_loop); }
        },
        update => {
            let u = m.updateInfo(id);
            countAstNodesAndLoops(m, u.root, count, has_loop);
            countAstNodesAndLoops(m, u.value, count, has_loop);
            for sel in m.updateSelectors(id) {
                if sel.kind == blot_check_core::UpdateKind.index { countAstNodesAndLoops(m, sel.index, count, has_loop); }
            }
        },
        _ => {},
    }
}

recursive fn checkPeelCalls(
    g: const Generator&,
    m: const Module&,
    id: u32,
    target: BindingRef,
    param_count: i64,
    d_binding: u32,
    d_idx: i64,
    allow_self: bool,
    self_count: i64&,
    ok: bool&,
) {
    if id == 0 || !ok { return; }
    let n = m.node(id);
    match n.tag {
        suite, block_, product, record, array, array_op, storage, break_ => {
            for c in m.children(id) { checkPeelCalls(g, m, c, target, param_count, d_binding, d_idx, allow_self, self_count, ok); }
        },
        bind, construct => { checkPeelCalls(g, m, n.b, target, param_count, d_binding, d_idx, allow_self, self_count, ok); },
        return_, project => { checkPeelCalls(g, m, n.a, target, param_count, d_binding, d_idx, allow_self, self_count, ok); },
        scalar, logical, associated, apply => {
            checkPeelCalls(g, m, n.a, target, param_count, d_binding, d_idx, allow_self, self_count, ok);
            checkPeelCalls(g, m, n.b, target, param_count, d_binding, d_idx, allow_self, self_count, ok);
        },
        pattern_bind => {
            checkPeelCalls(g, m, n.b, target, param_count, d_binding, d_idx, allow_self, self_count, ok);
            checkPeelCalls(g, m, n.c, target, param_count, d_binding, d_idx, allow_self, self_count, ok);
        },
        if_stmt, if_value => {
            checkPeelCalls(g, m, n.a, target, param_count, d_binding, d_idx, allow_self, self_count, ok);
            checkPeelCalls(g, m, n.b, target, param_count, d_binding, d_idx, allow_self, self_count, ok);
            checkPeelCalls(g, m, n.c, target, param_count, d_binding, d_idx, allow_self, self_count, ok);
        },
        call => {
            let info = m.call(id);
            for arg in info.arguments { checkPeelCalls(g, m, arg, target, param_count, d_binding, d_idx, allow_self, self_count, ok); }
            if g.resolve(m, info.target) == target {
                if !allow_self || info.arguments.len != param_count || d_idx >= info.arguments.len { ok = false; return; }
                let d_arg = m.node(info.arguments[d_idx]);
                if d_arg.tag != blot_check_core::Tag.scalar || d_arg.op != blot_check_core::Op.sub ||
                    localRef(m, d_arg.a) != d_binding || d_arg.b == 0 ||
                    m.node(d_arg.b).tag != blot_check_core::Tag.constant || m.node(d_arg.b).a != 1 {
                    ok = false;
                    return;
                }
                self_count += 1;
            }
        },
        _ => {},
    }
}

fn tryDetectLeafPeel(
    g: const Generator&,
    m: const Module&,
    root: u32,
    target: BindingRef,
    param_bindings: const u32[8]&,
    param_tys: const Ty[8]&,
    param_count: i64,
    out_d_idx: i64&,
    out_suite: u32&,
    out_if_pos: i64&,
) -> bool {
    var cur = root;
    for step in 0..6 {
        let n = m.node(cur);
        if n.tag == blot_check_core::Tag.return_ && n.a != 0 { cur = n.a; }
        else if (n.tag == blot_check_core::Tag.block_ || n.tag == blot_check_core::Tag.suite) && n.b == 1 { cur = m.children(cur)[0]; }
        else { break; }
    }
    let cur_tag = m.node(cur).tag;
    if cur_tag != blot_check_core::Tag.suite && cur_tag != blot_check_core::Tag.block_ { return false; }
    let ch = m.children(cur);
    if ch.len < 2 { return false; }
    var total_nodes: i64 = 0;
    var has_loop = false;
    countAstNodesAndLoops(m, cur, total_nodes, has_loop);
    if has_loop || total_nodes > 72 { return false; }
    var if_pos: i64 = -1;
    let max_prefix = if ch.len - 1 < 6 { ch.len - 1 } else { 6 };
    for ci in 0..max_prefix {
        let cn = m.node(ch[ci]);
        if cn.tag == blot_check_core::Tag.if_stmt {
            if_pos = ci;
            break;
        }
        if cn.tag != blot_check_core::Tag.bind || cn.c >= 2 { return false; }
    }
    if if_pos < 0 { return false; }
    let if_id = ch[if_pos];
    let if_n = m.node(if_id);
    if if_n.c != 0 { return false; }
    let cond_n = m.node(if_n.a);
    if cond_n.tag != blot_check_core::Tag.scalar || cond_n.op != blot_check_core::Op.equal { return false; }
    var d_b: u32 = 0;
    if localRef(m, cond_n.a) != 0 && cond_n.b != 0 && m.node(cond_n.b).tag == blot_check_core::Tag.constant && m.node(cond_n.b).a == 0 {
        d_b = localRef(m, cond_n.a);
    } else if localRef(m, cond_n.b) != 0 && cond_n.a != 0 && m.node(cond_n.a).tag == blot_check_core::Tag.constant && m.node(cond_n.a).a == 0 {
        d_b = localRef(m, cond_n.b);
    } else {
        return false;
    }
    var d_idx: i64 = -1;
    for pi in 0..param_count {
        if pi < 8 && param_bindings[pi] == d_b && param_tys[pi] == blot_direct_types::u32_ { d_idx = pi; break; }
    }
    if d_idx < 0 { return false; }
    var leaf_nodes: i64 = 0;
    var leaf_loop = false;
    countAstNodesAndLoops(m, if_n.b, leaf_nodes, leaf_loop);
    if leaf_loop || leaf_nodes > 32 { return false; }
    // Verify prefix and leaf have zero self-calls, and leaf always returns.
    if !nodeAlwaysReturns(m, if_n.b, 0) { return false; }
    var ok = true;
    var dummy_cnt: i64 = 0;
    for ci in 0..if_pos {
        checkPeelCalls(g, m, ch[ci], target, param_count, d_b, d_idx, false, dummy_cnt, ok);
    }
    checkPeelCalls(g, m, if_n.b, target, param_count, d_b, d_idx, false, dummy_cnt, ok);
    if !ok { return false; }
    var self_cnt: i64 = 0;
    for ci in (if_pos + 1)..ch.len {
        checkPeelCalls(g, m, ch[ci], target, param_count, d_b, d_idx, true, self_cnt, ok);
    }
    if !ok || self_cnt == 0 || self_cnt > 4 { return false; }
    out_d_idx = d_idx;
    out_suite = cur;
    out_if_pos = if_pos;
    return true;
}

recursive fn emitPeelLeafCall(g: Generator&, f: Fn&, direct: Vals, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let key = g.s.instances[f.instance_id].key;
    let body .= m.body(key.id);
    if !body { return neverVal(), g.fail(m, id, "peel leaf without body"); }
    let params = m.bodyParameters(body);
    let res_ty = g.s.instances[f.instance_id].result;

    let saved_bindings = f.bindings;
    let saved_labels_base = f.labels_base;
    let saved_fn_ret_block = f.fn_return_block;
    let saved_direct_returns = f.direct_returns;
    let saved_peel_force = f.peel_force_leaf;
    let saved_tco_inhibit = f.tco_inhibit;

    let slot = g.newSlot();
    let made, merr = fresh(g, f, res_ty, id);
    if merr != blot_direct_types::Error.none { return neverVal(), merr; }
    g.s.slots[slot] = blot_direct_emit::Slot { true, made };

    let exit = open(g, f, OP_block);
    let s .= g.s;
    let labels_mark = s.labels.len;
    s.labels.push(blot_direct_emit::Label { target: 0xffffffff, depth: exit, result: slot, kind: blot_direct_emit::LabelKind.function });

    f.bindings = blot_support_zigmap::Map {};
    f.labels_base = labels_mark;
    f.fn_return_block = 0;
    f.direct_returns = false;
    f.peel_force_leaf = false;
    f.tco_inhibit = saved_tco_inhibit + 1;

    for param, at in params {
        if at == f.peel_d_idx {
            let zero = constLocal(g, f, 0);
            recordConstU32(f, zero, 0);
            bindPut(g, f, param.binding, valOf1(g, blot_direct_types::u32_, zero));
        } else {
            bindPut(g, f, param.binding, g.s.vals[direct.start + at]);
        }
    }

    var final_err = blot_direct_types::Error.none;
    let ch = m.children(f.peel_prefix_parent);
    for ci in 0..f.peel_if_pos {
        let _, err = stmt(g, f, ch[ci]);
        if err != blot_direct_types::Error.none { final_err = err; break; }
    }
    if final_err == blot_direct_types::Error.none {
        let leaf_body = m.node(ch[f.peel_if_pos]).b;
        let leaf_val, lerr = stmt(g, f, leaf_body);
        if lerr != blot_direct_types::Error.none { final_err = lerr; }
        else if leaf_val.ty != blot_direct_types::never {
            final_err = deliver(g, f, leaf_val, slot, id);
        }
    }
    close(g, f);
    s.labels.resize(labels_mark);
    f.bindings = saved_bindings;
    f.labels_base = saved_labels_base;
    f.fn_return_block = saved_fn_ret_block;
    f.direct_returns = saved_direct_returns;
    f.peel_force_leaf = saved_peel_force;
    f.tco_inhibit = saved_tco_inhibit;
    if final_err != blot_direct_types::Error.none { return neverVal(), final_err; }

    let ret_val = g.s.slots[slot].value;
    let spec = g.s.worker_specs[f.worker_spec];
    if spec.drop_param != 0xff {
        let src_arg = g.s.vals[direct.start + (spec.drop_param as i64)];
        if spec.drop_ret_pos == -1 {
            propagateArrayFacts(g, f, src_arg, ret_val);
        } else if spec.drop_ret_pos >= 0 && tagOf(g, ret_val.ty) == blot_direct_types::Tag.tuple {
            let elem_val = Val { src_arg.ty, ret_val.start + spec.drop_word_start, 2 };
            propagateArrayFacts(g, f, src_arg, elem_val);
        }
    }
    return ret_val, blot_direct_types::Error.none;
}

// Collects top-level plain-element container owner slots from a function result
// when the result contains no boxed pointers, closures, or memory-holding sums.
// If every collected slot predates `owner_mark` (or is persistent) and no store
// escaped past `owner_mark`, the function can safely reclaim its local scratch.
recursive fn fnResultOwnerSlots(g: Generator&, ty: Ty, words: u32, out: u32[8]&, out_len: i64&) -> bool, Error {
    let holds, error = g.holdsMemory(ty);
    if error != blot_direct_types::Error.none { return false, error; }
    if !holds { return true, blot_direct_types::Error.none; }
    let boxed, berr = g.types.boxed(ty);
    if berr != blot_direct_types::Error.none { return false, berr; }
    if boxed { return false, blot_direct_types::Error.none; }
    let n = g.types.node(ty);
    match n.tag {
        array, view, ref, link => {
            let elem_holds, eherr = g.contentsHoldMemory(n.a);
            if eherr != blot_direct_types::Error.none { return false, eherr; }
            if elem_holds || out_len >= 8 { return false, blot_direct_types::Error.none; }
            out[out_len] = g.s.words[words];
            out_len += 1;
            return true, blot_direct_types::Error.none;
        },
        tuple => {
            var at: u32 = 0;
            for index in 0..(n.b as i64) {
                let item = g.types.tupleItems(ty)[index];
                let layout, lerr = g.types.layout(item);
                if lerr != blot_direct_types::Error.none { return false, lerr; }
                let safe, serr = fnResultOwnerSlots(g, item, words + at, out, out_len);
                if serr != blot_direct_types::Error.none || !safe { return false, serr; }
                at += layout.len as u32;
            }
            return true, blot_direct_types::Error.none;
        },
        record => {
            var at: u32 = 0;
            for index in 0..(n.b as i64) {
                let field = g.types.recordField(ty, index).ty;
                let layout, lerr = g.types.layout(field);
                if lerr != blot_direct_types::Error.none { return false, lerr; }
                let safe, serr = fnResultOwnerSlots(g, field, words + at, out, out_len);
                if serr != blot_direct_types::Error.none || !safe { return false, serr; }
                at += layout.len as u32;
            }
            return true, blot_direct_types::Error.none;
        },
        nominal => {
            let cases, cerr = g.types.variants(ty);
            if cerr != blot_direct_types::Error.none || cases.len != 1 { return false, cerr; }
            let payload = g.types.variant_payloads[cases.payloads];
            return fnResultOwnerSlots(g, payload, words, out, out_len);
        },
        _ => { return false, blot_direct_types::Error.none; },
    }
}

recursive fn emitWorkerFunction(g: Generator&, id: u32, spec_idx: i64, scc_idx: i64) -> Error {
    let s .= g.s;
    let code_mark = s.code.len;
    let sites_mark = blot_direct_relocations::mark();
    let locals_mark = s.locals.len;
    let shadows_mark = s.v128_shadows.len;
    let labels_mark = s.labels.len;
    let handles_mark = s.handles.len;
    let handle_cells_mark = s.handle_cells_len;

    let key = g.s.instances[id].key;
    let unit = key.unit;
    var f = newFn(g, unit, id);
    f.env = g.s.instances[id].env;
    f.evidence_context = key.evidence_context;
    f.worker_spec = spec_idx;
    f.worker_scc_idx = scc_idx;
    let spec = g.s.worker_specs[spec_idx];
    let parameters = g.s.instances[id].parameters;
    let m .= g.units[unit - 1];
    let body .= m.body(key.id);
    if !body {
        blot_direct_relocations::rewind(sites_mark);
        s.code.resize(code_mark); s.locals.resize(locals_mark); s.v128_shadows.resize(shadows_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
        return g.fail(m, 0, "worker instance without a body");
    }
    let body_parameters = m.bodyParameters(body);
    let own_mask = m.binding(body.binding).capability_parameters.own;
    let inputs = g.reserveVals(parameters.len);
    var param_bindings: u32[8] = [0; 8];
    var param_tys: Ty[8] = [0; 8];
    var arr_mask: u32 = 0;
    for at in 0..(parameters.len as i64) {
        let pty = g.s.tys[parameters.start + at];
        let pmode = if at < 8 { spec.param_modes[at] } else { 0 };
        if at < 8 {
            param_bindings[at] = body_parameters[at].binding;
            param_tys[at] = pty;
        }
        if pmode == 3 {
            let entry_loc = local(g, f, VT_i32);
            let pval = valOf2(g, pty, entry_loc, entry_loc);
            g.s.vals[inputs.start + at] = pval;
            recordWorkerM(f, entry_loc, entry_loc, entry_loc);
            recordCheckedGrow(f, entry_loc, entry_loc, entry_loc);
            recordMutable(g, f, pval);
        } else if pmode == 1 || pmode == 2 {
            let base_loc = local(g, f, VT_i32);
            let len_loc = local(g, f, VT_i32);
            let pval = valOf2(g, pty, base_loc, len_loc);
            g.s.vals[inputs.start + at] = pval;
            recordWorkerR(f, base_loc, len_loc, base_loc, len_loc);
            recordCheckedArray(f, base_loc, len_loc, base_loc, len_loc);
            if pmode == 2 { recordMutable(g, f, pval); }
            if at < 8 { arr_mask |= ((1 as u32) << (at as u32)); }
        } else {
            let value, error = fresh(g, f, pty, 0);
            if error != blot_direct_types::Error.none {
                blot_direct_relocations::rewind(sites_mark);
                s.code.resize(code_mark); s.locals.resize(locals_mark); s.v128_shadows.resize(shadows_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                return error;
            }
            g.s.vals[inputs.start + at] = value;
        }
    }
    f.parameter_words = localCount(g, f);
    let owner_mark = local(g, f, VT_i32);
    let stack_mark = local(g, f, VT_i32);
    let saved_esc = local(g, f, VT_i32);
    for parameter, at in body_parameters {
        let pval = g.s.vals[inputs.start + at];
        bindPut(g, f, parameter.binding, pval);
        if at < 32 && ((own_mask >> (at as u32)) & 1) != 0 {
            blot_support_zigmap::put(g.s.map_pool, f.unique_owned, parameter.binding, 1);
        }
    }
    let root = body.root;
    let slot = g.newSlot();
    let made, merr = fresh(g, f, g.s.instances[id].result, root);
    if merr != blot_direct_types::Error.none {
        blot_direct_relocations::rewind(sites_mark);
        s.code.resize(code_mark); s.locals.resize(locals_mark); s.v128_shadows.resize(shadows_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
        return merr;
    }
    g.s.slots[slot] = blot_direct_emit::Slot { true, made };
    let exit = open(g, f, OP_block);
    g.s.labels.push(blot_direct_emit::Label { target: 0xffffffff, depth: exit, result: slot, kind: blot_direct_emit::LabelKind.function });
    if root != 0 && m.node(root).tag == blot_check_core::Tag.block_ {
        f.fn_return_block = root;
    } else if root != 0 && m.node(root).tag == blot_check_core::Tag.return_ && m.node(root).a != 0 && m.node(m.node(root).a).tag == blot_check_core::Tag.block_ {
        f.fn_return_block = m.node(root).a;
    }
    let target = BindingRef { unit, key.id };
    f.direct_returns = spec.no_scope_alloc;
    var has_tco_loop = false;
    if spec.scc_len == 1 {
        let res_ty = g.s.instances[id].result;
        var int_res = res_ty == blot_direct_types::u32_ || res_ty == blot_direct_types::i32_ ||
            res_ty == blot_direct_types::u64_ || res_ty == blot_direct_types::i64_;
        var tco_params_ok = int_res;
        for at in 0..(parameters.len as i64) {
            let pty = g.s.tys[parameters.start + at];
            let pmode = if at < 8 { spec.param_modes[at] } else { 0 };
            if pmode == 1 { continue; }
            if pty != blot_direct_types::u32_ && pty != blot_direct_types::i32_ &&
                pty != blot_direct_types::u64_ && pty != blot_direct_types::i64_ &&
                pty != blot_direct_types::u8_ && pty != blot_direct_types::boolean {
                tco_params_ok = false;
            }
        }
        if tco_params_ok {
            var opcode: u8 = 0;
            var rbud: i64 = 256;
            if scanScalarRecursion(g, f, m, root, target, parameters.len as i64, arr_mask, param_bindings, f.fn_return_block, res_ty, opcode, rbud) && opcode != 0 {
                f.assoc_tco_opcode = opcode;
                f.assoc_tco_ty = res_ty;
                let is_i64 = res_ty == blot_direct_types::u64_ || res_ty == blot_direct_types::i64_;
                f.assoc_tco_local = local(g, f, if is_i64 { VT_i64 } else { VT_i32 });
                if opcode == OP_i32_mul {
                    i32Const(g, 1);
                    lset(g, f.assoc_tco_local);
                } else if opcode == OP_i64_mul {
                    i64Const(g, 1);
                    lset(g, f.assoc_tco_local);
                }
                f.direct_returns = true;
            }
        }
        if f.assoc_tco_local != 0xffffffff ||
            hasSelfTailCall(g, m, root, target, parameters.len as i64, f.fn_return_block, 0) {
            f.self_tco_loop = open(g, f, OP_loop);
            f.self_tco_inputs = inputs;
            has_tco_loop = true;
        }
    }
    // 1-level small-leaf peeling for non-TCO self-recursive no-scope-alloc workers.
    if spec.scc_len == 1 && !has_tco_loop && spec.no_scope_alloc && f.direct_returns {
        var d_idx: i64 = -1;
        var p_suite: u32 = 0;
        var p_if_pos: i64 = -1;
        if tryDetectLeafPeel(g, m, root, target, param_bindings, param_tys, parameters.len as i64, d_idx, p_suite, p_if_pos) {
            f.peel_active = true;
            f.peel_d_idx = d_idx;
            f.peel_prefix_parent = p_suite;
            f.peel_if_pos = p_if_pos;
            let d_local = w(g, g.s.vals[inputs.start + d_idx], 0);
            lget(g, d_local);
            i32Const(g, 1);
            op(g, OP_i32_eq);
            let peel_if = open(g, f, OP_if_);
            let saved_b = blot_support_zigmap::clone(g.s.map_pool, f.bindings);
            f.peel_force_leaf = true;
            let pch = m.children(p_suite);
            var perr = blot_direct_types::Error.none;
            for ci in 0..pch.len {
                if ci == p_if_pos {
                    for merge in m.branchMerges(pch[ci]) {
                        let ev, eok = bindGet(g, f, merge.else_binding);
                        if eok { bindPut(g, f, merge.result, ev); }
                    }
                    continue;
                }
                let _, serr = stmt(g, f, pch[ci]);
                if serr != blot_direct_types::Error.none { perr = serr; break; }
            }
            f.peel_force_leaf = false;
            f.bindings = saved_b;
            close(g, f);
            if perr != blot_direct_types::Error.none {
                blot_direct_relocations::rewind(sites_mark);
                s.code.resize(code_mark); s.locals.resize(locals_mark); s.v128_shadows.resize(shadows_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                return perr;
            }
        }
    }
    f.scratch_body = scratchBody(m, root);
    let value, err = stmt(g, f, root);
    if err != blot_direct_types::Error.none {
        blot_direct_relocations::rewind(sites_mark);
        s.code.resize(code_mark); s.locals.resize(locals_mark); s.v128_shadows.resize(shadows_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
        return err;
    }
    let delivered = deliver(g, f, value, slot, root);
    if delivered == blot_direct_types::Error.unsupported { g.recordFailure(m, root); }
    else if delivered != blot_direct_types::Error.none {
        blot_direct_relocations::rewind(sites_mark);
        s.code.resize(code_mark); s.locals.resize(locals_mark); s.v128_shadows.resize(shadows_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
        return delivered;
    }
    if has_tco_loop { close(g, f); }
    close(g, f);
    var result = neverVal();
    if g.s.slots[slot].present { result = g.s.slots[slot].value; }
    var release = false;
    var res_slots: u32[8] = [0; 8];
    var res_slots_len: i64 = 0;
    if f.allocates && !f.emitted_return_call && f.memory_stores == 0 {
        let res_ty = g.s.instances[id].result;
        if spec.drop_param != 0xff && spec.drop_ret_pos == -1 {
            // Worker returns void (the sole array owner lives in the wrapper's frame).
            release = true;
        } else {
            let holds, herr = g.holdsMemory(res_ty);
            if herr != blot_direct_types::Error.none {
                blot_direct_relocations::rewind(sites_mark);
                s.code.resize(code_mark); s.locals.resize(locals_mark); s.v128_shadows.resize(shadows_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                return herr;
            }
            if !holds {
                release = true;
            } else if result.ty != blot_direct_types::never && result.ty == res_ty {
                let safe, serr = fnResultOwnerSlots(g, res_ty, result.start, res_slots, res_slots_len);
                if serr != blot_direct_types::Error.none {
                    blot_direct_relocations::rewind(sites_mark);
                    s.code.resize(code_mark); s.locals.resize(locals_mark); s.v128_shadows.resize(shadows_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                    return serr;
                }
                if safe {
                    // Exclude the dropped worker handle slot (which holds entry/base, not a slot id).
                    if spec.drop_param != 0xff {
                        let dslot = w(g, result, spec.drop_word_start as i64);
                        var out_sl: i64 = 0;
                        for si in 0..res_slots_len {
                            if res_slots[si] != dslot { res_slots[out_sl] = res_slots[si]; out_sl += 1; }
                        }
                        res_slots_len = out_sl;
                    }
                    release = true;
                }
            }
        }
    }
    if release {
        let rt = g.runtime_();
        let fn_esc = local32(g, f);
        gget(g, rt.escape_min_slot);
        ltee(g, fn_esc);
        lget(g, owner_mark);
        op(g, OP_i32_ge_u);
        for si in 0..res_slots_len {
            let rslot = res_slots[si];
            lget(g, rslot);
            lget(g, owner_mark);
            op(g, OP_i32_lt_u);
            lget(g, rslot);
            i32Const(g, rt.layout.persistent_split);
            op(g, OP_i32_ge_u);
            op(g, OP_i32_or);
            op(g, OP_i32_and);
        }
        let opened = open(g, f, OP_if_);
        releaseTo(g, owner_mark, stack_mark);
        close(g, f);
        emitMergeEscapeMin(g, f, fn_esc, saved_esc);
    }
    if result.ty == blot_direct_types::never { op(g, OP_unreachable_); }
    else { pushWorkerResult(g, f, result); }
    op(g, OP_end);
    finishWith(g, spec.scc_fns[scc_idx], f, release, owner_mark, stack_mark, saved_esc);
    blot_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark);
    s.locals.resize(locals_mark);
    s.v128_shadows.resize(shadows_mark);
    s.labels.resize(labels_mark);
    s.handles.resize(handles_mark);
    s.handle_cells_len = handle_cells_mark;
    return blot_direct_types::Error.none;
}

recursive fn emitInstanceBody(g: Generator&, id: u32) -> Error {
    let key = g.s.instances[id].key;
    // Check if this named instance belongs to a specialized recursive worker SCC.
    if key.kind == blot_direct_emit::InstanceKind.named && !g.s.instances[id].closure && !g.s.instances[id].inferring {
        var spec_idx: i64 = -1;
        var scc_idx: i64 = -1;
        let existing_w, has_w = g.s.worker_map.get(id as u64);
        if has_w && existing_w != 0 {
            spec_idx = (existing_w - 1) as i64;
            let sp = g.s.worker_specs[spec_idx];
            for si in 0..(sp.scc_len as i64) {
                if sp.scc_insts[si] == id { scc_idx = si; break; }
            }
        } else {
            let new_spec, ok_spec = analyzeWorkerSCC(g, id);
            if ok_spec {
                if g.s.parallel_readonly {
                    g.s.parallel_aborted = true;
                    return blot_direct_types::Error.unsupported;
                }
                var spec = new_spec;
                let m .= g.units[key.unit - 1];
                // Resolve all SCC peer instances and build the shared worker signature.
                var all_ok = true;
                for si in 0..(spec.scc_len as i64) {
                    if si == 0 {
                        spec.scc_insts[0] = id;
                    } else {
                        let peer_inst, perr = g.namedWith(BindingRef { key.unit, spec.scc_bindings[si] }, key.ty, false, m, 0, 0);
                        if perr != blot_direct_types::Error.none || g.s.instances[peer_inst].inferring {
                            all_ok = false;
                            break;
                        }
                        spec.scc_insts[si] = peer_inst;
                    }
                }
                if all_ok {
                    let parameters = g.s.instances[id].parameters;
                    var wparams: ValType[>..<] = [];
                    var wresults: ValType[>..<] = [];
                    for pi in 0..(parameters.len as i64) {
                        let pmode = if pi < 8 { spec.param_modes[pi] } else { 0 };
                        if pmode == 3 {
                            wparams.push(VT_i32);
                        } else if pmode == 1 || pmode == 2 {
                            wparams.push(VT_i32);
                            wparams.push(VT_i32);
                        } else {
                            let pl, plerr = g.types.layout(g.s.tys[parameters.start + pi]);
                            if plerr != blot_direct_types::Error.none { all_ok = false; break; }
                            for vt in pl { wparams.push(vt); }
                        }
                    }
                    let res_ty = g.s.instances[id].result;
                    let rl, rlerr = g.types.layout(res_ty);
                    if rlerr != blot_direct_types::Error.none { all_ok = false; }
                    else {
                        let dstart = spec.drop_word_start as i64;
                        for vt, ri in rl {
                            if spec.drop_param != 0xff && (ri == dstart || ri == dstart + 1) { continue; }
                            wresults.push(vt);
                        }
                    }
                    if all_ok {
                        let wsig = g.module.signature(wparams[..], wresults[..]);
                        for si in 0..(spec.scc_len as i64) {
                            let wfn = g.module.addFunction(wsig);
                            blot_direct_writer::setName(g.module, wfn, "worker");
                            spec.scc_fns[si] = wfn;
                        }
                        spec_idx = g.s.worker_specs.len;
                        g.s.worker_specs.push(spec);
                        for si in 0..(spec.scc_len as i64) {
                            g.s.worker_map.put(spec.scc_insts[si] as u64, (spec_idx + 1) as u32);
                        }
                        scc_idx = 0;
                    }
                }
            }
        }
        if spec_idx >= 0 && scc_idx >= 0 {
            // Emit the thin validating wrapper into g.s.instances[id].function, then the worker.
            let spec = g.s.worker_specs[spec_idx];
            var wf = newFn(g, key.unit, id);
            let parameters = g.s.instances[id].parameters;
            let inputs = g.reserveVals(parameters.len);
            for at in 0..(parameters.len as i64) {
                let value, error = fresh(g, wf, g.s.tys[parameters.start + at], 0);
                if error != blot_direct_types::Error.none { return error; }
                g.s.vals[inputs.start + at] = value;
            }
            wf.parameter_words = localCount(g, wf);
            let rt = g.runtime_();
            for at in 0..(parameters.len as i64) {
                let pval = g.s.vals[inputs.start + at];
                let pmode = if at < 8 { spec.param_modes[at] } else { 0 };
                if pmode == 3 {
                    let entry_loc = local32(g, wf);
                    lget(g, w(g, pval, 0));
                    lget(g, w(g, pval, 1));
                    callf(g, rt.check);
                    ltee(g, entry_loc);
                    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_capacity);
                    i32Const(g, blot_direct_runtime::static_pool_flag);
                    op(g, OP_i32_and);
                    trap(g, wf);
                    lget(g, entry_loc);
                } else if pmode == 1 || pmode == 2 {
                    let entry_loc = local32(g, wf);
                    lget(g, w(g, pval, 0));
                    lget(g, w(g, pval, 1));
                    callf(g, rt.check);
                    ltee(g, entry_loc);
                    if pmode == 2 {
                        op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_capacity);
                        i32Const(g, blot_direct_runtime::static_pool_flag);
                        op(g, OP_i32_and);
                        trap(g, wf);
                        lget(g, entry_loc);
                    }
                    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
                    lget(g, entry_loc);
                    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
                } else {
                    push(g, pval);
                }
            }
            callf(g, spec.scc_fns[scc_idx]);
            let res_ty = g.s.instances[id].result;
            if spec.drop_param != 0xff {
                let drop_in = g.s.vals[inputs.start + (spec.drop_param as i64)];
                let full_res, perr = popWorkerResult(g, wf, res_ty, spec.drop_word_start, drop_in, 0);
                if perr != blot_direct_types::Error.none { return perr; }
                push(g, full_res);
            }
            op(g, OP_end);
            finishWith(g, g.s.instances[id].function, wf, false, 0, 0, 0);
            return emitWorkerFunction(g, id, spec_idx, scc_idx);
        }
    }
    var unit = key.unit;
    if !g.hasUnit(unit) { unit = g.s.instances[id].site; }
    var f = newFn(g, unit, id);
    f.env = g.s.instances[id].env;
    f.evidence_context = key.evidence_context;
    let m .= g.units[unit - 1];
    let closure = g.s.instances[id].closure;
    let parameters = g.s.instances[id].parameters;
    var root: u32 = 0;
    if closure { let environment = local(g, f, VT_i32); }
    let inputs = g.reserveVals(parameters.len);
    for at in 0..(parameters.len as i64) {
        let value, error = fresh(g, f, g.s.tys[parameters.start + at], 0);
        if error != blot_direct_types::Error.none { return error; }
        g.s.vals[inputs.start + at] = value;
    }
    f.parameter_words = localCount(g, f);
    let owner_mark = local(g, f, VT_i32);
    let stack_mark = local(g, f, VT_i32);
    let saved_esc = local(g, f, VT_i32);
    var captures = Vals {};
    if closure {
        let loaded, error = loadCaptures(g, f, g.s.instances[id].captures, 0);
        if error != blot_direct_types::Error.none { return error; }
        captures = loaded;
    }
    if key.kind == blot_direct_emit::InstanceKind.named {
        let body .= m.body(key.id);
        if !body { return g.fail(m, 0, "instance without a body"); }
        let body_parameters = m.bodyParameters(body);
        let own_mask = m.binding(body.binding).capability_parameters.own;
        for parameter, at in body_parameters {
            let pval = g.s.vals[inputs.start + at];
            bindPut(g, f, parameter.binding, pval);
            if at < 32 && ((own_mask >> (at as u32)) & 1) != 0 {
                blot_support_zigmap::put(g.s.map_pool, f.unique_owned, parameter.binding, 1);
            }
        }
        root = body.root;
    } else if key.kind == blot_direct_emit::InstanceKind.lambda {
        let info = m.closure(key.id);
        let captured = m.closureCaptures(key.id);
        for binding, at in captured {
            let cap_val = g.s.vals[captures.start + at];
            let init_node, is_poly = g.s.polymorphic.get(polyCaptureKey(id, binding));
            if is_poly {
                let rerr = restorePolyCapture(g, f, id, binding, init_node, cap_val, 0);
                if rerr != blot_direct_types::Error.none { return rerr; }
            } else {
                bindPut(g, f, binding, cap_val);
                if tagOf(g, cap_val.ty) == blot_direct_types::Tag.cell {
                    blot_support_zigmap::put(g.s.map_pool, f.with_cells, binding, g.types.node(cap_val.ty).a);
                }
            }
        }
        bindPut(g, f, info.parameter.binding, g.s.vals[inputs.start]);
        root = info.body;
    }
    let slot = g.newSlot();
    if !g.s.instances[id].inferring {
        let made, error = fresh(g, f, g.s.instances[id].result, root);
        if error != blot_direct_types::Error.none { return error; }
        g.s.slots[slot] = blot_direct_emit::Slot { true, made };
    }
    let exit = open(g, f, OP_block);
    g.s.labels.push(blot_direct_emit::Label { target: 0xffffffff, depth: exit, result: slot, kind: blot_direct_emit::LabelKind.function });
    var has_tco_loop = false;
    if key.kind == blot_direct_emit::InstanceKind.named && !closure {
        if root != 0 && m.node(root).tag == blot_check_core::Tag.block_ {
            f.fn_return_block = root;
        } else if root != 0 && m.node(root).tag == blot_check_core::Tag.return_ && m.node(root).a != 0 && m.node(m.node(root).a).tag == blot_check_core::Tag.block_ {
            f.fn_return_block = m.node(root).a;
        }
        if !g.s.instances[id].inferring {
            let target = BindingRef { unit, key.id };
            var budget: i64 = 512;
            f.direct_returns = bodyNoAlloc(g, f, m, root, budget);
            let res_ty = g.s.instances[id].result;
            var scalar_parameters = res_ty == blot_direct_types::u32_ || res_ty == blot_direct_types::i32_ ||
                res_ty == blot_direct_types::u64_ || res_ty == blot_direct_types::i64_;
            for at in 0..(parameters.len as i64) {
                let pt = g.s.tys[parameters.start + at];
                if pt != blot_direct_types::u32_ && pt != blot_direct_types::i32_ &&
                    pt != blot_direct_types::u64_ && pt != blot_direct_types::i64_ { scalar_parameters = false; }
            }
            if scalar_parameters {
                var opcode: u8 = 0;
                var recursion_budget: i64 = 256;
                var dummy_pbs: u32[8] = [0; 8];
                if scanScalarRecursion(g, f, m, root, target, parameters.len as i64, 0, dummy_pbs, f.fn_return_block, res_ty, opcode, recursion_budget) && opcode != 0 {
                    f.assoc_tco_opcode = opcode;
                    f.assoc_tco_ty = res_ty;
                    let is_i64 = res_ty == blot_direct_types::u64_ || res_ty == blot_direct_types::i64_;
                    f.assoc_tco_local = local(g, f, if is_i64 { VT_i64 } else { VT_i32 });
                    if opcode == OP_i32_mul {
                        i32Const(g, 1);
                        lset(g, f.assoc_tco_local);
                    } else if opcode == OP_i64_mul {
                        i64Const(g, 1);
                        lset(g, f.assoc_tco_local);
                    }
                    f.direct_returns = true;
                }
            }
            if f.assoc_tco_local != 0xffffffff ||
                hasSelfTailCall(g, m, root, target, parameters.len as i64, f.fn_return_block, 0) {
                f.self_tco_loop = open(g, f, OP_loop);
                f.self_tco_inputs = inputs;
                has_tco_loop = true;
            }
        }
    }
    var value = neverVal();
    match key.kind {
        named, lambda => {
            f.scratch_body = scratchBody(m, root);
            let made, error = stmt(g, f, root);
            if error != blot_direct_types::Error.none { return error; }
            value = made;
        },
        partial, primitive, constructor => {
            let made, error = adapterBody(g, f, id, captures, g.s.vals[inputs.start]);
            if error != blot_direct_types::Error.none { return error; }
            value = made;
        },
        host => {
            let made, error = hostBody(g, f, id, captures, g.s.vals[inputs.start]);
            if error != blot_direct_types::Error.none { return error; }
            value = made;
        },
        pool => {
            let made, error = poolBody(g, f, id);
            if error != blot_direct_types::Error.none { return error; }
            value = made;
        },
        operation => {
            let made, error = operationBody(g, f, id, g.s.vals[inputs.start]);
            if error != blot_direct_types::Error.none { return error; }
            value = made;
        },
        state_get => {
            let made, error = readFlat(g, f, 0, 0, g.s.instances[id].result, root);
            if error != blot_direct_types::Error.none { return error; }
            value = made;
        },
        state_set => {
            let arg = g.s.vals[inputs.start];
            let rt = g.runtime_();
            if rt.has_fork {
                let bytes, berr = flatBytes(g, f, arg.ty, root);
                if berr != blot_direct_types::Error.none { return berr; }
                if bytes != 0 {
                    gget(g, rt.fork_depth);
                    let opened = open(g, f, OP_if_);
                    lget(g, 0);
                    i32Const(g, bytes);
                    callf(g, rt.undo_record);
                    close(g, f);
                }
            }
            let written = writeFlat(g, f, 0, 0, arg, root);
            if written != blot_direct_types::Error.none { return written; }
            value = unitVal();
        },
        trap => { op(g, OP_unreachable_); },
    }
    let delivered = deliver(g, f, value, slot, root);
    if delivered == blot_direct_types::Error.unsupported { g.recordFailure(m, root); }
    else if delivered != blot_direct_types::Error.none { return delivered; }
    if has_tco_loop { close(g, f); }
    close(g, f);
    // An inferred result is the type of the first value the body delivers.
    var result = neverVal();
    if g.s.slots[slot].present { result = g.s.slots[slot].value; }
    if g.s.instances[id].inferring { g.s.instances[id].result = result.ty; }
    // Stored memory-holding values may now be reachable from older storage.
    var release = false;
    var res_slots: u32[8] = [0; 8];
    var res_slots_len: i64 = 0;
    if f.allocates && !f.emitted_return_call && f.memory_stores == 0 {
        let res_ty = g.s.instances[id].result;
        let holds, error = g.holdsMemory(res_ty);
        if error != blot_direct_types::Error.none { return error; }
        if !holds {
            release = true;
        } else if result.ty != blot_direct_types::never && result.ty == res_ty {
            let safe, serr = fnResultOwnerSlots(g, res_ty, result.start, res_slots, res_slots_len);
            if serr != blot_direct_types::Error.none { return serr; }
            if safe { release = true; }
            else { res_slots_len = 0; }
        }
    }
    if release {
        let rt = g.runtime_();
        let fn_esc = local32(g, f);
        gget(g, rt.escape_min_slot);
        ltee(g, fn_esc);
        lget(g, owner_mark);
        op(g, OP_i32_ge_u);
        for si in 0..res_slots_len {
            let rslot = res_slots[si];
            lget(g, rslot);
            lget(g, owner_mark);
            op(g, OP_i32_lt_u);
            lget(g, rslot);
            i32Const(g, rt.layout.persistent_split);
            op(g, OP_i32_ge_u);
            op(g, OP_i32_or);
            op(g, OP_i32_and);
        }
        let opened = open(g, f, OP_if_);
        releaseTo(g, owner_mark, stack_mark);
        close(g, f);
        emitMergeEscapeMin(g, f, fn_esc, saved_esc);
    }
    if result.ty == blot_direct_types::never { op(g, OP_unreachable_); } else { push(g, result); }
    op(g, OP_end);
    finishWith(g, g.s.instances[id].function, f, release, owner_mark, stack_mark, saved_esc);
    return blot_direct_types::Error.none;
}

// Encodes the body and gives the generator's stacks back. Only for bodies
// that are not nested in another one (exports and start functions).
fn finish(g: Generator&, function: u32, f: const Fn&) {
    finishWith(g, function, f, false, 0, 0, 0);
    g.s.code.resize(f.code_base);
    g.s.locals.resize(f.locals_base);
    g.s.v128_shadows.resize(f.shadows_base);
    g.s.labels.resize(f.labels_base);
    g.s.handles.resize(f.handles_base);
    g.s.handle_cells_len = f.handle_cells_base;
}

var finish_body_scratch: u8[>..<] = [];

// Encodes the body: local declarations (in runs of one type), the marks a
// releasing body records on entry, then code.
fn finishWith(g: Generator&, function: u32, f: const Fn&, release: bool, owner_mark: u32, stack_mark: u32, saved_esc: u32) {
    let mark = finish_body_scratch.len;
    let first = f.locals_base + f.parameter_words;
    let count = g.s.locals.len - first;
    var runs: u64 = 0;
    var at: i64 = 0;
    while at < count {
        var end = at + 1;
        while end < count && g.s.locals[first + end] == g.s.locals[first + at] { end += 1; }
        at = end;
        runs += 1;
    }
    blot_direct_writer::uleb(finish_body_scratch, runs);
    at = 0;
    while at < count {
        var end = at + 1;
        while end < count && g.s.locals[first + end] == g.s.locals[first + at] { end += 1; }
        blot_direct_writer::uleb(finish_body_scratch, (end - at) as! u64);
        finish_body_scratch.push(g.s.locals[first + at]);
        at = end;
    }
    if release {
        markInto(g, finish_body_scratch, owner_mark, stack_mark);
        let esc_global = g.runtime_().escape_min_slot;
        finish_body_scratch.push(OP_global_get);
        blot_direct_writer::uleb(finish_body_scratch, esc_global);
        finish_body_scratch.push(OP_local_set);
        blot_direct_writer::uleb(finish_body_scratch, saved_esc);
        finish_body_scratch.push(OP_i32_const);
        blot_direct_writer::sleb(finish_body_scratch, -1);
        finish_body_scratch.push(OP_global_set);
        blot_direct_writer::uleb(finish_body_scratch, esc_global);
    }
    if g.s.parallel_readonly {
        let header_len = finish_body_scratch.len - mark;
        blot_direct_emit::setParallelBody(finish_body_scratch[mark..], g.s.code[f.code_base..g.s.code.len], f.code_base);
        blot_direct_relocations::finishBody(f.sites_base, header_len - f.code_base, 0, 0);
        finish_body_scratch.resize(mark);
        return;
    }
    let body_start = g.module.text.len;
    g.module.text.append(finish_body_scratch[mark..]);
    let header_len = g.module.text.len - body_start;
    blot_direct_relocations::finishBody(f.sites_base, header_len - f.code_base, (function - g.module.imports.len) as u32, body_start);
    g.module.text.append(g.s.code[f.code_base..g.s.code.len]);
    g.module.functions[function - g.module.imports.len].body = blot_direct_writer::Range { start: body_start, len: g.module.text.len - body_start };
    finish_body_scratch.resize(mark);
}

// ----- ABI ---------------------------------------------------------------

// ABI 8 value kinds (runtime_ir.Scalar + extended tags 14..23), and callback import names.
enum Abi { unit, u32_, bool_, f32_, array_u32, array_f32, u8_, i32_, u64_, i64_, f64_, array_u8, array_i32, array_u64, array_i64, array_f64 }
fn abiCode(kind: Abi) -> u8 {
    match kind {
        unit => { return 0; },
        u32_ => { return 1; },
        bool_ => { return 2; },
        f32_ => { return 3; },
        array_u32 => { return 5; },
        array_f32 => { return 6; },
        u8_ => { return 14; },
        i32_ => { return 15; },
        u64_ => { return 16; },
        i64_ => { return 17; },
        f64_ => { return 18; },
        array_u8 => { return 19; },
        array_i32 => { return 20; },
        array_u64 => { return 21; },
        array_i64 => { return 22; },
        array_f64 => { return 23; },
    }
}
fn abiName(kind: Abi) -> Chars {
    match kind {
        unit => { return "unit"; },
        u32_ => { return "u32"; },
        bool_ => { return "bool"; },
        f32_ => { return "f32"; },
        array_u32 => { return "array_u32"; },
        array_f32 => { return "array_f32"; },
        u8_ => { return "u8"; },
        i32_ => { return "i32"; },
        u64_ => { return "u64"; },
        i64_ => { return "i64"; },
        f64_ => { return "f64"; },
        array_u8 => { return "array_u8"; },
        array_i32 => { return "array_i32"; },
        array_u64 => { return "array_u64"; },
        array_i64 => { return "array_i64"; },
        array_f64 => { return "array_f64"; },
    }
}
fn abiKind(g: const Generator&, ty: Ty) -> Abi, bool {
    let n = g.types.node(ty);
    match n.tag {
        unit => { return Abi.unit, true; },
        u32_ => { return Abi.u32_, true; },
        boolean => { return Abi.bool_, true; },
        f32_ => { return Abi.f32_, true; },
        u8_ => { return Abi.u8_, true; },
        i32_ => { return Abi.i32_, true; },
        u64_ => { return Abi.u64_, true; },
        i64_ => { return Abi.i64_, true; },
        f64_ => { return Abi.f64_, true; },
        array => {
            let element = g.types.node(n.a).tag;
            match element {
                u32_ => { return Abi.array_u32, true; },
                f32_ => { return Abi.array_f32, true; },
                u8_ => { return Abi.array_u8, true; },
                i32_ => { return Abi.array_i32, true; },
                u64_ => { return Abi.array_u64, true; },
                i64_ => { return Abi.array_i64, true; },
                f64_ => { return Abi.array_f64, true; },
                _ => { return Abi.unit, false; },
            }
        },
        _ => { return Abi.unit, false; },
    }
}
fn abiMachine(kind: Abi) -> ValType {
    match kind {
        f32_ => { return VT_f32; },
        u64_, i64_ => { return VT_i64; },
        f64_ => { return VT_f64; },
        _ => { return VT_i32; },
    }
}
fn isArray(kind: Abi) -> bool {
    match kind {
        array_u32, array_f32, array_u8, array_i32, array_u64, array_i64, array_f64 => { return true; },
        _ => { return false; },
    }
}
// A Foreign host callback parameter: its argument and result kinds.
fn callbackAbi(g: const Generator&, ty: Ty) -> Abi, Abi, bool {
    let n = g.types.node(ty);
    if n.tag != blot_direct_types::Tag.function { return Abi.unit, Abi.unit, false; }
    let first, has_first = abiKind(g, n.a);
    if !has_first { return Abi.unit, Abi.unit, false; }
    let second, has_second = abiKind(g, n.b);
    if !has_second { return Abi.unit, Abi.unit, false; }
    return first, second, true;
}
// Declares the host import for a callback shape; imports precede functions.
fn hostImport(g: Generator&, first: Abi, second: Abi) -> u32 {
    let key = blot_direct_emit::key64(abiCode(first), abiCode(second));
    let found, present = g.s.host_imports.get(key);
    if present { return found; }
    var name: u8[>..<] = [];
    name.append("call_");
    name.append(abiName(first));
    name.append("_");
    name.append(abiName(second));
    let signature = g.module.signature([VT_externref, abiMachine(first)], [abiMachine(second)]);
    let import_id = g.module.importFunction("blot:host/1", name[..], signature);
    let stored = g.s.host_imports.put(key, import_id);
    return import_id;
}

// ----- exports -----------------------------------------------------------

// Recovers temporaries, speculative fork state, and providers a trapped earlier call left behind.
// Rewinds fork journal BEFORE releasing owners so realloc sentinels free cleanly and pre-fork entries restore.
fn resetEntry(g: Generator&) {
    let rt = g.runtime_();
    if rt.has_fork {
        i32Const(g, 0);
        callf(g, rt.undo_rewind);
        i32Const(g, 0);
        gset(g, rt.fork_depth);
        i32Const(g, 0);
        gset(g, rt.fork_owner_mark);
    }
    i32Const(g, 1);
    callf(g, rt.release);
    i32Const(g, 0);
    callf(g, rt.rewind_stack);
    i32Const(g, 0);
    gset(g, rt.effect_context);
    i32Const(g, 0xffffffff);
    gset(g, rt.escape_min_slot);
}
fn releaseEntry(g: Generator&) {
    let rt = g.runtime_();
    i32Const(g, 1);
    callf(g, rt.release);
    i32Const(g, 0);
    callf(g, rt.rewind_stack);
}

// Called by the host after the final result has been copied, or after a trap.
fn emitInvocationFinish(g: Generator&, m: const Module&) {
    let function = g.module.addFunction(g.module.signature([], [VT_i32]));
    var f = newFn(g, m.unit, 0);
    let owner_top = g.runtime_().owner_top;
    let before = local(g, f, VT_i32);
    gget(g, owner_top);
    lset(g, before);
    resetEntry(g);
    for slot in 0..g.module.host_slots {
        i32Const(g, slot);
        op(g, blot_direct_writer::OP_ref_null);
        op(g, VT_externref);
        opIndex(g, OP_table_set, 1);
    }
    lget(g, before);
    gget(g, owner_top);
    op(g, OP_i32_sub);
    op(g, OP_end);
    finish(g, function, f);
    g.module.exportItem("blot:finish_invocation", blot_direct_writer::EXPORT_function, function);
    g.module.custom("blot:invocation", [1]);
}

// An exported scalar constant: a global its init function sets from the
// constant's instance. Returns the init function; the caller writes the ABI.
fn emitConstantExport(g: Generator&, m: const Module&, body: const blot_check_core::Body&, abi: u8[>..<]&) -> u32, Error {
    let ty, error = g.types.lower(m, m.binding(body.binding).ty, Env {});
    if error != blot_direct_types::Error.none { return 0, g.failCode(m, body.root, blot_check_diagnostic_code::Code.entry_type, "an exported binding needs a concrete type"); }
    let kind, supported = abiKind(g, ty);
    if !supported {
        g.failOpenCode(m, body.root, blot_check_diagnostic_code::Code.entry_type);
        g.put("exported constants of type ");
        g.put(blot_direct_types::tagName(g.types.node(ty).tag));
        g.put(" are not supported");
        return 0, g.failClose();
    }
    if isArray(kind) { return 0, g.failCode(m, body.root, blot_check_diagnostic_code::Code.entry_type, "exported constants must be scalars"); }
    let instance_id, error = g.named(BindingRef { unit: m.unit, binding: body.binding }, ty, m, body.root);
    if error != blot_direct_types::Error.none { return 0, error; }
    let machine = abiMachine(kind);
    let global = g.module.addGlobal(machine, true, 0);
    let function = g.module.addFunction(g.module.signature([], []));
    var f = newFn(g, m.unit, 0);
    resetEntry(g);
    callf(g, g.s.instances[instance_id].function);
    let value, error = pop(g, f, ty, body.root);
    if error != blot_direct_types::Error.none { return 0, error; }
    if ty == blot_direct_types::unit { i32Const(g, 0); } else { push(g, value); }
    gset(g, global);
    releaseEntry(g);
    op(g, OP_end);
    finish(g, function, f);
    var export_name = body.export_name;
    if export_name.len == 0 { export_name = body.declaration_name; }
    let name = m.name(export_name);
    g.module.exportItem(name, blot_direct_writer::EXPORT_global, global);
    blot_direct_writer::name(abi, name);
    abi.push(abiCode(kind));
    return function, blot_direct_types::Error.none;
}

// Initializes every array constant the program reads, in declaration order,
// so their initializers run at instantiation rather than at a first read.
fn poolInits(g: Generator&, m: const Module&, pools: const u32[:]) -> u32, Error {
    let function = g.module.addFunction(g.module.signature([], []));
    var f = newFn(g, m.unit, 0);
    resetEntry(g);
    for pool_id in pools {
        callf(g, g.s.instances[pool_id].function);
        let words, error = g.types.layout(g.s.instances[pool_id].result);
        if error != blot_direct_types::Error.none { return 0, error; }
        for word in words { op(g, OP_drop); }
    }
    releaseEntry(g);
    op(g, OP_end);
    finish(g, function, f);
    return function, blot_direct_types::Error.none;
}

// The start function: computes every exported constant in order.
fn startFunction(g: Generator&, m: const Module&, inits: const u32[:]) -> u32 {
    let function = g.module.addFunction(g.module.signature([], []));
    var f = newFn(g, m.unit, 0);
    for init_function in inits { callf(g, init_function); }
    op(g, OP_end);
    finish(g, function, f);
    return function;
}

// An exported entry: resets temporaries, converts its one ABI argument, calls
// the instance, converts the result and releases temporaries.
fn emitExport(g: Generator&, m: const Module&, body: const blot_check_core::Body&, abi: u8[>..<]&) -> Error {
    let ty, error = g.types.lower(m, m.binding(body.binding).ty, Env {});
    if error != blot_direct_types::Error.none { return g.failCode(m, body.root, blot_check_diagnostic_code::Code.entry_type, "an exported binding needs a concrete type"); }
    let instance_id, error = g.named(BindingRef { unit: m.unit, binding: body.binding }, ty, m, body.root);
    if error != blot_direct_types::Error.none { return error; }
    // An exported constant whose value is a function: its instance builds
    // the closure, which the export then applies.
    let via_closure = !body.is_function;
    let arrow = g.types.node(ty);
    if via_closure && arrow.tag != blot_direct_types::Tag.function { return g.fail(m, body.root, "exported constant of a non-function type"); }
    let instance_function = g.s.instances[instance_id].function;
    let instance_result = g.s.instances[instance_id].result;
    var parameter = arrow.a;
    if !via_closure { parameter = g.s.tys[g.s.instances[instance_id].parameters.start]; }
    // The declared result: a body that always diverges has result never.
    var result_ty = instance_result;
    if via_closure || instance_result == blot_direct_types::never { result_ty = arrow.b; }
    let first, second, has_callback = callbackAbi(g, parameter);
    var parameter_abi = Abi.unit;
    if !has_callback {
        let kind, supported = abiKind(g, parameter);
        if !supported {
            g.failOpenCode(m, body.root, blot_check_diagnostic_code::Code.entry_type);
            g.put("io entry parameters of type ");
            g.put(blot_direct_types::tagName(g.types.node(parameter).tag));
            g.put(" are not supported");
            return g.failClose();
        }
        parameter_abi = kind;
    }
    let result_abi, supported = abiKind(g, result_ty);
    if !supported {
        g.failOpenCode(m, body.root, blot_check_diagnostic_code::Code.entry_type);
        g.put("io entry results of type ");
        g.put(blot_direct_types::tagName(g.types.node(result_ty).tag));
        g.put(" are not supported");
        return g.failClose();
    }
    var machine = abiMachine(parameter_abi);
    if has_callback { machine = VT_externref; }
    let signature = g.module.signature([machine], [abiMachine(result_abi)]);
    let function = g.module.addFunction(signature);
    var f = newFn(g, m.unit, 0);
    let entry_parameter = local(g, f, machine);
    f.parameter_words = 1;
    // The host requires the storage exports exactly when packets cross.
    let packets = isArray(parameter_abi) || isArray(result_abi) || (has_callback && (isArray(first) || isArray(second)));
    resetEntry(g);
    var argument = unitVal();
    if has_callback {
        let slot = g.module.host_slots;
        g.module.host_slots += 1;
        i32Const(g, slot);
        lget(g, 0);
        opIndex(g, OP_table_set, 1);
        let made, error = hostClosure(g, f, parameter, first, second, slot);
        if error != blot_direct_types::Error.none { return error; }
        argument = made;
    } else if isArray(parameter_abi) {
        let made, error = fromPacket(g, f, parameter, 0, true);
        if error != blot_direct_types::Error.none { return error; }
        argument = made;
    } else if parameter != blot_direct_types::unit {
        if parameter == blot_direct_types::u8_ {
            lget(g, 0);
            i32Const(g, 255);
            op(g, OP_i32_and);
            lset(g, 0);
        }
        argument = valOf1(g, parameter, 0);
    }
    var result = neverVal();
    if via_closure {
        callf(g, instance_function);
        let closure, error = pop(g, f, ty, body.root);
        if error != blot_direct_types::Error.none { return error; }
        let applied, error = applyClosure(g, f, closure, argument, body.root);
        if error != blot_direct_types::Error.none { return error; }
        result = applied;
    } else {
        push(g, argument);
        callf(g, instance_function);
        let returned, error = pop(g, f, instance_result, body.root);
        if error != blot_direct_types::Error.none { return error; }
        result = returned;
    }
    if result.ty == blot_direct_types::never || (result.ty != result_ty && g.types.node(result.ty).tag == blot_direct_types::Tag.never) {
        // The body always diverges: the export traps with it.
        op(g, OP_unreachable_);
        op(g, OP_end);
        finish(g, function, f);
        exportEntry(g, m, body, abi, function, has_callback, first, second, parameter_abi, result_abi, packets);
        return blot_direct_types::Error.none;
    }
    if isArray(result_abi) {
        let packet, error = toPacket(g, f, result, body.root);
        if error != blot_direct_types::Error.none { return error; }
        releaseEntry(g);
        lget(g, packet);
    } else {
        releaseEntry(g);
        if result_ty == blot_direct_types::unit { i32Const(g, 0); } else { push(g, result); }
    }
    op(g, OP_end);
    finish(g, function, f);
    exportEntry(g, m, body, abi, function, has_callback, first, second, parameter_abi, result_abi, packets);
    return blot_direct_types::Error.none;
}
// Exports `function` under the body's name and writes its ABI entry.
fn exportEntry(g: Generator&, m: const Module&, body: const blot_check_core::Body&, abi: u8[>..<]&, function: u32, has_callback: bool, first: Abi, second: Abi, parameter_abi: Abi, result_abi: Abi, packets: bool) {
    var export_name = body.export_name;
    if export_name.len == 0 { export_name = body.declaration_name; }
    let name = m.name(export_name);
    g.module.exportItem(name, blot_direct_writer::EXPORT_function, function);
    blot_direct_writer::name(abi, name);
    if has_callback {
        abi.push(4);
        abi.push(abiCode(first));
        abi.push(abiCode(second));
    } else { abi.push(abiCode(parameter_abi)); }
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
