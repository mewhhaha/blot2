// One instance's Wasm body. A single pass over its Core body; every value is a
// list of Wasm locals in its type's layout, so projections share locals.
// Port of compiler/src/direct/function.zig. The namespace continues in
// function_*.goose.
//
// Zig's `Fn` holds its generator, module and lists. Inside this recursive
// code Goose lets references only be passed down, so every function takes
// the generator `g` and the body state `f`, `f` names its module by unit,
// and the lists are the tops of the stacks in emit.State from `f`'s marks.
namespace blot_direct_function;
import std;
import check.core;
import check.effects;
import check.types;
import check.storage_ops;
import check.storage_types;
import check.diagnostic_code;
import reuse.principal_interface;
import direct.writer;
import direct.types;
import direct.emit;
import direct.runtime;
import direct.map;
import support.zigmap;
import .function_ops;
import .function_values;
import .function_calls;
import .function_data;
import .function_control;
import .function_storage;
import .function_effects;
import .function_entry;

type Ty = u32;
type Error = blot_direct_types::Error;
type Env = blot_direct_types::Env;
type Module = blot_check_core::Module;
type Generator = blot_direct_emit::Generator;
type Val = blot_direct_emit::Val;
type Vals = blot_direct_emit::Vals;
type Tys = blot_direct_emit::Tys;
type Words = blot_direct_emit::Words;
type InstanceKey = blot_direct_emit::InstanceKey;
type InstanceKind = blot_direct_emit::InstanceKind;
type BindingRef = blot_check_core::BindingRef;
type TId = blot_check_types::Id;
type ValType = blot_direct_writer::ValType;
type Chars = const u8[:];

struct Fn {
    // The module of this body, as `g.units[unit - 1]`.
    unit: u32,
    // The instance's type variables, refined as emission learns the concrete
    // type of each expression (dependent field/element results).
    env: Env = Env {},
    instance_id: u32 = 0,
    evidence_context: u32 = 0,
    // Distinguishes this body's entries in the generator's shared tables.
    serial: u32 = 0,
    // The call node whose arguments are being typed.
    current_call: u32 = 0,
    // Set while evaluating a direct field value of a record literal.
    field_value: bool = false,
    // Nested forwarding resolutions in progress (bounded against cycles).
    forward_depth: u32 = 0,
    // Stores of memory-holding values: a loop body that makes one cannot
    // release per iteration, since older storage may now refer to it.
    memory_stores: u32 = 0,
    // Where this body's part of each generator stack begins. Installed
    // providers are the first `handles_len` entries from `handles_base`:
    // Zig pops the list without restoring it after a failed operand, so the
    // count is kept here and the stack itself is only cut when the body ends.
    handles_base: i64 = 0,
    handles_len: u32 = 0,
    code_base: i64 = 0,
    locals_base: i64 = 0,
    labels_base: i64 = 0,
    parameter_words: u32 = 0,
    bindings: blot_support_zigmap::Map = blot_support_zigmap::Map {},
    depth: u32 = 0,
    // Set when this body allocates environment memory or receives a value
    // that may refer to it; such a body restores the stack on exit unless
    // its result can hold that memory.
    allocates: bool = false,
    // Allocation events so far, so a loop can tell whether its body allocated.
    allocations: u32 = 0,
}

fn op(g: Generator&, value: u8) { g.s.code.push(value); }
fn opIndex(g: Generator&, value: u8, index: u32) {
    g.s.code.push(value);
    blot_direct_writer::uleb(g.s.code, index);
}
fn uleb(g: Generator&, value: u32) { blot_direct_writer::uleb(g.s.code, value); }
fn lget(g: Generator&, id: u32) { opIndex(g, OP_local_get, id); }
fn lset(g: Generator&, id: u32) { opIndex(g, OP_local_set, id); }
fn ltee(g: Generator&, id: u32) { opIndex(g, OP_local_tee, id); }
fn gget(g: Generator&, id: u32) { opIndex(g, OP_global_get, id); }
fn gset(g: Generator&, id: u32) { opIndex(g, OP_global_set, id); }
fn callf(g: Generator&, function: u32) { opIndex(g, OP_call, function); }
fn i32Const(g: Generator&, value: u32) {
    g.s.code.push(OP_i32_const);
    blot_direct_writer::sleb(g.s.code, (value as! i32));
}
fn f32Const(g: Generator&, bits: u32) {
    g.s.code.push(OP_f32_const);
    blot_direct_writer::word(g.s.code, bits);
}
// Opens a void structured block (block, loop or if) and returns its depth.
fn open(g: Generator&, f: Fn&, kind: u8) -> u32 {
    g.s.code.push(kind);
    g.s.code.push(0x40);
    f.depth += 1;
    return f.depth;
}
fn close(g: Generator&, f: Fn&) {
    g.s.code.push(OP_end);
    f.depth -= 1;
}
fn br(g: Generator&, f: const Fn&, value: u8, depth: u32) { opIndex(g, value, f.depth - depth); }

