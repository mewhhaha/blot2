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
    popCheckedArraysAt(f, opened);
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
        if !scratchFieldUpdate(m, update, next.b) { return 0; }
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
        comptime_if, if_value, if_stmt, state_provider => {
            collectComptimeProjectVars(m, n.a, binder, vars, count, depth + 1);
            collectComptimeProjectVars(m, n.b, binder, vars, count, depth + 1);
            collectComptimeProjectVars(m, n.c, binder, vars, count, depth + 1);
        },
        suite, block_, product, record, array, array_op, storage => {
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
        return_, project, result_associated, fork_ => {
            collectComptimeProjectVars(m, n.a, binder, vars, count, depth + 1);
        },
        scalar, logical, apply, associated, type_same, effect_provider, handle, staging => {
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
        let arr_ty, terr = typeOf(g, f, id);
        if terr != blot_direct_types::Error.none { return neverVal(), terr; }
        let text = g.types.spelling(f.comptime_frames[fidx].name_id);
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
        // Merge saved escape marks for every enclosing releasing loop left by this return.
        var lk = g.s.labels.len;
        while lk > at + 1 {
            lk -= 1;
            if g.s.labels[lk].kind == blot_direct_emit::LabelKind.loop_ && g.s.labels[lk].has_release {
                g.s.labels[lk].used = true;
                emitMergeEscapeMinCurrent(g, f, g.s.labels[lk].saved_esc);
            }
        }
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
    let merges = m.branchMerges(id);
    if inputs.len == 1 && merges.len == 0 {
        let input_val = g.s.vals[values.start];
        if input_val.len == 1 && tagOf(g, input_val.ty) == blot_direct_types::Tag.nominal {
            let known_tag, has_known = findConstTag(f, w(g, input_val, 0));
            if has_known {
                let boxed, berr = isBoxed(g, f, input_val.ty, id);
                let cases, cerr = g.types.variants(input_val.ty);
                if berr == blot_direct_types::Error.none && !boxed && cerr == blot_direct_types::Error.none && cases.len > 1 {
                    let arms = m.matchArms(id);
                    var matched_arm: i64 = -1;
                    var matched_bind: u32 = 0;
                    var can_fold = true;
                    for arm, arm_index in arms {
                        if arm.guard_ != 0 { can_fold = false; break; }
                        let rows = m.armRows(arm);
                        var row_hit = false;
                        for row in rows {
                            let patterns = m.rowPatterns(row);
                            if patterns.len != 1 { can_fold = false; break; }
                            let pat = m.pattern(patterns[0]);
                            match pat.tag {
                                wildcard => { row_hit = true; break; },
                                bind => { row_hit = true; matched_bind = pat.a; break; },
                                constructor => {
                                    if pat.b != 0 { can_fold = false; break; }
                                    if m.constructor(pat.a).tag == known_tag { row_hit = true; break; }
                                },
                                _ => { can_fold = false; break; },
                            }
                        }
                        if !can_fold { break; }
                        if row_hit { matched_arm = arm_index; break; }
                    }
                    if can_fold && matched_arm >= 0 {
                        if matched_bind != 0 {
                            refine(g, f, m.binding(matched_bind).ty, input_val.ty);
                            bindPut(g, f, matched_bind, input_val);
                        }
                        let arm_body = arms[matched_arm].body;
                        let body_val, berr2 = stmt(g, f, arm_body);
                        if berr2 != blot_direct_types::Error.none { return body_val, berr2; }
                        if body_val.ty == blot_direct_types::never { return neverVal(), blot_direct_types::Error.none; }
                        if info.statement { return unitVal(), blot_direct_types::Error.none; }
                        return body_val, blot_direct_types::Error.none;
                    }
                }
            }
        }
    }
    let result = g.newSlot();
    let merged = newSlots(g, merges.len);
    var falls = false;
    let done = open(g, f, OP_block);
    let arms = m.matchArms(id);
    var fbip_block: u32 = 0;
    var fbip_ty: Ty = 0;
    if !info.statement && inputs.len == 1 && !g.runtime_().has_fork {
        let matched_binding = localRef(m, inputs[0]);
        if matched_binding != 0 && isUniqueBoxed(g, f, matched_binding) && uses(g, f, matched_binding) == 1 && !bindingCaptured(g, f, matched_binding) {
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
                            invalidateCheckedArrayVal(g, f, target);
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
            // A one-field record's child is always that field's own pattern
            // (even when that pattern is a tuple product pattern).
            if storage.tag == blot_check_types::Tag.record && storage.b == 1 {
                return recordPattern(g, f, pattern.b, true, storage, value, has_fail, fail, id);
            }
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
fn assign(g: Generator&, f: Fn&, values: Vals, targets: Vals, id: u32) -> Error {
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
        let staged_val = g.s.vals[staged.start + at];
        let target = g.s.vals[targets.start + at];
        if sameWords(g, staged_val, target) { continue; }
        let copied = copy(g, f, staged_val, target, id);
        if copied != blot_direct_types::Error.none { return copied; }
        invalidateCheckedArrayVal(g, f, target);
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
// Speculatively validates a View handle and computes its shifted base address
// without trapping; returns 0 in `vbase` when the view is stale, out-of-bounds,
// or (if `require_immutable`) backed by mutable growable storage.
fn tryHoistViewBase(g: Generator&, f: Fn&, vslot: u32, vgen: u32, vstart: u32, vlen: u32, step: u32, require_immutable: bool) -> u32 {
    let rt = g.runtime_();
    let vbase = constLocal(g, f, 0);
    lget(g, vslot);
    i32Const(g, 0);
    op(g, OP_i32_ne);
    lget(g, vslot);
    i32Const(g, rt.layout.owner_capacity);
    op(g, OP_i32_lt_u);
    op(g, OP_i32_and);
    let slot_ok = open(g, f, OP_if_);
    let block_ptr = local32(g, f);
    lget(g, vslot);
    i32Const(g, 8);
    op(g, OP_i32_shr_u);
    i32Const(g, 2);
    op(g, OP_i32_shl);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, rt.layout.owner_table);
    ltee(g, block_ptr);
    let block_ok = open(g, f, OP_if_);
    let entry = local32(g, f);
    lget(g, block_ptr);
    lget(g, vslot);
    i32Const(g, 255);
    op(g, OP_i32_and);
    i32Const(g, 4);
    op(g, OP_i32_shl);
    op(g, OP_i32_add);
    ltee(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_generation);
    lget(g, vgen);
    op(g, OP_i32_eq);
    let gen_ok = open(g, f, OP_if_);
    let end_pos = local32(g, f);
    lget(g, vstart);
    lget(g, vlen);
    op(g, OP_i32_add);
    ltee(g, end_pos);
    lget(g, vstart);
    op(g, OP_i32_ge_u);
    lget(g, end_pos);
    lget(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
    op(g, OP_i32_le_u);
    op(g, OP_i32_and);
    if require_immutable {
        lget(g, entry);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_capacity);
        i32Const(g, blot_direct_runtime::static_pool_flag);
        op(g, OP_i32_and);
        i32Const(g, 0);
        op(g, OP_i32_ne);
        op(g, OP_i32_and);
    }
    let bounds_ok = open(g, f, OP_if_);
    let elem_base = local32(g, f);
    lget(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
    lset(g, elem_base);
    let shifted = emitOffsetAddress(g, f, elem_base, vstart, step);
    lget(g, shifted);
    lset(g, vbase);
    close(g, f);
    close(g, f);
    close(g, f);
    close(g, f);
    return vbase;
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
        g.recordInlined(target.unit, target.binding);
    } else {
        if lengthReceiver(m, info.end) == 0 { return 0; }
        let args = m.children(info.end);
        if args.len != 1 { return 0; }
        receiver = args[0];
    }
    return coreSizedLength(m, m.typeOf(receiver));
}

// Conservative check that a loop body cannot grow, shrink, or move a live
// View's backing owner (allows reads, writes, branches, exits, and proved
// scalar calls; rejects storage growth/shrink and opaque calls).
recursive fn noStorageResize(g: const Generator&, m: const Module&, id: u32, left: i64&) -> bool {
    if id == 0 { return true; }
    if left <= 0 { return false; }
    left -= 1;
    let n = m.node(id);
    match n.tag {
        suite, block_, product, record, array => {
            for child in m.children(id) {
                if !noStorageResize(g, m, child, left) { return false; }
            }
            return true;
        },
        construct => { return noStorageResize(g, m, n.b, left); },
        bind => { return noStorageResize(g, m, n.b, left); },
        return_ => { return noStorageResize(g, m, n.a, left); },
        break_ => {
            for child in m.children(id) {
                if !noStorageResize(g, m, child, left) { return false; }
            }
            return true;
        },
        if_value, if_stmt => {
            return noStorageResize(g, m, n.a, left) &&
                noStorageResize(g, m, n.b, left) &&
                noStorageResize(g, m, n.c, left);
        },
        update => {
            let change = m.updateInfo(id);
            if !noStorageResize(g, m, change.root, left) || !noStorageResize(g, m, change.value, left) { return false; }
            for sel in m.updateSelectors(id) {
                if sel.kind == blot_check_core::UpdateKind.index && !noStorageResize(g, m, sel.index, left) { return false; }
            }
            return true;
        },
        constant, reference, panic => { return true; },
        project => {
            let proj = m.projection(n.b);
            let variants = m.projectionVariants(n.b);
            if variants.len != 0 { return noStorageResize(g, m, n.a, left); }
            let receiver_ty = m.types.node(m.typeOf(n.a)).tag;
            if receiver_ty == blot_check_types::Tag.record || receiver_ty == blot_check_types::Tag.product {
                return noStorageResize(g, m, n.a, left);
            }
            // Allow standard `.length` / `.view` projection checks conservatively by
            // inspecting `n.a` only when it's a known pure length call.
            let receiver_local = localRef(m, n.a);
            if receiver_local != 0 {
                let spelling = m.fieldSpelling(proj.field);
                if spelling.present && spelling.value == "length" { return true; }
            }
            return false;
        },
        scalar, associated, logical => {
            if n.tag == blot_check_core::Tag.associated && n.op == blot_check_core::Op.none { return false; }
            return noStorageResize(g, m, n.a, left) && noStorageResize(g, m, n.b, left);
        },
        call => {
            let call = m.call(id);
            if !scratchScalarCallee(g, m, call) { return false; }
            for arg in call.arguments {
                if !noStorageResize(g, m, arg, left) { return false; }
            }
            return true;
        },
        array_op => {
            match m.arrayOperation(id) {
                length, get => {
                    for child in m.children(id) {
                        if !noStorageResize(g, m, child, left) { return false; }
                    }
                    return true;
                },
                _ => { return false; },
            }
        },
        storage => {
            let op_kind, ok = blot_check_storage_ops::opFromCode(n.c);
            if ok != blot_error::Error.none { return false; }
            match op_kind {
                length, read, view => {
                    for child in m.children(id) {
                        if !noStorageResize(g, m, child, left) { return false; }
                    }
                    return true;
                },
                _ => { return false; },
            }
        },
        _ => { return false; },
    }
}
fn rangeOwner(g: Generator&, f: Fn&, id: u32, info: blot_check_core::LoopInfo) -> Val, bool {
    let m .= g.units[f.unit - 1];
    if info.pattern == 0 { return neverVal(), false; }
    let pattern = m.pattern(info.pattern);
    if pattern.tag != blot_check_core::PatternTag.bind { return neverVal(), false; }
    let n = m.node(info.end);
    var owner: u32 = 0;
    if n.tag == blot_check_core::Tag.project { owner = localRef(m, n.a); }
    else { owner = lengthReceiver(m, info.end); }
    if owner == 0 { return neverVal(), false; }
    let handle, found = bindGet(g, f, owner);
    if !found { return neverVal(), false; }
    let tag = tagOf(g, handle.ty);
    if tag != blot_direct_types::Tag.array && tag != blot_direct_types::Tag.view { return neverVal(), false; }
    if n.tag == blot_check_core::Tag.project {
        let identity, present = g.receiverIdentity(handle.ty);
        if !present { return neverVal(), false; }
        let target, exists = g.dispatchTarget(m, identity, m.projection(n.b).field, blot_check_types::Operator.none);
        if !exists || !g.hasUnit(target.unit) { return neverVal(), false; }
        let unit .= g.units[target.unit - 1];
        let body .= unit.body(target.binding);
        if !body || !body.is_function { return neverVal(), false; }
        let params = unit.bodyParameters(body);
        if params.len != 1 || lengthReceiver(unit, scratchReturned(unit, body.root)) != params[0].binding { return neverVal(), false; }
        g.recordInlined(target.unit, target.binding);
    }
    if tag == blot_direct_types::Tag.view {
        var budget: i64 = 256;
        if !noStorageResize(g, m, info.body, budget) { return neverVal(), false; }
        return handle, true;
    }
    var receiver_node: u32 = info.end;
    if n.tag == blot_check_core::Tag.project { receiver_node = n.a; }
    else { receiver_node = m.children(info.end)[0]; }
    if coreSizedLength(m, m.typeOf(receiver_node)) == 0 {
        var budget: i64 = 256;
        if !noStorageResize(g, m, info.body, budget) { return neverVal(), false; }
    }
    return handle, false;
}
fn inBindingSet(set: const u32[64]&, len: i64, b: u32) -> bool {
    for i in 0..len { if set[i] == b { return true; } }
    return false;
}
fn addBindingSet(set: u32[64]&, len: i64&, b: u32) {
    if b == 0 || inBindingSet(set, len, b) || len >= 64 { return; }
    set[len] = b;
    len += 1;
}
recursive fn exprPreservesHandle(m: const Module&, id: u32, same: const u32[64]&, same_len: i64, depth: i64) -> bool {
    if id == 0 || depth >= 32 { return false; }
    let n = m.node(id);
    match n.tag {
        reference => {
            let b = localRef(m, id);
            return b != 0 && inBindingSet(same, same_len, b);
        },
        update => {
            let info = m.updateInfo(id);
            let sels = m.updateSelectors(id);
            return sels.len > 0 && sels[0].kind == blot_check_core::UpdateKind.index &&
                exprPreservesHandle(m, info.root, same, same_len, depth + 1);
        },
        array_op => {
            if m.arrayOperation(id) != blot_backend_collection_ops::Op.simd_store { return false; }
            let ch = m.children(id);
            return ch.len > 0 && exprPreservesHandle(m, ch[0], same, same_len, depth + 1);
        },
        block_, suite => {
            let ch = m.children(id);
            if ch.len == 1 { return exprPreservesHandle(m, ch[0], same, same_len, depth + 1); }
            return false;
        },
        _ => { return false; },
    }
}
recursive fn carryStaysInPlace(m: const Module&, loop_id: u32, carry_at: i64, iter_binding: u32, backedge_binding: u32, budget: i64&) -> bool {
    var same: u32[64] = [0; 64];
    var same_len: i64 = 0;
    addBindingSet(same, same_len, iter_binding);
    if !scanCarryInPlace(m, loop_id, carry_at, m.loopInfo(loop_id).body, same, same_len, budget) { return false; }
    return backedge_binding == 0 || inBindingSet(same, same_len, backedge_binding);
}
recursive fn scanCarryInPlace(m: const Module&, loop_id: u32, carry_at: i64, id: u32, same: u32[64]&, same_len: i64&, budget: i64&) -> bool {
    if id == 0 { return true; }
    if budget <= 0 { return false; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        suite, block_ => {
            for child in m.children(id) {
                if !scanCarryInPlace(m, loop_id, carry_at, child, same, same_len, budget) { return false; }
            }
            return true;
        },
        bind => {
            if !scanCarryInPlace(m, loop_id, carry_at, n.b, same, same_len, budget) { return false; }
            if exprPreservesHandle(m, n.b, same, same_len, 0) { addBindingSet(same, same_len, n.a); }
            return true;
        },
        if_stmt, if_value => {
            if !scanCarryInPlace(m, loop_id, carry_at, n.a, same, same_len, budget) ||
                !scanCarryInPlace(m, loop_id, carry_at, n.b, same, same_len, budget) ||
                !scanCarryInPlace(m, loop_id, carry_at, n.c, same, same_len, budget) { return false; }
            for merge in m.branchMerges(id) {
                if inBindingSet(same, same_len, merge.then_binding) && inBindingSet(same, same_len, merge.else_binding) {
                    addBindingSet(same, same_len, merge.result);
                }
            }
            return true;
        },
        match_ => {
            for inp in m.matchInputs(id) {
                if !scanCarryInPlace(m, loop_id, carry_at, inp, same, same_len, budget) { return false; }
            }
            for arm in m.matchArms(id) {
                if !scanCarryInPlace(m, loop_id, carry_at, arm.guard_, same, same_len, budget) ||
                    !scanCarryInPlace(m, loop_id, carry_at, arm.body, same, same_len, budget) { return false; }
            }
            for merge in m.branchMerges(id) {
                if inBindingSet(same, same_len, merge.then_binding) && inBindingSet(same, same_len, merge.else_binding) {
                    addBindingSet(same, same_len, merge.result);
                }
            }
            return true;
        },
        loop_ => {
            let ninfo = m.loopInfo(id);
            if !scanCarryInPlace(m, loop_id, carry_at, ninfo.first, same, same_len, budget) ||
                !scanCarryInPlace(m, loop_id, carry_at, ninfo.end, same, same_len, budget) { return false; }
            let ncarries = m.loopCarries(id);
            for nc, nc_at in ncarries {
                if inBindingSet(same, same_len, nc.incoming) {
                    if carryStaysInPlace(m, id, nc_at, nc.iteration, nc.backedge, budget) {
                        addBindingSet(same, same_len, nc.iteration);
                        addBindingSet(same, same_len, nc.outgoing);
                    }
                }
            }
            return scanCarryInPlace(m, loop_id, carry_at, ninfo.body, same, same_len, budget);
        },
        break_ => {
            let vals = m.breakValues(id);
            for child in vals {
                if !scanCarryInPlace(m, loop_id, carry_at, child, same, same_len, budget) { return false; }
            }
            if n.a == loop_id {
                if carry_at >= vals.len || !exprPreservesHandle(m, vals[carry_at], same, same_len, 0) { return false; }
            }
            return true;
        },
        pattern_bind => {
            return scanCarryInPlace(m, loop_id, carry_at, n.b, same, same_len, budget) &&
                scanCarryInPlace(m, loop_id, carry_at, n.c, same, same_len, budget);
        },
        update => {
            let info = m.updateInfo(id);
            if !scanCarryInPlace(m, loop_id, carry_at, info.root, same, same_len, budget) ||
                !scanCarryInPlace(m, loop_id, carry_at, info.value, same, same_len, budget) { return false; }
            for sel in m.updateSelectors(id) {
                if sel.kind == blot_check_core::UpdateKind.index && !scanCarryInPlace(m, loop_id, carry_at, sel.index, same, same_len, budget) { return false; }
            }
            return true;
        },
        call => {
            for arg in m.call(id).arguments {
                if !scanCarryInPlace(m, loop_id, carry_at, arg, same, same_len, budget) { return false; }
            }
            return true;
        },
        product, record, array, array_op, storage => {
            for child in m.children(id) {
                if !scanCarryInPlace(m, loop_id, carry_at, child, same, same_len, budget) { return false; }
            }
            return true;
        },
        construct => { return scanCarryInPlace(m, loop_id, carry_at, n.b, same, same_len, budget); },
        return_, project, result_associated, fork_ => { return scanCarryInPlace(m, loop_id, carry_at, n.a, same, same_len, budget); },
        scalar, associated, logical, apply => {
            return scanCarryInPlace(m, loop_id, carry_at, n.a, same, same_len, budget) &&
                scanCarryInPlace(m, loop_id, carry_at, n.b, same, same_len, budget);
        },
        constant, reference, panic, closure => { return true; },
        _ => { return false; },
    }
}
fn unwrapSingleBody(m: const Module&, id: u32) -> u32 {
    var cur = id;
    for step in 0..8 {
        if cur == 0 { return 0; }
        let n = m.node(cur);
        if (n.tag == blot_check_core::Tag.suite || n.tag == blot_check_core::Tag.block_) && n.b == 1 {
            cur = m.children(cur)[0];
        } else { break; }
    }
    return cur;
}

fn isTwoParamPushForwarder(tm: const Module&, body: const blot_check_core::Body&) -> bool {
    if !body.is_function { return false; }
    let params = tm.bodyParameters(body);
    if params.len != 2 { return false; }
    let inner = scratchReturned(tm, unwrapSingleBody(tm, body.root));
    if inner == 0 { return false; }
    let n = tm.node(inner);
    if n.tag != blot_check_core::Tag.storage { return false; }
    let op_kind, ok = blot_check_storage_ops::opFromCode(n.c);
    if ok != blot_error::Error.none || op_kind != blot_check_storage_ops::Op.push { return false; }
    let ch = tm.children(inner);
    return ch.len == 2 && localRef(tm, ch[0]) == params[0].binding && localRef(tm, ch[1]) == params[1].binding;
}

// Recognize `for item in src: dest.push item` (or `@storage.push dest item`)
// with no loop carries and plain non-boxed elements, emitting a single ensure
// + `memory.copy`.
recursive fn tryBulkPushLoop(g: Generator&, f: Fn&, id: u32, info: blot_check_core::LoopInfo) -> bool, Error {
    if g.runtime_().has_fork { return false, blot_direct_types::Error.none; }
    if info.kind != blot_check_core::LoopKind.array || info.carries.len != 0 || info.pattern == 0 {
        return false, blot_direct_types::Error.none;
    }
    var dest = neverVal();
    var method_target = BindingRef { 0, 0 };
    var step: u32 = 0;
    var stag = blot_direct_types::Tag.unit;
    {
        let m .= g.units[f.unit - 1];
        let pat = m.pattern(info.pattern);
        if pat.tag != blot_check_core::PatternTag.bind { return false, blot_direct_types::Error.none; }
        let item_binding = pat.a;
        let body_node = unwrapSingleBody(m, info.body);
        if body_node == 0 { return false, blot_direct_types::Error.none; }
        let bn = m.node(body_node);
        var dest_binding: u32 = 0;
        if bn.tag == blot_check_core::Tag.storage {
            let op_kind, ok = blot_check_storage_ops::opFromCode(bn.c);
            if ok != blot_error::Error.none || op_kind != blot_check_storage_ops::Op.push {
                return false, blot_direct_types::Error.none;
            }
            let ch = m.children(body_node);
            if ch.len != 2 || localRef(m, ch[1]) != item_binding { return false, blot_direct_types::Error.none; }
            dest_binding = localRef(m, ch[0]);
        } else if bn.tag == blot_check_core::Tag.apply {
            if localRef(m, bn.b) != item_binding || m.node(bn.a).tag != blot_check_core::Tag.project {
                return false, blot_direct_types::Error.none;
            }
            let proj = m.node(bn.a);
            dest_binding = localRef(m, proj.a);
            if dest_binding == 0 { return false, blot_direct_types::Error.none; }
            let dest_check, has_dest = bindGet(g, f, dest_binding);
            if !has_dest || tagOf(g, dest_check.ty) != blot_direct_types::Tag.array {
                return false, blot_direct_types::Error.none;
            }
            let identity, has_id = g.receiverIdentity(dest_check.ty);
            if !has_id { return false, blot_direct_types::Error.none; }
            let target, has_target = g.dispatchTarget(m, identity, m.projection(proj.b).field, blot_check_types::Operator.none);
            if !has_target || !g.hasUnit(target.unit) { return false, blot_direct_types::Error.none; }
            let tm .= g.units[target.unit - 1];
            let tbody .= tm.body(target.binding);
            if !tbody || !isTwoParamPushForwarder(tm, tbody) { return false, blot_direct_types::Error.none; }
            method_target = target;
        } else if bn.tag == blot_check_core::Tag.call {
            let cinfo = m.call(body_node);
            if cinfo.arguments.len != 2 || localRef(m, cinfo.arguments[1]) != item_binding {
                return false, blot_direct_types::Error.none;
            }
            let target = g.resolve(m, cinfo.target);
            if !g.hasUnit(target.unit) { return false, blot_direct_types::Error.none; }
            let tm .= g.units[target.unit - 1];
            let tbody .= tm.body(target.binding);
            if !tbody || !isTwoParamPushForwarder(tm, tbody) { return false, blot_direct_types::Error.none; }
            dest_binding = localRef(m, cinfo.arguments[0]);
            method_target = target;
        } else {
            return false, blot_direct_types::Error.none;
        }
        if dest_binding == 0 || dest_binding == item_binding || dest_binding == localRef(m, info.first) { return false, blot_direct_types::Error.none; }
        let found_dest, has_dest = bindGet(g, f, dest_binding);
        if !has_dest { return false, blot_direct_types::Error.none; }
        dest = found_dest;
        let dtag = tagOf(g, dest.ty);
        if dtag != blot_direct_types::Tag.array {
            return false, blot_direct_types::Error.none;
        }
        let elem, elem_err = elementOf(g, f, dest.ty, id);
        if elem_err != blot_direct_types::Error.none { return false, blot_direct_types::Error.none; }
        let holds, herr = g.contentsHoldMemory(elem);
        if herr != blot_direct_types::Error.none || holds { return false, blot_direct_types::Error.none; }
        let boxed, berr = isBoxed(g, f, elem, id);
        if berr != blot_direct_types::Error.none || boxed { return false, blot_direct_types::Error.none; }
        let got_step, serr = stride(g, f, elem, id);
        if serr != blot_direct_types::Error.none || got_step == 0 || got_step > 65536 { return false, blot_direct_types::Error.none; }
        step = got_step;

        // Verify source Core type lowers to a contiguous container of the exact same element type.
        let src_ty, sty_err = g.types.lower(m, m.typeOf(info.first), f.env);
        if sty_err != blot_direct_types::Error.none { return false, blot_direct_types::Error.none; }
        stag = tagOf(g, src_ty);
        if stag != blot_direct_types::Tag.array && stag != blot_direct_types::Tag.view {
            return false, blot_direct_types::Error.none;
        }
        if g.types.node(src_ty).a != elem { return false, blot_direct_types::Error.none; }
    }

    if method_target.unit != 0 { g.recordInlined(method_target.unit, method_target.binding); }
    let source, eval_err = expr(g, f, info.first);
    if eval_err != blot_direct_types::Error.none { return false, eval_err; }
    let count, lerr = lengthOf(g, f, source, id);
    if lerr != blot_direct_types::Error.none { return false, lerr; }

    let rt = g.runtime_();
    lget(g, count);
    let non_empty = open(g, f, OP_if_);
    let entry = ensureCheckedGrow(g, f, dest);
    let cap = local32(g, f);
    lget(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_capacity);
    ltee(g, cap);
    i32Const(g, blot_direct_runtime::static_pool_flag);
    op(g, OP_i32_and);
    trap(g, f);
    let old_len = local32(g, f);
    let new_len = local32(g, f);
    lget(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
    ltee(g, old_len);
    lget(g, count);
    op(g, OP_i32_add);
    ltee(g, new_len);
    lget(g, old_len);
    op(g, OP_i32_lt_u);
    let max_count = (rt.layout.heap_end - rt.layout.heap_base) / step;
    lget(g, new_len);
    i32Const(g, max_count);
    op(g, OP_i32_gt_u);
    op(g, OP_i32_or);
    trap(g, f);
    let need = emitScaledBytes(g, f, new_len, step);
    let cap_bytes = local32(g, f);
    lget(g, cap);
    i32Const(g, blot_direct_runtime::capacity_mask);
    op(g, OP_i32_and);
    lset(g, cap_bytes);
    lget(g, need);
    lget(g, cap_bytes);
    op(g, OP_i32_gt_u);
    let grow_if = open(g, f, OP_if_);
    let doubled = local32(g, f);
    lget(g, cap_bytes);
    i32Const(g, 1);
    op(g, OP_i32_shl);
    lset(g, doubled);
    lget(g, need);
    lget(g, doubled);
    lget(g, need);
    lget(g, doubled);
    op(g, OP_i32_gt_u);
    op(g, OP_select);
    callf(g, rt.heap_alloc);
    let fresh_size = local32(g, f);
    let fresh_base = local32(g, f);
    lset(g, fresh_size);
    lset(g, fresh_base);
    let old_base = local32(g, f);
    lget(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
    lset(g, old_base);
    let old_bytes = emitScaledBytes(g, f, old_len, step);
    lget(g, fresh_base);
    lget(g, old_base);
    lget(g, old_bytes);
    memoryCopyOp(g);
    lget(g, cap);
    i32Const(g, blot_direct_runtime::heap_flag);
    op(g, OP_i32_and);
    i32Const(g, 0);
    op(g, OP_i32_ne);
    lget(g, cap_bytes);
    i32Const(g, 0);
    op(g, OP_i32_ne);
    op(g, OP_i32_and);
    let free_if = open(g, f, OP_if_);
    lget(g, old_base);
    lget(g, cap_bytes);
    callf(g, rt.heap_free);
    close(g, f);
    lget(g, entry);
    lget(g, fresh_base);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
    lget(g, entry);
    lget(g, fresh_size);
    i32Const(g, blot_direct_runtime::heap_flag | blot_direct_runtime::live_flag);
    op(g, OP_i32_or);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, blot_direct_runtime::entry_capacity);
    close(g, f);

    // Resolve source base address after any growth of `dest`.
    invalidateCheckedContainers(f);
    var src_base: u32 = 0;
    if stag == blot_direct_types::Tag.array {
        let base, _ = ensureCheckedArray(g, f, source);
        src_base = base;
    } else if stag == blot_direct_types::Tag.view {
        let vslot = w(g, source, 0);
        let vgen = w(g, source, 1);
        let vstart = w(g, source, 2);
        let vlen = w(g, source, 3);
        let cv = findCheckedView(f, vslot, vgen, vstart, vlen);
        if cv >= 0 {
            src_base = f.checked_views[cv].base;
        } else {
            let src_entry = local32(g, f);
            lget(g, vslot);
            lget(g, vgen);
            callf(g, rt.check);
            lset(g, src_entry);
            let vend = local32(g, f);
            lget(g, vstart);
            lget(g, vlen);
            op(g, OP_i32_add);
            ltee(g, vend);
            lget(g, vstart);
            op(g, OP_i32_lt_u);
            lget(g, vend);
            lget(g, src_entry);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
            op(g, OP_i32_gt_u);
            op(g, OP_i32_or);
            trap(g, f);
            let raw_base = local32(g, f);
            lget(g, src_entry);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
            lset(g, raw_base);
            src_base = emitOffsetAddress(g, f, raw_base, vstart, step);
        }
    } else {
        let src_entry = ensureCheckedGrow(g, f, source);
        src_base = local32(g, f);
        lget(g, src_entry);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
        lset(g, src_base);
    }

    let dst_base = local32(g, f);
    lget(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
    lset(g, dst_base);
    let dst_addr = emitOffsetAddress(g, f, dst_base, old_len, step);
    let copy_bytes = emitScaledBytes(g, f, count, step);
    lget(g, dst_addr);
    lget(g, src_base);
    lget(g, copy_bytes);
    memoryCopyOp(g);
    lget(g, entry);
    lget(g, new_len);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
    close(g, f);
    return true, blot_direct_types::Error.none;
}

recursive fn countBodyNodes(m: const Module&, id: u32, budget: i64&) -> bool {
    if id == 0 { return true; }
    if budget <= 0 { return false; }
    budget -= 1;
    let n = m.node(id);
    match n.tag {
        suite, block_, product, record, array, array_op, storage => {
            for c in m.children(id) { if !countBodyNodes(m, c, budget) { return false; } }
            return true;
        },
        call, break_ => {
            for c in m.children(id) { if !countBodyNodes(m, c, budget) { return false; } }
            return true;
        },
        bind, construct => { return countBodyNodes(m, n.b, budget); },
        pattern_bind => { return countBodyNodes(m, n.b, budget) && countBodyNodes(m, n.c, budget); },
        return_, project, result_associated => { return countBodyNodes(m, n.a, budget); },
        scalar, logical, associated, apply => { return countBodyNodes(m, n.a, budget) && countBodyNodes(m, n.b, budget); },
        if_value, if_stmt => { return countBodyNodes(m, n.a, budget) && countBodyNodes(m, n.b, budget) && countBodyNodes(m, n.c, budget); },
        update => {
            let u = m.updateInfo(id);
            if !countBodyNodes(m, u.root, budget) || !countBodyNodes(m, u.value, budget) { return false; }
            for s in m.updateSelectors(id) { if s.kind == blot_check_core::UpdateKind.index && !countBodyNodes(m, s.index, budget) { return false; } }
            return true;
        },
        match_ => {
            for inp in m.matchInputs(id) { if !countBodyNodes(m, inp, budget) { return false; } }
            for arm in m.matchArms(id) { if !countBodyNodes(m, arm.guard_, budget) || !countBodyNodes(m, arm.body, budget) { return false; } }
            return true;
        },
        constant, reference, panic => { return true; },
        _ => { return false; },
    }
}

// Unroll `for x in const_array:` over small (1..4) compile-time scalar/enum
// constant arrays so `pool()` + `rt.check()` disappear and Cranelift can
// constant-fold match dispatch on the iteration element.
recursive fn tryUnrollConstArrayLoop(g: Generator&, f: Fn&, id: u32, info: blot_check_core::LoopInfo, iteration: Vals, outgoing: Vals, slots: Words) -> bool, Error {
    if g.runtime_().has_fork { return false, blot_direct_types::Error.none; }
    if info.kind != blot_check_core::LoopKind.array { return false, blot_direct_types::Error.none; }
    var target = BindingRef { 0, 0 };
    var elem_count: i64 = 0;
    var elem_is_const: bool[4] = [false; 4];
    var elem_nodes: u32[4] = [0; 4];
    var elem_vals: u32[4] = [0; 4];
    var elem_ty: Ty = 0;
    {
        let m .= g.units[f.unit - 1];
        if m.node(info.first).tag != blot_check_core::Tag.reference { return false, blot_direct_types::Error.none; }
        target = g.resolve(m, m.reference(info.first));
        if !g.hasUnit(target.unit) { return false, blot_direct_types::Error.none; }
        let tm .= g.units[target.unit - 1];
        let cbody .= tm.body(target.binding);
        if !cbody || cbody.is_function || tm.node(cbody.root).tag != blot_check_core::Tag.array {
            return false, blot_direct_types::Error.none;
        }
        let elems = tm.children(cbody.root);
        if elems.len == 0 || elems.len > 4 { return false, blot_direct_types::Error.none; }
        for el, ei in elems {
            let en = tm.node(el);
            if en.tag == blot_check_core::Tag.constant {
                elem_is_const[ei] = true;
                elem_nodes[ei] = el;
                elem_vals[ei] = en.a;
            } else if en.tag == blot_check_core::Tag.construct && en.b == 0 {
                elem_is_const[ei] = false;
                elem_nodes[ei] = el;
                elem_vals[ei] = tm.constructor(en.a).tag;
            } else {
                return false, blot_direct_types::Error.none;
            }
        }
        elem_count = elems.len;
        let arr_ty, ty_err = g.types.lower(m, m.typeOf(info.first), f.env);
        if ty_err != blot_direct_types::Error.none || tagOf(g, arr_ty) != blot_direct_types::Tag.array {
            return false, blot_direct_types::Error.none;
        }
        elem_ty = g.types.node(arr_ty).a;
        let boxed, berr = isBoxed(g, f, elem_ty, id);
        if berr != blot_direct_types::Error.none || boxed { return false, blot_direct_types::Error.none; }
        let width, werr = layoutLen(g, f, elem_ty, id);
        if werr != blot_direct_types::Error.none || width != 1 { return false, blot_direct_types::Error.none; }
        let carries = m.loopCarries(id);
        for at in 0..carries.len {
            if g.s.words[slots.start + at] != 0 { return false, blot_direct_types::Error.none; }
        }
        var budget: i64 = 64;
        if !countBodyNodes(m, info.body, budget) { return false, blot_direct_types::Error.none; }
    }

    g.recordInlined(target.unit, target.binding);
    let exit = open(g, f, OP_block);
    let unused = g.newSlot();
    for ei in 0..elem_count {
        let iter_done = open(g, f, OP_block);
        var item = neverVal();
        if elem_is_const[ei] {
            let loc = local(g, f, localKindForScalar(g, elem_ty));
            if tagOf(g, elem_ty) == blot_direct_types::Tag.f32_ {
                blot_direct_relocations::operand(target.unit, elem_nodes[ei], g.s.code.len);
                f32Const(g, elem_vals[ei]);
            } else {
                blot_direct_relocations::operand(target.unit, elem_nodes[ei], g.s.code.len);
                i32Const(g, elem_vals[ei]);
            }
            lset(g, loc);
            item = valOf1(g, elem_ty, loc);
        } else {
            let loc = constLocal(g, f, elem_vals[ei]);
            recordConstTag(f, loc, elem_vals[ei]);
            item = valOf1(g, elem_ty, loc);
        }
        if info.pattern != 0 {
            let tested = test_(g, f, info.pattern, item, false, 0, id);
            if tested != blot_direct_types::Error.none { return false, tested; }
        }
        let s .= g.s;
        let labels_mark = s.labels.len;
        s.labels.push(blot_direct_emit::Label { target: id, depth: exit, result: unused, kind: blot_direct_emit::LabelKind.loop_, top: iter_done, iteration: iteration, outgoing: outgoing, unchanged: 0xffffffff, has_release: false, release_owner: 0, release_stack: 0, allocations: f.allocations, slots: slots, saved_esc: 0, guards: Words {} });
        let body_val, body_err = stmt(g, f, info.body);
        s.labels.resize(labels_mark);
        if body_err != blot_direct_types::Error.none { return false, body_err; }
        if body_val.ty != blot_direct_types::never {
            let carry_len = g.units[f.unit - 1].loopCarries(id).len;
            let backedge = g.reserveVals(carry_len);
            for at in 0..carry_len {
                let carry_be = g.units[f.unit - 1].loopCarries(id)[at].backedge;
                let value, present, rerr = readBindingVal(g, f, carry_be, id);
                if rerr != blot_direct_types::Error.none { return false, rerr; }
                if !present { return false, g.fail(g.units[f.unit - 1], id, "loop carry without a backedge value"); }
                g.s.vals[backedge.start + at] = value;
            }
            let assigned = assignCarries(g, f, backedge, iteration, slots, 0xffffffff, 0, 0, id);
            if assigned != blot_direct_types::Error.none { return false, assigned; }
        }
        close(g, f);
    }
    let final_assign = assign(g, f, iteration, outgoing, id);
    if final_assign != blot_direct_types::Error.none { return false, final_assign; }
    close(g, f);
    let carry_len = g.units[f.unit - 1].loopCarries(id).len;
    for at in 0..carry_len {
        let carry_out = g.units[f.unit - 1].loopCarries(id)[at].outgoing;
        bindPut(g, f, carry_out, g.s.vals[outgoing.start + at]);
    }
    return true, blot_direct_types::Error.none;
}

fn localKindForScalar(g: const Generator&, ty: Ty) -> ValType {
    if tagOf(g, ty) == blot_direct_types::Tag.f32_ { return VT_f32; }
    return VT_i32;
}

recursive fn loop_(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let info = g.units[f.unit - 1].loopInfo(id);
    if info.kind == blot_check_core::LoopKind.array && info.carries.len == 0 {
        let bulk_done, bulk_err = tryBulkPushLoop(g, f, id, info);
        if bulk_err != blot_direct_types::Error.none { return neverVal(), bulk_err; }
        if bulk_done { return unitVal(), blot_direct_types::Error.none; }
    }
    var iteration = Vals {};
    var outgoing = Vals {};
    var slots = Words {};
    {
        let m .= g.units[f.unit - 1];
        let carries = m.loopCarries(id);
        let incoming = g.reserveVals(carries.len);
        for carry, at in carries {
            let value, present, rerr = readBindingVal(g, f, carry.incoming, id);
            if rerr != blot_direct_types::Error.none { return neverVal(), rerr; }
            if !present { return neverVal(), g.fail(m, id, "loop carry without an incoming value"); }
            g.s.vals[incoming.start + at] = value;
        }
        iteration = g.reserveVals(carries.len);
        outgoing = g.reserveVals(carries.len);
        // A boxed carry lives in a slot reserved before the loop, so each
        // iteration can release what it allocated.
        slots = Words { g.s.words.len as u32, carries.len as u32 };
        for carry in carries { g.s.words.push(0); }
        for at in 0..carries.len {
            let value = g.s.vals[incoming.start + at];
            let held, error = copiedBox(g, f, value.ty, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let ctag = tagOf(g, value.ty);
            var in_place = false;
            if !held && ctag == blot_direct_types::Tag.array {
                var cbudget: i64 = 256;
                in_place = carryStaysInPlace(m, id, at, carries[at].iteration, carries[at].backedge, cbudget);
            }
            if in_place {
                g.s.vals[iteration.start + at] = value;
                g.s.vals[outgoing.start + at] = value;
                continue;
            }
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
            if isUniqueBoxed(g, f, carry.incoming) && uses(g, f, carry.incoming) == 0 && !bindingCaptured(g, f, carry.incoming) {
                blot_support_zigmap::put(g.s.map_pool, f.unique_boxed, carry.iteration, 1);
            }
        }
    }
    if info.kind == blot_check_core::LoopKind.array {
        let unrolled, uerr = tryUnrollConstArrayLoop(g, f, id, info, iteration, outgoing, slots);
        if uerr != blot_direct_types::Error.none { return neverVal(), uerr; }
        if unrolled { return unitVal(), blot_direct_types::Error.none; }
    }
    let m .= g.units[f.unit - 1];
    let carries = m.loopCarries(id);
    var has_index = false;
    var index: u32 = 0;
    var end = neverVal();
    var has_source = false;
    var source = neverVal();
    var source_view_base: u32 = 0xffffffff;
    var range = CheckedRange {};
    var body_no_resize_budget: i64 = 256;
    let body_no_resize = noStorageResize(g, m, info.body, body_no_resize_budget);
    if !body_no_resize { invalidateCheckedContainers(f); }
    match info.kind {
        forever => {},
        range => {
            has_index = true;
            index = local32(g, f);
            let first, error = expr(g, f, info.first);
            if error != blot_direct_types::Error.none { return first, error; }
            let copied = copy(g, f, first, valOf1(g, blot_direct_types::u32_, index), id);
            if copied != blot_direct_types::Error.none { return neverVal(), copied; }
            let handle, is_view = rangeOwner(g, f, id, info);
            if handle.ty != blot_direct_types::never && !is_view {
                let base, len = ensureCheckedArray(g, f, handle);
                end = valOf1(g, blot_direct_types::u32_, len);
                range.slot = w(g, handle, 0);
                range.generation = w(g, handle, 1);
                range.base = base;
                range.end_local = len;
            } else if handle.ty != blot_direct_types::never && is_view {
                let vslot = w(g, handle, 0);
                let vgen = w(g, handle, 1);
                let vstart = w(g, handle, 2);
                let vlen = w(g, handle, 3);
                end = valOf1(g, blot_direct_types::u32_, vlen);
                let element, elem_err = elementOf(g, f, handle.ty, id);
                if elem_err != blot_direct_types::Error.none { return neverVal(), elem_err; }
                let step, step_err = stride(g, f, element, id);
                if step_err != blot_direct_types::Error.none { return neverVal(), step_err; }
                let cv = findCheckedView(f, vslot, vgen, vstart, vlen);
                if cv >= 0 {
                    range.base = f.checked_views[cv].base;
                    range.trusted_view = true;
                } else {
                    range.base = tryHoistViewBase(g, f, vslot, vgen, vstart, vlen, step, false);
                }
                range.slot = vslot;
                range.generation = vgen;
                range.end_local = vlen;
                range.is_view = true;
                range.view_start = vstart;
            } else {
                let limit, error = fresh(g, f, blot_direct_types::u32_, id);
                if error != blot_direct_types::Error.none { return neverVal(), error; }
                end = limit;
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
            if tagOf(g, source.ty) == blot_direct_types::Tag.array {
                let base, len = ensureCheckedArray(g, f, source);
                range.slot = w(g, source, 0);
                range.generation = w(g, source, 1);
                range.base = base;
                range.end_local = len;
            } else if tagOf(g, source.ty) == blot_direct_types::Tag.view {
                let vslot = w(g, source, 0);
                let vgen = w(g, source, 1);
                let vstart = w(g, source, 2);
                let vlen = w(g, source, 3);
                let element, elem_err = elementOf(g, f, source.ty, id);
                if elem_err != blot_direct_types::Error.none { return neverVal(), elem_err; }
                let step, step_err = stride(g, f, element, id);
                if step_err != blot_direct_types::Error.none { return neverVal(), step_err; }
                let cv = findCheckedView(f, vslot, vgen, vstart, vlen);
                if cv >= 0 {
                    range.slot = vslot;
                    range.generation = vgen;
                    range.base = f.checked_views[cv].base;
                    range.end_local = vlen;
                    range.is_view = true;
                    range.trusted_view = true;
                    range.view_start = vstart;
                } else {
                    var budget: i64 = 256;
                    let static_safe = noStorageResize(g, m, info.body, budget);
                    let vbase = tryHoistViewBase(g, f, vslot, vgen, vstart, vlen, step, !static_safe);
                    source_view_base = vbase;
                }
            }
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
            if source_view_base != 0xffffffff {
                let element, elem_err = elementOf(g, f, source.ty, id);
                if elem_err != blot_direct_types::Error.none { return neverVal(), elem_err; }
                let step, step_err = stride(g, f, element, id);
                if step_err != blot_direct_types::Error.none { return neverVal(), step_err; }
                let addr = local32(g, f);
                lget(g, source_view_base);
                let fast = open(g, f, OP_if_);
                let fast_addr = emitOffsetAddress(g, f, source_view_base, current, step);
                lget(g, fast_addr);
                lset(g, addr);
                popCheckedArraysAt(f, fast);
                op(g, OP_else_);
                let slow_addr, slow_err = elementAddress(g, f, source, current, id);
                if slow_err != blot_direct_types::Error.none { return neverVal(), slow_err; }
                lget(g, slow_addr);
                lset(g, addr);
                close(g, f);
                let loaded, lerr = loadElement(g, f, addr, 0, element, id);
                if lerr != blot_direct_types::Error.none { return neverVal(), lerr; }
                item = loaded;
            } else {
                let previous_range = f.checked_range;
                f.checked_range = range;
                let element, error = readElement(g, f, source, current, id);
                f.checked_range = previous_range;
                if error != blot_direct_types::Error.none { return neverVal(), error; }
                item = element;
            }
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
    let saved_esc = local32(g, f);
    let mark_at = s.code.len;
    let allocations = f.allocations;
    let stores = f.memory_stores;
    let unused = g.newSlot();
    let labels_mark = s.labels.len;
    s.labels.push(blot_direct_emit::Label { target: id, depth: exit, result: unused, kind: blot_direct_emit::LabelKind.loop_, top: top, iteration: iteration, outgoing: outgoing, unchanged: unchanged, has_release: release, release_owner: owner_mark, release_stack: stack_mark, allocations: allocations, slots: slots, saved_esc: saved_esc, guards: guards });
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
        if label.has_release && (f.allocations != allocations || label.used) {
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
    if release && (f.allocations != allocations || label.used) {
        // Insert the iteration's marks and escape save/reset at its start.
        var prefix: u8[>..<] = [];
        markInto(g, prefix, owner_mark, stack_mark);
        let esc_global = g.runtime_().escape_min_slot;
        prefix.push(OP_global_get);
        blot_direct_writer::uleb(prefix, esc_global);
        prefix.push(OP_local_set);
        blot_direct_writer::uleb(prefix, saved_esc);
        prefix.push(OP_i32_const);
        blot_direct_writer::sleb(prefix, -1);
        prefix.push(OP_global_set);
        blot_direct_writer::uleb(prefix, esc_global);
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
// Merges `min_u(cur_esc, saved_esc)` back into `rt.escape_min_slot`.
fn emitMergeEscapeMin(g: Generator&, f: Fn&, cur_esc: u32, saved_esc: u32) {
    let rt = g.runtime_();
    lget(g, cur_esc);
    lget(g, saved_esc);
    lget(g, cur_esc);
    lget(g, saved_esc);
    op(g, OP_i32_lt_u);
    op(g, OP_select);
    gset(g, rt.escape_min_slot);
}
fn emitMergeEscapeMinCurrent(g: Generator&, f: Fn&, saved_esc: u32) {
    let cur_esc = local32(g, f);
    gget(g, g.runtime_().escape_min_slot);
    lset(g, cur_esc);
    emitMergeEscapeMin(g, f, cur_esc, saved_esc);
}
// Records a store into an untracked cell/effect, conservatively escaping to age 0.
fn noteStore(g: Generator&, f: Fn&, value: Val) -> Error {
    if value.ty == blot_direct_types::never { return blot_direct_types::Error.none; }
    let holds, error = g.contentsHoldMemory(value.ty);
    if error != blot_direct_types::Error.none { return error; }
    if holds {
        f.memory_stores += 1;
        i32Const(g, 0);
        gset(g, g.runtime_().escape_min_slot);
    }
    return blot_direct_types::Error.none;
}
// Collect byte offsets of plain-element owner/view handles inside the flat memory
// layout of a non-recursive copied-box value (`copiedBox == true`). Returns `false`
// if any memory-holding part is recursive, nested-owner, closure, multi-variant sum,
// or exceeds the fixed 16-slot buffer.
recursive fn collectFlatPlainOwnerOffsets(g: Generator&, ty: Ty, base_off: u32, out: u32[16]&, out_len: i64&) -> bool, Error {
    let holds, error = g.contentsHoldMemory(ty);
    if error != blot_direct_types::Error.none { return false, error; }
    if !holds { return true, blot_direct_types::Error.none; }
    let rec, rerr = g.types.isRecursive(ty);
    if rerr != blot_direct_types::Error.none { return false, rerr; }
    if rec { return false, blot_direct_types::Error.none; }
    let n = g.types.node(ty);
    match n.tag {
        array, view, ref, link => {
            let elem_holds, herr = g.contentsHoldMemory(n.a);
            if herr != blot_direct_types::Error.none { return false, herr; }
            if elem_holds || out_len >= 16 { return false, blot_direct_types::Error.none; }
            out[out_len] = base_off;
            out_len += 1;
            return true, blot_direct_types::Error.none;
        },
        tuple => {
            var off = base_off;
            for index in 0..(n.b as i64) {
                let item = g.types.words[n.a + index];
                let ok, oerr = collectFlatPlainOwnerOffsets(g, item, off, out, out_len);
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
                let ok, oerr = collectFlatPlainOwnerOffsets(g, field, off, out, out_len);
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
            return collectFlatPlainOwnerOffsets(g, payload, base_off, out, out_len);
        },
        _ => { return false, blot_direct_types::Error.none; },
    }
}
// Collect owner-slot locals of plain-element owner/view handles inside an unboxed Val.
recursive fn collectRegPlainOwnerSlots(g: Generator&, ty: Ty, words: u32, out: u32[16]&, out_len: i64&) -> bool, Error {
    let holds, error = g.contentsHoldMemory(ty);
    if error != blot_direct_types::Error.none { return false, error; }
    if !holds { return true, blot_direct_types::Error.none; }
    let boxed, berr = g.types.boxed(ty);
    if berr != blot_direct_types::Error.none { return false, berr; }
    if boxed { return false, blot_direct_types::Error.none; }
    let n = g.types.node(ty);
    match n.tag {
        array, view, ref, link => {
            let elem_holds, herr = g.contentsHoldMemory(n.a);
            if herr != blot_direct_types::Error.none { return false, herr; }
            if elem_holds || out_len >= 16 { return false, blot_direct_types::Error.none; }
            out[out_len] = g.s.words[words];
            out_len += 1;
            return true, blot_direct_types::Error.none;
        },
        tuple => {
            var at: u32 = 0;
            for index in 0..(n.b as i64) {
                let item = g.types.words[n.a + index];
                let layout, lerr = g.types.layout(item);
                if lerr != blot_direct_types::Error.none { return false, lerr; }
                let width = layout.len as u32;
                let ok, oerr = collectRegPlainOwnerSlots(g, item, words + at, out, out_len);
                if oerr != blot_direct_types::Error.none { return false, oerr; }
                if !ok { return false, blot_direct_types::Error.none; }
                at += width;
            }
            return true, blot_direct_types::Error.none;
        },
        record => {
            var at: u32 = 0;
            for index in 0..(n.b as i64) {
                let field = g.types.recordField(ty, index).ty;
                let layout, lerr = g.types.layout(field);
                if lerr != blot_direct_types::Error.none { return false, lerr; }
                let width = layout.len as u32;
                let ok, oerr = collectRegPlainOwnerSlots(g, field, words + at, out, out_len);
                if oerr != blot_direct_types::Error.none { return false, oerr; }
                if !ok { return false, blot_direct_types::Error.none; }
                at += width;
            }
            return true, blot_direct_types::Error.none;
        },
        nominal => {
            let cases, verr = g.types.variants(ty);
            if verr != blot_direct_types::Error.none { return false, verr; }
            if cases.len != 1 { return false, blot_direct_types::Error.none; }
            let payload = g.types.variant_payloads[cases.payloads];
            return collectRegPlainOwnerSlots(g, payload, words, out, out_len);
        },
        _ => { return false, blot_direct_types::Error.none; },
    }
}
// Records a store into the owner at `dst_slot`, propagating normalized age into `rt.escape_min_slot`.
// When `value` is a non-recursive flat value whose only memory-holding leaves are plain-element
// owners/views (such as `render.Draw` holding static `&no_extra[0..0]`), only a leaf temporary
// handle strictly newer than `dst_slot` (`src_slot < persistent_split && age < src_slot`) can
// escape and disable enclosing scope releases.
fn noteStoreToSlot(g: Generator&, f: Fn&, dst_slot: u32, value: Val) -> Error {
    if value.ty == blot_direct_types::never { return blot_direct_types::Error.none; }
    let holds, error = g.contentsHoldMemory(value.ty);
    if error != blot_direct_types::Error.none { return error; }
    if !holds { return blot_direct_types::Error.none; }
    let rt = g.runtime_();
    let age = local32(g, f);
    i32Const(g, 0);
    lget(g, dst_slot);
    lget(g, dst_slot);
    i32Const(g, rt.layout.persistent_split);
    op(g, OP_i32_ge_u);
    op(g, OP_select);
    lset(g, age);
    let boxed, berr = g.types.boxed(value.ty);
    if berr != blot_direct_types::Error.none { return berr; }
    let rec, rerr = g.types.isRecursive(value.ty);
    if rerr != blot_direct_types::Error.none { return rerr; }
    var items: u32[16] = [0; 16];
    var count: i64 = 0;
    if boxed && !rec {
        let ok, cerr = collectFlatPlainOwnerOffsets(g, value.ty, 0, items, count);
        if cerr != blot_direct_types::Error.none { return cerr; }
        if ok {
            if count > 0 {
                let src_slot = local32(g, f);
                for i in 0..count {
                    let off = items[i];
                    lget(g, w(g, value, 0));
                    op(g, OP_i32_load); uleb(g, 2); uleb(g, off);
                    ltee(g, src_slot);
                    i32Const(g, rt.layout.persistent_split);
                    op(g, OP_i32_lt_u);
                    lget(g, age);
                    lget(g, src_slot);
                    op(g, OP_i32_lt_u);
                    op(g, OP_i32_and);
                    let esc_if = open(g, f, OP_if_);
                    emitMergeEscapeMinCurrent(g, f, age);
                    close(g, f);
                }
            }
            return blot_direct_types::Error.none;
        }
    } else if !boxed {
        let ok, cerr = collectRegPlainOwnerSlots(g, value.ty, value.start, items, count);
        if cerr != blot_direct_types::Error.none { return cerr; }
        if ok {
            if count > 0 {
                for i in 0..count {
                    let src_slot = items[i];
                    lget(g, src_slot);
                    i32Const(g, rt.layout.persistent_split);
                    op(g, OP_i32_lt_u);
                    lget(g, age);
                    lget(g, src_slot);
                    op(g, OP_i32_lt_u);
                    op(g, OP_i32_and);
                    let esc_if = open(g, f, OP_if_);
                    emitMergeEscapeMinCurrent(g, f, age);
                    close(g, f);
                }
            }
            return blot_direct_types::Error.none;
        }
    }
    emitMergeEscapeMinCurrent(g, f, age);
    return blot_direct_types::Error.none;
}
// Releases an iteration's allocations when no inter-procedural store escaped past
// `label.release_owner` and every carried owner predates the iteration.
fn releaseIteration(g: Generator&, f: Fn&, label: blot_direct_emit::Label, iter_esc: u32) {
    lget(g, iter_esc);
    lget(g, label.release_owner);
    op(g, OP_i32_ge_u);
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
        array, view, ref, link => {
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
        // Merge saved escape marks for every inner releasing loop strictly inside `at`.
        var lk = g.s.labels.len;
        while lk > at + 1 {
            lk -= 1;
            if g.s.labels[lk].kind == blot_direct_emit::LabelKind.loop_ && g.s.labels[lk].has_release {
                g.s.labels[lk].used = true;
                emitMergeEscapeMinCurrent(g, f, g.s.labels[lk].saved_esc);
            }
        }
        if n.op == blot_check_core::Op.continue_ {
            let assigned = assignCarries(g, f, values, label.iteration, label.slots, label.unchanged, label.release_owner, label.release_stack, id);
            if assigned != blot_direct_types::Error.none { return neverVal(), assigned; }
            if label.has_release {
                g.s.labels[at].used = true;
                let iter_esc = local32(g, f);
                gget(g, g.runtime_().escape_min_slot);
                lset(g, iter_esc);
                if f.allocations != label.allocations {
                    releaseIteration(g, f, label, iter_esc);
                }
                emitMergeEscapeMin(g, f, iter_esc, label.saved_esc);
            }
            br(g, f, OP_br, label.top);
        } else {
            let assigned = assign(g, f, values, label.outgoing, id);
            if assigned != blot_direct_types::Error.none { return neverVal(), assigned; }
            if label.has_release {
                g.s.labels[at].used = true;
                emitMergeEscapeMinCurrent(g, f, label.saved_esc);
            }
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

// Synchronous ordered data-parallel array map `spark #[body | pat <- source]`.
// Phase 1 emits an escape-safe preallocated direct loop; Phase 2 adds 4-wide
// Wasm SIMD (`v128`) vectorization ahead of this scalar fallback.
recursive fn sparkNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let info = m.sparkInfo(id);
    let out_ty, ty_err = typeOf(g, f, id);
    if ty_err != blot_direct_types::Error.none { return neverVal(), ty_err; }
    let elem_ty, elem_err = elementOf(g, f, out_ty, id);
    if elem_err != blot_direct_types::Error.none { return neverVal(), elem_err; }
    let step, step_err = stride(g, f, elem_ty, id);
    if step_err != blot_direct_types::Error.none { return neverVal(), step_err; }
    let elem_holds, hold_err = g.contentsHoldMemory(elem_ty);
    if hold_err != blot_direct_types::Error.none { return neverVal(), hold_err; }

    var start_local: u32 = 0;
    var count: u32 = 0;
    var source_val = neverVal();
    if info.is_range {
        let s_val, s_err = expr(g, f, info.source);
        if s_err != blot_direct_types::Error.none { return s_val, s_err; }
        let s_loc, sl_err = scalarLocal(g, f, s_val, id);
        if sl_err != blot_direct_types::Error.none { return neverVal(), sl_err; }
        start_local = s_loc;
        let e_val, e_err = expr(g, f, info.end);
        if e_err != blot_direct_types::Error.none { return e_val, e_err; }
        let e_loc, el_err = scalarLocal(g, f, e_val, id);
        if el_err != blot_direct_types::Error.none { return neverVal(), el_err; }
        count = local32(g, f);
        lget(g, e_loc);
        lget(g, start_local);
        op(g, OP_i32_gt_u);
        let cmp_if = open(g, f, OP_if_);
        lget(g, e_loc);
        lget(g, start_local);
        op(g, OP_i32_sub);
        lset(g, count);
        popCheckedArraysAt(f, cmp_if);
        op(g, OP_else_);
        i32Const(g, 0);
        lset(g, count);
        close(g, f);
    } else {
        let c_val, c_err = expr(g, f, info.source);
        if c_err != blot_direct_types::Error.none { return c_val, c_err; }
        source_val = c_val;
        let len_loc, len_err = lengthOf(g, f, source_val, id);
        if len_err != blot_direct_types::Error.none { return neverVal(), len_err; }
        count = len_loc;
    }

    let handle, base, alloc_err = createUninit(g, f, out_ty, count, id);
    if alloc_err != blot_direct_types::Error.none { return handle, alloc_err; }

    let vectorized, vec_index, vec_err = tryEmitVectorSpark(g, f, id, out_ty, elem_ty, start_local, source_val, count, base);
    if vec_err != blot_direct_types::Error.none { return neverVal(), vec_err; }

    var index: u32 = 0;
    if vectorized {
        index = vec_index;
    } else {
        g.s.sparks_scalar_fallback += 1;
        index = constLocal(g, f, 0);
    }
    let exit = open(g, f, OP_block);
    let top = open(g, f, OP_loop);
    lget(g, index);
    lget(g, count);
    op(g, OP_i32_ge_u);
    br(g, f, OP_br_if, exit);

    let owner_mark = local32(g, f);
    let stack_mark = local32(g, f);
    let saved_esc = local32(g, f);
    let mark_at = g.s.code.len;
    let allocs_before = f.allocations;
    let stores_before = f.memory_stores;

    var item = neverVal();
    if info.is_range {
        let cur = local32(g, f);
        lget(g, start_local);
        lget(g, index);
        op(g, OP_i32_add);
        lset(g, cur);
        item = valOf1(g, blot_direct_types::u32_, cur);
    } else {
        let loaded, lerr = readElement(g, f, source_val, index, id, g.units[f.unit - 1].typeOf(info.source));
        if lerr != blot_direct_types::Error.none { return neverVal(), lerr; }
        item = loaded;
    }

    let saved_bindings = blot_support_zigmap::clone(g.s.map_pool, f.bindings);
    let tested = test_(g, f, info.pattern, item, false, 0, id);
    if tested != blot_direct_types::Error.none {
        f.bindings = saved_bindings;
        return neverVal(), tested;
    }
    let val, verr = stmt(g, f, info.body);
    f.bindings = saved_bindings;
    if verr != blot_direct_types::Error.none { return val, verr; }

    if val.ty != blot_direct_types::never {
        let dst_addr = emitOffsetAddress(g, f, base, index, step);
        let written = writeFlat(g, f, dst_addr, 0, val, id);
        if written != blot_direct_types::Error.none { return neverVal(), written; }
        // Escape-safe per-iteration scratch release: only release when output
        // elements cannot hold scope memory and no store escaped past owner_mark.
        let release_ok = !elem_holds && f.memory_stores == stores_before && f.allocations != allocs_before;
        if release_ok {
            let iter_esc = local32(g, f);
            gget(g, g.runtime_().escape_min_slot);
            ltee(g, iter_esc);
            lget(g, owner_mark);
            op(g, OP_i32_ge_u);
            let rel_if = open(g, f, OP_if_);
            releaseTo(g, owner_mark, stack_mark);
            close(g, f);
            emitMergeEscapeMin(g, f, iter_esc, saved_esc);
            var prefix: u8[>..<] = [];
            markInto(g, prefix, owner_mark, stack_mark);
            let esc_global = g.runtime_().escape_min_slot;
            prefix.push(OP_global_get);
            blot_direct_writer::uleb(prefix, esc_global);
            prefix.push(OP_local_set);
            blot_direct_writer::uleb(prefix, saved_esc);
            prefix.push(OP_i32_const);
            blot_direct_writer::sleb(prefix, -1);
            prefix.push(OP_global_set);
            blot_direct_writer::uleb(prefix, esc_global);
            blot_direct_relocations::insert(f.sites_base, mark_at, prefix.len);
            let old_len = g.s.code.len;
            for byte in prefix { g.s.code.push(byte); }
            var at = old_len;
            while at > mark_at {
                at -= 1;
                g.s.code[at + prefix.len] = g.s.code[at];
            }
            for byte, offset in prefix { g.s.code[mark_at + offset] = byte; }
        }
        lget(g, index);
        i32Const(g, 1);
        op(g, OP_i32_add);
        lset(g, index);
        br(g, f, OP_br, top);
    }
    close(g, f);
    close(g, f);
    return handle, blot_direct_types::Error.none;
}

recursive fn flatOpNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    if n.c == blot_check_core::flat_op_kernel_handle {
        let kidx = n.a;
        if (kidx as i64) >= g.s.kernels.len {
            return neverVal(), g.fail(m, id, "unknown kernel declaration index");
        }
        let kinfo = g.s.kernels[kidx];
        let ty, ty_err = typeOf(g, f, id);
        if ty_err != blot_direct_types::Error.none { return neverVal(), ty_err; }
        let w0 = constLocal(g, f, kidx);
        let w1 = constLocal(g, f, (kinfo.binding_hash & 0xffffffff) as u32);
        let w2 = constLocal(g, f, (kinfo.binding_hash >> 32) as u32);
        let w3 = constLocal(g, f, (kinfo.ctx_schema.schema_hash & 0xffffffff) as u32);
        let w4 = constLocal(g, f, (kinfo.ctx_schema.schema_hash >> 32) as u32);
        let w5 = constLocal(g, f, (kinfo.io_schema_hash & 0xffffffff) as u32);
        let w6 = constLocal(g, f, (kinfo.io_schema_hash >> 32) as u32);
        let boxed, berr = isBoxed(g, f, ty, id);
        if berr != blot_direct_types::Error.none { return neverVal(), berr; }
        if boxed {
            let blk, merr = newBlock(g, f, ty, id);
            if merr != blot_direct_types::Error.none { return neverVal(), merr; }
            let vals: u32[7] = [w0, w1, w2, w3, w4, w5, w6];
            for wi in 0..7 {
                lget(g, blk);
                lget(g, vals[wi]);
                op(g, OP_i32_store);
                uleb(g, 2);
                uleb(g, (wi * 4) as u32);
            }
            return valOf1(g, ty, blk), blot_direct_types::Error.none;
        }
        let words = g.saveWords([w0, w1, w2, w3, w4, w5, w6]);
        return Val { ty, words.start, words.len }, blot_direct_types::Error.none;
    }
    if n.c == blot_check_core::flat_op_process_handle {
        let ty, ty_err = typeOf(g, f, id);
        if ty_err != blot_direct_types::Error.none { return neverVal(), ty_err; }
        let loc = constLocal(g, f, n.a);
        return valOf1(g, ty, loc), blot_direct_types::Error.none;
    }
    if n.c == blot_check_core::flat_op_kernel_id {
        let kval, kerr = expr(g, f, n.a);
        if kerr != blot_direct_types::Error.none { return kval, kerr; }
        let boxed, berr = isBoxed(g, f, kval.ty, id);
        if berr != blot_direct_types::Error.none { return neverVal(), berr; }
        if boxed {
            let res = local32(g, f);
            lget(g, w(g, kval, 0));
            op(g, OP_i32_load);
            uleb(g, 2);
            uleb(g, 0);
            lset(g, res);
            return valOf1(g, blot_direct_types::u32_, res), blot_direct_types::Error.none;
        }
        return valOf1(g, blot_direct_types::u32_, w(g, kval, 0)), blot_direct_types::Error.none;
    }
    if n.c == blot_check_core::flat_op_kernel_binding_hash || n.c == blot_check_core::flat_op_kernel_ctx_hash || n.c == blot_check_core::flat_op_kernel_io_hash {
        let kval, kerr = expr(g, f, n.a);
        if kerr != blot_direct_types::Error.none { return kval, kerr; }
        let ty, ty_err = typeOf(g, f, id);
        if ty_err != blot_direct_types::Error.none { return neverVal(), ty_err; }
        var word_base: i64 = 1;
        if n.c == blot_check_core::flat_op_kernel_ctx_hash { word_base = 3; }
        else if n.c == blot_check_core::flat_op_kernel_io_hash { word_base = 5; }
        let boxed, berr = isBoxed(g, f, kval.ty, id);
        if berr != blot_direct_types::Error.none { return neverVal(), berr; }
        var lo: u32 = 0;
        var hi: u32 = 0;
        if boxed {
            lo = local32(g, f);
            lget(g, w(g, kval, 0));
            op(g, OP_i32_load);
            uleb(g, 2);
            uleb(g, (word_base * 4) as u32);
            lset(g, lo);
            hi = local32(g, f);
            lget(g, w(g, kval, 0));
            op(g, OP_i32_load);
            uleb(g, 2);
            uleb(g, ((word_base + 1) * 4) as u32);
            lset(g, hi);
        } else {
            lo = w(g, kval, word_base);
            hi = w(g, kval, word_base + 1);
        }
        let words = g.saveWords([lo, hi]);
        return Val { ty, words.start, words.len }, blot_direct_types::Error.none;
    }
    if n.c == blot_check_core::flat_op_schema_hash {
        let ignored, aerr = expr(g, f, n.a);
        if aerr != blot_direct_types::Error.none { return ignored, aerr; }
        let ty, ty_err = typeOf(g, f, id);
        if ty_err != blot_direct_types::Error.none { return neverVal(), ty_err; }
        let h, ok = blot_check_wire_schema::computeSchemaHash(g.units, f.unit, n.b);
        if !ok {
            return neverVal(), g.failCode(m, id, blot_check_diagnostic_code::Code.kernel_type, "@flat.schema_hash requires a closed FlatNumeric, Unit, #[U32], or #[F32] type");
        }
        let lo = constLocal(g, f, (h & 0xffffffff) as u32);
        let hi = constLocal(g, f, (h >> 32) as u32);
        let words = g.saveWords([lo, hi]);
        return Val { ty, words.start, words.len }, blot_direct_types::Error.none;
    }
    if n.c == blot_check_core::flat_op_encode {
        let arg_val, aerr = expr(g, f, n.a);
        if aerr != blot_direct_types::Error.none { return arg_val, aerr; }
        let out_ty, ty_err = typeOf(g, f, id);
        if ty_err != blot_direct_types::Error.none { return neverVal(), ty_err; }
        return emitFlatEncodeVal(g, f, arg_val, n.b, out_ty, id);
    }
    if n.c == blot_check_core::flat_op_decode {
        let src_val, serr = expr(g, f, n.a);
        if serr != blot_direct_types::Error.none { return src_val, serr; }
        let maybe_ty, ty_err = typeOf(g, f, id);
        if ty_err != blot_direct_types::Error.none { return neverVal(), ty_err; }
        return emitFlatDecodeVal(g, f, src_val, m.typeOf(id), maybe_ty, id);
    }
    return neverVal(), g.fail(m, id, "unknown @flat intrinsic");
}
