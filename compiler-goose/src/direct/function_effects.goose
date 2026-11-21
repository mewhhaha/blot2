// Effect operations, providers and handlers of the direct backend's function
// emitter (compiler/src/direct/function.zig).
namespace blot_direct_function;
import .function;

// The trampoline body: run the newest frame for this operation in the context
// it was installed in.
recursive fn operationBody(g: Generator&, f: Fn&, instance_id: u32, argument: Val) -> Val, Error {
    let key = g.s.instances[instance_id].key;
    let effect_context = g.runtime_().effect_context;
    let frame = local32(g, f);
    opIndex(g, OP_global_get, effect_context);
    opIndex(g, OP_local_set, frame);
    let found = open(g, f, OP_block);
    let search = open(g, f, OP_loop);
    // An unhandled operation: the checker rejects these in exports.
    opIndex(g, OP_local_get, frame);
    op(g, OP_i32_eqz);
    op(g, OP_if_);
    op(g, 0x40);
    op(g, OP_unreachable_);
    op(g, OP_end);
    opIndex(g, OP_local_get, frame);
    memoryOp(g, OP_i32_load, 0);
    i32Const(g, key.id);
    op(g, OP_i32_eq);
    br(g, f, OP_br_if, found);
    opIndex(g, OP_local_get, frame);
    memoryOp(g, OP_i32_load, 12);
    opIndex(g, OP_local_set, frame);
    br(g, f, OP_br, search);
    close(g, f);
    close(g, f);
    let saved = local32(g, f);
    opIndex(g, OP_global_get, effect_context);
    opIndex(g, OP_local_set, saved);
    opIndex(g, OP_local_get, frame);
    memoryOp(g, OP_i32_load, 12);
    opIndex(g, OP_global_set, effect_context);
    let slot = local32(g, f);
    let env = local32(g, f);
    opIndex(g, OP_local_get, frame);
    memoryOp(g, OP_i32_load, 4);
    opIndex(g, OP_local_set, slot);
    opIndex(g, OP_local_get, frame);
    memoryOp(g, OP_i32_load, 8);
    opIndex(g, OP_local_set, env);
    let signature = key.ty;
    let result, error = applyClosure(g, f, valOf2(g, signature, slot, env), argument, 0);
    if error != blot_direct_types::Error.none { return result, error; }
    opIndex(g, OP_local_get, saved);
    opIndex(g, OP_global_set, effect_context);
    return result, blot_direct_types::Error.none;
}
// `@effect.provider Operation implementation`: the implementation closure.
recursive fn effectProvider(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let n = g.units[f.unit - 1].node(id);
    let ty, error = typeOf(g, f, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let implementation, error = expr(g, f, n.b);
    if error != blot_direct_types::Error.none { return implementation, error; }
    if implementation.ty == blot_direct_types::never { return implementation, blot_direct_types::Error.none; }
    return Val { ty, implementation.start, implementation.len }, blot_direct_types::Error.none;
}
// `@effect.state Read Write initial`: the initial state.
recursive fn stateProvider(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let n = g.units[f.unit - 1].node(id);
    let ty, error = typeOf(g, f, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let initial, error = expr(g, f, n.c);
    if error != blot_direct_types::Error.none { return initial, error; }
    if initial.ty == blot_direct_types::never { return initial, blot_direct_types::Error.none; }
    return Val { ty, initial.start, initial.len }, blot_direct_types::Error.none;
}
fn pushHandleCells(g: Generator&, f: Fn&, saved: u32, depth: u32, cells_start: u32, cells_len: u32) {
    let at = f.handles_base + f.handles_len;
    if at < g.s.handles.len { g.s.handles[at] = blot_direct_emit::Handle { saved, depth, cells_start, cells_len }; }
    else { g.s.handles.push(blot_direct_emit::Handle { saved, depth, cells_start, cells_len }); }
    f.handles_len += 1;
}
fn pushHandle(g: Generator&, f: Fn&, saved: u32, depth: u32) {
    pushHandleCells(g, f, saved, depth, 0, 0);
}
// `with Effect = { ... }: suite`: allocates stack cells for linearly shadowed
// outer locals, pushes provider frames, runs `suite`, and reads final cell
// values into the post-`with` bindings.
recursive fn withHandleNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let n = g.units[f.unit - 1].node(id);
    let effect_context = g.runtime_().effect_context;
    let saved = local32(g, f);
    opIndex(g, OP_global_get, effect_context);
    opIndex(g, OP_local_set, saved);
    var outer_bs: u32[16] = [0; 16];
    var after_bs: u32[16] = [0; 16];
    var cell_locals: u32[16] = [0; 16];
    var cell_tys: Ty[16] = [0; 16];
    var prev_vals: Val[16] = [Val {}; 16];
    var prev_cells: Ty[16] = [0; 16];
    var cell_count: i64 = 0;
    let extra_start = n.b as i64;
    let extra_end = (n.b + n.c) as i64;
    for ei in extra_start..extra_end {
        let child = g.units[f.unit - 1].extra[ei];
        let cn = g.units[f.unit - 1].node(child);
        if cn.tag == blot_check_core::Tag.bind && cn.c == 1 && g.units[f.unit - 1].node(cn.b).tag == blot_check_core::Tag.reference {
            if cell_count >= 16 { return neverVal(), g.fail(g.units[f.unit - 1], child, "too many shadowed locals in one with handler"); }
            let outer_b = g.units[f.unit - 1].reference(cn.b).binding;
            let raw_prev, raw_ok = bindGet(g, f, outer_b);
            if !raw_ok { return neverVal(), g.fail(g.units[f.unit - 1], child, "with handler shadowed unbound local"); }
            let prev_cell_ty, had_cell = withCellType(g, f, outer_b);
            let outer_val, ok, rerr = readBindingVal(g, f, outer_b, child);
            if rerr != blot_direct_types::Error.none { return neverVal(), rerr; }
            if !ok { return neverVal(), g.fail(g.units[f.unit - 1], child, "with handler shadowed unbound local"); }
            let noted = noteStore(g, f, outer_val);
            if noted != blot_direct_types::Error.none { return neverVal(), noted; }
            let bytes, berr = g.types.flatBytes(outer_val.ty);
            if berr != blot_direct_types::Error.none { return neverVal(), berr; }
            let cell = allocate(g, f, bytes);
            if bytes != 0 {
                let werr = writeFlat(g, f, cell, 0, outer_val, child);
                if werr != blot_direct_types::Error.none { return neverVal(), werr; }
            }
            let cell_ty, cty_err = g.types.cell(outer_val.ty);
            if cty_err != blot_direct_types::Error.none { return neverVal(), cty_err; }
            outer_bs[cell_count] = outer_b;
            after_bs[cell_count] = cn.a;
            cell_locals[cell_count] = cell;
            cell_tys[cell_count] = outer_val.ty;
            prev_vals[cell_count] = raw_prev;
            if had_cell { prev_cells[cell_count] = prev_cell_ty; } else { prev_cells[cell_count] = 0; }
            cell_count += 1;
            bindPut(g, f, outer_b, valOf1(g, cell_ty, cell));
            blot_support_zigmap::put(g.s.map_pool, f.with_cells, outer_b, outer_val.ty);
        }
    }
    var prev_frame = saved;
    for ei in extra_start..extra_end {
        let child = g.units[f.unit - 1].extra[ei];
        let cn = g.units[f.unit - 1].node(child);
        if cn.tag == blot_check_core::Tag.effect_provider {
            let prov, perr = expr(g, f, child);
            if perr != blot_direct_types::Error.none {
                for ci in 0..cell_count {
                    bindPut(g, f, outer_bs[ci], prev_vals[ci]);
                    blot_support_zigmap::put(g.s.map_pool, f.with_cells, outer_bs[ci], prev_cells[ci]);
                }
                return prov, perr;
            }
            if prov.ty == blot_direct_types::never {
                for ci in 0..cell_count {
                    bindPut(g, f, outer_bs[ci], prev_vals[ci]);
                    blot_support_zigmap::put(g.s.map_pool, f.with_cells, outer_bs[ci], prev_cells[ci]);
                }
                return prov, blot_direct_types::Error.none;
            }
            let shape = g.types.node(prov.ty);
            if shape.tag != blot_direct_types::Tag.provider {
                for ci in 0..cell_count {
                    bindPut(g, f, outer_bs[ci], prev_vals[ci]);
                    blot_support_zigmap::put(g.s.map_pool, f.with_cells, outer_bs[ci], prev_cells[ci]);
                }
                return neverVal(), g.fail(g.units[f.unit - 1], child, "with handler provider has non-provider type");
            }
            pushFrame(g, f, g.operationId(shape.a), w(g, prov, 0), w(g, prov, 1), prev_frame);
            let next_frame = local32(g, f);
            opIndex(g, OP_global_get, effect_context);
            opIndex(g, OP_local_set, next_frame);
            prev_frame = next_frame;
        }
    }
    for ci in 0..cell_count {
        bindPut(g, f, outer_bs[ci], prev_vals[ci]);
        blot_support_zigmap::put(g.s.map_pool, f.with_cells, outer_bs[ci], prev_cells[ci]);
    }
    let cells_mark = g.s.handle_cells_len;
    for ci in 0..cell_count {
        let entry = blot_direct_emit::HandleCell { cell: cell_locals[ci], outer: prev_vals[ci], ty: cell_tys[ci], outer_is_cell: prev_cells[ci] != 0 };
        if g.s.handle_cells_len < g.s.handle_cells.len { g.s.handle_cells[g.s.handle_cells_len] = entry; }
        else { g.s.handle_cells.push(entry); }
        g.s.handle_cells_len += 1;
    }
    pushHandleCells(g, f, saved, f.depth, cells_mark as u32, cell_count as u32);
    let inner, error = stmt(g, f, n.a);
    if error != blot_direct_types::Error.none {
        f.handles_len -= 1;
        g.s.handle_cells_len = cells_mark;
        return inner, error;
    }
    f.handles_len -= 1;
    g.s.handle_cells_len = cells_mark;
    if inner.ty == blot_direct_types::never { return inner, blot_direct_types::Error.none; }
    opIndex(g, OP_local_get, saved);
    opIndex(g, OP_global_set, effect_context);
    for ci in 0..cell_count {
        let final, ferr = readFlat(g, f, cell_locals[ci], 0, cell_tys[ci], id);
        if ferr != blot_direct_types::Error.none { return neverVal(), ferr; }
        if prev_cells[ci] != 0 {
            let werr = writeWithCell(g, f, w(g, prev_vals[ci], 0), prev_cells[ci], final, id);
            if werr != blot_direct_types::Error.none { return neverVal(), werr; }
            bindPut(g, f, after_bs[ci], prev_vals[ci]);
            blot_support_zigmap::put(g.s.map_pool, f.with_cells, after_bs[ci], prev_cells[ci]);
        } else {
            bindPut(g, f, after_bs[ci], final);
        }
    }
    return inner, blot_direct_types::Error.none;
}
// `do provider: inner`: installs the provider's frames around `inner`. A
// state provider's block yields (final state, inner result).
recursive fn handleNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let provider, error = expr(g, f, n.a);
    if error != blot_direct_types::Error.none { return provider, error; }
    if provider.ty == blot_direct_types::never { return provider, blot_direct_types::Error.none; }
    let effect_context = g.runtime_().effect_context;
    let saved = local32(g, f);
    opIndex(g, OP_global_get, effect_context);
    opIndex(g, OP_local_set, saved);
    let shape = g.types.node(provider.ty);
    var has_cell = false;
    var cell: u32 = 0;
    var state: Ty = blot_direct_types::unit;
    match shape.tag {
        provider => { pushFrame(g, f, g.operationId(shape.a), w(g, provider, 0), w(g, provider, 1), saved); },
        state_provider => {
            let get_operation = g.types.words[shape.a];
            let set_operation = g.types.words[shape.a + 1];
            state = g.types.words[shape.a + 2];
            let bytes, error = g.types.flatBytes(state);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let address = allocate(g, f, bytes);
            let written = writeFlat(g, f, address, 0, Val { state, provider.start, provider.len }, id);
            if written != blot_direct_types::Error.none { return neverVal(), written; }
            has_cell = true;
            cell = address;
            let get, error = stateAccessor(g, f, blot_direct_emit::InstanceKind.state_get, state, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let set, error = stateAccessor(g, f, blot_direct_emit::InstanceKind.state_set, state, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let frame = local32(g, f);
            pushFrame(g, f, g.operationId(get_operation), get, address, saved);
            opIndex(g, OP_global_get, effect_context);
            opIndex(g, OP_local_set, frame);
            pushFrame(g, f, g.operationId(set_operation), set, address, frame);
        },
        _ => {
            g.failOpen(m, id);
            g.put("handling a value of type ");
            g.put(blot_direct_types::tagName(shape.tag));
            return neverVal(), g.failClose();
        },
    }
    pushHandle(g, f, saved, f.depth);
    let inner, error = expr(g, f, n.b);
    // Zig pops only after a successful operand.
    if error != blot_direct_types::Error.none { return inner, error; }
    f.handles_len -= 1;
    if inner.ty == blot_direct_types::never { return inner, blot_direct_types::Error.none; }
    opIndex(g, OP_local_get, saved);
    opIndex(g, OP_global_set, effect_context);
    if !has_cell { return inner, blot_direct_types::Error.none; }
    let final, error = readFlat(g, f, cell, 0, state, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let start = g.s.words.len as u32;
    for at in 0..(final.len as i64) { let word = g.s.words[final.start + at]; g.s.words.push(word); }
    for at in 0..(inner.len as i64) { let word = g.s.words[inner.start + at]; g.s.words.push(word); }
    let ty, error = g.types.tuple([state, inner.ty]);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    refine(g, f, m.typeOf(id), ty);
    return Val { ty, start, final.len + inner.len }, blot_direct_types::Error.none;
}
// A 4-byte-aligned load or store at constant `offset`.
fn memoryOp(g: Generator&, code: u8, offset: u32) {
    op(g, code);
    uleb(g, 2);
    uleb(g, offset);
}
// Pushes a frame {operation, slot, environment, previous} and makes it the
// effect context. `slot` and `environment` are locals.
fn pushFrame(g: Generator&, f: Fn&, operation_id: u32, slot: u32, environment: u32, previous: u32) {
    let effect_context = g.runtime_().effect_context;
    let frame = allocate(g, f, 16);
    let sources: u32[4] = [0, slot, environment, previous];
    for index in 0..4 {
        opIndex(g, OP_local_get, frame);
        if index == 0 { i32Const(g, operation_id); } else { opIndex(g, OP_local_get, sources[index]); }
        memoryOp(g, OP_i32_store, (index * 4) as u32);
    }
    opIndex(g, OP_local_get, frame);
    opIndex(g, OP_global_set, effect_context);
}
// A local holding the table slot of a state cell accessor closure.
fn stateAccessor(g: Generator&, f: Fn&, kind: InstanceKind, state: Ty, id: u32) -> u32, Error {
    let key = InstanceKey { kind, 0, 0, state, 0, 0 };
    var parameter = state;
    var result = blot_direct_types::unit;
    if kind == blot_direct_emit::InstanceKind.state_get { parameter = blot_direct_types::unit; result = state; }
    var instance, present = g.find(key);
    if !present {
        let made, error = g.addInstanceWith(key, Env {}, g.saveTys([parameter]), result, true, Tys {}, g.units[f.unit - 1], id);
        if error != blot_direct_types::Error.none { return 0, error; }
        instance = made;
    }
    let slot = local32(g, f);
    i32Const(g, g.s.instances[instance].slot);
    opIndex(g, OP_local_set, slot);
    return slot, blot_direct_types::Error.none;
}
// Restores the effect context (and writes back any `with` handler cells)
// when control leaves installed providers for a block at `depth` or outside.
fn leaveHandles(g: Generator&, f: Fn&, depth: u32) -> Error {
    var has_restore = false;
    var restore_saved: u32 = 0;
    var at = f.handles_len as i64;
    while at != 0 {
        at -= 1;
        let installed = g.s.handles[f.handles_base + at];
        if installed.depth < depth { break; }
        for ci in 0..(installed.cells_len as i64) {
            let hc = g.s.handle_cells[installed.cells_start + ci];
            let final, rerr = readFlat(g, f, hc.cell, 0, hc.ty, 0);
            if rerr != blot_direct_types::Error.none { return rerr; }
            if hc.outer_is_cell {
                let werr = writeWithCell(g, f, w(g, hc.outer, 0), hc.ty, final, 0);
                if werr != blot_direct_types::Error.none { return werr; }
            } else {
                let cerr = copy(g, f, final, hc.outer, 0);
                if cerr != blot_direct_types::Error.none { return cerr; }
            }
        }
        has_restore = true;
        restore_saved = installed.saved;
    }
    if has_restore {
        let effect_context = g.runtime_().effect_context;
        opIndex(g, OP_local_get, restore_saved);
        opIndex(g, OP_global_set, effect_context);
    }
    return blot_direct_types::Error.none;
}