fn local(g: Generator&, f: const Fn&, ty: ValType) -> u32 {
    let id = (g.s.locals.len - f.locals_base) as u32;
    g.s.locals.push(ty);
    return id;
}
fn local32(g: Generator&, f: const Fn&) -> u32 { return local(g, f, VT_i32); }
fn localType(g: const Generator&, f: const Fn&, id: u32) -> ValType { return g.s.locals[f.locals_base + id]; }
fn localCount(g: const Generator&, f: const Fn&) -> u32 { return (g.s.locals.len - f.locals_base) as u32; }
fn tagOf(g: const Generator&, ty: Ty) -> blot_direct_types::Tag { return g.types.node(ty).tag; }
fn unitVal() -> Val { return Val { ty: blot_direct_types::unit }; }
fn neverVal() -> Val { return Val { ty: blot_direct_types::never }; }
// A value of one word that is local `id`.
fn wordVal(g: Generator&, ty: Ty, id: u32) -> Val {
    g.s.words.push(id);
    return Val { ty, (g.s.words.len - 1) as u32, 1 };
}
// A value of type `ty` whose words are `count` words from `start`.
fn valOf1(g: Generator&, ty: Ty, a: u32) -> Val { return wordVal(g, ty, a); }
fn valOf2(g: Generator&, ty: Ty, a: u32, b: u32) -> Val {
    g.s.words.push(a);
    g.s.words.push(b);
    return Val { ty, (g.s.words.len - 2) as u32, 2 };
}
// The length of a value's layout, as Zig's `(try self.layout(ty, id)).len`.
fn layoutLen(g: Generator&, f: const Fn&, ty: Ty, id: u32) -> u32, Error {
    let words, error = g.types.layout(ty);
    if error != blot_direct_types::Error.none { return 0, g.typeFailure(g.units[f.unit - 1], id); }
    return words.len as u32, blot_direct_types::Error.none;
}
fn w(g: const Generator&, value: Val, at: i64) -> u32 { return g.s.words[value.start + at]; }

fn bindPut(g: Generator&, f: Fn&, binding: u32, value: Val) {
    g.s.vals.push(value);
    blot_support_zigmap::put(g.s.map_pool, f.bindings, binding, (g.s.vals.len - 1) as u32);
}
fn bindGet(g: const Generator&, f: const Fn&, binding: u32) -> Val, bool {
    let at, present = blot_support_zigmap::get(g.s.map_pool, f.bindings, binding);
    if !present { return Val {}, false; }
    return g.s.vals[at], true;
}
fn polyKey(f: const Fn&, binding: u32) -> u64 { return blot_direct_emit::key64(f.serial, binding); }

fn fresh(g: Generator&, f: const Fn&, ty: Ty, id: u32) -> Val, Error {
    let words, error = g.types.layout(ty);
    if error != blot_direct_types::Error.none { return Val {}, g.typeFailure(g.units[f.unit - 1], id); }
    let start = g.s.words.len as u32;
    for kind in words { let slot = local(g, f, kind); g.s.words.push(slot); }
    return Val { ty, start, words.len as u32 }, blot_direct_types::Error.none;
}
fn lower(g: Generator&, f: Fn&, ty: TId, id: u32) -> Ty, Error {
    let m .= g.units[f.unit - 1];
    let lowered, error = g.types.lower(m, ty, f.env);
    if error == blot_direct_types::Error.none { return lowered, blot_direct_types::Error.none; }
    // Values refined since the instance began may now decide the enclosing
    // body's obligations (a collection's element).
    let body .= enclosingBody(g, f);
    if body {
        let before = f.env.count;
        let solved = g.solveObligationsPublic(m, body.scheme.obligations, f.env);
        if solved != blot_direct_types::Error.none { return 0, solved; }
        if f.env.count != before {
            let found, error = g.types.lower(m, ty, f.env);
            if error == blot_direct_types::Error.none { g.dropFailure(); return found, blot_direct_types::Error.none; }
        }
    }
    // Variables no use can reach take Unit, consistently for the rest of this
    // instance: no value of such a part exists.
    if holesUnused(g, f, ty, 0) {
        defaultUnused(g, f, ty, 0);
        let found, error = g.types.lower(m, ty, f.env);
        if error == blot_direct_types::Error.none { g.dropFailure(); return found, blot_direct_types::Error.none; }
    }
    return 0, g.typeFailure(m, id);
}
// The named body this instance's code belongs to (a lambda's enclosing named
// instance), in this unit.
fn enclosingBody(g: const Generator&, f: const Fn&) -> const blot_check_core::Body? {
    var key = g.s.instances[f.instance_id].key;
    for step in 0..64 {
        if key.unit != f.unit { return null; }
        if key.kind == blot_direct_emit::InstanceKind.lambda { key = g.s.instances[key.parent].key; }
        else if key.kind == blot_direct_emit::InstanceKind.named { return g.units[f.unit - 1].body(key.id); }
        else { return null; }
    }
    return null;
}
fn typeOf(g: Generator&, f: Fn&, id: u32) -> Ty, Error { return lower(g, f, g.units[f.unit - 1].typeOf(id), id); }
fn push(g: Generator&, value: Val) {
    for at in 0..(value.len as i64) { opIndex(g, OP_local_get, g.s.words[value.start + at]); }
}
// Pops a value of type `ty` from the operand stack into fresh locals.
fn pop(g: Generator&, f: const Fn&, ty: Ty, id: u32) -> Val, Error {
    let value, error = fresh(g, f, ty, id);
    if error != blot_direct_types::Error.none { return value, error; }
    var at = value.len as i64;
    while at != 0 {
        at -= 1;
        opIndex(g, OP_local_set, g.s.words[value.start + at]);
    }
    return value, blot_direct_types::Error.none;
}
fn copy(g: Generator&, f: const Fn&, from: Val, to: Val, id: u32) -> Error {
    if from.ty == blot_direct_types::never { return blot_direct_types::Error.none; }
    if from.len != to.len {
        g.failOpen(g.units[f.unit - 1], id);
        g.put("value layout mismatch (");
        g.put(blot_direct_types::tagName(tagOf(g, from.ty)));
        g.put(" of ");
        g.putNumber(from.len);
        g.put(" words into ");
        g.put(blot_direct_types::tagName(tagOf(g, to.ty)));
        g.put(" of ");
        g.putNumber(to.len);
        g.put(")");
        return g.failClose();
    }
    for at in 0..(from.len as i64) {
        let source = g.s.words[from.start + at];
        let target = g.s.words[to.start + at];
        if source == target { continue; }
        opIndex(g, OP_local_get, source);
        opIndex(g, OP_local_set, target);
    }
    return blot_direct_types::Error.none;
}

