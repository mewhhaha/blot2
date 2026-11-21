// Conditionals, blocks, matches and loops of the direct backend's function
// emitter (compiler/src/direct/function.zig).
namespace blot_direct_function;
import .function;

// `count` empty result slots; the first one's index.
fn newSlots(g: Generator&, count: i64) -> u32 {
    let first = g.s.slots.len as u32;
    for at in 0..count { g.s.slots.push(blot_direct_emit::Slot {}); }
    return first;
}
recursive fn ifNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let result = g.newSlot();
    let merges = m.branchMerges(id);
    let merged = newSlots(g, merges.len);
    let condition, error = expr(g, f, n.a);
    if error != blot_direct_types::Error.none { return condition, error; }
    push(g, condition);
    let opened = open(g, f, OP_if_);
    let then, error = stmt(g, f, n.b);
    if error != blot_direct_types::Error.none { return then, error; }
    var falls = then.ty != blot_direct_types::never;
    if falls {
        if n.tag == blot_check_core::Tag.if_value {
            let delivered = deliver(g, f, then, result, id);
            if delivered != blot_direct_types::Error.none { return neverVal(), delivered; }
        }
        for merge, at in merges {
            let value, present = bindGet(g, f, merge.then_binding);
            if present {
                let delivered = deliver(g, f, value, merged + (at as u32), id);
                if delivered != blot_direct_types::Error.none { return neverVal(), delivered; }
            }
        }
    }
    op(g, OP_else_);
    if n.c != 0 {
        let otherwise, error = stmt(g, f, n.c);
        if error != blot_direct_types::Error.none { return otherwise, error; }
        if otherwise.ty != blot_direct_types::never {
            falls = true;
            if n.tag == blot_check_core::Tag.if_value {
                let delivered = deliver(g, f, otherwise, result, id);
                if delivered != blot_direct_types::Error.none { return neverVal(), delivered; }
            }
            for merge, at in merges {
                let value, present = bindGet(g, f, merge.else_binding);
                if present {
                    let delivered = deliver(g, f, value, merged + (at as u32), id);
                    if delivered != blot_direct_types::Error.none { return neverVal(), delivered; }
                }
            }
        }
    } else {
        falls = true;
        for merge, at in merges {
            let value, present = bindGet(g, f, merge.else_binding);
            if present {
                let delivered = deliver(g, f, value, merged + (at as u32), id);
                if delivered != blot_direct_types::Error.none { return neverVal(), delivered; }
            }
        }
    }
    close(g, f);
    for merge, at in merges {
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
    if !falls { return neverVal(), blot_direct_types::Error.none; }
    if n.tag == blot_check_core::Tag.if_stmt { return unitVal(), blot_direct_types::Error.none; }
    if g.s.slots[result].present { return g.s.slots[result].value, blot_direct_types::Error.none; }
    return neverVal(), blot_direct_types::Error.none;
}

// Only visit a block whose value is returned by the function itself. Once a
// return starts, another block's continuation cannot run before the exit.
fn scratchBody(m: const Module&, root: u32) -> u32 {
    var current = root;
    for step in 0..8 {
        let node = m.node(current);
        if node.tag == blot_check_core::Tag.return_ { current = node.a; continue; }
        if node.tag != blot_check_core::Tag.block_ { return 0; }
        if node.b != 1 { return current; }
        let only = m.children(current)[0];
        if m.node(only).tag != blot_check_core::Tag.return_ { return 0; }
        current = only;
    }
    return 0;
}

