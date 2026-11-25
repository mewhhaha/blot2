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
import check.wire_schema;
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
import .function_staging;
import .function_spark;
import .function_persist;
import .function_kernels;

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

struct ScratchCut { target: u32 = 0, owner: u32 = 0, stack: u32 = 0 }
struct CheckedArray {
    slot: u32 = 0xffffffff,
    generation: u32 = 0,
    base: u32 = 0,
    length: u32 = 0,
    depth: u32 = 0
}
struct CheckedGrow {
    slot: u32 = 0xffffffff,
    generation: u32 = 0,
    entry: u32 = 0,
    depth: u32 = 0
}
struct CheckedView {
    slot: u32 = 0xffffffff,
    generation: u32 = 0,
    start: u32 = 0,
    length: u32 = 0,
    base: u32 = 0,
    depth: u32 = 0
}
struct CheckedElem {
    slot: u32 = 0xffffffff,
    generation: u32 = 0,
    index: u32 = 0,
    step: u32 = 0,
    address: u32 = 0,
    val_local: u32 = 0xffffffff,
    val_ty: Ty = 0,
    depth: u32 = 0
}
struct CheckedBound {
    index: u32 = 0,
    bound: u32 = 0,
    depth: u32 = 0
}
struct ConstTag { local: u32 = 0, tag: u32 = 0, depth: u32 = 0 }
struct CheckedRange {
    slot: u32 = 0xffffffff,
    generation: u32 = 0,
    index: u32 = 0,
    base: u32 = 0,
    length_ty: TId = 0,
    end_local: u32 = 0xffffffff,
    is_view: bool = false,
    trusted_view: bool = false,
    view_start: u32 = 0
}
struct ComptimeFrame {
    binder: u32 = 0,
    is_variants: bool = false,
    target_ty: Ty = 0,
    nominal_unit: u32 = 0,
    nominal_decl: u32 = 0,
    index: u32 = 0,
    ctor_tag: u32 = 0,
    name_id: u32 = 0,
    field_ty: Ty = 0,
}
struct Fn {
    checked_range: CheckedRange = CheckedRange {},
    checked_arrays: CheckedArray[16] = [CheckedArray {}; 16],
    checked_arrays_len: i64 = 0,
    checked_grows: CheckedGrow[8] = [CheckedGrow {}; 8],
    checked_grows_len: i64 = 0,
    checked_views: CheckedView[8] = [CheckedView {}; 8],
    checked_views_len: i64 = 0,
    checked_elems: CheckedElem[8] = [CheckedElem {}; 8],
    checked_elems_len: i64 = 0,
    checked_bounds: CheckedBound[8] = [CheckedBound {}; 8],
    checked_bounds_len: i64 = 0,
    comptime_frames: ComptimeFrame[16] = [ComptimeFrame {}; 16],
    comptime_len: i64 = 0,
    sites_base:i64=0,
    scratch_body: u32 = 0,
    scratch_cut: ScratchCut = ScratchCut {},
    // Uniquely-owned boxed bindings eligible for FBIP same-shape reuse.
    unique_boxed: blot_support_zigmap::Map = blot_support_zigmap::Map {},
    // Uniquely-owned local/own-param array/container bindings eligible for in-place spark reuse.
    unique_owned: blot_support_zigmap::Map = blot_support_zigmap::Map {},
    owned_uses_computed: bool = false,
    owned_uses: blot_support_zigmap::Map = blot_support_zigmap::Map {},
    owned_flows: blot_support_zigmap::Map = blot_support_zigmap::Map {},
    reuse_node: u32 = 0,
    reuse_block: u32 = 0,
    reuse_ty: Ty = 0,
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
    // Nested forwarding / inlining resolutions in progress (bounded against cycles).
    forward_depth: u32 = 0,
    inline_depth: u32 = 0,
    const_tags: ConstTag[8] = [ConstTag {}; 8],
    const_tags_len: i64 = 0,
    // Stores of memory-holding values into untracked cells/effects: a loop body
    // or function that makes one cannot release its allocations.
    memory_stores: u32 = 0,
    // Where this body's part of each generator stack begins. Installed
    // providers are the first `handles_len` entries from `handles_base`:
    // Zig pops the list without restoring it after a failed operand, so the
    // count is kept here and the stack itself is only cut when the body ends.
    handles_base: i64 = 0,
    handles_len: u32 = 0,
    handle_cells_base: i64 = 0,
    code_base: i64 = 0,
    locals_base: i64 = 0,
    labels_base: i64 = 0,
    parameter_words: u32 = 0,
    bindings: blot_support_zigmap::Map = blot_support_zigmap::Map {},
    with_cells: blot_support_zigmap::Map = blot_support_zigmap::Map {},
    depth: u32 = 0,
    // Set when this body allocates environment memory or receives a value
    // that may refer to it; such a body restores the stack on exit unless
    // its result can hold that memory.
    allocates: bool = false,
    // Allocation events so far, so a loop can tell whether its body allocated.
    allocations: u32 = 0,
    // Direct child Core node eligible to elide F32 NaN canonicalization because
    // its immediate parent is itself a canonicalizing consumer.
    elide_f32_nan_node: u32 = 0,
    // Lazily computed per-body map of local F32 bindings whose NaN payload may be observed.
    nan_elide_computed: bool = false,
    nan_observed: blot_support_zigmap::Map = blot_support_zigmap::Map {},
    // Local F32 bindings statically proved finite and bounded (|x| <= 2^33).
    finite_f32: u32[32] = [0; 32],
    finite_f32_len: i64 = 0,
}

