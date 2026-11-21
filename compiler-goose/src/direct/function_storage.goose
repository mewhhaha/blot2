// Storage: flat memory forms, containers and array operations of the direct
// backend's function emitter (compiler/src/direct/function.zig).
namespace blot_direct_function;
import .function;
type ArrayOp = blot_backend_collection_ops::Op;

fn isBoxed(g: Generator&, f: const Fn&, ty: Ty, id: u32) -> bool, Error {
    let boxed, error = g.types.boxed(ty);
    if error != blot_direct_types::Error.none { return false, g.typeFailure(g.units[f.unit - 1], id); }
    return boxed, blot_direct_types::Error.none;
}
fn flatBytes(g: Generator&, f: const Fn&, ty: Ty, id: u32) -> u32, Error {
    let bytes, error = g.types.flatBytes(ty);
    if error != blot_direct_types::Error.none { return 0, g.typeFailure(g.units[f.unit - 1], id); }
    return bytes, blot_direct_types::Error.none;
}
// A fresh scope block holding one boxed value of `ty`.
fn newBlock(g: Generator&, f: Fn&, ty: Ty, id: u32) -> u32, Error {
    let bytes, error = blockBytes(g, f, ty, id);
    if error != blot_direct_types::Error.none { return 0, error; }
    return allocate(g, f, bytes), blot_direct_types::Error.none;
}
// Bytes of a boxed value's block.
fn blockBytes(g: Generator&, f: const Fn&, ty: Ty, id: u32) -> u32, Error {
    let bytes, error = g.types.blockBytes(ty);
    if error != blot_direct_types::Error.none { return 0, g.typeFailure(g.units[f.unit - 1], id); }
    return bytes, blot_direct_types::Error.none;
}
// Whether `ty` is boxed and copied by contents (recursive types are held by
// their pointer, which is their flat form).
fn copiedBox(g: Generator&, f: const Fn&, ty: Ty, id: u32) -> bool, Error {
    let boxed, error = isBoxed(g, f, ty, id);
    if error != blot_direct_types::Error.none { return false, error; }
    if !boxed { return false, blot_direct_types::Error.none; }
    let is_recursive, error = g.types.isRecursive(ty);
    if error != blot_direct_types::Error.none { return false, g.typeFailure(g.units[f.unit - 1], id); }
    return !is_recursive, blot_direct_types::Error.none;
}
fn memoryCopyOp(g: Generator&) {
    op(g, OP_prefix_fc);
    uleb(g, 10);
    op(g, 0);
    op(g, 0);
}
fn memoryCopy(g: Generator&, to: u32, to_offset: u32, from: u32, bytes: u32) {
    lget(g, to);
    if to_offset != 0 {
        i32Const(g, to_offset);
        op(g, OP_i32_add);
    }
    lget(g, from);
    i32Const(g, bytes);
    memoryCopyOp(g);
}
// Writes `value` in flat form at `base + offset`.
fn writeFlat(g: Generator&, f: const Fn&, base: u32, offset: u32, value: Val, id: u32) -> Error {
    if value.ty == blot_direct_types::never { return blot_direct_types::Error.none; }
    let copied, error = copiedBox(g, f, value.ty, id);
    if error != blot_direct_types::Error.none { return error; }
    if copied {
        let bytes, error = blockBytes(g, f, value.ty, id);
        if error != blot_direct_types::Error.none { return error; }
        memoryCopy(g, base, offset, w(g, value, 0), bytes);
        return blot_direct_types::Error.none;
    }
    storeAt(g, f, base, offset, value);
    return blot_direct_types::Error.none;
}
// Reads a value of `ty` at `base + offset` of an immutable block: a boxed
// value shares the block, others load into locals.
fn readFlat(g: Generator&, f: const Fn&, base: u32, offset: u32, ty: Ty, id: u32) -> Val, Error {
    let copied, error = copiedBox(g, f, ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    if copied {
        let pointer = local32(g, f);
        lget(g, base);
        i32Const(g, offset);
        op(g, OP_i32_add);
        lset(g, pointer);
        return valOf1(g, ty, pointer), blot_direct_types::Error.none;
    }
    return loadAt(g, f, base, offset, ty, id);
}
// Element reads copy: storage elements change through their owner.
fn loadElement(g: Generator&, f: Fn&, address: u32, offset: u32, ty: Ty, id: u32) -> Val, Error {
    let copied, error = copiedBox(g, f, ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    if copied {
        let memory_block, error = newBlock(g, f, ty, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        let bytes, error = blockBytes(g, f, ty, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        memoryCopy(g, memory_block, 0, address, bytes);
        if offset != 0 { return neverVal(), g.fail(g.units[f.unit - 1], id, "offset boxed element read"); }
        return valOf1(g, ty, memory_block), blot_direct_types::Error.none;
    }
    return loadAt(g, f, address, offset, ty, id);
}
// Byte offset of record field `index` in flat form.
fn fieldOffset(g: Generator&, f: const Fn&, ty: Ty, index: i64, id: u32) -> u32, Error {
    var offset: u32 = 0;
    for before in 0..index {
        let bytes, error = flatBytes(g, f, g.types.recordField(ty, before).ty, id);
        if error != blot_direct_types::Error.none { return 0, error; }
        offset += bytes;
    }
    return offset, blot_direct_types::Error.none;
}
fn itemOffset(g: Generator&, f: const Fn&, ty: Ty, index: i64, id: u32) -> u32, Error {
    var offset: u32 = 0;
    let n = g.types.node(ty);
    for before in 0..index {
        let bytes, error = flatBytes(g, f, g.types.words[n.a + before], id);
        if error != blot_direct_types::Error.none { return 0, error; }
        offset += bytes;
    }
    return offset, blot_direct_types::Error.none;
}
// Field `position` of a record value, boxed or not.
fn recordField(g: Generator&, f: const Fn&, record: Val, position: i64, id: u32) -> Val, Error {
    let field_ty = g.types.recordField(record.ty, position).ty;
    let boxed, error = isBoxed(g, f, record.ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    if boxed {
        let offset, error = fieldOffset(g, f, record.ty, position, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        return readFlat(g, f, w(g, record, 0), offset, field_ty, id);
    }
    let start, len, error = fieldSlice(g, f, record.ty, position, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    return Val { field_ty, record.start + start, len }, blot_direct_types::Error.none;
}
fn tupleItem(g: Generator&, f: const Fn&, tuple: Val, index: i64, id: u32) -> Val, Error {
    let n = g.types.node(tuple.ty);
    let item_ty = g.types.words[n.a + index];
    let boxed, error = isBoxed(g, f, tuple.ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    if boxed {
        let offset, error = itemOffset(g, f, tuple.ty, index, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        return readFlat(g, f, w(g, tuple, 0), offset, item_ty, id);
    }
    var start: u32 = 0;
    for before in 0..index {
        let width, error = layoutLen(g, f, g.types.words[n.a + before], id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        start += width;
    }
    let width, error = layoutLen(g, f, item_ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    return Val { item_ty, tuple.start + start, width }, blot_direct_types::Error.none;
}
fn wordBytes(kind: ValType) -> u32 {
    if kind == VT_v128 { return 16; }
    return 4;
}
// Bytes per element of a container holding `element`.
fn stride(g: Generator&, f: const Fn&, element: Ty, id: u32) -> u32, Error {
    let bytes, error = flatBytes(g, f, element, id);
    if error != blot_direct_types::Error.none { return 0, error; }
    return max(bytes, 4), blot_direct_types::Error.none;
}
fn storeAt(g: Generator&, f: const Fn&, address: u32, offset: u32, value: Val) {
    var at = offset;
    for index in 0..(value.len as i64) {
        let word = g.s.words[value.start + index];
        let kind = localType(g, f, word);
        lget(g, address);
        lget(g, word);
        if kind == VT_f32 { op(g, OP_f32_store); }
        else if kind == VT_v128 { op(g, OP_prefix_fd); uleb(g, 11); }
        else { op(g, OP_i32_store); }
        if kind == VT_v128 { uleb(g, 4); } else { uleb(g, 2); }
        uleb(g, at);
        at += wordBytes(kind);
    }
}
fn loadAt(g: Generator&, f: const Fn&, address: u32, offset: u32, ty: Ty, id: u32) -> Val, Error {
    let value, error = fresh(g, f, ty, id);
    if error != blot_direct_types::Error.none { return value, error; }
    var at = offset;
    for index in 0..(value.len as i64) {
        let word = g.s.words[value.start + index];
        let kind = localType(g, f, word);
        lget(g, address);
        if kind == VT_f32 { op(g, OP_f32_load); }
        else if kind == VT_v128 { op(g, OP_prefix_fd); uleb(g, 0); }
        else { op(g, OP_i32_load); }
        if kind == VT_v128 { uleb(g, 4); } else { uleb(g, 2); }
        uleb(g, at);
        lset(g, word);
        at += wordBytes(kind);
    }
    return value, blot_direct_types::Error.none;
}
fn elementOf(g: Generator&, f: const Fn&, ty: Ty, id: u32) -> Ty, Error {
    match tagOf(g, ty) {
        array, list, grow, resize, view, ref, link => { return g.types.node(ty).a, blot_direct_types::Error.none; },
        _ => {
            g.failOpen(g.units[f.unit - 1], id);
            g.put("storage operation on a ");
            g.put(blot_direct_types::tagName(tagOf(g, ty)));
            return 0, g.failClose();
        },
    }
}
fn growable(g: const Generator&, ty: Ty) -> bool {
    let tag = tagOf(g, ty);
    return tag == blot_direct_types::Tag.grow || tag == blot_direct_types::Tag.resize;
}
fn boolWord(value: bool) -> u32 { if value { return 1; } return 0; }
// A fresh owner of `ty` (a container) with `length` zeroed elements.
fn create(g: Generator&, f: Fn&, ty: Ty, length: u32, id: u32) -> Val, Error {
    let create_function = g.runtime_().create;
    noteAllocation(f);
    let element, error = elementOf(g, f, ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    lget(g, length);
    let step, error = stride(g, f, element, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    i32Const(g, step);
    i32Const(g, boolWord(growable(g, ty)));
    callf(g, create_function);
    return pop(g, f, ty, id);
}
// The address of element 0 of an owner handle.
fn baseOf(g: Generator&, f: const Fn&, handle: Val) -> u32 {
    let check = g.runtime_().check;
    let base = local32(g, f);
    lget(g, w(g, handle, 0));
    lget(g, w(g, handle, 1));
    callf(g, check);
    op(g, OP_i32_load);
    uleb(g, 2);
    uleb(g, blot_direct_runtime::entry_base);
    lset(g, base);
    return base;
}
fn lengthOf(g: Generator&, f: const Fn&, container: Val, id: u32) -> u32, Error {
    let length_function = g.runtime_().length;
    if tagOf(g, container.ty) == blot_direct_types::Tag.view { return w(g, container, 3), blot_direct_types::Error.none; }
    let element, error = elementOf(g, f, container.ty, id);
    if error != blot_direct_types::Error.none { return 0, error; }
    let length = local32(g, f);
    lget(g, w(g, container, 0));
    lget(g, w(g, container, 1));
    callf(g, length_function);
    lset(g, length);
    return length, blot_direct_types::Error.none;
}
// The checked address of element `index` (a local) of a container or view;
// views check their own range first.
fn elementAddress(g: Generator&, f: Fn&, container: Val, index: u32, id: u32) -> u32, Error {
    let address_function = g.runtime_().address;
    let element, error = elementOf(g, f, container.ty, id);
    if error != blot_direct_types::Error.none { return 0, error; }
    let range = f.checked_range;
    if range.slot != 0xffffffff && index == range.index && tagOf(g, container.ty) == blot_direct_types::Tag.array &&
        w(g, container, 0) == range.slot && w(g, container, 1) == range.generation {
        let step, error = stride(g, f, element, id);
        if error != blot_direct_types::Error.none { return 0, error; }
        let address = local32(g, f);
        lget(g, range.base);
        lget(g, index);
        i32Const(g, step);
        op(g, OP_i32_mul);
        op(g, OP_i32_add);
        lset(g, address);
        return address, blot_direct_types::Error.none;
    }
    var position = index;
    if tagOf(g, container.ty) == blot_direct_types::Tag.view {
        lget(g, index);
        lget(g, w(g, container, 3));
        op(g, OP_i32_ge_u);
        trap(g, f);
        position = local32(g, f);
        lget(g, w(g, container, 2));
        lget(g, index);
        op(g, OP_i32_add);
        lset(g, position);
    }
    let address = local32(g, f);
    lget(g, w(g, container, 0));
    lget(g, w(g, container, 1));
    lget(g, position);
    let step, error = stride(g, f, element, id);
    if error != blot_direct_types::Error.none { return 0, error; }
    i32Const(g, step);
    callf(g, address_function);
    lset(g, address);
    return address, blot_direct_types::Error.none;
}
// Traps when the i32 on the stack is nonzero.
fn trap(g: Generator&, f: Fn&) {
    let opened = open(g, f, OP_if_);
    op(g, OP_unreachable_);
    close(g, f);
}
fn scalarLocal(g: Generator&, f: const Fn&, value: Val, id: u32) -> u32, Error {
    if value.len != 1 { return 0, g.fail(g.units[f.unit - 1], id, "expected a scalar"); }
    return w(g, value, 0), blot_direct_types::Error.none;
}
fn readElement(g: Generator&, f: Fn&, container: Val, index: u32, id: u32) -> Val, Error {
    let address, error = elementAddress(g, f, container, index, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let element, error = elementOf(g, f, container.ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    return loadElement(g, f, address, 0, element, id);
}
fn constLocal(g: Generator&, f: const Fn&, value: u32) -> u32 {
    let made = local32(g, f);
    i32Const(g, value);
    lset(g, made);
    return made;
}

recursive fn arrayLiteral(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let children = m.children(id);
    // An empty literal whose element type no use can fix holds no element:
    // its unused variables are Unit.
    var ty, error = g.types.lower(m, m.typeOf(id), f.env);
    if error != blot_direct_types::Error.none {
        if !holesUnused(g, f, m.typeOf(id), 0) { return neverVal(), g.typeFailure(m, id); }
        defaultUnused(g, f, m.typeOf(id), 0);
        let defaulted, error = lower(g, f, m.typeOf(id), id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        ty = defaulted;
    }
    let values = g.reserveVals(children.len);
    for child, at in children {
        let value, error = expr(g, f, child);
        if error != blot_direct_types::Error.none { return value, error; }
        g.s.vals[values.start + at] = value;
    }
    if f.scratch_cut.target == id {
        releaseTo(g, f.scratch_cut.owner, f.scratch_cut.stack);
        f.scratch_cut = ScratchCut {};
    }
    return arrayFromValues(g, f, ty, values, id);
}

fn arrayFromValues(g: Generator&, f: Fn&, ty: Ty, values: Vals, id: u32) -> Val, Error {
    let count = constLocal(g, f, values.len);
    let handle, error = create(g, f, ty, count, id);
    if error != blot_direct_types::Error.none { return handle, error; }
    if values.len == 0 { return handle, blot_direct_types::Error.none; }
    let base = baseOf(g, f, handle);
    let element, error = elementOf(g, f, ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let step, error = stride(g, f, element, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    for index in 0..(values.len as i64) {
        let written = writeFlat(g, f, base, (index as u32) * step, g.s.vals[values.start + index], id);
        if written != blot_direct_types::Error.none { return neverVal(), written; }
    }
    return handle, blot_direct_types::Error.none;
}

recursive fn arrayOp(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let operation = m.arrayOperation(id);
    let children = m.children(id);
    // Operations whose operands decide the result type look at them when the
    // node's own type is still open.
    let declared, declared_error = g.types.lower(m, m.typeOf(id), f.env);
    let has_declared = declared_error == blot_direct_types::Error.none;
    match operation {
        length, get, fill, generate => {},
        _ => { if !has_declared { return neverVal(), g.typeFailure(m, id); } },
    }
    var ty = blot_direct_types::never;
    if has_declared { ty = declared; }
    match operation {
        length => {
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let length, error = lengthOf(g, f, container, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            return valOf1(g, blot_direct_types::u32_, length), blot_direct_types::Error.none;
        },
        get => {
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let position, error = expr(g, f, children[1]);
            if error != blot_direct_types::Error.none { return position, error; }
            let index, error = scalarLocal(g, f, position, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            return readElement(g, f, container, index, id);
        },
        identity, convert => {
            let value, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return value, error; }
            if operation == blot_backend_collection_ops::Op.identity { return Val { ty, value.start, value.len }, blot_direct_types::Error.none; }
            return copyContainer(g, f, value, ty, id);
        },
        set => {
            // A new array with one element replaced; the input is unchanged.
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let position, error = expr(g, f, children[1]);
            if error != blot_direct_types::Error.none { return position, error; }
            let index, error = scalarLocal(g, f, position, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let value, error = expr(g, f, children[2]);
            if error != blot_direct_types::Error.none { return value, error; }
            let replaced, error = copyContainer(g, f, container, ty, id);
            if error != blot_direct_types::Error.none { return replaced, error; }
            let address, error = elementAddress(g, f, replaced, index, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let written = writeFlat(g, f, address, 0, value, id);
            if written != blot_direct_types::Error.none { return neverVal(), written; }
            return replaced, blot_direct_types::Error.none;
        },
        fill, generate => {
            let counted, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return counted, error; }
            let count, error = scalarLocal(g, f, counted, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let source, error = expr(g, f, children[1]);
            if error != blot_direct_types::Error.none { return source, error; }
            var ty_ = declared;
            if !has_declared {
                var element = source.ty;
                if operation != blot_backend_collection_ops::Op.fill { element = g.types.node(source.ty).b; }
                if operation == blot_backend_collection_ops::Op.generate && tagOf(g, source.ty) != blot_direct_types::Tag.function { return neverVal(), g.typeFailure(m, id); }
                let container, error = g.types.lowerHoles(m, m.typeOf(id), f.env);
                if error != blot_direct_types::Error.none { return neverVal(), error; }
                let built, error = g.types.intern(tagOf(g, container), [element]);
                if error != blot_direct_types::Error.none { return neverVal(), error; }
                refine(g, f, m.typeOf(id), built);
                ty_ = built;
            }
            let handle, error = create(g, f, ty_, count, id);
            if error != blot_direct_types::Error.none { return handle, error; }
            let base = baseOf(g, f, handle);
            let element, error = elementOf(g, f, ty_, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let step, error = stride(g, f, element, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let index = constLocal(g, f, 0);
            let exit = open(g, f, OP_block);
            let top = open(g, f, OP_loop);
            lget(g, index);
            lget(g, count);
            op(g, OP_i32_ge_u);
            br(g, f, OP_br_if, exit);
            var value = source;
            if operation != blot_backend_collection_ops::Op.fill {
                let applied, error = applyClosure(g, f, source, valOf1(g, blot_direct_types::u32_, index), id);
                if error != blot_direct_types::Error.none { return applied, error; }
                value = applied;
            }
            let address = local32(g, f);
            lget(g, base);
            lget(g, index);
            i32Const(g, step);
            op(g, OP_i32_mul);
            op(g, OP_i32_add);
            lset(g, address);
            let written = writeFlat(g, f, address, 0, value, id);
            if written != blot_direct_types::Error.none { return neverVal(), written; }
            lget(g, index);
            i32Const(g, 1);
            op(g, OP_i32_add);
            lset(g, index);
            br(g, f, OP_br, top);
            close(g, f);
            close(g, f);
            return handle, blot_direct_types::Error.none;
        },
        append, prepend, concat => {
            let first, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return first, error; }
            let second, error = expr(g, f, children[1]);
            if error != blot_direct_types::Error.none { return second, error; }
            let element, error = elementOf(g, f, ty, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let parts = g.reserveVals(2);
            if operation == blot_backend_collection_ops::Op.prepend {
                g.s.vals[parts.start] = second;
                g.s.vals[parts.start + 1] = first;
            } else {
                g.s.vals[parts.start] = first;
                g.s.vals[parts.start + 1] = second;
            }
            return joined(g, f, ty, element, parts, operation == blot_backend_collection_ops::Op.concat, id);
        },
        slice => {
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let started, error = expr(g, f, children[1]);
            if error != blot_direct_types::Error.none { return started, error; }
            let start, error = scalarLocal(g, f, started, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let counted, error = expr(g, f, children[2]);
            if error != blot_direct_types::Error.none { return counted, error; }
            let count, error = scalarLocal(g, f, counted, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let length, error = lengthOf(g, f, container, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            // start + count <= length, without overflow.
            lget(g, start);
            lget(g, length);
            op(g, OP_i32_gt_u);
            lget(g, count);
            lget(g, length);
            lget(g, start);
            op(g, OP_i32_sub);
            op(g, OP_i32_gt_u);
            op(g, OP_i32_or);
            trap(g, f);
            let handle, error = create(g, f, ty, count, id);
            if error != blot_direct_types::Error.none { return handle, error; }
            let zero = constLocal(g, f, 0);
            let copied = copyElements(g, f, container, start, handle, zero, count, id);
            if copied != blot_direct_types::Error.none { return neverVal(), copied; }
            return handle, blot_direct_types::Error.none;
        },
        cursor => {
            // (slot, generation, position, end) over the container's live range.
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let result, error = fresh(g, f, ty, id);
            if error != blot_direct_types::Error.none { return result, error; }
            let u32_ty = blot_direct_types::u32_;
            let copied = copy(g, f, Val { u32_ty, container.start, 1 }, Val { u32_ty, result.start, 1 }, id);
            if copied != blot_direct_types::Error.none { return neverVal(), copied; }
            let copied = copy(g, f, Val { u32_ty, container.start + 1, 1 }, Val { u32_ty, result.start + 1, 1 }, id);
            if copied != blot_direct_types::Error.none { return neverVal(), copied; }
            let length, error = lengthOf(g, f, container, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            if tagOf(g, container.ty) == blot_direct_types::Tag.view {
                lget(g, w(g, container, 2));
                lset(g, w(g, result, 2));
                lget(g, w(g, container, 2));
                lget(g, length);
                op(g, OP_i32_add);
            } else {
                i32Const(g, 0);
                lset(g, w(g, result, 2));
                lget(g, length);
            }
            lset(g, w(g, result, 3));
            return result, blot_direct_types::Error.none;
        },
        cursor_has => {
            let cursor, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return cursor, error; }
            let result, error = fresh(g, f, blot_direct_types::boolean, id);
            if error != blot_direct_types::Error.none { return result, error; }
            lget(g, w(g, cursor, 2));
            lget(g, w(g, cursor, 3));
            op(g, OP_i32_lt_u);
            lset(g, w(g, result, 0));
            return result, blot_direct_types::Error.none;
        },
        cursor_value, cursor_advance => {
            let cursor, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return cursor, error; }
            lget(g, w(g, cursor, 2));
            lget(g, w(g, cursor, 3));
            op(g, OP_i32_ge_u);
            trap(g, f);
            if operation == blot_backend_collection_ops::Op.cursor_advance {
                let result, error = fresh(g, f, cursor.ty, id);
                if error != blot_direct_types::Error.none { return result, error; }
                for index in 0..(cursor.len as i64) {
                    lget(g, w(g, cursor, index));
                    if index == 2 {
                        i32Const(g, 1);
                        op(g, OP_i32_add);
                    }
                    lset(g, w(g, result, index));
                }
                return result, blot_direct_types::Error.none;
            }
            let address_function = g.runtime_().address;
            // A cursor's type argument is its collection.
            let collection = g.types.node(cursor.ty).a;
            var element = collection;
            match tagOf(g, collection) {
                array, list, grow, resize, view => { element = g.types.node(collection).a; },
                _ => {},
            }
            let address = local32(g, f);
            lget(g, w(g, cursor, 0));
            lget(g, w(g, cursor, 1));
            lget(g, w(g, cursor, 2));
            let step, error = stride(g, f, element, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            i32Const(g, step);
            callf(g, address_function);
            lset(g, address);
            return loadElement(g, f, address, 0, element, id);
        },
        simd_load, simd_store => {
            // Four consecutive elements, all in bounds.
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let position, error = expr(g, f, children[1]);
            if error != blot_direct_types::Error.none { return position, error; }
            let index, error = scalarLocal(g, f, position, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let last = local32(g, f);
            lget(g, index);
            i32Const(g, 3);
            op(g, OP_i32_add);
            ltee(g, last);
            lget(g, index);
            op(g, OP_i32_lt_u);
            trap(g, f);
            let last_address, error = elementAddress(g, f, container, last, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let address, error = elementAddress(g, f, container, index, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let element, error = elementOf(g, f, container.ty, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let lane_ty, error = g.types.tuple([element, element, element, element]);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            if operation == blot_backend_collection_ops::Op.simd_load { return loadAt(g, f, address, 0, lane_ty, id); }
            let lanes_value, error = expr(g, f, children[2]);
            if error != blot_direct_types::Error.none { return lanes_value, error; }
            storeAt(g, f, address, 0, lanes_value);
            return container, blot_direct_types::Error.none;
        },
        flatten => {
            // Sum the inner lengths, then copy each inner array in turn.
            let outer, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return outer, error; }
            let inner_ty, error = elementOf(g, f, outer.ty, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let count, error = lengthOf(g, f, outer, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let total = constLocal(g, f, 0);
            let index = local32(g, f);
            var result = neverVal();
            for pass in 0..2 {
                if pass == 1 {
                    let made, error = create(g, f, ty, total, id);
                    if error != blot_direct_types::Error.none { return made, error; }
                    result = made;
                }
                let at = constLocal(g, f, 0);
                i32Const(g, 0);
                lset(g, index);
                let exit = open(g, f, OP_block);
                let top = open(g, f, OP_loop);
                lget(g, index);
                lget(g, count);
                op(g, OP_i32_ge_u);
                br(g, f, OP_br_if, exit);
                let address, error = elementAddress(g, f, outer, index, id);
                if error != blot_direct_types::Error.none { return neverVal(), error; }
                let inner, error = loadElement(g, f, address, 0, inner_ty, id);
                if error != blot_direct_types::Error.none { return neverVal(), error; }
                let length, error = lengthOf(g, f, inner, id);
                if error != blot_direct_types::Error.none { return neverVal(), error; }
                var counter = total;
                if pass == 1 {
                    let zero = constLocal(g, f, 0);
                    let copied = copyElements(g, f, inner, zero, result, at, length, id);
                    if copied != blot_direct_types::Error.none { return neverVal(), copied; }
                    counter = at;
                }
                lget(g, counter);
                lget(g, length);
                op(g, OP_i32_add);
                lset(g, counter);
                lget(g, index);
                i32Const(g, 1);
                op(g, OP_i32_add);
                lset(g, index);
                br(g, f, OP_br, top);
                close(g, f);
                close(g, f);
            }
            return result, blot_direct_types::Error.none;
        },
    }
}
// Copies `count` elements from `source[from..]` to `target[to..]`.
fn copyElements(g: Generator&, f: Fn&, source: Val, from: u32, target: Val, to: u32, count: u32, id: u32) -> Error {
    let element, error = elementOf(g, f, target.ty, id);
    if error != blot_direct_types::Error.none { return error; }
    let step, error = stride(g, f, element, id);
    if error != blot_direct_types::Error.none { return error; }
    let opened = open(g, f, OP_block);
    lget(g, count);
    op(g, OP_i32_eqz);
    opIndex(g, OP_br_if, 0);
    let destination, error = elementAddress(g, f, target, to, id);
    if error != blot_direct_types::Error.none { return error; }
    let origin, error = elementAddress(g, f, source, from, id);
    if error != blot_direct_types::Error.none { return error; }
    // Both ranges end inside their owners: check the last elements too.
    let last = local32(g, f);
    lget(g, count);
    i32Const(g, 1);
    op(g, OP_i32_sub);
    lset(g, last);
    let end_target = local32(g, f);
    lget(g, to);
    lget(g, last);
    op(g, OP_i32_add);
    lset(g, end_target);
    let checked_target, error = elementAddress(g, f, target, end_target, id);
    if error != blot_direct_types::Error.none { return error; }
    let end_source = local32(g, f);
    lget(g, from);
    lget(g, last);
    op(g, OP_i32_add);
    lset(g, end_source);
    let checked_source, error = elementAddress(g, f, source, end_source, id);
    if error != blot_direct_types::Error.none { return error; }
    lget(g, destination);
    lget(g, origin);
    lget(g, count);
    i32Const(g, step);
    op(g, OP_i32_mul);
    memoryCopyOp(g);
    close(g, f);
    return blot_direct_types::Error.none;
}
// A new fixed array: the elements of each part in order (a part is either a
// container or, unless `containers`, one element).
fn joined(g: Generator&, f: Fn&, ty: Ty, element: Ty, parts: Vals, containers: bool, id: u32) -> Val, Error {
    // Per part: whether it is a container, and its length local.
    let lengths = blot_direct_emit::Words { g.s.words.len as u32, parts.len * 2 };
    for at in 0..(parts.len as i64) * 2 { g.s.words.push(0); }
    let total = constLocal(g, f, 0);
    for at in 0..(parts.len as i64) {
        let part = g.s.vals[parts.start + at];
        let is_container = containers || part.ty != element;
        if is_container {
            let length, error = lengthOf(g, f, part, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            g.s.words[lengths.start + at * 2] = 1;
            g.s.words[lengths.start + at * 2 + 1] = length;
        }
        lget(g, total);
        if is_container { lget(g, g.s.words[lengths.start + at * 2 + 1]); } else { i32Const(g, 1); }
        op(g, OP_i32_add);
        lset(g, total);
    }
    let handle, error = create(g, f, ty, total, id);
    if error != blot_direct_types::Error.none { return handle, error; }
    let at = constLocal(g, f, 0);
    for index in 0..(parts.len as i64) {
        let part = g.s.vals[parts.start + index];
        if g.s.words[lengths.start + index * 2] != 0 {
            let count = g.s.words[lengths.start + index * 2 + 1];
            let zero = constLocal(g, f, 0);
            let copied = copyElements(g, f, part, zero, handle, at, count, id);
            if copied != blot_direct_types::Error.none { return neverVal(), copied; }
            lget(g, at);
            lget(g, count);
        } else {
            let address, error = elementAddress(g, f, handle, at, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let written = writeFlat(g, f, address, 0, part, id);
            if written != blot_direct_types::Error.none { return neverVal(), written; }
            lget(g, at);
            i32Const(g, 1);
        }
        op(g, OP_i32_add);
        lset(g, at);
    }
    return handle, blot_direct_types::Error.none;
}
// An independent owner of type `ty` with `value`'s elements.
fn copyContainer(g: Generator&, f: Fn&, value: Val, ty: Ty, id: u32) -> Val, Error {
    let length, error = lengthOf(g, f, value, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let handle, error = create(g, f, ty, length, id);
    if error != blot_direct_types::Error.none { return handle, error; }
    let from = constLocal(g, f, 0);
    let to = constLocal(g, f, 0);
    let copied = copyElements(g, f, value, from, handle, to, length, id);
    if copied != blot_direct_types::Error.none { return neverVal(), copied; }
    return handle, blot_direct_types::Error.none;
}
// The two handle words of `container` copied into the first two of `result`.
fn copyHandle(g: Generator&, f: const Fn&, container: Val, result: Val, id: u32) -> Error {
    let u32_ty = blot_direct_types::u32_;
    let copied = copy(g, f, Val { u32_ty, container.start, 1 }, Val { u32_ty, result.start, 1 }, id);
    if copied != blot_direct_types::Error.none { return copied; }
    return copy(g, f, Val { u32_ty, container.start + 1, 1 }, Val { u32_ty, result.start + 1, 1 }, id);
}

recursive fn storageOp(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    let operation, decoded = blot_check_storage_ops::opFromCode(n.c);
    assert(decoded == blot_error::Error.none);
    let children = m.children(id);
    let ty, error = typeOf(g, f, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let address_function = g.runtime_().address;
    match operation {
        reserve => {
            let ignored, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return ignored, error; }
            return unitVal(), blot_direct_types::Error.none;
        },
        length => {
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let length, error = lengthOf(g, f, container, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            return valOf1(g, blot_direct_types::u32_, length), blot_direct_types::Error.none;
        },
        read => {
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let position, error = expr(g, f, children[1]);
            if error != blot_direct_types::Error.none { return position, error; }
            let index, error = scalarLocal(g, f, position, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            return readElement(g, f, container, index, id);
        },
        push => {
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let value, error = expr(g, f, children[1]);
            if error != blot_direct_types::Error.none { return value, error; }
            let address = local32(g, f);
            lget(g, w(g, container, 0));
            lget(g, w(g, container, 1));
            let element, error = elementOf(g, f, container.ty, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let step, error = stride(g, f, element, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            i32Const(g, step);
            callf(g, g.runtime_().push);
            lset(g, address);
            let noted = noteStore(g, f, value);
            if noted != blot_direct_types::Error.none { return neverVal(), noted; }
            let written = writeFlat(g, f, address, 0, value, id);
            if written != blot_direct_types::Error.none { return neverVal(), written; }
            return unitVal(), blot_direct_types::Error.none;
        },
        pop => {
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let address = local32(g, f);
            lget(g, w(g, container, 0));
            lget(g, w(g, container, 1));
            let element, error = elementOf(g, f, container.ty, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let step, error = stride(g, f, element, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            i32Const(g, step);
            callf(g, g.runtime_().pop);
            lset(g, address);
            return loadElement(g, f, address, 0, ty, id);
        },
        truncate => {
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let counted, error = expr(g, f, children[1]);
            if error != blot_direct_types::Error.none { return counted, error; }
            let count, error = scalarLocal(g, f, counted, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            lget(g, w(g, container, 0));
            lget(g, w(g, container, 1));
            lget(g, count);
            callf(g, g.runtime_().truncate);
            return unitVal(), blot_direct_types::Error.none;
        },
        freeze => {
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            lget(g, w(g, container, 0));
            lget(g, w(g, container, 1));
            callf(g, g.runtime_().freeze);
            return Val { ty, container.start, container.len }, blot_direct_types::Error.none;
        },
        share => {
            let value, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return value, error; }
            let froze = freezeValue(g, f, value, id, 0);
            if froze != blot_direct_types::Error.none { return neverVal(), froze; }
            return Val { ty, value.start, value.len }, blot_direct_types::Error.none;
        },
        copy => {
            let value, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return value, error; }
            return deepCopyValue(g, f, value, ty, id, 0);
        },
        view => {
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let started, error = expr(g, f, children[1]);
            if error != blot_direct_types::Error.none { return started, error; }
            let start, error = scalarLocal(g, f, started, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let ended, error = expr(g, f, children[2]);
            if error != blot_direct_types::Error.none { return ended, error; }
            let end, error = scalarLocal(g, f, ended, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let length, error = lengthOf(g, f, container, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            lget(g, start);
            lget(g, end);
            op(g, OP_i32_gt_u);
            lget(g, end);
            lget(g, length);
            op(g, OP_i32_gt_u);
            op(g, OP_i32_or);
            trap(g, f);
            let result, error = fresh(g, f, ty, id);
            if error != blot_direct_types::Error.none { return result, error; }
            let copied = copyHandle(g, f, container, result, id);
            if copied != blot_direct_types::Error.none { return neverVal(), copied; }
            if tagOf(g, container.ty) == blot_direct_types::Tag.view {
                lget(g, w(g, container, 2));
                lget(g, start);
                op(g, OP_i32_add);
            } else { lget(g, start); }
            lset(g, w(g, result, 2));
            lget(g, end);
            lget(g, start);
            op(g, OP_i32_sub);
            lset(g, w(g, result, 3));
            return result, blot_direct_types::Error.none;
        },
        at, link => {
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let position, error = expr(g, f, children[1]);
            if error != blot_direct_types::Error.none { return position, error; }
            let index, error = scalarLocal(g, f, position, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            // Check now, so a reference never names a missing element.
            let checked, error = elementAddress(g, f, container, index, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let result, error = fresh(g, f, ty, id);
            if error != blot_direct_types::Error.none { return result, error; }
            let copied = copyHandle(g, f, container, result, id);
            if copied != blot_direct_types::Error.none { return neverVal(), copied; }
            if tagOf(g, container.ty) == blot_direct_types::Tag.view {
                lget(g, w(g, container, 2));
                lget(g, index);
                op(g, OP_i32_add);
            } else { lget(g, index); }
            lset(g, w(g, result, 2));
            return result, blot_direct_types::Error.none;
        },
        load => {
            let reference_, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return reference_, error; }
            let element, error = elementOf(g, f, reference_.ty, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let address = local32(g, f);
            lget(g, w(g, reference_, 0));
            lget(g, w(g, reference_, 1));
            lget(g, w(g, reference_, 2));
            let step, error = stride(g, f, element, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            i32Const(g, step);
            callf(g, address_function);
            lset(g, address);
            return loadElement(g, f, address, 0, element, id);
        },
        ref => { return neverVal(), g.fail(m, id, "references to whole values are not supported yet"); },
        // An operation the Zig backend has no arm for (the checker lowers
        // `write` to a store).
        _ => { abort("storage operation without a direct lowering"); },
    }
}

recursive fn holdsGrowable(g: Generator&, ty: Ty, depth: i64) -> bool {
    if depth > 32 { return false; }
    let n = g.types.node(ty);
    match n.tag {
        grow, resize => { return true; },
        tuple => {
            for at in 0..(n.b as i64) { if holdsGrowable(g, g.types.words[n.a + at], depth + 1) { return true; } }
            return false;
        },
        record => {
            for index in 0..(n.b as i64) { if holdsGrowable(g, g.types.recordField(ty, index).ty, depth + 1) { return true; } }
            return false;
        },
        nominal => {
            let cases, error = g.types.variants(ty);
            if error != blot_direct_types::Error.none { return false; }
            for at in 0..(cases.len as i64) {
                let payload = g.types.variant_payloads[cases.payloads + at];
                if payload != ty && holdsGrowable(g, payload, depth + 1) { return true; }
            }
            return false;
        },
        _ => { return false; },
    }
}

recursive fn freezeValue(g: Generator&, f: Fn&, value: Val, id: u32, depth: i64) -> Error {
    if depth > 32 || value.ty == blot_direct_types::never { return blot_direct_types::Error.none; }
    let tag = tagOf(g, value.ty);
    if tag == blot_direct_types::Tag.grow || tag == blot_direct_types::Tag.resize {
        lget(g, w(g, value, 0));
        lget(g, w(g, value, 1));
        callf(g, g.runtime_().freeze);
        return blot_direct_types::Error.none;
    }
    if !holdsGrowable(g, value.ty, 0) { return blot_direct_types::Error.none; }
    if tag == blot_direct_types::Tag.record {
        let count = g.types.node(value.ty).b as i64;
        for index in 0..count {
            let field_ty = g.types.recordField(value.ty, index).ty;
            if !holdsGrowable(g, field_ty, 0) { continue; }
            let field, error = recordField(g, f, value, index, id);
            if error != blot_direct_types::Error.none { return error; }
            let err = freezeValue(g, f, field, id, depth + 1);
            if err != blot_direct_types::Error.none { return err; }
        }
        return blot_direct_types::Error.none;
    }
    if tag == blot_direct_types::Tag.tuple {
        let n = g.types.node(value.ty);
        for index in 0..(n.b as i64) {
            let item_ty = g.types.words[n.a + index];
            if !holdsGrowable(g, item_ty, 0) { continue; }
            let item, error = tupleItem(g, f, value, index, id);
            if error != blot_direct_types::Error.none { return error; }
            let err = freezeValue(g, f, item, id, depth + 1);
            if err != blot_direct_types::Error.none { return err; }
        }
        return blot_direct_types::Error.none;
    }
    if tag == blot_direct_types::Tag.nominal {
        let cases, error = g.types.variants(value.ty);
        if error != blot_direct_types::Error.none { return g.typeFailure(g.units[f.unit - 1], id); }
        if cases.len == 1 {
            let unwrapped, error = unwrapVariant(g, f, value, g.types.variant_tags[cases.tags], id);
            if error != blot_direct_types::Error.none { return error; }
            return freezeValue(g, f, unwrapped, id, depth + 1);
        }
    }
    return blot_direct_types::Error.none;
}

recursive fn holdsContainer(g: Generator&, ty: Ty, depth: i64) -> bool {
    if depth > 32 { return false; }
    let n = g.types.node(ty);
    match n.tag {
        array, grow, resize => { return true; },
        tuple => {
            for at in 0..(n.b as i64) { if holdsContainer(g, g.types.words[n.a + at], depth + 1) { return true; } }
            return false;
        },
        record => {
            for index in 0..(n.b as i64) { if holdsContainer(g, g.types.recordField(ty, index).ty, depth + 1) { return true; } }
            return false;
        },
        nominal => {
            let cases, error = g.types.variants(ty);
            if error != blot_direct_types::Error.none { return false; }
            for at in 0..(cases.len as i64) {
                let payload = g.types.variant_payloads[cases.payloads + at];
                if payload != ty && holdsContainer(g, payload, depth + 1) { return true; }
            }
            return false;
        },
        _ => { return false; },
    }
}

recursive fn deepCopyValue(g: Generator&, f: Fn&, value: Val, ty: Ty, id: u32, depth: i64) -> Val, Error {
    if depth > 32 || value.ty == blot_direct_types::never { return Val { ty, value.start, value.len }, blot_direct_types::Error.none; }
    let tag = tagOf(g, ty);
    if tag == blot_direct_types::Tag.array || tag == blot_direct_types::Tag.grow || tag == blot_direct_types::Tag.resize {
        return copyContainer(g, f, value, ty, id);
    }
    if !holdsContainer(g, ty, 0) { return Val { ty, value.start, value.len }, blot_direct_types::Error.none; }
    if tag == blot_direct_types::Tag.record {
        let count = g.types.node(ty).b as i64;
        let boxed, error = isBoxed(g, f, ty, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        var memory_block: u32 = 0;
        if boxed {
            let made, error = newBlock(g, f, ty, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            memory_block = made;
        }
        let s .= g.s;
        let mark = s.scratch.len;
        for index in 0..count {
            let field_ty = g.types.recordField(ty, index).ty;
            let field, error = recordField(g, f, value, index, id);
            if error != blot_direct_types::Error.none { s.scratch.resize(mark); return neverVal(), error; }
            let copied, error = deepCopyValue(g, f, field, field_ty, id, depth + 1);
            if error != blot_direct_types::Error.none { s.scratch.resize(mark); return neverVal(), error; }
            if boxed {
                let offset, error = fieldOffset(g, f, ty, index, id);
                if error != blot_direct_types::Error.none { s.scratch.resize(mark); return neverVal(), error; }
                let written = writeFlat(g, f, memory_block, offset, copied, id);
                if written != blot_direct_types::Error.none { s.scratch.resize(mark); return neverVal(), written; }
            } else {
                for at in 0..(copied.len as i64) { s.scratch.push(g.s.words[copied.start + at]); }
            }
        }
        if boxed { s.scratch.resize(mark); return valOf1(g, ty, memory_block), blot_direct_types::Error.none; }
        let start = g.s.words.len as u32;
        let words_count = (s.scratch.len - mark) as u32;
        for at in mark..s.scratch.len { let word = s.scratch[at]; g.s.words.push(word); }
        s.scratch.resize(mark);
        return Val { ty, start, words_count }, blot_direct_types::Error.none;
    }
    if tag == blot_direct_types::Tag.tuple {
        let n = g.types.node(ty);
        let boxed, error = isBoxed(g, f, ty, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        var memory_block: u32 = 0;
        if boxed {
            let made, error = newBlock(g, f, ty, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            memory_block = made;
        }
        let s .= g.s;
        let mark = s.scratch.len;
        for index in 0..(n.b as i64) {
            let item_ty = g.types.words[n.a + index];
            let item, error = tupleItem(g, f, value, index, id);
            if error != blot_direct_types::Error.none { s.scratch.resize(mark); return neverVal(), error; }
            let copied, error = deepCopyValue(g, f, item, item_ty, id, depth + 1);
            if error != blot_direct_types::Error.none { s.scratch.resize(mark); return neverVal(), error; }
            if boxed {
                let offset, error = itemOffset(g, f, ty, index, id);
                if error != blot_direct_types::Error.none { s.scratch.resize(mark); return neverVal(), error; }
                let written = writeFlat(g, f, memory_block, offset, copied, id);
                if written != blot_direct_types::Error.none { s.scratch.resize(mark); return neverVal(), written; }
            } else {
                for at in 0..(copied.len as i64) { s.scratch.push(g.s.words[copied.start + at]); }
            }
        }
        if boxed { s.scratch.resize(mark); return valOf1(g, ty, memory_block), blot_direct_types::Error.none; }
        let start = g.s.words.len as u32;
        let words_count = (s.scratch.len - mark) as u32;
        for at in mark..s.scratch.len { let word = s.scratch[at]; g.s.words.push(word); }
        s.scratch.resize(mark);
        return Val { ty, start, words_count }, blot_direct_types::Error.none;
    }
    if tag == blot_direct_types::Tag.nominal {
        let cases, error = g.types.variants(ty);
        if error != blot_direct_types::Error.none { return neverVal(), g.typeFailure(g.units[f.unit - 1], id); }
        if cases.len == 1 {
            let vtag = g.types.variant_tags[cases.tags];
            let payload_ty = g.types.variant_payloads[cases.payloads];
            let unwrapped, error = unwrapVariant(g, f, value, vtag, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let copied, error = deepCopyValue(g, f, unwrapped, payload_ty, id, depth + 1);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            return wrapVariant(g, f, ty, vtag, copied, id);
        }
        let result, error = fresh(g, f, ty, id);
        if error != blot_direct_types::Error.none { return result, error; }
        let vtag_local = local32(g, f);
        lget(g, w(g, value, 0));
        let boxed, error = isBoxed(g, f, ty, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        if boxed { memoryOp(g, OP_i32_load, 0); }
        lset(g, vtag_local);
        let exit = open(g, f, OP_block);
        for pos in 0..(cases.len as i64) {
            let vtag = g.types.variant_tags[cases.tags + pos];
            let payload_ty = g.types.variant_payloads[cases.payloads + pos];
            let next = open(g, f, OP_block);
            lget(g, vtag_local);
            i32Const(g, vtag);
            op(g, OP_i32_ne);
            br(g, f, OP_br_if, next);
            let unwrapped, error = unwrapVariant(g, f, value, vtag, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let copied, error = deepCopyValue(g, f, unwrapped, payload_ty, id, depth + 1);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let wrapped, error = wrapVariant(g, f, ty, vtag, copied, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let stored = copy(g, f, wrapped, result, id);
            if stored != blot_direct_types::Error.none { return neverVal(), stored; }
            br(g, f, OP_br, exit);
            close(g, f);
        }
        op(g, OP_unreachable_);
        close(g, f);
        return result, blot_direct_types::Error.none;
    }
    return Val { ty, value.start, value.len }, blot_direct_types::Error.none;
}
