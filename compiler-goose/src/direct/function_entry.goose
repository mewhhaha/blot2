// Instance bodies, exported entries and the host boundary of the direct
// backend's function emitter (compiler/src/direct/function.zig).
namespace blot_direct_function;
import .function;

// A body that begins at the top of the generator's stacks.
fn newFn(g: Generator&, unit: u32, instance_id: u32) -> Fn {
    g.s.serial += 1;
    return Fn { sites_base:blot_direct_relocations::mark(), unit: unit, instance_id: instance_id, serial: g.s.serial, handles_base: g.s.handles.len, handle_cells_base: g.s.handle_cells_len, code_base: g.s.code.len, locals_base: g.s.locals.len, labels_base: g.s.labels.len };
}

// ----- host boundary -----------------------------------------------------

// A fresh fixed array from the host packet at `packet` (a local). When
// `zero_copy` is true (pure non-callback entry parameter), open the transport
// slice in place; `toPacket` copies with overlap-safe `memory.copy` and skips
// zeroing so returning or aliasing the input remains sound.
fn fromPacket(g: Generator&, f: Fn&, ty: Ty, packet: u32, zero_copy: bool = false) -> Val, Error {
    let rt = g.runtime_();
    let length = local32(g, f);
    lget(g, packet);
    callf(g, rt.packet_length);
    lset(g, length);
    let array_ty, error = g.types.intern(blot_direct_types::Tag.array, [g.types.node(ty).a]);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    if zero_copy {
        let base = local32(g, f);
        lget(g, packet);
        i32Const(g, 4);
        op(g, OP_i32_add);
        lset(g, base);
        let bytes = emitScaledBytes(g, f, length, 4);
        lget(g, bytes);
        i32Const(g, rt.layout.transport_end);
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
    i32Const(g, 4);
    op(g, OP_i32_mul);
    op(g, OP_prefix_fc);
    uleb(g, 10);
    op(g, 0);
    op(g, 0);
    return Val { ty, handle.start, handle.len }, blot_direct_types::Error.none;
}
// Copies an array into a fresh host packet; returns its address local.
fn toPacket(g: Generator&, f: Fn&, value: Val, id: u32) -> u32, Error {
    let rt = g.runtime_();
    let length, error = lengthOf(g, f, value, id);
    if error != blot_direct_types::Error.none { return 0, error; }
    let max_words = (rt.layout.transport_end - rt.layout.transport_base - 4) / 4;
    lget(g, length);
    i32Const(g, max_words);
    op(g, OP_i32_gt_u);
    trap(g, f);
    let bytes = emitScaledBytes(g, f, length, 4);
    let packet = constLocal(g, f, rt.layout.transport_base);
    i32Const(g, rt.layout.transport_base + 4);
    lget(g, bytes);
    op(g, OP_i32_add);
    gset(g, rt.transport_top);
    let opened = open(g, f, OP_block);
    lget(g, length);
    op(g, OP_i32_eqz);
    opIndex(g, OP_br_if, 0);
    let base = baseOf(g, f, value);
    i32Const(g, rt.layout.transport_base + 4);
    lget(g, base);
    lget(g, bytes);
    op(g, OP_prefix_fc);
    uleb(g, 10);
    op(g, 0);
    op(g, 0);
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
    s.labels.resize(labels_mark);
    s.handles.resize(handles_mark);
    s.handle_cells_len = handle_cells_mark;
    return error;
}
recursive fn emitInstanceBody(g: Generator&, id: u32) -> Error {
    let key = g.s.instances[id].key;
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
        for parameter, at in body_parameters { bindPut(g, f, parameter.binding, g.s.vals[inputs.start + at]); }
        root = body.root;
    } else if key.kind == blot_direct_emit::InstanceKind.lambda {
        let info = m.closure(key.id);
        let captured = m.closureCaptures(key.id);
        for binding, at in captured {
            let cap_val = g.s.vals[captures.start + at];
            bindPut(g, f, binding, cap_val);
            if tagOf(g, cap_val.ty) == blot_direct_types::Tag.cell {
                blot_support_zigmap::put(g.s.map_pool, f.with_cells, binding, g.types.node(cap_val.ty).a);
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
                    gget(g, rt.fork_owner_mark);
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
    close(g, f);
    // An inferred result is the type of the first value the body delivers.
    var result = neverVal();
    if g.s.slots[slot].present { result = g.s.slots[slot].value; }
    if g.s.instances[id].inferring { g.s.instances[id].result = result.ty; }
    // Stored memory-holding values may now be reachable from older storage.
    var release = false;
    if f.allocates {
        let holds, error = g.holdsMemory(g.s.instances[id].result);
        if error != blot_direct_types::Error.none { return error; }
        release = !holds && f.memory_stores == 0;
    }
    if release { releaseTo(g, owner_mark, stack_mark); }
    if result.ty == blot_direct_types::never { op(g, OP_unreachable_); } else { push(g, result); }
    op(g, OP_end);
    finishWith(g, g.s.instances[id].function, f, release, owner_mark, stack_mark);
    return blot_direct_types::Error.none;
}

// Encodes the body and gives the generator's stacks back. Only for bodies
// that are not nested in another one (exports and start functions).
fn finish(g: Generator&, function: u32, f: const Fn&) {
    finishWith(g, function, f, false, 0, 0);
    g.s.code.resize(f.code_base);
    g.s.locals.resize(f.locals_base);
    g.s.labels.resize(f.labels_base);
    g.s.handles.resize(f.handles_base);
    g.s.handle_cells_len = f.handle_cells_base;
}

var finish_body_scratch: u8[>..<] = [];

// Encodes the body: local declarations (in runs of one type), the marks a
// releasing body records on entry, then code.
fn finishWith(g: Generator&, function: u32, f: const Fn&, release: bool, owner_mark: u32, stack_mark: u32) {
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
    if release { markInto(g, finish_body_scratch, owner_mark, stack_mark); }
    blot_direct_relocations::finishBody(f.sites_base,(finish_body_scratch.len-mark)-f.code_base,(function-g.module.imports.len) as u32,g.module.text.len);
    blot_direct_writer::raw(finish_body_scratch, g.s.code[f.code_base..g.s.code.len]);
    blot_direct_writer::setBody(g.module, function, finish_body_scratch[mark..]);
    finish_body_scratch.resize(mark);
}

// ----- ABI ---------------------------------------------------------------

// ABI 8 value kinds (runtime_ir.Scalar), and callback import names.
enum Abi { unit, u32_, bool_, f32_, array_u32, array_f32 }
fn abiCode(kind: Abi) -> u8 {
    match kind {
        unit => { return 0; },
        u32_ => { return 1; },
        bool_ => { return 2; },
        f32_ => { return 3; },
        array_u32 => { return 5; },
        array_f32 => { return 6; },
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
    }
}
fn abiKind(g: const Generator&, ty: Ty) -> Abi, bool {
    let n = g.types.node(ty);
    match n.tag {
        unit => { return Abi.unit, true; },
        u32_ => { return Abi.u32_, true; },
        boolean => { return Abi.bool_, true; },
        f32_ => { return Abi.f32_, true; },
        array, grow, resize => {
            let element = g.types.node(n.a).tag;
            if element == blot_direct_types::Tag.u32_ { return Abi.array_u32, true; }
            if element == blot_direct_types::Tag.f32_ { return Abi.array_f32, true; }
            return Abi.unit, false;
        },
        _ => { return Abi.unit, false; },
    }
}
fn abiMachine(kind: Abi) -> ValType {
    if kind == Abi.f32_ { return VT_f32; }
    return VT_i32;
}
fn isArray(kind: Abi) -> bool { return kind == Abi.array_u32 || kind == Abi.array_f32; }
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

// Recovers temporaries and providers a trapped earlier call left behind.
fn resetEntry(g: Generator&) {
    let rt = g.runtime_();
    let release = rt.release;
    let stack_base = rt.layout.stack_base;
    let stack_pointer = rt.stack_pointer;
    let effect_context = rt.effect_context;
    i32Const(g, 1);
    callf(g, release);
    i32Const(g, stack_base);
    gset(g, stack_pointer);
    i32Const(g, 0);
    gset(g, effect_context);
    if rt.has_fork {
        i32Const(g, 0);
        gset(g, rt.fork_owner_mark);
        i32Const(g, rt.layout.undo_base);
        gset(g, rt.undo_sp);
    }
}
fn releaseEntry(g: Generator&) {
    let release = g.runtime_().release;
    i32Const(g, 1);
    callf(g, release);
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
    let name = m.name(body.export_name);
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
            g.put("entry parameters of type ");
            g.put(blot_direct_types::tagName(g.types.node(parameter).tag));
            g.put(" are not supported");
            return g.failClose();
        }
        parameter_abi = kind;
    }
    let result_abi, supported = abiKind(g, result_ty);
    if !supported {
        g.failOpenCode(m, body.root, blot_check_diagnostic_code::Code.entry_type);
        g.put("entry results of type ");
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
    let name = m.name(body.export_name);
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