fn hasFiniteF32(f: const Fn&, binding: u32) -> bool {
    for i in 0..f.finite_f32_len {
        if f.finite_f32[i] == binding { return true; }
    }
    return false;
}
fn recordFiniteF32(f: Fn&, binding: u32) {
    if binding == 0 || hasFiniteF32(f, binding) || f.finite_f32_len >= 32 { return; }
    f.finite_f32[f.finite_f32_len] = binding;
    f.finite_f32_len += 1;
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
    popCheckedArrays(f, f.depth);
}
fn popCheckedArrays(f: Fn&, max_depth: u32) {
    while f.checked_arrays_len > 0 && f.checked_arrays[f.checked_arrays_len - 1].depth > max_depth {
        f.checked_arrays_len -= 1;
    }
    while f.checked_grows_len > 0 && f.checked_grows[f.checked_grows_len - 1].depth > max_depth {
        f.checked_grows_len -= 1;
    }
    while f.checked_views_len > 0 && f.checked_views[f.checked_views_len - 1].depth > max_depth {
        f.checked_views_len -= 1;
    }
    while f.checked_elems_len > 0 && f.checked_elems[f.checked_elems_len - 1].depth > max_depth {
        f.checked_elems_len -= 1;
    }
    while f.checked_bounds_len > 0 && f.checked_bounds[f.checked_bounds_len - 1].depth > max_depth {
        f.checked_bounds_len -= 1;
    }
    while f.const_tags_len > 0 && f.const_tags[f.const_tags_len - 1].depth > max_depth {
        f.const_tags_len -= 1;
    }
}
fn popCheckedArraysAt(f: Fn&, depth: u32) {
    while f.checked_arrays_len > 0 && f.checked_arrays[f.checked_arrays_len - 1].depth >= depth {
        f.checked_arrays_len -= 1;
    }
    while f.checked_grows_len > 0 && f.checked_grows[f.checked_grows_len - 1].depth >= depth {
        f.checked_grows_len -= 1;
    }
    while f.checked_views_len > 0 && f.checked_views[f.checked_views_len - 1].depth >= depth {
        f.checked_views_len -= 1;
    }
    while f.checked_elems_len > 0 && f.checked_elems[f.checked_elems_len - 1].depth >= depth {
        f.checked_elems_len -= 1;
    }
    while f.checked_bounds_len > 0 && f.checked_bounds[f.checked_bounds_len - 1].depth >= depth {
        f.checked_bounds_len -= 1;
    }
    while f.const_tags_len > 0 && f.const_tags[f.const_tags_len - 1].depth >= depth {
        f.const_tags_len -= 1;
    }
}
fn findConstTag(f: const Fn&, local_id: u32) -> u32, bool {
    var i = f.const_tags_len;
    while i > 0 {
        i -= 1;
        if f.const_tags[i].local == local_id { return f.const_tags[i].tag, true; }
    }
    return 0, false;
}
fn recordConstTag(f: Fn&, local_id: u32, tag: u32) {
    let _, exists = findConstTag(f, local_id);
    if exists || f.const_tags_len >= 8 { return; }
    f.const_tags[f.const_tags_len] = ConstTag { local: local_id, tag: tag, depth: f.depth };
    f.const_tags_len += 1;
}
fn findCheckedArray(f: const Fn&, slot: u32, generation: u32) -> i64 {
    var i = f.checked_arrays_len;
    while i > 0 {
        i -= 1;
        let entry = f.checked_arrays[i];
        if entry.slot == slot && entry.generation == generation { return i; }
    }
    return -1;
}
fn recordCheckedArray(f: Fn&, slot: u32, generation: u32, base: u32, length: u32) {
    if findCheckedArray(f, slot, generation) >= 0 { return; }
    if f.checked_arrays_len >= 16 { return; }
    f.checked_arrays[f.checked_arrays_len] = CheckedArray { slot: slot, generation: generation, base: base, length: length, depth: f.depth };
    f.checked_arrays_len += 1;
}
fn findCheckedGrow(f: const Fn&, slot: u32, generation: u32) -> i64 {
    var i = f.checked_grows_len;
    while i > 0 {
        i -= 1;
        let entry = f.checked_grows[i];
        if entry.slot == slot && entry.generation == generation { return i; }
    }
    return -1;
}
fn recordCheckedGrow(f: Fn&, slot: u32, generation: u32, entry: u32) {
    if findCheckedGrow(f, slot, generation) >= 0 { return; }
    if f.checked_grows_len >= 8 { return; }
    f.checked_grows[f.checked_grows_len] = CheckedGrow { slot: slot, generation: generation, entry: entry, depth: f.depth };
    f.checked_grows_len += 1;
}
fn findCheckedView(f: const Fn&, slot: u32, generation: u32, start: u32, length: u32) -> i64 {
    var i = f.checked_views_len;
    while i > 0 {
        i -= 1;
        let entry = f.checked_views[i];
        if entry.slot == slot && entry.generation == generation && entry.start == start && entry.length == length { return i; }
    }
    return -1;
}
fn recordCheckedView(f: Fn&, slot: u32, generation: u32, start: u32, length: u32, base: u32) {
    if findCheckedView(f, slot, generation, start, length) >= 0 { return; }
    if f.checked_views_len >= 8 { return; }
    f.checked_views[f.checked_views_len] = CheckedView { slot: slot, generation: generation, start: start, length: length, base: base, depth: f.depth };
    f.checked_views_len += 1;
}
fn findCheckedElem(f: const Fn&, slot: u32, generation: u32, index: u32, step: u32) -> i64 {
    var i = f.checked_elems_len;
    while i > 0 {
        i -= 1;
        let entry = f.checked_elems[i];
        if entry.slot == slot && entry.generation == generation && entry.index == index && entry.step == step { return i; }
    }
    return -1;
}
fn recordCheckedElem(f: Fn&, slot: u32, generation: u32, index: u32, step: u32, address: u32) {
    if findCheckedElem(f, slot, generation, index, step) >= 0 { return; }
    if f.checked_elems_len >= 8 { return; }
    f.checked_elems[f.checked_elems_len] = CheckedElem { slot: slot, generation: generation, index: index, step: step, address: address, val_local: 0xffffffff, val_ty: 0, depth: f.depth };
    f.checked_elems_len += 1;
}
fn recordCheckedElemVal(f: Fn&, slot: u32, generation: u32, index: u32, step: u32, val_local: u32, val_ty: Ty) {
    let at = findCheckedElem(f, slot, generation, index, step);
    if at >= 0 {
        f.checked_elems[at].val_local = val_local;
        f.checked_elems[at].val_ty = val_ty;
    }
}
fn invalidateCheckedOwner(g: const Generator&, f: Fn&, container: Val) {
    let slot = w(g, container, 0);
    let gen = w(g, container, 1);
    if f.checked_arrays_len != 0 {
        var out: i64 = 0;
        for i in 0..f.checked_arrays_len {
            let entry = f.checked_arrays[i];
            if entry.slot == slot && entry.generation == gen {
                // Also drop any CheckedBound referencing this owner's old cached length local.
                if f.checked_bounds_len != 0 {
                    var bout: i64 = 0;
                    for bi in 0..f.checked_bounds_len {
                        let bentry = f.checked_bounds[bi];
                        if bentry.bound != entry.length && bentry.index != entry.length {
                            f.checked_bounds[bout] = bentry;
                            bout += 1;
                        }
                    }
                    f.checked_bounds_len = bout;
                }
            } else {
                f.checked_arrays[out] = entry;
                out += 1;
            }
        }
        f.checked_arrays_len = out;
    }
    f.checked_views_len = 0;
    f.checked_elems_len = 0;
}
fn findCheckedBound(f: const Fn&, index: u32, bound: u32) -> i64 {
    var i = f.checked_bounds_len;
    while i > 0 {
        i -= 1;
        let entry = f.checked_bounds[i];
        if entry.index == index && entry.bound == bound { return i; }
    }
    return -1;
}
fn recordCheckedBound(f: Fn&, index: u32, bound: u32) {
    if findCheckedBound(f, index, bound) >= 0 { return; }
    if f.checked_bounds_len >= 8 { return; }
    f.checked_bounds[f.checked_bounds_len] = CheckedBound { index: index, bound: bound, depth: f.depth };
    f.checked_bounds_len += 1;
}
fn invalidateCheckedContainers(f: Fn&) {
    f.checked_arrays_len = 0;
    f.checked_views_len = 0;
    f.checked_elems_len = 0;
    f.checked_bounds_len = 0;
}
fn invalidateCheckedArrayVal(g: const Generator&, f: Fn&, value: Val) {
    if value.len == 0 { return; }
    if f.checked_arrays_len != 0 {
        var out: i64 = 0;
        for i in 0..f.checked_arrays_len {
            let entry = f.checked_arrays[i];
            var hit = false;
            for at in 0..(value.len as i64) {
                let local_id = g.s.words[value.start + at];
                if local_id == entry.slot || local_id == entry.generation || local_id == entry.base || local_id == entry.length {
                    hit = true;
                    break;
                }
            }
            if !hit {
                f.checked_arrays[out] = entry;
                out += 1;
            }
        }
        f.checked_arrays_len = out;
    }
    if f.checked_grows_len != 0 {
        var out: i64 = 0;
        for i in 0..f.checked_grows_len {
            let entry = f.checked_grows[i];
            var hit = false;
            for at in 0..(value.len as i64) {
                let local_id = g.s.words[value.start + at];
                if local_id == entry.slot || local_id == entry.generation || local_id == entry.entry {
                    hit = true;
                    break;
                }
            }
            if !hit {
                f.checked_grows[out] = entry;
                out += 1;
            }
        }
        f.checked_grows_len = out;
    }
    if f.checked_views_len != 0 {
        var out: i64 = 0;
        for i in 0..f.checked_views_len {
            let entry = f.checked_views[i];
            var hit = false;
            for at in 0..(value.len as i64) {
                let local_id = g.s.words[value.start + at];
                if local_id == entry.slot || local_id == entry.generation || local_id == entry.start || local_id == entry.length || local_id == entry.base {
                    hit = true;
                    break;
                }
            }
            if !hit {
                f.checked_views[out] = entry;
                out += 1;
            }
        }
        f.checked_views_len = out;
    }
    if f.checked_elems_len != 0 {
        var out: i64 = 0;
        for i in 0..f.checked_elems_len {
            let entry = f.checked_elems[i];
            var hit = false;
            for at in 0..(value.len as i64) {
                let local_id = g.s.words[value.start + at];
                if local_id == entry.slot || local_id == entry.generation || local_id == entry.index || local_id == entry.address {
                    hit = true;
                    break;
                }
            }
            if !hit {
                f.checked_elems[out] = entry;
                out += 1;
            }
        }
        f.checked_elems_len = out;
    }
    if f.checked_bounds_len != 0 {
        var out: i64 = 0;
        for i in 0..f.checked_bounds_len {
            let entry = f.checked_bounds[i];
            var hit = false;
            for at in 0..(value.len as i64) {
                let local_id = g.s.words[value.start + at];
                if local_id == entry.index || local_id == entry.bound {
                    hit = true;
                    break;
                }
            }
            if !hit {
                f.checked_bounds[out] = entry;
                out += 1;
            }
        }
        f.checked_bounds_len = out;
    }
    if f.const_tags_len != 0 {
        var out: i64 = 0;
        for i in 0..f.const_tags_len {
            let entry = f.const_tags[i];
            var hit = false;
            for at in 0..(value.len as i64) {
                if g.s.words[value.start + at] == entry.local {
                    hit = true;
                    break;
                }
            }
            if !hit {
                f.const_tags[out] = entry;
                out += 1;
            }
        }
        f.const_tags_len = out;
    }
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
    let elide_f32_nan = id != 0 && f.elide_f32_nan_node == id;
    f.elide_f32_nan_node = 0;
    if id == 0 { return unitVal(), blot_direct_types::Error.none; }
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    match n.tag {
        constant => { return constant(g, f, id, n.a, true); },
        staging => { return stagedConstant(g, f, id); },
        reference => { return reference(g, f, id); },
        scalar => { return scalar(g, f, id, elide_f32_nan); },
        logical => { return logical(g, f, id); },
        call => { return call(g, f, id, elide_f32_nan); },
        associated => { return associated(g, f, id, elide_f32_nan); },
        if_value, if_stmt => { return ifNode(g, f, id); },
        block_ => { return block_(g, f, id); },
        fork_ => { return forkNode(g, f, id); },
        with_handle => { return withHandleNode(g, f, id); },
        comptime_for => { return comptimeForNode(g, f, id); },
        comptime_if => { return comptimeIfNode(g, f, id); },
        comptime_meta => { return comptimeMetaNode(g, f, id); },
        suite => {
            var last = unitVal();
            for child in m.children(id) {
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
        result_associated => { return resultAssociated(g, f, id); },
        contract_method => { return staticContractMethod(g, f, id); },
        operation_value => { return operationValue(g, f, id); },
        effect_provider => { return effectProvider(g, f, id); },
        state_provider => { return stateProvider(g, f, id); },
        handle => { return handleNode(g, f, id); },
        break_ => { return breakNode(g, f, id); },
        panic => {
            op(g, OP_unreachable_);
            return neverVal(), blot_direct_types::Error.none;
        },
        spark => { return sparkNode(g, f, id); },
        flat_op => { return flatOpNode(g, f, id); },
        _ => {
            g.failOpen(m, id);
            g.put(blot_direct_emit::nodeTagName(n.tag));
            g.put(" expressions are not supported yet");
            return neverVal(), g.failClose();
        },
    }
}
fn withCellType(g: const Generator&, f: const Fn&, binding: u32) -> Ty, bool {
    let val, present = blot_support_zigmap::get(g.s.map_pool, f.with_cells, binding);
    return val, present && val != 0;
}
fn readBindingVal(g: Generator&, f: Fn&, binding: u32, id: u32) -> Val, bool, Error {
    let bound, present = bindGet(g, f, binding);
    if !present { return neverVal(), false, blot_direct_types::Error.none; }
    let elem_ty, is_cell = withCellType(g, f, binding);
    if !is_cell { return bound, true, blot_direct_types::Error.none; }
    let loaded, error = readFlat(g, f, w(g, bound, 0), 0, elem_ty, id);
    return loaded, true, error;
}
fn writeWithCell(g: Generator&, f: Fn&, cell_addr: u32, elem_ty: Ty, value: Val, id: u32) -> Error {
    let noted = noteStore(g, f, value);
    if noted != blot_direct_types::Error.none { return noted; }
    let bytes, berr = g.types.flatBytes(elem_ty);
    if berr != blot_direct_types::Error.none { return berr; }
    if bytes == 0 { return blot_direct_types::Error.none; }
    if g.s.has_rt && g.s.rt.has_fork {
        gget(g, g.s.rt.fork_depth);
        op(g, OP_if_);
        op(g, 0x40);
        lget(g, cell_addr);
        i32Const(g, bytes);
        callf(g, g.s.rt.undo_record);
        op(g, OP_end);
    }
    return writeFlat(g, f, cell_addr, 0, value, id);
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
    if deferred && n.c < 2 && m.binding(n.a).scheme.variables.len != 0 {
        g.s.polymorphic.put(polyKey(f, n.a), n.b);
        return unitVal(), blot_direct_types::Error.none;
    }
    let grown, has_grown, error = linearAppend(g, f, n.b);
    if error != blot_direct_types::Error.none { return grown, error; }
    var value = grown;
    if !has_grown {
        // A generalized local value is computed once: its uses decide the one
        // type it is computed at.
        if m.binding(n.a).scheme.variables.len != 0 {
            let typed = typeByUses(g, f, n.a, n.b);
            if typed != blot_direct_types::Error.none { return neverVal(), typed; }
            // Nothing reads an unused local, so its open types are Unit.
            if uses(g, f, n.a) == 0 { defaultUnused(g, f, m.binding(n.a).ty, 0); }
        }
        if n.c < 2 && m.types.node(m.binding(n.a).ty).tag == blot_check_types::Tag.floating32 && bindingIgnoresNanPayload(g, f, n.a) {
            f.elide_f32_nan_node = n.b;
        }
        let evaluated, eval_err = stmt(g, f, n.b);
        f.elide_f32_nan_node = 0;
        if eval_err != blot_direct_types::Error.none { return evaluated, eval_err; }
        value = evaluated;
    }
    if n.c >= 2 {
        let outer_b = n.c - 2;
        let cell_val, has_cell = bindGet(g, f, outer_b);
        let elem_ty, is_cell = withCellType(g, f, outer_b);
        if has_cell && is_cell && value.ty != blot_direct_types::never {
            refine(g, f, m.binding(n.a).ty, value.ty);
            let werr = writeWithCell(g, f, w(g, cell_val, 0), elem_ty, value, id);
            if werr != blot_direct_types::Error.none { return neverVal(), werr; }
            bindPut(g, f, n.a, cell_val);
            blot_support_zigmap::put(g.s.map_pool, f.with_cells, n.a, elem_ty);
            return unitVal(), blot_direct_types::Error.none;
        }
    }
    if !has_grown && value.ty != blot_direct_types::never {
        refine(g, f, m.binding(n.a).ty, value.ty);
        if isFreshBoxedRhs(g, f, m, n.b, value.ty) {
            blot_support_zigmap::put(g.s.map_pool, f.unique_boxed, n.a, 1);
        }
        if isFreshOwnedArrayRhs(g, f, m, n.b, value.ty) {
            blot_support_zigmap::put(g.s.map_pool, f.unique_owned, n.a, 1);
        }
        if n.c == 0 && tagOf(g, value.ty) == blot_direct_types::Tag.f32_ && isBoundedFiniteF32(g, f, m, n.b) {
            recordFiniteF32(f, n.a);
        }
    }
    bindPut(g, f, n.a, value);
    if value.ty == blot_direct_types::never { return value, blot_direct_types::Error.none; }
    return unitVal(), blot_direct_types::Error.none;
}
fn bindingCaptured(g: Generator&, f: const Fn&, binding: u32) -> bool {
    let m .= g.units[f.unit - 1];
    let uid = (m.unit - 1) as i64;
    while g.s.captured_base.len < g.units.len { g.s.captured_base.push(0xffffffff); }
    var base = g.s.captured_base[uid];
    if base == 0xffffffff {
        base = g.s.captured_vals.len as u32;
        g.s.captured_base[uid] = base;
        for at in 0..m.bindings.len { g.s.captured_vals.push(0); }
        for closure in m.closures {
            for captured in m.extra[closure.captures.start..closure.captures.start + closure.captures.len] {
                if (captured as i64) < m.bindings.len { g.s.captured_vals[(base as i64) + (captured as i64)] = 1; }
            }
        }
    }
    return g.s.captured_vals[(base as i64) + (binding as i64)] != 0;
}
fn isUniqueBoxed(g: const Generator&, f: const Fn&, binding: u32) -> bool {
    let val, present = blot_support_zigmap::get(g.s.map_pool, f.unique_boxed, binding);
    return present && val != 0;
}
fn isUniqueOwned(g: const Generator&, f: const Fn&, binding: u32) -> bool {
    let val, present = blot_support_zigmap::get(g.s.map_pool, f.unique_owned, binding);
    return present && val != 0;
}
fn incOwnedMap(g: Generator&, map: blot_support_zigmap::Map&, b: u32) {
    if b == 0 { return; }
    let prev, ok = blot_support_zigmap::get(g.s.map_pool, map, b);
    var next: u32 = 1;
    if ok { next = prev + 1; }
    blot_support_zigmap::put(g.s.map_pool, map, b, next);
}
recursive fn scanOwnedUses(
    g: Generator&,
    f: Fn&,
    m: const Module&,
    id: u32,
    length_only: bool,
    overflow: bool&,
    left: i64&,
) {
    if id == 0 || overflow { return; }
    if left <= 0 { overflow = true; return; }
    left -= 1;
    let n = m.node(id);
    match n.tag {
        constant, panic => {},
        reference => {
            if !length_only {
                let b = localRef(m, id);
                if b != 0 { incOwnedMap(g, f.owned_uses, b); }
            }
        },
        suite, block_, product, record, array => {
            for child in m.children(id) { scanOwnedUses(g, f, m, child, false, overflow, left); }
        },
        bind => {
            if n.c >= 2 {
                incOwnedMap(g, f.owned_flows, n.a);
                incOwnedMap(g, f.owned_flows, n.c - 2);
            }
            scanOwnedUses(g, f, m, n.b, false, overflow, left);
        },
        pattern_bind => {
            scanOwnedUses(g, f, m, n.b, false, overflow, left);
            scanOwnedUses(g, f, m, n.c, false, overflow, left);
        },
        if_stmt, if_value => {
            scanOwnedUses(g, f, m, n.a, false, overflow, left);
            scanOwnedUses(g, f, m, n.b, false, overflow, left);
            scanOwnedUses(g, f, m, n.c, false, overflow, left);
            for merge in m.branchMerges(id) {
                incOwnedMap(g, f.owned_flows, merge.then_binding);
                incOwnedMap(g, f.owned_flows, merge.else_binding);
            }
        },
        match_ => {
            for inp in m.matchInputs(id) { scanOwnedUses(g, f, m, inp, false, overflow, left); }
            for arm in m.matchArms(id) {
                scanOwnedUses(g, f, m, arm.guard_, false, overflow, left);
                scanOwnedUses(g, f, m, arm.body, false, overflow, left);
            }
            for merge in m.branchMerges(id) {
                incOwnedMap(g, f.owned_flows, merge.then_binding);
                incOwnedMap(g, f.owned_flows, merge.else_binding);
            }
        },
        loop_ => {
            let linfo = m.loopInfo(id);
            scanOwnedUses(g, f, m, linfo.first, false, overflow, left);
            scanOwnedUses(g, f, m, linfo.end, false, overflow, left);
            for carry in m.loopCarries(id) {
                incOwnedMap(g, f.owned_flows, carry.incoming);
                incOwnedMap(g, f.owned_flows, carry.backedge);
            }
            scanOwnedUses(g, f, m, linfo.body, false, overflow, left);
        },
        break_ => {
            for child in m.breakValues(id) { scanOwnedUses(g, f, m, child, false, overflow, left); }
        },
        return_, result_associated, fork_ => {
            scanOwnedUses(g, f, m, n.a, false, overflow, left);
        },
        project => {
            let proj = m.projection(n.b);
            var is_len = false;
            if m.projectionVariants(n.b).len == 0 && proj.field != 0 {
                let sp = m.fieldSpelling(proj.field);
                is_len = sp.present && sp.value == "length";
            }
            scanOwnedUses(g, f, m, n.a, is_len, overflow, left);
        },
        construct => {
            scanOwnedUses(g, f, m, n.b, false, overflow, left);
        },
        array_op => {
            let ch = m.children(id);
            let is_len = m.arrayOperation(id) == blot_backend_collection_ops::Op.length && ch.len == 1;
            for child in ch { scanOwnedUses(g, f, m, child, is_len, overflow, left); }
        },
        storage => {
            let ch = m.children(id);
            let op_kind, ok = blot_check_storage_ops::opFromCode(n.c);
            let is_len = ok == blot_error::Error.none && op_kind == blot_check_storage_ops::Op.length && ch.len == 1;
            for child in ch { scanOwnedUses(g, f, m, child, is_len, overflow, left); }
        },
        update => {
            let change = m.updateInfo(id);
            scanOwnedUses(g, f, m, change.root, false, overflow, left);
            scanOwnedUses(g, f, m, change.value, false, overflow, left);
            for sel in m.updateSelectors(id) {
                if sel.kind == blot_check_core::UpdateKind.index {
                    scanOwnedUses(g, f, m, sel.index, false, overflow, left);
                }
            }
        },
        scalar, logical, apply => {
            scanOwnedUses(g, f, m, n.a, false, overflow, left);
            scanOwnedUses(g, f, m, n.b, false, overflow, left);
        },
        associated => {
            var is_len = false;
            if n.b == 0 && n.c != 0 {
                let sp = m.fieldSpelling(n.c);
                is_len = sp.present && sp.value == "length";
            }
            scanOwnedUses(g, f, m, n.a, is_len, overflow, left);
            scanOwnedUses(g, f, m, n.b, false, overflow, left);
        },
        call => {
            for arg in m.call(id).arguments { scanOwnedUses(g, f, m, arg, false, overflow, left); }
        },
        closure => {
            for cap in m.closureCaptures(id) { incOwnedMap(g, f.owned_flows, cap); }
        },
        spark => {
            let sinfo = m.sparkInfo(id);
            scanOwnedUses(g, f, m, sinfo.source, false, overflow, left);
            scanOwnedUses(g, f, m, sinfo.end, false, overflow, left);
            scanOwnedUses(g, f, m, sinfo.body, false, overflow, left);
        },
        _ => { overflow = true; },
    }
}
fn ensureOwnedUses(g: Generator&, f: Fn&) -> bool {
    if !f.owned_uses_computed {
        f.owned_uses_computed = true;
        let m .= g.units[f.unit - 1];
        let body .= enclosingBody(g, f);
        if !body {
            blot_support_zigmap::put(g.s.map_pool, f.owned_flows, 0xffffffff, 1);
            return false;
        }
        var overflow = false;
        var budget: i64 = 2048;
        scanOwnedUses(g, f, m, body.root, false, overflow, budget);
        if overflow {
            blot_support_zigmap::put(g.s.map_pool, f.owned_flows, 0xffffffff, 1);
            return false;
        }
    }
    let bad, present = blot_support_zigmap::get(g.s.map_pool, f.owned_flows, 0xffffffff);
    return !(present && bad != 0);
}
fn ownedRefUses(g: Generator&, f: Fn&, binding: u32) -> u32 {
    if !ensureOwnedUses(g, f) { return 0xffffffff; }
    let v, ok = blot_support_zigmap::get(g.s.map_pool, f.owned_uses, binding);
    if ok { return v; }
    return 0;
}
fn ownedFlowUses(g: Generator&, f: Fn&, binding: u32) -> u32 {
    if !ensureOwnedUses(g, f) { return 0xffffffff; }
    let v, ok = blot_support_zigmap::get(g.s.map_pool, f.owned_flows, binding);
    if ok { return v; }
    return 0;
}
fn ownedTotalUses(g: Generator&, f: Fn&, binding: u32) -> u32 {
    let r = ownedRefUses(g, f, binding);
    let fl = ownedFlowUses(g, f, binding);
    if r == 0xffffffff || fl == 0xffffffff { return 0xffffffff; }
    return r + fl;
}
fn isFreshOwnedArrayRhs(g: Generator&, f: Fn&, m: const Module&, id: u32, ty: Ty) -> bool {
    if id == 0 || tagOf(g, ty) != blot_direct_types::Tag.array { return false; }
    let n = m.node(id);
    match n.tag {
        array, spark => { return true; },
        array_op => {
            match m.arrayOperation(id) {
                fill, generate, slice, append, prepend, concat, flatten => { return true; },
                _ => { return false; },
            }
        },
        storage => {
            let op_kind, ok = blot_check_storage_ops::opFromCode(n.c);
            return ok == blot_error::Error.none && op_kind == blot_check_storage_ops::Op.copy;
        },
        reference => {
            let local_id = localRef(m, id);
            return local_id != 0 && isUniqueOwned(g, f, local_id) && ownedTotalUses(g, f, local_id) == 1 && !bindingCaptured(g, f, local_id);
        },
        _ => { return false; },
    }
}

// Conservative per-body analysis: marks every local F32 binding whose NaN
// payload could ever be observed (outside canonical F32 consumers or pure
// register propagation). Bindings NOT marked observed can elide per-op NaN
// canonicalization while preserving bit-exact 0x7fc00000 semantics everywhere.
fn markNanObserved(g: Generator&, f: Fn&, b: u32) {
    if b != 0 { blot_support_zigmap::put(g.s.map_pool, f.nan_observed, b, 1); }
}
fn isNanObserved(g: const Generator&, f: const Fn&, b: u32) -> bool {
    let v, ok = blot_support_zigmap::get(g.s.map_pool, f.nan_observed, b);
    return ok && v != 0;
}
fn addNanEdge(src_arr: u32[256]&, dst_arr: u32[256]&, len: i64&, src: u32, dst: u32) -> bool {
    if src == 0 || dst == 0 || src == dst { return true; }
    if len >= 256 { return false; }
    src_arr[len] = src;
    dst_arr[len] = dst;
    len += 1;
    return true;
}
recursive fn scanNanUses(
    g: Generator&,
    f: Fn&,
    m: const Module&,
    id: u32,
    safe_ref: bool,
    edge_src: u32[256]&,
    edge_dst: u32[256]&,
    edge_len: i64&,
    overflow: bool&,
    left: i64&,
) {
    if id == 0 || overflow { return; }
    if left <= 0 { overflow = true; return; }
    left -= 1;
    let n = m.node(id);
    match n.tag {
        constant, panic => {},
        reference => {
            let b = localRef(m, id);
            if b != 0 && !safe_ref { markNanObserved(g, f, b); }
        },
        scalar => {
            let consumer = isCanonicalF32Consumer(n.op) && m.types.node(m.typeOf(n.a)).tag == blot_check_types::Tag.floating32;
            scanNanUses(g, f, m, n.a, consumer, edge_src, edge_dst, edge_len, overflow, left);
            if n.b != 0 { scanNanUses(g, f, m, n.b, consumer, edge_src, edge_dst, edge_len, overflow, left); }
        },
        bind => {
            if n.c >= 2 {
                markNanObserved(g, f, n.a);
                scanNanUses(g, f, m, n.b, false, edge_src, edge_dst, edge_len, overflow, left);
            } else {
                let rhs_b = localRef(m, n.b);
                if rhs_b != 0 {
                    if !addNanEdge(edge_src, edge_dst, edge_len, rhs_b, n.a) { overflow = true; }
                } else {
                    scanNanUses(g, f, m, n.b, false, edge_src, edge_dst, edge_len, overflow, left);
                }
            }
        },
        suite, block_ => {
            for child in m.children(id) {
                scanNanUses(g, f, m, child, false, edge_src, edge_dst, edge_len, overflow, left);
            }
        },
        if_stmt, if_value => {
            scanNanUses(g, f, m, n.a, false, edge_src, edge_dst, edge_len, overflow, left);
            scanNanUses(g, f, m, n.b, false, edge_src, edge_dst, edge_len, overflow, left);
            scanNanUses(g, f, m, n.c, false, edge_src, edge_dst, edge_len, overflow, left);
            for merge in m.branchMerges(id) {
                if !addNanEdge(edge_src, edge_dst, edge_len, merge.then_binding, merge.result) { overflow = true; }
                if !addNanEdge(edge_src, edge_dst, edge_len, merge.else_binding, merge.result) { overflow = true; }
            }
        },
        match_ => {
            for inp in m.matchInputs(id) {
                scanNanUses(g, f, m, inp, false, edge_src, edge_dst, edge_len, overflow, left);
            }
            for arm in m.matchArms(id) {
                scanNanUses(g, f, m, arm.guard_, false, edge_src, edge_dst, edge_len, overflow, left);
                scanNanUses(g, f, m, arm.body, false, edge_src, edge_dst, edge_len, overflow, left);
            }
            for merge in m.branchMerges(id) {
                if !addNanEdge(edge_src, edge_dst, edge_len, merge.then_binding, merge.result) { overflow = true; }
                if !addNanEdge(edge_src, edge_dst, edge_len, merge.else_binding, merge.result) { overflow = true; }
            }
        },
        pattern_bind => {
            scanNanUses(g, f, m, n.b, false, edge_src, edge_dst, edge_len, overflow, left);
            scanNanUses(g, f, m, n.c, false, edge_src, edge_dst, edge_len, overflow, left);
        },
        loop_ => {
            let linfo = m.loopInfo(id);
            scanNanUses(g, f, m, linfo.first, false, edge_src, edge_dst, edge_len, overflow, left);
            scanNanUses(g, f, m, linfo.end, false, edge_src, edge_dst, edge_len, overflow, left);
            for carry in m.loopCarries(id) {
                if !addNanEdge(edge_src, edge_dst, edge_len, carry.incoming, carry.iteration) { overflow = true; }
                if !addNanEdge(edge_src, edge_dst, edge_len, carry.incoming, carry.outgoing) { overflow = true; }
                if !addNanEdge(edge_src, edge_dst, edge_len, carry.backedge, carry.iteration) { overflow = true; }
                if !addNanEdge(edge_src, edge_dst, edge_len, carry.iteration, carry.outgoing) { overflow = true; }
            }
            scanNanUses(g, f, m, linfo.body, false, edge_src, edge_dst, edge_len, overflow, left);
        },
        break_ => {
            let vals = m.breakValues(id);
            if n.a != 0 && m.node(n.a).tag == blot_check_core::Tag.loop_ {
                let carries = m.loopCarries(n.a);
                for child, ci in vals {
                    let vb = localRef(m, child);
                    if vb != 0 && ci < carries.len {
                        if n.op == blot_check_core::Op.continue_ {
                            if !addNanEdge(edge_src, edge_dst, edge_len, vb, carries[ci].iteration) { overflow = true; }
                        } else {
                            if !addNanEdge(edge_src, edge_dst, edge_len, vb, carries[ci].outgoing) { overflow = true; }
                        }
                    } else {
                        scanNanUses(g, f, m, child, false, edge_src, edge_dst, edge_len, overflow, left);
                    }
                }
            } else {
                for child in vals {
                    scanNanUses(g, f, m, child, false, edge_src, edge_dst, edge_len, overflow, left);
                }
            }
        },
        return_, project, result_associated, fork_ => {
            scanNanUses(g, f, m, n.a, false, edge_src, edge_dst, edge_len, overflow, left);
        },
        construct => {
            scanNanUses(g, f, m, n.b, false, edge_src, edge_dst, edge_len, overflow, left);
        },
        product, record, array, array_op, storage => {
            for child in m.children(id) {
                scanNanUses(g, f, m, child, false, edge_src, edge_dst, edge_len, overflow, left);
            }
        },
        update => {
            let change = m.updateInfo(id);
            scanNanUses(g, f, m, change.root, false, edge_src, edge_dst, edge_len, overflow, left);
            scanNanUses(g, f, m, change.value, false, edge_src, edge_dst, edge_len, overflow, left);
            for sel in m.updateSelectors(id) {
                if sel.kind == blot_check_core::UpdateKind.index {
                    scanNanUses(g, f, m, sel.index, false, edge_src, edge_dst, edge_len, overflow, left);
                }
            }
        },
        associated, logical, apply => {
            scanNanUses(g, f, m, n.a, false, edge_src, edge_dst, edge_len, overflow, left);
            scanNanUses(g, f, m, n.b, false, edge_src, edge_dst, edge_len, overflow, left);
        },
        call => {
            for arg in m.call(id).arguments {
                scanNanUses(g, f, m, arg, false, edge_src, edge_dst, edge_len, overflow, left);
            }
        },
        closure => {
            for cap in m.closureCaptures(id) { markNanObserved(g, f, cap); }
        },
        spark => {
            let sinfo = m.sparkInfo(id);
            scanNanUses(g, f, m, sinfo.source, false, edge_src, edge_dst, edge_len, overflow, left);
            scanNanUses(g, f, m, sinfo.end, false, edge_src, edge_dst, edge_len, overflow, left);
            scanNanUses(g, f, m, sinfo.body, false, edge_src, edge_dst, edge_len, overflow, left);
        },
        _ => { overflow = true; },
    }
}
fn bindingIgnoresNanPayload(g: Generator&, f: Fn&, binding: u32) -> bool {
    if binding == 0 || bindingCaptured(g, f, binding) { return false; }
    if !f.nan_elide_computed {
        f.nan_elide_computed = true;
        let m .= g.units[f.unit - 1];
        let body .= enclosingBody(g, f);
        if !body {
            // Sentinel 0xffffffff marks analysis unavailable (conservative).
            markNanObserved(g, f, 0xffffffff);
            return false;
        }
        var edge_src: u32[256] = [0; 256];
        var edge_dst: u32[256] = [0; 256];
        var edge_len: i64 = 0;
        var overflow = false;
        var budget: i64 = 2048;
        scanNanUses(g, f, m, body.root, false, edge_src, edge_dst, edge_len, overflow, budget);
        if overflow {
            markNanObserved(g, f, 0xffffffff);
            return false;
        }
        // Backwards fixed-point propagation along binding/carry/merge edges.
        var changed = true;
        var pass: i64 = 0;
        while changed && pass < 16 {
            changed = false;
            pass += 1;
            for ei in 0..edge_len {
                if isNanObserved(g, f, edge_dst[ei]) && !isNanObserved(g, f, edge_src[ei]) {
                    markNanObserved(g, f, edge_src[ei]);
                    changed = true;
                }
            }
        }
        if changed {
            markNanObserved(g, f, 0xffffffff);
            return false;
        }
    }
    if isNanObserved(g, f, 0xffffffff) { return false; }
    return !isNanObserved(g, f, binding);
}
fn isFreshBoxedRhs(g: Generator&, f: const Fn&, m: const Module&, id: u32, ty: Ty) -> bool {
    if id == 0 { return false; }
    let boxed, error = g.types.boxed(ty);
    if error != blot_direct_types::Error.none || !boxed { return false; }
    let n = m.node(id);
    match n.tag {
        construct, record, update => { return true; },
        reference => {
            let local_id = localRef(m, id);
            return local_id != 0 && isUniqueBoxed(g, f, local_id) && uses(g, f, local_id) == 1 && !bindingCaptured(g, f, local_id);
        },
        if_value => {
            return isFreshBoxedNode(m, n.b, 0) && isFreshBoxedNode(m, n.c, 0);
        },
        match_ => {
            for arm in m.matchArms(id) {
                if !isFreshBoxedNode(m, arm.body, 0) { return false; }
            }
            return true;
        },
        _ => { return false; },
    }
}
recursive fn isFreshBoxedNode(m: const Module&, id: u32, depth: i64) -> bool {
    if id == 0 || depth > 16 { return false; }
    let n = m.node(id);
    match n.tag {
        construct, record, update => { return true; },
        suite => {
            let items = m.children(id);
            if items.len == 0 { return false; }
            return isFreshBoxedNode(m, items[items.len - 1], depth + 1);
        },
        if_value => { return isFreshBoxedNode(m, n.b, depth + 1) && isFreshBoxedNode(m, n.c, depth + 1); },
        match_ => {
            for arm in m.matchArms(id) { if !isFreshBoxedNode(m, arm.body, depth + 1) { return false; } }
            return true;
        },
        _ => { return false; },
    }
}
fn tailConstruct(m: const Module&, id: u32) -> u32 {
    var cursor = id;
    for step in 0..8 {
        if cursor == 0 { return 0; }
        let n = m.node(cursor);
        if n.tag == blot_check_core::Tag.construct { return cursor; }
        if n.tag == blot_check_core::Tag.suite {
            let items = m.children(cursor);
            if items.len == 0 { return 0; }
            cursor = items[items.len - 1];
            continue;
        }
        return 0;
    }
    return 0;
}

fn constant(g: Generator&, f: Fn&, id: u32, bits: u32, literal:bool=false) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let ty, error = typeOf(g, f, id);
    if error != blot_direct_types::Error.none { return neverVal(), error; }
    if literal && ty!=blot_direct_types::unit { blot_direct_relocations::operand(m.unit,id,g.s.code.len); }
    match tagOf(g, ty) {
        unit => { return unitVal(), blot_direct_types::Error.none; },
        f32_ => { f32Const(g, bits); },
        u32_, boolean => { i32Const(g, bits); },
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
        let bound, present, rerr = readBindingVal(g, f, ref.binding, id);
        if rerr != blot_direct_types::Error.none { return neverVal(), rerr; }
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
    if has_alias { g.recordInlined(target.unit, target.binding); return partial(g, f, blot_direct_emit::InstanceKind.primitive, target, ty, Vals {}, id); }
    let body .= tm.body(target.binding);
    if body {
        if body.is_function { return partial(g, f, blot_direct_emit::InstanceKind.partial, target, ty, Vals {}, id); }
        match tagOf(g, ty) {
            array => { return pool(g, f, target, ty, id); },
            _ => {},
        }
        // Inline non-exported scalar or nullary-constructor constants directly
        // instead of emitting a getter call on every read.
        if !body.exported && evidenceContext(g, f, target, id) == 0 && g.types.concrete(ty, 0) {
            let root = body.root;
            let rn = tm.node(root);
            if rn.tag == blot_check_core::Tag.constant {
                let ctag = tagOf(g, ty);
                if ctag == blot_direct_types::Tag.u32_ || ctag == blot_direct_types::Tag.boolean || ctag == blot_direct_types::Tag.f32_ {
                    g.recordInlined(target.unit, target.binding);
                    blot_direct_relocations::operand(target.unit, root, g.s.code.len);
                    if ctag == blot_direct_types::Tag.f32_ { f32Const(g, rn.a); } else { i32Const(g, rn.a); }
                    return pop(g, f, ty, id);
                }
            } else if rn.tag == blot_check_core::Tag.construct && rn.b == 0 {
                let boxed, berr = isBoxed(g, f, ty, id);
                let width, werr = layoutLen(g, f, ty, id);
                if berr == blot_direct_types::Error.none && !boxed && werr == blot_direct_types::Error.none && width == 1 {
                    g.recordInlined(target.unit, target.binding);
                    let ctor_tag = tm.constructor(rn.a).tag;
                    let loc = constLocal(g, f, ctor_tag);
                    recordConstTag(f, loc, ctor_tag);
                    return valOf1(g, ty, loc), blot_direct_types::Error.none;
                }
            }
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
        usage, forall, array => { return holesUnused(g, f, n.a, depth + 1); },
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
        usage, forall, array => { defaultUnused(g, f, n.a, depth + 1); },
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
        function, array, ref, view, link, cell => { return true; },
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
    let rt = g.runtime_();
    opIndex(g, OP_global_get, rt.owner_top);
    opIndex(g, OP_local_get, owner_mark);
    op(g, OP_i32_ne);
    op(g, OP_if_);
    op(g, 0x40);
    opIndex(g, OP_local_get, owner_mark);
    opIndex(g, OP_call, rt.release);
    op(g, OP_end);
    opIndex(g, OP_global_get, rt.stack_pointer);
    opIndex(g, OP_local_get, stack_mark);
    op(g, OP_i32_ne);
    op(g, OP_if_);
    op(g, 0x40);
    opIndex(g, OP_local_get, stack_mark);
    opIndex(g, OP_call, rt.rewind_stack);
    op(g, OP_end);
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
            if tagOf(g, argument.ty) == blot_direct_types::Tag.tuple && constructor.payload != 0 && tm.types.node(constructor.payload).tag == blot_check_types::Tag.record && tm.types.node(constructor.payload).b > 1 {
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
        let next_instance = g.s.instances.len as u32;
        for binding in capture_ids {
            let _, bound_here = bindGet(g, f, binding);
            if bound_here { continue; }
            let init_node, is_poly = g.s.polymorphic.get(polyKey(f, binding));
            if is_poly && m.node(init_node).tag == blot_check_core::Tag.closure {
                recordPolyCapture(g, f, next_instance, binding, init_node, 0);
            }
        }
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
        let next_instance = g.s.instances.len as u32;
        for binding in capture_ids {
            let _, bound_here = bindGet(g, f, binding);
            if bound_here { continue; }
            let init_node, is_poly = g.s.polymorphic.get(polyKey(f, binding));
            if is_poly && m.node(init_node).tag == blot_check_core::Tag.closure {
                recordPolyCapture(g, f, next_instance, binding, init_node, 0);
            }
        }
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
