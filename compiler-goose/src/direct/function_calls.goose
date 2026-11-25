// Calls, closures applied, partial applications and generalized locals of the
// direct backend's function emitter (compiler/src/direct/function.zig).
namespace blot_direct_function;
import .function;

// Generic requirements specialize in the caller's evidence context. A
// closed use in a body can instead select its defining module's evidence.
fn requiresEvidence(g: const Generator&, target: BindingRef) -> bool {
    if !g.hasUnit(target.unit) { return false; }
    let m .= g.units[target.unit - 1];
    if target.binding >= m.bindings.len { return false; }
    let body .= m.body(target.binding);
    if !body { return false; }
    if m.node(body.root).tag == blot_check_core::Tag.contract_method { return true; }
    let goals = body.scheme.obligations;
    for obligation in m.obligations[goals.start..goals.start + goals.len] {
        if obligation.kind == blot_check_types::ObligationKind.contract { return true; }
    }
    return false;
}
fn evidenceContext(g: Generator&, f: const Fn&, target: BindingRef, id: u32) -> u32 {
    if !requiresEvidence(g, target) { return 0; }
    if f.evidence_context == 0 { return f.unit; }
    if id != 0 && f.unit != f.evidence_context {
        let m .= g.units[f.unit - 1];
        var signature = m.typeOf(id);
        if m.node(id).tag == blot_check_core::Tag.call { signature = m.call(id).callee_type; }
        let _, error = g.types.lower(m, signature, Env {});
        if error == blot_direct_types::Error.none { return f.unit; }
    }
    return f.evidence_context;
}

// Contract member symbols are local to each Core module. The members in
// both copies of the declaration follow the original declaration order.
fn memberName(origin: const Module&, context: const Module&, template: blot_reuse_principal_interface::MemberTemplate) -> u32 {
    if origin.unit == context.unit { return template.name; }
    for declared in origin.contracts {
        if declared.identity != template.contract { continue; }
        for member, index in origin.contract_members[declared.members.start..declared.members.start + declared.members.len] {
            if member.name != template.name { continue; }
            for observed in context.contracts {
                if observed.identity == template.contract && index < observed.members.len {
                    return context.contract_members[observed.members.start + index].name;
                }
            }
        }
    }
    return 0;
}

// Lowered Wasm function types omit effect rows. Comparing them would merge
// separate implementation heads and could select the wrong proof.
recursive fn hasContractArgumentIdentity(g: const Generator&, ty: Ty, depth: i64) -> bool {
    if depth >= 256 { return false; }
    let shape = g.types.node(ty);
    match shape.tag {
        unit, boolean, u32_, f32_ => { return true; },
        function, provider, state_provider, cell, never => { return false; },
        array, ref, view, link => { return hasContractArgumentIdentity(g, shape.a, depth + 1); },
        tuple => {
            for child in g.types.words[shape.a..shape.a + shape.b] {
                if !hasContractArgumentIdentity(g, child, depth + 1) { return false; }
            }
        },
        record => {
            for index in 0..shape.b {
                if !hasContractArgumentIdentity(g, g.types.recordField(ty, index).ty, depth + 1) { return false; }
            }
        },
        nominal => {
            for child in g.types.words[shape.a + 2..shape.a + 2 + shape.b] {
                if !hasContractArgumentIdentity(g, child, depth + 1) { return false; }
            }
        },
    }
    return true;
}

fn staticContractTarget(g: Generator&, f: const Fn&, id: u32) -> BindingRef, Error {
    let m .= g.units[f.unit - 1];
    let template = m.member_templates[m.node(id).a];
    var context = f.evidence_context;
    if context == 0 { context = f.unit; }
    let catalog .= g.units[context - 1];
    let name = memberName(m, catalog, template);
    for contract in m.contracts {
        if contract.identity == template.contract && contract.row_parameters.len != 0 {
            return BindingRef { 0, 0 }, g.fail(m, id, "a contract method with effect row arguments");
        }
    }
    var parameters: Ty[>..<] = [];
    for argument in m.types.list(template.arguments) {
        let resolved, error = g.types.lower(m, argument, f.env);
        if error != blot_direct_types::Error.none { return BindingRef { 0, 0 }, g.typeFailure(m, id); }
        if !hasContractArgumentIdentity(g, resolved, 0) {
            return BindingRef { 0, 0 }, g.fail(m, id, "a contract method whose type arguments are not first-order data");
        }
        parameters.push(resolved);
    }
    var target = BindingRef { 0, 0 };
    for unit in g.units {
        let uname = memberName(m, unit, template);
        if uname == 0 { continue; }
        for impl_ in unit.implementations {
            if impl_.contract != template.contract { continue; }
            if impl_.private && unit.unit != context { continue; }
            let head_list = unit.types.list(impl_.head);
            if head_list.len != parameters.len { continue; }
            var match_env = Env {};
            var matches = true;
            for head_arg, index in head_list {
                let want = parameters[index];
                g.types.match_(unit, head_arg, want, match_env);
                let lowered, lerr = g.types.lower(unit, head_arg, match_env);
                if lerr != blot_direct_types::Error.none { matches = false; break; }
                if lowered != want {
                    matches = false; break;
                }
            }
            if !matches { continue; }
            for member in unit.implementation_members[impl_.members.start..impl_.members.start + impl_.members.len] {
                if member.name != uname || member.kind != blot_reuse_principal_interface::ImplementationMemberKind.value { continue; }
                let candidate = g.resolve(unit, BindingRef { member.target.unit, member.target.binding });
                if target.binding != 0 && target != candidate { return BindingRef { 0, 0 }, g.fail(m, id, "ambiguous contract methods at this concrete type"); }
                target = candidate;
            }
        }
    }
    if target.binding == 0 {
        return BindingRef { 0, 0 }, g.fail(m, id, "contract method has no selected implementation in its evidence context");
    }
    return target, blot_direct_types::Error.none;
}
recursive fn staticContractMethod(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let target, error = staticContractTarget(g, f, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let arguments = m.children(id);
    let values = g.reserveVals(arguments.len);
    for argument, index in arguments {
        let value, error = expr(g, f, argument);
        if error != blot_direct_types::Error.none { return value, error; }
        g.s.vals[values.start + index] = value;
    }
    let result, error = typeOf(g, f, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let signature, error = curried(g, values, result);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    return callTarget(g, f, target, values, signature, result, id);
}

// Marks a primitive node (rather than a binding) as a partial target.
let primitive_node_bit: u32 = 0x80000000;

// Calls the closure `callee` with one argument.
fn applyClosure(g: Generator&, f: Fn&, callee: Val, argument: Val, id: u32, is_tail: bool = false) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let arrow = g.types.node(callee.ty);
    if arrow.tag != blot_direct_types::Tag.function || callee.len != 2 { return neverVal(), g.fail(m, id, "application of a non-function value"); }
    let parameter_words, error = layoutLen(g, f, arrow.a, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    if parameter_words != argument.len {
        g.failOpen(m, id);
        g.put("closure argument of ");
        g.putNumber(argument.len);
        g.put(" words for a ");
        g.put(blot_direct_types::tagName(tagOf(g, arrow.a)));
        g.put(" parameter of ");
        g.putNumber(parameter_words);
        g.put(" words");
        return neverVal(), g.failClose();
    }
    lget(g, w(g, callee, 1));
    push(g, argument);
    lget(g, w(g, callee, 0));
    let signature, error = g.closureSignature(arrow.a, arrow.b);
    if error != blot_direct_types::Error.none { return neverVal(), g.typeFailure(m, id); }
    if is_tail && blot_direct_writer::tailCallsEnabled() && !g.s.instances[f.instance_id].inferring &&
        arrow.b == g.s.instances[f.instance_id].result &&
        g.s.instances[f.instance_id].result != blot_direct_types::never {
        opIndex(g, OP_return_call_indirect, signature);
        uleb(g, 0);
        f.emitted_return_call = true;
        f.checked_elems_len = 0;
        return neverVal(), blot_direct_types::Error.none;
    }
    opIndex(g, OP_call_indirect, signature);
    uleb(g, 0);
    f.checked_elems_len = 0;
    return received(g, f, arrow.b, id);
}
recursive fn apply(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let is_tail = f.tail_call_node == id;
    f.tail_call_node = 0;
    let m .= g.units[f.unit - 1];
    // Unwind `receiver.method a1 ... aK` into a direct call without allocating
    // intermediate partial-application closures or using `call_indirect`.
    var chain_args: u32[8] = [0; 8];
    var chain_len: i64 = 0;
    var cursor = id;
    while m.node(cursor).tag == blot_check_core::Tag.apply && chain_len < 8 {
        chain_args[chain_len] = m.node(cursor).b;
        chain_len += 1;
        cursor = m.node(cursor).a;
    }
    if chain_len > 0 && m.node(cursor).tag == blot_check_core::Tag.project {
        let proj = m.node(cursor);
        let receiver, error = expr(g, f, proj.a);
        if error != blot_direct_types::Error.none { return receiver, error; }
        let field_val, target, is_method, error = projectFieldOrMethod(g, f, cursor, receiver);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        if is_method {
            let all_args = g.reserveVals(1 + chain_len);
            g.s.vals[all_args.start] = receiver;
            for step in 0..chain_len {
                let arg_node = chain_args[chain_len - 1 - step];
                let val, error = expr(g, f, arg_node);
                if error != blot_direct_types::Error.none { return val, error; }
                g.s.vals[all_args.start + 1 + step] = val;
            }
            let callee, error = calleeOf(g, f, target, all_args, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let rest, error = restType(g, f, callee, all_args.len as i64, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            if is_tail { f.tail_call_node = id; }
            let res_v, res_err = callTarget(g, f, target, all_args, callee, rest, id);
            f.tail_call_node = 0;
            return res_v, res_err;
        }
        var current = field_val;
        for step in 0..chain_len {
            let arg_node = chain_args[chain_len - 1 - step];
            let arg_val, error = expr(g, f, arg_node);
            if error != blot_direct_types::Error.none { return arg_val, error; }
            let applied, error = applyClosure(g, f, current, arg_val, id, is_tail && step + 1 == chain_len);
            if error != blot_direct_types::Error.none { return applied, error; }
            current = applied;
        }
        return current, blot_direct_types::Error.none;
    }
    let n = m.node(id);
    let callee, error = expr(g, f, n.a);
    if error != blot_direct_types::Error.none { return callee, error; }
    let argument, error = expr(g, f, n.b);
    if error != blot_direct_types::Error.none { return argument, error; }
    // An effect operation's handler (a state cell's setter, for one) may store
    // a memory-holding argument into older storage.
    var head = n.a;
    while m.node(head).tag == blot_check_core::Tag.apply { head = m.node(head).a; }
    if m.node(head).tag == blot_check_core::Tag.operation_value {
        let noted = noteStore(g, f, argument);
        if noted != blot_direct_types::Error.none { return neverVal(), noted; }
    }
    return applyClosure(g, f, callee, argument, id, is_tail);
}
fn constructorFunction(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let n = g.units[f.unit - 1].node(id);
    let ty, error = typeOf(g, f, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    return partial(g, f, blot_direct_emit::InstanceKind.constructor, BindingRef { f.unit, n.a }, ty, Vals {}, id);
}
fn primitiveFunction(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let ty, error = typeOf(g, f, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    // A primitive node is its own target: the unit's primitive catalog.
    return partial(g, f, blot_direct_emit::InstanceKind.primitive, BindingRef { f.unit, id | primitive_node_bit }, ty, Vals {}, id);
}

// A global array constant: one persistent owner per instance, initialized on
// first use.
fn pool(g: Generator&, f: Fn&, target: BindingRef, ty: Ty, id: u32) -> Val, Error {
    let key = InstanceKey { blot_direct_emit::InstanceKind.pool, target.unit, target.binding, ty, 0, 0 };
    var instance, present = g.find(key);
    if !present {
        let created, error = g.addInstanceWith(key, Env {}, Tys {}, ty, false, Tys {}, g.units[f.unit - 1], id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        let at = g.s.pool_words.len as u32;
        let first = g.module.addGlobal(VT_i32, true, 0);
        let second = g.module.addGlobal(VT_i32, true, 0);
        let third = g.module.addGlobal(VT_i32, true, 0);
        g.s.pool_words.push(first);
        g.s.pool_words.push(second);
        g.s.pool_words.push(third);
        g.s.instances[created].pool_offset = at;
        g.s.pool_order.push(created);
        instance = created;
    }
    callf(g, g.s.instances[instance].function);
    return pop(g, f, ty, id);
}
// Emit a memoized helper `persist_rec(old_ptr: i32) -> new_ptr: i32` that copies a
// recursive nominal node into the persistent bump region and recursively persists
// all nested owners and recursive pointers, recording deeply-immutable boxes in `static_blocks`.
recursive fn ensurePersistRecHelper(g: Generator&, unit: u32, ty: Ty) -> u32, Error {
    let key = blot_direct_emit::key64(ty, 1);
    let existing, found = g.s.persist_rec_helpers.get(key);
    if found { return existing, blot_direct_types::Error.none; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32], [VT_i32]));
    g.s.persist_rec_helpers.put(key, fn_id);
    let s .= g.s;
    let code_mark = s.code.len;
    let sites_mark = blot_direct_relocations::mark();
    let locals_mark = s.locals.len;
    let labels_mark = s.labels.len;
    let handles_mark = s.handles.len;
    let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, unit, 0);
    let old_ptr = local(g, nf, VT_i32);
    nf.parameter_words = 1;
    let bbytes, berr = blockBytes(g, nf, ty, 0);
    if berr != blot_direct_types::Error.none {
        blot_direct_relocations::rewind(sites_mark);
        s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
        return 0, berr;
    }
    let rt = g.runtime_();
    let new_ptr = local32(g, nf);
    lget(g, old_ptr);
    op(g, OP_i32_eqz);
    let z_if = open(g, nf, OP_if_);
    i32Const(g, 0);
    op(g, OP_return_);
    close(g, nf);
    i32Const(g, bbytes);
    callf(g, rt.alloc_persistent);
    lset(g, new_ptr);
    memoryCopy(g, new_ptr, 0, old_ptr, bbytes);
    if rt.has_persistent_state {
        lget(g, new_ptr);
        i32Const(g, bbytes);
        i32Const(g, ty);
        callf(g, rt.record_static_block);
    }
    let cases, cerr = g.types.variants(ty);
    if cerr != blot_direct_types::Error.none {
        blot_direct_relocations::rewind(sites_mark);
        s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
        return 0, cerr;
    }
    if cases.len == 1 {
        let perr = persistFlatAt(g, nf, new_ptr, 0, g.types.variant_payloads[cases.payloads], 0, 0);
        if perr != blot_direct_types::Error.none {
            blot_direct_relocations::rewind(sites_mark);
            s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
            return 0, perr;
        }
    } else if cases.len > 1 {
        let tag_loc = local32(g, nf);
        lget(g, new_ptr);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, 0);
        lset(g, tag_loc);
        for ci in 0..(cases.len as i64) {
            let pty = g.types.variant_payloads[cases.payloads + ci];
            let pholds, herr = g.contentsHoldMemory(pty);
            if herr != blot_direct_types::Error.none {
                blot_direct_relocations::rewind(sites_mark);
                s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                return 0, herr;
            }
            if !pholds { continue; }
            lget(g, tag_loc);
            i32Const(g, g.types.variant_tags[cases.tags + ci]);
            op(g, OP_i32_eq);
            let cif = open(g, nf, OP_if_);
            let perr = persistFlatAt(g, nf, new_ptr, 4, pty, 0, 0);
            if perr != blot_direct_types::Error.none {
                blot_direct_relocations::rewind(sites_mark);
                s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
                return 0, perr;
            }
            close(g, nf);
        }
    }
    lget(g, new_ptr);
    op(g, OP_end);
    finishWith(g, fn_id, nf, false, 0, 0, 0);
    blot_direct_relocations::rewind(sites_mark);
    s.code.resize(code_mark);
    s.locals.resize(locals_mark);
    s.labels.resize(labels_mark);
    s.handles.resize(handles_mark);
    s.handle_cells_len = handle_cells_mark;
    return fn_id, blot_direct_types::Error.none;
}

// Recursively persists nested owned arrays and recursive boxes stored flat at `base + offset`.
// All module const pools are deeply immutable, so nested pools always use mode = 2 (static_pool_flag | live_flag).
recursive fn persistFlatAt(g: Generator&, f: Fn&, base: u32, offset: u32, ty: Ty, id: u32, depth: i64) -> Error {
    if depth > 32 { return blot_direct_types::Error.none; }
    let holds, herr = g.contentsHoldMemory(ty);
    if herr != blot_direct_types::Error.none { return herr; }
    if !holds { return blot_direct_types::Error.none; }
    let is_rec, rerr = g.types.isRecursive(ty);
    if rerr != blot_direct_types::Error.none { return rerr; }
    if is_rec {
        let helper_fn, aerr = ensurePersistRecHelper(g, f.unit, ty);
        if aerr != blot_direct_types::Error.none { return aerr; }
        let old_p = local32(g, f);
        lget(g, base);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, offset);
        lset(g, old_p);
        lget(g, base);
        lget(g, old_p);
        callf(g, helper_fn);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, offset);
        return blot_direct_types::Error.none;
    }
    let n = g.types.node(ty);
    match n.tag {
        array => {
            let c_slot = local32(g, f);
            let c_gen = local32(g, f);
            let p_slot = local32(g, f);
            let p_gen = local32(g, f);
            lget(g, base);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, offset);
            lset(g, c_slot);
            lget(g, base);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, offset + 4);
            lset(g, c_gen);
            let elem_ty = n.a;
            let elem_step, serr = stride(g, f, elem_ty, id);
            if serr != blot_direct_types::Error.none { return serr; }
            lget(g, c_slot);
            lget(g, c_gen);
            i32Const(g, elem_step);
            i32Const(g, 2);
            callf(g, g.runtime_().persist);
            lset(g, p_gen);
            lset(g, p_slot);
            lget(g, base);
            lget(g, p_slot);
            op(g, OP_i32_store); uleb(g, 2); uleb(g, offset);
            lget(g, base);
            lget(g, p_gen);
            op(g, OP_i32_store); uleb(g, 2); uleb(g, offset + 4);
            let elem_holds, eherr = g.contentsHoldMemory(elem_ty);
            if eherr != blot_direct_types::Error.none { return eherr; }
            if elem_holds {
                let perr = persistArrayElements(g, f, p_slot, p_gen, elem_ty, elem_step, id, depth + 1);
                if perr != blot_direct_types::Error.none { return perr; }
            }
            return blot_direct_types::Error.none;
        },
        ref, link, view => {
            let c_slot = local32(g, f);
            let c_gen = local32(g, f);
            lget(g, base);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, offset);
            lset(g, c_slot);
            lget(g, c_slot);
            i32Const(g, g.runtime_().layout.persistent_split);
            op(g, OP_i32_lt_u);
            let _ = open(g, f, OP_if_);
            lget(g, base);
            op(g, OP_i32_load); uleb(g, 2); uleb(g, offset + 4);
            lset(g, c_gen);
            let elem_ty = n.a;
            let elem_step, serr = stride(g, f, elem_ty, id);
            if serr != blot_direct_types::Error.none { return serr; }
            let p_slot = local32(g, f);
            let p_gen = local32(g, f);
            lget(g, c_slot);
            lget(g, c_gen);
            i32Const(g, elem_step);
            i32Const(g, 2);
            callf(g, g.runtime_().persist);
            lset(g, p_gen);
            lset(g, p_slot);
            lget(g, base);
            lget(g, p_slot);
            op(g, OP_i32_store); uleb(g, 2); uleb(g, offset);
            lget(g, base);
            lget(g, p_gen);
            op(g, OP_i32_store); uleb(g, 2); uleb(g, offset + 4);
            let elem_holds, eherr = g.contentsHoldMemory(elem_ty);
            if eherr != blot_direct_types::Error.none { return eherr; }
            if elem_holds {
                let perr = persistArrayElements(g, f, p_slot, p_gen, elem_ty, elem_step, id, depth + 1);
                if perr != blot_direct_types::Error.none { return perr; }
            }
            close(g, f);
            return blot_direct_types::Error.none;
        },
        tuple => {
            var off = offset;
            for at in 0..(n.b as i64) {
                let item_ty = g.types.words[n.a + at];
                let perr = persistFlatAt(g, f, base, off, item_ty, id, depth + 1);
                if perr != blot_direct_types::Error.none { return perr; }
                let fb, ferr = flatBytes(g, f, item_ty, id);
                if ferr != blot_direct_types::Error.none { return ferr; }
                off += fb;
            }
            return blot_direct_types::Error.none;
        },
        record => {
            var off = offset;
            for idx in 0..(n.b as i64) {
                let field_ty = g.types.recordField(ty, idx).ty;
                let perr = persistFlatAt(g, f, base, off, field_ty, id, depth + 1);
                if perr != blot_direct_types::Error.none { return perr; }
                let fb, ferr = flatBytes(g, f, field_ty, id);
                if ferr != blot_direct_types::Error.none { return ferr; }
                off += fb;
            }
            return blot_direct_types::Error.none;
        },
        nominal => {
            let cases, cerr = g.types.variants(ty);
            if cerr != blot_direct_types::Error.none { return cerr; }
            if cases.len == 1 {
                return persistFlatAt(g, f, base, offset, g.types.variant_payloads[cases.payloads], id, depth + 1);
            }
            if cases.len > 1 {
                let tag_loc = local32(g, f);
                lget(g, base);
                op(g, OP_i32_load); uleb(g, 2); uleb(g, offset);
                lset(g, tag_loc);
                for ci in 0..(cases.len as i64) {
                    let pty = g.types.variant_payloads[cases.payloads + ci];
                    let pholds, pherr = g.contentsHoldMemory(pty);
                    if pherr != blot_direct_types::Error.none { return pherr; }
                    if !pholds { continue; }
                    lget(g, tag_loc);
                    i32Const(g, g.types.variant_tags[cases.tags + ci]);
                    op(g, OP_i32_eq);
                    let cif = open(g, f, OP_if_);
                    let perr = persistFlatAt(g, f, base, offset + 4, pty, id, depth + 1);
                    if perr != blot_direct_types::Error.none { return perr; }
                    close(g, f);
                }
            }
            return blot_direct_types::Error.none;
        },
        _ => { return blot_direct_types::Error.none; },
    }
}