// An operand: if it diverges, so does the expression using it.
recursive fn expr(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let value, error = stmt(g, f, id);
    if error != blot_direct_types::Error.none { return value, error; }
    if value.ty == blot_direct_types::never { return value, blot_direct_types::Error.diverged; }
    return value, blot_direct_types::Error.none;
}
// A value that may diverge (statements, branches, bodies). An unsupported
// form is recorded and compiled as a trap, so one build reports every missing
// form; the compilation still fails.
recursive fn stmt(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    // Only the field's own reference node may see the field flag.
    let field_value = f.field_value;
    if id == 0 || m.node(id).tag != blot_check_core::Tag.reference { f.field_value = false; }
    let depth = f.depth;
    let s .= g.s;
    let labels = s.labels.len;
    let value, error = exprInner(g, f, id);
    if error != blot_direct_types::Error.none {
        if error == blot_direct_types::Error.unsupported { g.recordFailure(m, id); }
        // The rest is unreachable; close what the operand left open.
        while f.depth > depth { close(g, f); }
        s.labels.resize(labels);
        op(g, OP_unreachable_);
        f.field_value = field_value;
        return neverVal(), blot_direct_types::Error.none;
    }
    if value.ty != blot_direct_types::never && id != 0 { refine(g, f, m.typeOf(id), value.ty); }
    f.field_value = field_value;
    return value, blot_direct_types::Error.none;
}
// Binds the variables of Core type `ty` that `actual` determines.
fn refine(g: Generator&, f: Fn&, ty: TId, actual: Ty) {
    if ty <= blot_check_types::never { return; }
    if g.types.isClosed(f.unit, ty) { return; }
    g.types.match_(g.units[f.unit - 1], ty, actual, f.env);
}
recursive fn exprInner(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    // Node zero is an absent value, such as a bare `return ()`.
    if id == 0 { return unitVal(), blot_direct_types::Error.none; }
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    match n.tag {
        constant => { return constant(g, f, id); },
        reference => { return reference(g, f, id); },
        scalar => { return scalar(g, f, id); },
        logical => { return logical(g, f, id); },
        call => { return call(g, f, id); },
        associated => { return associated(g, f, id); },
        if_value, if_stmt => { return ifNode(g, f, id); },
        block_ => { return block_(g, f, id); },
        suite => {
            var last = unitVal();
            let children = m.children(id);
            for child in children {
                let value, error = stmt(g, f, child);
                if error != blot_direct_types::Error.none { return value, error; }
                last = value;
            }
            if last.ty == blot_direct_types::never { return last, blot_direct_types::Error.none; }
            return unitVal(), blot_direct_types::Error.none;
        },
        bind => { return bind(g, f, id); },
        return_ => { return returnNode(g, f, id); },
        product, record => { return product(g, f, id); },
        construct => { return construct(g, f, id); },
        project => { return project(g, f, id); },
        match_ => { return match_(g, f, id); },
        pattern_bind => { return patternBind(g, f, id); },
        loop_ => { return loop_(g, f, id); },
        closure => { return closureNode(g, f, id); },
        apply => { return apply(g, f, id); },
        constructor_function => { return constructorFunction(g, f, id); },
        primitive_function => { return primitiveFunction(g, f, id); },
        update => { return update(g, f, id); },
        array => { return arrayLiteral(g, f, id); },
        array_op => { return arrayOp(g, f, id); },
        storage => { return storageOp(g, f, id); },
        record_merge => { return recordMerge(g, f, id); },
        result_associated => { return resultAssociated(g, f, id); },
        contract_method => {
            if !pureContractMethod(m, n.a) {
                return neverVal(), g.fail(m, id, "contract_method expressions are not supported yet");
            }
            return staticContractMethod(g, f, id);
        },
        operation_value => { return operationValue(g, f, id); },
        effect_provider => { return effectProvider(g, f, id); },
        state_provider => { return stateProvider(g, f, id); },
        handle => { return handleNode(g, f, id); },
        break_ => { return breakNode(g, f, id); },
        panic => {
            op(g, OP_unreachable_);
            return neverVal(), blot_direct_types::Error.none;
        },
        _ => {
            g.failOpen(m, id);
            g.put(blot_direct_emit::nodeTagName(n.tag));
            g.put(" expressions are not supported yet");
            return neverVal(), g.failClose();
        },
    }
}
recursive fn bind(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    // A generalized local closure is built at each use, at that use's types;
    // its captures are already immutable values.
    var deferred = false;
    match m.node(n.b).tag {
        closure, constructor_function, primitive_function, reference => { deferred = true; },
        // A pure partial application, rebuilt at each use's types.
        call => { deferred = partialCall(g, f, n.b); },
        apply => { deferred = partialApply(g, f, n.b); },
        _ => {},
    }
    if deferred && m.binding(n.a).scheme.variables.len != 0 {
        g.s.polymorphic.put(polyKey(f, n.a), n.b);
        return unitVal(), blot_direct_types::Error.none;
    }
    let grown, has_grown, error = linearAppend(g, f, n.b);
    if error != blot_direct_types::Error.none { return grown, error; }
    if has_grown {
        bindPut(g, f, n.a, grown);
        return unitVal(), blot_direct_types::Error.none;
    }
    // A generalized local value is computed once: its uses decide the one
    // type it is computed at.
    if m.binding(n.a).scheme.variables.len != 0 {
        let typed = typeByUses(g, f, n.a, n.b);
        if typed != blot_direct_types::Error.none { return neverVal(), typed; }
        // Nothing reads an unused local, so its open types are Unit.
        if uses(g, f, n.a) == 0 { defaultUnused(g, f, m.binding(n.a).ty, 0); }
    }
    let value, error = stmt(g, f, n.b);
    if error != blot_direct_types::Error.none { return value, error; }
    if value.ty != blot_direct_types::never { refine(g, f, m.binding(n.a).ty, value.ty); }
    bindPut(g, f, n.a, value);
    if value.ty == blot_direct_types::never { return value, blot_direct_types::Error.none; }
    return unitVal(), blot_direct_types::Error.none;
}

