// One instance's Wasm body. A single pass over its Core body; every value is a
// list of Wasm locals in its type's layout, so projections share locals.
// Port of compiler/src/direct/function.zig. The namespace continues in
// function_*.goose.
//
// Zig's `Fn` holds its generator, module and lists. Inside this recursive
// code Goose lets references only be passed down, so every function takes
// the generator `g` and the body state `f`, `f` names its module by unit,
// and the lists are the tops of the stacks in emit.State from `f`'s marks.
namespace squid_direct_function;
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
import .function_packed;
import .function_seq;
import .function_effects;
import .function_entry;
import .function_staging;
import .function_spark;
import .function_persist;
import .function_kernels;

type Ty = u32;
type Error = squid_direct_types::Error;
type Env = squid_direct_types::Env;
type Module = squid_check_core::Module;
type Generator = squid_direct_emit::Generator;
type Val = squid_direct_emit::Val;
type Vals = squid_direct_emit::Vals;
type Tys = squid_direct_emit::Tys;
type Words = squid_direct_emit::Words;
type InstanceKey = squid_direct_emit::InstanceKey;
type InstanceKind = squid_direct_emit::InstanceKind;
type BindingRef = squid_check_core::BindingRef;
type TId = squid_check_types::Id;
type ValType = squid_direct_writer::ValType;
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
    known_tag: u32 = 0xffffffff,
    depth: u32 = 0
}
struct CheckedBound {
    index: u32 = 0,
    bound: u32 = 0,
    sized_len_ty: TId = 0,
    depth: u32 = 0
}
struct CheckedLeBound {
    a: u32 = 0,
    b: u32 = 0,
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
    serial: u32 = 0,
    block_: u32 = 0,
    loop_node: u32 = 0,
    carry_slots: Vals = Vals {},
}
struct ConstU32 {
    local_id: u32 = 0,
    value: u32 = 0,
    unit: u32 = 0,
    node: u32 = 0,
}
struct ConstU64 {
    local_id: u32 = 0,
    value: u64 = 0,
    unit: u32 = 0,
    node: u32 = 0,
}
struct ExtU32U64 {
    u64_local: u32 = 0,
    u32_local: u32 = 0,
}
struct MutableOwner {
    slot: u32 = 0,
    generation: u32 = 0,
}
struct LoopReciprocal {
    divisor: u32 = 0,
    multiplier: u32 = 0,
    shift: u32 = 0,
    check_at_use: bool = true,
}
struct LoopReciprocalU64 {
    divisor: u32 = 0,
    from_u32: bool = false,
    m_lo: u32 = 0,
    m_hi: u32 = 0,
    sh1: u32 = 0,
    sh2: u32 = 0,
    check_at_use: bool = true,
}
struct CheckedMask {
    index: u32 = 0,
    max_local: u32 = 0xffffffff,
    max_const: u32 = 0,
    has_const: bool = false,
    depth: u32 = 0,
}
struct CheckedAdd {
    res: u32 = 0,
    base: u32 = 0xffffffff,
    idx: u32 = 0,
    c: u32 = 0,
    depth: u32 = 0,
}
struct CheckedAffineBound {
    base: u32 = 0xffffffff,
    end_local: u32 = 0,
    c: u32 = 0,
    bound: u32 = 0,
    depth: u32 = 0,
}
struct CheckedSub1 {
    res: u32 = 0,
    src: u32 = 0,
    depth: u32 = 0,
}
struct PackedF32x4 {
    w0: u32 = 0,
    w1: u32 = 0,
    w2: u32 = 0,
    w3: u32 = 0,
    vloc: u32 = 0,
    depth: u32 = 0,
}
struct DirectArray {
    binding: u32 = 0,
    slot_local: u32 = 0xffffffff,
    base: u32 = 0,
    len_local: u32 = 0,
    length: u32 = 0,
    elem_ty: Ty = 0,
    step: u32 = 0,
    depth: u32 = 0,
    // Scalar-packed register mode for tiny <= 16-byte U8/Bool non-escaping buffers.
    scalar_packed: bool = false,
    pack_lo: u32 = 0xffffffff,
    pack_hi: u32 = 0xffffffff,
}
struct WorkerR {
    slot: u32 = 0xffffffff,
    generation: u32 = 0,
    base: u32 = 0,
    length: u32 = 0,
}
struct WorkerM {
    slot: u32 = 0xffffffff,
    generation: u32 = 0,
    entry: u32 = 0,
}
// Statically known closure value within the current Wasm function (surviving
// inlineSmall boundaries via word-level propagation).
// kind: 1 = partial of named function, 2 = closure literal, 3 = partial of primitive.
struct KnownClosure {
    fn_local: u32 = 0,
    env_local: u32 = 0,
    kind: u8 = 0,
    unit: u32 = 0,
    id: u32 = 0,
    instance_id: u32 = 0,
    full_ty: Ty = 0,
    cap_count: u8 = 0,
    caps: Val[4] = [Val {}; 4],
    cap_bindings: u32[4] = [0; 4],
    lambda_env: Env = Env {},
    depth: u32 = 0,
}
struct Fn {
    // Only stable value locals have facts. Loop-carried copies and mutable
    // counters start out unknown. An in-place array carry keeps its handle.
    const_u32: ConstU32[32] = [ConstU32 {}; 32],
    const_u32_len: i64 = 0,
    const_u64: ConstU64[16] = [ConstU64 {}; 16],
    const_u64_len: i64 = 0,
    ext_u32_u64: ExtU32U64[16] = [ExtU32U64 {}; 16],
    ext_u32_u64_len: i64 = 0,
    known_mutable: MutableOwner[32] = [MutableOwner {}; 32],
    known_mutable_len: i64 = 0,
    loop_reciprocals: LoopReciprocal[8] = [LoopReciprocal {}; 8],
    loop_reciprocals_len: i64 = 0,
    loop_reciprocals_u64: LoopReciprocalU64[8] = [LoopReciprocalU64 {}; 8],
    loop_reciprocals_u64_len: i64 = 0,
    checked_range: CheckedRange = CheckedRange {},
    checked_arrays: CheckedArray[16] = [CheckedArray {}; 16],
    checked_arrays_len: i64 = 0,
    checked_grows: CheckedGrow[8] = [CheckedGrow {}; 8],
    checked_grows_len: i64 = 0,
    checked_views: CheckedView[8] = [CheckedView {}; 8],
    checked_views_len: i64 = 0,
    checked_elems: CheckedElem[8] = [CheckedElem {}; 8],
    checked_elems_len: i64 = 0,
    checked_bounds: CheckedBound[32] = [CheckedBound {}; 32],
    checked_bounds_len: i64 = 0,
    checked_le: CheckedLeBound[16] = [CheckedLeBound {}; 16],
    checked_le_len: i64 = 0,
    checked_masks: CheckedMask[32] = [CheckedMask {}; 32],
    checked_masks_len: i64 = 0,
    checked_adds: CheckedAdd[8] = [CheckedAdd {}; 8],
    checked_adds_len: i64 = 0,
    checked_affines: CheckedAffineBound[8] = [CheckedAffineBound {}; 8],
    checked_affines_len: i64 = 0,
    checked_sub1: CheckedSub1[16] = [CheckedSub1 {}; 16],
    checked_sub1_len: i64 = 0,
    packed_f32x4: PackedF32x4[16] = [PackedF32x4 {}; 16],
    packed_f32x4_len: i64 = 0,
    comptime_frames: ComptimeFrame[16] = [ComptimeFrame {}; 16],
    comptime_len: i64 = 0,
    sites_base:i64=0,
    scratch_body: u32 = 0,
    scratch_cut: ScratchCut = ScratchCut {},
    // Uniquely-owned boxed bindings eligible for FBIP same-shape reuse.
    unique_boxed: squid_support_zigmap::Map = squid_support_zigmap::Map {},
    // Non-escaping, non-boxed field projection references already emitted on unique_boxed bindings.
    unique_boxed_safe_refs: squid_support_zigmap::Map = squid_support_zigmap::Map {},
    // Outer curried parameters of an inlined multi-arg lambda proven not captured in its peeled body.
    inlined_uncaptured: u32[8] = [0; 8],
    inlined_uncaptured_len: i64 = 0,
    // Transitive depth of cross-function KnownClosure specialization for this body.
    closure_spec_depth: u8 = 0,
    // Uniquely-owned local/own-param array/container bindings eligible for in-place spark reuse.
    unique_owned: squid_support_zigmap::Map = squid_support_zigmap::Map {},
    loop_depth: u32 = 0,
    indirect_bound_binding: u32 = 0,
    indirect_bound_len: u32 = 0,
    owned_uses_computed: bool = false,
    owned_uses: squid_support_zigmap::Map = squid_support_zigmap::Map {},
    owned_flows: squid_support_zigmap::Map = squid_support_zigmap::Map {},
    reuse_nodes: u32[4] = [0; 4],
    reuse_nodes_len: i64 = 0,
    reuse_block: u32 = 0,
    reuse_ty: Ty = 0,
    reuse_preexisting: bool = false,
    boxed_noop_alias: bool = false,
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
    shadows_base: i64 = 0,
    labels_base: i64 = 0,
    parameter_words: u32 = 0,
    bindings: squid_support_zigmap::Map = squid_support_zigmap::Map {},
    with_cells: squid_support_zigmap::Map = squid_support_zigmap::Map {},
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
    nan_observed: squid_support_zigmap::Map = squid_support_zigmap::Map {},
    // Local F32 bindings statically proved finite and bounded (|x| <= 2^33).
    finite_f32: u32[32] = [0; 32],
    finite_f32_len: i64 = 0,
    // Set on prefix iterations 0..end-2 of a pure-FP counted loop whose final
    // iteration canonicalizes all overwritten F32 outputs to exact 0x7fc00000.
    defer_f32_nan: bool = false,
    // Non-zero while emitting an inlined function body via `inlineSmall`.
    inlined_body_binding: u32 = 0,
    // Non-zero while emitting an inlined lambda/const body root in `f.unit`.
    inlined_body_root: u32 = 0,
    known_closures: KnownClosure[16] = [KnownClosure {}; 16],
    known_closures_len: i64 = 0,
    // Prevents recursive loop-specialization cloning.
    in_specialized_loop: bool = false,
    spec_loop_depth: u32 = 0,
    // 6A: Local holding 1 iff the pre-scanned indirect index array is strictly increasing.
    indirect_bound_distinct_local: u32 = 0xffffffff,
    // Tail-call optimization state:
    // `fn_return_block`: outermost Core block of a named body (returns targeting it exit the fn).
    // `self_tco_loop`: Wasm loop depth for MVP self-tail-call-to-loop lowering (0xffffffff if none).
    // `self_tco_inputs`: parameter value slots rebound on each self-tail-call backedge.
    // `tail_call_node`: exact Core `Tag.call` node currently being emitted in function tail position.
    // `tco_inhibit`: > 0 inside `fork`, `inlineSmall`, etc. where tail jumps must not fire.
    // `emitted_return_call`: true if Wasm 3.0 `return_call` fired (suppresses entry/exit release wrap).
    fn_return_block: u32 = 0,
    self_tco_loop: u32 = 0xffffffff,
    self_tco_inputs: Vals = Vals {},
    tail_call_node: u32 = 0,
    direct_returns: bool = false,
    assoc_tco_local: u32 = 0xffffffff,
    assoc_tco_opcode: u8 = 0,
    assoc_tco_ty: Ty = 0,
    tco_inhibit: u32 = 0,
    emitted_return_call: bool = false,
    // 7B: `@array.fill` node IDs proved completely overwritten by an immediately following 0..n loop.
    skip_fill_nodes: u32[8] = [0; 8],
    skip_fill_len: i64 = 0,
    // Backend-only stack-inlined small fixed local arrays (skip owner table open/check/release).
    direct_arrays: DirectArray[16] = [DirectArray {}; 16],
    direct_arrays_len: i64 = 0,
    // Active specialized recursive worker state (never cleared by invalidateCheckedContainers).
    worker_spec: i64 = -1,
    worker_scc_idx: i64 = -1,
    worker_r: WorkerR[16] = [WorkerR {}; 16],
    worker_r_len: i64 = 0,
    worker_m: WorkerM[16] = [WorkerM {}; 16],
    worker_m_len: i64 = 0,
    // 1-level small-leaf peeling state inside a self-recursive worker.
    peel_active: bool = false,
    peel_d_idx: i64 = -1,
    peel_prefix_parent: u32 = 0,
    peel_if_pos: i64 = -1,
    peel_force_leaf: bool = false,
}

