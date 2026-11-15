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
fn pushHandle(g: Generator&, f: Fn&, saved: u32, depth: u32) {
    let at = f.handles_base + f.handles_len;
    if at < g.s.handles.len { g.s.handles[at] = blot_direct_emit::Handle { saved, depth }; }
    else { g.s.handles.push(blot_direct_emit::Handle { saved, depth }); }
    f.handles_len += 1;
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
    let key = InstanceKey { kind, 0, 0, state, 0 };
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
// Restores the effect context when control leaves installed providers for a
// block at `depth` or outside.
fn leaveHandles(g: Generator&, f: const Fn&, depth: u32) {
    for at in 0..(f.handles_len as i64) {
        let installed = g.s.handles[f.handles_base + at];
        if installed.depth >= depth {
            let effect_context = g.runtime_().effect_context;
            opIndex(g, OP_local_get, installed.saved);
            opIndex(g, OP_global_set, effect_context);
            return;
        }
    }
}