fn constant(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let ty, error = typeOf(g, f, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    match tagOf(g, ty) {
        unit => { return unitVal(), blot_direct_types::Error.none; },
        f32_ => { f32Const(g, n.a); },
        u32_, boolean => { i32Const(g, n.a); },
        _ => { return neverVal(), g.fail(m, id, "constant of a composite type"); },
    }
    return pop(g, f, ty, id);
}

fn containsText(haystack: Chars, needle: Chars) -> bool {
    if needle.len > haystack.len { return false; }
    for at in 0..haystack.len - needle.len + 1 {
        if haystack[at..at + needle.len] == needle { return true; }
    }
    return false;
}
fn bindingKindName(kind: blot_reuse_principal_interface::Kind) -> Chars {
    match kind { const for <N, V> in variants<blot_reuse_principal_interface::Kind> { V => { return N; }, } }
}
recursive fn reference(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let value, error = referenceInner(g, f, id);
    if error != blot_direct_types::Error.unsupported { return value, error; }
    // Name the binding: a generic function value needs annotations.
    let m .= g.units[f.unit - 1];
    let target = g.resolve(m, m.reference(id));
    let tm .= g.units[target.unit - 1];
    let body .= tm.body(target.binding);
    if body && g.s.has_failure && containsText(g.s.text[g.s.failure.message.start..g.s.failure.message.start + g.s.failure.message.len], "unresolved type variable") {
        let cause = g.s.failure.message;
        g.dropFailure();
        g.failOpen(m, id);
        g.put("value of `");
        g.put(tm.name(body.declaration_name));
        g.put("` (unit ");
        g.putNumber(target.unit);
        g.put(") has a type its uses leave open [");
        g.putText(cause);
        g.put("]");
        return neverVal(), g.failClose();
    }
    return value, error;
}
recursive fn referenceInner(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let ref = m.reference(id);
    if ref.unit == 0 || ref.unit == m.unit {
        let bound, present = bindGet(g, f, ref.binding);
        if present { return bound, blot_direct_types::Error.none; }
        let closure, generalized = g.s.polymorphic.get(polyKey(f, ref.binding));
        if generalized {
            // The closure is built in a copy of the environment that this
            // use's type refines.
            var env = f.env;
            let use_ty, error = typeOf(g, f, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            g.types.match_(m, m.typeOf(closure), use_ty, env);
            let previous = f.env;
            f.env = env;
            let value, error = expr(g, f, closure);
            f.env = previous;
            return value, error;
        }
    }
    let target = g.resolve(m, ref);
    let tm .= g.units[target.unit - 1];
    let binding = tm.binding(target.binding);
    if binding.kind == blot_reuse_principal_interface::Kind.local || binding.kind == blot_reuse_principal_interface::Kind.parameter {
        return neverVal(), g.fail(m, id, "unbound local reference");
    }
    var holed = false;
    var ty, error = g.types.lower(m, m.typeOf(id), f.env);
    if error != blot_direct_types::Error.none {
        // Variables no use here determines may only sit inside function
        // types: such a function can never be called here.
        let partial_ty, error = g.types.lowerHoles(m, m.typeOf(id), f.env);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        if !holesOnlyInFunctions(g, partial_ty) { return neverVal(), g.typeFailure(m, id); }
        holed = true;
        ty = partial_ty;
    }
    // Holes no use can reach: variables the checker left ambiguous, or ones
    // this instance's key already left unused.
    let unused = holed && holesUnused(g, f, m.typeOf(id), 0);
    if holed && tagOf(g, ty) == blot_direct_types::Tag.function {
        // A function stored as a field of a literal record can go unused at a
        // type no use fixes.
        if f.field_value { return trapClosure(g, f, ty, id); }
        if !unused { return neverVal(), g.typeFailure(m, id); }
        // A function with requirements on its type (fields, operators) is
        // never called at a type no use fixes: a call's arguments would fix
        // it. One without requirements may be called with arguments whose
        // open parts are never inspected: those take Unit.
        if requirements(tm, target.binding) { return trapClosure(g, f, ty, id); }
        defaultUnused(g, f, m.typeOf(id), 0);
        let defaulted, error = g.types.lower(m, m.typeOf(id), f.env);
        if error != blot_direct_types::Error.none { return neverVal(), g.typeFailure(m, id); }
        return bindingValue(g, f, target, defaulted, false, id);
    }
    return bindingValue(g, f, target, ty, unused, id);
}
// The value of named binding `target` at concrete type `ty`.
recursive fn bindingValue(g: Generator&, f: Fn&, target: BindingRef, ty: Ty, unused: bool, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let tm .= g.units[target.unit - 1];
    let binding = tm.binding(target.binding);
    let alias, has_alias = primitiveAlias(tm, target.binding);
    if has_alias { return partial(g, f, blot_direct_emit::InstanceKind.primitive, target, ty, Vals {}, id); }
    let body .= tm.body(target.binding);
    if body {
        if body.is_function { return partial(g, f, blot_direct_emit::InstanceKind.partial, target, ty, Vals {}, id); }
        match tagOf(g, ty) {
            array, grow, resize => { return pool(g, f, target, ty, id); },
            _ => {},
        }
        // A constant: its instance computes the value.
        let instance, error = g.namedWith(target, ty, unused, m, id, evidenceContext(g, f, target, id));
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        opIndex(g, OP_call, g.s.instances[instance].function);
        return received(g, f, ty, id);
    }
    g.failOpen(m, id);
    g.put("reference to a ");
    g.put(bindingKindName(binding.kind));
    g.put(" binding without a value");
    return neverVal(), g.failClose();
}
// Whether every variable of Core type `ty` that the environment leaves
// unbound is unused: ambiguous (no scheme quantifies it), or quantified by
// this instance's binding when its key's holes are unused.
recursive fn holesUnused(g: Generator&, f: const Fn&, ty: TId, depth: i64) -> bool {
    if ty <= blot_check_types::never { return true; }
    if depth > 64 { return false; }
    let m .= g.units[f.unit - 1];
    let n = m.types.node(ty);
    match n.tag {
        variable => {
            let bound, present = g.types.envGet(f.env, m.unit, ty);
            if present { return true; }
            if !g.isQuantified(m, ty) { return true; }
            let instance = g.s.instances[f.instance_id];
            if !instance.unused_holes || instance.key.kind != blot_direct_emit::InstanceKind.named || instance.key.unit != m.unit { return false; }
            for variable in m.types.list(m.binding(instance.key.id).scheme.variables) { if variable == ty { return true; } }
            return false;
        },
        bound => {
            let bound_to, present = g.types.envGet(f.env, m.unit, ty);
            return present;
        },
        usage, forall, array, list, cursor => { return holesUnused(g, f, n.a, depth + 1); },
        function => { return holesUnused(g, f, n.a, depth + 1) && holesUnused(g, f, n.b, depth + 1); },
        product => {
            for at in 0..(n.b as i64) { if !holesUnused(g, f, m.types.extra[n.a + at], depth + 1) { return false; } }
            return true;
        },
        record => {
            for index in 0..(n.b as i64) { if !holesUnused(g, f, m.types.recordField(n, index).ty, depth + 1) { return false; } }
            return true;
        },
        nominal => {
            let count = m.types.nominalArguments(n).len;
            for at in 0..count { if !holesUnused(g, f, m.types.nominalArguments(n)[at], depth + 1) { return false; } }
            return true;
        },
        _ => { return false; },
    }
}
// Binds every unbound variable of Core type `ty` to Unit.
recursive fn defaultUnused(g: Generator&, f: Fn&, ty: TId, depth: i64) {
    if ty <= blot_check_types::never || depth > 64 { return; }
    let m .= g.units[f.unit - 1];
    let n = m.types.node(ty);
    match n.tag {
        variable => { g.types.envBind(f.env, m.unit, ty, blot_direct_types::unit); },
        usage, forall, array, list, cursor => { defaultUnused(g, f, n.a, depth + 1); },
        function => {
            defaultUnused(g, f, n.a, depth + 1);
            defaultUnused(g, f, n.b, depth + 1);
        },
        product => { for at in 0..(n.b as i64) { defaultUnused(g, f, m.types.extra[n.a + at], depth + 1); } },
        record => { for index in 0..(n.b as i64) { defaultUnused(g, f, m.types.recordField(n, index).ty, depth + 1); } },
        nominal => {
            let count = m.types.nominalArguments(n).len;
            for at in 0..count { defaultUnused(g, f, m.types.nominalArguments(n)[at], depth + 1); }
        },
        _ => {},
    }
}
// Whether no hole (`never`) of `ty` affects its layout: holes may sit under
// function and container types, whose layouts are fixed.
fn holesOnlyInFunctions(g: Generator&, ty: Ty) -> bool { return layoutFree(g, ty, 0); }
recursive fn layoutFree(g: Generator&, ty: Ty, depth: i64) -> bool {
    if depth > 32 { return false; }
    let n = g.types.node(ty);
    match n.tag {
        never => { return false; },
        function, array, list, cursor, grow, resize, ref, view, link => { return true; },
        tuple => {
            for at in 0..(n.b as i64) { if !layoutFree(g, g.types.words[n.a + at], depth + 1) { return false; } }
            return true;
        },
        record => {
            for index in 0..(n.b as i64) { if !layoutFree(g, g.types.recordField(ty, index).ty, depth + 1) { return false; } }
            return true;
        },
        nominal => {
            let cases, error = g.types.variants(ty);
            if error != blot_direct_types::Error.none { return false; }
            for at in 0..(cases.len as i64) {
                let payload = g.types.variant_payloads[cases.payloads + at];
                if payload != ty && !layoutFree(g, payload, depth + 1) { return false; }
            }
            return true;
        },
        _ => { return true; },
    }
}
// A closure of a type no use determines: calling it traps.
fn trapClosure(g: Generator&, f: Fn&, ty: Ty, id: u32) -> Val, Error {
    // Never called, so one shared `(env) -> ()` body serves every type.
    let key = InstanceKey { blot_direct_emit::InstanceKind.trap, f.unit, 0, blot_direct_types::unit, 0, 0 };
    var instance, present = g.find(key);
    if !present {
        let made, error = g.addInstanceWith(key, Env {}, g.saveTys([blot_direct_types::unit]), blot_direct_types::unit, true, Tys {}, g.units[f.unit - 1], id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        instance = made;
    }
    g.s.trap_closures += 1;
    return makeClosure(g, f, instance, ty, Vals {}, id);
}
// Pops a call result; a result that may refer to scope memory makes this body
// responsible for releasing it.
fn received(g: Generator&, f: Fn&, ty: Ty, id: u32) -> Val, Error {
    let holds, error = g.holdsMemory(ty);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    if holds { noteAllocation(f); }
    return pop(g, f, ty, id);
}

// Allocates `bytes` of scope memory and returns its address local.
fn allocate(g: Generator&, f: Fn&, bytes: u32) -> u32 {
    noteAllocation(f);
    let stack = g.runtime_().stack;
    let address = local32(g, f);
    i32Const(g, bytes);
    opIndex(g, OP_call, stack);
    opIndex(g, OP_local_set, address);
    return address;
}
fn noteAllocation(f: Fn&) {
    f.allocates = true;
    f.allocations += 1;
}
// Code that records the current owner and stack marks into locals.
fn markInto(g: Generator&, out: u8[>..<]&, owner_mark: u32, stack_mark: u32) {
    let owner_top = g.runtime_().owner_top;
    let stack_pointer = g.runtime_().stack_pointer;
    out.push(OP_global_get);
    blot_direct_writer::uleb(out, owner_top);
    out.push(OP_local_set);
    blot_direct_writer::uleb(out, owner_mark);
    out.push(OP_global_get);
    blot_direct_writer::uleb(out, stack_pointer);
    out.push(OP_local_set);
    blot_direct_writer::uleb(out, stack_mark);
}
// Releases every owner and stack byte allocated since the marks.
fn releaseTo(g: Generator&, owner_mark: u32, stack_mark: u32) {
    let release = g.runtime_().release;
    let stack_pointer = g.runtime_().stack_pointer;
    opIndex(g, OP_local_get, owner_mark);
    opIndex(g, OP_call, release);
    opIndex(g, OP_local_get, stack_mark);
    opIndex(g, OP_global_set, stack_pointer);
}
fn storeOp(g: const Generator&, f: const Fn&, local_id: u32) -> u8 {
    if localType(g, f, local_id) == VT_f32 { return OP_f32_store; }
    return OP_i32_store;
}
fn loadOp(g: const Generator&, f: const Fn&, local_id: u32) -> u8 {
    if localType(g, f, local_id) == VT_f32 { return OP_f32_load; }
    return OP_i32_load;
}
// A closure over `captures`, invoking instance `instance` with them.
fn makeClosure(g: Generator&, f: Fn&, instance: u32, ty: Ty, captures: Vals, id: u32) -> Val, Error {
    let slot = g.s.instances[instance].slot;
    var words: i64 = 0;
    for at in 0..(captures.len as i64) { words += g.s.vals[captures.start + at].len; }
    let result, error = fresh(g, f, ty, id);
    if error != blot_direct_types::Error.none { return result, error; }
    i32Const(g, slot);
    opIndex(g, OP_local_set, w(g, result, 0));
    if words == 0 {
        i32Const(g, 0);
        opIndex(g, OP_local_set, w(g, result, 1));
        return result, blot_direct_types::Error.none;
    }
    let address = allocate(g, f, (words * 4) as u32);
    var offset: u32 = 0;
    for at in 0..(captures.len as i64) {
        let capture = g.s.vals[captures.start + at];
        for index in 0..(capture.len as i64) {
            let word = g.s.words[capture.start + index];
            opIndex(g, OP_local_get, address);
            opIndex(g, OP_local_get, word);
            op(g, storeOp(g, f, word));
            uleb(g, 2);
            uleb(g, offset);
            offset += 4;
        }
    }
    opIndex(g, OP_local_get, address);
    opIndex(g, OP_local_set, w(g, result, 1));
    return result, blot_direct_types::Error.none;
}
// Loads a closure's captures from its environment parameter (local 0).
fn loadCaptures(g: Generator&, f: Fn&, captures: Tys, id: u32) -> Vals, Error {
    let out = g.reserveVals(captures.len);
    var offset: u32 = 0;
    for at in 0..(captures.len as i64) {
        let value, error = fresh(g, f, g.s.tys[captures.start + at], id);
        if error != blot_direct_types::Error.none { return out, error; }
        g.s.vals[out.start + at] = value;
        for index in 0..(value.len as i64) {
            let word = g.s.words[value.start + index];
            opIndex(g, OP_local_get, 0);
            op(g, loadOp(g, f, word));
            uleb(g, 2);
            uleb(g, offset);
            opIndex(g, OP_local_set, word);
            offset += 4;
        }
    }
    return out, blot_direct_types::Error.none;
}

// A curried function value: `target` (a named function, primitive alias or
// constructor) applied to its first `arguments`.
fn partial(g: Generator&, f: Fn&, kind: InstanceKind, target: BindingRef, ty: Ty, arguments: Vals, id: u32) -> Val, Error {
    let full, error = curried(g, arguments, ty);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let instance, error = adapter(g, f, kind, target, full, arguments.len, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    return makeClosure(g, f, instance, ty, arguments, id);
}
// The closure taking argument `count` of `target` at function type `full`.
fn adapter(g: Generator&, f: const Fn&, kind: InstanceKind, target: BindingRef, full: Ty, count: i64, id: u32) -> u32, Error {
    let m .= g.units[f.unit - 1];
    var evidence_context: u32 = 0;
    if kind == blot_direct_emit::InstanceKind.partial { evidence_context = evidenceContext(g, f, target, id); }
    let key = InstanceKey { kind, target.unit, target.binding, full, count as u32, evidence_context };
    let found, present = g.find(key);
    if present { return found, blot_direct_types::Error.none; }
    let captures = Tys { g.s.tys.len as u32, count as u32 };
    var rest = full;
    for step in 0..count {
        let arrow = g.types.node(rest);
        if arrow.tag != blot_direct_types::Tag.function { return 0, g.fail(m, id, "partial application beyond the function's arity"); }
        g.s.tys.push(arrow.a);
        rest = arrow.b;
    }
    let arrow = g.types.node(rest);
    if arrow.tag != blot_direct_types::Tag.function { return 0, g.fail(m, id, "function value of a non-function type"); }
    let parameters = g.saveTys([arrow.a]);
    return g.addInstanceWith(key, Env {}, parameters, arrow.b, true, captures, m, id);
}

// The body of a curried adapter: the captured arguments plus this one either
// saturate the target or form the next partial application.
recursive fn adapterBody(g: Generator&, f: Fn&, instance_id: u32, captures: Vals, argument: Val) -> Val, Error {
    let key = g.s.instances[instance_id].key;
    let result = g.s.instances[instance_id].result;
    let arguments = g.reserveVals(captures.len + 1);
    for at in 0..(captures.len as i64) { g.s.vals[arguments.start + at] = g.s.vals[captures.start + at]; }
    g.s.vals[arguments.start + captures.len] = argument;
    let tm .= g.units[key.unit - 1];
    match key.kind {
        partial => {
            let target = BindingRef { key.unit, key.id };
            let body .= tm.body(key.id);
            assert(body);
            let parameters = tm.bodyParameters(body);
            if arguments.len < parameters.len { return partial(g, f, blot_direct_emit::InstanceKind.partial, target, result, arguments, 0); }
            return callTarget(g, f, target, arguments, key.ty, result, 0);
        },
        primitive => {
            var primitive = blot_check_core::Primitive { kind: blot_check_core::PrimitiveKind.scalar, arity: 0 };
            if (key.id & primitive_node_bit) != 0 { primitive = tm.primitive(key.id & 0x7fffffff); }
            else {
                let alias, has_alias = primitiveAlias(tm, key.id);
                assert(has_alias);
                primitive = tm.primitive(alias);
            }
            return applyPrimitive(g, f, primitive, arguments, key.ty, result, BindingRef { key.unit, key.id }, 0);
        },
        constructor => {
            let constructor = tm.constructor(key.id);
            // A record-bodied constructor used as a function takes its fields
            // as a tuple in declared order.
            if tagOf(g, argument.ty) == blot_direct_types::Tag.tuple && constructor.payload != 0 && tm.types.node(constructor.payload).tag == blot_check_types::Tag.record {
                let cases, error = g.types.variants(result);
                if error != blot_direct_types::Error.none { return neverVal(), g.typeFailure(tm, 0); }
                let position, error = variantPosition(g, f, cases, constructor.tag, 0);
                if error != blot_direct_types::Error.none { return neverVal(), error; }
                let payload = g.types.variant_payloads[cases.payloads + position];
                if tagOf(g, payload) == blot_direct_types::Tag.record {
                    let declared, error = declaredRecord(g, f, tm, argument, payload, constructor.payload);
                    if error != blot_direct_types::Error.none { return neverVal(), error; }
                    return wrapVariant(g, f, result, constructor.tag, declared, 0);
                }
            }
            return wrapVariant(g, f, result, constructor.tag, argument, 0);
        },
        _ => { abort("adapter of another instance kind"); },
    }
}
recursive fn closureNode(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let ty, error = g.types.lower(m, m.typeOf(id), f.env);
    if error != blot_direct_types::Error.none { return inferredClosure(g, f, id); }
    let arrow = g.types.node(ty);
    if arrow.tag != blot_direct_types::Tag.function { return neverVal(), g.fail(m, id, "closure of a non-function type"); }
    let capture_ids = m.closureCaptures(id);
    let captures = g.reserveVals(capture_ids.len);
    for binding, at in capture_ids {
        let value, error = captureValue(g, f, binding, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        g.s.vals[captures.start + at] = value;
    }
    let key = InstanceKey { blot_direct_emit::InstanceKind.lambda, m.unit, id, ty, f.instance_id, f.evidence_context };
    var instance, present = g.find(key);
    if !present {
        let capture_types = Tys { g.s.tys.len as u32, captures.len };
        for at in 0..(captures.len as i64) { g.s.tys.push(g.s.vals[captures.start + at].ty); }
        let parameters = g.saveTys([arrow.a]);
        let made, error = g.addInstanceWith(key, f.env, parameters, arrow.b, true, capture_types, m, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        instance = made;
    }
    return makeClosure(g, f, instance, ty, captures, id);
}

// A lambda whose parameter type is known but whose result only its body
// determines: its instance is emitted now to learn the result.
recursive fn inferredClosure(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let info = m.closure(id);
    let parameter, error = lower(g, f, info.parameter.ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let capture_ids = m.closureCaptures(id);
    let captures = g.reserveVals(capture_ids.len);
    for binding, at in capture_ids {
        let value, error = captureValue(g, f, binding, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        g.s.vals[captures.start + at] = value;
    }
    let marker, error = g.types.function(parameter, blot_direct_types::never);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let key = InstanceKey { blot_direct_emit::InstanceKind.lambda, m.unit, id, marker, f.instance_id, f.evidence_context };
    var instance, present = g.find(key);
    if !present {
        let capture_types = Tys { g.s.tys.len as u32, captures.len };
        for at in 0..(captures.len as i64) { g.s.tys.push(g.s.vals[captures.start + at].ty); }
        let parameters = g.saveTys([parameter]);
        let made, error = g.inferClosure(key, f.env, parameters, capture_types, m, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        instance = made;
    }
    let ty, error = g.types.function(parameter, g.s.instances[instance].result);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    refine(g, f, m.typeOf(id), ty);
    return makeClosure(g, f, instance, ty, captures, id);
}
// An effect operation as a function value: a closure over its trampoline,
// which finds the newest provider frame for it.
fn operationValue(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let info = m.operationValue(id);
    let operation, error = operationType(g, f, info.identity, m.operationValueArguments(id), id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let signature, error = lower(g, f, info.signature, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let arrow = g.types.node(signature);
    if arrow.tag != blot_direct_types::Tag.function { return neverVal(), g.fail(m, id, "operation of a non-function type"); }
    let operation_id = g.operationId(operation);
    let key = InstanceKey { blot_direct_emit::InstanceKind.operation, 0, operation_id, signature, 0, 0 };
    var instance, present = g.find(key);
    if !present {
        let made, error = g.addInstanceWith(key, Env {}, g.saveTys([arrow.a]), arrow.b, true, Tys {}, m, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        instance = made;
    }
    return makeClosure(g, f, instance, signature, Vals {}, id);
}
// The lowered nominal type naming an effect operation and its arguments, as a
// provider's type names it.
fn operationType(g: Generator&, f: Fn&, identity: blot_check_types::NominalIdentity, arguments: const TId[:], id: u32) -> Ty, Error {
    let payload = blot_direct_emit::Words { g.s.words.len as u32, (arguments.len + 2) as u32 };
    g.s.words.push(identity.unit);
    g.s.words.push(identity.decl);
    for argument in arguments { g.s.words.push(0); }
    for argument, at in arguments {
        let lowered, error = lower(g, f, argument, id);
        if error != blot_direct_types::Error.none { return 0, error; }
        g.s.words[payload.start + 2 + at] = lowered;
    }
    return g.types.intern(blot_direct_types::Tag.nominal, g.s.words[payload.start..payload.start + payload.len]);
}
