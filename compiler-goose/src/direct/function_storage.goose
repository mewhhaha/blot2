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
// Writes an element `value` into a container at `base + offset`.
// Bare `Bool` and `U8` container elements are byte-packed (1-byte stride).
fn writeElement(g: Generator&, f: const Fn&, base: u32, offset: u32, value: Val, id: u32) -> Error {
    if value.ty == blot_direct_types::never { return blot_direct_types::Error.none; }
    if byteElement(tagOf(g, value.ty)) {
        lget(g, base);
        lget(g, w(g, value, 0));
        op(g, OP_i32_store8);
        uleb(g, 0);
        uleb(g, offset);
        return blot_direct_types::Error.none;
    }
    return writeFlat(g, f, base, offset, value, id);
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
    if byteElement(tagOf(g, ty)) {
        let value, error = fresh(g, f, ty, id);
        if error != blot_direct_types::Error.none { return value, error; }
        lget(g, address);
        op(g, OP_i32_load8_u);
        uleb(g, 0);
        uleb(g, offset);
        lset(g, w(g, value, 0));
        return value, blot_direct_types::Error.none;
    }
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
    let off, error = g.types.recordFieldByteOffset(ty, index);
    if error != blot_direct_types::Error.none { return 0, g.typeFailure(g.units[f.unit - 1], id); }
    return off, blot_direct_types::Error.none;
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
fn byteElement(tag: blot_direct_types::Tag) -> bool {
    return tag == blot_direct_types::Tag.boolean || tag == blot_direct_types::Tag.u8_;
}
// Bytes per element of a container holding `element`.
fn stride(g: Generator&, f: const Fn&, element: Ty, id: u32) -> u32, Error {
    if byteElement(tagOf(g, element)) {
        return 1, blot_direct_types::Error.none;
    }
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
        else if kind == VT_i64 { op(g, OP_i64_store); }
        else if kind == VT_f64 { op(g, OP_f64_store); }
        else if kind == VT_v128 { op(g, OP_prefix_fd); uleb(g, 11); }
        else { op(g, OP_i32_store); }
        if kind == VT_v128 { uleb(g, 4); } else { uleb(g, 2); }
        uleb(g, at);
        at += blot_direct_writer::wordBytes(kind);
    }
}
// Like `storeAt`, but packs contiguous 4x F32 runs in wide aggregates into
// cached `v128` locals so both memory stores and subsequent wide-worker calls
// share the exact same XMM registers.
fn storeAtPack(g: Generator&, f: Fn&, address: u32, offset: u32, value: Val) {
    var at = offset;
    var index: i64 = 0;
    let total = value.len as i64;
    while index < total {
        if total >= 8 && index + 3 < total {
            let w0 = g.s.words[value.start + index];
            let w1 = g.s.words[value.start + index + 1];
            let w2 = g.s.words[value.start + index + 2];
            let w3 = g.s.words[value.start + index + 3];
            if localType(g, f, w0) == VT_f32 && localType(g, f, w1) == VT_f32 &&
                localType(g, f, w2) == VT_f32 && localType(g, f, w3) == VT_f32 {
                let vloc = packF32x4Cached(g, f, w0, w1, w2, w3);
                lget(g, address);
                lget(g, vloc);
                op(g, OP_prefix_fd);
                uleb(g, 11);
                uleb(g, 2);
                uleb(g, at);
                at += 16;
                index += 4;
                continue;
            }
        }
        let word = g.s.words[value.start + index];
        let kind = localType(g, f, word);
        lget(g, address);
        lget(g, word);
        if kind == VT_f32 { op(g, OP_f32_store); }
        else if kind == VT_i64 { op(g, OP_i64_store); }
        else if kind == VT_f64 { op(g, OP_f64_store); }
        else if kind == VT_v128 { op(g, OP_prefix_fd); uleb(g, 11); }
        else { op(g, OP_i32_store); }
        if kind == VT_v128 { uleb(g, 4); } else { uleb(g, 2); }
        uleb(g, at);
        at += blot_direct_writer::wordBytes(kind);
        index += 1;
    }
}
fn writeFlatPack(g: Generator&, f: Fn&, base: u32, offset: u32, value: Val, id: u32) -> Error {
    if value.ty == blot_direct_types::never { return blot_direct_types::Error.none; }
    let copied, error = copiedBox(g, f, value.ty, id);
    if error != blot_direct_types::Error.none { return error; }
    if copied {
        let bytes, error = blockBytes(g, f, value.ty, id);
        if error != blot_direct_types::Error.none { return error; }
        memoryCopy(g, base, offset, w(g, value, 0), bytes);
        return blot_direct_types::Error.none;
    }
    storeAtPack(g, f, base, offset, value);
    return blot_direct_types::Error.none;
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
        else if kind == VT_i64 { op(g, OP_i64_load); }
        else if kind == VT_f64 { op(g, OP_f64_load); }
        else if kind == VT_v128 { op(g, OP_prefix_fd); uleb(g, 0); }
        else { op(g, OP_i32_load); }
        if kind == VT_v128 { uleb(g, 4); } else { uleb(g, 2); }
        uleb(g, at);
        lset(g, word);
        at += blot_direct_writer::wordBytes(kind);
    }
    return value, blot_direct_types::Error.none;
}
fn elementOf(g: Generator&, f: const Fn&, ty: Ty, id: u32) -> Ty, Error {
    match tagOf(g, ty) {
        array, view, ref, link => { return g.types.node(ty).a, blot_direct_types::Error.none; },
        _ => {
            g.failOpen(g.units[f.unit - 1], id);
            g.put("storage operation on a ");
            g.put(blot_direct_types::tagName(tagOf(g, ty)));
            return 0, g.failClose();
        },
    }
}
fn boolWord(value: bool) -> u32 { if value { return 1; } return 0; }
fn memoryFillOp(g: Generator&) {
    op(g, OP_prefix_fc);
    uleb(g, 11);
    op(g, 0);
}
fn emitOffsetAddress(g: Generator&, f: const Fn&, base: u32, index: u32, step: u32) -> u32 {
    let address = local32(g, f);
    lget(g, base);
    lget(g, index);
    if step == 4 {
        i32Const(g, 2);
        op(g, OP_i32_shl);
    } else if step == 8 {
        i32Const(g, 3);
        op(g, OP_i32_shl);
    } else if step == 16 {
        i32Const(g, 4);
        op(g, OP_i32_shl);
    } else if step != 1 {
        i32Const(g, step);
        op(g, OP_i32_mul);
    }
    op(g, OP_i32_add);
    lset(g, address);
    return address;
}
fn emitScaledBytes(g: Generator&, f: const Fn&, count: u32, step: u32) -> u32 {
    let bytes = local32(g, f);
    lget(g, count);
    if step == 4 {
        i32Const(g, 2);
        op(g, OP_i32_shl);
    } else if step == 8 {
        i32Const(g, 3);
        op(g, OP_i32_shl);
    } else if step == 16 {
        i32Const(g, 4);
        op(g, OP_i32_shl);
    } else if step != 1 {
        i32Const(g, step);
        op(g, OP_i32_mul);
    }
    lset(g, bytes);
    return bytes;
}
fn ensureCheckedArray(g: Generator&, f: Fn&, container: Val) -> u32, u32 {
    let slot = w(g, container, 0);
    let da_idx = findDirectArrayBySlot(f, slot);
    if da_idx >= 0 && !f.direct_arrays[da_idx].scalar_packed {
        return f.direct_arrays[da_idx].base, f.direct_arrays[da_idx].len_local;
    }
    let generation = w(g, container, 1);
    let wr = findWorkerR(f, slot, generation);
    if wr >= 0 {
        return f.worker_r[wr].base, f.worker_r[wr].length;
    }
    let cached = findCheckedArray(f, slot, generation);
    if cached >= 0 {
        let entry = f.checked_arrays[cached];
        return entry.base, entry.length;
    }
    let wm = findWorkerM(f, slot, generation);
    let cg = if wm >= 0 { -1 } else { findCheckedGrow(f, slot, generation) };
    var entry: u32 = 0;
    if wm >= 0 {
        entry = f.worker_m[wm].entry;
        lget(g, entry);
    } else if cg >= 0 {
        entry = f.checked_grows[cg].entry;
        lget(g, entry);
    } else {
        entry = local32(g, f);
        lget(g, slot);
        lget(g, generation);
        callf(g, g.runtime_().check);
        ltee(g, entry);
        recordCheckedGrow(f, slot, generation, entry);
    }
    let base = local32(g, f);
    let length = local32(g, f);
    op(g, OP_i32_load);
    uleb(g, 2);
    uleb(g, blot_direct_runtime::entry_base);
    lset(g, base);
    lget(g, entry);
    op(g, OP_i32_load);
    uleb(g, 2);
    uleb(g, blot_direct_runtime::entry_length);
    lset(g, length);
    recordCheckedArray(f, slot, generation, base, length);
    return base, length;
}
// A fresh fixed array without zero-filling: caller overwrites all `length` elements.
fn createUninit(g: Generator&, f: Fn&, ty: Ty, length: u32, id: u32) -> Val, u32, Error {
    if tagOf(g, ty) != blot_direct_types::Tag.array {
        let handle, error = create(g, f, ty, length, id);
        if error != blot_direct_types::Error.none { return handle, 0, error; }
        let base = baseOf(g, f, handle);
        return handle, base, blot_direct_types::Error.none;
    }
    let rt = g.runtime_();
    noteAllocation(f);
    let element, error = elementOf(g, f, ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), 0, error; }
    let step, error = stride(g, f, element, id);
    if error != blot_direct_types::Error.none { return neverVal(), 0, error; }
    if step > 0 {
        let max_count = (rt.layout.stack_end - rt.layout.stack_base) / step;
        lget(g, length);
        i32Const(g, max_count);
        op(g, OP_i32_gt_u);
        trap(g, f);
    }
    let bytes = emitScaledBytes(g, f, length, step);
    let base = local32(g, f);
    lget(g, bytes);
    callf(g, rt.stack);
    lset(g, base);
    lget(g, base);
    lget(g, length);
    lget(g, bytes);
    callf(g, rt.open);
    let handle, error = pop(g, f, ty, id);
    if error != blot_direct_types::Error.none { return handle, 0, error; }
    recordMutable(g, f, handle);
    recordCheckedArray(f, w(g, handle, 0), w(g, handle, 1), base, length);
    return handle, base, blot_direct_types::Error.none;
}
fn ensureCheckedGrow(g: Generator&, f: Fn&, container: Val) -> u32 {
    let slot = w(g, container, 0);
    let generation = w(g, container, 1);
    let wm = findWorkerM(f, slot, generation);
    if wm >= 0 { return f.worker_m[wm].entry; }
    let cached = findCheckedGrow(f, slot, generation);
    if cached >= 0 { return f.checked_grows[cached].entry; }
    let entry = local32(g, f);
    lget(g, slot);
    lget(g, generation);
    callf(g, g.runtime_().check);
    lset(g, entry);
    recordCheckedGrow(f, slot, generation, entry);
    return entry;
}
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
    i32Const(g, 0);
    callf(g, create_function);
    let handle, error = pop(g, f, ty, id);
    if error != blot_direct_types::Error.none { return handle, error; }
    recordMutable(g, f, handle);
    return handle, blot_direct_types::Error.none;
}
// The address of element 0 of an owner handle.
fn baseOf(g: Generator&, f: Fn&, handle: Val) -> u32 {
    let htag = tagOf(g, handle.ty);
    if htag == blot_direct_types::Tag.array || htag == blot_direct_types::Tag.view {
        let base, _ = ensureCheckedArray(g, f, handle);
        return base;
    }
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
fn lengthOf(g: Generator&, f: Fn&, container: Val, id: u32) -> u32, Error {
    let length_function = g.runtime_().length;
    if tagOf(g, container.ty) == blot_direct_types::Tag.view { return w(g, container, 3), blot_direct_types::Error.none; }
    if tagOf(g, container.ty) == blot_direct_types::Tag.array {
        let _, length = ensureCheckedArray(g, f, container);
        return length, blot_direct_types::Error.none;
    }
    let element, error = elementOf(g, f, container.ty, id);
    if error != blot_direct_types::Error.none { return 0, error; }
    let length = local32(g, f);
    lget(g, w(g, container, 0));
    lget(g, w(g, container, 1));
    callf(g, length_function);
    lset(g, length);
    return length, blot_direct_types::Error.none;
}
// When the module uses `fork`, journals `[address + offset .. + bytes]`
// before mutating an owner opened before the active `fork` or a persistent owner.
fn recordBeforeWrite(g: Generator&, f: Fn&, slot_local: u32, address: u32, offset: u32, bytes: u32) {
    let rt = g.runtime_();
    if !rt.has_fork || bytes == 0 { return; }
    gget(g, rt.fork_depth);
    i32Const(g, 0);
    op(g, OP_i32_ne);
    lget(g, slot_local);
    gget(g, rt.fork_owner_mark);
    op(g, OP_i32_lt_u);
    lget(g, slot_local);
    i32Const(g, rt.layout.persistent_split);
    op(g, OP_i32_ge_u);
    op(g, OP_i32_or);
    op(g, OP_i32_and);
    let opened = open(g, f, OP_if_);
    lget(g, address);
    if offset != 0 {
        i32Const(g, offset);
        op(g, OP_i32_add);
    }
    i32Const(g, bytes);
    callf(g, rt.undo_record);
    close(g, f);
}
// The checked address of element `index` (a local) of a container or view;
// views check their own range first.
fn elementAddress(g: Generator&, f: Fn&, container: Val, index: u32, id: u32, container_core_ty: TId = 0, cache_elem: bool = false) -> u32, Error {
    let address_function = g.runtime_().address;
    let element, error = elementOf(g, f, container.ty, id);
    if error != blot_direct_types::Error.none { return 0, error; }
    let step, error = stride(g, f, element, id);
    if error != blot_direct_types::Error.none { return 0, error; }
    let range = f.checked_range;
    if tagOf(g, container.ty) == blot_direct_types::Tag.array {
        let slot = w(g, container, 0);
        let gen = w(g, container, 1);
        if cache_elem {
            let cached_elem = findCheckedElem(f, slot, gen, index, step);
            if cached_elem >= 0 {
                return f.checked_elems[cached_elem].address, blot_direct_types::Error.none;
            }
        }
        let base, len = ensureCheckedArray(g, f, container);
        var arr_len_ty: TId = 0;
        if container_core_ty != 0 {
            arr_len_ty = coreSizedLength(g.units[f.unit - 1], container_core_ty);
        }
        var in_bounds = false;
        if index == range.index && !range.is_view {
            if range.slot != 0xffffffff && slot == range.slot && gen == range.generation {
                in_bounds = true;
            } else if range.end_local != 0xffffffff && (len == range.end_local || findCheckedLe(f, range.end_local, len) >= 0) {
                in_bounds = true;
            } else if range.length_ty != 0 && arr_len_ty != 0 {
                let m .= g.units[f.unit - 1];
                if sameSizedLength(m, range.length_ty, arr_len_ty) {
                    in_bounds = true;
                }
            }
        }
        if !in_bounds {
            let length, known_length = constU32(f, len);
            if known_length {
                let position, known_position = constU32(f, index);
                if known_position && position.value < length.value {
                    useConstU32(position);
                    in_bounds = true;
                } else if index == range.index && !range.is_view && range.end_local != 0xffffffff {
                    let end, known_end = constU32(f, range.end_local);
                    if known_end && end.value <= length.value {
                        useConstU32(end);
                        in_bounds = true;
                    }
                }
                if in_bounds { useConstU32(length); }
            }
        }
        if !in_bounds && findCheckedBound(f, index, len) >= 0 {
            in_bounds = true;
        }
        if !in_bounds && arr_len_ty != 0 && findCheckedSizedBound(g.units[f.unit - 1], f, index, arr_len_ty) {
            in_bounds = true;
        }
        if !in_bounds {
            let cm = findCheckedMask(f, index);
            if cm >= 0 {
                let entry = f.checked_masks[cm];
                if entry.max_local != 0xffffffff && findCheckedBound(f, entry.max_local, len) >= 0 {
                    in_bounds = true;
                } else if entry.has_const {
                    let clen, known_len = constU32(f, len);
                    if known_len && entry.max_const < clen.value {
                        useConstU32(clen);
                        in_bounds = true;
                    }
                }
            }
        }
        if !in_bounds && !range.is_view && range.end_local != 0xffffffff {
            let ca = findCheckedAdd(f, index);
            if ca >= 0 {
                let add_e = f.checked_adds[ca];
                if add_e.idx == range.index {
                    if add_e.base == 0xffffffff && add_e.c == 1 && findCheckedBound(f, range.end_local, len) >= 0 {
                        in_bounds = true;
                    } else if findCheckedAffine(f, add_e.base, range.end_local, add_e.c, len) >= 0 {
                        in_bounds = true;
                    } else if add_e.base == 0xffffffff {
                        let clen, klen = constU32(f, len);
                        let cend, kend = constU32(f, range.end_local);
                        if klen && kend && (cend.value as u64) + (add_e.c as u64) <= (clen.value as u64) {
                            useConstU32(clen);
                            useConstU32(cend);
                            in_bounds = true;
                        }
                    }
                }
            }
        }
        if !in_bounds {
            lget(g, index);
            lget(g, len);
            op(g, OP_i32_ge_u);
            trapBounds(g, f, id);
            recordCheckedBoundSized(f, index, len, arr_len_ty);
        }
        let addr = emitOffsetAddress(g, f, base, index, step);
        if cache_elem { recordCheckedElem(f, slot, gen, index, step, addr); }
        return addr, blot_direct_types::Error.none;
    }
    if tagOf(g, container.ty) == blot_direct_types::Tag.view &&
        range.is_view && range.slot != 0xffffffff && index == range.index &&
        w(g, container, 0) == range.slot && w(g, container, 1) == range.generation &&
        w(g, container, 2) == range.view_start && w(g, container, 3) == range.end_local {
        if range.trusted_view {
            return emitOffsetAddress(g, f, range.base, index, step), blot_direct_types::Error.none;
        }
        let address = local32(g, f);
        lget(g, range.base);
        let fast = open(g, f, OP_if_);
        let fast_addr = emitOffsetAddress(g, f, range.base, index, step);
        lget(g, fast_addr);
        lset(g, address);
        popCheckedArraysAt(f, fast);
        op(g, OP_else_);
        lget(g, index);
        lget(g, w(g, container, 3));
        op(g, OP_i32_ge_u);
        trapBounds(g, f, id);
        let position = local32(g, f);
        lget(g, w(g, container, 2));
        lget(g, index);
        op(g, OP_i32_add);
        lset(g, position);
        lget(g, w(g, container, 0));
        lget(g, w(g, container, 1));
        lget(g, position);
        i32Const(g, step);
        callf(g, address_function);
        lset(g, address);
        close(g, f);
        return address, blot_direct_types::Error.none;
    }
    var position = index;
    if tagOf(g, container.ty) == blot_direct_types::Tag.view {
        lget(g, index);
        lget(g, w(g, container, 3));
        op(g, OP_i32_ge_u);
        trapBounds(g, f, id);
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
// Bounds trap: identical to `trap` outside `--test`, records `blot:traps` kind=2 in `--test` mode.
fn trapBounds(g: Generator&, f: Fn&, id: u32) {
    let opened = open(g, f, OP_if_);
    if blot_direct_writer::testModeEnabled() {
        emitTrapSite(g, f, 2, id, "index out of bounds");
    }
    op(g, OP_unreachable_);
    close(g, f);
}
// Runtime guard against mutating immutable static const pools (`slot >= persistent_split && static_pool_flag != 0`).
// Matches runtime.push/pop/truncate while leaving temporary transport pins (`slot < persistent_split`) untouched.
fn checkMutableOwner(g: Generator&, f: Fn&, container: Val) {
    if tagOf(g, container.ty) != blot_direct_types::Tag.array || knownMutable(g, f, container) { return; }
    let rt = g.runtime_();
    lget(g, w(g, container, 0));
    i32Const(g, rt.layout.persistent_split);
    op(g, OP_i32_ge_u);
    let opened = open(g, f, OP_if_);
    lget(g, w(g, container, 0));
    lget(g, w(g, container, 1));
    callf(g, rt.check);
    op(g, OP_i32_load);
    uleb(g, 2);
    uleb(g, blot_direct_runtime::entry_capacity);
    i32Const(g, blot_direct_runtime::static_pool_flag);
    op(g, OP_i32_and);
    trap(g, f);
    close(g, f);
}
fn scalarLocal(g: Generator&, f: const Fn&, value: Val, id: u32) -> u32, Error {
    if value.len != 1 { return 0, g.fail(g.units[f.unit - 1], id, "expected a scalar"); }
    return w(g, value, 0), blot_direct_types::Error.none;
}
fn readElement(g: Generator&, f: Fn&, container: Val, index: u32, id: u32, container_core_ty: TId = 0, cache_elem: bool = true) -> Val, Error {
    let element, error = elementOf(g, f, container.ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let step, error = stride(g, f, element, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    if cache_elem && tagOf(g, container.ty) == blot_direct_types::Tag.array && isScalarTag(tagOf(g, element)) {
        let cached_elem = findCheckedElem(f, w(g, container, 0), w(g, container, 1), index, step);
        if cached_elem >= 0 && f.checked_elems[cached_elem].val_local != 0xffffffff && f.checked_elems[cached_elem].val_ty == element {
            return valOf1(g, element, f.checked_elems[cached_elem].val_local), blot_direct_types::Error.none;
        }
    }
    let address, error = elementAddress(g, f, container, index, id, container_core_ty, cache_elem);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let loaded, lerr = loadElement(g, f, address, 0, element, id);
    if lerr != blot_direct_types::Error.none { return neverVal(), lerr; }
    if cache_elem && tagOf(g, container.ty) == blot_direct_types::Tag.array && isScalarTag(tagOf(g, element)) && loaded.len == 1 {
        recordCheckedElemVal(f, w(g, container, 0), w(g, container, 1), index, step, w(g, loaded, 0), element);
    }
    return loaded, blot_direct_types::Error.none;
}
fn constLocal(g: Generator&, f: const Fn&, value: u32) -> u32 {
    let made = local32(g, f);
    i32Const(g, value);
    lset(g, made);
    return made;
}

fn emitDirectArrayBoundsCheck(g: Generator&, f: Fn&, da: DirectArray, index: u32, id: u32) {
    var skip_bounds = false;
    let cf, known = constU32(f, index);
    if known && cf.value < da.length {
        useConstU32(cf);
        skip_bounds = true;
    }
    if !skip_bounds {
        let cm = findCheckedMask(f, index);
        if cm >= 0 && f.checked_masks[cm].has_const && f.checked_masks[cm].max_const < da.length {
            skip_bounds = true;
        }
    }
    if !skip_bounds && !f.checked_range.is_view && f.checked_range.end_local != 0xffffffff && index == f.checked_range.index {
        let ce, ek = constU32(f, f.checked_range.end_local);
        if ek && ce.value <= da.length {
            useConstU32(ce);
            skip_bounds = true;
        }
    }
    if !skip_bounds {
        lget(g, index);
        i32Const(g, da.length);
        op(g, OP_i32_ge_u);
        trapBounds(g, f, id);
    }
}

fn directArrayAddress(g: Generator&, f: Fn&, da: DirectArray, index: u32, id: u32) -> u32 {
    emitDirectArrayBoundsCheck(g, f, da, index, id);
    return emitOffsetAddress(g, f, da.base, index, da.step);
}

fn emitDirectArrayRead(g: Generator&, f: Fn&, da: DirectArray, index: u32, id: u32) -> Val, Error {
    if !da.scalar_packed {
        let addr = directArrayAddress(g, f, da, index, id);
        return loadElement(g, f, addr, 0, da.elem_ty, id);
    }
    emitDirectArrayBoundsCheck(g, f, da, index, id);
    let out_loc = local32(g, f);
    let cf, known = constU32(f, index);
    if known && cf.value < da.length {
        useConstU32(cf);
        let src_word = if cf.value < 8 { da.pack_lo } else { da.pack_hi };
        let sh = ((cf.value & 7) * 8) as i64;
        lget(g, src_word);
        if sh != 0 {
            i64Const(g, sh);
            op(g, OP_i64_shr_u);
        }
        op(g, OP_i32_wrap_i64);
        i32Const(g, 0xff);
        op(g, OP_i32_and);
        lset(g, out_loc);
        return valOf1(g, da.elem_ty, out_loc), blot_direct_types::Error.none;
    }
    if da.pack_hi == 0xffffffff {
        lget(g, da.pack_lo);
        lget(g, index);
        i32Const(g, 3);
        op(g, OP_i32_shl);
        op(g, OP_i64_extend_i32_u);
    } else {
        lget(g, da.pack_hi);
        lget(g, da.pack_lo);
        lget(g, index);
        i32Const(g, 8);
        op(g, OP_i32_ge_u);
        op(g, OP_select);
        lget(g, index);
        i32Const(g, 7);
        op(g, OP_i32_and);
        i32Const(g, 3);
        op(g, OP_i32_shl);
        op(g, OP_i64_extend_i32_u);
    }
    op(g, OP_i64_shr_u);
    op(g, OP_i32_wrap_i64);
    i32Const(g, 0xff);
    op(g, OP_i32_and);
    lset(g, out_loc);
    return valOf1(g, da.elem_ty, out_loc), blot_direct_types::Error.none;
}

fn emitDirectArrayWrite(g: Generator&, f: Fn&, da: DirectArray, index: u32, replacement: Val, id: u32) -> Error {
    if !da.scalar_packed {
        let addr = directArrayAddress(g, f, da, index, id);
        return writeElement(g, f, addr, 0, replacement, id);
    }
    emitDirectArrayBoundsCheck(g, f, da, index, id);
    let cf, known = constU32(f, index);
    if known && cf.value < da.length {
        useConstU32(cf);
        let target_word = if cf.value < 8 { da.pack_lo } else { da.pack_hi };
        let sh = ((cf.value & 7) * 8) as u64;
        let clear_mask: u64 = ((0xff as u64) << sh) ^ 0xffffffffffffffff;
        lget(g, target_word);
        i64Const(g, clear_mask as! i64);
        op(g, OP_i64_and);
        lget(g, w(g, replacement, 0));
        i32Const(g, 0xff);
        op(g, OP_i32_and);
        op(g, OP_i64_extend_i32_u);
        if sh != 0 {
            i64Const(g, sh as i64);
            op(g, OP_i64_shl);
        }
        op(g, OP_i64_or);
        lset(g, target_word);
        return blot_direct_types::Error.none;
    }
    let sh64 = local(g, f, VT_i64);
    lget(g, index);
    if da.pack_hi != 0xffffffff {
        i32Const(g, 7);
        op(g, OP_i32_and);
    }
    i32Const(g, 3);
    op(g, OP_i32_shl);
    op(g, OP_i64_extend_i32_u);
    lset(g, sh64);
    let keep_mask = local(g, f, VT_i64);
    i64Const(g, 0xff);
    lget(g, sh64);
    op(g, OP_i64_shl);
    i64Const(g, -1);
    op(g, OP_i64_xor);
    lset(g, keep_mask);
    let ins_bits = local(g, f, VT_i64);
    lget(g, w(g, replacement, 0));
    i32Const(g, 0xff);
    op(g, OP_i32_and);
    op(g, OP_i64_extend_i32_u);
    lget(g, sh64);
    op(g, OP_i64_shl);
    lset(g, ins_bits);
    if da.pack_hi == 0xffffffff {
        lget(g, da.pack_lo);
        lget(g, keep_mask);
        op(g, OP_i64_and);
        lget(g, ins_bits);
        op(g, OP_i64_or);
        lset(g, da.pack_lo);
    } else {
        lget(g, index);
        i32Const(g, 8);
        op(g, OP_i32_lt_u);
        let _ = open(g, f, OP_if_);
        lget(g, da.pack_lo);
        lget(g, keep_mask);
        op(g, OP_i64_and);
        lget(g, ins_bits);
        op(g, OP_i64_or);
        lset(g, da.pack_lo);
        op(g, OP_else_);
        lget(g, da.pack_hi);
        lget(g, keep_mask);
        op(g, OP_i64_and);
        lget(g, ins_bits);
        op(g, OP_i64_or);
        lset(g, da.pack_hi);
        close(g, f);
    }
    return blot_direct_types::Error.none;
}

fn extractConstScalar(tm: const Module&, id: u32, elem_tag: blot_direct_types::Tag) -> u32, u32, bool {
    if id == 0 { return 0, 0, false; }
    let n = tm.node(id);
    if n.tag == blot_check_core::Tag.constant {
        match elem_tag {
            boolean => {
                if n.a > 1 { return 0, 0, false; }
                return n.a, 0, true;
            },
            u8_ => {
                if n.a > 255 { return 0, 0, false; }
                return n.a, 0, true;
            },
            u32_, i32_, f32_ => { return n.a, 0, true; },
            u64_, i64_, f64_ => { return n.a, n.b, true; },
            _ => { return 0, 0, false; },
        }
    }
    if n.tag == blot_check_core::Tag.scalar && n.op == blot_check_core::Op.neg && n.b == 0 {
        let cn = tm.node(n.a);
        if cn.tag != blot_check_core::Tag.constant { return 0, 0, false; }
        match elem_tag {
            i32_ => { return (0 as u32) - cn.a, 0, true; },
            i64_ => {
                let v: u64 = (0 as u64) - ((cn.a as u64) | ((cn.b as u64) << 32));
                return v as! u32, (v >> 32) as! u32, true;
            },
            f32_ => {
                if (cn.a & 0x7fffffff) <= 0x7f800000 { return cn.a ^ 0x80000000, 0, true; }
                return 0, 0, false;
            },
            f64_ => {
                let hi = cn.b & 0x7fffffff;
                if hi < 0x7ff00000 || (hi == 0x7ff00000 && cn.a == 0) {
                    return cn.a, cn.b ^ 0x80000000, true;
                }
                return 0, 0, false;
            },
            _ => { return 0, 0, false; },
        }
    }
    return 0, 0, false;
}

fn tryResolveRodata(g: Generator&, f: const Fn&, ref_node: u32) -> blot_direct_emit::RodataEntry, bool {
    if ref_node == 0 { return blot_direct_emit::RodataEntry {}, false; }
    let m .= g.units[f.unit - 1];
    if m.node(ref_node).tag != blot_check_core::Tag.reference { return blot_direct_emit::RodataEntry {}, false; }
    let ref = m.reference(ref_node);
    if ref.unit == 0 || ref.unit == m.unit {
        let _, bound_here = bindGet(g, f, ref.binding);
        if bound_here { return blot_direct_emit::RodataEntry {}, false; }
        let _, is_poly = g.s.polymorphic.get(polyKey(f, ref.binding));
        if is_poly { return blot_direct_emit::RodataEntry {}, false; }
    }
    let target = g.resolve(m, ref);
    if !g.hasUnit(target.unit) { return blot_direct_emit::RodataEntry {}, false; }
    let tm .= g.units[target.unit - 1];
    let body .= tm.body(target.binding);
    if !body || body.is_function || body.scheme.variables.len != 0 { return blot_direct_emit::RodataEntry {}, false; }
    let root = unwrapSingleBody(tm, body.root);
    if root == 0 || tm.node(root).tag != blot_check_core::Tag.array { return blot_direct_emit::RodataEntry {}, false; }
    let key = blot_direct_emit::key64(target.unit, target.binding);
    let cached, found = g.s.rodata_map.get(key);
    if found && cached != 0 && ((cached - 1) as i64) < g.s.rodata_entries.len {
        g.recordInlined(target.unit, target.binding);
        blot_direct_relocations::unpatchableOperand(target.unit, root);
        return g.s.rodata_entries[(cached - 1) as i64], true;
    }
    let children = tm.children(root);
    if children.len > 65536 { return blot_direct_emit::RodataEntry {}, false; }
    let arr_ty, aerr = g.types.lower(tm, tm.binding(target.binding).ty, Env {});
    if aerr != blot_direct_types::Error.none {
        g.dropFailure();
        return blot_direct_emit::RodataEntry {}, false;
    }
    if tagOf(g, arr_ty) != blot_direct_types::Tag.array { return blot_direct_emit::RodataEntry {}, false; }
    let elem_ty = g.types.node(arr_ty).a;
    let elem_tag = tagOf(g, elem_ty);
    var step: u32 = 0;
    match elem_tag {
        boolean, u8_ => { step = 1; },
        u32_, i32_, f32_ => { step = 4; },
        u64_, i64_, f64_ => { step = 8; },
        _ => { return blot_direct_emit::RodataEntry {}, false; },
    }
    let byte_len = (children.len as u32) * step;
    if (g.module.data.len as u32) + byte_len + 16 > 262144 { return blot_direct_emit::RodataEntry {}, false; }
    for child in children {
        let _, _, ok = extractConstScalar(tm, child, elem_tag);
        if !ok { return blot_direct_emit::RodataEntry {}, false; }
    }
    if g.s.parallel_readonly {
        g.s.parallel_aborted = true;
        return blot_direct_emit::RodataEntry {}, false;
    }
    if !g.module.has_memory {
        g.module.has_memory = true;
        g.module.memory_pages = 1;
        g.module.memory_max_pages = 1;
    }
    let align: i64 = if step > 8 { step as i64 } else { 8 };
    while (g.module.data.len % align) != 0 { g.module.data.push(0); }
    let addr = blot_direct_runtime::arena_start + (g.module.data.len as u32);
    for child in children {
        let low, high, _ = extractConstScalar(tm, child, elem_tag);
        if step == 1 {
            g.module.data.push((low & 0xff) as! u8);
        } else if step == 4 {
            g.module.data.push((low & 0xff) as! u8);
            g.module.data.push(((low >> 8) & 0xff) as! u8);
            g.module.data.push(((low >> 16) & 0xff) as! u8);
            g.module.data.push(((low >> 24) & 0xff) as! u8);
        } else {
            g.module.data.push((low & 0xff) as! u8);
            g.module.data.push(((low >> 8) & 0xff) as! u8);
            g.module.data.push(((low >> 16) & 0xff) as! u8);
            g.module.data.push(((low >> 24) & 0xff) as! u8);
            g.module.data.push((high & 0xff) as! u8);
            g.module.data.push(((high >> 8) & 0xff) as! u8);
            g.module.data.push(((high >> 16) & 0xff) as! u8);
            g.module.data.push(((high >> 24) & 0xff) as! u8);
        }
    }
    let entry = blot_direct_emit::RodataEntry {
        addr: addr,
        count: children.len as u32,
        byte_len: byte_len,
        elem_ty: elem_ty,
        step: step,
    };
    g.s.rodata_entries.push(entry);
    g.s.rodata_map.put(key, g.s.rodata_entries.len as u32);
    g.recordInlined(target.unit, target.binding);
    blot_direct_relocations::unpatchableOperand(target.unit, root);
    return entry, true;
}

fn emitRodataRead(g: Generator&, f: Fn&, rd: blot_direct_emit::RodataEntry, idx_node: u32, id: u32) -> Val, Error {
    let position, perr = expr(g, f, idx_node);
    if perr != blot_direct_types::Error.none { return position, perr; }
    let index, ierr = scalarLocal(g, f, position, id);
    if ierr != blot_direct_types::Error.none { return neverVal(), ierr; }
    let cf, known = constU32(f, index);
    if known && cf.value < rd.count {
        useConstU32(cf);
        let zero = constLocal(g, f, 0);
        return loadElement(g, f, zero, rd.addr + cf.value * rd.step, rd.elem_ty, id);
    }
    var skip_bounds = false;
    let cm = findCheckedMask(f, index);
    if cm >= 0 && f.checked_masks[cm].has_const && f.checked_masks[cm].max_const < rd.count {
        skip_bounds = true;
    }
    if !skip_bounds && !f.checked_range.is_view && f.checked_range.end_local != 0xffffffff && index == f.checked_range.index {
        let ce, ek = constU32(f, f.checked_range.end_local);
        if ek && ce.value <= rd.count {
            useConstU32(ce);
            skip_bounds = true;
        }
    }
    if !skip_bounds {
        lget(g, index);
        i32Const(g, rd.count);
        op(g, OP_i32_ge_u);
        trapBounds(g, f, id);
    }
    let scaled = if rd.step == 1 { index } else { emitScaledBytes(g, f, index, rd.step) };
    return loadElement(g, f, scaled, rd.addr, rd.elem_ty, id);
}

fn emitExtendFromRodata(g: Generator&, f: Fn&, dst: Val, is_direct: bool, rd: blot_direct_emit::RodataEntry, id: u32) -> Val, Error {
    let element, eerr = elementOf(g, f, dst.ty, id);
    if eerr != blot_direct_types::Error.none { return neverVal(), eerr; }
    let step, sterr = stride(g, f, element, id);
    if sterr != blot_direct_types::Error.none { return neverVal(), sterr; }
    let rt = g.runtime_();
    let fast_eligible = !rt.has_fork && step > 0 && step <= 65536 && tagOf(g, dst.ty) == blot_direct_types::Tag.array;
    var dst_entry: u32 = 0;
    var dst_len: u32 = 0;
    if fast_eligible {
        dst_entry = ensureCheckedGrow(g, f, dst);
        dst_len = local32(g, f);
        lget(g, dst_entry);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
        lset(g, dst_len);
    } else {
        let dl, dlerr = lengthOf(g, f, dst, id);
        if dlerr != blot_direct_types::Error.none { return neverVal(), dlerr; }
        dst_len = dl;
    }
    var next_len = dst_len;
    if rd.count > 0 {
        next_len = local32(g, f);
        lget(g, dst_len);
        i32Const(g, rd.count);
        op(g, OP_i32_add);
        ltee(g, next_len);
        lget(g, dst_len);
        op(g, OP_i32_lt_u);
        trap(g, f);
    }
    if fast_eligible {
        let max_elems = if blot_direct_runtime::capacity_mask / step < 0x04000000 { blot_direct_runtime::capacity_mask / step } else { 0x04000000 };
        let need_bytes = emitScaledBytes(g, f, next_len, step);
        let cap = local32(g, f);
        lget(g, dst_entry);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_capacity);
        ltee(g, cap);
        i32Const(g, blot_direct_runtime::flag_mask ^ blot_direct_runtime::heap_flag);
        op(g, OP_i32_and);
        i32Const(g, blot_direct_runtime::live_flag);
        op(g, OP_i32_eq);
        lget(g, next_len);
        i32Const(g, max_elems);
        op(g, OP_i32_le_u);
        op(g, OP_i32_and);
        lget(g, need_bytes);
        lget(g, cap);
        i32Const(g, blot_direct_runtime::capacity_mask);
        op(g, OP_i32_and);
        op(g, OP_i32_le_u);
        op(g, OP_i32_and);
        op(g, OP_i32_eqz);
        let need_grow = open(g, f, OP_if_);
        lget(g, w(g, dst, 0));
        lget(g, w(g, dst, 1));
        lget(g, next_len);
        i32Const(g, step);
        callf(g, rt.reserve);
        popCheckedArraysAt(f, need_grow);
        close(g, f);
    } else {
        lget(g, w(g, dst, 0));
        lget(g, w(g, dst, 1));
        lget(g, next_len);
        i32Const(g, step);
        callf(g, rt.reserve);
    }
    if rd.count > 0 {
        if !fast_eligible {
            dst_entry = local32(g, f);
            lget(g, w(g, dst, 0));
            lget(g, w(g, dst, 1));
            callf(g, rt.check);
            lset(g, dst_entry);
        }
        let dst_base = local32(g, f);
        lget(g, dst_entry);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
        lset(g, dst_base);
        let dst_ptr = emitOffsetAddress(g, f, dst_base, dst_len, step);
        if rt.has_fork {
            recordBeforeWrite(g, f, w(g, dst, 0), dst_entry, blot_direct_runtime::entry_length, 4);
        }
        let data_start = (rd.addr - blot_direct_runtime::arena_start) as i64;
        if rd.byte_len <= 16 && data_start + (rd.byte_len as i64) <= g.module.data.len {
            var off: u32 = 0;
            while off < rd.byte_len {
                let rem = rd.byte_len - off;
                let di = data_start + (off as i64);
                if rem >= 8 {
                    let v64: u64 =
                        (g.module.data[di] as u64) |
                        ((g.module.data[di + 1] as u64) << 8) |
                        ((g.module.data[di + 2] as u64) << 16) |
                        ((g.module.data[di + 3] as u64) << 24) |
                        ((g.module.data[di + 4] as u64) << 32) |
                        ((g.module.data[di + 5] as u64) << 40) |
                        ((g.module.data[di + 6] as u64) << 48) |
                        ((g.module.data[di + 7] as u64) << 56);
                    lget(g, dst_ptr);
                    i64Const(g, v64 as! i64);
                    op(g, OP_i64_store); uleb(g, 0); uleb(g, off);
                    off += 8;
                } else if rem >= 4 {
                    let v32: u32 =
                        (g.module.data[di] as u32) |
                        ((g.module.data[di + 1] as u32) << 8) |
                        ((g.module.data[di + 2] as u32) << 16) |
                        ((g.module.data[di + 3] as u32) << 24);
                    lget(g, dst_ptr);
                    i32Const(g, v32);
                    op(g, OP_i32_store); uleb(g, 0); uleb(g, off);
                    off += 4;
                } else if rem >= 2 {
                    let v16: u32 = (g.module.data[di] as u32) | ((g.module.data[di + 1] as u32) << 8);
                    lget(g, dst_ptr);
                    i32Const(g, v16);
                    op(g, OP_i32_store16); uleb(g, 0); uleb(g, off);
                    off += 2;
                } else {
                    lget(g, dst_ptr);
                    i32Const(g, g.module.data[di] as u32);
                    op(g, OP_i32_store8); uleb(g, 0); uleb(g, off);
                    off += 1;
                }
            }
        } else {
            lget(g, dst_ptr);
            i32Const(g, rd.addr);
            i32Const(g, rd.byte_len);
            memoryCopyOp(g);
        }
        lget(g, dst_entry);
        lget(g, next_len);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
    }
    if is_direct && tagOf(g, dst.ty) == blot_direct_types::Tag.array {
        invalidateCheckedOwner(g, f, dst);
    } else {
        invalidateCheckedContainers(f);
    }
    return dst, blot_direct_types::Error.none;
}

recursive fn tryEmitDirectLocalArray(g: Generator&, f: Fn&, binding: u32, init_id: u32, id: u32) -> Val, bool, Error {
    let m .= g.units[f.unit - 1];
    let init_n = m.node(init_id);
    var is_lit = false;
    var count_val: u32 = 0;
    var count_node: u32 = 0;
    var fill_val_node: u32 = 0;
    if init_n.tag == blot_check_core::Tag.array {
        let ch = m.children(init_id);
        if ch.len < 1 || ch.len > 32 { return neverVal(), false, blot_direct_types::Error.none; }
        is_lit = true;
        count_val = ch.len as u32;
    } else if init_n.tag == blot_check_core::Tag.array_op && m.arrayOperation(init_id) == blot_backend_collection_ops::Op.fill {
        let ch = m.children(init_id);
        if ch.len != 2 { return neverVal(), false, blot_direct_types::Error.none; }
        let cn = m.node(ch[0]);
        if cn.tag != blot_check_core::Tag.constant || cn.a < 1 || cn.a > 32 { return neverVal(), false, blot_direct_types::Error.none; }
        count_val = cn.a;
        count_node = ch[0];
        fill_val_node = ch[1];
    } else {
        return neverVal(), false, blot_direct_types::Error.none;
    }
    let arr_ty, ty_err = g.types.lower(m, m.binding(binding).ty, f.env);
    if ty_err != blot_direct_types::Error.none {
        g.dropFailure();
        return neverVal(), false, blot_direct_types::Error.none;
    }
    if tagOf(g, arr_ty) != blot_direct_types::Tag.array { return neverVal(), false, blot_direct_types::Error.none; }
    let elem_ty, eerr = elementOf(g, f, arr_ty, id);
    if eerr != blot_direct_types::Error.none || !isScalarTag(tagOf(g, elem_ty)) {
        return neverVal(), false, blot_direct_types::Error.none;
    }
    let root = currentBodyRoot(g, f);
    var needs_addr = false;
    if root == 0 || !isDirectLocalArrayBinding(g, f, m, root, binding, needs_addr) {
        return neverVal(), false, blot_direct_types::Error.none;
    }
    let step, serr = stride(g, f, elem_ty, id);
    if serr != blot_direct_types::Error.none { return neverVal(), false, serr; }
    let total_bytes = count_val * step;
    let slot_local = constLocal(g, f, 0);
    let len_local = constLocal(g, f, count_val);
    recordConstU32(f, len_local, count_val);
    let pack_scalar = !needs_addr && step == 1 && count_val <= 16 &&
        (tagOf(g, elem_ty) == blot_direct_types::Tag.u8_ || tagOf(g, elem_ty) == blot_direct_types::Tag.boolean);
    if pack_scalar {
        let pack_lo = local(g, f, VT_i64);
        let pack_hi = if count_val > 8 { local(g, f, VT_i64) } else { 0xffffffff };
        if is_lit {
            let ch = m.children(init_id);
            for child, at in ch {
                let v, verr = expr(g, f, child);
                if verr != blot_direct_types::Error.none { return v, false, verr; }
                let target_w = if at < 8 { pack_lo } else { pack_hi };
                let sh = ((at & 7) * 8) as i64;
                if at != 0 && at != 8 { lget(g, target_w); }
                lget(g, w(g, v, 0));
                i32Const(g, 0xff);
                op(g, OP_i32_and);
                op(g, OP_i64_extend_i32_u);
                if sh != 0 {
                    i64Const(g, sh);
                    op(g, OP_i64_shl);
                }
                if at != 0 && at != 8 { op(g, OP_i64_or); }
                lset(g, target_w);
            }
        } else {
            let val, verr = expr(g, f, fill_val_node);
            if verr != blot_direct_types::Error.none { return val, false, verr; }
            blot_direct_relocations::unpatchableOperand(m.unit, count_node);
            let skip_fill = consumeSkipFillNode(f, init_id);
            let vf, vknown = constU32(f, w(g, val, 0));
            let is_zero_fill = vknown && (vf.value & 0xff) == 0;
            if is_zero_fill { useConstU32(vf); }
            if !skip_fill && !is_zero_fill {
                lget(g, w(g, val, 0));
                i32Const(g, 0xff);
                op(g, OP_i32_and);
                op(g, OP_i64_extend_i32_u);
                i64Const(g, 0x0101010101010101);
                op(g, OP_i64_mul);
                if pack_hi != 0xffffffff {
                    ltee(g, pack_lo);
                    lset(g, pack_hi);
                } else {
                    lset(g, pack_lo);
                }
            }
        }
        recordDirectArray(f, binding, slot_local, 0, len_local, count_val, elem_ty, step, true, pack_lo, pack_hi);
        let dummy = valOf2(g, arr_ty, slot_local, slot_local);
        recordMutable(g, f, dummy);
        return dummy, true, blot_direct_types::Error.none;
    }
    if is_lit {
        let ch = m.children(init_id);
        let values = g.reserveVals(ch.len);
        for child, at in ch {
            let v, verr = expr(g, f, child);
            if verr != blot_direct_types::Error.none { return v, false, verr; }
            g.s.vals[values.start + at] = v;
        }
        let base = allocate(g, f, total_bytes);
        for i in 0..(count_val as i64) {
            let werr = writeElement(g, f, base, (i as u32) * step, g.s.vals[values.start + i], id);
            if werr != blot_direct_types::Error.none { return neverVal(), false, werr; }
        }
        recordDirectArray(f, binding, slot_local, base, len_local, count_val, elem_ty, step);
    } else {
        let val, verr = expr(g, f, fill_val_node);
        if verr != blot_direct_types::Error.none { return val, false, verr; }
        blot_direct_relocations::unpatchableOperand(m.unit, count_node);
        let base = allocate(g, f, total_bytes);
        let skip_fill = consumeSkipFillNode(f, init_id);
        if !skip_fill {
            if step == 1 && val.len == 1 {
                lget(g, base);
                lget(g, w(g, val, 0));
                i32Const(g, total_bytes);
                memoryFillOp(g);
            } else if count_val <= 8 {
                for i in 0..(count_val as i64) {
                    let werr = writeElement(g, f, base, (i as u32) * step, val, id);
                    if werr != blot_direct_types::Error.none { return neverVal(), false, werr; }
                }
            } else {
                let ptr = local32(g, f);
                let end_ptr = local32(g, f);
                lget(g, base);
                ltee(g, ptr);
                i32Const(g, total_bytes);
                op(g, OP_i32_add);
                lset(g, end_ptr);
                let exit = open(g, f, OP_block);
                let top = open(g, f, OP_loop);
                lget(g, ptr);
                lget(g, end_ptr);
                op(g, OP_i32_ge_u);
                br(g, f, OP_br_if, exit);
                let werr = writeElement(g, f, ptr, 0, val, id);
                if werr != blot_direct_types::Error.none { return neverVal(), false, werr; }
                lget(g, ptr);
                i32Const(g, step);
                op(g, OP_i32_add);
                lset(g, ptr);
                br(g, f, OP_br, top);
                close(g, f);
                close(g, f);
            }
        }
        recordDirectArray(f, binding, slot_local, base, len_local, count_val, elem_ty, step);
    }
    let dummy = valOf2(g, arr_ty, slot_local, slot_local);
    recordMutable(g, f, dummy);
    return dummy, true, blot_direct_types::Error.none;
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
    recordConstU32(f, count, values.len);
    if values.len == 0 { return create(g, f, ty, count, id); }
    let handle, base, error = createUninit(g, f, ty, count, id);
    if error != blot_direct_types::Error.none { return handle, error; }
    let element, error = elementOf(g, f, ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let step, error = stride(g, f, element, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    for index in 0..(values.len as i64) {
        let written = writeElement(g, f, base, (index as u32) * step, g.s.vals[values.start + index], id);
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
            let da_idx = findDirectArray(f, localRef(m, children[0]));
            if da_idx >= 0 {
                let klen = constLocal(g, f, f.direct_arrays[da_idx].length);
                recordConstU32(f, klen, f.direct_arrays[da_idx].length);
                return valOf1(g, blot_direct_types::u32_, klen), blot_direct_types::Error.none;
            }
            let rd, is_rd = tryResolveRodata(g, f, children[0]);
            if is_rd {
                let klen = constLocal(g, f, rd.count);
                recordConstU32(f, klen, rd.count);
                return valOf1(g, blot_direct_types::u32_, klen), blot_direct_types::Error.none;
            }
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let length, error = lengthOf(g, f, container, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            return valOf1(g, blot_direct_types::u32_, length), blot_direct_types::Error.none;
        },
        get => {
            let da_idx = findDirectArray(f, localRef(m, children[0]));
            if da_idx >= 0 {
                let da = f.direct_arrays[da_idx];
                let position, perr = expr(g, f, children[1]);
                if perr != blot_direct_types::Error.none { return position, perr; }
                let index, ierr = scalarLocal(g, f, position, id);
                if ierr != blot_direct_types::Error.none { return neverVal(), ierr; }
                return emitDirectArrayRead(g, f, da, index, id);
            }
            let rd, is_rd = tryResolveRodata(g, f, children[0]);
            if is_rd {
                return emitRodataRead(g, f, rd, children[1], id);
            }
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let position, error = expr(g, f, children[1]);
            if error != blot_direct_types::Error.none { return position, error; }
            let index, error = scalarLocal(g, f, position, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            return readElement(g, f, container, index, id, m.typeOf(children[0]));
        },
        identity => {
            let value, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return value, error; }
            return Val { ty, value.start, value.len }, blot_direct_types::Error.none;
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
            let written = writeElement(g, f, address, 0, value, id);
            if written != blot_direct_types::Error.none { return neverVal(), written; }
            return replaced, blot_direct_types::Error.none;
        },
        fill, generate => {
            let gen_arg0 = children[0];
            let gen_arg1 = children[1];
            let counted, error = expr(g, f, gen_arg0);
            if error != blot_direct_types::Error.none { return counted, error; }
            let count, error = scalarLocal(g, f, counted, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            if operation == blot_backend_collection_ops::Op.generate && m.node(gen_arg1).tag == blot_check_core::Tag.closure && has_declared {
                let inlined, did_inline, ierr = tryEmitGenerateInlineClosure(g, f, count, gen_arg1, declared, id);
                if ierr != blot_direct_types::Error.none { return inlined, ierr; }
                if did_inline { return inlined, blot_direct_types::Error.none; }
            }
            let source, error = expr(g, f, gen_arg1);
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
            let skip_fill = operation == blot_backend_collection_ops::Op.fill && consumeSkipFillNode(f, id);
            return emitFillOrGenerate(g, f, operation == blot_backend_collection_ops::Op.fill, count, source, ty_, id, skip_fill);
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
            trapBounds(g, f, id);
            let handle, _, error = createUninit(g, f, ty, count, id);
            if error != blot_direct_types::Error.none { return handle, error; }
            let zero = constLocal(g, f, 0);
            let copied = copyElements(g, f, container, start, handle, zero, count, id);
            if copied != blot_direct_types::Error.none { return neverVal(), copied; }
            return handle, blot_direct_types::Error.none;
        },
        simd_load, simd_store, simd_load_u8x16, simd_store_u8x16, simd_load_f64x2, simd_store_f64x2 => {
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let position, error = expr(g, f, children[1]);
            if error != blot_direct_types::Error.none { return position, error; }
            let index, error = scalarLocal(g, f, position, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let element, error = elementOf(g, f, container.ty, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let step, error = stride(g, f, element, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let core_ty = m.typeOf(children[0]);
            let is_u8x16 = operation == blot_backend_collection_ops::Op.simd_load_u8x16 || operation == blot_backend_collection_ops::Op.simd_store_u8x16;
            let is_f64x2 = operation == blot_backend_collection_ops::Op.simd_load_f64x2 || operation == blot_backend_collection_ops::Op.simd_store_f64x2;
            var lane_count: u32 = 4;
            if is_u8x16 { lane_count = 16; } else if is_f64x2 { lane_count = 2; }
            let address, error = simdAddress(g, f, container, index, step, id, core_ty, lane_count);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            if operation == blot_backend_collection_ops::Op.simd_load {
                return simdLoadAt(g, f, address, element, step, id);
            }
            if operation == blot_backend_collection_ops::Op.simd_load_u8x16 {
                return simdLoadWideAt(g, f, address, false, id);
            }
            if operation == blot_backend_collection_ops::Op.simd_load_f64x2 {
                return simdLoadWideAt(g, f, address, true, id);
            }
            let lanes_value, error = expr(g, f, children[2]);
            if error != blot_direct_types::Error.none { return lanes_value, error; }
            var rhs_budget: i64 = 128;
            let rhs_safe = tagOf(g, container.ty) == blot_direct_types::Tag.array &&
                (coreSizedLength(m, core_ty) != 0 || noStorageResize(g, m, children[2], rhs_budget));
            if is_u8x16 || is_f64x2 {
                return simdStoreWideAt(g, f, container, index, address, is_f64x2, lanes_value, rhs_safe, id, core_ty);
            }
            return simdStoreAt(g, f, container, index, address, element, step, lanes_value, rhs_safe, id, core_ty);
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
// One logical bounds trap for the whole vector interval. Testing
// length before subtracting lane_count keeps even a maximally large U32 index safe.
fn simdAddress(g: Generator&, f: Fn&, container: Val, index: u32, step: u32, id: u32, core_ty: TId = 0, lane_count: u32 = 4) -> u32, Error {
    if tagOf(g, container.ty) == blot_direct_types::Tag.array {
        let base, len = ensureCheckedArray(g, f, container);
        lget(g, len);
        i32Const(g, lane_count);
        op(g, OP_i32_lt_u);
        lget(g, index);
        lget(g, len);
        i32Const(g, lane_count);
        op(g, OP_i32_sub);
        op(g, OP_i32_gt_u);
        op(g, OP_i32_or);
        trapBounds(g, f, id);
        return emitOffsetAddress(g, f, base, index, step), blot_direct_types::Error.none;
    }
    // Views retain their existing handle and subrange checks.
    let last = local32(g, f);
    lget(g, index);
    i32Const(g, lane_count - 1);
    op(g, OP_i32_add);
    ltee(g, last);
    lget(g, index);
    op(g, OP_i32_lt_u);
    trapBounds(g, f, id);
    let _, error = elementAddress(g, f, container, last, id, core_ty);
    if error != blot_direct_types::Error.none { return 0, error; }
    return elementAddress(g, f, container, index, id, core_ty);
}
fn simdLoadWideAt(g: Generator&, f: Fn&, address: u32, is_float: bool, id: u32) -> Val, Error {
    let elem = if is_float { blot_direct_types::f64_ } else { blot_direct_types::u64_ };
    let lane_ty, error = g.types.tuple([elem, elem]);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    lget(g, address);
    simdMemOp(g, SIMD_v128_load, if is_float { 3 } else { 0 }, 0);
    return popV128(g, f, lane_ty), blot_direct_types::Error.none;
}
fn simdStoreWideAt(g: Generator&, f: Fn&, container: Val, index: u32, address: u32, is_float: bool, lanes_value: Val, rhs_safe: bool, id: u32, core_ty: TId = 0) -> Val, Error {
    checkMutableOwner(g, f, container);
    var target = address;
    if !rhs_safe {
        let step: u32 = if is_float { 8 } else { 1 };
        let count: u32 = if is_float { 2 } else { 16 };
        let recomputed, error = simdAddress(g, f, container, index, step, id, core_ty, count);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        target = recomputed;
    }
    recordBeforeWrite(g, f, w(g, container, 0), target, 0, 16);
    let vector = ensureV128(g, f, lanes_value);
    lget(g, target);
    lget(g, vector);
    simdMemOp(g, SIMD_v128_store, if is_float { 3 } else { 0 }, 0);
    f.checked_elems_len = 0;
    return container, blot_direct_types::Error.none;
}
fn hasV128Elements(element: Ty) -> bool {
    return element == blot_direct_types::f32_ || element == blot_direct_types::u32_;
}
fn simdLoadAt(g: Generator&, f: Fn&, address: u32, element: Ty, step: u32, id: u32) -> Val, Error {
    let lane_ty, error = g.types.tuple([element, element, element, element]);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    if hasV128Elements(element) {
        lget(g, address);
        simdMemOp(g, SIMD_v128_load, 2, 0);
        return popV128(g, f, lane_ty), blot_direct_types::Error.none;
    }
    let lanes_vals = g.reserveVals(4);
    for lane in 0..4 {
        var addr = address;
        var offset = (lane as u32) * step;
        // Boxed element reads copy a block from their base address.
        if offset != 0 && element != blot_direct_types::boolean {
            addr = local32(g, f);
            lget(g, address);
            i32Const(g, offset);
            op(g, OP_i32_add);
            lset(g, addr);
            offset = 0;
        }
        let value, error = loadElement(g, f, addr, offset, element, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        g.s.vals[lanes_vals.start + lane] = value;
    }
    return packProduct(g, f, id, lane_ty, lanes_vals);
}
fn simdStoreAt(g: Generator&, f: Fn&, container: Val, index: u32, address: u32, element: Ty, step: u32, lanes_value: Val, rhs_safe: bool, id: u32, core_ty: TId = 0) -> Val, Error {
    // checkMutableOwner elides the runtime guard for a knownMutable owner.
    checkMutableOwner(g, f, container);
    let noted = noteStoreToSlot(g, f, w(g, container, 0), lanes_value);
    if noted != blot_direct_types::Error.none { return neverVal(), noted; }
    var target = address;
    if !rhs_safe {
        let recomputed, error = simdAddress(g, f, container, index, step, id, core_ty);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        target = recomputed;
    }
    recordBeforeWrite(g, f, w(g, container, 0), target, 0, step * 4);
    if hasV128Elements(element) {
        let vector = ensureV128(g, f, lanes_value);
        lget(g, target);
        lget(g, vector);
        simdMemOp(g, SIMD_v128_store, 2, 0);
    } else {
        for lane in 0..4 {
            let value, error = tupleItem(g, f, lanes_value, lane, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let written = writeElement(g, f, target, (lane as u32) * step, value, id);
            if written != blot_direct_types::Error.none { return neverVal(), written; }
        }
    }
    f.checked_elems_len = 0;
    return container, blot_direct_types::Error.none;
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
fn emitFillOrGenerate(g: Generator&, f: Fn&, is_fill: bool, count: u32, source: Val, ty_: Ty, id: u32, skip_fill: bool = false) -> Val, Error {
    let element, error = elementOf(g, f, ty_, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let step, error = stride(g, f, element, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let handle, base, error = createUninit(g, f, ty_, count, id);
    if error != blot_direct_types::Error.none { return handle, error; }
    let elem_tag = tagOf(g, element);
    // 7B: Skip dead zero/constant memory.fill when an immediately following 0..count loop
    // unconditionally initializes every element before any read.
    if is_fill && skip_fill && source.len == 1 && (step == 1 || step == 4 || step == 8) && isScalarTag(elem_tag) {
        return handle, blot_direct_types::Error.none;
    }
    if is_fill && step == 1 && source.len == 1 && byteElement(elem_tag) {
        lget(g, base);
        lget(g, w(g, source, 0));
        lget(g, count);
        memoryFillOp(g);
        return handle, blot_direct_types::Error.none;
    }
    if is_fill && step == 8 && source.len == 1 &&
        (elem_tag == blot_direct_types::Tag.u64_ || elem_tag == blot_direct_types::Tag.i64_ || elem_tag == blot_direct_types::Tag.f64_) {
        let bytes = emitScaledBytes(g, f, count, 8);
        lget(g, w(g, source, 0));
        if elem_tag == blot_direct_types::Tag.f64_ { op(g, OP_i64_reinterpret_f64); }
        op(g, OP_i64_eqz);
        let opened = open(g, f, OP_if_);
        lget(g, base);
        i32Const(g, 0);
        lget(g, bytes);
        memoryFillOp(g);
        popCheckedArraysAt(f, opened);
        op(g, OP_else_);
        let ptr = local32(g, f);
        let end_ptr = local32(g, f);
        lget(g, base);
        ltee(g, ptr);
        lget(g, bytes);
        op(g, OP_i32_add);
        lset(g, end_ptr);
        let exit = open(g, f, OP_block);
        let top = open(g, f, OP_loop);
        lget(g, ptr);
        lget(g, end_ptr);
        op(g, OP_i32_ge_u);
        br(g, f, OP_br_if, exit);
        lget(g, ptr);
        lget(g, w(g, source, 0));
        if elem_tag == blot_direct_types::Tag.f64_ { op(g, OP_f64_store); } else { op(g, OP_i64_store); }
        uleb(g, 2);
        uleb(g, 0);
        lget(g, ptr);
        i32Const(g, 8);
        op(g, OP_i32_add);
        lset(g, ptr);
        br(g, f, OP_br, top);
        close(g, f);
        close(g, f);
        popCheckedArraysAt(f, opened);
        close(g, f);
        return handle, blot_direct_types::Error.none;
    }
    if is_fill && step == 4 && source.len == 1 && (elem_tag == blot_direct_types::Tag.u32_ || elem_tag == blot_direct_types::Tag.i32_ || elem_tag == blot_direct_types::Tag.boolean || elem_tag == blot_direct_types::Tag.f32_) {
        let bytes = emitScaledBytes(g, f, count, 4);
        let bits = local32(g, f);
        lget(g, w(g, source, 0));
        if elem_tag == blot_direct_types::Tag.f32_ { op(g, OP_i32_reinterpret_f32); }
        ltee(g, bits);
        let byte_val = local32(g, f);
        i32Const(g, 0xff);
        op(g, OP_i32_and);
        ltee(g, byte_val);
        i32Const(g, 0x01010101);
        op(g, OP_i32_mul);
        lget(g, bits);
        op(g, OP_i32_eq);
        let opened = open(g, f, OP_if_);
        lget(g, base);
        lget(g, byte_val);
        lget(g, bytes);
        memoryFillOp(g);
        popCheckedArraysAt(f, opened);
        op(g, OP_else_);
        let ptr = local32(g, f);
        let end_ptr = local32(g, f);
        lget(g, base);
        ltee(g, ptr);
        lget(g, bytes);
        op(g, OP_i32_add);
        lset(g, end_ptr);
        let exit = open(g, f, OP_block);
        let top = open(g, f, OP_loop);
        lget(g, ptr);
        lget(g, end_ptr);
        op(g, OP_i32_ge_u);
        br(g, f, OP_br_if, exit);
        lget(g, ptr);
        lget(g, bits);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, 0);
        lget(g, ptr);
        i32Const(g, 4);
        op(g, OP_i32_add);
        lset(g, ptr);
        br(g, f, OP_br, top);
        close(g, f);
        close(g, f);
        close(g, f);
        return handle, blot_direct_types::Error.none;
    }
    if is_fill {
        let bytes = emitScaledBytes(g, f, count, step);
        let ptr = local32(g, f);
        let end_ptr = local32(g, f);
        lget(g, base);
        ltee(g, ptr);
        lget(g, bytes);
        op(g, OP_i32_add);
        lset(g, end_ptr);
        let exit = open(g, f, OP_block);
        let top = open(g, f, OP_loop);
        lget(g, ptr);
        lget(g, end_ptr);
        op(g, OP_i32_ge_u);
        br(g, f, OP_br_if, exit);
        let written = writeElement(g, f, ptr, 0, source, id);
        if written != blot_direct_types::Error.none { return neverVal(), written; }
        lget(g, ptr);
        i32Const(g, step);
        op(g, OP_i32_add);
        lset(g, ptr);
        br(g, f, OP_br, top);
        close(g, f);
        close(g, f);
        return handle, blot_direct_types::Error.none;
    }
    let index = constLocal(g, f, 0);
    let exit = open(g, f, OP_block);
    let top = open(g, f, OP_loop);
    lget(g, index);
    lget(g, count);
    op(g, OP_i32_ge_u);
    br(g, f, OP_br_if, exit);
    let applied, error = applyClosure(g, f, source, valOf1(g, blot_direct_types::u32_, index), id);
    if error != blot_direct_types::Error.none { return applied, error; }
    let address = emitOffsetAddress(g, f, base, index, step);
    let written = writeElement(g, f, address, 0, applied, id);
    if written != blot_direct_types::Error.none { return neverVal(), written; }
    lget(g, index);
    i32Const(g, 1);
    op(g, OP_i32_add);
    lset(g, index);
    br(g, f, OP_br, top);
    close(g, f);
    close(g, f);
    return handle, blot_direct_types::Error.none;
}
// Inline a direct syntactic closure `(func i => body)` passed to `@array.generate`
// or `std/array.generate` when the body is non-allocating, avoiding closure
// allocation and per-element `call_indirect`.
recursive fn tryEmitGenerateInlineClosure(g: Generator&, f: Fn&, count: u32, closure_node: u32, out_ty: Ty, id: u32) -> Val, bool, Error {
    if tagOf(g, out_ty) != blot_direct_types::Tag.array { return neverVal(), false, blot_direct_types::Error.none; }
    var param_binding: u32 = 0;
    var body_node: u32 = 0;
    {
        let m .= g.units[f.unit - 1];
        if m.node(closure_node).tag != blot_check_core::Tag.closure { return neverVal(), false, blot_direct_types::Error.none; }
        let cinfo = m.closure(closure_node);
        if cinfo.parameter.binding == 0 { return neverVal(), false, blot_direct_types::Error.none; }
        refine(g, f, cinfo.parameter.ty, blot_direct_types::u32_);
        var no_alloc_budget: i64 = 256;
        if !bodyNoAlloc(g, f, m, cinfo.body, no_alloc_budget) {
            return neverVal(), false, blot_direct_types::Error.none;
        }
        param_binding = cinfo.parameter.binding;
        body_node = cinfo.body;
    }
    let elem_ty, eerr = elementOf(g, f, out_ty, id);
    if eerr != blot_direct_types::Error.none || tagOf(g, elem_ty) == blot_direct_types::Tag.never {
        return neverVal(), false, blot_direct_types::Error.none;
    }
    let step, serr = stride(g, f, elem_ty, id);
    if serr != blot_direct_types::Error.none { return neverVal(), false, serr; }
    let handle, base, herr = createUninit(g, f, out_ty, count, id);
    if herr != blot_direct_types::Error.none { return handle, false, herr; }

    let index = constLocal(g, f, 0);
    let ptr = local32(g, f);
    lget(g, base);
    lset(g, ptr);
    let exit = open(g, f, OP_block);
    let top = open(g, f, OP_loop);
    f.checked_elems_len = 0;
    lget(g, index);
    lget(g, count);
    op(g, OP_i32_ge_u);
    br(g, f, OP_br_if, exit);

    let saved_bindings = blot_support_zigmap::clone(g.s.map_pool, f.bindings);
    let saved_labels_base = f.labels_base;
    let s .= g.s;
    let labels_mark = s.labels.len;
    let body_slot = g.newSlot();
    let made, merr = fresh(g, f, elem_ty, id);
    if merr != blot_direct_types::Error.none {
        f.bindings = saved_bindings;
        return neverVal(), false, merr;
    }
    s.slots[body_slot] = blot_direct_emit::Slot { true, made };
    let body_exit = open(g, f, OP_block);
    f.labels_base = labels_mark;
    s.labels.push(blot_direct_emit::Label { target: closure_node, depth: body_exit, result: body_slot, kind: blot_direct_emit::LabelKind.function });
    bindPut(g, f, param_binding, valOf1(g, blot_direct_types::u32_, index));

    let body_val, berr = stmt(g, f, body_node);
    s.labels.resize(labels_mark);
    f.labels_base = saved_labels_base;
    f.bindings = saved_bindings;
    if berr != blot_direct_types::Error.none { return neverVal(), false, berr; }
    if body_val.ty != blot_direct_types::never {
        let delivered = deliver(g, f, body_val, body_slot, id);
        if delivered != blot_direct_types::Error.none { return neverVal(), false, delivered; }
    }
    close(g, f);

    let written = writeElement(g, f, ptr, 0, g.s.slots[body_slot].value, id);
    if written != blot_direct_types::Error.none { return neverVal(), false, written; }
    lget(g, ptr);
    i32Const(g, step);
    op(g, OP_i32_add);
    lset(g, ptr);
    lget(g, index);
    i32Const(g, 1);
    op(g, OP_i32_add);
    lset(g, index);
    br(g, f, OP_br, top);
    close(g, f);
    close(g, f);
    return handle, true, blot_direct_types::Error.none;
}
// Lazily emit `runtime.push_entry(entry: i32, stride: i32) -> addr: i32` for
// validated mutable owner entries (no `has_fork`, caller already validated
// liveness and non-static mutability). Preserves exact `runtime.push` doubling
// growth and heap freeing semantics for arbitrary initial capacities.
fn ensurePushEntryHelper(g: Generator&) -> u32, Error {
    if g.s.push_entry_helper != 0 { return g.s.push_entry_helper, blot_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, blot_direct_types::Error.unsupported; }
    let rt = g.runtime_();
    let fn_id = g.module.addFunction(g.module.signature([VT_i32, VT_i32], [VT_i32]));
    blot_direct_writer::setName(g.module, fn_id, "runtime.push_entry");
    g.s.push_entry_helper = fn_id;
    let s .= g.s;
    let code_mark = s.code.len;
    let sites_mark = blot_direct_relocations::mark();
    let locals_mark = s.locals.len;
    let labels_mark = s.labels.len;
    let handles_mark = s.handles.len;
    let handle_cells_mark = s.handle_cells_len;
    var nf = newFn(g, 1, 0);
    let entry = local(g, nf, VT_i32);
    let stride_loc = local(g, nf, VT_i32);
    nf.parameter_words = 2;
    let capacity = local32(g, nf);
    let length = local32(g, nf);
    let need = local32(g, nf);
    let fresh_ptr = local32(g, nf);
    let size = local32(g, nf);
    lget(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_capacity);
    lset(g, capacity);
    lget(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
    ltee(g, length);
    i32Const(g, 1);
    op(g, OP_i32_add);
    lget(g, stride_loc);
    op(g, OP_i32_mul);
    ltee(g, need);
    lget(g, capacity);
    i32Const(g, blot_direct_runtime::capacity_mask);
    op(g, OP_i32_and);
    op(g, OP_i32_gt_u);
    let need_grow = open(g, nf, OP_if_);
    lget(g, need);
    lget(g, capacity);
    i32Const(g, blot_direct_runtime::capacity_mask);
    op(g, OP_i32_and);
    i32Const(g, 1);
    op(g, OP_i32_shl);
    lget(g, need);
    lget(g, capacity);
    i32Const(g, blot_direct_runtime::capacity_mask);
    op(g, OP_i32_and);
    i32Const(g, 1);
    op(g, OP_i32_shl);
    op(g, OP_i32_gt_u);
    op(g, OP_select);
    callf(g, rt.heap_alloc);
    lset(g, size);
    lset(g, fresh_ptr);
    lget(g, fresh_ptr);
    lget(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
    lget(g, length);
    lget(g, stride_loc);
    op(g, OP_i32_mul);
    memoryCopyOp(g);
    lget(g, capacity);
    i32Const(g, blot_direct_runtime::heap_flag);
    op(g, OP_i32_and);
    i32Const(g, 0);
    op(g, OP_i32_ne);
    lget(g, capacity);
    i32Const(g, blot_direct_runtime::capacity_mask);
    op(g, OP_i32_and);
    i32Const(g, 0);
    op(g, OP_i32_ne);
    op(g, OP_i32_and);
    let free_old = open(g, nf, OP_if_);
    lget(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
    lget(g, capacity);
    i32Const(g, blot_direct_runtime::capacity_mask);
    op(g, OP_i32_and);
    callf(g, rt.heap_free);
    close(g, nf);
    lget(g, entry);
    lget(g, fresh_ptr);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
    lget(g, entry);
    lget(g, size);
    i32Const(g, blot_direct_runtime::heap_flag | blot_direct_runtime::live_flag);
    op(g, OP_i32_or);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, blot_direct_runtime::entry_capacity);
    close(g, nf);
    lget(g, entry);
    lget(g, length);
    i32Const(g, 1);
    op(g, OP_i32_add);
    op(g, OP_i32_store); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
    lget(g, entry);
    op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
    lget(g, length);
    lget(g, stride_loc);
    op(g, OP_i32_mul);
    op(g, OP_i32_add);
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

fn emitStoragePushVal(g: Generator&, f: Fn&, container: Val, value: Val, id: u32, selective: bool = false) -> Val, Error {
    let element, error = elementOf(g, f, container.ty, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let step, error = stride(g, f, element, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    let address = local32(g, f);
    let ctag = tagOf(g, container.ty);
    if !g.runtime_().has_fork && step > 0 && step <= 65536 && ctag == blot_direct_types::Tag.array {
        let wm = findWorkerM(f, w(g, container, 0), w(g, container, 1));
        let entry = ensureCheckedGrow(g, f, container);
        let len = local32(g, f);
        let next_len = local32(g, f);
        lget(g, entry);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
        ltee(g, len);
        i32Const(g, 1);
        op(g, OP_i32_add);
        lset(g, next_len);
        let need = emitScaledBytes(g, f, next_len, step);
        let cap = local32(g, f);
        lget(g, entry);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_capacity);
        let is_mut = wm >= 0 || knownMutable(g, f, container);
        if is_mut {
            i32Const(g, blot_direct_runtime::capacity_mask);
            op(g, OP_i32_and);
            lget(g, need);
            op(g, OP_i32_ge_u);
        } else {
            ltee(g, cap);
            i32Const(g, blot_direct_runtime::flag_mask ^ blot_direct_runtime::heap_flag);
            op(g, OP_i32_and);
            i32Const(g, blot_direct_runtime::live_flag);
            op(g, OP_i32_eq);
            lget(g, need);
            lget(g, cap);
            i32Const(g, blot_direct_runtime::capacity_mask);
            op(g, OP_i32_and);
            op(g, OP_i32_le_u);
            op(g, OP_i32_and);
        }
        let fast = open(g, f, OP_if_);
        lget(g, entry);
        lget(g, next_len);
        op(g, OP_i32_store); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
        let elem_base = local32(g, f);
        lget(g, entry);
        op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
        lset(g, elem_base);
        let fast_addr = emitOffsetAddress(g, f, elem_base, len, step);
        lget(g, fast_addr);
        lset(g, address);
        popCheckedArraysAt(f, fast);
        op(g, OP_else_);
        if wm >= 0 {
            let pe_fn, pe_err = ensurePushEntryHelper(g);
            if pe_err != blot_direct_types::Error.none { return neverVal(), pe_err; }
            lget(g, entry);
            i32Const(g, step);
            callf(g, pe_fn);
        } else {
            lget(g, w(g, container, 0));
            lget(g, w(g, container, 1));
            i32Const(g, step);
            callf(g, g.runtime_().push);
        }
        lset(g, address);
        close(g, f);
    } else {
        lget(g, w(g, container, 0));
        lget(g, w(g, container, 1));
        i32Const(g, step);
        callf(g, g.runtime_().push);
        lset(g, address);
    }
    let noted = noteStoreToSlot(g, f, w(g, container, 0), value);
    if noted != blot_direct_types::Error.none { return neverVal(), noted; }
    if g.runtime_().has_fork {
        recordBeforeWrite(g, f, w(g, container, 0), address, 0, step);
    }
    let written = writeElement(g, f, address, 0, value, id);
    if written != blot_direct_types::Error.none { return neverVal(), written; }
    if selective && tagOf(g, container.ty) == blot_direct_types::Tag.array {
        invalidateCheckedOwner(g, f, container);
    } else {
        invalidateCheckedContainers(f);
    }
    return container, blot_direct_types::Error.none;
}
fn emitStorageViewVal(g: Generator&, f: Fn&, container: Val, start: u32, end: u32, ty: Ty, id: u32) -> Val, Error {
    let length, error = lengthOf(g, f, container, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    lget(g, start);
    lget(g, end);
    op(g, OP_i32_gt_u);
    lget(g, end);
    lget(g, length);
    op(g, OP_i32_gt_u);
    op(g, OP_i32_or);
    trapBounds(g, f, id);
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
    if tagOf(g, container.ty) == blot_direct_types::Tag.array {
        let base, _ = ensureCheckedArray(g, f, container);
        let element, elem_err = elementOf(g, f, ty, id);
        if elem_err == blot_direct_types::Error.none {
            let step, step_err = stride(g, f, element, id);
            if step_err == blot_direct_types::Error.none {
                let view_base = emitOffsetAddress(g, f, base, start, step);
                recordCheckedView(f, w(g, result, 0), w(g, result, 1), w(g, result, 2), w(g, result, 3), view_base);
            }
        }
    } else if tagOf(g, container.ty) == blot_direct_types::Tag.view {
        let cv = findCheckedView(f, w(g, container, 0), w(g, container, 1), w(g, container, 2), w(g, container, 3));
        if cv >= 0 {
            let base = f.checked_views[cv].base;
            let element, elem_err = elementOf(g, f, ty, id);
            if elem_err == blot_direct_types::Error.none {
                let step, step_err = stride(g, f, element, id);
                if step_err == blot_direct_types::Error.none {
                    let view_base = emitOffsetAddress(g, f, base, start, step);
                    recordCheckedView(f, w(g, result, 0), w(g, result, 1), w(g, result, 2), w(g, result, 3), view_base);
                }
            }
        }
    }
    return result, blot_direct_types::Error.none;
}
// A fresh fixed array: the elements of each part in order (a part is either a
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
            let written = writeElement(g, f, address, 0, part, id);
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
    let handle, _, error = createUninit(g, f, ty, length, id);
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
    var ty: Ty = blot_direct_types::never;
    if operation == blot_check_storage_ops::Op.with_capacity {
        var lowered_ty, lerr = g.types.lower(m, m.typeOf(id), f.env);
        if lerr != blot_direct_types::Error.none {
            if !holesUnused(g, f, m.typeOf(id), 0) { return neverVal(), g.typeFailure(m, id); }
            defaultUnused(g, f, m.typeOf(id), 0);
            let defaulted, derr = lower(g, f, m.typeOf(id), id);
            if derr != blot_direct_types::Error.none { return neverVal(), derr; }
            lowered_ty = defaulted;
        }
        ty = lowered_ty;
    } else {
        let lowered_ty, error = typeOf(g, f, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        ty = lowered_ty;
    }
    let address_function = g.runtime_().address;
    match operation {
        length => {
            let da_idx = findDirectArray(f, localRef(m, children[0]));
            if da_idx >= 0 {
                let klen = constLocal(g, f, f.direct_arrays[da_idx].length);
                recordConstU32(f, klen, f.direct_arrays[da_idx].length);
                return valOf1(g, blot_direct_types::u32_, klen), blot_direct_types::Error.none;
            }
            let rd, is_rd = tryResolveRodata(g, f, children[0]);
            if is_rd {
                let klen = constLocal(g, f, rd.count);
                recordConstU32(f, klen, rd.count);
                return valOf1(g, blot_direct_types::u32_, klen), blot_direct_types::Error.none;
            }
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let length, error = lengthOf(g, f, container, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            return valOf1(g, blot_direct_types::u32_, length), blot_direct_types::Error.none;
        },
        read => {
            let da_idx = findDirectArray(f, localRef(m, children[0]));
            if da_idx >= 0 {
                let da = f.direct_arrays[da_idx];
                let position, perr = expr(g, f, children[1]);
                if perr != blot_direct_types::Error.none { return position, perr; }
                let index, ierr = scalarLocal(g, f, position, id);
                if ierr != blot_direct_types::Error.none { return neverVal(), ierr; }
                return emitDirectArrayRead(g, f, da, index, id);
            }
            let rd, is_rd = tryResolveRodata(g, f, children[0]);
            if is_rd {
                return emitRodataRead(g, f, rd, children[1], id);
            }
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let position, error = expr(g, f, children[1]);
            if error != blot_direct_types::Error.none { return position, error; }
            let index, error = scalarLocal(g, f, position, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            return readElement(g, f, container, index, id, m.typeOf(children[0]));
        },
        push => {
            let is_direct = localRef(m, children[0]) != 0;
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let value, error = expr(g, f, children[1]);
            if error != blot_direct_types::Error.none { return value, error; }
            return emitStoragePushVal(g, f, container, value, id, is_direct);
        },
        pop => {
            let is_direct = localRef(m, children[0]) != 0;
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
            if is_direct && tagOf(g, container.ty) == blot_direct_types::Tag.array {
                invalidateCheckedOwner(g, f, container);
            } else {
                invalidateCheckedContainers(f);
            }
            return loadElement(g, f, address, 0, ty, id);
        },
        truncate => {
            let is_direct = localRef(m, children[0]) != 0;
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
            if is_direct && tagOf(g, container.ty) == blot_direct_types::Tag.array {
                invalidateCheckedOwner(g, f, container);
            } else {
                invalidateCheckedContainers(f);
            }
            return unitVal(), blot_direct_types::Error.none;
        },
        share => {
            let value, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return value, error; }
            return Val { ty, value.start, value.len }, blot_direct_types::Error.none;
        },
        copy => {
            let value, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return value, error; }
            return deepCopyValue(g, f, value, ty, id, 0);
        },
        with_capacity => {
            let cap_val, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return cap_val, error; }
            let cap, cerr = scalarLocal(g, f, cap_val, id);
            if cerr != blot_direct_types::Error.none { return neverVal(), cerr; }
            let element, eerr = elementOf(g, f, ty, id);
            if eerr != blot_direct_types::Error.none { return neverVal(), eerr; }
            let step, serr = stride(g, f, element, id);
            if serr != blot_direct_types::Error.none { return neverVal(), serr; }
            let rt = g.runtime_();
            noteAllocation(f);
            lget(g, cap);
            i32Const(g, 0x04000000);
            op(g, OP_i32_gt_u);
            trap(g, f);
            if step != 0 {
                lget(g, cap);
                i32Const(g, blot_direct_runtime::capacity_mask / step);
                op(g, OP_i32_gt_u);
                trap(g, f);
            }
            let bytes = emitScaledBytes(g, f, cap, step);
            let result, rerr = fresh(g, f, ty, id);
            if rerr != blot_direct_types::Error.none { return result, rerr; }
            lget(g, bytes);
            let nonzero = open(g, f, OP_if_);
            // Top-level (non-loop, non-inlined) pre-sized arrays and large
            // (> 4 MiB) arrays use exact-size stack backing so they avoid
            // heap_alloc/heap_free overhead and power-of-two rounding bloat,
            // rewinding in one store on function exit while still growing
            // transparently onto the heap via rt.push / rt.reserve if needed.
            if f.inline_depth == 0 && f.loop_depth == 0 {
                lget(g, bytes);
                callf(g, rt.stack);
                i32Const(g, 0);
                lget(g, bytes);
                callf(g, rt.open);
                lset(g, w(g, result, 1));
                lset(g, w(g, result, 0));
            } else {
                lget(g, bytes);
                i32Const(g, 4194304);
                op(g, OP_i32_gt_u);
                let large_stack = open(g, f, OP_if_);
                lget(g, bytes);
                callf(g, rt.stack);
                i32Const(g, 0);
                lget(g, bytes);
                callf(g, rt.open);
                lset(g, w(g, result, 1));
                lset(g, w(g, result, 0));
                popCheckedArraysAt(f, large_stack);
                op(g, OP_else_);
                lget(g, bytes);
                i32Const(g, 0);
                callf(g, rt.open_heap);
                op(g, OP_drop);
                op(g, OP_drop);
                lset(g, w(g, result, 1));
                lset(g, w(g, result, 0));
                close(g, f);
            }
            popCheckedArraysAt(f, nonzero);
            op(g, OP_else_);
            i32Const(g, 0);
            i32Const(g, step);
            i32Const(g, 0);
            callf(g, rt.create);
            lset(g, w(g, result, 1));
            lset(g, w(g, result, 0));
            close(g, f);
            recordMutable(g, f, result);
            return result, blot_direct_types::Error.none;
        },
        reserve => {
            let is_direct = localRef(m, children[0]) != 0;
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let add_val, aerr = expr(g, f, children[1]);
            if aerr != blot_direct_types::Error.none { return add_val, aerr; }
            let additional, serr = scalarLocal(g, f, add_val, id);
            if serr != blot_direct_types::Error.none { return neverVal(), serr; }
            let element, eerr = elementOf(g, f, container.ty, id);
            if eerr != blot_direct_types::Error.none { return neverVal(), eerr; }
            let step, sterr = stride(g, f, element, id);
            if sterr != blot_direct_types::Error.none { return neverVal(), sterr; }
            let rt = g.runtime_();
            let cur_len, lerr = lengthOf(g, f, container, id);
            if lerr != blot_direct_types::Error.none { return neverVal(), lerr; }
            let need_elems = local32(g, f);
            lget(g, cur_len);
            lget(g, additional);
            op(g, OP_i32_add);
            ltee(g, need_elems);
            lget(g, cur_len);
            op(g, OP_i32_lt_u);
            trap(g, f);
            if !rt.has_fork && step > 0 && step <= 65536 && tagOf(g, container.ty) == blot_direct_types::Tag.array {
                let entry = ensureCheckedGrow(g, f, container);
                let max_elems = if blot_direct_runtime::capacity_mask / step < 0x04000000 { blot_direct_runtime::capacity_mask / step } else { 0x04000000 };
                let need_bytes = emitScaledBytes(g, f, need_elems, step);
                let cap = local32(g, f);
                lget(g, entry);
                op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_capacity);
                ltee(g, cap);
                i32Const(g, blot_direct_runtime::flag_mask ^ blot_direct_runtime::heap_flag);
                op(g, OP_i32_and);
                i32Const(g, blot_direct_runtime::live_flag);
                op(g, OP_i32_eq);
                lget(g, need_elems);
                i32Const(g, max_elems);
                op(g, OP_i32_le_u);
                op(g, OP_i32_and);
                lget(g, need_bytes);
                lget(g, cap);
                i32Const(g, blot_direct_runtime::capacity_mask);
                op(g, OP_i32_and);
                op(g, OP_i32_le_u);
                op(g, OP_i32_and);
                op(g, OP_i32_eqz);
                let need_grow = open(g, f, OP_if_);
                lget(g, w(g, container, 0));
                lget(g, w(g, container, 1));
                lget(g, need_elems);
                i32Const(g, step);
                callf(g, rt.reserve);
                popCheckedArraysAt(f, need_grow);
                close(g, f);
            } else {
                lget(g, w(g, container, 0));
                lget(g, w(g, container, 1));
                lget(g, need_elems);
                i32Const(g, step);
                callf(g, rt.reserve);
            }
            if is_direct && tagOf(g, container.ty) == blot_direct_types::Tag.array {
                invalidateCheckedOwner(g, f, container);
            } else {
                invalidateCheckedContainers(f);
            }
            return container, blot_direct_types::Error.none;
        },
        extend => {
            let is_direct = localRef(m, children[0]) != 0;
            let dst, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return dst, error; }
            let rd, is_rd = tryResolveRodata(g, f, children[1]);
            if is_rd && tagOf(g, dst.ty) == blot_direct_types::Tag.array && g.types.node(dst.ty).a == rd.elem_ty {
                return emitExtendFromRodata(g, f, dst, is_direct, rd, id);
            }
            let src, serr = expr(g, f, children[1]);
            if serr != blot_direct_types::Error.none { return src, serr; }
            let element, eerr = elementOf(g, f, dst.ty, id);
            if eerr != blot_direct_types::Error.none { return neverVal(), eerr; }
            let step, sterr = stride(g, f, element, id);
            if sterr != blot_direct_types::Error.none { return neverVal(), sterr; }
            let src_len, slerr = lengthOf(g, f, src, id);
            if slerr != blot_direct_types::Error.none { return neverVal(), slerr; }
            let rt = g.runtime_();
            let fast_eligible = !rt.has_fork && step > 0 && step <= 65536 && tagOf(g, dst.ty) == blot_direct_types::Tag.array;
            var dst_entry: u32 = 0;
            var dst_len: u32 = 0;
            if fast_eligible {
                dst_entry = ensureCheckedGrow(g, f, dst);
                dst_len = local32(g, f);
                lget(g, dst_entry);
                op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
                lset(g, dst_len);
            } else {
                let dl, dlerr = lengthOf(g, f, dst, id);
                if dlerr != blot_direct_types::Error.none { return neverVal(), dlerr; }
                dst_len = dl;
            }
            let next_len = local32(g, f);
            lget(g, dst_len);
            lget(g, src_len);
            op(g, OP_i32_add);
            ltee(g, next_len);
            lget(g, dst_len);
            op(g, OP_i32_lt_u);
            trap(g, f);
            if fast_eligible {
                let max_elems = if blot_direct_runtime::capacity_mask / step < 0x04000000 { blot_direct_runtime::capacity_mask / step } else { 0x04000000 };
                let need_bytes = emitScaledBytes(g, f, next_len, step);
                let cap = local32(g, f);
                let skip_flags = knownMutable(g, f, dst);
                lget(g, dst_entry);
                op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_capacity);
                if skip_flags {
                    i32Const(g, blot_direct_runtime::capacity_mask);
                    op(g, OP_i32_and);
                    lget(g, need_bytes);
                    op(g, OP_i32_lt_u);
                    lget(g, next_len);
                    i32Const(g, max_elems);
                    op(g, OP_i32_gt_u);
                    op(g, OP_i32_or);
                } else {
                    ltee(g, cap);
                    i32Const(g, blot_direct_runtime::flag_mask ^ blot_direct_runtime::heap_flag);
                    op(g, OP_i32_and);
                    i32Const(g, blot_direct_runtime::live_flag);
                    op(g, OP_i32_eq);
                    lget(g, next_len);
                    i32Const(g, max_elems);
                    op(g, OP_i32_le_u);
                    op(g, OP_i32_and);
                    lget(g, need_bytes);
                    lget(g, cap);
                    i32Const(g, blot_direct_runtime::capacity_mask);
                    op(g, OP_i32_and);
                    op(g, OP_i32_le_u);
                    op(g, OP_i32_and);
                    op(g, OP_i32_eqz);
                }
                let need_grow = open(g, f, OP_if_);
                lget(g, w(g, dst, 0));
                lget(g, w(g, dst, 1));
                lget(g, next_len);
                i32Const(g, step);
                callf(g, rt.reserve);
                popCheckedArraysAt(f, need_grow);
                close(g, f);
            } else {
                lget(g, w(g, dst, 0));
                lget(g, w(g, dst, 1));
                lget(g, next_len);
                i32Const(g, step);
                callf(g, rt.reserve);
            }
            if !holdsContainer(g, element, 0) {
                let non_empty = open(g, f, OP_block);
                lget(g, src_len);
                op(g, OP_i32_eqz);
                opIndex(g, OP_br_if, 0);
                if !fast_eligible {
                    dst_entry = local32(g, f);
                    lget(g, w(g, dst, 0));
                    lget(g, w(g, dst, 1));
                    callf(g, rt.check);
                    lset(g, dst_entry);
                }
                let dst_base = local32(g, f);
                lget(g, dst_entry);
                op(g, OP_i32_load); uleb(g, 2); uleb(g, blot_direct_runtime::entry_base);
                lset(g, dst_base);
                let dst_ptr = emitOffsetAddress(g, f, dst_base, dst_len, step);
                var src_ptr: u32 = 0;
                if tagOf(g, src.ty) == blot_direct_types::Tag.view {
                    let cv = findCheckedView(f, w(g, src, 0), w(g, src, 1), w(g, src, 2), w(g, src, 3));
                    if cv >= 0 {
                        src_ptr = f.checked_views[cv].base;
                    } else {
                        src_ptr = emitOffsetAddress(g, f, baseOf(g, f, src), w(g, src, 2), step);
                    }
                } else {
                    src_ptr = baseOf(g, f, src);
                }
                let copy_bytes = emitScaledBytes(g, f, src_len, step);
                if rt.has_fork {
                    recordBeforeWrite(g, f, w(g, dst, 0), dst_entry, blot_direct_runtime::entry_length, 4);
                }
                lget(g, dst_ptr);
                lget(g, src_ptr);
                lget(g, copy_bytes);
                memoryCopyOp(g);
                lget(g, dst_entry);
                lget(g, next_len);
                op(g, OP_i32_store); uleb(g, 2); uleb(g, blot_direct_runtime::entry_length);
                close(g, f);
            } else {
                let idx = constLocal(g, f, 0);
                let exit = open(g, f, OP_block);
                let top = open(g, f, OP_loop);
                lget(g, idx);
                lget(g, src_len);
                op(g, OP_i32_ge_u);
                br(g, f, OP_br_if, exit);
                let elem_val, rerr = readElement(g, f, src, idx, id, m.typeOf(children[1]), false);
                if rerr != blot_direct_types::Error.none { return neverVal(), rerr; }
                let copied_elem, cerr = deepCopyValue(g, f, elem_val, element, id, 0);
                if cerr != blot_direct_types::Error.none { return neverVal(), cerr; }
                let _, perr = emitStoragePushVal(g, f, dst, copied_elem, id, is_direct);
                if perr != blot_direct_types::Error.none { return neverVal(), perr; }
                lget(g, idx);
                i32Const(g, 1);
                op(g, OP_i32_add);
                lset(g, idx);
                br(g, f, OP_br, top);
                close(g, f);
                close(g, f);
            }
            if is_direct && tagOf(g, dst.ty) == blot_direct_types::Tag.array {
                invalidateCheckedOwner(g, f, dst);
            } else {
                invalidateCheckedContainers(f);
            }
            return dst, blot_direct_types::Error.none;
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
            return emitStorageViewVal(g, f, container, start, end, ty, id);
        },
        at, link => {
            let container, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return container, error; }
            let position, error = expr(g, f, children[1]);
            if error != blot_direct_types::Error.none { return position, error; }
            let index, error = scalarLocal(g, f, position, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            // Check now, so a reference never names a missing element.
            let checked, error = elementAddress(g, f, container, index, id, m.typeOf(children[0]));
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
        ref => {
            let value, error = expr(g, f, children[0]);
            if error != blot_direct_types::Error.none { return value, error; }
            if value.ty == blot_direct_types::never { return neverVal(), blot_direct_types::Error.none; }
            let element, error = elementOf(g, f, ty, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let step, error = stride(g, f, element, id);
            if error != blot_direct_types::Error.none { return neverVal(), error; }
            let rt = g.runtime_();
            noteAllocation(f);
            let base = local32(g, f);
            i32Const(g, step);
            callf(g, rt.stack);
            lset(g, base);
            lget(g, base);
            i32Const(g, 1);
            i32Const(g, step);
            callf(g, rt.open);
            let result, error = fresh(g, f, ty, id);
            if error != blot_direct_types::Error.none { return result, error; }
            lset(g, w(g, result, 1));
            lset(g, w(g, result, 0));
            i32Const(g, 0);
            lset(g, w(g, result, 2));
            let noted = noteStoreToSlot(g, f, w(g, result, 0), value);
            if noted != blot_direct_types::Error.none { return neverVal(), noted; }
            let written = writeElement(g, f, base, 0, value, id);
            if written != blot_direct_types::Error.none { return neverVal(), written; }
            return result, blot_direct_types::Error.none;
        },
        _ => { abort("storage operation without a direct lowering"); },
    }
}

recursive fn holdsContainerVisited(g: Generator&, ty: Ty, visited: Ty[64]&, visited_len: i64&) -> bool {
    let n = g.types.node(ty);
    match n.tag {
        array => { return true; },
        tuple => {
            for at in 0..(n.b as i64) { if holdsContainerVisited(g, g.types.words[n.a + at], visited, visited_len) { return true; } }
            return false;
        },
        record => {
            for index in 0..(n.b as i64) { if holdsContainerVisited(g, g.types.recordField(ty, index).ty, visited, visited_len) { return true; } }
            return false;
        },
        nominal => {
            for vi in 0..visited_len { if visited[vi] == ty { return false; } }
            if visited_len >= 64 { return true; }
            visited[visited_len] = ty;
            visited_len += 1;
            let cases, error = g.types.variants(ty);
            if error != blot_direct_types::Error.none { return false; }
            for at in 0..(cases.len as i64) {
                let payload = g.types.variant_payloads[cases.payloads + at];
                if holdsContainerVisited(g, payload, visited, visited_len) { return true; }
            }
            return false;
        },
        _ => { return false; },
    }
}
fn holdsContainer(g: Generator&, ty: Ty, depth: i64) -> bool {
    var visited: Ty[64] = [0; 64];
    var visited_len: i64 = 0;
    return holdsContainerVisited(g, ty, visited, visited_len);
}

// Emit a memoized recursive Wasm helper `deep_copy_nom(old_ptr: i32) -> new_ptr: i32`
// for recursive nominal types so deep copying arbitrary-depth recursive ADTs never
// truncates at a compile-time recursion cutoff or blows up code size.
recursive fn ensureDeepCopyNomHelper(g: Generator&, unit: u32, ty: Ty) -> u32, Error {
    let key = blot_direct_emit::key64(ty, 1);
    let existing, found = g.s.deep_copy_helpers.get(key);
    if found { return existing, blot_direct_types::Error.none; }
    if g.s.parallel_readonly { g.s.parallel_aborted = true; return 0, blot_direct_types::Error.unsupported; }
    let fn_id = g.module.addFunction(g.module.signature([VT_i32], [VT_i32]));
    g.s.deep_copy_helpers.put(key, fn_id);
    blot_direct_emit::recordParentAux(2, ty, fn_id);
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
    lget(g, old_ptr);
    op(g, OP_i32_eqz);
    let z_if = open(g, nf, OP_if_);
    i32Const(g, 0);
    op(g, OP_return_);
    close(g, nf);
    let old_val = valOf1(g, ty, old_ptr);
    let copied, cerr = deepCopyNominalInline(g, nf, old_val, ty, 0, 0);
    if cerr != blot_direct_types::Error.none {
        blot_direct_relocations::rewind(sites_mark);
        s.code.resize(code_mark); s.locals.resize(locals_mark); s.labels.resize(labels_mark); s.handles.resize(handles_mark); s.handle_cells_len = handle_cells_mark;
        return 0, cerr;
    }
    lget(g, w(g, copied, 0));
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

recursive fn deepCopyNominalInline(g: Generator&, f: Fn&, value: Val, ty: Ty, id: u32, depth: i64) -> Val, Error {
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

recursive fn deepCopyValue(g: Generator&, f: Fn&, value: Val, ty: Ty, id: u32, depth: i64) -> Val, Error {
    if value.ty == blot_direct_types::never { return Val { ty, value.start, value.len }, blot_direct_types::Error.none; }
    if depth > 256 { return neverVal(), g.fail(g.units[f.unit - 1], id, "deep copy type nesting exceeds 256"); }
    let tag = tagOf(g, ty);
    if tag == blot_direct_types::Tag.array {
        let elem_ty, error = elementOf(g, f, ty, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        if !holdsContainer(g, elem_ty, 0) {
            return copyContainer(g, f, value, ty, id);
        }
        let length, error = lengthOf(g, f, value, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        let handle, dst_base, error = createUninit(g, f, ty, length, id);
        if error != blot_direct_types::Error.none { return handle, error; }
        let step, error = stride(g, f, elem_ty, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        let src_base, _ = ensureCheckedArray(g, f, value);
        let idx = constLocal(g, f, 0);
        let exit = open(g, f, OP_block);
        let top = open(g, f, OP_loop);
        lget(g, idx);
        lget(g, length);
        op(g, OP_i32_ge_u);
        br(g, f, OP_br_if, exit);
        let src_addr = emitOffsetAddress(g, f, src_base, idx, step);
        let elem_val, error = loadElement(g, f, src_addr, 0, elem_ty, id);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        let copied_elem, error = deepCopyValue(g, f, elem_val, elem_ty, id, depth + 1);
        if error != blot_direct_types::Error.none { return neverVal(), error; }
        let dst_addr = emitOffsetAddress(g, f, dst_base, idx, step);
        let noted = noteStoreToSlot(g, f, w(g, handle, 0), copied_elem);
        if noted != blot_direct_types::Error.none { return neverVal(), noted; }
        let written = writeElement(g, f, dst_addr, 0, copied_elem, id);
        if written != blot_direct_types::Error.none { return neverVal(), written; }
        lget(g, idx);
        i32Const(g, 1);
        op(g, OP_i32_add);
        lset(g, idx);
        br(g, f, OP_br, top);
        close(g, f);
        close(g, f);
        return handle, blot_direct_types::Error.none;
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
        let is_rec, rerr = g.types.isRecursive(ty);
        if rerr != blot_direct_types::Error.none { return neverVal(), g.typeFailure(g.units[f.unit - 1], id); }
        if is_rec {
            let fn_id, herr = ensureDeepCopyNomHelper(g, f.unit, ty);
            if herr != blot_direct_types::Error.none { return neverVal(), herr; }
            lget(g, w(g, value, 0));
            callf(g, fn_id);
            f.allocates = true;
            f.allocations += 1;
            return pop(g, f, ty, id);
        }
        return deepCopyNominalInline(g, f, value, ty, id, depth);
    }
    return Val { ty, value.start, value.len }, blot_direct_types::Error.none;
}
