// Calls, closures applied, partial applications and generalized locals of the
// direct backend's function emitter (compiler/src/direct/function.zig).
namespace blot_direct_function;
import .function;

// Marks a primitive node (rather than a binding) as a partial target.
let primitive_node_bit: u32 = 0x80000000;

// Calls the closure `callee` with one argument.
fn applyClosure(g: Generator&, f: Fn&, callee: Val, argument: Val, id: u32) -> Val, Error {
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
    opIndex(g, OP_call_indirect, signature);
    uleb(g, 0);
    return received(g, f, arrow.b, id);
}
recursive fn apply(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
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
    return applyClosure(g, f, callee, argument, id);
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
    let key = InstanceKey { blot_direct_emit::InstanceKind.pool, target.unit, target.binding, ty, 0 };
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
        g.s.pool_globals.put(created, at);
        g.s.pool_order.push(created);
        instance = created;
    }
    callf(g, g.s.instances[instance].function);
    return pop(g, f, ty, id);
}
recursive fn poolBody(g: Generator&, f: Fn&, instance_id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let at, present = g.s.pool_globals.get(f.instance_id);
    assert(present);
    let slot_global = g.s.pool_words[at];
    let generation_global = g.s.pool_words[at + 1];
    let state_global = g.s.pool_words[at + 2];
    let persist = g.runtime_().persist;
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
    i32Const(g, boolWord(growable(g, key.ty)));
    callf(g, persist);
    gset(g, generation_global);
    gset(g, slot_global);
    releaseTo(g, owner_mark, stack_mark);
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

recursive fn call(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let previous_call = f.current_call;
    f.current_call = id;
    let value, error = callInner(g, f, id);
    f.current_call = previous_call;
    return value, error;
}
recursive fn callInner(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let info = m.call(id);
    let target = g.resolve(m, info.target);
    let arguments = info.arguments;
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
        let value, error = expr(g, f, argument);
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
    var callee, error = g.types.lower(m, info.callee_type, f.env);
    if error != blot_direct_types::Error.none {
        let derived, error = calleeOf(g, f, target, values, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        callee = derived;
    }
    refine(g, f, info.callee_type, callee);
    let rest, error = restType(g, f, callee, values.len, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    return callTarget(g, f, target, values, callee, rest, id);
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
        if goal.kind != blot_check_types::ObligationKind.field || goal.ty != formal || goal.result == 0 { continue; }
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
    if tagOf(g, list.ty) != blot_direct_types::Tag.list && tagOf(g, list.ty) != blot_direct_types::Tag.array { return neverVal(), false, blot_direct_types::Error.none; }
    if uses(g, f, ref.binding) != 1 { return neverVal(), false, blot_direct_types::Error.none; }
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
    let noted = noteStore(g, f, value);
    if noted != blot_direct_types::Error.none { return neverVal(), false, noted; }
    let written = writeFlat(g, f, address, 0, value, id);
    if written != blot_direct_types::Error.none { return neverVal(), false, written; }
    return list, true, blot_direct_types::Error.none;
}
// The value a closure captures for `binding`: a generalized local built at
// each use is built here at the type its uses give it.
recursive fn captureValue(g: Generator&, f: Fn&, binding: u32, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let bound, present = bindGet(g, f, binding);
    if present { return bound, blot_direct_types::Error.none; }
    let initializer, generalized = g.s.polymorphic.get(polyKey(f, binding));
    if !generalized { return neverVal(), g.fail(m, id, "closure capture without a value"); }
    let typed = typeByUses(g, f, binding, initializer);
    if typed != blot_direct_types::Error.none { return neverVal(), typed; }
    let value, error = expr(g, f, initializer);
    if error != blot_direct_types::Error.none { return value, error; }
    refine(g, f, m.binding(binding).ty, value.ty);
    bindPut(g, f, binding, value);
    return value, blot_direct_types::Error.none;
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
recursive fn usesType(g: Generator&, f: Fn&, binding: u32, id: u32, depth: u32) -> Ty, bool, Error {
    let m .= g.units[f.unit - 1];
    var has_chosen = false;
    var chosen: Ty = 0;
    for index in 0..m.nodes.len {
        let node = m.nodes[index];
        if node.tag != blot_check_core::Tag.reference { continue; }
        let target = m.references[node.a];
        if (target.unit != 0 && target.unit != m.unit) || target.binding != binding { continue; }
        var ty, error = g.types.lower(m, m.typeOf(index as u32), f.env);
        if error != blot_direct_types::Error.none {
            let aliased, found, error = aliasType(g, f, index as u32, id, depth);
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
// References to local `binding` in this unit, counted once. A loop exit
// (`break_`) carrying a version is on a path exclusive with any later
// rebinding of it, so it does not count.
fn uses(g: Generator&, f: const Fn&, binding: u32) -> u32 {
    let m .= g.units[f.unit - 1];
    if !g.s.use_count_units.contains(m.unit) {
        g.s.use_count_units.put(m.unit, 1);
        var exits = blot_direct_map::U64Map {};
        for index in 0..m.nodes.len {
            if m.nodes[index].tag != blot_check_core::Tag.break_ { continue; }
            for child in m.children(index as u32) { exits.put(child, 1); }
        }
        for index in 0..m.nodes.len {
            let node = m.nodes[index];
            if node.tag != blot_check_core::Tag.reference || exits.contains(index as u64) { continue; }
            let target = m.references[node.a];
            if target.unit != 0 && target.unit != m.unit { continue; }
            let key = blot_direct_emit::key64(m.unit, target.binding);
            let count, counted = g.s.use_counts.get(key);
            g.s.use_counts.put(key, count + 1);
        }
    }
    let count, counted = g.s.use_counts.get(blot_direct_emit::key64(m.unit, binding));
    return count;
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
// Applies a resolved module-level binding to evaluated arguments. `callee` is
// its concrete (curried) function type at this site.
recursive fn callTarget(g: Generator&, f: Fn&, target: BindingRef, arguments: Vals, callee: Ty, result: Ty, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let tm .= g.units[target.unit - 1];
    let body .= tm.body(target.binding);
    if body && body.is_function {
        let parameters = tm.bodyParameters(body);
        if arguments.len < parameters.len {
            let rest, error = restType(g, f, callee, arguments.len, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            return partial(g, f, blot_direct_emit::InstanceKind.partial, target, rest, arguments, id);
        }
        let direct = Vals { arguments.start, parameters.len as u32 };
        let after, error = restType(g, f, callee, parameters.len, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        // Forwarding chains are short; a cycle (a function that forwards to
        // itself) ends in an ordinary call.
        var value = neverVal();
        var has_value = false;
        if f.forward_depth < 8 {
            f.forward_depth += 1;
            let forwarded, was_forwarded, error = forward(g, f, tm, body, direct, callee, after, id);
            f.forward_depth -= 1;
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            value = forwarded;
            has_value = was_forwarded;
        }
        if !has_value {
            let instance, error = g.named(target, callee, m, id);
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
            for at in 0..(direct.len as i64) { push(g, g.s.vals[direct.start + at]); }
            callf(g, g.s.instances[instance].function);
            let returned, error = received(g, f, g.s.instances[instance].result, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            value = returned;
        }
        for at in parameters.len..(arguments.len as i64) {
            let applied, error = applyClosure(g, f, value, g.s.vals[arguments.start + at], id);
            if error != blot_direct_types::Error.none { return applied, error; }
            value = applied;
        }
        return value, blot_direct_types::Error.none;
    }
    let node, has_alias = primitiveAlias(tm, target.binding);
    if has_alias { return applyPrimitive(g, f, tm.primitive(node), arguments, callee, result, target, id); }
    // A constant holding a function value: apply it one argument at a time.
    var value, error = namedValue(g, f, target, callee, id);
    if error != blot_direct_types::Error.none { return value, error; }
    for at in 0..(arguments.len as i64) {
        let applied, error = applyClosure(g, f, value, g.s.vals[arguments.start + at], id);
        if error != blot_direct_types::Error.none { return applied, error; }
        value = applied;
    }
    return value, blot_direct_types::Error.none;
}
fn namedValue(g: Generator&, f: Fn&, target: BindingRef, ty: Ty, id: u32) -> Val, Error {
    let instance, error = g.named(target, ty, g.units[f.unit - 1], id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    callf(g, g.s.instances[instance].function);
    return received(g, f, ty, id);
}
fn applyPrimitive(g: Generator&, f: Fn&, primitive: blot_check_core::Primitive, arguments: Vals, callee: Ty, result: Ty, target: BindingRef, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    if primitive.kind != blot_check_core::PrimitiveKind.scalar { return neverVal(), g.fail(m, id, "array primitives are not supported yet"); }
    if arguments.len < primitive.arity {
        let rest, error = restType(g, f, callee, arguments.len, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        return partial(g, f, blot_direct_emit::InstanceKind.primitive, target, rest, arguments, id);
    }
    if arguments.len > primitive.arity { return neverVal(), g.fail(m, id, "primitive over-application"); }
    for at in 0..(arguments.len as i64) { push(g, g.s.vals[arguments.start + at]); }
    let emitted = scalarOp(g, f, primitive.op, g.s.vals[arguments.start].ty, id);
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
    let inner_type, error = g.types.lower(tm, inner.callee_type, env);
    if error != blot_direct_types::Error.none { return neverVal(), false, blot_direct_types::Error.none; }
    let value, error = callTarget(g, f, g.resolve(tm, inner.target), forwarded, inner_type, result, id);
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
recursive fn associated(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let left, error = expr(g, f, n.a);
    if error != blot_direct_types::Error.none { return left, error; }
    var has_right = false;
    var right = neverVal();
    if n.b != 0 {
        let value, error = expr(g, f, n.b);
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
        let emitted = scalarOp(g, f, machine, left.ty, id);
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