// The block ends by returning scalar reads from freshly produced storage.
// The array literal commits the result after those reads finish.
fn scratchLiteral(g: Generator&, f: Fn&, tail: const u32[:]) -> u32 {
    let m .= g.units[f.unit - 1];
    let producer = m.node(tail[0]);
    if producer.tag != blot_check_core::Tag.bind || producer.c != 0 { return 0; }
    let init = m.node(producer.b);
    if init.tag != blot_check_core::Tag.array_op { return 0; }
    let operation = m.arrayOperation(producer.b);
    if operation != blot_backend_collection_ops::Op.generate && operation != blot_backend_collection_ops::Op.fill { return 0; }
    let shape = m.types.node(init.ty);
    if shape.tag != blot_check_types::Tag.array || !scratchScalarType(m, shape.a) { return 0; }
    let next = m.node(tail[1]);
    var literal: u32 = 0;
    if tail.len == 2 && next.tag == blot_check_core::Tag.return_ { literal = next.a; }
    else if tail.len == 3 && next.tag == blot_check_core::Tag.bind && m.node(next.b).tag == blot_check_core::Tag.update {
        let returned = m.node(tail[2]);
        if returned.tag != blot_check_core::Tag.return_ || localRef(m, returned.a) != next.a { return 0; }
        let update = m.updateInfo(next.b);
        if update.store || !scratchFieldUpdate(m, update, next.b) { return 0; }
        let root = localRef(m, update.root);
        if root == 0 || root == producer.a { return 0; }
        let value, found = bindGet(g, f, root);
        // A structural record reaches the replacement once. A sum can
        // emit the replacement separately in several branches.
        if !found || tagOf(g, value.ty) != blot_direct_types::Tag.record { return 0; }
        literal = update.value;
    } else { return 0; }
    if m.node(literal).tag != blot_check_core::Tag.array { return 0; }
    var reads = false;
    for element in m.children(literal) {
        if !scratchScalar(g, f, m, element, producer.a, 0, reads, 0) { return 0; }
    }
    if !reads { return 0; }
    let arguments = m.children(producer.b);
    var ignored = false;
    if arguments.len != 2 || !scratchScalar(g, f, m, arguments[0], 0, 0, ignored, 0) { return 0; }
    if operation == blot_backend_collection_ops::Op.fill {
        if !scratchScalar(g, f, m, arguments[1], 0, 0, ignored, 0) { return 0; }
    } else {
        let mapper = arguments[1];
        if m.node(mapper).tag != blot_check_core::Tag.closure { return 0; }
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
    if m.node(id).tag != blot_check_core::Tag.reference { return 0; }
    let ref = m.reference(id);
    if ref.unit != 0 && ref.unit != m.unit { return 0; }
    return ref.binding;
}

fn scratchFieldUpdate(m: const Module&, update: blot_check_core::UpdateInfo, id: u32) -> bool {
    let selectors = m.updateSelectors(id);
    if selectors.len == 0 { return update.path.len == 1; }
    return selectors.len == 1 && selectors[0].kind == blot_check_core::UpdateKind.field;
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
    return tag == blot_check_types::Tag.unsigned32 || tag == blot_check_types::Tag.floating32 || tag == blot_check_types::Tag.boolean;
}

fn scratchReturned(m: const Module&, id: u32) -> u32 {
    var current = id;
    for step in 0..8 {
        let n = m.node(current);
        if n.tag == blot_check_core::Tag.return_ { current = n.a; }
        else if n.tag == blot_check_core::Tag.block_ && n.b == 1 { current = m.children(current)[0]; }
        else { break; }
    }
    return current;
}

// Use the same scalar forwarding shape as call emission. Such a call
// reads only its proved scalar operands and has no storage operation.
fn scratchScalarCallee(g: const Generator&, m: const Module&, call: blot_check_core::Call) -> bool {
    let target = g.resolve(m, call.target);
    if !g.hasUnit(target.unit) { return false; }
    let owner .= g.units[target.unit - 1];
    let alias, present = primitiveAlias(owner, target.binding);
    if present {
        let primitive = owner.primitive(alias);
        return primitive.kind == blot_check_core::PrimitiveKind.scalar && primitive.arity == call.arguments.len;
    }
    let body .= owner.body(target.binding);
    if !body || !body.is_function { return false; }
    let parameters = owner.bodyParameters(body);
    if parameters.len != call.arguments.len { return false; }
    let node = owner.node(scratchReturned(owner, body.root));
    if node.tag != blot_check_core::Tag.associated || node.op == blot_check_core::Op.none { return false; }
    for operand in [node.a, node.b] {
        if operand == 0 { continue; }
        if owner.node(operand).tag != blot_check_core::Tag.reference { return false; }
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
            if n.tag == blot_check_core::Tag.associated && n.op == blot_check_core::Op.none { return false; }
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
            if op != blot_backend_collection_ops::Op.get && op != blot_backend_collection_ops::Op.length { return false; }
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

recursive fn block_(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let result = g.newSlot();
    let depth = open(g, f, OP_block);
    let s .= g.s;
    let mark = s.labels.len;
    s.labels.push(blot_direct_emit::Label { target: id, depth: depth, result: result });
    var last = unitVal();
    let children = m.children(id);
    let saved = f.scratch_cut;
    for child, at in children {
        // Statements after one that always diverges are unreachable.
        if last.ty == blot_direct_types::never { break; }
        if id == f.scratch_body { markScratchPair(g, f, children, at); }
        let value, error = stmt(g, f, child);
        if error != blot_direct_types::Error.none { f.scratch_cut = saved; s.labels.resize(mark); return value, error; }
        last = value;
    }
    f.scratch_cut = saved;
    s.labels.resize(mark);
    close(g, f);
    if g.s.slots[result].present { return g.s.slots[result].value, blot_direct_types::Error.none; }
    // A Unit block may fall through its end.
    if last.ty != blot_direct_types::never && m.typeOf(id) == blot_check_types::unit { return unitVal(), blot_direct_types::Error.none; }
    return neverVal(), blot_direct_types::Error.none;
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
    let result, error = block_(g, f, n.a);
    if error != blot_direct_types::Error.none { return result, error; }
    gget(g, rt.fork_depth);
    i32Const(g, 1);
    op(g, OP_i32_sub);
    gset(g, rt.fork_depth);
    lget(g, saved_undo);
    callf(g, rt.undo_rewind);
    lget(g, saved_mark);
    gset(g, rt.fork_owner_mark);
    return result, blot_direct_types::Error.none;
}

fn findComptimeFrame(f: const Fn&, binder: u32) -> i64 {
    var i = f.comptime_len;
    while i > 0 {
        i -= 1;
        if f.comptime_frames[i].binder == binder { return i; }
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
                if n.b == binder && m.types.node(n.ty).tag == blot_check_types::Tag.variable {
                    recordProjVar(vars, count, n.ty);
                }
                collectComptimeProjectVars(m, n.a, binder, vars, count, depth + 1);
            } else if n.c == 8 || n.c == 9 {
                collectComptimeProjectVars(m, n.b, binder, vars, count, depth + 1);
            }
        },
        comptime_for => {
            if n.a != binder { collectComptimeProjectVars(m, n.b, binder, vars, count, depth + 1); }
        },
        comptime_if, if_value, if_stmt, state_provider, resource_scope => {
            collectComptimeProjectVars(m, n.a, binder, vars, count, depth + 1);
            collectComptimeProjectVars(m, n.b, binder, vars, count, depth + 1);
            collectComptimeProjectVars(m, n.c, binder, vars, count, depth + 1);
        },
        suite, block_, product, record, array, array_op, storage, task => {
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
        return_, project, result_associated, computation, effect_scope, fork_, resource_release, usage_share, usage_read => {
            collectComptimeProjectVars(m, n.a, binder, vars, count, depth + 1);
        },
        scalar, logical, apply, associated, record_merge, type_same, effect_provider, handle, proof_guard, resource_acquire, usage_borrow, staging => {
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
            for step in m.updateSelectors(id) { collectComptimeProjectVars(m, step.index, binder, vars, count, depth + 1); }
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
        _ => {},
    }
}

recursive fn comptimeForNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let cstart = m.extra[n.c];
    let clen = m.extra[n.c + 1];
    let mode = m.extra[n.c + 2];
    let carries = m.loop_carries[cstart..cstart + clen];
    let target_ty, terr = lower(g, f, m.binding(n.a).ty, id);
    if terr != blot_direct_types::Error.none { return neverVal(), terr; }
    let current = g.reserveVals(carries.len);
    for carry, at in carries {
        let value, present, rerr = readBindingVal(g, f, carry.incoming, id);
        if rerr != blot_direct_types::Error.none { return neverVal(), rerr; }
        if !present { return neverVal(), g.fail(m, id, "#for carry without an incoming value"); }
        g.s.vals[current.start + at] = value;
    }
    var proj_vars: u32[64] = [0; 64];
    var proj_var_len: i64 = 0;
    if mode == 0 { collectComptimeProjectVars(m, n.b, n.a, proj_vars, proj_var_len, 0); }
    let saved_env = f.env;
    if mode == 0 {
        var record_ty: Ty = 0;
        var nom_unit: u32 = 0;
        var nom_decl: u32 = 0;
        var ctor_tag: u32 = 0;
        if tagOf(g, target_ty) == blot_direct_types::Tag.record {
            record_ty = target_ty;
        } else if tagOf(g, target_ty) == blot_direct_types::Tag.nominal {
            let nom_id = g.types.nominalIdentity(target_ty);
            nom_unit = nom_id.unit;
            nom_decl = nom_id.decl;
            let cases, verr = g.types.variants(target_ty);
            if verr != blot_direct_types::Error.none { return neverVal(), g.typeFailure(m, id); }
            if cases.len != 1 { return neverVal(), g.fail(m, id, "#fields requires a single-constructor data type"); }
            ctor_tag = g.types.variant_tags[cases.tags];
            let payload = g.types.variant_payloads[cases.payloads];
            if payload != blot_direct_types::unit {
                if tagOf(g, payload) != blot_direct_types::Tag.record { return neverVal(), g.fail(m, id, "#fields requires a record payload"); }
                record_ty = payload;
            }
        } else {
            return neverVal(), g.fail(m, id, "#fields requires a record or single-constructor data type");
        }
        var field_count: i64 = 0;
        if record_ty != 0 { field_count = g.types.node(record_ty).b as i64; }
        for fi in 0..field_count {
            let fld = g.types.recordField(record_ty, fi);
            f.env = saved_env;
            for pi in 0..proj_var_len { g.types.envPut(f.env, f.unit, proj_vars[pi], fld.ty); }
            for carry, at in carries { bindPut(g, f, carry.iteration, g.s.vals[current.start + at]); }
            if f.comptime_len >= 16 { f.env = saved_env; return neverVal(), g.fail(m, id, "#for nesting limit exceeded"); }
            f.comptime_frames[f.comptime_len] = ComptimeFrame {
                binder: n.a, is_variants: false, target_ty: target_ty,
                nominal_unit: nom_unit, nominal_decl: nom_decl,
                index: fi as u32, ctor_tag: ctor_tag, name_id: fld.name, field_ty: fld.ty,
            };
            f.comptime_len += 1;
            let iter_val, ierr = stmt(g, f, n.b);
            f.comptime_len -= 1;
            if ierr != blot_direct_types::Error.none { f.env = saved_env; return iter_val, ierr; }
            if iter_val.ty == blot_direct_types::never { f.env = saved_env; return neverVal(), blot_direct_types::Error.none; }
            for carry, at in carries {
                let bv, ok, berr = readBindingVal(g, f, carry.backedge, id);
                if berr != blot_direct_types::Error.none { f.env = saved_env; return neverVal(), berr; }
                if ok { g.s.vals[current.start + at] = bv; }
            }
        }
        f.env = saved_env;
    } else {
        if tagOf(g, target_ty) != blot_direct_types::Tag.nominal { return neverVal(), g.fail(m, id, "#variants requires a nominal data type"); }
        let nom_id = g.types.nominalIdentity(target_ty);
        if !g.hasUnit(nom_id.unit) { return neverVal(), g.fail(m, id, "#variants defining unit missing"); }
        let owner .= g.units[nom_id.unit - 1];
        let ordinal, oerr = g.types.nominalOrdinal(owner, nom_id);
        if oerr != blot_direct_types::Error.none { return neverVal(), g.typeFailure(m, id); }
        let ctors = owner.nominalConstructors(ordinal);
        for ctor_idx, ci in ctors {
            let ctor = owner.constructor(ctor_idx);
            var name_id: u32 = 0;
            let sp = owner.fieldSpelling(ctor.name);
            if sp.present { name_id = g.types.fieldName(sp.value); }
            for carry, at in carries { bindPut(g, f, carry.iteration, g.s.vals[current.start + at]); }
            if f.comptime_len >= 16 { return neverVal(), g.fail(m, id, "#for nesting limit exceeded"); }
            f.comptime_frames[f.comptime_len] = ComptimeFrame {
                binder: n.a, is_variants: true, target_ty: target_ty,
                nominal_unit: nom_id.unit, nominal_decl: nom_id.decl,
                index: ci as u32, ctor_tag: ctor.tag, name_id: name_id, field_ty: 0,
            };
            f.comptime_len += 1;
            let iter_val, ierr = stmt(g, f, n.b);
            f.comptime_len -= 1;
            if ierr != blot_direct_types::Error.none { return iter_val, ierr; }
            if iter_val.ty == blot_direct_types::never { return neverVal(), blot_direct_types::Error.none; }
            for carry, at in carries {
                let bv, ok, berr = readBindingVal(g, f, carry.backedge, id);
                if berr != blot_direct_types::Error.none { return neverVal(), berr; }
                if ok { g.s.vals[current.start + at] = bv; }
            }
        }
    }
    for carry, at in carries { bindPut(g, f, carry.outgoing, g.s.vals[current.start + at]); }
    return unitVal(), blot_direct_types::Error.none;
}

recursive fn comptimeIfNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    var s = Stage {..};
    let cond = evaluateStage(g, f, s, m, n.a, 0, 0);
    let failed = s.failure;
    blot_support_pooled_buffer::deinit(s.functions, stage_function_runs);
    blot_support_pooled_buffer::deinit(s.parts, part_runs);
    blot_support_pooled_buffer::deinit(s.aggregates, aggregate_runs);
    blot_support_pooled_buffer::deinit(s.bindings, binding_runs);
    if failed.len != 0 { return neverVal(), g.fail(m, n.a, failed); }
    let taken = cond.bits != 0;
    var branch = n.c;
    if taken { branch = n.b; }
    if branch != 0 {
        let res, err = stmt(g, f, branch);
        if err != blot_direct_types::Error.none { return res, err; }
        if res.ty == blot_direct_types::never { return neverVal(), blot_direct_types::Error.none; }
    }
    for merge in m.branchMerges(id) {
        var from_b = merge.else_binding;
        if taken { from_b = merge.then_binding; }
        let val, present = bindGet(g, f, from_b);
        if present { bindPut(g, f, merge.result, val); }
    }
    return unitVal(), blot_direct_types::Error.none;
}

recursive fn comptimeMetaNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    if n.c == 0 {
        let fidx = findComptimeFrame(f, n.b);
        if fidx < 0 { return neverVal(), g.fail(m, id, "comptime field projection outside #for"); }
        let cf = f.comptime_frames[fidx];
        let val, err = expr(g, f, n.a);
        if err != blot_direct_types::Error.none { return val, err; }
        var rec = val;
        if tagOf(g, val.ty) == blot_direct_types::Tag.nominal {
            let cases, verr = g.types.variants(val.ty);
            if verr != blot_direct_types::Error.none { return neverVal(), g.typeFailure(m, id); }
            if cases.len != 1 { return neverVal(), g.fail(m, id, "val.(field) requires a single-constructor data type"); }
            let unwrapped, uerr = unwrapVariant(g, f, val, g.types.variant_tags[cases.tags], id);
            if uerr != blot_direct_types::Error.none { return neverVal(), uerr; }
            rec = unwrapped;
        }
        let pos = g.types.findField(rec.ty, cf.name_id);
        if pos < 0 { return neverVal(), g.fail(m, id, "comptime projected field missing"); }
        return recordField(g, f, rec, pos, id);
    }
    if n.c == 1 {
        let fidx = findComptimeFrame(f, n.a);
        if fidx < 0 { return neverVal(), g.fail(m, id, "comptime .name outside #for"); }
        let text = g.types.spelling(f.comptime_frames[fidx].name_id);
        let arr_ty, terr = typeOf(g, f, id);
        if terr != blot_direct_types::Error.none { return neverVal(), terr; }
        var cp_count: i64 = 0;
        var p: i64 = 0;
        while p < text.len { let _, next = utf8Next(text, p); cp_count += 1; p = next; }
        let vals = g.reserveVals(cp_count);
        p = 0;
        var idx: i64 = 0;
        while p < text.len {
            let cp, next = utf8Next(text, p);
            g.s.vals[vals.start + idx] = valOf1(g, blot_direct_types::u32_, constLocal(g, f, cp));
            idx += 1;
            p = next;
        }
        return arrayFromValues(g, f, arr_ty, vals, id);
    }
    var s = Stage {..};
    let v = evalComptimeMetaStage(g, f, s, m, id, 0, 0);
    var result = neverVal();
    var error = blot_direct_types::Error.none;
    if s.failure.len != 0 { error = g.fail(m, id, s.failure); }
    else {
        let ty, lerr = typeOf(g, f, id);
        error = lerr;
        if error == blot_direct_types::Error.none {
            var remaining: i64 = 65536;
            result, error = emitStageValue(g, f, s, v, ty, id, remaining, 0);
        }
    }
    blot_support_pooled_buffer::deinit(s.functions, stage_function_runs);
    blot_support_pooled_buffer::deinit(s.parts, part_runs);
    blot_support_pooled_buffer::deinit(s.aggregates, aggregate_runs);
    blot_support_pooled_buffer::deinit(s.bindings, binding_runs);
    return result, error;
}
// Copies `value` into a lazily allocated result slot.
fn deliver(g: Generator&, f: const Fn&, value: Val, slot: u32, id: u32) -> Error {
    if value.ty == blot_direct_types::never { return blot_direct_types::Error.none; }
    if !g.s.slots[slot].present {
        let made, error = fresh(g, f, value.ty, id);
        if error != blot_direct_types::Error.none { return error; }
        g.s.slots[slot] = blot_direct_emit::Slot { true, made };
    }
    return copy(g, f, value, g.s.slots[slot].value, id);
}