fn recordSkipFillNode(f: Fn&, id: u32) {
    if id == 0 || f.skip_fill_len >= 8 { return; }
    for i in 0..f.skip_fill_len {
        if f.skip_fill_nodes[i] == id { return; }
    }
    f.skip_fill_nodes[f.skip_fill_len] = id;
    f.skip_fill_len += 1;
}
fn findDirectArray(f: const Fn&, binding: u32) -> i64 {
    if binding == 0 { return -1; }
    var at = f.direct_arrays_len;
    while at > 0 {
        at -= 1;
        if f.direct_arrays[at].binding == binding { return at; }
    }
    return -1;
}
fn findDirectArrayBySlot(f: const Fn&, slot_local: u32) -> i64 {
    var at = f.direct_arrays_len;
    while at > 0 {
        at -= 1;
        if f.direct_arrays[at].slot_local == slot_local { return at; }
    }
    return -1;
}
fn recordDirectArray(f: Fn&, binding: u32, slot_local: u32, base: u32, len_local: u32, length: u32, elem_ty: Ty, step: u32, scalar_packed: bool = false, pack_lo: u32 = 0xffffffff, pack_hi: u32 = 0xffffffff) {
    if binding == 0 || f.direct_arrays_len >= 16 { return; }
    f.direct_arrays[f.direct_arrays_len] = DirectArray { binding, slot_local, base, len_local, length, elem_ty, step, f.depth, scalar_packed, pack_lo, pack_hi };
    f.direct_arrays_len += 1;
}
fn findWorkerR(f: const Fn&, slot: u32, generation: u32) -> i64 {
    var i = f.worker_r_len;
    while i > 0 {
        i -= 1;
        if f.worker_r[i].slot == slot && f.worker_r[i].generation == generation { return i; }
    }
    return -1;
}
fn recordWorkerR(f: Fn&, slot: u32, generation: u32, base: u32, length: u32) {
    if findWorkerR(f, slot, generation) >= 0 || f.worker_r_len >= 16 { return; }
    f.worker_r[f.worker_r_len] = WorkerR { slot, generation, base, length };
    f.worker_r_len += 1;
}
fn findWorkerM(f: const Fn&, slot: u32, generation: u32) -> i64 {
    var i = f.worker_m_len;
    while i > 0 {
        i -= 1;
        if f.worker_m[i].slot == slot && f.worker_m[i].generation == generation { return i; }
    }
    return -1;
}
fn recordWorkerM(f: Fn&, slot: u32, generation: u32, entry: u32) {
    if findWorkerM(f, slot, generation) >= 0 || f.worker_m_len >= 16 { return; }
    f.worker_m[f.worker_m_len] = WorkerM { slot, generation, entry };
    f.worker_m_len += 1;
}
fn consumeSkipFillNode(f: Fn&, id: u32) -> bool {
    if id == 0 || f.skip_fill_len == 0 { return false; }
    for i in 0..f.skip_fill_len {
        if f.skip_fill_nodes[i] == id {
            f.skip_fill_nodes[i] = 0;
            return true;
        }
    }
    return false;
}