recursive fn persistArrayElements(g: Generator&, f: Fn&, p_slot: u32, p_gen: u32, elem_ty: Ty, elem_step: u32, id: u32, depth: i64) -> Error {
    let rt = g.runtime_();
    let entry = local32(g, f);
    let arr_base = local32(g, f);
    let arr_len = local32(g, f);
    let idx = local32(g, f);
    let elem_addr = local32(g, f);
    lget(g, p_slot);
    lget(g, p_gen);
    callf(g, rt.check);
    ltee(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
    lset(g, arr_base);
    lget(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
    lset(g, arr_len);
    i32Const(g, 0);
    lset(g, idx);
    let exit = open(g, f, OP_block);
    let top = open(g, f, OP_loop);
    lget(g, idx);
    lget(g, arr_len);
    op(g, OP_i32_ge_u);
    br(g, f, OP_br_if, exit);
    lget(g, arr_base);
    lget(g, idx);
    i32Const(g, elem_step);
    op(g, OP_i32_mul);
    op(g, OP_i32_add);
    lset(g, elem_addr);
    let perr = persistFlatAt(g, f, elem_addr, 0, elem_ty, id, depth);
    if perr != blot_direct_types::Error.none { return perr; }
    lget(g, idx);
    i32Const(g, 1);
    op(g, OP_i32_add);
    lset(g, idx);
    br(g, f, OP_br, top);
    close(g, f);
    close(g, f);
    return blot_direct_types::Error.none;
}

recursive fn poolBody(g: Generator&, f: Fn&, instance_id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let at = g.s.instances[f.instance_id].pool_offset;
    assert(at != 0xffffffff);
    let slot_global = g.s.pool_words[at];
    let generation_global = g.s.pool_words[at + 1];
    let state_global = g.s.pool_words[at + 2];
    let rt = g.runtime_();
    let persist = rt.persist;
    let key = g.s.instances[instance_id].key;
    gget(g, state_global);
    i32Const(g, 1);
    op(g, OP_i32_ne);
    let opened = open(g, f, OP_if_);
    // Initialization cycles trap.
    gget(g, state_global);
    i32Const(g, 2);
    op(g, OP_i32_eq);
    trap(g, f);
    i32Const(g, 2);
    gset(g, state_global);
    let owner_mark = local32(g, f);
    let stack_mark = local32(g, f);
    markInto(g, g.s.code, owner_mark, stack_mark);
    let value_instance, error = g.named(BindingRef { key.unit, key.id }, key.ty, m, 0);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    callf(g, g.s.instances[value_instance].function);
    let value, error = pop(g, f, key.ty, 0);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    lget(g, w(g, value, 0));
    lget(g, w(g, value, 1));
    let element, error = elementOf(g, f, key.ty, 0);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let step, error = stride(g, f, element, 0);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    i32Const(g, step);
    // All module const pools are deeply immutable: always emit mode = 2 (static_pool_flag | live_flag).
    i32Const(g, 2);
    callf(g, persist);
    let p_slot = local32(g, f);
    let p_gen = local32(g, f);
    lset(g, p_gen);
    lset(g, p_slot);
    let elem_holds, eherr = g.contentsHoldMemory(element);
    if eherr != blot_direct_types::Error.none { return neverVal(), eherr; }
    if elem_holds {
        let perr = persistArrayElements(g, f, p_slot, p_gen, element, step, 0, 0);
        if perr != blot_direct_types::Error.none { return neverVal(), perr; }
    }
    lget(g, p_slot);
    gset(g, slot_global);
    lget(g, p_gen);
    gset(g, generation_global);
    releaseTo(g, owner_mark, stack_mark);
    i32Const(g, 0xffffffff);
    gset(g, rt.escape_min_slot);
    i32Const(g, 1);
    gset(g, state_global);
    close(g, f);
    let result, error = fresh(g, f, key.ty, 0);
    if error != blot_direct_types::Error.none { return result, error; }
    gget(g, slot_global);
    lset(g, w(g, result, 0));
    gget(g, generation_global);
    lset(g, w(g, result, 1));
    return result, blot_direct_types::Error.none;
}

recursive fn call(g: Generator&, f: Fn&, id: u32, elide_nan: bool = false) -> Val, Error {
    let previous_call = f.current_call;
    f.current_call = id;
    let value, error = callInner(g, f, id, elide_nan);
    f.current_call = previous_call;
    return value, error;
}
recursive fn callInner(g: Generator&, f: Fn&, id: u32, elide_nan: bool = false) -> Val, Error {
    let tail_here = f.tail_call_node == id;
    f.tail_call_node = 0;
    let m .= g.units[f.unit - 1];
    let info = m.call(id);
    let target = g.resolve(m, info.target);
    let arguments = info.arguments;
    // Fast path: intercept 2-arg forwarding wrappers around `@array.generate`
    // (such as `std/array.generate`) when given a direct closure literal so we
    // never construct a closure or emit per-element `call_indirect`.
    var gen_wrap = false;
    var gen_arg0: u32 = 0;
    var gen_arg1: u32 = 0;
    var gen_out_ty: Ty = 0;
    var gen_resolved = BindingRef { 0, 0 };
    if arguments.len == 2 && m.node(arguments[1]).tag == blot_check_core::Tag.closure && g.hasUnit(target.unit) {
        let resolved_g = followAliasTarget(g, target);
        if g.hasUnit(resolved_g.unit) {
            let tm .= g.units[resolved_g.unit - 1];
            let tbody .= tm.body(resolved_g.binding);
            if tbody && tbody.is_function {
                let tparams = tm.bodyParameters(tbody);
                if tparams.len == 2 {
                    let inner = unwrapSingleBody(tm, tbody.root);
                    if inner != 0 && tm.node(inner).tag == blot_check_core::Tag.array_op && tm.arrayOperation(inner) == blot_backend_collection_ops::Op.generate {
                        let ch = tm.children(inner);
                        if ch.len == 2 && localRef(tm, ch[0]) == tparams[0].binding && localRef(tm, ch[1]) == tparams[1].binding {
                            let out_ty, ok_out = lowerInEnv(g, m, m.typeOf(id), f.env);
                            if ok_out && tagOf(g, out_ty) == blot_direct_types::Tag.array {
                                gen_wrap = true;
                                gen_arg0 = arguments[0];
                                gen_arg1 = arguments[1];
                                gen_out_ty = out_ty;
                                gen_resolved = resolved_g;
                            }
                        }
                    }
                }
            }
        }
    }
    if gen_wrap {
        let counted, cerr = expr(g, f, gen_arg0);
        if cerr != blot_direct_types::Error.none { return counted, cerr; }
        let count_loc, clerr = scalarLocal(g, f, counted, id);
        if clerr != blot_direct_types::Error.none { return neverVal(), clerr; }
        let inlined, did_inline, ierr = tryEmitGenerateInlineClosure(g, f, count_loc, gen_arg1, gen_out_ty, id);
        if ierr != blot_direct_types::Error.none { return inlined, ierr; }
        if did_inline {
            g.recordInlined(gen_resolved.unit, gen_resolved.binding);
            return inlined, blot_direct_types::Error.none;
        }
        // Fallback: count already evaluated; build closure and run generate.
        let src_val, serr = expr(g, f, gen_arg1);
        if serr != blot_direct_types::Error.none { return src_val, serr; }
        g.recordInlined(gen_resolved.unit, gen_resolved.binding);
        return emitFillOrGenerate(g, f, false, count_loc, src_val, gen_out_ty, id);
    }
    var elide_args = false;
    if arguments.len >= 1 && arguments.len <= 2 && g.hasUnit(target.unit) {
        let resolved_prim = followAliasTarget(g, target);
        if g.hasUnit(resolved_prim.unit) {
            let rtm .= g.units[resolved_prim.unit - 1];
            let palias, has_palias = primitiveAlias(rtm, resolved_prim.binding);
            if has_palias {
                let pinfo = rtm.primitive(palias);
                if pinfo.kind == blot_check_core::PrimitiveKind.scalar && (pinfo.arity as i64) == arguments.len && isCanonicalF32Consumer(pinfo.op) && isF32CoreExpr(g, f, m, arguments[0]) {
                    elide_args = true;
                }
            }
        }
    }
    let values = g.reserveVals(arguments.len);
    // Building a function value has no effects, so one whose type the other
    // arguments still determine is built after them.
    var deferred = false;
    for argument, at in arguments {
        if pureFunctionValue(g, f, argument) && !lowers(g, f, m.typeOf(argument)) {
            deferred = true;
            g.s.vals[values.start + at] = neverVal();
            continue;
        }
        if elide_args { f.elide_f32_nan_node = argument; }
        let value, error = expr(g, f, argument);
        f.elide_f32_nan_node = 0;
        if error != blot_direct_types::Error.none { return value, error; }
        g.s.vals[values.start + at] = value;
    }
    if deferred {
        for argument, index in arguments {
            if g.s.vals[values.start + index].ty != blot_direct_types::never { continue; }
            // Still unknown: take the type the callee expects from the
            // arguments known so far, with holes for what they leave open.
            if !lowers(g, f, m.typeOf(argument)) {
                let expected, has_expected, error = expectedArgument(g, f, target, values, index);
                if error != blot_direct_types::Error.none { return neverVal(), error; }
                if has_expected { refine(g, f, m.typeOf(argument), expected); }
            }
            let value, error = expr(g, f, argument);
            if error != blot_direct_types::Error.none { return value, error; }
            g.s.vals[values.start + index] = value;
        }
    }
    // Intercept 1-argument std/ `@flat.encode` / `@flat.decode` / `@flat.schema_hash`
    // forwarding helpers at the call site so caller-side concrete Core types (including
    // `#[K; E]` length literals and nominal identities) are preserved through generics.
    if arguments.len == 1 && !deferred && g.hasUnit(target.unit) {
        let resolved_f = followAliasTarget(g, target);
        if g.hasUnit(resolved_f.unit) {
            let tm .= g.units[resolved_f.unit - 1];
            let tbody .= tm.body(resolved_f.binding);
            if tbody && tbody.is_function {
                let tparams = tm.bodyParameters(tbody);
                if tparams.len == 1 {
                    let inner = unwrapSingleBody(tm, tbody.root);
                    if inner != 0 && tm.node(inner).tag == blot_check_core::Tag.flat_op {
                        let fn_node = tm.node(inner);
                        if localRef(tm, fn_node.a) == tparams[0].binding {
                            let arg_ct = m.typeOf(arguments[0]);
                            let res_ct = m.typeOf(id);
                            if fn_node.c == blot_check_core::flat_op_encode && m.types.node(arg_ct).tag != blot_check_types::Tag.variable {
                                let out_ty, ty_err = typeOf(g, f, id);
                                if ty_err != blot_direct_types::Error.none { return neverVal(), ty_err; }
                                g.recordInlined(resolved_f.unit, resolved_f.binding);
                                return emitFlatEncodeVal(g, f, g.s.vals[values.start], arg_ct, out_ty, id);
                            }
                            if fn_node.c == blot_check_core::flat_op_decode && m.types.node(res_ct).tag == blot_check_types::Tag.nominal {
                                let maybe_ty, ty_err = typeOf(g, f, id);
                                if ty_err != blot_direct_types::Error.none { return neverVal(), ty_err; }
                                g.recordInlined(resolved_f.unit, resolved_f.binding);
                                return emitFlatDecodeVal(g, f, g.s.vals[values.start], res_ct, maybe_ty, id);
                            }
                            if fn_node.c == blot_check_core::flat_op_schema_hash && m.types.node(arg_ct).tag != blot_check_types::Tag.variable {
                                let out_ty, ty_err = typeOf(g, f, id);
                                if ty_err != blot_direct_types::Error.none { return neverVal(), ty_err; }
                                let h, ok = blot_check_wire_schema::computeSchemaHash(g.units, f.unit, arg_ct);
                                if !ok {
                                    return neverVal(), g.failCode(m, id, blot_check_diagnostic_code::Code.kernel_type, "@flat.schema_hash requires a closed FlatNumeric, Unit, #[U32], or #[F32] type");
                                }
                                g.recordInlined(resolved_f.unit, resolved_f.binding);
                                let lo = constLocal(g, f, (h & 0xffffffff) as u32);
                                let hi = constLocal(g, f, (h >> 32) as u32);
                                let words = g.saveWords([lo, hi]);
                                return Val { out_ty, words.start, words.len }, blot_direct_types::Error.none;
                            }
                        }
                    }
                }
            }
        }
    }
    var callee, error = g.types.lower(m, info.callee_type, f.env);
    if error != blot_direct_types::Error.none {
        let derived, error = calleeOf(g, f, target, values, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        callee = derived;
    }
    refine(g, f, info.callee_type, callee);
    let rest, error = restType(g, f, callee, values.len, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    if tail_here { f.tail_call_node = id; }
    let res_v, res_err = callTarget(g, f, target, values, callee, rest, id, elide_nan);
    f.tail_call_node = 0;
    return res_v, res_err;
}
// Parameter `index` of `target` as fixed by the evaluated `values` (entries
// typed never are not yet evaluated), with holes.
fn expectedArgument(g: Generator&, f: Fn&, target: BindingRef, values: Vals, index: i64) -> Ty, bool, Error {
    let tm .= g.units[target.unit - 1];
    var env = Env {};
    var arrow = tm.binding(target.binding).ty;
    var has_parameter = false;
    var parameter: TId = 0;
    for at in 0..(values.len as i64) {
        let value = g.s.vals[values.start + at];
        var n = tm.types.node(arrow);
        while n.tag == blot_check_types::Tag.forall || n.tag == blot_check_types::Tag.usage {
            arrow = n.a;
            n = tm.types.node(arrow);
        }
        if n.tag != blot_check_types::Tag.function { return 0, false, blot_direct_types::Error.none; }
        if at == index { has_parameter = true; parameter = n.a; }
        else if value.ty != blot_direct_types::never { g.types.match_(tm, n.a, value.ty, env); }
        arrow = n.b;
    }
    let body .= tm.body(target.binding);
    if body {
        let solved = g.solveObligationsPublic(tm, body.scheme.obligations, env);
        if solved != blot_direct_types::Error.none { return 0, false, solved; }
    }
    if !has_parameter { return 0, false, blot_direct_types::Error.none; }
    let expected, error = g.types.lowerHoles(tm, parameter, env);
    if error != blot_direct_types::Error.none { return 0, false, error; }
    if tagOf(g, expected) != blot_direct_types::Tag.never { return expected, true, blot_direct_types::Error.none; }
    // The parameter is a bare variable: its field constraints and the
    // argument's own nominal type give the argument's type arguments.
    if !body { return 0, false, blot_direct_types::Error.none; }
    return fromFieldConstraints(g, f, tm, body.scheme.obligations, parameter, env, index);
}
// The nominal type of argument `index` of the current call, with its type
// arguments taken from the callee's field constraints on it.
fn fromFieldConstraints(g: Generator&, f: Fn&, tm: const Module&, goals_span: blot_check_types::List, formal: TId, env: Env, index: i64) -> Ty, bool, Error {
    let m .= g.units[f.unit - 1];
    let info = m.call(f.current_call);
    let argument_type = m.typeOf(info.arguments[index]);
    let shape = m.types.node(argument_type);
    if shape.tag != blot_check_types::Tag.nominal { return 0, false, blot_direct_types::Error.none; }
    let identity = blot_check_types::NominalIdentity { shape.a, shape.b };
    if !g.hasUnit(identity.unit) { return 0, false, blot_direct_types::Error.none; }
    let owner .= g.units[identity.unit - 1];
    let ordinal, error = g.types.nominalOrdinal(owner, identity);
    if error != blot_direct_types::Error.none { return 0, false, blot_direct_types::Error.none; }
    let constructors = owner.nominalConstructors(ordinal);
    if constructors.len != 1 { return 0, false, blot_direct_types::Error.none; }
    let constructor = owner.constructor(constructors[0]);
    let payload = owner.types.node(constructor.payload);
    if payload.tag != blot_check_types::Tag.record { return 0, false, blot_direct_types::Error.none; }
    var params_env = Env {};
    for at in 0..(goals_span.len as i64) {
        let goal = tm.obligations[goals_span.start + at];
        if (goal.kind != blot_check_types::ObligationKind.field && goal.kind != blot_check_types::ObligationKind.writable_field) || goal.ty != formal || goal.result == 0 { continue; }
        let spelling = tm.fieldSpelling(goal.name);
        if !spelling.present { continue; }
        let wanted, error = g.types.lowerHoles(tm, goal.result, env);
        if error != blot_direct_types::Error.none { return 0, false, error; }
        for field_index in 0..(payload.b as i64) {
            let field = owner.types.recordField(payload, field_index);
            let name = owner.fieldSpelling(field.name);
            if !name.present { continue; }
            if name.value == spelling.value { g.types.match_(owner, field.ty, wanted, params_env); }
        }
    }
    // The payload's fields bind the constructor's scheme variables.
    let signature = owner.types.node(constructor.scheme.root);
    var result = constructor.scheme.root;
    if signature.tag == blot_check_types::Tag.function { result = signature.b; }
    let lowered, error = g.types.lowerHoles(owner, result, params_env);
    if error != blot_direct_types::Error.none { return 0, false, error; }
    return lowered, true, blot_direct_types::Error.none;
}
// `acc := @list.append acc x` (a comprehension's accumulator) where the old
// `acc` has no other use: grow the same owner in place, so the loop carries
// an owner created before it instead of a fresh one.
recursive fn linearAppend(g: Generator&, f: Fn&, id: u32) -> Val, bool, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    if n.tag != blot_check_core::Tag.array_op || m.arrayOperation(id) != blot_backend_collection_ops::Op.append { return neverVal(), false, blot_direct_types::Error.none; }
    let children = m.children(id);
    if children.len != 2 || m.node(children[0]).tag != blot_check_core::Tag.reference { return neverVal(), false, blot_direct_types::Error.none; }
    let ref = m.reference(children[0]);
    if ref.unit != 0 && ref.unit != m.unit { return neverVal(), false, blot_direct_types::Error.none; }
    let list, present = bindGet(g, f, ref.binding);
    if !present { return neverVal(), false, blot_direct_types::Error.none; }
    if tagOf(g, list.ty) != blot_direct_types::Tag.array { return neverVal(), false, blot_direct_types::Error.none; }
    if uses(g, f, ref.binding) != 1 || !isUniqueOwned(g, f, ref.binding) || bindingCaptured(g, f, ref.binding) { return neverVal(), false, blot_direct_types::Error.none; }
    let value, error = expr(g, f, children[1]);
    if error != blot_direct_types::Error.none { return value, false, error; }
    let push_function = g.runtime_().push;
    let address = local32(g, f);
    lget(g, w(g, list, 0));
    lget(g, w(g, list, 1));
    let element, error = elementOf(g, f, list.ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), false, error; }
    let step, error = stride(g, f, element, id);
    if error != blot_direct_types::Error.none { return neverVal(), false, error; }
    i32Const(g, step);
    callf(g, push_function);
    lset(g, address);
    let noted = noteStoreToSlot(g, f, w(g, list, 0), value);
    if noted != blot_direct_types::Error.none { return neverVal(), false, noted; }
    if g.runtime_().has_fork {
        recordBeforeWrite(g, f, w(g, list, 0), address, 0, step);
    }
    let written = writeElement(g, f, address, 0, value, id);
    if written != blot_direct_types::Error.none { return neverVal(), false, written; }
    invalidateCheckedOwner(g, f, list);
    return list, true, blot_direct_types::Error.none;
}
// The value a closure captures for `binding`. Deferred polymorphic local
// closures (`Tag.closure`) are NOT monomorphized at the enclosing closure's
// creation site: we pack only their own concrete captures and forward the
// polymorphic entry into the child lambda so every use inside the child (or a
// nested polymorphic closure inside it) instantiates at its exact concrete type.
recursive fn captureValue(g: Generator&, f: Fn&, binding: u32, id: u32) -> Val, Error {
    return captureValueInner(g, f, binding, id, 0);
}
recursive fn captureValueInner(g: Generator&, f: Fn&, binding: u32, id: u32, depth: i64) -> Val, Error {
    if depth >= 32 { return neverVal(), g.fail(g.units[f.unit - 1], id, "polymorphic capture nesting limit"); }
    let m .= g.units[f.unit - 1];
    let bound, present = bindGet(g, f, binding);
    if present { return bound, blot_direct_types::Error.none; }
    let initializer, generalized = g.s.polymorphic.get(polyKey(f, binding));
    if !generalized { return neverVal(), g.fail(m, id, "closure capture without a value"); }
    if m.node(initializer).tag == blot_check_core::Tag.closure {
        return packPolyCaptures(g, f, initializer, id, depth + 1);
    }
    var chosen: Ty = 0;
    var has_chosen = false;
    var saw_open = false;
    if m.node(id).tag == blot_check_core::Tag.closure {
        let scan_err = usesTypeIn(g, f, m.closure(id).body, binding, initializer, chosen, has_chosen, saw_open, 0);
        if scan_err != blot_direct_types::Error.none { return neverVal(), scan_err; }
    }
    if !has_chosen && !saw_open {
        let fallback_ty, found, fb_err = usesType(g, f, binding, initializer, 0);
        if fb_err != blot_direct_types::Error.none { return neverVal(), fb_err; }
        if found { chosen = fallback_ty; has_chosen = true; }
    }
    var env = f.env;
    if has_chosen { g.types.match_(m, m.typeOf(initializer), chosen, env); }
    let previous = f.env;
    f.env = env;
    let value, error = expr(g, f, initializer);
    f.env = previous;
    return value, error;
}
recursive fn packPolyCaptures(g: Generator&, f: Fn&, initializer: u32, id: u32, depth: i64) -> Val, Error {
    if depth >= 32 { return neverVal(), g.fail(g.units[f.unit - 1], id, "polymorphic capture nesting limit"); }
    let m .= g.units[f.unit - 1];
    let inner_caps = m.closureCaptures(initializer);
    if inner_caps.len == 0 { return unitVal(), blot_direct_types::Error.none; }
    if inner_caps.len == 1 { return captureValueInner(g, f, inner_caps[0], initializer, depth + 1); }
    let values = g.reserveVals(inner_caps.len);
    for cap, at in inner_caps {
        let v, err = captureValueInner(g, f, cap, initializer, depth + 1);
        if err != blot_direct_types::Error.none { return neverVal(), err; }
        g.s.vals[values.start + at] = v;
    }
    var items: Ty[>..] = [];
    for at in 0..(values.len as i64) { items.push(g.s.vals[values.start + at].ty); }
    let tup_ty, terr = g.types.tuple(items[..]);
    if terr != blot_direct_types::Error.none { return neverVal(), terr; }
    let boxed, berr = isBoxed(g, f, tup_ty, id);
    if berr != blot_direct_types::Error.none { return neverVal(), berr; }
    if boxed {
        let memory_block, merr = newBlock(g, f, tup_ty, id);
        if merr != blot_direct_types::Error.none { return neverVal(), merr; }
        for index in 0..(values.len as i64) {
            let offset, oerr = itemOffset(g, f, tup_ty, index, id);
            if oerr != blot_direct_types::Error.none { return neverVal(), oerr; }
            let werr = writeFlat(g, f, memory_block, offset, g.s.vals[values.start + index], id);
            if werr != blot_direct_types::Error.none { return neverVal(), werr; }
        }
        return valOf1(g, tup_ty, memory_block), blot_direct_types::Error.none;
    }
    let s .= g.s;
    let mark = s.scratch.len;
    for index in 0..(values.len as i64) {
        let value = g.s.vals[values.start + index];
        for at in 0..(value.len as i64) { s.scratch.push(g.s.words[value.start + at]); }
    }
    let start = g.s.words.len as u32;
    let words_count = (s.scratch.len - mark) as u32;
    for at in mark..s.scratch.len { let word = s.scratch[at]; g.s.words.push(word); }
    s.scratch.resize(mark);
    return Val { tup_ty, start, words_count }, blot_direct_types::Error.none;
}
fn polyCaptureKey(instance_id: u32, binding: u32) -> u64 {
    return blot_direct_emit::key64(0x80000000 | instance_id, binding);
}
recursive fn recordPolyCapture(g: Generator&, f: const Fn&, target_instance: u32, binding: u32, init_node: u32, depth: i64) {
    if depth >= 32 { return; }
    let m .= g.units[f.unit - 1];
    g.s.polymorphic.put(polyCaptureKey(target_instance, binding), init_node);
    if m.node(init_node).tag != blot_check_core::Tag.closure { return; }
    for c in m.closureCaptures(init_node) {
        let _, bound_here = bindGet(g, f, c);
        if bound_here { continue; }
        let c_init, c_poly = g.s.polymorphic.get(polyKey(f, c));
        if c_poly && m.node(c_init).tag == blot_check_core::Tag.closure {
            recordPolyCapture(g, f, target_instance, c, c_init, depth + 1);
        }
    }
}
recursive fn restorePolyCapture(g: Generator&, f: Fn&, instance_id: u32, binding: u32, init_node: u32, cap_val: Val, depth: i64) -> Error {
    if depth >= 32 { return blot_direct_types::Error.none; }
    let m .= g.units[f.unit - 1];
    g.s.polymorphic.put(polyKey(f, binding), init_node);
    if m.node(init_node).tag != blot_check_core::Tag.closure { return blot_direct_types::Error.none; }
    let inner_caps = m.closureCaptures(init_node);
    if inner_caps.len == 0 { return blot_direct_types::Error.none; }
    if inner_caps.len == 1 {
        let c = inner_caps[0];
        let c_init, c_poly = g.s.polymorphic.get(polyCaptureKey(instance_id, c));
        if c_poly {
            return restorePolyCapture(g, f, instance_id, c, c_init, cap_val, depth + 1);
        }
        bindPut(g, f, c, cap_val);
        if tagOf(g, cap_val.ty) == blot_direct_types::Tag.cell {
            blot_support_zigmap::put(g.s.map_pool, f.with_cells, c, g.types.node(cap_val.ty).a);
        }
        return blot_direct_types::Error.none;
    }
    for c, idx in inner_caps {
        let item, err = tupleItem(g, f, cap_val, idx, init_node);
        if err != blot_direct_types::Error.none { return err; }
        let c_init, c_poly = g.s.polymorphic.get(polyCaptureKey(instance_id, c));
        if c_poly {
            let rerr = restorePolyCapture(g, f, instance_id, c, c_init, item, depth + 1);
            if rerr != blot_direct_types::Error.none { return rerr; }
        } else {
            bindPut(g, f, c, item);
            if tagOf(g, item.ty) == blot_direct_types::Tag.cell {
                blot_support_zigmap::put(g.s.map_pool, f.with_cells, c, g.types.node(item.ty).a);
            }
        }
    }
    return blot_direct_types::Error.none;
}
recursive fn usesTypeIn(g: Generator&, f: Fn&, id: u32, binding: u32, site: u32, chosen: Ty&, has_chosen: bool&, saw_open: bool&, depth: u32) -> Error {
    if id == 0 || depth >= 128 { return blot_direct_types::Error.none; }
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    match n.tag {
        reference => {
            let target = m.references[n.a];
            if (target.unit == 0 || target.unit == m.unit) && target.binding == binding {
                var ty, error = g.types.lower(m, m.typeOf(id), f.env);
                if error != blot_direct_types::Error.none {
                    let aliased, found, aerr = aliasType(g, f, id, site, 0);
                    if aerr != blot_direct_types::Error.none { return aerr; }
                    if !found { saw_open = true; return blot_direct_types::Error.none; }
                    ty = aliased;
                }
                if has_chosen {
                    if chosen != ty { return g.fail(m, site, "a local value is used at different types; give it an annotation"); }
                } else { has_chosen = true; chosen = ty; }
            }
            return blot_direct_types::Error.none;
        },
        comptime_if, if_value, if_stmt, state_provider => {
            let e1 = usesTypeIn(g, f, n.a, binding, site, chosen, has_chosen, saw_open, depth + 1);
            if e1 != blot_direct_types::Error.none { return e1; }
            let e2 = usesTypeIn(g, f, n.b, binding, site, chosen, has_chosen, saw_open, depth + 1);
            if e2 != blot_direct_types::Error.none { return e2; }
            return usesTypeIn(g, f, n.c, binding, site, chosen, has_chosen, saw_open, depth + 1);
        },
        suite, block_, product, record, array, array_op, storage => {
            for child in m.children(id) {
                let err = usesTypeIn(g, f, child, binding, site, chosen, has_chosen, saw_open, depth + 1);
                if err != blot_direct_types::Error.none { return err; }
            }
            return blot_direct_types::Error.none;
        },
        call, contract_method, break_ => {
            for child in m.extra[n.b..n.b + n.c] {
                let err = usesTypeIn(g, f, child, binding, site, chosen, has_chosen, saw_open, depth + 1);
                if err != blot_direct_types::Error.none { return err; }
            }
            return blot_direct_types::Error.none;
        },
        with_handle => {
            for child in m.extra[n.b..n.b + n.c] {
                let err = usesTypeIn(g, f, child, binding, site, chosen, has_chosen, saw_open, depth + 1);
                if err != blot_direct_types::Error.none { return err; }
            }
            return usesTypeIn(g, f, n.a, binding, site, chosen, has_chosen, saw_open, depth + 1);
        },
        bind, construct, comptime_for => {
            return usesTypeIn(g, f, n.b, binding, site, chosen, has_chosen, saw_open, depth + 1);
        },
        return_, project, result_associated, fork_ => {
            return usesTypeIn(g, f, n.a, binding, site, chosen, has_chosen, saw_open, depth + 1);
        },
        scalar, logical, apply, associated, type_same, effect_provider, handle, staging => {
            let e1 = usesTypeIn(g, f, n.a, binding, site, chosen, has_chosen, saw_open, depth + 1);
            if e1 != blot_direct_types::Error.none { return e1; }
            return usesTypeIn(g, f, n.b, binding, site, chosen, has_chosen, saw_open, depth + 1);
        },
        pattern_bind => {
            let e1 = usesTypeIn(g, f, n.b, binding, site, chosen, has_chosen, saw_open, depth + 1);
            if e1 != blot_direct_types::Error.none { return e1; }
            return usesTypeIn(g, f, n.c, binding, site, chosen, has_chosen, saw_open, depth + 1);
        },
        update => {
            let u = m.updateInfo(id);
            let e1 = usesTypeIn(g, f, u.root, binding, site, chosen, has_chosen, saw_open, depth + 1);
            if e1 != blot_direct_types::Error.none { return e1; }
            for step in m.updateSelectors(id) {
                let es = usesTypeIn(g, f, step.index, binding, site, chosen, has_chosen, saw_open, depth + 1);
                if es != blot_direct_types::Error.none { return es; }
            }
            return usesTypeIn(g, f, u.value, binding, site, chosen, has_chosen, saw_open, depth + 1);
        },
        loop_ => {
            let info = m.loopInfo(id);
            let e1 = usesTypeIn(g, f, info.first, binding, site, chosen, has_chosen, saw_open, depth + 1);
            if e1 != blot_direct_types::Error.none { return e1; }
            let e2 = usesTypeIn(g, f, info.end, binding, site, chosen, has_chosen, saw_open, depth + 1);
            if e2 != blot_direct_types::Error.none { return e2; }
            return usesTypeIn(g, f, info.body, binding, site, chosen, has_chosen, saw_open, depth + 1);
        },
        match_ => {
            for inp in m.matchInputs(id) {
                let ei = usesTypeIn(g, f, inp, binding, site, chosen, has_chosen, saw_open, depth + 1);
                if ei != blot_direct_types::Error.none { return ei; }
            }
            for arm in m.matchArms(id) {
                let eg = usesTypeIn(g, f, arm.guard_, binding, site, chosen, has_chosen, saw_open, depth + 1);
                if eg != blot_direct_types::Error.none { return eg; }
                let eb = usesTypeIn(g, f, arm.body, binding, site, chosen, has_chosen, saw_open, depth + 1);
                if eb != blot_direct_types::Error.none { return eb; }
            }
            return blot_direct_types::Error.none;
        },
        closure => {
            return usesTypeIn(g, f, m.closure(id).body, binding, site, chosen, has_chosen, saw_open, depth + 1);
        },
        comptime_meta => {
            if n.c == 0 { return usesTypeIn(g, f, n.a, binding, site, chosen, has_chosen, saw_open, depth + 1); }
            if n.c == 8 || n.c == 9 { return usesTypeIn(g, f, n.b, binding, site, chosen, has_chosen, saw_open, depth + 1); }
            return blot_direct_types::Error.none;
        },
        spark => {
            let info = m.sparkInfo(id);
            let e1 = usesTypeIn(g, f, info.source, binding, site, chosen, has_chosen, saw_open, depth + 1);
            if e1 != blot_direct_types::Error.none { return e1; }
            let e2 = usesTypeIn(g, f, info.end, binding, site, chosen, has_chosen, saw_open, depth + 1);
            if e2 != blot_direct_types::Error.none { return e2; }
            return usesTypeIn(g, f, info.body, binding, site, chosen, has_chosen, saw_open, depth + 1);
        },
        flat_op => {
            if n.c == blot_check_core::flat_op_encode || n.c == blot_check_core::flat_op_decode {
                return usesTypeIn(g, f, n.a, binding, site, chosen, has_chosen, saw_open, depth + 1);
            }
            return blot_direct_types::Error.none;
        },
        _ => { return blot_direct_types::Error.none; },
    }
}
// Binds the scheme variables of generalized local `binding` to the one
// concrete type its references in this unit give it. References at different
// types cannot share one computed value.
fn typeByUses(g: Generator&, f: Fn&, binding: u32, id: u32) -> Error {
    let ty, found, error = usesType(g, f, binding, id, 0);
    if error != blot_direct_types::Error.none { return error; }
    if found { refine(g, f, g.units[f.unit - 1].binding(binding).ty, ty); }
    return blot_direct_types::Error.none;
}
// The one concrete type the references to local `binding` agree on. A
// reference that is the whole value of another generalized local
// (`let c = b`) takes the type of that alias's uses.
fn ensureLocalRefs(g: Generator&, m: const Module&) -> u32 {
    let uid = (m.unit - 1) as i64;
    while g.s.local_refs_base.len < g.units.len { g.s.local_refs_base.push(0xffffffff); }
    var base = g.s.local_refs_base[uid];
    if base == 0xffffffff {
        base = g.s.local_refs_head.len as u32;
        g.s.local_refs_base[uid] = base;
        blot_direct_emit::growZerosU32(g.s.local_refs_head, m.bindings.len);
        var idx = m.nodes.len;
        while idx > 0 {
            idx -= 1;
            let node = m.nodes[idx];
            if node.tag != blot_check_core::Tag.reference { continue; }
            let target = m.references[node.a];
            if target.unit != 0 && target.unit != m.unit { continue; }
            let slot = (base as i64) + (target.binding as i64);
            let prev = g.s.local_refs_head[slot];
            let entry = (g.s.local_refs_node.len as u32) + 1;
            g.s.local_refs_node.push(idx as u32);
            g.s.local_refs_next.push(prev);
            g.s.local_refs_head[slot] = entry;
        }
    }
    return base;
}
recursive fn usesType(g: Generator&, f: Fn&, binding: u32, id: u32, depth: u32) -> Ty, bool, Error {
    let m .= g.units[f.unit - 1];
    let base = ensureLocalRefs(g, m);
    var has_chosen = false;
    var chosen: Ty = 0;
    var cur = g.s.local_refs_head[(base as i64) + (binding as i64)];
    while cur != 0 {
        let index = g.s.local_refs_node[(cur - 1) as i64];
        cur = g.s.local_refs_next[(cur - 1) as i64];
        var ty, error = g.types.lower(m, m.typeOf(index), f.env);
        if error != blot_direct_types::Error.none {
            let aliased, found, error = aliasType(g, f, index, id, depth);
            if error != blot_direct_types::Error.none { return 0, false, error; }
            if !found { continue; }
            ty = aliased;
        }
        if has_chosen {
            if chosen != ty { return 0, false, g.fail(m, id, "a local value is used at different types; give it an annotation"); }
        } else { has_chosen = true; chosen = ty; }
    }
    return chosen, has_chosen, blot_direct_types::Error.none;
}
recursive fn aliasType(g: Generator&, f: Fn&, use: u32, id: u32, depth: u32) -> Ty, bool, Error {
    if depth >= 8 { return 0, false, blot_direct_types::Error.none; }
    let m .= g.units[f.unit - 1];
    for index in 0..m.nodes.len {
        let node = m.nodes[index];
        if node.tag != blot_check_core::Tag.bind || node.b != use { continue; }
        if m.binding(node.a).scheme.variables.len == 0 { return 0, false, blot_direct_types::Error.none; }
        return usesType(g, f, node.a, id, depth + 1);
    }
    return 0, false, blot_direct_types::Error.none;
}
// Whether Core subtree `id` reads local `binding` (directly, via branch merge,
// loop carry, or closure capture). Conservative on excessive depth.
recursive fn nodeReadsBinding(m: const Module&, id: u32, binding: u32, depth: i64) -> bool {
    if id == 0 || binding == 0 { return false; }
    if depth > 64 { return true; }
    let n = m.node(id);
    match n.tag {
        constant, panic => { return false; },
        reference => { return localRef(m, id) == binding; },
        suite, block_, product, record, array, array_op, storage, break_ => {
            for child in m.children(id) {
                if nodeReadsBinding(m, child, binding, depth + 1) { return true; }
            }
            return false;
        },
        bind => { return nodeReadsBinding(m, n.b, binding, depth + 1); },
        pattern_bind => {
            return nodeReadsBinding(m, n.b, binding, depth + 1) || nodeReadsBinding(m, n.c, binding, depth + 1);
        },
        if_stmt, if_value => {
            if nodeReadsBinding(m, n.a, binding, depth + 1) ||
                nodeReadsBinding(m, n.b, binding, depth + 1) ||
                nodeReadsBinding(m, n.c, binding, depth + 1) { return true; }
            for merge in m.branchMerges(id) {
                if merge.then_binding == binding || merge.else_binding == binding { return true; }
            }
            return false;
        },
        match_ => {
            for inp in m.matchInputs(id) {
                if nodeReadsBinding(m, inp, binding, depth + 1) { return true; }
            }
            for arm in m.matchArms(id) {
                if nodeReadsBinding(m, arm.guard_, binding, depth + 1) ||
                    nodeReadsBinding(m, arm.body, binding, depth + 1) { return true; }
            }
            for merge in m.branchMerges(id) {
                if merge.then_binding == binding || merge.else_binding == binding { return true; }
            }
            return false;
        },
        loop_ => {
            let linfo = m.loopInfo(id);
            if nodeReadsBinding(m, linfo.first, binding, depth + 1) ||
                nodeReadsBinding(m, linfo.end, binding, depth + 1) { return true; }
            for carry in m.loopCarries(id) {
                if carry.incoming == binding || carry.backedge == binding { return true; }
            }
            return nodeReadsBinding(m, linfo.body, binding, depth + 1);
        },
        return_, result_associated, fork_, project, flat_op => {
            return nodeReadsBinding(m, n.a, binding, depth + 1);
        },
        construct => {
            return nodeReadsBinding(m, n.b, binding, depth + 1);
        },
        update => {
            let uinfo = m.updateInfo(id);
            if nodeReadsBinding(m, uinfo.root, binding, depth + 1) ||
                nodeReadsBinding(m, uinfo.value, binding, depth + 1) { return true; }
            for sel in m.updateSelectors(id) {
                if sel.kind == blot_check_core::UpdateKind.index && nodeReadsBinding(m, sel.index, binding, depth + 1) { return true; }
            }
            return false;
        },
        scalar, logical, apply, associated => {
            return nodeReadsBinding(m, n.a, binding, depth + 1) || nodeReadsBinding(m, n.b, binding, depth + 1);
        },
        call => {
            for arg in m.call(id).arguments {
                if nodeReadsBinding(m, arg, binding, depth + 1) { return true; }
            }
            return false;
        },
        closure => {
            for cap in m.closureCaptures(id) {
                if cap == binding { return true; }
            }
            return false;
        },
        spark => {
            let sinfo = m.sparkInfo(id);
            return nodeReadsBinding(m, sinfo.source, binding, depth + 1) ||
                nodeReadsBinding(m, sinfo.end, binding, depth + 1) ||
                nodeReadsBinding(m, sinfo.body, binding, depth + 1);
        },
        _ => { return true; },
    }
}
// Follow the version a loop gives to its next iteration. Only a terminal
// rebinding in an actual arm may count as a use of the old list. Conditions,
// guards, item expressions and earlier statements still count as ordinary
// references. A statement case lowers to nested two-arm matches.
recursive fn terminalAppends(m: const Module&, suite: u32, incoming: u32, outgoing: u32, depth: i64) -> u32 {
    if incoming == 0 || depth >= 64 { return 0; }
    if incoming == outgoing {
        if depth == 0 { return 0; }
        if suite == 0 || !nodeReadsBinding(m, suite, incoming, 0) { return 1; }
        return 0;
    }
    if suite == 0 { return 0; }
    if m.node(suite).tag != blot_check_core::Tag.suite { return 0; }
    let statements = m.children(suite);
    if statements.len == 0 { return 0; }
    let id = statements[statements.len - 1];
    let n = m.node(id);
    if n.tag == blot_check_core::Tag.bind {
        if n.a != outgoing || n.c != 1 { return 0; }
        if m.node(n.b).tag != blot_check_core::Tag.array_op || m.arrayOperation(n.b) != blot_backend_collection_ops::Op.append { return 0; }
        let args = m.children(n.b);
        if args.len == 2 && localRef(m, args[0]) == incoming { return 1; }
        return 0;
    }
    var yes: u32 = 0;
    var no: u32 = 0;
    if n.tag == blot_check_core::Tag.if_stmt { yes = n.b; no = n.c; }
    else if n.tag == blot_check_core::Tag.match_ && m.matchInfo(id).statement {
        let arms = m.matchArms(id);
        if arms.len != 2 { return 0; }
        yes = arms[0].body;
        no = arms[1].body;
    } else { return 0; }
    for merge in m.branchMerges(id) {
        if merge.result == outgoing {
            return terminalAppends(m, yes, incoming, merge.then_binding, depth + 1)
                 + terminalAppends(m, no, incoming, merge.else_binding, depth + 1);
        }
    }
    return 0;
}
// References to local `binding` in this unit, counted once. A loop exit
// (`break_`) carrying a version is on a path exclusive with any later
// rebinding of it, so it does not count. Implicit reads in branch merges
// (`then_binding`/`else_binding`) and loop carries (`incoming`/`backedge`)
// are included so aliases via merges or carries are never treated as single-use.
fn uses(g: Generator&, f: const Fn&, binding: u32) -> u32 {
    let m .= g.units[f.unit - 1];
    let uid = (m.unit - 1) as i64;
    while g.s.use_count_base.len < g.units.len { g.s.use_count_base.push(0xffffffff); }
    var base = g.s.use_count_base[uid];
    if base == 0xffffffff {
        base = g.s.use_count_vals.len as u32;
        g.s.use_count_base[uid] = base;
        blot_direct_emit::growZerosU32(g.s.use_count_vals, m.bindings.len);
        var is_exit: u8[>..<] = [];
        is_exit.resize(m.nodes.len, 0);
        for index in 0..m.nodes.len {
            if m.nodes[index].tag != blot_check_core::Tag.break_ { continue; }
            for child in m.children(index as u32) { is_exit[child] = 1; }
        }
        for index in 0..m.nodes.len {
            let node = m.nodes[index];
            if node.tag != blot_check_core::Tag.reference || is_exit[index] != 0 { continue; }
            let target = m.references[node.a];
            if target.unit != 0 && target.unit != m.unit { continue; }
            g.s.use_count_vals[(base as i64) + (target.binding as i64)] += 1;
        }
        for merge in m.merges {
            if merge.then_binding != 0 && (merge.then_binding as i64) < m.bindings.len {
                g.s.use_count_vals[(base as i64) + (merge.then_binding as i64)] += 1;
            }
            if merge.else_binding != 0 && (merge.else_binding as i64) < m.bindings.len {
                g.s.use_count_vals[(base as i64) + (merge.else_binding as i64)] += 1;
            }
        }
        for carry in m.loop_carries {
            if carry.incoming != 0 && (carry.incoming as i64) < m.bindings.len {
                g.s.use_count_vals[(base as i64) + (carry.incoming as i64)] += 1;
            }
            if carry.backedge != 0 && (carry.backedge as i64) < m.bindings.len {
                g.s.use_count_vals[(base as i64) + (carry.backedge as i64)] += 1;
            }
        }
        // Each arm hands its successor to the same carry, so only one of
        // these receivers can run before the old version is replaced.
        for loop_ in m.loops {
            for carry in m.loop_carries[loop_.carries.start..loop_.carries.start + loop_.carries.len] {
                let slot = (base as i64) + (carry.iteration as i64);
                let count = g.s.use_count_vals[slot];
                if count < 2 || m.types.node(m.binding(carry.iteration).ty).tag != blot_check_types::Tag.array { continue; }
                if terminalAppends(m, loop_.body, carry.iteration, carry.backedge, 0) == count {
                    g.s.use_count_vals[slot] = 1;
                }
            }
        }
    }
    return g.s.use_count_vals[(base as i64) + (binding as i64)];
}
// Whether call node `id` applies a named function to fewer arguments than its
// parameters.
fn partialCall(g: const Generator&, f: const Fn&, id: u32) -> bool {
    let m .= g.units[f.unit - 1];
    let info = m.call(id);
    let target = g.resolve(m, info.target);
    let tm .= g.units[target.unit - 1];
    let body .= tm.body(target.binding);
    if !body { return false; }
    return body.is_function && info.arguments.len < tm.bodyParameters(body).len;
}
// Whether an apply chain applies a named function to fewer arguments than its
// parameters (with pure arguments).
fn partialApply(g: const Generator&, f: const Fn&, id: u32) -> bool {
    let m .= g.units[f.unit - 1];
    var head = id;
    var count: i64 = 0;
    while m.node(head).tag == blot_check_core::Tag.apply { head = m.node(head).a; count += 1; }
    if m.node(head).tag != blot_check_core::Tag.reference { return false; }
    let target = g.resolve(m, m.reference(head));
    let tm .= g.units[target.unit - 1];
    let body .= tm.body(target.binding);
    if !body { return false; }
    return body.is_function && count < tm.bodyParameters(body).len;
}
fn pureFunctionValue(g: const Generator&, f: const Fn&, id: u32) -> bool {
    match g.units[f.unit - 1].node(id).tag {
        reference, closure, constructor_function, primitive_function => { return true; },
        _ => { return false; },
    }
}
// Whether `ty` lowers under the current environment (no failure kept).
fn lowers(g: Generator&, f: const Fn&, ty: TId) -> bool {
    let lowered, error = g.types.lower(g.units[f.unit - 1], ty, f.env);
    return error == blot_direct_types::Error.none;
}
recursive fn bodyContainsCall(m: const Module&, id: u32, left: i64&) -> bool {
    if id == 0 || left <= 0 { return true; }
    left -= 1;
    let n = m.node(id);
    match n.tag {
        call, apply, contract_method => { return true; },
        suite, block_, product, record, array, array_op, storage => {
            for child in m.children(id) {
                if bodyContainsCall(m, child, left) { return true; }
            }
            return false;
        },
        if_stmt, if_value => {
            return bodyContainsCall(m, n.a, left) || bodyContainsCall(m, n.b, left) || bodyContainsCall(m, n.c, left);
        },
        bind, construct => { return bodyContainsCall(m, n.b, left); },
        pattern_bind => { return bodyContainsCall(m, n.b, left) || bodyContainsCall(m, n.c, left); },
        return_, project => { return bodyContainsCall(m, n.a, left); },
        scalar, logical, associated => { return bodyContainsCall(m, n.a, left) || bodyContainsCall(m, n.b, left); },
        match_ => {
            for inp in m.matchInputs(id) {
                if bodyContainsCall(m, inp, left) { return true; }
            }
            for arm in m.matchArms(id) {
                if bodyContainsCall(m, arm.guard_, left) || bodyContainsCall(m, arm.body, left) { return true; }
            }
            return false;
        },
        loop_ => {
            let linfo = m.loopInfo(id);
            return bodyContainsCall(m, linfo.first, left) || bodyContainsCall(m, linfo.end, left) || bodyContainsCall(m, linfo.body, left);
        },
        _ => { return false; },
    }
}

// Applies a resolved module-level binding to evaluated arguments. `callee` is
// its concrete (curried) function type at this site.
recursive fn callTarget(g: Generator&, f: Fn&, target: BindingRef, arguments: Vals, callee: Ty, result: Ty, id: u32, elide_nan: bool = false) -> Val, Error {
    let tm .= g.units[target.unit - 1];
    let body .= tm.body(target.binding);
    if body && body.is_function {
        let parameters = tm.bodyParameters(body);
        let param_count = parameters.len;
        let tail_here = f.tail_call_node == id;
        let is_tail = tail_here && (arguments.len as i64) == param_count;
        f.tail_call_node = 0;
        if arguments.len < param_count {
            let rest, error = restType(g, f, callee, arguments.len, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            return partial(g, f, blot_direct_emit::InstanceKind.partial, target, rest, arguments, id);
        }
        let direct = Vals { arguments.start, param_count as u32 };
        let after, error = restType(g, f, callee, param_count, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        // Forwarding chains are short; a cycle (a function that forwards to
        // itself) ends in an ordinary call.
        var value = neverVal();
        var has_value = false;
        let evidence_context = evidenceContext(g, f, target, id);
        let self_tco_target = is_tail && f.self_tco_loop != 0xffffffff &&
            target.unit == f.unit && target.binding == g.s.instances[f.instance_id].key.id;
        var skip_inline_for_tco = self_tco_target;
        if !skip_inline_for_tco && is_tail && blot_direct_writer::tailCallsEnabled() {
            var cbud: i64 = 64;
            if bodyContainsCall(tm, body.root, cbud) { skip_inline_for_tco = true; }
        }
        if !self_tco_target && f.forward_depth < 8 && evidence_context == 0 {
            f.forward_depth += 1;
            let forwarded, was_forwarded, error = forward(g, f, tm, body, direct, callee, after, id);
            f.forward_depth -= 1;
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            if was_forwarded { g.recordInlined(target.unit, target.binding); }
            value = forwarded;
            has_value = was_forwarded;
        }
        if !has_value && !skip_inline_for_tco && f.inline_depth < 3 && evidence_context == 0 {
            let inlined, was_inlined, ierr = inlineSmall(g, f, target, direct, callee, after, id);
            if ierr != blot_direct_types::Error.none { return neverVal(), ierr; }
            if was_inlined {
                g.recordInlined(target.unit, target.binding);
                value = inlined;
                has_value = true;
            }
        }
        if !has_value {
            let m .= g.units[f.unit - 1];
            let instance, error = g.namedWith(target, callee, false, m, id, evidence_context);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            if g.s.instances[instance].inferring { return neverVal(), g.fail(m, id, "recursion through a function whose result type its body determines"); }
            let instance_parameters = g.s.instances[instance].parameters;
            for at in 0..(direct.len as i64) {
                let argument = g.s.vals[direct.start + at];
                let parameter = g.s.tys[instance_parameters.start + at];
                let width, error = layoutLen(g, f, parameter, id);
                if error != blot_direct_types::Error.none { return neverVal(), error; }
                if width != argument.len {
                    g.failOpen(m, id);
                    g.put("argument of ");
                    g.putNumber(argument.len);
                    g.put(" words for a ");
                    g.put(blot_direct_types::tagName(tagOf(g, parameter)));
                    g.put(" parameter of ");
                    g.putNumber(width);
                    g.put(" words");
                    return neverVal(), g.failClose();
                }
            }
            if is_tail && f.self_tco_loop != 0xffffffff && instance == f.instance_id && direct.len == f.self_tco_inputs.len {
                // Default MVP self-tail-call-to-loop: push all argument words onto the
                // Wasm stack, pop in reverse into parameter locals (parallel-swap safe!),
                // clear caches, and jump back to the function's TCO loop header.
                for at in 0..(direct.len as i64) { push(g, g.s.vals[direct.start + at]); }
                var at = direct.len as i64;
                while at > 0 {
                    at -= 1;
                    let param_v = g.s.vals[f.self_tco_inputs.start + at];
                    var wi = param_v.len as i64;
                    while wi > 0 {
                        wi -= 1;
                        lset(g, w(g, param_v, wi));
                    }
                }
                f.checked_arrays_len = 0;
                f.checked_grows_len = 0;
                f.checked_views_len = 0;
                f.checked_elems_len = 0;
                f.checked_bounds_len = 0;
                f.checked_le_len = 0;
                f.const_tags_len = 0;
                br(g, f, OP_br, f.self_tco_loop);
                return neverVal(), blot_direct_types::Error.none;
            }
            if is_tail && blot_direct_writer::tailCallsEnabled() && !g.s.instances[f.instance_id].inferring &&
                g.s.instances[instance].result == g.s.instances[f.instance_id].result &&
                g.s.instances[f.instance_id].result != blot_direct_types::never {
                // Opt-in Wasm 3.0 `return_call` (0x12) for non-self / mutual tail calls.
                for at in 0..(direct.len as i64) { push(g, g.s.vals[direct.start + at]); }
                opIndex(g, OP_return_call, g.s.instances[instance].function);
                f.emitted_return_call = true;
                f.checked_elems_len = 0;
                return neverVal(), blot_direct_types::Error.none;
            }
            for at in 0..(direct.len as i64) { push(g, g.s.vals[direct.start + at]); }
            callf(g, g.s.instances[instance].function);
            f.checked_elems_len = 0;
            let returned, error = received(g, f, g.s.instances[instance].result, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            value = returned;
        }
        for at in param_count..(arguments.len as i64) {
            let applied, error = applyClosure(g, f, value, g.s.vals[arguments.start + at], id, tail_here && at + 1 == (arguments.len as i64));
            if error != blot_direct_types::Error.none { return applied, error; }
            value = applied;
        }
        return value, blot_direct_types::Error.none;
    }
    let tail_const = f.tail_call_node == id;
    f.tail_call_node = 0;
    if body && !body.is_function && tm.node(body.root).tag == blot_check_core::Tag.reference && f.forward_depth < 8 {
        let next = g.resolve(tm, tm.reference(body.root));
        if next != target {
            g.recordInlined(target.unit, target.binding);
            f.forward_depth += 1;
            if tail_const { f.tail_call_node = id; }
            let forwarded, ferr = callTarget(g, f, next, arguments, callee, result, id, elide_nan);
            f.tail_call_node = 0;
            f.forward_depth -= 1;
            return forwarded, ferr;
        }
    }
    let node, has_alias = primitiveAlias(tm, target.binding);
    if has_alias {
        g.recordInlined(target.unit, target.binding);
        return applyPrimitive(g, f, tm.primitive(node), arguments, callee, result, target, id, elide_nan);
    }
    // A constant holding a function value: apply it one argument at a time.
    var value, error = namedValue(g, f, target, callee, id);
    if error != blot_direct_types::Error.none { return value, error; }
    for at in 0..(arguments.len as i64) {
        let applied, error = applyClosure(g, f, value, g.s.vals[arguments.start + at], id, tail_const && at + 1 == (arguments.len as i64));
        if error != blot_direct_types::Error.none { return applied, error; }
        value = applied;
    }
    return value, blot_direct_types::Error.none;
}
fn namedValue(g: Generator&, f: Fn&, target: BindingRef, ty: Ty, id: u32) -> Val, Error {
    let instance, error = g.namedWith(target, ty, false, g.units[f.unit - 1], id, evidenceContext(g, f, target, id));
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    callf(g, g.s.instances[instance].function);
    return received(g, f, ty, id);
}
fn applyPrimitive(g: Generator&, f: Fn&, primitive: blot_check_core::Primitive, arguments: Vals, callee: Ty, result: Ty, target: BindingRef, id: u32, elide_nan: bool = false) -> Val, Error {
    let m .= g.units[f.unit - 1];
    if primitive.kind != blot_check_core::PrimitiveKind.scalar { return neverVal(), g.fail(m, id, "array primitives are not supported yet"); }
    if arguments.len < primitive.arity {
        let rest, error = restType(g, f, callee, arguments.len, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        return partial(g, f, blot_direct_emit::InstanceKind.primitive, target, rest, arguments, id);
    }
    if arguments.len > primitive.arity { return neverVal(), g.fail(m, id, "primitive over-application"); }
    for at in 0..(arguments.len as i64) { push(g, g.s.vals[arguments.start + at]); }
    let emitted = scalarOp(g, f, primitive.op, g.s.vals[arguments.start].ty, id, !elide_nan);
    if emitted != blot_direct_types::Error.none { return neverVal(), emitted; }
    return pop(g, f, result, id);
}
// The type left after applying `count` arguments to function type `ty`.
fn restType(g: Generator&, f: const Fn&, ty: Ty, count: i64, id: u32) -> Ty, Error {
    var rest = ty;
    for step in 0..count {
        let arrow = g.types.node(rest);
        if arrow.tag != blot_direct_types::Tag.function { return 0, g.fail(g.units[f.unit - 1], id, "too many arguments"); }
        rest = arrow.b;
    }
    return rest, blot_direct_types::Error.none;
}
// Eligibility check for direct leaf-function inlining: small, non-recursive,
// loop-free, closure-free, non-allocating Core bodies so caller CheckedArray/
// CheckedView descriptors remain live across the call and Cranelift can fold
// constant arguments and match dispatch.
recursive fn canInlineBody(g: const Generator&, tm: const Module&, id: u32, target: BindingRef, budget: i64&) -> bool {
    if id == 0 { return true; }
    if budget <= 0 { return false; }
    budget -= 1;
    let n = tm.node(id);
    match n.tag {
        constant, panic => { return true; },
        reference => {
            let resolved = g.resolve(tm, tm.reference(id));
            return !(resolved == target);
        },
        scalar, logical, associated => {
            return canInlineBody(g, tm, n.a, target, budget) && canInlineBody(g, tm, n.b, target, budget);
        },
        if_value, if_stmt => {
            return canInlineBody(g, tm, n.a, target, budget) &&
                canInlineBody(g, tm, n.b, target, budget) &&
                canInlineBody(g, tm, n.c, target, budget);
        },
        block_, suite => {
            for child in tm.children(id) {
                if !canInlineBody(g, tm, child, target, budget) { return false; }
            }
            return true;
        },
        bind => {
            if n.c >= 2 || tm.binding(n.a).scheme.variables.len != 0 { return false; }
            return canInlineBody(g, tm, n.b, target, budget);
        },
        pattern_bind => {
            return canInlineBody(g, tm, n.b, target, budget) && canInlineBody(g, tm, n.c, target, budget);
        },
        return_ => { return canInlineBody(g, tm, n.a, target, budget); },
        product, record => {
            let children = tm.children(id);
            if children.len > 8 { return false; }
            for child in children {
                if !canInlineBody(g, tm, child, target, budget) { return false; }
            }
            return true;
        },
        construct => { return canInlineBody(g, tm, n.b, target, budget); },
        project => { return canInlineBody(g, tm, n.a, target, budget); },
        match_ => {
            for inp in tm.matchInputs(id) {
                if !canInlineBody(g, tm, inp, target, budget) { return false; }
            }
            for arm in tm.matchArms(id) {
                if !canInlineBody(g, tm, arm.guard_, target, budget) ||
                    !canInlineBody(g, tm, arm.body, target, budget) { return false; }
            }
            return true;
        },
        array_op => {
            let op = tm.arrayOperation(id);
            if op != blot_backend_collection_ops::Op.length && op != blot_backend_collection_ops::Op.get { return false; }
            for child in tm.children(id) {
                if !canInlineBody(g, tm, child, target, budget) { return false; }
            }
            return true;
        },
        storage => {
            let op_kind, ok = blot_check_storage_ops::opFromCode(n.c);
            if ok != blot_error::Error.none { return false; }
            if op_kind != blot_check_storage_ops::Op.length && op_kind != blot_check_storage_ops::Op.read && op_kind != blot_check_storage_ops::Op.push && op_kind != blot_check_storage_ops::Op.pop && op_kind != blot_check_storage_ops::Op.truncate { return false; }
            for child in tm.children(id) {
                if !canInlineBody(g, tm, child, target, budget) { return false; }
            }
            return true;
        },
        call => {
            let info = tm.call(id);
            let callee_ref = g.resolve(tm, info.target);
            if callee_ref == target { return false; }
            for arg in info.arguments {
                if !canInlineBody(g, tm, arg, target, budget) { return false; }
            }
            return true;
        },
        apply => {
            return canInlineBody(g, tm, n.a, target, budget) && canInlineBody(g, tm, n.b, target, budget);
        },
        update => {
            let uinfo = tm.updateInfo(id);
            if !canInlineBody(g, tm, uinfo.root, target, budget) ||
                !canInlineBody(g, tm, uinfo.value, target, budget) { return false; }
            for sel in tm.updateSelectors(id) {
                if sel.kind == blot_check_core::UpdateKind.index && !canInlineBody(g, tm, sel.index, target, budget) { return false; }
            }
            return true;
        },
        loop_ => {
            if budget < 8 { return false; }
            budget -= 4;
            let linfo = tm.loopInfo(id);
            return canInlineBody(g, tm, linfo.first, target, budget) &&
                canInlineBody(g, tm, linfo.end, target, budget) &&
                canInlineBody(g, tm, linfo.body, target, budget);
        },
        break_ => {
            for child in tm.breakValues(id) {
                if !canInlineBody(g, tm, child, target, budget) { return false; }
            }
            return true;
        },
        spark => {
            if budget < 24 { return false; }
            budget -= 16;
            let sinfo = tm.sparkInfo(id);
            return canInlineBody(g, tm, sinfo.source, target, budget) &&
                canInlineBody(g, tm, sinfo.end, target, budget) &&
                canInlineBody(g, tm, sinfo.body, target, budget);
        },
        _ => { return false; },
    }
}

fn canInlineTarget(g: Generator&, target: BindingRef, inline_depth: u32) -> bool {
    let uid = (target.unit - 1) as i64;
    while g.s.inline_ok_base.len < g.units.len { g.s.inline_ok_base.push(0xffffffff); }
    var base = g.s.inline_ok_base[uid];
    if base == 0xffffffff {
        base = g.s.inline_ok_vals.len as u32;
        g.s.inline_ok_base[uid] = base;
        blot_direct_emit::growZerosU8(g.s.inline_ok_vals, g.units[uid].bindings.len);
    }
    let slot = (base as i64) + (target.binding as i64);
    var mask = g.s.inline_ok_vals[slot];
    if mask == 0 {
        mask = 0x80;
        let tm .= g.units[uid];
        let body .= tm.body(target.binding);
        if body && body.is_function && !body.exported {
            var b168: i64 = 168;
            if canInlineBody(g, tm, body.root, target, b168) {
                mask |= 1;
                var b152: i64 = 152;
                if canInlineBody(g, tm, body.root, target, b152) {
                    mask |= 2;
                    var b32: i64 = 32;
                    if canInlineBody(g, tm, body.root, target, b32) {
                        mask |= 4;
                    }
                }
            }
        }
        g.s.inline_ok_vals[slot] = mask;
    }
    var bit: u8 = 1;
    if inline_depth == 1 { bit = 2; }
    else if inline_depth >= 2 { bit = 4; }
    return (mask & bit) != 0;
}

recursive fn inlineSmall(g: Generator&, f: Fn&, target: BindingRef, direct: Vals, callee: Ty, after: Ty, id: u32) -> Val, bool, Error {
    if g.s.instances[f.instance_id].key.kind == blot_direct_emit::InstanceKind.partial {
        return neverVal(), false, blot_direct_types::Error.none;
    }
    if tagOf(g, after) == blot_direct_types::Tag.never || tagOf(g, after) == blot_direct_types::Tag.function {
        return neverVal(), false, blot_direct_types::Error.none;
    }
    if !g.types.concrete(callee, 0) || !g.types.concrete(after, 0) {
        return neverVal(), false, blot_direct_types::Error.none;
    }
    if !canInlineTarget(g, target, f.inline_depth) {
        return neverVal(), false, blot_direct_types::Error.none;
    }
    let boxed_ret, berr = g.types.boxed(after);
    if berr != blot_direct_types::Error.none || boxed_ret {
        return neverVal(), false, blot_direct_types::Error.none;
    }
    var body_root: u32 = 0;
    var param_bindings: u32[16] = [0; 16];
    var param_count: i64 = 0;
    var obligations = blot_check_types::List {};
    var env = Env {};
    {
        let tm .= g.units[target.unit - 1];
        let body .= tm.body(target.binding);
        if !body || !body.is_function || body.exported { return neverVal(), false, blot_direct_types::Error.none; }
        body_root = body.root;
        g.types.match_(tm, tm.binding(body.binding).ty, callee, env);
        obligations = body.scheme.obligations;
    }
    if obligations.len != 0 {
        let solved = g.solveObligationsPublic(g.units[target.unit - 1], obligations, env);
        if solved != blot_direct_types::Error.none {
            g.dropFailure();
            return neverVal(), false, blot_direct_types::Error.none;
        }
    }
    {
        let tm .= g.units[target.unit - 1];
        let body .= tm.body(target.binding);
        if !body { return neverVal(), false, blot_direct_types::Error.none; }
        for v in tm.types.list(body.scheme.variables) {
            let _, verr = g.types.lower(tm, v, env);
            if verr != blot_direct_types::Error.none {
                g.dropFailure();
                return neverVal(), false, blot_direct_types::Error.none;
            }
        }
        let parameters = tm.bodyParameters(body);
        if parameters.len > 16 || parameters.len != direct.len {
            return neverVal(), false, blot_direct_types::Error.none;
        }
        for parameter, at in parameters {
            let pty, perr = g.types.lower(tm, parameter.ty, env);
            if perr != blot_direct_types::Error.none {
                g.dropFailure();
                return neverVal(), false, blot_direct_types::Error.none;
            }
            let pwords, werr = g.types.layout(pty);
            if werr != blot_direct_types::Error.none || (pwords.len as u32) != g.s.vals[direct.start + at].len {
                return neverVal(), false, blot_direct_types::Error.none;
            }
            param_bindings[at] = parameter.binding;
        }
        param_count = parameters.len;
    }

    // Forward single-use uniquely-owned array arguments from caller into the
    // inlined callee so `spark` inside inlined helpers (e.g. `integrate_particles`)
    // can reuse the caller's uniquely-owned buffer in place!
    var unique_arg_mask: u32 = 0;
    if id != 0 && param_count <= 16 {
        let cm .= g.units[f.unit - 1];
        if cm.node(id).tag == blot_check_core::Tag.call {
            let call_info = cm.call(id);
            if call_info.arguments.len == param_count {
                var arg_bs: u32[16] = [0; 16];
                for ai in 0..param_count { arg_bs[ai] = localRef(cm, call_info.arguments[ai]); }
                for ai in 0..param_count {
                    let ab = arg_bs[ai];
                    if ab == 0 { continue; }
                    var dup = false;
                    for aj in 0..param_count {
                        if aj != ai && arg_bs[aj] == ab { dup = true; break; }
                    }
                    if dup { continue; }
                    if isUniqueOwned(g, f, ab) && ownedTotalUses(g, f, ab) == 1 && !bindingCaptured(g, f, ab) {
                        unique_arg_mask |= ((1 as u32) << (ai as u32));
                    }
                }
            }
        }
    }

    // Emit the callee body directly in the caller's Wasm function while keeping
    // the caller's CheckedArray/CheckedGrow/CheckedView descriptors live.
    let saved_unit = f.unit;
    let saved_env = f.env;
    let saved_bindings = f.bindings;
    let saved_with_cells = f.with_cells;
    let saved_unique_boxed = f.unique_boxed;
    let saved_unique_owned = f.unique_owned;
    let saved_loop_depth = f.loop_depth;
    let saved_indirect_b = f.indirect_bound_binding;
    let saved_indirect_l = f.indirect_bound_len;
    let saved_indirect_d = f.indirect_bound_distinct_local;
    let saved_fn_ret_block = f.fn_return_block;
    let saved_self_tco_loop = f.self_tco_loop;
    let saved_tail_call = f.tail_call_node;
    let saved_tco_inhibit = f.tco_inhibit;
    let saved_owned_computed = f.owned_uses_computed;
    let saved_owned_uses = f.owned_uses;
    let saved_owned_flows = f.owned_flows;
    let saved_nan_computed = f.nan_elide_computed;
    let saved_nan_observed = f.nan_observed;
    let saved_finite_f32 = f.finite_f32;
    let saved_finite_f32_len = f.finite_f32_len;
    let saved_inlined_body = f.inlined_body_binding;
    let saved_labels_base = f.labels_base;
    let saved_scratch_body = f.scratch_body;
    let saved_scratch_cut = f.scratch_cut;
    let saved_serial = f.serial;
    let saved_checked_range = f.checked_range;
    let saved_current_call = f.current_call;
    let saved_field_value = f.field_value;
    let saved_evidence_context = f.evidence_context;

    let slot = g.newSlot();
    let made, merr = fresh(g, f, after, id);
    if merr != blot_direct_types::Error.none { return neverVal(), false, merr; }
    g.s.slots[slot] = blot_direct_emit::Slot { true, made };

    let exit = open(g, f, OP_block);
    let s .= g.s;
    let labels_mark = s.labels.len;
    s.labels.push(blot_direct_emit::Label { target: 0xffffffff, depth: exit, result: slot, kind: blot_direct_emit::LabelKind.function });

    s.serial += 1;
    f.serial = s.serial;
    f.unit = target.unit;
    f.env = env;
    f.bindings = blot_support_zigmap::Map {};
    f.with_cells = blot_support_zigmap::Map {};
    f.unique_boxed = blot_support_zigmap::Map {};
    f.unique_owned = blot_support_zigmap::Map {};
    f.loop_depth = 0;
    f.indirect_bound_binding = 0;
    f.indirect_bound_len = 0;
    f.indirect_bound_distinct_local = 0xffffffff;
    f.fn_return_block = 0;
    f.self_tco_loop = 0xffffffff;
    f.tail_call_node = 0;
    f.tco_inhibit = saved_tco_inhibit + 1;
    f.owned_uses_computed = false;
    f.owned_uses = blot_support_zigmap::Map {};
    f.owned_flows = blot_support_zigmap::Map {};
    f.nan_elide_computed = false;
    f.nan_observed = blot_support_zigmap::Map {};
    f.finite_f32_len = 0;
    f.inlined_body_binding = target.binding;
    f.labels_base = labels_mark;
    f.scratch_body = 0;
    f.scratch_cut = ScratchCut {};
    f.checked_range = CheckedRange {};
    f.current_call = 0;
    f.field_value = false;
    f.evidence_context = 0;
    f.inline_depth += 1;

    for at in 0..param_count {
        bindPut(g, f, param_bindings[at], g.s.vals[direct.start + at]);
        if (unique_arg_mask & ((1 as u32) << (at as u32))) != 0 {
            blot_support_zigmap::put(g.s.map_pool, f.unique_owned, param_bindings[at], 1);
        }
    }
    let body_val, b_err = stmt(g, f, body_root);
    var final_err = b_err;
    if final_err == blot_direct_types::Error.none {
        let derr = deliver(g, f, body_val, slot, body_root);
        if derr == blot_direct_types::Error.unsupported { g.recordFailure(g.units[target.unit - 1], body_root); }
        else if derr != blot_direct_types::Error.none { final_err = derr; }
    }
    close(g, f);

    s.labels.resize(labels_mark);
    f.inline_depth -= 1;
    f.unit = saved_unit;
    f.env = saved_env;
    f.bindings = saved_bindings;
    f.with_cells = saved_with_cells;
    f.unique_boxed = saved_unique_boxed;
    f.unique_owned = saved_unique_owned;
    f.loop_depth = saved_loop_depth;
    f.indirect_bound_binding = saved_indirect_b;
    f.indirect_bound_len = saved_indirect_l;
    f.indirect_bound_distinct_local = saved_indirect_d;
    f.fn_return_block = saved_fn_ret_block;
    f.self_tco_loop = saved_self_tco_loop;
    f.tail_call_node = saved_tail_call;
    f.tco_inhibit = saved_tco_inhibit;
    f.owned_uses_computed = saved_owned_computed;
    f.owned_uses = saved_owned_uses;
    f.owned_flows = saved_owned_flows;
    f.nan_elide_computed = saved_nan_computed;
    f.nan_observed = saved_nan_observed;
    f.finite_f32 = saved_finite_f32;
    f.finite_f32_len = saved_finite_f32_len;
    f.inlined_body_binding = saved_inlined_body;
    f.labels_base = saved_labels_base;
    f.scratch_body = saved_scratch_body;
    f.scratch_cut = saved_scratch_cut;
    f.serial = saved_serial;
    f.checked_range = saved_checked_range;
    f.current_call = saved_current_call;
    f.field_value = saved_field_value;
    f.evidence_context = saved_evidence_context;

    if final_err != blot_direct_types::Error.none { return neverVal(), false, final_err; }
    return g.s.slots[slot].value, true, blot_direct_types::Error.none;
}

// A wrapper whose body only passes its parameters to an associated member or
// another named function is resolved at the call site, so an operator on
// scalars costs one machine instruction, not two calls.
recursive fn forward(g: Generator&, f: Fn&, tm: const Module&, body: const blot_check_core::Body&, arguments: Vals, callee: Ty, result: Ty, id: u32) -> Val, bool, Error {
    let m .= g.units[f.unit - 1];
    let parameters = tm.bodyParameters(body);
    var root = body.root;
    for step in 0..8 {
        let n = tm.node(root);
        if n.tag == blot_check_core::Tag.return_ { root = n.a; }
        else if n.tag == blot_check_core::Tag.block_ && n.b == 1 { root = tm.children(root)[0]; }
        else { break; }
    }
    let n = tm.node(root);
    var operands: u32[8] = [0; 8];
    var operand_count: i64 = 0;
    if n.tag == blot_check_core::Tag.associated {
        operands[0] = n.a;
        operand_count = 1;
        if n.b != 0 { operands[1] = n.b; operand_count = 2; }
    } else if n.tag == blot_check_core::Tag.call {
        let inner_arguments = tm.call(root).arguments;
        if inner_arguments.len > 8 { return neverVal(), false, blot_direct_types::Error.none; }
        for operand, at in inner_arguments { operands[at] = operand; }
        operand_count = inner_arguments.len;
    } else if n.tag == blot_check_core::Tag.array_op || n.tag == blot_check_core::Tag.storage {
        let children = tm.children(root);
        if children.len == 0 || children.len > 8 { return neverVal(), false, blot_direct_types::Error.none; }
        for operand, at in children { operands[at] = operand; }
        operand_count = children.len;
    } else { return neverVal(), false, blot_direct_types::Error.none; }
    let forwarded = g.reserveVals(operand_count);
    for at in 0..operand_count {
        let operand = operands[at];
        if tm.node(operand).tag != blot_check_core::Tag.reference { return neverVal(), false, blot_direct_types::Error.none; }
        let ref = tm.reference(operand);
        if ref.unit != 0 && ref.unit != tm.unit { return neverVal(), false, blot_direct_types::Error.none; }
        var found = false;
        for parameter, position in parameters {
            if parameter.binding == ref.binding {
                g.s.vals[forwarded.start + at] = g.s.vals[arguments.start + position];
                found = true;
                break;
            }
        }
        if !found { return neverVal(), false, blot_direct_types::Error.none; }
    }
    if n.tag == blot_check_core::Tag.array_op {
        let operation = tm.arrayOperation(root);
        match operation {
            length => {
                if operand_count != 1 { return neverVal(), false, blot_direct_types::Error.none; }
                let length, error = lengthOf(g, f, g.s.vals[forwarded.start], id);
                if error != blot_direct_types::Error.none { return neverVal(), false, error; }
                return valOf1(g, blot_direct_types::u32_, length), true, blot_direct_types::Error.none;
            },
            get => {
                if operand_count != 2 { return neverVal(), false, blot_direct_types::Error.none; }
                let index, error = scalarLocal(g, f, g.s.vals[forwarded.start + 1], id);
                if error != blot_direct_types::Error.none { return neverVal(), false, error; }
                let value, error = readElement(g, f, g.s.vals[forwarded.start], index, id);
                return value, true, error;
            },
            fill, generate => {
                if operand_count != 2 || tagOf(g, result) == blot_direct_types::Tag.never { return neverVal(), false, blot_direct_types::Error.none; }
                let count, error = scalarLocal(g, f, g.s.vals[forwarded.start], id);
                if error != blot_direct_types::Error.none { return neverVal(), false, error; }
                let value, error = emitFillOrGenerate(g, f, operation == blot_backend_collection_ops::Op.fill, count, g.s.vals[forwarded.start + 1], result, id);
                return value, true, error;
            },
            _ => { return neverVal(), false, blot_direct_types::Error.none; },
        }
    }
    if n.tag == blot_check_core::Tag.storage {
        let operation, decoded = blot_check_storage_ops::opFromCode(n.c);
        if decoded != blot_error::Error.none { return neverVal(), false, blot_direct_types::Error.none; }
        match operation {
            length => {
                if operand_count != 1 { return neverVal(), false, blot_direct_types::Error.none; }
                let length, error = lengthOf(g, f, g.s.vals[forwarded.start], id);
                if error != blot_direct_types::Error.none { return neverVal(), false, error; }
                return valOf1(g, blot_direct_types::u32_, length), true, blot_direct_types::Error.none;
            },
            read => {
                if operand_count != 2 { return neverVal(), false, blot_direct_types::Error.none; }
                let index, error = scalarLocal(g, f, g.s.vals[forwarded.start + 1], id);
                if error != blot_direct_types::Error.none { return neverVal(), false, error; }
                let value, error = readElement(g, f, g.s.vals[forwarded.start], index, id);
                return value, true, error;
            },
            push => {
                if operand_count != 2 { return neverVal(), false, blot_direct_types::Error.none; }
                let pushed = g.s.vals[forwarded.start + 1];
                let holds, herr = g.contentsHoldMemory(pushed.ty);
                if herr != blot_direct_types::Error.none { return neverVal(), false, herr; }
                if holds { return neverVal(), false, blot_direct_types::Error.none; }
                let value, error = emitStoragePushVal(g, f, g.s.vals[forwarded.start], pushed, id);
                return value, true, error;
            },
            truncate => {
                if operand_count != 2 { return neverVal(), false, blot_direct_types::Error.none; }
                let container = g.s.vals[forwarded.start];
                let count, error = scalarLocal(g, f, g.s.vals[forwarded.start + 1], id);
                if error != blot_direct_types::Error.none { return neverVal(), false, error; }
                lget(g, w(g, container, 0));
                lget(g, w(g, container, 1));
                lget(g, count);
                callf(g, g.runtime_().truncate);
                return unitVal(), true, blot_direct_types::Error.none;
            },
            copy => {
                if operand_count != 1 || tagOf(g, result) == blot_direct_types::Tag.never { return neverVal(), false, blot_direct_types::Error.none; }
                let value, error = deepCopyValue(g, f, g.s.vals[forwarded.start], result, id, 0);
                return value, true, error;
            },
            view => {
                if operand_count != 3 || tagOf(g, result) == blot_direct_types::Tag.never { return neverVal(), false, blot_direct_types::Error.none; }
                let start, error = scalarLocal(g, f, g.s.vals[forwarded.start + 1], id);
                if error != blot_direct_types::Error.none { return neverVal(), false, error; }
                let end, error = scalarLocal(g, f, g.s.vals[forwarded.start + 2], id);
                if error != blot_direct_types::Error.none { return neverVal(), false, error; }
                let value, error = emitStorageViewVal(g, f, g.s.vals[forwarded.start], start, end, result, id);
                return value, true, error;
            },
            _ => { return neverVal(), false, blot_direct_types::Error.none; },
        }
    }
    if n.tag == blot_check_core::Tag.associated {
        let left = g.s.vals[forwarded.start];
        let tag = g.types.node(left.ty).tag;
        if n.op != blot_check_core::Op.none && isScalarTag(tag) {
            for at in 1..(forwarded.len as i64) {
                let value = g.s.vals[forwarded.start + at];
                if value.ty != left.ty {
                    g.failOpenCode(m, id, blot_check_diagnostic_code::Code.type_mismatch);
                    g.put(opName(n.op));
                    g.put(" applied to a ");
                    g.put(blot_direct_types::tagName(tag));
                    g.put(" and a ");
                    g.put(blot_direct_types::tagName(tagOf(g, value.ty)));
                    return neverVal(), false, g.failClose();
                }
            }
            let machine, error = scalarMember(g, f, tm, left.ty, n.c, n.op, id);
            if error != blot_direct_types::Error.none { return neverVal(), false, error; }
            for at in 0..(forwarded.len as i64) { push(g, g.s.vals[forwarded.start + at]); }
            let emitted = scalarOp(g, f, machine, left.ty, id);
            if emitted != blot_direct_types::Error.none { return neverVal(), false, emitted; }
            var popped_ty = result;
            if tagOf(g, result) == blot_direct_types::Tag.never { popped_ty = scalarResult(machine, left.ty); }
            let value, error = pop(g, f, popped_ty, id);
            return value, true, error;
        }
        let identity, has_identity = g.receiverIdentity(left.ty);
        if !has_identity { return neverVal(), false, blot_direct_types::Error.none; }
        let target, has_target = g.dispatchTarget(tm, identity, n.c, blot_check_types::Operator.none);
        if !has_target { return neverVal(), false, blot_direct_types::Error.none; }
        let full, error = curried(g, forwarded, result);
        if error != blot_direct_types::Error.none { return neverVal(), false, error; }
        let value, error = callTarget(g, f, target, forwarded, full, result, id);
        return value, true, error;
    }
    // Lower the inner call's type under the wrapper's own instance types.
    var env = Env {};
    g.types.match_(tm, tm.binding(body.binding).ty, callee, env);
    let inner = tm.call(root);
    let target = g.resolve(tm, inner.target);
    if requiresEvidence(g, target) { return neverVal(), false, blot_direct_types::Error.none; }
    let inner_type, error = g.types.lower(tm, inner.callee_type, env);
    if error != blot_direct_types::Error.none { return neverVal(), false, blot_direct_types::Error.none; }
    let value, error = callTarget(g, f, target, forwarded, inner_type, result, id);
    return value, true, error;
}
// The curried function type taking `arguments` and returning `result`.
fn curried(g: Generator&, arguments: Vals, result: Ty) -> Ty, Error {
    var ty = result;
    var at = arguments.len as i64;
    while at != 0 {
        at -= 1;
        let wrapped, error = g.types.function(g.s.vals[arguments.start + at].ty, ty);
        if error != blot_direct_types::Error.none { return 0, error; }
        ty = wrapped;
    }
    return ty, blot_direct_types::Error.none;
}

// Operator or member dispatch on the left operand's concrete type.
recursive fn associated(g: Generator&, f: Fn&, id: u32, elide_nan: bool = false) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let elide_children = n.op != blot_check_core::Op.none && isCanonicalF32Consumer(n.op) && isF32CoreExpr(g, f, m, n.a);
    if elide_children { f.elide_f32_nan_node = n.a; }
    let left, error = expr(g, f, n.a);
    f.elide_f32_nan_node = 0;
    if error != blot_direct_types::Error.none { return left, error; }
    var has_right = false;
    var right = neverVal();
    if n.b != 0 {
        if elide_children { f.elide_f32_nan_node = n.b; }
        let value, error = expr(g, f, n.b);
        f.elide_f32_nan_node = 0;
        if error != blot_direct_types::Error.none { return value, error; }
        has_right = true;
        right = value;
    }
    let result, result_error = g.types.lower(m, m.typeOf(id), f.env);
    let has_result = result_error == blot_direct_types::Error.none;
    let tag = g.types.node(left.ty).tag;
    if n.op != blot_check_core::Op.none && isScalarTag(tag) {
        let machine, error = scalarMember(g, f, m, left.ty, n.c, n.op, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        push(g, left);
        if has_right { push(g, right); }
        let skip_nan = elide_nan || (f.defer_f32_nan && isCanonicalF32Op(machine));
        let emitted = scalarOp(g, f, machine, left.ty, id, !skip_nan);
        if emitted != blot_direct_types::Error.none { return neverVal(), emitted; }
        var popped_ty = scalarResult(machine, left.ty);
        if has_result { popped_ty = result; }
        return pop(g, f, popped_ty, id);
    }
    let identity, has_identity = g.receiverIdentity(left.ty);
    if !has_identity {
        g.failOpen(m, id);
        g.put("associated member on a ");
        g.put(blot_direct_types::tagName(tag));
        return neverVal(), g.failClose();
    }
    let target, has_target = g.dispatchTarget(m, identity, n.c, blot_check_types::Operator.none);
    if !has_target { return neverVal(), g.failCode(m, id, blot_check_diagnostic_code::Code.missing_associated, "no associated member for this receiver"); }
    var owned = g.saveVals([left]);
    if has_right { owned = g.saveVals([left, right]); }
    var callee: Ty = 0;
    if has_result {
        let full, error = curried(g, owned, result);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        callee = full;
    } else {
        let derived, error = calleeOf(g, f, target, owned, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        callee = derived;
    }
    let rest, error = restType(g, f, callee, owned.len, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    return callTarget(g, f, target, owned, callee, rest, id);
}