recursive fn returnNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let value, error = stmt(g, f, n.a);
    if error != blot_direct_types::Error.none { return value, error; }
    if value.ty == blot_direct_types::never { return neverVal(), blot_direct_types::Error.none; }
    var at = g.s.labels.len;
    while at != f.labels_base {
        at -= 1;
        let label = g.s.labels[at];
        if (label.target != n.b && label.kind != blot_direct_emit::LabelKind.function) || label.kind == blot_direct_emit::LabelKind.loop_ { continue; }
        let delivered = deliver(g, f, value, label.result, id);
        if delivered != blot_direct_types::Error.none { return neverVal(), delivered; }
        let left = leaveHandles(g, f, label.depth);
        if left != blot_direct_types::Error.none { return neverVal(), left; }
        br(g, f, OP_br, label.depth);
        return neverVal(), blot_direct_types::Error.none;
    }
    return neverVal(), g.fail(g.units[f.unit - 1], id, "return outside its block");
}

fn sameWords(g: const Generator&, left: Val, right: Val) -> bool {
    if left.len != right.len { return false; }
    for at in 0..(left.len as i64) { if g.s.words[left.start + at] != g.s.words[right.start + at] { return false; } }
    return true;
}
recursive fn match_(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let info = m.matchInfo(id);
    let inputs = m.matchInputs(id);
    let values = g.reserveVals(inputs.len);
    for input, at in inputs {
        let value, error = expr(g, f, input);
        if error != blot_direct_types::Error.none { return value, error; }
        g.s.vals[values.start + at] = value;
    }
    let result = g.newSlot();
    let merges = m.branchMerges(id);
    let merged = newSlots(g, merges.len);
    var falls = false;
    let done = open(g, f, OP_block);
    let arms = m.matchArms(id);
    var fbip_block: u32 = 0;
    var fbip_ty: Ty = 0;
    if !info.statement && inputs.len == 1 && !g.runtime_().has_fork {
        let matched_binding = localRef(m, inputs[0]);
        if matched_binding != 0 && isUniqueBoxed(g, f, matched_binding) && uses(g, f, matched_binding) == 1 && !bindingCaptured(m, matched_binding) {
            let input_val = g.s.vals[values.start];
            let boxed, berr = isBoxed(g, f, input_val.ty, id);
            if berr == blot_direct_types::Error.none && boxed && input_val.len == 1 {
                fbip_block = w(g, input_val, 0);
                fbip_ty = input_val.ty;
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
                if tested != blot_direct_types::Error.none { return neverVal(), tested; }
            }
        } else {
            // Alternatives bind the same names; later rows copy into the first row's locals.
            let matched = open(g, f, OP_block);
            var first = blot_support_zigmap::Map {};
            for row, row_index in rows {
                let row_fail = open(g, f, OP_block);
                let before = blot_support_zigmap::clone(g.s.map_pool, f.bindings);
                let patterns = m.rowPatterns(row);
                for pattern, at in patterns {
                    let tested = test_(g, f, pattern, g.s.vals[values.start + at], true, row_fail, id);
                    if tested != blot_direct_types::Error.none { return neverVal(), tested; }
                }
                if row_index == 0 {
                    // Zig walks its hash map here; the table keeps its order.
                    let table = f.bindings;
                    for slot in 0..(table.capacity as i64) {
                        if !blot_support_zigmap::used(g.s.map_pool, table, slot as u32) { continue; }
                        let key = blot_support_zigmap::keyAt(g.s.map_pool, table, slot as u32);
                        let entry = g.s.vals[blot_support_zigmap::valueAt(g.s.map_pool, table, slot as u32)];
                        let prior_at, has_prior = blot_support_zigmap::get(g.s.map_pool, before, key);
                        if has_prior && sameWords(g, g.s.vals[prior_at], entry) { continue; }
                        let owned, error = fresh(g, f, entry.ty, id);
                        if error != blot_direct_types::Error.none { return neverVal(), error; }
                        let copied = copy(g, f, entry, owned, id);
                        if copied != blot_direct_types::Error.none { return neverVal(), copied; }
                        g.s.vals.push(owned);
                        blot_support_zigmap::put(g.s.map_pool, first, key, (g.s.vals.len - 1) as u32);
                    }
                } else {
                    // Every name the first row binds: a later row's payload
                    // may sit in the same locals as the first row's.
                    for slot in 0..(first.capacity as i64) {
                        if !blot_support_zigmap::used(g.s.map_pool, first, slot as u32) { continue; }
                        let key = blot_support_zigmap::keyAt(g.s.map_pool, first, slot as u32);
                        let target = g.s.vals[blot_support_zigmap::valueAt(g.s.map_pool, first, slot as u32)];
                        let value, present = bindGet(g, f, key);
                        if present {
                            let copied = copy(g, f, value, target, id);
                            if copied != blot_direct_types::Error.none { return neverVal(), copied; }
                        }
                    }
                }
                br(g, f, OP_br, matched);
                close(g, f);
            }
            br(g, f, OP_br, next);
            close(g, f);
            for slot in 0..(first.capacity as i64) {
                if !blot_support_zigmap::used(g.s.map_pool, first, slot as u32) { continue; }
                let key = blot_support_zigmap::keyAt(g.s.map_pool, first, slot as u32);
                bindPut(g, f, key, g.s.vals[blot_support_zigmap::valueAt(g.s.map_pool, first, slot as u32)]);
            }
        }
        if arm.guard_ != 0 {
            let guard_value, error = expr(g, f, arm.guard_);
            if error != blot_direct_types::Error.none { return guard_value, error; }
            push(g, guard_value);
            op(g, OP_i32_eqz);
            br(g, f, OP_br_if, next);
        }
        let prev_reuse_node = f.reuse_node;
        let prev_reuse_block = f.reuse_block;
        let prev_reuse_ty = f.reuse_ty;
        if fbip_block != 0 {
            let target_construct = tailConstruct(m, arm.body);
            if target_construct != 0 {
                f.reuse_node = target_construct;
                f.reuse_block = fbip_block;
                f.reuse_ty = fbip_ty;
            }
        }
        let body, error = stmt(g, f, arm.body);
        f.reuse_node = prev_reuse_node;
        f.reuse_block = prev_reuse_block;
        f.reuse_ty = prev_reuse_ty;
        if error != blot_direct_types::Error.none { return body, error; }
        if body.ty != blot_direct_types::never {
            falls = true;
            if !info.statement {
                let delivered = deliver(g, f, body, result, id);
                if delivered != blot_direct_types::Error.none { return neverVal(), delivered; }
            }
            // A two-arm statement match carries rebindings like an if.
            if merges.len != 0 && arm_index < 2 {
                for merge, at in merges {
                    var binding = merge.else_binding;
                    if arm_index == 0 { binding = merge.then_binding; }
                    let value, present = bindGet(g, f, binding);
                    if present {
                        let delivered = deliver(g, f, value, merged + (at as u32), id);
                        if delivered != blot_direct_types::Error.none { return neverVal(), delivered; }
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
            let ct1, ok1 = withCellType(g, f, merge.then_binding);
            if ok1 { blot_support_zigmap::put(g.s.map_pool, f.with_cells, merge.result, ct1); }
            else {
                let ct2, ok2 = withCellType(g, f, merge.else_binding);
                if ok2 { blot_support_zigmap::put(g.s.map_pool, f.with_cells, merge.result, ct2); }
            }
        }
    }
    if !falls { return neverVal(), blot_direct_types::Error.none; }
    if info.statement { return unitVal(), blot_direct_types::Error.none; }
    if g.s.slots[result].present { return g.s.slots[result].value, blot_direct_types::Error.none; }
    return neverVal(), blot_direct_types::Error.none;
}

// Tests `pattern` against `value`, branching to `fail` (a Wasm depth) on
// mismatch, and binds its names. Without `has_fail` a mismatch traps.
recursive fn test_(g: Generator&, f: Fn&, pattern_id: u32, value: Val, has_fail: bool, fail: u32, id: u32) -> Error {
    let m .= g.units[f.unit - 1];
    let pattern = m.pattern(pattern_id);
    if value.ty == blot_direct_types::never { return blot_direct_types::Error.none; }
    match pattern.tag {
        wildcard => {},
        bind => {
            refine(g, f, m.binding(pattern.a).ty, value.ty);
            bindPut(g, f, pattern.a, value);
        },
        constant, value => {
            let tag = g.types.node(value.ty).tag;
            // Unit has one value: its pattern always matches.
            if tag == blot_direct_types::Tag.unit {
                if pattern.tag == blot_check_core::PatternTag.value {
                    let ignored, error = expr(g, f, pattern.a);
                    if error != blot_direct_types::Error.none { return error; }
                }
                return blot_direct_types::Error.none;
            }
            push(g, value);
            if pattern.tag == blot_check_core::PatternTag.constant {
                if tag == blot_direct_types::Tag.f32_ { f32Const(g, pattern.a); } else { i32Const(g, pattern.a); }
            } else {
                let expected, error = expr(g, f, pattern.a);
                if error != blot_direct_types::Error.none { return error; }
                push(g, expected);
            }
            if tag == blot_direct_types::Tag.f32_ { op(g, OP_f32_ne); } else { op(g, OP_i32_ne); }
            failIf(g, f, has_fail, fail);
        },
        product => {
            let children = m.patternChildren(pattern_id);
            let shape = g.types.node(value.ty);
            match shape.tag {
                tuple => {
                    for child, index in children {
                        let item, error = tupleItem(g, f, value, index, id);
                        if error != blot_direct_types::Error.none { return error; }
                        let tested = test_(g, f, child, item, has_fail, fail, id);
                        if tested != blot_direct_types::Error.none { return tested; }
                    }
                },
                unit => {},
                // Children follow the pattern's Core record type order.
                record => { return recordPattern(g, f, pattern_id, false, m.types.node(pattern.ty), value, has_fail, fail, id); },
                _ => {
                    g.failOpen(m, id);
                    g.put("product pattern on a ");
                    g.put(blot_direct_types::tagName(shape.tag));
                    return g.failClose();
                },
            }
        },
        constructor => {
            let constructor = m.constructor(pattern.a);
            let cases, error = g.types.variants(value.ty);
            if error != blot_direct_types::Error.none { return g.typeFailure(m, id); }
            if cases.len > 1 {
                lget(g, w(g, value, 0));
                // A boxed value's tag is the first word of its block.
                let boxed, error = isBoxed(g, f, value.ty, id);
                if error != blot_direct_types::Error.none { return error; }
                if boxed {
                    op(g, OP_i32_load);
                    uleb(g, 2);
                    uleb(g, 0);
                }
                i32Const(g, constructor.tag);
                op(g, OP_i32_ne);
                failIf(g, f, has_fail, fail);
            }
            if pattern.b != 0 {
                let payload, error = unwrapVariant(g, f, value, constructor.tag, id);
                if error != blot_direct_types::Error.none { return error; }
                return test_(g, f, pattern.b, payload, has_fail, fail, id);
            }
        },
        record_payload => {
            if g.types.node(value.ty).tag != blot_direct_types::Tag.record { return g.fail(m, id, "record pattern on a non-record"); }
            // One pattern for a wider record binds the whole payload as a
            // tuple in declared field order.
            let storage = m.types.node(pattern.ty);
            if m.pattern(pattern.b).tag != blot_check_core::PatternTag.product && storage.tag == blot_check_types::Tag.record && storage.b > 1 {
                let declared, error = declaredTuple(g, f, storage, value, id);
                if error != blot_direct_types::Error.none { return error; }
                return test_(g, f, pattern.b, declared, has_fail, fail, id);
            }
            // A one-field record's child is that field's own pattern.
            if m.pattern(pattern.b).tag == blot_check_core::PatternTag.product { return recordPattern(g, f, pattern.b, false, storage, value, has_fail, fail, id); }
            return recordPattern(g, f, pattern.b, true, storage, value, has_fail, fail, id);
        },
        invalid => { return g.fail(m, id, "invalid pattern"); },
    }
    return blot_direct_types::Error.none;
}
// The fields of record `value` as a tuple in the declared order of the Core
// record type `storage`.
fn declaredTuple(g: Generator&, f: Fn&, storage: blot_check_types::Node, value: Val, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    var items: Ty[>..<] = [];
    var collected: u32[>..<] = [];
    for index in 0..(storage.b as i64) {
        let field = m.types.recordField(storage, index);
        let spelling = m.fieldSpelling(field.name);
        if !spelling.present { return neverVal(), g.fail(m, id, "record pattern field without a spelling"); }
        let position = g.types.findField(value.ty, g.types.fieldName(spelling.value));
        if position < 0 { return neverVal(), g.fail(m, id, "record pattern field missing"); }
        let part, error = recordField(g, f, value, position, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        items.push(part.ty);
        for at in 0..(part.len as i64) { collected.push(g.s.words[part.start + at]); }
    }
    let ty, error = g.types.tuple(items[..]);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let words = g.saveWords(collected[..]);
    return Val { ty, words.start, words.len }, blot_direct_types::Error.none;
}
// Child `i` matches field `i` of the Core record type `storage`. The children
// are those of product pattern `pattern_id`, or that pattern alone (`single`).
recursive fn recordPattern(g: Generator&, f: Fn&, pattern_id: u32, single: bool, storage: blot_check_types::Node, value: Val, has_fail: bool, fail: u32, id: u32) -> Error {
    let m .= g.units[f.unit - 1];
    var count: i64 = 1;
    if !single { count = m.patternChildren(pattern_id).len; }
    if storage.tag != blot_check_types::Tag.record || storage.b < count { return g.fail(m, id, "record pattern without a record type"); }
    for index in 0..count {
        var child = pattern_id;
        if !single { child = m.patternChildren(pattern_id)[index]; }
        let field = m.types.recordField(storage, index);
        let spelling = m.fieldSpelling(field.name);
        if !spelling.present { return g.fail(m, id, "record pattern field without a spelling"); }
        let position = g.types.findField(value.ty, g.types.fieldName(spelling.value));
        if position < 0 { return g.fail(m, id, "record pattern field missing"); }
        let part, error = recordField(g, f, value, position, id);
        if error != blot_direct_types::Error.none { return error; }
        let tested = test_(g, f, child, part, has_fail, fail, id);
        if tested != blot_direct_types::Error.none { return tested; }
    }
    return blot_direct_types::Error.none;
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
fn assign(g: Generator&, f: const Fn&, values: Vals, targets: Vals, id: u32) -> Error {
    let staged = g.reserveVals(values.len);
    for at in 0..(values.len as i64) {
        let value = g.s.vals[values.start + at];
        let target = g.s.vals[targets.start + at];
        g.s.vals[staged.start + at] = value;
        if value.ty == blot_direct_types::never || sameWords(g, value, target) { continue; }
        for other_at in 0..(targets.len as i64) {
            let other = g.s.vals[targets.start + other_at];
            // Zig's `break` leaves only the scan of this target's words.
            for word_at in 0..(other.len as i64) {
                if hasWord(g, value, g.s.words[other.start + word_at]) {
                    let made, error = fresh(g, f, target.ty, id);
                    if error != blot_direct_types::Error.none { return error; }
                    g.s.vals[staged.start + at] = made;
                    let copied = copy(g, f, value, made, id);
                    if copied != blot_direct_types::Error.none { return copied; }
                    break;
                }
            }
        }
    }
    for at in 0..(values.len as i64) {
        let copied = copy(g, f, g.s.vals[staged.start + at], g.s.vals[targets.start + at], id);
        if copied != blot_direct_types::Error.none { return copied; }
    }
    return blot_direct_types::Error.none;
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
        if value.ty == blot_direct_types::never || w(g, value, 0) == w(g, target, 0) { continue; }
        let bytes, error = blockBytes(g, f, value.ty, id);
        if error != blot_direct_types::Error.none { return error; }
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
        let done = open(g, f, OP_block);
        let again = open(g, f, OP_loop);
        lget(g, cursor);
        i32Const(g, bytes);
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
// Only scalar arithmetic and reads of the induction variable from this array
// may share the descriptor validated by the range end. Bound this optional
// inspection independently of the checker's own complexity budget.
recursive fn stableScan(g: const Generator&, m: const Module&, id: u32, owner: u32, index: u32, left: i64&, reads: bool&) -> bool {
    if id == 0 || left <= 0 { return false; }
    left -= 1;
    let n = m.node(id);
    match n.tag {
        suite, block_ => {
            for child in m.children(id) {
                if !stableScan(g, m, child, owner, index, left, reads) { return false; }
            }
            return true;
        },
        bind => {
            return scratchScalarType(m, m.typeOf(n.b)) && stableScan(g, m, n.b, owner, index, left, reads);
        },
        update => {
            let change = m.updateInfo(id);
            return !change.store && change.path.len == 0 && change.selectors.len == 0 &&
                stableScan(g, m, change.root, owner, index, left, reads) &&
                stableScan(g, m, change.value, owner, index, left, reads);
        },
        constant => { return scratchScalarType(m, n.ty); },
        reference => {
            let ref = localRef(m, id);
            if ref == 0 || !scratchScalarType(m, n.ty) { return false; }
            let binding = m.binding(ref);
            return binding.scheme.variables.len == 0 &&
                (binding.kind == blot_reuse_principal_interface::Kind.local || binding.kind == blot_reuse_principal_interface::Kind.parameter);
        },
        scalar, associated, logical => {
            if !scratchScalarType(m, n.ty) || n.op == blot_check_core::Op.none { return false; }
            return stableScan(g, m, n.a, owner, index, left, reads) &&
                (n.b == 0 || stableScan(g, m, n.b, owner, index, left, reads));
        },
        call => {
            let call = m.call(id);
            if !scratchScalarType(m, n.ty) || !scratchScalarCallee(g, m, call) { return false; }
            for arg in call.arguments {
                if !stableScan(g, m, arg, owner, index, left, reads) { return false; }
            }
            return true;
        },
        array_op, storage => {
            if n.tag == blot_check_core::Tag.array_op {
                if m.arrayOperation(id) != blot_backend_collection_ops::Op.get { return false; }
            } else if n.c != blot_check_storage_ops::opCode(blot_check_storage_ops::Op.read) { return false; }
            let args = m.children(id);
            if args.len != 2 || localRef(m, args[0]) != owner || localRef(m, args[1]) != index { return false; }
            reads = true;
            return true;
        },
        _ => { return false; },
    }
}

// A prelude member can be replaced. Recognize its actual one-argument body
// instead of assuming a member spelled "length" has the standard semantics.
fn lengthReceiver(m: const Module&, id: u32) -> u32 {
    let n = m.node(id);
    if n.tag == blot_check_core::Tag.array_op {
        if m.arrayOperation(id) != blot_backend_collection_ops::Op.length { return 0; }
    } else if n.tag != blot_check_core::Tag.storage || n.c != blot_check_storage_ops::opCode(blot_check_storage_ops::Op.length) {
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
        if n.tag == blot_check_types::Tag.usage { cursor = n.a; continue; }
        let inner = blot_check_storage_types::sharedInner(m.types, cursor);
        if inner.present { cursor = inner.value; continue; }
        break;
    }
    let info = blot_check_storage_types::info(m.types, cursor);
    if !info.present || info.value.kind != blot_check_storage_types::sized_array { return 0; }
    let len = blot_check_storage_types::lengthOf(m.types, cursor);
    if !len.present { return 0; }
    return len.value;
}
fn sameSizedLength(m: const Module&, a: TId, b: TId) -> bool {
    if a == 0 || b == 0 { return false; }
    if a == b { return true; }
    let na = m.types.node(a);
    let nb = m.types.node(b);
    if na.tag == blot_check_types::Tag.nominal && nb.tag == blot_check_types::Tag.nominal &&
        blot_check_storage_types::isLengthLiteral(na.a, na.b) &&
        blot_check_storage_types::isLengthLiteral(nb.a, nb.b) {
        return na.b == nb.b;
    }
    return false;
}
fn rangeSizedLength(g: Generator&, f: Fn&, info: blot_check_core::LoopInfo) -> TId {
    let m .= g.units[f.unit - 1];
    if info.first == 0 || info.end == 0 { return 0; }
    let first_node = m.node(info.first);
    if first_node.tag != blot_check_core::Tag.constant || first_node.a != 0 { return 0; }
    let n = m.node(info.end);
    var receiver: u32 = 0;
    if n.tag == blot_check_core::Tag.project {
        receiver = n.a;
        let owner = localRef(m, receiver);
        if owner == 0 { return 0; }
        let handle, found = bindGet(g, f, owner);
        if !found || tagOf(g, handle.ty) != blot_direct_types::Tag.array { return 0; }
        let identity, present = g.receiverIdentity(handle.ty);
        if !present { return 0; }
        let target, exists = g.dispatchTarget(m, identity, m.projection(n.b).field, blot_check_types::Operator.none);
        if !exists || !g.hasUnit(target.unit) { return 0; }
        let unit .= g.units[target.unit - 1];
        let body .= unit.body(target.binding);
        if !body || !body.is_function { return 0; }
        let params = unit.bodyParameters(body);
        if params.len != 1 || lengthReceiver(unit, scratchReturned(unit, body.root)) != params[0].binding { return 0; }
    } else {
        if lengthReceiver(m, info.end) == 0 { return 0; }
        let args = m.children(info.end);
        if args.len != 1 { return 0; }
        receiver = args[0];
    }
    return coreSizedLength(m, m.typeOf(receiver));
}

fn scanOwner(g: Generator&, f: Fn&, id: u32, info: blot_check_core::LoopInfo) -> Val {
    let m .= g.units[f.unit - 1];
    if info.pattern == 0 { return neverVal(); }
    let pattern = m.pattern(info.pattern);
    if pattern.tag != blot_check_core::PatternTag.bind { return neverVal(); }
    let n = m.node(info.end);
    var owner: u32 = 0;
    if n.tag == blot_check_core::Tag.project { owner = localRef(m, n.a); }
    else { owner = lengthReceiver(m, info.end); }
    if owner == 0 { return neverVal(); }
    let handle, found = bindGet(g, f, owner);
    if !found || tagOf(g, handle.ty) != blot_direct_types::Tag.array { return neverVal(); }
    let element = g.types.node(handle.ty).a;
    if !isScalarTag(tagOf(g, element)) { return neverVal(); }
    if n.tag == blot_check_core::Tag.project {
        let identity, present = g.receiverIdentity(handle.ty);
        if !present { return neverVal(); }
        let target, exists = g.dispatchTarget(m, identity, m.projection(n.b).field, blot_check_types::Operator.none);
        if !exists || !g.hasUnit(target.unit) { return neverVal(); }
        let unit .= g.units[target.unit - 1];
        let body .= unit.body(target.binding);
        if !body || !body.is_function { return neverVal(); }
        let params = unit.bodyParameters(body);
        if params.len != 1 || lengthReceiver(unit, scratchReturned(unit, body.root)) != params[0].binding { return neverVal(); }
    }
    for carry in m.loopCarries(id) {
        if !scratchScalarType(m, m.binding(carry.iteration).ty) { return neverVal(); }
    }
    var budget: i64 = 96;
    var reads = false;
    if !stableScan(g, m, info.body, owner, pattern.a, budget, reads) || !reads { return neverVal(); }
    return handle;
}
recursive fn loop_(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let info = m.loopInfo(id);
    let carries = m.loopCarries(id);
    let incoming = g.reserveVals(carries.len);
    for carry, at in carries {
        let value, present, rerr = readBindingVal(g, f, carry.incoming, id);
        if rerr != blot_direct_types::Error.none { return neverVal(), rerr; }
        if !present { return neverVal(), g.fail(m, id, "loop carry without an incoming value"); }
        g.s.vals[incoming.start + at] = value;
    }
    let iteration = g.reserveVals(carries.len);
    let outgoing = g.reserveVals(carries.len);
    // A boxed carry lives in a slot reserved before the loop, so each
    // iteration can release what it allocated.
    let slots = Words { g.s.words.len as u32, carries.len as u32 };
    for carry in carries { g.s.words.push(0); }
    for at in 0..carries.len {
        let value = g.s.vals[incoming.start + at];
        let held, error = copiedBox(g, f, value.ty, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        if held {
            g.s.words[slots.start + at] = 1;
            let reserved, error = newBlock(g, f, value.ty, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            g.s.vals[iteration.start + at] = valOf1(g, value.ty, reserved);
        } else {
            let current, error = fresh(g, f, value.ty, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            g.s.vals[iteration.start + at] = current;
        }
        let after, error = fresh(g, f, value.ty, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        g.s.vals[outgoing.start + at] = after;
    }
    let assigned = assignCarries(g, f, incoming, iteration, slots, 0xffffffff, 0, 0, id);
    if assigned != blot_direct_types::Error.none { return neverVal(), assigned; }
    for carry, at in carries {
        bindPut(g, f, carry.iteration, g.s.vals[iteration.start + at]);
        if isUniqueBoxed(g, f, carry.incoming) && uses(g, f, carry.incoming) == 0 && !bindingCaptured(m, carry.incoming) {
            blot_support_zigmap::put(g.s.map_pool, f.unique_boxed, carry.iteration, 1);
        }
    }
    var has_index = false;
    var index: u32 = 0;
    var end = neverVal();
    var has_source = false;
    var source = neverVal();
    var range = CheckedRange {};
    match info.kind {
        forever => {},
        range => {
            has_index = true;
            index = local32(g, f);
            let first, error = expr(g, f, info.first);
            if error != blot_direct_types::Error.none { return first, error; }
            let copied = copy(g, f, first, valOf1(g, blot_direct_types::u32_, index), id);
            if copied != blot_direct_types::Error.none { return neverVal(), copied; }
            let limit, error = fresh(g, f, blot_direct_types::u32_, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            end = limit;
            let handle = scanOwner(g, f, id, info);
            if handle.ty != blot_direct_types::never {
                // The source already reads length here, even on an empty range.
                // Read the same checked entry's base before entering the loop.
                let entry = local32(g, f);
                range.slot = w(g, handle, 0);
                range.generation = w(g, handle, 1);
                range.base = local32(g, f);
                lget(g, range.slot);
                lget(g, range.generation);
                callf(g, g.runtime_().check);
                ltee(g, entry);
                op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
                lset(g, w(g, end, 0));
                lget(g, entry);
                op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
                lset(g, range.base);
            } else {
                let last, error = expr(g, f, info.end);
                if error != blot_direct_types::Error.none { return last, error; }
                let copied = copy(g, f, last, end, id);
                if copied != blot_direct_types::Error.none { return neverVal(), copied; }
            }
            range.length_ty = rangeSizedLength(g, f, info);
        },
        array => {
            let container, error = expr(g, f, info.first);
            if error != blot_direct_types::Error.none { return container, error; }
            has_source = true;
            source = container;
            has_index = true;
            index = constLocal(g, f, 0);
            let length, error = lengthOf(g, f, source, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            end = valOf1(g, blot_direct_types::u32_, length);
        },
    }
    let exit = open(g, f, OP_block);
    let top = open(g, f, OP_loop);
    if has_index {
        lget(g, index);
        lget(g, w(g, end, 0));
        op(g, OP_i32_ge_u);
        let opened = open(g, f, OP_if_);
        let assigned = assign(g, f, iteration, outgoing, id);
        if assigned != blot_direct_types::Error.none { return neverVal(), assigned; }
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
            let element, error = readElement(g, f, source, current, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            item = element;
        } else { item = valOf1(g, blot_direct_types::u32_, current); }
        if info.pattern != 0 {
            let tested = test_(g, f, info.pattern, item, false, 0, id);
            if tested != blot_direct_types::Error.none { return neverVal(), tested; }
        }
    }
    // An iteration may release what it allocated when no carry can refer to
    // it: carries are plain values or owners of plain elements, each carried
    // owner predates the iteration (checked at run time), and the body stored
    // no memory-holding value into older storage.
    var release = true;
    let s .= g.s;
    let scratch_mark = s.scratch.len;
    // A boxed carry is judged at run time instead: an iteration that leaves
    // its slot's words as they were carries out nothing it allocated there.
    var boxed_carries = false;
    for at in 0..carries.len {
        if g.s.words[slots.start + at] != 0 { boxed_carries = true; continue; }
        let value = g.s.vals[iteration.start + at];
        let safe, error = ownerSlots(g, value.ty, value.start);
        if error != blot_direct_types::Error.none { s.scratch.resize(scratch_mark); return neverVal(), error; }
        if !safe { release = false; }
    }
    var unchanged: u32 = 0xffffffff;
    if release && boxed_carries { unchanged = local32(g, f); }
    let guards = Words { g.s.words.len as u32, (s.scratch.len - scratch_mark) as u32 };
    for at in scratch_mark..s.scratch.len { let slot = s.scratch[at]; g.s.words.push(slot); }
    s.scratch.resize(scratch_mark);
    let owner_mark = local32(g, f);
    let stack_mark = local32(g, f);
    let allow = local32(g, f);
    let mark_at = s.code.len;
    let allocations = f.allocations;
    let stores = f.memory_stores;
    let unused = g.newSlot();
    let labels_mark = s.labels.len;
    s.labels.push(blot_direct_emit::Label { target: id, depth: exit, result: unused, kind: blot_direct_emit::LabelKind.loop_, top: top, iteration: iteration, outgoing: outgoing, unchanged: unchanged, has_release: release, release_owner: owner_mark, release_stack: stack_mark, slots: slots, allow: allow, guards: guards });
    let previous_range = f.checked_range;
    f.checked_range = range;
    let body, error = stmt(g, f, info.body);
    f.checked_range = previous_range;
    let label = s.labels[labels_mark];
    s.labels.resize(labels_mark);
    if error != blot_direct_types::Error.none { return body, error; }
    if body.ty != blot_direct_types::never {
        let backedge = g.reserveVals(carries.len);
        for carry, at in carries {
            let value, present, rerr = readBindingVal(g, f, carry.backedge, id);
            if rerr != blot_direct_types::Error.none { return neverVal(), rerr; }
            if !present { return neverVal(), g.fail(m, id, "loop carry without a backedge value"); }
            g.s.vals[backedge.start + at] = value;
        }
        let assigned = assignCarries(g, f, backedge, iteration, slots, unchanged, owner_mark, stack_mark, id);
        if assigned != blot_direct_types::Error.none { return neverVal(), assigned; }
        if label.has_release && f.allocations != allocations { releaseIteration(g, f, label); }
        br(g, f, OP_br, top);
    }
    if release && (f.allocations != allocations || label.used) {
        // Insert the iteration's marks at its start, now that the body is
        // known to allocate.
        var prefix: u8[>..<] = [];
        markInto(g, prefix, owner_mark, stack_mark);
        prefix.push(OP_i32_const);
        blot_direct_writer::sleb(prefix, boolWord(f.memory_stores == stores));
        prefix.push(OP_local_set);
        blot_direct_writer::uleb(prefix, allow);
        blot_direct_relocations::insert(f.sites_base,mark_at,prefix.len);
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
    for carry, at in carries { bindPut(g, f, carry.outgoing, g.s.vals[outgoing.start + at]); }
    if info.kind == blot_check_core::LoopKind.forever && !info.can_exit { return neverVal(), blot_direct_types::Error.none; }
    return unitVal(), blot_direct_types::Error.none;
}
// Records a store into an existing owner, which may predate this scope.
fn noteStore(g: Generator&, f: Fn&, value: Val) -> Error {
    if value.ty == blot_direct_types::never { return blot_direct_types::Error.none; }
    let holds, error = g.contentsHoldMemory(value.ty);
    if error != blot_direct_types::Error.none { return error; }
    if holds { f.memory_stores += 1; }
    return blot_direct_types::Error.none;
}
// Releases an iteration's allocations when its loop allows it and every
// carried owner predates the iteration.
fn releaseIteration(g: Generator&, f: Fn&, label: blot_direct_emit::Label) {
    lget(g, label.allow);
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
    if error != blot_direct_types::Error.none { return false, error; }
    if !holds { return true, blot_direct_types::Error.none; }
    // A boxed carry is copied into its reserved slot; owners inside it are
    // not checked word by word.
    let boxed, error = g.types.boxed(ty);
    if error != blot_direct_types::Error.none { return false, error; }
    if boxed { return false, blot_direct_types::Error.none; }
    let n = g.types.node(ty);
    match n.tag {
        array, list, grow, resize, view, ref, link, cursor => {
            let element_holds, error = g.contentsHoldMemory(n.a);
            if error != blot_direct_types::Error.none { return false, error; }
            if element_holds { return false, blot_direct_types::Error.none; }
            let slot = g.s.words[words];
            g.s.scratch.push(slot);
            return true, blot_direct_types::Error.none;
        },
        tuple => {
            var at: u32 = 0;
            for index in 0..(n.b as i64) {
                let item = g.types.tupleItems(ty)[index];
                let layout, error = g.types.layout(item);
                if error != blot_direct_types::Error.none { return false, error; }
                let width = layout.len as u32;
                let safe, error = ownerSlots(g, item, words + at);
                if error != blot_direct_types::Error.none { return false, error; }
                if !safe { return false, blot_direct_types::Error.none; }
                at += width;
            }
            return true, blot_direct_types::Error.none;
        },
        record => {
            var at: u32 = 0;
            for index in 0..(n.b as i64) {
                let field = g.types.recordField(ty, index).ty;
                let layout, error = g.types.layout(field);
                if error != blot_direct_types::Error.none { return false, error; }
                let width = layout.len as u32;
                let safe, error = ownerSlots(g, field, words + at);
                if error != blot_direct_types::Error.none { return false, error; }
                if !safe { return false, blot_direct_types::Error.none; }
                at += width;
            }
            return true, blot_direct_types::Error.none;
        },
        _ => { return false, blot_direct_types::Error.none; },
    }
}
recursive fn breakNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    var at = g.s.labels.len;
    while at != f.labels_base {
        at -= 1;
        let label = g.s.labels[at];
        if label.target != n.a || label.kind != blot_direct_emit::LabelKind.loop_ { continue; }
        let left = leaveHandles(g, f, label.depth);
        if left != blot_direct_types::Error.none { return neverVal(), left; }
        let count = g.units[f.unit - 1].breakValues(id).len;
        if count != (label.iteration.len as i64) { return neverVal(), g.fail(g.units[f.unit - 1], id, "break carries the wrong number of values"); }
        let values = g.reserveVals(count);
        for vi in 0..count {
            let child = g.units[f.unit - 1].breakValues(id)[vi];
            let value, error = expr(g, f, child);
            if error != blot_direct_types::Error.none { return value, error; }
            g.s.vals[values.start + vi] = value;
        }
        if n.op == blot_check_core::Op.continue_ {
            let assigned = assignCarries(g, f, values, label.iteration, label.slots, label.unchanged, label.release_owner, label.release_stack, id);
            if assigned != blot_direct_types::Error.none { return neverVal(), assigned; }
            if label.has_release {
                releaseIteration(g, f, label);
                g.s.labels[at].used = true;
            }
            br(g, f, OP_br, label.top);
        } else {
            let assigned = assign(g, f, values, label.outgoing, id);
            if assigned != blot_direct_types::Error.none { return neverVal(), assigned; }
            br(g, f, OP_br, label.depth);
        }
        return neverVal(), blot_direct_types::Error.none;
    }
    return neverVal(), g.fail(m, id, "break outside its loop");
}

recursive fn patternBind(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let n = g.units[f.unit - 1].node(id);
    let value, error = expr(g, f, n.b);
    if error != blot_direct_types::Error.none { return value, error; }
    if n.c == 0 {
        let tested = test_(g, f, n.a, value, false, 0, id);
        if tested != blot_direct_types::Error.none { return neverVal(), tested; }
        return unitVal(), blot_direct_types::Error.none;
    }
    let ok = open(g, f, OP_block);
    let failed = open(g, f, OP_block);
    let tested = test_(g, f, n.a, value, true, failed, id);
    if tested != blot_direct_types::Error.none { return neverVal(), tested; }
    br(g, f, OP_br, ok);
    close(g, f);
    let otherwise, error = stmt(g, f, n.c);
    if error != blot_direct_types::Error.none { return otherwise, error; }
    op(g, OP_unreachable_);
    close(g, f);
    return unitVal(), blot_direct_types::Error.none;
}