fn constU32(f: const Fn&, local_id: u32) -> ConstU32, bool {
    for at in 0..f.const_u32_len {
        let fact = f.const_u32[at];
        if fact.local_id == local_id { return fact, true; }
    }
    return ConstU32 {}, false;
}
fn recordConstU32(f: Fn&, local_id: u32, value: u32, unit: u32 = 0, node: u32 = 0) {
    if f.const_u32_len >= 32 { return; }
    f.const_u32[f.const_u32_len] = ConstU32 { local_id, value, unit, node };
    f.const_u32_len += 1;
}
fn useConstU32(fact: ConstU32) {
    if fact.node != 0 { squid_direct_relocations::unpatchableOperand(fact.unit, fact.node); }
}
fn constU64(f: const Fn&, local_id: u32) -> ConstU64, bool {
    for at in 0..f.const_u64_len {
        let fact = f.const_u64[at];
        if fact.local_id == local_id { return fact, true; }
    }
    return ConstU64 {}, false;
}
fn recordConstU64(f: Fn&, local_id: u32, value: u64, unit: u32 = 0, node: u32 = 0) {
    if f.const_u64_len >= 16 { return; }
    f.const_u64[f.const_u64_len] = ConstU64 { local_id, value, unit, node };
    f.const_u64_len += 1;
}
fn useConstU64(fact: ConstU64) {
    if fact.node != 0 { squid_direct_relocations::unpatchableOperand(fact.unit, fact.node); }
}
fn recordExtU32U64(f: Fn&, u64_local: u32, u32_local: u32) {
    if f.ext_u32_u64_len >= 16 { return; }
    f.ext_u32_u64[f.ext_u32_u64_len] = ExtU32U64 { u64_local, u32_local };
    f.ext_u32_u64_len += 1;
}
fn findExtU32U64(f: const Fn&, u64_local: u32) -> u32, bool {
    var i = f.ext_u32_u64_len;
    while i > 0 {
        i -= 1;
        if f.ext_u32_u64[i].u64_local == u64_local { return f.ext_u32_u64[i].u32_local, true; }
    }
    return 0, false;
}
fn recordCheckedMask(f: Fn&, index: u32, max_local: u32, max_const: u32, has_const: bool) {
    if f.checked_masks_len >= 32 { return; }
    f.checked_masks[f.checked_masks_len] = CheckedMask { index, max_local, max_const, has_const, f.depth };
    f.checked_masks_len += 1;
}
fn findCheckedMask(f: const Fn&, index: u32) -> i64 {
    var i = f.checked_masks_len;
    while i > 0 {
        i -= 1;
        if f.checked_masks[i].index == index { return i; }
    }
    return -1;
}
fn recordCheckedAdd(f: Fn&, res: u32, base: u32, idx: u32, c: u32) {
    if f.checked_adds_len >= 8 { return; }
    f.checked_adds[f.checked_adds_len] = CheckedAdd { res, base, idx, c, f.depth };
    f.checked_adds_len += 1;
}
fn findCheckedAdd(f: const Fn&, res: u32) -> i64 {
    var i = f.checked_adds_len;
    while i > 0 {
        i -= 1;
        if f.checked_adds[i].res == res { return i; }
    }
    return -1;
}
fn recordCheckedAffine(f: Fn&, base: u32, end_local: u32, c: u32, bound: u32) {
    if f.checked_affines_len >= 8 { return; }
    f.checked_affines[f.checked_affines_len] = CheckedAffineBound { base, end_local, c, bound, f.depth };
    f.checked_affines_len += 1;
}
fn findCheckedAffine(f: const Fn&, base: u32, end_local: u32, c: u32, bound: u32) -> i64 {
    var i = f.checked_affines_len;
    while i > 0 {
        i -= 1;
        let e = f.checked_affines[i];
        if e.base == base && e.end_local == end_local && c <= e.c &&
            (e.bound == bound || findCheckedLe(f, e.bound, bound) >= 0) {
            return i;
        }
    }
    return -1;
}
fn recordCheckedSub1(f: Fn&, res: u32, src: u32) {
    if f.checked_sub1_len >= 16 { return; }
    f.checked_sub1[f.checked_sub1_len] = CheckedSub1 { res, src, f.depth };
    f.checked_sub1_len += 1;
}
fn findCheckedSub1(f: const Fn&, res: u32, src: u32) -> i64 {
    var i = f.checked_sub1_len;
    while i > 0 {
        i -= 1;
        let e = f.checked_sub1[i];
        if e.res == res && e.src == src { return i; }
    }
    return -1;
}
fn findPackedF32x4(f: const Fn&, w0: u32, w1: u32, w2: u32, w3: u32) -> i64 {
    var i = f.packed_f32x4_len;
    while i > 0 {
        i -= 1;
        let e = f.packed_f32x4[i];
        if e.w0 == w0 && e.w1 == w1 && e.w2 == w2 && e.w3 == w3 { return i; }
    }
    return -1;
}
fn recordPackedF32x4(f: Fn&, w0: u32, w1: u32, w2: u32, w3: u32, vloc: u32) {
    if f.packed_f32x4_len >= 16 { return; }
    f.packed_f32x4[f.packed_f32x4_len] = PackedF32x4 { w0, w1, w2, w3, vloc, f.depth };
    f.packed_f32x4_len += 1;
}
fn packF32x4Cached(g: Generator&, f: Fn&, w0: u32, w1: u32, w2: u32, w3: u32) -> u32 {
    let hit = findPackedF32x4(f, w0, w1, w2, w3);
    if hit >= 0 { return f.packed_f32x4[hit].vloc; }
    let vloc = local(g, f, VT_v128);
    lget(g, w0);
    simdOp(g, SIMD_f32x4_splat);
    lget(g, w1);
    simdLaneOp(g, SIMD_f32x4_replace_lane, 1);
    lget(g, w2);
    simdLaneOp(g, SIMD_f32x4_replace_lane, 2);
    lget(g, w3);
    simdLaneOp(g, SIMD_f32x4_replace_lane, 3);
    lset(g, vloc);
    recordPackedF32x4(f, w0, w1, w2, w3, vloc);
    return vloc;
}
fn isMutableOwnerTag(tag: squid_direct_types::Tag) -> bool {
    return tag == squid_direct_types::Tag.array || tag == squid_direct_types::Tag.packed || tag == squid_direct_types::Tag.seq;
}
fn knownMutable(g: const Generator&, f: const Fn&, owner: Val) -> bool {
    if !isMutableOwnerTag(tagOf(g, owner.ty)) { return false; }
    let slot = w(g, owner, 0);
    let generation = w(g, owner, 1);
    for at in 0..f.known_mutable_len {
        let fact = f.known_mutable[at];
        if fact.slot == slot && fact.generation == generation { return true; }
    }
    return false;
}
fn recordMutable(g: const Generator&, f: Fn&, owner: Val) {
    if !isMutableOwnerTag(tagOf(g, owner.ty)) || f.known_mutable_len >= 32 || knownMutable(g, f, owner) { return; }
    f.known_mutable[f.known_mutable_len] = MutableOwner { w(g, owner, 0), w(g, owner, 1) };
    f.known_mutable_len += 1;
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

// Materialization is reusable within straight-line code. An extraction in
// one arm of a branch (or in a possibly empty loop) does not dominate its exit.
fn op(g: Generator&, value: u8) {
    if value == OP_else_ || value == OP_end || value == OP_if_ || value == OP_block || value == OP_loop {
        g.s.shadow_epoch += 1;
    }
    g.s.code.push(value);
}
fn opIndex(g: Generator&, value: u8, index: u32) {
    if value == OP_local_get && isShadowWord(index) { lget(g, index); return; }
    g.s.code.push(value);
    if g.s.parallel_readonly {
        if (value == OP_call || value == OP_return_call) && squid_direct_emit::tryPatchCall(g, index) { return; }
        if (value == OP_call_indirect || value == OP_return_call_indirect) && squid_direct_emit::tryPatchSig(g, index) { return; }
    }
    squid_direct_writer::uleb(g.s.code, index);
}
fn uleb(g: Generator&, value: u32) { squid_direct_writer::uleb(g.s.code, value); }
fn opIndexRaw(g: Generator&, value: u8, index: u32) {
    g.s.code.push(value);
    if index < 128 { g.s.code.push(index as u8); } else { squid_direct_writer::uleb(g.s.code, index); }
}
// Shadow words can be projected, flattened or passed around like ordinary
// immutable words. All scalar machine reads converge here, including reads
// from only part of a tuple or from a larger product containing one.
let shadow_word_bit: u32 = 0x80000000;
fn isShadowWord(word: u32) -> bool { return (word & shadow_word_bit) != 0; }
fn shadowIndex(word: u32) -> u32 { return (word & ~shadow_word_bit) >> 2; }
fn lget(g: Generator&, id: u32) {
    if !isShadowWord(id) {
        opIndexRaw(g, OP_local_get, id);
        return;
    }
    let at = shadowIndex(id);
    let shadow = g.s.v128_shadows[at];
    if shadow.materialized_at != g.s.shadow_epoch {
        if shadow.is_wide {
            let opcode = if shadow.is_float { SIMD_f64x2_extract_lane } else { SIMD_i64x2_extract_lane };
            for lane in 0..2 {
                opIndexRaw(g, OP_local_get, shadow.vloc);
                simdLaneOp(g, opcode, lane as u8);
                lset(g, shadow.w0 + (lane as u32));
            }
        } else {
            var opcode = SIMD_i32x4_extract_lane;
            if shadow.is_float { opcode = SIMD_f32x4_extract_lane; }
            for lane in 0..4 {
                opIndexRaw(g, OP_local_get, shadow.vloc);
                simdLaneOp(g, opcode, lane as u8);
                lset(g, shadow.w0 + (lane as u32));
            }
        }
        g.s.v128_shadows[at].materialized_at = g.s.shadow_epoch;
    }
    opIndexRaw(g, OP_local_get, shadow.w0 + (id & 3));
}
fn lset(g: Generator&, id: u32) { opIndexRaw(g, OP_local_set, id); }
fn ltee(g: Generator&, id: u32) { opIndexRaw(g, OP_local_tee, id); }
fn gget(g: Generator&, id: u32) { opIndexRaw(g, OP_global_get, id); }
fn gset(g: Generator&, id: u32) { opIndexRaw(g, OP_global_set, id); }
fn callf(g: Generator&, function: u32) { opIndex(g, OP_call, function); }
fn i32Const(g: Generator&, value: u32) {
    g.s.code.push(OP_i32_const);
    if value < 64 { g.s.code.push(value as u8); return; }
    squid_direct_writer::sleb(g.s.code, (value as! i32));
}
fn i64Const(g: Generator&, value: i64) {
    op(g, OP_i64_const);
    squid_direct_writer::sleb(g.s.code, value);
}
fn f32Const(g: Generator&, bits: u32) {
    g.s.code.push(OP_f32_const);
    squid_direct_writer::word(g.s.code, bits);
}
fn f64Const(g: Generator&, low: u32, high: u32) {
    op(g, OP_f64_const);
    squid_direct_writer::word(g.s.code, low);
    squid_direct_writer::word(g.s.code, high);
}
fn pushConstant(g: Generator&, ty: Ty, low: u32, high: u32 = 0) {
    match tagOf(g, ty) {
        f32_ => { f32Const(g, low); },
        f64_ => { f64Const(g, low, high); },
        i64_, u64_ => { i64Const(g, ((low as u64) | ((high as u64) << 32)) as! i64); },
        _ => { i32Const(g, low); },
    }
}
fn pushZero(g: Generator&, kind: ValType) {
    match kind {
        VT_i64 => { i64Const(g, 0); },
        VT_f64 => { f64Const(g, 0, 0); },
        VT_f32 => { f32Const(g, 0); },
        _ => { i32Const(g, 0); },
    }
}
// Opens a void structured block (block, loop or if) and returns its depth.
fn open(g: Generator&, f: Fn&, kind: u8) -> u32 {
    op(g, kind);
    g.s.code.push(0x40);
    f.depth += 1;
    return f.depth;
}
fn close(g: Generator&, f: Fn&) {
    op(g, OP_end);
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
    while f.checked_le_len > 0 && f.checked_le[f.checked_le_len - 1].depth > max_depth {
        f.checked_le_len -= 1;
    }
    while f.const_tags_len > 0 && f.const_tags[f.const_tags_len - 1].depth > max_depth {
        f.const_tags_len -= 1;
    }
    while f.checked_masks_len > 0 && f.checked_masks[f.checked_masks_len - 1].depth > max_depth {
        f.checked_masks_len -= 1;
    }
    while f.checked_adds_len > 0 && f.checked_adds[f.checked_adds_len - 1].depth > max_depth {
        f.checked_adds_len -= 1;
    }
    while f.checked_affines_len > 0 && f.checked_affines[f.checked_affines_len - 1].depth > max_depth {
        f.checked_affines_len -= 1;
    }
    while f.checked_sub1_len > 0 && f.checked_sub1[f.checked_sub1_len - 1].depth > max_depth {
        f.checked_sub1_len -= 1;
    }
    while f.packed_f32x4_len > 0 && f.packed_f32x4[f.packed_f32x4_len - 1].depth > max_depth {
        f.packed_f32x4_len -= 1;
    }
    while f.direct_arrays_len > 0 && f.direct_arrays[f.direct_arrays_len - 1].depth > max_depth {
        f.direct_arrays_len -= 1;
    }
    while f.known_closures_len > 0 && f.known_closures[f.known_closures_len - 1].depth > max_depth {
        f.known_closures_len -= 1;
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
    while f.checked_le_len > 0 && f.checked_le[f.checked_le_len - 1].depth >= depth {
        f.checked_le_len -= 1;
    }
    while f.const_tags_len > 0 && f.const_tags[f.const_tags_len - 1].depth >= depth {
        f.const_tags_len -= 1;
    }
    while f.checked_masks_len > 0 && f.checked_masks[f.checked_masks_len - 1].depth >= depth {
        f.checked_masks_len -= 1;
    }
    while f.checked_adds_len > 0 && f.checked_adds[f.checked_adds_len - 1].depth >= depth {
        f.checked_adds_len -= 1;
    }
    while f.checked_affines_len > 0 && f.checked_affines[f.checked_affines_len - 1].depth >= depth {
        f.checked_affines_len -= 1;
    }
    while f.checked_sub1_len > 0 && f.checked_sub1[f.checked_sub1_len - 1].depth >= depth {
        f.checked_sub1_len -= 1;
    }
    while f.packed_f32x4_len > 0 && f.packed_f32x4[f.packed_f32x4_len - 1].depth >= depth {
        f.packed_f32x4_len -= 1;
    }
    while f.direct_arrays_len > 0 && f.direct_arrays[f.direct_arrays_len - 1].depth >= depth {
        f.direct_arrays_len -= 1;
    }
    while f.known_closures_len > 0 && f.known_closures[f.known_closures_len - 1].depth >= depth {
        f.known_closures_len -= 1;
    }
}
fn findKnownClosure(f: const Fn&, fn_local: u32, env_local: u32) -> i64 {
    var i = f.known_closures_len;
    while i > 0 {
        i -= 1;
        if f.known_closures[i].fn_local == fn_local && f.known_closures[i].env_local == env_local {
            return i;
        }
    }
    return -1;
}
fn recordKnownClosure(f: Fn&, kc: KnownClosure) {
    if f.known_closures_len >= 16 { return; }
    f.known_closures[f.known_closures_len] = kc;
    f.known_closures_len += 1;
}
fn propagateKnownClosures(g: const Generator&, f: Fn&, src: Val, dst: Val, out_depth: u32) {
    if src.len != dst.len || src.len < 2 || f.known_closures_len == 0 { return; }
    var moved: KnownClosure[8] = [KnownClosure {}; 8];
    var moved_len: i64 = 0;
    var off: i64 = 0;
    while off + 1 < (src.len as i64) {
        let s0 = w(g, src, off);
        let s1 = w(g, src, off + 1);
        let idx = findKnownClosure(f, s0, s1);
        if idx >= 0 {
            if moved_len < 8 {
                var copied = f.known_closures[idx];
                copied.fn_local = w(g, dst, off);
                copied.env_local = w(g, dst, off + 1);
                copied.depth = out_depth;
                moved[moved_len] = copied;
                moved_len += 1;
            }
            off += 2;
        } else {
            off += 1;
        }
    }
    if moved_len == 0 { return; }
    while f.known_closures_len > 0 && f.known_closures[f.known_closures_len - 1].depth > out_depth {
        f.known_closures_len -= 1;
    }
    for mi in 0..moved_len {
        recordKnownClosure(f, moved[mi]);
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
fn recordCheckedArrayAtDepth(f: Fn&, slot: u32, generation: u32, base: u32, length: u32, depth: u32) {
    if findCheckedArray(f, slot, generation) >= 0 { return; }
    if f.checked_arrays_len >= 16 { return; }
    f.checked_arrays[f.checked_arrays_len] = CheckedArray { slot: slot, generation: generation, base: base, length: length, depth: depth };
    f.checked_arrays_len += 1;
}
fn recordCheckedArray(f: Fn&, slot: u32, generation: u32, base: u32, length: u32) {
    recordCheckedArrayAtDepth(f, slot, generation, base, length, f.depth);
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
    f.checked_elems[f.checked_elems_len] = CheckedElem { slot: slot, generation: generation, index: index, step: step, address: address, val_local: 0xffffffff, val_ty: 0, known_tag: 0xffffffff, depth: f.depth };
    f.checked_elems_len += 1;
}
fn recordCheckedElemVal(f: Fn&, slot: u32, generation: u32, index: u32, step: u32, val_local: u32, val_ty: Ty) {
    let at = findCheckedElem(f, slot, generation, index, step);
    if at >= 0 {
        f.checked_elems[at].val_local = val_local;
        f.checked_elems[at].val_ty = val_ty;
    }
}
fn recordCheckedElemTag(f: Fn&, slot: u32, generation: u32, index: u32, step: u32, tag: u32) -> i64, u32 {
    let at = findCheckedElem(f, slot, generation, index, step);
    if at < 0 { return -1, 0xffffffff; }
    let prev = f.checked_elems[at].known_tag;
    f.checked_elems[at].known_tag = tag;
    return at, prev;
}
fn invalidateCheckedOwner(g: const Generator&, f: Fn&, container: Val) {
    let slot = w(g, container, 0);
    let gen = w(g, container, 1);
    if f.checked_arrays_len != 0 {
        var out: i64 = 0;
        for i in 0..f.checked_arrays_len {
            let entry = f.checked_arrays[i];
            if entry.slot == slot && entry.generation == gen {
                // Also drop any CheckedBound/CheckedLe referencing this owner's old cached length local.
                if f.checked_bounds_len != 0 {
                    var bout: i64 = 0;
                    for bi in 0..f.checked_bounds_len {
                        let bentry = f.checked_bounds[bi];
                        if bentry.bound != entry.length && bentry.bound != 0xffffffff && bentry.index != entry.length {
                            f.checked_bounds[bout] = bentry;
                            bout += 1;
                        }
                    }
                    f.checked_bounds_len = bout;
                }
                if f.checked_le_len != 0 {
                    var lout: i64 = 0;
                    for li in 0..f.checked_le_len {
                        let lentry = f.checked_le[li];
                        if lentry.a != entry.length && lentry.b != entry.length {
                            f.checked_le[lout] = lentry;
                            lout += 1;
                        }
                    }
                    f.checked_le_len = lout;
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
fn findCheckedLe(f: const Fn&, a: u32, b: u32) -> i64 {
    var i = f.checked_le_len;
    while i > 0 {
        i -= 1;
        let entry = f.checked_le[i];
        if entry.a == a && entry.b == b { return i; }
    }
    return -1;
}
fn recordCheckedLe(f: Fn&, a: u32, b: u32) {
    if a == b || findCheckedLe(f, a, b) >= 0 { return; }
    if f.checked_le_len >= 16 { return; }
    f.checked_le[f.checked_le_len] = CheckedLeBound { a: a, b: b, depth: f.depth };
    f.checked_le_len += 1;
}
fn findCheckedBound(f: const Fn&, index: u32, bound: u32) -> i64 {
    if bound == 0xffffffff { return -1; }
    var i = f.checked_bounds_len;
    while i > 0 {
        i -= 1;
        let entry = f.checked_bounds[i];
        if entry.index == index && entry.bound != 0xffffffff && (entry.bound == bound || findCheckedLe(f, entry.bound, bound) >= 0) { return i; }
    }
    return -1;
}
fn findCheckedSizedBound(m: const Module&, f: const Fn&, index: u32, len_ty: TId) -> bool {
    if len_ty == 0 { return false; }
    var i = f.checked_bounds_len;
    while i > 0 {
        i -= 1;
        let entry = f.checked_bounds[i];
        if entry.index == index && entry.sized_len_ty != 0 && sameSizedLength(m, entry.sized_len_ty, len_ty) { return true; }
    }
    return false;
}
fn recordCheckedBoundSized(f: Fn&, index: u32, bound: u32, sized_len_ty: TId) {
    var i = f.checked_bounds_len;
    while i > 0 {
        i -= 1;
        let entry = f.checked_bounds[i];
        if entry.index == index && entry.bound == bound && entry.sized_len_ty == sized_len_ty { return; }
    }
    if f.checked_bounds_len >= 32 { return; }
    f.checked_bounds[f.checked_bounds_len] = CheckedBound { index: index, bound: bound, sized_len_ty: sized_len_ty, depth: f.depth };
    f.checked_bounds_len += 1;
}
fn recordCheckedBound(f: Fn&, index: u32, bound: u32) {
    if findCheckedBound(f, index, bound) >= 0 { return; }
    recordCheckedBoundSized(f, index, bound, 0);
}
fn invalidateCheckedContainers(f: Fn&) {
    f.checked_arrays_len = 0;
    f.checked_views_len = 0;
    f.checked_elems_len = 0;
    f.checked_bounds_len = 0;
    f.checked_le_len = 0;
    f.checked_affines_len = 0;
}
fn invalidateCheckedArrayVal(g: const Generator&, f: Fn&, value: Val) {
    if value.len == 0 { return; }
    var constants: i64 = 0;
    for at in 0..f.const_u32_len {
        let fact = f.const_u32[at];
        if !hasWord(g, value, fact.local_id) {
            f.const_u32[constants] = fact;
            constants += 1;
        }
    }
    f.const_u32_len = constants;
    var owners: i64 = 0;
    for at in 0..f.known_mutable_len {
        let fact = f.known_mutable[at];
        if !hasWord(g, value, fact.slot) && !hasWord(g, value, fact.generation) {
            f.known_mutable[owners] = fact;
            owners += 1;
        }
    }
    f.known_mutable_len = owners;
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
    if f.checked_le_len != 0 {
        var out: i64 = 0;
        for i in 0..f.checked_le_len {
            let entry = f.checked_le[i];
            var hit = false;
            for at in 0..(value.len as i64) {
                let local_id = g.s.words[value.start + at];
                if local_id == entry.a || local_id == entry.b {
                    hit = true;
                    break;
                }
            }
            if !hit {
                f.checked_le[out] = entry;
                out += 1;
            }
        }
        f.checked_le_len = out;
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
    if f.checked_masks_len != 0 {
        var out: i64 = 0;
        for i in 0..f.checked_masks_len {
            let entry = f.checked_masks[i];
            var hit = false;
            for at in 0..(value.len as i64) {
                let lid = g.s.words[value.start + at];
                if lid == entry.index || lid == entry.max_local { hit = true; break; }
            }
            if !hit { f.checked_masks[out] = entry; out += 1; }
        }
        f.checked_masks_len = out;
    }
    if f.checked_adds_len != 0 {
        var out: i64 = 0;
        for i in 0..f.checked_adds_len {
            let entry = f.checked_adds[i];
            var hit = false;
            for at in 0..(value.len as i64) {
                let lid = g.s.words[value.start + at];
                if lid == entry.res || lid == entry.base || lid == entry.idx { hit = true; break; }
            }
            if !hit { f.checked_adds[out] = entry; out += 1; }
        }
        f.checked_adds_len = out;
    }
    if f.checked_affines_len != 0 {
        var out: i64 = 0;
        for i in 0..f.checked_affines_len {
            let entry = f.checked_affines[i];
            var hit = false;
            for at in 0..(value.len as i64) {
                let lid = g.s.words[value.start + at];
                if lid == entry.base || lid == entry.end_local || lid == entry.bound { hit = true; break; }
            }
            if !hit { f.checked_affines[out] = entry; out += 1; }
        }
        f.checked_affines_len = out;
    }
    if f.checked_sub1_len != 0 {
        var out: i64 = 0;
        for i in 0..f.checked_sub1_len {
            let entry = f.checked_sub1[i];
            var hit = false;
            for at in 0..(value.len as i64) {
                let lid = g.s.words[value.start + at];
                if lid == entry.res || lid == entry.src { hit = true; break; }
            }
            if !hit { f.checked_sub1[out] = entry; out += 1; }
        }
        f.checked_sub1_len = out;
    }
    if f.packed_f32x4_len != 0 {
        var out: i64 = 0;
        for i in 0..f.packed_f32x4_len {
            let entry = f.packed_f32x4[i];
            var hit = false;
            for at in 0..(value.len as i64) {
                let lid = g.s.words[value.start + at];
                if lid == entry.w0 || lid == entry.w1 || lid == entry.w2 || lid == entry.w3 || lid == entry.vloc { hit = true; break; }
            }
            if !hit { f.packed_f32x4[out] = entry; out += 1; }
        }
        f.packed_f32x4_len = out;
    }
}
fn br(g: Generator&, f: const Fn&, value: u8, depth: u32) { opIndex(g, value, f.depth - depth); }

fn local(g: Generator&, f: const Fn&, ty: ValType) -> u32 {
    let id = (g.s.locals.len - f.locals_base) as u32;
    g.s.locals.push(ty);
    return id;
}
fn local32(g: Generator&, f: const Fn&) -> u32 { return local(g, f, VT_i32); }
fn localType(g: const Generator&, f: const Fn&, id: u32) -> ValType {
    if isShadowWord(id) {
        let shadow = g.s.v128_shadows[shadowIndex(id)];
        if shadow.is_wide {
            if shadow.is_float { return VT_f64; }
            return VT_i64;
        }
        if shadow.is_float { return VT_f32; }
        return VT_i32;
    }
    return g.s.locals[f.locals_base + id];
}
fn localCount(g: const Generator&, f: const Fn&) -> u32 { return (g.s.locals.len - f.locals_base) as u32; }
fn tagOf(g: const Generator&, ty: Ty) -> squid_direct_types::Tag { return g.types.node(ty).tag; }
fn unitVal() -> Val { return Val { ty: squid_direct_types::unit }; }
fn neverVal() -> Val { return Val { ty: squid_direct_types::never }; }
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
    if error != squid_direct_types::Error.none { return 0, g.typeFailure(g.units[f.unit - 1], id); }
    return words.len as u32, squid_direct_types::Error.none;
}
fn w(g: const Generator&, value: Val, at: i64) -> u32 { return g.s.words[value.start + at]; }

fn bindPut(g: Generator&, f: Fn&, binding: u32, value: Val) {
    g.s.vals.push(value);
    squid_support_zigmap::put(g.s.map_pool, f.bindings, binding, (g.s.vals.len - 1) as u32);
}
fn bindGet(g: const Generator&, f: const Fn&, binding: u32) -> Val, bool {
    let at, present = squid_support_zigmap::get(g.s.map_pool, f.bindings, binding);
    if !present { return Val {}, false; }
    return g.s.vals[at], true;
}
fn polyKey(f: const Fn&, binding: u32) -> u64 { return squid_direct_emit::key64(f.serial, binding); }

fn fresh(g: Generator&, f: const Fn&, ty: Ty, id: u32) -> Val, Error {
    if ty == squid_direct_types::u32_ || ty == squid_direct_types::boolean {
        let start = g.s.words.len as u32;
        let base_local = (g.s.locals.len - f.locals_base) as u32;
        g.s.locals.push(squid_direct_writer::VT_i32);
        g.s.words.push(base_local);
        return Val { ty, start, 1 }, squid_direct_types::Error.none;
    }
    if ty == squid_direct_types::f32_ {
        let start = g.s.words.len as u32;
        let base_local = (g.s.locals.len - f.locals_base) as u32;
        g.s.locals.push(squid_direct_writer::VT_f32);
        g.s.words.push(base_local);
        return Val { ty, start, 1 }, squid_direct_types::Error.none;
    }
    if ty == squid_direct_types::unit { return Val { ty, 0, 0 }, squid_direct_types::Error.none; }
    let words, error = g.types.layout(ty);
    if error != squid_direct_types::Error.none { return Val {}, g.typeFailure(g.units[f.unit - 1], id); }
    let n = words.len;
    if n == 0 { return Val { ty, 0, 0 }, squid_direct_types::Error.none; }
    let start = g.s.words.len as u32;
    let base_local = (g.s.locals.len - f.locals_base) as u32;
    if n == 1 {
        g.s.locals.push(words[0]);
        g.s.words.push(base_local);
        return Val { ty, start, 1 }, squid_direct_types::Error.none;
    }
    g.s.locals.append(words);
    for i in 0..n { g.s.words.push(base_local + (i as u32)); }
    return Val { ty, start, n as u32 }, squid_direct_types::Error.none;
}
fn lower(g: Generator&, f: Fn&, ty: TId, id: u32) -> Ty, Error {
    if ty >= squid_check_types::unit && ty <= squid_check_types::never {
        return squid_direct_types::lowerBuiltin(ty), squid_direct_types::Error.none;
    }
    let m .= g.units[f.unit - 1];
    let lowered, error = g.types.lower(m, ty, f.env);
    if error == squid_direct_types::Error.none { return lowered, squid_direct_types::Error.none; }
    // Values refined since the instance began may now decide the enclosing
    // body's obligations (a collection's element).
    let body .= enclosingBody(g, f);
    if body {
        let before = f.env.count;
        let solved = g.solveObligationsPublic(m, body.scheme.obligations, f.env);
        if solved != squid_direct_types::Error.none { return 0, solved; }
        if f.env.count != before {
            let found, error = g.types.lower(m, ty, f.env);
            if error == squid_direct_types::Error.none { g.dropFailure(); return found, squid_direct_types::Error.none; }
        }
    }
    // Variables no use can reach take Unit, consistently for the rest of this
    // instance: no value of such a part exists.
    if holesUnused(g, f, ty, 0) {
        defaultUnused(g, f, ty, 0);
        let found, error = g.types.lower(m, ty, f.env);
        if error == squid_direct_types::Error.none { g.dropFailure(); return found, squid_direct_types::Error.none; }
    }
    return 0, g.typeFailure(m, id);
}
// The named body this instance's code belongs to (a lambda's enclosing named
// instance), in this unit.
fn enclosingBody(g: const Generator&, f: const Fn&) -> const squid_check_core::Body? {
    if f.inlined_body_binding != 0 { return g.units[f.unit - 1].body(f.inlined_body_binding); }
    var key = g.s.instances[f.instance_id].key;
    for step in 0..64 {
        if key.unit != f.unit { return null; }
        if key.kind == squid_direct_emit::InstanceKind.lambda { key = g.s.instances[key.parent].key; }
        else if key.kind == squid_direct_emit::InstanceKind.named { return g.units[f.unit - 1].body(key.id); }
        else { return null; }
    }
    return null;
}
// The active AST body root for this instance (inlined named body, named body,
// or the lambda's own closure body — never walking up to an outer named body).
fn currentBodyRoot(g: const Generator&, f: const Fn&) -> u32 {
    if f.inlined_body_root != 0 { return f.inlined_body_root; }
    if f.inlined_body_binding != 0 {
        let body .= g.units[f.unit - 1].body(f.inlined_body_binding);
        if body { return body.root; }
        return 0;
    }
    let key = g.s.instances[f.instance_id].key;
    if key.unit != f.unit { return 0; }
    if key.kind == squid_direct_emit::InstanceKind.named {
        let body .= g.units[f.unit - 1].body(key.id);
        if body { return body.root; }
        return 0;
    }
    if key.kind == squid_direct_emit::InstanceKind.lambda {
        return g.units[f.unit - 1].closure(key.id).body;
    }
    return 0;
}
fn typeOf(g: Generator&, f: Fn&, id: u32) -> Ty, Error { return lower(g, f, g.units[f.unit - 1].typeOf(id), id); }
fn push(g: Generator&, value: Val) {
    for at in 0..(value.len as i64) { opIndex(g, OP_local_get, g.s.words[value.start + at]); }
}
// Pops a value of type `ty` from the operand stack into fresh locals.
fn pop(g: Generator&, f: const Fn&, ty: Ty, id: u32) -> Val, Error {
    let value, error = fresh(g, f, ty, id);
    if error != squid_direct_types::Error.none { return value, error; }
    var at = value.len as i64;
    while at != 0 {
        at -= 1;
        opIndex(g, OP_local_set, g.s.words[value.start + at]);
    }
    return value, squid_direct_types::Error.none;
}
fn copy(g: Generator&, f: const Fn&, from: Val, to: Val, id: u32) -> Error {
    if from.ty == squid_direct_types::never { return squid_direct_types::Error.none; }
    if from.len != to.len {
        g.failOpen(g.units[f.unit - 1], id);
        g.put("value layout mismatch (");
        g.put(squid_direct_types::tagName(tagOf(g, from.ty)));
        g.put(" of ");
        g.putNumber(from.len);
        g.put(" words into ");
        g.put(squid_direct_types::tagName(tagOf(g, to.ty)));
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
    return squid_direct_types::Error.none;
}

// An operand: if it diverges, so does the expression using it.
recursive fn expr(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let value, error = stmt(g, f, id);
    if error != squid_direct_types::Error.none { return value, error; }
    if value.ty == squid_direct_types::never { return value, squid_direct_types::Error.diverged; }
    return value, squid_direct_types::Error.none;
}
// A value that may diverge (statements, branches, bodies). An unsupported
// form is recorded and compiled as a trap, so one build reports every missing
// form; the compilation still fails.
recursive fn stmt(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    // Only the field's own reference node may see the field flag.
    let field_value = f.field_value;
    if id == 0 || m.node(id).tag != squid_check_core::Tag.reference { f.field_value = false; }
    let depth = f.depth;
    let s .= g.s;
    let labels = s.labels.len;
    let value, error = exprInner(g, f, id);
    if error != squid_direct_types::Error.none {
        if error == squid_direct_types::Error.unsupported { g.recordFailure(m, id); }
        // The rest is unreachable; close what the operand left open.
        while f.depth > depth { close(g, f); }
        s.labels.resize(labels);
        op(g, OP_unreachable_);
        f.field_value = field_value;
        return neverVal(), squid_direct_types::Error.none;
    }
    if value.ty != squid_direct_types::never && id != 0 {
        let rty = m.typeOf(id);
        if rty > squid_check_types::never { refine(g, f, rty, value.ty); }
    }
    f.field_value = field_value;
    return value, squid_direct_types::Error.none;
}
// Binds the variables of Core type `ty` that `actual` determines.
fn refine(g: Generator&, f: Fn&, ty: TId, actual: Ty) {
    if ty <= squid_check_types::never { return; }
    if g.types.isNoVars(f.unit, ty) { return; }
    g.types.match_(g.units[f.unit - 1], ty, actual, f.env);
}
recursive fn exprInner(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    // Node zero is an absent value, such as a bare `return ()`.
    let elide_f32_nan = id != 0 && f.elide_f32_nan_node == id;
    f.elide_f32_nan_node = 0;
    if id == 0 { return unitVal(), squid_direct_types::Error.none; }
    let m .= g.units[f.unit - 1];
    let n = m.node(id);
    match n.tag {
        constant => { return constant(g, f, id, n.a, true, n.b); },
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
            let children = m.children(id);
            let saved_skip = f.skip_fill_len;
            scanDeadFills(g, f, m, children);
            var last = unitVal();
            for child in children {
                let value, error = stmt(g, f, child);
                if error != squid_direct_types::Error.none { f.skip_fill_len = saved_skip; return value, error; }
                last = value;
            }
            f.skip_fill_len = saved_skip;
            if last.ty == squid_direct_types::never { return last, squid_direct_types::Error.none; }
            return unitVal(), squid_direct_types::Error.none;
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
            emitPanicTrap(g, f, id);
            op(g, OP_unreachable_);
            return neverVal(), squid_direct_types::Error.none;
        },
        spark => { return sparkNode(g, f, id); },
        flat_op => { return flatOpNode(g, f, id); },
        _ => {
            g.failOpen(m, id);
            g.put(squid_direct_emit::nodeTagName(n.tag));
            g.put(" expressions are not supported yet");
            return neverVal(), g.failClose();
        },
    }
}
fn withCellType(g: const Generator&, f: const Fn&, binding: u32) -> Ty, bool {
    let val, present = squid_support_zigmap::get(g.s.map_pool, f.with_cells, binding);
    return val, present && val != 0;
}
fn readBindingVal(g: Generator&, f: Fn&, binding: u32, id: u32) -> Val, bool, Error {
    let bound, present = bindGet(g, f, binding);
    if !present { return neverVal(), false, squid_direct_types::Error.none; }
    let elem_ty, is_cell = withCellType(g, f, binding);
    if !is_cell { return bound, true, squid_direct_types::Error.none; }
    let loaded, error = readFlat(g, f, w(g, bound, 0), 0, elem_ty, id);
    return loaded, true, error;
}
fn writeWithCell(g: Generator&, f: Fn&, cell_addr: u32, elem_ty: Ty, value: Val, id: u32) -> Error {
    let noted = noteStore(g, f, value);
    if noted != squid_direct_types::Error.none { return noted; }
    let bytes, berr = g.types.flatBytes(elem_ty);
    if berr != squid_direct_types::Error.none { return berr; }
    if bytes == 0 { return squid_direct_types::Error.none; }
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
    let rhs_tag = m.node(n.b).tag;
    var deferred = false;
    match rhs_tag {
        closure, constructor_function, primitive_function, reference => { deferred = true; },
        // A pure partial application, rebuilt at each use's types.
        call => { deferred = partialCall(g, f, n.b); },
        apply => { deferred = partialApply(g, f, n.b); },
        _ => {},
    }
    if deferred && n.c < 2 && m.binding(n.a).scheme.variables.len != 0 {
        g.s.polymorphic.put(polyKey(f, n.a), n.b);
        return unitVal(), squid_direct_types::Error.none;
    }
    var value = neverVal();
    var has_grown = false;
    var has_direct = false;
    if n.c < 2 && m.binding(n.a).scheme.variables.len == 0 && !g.runtime_().has_fork && f.direct_arrays_len < 16 && f.tco_inhibit == 0 && !bindingCaptured(g, f, n.a) {
        if rhs_tag == squid_check_core::Tag.array || (rhs_tag == squid_check_core::Tag.array_op && m.arrayOperation(n.b) == squid_backend_collection_ops::Op.fill) {
            let direct_val, ok_direct, derr = tryEmitDirectLocalArray(g, f, n.a, n.b, id);
            if derr != squid_direct_types::Error.none { return direct_val, derr; }
            if ok_direct {
                value = direct_val;
                has_direct = true;
            }
        }
    }
    if !has_direct && rhs_tag == squid_check_core::Tag.array_op {
        let grown, ok_grown, error = linearAppend(g, f, n.b);
        if error != squid_direct_types::Error.none { return grown, error; }
        value = grown;
        has_grown = ok_grown;
    }
    var had_noop = false;
    if !has_grown && !has_direct {
        // A generalized local value is computed once: its uses decide the one
        // type it is computed at.
        let bnd = m.binding(n.a);
        if bnd.scheme.variables.len != 0 {
            let typed = typeByUses(g, f, n.a, n.b);
            if typed != squid_direct_types::Error.none { return neverVal(), typed; }
            // Nothing reads an unused local, so its open types are Unit.
            if uses(g, f, n.a) == 0 { defaultUnused(g, f, bnd.ty, 0); }
        }
        if n.c < 2 && isFloatOrVecCoreType(m, bnd.ty) && bindingIgnoresNanPayload(g, f, n.a) {
            f.elide_f32_nan_node = n.b;
        }
        let prev_noop = f.boxed_noop_alias;
        f.boxed_noop_alias = false;
        let evaluated, eval_err = stmt(g, f, n.b);
        had_noop = f.boxed_noop_alias;
        f.boxed_noop_alias = prev_noop;
        f.elide_f32_nan_node = 0;
        if eval_err != squid_direct_types::Error.none { return evaluated, eval_err; }
        value = evaluated;
    }
    if n.c >= 2 {
        let outer_b = n.c - 2;
        let cell_val, has_cell = bindGet(g, f, outer_b);
        let elem_ty, is_cell = withCellType(g, f, outer_b);
        if has_cell && is_cell && value.ty != squid_direct_types::never {
            refine(g, f, m.binding(n.a).ty, value.ty);
            let werr = writeWithCell(g, f, w(g, cell_val, 0), elem_ty, value, id);
            if werr != squid_direct_types::Error.none { return neverVal(), werr; }
            bindPut(g, f, n.a, cell_val);
            squid_support_zigmap::put(g.s.map_pool, f.with_cells, n.a, elem_ty);
            return unitVal(), squid_direct_types::Error.none;
        }
    }
    if has_grown && value.ty != squid_direct_types::never {
        squid_support_zigmap::put(g.s.map_pool, f.unique_owned, n.a, f.loop_depth + 1);
    }
    if !has_grown && value.ty != squid_direct_types::never {
        let bty = m.binding(n.a).ty;
        if bty > squid_check_types::never { refine(g, f, bty, value.ty); }
        if value.ty > squid_direct_types::never {
            if !had_noop && isFreshBoxedRhs(g, f, m, n.b, value.ty) {
                let pre_flag: u32 = if rhsBoxedPreexisting(g, f, m, n.b) { UNIQUE_BOXED_PREEXISTING } else { 0 };
                squid_support_zigmap::put(g.s.map_pool, f.unique_boxed, n.a, (f.loop_depth + 1) | pre_flag);
            }
            if isFreshOwnedArrayRhs(g, f, m, n.b, value.ty) {
                squid_support_zigmap::put(g.s.map_pool, f.unique_owned, n.a, f.loop_depth + 1);
            }
        } else if n.c == 0 && value.ty == squid_direct_types::f32_ && isBoundedFiniteF32(g, f, m, n.b) {
            recordFiniteF32(f, n.a);
        }
    }
    bindPut(g, f, n.a, value);
    if !has_direct && n.c < 2 && value.ty != squid_direct_types::never {
        var src_da: i64 = -1;
        if rhs_tag == squid_check_core::Tag.reference {
            src_da = findDirectArray(f, localRef(m, n.b));
        } else if rhs_tag == squid_check_core::Tag.update {
            let uinfo = m.updateInfo(n.b);
            src_da = findDirectArray(f, localRef(m, uinfo.root));
        }
        if src_da >= 0 {
            let da = f.direct_arrays[src_da];
            recordDirectArray(f, n.a, da.slot_local, da.base, da.len_local, da.length, da.elem_ty, da.step, da.scalar_packed, da.pack_lo, da.pack_hi);
        }
    }
    if f.indirect_bound_binding != 0 && n.a == f.indirect_bound_binding && tagOf(g, value.ty) == squid_direct_types::Tag.u32_ {
        recordCheckedBound(f, w(g, value, 0), f.indirect_bound_len);
    }
    if value.ty == squid_direct_types::never { return value, squid_direct_types::Error.none; }
    return unitVal(), squid_direct_types::Error.none;
}
fn bindingCaptured(g: Generator&, f: const Fn&, binding: u32) -> bool {
    for ui in 0..f.inlined_uncaptured_len {
        if f.inlined_uncaptured[ui] == binding { return false; }
    }
    let m .= g.units[f.unit - 1];
    let uid = (m.unit - 1) as i64;
    while g.s.captured_base.len < g.units.len { g.s.captured_base.push(0xffffffff); }
    var base = g.s.captured_base[uid];
    if base == 0xffffffff {
        base = g.s.captured_vals.len as u32;
        g.s.captured_base[uid] = base;
        squid_direct_emit::growZerosU8(g.s.captured_vals, m.bindings.len);
        for closure in m.closures {
            for captured in m.extra[closure.captures.start..closure.captures.start + closure.captures.len] {
                if (captured as i64) < m.bindings.len { g.s.captured_vals[(base as i64) + (captured as i64)] = 1; }
            }
        }
    }
    return g.s.captured_vals[(base as i64) + (binding as i64)] != 0;
}
let UNIQUE_BOXED_PREEXISTING: u32 = 0x80000000;
fn isUniqueBoxedAt(g: const Generator&, f: const Fn&, binding: u32, loop_depth: u32) -> bool {
    let val, present = squid_support_zigmap::get(g.s.map_pool, f.unique_boxed, binding);
    return present && (val & ~UNIQUE_BOXED_PREEXISTING) == loop_depth + 1;
}
fn isUniqueBoxed(g: const Generator&, f: const Fn&, binding: u32) -> bool {
    return isUniqueBoxedAt(g, f, binding, f.loop_depth);
}
fn isUniqueBoxedPreexisting(g: const Generator&, f: const Fn&, binding: u32) -> bool {
    let val, present = squid_support_zigmap::get(g.s.map_pool, f.unique_boxed, binding);
    return present && (val & UNIQUE_BOXED_PREEXISTING) != 0;
}
fn rhsBoxedPreexisting(g: const Generator&, f: const Fn&, m: const Module&, id: u32) -> bool {
    if id == 0 { return false; }
    let n = m.node(id);
    match n.tag {
        reference => {
            let local_id = localRef(m, id);
            return local_id != 0 && isUniqueBoxedPreexisting(g, f, local_id);
        },
        update => {
            let rb = localRef(m, m.updateInfo(id).root);
            return rb != 0 && isUniqueBoxedPreexisting(g, f, rb);
        },
        match_ => {
            let inputs = m.matchInputs(id);
            if inputs.len == 1 {
                let mb = localRef(m, inputs[0]);
                if mb != 0 && isUniqueBoxedPreexisting(g, f, mb) { return true; }
            }
            return f.reuse_preexisting;
        },
        suite, block_, if_value => { return f.reuse_preexisting; },
        _ => { return false; },
    }
}
fn isOpaqueOutsideUnit(g: const Generator&, m: const Module&, ty: Ty) -> bool {
    if tagOf(g, ty) != squid_direct_types::Tag.nominal { return false; }
    let nom_id = g.types.nominalIdentity(ty);
    if nom_id.unit == 0 || nom_id.unit == 0xffffffff || nom_id.unit == m.unit || !g.hasUnit(nom_id.unit) { return false; }
    let owner .= g.units[nom_id.unit - 1];
    for nom in owner.nominals {
        if nom.identity.unit == nom_id.unit && nom.identity.decl == nom_id.decl {
            return nom.is_opaque;
        }
    }
    return false;
}
fn recordTrapEntry(g: Generator&, kind: u8, unit: u32, sp_start: u32, sp_end: u32, message: Chars) -> u32 {
    if g.s.replaying {
        for entry, i in g.s.traps {
            if entry.kind == kind && entry.unit == unit && entry.start == sp_start && entry.end == sp_end && (entry.message_len as i64) == message.len {
                let ms = entry.message_start as i64;
                if g.s.trap_text[ms..ms + (entry.message_len as i64)] == message {
                    return (i + 1) as u32;
                }
            }
        }
    }
    let msg_start = g.s.trap_text.len as u32;
    g.s.trap_text.append(message);
    let msg_len = (g.s.trap_text.len as u32) - msg_start;
    g.s.traps.push(squid_direct_emit::TrapEntry { kind: kind, unit: unit, start: sp_start, end: sp_end, message_start: msg_start, message_len: msg_len });
    return g.s.traps.len as u32;
}
fn emitTrapSite(g: Generator&, f: Fn&, kind: u8, id: u32, message: Chars) {
    if !g.module.has_memory {
        if g.s.parallel_readonly { g.s.parallel_aborted = true; return; }
        g.module.has_memory = true;
        g.module.memory_pages = 1;
        g.module.memory_max_pages = 1;
    }
    var sp_start: u32 = 0;
    var sp_end: u32 = 0;
    if squid_direct_writer::testModeEnabled() {
        let sp = squid_direct_emit::spanOf(g.units[f.unit - 1], id);
        sp_start = sp.start;
        sp_end = sp.end;
    }
    if g.s.parallel_readonly {
        let ev_idx = squid_direct_emit::recordParallelTrap(kind, g.units[f.unit - 1].unit, sp_start, sp_end, message);
        i32Const(g, squid_direct_runtime::trap_site_offset);
        op(g, OP_i32_const);
        squid_direct_emit::recordParallelTrapPatch(g.s.code.len as u32, ev_idx);
        op(g, 0);
        op(g, OP_i32_store);
        uleb(g, 2);
        uleb(g, 0);
        return;
    }
    let trap_id = recordTrapEntry(g, kind, g.units[f.unit - 1].unit, sp_start, sp_end, message);
    i32Const(g, squid_direct_runtime::trap_site_offset);
    i32Const(g, trap_id);
    op(g, OP_i32_store);
    uleb(g, 2);
    uleb(g, 0);
}
fn emitPanicTrap(g: Generator&, f: Fn&, id: u32) {
    if !g.module.has_memory {
        if g.s.parallel_readonly { g.s.parallel_aborted = true; return; }
        g.module.has_memory = true;
        g.module.memory_pages = 1;
        g.module.memory_max_pages = 1;
    }
    var sp_start: u32 = 0;
    var sp_end: u32 = 0;
    if squid_direct_writer::testModeEnabled() {
        let sp = squid_direct_emit::spanOf(g.units[f.unit - 1], id);
        sp_start = sp.start;
        sp_end = sp.end;
    }
    if g.s.parallel_readonly {
        let ev_idx = squid_direct_emit::recordParallelTrap(1, g.units[f.unit - 1].unit, sp_start, sp_end, g.units[f.unit - 1].panicMessage(id));
        i32Const(g, squid_direct_runtime::trap_site_offset);
        op(g, OP_i32_const);
        squid_direct_emit::recordParallelTrapPatch(g.s.code.len as u32, ev_idx);
        op(g, 0);
        op(g, OP_i32_store);
        uleb(g, 2);
        uleb(g, 0);
        return;
    }
    let trap_id = recordTrapEntry(g, 1, g.units[f.unit - 1].unit, sp_start, sp_end, g.units[f.unit - 1].panicMessage(id));
    i32Const(g, squid_direct_runtime::trap_site_offset);
    i32Const(g, trap_id);
    op(g, OP_i32_store);
    uleb(g, 2);
    uleb(g, 0);
}
fn isUniqueOwnedAt(g: const Generator&, f: const Fn&, binding: u32, loop_depth: u32) -> bool {
    let val, present = squid_support_zigmap::get(g.s.map_pool, f.unique_owned, binding);
    return present && val == loop_depth + 1;
}
fn isUniqueOwned(g: const Generator&, f: const Fn&, binding: u32) -> bool {
    return isUniqueOwnedAt(g, f, binding, f.loop_depth);
}
fn incOwnedMap(g: Generator&, map: squid_support_zigmap::Map&, b: u32) {
    if b == 0 { return; }
    let prev, ok = squid_support_zigmap::get(g.s.map_pool, map, b);
    var next: u32 = 1;
    if ok { next = prev + 1; }
    squid_support_zigmap::put(g.s.map_pool, map, b, next);
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
            let is_len = m.arrayOperation(id) == squid_backend_collection_ops::Op.length && ch.len == 1;
            for child in ch { scanOwnedUses(g, f, m, child, is_len, overflow, left); }
        },
        storage => {
            let ch = m.children(id);
            let op_kind, ok = squid_check_storage_ops::opFromCode(n.c);
            let is_len = ok == squid_error::Error.none && op_kind == squid_check_storage_ops::Op.length && ch.len == 1;
            for child in ch { scanOwnedUses(g, f, m, child, is_len, overflow, left); }
        },
        update => {
            let change = m.updateInfo(id);
            scanOwnedUses(g, f, m, change.root, false, overflow, left);
            scanOwnedUses(g, f, m, change.value, false, overflow, left);
            for sel in m.updateSelectors(id) {
                if sel.kind == squid_check_core::UpdateKind.index {
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
        let root = currentBodyRoot(g, f);
        if root == 0 {
            squid_support_zigmap::put(g.s.map_pool, f.owned_flows, 0xffffffff, 1);
            return false;
        }
        var overflow = false;
        var budget: i64 = 2048;
        scanOwnedUses(g, f, m, root, false, overflow, budget);
        if overflow {
            squid_support_zigmap::put(g.s.map_pool, f.owned_flows, 0xffffffff, 1);
            return false;
        }
    }
    let bad, present = squid_support_zigmap::get(g.s.map_pool, f.owned_flows, 0xffffffff);
    return !(present && bad != 0);
}
fn ownedRefUses(g: Generator&, f: Fn&, binding: u32) -> u32 {
    if !ensureOwnedUses(g, f) { return 0xffffffff; }
    let v, ok = squid_support_zigmap::get(g.s.map_pool, f.owned_uses, binding);
    if ok { return v; }
    return 0;
}
fn ownedFlowUses(g: Generator&, f: Fn&, binding: u32) -> u32 {
    if !ensureOwnedUses(g, f) { return 0xffffffff; }
    let v, ok = squid_support_zigmap::get(g.s.map_pool, f.owned_flows, binding);
    if ok { return v; }
    return 0;
}
fn ownedTotalUses(g: Generator&, f: Fn&, binding: u32) -> u32 {
    let r = ownedRefUses(g, f, binding);
    let fl = ownedFlowUses(g, f, binding);
    if r == 0xffffffff || fl == 0xffffffff { return 0xffffffff; }
    return r + fl;
}
recursive fn isFreshOwnedArrayRhs(g: Generator&, f: Fn&, m: const Module&, id: u32, ty: Ty) -> bool {
    if id == 0 || tagOf(g, ty) != squid_direct_types::Tag.array { return false; }
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
            let op_kind, ok = squid_check_storage_ops::opFromCode(n.c);
            if ok != squid_error::Error.none { return false; }
            if op_kind == squid_check_storage_ops::Op.copy || op_kind == squid_check_storage_ops::Op.with_capacity { return true; }
            if op_kind == squid_check_storage_ops::Op.push || op_kind == squid_check_storage_ops::Op.reserve || op_kind == squid_check_storage_ops::Op.extend {
                let ch = m.children(id);
                return ch.len == 2 && isFreshOwnedArrayRhs(g, f, m, ch[0], ty);
            }
            return false;
        },
        reference => {
            let local_id = localRef(m, id);
            return local_id != 0 && isUniqueOwned(g, f, local_id) && ownedTotalUses(g, f, local_id) == 1 && !bindingCaptured(g, f, local_id);
        },
        call => {
            let target = g.resolve(m, m.call(id).target);
            if !g.hasUnit(target.unit) { return false; }
            let tm .= g.units[target.unit - 1];
            let tbody .= tm.body(target.binding);
            if !tbody || !tbody.is_function || tbody.exported { return false; }
            let ret = returnedFreshArrayExpr(tm, tbody.root);
            return isFreshOwnedArrayNode(g, tm, ret, 1);
        },
        _ => { return false; },
    }
}

// Conservative per-body analysis: marks every local F32 binding whose NaN
// payload could ever be observed (outside canonical F32 consumers or pure
// register propagation). Bindings NOT marked observed can elide per-op NaN
// canonicalization while preserving bit-exact 0x7fc00000 semantics everywhere.
fn markNanObserved(g: Generator&, f: Fn&, b: u32) {
    if b != 0 { squid_support_zigmap::put(g.s.map_pool, f.nan_observed, b, 1); }
}
fn isNanObserved(g: const Generator&, f: const Fn&, b: u32) -> bool {
    let v, ok = squid_support_zigmap::get(g.s.map_pool, f.nan_observed, b);
    return ok && v != 0;
}
fn isFloatOrVecCoreType(m: const Module&, ty: TId) -> bool {
    if ty == squid_check_types::f32_type || ty == squid_check_types::f64_type { return true; }
    if ty <= squid_check_types::never { return false; }
    let n = m.types.node(ty);
    if n.tag == squid_check_types::Tag.floating32 || n.tag == squid_check_types::Tag.floating64 { return true; }
    if n.tag == squid_check_types::Tag.product {
        if n.b == 2 {
            return m.types.extra[n.a] == squid_check_types::f64_type && m.types.extra[n.a + 1] == squid_check_types::f64_type;
        }
        if n.b == 4 {
            for lane in 0..4 {
                if m.types.extra[n.a + lane] != squid_check_types::f32_type { return false; }
            }
            return true;
        }
    }
    return false;
}
fn callIsCanonicalFloatConsumer(g: const Generator&, m: const Module&, call_id: u32, allow_body: bool) -> bool {
    let info = m.call(call_id);
    let arguments = info.arguments;
    if arguments.len == 0 || arguments.len > 4 { return false; }
    let target = g.resolve(m, info.target);
    if !g.hasUnit(target.unit) { return false; }
    let resolved = followAliasTarget(g, target);
    if !g.hasUnit(resolved.unit) { return false; }
    let rtm .= g.units[resolved.unit - 1];
    let palias, has_palias = primitiveAlias(rtm, resolved.binding);
    if has_palias {
        let pinfo = rtm.primitive(palias);
        if pinfo.kind == squid_check_core::PrimitiveKind.scalar && (pinfo.arity as i64) == arguments.len && isCanonicalF32Consumer(pinfo.op) {
            let atag = m.types.node(m.typeOf(arguments[0])).tag;
            if atag == squid_check_types::Tag.floating32 || atag == squid_check_types::Tag.floating64 { return true; }
        }
    }
    let body .= rtm.body(resolved.binding);
    if !body || !body.is_function || rtm.bodyParameters(body).len != arguments.len { return false; }
    let root = forwardingRoot(rtm, body.root);
    let node = rtm.node(root);
    if node.tag == squid_check_core::Tag.scalar && node.c == 0 &&
        (isF32x4CoreExpr(rtm, node.a) || isF64x2CoreExpr(rtm, node.a)) &&
        (isCanonicalF32Consumer(node.op) || canonicalV128Producer(node.op)) &&
        simdForwardingOperands(rtm, body, node.a, node.b) {
        return true;
    }
    if allow_body && !body.exported {
        var budget: i64 = 96;
        return bodyOnlyCanonicalFloatOps(g, rtm, body.root, false, budget);
    }
    return false;
}
// True when `id` contains only pure canonical float/SIMD arithmetic/rounding/
// comparison/conversion operations and never exposes any reference's raw NaN
// bits (no `bits`, memory stores, closures, or pass-through returns).
recursive fn bodyOnlyCanonicalFloatOps(g: const Generator&, m: const Module&, id: u32, safe_ref: bool, left: i64&) -> bool {
    if id == 0 { return true; }
    if left <= 0 { return false; }
    left -= 1;
    let n = m.node(id);
    match n.tag {
        constant => { return true; },
        reference => { return safe_ref; },
        suite, block_ => {
            for child in m.children(id) {
                if !bodyOnlyCanonicalFloatOps(g, m, child, false, left) { return false; }
            }
            return true;
        },
        return_ => { return bodyOnlyCanonicalFloatOps(g, m, n.a, false, left); },
        bind => { return n.c < 2 && bodyOnlyCanonicalFloatOps(g, m, n.b, false, left); },
        product => {
            if !safe_ref { return false; }
            for child in m.children(id) {
                if !bodyOnlyCanonicalFloatOps(g, m, child, true, left) { return false; }
            }
            return true;
        },
        scalar => {
            let t = m.types.node(m.typeOf(n.a)).tag;
            let is_f = t == squid_check_types::Tag.floating32 || t == squid_check_types::Tag.floating64;
            let is_v = isF32x4CoreExpr(m, n.a) || isF64x2CoreExpr(m, n.a);
            let ok = (is_f && isCanonicalF32Consumer(n.op)) || (is_v && (isCanonicalF32Consumer(n.op) || canonicalV128Producer(n.op)));
            if !ok { return false; }
            return bodyOnlyCanonicalFloatOps(g, m, n.a, true, left) && (n.b == 0 || bodyOnlyCanonicalFloatOps(g, m, n.b, true, left));
        },
        associated => {
            let t = m.types.node(m.typeOf(n.a)).tag;
            let is_f = t == squid_check_types::Tag.floating32 || t == squid_check_types::Tag.floating64;
            if n.op == squid_check_core::Op.none || !is_f || !isCanonicalF32Consumer(n.op) { return false; }
            return bodyOnlyCanonicalFloatOps(g, m, n.a, true, left) && (n.b == 0 || bodyOnlyCanonicalFloatOps(g, m, n.b, true, left));
        },
        call => {
            if !callIsCanonicalFloatConsumer(g, m, id, false) { return false; }
            for arg in m.call(id).arguments {
                if !bodyOnlyCanonicalFloatOps(g, m, arg, true, left) { return false; }
            }
            return true;
        },
        _ => { return false; },
    }
}
fn addNanEdge(src_arr: u32[512]&, dst_arr: u32[512]&, len: i64&, src: u32, dst: u32) -> bool {
    if src == 0 || dst == 0 || src == dst { return true; }
    if len >= 512 { return false; }
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
    edge_src: u32[512]&,
    edge_dst: u32[512]&,
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
            let t = m.types.node(m.typeOf(n.a)).tag;
            let is_f = t == squid_check_types::Tag.floating32 || t == squid_check_types::Tag.floating64;
            let is_v = isF32x4CoreExpr(m, n.a) || isF64x2CoreExpr(m, n.a);
            let consumer = (is_f && isCanonicalF32Consumer(n.op)) || (is_v && (isCanonicalF32Consumer(n.op) || canonicalV128Producer(n.op)));
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
            if n.a != 0 && m.node(n.a).tag == squid_check_core::Tag.loop_ {
                let carries = m.loopCarries(n.a);
                for child, ci in vals {
                    let vb = localRef(m, child);
                    if vb != 0 && ci < carries.len {
                        if n.op == squid_check_core::Op.continue_ {
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
        product => {
            for child in m.children(id) {
                scanNanUses(g, f, m, child, safe_ref, edge_src, edge_dst, edge_len, overflow, left);
            }
        },
        record, array, array_op, storage => {
            for child in m.children(id) {
                scanNanUses(g, f, m, child, false, edge_src, edge_dst, edge_len, overflow, left);
            }
        },
        update => {
            let change = m.updateInfo(id);
            scanNanUses(g, f, m, change.root, false, edge_src, edge_dst, edge_len, overflow, left);
            scanNanUses(g, f, m, change.value, false, edge_src, edge_dst, edge_len, overflow, left);
            for sel in m.updateSelectors(id) {
                if sel.kind == squid_check_core::UpdateKind.index {
                    scanNanUses(g, f, m, sel.index, false, edge_src, edge_dst, edge_len, overflow, left);
                }
            }
        },
        associated => {
            let t = m.types.node(m.typeOf(n.a)).tag;
            let is_f = t == squid_check_types::Tag.floating32 || t == squid_check_types::Tag.floating64;
            let consumer = n.op != squid_check_core::Op.none && is_f && isCanonicalF32Consumer(n.op);
            scanNanUses(g, f, m, n.a, consumer, edge_src, edge_dst, edge_len, overflow, left);
            scanNanUses(g, f, m, n.b, consumer, edge_src, edge_dst, edge_len, overflow, left);
        },
        logical, apply => {
            scanNanUses(g, f, m, n.a, false, edge_src, edge_dst, edge_len, overflow, left);
            scanNanUses(g, f, m, n.b, false, edge_src, edge_dst, edge_len, overflow, left);
        },
        call => {
            let consumer = callIsCanonicalFloatConsumer(g, m, id, true);
            for arg in m.call(id).arguments {
                scanNanUses(g, f, m, arg, consumer, edge_src, edge_dst, edge_len, overflow, left);
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
        let root = currentBodyRoot(g, f);
        if root == 0 {
            // Sentinel 0xffffffff marks analysis unavailable (conservative).
            markNanObserved(g, f, 0xffffffff);
            return false;
        }
        var edge_src: u32[512] = [0; 512];
        var edge_dst: u32[512] = [0; 512];
        var edge_len: i64 = 0;
        var overflow = false;
        var budget: i64 = 4096;
        scanNanUses(g, f, m, root, false, edge_src, edge_dst, edge_len, overflow, budget);
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
recursive fn nodeReturnsBinding(m: const Module&, id: u32, binding: u32, depth: i64) -> bool {
    if id == 0 || binding == 0 || depth > 16 { return false; }
    let n = m.node(id);
    match n.tag {
        reference => { return localRef(m, id) == binding; },
        suite => {
            let items = m.children(id);
            if items.len == 0 { return false; }
            return nodeReturnsBinding(m, items[items.len - 1], binding, depth + 1);
        },
        block_ => {
            let items = m.children(id);
            if items.len == 0 { return false; }
            let ln = m.node(items[items.len - 1]);
            return ln.tag == squid_check_core::Tag.return_ && ln.b == id && nodeReturnsBinding(m, ln.a, binding, depth + 1);
        },
        update => {
            let uinfo = m.updateInfo(id);
            return nodeReturnsBinding(m, uinfo.root, binding, depth + 1) && updateCanNoopAlias(m, id, depth + 1);
        },
        _ => { return false; },
    }
}
recursive fn updateCanNoopAlias(m: const Module&, id: u32, depth: i64) -> bool {
    if depth > 16 { return true; }
    let uinfo = m.updateInfo(id);
    for sel in m.updateSelectors(id) {
        if sel.kind == squid_check_core::UpdateKind.index { return true; }
    }
    if uinfo.self_binding != 0 && uinfo.value != 0 {
        if nodeReturnsBinding(m, uinfo.value, uinfo.self_binding, depth + 1) { return true; }
    }
    return false;
}
fn isFreshBoxedRhs(g: Generator&, f: const Fn&, m: const Module&, id: u32, ty: Ty) -> bool {
    if id == 0 { return false; }
    let boxed, error = g.types.boxed(ty);
    if error != squid_direct_types::Error.none || !boxed { return false; }
    let n = m.node(id);
    match n.tag {
        construct, record => { return true; },
        update => {
            if m.updateSelectors(id).len != 0 || m.updatePath(id).len != 0 { return true; }
            return !updateCanNoopAlias(m, id, 0);
        },
        reference => {
            let local_id = localRef(m, id);
            return local_id != 0 && isUniqueBoxed(g, f, local_id) && uses(g, f, local_id) == 1 && !bindingCaptured(g, f, local_id);
        },
        suite, block_ => { return isFreshBoxedNode(m, id, 0); },
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
        construct, record => { return true; },
        update => { return !updateCanNoopAlias(m, id, 0); },
        suite => {
            let items = m.children(id);
            if items.len == 0 { return false; }
            return isFreshBoxedNode(m, items[items.len - 1], depth + 1);
        },
        block_ => {
            let items = m.children(id);
            if items.len == 0 { return false; }
            for i in 0..items.len - 1 {
                if m.node(items[i]).tag != squid_check_core::Tag.bind { return false; }
            }
            let ln = m.node(items[items.len - 1]);
            return ln.tag == squid_check_core::Tag.return_ && ln.b == id && ln.a != 0 && isFreshBoxedNode(m, ln.a, depth + 1);
        },
        if_value => { return isFreshBoxedNode(m, n.b, depth + 1) && isFreshBoxedNode(m, n.c, depth + 1); },
        match_ => {
            for arm in m.matchArms(id) { if !isFreshBoxedNode(m, arm.body, depth + 1) { return false; } }
            return true;
        },
        _ => { return false; },
    }
}
fn consumeReuseNode(f: Fn&, id: u32) -> bool {
    for i in 0..f.reuse_nodes_len {
        if f.reuse_nodes[i] == id {
            f.reuse_nodes[i] = 0;
            return true;
        }
    }
    return false;
}
recursive fn collectTailConstructs(
    m: const Module&,
    id: u32,
    allow_bind: bool,
    out: u32[4]&,
    out_len: i64&,
    depth: i64 = 0,
) -> bool {
    if id == 0 || depth > 8 { return true; }
    let n = m.node(id);
    match n.tag {
        construct => {
            if out_len >= 4 { return false; }
            out[out_len] = id;
            out_len += 1;
            return true;
        },
        suite => {
            let items = m.children(id);
            if items.len == 0 { return true; }
            return collectTailConstructs(m, items[items.len - 1], allow_bind, out, out_len, depth + 1);
        },
        return_ => {
            return collectTailConstructs(m, n.a, false, out, out_len, depth + 1);
        },
        block_ => {
            let items = m.children(id);
            if items.len == 0 { return true; }
            let ln = m.node(items[items.len - 1]);
            if ln.tag == squid_check_core::Tag.return_ && ln.b == id && ln.a != 0 {
                return collectTailConstructs(m, ln.a, false, out, out_len, depth + 1);
            }
            return true;
        },
        bind => {
            if allow_bind && n.c < 2 && n.b != 0 {
                return collectTailConstructs(m, n.b, false, out, out_len, depth + 1);
            }
            return true;
        },
        if_value => {
            return collectTailConstructs(m, n.b, false, out, out_len, depth + 1) &&
                collectTailConstructs(m, n.c, false, out, out_len, depth + 1);
        },
        if_stmt => {
            if !allow_bind { return true; }
            if n.c != 0 {
                return collectTailConstructs(m, n.b, true, out, out_len, depth + 1) &&
                    collectTailConstructs(m, n.c, true, out, out_len, depth + 1);
            }
            return collectTailConstructs(m, n.b, true, out, out_len, depth + 1);
        },
        _ => { return true; },
    }
}

fn constant(g: Generator&, f: Fn&, id: u32, bits: u32, literal:bool=false, high:u32=0) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let ty, error = typeOf(g, f, id);
    if error != squid_direct_types::Error.none { return neverVal(), error; }
    if literal && ty!=squid_direct_types::unit { squid_direct_relocations::operand(m.unit,id,g.s.code.len); }
    if ty == squid_direct_types::unit { return unitVal(), squid_direct_types::Error.none; }
    if !isScalarTag(tagOf(g, ty)) { return neverVal(), g.fail(m, id, "constant of a composite type"); }
    pushConstant(g, ty, bits, high);
    let value, err = pop(g, f, ty, id);
    if err == squid_direct_types::Error.none && ty == squid_direct_types::u32_ {
        if literal { recordConstU32(f, w(g, value, 0), bits, m.unit, id); }
        // Staging records its dependencies while evaluating the value.
        else { recordConstU32(f, w(g, value, 0), bits); }
    } else if err == squid_direct_types::Error.none && ty == squid_direct_types::u64_ {
        let v64 = (bits as u64) | ((high as u64) << 32);
        if literal { recordConstU64(f, w(g, value, 0), v64, m.unit, id); }
        else { recordConstU64(f, w(g, value, 0), v64); }
    }
    return value, err;
}

fn containsText(haystack: Chars, needle: Chars) -> bool {
    if needle.len > haystack.len { return false; }
    for at in 0..haystack.len - needle.len + 1 {
        if haystack[at..at + needle.len] == needle { return true; }
    }
    return false;
}
fn bindingKindName(kind: squid_reuse_principal_interface::Kind) -> Chars {
    match kind { const for <N, V> in variants<squid_reuse_principal_interface::Kind> { V => { return N; }, } }
}
recursive fn reference(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let value, error = referenceInner(g, f, id);
    if error != squid_direct_types::Error.unsupported { return value, error; }
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
        if rerr != squid_direct_types::Error.none { return neverVal(), rerr; }
        if present { return bound, squid_direct_types::Error.none; }
        let closure, generalized = g.s.polymorphic.get(polyKey(f, ref.binding));
        if generalized {
            // The closure is built in a copy of the environment that this
            // use's type refines.
            var env = f.env;
            let use_ty, error = typeOf(g, f, id);
            if error != squid_direct_types::Error.none { return neverVal(), error; }
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
    if binding.kind == squid_reuse_principal_interface::Kind.local || binding.kind == squid_reuse_principal_interface::Kind.parameter {
        return neverVal(), g.fail(m, id, "unbound local reference");
    }
    var holed = false;
    var ty, error = g.types.lower(m, m.typeOf(id), f.env);
    if error != squid_direct_types::Error.none {
        // Variables no use here determines may only sit inside function
        // types: such a function can never be called here.
        let partial_ty, error = g.types.lowerHoles(m, m.typeOf(id), f.env);
        if error != squid_direct_types::Error.none { return neverVal(), error; }
        if !holesOnlyInFunctions(g, partial_ty) { return neverVal(), g.typeFailure(m, id); }
        holed = true;
        ty = partial_ty;
    }
    // Holes no use can reach: variables the checker left ambiguous, or ones
    // this instance's key already left unused.
    let unused = holed && holesUnused(g, f, m.typeOf(id), 0);
    if holed && tagOf(g, ty) == squid_direct_types::Tag.function {
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
        if error != squid_direct_types::Error.none { return neverVal(), g.typeFailure(m, id); }
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
    if has_alias { g.recordInlined(target.unit, target.binding); return partial(g, f, squid_direct_emit::InstanceKind.primitive, target, ty, Vals {}, id); }
    let body .= tm.body(target.binding);
    if body {
        if body.is_function { return partial(g, f, squid_direct_emit::InstanceKind.partial, target, ty, Vals {}, id); }
        match tagOf(g, ty) {
            array, packed, seq => { return pool(g, f, target, ty, id); },
            _ => {},
        }
        // Inline non-exported scalar or nullary-constructor constants directly
        // instead of emitting a getter call on every read.
        if !body.exported && evidenceContext(g, f, target, id) == 0 && g.types.concrete(ty, 0) {
            let root = body.root;
            let rn = tm.node(root);
            if rn.tag == squid_check_core::Tag.constant {
                let ctag = tagOf(g, ty);
                if isScalarTag(ctag) {
                    g.recordInlined(target.unit, target.binding);
                    squid_direct_relocations::operand(target.unit, root, g.s.code.len);
                    pushConstant(g, ty, rn.a, rn.b);
                    let value, error = pop(g, f, ty, id);
                    if error == squid_direct_types::Error.none && ctag == squid_direct_types::Tag.u32_ {
                        recordConstU32(f, w(g, value, 0), rn.a, target.unit, root);
                    } else if error == squid_direct_types::Error.none && ctag == squid_direct_types::Tag.u64_ {
                        recordConstU64(f, w(g, value, 0), (rn.a as u64) | ((rn.b as u64) << 32), target.unit, root);
                    }
                    return value, error;
                }
            } else if rn.tag == squid_check_core::Tag.construct && rn.b == 0 {
                let boxed, berr = isBoxed(g, f, ty, id);
                let width, werr = layoutLen(g, f, ty, id);
                if berr == squid_direct_types::Error.none && !boxed && werr == squid_direct_types::Error.none && width == 1 {
                    let is_niche, null_tag, _, _, nerr = g.types.nullableNiche(ty);
                    if nerr == squid_direct_types::Error.none {
                        let ctor_tag = tm.constructor(rn.a).tag;
                        if is_niche && ctor_tag == null_tag {
                            g.recordInlined(target.unit, target.binding);
                            return valOf1(g, ty, constLocal(g, f, 0)), squid_direct_types::Error.none;
                        }
                        if !is_niche {
                            g.recordInlined(target.unit, target.binding);
                            let loc = constLocal(g, f, ctor_tag);
                            recordConstTag(f, loc, ctor_tag);
                            return valOf1(g, ty, loc), squid_direct_types::Error.none;
                        }
                    }
                }
            } else if f.inline_depth < 3 {
                let inlined, was_inlined, ierr = inlineSmallConst(g, f, target, ty, id);
                if ierr != squid_direct_types::Error.none { return neverVal(), ierr; }
                if was_inlined {
                    g.recordInlined(target.unit, target.binding);
                    return inlined, squid_direct_types::Error.none;
                }
            }
        }
        // A constant: its instance computes the value.
        let instance, error = g.namedWith(target, ty, unused, m, id, evidenceContext(g, f, target, id));
        if error != squid_direct_types::Error.none { return neverVal(), error; }
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
    if ty <= squid_check_types::never { return true; }
    if depth > 64 { return false; }
    let m .= g.units[f.unit - 1];
    let n = m.types.node(ty);
    match n.tag {
        variable => {
            let bound, present = g.types.envGet(f.env, m.unit, ty);
            if present { return true; }
            if !g.isQuantified(m, ty) { return true; }
            let instance = g.s.instances[f.instance_id];
            if !instance.unused_holes || instance.key.kind != squid_direct_emit::InstanceKind.named || instance.key.unit != m.unit { return false; }
            for variable in m.types.list(m.binding(instance.key.id).scheme.variables) { if variable == ty { return true; } }
            return false;
        },
        bound, rigid => {
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
    if ty <= squid_check_types::never || depth > 64 { return; }
    let m .= g.units[f.unit - 1];
    let n = m.types.node(ty);
    match n.tag {
        variable => { g.types.envBind(f.env, m.unit, ty, squid_direct_types::unit); },
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
        function, array, packed, seq, ref, view, link, cell => { return true; },
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
            if error != squid_direct_types::Error.none { return false; }
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
    let key = InstanceKey { squid_direct_emit::InstanceKind.trap, f.unit, 0, squid_direct_types::unit, 0, 0 };
    var instance, present = g.find(key);
    if !present {
        let made, error = g.addInstanceWith(key, Env {}, g.saveTys([squid_direct_types::unit]), squid_direct_types::unit, true, Tys {}, g.units[f.unit - 1], id);
        if error != squid_direct_types::Error.none { return neverVal(), error; }
        instance = made;
    }
    g.s.trap_closures += 1;
    return makeClosure(g, f, instance, ty, Vals {}, id);
}
// Pops a call result; a result that may refer to scope memory makes this body
// responsible for releasing it.
fn received(g: Generator&, f: Fn&, ty: Ty, id: u32) -> Val, Error {
    let holds, error = g.holdsMemory(ty);
    if error != squid_direct_types::Error.none { return neverVal(), error; }
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
    squid_direct_writer::uleb(out, owner_top);
    out.push(OP_local_set);
    squid_direct_writer::uleb(out, owner_mark);
    out.push(OP_global_get);
    squid_direct_writer::uleb(out, stack_pointer);
    out.push(OP_local_set);
    squid_direct_writer::uleb(out, stack_mark);
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
    let kind = localType(g, f, local_id);
    if kind == VT_f32 { return OP_f32_store; }
    if kind == VT_i64 { return OP_i64_store; }
    if kind == VT_f64 { return OP_f64_store; }
    return OP_i32_store;
}
fn loadOp(g: const Generator&, f: const Fn&, local_id: u32) -> u8 {
    let kind = localType(g, f, local_id);
    if kind == VT_f32 { return OP_f32_load; }
    if kind == VT_i64 { return OP_i64_load; }
    if kind == VT_f64 { return OP_f64_load; }
    return OP_i32_load;
}
// A closure over `captures`, invoking instance `instance` with them.
fn makeClosure(g: Generator&, f: Fn&, instance: u32, ty: Ty, captures: Vals, id: u32) -> Val, Error {
    let slot = g.s.instances[instance].slot;
    var bytes: u32 = 0;
    for at in 0..(captures.len as i64) {
        let capture = g.s.vals[captures.start + at];
        for index in 0..(capture.len as i64) {
            bytes += squid_direct_writer::wordBytes(localType(g, f, w(g, capture, index)));
        }
    }
    let result, error = fresh(g, f, ty, id);
    if error != squid_direct_types::Error.none { return result, error; }
    if g.s.parallel_readonly && squid_direct_emit::tryPatchSlot(g, slot) {
    } else {
        i32Const(g, slot);
    }
    opIndex(g, OP_local_set, w(g, result, 0));
    if bytes == 0 {
        i32Const(g, 0);
        opIndex(g, OP_local_set, w(g, result, 1));
        return result, squid_direct_types::Error.none;
    }
    let address = allocate(g, f, bytes);
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
            offset += squid_direct_writer::wordBytes(localType(g, f, word));
        }
    }
    opIndex(g, OP_local_get, address);
    opIndex(g, OP_local_set, w(g, result, 1));
    return result, squid_direct_types::Error.none;
}
// Loads a closure's captures from its environment parameter (local 0).
fn loadCaptures(g: Generator&, f: Fn&, captures: Tys, id: u32) -> Vals, Error {
    let out = g.reserveVals(captures.len);
    var offset: u32 = 0;
    for at in 0..(captures.len as i64) {
        let value, error = fresh(g, f, g.s.tys[captures.start + at], id);
        if error != squid_direct_types::Error.none { return out, error; }
        g.s.vals[out.start + at] = value;
        for index in 0..(value.len as i64) {
            let word = g.s.words[value.start + index];
            opIndex(g, OP_local_get, 0);
            op(g, loadOp(g, f, word));
            uleb(g, 2);
            uleb(g, offset);
            opIndex(g, OP_local_set, word);
            offset += squid_direct_writer::wordBytes(localType(g, f, word));
        }
    }
    return out, squid_direct_types::Error.none;
}

// A curried function value: `target` (a named function, primitive alias or
// constructor) applied to its first `arguments`.
fn partial(g: Generator&, f: Fn&, kind: InstanceKind, target: BindingRef, ty: Ty, arguments: Vals, id: u32) -> Val, Error {
    let full, error = curried(g, arguments, ty);
    if error != squid_direct_types::Error.none { return neverVal(), error; }
    let instance, error = adapter(g, f, kind, target, full, arguments.len, id);
    if error != squid_direct_types::Error.none { return neverVal(), error; }
    let res, merr = makeClosure(g, f, instance, ty, arguments, id);
    if merr != squid_direct_types::Error.none { return res, merr; }
    if (kind == squid_direct_emit::InstanceKind.partial || kind == squid_direct_emit::InstanceKind.primitive) &&
        arguments.len <= 4 && f.evidence_context == 0 {
        var ok = true;
        var kc = KnownClosure {
            fn_local: w(g, res, 0),
            env_local: w(g, res, 1),
            kind: if kind == squid_direct_emit::InstanceKind.partial { 1 } else { 3 },
            unit: target.unit,
            id: target.binding,
            instance_id: instance,
            full_ty: full,
            cap_count: arguments.len as u8,
            depth: f.depth,
        };
        for at in 0..(arguments.len as i64) {
            let av = g.s.vals[arguments.start + at];
            if tagOf(g, av.ty) == squid_direct_types::Tag.cell { ok = false; break; }
            kc.caps[at] = av;
        }
        if ok { recordKnownClosure(f, kc); }
    }
    return res, squid_direct_types::Error.none;
}
// The closure taking argument `count` of `target` at function type `full`.
fn adapter(g: Generator&, f: const Fn&, kind: InstanceKind, target: BindingRef, full: Ty, count: i64, id: u32) -> u32, Error {
    let m .= g.units[f.unit - 1];
    var evidence_context: u32 = 0;
    if kind == squid_direct_emit::InstanceKind.partial { evidence_context = evidenceContext(g, f, target, id); }
    let key = InstanceKey { kind, target.unit, target.binding, full, count as u32, evidence_context };
    let found, present = g.find(key);
    if present { return found, squid_direct_types::Error.none; }
    let captures = Tys { g.s.tys.len as u32, count as u32 };
    var rest = full;
    for step in 0..count {
        let arrow = g.types.node(rest);
        if arrow.tag != squid_direct_types::Tag.function { return 0, g.fail(m, id, "partial application beyond the function's arity"); }
        g.s.tys.push(arrow.a);
        rest = arrow.b;
    }
    let arrow = g.types.node(rest);
    if arrow.tag != squid_direct_types::Tag.function { return 0, g.fail(m, id, "function value of a non-function type"); }
    let parameters = g.saveTys([arrow.a]);
    if g.s.parallel_readonly {
        return g.addParallelPartial(key, parameters, arrow.b, captures, m.unit), squid_direct_types::Error.none;
    }
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
            if arguments.len < parameters.len { return partial(g, f, squid_direct_emit::InstanceKind.partial, target, result, arguments, 0); }
            return callTarget(g, f, target, arguments, key.ty, result, 0);
        },
        primitive => {
            var primitive = squid_check_core::Primitive { kind: squid_check_core::PrimitiveKind.scalar, arity: 0 };
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
            if tagOf(g, argument.ty) == squid_direct_types::Tag.tuple && constructor.payload != 0 && tm.types.node(constructor.payload).tag == squid_check_types::Tag.record && tm.types.node(constructor.payload).b > 1 {
                let cases, error = g.types.variants(result);
                if error != squid_direct_types::Error.none { return neverVal(), g.typeFailure(tm, 0); }
                let position, error = variantPosition(g, f, cases, constructor.tag, 0);
                if error != squid_direct_types::Error.none { return neverVal(), error; }
                let payload = g.types.variant_payloads[cases.payloads + position];
                if tagOf(g, payload) == squid_direct_types::Tag.record {
                    let declared, error = declaredRecord(g, f, tm, argument, payload, constructor.payload);
                    if error != squid_direct_types::Error.none { return neverVal(), error; }
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
    if error != squid_direct_types::Error.none { return inferredClosure(g, f, id); }
    let arrow = g.types.node(ty);
    if arrow.tag != squid_direct_types::Tag.function { return neverVal(), g.fail(m, id, "closure of a non-function type"); }
    let capture_ids = m.closureCaptures(id);
    let captures = g.reserveVals(capture_ids.len);
    for binding, at in capture_ids {
        let value, error = captureValue(g, f, binding, id);
        if error != squid_direct_types::Error.none { return neverVal(), error; }
        g.s.vals[captures.start + at] = value;
    }
    let key = InstanceKey { squid_direct_emit::InstanceKind.lambda, m.unit, id, ty, f.instance_id, f.evidence_context };
    var instance, present = g.find(key);
    if !present {
        let next_instance = g.s.instances.len as u32;
        for binding in capture_ids {
            let _, bound_here = bindGet(g, f, binding);
            if bound_here { continue; }
            let init_node, is_poly = g.s.polymorphic.get(polyKey(f, binding));
            if is_poly && m.node(init_node).tag == squid_check_core::Tag.closure {
                if g.s.parallel_readonly { g.s.parallel_aborted = true; return neverVal(), squid_direct_types::Error.unsupported; }
                recordPolyCapture(g, f, next_instance, binding, init_node, 0);
            }
        }
        let capture_types = Tys { g.s.tys.len as u32, captures.len };
        for at in 0..(captures.len as i64) { g.s.tys.push(g.s.vals[captures.start + at].ty); }
        let parameters = g.saveTys([arrow.a]);
        if g.s.parallel_readonly {
            if m.unit != g.s.instances[f.instance_id].key.unit {
                g.s.parallel_aborted = true;
                return neverVal(), squid_direct_types::Error.unsupported;
            }
            instance = g.addParallelLambda(key, f.env, g.s.instances[f.instance_id].env.head, parameters, arrow.b, capture_types, m.unit);
        } else {
            let made, error = g.addInstanceWith(key, f.env, parameters, arrow.b, true, capture_types, m, id);
            if error != squid_direct_types::Error.none { return neverVal(), error; }
            instance = made;
        }
    }
    let res, merr = makeClosure(g, f, instance, ty, captures, id);
    if merr != squid_direct_types::Error.none { return res, merr; }
    if capture_ids.len <= 4 && f.evidence_context == 0 {
        var ok = true;
        var kc = KnownClosure {
            fn_local: w(g, res, 0),
            env_local: w(g, res, 1),
            kind: 2,
            unit: m.unit,
            id: id,
            instance_id: instance,
            full_ty: ty,
            cap_count: capture_ids.len as u8,
            lambda_env: f.env,
            depth: f.depth,
        };
        for binding, at in capture_ids {
            let _, bound_here = bindGet(g, f, binding);
            let cv = g.s.vals[captures.start + at];
            if !bound_here || tagOf(g, cv.ty) == squid_direct_types::Tag.cell { ok = false; break; }
            kc.caps[at] = cv;
            kc.cap_bindings[at] = binding;
        }
        if ok { recordKnownClosure(f, kc); }
    }
    return res, squid_direct_types::Error.none;
}

// A lambda whose parameter type is known but whose result only its body
// determines: its instance is emitted now to learn the result.
recursive fn inferredClosure(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let info = m.closure(id);
    let parameter, error = lower(g, f, info.parameter.ty, id);
    if error != squid_direct_types::Error.none { return neverVal(), error; }
    let capture_ids = m.closureCaptures(id);
    let captures = g.reserveVals(capture_ids.len);
    for binding, at in capture_ids {
        let value, error = captureValue(g, f, binding, id);
        if error != squid_direct_types::Error.none { return neverVal(), error; }
        g.s.vals[captures.start + at] = value;
    }
    let marker, error = g.types.function(parameter, squid_direct_types::never);
    if error != squid_direct_types::Error.none { return neverVal(), error; }
    let key = InstanceKey { squid_direct_emit::InstanceKind.lambda, m.unit, id, marker, f.instance_id, f.evidence_context };
    var instance, present = g.find(key);
    if !present {
        let next_instance = g.s.instances.len as u32;
        for binding in capture_ids {
            let _, bound_here = bindGet(g, f, binding);
            if bound_here { continue; }
            let init_node, is_poly = g.s.polymorphic.get(polyKey(f, binding));
            if is_poly && m.node(init_node).tag == squid_check_core::Tag.closure {
                recordPolyCapture(g, f, next_instance, binding, init_node, 0);
            }
        }
        let capture_types = Tys { g.s.tys.len as u32, captures.len };
        for at in 0..(captures.len as i64) { g.s.tys.push(g.s.vals[captures.start + at].ty); }
        let parameters = g.saveTys([parameter]);
        let made, error = g.inferClosure(key, f.env, parameters, capture_types, m, id);
        if error != squid_direct_types::Error.none { return neverVal(), error; }
        instance = made;
    }
    let ty, error = g.types.function(parameter, g.s.instances[instance].result);
    if error != squid_direct_types::Error.none { return neverVal(), error; }
    refine(g, f, m.typeOf(id), ty);
    return makeClosure(g, f, instance, ty, captures, id);
}
// An effect operation as a function value: a closure over its trampoline,
// which finds the newest provider frame for it.
fn operationValue(g: Generator&, f: Fn&, id: u32) -> Val, Error {
    let m .= g.units[f.unit - 1];
    let info = m.operationValue(id);
    let operation, error = operationType(g, f, info.identity, m.operationValueArguments(id), id);
    if error != squid_direct_types::Error.none { return neverVal(), error; }
    let signature, error = lower(g, f, info.signature, id);
    if error != squid_direct_types::Error.none { return neverVal(), error; }
    let arrow = g.types.node(signature);
    if arrow.tag != squid_direct_types::Tag.function { return neverVal(), g.fail(m, id, "operation of a non-function type"); }
    let operation_id = g.operationId(operation);
    let key = InstanceKey { squid_direct_emit::InstanceKind.operation, 0, operation_id, signature, 0, 0 };
    var instance, present = g.find(key);
    if !present {
        let made, error = g.addInstanceWith(key, Env {}, g.saveTys([arrow.a]), arrow.b, true, Tys {}, m, id);
        if error != squid_direct_types::Error.none { return neverVal(), error; }
        instance = made;
    }
    return makeClosure(g, f, instance, signature, Vals {}, id);
}
// The lowered nominal type naming an effect operation and its arguments, as a
// provider's type names it.
fn operationType(g: Generator&, f: Fn&, identity: squid_check_types::NominalIdentity, arguments: const TId[:], id: u32) -> Ty, Error {
    let payload = squid_direct_emit::Words { g.s.words.len as u32, (arguments.len + 2) as u32 };
    g.s.words.push(identity.unit);
    g.s.words.push(identity.decl);
    for argument in arguments { g.s.words.push(0); }
    for argument, at in arguments {
        let lowered, error = lower(g, f, argument, id);
        if error != squid_direct_types::Error.none { return 0, error; }
        g.s.words[payload.start + 2 + at] = lowered;
    }
    return g.types.intern(squid_direct_types::Tag.nominal, g.s.words[payload.start..payload.start + payload.len]);
}
